# 在 flock 下执行 python -c（$1=代码）；环境变量传参
users_py_locked() {
  users_require_python
  if [ "${DRY_RUN:-0}" -eq 1 ]; then
    msg "[dry-run] update users state: $MITA_USERS_STATE"
    return 0
  fi
  run mkdir -p "$(dirname "$MITA_USERS_STATE")" "$(dirname "$MITA_USERS_LOCK")"
  local code="$1"
  if command -v flock >/dev/null 2>&1; then
    flock -w 30 "$MITA_USERS_LOCK" env MITA_USERS_STATE="$MITA_USERS_STATE" \
      _U_NAME="${_U_NAME-}" _U_PASS="${_U_PASS-}" _U_PORT="${_U_PORT-}" _U_PROTO="${_U_PROTO-}" \
      _U_QUOTA_MB="${_U_QUOTA_MB-}" _U_QUOTA_DAYS="${_U_QUOTA_DAYS-}" \
      _U_QUOTA_MODE="${_U_QUOTA_MODE-}" \
      _U_EXPIRE="${_U_EXPIRE-}" _U_PACKAGE="${_U_PACKAGE-}" _U_ENABLED="${_U_ENABLED-}" \
      _U_BW="${_U_BW-}" _U_PRIMARY="${_U_PRIMARY-}" \
      _U_ADVERTISE_HOST="${_U_ADVERTISE_HOST-}" _U_ADVERTISE_PORT="${_U_ADVERTISE_PORT-}" \
      _U_DEPLOYMENT_MODEL="${_U_DEPLOYMENT_MODEL-}" \
      python3 -c "$code"
  else
    MITA_USERS_STATE="$MITA_USERS_STATE" \
      _U_NAME="${_U_NAME-}" _U_PASS="${_U_PASS-}" _U_PORT="${_U_PORT-}" _U_PROTO="${_U_PROTO-}" \
      _U_QUOTA_MB="${_U_QUOTA_MB-}" _U_QUOTA_DAYS="${_U_QUOTA_DAYS-}" \
      _U_QUOTA_MODE="${_U_QUOTA_MODE-}" \
      _U_EXPIRE="${_U_EXPIRE-}" _U_PACKAGE="${_U_PACKAGE-}" _U_ENABLED="${_U_ENABLED-}" \
      _U_BW="${_U_BW-}" _U_PRIMARY="${_U_PRIMARY-}" \
      _U_ADVERTISE_HOST="${_U_ADVERTISE_HOST-}" _U_ADVERTISE_PORT="${_U_ADVERTISE_PORT-}" \
      _U_DEPLOYMENT_MODEL="${_U_DEPLOYMENT_MODEL-}" \
      python3 -c "$code"
  fi
}

normalize_quota_mode() {
  case "$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')" in
    calendar|cal|month|monthly|日历|月|自然月) printf 'calendar' ;;
    rolling|roll|滚动) printf 'rolling' ;;
    *) return 1 ;;
  esac
}

current_year_month() {
  date +%Y-%m 2>/dev/null || python3 -c 'import datetime;print(datetime.date.today().strftime("%Y-%m"))'
}

users_get_field() {
  # users_get_field <name> <field>
  local name="$1" field="$2"
  users_state_exists || return 1
  python3 -c '
import json, sys
name, field, path = sys.argv[1], sys.argv[2], sys.argv[3]
d = json.load(open(path))
for u in d.get("users") or []:
    if u.get("name") == name:
        v = u.get(field, "")
        if field == "enabled":
            print("1" if v is not False else "0")
        else:
            print(v if v is not None else "")
        sys.exit(0)
sys.exit(1)
' "$name" "$field" "$MITA_USERS_STATE" 2>/dev/null
}

users_name_exists() {
  local name="$1"
  [ -n "$(users_get_field "$name" name 2>/dev/null || true)" ]
}

users_all_ports() {
  users_state_exists || return 0
  # 协议经 argv 传入
  python3 -c '
import json, sys, os
d = json.load(open(sys.argv[1]))
proto = (sys.argv[2] if len(sys.argv) > 2 else "") or os.environ.get("PROTOCOL", "TCP")
for u in d.get("users") or []:
    p = u.get("port")
    if p is None:
        continue
    try:
        p = int(p)
    except Exception:
        continue
    print(p)
    if proto == "BOTH":
        print(p + 1)
' "$MITA_USERS_STATE" "${PROTOCOL:-TCP}" 2>/dev/null
}

port_is_listening() {
  local p="$1" proto="${2:-ANY}"
  case "$proto" in
    TCP|UDP) nb_port_is_listening "$proto" "$p" ;;
    *) nb_port_is_listening TCP "$p" || nb_port_is_listening UDP "$p" ;;
  esac
}

