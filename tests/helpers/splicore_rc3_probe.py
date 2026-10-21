#!/usr/bin/env python3
"""Public rc.3 local qualification. Never controls host services or nftables.

The fixture supervisor owns real loopback processes. Production artifact,
render, preflight, validation, transaction and rollback code runs unchanged.
REALITY native controls deliberately bypass the product's blocked policy gate.
"""
import argparse
import copy
import gzip
import hashlib
import json
import os
from pathlib import Path
import shutil
import socket
import socketserver
import subprocess
import sys
import tempfile
import threading
import time
from types import SimpleNamespace
from unittest.mock import patch

import splicore_blocker_probe as legacy
import splicore_rc2_probe as contract
from splicore_local_integration import sc
import socks5_probe as socks

ROOT = Path(__file__).resolve().parents[2]


class Checks(dict):
    def __setitem__(self, key, value):
        super().__setitem__(key, value)
        print(key + ': ' + str(value), file=sys.stderr, flush=True)


def check(condition, detail):
    if not condition:
        raise contract.Rejected(detail)


def expect_failure(callback, category=None):
    try:
        callback()
    except sc.Failure as exc:
        check(not category or exc.category == category, 'unexpected failure category')
        return
    raise contract.Rejected('expected rejection did not occur')


def environment(root):
    return {'NOBRAND_STATE_DIR': str(root / 'state'), 'NOBRAND_CONFIG_DIR': str(root / 'config'),
            'NOBRAND_LIB_DIR': str(root / 'lib'), 'NOBRAND_LIFECYCLE_DIR': str(root / 'journal'),
            'NOBRAND_LIFECYCLE_LOCK_FILE': str(root / 'guard'), 'NOBRAND_SPLICORE_FIXTURE': '1'}


class Supervisor:
    def __init__(self, runtime, log, xray=None, old_config=None):
        self.runtime, self.log = runtime, log
        self.xray, self.old_config = xray, old_config
        self.children, self.enabled = {}, {}
        self.fail_candidate = False
        self.all_children = []

    def start(self, name, generation):
        if name == 'nobrand-hysteria2':
            argv = [self.xray, 'run', '-c', self.old_config]
        else:
            argv = [sys.executable, generation / 'launch.py']
        child = subprocess.Popen([str(a) for a in argv], stdout=self.log, stderr=self.log)
        self.children[name] = child
        self.all_children.append(child)
        if name == 'nobrand-splicore':
            deadline = time.monotonic() + 10
            while time.monotonic() < deadline and child.poll() is None:
                result = sc.command([generation / 'splicore', 'inbound', 'list', '--config', generation / 'bootstrap.yaml'], ok=False)
                if result.returncode == 0:
                    return
                time.sleep(.05)
            raise sc.Failure('SERVICE_START', 'private daemon did not start')
        time.sleep(.3)
        check(child.poll() is None, 'legacy process did not start')

    def call(self, service, action, name='nobrand-splicore', ok=True):
        child = self.children.get(name)
        if action == 'active':
            return child is not None and child.poll() is None
        if action == 'enabled':
            return self.enabled.get(name, False)
        if action in ('enable', 'disable'):
            self.enabled[name] = action == 'enable'
        elif action == 'stop':
            legacy.stop(child)
        elif action == 'start':
            self.start(name, service.generation)
        elif action == 'verify':
            docs = sc.render(sc.load(service.generation / 'desired.json'))
            self.runtime.apply_documents(service.generation, docs, service)
            if self.fail_candidate:
                self.fail_candidate = False
                raise sc.Failure('HEALTH', 'injected failure after actual candidate apply')
        elif action not in ('reload-manager', 'firewall-open', 'firewall-close'):
            raise contract.Rejected('unknown fixture supervisor action')
        return True

    def close(self):
        for child in reversed(self.all_children):
            legacy.stop(child)


class TCP(socketserver.BaseRequestHandler):
    def handle(self):
        while True:
            data = self.request.recv(65536)
            if not data:
                break
            self.request.sendall(data)


class UDP(socketserver.BaseRequestHandler):
    def handle(self):
        data, stream = self.request
        stream.sendto(data, self.client_address)


