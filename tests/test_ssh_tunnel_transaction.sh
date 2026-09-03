#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/testlib.sh"

fixture="$(mktemp -d)"
fake_service_pid=""
sigkill_manager_pid=""
orphan_watchdog_pid=""
cleanup() {
  [ -z "$sigkill_manager_pid" ] || kill -KILL "$sigkill_manager_pid" >/dev/null 2>&1 || true
  [ -z "$sigkill_manager_pid" ] || wait "$sigkill_manager_pid" >/dev/null 2>&1 || true
  [ -z "$orphan_watchdog_pid" ] || kill "$orphan_watchdog_pid" >/dev/null 2>&1 || true
  [ -z "$fake_service_pid" ] || kill "$fake_service_pid" >/dev/null 2>&1 || true
  [ -z "$fake_service_pid" ] || wait "$fake_service_pid" >/dev/null 2>&1 || true
  rm -rf -- "$fixture"
}
trap cleanup EXIT
export NOBRAND_STATE_DIR="$fixture/nobrand-oneclick/state"
export NOBRAND_CONFIG_DIR="$fixture/nobrand-oneclick/config"
export NOBRAND_LIB_DIR="$fixture/nobrand-oneclick/lib"
export NOBRAND_LIFECYCLE_DIR="$fixture/nobrand-oneclick-lifecycle"
export NOBRAND_LIFECYCLE_TX_FILE="$NOBRAND_LIFECYCLE_DIR/transaction.env"
export NOBRAND_LIFECYCLE_LOCK_FILE="$fixture/run/nobrand-oneclick/lifecycle.lock"
mkdir -p "$(dirname "$NOBRAND_LIFECYCLE_LOCK_FILE")"
chmod 0700 "$(dirname "$NOBRAND_LIFECYCLE_LOCK_FILE")"
export NOBRAND_SSH_CONFIG_MAIN="$fixture/sshd_config"
export NOBRAND_SSH_CONFIG_DROPIN="$fixture/sshd_config.d/90-nobrand-ssh-tunnel.conf"
export NOBRAND_SSH_WATCHDOG_TIMEOUT=30
source_installer
nb_init_state_layout

fake_sshd="$fixture/sshd"
cat >"$fake_sshd" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = -T ]; then
  printf '%s\n' 'port 2222'
fi
exit 0
EOF
chmod 0755 "$fake_sshd"
( trap : HUP; while :; do sleep 1; done ) &
fake_service_pid=$!
ssh_tunnel_sshd_binary() { printf '%s' "$fake_sshd"; }
ssh_tunnel_detect_service() { printf 'sighup|%s' "$fake_service_pid"; }
ssh_tunnel_reload() { return 0; }
ssh_tunnel_sshd_test() { return 0; }
ssh_tunnel_effective_policy_valid() { return 0; }

key_validation_dir="$fixture/key-validation"
mkdir -p "$key_validation_dir"
ssh-keygen -q -t ed25519 -N '' -f "$key_validation_dir/one"
ssh-keygen -q -t ed25519 -N '' -f "$key_validation_dir/two"
cat "$key_validation_dir/one.pub" "$key_validation_dir/two.pub" \
  >"$key_validation_dir/multiple.pub"
if ssh_tunnel_key_fingerprint "$key_validation_dir/multiple.pub" >/dev/null 2>&1; then
  fail 'multiple public-key records produced a single accepted fingerprint'
fi
if ssh_tunnel_authorized_key_line "$key_validation_dir/multiple.pub" /usr/sbin/nologin \
     >"$key_validation_dir/authorized" 2>/dev/null; then
  fail 'multiple public-key records produced authorized_keys output'
fi
[ ! -s "$key_validation_dir/authorized" ] \
  || fail 'rejected multiple public keys leaked an unrestricted later line'

tuple_token=0123456789abcdef0123456789abcdef
if ssh_tunnel_pending_tuple_valid install "$tuple_token" '' '' true; then
  fail 'a real watchdog token without a PID was accepted'
fi
if ssh_tunnel_pending_tuple_valid install disabled '' \
  '192.0.2.10 41000 192.0.2.20 22' true; then
  fail 'a disabled watchdog tuple retained an origin connection'
fi

# Recursive stale-artifact cleanup is allowed only inside the exact protected
# watchdog namespace and only when that directory remains root-owned 0700.
foreign_watchdog="$fixture/foreign-watchdog"
mkdir -p "$foreign_watchdog"
printf '%s\n' preserve >"$foreign_watchdog/sentinel"
(
  NOBRAND_SSH_WATCHDOG_DIR="$foreign_watchdog"
  if ssh_tunnel_cleanup_disarmed_watchdogs >/dev/null 2>&1; then
    fail 'watchdog cleanup accepted a mismatched namespace'
  fi
  if ssh_tunnel_watchdog_mutation_preflight >/dev/null 2>&1; then
    fail 'watchdog mutation guard accepted a mismatched namespace'
  fi
)
[ -s "$foreign_watchdog/sentinel" ] \
  || fail 'mismatched watchdog cleanup removed a foreign sentinel'

rm -rf -- "$NOBRAND_SSH_WATCHDOG_DIR"
ln -s "$foreign_watchdog" "$NOBRAND_SSH_WATCHDOG_DIR"
if ( ssh_tunnel_cleanup_disarmed_watchdogs >/dev/null 2>&1 ); then
  fail 'watchdog cleanup accepted a symlink root'
fi
if ( ssh_tunnel_watchdog_mutation_preflight >/dev/null 2>&1 ); then
  fail 'watchdog mutation guard accepted a symlink root'
fi
[ -s "$foreign_watchdog/sentinel" ] \
  || fail 'symlinked watchdog cleanup removed a foreign sentinel'
rm -f "$NOBRAND_SSH_WATCHDOG_DIR"
mkdir -p "$NOBRAND_SSH_WATCHDOG_DIR"
printf '%s\n' preserve >"$NOBRAND_SSH_WATCHDOG_DIR/sentinel"
chmod 0755 "$NOBRAND_SSH_WATCHDOG_DIR"
if ssh_tunnel_cleanup_disarmed_watchdogs >/dev/null 2>&1; then
  fail 'watchdog cleanup accepted a non-0700 directory'
fi
if ssh_tunnel_watchdog_mutation_preflight >/dev/null 2>&1; then
  fail 'watchdog mutation guard accepted a non-0700 directory'
fi
[ -s "$NOBRAND_SSH_WATCHDOG_DIR/sentinel" ] \
  || fail 'insecure watchdog cleanup removed its sentinel'
rm -f "$NOBRAND_SSH_WATCHDOG_DIR/sentinel"
chmod 0700 "$NOBRAND_SSH_WATCHDOG_DIR"
printf '%s\n' stale >"$NOBRAND_SSH_WATCHDOG_DIR/disarmed.backup"
ssh_tunnel_watchdog_mutation_preflight \
  || fail 'fully disarmed watchdog artifacts blocked an SSH mutation forever'
ssh_tunnel_cleanup_disarmed_watchdogs
[ ! -e "$NOBRAND_SSH_WATCHDOG_DIR/disarmed.backup" ] \
  || fail 'fully disarmed watchdog artifacts were not cleanable'
: >"$NOBRAND_SSH_WATCHDOG_DIR/unresolved.rollback.sh.running"
if ssh_tunnel_watchdog_mutation_preflight >/dev/null 2>&1; then
  fail 'a running watchdog claim did not block SSH mutation'
fi
if ssh_tunnel_cleanup_disarmed_watchdogs >/dev/null 2>&1; then
  fail 'disarmed cleanup removed a running watchdog claim'
fi
[ -f "$NOBRAND_SSH_WATCHDOG_DIR/unresolved.rollback.sh.running" ] \
  || fail 'running watchdog evidence was discarded'
rm -f "$NOBRAND_SSH_WATCHDOG_DIR/unresolved.rollback.sh.running"

mkdir -p "$NOBRAND_SSH_STATE_DIR"
printf '%s\n' 'Port 2222' >"$NOBRAND_SSH_CONFIG_MAIN"
printf '%s\n' '{"schema_version":3,"ownership":"nobrand-v3","protocol":"ssh-tunnel","policy_applied":false,"pending_operation":"","pending_watchdog_token":"","users":[]}' \
  >"$NOBRAND_SSH_STATE_FILE"
chmod 0600 "$NOBRAND_SSH_STATE_FILE"

config_hash="$(sha256sum "$NOBRAND_SSH_CONFIG_MAIN")"
state_hash="$(sha256sum "$NOBRAND_SSH_STATE_FILE")"
nb_lifecycle_lock_acquire
watchdog="$(NOBRAND_SSH_WATCHDOG_NOW=1 \
  ssh_tunnel_watchdog_begin "$NOBRAND_SSH_CONFIG_MAIN" install)"
IFS='|' read -r token pid _origin operation <<<"$watchdog"
nb_lifecycle_lock_release
(
  nb_lifecycle_lock_acquire
  nb_lifecycle_lock_release
) || fail 'SSH watchdog inherited the lifecycle lock and blocked fresh-admin confirmation'
assert_eq install "$operation" 'SSH watchdog operation identity'
[ -f "${NOBRAND_SSH_WATCHDOG_DIR}/${token}.armed" ] \
  && [ ! -L "${NOBRAND_SSH_WATCHDOG_DIR}/${token}.armed" ] \
  || fail 'watchdog returned before its regular armed claim was ready'
[ ! -e "${NOBRAND_SSH_WATCHDOG_DIR}/${token}.rollback.sh.running" ] \
  && [ ! -e "${NOBRAND_SSH_WATCHDOG_DIR}/${token}.rollback.sh.confirmed" ] \
  || fail 'watchdog returned after losing its rollback claim'
ssh_tunnel_watchdog_claim_ready "$token" "$pid" \
  || fail 'watchdog returned without a live owned rollback process and snapshots'
printf '%s\n' 'BROKEN CONFIG' >"$NOBRAND_SSH_CONFIG_MAIN"
printf '%s\n' '{"broken":true}' >"$NOBRAND_SSH_STATE_FILE"
ssh_tunnel_watchdog_rollback_now "$token" "$pid"
assert_eq "$config_hash" "$(sha256sum "$NOBRAND_SSH_CONFIG_MAIN")" \
  'SSH watchdog restores exact config snapshot'
assert_eq "$state_hash" "$(sha256sum "$NOBRAND_SSH_STATE_FILE")" \
  'SSH watchdog restores exact state snapshot'

# Reproduce the launch/state-commit durability window with real processes. The
# applying shell pauses only at its final state.json commit, after sshd config
# has changed and the real rollback watchdog is armed. SIGKILL must leave a
# discoverable claim that blocks every later mutation until rollback finishes.
sigkill_ready="$fixture/sigkill-before-state-commit.ready"
precommit_config_hash="$(sha256sum "$NOBRAND_SSH_CONFIG_MAIN")"
precommit_state_hash="$(sha256sum "$NOBRAND_SSH_STATE_FILE")"
(
  trap - EXIT
  nb_atomic_install_file() {
    local source="$1" destination="$2" mode="${3:-0600}"
    if [ "$destination" = "$NOBRAND_SSH_STATE_FILE" ]; then
      : >"$sigkill_ready"
      while :; do sleep 1; done
    fi
    command install -m "$mode" "$source" "$destination"
  }
  NOBRAND_SSH_WATCHDOG_TIMEOUT=300 ssh_tunnel_apply_policy nobody install \
    >/dev/null 2>&1
) &
sigkill_manager_pid=$!
sigkill_wait_attempts=0
while [ ! -e "$sigkill_ready" ]; do
  kill -0 "$sigkill_manager_pid" 2>/dev/null \
    || fail 'SSH apply exited before reaching the watchdog/state-commit window'
  sigkill_wait_attempts=$((sigkill_wait_attempts + 1))
  [ "$sigkill_wait_attempts" -lt 500 ] \
    || fail 'SSH apply did not reach the watchdog/state-commit window'
  sleep 0.01
done
kill -KILL "$sigkill_manager_pid"
wait "$sigkill_manager_pid" >/dev/null 2>&1 || true
sigkill_manager_pid=""

assert_eq "$precommit_state_hash" "$(sha256sum "$NOBRAND_SSH_STATE_FILE")" \
  'SIGKILL before state commit leaves the previous authoritative state'
[ "$precommit_config_hash" != "$(sha256sum "$NOBRAND_SSH_CONFIG_MAIN")" ] \
  || fail 'SIGKILL fixture did not cross the sshd-config mutation boundary'
assert_contains "$(cat "$NOBRAND_SSH_CONFIG_MAIN")" "$NOBRAND_SSH_BLOCK_BEGIN" \
  'SIGKILL fixture leaves the uncommitted SSH policy mutation visible'
orphan_armed="$(find "$NOBRAND_SSH_WATCHDOG_DIR" -mindepth 1 -maxdepth 1 \
  -name '*.armed' -print)"
[ -n "$orphan_armed" ] \
  && [ "$(printf '%s\n' "$orphan_armed" | wc -l | tr -d '[:space:]')" = 1 ] \
  || fail 'SIGKILL window did not retain exactly one durable armed claim'
