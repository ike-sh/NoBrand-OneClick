nobrand_ssh_confirmation_pending() {
  local token=""
  declare -F ssh_tunnel_state_exists >/dev/null 2>&1 || return 1
  ssh_tunnel_state_exists 2>/dev/null || return 1
  token="$(ssh_tunnel_state_field pending_watchdog_token 2>/dev/null || true)"
  [ -n "$token" ] && [ "$token" != disabled ]
}

nobrand_pending_ssh_confirmation_notice() {
  local token
  token="$(ssh_tunnel_state_field pending_watchdog_token 2>/dev/null || true)"
  [ -n "$token" ] && [ "$token" != disabled ] || return 1
  t 'SSH 策略正在等待全新管理员连接确认；当前管理菜单将退出以释放生命周期锁。请从全新连接运行：' \
    'SSH policy is awaiting confirmation from a fresh administrator connection. This menu will exit to release the lifecycle lock. Run from the fresh connection:'
  printf '  nobrand ssh confirm-admin --token %s\n' "$token"
}

nobrand_action_is_ssh_confirmation() {
  [ "${ACTION:-}" = nobrand-ssh-tunnel ] \
    && [ "${SSH_TUNNEL_ACTION:-}" = confirm-admin ]
}

nobrand_recovery_action_allowed() {
  local state="$1" action="${2:-}"
  [ -n "$action" ] || return 0
  nobrand_action_is_ssh_confirmation && return 0
  case "$state:$action" in
    CURRENT_PARTIAL_INSTALL:install|CURRENT_PARTIAL_REPAIR:install|\
      CURRENT_PARTIAL_UNINSTALL:install|CURRENT_PARTIAL_UNINSTALL:nobrand-uninstall|\
      LEGACY_SUPPORTED:install)
      return 0
      ;;
  esac
  return 1
}

nobrand_recovery_action_refused() {
  local state="$1"
  case "$state" in
    CURRENT_PARTIAL_UNINSTALL)
      warn "$(t \
        '当前完整卸载尚未完成；仅允许安全修复、继续完整卸载或完成待确认的 SSH 管理员验收。' \
        'Full uninstall is incomplete; only safe repair, continued full uninstall, or pending SSH administrator confirmation is allowed.')"
      ;;
    *)
      warn "$(t \
        '当前安装或修复事务尚未完成；仅允许继续安全修复或完成待确认的 SSH 管理员验收。' \
        'An install or repair transaction is incomplete; only safe repair or pending SSH administrator confirmation is allowed.')"
      ;;
  esac
}

nb_select_partial_recovery_action() {
  local state="${1:-$NOBRAND_INSTALL_STATE}" choice=""
  case "$state" in
    CURRENT_PARTIAL_INSTALL|CURRENT_PARTIAL_REPAIR)
      t '检测到未完成的安装或修复。请选择恢复操作：' \
        'An incomplete install or repair was detected. Choose a recovery action:'
      t '  1) 继续安全修复（默认）' '  1) Continue safe repair (default)'
      t '  0) 退出，不做更改' '  0) Exit without changes'
      if [ "${YES:-0}" -eq 1 ]; then
        choice=1
      else
        read_tty choice "$(t '请选择 [0-1]: ' 'Choose [0-1]: ')" || {
          warn "$(t '无法读取恢复选择；未进行任何更改。' \
            'Unable to read a recovery choice; no changes were made.')"
          return 1
        }
      fi
      case "${choice:-1}" in
        1) ACTION=install ;;
        0) return 2 ;;
        *) warn "$(t '无效恢复选择' 'Invalid recovery choice')"; return 1 ;;
      esac
      ;;
    CURRENT_PARTIAL_UNINSTALL)
      t '检测到未完成的完整卸载。请选择恢复操作：' \
        'An incomplete full uninstall was detected. Choose a recovery action:'
      t '  1) 安全修复安装（默认；仅恢复仍有权威状态的资源）' \
        '  1) Repair safely (default; restore only resources with authoritative state)'
      t '  2) 继续清理 NoBrand 管理的剩余资源' \
        '  2) Continue cleaning remaining NoBrand-managed resources'
      t '  0) 退出，不做更改' '  0) Exit without changes'
      if [ "${YES:-0}" -eq 1 ]; then
        choice=1
      else
        read_tty choice "$(t '请选择 [0-2]: ' 'Choose [0-2]: ')" || {
          warn "$(t '无法读取恢复选择；未进行任何更改。' \
            'Unable to read a recovery choice; no changes were made.')"
          return 1
        }
      fi
      case "${choice:-1}" in
        1) ACTION=install ;;
        2)
          t '[提示] 将继续清理由 NoBrand 管理的剩余资源。' \
            '[Info] Cleanup of remaining NoBrand-managed resources will continue.'
          ACTION=nobrand-uninstall
          ;;
        0) return 2 ;;
        *) warn "$(t '无效恢复选择' 'Invalid recovery choice')"; return 1 ;;
      esac
      ;;
  esac
}

