#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/testlib.sh"

fixture="$(mktemp -d)"
trap 'rm -rf -- "$fixture"' EXIT
export NOBRAND_STATE_DIR="$fixture/nobrand-oneclick/state"
export NOBRAND_CONFIG_DIR="$fixture/nobrand-oneclick/config"
export NOBRAND_LIB_DIR="$fixture/nobrand-oneclick/lib"
source_installer
# Use the maintained UI implementation for this focused test even before the
# generated installer is rebuilt by the full suite.
# shellcheck disable=SC1091
source "$TEST_ROOT/src/90-ui.sh"
trap - ERR

action_log="$fixture/actions"
input_index=0
inputs=()
set_inputs() { inputs=("$@"); input_index=0; }
read_tty() {
  local destination="$1"
  [ "$input_index" -lt "${#inputs[@]}" ] || return 1
  printf -v "$destination" '%s' "${inputs[$input_index]}"
  input_index=$((input_index + 1))
}

# Raw status 4 is not proof of a successful global uninstall. An arbitrary
# callback returning it must take the ordinary error path and stay contained
# inside the menu wrapper.
menu_exit_success="${NOBRAND_MENU_EXIT_SUCCESS:-4}"
status_four_error="$fixture/status-four-on-error"
status_four_output="$fixture/status-four.out"
on_error() { : >"$status_four_error"; }
status_four_action() { return "$menu_exit_success"; }
set +e
# The production wrapper is sourced above; a later test intentionally replaces
# it with a lightweight stub after this real-wrapper boundary check.
# shellcheck disable=SC2218
nobrand_menu_run status_four_action >"$status_four_output" 2>&1
status_four_rc=$?
set -e
assert_eq 0 "$status_four_rc" 'raw status-4 containment'
[ -e "$status_four_error" ] || fail 'raw status 4 bypassed the generic ERR handler'
assert_contains "$(<"$status_four_output")" '操作未完成；请重试或运行 nobrand doctor' \
  'raw status-4 failure warning'

# Even the global-uninstall callback name is insufficient without the marker
# written after its terminal postcondition. A raw status 4 must return to the
# manager so another action remains reachable.
unconfirmed_trace="$fixture/unconfirmed-global.trace"
unconfirmed_output="$fixture/unconfirmed-global.out"
: >"$unconfirmed_trace"
set +e
(
  unconfirmed_choices=(16 1 0)
  unconfirmed_choice_index=0
  read_tty() {
    [ "$unconfirmed_choice_index" -lt "${#unconfirmed_choices[@]}" ] \
      || fail 'unconfirmed global uninstall exhausted its menu choices'
    printf -v "$1" '%s' "${unconfirmed_choices[$unconfirmed_choice_index]}"
    unconfirmed_choice_index=$((unconfirmed_choice_index + 1))
  }
  nobrand_print_banner() { printf 'banner\n' >>"$unconfirmed_trace"; }
  menu_pause() { printf 'pause\n' >>"$unconfirmed_trace"; }
  nobrand_uninstall() {
    printf 'unconfirmed-global\n' >>"$unconfirmed_trace"
    return "$menu_exit_success"
  }
  # A marker inherited from an earlier call is not proof for this invocation;
  # nobrand_menu_run must reset it immediately before dispatch.
  # Read dynamically by the real menu wrapper in the callback subprocess.
  # shellcheck disable=SC2034
  NOBRAND_MENU_GLOBAL_UNINSTALL_CONFIRMED=1
  menu_loop() { printf 'post-failure-action\n' >>"$unconfirmed_trace"; }
  nobrand_ssh_confirmation_pending() { return 1; }
  on_error() { printf 'on-error\n' >>"$unconfirmed_trace"; }
  nobrand_menu_loop
) >"$unconfirmed_output" 2>&1
unconfirmed_menu_rc=$?
set -e
assert_eq 0 "$unconfirmed_menu_rc" 'unconfirmed global uninstall parent status'
assert_eq 1 "$(grep -Fc 'unconfirmed-global' "$unconfirmed_trace")" \
  'unconfirmed global uninstall action count'
assert_eq 1 "$(grep -Fc 'post-failure-action' "$unconfirmed_trace")" \
  'manager usability after unconfirmed global uninstall'
assert_eq 1 "$(grep -Fc 'on-error' "$unconfirmed_trace")" \
  'unconfirmed global uninstall error-handler count'
assert_eq 1 "$(grep -Fc 'pause' "$unconfirmed_trace")" \
  'unconfirmed global uninstall failure pause'

