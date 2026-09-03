random_token() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -base64 12 | tr -dc 'a-zA-Z0-9' | head -c 10
  else
    date +%s | sha256sum | head -c 10
  fi
}

random_port() {
  local p
  if command -v shuf >/dev/null 2>&1; then
    p="$(shuf -i 1025-65535 -n 1)"
  elif command -v awk >/dev/null 2>&1; then
    p="$(awk 'BEGIN{srand(); print int(1025 + rand() * (65535 - 1025 + 1))}')"
  else
    p=$((1025 + RANDOM % (65535 - 1025 + 1)))
  fi
  printf '%s' "$p"
}

random_available_port() {
  local p i
  i=0
  while [ "$i" -lt 256 ]; do
    p="$(random_port)"
    if port_available_for_mode "$p"; then
      printf '%s' "$p"
      return 0
    fi
    i=$((i + 1))
  done
  return 1
}

normalize_uint() {
  local value="${1:-}"
  [[ "$value" =~ ^[0-9]+$ ]] || return 1
  while [ "${#value}" -gt 1 ] && [ "${value#0}" != "$value" ]; do
    value="${value#0}"
  done
  printf '%s' "$value"
}

# 取本机主用 IPv4：优先默认路由出口地址（ip route get 不发包，仅查路由表，
# 内网无外网也可用），回退首个非回环地址。
detect_local_ip() {
  nb_detect_local_ipv4
}

# 由本机 IP 末位八位组推导端口基数 N*100（要求 N=1-254 且基数≥1025）；不可用返回非0
derive_port_base() {
  local ip
  ip="$(detect_local_ip)"
  nb_port_base_for_ip "$ip"
}

# 在 IP 尾号端口段内随机取一个可用端口：xx01-xx99（xx00 留给 SSH）；不可用返回非0。
# BOTH 双协议时末两位上限取 98，避免 UDP=主端口+1 溢出到 xx00 或下一机器段。
derive_port_from_ip() {
  local base hi
  base="$(derive_port_base)" || return 1
  hi=99
  [ "$PROTOCOL" = "BOTH" ] && hi=98
  nb_scan_port_span "$((base + 1))" "$((base + hi))" port_available_for_mode
}

valid_port() {
  local p
  p="$(normalize_uint "${1:-}")" || return 1
  [ "${#p}" -le 5 ] && [ "$p" -ge 1025 ] && [ "$p" -le 65535 ]
}

valid_advertise_port() {
  local p
  p="$(normalize_uint "${1:-}")" || return 1
  [ "${#p}" -le 5 ] && [ "$p" -ge 1 ] && [ "$p" -le 65535 ]
}

validate_advertise_endpoint_values() {
  local host="${1:-}" port="${2:-}" protocol="${3:-${PROTOCOL:-TCP}}"
  if [ -z "$host" ] && [ -z "$port" ]; then
    return 0
  fi
  [ -n "$host" ] && [ -n "$port" ] || {
    warn "$(t '自定义客户端入口必须同时提供地址和端口' \
      'Custom client entry requires both a host and a port')"
    return 1
  }
  if ! nb_validate_advertise_endpoint "$host" "$port" "$protocol"; then
    warn "$(t '客户端入口无效；请输入有效 IPv4、IPv6 或域名及 1-65535 端口（双协议主端口 ≤65534）' \
      'Invalid client endpoint; use a valid IPv4, IPv6, or domain and port 1-65535 (dual main port <=65534)')"
    return 1
  fi
}

validate_advertise_endpoint() {
  validate_advertise_endpoint_values "$ADVERTISE_HOST" "$ADVERTISE_PORT" "${PROTOCOL:-TCP}"
}

valid_mtu() {
  local value
  value="$(normalize_uint "${1:-}")" || return 1
  [ "${#value}" -le 4 ] && [ "$value" -ge 1280 ] && [ "$value" -le 1500 ]
}

valid_nonnegative_int32() {
  local value="${1:-}" digits
  [[ "$value" =~ ^0*([0-9]{1,10})$ ]] || return 1
  digits="${BASH_REMATCH[1]}"
  [ "$((10#$digits))" -le 2147483647 ]
}

valid_bandwidth_mbps() {
  local value="${1:-}" digits
  [[ "$value" =~ ^0*([0-9]{1,7})$ ]] || return 1
  digits="${BASH_REMATCH[1]}"
  [ "$((10#$digits))" -le 1000000 ]
}

normalize_mtu_policy() {
  case "$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')" in
    safe|default|保守|安全) printf 'safe' ;;
    auto|optimized|optimised|自动|优化) printf 'optimized' ;;
    custom|manual|自定义|手动) printf 'custom' ;;
    *) return 1 ;;
  esac
}

