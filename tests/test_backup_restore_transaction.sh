#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/testlib.sh"

fixture="$(mktemp -d)"
trap 'rm -rf -- "$fixture"' EXIT
export NOBRAND_STATE_DIR="$fixture/nobrand-oneclick/state"
export NOBRAND_CONFIG_DIR="$fixture/nobrand-oneclick/config"
export NOBRAND_LIB_DIR="$fixture/nobrand-oneclick/lib"
export NOBRAND_LIFECYCLE_DIR="$fixture/nobrand-oneclick-lifecycle"
export NOBRAND_LIFECYCLE_TX_FILE="$NOBRAND_LIFECYCLE_DIR/transaction.env"
export NOBRAND_LIFECYCLE_LOCK_FILE="$fixture/run/nobrand-oneclick/lifecycle.lock"
mkdir -p "$(dirname "$NOBRAND_LIFECYCLE_LOCK_FILE")"
chmod 0700 "$(dirname "$NOBRAND_LIFECYCLE_LOCK_FILE")"
export NOBRAND_INSTALL_SCRIPT_PATH="$fixture/bin/install-nobrand"
export NOBRAND_COMMAND_PATH="$fixture/bin/nobrand"
export NOBRAND_SHORT_COMMAND_PATH="$fixture/bin/nb"
export NOBRAND_SSH_CONFIG_MAIN="$fixture/sshd_config"
export NOBRAND_SSH_CONFIG_DROPIN="$fixture/sshd_config.d/90-nobrand-ssh-tunnel.conf"
source_installer
source "$TEST_ROOT/src/15-core-state.sh"
source "$TEST_ROOT/src/18-core-nodes.sh"

# Keep deliberately killed restore-import staging inside the disposable test
# fixture so the test cannot leave unrelated /tmp residue.
mktemp_dir() {
  mktemp -d "$fixture/import-stage.XXXXXX"
}

eval "$(declare -f nobrand_backup_restore_managed_roots \
  | sed '1s/^nobrand_backup_restore_managed_roots /nobrand_backup_restore_managed_roots_real /')"
eval "$(declare -f nobrand_backup_tree_matches \
  | sed '1s/^nobrand_backup_tree_matches /nobrand_backup_tree_matches_real /')"
eval "$(declare -f nobrand_backup_restore_transaction_prepare \
  | sed '1s/^nobrand_backup_restore_transaction_prepare /nobrand_backup_restore_transaction_prepare_real /')"
eval "$(declare -f tc_clear_owned_filters_strict \
  | sed '1s/^tc_clear_owned_filters_strict /tc_clear_owned_filters_strict_real /')"

archive_stage="$fixture/archive-stage"
archive="$fixture/restore.tar.gz"
mkdir -p "$archive_stage/state/ssh-tunnel/keys" \
  "$archive_stage/state/ssh-tunnel/watchdog" \
  "$archive_stage/config/ssh-tunnel/authorized_keys" \
  "$archive_stage/config/ssh-tunnel/accounts"
printf '%s\n' \
  'project=NoBrand-OneClick' \
  'version=3.2.0' \
  'schema_version=3' \
  'ownership=nobrand-v3' \
  'created_at=2026-09-02T00:00:00Z' \
  'contents=state,config' >"$archive_stage/manifest.txt"
printf '%s\n' \
  '{"schema_version":3,"project":"NoBrand-OneClick","ownership":"nobrand-v3"}' \
  >"$archive_stage/state/state.json"
ssh_tunnel_generate_state "$archive_stage/state/ssh-tunnel/state.json" custom \
  restore.example.test 443 2222 marker-block "$NOBRAND_SSH_CONFIG_MAIN" '[]' \
  2026-09-02T00:00:00Z
jq '.policy_applied=true' "$archive_stage/state/ssh-tunnel/state.json" \
  >"$archive_stage/state/ssh-tunnel/state.ready"
mv -f "$archive_stage/state/ssh-tunnel/state.ready" \
  "$archive_stage/state/ssh-tunnel/state.json"
chmod 0700 "$archive_stage/state" "$archive_stage/state/ssh-tunnel" \
  "$archive_stage/state/ssh-tunnel/keys" "$archive_stage/state/ssh-tunnel/watchdog"
chmod 0711 "$archive_stage/config" "$archive_stage/config/ssh-tunnel"
chmod 0755 "$archive_stage/config/ssh-tunnel/authorized_keys"
chmod 0700 "$archive_stage/config/ssh-tunnel/accounts"
chmod 0600 "$archive_stage/state/state.json" \
  "$archive_stage/state/ssh-tunnel/state.json"
tar -C "$archive_stage" -czf "$archive" manifest.txt state config

