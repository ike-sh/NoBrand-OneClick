#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/testlib.sh"

fixture="$(mktemp -d)"
trap 'rm -rf -- "$fixture"' EXIT

export NOBRAND_STATE_DIR="$fixture/nobrand-oneclick/state"
export NOBRAND_CONFIG_DIR="$fixture/nobrand-oneclick/config"
export NOBRAND_LIB_DIR="$fixture/nobrand-oneclick/lib"
export MITA_INSTANCES_DIR="$fixture/mita-instances"
export MITA_INSTANCE_METRICS_DIR="$fixture/mita-metrics"
export NOBRAND_SNELL_SYSTEMD_TEMPLATE="$fixture/systemd/nobrand-snell@.service"
export NOBRAND_SSH_CONFIG_MAIN="$fixture/sshd_config"
export NOBRAND_SSH_CONFIG_DROPIN="$fixture/sshd_config.d/90-nobrand-ssh-tunnel.conf"
export NOBRAND_TEST_INTERFACE_ROWS=$'eth0|192.0.2.110|UP|1\neth1|198.51.100.40|UP|0\neth1|198.51.100.41|UP|0\neth2|203.0.113.20|UP|0\neth3|192.0.2.10|UP|0'
export NOBRAND_TEST_DEFAULT_EGRESS='eth0|192.0.2.110'
export NOBRAND_TEST_LOCAL_IPV4='192.0.2.110'
export NOBRAND_TEST_RANDOM_START=0

source_installer
nb_init_state_layout

# Keep all allocator assertions deterministic and independent from sockets on
# the test host. Registry ownership remains fully active.
nb_port_is_listening() { return 1; }
snell_platform_supported() { return 0; }
install_users_scheduler() { :; }

ingress_cli() {
  ingress_menu_reset_requests
  parse_nobrand_ingress_args "$@"
  nobrand_run_ingress_action
}

input_index=0
inputs=()
set_inputs() { inputs=("$@"); input_index=0; }
read_tty() {
  local destination="$1"
  [ "$input_index" -lt "${#inputs[@]}" ] || return 1
  printf -v "$destination" '%s' "${inputs[$input_index]}"
  input_index=$((input_index + 1))
}

# A schema-v3 manager and node that predate 3.2 have no ingress document or
# ingress_profile_id. Read-only 3.2 actions must not create or rewrite either.
legacy_id=s0000000000000031
snell_generate_state "$(snell_state_path "$legacy_id")" "$legacy_id" legacy-v31 5 legacy-psk-safe \
  0.0.0.0 3611 custom legacy.example.test 3611 '' false
snell_generate_server_config "$(snell_config_path "$legacy_id")" 5 0.0.0.0 3611 legacy-psk-safe
if jq -e 'has("ingress_profile_id")' "$(snell_state_path "$legacy_id")" >/dev/null; then
  fail 'legacy schema-v3 Snell state unexpectedly gained an ingress association'
fi
legacy_hash="$(sha256sum "$(snell_state_path "$legacy_id")")"
[ ! -e "$NOBRAND_INGRESS_STATE_FILE" ] || fail 'state initialization created ingress.json automatically'
nb_ingress_list >/dev/null
nb_ingress_doctor >/dev/null
[ ! -e "$NOBRAND_INGRESS_STATE_FILE" ] || fail 'read-only ingress actions created ingress.json'
assert_eq "$legacy_hash" "$(sha256sum "$(snell_state_path "$legacy_id")")" \
  'legacy 3.1 node remains byte-stable'
assert_eq "$NOBRAND_LEGACY_INGRESS_PROFILE_ID" "$(nb_resolve_ingress_profile '')" \
  'implicit legacy profile resolution'

# Exercise the public CLI parser and state writer for every Phase-1 policy.
ingress_cli add --name Public-Derived --type public --interface eth0 \
  --address 192.0.2.110 --port-policy derived-tail --yes >/dev/null
ingress_cli add --name Mapped-Custom --type mapped --interface eth1 \
  --address 198.51.100.41 --port-policy custom-range \
  --range-start 30001 --range-end 30020 --reserve 30005 --reserve 30010 \
  --advertise-host mapped.example.test --display-port-policy custom --display-port 443 --yes >/dev/null
ingress_cli add --name Public-Manual --type public --interface eth2 \
  --address 203.0.113.20 --port-policy manual-only --reserve 32000 --yes >/dev/null