orphan_token="${orphan_armed##*/}"
orphan_token="${orphan_token%.armed}"
for orphan_proc in /proc/[0-9]*; do
  orphan_candidate_pid="${orphan_proc##*/}"
  if ssh_tunnel_watchdog_pid_matches "$orphan_token" "$orphan_candidate_pid"; then
    orphan_watchdog_pid="$orphan_candidate_pid"
    break
  fi
done
[ -n "$orphan_watchdog_pid" ] \
  || fail 'SIGKILL window did not leave the owned rollback subprocess alive'
assert_eq '' "$(ssh_tunnel_state_field pending_watchdog_token 2>/dev/null || true)" \
  'SIGKILL window precedes pending-token state commit'

blocked_config_hash="$(sha256sum "$NOBRAND_SSH_CONFIG_MAIN")"
blocked_state_hash="$(sha256sum "$NOBRAND_SSH_STATE_FILE")"
blocked_apply_rc=0
if ssh_tunnel_apply_policy nobody install >/dev/null 2>&1; then
  fail 'a second SSH policy transaction raced an uncommitted armed watchdog'
else
  blocked_apply_rc=$?
fi
assert_eq 75 "$blocked_apply_rc" \
  'an uncommitted armed watchdog reports unresolved rollback ownership'
blocked_endpoint_rc=0
if ssh_tunnel_set_endpoint_state replacement.example.test 8443 >/dev/null 2>&1; then
  fail 'an endpoint mutation raced an uncommitted armed watchdog'
else
  blocked_endpoint_rc=$?
fi
assert_eq 75 "$blocked_endpoint_rc" \
  'an armed watchdog blocks non-policy SSH state mutations'
assert_eq "$blocked_config_hash" "$(sha256sum "$NOBRAND_SSH_CONFIG_MAIN")" \
  'blocked rerun preserves the uncommitted config for its owning watchdog'
assert_eq "$blocked_state_hash" "$(sha256sum "$NOBRAND_SSH_STATE_FILE")" \
  'blocked rerun preserves the watchdog snapshot state'

ssh_tunnel_watchdog_rollback_now "$orphan_token" "$orphan_watchdog_pid"
assert_eq "$precommit_config_hash" "$(sha256sum "$NOBRAND_SSH_CONFIG_MAIN")" \
  'orphan watchdog restores config after its manager is SIGKILLed'
assert_eq "$precommit_state_hash" "$(sha256sum "$NOBRAND_SSH_STATE_FILE")" \
  'orphan watchdog restores state after its manager is SIGKILLed'
ssh_tunnel_watchdog_mutation_preflight \
  || fail 'completed orphan-watchdog rollback did not release the mutation boundary'
orphan_stop_attempts=0
while kill -0 "$orphan_watchdog_pid" 2>/dev/null; do
  orphan_stop_attempts=$((orphan_stop_attempts + 1))
  if [ "$orphan_stop_attempts" -ge 100 ]; then
    kill -KILL "$orphan_watchdog_pid" >/dev/null 2>&1 || true
    break
  fi
  sleep 0.01
done
orphan_watchdog_pid=""

# External backup rollback must preserve symlink objects themselves. A
# relative link becomes dangling inside the snapshot directory, so `-e` alone
# is not a valid presence check there.
relative_target="$(dirname "$NOBRAND_SSH_CONFIG_MAIN")/sshd_config.real"
mv "$NOBRAND_SSH_CONFIG_MAIN" "$relative_target"
ln -s "$(basename "$relative_target")" "$NOBRAND_SSH_CONFIG_MAIN"
relative_snapshot="$(mktemp -d)"
ssh_tunnel_snapshot_external_state "$relative_snapshot"
rm -f "$NOBRAND_SSH_CONFIG_MAIN"
printf '%s\n' mutated >"$NOBRAND_SSH_CONFIG_MAIN"
ssh_tunnel_restore_external_snapshot "$relative_snapshot"
[ -L "$NOBRAND_SSH_CONFIG_MAIN" ] \
  || fail 'external SSH snapshot flattened a relative config symlink'
assert_eq "$(basename "$relative_target")" "$(readlink "$NOBRAND_SSH_CONFIG_MAIN")" \
  'external SSH snapshot preserves the relative symlink target'
assert_eq 'Port 2222' "$(cat "$NOBRAND_SSH_CONFIG_MAIN")" \
  'external SSH snapshot restores the relative symlink content target'
rm -rf -- "$relative_snapshot"
rm -f "$NOBRAND_SSH_CONFIG_MAIN"
mv "$relative_target" "$NOBRAND_SSH_CONFIG_MAIN"

mv "$NOBRAND_SSH_CONFIG_MAIN" "$relative_target"
ln -s "$(basename "$relative_target")" "$NOBRAND_SSH_CONFIG_MAIN"
symlink_watchdog="$(ssh_tunnel_watchdog_begin "$NOBRAND_SSH_CONFIG_MAIN" install)"
IFS='|' read -r symlink_token symlink_pid _symlink_origin _symlink_operation \
  <<<"$symlink_watchdog"
rm -f "$NOBRAND_SSH_CONFIG_MAIN"
printf '%s\n' mutated >"$NOBRAND_SSH_CONFIG_MAIN"
ssh_tunnel_watchdog_rollback_now "$symlink_token" "$symlink_pid"
[ -L "$NOBRAND_SSH_CONFIG_MAIN" ] \
  || fail 'generated watchdog rollback flattened a relative config symlink'
assert_eq "$(basename "$relative_target")" "$(readlink "$NOBRAND_SSH_CONFIG_MAIN")" \
  'generated watchdog rollback preserves a relative symlink target'
rm -f "$NOBRAND_SSH_CONFIG_MAIN"
mv "$relative_target" "$NOBRAND_SSH_CONFIG_MAIN"

rm -f "$NOBRAND_SSH_CONFIG_MAIN"
ln -s missing-sshd-config "$NOBRAND_SSH_CONFIG_MAIN"
dangling_snapshot="$(mktemp -d)"
ssh_tunnel_snapshot_external_state "$dangling_snapshot"
rm -f "$NOBRAND_SSH_CONFIG_MAIN"
printf '%s\n' mutated >"$NOBRAND_SSH_CONFIG_MAIN"
ssh_tunnel_restore_external_snapshot "$dangling_snapshot"
[ -L "$NOBRAND_SSH_CONFIG_MAIN" ] \
  || fail 'external SSH snapshot discarded a dangling config symlink'
assert_eq missing-sshd-config "$(readlink "$NOBRAND_SSH_CONFIG_MAIN")" \
  'external SSH snapshot preserves a dangling symlink target'
rm -rf -- "$dangling_snapshot"
rm -f "$NOBRAND_SSH_CONFIG_MAIN"
printf '%s\n' 'Port 2222' >"$NOBRAND_SSH_CONFIG_MAIN"

# watchdog_begin is always consumed through a conditional assignment by the
# policy callers. Every prerequisite must therefore return explicitly: Bash
# suppresses errexit inside a function whose status is being tested. Inject
# failures at each durable artifact boundary and ensure no success tuple or
# background rollback process escapes.
exercise_watchdog_begin_failure() {
  local stage="$1" case_dir token base target_hash state_hash_before=''
  case_dir="$fixture/watchdog-begin-failures/$stage"
  token=44444444444444444444444444444444
  base="${NOBRAND_SSH_WATCHDOG_DIR}/${token}"
  rm -rf -- "$NOBRAND_SSH_WATCHDOG_DIR" "$case_dir"
  mkdir -p "$NOBRAND_SSH_WATCHDOG_DIR" "$case_dir"
  chmod 0700 "$NOBRAND_SSH_WATCHDOG_DIR"
  printf '%s\n' 'Port 2222' >"$NOBRAND_SSH_CONFIG_MAIN"
  if [ "$stage" = state-absent-sentinel ]; then
    rm -f "$NOBRAND_SSH_STATE_FILE"
    mkdir "${base}.state.absent"
  else
    printf '%s\n' '{"snapshot":true}' >"$NOBRAND_SSH_STATE_FILE"
    chmod 0600 "$NOBRAND_SSH_STATE_FILE"
    state_hash_before="$(sha256sum "$NOBRAND_SSH_STATE_FILE")"
  fi
  case "$stage" in
    armed-create) mkdir "${base}.armed" ;;
    script-create) mkdir "${base}.rollback.sh" ;;
  esac
  target_hash="$(sha256sum "$NOBRAND_SSH_CONFIG_MAIN")"
  (
    trap - EXIT
    ssh_tunnel_watchdog_mutation_preflight() { return 0; }
    openssl() { printf '%s' "$token"; }
    ssh_tunnel_detect_service() { printf 'sighup|4242'; }
    ssh_tunnel_sshd_binary() { printf '%s' "$fake_sshd"; }
    cp() {
      local arg
      for arg in "$@"; do
        [ "$stage" != config-snapshot ] || [ "$arg" != "$NOBRAND_SSH_CONFIG_MAIN" ] \
          || return 71
        [ "$stage" != state-snapshot ] || [ "$arg" != "$NOBRAND_SSH_STATE_FILE" ] \
          || return 72
      done
      command cp "$@"
    }
    chmod() {
      local arg
      if [ "$stage" = script-chmod ]; then
        for arg in "$@"; do
          [ "$arg" != "${base}.rollback.sh" ] || return 73
        done
      fi
      command chmod "$@"
    }
    nohup() {
      : >"$case_dir/background-launched"
      return 0
    }
    if [ "$stage" = script-mid-write ]; then
      ssh_tunnel_write_watchdog_script() {
        command printf '%s\n' '#!/usr/bin/env bash' 'partial rollback'
        return 73
      }
    fi
    watchdog=''
    if watchdog="$(ssh_tunnel_watchdog_begin "$NOBRAND_SSH_CONFIG_MAIN" install 2>/dev/null)"; then
      : >"$case_dir/accepted"
    else
      printf '%s' "$?" >"$case_dir/rc"
    fi
    wait 2>/dev/null || true
    printf '%s' "$watchdog" >"$case_dir/output"
  )
  [ ! -e "$case_dir/accepted" ] \
    || fail "watchdog_begin hid the ${stage} failure under conditional assignment"
  [ -s "$case_dir/rc" ] && [ "$(cat "$case_dir/rc")" -ne 0 ] \
    || fail "watchdog_begin did not propagate the ${stage} failure status"
  [ ! -s "$case_dir/output" ] \
    || fail "watchdog_begin emitted a success tuple after the ${stage} failure"
  [ ! -e "$case_dir/background-launched" ] \
    || fail "watchdog_begin launched rollback after the ${stage} failure"
  assert_eq "$target_hash" "$(sha256sum "$NOBRAND_SSH_CONFIG_MAIN")" \
    "watchdog_begin ${stage} failure preserves SSH config"
  if [ "$stage" = state-absent-sentinel ]; then
    [ ! -e "$NOBRAND_SSH_STATE_FILE" ] \
      || fail 'failed absent-state sentinel creation fabricated SSH state'
  else
    assert_eq "$state_hash_before" "$(sha256sum "$NOBRAND_SSH_STATE_FILE")" \
      "watchdog_begin ${stage} failure preserves SSH state"
  fi
  case "$stage" in
    armed-create|script-create|state-absent-sentinel) ;;
    *)
      for watchdog_artifact in \
        "${base}.backup" "${base}.backup.absent" \
        "${base}.state.backup" "${base}.state.absent" \
        "${base}.rollback.sh" "${base}.armed" \
        "${base}.rollback.sh.running" "${base}.rollback.sh.confirmed" \
        "${base}.rollback.sh.cancelled"; do
        [ ! -e "$watchdog_artifact" ] && [ ! -L "$watchdog_artifact" ] \
          || fail "watchdog_begin ${stage} failure leaked $(basename "$watchdog_artifact")"
      done
      ;;
  esac
}

for watchdog_failure_stage in \
  config-snapshot state-snapshot state-absent-sentinel \
  armed-create script-create script-chmod script-mid-write; do
  exercise_watchdog_begin_failure "$watchdog_failure_stage"
done

# Fixed-name sshd targets are not ownership proof. Build authoritative state
# explicitly so the following cases distinguish a legitimate restore from a
# foreign collision rather than merely exercising malformed state handling.
write_ssh_config_target_state() {
  local strategy="$1" managed_path="$2" policy_applied="$3" tmp
  tmp="$(mktemp_file .ssh-target-state)" || return 1
  ssh_tunnel_generate_state "$tmp" custom entry.example.test 443 2222 \
    "$strategy" "$managed_path" '[]' 2026-08-30T00:00:00Z || {
      rm -f "$tmp"
      return 1
    }
  jq --argjson applied "$policy_applied" '.policy_applied=$applied' \
    "$tmp" >"$NOBRAND_SSH_STATE_FILE" || {
      rm -f "$tmp"
      return 1
    }
  rm -f "$tmp"
  chmod 0600 "$NOBRAND_SSH_STATE_FILE"
}