port_required_bindings() {
  local p
  p="$(normalize_uint "$1")" || return 1
  case "${PROTOCOL:-TCP}" in
    UDP) printf 'UDP|%s\n' "$p" ;;
    BOTH)
      printf 'TCP|%s\n' "$p"
      printf 'UDP|%s\n' "$((p + 1))"
      ;;
    *) printf 'TCP|%s\n' "$p" ;;
  esac
}

port_available_for_mode() {
  local p="$1" binding proto bind_port
  valid_port "$p" || return 1
  if [ "${PROTOCOL:-TCP}" = "BOTH" ] && [ "$p" -ge 65535 ]; then
    return 1
  fi
  while IFS='|' read -r proto bind_port; do
    [ -n "$proto" ] && [ -n "$bind_port" ] || continue
    nb_port_is_tail_base_reserved "$bind_port" && return 1
    port_is_listening "$bind_port" "$proto" && return 1
  done < <(port_required_bindings "$p")
  return 0
}

port_listener_details() {
  local p="$1" only_proto="${2:-}" bindings proto bind_port flags line
  command -v ss >/dev/null 2>&1 || return 0
  if [ -n "$only_proto" ]; then
    bindings="${only_proto}|${p}"
  else
    bindings="$(port_required_bindings "$p")"
  fi
  while IFS='|' read -r proto bind_port; do
    [ -n "$proto" ] && [ -n "$bind_port" ] || continue
    if nb_port_is_tail_base_reserved "$bind_port"; then
      nb_describe_port_conflict "$proto" "$bind_port"
      continue
    fi
    case "$proto" in
      TCP) flags="-Hlntp" ;;
      UDP) flags="-Hlnup" ;;
      *) flags="-Hlntup" ;;
    esac
    while IFS= read -r line; do
      [ -n "$line" ] && msg "  ${proto}/${bind_port}: ${line}"
    done < <(ss "$flags" 2>/dev/null | awk -v port="$bind_port" '
      {
        for (i = 1; i <= NF; i++) {
          if ($i ~ (":" port "$")) {
            print
            break
          }
        }
      }
    ')
  done <<<"$bindings"
}

select_available_port() {
  local selected=""
  if selected="$(derive_port_from_ip 2>/dev/null)" && [ -n "$selected" ]; then
    printf '%s' "$selected"
    return 0
  fi
  selected="$(random_available_port 2>/dev/null)" || return 1
  [ -n "$selected" ] || return 1
  printf '%s' "$selected"
}

ensure_install_port_available() {
  local old_port="$PORT" replacement=""
  port_available_for_mode "$PORT" && return 0
  warn "$(t "端口 ${PORT} 与当前 ${PROTOCOL} 监听需求冲突" \
    "Port ${PORT} conflicts with current ${PROTOCOL} listener requirements")"
  port_listener_details "$PORT"
  if [ "${PORT_AUTO_SELECTED:-0}" -eq 1 ]; then
    replacement="$(select_available_port)" || {
      die "$(t '未找到可用监听端口' 'No available listen port found')" || return 1
    }
    PORT="$replacement"
    t "自动端口 ${old_port} 已被占用，改用 ${PORT}" \
      "Auto-selected port ${old_port} became busy; switched to ${PORT}"
    return 0
  fi
  die "$(t "指定端口 ${PORT} 已被占用，请换一个端口" \
    "Requested port ${PORT} is already in use; choose another port")" || return 1
}

port_is_allocated() {
  local p="$1" used
  while IFS= read -r used; do
    [ -n "$used" ] || continue
    [ "$used" = "$p" ] && return 0
  done < <(users_all_ports)
  return 1
}

# 计算端口池起止（写入全局 _pool_lo _pool_hi）
users_port_pool_bounds() {
  if [ -n "${USER_PORT_POOL_START:-}" ] && [ -n "${USER_PORT_POOL_END:-}" ]; then
    _pool_lo="$USER_PORT_POOL_START"
    _pool_hi="$USER_PORT_POOL_END"
    return 0
  fi
  local base
  if base="$(derive_port_base 2>/dev/null)"; then
    _pool_lo=$((base + 1))
    _pool_hi=$((base + 99))
    [ "${PROTOCOL:-TCP}" = "BOTH" ] && _pool_hi=$((base + 98))
    return 0
  fi
  # 无 IP 尾号时：主端口附近 或 默认 20000-29999
  if [ -n "${PORT:-}" ] && valid_port "$PORT"; then
    _pool_lo=$((PORT + 2))
    _pool_hi=$((PORT + 200))
    [ "$_pool_hi" -gt 65535 ] && _pool_hi=65535
    [ "$_pool_lo" -lt 1025 ] && _pool_lo=1025
    return 0
  fi
  _pool_lo=20000
  _pool_hi=29999
}

