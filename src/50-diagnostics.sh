doctor_check_tc_limits() {
  local dev rate_users
  rate_users="$(users_rate_limited_count)"
  if [ "${rate_users:-0}" -eq 0 ]; then
    check "rate-limit rules" 1 "$(t '未配置用户限速，clsact/filter 无需创建' \
      'No users have rate limits; clsact/filter rules are not required')"
  elif ! command -v tc >/dev/null 2>&1; then
    check "tc binary" 0 "$(t "${rate_users} 个限速用户，但 tc 未安装" \
      "${rate_users} rate-limited user(s), but tc is not installed")"
  else
    dev="$(tc_default_iface 2>/dev/null || true)"
    if [ -z "$dev" ]; then
      check "nic detect" 0 "$(t "${rate_users} 个限速用户，但未检测到网卡；可设置 TC_IFACE" \
        "${rate_users} rate-limited user(s), but no interface was detected; set TC_IFACE")"
    else
      check "nic" 1 "$dev"
      if tc qdisc show dev "$dev" 2>/dev/null | grep -qw clsact; then
        check "clsact" 1
      else
        check "clsact" 0 "$(t "${rate_users} 个限速用户，但 clsact 缺失" \
          "${rate_users} rate-limited user(s), but clsact is missing")"
      fi
      if [ -s "$TC_OWNED_STATE" ]; then
        check "owned filter manifest" 1 "$TC_OWNED_STATE"
      else
        check "owned filter manifest" 0 "$(t "${rate_users} 个限速用户，但规则清单缺失" \
          "${rate_users} rate-limited user(s), but the owned-filter manifest is missing")"
      fi
    fi
  fi
}

do_doctor() {
  require_root 2>/dev/null || true
  local pass=0 fail=0 warn_n=0
  check() {
    local name="$1" ok="$2" detail="${3:-}"
    if [ "$ok" = "1" ]; then
      msg "  [PASS] $name${detail:+ — $detail}"
      pass=$((pass + 1))
    elif [ "$ok" = "2" ]; then
      msg "  [WARN] $name${detail:+ — $detail}"
      warn_n=$((warn_n + 1))
    else
      msg "  [FAIL] $name${detail:+ — $detail}"
      fail=$((fail + 1))
    fi
  }
  print_banner
  t '========== 一键验收 doctor ==========' '========== doctor / verify =========='
  msg ""

  t '【环境】' '[Environment]'
  check "root" "$([ "$(id -u 2>/dev/null || echo 1)" -eq 0 ] && echo 1 || echo 0)"
  check "python3" "$(command -v python3 >/dev/null 2>&1 && echo 1 || echo 0)"
  check "tc (iproute2)" "$(command -v tc >/dev/null 2>&1 && echo 1 || echo 2)" "专属端口限速"
  check "flock" "$(command -v flock >/dev/null 2>&1 && echo 1 || echo 2)" "并发锁"

  t '【mita】' '[mita]'
  load_install_state 2>/dev/null || true
  if mita_installed; then
    check "mita installed" 1 "$(installed_version 2>/dev/null || echo ok)"
    local bin st iid iname iport cfg_ok
    bin="$(mita_bin)"
    if users_isolated_mode; then
      check "deployment model" 1 "$MITA_DEPLOYMENT_MODEL"
      if [ "$(service_manager)" = systemd ]; then
        check "instance service template" "$([ -f "$MITA_INSTANCE_SYSTEMD_TEMPLATE" ] && echo 1 || echo 0)"
        check "instance runtime tmpfiles" "$([ -f "$MITA_INSTANCE_TMPFILES" ] && echo 1 || echo 0)"
      else
        check "instance runner" "$([ -x "$MITA_INSTANCE_RUNNER" ] && echo 1 || echo 0)"
      fi
      while IFS=$'\t' read -r iid iname iport; do
        [ -n "$iid" ] || continue
        check "instance ${iname} config" "$([ -r "$(instance_config_path "$iid")" ] && echo 1 || echo 0)" "$iid"
        check "instance ${iname} socket" "$([ -S "$(instance_socket_path "$iid")" ] && echo 1 || echo 0)" "$iid"
        st="$(instance_cmd "$iid" status 2>/dev/null || true)"
        check "instance ${iname} RUNNING" "$(printf '%s' "$st" | grep -q 'status is \"RUNNING\"' && echo 1 || echo 0)" "$iid"
        cfg_ok="$(python3 - "$(instance_config_path "$iid")" "$iname" "$iport" "${PROTOCOL:-TCP}" <<'PY' 2>/dev/null && echo 1 || echo 0
import json,sys
path,name,port,proto=sys.argv[1],sys.argv[2],int(sys.argv[3]),sys.argv[4]
d=json.load(open(path))
users=d.get("users") or []
bindings=d.get("portBindings") or []
expected={(port, "TCP" if proto=="BOTH" else proto)}
if proto=="BOTH": expected.add((port+1,"UDP"))
actual={(int(x.get("port") or 0),x.get("protocol")) for x in bindings}
raise SystemExit(0 if len(users)==1 and users[0].get("name")==name and actual==expected else 1)
PY
)"
        check "instance ${iname} isolation" "$cfg_ok" "one user / dedicated bindings"
        check "instance ${iname} metrics dir" "$([ -d "$(instance_metrics_dir "$iid")" ] && echo 1 || echo 0)" "$iid"
        if instance_cmd "$iid" get users >/dev/null 2>&1; then
          check "instance ${iname} metrics API" 1
        else
          check "instance ${iname} metrics API" 2 "get users unavailable"
        fi
      done < <(users_enabled_instance_rows)
    else
      check "deployment model" 0 "schema v3 requires isolated-v2"
    fi
  else
    check "mita installed" 0
  fi

  t '【用户状态】' '[Users state]'
  if users_state_exists; then
    check "users.json" 1 "$(users_count) users"
    local en
    en="$(python3 -c '
