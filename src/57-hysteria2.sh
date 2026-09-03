# ---------- Hysteria2 engine: Xray-core v2 inbound parity ----------

hysteria2_state_exists() {
  [ -s "$NOBRAND_HY2_STATE_FILE" ] && jq empty "$NOBRAND_HY2_STATE_FILE" >/dev/null 2>&1
}

hysteria2_state_field() {
  local field="$1"
  hysteria2_state_exists || return 1
  jq -r --arg field "$field" \
    'if has($field) and .[$field] != null then .[$field] else empty end' "$NOBRAND_HY2_STATE_FILE"
}

hysteria2_valid_sni() {
  local value="${1:-}"
  valid_domain_name "$value" || {
    [[ "$value" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] && valid_ip_literal "$value"
  }
}

# 保持 Xray-OneClick lib/57-hysteria2.sh 的 prime256v1、3650 days、CN、
# 0600/0644 与 key-first atomic rollback 语义。
generate_hysteria2_cert() {
  local cert="$NOBRAND_HY2_CERT_FILE" key="$NOBRAND_HY2_KEY_FILE"
  local tmp_cert tmp_key old_key=""
  command -v openssl >/dev/null 2>&1 || {
    warn '[Hysteria2] 需要 openssl 生成自签证书。'
    return 1
  }
  mkdir -p "$NOBRAND_HY2_CONFIG_DIR" || return 1
  chmod 0700 "$NOBRAND_HY2_CONFIG_DIR" || return 1
  tmp_key="$(mktemp "${key}.tmp.XXXXXX")" || return 1
  tmp_cert="$(mktemp "${cert}.tmp.XXXXXX")" || { rm -f "$tmp_key"; return 1; }
  if ! openssl ecparam -genkey -name prime256v1 -out "$tmp_key" 2>/dev/null; then
    rm -f "$tmp_key" "$tmp_cert"
    warn '[Hysteria2] 生成 P-256 私钥失败。'
    return 1
  fi
  if ! openssl req -new -x509 -days 3650 -key "$tmp_key" -out "$tmp_cert" \
      -subj "/CN=${HY2_SNI:-bing.com}" 2>/dev/null; then
    rm -f "$tmp_key" "$tmp_cert"
    warn '[Hysteria2] 生成自签证书失败。'
    return 1
  fi
  chmod 0600 "$tmp_key" && chmod 0644 "$tmp_cert" \
    || { rm -f "$tmp_key" "$tmp_cert"; return 1; }
  if [ -f "$key" ]; then
    old_key="$(mktemp "${key}.rollback.XXXXXX")" \
      || { rm -f "$tmp_key" "$tmp_cert"; return 1; }
    cp -a "$key" "$old_key" \
      || { rm -f "$tmp_key" "$tmp_cert" "$old_key"; return 1; }
  fi
  mv "$tmp_key" "$key" \
    || { rm -f "$tmp_key" "$tmp_cert" "$old_key"; return 1; }
  if ! mv "$tmp_cert" "$cert"; then
    rm -f "$tmp_cert"
    if [ -n "$old_key" ]; then cp -a "$old_key" "$key" || true; else rm -f "$key"; fi
    rm -f "$old_key"
    return 1
  fi
  rm -f "$old_key"
}

hysteria2_generate_config() {
  local output="$1" listen="$2" port="$3" auth="$4" sni="$5" obfs="$6"
  local cert="${7:-$NOBRAND_HY2_CERT_FILE}" key="${8:-$NOBRAND_HY2_KEY_FILE}"
  jq -n --arg tag "$NOBRAND_HY2_TAG" --arg listen "$listen" --arg port "$port" \
    --arg auth "$auth" --arg cert "$cert" --arg key "$key" --arg obfs "$obfs" '
    {
      "log": {"loglevel":"warning"},
      "inbounds": [{
        "tag": $tag,
        "listen": $listen,
        "port": ($port|tonumber),
        "protocol": "hysteria",
        "settings": {
          "version": 2,
          "clients": [{"auth":$auth,"email":"hysteria2@xray"}]
        },
        "streamSettings": {
          "network": "hysteria",
          "security": "tls",
          "tlsSettings": {
            "alpn": ["h3"],
            "certificates": [{"certificateFile":$cert,"keyFile":$key}]
          },
          "hysteriaSettings": {"version":2},
          "finalmask": {
            "udp": [{"type":"salamander","settings":{"password":$obfs}}]
          }
        }
      }],
      "outbounds": [{"tag":"direct","protocol":"freedom"}],
      "routing": {"rules":[]}
    }
  ' >"$output"
}

hysteria2_build_share_link() {
  local auth="${1:-}" host="${2:-}" port="${3:-}" sni="${4:-}" obfs="${5:-}"
  local name="${6:-NoBrand-Hysteria2}" auth_uri host_uri sni_uri obfs_uri name_uri
  [ -n "$auth" ] && [ -n "$host" ] && nb_valid_port "$port" && [ -n "$sni" ] || return 1
  auth_uri="$(urlencode "$auth")" || return 1
  host_uri="$(url_host "$host")"
  sni_uri="$(urlencode "$sni")" || return 1
  obfs_uri="$(urlencode "$obfs")" || return 1
  name_uri="$(urlencode "$name")" || return 1
  printf 'hysteria2://%s@%s:%s?sni=%s&alpn=h3&insecure=1&obfs=salamander&obfs-password=%s#%s' \
    "$auth_uri" "$host_uri" "$port" "$sni_uri" "$obfs_uri" "$name_uri"
}

hysteria2_current_share_link() {
  local auth sni obfs listen_port mode advertise_host advertise_port ingress_profile_id host port
  hysteria2_state_exists || return 1
  auth="$(hysteria2_state_field auth)"
  sni="$(hysteria2_state_field sni)"
  obfs="$(hysteria2_state_field obfs)"
  listen_port="$(hysteria2_state_field listen_port)"
  mode="$(hysteria2_state_field advertise_mode)"
  advertise_host="$(hysteria2_state_field advertise_host)"
  advertise_port="$(hysteria2_state_field advertise_port)"
  ingress_profile_id="$(hysteria2_state_field ingress_profile_id 2>/dev/null || true)"
  host="$(nb_effective_advertise_host "$mode" "$advertise_host" "$ingress_profile_id")"
  port="$(nb_effective_advertise_port "$mode" "$advertise_port" "$listen_port" "$ingress_profile_id")"
  hysteria2_build_share_link "$auth" "$host" "$port" "$sni" "$obfs"
}

hysteria2_export_values() {
  local auth sni obfs listen_port mode advertise_host advertise_port ingress_profile_id host port
  hysteria2_state_exists || return 1
  auth="$(hysteria2_state_field auth)"
  sni="$(hysteria2_state_field sni)"
  obfs="$(hysteria2_state_field obfs)"
  listen_port="$(hysteria2_state_field listen_port)"
  mode="$(hysteria2_state_field advertise_mode)"
  advertise_host="$(hysteria2_state_field advertise_host)"
  advertise_port="$(hysteria2_state_field advertise_port)"
  ingress_profile_id="$(hysteria2_state_field ingress_profile_id 2>/dev/null || true)"
  host="$(nb_effective_advertise_host "$mode" "$advertise_host" "$ingress_profile_id")"
  port="$(nb_effective_advertise_port "$mode" "$advertise_port" "$listen_port" "$ingress_profile_id")"
  printf '%s\t%s\t%s\t%s\t%s\n' "$auth" "$sni" "$obfs" "$host" "$port"
}

hysteria2_export_mihomo() {
  local auth sni obfs host port values
  values="$(hysteria2_export_values)" || return 1
  IFS=$'\t' read -r auth sni obfs host port <<<"$values"
  jq -n --arg server "$host" --arg port "$port" --arg password "$auth" \
    --arg sni "$sni" --arg obfs "$obfs" -r '
      "- name: NoBrand-Hysteria2\n" +
      "  type: hysteria2\n" +
      "  server: " + ($server|tojson) + "\n" +
      "  port: " + $port + "\n" +
      "  password: " + ($password|tojson) + "\n" +
      "  sni: " + ($sni|tojson) + "\n" +
      "  skip-cert-verify: true\n" +
      "  obfs: salamander\n" +
      "  obfs-password: " + ($obfs|tojson)
    '
}

hysteria2_export_singbox() {
  local auth sni obfs host port values
  values="$(hysteria2_export_values)" || return 1
  IFS=$'\t' read -r auth sni obfs host port <<<"$values"
  jq -n --arg server "$host" --arg port "$port" --arg password "$auth" \
    --arg sni "$sni" --arg obfs "$obfs" '
      {
        type:"hysteria2",
        tag:"NoBrand-Hysteria2",
        server:$server,
        server_port:($port|tonumber),
        password:$password,
        obfs:{type:"salamander",password:$obfs},
        tls:{enabled:true,server_name:$sni,insecure:true,alpn:["h3"]}
      }
    '
}

hysteria2_generate_state() {
  local output="$1" listen="$2" port="$3" auth="$4" sni="$5" obfs="$6"
  local advertise_mode="$7" advertise_host="$8" advertise_port="$9"
  local created_at="${10:-}" updated_at link effective_host effective_port runtime_version
  local ingress_profile_id="${11:-}"
  [ -n "$created_at" ] || created_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  updated_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  effective_host="$(nb_effective_advertise_host "$advertise_mode" "$advertise_host" "$ingress_profile_id")"
  effective_port="$(nb_effective_advertise_port "$advertise_mode" "$advertise_port" "$port" "$ingress_profile_id")"
  link="$(hysteria2_build_share_link "$auth" "$effective_host" "$effective_port" "$sni" "$obfs")" || return 1
  runtime_version="$(nobrand_xray_version 2>/dev/null || printf unknown)"
  jq -n --arg auth "$auth" --arg sni "$sni" --arg obfs "$obfs" \
    --arg listen "$listen" --arg port "$port" --arg mode "$advertise_mode" \
    --arg advertise_host "$advertise_host" --arg advertise_port "$advertise_port" \
    --arg tag "$NOBRAND_HY2_TAG" --arg link "$link" --arg runtime "$runtime_version" \
    --arg created "$created_at" --arg updated "$updated_at" --arg ingress_profile_id "$ingress_profile_id" '
    {
      "protocol":"hysteria2",
      "auth":$auth,
      "sni":$sni,
      "obfs":$obfs,
      "listen_host":$listen,
      "listen_port":($port|tonumber),
      "transport":"udp",
      "advertise_mode":$mode,
      "advertise_host":$advertise_host,
      "advertise_port":(if $advertise_port=="" then "" else ($advertise_port|tonumber) end),
      "tag":$tag,
      "runtime_version":$runtime,
      "link":$link,
      "enabled":true,
      "created_at":$created,
      "updated_at":$updated
    }
    + if $ingress_profile_id=="" then {} else {ingress_profile_id:$ingress_profile_id} end
  ' >"$output"
}

hysteria2_snapshot_file() {
  local source="$1" destination="$2"
  if [ -e "$source" ]; then cp -a "$source" "$destination"; else printf absent >"${destination}.absent"; fi
}

hysteria2_restore_snapshot_file() {
  local snapshot="$1" destination="$2"
  if [ -f "${snapshot}.absent" ]; then
    rm -f "$destination"
  elif [ -e "$snapshot" ]; then
    mkdir -p "$(dirname "$destination")"
    cp -a "$snapshot" "$destination"
  fi
}

hysteria2_configure_requests() {
  local interactive="${1:-0}" old_port="" conflict_owner=""
  if hysteria2_state_exists && [ "${INGRESS_PROFILE_CLI:-0}" -eq 0 ]; then
    INGRESS_PROFILE_ID="$(hysteria2_state_field ingress_profile_id 2>/dev/null || true)"
    [ -n "$INGRESS_PROFILE_ID" ] || INGRESS_PROFILE_ID="$NOBRAND_LEGACY_INGRESS_PROFILE_ID"
  else
    nb_prepare_ingress_request || return 1
  fi
  nb_prepare_ingress_deployment "$INGRESS_PROFILE_ID" native-bind \
    || die 'Hysteria2 无法绑定所选 Ingress 的 Strict 本地地址'
  HY2_LISTEN="$INGRESS_LISTEN_HOST"
  hysteria2_state_exists && old_port="$(hysteria2_state_field listen_port 2>/dev/null || true)"
  if [ -z "${PORT:-}" ]; then
    PORT="$(nb_select_available_port UDP "$INGRESS_PROFILE_ID")" \
      || die '所选入口配置没有可用 Hysteria2 UDP 自动端口；manual-only 必须显式使用 --port'
    PORT_AUTO_SELECTED=1
  else
    nb_valid_port "$PORT" || die 'Hysteria2 端口必须是 1-65535'
    PORT="$(normalize_uint "$PORT")"
    nb_warn_if_outside_recommended_range "$PORT" "$INGRESS_PROFILE_ID"
    if [ "$PORT" != "$old_port" ] \
       && ! nb_port_available_for_profile "$PORT" UDP "$INGRESS_PROFILE_ID" 'hy2:default'; then
      warn "Hysteria2 UDP/${PORT} 已占用"
      nb_describe_port_conflict UDP "$PORT"
      return 1
    fi
  fi
  if [ "$interactive" -eq 1 ] && [ "${ADVERTISE_CLI:-0}" -eq 0 ]; then
    nb_collect_advertise_endpoint_interactive Hysteria2 "$PORT"
  else
    nb_require_explicit_endpoint_noninteractive
  fi
  nb_validate_advertise_endpoint "$ADVERTISE_HOST" "$ADVERTISE_PORT" UDP \
    || die 'Hysteria2 Display Endpoint 无效'
  if [ -n "$ADVERTISE_HOST" ]; then
    conflict_owner="$(nb_endpoint_conflict_owner UDP "$ADVERTISE_HOST" "$ADVERTISE_PORT" 'hy2:default' 2>/dev/null || true)"
    [ -z "$conflict_owner" ] || die "Hysteria2 Display Endpoint 与 ${conflict_owner} 冲突"
  fi
  if [ -z "${HY2_SNI:-}" ]; then
    if [ "$interactive" -eq 1 ]; then
      read_tty HY2_SNI "$(t 'Hysteria2 伪装 SNI（回车随机）: ' 'Hysteria2 camouflage SNI (Enter=random): ')" || HY2_SNI=""
      [ -n "$HY2_SNI" ] || HY2_SNI="${NOBRAND_HY2_SNI_CANDIDATES[$((RANDOM % ${#NOBRAND_HY2_SNI_CANDIDATES[@]}))]}"
    else
      HY2_SNI="${NOBRAND_HY2_SNI_CANDIDATES[0]}"
    fi
  fi
  hysteria2_valid_sni "$HY2_SNI" || die 'Hysteria2 SNI 必须是有效域名或 IPv4 地址'
  HY2_AUTH="$(openssl rand -hex 16 2>/dev/null || true)"
  [ -n "$HY2_AUTH" ] || HY2_AUTH="$(random_token)$(random_token)$(random_token)"
  HY2_OBFS="$(openssl rand -hex 16 2>/dev/null || true)"
  [ -n "$HY2_OBFS" ] || HY2_OBFS="$(random_token)$(random_token)$(random_token)"
}

hysteria2_install_rollback() {
  local snapshot="$1" was_active="$2" new_binding_owned="$3"
  nobrand_hy2_service_action stop >/dev/null 2>&1 || true
  [ "$new_binding_owned" -eq 0 ] || nb_firewall_close_pairs "UDP|${PORT}" >/dev/null 2>&1 || true
  hysteria2_restore_snapshot_file "$snapshot/config" "$NOBRAND_HY2_CONFIG_FILE"
  hysteria2_restore_snapshot_file "$snapshot/state" "$NOBRAND_HY2_STATE_FILE"
  hysteria2_restore_snapshot_file "$snapshot/cert" "$NOBRAND_HY2_CERT_FILE"
  hysteria2_restore_snapshot_file "$snapshot/key" "$NOBRAND_HY2_KEY_FILE"
  hysteria2_restore_snapshot_file "$snapshot/service-systemd" "$NOBRAND_HY2_SYSTEMD_SERVICE"
  hysteria2_restore_snapshot_file "$snapshot/service-openrc" "$NOBRAND_HY2_OPENRC_SERVICE"
  hysteria2_restore_snapshot_file "$snapshot/xray" "$NOBRAND_XRAY_BIN"
  [ "$(nb_service_manager)" != systemd ] || systemctl daemon-reload >/dev/null 2>&1 || true
  [ "$was_active" -eq 0 ] || nobrand_hy2_service_action start >/dev/null 2>&1 || true
}

install_hysteria2() {
  local interactive=0 snapshot config_tmp state_tmp advertise_mode old_port="" old_created=""
  local was_active=0 binding_was_owned=0 binding_now_owned=0
  [ "${YES:-0}" -eq 1 ] || interactive=1
  nobrand_prepare_common
  admin_lock_acquire || return 1
  snapshot="$(mktemp_dir)" || { admin_lock_release; return 1; }
  hysteria2_snapshot_file "$NOBRAND_HY2_CONFIG_FILE" "$snapshot/config"
  hysteria2_snapshot_file "$NOBRAND_HY2_STATE_FILE" "$snapshot/state"
  hysteria2_snapshot_file "$NOBRAND_HY2_CERT_FILE" "$snapshot/cert"
  hysteria2_snapshot_file "$NOBRAND_HY2_KEY_FILE" "$snapshot/key"
  hysteria2_snapshot_file "$NOBRAND_HY2_SYSTEMD_SERVICE" "$snapshot/service-systemd"
  hysteria2_snapshot_file "$NOBRAND_HY2_OPENRC_SERVICE" "$snapshot/service-openrc"
  hysteria2_snapshot_file "$NOBRAND_XRAY_BIN" "$snapshot/xray"
  nobrand_hy2_service_active && was_active=1
  if hysteria2_state_exists; then
    old_port="$(hysteria2_state_field listen_port 2>/dev/null || true)"
    old_created="$(hysteria2_state_field created_at 2>/dev/null || true)"
  fi
  if ! nobrand_install_xray_runtime 0 || ! hysteria2_configure_requests "$interactive"; then
    hysteria2_install_rollback "$snapshot" "$was_active" 0
    rm -rf -- "$snapshot"
    admin_lock_release
    return 1
  fi
  nb_firewall_binding_owned UDP "$PORT" && binding_was_owned=1
  if [ "$was_active" -eq 1 ]; then
    nobrand_hy2_service_action stop || {
      hysteria2_install_rollback "$snapshot" "$was_active" 0
      rm -rf -- "$snapshot"; admin_lock_release; return 1;
    }
  fi
  # TOCTOU 二次检测：旧实例同端口需先停止自身 listener。
  if ! nb_port_available_for_profile "$PORT" UDP "$INGRESS_PROFILE_ID" 'hy2:default'; then
    warn "提交前发现 UDP/${PORT} 已被其它进程占用"
    nb_describe_port_conflict UDP "$PORT"
    hysteria2_install_rollback "$snapshot" "$was_active" 0
    rm -rf -- "$snapshot"; admin_lock_release; return 1
  fi
  if ! generate_hysteria2_cert; then
    hysteria2_install_rollback "$snapshot" "$was_active" 0
    rm -rf -- "$snapshot"; admin_lock_release; return 1
  fi
  config_tmp="$(mktemp_file .json)" || {
    hysteria2_install_rollback "$snapshot" "$was_active" 0
    rm -rf -- "$snapshot"; admin_lock_release; return 1;
  }
  state_tmp="$(mktemp_file .json)" || {
    rm -f "$config_tmp"; hysteria2_install_rollback "$snapshot" "$was_active" 0
    rm -rf -- "$snapshot"; admin_lock_release; return 1;
  }
  advertise_mode="$(nb_endpoint_mode_from_values "$ADVERTISE_HOST")"
  if ! hysteria2_generate_config "$config_tmp" "$HY2_LISTEN" "$PORT" "$HY2_AUTH" "$HY2_SNI" "$HY2_OBFS" \
     || ! nobrand_xray_test_config "$config_tmp" \
     || ! hysteria2_generate_state "$state_tmp" "$HY2_LISTEN" "$PORT" "$HY2_AUTH" "$HY2_SNI" "$HY2_OBFS" \
          "$advertise_mode" "$ADVERTISE_HOST" "$ADVERTISE_PORT" "$old_created" "$INGRESS_PROFILE_ID" \
     || ! nb_ingress_stamp_state_file "$state_tmp" "$INGRESS_PROFILE_ID" native-bind \
     || ! nb_atomic_install_file "$config_tmp" "$NOBRAND_HY2_CONFIG_FILE" 0600 \
     || ! nb_atomic_install_file "$state_tmp" "$NOBRAND_HY2_STATE_FILE" 0600 \
     || ! nobrand_write_hy2_service \
     || ! nb_firewall_open_pairs "UDP|${PORT}"; then
    rm -f "$config_tmp" "$state_tmp"
    nb_firewall_binding_owned UDP "$PORT" && [ "$binding_was_owned" -eq 0 ] && binding_now_owned=1
    hysteria2_install_rollback "$snapshot" "$was_active" "$binding_now_owned"
    rm -rf -- "$snapshot"; admin_lock_release; return 1
  fi
  rm -f "$config_tmp" "$state_tmp"
  nb_firewall_binding_owned UDP "$PORT" && [ "$binding_was_owned" -eq 0 ] && binding_now_owned=1
  if ! nobrand_hy2_service_action restart \
     || ! nobrand_hy2_service_active \
     || ! nb_wait_for_enforced_listener "$INGRESS_ENFORCEMENT_RESOLVED" "$INGRESS_ENFORCEMENT_METHOD" \
          UDP "$PORT" "$INGRESS_LOCAL_ADDRESS" 'hy2:default' 25; then
    hysteria2_install_rollback "$snapshot" "$was_active" "$binding_now_owned"
    rm -rf -- "$snapshot"; admin_lock_release
    warn 'Hysteria2 服务启动或 UDP listener 验收失败，已回滚'
    return 1
  fi
  if [ -n "$old_port" ] && [ "$old_port" != "$PORT" ]; then
    nb_firewall_close_pairs "UDP|${old_port}" || true
  fi
  nobrand_install_manager_script || true
  rm -rf -- "$snapshot"
  admin_lock_release
  print_hysteria2_result install
}

hysteria2_set_endpoint() {
  local interactive=0 tmp mode owner auth sni obfs host port link ingress_profile_id
  require_root
  hysteria2_state_exists || die 'Hysteria2 未安装'
  [ "${YES:-0}" -eq 1 ] || interactive=1
  PORT="$(hysteria2_state_field listen_port)"
  if [ "$interactive" -eq 1 ] && [ "${ADVERTISE_CLI:-0}" -eq 0 ]; then
    nb_collect_advertise_endpoint_interactive Hysteria2 "$PORT"
  else
    nb_require_explicit_endpoint_noninteractive
  fi
  nb_validate_advertise_endpoint "$ADVERTISE_HOST" "$ADVERTISE_PORT" UDP || die 'Display Endpoint 无效'
  if [ -n "$ADVERTISE_HOST" ]; then
    owner="$(nb_endpoint_conflict_owner UDP "$ADVERTISE_HOST" "$ADVERTISE_PORT" 'hy2:default' 2>/dev/null || true)"
    [ -z "$owner" ] || die "Display Endpoint 与 ${owner} 冲突"
  fi
  admin_lock_acquire || return 1
  tmp="$(mktemp_file .json)" || { admin_lock_release; return 1; }
  mode="$(nb_endpoint_mode_from_values "$ADVERTISE_HOST")"
  auth="$(hysteria2_state_field auth)"
  sni="$(hysteria2_state_field sni)"
  obfs="$(hysteria2_state_field obfs)"
  ingress_profile_id="$(hysteria2_state_field ingress_profile_id 2>/dev/null || true)"
  [ -n "$ingress_profile_id" ] || ingress_profile_id="$NOBRAND_LEGACY_INGRESS_PROFILE_ID"
  host="$(nb_effective_advertise_host "$mode" "$ADVERTISE_HOST" "$ingress_profile_id")"
  port="$(nb_effective_advertise_port "$mode" "$ADVERTISE_PORT" "$PORT" "$ingress_profile_id")"
  link="$(hysteria2_build_share_link "$auth" "$host" "$port" "$sni" "$obfs")" \
    || { rm -f "$tmp"; admin_lock_release; return 1; }
  if ! jq --arg mode "$mode" --arg host "$ADVERTISE_HOST" --arg port "$ADVERTISE_PORT" \
      --arg link "$link" --arg updated "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
        .advertise_mode=$mode |
        .advertise_host=$host |
        .advertise_port=(if $port=="" then "" else ($port|tonumber) end) |
        .link=$link |
        .updated_at=$updated
      ' "$NOBRAND_HY2_STATE_FILE" >"$tmp" \
     || ! nb_atomic_install_file "$tmp" "$NOBRAND_HY2_STATE_FILE" 0600; then
    rm -f "$tmp"; admin_lock_release; return 1
  fi
  rm -f "$tmp"
  # 红线：本函数不调用 service、firewall、config、tc 或 quota。
  admin_lock_release
  t 'Hysteria2 客户端展示入口已更新；server config/listener/service/firewall 均未改变' \
    'Hysteria2 display endpoint updated; server config/listener/service/firewall are unchanged'
  print_hysteria2_result show
}

hysteria2_running() {
  local port policy method address
  hysteria2_state_exists || return 1
  port="$(hysteria2_state_field listen_port)"
  policy="$(hysteria2_state_field ingress_enforcement 2>/dev/null || printf permissive)"
  method="$(hysteria2_state_field ingress_enforcement_method 2>/dev/null || printf wildcard)"
  address="$(hysteria2_state_field ingress_local_address 2>/dev/null || true)"
  nobrand_hy2_service_active \
    && nb_wait_for_enforced_listener "$policy" "$method" UDP "$port" "$address" 'hy2:default' 1
}

hysteria2_apply_ingress_enforcement() {
  local profile_id port auth sni obfs candidate_state candidate_config snapshot was_active=0 rc=0
  hysteria2_state_exists || return 1
  profile_id="$(hysteria2_state_field ingress_profile_id 2>/dev/null || true)"
  [ -n "$profile_id" ] || profile_id="$NOBRAND_LEGACY_INGRESS_PROFILE_ID"
  nb_prepare_ingress_deployment "$profile_id" native-bind || return 1
  port="$(hysteria2_state_field listen_port)"
  auth="$(hysteria2_state_field auth)"
  sni="$(hysteria2_state_field sni)"
  obfs="$(hysteria2_state_field obfs)"
  candidate_state="$(mktemp_file .hy2-ingress-state)" || return 1
  candidate_config="$(mktemp_file .hy2-ingress-config)" || { rm -f "$candidate_state"; return 1; }
  snapshot="$(mktemp_dir)" || { rm -f "$candidate_state" "$candidate_config"; return 1; }
  cp -a "$NOBRAND_HY2_STATE_FILE" "$snapshot/state" \
    && cp -a "$NOBRAND_HY2_CONFIG_FILE" "$snapshot/config" || rc=1
  if [ "$rc" -eq 0 ]; then
    jq --arg listen "$INGRESS_LISTEN_HOST" '.listen_host=$listen' "$NOBRAND_HY2_STATE_FILE" >"$candidate_state" \
      && nb_ingress_stamp_state_file "$candidate_state" "$profile_id" native-bind \
      && hysteria2_generate_config "$candidate_config" "$INGRESS_LISTEN_HOST" "$port" "$auth" "$sni" "$obfs" \
      && nobrand_xray_test_config "$candidate_config" || rc=1
  fi
  nobrand_hy2_service_active && was_active=1
  if [ "$rc" -eq 0 ]; then
    nb_atomic_install_file "$candidate_config" "$NOBRAND_HY2_CONFIG_FILE" 0600 \
      && nb_atomic_install_file "$candidate_state" "$NOBRAND_HY2_STATE_FILE" 0600 || rc=1
  fi
  if [ "$rc" -eq 0 ] && [ "$was_active" -eq 1 ]; then
    [ "${NOBRAND_TEST_INGRESS_SERVICE_FAIL:-0}" -eq 0 ] \
      && nobrand_hy2_service_action restart \
      && [ "${NOBRAND_TEST_INGRESS_LISTENER_FAIL:-0}" -eq 0 ] \
      && hysteria2_running || rc=1
  fi
  if [ "$rc" -ne 0 ]; then
    nb_atomic_install_file "$snapshot/config" "$NOBRAND_HY2_CONFIG_FILE" 0600 >/dev/null 2>&1 || true
    nb_atomic_install_file "$snapshot/state" "$NOBRAND_HY2_STATE_FILE" 0600 >/dev/null 2>&1 || true
    if [ "$was_active" -eq 1 ]; then
      nobrand_hy2_service_action restart >/dev/null 2>&1 && hysteria2_running >/dev/null 2>&1 || true
    else
      nobrand_hy2_service_action stop >/dev/null 2>&1 || true
    fi
  fi
  rm -f "$candidate_state" "$candidate_config"
  rm -rf -- "$snapshot"
  return "$rc"
}

hysteria2_state_set_enabled() {
  local enabled="$1" tmp
  tmp="$(mktemp_file .json)" || return 1
  if ! jq --argjson enabled "$enabled" --arg updated "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      '.enabled=$enabled | .updated_at=$updated' "$NOBRAND_HY2_STATE_FILE" >"$tmp" \
     || ! nb_atomic_install_file "$tmp" "$NOBRAND_HY2_STATE_FILE" 0600; then
    rm -f "$tmp"
    return 1
  fi
  rm -f "$tmp"
}

hysteria2_node_rows() {
  local mode advertise_host advertise_port listen_port host port status
  hysteria2_state_exists || return 0
  mode="$(hysteria2_state_field advertise_mode)"
  advertise_host="$(hysteria2_state_field advertise_host)"
  advertise_port="$(hysteria2_state_field advertise_port)"
  listen_port="$(hysteria2_state_field listen_port)"
  host="$(nb_effective_advertise_host "$mode" "$advertise_host" "$(hysteria2_state_field ingress_profile_id 2>/dev/null || true)")"
  port="$(nb_effective_advertise_port "$mode" "$advertise_port" "$listen_port" "$(hysteria2_state_field ingress_profile_id 2>/dev/null || true)")"
  status=Stopped; hysteria2_running && status=Running
  printf 'Hysteria2|default|%s:%s/UDP|%s|UDP\n' "$host" "$port" "$status"
}

print_hysteria2_result() {
  local context="${1:-show}" auth sni obfs listen_host listen_port mode mode_label advertise_host advertise_port host port status link
  hysteria2_state_exists || { t 'Hysteria2 未安装' 'Hysteria2 is not installed'; return 0; }
  auth="$(hysteria2_state_field auth)"; sni="$(hysteria2_state_field sni)"; obfs="$(hysteria2_state_field obfs)"
  listen_host="$(hysteria2_state_field listen_host)"; listen_port="$(hysteria2_state_field listen_port)"
  mode="$(hysteria2_state_field advertise_mode)"; advertise_host="$(hysteria2_state_field advertise_host)"
  advertise_port="$(hysteria2_state_field advertise_port)"
  host="$(nb_effective_advertise_host "$mode" "$advertise_host" "$(hysteria2_state_field ingress_profile_id 2>/dev/null || true)")"
  port="$(nb_effective_advertise_port "$mode" "$advertise_port" "$listen_port" "$(hysteria2_state_field ingress_profile_id 2>/dev/null || true)")"
  status=已停止; hysteria2_running && status=运行中
  mode_label="$mode"; case "$mode" in auto) mode_label='自动' ;; custom) mode_label='自定义' ;; esac
  link="$(hysteria2_build_share_link "$auth" "$host" "$port" "$sni" "$obfs")"
  nobrand_print_banner
  msg "$( [ "$context" = install ] && printf '部署完成' || printf '节点配置' )"
  msg ''
  printf '协议        Hysteria2\n节点        default\n状态        %s\n' "$status"
  msg ''
  printf '实际监听 / Actual Listener\n  地址      %s\n  端口      %s\n  传输      UDP\n' "$listen_host" "$listen_port"
  msg ''
  printf '网络入口 / Ingress\n  入口配置 / Ingress Profile  %s\n' "$(nb_ingress_profile_name "$(hysteria2_state_field ingress_profile_id 2>/dev/null || true)")"
  msg ''
  printf '展示端点 / Display Endpoint\n  主机      %s\n  端口      %s\n  模式      %s\n' "$host" "$port" "$mode_label"
  msg ''
  printf '认证\n  Auth      %s\n  SNI       %s\n  Salamander 密码  %s\n' "$auth" "$sni" "$obfs"
  msg ''
  msg '========================================'
  msg 'Mihomo'
  msg '========================================'
  hysteria2_export_mihomo
  msg ''
  msg '========================================'
  msg 'sing-box'
  msg '========================================'
  hysteria2_export_singbox
  msg '  证书：P-256 自签名证书，有效期 3650 天；客户端必须设置 insecure=1。'
  msg ''
  msg '========================================'
  msg '客户端配置'
  msg '========================================'
  msg "$link"
}

