#!/usr/bin/env python3
"""Loopback-only Linux/amd64 data-plane check for the six NoBrand v4.3 profiles.

Run as an ordinary user with the official release assets already downloaded:
  python3 tests/helpers/probe_protocols_v43.py --artifacts DIR --sing-box-archive FILE
The independent sing-box v1.14.1 client lives only in a temporary directory.
Optional outer isolation: run in a private network namespace with lo up.
"""
import argparse
import base64
from contextlib import contextmanager
import errno
import json
import os
from pathlib import Path
import platform
import shutil
import socket
import socketserver
import subprocess
import sys
import tarfile
import tempfile
import threading
import time
from types import SimpleNamespace
from unittest.mock import patch

import socks5_probe as socks
from splicore_native_probe import Supervisor, sc, stop, vacant

HOST = '127.0.0.1'
# https://github.com/ike-sh/Splicore/releases/tag/v0.6.7
CORE = 'b650e29c13752c83d3a72d346dc73ae0844fcf16953f3811d5abb05f174403b8'
COMMIT = 'a5ecdc5785fbcf978534046517d1692613d91706'
# https://github.com/SagerNet/sing-box/releases/download/v1.14.1/sing-box-1.14.1-linux-amd64.tar.gz
CLIENT_ARCHIVE = '12cb2816b52febb356f6a885b740cc8758c3f30b8ae0ca8edba80f0d2d35343f'
CLIENT = '9334a1c1fe97234911afaedd37226667ebdb3dab2abe383f2c4ae1387706dad9'
CASES = {**{f'snell-v{v}': ('snell', v) for v in (4, 5, 6)}, **{
    method: ('ss2022', '2022-blake3-' + method)
    for method in ('aes-128-gcm', 'aes-256-gcm', 'chacha20-poly1305')}}
TCP_BYTES, UDP_SIZES = 32768, (64, 512, 1200)


class CheckFailed(Exception):
    """Only static, credential-free assertions may be exposed to callers."""


def need(ok, message):
    if not ok:
        raise CheckFailed(message)


def extract_client(archive, work):
    need(sc.sha(archive) == CLIENT_ARCHIVE, 'independent client archive digest mismatch')
    binary = work / 'sing-box'
    with tarfile.open(archive, 'r:gz') as stream:
        item = stream.getmember('sing-box-1.14.1-linux-amd64/sing-box')
        need(item.isfile(), 'client executable is not a regular file')
        with stream.extractfile(item) as src, binary.open('xb') as dst:
            shutil.copyfileobj(src, dst)
    binary.chmod(0o700)
    need(sc.sha(binary) == CLIENT, 'independent client executable digest mismatch')
    version = subprocess.check_output([binary, 'version'], stderr=subprocess.DEVNULL, timeout=10)
    need(b'sing-box version 1.14.1\n' in version and b'linux/amd64' in version, 'independent client identity mismatch')
    return binary


@contextmanager
def destinations():
    """Count actual target-side accepts/bytes/datagrams; a local SOCKS ACK is not a pass."""
    counts = dict(tcp_accepts=0, tcp_bytes=0, udp_datagrams=0, udp_bytes=0)
    lock = threading.Lock()

    def add(**changes):
        with lock:
            for key, value in changes.items():
                counts[key] += value

    def snapshot():
        with lock:
            return counts.copy()

    class TCP(socketserver.BaseRequestHandler):
        def handle(self):
            add(tcp_accepts=1)
            try:
                while block := self.request.recv(65536):
                    add(tcp_bytes=len(block))
                    self.request.sendall(block)
            except OSError:
                pass

    class UDP(socketserver.BaseRequestHandler):
        def handle(self):
            block, stream = self.request
            add(udp_datagrams=1, udp_bytes=len(block))
            stream.sendto(block, self.client_address)

    with socketserver.ThreadingTCPServer((HOST, 0), TCP) as tcp, socketserver.ThreadingUDPServer((HOST, 0), UDP) as udp:
        servers = (tcp, udp)
        threads = [threading.Thread(target=s.serve_forever, args=(0.05,), daemon=True) for s in servers]
        for server, worker in zip(servers, threads):
            server.daemon_threads = True
            worker.start()
        try:
            yield tcp.server_address[1], udp.server_address[1], snapshot
        finally:
            for server, worker in zip(servers, threads):
                server.shutdown()
                worker.join()


