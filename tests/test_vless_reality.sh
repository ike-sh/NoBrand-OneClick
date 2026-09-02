#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/testlib.sh"

fixture="$(mktemp -d)"
trap 'rm -rf -- "$fixture"' EXIT
export NOBRAND_STATE_DIR="$fixture/nobrand-oneclick/state"
export NOBRAND_CONFIG_DIR="$fixture/nobrand-oneclick/config"
export NOBRAND_LIB_DIR="$fixture/nobrand-oneclick/lib"
export NOBRAND_REALITY_SYSTEMD_TEMPLATE="$fixture/systemd/nobrand-vless-reality@.service"
export NOBRAND_REALITY_OPENRC_PREFIX="$fixture/openrc/nobrand-vless-reality-"
export NOBRAND_TEST_INTERFACE_ROWS=$'eth0|192.0.2.50|UP|1\neth1|198.51.100.40|UP|0'
export NOBRAND_TEST_DEFAULT_EGRESS='eth0|192.0.2.50'
source_installer
nb_init_state_layout
nb_port_is_listening() { return 1; }

ingress_cli() {
  ingress_menu_reset_requests
  parse_nobrand_ingress_args "$@"
  nobrand_run_ingress_action
}

ingress_cli add --name Public-Manual --type public --interface eth0 \
  --address 192.0.2.50 --port-policy manual-only --reserve 32000 --yes >/dev/null
ingress_cli add --name Mapped-Custom --type mapped --interface eth1 \
  --address 198.51.100.40 --port-policy custom-range --range-start 32100 --range-end 32199 \
  --reserve 32101 --advertise-host mapped.example.test --yes >/dev/null
public_id="$(nb_ingress_profile_id Public-Manual)"
mapped_id="$(nb_ingress_profile_id Mapped-Custom)"

assert_eq recommended "$(reality_profile_recommendation "$public_id")" 'public recommendation'
assert_eq warning "$(reality_profile_recommendation "$mapped_id")" 'mapped warning recommendation'

mapfile -t qualified_pool < <(reality_auto_candidate_rows)
assert_eq 6 "${#qualified_pool[@]}" 'release-qualified REALITY auto pool size'
printf '%s\n' "${qualified_pool[@]}" | grep -qxF www.microsoft.com \
  && fail 'failed Microsoft candidate entered the automatic pool'
assert_eq "${#qualified_pool[@]}" "$(printf '%s\n' "${qualified_pool[@]}" | sort -u | wc -l | tr -d '[:space:]')" \
  'release-qualified REALITY auto pool uniqueness'
mapfile -t randomized_pool < <(reality_randomized_auto_candidates)
assert_eq "$(printf '%s\n' "${qualified_pool[@]}" | sort)" \
  "$(printf '%s\n' "${randomized_pool[@]}" | sort)" \
  'randomized automatic candidate order is an exact no-replacement pool permutation'
printf 'REALITY_AUTO_POOL_EXCLUSION=PASS\n'

auto_validation_mode=pass
auto_order_mode=normal
auto_validation_log="$fixture/auto-validation.log"
reality_randomized_auto_candidates() {
  case "$auto_order_mode" in
    retry) printf '%s\n' www.abmindustriesgroup.com www.abmindustriesgroup.com www.oracle.com ;;
    *) printf '%s\n' www.abmindustriesgroup.com www.oracle.com ;;
  esac
}
reality_validate_target_live() {
  printf '%s:%s\n' "$1" "$2" >>"$auto_validation_log"
  case "$auto_validation_mode:$1" in
    fail:*) return 1 ;;
    retry:www.abmindustriesgroup.com) return 1 ;;
    *) return 0 ;;
  esac
}

VLESS_REALITY_TARGET="" VLESS_REALITY_TARGET_PORT=""
reality_apply_camouflage_defaults
assert_eq auto "$VLESS_REALITY_CAMOUFLAGE_MODE" 'missing REALITY camouflage host selects auto mode'
assert_eq 443 "$VLESS_REALITY_TARGET_PORT" 'default REALITY camouflage target port'
reality_resolve_camouflage_request
assert_eq www.abmindustriesgroup.com "$VLESS_REALITY_TARGET" 'auto REALITY camouflage selection'
assert_eq auto "$VLESS_REALITY_CAMOUFLAGE_MODE" 'selected automatic camouflage mode'
printf 'AUTO_HOST_DEFAULT_PORT=PASS\nREALITY_AUTO_SELECTION=PASS\n'

