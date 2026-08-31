menu_pause() {
  local _ignore=""
  msg ""
  read_tty _ignore "$(t '按回车返回主菜单...' 'Press Enter to return to the menu...')" || true
}

user_menu_pause() {
  local _ignore=""
  msg ""
  read_tty _ignore "$(t '按回车返回用户管理菜单...' \
    'Press Enter to return to user management...')" || true
}

menu_run_action() {
  if dry_run_should_preview "$ACTION"; then
    dry_run_action_preview "$ACTION"
    return 0
  fi
  case "$ACTION" in
    install) do_install ;;
    reconfigure) do_reconfigure ;;
    upgrade) do_upgrade ;;
    uninstall)
      do_uninstall
      [ "${UNINSTALL_CANCELLED:-0}" -eq 1 ] && return 0
      # do_uninstall 只有在最终残留验收通过后才返回成功。
      return 2
      ;;
    status) do_status ;;
    client-config) do_client_config ;;
    mtu-config) do_mtu_config ;;
    start) do_start ;;
    stop) do_stop ;;
    restart) do_restart ;;
    user-list) do_user_list ;;
    user-add) do_user_add ;;
    user-del) do_user_del ;;
    user-show) do_user_show ;;
    user-manage) do_user_manage ;;
    user-set-endpoint) do_user_set_endpoint ;;
    user-set-quota) do_user_set_quota ;;
    user-set-expire) do_user_set_expire ;;
    user-enable) do_user_enable ;;
    user-disable) do_user_disable ;;
    user-scan) do_user_scan ;;
    user-quota-reset)
      if [ "${YES:-0}" -eq 1 ]; then
        do_user_quota_reset force
      else
        do_user_quota_reset
      fi
      ;;
    user-set-rate) do_user_set_rate ;;
    rate-status) do_rate_status ;;
    rate-restore) do_rate_restore ;;
    user-usage) do_user_usage ;;
    user-export-clients) do_user_export_clients ;;
    user-backup) do_user_backup ;;
    user-restore) do_user_restore ;;
    user-export) do_user_export ;;
    user-import) do_user_import ;;
    doctor) do_doctor ;;
    perf) do_perf ;;
    profile-config) do_profile_config ;;
    client-modes-config) do_tuning_config client-modes ;;
    traffic-config) do_tuning_config traffic ;;
    low-entropy-config) do_tuning_config low-entropy ;;
    bbr-config) do_bbr_config ;;
    version-channel) do_version_channel_config ;;
    help) usage ;;
    *) warn "$(t '未知操作' 'Unknown action')"; return 1 ;;
  esac
}

menu_loop() {
  MENU_MODE=1
  MAIN_MENU_ACTIVE=1
  trap - ERR
  # 仅当已安装(或半装/损坏状态)时才做二进制修复。否则在「全新系统」上，repair_mita_binary_paths
  # 会因找不到二进制而走 recover_deb_mita → reinstall_mita_package，在显示菜单前就「自动重下安装」mita，
  # 随后用户选「1) 新装安装」时便被误判「检测到已安装」。修复必须放进 mita_installed 守卫内（与非交互路径一致）。
  if [ "${DRY_RUN:-0}" -ne 1 ] && mita_installed; then
    repair_mita_binary_paths 2>/dev/null || true
    ensure_management_scripts || true
    MENU_SCRIPTS_READY=1
  fi
  while true; do
    ACTION=""
    # 安全捕获：set -e 下裸调用 show_menu 返回非0(无效输入)会直接退脚本
    local sm_rc=0
    show_menu || sm_rc=$?
    if [ "$sm_rc" -eq 2 ]; then
      break
    fi
    if [ "$sm_rc" -ne 0 ]; then
      continue
    fi
    # 不能把业务函数放在 if/|| 条件上下文中：Bash 会在整个函数调用链内
    # 抑制 errexit。用独立子 shell 作为简单命令执行，父菜单再读取退出码。
    local rc=0
    set +e
    (
      set -Eeuo pipefail
      trap 'rc=$?; if [ "$rc" -eq 2 ] || [ "$rc" -eq 3 ]; then exit "$rc"; fi; on_error' ERR
      menu_run_action
    )
    rc=$?
    set -e
    if [ "$rc" -eq 2 ]; then
      break
    fi
    if [ "$rc" -eq 3 ]; then
      continue
    fi
    if [ "$rc" -ne 0 ]; then
      warn "$(t '操作未完成，请重试或运行 mita doctor 排查' 'Action failed; retry or run mita doctor')"
    fi
    menu_pause
  done
}

show_performance_menu() {
  msg ""
  t '【性能与网络】' '[Performance and network]'
  msg '  1) 性能诊断（只读）'
  msg '  2) 配置预设 Profile'
  msg '  3) MTU'
  msg '  4) BBR / FQ'
  msg '  5) Multiplexing / Handshake'
  msg '  6) Traffic Pattern'
  msg '  7) Low Entropy'
  msg '  8) 带宽限制状态'
  msg '  9) Mieru 版本通道'
  msg ' 10) 清理并恢复本项目 tc 规则'
  msg '  0) 返回'
  local choice=""
  read_tty choice "$(t '请选择 [0-10]: ' 'Choose [0-10]: ')" || choice=""
  case "$(printf '%s' "$choice" | tr -d '[:space:]')" in
    1) ACTION=perf ;;
    2) ACTION="profile-config" ;;
    3) ACTION="mtu-config" ;;
    4) ACTION="bbr-config" ;;
    5) ACTION="client-modes-config" ;;
    6) ACTION="traffic-config" ;;
    7) ACTION="low-entropy-config" ;;
    8) ACTION="rate-status" ;;
    9) ACTION="version-channel" ;;
    10) ACTION="rate-restore" ;;
    0) return 2 ;;
    *) warn "$(t '无效选择' 'Invalid choice')"; return 1 ;;
  esac
}

