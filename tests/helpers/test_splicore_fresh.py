#!/usr/bin/env python3
"""Fresh architecture policy, guard intent and new certificate gates."""
import copy
import json
import os
from pathlib import Path
import socket
import subprocess
import tarfile
import io
import unittest
from unittest.mock import patch
import test_splicore_runtime as base
sc = base.sc


class FreshTests(base.RuntimeTests):
    # Reuse the isolated service/artifact harness, without inherited test cases.
    def snapshot(self):
        return {str(p.relative_to(self.root)): (p.lstat().st_mode, p.read_bytes())
                for p in self.root.rglob('*') if p.is_file() and not p.is_symlink()}

    def test_legacy_refusal_has_zero_mutations(self):
        markers = ['state/mieru/users.json', 'state/mieru/install-state.env',
                   'state/snell/instances/old.json', 'state/tuic/instances/old/state.json',
                   'state/hysteria2/state.json', 'state/vless-reality/instances/old/state.json',
                   'lib/bin/xray', 'lib/bin/sing-box', 'lib/bin/mita', 'lib/bin/hysteria',
                   'state/state.json', 'etc/systemd/system/nobrand-mieru@.service',
                   'etc/init.d/nobrand-hysteria2']
        for marker in markers:
            with self.subTest(marker=marker):
                path = self.root / marker
                sc.atomic(path, '{}' if marker.endswith('.json') else 'owned synthetic legacy evidence')
                before = self.snapshot()
                for action in (lambda: self.deploy(), lambda: self.runtime.protocol('hysteria2', 'install', 'fresh'),
                               lambda: self.runtime.uninstall(), lambda: self.runtime.uninstall(True),
                               lambda: self.runtime.stop(), lambda: self.runtime.rollback(),
                               lambda: self.runtime.certificate('test', 'probe.example')):
                    with self.assertRaisesRegex(sc.Failure, 'No changes were made'):
                        action()
                    self.assertEqual(self.snapshot(), before)
                    self.assertEqual(self.artifact_calls, 0)
                    self.assertEqual(self.events(), '')
                path.unlink()
                # Each marker gets an otherwise empty owned namespace.
                for parent in list(path.parents):
                    if parent == self.root:
                        break
                    try: parent.rmdir()
                    except OSError: break

    def test_third_party_core_names_do_not_claim_ownership(self):
        for name in ('xray', 'sing-box', 'hysteria', 'mita'):
            sc.atomic(self.root / 'usr/local/bin' / name, 'foreign executable')
            sc.atomic(self.root / 'etc/systemd/system' / (name + '.service'), 'foreign service')
        self.assertFalse(self.runtime.legacy_present())
        self.assertEqual(self.deploy()['result'], 'committed')

    def test_new_marker_and_no_implicit_legacy_fields(self):
        self.deploy()
        registry = sc.load(self.runtime.state / 'state.json')
        self.assertEqual(registry['architecture'], 'splicore-native')
        self.assertEqual(registry['splicore_version'], sc.RELEASE['version'])
        graph = base.desired()
        graph['legacy_services'] = ['nobrand-hysteria2']
        before = self.events()
        with self.assertRaises(sc.Failure): self.deploy(graph)
        self.assertEqual(self.events(), before)

    def test_fresh_hy2_leaf_and_verified_client_trust(self):
        env = {'PORT': '31232', 'ADVERTISE_HOST': 'entry.example', 'HY2_SNI': 'probe.example'}
        with patch.dict(os.environ, env):
            outcome = self.runtime.protocol('hysteria2', 'install', 'fresh')
        node = self.runtime.desired()['nodes'][0]
        tls = node['document']['settings']['tls']
        sc.tls_check(tls)
        text = sc.command(['openssl', 'x509', '-in', tls['certificate_file'], '-noout', '-text']).stdout
        for expected in (b'CA:FALSE', b'Digital Signature', b'TLS Web Server Authentication', b'DNS:probe.example'):
            self.assertIn(expected, text)
        self.assertFalse(list((self.runtime.config / 'splicore/tls').rglob('ca.key')))
        profile = outcome['client_profiles'][0]
        self.assertFalse(profile['sing_box']['tls']['insecure'])
        self.assertIn('pinSHA256=', profile['uri'])
        self.assertIn('skip-cert-verify: false', profile['mihomo'])
        self.assertIn('fingerprint:', profile['mihomo'])
        self.assertEqual(sc.hysteria_obfs(node['document']['settings'])['type'], 'salamander')
        self.assertNotEqual(node['document']['users'][0]['password'], sc.hysteria_obfs(node['document']['settings'])['password'])

    def test_fresh_hy2_failure_cleans_new_tls_and_can_retry(self):
        env = {'PORT': '31232', 'ADVERTISE_HOST': 'entry.example', 'HY2_SNI': 'probe.example'}
        (self.root / 'fail-health').touch()
        with patch.dict(os.environ, env):
            with self.assertRaises(sc.Failure): self.runtime.protocol('hysteria2', 'install', 'fresh')
            self.assertFalse(self.runtime.current.exists())
            self.assertFalse((self.runtime.state / 'state.json').exists())
            self.assertEqual(list((self.runtime.config / 'splicore/tls').iterdir()), [])
            self.assertEqual(self.runtime.protocol('hysteria2', 'install', 'fresh')['result'], 'committed')

    def test_fresh_tuic_failure_cleans_new_tls(self):
        (self.root / 'fail-health').touch()
        with patch.dict(os.environ, {'PORT': '31232', 'ADVERTISE_HOST': 'entry.example'}):
            with self.assertRaises(sc.Failure): self.runtime.protocol('tuic', 'install', 'fresh')
        self.assertFalse(self.runtime.current.exists())
        self.assertEqual(list((self.runtime.config / 'splicore/tls').iterdir()), [])

    def test_product_backup_requires_native_marker_before_extraction(self):
        archive = self.root / 'legacy-product.tar.gz'
        with tarfile.open(archive, 'w:gz') as stream:
            for directory in ('state', 'config'):
                item = tarfile.TarInfo(directory); item.type = tarfile.DIRTYPE; stream.addfile(item)
            for name, body in [('manifest.txt', b'synthetic'), ('state/state.json', b'{"schema_version":3}')]:
                item = tarfile.TarInfo(name); item.size = len(body); stream.addfile(item, io.BytesIO(body))
        before = self.snapshot()
        with self.assertRaises(sc.Failure) as caught: sc.inspect_backup_archive(archive)
        self.assertEqual(caught.exception.category, 'UNSUPPORTED_LEGACY_INSTALLATION')
        self.assertEqual(self.snapshot(), before)

    def test_native_ingress_change_keeps_credentials_and_transport(self):
        with patch.dict(os.environ, {'PORT': '31232', 'ADVERTISE_HOST': 'entry.example',
                                   'PROTOCOL': 'TCP', 'TRAFFIC_PATTERN': 'off',
                                   'NOBRAND_SPLICORE_INGRESS_ID': 'fixture-profile'}):
            self.runtime.protocol('mieru', 'install', 'fresh')
        node = copy.deepcopy(self.runtime.desired()['nodes'][0])
        with patch.dict(os.environ, {'NOBRAND_SPLICORE_LISTEN': '127.0.0.1'}):
            self.runtime.protocol('mieru', 'set-listen', node['id'])
        current = self.runtime.desired()['nodes'][0]
        self.assertEqual(current['ingress'], {'profile_id': 'fixture-profile'})
        self.assertEqual(current['document']['users'], node['document']['users'])
        self.assertEqual(current['document']['listener']['host'], '127.0.0.1')

    def test_fresh_reality_native_guard_and_secret_projection(self):
        env = {'PORT': '31233', 'ADVERTISE_HOST': 'entry.example', 'VLESS_REALITY_TARGET': 'cover.example'}
        with patch.dict(os.environ, env):
            outcome = self.runtime.protocol('vless-reality', 'install', 'fresh')
        node = self.runtime.desired()['nodes'][0]
        docs = sc.render(self.runtime.desired())
        self.assertEqual(docs[0][1], 'vless')
        self.assertEqual(docs[0][2]['settings']['flow'], 'xtls-rprx-vision')
        mutations = sc.guard_mutations(self.runtime.desired())
        guard = mutations[0]['local_inbound']
        self.assertEqual(guard['listen']['host'], '127.0.0.1')
        self.assertTrue(guard['sniffing']['route_only'])
        rules = mutations[-1]['network']['route']['rules']
        self.assertEqual([r['action']['kind'] for r in rules], ['direct', 'reject'])
        self.assertEqual(rules[0]['match']['sniffed_domains'], ['cover.example'])
        private = node['document']['server_secret']['private_key']
        self.assertNotIn(private, json.dumps(outcome))
        self.assertNotIn(private, json.dumps(sc.redacted_plan(self.runtime.desired())))
        for mutate in (lambda n: n['guard']['listen'].update(host='0.0.0.0'),
                       lambda n: n['guard'].update(approved_sni=['arbitrary.example']),
                       lambda n: n['document']['settings'].update(stream_transport={'kind': 'grpc'})):
            bad = copy.deepcopy(self.runtime.desired()); mutate(bad['nodes'][0])
            before = self.events()
            with self.assertRaises(sc.Failure): self.deploy(bad)
            self.assertEqual(before, self.events())

    def test_ordinary_port_conflict_is_a_port_error(self):
        with socket.socket() as listener:
            listener.bind(('127.0.0.1', 0)); listener.listen()
            with self.assertRaises(sc.Failure) as caught: self.deploy(base.desired(listener.getsockname()[1]))
            self.assertEqual(caught.exception.category, 'PORT_CONFLICT')
        self.assertNotIn('stop ', self.events())

# Inherited generic transaction tests run in their own suite once.
for name in dir(base.RuntimeTests):
    if name.startswith('test_'):
        setattr(FreshTests, name, None)

if __name__ == '__main__':
    unittest.main(verbosity=2)
