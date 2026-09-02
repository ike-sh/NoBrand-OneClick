# ---------- 多用户（阶段1 端口；阶段2 套餐 quotas + 到期停用） ----------

users_require_python() {
  command -v python3 >/dev/null 2>&1 || die "$(t '多用户管理需要 python3' 'python3 required for multi-user management')"
}

users_log() {
  local line quiet="${USERS_LOG_QUIET:-0}"
  line="$(date '+%Y-%m-%d %H:%M:%S') $*"
  printf '%s\n' "$line" >>"${MITA_USERS_LOG}" 2>/dev/null || true
  [ "$quiet" = "1" ] || msg "$line" >&2
}

# 套餐模板 → 设置 USER_QUOTA_MB / USER_QUOTA_DAYS / 可选默认到期
# unlimited: 0/0；trial: 10GB/7天；standard: 100GB/30天；custom: 用 CLI 值
apply_user_package_defaults() {
  local fill_missing="${1:-1}" pkg
  pkg="$(printf '%s' "${USER_PACKAGE:-}" | tr '[:upper:]' '[:lower:]')"
  case "$pkg" in
    "")
      ;;
    unlimited|unlimit|none|0|无限)
      USER_QUOTA_MB=0
      USER_QUOTA_DAYS=0
      USER_PACKAGE="unlimited"
      ;;
    trial|体验|test)
      [ -n "${USER_QUOTA_MB}" ] || USER_QUOTA_MB=10240
      [ -n "${USER_QUOTA_DAYS}" ] || USER_QUOTA_DAYS=7
      [ -n "${USER_EXPIRE}" ] || USER_EXPIRE="+7d"
      USER_PACKAGE="trial"
      ;;
    standard|std|标准|月包)
      [ -n "${USER_QUOTA_MB}" ] || USER_QUOTA_MB=102400
      [ -n "${USER_QUOTA_DAYS}" ] || USER_QUOTA_DAYS=30
      [ -n "${USER_EXPIRE}" ] || USER_EXPIRE="+30d"
      USER_PACKAGE="standard"
      ;;
    custom|自定义)
      USER_PACKAGE="custom"
      ;;
    *)
      warn "$(t "未知套餐 ${USER_PACKAGE}，忽略（可用 unlimited|trial|standard|custom）" \
        "Unknown package ${USER_PACKAGE}; use unlimited|trial|standard|custom")"
      USER_PACKAGE=""
      return 1
      ;;
  esac
  if [ "$fill_missing" = "1" ]; then
    [ -n "${USER_QUOTA_DAYS}" ] || USER_QUOTA_DAYS=30
    [ -n "${USER_QUOTA_MB}" ] || USER_QUOTA_MB=0
  elif [ -n "${USER_QUOTA_MB}" ]; then
    valid_nonnegative_int32 "$USER_QUOTA_MB" || return 1
    if [ "$USER_QUOTA_MB" -eq 0 ]; then
      USER_QUOTA_DAYS=0
    else
      [ -n "${USER_QUOTA_DAYS}" ] || USER_QUOTA_DAYS=30
    fi
  fi
}

