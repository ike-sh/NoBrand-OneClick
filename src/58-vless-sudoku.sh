# ---------- Plain VLESS + FinalMask Sudoku over TCP ----------

vless_sudoku_state_exists() {
  [ -s "$NOBRAND_VLESS_STATE_FILE" ] && jq empty "$NOBRAND_VLESS_STATE_FILE" >/dev/null 2>&1
}

vless_sudoku_state_field() {
  local field="$1"
  vless_sudoku_state_exists || return 1
  jq -r --arg field "$field" \
    'if has($field) and .[$field] != null then .[$field] else empty end' "$NOBRAND_VLESS_STATE_FILE"
}

vless_sudoku_finalmask_json() {
  local password="$1"
  [[ "$password" =~ ^[0-9A-Fa-f]{32}$ ]] || return 1
  jq -cn --arg password "$password" '{
    tcp: [{
      type: "sudoku",
      settings: {
        password: $password,
        ascii: "prefer_ascii",
        paddingMin: 0,
        paddingMax: 3
      }
    }]
  }'
}

vless_sudoku_valid_uuid() {
  [[ "${1:-}" =~ ^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$ ]]
}

vless_sudoku_generate_uuid() {
  local value=""
  if [ -x "$NOBRAND_XRAY_BIN" ]; then
    value="$("$NOBRAND_XRAY_BIN" uuid 2>/dev/null | tr -d '\r\n' || true)"
  fi
  if ! vless_sudoku_valid_uuid "$value" && command -v uuidgen >/dev/null 2>&1; then
    value="$(uuidgen 2>/dev/null | tr '[:upper:]' '[:lower:]' | tr -d '\r\n' || true)"
  fi
  if ! vless_sudoku_valid_uuid "$value" && [ -r /proc/sys/kernel/random/uuid ]; then
    value="$(tr -d '\r\n' </proc/sys/kernel/random/uuid)"
  fi
  if ! vless_sudoku_valid_uuid "$value" && command -v openssl >/dev/null 2>&1; then
    value="$(openssl rand -hex 16 2>/dev/null \
      | sed -E 's/(.{8})(.{4})(.{4})(.{4})(.{12})/\1-\2-\3-\4-\5/')"
  fi
  vless_sudoku_valid_uuid "$value" || return 1
  printf '%s' "$value"
}

vless_sudoku_generate_server_config() {
  local output="$1" listen="$2" port="$3" uuid="$4" password="$5" finalmask
  finalmask="$(vless_sudoku_finalmask_json "$password")" || return 1
  jq -n --arg tag "$NOBRAND_VLESS_TAG" --arg listen "$listen" --arg port "$port" \
    --arg uuid "$uuid" --argjson finalmask "$finalmask" '
    {
      "log": {"loglevel":"warning"},
      "inbounds": [{
        "tag": $tag,
        "listen": $listen,
        "port": ($port|tonumber),
        "protocol": "vless",
        "settings": {
          "clients": [{"id":$uuid,"email":"vless-sudoku@nobrand"}],
          "decryption": "none"
        },
        "streamSettings": {
          "network": "tcp",
          "security": "none",
          "finalmask": $finalmask
        },
        "sniffing": {
          "enabled": true,
          "destOverride": ["http","tls"]
        }
      }],
      "outbounds": [{"tag":"direct","protocol":"freedom"}],
      "routing": {"rules":[]}
    }
  ' >"$output"
}

vless_sudoku_build_share_link() {
  local uuid="$1" host="$2" port="$3" finalmask_json="$4"
  local host_uri fm_uri name_uri
  vless_sudoku_valid_uuid "$uuid" && [ -n "$host" ] && nb_valid_port "$port" || return 1
  jq -e '.tcp[0].type == "sudoku"' <<<"$finalmask_json" >/dev/null 2>&1 || return 1
  host_uri="$(url_host "$host")"
  fm_uri="$(urlencode "$finalmask_json")" || return 1
  name_uri="$(urlencode 'NoBrand-VLESS-Sudoku')" || return 1
  printf 'vless://%s@%s:%s?type=tcp&security=none&encryption=none&fm=%s#%s' \
    "$uuid" "$host_uri" "$port" "$fm_uri" "$name_uri"
}

vless_sudoku_generate_client_config() {
  local output="$1" host="$2" port="$3" uuid="$4" password="$5"
  local socks_port="${6:-$VLESS_SUDOKU_CLIENT_SOCKS_PORT}" finalmask
  finalmask="$(vless_sudoku_finalmask_json "$password")" || return 1
  { valid_advertise_host "$host" || [ "$host" = YOUR_SERVER_IP ]; } \
    && nb_valid_port "$port" && nb_valid_port "$socks_port" \
    && vless_sudoku_valid_uuid "$uuid" || return 1
  jq -n --arg host "$host" --arg port "$port" --arg uuid "$uuid" \
    --arg socks_port "$socks_port" --argjson finalmask "$finalmask" '
    {
      "log": {"loglevel":"warning"},
      "inbounds": [{
        "tag":"local-socks",
        "listen":"127.0.0.1",
        "port":($socks_port|tonumber),
        "protocol":"socks",
        "settings":{"udp":true}
      }],
      "outbounds": [{
        "tag":"vless-sudoku-out",
        "protocol":"vless",
        "settings": {
          "vnext": [{
            "address":$host,
            "port":($port|tonumber),
            "users":[{"id":$uuid,"encryption":"none"}]
          }]
        },
        "streamSettings": {
          "network":"tcp",
          "security":"none",
          "finalmask":$finalmask
        }
      }]
    }
  ' >"$output"
}

vless_sudoku_forbidden_absent() {
  local file
  for file in "$@"; do
    [ -f "$file" ] || return 1
    if grep -Eqi 'vlessenc|mlkem|xorpub|server_ticket|enc_method|client_rtt|vless_encryption|vless_decryption' "$file"; then
      return 1
    fi
    jq -e '
      ([.. | objects | to_entries[] |
        select((.key | ascii_downcase) |
          test("^(vlessenc|mlkem|xorpub|server_ticket|enc_method|client_rtt|vless_encryption|vless_decryption|decryption_secret|encryption_secret)$"))]
       | length) == 0 and
      ([.. | objects | to_entries[] |
        select(((.key | ascii_downcase) == "encryption" or
                (.key | ascii_downcase) == "decryption") and
               .value != "none")]
       | length) == 0
    ' "$file" >/dev/null 2>&1 || return 1
  done
}

