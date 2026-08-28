# ---------- 专属实例按端口限速（仅管理本脚本拥有的 tc filter） ----------

tc_available() {
  command -v tc >/dev/null 2>&1 || return 1
  tc qdisc show >/dev/null 2>&1 || return 1
  return 0
}

tc_default_iface() {
  local dev=""
  if [ -n "${TC_IFACE:-}" ]; then
    printf '%s' "$TC_IFACE"
    return 0
  fi
  if command -v ip >/dev/null 2>&1; then
    dev="$(ip route 2>/dev/null | awk '/^default/{print $5; exit}')"
    [ -n "$dev" ] || dev="$(ip -br link 2>/dev/null | awk '$1!="lo"{print $1; exit}' | cut -d@ -f1)"
  fi
  printf '%s' "$dev"
}

tc_clear_owned_filters() {
  local state="${1:-$TC_OWNED_STATE}" dev="" dir proto pref _rest
  [ -f "$state" ] || return 0
  dev="$(awk -F'|' '$1=="iface"{print $2; exit}' "$state" 2>/dev/null || true)"
  [ -n "$dev" ] || { rm -f "$state"; return 0; }
  while IFS='|' read -r dir proto pref _rest; do
    [ "$dir" = "ingress" ] || [ "$dir" = "egress" ] || continue
    [[ "$pref" =~ ^[0-9]+$ ]] || continue
    [ "$pref" -ge "$TC_PREF_MIN" ] && [ "$pref" -le "$TC_PREF_MAX" ] || continue
    case "$proto" in ip|ipv6) ;; *) continue ;; esac
    tc filter del dev "$dev" "$dir" protocol "$proto" pref "$pref" 2>/dev/null || true
  done <"$state"
  rm -f "$state"
}

tc_restore_manifest() {
  local state="$1" dev="" dir family pref l4 field port bw burst
  [ -f "$state" ] || return 0
  dev="$(awk -F'|' '$1=="iface"{print $2; exit}' "$state" 2>/dev/null || true)"
  [ -n "$dev" ] || return 1
  while IFS='|' read -r dir family pref l4 field port bw; do
    [ "$dir" = ingress ] || [ "$dir" = egress ] || continue
    [[ "$pref" =~ ^[0-9]+$ && "$port" =~ ^[0-9]+$ && "$bw" =~ ^[0-9]+$ ]] || continue
    burst=$((bw * 128))
    [ "$burst" -lt 64 ] && burst=64
    [ "$burst" -gt 4096 ] && burst=4096
    tc filter add dev "$dev" "$dir" protocol "$family" pref "$pref" flower \
      ip_proto "$l4" "$field" "$port" \
      action police rate "${bw}mbit" burst "${burst}k" conform-exceed drop \
      >/dev/null 2>&1 || return 1
  done <"$state"
}

tc_rollback_filter_update() {
  local partial="$1" previous="${2:-}"
  tc_clear_owned_filters "$partial"
  if [ -n "$previous" ] && [ -f "$previous" ]; then
    tc_restore_manifest "$previous" || true
    mv -f "$previous" "$TC_OWNED_STATE"
  fi
}

tc_add_owned_filter() {
  local state="$1" dev="$2" dir="$3" family="$4" pref="$5"
  local l4="$6" field="$7" port="$8" bw="$9" burst
  burst=$((bw * 128))
  [ "$burst" -lt 64 ] && burst=64
  [ "$burst" -gt 4096 ] && burst=4096
  if ! tc filter add dev "$dev" "$dir" protocol "$family" pref "$pref" flower \
      ip_proto "$l4" "$field" "$port" \
      action police rate "${bw}mbit" burst "${burst}k" conform-exceed drop; then
    return 1
  fi
  printf '%s|%s|%s|%s|%s|%s|%s\n' \
    "$dir" "$family" "$pref" "$l4" "$field" "$port" "$bw" >>"$state"
}

