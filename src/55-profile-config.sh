normalize_profile() {
  case "$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]' | tr '_ ' '--')" in
    iplc|iplc-performance|performance) printf 'iplc' ;;
    balanced|balance|default) printf 'balanced' ;;
    stealth|obfuscation) printf 'stealth' ;;
    custom|advanced) printf 'custom' ;;
    *) return 1 ;;
  esac
}

# Optional argument is part of the public helper API.
# shellcheck disable=SC2120
profile_label() {
  case "$(normalize_profile "${1:-${PROFILE:-custom}}" 2>/dev/null || printf custom)" in
    iplc) t 'IPLC / 专线性能' 'IPLC / Dedicated-line Performance' ;;
    balanced) t '普通公网' 'General Public Network' ;;
    stealth) t '强化伪装' 'Enhanced Camouflage' ;;
    *) t '高级自定义' 'Advanced Custom' ;;
  esac
}

profile_values_match() {
  local expected="$1"
  local proto mtu mux handshake traffic low
  proto="$(normalize_protocol "${PROTOCOL:-TCP}" 2>/dev/null || true)"
  mtu="$(normalize_uint "${MTU:-}" 2>/dev/null || true)"
  mux="$(normalize_multiplexing "${MULTIPLEXING:-}" 2>/dev/null || true)"
  handshake="$(normalize_handshake_mode "${HANDSHAKE_MODE:-}" 2>/dev/null || true)"
  traffic="$(normalize_traffic_pattern "${TRAFFIC_PATTERN:-}" 2>/dev/null || true)"
  low="$(normalize_low_entropy_mode "${LOW_ENTROPY_MODE:-}" 2>/dev/null || true)"
  case "$expected" in
    iplc)
      [ "$proto|$mtu|$mux|$handshake|$traffic|$low" = \
        'TCP|1400|MULTIPLEXING_OFF|HANDSHAKE_NO_WAIT|off|LOW_ENTROPY_MODE_OFF' ]
      ;;
    balanced)
      [ "$proto|$mtu|$mux|$handshake|$traffic|$low" = \
        'TCP|1400|MULTIPLEXING_OFF|HANDSHAKE_NO_WAIT|conservative|LOW_ENTROPY_MODE_OFF' ]
      ;;
    stealth)
      [ "$proto|$mtu|$mux|$handshake|$traffic|$low" = \
        'TCP|1400|MULTIPLEXING_OFF|HANDSHAKE_NO_WAIT|aggressive|LOW_ENTROPY_MODE_OFF' ]
      ;;
    *) return 1 ;;
  esac
}

infer_profile_from_values() {
  local candidate
  for candidate in iplc balanced stealth; do
    if profile_values_match "$candidate"; then
      printf '%s' "$candidate"
      return 0
    fi
  done
  printf 'custom'
}

apply_profile_values() {
  local selected
  selected="$(normalize_profile "${1:-}")" || return 1
  PROFILE="$selected"
  case "$selected" in
    iplc)
      PROTOCOL=TCP
      MTU=1400
      MTU_POLICY=safe
      MULTIPLEXING=MULTIPLEXING_OFF
      HANDSHAKE_MODE=HANDSHAKE_NO_WAIT
      TRAFFIC_PATTERN=off
      LOW_ENTROPY_MODE=LOW_ENTROPY_MODE_OFF
      ;;
    balanced)
      PROTOCOL=TCP
      MTU=1400
      MTU_POLICY=safe
      MULTIPLEXING=MULTIPLEXING_OFF
      HANDSHAKE_MODE=HANDSHAKE_NO_WAIT
      TRAFFIC_PATTERN=conservative
      LOW_ENTROPY_MODE=LOW_ENTROPY_MODE_OFF
      ;;
    stealth)
      PROTOCOL=TCP
      MTU=1400
      MTU_POLICY=safe
      MULTIPLEXING=MULTIPLEXING_OFF
      HANDSHAKE_MODE=HANDSHAKE_NO_WAIT
      TRAFFIC_PATTERN=aggressive
      # Low Entropy 始终是单独确认的高开销高级选项，预设不得自动开启。
      LOW_ENTROPY_MODE=LOW_ENTROPY_MODE_OFF
      ;;
    custom) ;;
  esac
}

apply_requested_profile_preserving_cli() {
  [ "${PROFILE_CLI:-0}" -eq 1 ] || return 0
  local cli_protocol="$PROTOCOL" cli_mtu_request="$MTU_REQUEST"
  local cli_mux="$MULTIPLEXING" cli_handshake="$HANDSHAKE_MODE"
  local cli_traffic="$TRAFFIC_PATTERN" cli_low="$LOW_ENTROPY_MODE"
  apply_profile_values "$PROFILE" || die "$(t '非法 Profile（iplc/balanced/stealth/custom）' \
    'Invalid profile (iplc/balanced/stealth/custom)')"
  [ "${PROTOCOL_CLI:-0}" -eq 0 ] || PROTOCOL="$cli_protocol"
  [ "${MTU_CLI:-0}" -eq 0 ] || MTU_REQUEST="$cli_mtu_request"
  [ "${MULTIPLEXING_CLI:-0}" -eq 0 ] || MULTIPLEXING="$cli_mux"
  [ "${HANDSHAKE_CLI:-0}" -eq 0 ] || HANDSHAKE_MODE="$cli_handshake"
  [ "${TRAFFIC_CLI:-0}" -eq 0 ] || TRAFFIC_PATTERN="$cli_traffic"
  [ "${LOW_ENTROPY_CLI:-0}" -eq 0 ] || LOW_ENTROPY_MODE="$cli_low"
}

profile_reconcile_metadata() {
  PROFILE="$(normalize_profile "${PROFILE:-custom}" 2>/dev/null || printf custom)"
  [ "$PROFILE" = custom ] && return 0
  profile_values_match "$PROFILE" || PROFILE=custom
}

