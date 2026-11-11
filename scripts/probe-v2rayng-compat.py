#!/usr/bin/env python3
"""Source and referenced Core qualification, distinct from an Android app test.

The optional Xray artifact is a test CLIENT only. This script never installs a
production server, unit, fallback or NoBrand runtime.
"""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import zipfile

ROOT=Path(__file__).resolve().parents[1]
TAG_COMMIT='57907cf354d9769200ed4717b4430d605abe0952'
CLIENT_ARCHIVE_SHA='e4bd9119f50ae7c41658b1abd0679ae06f98bd864a2907ff33f2f2cf7081b214'
ERROR='vless without TLS or other encryption is prohibited unless the server address is a private IP or domain'


def run(source,archive):
    head=subprocess.check_output(['git','rev-parse','HEAD'],cwd=source,text=True).strip()
    if head!=TAG_COMMIT: raise ValueError('v2rayNG 2.3.15 source identity differs')
    files={
     'V2rayNG/app/src/main/java/com/v2ray/ang/fmt/VlessFmt.kt':['queryParam["encryption"] ?: "none"'],
     'V2rayNG/app/src/main/java/com/v2ray/ang/fmt/FmtBase.kt':['config.finalMask = queryParam["fm"]'],
     'V2rayNG/app/src/main/java/com/v2ray/ang/core/CoreOutboundBuilder.kt':['settings.encryption = profileItem.method','streamSettings.finalmask = parsedFinalMask'],
    }
    for name,needles in files.items():
        text=(source/name).read_text()
        if not all(n in text for n in needles):raise ValueError('pinned source parser contract differs')
    if hashlib.sha256(archive.read_bytes()).hexdigest()!=CLIENT_ARCHIVE_SHA:raise ValueError('reference client archive checksum differs')
    spec=importlib.util.spec_from_file_location('compat_runtime',ROOT/'runtime/splicore.py')
    sc=importlib.util.module_from_spec(spec);spec.loader.exec_module(sc)
    result={'v2rayNG_version':'2.3.15','v2rayNG_commit':head,'source_fm_and_encryption_projection':'PASS (static source audit)',
            'reference_core':'Xray-core v26.10.31 a4a3dff','client_archive_sha256':CLIENT_ARCHIVE_SHA,
            'Android_import_and_VPN_runtime':'NOT EXECUTED','public_plain_vless_sudoku':'FAIL','checks':{}}
    with tempfile.TemporaryDirectory(prefix='nb-client-compat-') as d:
        root=Path(d);binary=root/'reference-client'
        with zipfile.ZipFile(archive) as z:binary.write_bytes(z.read('xray'))
        binary.chmod(0o700)
        for host,expected in [('203.0.113.1',False),('127.0.0.1',True)]:
            node={'id':'compat','protocol':'vless-sudoku','document':{
                'display_endpoint':{'host':host,'port':443},'users':[{'uuid':'11111111-1111-4111-8111-111111111111'}],
                'settings':{'security':'none','flow':'none','transport':'tcp','packet_encoding':'xudp',
                            'stream_transport':{'kind':'tcp','final_mask':sc.sudoku_mask('synthetic-compatibility-table')}}}}
            profile=sc.client_profiles(node)
            path=root/'client.json';sc.save(path,{'log':{'loglevel':'warning'},'outbounds':[profile['xray']]})
            p=subprocess.run([str(binary),'run','-test','-c',str(path)],capture_output=True,text=True,timeout=30)
            if (p.returncode==0)!=expected or not expected and ERROR not in p.stdout+p.stderr:
                raise AssertionError('reference Core result differs')
            result['checks'][host]={'exit_code':p.returncode,'config_accepted':p.returncode==0,
                'result':'PASS' if expected else 'FAIL','reason':None if expected else ERROR}
    return result


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source',required=True,type=Path)
    parser.add_argument('--client-archive',required=True,type=Path)
    parser.add_argument('--output',type=Path)
    args=parser.parse_args()
    result=run(args.source,args.client_archive)
    text=json.dumps(result,indent=2)+'\n'
    if args.output:args.output.write_text(text)
    print(text,end='')
    # Expected incompatibility reproduced; do not conflate harness success with compatibility.
    return 0

if __name__=='__main__':raise SystemExit(main())
