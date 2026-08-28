# ---------- NoBrand Common Core: 入口、节点聚合、状态、Doctor、备份 ----------

nobrand_print_banner() {
  msg ""
  msg '========================================'
  printf '          %s v%s\n' "$SCRIPT_NAME" "$SCRIPT_VERSION"
  msg '========================================'
  t "Author: ${SCRIPT_AUTHOR}" "Author: ${SCRIPT_AUTHOR}"
}

nobrand_version() {
  printf '%s %s\nAuthor: %s\n' "$SCRIPT_NAME" "$SCRIPT_VERSION" "$SCRIPT_AUTHOR"
}

nobrand_usage() {
  cat <<'EOF'
NoBrand-OneClick — Mieru / Snell v4-v5 / Hysteria2 / VLESS + FinalMask + Sudoku (TCP)

用法:
  nobrand                         打开统一菜单
  nobrand --version               显示产品版本与作者
  nobrand status                  综合状态
  nobrand nodes [--protocol P]    查看全部或指定协议节点
  nobrand doctor                  综合诊断（默认不输出 secret）
  nobrand backup create [FILE]    备份 NoBrand Snell/HY2/VLESS state 与配置
  nobrand backup restore FILE     恢复 NoBrand 备份
  nobrand uninstall [-y]          只删除 NoBrand 的 Snell/HY2/VLESS/Common 内容

  nobrand mieru <原 mita 子命令与参数>
  nobrand snell install --name NAME [--version 5|4] [--port PORT] [--quic on|off]
      [--advertise-host HOST --advertise-port PORT | --advertise-auto] [-y]
  nobrand snell show|status|doctor|start|stop|restart|remove [--name NAME]
  nobrand snell set-quic --name NAME --quic on|off [-y]
  nobrand snell set-endpoint --name NAME
      [--advertise-host HOST --advertise-port PORT | --advertise-auto]

  nobrand hy2 install [--port PORT] [--sni SNI]
      [--advertise-host HOST --advertise-port PORT | --advertise-auto] [-y]
  nobrand hy2 show|status|doctor|start|stop|restart|remove
  nobrand hy2 set-endpoint
      [--advertise-host HOST --advertise-port PORT | --advertise-auto]

  nobrand vless-sudoku install [--port PORT]
      [--advertise-host HOST --advertise-port PORT | --advertise-auto] [-y]
  nobrand vless-sudoku show|status|doctor|smoke|start|stop|restart|remove
  nobrand vless-sudoku set-endpoint
      [--advertise-host HOST --advertise-port PORT | --advertise-auto]

说明:
  - Snell 只支持 v5（默认/推荐）与 v4（兼容）。
  - Snell v5 QUIC 默认关闭；--quic on 才让 NoBrand 管理同号 UDP firewall ownership。
  - 官方 v5 runtime 即使 QUIC 关闭也可能监听同号 UDP；本地 socket 不等于公网 QUIC 已启用。
  - Display Endpoint 只影响客户端输出，不创建 DNAT/IPLC 转发，也不改 listener。
  - 非交互 -y 必须明确给出完整 Display Endpoint 或 --advertise-auto。
  - VLESS Sudoku = plain VLESS + FinalMask(sudoku) + TCP。
  - VLESS Encryption: NOT USED；不调用密钥生成子命令，不保存加密密钥。
EOF
}