class Echo:
    def __enter__(self):
        self.tcp = socketserver.ThreadingTCPServer(('127.0.0.1', 0), TCP)
        self.tcp.daemon_threads = True
        self.udp = socketserver.ThreadingUDPServer(('127.0.0.1', 0), UDP)
        self.udp.daemon_threads = True
        for server in (self.tcp, self.udp):
            threading.Thread(target=server.serve_forever, daemon=True).start()
        return self

    def __exit__(self, *_args):
        for server in (self.tcp, self.udp):
            server.shutdown()
            server.server_close()


def hy2_profile(fragment, name="NoBrand-Hysteria2"):
    proxies = fragment if fragment.startswith('proxies:\n') else 'proxies:\n' + '\n'.join('  ' + line for line in fragment.splitlines())
    return ('mixed-port: 7890\nallow-lan: false\nmode: rule\nlog-level: warning\n' + proxies +
            '\nproxy-groups:\n  - name: NOBRAND\n    type: select\n    proxies: [' + name + ']\nrules:\n  - MATCH,NOBRAND\n')


def traffic(work, client, log, echo, profile, positive=True, udp=True):
    with tempfile.TemporaryDirectory(prefix='client-', dir=work) as directory:
        folder = Path(directory)
        port = contract.vacant_port(socket.SOCK_STREAM)
        config = folder / 'config.yaml'
        config.write_text(profile.replace('mixed-port: 7890', f'mixed-port: {port}'))
        child = subprocess.Popen([str(client), '-d', str(folder), '-f', str(config)], stdout=log, stderr=log)
        try:
            legacy.wait_port(child, port)
            args = SimpleNamespace(proxy_host='127.0.0.1', proxy_port=port, target_host='localhost',
                                   target_port=echo.tcp.server_address[1], timeout=3, size=32768,
                                   sizes=[64, 512])
            passed = False
            for attempt in range(3 if positive else 1):
                try:
                    socks.tcp_probe(args)
                    passed = True
                    break
                except (OSError, RuntimeError):
                    if positive and attempt < 2:
                        time.sleep(.3)
            check(passed == positive, 'TCP old-profile traffic outcome differs')
            if positive and udp:
                args.target_port = echo.udp.server_address[1]
                socks.udp_probe(args)
        finally:
            legacy.stop(child)


def documents(runtime, tls, hy2=None):
    graph = sc.empty()
    for protocol in ('snell', 'mieru', 'hysteria2', 'tuic'):
        port = contract.vacant_port(socket.SOCK_STREAM if protocol in ('snell', 'mieru') else socket.SOCK_DGRAM)
        doc = {'schema': 1, 'listener': {'host': '127.0.0.1', 'port': port},
               'display_endpoint': {'host': '127.0.0.1', 'port': port}}
        if protocol == 'snell':
            doc.update(settings={'version': 5}, psk='synthetic-preserved-snell-psk')
        else:
            doc['users'] = [{'password': 'synthetic-preserved-password'}]
            if protocol == 'mieru':
                doc['users'][0]['username'] = 'synthetic-user'
                doc['settings'] = {'transport': 'tcp', 'mtu': 1400, 'multiplex': 'off'}
            elif protocol == 'hysteria2':
                doc['settings'] = {'tls': tls}
            else:
                doc['users'][0]['uuid'] = legacy.UUID
                doc['settings'] = {'tls': tls, 'version': 5, 'congestion_control': 'cubic',
                                   'udp_relay_mode': 'native', 'zero_rtt_handshake': False}
        graph['nodes'].append({'id': protocol, 'protocol': protocol, 'document': doc})
    if hy2:
        graph['nodes'].append(copy.deepcopy(hy2))
    return graph


