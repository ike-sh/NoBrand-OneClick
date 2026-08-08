mita_socket_paths() {
  printf '%s\n' /var/run/mita/mita.sock /run/mita/mita.sock /var/run/mita.sock
}

mita_log_tail() {
  local f
  for f in /var/log/mita.err /var/log/mita.log; do
    if [ -s "$f" ]; then
      warn "$(t "mita 日志 (${f}):" "mita log (${f}):")"
      tail -n 8 "$f" 2>/dev/null | while IFS= read -r line; do
        msg "  $line"
      done
    fi
  done
}

wait_mita_socket() {
  local timeout="${1:-45}" i=0 sock
  while [ "$i" -lt "$timeout" ]; do
    while IFS= read -r sock; do
      [ -S "$sock" ] 2>/dev/null && return 0
    done < <(mita_socket_paths)
    sleep 1
    i=$((i + 1))
  done
  return 1
}

ensure_mita_daemon() {
  if [ "${DRY_RUN:-0}" -eq 1 ]; then
    msg "[dry-run] ensure mita management daemon"
    return 0
  fi
  local sm
  sm="$(service_manager)"
  case "$sm" in
    systemd)
      run systemctl enable mita 2>/dev/null || true
      run systemctl start mita 2>/dev/null || run systemctl restart mita 2>/dev/null || true
      ;;
    openrc)
      run rc-update add mita default 2>/dev/null || true
      openrc_mita_recover
      if ! openrc_mita_is_started; then
        mita_log_tail
      fi
      ;;
    *)
      run "$(mita_bin)" run >/dev/null 2>&1 &
      ;;
  esac
}

apply_config() {
  local cfg="$1"
  STAGE="应用配置"
  local bin err_file i=0
  if [ "${DRY_RUN:-0}" -eq 1 ]; then
    msg "[dry-run] mita apply config $cfg"
    rm -f "$cfg" 2>/dev/null || true
    return 0
  fi
  bin="$(mita_bin)"
  err_file="$(mktemp_file .log)"
  ensure_mita_daemon
  if ! wait_mita_socket 45; then
    warn "$(t 'mita 管理进程未就绪，正在重试 apply config...' \
      'mita management daemon not ready, retrying apply config...')"
    mita_log_tail
  fi
  while [ "$i" -lt 5 ]; do
    : >"$err_file"
    if "$bin" apply config "$cfg" 2>"$err_file"; then
      rm -f "$cfg" "$err_file"
      return 0
    fi
    i=$((i + 1))
    ensure_mita_daemon
    wait_mita_socket 10 || true
    sleep 2
  done
  if [ -s "$err_file" ]; then
    warn "$(t 'mita apply 最后一次错误:' 'Last mita apply error:')"
    tail -n 8 "$err_file" >&2 || true
  fi
  rm -f "$cfg" "$err_file"
  warn "$(t '应用配置失败；原配置未被脚本降级或删改' \
    'Failed to apply config; the script did not downgrade or remove any fields')"
  return 1
}

collect_ports_from_mita() {
  local saved_protocol="" saved_port="" saved_port_range=""
  if [ -f "$MITA_STATE" ]; then
    state_file_is_secure "$MITA_STATE" || return 1
    # shellcheck disable=SC1090
    source "$MITA_STATE" 2>/dev/null || true
    saved_protocol="$PROTOCOL"
    saved_port="$PORT"
    saved_port_range="$PORT_RANGE"
  else
    PORT=""
    PORT_RANGE=""
    PROTOCOL="TCP"
  fi

  local desc bin
  bin="$(mita_bin)"
  desc="$("$bin" describe config 2>/dev/null || true)"
  if [ -z "$desc" ]; then
    if [ -n "$saved_protocol" ]; then
      PROTOCOL="$saved_protocol"
      PORT="$saved_port"
      PORT_RANGE="$saved_port_range"
    fi
    return 0
  fi

  PORT="$(printf '%s' "$desc" | sed -n 's/.*"port"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p' | head -n1)"
  PORT_RANGE="$(printf '%s' "$desc" | sed -n 's/.*"portRange"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
  local tcp_count udp_count
  tcp_count="$(printf '%s' "$desc" | grep -c '"protocol"[[:space:]]*:[[:space:]]*"TCP"' || true)"
  udp_count="$(printf '%s' "$desc" | grep -c '"protocol"[[:space:]]*:[[:space:]]*"UDP"' || true)"
  if [ -n "$saved_protocol" ]; then
    PROTOCOL="$saved_protocol"
  elif [ "$tcp_count" -gt 0 ] && [ "$udp_count" -gt 0 ]; then
    PROTOCOL="BOTH"
  elif [ "$udp_count" -gt 0 ]; then
    PROTOCOL="UDP"
  else
    PROTOCOL="TCP"
  fi
}