nobrand_install_manager_script() {
  local source_path="" source_real="" destination_real=""
  if [ "${DRY_RUN:-0}" -eq 1 ]; then
    msg "[dry-run] install NoBrand manager and nobrand/nb commands"
    return 0
  fi
  if [ -n "${BASH_SOURCE[0]:-}" ] && [ -r "${BASH_SOURCE[0]}" ] \
     && grep -qxF "SCRIPT_NAME=\"NoBrand-OneClick\"" "${BASH_SOURCE[0]}" 2>/dev/null; then
    source_path="${BASH_SOURCE[0]}"
  elif [ -r "$INSTALL_SCRIPT_PATH" ] \
       && grep -qxF "SCRIPT_NAME=\"NoBrand-OneClick\"" "$INSTALL_SCRIPT_PATH" 2>/dev/null; then
    source_path="$INSTALL_SCRIPT_PATH"
  elif [ -r "$NOBRAND_INSTALL_SCRIPT_PATH" ]; then
    source_path="$NOBRAND_INSTALL_SCRIPT_PATH"
  fi
  [ -n "$source_path" ] || {
    warn "$(t '找不到当前 NoBrand 单文件安装器，未安装统一快捷命令' \
      'Current NoBrand single-file installer not found; unified shortcuts were not installed')"
    return 1
  }
  source_real="$(readlink -f "$source_path" 2>/dev/null || realpath "$source_path" 2>/dev/null || printf '%s' "$source_path")"
  destination_real="$(readlink -f "$NOBRAND_INSTALL_SCRIPT_PATH" 2>/dev/null \
    || realpath "$NOBRAND_INSTALL_SCRIPT_PATH" 2>/dev/null || printf '%s' "$NOBRAND_INSTALL_SCRIPT_PATH")"
  if [ "$source_real" != "$destination_real" ]; then
    install -m 0755 "$source_path" "$NOBRAND_INSTALL_SCRIPT_PATH" || return 1
  else
    chmod 0755 "$NOBRAND_INSTALL_SCRIPT_PATH" || return 1
  fi
  local wrapper
  wrapper="$(mktemp_file .sh)" || return 1
  cat >"$wrapper" <<EOF
#!/usr/bin/env bash
exec ${NOBRAND_INSTALL_SCRIPT_PATH} "\$@"
EOF
  chmod 0755 "$wrapper" || { rm -f "$wrapper"; return 1; }
  install -m 0755 "$wrapper" "$NOBRAND_COMMAND_PATH" || { rm -f "$wrapper"; return 1; }
  install -m 0755 "$wrapper" "$NOBRAND_SHORT_COMMAND_PATH" || { rm -f "$wrapper"; return 1; }
  rm -f "$wrapper"
}

nb_mieru_instance_running() {
  local instance_id="$1" transport="$2" port="$3" unit service
  unit="mita-oneclick@${instance_id}.service"
  service="mita-oneclick-${instance_id}"
  nb_service_is_active "$unit" "$service" || return 1
  case "$transport" in
    BOTH) nb_port_is_listening TCP "$port" && nb_port_is_listening UDP "$((port + 1))" ;;
    *) nb_port_is_listening "$transport" "$port" ;;
  esac
}

# protocol|name|display endpoint|status|transport
nb_mieru_legacy_node_rows() {
  local values name port protocol advertise_host advertise_port auto_host effective_host effective_port status
  [ -s "$MITA_STATE" ] && state_file_is_secure "$MITA_STATE" || return 0
  values="$(
    PORT="" PROTOCOL="TCP" ADVERTISE_HOST="" ADVERTISE_PORT="" USERNAME="legacy"
    # shellcheck disable=SC1090
    source "$MITA_STATE" 2>/dev/null || exit 0
    nb_valid_port "${PORT:-}" || exit 0
    case "${PROTOCOL:-TCP}" in TCP|UDP|BOTH) ;; *) exit 0 ;; esac
    printf '%s\t%s\t%s\t%s\t%s' "${USERNAME:-legacy}" "$PORT" "$PROTOCOL" \
      "${ADVERTISE_HOST:-}" "${ADVERTISE_PORT:-}"
  )"
  [ -n "$values" ] || return 0
  IFS=$'\t' read -r name port protocol advertise_host advertise_port <<<"$values"
  auto_host="$(public_ip 2>/dev/null || printf 'YOUR_SERVER_IP')"
  effective_host="${advertise_host:-$auto_host}"
  effective_port="${advertise_port:-$port}"
  status=Stopped
  if nb_service_is_active mita.service mita; then
    case "$protocol" in
      TCP|UDP) nb_port_is_listening "$protocol" "$port" && status=Running ;;
      BOTH) nb_port_is_listening TCP "$port" && nb_port_is_listening UDP "$((port + 1))" && status=Running ;;
    esac
  fi
  if [ "$protocol" = BOTH ]; then
    printf 'Mieru/BOTH|%s|%s:%s (TCP), %s:%s (UDP)|%s|BOTH\n' \
      "$name" "$effective_host" "$effective_port" "$effective_host" "$((effective_port + 1))" "$status"
  else
    printf 'Mieru/%s|%s|%s:%s|%s|%s\n' \
      "$protocol" "$name" "$effective_host" "$effective_port" "$status" "$protocol"
  fi
}

