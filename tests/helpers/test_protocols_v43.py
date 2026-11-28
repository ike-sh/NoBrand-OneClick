#!/usr/bin/env python3
"""NoBrand 4.3 managed creation, reservation, credential and projection regressions."""
import base64
import contextlib
import copy
import io
import json
import os
import socket
import unittest
from unittest.mock import patch
from urllib.parse import unquote, urlsplit

import test_splicore_runtime as base

sc = base.sc
LABEL = '东京 / edge #1 + a@b'
KEY = base64.b64encode(bytes.fromhex('fbff' * 8)).decode('ascii')


def ss_node(method=sc.SS2022_DEFAULT_METHOD, udp=True, port=41021):
    key = base64.b64encode(bytes.fromhex('fbff' * (sc.SS2022_KEY_BYTES[method] // 2))).decode('ascii')
    return {'id': 'test', 'protocol': 'ss2022', 'client': {'name': LABEL}, 'enabled': True,
            'document': {'schema': 1, 'listener': {'host': '0.0.0.0', 'port': port},
                         'display_endpoint': {'host': 'edge.example', 'port': 65535},
                         'settings': {'method': method, 'udp': udp}, 'users': [{'key': key}]}}


def graph(*nodes):
    return dict(sc.empty(), nodes=list(nodes))


def free_port():
    for _ in range(32):
        with socket.socket() as tcp, socket.socket(type=socket.SOCK_DGRAM) as udp:
            tcp.bind(('127.0.0.1', 0))
            port = tcp.getsockname()[1]
            try:
                udp.bind(('127.0.0.1', port))
            except OSError:
                continue
            return port
    raise AssertionError('no free TCP+UDP fixture port')


class ContractTests(unittest.TestCase):
    def test_all_methods_single_key_envelope_and_lossless_client_formats(self):
        for method, size in sc.SS2022_KEY_BYTES.items():
            for host in ('203.0.113.5', '2001:db8::5', 'edge.example'):
                for udp in (True, False):
                    with self.subTest(method=method, host=host, udp=udp):
                        node = ss_node(method, udp)
                        node['document']['display_endpoint']['host'] = host
                        key = node['document']['users'][0]['key']
                        name, family, doc = sc.render(graph(node))[0]
                        self.assertEqual((name, family, doc['users']), ('test', 'shadowsocks', [{'account_name': 'nb-test-0', 'key': key}]))
                        self.assertNotIn('server_key', doc)
                        self.assertEqual(len(base64.b64decode(key, validate=True)), size)
                        profile = sc.client_profiles(node)
                        self.assertEqual(profile['connection'], {'name': LABEL, 'host': host, 'port': 65535, 'method': method, 'key': key, 'udp': udp})
                        self.assertEqual(profile['sing_box'], {'type': 'shadowsocks', 'tag': LABEL, 'server': host, 'server_port': 65535,
                                                              'method': method, 'password': key, **({} if udp else {'network': 'tcp'})})
                        self.assertEqual(profile['mihomo'], {'proxies': [{'type': 'ss', 'name': LABEL, 'server': host, 'port': 65535,
                                                                       'cipher': method, 'password': key, 'udp': udp}]})
                        if udp:
                            uri = urlsplit(profile['uri'])
                            self.assertEqual((uri.scheme, uri.username, unquote(uri.password), uri.hostname, uri.port, unquote(uri.fragment)),
                                             ('ss', method, key, host, 65535, LABEL))
                            self.assertNotIn(key, profile['uri'])
                            if ':' in host:
                                self.assertIn('@[' + host + ']:65535', profile['uri'])
                        else:
                            self.assertNotIn('uri', profile)

    def test_reject_malformed_key_and_schema_without_echo(self):
        for method, size in sc.SS2022_KEY_BYTES.items():
            valid = sc.ss2022_requested_key(method, {})
            self.assertEqual(len(base64.b64decode(valid, validate=True)), size)
            for bad in (None, '', 'not Base64', 'A' * (len(valid)-1), valid + '=', valid.rstrip('='), valid + '\n',
                        valid + ':' + valid, KEY.replace('/', '_'), 'A' * (len(valid)-1) + 'é',
                        base64.b64encode(bytes(size - 1)).decode(), base64.b64encode(bytes(size + 1)).decode(),
                        ('A' * 21 + 'B==') if size == 16 else ('A' * 42 + 'B=')):
                with self.subTest(method=method, invalid_type=type(bad).__name__):
                    node = ss_node(method)
                    node['document']['users'][0]['key'] = bad
                    with self.assertRaises(sc.Failure) as caught:
                        sc.render(graph(node))
                    self.assertEqual(caught.exception.category, 'CONFIG_INVALID')
                    if bad:
                        self.assertNotIn(bad, str(caught.exception))
        for update in (lambda d: d['settings'].update(method='aes-128-gcm'), lambda d: d['settings'].update(multi_user=True),
                       lambda d: d['settings'].update(udp='false'), lambda d: d['settings'].pop('udp'),
                       lambda d: d['users'].append({'key': KEY}), lambda d: d.update(users=[{'password': KEY}]),
                       lambda d: d.update(server_key=KEY), lambda d: d.update(psk=KEY), lambda d: d.update(users=[])):
            node = ss_node()
            update(node['document'])
            with self.assertRaises(sc.Failure) as caught:
                sc.render(graph(node))
            self.assertNotIn(KEY, str(caught.exception))
        a, b = ss_node(), ss_node(port=41022)
        b['id'] = 'secondary'
        b['document']['display_endpoint']['port'] -= 1
        with self.assertRaisesRegex(sc.Failure, 'independent keys'):
            sc.render(graph(a, b))

    def test_snell_versions_and_physical_reservations_vs_exported_transports(self):
        rt = sc.Runtime()
        for version, expected in ((4, {'surge': 4, 'sing_box': 4, 'mihomo': 4}),
                                  (5, {'surge': 5, 'sing_box': 4, 'mihomo': 4}),
                                  (6, {'surge': 6, 'sing_box': 6})):
            g = base.desired()
            node = g['nodes'][0]
            node['document']['settings']['version'] = version
            self.assertEqual(sc.render(g)[0][2]['settings']['version'], version)
            profile = sc.client_profiles(node)
            self.assertEqual(profile['client_versions'], expected)
            self.assertIn('version = ' + str(version), profile['surge'])
            self.assertEqual(profile['sing_box']['version'], expected['sing_box'])
            self.assertEqual('mihomo' in profile, version != 6)
            if version != 6:
                self.assertIn('version: 4', profile['mihomo'])
            self.assertEqual(rt.port_pairs(g), {'TCP|31231', 'UDP|31231'} if version == 5 else {'TCP|31231'})
            self.assertEqual(rt.firewall_pairs(g), {'TCP|31231'})
            self.assertEqual(rt.service_firewall_pairs(g), {'TCP|31231'})
            node['enabled'] = False
            self.assertEqual(rt.service_firewall_pairs(g), set())
            self.assertIn('TCP|31231', rt.port_pairs(g))
        for invalid in (True, 4.0, '6', 3, 7):
            node['document']['settings']['version'] = invalid
            with self.assertRaises(sc.Failure):
                sc.render(g)

    def test_conflicts_with_other_transports_and_display_endpoint(self):
        node, udp_node = ss_node(), {'id': 'other', 'protocol': 'mieru', 'document': {
            'schema': 1, 'listener': {'host': '127.0.0.1', 'port': 41021}, 'display_endpoint': {'host': 'other.example', 'port': 1024},
            'settings': {'transport': 'udp', 'mtu': 1400, 'multiplex': 'off'}, 'users': [{'username': 'tester', 'password': 'synthetic'}]}}
        rt = sc.Runtime()
        self.assertEqual(rt.port_pairs(graph(node)), {'TCP|41021', 'UDP|41021'})
        self.assertEqual(rt.firewall_pairs(graph(node)), rt.port_pairs(graph(node)))
        with self.assertRaisesRegex(sc.Failure, 'overlapping'):
            sc.render(graph(node, udp_node))
        node['document']['settings']['udp'] = False
        self.assertEqual(len(sc.render(graph(node, udp_node))), 2)
        self.assertEqual(rt.firewall_pairs(graph(node)), {'TCP|41021'})
        node['enabled'] = False
        self.assertEqual(rt.firewall_pairs(graph(node)), set())
        self.assertEqual(rt.port_pairs(graph(node)), {'TCP|41021'})
        node['enabled'] = True
        node['document']['listener']['host'] = '127.0.0.1'
        node['document']['settings']['udp'] = True
        self.assertEqual(rt.firewall_pairs(graph(node)), set())
        udp_node['document']['listener']['port'] += 1
        udp_node['document']['display_endpoint'] = {'host': 'EDGE.example', 'port': 65535}
        for nodes in ((node, udp_node), (udp_node, node)):
            with self.assertRaisesRegex(sc.Failure, 'client endpoint overlaps'):
                sc.render(graph(*nodes))


class ManagementTests(unittest.TestCase):
    def setUp(self):
        fixture = base.RuntimeTests()
        fixture.setUp()
        self.addCleanup(fixture.tearDown)
        self.runtime, self.root = fixture.runtime, fixture.root
        self.port = free_port()
        env = patch.dict(os.environ, {'ADVERTISE_HOST': 'edge.example', 'ADVERTISE_PORT': '', 'PORT': str(self.port),
                                      'NOBRAND_SPLICORE_LISTEN': '127.0.0.1', 'NOBRAND_SPLICORE_EXPORT_FORMAT': '',
                                      'NOBRAND_SPLICORE_DISPLAY_PORT_POLICY': '', 'SS2022_KEY': '', 'SS2022_UDP': '', 'SS2022_METHOD': ''})
        env.start()
        self.addCleanup(env.stop)

    def run_ss(self, action, label=LABEL):
        return self.runtime.protocol('ss2022', action, label)

    def test_default_rotation_redaction_restore_and_removal(self):
        result = self.run_ss('install')
        original = self.run_ss('export')
        key = original['key']
        self.assertEqual((original['method'], original['udp'], original['port']), (sc.SS2022_DEFAULT_METHOD, True, self.port))
        self.assertEqual(len(base64.b64decode(key, validate=True)), 16)
        installed = sc.load(self.runtime.current / 'desired.json')['nodes'][0]
        self.assertEqual(installed['document']['users'], [{'key': key}])
        for f in (self.runtime.current / 'desired.json', self.runtime.current / 'documents' / (installed['id'] + '.json')):
            self.assertEqual(f.stat().st_mode & 0o777, 0o600)
        for projected in [result, self.run_ss('show'), self.run_ss('status'), self.run_ss('doctor'), sc.redacted_plan(self.runtime.desired())]:
            self.assertNotIn(key, json.dumps(projected))
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            sc.main(['render', '--file', str(self.runtime.current / 'desired.json')])
        self.assertNotIn(key, out.getvalue())
        for operation in ('user-show', 'client-config'):
            with self.assertRaises(sc.Failure):
                self.run_ss(operation)
        with self.assertRaises(sc.Failure):
            self.run_ss('export', '')
        backup = self.root / 'ss-backup.tar.gz'
        self.runtime.backup(backup)
        with patch.dict(os.environ, {'SS2022_KEY': KEY}):
            self.assertNotIn(KEY, json.dumps(self.run_ss('rotate-key')))
        self.assertEqual(self.run_ss('export')['key'], KEY)
        with patch.dict(os.environ, {'SS2022_KEY': KEY}):
            with self.assertRaisesRegex(sc.Failure, 'must differ'):
                self.run_ss('rotate-key')
        path = self.runtime.current.resolve()
        with patch.dict(os.environ, {'SS2022_KEY': KEY + ':' + KEY}):
            with self.assertRaises(sc.Failure):
                self.run_ss('rotate-key')
        self.assertEqual(self.runtime.current.resolve(), path)
        (self.root / 'fail-health').touch()
        with self.assertRaises(sc.Failure):
            self.run_ss('rotate-key')
        self.assertEqual(self.runtime.current.resolve(), path)
        self.assertEqual(self.run_ss('export')['key'], KEY)
        self.assertEqual(sc.load(self.runtime.transaction)['phase'], 'ROLLED_BACK')
        self.runtime.restore(backup)
        self.assertEqual(self.run_ss('export'), original)
        self.run_ss('remove')
        self.assertEqual(self.runtime.port_pairs(self.runtime.desired()), set())
        self.assertEqual(self.run_ss('status')['nodes'], [])

    def test_atomic_network_and_endpoint_edits_and_export_selection(self):
        with patch.dict(os.environ, {'SS2022_KEY': KEY, 'SS2022_UDP': 'off'}):
            self.run_ss('install')
        with patch.dict(os.environ, {'NOBRAND_SPLICORE_EXPORT_FORMAT': 'uri'}):
            with self.assertRaisesRegex(sc.Failure, 'TCP-only'):
                self.run_ss('export')
        with patch.dict(os.environ, {'NOBRAND_SPLICORE_EXPORT_FORMAT': 'sing-box'}):
            self.assertEqual(self.run_ss('export')['network'], 'tcp')
        with socket.socket(type=socket.SOCK_DGRAM) as blocker, patch.dict(os.environ, {'SS2022_UDP': 'on'}):
            blocker.bind(('127.0.0.1', self.port))
            old = self.runtime.current.resolve()
            with self.assertRaisesRegex(sc.Failure, 'UDP'):
                self.run_ss('set-udp')
            self.assertEqual(self.runtime.current.resolve(), old)
            self.assertFalse(self.run_ss('show')['nodes'][0]['udp'])
        with patch.dict(os.environ, {'SS2022_UDP': 'on'}):
            self.run_ss('set-udp')
        port = free_port()
        with patch.dict(os.environ, {'PORT': str(port)}):
            self.run_ss('set-port')
        self.assertEqual(self.runtime.port_pairs(self.runtime.desired()), {'TCP|' + str(port), 'UDP|' + str(port)})
        self.assertEqual(self.run_ss('export')['port'], port)
        with patch.dict(os.environ, {'ADVERTISE_HOST': '2001:db8::42', 'ADVERTISE_PORT': '65535'}):
            self.run_ss('set-endpoint')
        with patch.dict(os.environ, {'PORT': str(free_port())}):
            self.run_ss('set-port')
        with patch.dict(os.environ, {'NOBRAND_SPLICORE_EXPORT_FORMAT': 'mihomo'}):
            self.assertEqual(self.run_ss('export')['proxies'][0]['port'], 65535)
        with patch.dict(os.environ, {'NOBRAND_SPLICORE_EXPORT_FORMAT': 'uri'}):
            self.assertEqual(urlsplit(self.run_ss('export')).netloc.split('@')[1], '[2001:db8::42]:65535')
        self.assertEqual(self.run_ss('export')['key'], KEY)
        self.run_ss('stop')
        self.assertFalse(self.run_ss('show')['nodes'][0]['enabled'])
        self.run_ss('start')
        self.assertTrue(self.run_ss('show')['nodes'][0]['enabled'])
        self.assertEqual(self.run_ss('export')['key'], KEY)

    def test_snell_set_port_physical_conflict_and_display_policy(self):
        for version in (4, 5, 6):
            with self.subTest(version=version):
                label, psk = 'snell-' + str(version), 'synthetic-key-' + str(version)
                original = free_port()
                # v4 has a manually selected advertised port; v5/v6 follow the
                # listener. In either case the wire version and PSK are immutable.
                display = '43210' if version == 4 else ''
                with patch.dict(os.environ, {'PORT': str(original), 'SNELL_VERSION': str(version),
                                             'SNELL_PSK': psk, 'ADVERTISE_PORT': display}):
                    self.runtime.protocol('snell', 'install', label)
                before = self.runtime.current.resolve()
                new = free_port()
                while new == original:
                    new = free_port()
                with socket.socket() as tcp, patch.dict(os.environ, {'PORT': str(new)}):
                    tcp.bind(('127.0.0.1', new))
                    tcp.listen()
                    with self.assertRaisesRegex(sc.Failure, 'TCP'):
                        self.runtime.protocol('snell', 'set-port', label)
                    self.assertEqual(self.runtime.current.resolve(), before)
                with socket.socket(type=socket.SOCK_DGRAM) as udp, patch.dict(os.environ, {'PORT': str(new)}):
                    udp.bind(('127.0.0.1', new))
                    if version == 5:
                        with self.assertRaisesRegex(sc.Failure, 'UDP'):
                            self.runtime.protocol('snell', 'set-port', label)
                        self.assertEqual(self.runtime.current.resolve(), before)
                    else:
                        outcome = self.runtime.protocol('snell', 'set-port', label)
                if version == 5:
                    with patch.dict(os.environ, {'PORT': str(new)}):
                        outcome = self.runtime.protocol('snell', 'set-port', label)
                self.assertNotIn(psk, json.dumps(outcome))
                metadata, = outcome['listeners']
                self.assertEqual((metadata['version'], metadata['listener']['port']), (version, new))
                self.assertEqual(metadata['display_endpoint']['port'], 43210 if version == 4 else new)
                current = self.runtime.desired()
                self.assertEqual(current['nodes'][0]['document']['psk'], psk)
                expected = {'TCP|' + str(new)}
                self.assertEqual(self.runtime.firewall_pairs(current), expected)
                self.assertEqual(self.runtime.port_pairs(current), expected | ({'UDP|' + str(new)} if version == 5 else set()))
                self.runtime.rollback()
                restored = self.runtime.desired()['nodes'][0]['document']
                self.assertEqual((restored['listener']['port'], restored['psk'], restored['settings']['version']),
                                 (original, psk, version))
                self.runtime.protocol('snell', 'remove', label)

    def test_old_snell_missing_display_policy_keeps_export_port(self):
        g = base.desired(port=32010)
        node = g['nodes'][0]
        sc.set_listener_port([node], 'snell', node['id'], '65535')
        self.assertEqual(node['document']['display_endpoint']['port'], 32010)
        self.assertEqual(node['document']['listener']['port'], 65535)
        self.assertNotIn('client', node)
        self.assertEqual(len(sc.render(g)), 1)

    def test_preserve_snell_versions_and_reject_v6_mihomo(self):
        nodes = []
        for v in (4, 5, 6):
            with patch.dict(os.environ, {'SNELL_VERSION': str(v), 'SNELL_PSK': 'synthetic-key-' + str(v), 'PORT': str(free_port())}):
                self.runtime.protocol('snell', 'install', str(v))
            nodes.append(copy.deepcopy(self.runtime.desired()['nodes'][-1]))
        self.assertEqual(self.runtime.desired()['nodes'], nodes)
        self.runtime.protocol('snell', 'upgrade')
        self.assertEqual(self.runtime.desired()['nodes'], nodes)
        with patch.dict(os.environ, {'NOBRAND_SPLICORE_EXPORT_FORMAT': 'mihomo'}):
            with self.assertRaises(sc.Failure):
                self.runtime.protocol('snell', 'export', '6')
        with patch.dict(os.environ, {'SNELL_QUIC_PROXY': 'on'}):
            for v in (4, 5, 6):
                with self.assertRaises(sc.Failure):
                    self.runtime.protocol('snell', 'set-quic', str(v))


if __name__ == '__main__':
    unittest.main(verbosity=2)
