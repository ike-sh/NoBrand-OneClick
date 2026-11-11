"""Public Splicore Client Core probe; never substitutes a third-party server."""
import copy
import json
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import time
import uuid
from types import SimpleNamespace
import socks5_probe as socks


def probe(sc, binary, work, log, echo, node, positive=True):
    with tempfile.TemporaryDirectory(prefix='sudoku-', dir=work) as directory:
        root=Path(directory)
        runtime=sc.Runtime(root=root/'s',adapter='process')
        bootstrap=root/'bootstrap.yaml'
        # Client-only bootstrap; no NoBrand production generation pointer.
        sc.command([binary,'key','init','--file',root/'runtime/master.key'])
        sc.atomic(bootstrap,runtime.bootstrap_text(root))
        child=subprocess.Popen([str(binary),'run','--config',str(bootstrap)],stdout=log,stderr=log)
        def cli(*args, ok=True):
            return sc.command([binary,*args,'--config',bootstrap],ok=ok)
        try:
            deadline=time.monotonic()+10
            while cli('client','status',ok=False).returncode:
                if child.poll() is not None or time.monotonic()>deadline: raise AssertionError('native client startup')
                time.sleep(.05)
            cli('client','stop')
            doc=node['document']
            nid,oid,lid=[str(uuid.uuid4()) for _ in range(3)]
            with socket.socket() as s:
                s.bind(('127.0.0.1',0));port=s.getsockname()[1]
            mutations=[{'resource':'node','action':'create','node':{
                'id':nid,'name':'Sudoku native client','protocol':{'protocol':'vless','wire_version':'0','feature_profile':'plain'},
                'endpoint':doc['display_endpoint'],'transport':copy.deepcopy(doc['settings']['stream_transport']),
                'security':{'kind':'none','tls':{'enabled':False}},'options':{'schema_version':1,'data':{'security':'none','flow':'none','packet_encoding':'xudp','encryption':sc.sudoku_encryption(node)}},'metadata':{}},
                'credential':{'kind':'uuid','value':doc['users'][0]['uuid']}},
                {'resource':'outbound','action':'create','outbound':{'id':oid,'name':'Sudoku outbound','kind':'proxy','node_id':nid,'engine':'native'}},
                {'resource':'local-inbound','action':'create','local_inbound':{'id':lid,'name':'Native SOCKS','kind':'socks5','listen':{'host':'127.0.0.1','port':port},'selected_outbound':oid}}]
            for mutation in mutations:
                path,plan=root/'mutation.json',root/'plan.json'
                sc.save(path,mutation)
                cli('client','validate','--file',path)
                sc.atomic(plan,cli('client','plan','--file',path).stdout)
                cli('client','apply','--file',path,'--plan',plan)
            cli('client','start')
            args=SimpleNamespace(proxy_host='127.0.0.1',proxy_port=port,target_host='localhost',target_port=echo.tcp.server_address[1],
                                 timeout=3,size=32768,sizes=[64,512])
            succeeded=False
            try: socks.tcp_probe(args);succeeded=True
            except (OSError,RuntimeError): pass
            if succeeded!=positive: raise AssertionError('native Sudoku TCP result differs')
            if positive:
                # The UDP echo binds IPv4 only; localhost may resolve to an
                # IPv6 address with no echo listener on the hosted runner.
                args.target_host,args.target_port=echo.udp.server_address[:2]
                socks.udp_probe(args)
        finally:
            child.terminate()
            try: child.wait(timeout=10)
            except subprocess.TimeoutExpired: child.kill();child.wait(timeout=5)