reset_live_roots() {
  rm -rf -- "$NOBRAND_STATE_DIR" "$NOBRAND_CONFIG_DIR" \
    "$NOBRAND_BACKUP_RESTORE_TX_DIR"
  mkdir -p "$NOBRAND_STATE_DIR" "$NOBRAND_CONFIG_DIR"
  chmod 0700 "$NOBRAND_STATE_DIR" "$NOBRAND_CONFIG_DIR"
  printf '%s\n' \
    '{"schema_version":3,"project":"NoBrand-OneClick","ownership":"nobrand-v3"}' \
    >"$NOBRAND_REGISTRY_FILE"
  printf '%s\n' original-state >"$NOBRAND_STATE_DIR/original.txt"
  printf '%s\n' original-config >"$NOBRAND_CONFIG_DIR/original.txt"
  printf '%s\n' 'Port 2222' >"$NOBRAND_SSH_CONFIG_MAIN"
}

recovery_calls="$fixture/recovery-calls"
reset_recovery_calls() {
  : >"$recovery_calls"
}

record_recovery_call() {
  printf '%s\n' "$1" >>"$recovery_calls"
}

transaction_create_calls="$fixture/transaction-create-calls"
nobrand_backup_restore_transaction_prepare() {
  printf '%s\n' create >>"$transaction_create_calls"
  nobrand_backup_restore_transaction_prepare_real "$@"
}

ssh_tunnel_restore_preflight() { return 0; }
nobrand_fresh_restore_runtime_preflight() { return 0; }
nb_init_state_layout() { return 0; }
nobrand_restore_protocol_runtimes() {
  record_recovery_call runtime-restore
  return 0
}
tc_cleanup_mode=success
tc_clear_owned_filters_strict() {
  record_recovery_call tc-cleanup
  [ "$tc_cleanup_mode" = success ] || return 1
  tc_clear_owned_filters_strict_real "$@"
}
fresh_cleanup_mode=success
nobrand_remove_fresh_restore_protocol_resources() {
  record_recovery_call fresh-cleanup
  [ "$fresh_cleanup_mode" = success ]
}
nobrand_stop_all_services() { return 0; }
tuic_cleanup_mode=success
tuic_remove_restore_attempt_resources() {
  record_recovery_call tuic-cleanup
  [ "$tuic_cleanup_mode" = success ]
}
forward_cleanup_mode=success
forward_remove_restore_attempt_resources() {
  record_recovery_call forward-cleanup
  [ "$forward_cleanup_mode" = success ]
}
tuic_external_rollback=success
tuic_restore_side_effect_snapshot() {
  record_recovery_call tuic-external-restore
  [ "$tuic_external_rollback" = success ]
}
forward_external_rollback=success
forward_restore_side_effect_snapshot() {
  record_recovery_call forward-external-restore
  [ "$forward_external_rollback" = success ]
}
ssh_tunnel_cancel_pending_watchdog() {
  record_recovery_call ssh-watchdog-cancel
  return 0
}
ssh_tunnel_cleanup_disarmed_watchdogs() {
  record_recovery_call ssh-watchdog-cleanup
  return 0
}

ssh_tunnel_snapshot_external_state() {
  mkdir -p "$1"
  command cp -a "$NOBRAND_SSH_CONFIG_MAIN" "$1/main"
  : >"$1/dropin.absent"
  : >"$1/created.log"
}
tuic_snapshot_restore_side_effects() { mkdir -p "$1"; }
forward_snapshot_restore_side_effects() { mkdir -p "$1"; }

ssh_restore_mode=confirmation
ssh_tunnel_restore_system_state() {
  local tmp
  tmp="$(mktemp_file .pending-restore)"
  if [ "$ssh_restore_mode" = complete ]; then
    jq '
        .policy_applied=true
        | .pending_operation=""
        | .pending_watchdog_token=""
        | .pending_watchdog_pid=""
        | .pending_origin_connection=""
      ' "$NOBRAND_SSH_STATE_FILE" >"$tmp"
  else
    jq '
        .policy_applied=true
        | .pending_operation="restore"
        | .pending_watchdog_token="0123456789abcdef0123456789abcdef"
        | .pending_watchdog_pid="4242"
        | .pending_origin_connection="192.0.2.10 41000 192.0.2.20 22"
      ' "$NOBRAND_SSH_STATE_FILE" >"$tmp"
  fi
  nb_atomic_install_file "$tmp" "$NOBRAND_SSH_STATE_FILE" 0600
  rm -f "$tmp"
}

