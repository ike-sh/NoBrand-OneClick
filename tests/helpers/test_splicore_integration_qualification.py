#!/usr/bin/env python3
"""Current architecture and integration qualification regression."""
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
ROOT=Path(__file__).resolve().parents[2]
def module(name,path):
 s=importlib.util.spec_from_file_location(name,ROOT/path);m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m
q=module('native_qualification','scripts/qualify-splicore.py')
audit=module('runtimeaudit','scripts/audit-runtime.py')

class IntegrationQualificationTests(unittest.TestCase):
 def test_production_architecture(self):
  self.assertEqual(audit.violations(ROOT),[])
 def test_new_runtime_download_start_and_python_fallback_rejected(self):
  with tempfile.TemporaryDirectory() as d:
   root=Path(d)
   for folder in ('src','runtime','dist','scripts'): (root/folder).mkdir()
   for name in ('scripts/build.sh','install-nobrand.sh','dist/install-nobrand.sh'): (root/name).write_text('')
   for payload in ('curl https://github.com/XTLS/Xray-core/releases/download/v1/x.zip',
                   'nobrand_install_xray_runtime() { :; }','ExecStart=${NOBRAND_XRAY_BIN} run -c a.json',
                   '"$NOBRAND_XRAY_BIN" run -c a.json','subprocess.Popen(["xray", "run", "-c", "a.json"])'):
    (root/'src/new.sh').write_text(payload)
    self.assertTrue(audit.violations(root),payload)
 def test_release_and_rollback_pins_are_separate(self):
  self.assertEqual(q.sc.RELEASE['version'],'v0.6.7')
  self.assertEqual(q.sc.RELEASE['commit'],'a5ecdc5785fbcf978534046517d1692613d91706')
  self.assertEqual(set(q.sc.RELEASE['rollback_releases']),{'v0.4.0','v0.5.0','v0.6.4','v0.6.5'})
  self.assertFalse(q.sc.RELEASE['capabilities']['vless-sudoku']['requires_external_xray'])
 def test_exact_integration_inventory_and_workflow(self):
  self.assertEqual(q.review_integrity()['result'],'PASS')
  self.assertEqual(q.workflow_contract((ROOT/'.github/workflows/ci.yml').read_text())['contract'],'PASS')
 def test_manifest_cannot_hide_unbuilt_new_production_module(self):
  original=q.sc.sha
  with patch.object(q.sc,'sha',side_effect=lambda p: '0'*64 if Path(p).name=='splicore.py' else original(p)):
   with self.assertRaises(q.QualificationFailure):q.review_integrity()
 def test_arm64_rejected_before_download(self):
  self.assertEqual(set(q.sc.RELEASE['assets']),{'amd64'})
  with patch.object(q.sc.platform,'machine',return_value='aarch64'), patch.object(q.sc,'download') as download:
   with tempfile.TemporaryDirectory() as directory:
    destination=Path(directory)/'splicore'
    with self.assertRaises(q.sc.Failure) as raised:
     q.sc.artifact(destination,target_arch='amd64')
    self.assertEqual(raised.exception.category,'ARCH_UNSUPPORTED')
    self.assertFalse(destination.exists())
    download.assert_not_called()

 def test_only_confirmed_parent_can_purge_inside_uninstall(self):
  import os, subprocess
  with tempfile.TemporaryDirectory() as d:
   root=Path(d)
   env=dict(os.environ, NOBRAND_STATE_DIR=d+'/state', NOBRAND_CONFIG_DIR=d+'/config',
            NOBRAND_LIB_DIR=d+'/lib', NOBRAND_SYSTEM_ROOT=d, NOBRAND_LIFECYCLE_DIR=d+'/journal',
            NOBRAND_LIFECYCLE_LOCK_FILE=d+'/lock', NOBRAND_PARENT_UNINSTALL_TX='abc')
   journal=root/'journal/transaction.env';journal.parent.mkdir()
   code='''import sys,splicore
try:
 with splicore.Runtime(adapter="process").locked(parent_purge=sys.argv[1]=="purge"): pass
except splicore.Failure as error:
 sys.exit(93 if error.category=="LIFECYCLE_PENDING" else 1)
'''
   for inherited, token, action, scope, mutated, expected in (
     (True,'abc','purge','global',1,0), (False,'abc','purge','global',1,93),
     (True,'wrong','purge','global',1,93), (True,'abc','start','global',1,93),
     (True,'abc','purge','manager',1,93), (True,'abc','purge','global',0,93)):
    with self.subTest(inherited=inherited, token=token, action=action, scope=scope, mutated=mutated):
     journal.write_text(f'FORMAT=nobrand-lifecycle-v2\nOPERATION=uninstall\nSCOPE={scope}\nSTATUS=in-progress\n'
                        f'TRANSACTION_ID=abc\nMUTATION_STARTED={mutated}\nLAST_COMPLETED_PHASE=prepare\n')
     env['NOBRAND_PARENT_UNINSTALL_TX']=token
     wrapper=('exec 7>"$NOBRAND_LIFECYCLE_LOCK_FILE"; flock -x 7; ' if inherited else '')+'exec python3 -c "$1" "$2"'
     self.assertEqual(subprocess.run(['bash','-c',wrapper,'test',code,action],env=env,cwd=ROOT/'runtime').returncode,expected)

 def test_cross_architecture_snapshot_is_refused_before_binary_execution(self):
  with tempfile.TemporaryDirectory() as directory, patch.object(q.sc,'binary_identity') as identity:
   snapshot=Path(directory)
   metadata=snapshot/'artifact.json'
   q.sc.save(metadata,{'version':'v0.6.4','architecture':'arm64'})
   with self.assertRaises(q.sc.Failure) as raised:
    q.sc.Runtime(root=snapshot,adapter='process').verify_installed_binary(snapshot)
   self.assertEqual(raised.exception.category,'ARCH_UNSUPPORTED')
   self.assertTrue(metadata.is_file())
   identity.assert_not_called()

if __name__=='__main__':unittest.main(verbosity=2)
