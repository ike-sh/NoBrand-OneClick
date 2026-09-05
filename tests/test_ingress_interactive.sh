#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/testlib.sh"

fixture="$(mktemp -d)"
trap 'rm -rf -- "$fixture"' EXIT

export NOBRAND_STATE_DIR="$fixture/state"
export NOBRAND_CONFIG_DIR="$fixture/config"
export NOBRAND_LIB_DIR="$fixture/lib"
export NOBRAND_LIFECYCLE_DIR="$fixture/nobrand-oneclick-lifecycle"
export NOBRAND_LIFECYCLE_TX_FILE="$NOBRAND_LIFECYCLE_DIR/transaction.env"
export NOBRAND_LIFECYCLE_LOCK_FILE="$fixture/run/nobrand-oneclick/lifecycle.lock"
export NOBRAND_INSTALL_SCRIPT_PATH="$fixture/bin/install-nobrand"
export NOBRAND_COMMAND_PATH="$fixture/bin/nobrand"
export NOBRAND_SHORT_COMMAND_PATH="$fixture/bin/nb"
export NOBRAND_TEST_MODE=1
export LANG_ZH=1
mkdir -p "$(dirname "$NOBRAND_LIFECYCLE_LOCK_FILE")"
chmod 0700 "$(dirname "$NOBRAND_LIFECYCLE_LOCK_FILE")"

source_installer

# Keep this focused test runnable before the release artifact is rebuilt. The
# normal suite still verifies that the generated installer matches these source
# modules byte-for-byte.
set --
# shellcheck disable=SC1091
source "$TEST_ROOT/src/10-cli-prelude.sh"
trap - ERR
# shellcheck disable=SC1091
source "$TEST_ROOT/src/15-core-state.sh"
# shellcheck disable=SC1091
source "$TEST_ROOT/src/16-core-ingress.sh"
# shellcheck disable=SC1091
source "$TEST_ROOT/src/80-lifecycle.sh"
# shellcheck disable=SC1091
source "$TEST_ROOT/src/90-ui.sh"
trap - ERR

cli_marker="$fixture/cli-state-action"
run_early_ingress_parser() {
  NOBRAND_TEST_SOURCE_ROOT="$TEST_ROOT" NOBRAND_TEST_MARKER="$cli_marker" \
    "$BASH" -c '
      set -euo pipefail
      source "$NOBRAND_TEST_SOURCE_ROOT/src/05-constants.sh"
      nb_init_state_layout() { printf init >"$NOBRAND_TEST_MARKER"; }
      nb_ingress_ensure_state() { printf ensure >"$NOBRAND_TEST_MARKER"; }
      set -- ingress add "$@"
      source "$NOBRAND_TEST_SOURCE_ROOT/src/10-cli-prelude.sh"
    ' bash "$@"
}

expect_cli_contract_rejection() {
  local label="$1" output
  shift
  rm -f -- "$cli_marker"
  if output="$(run_early_ingress_parser "$@" 2>&1)"; then
    fail "CLI omission unexpectedly parsed: $label"
  fi
  assert_contains "$output" \
    'ingress add 非交互模式需要 --name --type --interface --address --port-policy' \
    "CLI contract error: $label"
  [ ! -e "$cli_marker" ] || fail "CLI omission reached a state helper: $label"
}

expect_cli_contract_rejection name \
  --type public --interface ens3 --address 192.0.2.11 --port-policy manual-only
expect_cli_contract_rejection type \
  --name CLI-Guard --interface ens3 --address 192.0.2.11 --port-policy manual-only
expect_cli_contract_rejection interface \
  --name CLI-Guard --type public --address 192.0.2.11 --port-policy manual-only
expect_cli_contract_rejection address \
  --name CLI-Guard --type public --interface ens3 --port-policy manual-only
expect_cli_contract_rejection port-policy \
  --name CLI-Guard --type public --interface ens3 --address 192.0.2.11