vless_sudoku_state_matches() {
  local state="${1:-$NOBRAND_VLESS_STATE_FILE}"
  jq -e --arg tag "$NOBRAND_VLESS_TAG" '
    .protocol == "vless-sudoku" and
    (.uuid | type == "string" and test("^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$")) and
    (.listen_host | type == "string" and length > 0) and
    (.listen_port | type == "number" and . >= 1 and . <= 65535 and floor == .) and
    .transport == "tcp" and
    ((.advertise_mode == "auto" and .advertise_host == "" and .advertise_port == "") or
     (.advertise_mode == "custom" and (.advertise_host | type == "string" and length > 0) and
      (.advertise_port | type == "number" and . >= 1 and . <= 65535 and floor == .))) and
    .finalmask_mode == "sudoku" and
    (.finalmask_json.tcp | length) == 1 and
    .finalmask_json.tcp[0].type == "sudoku" and
    (.finalmask_json.tcp[0].settings.password | type == "string" and test("^[0-9A-Fa-f]{32}$")) and
    .finalmask_json.tcp[0].settings.ascii == "prefer_ascii" and
    .finalmask_json.tcp[0].settings.paddingMin == 0 and
    .finalmask_json.tcp[0].settings.paddingMax == 3 and
    .tag == $tag and
    (.runtime_version | type == "string" and length > 0) and
    (.link | type == "string" and startswith("vless://") and contains("type=tcp") and
      contains("security=none") and contains("encryption=none") and contains("fm=")) and
    .client_config == "client.json" and
    (.enabled | type) == "boolean" and
    (.created_at | type == "string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")) and
    (.updated_at | type == "string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$"))
  ' "$state" >/dev/null 2>&1 && vless_sudoku_forbidden_absent "$state"
}

vless_sudoku_server_config_matches() {
  local config="${1:-$NOBRAND_VLESS_CONFIG_FILE}" uuid="${2:-}" port="${3:-}" password="${4:-}"
  local listen="${5:-}"
  [ -n "$uuid" ] || uuid="$(vless_sudoku_state_field uuid)" || return 1
  [ -n "$port" ] || port="$(vless_sudoku_state_field listen_port)" || return 1
  [ -n "$password" ] || password="$(jq -r '.finalmask_json.tcp[0].settings.password // empty' "$NOBRAND_VLESS_STATE_FILE")"
  [ -n "$listen" ] || listen="$(vless_sudoku_state_field listen_host)" || return 1
  jq -e --arg tag "$NOBRAND_VLESS_TAG" --arg uuid "$uuid" --arg port "$port" \
    --arg password "$password" --arg listen "$listen" '
    (.inbounds | length) == 1 and
    .inbounds[0].tag == $tag and
    .inbounds[0].listen == $listen and
    .inbounds[0].protocol == "vless" and
    .inbounds[0].port == ($port|tonumber) and
    .inbounds[0].settings.clients == [{"id":$uuid,"email":"vless-sudoku@nobrand"}] and
    .inbounds[0].settings.decryption == "none" and
    .inbounds[0].streamSettings.network == "tcp" and
    .inbounds[0].streamSettings.security == "none" and
    .inbounds[0].streamSettings.finalmask.tcp == [{
      "type":"sudoku",
      "settings":{
        "password":$password,
        "ascii":"prefer_ascii",
        "paddingMin":0,
        "paddingMax":3
      }
    }]
  ' "$config" >/dev/null 2>&1 && vless_sudoku_forbidden_absent "$config"
}

vless_sudoku_client_config_matches() {
  local config="${1:-$NOBRAND_VLESS_CLIENT_FILE}" host="${2:-}" port="${3:-}"
  local uuid="${4:-}" password="${5:-}" ingress_profile_id
  ingress_profile_id="$(vless_sudoku_state_field ingress_profile_id 2>/dev/null || true)"
  [ -n "$ingress_profile_id" ] || ingress_profile_id="$NOBRAND_LEGACY_INGRESS_PROFILE_ID"
  [ -n "$host" ] || {
    local mode advertise_host
    mode="$(vless_sudoku_state_field advertise_mode)" || return 1
    advertise_host="$(vless_sudoku_state_field advertise_host)"
    host="$(nb_effective_advertise_host "$mode" "$advertise_host" "$ingress_profile_id")"
  }
  [ -n "$port" ] || {
    local mode advertise_port listen_port
    mode="$(vless_sudoku_state_field advertise_mode)" || return 1
    advertise_port="$(vless_sudoku_state_field advertise_port)"
    listen_port="$(vless_sudoku_state_field listen_port)"
    port="$(nb_effective_advertise_port "$mode" "$advertise_port" "$listen_port" "$ingress_profile_id")"
  }
  [ -n "$uuid" ] || uuid="$(vless_sudoku_state_field uuid)" || return 1
  [ -n "$password" ] \
    || password="$(jq -r '.finalmask_json.tcp[0].settings.password // empty' "$NOBRAND_VLESS_STATE_FILE")"
  jq -e --arg host "$host" --arg port "$port" --arg uuid "$uuid" --arg password "$password" '
    .outbounds[0].protocol == "vless" and
    .outbounds[0].settings.vnext[0].address == $host and
    .outbounds[0].settings.vnext[0].port == ($port|tonumber) and
    .outbounds[0].settings.vnext[0].users == [{"id":$uuid,"encryption":"none"}] and
    .outbounds[0].streamSettings.network == "tcp" and
    .outbounds[0].streamSettings.security == "none" and
    .outbounds[0].streamSettings.finalmask.tcp == [{
      "type":"sudoku",
      "settings":{
        "password":$password,
        "ascii":"prefer_ascii",
        "paddingMin":0,
        "paddingMax":3
      }
    }]
  ' "$config" >/dev/null 2>&1 && vless_sudoku_forbidden_absent "$config"
}

