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
q=module('qualification050','scripts/qualify-splicore.py')
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
  self.assertEqual(q.sc.RELEASE['version'],'v0.5.0')
  self.assertEqual(q.sc.RELEASE['commit'],'70b09da7d2758e19ba03df9ff9b9e541a669fa29')
  self.assertEqual(set(q.sc.RELEASE['rollback_releases']),{'v0.4.0'})
  self.assertFalse(q.sc.RELEASE['capabilities']['vless-sudoku']['requires_external_xray'])
 def test_exact_integration_inventory_and_workflow(self):
  self.assertEqual(q.review_integrity()['result'],'PASS')
  self.assertEqual(q.workflow_contract((ROOT/'.github/workflows/ci.yml').read_text())['contract'],'PASS')
 def test_manifest_cannot_hide_unbuilt_new_production_module(self):
  original=q.sc.sha
  with patch.object(q.sc,'sha',side_effect=lambda p: '0'*64 if Path(p).name=='splicore.py' else original(p)):
   with self.assertRaises(q.QualificationFailure):q.review_integrity()
 def test_architecture_qualifications_are_not_combined(self):
  self.assertIn('BUILD ONLY',q.sc.RELEASE['assets']['arm64']['qualification'])
  self.assertNotIn('PASS',q.sc.RELEASE['assets']['arm64']['qualification'])

if __name__=='__main__':unittest.main(verbosity=2)
