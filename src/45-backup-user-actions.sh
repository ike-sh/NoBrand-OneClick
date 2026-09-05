# ---------- 阶段4：备份 / 恢复 / 导出导入 / 管理锁 ----------

user_package_display_label() {
  case "${1:-}" in
    unlimited) t '不限量' 'unlimited' ;;
    trial) t '体验' 'trial' ;;
    standard) t '标准' 'standard' ;;
    custom) t '自定义' 'custom' ;;
    "") printf '%s' '-' ;;
    *) printf '%s' "$1" ;;
  esac
}

user_enabled_display_label() {
  if [ "${1:-0}" = 1 ]; then
    t '启用' 'on'
  else
    t '停用' 'off'
  fi
}

# 破坏性变更前备份 users.json；成功打印备份路径
users_backup_now() {
  local tag="${1:-auto}" dest ts
  users_state_exists || return 1
  if [ "${DRY_RUN:-0}" -eq 1 ]; then
    t "[演练] 备份用户状态: $MITA_USERS_STATE" \
      "[dry-run] backup users state: $MITA_USERS_STATE"
    return 0
  fi
  run mkdir -p "$MITA_USERS_BACKUP_DIR"
  ts="$(date +%Y%m%d_%H%M%S 2>/dev/null || echo unknown)_$$_${RANDOM}"
  dest="${MITA_USERS_BACKUP_DIR}/users_${tag}_${ts}.json"
  if command -v install >/dev/null 2>&1; then
    run install -m 0600 "$MITA_USERS_STATE" "$dest"
  else
    run cp -f "$MITA_USERS_STATE" "$dest"
    run chmod 0600 "$dest" 2>/dev/null || true
  fi
  # 只保留最近 20 份
  if command -v python3 >/dev/null 2>&1; then
    MITA_USERS_BACKUP_DIR="$MITA_USERS_BACKUP_DIR" python3 -c '
import os, glob
d=os.environ.get("MITA_USERS_BACKUP_DIR", "/var/lib/nobrand-oneclick/mieru/backups")
files=sorted(glob.glob(os.path.join(d, "users_*.json")), key=os.path.getmtime, reverse=True)
for f in files[20:]:
    try: os.remove(f)
    except Exception: pass
' 2>/dev/null || true
  fi
  printf '%s' "$dest"
}

users_validate_state_file() {
  local f="$1" protocol="${2:-${PROTOCOL:-TCP}}" auto_host="${3:-}"
  [ -f "$f" ] || return 1
  python3 -c '
import datetime,ipaddress,json,re,sys
d=json.load(open(sys.argv[1]))
proto=(sys.argv[2] if len(sys.argv)>2 else "TCP").upper()
auto_host=(sys.argv[3] if len(sys.argv)>3 else "").strip()
if d.get("deployment_model") != "isolated-v2":
    sys.exit(19)
def normalize_endpoint_host(value):
    value=str(value or "").strip()
    try:
        return str(ipaddress.ip_address(value))
    except Exception:
        pass
    raw=value[:-1] if value.endswith(".") else value
    if not raw or len(raw)>253 or "://" in raw or ":" in raw or "/" in raw:
        raise ValueError("invalid host")
    labels=raw.split(".")
    if any(not label or len(label)>63 or not re.fullmatch(r"[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?", label) for label in labels):
        raise ValueError("invalid host")
    return raw.lower()
if proto not in ("TCP", "UDP", "BOTH"):
    sys.exit(15)
if auto_host:
    try:
        auto_host=str(ipaddress.ip_address(auto_host))
    except Exception:
        auto_host=""
users=d.get("users")
if not isinstance(users, list):
    sys.exit(2)
names=set(); occupied_ports=set(); advertised_endpoints=set()
for u in users:
    if not isinstance(u, dict):
        sys.exit(3)
    n=u.get("name")
    pw=u.get("password")
    if not isinstance(n, str) or not n or len(n.encode()) > 64:
        sys.exit(4)
    if any(ord(c) < 32 or ord(c) == 127 for c in n):
        sys.exit(4)
    if not isinstance(pw, str) or not pw or len(pw.encode()) > 64:
        sys.exit(8)
    if any(ord(c) < 32 or ord(c) == 127 for c in pw):
        sys.exit(8)
    if n in names:
        sys.exit(5)
    names.add(n)
    try:
        p=int(u.get("port"))
    except Exception:
        sys.exit(6)
    if p < 1025 or p > 65535 or (proto == "BOTH" and p > 65534):
        sys.exit(6)
    user_ports=(p, p+1) if proto == "BOTH" else (p,)
    if any(port in occupied_ports for port in user_ports):
        sys.exit(7)
    occupied_ports.update(user_ports)
    advertise_host=str(u.get("advertise_host") or "").strip()
    advertise_port=u.get("advertise_port")
    if bool(advertise_host) != bool(advertise_port):
        sys.exit(17)
    if advertise_host:
        try:
            advertise_host=normalize_endpoint_host(advertise_host)
            advertise_port=int(advertise_port)
        except Exception:
            sys.exit(17)
        if advertise_port < 1 or advertise_port > 65535 or (proto == "BOTH" and advertise_port > 65534):
            sys.exit(17)
    else:
        advertise_port=""
    u["advertise_host"]=advertise_host
    u["advertise_port"]=advertise_port
    effective_host=advertise_host or auto_host
    effective_port=advertise_port if advertise_host else p
    if effective_host:
        endpoint_pairs=(("TCP", effective_port), ("UDP", effective_port+1)) if proto == "BOTH" else ((proto, effective_port),)
        for endpoint_proto, endpoint_port in endpoint_pairs:
            endpoint=(effective_host, endpoint_proto, endpoint_port)
            if endpoint in advertised_endpoints:
                sys.exit(18)
            advertised_endpoints.add(endpoint)
    try:
        qmb=max(0, int(u.get("quota_mb") or 0))
        qdays=max(0, int(u.get("quota_days") or 0))
        bw=max(0, int(u.get("bandwidth_mbps") or 0))
    except Exception:
        sys.exit(9)
    if qmb > 2147483647 or qdays > 2147483647 or bw > 1000000:
        sys.exit(16)
    u["quota_mb"]=qmb
    u["quota_days"]=(qdays if qdays > 0 else 30) if qmb > 0 else 0
    qmode=str(u.get("quota_mode") or "rolling").strip().lower()
    if qmode not in ("rolling","calendar"):
        sys.exit(10)
    u["quota_mode"]=qmode
    enabled=u.get("enabled", True)
    if not isinstance(enabled, bool):
        sys.exit(11)
    u["enabled"]=enabled
    ingress_profile_id=str(u.get("ingress_profile_id") or "legacy-default-route").strip()
    ingress_enforcement=str(u.get("ingress_enforcement") or "permissive").strip().lower()
    ingress_method=str(u.get("ingress_enforcement_method") or "wildcard").strip().lower()
    ingress_address=str(u.get("ingress_local_address") or "").strip()
    if not ingress_profile_id or ingress_enforcement not in ("permissive","strict"):
        sys.exit(20)
    if ingress_enforcement == "permissive" and ingress_method != "wildcard":
        sys.exit(20)
    if ingress_enforcement == "strict":
        if ingress_method != "firewall":
            sys.exit(20)
        try:
            if ipaddress.ip_address(ingress_address).version != 4:
                sys.exit(20)
        except Exception:
            sys.exit(20)
    expire=str(u.get("expire_at") or "").strip()
    if expire:
        try:
            datetime.date.fromisoformat(expire)
        except Exception:
            sys.exit(12)
    u["expire_at"]=expire
    last_reset=str(u.get("last_quota_reset") or "").strip()
    if last_reset and (len(last_reset) != 7 or last_reset[4] != "-" or not last_reset.replace("-","").isdigit()):
        sys.exit(13)
    u["last_quota_reset"]=last_reset
    package=str(u.get("package") or ("custom" if qmb > 0 else "unlimited"))
    if len(package.encode()) > 64 or any(ord(c) < 32 or ord(c) == 127 for c in package):
        sys.exit(14)
    u["package"]=package
    u["bandwidth_mbps"]=bw
d["version"]=2
d["deployment_model"]="isolated-v2"
d["protocol"]=proto
json.dump(d, open(sys.argv[1]+".norm","w"), indent=2)
' "$f" "$protocol" "$auto_host" 2>/dev/null || return 1
  if [ -f "${f}.norm" ]; then
    mv -f "${f}.norm" "$f" 2>/dev/null || return 1
  fi
  return 0
}