show_service_menu() {
  msg ""
  t '【服务管理】' '[Service management]'
  msg '  1) 状态'
  msg '  2) 启动'
  msg '  3) 停止'
  msg '  4) 重启'
  msg '  0) 返回'
  local choice=""
  read_tty choice "$(t '请选择 [0-4]: ' 'Choose [0-4]: ')" || choice=""
  case "$(printf '%s' "$choice" | tr -d '[:space:]')" in
    1) ACTION=status ;;
    2) ACTION=start ;;
    3) ACTION=stop ;;
    4) ACTION=restart ;;
    0) return 2 ;;
    *) warn "$(t '无效选择' 'Invalid choice')"; return 1 ;;
  esac
}

show_backup_menu() {
  msg ""
  t '【备份 / 恢复】' '[Backup / restore]'
  msg '  1) 备份用户状态'
  msg '  2) 从备份恢复'
  msg '  3) 导出用户状态 JSON'
  msg '  4) 导入用户状态 JSON'
  msg '  5) 批量导出客户端配置'
  msg '  0) 返回'
  local choice=""
  read_tty choice "$(t '请选择 [0-5]: ' 'Choose [0-5]: ')" || choice=""
  case "$(printf '%s' "$choice" | tr -d '[:space:]')" in
    1) ACTION="user-backup" ;;
    2) ACTION="user-restore" ;;
    3) ACTION="user-export" ;;
    4) ACTION="user-import" ;;
    5) ACTION="user-export-clients" ;;
    0) return 2 ;;
    *) warn "$(t '无效选择' 'Invalid choice')"; return 1 ;;
  esac
}

show_menu() {
  if [ "${DRY_RUN:-0}" -ne 1 ] \
     && [ "${MENU_SCRIPTS_READY:-0}" -eq 0 ] \
     && mita_installed; then
    ensure_management_scripts || true
    MENU_SCRIPTS_READY=1
  fi
  load_install_state 2>/dev/null || true
  local installed="no" users="-" selected_rc=0 profile_text="-" version_text=""
  if mita_installed; then installed="yes"; fi
  if [ "$installed" = yes ]; then
    users="$(users_count 2>/dev/null || echo 0)"
    profile_text="$(profile_label)"
    version_text="$(installed_version 2>/dev/null || printf '-')"
  else
    version_text="$(t '未安装' 'not installed')"
  fi
  msg ''
  t '========== NoBrand-OneClick / Mieru ==========' \
    '========== NoBrand-OneClick / Mieru =========='
  t "作者: ${SCRIPT_AUTHOR} / https://github.com/${SCRIPT_REPO}" \
    "Author: ${SCRIPT_AUTHOR} / https://github.com/${SCRIPT_REPO}"
  t "状态: $([ "$installed" = yes ] && printf '已安装' || printf '未安装')" \
    "Status: $([ "$installed" = yes ] && printf 'installed' || printf 'not installed')"
  t "用户: ${users}" "Users: ${users}"
  t "Profile: ${profile_text}" "Profile: ${profile_text}"
  t "Mieru Version: ${version_text}" "Mieru Version: ${version_text}"
  msg ''
  if [ "$installed" = yes ]; then
    msg '  1) 修复安装'
  else
    msg '  1) 新装 / 安装'
  fi
  msg '  2) 查看节点'
  msg '  3) 用户管理'
  msg '  4) 性能与网络'
  if [ "$installed" = yes ]; then
    msg '  5) 重新配置'
  else
    msg '  5) 重新配置（需先安装）'
  fi
  msg '  6) 服务管理'
  msg '  7) 备份 / 恢复'
  msg '  8) 升级'
  msg '  9) Doctor'
  msg ' 10) 卸载'
  msg '  0) 退出'
  msg ""
  t '快捷命令: nobrand mieru（nb mieru 同义）' \
    'Quick command: nobrand mieru (or nb mieru)'
  msg ""
  local choice=""
  read_tty choice "$(t '请选择 [0-10]: ' 'Choose [0-10]: ')" || choice=""
  choice="$(printf '%s' "$choice" | tr -d '[:space:]')"
  if [ -z "$choice" ]; then
    warn "$(t '请输入 0-10' 'Enter 0-10')"
    return 1
  fi
  case "$choice" in
    1) ACTION=install ;;
    2) ACTION="client-config" ;;
    3) ACTION="user-manage" ;;
    4)
      show_performance_menu || selected_rc=$?
      [ "$selected_rc" -eq 0 ] || return 1
      ;;
    5) ACTION=reconfigure ;;
    6)
      show_service_menu || selected_rc=$?
      [ "$selected_rc" -eq 0 ] || return 1
      ;;
    7)
      show_backup_menu || selected_rc=$?
      [ "$selected_rc" -eq 0 ] || return 1
      ;;
    8) ACTION=upgrade ;;
    9) ACTION=doctor ;;
    10) ACTION=uninstall ;;
    0) return 2 ;;
    *)
      warn "$(t '无效选择，请输入 0-10' 'Invalid choice, enter 0-10')"
      return 1
      ;;
  esac
  return 0
}