nb_ingress_state_valid || fail 'valid public/mapped ingress state was rejected'
assert_eq 3 "$(jq '.schema_version' "$NOBRAND_INGRESS_STATE_FILE")" 'ingress schema version'
assert_eq 3 "$(jq '.profiles|length' "$NOBRAND_INGRESS_STATE_FILE")" 'explicit profile count'
public_id="$(nb_ingress_profile_id Public-Derived)"
mapped_id="$(nb_ingress_profile_id Mapped-Custom)"
manual_id="$(nb_ingress_profile_id Public-Manual)"
assert_eq '198.51.100.41' "$(jq -r --arg id "$mapped_id" '.profiles[]|select(.profile_id==$id)|.local_address' \
  "$NOBRAND_INGRESS_STATE_FILE")" 'multi-address interface selection'
assert_eq '11001|11099' "$(nb_ingress_profile_auto_range "$public_id")" 'derived-tail range'
assert_eq '[11000]' "$(jq -c --arg id "$public_id" '.profiles[]|select(.profile_id==$id)|.reserved_ports' \
  "$NOBRAND_INGRESS_STATE_FILE")" 'derived-tail default reservation'
assert_eq '30001|30020' "$(nb_ingress_profile_auto_range "$mapped_id")" 'custom range'
assert_eq '[30005,30010]' "$(jq -c --arg id "$mapped_id" '.profiles[]|select(.profile_id==$id)|.reserved_ports' \
  "$NOBRAND_INGRESS_STATE_FILE")" 'multiple custom reservations'
assert_eq '192.0.2.110' "$(nb_ingress_profile_display_host "$public_id")" \
  'public display host defaults to local address'
assert_eq mapped.example.test "$(nb_ingress_profile_display_host "$mapped_id")" \
  'mapped display host is explicit'
assert_eq 443 "$(nb_ingress_profile_display_port "$mapped_id" 30001)" \
  'mapped custom display port'

# Interface/address mismatch and an invalid derived tail fail closed. The
# latter must never escape into the legacy random fallback.
profile_count="$(jq '.profiles|length' "$NOBRAND_INGRESS_STATE_FILE")"
if ( ingress_cli add --name Wrong-Address --type public --interface eth1 \
       --address 203.0.113.20 --port-policy manual-only --yes >/dev/null 2>&1 ); then
  fail 'profile accepted an address assigned to another interface'
fi
if ( ingress_cli add --name Invalid-Derived --type public --interface eth3 \
       --address 192.0.2.10 --port-policy derived-tail --yes >/dev/null 2>&1 ); then
  fail 'invalid derived-tail profile silently fell back'
fi
assert_eq "$profile_count" "$(jq '.profiles|length' "$NOBRAND_INGRESS_STATE_FILE")" \
  'invalid profile writes are atomic'
invalid_state="$fixture/invalid-ingress.json"
jq --arg id "$public_id" '(.profiles[]|select(.profile_id==$id)|.local_address)="192.0.2.10"' \
  "$NOBRAND_INGRESS_STATE_FILE" >"$invalid_state"
if nb_ingress_state_valid "$invalid_state"; then
  fail 'structural validation accepted an invalid explicit derived tail'
fi
jq --arg id "$mapped_id" --arg conflicting_name "$public_id" \
  '(.profiles[]|select(.profile_id==$id)|.name)=$conflicting_name' \
  "$NOBRAND_INGRESS_STATE_FILE" >"$invalid_state"
if nb_ingress_state_valid "$invalid_state"; then
  fail 'structural validation accepted cross-selector name/ID ambiguity'
fi

# The custom allocator skips every reserved port. manual-only never allocates,
# but a free, explicit, non-reserved port remains valid.
NOBRAND_TEST_RANDOM_START=4
assert_eq 30006 "$(nb_select_available_port TCP "$mapped_id")" 'custom allocator skips reserved 30005'
NOBRAND_TEST_RANDOM_START=9
assert_eq 30011 "$(nb_select_available_port UDP "$mapped_id")" 'custom allocator skips reserved 30010'
NOBRAND_TEST_RANDOM_START=0
if nb_select_available_port TCP "$manual_id" >/dev/null 2>&1; then
  fail 'manual-only profile auto-allocated a port'
fi
nb_port_available_for_profile 32001 TCP "$manual_id" \
  || fail 'manual-only profile rejected a valid explicit port'
if nb_port_available_for_profile 32000 TCP "$manual_id"; then
  fail 'manual-only profile accepted a reserved explicit port'
fi
if nb_port_available_for_profile 32001 TCP i0000000000000000; then
  fail 'unknown profile association did not fail closed'
fi