users_restore_from_file() {
  local src="$1" bak tx tmp imported_protocol
  local old_protocol old_user old_password old_port old_pairs new_pairs close_pairs rollback_close_pairs
  local old_advertise_host old_advertise_port
  [ -f "$src" ] || { warn "$(t "备份不存在: $src" "Backup not found: $src")"; return 1; }
  admin_lock_acquire || return 1
  load_install_state
  old_protocol="${PROTOCOL:-TCP}"
  old_user="${USERNAME:-}"
  old_password="${PASSWORD:-}"
  old_port="${PORT:-}"
  old_advertise_host="${ADVERTISE_HOST:-}"
  old_advertise_port="${ADVERTISE_PORT:-}"
  old_pairs="$(multi_user_port_protocol_pairs)"
  tmp="$(mktemp_file .json)"
  cp -f "$src" "$tmp"
  imported_protocol="$(python3 -c '
import json,sys
d=json.load(open(sys.argv[1]))
print(str(d.get("protocol") or sys.argv[2]).strip().upper())
' "$tmp" "$old_protocol" 2>/dev/null || true)"
  case "$imported_protocol" in
    TCP|UDP|BOTH) ;;
    *)
      rm -f "$tmp"
      admin_lock_release
      warn "$(t '备份中的协议无效（仅支持 TCP/UDP/BOTH）' \
        'Invalid protocol in backup (only TCP/UDP/BOTH are supported)')"
      return 1
      ;;
  esac
  users_validate_state_file "$tmp" "$imported_protocol" || {
    rm -f "$tmp"
    admin_lock_release
    warn "$(t '备份文件格式无效' 'Invalid backup format')"
    return 1
  }
  tx="$(users_tx_snapshot)" || { rm -f "$tmp"; admin_lock_release; return 1; }
  if users_state_exists; then
    bak="$(users_backup_now pre-restore 2>/dev/null || true)"
    [ -n "$bak" ] && t "恢复前已备份: $bak" "Pre-restore backup: $bak" >&2
  fi
  run mkdir -p "$(dirname "$MITA_USERS_STATE")"
  if command -v install >/dev/null 2>&1; then
    if ! run install -m 0600 "$tmp" "$MITA_USERS_STATE"; then
      rm -f "$tmp"
      users_tx_rollback "$tx" 0
      admin_lock_release
      return 1
    fi
  else
    if ! run cp -f "$tmp" "$MITA_USERS_STATE"; then
      rm -f "$tmp"
      users_tx_rollback "$tx" 0
      admin_lock_release
      return 1
    fi
    run chmod 0600 "$MITA_USERS_STATE" 2>/dev/null || true
  fi
  rm -f "$tmp"
  PROTOCOL="$imported_protocol"
  MULTI_USER_MODE=1
  users_sync_primary_globals
  if mita_installed 2>/dev/null; then
    if ! apply_users_config "$tx"; then
      # apply_users_config 已恢复 users.json，但它执行回滚时仍使用导入协议；
      # 这里切回旧协议并再次收敛，保证旧实例与旧端口完整恢复。
      PROTOCOL="$old_protocol"
      USERNAME="$old_user"
      PASSWORD="$old_password"
      PORT="$old_port"
      ADVERTISE_HOST="$old_advertise_host"
      ADVERTISE_PORT="$old_advertise_port"
      if users_isolated_mode; then
        reconcile_isolated_instances 2>/dev/null || true
        apply_tc_limits 2>/dev/null || true
      fi
      admin_lock_release
      return 1
    fi
    new_pairs="$(multi_user_port_protocol_pairs)"
    open_firewall_for_pairs "$new_pairs" 2>/dev/null || true
  else
    new_pairs="$(multi_user_port_protocol_pairs)"
    if ! apply_tc_limits; then
      PROTOCOL="$old_protocol"
      USERNAME="$old_user"
      PASSWORD="$old_password"
      PORT="$old_port"
      ADVERTISE_HOST="$old_advertise_host"
      ADVERTISE_PORT="$old_advertise_port"
      users_tx_rollback "$tx" 0
      admin_lock_release
      return 1
    fi
  fi
  if ! save_install_state; then
    rollback_close_pairs="$(comm -23 \
      <(printf '%s\n' "$new_pairs" | sed '/^[[:space:]]*$/d' | LC_ALL=C sort -u) \
      <(printf '%s\n' "$old_pairs" | sed '/^[[:space:]]*$/d' | LC_ALL=C sort -u))"
    PROTOCOL="$old_protocol"
    USERNAME="$old_user"
    PASSWORD="$old_password"
    PORT="$old_port"
    ADVERTISE_HOST="$old_advertise_host"
    ADVERTISE_PORT="$old_advertise_port"
    if mita_installed 2>/dev/null; then
      users_tx_rollback "$tx" 1
    else
      users_tx_rollback "$tx" 0
    fi
    open_firewall_for_pairs "$old_pairs" 2>/dev/null || true
    [ -z "$rollback_close_pairs" ] || close_firewall_for_bindings "$rollback_close_pairs"
    admin_lock_release
    return 1
  fi
  close_pairs="$(comm -23 \
    <(printf '%s\n' "$old_pairs" | sed '/^[[:space:]]*$/d' | LC_ALL=C sort -u) \
    <(printf '%s\n' "$new_pairs" | sed '/^[[:space:]]*$/d' | LC_ALL=C sort -u))"
  [ -z "$close_pairs" ] || close_firewall_for_bindings "$close_pairs"
  users_tx_commit "$tx"
  client_exports_clear_current 2>/dev/null || true
  admin_lock_release
  t "已从备份恢复用户状态" "Users restored from backup"
}

