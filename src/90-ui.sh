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
  msg '  0) 返回'
  local choice=""
  read_tty choice "$(t '请选择 [0-8]: ' 'Choose [0-8]: ')" || choice=""
  case "$(printf '%s' "$choice" | tr -d '[:space:]')" in
    1) ACTION=perf ;;
    2) ACTION="profile-config" ;;
    3) ACTION="mtu-config" ;;
    4) ACTION="bbr-config" ;;
    5) ACTION="client-modes-config" ;;
    6) ACTION="traffic-config" ;;
    7) ACTION="low-entropy-config" ;;
    8) ACTION="rate-status" ;;
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
    1) ACTION=user-backup ;;
    2) ACTION="user-restore" ;;
    3) ACTION="user-export" ;;
    4) ACTION="user-import" ;;
    5) ACTION="user-export-clients" ;;
    0) return 2 ;;
    *) warn "$(t '无效选择' 'Invalid choice')"; return 1 ;;
  esac
}

show_advanced_menu() {
  msg ""
  t '【高级设置】' '[Advanced settings]'
  msg '  1) Mieru 版本通道'
  msg '  2) 清理并恢复本项目 tc 规则'
  msg '  3) 帮助 / 全部 CLI 命令'
  msg '  0) 返回'
  local choice=""
  read_tty choice "$(t '请选择 [0-3]: ' 'Choose [0-3]: ')" || choice=""
  case "$(printf '%s' "$choice" | tr -d '[:space:]')" in
    1) ACTION="version-channel" ;;
    2) ACTION="rate-restore" ;;
    3) ACTION=help ;;
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
  t '========== Mieru OneClick ==========' '========== Mieru OneClick =========='
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
  t '快捷命令: 直接输入 mita 打开菜单（不区分大小写）' \
    'Quick command: type mita to open menu (case-insensitive)'
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
    2) ACTION=client-config ;;
    3) ACTION=user-manage ;;
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
