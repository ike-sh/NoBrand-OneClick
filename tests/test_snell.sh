#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/testlib.sh"

fixture="$(mktemp -d)"
trap 'rm -rf -- "$fixture"' EXIT
export NOBRAND_STATE_DIR="$fixture/nobrand-oneclick/state"
export NOBRAND_CONFIG_DIR="$fixture/nobrand-oneclick/config"
export NOBRAND_LIB_DIR="$fixture/nobrand-oneclick/lib"
export NOBRAND_SNELL_SYSTEMD_TEMPLATE="$fixture/nobrand-oneclick/systemd/nobrand-snell@.service"
source_installer
nb_init_state_layout

release_fixture='https://dl.nssurge.com/snell/snell-server-v6.0.0rc2-linux-amd64.zip
https://dl.nssurge.com/snell/snell-server-v5.0.1-linux-amd64.zip
https://dl.nssurge.com/snell/snell-server-v4.1.1-linux-amd64.zip'
resolved="$(printf '%s\n' "$release_fixture" | snell_select_release_from_text 5 amd64)"
assert_eq $'5.0.1\thttps://dl.nssurge.com/snell/snell-server-v5.0.1-linux-amd64.zip\tStable' \
  "$resolved" 'v5 stable resolver'
resolved="$(printf '%s\n' "$release_fixture" | snell_select_release_from_text 4 amd64)"
assert_eq $'4.1.1\thttps://dl.nssurge.com/snell/snell-server-v4.1.1-linux-amd64.zip\tStable' \
  "$resolved" 'v4 stable resolver'
if printf '%s\n' "$release_fixture" | snell_select_release_from_text 6 amd64 >/dev/null 2>&1; then
  fail 'removed v6 must be rejected by the low-level release selector'
fi
if snell_resolve_release 6 >/dev/null 2>&1; then
  fail 'removed v6 must be rejected before network resolution'
fi
fixture_sha=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
hashed="$(printf '%s %s\n' 'https://dl.nssurge.com/snell/snell-server-v5.0.1-linux-amd64.zip' "$fixture_sha" \
  | snell_select_release_from_text 5 amd64)"
assert_eq $'5.0.1\thttps://dl.nssurge.com/snell/snell-server-v5.0.1-linux-amd64.zip\tStable\t'"$fixture_sha" \
  "$hashed" 'optional upstream SHA-256 resolver'
NOBRAND_TEST_ARCH=arm64
assert_eq aarch64 "$(snell_arch_asset_name)" 'arm64 official asset mapping'
assert_eq Xray-linux-arm64-v8a.zip "$(nobrand_xray_arch_asset)" 'arm64 Xray asset mapping'
NOBRAND_TEST_ARCH=amd64

for major in 4 5; do
  runtime="$(snell_runtime_path "$major")"
  printf '#!/bin/sh\necho snell-server v%s.0.1\n' "$major" >"$runtime"
  chmod +x "$runtime"
done
snell_platform_supported 4 || fail 'v4 platform support'
snell_platform_supported 5 || fail 'v5 platform support'
snell_platform_supported 6 && fail 'v6 platform path must be absent'
snell_runtime_path 6 >/dev/null 2>&1 && fail 'v6 runtime path must be absent'
snell_install_runtime 6 0 >/dev/null 2>&1 && fail 'v6 runtime install must be absent'

config4="$fixture/v4.conf"
config5_off="$fixture/v5-off.conf"
config5_on="$fixture/v5-on.conf"
snell_generate_server_config "$config4" 4 0.0.0.0 3614 psk-v4-safe
snell_generate_server_config "$config5_off" 5 0.0.0.0 3615 psk-v5-safe
snell_generate_server_config "$config5_on" 5 0.0.0.0 3615 psk-v5-safe
assert_contains "$(<"$config4")" 'ipv6 = false' 'v4 official config'
assert_contains "$(<"$config5_off")" 'ipv6 = false' 'v5 official config'
assert_eq "$(nobrand_sha256_file "$config5_off")" "$(nobrand_sha256_file "$config5_on")" \
  'QUIC ON/OFF server config golden identity'
if snell_generate_server_config "$fixture/v6.conf" 6 0.0.0.0 3616 psk-v6-safe; then
  fail 'removed v6 config generation must fail'
fi

id4=s0000000000000004
id5off=s0000000000000005
id5on=s0000000000000015
snell_generate_state "$(snell_state_path "$id4")" "$id4" node-v4 4 psk-v4-safe \
  0.0.0.0 3614 custom entry.example.com 4404
snell_generate_state "$(snell_state_path "$id5off")" "$id5off" node-v5-off 5 psk-v5-safe \
  0.0.0.0 3615 custom entry.example.com 4405 '' false
snell_generate_state "$(snell_state_path "$id5on")" "$id5on" node-v5-on 5 psk-v5-on-safe \
  0.0.0.0 3625 custom entry.example.com 4425 '' true
cp "$config4" "$(snell_config_path "$id4")"
cp "$config5_off" "$(snell_config_path "$id5off")"
snell_generate_server_config "$(snell_config_path "$id5on")" 5 0.0.0.0 3625 psk-v5-on-safe

