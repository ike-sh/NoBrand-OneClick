#!/usr/bin/env python3
"""Presentation contracts against synthetic v4 canonical profiles and installers."""
import contextlib
import copy
import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import yaml
import test_splicore_runtime as base

ROOT = Path(__file__).resolve().parents[2]
FIXTURE = json.loads((ROOT / 'tests/fixtures/client-profile-output.json').read_text())
spec = importlib.util.spec_from_file_location('client_output', ROOT / 'runtime/client-output.py')
ui = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ui)
spec = importlib.util.spec_from_file_location('diagnostics', ROOT / 'scripts/ci-diagnostics.py')
diagnostics = importlib.util.module_from_spec(spec)
spec.loader.exec_module(diagnostics)


def mieru(host='203.0.113.10', port=10201):
    node = copy.deepcopy(FIXTURE['nodes'][2])
    node['document']['display_endpoint'] = {'host': host, 'port': port}
    return base.sc.client_profiles(node)


def render(*profiles, listeners=None):
    return ui.render_client_profiles({'client_profiles': list(profiles)}, listeners)


def section(text, heading):
    return text.split('[' + heading + ']\n', 1)[1].split('\n[', 1)[0].rstrip('=\n')


class PresentationTests(unittest.TestCase):
    def test_machine_golden_unchanged_for_every_producer(self):
        with patch.object(base.sc, 'leaf_fingerprint', return_value='a' * 64):
            actual = [base.sc.client_profiles(node) for node in FIXTURE['nodes']]
        self.assertEqual(json.dumps(actual, indent=2), json.dumps(FIXTURE['client_profiles'], indent=2))

    def test_historical_mieru_semantics(self):
        text = render(mieru(), listeners={'mieru': {'host': '0.0.0.0', 'port': 10201}})
        for value in ('Mieru 节点配置', '用户名: user_test_001', '密码: pass_test_001',
                      '传输协议: TCP', '传输预设: default', '服务监听: 0.0.0.0:10201',
                      '客户端入口: 203.0.113.10:10201', '[分享链接]', 'mierus://', '[Mihomo / Clash Meta]'):
            self.assertIn(value, text)
        self.assertNotIn('IPLC', text)
        for value in ('"client_profiles"', '"mihomo":', '\\n', '\\"', '\x1b'):
            self.assertNotIn(value, text)

    def test_uri_bytes_and_no_hard_wrap(self):
        profile = mieru()
        profile['uri'] += '&synthetic=' + 'a%2Fb%26c' * 100
        text = render(profile)
        self.assertIn(profile['uri'].encode() + b'\n', text.encode())
        self.assertEqual(section(text, '分享链接').strip(), profile['uri'])

    def test_mihomo_exact_multiline_and_parse(self):
        profile = mieru()
        block = section(render(profile), 'Mihomo / Clash Meta').rstrip('\n') + '\n'
        self.assertEqual(block, profile['mihomo'])
        proxy = yaml.safe_load(block)['proxies'][0]
        self.assertEqual((proxy['server'], proxy['port'], proxy['username'], proxy['password']),
                         ('203.0.113.10', 10201, 'user_test_001', 'pass_test_001'))
        self.assertGreater(len(block.splitlines()), 5)
        self.assertNotIn('\\n', block)

    def test_canonical_formats_exact_for_all_protocols(self):
        for profile in FIXTURE['client_profiles']:
            with self.subTest(protocol=profile['protocol'], ident=profile['id']):
                text = render(profile)
                entries = profile['profiles'] if profile['protocol'] == 'tuic' else [profile]
                for entry in entries:
                    self.assertIn(entry['mihomo'], text)
                    yaml.safe_load(entry['mihomo'])
                if profile.get('uri'):
                    self.assertIn(profile['uri'] + '\n', text)
                else:
                    self.assertNotIn('[分享链接]', text)
                self.assertNotIn('"client_profiles"', text)

    def test_native_is_client_document(self):
        profile = mieru()
        native = json.loads(section(render(profile), 'Mieru 原生客户端配置'))
        self.assertEqual(native, profile['mieru'])
        self.assertEqual(native['activeProfile'], 'default')

    def test_endpoints_ipv4_domain_ipv6(self):
        for host, expected in (('203.0.113.10', '203.0.113.10:443'),
                               ('edge.example', 'edge.example:443'), ('2001:db8::10', '[2001:db8::10]:443')):
            with self.subTest(host=host):
                profile = mieru(host, 443)
                text = render(profile, listeners={'mieru': {'host': '::', 'port': 10201}})
                self.assertIn('客户端入口: ' + expected, text)
                self.assertIn('服务监听: [::]:10201', text)
                self.assertIn(profile['uri'] + '\n', text)
                self.assertEqual(yaml.safe_load(profile['mihomo'])['proxies'][0]['server'], host)

    def test_multiple_profiles_and_tuic_users_in_order(self):
        a, b = mieru(), mieru('edge.example')
        a['id'], b['id'] = 'Profile A', 'Profile B'
        text = render(a, b)
        self.assertLess(text.index('Profile A'), text.index('Profile B'))
        self.assertIn('Profile 1 / 2', text)
        self.assertIn('Profile 2 / 2', text)
        tuic = render(FIXTURE['client_profiles'][4])
        self.assertLess(tuic.index('用户: Profile A'), tuic.index('用户: Profile B'))
        self.assertIn('synthetic-tuic-a', tuic)
        self.assertIn('synthetic-tuic-b', tuic)

    def test_absent_optional_sections(self):
        profile = mieru()
        del profile['mihomo']
        profile['uri'] = None
        text = render(profile)
        self.assertNotIn('[分享链接]', text)
        self.assertNotIn('[Mihomo / Clash Meta]', text)
        for value in ('None', 'null', '{}', '[]', '<missing>'):
            self.assertNotIn(value, text)

    def test_no_input_mutation(self):
        original = copy.deepcopy(FIXTURE)
        render(*FIXTURE['client_profiles'])
        self.assertEqual(FIXTURE, original)

    def test_required_server_port_and_credentials(self):
        for field in ('ipAddress', 'port', 'password', 'name'):
            with self.subTest(field=field):
                profile = mieru()
                native = profile['mieru']['profiles'][0]
                if field == 'ipAddress': native['servers'][0]['ipAddress'] = ''
                elif field == 'port': del native['servers'][0]['portBindings'][0]['port']
                else: del native['user'][field]
                with self.assertRaises(ui.ProfileError): render(profile)

    def test_bind_address_rejected_as_client_server(self):
        for host in ('0.0.0.0', '::'):
            with self.subTest(host=host), self.assertRaises(ui.ProfileError): render(mieru(host))

    def test_server_private_fields_never_render(self):
        text = render(*FIXTURE['client_profiles'])
        self.assertNotIn('REALITY_PRIVATE_KEY_SHOULD_NEVER_RENDER', text)
        self.assertNotIn('TLS_PRIVATE_KEY_SHOULD_NEVER_RENDER', text)
        profile = mieru()
        profile['server_secret'] = {'private_key': 'REALITY_PRIVATE_KEY_SHOULD_NEVER_RENDER'}
        self.assertNotIn('REALITY_PRIVATE_KEY_SHOULD_NEVER_RENDER', render(profile))
        profile['mieru']['server_secret'] = {'private_key': 'REALITY_PRIVATE_KEY_SHOULD_NEVER_RENDER'}
        with self.assertRaises(ui.ProfileError): render(profile)

    def test_explicit_credentials_and_sanitized_diagnostics(self):
        secret = 'CLIENT_SECRET_VISIBLE_123'
        profile = FIXTURE['client_profiles'][3]
        text = render(profile)
        self.assertIn(secret, text)
        redact = diagnostics.sanitizer([json.dumps(profile), text])
        self.assertNotIn(secret, redact(text))
        self.assertNotIn(secret, json.dumps(base.sc.redacted_plan(dict(base.sc.empty(), nodes=FIXTURE['nodes']))))

    def test_status_and_doctor_exclude_credentials(self):
        harness = base.RuntimeTests()
        harness.setUp()
        try:
            with patch.dict(os.environ, {'PORT': '10201', 'ADVERTISE_HOST': '203.0.113.10',
                                        'USERNAME': 'user_test_001', 'PASSWORD': 'CLIENT_SECRET_VISIBLE_123',
                                        'TRAFFIC_PATTERN': 'off', 'PROTOCOL': 'TCP'}):
                created = harness.runtime.protocol('mieru', 'install', 'synthetic')
            self.assertIn('CLIENT_SECRET_VISIBLE_123', render(*created['client_profiles']))
            for operation in ('status', 'doctor'):
                self.assertNotIn('CLIENT_SECRET_VISIBLE_123', json.dumps(harness.runtime.protocol('mieru', operation)))
        finally:
            harness.tearDown()

    def test_actual_runtime_machine_json_and_create_view_identity(self):
        harness = base.RuntimeTests()
        harness.setUp()
        try:
            with patch.dict(os.environ, {'PORT': '10201', 'ADVERTISE_HOST': '203.0.113.10',
                                        'USERNAME': 'user_test_001', 'PASSWORD': 'pass_test_001',
                                        'TRAFFIC_PATTERN': 'off', 'PROTOCOL': 'TCP'}):
                created = harness.runtime.protocol('mieru', 'install', 'synthetic')
            output = io.StringIO()
            with contextlib.redirect_stdout(output):
                code = base.sc.main(['protocol', '--protocol', 'mieru', '--operation', 'show',
                                     '--adapter', 'fixture', '--fixture-driver', str(harness.driver)])
            self.assertEqual(code, 0)
            self.assertEqual(json.loads(output.getvalue()), {'client_profiles': created['client_profiles']})
            self.assertEqual(render(*created['client_profiles']),
                             render(*json.loads(output.getvalue())['client_profiles']))
        finally:
            harness.tearDown()

    def test_english_labels(self):
        text = ui.render_client_profiles({'client_profiles': [mieru()]}, chinese=False)
        self.assertIn('Client endpoint: 203.0.113.10:10201', text)
        self.assertIn('[Share link]', text)

    def test_cli_error_is_atomic_and_sanitized(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'desired.json'
            path.write_text(json.dumps({'nodes': FIXTURE['nodes']}))
            profile = mieru()
            del profile['mieru']['profiles'][0]['user']['password']
            proc = subprocess.run(['python3', str(ROOT / 'runtime/client-output.py'), str(path), '1'],
                                  input=json.dumps({'client_profiles': [mieru(), profile]}), text=True, capture_output=True)
            self.assertEqual(proc.returncode, 1)
            self.assertEqual(proc.stdout, '')
            self.assertIn('CLIENT_PROFILE_INVALID', proc.stderr)
            self.assertNotIn('pass_test_001', proc.stderr)


class InstallerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='client-output-')
        self.root = Path(self.temp.name)
        self.state = self.root / 'state'
        generation = self.state / 'splicore/generations/synthetic'
        generation.mkdir(parents=True)
        (generation / 'desired.json').write_text(json.dumps(dict(base.sc.empty(), nodes=FIXTURE['nodes'])))
        (self.state / 'splicore/current').symlink_to('generations/synthetic')
        self.env = dict(os.environ, NOBRAND_TEST_MODE='1', NOBRAND_SYSTEM_ROOT=str(self.root / 'system'),
                        NOBRAND_STATE_DIR=str(self.state), NOBRAND_CONFIG_DIR=str(self.root / 'config'),
                        NOBRAND_LIB_DIR=str(self.root / 'lib'), NOBRAND_LIFECYCLE_DIR=str(self.root / 'journal'),
                        NOBRAND_LIFECYCLE_LOCK_FILE=str(self.root / 'guard'))
        self.common = '''set -euo pipefail
export MITA_SOURCE_ONLY=1
source "$INSTALLER" "$@"
trap - ERR
PORT=10201
YES=1
require_root() { :; }
nb_prepare_ingress_request() { INGRESS_PROFILE_ID=synthetic; }
nb_prepare_ingress_deployment() { INGRESS_LISTEN_HOST=0.0.0.0; }
nb_ingress_port_is_reserved() { return 1; }
nobrand_install_manager_script() { :; }
# Only the runtime boundary is a fixture. Parsing, menus and human output are production.
nb_splicore_python() { cat "$PROFILE_RESULT"; }
read_tty() { case "$1" in choice) printf -v "$1" 2;; *) printf -v "$1" ''; esac; }
'''

    def tearDown(self):
        self.temp.cleanup()

    def shell(self, installer, profile, command, args=()):
        result = self.root / 'result.json'
        result.write_text(json.dumps({'client_profiles': [profile]}))
        env = dict(self.env, INSTALLER=str(ROOT / installer), PROFILE_RESULT=str(result))
        return subprocess.run(['bash', '-c', self.common + command, 'nobrand', *args],
                              env=env, capture_output=True, text=True)

    def test_create_view_shortcut_and_export_all_protocols_both_installers(self):
        for installer in ('install-nobrand.sh', 'dist/install-nobrand.sh'):
            for profile in FIXTURE['client_profiles']:
                protocol = profile['protocol']
                outputs = []
                for operation in ('install', 'show', 'export'):
                    with self.subTest(installer=installer, protocol=protocol, operation=operation):
                        proc = self.shell(installer, profile,
                                          'nb_splicore_protocol ' + protocol + ' ' + operation + ' synthetic')
                        self.assertEqual(proc.returncode, 0, proc.stderr)
                        self.assertNotIn('"client_profiles"', proc.stdout)
                        self.assertIn('[基本信息]', proc.stdout)
                        outputs.append(proc.stdout)
                self.assertEqual(outputs[0], outputs[1])
                self.assertEqual(outputs[1], outputs[2])

    def test_mieru_menu_aliases_and_explicit_show_consistent(self):
        for alias in ('nobrand', 'nb'):
            entry = self.root / alias
            entry.symlink_to(ROOT / 'dist/install-nobrand.sh')
            for args in (('mieru',), ('mieru', 'show')):
                with self.subTest(alias=alias, args=args):
                    # Exercise shipped parser through both installed executable names.
                    installer = str(entry)
                    command = 'if [ "$ACTION" = nobrand-mieru-menu ]; then show_menu; menu_run_action; else nb_splicore_route_main; fi'
                    proc = self.shell(installer, mieru(), command, args)
                    self.assertEqual(proc.returncode, 0, proc.stderr)
                    core = proc.stdout[proc.stdout.index('=' * 60):]
                    expected = render(mieru(), listeners={'mieru': {'host': '0.0.0.0', 'port': 10201}})
                    self.assertEqual(core.rstrip(), expected.rstrip())

    def test_existing_runtime_machine_entry_bypasses_human_renderer(self):
        proc = self.shell('install-nobrand.sh', mieru(), 'nb_splicore_route_main',
                          ('runtime', 'protocol', '--protocol', 'mieru', '--operation', 'show'))
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertEqual(json.loads(proc.stdout), {'client_profiles': [mieru()]})
        self.assertNotIn('[基本信息]', proc.stdout)

    def test_all_protocol_shortcut_parsers_use_shared_renderer(self):
        for profile in FIXTURE['client_profiles']:
            protocol = profile['protocol']
            alias = 'hy2' if protocol == 'hysteria2' else protocol
            with self.subTest(protocol=protocol, ident=profile['id']):
                proc = self.shell('dist/install-nobrand.sh', profile, 'nb_splicore_route_main', (alias, 'show'))
                self.assertEqual(proc.returncode, 0, proc.stderr)
                self.assertEqual(proc.stdout.rstrip(),
                                 render(profile, listeners={profile['id']: {'host': '0.0.0.0', 'port': 10201}}).rstrip())

    def test_renderer_failure_propagates_without_json_fallback(self):
        profile = mieru()
        del profile['mieru']['profiles'][0]['user']['password']
        proc = self.shell('dist/install-nobrand.sh', profile, 'nb_splicore_protocol mieru show synthetic')
        self.assertEqual(proc.returncode, 1)
        self.assertEqual(proc.stdout, '')
        self.assertIn('CLIENT_PROFILE_INVALID', proc.stderr)

    def test_missing_wrapper_fails_without_raw_json_fallback(self):
        proc = self.shell('dist/install-nobrand.sh', mieru(),
                          "nb_splicore_python() { printf '%s\\n' '{}'; }; nb_splicore_protocol mieru show synthetic")
        self.assertEqual(proc.returncode, 1)
        self.assertEqual(proc.stdout, '')
        self.assertIn('CLIENT_PROFILE_INVALID', proc.stderr)


if __name__ == '__main__':
    unittest.main()
