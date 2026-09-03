mieru_prepare_noninteractive_ingress_endpoint() {
  # Resolve the explicit/default Profile before enforcing the unattended
  # Display Endpoint guard.  A first-class Profile with a stable display host
  # is sufficient input; legacy-default-route still requires an explicit
  # endpoint or --advertise-auto.
  nb_prepare_ingress_request || return 1
  nb_require_explicit_endpoint_noninteractive
}

nb_authoritative_protocol_state_exists() {
  local path root
  for path in \
    "$MITA_STATE" "$MITA_USERS_STATE" \
    "$NOBRAND_HY2_STATE_FILE" "$NOBRAND_VLESS_STATE_FILE" \
    "$NOBRAND_SSH_STATE_FILE" "$NOBRAND_FORWARD_STATE_FILE"; do
    [ ! -s "$path" ] || return 0
  done
  for root in "$NOBRAND_SNELL_STATE_DIR" "$NOBRAND_REALITY_STATE_DIR" "$NOBRAND_TUIC_STATE_DIR"; do
    [ ! -d "$root" ] || ! nb_directory_has_entries "$root" || return 0
  done
  return 1
}

nb_lifecycle_validate_manager_repair() {
  local installed=""
  nb_schema_v3_file_valid || return 1
  installed="$(nb_installed_manager_version 2>/dev/null || true)"
  [ "$installed" = "$SCRIPT_VERSION" ]
}

nb_reconcile_partial_uninstall() {
  local ssh_pending="" ssh_policy="" ssh_token="" ssh_pid="" ssh_origin=""
  # A durable backup restore in `applying` state may have crashed between
  # clearing and copying state/config. Restore its pre-restore snapshot before
  # ordinary repair is allowed to initialize or infer any authoritative state.
  if declare -F nobrand_backup_restore_transaction_present >/dev/null 2>&1 \
     && nobrand_backup_restore_transaction_present; then
    nobrand_backup_restore_transaction_valid || {
      warn "$(t '备份恢复的持久快照或事务元数据无效；拒绝初始化新状态' \
        'The durable backup-restore snapshot or transaction metadata is invalid; refusing to initialize new state')"
      return 1
    }
    case "$(nb_lifecycle_field STATUS "$NOBRAND_BACKUP_RESTORE_META_FILE")" in
      applying|runtime-applying|rollback-roots)
        nobrand_backup_restore_recover_applying || return $?
        ;;
    esac
  fi
  ensure_manager_state_layout 1 || return 1
  nb_lifecycle_checkpoint repair partial-uninstall-state-layout || return 1
  install_self_script || return 1
  nb_lifecycle_checkpoint repair partial-uninstall-manager-ready || return 1
  if ! nb_authoritative_protocol_state_exists; then
    return 0
  fi
  # Restore only from the protocol state that survived the interrupted
  # uninstall. These routines are state-driven and do not synthesize a fresh
  # Mieru user, node, key, or credential.
  nobrand_restore_protocol_runtimes || return 1
  nb_lifecycle_checkpoint repair partial-uninstall-runtimes-reconciled || return 1
  nobrand_start_enabled_services || return 1
  nb_lifecycle_checkpoint repair partial-uninstall-services-reconciled || return 1
  if [ -e "$NOBRAND_SSH_STATE_FILE" ] || [ -L "$NOBRAND_SSH_STATE_FILE" ]; then
    ssh_tunnel_state_exists || return 1
    ssh_tunnel_state_identity_valid || return 1
    ssh_pending="$(ssh_tunnel_state_field pending_operation 2>/dev/null || true)"
    ssh_policy="$(ssh_tunnel_state_field policy_applied 2>/dev/null || true)"
    ssh_token="$(ssh_tunnel_state_field pending_watchdog_token 2>/dev/null || true)"
    ssh_pid="$(ssh_tunnel_state_field pending_watchdog_pid 2>/dev/null || true)"
    ssh_origin="$(ssh_tunnel_state_field pending_origin_connection 2>/dev/null || true)"
    if [ "$ssh_policy" = false ] && { [ -z "$ssh_pending" ] \
       || [ "$ssh_pending" = uninstall ] || [ "$ssh_pending" = unified-uninstall ]; } \
       && [ -z "$ssh_token" ] && [ -z "$ssh_pid" ] && [ -z "$ssh_origin" ]; then
      ssh_tunnel_restore_system_state || return 1
      ssh_pending="$(ssh_tunnel_state_field pending_operation 2>/dev/null || true)"
      ssh_policy="$(ssh_tunnel_state_field policy_applied 2>/dev/null || true)"
      ssh_token="$(ssh_tunnel_state_field pending_watchdog_token 2>/dev/null || true)"
      ssh_pid="$(ssh_tunnel_state_field pending_watchdog_pid 2>/dev/null || true)"
      ssh_origin="$(ssh_tunnel_state_field pending_origin_connection 2>/dev/null || true)"
    fi
    if [ "$ssh_pending" = restore ]; then
      ssh_tunnel_pending_tuple_valid "$ssh_pending" "$ssh_token" "$ssh_pid" \
        "$ssh_origin" "$ssh_policy" || return 1
      if [ "$ssh_token" = disabled ]; then
        ssh_tunnel_confirm_admin disabled || return 1
        ssh_pending="$(ssh_tunnel_state_field pending_operation 2>/dev/null || true)"
        ssh_policy="$(ssh_tunnel_state_field policy_applied 2>/dev/null || true)"
        ssh_token="$(ssh_tunnel_state_field pending_watchdog_token 2>/dev/null || true)"
        ssh_pid="$(ssh_tunnel_state_field pending_watchdog_pid 2>/dev/null || true)"
        ssh_origin="$(ssh_tunnel_state_field pending_origin_connection 2>/dev/null || true)"
      else
        ssh_tunnel_watchdog_claim_ready "$ssh_token" "$ssh_pid" || return 1
        ssh_tunnel_watchdog_prompt "$ssh_token" || return 1
        if declare -F nobrand_backup_restore_transaction_present >/dev/null 2>&1 \
           && nobrand_backup_restore_transaction_present; then
          nobrand_backup_restore_transaction_mark_ssh_pending || return 1
        fi
        nb_lifecycle_mark_phase partial-uninstall-ssh-confirmation-pending || return 1
        return 0
      fi
    fi
    [ -z "$ssh_pending" ] && [ -z "$ssh_token" ] && [ -z "$ssh_pid" ] \
      && [ -z "$ssh_origin" ] && [ "$ssh_policy" = true ] || return 1
    ssh_tunnel_cleanup_disarmed_watchdogs || return 1
  fi
  if [ -s "$MITA_STATE" ] || [ -s "$MITA_USERS_STATE" ]; then
    mita_v3_install_state_valid || return 1
    users_state_exists && [ "$(users_count)" -gt 0 ] || return 1
    verify_mita_running 1 || return 1
  fi
  nobrand_doctor || return 1
  nb_lifecycle_checkpoint repair partial-uninstall-state-validated || return 1
}

