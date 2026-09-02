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
reality_id="r$(openssl rand -hex 8)"
reality_uuid="$(tr -d '\r\n' </proc/sys/kernel/random/uuid)"
reality_public="$(openssl rand -base64 32 | tr '/+' '_-' | tr -d '=\r\n')"
reality_short="$(openssl rand -hex 8)"
reality_ingress="$NOBRAND_LEGACY_INGRESS_PROFILE_ID"
mkdir -p "$(dirname "$(reality_state_file "$reality_id")")"
reality_generate_state "$(reality_state_file "$reality_id")" "$reality_id" reality-running \
  0.0.0.0 3607 custom reality.example 448 "$reality_uuid" "$reality_public" \
  "$(reality_private_key_file "$reality_id")" "$reality_short" example.com 443 chrome / \
  "$TESTED_XRAY_VERSION" "$reality_ingress" 23607 2026-09-01T00:00:00Z

public_ip() { printf 198.51.100.20; }
nb_service_is_active() {
  case "$1" in
    nobrand-mieru@m000000000000001.service|nobrand-snell@s0000000000000001.service|nobrand-hysteria2|nobrand-vless-sudoku|"$(reality_systemd_unit "$reality_id")") return 0 ;;
    *) return 1 ;;
  esac
}
nb_port_is_listening() {
  case "$1:$2" in TCP:3601|TCP:3602|UDP:3604|TCP:3606|TCP:3607) return 0 ;; *) return 1 ;; esac
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
assert_contains "$output" 'VLESS REALITY' 'unified VLESS REALITY node'
assert_contains "$output" 'reality.example:448/TCP' 'REALITY display endpoint'
status="$(nobrand_status)"
assert_contains "$status" 'Running: 1/1' 'Mieru aggregate status'
assert_contains "$status" 'Running: 1/2' 'Snell aggregate status'
assert_contains "$status" 'Running: yes' 'HY2 aggregate status'
assert_contains "$status" 'VLESS/Sudoku' 'VLESS aggregate status'
assert_contains "$status" 'Port: 3606' 'VLESS aggregate port'
assert_contains "$status" 'Instances: 1' 'REALITY aggregate instance count'

filtered="$(NOBRAND_PROTOCOL_FILTER=snell nobrand_nodes)"
assert_contains "$filtered" 'Snell/v5' 'filtered Snell'
assert_not_contains "$filtered" 'Mieru/TCP' 'filtered out Mieru'
assert_not_contains "$filtered" 'Hysteria2|' 'filtered out HY2'
assert_not_contains "$filtered" 'VLESS/Sudoku|' 'filtered out VLESS'
assert_not_contains "$filtered" 'VLESS REALITY|' 'filtered out REALITY'

vless_filtered="$(NOBRAND_PROTOCOL_FILTER=vless-sudoku nobrand_nodes)"
assert_contains "$vless_filtered" 'VLESS/Sudoku' 'filtered VLESS'
assert_not_contains "$vless_filtered" 'Snell/v5' 'filtered out Snell from VLESS view'

reality_filtered="$(NOBRAND_PROTOCOL_FILTER=vless-reality nobrand_nodes)"
assert_contains "$reality_filtered" 'VLESS REALITY' 'filtered REALITY'
assert_not_contains "$reality_filtered" 'VLESS/Sudoku' 'filtered REALITY excludes Sudoku'

rm -f "$MITA_USERS_STATE"
[ -z "$(nb_mieru_node_rows)" ] || fail 'unified nodes must not read single-instance legacy state'

pass 'unified node view and running/stopped status aggregation'