vless_sudoku_current_share_link() {
  local uuid listen_port mode advertise_host advertise_port ingress_profile_id host port finalmask
  vless_sudoku_state_exists || return 1
  uuid="$(vless_sudoku_state_field uuid)"
  listen_port="$(vless_sudoku_state_field listen_port)"
  mode="$(vless_sudoku_state_field advertise_mode)"
  advertise_host="$(vless_sudoku_state_field advertise_host)"
  advertise_port="$(vless_sudoku_state_field advertise_port)"
  ingress_profile_id="$(vless_sudoku_state_field ingress_profile_id 2>/dev/null || true)"
  host="$(nb_effective_advertise_host "$mode" "$advertise_host" "$ingress_profile_id")"
  port="$(nb_effective_advertise_port "$mode" "$advertise_port" "$listen_port" "$ingress_profile_id")"
  finalmask="$(jq -c '.finalmask_json' "$NOBRAND_VLESS_STATE_FILE")" || return 1
  vless_sudoku_build_share_link "$uuid" "$host" "$port" "$finalmask"
}

vless_sudoku_generate_state() {
  local output="$1" listen="$2" port="$3" uuid="$4" password="$5"
  local advertise_mode="$6" advertise_host="$7" advertise_port="$8" created_at="${9:-}"
  local ingress_profile_id="${10:-}"
  local updated_at runtime_version finalmask effective_host effective_port link
  [ -n "$created_at" ] || created_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  updated_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  runtime_version="$(nobrand_xray_version 2>/dev/null || printf unknown)"
  finalmask="$(vless_sudoku_finalmask_json "$password")" || return 1
  effective_host="$(nb_effective_advertise_host "$advertise_mode" "$advertise_host" "$ingress_profile_id")"
  effective_port="$(nb_effective_advertise_port "$advertise_mode" "$advertise_port" "$port" "$ingress_profile_id")"
  link="$(vless_sudoku_build_share_link "$uuid" "$effective_host" "$effective_port" "$finalmask")" || return 1
  jq -n --arg uuid "$uuid" --arg listen "$listen" --arg port "$port" \
    --arg mode "$advertise_mode" --arg advertise_host "$advertise_host" \
    --arg advertise_port "$advertise_port" --arg tag "$NOBRAND_VLESS_TAG" \
    --arg runtime "$runtime_version" --arg link "$link" --arg created "$created_at" \
    --arg updated "$updated_at" --argjson finalmask "$finalmask" --arg ingress_profile_id "$ingress_profile_id" '
    {
      "protocol":"vless-sudoku",
      "uuid":$uuid,
      "listen_host":$listen,
      "listen_port":($port|tonumber),
      "transport":"tcp",
      "advertise_mode":$mode,
      "advertise_host":$advertise_host,
      "advertise_port":(if $advertise_port=="" then "" else ($advertise_port|tonumber) end),
      "finalmask_mode":"sudoku",
      "finalmask_json":$finalmask,
      "tag":$tag,
      "runtime_version":$runtime,
      "link":$link,
      "client_config":"client.json",
      "enabled":true,
      "created_at":$created,
      "updated_at":$updated
    }
    + if $ingress_profile_id=="" then {} else {ingress_profile_id:$ingress_profile_id} end
  ' >"$output"
}

vless_sudoku_snapshot_file() {
  local source="$1" destination="$2"
  if [ -e "$source" ]; then cp -a "$source" "$destination"; else printf absent >"${destination}.absent"; fi
}

vless_sudoku_restore_snapshot_file() {
  local snapshot="$1" destination="$2"
  if [ -f "${snapshot}.absent" ]; then
    rm -f "$destination"
  elif [ -e "$snapshot" ]; then
    mkdir -p "$(dirname "$destination")"
    cp -a "$snapshot" "$destination"
  fi
}

vless_sudoku_configure_requests() {
  local interactive="${1:-0}" old_port="" old_password="" conflict_owner=""
  if vless_sudoku_state_exists && [ "${INGRESS_PROFILE_CLI:-0}" -eq 0 ]; then
    INGRESS_PROFILE_ID="$(vless_sudoku_state_field ingress_profile_id 2>/dev/null || true)"
    [ -n "$INGRESS_PROFILE_ID" ] || INGRESS_PROFILE_ID="$NOBRAND_LEGACY_INGRESS_PROFILE_ID"
  else
    nb_prepare_ingress_request || return 1
  fi
  nb_prepare_ingress_deployment "$INGRESS_PROFILE_ID" native-bind \
    || die 'VLESS Sudoku 无法绑定所选 Ingress 的 Strict 本地地址'
  VLESS_SUDOKU_LISTEN="$INGRESS_LISTEN_HOST"
  if vless_sudoku_state_exists; then
    old_port="$(vless_sudoku_state_field listen_port 2>/dev/null || true)"
    VLESS_SUDOKU_UUID="$(vless_sudoku_state_field uuid 2>/dev/null || true)"
    old_password="$(jq -r '.finalmask_json.tcp[0].settings.password // empty' "$NOBRAND_VLESS_STATE_FILE" 2>/dev/null)"
  fi
  if [ -z "${PORT:-}" ]; then
    PORT="$(nb_select_available_port TCP "$INGRESS_PROFILE_ID")" \
      || die '所选入口配置没有可用 VLESS Sudoku TCP 自动端口；manual-only 必须显式使用 --port'
    PORT_AUTO_SELECTED=1
  else
    nb_valid_port "$PORT" || die 'VLESS Sudoku 端口必须是 1-65535'
    PORT="$(normalize_uint "$PORT")"
    nb_warn_if_outside_recommended_range "$PORT" "$INGRESS_PROFILE_ID"
    if [ "$PORT" != "$old_port" ] \
       && ! nb_port_available_for_profile "$PORT" TCP "$INGRESS_PROFILE_ID" 'vless-sudoku:default'; then
      warn "VLESS Sudoku TCP/${PORT} 已占用"
      nb_describe_port_conflict TCP "$PORT"
      return 1
    fi
  fi
  if [ "$interactive" -eq 1 ] && [ "${ADVERTISE_CLI:-0}" -eq 0 ]; then
    nb_collect_advertise_endpoint_interactive 'VLESS Sudoku' "$PORT"
  else
    nb_require_explicit_endpoint_noninteractive
  fi
  nb_validate_advertise_endpoint "$ADVERTISE_HOST" "$ADVERTISE_PORT" TCP \
    || die 'VLESS Sudoku Display Endpoint 无效'
  if [ -n "$ADVERTISE_HOST" ]; then
    conflict_owner="$(nb_endpoint_conflict_owner TCP "$ADVERTISE_HOST" "$ADVERTISE_PORT" \
      'vless-sudoku:default' 2>/dev/null || true)"
    [ -z "$conflict_owner" ] || die "VLESS Sudoku Display Endpoint 与 ${conflict_owner} 冲突"
  fi
  vless_sudoku_valid_uuid "$VLESS_SUDOKU_UUID" \
    || VLESS_SUDOKU_UUID="$(vless_sudoku_generate_uuid)" \
    || die '无法生成 VLESS UUID'
  if [[ "$old_password" =~ ^[0-9A-Fa-f]{32}$ ]]; then
    VLESS_SUDOKU_PASSWORD="$old_password"
  else
    VLESS_SUDOKU_PASSWORD="$(openssl rand -hex 16 2>/dev/null || true)"
    [[ "$VLESS_SUDOKU_PASSWORD" =~ ^[0-9A-Fa-f]{32}$ ]] \
      || die '无法生成 FinalMask Sudoku 密码'
  fi
}

