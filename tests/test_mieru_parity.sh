#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/testlib.sh"

fixture="$(mktemp -d)"
trap 'rm -rf -- "$fixture"' EXIT
golden="$TEST_ROOT/tests/fixtures/mieru-v2.2.1-parity.json"

command -v jq >/dev/null 2>&1 || fail 'Mieru parity test requires jq'
jq -e '.authority.tag == "v2.2.1" and .authority.commit == "2b3e2371746a0dd0248887a216d3a45d6ac8e95c"' \
  "$golden" >/dev/null || fail 'invalid Mieru parity authority fixture'

# Native jq on Windows writes CRLF even under MSYS Bash. Keep comparisons
# platform-neutral without changing the checked-in LF-only fixtures.
jq_clean() {
  jq "$@" | tr -d '\r'
}

export MITA_MANAGER_STATE_DIR="$fixture/state/mieru"
export NOBRAND_STATE_DIR="$fixture/state"
export NOBRAND_CONFIG_DIR="$fixture/config"
export NOBRAND_LIB_DIR="$fixture/lib"
export NOBRAND_TEST_LOCAL_IPV4=172.16.1.36
source_installer

fixture_default() {
  jq_clean -r --arg key "$1" '.defaults[$key]' "$golden"
}

assert_eq "$(fixture_default PROFILE)" "$PROFILE" 'default Profile'
assert_eq "$(fixture_default PROTOCOL)" "$PROTOCOL" 'default transport'
assert_eq "$(fixture_default MTU)" "$MTU" 'default MTU'
assert_eq "$(fixture_default MTU_POLICY)" "$MTU_POLICY" 'default MTU policy'
assert_eq "$(fixture_default MULTIPLEXING)" "$MULTIPLEXING" 'default multiplexing'
assert_eq "$(fixture_default HANDSHAKE_MODE)" "$HANDSHAKE_MODE" 'default handshake'
assert_eq "$(fixture_default TRAFFIC_PATTERN)" "$TRAFFIC_PATTERN" 'default traffic pattern'
assert_eq "$(fixture_default LOW_ENTROPY_MODE)" "$LOW_ENTROPY_MODE" 'default low entropy'
assert_eq "$(fixture_default MIERU_CHANNEL)" "$MIERU_CHANNEL" 'default Mieru channel'
assert_eq "$(fixture_default TESTED_MIERU_VERSION)" "$TESTED_MIERU_VERSION" 'tested Mieru version'
assert_eq "$(fixture_default CLIENT_RPC_PORT)" "$CLIENT_RPC_PORT" 'client RPC port'
assert_eq "$(fixture_default CLIENT_SOCKS5_PORT)" "$CLIENT_SOCKS5_PORT" 'client SOCKS port'
assert_eq "$(fixture_default CLIENT_HTTP_PORT)" "$CLIENT_HTTP_PORT" 'client HTTP port'
assert_eq "$(fixture_default QUOTA_RESET_METHOD)" "$QUOTA_RESET_METHOD" 'quota reset method'
assert_eq "$(fixture_default MITA_DEPLOYMENT_MODEL)" "$MITA_DEPLOYMENT_MODEL" 'deployment model'

while IFS=$'\t' read -r alias expected; do
  assert_eq "$expected" "$(normalize_profile "$alias")" "profile alias $alias"
done < <(jq_clean -r '.profile_aliases | to_entries[] | [.key,.value] | @tsv' "$golden")
while IFS=$'\t' read -r alias expected; do
  assert_eq "$expected" "$(normalize_multiplexing "$alias")" "multiplexing alias $alias"
done < <(jq_clean -r '.multiplexing_aliases | to_entries[] | [.key,.value] | @tsv' "$golden")
while IFS=$'\t' read -r alias expected; do
  assert_eq "$expected" "$(normalize_handshake_mode "$alias")" "handshake alias $alias"
done < <(jq_clean -r '.handshake_aliases | to_entries[] | [.key,.value] | @tsv' "$golden")
while IFS=$'\t' read -r alias expected; do
  assert_eq "$expected" "$(normalize_traffic_pattern "$alias")" "traffic alias $alias"
done < <(jq_clean -r '.traffic_aliases | to_entries[] | [.key,.value] | @tsv' "$golden")
while IFS=$'\t' read -r alias expected; do
  assert_eq "$expected" "$(normalize_low_entropy_mode "$alias")" "low entropy alias $alias"
