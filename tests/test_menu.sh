#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/testlib.sh"

fixture="$(mktemp -d)"
trap 'rm -rf -- "$fixture"' EXIT
export NOBRAND_STATE_DIR="$fixture/nobrand-oneclick/state"
export NOBRAND_CONFIG_DIR="$fixture/nobrand-oneclick/config"
export NOBRAND_LIB_DIR="$fixture/nobrand-oneclick/lib"
source_installer

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

pass 'menu-to-handler mapping, invalid/empty input safety, VLESS 1-11, and backup/restore reachability'
