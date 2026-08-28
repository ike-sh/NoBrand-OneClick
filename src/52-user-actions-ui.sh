do_user_quota_reset() {
  # 手动触发日历月重置（或强制所有 calendar 用户）
  require_root
  load_install_state
  users_ensure_loaded
  local force="${1:-}" cal tx
  admin_lock_acquire || return 1
  tx="$(users_tx_snapshot)" || { admin_lock_release; return 1; }
  if [ "$force" = "force" ] || [ "${YES:-0}" -eq 1 ]; then
    # 清除 last_quota_reset 使本月全部 calendar 用户重跑
    python3 -c '
import json,sys
path=sys.argv[1]
d=json.load(open(path))
for u in d.get("users") or []:
    if (u.get("quota_mode") or "")=="calendar" and int(u.get("quota_mb") or 0)>0:
        u["last_quota_reset"]=""
json.dump(d, open(path,"w"), indent=2)
' "$MITA_USERS_STATE" 2>/dev/null || {
      users_tx_rollback "$tx" 0
      admin_lock_release
      return 1
    }
  fi
  if ! cal="$(users_scan_calendar_quota_reset)"; then
    users_tx_rollback "$tx" 0
    admin_lock_release
    return 1
  fi
  users_tx_commit "$tx"
  admin_lock_release
  if [ -n "$cal" ]; then
    t "已重置日历月配额: $(printf '%s' "$cal" | tr '\n' ' ')" \
      "Calendar quota reset: $(printf '%s' "$cal" | tr '\n' ' ')"
  else
    t '无需重置（无 calendar 用户或本月已重置）' \
      'Nothing to reset (no calendar users or already done this month)'
  fi
}

do_user_set_rate() {
  require_root
  mita_installed || die "$(t 'mita 未安装' 'mita is not installed')"
  local requested_name="${USERNAME:-}"
  load_install_state
  users_ensure_loaded
  local name="${requested_name:-${USERNAME:-}}" bw="${USER_BANDWIDTH_MBPS:-}"
  [ -n "$name" ] || die "$(t '需要 --user NAME' 'Need --user NAME')"
  [ -n "$bw" ] || die "$(t '需要 --bandwidth Mbps（0=不限）' 'Need --bandwidth Mbps (0=unlimited)')"
  valid_bandwidth_mbps "$bw" || die "$(t '带宽须为 0-1000000 Mbps 的整数' \
    'Bandwidth must be an integer from 0 to 1000000 Mbps')"
  users_name_exists "$name" || die "$(t "用户不存在: $name" "User not found: $name")"
  USER_QUOTA_MB="" USER_QUOTA_DAYS="" USER_EXPIRE="" USER_PACKAGE=""
  USER_BANDWIDTH_MBPS="$bw"
  local tx
  admin_lock_acquire || return 1
  tx="$(users_tx_snapshot)" || { admin_lock_release; return 1; }
  if ! users_update_fields "$name"; then
    users_tx_rollback "$tx" 0
    admin_lock_release
    return 1
  fi
  if ! apply_users_config "$tx"; then
    admin_lock_release
    return 1
  fi
  users_tx_commit "$tx"
  admin_lock_release
  t "已更新 ${name} 的专属实例限速: ${bw} Mbps（0=不限）" \
    "Updated dedicated-instance limit for ${name}: ${bw} Mbps (0=unlimited)"
}

do_rate_status() {
  require_root 2>/dev/null || true
  load_install_state 2>/dev/null || true
  tc_rate_status
}

do_rate_restore() {
  require_root 2>/dev/null || true
  load_install_state 2>/dev/null || true
  admin_lock_acquire || return 1
  if ! apply_tc_limits; then
    admin_lock_release
    return 1
  fi
  admin_lock_release
  t '已根据专属实例套餐恢复本脚本拥有的 tc filter；未替换现有 root qdisc' \
    'Restored script-owned tc filters from dedicated packages; existing root qdiscs were not replaced'
}

