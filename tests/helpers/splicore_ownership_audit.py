#!/usr/bin/env python3
"""Opt-in ownership audit: synthetic secrets, loopback only, no host services.

Needs verified public rc.3/Xray/Mihomo caches and the isolated Go fixture.
The Go fixture links the published backend, never the Splicore daemon main.
All private fixtures are temporary; exported evidence contains no key material.
"""
import copy
import gzip
import hashlib
import json
import os
from pathlib import Path
import shutil
import socket
import socketserver
import ssl
import struct
import subprocess
import sys
import tempfile
import threading
import time
from types import SimpleNamespace
import zipfile

import splicore_blocker_probe as old
import splicore_rc2_probe as contract
import splicore_rc3_probe as rc3
import socks5_probe as socks

ROOT = Path(__file__).resolve().parents[2]
CACHE = ROOT / '.lab/splicore-rc3-audit'
AUDIT = ROOT / '.lab/splicore-ownership-audit'
BINARY = CACHE / 'amd64/splicore'
XRAY = CACHE / 'legacy-xray'
FIXTURE = AUDIT / 'tls-fixture'


def build_fixture():
    """Compile only the audit main against the retained public source tree."""
    source = CACHE / 'source/Splicore-72166d2fcda95b943cbae584bdd59876df7d0ed8'
    build = AUDIT / 'go-fixture'
    build.mkdir(parents=True, exist_ok=True)
    (build/'go.mod').write_text('module github.com/ike-sh/Splicore/auditfixture\n\ngo 1.26.3\n\n'
        'require github.com/ike-sh/Splicore v0.0.0\nreplace github.com/ike-sh/Splicore => '+str(source)+'\n')
    shutil.copyfile(source/'go.sum',build/'go.sum')
    shutil.copyfile(Path(__file__).with_name('splicore_ownership_tls.go'),build/'main.go')
    compiler = '/usr/local/go/bin/go' if Path('/usr/local/go/bin/go').is_file() else shutil.which('go')
    subprocess.run([compiler,'build','-mod=mod','-o',str(FIXTURE),'.'],cwd=build,check=True,timeout=180,
                   env=dict(os.environ,GOTOOLCHAIN='local'))
    print('isolated audit fixture built; no daemon build or source edits')


def run(argv, **kw):
    return subprocess.run([str(a) for a in argv], capture_output=True, timeout=30, **kw)


def call(argv):
    p = run(argv)
    if p.returncode:
        raise RuntimeError('audit command failed: ' + str(argv[1:3]) + ': ' + p.stderr.decode()[-300:])
    return p.stdout


def save(path, data):
    path.write_text(json.dumps(data, indent=2) + '\n')


def spawn(argv, log, **kw):
    return subprocess.Popen([str(a) for a in argv], stdout=log, stderr=log, **kw)


def tcp_via_profile(work, client, log, profile, host, port, payload=b'ownership-audit', udp_port=None):
    """No DIRECT fallback: the actual exported MATCH profile owns all traffic."""
    with tempfile.TemporaryDirectory(dir=work, prefix='client-') as directory:
        folder = Path(directory)
        local = contract.vacant_port(socket.SOCK_STREAM)
        config = folder / 'config.yaml'
        config.write_text(profile.replace('mixed-port: 7890', f'mixed-port: {local}'))
        child = spawn([client, '-d', folder, '-f', config], log)
        try:
            old.wait_port(child, local)
            with socket.create_connection(('127.0.0.1', local), 3) as s:
                s.settimeout(4)
                socks.socks_greeting(s)
                s.sendall(b'\x05\x01\x00' + socks.address_field(host) + struct.pack('!H', port))
                socks.read_reply_address(s)
                s.sendall(payload)
                if socks.recv_exact(s, len(payload)) != payload:
                    return 'INTEGRITY_FAILURE'
            if udp_port:
                args = SimpleNamespace(proxy_host='127.0.0.1', proxy_port=local, target_host='localhost',
                                       target_port=udp_port, timeout=4, sizes=[64, 512])
                socks.udp_probe(args)
            return 'PASS'
        except (OSError, RuntimeError) as exc:
            print('TCP outcome:',host,str(exc),flush=True)
            return 'BLOCKED'
        finally:
            old.stop(child)