nb_mieru_node_rows() {
  local auto_host instance_id name port protocol advertise_host advertise_port effective_host effective_port status
  if [ ! -s "$MITA_USERS_STATE" ]; then
    nb_mieru_legacy_node_rows
    return 0
  fi
  command -v python3 >/dev/null 2>&1 || return 0
  auto_host="$(public_ip 2>/dev/null || printf 'YOUR_SERVER_IP')"
  while IFS=$'\t' read -r instance_id name port protocol advertise_host advertise_port; do
    [ -n "$name" ] || continue
    effective_host="${advertise_host:-$auto_host}"
    effective_port="${advertise_port:-$port}"
    status=Stopped
    nb_mieru_instance_running "$instance_id" "$protocol" "$port" && status=Running
    if [ "$protocol" = BOTH ]; then
      printf 'Mieru/BOTH|%s|%s:%s (TCP), %s:%s (UDP)|%s|BOTH\n' \
        "$name" "$effective_host" "$effective_port" "$effective_host" "$((effective_port + 1))" "$status"
    else
      printf 'Mieru/%s|%s|%s:%s|%s|%s\n' \
        "$protocol" "$name" "$effective_host" "$effective_port" "$status" "$protocol"
    fi
  done < <(python3 - "$MITA_USERS_STATE" <<'PY'
import json,sys
try:
    state=json.load(open(sys.argv[1], encoding="utf-8"))
except Exception:
    raise SystemExit(0)
protocol=str(state.get("protocol") or "TCP").upper()
for user in state.get("users") or []:
    print("\t".join(str(v or "") for v in (
        user.get("instance_id"), user.get("name"), user.get("port"), protocol,
        user.get("advertise_host"), user.get("advertise_port"))))
PY
  )
}

nb_all_node_rows() {
  local filter
  filter="$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')"
  case "$filter" in
    ""|all)
      nb_mieru_node_rows
      snell_node_rows
      hysteria2_node_rows
      vless_sudoku_node_rows
      ;;
    mieru) nb_mieru_node_rows ;;
    snell) snell_node_rows ;;
    hy2|hysteria2) hysteria2_node_rows ;;
    vless-sudoku|sudoku|vless) vless_sudoku_node_rows ;;
    *) die "--protocol 只支持 mieru、snell、hy2、vless-sudoku" ;;
  esac
}

nobrand_nodes() {
  local rows protocol name endpoint status transport
  rows="$(nb_all_node_rows "${NOBRAND_PROTOCOL_FILTER:-}")"
  nobrand_print_banner
  msg ""
  t '协议              节点              客户端入口                              状态' \
    'Protocol          Node              Client endpoint                         Status'
  msg '--------------------------------------------------------------------------------------'
  if [ -z "$rows" ]; then
    t '暂无持久化节点。' 'No persistent nodes.'
    return 0
  fi
  while IFS='|' read -r protocol name endpoint status transport; do
    [ -n "$protocol" ] || continue
    printf '%-17s %-17s %-40s %s\n' "$protocol" "$name" "$endpoint" "$status"
  done <<<"$rows"
}