rm -f -- "$cli_marker"
if missing_value_output="$(run_early_ingress_parser \
    --name CLI-Guard --type --interface ens3 --address 192.0.2.11 --port-policy manual-only 2>&1)"; then
  fail 'CLI --type without a value unexpectedly parsed'
fi
assert_contains "$missing_value_output" '--type 需要类型' 'CLI --type missing-value error'
[ ! -e "$cli_marker" ] || fail 'CLI --type missing value reached a state helper'

rm -f -- "$cli_marker"
if missing_value_output="$(run_early_ingress_parser \
    --name CLI-Guard --type public --interface ens3 --address 192.0.2.11 --port-policy 2>&1)"; then
  fail 'CLI --port-policy without a value unexpectedly parsed'
fi
assert_contains "$missing_value_output" '--port-policy 需要端口策略' 'CLI --port-policy missing-value error'
[ ! -e "$cli_marker" ] || fail 'CLI --port-policy missing value reached a state helper'

# The dispatcher must terminate explicitly even when an outer `if` suppresses
# Bash errexit for every function in the condition.
outer_trace="$fixture/outer-if.trace"
outer_output="$fixture/outer-if.out"
: >"$outer_trace"
runner_rc=0
if (
  set -Eeuo pipefail
  MENU_MODE=1
  NOBRAND_MANAGER_SESSION_ACTIVE=1
  ingress_menu_reset_requests
  # Request globals are consumed by the sourced production dispatcher.
  # shellcheck disable=SC2034
  INGRESS_ACTION=add INGRESS_NAME=Guard INGRESS_TYPE=public \
    INGRESS_INTERFACE='' INGRESS_ADDRESS='' INGRESS_PORT_POLICY=manual-only

  require_root() { printf 'root\n' >>"$outer_trace"; }
  nb_lifecycle_lock_acquire() { printf 'lifecycle-lock\n' >>"$outer_trace"; return 99; }
  admin_lock_acquire() { printf 'lock\n' >>"$outer_trace"; }
  admin_lock_release() { printf 'unlock\n' >>"$outer_trace"; }
  nb_init_state_layout() { printf 'init\n' >>"$outer_trace"; }
  nb_ingress_ensure_state() { printf 'ensure\n' >>"$outer_trace"; }
  nb_ingress_generate_id() { printf 'id\n' >>"$outer_trace"; printf i0000000000000001; }
  nb_atomic_install_file() { printf 'install\n' >>"$outer_trace"; }

  nobrand_run_ingress_action
) >"$outer_output" 2>&1; then
  runner_rc=0
else
  runner_rc=$?
fi
[ "$runner_rc" -ne 0 ] || fail 'invalid add succeeded with errexit suppressed'
assert_eq '' "$(<"$outer_trace")" 'no durable helper after rejected add'
assert_eq 1 "$(grep -Fc '[错误]' "$outer_output" || true)" 'single core validation error'
assert_not_contains "$(<"$outer_output")" '非交互模式需要' 'mode-neutral core error'
[ ! -e "$NOBRAND_INGRESS_STATE_FILE" ] || fail 'invalid runner created Ingress state'
[ ! -e "$NOBRAND_LIFECYCLE_TX_FILE" ] \
  || fail 'invalid preflight created a configure lifecycle transaction'

input_index=0
inputs=()
test_interface_rows=''
interface_calls="$fixture/interface.calls"
set_inputs() {
  inputs=("$@")
  input_index=0
}
read_tty() {
  local destination="$1" prompt="${2:-}"
  printf '%s\n' "$prompt"
  [ "$input_index" -lt "${#inputs[@]}" ] || {
    printf '[TEST] unexpected input exhaustion at: %s\n' "$prompt" >&2
    return 1
  }
  printf -v "$destination" '%s' "${inputs[$input_index]}"
  input_index=$((input_index + 1))
}
nb_ingress_interface_rows() {
  printf 'call\n' >>"$interface_calls"
  [ -z "$test_interface_rows" ] || printf '%s\n' "$test_interface_rows"
}
nb_registry_rows() { :; }
menu_pause() { :; }

