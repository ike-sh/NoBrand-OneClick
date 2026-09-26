#!/usr/bin/env bash
# shellcheck disable=SC2034
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/testlib.sh"

fixture="$(mktemp -d)"
trap 'rm -rf -- "$fixture"' EXIT
export NOBRAND_STATE_DIR="$fixture/state"
export NOBRAND_CONFIG_DIR="$fixture/config"
export NOBRAND_LIB_DIR="$fixture/lib"
export MITA_INSTANCES_DIR="$fixture/instances"
export MITA_INSTANCE_METRICS_DIR="$fixture/metrics"
source_installer
nb_init_state_layout

harden_mita_permissions() { :; }
install_users_scheduler() { :; }
require_root() { :; }
require_linux() { :; }
mita_installed() { :; }
admin_lock_acquire() { :; }
admin_lock_release() { :; }
public_ip() { printf '198.51.100.50'; }
nb_port_is_listening() { return 1; }
nb_mieru_instance_running() { return 1; }
reconcile_isolated_instances() { prune_orphan_instances; }
apply_tc_limits() { :; }
instance_daemon_stop() { rm -f "$fixture/services/$1"; }
print_user_outputs() { :; }
ip() {
  if [[ " $* " =~ [[:space:]](add|del|delete|replace|flush)[[:space:]] ]]; then
    fail 'Display Endpoint must not mutate Linux routes or policy rules'
  fi
  command ip "$@"
}
apply_users_config() {
  if ! users_validate_state_file "$MITA_USERS_STATE" "$PROTOCOL" "$(public_ip)"; then
    users_tx_rollback "$1" 0
    return 1
  fi
  local id
  mkdir -p "$fixture/services"
  jq -r '.users[]|select(.name=="firewall-failure")|.instance_id' "$MITA_USERS_STATE" \
    >"$fixture/failing-instance-id"
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    mkdir -p "$MITA_INSTANCES_DIR/$id" "$MITA_INSTANCE_METRICS_DIR/$id"
    printf 'listener=%s\n' "$(jq -r --arg id "$id" '.users[]|select(.instance_id==$id)|.port' "$MITA_USERS_STATE")" \
      >"$MITA_INSTANCES_DIR/$id/server.json"
    touch "$fixture/services/$id"
  done < <(jq -r '.users[].instance_id' "$MITA_USERS_STATE")
}
open_firewall_for_pairs() {
  printf '%s\n' "$1" >>"$fixture/firewall-open"
  local pair proto port
  while IFS='|' read -r proto port; do
    [ -n "$proto" ] && [ -n "$port" ] || continue
    firewall_owned_add "iptables|$(proto_lower "$proto")|$port"
    [ "${FIREWALL_FAIL_PORT:-}" != "$port" ] || return 1
  done <<<"$1"
}
close_firewall_for_bindings() {
  printf '%s\n' "$1" >>"$fixture/firewall-close"
  local pair proto port
  while IFS='|' read -r proto port; do
    [ -n "$proto" ] && [ -n "$port" ] || continue
    firewall_owned_remove "iptables|$(proto_lower "$proto")|$port"
  done <<<"$1"
}
tty_values=()
tty_index=0
read_tty() {
  [ "$tty_index" -lt "${#tty_values[@]}" ] || fail "unexpected interactive prompt: $2"
  printf -v "$1" '%s' "${tty_values[$tty_index]}"
  tty_index=$((tty_index + 1))
}

# shellcheck disable=SC2034
PROFILE=balanced PROTOCOL=TCP PORT=3611 PORT_RANGE=""
# shellcheck disable=SC2034
USERNAME=alice PASSWORD=alice-pass
ADVERTISE_HOST=old.example.com ADVERTISE_PORT=443
# shellcheck disable=SC2034
MTU=1400 MTU_POLICY=safe TRAFFIC_PATTERN=off TRAFFIC_SEED=42
# shellcheck disable=SC2034
LOW_ENTROPY_MODE=LOW_ENTROPY_MODE_OFF
# shellcheck disable=SC2034
MULTIPLEXING=MULTIPLEXING_OFF HANDSHAKE_MODE=HANDSHAKE_NO_WAIT
# shellcheck disable=SC2034
MIERU_CHANNEL=stable MIERU_VERSION=3.35.0
users_initialize_primary
save_install_state

add_request() {
  USERNAME="$1" PASSWORD=test-pass PORT="$2" PORT_CLI=1
  USER_PACKAGE=unlimited USER_QUOTA_MB="" USER_QUOTA_DAYS=""
  USER_EXPIRE="" USER_BANDWIDTH_MBPS=0
  ADVERTISE_HOST="${3:-}" ADVERTISE_PORT="${4:-}"
  ADVERTISE_CLI="${5:-0}" ADVERTISE_AUTO_REQUESTED="${6:-0}"
  YES="${7:-1}"
  do_user_add >/dev/null
}