choose_profile_interactive() {
  local input="" def=2
  case "$(normalize_profile "${PROFILE:-balanced}" 2>/dev/null || printf balanced)" in
    iplc) def=1 ;;
    stealth) def=3 ;;
    custom) def=4 ;;
  esac
  msg ""
  t '配置预设（真实参数仍会完整保存；之后单独修改参数会自动变为高级自定义）:' \
    'Configuration profile (full parameters are saved; later manual edits become Advanced Custom):'
  t '  1) IPLC / 专线性能 — IPLC、企业专线、明确允许使用的网络' \
    '  1) IPLC / Dedicated-line Performance — IPLC, enterprise lines, permitted networks'
  t '  2) 普通公网 — 普通 VPS / 公网环境' \
    '  2) General Public Network — ordinary VPS / public networks'
  t '  3) 强化伪装 — 更强 traffic-pattern；Low Entropy 仍默认关闭' \
    '  3) Enhanced Camouflage — stronger traffic-pattern; Low Entropy remains off'
  t '  4) 高级自定义 — 逐项配置全部高级参数' \
    '  4) Advanced Custom — configure every advanced parameter'
  read_tty input "$(t "请选择 [1-4，默认 ${def}]: " "Choose [1-4, default ${def}]: ")" || input=""
  input="${input:-$def}"
  case "$input" in
    1) apply_profile_values iplc ;;
    3) apply_profile_values stealth ;;
    4) PROFILE=custom ;;
    *) apply_profile_values balanced ;;
  esac
  t "已选 Profile: $(profile_label)" "Selected profile: $(profile_label)"
}

choose_protocol_interactive() {
  msg ""
  t '传输协议:' 'Transport protocol:'
  t '  1) TCP（推荐；Clash 设 udp: true 即可）' \
    '  1) TCP (recommended; Clash udp: true is enough)'
  t '  2) UDP' '  2) UDP'
  t '  3) TCP + UDP 双协议（UDP 端口 = TCP 端口 + 1）' \
    '  3) TCP + UDP dual (UDP port = TCP port + 1)'
  msg ""
  local choice=""
  read_tty choice "$(t '请选择协议 [1-3，默认 1]: ' 'Choose protocol [1-3, default 1]: ')" || choice="1"
  choice="${choice:-1}"
  case "$choice" in
    1|TCP|tcp) PROTOCOL="TCP" ;;
    2|UDP|udp) PROTOCOL="UDP" ;;
    3|BOTH|both|双协议) PROTOCOL="BOTH" ;;
    *)
      warn "$(t "无效选择「${choice}」，使用默认 TCP" "Invalid choice \"${choice}\", using TCP")"
      PROTOCOL="TCP"
      ;;
  esac
}

collect_advertise_endpoint_interactive() {
  local input="" candidate="" detected="" auto_selected=0
  local default_host="${ADVERTISE_HOST:-}" default_port="${ADVERTISE_PORT:-${PORT:-}}"
  if [ "${ADVERTISE_CLI:-0}" -eq 1 ]; then
    validate_advertise_endpoint || die "$(t '自定义客户端入口参数无效' \
      'Invalid custom client entry parameters')"
    [ -z "$ADVERTISE_PORT" ] || ADVERTISE_PORT="$(normalize_uint "$ADVERTISE_PORT")"
    return
  fi

  msg ""
  if [ -z "$default_host" ]; then
    detected="$(public_ip 2>/dev/null || true)"
    default_host="$detected"
  fi
  if [ -n "$detected" ]; then
    t "检测到服务器公网 IP: ${detected}" "Detected server public IP: ${detected}"
  fi
  t '客户端入口只用于节点展示/导出，不会修改 mita 监听、firewall 或 tc。' \
    'The client entry is only used in client exports; it never changes mita listeners, firewall, or tc.'
  t '如前面有 IPLC/NAT/端口映射，请在这里填写用户真正连接的入口；输入 auto 可恢复自动探测。' \
    'If IPLC/NAT/port mapping is in front, enter the endpoint clients really use; enter auto to restore auto detection.'

  while true; do
    input=""
    if [ -n "$default_host" ]; then
      read_tty input "$(t "客户端连接时使用的入口地址 [${default_host}]: " \
        "Client entry host [${default_host}]: ")" || input=""
    else
      read_tty input "$(t '客户端连接时使用的入口地址: ' \
        'Client entry host: ')" || input=""
    fi
    candidate="${input:-$default_host}"
    candidate="$(printf '%s' "$candidate" | tr -d '[:space:]')"
    if [ "$(printf '%s' "$candidate" | tr '[:upper:]' '[:lower:]')" = auto ]; then
      auto_selected=1
      ADVERTISE_HOST=""
      break
    fi
    if valid_advertise_host "$candidate"; then
      ADVERTISE_HOST="$candidate"
      break
    fi
    warn "$(t '入口地址无效，请重新输入 IPv4、IPv6 或域名' \
      'Invalid entry host; enter IPv4, IPv6, or a domain name')"
  done

  while true; do
    input=""
    read_tty input "$(t "客户端入口端口 [${default_port}]: " \
      "Client entry port [${default_port}]: ")" || input=""
    candidate="${input:-$default_port}"
    if [ "$auto_selected" -eq 1 ]; then
      if valid_advertise_port "$candidate"; then
        ADVERTISE_PORT=""
        break
      fi
    elif validate_advertise_endpoint_values "$ADVERTISE_HOST" "$candidate" "$PROTOCOL"; then
      ADVERTISE_PORT="$(normalize_uint "$candidate")"
      break
    fi
    warn "$(t '入口端口必须是 1-65535 的整数' \
      'Client entry port must be an integer from 1 to 65535')"
  done

  msg ""
  if [ "$auto_selected" -eq 1 ]; then
    t '客户端入口: 自动探测公网地址并使用实际监听端口' \
      'Client entry: auto-detected public address with the backend listen port'
  elif [ "$PROTOCOL" = "BOTH" ]; then
    t "客户端配置将展示: ${ADVERTISE_HOST}，TCP ${ADVERTISE_PORT} / UDP $((ADVERTISE_PORT + 1))" \
      "Client configs will show: ${ADVERTISE_HOST}, TCP ${ADVERTISE_PORT} / UDP $((ADVERTISE_PORT + 1))"
  else
    t "客户端配置将展示: ${ADVERTISE_HOST}:${ADVERTISE_PORT}" \
      "Client configs will show: ${ADVERTISE_HOST}:${ADVERTISE_PORT}"
  fi
  t "服务端仍使用实际监听端口 ${PORT}；自定义入口不修改 mita、防火墙或 tc 配置" \
    "The server still listens on ${PORT}; the custom entry does not change mita, firewall, or tc settings"
}

