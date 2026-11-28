#!/usr/bin/env bash
set -euo pipefail
TEST_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
python3 - "$TEST_ROOT" <<'PY'
import json, pathlib, re, sys
root=pathlib.Path(sys.argv[1])
release=json.loads((root/'runtime/splicore-release.json').read_text())
assert release['version']=='v0.6.7'
assert release['commit']=='a5ecdc5785fbcf978534046517d1692613d91706'
assert set(release['assets']) == {'amd64'}
assert release['assets']['amd64']['name']=='splicore-v0.6.7-linux-amd64.tar.gz'
assert release['assets']['amd64']['sha256']=='1d93e898f5c92fa5327acdf64711f7d53e4046ce78878e884e145c316a0d46e7'
assert release['assets']['amd64']['binary_sha256']=='b650e29c13752c83d3a72d346dc73ae0844fcf16953f3811d5abb05f174403b8'
assert release['manifest_sha256']=='4aafe021a1d5bb510742e43731a0ac690afd7452a8acd4ad76ac8930ce96957c'
assert release['checksum_sha256']=='672b3fa3682f4cc346f4fc44f397608a28f78d9d36fbdbc2c1d6b092a12448ad'
assert release['capabilities']['vless-reality']['local_tunnel_guard']
assert release['capabilities']['vless-sudoku']['managed']
assert not release['capabilities']['vless-sudoku']['requires_external_xray']
assert release['capabilities']['vless-sudoku']['vless_encryption']
assert release['capabilities']['socks5']['managed']
assert release['capabilities']['socks5']['protocol_key'] == 'socks5/5/base'
assert set(release['rollback_releases']) == {'v0.4.0', 'v0.5.0', 'v0.6.4', 'v0.6.5'}
old = release['rollback_releases']['v0.6.5']
assert old['commit'] == '3c062eb21da933217f6d0bd4f2c42dc1075bb942'
assert set(old['assets']) == {'amd64'}
assert old['assets']['amd64']['sha256'] == '8ca72dc7490cb4ab28b870c1c498766e3525d4a285e439f4745e3711aaad532a'
assert old['assets']['amd64']['binary_sha256'] == '504fac4f93fac20063ca559de9fe567514ce7ff28d5d49ea8c378559e49210c0'
assert old['vless_encryption'] and old['capabilities']['socks5']['managed']
assert release['commit_witness'] and not old.get('commit_witness')
assert release['capabilities']['ss2022']['protocol_key'] == 'shadowsocks/2022/base'
assert release['rollback_releases']['v0.4.0']['assets']['amd64']['binary_sha256'] == 'fd37493b7565c88fa6ec8291ea02300e3b7c246dcd07af02f856127ff75f766e'
assert release['rollback_releases']['v0.5.0']['vless_encryption']
assert release['rollback_releases']['v0.5.0']['assets']['amd64']['binary_sha256'] == 'f27b8b9bb0bab32e7323370aa8870c1b8d5a78e95a163fa28cb31dbb60825de3'
assert release['rollback_releases']['v0.6.4']['assets']['amd64']['binary_sha256'] == 'cf861fb081b578598d3bc5e3cb4e4f6f80213b7c77afac9407709d8694a5eb84'
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
print('[PASS] official v0.6.7 release hashes, Linux amd64 and rollback-only pins')
PY

workspace="$(mktemp -d)"
trap 'rm -rf -- "$workspace"' EXIT
mkdir "$workspace/bin"
cat >"$workspace/bin/uname" <<'SH'
#!/bin/sh
case "$1" in
  -s) printf '%s\n' Linux ;;
  -m) printf '%s\n' aarch64 ;;
esac
SH
chmod +x "$workspace/bin/uname"
if output="$(PATH="$workspace/bin:$PATH" NOBRAND_SYSTEM_ROOT="$workspace" \
    NOBRAND_STATE_DIR="$workspace/state" NOBRAND_CONFIG_DIR="$workspace/config" \
    NOBRAND_LIB_DIR="$workspace/lib" NOBRAND_LIFECYCLE_DIR="$workspace/lifecycle" \
    NOBRAND_LIFECYCLE_LOCK_FILE="$workspace/lock" NOBRAND_INSTALL_SCRIPT_PATH="$workspace/installer" \
    bash "$TEST_ROOT/install-nobrand.sh" manager upgrade 2>&1)"; then
  printf 'ARM64 unexpectedly accepted\n' >&2
  exit 1
fi
[[ "$output" == *ARCH_UNSUPPORTED*"Linux amd64"* ]]
for path in state config lib lifecycle lock installer; do
  [ ! -e "$workspace/$path" ]
done
printf '[PASS] standalone installer refuses ARM64 before creating manager state or a lock\n'