# Exhausted explicit pools never escape into the legacy random fallback.
original_scan_port_span="$(declare -f nb_scan_port_span)"
nb_scan_port_span() { return 1; }
if nb_select_available_port TCP "$public_id" >/dev/null 2>&1; then
  fail 'exhausted derived profile escaped into a fallback port'
fi
if nb_select_available_port UDP "$mapped_id" >/dev/null 2>&1; then
  fail 'exhausted custom profile escaped into a fallback port'
fi
eval "$original_scan_port_span"

# Default selection applies only to newly prepared requests; an explicit
# profile always wins. Existing node bytes are not touched by default changes.
ingress_cli set-default Public-Derived >/dev/null

# A current default cannot be disabled. After explicitly unsetting it, the
# profile can be disabled and re-enabled without rewriting existing nodes.
if ( ingress_cli modify Public-Derived --disable >/dev/null 2>&1 ); then
  fail 'current default profile was disabled'
fi
ingress_cli unset-default >/dev/null
ingress_cli modify Public-Derived --disable >/dev/null
assert_eq false "$(jq -r --arg id "$public_id" '.profiles[]|select(.profile_id==$id)|.enabled' \
  "$NOBRAND_INGRESS_STATE_FILE")" 'unset default permits explicit disable'
ingress_cli modify Public-Derived --enable >/dev/null
ingress_cli set-default Public-Derived >/dev/null

# Profile names cannot enter the generated ID selector namespace.
if ( ingress_cli add --name "$public_id" --type public --interface eth2 \
       --address 203.0.113.20 --port-policy manual-only --yes >/dev/null 2>&1 ); then
  fail 'profile name collided with a generated profile ID'
fi
assert_eq "$public_id" "$(nb_resolve_ingress_profile '')" 'configured default profile'
assert_eq "$mapped_id" "$(nb_resolve_ingress_profile Mapped-Custom)" 'explicit profile overrides default'
before_default_hash="$(sha256sum "$(snell_state_path "$legacy_id")")"
ingress_cli set-default Mapped-Custom >/dev/null
assert_eq "$before_default_hash" "$(sha256sum "$(snell_state_path "$legacy_id")")" \
  'default profile change does not mutate an existing node'
ingress_cli set-default Public-Derived >/dev/null

# The Mieru lifecycle used to enforce its unattended endpoint guard before it
# resolved the configured default Profile.  Exercise the exact lifecycle
# helper with no --ingress-profile and no explicit display flags: the Profile
# display host must be accepted and selected before installation continues.
INGRESS_PROFILE="" INGRESS_PROFILE_ID=""
YES=1 ADVERTISE_HOST="" ADVERTISE_PORT="" ADVERTISE_CLI=0 ADVERTISE_AUTO_REQUESTED=0
mieru_prepare_noninteractive_ingress_endpoint \
  || fail 'Mieru non-interactive install rejected the default Profile display endpoint'
assert_eq "$public_id" "$INGRESS_PROFILE_ID" \
  'Mieru lifecycle resolves default Profile before endpoint validation'

# Mieru receives an automatic profile-selected port and writes it to both
# authoritative state and the actual Mita server configuration.
INGRESS_PROFILE="" INGRESS_PROFILE_ID=""
nb_prepare_ingress_request
# Request globals are consumed by the sourced Mieru production functions.
# shellcheck disable=SC2034
PROTOCOL=TCP
PORT="$(select_available_port)"
# shellcheck disable=SC2034
USERNAME=mieru-profile PASSWORD=mieru-profile-pass
ADVERTISE_HOST="" ADVERTISE_PORT=""
# shellcheck disable=SC2034
PROFILE=balanced MTU=1400 TRAFFIC_PATTERN=conservative TRAFFIC_SEED=42
# shellcheck disable=SC2034
LOW_ENTROPY_MODE=LOW_ENTROPY_MODE_OFF MULTIPLEXING=MULTIPLEXING_OFF HANDSHAKE_MODE=HANDSHAKE_NO_WAIT
users_initialize_primary
assert_eq "$public_id" "$(jq -r '.users[0].ingress_profile_id' "$MITA_USERS_STATE")" \
  'Mieru profile association'
mieru_port="$(jq -r '.users[0].port' "$MITA_USERS_STATE")"
mieru_config="$(write_server_config)"
assert_eq "$mieru_port" "$(jq -r '.portBindings[0].port' "$mieru_config")" \
  'Mieru actual runtime config port'
case "$mieru_port" in 110??) ;; *) fail "Mieru auto port escaped derived profile: $mieru_port" ;; esac