hysteria2_service_command() {
  local action="$1" port was_enabled
  hysteria2_state_exists || die 'Hysteria2 未安装'
  port="$(hysteria2_state_field listen_port)"
  was_enabled="$(hysteria2_state_field enabled)"
  case "$action" in
    start)
      nb_firewall_open_pairs "UDP|${port}" || return 1
      if ! nobrand_hy2_service_action start || ! hysteria2_running \
         || ! hysteria2_state_set_enabled true; then
        nobrand_hy2_service_action stop >/dev/null 2>&1 || true
        [ "$was_enabled" = true ] || hysteria2_state_set_enabled false >/dev/null 2>&1 || true
        return 1
      fi
      ;;
    stop)
      nobrand_hy2_service_action stop || return 1
      if ! hysteria2_state_set_enabled false; then
        [ "$was_enabled" != true ] || nobrand_hy2_service_action start >/dev/null 2>&1 || true
        return 1
      fi
      ;;
    restart) nobrand_hy2_service_action restart && hysteria2_running ;;
    status)
      if hysteria2_running; then msg 'Hysteria2：运行中'; else msg 'Hysteria2：已停止'; return 1; fi
      ;;
  esac
}

remove_hysteria2_config() {
  local port
  require_root
  hysteria2_state_exists || { t 'Hysteria2 未安装' 'Hysteria2 is not installed'; return 0; }
  port="$(hysteria2_state_field listen_port)"
  admin_lock_acquire || return 1
  nobrand_remove_hy2_service || { admin_lock_release; return 1; }
  nb_firewall_close_pairs "UDP|${port}" || { admin_lock_release; return 1; }
  rm -f "$NOBRAND_HY2_CONFIG_FILE" "$NOBRAND_HY2_STATE_FILE" \
    "$NOBRAND_HY2_CERT_FILE" "$NOBRAND_HY2_KEY_FILE"
  admin_lock_release
  t '已删除 NoBrand 管理的 Hysteria2；未触碰 /etc/xray、xray.service、ike 或 Xray-OneClick' \
    'Removed NoBrand-managed Hysteria2; /etc/xray, xray.service, ike, and Xray-OneClick were untouched'
}