done < <(jq_clean -r '.low_entropy_aliases | to_entries[] | [.key,.value] | @tsv' "$golden")

profile_tuple() {
  printf '%s|%s|%s|%s|%s|%s|%s' "$PROTOCOL" "$MTU" "$MTU_POLICY" \
    "$MULTIPLEXING" "$HANDSHAKE_MODE" "$TRAFFIC_PATTERN" "$LOW_ENTROPY_MODE"
}
for profile in iplc balanced stealth; do
  apply_profile_values "$profile"
  assert_eq "$(jq_clean -r --arg key "$profile" '.profiles[$key]' "$golden")" \
    "$(profile_tuple)" "$profile profile"
  profile_values_match "$profile" || fail "$profile profile must reconcile from concrete values"
done
PROTOCOL=UDP MTU=1492 MTU_POLICY=custom MULTIPLEXING=MULTIPLEXING_HIGH
HANDSHAKE_MODE=HANDSHAKE_STANDARD TRAFFIC_PATTERN=aggressive LOW_ENTROPY_MODE=LOW_ENTROPY_MODE_48
before_custom="$(profile_tuple)"
apply_profile_values custom
assert_eq "$before_custom" "$(profile_tuple)" 'custom profile preserves every concrete value'
assert_eq custom "$(infer_profile_from_values)" 'custom inference'

USER_PACKAGE=trial USER_QUOTA_MB='' USER_QUOTA_DAYS='' USER_EXPIRE=''
apply_user_package_defaults
assert_eq 'trial|10240|7|+7d' \
  "$USER_PACKAGE|$USER_QUOTA_MB|$USER_QUOTA_DAYS|$USER_EXPIRE" 'trial defaults'
USER_PACKAGE=standard USER_QUOTA_MB='' USER_QUOTA_DAYS='' USER_EXPIRE=''
apply_user_package_defaults
assert_eq 'standard|102400|30|+30d' \
  "$USER_PACKAGE|$USER_QUOTA_MB|$USER_QUOTA_DAYS|$USER_EXPIRE" 'standard defaults'
USER_PACKAGE=unlimited USER_QUOTA_MB=9 USER_QUOTA_DAYS=9 USER_EXPIRE=''
apply_user_package_defaults
assert_eq 'unlimited|0|0|' \
  "$USER_PACKAGE|$USER_QUOTA_MB|$USER_QUOTA_DAYS|$USER_EXPIRE" 'unlimited defaults'

# Freeze support gates so golden configuration generation is independent of
# the runtime installed on the developer machine.
installed_version() { printf '3.35.0'; }
mita_supports_traffic_pattern() { return 0; }
mita_supports_low_entropy() { return 0; }
export_traffic_pattern_value() { printf 'QUJDRA=='; }
public_ip() { printf '198.51.100.7'; }

json_semantic_eq() {
  local expected="$1" actual="$2" label="$3"
  diff -u <(jq -S . "$expected") <(jq -S . "$actual") >/dev/null \
    || fail "$label semantic JSON differs from mieru-OneClick v2.2.1"
}

write_expected_profile_config() {
  local profile="$1" output="$2"
  jq -n --arg profile "$profile" '
    {
      portBindings:[{port:3611,protocol:"TCP"}],
      users:[{name:"alice",password:"secret"}],
      loggingLevel:"INFO",
      mtu:1400
    }
    + if $profile == "iplc" then {}
      else {trafficPattern:(
        if $profile == "stealth" then {
          seed:4242,unlockAll:false,
          lowEntropy:{mode:"LOW_ENTROPY_MODE_OFF"},
          tcpFragment:{enable:true,maxSleepMs:8},
          nonce:{type:"NONCE_TYPE_PRINTABLE",applyToAllUDPPacket:true,minLen:6,maxLen:12},
          padding:{maxMiddlePaddingLen:64,maxEndPaddingLen:255}
        } else {
          seed:4242,unlockAll:false,
          lowEntropy:{mode:"LOW_ENTROPY_MODE_OFF"},
          nonce:{type:"NONCE_TYPE_PRINTABLE",applyToAllUDPPacket:true,minLen:4,maxLen:8},
          padding:{maxMiddlePaddingLen:0,maxEndPaddingLen:128}
        } end
      )} end
  ' >"$output"
}