def tls_probe(port, name, request=False):
    context = ssl._create_unverified_context()
    context.minimum_version = ssl.TLSVersion.TLSv1_3
    try:
        with socket.create_connection(('127.0.0.1', port), 3) as raw:
            raw.settimeout(3)
            with context.wrap_socket(raw, server_hostname=name) as stream:
                if request:
                    stream.sendall(b'GET / HTTP/1.0\r\nHost: localhost\r\n\r\n')
                    return 'HTTP_RESPONSE' if b'HTTP/' in stream.recv(1024) else 'NO_HTTP_RESPONSE'
                return 'TLS_HANDSHAKE'
    except (OSError, ValueError):
        return 'BLOCKED'


def raw_probe(port, payload):
    try:
        with socket.create_connection(('127.0.0.1', port), 3) as s:
            s.settimeout(3)
            s.sendall(payload)
            return 'RESPONSE' if s.recv(1024) else 'BLOCKED'
    except OSError:
        return 'BLOCKED'


class TargetHandler(socketserver.BaseRequestHandler):
    def handle(self):
        self.request.settimeout(4)
        try:
            data = self.request.recv(1024, socket.MSG_PEEK)
            if not data:
                return
            kind = 'tls' if data.startswith(b'\x16') else 'http' if data.startswith(b'GET ') else 'random'
            self.server.events.append({'bytes': kind})
            with self.server.context.wrap_socket(self.request, server_side=True) as stream:
                data = stream.recv(4096)
                if data:
                    stream.sendall(b'HTTP/1.0 200 OK\r\nContent-Length: 5\r\n\r\naudit')
        except OSError:
            pass


class Target(socketserver.ThreadingTCPServer):
    daemon_threads = True

    def __init__(self, port, cert, key):
        self.events = []
        self.context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        self.context.minimum_version = ssl.TLSVersion.TLSv1_3
        self.context.load_cert_chain(cert, key)
        self.context.set_servername_callback(lambda _s, name, _c: self.events.append({'sni': name}))
        super().__init__(('127.0.0.1', port), TargetHandler)
        threading.Thread(target=self.serve_forever, daemon=True).start()


class Core:
    def __init__(self, work, log):
        self.root = work / 'core'
        self.root.mkdir(mode=0o700)
        (self.root / 'state').mkdir(mode=0o700)
        self.bootstrap = self.root / 'bootstrap.yaml'
        self.bootstrap.write_text(f'schema: 1\nstate_directory: {self.root}/state\nkey_file: {self.root}/state/master.key\napi:\n  unix_socket: {self.root}/control.sock\n')
        call([BINARY, 'key', 'init', '--file', self.root / 'state/master.key'])
        self.child = spawn([BINARY, 'run', '--config', self.bootstrap], log)
        deadline = time.monotonic() + 10
        while time.monotonic() < deadline:
            if self.command(['inbound', 'list']).returncode == 0:
                return
            time.sleep(.05)
        raise RuntimeError('public daemon startup failed')

    def command(self, args):
        return run([BINARY] + args + ['--config', self.bootstrap])

    def admission(self, protocol, document):
        document = copy.deepcopy(document)
        document.setdefault('display_endpoint', document['listener'])
        path, plan = self.root / 'doc.json', self.root / 'plan.json'
        save(path, document)
        structural = run([BINARY, 'inbound', 'validate', '--protocol', protocol, '--file', path])
        p = self.command(['inbound', 'plan', '--protocol', protocol, '--file', path])
        phase = 'plan'
        if not p.returncode:
            plan.write_bytes(p.stdout)
            p = self.command(['inbound', 'apply', '--protocol', protocol, '--file', path, '--plan', plan])
            phase = 'apply'
        # Core errors are sanitized typed messages; no submitted document is printed.
        return {'structural_validate': structural.returncode, 'material_phase': phase,
                'returncode': p.returncode, 'error': p.stderr.decode().strip()[:500]}

    def reject_route(self):
        path, plan = self.root / 'network.json', self.root / 'network-plan.json'
        save(path, {'resource': 'network', 'action': 'replace', 'network': {
            'route': {'rules': [], 'final': {'kind': 'reject'}}, 'rule_sets': [], 'policy_groups': [],
            'dns_servers': [], 'dns_rules': [], 'dns': {'enabled': False, 'strategy': 'dual',
             'cache': {'capacity': 256}, 'timeout_seconds': 3}}})
        p = self.command(['network', 'plan', '--file', path])
        if p.returncode:
            raise RuntimeError('network composition plan failed: ' + p.stderr.decode())
        plan.write_bytes(p.stdout)
        p = self.command(['network', 'apply', '--file', path, '--plan', plan])
        if p.returncode:
            raise RuntimeError('network composition apply failed: ' + p.stderr.decode())
        return 'APPLIED'


