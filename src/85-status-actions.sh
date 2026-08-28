status_binding_text() {
  local port="$1"
  case "${PROTOCOL:-TCP}" in
    BOTH) printf 'TCP %s / UDP %s' "$port" "$((port + 1))" ;;
    UDP) printf 'UDP %s' "$port" ;;
    *) printf 'TCP %s' "$port" ;;
  esac
}

do_status() {
  local sm status_out iid iname iport
  sm="$(service_manager)"
  if ! mita_installed; then
    t 'mita 未安装' 'mita is not installed'
    [ "${MENU_MODE:-0}" -eq 1 ] && return 1
    exit 1
  fi
  load_install_state 2>/dev/null || true
  msg ""
  t '【版本与配置】' '[Version and configuration]'
  t "  OneClick Version: ${SCRIPT_VERSION}" "  OneClick Version: ${SCRIPT_VERSION}"
  t "  Installed Mieru: $(installed_version 2>/dev/null || printf unknown)" \
    "  Installed Mieru: $(installed_version 2>/dev/null || printf unknown)"
  t "  Channel: $(mieru_channel_label)" "  Channel: $(mieru_channel_label)"
  t "  Tested/Stable Mieru: ${TESTED_MIERU_VERSION}" \
    "  Tested/Stable Mieru: ${TESTED_MIERU_VERSION}"
  t "  Profile: $(profile_label)" "  Profile: $(profile_label)"
  msg ""
  users_isolated_mode || {
    warn "$(t 'schema v3 Mieru 状态不是 isolated-v2' \
      'Schema-v3 Mieru state is not isolated-v2')"
    return 1
  }
  t '部署模型: 用户专属实例 isolated-v2' 'Deployment: dedicated user instances (isolated-v2)'
  if [ -z "$(users_enabled_instance_rows 2>/dev/null || true)" ]; then
    warn "$(t '当前没有启用中的用户；所有专属实例均应处于停止状态' \
      'No users are enabled; all dedicated instances should be stopped')"
  fi
  while IFS=$'\t' read -r iid iname iport; do
    [ -n "$iid" ] || continue
    msg ""
    t "【${iname} / ${iid}】" "[${iname} / ${iid}]"
    t "  监听: $(status_binding_text "$iport")" \
      "  Listen: $(status_binding_text "$iport")"
    case "$sm" in
      systemd) systemctl status "$(instance_systemd_unit "$iid")" --no-pager 2>/dev/null | head -n 12 || true ;;
      openrc) rc-service "$(instance_openrc_service "$iid")" status 2>/dev/null || true ;;
    esac
    status_out="$(instance_cmd "$iid" status 2>/dev/null || true)"
    msg "${status_out:-status unavailable}"
  done < <(users_enabled_instance_rows)
  msg ""
  t '状态页已隐藏密码；查看或导出节点配置请使用主菜单「查看节点」' \
    'Passwords are hidden on the status page; use View node in the main menu to view or export node configuration'
}

do_client_config() {
  require_root
  mita_installed || bail "$(t 'mita 未安装' 'mita is not installed')" || return 1
  repair_mita_binary_paths 2>/dev/null || true
  load_config_from_mita || return 1
  generate_client_config
}

rollback_mtu_change() {
  local restore_mtu="$1" restore_policy="$2" restore_profile="${3:-custom}"
  MTU="$restore_mtu"
  MTU_POLICY="$restore_policy"
  PROFILE="$restore_profile"
  users_isolated_mode || return 1
  reconcile_isolated_instances && verify_mita_running
}