# The compact unified node table must resolve automatic Mieru display metadata
# through the stored Profile just like the detailed Actual/Display/Ingress
# section. Use the mapped Profile's custom display port so a legacy public-IP
# fallback cannot accidentally satisfy this assertion.
mieru_state_before_profile_row="$(mktemp)"
cp "$MITA_USERS_STATE" "$mieru_state_before_profile_row"
jq --arg id "$mapped_id" '(.users[0].ingress_profile_id)=$id' \
  "$MITA_USERS_STATE" >"${MITA_USERS_STATE}.tmp"
mv "${MITA_USERS_STATE}.tmp" "$MITA_USERS_STATE"
assert_contains "$(nb_mieru_node_rows)" 'mapped.example.test:443' \
  'Mieru compact node row uses stored Profile display defaults'
mv "$mieru_state_before_profile_row" "$MITA_USERS_STATE"

# TCP and UDP with the same numeric port can coexist, while another TCP owner
# cannot reuse it merely by selecting a different profile.
nb_port_available_for_profile "$mieru_port" UDP "$mapped_id" \
  || fail 'TCP ownership incorrectly blocked same-number UDP'
if nb_port_available_for_profile "$mieru_port" TCP "$mapped_id"; then
  fail 'same transport/port was incorrectly scoped by profile'
fi

# Snell v5 QUIC stays OFF. Its collector allocates from the default profile,
# and the selected port is written into the wildcard runtime config and state.
PORT="" PORT_AUTO_SELECTED=0 INGRESS_PROFILE="" INGRESS_PROFILE_ID=""
# shellcheck disable=SC2034
SNELL_NAME=snell-profile SNELL_VERSION=5 SNELL_PSK=snell-profile-psk SNELL_QUIC_PROXY=off SNELL_QUIC_CLI=1
YES=1 ADVERTISE_HOST="" ADVERTISE_PORT="" ADVERTISE_CLI=0 ADVERTISE_AUTO_REQUESTED=0
snell_collect_install_requests 0
snell_id=s0000000000000032
snell_generate_server_config "$(snell_config_path "$snell_id")" 5 0.0.0.0 "$PORT" "$SNELL_PSK"
snell_generate_state "$(snell_state_path "$snell_id")" "$snell_id" "$SNELL_NAME" 5 "$SNELL_PSK" \
  0.0.0.0 "$PORT" auto '' '' '' false "$INGRESS_PROFILE_ID"
assert_eq "$public_id" "$(jq -r .ingress_profile_id "$(snell_state_path "$snell_id")")" \
  'Snell profile association'
assert_eq "$PORT" "$(awk -F' = ' '$1=="listen"{split($2,a,":"); print a[2]}' "$(snell_config_path "$snell_id")")" \
  'Snell actual runtime config port'
assert_eq false "$(jq -r .quic_proxy_enabled "$(snell_state_path "$snell_id")")" 'Snell v5 QUIC remains OFF'
snell_port="$PORT"

# HY2 uses the same derived pool independently on UDP and keeps its validated
# wildcard listener semantics.
PORT="" PORT_AUTO_SELECTED=0 INGRESS_PROFILE="" INGRESS_PROFILE_ID=""
YES=1 ADVERTISE_HOST="" ADVERTISE_PORT="" ADVERTISE_CLI=0 ADVERTISE_AUTO_REQUESTED=0 HY2_SNI=www.example.com
hysteria2_configure_requests 0
hysteria2_generate_config "$NOBRAND_HY2_CONFIG_FILE" "$HY2_LISTEN" "$PORT" "$HY2_AUTH" "$HY2_SNI" "$HY2_OBFS" \
  "$NOBRAND_HY2_CERT_FILE" "$NOBRAND_HY2_KEY_FILE"
hysteria2_generate_state "$NOBRAND_HY2_STATE_FILE" "$HY2_LISTEN" "$PORT" "$HY2_AUTH" "$HY2_SNI" "$HY2_OBFS" \
  auto '' '' '' "$INGRESS_PROFILE_ID"
assert_eq "$public_id" "$(jq -r .ingress_profile_id "$NOBRAND_HY2_STATE_FILE")" 'HY2 profile association'
assert_eq "$PORT" "$(jq -r '.inbounds[0].port' "$NOBRAND_HY2_CONFIG_FILE")" 'HY2 actual runtime config port'
assert_eq '0.0.0.0' "$(jq -r '.inbounds[0].listen' "$NOBRAND_HY2_CONFIG_FILE")" 'HY2 wildcard listener unchanged'
hy2_port="$PORT"
assert_eq "$mieru_port" "$hy2_port" 'transport-aware TCP/UDP pool coexistence'

