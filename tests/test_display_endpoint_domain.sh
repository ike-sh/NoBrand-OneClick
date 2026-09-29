#!/usr/bin/env bash
# Fixture globals are read by functions sourced from the generated installer.
# shellcheck disable=SC2034
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/testlib.sh"

fixture="$(mktemp -d)"
trap 'rm -rf -- "$fixture"' EXIT
export NOBRAND_STATE_DIR="$fixture/state"
export NOBRAND_CONFIG_DIR="$fixture/config"
export NOBRAND_LIB_DIR="$fixture/lib"
source_installer
nb_init_state_layout
public_ip() { printf '198.51.100.20'; }

host=edge.example.com
for candidate in 203.0.113.30 2001:db8::10 "$host" node-01.example.net \
  xn--example-test.example; do
  nb_validate_advertise_endpoint "$candidate" 443 TCP \
    || fail "valid client Display Endpoint rejected: $candidate"
done
for candidate in '' 999.999.999.999 256.1.1.1 1.2.3.999 \
  http://example.com https://example.com example.com/path example.com:443 \
  -example.com example-.com example..com 'bad host.example' \
  $'example.com\n' $'example.com\001'; do
  if nb_validate_advertise_endpoint "$candidate" 443 TCP; then
    fail "invalid client Display Endpoint accepted: $candidate"
  fi
done
nb_validate_advertise_endpoint "$host" 443 TCP \
  || fail 'syntactically valid hostname must not require DNS resolution'
forward_target_valid realm "$host" || fail 'Realm target domain rejected'
if forward_target_valid nftables "$host"; then
  fail 'nftables target accepted DNS hostname'
fi
pass 'client host syntax accepts IP and DNS, rejects malformed hosts without resolving DNS'

# Mieru's existing user-add test covers persisted user state. Exercise all
# client formats here with an independent domain and no DNS dependency.
USERNAME=alice PASSWORD=dummy-password PORT=3611 PORT_RANGE="" PROTOCOL=TCP
ADVERTISE_HOST="$host" ADVERTISE_PORT=443 MTU=1400
assert_contains "$(build_client_json_for "$host" TCP)" \
  '"domainName": "edge.example.com"' 'Mieru official client domain'
assert_contains "$(build_clash_yaml_full "$host")" \
  'server: "edge.example.com"' 'Mieru Mihomo domain'
assert_contains "$(generate_share_link_for "$host" TCP)" \
  '@edge.example.com' 'Mieru URI domain'

snell4=s1111111111111111
snell5=s2222222222222222
for spec in "$snell4:4" "$snell5:5"; do
  id="${spec%%:*}" major="${spec#*:}"
  snell_generate_state "$(snell_state_path "$id")" "$id" "node-$major" \
    "$major" dummy-psk 0.0.0.0 3612 custom "$host" 443
  assert_eq "$host" "$(snell_state_field "$id" advertise_host)" "Snell v$major state"
  assert_contains "$(snell_export_surge "$id")" "snell, $host, 443" "Snell v$major Surge"
  assert_contains "$(snell_export_mihomo "$id")" "server: \"$host\"" "Snell v$major Mihomo"
  assert_eq "$host" "$(snell_export_singbox "$id" | jq -r .server)" "Snell v$major sing-box"
done

hysteria2_generate_state "$NOBRAND_HY2_STATE_FILE" 0.0.0.0 3613 \
  dummy-auth www.example.org dummy-obfs custom "$host" 443
assert_eq "$host" "$(hysteria2_state_field advertise_host)" 'Hysteria2 state'
assert_contains "$(hysteria2_current_share_link)" "@$host:443" 'Hysteria2 URI'
assert_contains "$(hysteria2_export_mihomo)" "server: \"$host\"" 'Hysteria2 Mihomo'
assert_eq "$host" "$(hysteria2_export_singbox | jq -r .server)" 'Hysteria2 sing-box'
assert_eq www.example.org "$(hysteria2_export_singbox | jq -r .tls.server_name)" \
  'Hysteria2 connection host and SNI stay separate'

uuid=11111111-2222-4333-8444-555555555555
password=00112233445566778899aabbccddeeff
vless_sudoku_generate_state "$NOBRAND_VLESS_STATE_FILE" 0.0.0.0 3614 \
  "$uuid" "$password" custom "$host" 443
vless_sudoku_generate_client_config "$NOBRAND_VLESS_CLIENT_FILE" "$host" 443 \
  "$uuid" "$password"
assert_eq "$host" "$(vless_sudoku_state_field advertise_host)" 'VLESS FinalMask state'
assert_eq "$host" "$(jq -r '.outbounds[0].settings.vnext[0].address' \
  "$NOBRAND_VLESS_CLIENT_FILE")" 'VLESS FinalMask Xray client'
assert_contains "$(vless_sudoku_current_share_link)" "@$host:443" 'VLESS FinalMask URI'

tuic_id=t1111111111111111
users='[{"user_id":"u1111111111111111","name":"alice","uuid":"11111111-1111-4111-8111-111111111111","password":"dummy-password"}]'
mkdir -p "$(dirname "$(tuic_state_file "$tuic_id")")"
tuic_generate_state "$(tuic_state_file "$tuic_id")" "$tuic_id" tuic-edge \
  0.0.0.0 3615 custom "$host" 443 www.example.org stable 1.13.20 \
  "$fixture/tuic-cert.pem" "$fixture/tuic-key.pem" "$users"
