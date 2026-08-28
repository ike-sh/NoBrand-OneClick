#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/testlib.sh"

fixture="$(mktemp -d)"
trap 'rm -rf -- "$fixture"' EXIT
export MITA_MANAGER_STATE_DIR="$fixture/mita-oneclick"
export NOBRAND_STATE_DIR="$fixture/nobrand-oneclick/state"
export NOBRAND_CONFIG_DIR="$fixture/nobrand-oneclick/config"
export NOBRAND_LIB_DIR="$fixture/nobrand-oneclick/lib"
source_installer
nb_init_state_layout
mkdir -p "$MITA_MANAGER_STATE_DIR"

jq -n '{protocol:"TCP",users:[
  {instance_id:"m000000000000001",name:"mieru-running",port:3601,advertise_host:"mieru.example",advertise_port:443}
]}' >"$MITA_USERS_STATE"

for major in 4 5; do
  runtime="$(snell_runtime_path "$major")"
  printf '#!/bin/sh\necho snell-server v%s.0.0\n' "$major" >"$runtime"
  chmod +x "$runtime"
done
snell_generate_state "$NOBRAND_SNELL_STATE_DIR/s0000000000000001.json" s0000000000000001 \
  snell-running 5 psk-running 0.0.0.0 3602 custom snell.example 444
snell_generate_state "$NOBRAND_SNELL_STATE_DIR/s0000000000000002.json" s0000000000000002 \
  snell-stopped 4 psk-stopped 0.0.0.0 3603 custom stopped.example 445

HY2_AUTH=0123456789abcdef0123456789abcdef
HY2_SNI=www.microsoft.com
HY2_OBFS=abcdef0123456789abcdef0123456789
hysteria2_generate_state "$NOBRAND_HY2_STATE_FILE" 0.0.0.0 3604 "$HY2_AUTH" "$HY2_SNI" "$HY2_OBFS" \
  custom hy2.example 446
vless_sudoku_generate_state "$NOBRAND_VLESS_STATE_FILE" 0.0.0.0 3606 \
  11111111-2222-4333-8444-555555555555 00112233445566778899aabbccddeeff \
  custom vless.example 447

public_ip() { printf 198.51.100.20; }
nb_service_is_active() {
  case "$1" in
    mita-oneclick@m000000000000001.service|nobrand-snell@s0000000000000001.service|nobrand-hysteria2|nobrand-vless-sudoku) return 0 ;;
    *) return 1 ;;
  esac
}
nb_port_is_listening() {
  case "$1:$2" in TCP:3601|TCP:3602|UDP:3604|TCP:3606) return 0 ;; *) return 1 ;; esac
}
nb_service_manager() { printf systemd; }

output="$(nobrand_nodes)"
assert_contains "$output" 'Mieru/TCP' 'unified Mieru node'
assert_contains "$output" 'mieru-running' 'Mieru name'
assert_contains "$output" 'Snell/v5' 'running Snell node'
assert_contains "$output" 'snell-stopped' 'stopped Snell visibility'
assert_contains "$output" 'Stopped' 'stopped state text'
assert_contains "$output" 'Hysteria2' 'unified HY2 node'
assert_contains "$output" 'VLESS/Sudoku' 'unified VLESS Sudoku node'
assert_contains "$output" 'vless.example:447/TCP' 'VLESS display endpoint'
status="$(nobrand_status)"
assert_contains "$status" 'Running: 1/1' 'Mieru aggregate status'
assert_contains "$status" 'Running: 1/2' 'Snell aggregate status'
assert_contains "$status" 'Running: yes' 'HY2 aggregate status'
assert_contains "$status" 'VLESS/Sudoku' 'VLESS aggregate status'
assert_contains "$status" 'Port: 3606' 'VLESS aggregate port'

filtered="$(NOBRAND_PROTOCOL_FILTER=snell nobrand_nodes)"
assert_contains "$filtered" 'Snell/v5' 'filtered Snell'
assert_not_contains "$filtered" 'Mieru/TCP' 'filtered out Mieru'
assert_not_contains "$filtered" 'Hysteria2|' 'filtered out HY2'
assert_not_contains "$filtered" 'VLESS/Sudoku|' 'filtered out VLESS'

vless_filtered="$(NOBRAND_PROTOCOL_FILTER=vless-sudoku nobrand_nodes)"
assert_contains "$vless_filtered" 'VLESS/Sudoku' 'filtered VLESS'
assert_not_contains "$vless_filtered" 'Snell/v5' 'filtered out Snell from VLESS view'

rm -f "$MITA_USERS_STATE"
chmod 0700 "$MITA_MANAGER_STATE_DIR"
{
  _state_kv PORT 3605
  _state_kv PROTOCOL TCP
  _state_kv USERNAME legacy-mieru
  _state_kv ADVERTISE_HOST legacy.example.com
  _state_kv ADVERTISE_PORT 10443
} >"$MITA_STATE"
chmod 0600 "$MITA_STATE"
nb_service_is_active() {
  [ "$1" = mita.service ]
}
nb_port_is_listening() {
  [ "$1:$2" = TCP:3605 ]
}
legacy="$(nb_mieru_node_rows)"
assert_contains "$legacy" 'Mieru/TCP|legacy-mieru|legacy.example.com:10443|Running|TCP' 'legacy single-instance node adapter'

pass 'unified node view and running/stopped status aggregation'