# TUIC uses the next free UDP candidate, stores the association, and leaves
# the server listener on 0.0.0.0.
PORT="" PORT_AUTO_SELECTED=0 INGRESS_PROFILE="" INGRESS_PROFILE_ID=""
# shellcheck disable=SC2034
TUIC_NAME=tuic-profile TUIC_USER=default TUIC_SNI=www.example.com TUIC_CHANNEL=stable TUIC_VERSION=""
YES=1 ADVERTISE_HOST="" ADVERTISE_PORT="" ADVERTISE_CLI=0 ADVERTISE_AUTO_REQUESTED=0
tuic_collect_install_requests
tuic_id=t0000000000000032
tuic_user_id=u0000000000000032
tuic_user="$(tuic_user_json "$tuic_user_id" default 11111111-1111-4111-8111-111111111111 tuic-profile-pass)"
tuic_users="[$tuic_user]"
tuic_cert="$(tuic_cert_file "$tuic_id")"; tuic_key="$(tuic_key_file "$tuic_id")"
tuic_generate_certificate "$tuic_cert" "$tuic_key" "$TUIC_SNI"
mkdir -p "$(tuic_instance_config_dir "$tuic_id")" "$(dirname "$(tuic_state_file "$tuic_id")")"
tuic_generate_server_config "$(tuic_config_file "$tuic_id")" "$tuic_id" 0.0.0.0 "$PORT" \
  "$tuic_cert" "$tuic_key" "$TUIC_SNI" "$tuic_users"
tuic_generate_state "$(tuic_state_file "$tuic_id")" "$tuic_id" "$TUIC_NAME" 0.0.0.0 "$PORT" auto '' '' \
  "$TUIC_SNI" stable 1.13.20 "$tuic_cert" "$tuic_key" "$tuic_users" '' "$INGRESS_PROFILE_ID"
assert_eq "$public_id" "$(jq -r .ingress_profile_id "$(tuic_state_file "$tuic_id")")" \
  'TUIC profile association'
assert_eq "$PORT" "$(jq -r '.inbounds[0].listen_port' "$(tuic_config_file "$tuic_id")")" \
  'TUIC actual runtime config port'
assert_eq '0.0.0.0' "$(jq -r '.inbounds[0].listen' "$(tuic_config_file "$tuic_id")")" \
  'TUIC wildcard listener unchanged'
tuic_port="$PORT"

# VLESS/Sudoku remains the existing plain TCP + FinalMask implementation.
# shellcheck disable=SC2034
PORT="" PORT_AUTO_SELECTED=0 INGRESS_PROFILE="" INGRESS_PROFILE_ID=""
VLESS_SUDOKU_UUID="" VLESS_SUDOKU_PASSWORD=""
YES=1 ADVERTISE_HOST="" ADVERTISE_PORT="" ADVERTISE_CLI=0 ADVERTISE_AUTO_REQUESTED=0
vless_sudoku_configure_requests 0
vless_sudoku_generate_server_config "$NOBRAND_VLESS_CONFIG_FILE" "$VLESS_SUDOKU_LISTEN" "$PORT" \
  "$VLESS_SUDOKU_UUID" "$VLESS_SUDOKU_PASSWORD"
vless_sudoku_generate_state "$NOBRAND_VLESS_STATE_FILE" "$VLESS_SUDOKU_LISTEN" "$PORT" \
  "$VLESS_SUDOKU_UUID" "$VLESS_SUDOKU_PASSWORD" auto '' '' '' "$INGRESS_PROFILE_ID"
vless_effective_host="$(nb_effective_advertise_host auto '' "$INGRESS_PROFILE_ID")"
vless_effective_port="$(nb_effective_advertise_port auto '' "$PORT" "$INGRESS_PROFILE_ID")"
vless_sudoku_generate_client_config "$NOBRAND_VLESS_CLIENT_FILE" "$vless_effective_host" "$vless_effective_port" \
  "$VLESS_SUDOKU_UUID" "$VLESS_SUDOKU_PASSWORD"
assert_eq "$public_id" "$(jq -r .ingress_profile_id "$NOBRAND_VLESS_STATE_FILE")" \
  'VLESS/Sudoku profile association'
assert_eq "$PORT" "$(jq -r '.inbounds[0].port' "$NOBRAND_VLESS_CONFIG_FILE")" \
  'VLESS/Sudoku actual runtime config port'
