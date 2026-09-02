urlencode() {
  local value="$1"
  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$value"
    return 0
  fi
  if [[ "$value" =~ ^[a-zA-Z0-9._~-]+$ ]]; then
    printf '%s' "$value"
    return 0
  fi
  die "$(t '密码含特殊字符时需要 python3 以生成节点链接' \
    'python3 required to encode special characters in share link')"
}

url_host() {
  local host="$1"
  if [[ "$host" == *:* ]] && [[ "$host" != \[*\] ]]; then
    printf '[%s]' "$host"
  else
    printf '%s' "$host"
  fi
}

export_traffic_pattern_value() {
  local bin value="" iid
  if [ "${TRAFFIC_PATTERN_EXPORT_READY:-0}" -eq 1 ]; then
    printf '%s' "${TRAFFIC_PATTERN_EXPORT_CACHE:-}"
    return 0
  fi
  [ "$(normalize_traffic_pattern "${TRAFFIC_PATTERN:-conservative}")" != "off" ] || return 0
  mita_supports_traffic_pattern || return 0
  bin="$(mita_bin)"
  [ -x "$bin" ] || return 0
  if users_isolated_mode && [ -n "${USERNAME:-}" ]; then
    iid="$(users_get_field "$USERNAME" instance_id 2>/dev/null || true)"
    if instance_valid_id "$iid"; then
      value="$(instance_cmd "$iid" export traffic-pattern 2>/dev/null | tr -d '\r\n' || true)"
    fi
  fi
  case "$value" in
    ''|*[!A-Za-z0-9+/=]*) return 0 ;;
  esac
  printf '%s' "$value"
}

prepare_traffic_pattern_export() {
  TRAFFIC_PATTERN_EXPORT_READY=0
  TRAFFIC_PATTERN_EXPORT_CACHE="$(export_traffic_pattern_value)"
  TRAFFIC_PATTERN_EXPORT_READY=1
}

generate_share_link_for() {
  local ip="$1"
  local proto="$2"
  local enc_user enc_pass p host query tp enc_tp=""
  enc_user="$(urlencode "$USERNAME")"
  enc_pass="$(urlencode "$PASSWORD")"
  p="$(advertised_port_for_protocol "$proto")"
  # 官方 simple URL 始终要求 port/protocol 在 query 中成对出现。
  # profile=default 是上游客户端的 profileName，不是 OneClick UI 的参数预设 PROFILE。
  host="$(url_host "$ip")"
  tp="$(export_traffic_pattern_value)"
  [ -n "$tp" ] && enc_tp="&traffic-pattern=$(urlencode "$tp")"
  query="handshake-mode=${HANDSHAKE_MODE}&mtu=${MTU}&multiplexing=${MULTIPLEXING}&port=$(urlencode "$p")&profile=default&protocol=${proto}${enc_tp}"
  printf 'mierus://%s:%s@%s?%s' "$enc_user" "$enc_pass" "$host" "$query"
}

build_client_json_for() {
  local ip="$1"
  local proto="$2"
  local p binding tp tp_section="" user_json password_json ip_json domain_json
  p="$(advertised_port_for_protocol "$proto")"
  user_json="$(json_string "$USERNAME")"
  password_json="$(json_string "$PASSWORD")"
  if valid_ip_literal "$ip"; then
    ip_json="$(json_string "$ip")"
    domain_json='""'
  else
    ip_json='""'
    domain_json="$(json_string "$ip")"
  fi
  ensure_traffic_seed
  tp="$(traffic_pattern_json '      ')"
  [ -n "$tp" ] && tp_section=",
${tp}"
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
  cat <<EOF
{
  "profiles": [
    {
      "profileName": "default",
      "user": {
        "name": ${user_json},
        "password": ${password_json}
      },
      "servers": [
        {
          "ipAddress": ${ip_json},
          "domainName": ${domain_json},
          "portBindings": [
${binding}
          ]
        }
      ],
      "mtu": ${MTU},
      "multiplexing": {
        "level": "${MULTIPLEXING}"
      },
      "handshakeMode": "${HANDSHAKE_MODE}"${tp_section}
    }
  ],
  "activeProfile": "default",
  "rpcPort": ${CLIENT_RPC_PORT},
  "socks5Port": ${CLIENT_SOCKS5_PORT},
  "loggingLevel": "INFO",
  "socks5ListenLAN": false,
  "httpProxyPort": ${CLIENT_HTTP_PORT},
  "httpProxyListenLAN": false
}
EOF
}

