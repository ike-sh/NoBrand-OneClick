# ---------- TUIC v5: named instance, one QUIC listener, multiple users ----------

tuic_protocol_scope_valid() {
  [ "$TUIC_PROTOCOL_VERSION" = 5 ] \
    && [ "$TUIC_V5_SUPPORTED" = true ] \
    && [ "$TUIC_V1_SUPPORTED" = false ] \
    && [ "$TUIC_V2_SUPPORTED" = false ] \
    && [ "$TUIC_V3_SUPPORTED" = false ] \
    && [ "$TUIC_V4_SUPPORTED" = false ]
}

tuic_valid_name() {
  local value="${1:-}"
  [ -n "$value" ] && [ "$(printf '%s' "$value" | wc -c | tr -d '[:space:]')" -le 64 ] \
    && ! has_control_chars "$value" && [[ "$value" != *'|'* ]]
}

tuic_generate_instance_id() {
  local value
  value="$(openssl rand -hex 8 2>/dev/null || true)"
  [ -n "$value" ] || value="$(printf '%08x%08x' "$RANDOM" "$RANDOM")"
  printf 't%s' "$value"
}

tuic_generate_user_id() {
  local value
  value="$(openssl rand -hex 8 2>/dev/null || true)"
  [ -n "$value" ] || value="$(printf '%08x%08x' "$RANDOM" "$RANDOM")"
  printf 'u%s' "$value"
}