# ---------- NoBrand unified interactive presentation ----------

nobrand_menu_run() {
  local rc=0
  set +e
  (
    set -Eeuo pipefail
    trap 'rc=$?; on_error' ERR
    "$@"
  )
  rc=$?
  set -e
  if [ "$rc" -ne 0 ]; then
    warn "$(t '操作未完成；请重试或运行 nobrand doctor' \
      'Action did not complete; retry or run nobrand doctor')"
  fi
  return 0
}

snell_menu_select_instance() {
  local id name major found=0 choice=""
  msg ''
  msg 'Snell 节点:'
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    name="$(snell_state_field "$id" name)"
    major="$(snell_state_field "$id" version)"
    printf '  - %s (v%s, %s)\n' "$name" "$major" "$id"
    found=1
  done < <(snell_instance_ids)
  [ "$found" -eq 1 ] || { warn 'Snell 尚无节点'; return 1; }
  read_tty choice "$(t '输入节点名: ' 'Enter node name: ')" || choice=""
  [ -n "$choice" ] && snell_find_id_by_name "$choice" >/dev/null 2>&1 \
    || { warn '节点名不存在'; return 1; }
  SNELL_NAME="$choice"
}

snell_menu_install_version() {
  local version="$1"
  SNELL_VERSION="$version" SNELL_VERSION_CLI=1 SNELL_NAME="" SNELL_PSK=""
  SNELL_QUIC_PROXY="" SNELL_QUIC_CLI=0
  PORT="" PORT_CLI=0 ADVERTISE_HOST="" ADVERTISE_PORT="" ADVERTISE_CLI=0 ADVERTISE_AUTO_REQUESTED=0
  YES=0 SNELL_ACTION=install
  nobrand_menu_run nobrand_run_snell_action
}

snell_menu_set_quic() {
  local choice=""
  snell_menu_select_instance || return 0
  msg '  1) 关闭 QUIC Proxy Mode [默认 / 推荐兼容]'
  msg '  2) 启用 QUIC Proxy Mode [开放同号 UDP]'
  read_tty choice "$(t '请选择 [1-2]: ' 'Choose [1-2]: ')" || choice=""
  case "$choice" in
    1) SNELL_QUIC_PROXY=off ;;
    2) SNELL_QUIC_PROXY=on ;;
    *) warn '无效选择'; return 0 ;;
  esac
  SNELL_QUIC_CLI=1 YES=0 SNELL_ACTION="set-quic"
  nobrand_menu_run nobrand_run_snell_action
}

snell_menu_service() {
  local choice=""
  snell_menu_select_instance || return 0
  msg '  1) 状态'
  msg '  2) 启动'
  msg '  3) 停止'
  msg '  4) 重启'
  read_tty choice "$(t '请选择 [1-4]: ' 'Choose [1-4]: ')" || choice=""
  case "$choice" in
    1) SNELL_ACTION=status ;;
    2) SNELL_ACTION=start ;;
    3) SNELL_ACTION=stop ;;
    4) SNELL_ACTION=restart ;;
    *) warn '无效选择'; return 0 ;;
  esac
  nobrand_menu_run nobrand_run_snell_action
}

snell_menu_loop() {
  local choice="" confirm=""
  trap - ERR
  while true; do
    msg ''
    msg '========== Snell =========='
    msg '  1) 安装 Snell v5 [推荐]'
    msg '  2) 安装 Snell v4 [兼容]'
    msg '  3) 查看 Snell 节点'
    msg '  4) QUIC 设置'
    msg '  5) 修改 Display Endpoint'
    msg '  6) 服务管理'
    msg '  7) 升级官方 runtime'
    msg '  8) Doctor'
    msg '  9) 删除节点'
    msg '  0) 返回'
    read_tty choice "$(t '请选择 [0-9]: ' 'Choose [0-9]: ')" || choice=""
    case "$choice" in
      1) snell_menu_install_version 5 ;;
      2) snell_menu_install_version 4 ;;
      3) SNELL_NAME=""; SNELL_ACTION=show; nobrand_menu_run nobrand_run_snell_action ;;
      4) snell_menu_set_quic ;;
      5)
        snell_menu_select_instance || continue
        ADVERTISE_CLI=0 ADVERTISE_AUTO_REQUESTED=0 YES=0 SNELL_ACTION="set-endpoint"
        nobrand_menu_run nobrand_run_snell_action
        ;;
      6) snell_menu_service ;;
      7)
        msg '升级版本: 1) v5  2) v4'
        read_tty confirm '请选择 [1-2]: ' || confirm=""
        case "$confirm" in 1) SNELL_VERSION=5 ;; 2) SNELL_VERSION=4 ;; *) warn '无效选择'; continue ;; esac
        SNELL_NAME="" SNELL_ACTION=upgrade
        nobrand_menu_run nobrand_run_snell_action
        ;;
      8) SNELL_ACTION=doctor; nobrand_menu_run nobrand_run_snell_action ;;
      9)
        snell_menu_select_instance || continue
        read_tty confirm "确认删除 ${SNELL_NAME}？输入 yes: " || confirm=""
        [ "$confirm" = yes ] || { warn '已取消'; continue; }
        SNELL_ACTION=remove
        nobrand_menu_run nobrand_run_snell_action
        ;;
      0) return 0 ;;
      *) warn '无效选择' ;;
    esac
    menu_pause
  done
}

