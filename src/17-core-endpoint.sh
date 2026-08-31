# ---------- NoBrand Common Core: state、Endpoint、firewall/service adapters ----------

nb_init_state_layout() {
  if [ "${DRY_RUN:-0}" -eq 1 ]; then
    msg "[dry-run] initialize NoBrand state: $NOBRAND_STATE_DIR"
    return 0
  fi
  ensure_manager_state_layout 1 || return 1
  mkdir -p "$NOBRAND_BACKUP_DIR" "$NOBRAND_LOCK_DIR" \
    "$MITA_MANAGER_STATE_DIR" "$MITA_USERS_BACKUP_DIR" \
    "$NOBRAND_SNELL_STATE_DIR" "$NOBRAND_HY2_STATE_DIR" \
    "$NOBRAND_VLESS_STATE_DIR" "$NOBRAND_TUIC_STATE_DIR" \
    "$NOBRAND_SSH_STATE_DIR" "$NOBRAND_SSH_KEYS_DIR" "$NOBRAND_SSH_WATCHDOG_DIR" \
    "$NOBRAND_FORWARD_STATE_DIR" \
    "$NOBRAND_CONFIG_DIR" "$NOBRAND_SNELL_CONFIG_DIR" "$NOBRAND_HY2_CONFIG_DIR" \
    "$NOBRAND_VLESS_CONFIG_DIR" "$NOBRAND_TUIC_CONFIG_DIR" "$NOBRAND_FORWARD_CONFIG_DIR" \
    "$NOBRAND_SSH_CONFIG_DIR" "$NOBRAND_SSH_AUTHORIZED_KEYS_DIR" \
    "$NOBRAND_SSH_ACCOUNT_MARKER_DIR" \
    "$NOBRAND_BIN_DIR" "$NOBRAND_SNELL_RUNTIME_DIR" "$NOBRAND_LIB_DIR" \
    || return 1
  chmod 0700 "$NOBRAND_STATE_DIR" "$NOBRAND_BACKUP_DIR" "$NOBRAND_LOCK_DIR" \
    "$MITA_MANAGER_STATE_DIR" "$MITA_USERS_BACKUP_DIR" \
    "$NOBRAND_SNELL_STATE_DIR" "$NOBRAND_HY2_STATE_DIR" \
    "$NOBRAND_VLESS_STATE_DIR" "$NOBRAND_TUIC_STATE_DIR" \
    "$NOBRAND_SSH_STATE_DIR" "$NOBRAND_SSH_KEYS_DIR" "$NOBRAND_SSH_WATCHDOG_DIR" \
    "$NOBRAND_FORWARD_STATE_DIR" \
    "$NOBRAND_SNELL_CONFIG_DIR" "$NOBRAND_HY2_CONFIG_DIR" \
    "$NOBRAND_VLESS_CONFIG_DIR" "$NOBRAND_TUIC_CONFIG_DIR" "$NOBRAND_FORWARD_CONFIG_DIR" \
    "$NOBRAND_SSH_ACCOUNT_MARKER_DIR" || return 1
  # sshd reads AuthorizedKeysFile after switching to the target identity. Keep
  # the shared and SSH config roots traversable but not listable; every other
  # protocol config directory and all secret/state directories remain 0700.
  chmod 0711 "$NOBRAND_CONFIG_DIR" "$NOBRAND_SSH_CONFIG_DIR" || return 1
  chmod 0755 "$NOBRAND_SSH_AUTHORIZED_KEYS_DIR" || return 1
  # Protocol services can run as dedicated unprivileged users (Mieru uses the
  # mita account). Runtime directories contain only managed executables/assets
  # and must remain traversable; secrets stay in the 0700 state/config roots.
  chmod 0755 "$NOBRAND_LIB_DIR" "$NOBRAND_BIN_DIR" "$NOBRAND_SNELL_RUNTIME_DIR" \
    || return 1
  nb_schema_v3_file_valid || return 1
  chmod 0600 "$NOBRAND_REGISTRY_FILE" 2>/dev/null || return 1
}