do_install_impl() {
  ensure_manager_state_layout 1
  nb_lifecycle_checkpoint "$NOBRAND_LIFECYCLE_OPERATION" state-layout || return 1

  local pm arch ver url tmp tx runtime_tx reinstall_existing=0 managed_existing=0
  pm="$(detect_pkg_manager)"
  arch="$(detect_arch)"
  ensure_management_dependencies "$pm"

  if mita_installed; then
    local cur
    cur="$(installed_version || true)"
    t "检测到已安装 mita ${cur:-未知版本}" "mita already installed (${cur:-unknown})"
    if mita_preservable_config_exists; then
      t '如需改端口/密码/协议，请选菜单「重新配置」或执行: nobrand mieru reconfigure' \
        'To change port/password/protocol, use menu Reconfigure or: nobrand mieru reconfigure'
      if ! confirm '继续重新下载安装包并保留当前用户/节点配置？[y/N]: ' \
        'Re-download the package and keep the current users/node config? [y/N]: ' n; then
        NOBRAND_INSTALL_CANCELLED=1
        return 0
      fi
      if [ "$USERNAME_CLI" -eq 1 ] || [ "$PASSWORD_CLI" -eq 1 ] \
         || [ "$PORT_CLI" -eq 1 ] || [ "$PORT_RANGE_CLI" -eq 1 ] \
         || [ "$PROTOCOL_CLI" -eq 1 ] || [ "$MTU_CLI" -eq 1 ] \
         || [ "$ADVERTISE_CLI" -eq 1 ] \
         || [ "$PROFILE_CLI" -eq 1 ] \
         || [ "$MULTIPLEXING_CLI" -eq 1 ] || [ "$HANDSHAKE_CLI" -eq 1 ] \
         || [ "$TRAFFIC_CLI" -eq 1 ] || [ "$LOW_ENTROPY_CLI" -eq 1 ]; then
        die "$(t '重装只保留当前配置；如需同时改节点参数，请使用 reconfigure' \
          'Reinstall preserves current config; use reconfigure to change node parameters')"
      fi
      reinstall_existing=1
      load_install_state
      if users_state_exists && [ "$(users_count)" -gt 0 ]; then
        managed_existing=1
        users_sync_primary_globals
      fi
    else
      warn "$(t '检测到上次安装未完成，且没有可恢复的 OneClick 状态；本次将重新生成配置并完成安装' \
        'Previous install is incomplete and has no recoverable OneClick state; configuration will be regenerated')"
      if ! confirm '继续修复并完成安装？[y/N]: ' \
        'Repair and complete the installation? [y/N]: ' n; then
        NOBRAND_INSTALL_CANCELLED=1
        return 0
      fi
    fi
  fi

  if [ "$reinstall_existing" -eq 1 ]; then
    ensure_config_noninteractive
  elif [ "$YES" -eq 1 ]; then
    mieru_prepare_noninteractive_ingress_endpoint || return 1
    ensure_config_noninteractive
  else
    collect_config_interactive
  fi
  [ -z "$PORT_RANGE" ] || die "$(t 'v2 用户专属实例不支持端口段，请改用单端口' \
    'v2 dedicated user instances do not support port ranges; use one port')"
  [ -z "$PORT" ] || PORT="$(normalize_uint "$PORT")"
  if [ "$reinstall_existing" -eq 0 ]; then
    ensure_install_port_available
  fi

  mieru_resolve_runtime "${MIERU_CHANNEL:-stable}" "${MIERU_VERSION:-}" "$pm" "$arch" \
    || die "$(t '无法解析并验证官方 Mieru release' \
      'Failed to resolve and validate the official Mieru release')"
  ver="$MIERU_RUNTIME_RESOLVED_VERSION"
  url="$MIERU_RUNTIME_RESOLVED_URL"
  tmp="$(mktemp_file)"
  download_package "$url" "$tmp" \
    "$MIERU_RUNTIME_RESOLVED_SHA256" \
    "$MIERU_RUNTIME_RESOLVED_CHECKSUM_URL"
  runtime_tx="$(mieru_runtime_snapshot)" || { rm -f "$tmp"; return 1; }
  if ! ( install_package "$tmp" "$pm" ) || ! mieru_assert_runtime_version "$ver"; then
    rm -f "$tmp"
    mieru_runtime_rollback "$runtime_tx" 2>/dev/null || true
    die "$(t 'Mieru runtime 安装验证失败，已恢复原有 managed runtime' \
      'Mieru runtime installation validation failed; the previous managed runtime was restored')"
    return 1
  fi
  rm -f "$tmp"
  mieru_runtime_commit "$runtime_tx" || return 1
  MIERU_VERSION="$ver"
  nb_lifecycle_checkpoint "$NOBRAND_LIFECYCLE_OPERATION" runtime-ready || return 1

  add_op_user "$OP_USER"
  warn_traffic_unsupported
  warn_low_entropy_unsupported
  if [ "$managed_existing" -eq 1 ]; then
    install_self_script
    admin_lock_acquire || return 1
    tx="$(users_tx_snapshot)" || { admin_lock_release; return 1; }
    isolated_stop_all
    if ! apply_users_config "$tx"; then
      admin_lock_release
      die "$(t '重装后二次应用专属实例失败；用户状态已回滚' \
        'Failed to reapply dedicated instances after reinstall; user state was rolled back')"
    fi
    if ! verify_mita_running; then
      users_tx_rollback "$tx" 1
      admin_lock_release
      die "$(t '重装后二次启动专属实例失败；用户状态已回滚' \
        'Dedicated instances failed after reinstall; user state was rolled back')"
    fi
    users_sync_primary_globals
    if ! save_install_state; then
      users_tx_rollback "$tx" 1
      admin_lock_release
      die "$(t '重装后保存安装状态失败；用户状态已回滚' \
        'Failed to save install state after reinstall; user state was rolled back')"
    fi
    users_tx_commit "$tx"
    admin_lock_release
  else
    if [ "$reinstall_existing" -eq 0 ]; then
      # 下载/安装期间端口可能被其它进程抢占，落盘前再验一次。
      ensure_install_port_available
    fi
    install_fresh_isolated
  fi
  nb_lifecycle_checkpoint "$NOBRAND_LIFECYCLE_OPERATION" state-committed || return 1

  offer_bbr_fq

  print_summary
}