VLESS_REALITY_TARGET=custom-host.example.com VLESS_REALITY_TARGET_PORT=""
reality_apply_camouflage_defaults
reality_resolve_camouflage_request
assert_eq custom-host.example.com "$VLESS_REALITY_TARGET" 'custom REALITY camouflage host'
assert_eq custom "$VLESS_REALITY_CAMOUFLAGE_MODE" 'explicit REALITY camouflage host mode'
assert_eq 443 "$VLESS_REALITY_TARGET_PORT" 'custom host keeps default camouflage target port'
printf 'CUSTOM_HOST_DEFAULT_PORT=PASS\nREALITY_CUSTOM_HOST_OVERRIDE=PASS\n'

VLESS_REALITY_TARGET="" VLESS_REALITY_TARGET_PORT=8443
reality_apply_camouflage_defaults
reality_resolve_camouflage_request
assert_eq www.abmindustriesgroup.com "$VLESS_REALITY_TARGET" 'custom port uses auto camouflage host'
assert_eq auto "$VLESS_REALITY_CAMOUFLAGE_MODE" 'custom port keeps automatic camouflage mode'
assert_eq 8443 "$VLESS_REALITY_TARGET_PORT" 'custom REALITY camouflage target port'
assert_contains "$(<"$auto_validation_log")" 'www.abmindustriesgroup.com:8443' \
  'automatic selection validates the actual custom target port'
printf 'AUTO_HOST_CUSTOM_PORT=PASS\n'

VLESS_REALITY_TARGET=custom-both.example.com VLESS_REALITY_TARGET_PORT=9443
reality_apply_camouflage_defaults
reality_resolve_camouflage_request
assert_eq custom-both.example.com "$VLESS_REALITY_TARGET" 'custom REALITY camouflage host and port host'
assert_eq custom "$VLESS_REALITY_CAMOUFLAGE_MODE" 'custom REALITY camouflage host and port mode'
assert_eq 9443 "$VLESS_REALITY_TARGET_PORT" 'custom REALITY camouflage host and port port'
printf 'CUSTOM_HOST_CUSTOM_PORT=PASS\n'

auto_order_mode=retry auto_validation_mode=retry
: >"$auto_validation_log"
VLESS_REALITY_TARGET="" VLESS_REALITY_TARGET_PORT=443
reality_apply_camouflage_defaults
reality_resolve_camouflage_request
assert_eq www.oracle.com "$VLESS_REALITY_TARGET" 'automatic selection retries the next candidate'
assert_eq $'www.abmindustriesgroup.com:443\nwww.oracle.com:443' "$(<"$auto_validation_log")" \
  'automatic selection retries without replacement'
printf 'REALITY_AUTO_RETRY_WITHOUT_REPLACEMENT=PASS\n'

auto_order_mode=normal auto_validation_mode=fail
: >"$auto_validation_log"
VLESS_REALITY_TARGET="" VLESS_REALITY_TARGET_PORT=443
reality_apply_camouflage_defaults
if reality_resolve_camouflage_request; then
  fail 'automatic selection accepted an exhausted candidate pool'
fi
assert_eq '' "$VLESS_REALITY_TARGET" 'automatic pool exhaustion selects no target'
assert_eq auto "$VLESS_REALITY_CAMOUFLAGE_MODE" 'automatic pool exhaustion retains request origin'
printf 'REALITY_AUTO_POOL_EXHAUSTION_ROLLBACK=PASS\n'
auto_order_mode=normal auto_validation_mode=pass

reality_valid_public_hostname_syntax example.com || fail 'valid public target hostname'
for bad in localhost localdomain 127.0.0.1 '[::1]' 'https://example.com' '-bad.example'; do
  if reality_valid_public_hostname_syntax "$bad"; then fail "invalid REALITY target accepted: $bad"; fi
done
for valid in 00 aabb 0123456789abcdef; do
  reality_valid_short_id "$valid" || fail "valid REALITY short ID rejected: $valid"
done
for bad in '' a abc 0123456789abcdef00 xyz1; do
  if reality_valid_short_id "$bad"; then fail "invalid REALITY short ID accepted: $bad"; fi
done