# A direct exit bypasses ERR traps. Even if it collides with the wrapper's
# private subprocess status, the absent out-of-band proof must keep the manager
# alive and expose the next action surface.
private_exit_trace="$fixture/private-exit.trace"
private_exit_output="$fixture/private-exit.out"
: >"$private_exit_trace"
set +e
(
  private_exit_choices=(16 1 0)
  private_exit_choice_index=0
  read_tty() {
    [ "$private_exit_choice_index" -lt "${#private_exit_choices[@]}" ] \
      || fail 'private-status collision exhausted its menu choices'
    printf -v "$1" '%s' "${private_exit_choices[$private_exit_choice_index]}"
    private_exit_choice_index=$((private_exit_choice_index + 1))
  }
  nobrand_print_banner() { printf 'banner\n' >>"$private_exit_trace"; }
  menu_pause() { printf 'pause\n' >>"$private_exit_trace"; }
  nobrand_uninstall() {
    printf 'direct-exit-125\n' >>"$private_exit_trace"
    exit 125
  }
  menu_loop() { printf 'post-private-exit-action\n' >>"$private_exit_trace"; }
  nobrand_ssh_confirmation_pending() { return 1; }
  on_error() { printf 'on-error\n' >>"$private_exit_trace"; }
  nobrand_menu_loop
) >"$private_exit_output" 2>&1
private_exit_menu_rc=$?
set -e
assert_eq 0 "$private_exit_menu_rc" 'private-status collision parent status'
assert_eq 1 "$(grep -Fc 'direct-exit-125' "$private_exit_trace")" \
  'private-status collision uninstall action count'
assert_eq 1 "$(grep -Fc 'post-private-exit-action' "$private_exit_trace")" \
  'manager usability after private-status collision'
assert_eq 1 "$(grep -Fc 'pause' "$private_exit_trace")" \
  'private-status collision failure pause'
assert_not_contains "$(<"$private_exit_trace")" 'on-error' \
  'direct exit must not pretend its ERR trap ran'
assert_contains "$(<"$private_exit_output")" '操作未完成；请重试或运行 nobrand doctor' \
  'private-status collision failure warning'

# A successful global uninstall renders the root menu exactly once, does not
# pause, exposes no second action surface, and returns success to its parent.
global_trace="$fixture/global-uninstall.trace"
global_output="$fixture/global-uninstall.out"
: >"$global_trace"
set +e
(
  global_read_count=0
  read_tty() {
    global_read_count=$((global_read_count + 1))
    [ "$global_read_count" -eq 1 ] || fail 'global uninstall rendered a second input surface'
    printf -v "$1" 16
  }
  nobrand_print_banner() { printf 'banner\n' >>"$global_trace"; msg 'NoBrand global uninstall menu'; }
  menu_pause() { printf 'pause\n' >>"$global_trace"; }
  # shellcheck disable=SC2034
  nobrand_uninstall() {
    printf 'global-uninstall\n' >>"$global_trace"
    # Read dynamically by the real menu wrapper after this callback returns.
    NOBRAND_MENU_GLOBAL_UNINSTALL_CONFIRMED=1
    return "$menu_exit_success"
  }
  nobrand_ssh_confirmation_pending() { return 1; }
  on_error() { printf 'on-error\n' >>"$global_trace"; }
  nobrand_menu_loop
) >"$global_output" 2>&1
global_menu_rc=$?
set -e
assert_eq 0 "$global_menu_rc" 'global uninstall parent status'
assert_eq 1 "$(grep -Fc 'banner' "$global_trace")" 'global uninstall menu render count'
assert_eq 1 "$(grep -Fc 'global-uninstall' "$global_trace")" 'global uninstall action count'
assert_not_contains "$(<"$global_trace")" 'pause' 'global uninstall pause suppression'
assert_not_contains "$(<"$global_trace")" 'on-error' 'global uninstall error-handler suppression'
assert_eq 1 "$(grep -Fc '卸载 NoBrand-OneClick（全部协议）' "$global_output")" \
  'global uninstall action-surface count'

