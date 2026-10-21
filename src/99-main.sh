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
      CURRENT_PARTIAL_UNINSTALL:install|CURRENT_PARTIAL_UNINSTALL:nobrand-uninstall)
      return 0
      ;;
  esac
  if [ "$state" = CURRENT_PARTIAL_INSTALL ] \
     && [ -n "${NOBRAND_PROTOCOL_EXPLICIT_RETRY_SCOPE:-}" ] \
     && nb_lifecycle_tx_valid \
     && [ "$(nb_lifecycle_field STATUS)" = in-progress ] \
     && [ "$(nb_lifecycle_scope)" = "$NOBRAND_PROTOCOL_EXPLICIT_RETRY_SCOPE" ]; then
    if [ "$NOBRAND_PROTOCOL_EXPLICIT_RETRY_SCOPE" = forward ]; then
      [ "$(nb_lifecycle_field FORMAT)" = nobrand-lifecycle-v2 ] \
        && [ "$(nb_lifecycle_mutation_started)" = 0 ] || return 1
    fi
    return 0
  fi
  if [ "$state:$action" = CURRENT_PARTIAL_CONFIGURE:nobrand-ingress ] \
     && [ "${NOBRAND_PROTOCOL_EXPLICIT_RETRY_SCOPE:-}" = ingress ] \
     && nb_lifecycle_tx_valid \
     && [ "$(nb_lifecycle_field FORMAT)" = nobrand-lifecycle-v2 ] \
     && [ "$(nb_lifecycle_field STATUS)" = in-progress ] \
     && [ "$(nb_lifecycle_field OPERATION)" = configure ] \
     && [ "$(nb_lifecycle_scope)" = ingress ] \
     && [ "$(nb_lifecycle_mutation_started)" = 0 ]; then
    return 0
  fi
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

nobrand_recovery_scope() {
  local state="${1:-$NOBRAND_INSTALL_STATE}"
  if nb_lifecycle_tx_valid \
     && [ "$(nb_lifecycle_field STATUS)" = in-progress ]; then
    nb_lifecycle_scope
    return $?
  fi
  case "$state" in
    CURRENT_PARTIAL_INSTALL) printf 'manager' ;;
    CURRENT_PARTIAL_REPAIR)
      if declare -F nobrand_backup_restore_transaction_present >/dev/null 2>&1 \
         && nobrand_backup_restore_transaction_present; then
        printf 'global'
      else
        printf 'manager'
      fi
      ;;
    CURRENT_PARTIAL_UNINSTALL) printf 'global' ;;
    *) return 1 ;;
  esac
}

nobrand_set_scoped_recovery_action() {
  local state="${1:-$NOBRAND_INSTALL_STATE}" scope format operation phase mutation_started
  scope="$(nobrand_recovery_scope "$state")" || return 1
  NOBRAND_RECOVERY_EXPECTED_SCOPE="$scope"
  NOBRAND_RECOVERY_EXPECTED_STATE="$state"
  NOBRAND_RECOVERY_EXPECTED_TX_PRESENT=0
  NOBRAND_RECOVERY_EXPECTED_TX_STATUS=""
  NOBRAND_RECOVERY_EXPECTED_TX_ID=""
  NOBRAND_RECOVERY_EXPECTED_TX_RECORD=""
  if [ "$scope" = manager ] && nb_lifecycle_tx_valid; then
    NOBRAND_RECOVERY_EXPECTED_TX_PRESENT=1
    NOBRAND_RECOVERY_EXPECTED_TX_STATUS="$(nb_lifecycle_field STATUS)"
    NOBRAND_RECOVERY_EXPECTED_TX_ID="$(nb_lifecycle_field TRANSACTION_ID)"
    NOBRAND_RECOVERY_EXPECTED_TX_RECORD="$(<"$NOBRAND_LIFECYCLE_TX_FILE")"
  fi
  case "$scope" in
    manager) ACTION=nobrand-manager-bootstrap ;;
    ingress) ACTION=nobrand-ingress-recover ;;
    vless-sudoku) ACTION=nobrand-vless-sudoku; VLESS_SUDOKU_ACTION=install ;;
    ssh-tunnel) ACTION=nobrand-ssh-tunnel; SSH_TUNNEL_ACTION=install ;;
    forward)
      # Forward add parameters are intentionally not copied into lifecycle
      # metadata. Its dedicated route therefore validates committed state or
      # fails closed; it never guesses, recollects, or replays an incomplete add.
      ACTION=nobrand-forward
      FORWARD_ACTION=recover-add
      ;;
    global) ACTION=install ;;
    *) return 1 ;;
  esac
}

