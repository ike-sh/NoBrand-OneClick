#!/usr/bin/env bash
set -euo pipefail
TEST_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
python3 - "$TEST_ROOT" <<'PY'
import json, pathlib, re, sys
root=pathlib.Path(sys.argv[1])
release=json.loads((root/'runtime/splicore-release.json').read_text())
assert release['version']=='v0.5.0'
assert release['commit']=='70b09da7d2758e19ba03df9ff9b9e541a669fa29'
assert release['assets']['amd64']['sha256']=='a99a419a4fe6aaaacaee25de6d7886ca5dc6e2cf31f1b67ae57f13f2a5fda5d7'
assert release['assets']['arm64']['sha256']=='c71c27dfa87c6bb55242b4be955a32fc4a9795c600f7bee73fcba3e43a4082f8'
assert 'BUILD ONLY' in release['assets']['arm64']['qualification']
assert release['capabilities']['vless-reality']['local_tunnel_guard']
assert release['capabilities']['vless-sudoku']['managed']
assert not release['capabilities']['vless-sudoku']['requires_external_xray']
assert release['capabilities']['vless-sudoku']['vless_encryption']
assert set(release['rollback_releases']) == {'v0.4.0'}
assert release['rollback_releases']['v0.4.0']['assets']['amd64']['binary_sha256'] == 'fd37493b7565c88fa6ec8291ea02300e3b7c246dcd07af02f856127ff75f766e'
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
print('[PASS] official v0.5.0 pin, architecture qualifications, ordinary download boundary and removed migration contract')
PY
