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

uuid='11111111-2222-4333-8444-555555555555'
password='00112233445566778899aabbccddeeff'
port=3681
host='entry.example.com'
server="$fixture/nobrand-server.json"
client="$fixture/nobrand-client.json"
reference="$fixture/xray-oneclick-reference.json"
reference_canonical="$fixture/reference.canonical.json"
nobrand_canonical="$fixture/nobrand.canonical.json"

vless_sudoku_generate_server_config "$server" 0.0.0.0 "$port" "$uuid" "$password"

# Canonical reference derived from Xray-OneClick commit
# 5b6a049f1c24469c79e233989248deb9ecf3481c, lib/50-vless-enc.sh:331-362.
jq -n --arg uuid "$uuid" --arg port "$port" --arg password "$password" '{
  tag:"vless-enc-tcp-finalmask-in",
  listen:"0.0.0.0",
  port:($port|tonumber),
  protocol:"vless",
  settings:{
    clients:[{id:$uuid,email:"tcp-finalmask@xray"}],
    decryption:"REFERENCE_VLESS_ENCRYPTION_SECRET"
  },
  streamSettings:{
    network:"tcp",
    security:"none",
    finalmask:{tcp:[{type:"sudoku",settings:{
      password:$password,
      ascii:"prefer_ascii",
      paddingMin:0,
      paddingMax:3
    }}]}
  },
  sniffing:{enabled:true,destOverride:["http","tls"]}
}' >"$reference"

# Allowed differences: tag/branding email and the removed Encryption decryption
# secret. All transport and FinalMask/Sudoku semantics must compare byte-for-byte
# after jq canonicalization.
jq -S 'del(.tag,.settings.clients[].email,.settings.decryption)' "$reference" \
  >"$reference_canonical"
jq -S '.inbounds[0] | del(.tag,.settings.clients[].email,.settings.decryption)' "$server" \
  >"$nobrand_canonical"
diff -u "$reference_canonical" "$nobrand_canonical" \
  || fail 'NoBrand VLESS FinalMask/Sudoku inbound differs from canonical Xray-OneClick behavior'

jq -e --arg uuid "$uuid" --arg password "$password" --arg port "$port" '
  (.inbounds|length)==1 and
  .inbounds[0].protocol=="vless" and
  .inbounds[0].port==($port|tonumber) and
  .inbounds[0].settings.decryption=="none" and
  .inbounds[0].settings.clients[0].id==$uuid and
  .inbounds[0].streamSettings.network=="tcp" and
  .inbounds[0].streamSettings.security=="none" and
  .inbounds[0].streamSettings.finalmask=={
    tcp:[{type:"sudoku",settings:{password:$password,ascii:"prefer_ascii",paddingMin:0,paddingMax:3}}]
  }
' "$server" >/dev/null || fail 'plain VLESS server golden semantics'

vless_sudoku_generate_client_config "$client" "$host" 443 "$uuid" "$password" 18081
jq -e --arg uuid "$uuid" --arg password "$password" --arg host "$host" '
  (.inbounds|length)==1 and
  .inbounds[0].listen=="127.0.0.1" and
  .inbounds[0].port==18081 and
  .inbounds[0].protocol=="socks" and
  .outbounds[0].protocol=="vless" and
  .outbounds[0].settings.vnext==[{
    address:$host,port:443,users:[{id:$uuid,encryption:"none"}]
  }] and
  .outbounds[0].streamSettings.network=="tcp" and
  .outbounds[0].streamSettings.security=="none" and
  .outbounds[0].streamSettings.finalmask=={
    tcp:[{type:"sudoku",settings:{password:$password,ascii:"prefer_ascii",paddingMin:0,paddingMax:3}}]
  }
' "$client" >/dev/null || fail 'plain VLESS client golden semantics'

link="$(vless_sudoku_build_share_link "$uuid" "$host" 443 "$(vless_sudoku_finalmask_json "$password")")"
assert_contains "$link" "vless://${uuid}@${host}:443?type=tcp" 'VLESS URL display endpoint'
assert_contains "$link" 'security=none&encryption=none' 'VLESS URL plain semantics'
assert_contains "$link" '%22type%22%3A%22sudoku%22' 'VLESS URL FinalMask encoding'

placeholder="$fixture/placeholder-client.json"
vless_sudoku_generate_client_config "$placeholder" YOUR_SERVER_IP 443 "$uuid" "$password" 18082 \
  || fail 'auto endpoint placeholder must remain exportable when public detection is unavailable'

if [ -n "${NOBRAND_XRAY_TEST_BIN:-}" ]; then
  nobrand_xray_test_config "$server" "$NOBRAND_XRAY_TEST_BIN" \
    || fail 'real Xray rejected golden VLESS Sudoku server config'
  nobrand_xray_test_config "$client" "$NOBRAND_XRAY_TEST_BIN" \
    || fail 'real Xray rejected golden VLESS Sudoku client config'
  printf '[PASS] VLESS Sudoku golden server/client validated by the same real Xray runtime\n'
else
  printf '[SKIP] real Xray validation inside golden test (covered by --runtime)\n'
fi

pass 'VLESS FinalMask/Sudoku canonical server, client JSON, and share link golden'