start_mode=success
start_calls=0
nobrand_start_enabled_services() {
  start_calls=$((start_calls + 1))
  if [ "$start_mode" = fail-first ] && [ "$start_calls" -eq 1 ]; then
    return 1
  fi
  return 0
}
external_ssh_rollback=success
ssh_tunnel_restore_external_snapshot() {
  record_recovery_call ssh-external-restore
  [ "$external_ssh_rollback" = success ]
}
managed_root_rollback=success
nobrand_backup_restore_managed_roots() {
  record_recovery_call managed-roots
  [ "$managed_root_rollback" = success ] || return 1
  nobrand_backup_restore_managed_roots_real "$@"
}
tree_match_mode=success
nobrand_backup_tree_matches() {
  if [ "$tree_match_mode" = fail-import-state ] \
     && [ "$2" = "$NOBRAND_STATE_DIR" ] \
     && [ "$1" != "$NOBRAND_BACKUP_RESTORE_SNAPSHOT_DIR/state" ]; then
    return 1
  fi
  if [ "$tree_match_mode" = fail-snapshot-state ] \
     && [ "$1" = "$NOBRAND_STATE_DIR" ] \
     && [[ "$2" == "$NOBRAND_LIFECYCLE_DIR"/.backup-restore.prepare.*/snapshot/state ]]; then
    return 1
  fi
  nobrand_backup_tree_matches_real "$@"
}

prepare_restore_transaction() {
  local status="$1" state_created="${2:-0}" config_created="${3:-0}"
  local fresh_restore="${4:-0}"
  reset_live_roots
  if [ "$state_created" -eq 1 ]; then
    rm -rf -- "$NOBRAND_STATE_DIR"
  fi
  if [ "$config_created" -eq 1 ]; then
    rm -rf -- "$NOBRAND_CONFIG_DIR"
  fi
  nobrand_backup_restore_transaction_prepare "$NOBRAND_STATE_DIR" \
    "$NOBRAND_CONFIG_DIR" "$state_created" "$config_created" "$fresh_restore" \
    "$status"
  nobrand_backup_restore_transaction_valid \
    || fail "could not create a valid ${status} restore transaction fixture"
}

write_imported_roots() {
  mkdir -p "$NOBRAND_STATE_DIR" "$NOBRAND_CONFIG_DIR"
  chmod 0700 "$NOBRAND_STATE_DIR" "$NOBRAND_CONFIG_DIR"
  find "$NOBRAND_STATE_DIR" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
  find "$NOBRAND_CONFIG_DIR" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
  printf '%s\n' imported-state >"$NOBRAND_STATE_DIR/imported.txt"
  printf '%s\n' imported-config >"$NOBRAND_CONFIG_DIR/imported.txt"
}