# 解析到期：空/0/never → 空；+Nd → 今天+N天 YYYY-MM-DD；YYYY-MM-DD 原样
parse_expire_date() {
  local raw="$1" days
  raw="$(printf '%s' "$raw" | tr -d '[:space:]')"
  if [ -z "$raw" ] || [ "$raw" = "0" ] || [ "$raw" = "never" ] || [ "$raw" = "none" ] || [ "$raw" = "-" ]; then
    printf ''
    return 0
  fi
  if [[ "$raw" =~ ^\+([0-9]+)[dD]?$ ]]; then
    days="${BASH_REMATCH[1]}"
    if date -u -d "+${days} days" +%Y-%m-%d >/dev/null 2>&1; then
      date -u -d "+${days} days" +%Y-%m-%d
      return 0
    fi
    if date -u -v+"${days}"d +%Y-%m-%d >/dev/null 2>&1; then
      date -u -v+"${days}"d +%Y-%m-%d
      return 0
    fi
    # busybox / python fallback
    if command -v python3 >/dev/null 2>&1; then
      python3 -c "import datetime;print((datetime.date.today()+datetime.timedelta(days=int('${days}'))).isoformat())" 2>/dev/null
      return $?
    fi
    warn "$(t "当前系统无法计算相对日期: $raw" "Cannot calculate relative date on this system: $raw")"
    return 1
  fi
  if [[ "$raw" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
    if [ "$(date -d "$raw" +%Y-%m-%d 2>/dev/null || true)" = "$raw" ]; then
      printf '%s' "$raw"
      return 0
    fi
    if command -v python3 >/dev/null 2>&1 \
       && python3 -c 'import datetime,sys; datetime.date.fromisoformat(sys.argv[1])' "$raw" 2>/dev/null; then
      printf '%s' "$raw"
      return 0
    fi
    warn "$(t "无效日历日期: $raw" "Invalid calendar date: $raw")"
    return 1
  fi
  warn "$(t "无法解析到期日: $raw（用 YYYY-MM-DD 或 +30d）" "Bad expire: $raw (use YYYY-MM-DD or +30d)")"
  return 1
}

# 与 calendar 重置统一用本地日历日（与 mita 服务器本地时间一致）
today_ymd() {
  date +%Y-%m-%d 2>/dev/null || python3 -c 'import datetime;print(datetime.date.today().isoformat())'
}

quota_label() {
  local mb="${1:-0}" days="${2:-0}"
  if [ -z "$mb" ] || [ "$mb" = "0" ] || [ "$mb" = "null" ]; then
    t '不限量' 'unlimited'
    return
  fi
  if [ "$mb" -ge 1024 ] 2>/dev/null; then
    printf '%sGB/%sd' "$((mb / 1024))" "${days:-30}"
  else
    printf '%sMB/%sd' "$mb" "${days:-30}"
  fi
}

users_state_init_empty() {
  if [ "${DRY_RUN:-0}" -eq 1 ]; then
    msg "[dry-run] initialize users state: $MITA_USERS_STATE"
    return 0
  fi
  run mkdir -p "$(dirname "$MITA_USERS_STATE")"
  printf '{"version":2,"deployment_model":"%s","protocol":"%s","users":[]}\n' \
    "$MITA_DEPLOYMENT_MODEL" "${PROTOCOL:-TCP}" >"$MITA_USERS_STATE"
  run chmod 0600 "$MITA_USERS_STATE" 2>/dev/null || true
}

users_state_exists() {
  [ -f "$MITA_USERS_STATE" ] && [ -s "$MITA_USERS_STATE" ]
}

users_tx_snapshot() {
  local snapshot
  snapshot="$(mktemp_file .users.json)" || return 1
  if users_state_exists; then
    cp -f "$MITA_USERS_STATE" "$snapshot" || { rm -f "$snapshot"; return 1; }
  else
    printf '%s\n' '__MITA_USERS_STATE_ABSENT__' >"$snapshot"
  fi
  chmod 0600 "$snapshot" 2>/dev/null || true
  printf '%s' "$snapshot"
}

users_tx_commit() {
  local snapshot="${1:-}"
  [ -n "$snapshot" ] && prune_orphan_instances 2>/dev/null || true
  [ -n "$snapshot" ] && rm -f "$snapshot" 2>/dev/null || true
}

users_tx_restore() {
  local snapshot="${1:-}"
  [ -f "$snapshot" ] || return 1
  if grep -qx '__MITA_USERS_STATE_ABSENT__' "$snapshot" 2>/dev/null; then
    rm -f "$MITA_USERS_STATE" 2>/dev/null || true
    return 2
  fi
  run mkdir -p "$(dirname "$MITA_USERS_STATE")"
  cp -f "$snapshot" "$MITA_USERS_STATE" || return 1
  chmod 0600 "$MITA_USERS_STATE" 2>/dev/null || true
  return 0
}

users_tx_rollback() {
  local snapshot="${1:-}" reapply="${2:-0}" restored=0 restore_rc=0
  [ -n "$snapshot" ] || return 0
  # apply_users_config 失败时会自行消费快照；外层再次回滚应是安全空操作。
  [ -f "$snapshot" ] || return 0
  if users_tx_restore "$snapshot"; then
    restored=1
  else
    restore_rc=$?
    if [ "$restore_rc" -eq 2 ]; then
      restored=2
    else
      warn "$(t '用户状态回滚失败，请从最近备份恢复' \
        'Failed to roll back users state; restore the latest backup')"
    fi
  fi
  if [ "$restored" -gt 0 ] && [ "$reapply" -eq 1 ] && mita_installed 2>/dev/null; then
    MULTI_USER_MODE=1
    if [ "$restored" -eq 2 ]; then
      isolated_stop_all
      apply_tc_limits 2>/dev/null || true
    else
      if ! reconcile_isolated_instances 2>/dev/null; then
        warn "$(t '用户状态已回滚，但专属实例配置重新应用失败，请立即运行 doctor' \
          'Users state was rolled back, but reapplying dedicated instances failed; run doctor now')"
      fi
      apply_tc_limits 2>/dev/null || warn "$(t '用户状态已回滚，但旧限速规则未能完全恢复' \
        'Users state was rolled back, but previous rate filters were not fully restored')"
    fi
  fi
  users_tx_commit "$snapshot"
}

users_count() {
  users_state_exists || { printf '0'; return 0; }
  command -v python3 >/dev/null 2>&1 || { printf '0'; return 0; }
  python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(len(d.get("users") or []))' \
    "$MITA_USERS_STATE" 2>/dev/null || printf '0'
}

users_rate_limited_count() {
  users_state_exists || { printf '0'; return 0; }
  command -v python3 >/dev/null 2>&1 || { printf '0'; return 0; }
  python3 -c '
import json,sys
d=json.load(open(sys.argv[1]))
print(sum(
    1 for u in (d.get("users") or [])
    if u.get("enabled", True) and int(u.get("bandwidth_mbps") or 0) > 0
))
' "$MITA_USERS_STATE" 2>/dev/null || printf '0'
}

users_deployment_model() {
  users_state_exists || return 1
  python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("deployment_model") or "")' \
    "$MITA_USERS_STATE" 2>/dev/null
}

users_isolated_mode() {
  [ "$(users_deployment_model 2>/dev/null || true)" = "$MITA_DEPLOYMENT_MODEL" ]
}

users_enabled_instance_rows() {
  users_state_exists || return 1
  python3 -c '
import json,sys
d=json.load(open(sys.argv[1]))
for u in d.get("users") or []:
    if not u.get("enabled", True):
        continue
    instance_id=str(u.get("instance_id") or "")
    name=str(u.get("name") or "")
    port=int(u.get("port") or 0)
    if instance_id and name and port:
        print(f"{instance_id}\t{name}\t{port}")
' "$MITA_USERS_STATE" 2>/dev/null
}

users_all_instance_ids() {
  users_state_exists || return 0
  python3 -c '
import json,sys
d=json.load(open(sys.argv[1]))
for u in d.get("users") or []:
    instance_id=str(u.get("instance_id") or "")
    if instance_id: print(instance_id)
' "$MITA_USERS_STATE" 2>/dev/null | LC_ALL=C sort -u
}

instance_valid_id() {
  local id="${1:-}"
  [[ "$id" =~ ^u[0-9a-f]{16}$ ]]
}

instance_config_path() { printf '%s/%s/server.json' "$MITA_INSTANCES_DIR" "$1"; }
instance_socket_path() { printf '%s/%s.sock' "$MITA_INSTANCE_RUN_DIR" "$1"; }
instance_metrics_dir() { printf '%s/%s' "$MITA_INSTANCE_METRICS_DIR" "$1"; }
instance_metrics_file() { printf '%s/%s/metrics.pb' "$MITA_INSTANCE_METRICS_DIR" "$1"; }
instance_systemd_unit() { printf 'nobrand-mieru@%s.service' "$1"; }
instance_openrc_service() { printf 'nobrand-mieru-%s' "$1"; }

instance_cmd() {
  local id="$1"
  shift
  instance_valid_id "$id" || return 1
  env MITA_CONFIG_JSON_FILE="$(instance_config_path "$id")" \
      MITA_UDS_PATH="$(instance_socket_path "$id")" \
      "$(mita_bin)" "$@"
}

instance_wait_socket() {
  local id="$1" timeout="${2:-30}" i=0 sock
  sock="$(instance_socket_path "$id")"
  while [ "$i" -lt "$timeout" ]; do
    [ -S "$sock" ] && return 0
    sleep 1
    i=$((i + 1))
  done
  return 1
}

users_ensure_instance_ids() {
  users_state_exists || return 1
  users_py_locked '
import hashlib,json,os
path=os.environ["MITA_USERS_STATE"]
d=json.load(open(path))
used=set()
for index,u in enumerate(d.get("users") or []):
    current=str(u.get("instance_id") or "")
    if current.startswith("u") and len(current)==17 \
       and all(c in "0123456789abcdef" for c in current[1:]) and current not in used:
        used.add(current)
        continue
    material="%s\0%s\0%s\0%s" % (
        u.get("name") or "", u.get("created_at") or 0, u.get("port") or 0, index
    )
    salt=0
    while True:
        candidate="u"+hashlib.sha256((material+"\0"+str(salt)).encode()).hexdigest()[:16]
        if candidate not in used:
            break
        salt += 1
    u["instance_id"]=candidate
    used.add(candidate)
d["version"]=max(2,int(d.get("version") or 1))
json.dump(d,open(path,"w"),indent=2)
'
}

install_instance_runtime() {
  local sm bin
  sm="$(service_manager)"
  bin="$(mita_real_bin)"
  if [ "${DRY_RUN:-0}" -eq 1 ]; then
    msg "[dry-run] install isolated mita instance runtime ($sm)"
    return 0
  fi
  [ "$sm" != "none" ] || {
    warn "$(t '专属实例模式需要 systemd 或 OpenRC' \
      'Dedicated-instance mode requires systemd or OpenRC')"
    return 1
  }
  run mkdir -p "$MITA_INSTANCES_DIR" "$MITA_INSTANCE_RUN_DIR" \
    "$MITA_INSTANCE_METRICS_DIR" /usr/local/libexec /var/lib/mita || return 1
  # 配置子目录/文件属于 mita，但父目录必须至少允许 mita 组穿越。
  run chown root:mita "$MITA_INSTANCES_DIR" || return 1
  run chown mita:mita "$MITA_INSTANCE_RUN_DIR" "$MITA_INSTANCE_METRICS_DIR" /var/lib/mita \
    || return 1
  run chmod 0750 "$MITA_INSTANCES_DIR" "$MITA_INSTANCE_RUN_DIR" "$MITA_INSTANCE_METRICS_DIR" \
    || return 1

  case "$sm" in
    systemd)
      run mkdir -p "$(dirname "$MITA_INSTANCE_TMPFILES")" || return 1
      cat >"$MITA_INSTANCE_TMPFILES" <<EOF
d ${MITA_INSTANCE_RUN_DIR} 0750 mita mita -
EOF
      run chmod 0644 "$MITA_INSTANCE_TMPFILES" || return 1
      if command -v systemd-tmpfiles >/dev/null 2>&1; then
        run systemd-tmpfiles --create "$MITA_INSTANCE_TMPFILES" || return 1
      fi
      cat >"$MITA_INSTANCE_SYSTEMD_TEMPLATE" <<EOF
[Unit]
Description=Mieru dedicated user instance %i
After=network-online.target
Wants=network-online.target

[Service]
Type=exec
User=mita
Group=mita
Environment=MITA_CONFIG_JSON_FILE=${MITA_INSTANCES_DIR}/%i/server.json
Environment=MITA_UDS_PATH=${MITA_INSTANCE_RUN_DIR}/%i.sock
PrivateMounts=true
BindPaths=${MITA_INSTANCE_METRICS_DIR}/%i:/var/lib/mita
ExecStart=${bin} run
Restart=on-failure
RestartSec=2
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF
      run chmod 0644 "$MITA_INSTANCE_SYSTEMD_TEMPLATE" || return 1
      run systemctl daemon-reload || return 1
      ;;
    openrc)
      if ! command -v unshare >/dev/null 2>&1 \
          || ! command -v mount >/dev/null 2>&1 \
          || ! command -v setpriv >/dev/null 2>&1; then
          warn "$(t 'OpenRC 专属实例需要 util-linux（unshare、mount、setpriv）' \
            'OpenRC dedicated instances require util-linux (unshare, mount, setpriv)')"
          return 1
      fi
      cat >"$MITA_INSTANCE_RUNNER" <<EOF