vless_sudoku_install_rollback() {
  local snapshot="$1" was_active="$2" new_binding_owned="$3"
  nobrand_vless_sudoku_service_action stop >/dev/null 2>&1 || true
  [ "$new_binding_owned" -eq 0 ] \
    || nb_firewall_close_pairs "TCP|${PORT}" >/dev/null 2>&1 || true
  vless_sudoku_restore_snapshot_file "$snapshot/config" "$NOBRAND_VLESS_CONFIG_FILE"
  vless_sudoku_restore_snapshot_file "$snapshot/state" "$NOBRAND_VLESS_STATE_FILE"
  vless_sudoku_restore_snapshot_file "$snapshot/client" "$NOBRAND_VLESS_CLIENT_FILE"
  vless_sudoku_restore_snapshot_file "$snapshot/service-systemd" "$NOBRAND_VLESS_SYSTEMD_SERVICE"
  vless_sudoku_restore_snapshot_file "$snapshot/service-openrc" "$NOBRAND_VLESS_OPENRC_SERVICE"
  vless_sudoku_restore_snapshot_file "$snapshot/xray" "$NOBRAND_XRAY_BIN"
  [ "$(nb_service_manager)" != systemd ] || systemctl daemon-reload >/dev/null 2>&1 || true
  [ "$was_active" -eq 0 ] \
    || nobrand_vless_sudoku_service_action start >/dev/null 2>&1 || true
}

install_vless_sudoku() {
  local interactive=0 snapshot config_tmp state_tmp client_tmp advertise_mode
  local old_port="" old_created="" was_active=0 binding_was_owned=0 binding_now_owned=0
  [ "${YES:-0}" -eq 1 ] || interactive=1
  nobrand_prepare_common
  admin_lock_acquire || return 1
  snapshot="$(mktemp_dir)" || { admin_lock_release; return 1; }
  vless_sudoku_snapshot_file "$NOBRAND_VLESS_CONFIG_FILE" "$snapshot/config"
  vless_sudoku_snapshot_file "$NOBRAND_VLESS_STATE_FILE" "$snapshot/state"
  vless_sudoku_snapshot_file "$NOBRAND_VLESS_CLIENT_FILE" "$snapshot/client"
  vless_sudoku_snapshot_file "$NOBRAND_VLESS_SYSTEMD_SERVICE" "$snapshot/service-systemd"
  vless_sudoku_snapshot_file "$NOBRAND_VLESS_OPENRC_SERVICE" "$snapshot/service-openrc"
  vless_sudoku_snapshot_file "$NOBRAND_XRAY_BIN" "$snapshot/xray"
  nobrand_vless_sudoku_service_active && was_active=1
  if vless_sudoku_state_exists; then
    old_port="$(vless_sudoku_state_field listen_port 2>/dev/null || true)"
    old_created="$(vless_sudoku_state_field created_at 2>/dev/null || true)"
  fi
  if ! nobrand_install_xray_runtime 0 || ! vless_sudoku_configure_requests "$interactive"; then
    vless_sudoku_install_rollback "$snapshot" "$was_active" 0
    rm -rf -- "$snapshot"
    admin_lock_release
    return 1
  fi
  nb_firewall_binding_owned TCP "$PORT" && binding_was_owned=1
  if [ "$was_active" -eq 1 ]; then
    nobrand_vless_sudoku_service_action stop || {
      vless_sudoku_install_rollback "$snapshot" "$was_active" 0
      rm -rf -- "$snapshot"; admin_lock_release; return 1;
    }
  fi
  if ! nb_port_available_for_profile "$PORT" TCP "$INGRESS_PROFILE_ID" 'vless-sudoku:default'; then
    warn "提交前发现 TCP/${PORT} 已被其它进程占用"
    nb_describe_port_conflict TCP "$PORT"
    vless_sudoku_install_rollback "$snapshot" "$was_active" 0
    rm -rf -- "$snapshot"; admin_lock_release; return 1
  fi
  config_tmp="$(mktemp_file .json)" || {
    vless_sudoku_install_rollback "$snapshot" "$was_active" 0
    rm -rf -- "$snapshot"; admin_lock_release; return 1;
  }
  state_tmp="$(mktemp_file .json)" || {
    rm -f "$config_tmp"; vless_sudoku_install_rollback "$snapshot" "$was_active" 0
    rm -rf -- "$snapshot"; admin_lock_release; return 1;
  }
  client_tmp="$(mktemp_file .json)" || {
    rm -f "$config_tmp" "$state_tmp"; vless_sudoku_install_rollback "$snapshot" "$was_active" 0
    rm -rf -- "$snapshot"; admin_lock_release; return 1;
  }
  advertise_mode="$(nb_endpoint_mode_from_values "$ADVERTISE_HOST")"
  local effective_host effective_port
  effective_host="$(nb_effective_advertise_host "$advertise_mode" "$ADVERTISE_HOST" "$INGRESS_PROFILE_ID")"
  effective_port="$(nb_effective_advertise_port "$advertise_mode" "$ADVERTISE_PORT" "$PORT" "$INGRESS_PROFILE_ID")"
  if ! vless_sudoku_generate_server_config "$config_tmp" "$VLESS_SUDOKU_LISTEN" "$PORT" \
       "$VLESS_SUDOKU_UUID" "$VLESS_SUDOKU_PASSWORD" \
     || ! nobrand_xray_test_config "$config_tmp" \
     || ! vless_sudoku_server_config_matches "$config_tmp" "$VLESS_SUDOKU_UUID" "$PORT" \
       "$VLESS_SUDOKU_PASSWORD" "$VLESS_SUDOKU_LISTEN" \
     || ! vless_sudoku_generate_state "$state_tmp" "$VLESS_SUDOKU_LISTEN" "$PORT" \
       "$VLESS_SUDOKU_UUID" "$VLESS_SUDOKU_PASSWORD" "$advertise_mode" \
       "$ADVERTISE_HOST" "$ADVERTISE_PORT" "$old_created" "$INGRESS_PROFILE_ID" \
     || ! nb_ingress_stamp_state_file "$state_tmp" "$INGRESS_PROFILE_ID" native-bind \
     || ! vless_sudoku_generate_client_config "$client_tmp" "$effective_host" "$effective_port" \
       "$VLESS_SUDOKU_UUID" "$VLESS_SUDOKU_PASSWORD" \
     || ! vless_sudoku_client_config_matches "$client_tmp" "$effective_host" "$effective_port" \
       "$VLESS_SUDOKU_UUID" "$VLESS_SUDOKU_PASSWORD" \
     || ! vless_sudoku_state_matches "$state_tmp" \
     || ! nb_atomic_install_file "$config_tmp" "$NOBRAND_VLESS_CONFIG_FILE" 0600 \
     || ! nobrand_write_vless_sudoku_service \
     || ! nb_firewall_open_pairs "TCP|${PORT}"; then
    rm -f "$config_tmp" "$state_tmp" "$client_tmp"
    nb_firewall_binding_owned TCP "$PORT" \
      && [ "$binding_was_owned" -eq 0 ] && binding_now_owned=1
    vless_sudoku_install_rollback "$snapshot" "$was_active" "$binding_now_owned"
    rm -rf -- "$snapshot"; admin_lock_release; return 1
  fi
  rm -f "$config_tmp"
  nb_firewall_binding_owned TCP "$PORT" \
    && [ "$binding_was_owned" -eq 0 ] && binding_now_owned=1
  local service_action=start
  [ "$was_active" -eq 0 ] || service_action=restart
  if ! nobrand_vless_sudoku_service_action "$service_action" \
     || ! nobrand_vless_sudoku_service_active \
     || ! nb_wait_for_enforced_listener "$INGRESS_ENFORCEMENT_RESOLVED" "$INGRESS_ENFORCEMENT_METHOD" \
          TCP "$PORT" "$INGRESS_LOCAL_ADDRESS" 'vless-sudoku:default' 25 \
     || ! nb_atomic_install_file "$client_tmp" "$NOBRAND_VLESS_CLIENT_FILE" 0600 \
     || ! nb_atomic_install_file "$state_tmp" "$NOBRAND_VLESS_STATE_FILE" 0600; then
    rm -f "$state_tmp" "$client_tmp"
    vless_sudoku_install_rollback "$snapshot" "$was_active" "$binding_now_owned"
    rm -rf -- "$snapshot"; admin_lock_release
    warn 'VLESS Sudoku 服务、listener 或 state 验收失败，已回滚'
    return 1
  fi
  rm -f "$state_tmp" "$client_tmp"
  if [ -n "$old_port" ] && [ "$old_port" != "$PORT" ]; then
    nb_firewall_close_pairs "TCP|${old_port}" || true
  fi
  nobrand_install_manager_script || true
  rm -rf -- "$snapshot"
  admin_lock_release
  print_vless_sudoku_result install
}

