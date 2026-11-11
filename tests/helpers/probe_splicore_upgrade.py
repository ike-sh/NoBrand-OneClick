#!/usr/bin/env python3
"""Real v0.4.0 -> v0.5.0 -> matched v0.4.0 snapshot rollback, private loopback only."""
import argparse
import copy
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
from types import SimpleNamespace
from unittest.mock import patch
import splicore_native_probe as probe
from native_sudoku_client import probe as sudoku_traffic

sc=probe.sc

def run(args):
 spec=importlib.util.spec_from_file_location('original_v040',args.old_runtime)
 old=importlib.util.module_from_spec(spec);spec.loader.exec_module(old)
 result={'version':sc.RELEASE['version'],'scope':'public artifacts, private loopback, process supervisor','checks':{}}
 os.umask(0o077)
 with tempfile.TemporaryDirectory(prefix='sc-up-') as d,probe.Echo() as echo:
  work=Path(d)
  env={'NOBRAND_SYSTEM_ROOT':str(work),'NOBRAND_STATE_DIR':str(work/'s'),'NOBRAND_CONFIG_DIR':str(work/'c'),
       'NOBRAND_LIB_DIR':str(work/'l'),'NOBRAND_LIFECYCLE_DIR':str(work/'j'),'NOBRAND_LIFECYCLE_LOCK_FILE':str(work/'lock'),
       'NOBRAND_SPLICORE_FIXTURE':'1','NOBRAND_SPLICORE_LISTEN':'127.0.0.1','ADVERTISE_HOST':'127.0.0.1',
       'ADVERTISE_PORT':'','PORT':str(probe.vacant()),'SNELL_VERSION':'4'}
  with patch.dict(os.environ,env),(work/'driver').open('w') as driver,(work/'private.log').open('wb') as log:
   driver.write('supervisor only')
   runtime=old.Runtime(adapter='fixture',fixture=work/'driver')
   supervisor=probe.Supervisor(runtime,log)
   def call(service,*a,**kw):return supervisor.call(service,*a,**kw)
   try:
    with patch.object(old.Service,'call',call),patch.object(sc.Service,'call',call):
     runtime.protocol('snell','install','original',args.old_artifacts)
     original=runtime.current.resolve()
     original_graph=runtime.desired();original_key=(original/'runtime/master.key').read_bytes()
     # Baseline and rollback traffic use the original NoBrand projection.
     import gzip
     client=work/'mihomo'
     with gzip.open(args.mihomo_gzip,'rb') as stream:sc.atomic(client,stream.read(),0o700)
     if sc.sha(args.mihomo_gzip)!=probe.MIHOMO_SHA256:raise AssertionError('client checksum')
     fragment=old.client_profiles(original_graph['nodes'][0])['mihomo']
     probe.traffic(work,client,log,echo,fragment,'original')
     result['checks']['official_v040_baseline_tcp_udp']='PASS'
     runtime=sc.Runtime(adapter='fixture',fixture=work/'driver');supervisor.runtime=runtime
     with patch.dict(os.environ,{'PORT':str(probe.vacant())}):
      runtime.protocol('vless-sudoku','install','native',args.artifacts)
     current=runtime.current.resolve()
     assert current!=original and current.joinpath('runtime/state.db').resolve()!=original.joinpath('runtime/state.db').resolve()
     assert current.joinpath('runtime/master.key').read_bytes()==original_key
     assert runtime.desired()['nodes'][0]['document']['psk']==original_graph['nodes'][0]['document']['psk']
     assert sc.load(current/'artifact.json')['version']==sc.RELEASE['version']
     probe.traffic(work,client,log,echo,fragment,'original')
     sudoku_traffic(sc,current/'splicore',work,log,echo,runtime.desired()['nodes'][1])
     result['checks']['upgrade_rebuilds_database_preserves_credentials_and_key']='PASS'
     result['checks']['upgraded_snell_and_native_sudoku_tcp_udp']='PASS'
     runtime.rollback()
     assert runtime.current.resolve()==original
     assert sc.load(runtime.state/'state.json')['splicore_version']=='v0.4.0'
     assert runtime.desired()==original_graph
     probe.traffic(work,client,log,echo,fragment,'original')
     result['checks']['rollback_matches_old_binary_database_key_registry_and_traffic']='PASS'
     result['checks']['new_generation_retained_for_review']='PASS' if current.exists() else 'FAIL'
   finally:probe.stop(supervisor.child)
 result['result']='PASS'
 return result

if __name__=='__main__':
 p=argparse.ArgumentParser(description=__doc__)
 p.add_argument('--old-runtime',type=Path,required=True);p.add_argument('--old-artifacts',type=Path,required=True)
 p.add_argument('--artifacts',type=Path,required=True);p.add_argument('--mihomo-gzip',type=Path,required=True)
 p.add_argument('--output',type=Path,required=True)
 a=p.parse_args();out=run(a);sc.save(a.output,out);print(json.dumps(out,indent=2))