do_user_backup() {
  require_root
  users_state_exists || die "$(t '无用户状态可备份' 'No users state to backup')"
  local dest
  dest="$(users_backup_now manual)"
  t "已备份: $dest" "Backed up: $dest"
  # 同时备份 install-state 若存在
  if [ -f "$MITA_STATE" ]; then
    local sdest
    sdest="${dest%.json}_install-state.env"
    cp -f "$MITA_STATE" "$sdest" 2>/dev/null || true
    chmod 0600 "$sdest" 2>/dev/null || true
    t "  安装状态: $sdest" "  Install state: $sdest"
  fi
  msg ""
  t '最近备份:' 'Recent backups:'
  # shellcheck disable=SC2012
  ls -1t "$MITA_USERS_BACKUP_DIR"/users_*.json 2>/dev/null | head -n 10 || true
}

do_user_restore() {
  require_root
  local f="${USER_RESTORE_FILE:-}"
  if [ -z "$f" ]; then
    if [ "$YES" -eq 1 ]; then
      die "$(t '需要备份文件路径' 'Backup file path required')"
    fi
    msg ""
    t '可用备份:' 'Available backups:'
    # shellcheck disable=SC2012
    ls -1t "$MITA_USERS_BACKUP_DIR"/users_*.json 2>/dev/null | head -n 15 || true
    read_tty f "$(t '备份文件路径: ' 'Backup file: ')" || true
  fi
  [ -n "$f" ] || die "$(t '需要备份文件路径' 'Backup file path required')"
  if [ "$YES" -ne 1 ]; then
    confirm '确认用该备份覆盖当前用户配置？[y/N]: ' 'Overwrite current users with this backup? [y/N]: ' n || return 0
  fi
  users_restore_from_file "$f"
}

do_user_export() {
  require_root
  users_state_exists || die "$(t '无用户状态' 'No users state')"
  local out="${USER_EXPORT_FILE:-}"
  if [ -n "$out" ]; then
    run mkdir -p "$(dirname "$out")" 2>/dev/null || true
    cp -f "$MITA_USERS_STATE" "$out"
    chmod 0600 "$out" 2>/dev/null || true
    t "已导出: $out" "Exported: $out"
  else
    cat "$MITA_USERS_STATE"
  fi
}

do_user_import() {
  require_root
  local f="${USER_RESTORE_FILE:-}"
  if [ -z "$f" ] && [ "$YES" -ne 1 ]; then
    read_tty f "$(t '导入文件路径: ' 'Import file: ')" || f=""
  fi
  [ -n "$f" ] || die "$(t '需要 --user-import FILE' 'Need --user-import FILE')"
  if [ "$YES" -ne 1 ]; then
    confirm '导入将覆盖当前用户配置，是否继续？[y/N]: ' 'Import overwrites current users. Continue? [y/N]: ' n || return 0
  fi
  users_restore_from_file "$f"
}