vless_sudoku_set_endpoint() {
  local interactive=0 state_tmp client_tmp snapshot mode owner uuid password host port link finalmask ingress_profile_id
  require_root
  vless_sudoku_state_exists || die 'VLESS Sudoku 未安装'
  [ "${YES:-0}" -eq 1 ] || interactive=1
  PORT="$(vless_sudoku_state_field listen_port)"
  if [ "$interactive" -eq 1 ] && [ "${ADVERTISE_CLI:-0}" -eq 0 ]; then
    nb_collect_advertise_endpoint_interactive 'VLESS Sudoku' "$PORT"
  else
    nb_require_explicit_endpoint_noninteractive
  fi
  nb_validate_advertise_endpoint "$ADVERTISE_HOST" "$ADVERTISE_PORT" TCP \
    || die 'Display Endpoint 无效'
  if [ -n "$ADVERTISE_HOST" ]; then
    owner="$(nb_endpoint_conflict_owner TCP "$ADVERTISE_HOST" "$ADVERTISE_PORT" \
      'vless-sudoku:default' 2>/dev/null || true)"
    [ -z "$owner" ] || die "Display Endpoint 与 ${owner} 冲突"
  fi
  admin_lock_acquire || return 1
  snapshot="$(mktemp_dir)" || { admin_lock_release; return 1; }
  vless_sudoku_snapshot_file "$NOBRAND_VLESS_STATE_FILE" "$snapshot/state"
  vless_sudoku_snapshot_file "$NOBRAND_VLESS_CLIENT_FILE" "$snapshot/client"
  state_tmp="$(mktemp_file .json)" || { rm -rf -- "$snapshot"; admin_lock_release; return 1; }
  client_tmp="$(mktemp_file .json)" || {
    rm -f "$state_tmp"; rm -rf -- "$snapshot"; admin_lock_release; return 1;
  }
  mode="$(nb_endpoint_mode_from_values "$ADVERTISE_HOST")"
  uuid="$(vless_sudoku_state_field uuid)"
  password="$(jq -r '.finalmask_json.tcp[0].settings.password' "$NOBRAND_VLESS_STATE_FILE")"
  ingress_profile_id="$(vless_sudoku_state_field ingress_profile_id 2>/dev/null || true)"
  [ -n "$ingress_profile_id" ] || ingress_profile_id="$NOBRAND_LEGACY_INGRESS_PROFILE_ID"
  finalmask="$(vless_sudoku_finalmask_json "$password")" || {
    rm -f "$state_tmp" "$client_tmp"; rm -rf -- "$snapshot"; admin_lock_release; return 1;
  }
  host="$(nb_effective_advertise_host "$mode" "$ADVERTISE_HOST" "$ingress_profile_id")"
  port="$(nb_effective_advertise_port "$mode" "$ADVERTISE_PORT" "$PORT" "$ingress_profile_id")"
  link="$(vless_sudoku_build_share_link "$uuid" "$host" "$port" "$finalmask")" || {
    rm -f "$state_tmp" "$client_tmp"; rm -rf -- "$snapshot"; admin_lock_release; return 1;
  }
  if ! jq --arg mode "$mode" --arg host "$ADVERTISE_HOST" --arg port "$ADVERTISE_PORT" \
      --arg link "$link" --arg updated "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
        .advertise_mode=$mode |
        .advertise_host=$host |
        .advertise_port=(if $port=="" then "" else ($port|tonumber) end) |
        .link=$link |
        .updated_at=$updated
      ' "$NOBRAND_VLESS_STATE_FILE" >"$state_tmp" \
     || ! vless_sudoku_generate_client_config "$client_tmp" "$host" "$port" "$uuid" "$password" \
     || ! vless_sudoku_client_config_matches "$client_tmp" "$host" "$port" \
     || ! nb_atomic_install_file "$client_tmp" "$NOBRAND_VLESS_CLIENT_FILE" 0600 \
     || ! nb_atomic_install_file "$state_tmp" "$NOBRAND_VLESS_STATE_FILE" 0600; then
    vless_sudoku_restore_snapshot_file "$snapshot/state" "$NOBRAND_VLESS_STATE_FILE"
    vless_sudoku_restore_snapshot_file "$snapshot/client" "$NOBRAND_VLESS_CLIENT_FILE"
    rm -f "$state_tmp" "$client_tmp"; rm -rf -- "$snapshot"; admin_lock_release
    return 1
  fi
  rm -f "$state_tmp" "$client_tmp"; rm -rf -- "$snapshot"
  # 本函数禁止调用 service、firewall 或 server config writer。
  admin_lock_release
  t 'VLESS Sudoku 客户端展示入口已更新；server config/listener/PID/service/firewall 均未改变' \
    'VLESS Sudoku display endpoint updated; server config/listener/PID/service/firewall are unchanged'
  print_vless_sudoku_result show
}