nb_atomic_install_file() {
  local source="$1" destination="$2" mode="${3:-0600}" tmp
  [ -f "$source" ] || return 1
  if [ "${DRY_RUN:-0}" -eq 1 ]; then
    msg "[dry-run] install -m ${mode} ${source} ${destination}"
    return 0
  fi
  mkdir -p "$(dirname "$destination")" || return 1
  tmp="$(mktemp "${destination}.tmp.XXXXXX")" || return 1
  if ! install -m "$mode" "$source" "$tmp" || ! mv -f "$tmp" "$destination"; then
    rm -f "$tmp"
    return 1
  fi
}

nb_normalize_endpoint_host() {
  local host="${1:-}"
  command -v python3 >/dev/null 2>&1 || {
    printf '%s' "$(printf '%s' "${host%.}" | tr '[:upper:]' '[:lower:]')"
    return 0
  }
  python3 - "$host" <<'PY'
import ipaddress
import sys
value=sys.argv[1].strip()
try:
    print(ipaddress.ip_address(value))
except ValueError:
    print(value.rstrip('.').lower())
PY
}

nb_validate_advertise_endpoint() {
  local host="${1:-}" port="${2:-}" transport="${3:-TCP}"
  transport="$(printf '%s' "$transport" | tr '[:lower:]' '[:upper:]')"
  case "$transport" in TCP|UDP|BOTH) ;; *) return 1 ;; esac
  if [ -z "$host" ] && [ -z "$port" ]; then
    return 0
  fi
  [ -n "$host" ] && [ -n "$port" ] || return 1
  valid_advertise_host "$host" || return 1
  valid_advertise_port "$port" || return 1
  [ "$transport" != BOTH ] || [ "$(normalize_uint "$port")" -le 65534 ]
}

nb_endpoint_conflict_owner() {
  local transport host port ignore_owner="${4:-}" auto_host owner row_transport listen_port advertise_host advertise_port
  local normalized expected_host effective_host effective_port
  transport="$(nb_normalize_transport "$1")" || return 1
  host="$2"
  port="$(normalize_uint "$3")" || return 1
  expected_host="$(nb_normalize_endpoint_host "$host")"
  auto_host="$(public_ip 2>/dev/null || true)"
  while IFS='|' read -r owner row_transport listen_port advertise_host advertise_port; do
    [ -n "$owner" ] || continue
    [ "$owner" = "$ignore_owner" ] && continue
    [ "$row_transport" = "$transport" ] || continue
    effective_host="${advertise_host:-$auto_host}"
    effective_port="${advertise_port:-$listen_port}"
    [ -n "$effective_host" ] || continue
    normalized="$(nb_normalize_endpoint_host "$effective_host")"
    if [ "$normalized" = "$expected_host" ] && [ "$effective_port" = "$port" ]; then
      printf '%s' "$owner"
      return 0
    fi
  done < <(nb_registry_rows)
  return 1
}

nb_require_explicit_endpoint_noninteractive() {
  [ "${YES:-0}" -eq 1 ] || return 0
  if [ "${ADVERTISE_AUTO_REQUESTED:-0}" -eq 1 ]; then
    return 0
  fi
  if [ "${ADVERTISE_CLI:-0}" -eq 1 ] && [ -n "${ADVERTISE_HOST:-}" ] && [ -n "${ADVERTISE_PORT:-}" ]; then
    return 0
  fi
  die "$(t '非交互模式必须同时提供 --advertise-host/--advertise-port，或明确使用 --advertise-auto' \
    'Non-interactive mode requires --advertise-host with --advertise-port, or explicit --advertise-auto')"
}