id="r$(openssl rand -hex 8)"
name=primary
port=32051
defender_port=22051
uuid="$(tr -d '\r\n' </proc/sys/kernel/random/uuid)"
private_key="$(openssl rand -base64 32 | tr '/+' '_-' | tr -d '=\r\n')"
public_key="$(openssl rand -base64 32 | tr '/+' '_-' | tr -d '=\r\n')"
short_id="$(openssl rand -hex 8)"
config="$(reality_config_file "$id")"
state="$(reality_state_file "$id")"
key_file="$(reality_private_key_file "$id")"
mkdir -p "$(dirname "$config")" "$(dirname "$state")"
printf '%s\n' "$private_key" >"$key_file"
chmod 0600 "$key_file"
reality_generate_server_config "$config" "$id" 0.0.0.0 "$port" "$uuid" "$private_key" \
  "$short_id" example.com 443 "$defender_port"
reality_generate_state "$state" "$id" "$name" 0.0.0.0 "$port" auto '' '' "$uuid" \
  "$public_key" "$key_file" "$short_id" example.com 443 chrome / 26.3.27 "$public_id" \
  "$defender_port" 2026-09-01T00:00:00Z auto
chmod 0600 "$config" "$state"

reality_state_matches "$state" "$id" || fail 'REALITY schema-v3 state contract'
assert_eq auto "$(reality_state_field "$id" camouflage_mode)" 'selected automatic host origin persisted'
reality_config_matches_state "$id" || fail 'REALITY server config/state/private-key parity'
if [ -n "${NOBRAND_TEST_XRAY_BIN:-}" ]; then
  [ -x "$NOBRAND_TEST_XRAY_BIN" ] || fail 'requested exact Xray validator is not executable'
  [ -s "${NOBRAND_TEST_XRAY_ASSET_DIR:-}/geoip.dat" ] \
    || fail 'requested exact Xray geoip asset is unavailable'
  NOBRAND_XRAY_ASSET_DIR="$NOBRAND_TEST_XRAY_ASSET_DIR" \
    nobrand_xray_test_config "$config" "$NOBRAND_TEST_XRAY_BIN" \
    || fail 'exact Xray runtime rejected REALITY defender config'
  printf 'REALITY_DEFENDER_EXACT_XRAY_CONFIG=PASS\n'
fi
jq -e '
  .inbounds[0].listen=="0.0.0.0"
  and .inbounds[0].protocol=="vless"
  and .inbounds[0].settings.decryption=="none"
  and .inbounds[0].settings.clients[0].flow=="xtls-rprx-vision"
  and .inbounds[0].streamSettings.network=="tcp"
  and .inbounds[0].streamSettings.security=="reality"
  and .inbounds[0].streamSettings.realitySettings.show==false
  and .inbounds[0].streamSettings.realitySettings.target=="127.0.0.1:22051"
  and .inbounds[0].streamSettings.realitySettings.xver==0
  and .inbounds[0].streamSettings.realitySettings.minClientVer=="0.0.0"
  and .inbounds[0].streamSettings.realitySettings.serverNames==["example.com"]
  and .inbounds[0].streamSettings.realitySettings.shortIds==[$short_id]
  and .inbounds[0].sniffing.destOverride==["http","tls","quic"]
  and .inbounds[1]=={
    tag:("nobrand-vless-reality-"+$id+"-defender"),listen:"127.0.0.1",port:22051,
    protocol:"dokodemo-door",settings:{address:"nobrand.invalid",port:443,network:"tcp"},
    sniffing:{enabled:true,routeOnly:true,destOverride:["tls"]}
  }
  and .outbounds==[
    {tag:"PUBLIC_DIRECT",protocol:"freedom"},
    {tag:"DIRECT",protocol:"freedom",settings:{redirect:"example.com:443"}},
    {tag:"BLOCK",protocol:"blackhole"}
  ]
  and .routing.rules[0].ip==["geoip:private"]
  and .routing.rules[1].port=="25,135,137,138,139,445,465,587"
  and .routing.rules[2].protocol==["bittorrent"]
  and .routing.rules[3].domain==["full:example.com"]
  and .routing.rules[3].inboundTag==[("nobrand-vless-reality-"+$id+"-defender")]
  and .routing.rules[3].outboundTag=="DIRECT"
  and .routing.rules[4]=={type:"field",inboundTag:[("nobrand-vless-reality-"+$id+"-defender")],outboundTag:"BLOCK"}
  and .routing.rules[5]=={type:"field",inboundTag:[("nobrand-vless-reality-"+$id+"-in")],outboundTag:"PUBLIC_DIRECT"}