assert_eq none "$(jq -r '.inbounds[0].settings.decryption' "$NOBRAND_VLESS_CONFIG_FILE")" \
  'VLESS remains plain and does not add REALITY/encryption'
vless_port="$PORT"

# SSH profiles affect display metadata only. The actual system listener stays
# 22 while the derived external-display exception uses 11000.
INGRESS_PROFILE_ID="$public_id"
assert_eq 11000 "$(ssh_tunnel_default_display_port)" 'SSH derived display exception'
ssh_tunnel_generate_state "$NOBRAND_SSH_STATE_FILE" auto '' 11000 22 marker-block \
  "$NOBRAND_SSH_CONFIG_MAIN" '[]' '' "$public_id"
assert_eq 22 "$(jq -r .real_port "$NOBRAND_SSH_STATE_FILE")" 'SSH actual system port'
assert_eq 11000 "$(jq -r .advertise_port "$NOBRAND_SSH_STATE_FILE")" 'SSH display port'
assert_eq "$public_id" "$(jq -r .ingress_profile_id "$NOBRAND_SSH_STATE_FILE")" \
  'SSH profile association'

# Commit Forward candidates into the fixture and render both actual backends;
# this keeps the unit test controlled while exercising production state and
# config generators rather than a helper return value alone.
forward_transaction_commit() {
  local candidate="$1"
  forward_state_valid "$candidate" || return 1
  nb_atomic_install_file "$candidate" "$NOBRAND_FORWARD_STATE_FILE" 0600 || return 1
  forward_generate_nft_ruleset "$NOBRAND_FORWARD_STATE_FILE" "$NOBRAND_FORWARD_NFT_RULESET" || return 1
  forward_generate_realm_config "$NOBRAND_FORWARD_STATE_FILE" "$NOBRAND_FORWARD_REALM_CONFIG"
}

INGRESS_PROFILE="" INGRESS_PROFILE_ID=""
FORWARD_NAME=profile-nft FORWARD_NOTE='profile auto nft' FORWARD_BACKEND=nftables FORWARD_PROTOCOL=TCP
FORWARD_LISTEN_HOST=0.0.0.0 FORWARD_LISTEN_PORT="" FORWARD_TARGET_HOST=203.0.113.80 FORWARD_TARGET_PORT=443
# shellcheck disable=SC2034
FORWARD_SOURCE_MODE=masquerade ADVERTISE_CLI=0 ADVERTISE_AUTO_REQUESTED=0
forward_add_rule >/dev/null
nft_rule_id="$(jq -r '.rules[]|select(.name=="profile-nft")|.rule_id' "$NOBRAND_FORWARD_STATE_FILE")"
nft_port="$(jq -r --arg id "$nft_rule_id" '.rules[]|select(.rule_id==$id)|.listen_port' "$NOBRAND_FORWARD_STATE_FILE")"
assert_eq "$public_id" "$(jq -r --arg id "$nft_rule_id" '.rules[]|select(.rule_id==$id)|.ingress_profile_id' \
  "$NOBRAND_FORWARD_STATE_FILE")" 'nftables Forward profile association'
assert_contains "$(<"$NOBRAND_FORWARD_NFT_RULESET")" "tcp dport ${nft_port}" \
  'nftables actual auto listener port'

# Request globals are consumed by the sourced Forward production functions.
# shellcheck disable=SC2034
INGRESS_PROFILE="" INGRESS_PROFILE_ID=""
# shellcheck disable=SC2034
FORWARD_NAME=profile-realm FORWARD_NOTE='profile auto realm' FORWARD_BACKEND=realm FORWARD_PROTOCOL=UDP
# shellcheck disable=SC2034
FORWARD_LISTEN_HOST=0.0.0.0 FORWARD_LISTEN_PORT="" FORWARD_TARGET_HOST=relay.example.test FORWARD_TARGET_PORT=8443
ADVERTISE_CLI=0 ADVERTISE_AUTO_REQUESTED=0
forward_add_rule >/dev/null
realm_rule_id="$(jq -r '.rules[]|select(.name=="profile-realm")|.rule_id' "$NOBRAND_FORWARD_STATE_FILE")"
realm_port="$(jq -r --arg id "$realm_rule_id" '.rules[]|select(.rule_id==$id)|.listen_port' "$NOBRAND_FORWARD_STATE_FILE")"
assert_eq "$public_id" "$(jq -r --arg id "$realm_rule_id" '.rules[]|select(.rule_id==$id)|.ingress_profile_id' \
  "$NOBRAND_FORWARD_STATE_FILE")" 'Realm Forward profile association'