nb_collect_advertise_endpoint_interactive() {
  local protocol_name="$1" listen_port="$2" detected="" choice="" host="" port=""
  detected="$(public_ip 2>/dev/null || true)"
  msg ""
  t "${protocol_name} 真实监听端口: ${listen_port}" "${protocol_name} real listen port: ${listen_port}"
  if [ -n "$detected" ]; then
    t "自动检测到客户端入口建议: ${detected}:${listen_port}" \
      "Detected client entry suggestion: ${detected}:${listen_port}"
  else
    warn "$(t '未检测到公网入口；IPLC/NAT 环境请填写实际前置入口' \
      'No public entry detected; enter the actual IPLC/NAT frontend endpoint')"
  fi
  t '  1) 使用自动入口（以后查看节点时重新探测 host；端口等于真实监听）' \
    '  1) Use auto endpoint (host is detected when viewing; port equals listener)'
  t '  2) 自定义客户端入口（IPLC / NAT / DNAT）' \
    '  2) Custom client endpoint (IPLC / NAT / DNAT)'
  read_tty choice "$(t '请选择 [1-2，默认 1]: ' 'Choose [1-2, default 1]: ')" || choice=""
  case "${choice:-1}" in
    2)
      while true; do
        read_tty host "$(t "客户端入口 Host [${detected:-example.com}]: " \
          "Client entry host [${detected:-example.com}]: ")" || host=""
        host="${host:-$detected}"
        read_tty port "$(t "客户端入口 Port [${listen_port}]: " \
          "Client entry port [${listen_port}]: ")" || port=""
        port="${port:-$listen_port}"
        if nb_validate_advertise_endpoint "$host" "$port"; then
          ADVERTISE_HOST="$host"
          ADVERTISE_PORT="$(normalize_uint "$port")"
          ADVERTISE_CLI=1
          ADVERTISE_AUTO_REQUESTED=0
          return 0
        fi
        warn "$(t '入口必须是有效 IPv4/IPv6/域名与 1-65535 端口' \
          'Endpoint must be a valid IPv4/IPv6/domain and port 1-65535')"
      done
      ;;
    *)
      ADVERTISE_HOST=""
      ADVERTISE_PORT=""
      ADVERTISE_CLI=1
      ADVERTISE_AUTO_REQUESTED=1
      ;;
  esac
}

nb_effective_advertise_host() {
  local mode="${1:-auto}" host="${2:-}"
  if [ "$mode" = custom ] && [ -n "$host" ]; then
    printf '%s' "$host"
  else
    public_ip 2>/dev/null || printf 'YOUR_SERVER_IP'
  fi
}

nb_effective_advertise_port() {
  local mode="${1:-auto}" advertise_port="${2:-}" listen_port="${3:-}"
  if [ "$mode" = custom ] && [ -n "$advertise_port" ]; then
    printf '%s' "$advertise_port"
  else
    printf '%s' "$listen_port"
  fi
}

nb_endpoint_mode_from_values() {
  [ -n "${1:-}" ] && printf 'custom' || printf 'auto'
}

nb_firewall_open_pairs() {
  local pairs="$1"
  local MITA_FIREWALL_OWNED_STATE="$NOBRAND_FIREWALL_OWNED_STATE"
  local MITA_FIREWALL_COMMENT="$NOBRAND_FIREWALL_COMMENT"
  open_firewall_for_pairs "$pairs"
}

nb_firewall_close_pairs() {
  local pairs="$1"
  local MITA_FIREWALL_OWNED_STATE="$NOBRAND_FIREWALL_OWNED_STATE"
  local MITA_FIREWALL_COMMENT="$NOBRAND_FIREWALL_COMMENT"
  close_firewall_for_bindings "$pairs"
}

nb_firewall_binding_owned() {
  local transport="$1" port="$2" proto tool
  proto="$(printf '%s' "$transport" | tr '[:upper:]' '[:lower:]')"
  [ -f "$NOBRAND_FIREWALL_OWNED_STATE" ] || return 1
  while IFS='|' read -r tool row_proto row_port; do
    [ "$row_proto" = "$proto" ] && [ "$row_port" = "$port" ] && return 0
  done <"$NOBRAND_FIREWALL_OWNED_STATE"
  return 1
}

nb_service_manager() {
  service_manager
}

nb_service_is_active() {
  local systemd_unit="$1" openrc_service="$2" manager
  manager="$(nb_service_manager)"
  case "$manager" in
    systemd) systemctl is-active --quiet "$systemd_unit" 2>/dev/null ;;
    openrc) rc-service "$openrc_service" status 2>/dev/null | grep -qiE 'started|running' ;;
    *) return 1 ;;
  esac
}

nb_wait_for_listener() {
  local transport="$1" port="$2" timeout="${3:-20}" elapsed=0
  while [ "$elapsed" -lt "$timeout" ]; do
    nb_port_is_listening "$transport" "$port" && return 0
    sleep 1
    elapsed=$((elapsed + 1))
  done
  return 1
}