build_clash_yaml_entry() {
  local ip="$1"
  local proto="$2"
  local p port_lines name_suffix tp tp_line="" server_yaml user_yaml password_yaml
  p="$(advertised_port_for_protocol "$proto")"
  name_suffix="$(proto_lower "$proto")"
  server_yaml="$(json_string "$ip")"
  user_yaml="$(json_string "$USERNAME")"
  password_yaml="$(json_string "$PASSWORD")"
  tp="$(export_traffic_pattern_value)"
  [ -n "$tp" ] && tp_line="
    traffic-pattern: \"${tp}\""
  if [ -n "$PORT" ]; then
    port_lines="    port: ${p}"
  else
    port_lines="    port-range: ${p}"
  fi
  cat <<EOF
  - name: mieru-mita-${name_suffix}
    type: mieru
    server: ${server_yaml}
${port_lines}
    transport: ${proto}
    udp: true
    username: ${user_yaml}
    password: ${password_yaml}
    multiplexing: ${MULTIPLEXING}
    handshake-mode: ${HANDSHAKE_MODE}${tp_line}
EOF
}

build_clash_yaml() {
  local ip="$1"
  local proto
  while IFS= read -r proto; do
    build_clash_yaml_entry "$ip" "$proto"
  done < <(protocols_for_mode)
}

build_clash_yaml_header() {
  printf '%s\n' 'proxies:'
}

build_clash_yaml_full() {
  local ip="$1"
  build_clash_yaml_header
  build_clash_yaml "$ip"
}

protocol_output_count() {
  local n=0 proto
  while IFS= read -r proto; do
    [ -n "$proto" ] || continue
    n=$((n + 1))
  done < <(protocols_for_mode)
  printf '%s' "$n"
}

client_current_dir() {
  printf '%s/current' "${MITA_CLIENT_EXPORT_DIR%/}"
}

client_json_path_for() {
  local proto="$1" safe_user
  safe_user="$(safe_filename_component "${USERNAME:-user}")"
  [ -n "$safe_user" ] || safe_user=user
  printf '%s/%s_%s.json' "$(client_current_dir)" "$safe_user" "$(proto_lower "$proto")"
}

client_export_remove_user() {
  local name="$1" current_dir safe_user
  current_dir="$(client_current_dir)"
  safe_user="$(safe_filename_component "$name")"
  [ -n "$safe_user" ] || return 0
  run rm -f -- "${current_dir}/${safe_user}_tcp.json" "${current_dir}/${safe_user}_udp.json"
}

client_exports_clear_current() {
  local current_dir
  current_dir="$(client_current_dir)"
  [ -d "$current_dir" ] || return 0
  run rm -f -- "${current_dir}/"*.json
}

client_exports_after_reconfigure() {
  local old_user="$1" old_protocol="$2" old_mtu="$3" old_traffic="$4"
  local old_seed="$5" old_low_entropy="$6" old_mux="$7" old_handshake="$8"
  if [ "${PROTOCOL:-TCP}" != "$old_protocol" ] \
     || [ "${MTU:-1400}" != "$old_mtu" ] \
     || [ "${TRAFFIC_PATTERN:-off}" != "$old_traffic" ] \
     || [ "${TRAFFIC_SEED:-}" != "$old_seed" ] \
     || [ "${LOW_ENTROPY_MODE:-LOW_ENTROPY_MODE_OFF}" != "$old_low_entropy" ] \
     || [ "${MULTIPLEXING:-MULTIPLEXING_OFF}" != "$old_mux" ] \
     || [ "${HANDSHAKE_MODE:-HANDSHAKE_NO_WAIT}" != "$old_handshake" ]; then
    client_exports_clear_current
  elif [ "${USERNAME:-}" != "$old_user" ]; then
    client_export_remove_user "$old_user"
  fi
}