mkdir -p "$(dirname "$NOBRAND_SSH_CONFIG_DROPIN")"
target_watchdog_marker="$fixture/config-target-watchdog-started"
printf '%s\n' 'foreign fixed-name policy' >"$NOBRAND_SSH_CONFIG_DROPIN"
chmod 0600 "$NOBRAND_SSH_CONFIG_DROPIN"
write_ssh_config_target_state dropin "$NOBRAND_SSH_CONFIG_DROPIN" false
foreign_dropin_hash="$(sha256sum "$NOBRAND_SSH_CONFIG_DROPIN")"
foreign_state_hash="$(sha256sum "$NOBRAND_SSH_STATE_FILE")"
rm -f "$target_watchdog_marker"
(
  ssh_tunnel_dropin_supported() { return 0; }
  ssh_tunnel_watchdog_begin() { : >"$target_watchdog_marker"; return 70; }
  if ssh_tunnel_apply_policy nobody install >/dev/null 2>&1; then
    fail 'fresh SSH install overwrote a foreign fixed-name drop-in'
  fi
)
assert_eq "$foreign_dropin_hash" "$(sha256sum "$NOBRAND_SSH_CONFIG_DROPIN")" \
  'foreign fixed-name drop-in collision remains byte-identical'
assert_eq "$foreign_state_hash" "$(sha256sum "$NOBRAND_SSH_STATE_FILE")" \
  'foreign fixed-name drop-in rejection preserves SSH state'
[ ! -e "$target_watchdog_marker" ] \
  || fail 'foreign fixed-name drop-in rejection started a watchdog'

for dropin_link_kind in live dangling; do
  rm -f "$NOBRAND_SSH_CONFIG_DROPIN" "$target_watchdog_marker"
  dropin_link_target="$fixture/${dropin_link_kind}-dropin-target"
  if [ "$dropin_link_kind" = live ]; then
    printf '%s\n' preserve >"$dropin_link_target"
  else
    rm -f "$dropin_link_target"
  fi
  ln -s "$dropin_link_target" "$NOBRAND_SSH_CONFIG_DROPIN"
  write_ssh_config_target_state dropin "$NOBRAND_SSH_CONFIG_DROPIN" false
  (
    ssh_tunnel_dropin_supported() { return 0; }
    ssh_tunnel_watchdog_begin() { : >"$target_watchdog_marker"; return 70; }
    if ssh_tunnel_apply_policy nobody install >/dev/null 2>&1; then
      fail "SSH install accepted a ${dropin_link_kind} drop-in symlink collision"
    fi
  )
  [ -L "$NOBRAND_SSH_CONFIG_DROPIN" ] \
    || fail "${dropin_link_kind} drop-in collision was flattened"
  assert_eq "$dropin_link_target" "$(readlink "$NOBRAND_SSH_CONFIG_DROPIN")" \
    "${dropin_link_kind} drop-in collision preserves its link target"
  [ ! -e "$target_watchdog_marker" ] \
    || fail "${dropin_link_kind} drop-in collision started a watchdog"
  if [ "$dropin_link_kind" = live ]; then
    assert_eq preserve "$(cat "$dropin_link_target")" \
      'live drop-in collision preserves its external target'
  else
    [ ! -e "$dropin_link_target" ] \
      || fail 'dangling drop-in collision created or mutated its missing target'
  fi
done

owned_dropin_policy="$fixture/owned-dropin-policy"
ssh_tunnel_generate_policy "$owned_dropin_policy" /usr/sbin/nologin
rm -f "$NOBRAND_SSH_CONFIG_DROPIN"
install -m 0600 "$owned_dropin_policy" "$NOBRAND_SSH_CONFIG_DROPIN"
write_ssh_config_target_state dropin "$NOBRAND_SSH_CONFIG_DROPIN" true
ssh_tunnel_apply_target_preflight dropin "$NOBRAND_SSH_CONFIG_DROPIN" \
  "$owned_dropin_policy" restore \
  || fail 'restore rejected the exact secure drop-in proved by applied state'
ssh_tunnel_prepare_restored_policy_state \
  || fail 'restore could not prepare truthful pre-apply SSH state'
assert_eq false "$(ssh_tunnel_state_field policy_applied)" \
  'restore preparation marks the imported policy unapplied'
ssh_tunnel_apply_target_preflight dropin "$NOBRAND_SSH_CONFIG_DROPIN" \
  "$owned_dropin_policy" restore \
  || fail 'restore rejected an exact drop-in after truthful pre-apply state preparation'
if ssh_tunnel_apply_target_preflight dropin "$NOBRAND_SSH_CONFIG_DROPIN" \
     "$owned_dropin_policy" install; then
  fail 'fresh install accepted an existing drop-in despite exact managed content'
fi

# Removal must re-prove the current bytes before deleting a state-named
# drop-in. Replacing it after state creation must fail before watchdog startup.
write_ssh_config_target_state dropin "$NOBRAND_SSH_CONFIG_DROPIN" true
printf '%s\n' 'foreign replacement' >"$NOBRAND_SSH_CONFIG_DROPIN"
chmod 0600 "$NOBRAND_SSH_CONFIG_DROPIN"
replaced_dropin_hash="$(sha256sum "$NOBRAND_SSH_CONFIG_DROPIN")"
rm -f "$target_watchdog_marker"
(
  ssh_tunnel_watchdog_begin() { : >"$target_watchdog_marker"; return 70; }
  if ssh_tunnel_remove_policy uninstall >/dev/null 2>&1; then
    fail 'SSH uninstall deleted a replaced fixed-name drop-in'
  fi
)
assert_eq "$replaced_dropin_hash" "$(sha256sum "$NOBRAND_SSH_CONFIG_DROPIN")" \
  'replaced fixed-name drop-in remains byte-identical on removal refusal'
[ ! -e "$target_watchdog_marker" ] \
  || fail 'replaced fixed-name drop-in removal started a watchdog'

# Marker-block mutation is intentionally conservative: replacing the main
# config symlink itself is outside this transaction, so both apply and removal
# reject it without flattening the link or writing through to its referent.
marker_main_real="$fixture/sshd_config.real"
{
  printf '%s\n' 'Port 2222' "$NOBRAND_SSH_BLOCK_BEGIN"
  cat "$owned_dropin_policy"
  printf '%s\n' "$NOBRAND_SSH_BLOCK_END"
} >"$marker_main_real"
cp -a "$marker_main_real" "$NOBRAND_SSH_CONFIG_MAIN"
write_ssh_config_target_state marker-block "$NOBRAND_SSH_CONFIG_MAIN" true
ssh_tunnel_prepare_restored_policy_state \
  || fail 'marker-block restore could not prepare truthful pre-apply SSH state'
ssh_tunnel_apply_target_preflight marker-block "$NOBRAND_SSH_CONFIG_MAIN" \
  "$owned_dropin_policy" restore \
  || fail 'restore rejected the exact marker block proved by prepared state'
if ssh_tunnel_apply_target_preflight marker-block "$NOBRAND_SSH_CONFIG_MAIN" \
     "$owned_dropin_policy" install; then
  fail 'fresh install accepted an existing marker block despite exact managed content'
fi

# Removal also proves the exact managed block. Missing markers or foreign
# content between the markers must remain untouched and must not arm rollback.
for marker_collision_kind in missing replaced; do
  if [ "$marker_collision_kind" = missing ]; then
    printf '%s\n' 'Port 2222' >"$NOBRAND_SSH_CONFIG_MAIN"
  else
    printf '%s\n' 'Port 2222' "$NOBRAND_SSH_BLOCK_BEGIN" \
      'foreign marker policy' "$NOBRAND_SSH_BLOCK_END" \
      >"$NOBRAND_SSH_CONFIG_MAIN"
  fi
  write_ssh_config_target_state marker-block "$NOBRAND_SSH_CONFIG_MAIN" true
  marker_collision_hash="$(sha256sum "$NOBRAND_SSH_CONFIG_MAIN")"
  rm -f "$target_watchdog_marker"
  (
    ssh_tunnel_watchdog_begin() { : >"$target_watchdog_marker"; return 70; }
    if ssh_tunnel_remove_policy uninstall >/dev/null 2>&1; then
      fail "SSH removal accepted a ${marker_collision_kind} managed marker block"
    fi
  )
  assert_eq "$marker_collision_hash" "$(sha256sum "$NOBRAND_SSH_CONFIG_MAIN")" \
    "${marker_collision_kind} marker-block collision remains byte-identical"
  [ ! -e "$target_watchdog_marker" ] \
    || fail "${marker_collision_kind} marker-block collision started a watchdog"
done

rm -f "$NOBRAND_SSH_CONFIG_MAIN"
ln -s "$marker_main_real" "$NOBRAND_SSH_CONFIG_MAIN"
write_ssh_config_target_state marker-block "$NOBRAND_SSH_CONFIG_MAIN" true
marker_main_hash="$(sha256sum "$marker_main_real")"
marker_main_link="$(readlink "$NOBRAND_SSH_CONFIG_MAIN")"
rm -f "$target_watchdog_marker"
(
  ssh_tunnel_dropin_supported() { return 1; }
  ssh_tunnel_watchdog_begin() { : >"$target_watchdog_marker"; return 70; }
  if ssh_tunnel_apply_policy nobody install >/dev/null 2>&1; then
    fail 'SSH marker-block apply accepted a symlinked main config'
  fi
  if ssh_tunnel_remove_policy uninstall >/dev/null 2>&1; then
    fail 'SSH marker-block removal accepted a symlinked main config'
  fi
)
[ -L "$NOBRAND_SSH_CONFIG_MAIN" ] \
  || fail 'marker-block refusal flattened the main-config symlink'
assert_eq "$marker_main_link" "$(readlink "$NOBRAND_SSH_CONFIG_MAIN")" \
  'marker-block refusal preserves the main-config link target'
assert_eq "$marker_main_hash" "$(sha256sum "$marker_main_real")" \
  'marker-block refusal preserves the main-config referent'
[ ! -e "$target_watchdog_marker" ] \
  || fail 'symlinked main-config refusal started a watchdog'

# If state commit fails after sshd mutation and immediate rollback no longer
# owns the watchdog claim, return the recovery status and retain its evidence.
rm -f "$NOBRAND_SSH_CONFIG_MAIN"
printf '%s\n' 'Port 2222' >"$NOBRAND_SSH_CONFIG_MAIN"
write_ssh_config_target_state marker-block "$NOBRAND_SSH_CONFIG_MAIN" false
commit_failure_state_hash="$(sha256sum "$NOBRAND_SSH_STATE_FILE")"
commit_failure_token=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
commit_failure_base="${NOBRAND_SSH_WATCHDOG_DIR}/${commit_failure_token}"
commit_failure_rollback_attempt="$fixture/commit-failure-rollback-attempt"
printf '%s\n' snapshot >"${commit_failure_base}.backup"
cp -a "$NOBRAND_SSH_STATE_FILE" "${commit_failure_base}.state.backup"
printf '%s\n' '#!/usr/bin/env bash' >"${commit_failure_base}.rollback.sh"
chmod 0700 "${commit_failure_base}.rollback.sh"
: >"${commit_failure_base}.armed"
chmod 0600 "${commit_failure_base}.armed"
commit_failure_rc=0
(
  ssh_tunnel_dropin_supported() { return 1; }
  ssh_tunnel_watchdog_mutation_preflight() { return 0; }
  ssh_tunnel_watchdog_begin() {
    printf '%s|4242||%s' "$commit_failure_token" "$2"
  }
  ssh_tunnel_watchdog_claim_ready() { return 0; }
  ssh_tunnel_watchdog_rollback_now() {
    : >"$commit_failure_rollback_attempt"
    return 74
  }
  nb_atomic_install_file() {
    local source="$1" destination="$2" mode="${3:-0600}"
    [ "$destination" != "$NOBRAND_SSH_STATE_FILE" ] || return 73
    command install -m "$mode" "$source" "$destination"
  }
  if ssh_tunnel_apply_policy nobody install >/dev/null 2>&1; then
    fail 'SSH apply hid state-commit failure after losing immediate rollback ownership'
  else
    commit_failure_rc=$?
  fi
  assert_eq 75 "$commit_failure_rc" \
    'SSH apply propagates unresolved watchdog ownership as recovery status'
)
[ -e "$commit_failure_rollback_attempt" ] \
  || fail 'SSH apply did not attempt immediate rollback after state-commit failure'
[ -f "${commit_failure_base}.armed" ] \
  && [ -f "${commit_failure_base}.backup" ] \
  && [ -f "${commit_failure_base}.state.backup" ] \
  || fail 'SSH apply discarded watchdog evidence after losing rollback ownership'
assert_eq "$commit_failure_state_hash" "$(sha256sum "$NOBRAND_SSH_STATE_FILE")" \
  'failed SSH state commit preserves authoritative state'
rm -f "$commit_failure_rollback_attempt" "${commit_failure_base}.armed" \
  "${commit_failure_base}.backup" "${commit_failure_base}.state.backup" \
  "${commit_failure_base}.rollback.sh"