print_user_outputs() {
  local name="$1"
  local ip password port saved_user saved_pass saved_port saved_advertise_host saved_advertise_port saved_ingress_profile_id
  password="$(users_get_field "$name" password)" || return 1
  port="$(users_get_field "$name" port)" || return 1
  saved_user="$USERNAME"
  saved_pass="$PASSWORD"
  saved_port="$PORT"
  saved_advertise_host="$ADVERTISE_HOST"
  saved_advertise_port="$ADVERTISE_PORT"
  saved_ingress_profile_id="${INGRESS_PROFILE_ID:-}"
  USERNAME="$name"
  PASSWORD="$password"
  PORT="$port"
  ADVERTISE_HOST="$(users_get_field "$name" advertise_host 2>/dev/null || true)"
  ADVERTISE_PORT="$(users_get_field "$name" advertise_port 2>/dev/null || true)"
  INGRESS_PROFILE_ID="$(users_get_field "$name" ingress_profile_id 2>/dev/null || true)"
  [ -n "$INGRESS_PROFILE_ID" ] || INGRESS_PROFILE_ID="$NOBRAND_LEGACY_INGRESS_PROFILE_ID"
  ip="$(advertised_host || echo 'YOUR_SERVER_IP')"
  msg ""
  t "========== 用户 ${name} ==========" "========== User ${name} =========="
  t "  专属实例端口: ${port}（其它用户凭据无法在此实例认证）" \
    "  Dedicated instance port: ${port} (other users cannot authenticate on this instance)"
  t "  网络入口: $(nb_ingress_profile_name "$INGRESS_PROFILE_ID")" \
    "  Ingress: $(nb_ingress_profile_name "$INGRESS_PROFILE_ID")"
  local qmb qdays exp en pkg bw status_label
  qmb="$(users_get_field "$name" quota_mb 2>/dev/null || echo 0)"
  qdays="$(users_get_field "$name" quota_days 2>/dev/null || echo 0)"
  exp="$(users_get_field "$name" expire_at 2>/dev/null || true)"
  en="$(users_get_field "$name" enabled 2>/dev/null || echo 1)"
  pkg="$(users_get_field "$name" package 2>/dev/null || true)"
  bw="$(users_get_field "$name" bandwidth_mbps 2>/dev/null || echo 0)"
  pkg="$(user_package_display_label "$pkg")"
  status_label="$(user_enabled_display_label "$en")"
  t "  套餐: ${pkg}  配额: $(quota_label "$qmb" "$qdays")  双向限速: ${bw:-0}Mbps（0=不限） 到期: ${exp:-永不过期}  状态: ${status_label}" \
    "  Package: ${pkg}  Quota: $(quota_label "$qmb" "$qdays")  Bidirectional rate: ${bw:-0}Mbps (0=unlim) Expire: ${exp:-never}  Status: ${status_label}"
  print_protocol_outputs "$ip"
  msg ""
  t '【连接信息】' '[Connection info]'
  t "  服务器: ${ip}" "  Server:   ${ip}"
  t "  用户名: ${name}" "  Username: ${name}"
  t "  密码:   ${password}" "  Password: ${password}"
  t "  协议:   $(client_protocol_label)" "  Protocol: $(client_protocol_label)"
  if [ "$PROTOCOL" = "BOTH" ]; then
    t "  入口端口: TCP $(advertised_port_for_protocol TCP) / UDP $(advertised_port_for_protocol UDP)" \
      "  Entry ports: TCP $(advertised_port_for_protocol TCP) / UDP $(advertised_port_for_protocol UDP)"
  else
    t "  入口端口: $(advertised_port_for_protocol "$PROTOCOL")" \
      "  Entry port:  $(advertised_port_for_protocol "$PROTOCOL")"
  fi
  print_client_endpoint_mapping
  if [ -n "$ip" ] && [ "$ip" != "YOUR_SERVER_IP" ]; then
    msg ""
    t '【Clash / mihomo 配置片段】' '[Clash / mihomo snippet]'
    build_clash_yaml_full "$ip"
  fi
  USERNAME="$saved_user"
  PASSWORD="$saved_pass"
  PORT="$saved_port"
  ADVERTISE_HOST="$saved_advertise_host"
  ADVERTISE_PORT="$saved_advertise_port"
  INGRESS_PROFILE_ID="$saved_ingress_profile_id"
}

open_firewall_for_pairs() {
  local pairs="$1"
  local fw="" pp proto p proto_lc failed=0
  [ -n "$pairs" ] || return 0
  if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q 'Status: active'; then
    fw=ufw
  elif command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
    fw=firewalld
  elif command -v iptables >/dev/null 2>&1; then
    fw=iptables
  else
    return 0
  fi
  while IFS= read -r pp; do
    [ -n "$pp" ] || continue
    proto="${pp%%|*}"
    p="${pp#*|}"
    proto_lc="$(proto_lower "$proto")"
    firewall_apply_binding "$fw" add "$proto_lc" "$p" || failed=1
  done <<< "$pairs"
  case "$fw" in
    firewalld) run firewall-cmd --reload || failed=1 ;;
    iptables) persist_iptables_rules || failed=1 ;;
  esac
  [ "$failed" -eq 0 ]
}