import json,sys
d=json.load(open(sys.argv[1]))
print(sum(1 for u in (d.get("users") or []) if u.get("enabled",True)))
' "$MITA_USERS_STATE" 2>/dev/null || echo 0)"
    check "enabled users" "$([ "${en:-0}" -ge 1 ] && echo 1 || echo 2)" \
      "$en$([ "${en:-0}" -eq 0 ] && printf ' (all disabled/expired)' || true)"
    if users_isolated_mode; then
      check "user-to-instance mapping" 1 "$en dedicated instances"
    else
      check "user-to-instance mapping" 0 "schema v3 requires isolated-v2"
    fi
    # 目录权限
    local mode
    mode="$(stat -c '%a' /etc/mita 2>/dev/null || stat -f '%OLp' /etc/mita 2>/dev/null || echo '?')"
    if [ "$mode" = "750" ] || [ "$mode" = "0750" ] || [ "$mode" = "770" ] || [ "$mode" = "0770" ] || [ "$mode" = "700" ] || [ "$mode" = "0700" ]; then
      check "/etc/mita mode" 1 "$mode"
    else
      check "/etc/mita mode" 2 "$mode (建议 mita:mita 750)"
    fi
  else
    check "users.json" 0 "schema v3 Mieru user state missing"
  fi

  t '【防火墙所有权】' '[Firewall ownership]'
  if [ -f "$MITA_FIREWALL_OWNED_STATE" ]; then
    check "owned firewall manifest" 1 "$MITA_FIREWALL_OWNED_STATE"
  else
    check "owned firewall manifest" 2 "未新增本地规则或沿用预先存在的规则"
  fi

  t '【专属实例 tc 限速】' '[Dedicated-instance tc limits]'
  doctor_check_tc_limits

  t '【定时任务】' '[Scheduler]'
  if [ -f "$MITA_USERS_TIMER" ] || systemctl is-enabled nobrand-mieru-users-scan.timer >/dev/null 2>&1; then
    check "systemd timer" 1
  elif [ -f "$MITA_USERS_CRON" ]; then
    check "cron.d" 1 "$MITA_USERS_CRON"
  else
    check "scheduler" 2 "未安装 timer/cron"
  fi
  if [ -f "$MITA_LOGROTATE_CONF" ]; then
    check "logrotate" 1
  else
    check "logrotate" 2 "可选"
  fi

  msg ""
  t "结果: PASS=$pass WARN=$warn_n FAIL=$fail" "Result: PASS=$pass WARN=$warn_n FAIL=$fail"
  if [ "$fail" -gt 0 ]; then
    t '存在失败项，请根据上方提示排查' 'Failures above need attention'
    return 1
  fi
  if [ "$warn_n" -gt 0 ]; then
    t '验收通过（警告可忽略或稍后处理）' 'Verify OK (warnings optional)'
  else
    t '验收通过' 'Verify OK'
  fi
  return 0
}