case_output="$fixture/case.out"

# Exactly one eligible pair offers both defaults, and the final UI preflight
# consumes the snapshot instead of querying the host again.
test_interface_rows='ens3|192.0.2.11|UP|1'
: >"$interface_calls"
set_inputs Single 1 '' '' 3 '' '' ''
ingress_menu_collect_add >"$case_output" 2>&1 \
  || fail 'single-pair blank defaults were rejected'
assert_eq ens3 "$INGRESS_INTERFACE" 'single-pair default interface'
assert_eq 192.0.2.11 "$INGRESS_ADDRESS" 'single-pair default address'
assert_eq 1 "$INGRESS_INTERFACE_CLI" 'single-pair interface collected'
assert_eq 1 "$INGRESS_ADDRESS_CLI" 'single-pair address collected'
assert_eq 192.0.2.11 "$INGRESS_DISPLAY_HOST_DEFAULT" 'public display default'
assert_contains "$(<"$case_output")" '  1) ens3  192.0.2.11  [UP]' 'numbered single pair'
assert_contains "$(<"$case_output")" '网络接口 / Interface [ens3]:' 'single interface prompt'
assert_contains "$(<"$case_output")" '本地监听 IPv4 [192.0.2.11]:' 'single address prompt'
assert_not_contains "$(<"$case_output")" '非交互模式需要' 'single-pair CLI error isolation'
assert_eq 1 "$(wc -l <"$interface_calls" | tr -d '[:space:]')" 'single interface snapshot'

# Bad interface/address input is handled by the wizard and can recover without
# ever reaching the mutation dispatcher.
: >"$interface_calls"
set_inputs BadIface 1 ghost0 ens3 '' 3 '' '' ''
ingress_menu_collect_add >"$case_output" 2>&1 \
  || fail 'invalid interface did not re-prompt successfully'
assert_contains "$(<"$case_output")" \
  '网络接口不存在或没有可用的非回环 IPv4: ghost0' 'invalid interface guidance'
assert_eq ens3 "$INGRESS_INTERFACE" 'interface after re-prompt'

: >"$interface_calls"
set_inputs WrongPair 1 '' 198.51.100.12 '' 3 '' '' ''
ingress_menu_collect_add >"$case_output" 2>&1 \
  || fail 'wrong interface/address association did not re-prompt successfully'
assert_contains "$(<"$case_output")" \
  '该 IPv4 未配置在所选网络接口 ens3 上: 198.51.100.12' 'wrong address guidance'
assert_eq 192.0.2.11 "$INGRESS_ADDRESS" 'address after re-prompt'

# Multiple pairs are all numbered. A blank does not select the default-egress
# marker; the user must explicitly choose a row or the manual path.
test_interface_rows=$'ens3|192.0.2.11|UP|1\nens4|198.51.100.12|UP|0'
: >"$interface_calls"
set_inputs Multi 1 '' 2 3 '' '' ''
ingress_menu_collect_add >"$case_output" 2>&1 \
  || fail 'multi-pair explicit selection failed'
grep -Fqx '  1) ens3  192.0.2.11  [UP] [默认出口/default egress]' "$case_output" \
  || fail 'first numbered pair or read-only egress marker missing'
grep -Fqx '  2) ens4  198.51.100.12  [UP]' "$case_output" \
  || fail 'second numbered pair missing'
assert_contains "$(<"$case_output")" '请选择列表编号、m 手动输入，或 0 返回' \
  'blank multi-pair selection rejected'
assert_eq ens4 "$INGRESS_INTERFACE" 'explicit multi-pair interface'
assert_eq 198.51.100.12 "$INGRESS_ADDRESS" 'explicit multi-pair address'
assert_eq 1 "$(wc -l <"$interface_calls" | tr -d '[:space:]')" 'multi interface snapshot'