print_json_import_hint() {
  if [ "${PROTOCOL:-TCP}" = "BOTH" ]; then
    t '  先将上方 TCP 或 UDP JSON 下载到客户端，再执行:' \
      '  Download the TCP or UDP JSON shown above to the client, then run:'
  else
    t '  先将上方 JSON 下载到客户端，再执行:' \
      '  Download the JSON shown above to the client, then run:'
  fi
  t '    mieru apply config <客户端本地 JSON 路径>' \
    '    mieru apply config <local-client-JSON-path>'
}

print_protocol_outputs() {
  local ip="$1"
  local proto link cfg_path cfg_tmp multi=0 count current_dir safe_user
  prepare_traffic_pattern_export
  count="$(protocol_output_count)"
  if [ "$count" -gt 1 ]; then
    multi=1
  fi
  current_dir="$(client_current_dir)"
  safe_user="$(safe_filename_component "${USERNAME:-user}")"
  [ -n "$safe_user" ] || safe_user=user
  if [ "$DRY_RUN" -ne 1 ]; then
    install -d -o root -g root -m 0700 "$current_dir"
  fi
  while IFS= read -r proto; do
    [ -n "$proto" ] || continue
    msg ""
    if [ "$multi" -eq 1 ]; then
      t "【${proto} 节点链接】" "[${proto} share link]"
    else
      t '【节点链接】' '[Share link]'
    fi
    link="$(generate_share_link_for "$ip" "$proto")"
    msg "$link"
    cfg_path="$(client_json_path_for "$proto")"
    msg ""
    if [ "$multi" -eq 1 ]; then
      t "【${proto} 客户端 JSON】（供 mieru 客户端使用，勿在服务器 mita apply）" \
        "[${proto} client JSON] (for mieru client only — do NOT mita apply on server)"
    else
      t '【客户端 JSON 配置】（供 mieru 客户端使用，勿在服务器 mita apply）' \
        '[Client JSON] (for mieru client only — do NOT mita apply on server)'
    fi
    if [ "$DRY_RUN" -ne 1 ]; then
      cfg_tmp="$(mktemp "${cfg_path}.XXXXXX")" || return 1
      if ! build_client_json_for "$ip" "$proto" >"$cfg_tmp" \
         || ! chmod 0600 "$cfg_tmp" \
         || ! mv -f "$cfg_tmp" "$cfg_path"; then
        rm -f "$cfg_tmp"
        return 1
      fi
      t "  已保存: ${cfg_path}" "  Saved:  ${cfg_path}"
    else
      t "  将保存: ${cfg_path}" "  Will save: ${cfg_path}"
    fi
  done < <(protocols_for_mode)
  if [ "$DRY_RUN" -ne 1 ]; then
    # v2.1.0 及更早版本的时间戳文件会造成通配符歧义和旧凭据回退，
    # 成功写入稳定文件后清理这些由脚本生成的旧导出。
    rm -f /root/nobrand_mieru_client_*.json 2>/dev/null || true
    case "${PROTOCOL:-TCP}" in
      TCP) rm -f "${current_dir}/${safe_user}_udp.json" 2>/dev/null || true ;;
      UDP) rm -f "${current_dir}/${safe_user}_tcp.json" 2>/dev/null || true ;;
    esac
  fi
}

print_client_endpoint_mapping() {
  [ -n "${ADVERTISE_HOST:-}" ] || return 0
  local backend_ip="${1:-}" entry_host backend_host
  [ -n "$backend_ip" ] || backend_ip="$(public_ip 2>/dev/null || true)"
  client_endpoint_is_independent "$backend_ip" || return 0
  entry_host="$(url_host "$ADVERTISE_HOST")"
  if [ -n "$backend_ip" ]; then
    backend_host="$(url_host "$backend_ip")"
  else
    backend_host="$(t '<本机可达 IP>' '<server reachable IP>')"
  fi
  msg ""
  t '【客户端入口映射】（仅提示，不修改服务器配置）' \
    '[Client endpoint mapping] (display only; server config is unchanged)'
  if [ "${PROTOCOL:-TCP}" = "BOTH" ]; then
    t "  客户端: TCP ${entry_host}:$(advertised_port_for_protocol TCP) / UDP ${entry_host}:$(advertised_port_for_protocol UDP)" \
      "  Client: TCP ${entry_host}:$(advertised_port_for_protocol TCP) / UDP ${entry_host}:$(advertised_port_for_protocol UDP)"
    t "       -> 后端: TCP ${backend_host}:${PORT} / UDP ${backend_host}:$((PORT + 1))" \
      "       -> Backend: TCP ${backend_host}:${PORT} / UDP ${backend_host}:$((PORT + 1))"
  else
    t "  客户端: ${entry_host}:$(advertised_port_for_protocol "$PROTOCOL")/${PROTOCOL}" \
      "  Client: ${entry_host}:$(advertised_port_for_protocol "$PROTOCOL")/${PROTOCOL}"
    t "       -> 后端: ${backend_host}:${PORT}/${PROTOCOL}" \
      "       -> Backend: ${backend_host}:${PORT}/${PROTOCOL}"
  fi
}