assert_eq "$host" "$(tuic_state_field "$tuic_id" advertise_host)" 'TUIC state'
assert_contains "$(tuic_export_mihomo "$tuic_id" alice)" \
  "server: \"$host\"" 'TUIC Mihomo'
assert_eq "$host" "$(tuic_export_singbox "$tuic_id" alice | jq -r .outbounds[0].server)" \
  'TUIC sing-box'
assert_eq www.example.org \
  "$(tuic_export_singbox "$tuic_id" alice | jq -r .outbounds[0].tls.server_name)" \
  'TUIC connection host and SNI stay separate'

reality_id=r1111111111111111
mkdir -p "$(dirname "$(reality_state_file "$reality_id")")"
reality_profile_recommendation() { printf warning; }
reality_generate_state "$(reality_state_file "$reality_id")" "$reality_id" \
  reality-edge 0.0.0.0 3616 custom "$host" 443 "$uuid" dummy-public-key \
  "$fixture/reality.key" aabbccdd camouflage.example.org 8443 chrome / 26.3.27 \
  "$NOBRAND_LEGACY_INGRESS_PROFILE_ID" 22052
assert_eq "$host" "$(reality_state_field "$reality_id" advertise_host)" 'REALITY state'
assert_contains "$(reality_build_uri "$reality_id")" "@$host:443" 'REALITY URI connection host'
assert_contains "$(reality_export_mihomo "$reality_id")" \
  "server: \"$host\"" 'REALITY Mihomo connection host'
assert_eq "$host" "$(reality_export_xray "$reality_id" \
  | jq -r '.outbounds[0].settings.vnext[0].address')" 'REALITY Xray connection host'
assert_eq "$host" "$(reality_export_singbox "$reality_id" \
  | jq -r '.outbounds[0].server')" 'REALITY sing-box connection host'
assert_eq camouflage.example.org "$(reality_state_field "$reality_id" target_host)" \
  'REALITY camouflage target stays independent'
assert_eq camouflage.example.org "$(reality_export_singbox "$reality_id" \
  | jq -r '.outbounds[0].tls.server_name')" 'REALITY SNI stays independent'

ssh_users='[{"account_id":"a1111111111111111","display_name":"alice","linux_user":"nbt-alice-11111111","uid":61001,"group":"nobrand-ssh-tunnel","key_fingerprint":"SHA256:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA","created_at":"2026-09-29T00:00:00Z"}]'
ssh_tunnel_generate_state "$NOBRAND_SSH_STATE_FILE" custom "$host" 443 22 \
  dropin "$fixture/sshd.conf" "$ssh_users"
assert_eq "$host" "$(ssh_tunnel_effective_host)" 'SSH connection host'
assert_contains "$(ssh_tunnel_show_user alice)" "@$host" 'SSH connection command'

cat >"$NOBRAND_FORWARD_STATE_FILE" <<'JSON'
{"schema_version":3,"ownership":"nobrand-v3","feature":"port-forward","rules":[
 {"rule_id":"f1111111111111111","name":"edge-forward","note":"","backend":"nftables","enabled":false,
  "protocol":"tcp","listen_host":"0.0.0.0","listen_port":16850,
  "target_host":"203.0.113.30","target_port":8443,"display_host":"edge.example.com","display_port":443,
  "display_mode":"custom","created_at":"2026-09-29T00:00:00Z","updated_at":"2026-09-29T00:00:00Z",
  "ownership_metadata":{"managed_listener":true,"managed_firewall":true},
  "backend_options":{"source_mode":"masquerade"}}
]}
JSON
forward_state_valid || fail 'Forward domain Display Endpoint state rejected'
assert_contains "$(forward_node_rows)" "$host:443" 'Forward nodes domain'
assert_eq "$host" "$(forward_export_json | jq -r '.rules[0].display_host')" \
  'Forward export raw domain'
assert_eq 203.0.113.30 "$(jq -r '.rules[0].target_host' "$NOBRAND_FORWARD_STATE_FILE")" \
  'nftables target remains IPv4 and independent of Display Endpoint'

assert_contains "$(nb_all_node_rows)" "$host:443" 'unified nodes domain'
pass 'domain stays raw in all supported protocol states, nodes, URI and client exporters'

# Backup copies authoritative state bytes. The existing backup boundary suite
# exercises restore and rollback; this archive check covers every domain state.
ssh_tunnel_backup_state_ready() { return 0; }
archive="$fixture/domain-backup.tar.gz"
nobrand_backup_create "$archive" >/dev/null
for path in \
  "state/snell/instances/$snell4.json" \
  "state/snell/instances/$snell5.json" \
  state/hysteria2/state.json state/vless-sudoku/state.json \
  "state/tuic/instances/$tuic_id/state.json" \
  "state/vless-reality/instances/$reality_id/state.json" \
  state/ssh-tunnel/state.json state/forward/state.json; do
  assert_contains "$(tar -xOzf "$archive" "$path")" "$host" "backup raw host: $path"
done
pass 'backup archive retains every tested domain endpoint verbatim'
