main() {
  if [ "${DRY_RUN:-0}" -ne 1 ] \
     && [ "$(id -u 2>/dev/null || echo 1)" -eq 0 ]; then
    ensure_manager_state_layout
  fi
  if [ -z "$ACTION" ]; then
    menu_loop
    exit 0
  fi
  if [ "$ACTION" != "menu" ]; then
    print_banner
  fi
  if dry_run_should_preview "$ACTION"; then
    dry_run_action_preview "$ACTION"
    return 0
  fi
  if [ "${DRY_RUN:-0}" -ne 1 ] \
     && [ "$(id -u 2>/dev/null || echo 1)" -eq 0 ] \
     && mita_installed; then
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
    help) usage; exit 0 ;;
    menu)
      menu_loop
      ;;
    *) usage; exit 1 ;;
  esac
}

# 允许被 source 做单测（设置 MITA_SOURCE_ONLY=1）
if [ "${MITA_SOURCE_ONLY:-0}" != "1" ]; then
  main
fi