nobrand_mark_explicit_protocol_retry() {
  [ -z "${NOBRAND_RECOVERY_EXPECTED_SCOPE:-}" ] || return 0
  case "${ACTION:-}" in
    install) NOBRAND_PROTOCOL_EXPLICIT_RETRY_SCOPE=mieru ;;
    reconfigure) NOBRAND_PROTOCOL_EXPLICIT_RETRY_SCOPE=mieru ;;
    nobrand-snell) [ "${SNELL_ACTION:-}" = install ] && NOBRAND_PROTOCOL_EXPLICIT_RETRY_SCOPE=snell ;;
    nobrand-hy2) [ "${HY2_ACTION:-}" = install ] && NOBRAND_PROTOCOL_EXPLICIT_RETRY_SCOPE=hy2 ;;
    nobrand-tuic) [ "${TUIC_ACTION:-}" = install ] && NOBRAND_PROTOCOL_EXPLICIT_RETRY_SCOPE=tuic ;;
    nobrand-vless-reality)
      [ "${VLESS_REALITY_ACTION:-}" = install ] && NOBRAND_PROTOCOL_EXPLICIT_RETRY_SCOPE=vless-reality
      ;;
    nobrand-vless-sudoku)
      [ "${VLESS_SUDOKU_ACTION:-}" = install ] && NOBRAND_PROTOCOL_EXPLICIT_RETRY_SCOPE=vless-sudoku
      ;;
    nobrand-ssh-tunnel)
      [ "${SSH_TUNNEL_ACTION:-}" = install ] && NOBRAND_PROTOCOL_EXPLICIT_RETRY_SCOPE=ssh-tunnel
      ;;
    nobrand-forward)
      [ "${FORWARD_ACTION:-}" = add ] && NOBRAND_PROTOCOL_EXPLICIT_RETRY_SCOPE=forward
      ;;
    nobrand-ingress)
      case "${INGRESS_ACTION:-}" in
        add|modify|delete|set-default|unset-default|apply)
          NOBRAND_PROTOCOL_EXPLICIT_RETRY_SCOPE=ingress
          ;;
      esac
      ;;
  esac
  return 0
}

nb_select_partial_recovery_action() {
  local state="${1:-$NOBRAND_INSTALL_STATE}" choice=""
  case "$state" in
    CURRENT_PARTIAL_INSTALL|CURRENT_PARTIAL_REPAIR|CURRENT_PARTIAL_CONFIGURE)
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
        1) nobrand_set_scoped_recovery_action "$state" ;;
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
        1) nobrand_set_scoped_recovery_action "$state" ;;
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

nobrand_action_opens_interactive_menu() {
  case "${ACTION:-}" in
    menu|nobrand-mieru-menu|user-manage) return 0 ;;
    nobrand-snell) [ "${SNELL_ACTION:-menu}" = menu ] ;;
    nobrand-hy2) [ "${HY2_ACTION:-menu}" = menu ] ;;
    nobrand-vless-sudoku) [ "${VLESS_SUDOKU_ACTION:-menu}" = menu ] ;;
    nobrand-forward) [ "${FORWARD_ACTION:-}" = menu ] ;;
    *) return 1 ;;
  esac
}