# Kill a real restore child at each snapshot-publication boundary. Before the
# atomic rename, only a root-owned sibling staging directory may remain and it
# must be invisible to classification. A retry must remove that orphan itself.
# Immediately after the rename, the canonical transaction must already be
# fully valid and ordinary repair recovery must be enough to permit a retry.
assert_interrupted_prepare_recoverable() {
  local phase="$1" expected_published="$2" layout="${3:-existing}"
  local marker child_log child_pid child_rc=""
  local baseline_state classified attempt entry
  local -a staging_dirs=()
  reset_live_roots
  if [ "$layout" = state-only ]; then
    rm -rf -- "$NOBRAND_CONFIG_DIR"
    mkdir -p "$NOBRAND_STATE_DIR/credentials"
    printf '%s\n' 'original-private-key-material' \
      >"$NOBRAND_STATE_DIR/credentials/private.key"
    chmod 0700 "$NOBRAND_STATE_DIR/credentials"
    chmod 0600 "$NOBRAND_STATE_DIR/credentials/private.key"
  else
    mkdir -p "$NOBRAND_STATE_DIR/credentials" "$NOBRAND_CONFIG_DIR/private"
    printf '%s\n' 'original-private-key-material' \
      >"$NOBRAND_STATE_DIR/credentials/private.key"
    printf '%s\n' 'original-private-config' \
      >"$NOBRAND_CONFIG_DIR/private/credentials.json"
    chmod 0700 "$NOBRAND_STATE_DIR/credentials" "$NOBRAND_CONFIG_DIR/private"
    chmod 0600 "$NOBRAND_STATE_DIR/credentials/private.key" \
      "$NOBRAND_CONFIG_DIR/private/credentials.json"
  fi
  baseline_state="$(nb_classify_installation_state)"
  marker="$fixture/interrupted-${layout}-${phase}.ready"
  child_log="$fixture/interrupted-${layout}-${phase}.out"
  ssh_restore_mode=complete
  (
    interrupted_phase="$phase"
    interrupted_marker="$marker"
    nobrand_backup_restore_prepare_checkpoint() {
      [ "$1" != "$interrupted_phase" ] || {
        printf '%s\n' ready >"$interrupted_marker"
        while :; do :; done
      }
    }
    nobrand_backup_restore "$archive"
  ) >"$child_log" 2>&1 &
  child_pid=$!
  for ((attempt = 0; attempt < 500; attempt++)); do
    [ ! -e "$marker" ] || break
    kill -0 "$child_pid" 2>/dev/null || break
    sleep 0.01
  done
  if [ ! -e "$marker" ]; then
    kill -KILL "$child_pid" 2>/dev/null || true
    wait "$child_pid" 2>/dev/null || true
    [ ! -s "$child_log" ] || tail -n 160 "$child_log" >&2
    fail "restore child did not reach preparation checkpoint: ${phase}"
  fi
  kill -KILL "$child_pid"
  set +e
  wait "$child_pid" 2>/dev/null
  child_rc=$?
  set -e
  assert_eq 137 "$child_rc" "${phase} uses a real SIGKILL interruption"
  if [ "$layout" = state-only ]; then
    assert_eq original-private-key-material \
      "$(cat "$NOBRAND_STATE_DIR/credentials/private.key")" \
      "${phase} interruption preserves live private key bytes"
    [ ! -e "$NOBRAND_CONFIG_DIR" ] && [ ! -L "$NOBRAND_CONFIG_DIR" ] \
      || fail "${phase} preparation materialized an absent config root"
  else
    assert_eq original-private-key-material \
      "$(cat "$NOBRAND_STATE_DIR/credentials/private.key")" \
      "${phase} interruption preserves live private key bytes"
    assert_eq 600 \
      "$(stat -c '%a' "$NOBRAND_STATE_DIR/credentials/private.key")" \
      "${phase} interruption preserves live private key mode"
    assert_eq original-private-config \
      "$(cat "$NOBRAND_CONFIG_DIR/private/credentials.json")" \
      "${phase} interruption preserves live private config bytes"
  fi

  if [ "$expected_published" -eq 1 ]; then
    nobrand_backup_restore_transaction_valid \
      || fail "${phase} exposed a partial canonical transaction"
    assert_eq CURRENT_PARTIAL_REPAIR "$(nb_classify_installation_state)" \
      "${phase} published transaction classification"
    entry="$NOBRAND_BACKUP_RESTORE_TX_DIR"
  else
    [ ! -e "$NOBRAND_BACKUP_RESTORE_TX_DIR" ] \
      || fail "${phase} exposed an incomplete canonical transaction"
    classified="$(nb_classify_installation_state)"
    assert_eq "$baseline_state" "$classified" \
      "${phase} orphan staging is invisible to classification"
    if [ -d "$NOBRAND_LIFECYCLE_DIR" ]; then
      mapfile -t staging_dirs < <(find "$NOBRAND_LIFECYCLE_DIR" -mindepth 1 \
        -maxdepth 1 -type d -name '.backup-restore.prepare.*' -print)
    fi
    assert_eq 1 "${#staging_dirs[@]}" \
      "${phase} leaves one isolated preparation directory"
    entry="${staging_dirs[0]}"
    assert_eq 700 "$(stat -c '%a' "$entry")" \
      "${phase} preparation directory mode"
    assert_eq 0 "$(stat -c '%u' "$entry")" \
      "${phase} preparation directory ownership"
  fi
  if [ "$layout" = state-only ]; then
    assert_eq original-private-key-material \
      "$(cat "$entry/snapshot/state/credentials/private.key")" \
      "${phase} asymmetric snapshot preserves private key bytes"
    nb_directory_empty "$entry/snapshot/config" \
      || fail "${phase} asymmetric snapshot fabricated config"
  elif [ "$phase" != snapshot-directory-ready ]; then
    assert_eq original-private-key-material \
      "$(cat "$entry/snapshot/state/credentials/private.key")" \
      "${phase} snapshot preserves private key bytes"
    assert_eq 600 \
      "$(stat -c '%a' "$entry/snapshot/state/credentials/private.key")" \
      "${phase} snapshot preserves private key mode"
    assert_eq 0 \
      "$(stat -c '%u' "$entry/snapshot/state/credentials/private.key")" \
      "${phase} snapshot preserves private key ownership"
  fi
  if [ "$expected_published" -eq 1 ]; then
    nobrand_backup_restore_recover_applying
    [ ! -e "$NOBRAND_BACKUP_RESTORE_TX_DIR" ] \
      || fail "${phase} repair recovery retained the published transaction"
    if [ "$layout" = state-only ]; then
      [ ! -e "$NOBRAND_CONFIG_DIR" ] \
        || fail "${phase} repair recovery retained an originally absent config root"
    fi
  fi

  # No manual staging deletion: the normal retry owns cleanup and must finish
  # with neither a canonical transaction nor an orphan preparation directory.
  nobrand_backup_restore "$archive" >/dev/null
  [ ! -e "$NOBRAND_BACKUP_RESTORE_TX_DIR" ] \
    || fail "${phase} retry retained a canonical transaction"
  staging_dirs=()
  if [ -d "$NOBRAND_LIFECYCLE_DIR" ]; then
    mapfile -t staging_dirs < <(find "$NOBRAND_LIFECYCLE_DIR" -mindepth 1 \
      -maxdepth 1 -name '.backup-restore.prepare.*' -print)
  fi
  assert_eq 0 "${#staging_dirs[@]}" \
    "${phase} retry cleans orphan preparation state"
}

for prepare_phase in snapshot-directory-ready managed-roots-snapshotted \
  external-state-snapshotted manifest-ready metadata-ready; do
  assert_interrupted_prepare_recoverable "$prepare_phase" 0
