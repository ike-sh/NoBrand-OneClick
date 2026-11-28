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
  unconfirmed_choices=(18 1 0)
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
  private_exit_choices=(18 1 0)
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
    printf -v "$1" 18
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
assert_eq 1 "$(grep -Fc '卸载 NoBrand-OneClick' "$global_output")" \
  'global uninstall action-surface count'

# Protocol-only uninstall returns normally. The root menu can render again and
# execute a subsequent manager action before the user exits.
protocol_trace="$fixture/protocol-uninstall.trace"
protocol_output="$fixture/protocol-uninstall.out"
: >"$protocol_trace"
set +e
(
  protocol_choices=(1 12 0)
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
# routing pass. All three wire versions must be reachable without enabling QUIC Proxy.
nobrand_run_snell_action() {
  printf 'snell:%s:%s:%s\n' "$SNELL_ACTION" "${SNELL_VERSION:-}" "${SNELL_QUIC_PROXY:-}" >>"$action_log"
}
# The real menu function reads this test-selection global indirectly.
# shellcheck disable=SC2034
snell_menu_select_instance() { SNELL_NAME=menu-v5; }
set_inputs 1 2 3 4 5 9 0
# Loaded by source_installer; the later definition is the routing stub.
# shellcheck disable=SC2218
snell_menu_loop >"$fixture/snell.out"
snell_output="$(<"$fixture/snell.out")"
for version in 6 5 4; do
  assert_contains "$snell_output" "安装 Snell v$version" 'Snell install label'
  grep -qx "snell:install:$version:" "$action_log" || fail "missing Snell v$version install route"
done
assert_contains "$snell_output" 'QUIC 支持范围' 'Snell native capability label'
assert_contains "$snell_output" 'QUIC Proxy Mode' 'Snell unsupported QUIC explanation'
assert_not_contains "$snell_output" '启用 QUIC Proxy Mode' 'no unsupported QUIC enable action'

# Exercise item 11 with production selection and port prompts. The runtime
# boundary is stubbed; specifically require the selected ID, not the label.
(
  d="$NOBRAND_STATE_DIR/splicore/generations/ui"
  mkdir -p "$d"; ln -s generations/ui "$NOBRAND_STATE_DIR/splicore/current"
  jq -n '{nodes:[range(4;7) as $v | {id:("id"+($v|tostring)),name:("v"+($v|tostring)),protocol:"snell",version:$v,transport:"tcp",listener:{host:"127.0.0.1",port:51001},display_endpoint:{host:"edge.example",port:51001},display_port_policy:"follow-actual"}]}' >"$fixture/snell-status.json"
  jq '{nodes:[.nodes[]|{id,client:{name:.name}}]}' "$fixture/snell-status.json" >"$d/desired.json"
  snell_menu_select_instance() { nb_splicore_menu_select snell; }
  nb_splicore_call() { cat "$fixture/snell-status.json"; }
  nb_splicore_protocol() { printf '%s|%s|%s|%s\n' "$1" "$2" "$3" "$PORT" >>"$fixture/snell-port.log"; }
  for language in 1 0; do
    LANG_ZH="$language"; set_inputs 11 v6 65536 11 v4 51004 11 v5 51005 11 v6 51006 0
    snell_menu_loop >"$fixture/snell-port-${language}.out"
  done
)
expected_port_trace=$'snell|set-port|id4|51004\nsnell|set-port|id5|51005\nsnell|set-port|id6|51006'
assert_eq "$(printf '%s\n' "$expected_port_trace" "$expected_port_trace")" "$(<"$fixture/snell-port.log")" 'item 11 dispatches by ID after a valid port'
assert_eq 1 "$(grep -cF 'Auxiliary same-port UDP socket; no UDP firewall opening' "$fixture/snell-port-0.out")" 'v5 alone reports a local auxiliary UDP reservation'
assert_contains "$(<"$fixture/snell-port-1.out")" ' 11) 修改真实监听端口' 'Snell item 11 Chinese label'
assert_contains "$(<"$fixture/snell-port-0.out")" ' 11) Change real listen port' 'Snell item 11 English label'
assert_contains "$(<"$fixture/snell-port-0.out")" '127.0.0.1:51001 /TCP · Display endpoint edge.example:51001 (Port follows listener)' 'Snell old listener and display policy'

set_inputs invalid -1 999 '' 1 2 3 4 5 6 7 8 9 10 11 yes 0
# Loaded by source_installer; the later definition is the top-level routing stub.
# shellcheck disable=SC2218
vless_sudoku_menu_loop >"$fixture/vless.out"
vless_output="$(<"$fixture/vless.out")"
assert_contains "$vless_output" '新建默认 VLESS Encryption：mlkem768 + random + 1rtt' 'VLESS submenu encryption default notice'
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
socks5_menu_loop() { printf 'top:socks5\n' >>"$action_log"; }
ss2022_menu_loop() { printf 'top:ss2022\n' >>"$action_log"; }
zh_labels=(Mieru 'Snell v4 / v5 / v6' 'Hysteria2 + Salamander' 'TUIC v5' 'VLESS REALITY + Vision'
  'VLESS + FinalMask + Sudoku' 'SOCKS5 代理' 'Shadowsocks 2022' 'SSH Tunnel' '端口转发 / Port Forward'
  '网络入口 / Ingress' '查看全部节点' '综合状态' 'Doctor / 诊断' '备份 / 恢复' '性能 / BBR / FQ' '帮助 / CLI' '卸载 NoBrand-OneClick' '退出')
en_labels=(Mieru 'Snell v4 / v5 / v6' 'Hysteria2 + Salamander' 'TUIC v5' 'VLESS REALITY + Vision'
  'VLESS + FinalMask + Sudoku' 'SOCKS5 proxy' 'Shadowsocks 2022' 'SSH Tunnel' 'Port Forward'
  Ingress 'List all nodes' Status 'Doctor / Diagnostics' 'Backup / Restore' 'Performance / BBR / FQ' 'Help / CLI' 'Uninstall NoBrand-OneClick' Exit)
routes=(mieru snell hy2 tuic reality vless socks5 ss2022 ssh forward ingress nodes status doctor backup network help uninstall)
for language in zh en; do
  if [ "$language" = zh ]; then LANG_ZH=1; labels=("${zh_labels[@]}"); else LANG_ZH=0; labels=("${en_labels[@]}"); fi
  # Assert the complete rendered table in order, not just presence of strings.
  set_inputs 0; nobrand_menu_loop >"$fixture/top.out"
  expected="$(for n in {1..18}; do printf ' %2d) %s\n' "$n" "${labels[n-1]}"; done; printf '  0) %s\n' "${labels[18]}")"
  assert_eq "$expected" "$(grep -E '^[[:space:]]*[0-9]+[)]' "$fixture/top.out")" "top menu $language labels and numbers"
  # Record the exact callback for each keystroke including invalid values.
  : >"$action_log"; set_inputs invalid -1 19 '' {1..18} 0; nobrand_menu_loop >/dev/null
  assert_eq "$(printf 'top:%s\n' "${routes[@]}")" "$(<"$action_log")" "top menu $language actual handler order"
done
# Consumed by the sourced menu translations below.
# shellcheck disable=SC2034
LANG_ZH=1

# A menu action that arms the SSH rollback watchdog must unwind the root menu,
# allowing the fresh administrator connection to acquire the lifecycle lock.
nobrand_ssh_confirmation_pending() { return 0; }
nobrand_pending_ssh_confirmation_notice() { printf 'pending SSH confirmation\n'; }
set_inputs 9
nobrand_menu_loop >"$fixture/pending-ssh-menu.out"
assert_contains "$(<"$fixture/pending-ssh-menu.out")" 'pending SSH confirmation' \
  'top menu exits for fresh-admin SSH watchdog confirmation'

menu_pause() { : >"$fixture/unified-uninstall-pause"; }
set_inputs 18
nobrand_menu_loop >"$fixture/pending-unified-uninstall-menu.out"
[ ! -e "$fixture/unified-uninstall-pause" ] \
  || fail 'unified uninstall paused while SSH confirmation needed the lifecycle lock'
assert_contains "$(<"$fixture/pending-unified-uninstall-menu.out")" \
  'pending SSH confirmation' 'unified uninstall unwinds for fresh-admin confirmation'

printf 'FULL_UNINSTALL_PROCESS_EXIT_GATE=PASS\n'
printf 'MENU_EXIT_SENTINEL_AUTH_GATE=PASS\n'
printf 'PROTOCOL_ONLY_UNINSTALL_GATE=PASS\n'
pass 'menu-to-handler mapping, invalid/empty input safety, VLESS 1-11, and backup/restore reachability'