@contextmanager
def test_client(work, binary, outbound):
    # Only the SOCKS frontend and final route are added to the unmodified NoBrand outbound.
    port = vacant()
    profile = {'log': {'disabled': True}, 'inbounds': [{'type': 'socks', 'tag': 'probe', 'listen': HOST,
               'listen_port': port}], 'outbounds': [outbound], 'route': {'final': outbound['tag']}}
    with tempfile.TemporaryDirectory(dir=work) as tmp:
        config = Path(tmp) / 'config.json'
        config.write_text(json.dumps(profile))
        validate = subprocess.run([binary, 'check', '-c', config], cwd=tmp, stdout=subprocess.DEVNULL,
                                  stderr=subprocess.DEVNULL, timeout=10)
        need(validate.returncode == 0, 'independent client rejected exported configuration')
        child = subprocess.Popen([binary, 'run', '-c', config], cwd=tmp, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        try:
            end = time.monotonic() + 8
            while True:
                need(child.poll() is None, 'independent client exited before SOCKS readiness')
                try:
                    with socket.create_connection((HOST, port), .2) as s:
                        socks.socks_greeting(s)
                    break
                except OSError:
                    need(time.monotonic() < end, 'independent client SOCKS readiness timeout')
                    time.sleep(.05)
            yield port
            need(child.poll() is None, 'independent client exited during data test')
        finally:
            stop(child)


def delta(current, before):
    return {k: current[k] - v for k, v in before.items()}


def exchange(work, client, profile, targets, positive, *, udp_positive=None):
    tcp_port, udp_port, snapshot = targets
    before = snapshot()
    results = {}
    if udp_positive is None:
        udp_positive = positive
    with test_client(work, client, profile) as proxy:
        args = SimpleNamespace(proxy_host=HOST, proxy_port=proxy, target_host=HOST, size=TCP_BYTES, sizes=UDP_SIZES)
        for name, fn, target, allowed in (('tcp', socks.tcp_probe, tcp_port, positive),
                                          ('udp', socks.udp_probe, udp_port, udp_positive)):
            args.target_port, args.timeout = target, (4 if allowed else 2)
            try:
                fn(args)
            except (OSError, RuntimeError) as exc:
                need(not allowed, 'positive ' + name + ' echo did not match')
                results[name] = 'timeout/no echo' if isinstance(exc, TimeoutError) else 'no usable echo'
            else:
                need(allowed, 'unexpected forwarding of ' + name + ' payload')
                results[name] = 'byte-identical echo'
    received = delta(snapshot(), before)
    expected = dict(tcp_accepts=int(positive), tcp_bytes=TCP_BYTES if positive else 0,
                    udp_datagrams=len(UDP_SIZES) if udp_positive else 0, udp_bytes=sum(UDP_SIZES) if udp_positive else 0)
    need(received == expected, 'target counts differ from expected data delivery')
    return dict(results, target=received)


def bindable(port, kind):
    with socket.socket(type=kind) as sock:
        if kind == socket.SOCK_STREAM:
            # Ignore closed TIME_WAIT sockets, never a live listener.
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        try:
            sock.bind((HOST, port))
            if kind == socket.SOCK_STREAM:
                sock.listen(1)
        except OSError as exc:
            if exc.errno == errno.EADDRINUSE:
                return False
            raise
        return True


def reject_invalid_material(runtime, work):
    # Exercise the official validator itself; suppress its credential-bearing input/output.
    checks = 0
    binary = runtime.current.resolve() / 'splicore'
    for name, protocol, original in sc.render(runtime.desired()):
        path = work / 'validator-input.json'
        args = [binary, 'inbound', 'validate', '--protocol', protocol, '--file', path]
        sc.save(path, original)
        need(sc.command(args, ok=False).returncode == 0, 'native credential control failed')
        if protocol == 'snell':
            invalid = dict(original, psk='short')
        elif protocol == 'shadowsocks':
            invalid = dict(original, users=[dict(original['users'][0], key=base64.b64encode(os.urandom(15)).decode())])
        else:
            raise CheckFailed('unexpected protocol in isolated validation graph')
        sc.save(path, invalid)
        need(sc.command(args, ok=False).returncode != 0, 'native validator accepted invalid credential length')
        checks += 1
    return checks


def assert_live_binary(runtime, supervisor):
    path = runtime.current.resolve() / 'splicore'
    live = Path(f'/proc/{supervisor.child.pid}/exe')
    need(supervisor.child.poll() is None and live.samefile(path) and sc.sha(live) == CORE,
         'running service is not the official release executable')


def lifecycle(work, runtime, supervisor, client, targets, artifacts, report):
    name = 'aes-128-gcm'
    tx = report['aes128_lifecycle'] = {}

    def export():
        with patch.dict(os.environ, {'NOBRAND_SPLICORE_EXPORT_FORMAT': 'sing-box'}):
            return runtime.protocol('ss2022', 'export', name)

    report['stage'] = 'AES-128 post-apply failure / rollback'
    original = runtime.current.resolve()
    original_export = export()
    original_map = sc.load(original / 'resource-map.json')
    original_graph = runtime.desired()['nodes']
    original_master = (original / 'runtime/master.key').read_bytes()
    candidate_port = vacant()
    apply = runtime.apply_documents

    def native_apply(*a, **kw):
        # Non-fixture deployment calls apply_documents directly, not Supervisor.verify.
        result = apply(*a, **kw)
        if runtime.adapter != 'fixture' and supervisor.fail:
            supervisor.fail = False
            raise sc.Failure('HEALTH', 'synthetic post-apply failure')
        return result

    supervisor.fail = True
    with patch.dict(os.environ, {'PORT': str(candidate_port)}), patch.object(runtime, 'apply_documents', native_apply):
        try:
            runtime.protocol('ss2022', 'set-port', name)
        except sc.Failure as exc:
            need(exc.category == 'HEALTH' and not supervisor.fail, 'wrong failure or candidate never reached post-apply stage')
        else:
            raise CheckFailed('post-apply fault did not abort port change')
    need(sc.load(runtime.transaction)['phase'] == 'ROLLED_BACK' and runtime.current.resolve() == original,
         'failed change did not restore the original generation')
    need(export() == original_export and runtime.desired()['nodes'] == original_graph,
         'old endpoint/credentials not restored')
    need(all(bindable(candidate_port, t) for t in (socket.SOCK_STREAM, socket.SOCK_DGRAM)),
         'failed candidate retained a port')
    tx['post_apply_rollback_original_data'] = exchange(work, client, original_export, targets, True)

    report['stage'] = 'AES-128 standalone backup'
    archive = work / 'standalone-backup.tar.gz'
    runtime.backup(archive)
    need(archive.stat().st_mode & 0o777 == 0o600, 'backup is not private')
    with tarfile.open(archive, 'r:gz') as backup:
        names = set(backup.getnames())
        need({'runtime/master.key', 'runtime/state.db', 'runtime/state.db.witness', 'desired.json'} <= names and
             'runtime/state.db.witness.pending' not in names, 'backup lacks a committed DB/witness pair')
    report['stage'] = 'AES-128 rotate and retire old key'
    runtime.protocol('ss2022', 'rotate-key', name)
    rotated = export()
    need(rotated['password'] != original_export['password'] and rotated['server_port'] == original_export['server_port'],
         'rotation did not replace the key on the same port')
    tx['rotated_key_works'] = exchange(work, client, rotated, targets, True)
    tx['old_key_denied_after_rotation'] = exchange(work, client, original_export, targets, False)
    report['stage'] = 'AES-128 remove then restore standalone backup'
    runtime.protocol('ss2022', 'remove', name)
    need(all(bindable(original_export['server_port'], t) for t in (socket.SOCK_STREAM, socket.SOCK_DGRAM)),
         'pre-restore removal retained a listener')
    runtime.restore(archive, artifacts=artifacts)
    restored = runtime.current.resolve()
    need(export() == original_export and (restored / 'runtime/master.key').read_bytes() == original_master and
         runtime.desired()['nodes'] == original_graph, 'restore did not bring back original keys/endpoints/nodes')
    if runtime.adapter != 'fixture':
        need(sc.load(restored / 'resource-map.json') == original_map, 'restore did not preserve native resource IDs')
        tx['storage_path'] = 'native DB/witness restore; native resource IDs preserved'
    else:
        tx['storage_path'] = 'fixture restore rebuilds from backed-up desired graph; NOT a native DB restore'
    assert_live_binary(runtime, supervisor)
    tx['restored_original_key_works'] = exchange(work, client, original_export, targets, True)
    tx['rotated_key_denied_after_restore'] = exchange(work, client, rotated, targets, False)
    report['stage'] = 'AES-128 TCP-only UDP off'
    with patch.dict(os.environ, {'SS2022_UDP': 'off'}):
        runtime.protocol('ss2022', 'set-udp', name)
    disabled = export()
    port = original_export['server_port']
    need(disabled == dict(original_export, network='tcp'), 'UDP off export changed more than the network')
    need(not bindable(port, socket.SOCK_STREAM) and bindable(port, socket.SOCK_DGRAM), 'UDP off did not free the UDP listener')
    tx['udp_off_export'] = exchange(work, client, disabled, targets, True, udp_positive=False)
    # The original client still supports UDP; no receiver exists at the managed server port.
    tx['udp_off_capable_client'] = exchange(work, client, original_export, targets, True, udp_positive=False)
    tx['udp_off_listener_rebind'] = ['udp']
    print('[PASS] UDP off keeps TCP echo, releases the UDP listener, and drops UDP even from a UDP-capable client.', flush=True)
    print('[PASS] AES-128 candidate failure rollback, backup/rotate/remove/restore and post-restore key isolation:',
          tx['storage_path'], flush=True)


def probe(args, report):
    need(platform.system() == 'Linux' and platform.machine() in ('amd64', 'x86_64'), 'Linux amd64 required')
    need(sc.RELEASE['version'] == 'v0.6.7' and sc.RELEASE['commit'] == COMMIT, 'manager release pin mismatch')
    if args.native_storage:
        # Never require or accept host root for this optional production-path test.
        mapping = Path('/proc/self/uid_map').read_text().split()
        need(os.geteuid() == 0 and len(mapping) == 3 and mapping[0] == '0' and int(mapping[1]) > 0 and mapping[2] == '1',
             '--native-storage requires an unprivileged single-UID user namespace mapped to root')
        need([n for _, n in socket.if_nameindex()] == ['lo'], '--native-storage requires a private, lo-only network namespace')
    os.umask(0o077)
    with tempfile.TemporaryDirectory(prefix='w43-', dir='/tmp') as tmp, destinations() as targets:
        work = Path(tmp)
        client = extract_client(args.sing_box_archive, work)
        args.artifacts = args.artifacts.resolve()
        environment = {'PATH': os.defpath + ':/usr/local/bin:/usr/sbin:/sbin', 'HOME': str(work), 'LANG': 'C',
                       'NOBRAND_SYSTEM_ROOT': tmp, 'NOBRAND_STATE_DIR': str(work / 's'), 'NOBRAND_CONFIG_DIR': str(work / 'c'),
                       'NOBRAND_LIB_DIR': str(work / 'l'), 'NOBRAND_LIFECYCLE_DIR': str(work / 'j'),
                       'NOBRAND_LIFECYCLE_LOCK_FILE': str(work / 'lock'), 'NOBRAND_SPLICORE_FIXTURE': '1',
                       'NOBRAND_SPLICORE_UNIT': str(work / 'probe.service'),
                       'NOBRAND_SPLICORE_LISTEN': HOST, 'ADVERTISE_HOST': HOST, 'ADVERTISE_PORT': ''}
        with patch.dict(os.environ, environment, clear=True), (work / 'private.log').open('wb') as log:
            marker = work / 'driver'
            marker.touch()
            runtime = sc.Runtime(adapter='systemd' if args.native_storage else 'fixture', fixture=marker)
            supervisor = Supervisor(runtime, log)
            ports = {}
            cases = args.case or list(CASES)
            try:
                with patch.object(sc.Service, 'call', lambda service, *a, **kw: supervisor.call(service, *a, **kw)), \
                     patch.object(runtime, 'firewall'):
                    for name in cases:
                        kind, spec = CASES[name]
                        report['stage'] = 'manager install ' + name
                        port = vacant()
                        env = {'SNELL_VERSION': str(spec), 'SNELL_QUIC_PROXY': 'off'} if kind == 'snell' else {
                            'SS2022_METHOD': spec, 'SS2022_UDP': 'on'}
                        with patch.dict(os.environ, dict(env, PORT=str(port))):
                            runtime.protocol(kind, 'install', name, args.artifacts if not ports else None)
                        ports[name] = port
                    assert_live_binary(runtime, supervisor)
                    report['invalid_creation_credentials_rejected'] = reject_invalid_material(runtime, work)
                    report['healthy_together'] = runtime.health(runtime.current.resolve())['inbound_count']
                    need(report['healthy_together'] == len(cases), 'native health count mismatch')
                    for name in cases:
                        kind, spec = CASES[name]
                        port = ports[name]
                        expect_udp_listener = kind == 'ss2022' or spec == 5
                        row = report['profiles'][name] = {}
                        report['stage'] = 'listener/export ' + name
                        need(not bindable(port, socket.SOCK_STREAM) and
                             bindable(port, socket.SOCK_DGRAM) != expect_udp_listener, 'live port ownership mismatch')
                        row['bound_transports'] = ['tcp', 'udp'] if expect_udp_listener else ['tcp']
                        with patch.dict(os.environ, {'NOBRAND_SPLICORE_EXPORT_FORMAT': 'sing-box'}):
                            profile = runtime.protocol(kind, 'export', name)
                        need(profile['server'] == HOST and profile['server_port'] == port, 'wrong exported listener')
                        if kind == 'snell':
                            need(profile['type'] == 'snell' and profile['version'] == (4 if spec == 5 else spec),
                                 'wrong exported Snell wire version')
                            row['client_wire_version'] = profile['version']
                            field = 'psk'
                            original = profile[field]
                            wrong = ('B' if original[0] == 'A' else 'A') + original[1:]
                        else:
                            need(profile['type'] == 'shadowsocks' and profile['method'] == spec, 'wrong exported SS method')
                            row['method'] = profile['method']
                            field = 'password'
                            key = bytearray(base64.b64decode(profile[field], validate=True))
                            need(len(key) == (16 if 'aes-128' in spec else 32), 'wrong exported SS key length')
                            key[0] ^= 1
                            wrong = base64.b64encode(key).decode('ascii')
                        for phase in ('correct', 'wrong', 'recovery'):
                            report['stage'] = phase + ' credential ' + name
                            row[phase] = exchange(work, client, dict(profile, **{field: wrong}) if phase == 'wrong' else profile,
                                                  targets, phase != 'wrong')
                        print('[PASS]', name, 'TCP/ordinary UDP; wrong credential did not reach either target; recovery', flush=True)
                    if 'aes-128-gcm' in cases:
                        lifecycle(work, runtime, supervisor, client, targets, args.artifacts, report)
                    for name in cases:
                        report['stage'] = 'manager remove/rebind ' + name
                        runtime.protocol(CASES[name][0], 'remove', name)
                        need(not runtime.protocol(CASES[name][0], 'status', name)['nodes'], 'removed node still registered')
                        need(all(bindable(ports[name], kind) for kind in (socket.SOCK_STREAM, socket.SOCK_DGRAM)),
                             'removed listener port not rebindable')
                        report['profiles'][name]['after_remove_rebind'] = ['tcp', 'udp']
                    need(runtime.health(runtime.current.resolve())['inbound_count'] == 0, 'native inbounds remain after removal')
                    report['after_remove_healthy_inbounds'] = 0
                    print('[PASS] Every removed port can be rebound on both transports; no managed inbound remains.', flush=True)
            finally:
                stop(supervisor.child)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--artifacts', required=True, type=Path)
    parser.add_argument('--sing-box-archive', required=True, type=Path)
    parser.add_argument('--output', type=Path, help='write only public identities, stage, counts and result')
    parser.add_argument('--native-storage', action='store_true', help='test production DB/witness restore in an unprivileged, private user/net namespace')
    parser.add_argument('--case', action='append', choices=CASES, help='select a subset (default: all six)')
    args = parser.parse_args()
    report = dict(result='FAIL', stage='preflight', core='v0.6.7', commit=COMMIT, core_sha256=CORE,
                  client='SagerNet/sing-box v1.14.1', client_archive_sha256=CLIENT_ARCHIVE, linux=platform.release(),
                  machine=platform.machine(), scope='IPv4 loopback; test supervisor; no host init/firewall or QUIC qualification',
                  tcp_bytes=TCP_BYTES, udp_packet_sizes=UDP_SIZES, profiles={})
    try:
        probe(args, report)
    except Exception as exc:
        # Suppress untrusted upstream diagnostics, exported profiles and private daemon logs.
        report['error'] = str(exc) if isinstance(exc, CheckFailed) else (exc.category if isinstance(exc, sc.Failure) else type(exc).__name__)
        print('[FAIL]', report['stage'] + ':', report['error'], file=sys.stderr)
    else:
        report.update(result='PASS', stage='complete')
    if args.output:
        args.output.write_text(json.dumps(report, indent=2) + '\n')
    return report['result'] != 'PASS'


if __name__ == '__main__':
    sys.exit(main())