#!/bin/sh
set -eu
id="\${1:-}"
printf '%s' "\$id" | grep -Eq '^u[0-9a-f]{16}\$' || exit 64
cfg="${MITA_INSTANCES_DIR}/\$id/server.json"
sock="${MITA_INSTANCE_RUN_DIR}/\$id.sock"
metrics="${MITA_INSTANCE_METRICS_DIR}/\$id"
[ -r "\$cfg" ] && [ -d "\$metrics" ] || exit 66
exec unshare --mount --propagation private sh -c '
  set -eu
  mount --bind "\$1" /var/lib/mita
  exec setpriv --reuid=mita --regid=mita --init-groups \
    env MITA_CONFIG_JSON_FILE="\$2" MITA_UDS_PATH="\$3" "\$4" run
' sh "\$metrics" "\$cfg" "\$sock" "${bin}"
EOF
      run chmod 0755 "$MITA_INSTANCE_RUNNER" || return 1
      ;;
  esac
}

instance_ensure_openrc_service() {
  local id="$1" svc
  instance_valid_id "$id" || return 1
  [ "$(service_manager)" = "openrc" ] || return 0
  svc="${MITA_INSTANCE_OPENRC_PREFIX}${id}"
  [ "${DRY_RUN:-0}" -eq 1 ] && {
    msg "[dry-run] write OpenRC instance service $svc"
    return 0
  }
  cat >"$svc" <<EOF
#!/sbin/openrc-run

name="mita dedicated instance ${id}"
description="Mieru dedicated user instance ${id}"
command="${MITA_INSTANCE_RUNNER}"
command_args="${id}"
command_background="yes"
pidfile="/run/nobrand-mieru-${id}.pid"
output_log="/var/log/nobrand-mieru-${id}.log"
error_log="/var/log/nobrand-mieru-${id}.err"
respawn
respawn_delay=5
respawn_max=0

depend() {
  need net localmount
  after firewall
}

start_pre() {
  checkpath --directory --owner mita:mita --mode 0750 "${MITA_INSTANCE_RUN_DIR}" "${MITA_INSTANCE_METRICS_DIR}/${id}"
  checkpath --file --owner mita:mita --mode 0640 "/var/log/nobrand-mieru-${id}.log" "/var/log/nobrand-mieru-${id}.err"
}
EOF
  run chmod 0755 "$svc"
}

