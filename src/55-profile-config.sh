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


apply_profile_values() {
  local selected
  selected="$(normalize_profile "${1:-}")" || return 1
  PROFILE="$selected"
  case "$selected" in
    iplc)
      PROTOCOL=TCP
      MTU=1400
      MULTIPLEXING=MULTIPLEXING_OFF
      HANDSHAKE_MODE=HANDSHAKE_NO_WAIT
      TRAFFIC_PATTERN=off
      LOW_ENTROPY_MODE=LOW_ENTROPY_MODE_OFF
      ;;
    balanced)
      PROTOCOL=TCP
      MTU=1400
      MULTIPLEXING=MULTIPLEXING_OFF
      HANDSHAKE_MODE=HANDSHAKE_NO_WAIT
      TRAFFIC_PATTERN=conservative
      LOW_ENTROPY_MODE=LOW_ENTROPY_MODE_OFF
      ;;
    stealth)
      PROTOCOL=TCP
      MTU=1400
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
  apply_profile_values "$PROFILE" || die "$(t '非法配置预设（仅支持 iplc/balanced/stealth/custom）' \
    'Invalid profile (iplc/balanced/stealth/custom)')"
  [ "${PROTOCOL_CLI:-0}" -eq 0 ] || PROTOCOL="$cli_protocol"
  [ "${MTU_CLI:-0}" -eq 0 ] || MTU_REQUEST="$cli_mtu_request"
  [ "${MULTIPLEXING_CLI:-0}" -eq 0 ] || MULTIPLEXING="$cli_mux"
  [ "${HANDSHAKE_CLI:-0}" -eq 0 ] || HANDSHAKE_MODE="$cli_handshake"
  [ "${TRAFFIC_CLI:-0}" -eq 0 ] || TRAFFIC_PATTERN="$cli_traffic"
  [ "${LOW_ENTROPY_CLI:-0}" -eq 0 ] || LOW_ENTROPY_MODE="$cli_low"
}

choose_profile_interactive() {
  t '使用原生 TCP 默认参数；traffic-pattern 与低熵模式当前不支持。' 'Using native TCP defaults; traffic-pattern and low entropy are unsupported.'
  apply_profile_values iplc
}