do_reconfigure_impl() {
  local old_bindings new_bindings close_bindings desired_bindings binding_proto binding_port tx
  local old_port old_port_range old_protocol old_mtu old_mtu_policy old_user old_password
  local old_profile old_traffic old_seed old_low_entropy old_mux old_handshake
  local old_advertise_host old_advertise_port
  local client_state_changed=0
  local requested_port="$PORT" requested_port_range="$PORT_RANGE" requested_protocol="$PROTOCOL"
  local requested_user="$USERNAME" requested_password="$PASSWORD"
  local requested_advertise_host="$ADVERTISE_HOST" requested_advertise_port="$ADVERTISE_PORT"
  local requested_profile="$PROFILE" requested_mtu_request="$MTU_REQUEST"
  local requested_traffic="$TRAFFIC_PATTERN" requested_low_entropy="$LOW_ENTROPY_MODE"
  local requested_mux="$MULTIPLEXING" requested_handshake="$HANDSHAKE_MODE"
  local requested_port_cli="${PORT_CLI:-0}" requested_port_range_cli="${PORT_RANGE_CLI:-0}"
  local requested_protocol_cli="${PROTOCOL_CLI:-0}" requested_user_cli="${USERNAME_CLI:-0}"
  local requested_password_cli="${PASSWORD_CLI:-0}" requested_advertise_cli="${ADVERTISE_CLI:-0}"
  local requested_profile_cli="${PROFILE_CLI:-0}" requested_mtu_cli="${MTU_CLI:-0}"
  local requested_traffic_cli="${TRAFFIC_CLI:-0}" requested_low_entropy_cli="${LOW_ENTROPY_CLI:-0}"
  local requested_mux_cli="${MULTIPLEXING_CLI:-0}" requested_handshake_cli="${HANDSHAKE_CLI:-0}"
  PORT_CLI=0 PORT_RANGE_CLI=0 PROTOCOL_CLI=0 USERNAME_CLI=0 PASSWORD_CLI=0
  ADVERTISE_CLI=0 PROFILE_CLI=0 MTU_CLI=0 TRAFFIC_CLI=0 LOW_ENTROPY_CLI=0
  MULTIPLEXING_CLI=0 HANDSHAKE_CLI=0
  load_install_state
  if users_state_exists && [ "$(users_count)" -gt 0 ]; then
    users_sync_primary_globals
  fi
  old_port="$PORT"; old_port_range="$PORT_RANGE"; old_protocol="$PROTOCOL"
  old_mtu="$MTU"; old_mtu_policy="$MTU_POLICY"
  old_user="$USERNAME"; old_password="$PASSWORD"
  old_advertise_host="$ADVERTISE_HOST"; old_advertise_port="$ADVERTISE_PORT"
  old_profile="$PROFILE"
  old_traffic="$TRAFFIC_PATTERN"; old_seed="$TRAFFIC_SEED"
  old_low_entropy="$LOW_ENTROPY_MODE"; old_mux="$MULTIPLEXING"; old_handshake="$HANDSHAKE_MODE"
  PORT_CLI="$requested_port_cli"; PORT_RANGE_CLI="$requested_port_range_cli"
  PROTOCOL_CLI="$requested_protocol_cli"; USERNAME_CLI="$requested_user_cli"
  PASSWORD_CLI="$requested_password_cli"; ADVERTISE_CLI="$requested_advertise_cli"
  PROFILE_CLI="$requested_profile_cli"; MTU_CLI="$requested_mtu_cli"
  TRAFFIC_CLI="$requested_traffic_cli"; LOW_ENTROPY_CLI="$requested_low_entropy_cli"
  MULTIPLEXING_CLI="$requested_mux_cli"; HANDSHAKE_CLI="$requested_handshake_cli"
  [ "$PORT_CLI" -eq 0 ] || PORT="$requested_port"
  [ "$PORT_RANGE_CLI" -eq 0 ] || PORT_RANGE="$requested_port_range"
  [ "$PROTOCOL_CLI" -eq 0 ] || PROTOCOL="$requested_protocol"
  [ "$USERNAME_CLI" -eq 0 ] || USERNAME="$requested_user"
  [ "$PASSWORD_CLI" -eq 0 ] || PASSWORD="$requested_password"
  [ "$ADVERTISE_CLI" -eq 0 ] || { ADVERTISE_HOST="$requested_advertise_host"; ADVERTISE_PORT="$requested_advertise_port"; }
  [ "$PROFILE_CLI" -eq 0 ] || PROFILE="$requested_profile"
  [ "$MTU_CLI" -eq 0 ] || MTU_REQUEST="$requested_mtu_request"
  [ "$TRAFFIC_CLI" -eq 0 ] || TRAFFIC_PATTERN="$requested_traffic"
  [ "$LOW_ENTROPY_CLI" -eq 0 ] || LOW_ENTROPY_MODE="$requested_low_entropy"
  [ "$MULTIPLEXING_CLI" -eq 0 ] || MULTIPLEXING="$requested_mux"
  [ "$HANDSHAKE_CLI" -eq 0 ] || HANDSHAKE_MODE="$requested_handshake"
  users_isolated_mode || die "$(t 'schema v3 Mieru 状态必须使用 isolated-v2' \
    'Schema-v3 Mieru state must use isolated-v2')"
  old_bindings="$(multi_user_port_protocol_pairs)"

  if [ "$YES" -eq 1 ]; then
    load_config_from_mita
    ensure_config_noninteractive
  else
    collect_reconfigure_interactive
  fi
  [ -z "$PORT_RANGE" ] || die "$(t 'v2 用户专属实例不支持端口段，请改用单端口' \
    'v2 dedicated user instances do not support port ranges; use one port')"
  [ -z "$PORT" ] || PORT="$(normalize_uint "$PORT")"
  validate_advertise_endpoint || die "$(t '自定义客户端入口参数无效' \
    'Invalid custom client entry parameters')"
  [ -z "$ADVERTISE_PORT" ] || ADVERTISE_PORT="$(normalize_uint "$ADVERTISE_PORT")"

  if [ "${PROFILE_CLI:-0}" -eq 0 ] \
     && { [ "$PROTOCOL" != "$old_protocol" ] || [ "$MTU" != "$old_mtu" ] \
       || [ "$MULTIPLEXING" != "$old_mux" ] || [ "$HANDSHAKE_MODE" != "$old_handshake" ] \
       || [ "$TRAFFIC_PATTERN" != "$old_traffic" ] || [ "$LOW_ENTROPY_MODE" != "$old_low_entropy" ]; }; then
    PROFILE=custom
  fi
  profile_reconcile_metadata

  if [ "$ADVERTISE_HOST" != "$old_advertise_host" ] \
     || [ "$ADVERTISE_PORT" != "$old_advertise_port" ] \
     || [ "$MTU_POLICY" != "$old_mtu_policy" ] \
     || [ "$MULTIPLEXING" != "$old_mux" ] \
     || [ "$HANDSHAKE_MODE" != "$old_handshake" ] \
     || [ "$PROFILE" != "$old_profile" ]; then
    client_state_changed=1
  fi

  # 展示入口、客户端握手/多路复用和 MTU 策略文本不改变服务端运行配置。
  # 这些字段单独持久化，避免无意义地重启所有专属实例。
  if [ "$PORT" = "$old_port" ] && [ "$PORT_RANGE" = "$old_port_range" ] \
     && [ "$PROTOCOL" = "$old_protocol" ] && [ "$MTU" = "$old_mtu" ] \
     && [ "$USERNAME" = "$old_user" ] && [ "$PASSWORD" = "$old_password" ] \
     && [ "$TRAFFIC_PATTERN" = "$old_traffic" ] && [ "$TRAFFIC_SEED" = "$old_seed" ] \
     && [ "$LOW_ENTROPY_MODE" = "$old_low_entropy" ]; then
    if [ "$client_state_changed" -eq 0 ]; then
      msg ""
      t '未检测到配置变化；服务未重启' \
        'No configuration changes detected; services were not restarted'
      print_summary current
      return 0
    fi
    local state_only_auto_host=""
    admin_lock_acquire || return 1
    tx="$(users_tx_snapshot)" || { admin_lock_release; return 1; }
    if [ "$ADVERTISE_HOST" != "$old_advertise_host" ] \
       || [ "$ADVERTISE_PORT" != "$old_advertise_port" ]; then
      if ! users_set_advertise_endpoint "$old_user" "$ADVERTISE_HOST" "$ADVERTISE_PORT"; then
        users_tx_rollback "$tx" 0
        admin_lock_release
        return 1
      fi
    fi
    state_only_auto_host="$(public_ip 2>/dev/null || true)"
    if ! users_validate_state_file "$MITA_USERS_STATE" "$PROTOCOL" "$state_only_auto_host"; then
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
    client_exports_after_reconfigure "$old_user" "$old_protocol" "$old_mtu" \
      "$old_traffic" "$old_seed" "$old_low_entropy" "$old_mux" "$old_handshake" \
      2>/dev/null || true
    msg ""
    t '仅客户端参数已更新；服务器运行配置未变化，服务未重启' \
      'Client-only settings were updated; server runtime is unchanged and services were not restarted'
    print_summary current
    return 0
  fi

  if [ -n "${PORT:-}" ]; then
    desired_bindings="$({
      multi_user_port_protocol_pairs
      port_required_bindings "$PORT"
    } | sed '/^[[:space:]]*$/d' | LC_ALL=C sort -u)"
    while IFS='|' read -r binding_proto binding_port; do
      [ -n "$binding_proto" ] && [ -n "$binding_port" ] || continue
      printf '%s\n' "$old_bindings" | grep -qxF "${binding_proto}|${binding_port}" && continue
      if port_is_listening "$binding_port" "$binding_proto"; then
        warn "$(t "新监听 ${binding_proto}/${binding_port} 已被系统其它服务占用" \
          "New listener ${binding_proto}/${binding_port} is already used by another service")"
        port_listener_details "$binding_port" "$binding_proto"
        die "$(t '重新配置已取消，请选择其它端口或协议' \
          'Reconfigure cancelled; choose another port or protocol')"
      fi
    done <<<"$desired_bindings"
  fi

  warn_traffic_unsupported
  warn_low_entropy_unsupported
  # 多用户：协议全局更新；仅当用户显式改了主用户名/密码/端口时同步「主用户」
  # 主用户 = install-state 中的 USERNAME，找不到则 users[0]
  MULTI_USER_MODE=1
  admin_lock_acquire || return 1
  tx="$(users_tx_snapshot)" || { admin_lock_release; return 1; }
  _U_NAME="$USERNAME" _U_PASS="$PASSWORD" _U_PORT="$PORT" _U_PROTO="$PROTOCOL"
  _U_ADVERTISE_HOST="$ADVERTISE_HOST" _U_ADVERTISE_PORT="$ADVERTISE_PORT"
  _U_PRIMARY="${old_user}"
  users_py_locked '