normalize_multiplexing() {
  case "$(printf '%s' "${1:-}" | tr '[:lower:]' '[:upper:]')" in
    OFF|0|NO|DISABLED|MULTIPLEXING_OFF) printf 'MULTIPLEXING_OFF' ;;
    LOW|MULTIPLEXING_LOW) printf 'MULTIPLEXING_LOW' ;;
    MIDDLE|MEDIUM|MULTIPLEXING_MIDDLE) printf 'MULTIPLEXING_MIDDLE' ;;
    HIGH|MULTIPLEXING_HIGH) printf 'MULTIPLEXING_HIGH' ;;
    *) return 1 ;;
  esac
}

normalize_handshake_mode() {
  case "$(printf '%s' "${1:-}" | tr '[:lower:]' '[:upper:]' | tr '-' '_')" in
    NO_WAIT|NOWAIT|0RTT|HANDSHAKE_NO_WAIT) printf 'HANDSHAKE_NO_WAIT' ;;
    STANDARD|WAIT|HANDSHAKE_STANDARD) printf 'HANDSHAKE_STANDARD' ;;
    *) return 1 ;;
  esac
}

normalize_low_entropy_mode() {
  case "$(printf '%s' "${1:-}" | tr '[:lower:]' '[:upper:]')" in
    OFF|0|NO|DISABLED|LOW_ENTROPY_MODE_OFF) printf 'LOW_ENTROPY_MODE_OFF' ;;
    56|MODE_56|LOW_ENTROPY_MODE_56) printf 'LOW_ENTROPY_MODE_56' ;;
    48|MODE_48|LOW_ENTROPY_MODE_48) printf 'LOW_ENTROPY_MODE_48' ;;
    40|MODE_40|LOW_ENTROPY_MODE_40) printf 'LOW_ENTROPY_MODE_40' ;;
    32|MODE_32|LOW_ENTROPY_MODE_32) printf 'LOW_ENTROPY_MODE_32' ;;
    *) return 1 ;;
  esac
}

low_entropy_label() {
  case "$(normalize_low_entropy_mode "${LOW_ENTROPY_MODE:-LOW_ENTROPY_MODE_OFF}" 2>/dev/null || true)" in
    LOW_ENTROPY_MODE_56) t '56（约 1.15 倍流量）' '56 (~1.15x traffic)' ;;
    LOW_ENTROPY_MODE_48) t '48（约 1.34 倍流量）' '48 (~1.34x traffic)' ;;
    LOW_ENTROPY_MODE_40) t '40（约 1.6 倍流量）' '40 (~1.6x traffic)' ;;
    LOW_ENTROPY_MODE_32) t '32（约 2 倍流量）' '32 (~2x traffic)' ;;
    *) t '关闭' 'Off' ;;
  esac
}

warn_low_entropy_client_compat() {
  [ "$(normalize_low_entropy_mode "${LOW_ENTROPY_MODE:-LOW_ENTROPY_MODE_OFF}" 2>/dev/null || true)" != "LOW_ENTROPY_MODE_OFF" ] || return 0
  warn "$(t \
    '低熵模式是较新的实验性能力；请确认客户端确实支持 lowEntropy。尚未适配的 mihomo 等客户端可能无法正确使用，不确定时请保持关闭并优先使用官方 mieru 客户端。' \
    'Low entropy is a newer experimental capability. Confirm that the client supports lowEntropy; clients such as mihomo builds without adaptation may not work correctly. Keep it off when unsure and prefer the official mieru client.')"
}