# Protocol-only uninstall returns normally. The root menu can render again and
# execute a subsequent manager action before the user exits.
protocol_trace="$fixture/protocol-uninstall.trace"
protocol_output="$fixture/protocol-uninstall.out"
: >"$protocol_trace"
set +e
(
  protocol_choices=(1 10 0)
  protocol_choice_index=0
  read_tty() {
    [ "$protocol_choice_index" -lt "${#protocol_choices[@]}" ] \
      || fail 'protocol uninstall exhausted its menu choices'
    printf -v "$1" '%s' "${protocol_choices[$protocol_choice_index]}"
    protocol_choice_index=$((protocol_choice_index + 1))
  }
  nobrand_print_banner() { printf 'banner\n' >>"$protocol_trace"; msg 'NoBrand protocol uninstall menu'; }
  menu_pause() { printf 'pause\n' >>"$protocol_trace"; }
  protocol_only_uninstall() { printf 'protocol-uninstall\n' >>"$protocol_trace"; return 0; }
  menu_loop() { nobrand_menu_run protocol_only_uninstall; }
  nobrand_nodes() { printf 'post-protocol-action\n' >>"$protocol_trace"; }
  nobrand_ssh_confirmation_pending() { return 1; }
  on_error() { printf 'on-error\n' >>"$protocol_trace"; }
  nobrand_menu_loop
) >"$protocol_output" 2>&1
protocol_menu_rc=$?
set -e
assert_eq 0 "$protocol_menu_rc" 'protocol uninstall parent status'
assert_eq 1 "$(grep -Fc 'protocol-uninstall' "$protocol_trace")" 'protocol uninstall action count'
assert_eq 1 "$(grep -Fc 'post-protocol-action' "$protocol_trace")" \
  'manager usability after protocol uninstall'
assert_eq 3 "$(grep -Fc 'banner' "$protocol_trace")" 'protocol uninstall menu return count'
assert_not_contains "$(<"$protocol_trace")" 'on-error' 'protocol uninstall error-handler suppression'

menu_pause() { :; }
nobrand_print_banner() { msg 'NoBrand test menu'; }
nobrand_menu_run() { "$@"; }
menu_loop() { printf 'top:mieru\n' >>"$action_log"; }
hysteria2_menu_loop() { printf 'top:hy2\n' >>"$action_log"; }
tuic_menu_loop() { printf 'top:tuic\n' >>"$action_log"; }
ssh_tunnel_menu_loop() { printf 'top:ssh\n' >>"$action_log"; }
forward_menu_loop() { printf 'top:forward\n' >>"$action_log"; }
ingress_menu_loop() { printf 'top:ingress\n' >>"$action_log"; }
nobrand_nodes() { printf 'top:nodes\n' >>"$action_log"; }
nobrand_status() { printf 'top:status\n' >>"$action_log"; }
nobrand_doctor() { printf 'top:doctor\n' >>"$action_log"; }
do_perf() { printf 'top:network\n' >>"$action_log"; }
nobrand_usage() { printf 'top:help\n' >>"$action_log"; }
nobrand_uninstall() { printf 'top:uninstall\n' >>"$action_log"; }
nobrand_run_vless_sudoku_action() { printf 'vless:%s\n' "$VLESS_SUDOKU_ACTION" >>"$action_log"; }
nobrand_backup_action() { printf 'backup:%s:%s\n' "$NOBRAND_BACKUP_ACTION" "${NOBRAND_BACKUP_PATH:-}" >>"$action_log"; }

# Exercise the real Snell submenu before replacing it for the top-level
# routing pass. No v6 label or handler may remain, and both QUIC directions
# must be reachable without numbering holes.
nobrand_run_snell_action() {
  printf 'snell:%s:%s:%s\n' "$SNELL_ACTION" "${SNELL_VERSION:-}" "${SNELL_QUIC_PROXY:-}" >>"$action_log"
}
# The real menu function reads this test-selection global indirectly.
# shellcheck disable=SC2034
snell_menu_select_instance() { SNELL_NAME=menu-v5; }
set_inputs invalid '' 1 2 3 4 1 4 2 7 1 7 2 8 0
# Loaded by source_installer; the later definition is the top-level routing stub.
# shellcheck disable=SC2218
snell_menu_loop >"$fixture/snell.out"
snell_output="$(<"$fixture/snell.out")"
assert_contains "$snell_output" '安装 Snell v5 [推荐]' 'Snell v5 menu default'
assert_contains "$snell_output" '安装 Snell v4 [兼容]' 'Snell v4 compatibility menu'
assert_contains "$snell_output" 'QUIC 设置' 'Snell QUIC menu'
assert_not_contains "$snell_output" 'v6' 'Snell v6 menu removed'
grep -qx 'snell:set-quic:4:off' "$action_log" || fail 'Snell menu QUIC OFF handler'
grep -qx 'snell:set-quic:4:on' "$action_log" || fail 'Snell menu QUIC ON handler'
grep -qx 'snell:upgrade:5:on' "$action_log" || fail 'Snell menu v5 upgrade handler'
grep -qx 'snell:upgrade:4:on' "$action_log" || fail 'Snell menu v4 upgrade handler'