hysteria2_menu_loop() {
  local choice="" confirm=""
  trap - ERR
  while true; do
    msg ''
    msg '========== Hysteria2 / Xray-core =========='
    msg '  1) 安装 / 重新部署'
    msg '  2) 查看节点'
    msg '  3) 修改 Display Endpoint'
    msg '  4) 状态'
    msg '  5) 启动'
    msg '  6) 停止'
    msg '  7) 重启'
    msg '  8) 升级 NoBrand 独立 Xray-core'
    msg '  9) Doctor'
    msg ' 10) 删除 Hysteria2'
    msg '  0) 返回'
    read_tty choice "$(t '请选择 [0-10]: ' 'Choose [0-10]: ')" || choice=""
    case "$choice" in
      1)
        PORT="" PORT_CLI=0 HY2_SNI="" ADVERTISE_HOST="" ADVERTISE_PORT=""
        ADVERTISE_CLI=0 ADVERTISE_AUTO_REQUESTED=0 YES=0 HY2_ACTION=install
        nobrand_menu_run nobrand_run_hy2_action
        ;;
      2) HY2_ACTION=show; nobrand_menu_run nobrand_run_hy2_action ;;
      3)
        ADVERTISE_CLI=0 ADVERTISE_AUTO_REQUESTED=0 YES=0 HY2_ACTION=set-endpoint
        nobrand_menu_run nobrand_run_hy2_action
        ;;
      4) HY2_ACTION=status; nobrand_menu_run nobrand_run_hy2_action ;;
      5) HY2_ACTION=start; nobrand_menu_run nobrand_run_hy2_action ;;
      6) HY2_ACTION=stop; nobrand_menu_run nobrand_run_hy2_action ;;
      7) HY2_ACTION=restart; nobrand_menu_run nobrand_run_hy2_action ;;
      8) HY2_ACTION=upgrade; nobrand_menu_run nobrand_run_hy2_action ;;
      9) HY2_ACTION=doctor; nobrand_menu_run nobrand_run_hy2_action ;;
      10)
        read_tty confirm '确认只删除 NoBrand Hysteria2？输入 yes: ' || confirm=""
        [ "$confirm" = yes ] || { warn '已取消'; continue; }
        HY2_ACTION=remove
        nobrand_menu_run nobrand_run_hy2_action
        ;;
      0) return 0 ;;
      *) warn '无效选择' ;;
    esac
    menu_pause
  done
}

vless_sudoku_menu_loop() {
  local choice="" confirm=""
  trap - ERR
  while true; do
    msg ''
    msg '========== Plain VLESS + FinalMask + Sudoku / TCP =========='
    msg 'VLESS Encryption: NOT USED'
    msg '  1) 安装 / 重新配置'
    msg '  2) 查看节点'
    msg '  3) 修改客户端展示入口'
    msg '  4) 状态'
    msg '  5) 启动'
    msg '  6) 停止'
    msg '  7) 重启'
    msg '  8) Doctor'
    msg '  9) Smoke / 配置验证'
    msg ' 10) 升级共享 Xray runtime'
    msg ' 11) 删除'
    msg '  0) 返回'
    read_tty choice "$(t '请选择 [0-11]: ' 'Choose [0-11]: ')" || choice=""
    case "$choice" in
      1)
        PORT="" PORT_CLI=0 VLESS_SUDOKU_UUID="" VLESS_SUDOKU_PASSWORD=""
        ADVERTISE_HOST="" ADVERTISE_PORT="" ADVERTISE_CLI=0 ADVERTISE_AUTO_REQUESTED=0
        YES=0 VLESS_SUDOKU_ACTION=install
        nobrand_menu_run nobrand_run_vless_sudoku_action
        ;;
      2) VLESS_SUDOKU_ACTION=show; nobrand_menu_run nobrand_run_vless_sudoku_action ;;
      3)
        ADVERTISE_HOST="" ADVERTISE_PORT="" ADVERTISE_CLI=0 ADVERTISE_AUTO_REQUESTED=0
        YES=0 VLESS_SUDOKU_ACTION="set-endpoint"
        nobrand_menu_run nobrand_run_vless_sudoku_action
        ;;
      4) VLESS_SUDOKU_ACTION=status; nobrand_menu_run nobrand_run_vless_sudoku_action ;;
      5) VLESS_SUDOKU_ACTION=start; nobrand_menu_run nobrand_run_vless_sudoku_action ;;
      6) VLESS_SUDOKU_ACTION=stop; nobrand_menu_run nobrand_run_vless_sudoku_action ;;
      7) VLESS_SUDOKU_ACTION=restart; nobrand_menu_run nobrand_run_vless_sudoku_action ;;
      8) VLESS_SUDOKU_ACTION=doctor; nobrand_menu_run nobrand_run_vless_sudoku_action ;;
      9) VLESS_SUDOKU_ACTION=smoke; nobrand_menu_run nobrand_run_vless_sudoku_action ;;
      10) VLESS_SUDOKU_ACTION=upgrade; nobrand_menu_run nobrand_run_vless_sudoku_action ;;
      11)
        read_tty confirm '确认只删除 NoBrand VLESS Sudoku？输入 yes: ' || confirm=""
        [ "$confirm" = yes ] || { warn '已取消'; continue; }
        VLESS_SUDOKU_ACTION=remove
        nobrand_menu_run nobrand_run_vless_sudoku_action
        ;;
      0) return 0 ;;
      *) warn '无效选择' ;;
    esac
    menu_pause
  done
}