done
assert_interrupted_prepare_recoverable transaction-published 1
assert_interrupted_prepare_recoverable metadata-ready 0 state-only
assert_interrupted_prepare_recoverable transaction-published 1 state-only
ssh_restore_mode=confirmation

# A successful import with a real SSH confirmation tuple must retain the
# durable global snapshot and classify as a recoverable partial repair.
reset_live_roots
start_mode=success
start_calls=0
external_ssh_rollback=success
managed_root_rollback=success
nobrand_backup_restore "$archive" >/dev/null
nobrand_backup_restore_transaction_valid \
  || fail 'pending SSH restore did not retain a valid durable transaction'
assert_eq pending-ssh-confirmation \
  "$(nb_lifecycle_field STATUS "$NOBRAND_BACKUP_RESTORE_META_FILE")" \
  'pending SSH restore transaction status'
assert_eq original-state \
  "$(cat "$NOBRAND_BACKUP_RESTORE_SNAPSHOT_DIR/state/original.txt")" \
  'pending SSH restore retains original state snapshot'
assert_eq CURRENT_PARTIAL_REPAIR "$(nb_classify_installation_state)" \
  'pending backup restore classification'
if ( nobrand_backup_create "$fixture/unsafe-new-backup.tar.gz" >/dev/null 2>&1 ); then
  fail 'backup creation proceeded while restore acceptance was pending'
fi
[ ! -e "$fixture/unsafe-new-backup.tar.gz" ] \
  || fail 'pending restore created a misleading backup archive'

# `pending-ssh-confirmation` proves that this restore contained SSH state.
# Generic repair acceptance must not turn disappearance of that state into a
# successful confirmation and discard the only global rollback snapshot.
mv "$NOBRAND_SSH_STATE_FILE" "$fixture/pending-ssh-state.saved"
if nobrand_backup_restore_confirmation_finalize repair-accepted >/dev/null 2>&1; then
  fail 'repair acceptance retired a pending transaction after SSH state disappeared'
fi
nobrand_backup_restore_transaction_valid \
  || fail 'missing pending SSH state discarded the durable transaction'
mv "$fixture/pending-ssh-state.saved" "$NOBRAND_SSH_STATE_FILE"

# Model the fresh administrator confirmation commit. The confirmation hook may
# retire the snapshot only after state is policy-applied and nonpending.
jq '
    .policy_applied=true
    | .pending_operation=""
    | .pending_watchdog_token=""
    | .pending_watchdog_pid=""
    | .pending_origin_connection=""
  ' "$NOBRAND_SSH_STATE_FILE" >"$fixture/confirmed-ssh-state.json"
mv -f "$fixture/confirmed-ssh-state.json" "$NOBRAND_SSH_STATE_FILE"
chmod 0600 "$NOBRAND_SSH_STATE_FILE"
nobrand_backup_restore_confirmation_finalize
[ ! -e "$NOBRAND_BACKUP_RESTORE_TX_DIR" ] \
  || fail 'confirmed SSH restore retained the global recovery snapshot'

# Reproduce interruption after both live roots were cleared but before the
# staged archive was copied. Ordinary repair must first restore the durable
# pre-restore snapshot; it must never create a fresh registry in the empty root
# and then retire the only copy of the original state.
prepare_restore_transaction applying
find "$NOBRAND_STATE_DIR" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
find "$NOBRAND_CONFIG_DIR" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
if nobrand_backup_restore_confirmation_finalize repair-accepted >/dev/null 2>&1; then
  fail 'generic repair acceptance retired an applying restore transaction'
fi
nobrand_backup_restore_transaction_valid \
  || fail 'applying restore evidence was discarded before rollback'
reset_recovery_calls
(
  nb_lifecycle_checkpoint() { return 0; }
  install_self_script() { return 0; }
  ensure_manager_state_layout() {
    [ -f "$NOBRAND_STATE_DIR/original.txt" ] \
      || fail 'repair initialized fresh state before restoring the durable snapshot'
  }
  nb_authoritative_protocol_state_exists() { return 1; }
  nb_reconcile_partial_uninstall
)
assert_eq original-state "$(cat "$NOBRAND_STATE_DIR/original.txt")" \
  'interrupted restore repair recovers original state before initialization'
assert_eq original-config "$(cat "$NOBRAND_CONFIG_DIR/original.txt")" \
  'interrupted restore repair recovers original config before initialization'
[ ! -e "$NOBRAND_BACKUP_RESTORE_TX_DIR" ] \
  || fail 'successfully recovered applying transaction retained stale evidence'
applying_calls="$(cat "$recovery_calls")"
assert_contains "$applying_calls" managed-roots \
  'applying recovery restores only the managed roots'
assert_not_contains "$applying_calls" fresh-cleanup \
  'applying recovery skips fresh resource cleanup'
assert_not_contains "$applying_calls" tuic-cleanup \
  'applying recovery skips TUIC attempt cleanup'
