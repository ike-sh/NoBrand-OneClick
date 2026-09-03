#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd -P)/testlib.sh"

fixture="$(mktemp -d)"
trap 'rm -rf -- "$fixture"' EXIT

export NOBRAND_STATE_DIR="$fixture/state"
export NOBRAND_CONFIG_DIR="$fixture/config"
export NOBRAND_LIB_DIR="$fixture/lib"
export NOBRAND_BIN_DIR="$fixture/lib/bin"
export NOBRAND_FORWARD_STATE_DIR="$fixture/state/forward"
export NOBRAND_FORWARD_STATE_FILE="$fixture/state/forward/state.json"
export NOBRAND_FORWARD_SYSCTL_STATE="$fixture/state/forward/sysctl.json"
export NOBRAND_FORWARD_SYSCTL_FRAGMENT="$fixture/sysctl.d/90-nobrand-forward.conf"
export NOBRAND_TEST_LOCAL_IPV4=192.0.2.168

source_installer
# Exercise the live source fragment without rebuilding the generated installer.
# shellcheck source=../src/62-forward.sh
source "$TEST_ROOT/src/62-forward.sh"
nb_init_state_layout

live_value="$fixture/live-ip-forward"
sysctl() {
  case "$*" in
    '-n net.ipv4.ip_forward') cat "$live_value" ;;
    '-q -w net.ipv4.ip_forward=0') printf '0\n' >"$live_value" ;;
    '-q -w net.ipv4.ip_forward=1') printf '1\n' >"$live_value" ;;
    *) return 1 ;;
  esac
}

active="$fixture/active.json"
empty="$fixture/empty.json"
cat >"$active" <<'JSON'
{"schema_version":3,"ownership":"nobrand-v3","feature":"port-forward","rules":[
 {"rule_id":"f1111111111111111","name":"sysctl","note":"","backend":"nftables","enabled":true,
  "protocol":"tcp","listen_host":"0.0.0.0","listen_port":16850,
  "target_host":"203.0.113.10","target_port":443,"display_host":"","display_port":16850,
  "display_mode":"auto","created_at":"2026-08-30T00:00:00Z","updated_at":"2026-08-30T00:00:00Z",
  "ownership_metadata":{"managed_listener":true,"managed_firewall":true},
  "backend_options":{"source_mode":"masquerade"}}
]}
JSON
jq '.rules=[]' "$active" >"$empty"

printf '0\n' >"$live_value"
forward_sysctl_reconcile "$active" || fail 'ip_forward original 0 activation'
assert_eq 1 "$(cat "$live_value")" 'NoBrand enables ip_forward for active nft rule'
assert_eq 0 "$(jq -r .original_value "$NOBRAND_FORWARD_SYSCTL_STATE")" 'original 0 recorded'
assert_eq true "$(jq -r .changed_by_nobrand "$NOBRAND_FORWARD_SYSCTL_STATE")" 'owned change recorded'

# Unified restore brings back the valid ownership state, but the generated
# /etc/sysctl.d runtime fragment is intentionally outside the backup archive.
# An absent path is safe to recreate; this must not weaken mismatch handling
# for an existing external file or symlink below.
rm -f "$NOBRAND_FORWARD_SYSCTL_FRAGMENT"
printf '0\n' >"$live_value"
forward_sysctl_reconcile "$active" || fail 'restore recreates missing owned sysctl fragment'
assert_eq 1 "$(cat "$live_value")" 'restored active nft rule re-enables ip_forward'
forward_sysctl_fragment_owned "$NOBRAND_FORWARD_SYSCTL_FRAGMENT" \
  || fail 'restore did not recreate the exact owned sysctl fragment'
assert_eq 0 "$(jq -r .original_value "$NOBRAND_FORWARD_SYSCTL_STATE")" \
  'restored ownership keeps original ip_forward value'
assert_eq true "$(jq -r .changed_by_nobrand "$NOBRAND_FORWARD_SYSCTL_STATE")" \
  'restored ownership records the live change'

forward_sysctl_reconcile "$empty" || fail 'ip_forward original 0 release'
assert_eq 0 "$(cat "$live_value")" 'last nft rule restores owned original 0'
[ ! -e "$NOBRAND_FORWARD_SYSCTL_STATE" ] || fail 'released sysctl ownership state remains'
[ ! -e "$NOBRAND_FORWARD_SYSCTL_FRAGMENT" ] || fail 'released sysctl fragment remains'