USERNAME=inherited PASSWORD=test-pass PORT=37000 PORT_CLI=1 YES=1
USER_PACKAGE=unlimited ADVERTISE_HOST=old.example.com ADVERTISE_PORT=443 ADVERTISE_CLI=0
do_user_add >/dev/null
assert_eq '' "$(users_get_field inherited advertise_host)" 'unflagged existing primary endpoint is not inherited'

add_request default 37001
assert_eq '' "$(users_get_field default advertise_host)" 'default remains automatic'
assert_eq '' "$(users_get_field default advertise_port)" 'default has no stored display port'
assert_contains "$(nb_mieru_node_rows)" '198.51.100.50:37001' 'automatic address resolver remains active'

tty_values=('') tty_index=0
add_request enter-auto 37002 '' '' 0 0 0
assert_eq 1 "$tty_index" 'interactive Enter chooses automatic endpoint'
assert_eq '' "$(users_get_field enter-auto advertise_host)" 'interactive auto remains empty'

tty_values=('2' 'Edge.Example.COM.' '') tty_index=0
add_request domain 37003 '' '' 0 0 0
assert_eq 3 "$tty_index" 'interactive custom reads host and port'
assert_eq edge.example.com "$(users_get_field domain advertise_host)" 'domain normalized'
assert_eq 37003 "$(users_get_field domain advertise_port)" 'blank display port inherits effective port'

add_request ipv4 37004 203.0.113.10 8443 1
assert_eq 203.0.113.10 "$(users_get_field ipv4 advertise_host)" 'IPv4 persisted'
assert_eq 8443 "$(users_get_field ipv4 advertise_port)" 'custom port persisted'
add_request ipv6 37005 2001:db8::10 9443 1
assert_eq 2001:db8::10 "$(users_get_field ipv6 advertise_host)" 'IPv6 persisted'
add_request host-only 37006 host-only.example.com '' 1
assert_eq 37006 "$(users_get_field host-only advertise_port)" 'CLI host-only inherits effective port'
add_request explicit-auto 37007 '' '' 1 1
assert_eq '' "$(users_get_field explicit-auto advertise_host)" 'CLI advertise-auto remains automatic'

for spec in 'bad host|bad host|443' 'bad ipv6|2001:db8:::1|443' \
  'bad ipv4|999.999.999.999|443' 'bad domain|-bad.example.com|443' \
  'bad port|bad.example.com|65536' 'zero port|bad.example.com|0' \
  'string port|bad.example.com|abc' \
  'blank| |443' 'newline|bad.example.com\n|443' \
  'control|bad.example.com\x01|443' 'collision|old.example.com|443'; do
  IFS='|' read -r label host port <<<"$spec"
  [ "$label" != control ] || host=$'bad.example.com\001'
  [ "$label" != newline ] || host=$'bad.example.com\n'
  before="$(sha256sum "$MITA_USERS_STATE")"
  if ( add_request "$label" 37008 "$host" "$port" 1 >/dev/null 2>&1 ); then
    fail "$label endpoint should be rejected"
  fi
  assert_eq "$before" "$(sha256sum "$MITA_USERS_STATE")" "$label rejection preserves users state"
done

tty_values=('3') tty_index=0
before="$(sha256sum "$MITA_USERS_STATE")"
if add_request cancelled 37009 '' '' 0 0 0 >/dev/null 2>&1; then
  fail 'interactive cancellation should not create user'
fi
assert_eq "$before" "$(sha256sum "$MITA_USERS_STATE")" 'cancel preserves users state'

USERNAME=ipv6 PASSWORD=test-pass PORT=37005 ADVERTISE_HOST="$(users_get_field ipv6 advertise_host)"
ADVERTISE_PORT="$(users_get_field ipv6 advertise_port)"
link="$(generate_share_link_for "$ADVERTISE_HOST" TCP)"
assert_contains "$link" '@[2001:db8::10]?' 'IPv6 URI brackets'
client="$(build_client_json_for "$ADVERTISE_HOST" TCP)"
assert_contains "$client" '"ipAddress": "2001:db8::10"' 'IPv6 client export'
assert_contains "$(nb_mieru_node_rows)" '2001:db8::10:9443' 'IPv6 nodes endpoint'
USERNAME=domain PORT=37003 ADVERTISE_HOST="$(users_get_field domain advertise_host)"
ADVERTISE_PORT="$(users_get_field domain advertise_port)"
assert_contains "$(build_client_json_for "$ADVERTISE_HOST" TCP)" \
  '"domainName": "edge.example.com"' 'domain client export'