# 从 mita describe config 输出解析 MTU；优先 JSON，旧环境无 python3 时用单字段回退。
extract_mtu_from_describe() {
  local desc="$1" value=""
  [ -n "$desc" ] || return 1
  if command -v python3 >/dev/null 2>&1; then
    value="$(printf '%s' "$desc" | python3 -c '
import json, sys
try:
    value = json.load(sys.stdin).get("mtu")
except Exception:
    raise SystemExit(1)
if isinstance(value, int):
    print(value)
' 2>/dev/null || true)"
  else
    value="$(printf '%s' "$desc" \
      | sed -n 's/.*"mtu"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p' \
      | head -n1)"
  fi
  valid_mtu "$value" || return 1
  printf '%s' "$value"
}

# 从 mita describe config 输出解析 portBindings，每行 proto|port_or_range
extract_bindings_from_describe() {
  local desc="$1"
  [ -n "$desc" ] || return 0
  if command -v python3 >/dev/null 2>&1; then
    printf '%s' "$desc" | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for binding in data.get("portBindings", []):
    proto = binding.get("protocol", "TCP")
    if "port" in binding:
        print("{}|{}".format(proto, binding.get("port")))
    elif binding.get("portRange"):
        print("{}|{}".format(proto, binding.get("portRange")))
' 2>/dev/null || true
    return 0
  fi
  printf '%s\n' "$desc" | awk '
    /"protocol"[[:space:]]*:/ {
      value=$0
      sub(/^.*"protocol"[[:space:]]*:[[:space:]]*"/, "", value)
      sub(/".*$/, "", value)
      proto=value
    }
    /"portRange"[[:space:]]*:/ {
      value=$0
      sub(/^.*"portRange"[[:space:]]*:[[:space:]]*"/, "", value)
      sub(/".*$/, "", value)
      port=value
    }
    /"port"[[:space:]]*:/ {
      value=$0
      sub(/^.*"port"[[:space:]]*:[[:space:]]*/, "", value)
      sub(/[^0-9].*$/, "", value)
      port=value
    }
    /}/ {
      if (proto != "" && port != "") print proto "|" port
      proto=""; port=""
    }
  '
}

firewall_owned_has() {
  local key="$1"
  [ -f "$MITA_FIREWALL_OWNED_STATE" ] \
    && grep -qxF "$key" "$MITA_FIREWALL_OWNED_STATE" 2>/dev/null
}

firewall_owned_add() {
  local key="$1"
  firewall_owned_has "$key" && return 0
  if [ "${DRY_RUN:-0}" -eq 1 ]; then
    msg "[dry-run] own firewall rule: $key"
    return 0
  fi
  mkdir -p "$(dirname "$MITA_FIREWALL_OWNED_STATE")"
  printf '%s\n' "$key" >>"$MITA_FIREWALL_OWNED_STATE"
  chmod 0600 "$MITA_FIREWALL_OWNED_STATE" 2>/dev/null || true
}

firewall_owned_remove() {
  local key="$1" tmp
  [ -f "$MITA_FIREWALL_OWNED_STATE" ] || return 0
  if [ "${DRY_RUN:-0}" -eq 1 ]; then
    msg "[dry-run] release firewall rule: $key"
    return 0
  fi
  tmp="${MITA_FIREWALL_OWNED_STATE}.new.$$"
  grep -vxF "$key" "$MITA_FIREWALL_OWNED_STATE" >"$tmp" 2>/dev/null || true
  if [ -s "$tmp" ]; then
    chmod 0600 "$tmp" 2>/dev/null || true
    mv -f "$tmp" "$MITA_FIREWALL_OWNED_STATE"
  else
    rm -f "$tmp" "$MITA_FIREWALL_OWNED_STATE"
  fi
}

iptables_remove_owned_rule() {
  local ipt="$1" proto="$2" p="$3" key
  key="${ipt}|${proto}|${p}"
  firewall_owned_has "$key" || return 0
  command -v "$ipt" >/dev/null 2>&1 || return 1
  if "$ipt" -C INPUT -p "$proto" --dport "$p" -m comment \
      --comment "$MITA_FIREWALL_COMMENT" -j ACCEPT 2>/dev/null; then
    run "$ipt" -D INPUT -p "$proto" --dport "$p" -m comment \
      --comment "$MITA_FIREWALL_COMMENT" -j ACCEPT 2>/dev/null || return 1
  fi
  if "$ipt" -C INPUT -p "$proto" --dport "$p" -m comment \
      --comment "$MITA_FIREWALL_COMMENT" -j ACCEPT 2>/dev/null; then
    return 1
  fi
  firewall_owned_remove "$key"
}

ufw_binding_exists() {
  local spec="$1"
  ufw show added 2>/dev/null | grep -Eq \
    "^ufw[[:space:]]+allow([[:space:]]+in)?[[:space:]]+${spec//./\\.}([[:space:]]|$)"
}

firewall_apply_binding() {
  local fw="$1" action="$2" proto="$3" p="$4" spec key
  spec="$(ufw_rule_spec "$p" "$proto")"
  case "${fw}:${action}" in
    ufw:add)
      key="ufw|${proto}|${p}"
      firewall_owned_has "$key" && return 0
      ufw_binding_exists "$spec" && return 0
      if run ufw allow "$spec"; then
        firewall_owned_add "$key"
      fi
      ;;
    ufw:del)
      key="ufw|${proto}|${p}"
      firewall_owned_has "$key" || return 0
      command -v ufw >/dev/null 2>&1 || return 0
      if run ufw --force delete allow "$spec" 2>/dev/null \
         || ! ufw_binding_exists "$spec"; then
        firewall_owned_remove "$key"
      fi
      ;;
    firewalld:add)
      key="firewalld|${proto}|${p}"
      firewall_owned_has "$key" && return 0
      firewall-cmd --permanent --query-port="${p}/${proto}" >/dev/null 2>&1 && return 0
      if run firewall-cmd --permanent --add-port="${p}/${proto}"; then
        firewall_owned_add "$key"
      fi
      ;;
    firewalld:del)
      key="firewalld|${proto}|${p}"
      firewall_owned_has "$key" || return 0
      command -v firewall-cmd >/dev/null 2>&1 || return 0
      if run firewall-cmd --permanent --remove-port="${p}/${proto}" 2>/dev/null \
         || ! firewall-cmd --permanent --query-port="${p}/${proto}" >/dev/null 2>&1; then
        firewall_owned_remove "$key"
      fi
      ;;
    iptables:add|iptables:del)
      iptables_accept_port "$p" "$proto" "$action"
      ;;
  esac
}