do_mtu_config() {
  require_root || return 1
  require_linux || return 1
  mita_installed || bail "$(t 'mita 未安装，请先安装' 'mita is not installed; run install first')" || return 1
  repair_mita_binary_paths 2>/dev/null || true
  load_config_from_mita || return 1

  local old_mtu="$MTU" old_policy="$MTU_POLICY" old_profile="$PROFILE"
  msg ""
  t "当前 MTU: ${old_mtu}（$(mtu_policy_label)）" \
    "Current MTU: ${old_mtu} ($(mtu_policy_label))"
  if [ "${MTU_CLI:-0}" -eq 1 ]; then
    resolve_mtu_request || return 1
    print_mtu_selection
  else
    choose_mtu_interactive || return 1
  fi

  if [ "$MTU" = "$old_mtu" ]; then
    save_install_state
    msg ""
    t "MTU 数值未变化，保持 ${MTU}；下面重新输出当前节点链接和配置。" \
      "MTU is unchanged at ${MTU}; current share links and config follow."
    generate_client_config
    return 0
  fi

  PROFILE=custom

  admin_lock_acquire || return 1
  MULTI_USER_MODE=1
  if ! reconcile_isolated_instances || ! verify_mita_running; then
    warn "$(t "新 MTU ${MTU} 未能正常启动，正在回滚到 ${old_mtu}" \
      "New MTU ${MTU} failed to start; rolling back to ${old_mtu}")"
    rollback_mtu_change "$old_mtu" "$old_policy" "$old_profile" || true
    admin_lock_release
    return 1
  fi
  if ! save_install_state; then
    warn "$(t '保存 MTU 状态失败，正在恢复原服务端配置' \
      'Failed to save MTU state; restoring the previous server config')"
    rollback_mtu_change "$old_mtu" "$old_policy" "$old_profile" || \
      warn "$(t '自动回滚未能完全验证，请运行 mita doctor 检查服务' \
        'Automatic rollback could not be fully verified; run mita doctor')"
    admin_lock_release
    return 1
  fi
  admin_lock_release
  client_exports_clear_current 2>/dev/null || true

  msg ""
  t "========== MTU 调整完成：${old_mtu} → ${MTU} ==========" \
    "========== MTU updated: ${old_mtu} -> ${MTU} =========="
  t '服务端配置已重新应用并完成重启；请在客户端重新导入下面的新链接或 JSON。' \
    'Server config was reapplied and restarted; re-import the new link or JSON on clients.'
  generate_client_config
}

do_profile_config() {
  require_root || return 1
  require_linux || return 1
  mita_installed || bail "$(t 'mita 未安装，请先安装' 'mita is not installed; run install first')" || return 1
  repair_mita_binary_paths 2>/dev/null || true
  load_config_from_mita || return 1
  if [ "${PROFILE_CLI:-0}" -eq 1 ]; then
    PROFILE="$(normalize_profile "$PROFILE")" || die "$(t '非法 Profile' 'Invalid profile')"
  else
    choose_profile_interactive
  fi
  if [ "$PROFILE" = custom ]; then
    t '高级自定义将逐项开放现有高级参数。' \
      'Advanced Custom opens all existing advanced parameters.'
    PROFILE_CLI=1
    do_reconfigure
    return
  fi
  apply_profile_values "$PROFILE"
  PROFILE_CLI=1
  PROTOCOL_CLI=1
  MTU_REQUEST="$MTU"; MTU_CLI=1
  MULTIPLEXING_CLI=1
  HANDSHAKE_CLI=1
  TRAFFIC_CLI=1
  LOW_ENTROPY_CLI=1
  local saved_yes="$YES"
  YES=1
  do_reconfigure
  YES="$saved_yes"
}

do_tuning_config() {
  local kind="$1" old_value="" saved_yes="$YES"
  require_root || return 1
  require_linux || return 1
  mita_installed || bail "$(t 'mita 未安装，请先安装' 'mita is not installed; run install first')" || return 1
  repair_mita_binary_paths 2>/dev/null || true
  load_config_from_mita || return 1
  PROFILE=custom
  PROFILE_CLI=1
  case "$kind" in
    client-modes)
      old_value="${MULTIPLEXING}|${HANDSHAKE_MODE}"
      MULTIPLEXING_CLI=0 HANDSHAKE_CLI=0
      choose_client_modes_interactive
      [ "$old_value" != "${MULTIPLEXING}|${HANDSHAKE_MODE}" ] || return 0
      MULTIPLEXING_CLI=1 HANDSHAKE_CLI=1
      ;;
    traffic)
      old_value="${TRAFFIC_PATTERN}|${LOW_ENTROPY_MODE}"
      TRAFFIC_CLI=0
      choose_traffic_pattern_interactive
      [ "$TRAFFIC_PATTERN" != off ] || LOW_ENTROPY_MODE=LOW_ENTROPY_MODE_OFF
      [ "$old_value" != "${TRAFFIC_PATTERN}|${LOW_ENTROPY_MODE}" ] || return 0
      TRAFFIC_CLI=1 LOW_ENTROPY_CLI=1
      ;;
    low-entropy)
      if [ "$(normalize_traffic_pattern "${TRAFFIC_PATTERN:-off}")" = off ]; then
        warn "$(t 'Traffic Pattern 当前为 OFF；Low Entropy 依赖该能力，请先配置 Traffic Pattern。' \
          'Traffic Pattern is OFF; Low Entropy depends on it, so configure Traffic Pattern first.')"
        return 0
      fi
      old_value="$LOW_ENTROPY_MODE"
      LOW_ENTROPY_CLI=0
      choose_low_entropy_interactive
      [ "$old_value" != "$LOW_ENTROPY_MODE" ] || return 0
      LOW_ENTROPY_CLI=1
      ;;
    *) return 1 ;;
  esac
  YES=1
  do_reconfigure
  YES="$saved_yes"
}