assert_contains "$(nb_mieru_node_rows)" 'edge.example.com:37003' 'domain nodes endpoint'
USERNAME=ipv4 PORT=37004 ADVERTISE_HOST="$(users_get_field ipv4 advertise_host)"
ADVERTISE_PORT="$(users_get_field ipv4 advertise_port)"
assert_contains "$(build_client_json_for "$ADVERTISE_HOST" TCP)" \
  '"ipAddress": "203.0.113.10"' 'IPv4 client export'
assert_contains "$(nb_mieru_node_rows)" '203.0.113.10:8443' 'IPv4 nodes endpoint'
assert_contains "$(build_clash_yaml_full "$ADVERTISE_HOST")" \
  'server: "203.0.113.10"' 'IPv4 Mihomo server'
assert_contains "$(build_clash_yaml_full "$ADVERTISE_HOST")" \
  'port: 8443' 'IPv4 Mihomo port'

server_cfg="$(write_server_config_multi)"
assert_not_contains "$(cat "$server_cfg")" '203.0.113.10' 'Display Endpoint absent from Mita server config'
assert_not_contains "$(cat "$server_cfg")" 'edge.example.com' 'Domain absent from Mita server config'
rm -f "$server_cfg"
backup="$(users_backup_now issue-1)"
assert_eq 203.0.113.10 "$(jq -r '.users[] | select(.name=="ipv4") | .advertise_host' "$backup" | tr -d '\r')" \
  'backup retains custom endpoint'
users_set_advertise_endpoint ipv4 changed.example.com 9443
users_restore_from_file "$backup" >/dev/null
assert_eq 203.0.113.10 "$(users_get_field ipv4 advertise_host)" 'restore retains custom host'
assert_eq 8443 "$(users_get_field ipv4 advertise_port)" 'restore retains custom port'

nb_ingress_ensure_state
cat >"$NOBRAND_INGRESS_STATE_FILE" <<'JSON'
{"schema_version":3,"ownership":"nobrand-v3","feature":"ingress-profiles",
 "default_profile_id":"i1111111111111111","profiles":[{
 "profile_id":"i1111111111111111","name":"Mapped-Test","type":"mapped",
 "interface":"eth-test","local_address":"192.0.2.40","port_policy":"manual-only",
 "range_start":null,"range_end":null,"reserved_ports":[],
 "display_host_default":"mapped.example.com","display_port_policy":"custom",
 "display_port":443,"enabled":true,"ingress_enforcement":"permissive",
 "created_at":"2026-09-26T00:00:00Z","updated_at":"2026-09-26T00:00:00Z"}]}
JSON
chmod 0600 "$NOBRAND_INGRESS_STATE_FILE"
nb_ingress_state_valid || fail 'mapped Ingress fixture invalid'
INGRESS_PROFILE=Mapped-Test
mapped_snapshot="$(users_tx_snapshot)"
add_request mapped-case 37011
mapped_auto="$(jq -c '.users[]|select(.name=="mapped-case")|{port,ingress_profile_id,ingress_enforcement,ingress_enforcement_method,ingress_local_address}' "$MITA_USERS_STATE")"
mapped_config="$(write_server_config_multi)"
mapped_auto_config="$(cat "$mapped_config")"
rm -f "$mapped_config"
mapped_auto_fw="$(sha256sum "$MITA_FIREWALL_OWNED_STATE")"
assert_contains "$(nb_mieru_node_rows)" 'mapped.example.com:443' 'mapped automatic display endpoint'
users_tx_restore "$mapped_snapshot"
users_tx_commit "$mapped_snapshot"
add_request mapped-case 37011 custom-mapped.example.com '' 1
assert_eq 443 "$(users_get_field mapped-case advertise_port)" \
  'host-only inherits mapped display port, not listener port'
assert_eq 37011 "$(users_get_field mapped-case port)" 'mapped actual listener port unchanged'
assert_eq "$mapped_auto" "$(jq -c '.users[]|select(.name=="mapped-case")|{port,ingress_profile_id,ingress_enforcement,ingress_enforcement_method,ingress_local_address}' "$MITA_USERS_STATE")" \
  'automatic and custom mapped ingress keep the same data-plane state'
mapped_config="$(write_server_config_multi)"
assert_eq "$mapped_auto_config" "$(cat "$mapped_config")" \
  'automatic and custom mapped ingress keep the same Mita server config'
rm -f "$mapped_config"
assert_eq "$mapped_auto_fw" "$(sha256sum "$MITA_FIREWALL_OWNED_STATE")" \
  'automatic and custom mapped ingress keep firewall ownership'
assert_contains "$(nb_mieru_node_rows)" 'custom-mapped.example.com:443' 'mapped custom nodes endpoint'
INGRESS_PROFILE=