mtu_policy_label() {
  case "$(normalize_mtu_policy "${MTU_POLICY:-safe}" 2>/dev/null || true)" in
    optimized) t '自动优化' 'Auto optimized' ;;
    custom) t '自定义' 'Custom' ;;
    *) t '安全默认' 'Safe default' ;;
  esac
}

mtu_default_iface() {
  local dev=""
  if command -v ip >/dev/null 2>&1; then
    dev="$(ip -o route show default 2>/dev/null \
      | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')"
    [ -n "$dev" ] || dev="$(ip -o -6 route show default 2>/dev/null \
      | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')"
    [ -n "$dev" ] || dev="$(ip -br link 2>/dev/null \
      | awk '$1!="lo"{print $1; exit}' | cut -d@ -f1)"
  fi
  if [ -z "$dev" ] && [ -r /proc/net/route ]; then
    dev="$(awk '$2=="00000000"{print $1; exit}' /proc/net/route 2>/dev/null)"
  fi
  printf '%s' "$dev"
}

mtu_iface_value() {
  local dev="${1:-}" value=""
  [ -n "$dev" ] || return 1
  if [ -r "/sys/class/net/${dev}/mtu" ]; then
    value="$(tr -dc '0-9' <"/sys/class/net/${dev}/mtu" 2>/dev/null || true)"
  fi
  if ! [[ "$value" =~ ^[0-9]+$ ]] && command -v ip >/dev/null 2>&1; then
    value="$(ip -o link show dev "$dev" 2>/dev/null \
      | awk '{for(i=1;i<=NF;i++) if($i=="mtu"){print $(i+1); exit}}')"
  fi
  [[ "$value" =~ ^[0-9]+$ ]] || return 1
  printf '%s' "$value"
}

mtu_route_family() {
  local dev="${1:-}"
  if command -v ip >/dev/null 2>&1 \
     && ip route get 1.1.1.1 2>/dev/null \
       | awk -v expected="$dev" '
           { for (i=1; i<NF; i++) if ($i=="dev" && $(i+1)==expected) found=1 }
           END { exit(found ? 0 : 1) }
         '; then
    printf 'IPv4'
    return 0
  fi
  if command -v ip >/dev/null 2>&1 \
     && ip -6 route get 2606:4700:4700::1111 2>/dev/null \
       | awk -v expected="$dev" '
           { for (i=1; i<NF; i++) if ($i=="dev" && $(i+1)==expected) found=1 }
           END { exit(found ? 0 : 1) }
         '; then
    printf 'IPv6'
    return 0
  fi
  printf 'unknown'
}

# 自动策略只对 UDP 数据报大小有直接收益；TCP 由流式分片控制，保持 1400。
# mihomo 的 mieru 节点当前没有 mtu 字段，因此自动策略统一封顶 1400；
# 只有明确使用支持同步 MTU 的官方客户端时，才建议手工配置 1401-1500。
calculate_optimized_mtu() {
  local candidate
  MTU_AUTO_IFACE=""
  MTU_AUTO_LINK=""
  MTU_AUTO_FAMILY=""
  MTU_AUTO_OVERHEAD=""
  MTU_POLICY="optimized"
  if [ "${PROTOCOL:-TCP}" = "TCP" ]; then
    MTU=1400
    MTU_AUTO_FAMILY="TCP"
    return 0
  fi
  MTU_AUTO_IFACE="$(mtu_default_iface)"
  MTU_AUTO_LINK="$(mtu_iface_value "$MTU_AUTO_IFACE" 2>/dev/null || true)"
  if ! [[ "$MTU_AUTO_LINK" =~ ^[0-9]+$ ]]; then
    MTU=1400
    return 0
  fi
  MTU_AUTO_FAMILY="$(mtu_route_family "$MTU_AUTO_IFACE")"
  case "$MTU_AUTO_FAMILY" in
    IPv4) MTU_AUTO_OVERHEAD=28 ;;
    *) MTU_AUTO_OVERHEAD=48 ;;
  esac
  candidate=$((MTU_AUTO_LINK - MTU_AUTO_OVERHEAD))
  [ "$candidate" -gt 1400 ] && candidate=1400
  [ "$candidate" -lt 1280 ] && candidate=1280
  MTU="$candidate"
}

