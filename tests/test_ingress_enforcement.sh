#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/testlib.sh"

fixture="$(mktemp -d)"
trap 'rm -rf -- "$fixture"' EXIT

export NOBRAND_STATE_DIR="$fixture/nobrand-oneclick/state"
export NOBRAND_CONFIG_DIR="$fixture/nobrand-oneclick/config"
export NOBRAND_LIB_DIR="$fixture/nobrand-oneclick/lib"
export NOBRAND_TEST_INTERFACE_ROWS=$'eth0|192.0.2.10|UP|1\neth1|198.51.100.10|UP|0'
export NOBRAND_TEST_DEFAULT_EGRESS='eth0|192.0.2.10'
export NOBRAND_TEST_LOCAL_IPV4=192.0.2.10

source_installer
nb_init_state_layout

ingress_cli() {
  ingress_menu_reset_requests
  parse_nobrand_ingress_args "$@"
  nobrand_run_ingress_action
}

nb_port_is_listening() { return 1; }

ingress_cli add --name Strict-A --type public --interface eth0 --address 192.0.2.10 \
  --port-policy manual-only --enforcement strict --yes >/dev/null
ingress_cli add --name Permissive-B --type public --interface eth1 --address 198.51.100.10 \
  --port-policy manual-only --enforcement permissive --yes >/dev/null
strict_id="$(nb_ingress_profile_id Strict-A)"
permissive_id="$(nb_ingress_profile_id Permissive-B)"

assert_eq strict "$(nb_ingress_profile_enforcement "$strict_id")" 'explicit strict profile policy'
assert_eq permissive "$(nb_ingress_profile_enforcement "$permissive_id")" 'explicit permissive profile policy'
assert_contains "$(ingress_cli list)" 'strict' 'Ingress list exposes strict policy'
assert_contains "$(ingress_cli show Strict-A)" 'Ingress enforcement: strict' 'Ingress show exposes strict policy'

legacy_profile="$fixture/legacy-profile.json"
jq 'del(.profiles[1].ingress_enforcement)' "$NOBRAND_INGRESS_STATE_FILE" >"$legacy_profile"
nb_ingress_state_valid "$legacy_profile" || fail 'legacy Profile without enforcement was rejected'
assert_eq permissive "$(jq -r '.profiles[1].ingress_enforcement // "permissive"' "$legacy_profile")" \
  'missing profile enforcement defaults to permissive'
invalid_profile="$fixture/invalid-profile.json"
jq '.profiles[0].ingress_enforcement="invented"' "$NOBRAND_INGRESS_STATE_FILE" >"$invalid_profile"
if nb_ingress_state_valid "$invalid_profile"; then
  fail 'invalid ingress enforcement policy was accepted'
fi

nb_prepare_ingress_deployment "$strict_id" native-bind
assert_eq 'strict|native-bind|192.0.2.10|192.0.2.10' \
  "$INGRESS_ENFORCEMENT_RESOLVED|$INGRESS_ENFORCEMENT_METHOD|$INGRESS_LOCAL_ADDRESS|$INGRESS_LISTEN_HOST" \
  'strict native-bind resolution'
nb_prepare_ingress_deployment "$strict_id" firewall
assert_eq 'strict|firewall|192.0.2.10|0.0.0.0' \
  "$INGRESS_ENFORCEMENT_RESOLVED|$INGRESS_ENFORCEMENT_METHOD|$INGRESS_LOCAL_ADDRESS|$INGRESS_LISTEN_HOST" \
  'strict firewall fallback resolution'
nb_prepare_ingress_deployment "$strict_id" address-match
assert_eq 'strict|address-match|192.0.2.10|192.0.2.10' \
  "$INGRESS_ENFORCEMENT_RESOLVED|$INGRESS_ENFORCEMENT_METHOD|$INGRESS_LOCAL_ADDRESS|$INGRESS_LISTEN_HOST" \
  'strict Forward address-match resolution'
nb_prepare_ingress_deployment "$strict_id" not-applicable
assert_eq 'not-applicable|system-ssh|0.0.0.0' \
  "$INGRESS_ENFORCEMENT_RESOLVED|$INGRESS_ENFORCEMENT_METHOD|$INGRESS_LISTEN_HOST" \
  'system SSH enforcement is not applicable'
nb_prepare_ingress_deployment "$permissive_id" native-bind
assert_eq 'permissive|wildcard|0.0.0.0' \
  "$INGRESS_ENFORCEMENT_RESOLVED|$INGRESS_ENFORCEMENT_METHOD|$INGRESS_LISTEN_HOST" \
  'permissive native-capable runtime remains wildcard'

saved_rows="$NOBRAND_TEST_INTERFACE_ROWS"
NOBRAND_TEST_INTERFACE_ROWS='eth1|198.51.100.10|UP|0'
if nb_prepare_ingress_deployment "$strict_id" native-bind; then
  fail 'strict deployment accepted a Profile address absent from its interface'