nobrand_status() {
  local rows protocol _name _endpoint status _transport
  local mieru_total=0 mieru_running=0 snell_total=0 snell_running=0 hy2_total=0 hy2_running=0
  local vless_total=0 vless_running=0 vless_port=""
  rows="$(nb_all_node_rows)"
  while IFS='|' read -r protocol _name _endpoint status _transport; do
    case "$protocol" in
      Mieru/*) mieru_total=$((mieru_total + 1)); [ "$status" != Running ] || mieru_running=$((mieru_running + 1)) ;;
      Snell*) snell_total=$((snell_total + 1)); [ "$status" != Running ] || snell_running=$((snell_running + 1)) ;;
      Hysteria2) hy2_total=$((hy2_total + 1)); [ "$status" != Running ] || hy2_running=$((hy2_running + 1)) ;;
      VLESS/Sudoku)
        vless_total=$((vless_total + 1))
        [ "$status" != Running ] || vless_running=$((vless_running + 1))
        vless_port="$(vless_sudoku_state_field listen_port 2>/dev/null || true)"
        ;;
    esac
  done <<<"$rows"
  nobrand_print_banner
  msg ""
  printf 'Mieru\n  Installed: %s\n  Users: %s\n  Running: %s/%s\n' \
    "$([ "$mieru_total" -gt 0 ] && printf yes || printf no)" "$mieru_total" "$mieru_running" "$mieru_total"
  printf 'Snell\n  Instances: %s\n  Running: %s/%s\n' "$snell_total" "$snell_running" "$snell_total"
  printf 'Hysteria2\n  Installed: %s\n  Running: %s\n' \
    "$([ "$hy2_total" -gt 0 ] && printf yes || printf no)" \
    "$([ "$hy2_running" -gt 0 ] && printf yes || printf no)"
  printf 'VLESS/Sudoku\n  Installed: %s\n  Running: %s\n  Port: %s\n' \
    "$([ "$vless_total" -gt 0 ] && printf yes || printf no)" \
    "$([ "$vless_running" -gt 0 ] && printf yes || printf no)" \
    "${vless_port:--}"
}

nb_doctor_line() {
  local level="$1"
  shift
  printf '[%s] %s\n' "$level" "$*"
}

nobrand_doctor_common() {
  local failed=0 manager arch_value
  [ "$(id -u 2>/dev/null || printf 1)" -eq 0 ] \
    && nb_doctor_line PASS 'root' || { nb_doctor_line FAIL '需要 root'; failed=1; }
  [ "$(uname -s 2>/dev/null || true)" = Linux ] \
    && nb_doctor_line PASS 'Linux' || { nb_doctor_line FAIL '仅支持 Linux'; failed=1; }
  arch_value="$(uname -m 2>/dev/null || printf unknown)"
  case "$arch_value" in
    x86_64|amd64|aarch64|arm64) nb_doctor_line PASS "arch=${arch_value}" ;;
    *) nb_doctor_line WARN "arch=${arch_value}（Snell 可能不支持）" ;;
  esac
  [ -d "$NOBRAND_STATE_DIR" ] && [ -w "$NOBRAND_STATE_DIR" ] \
    && nb_doctor_line PASS "state writable: $NOBRAND_STATE_DIR" \
    || nb_doctor_line WARN "state 尚未初始化或不可写: $NOBRAND_STATE_DIR"
  command -v ss >/dev/null 2>&1 || command -v netstat >/dev/null 2>&1 \
    && nb_doctor_line PASS 'port tool' || nb_doctor_line WARN '无 ss/netstat，将使用 bind probe'
  if command -v ufw >/dev/null 2>&1; then
    nb_doctor_line PASS 'firewall=ufw'
  elif command -v firewall-cmd >/dev/null 2>&1; then
    nb_doctor_line PASS 'firewall=firewalld'
  elif command -v iptables >/dev/null 2>&1; then
    nb_doctor_line PASS 'firewall=iptables'
  else
    nb_doctor_line WARN '未检测到本地 firewall backend'
  fi
  manager="$(nb_service_manager)"
  [ "$manager" != none ] && nb_doctor_line PASS "service-manager=${manager}" \
    || { nb_doctor_line FAIL '未检测到 systemd/OpenRC'; failed=1; }
  if bbr_fq_active 2>/dev/null; then
    nb_doctor_line PASS 'BBR/FQ active'
  else
    nb_doctor_line INFO 'BBR/FQ not active（可选）'
  fi
  return "$failed"
}

nobrand_doctor() {
  local failed=0
  nobrand_print_banner
  msg ''
  msg 'Common Core'
  nobrand_doctor_common || failed=1
  if mita_installed 2>/dev/null || [ -s "$MITA_USERS_STATE" ]; then
    msg ''
    msg 'Mieru'
    do_doctor || failed=1
  fi
  msg ''
  msg 'Snell'
  snell_doctor_all || failed=1
  msg ''
  msg 'Hysteria2'
  hysteria2_doctor || failed=1
  msg ''
  msg 'VLESS + FinalMask + Sudoku (TCP)'
  vless_sudoku_doctor || failed=1
  [ "$failed" -eq 0 ] || return 1
}

nb_backup_default_path() {
  printf '%s/nobrand-backup-%s.tar.gz' "$NOBRAND_BACKUP_DIR" "$(date +%Y%m%d_%H%M%S)"
}

nb_assert_safe_nobrand_root() {
  local value="${1:-}" label="${2:-path}" normalized
  [ -n "$value" ] || die "${label} 为空，拒绝破坏性操作"
  case "$value" in
    *'..'*) die "${label} 含有 ..，拒绝破坏性操作: $value" ;;
  esac
  normalized="$(readlink -m -- "$value" 2>/dev/null \
    || realpath -m -- "$value" 2>/dev/null || printf '%s' "$value")"
  case "$normalized" in
    /|/etc|/var|/usr|/usr/local) die "${label} 过宽，拒绝破坏性操作: $normalized" ;;
  esac
  case "$normalized" in
    */nobrand-oneclick|*/nobrand-oneclick/*|*/nobrand-oneclick-*) ;;
    *) die "${label} 不在明确的 NoBrand namespace 中: $normalized" ;;
  esac
  printf '%s' "$normalized"
}