choose_client_modes_interactive() {
  local input="" def=1
  if [ "${MULTIPLEXING_CLI:-0}" -ne 1 ]; then
    case "$(normalize_multiplexing "${MULTIPLEXING:-MULTIPLEXING_OFF}" 2>/dev/null || true)" in
      MULTIPLEXING_LOW) def=2 ;;
      MULTIPLEXING_MIDDLE) def=3 ;;
      MULTIPLEXING_HIGH) def=4 ;;
      *) def=1 ;;
    esac
    msg ""
    t '多路复用模式（默认推荐关闭）:' 'Multiplexing mode (OFF recommended by default):'
    t '  1) MULTIPLEXING_OFF（推荐）' '  1) MULTIPLEXING_OFF (recommended)'
    t '  2) MULTIPLEXING_LOW' '  2) MULTIPLEXING_LOW'
    t '  3) MULTIPLEXING_MIDDLE' '  3) MULTIPLEXING_MIDDLE'
    t '  4) MULTIPLEXING_HIGH' '  4) MULTIPLEXING_HIGH'
    read_tty input "$(t "请选择 [1-4，默认 ${def}]: " "Choose [1-4, default ${def}]: ")" || input=""
    input="${input:-$def}"
    case "$input" in
      2) MULTIPLEXING="MULTIPLEXING_LOW" ;;
      3) MULTIPLEXING="MULTIPLEXING_MIDDLE" ;;
      4) MULTIPLEXING="MULTIPLEXING_HIGH" ;;
      *) MULTIPLEXING="MULTIPLEXING_OFF" ;;
    esac
  fi

  input=""
  def=1
  if [ "${HANDSHAKE_CLI:-0}" -ne 1 ]; then
    [ "$(normalize_handshake_mode "${HANDSHAKE_MODE:-HANDSHAKE_NO_WAIT}" 2>/dev/null || true)" = "HANDSHAKE_STANDARD" ] && def=2
    msg ""
    t '握手模式:' 'Handshake mode:'
    t '  1) HANDSHAKE_NO_WAIT（推荐，0-RTT）' '  1) HANDSHAKE_NO_WAIT (recommended, 0-RTT)'
    t '  2) HANDSHAKE_STANDARD' '  2) HANDSHAKE_STANDARD'
    read_tty input "$(t "请选择 [1-2，默认 ${def}]: " "Choose [1-2, default ${def}]: ")" || input=""
    input="${input:-$def}"
    case "$input" in
      2) HANDSHAKE_MODE="HANDSHAKE_STANDARD" ;;
      *) HANDSHAKE_MODE="HANDSHAKE_NO_WAIT" ;;
    esac
  fi

  msg ""
  t "客户端模式: ${MULTIPLEXING} / ${HANDSHAKE_MODE}" \
    "Client modes: ${MULTIPLEXING} / ${HANDSHAKE_MODE}"
}

choose_low_entropy_interactive() {
  local current input="" def=1 enabled_default="n"
  if [ "$(normalize_traffic_pattern "${TRAFFIC_PATTERN:-conservative}")" = "off" ]; then
    LOW_ENTROPY_MODE="LOW_ENTROPY_MODE_OFF"
    return 0
  fi
  if [ "${LOW_ENTROPY_CLI:-0}" -eq 1 ]; then
    warn_low_entropy_client_compat
    return 0
  fi

  current="$(normalize_low_entropy_mode "${LOW_ENTROPY_MODE:-LOW_ENTROPY_MODE_OFF}" 2>/dev/null || printf 'LOW_ENTROPY_MODE_OFF')"
  [ "$current" != "LOW_ENTROPY_MODE_OFF" ] && enabled_default="y"
  msg ""
  if [ "$enabled_default" = "y" ]; then
    read_tty input "$(t '是否启用低熵模式？会增加流量和 CPU 开销 [Y/n]: ' \
      'Enable low entropy mode? This increases traffic and CPU load [Y/n]: ')" || input=""
    input="${input:-y}"
  else
    read_tty input "$(t '是否启用低熵模式？会增加流量和 CPU 开销 [y/N]: ' \
      'Enable low entropy mode? This increases traffic and CPU load [y/N]: ')" || input=""
    input="${input:-n}"
  fi
  case "$(printf '%s' "$input" | tr '[:upper:]' '[:lower:]')" in
    y|yes|1|是) ;;
    *)
      LOW_ENTROPY_MODE="LOW_ENTROPY_MODE_OFF"
      t '低熵模式: 关闭（推荐默认）' 'Low entropy: Off (recommended default)'
      return 0
      ;;
  esac

  case "$current" in
    LOW_ENTROPY_MODE_48) def=2 ;;
    LOW_ENTROPY_MODE_40) def=3 ;;
    LOW_ENTROPY_MODE_32) def=4 ;;
    *) def=1 ;;
  esac
  msg ""
  t '低熵强度（数字越小，伪装越强，但开销越大）:' \
    'Low entropy strength (smaller means stronger disguise and more overhead):'
  t '  1) 56 —— 需要 Low Entropy 时优先考虑；约增加 15% 数据体积' \
    '  1) 56 — first choice when Low Entropy is needed; about 15% more data'
  t '  2) 48 —— 更强 Low Entropy；流量开销进一步增加（约 34%）' \
    '  2) 48 — stronger Low Entropy; higher traffic overhead (~34%)'
  t '  3) 40 —— 高开销高级模式（约 60%）' \
    '  3) 40 — high-overhead advanced mode (~60%)'
  t '  4) 32 —— 高开销高级模式（约 100%）' \
    '  4) 32 — high-overhead advanced mode (~100%)'
  t '性能优先（IPLC/明确允许 Mieru 的环境）应保持 OFF。' \
    'For performance-first IPLC or explicitly permitted networks, keep this OFF.'
  input=""
  read_tty input "$(t "请选择 [1-4，默认 ${def}]: " "Choose [1-4, default ${def}]: ")" || input=""
  input="${input:-$def}"
  case "$input" in
    2) LOW_ENTROPY_MODE="LOW_ENTROPY_MODE_48" ;;
    3) LOW_ENTROPY_MODE="LOW_ENTROPY_MODE_40" ;;
    4) LOW_ENTROPY_MODE="LOW_ENTROPY_MODE_32" ;;
    *) LOW_ENTROPY_MODE="LOW_ENTROPY_MODE_56" ;;
  esac
  t "低熵模式: $(low_entropy_label)" "Low entropy: $(low_entropy_label)"
  warn_low_entropy_client_compat
}