main() {
  local main_lifecycle_lock=0 main_rc=0 recovery_rc=0 dispatch_rc=0
  local NOBRAND_MANAGER_SESSION_ACTIVE=1
  local NOBRAND_PROTOCOL_EXPLICIT_RETRY_SCOPE=""
  nb_lifecycle_signal_handlers_install
  nobrand_mark_explicit_protocol_retry
  # Help/version are intentionally state-independent. Every other root action
  # detects legacy/unknown state before it can read or mutate protocol data.
  case "${ACTION:-menu}" in
    nobrand-version) nobrand_version; return 0 ;;
    nobrand-help) nobrand_usage; return 0 ;;
  esac
  nb_splicore_legacy_preflight || return 1
  # The primary runtime has its own persistent generation transaction and uses
  # the same lifecycle lock. Route before any legacy repair/download branch.
  if nobrand_ssh_confirmation_pending; then
    case "${ACTION:-}" in
      nobrand-runtime|nobrand-snell|nobrand-tuic|nobrand-hy2|nobrand-vless-reality|install|upgrade|reconfigure)
        nobrand_pending_ssh_confirmation_notice
        return 1
        ;;
    esac
  fi
  local runtime_rc=0
  nb_splicore_route_main || runtime_rc=$?
  if [ "${NOBRAND_SPLICORE_HANDLED:-0}" -eq 1 ]; then
    return "$runtime_rc"
  fi
  # Explicit protocol commands may dispatch mutations directly, so retain the
  # process lock across their common state boundary and dispatcher. A no-arg
  # manager launch is different: bootstrap must install dependencies (including
  # flock) before acquiring its transaction lock. The full menu takes the outer
  # guard only after that bootstrap succeeds.
  if [ "${DRY_RUN:-0}" -ne 1 ] \
     && [ -n "${ACTION:-}" ] \
     && [ "${ACTION:-}" != nobrand-manager-upgrade ] \
     && [ "$(id -u 2>/dev/null || echo 1)" -eq 0 ]; then
    nb_lifecycle_lock_acquire || return 1
    main_lifecycle_lock=1
  fi
  if nb_splicore_installed && [ -z "$ACTION" ] && ! nobrand_manager_installation_valid; then
    nobrand_install_manager_script || return 1
  fi
  nb_validate_authoritative_state_boundary
  case "$NOBRAND_INSTALL_STATE" in
    CURRENT_PARTIAL_INSTALL|CURRENT_PARTIAL_REPAIR|CURRENT_PARTIAL_CONFIGURE|\
      CURRENT_PARTIAL_UNINSTALL)
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
    CURRENT_PARTIAL_INSTALL|CURRENT_PARTIAL_REPAIR|CURRENT_PARTIAL_CONFIGURE|\
      CURRENT_PARTIAL_UNINSTALL)
      if ! nobrand_recovery_action_allowed "$NOBRAND_INSTALL_STATE" "$ACTION"; then
        nobrand_recovery_action_refused "$NOBRAND_INSTALL_STATE"
        [ "$main_lifecycle_lock" -eq 0 ] || nb_lifecycle_lock_release
        return 1
      fi
      ;;
  esac
  if [ -z "$ACTION" ]; then
    case "$NOBRAND_INSTALL_STATE" in
      CURRENT_PARTIAL_INSTALL|CURRENT_PARTIAL_REPAIR|CURRENT_PARTIAL_CONFIGURE|\
        CURRENT_PARTIAL_UNINSTALL)
        nb_select_partial_recovery_action "$NOBRAND_INSTALL_STATE" || {
          recovery_rc=$?
          [ "$main_lifecycle_lock" -eq 0 ] || nb_lifecycle_lock_release
          [ "$recovery_rc" -eq 2 ] && return 0
          return "$recovery_rc"
        }
        ;;
    esac
  fi
  if [ "$main_lifecycle_lock" -eq 1 ] \
     && [ "${DRY_RUN:-0}" -ne 1 ] \
     && [ "$(id -u 2>/dev/null || echo 1)" -eq 0 ]; then
    ensure_manager_state_layout 0
  fi
  case "$ACTION" in
    nobrand-manager-bootstrap)
      nobrand_manager_bootstrap || {
        main_rc=$?
        [ "$main_lifecycle_lock" -eq 0 ] || nb_lifecycle_lock_release
        return "$main_rc"
      }
      ACTION=""
      NOBRAND_RECOVERY_EXPECTED_SCOPE=""
      ;;
    nobrand-ingress-recover)
      nobrand_recover_ingress_scope || {
        main_rc=$?
        [ "$main_lifecycle_lock" -eq 0 ] || nb_lifecycle_lock_release
        return "$main_rc"
      }
      ACTION=""
      NOBRAND_RECOVERY_EXPECTED_SCOPE=""
      ;;
  esac
  if [ -z "$ACTION" ]; then
    nobrand_manager_bootstrap || {
      main_rc=$?
      [ "$main_lifecycle_lock" -eq 0 ] || nb_lifecycle_lock_release
      return "$main_rc"
    }
    if [ "$main_lifecycle_lock" -eq 0 ] \
       && [ "${DRY_RUN:-0}" -ne 1 ] \
       && [ "$(id -u 2>/dev/null || echo 1)" -eq 0 ]; then
      nb_lifecycle_lock_acquire || return 1
      main_lifecycle_lock=1
    fi
    NOBRAND_INSTALL_STATE="$(nb_classify_installation_state)" || {
      [ "$main_lifecycle_lock" -eq 0 ] || nb_lifecycle_lock_release
      return 1
    }
    [ "$NOBRAND_INSTALL_STATE" = CURRENT_COMPLETE ] || {
      nb_fail_ambiguous_state
      [ "$main_lifecycle_lock" -eq 0 ] || nb_lifecycle_lock_release
      return 1
    }
    NOBRAND_MENU_EXPECTED_STATE="$NOBRAND_INSTALL_STATE"
    if [ "$main_lifecycle_lock" -eq 1 ]; then
      nb_lifecycle_lock_release
      main_lifecycle_lock=0
    fi
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
  # Legacy runtime recovery belongs to explicit restore/recovery operations.
  if [ "$main_lifecycle_lock" -eq 1 ] && nobrand_action_opens_interactive_menu; then
    NOBRAND_MENU_EXPECTED_STATE="$NOBRAND_INSTALL_STATE"
    nb_lifecycle_lock_release
    main_lifecycle_lock=0
  fi
  case "$ACTION" in
    user-manage) do_user_manage ;;
    perf) do_perf ;;
    bbr-config) do_bbr_config ;;
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
