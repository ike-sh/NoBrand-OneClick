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
nb_port_is_listening() { return 1; }

ingress_cli() {
  ingress_menu_reset_requests
  parse_nobrand_ingress_args "$@"
  nobrand_run_ingress_action
}

ingress_cli add --name Transactional --type public --interface eth0 --address 192.0.2.10 \
  --port-policy manual-only --enforcement permissive --yes >/dev/null
profile_id="$(nb_ingress_profile_id Transactional)"

# Profile modification is one transaction: a later owner failure restores the
# exact Profile JSON and reapplies the previous policy to earlier owners.
(
  marker_a="$fixture/owner-a.policy"
  marker_b="$fixture/owner-b.policy"
  printf '%s\n' permissive >"$marker_a"
  printf '%s\n' permissive >"$marker_b"
  apply_log="$fixture/profile-apply.log"
  : >"$apply_log"
  fail_second=0

  nb_ingress_profile_reference_rows() {
    case "$1" in
      "$profile_id") printf '%s\n' 'tuic:t1111111111111111' 'snell:s2222222222222222' ;;
      '*')
        printf '%s\n' \
          "$profile_id|tuic:t1111111111111111" \
          "$profile_id|snell:s2222222222222222"
        ;;
    esac
  }
  nb_ingress_apply_owner() {
    local owner="$1" policy
    policy="$(nb_ingress_profile_enforcement "$profile_id")"
    printf '%s|%s\n' "$owner" "$policy" >>"$apply_log"
    if [ "$owner" = snell:s2222222222222222 ] && [ "$policy" = strict ] \
       && [ "$fail_second" -eq 1 ]; then
      return 1
    fi
    case "$owner" in
      tuic:*) printf '%s\n' "$policy" >"$marker_a" ;;
      snell:*) printf '%s\n' "$policy" >"$marker_b" ;;
    esac
  }

  before_hash="$(sha256sum "$NOBRAND_INGRESS_STATE_FILE")"
  if ( ingress_cli modify Transactional --enforcement strict --yes >/dev/null 2>&1 ); then
    fail 'active Profile enforcement change succeeded without --apply-existing'
  fi
  assert_eq "$before_hash" "$(sha256sum "$NOBRAND_INGRESS_STATE_FILE")" \
    'missing explicit apply leaves Profile state byte-identical'
  assert_eq 0 "$(wc -l <"$apply_log" | tr -d '[:space:]')" \
    'missing explicit apply performs no runtime migration'

  fail_second=1
  if ingress_cli modify Transactional --enforcement strict --apply-existing --yes >/dev/null 2>&1; then
    fail 'injected second-owner Profile migration failure unexpectedly succeeded'
  fi
  assert_eq "$before_hash" "$(sha256sum "$NOBRAND_INGRESS_STATE_FILE")" \
    'failed Profile-wide migration restores exact Profile JSON'
  assert_eq permissive "$(cat "$marker_a")" \
    'failed Profile-wide migration reapplies old policy to an earlier owner'
  assert_eq permissive "$(cat "$marker_b")" \
    'failed owner retains old enforcement policy'
  assert_contains "$(cat "$apply_log")" 'tuic:t1111111111111111|strict' \
    'first owner attempted new strict policy'
  assert_contains "$(cat "$apply_log")" 'tuic:t1111111111111111|permissive' \
    'first owner received compensating permissive apply'

  fail_second=0
  ingress_cli modify Transactional --enforcement strict --apply-existing --yes >/dev/null
  assert_eq strict "$(nb_ingress_profile_enforcement "$profile_id")" \
    'successful explicit Profile-wide migration commits strict policy'
  assert_eq strict "$(cat "$marker_a")" 'successful migration applies first owner'
  assert_eq strict "$(cat "$marker_b")" 'successful migration applies second owner'

  before_explicit="$(wc -l <"$apply_log" | tr -d '[:space:]')"
  ingress_cli apply Transactional >/dev/null
  after_explicit="$(wc -l <"$apply_log" | tr -d '[:space:]')"
  assert_eq 2 "$((after_explicit - before_explicit))" \
    'explicit ingress apply dispatches every non-SSH owner'

  before_metadata_apply="$after_explicit"
  ingress_cli modify Transactional --display-host display.example.test --yes >/dev/null
  after_metadata_apply="$(wc -l <"$apply_log" | tr -d '[:space:]')"
  assert_eq "$before_metadata_apply" "$after_metadata_apply" \
    'Display metadata change performs no listener migration'
  assert_eq strict "$(cat "$marker_a")" 'Display metadata leaves runtime enforcement unchanged'
)