assert_contains "$(<"$NOBRAND_FORWARD_REALM_CONFIG")" "listen = \"0.0.0.0:${realm_port}\"" \
  'Realm actual auto listener port'

# Profile-auto endpoint resets must resolve through the stored association and
# remain metadata-only for HY2 and VLESS server runtime configuration.
hy2_config_hash="$(sha256sum "$NOBRAND_HY2_CONFIG_FILE")"
# Endpoint request globals are consumed by the sourced protocol functions.
# shellcheck disable=SC2034
INGRESS_PROFILE_ID="$public_id" YES=1 ADVERTISE_CLI=1 ADVERTISE_AUTO_REQUESTED=1 ADVERTISE_HOST="" ADVERTISE_PORT=""
hysteria2_set_endpoint >/dev/null
assert_eq "$hy2_config_hash" "$(sha256sum "$NOBRAND_HY2_CONFIG_FILE")" \
  'HY2 profile display reset leaves runtime config unchanged'
assert_contains "$(jq -r .link "$NOBRAND_HY2_STATE_FILE")" "@192.0.2.110:${hy2_port}?" \
  'HY2 profile display reset uses profile defaults'

vless_config_hash="$(sha256sum "$NOBRAND_VLESS_CONFIG_FILE")"
# shellcheck disable=SC2034
INGRESS_PROFILE_ID="$public_id" YES=1 ADVERTISE_CLI=1 ADVERTISE_AUTO_REQUESTED=1 ADVERTISE_HOST="" ADVERTISE_PORT=""
vless_sudoku_set_endpoint >/dev/null
assert_eq "$vless_config_hash" "$(sha256sum "$NOBRAND_VLESS_CONFIG_FILE")" \
  'VLESS profile display reset leaves runtime config unchanged'
assert_eq '192.0.2.110' "$(jq -r '.outbounds[0].settings.vnext[0].address' "$NOBRAND_VLESS_CLIENT_FILE")" \
  'VLESS profile display reset regenerates client metadata from the profile'

# A referenced mapped profile cannot be deleted. Adding a reservation that
# collides with an existing listener fails, while a range edit does not rewrite
# the listener and is reported as an informational Doctor condition.
mapped_node=s0000000000000099
snell_generate_server_config "$(snell_config_path "$mapped_node")" 5 0.0.0.0 30015 mapped-node-psk
snell_generate_state "$(snell_state_path "$mapped_node")" "$mapped_node" mapped-node 5 mapped-node-psk \
  0.0.0.0 30015 auto '' '' '' false "$mapped_id"
mapped_node_hash="$(sha256sum "$(snell_state_path "$mapped_node")")"
if ( ingress_cli modify Mapped-Custom --reserve 30005,30010,30015 >/dev/null 2>&1 ); then
  fail 'profile modification allowed a reserved-port/listener contradiction'
fi
assert_eq "$mapped_node_hash" "$(sha256sum "$(snell_state_path "$mapped_node")")" \
  'failed reservation edit leaves existing node unchanged'
ingress_cli modify Mapped-Custom --range-start 30101 --range-end 30120 >/dev/null
assert_eq '30101|30120' "$(nb_ingress_profile_auto_range "$mapped_id")" 'modified custom range'
assert_eq "$mapped_node_hash" "$(sha256sum "$(snell_state_path "$mapped_node")")" \
  'range edit does not rewrite existing actual port'
if ( ingress_cli delete Mapped-Custom >/dev/null 2>&1 ); then
  fail 'referenced profile deletion succeeded'
fi

# Profile display defaults remain independent from custom node metadata.
assert_eq mapped.example.test "$(nb_effective_advertise_host auto '' "$mapped_id")" \
  'mapped auto display before modification'
assert_eq custom.example.test "$(nb_effective_advertise_host custom custom.example.test "$mapped_id")" \
  'custom node display overrides profile'
ingress_cli modify Mapped-Custom --display-host mapped-new.example.test >/dev/null
assert_eq mapped-new.example.test "$(nb_effective_advertise_host auto '' "$mapped_id")" \
  'profile display modification affects automatic metadata'
assert_eq custom.example.test "$(nb_effective_advertise_host custom custom.example.test "$mapped_id")" \
  'profile display modification preserves custom node metadata'