mkdir -p "$NOBRAND_SNELL_STATE_DIR" "$(dirname "$NOBRAND_HY2_STATE_FILE")"
printf '%s\n' '{"protocol":"snell","instance_id":"s0123456789abcdef","version":5,"listen_port":38100,"advertise_host":"snell-conflict.example.com","advertise_port":443,"managed_udp":true}' \
  >"$NOBRAND_SNELL_STATE_DIR/s0123456789abcdef.json"
printf '%s\n' '{"listen_port":38101,"advertise_host":"hy2-conflict.example.com","advertise_port":9443}' \
  >"$NOBRAND_HY2_STATE_FILE"
assert_eq 'snell:s0123456789abcdef' \
  "$(nb_endpoint_conflict_owner TCP snell-conflict.example.com 443)" \
  'Snell owner is present in the shared registry'
assert_eq 'hy2:default' "$(nb_endpoint_conflict_owner UDP hy2-conflict.example.com 9443)" \
  'HY2 owner is present in the shared registry'
cross_state_before="$(sha256sum "$MITA_USERS_STATE")"
cross_fw_before="$(sha256sum "$MITA_FIREWALL_OWNED_STATE")"
if add_request snell-conflict 37012 snell-conflict.example.com 443 1 >/dev/null 2>&1; then
  fail 'Mieru must reject Snell-owned Display Endpoint'
fi
assert_eq "$cross_state_before" "$(sha256sum "$MITA_USERS_STATE")" 'Snell conflict preserves Mieru state'
assert_eq "$cross_fw_before" "$(sha256sum "$MITA_FIREWALL_OWNED_STATE")" \
  'Snell conflict preserves firewall ownership'
cp "$MITA_STATE" "$fixture/mita-state-before-udp"
PROTOCOL=UDP
save_install_state
if add_request hy2-conflict 37013 hy2-conflict.example.com 9443 1 >/dev/null 2>&1; then
  fail 'Mieru must reject HY2-owned Display Endpoint'
fi
cp "$fixture/mita-state-before-udp" "$MITA_STATE"
PROTOCOL=TCP
assert_eq "$cross_state_before" "$(sha256sum "$MITA_USERS_STATE")" 'HY2 conflict preserves Mieru state'
assert_eq "$cross_fw_before" "$(sha256sum "$MITA_FIREWALL_OWNED_STATE")" \
  'HY2 conflict preserves firewall ownership'
assert_eq 'snell:s0123456789abcdef' \
  "$(nb_endpoint_conflict_owner TCP snell-conflict.example.com 443)" \
  'Snell owner survives Mieru conflict'
assert_eq 'hy2:default' "$(nb_endpoint_conflict_owner UDP hy2-conflict.example.com 9443)" \
  'HY2 owner survives Mieru conflict'

invalid_state="$(users_tx_snapshot)"
jq '(.users[]|select(.name=="ipv4")|.advertise_host)="999.999.999.999"' \
  "$invalid_state" >"$invalid_state.tmp"
mv "$invalid_state.tmp" "$invalid_state"
if users_validate_state_file "$invalid_state" TCP "$(public_ip)"; then
  fail 'users state validator accepted invalid dotted-decimal IPv4'
fi
rm -f "$invalid_state" "$invalid_state.norm"

before="$(sha256sum "$MITA_USERS_STATE")"
owned_before="$(sha256sum "$MITA_FIREWALL_OWNED_STATE")"
FIREWALL_FAIL_PORT=37010
if add_request firewall-failure 37010 firewall.example.com 443 1 >/dev/null 2>&1; then
  fail 'firewall failure should reject new user'
fi
FIREWALL_FAIL_PORT=
assert_eq "$before" "$(sha256sum "$MITA_USERS_STATE")" 'firewall failure rolls back users state'
assert_contains "$(cat "$fixture/firewall-close")" '37010' 'firewall failure removes new ownership'
assert_eq "$owned_before" "$(sha256sum "$MITA_FIREWALL_OWNED_STATE")" \
  'firewall failure preserves existing ownership exactly'
assert_not_contains "$(cat "$MITA_FIREWALL_OWNED_STATE")" '37010' 'new firewall ownership removed'
failed_id="$(cat "$fixture/failing-instance-id")"
[ -n "$failed_id" ] || fail 'failed user instance id was not captured'
[ ! -e "$fixture/services/$failed_id" ] || fail 'failed user service remains'
[ ! -e "$MITA_INSTANCES_DIR/$failed_id" ] || fail 'failed user instance remains'
[ ! -e "$MITA_INSTANCE_METRICS_DIR/$failed_id" ] || fail 'failed user metrics remain'
add_request retry-after-firewall 37010 retry.example.com 443 1
assert_eq 37010 "$(users_get_field retry-after-firewall port)" 'port reusable after rollback'
pass 'Mieru user-add custom Display Endpoint and rollback'