' --arg short_id "$short_id" --arg id "$id" "$config" >/dev/null \
  || fail 'exact REALITY TCP/Vision defender server shape'
printf 'REALITY_MIN_CLIENT_VER_SERVER_ONLY=PASS\nREALITY_SERVER_CONFIG_TEST=PASS\n'
assert_file_mode 600 "$key_file"
assert_eq '0:0' "$(stat -c '%u:%g' "$key_file")" 'REALITY private key root ownership'

leaky_config="$fixture/leaky-reality.json"
leaky_binary="$fixture/leaky-xray"
leaky_log="$fixture/leaky-xray.log"
auth_value="$(openssl rand -hex 12)"
jq --arg public_key "$public_key" --arg password "$public_key" --arg auth "$auth_value" '
  .diagnostic_secrets={
    privateKey:.inbounds[0].streamSettings.realitySettings.privateKey,
    publicKey:$public_key,
    password:$password,
    uuid:.inbounds[0].settings.clients[0].id,
    shortId:.inbounds[0].streamSettings.realitySettings.shortIds[0],
    shortIds:.inbounds[0].streamSettings.realitySettings.shortIds,
    auth:$auth
  }
' "$config" >"$leaky_config"
cat >"$leaky_binary" <<'SH'
#!/usr/bin/env bash
config="${@: -1}"
jq -r '.diagnostic_secrets | to_entries[]
  | "\(.key)=\(.value | if type=="array" then join(",") else . end)"' "$config" >&2
printf 'asset-dir=%s\n' "$XRAY_LOCATION_ASSET" >&2
exit 23
SH
chmod 0755 "$leaky_binary"
if nobrand_xray_test_config "$leaky_config" "$leaky_binary" 2>"$leaky_log"; then
  fail 'failing Xray config validator unexpectedly passed'
fi
for secret in "$private_key" "$public_key" "$uuid" "$short_id" "$auth_value"; do
  assert_not_contains "$(<"$leaky_log")" "$secret" 'redacted Xray validation diagnostic'
done
assert_contains "$(<"$leaky_log")" '***REDACTED***' 'Xray validation redaction marker'
assert_contains "$(<"$leaky_log")" "asset-dir=${NOBRAND_XRAY_ASSET_DIR}" \
  'Xray validation uses the private NoBrand asset directory'

assert_eq "vless-reality:${id}" "$(nb_registry_port_owner TCP "$port")" 'REALITY TCP registry owner'
assert_eq "vless-reality-defender:${id}" "$(reality_defender_port_owner "$defender_port")" \
  'REALITY internal defender owner'
reality_defender_registry_valid || fail 'REALITY internal defender registry uniqueness'
if nb_registry_port_owner TCP "$defender_port" >/dev/null 2>&1; then
  fail 'REALITY defender port polluted the public Common Port registry'
fi
if reality_defender_port_available "$defender_port"; then
  fail 'REALITY defender allocator ignored authoritative internal ownership'
fi
duplicate_id="r$(openssl rand -hex 8)"
mkdir -p "$(dirname "$(reality_state_file "$duplicate_id")")"
jq --arg id "$duplicate_id" --arg tag "$(reality_defender_tag "$duplicate_id")" \
  '.instance_id=$id | .name="duplicate-defender" | .defender_tag=$tag' "$state" \
  >"$(reality_state_file "$duplicate_id")"
if reality_defender_registry_valid; then
  fail 'REALITY defender registry accepted duplicate internal port ownership'
fi
rm -rf -- "$(dirname "$(reality_state_file "$duplicate_id")")"
reality_defender_registry_valid || fail 'REALITY defender registry did not recover after duplicate removal'
nb_registry_port_owner UDP "$port" >/dev/null 2>&1 \
  && fail 'REALITY must not reserve the same numeric UDP port'
nb_port_available_for_profile "$port" TCP "$mapped_id" \
  && fail 'host-global TCP ownership conflict crossed Profile boundary'
nb_port_available_for_profile "$port" UDP "$mapped_id" \
  || fail 'same numeric UDP port should remain available'

uri="$(reality_build_uri "$id")"
for field in 'security=reality' 'type=tcp' 'flow=xtls-rprx-vision' 'sni=example.com' \
  'fp=chrome' "pbk=${public_key}" "sid=${short_id}" 'spx=%2F'; do
  assert_contains "$uri" "$field" "REALITY URI $field"
