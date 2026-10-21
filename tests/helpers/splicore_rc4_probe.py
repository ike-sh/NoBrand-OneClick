#!/usr/bin/env python3
"""Public rc.4 fresh profiles and protected destination qualification.

Temporary loopback processes only. The supervisor substitutes host init calls;
artifact verification, desired renderer, native validation and rollback are real.
"""
import argparse
import copy
import gzip
import importlib.util
import json
import os
from pathlib import Path
import shutil
import socket
import socketserver
import ssl
import subprocess
import sys
import tempfile
import threading
import time
from types import SimpleNamespace
from unittest.mock import patch
import socks5_probe as socks

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('sc4', ROOT / 'runtime/splicore.py')
sc = importlib.util.module_from_spec(spec); spec.loader.exec_module(sc)
MIHOMO_SHA256 = 'cf06ce2c7d1421bdbda14ee4a5b6046672dc35ebf8eecd8e77504ec3c0ed9a84'


def check(condition, detail):
    if not condition: raise AssertionError(detail)


def vacant(kind=socket.SOCK_STREAM):
    with socket.socket(socket.AF_INET, kind) as listener:
        listener.bind(('127.0.0.1', 0)); return listener.getsockname()[1]


def stop(child):
    if child and child.poll() is None:
        child.terminate()
        try: child.wait(timeout=10)
        except subprocess.TimeoutExpired: child.kill(); child.wait(timeout=5)


class Supervisor:
    def __init__(self, runtime, log):
        self.runtime, self.log, self.child = runtime, log, None
        self.enabled, self.fail = False, False
        self.starts = 0

    def call(self, service, action, name='nobrand-splicore', ok=True):
        check(name == 'nobrand-splicore', 'unexpected core/service owner')
        if action == 'active': return self.child is not None and self.child.poll() is None
        if action == 'enabled': return self.enabled
        if action in ('enable', 'disable'): self.enabled = action == 'enable'
        elif action == 'stop': stop(self.child)
        elif action == 'start':
            check(not self.child or self.child.poll() is not None, 'duplicate active runtime')
            self.child = subprocess.Popen([sys.executable, str(service.generation / 'launch.py')], stdout=self.log, stderr=self.log)
            self.starts += 1
            deadline = time.monotonic() + 10
            while True:
                check(self.child.poll() is None, 'public daemon exited at startup')
                result = sc.command([service.generation / 'splicore', 'inbound', 'list', '--config', service.generation / 'bootstrap.yaml'], ok=False)
                if result.returncode == 0: break
                check(time.monotonic() < deadline, 'control socket timeout'); time.sleep(.05)
        elif action == 'verify':
            graph = sc.load(service.generation / 'desired.json')
            self.runtime.apply_documents(service.generation, sc.render(graph), service)
            if self.fail:
                self.fail = False
                raise sc.Failure('HEALTH', 'synthetic post-apply failure')
        elif action not in ('reload-manager', 'firewall-open', 'firewall-close'):
            raise AssertionError('unknown supervisor action')
        return True


class TCP(socketserver.BaseRequestHandler):
    def handle(self):
        try:
            while True:
                data = self.request.recv(65536)
                if not data: break
                self.request.sendall(data)
        except OSError: pass


class UDP(socketserver.BaseRequestHandler):
    def handle(self):
        data, stream = self.request; stream.sendto(data, self.client_address)


class Echo:
    def __enter__(self):
        self.tcp = socketserver.ThreadingTCPServer(('127.0.0.1', 0), TCP); self.tcp.daemon_threads = True
        self.udp = socketserver.ThreadingUDPServer(('127.0.0.1', 0), UDP); self.udp.daemon_threads = True
        for server in (self.tcp, self.udp): threading.Thread(target=server.serve_forever, daemon=True).start()
        return self
    def __exit__(self, *_args):
        for server in (self.tcp, self.udp): server.shutdown(); server.server_close()


def profile_config(fragment, name):
    proxies = fragment if fragment.startswith('proxies:\n') else 'proxies:\n' + '\n'.join('  ' + line for line in fragment.splitlines())
    return ('mixed-port: 7890\nallow-lan: false\nmode: rule\nlog-level: error\n' + proxies
            + '\nproxy-groups:\n  - name: NOBRAND\n    type: select\n    proxies: [' + json.dumps(name) + ']\nrules:\n  - MATCH,NOBRAND\n')