apply_tc_limits() {
  local has_limit=0 dev tmp previous="" pref="$TC_PREF_MIN" name port bw l4 p family dir field
  users_state_exists || {
    tc_clear_owned_filters
    return 0
  }
  has_limit="$(python3 -c '
import json,sys
d=json.load(open(sys.argv[1]))
print(1 if any(u.get("enabled",True) and int(u.get("bandwidth_mbps") or 0)>0 for u in (d.get("users") or [])) else 0)
' "$MITA_USERS_STATE" 2>/dev/null || echo 0)"
  if [ "$has_limit" != "1" ]; then
    tc_clear_owned_filters
    return 0
  fi
  users_isolated_mode || {
    warn "$(t '拒绝应用限速：schema v3 必须使用 isolated-v2 用户专属实例' \
      'Refusing rate limits: schema v3 requires isolated-v2 dedicated instances')"
    return 1
  }
  tc_available || {
    warn "$(t '存在限速套餐但 tc/iproute2 不可用' \
      'Rate-limited packages exist but tc/iproute2 is unavailable')"
    return 1
  }
  dev="$(tc_default_iface)"
  [ -n "$dev" ] || {
    warn "$(t '存在限速套餐但无法检测默认网卡；可设置 TC_IFACE' \
      'Rate-limited packages exist but no default NIC was found; set TC_IFACE')"
    return 1
  }
  if ! tc qdisc show dev "$dev" 2>/dev/null | grep -qw clsact; then
    if ! tc qdisc add dev "$dev" clsact 2>/dev/null; then
      warn "$(t "无法安全添加 clsact 到 ${dev}；未删除或替换现有 qdisc" \
        "Cannot safely add clsact to ${dev}; existing qdiscs were not deleted or replaced")"
      return 1
    fi
  fi
  if [ -f "$TC_OWNED_STATE" ]; then
    previous="$(mktemp_file .tc-previous)" || return 1
    cp -f "$TC_OWNED_STATE" "$previous" || { rm -f "$previous"; return 1; }
  fi
  tc_clear_owned_filters
  tmp="$(mktemp_file .tc-filters)" || return 1
  printf 'iface|%s\n' "$dev" >"$tmp"
  while IFS=$'\t' read -r name port bw; do
    [ -n "$name" ] && [ -n "$port" ] && [ "${bw:-0}" -gt 0 ] || continue
    for l4 in $( [ "${PROTOCOL:-TCP}" = "UDP" ] && echo udp || echo tcp ); do
      p="$port"
      for family in ip ipv6; do
        for dir in ingress egress; do
          [ "$dir" = ingress ] && field=dst_port || field=src_port
          [ "$pref" -le "$TC_PREF_MAX" ] || {
            warn "$(t '专属限速规则过多，超出脚本保留的 tc 优先级范围' \
              'Too many dedicated rate rules for the reserved tc preference range')"
            tc_rollback_filter_update "$tmp" "$previous"
            return 1
          }
          if ! tc_add_owned_filter "$tmp" "$dev" "$dir" "$family" "$pref" \
              "$l4" "$field" "$p" "$bw"; then
            warn "$(t "应用 ${name} 的 tc 限速失败；已撤销本次脚本规则" \
              "Failed to apply tc limit for ${name}; this run's owned filters were rolled back")"
            tc_rollback_filter_update "$tmp" "$previous"
            return 1
          fi
          pref=$((pref + 1))
        done
      done
    done
    if [ "${PROTOCOL:-TCP}" = "BOTH" ]; then
      l4=udp
      p=$((port + 1))
      for family in ip ipv6; do
        for dir in ingress egress; do
          [ "$dir" = ingress ] && field=dst_port || field=src_port
          if ! tc_add_owned_filter "$tmp" "$dev" "$dir" "$family" "$pref" \
              "$l4" "$field" "$p" "$bw"; then
            tc_rollback_filter_update "$tmp" "$previous"
            return 1
          fi
          pref=$((pref + 1))
        done
      done
    fi
  done < <(python3 -c '
import json,sys
d=json.load(open(sys.argv[1]))
for u in d.get("users") or []:
    if u.get("enabled",True) and int(u.get("bandwidth_mbps") or 0)>0:
        print("%s\t%s\t%s" % (u.get("name") or "", int(u.get("port") or 0), int(u.get("bandwidth_mbps") or 0)))
' "$MITA_USERS_STATE")
  mv -f "$tmp" "$TC_OWNED_STATE"
  chmod 0600 "$TC_OWNED_STATE" 2>/dev/null || true
  [ -z "$previous" ] || rm -f "$previous"
  users_log "tc: applied dedicated per-user port filters on $dev"
}

tc_rate_status() {
  local dev
  dev="$(tc_default_iface)"
  msg ""
  t '【带宽状态】专属实例按端口限速；仅展示/维护本脚本拥有的 filter' \
    '[Bandwidth status] dedicated-instance port limits; only script-owned filters are managed'
  if ! tc_available; then
    warn "$(t 'tc 不可用' 'tc unavailable')"
    return 1
  fi
  if [ -z "$dev" ]; then
    warn "$(t '未检测到网卡' 'No NIC detected')"
    return 1
  fi
  msg "--- qdisc ---"
  tc qdisc show dev "$dev" 2>/dev/null || true
  msg "--- egress filter ---"
  tc filter show dev "$dev" egress 2>/dev/null | grep -E 'pref 42[0-9]{3}|police' | head -n 60 || true
  msg "--- ingress filter ---"
  tc filter show dev "$dev" ingress 2>/dev/null | grep -E 'pref 42[0-9]{3}|police' | head -n 60 || true
  msg ""
  t '【套餐带宽】0 表示不限速' '[Package bandwidth] 0 means unlimited'
  if users_state_exists; then
    python3 -c '
import json,sys
d=json.load(open(sys.argv[1]))
print("%-16s %-8s %-8s %s" % ("USER","PORT","MBPS","STATUS"))
for u in d.get("users") or []:
    bw=int(u.get("bandwidth_mbps") or 0)
    st="on" if u.get("enabled",True) else "off"
    print("%-16s %-8s %-8s %s" % (u.get("name") or "", u.get("port") or "", bw if bw>0 else "unlim", st))
' "$MITA_USERS_STATE"
  fi
}

users_set_enabled() {
  local name="$1" en="$2"
  _U_ENABLED="$en"
  USER_QUOTA_MB="" USER_QUOTA_DAYS="" USER_EXPIRE="" USER_PACKAGE="" USER_BANDWIDTH_MBPS=""
  if ! users_update_fields "$name"; then
    unset _U_ENABLED
    return 1
  fi
  unset _U_ENABLED
}

# 扫描到期：expire_at <= today 且 enabled → 停用；stdout 仅输出被停用的用户名
users_scan_expired() {
  users_require_python || return 1
  users_state_exists || return 0
  local today changed tx old_pairs new_pairs close_pairs
  admin_lock_acquire || return 1
  tx="$(users_tx_snapshot)" || { admin_lock_release; return 1; }
  old_pairs="$(multi_user_port_protocol_pairs)"
  today="$(today_ymd)"
  if ! changed="$(USERS_LOG_QUIET=1 python3 -c '
import json, sys, time
path, today = sys.argv[1], sys.argv[2]
d = json.load(open(path))
changed = []
for u in d.get("users") or []:
    exp = (u.get("expire_at") or "").strip()
    if not exp:
        continue
    if not u.get("enabled", True):
        continue
    if exp <= today:
        u["enabled"] = False
        u["updated_at"] = int(time.time())
        changed.append(u.get("name") or "")
if changed:
    json.dump(d, open(path, "w"), indent=2)
print("\n".join(changed))
' "$MITA_USERS_STATE" "$today" 2>/dev/null)"; then
    users_tx_rollback "$tx" 0
    admin_lock_release
    return 1
  fi
  if [ -z "$changed" ]; then
    users_tx_commit "$tx"
    admin_lock_release
    return 0
  fi
  local n
  while IFS= read -r n; do
    [ -n "$n" ] || continue
    USERS_LOG_QUIET=1 users_log "expired disable: $n (expire_at<=$today)"
  done <<< "$changed"
  if mita_installed 2>/dev/null; then
    load_install_state
    MULTI_USER_MODE=1
    if ! apply_users_config "$tx" >/dev/null 2>&1; then
      USERS_LOG_QUIET=1 users_log "apply after expire scan failed; users state rolled back"
      admin_lock_release
      return 1
    fi
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
  printf '%s\n' "$changed"
}

# 日历月配额重置：quota_mode=calendar 且 last_quota_reset != 当月。
# isolated-v2 为每个用户提供独立 metrics.pb，因此只重置待处理用户。
_calendar_mark_pending() {
  # stdout: 待重置用户名列表；不写 last_quota_reset
  python3 -c '
import json, sys, time, datetime, calendar
path, ym = sys.argv[1], sys.argv[2]
d = json.load(open(path))
reset = []
today = datetime.date.today()
mdays = calendar.monthrange(today.year, today.month)[1]
for u in d.get("users") or []:
    if not u.get("enabled", True):
        continue
    try:
        qmb = int(u.get("quota_mb") or 0)
    except Exception:
        qmb = 0
    if qmb <= 0:
        continue
    if (u.get("quota_mode") or "rolling").strip().lower() != "calendar":
        continue
    if (u.get("last_quota_reset") or "").strip() == ym:
        continue
    u["quota_days"] = mdays
    u["updated_at"] = int(time.time())
    u["_reset_pending"] = True
    reset.append(u.get("name") or "")
if reset:
    json.dump(d, open(path, "w"), indent=2)
print("\n".join(reset))
' "$MITA_USERS_STATE" "$1" 2>/dev/null
}

_calendar_commit_reset() {
  # 成功后：仅对 _reset_pending 用户写 last_quota_reset
  local ym="$1"
  python3 -c '
import json, sys, time
path, ym = sys.argv[1], sys.argv[2]
d = json.load(open(path))
for u in d.get("users") or []:
    pending = u.pop("_reset_pending", False)
    if pending:
        u["last_quota_reset"] = ym
    u["updated_at"] = int(time.time())
json.dump(d, open(path, "w"), indent=2)
' "$MITA_USERS_STATE" "$ym" 2>/dev/null
}

users_scan_calendar_quota_reset() {
  users_require_python || return 1
  users_state_exists || return 0
  if [ "${DRY_RUN:-0}" -eq 1 ]; then
    msg "[dry-run] calendar quota scan (no users.json or metrics changes)"
    return 0
  fi
  local ym reset_list method tx
  admin_lock_acquire || return 1
  tx="$(users_tx_snapshot)" || { admin_lock_release; return 1; }
  ym="$(current_year_month)"
  method="$(printf '%s' "${QUOTA_RESET_METHOD:-metrics}" | tr '[:upper:]' '[:lower:]')"
  if ! reset_list="$(_calendar_mark_pending "$ym")"; then
    users_tx_rollback "$tx" 0
    admin_lock_release
    return 1
  fi
  if [ -z "$reset_list" ]; then
    users_tx_commit "$tx"
    admin_lock_release
    return 0
  fi
  local n
  while IFS= read -r n; do
    [ -n "$n" ] || continue
    USERS_LOG_QUIET=1 users_log "calendar quota reset pending: $n month=$ym method=$method"
  done <<< "$reset_list"

  if ! mita_installed 2>/dev/null; then
    users_tx_rollback "$tx" 0
    admin_lock_release
    warn "$(t 'mita 未安装，无法清空真实指标；未记录 calendar 重置成功' \
      'mita is not installed, so real metrics cannot be cleared; calendar reset was not marked successful')"
    return 1
  fi

  if [ "$method" != "metrics" ]; then
    users_tx_rollback "$tx" 0
    admin_lock_release
    warn "$(t "QUOTA_RESET_METHOD=${method} 已禁用：该方法不会清空按用户名累计的指标。请使用 metrics。" \
      "QUOTA_RESET_METHOD=${method} is disabled because it does not clear username-keyed metrics. Use metrics.")"
    return 1
  fi

  # isolated-v2 中每个用户拥有独立 metrics.pb，可只重置到期的 calendar 用户，
  # 不再要求所有有限配额账号在同一时间清零。
  load_install_state
  MULTI_USER_MODE=1
  if ! apply_users_config "$tx" >/dev/null 2>&1; then
    USERS_LOG_QUIET=1 users_log "calendar dedicated instance apply failed"
    admin_lock_release
    return 1
  fi
  users_isolated_mode || {
    users_tx_rollback "$tx" 1
    admin_lock_release
    warn "$(t 'calendar 重置要求 isolated-v2，但当前模型无效' \
      'Calendar reset requires isolated-v2, but the current model is invalid')"
    return 1
  }

  local backup_dir id metric reset_failed=0
  backup_dir="$(mktemp_dir)"
  chmod 0700 "$backup_dir" 2>/dev/null || true
  while IFS= read -r n; do
    [ -n "$n" ] || continue
    id="$(users_get_field "$n" instance_id 2>/dev/null || true)"
    instance_valid_id "$id" || { reset_failed=1; break; }
    metric="$(instance_metrics_file "$id")"
    if ! instance_daemon_stop "$id" 0; then
      reset_failed=1
      break
    fi
    if [ -f "$metric" ]; then
      cp -f "$metric" "${backup_dir}/${id}.pb" || { reset_failed=1; break; }
    else
      : >"${backup_dir}/${id}.absent"
    fi
    if ! rm -f "$metric" || ! instance_start_proxy "$id"; then
      reset_failed=1
      break
    fi
    USERS_LOG_QUIET=1 users_log "calendar reset cleared dedicated metrics: user=$n instance=$id"
  done <<<"$reset_list"

  if [ "$reset_failed" -eq 0 ] && _calendar_commit_reset "$ym"; then
    rm -rf "$backup_dir"
    users_tx_commit "$tx"
    admin_lock_release
    printf '%s\n' "$reset_list"
    return 0
  fi

  while IFS= read -r n; do
    [ -n "$n" ] || continue
    id="$(users_get_field "$n" instance_id 2>/dev/null || true)"
    instance_valid_id "$id" || continue
    metric="$(instance_metrics_file "$id")"
    instance_daemon_stop "$id" 0 || true
    if [ -f "${backup_dir}/${id}.pb" ]; then
      cp -f "${backup_dir}/${id}.pb" "$metric" 2>/dev/null || true
      chown mita:mita "$metric" 2>/dev/null || true
      chmod 0600 "$metric" 2>/dev/null || true
    elif [ -f "${backup_dir}/${id}.absent" ]; then
      rm -f "$metric" 2>/dev/null || true
    fi
  done <<<"$reset_list"
  rm -rf "$backup_dir"
  users_tx_rollback "$tx" 1
  USERS_LOG_QUIET=1 users_log "calendar dedicated metrics reset failed; state and metrics rolled back"
  admin_lock_release
  return 1
}

install_users_scheduler() {
  # systemd timer 优先，否则 cron.d
  [ "${DRY_RUN:-0}" -eq 1 ] && return 0
  local script_path
  script_path="${INSTALL_SCRIPT_PATH}"
  [ -x "$script_path" ] || script_path="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || printf '%s' "${BASH_SOURCE[0]}")"
  [ -n "$script_path" ] || return 0

  if command -v systemctl >/dev/null 2>&1 && [ -d /etc/systemd/system ]; then
    cat >"$MITA_USERS_SERVICE" <<EOF
[Unit]
Description=NoBrand Mieru users expire and calendar quota scan
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=${script_path} mieru user-scan
Nice=10
EOF
    cat >"$MITA_USERS_TIMER" <<EOF
[Unit]
Description=Run NoBrand Mieru users scan every 15 minutes

[Timer]
OnBootSec=2min
OnUnitActiveSec=15min
AccuracySec=1min
Unit=nobrand-mieru-users-scan.service

[Install]
WantedBy=timers.target
EOF
    systemctl daemon-reload 2>/dev/null || true
    systemctl enable --now nobrand-mieru-users-scan.timer 2>/dev/null || true
    install_logrotate_config 2>/dev/null || true
    harden_mita_permissions 2>/dev/null || true
    users_log "scheduler: systemd expiry/quota timer"
    return 0
  fi

  if [ -d /etc/cron.d ]; then
    cat >"$MITA_USERS_CRON" <<EOF
# NoBrand Mieru multi-user expire / quota scan (every 15 min)
*/15 * * * * root ${script_path} mieru user-scan >>${MITA_USERS_LOG} 2>&1
EOF
    chmod 0644 "$MITA_USERS_CRON" 2>/dev/null || true
    install_logrotate_config 2>/dev/null || true
    harden_mita_permissions 2>/dev/null || true
    users_log "scheduler: cron ${MITA_USERS_CRON}"
    return 0
  fi
  # OpenRC / 无 cron：写入 hint
  install_logrotate_config 2>/dev/null || true
  warn "$(t '未找到 systemd timer 或 /etc/cron.d，请手动定期执行: nobrand mieru user-scan' \
    'No systemd timer or /etc/cron.d; run: nobrand mieru user-scan')"
}

remove_users_scheduler() {
  if [ -f "$MITA_USERS_TIMER" ] || [ -f "$MITA_USERS_SERVICE" ]; then
    systemctl disable --now nobrand-mieru-users-scan.timer 2>/dev/null || true
    rm -f "$MITA_USERS_TIMER" "$MITA_USERS_SERVICE" 2>/dev/null || true
    systemctl daemon-reload 2>/dev/null || true
  fi
  rm -f "$MITA_USERS_CRON" 2>/dev/null || true
}
