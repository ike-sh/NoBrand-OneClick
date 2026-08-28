#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/testlib.sh"

fixture="$(mktemp -d)"
trap 'rm -rf -- "$fixture"' EXIT
export NOBRAND_STATE_DIR="$fixture/nobrand-oneclick/state"
export NOBRAND_CONFIG_DIR="$fixture/nobrand-oneclick/config"
export NOBRAND_LIB_DIR="$fixture/nobrand-oneclick/lib"
export NOBRAND_HY2_SYSTEMD_SERVICE="$fixture/nobrand-oneclick/systemd/hy2.service"
export NOBRAND_VLESS_SYSTEMD_SERVICE="$fixture/nobrand-oneclick/systemd/vless.service"
export NOBRAND_SNELL_SYSTEMD_TEMPLATE="$fixture/nobrand-oneclick/systemd/snell.service"
source_installer
nb_init_state_layout
mkdir -p "$(dirname "$NOBRAND_HY2_SYSTEMD_SERVICE")"

public_ip() { printf '198.51.100.10'; }
require_root() { :; }
admin_lock_acquire() { :; }
admin_lock_release() { :; }
nb_service_manager() { printf none; }
nobrand_hy2_service_active() { return 1; }
nobrand_vless_sudoku_service_active() { return 1; }
snell_service_active() { return 1; }
service_calls="$fixture/service.calls"
nobrand_hy2_service_action() { printf 'hy2:%s\n' "$1" >>"$service_calls"; }
nobrand_vless_sudoku_service_action() { printf 'vless:%s\n' "$1" >>"$service_calls"; }
snell_service_action() { printf 'snell:%s:%s\n' "$1" "$2" >>"$service_calls"; }

HY2_AUTH=0123456789abcdef0123456789abcdef
HY2_SNI=www.microsoft.com
HY2_OBFS=abcdef0123456789abcdef0123456789
printf '{"listener":"unchanged"}\n' >"$NOBRAND_HY2_CONFIG_FILE"
printf 'unit-unchanged\n' >"$NOBRAND_HY2_SYSTEMD_SERVICE"
printf 'iptables|udp|3622\n' >"$NOBRAND_FIREWALL_OWNED_STATE"
state_tmp="$fixture/hy2-state.json"
hysteria2_generate_state "$state_tmp" 0.0.0.0 3622 "$HY2_AUTH" "$HY2_SNI" "$HY2_OBFS" \
  auto '' ''
nb_atomic_install_file "$state_tmp" "$NOBRAND_HY2_STATE_FILE" 0600
old_hy2_link="$(jq -r .link "$NOBRAND_HY2_STATE_FILE")"
hy2_config_hash="$(sha256sum "$NOBRAND_HY2_CONFIG_FILE")"
hy2_unit_hash="$(sha256sum "$NOBRAND_HY2_SYSTEMD_SERVICE")"
hy2_fw_hash="$(sha256sum "$NOBRAND_FIREWALL_OWNED_STATE")"
YES=1 ADVERTISE_CLI=1 ADVERTISE_AUTO_REQUESTED=0
ADVERTISE_HOST=entry.example.com ADVERTISE_PORT=443
hysteria2_set_endpoint >/dev/null
assert_eq "$hy2_config_hash" "$(sha256sum "$NOBRAND_HY2_CONFIG_FILE")" 'HY2 config isolation'
assert_eq "$hy2_unit_hash" "$(sha256sum "$NOBRAND_HY2_SYSTEMD_SERVICE")" 'HY2 unit isolation'
assert_eq "$hy2_fw_hash" "$(sha256sum "$NOBRAND_FIREWALL_OWNED_STATE")" 'HY2 firewall isolation'
[ ! -s "$service_calls" ] || fail 'HY2 endpoint update must not call service actions'
new_hy2_link="$(jq -r .link "$NOBRAND_HY2_STATE_FILE")"
[ "$old_hy2_link" != "$new_hy2_link" ] || fail 'HY2 cached link must change'
assert_contains "$new_hy2_link" 'entry.example.com:443' 'HY2 endpoint link'
hysteria2_state_set_enabled false
assert_eq false "$(hysteria2_state_field enabled)" 'HY2 false state round-trip'
hysteria2_state_set_enabled true

vless_uuid=11111111-2222-4333-8444-555555555555
vless_password=00112233445566778899aabbccddeeff
vless_state_tmp="$fixture/vless-state.json"
vless_sudoku_generate_state "$vless_state_tmp" 0.0.0.0 3623 "$vless_uuid" "$vless_password" \
  auto '' ''
