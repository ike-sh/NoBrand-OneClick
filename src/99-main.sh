main() {
  # Help/version are intentionally state-independent. Every other root action
  # detects legacy/unknown state before it can read or mutate protocol data.
  case "${ACTION:-menu}" in
    nobrand-version) nobrand_version; return 0 ;;
    nobrand-help) nobrand_usage; return 0 ;;
  esac
  nb_validate_authoritative_state_boundary
  if [ "${DRY_RUN:-0}" -ne 1 ] \
     && [ "$(id -u 2>/dev/null || echo 1)" -eq 0 ]; then
    ensure_manager_state_layout 0
  fi
  if [ -z "$ACTION" ]; then
    nobrand_menu_loop
    exit 0
  fi
  if [ "$ACTION" != "menu" ] && [[ "$ACTION" != nobrand-* ]]; then
    print_banner
  fi
  if dry_run_should_preview "$ACTION"; then
    dry_run_action_preview "$ACTION"
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
    nobrand-tuic) nobrand_run_tuic_action ;;
    nobrand-ssh-tunnel) nobrand_run_ssh_tunnel_action ;;
    nobrand-forward) nobrand_run_forward_action ;;
    nobrand-mieru-menu) menu_loop ;;
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
