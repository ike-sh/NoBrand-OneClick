#!/usr/bin/env bash
# Fixture variables are consumed by dynamically sourced manager functions.
# shellcheck disable=SC2034
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/testlib.sh"

fixture="$(mktemp -d)"
active_pid=""
second_pid=""
trap 'if [ -n "$active_pid" ]; then kill -TERM "$active_pid" 2>/dev/null || true; wait "$active_pid" 2>/dev/null || true; fi; if [ -n "$second_pid" ]; then kill -TERM "$second_pid" 2>/dev/null || true; wait "$second_pid" 2>/dev/null || true; fi; rm -rf -- "$fixture"' EXIT
export NOBRAND_STATE_DIR="$fixture/state"
export NOBRAND_CONFIG_DIR="$fixture/config"
export NOBRAND_LIB_DIR="$fixture/lib"
export NOBRAND_LIFECYCLE_DIR="$fixture/nobrand-oneclick-lifecycle"
export NOBRAND_LIFECYCLE_LOCK_FILE="$fixture/run/nobrand-oneclick/lifecycle.lock"
export NOBRAND_TEST_MODE=1
mkdir -p "$fixture/run" "$NOBRAND_STATE_DIR/snell/instances"
source_installer
# The generated installer may lag the source during a focused test.
# shellcheck disable=SC1091
source "$TEST_ROOT/src/52-user-actions-ui.sh"
# shellcheck disable=SC1091
source "$TEST_ROOT/src/90-ui.sh"
# shellcheck disable=SC1091
source "$TEST_ROOT/src/99-main.sh"
trap - ERR

snell_id=saaaaaaaaaaaaaaaa
jq -n --arg id "$snell_id" --arg name '测试-节点甲' \
  '{instance_id:$id,version:5,name:$name}' \
  >"$NOBRAND_SNELL_STATE_DIR/$snell_id.json"

# Only replace installation/environment setup. main(), the menus, and flock
# are the real implementations in this two-process fixture.
nb_validate_authoritative_state_boundary() { NOBRAND_INSTALL_STATE=CURRENT_COMPLETE; }
nb_classify_installation_state() { printf CURRENT_COMPLETE; }
nobrand_manager_bootstrap() { return 0; }
ensure_manager_state_layout() { return 0; }
nobrand_ssh_confirmation_pending() { return 1; }
nobrand_doctor() { printf 'DOCTOR_PASS\n'; }

read_tty() {
  local value=""
  TEST_PROMPT_INDEX=$((TEST_PROMPT_INDEX + 1))
  printf '%s\n' "$TEST_PROMPT_INDEX" >"$TEST_CASE_DIR/prompt-index"
  printf '%s\n' "${2:-}" >"$TEST_CASE_DIR/prompt"
  IFS= read -r value <"$TEST_INPUT_FIFO" || return 1
  printf -v "$1" '%s' "$value"
}

wait_for_prompt() {
  local wanted="$1" current="" attempt
  for attempt in {1..150}; do
    current="$(cat "$TEST_CASE_DIR/prompt-index" 2>/dev/null || true)"
    [ "$current" != "$wanted" ] || return 0
    kill -0 "$active_pid" 2>/dev/null || break
    sleep 0.1
  done
  cat "$TEST_CASE_DIR/output" >&2 || true
  fail "menu did not reach prompt $wanted"
}