do_bbr_config() {
  require_root || return 1
  require_linux || return 1
  report_bbr_fq_status
  offer_bbr_fq
}

do_version_channel_config() {
  require_root || return 1
  load_install_state 2>/dev/null || true
  local input="" version=""
  msg ""
  t "当前通道: $(mieru_channel_label)" "Current channel: $(mieru_channel_label)"
  t "  1) stable — 项目测试版本 ${TESTED_MIERU_VERSION}" \
    "  1) stable — project-tested ${TESTED_MIERU_VERSION}"
  t '  2) latest — 每次升级查询上游最新 release' \
    '  2) latest — query the newest upstream release on each upgrade'
  t '  3) pinned — 指定精确版本（高级）' \
    '  3) pinned — use an exact version (advanced)'
  read_tty input "$(t '请选择 [1-3]: ' 'Choose [1-3]: ')" || input=""
  case "$input" in
    1) MIERU_CHANNEL=stable; MIERU_VERSION="$TESTED_MIERU_VERSION" ;;
    2) MIERU_CHANNEL=latest; MIERU_VERSION="" ;;
    3)
      read_tty version "$(t '精确版本（例如 3.35.0）: ' 'Exact version (for example 3.35.0): ')" || version=""
      valid_mieru_version "$version" || die "$(t '版本号格式无效' 'Invalid version format')"
      MIERU_CHANNEL=pinned; MIERU_VERSION="$version"
      ;;
    *) warn "$(t '已取消通道修改' 'Channel change cancelled')"; return 0 ;;
  esac
  MIERU_CHANNEL_CLI=1
  [ "$MIERU_CHANNEL" != pinned ] || MIERU_VERSION_CLI=1
  do_upgrade
}

do_start() {
  require_root || return 1
  mita_installed || bail "$(t 'mita 未安装，请先安装' 'mita is not installed')" || return 1
  repair_mita_binary_paths 2>/dev/null || true
  start_mita
  verify_mita_running 1
  t '所有用户专属 mita 实例已启动' 'All dedicated mita user instances started'
}

do_stop() {
  require_root || return 1
  mita_installed || bail "$(t 'mita 未安装' 'mita is not installed')" || return 1
  users_isolated_mode || bail "$(t 'schema v3 Mieru 状态必须使用 isolated-v2' \
    'Schema-v3 Mieru state must use isolated-v2')" || return 1
  local iid iname iport
  STAGE="停止专属实例"
  while IFS=$'\t' read -r iid iname iport; do
    [ -n "$iid" ] || continue
    instance_daemon_stop "$iid" 0
  done < <(users_enabled_instance_rows)
  t '所有用户专属 mita 实例已停止' 'All dedicated mita user instances stopped'
}

do_restart() {
  require_root || return 1
  mita_installed || bail "$(t 'mita 未安装' 'mita is not installed')" || return 1
  repair_mita_binary_paths 2>/dev/null || true
  users_isolated_mode || bail "$(t 'schema v3 Mieru 状态必须使用 isolated-v2' \
    'Schema-v3 Mieru state must use isolated-v2')" || return 1
  local iid iname iport
  STAGE="重启专属实例"
  while IFS=$'\t' read -r iid iname iport; do
    [ -n "$iid" ] || continue
    instance_daemon_stop "$iid" 0
    instance_start_proxy "$iid" || return 1
  done < <(users_enabled_instance_rows)
  verify_mita_running 1
  t '所有用户专属 mita 实例已重启' 'All dedicated mita user instances restarted'
}