allocate_user_port() {
  # 可选参数: 首选端口；成功打印端口
  local prefer="${1:-}" p step=1
  [ "${PROTOCOL:-TCP}" = "BOTH" ] && step=2
  if [ -n "$prefer" ]; then
    valid_port "$prefer" || { die "$(t "非法端口: $prefer" "Invalid port: $prefer")" || return 1; }
    prefer="$(normalize_uint "$prefer")"
    if [ "$PROTOCOL" = "BOTH" ]; then
      valid_port "$((prefer + 1))" || { die "$(t '双协议需要主端口 ≤65534' 'Dual protocol needs main port ≤65534')" || return 1; }
    fi
    if port_is_allocated "$prefer"; then
      warn "$(t "端口 ${prefer} 已被其它用户占用" "Port ${prefer} already allocated")"
      return 1
    fi
    if ! port_available_for_mode "$prefer"; then
      warn "$(t "端口 ${prefer} 不满足 ${PROTOCOL} 监听需求" \
        "Port ${prefer} is unavailable for ${PROTOCOL}")"
      port_listener_details "$prefer"
      return 1
    fi
    if [ "$PROTOCOL" = "BOTH" ] && port_is_allocated "$((prefer + 1))"; then
      warn "$(t "UDP 端口 $((prefer + 1)) 不可用" "UDP port $((prefer + 1)) unavailable")"
      return 1
    fi
    printf '%s' "$prefer"
    return 0
  fi
  users_port_pool_bounds
  p="$_pool_lo"
  while [ "$p" -le "$_pool_hi" ]; do
    if ! port_is_allocated "$p" && port_available_for_mode "$p"; then
      if [ "$PROTOCOL" != "BOTH" ] || ! port_is_allocated "$((p + 1))"; then
        printf '%s' "$p"
        return 0
      fi
    fi
    p=$((p + step))
  done
  die "$(t "端口池 ${_pool_lo}-${_pool_hi} 已满，请指定 --port 或扩大池" \
    "Port pool ${_pool_lo}-${_pool_hi} exhausted; pass --port or enlarge pool")" || return 1
}

users_migrate_from_primary() {
  # 将当前 USERNAME/PASSWORD/PORT 写入 users.json（若空）
  users_require_python
  [ -n "${USERNAME:-}" ] || return 0
  [ -n "${PORT:-}" ] || return 0
  admin_lock_acquire || return 1
  if users_state_exists; then
    local n
    n="$(users_count)"
    if [ "${n:-0}" -gt 0 ]; then
      admin_lock_release
      return 0
    fi
  fi
  run mkdir -p "$(dirname "$MITA_USERS_STATE")"
  if ! python3 -c '
import hashlib, json, sys, time
path, name, pwd, port, proto, advertise_host, advertise_port = sys.argv[1:8]
port = int(port)
advertise_port = int(advertise_port) if advertise_port else ""
instance_id = "u" + hashlib.sha256(("%s\0%s" % (name, port)).encode()).hexdigest()[:16]
d = {"version": 2, "protocol": proto, "users": [{
    "instance_id": instance_id,
    "name": name,
    "password": pwd,
    "port": port,
    "advertise_host": advertise_host,
    "advertise_port": advertise_port,
    "enabled": True,
    "quota_mb": 0,
    "quota_days": 0,
    "quota_mode": "rolling",
    "last_quota_reset": "",
    "expire_at": "",
    "package": "unlimited",
    "bandwidth_mbps": 0,
    "created_at": int(time.time()),
    "updated_at": int(time.time()),
}]}
json.dump(d, open(path, "w"), indent=2)
' "$MITA_USERS_STATE" "$USERNAME" "$PASSWORD" "$PORT" "${PROTOCOL:-TCP}" \
    "${ADVERTISE_HOST:-}" "${ADVERTISE_PORT:-}"
  then
    admin_lock_release
    return 1
  fi
  run chmod 0600 "$MITA_USERS_STATE" 2>/dev/null || true
  MULTI_USER_MODE=1
  install_users_scheduler 2>/dev/null || true
  admin_lock_release
}