assert_not_contains "$applying_calls" forward-cleanup \
  'applying recovery skips Forward attempt cleanup'
assert_not_contains "$applying_calls" tc-cleanup \
  'applying recovery skips TC attempt cleanup'
assert_not_contains "$applying_calls" external-restore \
  'applying recovery skips external snapshot restoration'

# `runtime-applying` owns the imported state until every state-driven cleanup
# succeeds. A partial cleanup must leave that state and phase intact so an
# idempotent retry can use the same authoritative ownership records.
prepare_restore_transaction runtime-applying
write_imported_roots
reset_recovery_calls
tc_cleanup_mode=fail
tuic_cleanup_mode=success
if nobrand_backup_restore_recover_applying >/dev/null 2>&1; then
  fail 'runtime-applying recovery ignored a state-driven cleanup failure'
fi
nobrand_backup_restore_transaction_valid \
  || fail 'runtime cleanup failure invalidated the retained transaction'
assert_eq runtime-applying \
  "$(nb_lifecycle_field STATUS "$NOBRAND_BACKUP_RESTORE_META_FILE")" \
  'runtime cleanup failure retains the imported-state phase'
assert_eq imported-state "$(cat "$NOBRAND_STATE_DIR/imported.txt")" \
  'runtime cleanup failure retains imported state'
assert_eq imported-config "$(cat "$NOBRAND_CONFIG_DIR/imported.txt")" \
  'runtime cleanup failure retains imported config'
runtime_failure_calls="$(cat "$recovery_calls")"
assert_contains "$runtime_failure_calls" tc-cleanup \
  'runtime recovery attempts strict TC cleanup'
assert_contains "$runtime_failure_calls" tuic-cleanup \
  'runtime recovery attempts TUIC cleanup'
assert_contains "$runtime_failure_calls" forward-cleanup \
  'runtime recovery attempts Forward cleanup'
assert_not_contains "$runtime_failure_calls" external-restore \
  'runtime cleanup failure stops before external snapshot restoration'
assert_not_contains "$runtime_failure_calls" managed-roots \
  'runtime cleanup failure stops before managed-root restoration'
tc_cleanup_mode=success
reset_recovery_calls
nobrand_backup_restore_recover_applying
[ ! -e "$NOBRAND_BACKUP_RESTORE_TX_DIR" ] \
  || fail 'successful runtime-applying retry retained stale evidence'

# Asymmetric pre-restore roots are legitimate partial layouts. Recovery must
# remove whichever root the restore created and must not recreate it through
# ordinary state initialization.
prepare_restore_transaction applying 0 1 0
write_imported_roots
start_mode=success
start_calls=0
nobrand_backup_restore_recover_applying
assert_eq original-state "$(cat "$NOBRAND_STATE_DIR/original.txt")" \
  'state-only original layout restores its existing state root'
[ ! -e "$NOBRAND_CONFIG_DIR" ] \
  || fail 'state-only original layout fabricated a config root during rollback'
assert_eq 0 "$start_calls" 'state-only rollback skips service reconciliation'

prepare_restore_transaction applying 1 0 0
write_imported_roots
start_mode=success
start_calls=0
nobrand_backup_restore_recover_applying
[ ! -e "$NOBRAND_STATE_DIR" ] \
  || fail 'config-only original layout fabricated a state root during rollback'
assert_eq original-config "$(cat "$NOBRAND_CONFIG_DIR/original.txt")" \
  'config-only original layout restores its existing config root'
assert_eq 0 "$start_calls" 'config-only rollback skips service reconciliation'

# The durable manifest is recovery evidence, not decoration. Corrupt or
# missing snapshot bytes must fail closed without replacing the imported roots
# or allowing generic repair to initialize new state.
prepare_restore_transaction applying
write_imported_roots
printf '%s\n' corrupted-snapshot \
  >"$NOBRAND_BACKUP_RESTORE_SNAPSHOT_DIR/state/original.txt"
if nobrand_backup_restore_transaction_valid; then
  fail 'corrupted durable root snapshot still validated'
fi
if nobrand_backup_restore_recover_applying >/dev/null 2>&1; then
  fail 'recovery consumed a corrupted durable root snapshot'
fi
assert_eq imported-state "$(cat "$NOBRAND_STATE_DIR/imported.txt")" \
  'corrupted snapshot refusal preserves live state'
assert_eq imported-config "$(cat "$NOBRAND_CONFIG_DIR/imported.txt")" \
  'corrupted snapshot refusal preserves live config'

prepare_restore_transaction applying
write_imported_roots
rm -f "$NOBRAND_BACKUP_RESTORE_SNAPSHOT_DIR/config/original.txt"
if nobrand_backup_restore_transaction_valid; then
  fail 'durable root snapshot with a missing file still validated'