choose_traffic_pattern_interactive() {
  [ "${TRAFFIC_CLI:-0}" -eq 1 ] && return 0
  local cur def input="" enable_default="y"
  cur="$(normalize_traffic_pattern "${TRAFFIC_PATTERN:-conservative}")"
  [ "$cur" = "off" ] && enable_default="n"
  msg ""
  if [ "$enable_default" = "y" ]; then
    read_tty input "$(t '是否加入 traffic-pattern 流量伪装？[Y/n]: ' \
      'Include traffic-pattern obfuscation? [Y/n]: ')" || input=""
    input="${input:-y}"
  else
    read_tty input "$(t '是否加入 traffic-pattern 流量伪装？[y/N]: ' \
      'Include traffic-pattern obfuscation? [y/N]: ')" || input=""
    input="${input:-n}"
  fi
  case "$(printf '%s' "$input" | tr '[:upper:]' '[:lower:]')" in
    y|yes|1|是) ;;
    *)
      TRAFFIC_PATTERN="off"
      msg ""
      t '已选择不加入 traffic-pattern' 'traffic-pattern will not be included'
      return 0
      ;;
  esac

  def=1
  [ "$cur" = "aggressive" ] && def=2
  msg ""
  t 'traffic-pattern 主要用于改变流量特征，并不是性能优化功能（客户端无需与服务端一致）:' \
    'traffic-pattern changes traffic characteristics; it is not a performance feature (client need not match server):'
  t '  1) 保守 —— 可打印 Nonce + 末尾填充，额外开销较低（推荐）' \
    '  1) Conservative — printable nonce + end padding, lower extra overhead (recommended)'
  t '  2) 激进 —— 再加 TCP 分片 + 全量填充，更隐蔽但增加延迟/降速' \
    '  2) Aggressive — also TCP fragment + full padding, stealthier but slower'
  input=""
  read_tty input "$(t "请选择 [1-2，默认 ${def}]: " "Choose [1-2, default ${def}]: ")" || input=""
  input="${input:-$def}"
  case "$input" in
    2) TRAFFIC_PATTERN="aggressive" ;;
    *) TRAFFIC_PATTERN="conservative" ;;
  esac
  msg ""
  t "已选流量伪装: $(traffic_label)" "Traffic obfuscation: $(traffic_label)"
}

collect_config_interactive() {
  STAGE="交互配置"
  local requested_protocol="$PROTOCOL" requested_mtu="$MTU_REQUEST"
  local requested_mux="$MULTIPLEXING" requested_handshake="$HANDSHAKE_MODE"
  local requested_traffic="$TRAFFIC_PATTERN" requested_low="$LOW_ENTROPY_MODE"
  [ -n "$USERNAME" ] || USERNAME="$(random_token)"
  [ -n "$PASSWORD" ] || PASSWORD="$(random_token)"
  msg ""
  t '已自动生成代理凭据（安装完成后会再次显示）:' \
    'Proxy credentials auto-generated (shown again after install):'
  t "  用户名: ${USERNAME}" "  Username: ${USERNAME}"
  t "  密码:   ${PASSWORD}" "  Password: ${PASSWORD}"

  if [ "${PROFILE_CLI:-0}" -eq 1 ]; then
    apply_requested_profile_preserving_cli
  else
    choose_profile_interactive
    [ "${PROTOCOL_CLI:-0}" -eq 0 ] || PROTOCOL="$requested_protocol"
    [ "${MTU_CLI:-0}" -eq 0 ] || MTU_REQUEST="$requested_mtu"
    [ "${MULTIPLEXING_CLI:-0}" -eq 0 ] || MULTIPLEXING="$requested_mux"
    [ "${HANDSHAKE_CLI:-0}" -eq 0 ] || HANDSHAKE_MODE="$requested_handshake"
    [ "${TRAFFIC_CLI:-0}" -eq 0 ] || TRAFFIC_PATTERN="$requested_traffic"
    [ "${LOW_ENTROPY_CLI:-0}" -eq 0 ] || LOW_ENTROPY_MODE="$requested_low"
  fi

  if [ "$PROTOCOL_CLI" -eq 0 ] && [ "$PROFILE" = custom ]; then
    choose_protocol_interactive
  fi

  msg ""
  if [ -z "$PORT" ] && [ -z "$PORT_RANGE" ]; then
    local default_port input="" candidate="" base="" localip="" segment_hi=99
    localip="$(detect_local_ip)"
    [ "$PROTOCOL" = "BOTH" ] && segment_hi=98
    if base="$(derive_port_base)"; then
      if ! default_port="$(derive_port_from_ip)"; then
        warn "$(t "IP 尾号端口段 $((base + 1))-$((base + segment_hi)) 当前没有可用端口，回退全局随机端口" \
          "No available port in IP-derived range $((base + 1))-$((base + segment_hi)); falling back to a global random port")"
        default_port="$(random_available_port)" \
          || die "$(t '未找到可用监听端口' 'No available listen port found')"
      fi
      t "检测到本机 IP ${localip}，按尾号规则端口段 $((base + 1))-$((base + segment_hi))（${base} 留给 SSH，默认选择已校验的空闲端口）" \
        "Detected local IP ${localip}; range $((base + 1))-$((base + segment_hi)) (${base} reserved for SSH); default is a verified free port"
    else
      default_port="$(random_available_port)" \
        || die "$(t '未找到可用监听端口' 'No available listen port found')"
      warn "$(t "无法按 IP 尾号推导端口（IP=${localip:-未知}，尾号过小或无法识别），回退随机端口" \
        "Cannot derive port from IP last octet (IP=${localip:-unknown}); falling back to random port")"
    fi
    while true; do
      input=""
      read_tty input "$(t "监听端口 [${default_port}]: " "Listen port [${default_port}]: ")" || input=""
      candidate="${input:-$default_port}"
      if ! valid_port "$candidate"; then
        warn "$(t '非法端口，请重新输入' 'Invalid port; try again')"
        continue
      fi
      candidate="$(normalize_uint "$candidate")"
      if [ "$PROTOCOL" = "BOTH" ] && [ "$candidate" -ge 65535 ]; then
        warn "$(t '双协议需要主端口 ≤65534（UDP 使用主端口+1）' \
          'Dual protocol needs main port ≤65534 (UDP uses main port + 1)')"
        continue
      fi
      if ! port_available_for_mode "$candidate"; then
        warn "$(t "端口 ${candidate} 已被占用，请重新输入" \
          "Port ${candidate} is already in use; try again")"
        port_listener_details "$candidate"
        continue
      fi
      PORT="$candidate"
      [ -z "$input" ] && PORT_AUTO_SELECTED=1 || PORT_AUTO_SELECTED=0
      break
    done
    if [ -n "$base" ] && { [ "$PORT" -lt "$((base + 1))" ] || [ "$PORT" -gt "$((base + segment_hi))" ]; }; then
      warn "$(t "注意：端口 ${PORT} 不在 IP 尾号段 $((base + 1))-$((base + segment_hi)) 内，可能与按 IP 分配端口的约定冲突" \
        "Note: port ${PORT} is outside the IP last-octet range $((base + 1))-$((base + segment_hi)); may break the per-IP port convention")"
    fi
  elif [ -n "$PORT" ] && [ -n "$PORT_RANGE" ]; then
    die "$(t '不能同时指定端口与端口段' 'Cannot set both port and port range')"
  fi

  if [ "$PROTOCOL" = "BOTH" ] && [ -n "$PORT" ] && [ "$PORT" -ge 65535 ]; then
    die "$(t '双协议需要主端口 ≤65534（UDP 使用主端口+1）' \
      'Dual protocol needs main port ≤65534 (UDP uses main port + 1)')"
  fi
  msg ""
  t "已选协议: $(protocol_label)" "Selected protocol: $(protocol_label)"
  collect_advertise_endpoint_interactive
  if [ "$PROFILE" = custom ]; then
    choose_mtu_interactive
    choose_client_modes_interactive
    choose_traffic_pattern_interactive
    choose_low_entropy_interactive
  else
    [ "${MTU_CLI:-0}" -eq 0 ] || resolve_mtu_request
    t "预设参数: $(protocol_label) / MTU ${MTU} / ${MULTIPLEXING} / ${HANDSHAKE_MODE}" \
      "Preset parameters: $(protocol_label) / MTU ${MTU} / ${MULTIPLEXING} / ${HANDSHAKE_MODE}"
    t "Traffic Pattern: $(traffic_label)；Low Entropy: $(low_entropy_label)" \
      "Traffic Pattern: $(traffic_label); Low Entropy: $(low_entropy_label)"
  fi
  profile_reconcile_metadata
  ensure_traffic_seed
  validate_proxy_credentials
}