# Two addresses on the same interface remain distinct numbered choices.
test_interface_rows=$'ens3|192.0.2.11|UP|1\nens3|192.0.2.12|UP|1'
: >"$interface_calls"
set_inputs SameIface 1 2 3 '' '' ''
ingress_menu_collect_add >"$case_output" 2>&1 \
  || fail 'same-interface second address selection failed'
assert_eq ens3 "$INGRESS_INTERFACE" 'same-interface selected interface'
assert_eq 192.0.2.12 "$INGRESS_ADDRESS" 'same-interface selected second address'

# Zero eligible rows stop before any question or action and create no state.
test_interface_rows=''
: >"$interface_calls"
set_inputs
if ingress_menu_collect_add >"$case_output" 2>&1; then
  fail 'zero-row collector unexpectedly succeeded'
fi
assert_contains "$(<"$case_output")" '未检测到可用的非回环 IPv4' 'zero-row Chinese error'
assert_not_contains "$(<"$case_output")" '名称:' 'zero-row stops before questions'
assert_not_contains "$(<"$case_output")" '非交互模式需要' 'zero-row CLI error isolation'
[ ! -e "$NOBRAND_INGRESS_STATE_FILE" ] || fail 'zero-row collector created Ingress state'
[ ! -e "$NOBRAND_LIFECYCLE_TX_FILE" ] || fail 'zero-row collector created a lifecycle transaction'

# derived-tail incompatibility is explained once and offers every controlled
# fallback without stacking core errors.
test_interface_rows='ens3|192.0.2.10|UP|1'
: >"$interface_calls"
set_inputs Derived 1 '' '' 1 2 '' '' ''
ingress_menu_collect_add >"$case_output" 2>&1 \
  || fail 'derived-tail manual fallback failed'
assert_eq 1 "$(grep -Fc '所选本地 IPv4 无法使用 derived-tail。请选择替代策略：' "$case_output" || true)" \
  'single derived-tail explanation'
assert_contains "$(<"$case_output")" '1) custom-range' 'derived custom fallback offer'
assert_contains "$(<"$case_output")" '2) manual-only' 'derived manual fallback offer'
assert_contains "$(<"$case_output")" '0) 返回 Ingress 菜单' 'derived return offer'
assert_eq manual-only "$INGRESS_PORT_POLICY" 'derived manual fallback policy'

: >"$interface_calls"
set_inputs DerivedCustom 1 '' '' 1 1 31001 31020 '' '' ''
ingress_menu_collect_add >"$case_output" 2>&1 \
  || fail 'derived-tail custom-range fallback failed'
assert_eq custom-range "$INGRESS_PORT_POLICY" 'derived custom fallback policy'
assert_eq 31001 "$INGRESS_RANGE_START" 'derived custom fallback start'
assert_eq 31020 "$INGRESS_RANGE_END" 'derived custom fallback end'
assert_eq 1 "$(grep -Fc '所选本地 IPv4 无法使用 derived-tail。请选择替代策略：' "$case_output" || true)" \
  'single derived-tail custom explanation'

: >"$interface_calls"
set_inputs DerivedReturn 1 '' '' 1 0
if ingress_menu_collect_add >"$case_output" 2>&1; then
  fail 'derived-tail return path unexpectedly completed'
fi
assert_eq 1 "$(grep -Fc '所选本地 IPv4 无法使用 derived-tail。请选择替代策略：' "$case_output" || true)" \
  'single derived-tail return explanation'

# RFC1918 means the three explicit private ranges, not a library's broader
# interpretation of special-purpose addressing.
for private_ip in 10.0.0.1 172.16.0.1 172.31.255.254 192.168.1.1; do
  nb_ingress_is_rfc1918 "$private_ip" || fail "RFC1918 address rejected: $private_ip"
done
for public_ip_value in 172.15.255.254 172.32.0.1 100.64.0.1 192.0.2.1 192.169.0.1; do
  if nb_ingress_is_rfc1918 "$public_ip_value"; then
    fail "non-RFC1918 address accepted: $public_ip_value"
  fi