import json, os, time
path = os.environ["MITA_USERS_STATE"]
d = json.load(open(path))
name = os.environ.get("_U_NAME") or ""
password = os.environ.get("_U_PASS") or ""
port = os.environ.get("_U_PORT") or ""
proto = os.environ.get("_U_PROTO") or "TCP"
advertise_host = os.environ.get("_U_ADVERTISE_HOST") or ""
advertise_port = os.environ.get("_U_ADVERTISE_PORT") or ""
primary = os.environ.get("_U_PRIMARY") or ""
users = d.get("users") or []
# 定位主用户：优先同名，否则第一个
idx = 0
for i, u in enumerate(users):
    if primary and u.get("name") == primary:
        idx = i
        break
if users:
    u = users[idx]
    old_port = int(u.get("port") or 0)
    if name and name != u.get("name"):
        # 避免与其它用户重名
        if any(x.get("name") == name for j, x in enumerate(users) if j != idx):
            raise SystemExit(2)
        u["name"] = name
    if password and not password.startswith("*"):
        u["password"] = password
    if port and str(port).isdigit():
        new_port = int(port)
        # 端口冲突则拒绝改端口（保留其它用户端口）
        if any(int(x.get("port") or 0) == new_port for j, x in enumerate(users) if j != idx):
            raise SystemExit(3)
        u["port"] = new_port
    u["advertise_host"] = advertise_host
    u["advertise_port"] = int(advertise_port) if advertise_port else ""
    u["updated_at"] = int(time.time())
d["protocol"] = proto
json.dump(d, open(path, "w"), indent=2)
' || {
    local prc=$?
    users_tx_rollback "$tx" 0
    admin_lock_release
    if [ "$prc" -eq 2 ]; then
      die "$(t '新用户名与其它用户冲突' 'New username conflicts with another user')"
    elif [ "$prc" -eq 3 ]; then
      die "$(t '新端口已被其它用户占用' 'New port already used by another user')"
    fi
    die "$(t '更新多用户状态失败' 'Failed to update multi-user state')"
  }
  if ! users_validate_state_file "$MITA_USERS_STATE" "$PROTOCOL"; then
    users_tx_rollback "$tx" 0
    admin_lock_release
    die "$(t '新协议/端口组合会造成监听端口或客户端展示入口冲突' \
      'The new protocol/port combination would collide between listeners or client display endpoints')"
  fi
  # 协议变更时所有用户 portBindings 随 PROTOCOL 重建；端口仅主用户可能变
  if ! apply_users_config "$tx"; then
    PORT="$old_port"; PORT_RANGE="$old_port_range"; PROTOCOL="$old_protocol"
    MTU="$old_mtu"; MTU_POLICY="$old_mtu_policy"; PROFILE="$old_profile"
    USERNAME="$old_user"; PASSWORD="$old_password"
    ADVERTISE_HOST="$old_advertise_host"; ADVERTISE_PORT="$old_advertise_port"
    TRAFFIC_PATTERN="$old_traffic"; TRAFFIC_SEED="$old_seed"
    LOW_ENTROPY_MODE="$old_low_entropy"; MULTIPLEXING="$old_mux"; HANDSHAKE_MODE="$old_handshake"
    reconcile_isolated_instances >/dev/null 2>&1 || true
    admin_lock_release
    return 1
  fi
  new_bindings="$(multi_user_port_protocol_pairs)"
  open_firewall_for_pairs "$new_bindings"
  if ! verify_mita_running || ! save_install_state; then
    PORT="$old_port"; PORT_RANGE="$old_port_range"; PROTOCOL="$old_protocol"
    MTU="$old_mtu"; MTU_POLICY="$old_mtu_policy"; PROFILE="$old_profile"
    USERNAME="$old_user"; PASSWORD="$old_password"
    ADVERTISE_HOST="$old_advertise_host"; ADVERTISE_PORT="$old_advertise_port"
    TRAFFIC_PATTERN="$old_traffic"; TRAFFIC_SEED="$old_seed"
    LOW_ENTROPY_MODE="$old_low_entropy"; MULTIPLEXING="$old_mux"; HANDSHAKE_MODE="$old_handshake"
    users_tx_rollback "$tx" 1
    open_firewall_for_pairs "$old_bindings"
    close_bindings="$(comm -23 \
      <(printf '%s\n' "$new_bindings" | sed '/^[[:space:]]*$/d' | LC_ALL=C sort -u) \
      <(printf '%s\n' "$old_bindings" | sed '/^[[:space:]]*$/d' | LC_ALL=C sort -u))"
    [ -z "$close_bindings" ] || close_firewall_for_bindings "$close_bindings"
    admin_lock_release
    return 1
  fi
  users_tx_commit "$tx"
  client_exports_after_reconfigure "$old_user" "$old_protocol" "$old_mtu" \
    "$old_traffic" "$old_seed" "$old_low_entropy" "$old_mux" "$old_handshake" \
    2>/dev/null || true
  close_bindings="$(comm -23 \
    <(printf '%s\n' "$old_bindings" | sed '/^[[:space:]]*$/d' | LC_ALL=C sort -u) \
    <(printf '%s\n' "$new_bindings" | sed '/^[[:space:]]*$/d' | LC_ALL=C sort -u))"
  [ -z "$close_bindings" ] || close_firewall_for_bindings "$close_bindings"
  admin_lock_release
  msg ""
  t '========== 重新配置完成 ==========' '========== Reconfigure complete =========='
  if users_state_exists && [ "$(users_count)" -gt 1 ]; then
    t '提示: 多用户模式下「重新配置」只改主用户凭据/端口与全局协议；其它用户端口不变' \
      'Note: multi-user reconfigure updates primary user + global protocol only; other ports unchanged'
  fi
  print_summary current
}

