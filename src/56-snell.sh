# ---------- Snell v4/v5 multi-instance engine ----------

snell_state_path() {
  local id="${1:-}"
  [[ "$id" =~ ^s[0-9a-f]{16}$ ]] || return 1
  printf '%s/%s.json' "$NOBRAND_SNELL_STATE_DIR" "$id"
}

snell_config_path() {
  local id="${1:-}"
  [[ "$id" =~ ^s[0-9a-f]{16}$ ]] || return 1
  printf '%s/%s.conf' "$NOBRAND_SNELL_CONFIG_DIR" "$id"
}

snell_state_exists() {
  local path
  path="$(snell_state_path "$1")" || return 1
  [ -s "$path" ] && jq empty "$path" >/dev/null 2>&1
}

snell_state_field() {
  local id="$1" field="$2" path
  path="$(snell_state_path "$id")" || return 1
  snell_state_exists "$id" || return 1
  jq -r --arg field "$field" \
    'if has($field) and .[$field] != null then .[$field] else empty end' "$path"
}

snell_instance_ids() {
  local path id
  for path in "$NOBRAND_SNELL_STATE_DIR"/*.json; do
    [ -f "$path" ] || continue
    id="$(basename "$path" .json)"
    [[ "$id" =~ ^s[0-9a-f]{16}$ ]] || continue
    jq -e --arg id "$id" '.instance_id == $id and (.version == 4 or .version == 5)' \
      "$path" >/dev/null 2>&1 || continue
    printf '%s\n' "$id"
  done
}

snell_find_id_by_name() {
  local expected="${1:-}" id
  [ -n "$expected" ] || return 1
  while IFS= read -r id; do
    [ "$(snell_state_field "$id" name 2>/dev/null || true)" = "$expected" ] || continue
    printf '%s' "$id"
    return 0
  done < <(snell_instance_ids)
  return 1
}

snell_resolve_target_id() {
  local target="${1:-}" ids count major
  if [[ "$target" =~ ^s[0-9a-f]{16}$ ]] && snell_state_exists "$target"; then
    major="$(snell_state_field "$target" version 2>/dev/null || true)"
    case "$major" in 4|5) ;; *) return 1 ;; esac
    printf '%s' "$target"
    return 0
  fi
  if [ -n "$target" ]; then
    snell_find_id_by_name "$target"
    return $?
  fi
  ids="$(snell_instance_ids)"
  count="$(printf '%s\n' "$ids" | sed '/^$/d' | wc -l | tr -d '[:space:]')"
  [ "$count" -eq 1 ] || return 1
  printf '%s' "$ids"
}

snell_valid_name() {
  local value="${1:-}"
  valid_proxy_identity_part "$value" || return 1
  case "$value" in *'|'*|*$'\t'*|*$'\n'*|*$'\r'*) return 1 ;; esac
}

snell_valid_psk() {
  local value="${1:-}"
  [ "${#value}" -ge 8 ] && [ "${#value}" -le 128 ] || return 1
  [[ "$value" =~ ^[A-Za-z0-9._~+/@:=,-]+$ ]]
}

snell_generate_psk() {
  local value
  value="$(openssl rand -base64 24 2>/dev/null | tr -d '\r\n')"
  snell_valid_psk "$value" || value="$(openssl rand -hex 24 2>/dev/null || random_token)"
  snell_valid_psk "$value" || return 1
  printf '%s' "$value"
}

snell_generate_instance_id() {
  local id attempt=0
  while [ "$attempt" -lt 64 ]; do
    id="s$(openssl rand -hex 8 2>/dev/null || true)"
    [[ "$id" =~ ^s[0-9a-f]{16}$ ]] || {
      id="s$(printf '%016x' "$((RANDOM * 32768 + RANDOM))")"
    }
    if ! snell_state_exists "$id"; then
      printf '%s' "$id"
      return 0
    fi
    attempt=$((attempt + 1))
  done
  return 1
}

snell_release_status_for_version() {
  local version
  version="$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')"
  case "$version" in
    *rc*) printf RC ;;
    *beta*|v*b[0-9]*|*.*.*b[0-9]*) printf Beta ;;
    *alpha*|v*a[0-9]*|*.*.*a[0-9]*) printf Experimental ;;
    *[!0-9.v]*) printf Experimental ;;
    *) printf Stable ;;
  esac
}

snell_generate_state() {
  local output="$1" id="$2" name="$3" major="$4" psk="$5" listen_host="$6" listen_port="$7"
  local advertise_mode="$8" advertise_host="$9" advertise_port="${10}" created_at="${11:-}"
  local quic_proxy_enabled="${12:-false}"
  local runtime_version runtime_status updated_at
  case "$major" in 4|5) ;; *) return 1 ;; esac
  runtime_version="$(snell_runtime_release_version "$major" 2>/dev/null || printf unknown)"
  runtime_status="$(snell_runtime_release_status "$major" 2>/dev/null || snell_release_status_for_version "$runtime_version")"
  [ -n "$created_at" ] || created_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  updated_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  jq -n --arg id "$id" --arg name "$name" --arg version "$major" --arg psk "$psk" \
    --arg listen_host "$listen_host" --arg listen_port "$listen_port" \
    --arg advertise_mode "$advertise_mode" --arg advertise_host "$advertise_host" \
    --arg advertise_port "$advertise_port" --arg runtime_version "$runtime_version" \
    --arg runtime_status "$runtime_status" --arg created_at "$created_at" --arg updated_at "$updated_at" \
    --argjson quic_proxy_enabled "$quic_proxy_enabled" '
      {
        protocol:"snell",
        instance_id:$id,
        name:$name,
        version:($version|tonumber),
        psk:$psk,
        listen_host:$listen_host,
        listen_port:($listen_port|tonumber),
        transport:"tcp",
        advertise_mode:$advertise_mode,
        advertise_host:$advertise_host,
        advertise_port:(if $advertise_port=="" then "" else ($advertise_port|tonumber) end),
        enabled:true,
        quic_proxy_enabled:$quic_proxy_enabled,
        managed_udp:$quic_proxy_enabled,
        runtime_version:$runtime_version,
        runtime_status:$runtime_status,
        created_at:$created_at,
        updated_at:$updated_at
      }
    ' >"$output"
}

snell_config_matches_state() {
  local id="$1" state config
  state="$(snell_state_path "$id")" || return 1
  config="$(snell_config_path "$id")" || return 1
  [ -s "$state" ] && [ -s "$config" ] || return 1
  python3 - "$state" "$config" <<'PY'
import json
import sys

state=json.load(open(sys.argv[1], encoding="utf-8"))
values={}
section=""
for raw in open(sys.argv[2], encoding="utf-8"):
    line=raw.strip()
    if not line or line.startswith("#") or line.startswith(";"):
        continue
    if line.startswith("[") and line.endswith("]"):
        section=line[1:-1]
        continue
    if "=" not in line:
        raise SystemExit(1)
    key,value=(part.strip() for part in line.split("=",1))
    values[(section,key)]=value
expected="%s:%s" % (state.get("listen_host"), state.get("listen_port"))
if values.get(("snell-server","listen")) != expected:
    raise SystemExit(1)
if values.get(("snell-server","psk")) != state.get("psk"):
    raise SystemExit(1)
version=int(state.get("version"))
if version in (4,5):
    if values.get(("snell-server","ipv6")) != "false":
        raise SystemExit(1)
else:
    raise SystemExit(1)
PY
}

snell_quic_proxy_enabled() {
  local id="$1"
  [ "$(snell_state_field "$id" version 2>/dev/null || true)" = 5 ] || return 1
  [ "$(snell_state_field "$id" quic_proxy_enabled 2>/dev/null || printf false)" = true ]
}

snell_managed_udp_enabled() {
  local id="$1"
  [ "$(snell_state_field "$id" version 2>/dev/null || true)" = 5 ] || return 1
  [ "$(snell_state_field "$id" managed_udp 2>/dev/null || printf false)" = true ]
}

snell_quic_state_consistent() {
  local id="$1" quic managed
  quic="$(snell_state_field "$id" quic_proxy_enabled 2>/dev/null || printf false)"
  managed="$(snell_state_field "$id" managed_udp 2>/dev/null || printf false)"
  case "$quic:$managed" in false:false|true:true) return 0 ;; *) return 1 ;; esac
}

snell_firewall_pairs() {
  local id="$1" port
  port="$(snell_state_field "$id" listen_port)" || return 1
  printf 'TCP|%s\n' "$port"
  snell_managed_udp_enabled "$id" && printf 'UDP|%s\n' "$port"
  return 0
}

snell_install_port_available() {
  local port="$1"
  nb_port_available_for_transport "$port" TCP || return 1
  [ "${SNELL_QUIC_PROXY:-off}" != on ] || nb_port_available_for_transport "$port" UDP
}

snell_select_available_install_port() {
  local ip bounds lo hi selected attempt=0 random_value
  [ "${SNELL_QUIC_PROXY:-off}" = on ] || { nb_select_available_port TCP; return; }
  ip="$(nb_detect_local_ipv4 2>/dev/null || true)"
  if bounds="$(nb_tail_port_bounds "$ip" 2>/dev/null)"; then
    lo="${bounds%%|*}"; hi="${bounds#*|}"
    if selected="$(nb_scan_port_span "$lo" "$hi" snell_install_port_available)"; then
      printf '%s' "$selected"
      return 0
    fi
  fi
  while [ "$attempt" -lt 512 ]; do
    random_value="$(openssl rand -hex 2 2>/dev/null || true)"
    if [[ "$random_value" =~ ^[0-9a-fA-F]{4}$ ]]; then
      selected=$((1025 + 16#$random_value % (65535 - 1025 + 1)))
    else
      selected=$((1025 + RANDOM % (65535 - 1025 + 1)))
    fi
    snell_install_port_available "$selected" && { printf '%s' "$selected"; return 0; }
    attempt=$((attempt + 1))
  done
  return 1
}

snell_effective_endpoint() {
  local id="$1" mode host advertise_port listen_port effective_host effective_port
  mode="$(snell_state_field "$id" advertise_mode)"
  host="$(snell_state_field "$id" advertise_host)"
  advertise_port="$(snell_state_field "$id" advertise_port)"
  listen_port="$(snell_state_field "$id" listen_port)"
  effective_host="$(nb_effective_advertise_host "$mode" "$host")"
  effective_port="$(nb_effective_advertise_port "$mode" "$advertise_port" "$listen_port")"
  printf '%s|%s' "$effective_host" "$effective_port"
}

snell_state_set_enabled() {
  local id="$1" enabled="$2" path tmp
  path="$(snell_state_path "$id")" || return 1
  tmp="$(mktemp_file .json)" || return 1
  if ! jq --argjson enabled "$enabled" --arg updated "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      '.enabled=$enabled | .updated_at=$updated' "$path" >"$tmp" \
     || ! nb_atomic_install_file "$tmp" "$path" 0600; then
    rm -f "$tmp"
    return 1
  fi
  rm -f "$tmp"
}

snell_collect_install_requests() {
  local interactive="$1" detected="" owner quic_choice=""
  case "${SNELL_VERSION:-5}" in 4|5) ;; *) die 'Snell 只支持 v4、v5' ;; esac
  snell_platform_supported "$SNELL_VERSION" \
    || die "当前 OS/arch 不支持官方 Snell v${SNELL_VERSION} runtime"
  if [ -z "${SNELL_NAME:-}" ]; then
    if [ "$interactive" -eq 1 ]; then
      read_tty SNELL_NAME "$(t "节点名 [snell-v${SNELL_VERSION}]: " "Node name [snell-v${SNELL_VERSION}]: ")" || SNELL_NAME=""
    fi
    SNELL_NAME="${SNELL_NAME:-snell-v${SNELL_VERSION}}"
  fi
  snell_valid_name "$SNELL_NAME" || die 'Snell 节点名无效（1-64 字符且不能含控制字符或 |）'
  [ -z "$(snell_find_id_by_name "$SNELL_NAME" 2>/dev/null || true)" ] || die "Snell 节点名已存在: $SNELL_NAME"
  if [ -z "${PORT:-}" ]; then
    PORT="$(nb_select_available_port TCP)" || die '未找到可用 Snell TCP 端口'
    PORT_AUTO_SELECTED=1
  else
    nb_valid_port "$PORT" || die 'Snell 端口必须是 1-65535'
    PORT="$(normalize_uint "$PORT")"
    nb_warn_if_outside_recommended_range "$PORT"
    if ! nb_port_available_for_transport "$PORT" TCP; then
      warn "Snell TCP/${PORT} 已占用"
      nb_describe_port_conflict TCP "$PORT"
      return 1
    fi
  fi
  if [ -z "${SNELL_PSK:-}" ]; then
    SNELL_PSK="$(snell_generate_psk)" || die '无法生成 Snell PSK'
  fi
  snell_valid_psk "$SNELL_PSK" \
    || die 'Snell PSK 必须为 8-128 位安全 ASCII（字母、数字或 ._~+/@:=,-）'
  if [ "$SNELL_VERSION" = 5 ]; then
    if [ "$interactive" -eq 1 ] && [ "${SNELL_QUIC_CLI:-0}" -eq 0 ]; then
      msg ''
      msg '是否启用 Snell v5 QUIC Proxy Mode？'
      msg '  1) 否 [默认 / 推荐兼容]'
      msg '  2) 是 [同时开放 UDP，同端口]'
      read_tty quic_choice "$(t '请选择 [1]: ' 'Choose [1]: ')" || quic_choice=""
      case "$quic_choice" in
        ""|1) SNELL_QUIC_PROXY=off ;;
        2) SNELL_QUIC_PROXY=on ;;
        *) die 'QUIC Proxy Mode 选择无效' ;;
      esac
    else
      SNELL_QUIC_PROXY="${SNELL_QUIC_PROXY:-off}"
    fi
  else
    [ "${SNELL_QUIC_PROXY:-off}" != on ] || die 'Snell v4 不支持 QUIC Proxy Mode'
    SNELL_QUIC_PROXY=off
  fi
  case "$SNELL_QUIC_PROXY" in on|off) ;; *) die 'QUIC Proxy Mode 只支持 on 或 off' ;; esac
  if [ "$SNELL_QUIC_PROXY" = on ] && ! nb_port_available_for_transport "$PORT" UDP; then
    if [ "${PORT_AUTO_SELECTED:-0}" -eq 1 ]; then
      PORT="$(snell_select_available_install_port)" || die '未找到同时可用的 Snell v5 TCP/UDP 同号端口'
    else
      warn "Snell v5 QUIC 需要同号 UDP/${PORT}，但该端口已占用"
      nb_describe_port_conflict UDP "$PORT"
      return 1
    fi
  fi
  detected="$(public_ip 2>/dev/null || true)"
  if [ "$interactive" -eq 1 ] && [ "${ADVERTISE_CLI:-0}" -eq 0 ]; then
    nb_collect_advertise_endpoint_interactive "Snell v${SNELL_VERSION}" "$PORT"
  else
    nb_require_explicit_endpoint_noninteractive
  fi
  nb_validate_advertise_endpoint "$ADVERTISE_HOST" "$ADVERTISE_PORT" TCP \
    || die 'Snell Display Endpoint 无效'
  if [ -n "$ADVERTISE_HOST" ]; then
    owner="$(nb_endpoint_conflict_owner TCP "$ADVERTISE_HOST" "$ADVERTISE_PORT" '' 2>/dev/null || true)"
    [ -z "$owner" ] || die "Snell Display Endpoint 与 ${owner} 冲突"
    if [ "$SNELL_QUIC_PROXY" = on ]; then
      owner="$(nb_endpoint_conflict_owner UDP "$ADVERTISE_HOST" "$ADVERTISE_PORT" '' 2>/dev/null || true)"
      [ -z "$owner" ] || die "Snell QUIC Display Endpoint 与 ${owner} 冲突"
    fi
  fi
  [ -z "$detected" ] || :
}

snell_install_rollback() {
  local id="$1" close_pairs="${2:-}"
  snell_remove_service "$id" >/dev/null 2>&1 || true
  [ -z "$close_pairs" ] || nb_firewall_close_pairs "$close_pairs" >/dev/null 2>&1 || true
  rm -f "$(snell_state_path "$id" 2>/dev/null || true)" \
    "$(snell_config_path "$id" 2>/dev/null || true)"
}

install_snell() {
  local interactive=0 id config_tmp state_tmp mode firewall_pairs new_pairs=""
  local tcp_was_owned=0 udp_was_owned=0
  [ "${YES:-0}" -eq 1 ] || interactive=1
  nobrand_prepare_common
  snell_collect_install_requests "$interactive"
  snell_install_runtime "$SNELL_VERSION" 0 || return 1
  admin_lock_acquire || return 1
  id="$(snell_generate_instance_id)" || { admin_lock_release; return 1; }
  if ! snell_install_port_available "$PORT"; then
    warn "提交前发现 TCP/${PORT} 已被其它实例或进程占用"
    nb_describe_port_conflict TCP "$PORT"
    admin_lock_release
    return 1
  fi
  config_tmp="$(mktemp_file .conf)" || { admin_lock_release; return 1; }
  state_tmp="$(mktemp_file .json)" || { rm -f "$config_tmp"; admin_lock_release; return 1; }
  mode="$(nb_endpoint_mode_from_values "$ADVERTISE_HOST")"
  firewall_pairs="TCP|${PORT}"
  [ "$SNELL_QUIC_PROXY" != on ] || firewall_pairs="${firewall_pairs}"$'\n'"UDP|${PORT}"
  if ! snell_generate_server_config "$config_tmp" "$SNELL_VERSION" 0.0.0.0 "$PORT" "$SNELL_PSK" \
     || ! snell_generate_state "$state_tmp" "$id" "$SNELL_NAME" "$SNELL_VERSION" "$SNELL_PSK" \
          0.0.0.0 "$PORT" "$mode" "$ADVERTISE_HOST" "$ADVERTISE_PORT" "" \
          "$([ "$SNELL_QUIC_PROXY" = on ] && printf true || printf false)" \
     || ! snell_config_matches_state_files "$state_tmp" "$config_tmp"; then
    rm -f "$config_tmp" "$state_tmp"
    admin_lock_release
    return 1
  fi
  nb_firewall_binding_owned TCP "$PORT" && tcp_was_owned=1
  nb_firewall_binding_owned UDP "$PORT" && udp_was_owned=1
  if ! nb_atomic_install_file "$config_tmp" "$(snell_config_path "$id")" 0600 \
     || ! nb_atomic_install_file "$state_tmp" "$(snell_state_path "$id")" 0600 \
     || ! snell_install_service_runtime \
     || ! snell_ensure_openrc_service "$id" \
     || ! nb_firewall_open_pairs "$firewall_pairs"; then
    rm -f "$config_tmp" "$state_tmp"
    nb_firewall_binding_owned TCP "$PORT" && [ "$tcp_was_owned" -eq 0 ] \
      && new_pairs="TCP|${PORT}"
    nb_firewall_binding_owned UDP "$PORT" && [ "$udp_was_owned" -eq 0 ] \
      && new_pairs="${new_pairs}${new_pairs:+$'\n'}UDP|${PORT}"
    snell_install_rollback "$id" "$new_pairs"
    admin_lock_release
    return 1
  fi
  rm -f "$config_tmp" "$state_tmp"
  nb_firewall_binding_owned TCP "$PORT" && [ "$tcp_was_owned" -eq 0 ] \
    && new_pairs="TCP|${PORT}"
  nb_firewall_binding_owned UDP "$PORT" && [ "$udp_was_owned" -eq 0 ] \
    && new_pairs="${new_pairs}${new_pairs:+$'\n'}UDP|${PORT}"
  if ! snell_service_action "$id" start \
     || ! snell_service_active "$id" \
     || ! nb_wait_for_listener TCP "$PORT" 25 \
     || ! { [ "$SNELL_QUIC_PROXY" != on ] || snell_wait_for_quic_listener "$PORT" 25; }; then
    snell_install_rollback "$id" "$new_pairs"
    admin_lock_release
    warn "Snell v${SNELL_VERSION} 启动或 TCP listener 验收失败，已回滚"
    return 1
  fi
  nobrand_install_manager_script || true
  admin_lock_release
  snell_print_result "$id" install
}

# 与 snell_config_matches_state 相同，但用于尚未提交的事务文件。
snell_config_matches_state_files() {
  local state="$1" config="$2"
  python3 - "$state" "$config" <<'PY'
import json
import sys
state=json.load(open(sys.argv[1], encoding="utf-8"))
values={}
section=""
for raw in open(sys.argv[2], encoding="utf-8"):
    line=raw.strip()
    if not line or line.startswith(("#",";")):
        continue
    if line.startswith("[") and line.endswith("]"):
        section=line[1:-1]
    elif "=" in line:
        key,value=(x.strip() for x in line.split("=",1))
        values[(section,key)]=value
    else:
        raise SystemExit(1)
if values.get(("snell-server","listen")) != "%s:%s" % (state["listen_host"],state["listen_port"]):
    raise SystemExit(1)
if values.get(("snell-server","psk")) != state["psk"]:
    raise SystemExit(1)
if state["version"] in (4,5) and values.get(("snell-server","ipv6")) != "false":
    raise SystemExit(1)
PY
}

snell_set_endpoint() {
  local id interactive=0 owner path tmp mode
  require_root
  id="$(snell_resolve_target_id "${SNELL_NAME:-}")" \
    || die '请用 --name 指定唯一存在的 Snell 节点'
  [ "${YES:-0}" -eq 1 ] || interactive=1
  PORT="$(snell_state_field "$id" listen_port)"
  if [ "$interactive" -eq 1 ] && [ "${ADVERTISE_CLI:-0}" -eq 0 ]; then
    nb_collect_advertise_endpoint_interactive "Snell $(snell_state_field "$id" name)" "$PORT"
  else
    nb_require_explicit_endpoint_noninteractive
  fi
  nb_validate_advertise_endpoint "$ADVERTISE_HOST" "$ADVERTISE_PORT" TCP || die 'Display Endpoint 无效'
  if [ -n "$ADVERTISE_HOST" ]; then
    owner="$(nb_endpoint_conflict_owner TCP "$ADVERTISE_HOST" "$ADVERTISE_PORT" "snell:${id}" 2>/dev/null || true)"
    [ -z "$owner" ] || die "Display Endpoint 与 ${owner} 冲突"
    if snell_managed_udp_enabled "$id"; then
      owner="$(nb_endpoint_conflict_owner UDP "$ADVERTISE_HOST" "$ADVERTISE_PORT" "snell:${id}" 2>/dev/null || true)"
      [ -z "$owner" ] || die "QUIC Display Endpoint 与 ${owner} 冲突"
    fi
  fi
  admin_lock_acquire || return 1
  path="$(snell_state_path "$id")"
  tmp="$(mktemp_file .json)" || { admin_lock_release; return 1; }
  mode="$(nb_endpoint_mode_from_values "$ADVERTISE_HOST")"
  if ! jq --arg mode "$mode" --arg host "$ADVERTISE_HOST" --arg port "$ADVERTISE_PORT" \
      --arg updated "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
        .advertise_mode=$mode |
        .advertise_host=$host |
        .advertise_port=(if $port=="" then "" else ($port|tonumber) end) |
        .updated_at=$updated
      ' "$path" >"$tmp" \
     || ! nb_atomic_install_file "$tmp" "$path" 0600; then
    rm -f "$tmp"
    admin_lock_release
    return 1
  fi
  rm -f "$tmp"
  # Display Endpoint 红线：不触碰 config、unit、listener、firewall、tc 或 quota。
  admin_lock_release
  t 'Snell 客户端展示入口已更新；server config/listener/service/firewall 均未改变' \
    'Snell display endpoint updated; server config/listener/service/firewall are unchanged'
  snell_print_result "$id" show
}

snell_state_set_quic() {
  local id="$1" enabled="$2" path tmp
  path="$(snell_state_path "$id")" || return 1
  tmp="$(mktemp_file .json)" || return 1
  if ! jq --argjson enabled "$enabled" --arg updated "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
      .quic_proxy_enabled=$enabled |
      .managed_udp=$enabled |
      .updated_at=$updated
    ' "$path" >"$tmp" \
     || ! nb_atomic_install_file "$tmp" "$path" 0600; then
    rm -f "$tmp"
    return 1
  fi
  rm -f "$tmp"
}

snell_set_quic() {
  local id port desired current udp_was_owned=0 state_consistent=0
  require_root
  id="$(snell_resolve_target_id "${SNELL_NAME:-}")" \
    || die '请用 --name 指定唯一存在的 Snell v5 节点'
  [ "$(snell_state_field "$id" version)" = 5 ] || die 'QUIC Proxy Mode 只适用于 Snell v5'
  desired="${SNELL_QUIC_PROXY:-}"
  if [ -z "$desired" ] && [ "${YES:-0}" -ne 1 ]; then
    read_tty desired "$(t 'QUIC Proxy Mode [on/off]: ' 'QUIC Proxy Mode [on/off]: ')" || desired=""
  fi
  case "$desired" in on|off) ;; *) die '请用 --quic on 或 --quic off 明确选择' ;; esac
  current=off; snell_quic_proxy_enabled "$id" && current=on
  snell_quic_state_consistent "$id" && state_consistent=1
  if [ "$current" = "$desired" ] && [ "$state_consistent" -eq 1 ]; then
    t "Snell v5 QUIC Proxy Mode 已是 ${desired}" "Snell v5 QUIC Proxy Mode is already ${desired}"
    return 0
  fi
  port="$(snell_state_field "$id" listen_port)"
  admin_lock_acquire || return 1
  if [ "$desired" = on ]; then
    if snell_service_active "$id" \
       && ! snell_v5_auxiliary_udp_same_process "$port"; then
      admin_lock_release
      die "Snell v5 同进程 UDP/${port} listener 未通过验收，拒绝开放 QUIC"
    fi
    if ! snell_service_active "$id" \
       && ! nb_port_available_for_transport "$port" UDP; then
      admin_lock_release
      warn "Snell v5 QUIC 需要同号 UDP/${port}，但该端口已占用"
      nb_describe_port_conflict UDP "$port"
      return 1
    fi
    nb_firewall_binding_owned UDP "$port" && udp_was_owned=1
    if ! nb_firewall_open_pairs "UDP|${port}" \
       || ! snell_state_set_quic "$id" true; then
      [ "$udp_was_owned" -eq 1 ] || nb_firewall_close_pairs "UDP|${port}" >/dev/null 2>&1 || true
      admin_lock_release
      return 1
    fi
  else
    if ! nb_firewall_close_pairs "UDP|${port}" \
       || ! snell_state_set_quic "$id" false; then
      nb_firewall_open_pairs "UDP|${port}" >/dev/null 2>&1 || true
      admin_lock_release
      return 1
    fi
  fi
  admin_lock_release
  t "Snell v5 QUIC Proxy Mode: ${desired}；server config/service/PSK 未改变" \
    "Snell v5 QUIC Proxy Mode: ${desired}; server config/service/PSK unchanged"
  snell_print_result "$id" show
}

snell_running() {
  local id="$1" port
  snell_state_exists "$id" || return 1
  port="$(snell_state_field "$id" listen_port)"
  snell_service_active "$id" && nb_port_is_listening TCP "$port"
}

snell_v5_auxiliary_udp_same_process() {
  local port="$1" tcp_pids udp_pids tcp_pid udp_pid
  tcp_pids="$(nb_port_listener_pids TCP "$port")"
  udp_pids="$(nb_port_listener_pids UDP "$port")"
  [ -n "$tcp_pids" ] && [ -n "$udp_pids" ] || return 1
  for udp_pid in $udp_pids; do
    for tcp_pid in $tcp_pids; do
      [ "$udp_pid" != "$tcp_pid" ] || return 0
    done
  done
  return 1
}

snell_wait_for_quic_listener() {
  local port="$1" timeout="${2:-25}" elapsed=0
  while [ "$elapsed" -lt "$timeout" ]; do
    snell_v5_auxiliary_udp_same_process "$port" && return 0
    sleep 1
    elapsed=$((elapsed + 1))
  done
  return 1
}

snell_wait_for_required_listeners() {
  local id="$1" timeout="${2:-25}" port
  port="$(snell_state_field "$id" listen_port)" || return 1
  nb_wait_for_listener TCP "$port" "$timeout" || return 1
  snell_quic_proxy_enabled "$id" || return 0
  snell_wait_for_quic_listener "$port" "$timeout"
}

snell_node_rows() {
  local id name major endpoint host port status quic endpoint_text transport
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    name="$(snell_state_field "$id" name)"
    major="$(snell_state_field "$id" version)"
    endpoint="$(snell_effective_endpoint "$id")"
    host="${endpoint%%|*}"; port="${endpoint#*|}"
    status=Stopped; snell_running "$id" && status=Running
    quic=off; snell_quic_proxy_enabled "$id" && quic=on
    endpoint_text="$(url_host "$host"):${port}/TCP; QUIC Off"
    transport=TCP
    if [ "$quic" = on ]; then
      endpoint_text="$(url_host "$host"):${port}/TCP; QUIC On (UDP same port)"
      transport=TCP+UDP
    fi
    printf 'Snell/v%s|%s|%s|%s|%s\n' "$major" "$name" "$endpoint_text" "$status" "$transport"
  done < <(snell_instance_ids)
}

snell_print_result() {
  local id="$1" context="${2:-show}" name major psk listen_host listen_port endpoint host port status runtime quic
  snell_state_exists "$id" || { t 'Snell 节点不存在' 'Snell node does not exist'; return 1; }
  name="$(snell_state_field "$id" name)"; major="$(snell_state_field "$id" version)"
  psk="$(snell_state_field "$id" psk)"; listen_host="$(snell_state_field "$id" listen_host)"
  listen_port="$(snell_state_field "$id" listen_port)"; runtime="$(snell_state_field "$id" runtime_version)"
  endpoint="$(snell_effective_endpoint "$id")"; host="${endpoint%%|*}"; port="${endpoint#*|}"
  status=Stopped; snell_running "$id" && status=Running
  quic=Disabled; snell_quic_proxy_enabled "$id" && quic=Enabled
  nobrand_print_banner
  msg "$([ "$context" = install ] && printf '部署完成' || printf '节点配置')"
  msg ''
  printf '协议        Snell v%s\n节点        %s\nInstance    %s\n状态        %s\nRuntime     %s\n' \
    "$major" "$name" "$id" "$status" "$runtime"
  msg ''
  printf '真实监听\n  Address   %s\n  Port      %s\n  Transport TCP\n' "$listen_host" "$listen_port"
  printf '  QUIC Proxy %s\n' "$quic"
  [ "$quic" != Enabled ] || printf '  QUIC Transport UDP/%s (same port)\n' "$listen_port"
  msg ''
  printf '客户端入口\n  Host      %s\n  Port      %s\n' "$host" "$port"
  msg ''
  printf '认证\n  PSK       %s\n' "$psk"
  msg ''
  snell_print_client_exports "$id"
}

snell_show() {
  local id found=0
  if [ -n "${SNELL_NAME:-}" ]; then
    id="$(snell_resolve_target_id "$SNELL_NAME")" || die "Snell 节点不存在: $SNELL_NAME"
    snell_print_result "$id" show
    return
  fi
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    [ "$found" -eq 0 ] || msg ''
    snell_print_result "$id" show
    found=1
  done < <(snell_instance_ids)
  [ "$found" -eq 1 ] || t 'Snell 未安装任何节点' 'No Snell nodes are installed'
}

snell_service_command() {
  local action="$1" id port was_enabled firewall_pairs
  id="$(snell_resolve_target_id "${SNELL_NAME:-}")" || die '请用 --name 指定唯一存在的 Snell 节点'
  port="$(snell_state_field "$id" listen_port)"
  was_enabled="$(snell_state_field "$id" enabled)"
  firewall_pairs="$(snell_firewall_pairs "$id")"
  case "$action" in
    start)
      nb_firewall_open_pairs "$firewall_pairs" || return 1
      if ! snell_service_action "$id" start || ! snell_wait_for_required_listeners "$id" 25 \
         || ! snell_state_set_enabled "$id" true; then
        snell_service_action "$id" stop >/dev/null 2>&1 || true
        [ "$was_enabled" = true ] || snell_state_set_enabled "$id" false >/dev/null 2>&1 || true
        return 1
      fi
      ;;
    stop)
      snell_service_action "$id" stop || return 1
      if ! snell_state_set_enabled "$id" false; then
        [ "$was_enabled" != true ] || snell_service_action "$id" start >/dev/null 2>&1 || true
        return 1
      fi
      ;;
    restart)
      snell_service_action "$id" restart && snell_wait_for_required_listeners "$id" 25
      ;;
    status)
      if snell_running "$id"; then msg "Snell $(snell_state_field "$id" name): Running"; else msg "Snell $(snell_state_field "$id" name): Stopped"; return 1; fi
      ;;
  esac
}

remove_snell_instance() {
  local id firewall_pairs
  require_root
  id="$(snell_resolve_target_id "${SNELL_NAME:-}")" || die '请用 --name 指定唯一存在的 Snell 节点'
  firewall_pairs="$(snell_firewall_pairs "$id")"
  admin_lock_acquire || return 1
  snell_remove_service "$id" || { admin_lock_release; return 1; }
  nb_firewall_close_pairs "$firewall_pairs" || { admin_lock_release; return 1; }
  rm -f "$(snell_config_path "$id")" "$(snell_state_path "$id")"
  admin_lock_release
  t "Snell 节点已删除: ${SNELL_NAME:-$id}" "Snell node removed: ${SNELL_NAME:-$id}"
}

snell_doctor_instance() {
  local id="$1" failed=0 name major port endpoint host advertise_port mode runtime actual_runtime quic
  snell_state_exists "$id" || return 1
  case "$(snell_state_field "$id" version 2>/dev/null || true)" in 4|5) ;; *) return 1 ;; esac
  name="$(snell_state_field "$id" name)"; major="$(snell_state_field "$id" version)"
  port="$(snell_state_field "$id" listen_port)"; runtime="$(snell_state_field "$id" runtime_version)"
  printf 'Instance %s (%s, v%s)\n' "$name" "$id" "$major"
  if [ -x "$(snell_runtime_path "$major")" ]; then
    actual_runtime="$(snell_runtime_reported_version "$(snell_runtime_path "$major")" 2>/dev/null || true)"
    [[ "$actual_runtime" = "$major".* ]] \
      && nb_doctor_line PASS "official runtime v${actual_runtime}" \
      || { nb_doctor_line FAIL "runtime major mismatch: ${actual_runtime:-unknown}"; failed=1; }
    [ "$actual_runtime" = "$runtime" ] || nb_doctor_line INFO "state runtime=${runtime}, installed=${actual_runtime}"
  else
    nb_doctor_line FAIL "runtime missing: $(snell_runtime_path "$major")"; failed=1
  fi
  snell_config_matches_state "$id" && nb_doctor_line PASS 'config/state consistency' \
    || { nb_doctor_line FAIL 'config/state consistency'; failed=1; }
  snell_quic_state_consistent "$id" \
    && nb_doctor_line PASS 'QUIC state/managed UDP consistency' \
    || { nb_doctor_line FAIL 'QUIC state/managed UDP consistency'; failed=1; }
  snell_running "$id" && nb_doctor_line PASS "service + TCP/${port}" \
    || { nb_doctor_line FAIL "service/listener TCP/${port}"; failed=1; }
  quic=off; snell_quic_proxy_enabled "$id" && quic=on
  if [ "$major" = 5 ] && [ "$quic" = on ]; then
    snell_v5_auxiliary_udp_same_process "$port" \
      && nb_doctor_line PASS "QUIC Proxy Enabled; same-process UDP/${port} listener" \
      || { nb_doctor_line FAIL "QUIC Proxy Enabled but same-process UDP/${port} listener missing"; failed=1; }
    nb_firewall_binding_owned UDP "$port" \
      && nb_doctor_line PASS "QUIC firewall ownership UDP/${port}" \
      || { nb_doctor_line FAIL "QUIC Proxy Enabled but UDP/${port} firewall ownership missing"; failed=1; }
  elif [ "$major" = 5 ]; then
    nb_doctor_line PASS 'QUIC Proxy Disabled; UDP public ownership OFF'
    if nb_firewall_binding_owned UDP "$port"; then
      nb_doctor_line FAIL "QUIC Proxy Disabled but UDP/${port} is still NoBrand-owned"
      failed=1
    elif nb_port_is_listening UDP "$port"; then
      if snell_v5_auxiliary_udp_same_process "$port"; then
        nb_doctor_line INFO \
          "runtime auxiliary listener UDP/${port} detected; owner=snell-server; public ownership=OFF; canonical ownership=TCP/${port}"
      else
        nb_doctor_line WARN \
          "same-port UDP/${port} listener detected, but ownership could not be matched to the primary Snell process"
      fi
    fi
  fi
  nb_firewall_binding_owned TCP "$port" && nb_doctor_line PASS "firewall ownership TCP/${port}" \
    || nb_doctor_line INFO "firewall rule not owned (pre-existing/no local firewall): TCP/${port}"
  mode="$(snell_state_field "$id" advertise_mode)"; host="$(snell_state_field "$id" advertise_host)"
  advertise_port="$(snell_state_field "$id" advertise_port)"
  nb_validate_advertise_endpoint "$host" "$advertise_port" TCP \
    && nb_doctor_line PASS "display endpoint mode=${mode}" \
    || { nb_doctor_line FAIL 'display endpoint state'; failed=1; }
  endpoint="$(snell_effective_endpoint "$id" 2>/dev/null || true)"
  [ -n "$endpoint" ] || { nb_doctor_line FAIL 'effective endpoint'; failed=1; }
  return "$failed"
}

snell_doctor_all() {
  local id found=0 failed=0
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    snell_doctor_instance "$id" || failed=1
    found=1
  done < <(snell_instance_ids)
  [ "$found" -eq 1 ] || nb_doctor_line INFO 'not installed'
  return "$failed"
}

snell_upgrade_runtime() {
  local major id ids backup="" metadata_backup="" runtime metadata active_ids="" failed=0 port
  nobrand_prepare_common
  if [ -n "${SNELL_NAME:-}" ]; then
    id="$(snell_resolve_target_id "$SNELL_NAME")" || die "Snell 节点不存在: $SNELL_NAME"
    major="$(snell_state_field "$id" version)"
  elif [ "${SNELL_VERSION_CLI:-0}" -eq 1 ]; then
    major="${SNELL_VERSION:-5}"
  else
    major=5
  fi
  case "$major" in 4|5) ;; *) die 'Snell 只支持 v4、v5' ;; esac
  runtime="$(snell_runtime_path "$major")"
  metadata="$(snell_runtime_metadata_path "$major")"
  if [ -e "$runtime" ]; then
    backup="$(mktemp_file .snell-runtime)" || return 1
    cp -a "$runtime" "$backup" || { rm -f "$backup"; return 1; }
  fi
  if [ -e "$metadata" ]; then
    metadata_backup="$(mktemp_file .snell-metadata)" || { rm -f "$backup"; return 1; }
    cp -a "$metadata" "$metadata_backup" || { rm -f "$backup" "$metadata_backup"; return 1; }
  fi
  while IFS= read -r id; do
    [ "$(snell_state_field "$id" version)" = "$major" ] || continue
    snell_service_active "$id" && active_ids="${active_ids}${id}"$'\n'
  done < <(snell_instance_ids)
  admin_lock_acquire || { rm -f "$backup"; return 1; }
  if ! snell_install_runtime "$major" 1; then
    rm -f "$backup"
    admin_lock_release
    return 1
  fi
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    port="$(snell_state_field "$id" listen_port)"
    snell_service_action "$id" restart >/dev/null 2>&1 \
      && snell_wait_for_required_listeners "$id" 25 || { failed=1; break; }
  done <<<"$active_ids"
  if [ "$failed" -eq 1 ]; then
    [ -n "$backup" ] && install -m 0755 "$backup" "$runtime"
    if [ -n "$metadata_backup" ]; then
      install -m 0600 "$metadata_backup" "$metadata"
    else
      rm -f "$metadata"
    fi
    while IFS= read -r id; do [ -z "$id" ] || snell_service_action "$id" restart >/dev/null 2>&1 || true; done <<<"$active_ids"
    rm -f "$backup" "$metadata_backup"
    admin_lock_release
    warn "Snell v${major} 升级后实例验收失败，已恢复旧 runtime"
    return 1
  fi
  ids="$(snell_instance_ids)"
  while IFS= read -r id; do
    [ "$(snell_state_field "$id" version 2>/dev/null || true)" = "$major" ] || continue
    snell_refresh_runtime_metadata "$id" || true
  done <<<"$ids"
  rm -f "$backup" "$metadata_backup"
  admin_lock_release
  t "Snell v${major} runtime 升级完成" "Snell v${major} runtime upgraded"
}

snell_refresh_runtime_metadata() {
  local id="$1" path tmp major runtime status
  path="$(snell_state_path "$id")"; major="$(snell_state_field "$id" version)"
  runtime="$(snell_runtime_release_version "$major")" || return 1
  status="$(snell_runtime_release_status "$major")"
  tmp="$(mktemp_file .json)" || return 1
  jq --arg runtime "$runtime" --arg status "$status" --arg updated "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '.runtime_version=$runtime | .runtime_status=$status | .updated_at=$updated' "$path" >"$tmp" \
    && nb_atomic_install_file "$tmp" "$path" 0600
  local rc=$?
  rm -f "$tmp"
  return "$rc"
}

nobrand_run_snell_action() {
  case "${SNELL_ACTION:-menu}" in
    menu) snell_menu_loop ;;
    install) install_snell ;;
    show) snell_show ;;
    set-endpoint) snell_set_endpoint ;;
    set-quic) snell_set_quic ;;
    remove) remove_snell_instance ;;
    start|stop|restart|status) snell_service_command "$SNELL_ACTION" ;;
    doctor) snell_doctor_all ;;
    upgrade) snell_upgrade_runtime ;;
    help) nobrand_usage ;;
  esac
}