load_config_from_mita() {
  local cli_user="$USERNAME" cli_password="$PASSWORD"
  local cli_port="$PORT" cli_port_range="$PORT_RANGE" cli_protocol="$PROTOCOL"
  local cli_advertise_host="$ADVERTISE_HOST" cli_advertise_port="$ADVERTISE_PORT"
  local cli_mtu_request="$MTU_REQUEST"
  load_install_state || return 1
  users_isolated_mode || {
    bail "$(t 'schema v3 Mieru 状态必须使用 isolated-v2' \
      'Schema-v3 Mieru state must use isolated-v2')" || return 1
  }
  users_sync_primary_globals
  PORT_RANGE=""
  MTU_POLICY="$(normalize_mtu_policy "$MTU_POLICY" 2>/dev/null || printf 'safe')"
  [ "${USERNAME_CLI:-0}" -eq 1 ] && USERNAME="$cli_user"
  [ "${PASSWORD_CLI:-0}" -eq 1 ] && PASSWORD="$cli_password"
  [ "${PORT_CLI:-0}" -eq 1 ] && PORT="$cli_port"
  [ "${PORT_RANGE_CLI:-0}" -eq 1 ] && { PORT=""; PORT_RANGE="$cli_port_range"; }
  [ "${PROTOCOL_CLI:-0}" -eq 1 ] && PROTOCOL="$cli_protocol"
  if [ "${ADVERTISE_CLI:-0}" -eq 1 ]; then
    ADVERTISE_HOST="$cli_advertise_host"
    ADVERTISE_PORT="$cli_advertise_port"
  fi
  [ "${MTU_CLI:-0}" -eq 1 ] && MTU_REQUEST="$cli_mtu_request"
  validate_proxy_credentials
}

collect_reconfigure_interactive() {
  STAGE="重新配置"
  load_config_from_mita
  msg ""
  t '【当前配置】' '[Current config]'
  t "  用户名: ${USERNAME}" "  Username: ${USERNAME}"
  t '  密码:   （已隐藏）' '  Password: (hidden)'
  t "  协议:   $(protocol_label)" "  Protocol: $(protocol_label)"
  t "  MTU:    ${MTU}（$(mtu_policy_label)）" \
    "  MTU:      ${MTU} ($(mtu_policy_label))"
  if [ -n "$PORT" ]; then
    t "  端口:   ${PORT}" "  Port:     ${PORT}"
  else
    t "  端口段: ${PORT_RANGE}" "  Port range: ${PORT_RANGE}"
  fi
  msg ""
  t '留空则保持当前值' 'Press Enter to keep current value'

  local input=""
  read_tty input "$(t "新用户名 [${USERNAME}]: " "New username [${USERNAME}]: ")" || input=""
  [ -n "$input" ] && USERNAME="$input"

  input=""
  read_tty_secret input "$(t '新密码（留空保持当前）: ' 'New password (Enter to keep current): ')" || input=""
  [ -n "$input" ] && PASSWORD="$input"

  if [ "$PROTOCOL_CLI" -eq 0 ]; then
    msg ""
    t '是否更改传输协议？' 'Change transport protocol?'
    t '  1) 保持当前' '  1) Keep current'
    t '  2) 重新选择' '  2) Choose again'
    input=""
    read_tty input "$(t '请选择 [1-2，默认 1]: ' 'Choose [1-2, default 1]: ')" || input="1"
    input="${input:-1}"
    if [ "$input" = "2" ]; then
      choose_protocol_interactive
    fi
  fi

  if [ -z "$PORT_RANGE" ]; then
    msg ""
    input=""
    read_tty input "$(t "新监听端口 [${PORT}]: " "New listen port [${PORT}]: ")" || input=""
    if [ -n "$input" ]; then
      PORT="$input"
      valid_port "$PORT" || die "$(t '非法端口' 'Invalid port')"
      PORT="$(normalize_uint "$PORT")"
    fi
  fi

  if [ "$PROTOCOL" = "BOTH" ] && [ -n "$PORT" ] && [ "$PORT" -ge 65535 ]; then
    die "$(t '双协议需要主端口 ≤65534' 'Dual protocol needs main port ≤65534')"
  fi
  collect_advertise_endpoint_interactive
  choose_mtu_interactive
  choose_client_modes_interactive
  choose_traffic_pattern_interactive
  choose_low_entropy_interactive
  ensure_traffic_seed
  validate_proxy_credentials
  msg ""
  t "将应用协议: $(protocol_label)" "Will apply protocol: $(protocol_label)"
}