write_instance_config() {
  local id="$1" name="$2" port="$3" full tmp final dir
  instance_valid_id "$id" || return 1
  [ -n "$name" ] && valid_port "$port" || return 1
  full="$(write_server_config_multi)" || return 1
  tmp="$(mktemp_file .instance.json)" || { rm -f "$full"; return 1; }
  if ! _INSTANCE_PORT="$port" _INSTANCE_NAME="$name" _INSTANCE_PROTO="${PROTOCOL:-TCP}" \
      python3 - "$MITA_USERS_STATE" "$full" "$tmp" <<'PY'
import json, os, sys
state_path, full_path, out_path = sys.argv[1:4]
instance_port = int(os.environ["_INSTANCE_PORT"])
name = os.environ["_INSTANCE_NAME"]
proto = os.environ.get("_INSTANCE_PROTO", "TCP")
state = json.load(open(state_path))
full = json.load(open(full_path))
user_state = next((
    u for u in state.get("users") or []
    if u.get("enabled", True) and str(u.get("name") or "") == name
       and int(u.get("port") or 0) == instance_port
), None)
user_cfg = next((u for u in full.get("users") or [] if str(u.get("name") or "") == name), None)
if user_state is None or user_cfg is None:
    raise SystemExit(2)
bindings = [{"port": instance_port, "protocol": "TCP" if proto == "BOTH" else proto}]
if proto == "BOTH":
    bindings.append({"port": instance_port + 1, "protocol": "UDP"})
full["portBindings"] = bindings
full["users"] = [user_cfg]
json.dump(full, open(out_path, "w"), indent=2)
PY
  then
    rm -f "$full" "$tmp"
    return 1
  fi
  rm -f "$full"
  dir="${MITA_INSTANCES_DIR}/${id}"
  final="$(instance_config_path "$id")"
  if [ "${DRY_RUN:-0}" -eq 1 ]; then
    msg "[dry-run] install dedicated config $final"
    rm -f "$tmp"
    return 0
  fi
  run mkdir -p "$dir" "$(instance_metrics_dir "$id")" "$MITA_INSTANCE_RUN_DIR" \
    || { rm -f "$tmp"; return 1; }
  run chown mita:mita "$dir" "$(instance_metrics_dir "$id")" "$MITA_INSTANCE_RUN_DIR" \
    || { rm -f "$tmp"; return 1; }
  run chmod 0750 "$dir" "$(instance_metrics_dir "$id")" "$MITA_INSTANCE_RUN_DIR" \
    || { rm -f "$tmp"; return 1; }
  install -o mita -g mita -m 0600 "$tmp" "${final}.new" \
    || { rm -f "$tmp" "${final}.new"; return 1; }
  mv -f "${final}.new" "$final" \
    || { rm -f "$tmp" "${final}.new"; return 1; }
  rm -f "$tmp"
}