for profile in iplc balanced stealth; do
  apply_profile_values "$profile"
  USERNAME=alice PASSWORD=secret PORT=3611 PORT_RANGE='' TRAFFIC_SEED=4242 MULTI_USER_MODE=0
  actual="$(write_server_config)"
  expected="$fixture/server-$profile.json"
  write_expected_profile_config "$profile" "$expected"
  json_semantic_eq "$expected" "$actual" "$profile server config"
done

PROFILE=custom PROTOCOL=BOTH MTU=1492 MTU_POLICY=custom
MULTIPLEXING=MULTIPLEXING_HIGH HANDSHAKE_MODE=HANDSHAKE_STANDARD
# Some request globals are consumed indirectly by the golden config builder.
# shellcheck disable=SC2034
TRAFFIC_PATTERN=aggressive TRAFFIC_SEED=4242 LOW_ENTROPY_MODE=LOW_ENTROPY_MODE_48
# shellcheck disable=SC2034
USERNAME=alice PASSWORD=secret PORT=3611 PORT_RANGE='' MULTI_USER_MODE=0
actual_custom="$(write_server_config)"
jq -n '{
  portBindings:[{port:3611,protocol:"TCP"},{port:3612,protocol:"UDP"}],
  users:[{name:"alice",password:"secret"}],
  loggingLevel:"INFO",mtu:1492,
  trafficPattern:{seed:4242,unlockAll:false,
    lowEntropy:{mode:"LOW_ENTROPY_MODE_48"},
    tcpFragment:{enable:true,maxSleepMs:8},
    nonce:{type:"NONCE_TYPE_PRINTABLE",applyToAllUDPPacket:true,minLen:6,maxLen:12},
    padding:{maxMiddlePaddingLen:64,maxEndPaddingLen:255}}
}' >"$fixture/server-custom.expected.json"
json_semantic_eq "$fixture/server-custom.expected.json" "$actual_custom" 'custom/BOTH server config'

PROTOCOL=TCP PORT=3611 ADVERTISE_HOST=entry.example.com ADVERTISE_PORT=443
build_client_json_for entry.example.com TCP >"$fixture/client.actual.json"
jq -n '{
  profiles:[{
    profileName:"default",
    user:{name:"alice",password:"secret"},
    servers:[{ipAddress:"",domainName:"entry.example.com",portBindings:[{port:443,protocol:"TCP"}]}],
    mtu:1492,
    multiplexing:{level:"MULTIPLEXING_HIGH"},
    handshakeMode:"HANDSHAKE_STANDARD",
    trafficPattern:{seed:4242,unlockAll:false,
      lowEntropy:{mode:"LOW_ENTROPY_MODE_48"},
      tcpFragment:{enable:true,maxSleepMs:8},
      nonce:{type:"NONCE_TYPE_PRINTABLE",applyToAllUDPPacket:true,minLen:6,maxLen:12},
      padding:{maxMiddlePaddingLen:64,maxEndPaddingLen:255}}
  }],
  activeProfile:"default",rpcPort:8964,socks5Port:1080,loggingLevel:"INFO",
  socks5ListenLAN:false,httpProxyPort:8080,httpProxyListenLAN:false
}' >"$fixture/client.expected.json"
json_semantic_eq "$fixture/client.expected.json" "$fixture/client.actual.json" 'official client export'

link="$(generate_share_link_for entry.example.com TCP)"
assert_eq 'mierus://alice:secret@entry.example.com?handshake-mode=HANDSHAKE_STANDARD&mtu=1492&multiplexing=MULTIPLEXING_HIGH&port=443&profile=default&protocol=TCP&traffic-pattern=QUJDRA%3D%3D' \
  "$link" 'mierus link fields'
yaml="$(build_clash_yaml_full entry.example.com)"
for expected in 'type: mieru' 'server: "entry.example.com"' 'port: 443' 'transport: TCP' \
  'username: "alice"' 'password: "secret"' 'multiplexing: MULTIPLEXING_HIGH' \
  'handshake-mode: HANDSHAKE_STANDARD' 'traffic-pattern: "QUJDRA=="'; do
  assert_contains "$yaml" "$expected" 'Mihomo exporter'
done