tuic_menu_select_instance() {
  local id name choice="" found=0
  while IFS= read -r id; do
    name="$(tuic_state_field "$id" name)"
    printf '  - %s (%s)\n' "$name" "$id"
    found=1
  done < <(tuic_instance_ids)
  [ "$found" -eq 1 ] || { warn 'TUIC 尚无 instance'; return 1; }
  read_tty choice '输入 TUIC instance name: ' || choice=""
  tuic_find_id_by_name "$choice" >/dev/null 2>&1 || { warn 'TUIC instance 不存在'; return 1; }
  TUIC_NAME="$choice"
}

tuic_menu_loop() {
  local choice="" user="" confirm=""
  trap - ERR
  while true; do
    msg ''
    msg '========== TUIC v5 / official sing-box =========='
    msg '  1) 安装 TUIC v5 instance'
    msg '  2) 查看 / 导出用户节点'
    msg '  3) 用户管理（add/delete/list/rotate）'
    msg '  4) 修改 Display Endpoint'
    msg '  5) 状态'
    msg '  6) 启动'
    msg '  7) 停止'
    msg '  8) 重启'
    msg '  9) 升级 official sing-box runtime'
    msg ' 10) Doctor'
    msg ' 11) 卸载 instance'
    msg '  0) 返回'
    read_tty choice '请选择 [0-11]: ' || choice=""
    case "$choice" in
      1)
        read_tty TUIC_NAME 'Instance name [primary]: ' || TUIC_NAME=""
        TUIC_NAME="${TUIC_NAME:-primary}"
        read_tty TUIC_USER 'First user [default]: ' || TUIC_USER=""
        TUIC_USER="${TUIC_USER:-default}"
        PORT="" ADVERTISE_HOST="" ADVERTISE_PORT="" ADVERTISE_CLI=0 ADVERTISE_AUTO_REQUESTED=0
        TUIC_SNI="" TUIC_CHANNEL=stable TUIC_VERSION="" YES=0 TUIC_ACTION=install
        nobrand_menu_run nobrand_run_tuic_action
        ;;
      2)
        tuic_menu_select_instance || continue
        read_tty TUIC_USER 'User name（唯一 user 可留空）: ' || TUIC_USER=""
        TUIC_ACTION="export"; nobrand_menu_run nobrand_run_tuic_action
        ;;
      3)
        tuic_menu_select_instance || continue
        msg '  1) list  2) add  3) delete  4) rotate UUID+password'
        read_tty confirm '请选择 [1-4]: ' || confirm=""
        case "$confirm" in
          1) TUIC_ACTION="user-list" ;;
          2) read_tty user 'New user name: ' || user=""; TUIC_USER="$user"; TUIC_ACTION="user-add" ;;
          3) read_tty user 'Delete user name: ' || user=""; TUIC_USER="$user"; TUIC_ACTION="user-delete" ;;
          4) read_tty user 'Rotate user name: ' || user=""; TUIC_USER="$user"; TUIC_ACTION="user-rotate" ;;
          *) warn '无效选择'; continue ;;
        esac
        nobrand_menu_run nobrand_run_tuic_action
        ;;
      4)
        tuic_menu_select_instance || continue
        ADVERTISE_HOST="" ADVERTISE_PORT="" ADVERTISE_CLI=0 ADVERTISE_AUTO_REQUESTED=0
        nb_collect_advertise_endpoint_interactive 'TUIC v5' "$(tuic_state_field "$(tuic_find_id_by_name "$TUIC_NAME")" listen_port)"
        TUIC_ACTION="set-endpoint"; nobrand_menu_run nobrand_run_tuic_action
        ;;
      5|6|7|8)
        tuic_menu_select_instance || continue
        case "$choice" in 5) TUIC_ACTION=status ;; 6) TUIC_ACTION=start ;; 7) TUIC_ACTION=stop ;; 8) TUIC_ACTION=restart ;; esac
        nobrand_menu_run nobrand_run_tuic_action
        ;;
      9) TUIC_CHANNEL=stable TUIC_VERSION="" TUIC_ACTION="upgrade-runtime"; nobrand_menu_run nobrand_run_tuic_action ;;
      10) TUIC_ACTION=doctor; nobrand_menu_run nobrand_run_tuic_action ;;
      11)
        tuic_menu_select_instance || continue
        read_tty confirm "确认卸载 ${TUIC_NAME}？输入 yes: " || confirm=""
        [ "$confirm" = yes ] || { warn '已取消'; continue; }
        TUIC_ACTION=uninstall; nobrand_menu_run nobrand_run_tuic_action
        ;;
      0) return 0 ;;
      *) warn '无效选择' ;;
    esac
    menu_pause
  done
}