done
xray="$(reality_export_xray "$id")"
printf '%s\n' "$xray" | jq -e --arg key "$public_key" --arg sid "$short_id" '
  .outbounds[0].protocol=="vless"
  and .outbounds[0].settings.vnext[0].users[0].encryption=="none"
  and .outbounds[0].settings.vnext[0].users[0].flow=="xtls-rprx-vision"
  and .outbounds[0].streamSettings.network=="tcp"
  and .outbounds[0].streamSettings.security=="reality"
  and .outbounds[0].streamSettings.realitySettings.password==$key
  and .outbounds[0].streamSettings.realitySettings.shortId==$sid
  and .outbounds[0].streamSettings.realitySettings.fingerprint=="chrome"
  and .outbounds[0].streamSettings.realitySettings.spiderX=="/"
' >/dev/null || fail 'official Xray 26.3.27 client exporter contract'
printf '%s\n' "$xray" | jq -e '[.. | objects | has("minClientVer")] | any | not' >/dev/null \
  || fail 'Xray client exporter leaked server-only minClientVer'

mihomo="$(reality_export_mihomo "$id")"
printf '%s\n' "$mihomo" >"$fixture/mihomo.yaml"
python3 "$TEST_ROOT/tests/helpers/assert_mihomo_routing_contract.py" \
  "$fixture/mihomo.yaml" NOBRAND >/dev/null || fail 'Mihomo no-direct routing contract'
for field in 'type: vless' 'network: tcp' 'tls: true' 'flow: xtls-rprx-vision' \
  'client-fingerprint: "chrome"' 'reality-opts:' "public-key: \"${public_key}\"" \
  "short-id: \"${short_id}\""; do
  assert_contains "$mihomo" "$field" "Mihomo REALITY $field"
done
assert_not_contains "$mihomo" 'minClientVer' 'Mihomo exporter excludes server-only minClientVer'
singbox="$(reality_export_singbox "$id")"
printf '%s\n' "$singbox" | jq -e --arg key "$public_key" --arg sid "$short_id" '
  .outbounds[0].type=="vless" and .outbounds[0].flow=="xtls-rprx-vision"
  and .outbounds[0].tls.enabled==true and .outbounds[0].tls.server_name=="example.com"
  and .outbounds[0].tls.utls=={enabled:true,fingerprint:"chrome"}
  and .outbounds[0].tls.reality=={enabled:true,public_key:$key,short_id:$sid}
  and .route.final==.outbounds[0].tag
  and ([.outbounds[].type] | index("direct") | not)
' >/dev/null || fail 'sing-box REALITY/no-direct exporter contract'
printf '%s\n' "$singbox" | jq -e '[.. | objects | has("minClientVer")] | any | not' >/dev/null \
  || fail 'sing-box exporter leaked server-only minClientVer'

custom_id="r$(openssl rand -hex 8)"
custom_config="$(reality_config_file "$custom_id")"
custom_state="$(reality_state_file "$custom_id")"
custom_key_file="$(reality_private_key_file "$custom_id")"
mkdir -p "$(dirname "$custom_config")" "$(dirname "$custom_state")"
printf '%s\n' "$private_key" >"$custom_key_file"
chmod 0600 "$custom_key_file"
reality_generate_server_config "$custom_config" "$custom_id" 0.0.0.0 32053 "$uuid" \
  "$private_key" "$short_id" custom-camouflage.example.com 8443 22053
reality_generate_state "$custom_state" "$custom_id" custom-camouflage 0.0.0.0 32053 custom \
  public-endpoint.example.com 5443 "$uuid" "$public_key" "$custom_key_file" "$short_id" \
  custom-camouflage.example.com 8443 chrome / 26.3.27 "$public_id" 22053 \
  2026-09-01T00:00:00Z custom
chmod 0600 "$custom_config" "$custom_state"
reality_config_matches_state "$custom_id" || fail 'custom camouflage config/state parity'
jq -e '
  .inbounds[0].port==32053
  and .inbounds[0].streamSettings.realitySettings.serverNames==["custom-camouflage.example.com"]
  and .inbounds[1].settings.port==8443
  and .outbounds[1].settings.redirect=="custom-camouflage.example.com:8443"
' "$custom_config" >/dev/null || fail 'custom camouflage defender/server synchronization'
custom_uri="$(reality_build_uri "$custom_id")"
assert_contains "$custom_uri" '@public-endpoint.example.com:5443' \
  'custom camouflage target port does not replace public client endpoint port'