validate_advertise_endpoint_values '' '' TCP || fail 'automatic endpoint must validate'
validate_advertise_endpoint_values entry.example.com 443 TCP || fail 'domain endpoint must validate'
validate_advertise_endpoint_values 198.51.100.9 443 TCP || fail 'IPv4 endpoint must validate'
validate_advertise_endpoint_values 2001:db8::9 443 TCP || fail 'IPv6 endpoint must validate'
validate_advertise_endpoint_values entry.example.com 65535 BOTH >/dev/null 2>&1 \
  && fail 'BOTH display endpoint base port 65535 must be rejected'
validate_advertise_endpoint_values entry.example.com '' TCP >/dev/null 2>&1 \
  && fail 'persisted custom endpoint must never contain host without port'
validate_advertise_endpoint_values '' 443 TCP >/dev/null 2>&1 \
  && fail 'persisted custom endpoint must never contain port without host'
# Endpoint globals are consumed indirectly by advertised_port_for_protocol.
# shellcheck disable=SC2034
ADVERTISE_HOST=entry.example.com ADVERTISE_PORT=443 PROTOCOL=BOTH PORT=3611
assert_eq 443 "$(advertised_port_for_protocol TCP)" 'display TCP port'
assert_eq 444 "$(advertised_port_for_protocol UDP)" 'display UDP port'
assert_eq '[2001:db8::9]' "$(url_host 2001:db8::9)" 'IPv6 share-link host'

nb_port_is_listening() { return 1; }
nb_registry_port_owner() { return 1; }
PROTOCOL=BOTH
assert_eq $'TCP|3611\nUDP|3612' "$(PORT=3611 port_protocol_pairs)" 'BOTH real port semantics'
nb_port_is_tail_base_reserved 3600 || fail 'xx00 must be reserved'
port_available_for_mode 3600 && fail 'Mieru must reject xx00 on every transport'
nb_port_available_for_transport 3611 TCP || fail 'free TCP port must remain allocatable'
nb_port_available_for_transport 3611 UDP || fail 'free UDP port must remain independently allocatable'
valid_port 1024 && fail 'Mieru listener ports below 1025 must be rejected'
valid_port 1025 || fail 'Mieru listener port 1025 must be accepted'
valid_port 65535 || fail 'single-transport port 65535 must be accepted'

# Inventory completeness is checked independently of the semantic samples.
# This catches a parameter/action disappearing from routing or persistence even
# when the remaining golden combinations still happen to produce valid JSON.
while IFS= read -r action; do
  grep -Fq -- "$action" "$TEST_ROOT/src/10-cli-prelude.sh" \
    "$TEST_ROOT/src/90-ui.sh" "$TEST_ROOT/src/99-main.sh" \
    || fail "Mieru CLI/menu action disappeared: $action"
done < <(jq_clean -r '.cli_actions[]' "$golden")
while IFS= read -r option; do
  grep -Fq -- "$option" "$TEST_ROOT/src/10-cli-prelude.sh" \
    || fail "Mieru CLI value option disappeared: $option"
done < <(jq_clean -r '.cli_value_options[]' "$golden")
while IFS= read -r field; do
  grep -Fq -- "$field" "$TEST_ROOT/src/05-constants.sh" \
    "$TEST_ROOT/src/15-core-state.sh" \
    || fail "Mieru install-state field disappeared: $field"
done < <(jq_clean -r '.install_state_fields[]' "$golden")
while IFS= read -r field; do
  grep -Fq -- "$field" "$TEST_ROOT/src/30-users-instance.sh" \
    "$TEST_ROOT/src/35-users-state.sh" "$TEST_ROOT/src/40-tc-quota.sh" \
    "$TEST_ROOT/src/45-backup-user-actions.sh" \
    || fail "Mieru user-state field disappeared: $field"
done < <(jq_clean -r '.user_state_fields[]' "$golden")

printf 'MIERU_PARAMETER_PARITY=PASS\n'
printf 'MIERU_DEFAULT_PARITY=PASS\n'
printf 'MIERU_PROFILE_PARITY=PASS\n'
printf 'MIERU_CONFIG_PARITY=PASS\n'
printf 'MIERU_EXPORT_PARITY=PASS\n'
printf 'MIERU_ENDPOINT_PARITY=PASS\n'
printf 'MIERU_PORT_PARITY=PASS\n'