fi
invalid_snapshot_initialized="$fixture/invalid-snapshot-initialized"
if (
  ensure_manager_state_layout() { : >"$invalid_snapshot_initialized"; }
  nb_reconcile_partial_uninstall
) >/dev/null 2>&1; then
  fail 'generic repair accepted a durable snapshot with a missing file'
fi
[ ! -e "$invalid_snapshot_initialized" ] \
  || fail 'generic repair initialized state before rejecting a damaged snapshot'
assert_eq imported-state "$(cat "$NOBRAND_STATE_DIR/imported.txt")" \
  'missing snapshot file refusal preserves live state'
assert_eq imported-config "$(cat "$NOBRAND_CONFIG_DIR/imported.txt")" \
  'missing snapshot file refusal preserves live config'
rm -rf -- "$NOBRAND_BACKUP_RESTORE_TX_DIR"

# An external rollback failure must keep both the durable snapshot and the
# original managed roots, never report a complete rollback, and never replace
# the recovery copy with a new transaction.
reset_live_roots
start_mode=fail-first
start_calls=0
external_ssh_rollback=fail
tuic_external_rollback=success
forward_external_rollback=success
managed_root_rollback=success
reset_recovery_calls
if nobrand_backup_restore "$archive" >"$fixture/external-rollback.out" 2>&1; then
  fail 'backup restore hid an external rollback failure'
fi
nobrand_backup_restore_transaction_valid \
  || fail 'external rollback failure discarded the durable snapshot'
assert_eq rollback-roots \
  "$(nb_lifecycle_field STATUS "$NOBRAND_BACKUP_RESTORE_META_FILE")" \
  'external rollback failure retains the state-independent rollback phase'
assert_eq original-state "$(cat "$NOBRAND_STATE_DIR/original.txt")" \
  'external rollback failure still restores original managed state'
assert_contains "$(cat "$fixture/external-rollback.out")" '恢复快照' \
  'external rollback failure reports retained recovery material'

# A `rollback-roots` retry must not reinterpret restored/live state as
# restore-attempt ownership. It repeats state-independent external restoration,
# restores the roots idempotently, and retires the transaction only at the end.
write_imported_roots
external_ssh_rollback=success
start_mode=success
start_calls=0
reset_recovery_calls
nobrand_backup_restore_recover_applying
rollback_retry_calls="$(cat "$recovery_calls")"
assert_not_contains "$rollback_retry_calls" fresh-cleanup \
  'rollback-roots retry skips fresh resource cleanup'
assert_not_contains "$rollback_retry_calls" tuic-cleanup \
  'rollback-roots retry skips TUIC attempt cleanup'
assert_not_contains "$rollback_retry_calls" forward-cleanup \
  'rollback-roots retry skips Forward attempt cleanup'
assert_contains "$rollback_retry_calls" tuic-external-restore \
  'rollback-roots retry repeats TUIC external restoration'
assert_contains "$rollback_retry_calls" forward-external-restore \
  'rollback-roots retry repeats Forward external restoration'
assert_contains "$rollback_retry_calls" ssh-external-restore \
  'rollback-roots retry repeats SSH external restoration'
assert_contains "$rollback_retry_calls" managed-roots \
  'rollback-roots retry restores managed roots'
assert_eq original-state "$(cat "$NOBRAND_STATE_DIR/original.txt")" \
  'rollback-roots retry restores original managed state'
assert_eq original-config "$(cat "$NOBRAND_CONFIG_DIR/original.txt")" \
  'rollback-roots retry restores original managed config'
[ ! -e "$NOBRAND_BACKUP_RESTORE_TX_DIR" ] \
  || fail 'successful rollback-roots retry retained stale evidence'

# A managed-root rollback failure must likewise retain the only original copy.
reset_live_roots
start_mode=fail-first
start_calls=0
external_ssh_rollback=success
managed_root_rollback=fail
reset_recovery_calls
if nobrand_backup_restore "$archive" >"$fixture/managed-rollback.out" 2>&1; then
  fail 'backup restore hid a managed-root rollback failure'
fi
nobrand_backup_restore_transaction_valid \
  || fail 'managed-root rollback failure discarded the durable snapshot'
assert_eq rollback-roots \
  "$(nb_lifecycle_field STATUS "$NOBRAND_BACKUP_RESTORE_META_FILE")" \
  'managed-root rollback failure retains the state-independent rollback phase'
assert_eq original-state \
  "$(cat "$NOBRAND_BACKUP_RESTORE_SNAPSHOT_DIR/state/original.txt")" \
  'managed-root rollback failure retains the original state snapshot'
managed_root_rollback=success
start_mode=success
nobrand_backup_restore_recover_applying
[ ! -e "$NOBRAND_BACKUP_RESTORE_TX_DIR" ] \
  || fail 'managed-root rollback retry retained stale evidence'