do_install() {
  local operation state manager_only=0 partial_uninstall_repair=0 lifecycle_phase="" rc=0
  local allow_transition=0 prior_tx_valid=0 prior_operation="" prior_status=""
  local prior_txid="" prior_started="" prior_phase="" prior_mieru_owned=0
  local prior_preserve_package=0 prior_preserve_user=0 prior_preserve_group=0
  local prior_preserve_shared=0
  NOBRAND_INSTALL_CANCELLED=0
  require_root
  require_linux
  require_cmd curl
  state="$(nb_classify_installation_state)" || return 1
  case "$state" in
    CLEAN|CURRENT_PARTIAL_INSTALL) operation=install ;;
    CURRENT_COMPLETE|CURRENT_PARTIAL_REPAIR|CURRENT_PARTIAL_UNINSTALL|LEGACY_SUPPORTED)
      operation=repair
      ;;
    LEGACY_UNSUPPORTED) nb_fail_legacy_state; return 1 ;;
    *) nb_fail_ambiguous_state; return 1 ;;
  esac
  nb_lifecycle_lock_acquire || return 1
  # Reclassify while holding the process lock so no competing lifecycle can
  # change the evidence between classification and the transaction write.
  state="$(nb_classify_installation_state)" || {
    nb_lifecycle_lock_release
    return 1
  }
  case "$state" in
    CLEAN|CURRENT_PARTIAL_INSTALL) operation=install ;;
    CURRENT_COMPLETE|CURRENT_PARTIAL_REPAIR|CURRENT_PARTIAL_UNINSTALL|LEGACY_SUPPORTED)
      operation=repair
      ;;
    LEGACY_UNSUPPORTED)
      nb_lifecycle_lock_release
      nb_fail_legacy_state
      return 1
      ;;
    *)
      nb_lifecycle_lock_release
      nb_fail_ambiguous_state
      return 1
      ;;
  esac
  if [ "$state" = CURRENT_PARTIAL_UNINSTALL ]; then
    partial_uninstall_repair=1
  elif [ "$state" = CURRENT_PARTIAL_REPAIR ] \
       && declare -F nobrand_backup_restore_transaction_present >/dev/null 2>&1 \
       && nobrand_backup_restore_transaction_present \
       && nobrand_backup_restore_transaction_valid; then
    partial_uninstall_repair=1
  elif [ "$state" = CURRENT_PARTIAL_REPAIR ] && nb_lifecycle_tx_valid \
       && [ "$(nb_lifecycle_field OPERATION)" = repair ]; then
    lifecycle_phase="$(nb_lifecycle_field LAST_COMPLETED_PHASE)"
    case "$lifecycle_phase" in partial-uninstall-*) partial_uninstall_repair=1 ;; esac
  fi
  if [ "$partial_uninstall_repair" -eq 1 ]; then
    lifecycle_phase='partial-uninstall-prepare'
    [ "$state" != CURRENT_PARTIAL_UNINSTALL ] || allow_transition=1
  else
    lifecycle_phase=prepare
  fi
  if nb_lifecycle_tx_valid; then
    prior_tx_valid=1
    prior_operation="$(nb_lifecycle_field OPERATION)"
    prior_status="$(nb_lifecycle_field STATUS)"
    prior_txid="$(nb_lifecycle_field TRANSACTION_ID)"
    prior_started="$(nb_lifecycle_field STARTED_AT)"
    prior_phase="$(nb_lifecycle_field LAST_COMPLETED_PHASE)"
    prior_mieru_owned="$(nb_lifecycle_field MIERU_OWNED)"
    prior_preserve_package="$(nb_lifecycle_field MIERU_PRESERVE_PACKAGE)"
    prior_preserve_user="$(nb_lifecycle_field MIERU_PRESERVE_USER)"
    prior_preserve_group="$(nb_lifecycle_field MIERU_PRESERVE_GROUP)"
    prior_preserve_shared="$(nb_lifecycle_field MIERU_PRESERVE_SHARED)"
  fi
  nb_lifecycle_begin "$operation" "$lifecycle_phase" 0 0 0 0 0 "$allow_transition" || {
    nb_lifecycle_lock_release
    return 1
  }
  if [ "$partial_uninstall_repair" -eq 1 ]; then
    # This is a global lifecycle recovery, not a request to create a fresh
    # Mieru node. State-backed protocols are reconciled individually; if no
    # authoritative node state survived, only manager/schema are repaired.
    manager_only=1
    nb_reconcile_partial_uninstall
    rc=$?
  else
    do_install_impl
    rc=$?
  fi
  if [ "${NOBRAND_INSTALL_CANCELLED:-0}" -eq 1 ]; then
    if [ "$prior_tx_valid" -eq 1 ]; then
      nb_lifecycle_write "$prior_operation" "$prior_status" "$prior_txid" \
        "$prior_started" "$prior_phase" "$prior_mieru_owned" \
        "$prior_preserve_package" "$prior_preserve_user" "$prior_preserve_group" \
        "$prior_preserve_shared" || {
          nb_lifecycle_lock_release
          return 1
        }
      NOBRAND_LIFECYCLE_ACTIVE=0
      NOBRAND_LIFECYCLE_OPERATION=""
    else
      nb_lifecycle_clear || {
        nb_lifecycle_lock_release
        return 1
      }
    fi
    nb_lifecycle_lock_release
    return 0
  fi
  if [ "$rc" -ne 0 ]; then
    nb_lifecycle_lock_release
    return "$rc"
  fi
  if [ "$partial_uninstall_repair" -eq 1 ] \
     && declare -F ssh_tunnel_state_exists >/dev/null 2>&1 \
     && ssh_tunnel_state_exists \
     && [ "$(ssh_tunnel_state_field pending_operation 2>/dev/null || true)" = restore ] \
     && [ -n "$(ssh_tunnel_state_field pending_watchdog_token 2>/dev/null || true)" ]; then
    nb_lifecycle_lock_release
    return 0
  fi
  if [ "$partial_uninstall_repair" -eq 1 ]; then
    nb_lifecycle_checkpoint "$operation" partial-uninstall-ready-to-validate || {
      rc=$?
      nb_lifecycle_lock_release
      return "$rc"
    }
  else
    nb_lifecycle_checkpoint "$operation" ready-to-validate || {
      rc=$?
      nb_lifecycle_lock_release
      return "$rc"
    }
  fi
  nb_lifecycle_validate_manager_repair || {
    nb_lifecycle_lock_release
    return 1
  }
  if [ "$manager_only" -eq 0 ]; then
    mita_v3_install_state_valid || {
      nb_lifecycle_lock_release
      return 1
    }
    if ! users_state_exists || [ "$(users_count)" -le 0 ]; then
      nb_lifecycle_lock_release
      return 1
    fi
    verify_mita_running 1 || {
      nb_lifecycle_lock_release
      return 1
    }
  fi
  nb_lifecycle_complete "$operation" || {
    nb_lifecycle_lock_release
    return 1
  }
  if declare -F nobrand_backup_restore_transaction_present >/dev/null 2>&1 \
     && nobrand_backup_restore_transaction_present; then
    nobrand_backup_restore_confirmation_finalize repair-accepted || {
      nb_lifecycle_lock_release
      return 1
    }
  fi
  nb_lifecycle_lock_release
}

do_reconfigure() {
  local rc=0
  require_root
  require_linux
  mita_installed || die "$(t 'mita 未安装，请先执行安装' 'mita is not installed; run install first')"
  nb_lifecycle_lock_acquire || return 1
  nb_lifecycle_begin repair prepare || {
    nb_lifecycle_lock_release
    return 1
  }
  ensure_manager_state_layout 1
  rc=$?
  if [ "$rc" -ne 0 ]; then
    nb_lifecycle_lock_release
    return "$rc"
  fi
  nb_lifecycle_checkpoint repair state-layout || {
    rc=$?
    nb_lifecycle_lock_release
    return "$rc"
  }
  install_self_script
  rc=$?
  if [ "$rc" -ne 0 ]; then
    nb_lifecycle_lock_release
    return "$rc"
  fi
  nb_lifecycle_checkpoint repair manager-ready || {
    rc=$?
    nb_lifecycle_lock_release
    return "$rc"
  }
  do_reconfigure_impl
  rc=$?
  if [ "$rc" -ne 0 ]; then
    nb_lifecycle_lock_release
    return "$rc"
  fi
  nb_lifecycle_checkpoint repair ready-to-validate || {
    rc=$?
    nb_lifecycle_lock_release
    return "$rc"
  }
  nb_lifecycle_validate_manager_repair || {
    nb_lifecycle_lock_release
    return 1
  }
  mita_v3_install_state_valid || {
    nb_lifecycle_lock_release
    return 1
  }
  verify_mita_running 1 || {
    nb_lifecycle_lock_release
    return 1
  }
  nb_lifecycle_complete repair || {
    nb_lifecycle_lock_release
    return 1
  }
  nb_lifecycle_lock_release
}