def audit():
    assert os.geteuid() == 0, 'root only for faithful temporary legacy ownership, no host mutation'
    assert os.environ.get('NOBRAND_OWNERSHIP_NETNS') == '1'
    assert os.readlink('/proc/self/ns/net') != os.readlink('/proc/1/ns/net'), 'detached network namespace required'
    call(['ip','link','set','lo','up'])
    call(['ip','address','add','1.1.1.254/32','dev','lo'])
    expected = {'splicore': (BINARY, '737d5b2b22daafd36940c12192185922b53711e0dc24946327be4119304f1a61'),
                'xray': (XRAY, '8255dd939c34cf966cc91517b6324dd3c8d0bcf49ffac8beca049a38c46845ed')}
    for path, digest in expected.values():
        assert hashlib.sha256(path.read_bytes()).hexdigest() == digest
    evidence = {'scope': 'synthetic Linux amd64 detached network namespace; loopback only, no external route or host network mutation',
                'public_identity': json.loads(call([BINARY, 'version', '--json'])),
                'artifacts': {k: v[1] for k, v in expected.items()}, 'freeze': 'NO'}
    evidence['openssl_version']=call(['openssl','version']).decode().strip()
    evidence['openssl_config_sha256']=hashlib.sha256(Path('/etc/ssl/openssl.cnf').read_bytes()).hexdigest()
    with tempfile.TemporaryDirectory(prefix='nb-ownership-') as directory, rc3.Echo() as echo:
        work = Path(directory); work.chmod(0o700)
        log = (work / 'private.log').open('w')
        client = work / 'mihomo'
        source = ROOT / '.lab/v3.1-client/mihomo-linux-amd64-v1.19.30.gz'
        assert hashlib.sha256(source.read_bytes()).hexdigest() == old.MIHOMO_SHA256
        with gzip.open(source, 'rb') as stream:
            client.write_bytes(stream.read())
        client.chmod(0o700)
        with zipfile.ZipFile(CACHE / 'Xray-linux-64.zip') as archive:
            for name in ('geoip.dat', 'geosite.dat'):
                (work / name).write_bytes(archive.read(name))
        private, public = old.keypair(work)
        rp, hp, tp = contract.vacant_port(socket.SOCK_STREAM), contract.vacant_port(socket.SOCK_DGRAM), contract.vacant_port(socket.SOCK_STREAM)
        root = work / 'legacy'
        old.legacy_fixture(root, private, public, rp, hp, tp)
        cert = root / 'config/hysteria2/hysteria2-cert.pem'
        key = root / 'config/hysteria2/hysteria2-key.pem'
        original_hash = [hashlib.sha256(p.read_bytes()).hexdigest() for p in (cert, key)]
        call([FIXTURE, 'mint', work, cert, key])
        certs = {'old': (cert, key, cert),
                 'san_ca': (work/'san-ca.pem', work/'san-ca-key.pem', work/'san-ca.pem'),
                 'same_ca_leaf': (work/'same-ca-leaf.pem', work/'same-ca-leaf-key.pem', cert),
                 'new_ca_leaf': (work/'new-leaf.pem', work/'new-leaf-key.pem', work/'new-ca.pem'),
                 'expired': (work/'expired.pem', work/'expired-key.pem', cert),
                 'wrong_eku': (work/'wrong-eku.pem', work/'wrong-eku-key.pem', cert),
                 'wrong_ku': (work/'wrong-ku.pem', work/'wrong-ku-key.pem', cert),
                 'absent_usage': (work/'absent-usage.pem', work/'absent-usage-key.pem', cert)}
        inventory = {name: json.loads(call([FIXTURE,'inspect',c,k,ca,'probe.example'])) for name,(c,k,ca) in certs.items()}
        evidence['certificates'] = inventory
        pin = inventory['old']['sha256']
        evidence['go_tls'] = {name: json.loads(call([FIXTURE,'tls',c,k,cert,'probe.example',pin]))
                              for name,(c,k,_) in certs.items()}
        evidence['go_tls']['san_ca_own_trust']=json.loads(call([FIXTURE,'tls',work/'san-ca.pem',work/'san-ca-key.pem',work/'san-ca.pem','probe.example',inventory['san_ca']['sha256']]))
        core = Core(work, log)
        processes = [core.child]
        try:
            evidence['certificate_admission'] = {}
            for name,(c,k,ca) in certs.items():
                doc = {'schema':1,'name':'cert-'+name,'listener':{'host':'127.0.0.1','port':contract.vacant_port(socket.SOCK_DGRAM)},
                       'settings':{'tls':{'server_name':'probe.example','certificate_file':str(c),'private_key_file':str(k),'ca_certificate':ca.read_text()}},
                       'users':[{'account_name':'cert-'+name,'password':'synthetic-hy2-auth'}]}
                evidence['certificate_admission'][name] = core.admission('hysteria2',doc)
                evidence['certificate_admission'][name]['published_snapshot']=json.loads(call([FIXTURE,'snapshot',c,k,ca,'probe.example']))
            bad = copy.deepcopy(doc);bad['name']='bad-pair';bad['users'][0]['account_name']='bad-pair'
            bad['settings']['tls']['private_key_file']=str(work/'san-ca-key.pem')
            evidence['certificate_admission']['key_mismatch'] = core.admission('hysteria2',bad)
            evidence['certificate_admission']['key_mismatch']['published_snapshot']=json.loads(call([FIXTURE,'snapshot',certs['absent_usage'][0],work/'san-ca-key.pem',cert,'probe.example']))
            try:
                rc3.sc.tls_check({'server_name':'probe.example','certificate_file':str(cert),'private_key_file':str(key),'ca_certificate':cert.read_text()})
                adapter='UNEXPECTED_ACCEPT'
            except rc3.sc.Failure as exc:
                adapter=exc.category+': '+str(exc)
            evidence['nobrand_old_certificate_gate']=adapter
            print('certificate admission matrix complete',flush=True)
            save(AUDIT/'probe-partial.json',evidence)
            original = rc3.hy2_profile((root/'legacy-hy2-client.yaml').read_text())
            evidence['hy2']={}
            config = root/'config/hysteria2/config.json'
            server=spawn([XRAY,'run','-c',config],log);processes.append(server);time.sleep(.4)
            evidence['hy2']['legacy_xray_old_cert']=tcp_via_profile(work,client,log,original,'localhost',echo.tcp.server_address[1],udp_port=echo.udp.server_address[1])
            old.stop(server)
            for name in ('old','same_ca_leaf','new_ca_leaf'):
                c,k,_=certs[name]
                server=spawn([FIXTURE,'hy2',c,k,hp],log);processes.append(server);time.sleep(.5)
                evidence['hy2']['public_backend_'+name]=tcp_via_profile(work,client,log,original,'localhost',echo.tcp.server_address[1],udp_port=echo.udp.server_address[1])
                if name=='old':
                    evidence['hy2']['old_cert_wrong_auth']=tcp_via_profile(work,client,log,original.replace('synthetic-hy2-auth','wrong-auth'),'localhost',echo.tcp.server_address[1])
                    evidence['hy2']['old_cert_verified_client']=tcp_via_profile(work,client,log,original.replace('skip-cert-verify: true','skip-cert-verify: false'),'localhost',echo.tcp.server_address[1])
                old.stop(server)
            evidence['hy2']['unchanged_export_profile_sha256']=hashlib.sha256(original.encode()).hexdigest()
            print('HY2 isolated backend and rotation matrix complete',flush=True)
            save(AUDIT/'probe-partial.json',evidence)
            # Actual generated legacy topology. Synthetic target name localhost
            # avoids any DNS override, hosts edit, external target or sidecar.
            reality_config=root/'config/vless-reality/instances'/old.IDENT/'config.json'
            generated=json.loads(reality_config.read_text())
            generated=json.loads(json.dumps(generated).replace('probe.example','localhost'))
            # Deterministic process-local DNS for the synthetic hostname only.
            generated['dns']={'hosts':{'localhost':'127.0.0.1'}}
            for outbound in generated['outbounds']:
                if outbound['protocol']=='freedom':
                    outbound.setdefault('settings',{})['domainStrategy']='UseIPv4'
            generated['inbounds'][1]['port']=contract.vacant_port(socket.SOCK_STREAM)
            generated['inbounds'][0]['streamSettings']['realitySettings']['target']='127.0.0.1:'+str(generated['inbounds'][1]['port'])
            save(reality_config,generated)
            target=Target(tp,work/'same-ca-leaf.pem',work/'same-ca-leaf-key.pem')
            public_echo=socketserver.ThreadingTCPServer(('1.1.1.254',0),rc3.TCP)
            public_echo.daemon_threads=True
            threading.Thread(target=public_echo.serve_forever,daemon=True).start()
            dangerous=socketserver.ThreadingTCPServer(('1.1.1.254',25),rc3.TCP)
            dangerous.daemon_threads=True
            threading.Thread(target=dangerous.serve_forever,daemon=True).start()
            reality_profile=(root/'legacy-reality-client.yaml').read_text().replace('probe.example','localhost')
            reality={'schema':1,'name':'ownership-reality','listener':{'host':'127.0.0.1','port':rp},
                     'settings':{'security':'reality','flow':'xtls-rprx-vision','transport':'tcp','packet_encoding':'xudp',
                     'reality':{'public_key':public,'short_ids':['0123456789abcdef'],'server_name':'localhost','target':{'host':'127.0.0.1','port':tp}}},
                     'server_secret':{'private_key':private},'users':[{'account_name':'ownership-reality','uuid':old.UUID}]}
            matrix={}
            for which in ('legacy','rc3'):
                if which=='legacy':
                    server=spawn([XRAY,'run','-c',reality_config],log,env=dict(os.environ,XRAY_LOCATION_ASSET=str(work)))
                    processes.append(server);old.wait_port(server,rp)
                else:
                    admitted=core.admission('vless',reality)
                    assert admitted['returncode']==0,admitted
                matrix[which]={}
                for label,profile in [('valid',reality_profile),('wrong_uuid',reality_profile.replace(old.UUID,'22222222-2222-4222-8222-222222222222')),
                                      ('wrong_short_id',reality_profile.replace('0123456789abcdef','fedcba9876543210')),
                                      ('wrong_sni',reality_profile.replace('servername: "localhost"','servername: "unexpected.invalid"'))]:
                    if label != 'valid':
                        assert profile != reality_profile, 'negative profile mutation did not apply'
                    matrix[which][label]=tcp_via_profile(work,client,log,profile,'1.1.1.254',public_echo.server_address[1])
                matrix[which]['private_ip_destination']=tcp_via_profile(work,client,log,reality_profile,'127.0.0.1',echo.tcp.server_address[1])
                matrix[which]['dangerous_tcp_25']=tcp_via_profile(work,client,log,reality_profile,'1.1.1.254',25)
                matrix[which]['bittorrent']=tcp_via_profile(work,client,log,reality_profile,'1.1.1.254',public_echo.server_address[1],b'\x13BitTorrent protocol'+bytes(48))
                observations={}
                for label,probe in [
                    ('plain_tls_expected_sni',lambda:tls_probe(rp,'localhost')),
                    ('plain_tls_wrong_sni',lambda:tls_probe(rp,'unexpected.invalid')),
                    ('fallback_http_over_tls',lambda:tls_probe(rp,'localhost',True)),
                    ('plaintext_http',lambda:raw_probe(rp,b'GET / HTTP/1.0\r\nHost: localhost\r\n\r\n')),
                    ('random_tcp',lambda:raw_probe(rp,b'ownership-random-probe'))]:
                    before=len(target.events)
                    matrix[which][label]=probe()
                    time.sleep(.1)
                    observations[label]=target.events[before:]
                matrix[which]['target_observations']=observations
                if which=='legacy':
                    defender=generated['inbounds'][1]['port']
                    matrix[which]['defender_direct_expected_sni']=tls_probe(defender,'localhost')
                    matrix[which]['defender_direct_wrong_sni']=tls_probe(defender,'unexpected.invalid')
                    old.stop(server)
                print('REALITY '+which+' matrix complete',flush=True)
                evidence['reality']=matrix
                save(AUDIT/'probe-partial.json',evidence)
            matrix['rc3']['network_final_reject']=core.reject_route()
            query=core.root/'query.json'
            save(query,{'ip':'127.0.0.1','port':echo.tcp.server_address[1],'network':'tcp'})
            explained=core.command(['route','explain','--file',query])
            assert explained.returncode==0,explained.stderr.decode()
            matrix['rc3']['route_explain_after_reject']=json.loads(explained.stdout)
            matrix['rc3']['private_ip_after_network_final_reject']=tcp_via_profile(work,client,log,reality_profile,'127.0.0.1',echo.tcp.server_address[1])
            evidence['reality']=matrix
            dangerous.shutdown();dangerous.server_close()
            public_echo.shutdown();public_echo.server_close()
            target.shutdown();target.server_close()
            assert [hashlib.sha256(p.read_bytes()).hexdigest() for p in (cert,key)]==original_hash
            evidence['original_certificate_key_bytes_unchanged']=True
            # Positive controls must pass before negative outcomes are evidence.
            assert all(evidence['hy2'][k]=='PASS' for k in ('legacy_xray_old_cert','public_backend_old','public_backend_same_ca_leaf','public_backend_new_ca_leaf'))
            assert all(matrix[k]['valid']=='PASS' for k in ('legacy','rc3'))
            assert all(matrix[k][n]=='BLOCKED' for k in ('legacy','rc3') for n in ('wrong_uuid','wrong_short_id','wrong_sni'))
            assert all(matrix['legacy'][n]=='BLOCKED' and matrix['rc3'][n]=='PASS' for n in ('private_ip_destination','dangerous_tcp_25','bittorrent'))
            assert matrix['rc3']['route_explain_after_reject']['action']['kind']=='reject'
            assert matrix['rc3']['private_ip_after_network_final_reject']=='PASS'
            assert evidence['go_tls']['san_ca_own_trust']['ca_hostname']=='PASS'
            assert evidence['certificate_admission']['wrong_ku']['returncode']==0
            evidence['audit_assertions']='PASS; includes expected policy counterexamples, not migration acceptance'
        finally:
            for p in reversed(processes):old.stop(p)
            log.close()
            shutil.copyfile(work/'private.log',AUDIT/'private-runtime.log')
    save(AUDIT/'probe.json',evidence)
    print('sanitized evidence written',flush=True)


if __name__=='__main__':
    if sys.argv[1:]==['--build-fixture']:
        build_fixture()
    elif sys.argv[1:]:
        raise SystemExit('usage: splicore_ownership_audit.py [--build-fixture]')
    else:
        audit()