nb_atomic_install_file "$vless_state_tmp" "$NOBRAND_VLESS_STATE_FILE" 0600
vless_sudoku_generate_client_config "$NOBRAND_VLESS_CLIENT_FILE" 198.51.100.10 3623 \
  "$vless_uuid" "$vless_password"
printf '{"listener":"unchanged"}\n' >"$NOBRAND_VLESS_CONFIG_FILE"
printf 'vless-unit-unchanged\n' >"$NOBRAND_VLESS_SYSTEMD_SERVICE"
vless_config_hash="$(sha256sum "$NOBRAND_VLESS_CONFIG_FILE")"
vless_unit_hash="$(sha256sum "$NOBRAND_VLESS_SYSTEMD_SERVICE")"
vless_fw_hash="$(sha256sum "$NOBRAND_FIREWALL_OWNED_STATE")"
YES=1 ADVERTISE_CLI=1 ADVERTISE_AUTO_REQUESTED=0
ADVERTISE_HOST=vless-entry.example.com ADVERTISE_PORT=9443
vless_sudoku_set_endpoint >/dev/null
assert_eq "$vless_config_hash" "$(sha256sum "$NOBRAND_VLESS_CONFIG_FILE")" 'VLESS config isolation'
assert_eq "$vless_unit_hash" "$(sha256sum "$NOBRAND_VLESS_SYSTEMD_SERVICE")" 'VLESS unit isolation'
assert_eq "$vless_fw_hash" "$(sha256sum "$NOBRAND_FIREWALL_OWNED_STATE")" 'VLESS firewall isolation'
[ ! -s "$service_calls" ] || fail 'VLESS endpoint update must not call service actions'
assert_eq vless-entry.example.com "$(vless_sudoku_state_field advertise_host)" 'VLESS display host'
assert_eq 9443 "$(vless_sudoku_state_field advertise_port)" 'VLESS display port'
assert_eq vless-entry.example.com \
  "$(jq -r '.outbounds[0].settings.vnext[0].address' "$NOBRAND_VLESS_CLIENT_FILE")" \
  'VLESS client JSON display host'

fake_runtime="$NOBRAND_SNELL_RUNTIME_DIR/snell-v5"
mkdir -p "$(dirname "$fake_runtime")"
printf '#!/bin/sh\necho snell-server v5.0.1\n' >"$fake_runtime"
chmod +x "$fake_runtime"
sid=s0123456789abcdef
snell_state_tmp="$fixture/snell-state.json"
snell_generate_state "$snell_state_tmp" "$sid" node-v5 5 0123456789abcdef 0.0.0.0 3621 auto '' ''
nb_atomic_install_file "$snell_state_tmp" "$(snell_state_path "$sid")" 0600
snell_generate_server_config "$(snell_config_path "$sid")" 5 0.0.0.0 3621 0123456789abcdef
printf 'snell-unit-unchanged\n' >"$NOBRAND_SNELL_SYSTEMD_TEMPLATE"
snell_config_hash="$(sha256sum "$(snell_config_path "$sid")")"
snell_unit_hash="$(sha256sum "$NOBRAND_SNELL_SYSTEMD_TEMPLATE")"
snell_fw_hash="$(sha256sum "$NOBRAND_FIREWALL_OWNED_STATE")"
SNELL_NAME=node-v5 YES=1 ADVERTISE_CLI=1 ADVERTISE_AUTO_REQUESTED=0
ADVERTISE_HOST=snell-entry.example.com ADVERTISE_PORT=8443
snell_set_endpoint >/dev/null
assert_eq "$snell_config_hash" "$(sha256sum "$(snell_config_path "$sid")")" 'Snell config isolation'
assert_eq "$snell_unit_hash" "$(sha256sum "$NOBRAND_SNELL_SYSTEMD_TEMPLATE")" 'Snell unit isolation'
assert_eq "$snell_fw_hash" "$(sha256sum "$NOBRAND_FIREWALL_OWNED_STATE")" 'Snell firewall isolation'
[ ! -s "$service_calls" ] || fail 'Snell endpoint update must not call service actions'
assert_eq snell-entry.example.com "$(snell_state_field "$sid" advertise_host)" 'Snell display host'
assert_eq 8443 "$(snell_state_field "$sid" advertise_port)" 'Snell display port'
assert_eq "snell:${sid}" "$(nb_endpoint_conflict_owner TCP snell-entry.example.com 8443)" 'same-transport display conflict owner'
nb_endpoint_conflict_owner UDP snell-entry.example.com 8443 >/dev/null 2>&1 \
  && fail 'TCP and UDP display endpoints with the same host/port must remain independent'

pass 'HY2, VLESS Sudoku, and Snell Display Endpoint isolation'