hysteria2_doctor() {
  local failed=0 port mode host advertise_port key_mode cert_cn expected_sni
  if ! hysteria2_state_exists; then
    nb_doctor_line INFO 'Hysteria2 未安装'
    return 0
  fi
  port="$(hysteria2_state_field listen_port)"
  [ -x "$NOBRAND_XRAY_BIN" ] && nb_doctor_line PASS "Xray $(nobrand_xray_version 2>/dev/null || printf '未知版本')" \
    || { nb_doctor_line FAIL 'NoBrand Xray 可执行文件'; failed=1; }
  nobrand_xray_test_config "$NOBRAND_HY2_CONFIG_FILE" \
    && nb_doctor_line PASS 'Xray 配置校验' || { nb_doctor_line FAIL 'Xray 配置校验'; failed=1; }
  if openssl ec -in "$NOBRAND_HY2_KEY_FILE" -noout -text 2>/dev/null | grep -q 'ASN1 OID: prime256v1'; then
    key_mode="$(stat -c '%a' "$NOBRAND_HY2_KEY_FILE" 2>/dev/null || true)"
    [ "$key_mode" = 600 ] && nb_doctor_line PASS 'P-256 私钥权限=0600' \
      || { nb_doctor_line FAIL "私钥权限=${key_mode}"; failed=1; }
  else
    nb_doctor_line FAIL 'P-256 私钥'; failed=1
  fi
  if openssl x509 -in "$NOBRAND_HY2_CERT_FILE" -noout >/dev/null 2>&1; then
    cert_cn="$(openssl x509 -in "$NOBRAND_HY2_CERT_FILE" -noout -subject -nameopt RFC2253 2>/dev/null \
      | sed -nE 's/^subject=.*CN=([^,]+).*$/\1/p')"
    expected_sni="$(hysteria2_state_field sni)"
    if [ "$cert_cn" = "$expected_sni" ]; then
      nb_doctor_line PASS "证书 CN=${cert_cn}"
    else
      nb_doctor_line FAIL "证书 CN=${cert_cn:-缺失}，状态 SNI=${expected_sni}"
      failed=1
    fi
  else
    nb_doctor_line FAIL '证书'; failed=1
  fi
  hysteria2_running && nb_doctor_line PASS "服务与 UDP/${port} 监听正常" \
    || { nb_doctor_line FAIL "服务 / 监听异常: UDP/${port}"; failed=1; }
  nb_firewall_binding_owned UDP "$port" && nb_doctor_line PASS "防火墙归属正常: UDP/${port}" \
    || nb_doctor_line INFO "防火墙规则不归 NoBrand 管理（预先存在 / 无本地防火墙）: UDP/${port}"
  mode="$(hysteria2_state_field advertise_mode)"; host="$(hysteria2_state_field advertise_host)"
  advertise_port="$(hysteria2_state_field advertise_port)"
  nb_validate_advertise_endpoint "$host" "$advertise_port" UDP \
    && nb_doctor_line PASS "展示端点 / Display Endpoint 模式=${mode}" \
    || { nb_doctor_line FAIL '展示端点 / Display Endpoint 状态无效'; failed=1; }
  hysteria2_current_share_link >/dev/null \
    && nb_doctor_line PASS 'Hysteria2 URI 生成正常' || { nb_doctor_line FAIL 'URI 生成失败'; failed=1; }
  return "$failed"
}

hysteria2_refresh_runtime_metadata() {
  local tmp runtime
  hysteria2_state_exists || return 0
  runtime="$(nobrand_xray_version)" || return 1
  tmp="$(mktemp_file .json)" || return 1
  jq --arg runtime "$runtime" --arg updated "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '.runtime_version=$runtime | .updated_at=$updated' "$NOBRAND_HY2_STATE_FILE" >"$tmp" \
    && nb_atomic_install_file "$tmp" "$NOBRAND_HY2_STATE_FILE" 0600
  local rc=$?
  rm -f "$tmp"
  return "$rc"
}

hysteria2_upgrade_runtime() {
  nobrand_upgrade_xray_runtime
}

nobrand_run_hy2_action() {
  case "${HY2_ACTION:-menu}" in
    menu) hysteria2_menu_loop ;;
    install) install_hysteria2 ;;
    show) print_hysteria2_result show ;;
    set-endpoint) hysteria2_set_endpoint ;;
    remove) remove_hysteria2_config ;;
    start|stop|restart|status) hysteria2_service_command "$HY2_ACTION" ;;
    doctor) hysteria2_doctor ;;
    upgrade) hysteria2_upgrade_runtime ;;
    help) nobrand_usage ;;
  esac
}