ensure_config_noninteractive() {
  STAGE="参数校验"
  apply_requested_profile_preserving_cli
  [ -n "$PORT" ] && [ -n "$PORT_RANGE" ] && \
    die "$(t '--port 与 --port-range 不能同时使用' 'Cannot use --port and --port-range together')"
  [ -n "$USERNAME" ] || USERNAME="$(random_token)"
  [ -n "$PASSWORD" ] || PASSWORD="$(random_token)"
  validate_proxy_credentials
  PROTOCOL="$(normalize_protocol "$PROTOCOL")" || \
    die "$(t '非法协议（仅支持 TCP/UDP/BOTH）' \
      'Invalid protocol (only TCP/UDP/BOTH are supported)')"
  if [ -z "$PORT" ] && [ -z "$PORT_RANGE" ]; then
    PORT="$(select_available_port)" \
      || die "$(t '未找到可用监听端口' 'No available listen port found')"
    PORT_AUTO_SELECTED=1
  fi
  if [ -n "$PORT" ]; then
    valid_port "$PORT" || die "$(t '非法端口' 'Invalid port')"
    PORT="$(normalize_uint "$PORT")"
    local _base
    if _base="$(derive_port_base 2>/dev/null)" \
       && { [ "$PORT" -lt "$((_base + 1))" ] || [ "$PORT" -gt "$((_base + 99))" ]; }; then
      warn "$(t "端口 ${PORT} 不在本机 IP 尾号段 $((_base + 1))-$((_base + 99)) 内（如非本机 IP 可忽略）" \
        "Port ${PORT} is outside this host's IP last-octet range $((_base + 1))-$((_base + 99)) (ignore if intended)")"
    fi
  fi
  if [ -n "$PORT_RANGE" ]; then
    die "$(t 'v2 用户专属实例不支持 --port-range，请使用单个 --port' \
      'v2 dedicated user instances do not support --port-range; use one --port')"
  fi
  if [ "$PROTOCOL" = "BOTH" ] && [ -n "$PORT" ] && [ "$PORT" -ge 65535 ]; then
    die "$(t '双协议需要主端口 ≤65534' 'Dual protocol needs main port ≤65534')"
  fi
  validate_advertise_endpoint || die "$(t '自定义客户端入口参数无效' \
    'Invalid custom client entry parameters')"
  [ -z "$ADVERTISE_PORT" ] || ADVERTISE_PORT="$(normalize_uint "$ADVERTISE_PORT")"
  resolve_mtu_request || return 1
  [ "${MTU_CLI:-0}" -eq 1 ] && print_mtu_selection
  TRAFFIC_PATTERN="$(normalize_traffic_pattern "$TRAFFIC_PATTERN")" || \
    die "$(t '非法 traffic-pattern 模式' 'Invalid traffic-pattern mode')"
  LOW_ENTROPY_MODE="$(normalize_low_entropy_mode "$LOW_ENTROPY_MODE")" || \
    die "$(t '非法低熵模式' 'Invalid low entropy mode')"
  [ "$TRAFFIC_PATTERN" != "off" ] || LOW_ENTROPY_MODE="LOW_ENTROPY_MODE_OFF"
  warn_low_entropy_client_compat
  MULTIPLEXING="$(normalize_multiplexing "$MULTIPLEXING")" || \
    die "$(t '非法 multiplexing 模式' 'Invalid multiplexing mode')"
  HANDSHAKE_MODE="$(normalize_handshake_mode "$HANDSHAKE_MODE")" || \
    die "$(t '非法 handshake mode' 'Invalid handshake mode')"
  profile_reconcile_metadata
  ensure_traffic_seed
}

normalize_traffic_pattern() {
  case "$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')" in
    off|none|no|0|disable|disabled|close|关) printf 'off' ;;
    aggressive|aggr|full|high|强|激进|2) printf 'aggressive' ;;
    conservative|cons|safe|low|保守|1) printf 'conservative' ;;
    *) return 1 ;;
  esac
}

traffic_label() {
  case "$(normalize_traffic_pattern "${TRAFFIC_PATTERN:-conservative}")" in
    off) t '关闭' 'Off' ;;
    aggressive) t '激进' 'Aggressive' ;;
    *) t '保守' 'Conservative' ;;
  esac
}

random_seed() {
  local s=""
  if [ -r /dev/urandom ] && command -v od >/dev/null 2>&1; then
    s="$(od -An -N4 -tu4 /dev/urandom 2>/dev/null | tr -dc '0-9')"
  fi
  [ -n "$s" ] || s=$(( (RANDOM << 15) | RANDOM ))
  printf '%s' "$(( s % 2147483647 ))"
}