do_user_list() {
  require_root
  load_install_state
  users_ensure_loaded
  if ! users_state_exists || [ "$(users_count)" -eq 0 ]; then
    t '（schema v3 中没有 Mieru 用户）' '(No Mieru users in schema v3 state.)'
    return 0
  fi
  msg ""
  t '用户名      端口 状态 套餐      配额      模式  限速  到期' \
    'USER        PORT ST  PACKAGE   QUOTA     MODE  RATE  EXPIRE'
  t '----------- ---- ---- --------- --------- ----- ----- ----------' \
    '----------- ---- ---- --------- --------- ----- ----- ----------'
  python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
on_l,off_l,unlimited_l,never_l,day_l,rolling_l,calendar_l=sys.argv[2:9]
package_labels={"unlimited":unlimited_l,"trial":sys.argv[9],"standard":sys.argv[10],"custom":sys.argv[11]}
for u in d.get("users") or []:
    name = (u.get("name") or "")[:11]
    port = str(u.get("port") or "")
    st = on_l if u.get("enabled", True) else off_l
    raw_pkg = u.get("package") or "-"
    pkg = package_labels.get(raw_pkg,raw_pkg)[:9]
    qmb = int(u.get("quota_mb") or 0)
    qdays = int(u.get("quota_days") or 0)
    raw_mode = u.get("quota_mode") or "rolling"
    mode = (calendar_l if raw_mode == "calendar" else rolling_l)[:5]
    if qmb <= 0:
        quota = unlimited_l
        mode = "-"
    elif qmb >= 1024:
        quota = "%dG/%d%s" % (qmb // 1024, qdays or 30, day_l)
    else:
        quota = "%dM/%d%s" % (qmb, qdays or 30, day_l)
    bw = int(u.get("bandwidth_mbps") or 0)
    bws = str(bw) if bw > 0 else "-"
    exp = (u.get("expire_at") or never_l)[:10]
    print(f"{name:<11} {port:<4} {st:<4} {pkg:<9} {quota:<9} {mode:<5} {bws:<5} {exp}")
' "$MITA_USERS_STATE" \
    "$(t '启用' 'on')" "$(t '停用' 'off')" "$(t '不限量' 'unlimited')" \
    "$(t '永不过期' 'never')" "$(t '天' 'd')" "$(t '滚动' 'rolling')" \
    "$(t '日历月' 'calendar')" "$(t '体验' 'trial')" "$(t '标准' 'standard')" \
    "$(t '自定义' 'custom')"
  t "共 $(users_count) 个用户（滚动模式 rolling；日历月模式 calendar 每月 1 日重置）" \
    "Total $(users_count) (rolling window; calendar=reset on 1st)"
}

do_user_add() {
  require_root
  require_linux
  mita_installed || die "$(t 'mita 未安装，请先执行安装' 'mita is not installed; run install first')"
  # CLI 参数先保存，避免被 load_install_state 覆盖
  local name="${USERNAME:-}" password="${PASSWORD:-}" prefer="" tx
  local requested_advertise_host="${ADVERTISE_HOST:-}" requested_advertise_port="${ADVERTISE_PORT:-}"
  local requested_advertise_cli="${ADVERTISE_CLI:-0}"
  local saved_pkg="${USER_PACKAGE:-}" saved_qmb="${USER_QUOTA_MB:-}" saved_qd="${USER_QUOTA_DAYS:-}" saved_exp="${USER_EXPIRE:-}" saved_bw="${USER_BANDWIDTH_MBPS:-}"
  if [ "${PORT_CLI:-0}" -eq 1 ] && [ -n "${PORT:-}" ]; then
    prefer="$PORT"
  fi
  # --user/--password/--port 描述的是新用户；读取现有主用户时不能让这些 CLI 值覆盖安装状态。
  USERNAME_CLI=0
  PASSWORD_CLI=0
  PORT_CLI=0
  PORT_RANGE_CLI=0
  PROTOCOL_CLI=0
  ADVERTISE_CLI=0
  load_install_state
  USER_PACKAGE="$saved_pkg"
  USER_QUOTA_MB="$saved_qmb"
  USER_QUOTA_DAYS="$saved_qd"
  USER_EXPIRE="$saved_exp"
  USER_BANDWIDTH_MBPS="$saved_bw"
  if [ "$requested_advertise_cli" -ne 1 ]; then
    requested_advertise_host=""
    requested_advertise_port=""
  elif ! validate_advertise_endpoint_values "$requested_advertise_host" \
    "$requested_advertise_port" "${PROTOCOL:-TCP}"; then
    die "$(t '新用户的自定义客户端入口参数无效' \
      'Invalid custom client entry parameters for the new user')"
  fi
  [ -z "$requested_advertise_port" ] \
    || requested_advertise_port="$(normalize_uint "$requested_advertise_port")"
  if ! users_state_exists || [ "$(users_count)" -eq 0 ]; then
    die "$(t 'schema v3 Mieru 用户状态缺失；请重新执行全新安装' \
      'Schema-v3 Mieru user state is missing; perform a fresh install')"
  fi
  if [ -z "$name" ]; then
    if [ "$YES" -eq 1 ]; then
      name="$(random_token)"
    else
      read_tty name "$(t '新用户名: ' 'New username: ')" || true
    fi
  fi
  if [ -z "$password" ]; then
    if [ "$YES" -eq 1 ]; then
      password="$(random_token)"
    else
      read_tty_secret password "$(t '密码（回车随机）: ' 'Password (Enter=random): ')" || true
      [ -n "$password" ] || password="$(random_token)"
    fi
  fi
  if [ "$YES" -ne 1 ] && [ -z "${USER_PACKAGE}" ] && [ -z "${USER_QUOTA_MB}" ]; then
    local pk=""
    t '套餐: 1)不限量 2)体验10GB/7天 3)标准100GB/30天 4)自定义 5)跳过' \
      'Package: 1)unlimited 2)trial 10GB/7d 3)standard 100GB/30d 4)custom 5)skip'
    read_tty pk "$(t '选择 [1-5，默认1]: ' 'Choose [1-5, default 1]: ')" || pk=1
    case "${pk:-1}" in
      2) USER_PACKAGE=trial ;;
      3) USER_PACKAGE=standard ;;
      4)
        USER_PACKAGE=custom
        read_tty USER_QUOTA_MB "$(t '配额 MB（0=不限）: ' 'Quota MB (0=unlimited): ')" || true
        read_tty USER_QUOTA_DAYS "$(t '滚动天数 [30]: ' 'Rolling days [30]: ')" || true
        read_tty USER_EXPIRE "$(t '到期 YYYY-MM-DD 或 +30d（空=永不过期）: ' 'Expire YYYY-MM-DD or +30d (empty=never): ')" || true
        ;;
      5) ;;
      *) USER_PACKAGE=unlimited ;;
    esac
  fi
  admin_lock_acquire || return 1
  tx="$(users_tx_snapshot)" || { admin_lock_release; return 1; }
  if ! users_add "$name" "$password" "$prefer" \
    "$requested_advertise_host" "$requested_advertise_port" >/dev/null; then
    users_tx_rollback "$tx" 0
    admin_lock_release
    return 1
  fi
  if ! apply_users_config "$tx"; then
    admin_lock_release
    return 1
  fi
  users_sync_primary_globals
  if ! save_install_state; then
    users_tx_rollback "$tx" 1
    admin_lock_release
    return 1
  fi
  open_firewall_for_pairs "$(multi_user_port_protocol_pairs)"
  users_tx_commit "$tx"
  admin_lock_release
  print_user_outputs "$name"
}