printf '1\n' >"$live_value"
forward_sysctl_reconcile "$active" || fail 'ip_forward original 1 activation'
assert_eq false "$(jq -r .changed_by_nobrand "$NOBRAND_FORWARD_SYSCTL_STATE")" 'original 1 is not claimed as changed'
forward_sysctl_reconcile "$empty" || fail 'ip_forward original 1 release'
assert_eq 1 "$(cat "$live_value")" 'external original 1 remains enabled'

mkdir -p "$(dirname "$NOBRAND_FORWARD_SYSCTL_FRAGMENT")"
printf 'net.ipv4.ip_forward = 0\n' >"$NOBRAND_FORWARD_SYSCTL_FRAGMENT"
printf '0\n' >"$live_value"
if forward_sysctl_reconcile "$active"; then
  fail 'NoBrand replaced a pre-existing external sysctl fragment'
fi
assert_eq 0 "$(cat "$live_value")" 'external fragment conflict leaves live value unchanged'
assert_eq 'net.ipv4.ip_forward = 0' "$(cat "$NOBRAND_FORWARD_SYSCTL_FRAGMENT")" \
  'external sysctl fragment preserved'
rm -f "$NOBRAND_FORWARD_SYSCTL_FRAGMENT"

forward_sysctl_reconcile "$active" || fail 'owned sysctl setup before mismatch test'
printf '# external replacement\nnet.ipv4.ip_forward = 1\n' >"$NOBRAND_FORWARD_SYSCTL_FRAGMENT"
if forward_sysctl_reconcile "$empty"; then
  fail 'NoBrand released sysctl state after owned fragment was externally replaced'
fi
assert_eq 1 "$(cat "$live_value")" 'fragment mismatch fails without forcing ip_forward off'
[ -s "$NOBRAND_FORWARD_SYSCTL_STATE" ] || fail 'fragment mismatch must retain ownership state for diagnosis'
assert_eq '# external replacement' "$(sed -n '1p' "$NOBRAND_FORWARD_SYSCTL_FRAGMENT")" \
  'mismatched sysctl fragment preserved'

run_forward_sysctl_snapshot_failure_regressions() (
  set -euo pipefail
  local case_fixture snapshot
  case_fixture="$(mktemp -d)"
  trap 'rm -rf -- "$case_fixture"' EXIT
  NOBRAND_FORWARD_SYSCTL_STATE="$case_fixture/live/sysctl.json"
  NOBRAND_FORWARD_SYSCTL_FRAGMENT="$case_fixture/live/90-nobrand-forward.conf"

  sysctl() { return 71; }
  snapshot="$case_fixture/read-failure"
  if forward_sysctl_snapshot "$snapshot" 2>/dev/null; then
    fail 'Forward sysctl snapshot masked a live-value read failure'
  fi

  sysctl() {
    case "$*" in
      '-n net.ipv4.ip_forward') printf '0\n' ;;
      '-q -w net.ipv4.ip_forward=0') : ;;
      *) return 1 ;;
    esac
  }
  snapshot="$case_fixture/marker-failure"
  mkdir -p "$snapshot/state.absent"
  if forward_sysctl_snapshot "$snapshot" 2>/dev/null; then
    fail 'Forward sysctl snapshot masked an absent-marker write failure'
  fi

  snapshot="$case_fixture/remove-failure"
  mkdir -p "$snapshot" "$(dirname "$NOBRAND_FORWARD_SYSCTL_STATE")"
  : >"$snapshot/state.absent"
  : >"$snapshot/fragment.absent"
  printf '0\n' >"$snapshot/live-value"
  printf '%s\n' state >"$NOBRAND_FORWARD_SYSCTL_STATE"
  printf '%s\n' fragment >"$NOBRAND_FORWARD_SYSCTL_FRAGMENT"
  rm() {
    local arg
    for arg in "$@"; do
      [ "$arg" != "$NOBRAND_FORWARD_SYSCTL_STATE" ] || return 72
    done
    command rm "$@"
  }
  if forward_sysctl_restore_snapshot "$snapshot" 2>/dev/null; then
    fail 'Forward sysctl restore masked an owned-state removal failure'
  fi
)
run_forward_sysctl_snapshot_failure_regressions

pass 'Forward ip_forward ownership/refcount and mismatch safety'