# 流量模式自 mita v3.28.0 起支持；旧二进制不识别该字段，需跳过以免 apply 失败
mita_supports_traffic_pattern() {
  local v
  v="$(installed_version 2>/dev/null || true)"
  [ -n "$v" ] || return 1
  [ "$(printf '%s\n%s' "3.28.0" "$v" | sort -V 2>/dev/null | head -n1)" = "3.28.0" ]
}

mita_supports_low_entropy() {
  local v
  v="$(installed_version 2>/dev/null || true)"
  [ -n "$v" ] || return 1
  [ "$(printf '%s\n%s' "3.35.0" "$v" | sort -V 2>/dev/null | head -n1)" = "3.35.0" ]
}

ensure_traffic_seed() {
  [ "$(normalize_traffic_pattern "${TRAFFIC_PATTERN:-conservative}")" = "off" ] && return 0
  [ -n "$TRAFFIC_SEED" ] && return 0
  TRAFFIC_SEED="$(random_seed)"
}

# 选了流量伪装但当前 mita 过旧不支持时给出明确提示（须在二进制就绪后调用）
warn_traffic_unsupported() {
  [ "$(normalize_traffic_pattern "${TRAFFIC_PATTERN:-conservative}")" = "off" ] && return 0
  mita_supports_traffic_pattern && return 0
  warn "$(t '当前 mita 版本不支持流量伪装（需 ≥3.28.0），本次不会写入 trafficPattern；如需启用请先执行「升级」' \
    'Current mita does not support traffic obfuscation (needs >=3.28.0); trafficPattern will be skipped. Use 3) Upgrade to enable.')"
  TRAFFIC_PATTERN="off"
  LOW_ENTROPY_MODE="LOW_ENTROPY_MODE_OFF"
}

warn_low_entropy_unsupported() {
  [ "$(normalize_low_entropy_mode "${LOW_ENTROPY_MODE:-LOW_ENTROPY_MODE_OFF}" 2>/dev/null || true)" = "LOW_ENTROPY_MODE_OFF" ] && return 0
  mita_supports_low_entropy && return 0
  warn "$(t '当前 mita 版本不支持低熵模式（需要 ≥3.35.0），本次将关闭低熵；请先升级后再启用' \
    'Current mita does not support low entropy mode (needs >=3.35.0); it will be disabled. Upgrade first to enable it.')"
  LOW_ENTROPY_MODE="LOW_ENTROPY_MODE_OFF"
}

# 输出缩进后的 "trafficPattern": {...} 片段；off 或旧版 mita 时输出空
traffic_pattern_json() {
  local ind="${1:-  }"
  local level seed low_entropy_section=""
  level="$(normalize_traffic_pattern "${TRAFFIC_PATTERN:-conservative}")"
  [ "$level" = "off" ] && return 0
  mita_supports_traffic_pattern || return 0
  seed="${TRAFFIC_SEED:-0}"
  if mita_supports_low_entropy; then
    low_entropy_section="${ind}  \"lowEntropy\": { \"mode\": \"$(normalize_low_entropy_mode "${LOW_ENTROPY_MODE:-LOW_ENTROPY_MODE_OFF}")\" },
"
  fi
  if [ "$level" = "aggressive" ]; then
    cat <<EOF
${ind}"trafficPattern": {
${ind}  "seed": ${seed},
${ind}  "unlockAll": false,
${low_entropy_section}${ind}  "tcpFragment": { "enable": true, "maxSleepMs": 8 },
${ind}  "nonce": { "type": "NONCE_TYPE_PRINTABLE", "applyToAllUDPPacket": true, "minLen": 6, "maxLen": 12 },
${ind}  "padding": { "maxMiddlePaddingLen": 64, "maxEndPaddingLen": 255 }
${ind}}
EOF
  else
    cat <<EOF
${ind}"trafficPattern": {
${ind}  "seed": ${seed},
${ind}  "unlockAll": false,
${low_entropy_section}${ind}  "nonce": { "type": "NONCE_TYPE_PRINTABLE", "applyToAllUDPPacket": true, "minLen": 4, "maxLen": 8 },
${ind}  "padding": { "maxMiddlePaddingLen": 0, "maxEndPaddingLen": 128 }
${ind}}
EOF
  fi
}

write_server_config() {
  # Single-user semantic builder is retained as the golden-parity primitive;
  # production schema-v3 installs use the users.json multi-instance branch.
  if [ "${MULTI_USER_MODE:-0}" -eq 1 ] && users_state_exists && [ "$(users_count)" -gt 0 ]; then
    write_server_config_multi
    return
  fi
  local cfg bindings="" proto pp tp tp_section="" user_json password_json
  cfg="$(mktemp_file .json)"
  user_json="$(json_string "$USERNAME")"
  password_json="$(json_string "$PASSWORD")"
  while IFS= read -r pp; do
    proto="${pp%%|*}"
    local p="${pp#*|}"
    local binding
    if [ -n "$PORT" ]; then
      binding=$(cat <<EOB
    {
      "port": ${p},
      "protocol": "${proto}"
    }
EOB
)
    else
      binding=$(cat <<EOB
    {
      "portRange": "${p}",
      "protocol": "${proto}"
    }
EOB
)
    fi
    if [ -n "$bindings" ]; then
      bindings="${bindings},
${binding}"
    else
      bindings="${binding}"
    fi
  done < <(port_protocol_pairs)
  ensure_traffic_seed
  tp="$(traffic_pattern_json '  ')"
  [ -n "$tp" ] && tp_section=",
${tp}"
  cat >"$cfg" <<EOF
{
  "portBindings": [
${bindings}
  ],
  "users": [
    {
      "name": ${user_json},
      "password": ${password_json}
    }
  ],
  "loggingLevel": "INFO",
  "mtu": ${MTU}${tp_section}
}
EOF
  printf '%s' "$cfg"
}