set_inputs invalid -1 999 '' 1 2 3 4 5 6 7 8 9 10 11 yes 0
# Loaded by source_installer; the later definition is the top-level routing stub.
# shellcheck disable=SC2218
vless_sudoku_menu_loop >"$fixture/vless.out"
vless_output="$(<"$fixture/vless.out")"
assert_contains "$vless_output" 'VLESS Encryption：未使用（NOT USED）' 'VLESS submenu plain-mode notice'
for action in install show set-endpoint status start stop restart doctor smoke upgrade remove; do
  grep -qx "vless:${action}" "$action_log" || fail "VLESS submenu handler not reached: $action"
done

restore_path="$fixture/backup.tar.gz"
set_inputs invalid -1 999 '' 1 2 3 "$restore_path" 0
# Loaded by source_installer; the later definition is the top-level routing stub.
# shellcheck disable=SC2218
nobrand_backup_menu_loop >"$fixture/backup.out"
grep -qx 'backup:create:' "$action_log" || fail 'backup create menu handler'
grep -qx 'backup:list:' "$action_log" || fail 'backup list menu handler'
grep -qx "backup:restore:${restore_path}" "$action_log" || fail 'backup restore menu handler'

# The top-level routing test replaces only the already-covered nested VLESS
# loop so every top item can be traversed in one deterministic input stream.
vless_sudoku_menu_loop() { printf 'top:vless\n' >>"$action_log"; }
vless_reality_menu_loop() { printf 'top:reality\n' >>"$action_log"; }
nobrand_backup_menu_loop() { printf 'top:backup\n' >>"$action_log"; }
snell_menu_loop() { printf 'top:snell\n' >>"$action_log"; }
set_inputs invalid -1 999 '' 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 0
nobrand_menu_loop >"$fixture/top.out"
top_output="$(<"$fixture/top.out")"
assert_contains "$top_output" 'VLESS REALITY + Vision（TCP；推荐 Public Ingress）' 'top REALITY menu visibility'
assert_contains "$top_output" 'VLESS + FinalMask + Sudoku（TCP）' 'top VLESS menu visibility'
assert_contains "$top_output" 'TUIC v5（官方 sing-box Runtime）' 'top TUIC menu visibility'
assert_contains "$top_output" 'SSH Tunnel（现有 OpenSSH）' 'top SSH Tunnel menu visibility'
assert_contains "$top_output" '端口转发 / Port Forward（nftables / Realm）' 'top Port Forward menu visibility'
assert_contains "$top_output" '网络入口 / Ingress' 'top Ingress menu visibility'
assert_contains "$top_output" '卸载 NoBrand-OneClick（全部协议）' 'top unified uninstall label'
assert_not_contains "$top_output" '保留 Mieru' 'top uninstall must not claim Mieru preservation'
for item in mieru snell hy2 tuic reality vless ssh forward ingress nodes status doctor backup network help uninstall; do
  grep -qx "top:${item}" "$action_log" || fail "top menu handler not reached: $item"
done

# A menu action that arms the SSH rollback watchdog must unwind the root menu,
# allowing the fresh administrator connection to acquire the lifecycle lock.
nobrand_ssh_confirmation_pending() { return 0; }
nobrand_pending_ssh_confirmation_notice() { printf 'pending SSH confirmation\n'; }
set_inputs 7
nobrand_menu_loop >"$fixture/pending-ssh-menu.out"
assert_contains "$(<"$fixture/pending-ssh-menu.out")" 'pending SSH confirmation' \
  'top menu exits for fresh-admin SSH watchdog confirmation'

menu_pause() { : >"$fixture/unified-uninstall-pause"; }
set_inputs 16
nobrand_menu_loop >"$fixture/pending-unified-uninstall-menu.out"
[ ! -e "$fixture/unified-uninstall-pause" ] \
  || fail 'unified uninstall paused while SSH confirmation needed the lifecycle lock'
assert_contains "$(<"$fixture/pending-unified-uninstall-menu.out")" \
  'pending SSH confirmation' 'unified uninstall unwinds for fresh-admin confirmation'

printf 'FULL_UNINSTALL_PROCESS_EXIT_GATE=PASS\n'
printf 'MENU_EXIT_SENTINEL_AUTH_GATE=PASS\n'
printf 'PROTOCOL_ONLY_UNINSTALL_GATE=PASS\n'
pass 'menu-to-handler mapping, invalid/empty input safety, VLESS 1-11, and backup/restore reachability'