close_firewall_for_bindings() {
  local bindings="$1"
  local pp proto p proto_lc
  [ -n "$bindings" ] || return 0

  while IFS= read -r pp; do
    [ -n "$pp" ] || continue
    proto="${pp%%|*}"
    p="${pp#*|}"
    proto_lc="$(proto_lower "$proto")"
    firewall_apply_binding ufw del "$proto_lc" "$p"
    firewall_apply_binding firewalld del "$proto_lc" "$p"
    firewall_apply_binding iptables del "$proto_lc" "$p"
  done <<< "$bindings"

  command -v firewall-cmd >/dev/null 2>&1 \
    && run firewall-cmd --reload 2>/dev/null || true
  persist_iptables_rules
}

firewall_clear_all_owned() {
  local snapshot tool proto p failed=0
  [ -f "$MITA_FIREWALL_OWNED_STATE" ] || return 0
  snapshot="$(mktemp_file .firewall-owned)" || return 1
  cp -f "$MITA_FIREWALL_OWNED_STATE" "$snapshot" || {
    rm -f "$snapshot"
    return 1
  }
  while IFS='|' read -r tool proto p; do
    [ -n "$tool" ] && [ -n "$proto" ] && [ -n "$p" ] || continue
    case "$tool" in
      ufw|firewalld)
        firewall_apply_binding "$tool" del "$proto" "$p" || failed=1
        ;;
      iptables|ip6tables)
        iptables_remove_owned_rule "$tool" "$proto" "$p" || failed=1
        ;;
      *) failed=1 ;;
    esac
  done <"$snapshot"
  rm -f "$snapshot"
  command -v firewall-cmd >/dev/null 2>&1 \
    && run firewall-cmd --reload 2>/dev/null || true
  persist_iptables_rules || failed=1
  # 只有确认规则已不存在才删除所有权记录；残留记录代表清理未完成。
  [ ! -s "$MITA_FIREWALL_OWNED_STATE" ] || failed=1
  [ "$failed" -eq 0 ]
}