assert_contains "$custom_uri" 'sni=custom-camouflage.example.com' \
  'custom camouflage host reaches client exporter SNI'
assert_not_contains "$custom_uri" '@public-endpoint.example.com:8443' \
  'custom camouflage target port remains independent from public endpoint'
assert_contains "$(reality_export_mihomo "$custom_id")" 'servername: "custom-camouflage.example.com"' \
  'custom camouflage host reaches Mihomo exporter'
printf '%s\n' "$(reality_export_singbox "$custom_id")" | jq -e '
  .outbounds[0].server=="public-endpoint.example.com"
  and .outbounds[0].server_port==5443
  and .outbounds[0].tls.server_name=="custom-camouflage.example.com"
' >/dev/null || fail 'custom camouflage host and public endpoint stay independent in sing-box exporter'
printf 'CUSTOM_CAMOUFLAGE_EXPORTER_SYNC=PASS\nCUSTOM_CAMOUFLAGE_DEFENDER_SYNC=PASS\n'
printf 'REALITY_AUTO_EXPORTER_SYNC=PASS\nREALITY_PORT_SEPARATION=PASS\n'

auto_selected_host="$(reality_state_field "$id" server_name)"
auto_state_hash="$(sha256sum "$state")"
auto_order_mode=normal auto_validation_mode=fail
reality_show "$id" >/dev/null
reality_status >/dev/null
reality_export_all "$id" >/dev/null
assert_eq "$auto_selected_host" "$(reality_state_field "$id" server_name)" \
  'read-only actions keep the selected automatic hostname'
assert_eq "$auto_state_hash" "$(sha256sum "$state")" \
  'read-only actions do not rerandomize or mutate automatic camouflage state'
printf 'REALITY_AUTO_SELECTION_PERSISTENCE=PASS\n'
auto_validation_mode=pass

legacy_state_copy="$fixture/reality-state-with-target-port.json"
cp "$state" "$legacy_state_copy"
jq 'del(.target_port)' "$state" >"$fixture/reality-state-without-target-port.json"
mv "$fixture/reality-state-without-target-port.json" "$state"
legacy_hash="$(sha256sum "$state")"
assert_eq 443 "$(reality_state_field "$id" target_port)" \
  'legacy REALITY state without target_port reads default 443'
reality_state_matches "$state" "$id" || fail 'legacy REALITY state without target_port validates read-only'
reality_config_matches_state "$id" || fail 'legacy REALITY state without target_port matches default-port config'
reality_build_uri "$id" >/dev/null
reality_export_xray "$id" >/dev/null
reality_export_mihomo "$id" >/dev/null
reality_export_singbox "$id" >/dev/null
assert_eq "$legacy_hash" "$(sha256sum "$state")" \
  'legacy REALITY read-only commands do not rewrite missing target_port state'
cp "$legacy_state_copy" "$state"

reality_service_active() { return 1; }
legacy_mode_copy="$fixture/reality-state-without-camouflage-mode.json"
jq 'del(.camouflage_mode)' "$state" >"$legacy_mode_copy"
mv "$legacy_mode_copy" "$state"
legacy_mode_hash="$(sha256sum "$state")"
assert_eq custom "$(reality_state_field "$id" camouflage_mode)" \
  'legacy REALITY state without camouflage_mode is treated as explicit/custom'
reality_state_matches "$state" "$id" || fail 'legacy missing camouflage_mode state validates'
reality_show "$id" >/dev/null
reality_status >/dev/null
reality_export_all "$id" >/dev/null
assert_eq "$legacy_mode_hash" "$(sha256sum "$state")" \
  'read-only REALITY actions do not write a missing camouflage_mode field'
cp "$legacy_state_copy" "$state"

microsoft_legacy="$fixture/reality-microsoft-existing.json"
jq '.camouflage_mode="custom" | .server_name="www.microsoft.com" | .target_host="www.microsoft.com"' \
  "$state" >"$microsoft_legacy"
reality_state_matches "$microsoft_legacy" "$id" \
  || fail 'existing explicit Microsoft state remains schema-compatible outside the auto pool'