ssh_tunnel_menu_loop() {
  local choice="" user="" confirm=""
  trap - ERR
  while true; do
    msg ''
    msg '========== SSH Tunnel / existing OpenSSH =========='
    msg 'TCP forwarding: -L / -D / -R; no shell/exec/TTY/SFTP/SCP; GatewayPorts=no'
    msg '  1) 安装 SSH Tunnel policy + first user'
    msg '  2) 查看用户'
    msg '  3) 显式导出用户 private key/命令'
    msg '  4) 用户管理（add/delete/list/rotate-key）'
    msg '  5) 修改 Display Endpoint'
    msg '  6) 状态'
    msg '  7) Doctor'
    msg '  8) 卸载 SSH Tunnel'
    msg '  0) 返回'
    read_tty choice '请选择 [0-8]: ' || choice=""
    case "$choice" in
      1)
        read_tty SSH_TUNNEL_USER 'First tunnel user [default]: ' || SSH_TUNNEL_USER=""
        SSH_TUNNEL_USER="${SSH_TUNNEL_USER:-default}"
        ADVERTISE_HOST="" ADVERTISE_PORT="" ADVERTISE_CLI=0 ADVERTISE_AUTO_REQUESTED=0 YES=0
        SSH_TUNNEL_ACTION=install; nobrand_menu_run nobrand_run_ssh_tunnel_action
        ;;
      2|3)
        read_tty user 'Tunnel user label（唯一 user 可留空）: ' || user=""
        SSH_TUNNEL_USER="$user"
        if [ "$choice" = 2 ]; then
          SSH_TUNNEL_ACTION="show"
        else
          SSH_TUNNEL_ACTION="export"
        fi
        nobrand_menu_run nobrand_run_ssh_tunnel_action
        ;;
      4)
        msg '  1) list  2) add  3) delete  4) rotate-key'
        read_tty confirm '请选择 [1-4]: ' || confirm=""
        case "$confirm" in
          1) SSH_TUNNEL_ACTION="user-list" ;;
          2) read_tty user 'New tunnel user label: ' || user=""; SSH_TUNNEL_USER="$user"; SSH_TUNNEL_ACTION="user-add" ;;
          3) read_tty user 'Delete tunnel user label: ' || user=""; SSH_TUNNEL_USER="$user"; SSH_TUNNEL_ACTION="user-delete" ;;
          4) read_tty user 'Rotate tunnel user label: ' || user=""; SSH_TUNNEL_USER="$user"; SSH_TUNNEL_ACTION="user-rotate-key" ;;
          *) warn '无效选择'; continue ;;
        esac
        nobrand_menu_run nobrand_run_ssh_tunnel_action
        ;;
      5)
        nb_collect_advertise_endpoint_interactive 'SSH Tunnel' "$(ssh_tunnel_state_field advertise_port)"
        SSH_TUNNEL_ACTION="set-endpoint"; nobrand_menu_run nobrand_run_ssh_tunnel_action
        ;;
      6) SSH_TUNNEL_ACTION=status; nobrand_menu_run nobrand_run_ssh_tunnel_action ;;
      7) SSH_TUNNEL_ACTION=doctor; nobrand_menu_run nobrand_run_ssh_tunnel_action ;;
      8)
        read_tty confirm '确认卸载 SSH Tunnel？输入 yes: ' || confirm=""
        [ "$confirm" = yes ] || { warn '已取消'; continue; }
        SSH_TUNNEL_ACTION=uninstall; nobrand_menu_run nobrand_run_ssh_tunnel_action
        ;;
      0) return 0 ;;
      *) warn '无效选择' ;;
    esac
    menu_pause
  done
}

forward_menu_reset_requests() {
  FORWARD_RULE_ID="" FORWARD_NAME="" FORWARD_NOTE="" FORWARD_BACKEND="" FORWARD_PROTOCOL=""
  FORWARD_LISTEN_HOST="" FORWARD_LISTEN_PORT="" FORWARD_TARGET_HOST="" FORWARD_TARGET_PORT=""
  FORWARD_SOURCE_MODE=masquerade FORWARD_SOURCE_MODE_CLI=0 FORWARD_ADVANCED_CLI=0
  FORWARD_THROUGH="" FORWARD_INTERFACE="" FORWARD_LISTEN_INTERFACE=""
  FORWARD_TCP_TIMEOUT=5 FORWARD_UDP_TIMEOUT=30 FORWARD_PROXY_SEND=false FORWARD_PROXY_ACCEPT=false
  FORWARD_PROXY_VERSION=2 FORWARD_PROXY_ACCEPT_TIMEOUT=5 FORWARD_DNS_MODE=system
  FORWARD_DNS_PROTOCOL=tcp_and_udp FORWARD_DNS_NAMESERVERS="" FORWARD_LISTEN_TRANSPORT=""
  FORWARD_REMOTE_TRANSPORT="" FORWARD_EXTRA_TARGETS="" FORWARD_BALANCE=off FORWARD_WEIGHTS=""
  ADVERTISE_HOST="" ADVERTISE_PORT="" ADVERTISE_CLI=0 ADVERTISE_AUTO_REQUESTED=0 YES=0
}

forward_menu_select_rule() {
  local selector=""
  forward_list_rules
  read_tty selector '输入 rule ID 或 name: ' || selector=""
  [ -n "$selector" ] && forward_resolve_rule_id "$selector" >/dev/null 2>&1 \
    || { warn 'Forward rule 不存在'; return 1; }
  FORWARD_RULE_ID="$selector"
}