run_idle_case() {
  local label="$1" wanted="$2" signal="$3" exit_status="$4" action="$5"
  local input_fd="" input lock_status doctor_status doctor_rc
  local observed=1 attempt menu_rc
  shift 5
  TEST_CASE_DIR="$fixture/$label"
  TEST_INPUT_FIFO="$TEST_CASE_DIR/input"
  mkdir -p "$TEST_CASE_DIR"
  mkfifo "$TEST_INPUT_FIFO"
  exec {input_fd}<>"$TEST_INPUT_FIFO"
  (
    exec {input_fd}>&-
    TEST_PROMPT_INDEX=0
    ACTION="$action"
    [ "$action" != nobrand-forward ] || FORWARD_ACTION=menu
    main
  ) >"$TEST_CASE_DIR/output" 2>&1 &
  active_pid=$!
  wait_for_prompt 1
  for input in "$@"; do
    printf '%s\n' "$input" >&"$input_fd"
    observed=$((observed + 1))
    wait_for_prompt "$observed"
  done
  assert_eq "$wanted" "$observed" "$label prompt count"
  [ ! -e "/proc/$active_pid/fd/7" ] \
    || fail "$label idle menu retained FD 7"
  if flock -n "$NOBRAND_LIFECYCLE_LOCK_FILE" -c true; then
    lock_status=FREE
  else
    lock_status=HELD
  fi
  set +e
  ( ACTION=nobrand-doctor; main ) >"$TEST_CASE_DIR/doctor" 2>&1
  doctor_rc=$?
  set -e
  doctor_status=BLOCKED
  if [ "$doctor_rc" -eq 0 ] \
     && grep -q DOCTOR_PASS "$TEST_CASE_DIR/doctor"; then
    doctor_status=PASS
  fi
  if [ "$label" = main ]; then
    local second_dir="$fixture/second-menu" second_fd="" second_prompt=""
    mkdir -p "$second_dir"
    mkfifo "$second_dir/input"
    exec {second_fd}<>"$second_dir/input"
    (
      exec {second_fd}>&-
      TEST_CASE_DIR="$second_dir"
      TEST_INPUT_FIFO="$second_dir/input"
      TEST_PROMPT_INDEX=0
      ACTION=""
      main
    ) >"$second_dir/output" 2>&1 &
    second_pid=$!
    for attempt in {1..150}; do
      second_prompt="$(cat "$second_dir/prompt-index" 2>/dev/null || true)"
      [ "$second_prompt" != 1 ] || break
      kill -0 "$second_pid" 2>/dev/null || break
      sleep 0.1
    done
    assert_eq 1 "$second_prompt" 'second menu reaches prompt while first is idle'
    flock -n "$NOBRAND_LIFECYCLE_LOCK_FILE" -c true \
      || fail 'two idle menus held the lifecycle lock'
    kill -HUP "$second_pid"
    exec {second_fd}>&-
    set +e
    wait "$second_pid"
    menu_rc=$?
    set -e
    second_pid=""
    assert_eq 129 "$menu_rc" 'second menu HUP exit'

    (
      NOBRAND_MANAGER_SESSION_ACTIVE=1
      NOBRAND_MENU_EXPECTED_STATE=CURRENT_COMPLETE
      idle_peer_mutation() { : >"$fixture/idle-peer-mutated"; }
      nobrand_menu_run idle_peer_mutation
    ) >"$fixture/idle-peer.out" 2>&1 \
      || fail 'mutation from second session was blocked by idle menu'
    [ -e "$fixture/idle-peer-mutated" ] || fail 'idle peer mutation did not run'
    flock -n "$NOBRAND_LIFECYCLE_LOCK_FILE" -c true \
      || fail 'idle peer mutation retained lifecycle lock'
  fi
  printf '%s LOCK_%s DOCTOR_%s\n' "$label" "$lock_status" "$doctor_status"
  CASE_RESULTS+=("$label:$lock_status:$doctor_status")
  kill -"$signal" "$active_pid"
  exec {input_fd}>&-
  for attempt in {1..100}; do
    kill -0 "$active_pid" 2>/dev/null || break
    sleep 0.1
  done
  kill -0 "$active_pid" 2>/dev/null && fail "$label menu did not exit on $signal"
  set +e
  wait "$active_pid"
  menu_rc=$?
  set -e
  active_pid=""
  assert_eq "$exit_status" "$menu_rc" "$label $signal exit"
  flock -n "$NOBRAND_LIFECYCLE_LOCK_FILE" -c true \
    || fail "$label retained lock after HUP"
  [ ! -e "$NOBRAND_LIFECYCLE_TX_FILE" ] \
    || fail "$label created lifecycle transaction while idle"
}