done

test_interface_rows='lan0|10.23.4.11|UP|0'
: >"$interface_calls"
set_inputs PrivatePublic 1 '' '' 3 '' '' ''
ingress_menu_collect_add >"$case_output" 2>&1 \
  || fail 'public RFC1918 collector failed'
assert_contains "$(<"$case_output")" '[提示] 所选本地 IPv4 为私网地址。' 'RFC1918 public hint'
assert_contains "$(<"$case_output")" '通常应使用 mapped，并设置 Display Host' 'mapped suggestion'
assert_contains "$(<"$case_output")" '当前类型仍保持 public' 'public type retention notice'
assert_eq public "$INGRESS_TYPE" 'RFC1918 hint does not switch type'
assert_eq 10.23.4.11 "$INGRESS_DISPLAY_HOST_DEFAULT" 'RFC1918 public display default'

# mapped profiles reject a blank Display Host and clearly distinguish it from
# the local listener address.
test_interface_rows='ens3|192.0.2.11|UP|1'
: >"$interface_calls"
set_inputs Mapped 2 '' '' 3 '' '' mapped.example.test ''
ingress_menu_collect_add >"$case_output" 2>&1 \
  || fail 'mapped Display Host retry failed'
assert_eq 1 "$(grep -Fc 'mapped 入口必须显式填写有效的 Display Host' "$case_output" || true)" \
  'mapped blank Display Host rejection'
assert_contains "$(<"$case_output")" \
  '展示入口 / Display Host（mapped 必填；不同于本地监听 IPv4）' 'mapped listener/display distinction'
assert_eq mapped.example.test "$INGRESS_DISPLAY_HOST_DEFAULT" 'mapped explicit Display Host'

# A successful UI preflight is not a substitute for the dispatcher's live
# TOCTOU validation. Removing the address before dispatch must still stop before
# root checks, locks, layout, IDs, or installs.
toctou_trace="$fixture/toctou.trace"
toctou_output="$fixture/toctou.out"
: >"$toctou_trace"
runner_rc=0
# Request global is consumed by the sourced production dispatcher.
# shellcheck disable=SC2034
INGRESS_ACTION=add
if (
  set -Eeuo pipefail
  MENU_MODE=1
  nb_ingress_interface_rows() { :; }
  require_root() { printf 'root\n' >>"$toctou_trace"; }
  admin_lock_acquire() { printf 'lock\n' >>"$toctou_trace"; }
  admin_lock_release() { printf 'unlock\n' >>"$toctou_trace"; }
  nb_init_state_layout() { printf 'init\n' >>"$toctou_trace"; }
  nb_ingress_ensure_state() { printf 'ensure\n' >>"$toctou_trace"; }
  nb_ingress_generate_id() { printf 'id\n' >>"$toctou_trace"; printf i0000000000000001; }
  nb_atomic_install_file() { printf 'install\n' >>"$toctou_trace"; }
  nobrand_run_ingress_action
) >"$toctou_output" 2>&1; then
  runner_rc=0
else
  runner_rc=$?
fi
[ "$runner_rc" -ne 0 ] || fail 'TOCTOU-invalid add unexpectedly succeeded'
assert_eq '' "$(<"$toctou_trace")" 'TOCTOU failure stops before durable helpers'
assert_eq 1 "$(grep -Fc '[错误]' "$toctou_output" || true)" 'single TOCTOU validation error'
[ ! -e "$NOBRAND_INGRESS_STATE_FILE" ] || fail 'TOCTOU validation created Ingress state'