mieru_upgrade_rollback() {
  local runtime_tx="$1" users_tx="$2" old_channel="$3" old_version="$4" rc=0
  MIERU_CHANNEL="$old_channel"
  MIERU_VERSION="$old_version"
  mieru_runtime_rollback "$runtime_tx" || rc=1
  users_tx_rollback "$users_tx" 0
  isolated_stop_all 2>/dev/null || true
  reconcile_isolated_instances 2>/dev/null || rc=1
  verify_mita_running 2>/dev/null || rc=1
  return "$rc"
}

do_upgrade() {
  require_root
  require_linux
  require_cmd curl
  mita_installed || die "$(t 'mita 未安装，请先执行 fresh install' \
    'mita is not installed; perform a fresh install first')"
  mita_v3_install_state_valid || die "$(t 'schema v3 Mieru 安装状态缺失或损坏，拒绝升级' \
    'Schema-v3 Mieru install state is missing or invalid; refusing upgrade')"
  local pm arch ver url tmp tx runtime_tx cur state_channel state_version
  local requested_channel="$MIERU_CHANNEL" requested_version="$MIERU_VERSION"
  local requested_channel_cli="${MIERU_CHANNEL_CLI:-0}" requested_version_cli="${MIERU_VERSION_CLI:-0}"
  pm="$(detect_pkg_manager)"
  arch="$(detect_arch)"
  ensure_management_dependencies "$pm"
  MIERU_CHANNEL_CLI=0 MIERU_VERSION_CLI=0
  load_install_state
  state_channel="$MIERU_CHANNEL"
  state_version="$MIERU_VERSION"
  users_isolated_mode || die "$(t 'schema v3 Mieru 状态必须使用 isolated-v2' \
    'Schema-v3 Mieru state must use isolated-v2')"
  [ "$(users_count 2>/dev/null || printf 0)" -gt 0 ] \
    || die "$(t 'schema v3 Mieru 用户状态缺失，拒绝升级' \
      'Schema-v3 Mieru user state is missing; refusing upgrade')"
  MIERU_CHANNEL_CLI="$requested_channel_cli"; MIERU_VERSION_CLI="$requested_version_cli"
  if [ "$MIERU_CHANNEL_CLI" -eq 1 ]; then
    MIERU_CHANNEL="$requested_channel"
  fi
  if [ "$MIERU_VERSION_CLI" -eq 1 ]; then
    MIERU_VERSION="$requested_version"
  fi
  mieru_resolve_runtime "${MIERU_CHANNEL:-stable}" "${MIERU_VERSION:-}" "$pm" "$arch" \
    || die "$(t '无法解析并验证官方 Mieru release' \
      'Failed to resolve and validate the official Mieru release')"
  ver="$MIERU_RUNTIME_RESOLVED_VERSION"
  cur="$(installed_version || true)"
  if version_is_current "$cur" "$ver"; then
    MIERU_VERSION="$ver"
    install_self_script
    admin_lock_acquire || return 1
    tx="$(users_tx_snapshot)" || { admin_lock_release; return 1; }
    # 即使二进制已是最新版，也要让运行中的实例重新读取最新 unit/runner。
    isolated_stop_all
    if ! apply_users_config "$tx"; then
      admin_lock_release
      return 1
    fi
    users_tx_commit "$tx"
    admin_lock_release
    verify_mita_running
    [ -f "$MITA_STATE" ] && save_install_state
    t "管理脚本已更新至 v${SCRIPT_VERSION}（mita ${cur} 已满足 $(mieru_channel_label) 目标 ${ver}）" \
      "Manager script updated to v${SCRIPT_VERSION} (mita ${cur} satisfies $(mieru_channel_label) target ${ver})"
    [ "${MENU_MODE:-0}" -eq 1 ] && return 0
    exit 0
  fi
  if [ "${YES:-0}" -ne 1 ] && [ -t 0 ]; then
    t "已安装: ${cur:-未知}" "Installed: ${cur:-unknown}"
    t "最新稳定版: ${ver}" "Latest stable: ${ver}"
    if ! confirm '升级？[Y/n]: ' 'Upgrade? [Y/n]: ' y; then
      [ "${MENU_MODE:-0}" -eq 1 ] && return 0
      exit 0
    fi
  fi
  url="$MIERU_RUNTIME_RESOLVED_URL"
  tmp="$(mktemp_file)"
  download_package "$url" "$tmp" \
    "$MIERU_RUNTIME_RESOLVED_SHA256" \
    "$MIERU_RUNTIME_RESOLVED_CHECKSUM_URL"
  install_self_script
  admin_lock_acquire || { rm -f "$tmp"; return 1; }
  runtime_tx="$(mieru_runtime_snapshot)" \
    || { rm -f "$tmp"; admin_lock_release; return 1; }
  tx="$(users_tx_snapshot)" || {
    rm -f "$tmp"
    mieru_runtime_commit "$runtime_tx" 2>/dev/null || true
    admin_lock_release
    return 1
  }
  if ! ( install_package "$tmp" "$pm" ) || ! mieru_assert_runtime_version "$ver"; then
    rm -f "$tmp"
    mieru_upgrade_rollback "$runtime_tx" "$tx" "$state_channel" "$state_version" \
      || warn "$(t 'Mieru runtime 回滚后服务恢复不完整，请立即运行 doctor' \
        'Mieru services were not fully restored after runtime rollback; run doctor immediately')"
    admin_lock_release
    die "$(t 'Mieru runtime 升级验证失败，已恢复旧 runtime 与节点状态' \
      'Mieru runtime upgrade validation failed; the old runtime and node state were restored')"
    return 1
  fi
  rm -f "$tmp"
  MIERU_VERSION="$ver"
  isolated_stop_all
  if ! ( apply_users_config "$tx" ) \
     || ! verify_mita_running \
     || { [ ! -f "$MITA_STATE" ] || ! save_install_state; }; then
    mieru_upgrade_rollback "$runtime_tx" "$tx" "$state_channel" "$state_version" \
      || warn "$(t 'Mieru runtime 回滚后服务恢复不完整，请立即运行 doctor' \
        'Mieru services were not fully restored after runtime rollback; run doctor immediately')"
    admin_lock_release
    die "$(t 'Mieru 升级应用失败，已恢复旧 runtime、服务与状态' \
      'Mieru upgrade application failed; the old runtime, services, and state were restored')"
    return 1
  fi
  users_tx_commit "$tx"
  mieru_runtime_commit "$runtime_tx" || {
    admin_lock_release
    return 1
  }
  admin_lock_release
  t "已升级至 ${ver}（$(mieru_channel_label)）" \
    "Upgraded to ${ver} ($(mieru_channel_label))"
}

mita_nobrand_specific_residue_present() {
  local path pattern
  for path in "$MITA_BIN" "$MITA_MARKER" "$MITA_STATE" "$MITA_USERS_STATE" \
    "$MITA_INSTANCE_SYSTEMD_TEMPLATE" "$MITA_INSTANCE_TMPFILES" \
    "$MITA_INSTANCE_RUNNER" "$MITA_USERS_TIMER" "$MITA_USERS_SERVICE" \
    "$MITA_USERS_CRON" "$MITA_LOGROTATE_CONF" "$MITA_CLIENT_EXPORT_DIR"; do
    [ ! -e "$path" ] && [ ! -L "$path" ] || return 0
  done
  for pattern in "${MITA_INSTANCE_OPENRC_PREFIX}*" '/var/log/nobrand-mieru-*.log' \
    '/var/log/nobrand-mieru-*.err' '/root/nobrand_mieru_client_*.json'; do
    compgen -G "$pattern" >/dev/null 2>&1 && return 0
  done
  return 1
}

mita_uninstall_ledger_active() {
  nb_lifecycle_tx_valid \
    && [ "$(nb_lifecycle_field STATUS)" = in-progress ] \
    && [ "$(nb_lifecycle_field OPERATION)" = uninstall ] \
    && [ "$(nb_lifecycle_field MIERU_OWNED)" = 1 ]
}