fi
NOBRAND_TEST_INTERFACE_ROWS="$saved_rows"

stamped="$fixture/stamped.json"
printf '%s\n' '{"ownership":"fixture"}' >"$stamped"
nb_ingress_stamp_state_file "$stamped" "$strict_id" native-bind
assert_eq 'strict|native-bind|192.0.2.10' \
  "$(jq -r '[.ingress_enforcement,.ingress_enforcement_method,.ingress_local_address]|join("|")' "$stamped")" \
  'resolved node enforcement state stamp'

(
  ss() {
    printf '%s\n' \
      'LISTEN 0 128 0.0.0.0:41001 0.0.0.0:*' \
      'LISTEN 0 128 192.0.2.10:41002 0.0.0.0:*'
  }
  nb_listener_has_local_address TCP 41002 192.0.2.10 \
    || fail 'exact IPv4 listener was not detected'
  if nb_listener_has_local_address TCP 41001 192.0.2.10; then
    fail 'wildcard listener was mistaken for an exact strict listener'
  fi
  nb_wait_for_listener() { return 0; }
  nb_wait_for_enforced_listener '' '' TCP 41001 '' fixture 1 \
    || fail 'legacy missing enforcement did not use permissive listener acceptance'
)

firewall_candidate="$fixture/firewall-candidate.json"
nb_strict_firewall_empty_state >"$firewall_candidate"
jq --arg profile "$strict_id" '.rules=[
  {owner:"mieru:u1111111111111111",ingress_profile_id:$profile,local_address:"192.0.2.10",transport:"TCP",port:41010},
  {owner:"mieru:u1111111111111111",ingress_profile_id:$profile,local_address:"192.0.2.10",transport:"UDP",port:41011}
]' "$firewall_candidate" >"${firewall_candidate}.next"
mv -f "${firewall_candidate}.next" "$firewall_candidate"
nb_strict_firewall_state_valid "$firewall_candidate" || fail 'strict firewall state was rejected'
firewall_ruleset="$fixture/strict.nft"
nb_strict_firewall_generate_ruleset "$firewall_candidate" "$firewall_ruleset"
ruleset_text="$(cat "$firewall_ruleset")"
assert_contains "$ruleset_text" 'policy accept' 'strict firewall does not install a default-drop policy'
assert_contains "$ruleset_text" 'ip daddr != 192.0.2.10 tcp dport 41010 drop' \
  'strict Mieru TCP destination-address isolation rule'
assert_contains "$ruleset_text" 'ip daddr != 192.0.2.10 udp dport 41011 drop' \
  'strict Mieru UDP destination-address isolation rule'
assert_not_contains "$ruleset_text" 'counter' 'strict ingress rules introduce no traffic accounting'

(
  NOBRAND_INGRESS_FIREWALL_STATE_FILE="$fixture/rollback-absent.json"
  apply_calls=0
  nb_strict_firewall_apply_state() {
    apply_calls=$((apply_calls + 1))
    if [ "$apply_calls" -eq 1 ] && [ "$(jq '.rules|length' "$1")" -gt 0 ]; then
      return 1
    fi
    return 0
  }
  if nb_strict_firewall_commit_candidate "$firewall_candidate"; then
    fail 'injected strict firewall failure unexpectedly committed'
  fi
  [ ! -e "$NOBRAND_INGRESS_FIREWALL_STATE_FILE" ] \
    || fail 'failed first strict firewall apply created authoritative state'
)

