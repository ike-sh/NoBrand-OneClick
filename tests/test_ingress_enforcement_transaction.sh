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

pass 'Ingress profile changes roll back earlier owners on later failure'