mita_uninstall_ledger_capture() {
  local preserve_package=0 preserve_user=0 preserve_group=0 preserve_shared=0
  if nb_schema_v3_file_valid && [ -f "$MITA_MARKER" ] && [ ! -L "$MITA_MARKER" ]; then
    [ ! -f "$MITA_PRESERVE_PACKAGE_MARKER" ] || preserve_package=1
    [ ! -f "$MITA_PRESERVE_USER_MARKER" ] || preserve_user=1
    [ ! -f "$MITA_PRESERVE_GROUP_MARKER" ] || preserve_group=1
    [ ! -f "$MITA_PRESERVE_SHARED_MARKER" ] || preserve_shared=1
    printf '1|%s|%s|%s|%s' "$preserve_package" "$preserve_user" \
      "$preserve_group" "$preserve_shared"
  elif mita_nobrand_specific_residue_present; then
    # Exact NoBrand-named artifacts are positive ownership evidence, but a
    # missing authoritative marker cannot prove ownership of the upstream
    # package, shared directories, or generic mita account. Preserve them.
    printf '1|1|1|1|1'
  else
    printf '0|0|0|0|0'
  fi
}

mita_uninstall_target_present() {
  mita_uninstall_ledger_active && return 0
  nb_schema_v3_file_valid || return 1
  installed_by_oneclick \
    || [ -s "$MITA_USERS_STATE" ] \
    || [ -s "$MITA_STATE" ] \
    || [ -x "$MITA_BIN" ] \
    || [ -e "$MITA_INSTANCE_SYSTEMD_TEMPLATE" ] \
    || [ -e "$MITA_USERS_TIMER" ] \
    || [ -e "$MITA_USERS_SERVICE" ]
}

stop_mita_for_uninstall() {
  local sm
  STAGE="停止 mita 服务"
  isolated_stop_all
  tc_clear_owned_filters 2>/dev/null || true
  sm="$(service_manager)"
  case "$sm" in
    systemd)
      run systemctl disable --now nobrand-mieru-users-scan.timer \
        nobrand-mieru-users-scan.service nobrand-mieru-tc-restore.service 2>/dev/null || true
      ;;
    openrc) ;;
  esac
}

remove_mita_common() {
  STAGE="删除 mita 文件与账号"
  local preserve_package="${UNINSTALL_PRESERVE_PACKAGE:-0}"
  local preserve_user="${UNINSTALL_PRESERVE_USER:-0}"
  local preserve_group="${UNINSTALL_PRESERVE_GROUP:-0}"
  local preserve_shared="${UNINSTALL_PRESERVE_SHARED:-0}"
  run rm -f /var/log/nobrand-mieru-*.log /var/log/nobrand-mieru-*.err
  run rm -f /root/nobrand_mieru_client_*.json 2>/dev/null || true
  run rm -rf "$MITA_CLIENT_EXPORT_DIR"
  remove_users_scheduler 2>/dev/null || true
  run rm -f "$MITA_LOGROTATE_CONF" 2>/dev/null || true
  run rm -rf "$MITA_INSTANCES_DIR" "$MITA_INSTANCE_RUN_DIR" \
    "$MITA_INSTANCE_METRICS_DIR" "$MITA_USERS_BACKUP_DIR" "$MITA_MANAGER_STATE_DIR"
  if [ "$preserve_shared" -eq 0 ]; then
    run rm -rf /etc/mita /var/lib/mita /run/mita /var/run/mita /var/run/mita.sock
  fi
  run rm -f "$MITA_USERS_STATE" "$MITA_USERS_LOCK" "$MITA_ADMIN_LOCK" \
    "$MITA_FIREWALL_OWNED_STATE" "$TC_OWNED_STATE" "$MITA_STATE"
  run rm -f "$MITA_BIN" "$MITA_MARKER"
  run rm -f "$MITA_INSTANCE_SYSTEMD_TEMPLATE" "$MITA_INSTANCE_TMPFILES" \
    "$MITA_INSTANCE_RUNNER" "${MITA_INSTANCE_OPENRC_PREFIX}"*
  run rm -f "$MITA_USERS_LOG" 2>/dev/null || true
  if [ -d /etc/systemd/system ]; then
    find /etc/systemd/system -type l \
      \( -name 'nobrand-mieru@*.service' -o -name 'nobrand-mieru-users-scan.timer' \
         -o -name 'nobrand-mieru-tc-restore.service' \) -delete 2>/dev/null || true
  fi
  run systemctl daemon-reload 2>/dev/null || true
  run systemctl reset-failed 2>/dev/null || true
  if [ "$preserve_user" -eq 0 ] && _has_user mita; then
    run deluser mita 2>/dev/null || run userdel mita 2>/dev/null || true
  fi
  if [ "$preserve_group" -eq 0 ] && _has_group mita; then
    run delgroup mita 2>/dev/null || run groupdel mita 2>/dev/null || true
  fi
}

verify_mita_uninstalled() {
  STAGE="验收卸载结果"
  local failed=0 path pattern save_cmd
  local preserve_package="${UNINSTALL_PRESERVE_PACKAGE:-0}"
  local preserve_user="${UNINSTALL_PRESERVE_USER:-0}"
  local preserve_group="${UNINSTALL_PRESERVE_GROUP:-0}"
  local preserve_shared="${UNINSTALL_PRESERVE_SHARED:-0}"
  if [ "$preserve_package" -eq 0 ] \
     && command -v dpkg-query >/dev/null 2>&1 \
     && dpkg-query -W -f='${db:Status-Abbrev}' mita 2>/dev/null | grep -q .; then
    warn "$(t '卸载验收失败: Debian 软件包记录仍存在' \
      'Uninstall verification failed: Debian package record remains')"
    failed=1
  fi
  if [ "$preserve_package" -eq 0 ] \
     && command -v rpm >/dev/null 2>&1 && rpm -q mita >/dev/null 2>&1; then
    warn "$(t '卸载验收失败: RPM 软件包仍存在' \
      'Uninstall verification failed: RPM package remains')"
    failed=1
  fi
  for path in \
    "$MITA_MANAGER_STATE_DIR" \
    "$MITA_INSTANCES_DIR" "$MITA_INSTANCE_RUN_DIR" "$MITA_INSTANCE_METRICS_DIR" \
    "$MITA_USERS_STATE" "$MITA_USERS_LOCK" "$MITA_USERS_BACKUP_DIR" \
    "$MITA_ADMIN_LOCK" "$MITA_FIREWALL_OWNED_STATE" "$TC_OWNED_STATE" \
    "$MITA_BIN" "$MITA_CLIENT_EXPORT_DIR" \
    "$MITA_INSTANCE_SYSTEMD_TEMPLATE" "$MITA_INSTANCE_TMPFILES" "$MITA_INSTANCE_RUNNER" \
    "$MITA_USERS_TIMER" "$MITA_USERS_SERVICE" "$MITA_USERS_CRON" "$MITA_LOGROTATE_CONF" \
    "$MITA_USERS_LOG" \
    "$BBR_STATE_FILE" "$BBR_BACKUP_FILE"; do
    if [ -e "$path" ] || [ -L "$path" ]; then
      warn "$(t "卸载残留: ${path}" "Uninstall residue: ${path}")"
      failed=1
    fi
  done
  if [ "$preserve_shared" -eq 0 ]; then
    for path in /etc/mita /var/lib/mita /run/mita /var/run/mita; do
      if [ -e "$path" ] || [ -L "$path" ]; then
        warn "$(t "卸载残留: ${path}" "Uninstall residue: ${path}")"
        failed=1
      fi
    done
  fi
  for pattern in \
    "${MITA_INSTANCE_OPENRC_PREFIX}*" '/var/log/nobrand-mieru-*.log' \
    '/var/log/nobrand-mieru-*.err' '/root/nobrand_mieru_client_*.json'; do
    if compgen -G "$pattern" >/dev/null 2>&1; then
      warn "$(t "卸载仍有匹配残留: ${pattern}" "Uninstall residue matches: ${pattern}")"
      failed=1
    fi
  done
  local systemd_link_names=( -name 'nobrand-mieru@*.service' \
    -o -name 'nobrand-mieru-users-scan.timer' -o -name 'nobrand-mieru-tc-restore.service' )
  if [ -d /etc/systemd/system ] \
     && find /etc/systemd/system -type l \( "${systemd_link_names[@]}" \) \
       -print -quit 2>/dev/null | grep -q .; then
    warn "$(t '卸载残留: systemd wants 目录仍有 mita 符号链接' \
      'Uninstall residue: systemd wants directories still contain mita symlinks')"
    failed=1
  fi
  if { [ "$preserve_user" -eq 0 ] && _has_user mita; } \
     || { [ "$preserve_group" -eq 0 ] && _has_group mita; }; then
    warn "$(t '卸载残留: mita 系统用户或用户组仍存在' \
      'Uninstall residue: mita system user or group remains')"
    failed=1
  fi
  for save_cmd in iptables-save ip6tables-save; do
    if command -v "$save_cmd" >/dev/null 2>&1 \
       && "$save_cmd" 2>/dev/null | grep -q -- "$MITA_FIREWALL_COMMENT"; then
      warn "$(t "卸载残留: ${save_cmd} 中仍有 ${MITA_FIREWALL_COMMENT} 规则" \
        "Uninstall residue: ${save_cmd} still contains ${MITA_FIREWALL_COMMENT} rules")"
      failed=1
    fi
  done
  if [ -e "$NOBRAND_INGRESS_FIREWALL_STATE_FILE" ]; then
    if ! nb_strict_firewall_state_valid "$NOBRAND_INGRESS_FIREWALL_STATE_FILE"; then
      warn "$(t '卸载验收失败: Strict Ingress 防火墙状态无效' \
        'Uninstall verification failed: Strict Ingress firewall state is invalid')"
      failed=1
    elif jq -e 'any(.rules[]; .owner | startswith("mieru:"))' \
      "$NOBRAND_INGRESS_FIREWALL_STATE_FILE" >/dev/null; then
      warn "$(t '卸载残留: Strict Ingress 中仍有 Mieru 所有者规则' \
        'Uninstall residue: Strict Ingress still contains Mieru-owned rules')"
      failed=1
    fi
  fi
  [ "$failed" -eq 0 ]
}