main() {
  local main_lifecycle_lock=0 main_rc=0 recovery_rc=0 dispatch_rc=0
  nb_lifecycle_signal_handlers_install
  # Help/version are intentionally state-independent. Every other root action
  # detects legacy/unknown state before it can read or mutate protocol data.
  case "${ACTION:-menu}" in
    nobrand-version) nobrand_version; return 0 ;;
    nobrand-help) nobrand_usage; return 0 ;;
  esac
  # Protocol submenus dispatch their mutations directly, so the only common
  # exclusion boundary is the lifetime of a real root manager process. An
  # interactive root menu deliberately retains fd 7 while it is open; nested
  # lifecycle actions use the lock's reference count and cannot drop it early.
  # No transaction is created here, and dry-run/non-root read paths stay free
  # of lock-file writes.
  if [ "${DRY_RUN:-0}" -ne 1 ] \
     && [ "$(id -u 2>/dev/null || echo 1)" -eq 0 ]; then
    nb_lifecycle_lock_acquire || return 1
    main_lifecycle_lock=1
  fi
  nb_validate_authoritative_state_boundary
  case "$NOBRAND_INSTALL_STATE" in
    CURRENT_PARTIAL_INSTALL|CURRENT_PARTIAL_REPAIR|CURRENT_PARTIAL_UNINSTALL|LEGACY_SUPPORTED)
      nb_install_state_notice "$NOBRAND_INSTALL_STATE"
      ;;
    CURRENT_COMPLETE)
      [ "${ACTION:-menu}" != install ] || nb_install_state_notice "$NOBRAND_INSTALL_STATE"
      ;;
  esac
  # A live SSH rollback watchdog must be confirmed or allowed to roll back
  # before any recovery choice or explicit command can mutate lifecycle state.
  if nobrand_ssh_confirmation_pending; then
    if [ -z "$ACTION" ]; then
      nobrand_pending_ssh_confirmation_notice
      [ "$main_lifecycle_lock" -eq 0 ] || nb_lifecycle_lock_release
      return 0
    fi
    if ! nobrand_action_is_ssh_confirmation; then
      nobrand_pending_ssh_confirmation_notice
      [ "$main_lifecycle_lock" -eq 0 ] || nb_lifecycle_lock_release
      return 1
    fi
  fi
  case "$NOBRAND_INSTALL_STATE" in
    CURRENT_PARTIAL_INSTALL|CURRENT_PARTIAL_REPAIR|CURRENT_PARTIAL_UNINSTALL|LEGACY_SUPPORTED)
      if ! nobrand_recovery_action_allowed "$NOBRAND_INSTALL_STATE" "$ACTION"; then
        nobrand_recovery_action_refused "$NOBRAND_INSTALL_STATE"
        [ "$main_lifecycle_lock" -eq 0 ] || nb_lifecycle_lock_release
        return 1
      fi
      ;;
  esac
  if [ -z "$ACTION" ]; then
    case "$NOBRAND_INSTALL_STATE" in
      LEGACY_SUPPORTED) ACTION=install ;;
    esac
  fi
  if [ -z "$ACTION" ]; then
    case "$NOBRAND_INSTALL_STATE" in
      CURRENT_PARTIAL_INSTALL|CURRENT_PARTIAL_REPAIR|CURRENT_PARTIAL_UNINSTALL)
        nb_select_partial_recovery_action "$NOBRAND_INSTALL_STATE" || {
          recovery_rc=$?
          [ "$main_lifecycle_lock" -eq 0 ] || nb_lifecycle_lock_release
          [ "$recovery_rc" -eq 2 ] && return 0
          return "$recovery_rc"
        }
        ;;
    esac
  fi
  if [ "${DRY_RUN:-0}" -ne 1 ] \
     && [ "$(id -u 2>/dev/null || echo 1)" -eq 0 ]; then
    ensure_manager_state_layout 0
  fi
  if [ -z "$ACTION" ]; then
    nobrand_menu_loop
    main_rc=$?
    [ "$main_lifecycle_lock" -eq 0 ] || nb_lifecycle_lock_release
    return "$main_rc"
  fi
  if [ "$ACTION" != "menu" ] && [[ "$ACTION" != nobrand-* ]]; then
    print_banner
  fi
  if dry_run_should_preview "$ACTION"; then
    dry_run_action_preview "$ACTION"
    [ "$main_lifecycle_lock" -eq 0 ] || nb_lifecycle_lock_release
    return 0
  fi
  if [ "${DRY_RUN:-0}" -ne 1 ] \
     && [ "$(id -u 2>/dev/null || echo 1)" -eq 0 ] \
     && nb_schema_v3_file_valid \
     && is_mita_elf_binary "$MITA_BIN"; then
    repair_mita_binary_paths 2>/dev/null || true
  fi
  case "$ACTION" in
    install) do_install ;;
    reconfigure) do_reconfigure ;;
    upgrade) do_upgrade ;;
    uninstall) do_uninstall ;;
    status) do_status ;;
    client-config|show) do_client_config ;;
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
    nobrand-status) nobrand_status ;;
    nobrand-nodes) nobrand_nodes ;;
    nobrand-doctor) nobrand_doctor ;;
    nobrand-backup) nobrand_backup_action ;;
    nobrand-uninstall) nobrand_uninstall ;;
    nobrand-manager-upgrade) nobrand_manager_upgrade ;;
    nobrand-network) do_perf ;;
    nobrand-snell) nobrand_run_snell_action ;;
    nobrand-hy2) nobrand_run_hy2_action ;;
    nobrand-vless-sudoku) nobrand_run_vless_sudoku_action ;;
    nobrand-vless-reality) nobrand_run_vless_reality_action ;;
    nobrand-tuic) nobrand_run_tuic_action ;;
    nobrand-ssh-tunnel) nobrand_run_ssh_tunnel_action ;;
    nobrand-forward) nobrand_run_forward_action ;;
    nobrand-ingress) nobrand_run_ingress_action ;;
    nobrand-mieru-menu) menu_loop ;;
    help) usage ;;
    menu)
      menu_loop
      ;;
    *) usage; main_rc=1 ;;
  esac
  dispatch_rc=$?
  [ "$main_rc" -ne 0 ] || main_rc="$dispatch_rc"
  [ "$main_lifecycle_lock" -eq 0 ] || nb_lifecycle_lock_release
  return "$main_rc"
}

# 允许被 source 做单测（设置 MITA_SOURCE_ONLY=1）
if [ "${MITA_SOURCE_ONLY:-0}" != "1" ]; then
  main
fi
