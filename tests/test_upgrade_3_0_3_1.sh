#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/testlib.sh"

fixture="$(mktemp -d)"
trap 'rm -rf -- "$fixture"' EXIT
export NOBRAND_STATE_DIR="$fixture/nobrand-oneclick/state"
export NOBRAND_CONFIG_DIR="$fixture/nobrand-oneclick/config"
export NOBRAND_LIB_DIR="$fixture/nobrand-oneclick/lib"
source_installer
nb_init_state_layout

assert_eq 3 "$NOBRAND_SCHEMA_VERSION" '3.1 keeps schema v3'
assert_eq 3.2.1 "$SCRIPT_VERSION" '3.2 maintenance version'

mkdir -p "$(dirname "$MITA_USERS_STATE")" "$NOBRAND_SNELL_STATE_DIR" \
  "$NOBRAND_HY2_STATE_DIR" "$NOBRAND_VLESS_STATE_DIR"
jq -n '{schema_version:3,deployment_model:"isolated-v2",protocol:"TCP",users:[{instance_id:"m1111111111111111",name:"alice",port:3611,password:"keep-mieru",advertise_host:"entry.example.com",advertise_port:443,enabled:true}]}' \
  >"$MITA_USERS_STATE"
jq -n '{protocol:"snell",instance_id:"s1111111111111111",name:"snell-v5",version:5,listen_port:3612,psk:"keep-snell",advertise_host:"entry.example.com",advertise_port:444,enabled:true,managed_udp:false}' \
  >"$NOBRAND_SNELL_STATE_DIR/s1111111111111111.json"
jq -n '{protocol:"hysteria2",listen_port:3613,auth:"keep-hy2",sni:"www.microsoft.com",advertise_host:"entry.example.com",advertise_port:445,enabled:true}' \
  >"$NOBRAND_HY2_STATE_FILE"
jq -n '{protocol:"vless-sudoku",listen_port:3614,uuid:"11111111-1111-4111-8111-111111111111",advertise_host:"entry.example.com",advertise_port:446,enabled:true}' \
  >"$NOBRAND_VLESS_STATE_FILE"

before="$(find "$NOBRAND_STATE_DIR" -type f -print0 | sort -z | xargs -0 sha256sum)"
ensure_manager_state_layout 0
after="$(find "$NOBRAND_STATE_DIR" -type f -print0 | sort -z | xargs -0 sha256sum)"
assert_eq "$before" "$after" 'valid 3.0 schema-v3 state is accepted without mutation'
[ ! -e "$NOBRAND_SSH_STATE_FILE" ] || fail '3.0 upgrade must not synthesize SSH state'
[ -z "$(tuic_instance_ids)" ] || fail '3.0 upgrade must not synthesize TUIC state'

pass 'NoBrand 3.0 to 3.1 optional-module compatibility'
