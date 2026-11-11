#!/usr/bin/env python3
"""Native Sudoku regression; all supervision is isolated from the host."""
import copy
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import unittest
from unittest.mock import patch
import test_splicore_runtime as base
sc = base.sc


class SudokuTests(base.RuntimeTests):
    def install(self):
        with patch.dict(os.environ, {'PORT':'31239', 'ADVERTISE_HOST':'2001:db8::1', 'PASSWORD':'synthetic-sudoku-password'}):
            return self.runtime.protocol('vless-sudoku', 'install', 'primary')

    def test_canonical_and_client_roundtrip(self):
        result = self.install()
        node = self.runtime.desired()['nodes'][0]
        name, protocol, document = sc.render(self.runtime.desired())[0]
        self.assertEqual(protocol, 'vless')
        self.assertEqual(document['settings']['security'], 'none')
        mask = document['settings']['stream_transport']['final_mask']
        profile = result['client_profiles'][0]
        self.assertIsNone(profile['uri'])
        target = profile['xray']['settings']['vnext'][0]
        self.assertEqual(target['address'], '2001:db8::1')
        self.assertIn('mlkem768x25519plus.random.1rtt.', target['users'][0]['encryption'])
        self.assertIn('.random.0rtt.', document['settings']['encryption'])
        self.assertEqual(profile['xray']['streamSettings']['finalmask'], mask)
        self.assertEqual(profile['compatibility']['vless_encryption'], 'enabled')
        self.assertEqual(profile['client_version'], '26.10.21')
        self.assertNotIn('inbounds', profile['xray'])
        self.assertEqual(profile['xray_config']['outbounds'][0]['streamSettings']['finalmask'], mask)
        self.assertEqual(node['document']['users'][0]['uuid'], target['users'][0]['id'])
        self.assertNotIn(document['server_secret']['decryption'], json.dumps(profile))
        self.assertEqual(self.runtime.protocol('vless-sudoku', 'export', 'primary'), profile['xray_config'])
        self.assertEqual(self.runtime.protocol('vless-sudoku', 'subscription', 'primary'), profile['xray_config'])
        for env in ({'NOBRAND_SPLICORE_EXPORT_FORMAT':'uri'}, {'NOBRAND_SPLICORE_CLIENT_VERSION':'26.10.31'}):
            with patch.dict(os.environ, env):
                with self.assertRaises(sc.Failure): self.runtime.protocol('vless-sudoku', 'export', 'primary')
        self.assertEqual(self.runtime.port_pairs(self.runtime.desired()), {'TCP|31239'})
        self.assertTrue(name.startswith('n'))
        import importlib.util
        spec=importlib.util.spec_from_file_location('sudoku_output',base.ROOT/'runtime/client-output.py')
        presenter=importlib.util.module_from_spec(spec);spec.loader.exec_module(presenter)
        text=presenter.render_client_profiles(result)
        self.assertIn('VLESS Encryption',text)
        self.assertIn('26.10.21',text)
        self.assertIn('1rtt',text)
        self.assertNotIn(document['server_secret']['decryption'],text)

    def test_no_fake_encryption_or_xray_server(self):
        self.install()
        graph = self.runtime.desired()
        for field, value in [('encryption','mlkem768x25519plus.native.0rtt.fake'), ('decryption','fake'), ('engine_options',{'engine':'xray'})]:
            bad=copy.deepcopy(graph); bad['nodes'][0]['document']['settings'][field]=value
            with self.assertRaises(sc.Failure): sc.render(bad)
        bad=copy.deepcopy(graph);bad['nodes'][0]['document']['server_secret']={'private_key':'fake'}
        with self.assertRaises(sc.Failure): sc.render(bad)
        for path in self.root.rglob('*'):
            self.assertNotEqual(path.name, 'xray')
        self.assertEqual(sc.client_profiles(graph['nodes'][0])['compatibility']['vless_encryption'], 'enabled')

    def test_sudoku_parameters_fail_closed(self):
        self.install(); graph=self.runtime.desired()
        for params in ({'paddingMin':50,'paddingMax':10}, {'paddingMin':True}, {'ascii':'wrong'}, {'password':''}, {'customTable':'unsupported'}):
            bad=copy.deepcopy(graph)
            bad['nodes'][0]['document']['settings']['stream_transport']['final_mask']['tcp'][0]['settings'].update(params)
            with self.assertRaises(sc.Failure): sc.render(bad)

    def test_legacy_upgrade_preserves_plain_mode(self):
        self.install()
        graph = self.runtime.desired()
        document = graph['nodes'][0]['document']
        original_users = copy.deepcopy(document['users'])
        del document['settings']['encryption']
        del document['server_secret']
        del graph['nodes'][0]['client']['encryption']
        graph['splicore_version'] = 'v0.4.0'
        with patch.object(sc, 'generate_vless_encryption', side_effect=AssertionError('legacy key rotation')):
            self.runtime.deploy(graph)
            self.runtime.protocol('vless-sudoku', 'upgrade', 'primary')
            self.runtime.protocol('vless-sudoku', 'install', 'primary')
        node = self.runtime.desired()['nodes'][0]
        self.assertNotIn('server_secret', node['document'])
        self.assertEqual(node['document']['users'], original_users)
        self.assertEqual(sc.client_profiles(node)['xray']['settings']['vnext'][0]['users'][0]['encryption'], 'none')

    def test_shared_process_credentials_persist_and_node_remove(self):
        self.deploy()
        self.install()
        self.assertEqual({n['protocol'] for n in self.runtime.desired()['nodes']}, {'snell','vless-sudoku'})
        original=self.runtime.desired()['nodes'][1]['document']['users']
        self.runtime.protocol('vless-sudoku','stop','primary')
        self.assertEqual(len(sc.render(self.runtime.desired())), 1)
        self.runtime.protocol('vless-sudoku','start','primary')
        self.assertEqual(self.runtime.desired()['nodes'][1]['document']['users'], original)
        self.runtime.protocol('vless-sudoku','remove','primary')
        self.assertEqual([n['protocol'] for n in self.runtime.desired()['nodes']], ['snell'])
        self.assertNotIn('nobrand-vless-sudoku', self.events())
        self.assertEqual(set(json.loads((self.root/'services.json').read_text())), {'nobrand-splicore'})

    def test_duplicate_install_and_concurrent_lock(self):
        self.install(); before=self.runtime.current.resolve()
        self.assertEqual(self.install()['result'],'same-version-no-op')
        self.assertEqual(len(self.runtime.desired()['nodes']),1)
        self.assertEqual(before, self.runtime.current.resolve())
        import fcntl
        with Path(os.environ['NOBRAND_LIFECYCLE_LOCK_FILE']).open('a') as lock:
            fcntl.flock(lock, fcntl.LOCK_EX|fcntl.LOCK_NB)
            with self.assertRaisesRegex(sc.Failure, 'another runtime'): self.runtime.protocol('vless-sudoku','stop','primary')

    def test_reconfigure_preserves_uuid_and_uses_generation_rollback(self):
        self.install(); original=copy.deepcopy(self.runtime.desired()['nodes'][0])
        with patch.dict(os.environ,{'PORT':'31241','PORT_CLI':'1','PASSWORD_CLI':'1','PASSWORD':'synthetic-new-table','ADVERTISE_CLI':'1','ADVERTISE_HOST':'changed.example','ADVERTISE_PORT':'443'}):
            result=self.runtime.protocol('vless-sudoku','install','primary')
        node=self.runtime.desired()['nodes'][0]
        self.assertEqual(node['document']['users'],original['document']['users'])
        self.assertEqual(node['document']['server_secret'],original['document']['server_secret'])
        self.assertEqual(node['client']['encryption'],original['client']['encryption'])
        self.assertEqual(node['document']['listener']['port'],31241)
        self.assertEqual(node['document']['display_endpoint'],{'host':'changed.example','port':443})
        self.assertEqual(node['document']['settings']['stream_transport']['final_mask'],sc.sudoku_mask('synthetic-new-table'))
        self.assertIn('client_profiles',result)
        self.runtime.rollback()
        self.assertEqual(self.runtime.desired()['nodes'][0],original)

    def test_fresh_shell_provisions_dependencies_before_python_status(self):
        self.install()
        result=self.root/'client-result.json'
        sc.save(result,{'client_profiles':[sc.client_profiles(self.runtime.desired()['nodes'][0])]})
        env=dict(os.environ,NOBRAND_STATE_DIR=str(self.root/'fresh/state'),NOBRAND_CONFIG_DIR=str(self.root/'fresh/config'),
                 NOBRAND_LIB_DIR=str(self.root/'fresh/lib'),NOBRAND_LIFECYCLE_DIR=str(self.root/'fresh/journal'))
        script=r"""
set -euo pipefail
installer=$1
result_file=$2
set --
MITA_SOURCE_ONLY=1
source "$installer"
trap - ERR
deps_ready=0
command() {
  if [ "${1:-}:${2:-}" = -v:python3 ]; then return 1; fi
  builtin command "$@"
}
require_root() { :; }
nobrand_prepare_common() { deps_ready=1; }
nb_prepare_ingress_request() { INGRESS_PROFILE_ID=fixture; }
nb_prepare_ingress_deployment() { INGRESS_LISTEN_HOST=127.0.0.1; }
nb_ingress_port_is_reserved() { return 1; }
nb_warn_if_outside_recommended_range() { :; }
nb_require_explicit_endpoint_noninteractive() { :; }
nb_endpoint_conflict_owner() { return 1; }
nobrand_install_manager_script() { :; }
nb_render_client_profiles() { cat; }
nb_splicore_call() {
  [ "$deps_ready" -eq 1 ] || { printf 'Python called before dependencies' >&2; return 66; }
  cat "$result_file"
}
YES=1 PORT=31249 PORT_CLI=1 ADVERTISE_HOST=fixture.invalid ADVERTISE_PORT=31249 ADVERTISE_CLI=1
nb_splicore_protocol vless-sudoku install primary
"""
        proc=subprocess.run(['bash','-c',script,'sudoku-fresh',str(base.ROOT/'install-nobrand.sh'),str(result)],env=env,capture_output=True,text=True,timeout=20)
        self.assertEqual(proc.returncode,0,proc.stderr)
        self.assertIn('xray_config',proc.stdout)

    def test_readonly_diagnostics_and_unmutated_lifecycle_cancel(self):
        record={'FORMAT':'nobrand-lifecycle-v2','STATUS':'in-progress','OPERATION':'install','SCOPE':'vless-sudoku',
                'MUTATION_STARTED':'0','LAST_COMPLETED_PHASE':'state-layout','TRANSACTION_ID':'synthetic-original',
                'MANAGER_VERSION':'4.0.1','SCHEMA_GENERATION':'3','STARTED_AT':'2026-11-11T00:00:00Z',
                'MIERU_OWNED':'0','MIERU_PRESERVE_PACKAGE':'0','MIERU_PRESERVE_USER':'0','MIERU_PRESERVE_GROUP':'0','MIERU_PRESERVE_SHARED':'0'}
        path=self.runtime.lifecycle/'transaction.env'
        sc.atomic(path, ''.join(k+'='+v+'\n' for k,v in record.items()))
        before={p:(p.read_bytes(),p.stat().st_mtime_ns) for p in self.root.rglob('*') if p.is_file()}
        self.assertEqual(self.runtime.transactions()['lifecycle']['recovery'], 'NO_MUTATION_CANCEL')
        self.assertEqual(before,{p:(p.read_bytes(),p.stat().st_mtime_ns) for p in before})
        with self.assertRaisesRegex(sc.Failure, 'unfinished lifecycle'): self.install()
        with self.runtime.locked(recovery=True): self.runtime.recover_lifecycle()
        self.assertEqual(self.runtime.lifecycle_record()['STATUS'],'complete')
        self.assertEqual(len(list(self.runtime.lifecycle.glob('cancelled-*.env'))),1)
        self.install()

    def test_mutated_legacy_transaction_cannot_be_guessed(self):
        path=self.runtime.lifecycle/'transaction.env'
        sc.atomic(path,'FORMAT=nobrand-lifecycle-v2\nSTATUS=in-progress\nOPERATION=install\nSCOPE=vless-sudoku\nMUTATION_STARTED=1\n')
        before=path.read_bytes()
        with self.runtime.locked(recovery=True):
            with self.assertRaisesRegex(sc.Failure, 'original request'): self.runtime.recover_lifecycle()
        self.assertEqual(before,path.read_bytes())

    def test_failure_codes_and_retry_after_download_failure(self):
        with patch.object(sc,'artifact',side_effect=sc.Failure('NETWORK','download failed')):
            with self.assertRaises(sc.Failure): self.install()
        tx=sc.load(self.runtime.transaction)
        self.assertEqual(tx['error_code'],'NB-GEN-PREPARING-NETWORK')
        self.assertEqual(tx['phase'],'ROLLED_BACK')
        self.install()

    def test_sigkill_each_cutover_phase_and_interrupted_rollback(self):
        self.deploy(); original=self.runtime.current.resolve()
        for phase in ('PREPARING','VALIDATED','STOPPING','STOPPED','STARTING','VERIFIED','ROLLING_BACK'):
            with self.subTest(phase=phase):
                pid=os.fork()
                if pid==0:
                    checkpoint=self.runtime.checkpoint
                    def kill_at(tx, current):
                        checkpoint(tx,current)
                        if current==phase: os.kill(os.getpid(),signal.SIGKILL)
                    self.runtime.checkpoint=kill_at
                    if phase=='ROLLING_BACK': (self.root/'fail-start').touch()
                    self.install(); os._exit(7)
                _, status=os.waitpid(pid,0)
                self.assertEqual(os.waitstatus_to_exitcode(status),-signal.SIGKILL)
                self.assertEqual(sc.load(self.runtime.transaction)['phase'],phase)
                with self.runtime.locked(): self.runtime.recover()
                self.assertEqual(self.runtime.current.resolve(),original)
                self.assertEqual(sc.load(self.runtime.transaction)['phase'],'ROLLED_BACK')
        self.install()

    def test_recovery_rejects_corrupt_snapshot_without_touching_current(self):
        self.deploy(); self.install(); tx=sc.load(self.runtime.transaction); tx['phase']='STARTING'
        sc.save(self.runtime.transaction,tx)
        original=self.runtime.current.readlink()
        sc.atomic(self.runtime.generations/tx['old']/'splicore',b'corrupt')
        with self.assertRaises(sc.Failure):
            with self.runtime.locked(): self.runtime.recover()
        self.assertEqual(original,self.runtime.current.readlink())
        self.assertEqual(sc.load(self.runtime.transaction)['phase'],'STARTING')


if __name__=='__main__':
    names=sys.argv[1:]
    suite=unittest.TestSuite(SudokuTests(n) for n in names or SudokuTests.__dict__ if n.startswith('test_'))
    sys.exit(0 if unittest.TextTestRunner(verbosity=2).run(suite).wasSuccessful() else 1)