vless_sudoku_running() {
  local port policy method address
  vless_sudoku_state_exists || return 1
  port="$(vless_sudoku_state_field listen_port)"
  policy="$(vless_sudoku_state_field ingress_enforcement 2>/dev/null || printf permissive)"
  method="$(vless_sudoku_state_field ingress_enforcement_method 2>/dev/null || printf wildcard)"
  address="$(vless_sudoku_state_field ingress_local_address 2>/dev/null || true)"
  nobrand_vless_sudoku_service_active \
    && nb_wait_for_enforced_listener "$policy" "$method" TCP "$port" "$address" 'vless-sudoku:default' 1
}

vless_sudoku_apply_ingress_enforcement() {
  local profile_id port uuid password candidate_state candidate_config snapshot was_active=0 rc=0
  vless_sudoku_state_exists || return 1
  profile_id="$(vless_sudoku_state_field ingress_profile_id 2>/dev/null || true)"
  [ -n "$profile_id" ] || profile_id="$NOBRAND_LEGACY_INGRESS_PROFILE_ID"
  nb_prepare_ingress_deployment "$profile_id" native-bind || return 1
  port="$(vless_sudoku_state_field listen_port)"
  uuid="$(vless_sudoku_state_field uuid)"
  password="$(jq -r '.finalmask_json.tcp[0].settings.password // empty' "$NOBRAND_VLESS_STATE_FILE")"
  candidate_state="$(mktemp_file .vless-ingress-state)" || return 1
  candidate_config="$(mktemp_file .vless-ingress-config.json)" || { rm -f "$candidate_state"; return 1; }
  snapshot="$(mktemp_dir)" || { rm -f "$candidate_state" "$candidate_config"; return 1; }
  cp -a "$NOBRAND_VLESS_STATE_FILE" "$snapshot/state" \
    && cp -a "$NOBRAND_VLESS_CONFIG_FILE" "$snapshot/config" || rc=1
  if [ "$rc" -eq 0 ]; then
    jq --arg listen "$INGRESS_LISTEN_HOST" '.listen_host=$listen' "$NOBRAND_VLESS_STATE_FILE" >"$candidate_state" \
      && nb_ingress_stamp_state_file "$candidate_state" "$profile_id" native-bind \
      && vless_sudoku_state_matches "$candidate_state" \
      && vless_sudoku_generate_server_config "$candidate_config" "$INGRESS_LISTEN_HOST" "$port" "$uuid" "$password" \
      && vless_sudoku_server_config_matches "$candidate_config" "$uuid" "$port" "$password" "$INGRESS_LISTEN_HOST" \
      && nobrand_xray_test_config "$candidate_config" || rc=1
  fi
  nobrand_vless_sudoku_service_active && was_active=1
  if [ "$rc" -eq 0 ]; then
    nb_atomic_install_file "$candidate_config" "$NOBRAND_VLESS_CONFIG_FILE" 0600 \
      && nb_atomic_install_file "$candidate_state" "$NOBRAND_VLESS_STATE_FILE" 0600 || rc=1
  fi
  if [ "$rc" -eq 0 ] && [ "$was_active" -eq 1 ]; then
    [ "${NOBRAND_TEST_INGRESS_SERVICE_FAIL:-0}" -eq 0 ] \
      && nobrand_vless_sudoku_service_action restart \
      && [ "${NOBRAND_TEST_INGRESS_LISTENER_FAIL:-0}" -eq 0 ] \
      && vless_sudoku_running || rc=1
  fi
  if [ "$rc" -ne 0 ]; then
    nb_atomic_install_file "$snapshot/config" "$NOBRAND_VLESS_CONFIG_FILE" 0600 >/dev/null 2>&1 || true
    nb_atomic_install_file "$snapshot/state" "$NOBRAND_VLESS_STATE_FILE" 0600 >/dev/null 2>&1 || true
    if [ "$was_active" -eq 1 ]; then
      nobrand_vless_sudoku_service_action restart >/dev/null 2>&1 \
        && vless_sudoku_running >/dev/null 2>&1 || true
    else
      nobrand_vless_sudoku_service_action stop >/dev/null 2>&1 || true
    fi
  fi
  rm -f "$candidate_state" "$candidate_config"
  rm -rf -- "$snapshot"
  return "$rc"
}

vless_sudoku_state_set_enabled() {
  local enabled="$1" tmp
  tmp="$(mktemp_file .json)" || return 1
  if ! jq --argjson enabled "$enabled" --arg updated "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      '.enabled=$enabled | .updated_at=$updated' "$NOBRAND_VLESS_STATE_FILE" >"$tmp" \
     || ! nb_atomic_install_file "$tmp" "$NOBRAND_VLESS_STATE_FILE" 0600; then
    rm -f "$tmp"
    return 1
  fi
  rm -f "$tmp"
}