def probe(args):
    check(sys.platform == 'linux' and sc.arch() == 'amd64', 'Linux amd64 required')
    check(os.geteuid() == 0, 'private old-state ownership fixture requires root; no host service mutations')
    release = sc.RELEASE
    checks, urls = Checks(), []
    all_supervisors = []
    result = {'version': release['version'], 'commit': release['commit'], 'checks': checks,
              'scope': 'temporary WSL Linux amd64 loopback; fixture supervisor with real public binaries',
              'migration_blockers_closed': False, 'artifacts': {}, 'download_trace': urls,
              'udp_qualified_payload_bytes': [64, 512],
              'udp_large_payload_limit': 'old Xray baseline 1200-byte echo integrity mismatch observed in WSL; not qualified'}
    with tempfile.TemporaryDirectory(prefix='sc3-') as directory, Echo() as echo:
        work = Path(directory)
        for architecture, entry in release['assets'].items():
            archive = args.artifacts / entry['name']
            sc.inspect_archive(archive, entry, (args.artifacts / 'SHA256SUMS').read_text())
            import tarfile
            with tarfile.open(archive, 'r:gz') as package:
                digest = hashlib.sha256(package.extractfile('splicore').read()).hexdigest()
            check(digest == entry['binary_sha256'], 'extracted binary digest mismatch')
            result['artifacts'][architecture] = {'archive_sha256': sc.sha(archive), 'binary_sha256': digest,
                                                  'archive_checksum_identity': 'PASS',
                                                  'runtime': 'LOCAL PASS' if architecture == 'amd64' else 'NOT CERTIFIED'}
        binary = work / 'public-splicore'
        sc.artifact(binary, args.artifacts)
        old_release = release['rollback_releases']['v0.3.0-rc.2']
        old_binary = work / 'public-rc2'
        with patch.object(sc, 'RELEASE', old_release):
            sc.artifact(old_binary, args.rc2_artifacts)
        expect_failure(lambda: sc.binary_identity(old_binary, 'amd64'), 'BINARY_IDENTITY')
        checks['rc2_binary_when_expecting_rc3'] = 'REJECTED'
        wrong = work / 'wrong-version'
        wrong.write_text('#!/bin/sh\nprintf \'{"product":"Splicore","version":"v0.0.0"}\\n\'\n')
        wrong.chmod(0o700)
        expect_failure(lambda: sc.binary_identity(wrong, 'amd64'), 'BINARY_IDENTITY')
        checks['wrong_version_binary'] = 'REJECTED'
        expect_failure(lambda: sc.arch('riscv64'), 'ARCH_UNSUPPORTED')
        checks['unsupported_architecture'] = 'REJECTED'
        corrupt = work / 'corrupt.tar.gz'
        corrupt.write_bytes((args.artifacts / release['assets']['amd64']['name']).read_bytes()[:-100])
        expect_failure(lambda: sc.inspect_archive(corrupt, release['assets']['amd64'],
                                                  (args.artifacts / 'SHA256SUMS').read_text()), 'CHECKSUM_MISMATCH')
        checks['corrupted_archive'] = 'REJECTED'
        check(sc.sha(args.mihomo_gzip) == legacy.MIHOMO_SHA256, 'official client checksum differs')
        check(sc.sha(args.legacy_xray) == '8255dd939c34cf966cc91517b6324dd3c8d0bcf49ffac8beca049a38c46845ed', 'old-server fixture digest differs')
        client = work / 'mihomo'
        with gzip.open(args.mihomo_gzip, 'rb') as source:
            client.write_bytes(source.read())
        client.chmod(0o700)
        def transport(url, destination, proxy=''):
            urls.append(url)
            cache = args.rc2_artifacts if '/v0.3.0-rc.2/' in url else args.artifacts
            shutil.copyfile(cache / url.rsplit('/', 1)[1], destination)
        result['http_transport'] = 'verified public cache substituted; resolver/checksum/extraction/identity remain production code'
        with (work / 'private.log').open('w') as log, patch.object(sc, 'download', side_effect=transport):
            # Actual old HY2 service -> rc.3, same profile before/after/rollback.
            root = work / 'l'
            with patch.dict(os.environ, environment(root)):
                runtime = sc.Runtime(adapter='fixture', fixture=work / 'unused-driver')
                sc.save(runtime.state / 'state.json', {'schema_version': 3, 'ownership': 'nobrand-v3', 'project': 'NoBrand-OneClick'})
                tls = runtime.certificate('existing', 'probe.example')
                cert = Path(tls['certificate_file'])
                cert.write_text(cert.read_text() + tls['ca_certificate'])
                private, public = legacy.keypair(work)
                rp, hp, tp = contract.vacant_port(socket.SOCK_STREAM), contract.vacant_port(socket.SOCK_DGRAM), contract.vacant_port(socket.SOCK_STREAM)
                paths = legacy.legacy_fixture(root, private, public, rp, hp, tp, tls)
                (runtime.state / 'vless-reality').rename(root / 'held-reality')
                original = hy2_profile((root / 'legacy-hy2-client.yaml').read_text())
                reality_profile = (root / 'legacy-reality-client.yaml').read_text()
                profile_hash = hashlib.sha256(original.encode()).hexdigest()
                files = [paths['hy2'], runtime.config / 'hysteria2/config.json', cert, Path(tls['private_key_file'])]
                before = [(sc.sha(p), p.stat().st_mode & 0o777) for p in files]
                desired = runtime.discover()
                hy2 = copy.deepcopy(desired['nodes'][0])
                supervisor = Supervisor(runtime, log, args.legacy_xray, files[1])
                all_supervisors.append(supervisor)
                def service_call(service, *a, **kw):
                    return supervisor.call(service, *a, **kw)
                try:
                    with patch.object(sc.Service, 'call', new=service_call):
                        supervisor.start('nobrand-hysteria2', None)
                        traffic(work, client, log, echo, original)
                        checks['old_hy2_server_original_profile_tcp_udp_domain'] = 'PASS'
                        supervisor.fail_candidate = True
                        expect_failure(lambda: runtime.deploy(desired), 'HEALTH')
                        check(not runtime.current.exists(), 'failed legacy migration left active pointer')
                        check(sc.load(runtime.transaction)['phase'] == 'ROLLED_BACK', 'legacy rollback journal differs')
                        traffic(work, client, log, echo, original)
                        checks['actual_legacy_failure_rollback_original_profile'] = 'PASS'
                        runtime.deploy(desired)
                        traffic(work, client, log, echo, original)
                        checks['mapped_salamander_original_profile_tcp_udp_domain'] = 'PASS'
                        pointer = runtime.current.readlink()
                        check(runtime.deploy(desired)['result'] == 'same-version-no-op' and runtime.current.readlink() == pointer,
                              'same version update cut over')
                        checks['same_rc3_update_noop'] = 'PASS'
                        for label, profile in [('wrong_obfs', original.replace('synthetic-salamander-secret', 'wrong-obfs')),
                                               ('missing_obfs', '\n'.join(l for l in original.splitlines() if 'obfs:' not in l and 'obfs-password:' not in l) + '\n'),
                                               ('bad_auth', original.replace('synthetic-hy2-auth', 'wrong-auth')),
                                               ('tls_client_rejects_untrusted', original.replace('skip-cert-verify: true', 'skip-cert-verify: false'))]:
                            traffic(work, client, log, echo, profile, positive=False)
                            traffic(work, client, log, echo, original)
                            checks[label + '_existing_runtime_healthy'] = 'PASS'
                        bad = copy.deepcopy(desired)
                        bad['nodes'][0]['document']['settings']['tls']['private_key_file'] = '/missing/private.key'
                        expect_failure(lambda: runtime.deploy(bad), 'CONFIG_INVALID')
                        traffic(work, client, log, echo, original)
                        checks['bad_tls_pre_cutover'] = 'PASS'
                        conflict = copy.deepcopy(desired)
                        duplicate = copy.deepcopy(conflict['nodes'][0]); duplicate['id'] = 'conflict'
                        conflict['nodes'].append(duplicate)
                        expect_failure(lambda: runtime.deploy(conflict), 'PORT_CONFLICT')
                        traffic(work, client, log, echo, original)
                        checks['desired_port_conflict_existing_runtime_healthy'] = 'PASS'
                        runtime.rollback()
                        traffic(work, client, log, echo, original)
                        checks['committed_migration_explicit_legacy_rollback'] = 'PASS'
                        check([(sc.sha(p), p.stat().st_mode & 0o777) for p in files] == before, 'migration changed old TLS/config/state')
                        check(hashlib.sha256(original.encode()).hexdigest() == profile_hash, 'old client fixture changed')
                        checks['old_tls_paths_bytes_modes_state_credentials_preserved'] = 'PASS'
                finally:
                    supervisor.close()
                # Inspect actual old default certificate without replacing it.
                default_root = work / 'default'
                legacy.legacy_fixture(default_root, private, public)
                with patch.dict(os.environ, environment(default_root)):
                    default_runtime = sc.Runtime(adapter='fixture', fixture=work / 'unused')
                    (default_runtime.state / 'vless-reality').rename(default_root / 'held-reality')
                    default_graph = default_runtime.discover()
                    expect_failure(lambda: sc.render(default_graph))
                    default_doc = sc.render(default_graph, validate_tls=False)[0][2]
                    default_path = work / 'default-old-tls.json'; sc.save(default_path, default_doc)
                    contract.run([binary, 'inbound', 'validate', '--protocol', 'hysteria2', '--file', default_path])
                checks['default_old_ca_leaf_rejected_unchanged'] = 'PASS; HY2 migration blocker remains for this old TLS contract'
            # Explicit rc.2 -> rc.3 using actual public binary and retained data.
            root = work / 'u'
            with patch.dict(os.environ, environment(root)):
                runtime = sc.Runtime(adapter='fixture', fixture=work / 'unused')
                tls_upgrade = runtime.certificate('upgrade', 'probe.example')
                graph = documents(runtime, tls_upgrade)
                old_pin = dict(old_release, capabilities=release['capabilities'])
                supervisor = Supervisor(runtime, log)
                all_supervisors.append(supervisor)
                def service_call(service, *a, **kw):
                    return supervisor.call(service, *a, **kw)
                try:
                    with patch.object(sc.Service, 'call', new=service_call):
                        with patch.object(sc, 'RELEASE', old_pin):
                            runtime.deploy(graph)
                        old_generation = runtime.current.resolve()
                        master = (old_generation / 'runtime/master.key').read_bytes()
                        original_plain = hy2_profile(sc.client_profiles(graph['nodes'][2])['mihomo'])
                        traffic(work, client, log, echo, original_plain)
                        invalid = copy.deepcopy(graph)
                        invalid['nodes'][1]['document']['settings']['mtu'] = 999
                        expect_failure(lambda: runtime.deploy(invalid), 'CONFIG_INVALID')
                        check(runtime.current.resolve() == old_generation, 'invalid rc.3 config changed the rc.2 pointer')
                        runtime.health(old_generation)
                        traffic(work, client, log, echo, original_plain)
                        checks['rc3_public_candidate_validation_failure_keeps_actual_rc2_traffic'] = 'PASS'
                        supervisor.fail_candidate = True
                        expect_failure(lambda: runtime.deploy(graph), 'HEALTH')
                        check(runtime.current.resolve() == old_generation, 'upgrade rollback did not restore rc.2')
                        sc.binary_identity(runtime.current / 'splicore', 'amd64', old_release)
                        runtime.health(old_generation)
                        traffic(work, client, log, echo, original_plain)
                        checks['rc2_to_rc3_candidate_failure_actual_rc2_rollback'] = 'PASS'
                        runtime.deploy(graph)
                        sc.binary_identity(runtime.current / 'splicore', 'amd64')
                        check(sc.load(runtime.current / 'desired.json') == graph, 'upgrade changed config or credentials')
                        check((runtime.current / 'runtime/master.key').read_bytes() == master, 'upgrade changed master key')
                        traffic(work, client, log, echo, original_plain)
                        checks['rc2_to_rc3_config_ports_credentials_plain_traffic'] = 'PASS'
                        runtime.rollback()
                        runtime.health(old_generation)
                        traffic(work, client, log, echo, original_plain)
                        checks['explicit_rc3_to_rc2_rollback'] = 'PASS'
                finally:
                    supervisor.close()
            # Fresh HY2 selects only rc.3; REALITY rejects before any download.
            root = work / 'f'
            with patch.dict(os.environ, environment(root)), patch.dict(os.environ, {'PORT': str(contract.vacant_port(socket.SOCK_DGRAM)), 'ADVERTISE_HOST': '127.0.0.1', 'NOBRAND_SPLICORE_LISTEN': '127.0.0.1', 'HY2_SNI': 'probe.example'}):
                runtime = sc.Runtime(adapter='fixture', fixture=work / 'unused')
                supervisor = Supervisor(runtime, log)
                all_supervisors.append(supervisor)
                def service_call(service, *a, **kw):
                    return supervisor.call(service, *a, **kw)
                try:
                    with patch.object(sc.Service, 'call', new=service_call):
                        count = len(urls)
                        expect_failure(lambda: runtime.protocol('vless-reality', 'install', 'fresh'), 'CAPABILITY_UNSUPPORTED')
                        check(len(urls) == count, 'blocked REALITY downloaded a core')
                        runtime.protocol('hysteria2', 'install', 'fresh')
                        fresh = urls[count:]
                        check(len(fresh) == 2 and all('/v0.3.0-rc.3/' in u for u in fresh), 'fresh core download differs from rc.3')
                        traffic(work, client, log, echo, hy2_profile(sc.client_profiles(runtime.desired()['nodes'][0])['mihomo']))
                        checks['fresh_hy2_only_rc3_download_and_traffic'] = 'PASS'
                        checks['fresh_reality_policy_reject_no_core_download'] = 'PASS; implementation OPEN'
                finally:
                    supervisor.close()
            # Native single process control: policy gap must stay explicit.
            native = work / 'native'; native.mkdir()
            shutil.copyfile(binary, native / 'splicore'); (native / 'splicore').chmod(0o700)
            (native / 'runtime').mkdir()
            sc.atomic(native / 'launch.py', sc.LAUNCHER)
            sc.atomic(native / 'bootstrap.yaml', runtime.bootstrap_text(native))
            contract.run([binary, 'key', 'init', '--file', native / 'runtime/master.key'])
            native_docs = sc.render(documents(runtime, tls, hy2))
            old = sc.load(root.parent / 'l/held-reality/instances' / legacy.IDENT / 'state.json')
            reality = {'schema': 1, 'name': 'native-vision-control', 'listener': {'host': '127.0.0.1', 'port': rp},
                       'display_endpoint': {'host': '127.0.0.1', 'port': rp},
                       'settings': {'security': 'reality', 'flow': 'xtls-rprx-vision', 'transport': 'tcp', 'packet_encoding': 'xudp',
                                    'reality': {'public_key': old['public_key'], 'short_ids': [old['short_id']], 'server_name': old['server_name'],
                                                'target': {'host': '127.0.0.1', 'port': tp}}},
                       'server_secret': {'private_key': private}, 'users': [{'account_name': 'native-vision', 'uuid': old['uuid']}]}
            native_docs.append(('vision', 'vless', reality))
            supervisor = Supervisor(runtime, log)
            all_supervisors.append(supervisor)
            target = subprocess.Popen(['openssl', 's_server', '-accept', f'127.0.0.1:{tp}', '-cert', tls['certificate_file'],
                                       '-key', tls['private_key_file'], '-tls1_3', '-quiet', '-www'], stdout=log, stderr=log)
            try:
                legacy.wait_port(target, tp)
                runtime.validate(native, native_docs)
                checks['nobrand_salamander_candidate_public_validation'] = 'PASS'
                for label, mutate in (
                    ('bad_private_key', lambda d: d['server_secret'].update(private_key='invalid')),
                    ('missing_private_key', lambda d: d.pop('server_secret')),
                    ('bad_short_id', lambda d: d['settings']['reality'].update(short_ids=['xyz'])),
                    ('bad_uuid', lambda d: d['users'][0].update(uuid='invalid')),
                    ('unknown_defender', lambda d: d['settings'].update(defender={'enabled': True})),
                    ('legacy_routing', lambda d: d.update(routing={'rules': []})),
                    ('vision_invalid_transport', lambda d: d['settings'].update(transport='hysteria'))):
                    invalid = copy.deepcopy(reality); mutate(invalid)
                    invalid_path = work / 'invalid-reality.json'; sc.save(invalid_path, invalid)
                    contract.run([binary, 'inbound', 'validate', '--protocol', 'vless', '--file', invalid_path], False)
                    checks['public_reality_rejects_' + label] = 'PASS'
                for kind in ('gecko', 'salamander'):
                    doc = copy.deepcopy(native_docs[4][2])
                    obfs = doc['settings']['stream_transport']['hysteria']['obfs']; obfs['type'] = kind
                    path = work / 'capability.json'; sc.save(path, doc)
                    contract.run([binary, 'inbound', 'validate', '--protocol', 'hysteria2', '--file', path])
                    if kind == 'gecko':
                        obfs['min_packet_size'] = 0
                        sc.save(path, doc)
                        contract.run([binary, 'inbound', 'validate', '--protocol', 'hysteria2', '--file', path], False)
                checks['core_gecko_salamander_valid_and_invalid_gecko_size'] = 'PASS; no NoBrand UI'
                range_doc = copy.deepcopy(native_docs[4][2])
                range_doc['settings']['stream_transport']['hysteria']['udp'] = {'server_port_range': f'{hp}-{min(hp+2,65535)}'}
                sc.save(path, range_doc)
                contract.run([binary, 'inbound', 'validate', '--protocol', 'hysteria2', '--file', path])
                checks['linux_server_range_validation_only'] = 'PASS; NEVER APPLIED; nftables qualification PENDING'
                supervisor.start('nobrand-splicore', native)
                service = SimpleNamespace(adapter='fixture', generation=native)
                runtime.apply_documents(native, native_docs, service)
                invalid_tls = copy.deepcopy(default_doc)
                invalid_tls['name'] = 'incompatible-old-tls'
                invalid_tls['users'][0]['account_name'] = 'incompatible-old-tls'
                sc.save(path, invalid_tls)
                tls_plan = sc.command([binary, 'inbound', 'plan', '--protocol', 'hysteria2', '--config', native / 'bootstrap.yaml', '--file', path], ok=False)
                if tls_plan.returncode == 0:
                    sc.atomic(native / 'tls-plan.json', tls_plan.stdout)
                    tls_rejection = sc.command([binary, 'inbound', 'apply', '--protocol', 'hysteria2', '--config', native / 'bootstrap.yaml', '--file', path, '--plan', native / 'tls-plan.json'], ok=False)
                else:
                    tls_rejection = tls_plan
                check(tls_rejection.returncode != 0, 'public Core admitted incompatible old TLS material')
                runtime.health(native, native_docs)
                checks['default_old_tls_public_material_admission_rejected'] = 'PASS; structural inbound validate alone accepts file references'
                client_node = {'resource': 'node', 'action': 'create',
                    'node': {'name': 'hopping-validation-only',
                        'protocol': {'protocol': 'hysteria2', 'wire_version': '2', 'feature_profile': 'base'},
                        'endpoint': {'host': '127.0.0.1', 'port': hp},
                        'transport': {'kind': 'hysteria', 'hysteria': {'version': 2}},
                        'security': {'kind': 'tls', 'tls': {'enabled': True, 'server_name': 'probe.example', 'trust': 'system', 'alpn': ['h3']}},
                        'options': {'schema_version': 1, 'data': {}}, 'metadata': {}},
                    'credential': {'kind': 'password', 'value': 'synthetic-client-password'}}
                for label, udp_settings in (
                    ('single_port', {'ports': str(hp)}),
                    ('fixed_range', {'ports': '21000-21002', 'hop_interval': 5}),
                    ('mixed_randomized', {'ports': '21000,22000-22002', 'min_hop_interval': 5, 'max_hop_interval': 10})):
                    client_node['node']['transport']['hysteria']['udp'] = udp_settings
                    sc.save(path, client_node)
                    contract.run([binary, 'node', 'validate', '--config', native / 'bootstrap.yaml', '--file', path])
                    checks['core_hopping_' + label + '_validate_only'] = 'PASS; no client runtime or nftables mutation'
                client_node['node']['transport']['hysteria']['udp']['hop_interval'] = 5
                sc.save(path, client_node)
                contract.run([binary, 'node', 'validate', '--config', native / 'bootstrap.yaml', '--file', path], False)
                checks['conflicting_hopping_intervals_rejected'] = 'PASS'
                # Use the exact plain document actually installed above.
                plain_node = {'id': 'plain', 'protocol': 'hysteria2', 'document': native_docs[2][2]}
                plain = hy2_profile(sc.client_profiles(plain_node)['mihomo'])
                for phase in ('initial', 'restart', 'sigkill_recovery'):
                    if phase != 'initial':
                        child = supervisor.children['nobrand-splicore']
                        if phase == 'sigkill_recovery':
                            child.kill(); child.wait(timeout=5)
                        else:
                            legacy.stop(child)
                        supervisor.start('nobrand-splicore', native)
                    runtime.health(native, native_docs)
                    traffic(work, client, log, echo, reality_profile, udp=False)
                    traffic(work, client, log, echo, original)
                    traffic(work, client, log, echo, plain)
                    for index, protocol in ((1, 'mieru'), (3, 'tuic')):
                        node = {'id': protocol, 'protocol': protocol, 'document': native_docs[index][2]}
                        profile = sc.client_profiles(node)
                        fragment = profile['mihomo'] if protocol == 'mieru' else profile['profiles'][0]['mihomo']
                        proxy_name = 'mieru-mita-tcp' if protocol == 'mieru' else 'nobrand-tuic-0'
                        traffic(work, client, log, echo, hy2_profile(fragment, proxy_name), udp=protocol == 'tuic')
                        checks[phase + '_' + protocol + '_traffic'] = 'PASS'
                    checks[phase + '_vision_salamander_plain_single_process_traffic'] = 'PASS'
                checks['unchanged_old_vision_profile_native_vision_control'] = 'PASS; NOT migration acceptance'
                checks['reality_private_ip_policy_counterexample'] = 'FAIL PARITY: unchanged Vision profile reaches loopback echo; legacy geoip:private denies it'
                checks['six_native_inbounds_one_splicore_process'] = 'PASS: raw REALITY Vision, Salamander HY2, plain HY2, Snell v5, Mieru TCP, TUIC v5'
                # Public port-conflict rejection must leave existing graph healthy.
                conflict = copy.deepcopy(native_docs[4][2]); conflict['name'] = 'native-conflict'
                conflict['users'][0]['account_name'] = 'native-conflict'
                sc.save(path, conflict)
                planned = sc.command([binary, 'inbound', 'plan', '--protocol', 'hysteria2', '--config', native / 'bootstrap.yaml', '--file', path], ok=False)
                if planned.returncode == 0:
                    sc.atomic(native / 'conflict-plan.json', planned.stdout)
                    failed = sc.command([binary, 'inbound', 'apply', '--protocol', 'hysteria2', '--config', native / 'bootstrap.yaml', '--file', path, '--plan', native / 'conflict-plan.json'], ok=False)
                else:
                    failed = planned
                check(failed.returncode != 0 and b'port_conflict' in failed.stderr, 'public conflict did not reject with port_conflict')
                runtime.health(native, native_docs)
                traffic(work, client, log, echo, original)
                checks['public_core_port_conflict_no_live_graph_mutation'] = 'PASS'
            finally:
                supervisor.close()
                legacy.stop(target)
        checks['temporary_processes_stopped'] = all(p.poll() is not None for owner in all_supervisors for p in owner.all_children) and target.poll() is not None
    checks['temporary_directory_removed'] = not work.exists()
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('artifacts', 'rc2-artifacts', 'mihomo-gzip', 'legacy-xray', 'output'):
        parser.add_argument('--' + name, required=True, type=Path)
    args = parser.parse_args()
    for name in ('artifacts', 'rc2_artifacts', 'mihomo_gzip', 'legacy_xray', 'output'):
        setattr(args, name, getattr(args, name).resolve())
    os.umask(0o077)
    try:
        outcome = probe(args)
    except (contract.Rejected, sc.Failure, OSError, ValueError, RuntimeError, subprocess.SubprocessError) as exc:
        # Typed diagnostics contain no commands, documents or credentials.
        detail = str(exc) if isinstance(exc, (contract.Rejected, sc.Failure, RuntimeError)) else type(exc).__name__
        print(json.dumps({'probe': 'FAIL', 'detail': detail, 'migration_blockers_closed': False}))
        return 1
    sc.save(args.output, outcome)
    print(json.dumps(outcome, indent=2))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