ufw_rule_spec() {
  local p="$1"
  local proto="$2"
  if [[ "$p" == *-* ]]; then
    local start="${p%-*}"
    local end="${p#*-}"
    printf '%s:%s/%s' "$start" "$end" "$proto"
  else
    printf '%s/%s' "$p" "$proto"
  fi
}

iptables_accept_port() {
  local p="$1"
  local proto="$2"
  local action="${3:-add}"
  local ipt key
  for ipt in iptables ip6tables; do
    command -v "$ipt" >/dev/null 2>&1 || continue
    if [[ "$p" == *-* ]]; then
      local start end port
      start="${p%-*}"
      end="${p#*-}"
      port="$start"
      while [ "$port" -le "$end" ]; do
        key="${ipt}|${proto}|${port}"
        if [ "$action" = add ]; then
          if "$ipt" -C INPUT -p "$proto" --dport "$port" -m comment \
              --comment "$MITA_FIREWALL_COMMENT" -j ACCEPT 2>/dev/null; then
            firewall_owned_add "$key"
          elif "$ipt" -C INPUT -p "$proto" --dport "$port" -j ACCEPT 2>/dev/null; then
            :
          elif run "$ipt" -I INPUT -p "$proto" --dport "$port" -m comment \
              --comment "$MITA_FIREWALL_COMMENT" -j ACCEPT; then
            firewall_owned_add "$key"
          fi
        elif firewall_owned_has "$key"; then
          iptables_remove_owned_rule "$ipt" "$proto" "$port" || return 1
        fi
        port=$((port + 1))
      done
    else
      key="${ipt}|${proto}|${p}"
      if [ "$action" = add ]; then
        if "$ipt" -C INPUT -p "$proto" --dport "$p" -m comment \
            --comment "$MITA_FIREWALL_COMMENT" -j ACCEPT 2>/dev/null; then
          firewall_owned_add "$key"
        elif "$ipt" -C INPUT -p "$proto" --dport "$p" -j ACCEPT 2>/dev/null; then
          :
        elif run "$ipt" -I INPUT -p "$proto" --dport "$p" -m comment \
            --comment "$MITA_FIREWALL_COMMENT" -j ACCEPT; then
          firewall_owned_add "$key"
        fi
      elif firewall_owned_has "$key"; then
        iptables_remove_owned_rule "$ipt" "$proto" "$p" || return 1
      fi
    fi
  done
}

persist_iptables_rules() {
  if [ -d /etc/iptables ] || [ -f /etc/alpine-release ]; then
    if [ "${DRY_RUN:-0}" -eq 1 ]; then
      msg "[dry-run] iptables-save > /etc/iptables/rules.v4"
      return 0
    fi
    local rules_tmp
    rules_tmp="$(mktemp_file .rules.v4)" || return 1
    run mkdir -p /etc/iptables
    if iptables-save >"$rules_tmp" 2>/dev/null; then
      install -m 0600 "$rules_tmp" /etc/iptables/rules.v4 2>/dev/null || true
    fi
    rm -f "$rules_tmp"
    if command -v ip6tables-save >/dev/null 2>&1; then
      rules_tmp="$(mktemp_file .rules.v6)" || return 1
      if ip6tables-save >"$rules_tmp" 2>/dev/null; then
        install -m 0600 "$rules_tmp" /etc/iptables/rules.v6 2>/dev/null || true
      fi
      rm -f "$rules_tmp"
    fi
  fi
}

open_firewall() {
  STAGE="配置防火墙"
  local pp proto p proto_lc fw=""
  # 多用户：放行所有用户端口
  if [ "${MULTI_USER_MODE:-0}" -eq 1 ] && users_state_exists && [ "$(users_count)" -gt 0 ]; then
    open_firewall_for_pairs "$(multi_user_port_protocol_pairs)"
    return 0
  fi
  if ! pp="$(port_protocol_pairs | head -n1)" || [ -z "$pp" ]; then
    return 0
  fi

  if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q 'Status: active'; then
    fw=ufw
  elif command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
    fw=firewalld
  elif command -v iptables >/dev/null 2>&1; then
    fw=iptables
  else
    warn "$(t '未检测到本地防火墙工具，请仅在云安全组放行端口' \
      'No local firewall tool found; open ports in cloud security group')"
    return 0
  fi

  while IFS= read -r pp; do
    proto="${pp%%|*}"
    p="${pp#*|}"
    proto_lc="$(proto_lower "$proto")"
    firewall_apply_binding "$fw" add "$proto_lc" "$p"
  done < <(port_protocol_pairs)

  case "$fw" in
    firewalld) run firewall-cmd --reload || true ;;
    iptables) persist_iptables_rules ;;
  esac
}