instance_daemon_start() {
  local id="$1" sm unit svc
  instance_valid_id "$id" || return 1
  sm="$(service_manager)"
  case "$sm" in
    systemd)
      unit="$(instance_systemd_unit "$id")"
      run systemctl enable "$unit" >/dev/null 2>&1
      run systemctl restart "$unit"
      ;;
    openrc)
      instance_ensure_openrc_service "$id"
      svc="$(instance_openrc_service "$id")"
      run rc-update add "$svc" default >/dev/null 2>&1 || true
      run rc-service "$svc" restart 2>/dev/null || run rc-service "$svc" start
      ;;
    *) return 1 ;;
  esac
  instance_wait_socket "$id" 30
}

instance_daemon_stop() {
  local id="$1" disable="${2:-0}" sm unit svc
  instance_valid_id "$id" || return 1
  instance_cmd "$id" stop >/dev/null 2>&1 || true
  sm="$(service_manager)"
  case "$sm" in
    systemd)
      unit="$(instance_systemd_unit "$id")"
      run systemctl stop "$unit" >/dev/null 2>&1 || true
      [ "$disable" -eq 1 ] && run systemctl disable "$unit" >/dev/null 2>&1 || true
      ;;
    openrc)
      svc="$(instance_openrc_service "$id")"
      run rc-service "$svc" stop >/dev/null 2>&1 || true
      if [ "$disable" -eq 1 ]; then
        run rc-update del "$svc" default >/dev/null 2>&1 || true
        run rm -f "${MITA_INSTANCE_OPENRC_PREFIX}${id}"
      fi
      ;;
  esac
  run rm -f "$(instance_socket_path "$id")" 2>/dev/null || true
}