nobrand_backup_create() {
  local destination="${1:-}" stage archive_tmp
  nb_init_state_layout || return 1
  [ -n "$destination" ] || destination="$(nb_backup_default_path)"
  stage="$(mktemp_dir)" || return 1
  mkdir -p "$stage/state" "$stage/config" || { rm -rf -- "$stage"; return 1; }
  cp -a "$NOBRAND_STATE_DIR/." "$stage/state/" || { rm -rf -- "$stage"; return 1; }
  cp -a "$NOBRAND_CONFIG_DIR/." "$stage/config/" || { rm -rf -- "$stage"; return 1; }
  cat >"$stage/manifest.txt" <<EOF
project=NoBrand-OneClick
version=${SCRIPT_VERSION}
created_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
contents=state,config
EOF
  archive_tmp="$(mktemp_file .tar.gz)" || { rm -rf -- "$stage"; return 1; }
  if ! tar -C "$stage" -czf "$archive_tmp" manifest.txt state config; then
    rm -f "$archive_tmp"
    rm -rf -- "$stage"
    return 1
  fi
  mkdir -p "$(dirname "$destination")" || { rm -f "$archive_tmp"; rm -rf -- "$stage"; return 1; }
  chmod 0600 "$archive_tmp" || { rm -f "$archive_tmp"; rm -rf -- "$stage"; return 1; }
  mv -f "$archive_tmp" "$destination" || { rm -f "$archive_tmp"; rm -rf -- "$stage"; return 1; }
  rm -rf -- "$stage"
  t "NoBrand 备份已保存: ${destination}" "NoBrand backup saved: ${destination}"
}

nobrand_backup_list() {
  find "$NOBRAND_BACKUP_DIR" -maxdepth 1 -type f -name 'nobrand-backup-*.tar.gz' \
    -print 2>/dev/null | LC_ALL=C sort -r
}

nobrand_backup_restore() {
  local source="$1" stage snapshot safe_state safe_config
  [ -f "$source" ] || die "备份不存在: $source"
  safe_state="$(nb_assert_safe_nobrand_root "$NOBRAND_STATE_DIR" NOBRAND_STATE_DIR)" || return 1
  safe_config="$(nb_assert_safe_nobrand_root "$NOBRAND_CONFIG_DIR" NOBRAND_CONFIG_DIR)" || return 1
  tar -tzf "$source" 2>/dev/null | awk '
    /^\// || /(^|\/)\.\.($|\/)/ { bad=1 }
    END { exit bad ? 1 : 0 }
  ' || die '备份包含不安全路径，拒绝恢复'
  stage="$(mktemp_dir)" || return 1
  tar -C "$stage" -xzf "$source" || { rm -rf -- "$stage"; return 1; }
  grep -qx 'project=NoBrand-OneClick' "$stage/manifest.txt" 2>/dev/null \
    || { rm -rf -- "$stage"; die '不是 NoBrand-OneClick 备份'; }
  find "$stage/state" "$stage/config" -type f -name '*.json' -print0 2>/dev/null \
    | while IFS= read -r -d '' file; do jq empty "$file" >/dev/null || exit 1; done \
    || { rm -rf -- "$stage"; die '备份中存在无效 JSON'; }
  snapshot="$(mktemp_dir)" || { rm -rf -- "$stage"; return 1; }
  mkdir -p "$snapshot/state" "$snapshot/config"
  cp -a "$safe_state/." "$snapshot/state/" 2>/dev/null || true
  cp -a "$safe_config/." "$snapshot/config/" 2>/dev/null || true
  nobrand_stop_all_services 2>/dev/null || true
  if ! find "$safe_state" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + \
     || ! find "$safe_config" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + \
     || ! cp -a "$stage/state/." "$safe_state/" \
     || ! cp -a "$stage/config/." "$safe_config/"; then
    find "$safe_state" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + 2>/dev/null || true
    find "$safe_config" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + 2>/dev/null || true
    cp -a "$snapshot/state/." "$safe_state/" 2>/dev/null || true
    cp -a "$snapshot/config/." "$safe_config/" 2>/dev/null || true
    rm -rf -- "$stage" "$snapshot"
    die '恢复失败，已回滚原 NoBrand state/config'
  fi
  nb_init_state_layout
  if ! snell_migrate_removed_v6; then
    find "$safe_state" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + 2>/dev/null || true
    find "$safe_config" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + 2>/dev/null || true
    cp -a "$snapshot/state/." "$safe_state/" 2>/dev/null || true
    cp -a "$snapshot/config/." "$safe_config/" 2>/dev/null || true
    rm -rf -- "$stage" "$snapshot"
    die '备份包含无法安全迁移的已移除 Snell v6 state；已回滚原 NoBrand state/config'
  fi
  nobrand_start_enabled_services || {
    warn '配置已恢复，但部分服务未能启动；请运行 nobrand doctor'
  }
  rm -rf -- "$stage" "$snapshot"
  t 'NoBrand 备份恢复完成' 'NoBrand backup restored'
}