assert_eq false "$(jq -r .quic_proxy_enabled "$(snell_state_path "$id5off")")" 'v5 default QUIC OFF state'
assert_eq false "$(jq -r .managed_udp "$(snell_state_path "$id5off")")" 'v5 default managed UDP OFF state'
assert_eq true "$(jq -r .quic_proxy_enabled "$(snell_state_path "$id5on")")" 'v5 QUIC ON state'
assert_eq true "$(jq -r .managed_udp "$(snell_state_path "$id5on")")" 'v5 managed UDP ON state'
assert_eq 'TCP|3615' "$(snell_firewall_pairs "$id5off")" 'QUIC OFF firewall pair'
assert_eq $'TCP|3625\nUDP|3625' "$(snell_firewall_pairs "$id5on")" 'QUIC ON firewall pairs'

for id in "$id4" "$id5off" "$id5on"; do
  surge="$(snell_export_surge "$id")"
  assert_contains "$surge" 'version = ' 'Surge version export'
  mihomo="$(snell_export_mihomo "$id")"
  assert_contains "$mihomo" 'type: snell' 'Mihomo Snell schema'
  singbox="$(snell_export_singbox "$id")"
  assert_eq snell "$(jq -r .type <<<"$singbox")" 'sing-box Snell schema'
done
assert_eq 4 "$(jq -r .version <<<"$(snell_export_singbox "$id5off")")" \
  'v5 sing-box compatibility version'

# A historical v6 file cannot be resolved, listed, exported, or regenerated.
historical_id=s0000000000000006
jq -n --arg id "$historical_id" '{protocol:"snell",instance_id:$id,version:6,name:"removed-v6",listen_port:3616}' \
  >"$NOBRAND_SNELL_STATE_DIR/$historical_id.json"
snell_resolve_target_id "$historical_id" >/dev/null 2>&1 \
  && fail 'historical v6 state must not resolve as a product instance'
snell_export_surge "$historical_id" >/dev/null 2>&1 \
  && fail 'historical v6 state must not export'
if snell_generate_state "$fixture/generated-v6.json" "$historical_id" removed-v6 6 psk-v6-safe \
    0.0.0.0 3616 auto '' ''; then
  fail 'removed v6 state generation must fail'
fi

snell_service_active() { return 1; }
nb_port_is_listening() { return 1; }
rows="$(snell_node_rows)"
assert_contains "$rows" 'Snell/v4|node-v4|' 'v4 node row'
assert_contains "$rows" 'Snell/v5|node-v5-off|' 'v5 OFF node row'
assert_contains "$rows" 'QUIC Off' 'v5 OFF node label'
assert_contains "$rows" 'QUIC On (UDP same port)' 'v5 ON node label'
assert_not_contains "$rows" 'removed-v6' 'v6 nodes absent'

snell_service_active() { return 0; }
nb_port_is_listening() {
  case "$1:$2" in TCP:3615|UDP:3615|TCP:3625|UDP:3625) return 0 ;; *) return 1 ;; esac
}
nb_port_listener_pids() {
  case "$1:$2" in TCP:3615|UDP:3615) printf '415\n' ;; TCP:3625|UDP:3625) printf '425\n' ;; esac
}
nb_firewall_binding_owned() {
  case "$1:$2" in TCP:3615|TCP:3625|UDP:3625) return 0 ;; *) return 1 ;; esac
}
doctor_off="$(snell_doctor_instance "$id5off")"
assert_contains "$doctor_off" '[PASS] QUIC Proxy Disabled; UDP public ownership OFF' 'OFF Doctor state'
assert_contains "$doctor_off" '[INFO] runtime auxiliary listener UDP/3615 detected' 'OFF auxiliary socket INFO'
assert_not_contains "$doctor_off" '[FAIL]' 'OFF Doctor clean'
doctor_on="$(snell_doctor_instance "$id5on")"
assert_contains "$doctor_on" '[PASS] QUIC Proxy Enabled; same-process UDP/3625 listener' 'ON Doctor socket'
assert_contains "$doctor_on" '[PASS] QUIC firewall ownership UDP/3625' 'ON Doctor firewall'
assert_not_contains "$doctor_on" '[FAIL]' 'ON Doctor clean'

nb_service_manager() { printf systemd; }
systemctl() { :; }
mkdir -p "$(dirname "$NOBRAND_SNELL_SYSTEMD_TEMPLATE")"
snell_install_service_runtime
grep -qF "ExecStart=${NOBRAND_SNELL_RUNNER} %i" "$NOBRAND_SNELL_SYSTEMD_TEMPLATE" \
  || fail 'Snell systemd template must use stable instance id'
grep -qF 'case "$version" in 4|5)' "$NOBRAND_SNELL_RUNNER" \
  || fail 'Snell runner must accept only v4/v5'
grep -qF '4|5|6' "$NOBRAND_SNELL_RUNNER" \
  && fail 'Snell runner must contain no v6 branch'

pass 'Snell v4/v5 resolver, configs, state, QUIC semantics, Doctor, nodes, and exports'