close_firewall() {
  STAGE="清理防火墙规则"
  local desc bindings bin
  if users_state_exists && [ "$(users_count)" -gt 0 ]; then
    close_firewall_for_bindings "$(multi_user_port_protocol_pairs)"
    return 0
  fi
  bin="$(mita_bin)"
  desc="$("$bin" describe config 2>/dev/null || true)"
  bindings="$(extract_bindings_from_describe "$desc")"
  if [ -n "$bindings" ]; then
    close_firewall_for_bindings "$bindings"
    return 0
  fi
  collect_ports_from_mita
  local pp proto p proto_lc fw=""
  if ! pp="$(port_protocol_pairs | head -n1)" || [ -z "$pp" ]; then
    return 0
  fi

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
    proto="${pp%%|*}"
    p="${pp#*|}"
    proto_lc="$(proto_lower "$proto")"
    firewall_apply_binding "$fw" del "$proto_lc" "$p"
  done < <(port_protocol_pairs)

  case "$fw" in
    firewalld) run firewall-cmd --reload 2>/dev/null || true ;;
    iptables) persist_iptables_rules ;;
  esac
}

cloud_firewall_hint() {
  local specs=() pp proto p
  while IFS= read -r pp; do
    proto="${pp%%|*}"
    p="${pp#*|}"
    specs+=("${p}/${proto}")
  done < <(port_protocol_pairs)
  [ "${#specs[@]}" -gt 0 ] || return 0
  local spec
  spec="$(IFS=','; printf '%s' "${specs[*]}")"
  msg ""
  t "【云安全组提醒】请在 VPS/云控制台安全组放行: ${spec}" \
    "[Cloud SG] Allow in provider firewall: ${spec}"
}