users_sync_primary_globals() {
  # 用状态库第一个启用用户填充 USERNAME/PASSWORD/PORT（兼容旧摘要）
  users_state_exists || return 0
  local line rest
  line="$(python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
for u in d.get("users") or []:
    if u.get("enabled", True):
        print("%s\t%s\t%s" % (u.get("name") or "", u.get("password") or "", u.get("port") or ""))
        break
' "$MITA_USERS_STATE" 2>/dev/null)" || return 0
  [ -n "$line" ] || return 0
  USERNAME="${line%%$'\t'*}"
  rest="${line#*$'\t'}"
  PASSWORD="${rest%%$'\t'*}"
  PORT="${rest#*$'\t'}"
  ADVERTISE_HOST="$(users_get_field "$USERNAME" advertise_host 2>/dev/null || true)"
  ADVERTISE_PORT="$(users_get_field "$USERNAME" advertise_port 2>/dev/null || true)"
  MULTI_USER_MODE=1
}

users_ensure_loaded() {
  load_install_state
  if users_state_exists && [ "$(users_count)" -gt 0 ]; then
    MULTI_USER_MODE=1
    users_sync_primary_globals
    return 0
  fi
  # 尝试从 mita / 安装状态迁移
  if [ -n "${USERNAME:-}" ] && [ -n "${PORT:-}" ]; then
    users_migrate_from_primary
  fi
}

users_add() {
  local name="$1" password="$2" port_pref="${3:-}" port rc expire_at
  local advertise_host="${4:-}" advertise_port="${5:-}"
  local bw="${USER_BANDWIDTH_MBPS:-0}" qmode
  users_require_python || return 1
  [ -n "$name" ] || { die "$(t '用户名不能为空' 'Username required')" || return 1; }
  [ -n "$password" ] || password="$(random_token)"
  validate_proxy_credentials "$name" "$password" || return 1
  validate_advertise_endpoint_values "$advertise_host" "$advertise_port" "${PROTOCOL:-TCP}" || return 1
  [ -z "$advertise_port" ] || advertise_port="$(normalize_uint "$advertise_port")"
  valid_bandwidth_mbps "$bw" || {
    warn "$(t '带宽必须是 0-1000000 Mbps 的整数' \
      'Bandwidth must be an integer from 0 to 1000000 Mbps')"
    return 1
  }
  apply_user_package_defaults || return 1
  if ! valid_nonnegative_int32 "${USER_QUOTA_MB:-0}" \
     || ! valid_nonnegative_int32 "${USER_QUOTA_DAYS:-0}"; then
    warn "$(t '配额 MB/天数必须是 int32 范围内的非负整数' \
      'Quota MB/days must be non-negative int32 values')"
    return 1
  fi
  expire_at=""
  if [ -n "${USER_EXPIRE:-}" ]; then
    expire_at="$(parse_expire_date "$USER_EXPIRE")" || return 1
  fi
  load_install_state
  if ! users_state_exists || [ "$(users_count)" -eq 0 ]; then
    if [ -n "${USERNAME:-}" ] && [ -n "${PORT:-}" ] && [ -n "${PASSWORD:-}" ]; then
      users_migrate_from_primary
    else
      users_state_init_empty
    fi
  fi
  if users_name_exists "$name"; then
    warn "$(t "用户已存在: $name" "User already exists: $name")"
    return 1
  fi
  if ! port="$(allocate_user_port "$port_pref")"; then
    return 1
  fi
  users_backup_now pre-add >/dev/null 2>&1 || true
  qmode="$(normalize_quota_mode "${USER_QUOTA_MODE:-rolling}")" || {
    warn "$(t '配额模式仅支持 rolling 或 calendar' \
      'Quota mode must be rolling or calendar')"
    return 1
  }
  # 套餐默认 rolling；显式 calendar 保留
  [ -n "${USER_QUOTA_MODE:-}" ] || qmode="rolling"
  _U_NAME="$name" _U_PASS="$password" _U_PORT="$port" _U_PROTO="${PROTOCOL:-TCP}"
  _U_QUOTA_MB="${USER_QUOTA_MB:-0}" _U_QUOTA_DAYS="${USER_QUOTA_DAYS:-0}"
  _U_QUOTA_MODE="$qmode"
  _U_EXPIRE="${expire_at}" _U_PACKAGE="${USER_PACKAGE:-}" _U_BW="$bw"
  _U_ADVERTISE_HOST="$advertise_host" _U_ADVERTISE_PORT="$advertise_port"
  set +e
  users_py_locked '
import json, os, time, sys, datetime, secrets
path = os.environ["MITA_USERS_STATE"]
name = os.environ["_U_NAME"]
password = os.environ["_U_PASS"]
port = int(os.environ["_U_PORT"])
proto = os.environ.get("_U_PROTO", "TCP")
try:
    qmb = int(os.environ.get("_U_QUOTA_MB") or "0")
except Exception:
    qmb = 0
try:
    qdays = int(os.environ.get("_U_QUOTA_DAYS") or "0")
except Exception:
    qdays = 0
try:
    bw = int(os.environ.get("_U_BW") or "0")
except Exception:
    bw = 0
qmode = (os.environ.get("_U_QUOTA_MODE") or "rolling").strip().lower()
if qmode not in ("rolling", "calendar"):
    qmode = "rolling"
expire = (os.environ.get("_U_EXPIRE") or "").strip()
package = (os.environ.get("_U_PACKAGE") or "").strip() or ("custom" if qmb > 0 else "unlimited")
advertise_host = (os.environ.get("_U_ADVERTISE_HOST") or "").strip()
advertise_port = int(os.environ.get("_U_ADVERTISE_PORT")) if os.environ.get("_U_ADVERTISE_PORT") else ""
try:
    d = json.load(open(path))
except Exception:
    d = {"version": 1, "users": []}
users = d.setdefault("users", [])
for u in users:
    if u.get("name") == name:
        sys.exit(2)
    if int(u.get("port") or 0) == port:
        sys.exit(3)
ym = datetime.date.today().strftime("%Y-%m")
used_ids={str(u.get("instance_id") or "") for u in users}
while True:
    instance_id="u"+secrets.token_hex(8)
    if instance_id not in used_ids:
        break
users.append({
    "instance_id": instance_id,
    "name": name,
    "password": password,
    "port": port,
    "advertise_host": advertise_host,
    "advertise_port": advertise_port,
    "enabled": True,
    "quota_mb": qmb,
    "quota_days": (qdays if qdays > 0 else 30) if qmb > 0 else 0,
    "quota_mode": qmode,
    "last_quota_reset": ym if (qmb > 0 and qmode == "calendar") else "",
    "expire_at": expire,
    "package": package,
    "bandwidth_mbps": bw,
    "created_at": int(time.time()),
    "updated_at": int(time.time()),
})
d["protocol"] = proto
json.dump(d, open(path, "w"), indent=2)
'
  rc=$?
  set -e
  if [ "$rc" -eq 2 ]; then
    warn "$(t "用户已存在: $name" "User already exists: $name")"
    return 1
  fi
  if [ "$rc" -eq 3 ]; then
    warn "$(t "端口已被占用: $port" "Port already allocated: $port")"
    return 1
  fi
  if [ "$rc" -ne 0 ]; then
    warn "$(t "写入用户状态失败 ($rc)" "Failed to write user state ($rc)")"
    return 1
  fi
  MULTI_USER_MODE=1
  install_users_scheduler 2>/dev/null || true
  t "已添加用户 ${name}，专属端口 ${port}，套餐=${USER_PACKAGE:-unlimited} 配额=$(quota_label "${USER_QUOTA_MB:-0}" "${USER_QUOTA_DAYS:-0}") 限速=${bw}Mbps 到期=${expire_at:-永不过期}" \
    "Added ${name}; dedicated port ${port}, package=${USER_PACKAGE:-unlimited} quota=$(quota_label "${USER_QUOTA_MB:-0}" "${USER_QUOTA_DAYS:-0}") rate=${bw}Mbps expire=${expire_at:-never}" >&2
  printf '%s' "$port"
}