# Initial install must not interpret recovery status 75 as an ordinary apply
# failure and then erase the user/state that the watchdog may still need.
install_preserve_identity="$fixture/install-preserve-identity"
install_delete_marker="$fixture/install-delete-called"
install_rollback_marker="$fixture/install-rollback-called"
rm -f "$NOBRAND_SSH_STATE_FILE" "$install_preserve_identity" \
  "$install_delete_marker" "$install_rollback_marker"
printf '%s\n' 'Port 2222' >"$NOBRAND_SSH_CONFIG_MAIN"
(
  require_root() { return 0; }
  require_linux() { return 0; }
  nobrand_prepare_common() {
    mkdir -p "$NOBRAND_SSH_STATE_DIR" "$NOBRAND_SSH_KEYS_DIR" \
      "$NOBRAND_SSH_AUTHORIZED_KEYS_DIR" "$NOBRAND_SSH_ACCOUNT_MARKER_DIR"
  }
  # The sourced installer consumes this value after the stub returns.
  # shellcheck disable=SC2034
  nb_prepare_ingress_request() { INGRESS_PROFILE_ID=public-direct; }
  ssh_tunnel_sshd_binary() { printf '%s' "$fake_sshd"; }
  ssh_tunnel_detect_real_port() { printf '%s' 2222; }
  valid_advertise_host() { return 0; }
  valid_advertise_port() { return 0; }
  normalize_uint() { printf '%s' "$1"; }
  _has_group() { return 1; }
  ssh_tunnel_create_group() { return 0; }
  ssh_tunnel_dropin_supported() { return 1; }
  ssh_tunnel_add_user_internal() {
    local tmp account_id=a1111111111111111
    tmp="$(mktemp_file .ssh-install-user)" || return 1
    jq --arg account_id "$account_id" '
      .users=[{account_id:$account_id,linux_user:"nbt-preserved"}]
    ' "$NOBRAND_SSH_STATE_FILE" >"$tmp" \
      && nb_atomic_install_file "$tmp" "$NOBRAND_SSH_STATE_FILE" 0600 || {
        rm -f "$tmp"
        return 1
      }
    rm -f "$tmp"
    : >"$install_preserve_identity"
    printf '%s' "$account_id"
  }
  ssh_tunnel_apply_policy() { return 75; }
  ssh_tunnel_delete_user_internal() {
    : >"$install_delete_marker"
    rm -f "$install_preserve_identity"
  }
  ssh_tunnel_rollback_empty_install() {
    : >"$install_rollback_marker"
    rm -f "$install_preserve_identity" "$NOBRAND_SSH_STATE_FILE"
  }
  install_preserve_rc=0
  if SSH_TUNNEL_USER=preserved ADVERTISE_HOST=entry.example.test \
     ADVERTISE_PORT=443 ssh_tunnel_install >/dev/null 2>&1; then
    fail 'initial SSH install hid unresolved watchdog ownership'
  else
    install_preserve_rc=$?
  fi
  assert_eq 75 "$install_preserve_rc" \
    'initial SSH install propagates unresolved watchdog ownership'
)
[ -s "$NOBRAND_SSH_STATE_FILE" ] \
  || fail 'initial SSH install removed state needed by the watchdog'
[ -e "$install_preserve_identity" ] \
  || fail 'initial SSH install removed identity needed by the watchdog'
[ ! -e "$install_delete_marker" ] \
  || fail 'initial SSH install invoked account deletion for recovery status 75'
[ ! -e "$install_rollback_marker" ] \
  || fail 'initial SSH install invoked empty-install rollback for recovery status 75'

policy="$fixture/policy"
ssh_tunnel_generate_policy "$policy" /usr/sbin/nologin
{
  printf '%s\n' 'Port 2222'
  printf '%s\n' "$NOBRAND_SSH_BLOCK_BEGIN"
  cat "$policy"
  printf '%s\n' "$NOBRAND_SSH_BLOCK_END"
} >"$NOBRAND_SSH_CONFIG_MAIN"
users='[]'
ssh_tunnel_generate_state "$NOBRAND_SSH_STATE_FILE" custom entry.example.test 443 2222 marker-block \
  "$NOBRAND_SSH_CONFIG_MAIN" "$users" 2026-08-30T00:00:00Z
jq '.policy_applied=true' "$NOBRAND_SSH_STATE_FILE" >"$fixture/state.tmp"
mv -f "$fixture/state.tmp" "$NOBRAND_SSH_STATE_FILE"
chmod 0600 "$NOBRAND_SSH_STATE_FILE"
before_remove_config="$(sha256sum "$NOBRAND_SSH_CONFIG_MAIN")"
before_remove_state="$(sha256sum "$NOBRAND_SSH_STATE_FILE")"
remove_output="$(ssh_tunnel_remove_policy uninstall)"
assert_contains "$remove_output" 'nobrand ssh confirm-admin --token' \
  'SSH uninstall requires new-admin confirmation'
assert_eq uninstall "$(ssh_tunnel_state_field pending_operation)" \
  'SSH uninstall persists pending operation'
assert_eq false "$(ssh_tunnel_state_field policy_applied)" \
  'SSH uninstall marks policy removed while watchdog is armed'
assert_not_contains "$(cat "$NOBRAND_SSH_CONFIG_MAIN")" "$NOBRAND_SSH_BLOCK_BEGIN" \
  'SSH uninstall removes only managed marker block before confirmation'
token="$(ssh_tunnel_state_field pending_watchdog_token)"
pid="$(ssh_tunnel_state_field pending_watchdog_pid)"
ssh_tunnel_watchdog_rollback_now "$token" "$pid"
assert_eq "$before_remove_config" "$(sha256sum "$NOBRAND_SSH_CONFIG_MAIN")" \
  'unconfirmed SSH uninstall restores managed policy'
assert_eq "$before_remove_state" "$(sha256sum "$NOBRAND_SSH_STATE_FILE")" \
  'unconfirmed SSH uninstall restores exact module state'

ssh_tunnel_reload() { return 1; }
if ssh_tunnel_apply_policy nobody restore >/dev/null 2>&1; then
  fail 'SSH reload failure must fail the policy transaction'
fi
assert_eq "$before_remove_config" "$(sha256sum "$NOBRAND_SSH_CONFIG_MAIN")" \
  'SSH reload failure immediately restores config'
assert_eq "$before_remove_state" "$(sha256sum "$NOBRAND_SSH_STATE_FILE")" \
  'SSH reload failure immediately restores state'

# Confirmation and timeout must have a single atomic winner.  These cases use
# the on-disk claim names so a boundary race cannot be accidentally weakened to
# a check-then-delete sequence again.
write_pending_ssh_uninstall_state() {
  local operation="$1" token="$2" tmp origin='' pid=''
  if [ -n "$token" ]; then
    origin='192.0.2.10 41000 192.0.2.20 22'
    [ "$token" = disabled ] || pid=4242
  fi
  rm -rf -- "$NOBRAND_SSH_STATE_DIR" "$NOBRAND_SSH_CONFIG_DIR"
  mkdir -p "$NOBRAND_SSH_STATE_DIR" "$NOBRAND_SSH_CONFIG_DIR" "$NOBRAND_SSH_WATCHDOG_DIR"
  printf '%s\n' 'Port 2222' >"$NOBRAND_SSH_CONFIG_MAIN"
  tmp="$(mktemp_file .ssh-claim-state)"
  ssh_tunnel_generate_state "$tmp" custom entry.example.test 443 2222 marker-block \
    "$NOBRAND_SSH_CONFIG_MAIN" '[]' 2026-08-30T00:00:00Z
  jq --arg operation "$operation" --arg token "$token" --arg pid "$pid" --arg origin "$origin" '
      .policy_applied=false
      | .pending_operation=$operation
      | .pending_watchdog_token=$token
      | .pending_watchdog_pid=$pid
      | .pending_origin_connection=$origin
    ' "$tmp" >"$NOBRAND_SSH_STATE_FILE"
  rm -f "$tmp"
  chmod 0600 "$NOBRAND_SSH_STATE_FILE"
}

claim_token=0123456789abcdef0123456789abcdef
claim_base="${NOBRAND_SSH_WATCHDOG_DIR}/${claim_token}"

write_pending_ssh_uninstall_state uninstall "$claim_token"
: >"${claim_base}.armed"
claim_finalize_marker="$fixture/claim-confirm-finalized"
(
  require_root() { return 0; }
  ssh_tunnel_watchdog_claim_ready() { return 0; }
  ssh_tunnel_finalize_uninstall() { : >"$claim_finalize_marker"; }
  SSH_CONNECTION='198.51.100.10 42000 198.51.100.20 22' \
    ssh_tunnel_confirm_admin "$claim_token" >/dev/null
)
[ -e "$claim_finalize_marker" ] || fail 'confirmation-winning watchdog claim did not finalize'
assert_eq uninstall "$(ssh_tunnel_state_field pending_operation)" \
  'confirmed uninstall retains its durable finalization operation'
assert_eq '' "$(ssh_tunnel_state_field pending_watchdog_token)" \
  'confirmed uninstall clears its watchdog token only after winning the claim'
assert_eq false "$(ssh_tunnel_state_field policy_applied)" \
  'confirmed uninstall remains policy-removed until finalization'

write_pending_ssh_uninstall_state uninstall "$claim_token"
rm -f "$claim_finalize_marker" "${claim_base}.armed" "${claim_base}.rollback.sh.confirmed"
: >"${claim_base}.rollback.sh.running"
claim_state_hash="$(sha256sum "$NOBRAND_SSH_STATE_FILE")"
if (
  require_root() { return 0; }
  ssh_tunnel_finalize_uninstall() { : >"$claim_finalize_marker"; }
  SSH_CONNECTION='198.51.100.10 42000 198.51.100.20 22' \
    ssh_tunnel_confirm_admin "$claim_token" >/dev/null 2>&1
); then
  fail 'confirmation proceeded after the rollback watchdog won the atomic claim'
fi
assert_eq "$claim_state_hash" "$(sha256sum "$NOBRAND_SSH_STATE_FILE")" \
  'rollback-winning claim leaves pending SSH state untouched'
[ ! -e "$claim_finalize_marker" ] || fail 'rollback-winning claim reached SSH finalization'

write_pending_ssh_uninstall_state uninstall "$claim_token"
rm -f "$claim_finalize_marker" "${claim_base}.armed" "${claim_base}.rollback.sh.running"
: >"${claim_base}.rollback.sh.confirmed"
(
  require_root() { return 0; }
  ssh_tunnel_finalize_uninstall() { : >"$claim_finalize_marker"; }
  SSH_CONNECTION='198.51.100.10 42000 198.51.100.20 22' \
    ssh_tunnel_confirm_admin "$claim_token" >/dev/null
)
[ -e "$claim_finalize_marker" ] || fail 'pre-existing confirmed claim was not resumed'
assert_eq uninstall "$(ssh_tunnel_state_field pending_operation)" \
  'confirmed-claim retry preserves the uninstall finalization marker'
assert_eq '' "$(ssh_tunnel_state_field pending_watchdog_token)" \
  'confirmed-claim retry durably clears the watchdog token'

for claim_conflict in armed running; do
  write_pending_ssh_uninstall_state uninstall "$claim_token"
  rm -f "$claim_finalize_marker" "${claim_base}.armed" \
    "${claim_base}.rollback.sh.running" "${claim_base}.rollback.sh.confirmed"
  : >"${claim_base}.rollback.sh.confirmed"
  case "$claim_conflict" in
    armed) : >"${claim_base}.armed" ;;
    running) : >"${claim_base}.rollback.sh.running" ;;
  esac
  claim_state_hash="$(sha256sum "$NOBRAND_SSH_STATE_FILE")"
  if (
    require_root() { return 0; }
    ssh_tunnel_finalize_uninstall() { : >"$claim_finalize_marker"; }
    SSH_CONNECTION='198.51.100.10 42000 198.51.100.20 22' \
      ssh_tunnel_confirm_admin "$claim_token" >/dev/null 2>&1
  ); then
    fail "conflicting confirmed/${claim_conflict} watchdog claims were accepted"
  fi
  assert_eq "$claim_state_hash" "$(sha256sum "$NOBRAND_SSH_STATE_FILE")" \
    "conflicting confirmed/${claim_conflict} claims leave SSH state untouched"
  [ ! -e "$claim_finalize_marker" ] \
    || fail "conflicting confirmed/${claim_conflict} claims reached SSH finalization"
done