do_user_del() {
  require_root
  require_linux
  mita_installed || die "$(t 'mita 未安装' 'mita is not installed')"
  load_install_state
  users_ensure_loaded
  local name="${USER_DEL_NAME:-}"
  if [ -z "$name" ]; then
    if [ "$YES" -eq 1 ]; then
      die "$(t '--user-del 需要用户名' '--user-del requires username')"
    fi
    do_user_list
    read_tty name "$(t '要删除的用户名: ' 'Username to delete: ')" || true
  fi
  [ -n "$name" ] || die "$(t '用户名不能为空' 'Username required')"
  local n freed tx close_pairs=""
  admin_lock_acquire || return 1
  tx="$(users_tx_snapshot)" || { admin_lock_release; return 1; }
  n="$(users_count)"
  if [ "${n:-0}" -le 1 ] && users_name_exists "$name"; then
    users_tx_commit "$tx"
    admin_lock_release
    if [ "${MENU_MODE:-0}" -eq 1 ]; then
      warn "$(t '不能删除最后一个用户' 'Cannot delete the last user')"
      return "$USER_MENU_HANDLED_RC"
    fi
    die "$(t '不能删除最后一个用户' 'Cannot delete the last user')"
  fi
  if ! freed="$(users_del "$name")"; then
    users_tx_rollback "$tx" 0
    admin_lock_release
    return 1
  fi
  if ! apply_users_config "$tx"; then
    admin_lock_release
    return 1
  fi
  if [ -n "$freed" ]; then
    close_pairs="${PROTOCOL}|${freed}"
    [ "$PROTOCOL" = "BOTH" ] && close_pairs="TCP|${freed}"$'\n'"UDP|$((freed + 1))"
    close_firewall_for_bindings "$close_pairs"
  fi
  open_firewall_for_pairs "$(multi_user_port_protocol_pairs)"
  users_sync_primary_globals
  if ! save_install_state; then
    users_tx_rollback "$tx" 1
    open_firewall_for_pairs "$close_pairs"
    admin_lock_release
    return 1
  fi
  users_tx_commit "$tx"
  client_export_remove_user "$name" 2>/dev/null || true
  admin_lock_release
  t "完成。已释放端口: ${freed:-?}" "Done. Freed port: ${freed:-?}"
}

do_user_set_endpoint() {
  require_root
  require_linux
  local requested_name="${USERNAME:-}" requested_host="${ADVERTISE_HOST:-}"
  local requested_port="${ADVERTISE_PORT:-}" requested_cli="${ADVERTISE_CLI:-0}"
  local requested_auto="${ADVERTISE_AUTO_REQUESTED:-0}"
  local name host port actual_port current_host current_port tx auto_host=""
  USERNAME_CLI=0
  ADVERTISE_CLI=0
  load_install_state
  users_ensure_loaded
  users_state_exists || die "$(t '无用户状态' 'No users state')"
  name="${requested_name:-${USERNAME:-}}"
  if [ -z "$name" ]; then
    [ "$YES" -ne 1 ] || die "$(t '需要 --user NAME' 'Need --user NAME')"
    read_tty name "$(t '用户名: ' 'Username: ')" || true
  fi
  users_name_exists "$name" || die "$(t "用户不存在: $name" "User not found: $name")"
  actual_port="$(users_get_field "$name" port)"
  current_host="$(users_get_field "$name" advertise_host 2>/dev/null || true)"
  current_port="$(users_get_field "$name" advertise_port 2>/dev/null || true)"

  if [ "$requested_cli" -eq 1 ]; then
    if [ "$requested_auto" -eq 1 ]; then
      host=""
      port=""
    else
      host="${requested_host:-$current_host}"
      port="${requested_port:-${current_port:-$actual_port}}"
      if [ -z "$host" ]; then
        host="$(public_ip 2>/dev/null || true)"
      fi
    fi
    validate_advertise_endpoint_values "$host" "$port" "$PROTOCOL" \
      || die "$(t '自定义客户端入口参数无效' 'Invalid custom client entry parameters')"
    [ -z "$port" ] || port="$(normalize_uint "$port")"
  else
    [ "$YES" -ne 1 ] || die "$(t '请提供 --advertise-host/--advertise-port 或 --advertise-auto' \
      'Provide --advertise-host/--advertise-port or --advertise-auto')"
    ADVERTISE_HOST="$(users_get_field "$name" advertise_host 2>/dev/null || true)"
    ADVERTISE_PORT="$(users_get_field "$name" advertise_port 2>/dev/null || true)"
    PORT="$actual_port"
    msg ""
    t "当前客户端入口: $([ -n "$ADVERTISE_HOST" ] && printf '%s:%s' "$ADVERTISE_HOST" "$ADVERTISE_PORT" || printf '自动探测')" \
      "Current client entry: $([ -n "$ADVERTISE_HOST" ] && printf '%s:%s' "$ADVERTISE_HOST" "$ADVERTISE_PORT" || printf 'auto-detect')"
    collect_advertise_endpoint_interactive
    host="$ADVERTISE_HOST"
    port="$ADVERTISE_PORT"
  fi

  admin_lock_acquire || return 1
  tx="$(users_tx_snapshot)" || { admin_lock_release; return 1; }
  if ! users_set_advertise_endpoint "$name" "$host" "$port"; then
    users_tx_rollback "$tx" 0
    admin_lock_release
    return 1
  fi
  auto_host="$(public_ip 2>/dev/null || true)"
  if ! users_validate_state_file "$MITA_USERS_STATE" "$PROTOCOL" "$auto_host"; then
    users_tx_rollback "$tx" 0
    admin_lock_release
    die "$(t '客户端展示入口与其它用户冲突' \
      'Client display endpoint conflicts with another user')"
  fi
  users_sync_primary_globals
  if ! save_install_state; then
    users_tx_rollback "$tx" 0
    admin_lock_release
    return 1
  fi
  users_tx_commit "$tx"
  admin_lock_release
  ADVERTISE_AUTO_REQUESTED=0
  t "已更新 ${name} 的客户端展示入口；服务端实例未重启" \
    "Updated ${name} client display endpoint; server instance was not restarted"
  print_user_outputs "$name"
}