resolve_mtu_request() {
  local raw="${MTU_REQUEST:-${MTU_POLICY:-safe}}" normalized=""
  if [[ "$raw" =~ ^[0-9]+$ ]]; then
    valid_mtu "$raw" || {
      die "$(t '非法 MTU：必须为 1280-1500' 'Invalid MTU: expected 1280-1500')" || return 1
    }
    MTU="$(normalize_uint "$raw")"
    MTU_POLICY="custom"
    return 0
  fi
  normalized="$(normalize_mtu_policy "$raw" 2>/dev/null || true)"
  case "$normalized" in
    safe)
      MTU=1400
      MTU_POLICY="safe"
      ;;
    optimized)
      calculate_optimized_mtu
      ;;
    custom)
      valid_mtu "${MTU:-}" || {
        die "$(t '自定义 MTU 必须为 1280-1500' 'Custom MTU must be 1280-1500')" || return 1
      }
      MTU_POLICY="custom"
      ;;
    *)
      die "$(t '--mtu 仅支持 safe、auto 或 1280-1500' \
        '--mtu accepts only safe, auto, or a value from 1280 to 1500')" || return 1
      ;;
  esac
}

print_mtu_selection() {
  local family_label="${MTU_AUTO_FAMILY:-}"
  [ "$family_label" != unknown ] || family_label="$(t '未知协议族' 'unknown family')"
  t "已选 MTU: ${MTU}（$(mtu_policy_label)）" \
    "Selected MTU: ${MTU} ($(mtu_policy_label))"
  if [ "$MTU_POLICY" = "optimized" ]; then
    if [ "${PROTOCOL:-TCP}" = "TCP" ]; then
      t '  TCP 模式提高 MTU 没有明显收益，自动策略保持 1400' \
        '  Raising MTU has little benefit in TCP mode; auto keeps 1400'
    elif [ -n "$MTU_AUTO_LINK" ]; then
      t "  检测: 网卡 ${MTU_AUTO_IFACE}，链路 MTU ${MTU_AUTO_LINK}，${family_label} 开销 ${MTU_AUTO_OVERHEAD}" \
        "  Detected: ${MTU_AUTO_IFACE}, link MTU ${MTU_AUTO_LINK}, ${family_label} overhead ${MTU_AUTO_OVERHEAD}"
    else
      warn "$(t '未能读取出口链路 MTU，自动策略已回退到 1400' \
        'Could not read egress link MTU; auto fell back to 1400')"
    fi
  fi
  if [ "${PROTOCOL:-TCP}" = "TCP" ] && [ "$MTU" -gt 1400 ]; then
    warn "$(t 'TCP 模式使用大于 1400 的 MTU 通常没有明显收益，并可能降低复杂网络路径的兼容性' \
      'MTU above 1400 usually offers no clear benefit for TCP and may reduce path compatibility')"
  fi
  if [ "$MTU" -gt 1400 ]; then
    warn "$(t 'mihomo 的 mieru 节点当前不能单独指定 MTU；大于 1400 仅建议用于可同步相同 MTU 的官方 mieru 客户端' \
      'mihomo mieru proxies currently cannot set MTU; values above 1400 are recommended only with official mieru clients configured to the same MTU')"
  fi
}

choose_mtu_interactive() {
  local input="" def=1 custom=""
  if [ "${MTU_CLI:-0}" -eq 1 ]; then
    resolve_mtu_request || return 1
    print_mtu_selection
    return 0
  fi
  case "$(normalize_mtu_policy "${MTU_POLICY:-safe}" 2>/dev/null || true)" in
    optimized) def=2 ;;
    custom) def=3 ;;
    *) def=1 ;;
  esac
  msg ""
  t 'MTU 策略（与 multiplexing、handshake、traffic-pattern 无绑定关系）:' \
    'MTU policy (independent of multiplexing, handshake, and traffic-pattern):'
  t '  1) 安全默认 1400（推荐，跨网络兼容性最好）' \
    '  1) Safe 1400 (recommended, best path compatibility)'
  t '  2) 自动兼容（TCP 保持 1400；UDP/双协议按出口链路计算，兼容 mihomo，最大 1400）' \
    '  2) Auto compatible (TCP stays 1400; UDP/dual uses egress link MTU, mihomo-safe max 1400)'
  t '  3) 自定义 1280-1500' '  3) Custom 1280-1500'
  read_tty input "$(t "请选择 [1-3，默认 ${def}]: " "Choose [1-3, default ${def}]: ")" || input=""
  input="${input:-$def}"
  case "$input" in
    2)
      MTU_REQUEST="auto"
      resolve_mtu_request || return 1
      ;;
    3)
      while true; do
        custom=""
        read_tty custom "$(t "自定义 MTU [${MTU}]: " "Custom MTU [${MTU}]: ")" || custom=""
        custom="${custom:-$MTU}"
        if valid_mtu "$custom"; then
          MTU="$custom"
          MTU_POLICY="custom"
          break
        fi
        warn "$(t '请输入 1280-1500 的整数' 'Enter an integer from 1280 to 1500')"
      done
      ;;
    *)
      MTU=1400
      MTU_POLICY="safe"
      ;;
  esac
  print_mtu_selection
}