do_user_set_quota() {
  require_root
  mita_installed || die "$(t 'mita 未安装' 'mita is not installed')"
  local requested_name="${USERNAME:-}"
  load_install_state
  users_ensure_loaded
  local name="${requested_name:-${USERNAME:-}}"
  [ -n "$name" ] || die "$(t '需要 --user NAME' 'Need --user NAME')"
  users_name_exists "$name" || die "$(t "用户不存在: $name" "User not found: $name")"
  if [ -z "${USER_QUOTA_MB}" ] && [ -z "${USER_QUOTA_DAYS}" ] \
     && [ -z "${USER_PACKAGE}" ] && [ -z "${USER_QUOTA_MODE}" ] \
     && [ -z "${USER_EXPIRE}" ]; then
    die "$(t '需要 --package / --quota-mb / --quota-mode' 'Need --package / --quota-mb / --quota-mode')" || return 1
    return 1
  fi
  if ! apply_user_package_defaults 0; then
    die "$(t '套餐或配额参数无效' 'Invalid package or quota value')" || return 1
    return 1
  fi
  if [ -n "${USER_QUOTA_MB}" ] && ! valid_nonnegative_int32 "$USER_QUOTA_MB"; then
    die "$(t '--quota-mb 必须是 0-2147483647 的整数' \
      '--quota-mb must be an integer from 0 to 2147483647')" || return 1
    return 1
  fi
  if [ -n "${USER_QUOTA_DAYS}" ] && ! valid_nonnegative_int32 "$USER_QUOTA_DAYS"; then
    die "$(t '--quota-days 必须是 0-2147483647 的整数' \
      '--quota-days must be an integer from 0 to 2147483647')" || return 1
    return 1
  fi
  local exp_parsed=""
  if [ -n "${USER_EXPIRE:-}" ]; then
    exp_parsed="$(parse_expire_date "$USER_EXPIRE")" || return 1
    USER_EXPIRE="$exp_parsed"
    [ -z "$USER_EXPIRE" ] && USER_EXPIRE="__CLEAR__"
  fi
  if [ -n "${USER_QUOTA_MODE:-}" ]; then
    USER_QUOTA_MODE="$(normalize_quota_mode "$USER_QUOTA_MODE")" || {
      die "$(t '--quota-mode 仅支持 rolling 或 calendar' \
        '--quota-mode accepts only rolling or calendar')" || return 1
      return 1
    }
  fi
  USER_BANDWIDTH_MBPS=""
  local tx old_pairs new_pairs close_pairs="" disabled_now=0
  admin_lock_acquire || return 1
  tx="$(users_tx_snapshot)" || { admin_lock_release; return 1; }
  old_pairs="$(multi_user_port_protocol_pairs)"
  if ! users_update_fields "$name"; then
    users_tx_rollback "$tx" 0
    admin_lock_release
    return 1
  fi
  if [ -n "$exp_parsed" ]; then
    local today
    today="$(today_ymd)"
    if [[ "$exp_parsed" < "$today" || "$exp_parsed" == "$today" ]]; then
      users_set_enabled "$name" 0 || {
        users_tx_rollback "$tx" 0
        admin_lock_release
        return 1
      }
      disabled_now=1
    fi
  fi
  if ! apply_users_config "$tx"; then
    admin_lock_release
    return 1
  fi
  if [ "$disabled_now" -eq 1 ]; then
    new_pairs="$(multi_user_port_protocol_pairs)"
    close_pairs="$(comm -23 \
      <(printf '%s\n' "$old_pairs" | sed '/^[[:space:]]*$/d' | LC_ALL=C sort -u) \
      <(printf '%s\n' "$new_pairs" | sed '/^[[:space:]]*$/d' | LC_ALL=C sort -u))"
    [ -z "$close_pairs" ] || close_firewall_for_bindings "$close_pairs"
    users_sync_primary_globals
    if ! save_install_state; then
      users_tx_rollback "$tx" 1
      open_firewall_for_pairs "$old_pairs"
      admin_lock_release
      return 1
    fi
  fi
  users_tx_commit "$tx"
  admin_lock_release
  t "已更新 ${name} 配额=$(quota_label "${USER_QUOTA_MB:-0}" "${USER_QUOTA_DAYS:-0}") 模式=${USER_QUOTA_MODE:-keep} 套餐=${USER_PACKAGE:-} 到期=${exp_parsed:-保持}" \
    "Updated ${name} quota=$(quota_label "${USER_QUOTA_MB:-0}" "${USER_QUOTA_DAYS:-0}") mode=${USER_QUOTA_MODE:-keep} package=${USER_PACKAGE:-} expire=${exp_parsed:-keep}"
}

