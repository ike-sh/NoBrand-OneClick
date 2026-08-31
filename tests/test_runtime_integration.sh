#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/testlib.sh"

fixture="$(mktemp -d)"
server_pid="" client_pid="" target_pid=""
cleanup() {
  [ -z "$client_pid" ] || kill "$client_pid" >/dev/null 2>&1 || true
  [ -z "$server_pid" ] || kill "$server_pid" >/dev/null 2>&1 || true
  [ -z "$target_pid" ] || kill "$target_pid" >/dev/null 2>&1 || true
  rm -rf -- "$fixture"
}
trap cleanup EXIT
export NOBRAND_STATE_DIR="$fixture/nobrand-oneclick/state"
export NOBRAND_CONFIG_DIR="$fixture/nobrand-oneclick/config"
export NOBRAND_LIB_DIR="$fixture/nobrand-oneclick/lib"
source_installer
nb_init_state_layout

if ! command -v unzip >/dev/null 2>&1; then
  chmod 0755 "$TEST_ROOT/tests/helpers/unzip"
  PATH="$TEST_ROOT/tests/helpers:$PATH"
  export PATH
fi
for command_name in curl jq unzip openssl python3 ss; do
  command -v "$command_name" >/dev/null 2>&1 || fail "runtime integration dependency missing: $command_name"
done

xray_candidate="$fixture/xray"
nobrand_download_xray_candidate "$xray_candidate"
chmod +x "$xray_candidate"
# Read indirectly by nobrand_xray_version from the sourced installer.
# shellcheck disable=SC2034
NOBRAND_XRAY_BIN="$xray_candidate"
xray_version="$(nobrand_xray_version)"
[ -n "$xray_version" ] || fail 'real Xray version detection'
HY2_SNI=www.microsoft.com
generate_hysteria2_cert
config="$fixture/hy2-real.json"
hysteria2_generate_config "$config" 127.0.0.1 45672 \
  0123456789abcdef0123456789abcdef "$HY2_SNI" abcdef0123456789abcdef0123456789
nobrand_xray_test_config "$config" "$xray_candidate" || fail 'real Xray run -test rejected golden HY2 config'
printf '[PASS] real Xray-core %s Hysteria2 config test\n' "$xray_version"

NOBRAND_XRAY_TEST_BIN="$xray_candidate" bash "$TEST_ROOT/tests/test_vless_sudoku_golden.sh"
vless_server="$fixture/vless-server.json"
vless_client="$fixture/vless-client.json"
vless_uuid='11111111-2222-4333-8444-555555555555'
vless_password='00112233445566778899aabbccddeeff'
vless_sudoku_generate_server_config "$vless_server" 127.0.0.1 45673 \
  "$vless_uuid" "$vless_password"
vless_sudoku_generate_client_config "$vless_client" 127.0.0.1 45673 \
  "$vless_uuid" "$vless_password" 18083
nobrand_xray_test_config "$vless_server" "$xray_candidate" \
  || fail 'real Xray rejected VLESS Sudoku server config'
nobrand_xray_test_config "$vless_client" "$xray_candidate" \
  || fail 'real Xray rejected VLESS Sudoku client config'

python3 -m http.server 45674 --bind 127.0.0.1 >"$fixture/target.log" 2>&1 &
target_pid=$!
"$xray_candidate" run -c "$vless_server" >"$fixture/vless-server.log" 2>&1 &
server_pid=$!
"$xray_candidate" run -c "$vless_client" >"$fixture/vless-client.log" 2>&1 &
client_pid=$!
for _ in {1..30}; do
  if ss -lnt | grep -qE '127\.0\.0\.1:45673[[:space:]]' \
     && ss -lnt | grep -qE '127\.0\.0\.1:18083[[:space:]]' \
     && ss -lnt | grep -qE '127\.0\.0\.1:45674[[:space:]]'; then
    break
  fi
  sleep 0.2
done
ss -lnt | grep -qE '127\.0\.0\.1:45673[[:space:]]' || fail 'real VLESS Sudoku server listener'
ss -lnt | grep -qE '127\.0\.0\.1:18083[[:space:]]' || fail 'real VLESS Sudoku client SOCKS listener'
curl -fsS --max-time 15 --noproxy '' --socks5-hostname 127.0.0.1:18083 \
  http://127.0.0.1:45674/ >/dev/null || {
    sed -n '1,80p' "$fixture/vless-server.log" >&2 || true
    sed -n '1,80p' "$fixture/vless-client.log" >&2 || true
    fail 'real FinalMask/Sudoku localhost data plane'
  }
printf '[PASS] real Xray-core %s plain VLESS + FinalMask/Sudoku TCP data plane\n' "$xray_version"

for major in 4 5; do
  snell_install_runtime "$major" 1
  candidate="$(snell_runtime_path "$major")"
  version="$(snell_runtime_reported_version "$candidate")"
  release_version="$(snell_runtime_release_version "$major")"
  release_status="$(snell_runtime_release_status "$major")"
  [[ "$version" = "$major".* ]] || fail "Snell v${major} runtime reported ${version}"
  [[ "$release_version" = "$major".* ]] || fail "Snell v${major} official release metadata is ${release_version}"
  jq -e --arg major "$major" --arg release "$release_version" \
    '.major==($major|tonumber) and .release_version==$release and (.source_url|startswith("https://dl.nssurge.com/snell/")) and (.sha256|test("^[0-9a-f]{64}$"))' \
    "$(snell_runtime_metadata_path "$major")" >/dev/null || fail "Snell v${major} runtime metadata"
  psk="integration-psk-v${major}"
  snell_validate_runtime_config "$candidate" "$major" "$psk" \
    || fail "real Snell v${major} temporary localhost listener validation"
  printf '[PASS] real Surge Snell v%s release %s (%s), binary reports %s, localhost listener\n' \
    "$major" "$release_version" "$release_status" "$version"
done

snell_install_runtime 6 1 >/dev/null 2>&1 \
  && fail 'removed Snell v6 runtime must not be downloadable'

pass 'real upstream Xray and Surge Snell runtime integration'
