#!/usr/bin/env bash
set -euo pipefail
TEST_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
python3 - "$TEST_ROOT" <<'PY'
import json, pathlib, re, sys
root=pathlib.Path(sys.argv[1])
release=json.loads((root/'runtime/splicore-release.json').read_text())
assert release['version']=='v0.3.0-rc.4'
assert release['commit']=='2634ea50d19623591c5db63329a288862726db74'
assert release['assets']['amd64']['sha256']=='9dd1941c817143d18ea1c892a5fc13266c1b209600576946504a9d3c98c62161'
assert release['assets']['arm64']['sha256']=='5b5e39bd8e6ef373ebc00e7e3a8a688ce09d0369dc2c4ecfab06ed535d948b64'
assert 'BUILD ONLY' in release['assets']['arm64']['qualification']
assert release['capabilities']['vless-reality']['local_tunnel_guard']
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
print('[PASS] public rc.4 pin, architecture qualifications, ordinary download boundary and removed migration contract')
PY