# A second explicit restore must not race the watchdog from an earlier SSH
# policy change. The readiness gate runs before services stop or a durable
# restore transaction is created.
reset_live_roots
mkdir -p "$NOBRAND_SSH_STATE_DIR"
command cp -a "$archive_stage/state/ssh-tunnel/." "$NOBRAND_SSH_STATE_DIR/"
jq '
    .policy_applied=true
    | .pending_operation="restore"
    | .pending_watchdog_token="0123456789abcdef0123456789abcdef"
    | .pending_watchdog_pid="4242"
    | .pending_origin_connection="192.0.2.10 41000 192.0.2.20 22"
  ' "$NOBRAND_SSH_STATE_FILE" >"$fixture/live-pending-ssh-state.json"
mv -f "$fixture/live-pending-ssh-state.json" "$NOBRAND_SSH_STATE_FILE"
chmod 0600 "$NOBRAND_SSH_STATE_FILE"
pending_restore_services="$fixture/pending-restore-services-stopped"
nobrand_stop_all_services() {
  : >"$pending_restore_services"
  return 0
}
: >"$transaction_create_calls"
if ( nobrand_backup_restore "$archive" >"$fixture/pending-restore-refusal.out" 2>&1 ); then
  fail 'backup restore started while live SSH confirmation was pending'
fi
[ ! -e "$pending_restore_services" ] \
  || fail 'pending SSH restore refusal reached service mutation'
[ ! -s "$transaction_create_calls" ] \
  || fail 'pending SSH restore refusal reached transaction creation'
[ ! -e "$NOBRAND_BACKUP_RESTORE_TX_DIR" ] \
  || fail 'pending SSH restore refusal created durable recovery state'
assert_contains "$(cat "$fixture/pending-restore-refusal.out")" '拒绝启动备份恢复' \
  'pending SSH restore refusal explains the readiness gate'

# The phase may advance to `runtime-applying` only after both imported roots
# match their staged source. A post-copy verification failure rolls back before
# any restored runtime is installed.
reset_live_roots
tree_match_mode=fail-import-state
start_mode=success
start_calls=0
external_ssh_rollback=success
managed_root_rollback=success
reset_recovery_calls
if ( nobrand_backup_restore "$archive" >"$fixture/import-verification.out" 2>&1 ); then
  fail 'backup restore accepted an unverified imported state root'
fi
tree_match_mode=success
assert_eq original-state "$(cat "$NOBRAND_STATE_DIR/original.txt")" \
  'import verification failure restores original state'
assert_eq original-config "$(cat "$NOBRAND_CONFIG_DIR/original.txt")" \
  'import verification failure restores original config'
assert_not_contains "$(cat "$recovery_calls")" runtime-restore \
  'import verification failure stops before runtime mutation'
[ ! -e "$NOBRAND_BACKUP_RESTORE_TX_DIR" ] \
  || fail 'rolled-back import verification failure retained stale evidence'

# Snapshot copy must be verified before even the first live service is stopped.
reset_live_roots
services_stopped="$fixture/services-stopped"
nobrand_stop_all_services() { : >"$services_stopped"; }
tree_match_mode=fail-snapshot-state
if nobrand_backup_restore "$archive" >/dev/null 2>&1; then
  fail 'backup restore accepted an incomplete pre-mutation state snapshot'
fi
tree_match_mode=success
[ ! -e "$services_stopped" ] \
  || fail 'backup restore stopped live services before the snapshot copy completed'
assert_eq original-state "$(cat "$NOBRAND_STATE_DIR/original.txt")" \
  'snapshot copy failure preserves live state'
[ ! -e "$NOBRAND_BACKUP_RESTORE_TX_DIR" ] \
  || fail 'pre-mutation snapshot copy failure retained a misleading transaction'

# Strict rollback keeps TC ownership evidence whenever a recorded filter still
# exists, while treating an already-absent filter as an idempotent success.
mkdir -p "$(dirname "$TC_OWNED_STATE")"
printf '%s\n' \
  'iface|lo' \
  "ingress|ip|${TC_PREF_MIN}|tcp|dst_port|23456|10" >"$TC_OWNED_STATE"
tc_show_mode=present
tc() {
  if [ "${1:-}" = filter ] && [ "${2:-}" = del ]; then
    return 2
  fi
  if [ "${1:-}" = filter ] && [ "${2:-}" = show ]; then
    [ "$tc_show_mode" != present ] \
      || printf '%s\n' "filter protocol ip pref ${TC_PREF_MIN} flower"
    return 0
  fi
  return 2
}
if tc_clear_owned_filters_strict_real "$TC_OWNED_STATE"; then
  fail 'strict TC rollback discarded evidence for a surviving filter'
fi
[ -f "$TC_OWNED_STATE" ] \
  || fail 'strict TC rollback removed its manifest after deletion failure'
tc_show_mode=absent
tc_clear_owned_filters_strict_real "$TC_OWNED_STATE"
[ ! -e "$TC_OWNED_STATE" ] \
  || fail 'strict TC rollback retained evidence after proving the filter absent'

pass 'durable backup restore, pending SSH acceptance, and rollback snapshot retention'