forward_menu_collect_add() {
  local choice="" advanced=""
  forward_menu_reset_requests
  read_tty FORWARD_NAME 'Rule name: ' || FORWARD_NAME=""
  [ -n "$FORWARD_NAME" ] || { warn 'Rule name 不能为空'; return 1; }
  msg 'Backend: 1) nftables — Kernel NAT [simple IP forwarding]'
  msg '         2) Realm — Userspace Relay [domain / advanced forwarding]'
  read_tty choice '请选择 [1-2]: ' || choice=""
  case "$choice" in 1) FORWARD_BACKEND=nftables ;; 2) FORWARD_BACKEND=realm ;; *) warn '无效 backend'; return 1 ;; esac
  msg 'Protocol: 1) TCP  2) UDP  3) TCP + UDP'
  read_tty choice '请选择 [1-3]: ' || choice=""
  case "$choice" in 1) FORWARD_PROTOCOL=tcp ;; 2) FORWARD_PROTOCOL=udp ;; 3) FORWARD_PROTOCOL=both ;; *) warn '无效 protocol'; return 1 ;; esac
  read_tty FORWARD_LISTEN_HOST 'Listen address [0.0.0.0]: ' || FORWARD_LISTEN_HOST=""
  FORWARD_LISTEN_HOST="${FORWARD_LISTEN_HOST:-0.0.0.0}"
  read_tty FORWARD_LISTEN_PORT 'Listen port: ' || FORWARD_LISTEN_PORT=""
  read_tty FORWARD_TARGET_HOST 'Target host: ' || FORWARD_TARGET_HOST=""
  read_tty FORWARD_TARGET_PORT 'Target port: ' || FORWARD_TARGET_PORT=""
  read_tty FORWARD_NOTE 'Note [optional]: ' || FORWARD_NOTE=""
  if [ "$FORWARD_BACKEND" = nftables ]; then
    msg 'Source mode: 1) MASQUERADE [default]  2) Preserve Source [advanced; target needs return route]'
    read_tty choice '请选择 [1-2，默认 1]: ' || choice=""
    case "${choice:-1}" in
      1) FORWARD_SOURCE_MODE=masquerade ;;
      2)
        FORWARD_SOURCE_MODE=preserve
        warn 'Preserve Source 不做 SNAT；目标服务器必须经本转发机正确回程，否则连接会失败。'
        ;;
      *) warn '无效 source mode'; return 1 ;;
    esac
  else
    read_tty advanced '配置 Realm advanced options？[y/N]: ' || advanced=""
    case "$advanced" in
      y|Y|yes|YES)
        FORWARD_ADVANCED_CLI=1
        read_tty FORWARD_THROUGH 'Outgoing IP / through [empty=system]: ' || FORWARD_THROUGH=""
        read_tty FORWARD_INTERFACE 'Outgoing interface [empty=system]: ' || FORWARD_INTERFACE=""
        read_tty FORWARD_LISTEN_INTERFACE 'Listen interface [empty=system]: ' || FORWARD_LISTEN_INTERFACE=""
        read_tty FORWARD_DNS_NAMESERVERS 'DNS nameservers, comma-separated [empty=system]: ' || FORWARD_DNS_NAMESERVERS=""
        if [ -n "$FORWARD_DNS_NAMESERVERS" ]; then FORWARD_DNS_MODE=ipv4_and_ipv6; fi
        read_tty FORWARD_EXTRA_TARGETS 'Extra targets host:port, comma-separated [empty=none]: ' || FORWARD_EXTRA_TARGETS=""
        if [ -n "$FORWARD_EXTRA_TARGETS" ]; then
          read_tty FORWARD_BALANCE 'Balance [roundrobin/iphash]: ' || FORWARD_BALANCE=""
          read_tty FORWARD_WEIGHTS 'Weights including primary, comma-separated: ' || FORWARD_WEIGHTS=""
        fi
        ;;
    esac
  fi
  nb_collect_advertise_endpoint_interactive 'Port Forward' "$FORWARD_LISTEN_PORT"
}