reality_service_active() { return 1; }
ordinary="$(reality_status; reality_node_rows)"
assert_not_contains "$ordinary" "$private_key" 'ordinary REALITY output private key'
assert_not_contains "$ordinary" "$uuid" 'ordinary REALITY output UUID'
assert_not_contains "$ordinary" "$public_key" 'ordinary REALITY output public key'
assert_not_contains "$ordinary" "$short_id" 'ordinary REALITY output short ID'
explicit="$(reality_show "$id")"
assert_contains "$explicit" "$public_key" 'explicit show public client material'
assert_not_contains "$explicit" "$private_key" 'explicit show private key redaction'

config_hash="$(sha256sum "$config")"
key_hash="$(sha256sum "$key_file")"
credential_snapshot="$(jq -c '[.uuid,.public_key,.short_id,.server_name,.target_port,.listen_port,.ingress_profile_id]' "$state")"
reality_set_endpoint_state "$id" display-only.example.test 444
assert_eq "$config_hash" "$(sha256sum "$config")" 'Display update preserves REALITY server config bytes'
assert_eq "$key_hash" "$(sha256sum "$key_file")" 'Display update preserves REALITY private key bytes'
assert_eq "$credential_snapshot" \
  "$(jq -c '[.uuid,.public_key,.short_id,.server_name,.target_port,.listen_port,.ingress_profile_id]' "$state")" \
  'Display update preserves REALITY credentials, port, target, and Profile'
assert_eq display-only.example.test "$(reality_state_field "$id" advertise_host)" \
  'Display update changes only endpoint metadata'

set +e
doctor_mismatch_output="$(
  nobrand_xray_version() { printf '%s' "$TESTED_XRAY_VERSION"; }
  nobrand_xray_test_config() { :; }
  reality_derive_public_key() { printf '%s' "$(openssl rand -base64 32 | tr '/+' '_-' | tr -d '=\r\n')"; }
  reality_service_active() { :; }
  nb_port_is_listening() { :; }
  reality_listener_owned_by_service() { :; }
  nb_firewall_binding_owned() { :; }
  reality_doctor_one "$id"
  ) 2>&1"
doctor_mismatch_rc=$?
set -e
[ "$doctor_mismatch_rc" -ne 0 ] || fail 'REALITY Doctor accepted a private/public key mismatch'
assert_contains "$doctor_mismatch_output" 'REALITY_KEYS public derivation mismatch' \
  'REALITY Doctor private/public mismatch diagnosis'
assert_not_contains "$doctor_mismatch_output" "$private_key" 'REALITY Doctor mismatch private-key secrecy'

mkdir -p "$(dirname "$NOBRAND_REALITY_SYSTEMD_TEMPLATE")" "$(dirname "${NOBRAND_REALITY_OPENRC_PREFIX}${id}")"
printf '%s\n' 'external-systemd-template' >"$NOBRAND_REALITY_SYSTEMD_TEMPLATE"
external_template_hash="$(sha256sum "$NOBRAND_REALITY_SYSTEMD_TEMPLATE")"
if (
  nb_service_manager() { printf systemd; }
  systemctl() { :; }
  reality_install_service_runtime
) >/dev/null 2>&1; then
  fail 'REALITY replaced an unowned systemd template'
fi
assert_eq "$external_template_hash" "$(sha256sum "$NOBRAND_REALITY_SYSTEMD_TEMPLATE")" \
  'unowned REALITY systemd template preserved'
rm -f "$NOBRAND_REALITY_SYSTEMD_TEMPLATE"
(
  nb_service_manager() { printf systemd; }
  systemctl() { :; }
  reality_install_service_runtime
)
reality_systemd_template_owned || fail 'REALITY systemd template ownership marker'
reality_remove_service_runtime_if_owned
[ ! -e "$NOBRAND_REALITY_SYSTEMD_TEMPLATE" ] || fail 'owned REALITY systemd template removal'

openrc_path="${NOBRAND_REALITY_OPENRC_PREFIX}${id}"
printf '%s\n' 'external-openrc-service' >"$openrc_path"
external_openrc_hash="$(sha256sum "$openrc_path")"
if (
  nb_service_manager() { printf openrc; }
  rc-update() { :; }
  reality_ensure_openrc_service "$id"
) >/dev/null 2>&1; then
  fail 'REALITY replaced an unowned OpenRC service'
fi
assert_eq "$external_openrc_hash" "$(sha256sum "$openrc_path")" \
  'unowned REALITY OpenRC service preserved'
rm -f "$openrc_path"
(
  nb_service_manager() { printf openrc; }
  rc-update() { :; }
  reality_ensure_openrc_service "$id"
)
reality_openrc_service_owned "$id" || fail 'REALITY OpenRC service ownership marker'
rm -f "$openrc_path"