valid_ip_literal() {
  local value="${1:-}" a b c d extra colons segment remainder
  local -a parts=()
  [ -n "$value" ] || return 1
  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import ipaddress,sys; ipaddress.ip_address(sys.argv[1])' "$value" 2>/dev/null
    return $?
  fi
  if [[ "$value" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    IFS=. read -r a b c d extra <<< "$value"
    [ -z "${extra:-}" ] || return 1
    for segment in "$a" "$b" "$c" "$d"; do
      [[ "$segment" =~ ^[0-9]{1,3}$ ]] && [ "$segment" -le 255 ] || return 1
    done
    return 0
  fi
  [[ "$value" == *:* ]] || return 1
  [[ "$value" =~ ^[0-9A-Fa-f:]+$ ]] || return 1
  [[ "$value" != *:::* ]] || return 1
  colons="${value//[^:]/}"
  [ "${#colons}" -ge 2 ] && [ "${#colons}" -le 7 ] || return 1
  if [[ "$value" == *::* ]]; then
    remainder="${value#*::}"
    [[ "$remainder" != *::* ]] || return 1
  else
    [ "${#colons}" -eq 7 ] || return 1
  fi
  IFS=: read -r -a parts <<< "$value"
  for segment in "${parts[@]}"; do
    [ "${#segment}" -le 4 ] || return 1
  done
  return 0
}

valid_domain_name() {
  local value="${1:-}" label rest
  [ -n "$value" ] && [ "${#value}" -le 253 ] || return 1
  [[ "$value" != *[[:space:]]* ]] || return 1
  [[ "$value" != *://* && "$value" != *:* && "$value" != /* ]] || return 1
  value="${value%.}"
  [ -n "$value" ] || return 1
  rest="$value"
  while true; do
    label="${rest%%.*}"
    [ -n "$label" ] && [ "${#label}" -le 63 ] || return 1
    [[ "$label" =~ ^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?$ ]] || return 1
    [ "$rest" != "$label" ] || break
    rest="${rest#*.}"
  done
}

valid_advertise_host() {
  valid_ip_literal "${1:-}" || valid_domain_name "${1:-}"
}

valid_public_ip_literal() {
  local value="${1:-}"
  valid_ip_literal "$value" || return 1
  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import ipaddress,sys; raise SystemExit(0 if ipaddress.ip_address(sys.argv[1]).is_global else 1)' \
      "$value" 2>/dev/null
    return $?
  fi
  case "$value" in
    10.*|127.*|169.254.*|192.168.*|172.1[6-9].*|172.2[0-9].*|172.3[01].*|\
    100.6[4-9].*|100.[7-9][0-9].*|100.1[01][0-9].*|100.12[0-7].*|\
    ::1|fe8*|fe9*|fea*|feb*|fc*|fd*) return 1 ;;
  esac
  return 0
}

public_ip() {
  local candidate=""
  candidate="$(curl -fsSL --connect-timeout 5 --max-time 10 https://checkip.amazonaws.com 2>/dev/null \
    | head -n1 | tr -d '[:space:]' || true)"
  if valid_public_ip_literal "$candidate"; then
    printf '%s' "$candidate"
    return 0
  fi
  candidate="$(curl -fsSL --connect-timeout 5 --max-time 10 https://api.ip.sb/ip 2>/dev/null \
    | head -n1 | tr -d '[:space:]' || true)"
  if valid_public_ip_literal "$candidate"; then
    printf '%s' "$candidate"
    return 0
  fi
  candidate="$(hostname -I 2>/dev/null | awk '{print $1}' | tr -d '[:space:]' || true)"
  valid_public_ip_literal "$candidate" || return 1
  printf '%s' "$candidate"
}

endpoint_hosts_equal() {
  local left="${1:-}" right="${2:-}"
  [ -n "$left" ] && [ -n "$right" ] || return 1
  left="${left#\[}"; left="${left%\]}"; left="${left%.}"
  right="${right#\[}"; right="${right%\]}"; right="${right%.}"
  if valid_ip_literal "$left" && valid_ip_literal "$right" \
     && command -v python3 >/dev/null 2>&1; then
    python3 -c 'import ipaddress,sys; raise SystemExit(0 if ipaddress.ip_address(sys.argv[1]) == ipaddress.ip_address(sys.argv[2]) else 1)' \
      "$left" "$right" 2>/dev/null
    return $?
  fi
  [ "$(printf '%s' "$left" | tr '[:upper:]' '[:lower:]')" = \
    "$(printf '%s' "$right" | tr '[:upper:]' '[:lower:]')" ]
}

# 成功表示客户端入口与后端不同；显式填写同一公网 IP/端口不算独立入口。
client_endpoint_is_independent() {
  local advertised_port backend_port candidate
  [ -n "${ADVERTISE_HOST:-}" ] || return 1
  advertised_port="$(normalize_uint "${ADVERTISE_PORT:-${PORT:-}}" 2>/dev/null || printf '%s' "${ADVERTISE_PORT:-${PORT:-}}")"
  backend_port="$(normalize_uint "${PORT:-}" 2>/dev/null || printf '%s' "${PORT:-}")"
  [ "$advertised_port" = "$backend_port" ] || return 0
  for candidate in "$@"; do
    [ -n "$candidate" ] || continue
    endpoint_hosts_equal "$ADVERTISE_HOST" "$candidate" && return 1
  done
  return 0
}

advertised_host() {
  if [ -n "${ADVERTISE_HOST:-}" ]; then
    printf '%s' "$ADVERTISE_HOST"
  else
    public_ip
  fi
}

advertised_port_for_protocol() {
  local proto="$1" canonical_port
  if [ -n "${ADVERTISE_PORT:-}" ]; then
    canonical_port="$(normalize_uint "$ADVERTISE_PORT")" || return 1
    if [ "${PROTOCOL:-TCP}" = "BOTH" ] && [ "$proto" = "UDP" ]; then
      printf '%s' "$((canonical_port + 1))"
    else
      printf '%s' "$canonical_port"
    fi
  else
    port_for_protocol "$proto"
  fi
}

client_protocol_label() {
  if [ "${PROTOCOL:-TCP}" = "BOTH" ]; then
    printf 'TCP(%s) + UDP(%s)' \
      "$(advertised_port_for_protocol TCP)" "$(advertised_port_for_protocol UDP)"
  else
    printf '%s' "${PROTOCOL:-TCP}"
  fi
}
