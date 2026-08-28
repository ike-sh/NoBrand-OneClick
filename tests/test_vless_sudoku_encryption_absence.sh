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

uuid='aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee'
password='ffeeddccbbaa99887766554433221100'
server="$fixture/server.json"
client="$fixture/client.json"
state="$fixture/state.json"

vless_sudoku_generate_server_config "$server" 0.0.0.0 3682 "$uuid" "$password"
vless_sudoku_generate_client_config "$client" example.com 443 "$uuid" "$password" 18082
vless_sudoku_generate_state "$state" 0.0.0.0 3682 "$uuid" "$password" custom example.com 443
vless_sudoku_state_matches "$state" || fail 'generated VLESS state schema'
vless_sudoku_forbidden_absent "$server" "$client" "$state" \
  || fail 'generated VLESS artifacts contain forbidden Encryption material'

for term in vlessenc mlkem xorpub server_ticket enc_method client_rtt vless_encryption vless_decryption decryption_secret encryption_secret; do
  grep -Eqi "$term" "$server" "$client" "$state" \
    && fail "generated artifact contains forbidden term: $term"
done

jq -e '
  .inbounds[0].settings.decryption=="none" and
  ([..|objects|to_entries[]|select((.key|ascii_downcase)=="encryption")]|length)==0
' "$server" >/dev/null || fail 'server must contain only plain decryption=none semantics'
jq -e '
  .outbounds[0].settings.vnext[0].users[0].encryption=="none" and
  ([..|objects|to_entries[]|select((.key|ascii_downcase)=="decryption")]|length)==0
' "$client" >/dev/null || fail 'client must contain only plain encryption=none semantics'
jq -e '
  ([..|objects|to_entries[]|select((.key|ascii_downcase)=="encryption" or (.key|ascii_downcase)=="decryption")]|length)==0
' "$state" >/dev/null || fail 'state must not persist VLESS Encryption keys'

if grep -En '\$NOBRAND_XRAY_BIN[^[:cntrl:]]*[[:space:]]vlessenc|(^|[;&|[:space:]])xray[[:space:]]+vlessenc' \
    "$TEST_ROOT/src/58-vless-sudoku.sh" >/dev/null; then
  fail 'VLESS implementation invokes an Encryption key-generation subcommand'
fi

jq '.outbounds[0].settings.vnext[0].users[0].encryption="native.0rtt"' "$client" \
  >"$fixture/forbidden-client.json"
vless_sudoku_forbidden_absent "$fixture/forbidden-client.json" \
  && fail 'non-none client encryption must be rejected'
jq '.inbounds[0].settings.decryption="secret-material"' "$server" \
  >"$fixture/forbidden-server.json"
vless_sudoku_forbidden_absent "$fixture/forbidden-server.json" \
  && fail 'non-none server decryption must be rejected'
jq '.client_rtt="0rtt"' "$state" >"$fixture/forbidden-state.json"
vless_sudoku_forbidden_absent "$fixture/forbidden-state.json" \
  && fail 'Encryption RTT metadata must be rejected'

jq '.transport="udp"' "$state" >"$fixture/invalid-state.json"
vless_sudoku_state_matches "$fixture/invalid-state.json" \
  && fail 'state schema must reject non-TCP transport'

printf '[PASS] VLESS_ENCRYPTION_ENABLED=false\n'
pass 'no key generation, Encryption state, secret, method, RTT, ticket, or non-none encryption'