users_del() {
  local name="$1" freed rc
  users_require_python || return 1
  [ -n "$name" ] || { die "$(t '用户名不能为空' 'Username required')" || return 1; }
  users_state_exists || { die "$(t '无用户状态文件' 'No users state file')" || return 1; }
  users_name_exists "$name" || { die "$(t "用户不存在: $name" "User not found: $name")" || return 1; }
  freed="$(users_get_field "$name" port)"
  users_backup_now pre-del >/dev/null 2>&1 || true
  _U_NAME="$name"
  set +e
  users_py_locked '
import json, os, sys
path = os.environ["MITA_USERS_STATE"]
name = os.environ["_U_NAME"]
d = json.load(open(path))
before = len(d.get("users") or [])
d["users"] = [u for u in (d.get("users") or []) if u.get("name") != name]
if len(d["users"]) == before:
    sys.exit(2)
json.dump(d, open(path, "w"), indent=2)
'
  rc=$?
  set -e
  [ "$rc" -eq 0 ] || { die "$(t "删除失败: $name" "Delete failed: $name")" || return 1; }
  t "已删除用户 ${name}，释放端口 ${freed}" "Deleted user ${name}, freed port ${freed}" >&2
  printf '%s' "$freed"
}

# 从 users.json 生成 portBindings + users 片段路径（完整 server json 由 write_server_config_multi 写）
write_server_config_multi() {
  local cfg tp tp_section=""
  users_require_python
  users_state_exists || die "$(t '无多用户状态' 'No multi-user state')"
  ensure_traffic_seed
  tp="$(traffic_pattern_json '  ')"
  [ -n "$tp" ] && tp_section=",
${tp}"
  cfg="$(mktemp_file .json)"
  if ! MITA_USERS_STATE="$MITA_USERS_STATE" \
    _PROTO="${PROTOCOL:-TCP}" _MTU="${MTU:-1400}" \
    _CFG="$cfg" python3 - <<'PY'
import json, os, sys
path = os.environ["MITA_USERS_STATE"]
proto = os.environ.get("_PROTO", "TCP")
mtu = int(os.environ.get("_MTU", "1400"))
cfg_path = os.environ["_CFG"]
d = json.load(open(path))
users_out = []
bindings = []
seen = set()
for u in d.get("users") or []:
    if not u.get("enabled", True):
        continue
    name = u.get("name") or ""
    password = u.get("password") or ""
    try:
        port = int(u.get("port"))
    except Exception:
        continue
    if not name or not password:
        continue
    entry = {"name": name, "password": password}
    try:
        qmb = int(u.get("quota_mb") or 0)
    except Exception:
        qmb = 0
    try:
        qdays = int(u.get("quota_days") or 0)
    except Exception:
        qdays = 0
    qmode = (u.get("quota_mode") or "rolling").strip().lower()
    if qmb > 0:
        if qmode == "calendar":
            # 自然月：窗口取当月天数（28-31），月初由 user-scan 强制轮换
            import calendar, datetime
            t = datetime.date.today()
            qdays = calendar.monthrange(t.year, t.month)[1]
        elif qdays <= 0:
            qdays = 30
        entry["quotas"] = [{"days": qdays, "megabytes": qmb}]
    users_out.append(entry)
    if proto == "BOTH":
        pairs = [("TCP", port), ("UDP", port + 1)]
    else:
        pairs = [(proto, port)]
    for pr, p in pairs:
        key = (p, pr)
        if key in seen:
            continue
        seen.add(key)
        bindings.append({"port": p, "protocol": pr})
if not users_out:
    sys.stderr.write("no enabled users\n")
    sys.exit(1)
doc = {
    "portBindings": bindings,
    "users": users_out,
    "loggingLevel": "INFO",
    "mtu": mtu,
}
json.dump(doc, open(cfg_path, "w"), indent=2)
PY
  then
    die "$(t '生成多用户配置失败' 'Failed to build multi-user config')"
  fi
  # 追加 trafficPattern（若有）：与单用户路径一致的 JSON 片段
  if [ -n "$tp_section" ]; then
    if ! _CFG="$cfg" _TP="$tp_section" python3 - <<'PY' 2>/dev/null
import json, os, re
cfg = os.environ["_CFG"]
tp = os.environ.get("_TP", "").strip()
if not tp:
    raise SystemExit(0)
if tp.startswith(","):
    tp = tp[1:].strip()
# tp like: "trafficPattern": { ... }
m = re.match(r'"trafficPattern"\s*:\s*(\{.*\})\s*$', tp, re.S)
if not m:
    raise SystemExit(0)
doc = json.load(open(cfg))
doc["trafficPattern"] = json.loads(m.group(1))
json.dump(doc, open(cfg, "w"), indent=2)
PY
    then
      rm -f "$cfg"
      die "$(t '写入 trafficPattern 失败，已中止以避免静默丢失流量模式' \
        'Failed to write trafficPattern; aborted instead of silently dropping the traffic mode')"
    fi
  fi
  printf '%s' "$cfg"
}