instance_log_tail() {
  local id="$1" sm unit
  instance_valid_id "$id" || return 0
  sm="$(service_manager)"
  case "$sm" in
    systemd)
      unit="$(instance_systemd_unit "$id")"
      journalctl -u "$unit" -n 20 --no-pager 2>/dev/null >&2 || true
      ;;
    openrc)
      tail -n 20 "/var/log/nobrand-mieru-${id}.err" \
        "/var/log/nobrand-mieru-${id}.log" 2>/dev/null >&2 || true
      ;;
  esac
}

instance_start_proxy() {
  local id="$1" status_out
  if ! instance_daemon_start "$id"; then
    instance_log_tail "$id"
    return 1
  fi
  if ! instance_cmd "$id" start >/dev/null 2>&1; then
    instance_log_tail "$id"
    return 1
  fi
  sleep 1
  status_out="$(instance_cmd "$id" status 2>/dev/null || true)"
  if ! printf '%s' "$status_out" | grep -q 'status is "RUNNING"'; then
    instance_log_tail "$id"
    return 1
  fi
  mieru_instance_enforcement_valid "$id" 25 || return 1
  return 0
}

mieru_instance_enforcement_valid() {
  local id="$1" timeout="${2:-25}" row policy method address profile_id port proto bind_transport bind_port
  row="$(jq -r --arg id "$id" '.users[]|select((.instance_id // "")==$id)|[
    (.ingress_enforcement // "permissive"),(.ingress_enforcement_method // "wildcard"),
    (.ingress_local_address // ""),(.ingress_profile_id // "legacy-default-route"),(.port|tostring)]|@tsv' \
    "$MITA_USERS_STATE" 2>/dev/null || true)"
  [ -n "$row" ] || return 1
  IFS=$'\t' read -r policy method address profile_id port <<<"$row"
  proto="$(jq -r '.protocol // "TCP"' "$MITA_USERS_STATE")"
  if [ "$proto" = BOTH ]; then
    while IFS='|' read -r bind_transport bind_port; do
      nb_wait_for_enforced_listener "$policy" "$method" "$bind_transport" "$bind_port" \
        "$address" "mieru:${id}" "$timeout" || return 1
    done <<<"TCP|${port}"$'\n'"UDP|$((port + 1))"
  else
    nb_wait_for_enforced_listener "$policy" "$method" "$proto" "$port" \
      "$address" "mieru:${id}" "$timeout"
  fi
}

mieru_build_strict_firewall_candidate() {
  local output="$1" current
  current="$(mktemp_file .mieru-firewall-current)" || return 1
  nb_strict_firewall_current_or_empty "$current" || { rm -f "$current"; return 1; }
  python3 - "$current" "$MITA_USERS_STATE" "$output" <<'PY'
import json,sys
current_path,users_path,output_path=sys.argv[1:]
current=json.load(open(current_path,encoding="utf-8"))
users=json.load(open(users_path,encoding="utf-8"))
rules=[r for r in current.get("rules") or [] if not str(r.get("owner") or "").startswith("mieru:")]
proto=str(users.get("protocol") or "TCP").upper()
for user in users.get("users") or []:
    if not user.get("enabled",True) or str(user.get("ingress_enforcement") or "permissive")!="strict":
        continue
    if str(user.get("ingress_enforcement_method") or "")!="firewall":
        raise SystemExit(2)
    owner="mieru:"+str(user.get("instance_id") or "")
    address=str(user.get("ingress_local_address") or "")
    profile=str(user.get("ingress_profile_id") or "")
    port=int(user.get("port") or 0)
    bindings=[("TCP",port),("UDP",port+1)] if proto=="BOTH" else [(proto,port)]
    for transport,binding_port in bindings:
        rules.append({"owner":owner,"ingress_profile_id":profile,"transport":transport,
                      "port":binding_port,"local_address":address})
current["rules"]=sorted(rules,key=lambda r:(r["owner"],r["transport"],r["port"]))
json.dump(current,open(output_path,"w",encoding="utf-8"),indent=2)
PY
  local rc=$?
  rm -f "$current"
  [ "$rc" -eq 0 ] && nb_strict_firewall_state_valid "$output"
}

mieru_reconcile_strict_firewall() {
  local candidate
  users_state_exists || return 0
  candidate="$(mktemp_file .mieru-firewall-candidate)" || return 1
  mieru_build_strict_firewall_candidate "$candidate" \
    && nb_strict_firewall_commit_candidate "$candidate"
  local rc=$?
  rm -f "$candidate"
  return "$rc"
}

# Protocol uninstall removes every strict-ingress rule owned by Mieru before
# deleting users.json.  Filtering the authoritative owner namespace is more
# robust than enumerating the current users: it also clears a managed orphan
# left by an interrupted user transaction without touching another protocol.
mieru_clear_strict_firewall() {
  local candidate rc
  candidate="$(mktemp_file .mieru-firewall-clear)" || return 1
  nb_strict_firewall_current_or_empty "$candidate" \
    && jq '.rules |= map(select((.owner | startswith("mieru:")) | not))' \
      "$candidate" >"${candidate}.next" \
    && mv -f "${candidate}.next" "$candidate" \
    && nb_strict_firewall_commit_candidate "$candidate"
  rc=$?
  rm -f "$candidate" "${candidate}.next"
  return "$rc"
}

mieru_apply_ingress_enforcement() {
  local id="$1" profile_id candidate snapshot firewall_old firewall_existed=0 old_protocol rc=0
  users_state_exists || return 1
  profile_id="$(jq -r --arg id "$id" '.users[]|select((.instance_id // "")==$id)|.ingress_profile_id // empty' \
    "$MITA_USERS_STATE")"
  [ -n "$profile_id" ] || profile_id="$NOBRAND_LEGACY_INGRESS_PROFILE_ID"
  nb_prepare_ingress_deployment "$profile_id" firewall || return 1
  candidate="$(mktemp_file .mieru-ingress-users)" || return 1
  snapshot="$(mktemp_dir)" || { rm -f "$candidate"; return 1; }
  firewall_old="$snapshot/firewall.json"
  cp -a "$MITA_USERS_STATE" "$snapshot/users.json" || rc=1
  [ ! -e "$NOBRAND_INGRESS_FIREWALL_STATE_FILE" ] || firewall_existed=1
  [ "$rc" -ne 0 ] || nb_strict_firewall_current_or_empty "$firewall_old" || rc=1
  if [ "$rc" -eq 0 ]; then
    jq --arg id "$id" --arg policy "$INGRESS_ENFORCEMENT_RESOLVED" \
      --arg method "$INGRESS_ENFORCEMENT_METHOD" --arg address "$INGRESS_LOCAL_ADDRESS" '
        (.users[]|select((.instance_id // "")==$id)) |=
          (.ingress_enforcement=$policy|.ingress_enforcement_method=$method|.ingress_local_address=$address)
      ' "$MITA_USERS_STATE" >"$candidate" || rc=1
  fi
  old_protocol="${PROTOCOL:-TCP}"
  [ "$rc" -ne 0 ] || PROTOCOL="$(jq -r '.protocol // "TCP"' "$candidate")"
  if [ "$rc" -eq 0 ]; then
    nb_atomic_install_file "$candidate" "$MITA_USERS_STATE" 0600 \
      && [ "${NOBRAND_TEST_INGRESS_SERVICE_FAIL:-0}" -eq 0 ] \
      && reconcile_isolated_instances \
      && [ "${NOBRAND_TEST_INGRESS_LISTENER_FAIL:-0}" -eq 0 ] || rc=1
  fi
  if [ "$rc" -ne 0 ]; then
    nb_atomic_install_file "$snapshot/users.json" "$MITA_USERS_STATE" 0600 >/dev/null 2>&1 || true
    PROTOCOL="$(jq -r '.protocol // "TCP"' "$MITA_USERS_STATE" 2>/dev/null || printf '%s' "$old_protocol")"
    reconcile_isolated_instances >/dev/null 2>&1 || true
    nb_strict_firewall_commit_candidate "$firewall_old" >/dev/null 2>&1 || true
    [ "$firewall_existed" -eq 1 ] || rm -f "$NOBRAND_INGRESS_FIREWALL_STATE_FILE"
  fi
  PROTOCOL="$old_protocol"
  rm -f "$candidate"
  rm -rf -- "$snapshot"
  return "$rc"
}

isolated_stop_all() {
  local id
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    instance_daemon_stop "$id" 1 || true
  done < <(
    {
      users_all_instance_ids 2>/dev/null || true
      for id in "$MITA_INSTANCES_DIR"/*; do
        [ -d "$id" ] || continue
        basename "$id"
      done
    } | grep -E '^u[0-9a-f]{16}$' | LC_ALL=C sort -u || true
  )
}

prune_orphan_instances() {
  local id path all_ids candidates=""
  all_ids="$(users_all_instance_ids 2>/dev/null || true)"
  for path in "$MITA_INSTANCES_DIR"/* "$MITA_INSTANCE_METRICS_DIR"/*; do
    [ -d "$path" ] || continue
    id="$(basename "$path")"
    instance_valid_id "$id" || continue
    candidates="${candidates}${id}"$'\n'
  done
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    grep -qxF "$id" <<<"$all_ids" && continue
    instance_daemon_stop "$id" 1 || true
    nb_strict_firewall_remove_owner "mieru:${id}" || true
    run rm -rf "${MITA_INSTANCES_DIR:?}/${id}" "${MITA_INSTANCE_METRICS_DIR:?}/${id}"
  done < <(printf '%s' "$candidates" | sed '/^[[:space:]]*$/d' | LC_ALL=C sort -u)
}

reconcile_isolated_instances() {
  local id name port desired_ids="" existing_ids="" status_out
  users_require_python || return 1
  users_ensure_instance_ids || return 1
  install_instance_runtime || return 1
  mieru_reconcile_strict_firewall || return 1

  while IFS=$'\t' read -r id name port; do
    [ -n "$id" ] && [ -n "$name" ] && [ -n "$port" ] || continue
    write_instance_config "$id" "$name" "$port" || return 1
    instance_ensure_openrc_service "$id" || return 1
    desired_ids="${desired_ids}${id}"$'\n'
  done < <(users_enabled_instance_rows)
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    existing_ids="${existing_ids}${id}"$'\n'
  done < <(
    for id in "$MITA_INSTANCES_DIR"/*; do
      [ -d "$id" ] || continue
      basename "$id"
    done | grep -E '^u[0-9a-f]{16}$' || true
  )

  while IFS= read -r id; do
    [ -n "$id" ] || continue
    if ! instance_start_proxy "$id"; then
      warn "$(t "专属实例 ${id} 启动或验收失败" \
        "Dedicated instance ${id} failed to start or verify")"
      return 1
    fi
  done <<<"$desired_ids"

  while IFS= read -r id; do
    [ -n "$id" ] || continue
    if ! grep -qxF "$id" <<<"$desired_ids"; then
      instance_daemon_stop "$id" 1 || return 1
    fi
  done <<<"$existing_ids"

  while IFS= read -r id; do
    [ -n "$id" ] || continue
    status_out="$(instance_cmd "$id" status 2>/dev/null || true)"
    printf '%s' "$status_out" | grep -q 'status is "RUNNING"' || return 1
  done <<<"$desired_ids"
  return 0
}

ensure_isolated_deployment() {
  users_isolated_mode || {
    warn "$(t 'schema v3 Mieru 用户状态缺少 isolated-v2 标记，拒绝转换' \
      'Schema-v3 Mieru user state lacks the isolated-v2 marker; refusing conversion')"
    return 1
  }
  reconcile_isolated_instances
}