def traffic(work, client, log, echo, fragment, name, positive=True, udp=True):
    with tempfile.TemporaryDirectory(prefix='client-', dir=work) as directory:
        folder = Path(directory); port = vacant()
        config = folder / 'client.yaml'
        config.write_text(profile_config(fragment, name).replace('mixed-port: 7890', f'mixed-port: {port}'))
        child = subprocess.Popen([str(client), '-d', str(folder), '-f', str(config)], stdout=log, stderr=log)
        try:
            deadline = time.monotonic() + 10
            while True:
                check(child.poll() is None, 'client rejected exported profile')
                try:
                    with socket.create_connection(('127.0.0.1', port), .1): break
                except OSError:
                    check(time.monotonic() < deadline, 'client listener timeout'); time.sleep(.05)
            args = SimpleNamespace(proxy_host='127.0.0.1', proxy_port=port, target_host='localhost',
                target_port=echo.tcp.server_address[1], timeout=3, size=32768, sizes=[64, 512])
            passed = False
            for attempt in range(3 if positive else 1):
                try: socks.tcp_probe(args); passed = True; break
                except (OSError, RuntimeError):
                    if positive and attempt < 2: time.sleep(.2)
            check(passed == positive, 'exported profile TCP result differs')
            if positive and udp:
                args.target_port = echo.udp.server_address[1]; socks.udp_probe(args)
        finally: stop(child)


def tls_probe(port, sni):
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    context.check_hostname = False; context.verify_mode = ssl.CERT_NONE
    context.minimum_version = ssl.TLSVersion.TLSv1_3
    try:
        with socket.create_connection(('127.0.0.1', port), 3) as raw:
            with context.wrap_socket(raw, server_hostname=sni) as stream:
                stream.sendall(b'GET / HTTP/1.0\r\n\r\n'); return bool(stream.recv(4096))
    except (OSError, ssl.SSLError): return False


def raw_probe(port, payload):
    with socket.create_connection(('127.0.0.1', port), 3) as raw:
        raw.settimeout(4); raw.sendall(payload)
        try: return raw.recv(2048) == b''
        except (ConnectionResetError, BrokenPipeError): return True
        except socket.timeout: return False