forward_menu_loop() {
  local choice="" confirm="" backend_choice="" path=""
  trap - ERR
  while true; do
    msg ''
    msg '========== Port Forward / nftables + Realm =========='
    msg '  1) Add rule'
    msg '  2) List rules'
    msg '  3) Show rule'
    msg '  4) Modify rule'
    msg '  5) Switch backend'
    msg '  6) Enable rule'
    msg '  7) Disable rule'
    msg '  8) Set Display Endpoint'
    msg '  9) Delete rule'
    msg ' 10) Doctor'
    msg ' 11) Export JSON'
    msg ' 12) Import JSON'
    msg ' 13) Upgrade official Realm runtime'
    msg '  0) 返回'
    read_tty choice '请选择 [0-13]: ' || choice=""
    case "$choice" in
      1)
        forward_menu_collect_add || continue
        FORWARD_ACTION=add; nobrand_menu_run nobrand_run_forward_action
        ;;
      2) FORWARD_ACTION=list; nobrand_menu_run nobrand_run_forward_action ;;
      3) forward_menu_reset_requests; forward_menu_select_rule || continue; FORWARD_ACTION=show; nobrand_menu_run nobrand_run_forward_action ;;
      4)
        forward_menu_reset_requests; forward_menu_select_rule || continue
        read_tty FORWARD_TARGET_HOST 'New target host [empty=unchanged]: ' || FORWARD_TARGET_HOST=""
        read_tty FORWARD_TARGET_PORT 'New target port [empty=unchanged]: ' || FORWARD_TARGET_PORT=""
        FORWARD_ACTION=modify; nobrand_menu_run nobrand_run_forward_action
        ;;
      5)
        forward_menu_reset_requests; forward_menu_select_rule || continue
        msg 'New backend: 1) nftables  2) Realm'
        read_tty backend_choice '请选择 [1-2]: ' || backend_choice=""
        case "$backend_choice" in 1) FORWARD_BACKEND=nftables ;; 2) FORWARD_BACKEND=realm ;; *) warn '无效 backend'; continue ;; esac
        if [ "$FORWARD_BACKEND" = nftables ]; then
          read_tty FORWARD_TARGET_HOST 'nftables IPv4 target（domain rule 必须明确填写）[empty=keep if IPv4]: ' || FORWARD_TARGET_HOST=""
        fi
        FORWARD_ACTION=switch-backend; nobrand_menu_run nobrand_run_forward_action
        ;;
      6|7)
        forward_menu_reset_requests; forward_menu_select_rule || continue
        [ "$choice" = 6 ] && FORWARD_ACTION=enable || FORWARD_ACTION=disable
        nobrand_menu_run nobrand_run_forward_action
        ;;
      8)
        forward_menu_reset_requests; forward_menu_select_rule || continue
        nb_collect_advertise_endpoint_interactive 'Port Forward' \
          "$(jq -r --arg id "$(forward_resolve_rule_id "$FORWARD_RULE_ID")" '.rules[]|select(.rule_id==$id)|.listen_port' "$NOBRAND_FORWARD_STATE_FILE")"
        FORWARD_ACTION=set-endpoint; nobrand_menu_run nobrand_run_forward_action
        ;;
      9)
        forward_menu_reset_requests; forward_menu_select_rule || continue
        read_tty confirm '确认删除此 Forward rule？输入 yes: ' || confirm=""
        [ "$confirm" = yes ] || { warn '已取消'; continue; }
        FORWARD_ACTION=delete; nobrand_menu_run nobrand_run_forward_action
        ;;
      10) FORWARD_ACTION=doctor; nobrand_menu_run nobrand_run_forward_action ;;
      11)
        read_tty path 'Export path [empty=stdout]: ' || path=""
        FORWARD_EXPORT_FILE="$path" FORWARD_ACTION=export; nobrand_menu_run nobrand_run_forward_action
        ;;
      12)
        read_tty path 'Import JSON path: ' || path=""
        [ -n "$path" ] || { warn '路径不能为空'; continue; }
        FORWARD_IMPORT_FILE="$path" FORWARD_ACTION=import; nobrand_menu_run nobrand_run_forward_action
        ;;
      13) FORWARD_ACTION=upgrade-runtime; nobrand_menu_run nobrand_run_forward_action ;;
      0) return 0 ;;
      *) warn '无效选择' ;;
    esac
    menu_pause
  done
}

nobrand_backup_menu_loop() {
  local choice="" path=""
  trap - ERR
  while true; do
    msg ''
    msg '========== NoBrand 备份 / 恢复 =========='
    msg '  1) 创建备份'
    msg '  2) 列出备份'
    msg '  3) 从备份恢复'
    msg '  0) 返回'
    read_tty choice "$(t '请选择 [0-3]: ' 'Choose [0-3]: ')" || choice=""
    case "$choice" in
      1)
        NOBRAND_BACKUP_ACTION=create NOBRAND_BACKUP_PATH=""
        nobrand_menu_run nobrand_backup_action
        ;;
      2)
        NOBRAND_BACKUP_ACTION=list NOBRAND_BACKUP_PATH=""
        nobrand_menu_run nobrand_backup_action
        ;;
      3)
        read_tty path "$(t '备份文件绝对路径: ' 'Absolute backup path: ')" || path=""
        [ -n "$path" ] || { warn '备份路径不能为空'; continue; }
        NOBRAND_BACKUP_ACTION=restore NOBRAND_BACKUP_PATH="$path"
        nobrand_menu_run nobrand_backup_action
        ;;
      0) return 0 ;;
      *) warn '无效选择' ;;
    esac
    menu_pause
  done
}

nobrand_menu_loop() {
  local choice=""
  MENU_MODE=1
  trap - ERR
  while true; do
    nobrand_print_banner
    msg ''
    msg '  1) Mieru'
    msg '  2) Snell v4 / v5'
    msg '  3) Hysteria2 (Xray-core)'
    msg '  4) TUIC v5 (official sing-box)'
    msg '  5) VLESS + FinalMask + Sudoku (TCP)'
    msg '  6) SSH Tunnel (existing OpenSSH)'
    msg '  7) Port Forward (nftables / Realm)'
    msg '  8) 查看全部节点'
    msg '  9) 综合状态'
    msg ' 10) Doctor'
    msg ' 11) 备份 / 恢复'
    msg ' 12) 性能 / BBR / FQ（Mieru 公共网络工具）'
    msg ' 13) 帮助 / CLI'
    msg ' 14) 卸载 NoBrand-OneClick（全部协议）'
    msg '  0) 退出'
    read_tty choice "$(t '请选择 [0-14]: ' 'Choose [0-14]: ')" || choice=""
    case "$choice" in
      1) menu_loop ;;
      2) snell_menu_loop ;;
      3) hysteria2_menu_loop ;;
      4) tuic_menu_loop ;;
      5) vless_sudoku_menu_loop ;;
      6) ssh_tunnel_menu_loop ;;
      7) forward_menu_loop ;;
      8) NOBRAND_PROTOCOL_FILTER=""; nobrand_menu_run nobrand_nodes; menu_pause ;;
      9) nobrand_menu_run nobrand_status; menu_pause ;;
      10) nobrand_menu_run nobrand_doctor; menu_pause ;;
      11) nobrand_backup_menu_loop ;;
      12) nobrand_menu_run do_perf; menu_pause ;;
      13) nobrand_usage; menu_pause ;;
      14) YES=0; nobrand_menu_run nobrand_uninstall; menu_pause ;;
      0) return 0 ;;
      *) warn '无效选择' ;;
    esac
  done
}