detect_public_ip_family() {
  local family="${1:-4}" candidate="" curl_flag=-4
  [ "$family" = 6 ] && curl_flag=-6
  candidate="$(curl "$curl_flag" -fsSL --connect-timeout 4 --max-time 8 \
    https://api.ip.sb/ip 2>/dev/null | head -n1 | tr -d '[:space:]' || true)"
  valid_public_ip_literal "$candidate" || return 1
  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import ipaddress,sys; raise SystemExit(0 if ipaddress.ip_address(sys.argv[1]).version==int(sys.argv[2]) else 1)' \
      "$candidate" "$family" 2>/dev/null || return 1
  elif { [ "$family" = 4 ] && [[ "$candidate" == *:* ]]; } \
       || { [ "$family" = 6 ] && [[ "$candidate" != *:* ]]; }; then
    return 1
  fi
  printf '%s' "$candidate"
}

perf_sysctl_value() {
  local key="$1" path="/proc/sys/${1//./\/}"
  if command -v sysctl >/dev/null 2>&1; then
    sysctl -n "$key" 2>/dev/null || true
  elif [ -r "$path" ]; then
    head -n1 "$path" 2>/dev/null || true
  fi
}

do_perf() {
  # 严格只读：本函数不得调用 run/save/apply/reconcile/ensure/start/enable 等写路径。
  local iface="" iface_mtu="" public4="" public6="" cc="" default_qdisc="" qdisc_live=""
  local cpu_cores="" load_now="" memory="" instance_count=0 process_rows="" rate_users=0 tc_state="inactive"
  local bbr_state="disabled" fq_state="disabled" installed="unknown" advertised="auto"
  load_install_state 2>/dev/null || true
  if users_state_exists && [ "$(users_count 2>/dev/null || echo 0)" -gt 0 ]; then
    users_sync_primary_globals
  fi
  profile_reconcile_metadata
  installed="$(installed_version 2>/dev/null || printf unknown)"
  iface="$(tc_default_iface 2>/dev/null || true)"
  [ -z "$iface" ] || iface_mtu="$(mtu_iface_value "$iface" 2>/dev/null || true)"
  public4="$(detect_public_ip_family 4 2>/dev/null || true)"
  public6="$(detect_public_ip_family 6 2>/dev/null || true)"
  cc="$(perf_sysctl_value net.ipv4.tcp_congestion_control)"
  default_qdisc="$(perf_sysctl_value net.core.default_qdisc)"
  [ -z "$iface" ] || qdisc_live="$(tc qdisc show dev "$iface" 2>/dev/null || true)"
  [ "$cc" != bbr ] || bbr_state=enabled
  if [ "$default_qdisc" = fq ] || printf '%s' "$qdisc_live" | grep -qw fq; then
    fq_state=enabled
  fi
  cpu_cores="$(getconf _NPROCESSORS_ONLN 2>/dev/null || true)"
  if [ -z "$cpu_cores" ] && command -v nproc >/dev/null 2>&1; then
    cpu_cores="$(nproc 2>/dev/null || true)"
  fi
  [ -n "$cpu_cores" ] || cpu_cores=unknown
  load_now="$(awk '{print $1" "$2" "$3}' /proc/loadavg 2>/dev/null || printf unknown)"
  memory="$(awk '/^MemTotal:/{t=$2}/^MemAvailable:/{a=$2}END{if(t)printf "%.0f MiB total / %.0f MiB available",t/1024,a/1024}' /proc/meminfo 2>/dev/null || true)"
  [ -n "$memory" ] || memory=unknown
  if users_state_exists; then
    instance_count="$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(sum(1 for u in d.get("users",[]) if u.get("enabled",True)))' \
      "$MITA_USERS_STATE" 2>/dev/null || echo 0)"
    rate_users="$(users_rate_limited_count 2>/dev/null || echo 0)"
  elif mita_installed; then
    instance_count=1
  fi
  if command -v ps >/dev/null 2>&1; then
    process_rows="$(ps -eo pid=,pcpu=,rss=,comm=,args= 2>/dev/null \
      | awk '$4=="mita" {printf "    PID %-7s CPU %-6s RSS %.1f MiB  %s\n",$1,$2,$3/1024,$4}' \
      | head -n 20 || true)"
  fi
  if [ -s "$TC_OWNED_STATE" ]; then
    tc_state="owned filters recorded"
  elif [ -n "$qdisc_live" ]; then
    tc_state="no OneClick-owned rate filters"
  fi
  if [ -n "${ADVERTISE_HOST:-}" ]; then
    advertised="$(url_host "$ADVERTISE_HOST"):${ADVERTISE_PORT}"
  elif [ -n "$public4" ]; then
    advertised="${public4}:${PORT:-unknown} (auto)"
  elif [ -n "$public6" ]; then
    advertised="[$public6]:${PORT:-unknown} (auto)"
  fi

  msg '========== Mieru Performance ========='
  msg ''
  t 'Profile' 'Profile'
  t "  $(profile_label)" "  $(profile_label)"
  msg ''
  t 'Mieru' 'Mieru'
  t "  Version: ${installed}" "  Version: ${installed}"
  t "  Transport: ${PROTOCOL:-unknown}" "  Transport: ${PROTOCOL:-unknown}"
  t "  MTU: ${MTU:-unknown}" "  MTU: ${MTU:-unknown}"
  t "  Multiplexing: ${MULTIPLEXING:-unknown}" "  Multiplexing: ${MULTIPLEXING:-unknown}"
  t "  Handshake: ${HANDSHAKE_MODE:-unknown}" "  Handshake: ${HANDSHAKE_MODE:-unknown}"
  t "  Traffic Pattern: $(traffic_label)" "  Traffic Pattern: $(traffic_label)"
  t "  Low Entropy: $(low_entropy_label)" "  Low Entropy: $(low_entropy_label)"
  msg ''
  t 'Kernel' 'Kernel'
  t "  TCP congestion control: ${cc:-unknown}" "  TCP congestion control: ${cc:-unknown}"
  t "  Default qdisc: ${default_qdisc:-unknown}" "  Default qdisc: ${default_qdisc:-unknown}"
  t "  BBR status: ${bbr_state}" "  BBR status: ${bbr_state}"
  t "  fq status: ${fq_state}" "  fq status: ${fq_state}"
  msg ''
  t 'Network' 'Network'
  t "  Default interface: ${iface:-unknown}" "  Default interface: ${iface:-unknown}"
  t "  Interface MTU: ${iface_mtu:-unknown}" "  Interface MTU: ${iface_mtu:-unknown}"
  t "  Detected public IPv4: ${public4:-unavailable}" "  Detected public IPv4: ${public4:-unavailable}"
  t "  Detected public IPv6: ${public6:-unavailable}" "  Detected public IPv6: ${public6:-unavailable}"
  msg ''
  t 'Endpoint' 'Endpoint'
  t "  Backend listen address: all interfaces" "  Backend listen address: all interfaces"
  t "  Backend listen port: ${PORT:-unknown}" "  Backend listen port: ${PORT:-unknown}"
  t "  Advertised client address: ${ADVERTISE_HOST:-auto}" "  Advertised client address: ${ADVERTISE_HOST:-auto}"
  t "  Advertised client port: ${ADVERTISE_PORT:-${PORT:-unknown}}" "  Advertised client port: ${ADVERTISE_PORT:-${PORT:-unknown}}"
  if client_endpoint_is_independent "$public4" "$public6"; then
    local backend_endpoint="${public4:-${public6:-<undetected>}}"
    t '  [INFO] 当前使用独立客户端入口' \
      '  [INFO] An independent client endpoint is in use'
    t "    Client: ${advertised}" "    Client: ${advertised}"
    t "    Backend: $(url_host "$backend_endpoint"):${PORT:-unknown}" \
      "    Backend: $(url_host "$backend_endpoint"):${PORT:-unknown}"
  fi
  msg ''
  t 'Resource' 'Resource'
  t "  CPU cores: ${cpu_cores}" "  CPU cores: ${cpu_cores}"
  t "  Current load: ${load_now}" "  Current load: ${load_now}"
  t "  Memory: ${memory}" "  Memory: ${memory}"
  t "  Number of mita instances: ${instance_count}" "  Number of mita instances: ${instance_count}"
  if [ -n "$process_rows" ]; then
    t '  Relevant processes:' '  Relevant processes:'
    msg "$process_rows"
  else
    t '  Relevant processes: none detected' '  Relevant processes: none detected'
  fi
  msg ''
  t 'Traffic Control' 'Traffic Control'
  t '  Global bandwidth limit: not configured by OneClick' \
    '  Global bandwidth limit: not configured by OneClick'
  t "  Per-user bandwidth limits: ${rate_users}" "  Per-user bandwidth limits: ${rate_users}"
  t "  tc status: ${tc_state}" "  tc status: ${tc_state}"
  msg ''
  t 'Warnings' 'Warnings'
  local warning_count=0
  if [ "$(normalize_traffic_pattern "${TRAFFIC_PATTERN:-off}" 2>/dev/null || printf off)" != off ]; then
    warn "$(t 'Traffic Pattern 已开启；性能基准测试时建议关闭后进行 A/B 对比。' \
      'Traffic Pattern is enabled; benchmark with it off for an A/B comparison.')"
    warning_count=$((warning_count + 1))
  fi
  if [ "$(normalize_low_entropy_mode "${LOW_ENTROPY_MODE:-LOW_ENTROPY_MODE_OFF}" 2>/dev/null || true)" != LOW_ENTROPY_MODE_OFF ]; then
    warn "$(t 'Low Entropy 已开启，会增加额外流量。' 'Low Entropy is enabled and adds traffic overhead.')"
    warning_count=$((warning_count + 1))
  fi
  case "${MULTIPLEXING:-MULTIPLEXING_OFF}" in
    MULTIPLEXING_MIDDLE|MULTIPLEXING_HIGH)
      warn "$(t 'Multiplexing MIDDLE/HIGH 可能不适合纯大文件吞吐测试。' \
        'Multiplexing MIDDLE/HIGH may not suit bulk-file throughput tests.')"
      warning_count=$((warning_count + 1))
      ;;
  esac
  if [ "${rate_users:-0}" -gt 0 ] || [ -s "$TC_OWNED_STATE" ]; then
    warn "$(t 'tc 当前存在 OneClick 管理的限速。' 'OneClick-managed tc rate limits are active.')"
    warning_count=$((warning_count + 1))
  fi
  if [[ "${iface_mtu:-}" =~ ^[0-9]+$ ]] && [[ "${MTU:-}" =~ ^[0-9]+$ ]] \
     && { [ "$MTU" -gt "$iface_mtu" ] \
       || { [ "${PROTOCOL:-TCP}" != TCP ] && [ $((MTU + 48)) -gt "$iface_mtu" ]; }; }; then
    warn "$(t '网卡 MTU 与 Mieru MTU/传输开销组合可能存在分片风险。' \
      'Interface MTU versus Mieru MTU/transport overhead may cause fragmentation.')"
    warning_count=$((warning_count + 1))
  fi
  if [ "$bbr_state" != enabled ]; then
    warn "$(t 'BBR 未启用。' 'BBR is not enabled.')"
    warning_count=$((warning_count + 1))
  fi
  if [ "$fq_state" != enabled ]; then
    warn "$(t 'fq 未启用。' 'fq is not enabled.')"
    warning_count=$((warning_count + 1))
  fi
  [ "$warning_count" -gt 0 ] || t '  未发现明显性能限制。' '  No obvious performance limits detected.'
  t '  本报告为只读；未修改任何系统或 Mieru 配置。' \
    '  This report is read-only; no system or Mieru configuration was changed.'
}