forward_state="$fixture/forward-strict.json"
realm_options='{"through":"","interface":"","listen_interface":"","tcp_timeout":5,"udp_timeout":30,"proxy_send":false,"proxy_accept":false,"proxy_version":2,"proxy_accept_timeout":5,"dns_mode":"system","dns_protocol":"tcp_and_udp","dns_nameservers":[],"listen_transport":"","remote_transport":"","extra_targets":[],"balance":"off","weights":[]}'
jq -n --arg profile "$strict_id" --argjson realm "$realm_options" '{
  schema_version:3,ownership:"nobrand-v3",feature:"port-forward",rules:[
    {rule_id:"f1111111111111111",name:"strict-nft",note:"",backend:"nftables",enabled:true,protocol:"both",
     listen_host:"192.0.2.10",listen_port:41020,target_host:"203.0.113.20",target_port:42020,
     display_host:"edge.example.test",display_port:443,display_mode:"custom",
     created_at:"2026-09-01T00:00:00Z",updated_at:"2026-09-01T00:00:00Z",
     ownership_metadata:{managed_listener:true,managed_firewall:true},backend_options:{source_mode:"masquerade"},
     ingress_profile_id:$profile,ingress_enforcement:"strict",ingress_enforcement_method:"address-match",
     ingress_local_address:"192.0.2.10"},
    {rule_id:"f2222222222222222",name:"strict-realm",note:"",backend:"realm",enabled:true,protocol:"udp",
     listen_host:"192.0.2.10",listen_port:41021,target_host:"relay.example.test",target_port:42021,
     display_host:"edge.example.test",display_port:8443,display_mode:"custom",
     created_at:"2026-09-01T00:00:00Z",updated_at:"2026-09-01T00:00:00Z",
     ownership_metadata:{managed_listener:true,managed_firewall:true},backend_options:$realm,
     ingress_profile_id:$profile,ingress_enforcement:"strict",ingress_enforcement_method:"native-bind",
     ingress_local_address:"192.0.2.10"}
  ]
}' >"$forward_state"
forward_state_valid "$forward_state" || fail 'strict nftables/Realm Forward state was rejected'
forward_nft="$fixture/forward-strict.nft"
forward_realm="$fixture/forward-strict.toml"
forward_generate_nft_ruleset "$forward_state" "$forward_nft"
forward_generate_realm_config "$forward_state" "$forward_realm"
assert_contains "$(cat "$forward_nft")" 'ip daddr 192.0.2.10 tcp dport 41020' \
  'strict nftables Forward destination-address match'
assert_contains "$(cat "$forward_nft")" 'ip daddr 192.0.2.10 udp dport 41020' \
  'strict nftables Forward BOTH destination-address match'
assert_contains "$(cat "$forward_realm")" 'listen = "192.0.2.10:41021"' \
  'strict Realm native listener address'

mkdir -p "$(dirname "$NOBRAND_FORWARD_STATE_FILE")"
cp -a "$forward_state" "$NOBRAND_FORWARD_STATE_FILE"
forward_export="$fixture/forward-export.json"
forward_export_json "$forward_export"
forward_import_validate "$forward_export" || fail 'strict Forward export was not importable'
assert_eq 'strict|address-match|192.0.2.10' \
  "$(jq -r '.rules[0]|[.ingress_enforcement,.ingress_enforcement_method,.ingress_local_address]|join("|")' "$forward_export")" \
  'strict Forward enforcement fields round-trip unchanged'

(
  nb_registry_rows() { printf '%s\n' 'tuic:t1111111111111111|UDP|41030||'; }
  nb_port_is_listening() { return 1; }
  if nb_port_available_for_profile 41030 UDP "$permissive_id"; then
    fail 'strict Profiles bypassed host-global same-transport port ownership'
  fi
)

(
  lock_depth=0
  admin_lock_acquire() { lock_depth=$((lock_depth + 1)); }
  admin_lock_release() { lock_depth=$((lock_depth - 1)); }
  nb_ingress_add() { return 7; }
  export INGRESS_ACTION=add
  if nobrand_run_ingress_action; then
    fail 'injected ingress action failure unexpectedly succeeded'
  else
    action_rc=$?
  fi
  assert_eq 7 "$action_rc" 'ingress dispatcher preserves action failure status'
  assert_eq 0 "$lock_depth" 'ingress dispatcher releases its administrative lock on failure'
)

(
  state_initialized=0
  lock_depth=0
  require_root() { return 0; }
  nb_init_state_layout() { state_initialized=1; }
  detect_pkg_manager() { printf 'apt'; }
  ensure_management_dependencies() { return 0; }
  admin_lock_acquire() {
    [ "$state_initialized" -eq 1 ] || return 9
    lock_depth=$((lock_depth + 1))
  }
  admin_lock_release() { lock_depth=$((lock_depth - 1)); }
  nobrand_run_forward_action_unlocked() { return 7; }
  export FORWARD_ACTION=add
  if nobrand_run_forward_action; then
    fail 'injected Forward action failure unexpectedly succeeded'
  else
    action_rc=$?
  fi
  assert_eq 7 "$action_rc" 'Forward dispatcher preserves action failure status'
  assert_eq 1 "$state_initialized" 'Forward dispatcher initializes authoritative state before locking'
  assert_eq 0 "$lock_depth" 'Forward dispatcher releases its administrative lock on failure'
)

(
  export DRY_RUN=1
  _ADMIN_LOCK_HELD=0
  admin_lock_acquire
  admin_lock_acquire
  assert_eq 2 "$_ADMIN_LOCK_HELD" 'nested administrative lock depth'
  admin_lock_release
  assert_eq 1 "$_ADMIN_LOCK_HELD" 'nested administrative lock inner release'
  admin_lock_release
  assert_eq 0 "$_ADMIN_LOCK_HELD" 'nested administrative lock final release'
)

pass 'strict/permissive policy, legacy default, deployment mechanisms, firewall, Forward, ownership, and lock contracts'