tuic_instance_ids() {
  local path id
  for path in "$NOBRAND_TUIC_STATE_DIR"/*/state.json; do
    [ -f "$path" ] || continue
    id="$(basename "$(dirname "$path")")"
    [[ "$id" =~ ^t[0-9a-f]{16}$ ]] || continue
    jq -e --arg id "$id" '
      .schema_version==3 and .ownership=="nobrand-v3" and .protocol=="tuic"
      and .tuic_version==5 and .instance_id==$id
    ' "$path" >/dev/null 2>&1 || continue
    printf '%s\n' "$id"
  done
}

tuic_state_file() { printf '%s/%s/state.json' "$NOBRAND_TUIC_STATE_DIR" "$1"; }
tuic_instance_config_dir() { printf '%s/%s' "$NOBRAND_TUIC_CONFIG_DIR" "$1"; }
tuic_config_file() { printf '%s/config.json' "$(tuic_instance_config_dir "$1")"; }
tuic_cert_file() { printf '%s/tuic-cert.pem' "$(tuic_instance_config_dir "$1")"; }
tuic_key_file() { printf '%s/tuic-key.pem' "$(tuic_instance_config_dir "$1")"; }

tuic_state_exists() {
  local id="$1" state
  state="$(tuic_state_file "$id")"
  [ -s "$state" ] && jq -e --arg id "$id" '
    .schema_version==3 and .ownership=="nobrand-v3" and .protocol=="tuic"
    and .tuic_version==5 and .instance_id==$id
  ' "$state" >/dev/null 2>&1
}

tuic_state_field() {
  local id="$1" field="$2" state
  state="$(tuic_state_file "$id")"
  tuic_state_exists "$id" || return 1
  jq -r --arg field "$field" 'if has($field) and .[$field]!=null then .[$field] else empty end' "$state"
}

tuic_find_id_by_name() {
  local name="$1" id matched=""
  while IFS= read -r id; do
    [ "$(tuic_state_field "$id" name 2>/dev/null || true)" = "$name" ] || continue
    [ -z "$matched" ] || return 1
    matched="$id"
  done < <(tuic_instance_ids)
  [ -n "$matched" ] || return 1
  printf '%s' "$matched"
}

tuic_resolve_instance_id() {
  local selector="${1:-}" ids id
  if [[ "$selector" =~ ^t[0-9a-f]{16}$ ]] && tuic_state_exists "$selector"; then
    printf '%s' "$selector"
    return 0
  fi
  [ -z "$selector" ] || tuic_find_id_by_name "$selector"
  [ -n "$selector" ] && return $?
  ids="$(tuic_instance_ids)"
  [ "$(printf '%s\n' "$ids" | sed '/^$/d' | wc -l | tr -d '[:space:]')" -eq 1 ] || return 1
  id="$(printf '%s\n' "$ids" | sed '/^$/d')"
  printf '%s' "$id"
}

tuic_resolve_user_json() {
  local id="$1" selector="${2:-}" state
  state="$(tuic_state_file "$id")"
  tuic_state_exists "$id" || return 1
  if [ -z "$selector" ]; then
    [ "$(jq '.users|length' "$state")" -eq 1 ] || return 1
    jq -c '.users[0]' "$state"
    return 0
  fi
  jq -ce --arg selector "$selector" '
    [.users[] | select(.user_id==$selector or .name==$selector or .uuid==$selector)]
    | if length==1 then .[0] else empty end
  ' "$state"
}

tuic_generate_uuid() {
  if command -v uuidgen >/dev/null 2>&1; then
    uuidgen | tr '[:upper:]' '[:lower:]'
  elif [ -r /proc/sys/kernel/random/uuid ]; then
    tr '[:upper:]' '[:lower:]' </proc/sys/kernel/random/uuid
  else
    local hex
    hex="$(openssl rand -hex 16)" || return 1
    printf '%s-%s-4%s-%x%s-%s' "${hex:0:8}" "${hex:8:4}" "${hex:13:3}" \
      "$((0x${hex:16:1} % 4 + 8))" "${hex:17:3}" "${hex:20:12}"
  fi
}

tuic_generate_password() {
  openssl rand -hex 24
}

tuic_user_json() {
  local user_id="$1" name="$2" uuid="$3" password="$4" created_at="${5:-}"
  [ -n "$created_at" ] || created_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  jq -n --arg user_id "$user_id" --arg name "$name" --arg uuid "$uuid" \
    --arg password "$password" --arg created "$created_at" '
    {user_id:$user_id,name:$name,uuid:$uuid,password:$password,created_at:$created}
  '
}

tuic_generate_certificate() {
  local cert="$1" key="$2" sni="$3" tmp_cert tmp_key
  command -v openssl >/dev/null 2>&1 || return 1
  mkdir -p "$(dirname "$cert")" || return 1
  chmod 0700 "$(dirname "$cert")" || return 1
  tmp_key="$(mktemp "${key}.tmp.XXXXXX")" || return 1
  tmp_cert="$(mktemp "${cert}.tmp.XXXXXX")" || return 1
  openssl ecparam -genkey -name prime256v1 -out "$tmp_key" 2>/dev/null \
    && openssl req -new -x509 -days 3650 -key "$tmp_key" -out "$tmp_cert" \
      -subj "/CN=${sni}" 2>/dev/null \
    && chmod 0600 "$tmp_key" \
    && chmod 0644 "$tmp_cert" \
    && mv -f "$tmp_key" "$key" \
    && mv -f "$tmp_cert" "$cert" \
    || { rm -f "$tmp_key" "$tmp_cert"; return 1; }
}

tuic_generate_server_config() {
  local output="$1" instance_id="$2" listen="$3" port="$4" cert="$5" key="$6" sni="$7" users="$8"
  jq -n --arg tag "nobrand-tuic-${instance_id}-in" --arg listen "$listen" --arg port "$port" \
    --arg cert "$cert" --arg key "$key" --arg sni "$sni" --argjson users "$users" '
    {
      log:{level:"warn",timestamp:true},
      inbounds:[{
        type:"tuic",tag:$tag,listen:$listen,listen_port:($port|tonumber),
        users:[$users[] | {name:.name,uuid:.uuid,password:.password}],
        congestion_control:"cubic",zero_rtt_handshake:false,
        tls:{enabled:true,server_name:$sni,alpn:["h3"],certificate_path:$cert,key_path:$key}
      }],
      outbounds:[{type:"direct",tag:"direct"}]
    }
  ' >"$output"
}

tuic_certificate_fingerprint() {
  local cert="$1"
  openssl x509 -in "$cert" -noout -fingerprint -sha256 2>/dev/null | sed 's/^sha256 Fingerprint=//;s/^SHA256 Fingerprint=//'
}

tuic_certificate_not_after() {
  openssl x509 -in "$1" -noout -enddate 2>/dev/null | sed 's/^notAfter=//'
}

tuic_generate_state() {
  local output="$1" instance_id="$2" name="$3" listen="$4" port="$5" mode="$6"
  local advertise_host="$7" advertise_port="$8" sni="$9" channel="${10}" runtime_version="${11}"
  local cert="${12}" key="${13}" users="${14}" created_at="${15:-}" updated_at fingerprint not_after
  local ingress_profile_id="${16:-}"
  [ -n "$created_at" ] || created_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  updated_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  fingerprint="$(tuic_certificate_fingerprint "$cert" 2>/dev/null || true)"
  not_after="$(tuic_certificate_not_after "$cert" 2>/dev/null || true)"
  jq -n --arg instance_id "$instance_id" --arg name "$name" --arg listen "$listen" \
    --arg port "$port" --arg mode "$mode" --arg advertise_host "$advertise_host" \
    --arg advertise_port "$advertise_port" --arg sni "$sni" --arg channel "$channel" \
    --arg runtime "$runtime_version" --arg cert "$cert" --arg key "$key" \
    --arg fingerprint "$fingerprint" --arg not_after "$not_after" --argjson users "$users" \
    --arg created "$created_at" --arg updated "$updated_at" --arg ingress_profile_id "$ingress_profile_id" '
    {
      schema_version:3,ownership:"nobrand-v3",protocol:"tuic",tuic_version:5,
      instance_id:$instance_id,name:$name,listen_host:$listen,listen_port:($port|tonumber),transport:"udp",
      advertise_mode:$mode,advertise_host:$advertise_host,
      advertise_port:(if $advertise_port=="" then "" else ($advertise_port|tonumber) end),
      sni:$sni,congestion_control:"cubic",zero_rtt_handshake:false,udp_relay_mode:"native",
      runtime_channel:$channel,runtime_version:$runtime,
      tls:{type:"self-signed",curve:"P-256",alpn:["h3"],certificate_path:$cert,key_path:$key,
           fingerprint_sha256:$fingerprint,not_after:$not_after},
      users:$users,enabled:true,created_at:$created,updated_at:$updated
    }
    + if $ingress_profile_id=="" then {} else {ingress_profile_id:$ingress_profile_id} end
  ' >"$output"
}

tuic_config_matches_state() {
  local id="$1" state config
  state="$(tuic_state_file "$id")"
  config="$(tuic_config_file "$id")"
  tuic_state_exists "$id" && jq empty "$config" >/dev/null 2>&1 || return 1
  jq -e --slurpfile state "$state" '
    .inbounds|length==1
    and .[0].type=="tuic"
    and .[0].listen==$state[0].listen_host
    and .[0].listen_port==$state[0].listen_port
    and .[0].congestion_control=="cubic"
    and .[0].zero_rtt_handshake==false
    and .[0].tls.certificate_path==$state[0].tls.certificate_path
    and .[0].tls.key_path==$state[0].tls.key_path
    and ([.[0].users[]|{name,uuid,password}] == [$state[0].users[]|{name,uuid,password}])
  ' "$config" >/dev/null
}

tuic_effective_endpoint() {
  local id="$1" mode host port listen_port ingress_profile_id
  mode="$(tuic_state_field "$id" advertise_mode)"
  host="$(tuic_state_field "$id" advertise_host)"
  port="$(tuic_state_field "$id" advertise_port)"
  listen_port="$(tuic_state_field "$id" listen_port)"
  ingress_profile_id="$(tuic_state_field "$id" ingress_profile_id 2>/dev/null || true)"
  printf '%s|%s' "$(nb_effective_advertise_host "$mode" "$host" "$ingress_profile_id")" \
    "$(nb_effective_advertise_port "$mode" "$port" "$listen_port" "$ingress_profile_id")"
}

tuic_export_mihomo() {
  local id="$1" selector="${2:-}" user_json endpoint host port name uuid password sni
  user_json="$(tuic_resolve_user_json "$id" "$selector")" || return 1
  endpoint="$(tuic_effective_endpoint "$id")"
  host="${endpoint%%|*}" port="${endpoint#*|}"
  name="$(jq -r .name <<<"$user_json")"
  uuid="$(jq -r .uuid <<<"$user_json")"
  password="$(jq -r .password <<<"$user_json")"
  sni="$(tuic_state_field "$id" sni)"
  cat <<EOF
mixed-port: 7890
allow-lan: false
mode: rule
log-level: warning
proxies:
  - name: "NoBrand-TUIC-${name}"
    type: tuic
    server: "${host}"
    port: ${port}
    uuid: ${uuid}
    password: ${password}
    sni: "${sni}"
    alpn: [h3]
    skip-cert-verify: true
    reduce-rtt: false
    udp-relay-mode: native
    congestion-controller: cubic
    max-udp-relay-packet-size: 1400
proxy-groups:
  - name: NOBRAND
    type: select
    proxies: ["NoBrand-TUIC-${name}"]
rules:
  - MATCH,NOBRAND
EOF
}

tuic_export_singbox() {
  local id="$1" selector="${2:-}" user_json endpoint host port name uuid password sni
  user_json="$(tuic_resolve_user_json "$id" "$selector")" || return 1
  endpoint="$(tuic_effective_endpoint "$id")"
  host="${endpoint%%|*}" port="${endpoint#*|}"
  name="$(jq -r .name <<<"$user_json")"
  uuid="$(jq -r .uuid <<<"$user_json")"
  password="$(jq -r .password <<<"$user_json")"
  sni="$(tuic_state_field "$id" sni)"
  jq -n --arg tag "nobrand-tuic-${name}" --arg host "$host" --arg port "$port" \
    --arg uuid "$uuid" --arg password "$password" --arg sni "$sni" '
    {
      log:{level:"warn",timestamp:true},
      inbounds:[{type:"mixed",tag:"mixed-in",listen:"127.0.0.1",listen_port:1080}],
      outbounds:[{
        type:"tuic",tag:$tag,server:$host,server_port:($port|tonumber),uuid:$uuid,password:$password,
        congestion_control:"cubic",udp_relay_mode:"native",zero_rtt_handshake:false,
        tls:{enabled:true,server_name:$sni,insecure:true,alpn:["h3"]}
      }],
      route:{final:$tag}
    }
  '
}

# No current TUIC v5 specification defines a standardized URI. Exporters must
# not manufacture one; Mihomo YAML and sing-box JSON are the canonical outputs.
tuic_build_uri() { return 1; }

tuic_set_endpoint_state() {
  local id="$1" host="$2" port="$3" mode=custom state tmp
  state="$(tuic_state_file "$id")"
  tuic_state_exists "$id" || return 1
  if [ -z "$host" ]; then
    mode=auto
    port=""
  else
    nb_validate_advertise_endpoint "$host" "$port" UDP || return 1
    port="$(normalize_uint "$port")"
  fi
  tmp="$(mktemp_file .tuic-state)" || return 1
  jq --arg mode "$mode" --arg host "$host" --arg port "$port" \
    --arg updated "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
    .advertise_mode=$mode | .advertise_host=$host
    | .advertise_port=(if $port=="" then "" else ($port|tonumber) end) | .updated_at=$updated
  ' "$state" >"$tmp" && nb_atomic_install_file "$tmp" "$state" 0600
  rm -f "$tmp"
}

tuic_collect_install_requests() {
  local old_port="" owner
  tuic_protocol_scope_valid || die 'TUIC protocol scope constants invalid'
  nb_prepare_ingress_request || return 1
  nb_prepare_ingress_deployment "$INGRESS_PROFILE_ID" native-bind \
    || die '所选 Ingress strict local address cannot be bound by TUIC'
  TUIC_NAME="${TUIC_NAME:-primary}"
  tuic_valid_name "$TUIC_NAME" || die 'TUIC instance name 无效'
  tuic_find_id_by_name "$TUIC_NAME" >/dev/null 2>&1 \
    && { t "TUIC instance 已存在: ${TUIC_NAME}" "TUIC instance already exists: ${TUIC_NAME}"; return 2; }
  if [ -z "${PORT:-}" ]; then
    PORT="$(nb_select_available_port UDP "$INGRESS_PROFILE_ID")" \
      || die '所选入口配置没有可用 TUIC UDP 自动端口；manual-only 必须显式使用 --port'
    PORT_AUTO_SELECTED=1
  else
    nb_valid_port "$PORT" || die 'TUIC port 必须是 1025-65535'
    PORT="$(normalize_uint "$PORT")"
    nb_ingress_port_is_reserved "$INGRESS_PROFILE_ID" "$PORT" && die 'TUIC 禁止使用所选入口配置的保留 port'
    nb_warn_if_outside_recommended_range "$PORT" "$INGRESS_PROFILE_ID"
    nb_port_available_for_profile "$PORT" UDP "$INGRESS_PROFILE_ID" || {
      owner="$(nb_registry_port_owner UDP "$PORT" 2>/dev/null || true)"
      die "TUIC UDP/${PORT} 已占用${owner:+ by ${owner}}"
    }
  fi
  if [ -z "${ADVERTISE_HOST:-}" ]; then
    nb_require_explicit_endpoint_noninteractive
  else
    nb_validate_advertise_endpoint "$ADVERTISE_HOST" "$ADVERTISE_PORT" UDP || die 'TUIC Display Endpoint 无效'
  fi
  if [ -z "${TUIC_SNI:-}" ]; then TUIC_SNI=www.microsoft.com; fi
  hysteria2_valid_sni "$TUIC_SNI" || die 'TUIC SNI 必须是有效 domain 或 IPv4'
  TUIC_CHANNEL="$(tuic_normalize_channel "${TUIC_CHANNEL:-stable}")" || die 'TUIC runtime channel 无效'
  if [ "$TUIC_CHANNEL" = pinned ]; then
    tuic_valid_runtime_version "$TUIC_VERSION" || die 'pinned TUIC runtime 需要精确稳定版本'
  fi
  TUIC_USER="${TUIC_USER:-default}"
  tuic_valid_name "$TUIC_USER" || die 'TUIC user name 无效'
  [ -z "$old_port" ] || true
}

tuic_install_rollback() {
  local id="$1" port="$2"
  tuic_remove_service "$id" >/dev/null 2>&1 || true
  nb_firewall_close_pairs "UDP|${port}" >/dev/null 2>&1 || true
  find "$NOBRAND_TUIC_STATE_DIR/$id" -mindepth 1 -maxdepth 1 -delete 2>/dev/null || true
  find "$NOBRAND_TUIC_CONFIG_DIR/$id" -mindepth 1 -maxdepth 1 -delete 2>/dev/null || true
  rmdir "$NOBRAND_TUIC_STATE_DIR/$id" "$NOBRAND_TUIC_CONFIG_DIR/$id" 2>/dev/null || true
}

tuic_prepare_runtime_for_install() {
  local channel="$1" requested_version="${2:-}" first_id current id state_version
  first_id="$(tuic_instance_ids | head -n1)"
  if [ -z "$first_id" ]; then
    tuic_install_runtime "$channel" "$requested_version"
    return
  fi
  current="$(tuic_runtime_version)" || die '现有 NoBrand TUIC runtime 缺失或不可执行'
  tuic_runtime_metadata_valid "$current" "" || die '现有 NoBrand TUIC runtime ownership metadata 无效'
  while IFS= read -r id; do
    state_version="$(tuic_state_field "$id" runtime_version)"
    [ "$state_version" = "$current" ] \
      || die "TUIC instance ${id} runtime state 不一致，拒绝隐式替换共享 runtime"
  done < <(tuic_instance_ids)
  tuic_resolve_runtime "$channel" "$requested_version" || die '无法解析 official sing-box runtime'
  [ "$TUIC_RUNTIME_RESOLVED_VERSION" = "$current" ] \
    || die '新增 TUIC instance 不会隐式升级共享 runtime；请先执行 nobrand tuic upgrade-runtime'
}

tuic_install_transaction_rollback() {
  local id="$1" port="$2" runtime_snapshot="$3" template_preexisting="$4"
  tuic_install_rollback "$id" "$port"
  tuic_restore_runtime_files "$runtime_snapshot" || warn 'TUIC install runtime rollback failed'
  if [ "$template_preexisting" -eq 0 ] && [ -z "$(tuic_instance_ids)" ]; then
    case "$NOBRAND_TUIC_SYSTEMD_TEMPLATE" in
      /etc/systemd/system/nobrand-tuic@.service) rm -f "$NOBRAND_TUIC_SYSTEMD_TEMPLATE" ;;
    esac
    [ "$(nb_service_manager)" != systemd ] || systemctl daemon-reload >/dev/null 2>&1 || true
  fi
}

install_tuic() {
  local collect_rc=0 id="" user_id uuid password users cert key config state config_tmp="" state_tmp=""
  local mode runtime_version runtime_snapshot template_preexisting=0
  require_root
  require_linux
  nobrand_prepare_common
  tuic_collect_install_requests || collect_rc=$?
  [ "$collect_rc" -eq 0 ] || { [ "$collect_rc" -eq 2 ] && return 0; return "$collect_rc"; }
  runtime_snapshot="$(mktemp_dir)" || return 1
  tuic_snapshot_runtime_files "$runtime_snapshot" || return 1
  [ ! -e "$NOBRAND_TUIC_SYSTEMD_TEMPLATE" ] || template_preexisting=1
  tuic_prepare_runtime_for_install "$TUIC_CHANNEL" "$TUIC_VERSION" \
    || { rm -rf -- "$runtime_snapshot"; die 'official sing-box runtime 准备失败'; }
  runtime_version="$(tuic_runtime_version)" || {
    tuic_restore_runtime_files "$runtime_snapshot" || true
    rm -rf -- "$runtime_snapshot"
    return 1
  }
  id="$(tuic_generate_instance_id)"
  user_id="$(tuic_generate_user_id)"
  uuid="$(tuic_generate_uuid)" || {
    tuic_install_transaction_rollback "$id" "$PORT" "$runtime_snapshot" "$template_preexisting"
    rm -rf -- "$runtime_snapshot"
    return 1
  }
  password="$(tuic_generate_password)" || {
    tuic_install_transaction_rollback "$id" "$PORT" "$runtime_snapshot" "$template_preexisting"
    rm -rf -- "$runtime_snapshot"
    return 1
  }
  users="[$(tuic_user_json "$user_id" "$TUIC_USER" "$uuid" "$password")]"
  cert="$(tuic_cert_file "$id")" key="$(tuic_key_file "$id")"
  config="$(tuic_config_file "$id")" state="$(tuic_state_file "$id")"
  mkdir -p "$(dirname "$state")" "$(dirname "$config")" \
    && chmod 0700 "$(dirname "$state")" "$(dirname "$config")" \
    && tuic_generate_certificate "$cert" "$key" "$TUIC_SNI" \
    && config_tmp="$(mktemp_file .tuic-config)" \
    && state_tmp="$(mktemp_file .tuic-state)" || {
      tuic_install_transaction_rollback "$id" "$PORT" "$runtime_snapshot" "$template_preexisting"
      rm -f "$config_tmp" "$state_tmp"
      rm -rf -- "$runtime_snapshot"
      return 1
    }
  tuic_generate_server_config "$config_tmp" "$id" "$INGRESS_LISTEN_HOST" "$PORT" "$cert" "$key" "$TUIC_SNI" "$users" \
    && tuic_validate_config "$config_tmp" \
    || {
      tuic_install_transaction_rollback "$id" "$PORT" "$runtime_snapshot" "$template_preexisting"
      rm -f "$config_tmp" "$state_tmp"
      rm -rf -- "$runtime_snapshot"
      return 1
    }
  mode="$(nb_endpoint_mode_from_values "$ADVERTISE_HOST")"
  tuic_generate_state "$state_tmp" "$id" "$TUIC_NAME" "$INGRESS_LISTEN_HOST" "$PORT" "$mode" \
    "$ADVERTISE_HOST" "$ADVERTISE_PORT" "$TUIC_SNI" "$TUIC_CHANNEL" "$runtime_version" \
    "$cert" "$key" "$users" "" "$INGRESS_PROFILE_ID" \
    && nb_ingress_stamp_state_file "$state_tmp" "$INGRESS_PROFILE_ID" native-bind || {
      tuic_install_transaction_rollback "$id" "$PORT" "$runtime_snapshot" "$template_preexisting"
      rm -f "$config_tmp" "$state_tmp"
      rm -rf -- "$runtime_snapshot"
      return 1
    }
  admin_lock_acquire || {
    tuic_install_transaction_rollback "$id" "$PORT" "$runtime_snapshot" "$template_preexisting"
    rm -f "$config_tmp" "$state_tmp"
    rm -rf -- "$runtime_snapshot"
    return 1
  }
  if ! nb_port_available_for_profile "$PORT" UDP "$INGRESS_PROFILE_ID" \
     || ! nb_atomic_install_file "$config_tmp" "$config" 0600 \
     || ! nb_atomic_install_file "$state_tmp" "$state" 0600 \
     || ! tuic_install_service_runtime \
     || ! tuic_ensure_openrc_service "$id" \
     || ! nb_firewall_open_pairs "UDP|${PORT}" \
     || ! tuic_service_action "$id" start \
     || ! nb_wait_for_enforced_listener "$INGRESS_ENFORCEMENT_RESOLVED" "$INGRESS_ENFORCEMENT_METHOD" \
          UDP "$PORT" "$INGRESS_LOCAL_ADDRESS" "tuic:${id}" 25 \
     || ! tuic_listener_owned_by_service "$id" "$PORT"; then
    tuic_install_transaction_rollback "$id" "$PORT" "$runtime_snapshot" "$template_preexisting"
    admin_lock_release
    rm -f "$config_tmp" "$state_tmp"
    rm -rf -- "$runtime_snapshot"
    return 1
  fi
  admin_lock_release
  rm -f "$config_tmp" "$state_tmp"
  rm -rf -- "$runtime_snapshot"
  nobrand_install_manager_script || true
  tuic_show_user "$id" "$TUIC_USER"
}

tuic_commit_candidate_state() {
  local id="$1" candidate_state="$2" state config config_tmp snapshot running port users policy method address rc=0
  state="$(tuic_state_file "$id")" config="$(tuic_config_file "$id")"
  port="$(jq -r .listen_port "$candidate_state")"
  users="$(jq -c .users "$candidate_state")"
  config_tmp="$(mktemp_file .tuic-config)" || return 1
  tuic_generate_server_config "$config_tmp" "$id" "$(jq -r .listen_host "$candidate_state")" "$port" \
    "$(jq -r .tls.certificate_path "$candidate_state")" "$(jq -r .tls.key_path "$candidate_state")" \
    "$(jq -r .sni "$candidate_state")" "$users" || return 1
  tuic_validate_config "$config_tmp" || { rm -f "$config_tmp"; return 1; }
  snapshot="$(mktemp_dir)" || { rm -f "$config_tmp"; return 1; }
  cp -a "$state" "$config" "$snapshot/" || { rm -f "$config_tmp"; rm -rf -- "$snapshot"; return 1; }
  running=0
  tuic_service_active "$id" && running=1
  policy="$(jq -r '.ingress_enforcement // "permissive"' "$candidate_state")"
  method="$(jq -r '.ingress_enforcement_method // "wildcard"' "$candidate_state")"
  address="$(jq -r '.ingress_local_address // empty' "$candidate_state")"
  if ! nb_atomic_install_file "$config_tmp" "$config" 0600 \
     || ! nb_atomic_install_file "$candidate_state" "$state" 0600 \
     || ! { [ "$running" -eq 0 ] || {
           [ "${NOBRAND_TEST_INGRESS_SERVICE_FAIL:-0}" -eq 0 ] \
             && tuic_service_action "$id" restart \
             && [ "${NOBRAND_TEST_INGRESS_LISTENER_FAIL:-0}" -eq 0 ] \
             && nb_wait_for_enforced_listener "$policy" "$method" UDP "$port" "$address" "tuic:${id}" 25 \
             && tuic_listener_owned_by_service "$id" "$port"
         }; }; then
    cp -a "$snapshot/state.json" "$state" 2>/dev/null || true
    cp -a "$snapshot/config.json" "$config" 2>/dev/null || true
    if [ "$running" -eq 1 ]; then
      if ! tuic_service_action "$id" restart >/dev/null 2>&1 \
         || ! tuic_running "$id" >/dev/null 2>&1; then
        warn "TUIC rollback listener verification failed: ${id}"
      fi
    fi
    rc=1
  fi
  rm -f "$config_tmp"
  rm -rf -- "$snapshot"
  return "$rc"
}

tuic_apply_ingress_enforcement() {
  local id="$1" state profile_id candidate rc
  state="$(tuic_state_file "$id")"
  tuic_state_exists "$id" || return 1
  profile_id="$(tuic_state_field "$id" ingress_profile_id 2>/dev/null || true)"
  [ -n "$profile_id" ] || profile_id="$NOBRAND_LEGACY_INGRESS_PROFILE_ID"
  nb_prepare_ingress_deployment "$profile_id" native-bind || return 1
  candidate="$(mktemp_file .tuic-ingress-state)" || return 1
  jq --arg listen "$INGRESS_LISTEN_HOST" '.listen_host=$listen' "$state" >"$candidate" \
    && nb_ingress_stamp_state_file "$candidate" "$profile_id" native-bind \
    && tuic_commit_candidate_state "$id" "$candidate"
  rc=$?
  rm -f "$candidate"
  return "$rc"
}

tuic_user_add() {
  local id="$1" name="$2" state candidate user_id uuid password user_json
  tuic_valid_name "$name" || die 'TUIC user name 无效'
  tuic_resolve_user_json "$id" "$name" >/dev/null 2>&1 && die "TUIC user 已存在: $name"
  state="$(tuic_state_file "$id")" candidate="$(mktemp_file .tuic-state)" || return 1
  user_id="$(tuic_generate_user_id)" uuid="$(tuic_generate_uuid)" password="$(tuic_generate_password)"
  user_json="$(tuic_user_json "$user_id" "$name" "$uuid" "$password")"
  jq --argjson user "$user_json" --arg updated "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '.users += [$user] | .updated_at=$updated' "$state" >"$candidate" \
    && tuic_commit_candidate_state "$id" "$candidate"
  rm -f "$candidate"
}

tuic_user_delete() {
  local id="$1" selector="$2" user_json user_id state candidate
  user_json="$(tuic_resolve_user_json "$id" "$selector")" || die '找不到唯一 TUIC user'
  user_id="$(jq -r .user_id <<<"$user_json")"
  state="$(tuic_state_file "$id")" candidate="$(mktemp_file .tuic-state)" || return 1
  [ "$(jq '.users|length' "$state")" -gt 1 ] || die 'TUIC instance 至少保留一个 user；请卸载 instance'
  jq --arg user_id "$user_id" --arg updated "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '.users |= map(select(.user_id!=$user_id)) | .updated_at=$updated' "$state" >"$candidate" \
    && tuic_commit_candidate_state "$id" "$candidate"
  rm -f "$candidate"
}

tuic_user_rotate() {
  local id="$1" selector="$2" user_json user_id state candidate uuid password
  user_json="$(tuic_resolve_user_json "$id" "$selector")" || die '找不到唯一 TUIC user'
  user_id="$(jq -r .user_id <<<"$user_json")"
  uuid="$(tuic_generate_uuid)" password="$(tuic_generate_password)"
  state="$(tuic_state_file "$id")" candidate="$(mktemp_file .tuic-state)" || return 1
  jq --arg user_id "$user_id" --arg uuid "$uuid" --arg password "$password" \
    --arg updated "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
    (.users[] | select(.user_id==$user_id)) |= (.uuid=$uuid | .password=$password)
    | .updated_at=$updated
  ' "$state" >"$candidate" && tuic_commit_candidate_state "$id" "$candidate"
  rm -f "$candidate"
}

tuic_user_list() {
  local id="$1"
  jq -r '.users[] | [.name,.uuid,.created_at] | @tsv' "$(tuic_state_file "$id")"
}

tuic_show_user() {
  local id="$1" selector="${2:-}" user_json endpoint
  user_json="$(tuic_resolve_user_json "$id" "$selector")" || return 1
  endpoint="$(tuic_effective_endpoint "$id")"
  printf 'TUIC v5 instance: %s\nUser: %s\nIngress Profile: %s\nActual: %s:%s/UDP\nDisplay Endpoint: %s:%s\nSNI: %s\nUUID: %s\nPassword: %s\n' \
    "$(tuic_state_field "$id" name)" "$(jq -r .name <<<"$user_json")" \
    "$(nb_ingress_profile_name "$(tuic_state_field "$id" ingress_profile_id 2>/dev/null || true)")" \
    "$(tuic_state_field "$id" listen_host)" "$(tuic_state_field "$id" listen_port)" \
    "${endpoint%%|*}" "${endpoint#*|}" "$(tuic_state_field "$id" sni)" \
    "$(jq -r .uuid <<<"$user_json")" "$(jq -r .password <<<"$user_json")"
}

tuic_export_user() {
  local id="$1" selector="${2:-}" uri
  printf '%s\n' '===== MIHOMO YAML ====='
  tuic_export_mihomo "$id" "$selector"
  printf '%s\n' '' '===== SING-BOX JSON ====='
  tuic_export_singbox "$id" "$selector"
  if uri="$(tuic_build_uri "$id" "$selector" 2>/dev/null)"; then
    printf '\nTUIC URI: %s\n' "$uri"
  else
    printf '%s\n' '' 'TUIC URI: unavailable (no upstream-standardized v5 URI confirmed).'
  fi
}

tuic_node_rows() {
  local id endpoint status user
  while IFS= read -r id; do
    endpoint="$(tuic_effective_endpoint "$id")"
    status=Stopped
    tuic_running "$id" && status=Running
    while IFS= read -r user; do
      printf 'TUIC v5|%s/%s|%s:%s|%s|UDP\n' "$(tuic_state_field "$id" name)" \
        "$(jq -r .name <<<"$user")" "${endpoint%%|*}" "${endpoint#*|}" "$status"
    done < <(jq -c '.users[]' "$(tuic_state_file "$id")")
  done < <(tuic_instance_ids)
}

tuic_running() {
  local id="$1" port policy method address
  tuic_state_exists "$id" || return 1
  port="$(tuic_state_field "$id" listen_port)"
  policy="$(tuic_state_field "$id" ingress_enforcement 2>/dev/null || printf permissive)"
  method="$(tuic_state_field "$id" ingress_enforcement_method 2>/dev/null || printf wildcard)"
  address="$(tuic_state_field "$id" ingress_local_address 2>/dev/null || true)"
  tuic_service_active "$id" \
    && nb_wait_for_enforced_listener "$policy" "$method" UDP "$port" "$address" "tuic:${id}" 1 \
    && tuic_listener_owned_by_service "$id" "$port"
}

tuic_doctor_one() {
  local id="$1" failed=0 port cert key runtime expected
  port="$(tuic_state_field "$id" listen_port)"
  cert="$(jq -r .tls.certificate_path "$(tuic_state_file "$id")")"
  key="$(jq -r .tls.key_path "$(tuic_state_file "$id")")"
  runtime="$(tuic_runtime_version 2>/dev/null || true)"
  expected="$(tuic_state_field "$id" runtime_version)"
  [ "$runtime" = "$expected" ] && nb_doctor_line PASS "sing-box ${runtime}" \
    || { nb_doctor_line FAIL "sing-box version ${runtime:-missing}, expected ${expected}"; failed=1; }
  tuic_config_matches_state "$id" && tuic_validate_config "$(tuic_config_file "$id")" \
    && nb_doctor_line PASS "TUIC v5 config $(tuic_state_field "$id" name)" \
    || { nb_doctor_line FAIL "TUIC config $(tuic_state_field "$id" name)"; failed=1; }
  tuic_service_active "$id" && nb_doctor_line PASS 'service active' \
    || { nb_doctor_line FAIL 'service inactive'; failed=1; }
  tuic_running "$id" \
    && nb_doctor_line PASS "same-process UDP/${port}" \
    || { nb_doctor_line FAIL "same-process UDP/${port}"; failed=1; }
  nb_firewall_binding_owned UDP "$port" && nb_doctor_line PASS "firewall UDP/${port}" \
    || { nb_doctor_line FAIL "firewall UDP/${port}"; failed=1; }
  [ -s "$cert" ] && openssl x509 -in "$cert" -checkend 2592000 -noout >/dev/null 2>&1 \
    && nb_doctor_line PASS 'TLS certificate valid beyond 30 days' \
    || { nb_doctor_line FAIL 'TLS certificate missing/expiring'; failed=1; }
  [ "$(stat -c '%a' "$key" 2>/dev/null || true)" = 600 ] \
    && nb_doctor_line PASS 'TLS P-256 key mode=0600' \
    || { nb_doctor_line FAIL 'TLS key permission'; failed=1; }
  jq -e '.users|length>0 and all(.[]; .uuid|test("^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"))' \
    "$(tuic_state_file "$id")" >/dev/null \
    && nb_doctor_line PASS 'TUIC v5 UUID+password users' \
    || { nb_doctor_line FAIL 'TUIC users'; failed=1; }
  return "$failed"
}

tuic_doctor_all() {
  local id failed=0 found=0
  while IFS= read -r id; do
    found=1
    tuic_doctor_one "$id" || failed=1
  done < <(tuic_instance_ids)
  [ "$found" -eq 1 ] || nb_doctor_line INFO 'TUIC v5 not installed'
  return "$failed"
}

tuic_status() {
  local id endpoint
  id="$(tuic_resolve_instance_id "${TUIC_NAME:-}")" || { t 'TUIC instance 未安装或不唯一' 'TUIC instance missing or ambiguous'; return 0; }
  endpoint="$(tuic_effective_endpoint "$id")"
  printf 'TUIC v5\n  Instance: %s\n  Runtime: %s (%s)\n  Service: %s\n  UDP listener: %s\n  Display Endpoint: %s:%s\n  TLS: self-signed ECDSA P-256 / h3\n  Users: %s\n' \
    "$(tuic_state_field "$id" name)" "$(tuic_state_field "$id" runtime_version)" \
    "$(tuic_state_field "$id" runtime_channel)" \
    "$(tuic_service_active "$id" && printf Running || printf Stopped)" \
    "$(tuic_state_field "$id" listen_port)" "${endpoint%%|*}" "${endpoint#*|}" \
    "$(jq '.users|length' "$(tuic_state_file "$id")")"
}

tuic_service_command() {
  local id action="$1" port
  id="$(tuic_resolve_instance_id "${TUIC_NAME:-}")" || die '请用 --name 指定 TUIC instance'
  port="$(tuic_state_field "$id" listen_port)"
  tuic_service_action "$id" "$action" || return 1
  case "$action" in
    start|restart) tuic_running "$id" ;;
  esac
}

remove_tuic_instance() {
  local id port config_dir state_dir
  id="$(tuic_resolve_instance_id "${TUIC_NAME:-}")" || die '请用 --name 指定 TUIC instance'
  port="$(tuic_state_field "$id" listen_port)"
  config_dir="$(tuic_instance_config_dir "$id")" state_dir="$(dirname "$(tuic_state_file "$id")")"
  tuic_remove_service "$id" || return 1
  nb_firewall_close_pairs "UDP|${port}" || return 1
  find "$config_dir" -mindepth 1 -maxdepth 1 -delete
  find "$state_dir" -mindepth 1 -maxdepth 1 -delete
  rmdir "$config_dir" "$state_dir" 2>/dev/null || true
  if [ -z "$(tuic_instance_ids)" ]; then
    rm -f "$NOBRAND_SING_BOX_BIN" "$NOBRAND_SING_BOX_RUNTIME_META"
    case "$NOBRAND_TUIC_SYSTEMD_TEMPLATE" in
      /etc/systemd/system/nobrand-tuic@.service) rm -f "$NOBRAND_TUIC_SYSTEMD_TEMPLATE" ;;
    esac
    [ "$(nb_service_manager)" != systemd ] || systemctl daemon-reload
  fi
}

tuic_upgrade_runtime_rollback() {
  local snapshot="$1" active_file="$2" id port failed=0 state_snapshot
  tuic_restore_runtime_files "$snapshot/runtime" || failed=1
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    state_snapshot="$snapshot/states/${id}.json"
    [ ! -s "$state_snapshot" ] \
      || nb_atomic_install_file "$state_snapshot" "$(tuic_state_file "$id")" 0600 \
      || failed=1
  done < <(tuic_instance_ids)
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    port="$(tuic_state_field "$id" listen_port 2>/dev/null || true)"
    tuic_service_action "$id" restart >/dev/null 2>&1 \
      && tuic_running "$id" || failed=1
  done <"$active_file"
  [ "$failed" -eq 0 ]
}

tuic_upgrade_runtime() {
  local id version state tmp candidate metadata_tmp snapshot active_file port failed=0
  [ -n "$(tuic_instance_ids)" ] || die '没有可升级的 TUIC instance'
  candidate="$(mktemp_file .sing-box-upgrade)" || return 1
  metadata_tmp="$(mktemp_file .tuic-runtime-meta)" || return 1
  snapshot="$(mktemp_dir)" || return 1
  active_file="$snapshot/active.ids"
  : >"$active_file"
  mkdir -p "$snapshot/runtime" "$snapshot/states" || return 1
  tuic_download_runtime_candidate "$candidate" "$TUIC_CHANNEL" "$TUIC_VERSION" || {
    rm -f "$candidate" "$metadata_tmp"
    rm -rf -- "$snapshot"
    return 1
  }
  version="$(tuic_runtime_version "$candidate")" || return 1
  tuic_generate_runtime_metadata "$metadata_tmp" "$TUIC_CHANNEL" "$version" || return 1
  while IFS= read -r id; do
    tuic_validate_config "$(tuic_config_file "$id")" "$candidate" || failed=1
  done < <(tuic_instance_ids)
  [ "$failed" -eq 0 ] || {
    rm -f "$candidate" "$metadata_tmp"
    rm -rf -- "$snapshot"
    return 1
  }
  admin_lock_acquire || return 1
  tuic_snapshot_runtime_files "$snapshot/runtime" || {
    admin_lock_release
    return 1
  }
  while IFS= read -r id; do
    cp -a "$(tuic_state_file "$id")" "$snapshot/states/${id}.json" || failed=1
    tuic_service_active "$id" && printf '%s\n' "$id" >>"$active_file"
  done < <(tuic_instance_ids)
  if [ "$failed" -ne 0 ] \
     || ! nb_atomic_install_file "$candidate" "$NOBRAND_SING_BOX_BIN" 0755 \
     || ! nb_atomic_install_file "$metadata_tmp" "$NOBRAND_SING_BOX_RUNTIME_META" 0600 \
     || [ "$(tuic_runtime_version 2>/dev/null || true)" != "$version" ]; then
    tuic_upgrade_runtime_rollback "$snapshot" "$active_file" \
      || warn 'TUIC runtime upgrade rollback verification failed'
    admin_lock_release
    rm -f "$candidate" "$metadata_tmp"
    rm -rf -- "$snapshot"
    return 1
  fi
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    port="$(tuic_state_field "$id" listen_port)"
    if ! tuic_service_action "$id" restart \
       || ! tuic_running "$id"; then
      failed=1
      break
    fi
  done <"$active_file"
  if [ "$failed" -eq 0 ]; then
    while IFS= read -r id; do
      state="$(tuic_state_file "$id")"
      tmp="$(mktemp_file .tuic-state)" || { failed=1; break; }
      jq --arg version "$version" --arg channel "$TUIC_CHANNEL" \
        --arg updated "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '.runtime_version=$version | .runtime_channel=$channel | .updated_at=$updated' "$state" >"$tmp" \
        && nb_atomic_install_file "$tmp" "$state" 0600 || failed=1
      rm -f "$tmp"
      [ "$failed" -eq 0 ] || break
    done < <(tuic_instance_ids)
  fi
  if [ "$failed" -ne 0 ]; then
    tuic_upgrade_runtime_rollback "$snapshot" "$active_file" \
      || warn 'TUIC runtime upgrade rollback verification failed'
    admin_lock_release
    rm -f "$candidate" "$metadata_tmp"
    rm -rf -- "$snapshot"
    return 1
  fi
  admin_lock_release
  rm -f "$candidate" "$metadata_tmp"
  rm -rf -- "$snapshot"
}

tuic_restore_runtime() {
  local first_id channel version current id state_version metadata_tmp
  first_id="$(tuic_instance_ids | head -n1)"
  [ -n "$first_id" ] || return 0
  channel="$(tuic_state_field "$first_id" runtime_channel)"
  version="$(tuic_state_field "$first_id" runtime_version)"
  while IFS= read -r id; do
    state_version="$(tuic_state_field "$id" runtime_version)"
    [ "$state_version" = "$version" ] || return 1
  done < <(tuic_instance_ids)
  current="$(tuic_runtime_version 2>/dev/null || true)"
  if [ "$current" != "$version" ] || ! tuic_runtime_metadata_valid "$version" ""; then
    tuic_install_runtime pinned "$version" || return 1
    metadata_tmp="$(mktemp_file .tuic-runtime-meta)" || return 1
    jq --arg channel "$channel" '.channel=$channel' "$NOBRAND_SING_BOX_RUNTIME_META" >"$metadata_tmp" \
      && nb_atomic_install_file "$metadata_tmp" "$NOBRAND_SING_BOX_RUNTIME_META" 0600 || return 1
    rm -f "$metadata_tmp"
  fi
  tuic_install_service_runtime
}

nobrand_run_tuic_action() {
  local id
  case "${TUIC_ACTION:-menu}" in
    install) install_tuic ;;
    start|stop|restart) tuic_service_command "$TUIC_ACTION" ;;
    status) tuic_status ;;
    doctor) tuic_doctor_all ;;
    show)
      id="$(tuic_resolve_instance_id "${TUIC_NAME:-}")" || die '请用 --name 指定 TUIC instance'
      tuic_show_user "$id" "${TUIC_USER:-}"
      ;;
    export)
      id="$(tuic_resolve_instance_id "${TUIC_NAME:-}")" || die '请用 --name 指定 TUIC instance'
      tuic_export_user "$id" "${TUIC_USER:-}"
      ;;
    set-endpoint)
      id="$(tuic_resolve_instance_id "${TUIC_NAME:-}")" || die '请用 --name 指定 TUIC instance'
      tuic_set_endpoint_state "$id" "${ADVERTISE_HOST:-}" "${ADVERTISE_PORT:-}"
      ;;
    user-add)
      id="$(tuic_resolve_instance_id "${TUIC_NAME:-}")" || die '请用 --name 指定 TUIC instance'
      tuic_user_add "$id" "$TUIC_USER"
      ;;
    user-delete)
      id="$(tuic_resolve_instance_id "${TUIC_NAME:-}")" || die '请用 --name 指定 TUIC instance'
      tuic_user_delete "$id" "$TUIC_USER"
      ;;
    user-list)
      id="$(tuic_resolve_instance_id "${TUIC_NAME:-}")" || die '请用 --name 指定 TUIC instance'
      tuic_user_list "$id"
      ;;
    user-show)
      id="$(tuic_resolve_instance_id "${TUIC_NAME:-}")" || die '请用 --name 指定 TUIC instance'
      tuic_show_user "$id" "$TUIC_USER"
      ;;
    user-rotate)
      id="$(tuic_resolve_instance_id "${TUIC_NAME:-}")" || die '请用 --name 指定 TUIC instance'
      tuic_user_rotate "$id" "$TUIC_USER"
      ;;
    upgrade-runtime) tuic_upgrade_runtime ;;
    uninstall) remove_tuic_instance ;;
    menu) tuic_status ;;
    help)
      cat <<'EOF'
nobrand tuic install|start|stop|restart|status|doctor|show|export|set-endpoint|upgrade-runtime|uninstall
nobrand tuic user add|delete|list|show|rotate
TUIC v5 only; official sing-box; UDP/QUIC; independent UUID + password per user.
EOF
      ;;
    *) die "未知 TUIC 操作: ${TUIC_ACTION}" ;;
  esac
}