# Doctor fails closed when an object references an unknown profile, then
# returns cleanly after the fixture association is restored.
jq ' .ingress_profile_id="i0000000000000000"' "$(snell_state_path "$mapped_node")" >"$invalid_state"
mv "$invalid_state" "$(snell_state_path "$mapped_node")"
if invalid_doctor="$(nb_ingress_doctor 2>&1)"; then
  fail 'Doctor accepted an unknown node ingress association'
fi
assert_contains "$invalid_doctor" 'unknown ingress profile i0000000000000000' \
  'Doctor identifies the unknown profile association'
jq --arg id "$mapped_id" '.ingress_profile_id=$id' "$(snell_state_path "$mapped_node")" >"$invalid_state"
mv "$invalid_state" "$(snell_state_path "$mapped_node")"

# An unreferenced profile can be deleted. The explicit default remains valid,
# and Doctor distinguishes out-of-current-pool state without invalidating it.
# First exercise the full interactive modifier surface on that unreferenced
# profile: type, policy/range, reservation, Display port policy, and enablement.
set_inputs Public-Manual Interactive-Modified 2 '' '' 2 32001 32020 32000 \
  interactive.example.test 2 8443 2
ingress_menu_modify >/dev/null
assert_eq 'Interactive-Modified|mapped|custom-range|32001|32020|32000|interactive.example.test|custom|8443|false' \
  "$(jq -r --arg id "$manual_id" '.profiles[]|select(.profile_id==$id)|
    [.name,.type,.port_policy,.range_start,.range_end,.reserved_ports[0],.display_host_default,
     .display_port_policy,.display_port,.enabled]|join("|")' "$NOBRAND_INGRESS_STATE_FILE")" \
  'interactive modifier covers the complete profile entity'
ingress_cli delete Interactive-Modified >/dev/null
if nb_ingress_profile_json "$manual_id" >/dev/null 2>&1; then
  fail 'unreferenced profile was not deleted'
fi
doctor_output="$(nb_ingress_doctor)"
assert_not_contains "$doctor_output" '[FAIL]' 'Ingress Doctor clean result'
assert_contains "$doctor_output" 'OUTSIDE_CURRENT_AUTO_POOL' 'Doctor range-change observation'
assert_contains "$doctor_output" 'Current system default egress (read-only): eth0 / 192.0.2.110' \
  'Doctor read-only egress observation'
assert_contains "$doctor_output" 'Host-global, transport-aware actual port ownership valid' \
  'Doctor ownership check'

status_output="$(nobrand_status)"
assert_contains "$status_output" 'Default Profile: Public-Derived' 'status default ingress profile'
assert_contains "$status_output" '11001-11099' 'status derived auto range'
assert_contains "$status_output" '30101-30120' 'status custom auto range'
nodes_output="$(nobrand_nodes)"
assert_contains "$nodes_output" 'Actual / Display / Ingress Profile' 'nodes detail section'
assert_contains "$nodes_output" "192.0.2.110:${hy2_port}" 'nodes profile display endpoint'
assert_contains "$nodes_output" 'Ingress: Public-Derived' 'nodes ingress identity'

# Final association inventory covers every protocol and both Forward backends.
assert_eq "$public_id" "$(jq -r '.users[0].ingress_profile_id' "$MITA_USERS_STATE")" 'Mieru final association'
assert_eq "$public_id" "$(jq -r .ingress_profile_id "$(snell_state_path "$snell_id")")" 'Snell final association'
assert_eq "$public_id" "$(jq -r .ingress_profile_id "$NOBRAND_HY2_STATE_FILE")" 'HY2 final association'
assert_eq "$public_id" "$(jq -r .ingress_profile_id "$(tuic_state_file "$tuic_id")")" 'TUIC final association'
assert_eq "$public_id" "$(jq -r .ingress_profile_id "$NOBRAND_VLESS_STATE_FILE")" 'VLESS final association'
assert_eq "$public_id" "$(jq -r .ingress_profile_id "$NOBRAND_SSH_STATE_FILE")" 'SSH final association'
assert_eq 2 "$(jq --arg id "$public_id" '[.rules[]|select(.ingress_profile_id==$id)]|length' \
  "$NOBRAND_FORWARD_STATE_FILE")" 'Forward backend associations'

# Keep variables referenced so ShellCheck also guards the expected allocator
# progression without coupling assertions to a particular random candidate.
for selected_port in "$snell_port" "$tuic_port" "$vless_port" "$nft_port" "$realm_port"; do
  case "$selected_port" in 110??) ;; *) fail "profile-selected port escaped 11001-11099: $selected_port" ;; esac
done

pass 'Ingress profiles, profile-aware allocation, protocol state/config integration, display isolation, and Doctor'