export VLESS_REALITY_NAME=manual-missing VLESS_REALITY_TARGET=example.com VLESS_REALITY_TARGET_PORT=443
export VLESS_REALITY_TARGET_CLI=1 VLESS_REALITY_TARGET_PORT_CLI=1
export INGRESS_PROFILE=Public-Manual PORT='' YES=1 ADVERTISE_HOST='' ADVERTISE_PORT=''
if ( reality_collect_install_requests >/dev/null 2>&1 ); then
  fail 'manual-only REALITY install accepted a missing explicit port'
fi
export VLESS_REALITY_NAME=manual-explicit PORT=32052
reality_collect_install_requests >/dev/null
assert_eq "$public_id" "$INGRESS_PROFILE_ID" 'explicit public Profile association'
assert_eq 32052 "$PORT" 'manual-only explicit REALITY port'

export VLESS_REALITY_NAME=interactive-defaults INGRESS_PROFILE=Public-Manual PORT=33053 YES=0
export ADVERTISE_HOST='' ADVERTISE_PORT='' ADVERTISE_CLI=1 ADVERTISE_AUTO_REQUESTED=1
export VLESS_REALITY_TARGET='' VLESS_REALITY_TARGET_CLI=0
export VLESS_REALITY_TARGET_PORT=443 VLESS_REALITY_TARGET_PORT_CLI=0
prompt_log="$fixture/reality-default-prompts.txt"
read_tty() {
  printf '%s\n' "$2" >>"$prompt_log"
  printf -v "$1" '%s' ''
}
reality_collect_install_requests >/dev/null
assert_eq www.abmindustriesgroup.com "$VLESS_REALITY_TARGET" 'interactive empty camouflage host uses auto selection'
assert_eq auto "$VLESS_REALITY_CAMOUFLAGE_MODE" 'interactive empty camouflage host records auto mode'
assert_eq 443 "$VLESS_REALITY_TARGET_PORT" 'interactive empty camouflage target port uses default'
assert_contains "$(<"$prompt_log")" '[auto]' \
  'interactive REALITY camouflage host prompt exposes auto default'
assert_contains "$(<"$prompt_log")" '[443]' \
  'interactive REALITY camouflage target-port prompt exposes default'

export VLESS_REALITY_NAME=noninteractive-defaults PORT=33054 YES=1
export VLESS_REALITY_TARGET='' VLESS_REALITY_TARGET_CLI=0
export VLESS_REALITY_TARGET_PORT='' VLESS_REALITY_TARGET_PORT_CLI=0
reality_collect_install_requests >/dev/null
assert_eq www.abmindustriesgroup.com "$VLESS_REALITY_TARGET" '-y without camouflage host uses auto selection'
assert_eq auto "$VLESS_REALITY_CAMOUFLAGE_MODE" '-y without camouflage host records auto mode'
assert_eq 443 "$VLESS_REALITY_TARGET_PORT" '-y without camouflage target port uses default'
export VLESS_REALITY_NAME=mapped-allowed INGRESS_PROFILE=Mapped-Custom PORT=32102
mapped_output_file="$fixture/mapped-output.txt"
reality_collect_install_requests >"$mapped_output_file"
mapped_output="$(<"$mapped_output_file")"
assert_contains "$mapped_output" 'not recommended' 'mapped REALITY warning'
assert_eq "$mapped_id" "$INGRESS_PROFILE_ID" 'mapped Profile remains installable'
export VLESS_REALITY_NAME=reserved-rejected INGRESS_PROFILE=Mapped-Custom PORT=32101
if ( reality_collect_install_requests >/dev/null 2>&1 ); then
  fail 'REALITY accepted a Profile-reserved TCP port'
fi

sudoku_server="$fixture/sudoku.json"
vless_sudoku_generate_server_config "$sudoku_server" 0.0.0.0 32200 "$uuid" \
  "$(openssl rand -hex 16)"
jq -e '
  .inbounds[0].streamSettings.security=="none"
  and .inbounds[0].settings.decryption=="none"
  and .inbounds[0].streamSettings.finalmask.tcp[0].type=="sudoku"
  and (.inbounds[0].streamSettings|has("realitySettings")|not)
' "$sudoku_server" >/dev/null || fail 'existing VLESS/Sudoku contract changed'

pass 'VLESS REALITY state, Profile, port, secret, URI, and three-export contracts'