users_enabled_names_from_state() {
  users_require_python || return 1
  users_state_exists || return 1
  python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
names = {
    str(u.get("name") or "")
    for u in (d.get("users") or [])
    if u.get("enabled", True) and str(u.get("name") or "")
}
print("\n".join(sorted(names)))
' "$MITA_USERS_STATE" 2>/dev/null
}

mita_actual_user_names() {
  local bin desc
  bin="$(mita_bin)" || return 1
  [ -x "$bin" ] || return 1
  desc="$("$bin" describe config 2>/dev/null)" || return 1
  [ -n "$desc" ] || return 1
  printf '%s' "$desc" | python3 -c '
import json, sys
d = json.load(sys.stdin)
names = {
    str(u.get("name") or "")
    for u in (d.get("users") or [])
    if str(u.get("name") or "")
}
print("\n".join(sorted(names)))
' 2>/dev/null
}

mita_delete_user_exact() {
  local name="$1" bin
  [ -n "$name" ] || return 1
  bin="$(mita_bin)" || return 1
  if [ "${DRY_RUN:-0}" -eq 1 ]; then
    msg "[dry-run] $(printf '%q ' "$bin" delete user "$name")"
    return 0
  fi
  "$bin" delete user "$name" >/dev/null 2>&1
}

# mita apply config 会合并用户而不是替换用户。这里把脚本管理的用户集合
# 显式同步成期望集合，确保删除、停用、到期和事务回滚真正撤销旧凭据。
mita_sync_user_names() {
  local desired_raw="${1:-}" desired actual stale after
  users_require_python || return 1
  desired="$(printf '%s\n' "$desired_raw" | sed '/^[[:space:]]*$/d' | LC_ALL=C sort -u)"
  [ -n "$desired" ] || {
    warn "$(t '拒绝同步空用户集合' 'Refusing to synchronize an empty user set')"
    return 1
  }
  if ! actual="$(mita_actual_user_names)"; then
    warn "$(t '无法读取 mita 实际用户集合，未执行删除' \
      'Cannot read the actual mita user set; no deletion was attempted')"
    return 1
  fi
  stale="$(DESIRED="$desired" ACTUAL="$actual" python3 -c '
import os
desired = set(filter(None, os.environ.get("DESIRED", "").splitlines()))
actual = set(filter(None, os.environ.get("ACTUAL", "").splitlines()))
print("\n".join(sorted(actual - desired)))
' 2>/dev/null)" || return 1
  if [ -n "$stale" ]; then
    local name
    while IFS= read -r name; do
      [ -n "$name" ] || continue
      if ! mita_delete_user_exact "$name"; then
        warn "$(t "无法从 mita 删除旧用户: $name" \
          "Failed to delete stale user from mita: $name")"
        return 1
      fi
      users_log "mita user revoked: $name"
    done <<< "$stale"
  fi
  if [ "${DRY_RUN:-0}" -eq 1 ]; then
    return 0
  fi
  if ! after="$(mita_actual_user_names)"; then
    warn "$(t '删除后无法重新读取 mita 用户集合' \
      'Cannot read the mita user set after synchronization')"
    return 1
  fi
  if ! DESIRED="$desired" ACTUAL="$after" python3 -c '
import os, sys
desired = set(filter(None, os.environ.get("DESIRED", "").splitlines()))
actual = set(filter(None, os.environ.get("ACTUAL", "").splitlines()))
sys.exit(0 if actual == desired else 1)
' 2>/dev/null; then
    warn "$(t 'mita 实际用户与 users.json 启用用户仍不一致' \
      'The actual mita users still differ from enabled users in users.json')"
    return 1
  fi
  return 0
}