do_user_show() {
  require_root
  load_install_state
  users_ensure_loaded
  local name="${USER_SHOW_NAME:-}"
  if [ -z "$name" ]; then
    read_tty name "$(t '用户名: ' 'Username: ')" || true
  fi
  users_name_exists "$name" || die "$(t "用户不存在: $name" "User not found: $name")"
  print_user_outputs "$name"
}

do_user_manage() {
  require_root
  MENU_MODE=1
  while true; do
    msg ""
    t '【用户管理】每个账号使用专属 mita 实例、端口、配额 metrics 与可选双向限速' \
      '[Users] every account has a dedicated mita instance, port, quota metrics, and optional bidirectional rate limit'
    msg "  1) 列出用户"
    msg "  2) 添加用户"
    msg "  3) 删除用户"
    msg "  4) 查看用户节点配置"
    msg "  5) 设置套餐/配额"
    msg "  6) 设置到期日"
    msg "  7) 启用用户"
    msg "  8) 停用用户"
    msg "  9) 立即扫描到期+月配额"
    msg "  10) 设置专属实例限速"
    msg "  11) 查看专属限速/tc 状态"
    msg "  12) 备份用户配置"
    msg "  13) 从备份恢复"
    msg "  14) 强制日历月配额重置"
    msg "  15) 查看流量/配额用量"
    msg "  16) 批量导出客户端配置"
    msg "  17) 设置客户端展示入口"
    msg "  18) 返回主菜单"
    local c=""
    read_tty c "$(t '请选择 [1-18]: ' 'Choose [1-18]: ')" || c=""
    c="$(printf '%s' "$c" | tr -d '[:space:]')"
    if [ "$c" = 18 ]; then
      [ "${MAIN_MENU_ACTIVE:-0}" -eq 1 ] && return 3
      return 0
    fi
    local action_rc=0
    set +e
    (
      set -Eeuo pipefail
      trap 'rc=$?; if [ "$rc" -eq 3 ] || [ "$rc" -eq "$USER_MENU_HANDLED_RC" ]; then exit "$rc"; fi; on_error' ERR
      case "$c" in
        1) STAGE="列出用户" ;;
        2) STAGE="添加用户" ;;
        3) STAGE="删除用户" ;;
        4) STAGE="查看用户节点配置" ;;
        5) STAGE="设置用户套餐" ;;
        6) STAGE="设置用户到期日" ;;
        7) STAGE="启用用户" ;;
        8) STAGE="停用用户" ;;
        9) STAGE="扫描用户配额" ;;
        10) STAGE="设置用户限速" ;;
        11) STAGE="查看限速状态" ;;
        12) STAGE="备份用户配置" ;;
        13) STAGE="恢复用户配置" ;;
        14) STAGE="重置用户配额" ;;
        15) STAGE="查看用户用量" ;;
        16) STAGE="导出用户客户端配置" ;;
        17) STAGE="设置用户展示入口" ;;
        *) STAGE="用户管理" ;;
      esac
      case "$c" in
      1) do_user_list ;;
      2)
        USERNAME=""; PASSWORD=""; PORT=""; PORT_CLI=0
        USER_PACKAGE=""; USER_QUOTA_MB=""; USER_QUOTA_DAYS=""; USER_QUOTA_MODE=""; USER_EXPIRE=""; USER_BANDWIDTH_MBPS=""
        local bw_in="" qm_in=""
        read_tty USERNAME "$(t '新用户名: ' 'New username: ')" || true
        read_tty PASSWORD "$(t '密码（回车随机）: ' 'Password (Enter=random): ')" || true
        read_tty bw_in "$(t '带宽 Mbps（回车=不限，双向）: ' 'Bandwidth Mbps (Enter=unlim, both dirs): ')" || true
        USER_BANDWIDTH_MBPS="${bw_in:-0}"
        do_user_add
        ;;
      3)
        USER_DEL_NAME=""
        do_user_del
        ;;
      4)
        USER_SHOW_NAME=""
        do_user_show
        ;;
      5)
        USERNAME=""; USER_PACKAGE=""; USER_QUOTA_MB=""; USER_QUOTA_DAYS=""; USER_QUOTA_MODE=""; USER_EXPIRE=""; USER_BANDWIDTH_MBPS=""
        read_tty USERNAME "$(t '用户名: ' 'Username: ')" || true
        t '1)不限量 2)体验 3)标准 4)自定义' '1)unlimited 2)trial 3)standard 4)custom'
        local pk="" qm_in=""
        read_tty pk "$(t '套餐 [1-4]: ' 'Package [1-4]: ')" || true
        case "$pk" in
          1) USER_PACKAGE=unlimited ;;
          2) USER_PACKAGE=trial ;;
          3) USER_PACKAGE=standard ;;
          4)
            USER_PACKAGE=custom
            read_tty USER_QUOTA_MB "$(t '配额 MB: ' 'Quota MB: ')" || true
            read_tty USER_QUOTA_DAYS "$(t '滚动天数 [30]: ' 'Days [30]: ')" || true
            ;;
        esac
        read_tty qm_in "$(t '配额模式 1)滚动 2)日历月 [1]: ' 'Quota mode 1)rolling 2)calendar [1]: ')" || true
        case "${qm_in:-1}" in
          2) USER_QUOTA_MODE=calendar ;;
          *) USER_QUOTA_MODE=rolling ;;
        esac
        do_user_set_quota
        ;;
      6)
        USERNAME=""; USER_EXPIRE=""; USER_BANDWIDTH_MBPS=""
        read_tty USERNAME "$(t '用户名: ' 'Username: ')" || true
        read_tty USER_EXPIRE "$(t '到期 YYYY-MM-DD / +30d / 0: ' 'Expire YYYY-MM-DD / +30d / 0: ')" || true
        do_user_set_expire
        ;;
      7)
        USER_SHOW_NAME=""
        read_tty USER_SHOW_NAME "$(t '用户名: ' 'Username: ')" || true
        do_user_enable
        ;;
      8)
        USER_SHOW_NAME=""
        read_tty USER_SHOW_NAME "$(t '用户名: ' 'Username: ')" || true
        do_user_disable
        ;;
      9) do_user_scan ;;
      10)
        USERNAME=""; USER_BANDWIDTH_MBPS=""
        read_tty USERNAME "$(t '用户名: ' 'Username: ')" || true
        read_tty USER_BANDWIDTH_MBPS "$(t '带宽 Mbps（0=不限，双向）: ' 'Bandwidth Mbps (0=unlimited, both directions): ')" || true
        do_user_set_rate
        ;;
      11) do_rate_status ;;
      12) do_user_backup ;;
      13)
        USER_RESTORE_FILE=""
        do_user_restore
        ;;
      14)
        local saved_yes="$YES"
        YES=1
        do_user_quota_reset force
        YES="$saved_yes"
        ;;
      15) do_user_usage ;;
      16) do_user_export_clients ;;
      17)
        USERNAME=""; ADVERTISE_HOST=""; ADVERTISE_PORT=""; ADVERTISE_CLI=0
        read_tty USERNAME "$(t '用户名: ' 'Username: ')" || true
        do_user_set_endpoint
        ;;
      *) warn "$(t '无效选择' 'Invalid choice')" ;;
      esac
    )
    action_rc=$?
    set -e
    [ "$action_rc" -ne 3 ] || return 3
    if [ "$action_rc" -ne 0 ] && [ "$action_rc" -ne "$USER_MENU_HANDLED_RC" ]; then
      warn "$(t '用户操作未完成，请根据上方错误重试' \
        'User operation failed; review the error above and retry')"
    fi
    user_menu_pause
  done
}