do_uninstall() {
  local ledger_owned=0
  require_root
  UNINSTALL_CANCELLED=0
  UNINSTALL_PRESERVE_EXTERNAL=0
  UNINSTALL_PRESERVE_PACKAGE=0
  UNINSTALL_PRESERVE_USER=0
  UNINSTALL_PRESERVE_GROUP=0
  UNINSTALL_PRESERVE_SHARED=0
  mita_uninstall_target_present \
    || die "$(t '未检测到 mita 或 OneClick 残留，无需卸载' \
      'No mita or OneClick residue detected; nothing to uninstall')"
  mita_uninstall_ledger_active && ledger_owned=1
  if ! installed_by_oneclick && [ "$ledger_owned" -ne 1 ]; then
    die "$(t '缺少 schema v3 Mieru ownership 标记，拒绝清理未知资源' \
      'Schema-v3 Mieru ownership marker is missing; refusing to clean unknown resources')"
  fi
  if ! confirm '确认仅卸载 NoBrand 3 管理的 Mieru 协议资源？[y/N]: ' \
    'Uninstall only NoBrand-3-managed Mieru protocol resources? [y/N]: ' n; then
    if [ "${MENU_MODE:-0}" -eq 1 ]; then
      UNINSTALL_CANCELLED=1
      return 0
    fi
    exit 0
  fi
  if [ "$ledger_owned" -eq 1 ]; then
    UNINSTALL_PRESERVE_PACKAGE="$(nb_lifecycle_field MIERU_PRESERVE_PACKAGE)"
    UNINSTALL_PRESERVE_USER="$(nb_lifecycle_field MIERU_PRESERVE_USER)"
    UNINSTALL_PRESERVE_GROUP="$(nb_lifecycle_field MIERU_PRESERVE_GROUP)"
    UNINSTALL_PRESERVE_SHARED="$(nb_lifecycle_field MIERU_PRESERVE_SHARED)"
    if [ "$UNINSTALL_PRESERVE_PACKAGE" -eq 1 ] \
       || [ "$UNINSTALL_PRESERVE_USER" -eq 1 ] \
       || [ "$UNINSTALL_PRESERVE_GROUP" -eq 1 ] \
       || [ "$UNINSTALL_PRESERVE_SHARED" -eq 1 ]; then
      UNINSTALL_PRESERVE_EXTERNAL=1
    fi
  elif preexisting_mita_resources_recorded; then
    UNINSTALL_PRESERVE_EXTERNAL=1
    [ -f "$MITA_PRESERVE_PACKAGE_MARKER" ] && UNINSTALL_PRESERVE_PACKAGE=1
    [ -f "$MITA_PRESERVE_USER_MARKER" ] && UNINSTALL_PRESERVE_USER=1
    [ -f "$MITA_PRESERVE_GROUP_MARKER" ] && UNINSTALL_PRESERVE_GROUP=1
    [ -f "$MITA_PRESERVE_SHARED_MARKER" ] && UNINSTALL_PRESERVE_SHARED=1
    warn "$(t '检测到安装前已存在的 mita 包或系统账号；将按记录分别保留外部资源，预存包的公共目录也会保留，并保持服务停止。' \
      'A pre-existing mita package or system account was recorded; each external resource will be preserved separately, including shared directories for a pre-existing package, and left stopped.')"
  fi
  local pm
  # 必须在停止服务、清理规则和卸载软件包之前确认 BBR 文件仍由本脚本拥有，
  # 避免因人工修改触发保护后留下半卸载状态。
  if ! restore_owned_bbr_fq; then
    bail "$(t 'BBR/FQ 配置已被外部修改，卸载已在删除任何 mita 文件前停止' \
      'BBR/FQ configuration was modified externally; uninstall stopped before removing any mita files')" || return 1
    return 1
  fi
  pm="$(detect_pkg_manager)"
  stop_mita_for_uninstall
  STAGE="清理防火墙规则"
  firewall_clear_all_owned
  STAGE="清理 Strict Ingress 防火墙规则"
  mieru_clear_strict_firewall
  STAGE="卸载 mita 软件包"
  if [ "$UNINSTALL_PRESERVE_PACKAGE" -eq 0 ]; then
    case "$pm" in
      deb)
        if dpkg-query -W mita >/dev/null 2>&1; then
          run dpkg -P mita
        fi
        ;;
      rpm)
        if rpm -q mita >/dev/null 2>&1; then
          run rpm -e mita
        fi
        ;;
      alpine) ;;
    esac
  fi
  remove_mita_common
  if ! verify_mita_uninstalled; then
    warn "$(t '卸载未完全通过验收；已保留上方残留信息，请修复后重试' \
      'Uninstall did not pass verification; review the residue above and retry')"
    return 1
  fi
  if [ "$UNINSTALL_PRESERVE_EXTERNAL" -eq 1 ]; then
    t 'NoBrand 管理的 Mieru 文件已卸载；安装前存在的 mita 外部资源已保留。' \
      'NoBrand-managed Mieru files were removed; pre-existing mita resources were preserved.'
  else
    t 'NoBrand 3 管理的 Mieru runtime 与协议资源已卸载' \
      'The NoBrand-3-managed Mieru runtime and protocol resources were removed'
  fi
  t 'Mieru 协议资源已卸载；nobrand/nb 管理命令仍保留。' \
    'Mieru protocol resources were removed; nobrand/nb management commands remain.'
}