nobrand_backup_action() {
  case "${NOBRAND_BACKUP_ACTION:-create}" in
    create) nobrand_backup_create "${NOBRAND_BACKUP_PATH:-}" ;;
    list) nobrand_backup_list ;;
    restore)
      [ -n "${NOBRAND_BACKUP_PATH:-}" ] || die 'backup restore 需要文件路径'
      nobrand_backup_restore "$NOBRAND_BACKUP_PATH"
      ;;
  esac
}

nobrand_remove_owned_command() {
  local path="$1"
  [ -f "$path" ] && [ ! -L "$path" ] || return 0
  case "$path" in
    /usr/local/bin/install-nobrand|/usr/local/bin/nobrand|/usr/local/bin/nb|*/nobrand-oneclick/*|*/nobrand-oneclick-*/*) ;;
    *) warn "拒绝删除 NoBrand command allowlist 以外的路径: $path"; return 1 ;;
  esac
  if grep -qF 'NoBrand-OneClick' "$path" 2>/dev/null \
     || grep -qF "$NOBRAND_INSTALL_SCRIPT_PATH" "$path" 2>/dev/null; then
    rm -f "$path"
  else
    warn "拒绝删除内容不属于 NoBrand 的命令: $path"
    return 1
  fi
}

nobrand_uninstall() {
  local id port safe_state safe_config safe_lib pairs="" snell_pairs failed=0
  require_root
  if [ "${YES:-0}" -ne 1 ]; then
    confirm '确认删除 NoBrand 管理的 Snell/HY2/VLESS/Common state？Mieru 数据会保留。[y/N]: ' \
      'Remove NoBrand-managed Snell/HY2/VLESS/Common state? Mieru data is preserved. [y/N]: ' \
      n \
      || { t '已取消' 'Cancelled'; return 0; }
  fi
  safe_state="$(nb_assert_safe_nobrand_root "$NOBRAND_STATE_DIR" NOBRAND_STATE_DIR)" || return 1
  safe_config="$(nb_assert_safe_nobrand_root "$NOBRAND_CONFIG_DIR" NOBRAND_CONFIG_DIR)" || return 1
  safe_lib="$(nb_assert_safe_nobrand_root "$NOBRAND_LIB_DIR" NOBRAND_LIB_DIR)" || return 1
  admin_lock_acquire || return 1
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    port="$(snell_state_field "$id" listen_port 2>/dev/null || true)"
    snell_pairs="$(snell_firewall_pairs "$id" 2>/dev/null || true)"
    snell_remove_service "$id" || failed=1
    [ -z "$snell_pairs" ] || nb_firewall_close_pairs "$snell_pairs" || failed=1
  done < <(snell_instance_ids)
  if hysteria2_state_exists; then
    port="$(hysteria2_state_field listen_port 2>/dev/null || true)"
    nobrand_remove_hy2_service || failed=1
    [ -z "$port" ] || nb_firewall_close_pairs "UDP|${port}" || failed=1
  fi
  if vless_sudoku_state_exists; then
    port="$(vless_sudoku_state_field listen_port 2>/dev/null || true)"
    nobrand_remove_vless_sudoku_service || failed=1
    [ -z "$port" ] || nb_firewall_close_pairs "TCP|${port}" || failed=1
  fi
  # 清理可能由失败事务留下、但仍明确记录为 NoBrand-owned 的 firewall rows。
  if [ -s "$NOBRAND_FIREWALL_OWNED_STATE" ]; then
    while IFS='|' read -r _tool proto row_port; do
      case "$proto" in
        tcp|udp) printf -v pairs '%s%s|%s\n' "$pairs" "$(printf '%s' "$proto" | tr '[:lower:]' '[:upper:]')" "$row_port" ;;
      esac
    done <"$NOBRAND_FIREWALL_OWNED_STATE"
    [ -z "$pairs" ] || nb_firewall_close_pairs "$pairs" || failed=1
  fi
  if [ "$failed" -ne 0 ]; then
    admin_lock_release
    warn 'NoBrand service/firewall 清理未完整完成；保留 state 以便重试'
    return 1
  fi
  case "$NOBRAND_SNELL_SYSTEMD_TEMPLATE" in
    /etc/systemd/system/nobrand-snell@.service) rm -f "$NOBRAND_SNELL_SYSTEMD_TEMPLATE" ;;
  esac
  [ "$(nb_service_manager)" != systemd ] || systemctl daemon-reload 2>/dev/null || true
  find "$safe_state" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
  find "$safe_config" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
  find "$safe_lib" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
  rmdir "$safe_state" "$safe_config" "$safe_lib" 2>/dev/null || true
  nobrand_remove_owned_command "$NOBRAND_COMMAND_PATH" || failed=1
  nobrand_remove_owned_command "$NOBRAND_SHORT_COMMAND_PATH" || failed=1
  nobrand_remove_owned_command "$NOBRAND_INSTALL_SCRIPT_PATH" || failed=1
  admin_lock_release
  [ "$failed" -eq 0 ] || return 1
  t 'NoBrand Snell/HY2/VLESS/Common 内容已删除；Mieru、/etc/xray、xray.service、ike 均未触碰' \
    'NoBrand Snell/HY2/VLESS/Common content removed; Mieru, /etc/xray, xray.service, and ike were untouched'
}

nobrand_stop_all_services() {
  local id
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    snell_service_action "$id" stop >/dev/null 2>&1 || true
  done < <(snell_instance_ids)
  hysteria2_state_exists && nobrand_hy2_service_action stop >/dev/null 2>&1 || true
  vless_sudoku_state_exists \
    && nobrand_vless_sudoku_service_action stop >/dev/null 2>&1 || true
}

nobrand_start_enabled_services() {
  local id enabled port pairs failed=0
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    enabled="$(snell_state_field "$id" enabled 2>/dev/null || printf false)"
    [ "$enabled" = true ] || continue
    port="$(snell_state_field "$id" listen_port)"
    pairs="$(snell_firewall_pairs "$id")"
    nb_firewall_open_pairs "$pairs" >/dev/null 2>&1 \
      && snell_service_action "$id" start >/dev/null 2>&1 \
      && snell_wait_for_required_listeners "$id" 25 || failed=1
  done < <(snell_instance_ids)
  if hysteria2_state_exists \
     && [ "$(hysteria2_state_field enabled 2>/dev/null || printf false)" = true ]; then
    port="$(hysteria2_state_field listen_port)"
    nobrand_hy2_service_action start >/dev/null 2>&1 \
      && nb_wait_for_listener UDP "$port" 25 || failed=1
  fi
  if vless_sudoku_state_exists \
     && [ "$(vless_sudoku_state_field enabled 2>/dev/null || printf false)" = true ]; then
    port="$(vless_sudoku_state_field listen_port)"
    nobrand_vless_sudoku_service_action start >/dev/null 2>&1 \
      && nb_wait_for_listener TCP "$port" 25 || failed=1
  fi
  return "$failed"
}