CASE_RESULTS=()
printf 'BASELINE_VERSION=%s\n' "$SCRIPT_VERSION"
run_idle_case main 1 HUP 129 ''
run_idle_case snell_submenu 2 TERM 143 '' 2
run_idle_case snell_selector 3 HUP 129 '' 2 5
run_idle_case menu_pause 2 HUP 129 '' 15
run_idle_case mieru_user_submenu 3 HUP 129 '' 1 3
run_idle_case explicit_mieru 1 HUP 129 nobrand-mieru-menu
run_idle_case explicit_user_manage 1 HUP 129 user-manage
run_idle_case explicit_snell 1 HUP 129 nobrand-snell
run_idle_case explicit_hy2 1 HUP 129 nobrand-hy2
run_idle_case explicit_sudoku 1 HUP 129 nobrand-vless-sudoku
run_idle_case explicit_forward 1 HUP 129 nobrand-forward
for result in "${CASE_RESULTS[@]}"; do
  case "$result" in
    *:FREE:PASS) ;;
    *) fail "idle menu blocks another session: $result" ;;
  esac
done
pass 'idle main, protocol menus, and instance selector release lifecycle lock'
pass 'two menus coexist and an idle menu permits a peer mutation'

# A closed terminal must exit promptly; it must not spin through the menu.
TEST_CASE_DIR="$fixture/eof"
TEST_PROMPT_INDEX=0
read_tty() { TEST_PROMPT_INDEX=$((TEST_PROMPT_INDEX + 1)); return 1; }
ACTION=""
main >"$TEST_CASE_DIR.out" 2>&1 || fail 'EOF menu returned failure'
assert_eq 1 "$TEST_PROMPT_INDEX" 'EOF prompt count'
flock -n "$NOBRAND_LIFECYCLE_LOCK_FILE" -c true || fail 'EOF retained lock'
[ ! -e "$NOBRAND_LIFECYCLE_TX_FILE" ] || fail 'EOF created transaction'
pass 'EOF exits menu without a retry loop'

# Both actions use the real menu wrapper and flock. Their callbacks write
# disposable state, transaction, and ownership files only after taking it.
read_tty() { return 1; }
NOBRAND_MANAGER_SESSION_ACTIVE=1
NOBRAND_MENU_EXPECTED_STATE=CURRENT_COMPLETE
mutation_dir="$fixture/mutation"
mkdir -p "$mutation_dir"
mkfifo "$mutation_dir/barrier"
printf 'initial\n' >"$mutation_dir/state"
printf 'initial\n' >"$mutation_dir/ownership"
fixture_mutation() {
  local actor="$1" release=""
  if [ "$actor" = A ]; then
    : >"$mutation_dir/started"
    IFS= read -r release <"$mutation_dir/barrier" || return 1
  fi
  printf '%s\n' "$actor" >"$mutation_dir/state"
  printf '%s\n' "$actor" >"$mutation_dir/ownership"
  printf 'STATUS=complete\nACTOR=%s\n' "$actor" >"$mutation_dir/transaction"
}
nobrand_menu_run fixture_mutation A >"$mutation_dir/a.out" 2>&1 &
active_pid=$!
for attempt in {1..150}; do
  [ ! -e "$mutation_dir/started" ] || break
  kill -0 "$active_pid" 2>/dev/null || break
  sleep 0.1
done
[ -e "$mutation_dir/started" ] || fail 'first mutation did not reach barrier'
assert_eq "$NOBRAND_LIFECYCLE_LOCK_FILE" \
  "$(readlink "/proc/$active_pid/fd/7" 2>/dev/null || true)" \
  'active mutation FD 7 owns lifecycle lock file'
if nobrand_menu_run fixture_mutation B >"$mutation_dir/rejected.out" 2>&1; then
  fail 'conflicting mutation entered while first action held lock'
