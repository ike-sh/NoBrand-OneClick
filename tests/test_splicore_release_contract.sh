#!/usr/bin/env bash
set -euo pipefail
TEST_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
python3 - "$TEST_ROOT" <<'PY'
import json, pathlib, re, sys
root=pathlib.Path(sys.argv[1])
release=json.loads((root/'runtime/splicore-release.json').read_text())
assert release['version']=='v0.6.4'
assert release['commit']=='6ff2101e76f73941ecbd780ce2cb68869cb32cee'
assert release['assets']['amd64']['sha256']=='e3bba050699ef435ce1822354cfcd4ce6e15a7938f528410656a9ec72786851d'
assert release['assets']['arm64']['sha256']=='00e1668b12dac08fdd5d95dbd0fc8d5f951a4da759170f3e76bab57f601257ff'
assert release['manifest_sha256']=='efc935552ec60f3dd598b3f9473a9ca5c499408bb2e9c651238d69035cc7739d'
assert release['checksum_sha256']=='6356e6bcff5859942e37caa18b7a5950a39c91dac0964677eff12bb064a2788b'
assert 'BUILD ONLY' in release['assets']['arm64']['qualification']
assert release['capabilities']['vless-reality']['local_tunnel_guard']
assert release['capabilities']['vless-sudoku']['managed']
assert not release['capabilities']['vless-sudoku']['requires_external_xray']
assert release['capabilities']['vless-sudoku']['vless_encryption']
assert not release['capabilities']['socks5']['managed']
assert set(release['rollback_releases']) == {'v0.4.0', 'v0.5.0'}
assert release['rollback_releases']['v0.4.0']['assets']['amd64']['binary_sha256'] == 'fd37493b7565c88fa6ec8291ea02300e3b7c246dcd07af02f856127ff75f766e'
assert release['rollback_releases']['v0.5.0']['vless_encryption']
assert release['rollback_releases']['v0.5.0']['assets']['amd64']['binary_sha256'] == 'f27b8b9bb0bab32e7323370aa8870c1b8d5a78e95a163fa28cb31dbb60825de3'
active='\n'.join(p.read_text() for folder in ('src','runtime') for p in (root/folder).glob('*') if p.is_file())
assert 'v0.3.0-rc.3' not in active
assert 'LEGACY_SUPPORTED' not in active
assert not re.search(r'Splicore/(?:releases/latest|releases/download/(?:latest|main|master|nightly)|(?:blob|raw|tree)/(?:main|master))',active)
for removed in ('migrate','legacy_tls','legacy_hysteria2','discover_legacy'):
 assert not re.search(r'^\s*def '+removed+r'\(',active,re.M), removed
for removed in ('install_snell','install_hysteria2','install_tuic','install_vless_reality','download_package','reinstall_mita_package','tuic_install_runtime','snell_install_runtime'):
 assert not re.search(r'^'+removed+r'\(\)',active,re.M), removed
assert 'sing-box/releases' not in active
assert 'enfein/mieru/releases' not in active
assert 'apernet/hysteria/releases' not in active
assert 'Native Local Tunnel Guard' in (root/'README.md').read_text() or 'Local Tunnel Guard' in (root/'README.md').read_text()
print('[PASS] official v0.6.4 pin, architecture qualifications, rollback pins and download boundary')
PY