# A failed post-confirm finalization must retry the finalizer, never attempt to
# remove the already-absent sshd policy.  Cover both standalone and unified
# operations because the latter owns continuation of the global uninstall.
exercise_confirmed_finalize_retry() {
  local operation="$1" attempts remove_marker
  attempts="$fixture/finalize-${operation}.attempts"
  remove_marker="$fixture/finalize-${operation}.removed-policy"
  write_pending_ssh_uninstall_state "$operation" ''
  : >"$attempts"
  (
    require_root() { return 0; }
    ssh_tunnel_group_identity_valid() { return 0; }
    ssh_tunnel_user_identity_valid() { return 0; }
    ssh_tunnel_remove_policy() { : >"$remove_marker"; return 0; }
    ssh_tunnel_finalize_uninstall() {
      printf 'attempt\n' >>"$attempts"
      [ "$(wc -l <"$attempts" | tr -d '[:space:]')" -gt 1 ] || return 73
      rm -rf -- "$NOBRAND_SSH_STATE_DIR" "$NOBRAND_SSH_CONFIG_DIR"
    }
    if ssh_tunnel_uninstall "$operation" >/dev/null 2>&1; then
      fail "first confirmed ${operation} finalization failure was hidden"
    fi
    ssh_tunnel_uninstall "$operation" >/dev/null
  )
  assert_eq 2 "$(wc -l <"$attempts" | tr -d '[:space:]')" \
    "confirmed ${operation} retry re-enters finalization"
  [ ! -e "$remove_marker" ] \
    || fail "confirmed ${operation} retry attempted policy removal again"
  [ ! -e "$NOBRAND_SSH_STATE_FILE" ] \
    || fail "confirmed ${operation} retry did not converge"
}
exercise_confirmed_finalize_retry uninstall
exercise_confirmed_finalize_retry unified-uninstall

# Restore must be able to rebuild only the missing SSH config payload from
# authoritative state. Model Linux identities outside the managed roots and
# fail the first authorized_keys commit after group/user creation. A retry must
# reconcile the surviving identities and files rather than getting stuck on
# the partially recreated account.
SSH_RESTORE_CASE_DIR=''
SSH_RESTORE_FAKE_GROUP_FILE=''
SSH_RESTORE_FAKE_USERS_DIR=''
SSH_RESTORE_MUTATION_LOG=''
SSH_RESTORE_TRANSACTION_LOG=''
SSH_RESTORE_APPLY_LOG=''
SSH_RESTORE_AUTH_FAILURE_MARKER=''
SSH_RESTORE_FAIL_AUTH_ONCE=0
SSH_RESTORE_GROUPADD_RC=0
SSH_RESTORE_GROUPADD_ACTUAL_GID=49000
SSH_RESTORE_USERADD_RC=0
SSH_RESTORE_USERADD_ACTUAL_ACCOUNT_ID=a3333333333333333
SSH_RESTORE_ROLLBACK_SNAPSHOT=''
SSH_RESTORE_USER_JSON=''
SSH_RESTORE_FINGERPRINT=''

prepare_ssh_restore_fixture() {
  local name="$1" root_kind="${2:-absent}" key_dir private_key users tmp foreign_root
  SSH_RESTORE_CASE_DIR="$fixture/restore-cases/$name"
  SSH_RESTORE_FAKE_GROUP_FILE="$SSH_RESTORE_CASE_DIR/group"
  SSH_RESTORE_FAKE_USERS_DIR="$SSH_RESTORE_CASE_DIR/users"
  SSH_RESTORE_MUTATION_LOG="$SSH_RESTORE_CASE_DIR/mutations.log"
  SSH_RESTORE_TRANSACTION_LOG="$SSH_RESTORE_CASE_DIR/created.log"
  SSH_RESTORE_APPLY_LOG="$SSH_RESTORE_CASE_DIR/apply.log"
  SSH_RESTORE_AUTH_FAILURE_MARKER="$SSH_RESTORE_CASE_DIR/auth-failure-fired"
  SSH_RESTORE_FAIL_AUTH_ONCE=0
  SSH_RESTORE_GROUPADD_RC=0
  SSH_RESTORE_GROUPADD_ACTUAL_GID=49000
  SSH_RESTORE_USERADD_RC=0
  SSH_RESTORE_USERADD_ACTUAL_ACCOUNT_ID=a3333333333333333
  SSH_RESTORE_ROLLBACK_SNAPSHOT=''
  rm -rf -- "$NOBRAND_SSH_STATE_DIR" "$NOBRAND_SSH_CONFIG_DIR" "$SSH_RESTORE_CASE_DIR"
  mkdir -p "$NOBRAND_SSH_STATE_DIR" "$SSH_RESTORE_FAKE_USERS_DIR" \
    "$(dirname "$NOBRAND_SSH_CONFIG_DIR")"
  chmod 0700 "$NOBRAND_STATE_DIR" "$NOBRAND_SSH_STATE_DIR"
  chmod 0711 "$NOBRAND_CONFIG_DIR"
  : >"$SSH_RESTORE_MUTATION_LOG"
  : >"$SSH_RESTORE_TRANSACTION_LOG"
  key_dir="$NOBRAND_SSH_KEYS_DIR/a3333333333333333"
  private_key="$key_dir/id_ed25519"
  mkdir -p "$key_dir"
  chmod 0700 "$NOBRAND_SSH_KEYS_DIR" "$key_dir"
  ssh-keygen -q -t ed25519 -N '' -C nobrand:a3333333333333333 -f "$private_key"
  chmod 0600 "$private_key"
  SSH_RESTORE_FINGERPRINT="$(ssh_tunnel_key_fingerprint "${private_key}.pub")"
  SSH_RESTORE_USER_JSON="$(ssh_tunnel_user_json a3333333333333333 restore \
    nbt-restore 49003 "$SSH_RESTORE_FINGERPRINT" 2026-08-30T00:00:00Z)"
  users="$(jq -cn --argjson user "$SSH_RESTORE_USER_JSON" '[$user]')"
  tmp="$(mktemp_file .ssh-restore-state)"
  ssh_tunnel_generate_state "$tmp" custom entry.example.test 443 2222 marker-block \
    "$NOBRAND_SSH_CONFIG_MAIN" "$users" 2026-08-30T00:00:00Z
  jq '
    .policy_applied=false
    | .pending_operation="unified-uninstall"
    | .pending_watchdog_token=""
    | .pending_watchdog_pid=""
    | .pending_origin_connection=""
  ' "$tmp" >"$NOBRAND_SSH_STATE_FILE"
  rm -f "$tmp"
  chmod 0600 "$NOBRAND_SSH_STATE_FILE"
  case "$root_kind" in
    absent) ;;
    symlink)
      foreign_root="$SSH_RESTORE_CASE_DIR/foreign-config"
      mkdir -p "$foreign_root"
      printf '%s\n' preserve >"$foreign_root/sentinel"
      ln -s "$foreign_root" "$NOBRAND_SSH_CONFIG_DIR"
      ;;
    file) printf '%s\n' preserve >"$NOBRAND_SSH_CONFIG_DIR" ;;
    *) fail "unknown SSH restore root fixture: $root_kind" ;;
  esac
}

seed_ssh_restore_group_marker() {
  ssh_tunnel_ensure_restore_directories || return 1
  jq -n --arg group "$NOBRAND_SSH_GROUP" --argjson gid 49000 '
    {schema_version:3,ownership:"nobrand-v3",group:$group,gid:$gid}
  ' >"$NOBRAND_SSH_GROUP_MARKER" || return 1
  chmod 0600 "$NOBRAND_SSH_GROUP_MARKER"
}

