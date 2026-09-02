#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/testlib.sh"

fixture="$(mktemp -d)"
trap 'rm -rf -- "$fixture"' EXIT
export NOBRAND_STATE_DIR="$fixture/nobrand-oneclick/state"
export NOBRAND_CONFIG_DIR="$fixture/nobrand-oneclick/config"
export NOBRAND_LIB_DIR="$fixture/nobrand-oneclick/lib"
export NOBRAND_TEST_LOCAL_IPV4=172.16.1.36
source_installer
nb_init_state_layout

assert_eq 5 "$TUIC_PROTOCOL_VERSION" 'TUIC product protocol marker'
assert_eq true "$TUIC_V5_SUPPORTED" 'TUIC v5 support assertion'
assert_eq false "$TUIC_V1_SUPPORTED" 'TUIC v1 rejection assertion'
assert_eq false "$TUIC_V2_SUPPORTED" 'TUIC v2 rejection assertion'
assert_eq false "$TUIC_V3_SUPPORTED" 'TUIC v3 rejection assertion'
assert_eq false "$TUIC_V4_SUPPORTED" 'TUIC v4 rejection assertion'
assert_eq 1.13.20 "$TESTED_SING_BOX_SERVER_VERSION" 'tested sing-box stable'

instance_id=t1111111111111111
instance_name=primary
state="$fixture/state.json"
config="$fixture/config.json"
cert="$fixture/tuic-cert.pem"
key="$fixture/tuic-key.pem"
uuid_a=11111111-1111-4111-8111-111111111111
uuid_b=22222222-2222-4222-8222-222222222222
users='[{"user_id":"u1111111111111111","name":"alice","uuid":"'"$uuid_a"'","password":"alice-secret","created_at":"2026-08-30T00:00:00Z"},{"user_id":"u2222222222222222","name":"bob","uuid":"'"$uuid_b"'","password":"bob-secret","created_at":"2026-08-30T00:00:00Z"}]'

tuic_generate_server_config "$config" "$instance_id" 0.0.0.0 3611 "$cert" "$key" www.microsoft.com "$users"
jq -e '
  .inbounds | length == 1
  and .[0].type == "tuic"
  and .[0].listen == "0.0.0.0"
  and .[0].listen_port == 3611
  and .[0].congestion_control == "cubic"
  and .[0].zero_rtt_handshake == false
  and .[0].tls.enabled == true
  and .[0].tls.server_name == "www.microsoft.com"
  and .[0].tls.alpn == ["h3"]
  and .[0].users[0].uuid == "'"$uuid_a"'"
  and .[0].users[0].password == "alice-secret"
  and .[0].users[1].uuid == "'"$uuid_b"'"
  and .[0].users[1].password == "bob-secret"
  and ([paths | map(tostring) | join(".")] | all(test("token"; "i") | not))
' "$config" >/dev/null || fail 'canonical TUIC v5 sing-box inbound config'

tuic_generate_state "$state" "$instance_id" "$instance_name" 0.0.0.0 3611 \
  custom entry.example.com 443 www.microsoft.com stable 1.13.20 "$cert" "$key" "$users" \
  2026-08-30T00:00:00Z
jq -e '
  .schema_version == 3
  and .ownership == "nobrand-v3"
  and .protocol == "tuic"
  and .tuic_version == 5
  and .transport == "udp"
  and .listen_port == 3611
  and .advertise_host == "entry.example.com"
  and .advertise_port == 443
  and .congestion_control == "cubic"
  and .zero_rtt_handshake == false
  and .udp_relay_mode == "native"
  and (.users | length == 2)
' "$state" >/dev/null || fail 'TUIC schema-v3 optional-module state'

mkdir -p "$(dirname "$(tuic_state_file "$instance_id")")" \
  "$(dirname "$(tuic_config_file "$instance_id")")"
cp "$state" "$(tuic_state_file "$instance_id")"
cp "$config" "$(tuic_config_file "$instance_id")"
assert_eq "tuic:${instance_id}" "$(nb_registry_port_owner UDP 3611)" 'TUIC UDP registry owner'
nb_registry_port_owner TCP 3611 >/dev/null 2>&1 && fail 'TUIC must not reserve same-number TCP'
nb_port_available_for_transport 3600 UDP && fail 'TUIC must reject reserved xx00'

mihomo="$(tuic_export_mihomo "$instance_id" alice)"
printf '%s\n' "$mihomo" >"$fixture/tuic-mihomo.yaml"
python3 "$TEST_ROOT/tests/helpers/assert_mihomo_routing_contract.py" \
  "$fixture/tuic-mihomo.yaml" NOBRAND >/dev/null \
  || fail 'Mihomo TUIC routing contract'
assert_contains "$mihomo" 'type: tuic' 'Mihomo TUIC type'
assert_contains "$mihomo" "uuid: ${uuid_a}" 'Mihomo TUIC v5 UUID'
assert_contains "$mihomo" 'password: alice-secret' 'Mihomo TUIC v5 password'
assert_contains "$mihomo" 'udp-relay-mode: native' 'Mihomo native UDP relay'
assert_contains "$mihomo" 'congestion-controller: cubic' 'Mihomo cubic congestion control'
assert_contains "$mihomo" 'max-udp-relay-packet-size: 1400' 'Mihomo safe UDP packet size'
assert_not_contains "$mihomo" 'token:' 'Mihomo must not emit TUIC v4 token'

singbox="$(tuic_export_singbox "$instance_id" alice)"
printf '%s\n' "$singbox" | jq -e '
  .outbounds[0].type == "tuic"
  and .outbounds[0].uuid == "'"$uuid_a"'"
  and .outbounds[0].password == "alice-secret"
  and .outbounds[0].congestion_control == "cubic"
  and .outbounds[0].udp_relay_mode == "native"
  and .outbounds[0].zero_rtt_handshake == false
  and .outbounds[0].tls.server_name == "www.microsoft.com"
  and .outbounds[0].tls.alpn == ["h3"]
  and ([paths | map(tostring) | join(".")] | all(test("token"; "i") | not))
' >/dev/null || fail 'sing-box TUIC v5 exporter'

if tuic_build_uri "$instance_id" alice >/dev/null 2>&1; then
  fail 'TUIC URI must not be invented without an upstream standard'
fi

old_config_hash="$(sha256sum "$(tuic_config_file "$instance_id")")"
old_users_hash="$(jq -cS .users "$(tuic_state_file "$instance_id")" | sha256sum)"
tuic_set_endpoint_state "$instance_id" endpoint.example.net 8443
assert_eq "$old_config_hash" "$(sha256sum "$(tuic_config_file "$instance_id")")" \
  'TUIC endpoint must not rewrite server config'
assert_eq "$old_users_hash" "$(jq -cS .users "$(tuic_state_file "$instance_id")" | sha256sum)" \
  'TUIC endpoint must not rotate users'
assert_eq endpoint.example.net "$(jq -r .advertise_host "$(tuic_state_file "$instance_id")")" \
  'TUIC endpoint host update'
assert_eq 8443 "$(jq -r .advertise_port "$(tuic_state_file "$instance_id")")" \
  'TUIC endpoint port update'

pass 'TUIC v5 schema, ownership, exporters, and endpoint isolation'