fi
assert_eq initial "$(cat "$mutation_dir/state")" 'state before release'
assert_eq initial "$(cat "$mutation_dir/ownership")" 'ownership before release'
[ ! -e "$mutation_dir/transaction" ] || fail 'rejected action wrote transaction'
printf 'continue\n' >"$mutation_dir/barrier"
wait "$active_pid" || fail 'first mutation failed'
active_pid=""
assert_eq A "$(cat "$mutation_dir/state")" 'first mutation state'
assert_eq A "$(cat "$mutation_dir/ownership")" 'first mutation ownership'
flock -n "$NOBRAND_LIFECYCLE_LOCK_FILE" -c true || fail 'action retained lock'
nobrand_menu_run fixture_mutation B >"$mutation_dir/retry.out" 2>&1
assert_eq B "$(cat "$mutation_dir/state")" 'retry state'
assert_eq B "$(cat "$mutation_dir/ownership")" 'retry ownership'
assert_eq $'STATUS=complete\nACTOR=B' "$(cat "$mutation_dir/transaction")" 'retry transaction'
flock -n "$NOBRAND_LIFECYCLE_LOCK_FILE" -c true || fail 'retry retained lock'
pass 'concurrent mutations serialize and released lock permits retry'

# Mieru uses its own menu action subprocess instead of nobrand_menu_run.
(
  NOBRAND_MANAGER_SESSION_ACTIVE=1
  NOBRAND_MENU_EXPECTED_STATE=CURRENT_COMPLETE
  mita_installed() { return 1; }
  show_menu() { ACTION=status; }
  menu_run_action() {
    assert_eq 1 "$NOBRAND_LIFECYCLE_LOCK_HELD" 'Mieru action lock depth'
    assert_eq 1 "${NOBRAND_LIFECYCLE_LOCK_FLOOR:-0}" 'Mieru child lock floor'
    case "$(trap -p TERM)" in
      *nb_lifecycle_signal_exit*) ;;
      *) fail 'Mieru child did not install lifecycle signal handler' ;;
    esac
    if flock -n "$NOBRAND_LIFECYCLE_LOCK_FILE" -c true; then
      fail 'Mieru action did not own lifecycle lock'
    fi
    : >"$fixture/mieru-action"
    return 2
  }
  menu_loop
) >"$fixture/mieru-action.out" 2>&1 || fail 'Mieru action menu failed'
[ -e "$fixture/mieru-action" ] || fail 'Mieru action was not dispatched'
flock -n "$NOBRAND_LIFECYCLE_LOCK_FILE" -c true || fail 'Mieru action retained lock'
[ ! -e "$NOBRAND_LIFECYCLE_TX_FILE" ] || fail 'Mieru test action created transaction'
pass 'Mieru action acquires and releases lifecycle lock'

(
  NOBRAND_MANAGER_SESSION_ACTIVE=1
  NOBRAND_MENU_EXPECTED_STATE=CURRENT_COMPLETE
  MAIN_MENU_ACTIVE=1
  mita_installed() { return 0; }
  user_choice_index=0
  read_tty() {
    user_choice_index=$((user_choice_index + 1))
    case "$user_choice_index" in
      1) printf -v "$1" 1 ;;
      2) printf -v "$1" 18 ;;
      *) return 1 ;;
    esac
  }
  do_user_list() {
    assert_eq 1 "$NOBRAND_LIFECYCLE_LOCK_HELD" 'Mieru user action lock depth'
    assert_eq 1 "${NOBRAND_LIFECYCLE_LOCK_FLOOR:-0}" 'Mieru user child lock floor'
    if flock -n "$NOBRAND_LIFECYCLE_LOCK_FILE" -c true; then
      fail 'Mieru user action did not own lifecycle lock'
    fi
    : >"$fixture/mieru-user-action"
  }
  user_menu_pause() {
    flock -n "$NOBRAND_LIFECYCLE_LOCK_FILE" -c true \
      || fail 'Mieru user menu pause held lifecycle lock'
  }
  set +e
  do_user_manage
  rc=$?
  set -e
  assert_eq 3 "$rc" 'Mieru user submenu returns to main menu'
) >"$fixture/mieru-user-action.out" 2>&1 || fail 'Mieru user submenu action failed'
[ -e "$fixture/mieru-user-action" ] || fail 'Mieru user action was not dispatched'
flock -n "$NOBRAND_LIFECYCLE_LOCK_FILE" -c true || fail 'Mieru user submenu retained lock'
pass 'Mieru user submenu locks actions but releases before pause'