vless_sudoku_node_rows() {
  local mode advertise_host advertise_port listen_port host port status
  vless_sudoku_state_exists || return 0
  mode="$(vless_sudoku_state_field advertise_mode)"
  advertise_host="$(vless_sudoku_state_field advertise_host)"
  advertise_port="$(vless_sudoku_state_field advertise_port)"
  listen_port="$(vless_sudoku_state_field listen_port)"
  host="$(nb_effective_advertise_host "$mode" "$advertise_host" "$(vless_sudoku_state_field ingress_profile_id 2>/dev/null || true)")"
  port="$(nb_effective_advertise_port "$mode" "$advertise_port" "$listen_port" "$(vless_sudoku_state_field ingress_profile_id 2>/dev/null || true)")"
  status=Stopped; vless_sudoku_running && status=Running
  printf 'VLESS/Sudoku|sudoku|%s:%s/TCP|%s|TCP\n' "$host" "$port" "$status"
}

print_vless_sudoku_result() {
  local context="${1:-show}" uuid listen_host listen_port mode advertise_host advertise_port
  local host port status link finalmask password mode_label
  vless_sudoku_state_exists || { t 'VLESS Sudoku 未安装' 'VLESS Sudoku is not installed'; return 0; }
  uuid="$(vless_sudoku_state_field uuid)"
  listen_host="$(vless_sudoku_state_field listen_host)"
  listen_port="$(vless_sudoku_state_field listen_port)"
  mode="$(vless_sudoku_state_field advertise_mode)"
  advertise_host="$(vless_sudoku_state_field advertise_host)"
  advertise_port="$(vless_sudoku_state_field advertise_port)"
  host="$(nb_effective_advertise_host "$mode" "$advertise_host" "$(vless_sudoku_state_field ingress_profile_id 2>/dev/null || true)")"
  port="$(nb_effective_advertise_port "$mode" "$advertise_port" "$listen_port" "$(vless_sudoku_state_field ingress_profile_id 2>/dev/null || true)")"
  finalmask="$(jq -c '.finalmask_json' "$NOBRAND_VLESS_STATE_FILE")"
  password="$(jq -r '.finalmask_json.tcp[0].settings.password' "$NOBRAND_VLESS_STATE_FILE")"
  link="$(vless_sudoku_current_share_link)"
  status=已停止; vless_sudoku_running && status=运行中
  mode_label="$mode"; case "$mode" in auto) mode_label='自动' ;; custom) mode_label='自定义' ;; esac
  nobrand_print_banner
  msg ''
  [ "$context" != install ] || t '部署完成' 'Deployment complete'
  msg '协议        VLESS + FinalMask + Sudoku'
  msg '传输        TCP'
  msg 'VLESS Encryption：未使用（NOT USED）'
  msg "状态        ${status}"
  msg ''
  msg '实际监听 / Actual Listener'
  msg "  地址      ${listen_host}"
  msg "  端口      ${listen_port}"
  msg ''
  msg '网络入口 / Ingress'
  msg "  入口配置 / Ingress Profile  $(nb_ingress_profile_name "$(vless_sudoku_state_field ingress_profile_id 2>/dev/null || true)")"
  msg ''
  msg '展示端点 / Display Endpoint'
  msg "  主机      ${host}"
  msg "  端口      ${port}"
  msg "  模式      ${mode_label}"
  msg ''
  msg '认证与 FinalMask'
  msg "  UUID      ${uuid}"
  msg "  模式      sudoku"
  msg "  密码      ${password}"
  msg "  JSON      ${finalmask}"
  msg ''
  msg "Xray 客户端 JSON: ${NOBRAND_VLESS_CLIENT_FILE}"
  msg '========================================'
  msg "$link"
}

vless_sudoku_service_command() {
  local action="$1" port was_enabled
  vless_sudoku_state_exists || die 'VLESS Sudoku 未安装'
  port="$(vless_sudoku_state_field listen_port)"
  was_enabled="$(vless_sudoku_state_field enabled)"
  case "$action" in
    start|restart)
      nobrand_xray_test_config "$NOBRAND_VLESS_CONFIG_FILE" || return 1
      nb_firewall_open_pairs "TCP|${port}" || return 1
      if ! nobrand_vless_sudoku_service_action "$action" \
         || ! vless_sudoku_running \
         || ! vless_sudoku_state_set_enabled true; then
        nobrand_vless_sudoku_service_action stop >/dev/null 2>&1 || true
        [ "$was_enabled" = true ] || vless_sudoku_state_set_enabled false >/dev/null 2>&1 || true
        return 1
      fi
      ;;
    stop)
      nobrand_vless_sudoku_service_action stop || return 1
      if ! vless_sudoku_state_set_enabled false; then
        [ "$was_enabled" != true ] \
          || nobrand_vless_sudoku_service_action start >/dev/null 2>&1 || true
        return 1
      fi
      ;;
    status)
      if vless_sudoku_running; then msg 'VLESS Sudoku：运行中'; else msg 'VLESS Sudoku：已停止'; return 1; fi
      ;;
  esac
}

remove_vless_sudoku_config() {
  local port
  require_root
  vless_sudoku_state_exists \
    || { t 'VLESS Sudoku 未安装' 'VLESS Sudoku is not installed'; return 0; }
  port="$(vless_sudoku_state_field listen_port)"
  admin_lock_acquire || return 1
  nobrand_remove_vless_sudoku_service || { admin_lock_release; return 1; }
  nb_firewall_close_pairs "TCP|${port}" || { admin_lock_release; return 1; }
  rm -f "$NOBRAND_VLESS_CONFIG_FILE" "$NOBRAND_VLESS_STATE_FILE" "$NOBRAND_VLESS_CLIENT_FILE"
  rmdir "$NOBRAND_VLESS_CONFIG_DIR" "$NOBRAND_VLESS_STATE_DIR" 2>/dev/null || true
  admin_lock_release
  t '已删除 NoBrand VLESS Sudoku；共享 Xray、HY2、Mieru、Snell 与外部 Xray 均保留' \
    'Removed NoBrand VLESS Sudoku; shared Xray, HY2, Mieru, Snell, and external Xray are preserved'
}