print_summary() {
  local context="${1:-install}" ip
  ip="$(advertised_host || true)"
  msg ""
  case "$context" in
    install) t '========== 安装完成 ==========' '========== Installation complete ==========' ;;
    *) t '========== 当前节点配置 ==========' '========== Current node configuration ==========' ;;
  esac
  if [ -n "$ip" ]; then
    print_protocol_outputs "$ip"
  else
    warn "$(t '未能获取公网 IP，请手动将下方连接信息填入客户端' \
      'Could not detect public IP; use connection info below manually')"
  fi
  msg ""
  t '【连接信息】' '[Connection info]'
  if [ -n "${ADVERTISE_HOST:-}" ]; then
    t "  客户端入口: ${ip:-<未知>}" "  Client entry: ${ip:-<unknown>}"
  else
    t "  服务器: ${ip:-<未知>}" "  Server:   ${ip:-<unknown>}"
  fi
  t "  用户名: ${USERNAME}" "  Username: ${USERNAME}"
  t "  密码:   ${PASSWORD}" "  Password: ${PASSWORD}"
  t "  协议:   $(client_protocol_label)" "  Protocol: $(client_protocol_label)"
  t "  网络入口: $(nb_ingress_profile_name "${INGRESS_PROFILE_ID:-}")" \
    "  Ingress:  $(nb_ingress_profile_name "${INGRESS_PROFILE_ID:-}")"
  t "  Profile: $(profile_label)" "  Profile:  $(profile_label)"
  t "  MTU:    ${MTU}（$(mtu_policy_label)）" \
    "  MTU:      ${MTU} ($(mtu_policy_label))"
  t "  流量伪装: $(traffic_label)" "  Obfuscation: $(traffic_label)"
  t "  低熵模式: $(low_entropy_label)" "  Low entropy: $(low_entropy_label)"
  t "  多路复用: ${MULTIPLEXING}" "  Multiplexing: ${MULTIPLEXING}"
  t "  握手模式: ${HANDSHAKE_MODE}" "  Handshake: ${HANDSHAKE_MODE}"
  if [ -n "$PORT" ]; then
    if [ "$PROTOCOL" = "BOTH" ]; then
      t "  端口:   TCP $(advertised_port_for_protocol TCP) / UDP $(advertised_port_for_protocol UDP)" \
        "  Ports:    TCP $(advertised_port_for_protocol TCP) / UDP $(advertised_port_for_protocol UDP)"
    else
      t "  端口:   $(advertised_port_for_protocol "$PROTOCOL")" \
        "  Port:     $(advertised_port_for_protocol "$PROTOCOL")"
    fi
  else
    t "  端口段: ${PORT_RANGE}" "  Port range: ${PORT_RANGE}"
  fi
  print_client_endpoint_mapping
  msg ""
  t '导入方式:' 'Import options:'
  if [ "$PROTOCOL" = "BOTH" ]; then
    msg '  mieru import config "<TCP 节点链接>"   # 或分别导入 TCP / UDP 链接'
  else
    msg '  mieru import config "<节点链接>"   # 简单链接不含 socks5Port，全新设备建议用 JSON'
  fi
  print_json_import_hint
  if [ "$PROTOCOL" = "BOTH" ]; then
    msg ''
    t '【客户端提示】双协议已分开输出：TCP 与 UDP 各用对应链接/JSON；' \
      '[Client tip] Dual protocol outputs are split: use matching TCP or UDP link/JSON.'
    t '  v2rayN 导入后传输协议选 tcp 或 udp（勿选「两个都」）。' \
      '  In v2rayN pick transport tcp or udp (not "both").'
  fi
  if [ -n "$ip" ]; then
    msg ""
    t '【Clash / mihomo 配置片段】' '[Clash / mihomo snippet]'
    build_clash_yaml_full "$ip"
  fi
  cloud_firewall_hint
}

