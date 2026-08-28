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

config="$fixture/golden.json"
auth='0123456789abcdef0123456789abcdef'
obfs='abcdef0123456789abcdef0123456789'
sni='www.microsoft.com'
hysteria2_generate_config "$config" 0.0.0.0 3622 "$auth" "$sni" "$obfs" /cert.pem /key.pem
jq -e --arg auth "$auth" --arg obfs "$obfs" '
  .inbounds|length==1 and
  .[0].protocol=="hysteria" and
  .[0].settings.version==2 and
  .[0].settings.clients==[{"auth":$auth,"email":"hysteria2@xray"}] and
  .[0].streamSettings.network=="hysteria" and
  .[0].streamSettings.security=="tls" and
  .[0].streamSettings.tlsSettings.alpn==["h3"] and
  .[0].streamSettings.tlsSettings.certificates==[{"certificateFile":"/cert.pem","keyFile":"/key.pem"}] and
  .[0].streamSettings.hysteriaSettings.version==2 and
  .[0].streamSettings.finalmask.udp==[{"type":"salamander","settings":{"password":$obfs}}]
' "$config" >/dev/null || fail 'HY2 Xray JSON does not match golden semantics'

link="$(hysteria2_build_share_link 'auth +/%' '2001:db8::1' 443 'sni.example' 'obfs +/%' 'NoBrand HY2')"
assert_contains "$link" 'hysteria2://auth%20%2B%2F%25@[2001:db8::1]:443?' 'URI authority/IPv6'
assert_contains "$link" 'sni=sni.example' 'URI SNI'
assert_contains "$link" 'alpn=h3' 'URI ALPN'
assert_contains "$link" 'insecure=1' 'URI insecure'
assert_contains "$link" 'obfs=salamander' 'URI Salamander'
assert_contains "$link" 'obfs-password=obfs%20%2B%2F%25' 'URI obfs encoding'
assert_contains "$link" '#NoBrand%20HY2' 'URI label encoding'

hysteria2_generate_state "$NOBRAND_HY2_STATE_FILE" 0.0.0.0 3622 "$auth" "$sni" "$obfs" \
  custom 211.136.162.185 16808
mihomo="$(hysteria2_export_mihomo)"
assert_contains "$mihomo" 'type: hysteria2' 'HY2 Mihomo type'
assert_contains "$mihomo" 'server: "211.136.162.185"' 'HY2 Mihomo Display Endpoint'
assert_contains "$mihomo" 'port: 16808' 'HY2 Mihomo port'
assert_contains "$mihomo" 'skip-cert-verify: true' 'HY2 Mihomo self-signed TLS'
assert_contains "$mihomo" 'obfs: salamander' 'HY2 Mihomo Salamander'
singbox="$(hysteria2_export_singbox)"
jq -e --arg auth "$auth" --arg obfs "$obfs" --arg sni "$sni" '
  .type=="hysteria2" and .server=="211.136.162.185" and .server_port==16808 and
  .password==$auth and .obfs=={"type":"salamander","password":$obfs} and
  .tls.enabled==true and .tls.server_name==$sni and .tls.insecure==true and .tls.alpn==["h3"]
' <<<"$singbox" >/dev/null || fail 'HY2 sing-box exporter golden semantics'

pass 'HY2 golden Xray JSON, URI, Mihomo, and sing-box exports'