vless_sudoku_doctor() {
  local failed=0 port mode host advertise_port uuid password cached_link current_link
  if ! vless_sudoku_state_exists; then
    nb_doctor_line INFO 'VLESS Sudoku 未安装'
    return 0
  fi
  port="$(vless_sudoku_state_field listen_port)"
  uuid="$(vless_sudoku_state_field uuid)"
  password="$(jq -r '.finalmask_json.tcp[0].settings.password // empty' "$NOBRAND_VLESS_STATE_FILE")"
  [ -x "$NOBRAND_XRAY_BIN" ] \
    && nb_doctor_line PASS "Xray $(nobrand_xray_version 2>/dev/null || printf '未知版本')" \
    || { nb_doctor_line FAIL 'NoBrand Xray 可执行文件'; failed=1; }
  vless_sudoku_state_matches \
    && nb_doctor_line PASS '状态 schema 与 VLESS 元数据有效' \
    || { nb_doctor_line FAIL '状态 schema / 元数据无效'; failed=1; }
  vless_sudoku_server_config_matches "$NOBRAND_VLESS_CONFIG_FILE" "$uuid" "$port" "$password" \
    && nb_doctor_line PASS 'VLESS + TCP + FinalMask Sudoku 配置有效' \
    || { nb_doctor_line FAIL '服务端配置语义无效'; failed=1; }
  nobrand_xray_test_config "$NOBRAND_VLESS_CONFIG_FILE" \
    && nb_doctor_line PASS 'Xray 配置校验' \
    || { nb_doctor_line FAIL 'Xray 配置校验'; failed=1; }
  vless_sudoku_forbidden_absent "$NOBRAND_VLESS_CONFIG_FILE" \
    "$NOBRAND_VLESS_STATE_FILE" "$NOBRAND_VLESS_CLIENT_FILE" \
    && nb_doctor_line PASS 'VLESS Encryption 未使用' \
    || { nb_doctor_line FAIL '检测到禁用的 Encryption 依赖或字段'; failed=1; }
  vless_sudoku_client_config_matches \
    && nb_doctor_line PASS 'Xray 客户端 JSON' \
    || { nb_doctor_line FAIL 'Xray 客户端 JSON'; failed=1; }
  vless_sudoku_running \
    && nb_doctor_line PASS "服务与 TCP/${port} 监听正常" \
    || { nb_doctor_line FAIL "服务 / 监听异常: TCP/${port}"; failed=1; }
  nb_firewall_binding_owned TCP "$port" \
    && nb_doctor_line PASS "防火墙归属正常: TCP/${port}" \
    || nb_doctor_line INFO "防火墙规则不归 NoBrand 管理（预先存在 / 无本地防火墙）: TCP/${port}"
  mode="$(vless_sudoku_state_field advertise_mode)"
  host="$(vless_sudoku_state_field advertise_host)"
  advertise_port="$(vless_sudoku_state_field advertise_port)"
  nb_validate_advertise_endpoint "$host" "$advertise_port" TCP \
    && nb_doctor_line PASS "展示端点 / Display Endpoint 模式=${mode}" \
    || { nb_doctor_line FAIL '展示端点 / Display Endpoint 状态无效'; failed=1; }
  vless_sudoku_current_share_link >/dev/null \
    && nb_doctor_line PASS 'VLESS URL 生成正常' \
    || { nb_doctor_line FAIL 'VLESS URL 生成失败'; failed=1; }
  cached_link="$(vless_sudoku_state_field link 2>/dev/null || true)"
  current_link="$(vless_sudoku_current_share_link 2>/dev/null || true)"
  [ -n "$current_link" ] && [ "$cached_link" = "$current_link" ] \
    && nb_doctor_line PASS '缓存的 VLESS URL 与状态一致' \
    || { nb_doctor_line FAIL '缓存的 VLESS URL 与状态不一致'; failed=1; }
  return "$failed"
}

vless_sudoku_smoke() {
  local failed=0
  vless_sudoku_state_exists || { nb_doctor_line INFO 'VLESS Sudoku 未安装'; return 0; }
  vless_sudoku_state_matches \
    && nb_doctor_line PASS '状态 schema 有效' || { nb_doctor_line FAIL '状态 schema 无效'; failed=1; }
  nobrand_xray_test_config "$NOBRAND_VLESS_CONFIG_FILE" \
    && nb_doctor_line PASS 'xray run -test' || { nb_doctor_line FAIL 'xray run -test'; failed=1; }
  vless_sudoku_forbidden_absent "$NOBRAND_VLESS_CONFIG_FILE" \
    "$NOBRAND_VLESS_STATE_FILE" "$NOBRAND_VLESS_CLIENT_FILE" \
    && nb_doctor_line PASS 'VLESS_ENCRYPTION_ENABLED=false' \
    || { nb_doctor_line FAIL '检测到 VLESS Encryption 数据'; failed=1; }
  vless_sudoku_running \
    && nb_doctor_line PASS '服务 / 监听正常' || { nb_doctor_line FAIL '服务 / 监听异常'; failed=1; }
  return "$failed"
}

vless_sudoku_refresh_runtime_metadata() {
  local tmp runtime
  vless_sudoku_state_exists || return 0
  runtime="$(nobrand_xray_version)" || return 1
  tmp="$(mktemp_file .json)" || return 1
  jq --arg runtime "$runtime" --arg updated "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '.runtime_version=$runtime | .updated_at=$updated' "$NOBRAND_VLESS_STATE_FILE" >"$tmp" \
    && nb_atomic_install_file "$tmp" "$NOBRAND_VLESS_STATE_FILE" 0600
  local rc=$?
  rm -f "$tmp"
  return "$rc"
}

vless_sudoku_upgrade_runtime() {
  nobrand_upgrade_xray_runtime
}

nobrand_run_vless_sudoku_action() {
  case "${VLESS_SUDOKU_ACTION:-menu}" in
    menu) vless_sudoku_menu_loop ;;
    install) install_vless_sudoku ;;
    show) print_vless_sudoku_result show ;;
    set-endpoint) vless_sudoku_set_endpoint ;;
    remove) remove_vless_sudoku_config ;;
    start|stop|restart|status) vless_sudoku_service_command "$VLESS_SUDOKU_ACTION" ;;
    doctor) vless_sudoku_doctor ;;
    smoke) vless_sudoku_smoke ;;
    upgrade) vless_sudoku_upgrade_runtime ;;
    help) nobrand_usage ;;
  esac
}