def run(args):
    checks, trace = {}, []
    result = {'version': sc.RELEASE['version'], 'commit': sc.RELEASE['commit'], 'checks': checks,
              'scope': 'Linux amd64 temporary loopback; local process supervisor', 'download_trace': trace,
              'systemd': 'PENDING', 'openrc': 'PENDING', 'arm64': 'BUILD ONLY / runtime NOT CERTIFIED',
              'nftables_port_range': 'PENDING / NOT RUN', 'udp_payload_bytes': [64, 512]}
    def passed(name):
        checks[name] = 'PASS'; print(name + ': PASS', flush=True)
    os.umask(0o077)
    with tempfile.TemporaryDirectory(prefix='sc4-') as directory, Echo() as echo:
        work = Path(directory)
        check(sc.sha(args.mihomo_gzip) == MIHOMO_SHA256, 'reference client checksum')
        client = work / 'mihomo'
        with gzip.open(args.mihomo_gzip, 'rb') as source: sc.atomic(client, source.read(), 0o700)
        environment = {'NOBRAND_SYSTEM_ROOT': str(work), 'NOBRAND_STATE_DIR': str(work / 's'),
            'NOBRAND_CONFIG_DIR': str(work / 'c'), 'NOBRAND_LIB_DIR': str(work / 'l'),
            'NOBRAND_LIFECYCLE_DIR': str(work / 'j'), 'NOBRAND_LIFECYCLE_LOCK_FILE': str(work / 'lock'),
            'NOBRAND_SPLICORE_FIXTURE': '1', 'NOBRAND_SPLICORE_LISTEN': '127.0.0.1',
            'ADVERTISE_HOST': '127.0.0.1', 'ADVERTISE_PORT': ''}
        def download(url, destination, proxy=''):
            trace.append(url); shutil.copyfile(args.artifacts / url.rsplit('/', 1)[1], destination)
        with patch.dict(os.environ, environment), (work / 'fixture-driver').open('w') as driver:
            driver.write('not executed; service effects are isolated by Supervisor')
            runtime = sc.Runtime(adapter='fixture', fixture=work / 'fixture-driver')
            tls = runtime.certificate('cover', 'localhost')
            cover_port = vacant()
            log_path = args.private_log or work / 'process.log'
            with log_path.open('wb') as log:
                cover = subprocess.Popen(['openssl', 's_server', '-accept', '127.0.0.1:' + str(cover_port),
                    '-cert', tls['certificate_file'], '-key', tls['private_key_file'], '-tls1_3', '-alpn', 'h2,http/1.1', '-quiet', '-www'], stdout=log, stderr=log)
                supervisor = Supervisor(runtime, log)
                def call(service, *arguments, **kwargs): return supervisor.call(service, *arguments, **kwargs)
                try:
                    deadline = time.monotonic() + 10
                    while not tls_probe(cover_port, 'localhost'):
                        check(cover.poll() is None and time.monotonic() < deadline, 'cover TLS fixture unavailable'); time.sleep(.05)
                    with patch.object(sc.Service, 'call', call), patch.object(sc, 'download', download):
                        # All installs call the real fresh-install builder. Native
                        # validate is also exercised (fixture adapter normally skips only guard preflight).
                        for protocol, env in [
                            ('vless-reality', {'VLESS_REALITY_TARGET': 'localhost', 'VLESS_REALITY_TARGET_PORT': str(cover_port)}),
                            ('hysteria2', {'HY2_SNI': 'probe.example'}),
                            ('mieru', {'PROTOCOL': 'TCP', 'MTU': '1400', 'TRAFFIC_PATTERN': 'off', 'USERNAME': 'synthetic-user'}),
                            ('tuic', {'TUIC_SNI': 'probe.example', 'TUIC_USER': 'synthetic-user'}),
                            ('snell', {'SNELL_VERSION': '5'})]:
                            with patch.dict(os.environ, dict(env, PORT=str(vacant(socket.SOCK_DGRAM if protocol in ('hysteria2', 'tuic') else socket.SOCK_STREAM)))):
                                runtime.protocol(protocol, 'install', protocol)
                            passed('fresh_install_' + protocol)
                        graph = runtime.desired(); current = runtime.current.resolve()
                        # The production preflight uses the actual native Core API.
                        runtime.adapter = 'process'
                        try: runtime.validate(current, sc.render(graph))
                        finally: runtime.adapter = 'fixture'
                        passed('native_guard_pre_cutover_validation')
                        for phase in ('initial', 'restart', 'sigkill_recovery'):
                            if phase != 'initial':
                                service = sc.Service('fixture', current, work / 'fixture-driver')
                                if phase == 'restart': service.call('stop')
                                else: supervisor.child.kill(); supervisor.child.wait(timeout=5)
                                service.call('start'); runtime.wait_health(current)
                            for node in graph['nodes']:
                                profile = sc.client_profiles(node)
                                if node['protocol'] == 'tuic': profile = profile['profiles'][0]
                                name = 'NoBrand-Hysteria2' if node['protocol'] == 'hysteria2' else (
                                       'nobrand-tuic-synthetic-user' if node['protocol'] == 'tuic' else (
                                       'mieru-mita-tcp' if node['protocol'] == 'mieru' else ('snell' if node['protocol'] == 'snell' else 'vless-reality')))
                                traffic(work, client, log, echo, profile['mihomo'], name,
                                        udp=node['protocol'] in ('hysteria2', 'tuic', 'snell'))
                                passed(phase + '_profile_' + node['protocol'])
                        node = next(n for n in graph['nodes'] if n['protocol'] == 'vless-reality')
                        listener, guard_port = node['document']['listener']['port'], node['guard']['listen']['port']
                        profile = sc.client_profiles(node)['mihomo']
                        for name, mutate in [('wrong_uuid', lambda n: n['document']['users'][0].update(uuid='22222222-2222-4222-8222-222222222222')),
                                             ('wrong_short_id', lambda n: n['document']['settings']['reality'].update(short_ids=['deadbeef'])),
                                             ('wrong_sni', lambda n: n['document']['settings']['reality'].update(server_name='unapproved.example'))]:
                            bad = copy.deepcopy(node); mutate(bad)
                            traffic(work, client, log, echo, sc.client_profiles(bad)['mihomo'], 'vless-reality', positive=False, udp=False)
                            passed('reality_' + name + '_no_proxy')
                        check(tls_probe(listener, 'localhost'), 'approved plain TLS should reach fixed cover')
                        passed('reality_approved_plain_tls_fixed_cover')
                        check(not tls_probe(listener, 'unapproved.example'), 'wrong SNI cover forwarding')
                        passed('reality_wrong_sni_tls_rejected')
                        for destination, port in [('public', listener), ('guard', guard_port)]:
                            for name, payload in [('http', b'GET / HTTP/1.0\r\n\r\n'), ('random_tcp', b'\x00\x01random-data'),
                                                  ('malformed_tls', b'\x16\x03\x03\x00\x05hello')]:
                                check(raw_probe(port, payload), 'unsafe raw probe ' + name)
                                passed(destination + '_' + name + '_fail_closed')
                            check(not tls_probe(port, None), 'missing SNI accepted'); passed(destination + '_no_sni_fail_closed')
                        # Direct guard admission is exact; two approved visible
                        # names still share one fixed configured destination.
                        check(not tls_probe(guard_port, 'unapproved.example'), 'guard wrong SNI accepted')
                        passed('guard_no_arbitrary_sniffed_sni_forwarding')
                        hy2 = next(n for n in graph['nodes'] if n['protocol'] == 'hysteria2')
                        for name, mutate in [('wrong_auth', lambda n: n['document']['users'][0].update(password='synthetic-wrong-auth')),
                                             ('wrong_obfs', lambda n: n['document']['settings']['stream_transport']['hysteria']['obfs'].update(password='synthetic-wrong-obfs'))]:
                            bad = copy.deepcopy(hy2); mutate(bad)
                            traffic(work, client, log, echo, sc.client_profiles(bad)['mihomo'], 'NoBrand-Hysteria2', positive=False)
                            passed('hy2_' + name + '_rejected')
                        bad_pin = sc.client_profiles(hy2)['mihomo']
                        import re
                        bad_pin = re.sub(r'fingerprint: "[0-9a-f]+"', 'fingerprint: ' + json.dumps('0' * 64), bad_pin)
                        traffic(work, client, log, echo, bad_pin, 'NoBrand-Hysteria2', positive=False)
                        passed('hy2_wrong_certificate_pin_rejected')
                        old = current
                        supervisor.fail = True
                        bad = copy.deepcopy(graph); bad['nodes'][-1]['document']['settings']['version'] = 4
                        try: runtime.deploy(bad)
                        except sc.Failure: pass
                        else: raise AssertionError('injected candidate health failure accepted')
                        check(runtime.current.resolve() == old, 'config rollback pointer differs')
                        traffic(work, client, log, echo, sc.client_profiles(hy2)['mihomo'], 'NoBrand-Hysteria2')
                        traffic(work, client, log, echo, profile, 'vless-reality', udp=False)
                        passed('config_rollback_and_traffic')
                        starts = supervisor.starts
                        check(runtime.deploy(graph)['result'] == 'same-version-no-op', 'same version is not a no-op')
                        check(starts == supervisor.starts, 'same version restarted runtime'); passed('same_version_verify_noop')
                        check(len(trace) == 2 and all('/v0.3.0-rc.4/' in u for u in trace), 'unexpected runtime download')
                        passed('download_audit_splicore_rc4_only')
                        result['single_primary_runtime'] = 1
                        result['managed_inbounds'] = len(sc.render(graph))
                        result['native_local_guard_listeners'] = 1
                        result['snell'] = 'v5 server / rc.4 documented v4 client wire: TCP and UDP PASS'
                        runtime.uninstall(True); passed('new_architecture_uninstall_purge')
                finally: stop(supervisor.child); stop(cover)
    result['result'] = 'PASS'
    if args.output: sc.save(args.output, result)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--artifacts', required=True, type=Path)
    parser.add_argument('--mihomo-gzip', required=True, type=Path)
    parser.add_argument('--output', type=Path)
    parser.add_argument('--private-log', type=Path)
    args = parser.parse_args()
    run(args)

if __name__ == '__main__': main()