mita_sync_users_to_state() {
  local desired
  desired="$(users_enabled_names_from_state)" || return 1
  mita_sync_user_names "$desired"
}

mita_sync_single_user() {
  local name="$1"
  [ -n "$name" ] || return 1
  mita_sync_user_names "$name"
}

multi_user_port_protocol_pairs() {
  # 输出 proto|port 每行（用于防火墙）
  users_state_exists || return 0
  python3 -c '
import json, sys
path, proto = sys.argv[1], sys.argv[2]
d = json.load(open(path))
for u in d.get("users") or []:
    if not u.get("enabled", True):
        continue
    port = int(u.get("port"))
    if proto == "BOTH":
        print(f"TCP|{port}")
        print(f"UDP|{port+1}")
    else:
        print(f"{proto}|{port}")
' "$MITA_USERS_STATE" "${PROTOCOL:-TCP}" 2>/dev/null
}

apply_users_config() {
  # 每个启用用户对应一个独立 mita 实例；端口、认证、配额 metrics 均为专属资源。
  local snapshot="${1:-}" rollback_reapply="${2:-1}" auto_host=""
  STAGE="应用多用户配置"
  admin_lock_acquire || return 1
  auto_host="$(public_ip 2>/dev/null || true)"
  if ! users_validate_state_file "$MITA_USERS_STATE" "${PROTOCOL:-TCP}" "$auto_host"; then
    users_tx_rollback "$snapshot" 0
    admin_lock_release
    warn "$(t 'users.json 校验失败（字段、监听端口或客户端展示入口冲突），未应用到专属实例' \
      'users.json validation failed (fields, listen ports, or client display endpoints conflict); dedicated instances were not changed')"
    return 1
  fi
  if [ "$(users_count)" -eq 0 ]; then
    users_tx_rollback "$snapshot" 0
    admin_lock_release
    warn "$(t '至少保留一个用户' 'Keep at least one user')"
    return 1
  fi
  if ! ensure_isolated_deployment "$rollback_reapply"; then
    users_tx_rollback "$snapshot" "$rollback_reapply"
    admin_lock_release
    return 1
  fi
  if ! apply_tc_limits; then
    users_tx_rollback "$snapshot" "$rollback_reapply"
    admin_lock_release
    return 1
  fi
  harden_mita_permissions 2>/dev/null || true
  admin_lock_release
  return 0
}