do_user_set_expire() {
  require_root
  mita_installed || die "$(t 'mita 未安装' 'mita is not installed')"
  local requested_name="${USERNAME:-}"
  load_install_state
  users_ensure_loaded
  local name="${requested_name:-${USERNAME:-}}" exp disabled_now=0 disabled_port="" close_pairs=""
  [ -n "$name" ] || die "$(t '需要 --user NAME' 'Need --user NAME')"
  users_name_exists "$name" || die "$(t "用户不存在: $name" "User not found: $name")"
  [ -n "${USER_EXPIRE}" ] || die "$(t '需要 --expire YYYY-MM-DD|+Nd|0' 'Need --expire YYYY-MM-DD|+Nd|0')"
  exp="$(parse_expire_date "$USER_EXPIRE")" || return 1
  USER_EXPIRE="${exp:-__CLEAR__}"
  USER_QUOTA_MB="" USER_QUOTA_DAYS="" USER_PACKAGE="" USER_BANDWIDTH_MBPS=""
  local tx
  admin_lock_acquire || return 1
  tx="$(users_tx_snapshot)" || { admin_lock_release; return 1; }
  if ! users_update_fields "$name"; then
    users_tx_rollback "$tx" 0
    admin_lock_release
    return 1
  fi
  if [ -n "$exp" ]; then
    local today
    today="$(today_ymd)"
    if [[ "$exp" < "$today" || "$exp" == "$today" ]]; then
      if ! users_set_enabled "$name" 0; then
        users_tx_rollback "$tx" 0
        admin_lock_release
        return 1
      fi
      disabled_now=1
      disabled_port="$(users_get_field "$name" port 2>/dev/null || true)"
    fi
  fi
  if ! apply_users_config "$tx"; then
    admin_lock_release
    return 1
  fi
  if [ "$disabled_now" -eq 1 ] && valid_port "$disabled_port"; then
    close_pairs="${PROTOCOL:-TCP}|${disabled_port}"
    [ "$PROTOCOL" != "BOTH" ] || close_pairs="TCP|${disabled_port}"$'\n'"UDP|$((disabled_port + 1))"
    close_firewall_for_bindings "$close_pairs"
    users_sync_primary_globals
    if ! save_install_state; then
      users_tx_rollback "$tx" 1
      open_firewall_for_pairs "$close_pairs"
      admin_lock_release
      return 1
    fi
  fi
  users_tx_commit "$tx"
  admin_lock_release
  t "已设置 ${name} 到期=${exp:-永不过期}" "Set ${name} expire=${exp:-never}"
}

do_user_enable() {
  require_root
  mita_installed || die "$(t 'mita 未安装' 'mita is not installed')"
  load_install_state
  users_ensure_loaded
  local name="${USER_SHOW_NAME:-${USERNAME:-}}"
  [ -n "$name" ] || die "$(t '需要用户名' 'Username required')"
  local exp today tx old_pairs
  admin_lock_acquire || return 1
  tx="$(users_tx_snapshot)" || { admin_lock_release; return 1; }
  exp="$(users_get_field "$name" expire_at 2>/dev/null || true)"
  today="$(today_ymd)"
  if [ -n "$exp" ] && { [[ "$exp" < "$today" ]] || [[ "$exp" == "$today" ]]; }; then
    users_tx_commit "$tx"
    admin_lock_release
    warn "$(t "用户 $name 已到期 ($exp)，请先 --user-set-expire 续期" \
      "User $name expired ($exp); renew with --user-set-expire first")"
    return 1
  fi
  old_pairs="$(multi_user_port_protocol_pairs)"
  if ! users_set_enabled "$name" 1; then
    users_tx_rollback "$tx" 0
    admin_lock_release
    return 1
  fi
  if ! apply_users_config "$tx"; then
    admin_lock_release
    return 1
  fi
  users_sync_primary_globals
  if ! save_install_state; then
    users_tx_rollback "$tx" 1
    open_firewall_for_pairs "$old_pairs"
    admin_lock_release
    return 1
  fi
  open_firewall_for_pairs "$(multi_user_port_protocol_pairs)"
  users_tx_commit "$tx"
  admin_lock_release
  t "已启用用户 $name" "Enabled user $name"
}

do_user_disable() {
  require_root
  mita_installed || die "$(t 'mita 未安装' 'mita is not installed')"
  load_install_state
  users_ensure_loaded
  local name="${USER_SHOW_NAME:-${USERNAME:-}}"
  [ -n "$name" ] || die "$(t '需要用户名' 'Username required')"
  local en_n disabled_port close_pairs tx
  admin_lock_acquire || return 1
  tx="$(users_tx_snapshot)" || { admin_lock_release; return 1; }
  disabled_port="$(users_get_field "$name" port 2>/dev/null || true)"
  en_n="$(python3 -c '
import json,sys
d=json.load(open(sys.argv[1]))
print(sum(1 for u in (d.get("users") or []) if u.get("enabled", True) and u.get("name")!=sys.argv[2]))
' "$MITA_USERS_STATE" "$name" 2>/dev/null || echo 0)"
  if [ "${en_n:-0}" -lt 1 ]; then
    users_tx_commit "$tx"
    admin_lock_release
    die "$(t '不能停用最后一个启用中的用户' 'Cannot disable the last enabled user')"
  fi
  if ! users_set_enabled "$name" 0; then
    users_tx_rollback "$tx" 0
    admin_lock_release
    return 1
  fi
  if ! apply_users_config "$tx"; then
    admin_lock_release
    return 1
  fi
  if valid_port "$disabled_port"; then
    close_pairs="${PROTOCOL:-TCP}|${disabled_port}"
    if [ "$PROTOCOL" = "BOTH" ]; then
      close_pairs="TCP|${disabled_port}"$'\n'"UDP|$((disabled_port + 1))"
    fi
    close_firewall_for_bindings "$close_pairs"
  fi
  users_sync_primary_globals
  if ! save_install_state; then
    users_tx_rollback "$tx" 1
    open_firewall_for_pairs "$close_pairs"
    admin_lock_release
    return 1
  fi
  users_tx_commit "$tx"
  admin_lock_release
  t "已停用用户 $name（端口仍保留，可再次启用）" "Disabled $name (port kept; can re-enable)"
}