# Cancelling after an invalid manual interface never dispatches. The next list
# action and final 0 prove that the Ingress menu remains usable.
menu_trace="$fixture/menu.trace"
menu_output="$fixture/menu.out"
: >"$menu_trace"
test_interface_rows=$'ens3|192.0.2.11|UP|1\nens4|198.51.100.12|UP|0'
set_inputs 2 Cancelled 1 m ghost0 0 1 0
(
  set -Eeuo pipefail
  # Consumed by die() in the sourced production UI.
  # shellcheck disable=SC2034
  MENU_MODE=1
  nobrand_run_ingress_action() { printf 'unexpected-action\n' >>"$menu_trace"; }
  nb_ingress_list() { printf 'list\n' >>"$menu_trace"; }
  ingress_menu_loop
) >"$menu_output" 2>&1 &
menu_pid=$!
set +e
wait "$menu_pid"
menu_rc=$?
set -e
assert_eq 0 "$menu_rc" 'manual-cancel Ingress menu status'
assert_eq list "$(<"$menu_trace")" 'manual-cancel does not dispatch add'
assert_contains "$(<"$menu_output")" \
  '网络接口不存在或没有可用的非回环 IPv4: ghost0' 'manual invalid-interface guidance'

# A real nobrand_menu_run wrapper contains an action failure. The following
# list action executes, and 0 exits the Ingress menu normally.
: >"$menu_trace"
test_interface_rows='ens3|192.0.2.11|UP|1'
set_inputs 2 Recovered 1 '' 198.51.100.12 '' 3 '' '' '' 1 0
(
  set -Eeuo pipefail
  # Consumed by die() in the sourced production UI.
  # shellcheck disable=SC2034
  MENU_MODE=1
  nobrand_run_ingress_action() {
    printf 'add|%s|%s\n' "$INGRESS_INTERFACE" "$INGRESS_ADDRESS" >>"$menu_trace"
    return 42
  }
  nb_ingress_list() { printf 'list\n' >>"$menu_trace"; }
  ingress_menu_loop
) >"$menu_output" 2>&1 &
menu_pid=$!
set +e
wait "$menu_pid"
menu_rc=$?
set -e
assert_eq 0 "$menu_rc" 'failed-action Ingress menu recovery status'
assert_eq $'add|ens3|192.0.2.11\nlist' "$(<"$menu_trace")" 'action failure followed by list'
assert_contains "$(<"$menu_output")" \
  '该 IPv4 未配置在所选网络接口 ens3 上: 198.51.100.12' 'menu wrong-address recovery'
assert_contains "$(<"$menu_output")" '操作未完成；请重试或运行 nobrand doctor' \
  'menu action-failure warning'
assert_not_contains "$(<"$menu_output")" '非交互模式需要' 'menu CLI error isolation'

# Manager-menu mutations use the production configure:ingress lifecycle
# wrapper. A successful add completes its scoped transaction; a failure after
# dispatch begins preserves the exact scope and mutation evidence for recovery.
reset_scoped_ingress_fixture() {
  nb_lifecycle_lock_release_all >/dev/null 2>&1 || true
  rm -rf -- "$NOBRAND_STATE_DIR" "$NOBRAND_CONFIG_DIR" "$NOBRAND_LIB_DIR" \
    "$NOBRAND_LIFECYCLE_DIR"
  rm -f -- "$NOBRAND_LIFECYCLE_LOCK_FILE"
  mkdir -p "$(dirname "$NOBRAND_LIFECYCLE_LOCK_FILE")"
  chmod 0700 "$(dirname "$NOBRAND_LIFECYCLE_LOCK_FILE")"
  export NOBRAND_LIFECYCLE_ACTIVE=0
  export NOBRAND_LIFECYCLE_OPERATION=''
  export NOBRAND_LIFECYCLE_SCOPE=''
  export NOBRAND_LIFECYCLE_MUTATION_STARTED=0
  export NOBRAND_LIFECYCLE_LOCK_HELD=0
  export NOBRAND_MANAGER_SESSION_ACTIVE=1
  unset NOBRAND_TEST_INTERRUPT_CONFIGURE_AT
}

require_root() { return 0; }
admin_lock_acquire() { return 0; }
admin_lock_release() { return 0; }