# 更新用户字段（不改 name/port/password 除非传入）
users_update_fields() {
  local name="$1"
  users_require_python || return 1
  users_name_exists "$name" || { warn "$(t "用户不存在: $name" "User not found: $name")"; return 1; }
  users_backup_now pre-update >/dev/null 2>&1 || true
  _U_NAME="$name"
  _U_QUOTA_MB="${USER_QUOTA_MB-}"
  _U_QUOTA_DAYS="${USER_QUOTA_DAYS-}"
  _U_QUOTA_MODE="${USER_QUOTA_MODE-}"
  _U_EXPIRE="${USER_EXPIRE-}"
  _U_PACKAGE="${USER_PACKAGE-}"
  _U_ENABLED="${_U_ENABLED-}"
  _U_PASS="${_U_PASS-}"
  _U_BW="${USER_BANDWIDTH_MBPS-}"
  set +e
  users_py_locked '
import json, os, time, sys, datetime
path = os.environ["MITA_USERS_STATE"]
name = os.environ["_U_NAME"]
d = json.load(open(path))
found = None
for u in d.get("users") or []:
    if u.get("name") == name:
        found = u
        break
if found is None:
    sys.exit(2)
# optional fields: empty string means skip; special __CLEAR__ for expire
qm = os.environ.get("_U_QUOTA_MB")
if qm is not None and qm != "":
    try:
        found["quota_mb"] = int(qm)
    except Exception:
        pass
qd = os.environ.get("_U_QUOTA_DAYS")
if qd is not None and qd != "":
    try:
        found["quota_days"] = int(qd)
    except Exception:
        pass
if found.get("quota_mb", 0) <= 0:
    found["quota_mb"] = 0
    found["quota_days"] = 0
qmode = os.environ.get("_U_QUOTA_MODE")
if qmode is not None and qmode != "":
    qmode = qmode.strip().lower()
    if qmode in ("calendar", "cal", "month", "monthly"):
        found["quota_mode"] = "calendar"
        if not found.get("last_quota_reset"):
            found["last_quota_reset"] = datetime.date.today().strftime("%Y-%m")
    else:
        found["quota_mode"] = "rolling"
ex = os.environ.get("_U_EXPIRE")
if ex is not None and ex != "":
    if ex in ("0", "never", "none", "-", "__CLEAR__"):
        found["expire_at"] = ""
    else:
        found["expire_at"] = ex
pkg = os.environ.get("_U_PACKAGE")
if pkg is not None and pkg != "":
    found["package"] = pkg
en = os.environ.get("_U_ENABLED")
if en is not None and en != "":
    found["enabled"] = en in ("1", "true", "True", "yes")
pw = os.environ.get("_U_PASS")
if pw is not None and pw != "":
    found["password"] = pw
bw = os.environ.get("_U_BW")
if bw is not None and bw != "":
    try:
        found["bandwidth_mbps"] = max(0, int(bw))
    except Exception:
        pass
found["updated_at"] = int(time.time())
json.dump(d, open(path, "w"), indent=2)
'
  local rc=$?
  set -e
  [ "$rc" -eq 0 ] || return 1
  return 0
}

users_set_advertise_endpoint() {
  local name="$1" host="${2:-}" port="${3:-}"
  users_name_exists "$name" || return 1
  validate_advertise_endpoint_values "$host" "$port" "${PROTOCOL:-TCP}" || return 1
  [ -z "$port" ] || port="$(normalize_uint "$port")"
  _U_NAME="$name" _U_ADVERTISE_HOST="$host" _U_ADVERTISE_PORT="$port"
  users_py_locked '
import json, os, sys, time
path=os.environ["MITA_USERS_STATE"]
name=os.environ.get("_U_NAME") or ""
host=os.environ.get("_U_ADVERTISE_HOST") or ""
port=os.environ.get("_U_ADVERTISE_PORT") or ""
d=json.load(open(path))
for u in d.get("users") or []:
    if u.get("name") == name:
        u["advertise_host"] = host
        u["advertise_port"] = int(port) if port else ""
        u["updated_at"] = int(time.time())
        json.dump(d, open(path, "w"), indent=2)
        raise SystemExit(0)
raise SystemExit(2)
'
}