do_user_scan() {
  # cron/timer 入口：到期停用 + 日历月配额重置
  require_root 2>/dev/null || true
  load_install_state 2>/dev/null || true
  users_state_exists || return 0
  local out="" cal="" rc=0
  admin_lock_acquire || return 1
  if ! out="$(users_scan_expired)"; then
    warn "$(t '到期用户扫描失败，状态已回滚' 'Expired-user scan failed; state rolled back')"
    rc=1
  fi
  if ! cal="$(users_scan_calendar_quota_reset)"; then
    warn "$(t '日历月配额重置失败，状态已回滚' 'Calendar quota reset failed; state rolled back')"
    rc=1
  fi
  admin_lock_release
  if [ -n "$out" ]; then
    t "已停用: $(printf '%s' "$out" | tr '\n' ' ')" \
      "disabled: $(printf '%s' "$out" | tr '\n' ' ')"
  fi
  if [ -n "$cal" ]; then
    t "已重置配额: $(printf '%s' "$cal" | tr '\n' ' ')" \
      "quota-reset: $(printf '%s' "$cal" | tr '\n' ' ')"
  fi
  return "$rc"
}

do_user_usage() {
  require_root 2>/dev/null || true
  mita_installed || die "$(t 'mita 未安装' 'mita is not installed')"
  users_isolated_mode || die "$(t 'schema v3 Mieru 状态必须使用 isolated-v2' \
    'Schema-v3 Mieru state must use isolated-v2')"
  local iid iname iport
  while IFS=$'\t' read -r iid iname iport; do
    [ -n "$iid" ] || continue
    msg ""
    t "【${iname} / 专属实例 ${iid}】" "[${iname} / dedicated instance ${iid}]"
    instance_cmd "$iid" get users 2>/dev/null \
      || warn "$(t "${iname}: mita get users 不可用" "${iname}: mita get users unavailable")"
    instance_cmd "$iid" get quotas 2>/dev/null \
      || warn "$(t "${iname}: mita get quotas 不可用" "${iname}: mita get quotas unavailable")"
  done < <(users_enabled_instance_rows)
  msg ""
  t '【本地套餐配置】' '[Local package config]'
  if users_state_exists; then
    t '用户名         端口   配额模式 配额_MB    带宽_Mbps' \
      'USER           PORT   MODE     QUOTA_MB   BW_Mbps'
    python3 -c '
import json,sys
d=json.load(open(sys.argv[1]))
rolling_l,calendar_l=sys.argv[2:4]
for u in d.get("users") or []:
    raw_mode=u.get("quota_mode") or "rolling"
    print("%-14s %-6s %-8s %-10s %-8s" % (
      (u.get("name") or "")[:14],
      u.get("port") or "",
      (calendar_l if raw_mode == "calendar" else rolling_l)[:8],
      u.get("quota_mb") or 0,
      u.get("bandwidth_mbps") or 0,
    ))
' "$MITA_USERS_STATE" "$(t '滚动' 'rolling')" "$(t '日历月' 'calendar')"
  fi
}

do_user_export_clients() {
  require_root
  load_install_state
  users_ensure_loaded
  users_state_exists || die "$(t '无用户状态' 'No users state')"
  local dir="${MITA_CLIENT_EXPORT_DIR:-/root/mieru-clients}"
  local ts ip name safe_name backend_ip
  ts="$(date +%Y%m%d_%H%M%S)_$$_${RANDOM}"
  dir="${dir%/}/${ts}"
  run mkdir -p "$dir"
  run chmod 0700 "$dir" 2>/dev/null || true
  load_install_state
  backend_ip="$(public_ip 2>/dev/null || true)"
  t "导出目录: $dir" "Export dir: $dir" >&2
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    local password port saved_u saved_p saved_port saved_advertise_host saved_advertise_port proto f links_file
    password="$(users_get_field "$name" password)" || continue
    port="$(users_get_field "$name" port)" || continue
    saved_u="$USERNAME"; saved_p="$PASSWORD"; saved_port="$PORT"
    saved_advertise_host="$ADVERTISE_HOST"; saved_advertise_port="$ADVERTISE_PORT"
    USERNAME="$name"; PASSWORD="$password"; PORT="$port"
    ADVERTISE_HOST="$(users_get_field "$name" advertise_host 2>/dev/null || true)"
    ADVERTISE_PORT="$(users_get_field "$name" advertise_port 2>/dev/null || true)"
    ip="$(advertised_host || echo 'YOUR_SERVER_IP')"
    prepare_traffic_pattern_export
    safe_name="$(safe_filename_component "$name")"
    [ -n "$safe_name" ] || safe_name="user"
    links_file="${dir}/${safe_name}_links.txt"
    : >"$links_file"
    while IFS= read -r proto; do
      [ -n "$proto" ] || continue
      f="${dir}/${safe_name}_$(proto_lower "$proto").json"
      build_client_json_for "$ip" "$proto" >"$f"
      chmod 0600 "$f" 2>/dev/null || true
      generate_share_link_for "$ip" "$proto" >>"$links_file"
      printf '\n' >>"$links_file"
    done < <(protocols_for_mode)
    chmod 0600 "$links_file" 2>/dev/null || true
    print_client_endpoint_mapping "$backend_ip" >&2
    USERNAME="$saved_u"; PASSWORD="$saved_p"; PORT="$saved_port"
    ADVERTISE_HOST="$saved_advertise_host"; ADVERTISE_PORT="$saved_advertise_port"
    t "  已导出: $name" "  Exported: $name" >&2
  done < <(python3 -c '
import json,sys
d=json.load(open(sys.argv[1]))
for u in d.get("users") or []:
    if u.get("enabled", True):
        print(u.get("name") or "")
' "$MITA_USERS_STATE")
  t "完成: $dir" "Done: $dir" >&2
  printf '%s\n' "$dir"
}