# Exercise a real native-bind state/config transaction with TUIC. The runtime
# and service boundary are mocked, while all candidate generation, state
# stamping, exact file replacement, failure injection, and rollback are the
# production implementation.
tuic_id=t3333333333333333
tuic_state="$(tuic_state_file "$tuic_id")"
tuic_config="$(tuic_config_file "$tuic_id")"
tuic_cert="$(tuic_cert_file "$tuic_id")"
tuic_key="$(tuic_key_file "$tuic_id")"
mkdir -p "$(dirname "$tuic_state")" "$(dirname "$tuic_config")"
printf '%s\n' fixture-certificate >"$tuic_cert"
printf '%s\n' fixture-private-key >"$tuic_key"
tuic_users="[$(tuic_user_json u3333333333333333 alice 33333333-3333-4333-8333-333333333333 \
  fixture-tuic-password 2026-09-01T00:00:00Z)]"
tuic_generate_state "$tuic_state" "$tuic_id" strict-tuic 0.0.0.0 41040 custom \
  edge.example.test 443 tuic.example.test pinned 1.0.0 "$tuic_cert" "$tuic_key" \
  "$tuic_users" 2026-09-01T00:00:00Z "$profile_id"
tuic_generate_server_config "$tuic_config" "$tuic_id" 0.0.0.0 41040 \
  "$tuic_cert" "$tuic_key" tuic.example.test "$tuic_users"
tuic_legacy="$fixture/tuic-legacy.json"
jq '.ingress_enforcement="permissive" | .ingress_enforcement_method="wildcard" |
    .ingress_local_address="192.0.2.10"' "$tuic_state" >"$tuic_legacy"
mv -f "$tuic_legacy" "$tuic_state"

tuic_validate_config() { jq empty "$1" >/dev/null; }
tuic_service_active() { return 0; }
tuic_service_action() {
  printf '%s|%s\n' "$1" "$2" >>"$fixture/tuic-service.log"
  return 0
}
nb_wait_for_enforced_listener() {
  case "$1|$2" in
    strict\|native-bind)
      assert_eq 'strict|native-bind|UDP|41040|192.0.2.10' \
        "$1|$2|$3|$4|$5" 'TUIC strict listener acceptance arguments'
      ;;
    permissive\|wildcard)
      assert_eq 'permissive|wildcard|UDP|41040' \
        "$1|$2|$3|$4" 'TUIC rollback listener acceptance arguments'
      ;;
    *) fail "unexpected TUIC listener enforcement arguments: $1|$2" ;;
  esac
  return 0
}
tuic_listener_owned_by_service() { return 0; }

tuic_state_hash="$(sha256sum "$tuic_state")"
tuic_config_hash="$(sha256sum "$tuic_config")"
tuic_identity_hash="$(jq -Sc '{instance_id,name,listen_port,advertise_mode,advertise_host,advertise_port,sni,tls,users,runtime_channel,runtime_version}' "$tuic_state" | sha256sum)"
NOBRAND_TEST_INGRESS_LISTENER_FAIL=1
export NOBRAND_TEST_INGRESS_LISTENER_FAIL
if tuic_apply_ingress_enforcement "$tuic_id"; then
  fail 'injected TUIC strict listener failure unexpectedly succeeded'
fi
assert_eq "$tuic_state_hash" "$(sha256sum "$tuic_state")" \
  'TUIC listener failure restores exact state'
assert_eq "$tuic_config_hash" "$(sha256sum "$tuic_config")" \
  'TUIC listener failure restores exact config'
assert_contains "$(cat "$fixture/tuic-service.log")" "$tuic_id|restart" \
  'TUIC failure restarts the restored active service'

NOBRAND_TEST_INGRESS_LISTENER_FAIL=0
export NOBRAND_TEST_INGRESS_LISTENER_FAIL
tuic_apply_ingress_enforcement "$tuic_id"
assert_eq '192.0.2.10|strict|native-bind|192.0.2.10' \
  "$(jq -r '[.listen_host,.ingress_enforcement,.ingress_enforcement_method,.ingress_local_address]|join("|")' "$tuic_state")" \
  'TUIC successful strict native-bind state'
assert_eq 192.0.2.10 "$(jq -r '.inbounds[0].listen' "$tuic_config")" \
  'TUIC successful strict native-bind server config'
assert_eq "$tuic_identity_hash" \
  "$(jq -Sc '{instance_id,name,listen_port,advertise_mode,advertise_host,advertise_port,sni,tls,users,runtime_channel,runtime_version}' "$tuic_state" | sha256sum)" \
  'TUIC enforcement migration preserves credentials, TLS, port, runtime, and Display metadata'
assert_contains "$(tuic_show_user "$tuic_id" alice)" '实际监听 / Actual Listener: 192.0.2.10:41040/UDP' \
  'TUIC show reports the real strict listener address'

pass 'Profile-wide explicit migration, compensating rollback, native-bind failure rollback, and identity preservation'