run_ssh_restore_with_fake_identities() (
  local restore_rc=0 rollback_rc=0
  trap - EXIT
  _has_group() {
    [ "$1" = "$NOBRAND_SSH_GROUP" ] && [ -f "$SSH_RESTORE_FAKE_GROUP_FILE" ]
  }
  _has_user() { [ -f "$SSH_RESTORE_FAKE_USERS_DIR/$1" ]; }
  groupadd() {
    local name="" requested_gid=""
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --system) shift ;;
        --gid)
          [ "$#" -ge 2 ] || return 64
          requested_gid="$2"
          shift 2
          ;;
        *)
          [ -z "$name" ] || return 64
          name="$1"
          shift
          ;;
      esac
    done
    [ "$name" = "$NOBRAND_SSH_GROUP" ] \
      && { [ -z "$requested_gid" ] || [ "$requested_gid" = 49000 ]; } || return 64
    [ "${NOBRAND_LIFECYCLE_LOCK_HELD:-0}" -gt 0 ] || return 76
    printf '%s\n' "$SSH_RESTORE_GROUPADD_ACTUAL_GID" >"$SSH_RESTORE_FAKE_GROUP_FILE"
    printf 'groupadd\n' >>"$SSH_RESTORE_MUTATION_LOG"
    return "$SSH_RESTORE_GROUPADD_RC"
  }
  groupdel() {
    local remaining_user
    remaining_user="$(find "$SSH_RESTORE_FAKE_USERS_DIR" -mindepth 1 -maxdepth 1 \
      -type f -print -quit)" || return 1
    if [ -n "$remaining_user" ]; then
      printf 'groupdel-refused\n' >>"$SSH_RESTORE_MUTATION_LOG"
      return 8
    fi
    rm -f "$SSH_RESTORE_FAKE_GROUP_FILE"
    printf 'groupdel\n' >>"$SSH_RESTORE_MUTATION_LOG"
  }
  delgroup() { groupdel "$@"; }
  getent() {
    local database="${1:-}" key="${2:-}" path name uid account_id gid
    case "$database" in
      group)
        gid="$(cat "$SSH_RESTORE_FAKE_GROUP_FILE" 2>/dev/null || true)"
        if [ -f "$SSH_RESTORE_FAKE_GROUP_FILE" ] \
           && { [ "$key" = "$NOBRAND_SSH_GROUP" ] || [ "$key" = "$gid" ]; }; then
          printf '%s:x:%s:\n' "$NOBRAND_SSH_GROUP" "$gid"
          return 0
        fi
        return 2
        ;;
      passwd)
        if [ -f "$SSH_RESTORE_FAKE_USERS_DIR/$key" ]; then
          path="$SSH_RESTORE_FAKE_USERS_DIR/$key"
          name="$key"
        else
          path=''
          for path in "$SSH_RESTORE_FAKE_USERS_DIR"/*; do
            [ -f "$path" ] || continue
            IFS='|' read -r uid account_id <"$path"
            [ "$uid" = "$key" ] || continue
            name="$(basename "$path")"
            break
          done
          [ -n "$path" ] && [ -f "$path" ] || return 2
        fi
        IFS='|' read -r uid account_id <"$path"
        printf '%s:x:%s:49000:NoBrand SSH Tunnel %s:/nonexistent:/usr/sbin/nologin\n' \
          "$name" "$uid" "$account_id"
        ;;
      *) return 2 ;;
    esac
  }
  id() {
    if [ "${1:-}" = -u ] && [ -f "$SSH_RESTORE_FAKE_USERS_DIR/${2:-}" ]; then
      cut -d'|' -f1 "$SSH_RESTORE_FAKE_USERS_DIR/${2:-}"
    else
      command id "$@"
    fi
  }
  ssh_tunnel_nologin_shell() { printf '%s' /usr/sbin/nologin; }
  useradd() {
    local linux_user="" expected_uid="" requested_group="" home="" shell="" comment=""
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --system|--no-create-home) shift ;;
        --uid)
          [ "$#" -ge 2 ] || return 64
          expected_uid="$2"
          shift 2
          ;;
        --gid)
          [ "$#" -ge 2 ] || return 64
          requested_group="$2"
          shift 2
          ;;
        --home-dir)
          [ "$#" -ge 2 ] || return 64
          home="$2"
          shift 2
          ;;
        --shell)
          [ "$#" -ge 2 ] || return 64
          shell="$2"
          shift 2
          ;;
        --comment)
          [ "$#" -ge 2 ] || return 64
          comment="$2"
          shift 2
          ;;
        *)
          [ -z "$linux_user" ] || return 64
          linux_user="$1"
          shift
          ;;
      esac
    done
    [ "$linux_user" = nbt-restore ] \
      && [ "$expected_uid" = 49003 ] \
      && [ "$requested_group" = "$NOBRAND_SSH_GROUP" ] \
      && [ "$home" = /nonexistent ] \
      && [ "$shell" = /usr/sbin/nologin ] \
      && [ "$comment" = 'NoBrand SSH Tunnel a3333333333333333' ] \
      && [ "${NOBRAND_LIFECYCLE_LOCK_HELD:-0}" -gt 0 ] || return 76
    printf '%s|%s\n' "$expected_uid" "$SSH_RESTORE_USERADD_ACTUAL_ACCOUNT_ID" \
      >"$SSH_RESTORE_FAKE_USERS_DIR/$linux_user"
    printf 'useradd:%s\n' "$linux_user" >>"$SSH_RESTORE_MUTATION_LOG"
    return "$SSH_RESTORE_USERADD_RC"
  }
  passwd() { return 0; }
  pkill() { return 0; }
  ssh_tunnel_reload() { return 0; }
  ssh_tunnel_delete_linux_user() {
    rm -f "$SSH_RESTORE_FAKE_USERS_DIR/$1"
    printf 'userdel:%s\n' "$1" >>"$SSH_RESTORE_MUTATION_LOG"
  }
  nb_atomic_install_file() {
    local source="$1" destination="$2" mode="${3:-0600}"
    if [ "$SSH_RESTORE_FAIL_AUTH_ONCE" -eq 1 ] \
       && [ "$destination" = "$(ssh_tunnel_authorized_key_file nbt-restore)" ] \
       && [ ! -e "$SSH_RESTORE_AUTH_FAILURE_MARKER" ]; then
      : >"$SSH_RESTORE_AUTH_FAILURE_MARKER"
      return 74
    fi
    [ -f "$source" ] && [ -d "$(dirname "$destination")" ] \
      && install -m "$mode" "$source" "$destination"
  }
  ssh_tunnel_apply_policy() {
    local validation_user="$1" operation="$2" user_json
    [ "$validation_user" = nbt-restore ] && [ "$operation" = restore ] || return 1
    user_json="$(jq -c '.users[0]' "$NOBRAND_SSH_STATE_FILE")"
    ssh_tunnel_user_identity_valid "$user_json" || return 1
    printf '%s|%s\n' "$validation_user" "$operation" >"$SSH_RESTORE_APPLY_LOG"
  }
  nb_lifecycle_lock_acquire || return 1
  ssh_tunnel_restore_system_state "$SSH_RESTORE_TRANSACTION_LOG" || restore_rc=$?
  if [ "$restore_rc" -ne 0 ] && [ -n "$SSH_RESTORE_ROLLBACK_SNAPSHOT" ]; then
    ssh_tunnel_restore_external_snapshot "$SSH_RESTORE_ROLLBACK_SNAPSHOT" \
      "$SSH_RESTORE_TRANSACTION_LOG" || rollback_rc=$?
  fi
  nb_lifecycle_lock_release || return 1
  [ "$rollback_rc" -eq 0 ] || return "$rollback_rc"
  return "$restore_rc"
)

prepare_ssh_restore_fixture absent-root
SSH_RESTORE_FAIL_AUTH_ONCE=1
if run_ssh_restore_with_fake_identities >/dev/null 2>&1; then
  fail 'forced SSH authorized_keys restore failure unexpectedly completed'
fi
[ -d "$NOBRAND_SSH_CONFIG_DIR" ] && [ ! -L "$NOBRAND_SSH_CONFIG_DIR" ] \
  || fail 'SSH restore did not safely recreate its absent config root'
[ -d "$NOBRAND_SSH_ACCOUNT_MARKER_DIR" ] && [ ! -L "$NOBRAND_SSH_ACCOUNT_MARKER_DIR" ] \
  || fail 'SSH restore did not safely recreate its account marker directory'
[ -d "$NOBRAND_SSH_AUTHORIZED_KEYS_DIR" ] && [ ! -L "$NOBRAND_SSH_AUTHORIZED_KEYS_DIR" ] \
  || fail 'SSH restore did not safely recreate its authorized_keys directory'
assert_file_mode 711 "$NOBRAND_SSH_CONFIG_DIR"
assert_file_mode 700 "$NOBRAND_SSH_ACCOUNT_MARKER_DIR"
assert_file_mode 755 "$NOBRAND_SSH_AUTHORIZED_KEYS_DIR"
[ -s "$NOBRAND_SSH_GROUP_MARKER" ] \
  || fail 'interrupted SSH restore did not retain its recreated group marker'
[ -s "$(ssh_tunnel_account_marker_file nbt-restore)" ] \
  || fail 'interrupted SSH restore did not retain its recreated account marker'
[ ! -e "$(ssh_tunnel_authorized_key_file nbt-restore)" ] \
  || fail 'forced SSH authorized_keys failure unexpectedly committed the key'
[ ! -e "$SSH_RESTORE_APPLY_LOG" ] \
  || fail 'failed SSH restore applied policy before identity files converged'
assert_eq 1 "$(grep -c '^groupadd$' "$SSH_RESTORE_MUTATION_LOG")" \
  'interrupted SSH restore creates its group once'
assert_eq 1 "$(grep -c '^useradd:nbt-restore$' "$SSH_RESTORE_MUTATION_LOG")" \
  'interrupted SSH restore creates its user once'
assert_eq 1 "$(grep -c '^GROUP|' "$SSH_RESTORE_TRANSACTION_LOG")" \
  'interrupted SSH restore logs its created group once'
assert_eq 1 "$(grep -c '^USER|' "$SSH_RESTORE_TRANSACTION_LOG")" \
  'interrupted SSH restore logs its created user once'

run_ssh_restore_with_fake_identities >/dev/null
assert_eq 'nbt-restore|restore' "$(cat "$SSH_RESTORE_APPLY_LOG")" \
  'SSH restore retry converges before applying the policy'
assert_eq "$SSH_RESTORE_FINGERPRINT" \
  "$(ssh-keygen -lf "$(ssh_tunnel_authorized_key_file nbt-restore)" -E sha256 | awk '{print $2}')" \
  'SSH restore retry recreates the expected authorized key'
jq -e '
  .ownership=="nobrand-v3"
  and .account_id=="a3333333333333333"
  and .linux_user=="nbt-restore"
  and .uid==49003
' "$(ssh_tunnel_account_marker_file nbt-restore)" >/dev/null \
  || fail 'SSH restore retry did not recreate the exact account marker'
assert_eq 1 "$(grep -c '^groupadd$' "$SSH_RESTORE_MUTATION_LOG")" \
  'SSH restore retry does not recreate the surviving group'
assert_eq 1 "$(grep -c '^useradd:nbt-restore$' "$SSH_RESTORE_MUTATION_LOG")" \
  'SSH restore retry does not recreate the surviving user'

# A group command may create the requested identity and still report failure.
# The helper must expose that postcondition, restore must journal it before
# returning the original status, and the outer rollback must remove only the
# exact journaled identity.
prepare_ssh_restore_fixture partial-groupadd-exact
seed_ssh_restore_group_marker
SSH_RESTORE_GROUPADD_RC=73
SSH_RESTORE_ROLLBACK_SNAPSHOT="$SSH_RESTORE_CASE_DIR/external-snapshot"
ssh_tunnel_snapshot_external_state "$SSH_RESTORE_ROLLBACK_SNAPSHOT"
set +e
run_ssh_restore_with_fake_identities >/dev/null 2>&1
partial_group_rc=$?
set -e
assert_eq 73 "$partial_group_rc" 'partial groupadd preserves its failure status'
assert_eq "GROUP|${NOBRAND_SSH_GROUP}|49000|" \
  "$(cat "$SSH_RESTORE_TRANSACTION_LOG")" \
  'partial groupadd journals the exact transaction-created identity'
[ ! -e "$SSH_RESTORE_FAKE_GROUP_FILE" ] \
  || fail 'partial groupadd rollback left the transaction-created group'
[ ! -e "$SSH_RESTORE_FAKE_USERS_DIR/nbt-restore" ] \
  || fail 'partial groupadd failure unexpectedly created a user'
assert_eq 1 "$(grep -c '^groupdel$' "$SSH_RESTORE_MUTATION_LOG")" \
  'partial groupadd rollback removes its journaled group once'

# A failed group command that leaves a different GID is not attributable to
# this transaction. It must remain unjournaled and survive rollback.
prepare_ssh_restore_fixture partial-groupadd-mismatch
seed_ssh_restore_group_marker
SSH_RESTORE_GROUPADD_RC=73
SSH_RESTORE_GROUPADD_ACTUAL_GID=49009
SSH_RESTORE_ROLLBACK_SNAPSHOT="$SSH_RESTORE_CASE_DIR/external-snapshot"
ssh_tunnel_snapshot_external_state "$SSH_RESTORE_ROLLBACK_SNAPSHOT"
set +e
run_ssh_restore_with_fake_identities >/dev/null 2>&1
mismatched_group_rc=$?
set -e
assert_eq 73 "$mismatched_group_rc" 'mismatched groupadd preserves its failure status'
[ ! -s "$SSH_RESTORE_TRANSACTION_LOG" ] \
  || fail 'mismatched groupadd identity was journaled as transaction-created'
assert_eq 49009 "$(cat "$SSH_RESTORE_FAKE_GROUP_FILE")" \
  'mismatched groupadd identity survives rollback'
assert_not_contains "$(cat "$SSH_RESTORE_MUTATION_LOG")" groupdel \
  'mismatched groupadd identity is never selected for deletion'

# Apply the same contract to useradd. An exact postcondition is journaled and
# rolled back even though useradd failed; a different GECOS/account tuple is
# unproven and must not be deleted.
prepare_ssh_restore_fixture partial-useradd-exact
SSH_RESTORE_USERADD_RC=74
SSH_RESTORE_ROLLBACK_SNAPSHOT="$SSH_RESTORE_CASE_DIR/external-snapshot"
ssh_tunnel_snapshot_external_state "$SSH_RESTORE_ROLLBACK_SNAPSHOT"
set +e
run_ssh_restore_with_fake_identities >/dev/null 2>&1
partial_user_rc=$?
set -e
assert_eq 74 "$partial_user_rc" 'partial useradd preserves its failure status'
assert_eq 1 "$(grep -c '^GROUP|' "$SSH_RESTORE_TRANSACTION_LOG")" \
  'partial useradd restore journals its prerequisite group'
assert_eq 1 "$(grep -c '^USER|nbt-restore|49003|a3333333333333333$' \
  "$SSH_RESTORE_TRANSACTION_LOG")" \
  'partial useradd journals the exact transaction-created identity'
[ ! -e "$SSH_RESTORE_FAKE_USERS_DIR/nbt-restore" ] \
  || fail 'partial useradd rollback left the transaction-created user'
[ ! -e "$SSH_RESTORE_FAKE_GROUP_FILE" ] \
  || fail 'partial useradd rollback left the transaction-created group'
assert_eq 1 "$(grep -c '^userdel:nbt-restore$' "$SSH_RESTORE_MUTATION_LOG")" \
  'partial useradd rollback removes its journaled user once'

prepare_ssh_restore_fixture partial-useradd-mismatch
SSH_RESTORE_USERADD_RC=74
SSH_RESTORE_USERADD_ACTUAL_ACCOUNT_ID=foreign-account
SSH_RESTORE_ROLLBACK_SNAPSHOT="$SSH_RESTORE_CASE_DIR/external-snapshot"
ssh_tunnel_snapshot_external_state "$SSH_RESTORE_ROLLBACK_SNAPSHOT"
if run_ssh_restore_with_fake_identities >/dev/null 2>&1; then
  fail 'mismatched partial useradd unexpectedly completed restoration'
fi
assert_eq 1 "$(grep -c '^GROUP|' "$SSH_RESTORE_TRANSACTION_LOG")" \
  'mismatched partial useradd still journals its transaction-created group'
if grep -q '^USER|' "$SSH_RESTORE_TRANSACTION_LOG"; then
  fail 'mismatched partial useradd identity was journaled as transaction-created'
fi
assert_eq '49003|foreign-account' \
  "$(cat "$SSH_RESTORE_FAKE_USERS_DIR/nbt-restore")" \
  'mismatched partial useradd identity survives rollback'
[ -e "$SSH_RESTORE_FAKE_GROUP_FILE" ] \
  || fail 'rollback removed a group still referenced by an unproven user'
assert_not_contains "$(cat "$SSH_RESTORE_MUTATION_LOG")" 'userdel:nbt-restore' \
  'mismatched partial useradd identity is never selected for deletion'
assert_contains "$(cat "$SSH_RESTORE_MUTATION_LOG")" groupdel-refused \
  'rollback refuses to remove a group still referenced by an unproven user'

# A state-listed OS user with the exact UID/account/group tuple is positive
# proof for a surviving group whose config-root marker was removed. Recreate
# only the missing managed files; do not recreate either external identity.
prepare_ssh_restore_fixture surviving-identities
SSH_RESTORE_FAIL_AUTH_ONCE=0
printf '%s\n' 49000 >"$SSH_RESTORE_FAKE_GROUP_FILE"
printf '%s|%s\n' 49003 a3333333333333333 \
  >"$SSH_RESTORE_FAKE_USERS_DIR/nbt-restore"
run_ssh_restore_with_fake_identities >/dev/null
[ ! -s "$SSH_RESTORE_MUTATION_LOG" ] \
  || fail 'SSH restore recreated a positively identified surviving identity'
[ ! -s "$SSH_RESTORE_TRANSACTION_LOG" ] \
  || fail 'SSH restore logged a surviving identity as newly created'
[ -s "$NOBRAND_SSH_GROUP_MARKER" ] \
  || fail 'SSH restore did not recreate the proven surviving group marker'
[ -s "$(ssh_tunnel_account_marker_file nbt-restore)" ] \
  || fail 'SSH restore did not recreate the surviving user marker'
assert_eq "$SSH_RESTORE_FINGERPRINT" \
  "$(ssh-keygen -lf "$(ssh_tunnel_authorized_key_file nbt-restore)" -E sha256 | awk '{print $2}')" \
  'SSH restore recreates authorized_keys for a proven surviving user'
assert_eq 'nbt-restore|restore' "$(cat "$SSH_RESTORE_APPLY_LOG")" \
  'SSH restore accepts an exact surviving identity before policy apply'

# A group name alone is not ownership proof when its marker disappeared. If
# no exact state-listed OS user binds that group, restoration must stop before
# creating identities or ownership files.
prepare_ssh_restore_fixture unproven-surviving-group
SSH_RESTORE_FAIL_AUTH_ONCE=0
printf '%s\n' 49000 >"$SSH_RESTORE_FAKE_GROUP_FILE"
ssh_restore_state_hash="$(sha256sum "$NOBRAND_SSH_STATE_FILE")"
if run_ssh_restore_with_fake_identities >/dev/null 2>&1; then
  fail 'SSH restore trusted an unmarked group without a surviving managed user'
fi
[ ! -s "$SSH_RESTORE_MUTATION_LOG" ] \
  || fail 'SSH restore mutated an unproven surviving group or user'
[ ! -s "$SSH_RESTORE_TRANSACTION_LOG" ] \
  || fail 'SSH restore logged a mutation for an unproven surviving group'
[ ! -e "$SSH_RESTORE_APPLY_LOG" ] \
  || fail 'SSH restore applied policy for an unproven surviving group'
[ ! -e "$NOBRAND_SSH_GROUP_MARKER" ] \
  || fail 'SSH restore fabricated ownership for an unproven surviving group'
assert_eq "$ssh_restore_state_hash" "$(sha256sum "$NOBRAND_SSH_STATE_FILE")" \
  'SSH restore preserves state when surviving group ownership is unproven'

# A different local account occupying the state-listed UID is an identity
# collision, not a missing user. Reject it before group or config-file changes.
prepare_ssh_restore_fixture foreign-uid
SSH_RESTORE_FAIL_AUTH_ONCE=0
printf '%s|%s\n' 49003 foreign-account \
  >"$SSH_RESTORE_FAKE_USERS_DIR/foreign-owner"
ssh_restore_state_hash="$(sha256sum "$NOBRAND_SSH_STATE_FILE")"
if run_ssh_restore_with_fake_identities >/dev/null 2>&1; then
  fail 'SSH restore accepted a foreign account occupying the managed UID'
fi
[ ! -s "$SSH_RESTORE_MUTATION_LOG" ] \
  || fail 'SSH restore mutated identities after detecting a foreign UID owner'
[ ! -s "$SSH_RESTORE_TRANSACTION_LOG" ] \
  || fail 'SSH restore logged identity creation after a foreign UID collision'
[ ! -e "$SSH_RESTORE_APPLY_LOG" ] \
  || fail 'SSH restore applied policy after a foreign UID collision'
[ -z "$(find "$NOBRAND_SSH_CONFIG_DIR" -type f -print -quit 2>/dev/null || true)" ] \
  || fail 'SSH restore wrote ownership files after a foreign UID collision'
assert_eq "$ssh_restore_state_hash" "$(sha256sum "$NOBRAND_SSH_STATE_FILE")" \
  'SSH restore preserves state after a foreign UID collision'

for ssh_restore_bad_root in symlink file; do
  prepare_ssh_restore_fixture "bad-${ssh_restore_bad_root}" "$ssh_restore_bad_root"
  SSH_RESTORE_FAIL_AUTH_ONCE=0
  ssh_restore_state_hash="$(sha256sum "$NOBRAND_SSH_STATE_FILE")"
  if run_ssh_restore_with_fake_identities >/dev/null 2>&1; then
    fail "SSH restore accepted a ${ssh_restore_bad_root} config root"
  fi
  [ ! -s "$SSH_RESTORE_MUTATION_LOG" ] \
    || fail "SSH restore mutated identities for a ${ssh_restore_bad_root} config root"
  [ ! -e "$SSH_RESTORE_APPLY_LOG" ] \
    || fail "SSH restore applied policy for a ${ssh_restore_bad_root} config root"
  assert_eq "$ssh_restore_state_hash" "$(sha256sum "$NOBRAND_SSH_STATE_FILE")" \
    "SSH restore preserves state for a ${ssh_restore_bad_root} config root"
  if [ "$ssh_restore_bad_root" = symlink ]; then
    assert_eq preserve "$(cat "$SSH_RESTORE_CASE_DIR/foreign-config/sentinel")" \
      'SSH restore preserves the symlink target sentinel'
    [ -z "$(find "$SSH_RESTORE_CASE_DIR/foreign-config" -mindepth 1 -maxdepth 1 \
      ! -name sentinel -print -quit)" ] \
      || fail 'SSH restore wrote through its symlink config root'
  else
    assert_eq preserve "$(cat "$NOBRAND_SSH_CONFIG_DIR")" \
      'SSH restore preserves the non-directory config root'
  fi
done

# The watchdog directory is part of authoritative SSH state, even though it is
# created only when policy application begins. Reject a replacement object in
# that slot during restore preflight, before creating a group, user, marker,
# authorized key, or policy transaction.
for ssh_restore_bad_watchdog in symlink file; do
  prepare_ssh_restore_fixture "bad-watchdog-${ssh_restore_bad_watchdog}"
  SSH_RESTORE_FAIL_AUTH_ONCE=0
  if [ "$ssh_restore_bad_watchdog" = symlink ]; then
    ssh_restore_foreign_watchdog="$SSH_RESTORE_CASE_DIR/foreign-watchdog"
    mkdir -p "$ssh_restore_foreign_watchdog"
    printf '%s\n' preserve >"$ssh_restore_foreign_watchdog/sentinel"
    ln -s "$ssh_restore_foreign_watchdog" "$NOBRAND_SSH_WATCHDOG_DIR"
  else
    printf '%s\n' preserve >"$NOBRAND_SSH_WATCHDOG_DIR"
  fi
  ssh_restore_state_hash="$(sha256sum "$NOBRAND_SSH_STATE_FILE")"
  if run_ssh_restore_with_fake_identities >/dev/null 2>&1; then
    fail "SSH restore accepted a ${ssh_restore_bad_watchdog} watchdog root"
  fi
  [ ! -s "$SSH_RESTORE_MUTATION_LOG" ] \
    || fail "SSH restore mutated identities for a ${ssh_restore_bad_watchdog} watchdog root"
  [ ! -s "$SSH_RESTORE_TRANSACTION_LOG" ] \
    || fail "SSH restore logged identity creation for a ${ssh_restore_bad_watchdog} watchdog root"
  [ ! -e "$SSH_RESTORE_APPLY_LOG" ] \
    || fail "SSH restore applied policy for a ${ssh_restore_bad_watchdog} watchdog root"
  [ ! -e "$NOBRAND_SSH_CONFIG_DIR" ] && [ ! -L "$NOBRAND_SSH_CONFIG_DIR" ] \
    || fail "SSH restore created config payload before rejecting a ${ssh_restore_bad_watchdog} watchdog root"
  assert_eq "$ssh_restore_state_hash" "$(sha256sum "$NOBRAND_SSH_STATE_FILE")" \
    "SSH restore preserves state for a ${ssh_restore_bad_watchdog} watchdog root"
  if [ "$ssh_restore_bad_watchdog" = symlink ]; then
    assert_eq preserve "$(cat "$ssh_restore_foreign_watchdog/sentinel")" \
      'SSH restore preserves the watchdog symlink target sentinel'
    [ -z "$(find "$ssh_restore_foreign_watchdog" -mindepth 1 -maxdepth 1 \
      ! -name sentinel -print -quit)" ] \
      || fail 'SSH restore wrote through its watchdog symlink root'
  else
    assert_eq preserve "$(cat "$NOBRAND_SSH_WATCHDOG_DIR")" \
      'SSH restore preserves the non-directory watchdog root'
  fi
done

# Model managed identities outside the NoBrand roots.  The real finalizer is
# exercised while only account/group lookups and deletion primitives are
# replaced.  Sending TERM from a successful fake deletion reproduces a process
# interruption after the external identity changed but before state cleanup.
SSH_FAKE_USERS_DIR=''
SSH_FAKE_GROUP_FILE=''
SSH_FAKE_DELETE_LOG=''
SSH_INTERRUPT_AFTER_USER=''
SSH_INTERRUPT_AFTER_GROUP=0
SSH_MISMATCH_USER=''
SSH_MISMATCH_GROUP=0
SSH_FAIL_CONFIG_CLEANUP=0
SSH_FAIL_STATE_PAYLOAD_CLEANUP=0

prepare_ssh_finalize_fixture() {
  local name="$1" user_one user_two users tmp
  local case_dir="$fixture/finalize-cases/$name"
  rm -rf -- "$NOBRAND_SSH_STATE_DIR" "$NOBRAND_SSH_CONFIG_DIR" "$case_dir"
  mkdir -p "$NOBRAND_SSH_KEYS_DIR/a1111111111111111" "$NOBRAND_SSH_KEYS_DIR/a2222222222222222" \
    "$NOBRAND_SSH_AUTHORIZED_KEYS_DIR" "$NOBRAND_SSH_ACCOUNT_MARKER_DIR" "$case_dir/users"
  SSH_FAKE_USERS_DIR="$case_dir/users"
  SSH_FAKE_GROUP_FILE="$case_dir/group"
  SSH_FAKE_DELETE_LOG="$case_dir/deleted.log"
  : >"$SSH_FAKE_DELETE_LOG"
  printf '%s\n' 49000 >"$SSH_FAKE_GROUP_FILE"
  printf '%s\n' 49001 >"$SSH_FAKE_USERS_DIR/nbt-test-one"
  printf '%s\n' 49002 >"$SSH_FAKE_USERS_DIR/nbt-test-two"
  printf '%s\n' key-one >"$NOBRAND_SSH_AUTHORIZED_KEYS_DIR/nbt-test-one"
  printf '%s\n' key-two >"$NOBRAND_SSH_AUTHORIZED_KEYS_DIR/nbt-test-two"
  printf '%s\n' private-one >"$NOBRAND_SSH_KEYS_DIR/a1111111111111111/id_ed25519"
  printf '%s\n' private-two >"$NOBRAND_SSH_KEYS_DIR/a2222222222222222/id_ed25519"
  jq -n --arg group "$NOBRAND_SSH_GROUP" --argjson gid 49000 \
    '{ownership:"nobrand-v3",group:$group,gid:$gid}' >"$NOBRAND_SSH_GROUP_MARKER"
  jq -n '{ownership:"nobrand-v3",account_id:"a1111111111111111",linux_user:"nbt-test-one",uid:49001}' \
    >"$(ssh_tunnel_account_marker_file nbt-test-one)"
  jq -n '{ownership:"nobrand-v3",account_id:"a2222222222222222",linux_user:"nbt-test-two",uid:49002}' \
    >"$(ssh_tunnel_account_marker_file nbt-test-two)"
  user_one="$(ssh_tunnel_user_json a1111111111111111 one nbt-test-one 49001 SHA256:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA 2026-08-30T00:00:00Z)"
  user_two="$(ssh_tunnel_user_json a2222222222222222 two nbt-test-two 49002 SHA256:BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB 2026-08-30T00:00:00Z)"
  users="$(jq -cn --argjson one "$user_one" --argjson two "$user_two" '[$one,$two]')"
  tmp="$(mktemp_file .ssh-finalize-state)"
  ssh_tunnel_generate_state "$tmp" custom entry.example.test 443 2222 marker-block \
    "$NOBRAND_SSH_CONFIG_MAIN" "$users" 2026-08-30T00:00:00Z
  jq '.policy_applied=false | .pending_operation="uninstall"
      | .pending_watchdog_token="" | .pending_watchdog_pid=""
      | .pending_origin_connection=""' "$tmp" >"$NOBRAND_SSH_STATE_FILE"
  rm -f "$tmp"
  chmod 0600 "$NOBRAND_SSH_STATE_FILE"
}

run_ssh_finalize_with_fake_identities() (
  trap - EXIT
  _has_user() { [ -f "$SSH_FAKE_USERS_DIR/$1" ]; }
  _has_group() { [ "$1" = "$NOBRAND_SSH_GROUP" ] && [ -f "$SSH_FAKE_GROUP_FILE" ]; }
  getent() {
    local database="${1:-}" key="${2:-}" path name uid
    case "$database" in
      group)
        if [ -f "$SSH_FAKE_GROUP_FILE" ] \
           && { [ "$key" = "$NOBRAND_SSH_GROUP" ] || [ "$key" = "$(cat "$SSH_FAKE_GROUP_FILE")" ]; }; then
          printf '%s:x:%s:\n' "$NOBRAND_SSH_GROUP" "$(cat "$SSH_FAKE_GROUP_FILE")"
          return 0
        fi
        return 2
        ;;
      passwd)
        if [ -f "$SSH_FAKE_USERS_DIR/$key" ]; then
          printf '%s:x:%s:49999:foreign:/nonexistent:/usr/sbin/nologin\n' \
            "$key" "$(cat "$SSH_FAKE_USERS_DIR/$key")"
          return 0
        fi
        shopt -s nullglob
        for path in "$SSH_FAKE_USERS_DIR"/*; do
          uid="$(cat "$path")"
          [ "$uid" = "$key" ] || continue
          name="$(basename "$path")"
          printf '%s:x:%s:49999:foreign:/nonexistent:/usr/sbin/nologin\n' "$name" "$uid"
          return 0
        done
        return 2
        ;;
      *) return 2 ;;
    esac
  }
  id() {
    if [ "${1:-}" = -u ] && [ -f "$SSH_FAKE_USERS_DIR/${2:-}" ]; then
      cat "$SSH_FAKE_USERS_DIR/${2:-}"
    else
      command id "$@"
    fi
  }
  ssh_tunnel_user_identity_valid() {
    local user_json="$1" name expected_uid
    name="$(jq -r .linux_user <<<"$user_json")"
    expected_uid="$(jq -r .uid <<<"$user_json")"
    [ -f "$SSH_FAKE_USERS_DIR/$name" ] || return 1
    [ "$(cat "$SSH_FAKE_USERS_DIR/$name")" = "$expected_uid" ] || return 1
    [ "$name" != "$SSH_MISMATCH_USER" ]
  }
  ssh_tunnel_group_identity_valid() {
    [ -f "$SSH_FAKE_GROUP_FILE" ] && [ "$SSH_MISMATCH_GROUP" -eq 0 ]
  }
  ssh_tunnel_delete_linux_user() {
    local name="$1"
    printf 'user:%s\n' "$name" >>"$SSH_FAKE_DELETE_LOG"
    rm -f "$SSH_FAKE_USERS_DIR/$name"
    if [ "$name" = "$SSH_INTERRUPT_AFTER_USER" ]; then
      kill -TERM "$BASHPID"
    fi
  }
  groupdel() {
    printf 'group:%s\n' "$1" >>"$SSH_FAKE_DELETE_LOG"
    rm -f "$SSH_FAKE_GROUP_FILE"
    if [ "$SSH_INTERRUPT_AFTER_GROUP" -eq 1 ]; then
      kill -TERM "$BASHPID"
    fi
  }
  delgroup() { groupdel "$@"; }
  pkill() { return 0; }
  if [ "$SSH_FAIL_CONFIG_CLEANUP" -eq 1 ]; then
    ssh_tunnel_clear_managed_directory() { return 74; }
  fi
  if [ "$SSH_FAIL_STATE_PAYLOAD_CLEANUP" -eq 1 ]; then
    ssh_tunnel_clear_state_payload() { return 74; }
  fi
  ssh_tunnel_finalize_uninstall
)

prepare_ssh_finalize_fixture interrupted-user
SSH_INTERRUPT_AFTER_USER=nbt-test-one
set +e
run_ssh_finalize_with_fake_identities >/dev/null 2>&1
interrupted_user_rc=$?
set -e
[ "$interrupted_user_rc" -ne 0 ] || fail 'user-deletion interruption unexpectedly completed'
[ ! -e "$SSH_FAKE_USERS_DIR/nbt-test-one" ] \
  || fail 'user-deletion interruption did not cross the intended boundary'
[ -e "$SSH_FAKE_USERS_DIR/nbt-test-two" ] \
  || fail 'user-deletion interruption deleted a later identity'
[ -e "$NOBRAND_SSH_STATE_FILE" ] \
  || fail 'user-deletion interruption removed authoritative SSH state'
SSH_INTERRUPT_AFTER_USER=''
run_ssh_finalize_with_fake_identities >/dev/null
[ -z "$(find "$SSH_FAKE_USERS_DIR" -mindepth 1 -maxdepth 1 -type f -print -quit)" ] \
  || fail 'user-deletion retry left a managed identity'
[ ! -e "$SSH_FAKE_GROUP_FILE" ] || fail 'user-deletion retry left the managed group'
[ ! -e "$NOBRAND_SSH_STATE_FILE" ] || fail 'user-deletion retry left SSH state'

prepare_ssh_finalize_fixture interrupted-group
SSH_INTERRUPT_AFTER_GROUP=1
set +e
run_ssh_finalize_with_fake_identities >/dev/null 2>&1
interrupted_group_rc=$?
set -e
[ "$interrupted_group_rc" -ne 0 ] || fail 'group-deletion interruption unexpectedly completed'
[ ! -e "$SSH_FAKE_GROUP_FILE" ] \
  || fail 'group-deletion interruption did not cross the intended boundary'
[ -e "$NOBRAND_SSH_STATE_FILE" ] \
  || fail 'group-deletion interruption removed authoritative SSH state'
SSH_INTERRUPT_AFTER_GROUP=0
run_ssh_finalize_with_fake_identities >/dev/null
[ ! -e "$NOBRAND_SSH_STATE_FILE" ] || fail 'group-deletion retry left SSH state'

prepare_ssh_finalize_fixture config-cleanup-failure
SSH_FAIL_CONFIG_CLEANUP=1
if run_ssh_finalize_with_fake_identities >/dev/null 2>&1; then
  fail 'forced SSH config cleanup failure unexpectedly completed'
fi
[ -e "$NOBRAND_SSH_STATE_FILE" ] \
  || fail 'SSH config cleanup failure removed authoritative state'
SSH_FAIL_CONFIG_CLEANUP=0
run_ssh_finalize_with_fake_identities >/dev/null
[ ! -e "$NOBRAND_SSH_STATE_FILE" ] \
  || fail 'SSH config cleanup failure retry did not converge'

prepare_ssh_finalize_fixture state-payload-cleanup-failure
SSH_FAIL_STATE_PAYLOAD_CLEANUP=1
if run_ssh_finalize_with_fake_identities >/dev/null 2>&1; then
  fail 'forced SSH state payload cleanup failure unexpectedly completed'
fi
[ -e "$NOBRAND_SSH_STATE_FILE" ] \
  || fail 'SSH state payload cleanup failure removed authoritative state'
SSH_FAIL_STATE_PAYLOAD_CLEANUP=0
run_ssh_finalize_with_fake_identities >/dev/null
[ ! -e "$NOBRAND_SSH_STATE_FILE" ] \
  || fail 'SSH state payload cleanup failure retry did not converge'

prepare_ssh_finalize_fixture state-removed-last
set +e
NOBRAND_TEST_MODE=1 NOBRAND_TEST_INTERRUPT_SSH_UNINSTALL_AT=before-state-removal \
  run_ssh_finalize_with_fake_identities >/dev/null 2>&1
state_last_rc=$?
set -e
assert_eq 75 "$state_last_rc" 'SSH pre-state-removal interruption status'
[ -e "$NOBRAND_SSH_STATE_FILE" ] \
  || fail 'SSH authoritative state was not the final managed state payload'
[ -z "$(find "$NOBRAND_SSH_STATE_DIR" -mindepth 1 -maxdepth 1 \
  ! -path "$NOBRAND_SSH_STATE_FILE" -print -quit)" ] \
  || fail 'SSH payload remained at the pre-state-removal boundary'
run_ssh_finalize_with_fake_identities >/dev/null
[ ! -e "$NOBRAND_SSH_STATE_FILE" ] \
  || fail 'SSH pre-state-removal interruption retry did not converge'

prepare_ssh_finalize_fixture mismatched-user
SSH_MISMATCH_USER=nbt-test-one
if run_ssh_finalize_with_fake_identities >/dev/null 2>&1; then
  fail 'same-name replacement user was accepted as a managed identity'
fi
[ -e "$SSH_FAKE_USERS_DIR/nbt-test-one" ] \
  || fail 'mismatched user was deleted'
[ ! -s "$SSH_FAKE_DELETE_LOG" ] \
  || fail 'mismatched-user preflight performed a destructive action'
SSH_MISMATCH_USER=''

prepare_ssh_finalize_fixture mismatched-group
SSH_MISMATCH_GROUP=1
if run_ssh_finalize_with_fake_identities >/dev/null 2>&1; then
  fail 'same-name replacement group was accepted as managed'
fi
[ -s "$SSH_FAKE_GROUP_FILE" ] || fail 'mismatched group was deleted'
[ ! -s "$SSH_FAKE_DELETE_LOG" ] \
  || fail 'mismatched-group preflight performed a destructive action'
SSH_MISMATCH_GROUP=0

prepare_ssh_finalize_fixture reused-uid
rm -f "$SSH_FAKE_USERS_DIR/nbt-test-one"
printf '%s\n' 49001 >"$SSH_FAKE_USERS_DIR/foreign-reused-uid"
run_ssh_finalize_with_fake_identities >/dev/null
[ -e "$SSH_FAKE_USERS_DIR/foreign-reused-uid" ] \
  || fail 'an unrelated username reusing an old managed UID was deleted'
assert_not_contains "$(cat "$SSH_FAKE_DELETE_LOG")" 'foreign-reused-uid' \
  'reused UID identity is never selected for deletion'

prepare_ssh_finalize_fixture symlink-root
foreign_root="$fixture/finalize-cases/symlink-root/foreign-config"
rm -rf -- "$NOBRAND_SSH_CONFIG_DIR"
mkdir -p "$foreign_root"
printf '%s\n' preserve >"$foreign_root/sentinel"
ln -s "$foreign_root" "$NOBRAND_SSH_CONFIG_DIR"
if run_ssh_finalize_with_fake_identities >/dev/null 2>&1; then
  fail 'SSH finalization accepted a symlink managed root'
fi
assert_eq preserve "$(cat "$foreign_root/sentinel")" \
  'symlink-root rejection preserves the external target'
[ ! -s "$SSH_FAKE_DELETE_LOG" ] \
  || fail 'symlink-root preflight performed a destructive identity action'

# The fail-closed symlink case deliberately leaves its state payload intact.
# Reset only the fixture roots before exercising unrelated creation rollback.
rm -f -- "$NOBRAND_SSH_CONFIG_DIR"
rm -rf -- "$NOBRAND_SSH_STATE_DIR"
mkdir -p "$NOBRAND_SSH_STATE_DIR" "$NOBRAND_SSH_CONFIG_DIR"
ssh_tunnel_generate_state "$NOBRAND_SSH_STATE_FILE" custom entry.example.test 443 2222 marker-block \
  "$NOBRAND_SSH_CONFIG_MAIN" '[]' 2026-08-30T00:00:00Z
chmod 0600 "$NOBRAND_SSH_STATE_FILE"

# Early identity-creation failures must not leave an orphan group, Linux user,
# key directory, authorized key, or account marker.
simulated_group="$fixture/simulated-group"
simulated_user="$fixture/simulated-user"
fail_destination=""
_has_group() { [ -s "$simulated_group" ]; }
_has_user() { [ -s "$simulated_user" ] && [ "$(cat "$simulated_user")" = "$1" ]; }
groupadd() { printf '%s\n' 49000 >"$simulated_group"; }
groupdel() { rm -f "$simulated_group"; }
getent() {
  case "${1:-}" in
    group) [ -s "$simulated_group" ] && printf '%s:x:49000:\n' "$NOBRAND_SSH_GROUP" ;;
    *) command getent "$@" ;;
  esac
}
ssh_tunnel_create_linux_user() { printf '%s\n' "$1" >"$simulated_user"; }
ssh_tunnel_delete_linux_user() { rm -f "$simulated_user"; }
id() {
  if [ "${1:-}" = -u ] && [ -s "$simulated_user" ] && [ "$(cat "$simulated_user")" = "${2:-}" ]; then
    printf '%s\n' 49001
  else
    command id "$@"
  fi
}
nb_atomic_install_file() {
  local source="$1" destination="$2" mode="${3:-0600}"
  [ "$destination" != "$fail_destination" ] || return 1
  mkdir -p "$(dirname "$destination")" && install -m "$mode" "$source" "$destination"
}

rm -f "$NOBRAND_SSH_GROUP_MARKER"
fail_destination="$NOBRAND_SSH_GROUP_MARKER"
if ssh_tunnel_create_group; then
  fail 'SSH group marker failure must fail group creation'
fi
[ ! -e "$simulated_group" ] || fail 'SSH group marker failure left an orphan group'
[ ! -e "$NOBRAND_SSH_GROUP_MARKER" ] || fail 'SSH group marker failure left a marker'

fail_destination="$NOBRAND_SSH_STATE_FILE"
if ssh_tunnel_add_user_internal transaction-user >/dev/null 2>&1; then
  fail 'SSH state commit failure must fail user creation'
fi
[ ! -e "$simulated_user" ] || fail 'SSH state commit failure left an orphan Linux user'
[ -z "$(find "$NOBRAND_SSH_KEYS_DIR" -mindepth 1 -maxdepth 1 -print -quit)" ] \
  || fail 'SSH state commit failure left private-key material'
[ -z "$(find "$NOBRAND_SSH_AUTHORIZED_KEYS_DIR" -mindepth 1 -maxdepth 1 -type f -print -quit)" ] \
  || fail 'SSH state commit failure left an authorized key'
[ -z "$(find "$NOBRAND_SSH_ACCOUNT_MARKER_DIR" -mindepth 1 -maxdepth 1 -type f \
  ! -name .group.json -print -quit)" ] || fail 'SSH state commit failure left an account marker'

pass 'SSH watchdog claims, interruption-safe uninstall, and identity/apply rollback transactions'