reset_scoped_ingress_fixture
test_interface_rows='ens3|192.0.2.11|UP|1'
ingress_menu_reset_requests
export INGRESS_ACTION=add
export INGRESS_NAME=LifecycleSuccess
export INGRESS_TYPE=public
export INGRESS_INTERFACE=ens3
export INGRESS_ADDRESS=192.0.2.11
export INGRESS_PORT_POLICY=manual-only
export INGRESS_DISPLAY_PORT_POLICY=follow-actual
export INGRESS_ENFORCEMENT=permissive
export INGRESS_ENABLED=true
export INGRESS_NAME_CLI=1
export INGRESS_TYPE_CLI=1
export INGRESS_INTERFACE_CLI=1
export INGRESS_ADDRESS_CLI=1
export INGRESS_PORT_POLICY_CLI=1
export INGRESS_DISPLAY_PORT_POLICY_CLI=1
export INGRESS_ENFORCEMENT_CLI=1
nobrand_run_ingress_action >"$fixture/lifecycle-success.out" 2>&1 \
  || fail 'manager-session Ingress add did not complete'
nb_lifecycle_tx_valid || fail 'successful Ingress transaction is invalid'
assert_eq configure "$(nb_lifecycle_field OPERATION)" 'successful Ingress lifecycle operation'
assert_eq ingress "$(nb_lifecycle_scope)" 'successful Ingress lifecycle scope'
assert_eq 1 "$(nb_lifecycle_mutation_started)" 'successful Ingress mutation flag'
assert_eq complete "$(nb_lifecycle_field STATUS)" 'successful Ingress lifecycle status'
assert_eq complete "$(nb_lifecycle_field LAST_COMPLETED_PHASE)" 'successful Ingress lifecycle phase'
assert_eq 0 "$NOBRAND_LIFECYCLE_LOCK_HELD" 'successful Ingress lifecycle lock balance'
assert_eq 1 "$(jq '[.profiles[] | select(.name == "LifecycleSuccess")] | length' \
  "$NOBRAND_INGRESS_STATE_FILE")" 'successful Ingress state mutation'

nb_lifecycle_clear
ingress_menu_reset_requests
export INGRESS_ACTION=apply
export INGRESS_PROFILE_SELECTOR=LifecycleSuccess
nb_ingress_apply_profile() {
  warn 'forced post-mutation Ingress failure'
  return 42
}
set +e
( nobrand_run_ingress_action ) >"$fixture/lifecycle-failure.out" 2>&1
lifecycle_failure_rc=$?
set -e
[ "$lifecycle_failure_rc" -ne 0 ] || fail 'failing Ingress mutation unexpectedly succeeded'
assert_contains "$(<"$fixture/lifecycle-failure.out")" 'forced post-mutation Ingress failure' \
  'failing Ingress mutation reason'
nb_lifecycle_tx_valid || fail 'failed Ingress transaction is invalid'
assert_eq configure "$(nb_lifecycle_field OPERATION)" 'failed Ingress lifecycle operation'
assert_eq ingress "$(nb_lifecycle_scope)" 'failed Ingress lifecycle scope'
assert_eq 1 "$(nb_lifecycle_mutation_started)" 'failed Ingress mutation flag'
assert_eq in-progress "$(nb_lifecycle_field STATUS)" 'failed Ingress lifecycle status'
assert_eq prepare "$(nb_lifecycle_field LAST_COMPLETED_PHASE)" 'failed Ingress lifecycle phase'
assert_eq CURRENT_PARTIAL_CONFIGURE "$(nb_classify_installation_state)" \
  'failed Ingress lifecycle classification'
assert_eq 0 "$NOBRAND_LIFECYCLE_LOCK_HELD" 'failed Ingress lifecycle lock balance'

printf 'INGRESS_BLANK_DEFAULT_GATE=PASS\n'
printf 'INGRESS_VALIDATION_GATE=PASS\n'
printf 'INGRESS_PRIVATE_PUBLIC_HINT_GATE=PASS\n'

pass 'Ingress CLI/UI separation, snapshot selection, preflight, and interactive recovery'