generate_client_config() {
  local ip
  ip="$(advertised_host || echo 'YOUR_SERVER_IP')"
  msg ""
  t '========== 节点链接与客户端配置 ==========' \
    '========== Share links & client config =========='
  t "当前 MTU: ${MTU}（$(mtu_policy_label)）" \
    "Current MTU: ${MTU} ($(mtu_policy_label))"
  t 'MTU 已同步写入 mierus:// 节点链接和 mieru 客户端 JSON；mihomo 当前节点字段不单独配置 MTU。' \
    'MTU is included in the mierus:// link and mieru client JSON; current mihomo proxy fields do not expose a separate MTU option.'
  print_protocol_outputs "$ip"
  print_client_endpoint_mapping
  msg ""
  t '【导入方式】' '[How to import]'
  if [ "$PROTOCOL" = "BOTH" ]; then
    msg '  mieru import config "<TCP 节点链接>"   # TCP / UDP 各用对应链接'
  else
    msg '  mieru import config "<节点链接>"   # 一键导入（简单链接）'
  fi
  print_json_import_hint
  msg ""
  t '说明: 上方 mierus:// 为分享链接；JSON 为 mieru 客户端配置（在电脑/手机导入，勿在服务器 mita apply）' \
    'Note: mierus:// is the share link; JSON is for the mieru client on your device — do NOT mita apply on server'
  msg ""
  t '【Clash / mihomo 配置片段】' '[Clash / mihomo snippet]'
  build_clash_yaml_full "$ip"
  cloud_firewall_hint
}

install_fresh_rollback() {
  local snapshot="$1" bindings="${2:-}"
  if [ -n "$bindings" ]; then
    close_firewall_for_bindings "$bindings" 2>/dev/null || true
  fi
  isolated_stop_all 2>/dev/null || true
  tc_clear_owned_filters 2>/dev/null || true
  remove_users_scheduler 2>/dev/null || true
  users_tx_rollback "$snapshot" 0 || true
}

install_fresh_isolated() {
  local tx bindings
  install_self_script
  admin_lock_acquire || return 1
  tx="$(users_tx_snapshot)" || { admin_lock_release; return 1; }
  if ! users_initialize_primary; then
    install_fresh_rollback "$tx"
    admin_lock_release
    die "$(t '创建初始用户状态失败' 'Failed to create the initial user state')" || return 1
  fi
  if ! apply_users_config "$tx" 0; then
    install_fresh_rollback "$tx"
    admin_lock_release
    die "$(t '启动首个用户专属实例失败' \
      'Failed to start the first dedicated user instance')" || return 1
  fi
  bindings="$(multi_user_port_protocol_pairs)"
  if ! open_firewall_for_pairs "$bindings"; then
    install_fresh_rollback "$tx" "$bindings"
    admin_lock_release
    die "$(t '放行专属实例端口失败，安装状态已回滚' \
      'Failed to allow dedicated-instance ports; installation state was rolled back')" || return 1
  fi
  if ! verify_mita_running || ! save_install_state; then
    install_fresh_rollback "$tx" "$bindings"
    admin_lock_release
    die "$(t '专属实例验收或状态保存失败，安装状态已回滚' \
      'Dedicated-instance verification or state persistence failed; installation state was rolled back')" || return 1
  fi
  users_tx_commit "$tx"
  client_exports_clear_current 2>/dev/null || true
  admin_lock_release
}

mita_preservable_config_exists() {
  mita_v3_install_state_valid \
    && users_isolated_mode \
    && [ "$(users_count 2>/dev/null || printf 0)" -gt 0 ]
}
