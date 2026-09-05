# ---------- VLESS + TCP + REALITY + XTLS Vision ----------

reality_valid_name() {
  local value="${1:-}"
  [ -n "$value" ] && [ "$(printf '%s' "$value" | wc -c | tr -d '[:space:]')" -le 64 ] \
    && ! has_control_chars "$value" && [[ "$value" != *'|'* ]]
}

reality_generate_instance_id() {
  local value
  value="$(openssl rand -hex 8 2>/dev/null || true)"
  [ -n "$value" ] || value="$(printf '%08x%08x' "$RANDOM" "$RANDOM")"
  printf 'r%s' "$value"
}

reality_instance_ids() {
  local path id
  for path in "$NOBRAND_REALITY_STATE_DIR"/*/state.json; do
    [ -f "$path" ] || continue
    id="$(basename "$(dirname "$path")")"
    [[ "$id" =~ ^r[0-9a-f]{16}$ ]] || continue
    jq -e --arg id "$id" '
      .schema_version==3 and .ownership=="nobrand-v3"
      and .protocol=="vless-reality" and .instance_id==$id
    ' "$path" >/dev/null 2>&1 || continue
    printf '%s\n' "$id"
  done
}

reality_state_file() { printf '%s/%s/state.json' "$NOBRAND_REALITY_STATE_DIR" "$1"; }
reality_instance_config_dir() { printf '%s/%s' "$NOBRAND_REALITY_CONFIG_DIR" "$1"; }
reality_config_file() { printf '%s/config.json' "$(reality_instance_config_dir "$1")"; }
reality_private_key_file() { printf '%s/private.key' "$(reality_instance_config_dir "$1")"; }

reality_state_exists() {
  local id="$1" state
  state="$(reality_state_file "$id")"
  [ -s "$state" ] && jq -e --arg id "$id" '
    .schema_version==3 and .ownership=="nobrand-v3"
    and .protocol=="vless-reality" and .instance_id==$id
  ' "$state" >/dev/null 2>&1
}

reality_state_field() {
  local id="$1" field="$2" state
  state="$(reality_state_file "$id")"
  reality_state_exists "$id" || return 1
  jq -r --arg field "$field" --arg default_target_port "$NOBRAND_REALITY_DEFAULT_CAMOUFLAGE_PORT" '
    if has($field) and .[$field]!=null then .[$field]
    elif $field=="target_port" then $default_target_port
    elif $field=="camouflage_mode" then "custom"
    else empty
    end
  ' "$state"
}

reality_public_inbound_tag() { printf 'nobrand-vless-reality-%s-in' "$1"; }
reality_defender_tag() { printf 'nobrand-vless-reality-%s-defender' "$1"; }

reality_defender_owner_rows() {
  local id state
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    state="$(reality_state_file "$id")"
    jq -r --arg id "$id" '
      select(.defender_enabled == true)
      | select(.defender_port | type == "number")
      | [$id, (.defender_port|tostring), (.defender_tag // "")] | @tsv
    ' "$state" 2>/dev/null || true
  done < <(reality_instance_ids)
}

reality_defender_port_owner() {
  local port="$1" ignore_id="${2:-}" id row_port _tag
  while IFS=$'\t' read -r id row_port _tag; do
    [ "$id" = "$ignore_id" ] && continue
    if [ "$row_port" = "$port" ]; then
      printf 'vless-reality-defender:%s' "$id"
      return 0
    fi
  done < <(reality_defender_owner_rows)
  return 1
}

reality_defender_port_available() {
  local port="$1" ignore_id="${2:-}" public_port="${3:-}"
  nb_valid_port "$port" || return 1
  [ "$port" -ge "$NOBRAND_REALITY_DEFENDER_PORT_MIN" ] \
    && [ "$port" -le "$NOBRAND_REALITY_DEFENDER_PORT_MAX" ] || return 1
  [ -z "$public_port" ] || [ "$port" != "$public_port" ] || return 1
  reality_defender_port_owner "$port" "$ignore_id" >/dev/null 2>&1 && return 1
  nb_registry_port_owner TCP "$port" >/dev/null 2>&1 && return 1
  nb_port_is_listening TCP "$port" && return 1
  return 0
}

reality_select_defender_port() {
  local public_port="${1:-}"
  nb_scan_port_span "$NOBRAND_REALITY_DEFENDER_PORT_MIN" "$NOBRAND_REALITY_DEFENDER_PORT_MAX" \
    reality_defender_port_available '' "$public_port"
}

reality_defender_registry_valid() {
  local id port tag owner
  declare -A seen=()
  while IFS=$'\t' read -r id port tag; do
    [[ "$id" =~ ^r[0-9a-f]{16}$ ]] || return 1
    nb_valid_port "$port" || return 1
    [ "$port" -ge "$NOBRAND_REALITY_DEFENDER_PORT_MIN" ] \
      && [ "$port" -le "$NOBRAND_REALITY_DEFENDER_PORT_MAX" ] || return 1
    [ "$tag" = "$(reality_defender_tag "$id")" ] || return 1
    [ -z "${seen[$port]:-}" ] || return 1
    seen[$port]="$id"
    owner="$(nb_registry_port_owner TCP "$port" 2>/dev/null || true)"
    [ -z "$owner" ] || return 1
  done < <(reality_defender_owner_rows)
}

reality_find_id_by_name() {
  local name="$1" id matched=""
  while IFS= read -r id; do
    [ "$(reality_state_field "$id" name 2>/dev/null || true)" = "$name" ] || continue
    [ -z "$matched" ] || return 1
    matched="$id"
  done < <(reality_instance_ids)
  [ -n "$matched" ] || return 1
  printf '%s' "$matched"
}

reality_resolve_instance_id() {
  local selector="${1:-}" ids id
  if [[ "$selector" =~ ^r[0-9a-f]{16}$ ]] && reality_state_exists "$selector"; then
    printf '%s' "$selector"
    return 0
  fi
  if [ -n "$selector" ]; then
    reality_find_id_by_name "$selector"
    return $?
  fi
  ids="$(reality_instance_ids)"
  [ "$(printf '%s\n' "$ids" | sed '/^$/d' | wc -l | tr -d '[:space:]')" -eq 1 ] || return 1
  id="$(printf '%s\n' "$ids" | sed '/^$/d')"
  printf '%s' "$id"
}

reality_valid_uuid() {
  [[ "${1:-}" =~ ^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$ ]]
}

reality_generate_uuid() {
  local value=""
  if [ -x "$NOBRAND_XRAY_BIN" ]; then
    value="$("$NOBRAND_XRAY_BIN" uuid 2>/dev/null | tr -d '\r\n' || true)"
  fi
  if ! reality_valid_uuid "$value" && command -v uuidgen >/dev/null 2>&1; then
    value="$(uuidgen 2>/dev/null | tr '[:upper:]' '[:lower:]' | tr -d '\r\n' || true)"
  fi
  if ! reality_valid_uuid "$value" && [ -r /proc/sys/kernel/random/uuid ]; then
    value="$(tr -d '\r\n' </proc/sys/kernel/random/uuid)"
  fi
  reality_valid_uuid "$value" || return 1
  printf '%s' "$value"
}

reality_valid_x25519_key() {
  [[ "${1:-}" =~ ^[A-Za-z0-9_-]{43}$ ]]
}

reality_generate_keypair() {
  local output private_key public_key
  [ -x "$NOBRAND_XRAY_BIN" ] || return 1
  output="$("$NOBRAND_XRAY_BIN" x25519 2>/dev/null)" || return 1
  private_key="$(sed -nE 's/^PrivateKey:[[:space:]]*//p' <<<"$output" | head -n1 | tr -d '\r\n')"
  public_key="$(sed -nE 's/^Password \(PublicKey\):[[:space:]]*//p' <<<"$output" | head -n1 | tr -d '\r\n')"
  reality_valid_x25519_key "$private_key" && reality_valid_x25519_key "$public_key" || return 1
  printf '%s|%s' "$private_key" "$public_key"
}

reality_derive_public_key() {
  local private_key="$1" output public_key
  reality_valid_x25519_key "$private_key" || return 1
  output="$("$NOBRAND_XRAY_BIN" x25519 -i "$private_key" 2>/dev/null)" || return 1
  public_key="$(sed -nE 's/^Password \(PublicKey\):[[:space:]]*//p' <<<"$output" | head -n1 | tr -d '\r\n')"
  reality_valid_x25519_key "$public_key" || return 1
  printf '%s' "$public_key"
}

reality_valid_short_id() {
  local value="${1:-}"
  [[ "$value" =~ ^[0-9a-fA-F]{2,16}$ ]] && [ "$(( ${#value} % 2 ))" -eq 0 ]
}

reality_generate_short_id() {
  local value
  value="$(openssl rand -hex 8 2>/dev/null || true)"
  reality_valid_short_id "$value" || return 1
  printf '%s' "$value"
}

reality_normalize_hostname() {
  printf '%s' "${1%.}" | tr '[:upper:]' '[:lower:]'
}

reality_valid_public_hostname_syntax() {
  local host
  host="$(reality_normalize_hostname "${1:-}")"
  [ -n "$host" ] && [ "${#host}" -le 253 ] || return 1
  command -v python3 >/dev/null 2>&1 || return 1
  python3 - "$host" <<'PY'
import re
import sys

host = sys.argv[1]
if host in {"localhost", "localhost.localdomain"} or "." not in host:
    raise SystemExit(1)
labels = host.split(".")
ok = all(1 <= len(label) <= 63 and
         re.fullmatch(r"[a-z0-9](?:[a-z0-9-]*[a-z0-9])?", label)
         for label in labels)
raise SystemExit(0 if ok and not host.replace(".", "").isdigit() else 1)
PY
}

reality_target_resolves_public() {
  local host="$1" port="$2"
  python3 - "$host" "$port" <<'PY'
import ipaddress
import socket
import sys

host, port = sys.argv[1], int(sys.argv[2])
try:
    addresses = {item[4][0] for item in socket.getaddrinfo(host, port, type=socket.SOCK_STREAM)}
except OSError:
    raise SystemExit(1)
if not addresses:
    raise SystemExit(1)
for raw in addresses:
    ip = ipaddress.ip_address(raw.split("%", 1)[0])
    if not ip.is_global:
        raise SystemExit(1)
raise SystemExit(0)
PY
}

reality_validate_target_live() {
  local host="$1" port="$2" log rc=0
  reality_valid_public_hostname_syntax "$host" && nb_valid_port "$port" || return 1
  reality_target_resolves_public "$host" "$port" || return 1
  log="$(mktemp_file .reality-target)" || return 1
  if command -v timeout >/dev/null 2>&1; then
    timeout 20 openssl s_client -connect "${host}:${port}" -servername "$host" \
      -verify_hostname "$host" -verify_return_error -tls1_3 -brief </dev/null >"$log" 2>&1 || rc=$?
  else
    openssl s_client -connect "${host}:${port}" -servername "$host" \
      -verify_hostname "$host" -verify_return_error -tls1_3 -brief </dev/null >"$log" 2>&1 || rc=$?
  fi
  rm -f "$log"
  [ "$rc" -eq 0 ]
}

reality_auto_candidate_rows() {
  printf '%s\n' "${REALITY_AUTO_QUALIFIED_CANDIDATES[@]}"
}

reality_randomized_auto_candidates() {
  local candidates=() index swap_index swap
  mapfile -t candidates < <(reality_auto_candidate_rows)
  for ((index=${#candidates[@]}-1; index>0; index--)); do
    swap_index=$((RANDOM % (index + 1)))
    swap="${candidates[$index]}"
    candidates[$index]="${candidates[$swap_index]}"
    candidates[$swap_index]="$swap"
  done
  printf '%s\n' "${candidates[@]}"
}

reality_select_auto_camouflage_target() {
  local target_port="$1" candidate seen_candidates='|'
  VLESS_REALITY_TARGET=""
  while IFS= read -r candidate; do
    [ -n "$candidate" ] || continue
    case "$seen_candidates" in
      *"|${candidate}|"*) continue ;;
    esac
    seen_candidates="${seen_candidates}${candidate}|"
    if reality_validate_target_live "$candidate" "$target_port"; then
      VLESS_REALITY_TARGET="$candidate"
      VLESS_REALITY_CAMOUFLAGE_MODE=auto
      info "REALITY 已自动选择伪装目标: ${candidate}:${target_port}"
      return 0
    fi
    warn "REALITY 自动伪装候选在目标端口 ${target_port} 上不可用: ${candidate}"
  done < <(reality_randomized_auto_candidates)
  return 1
}

reality_resolve_camouflage_request() {
  VLESS_REALITY_TARGET_PORT="${VLESS_REALITY_TARGET_PORT:-$NOBRAND_REALITY_DEFAULT_CAMOUFLAGE_PORT}"
  nb_valid_port "$VLESS_REALITY_TARGET_PORT" || return 1
  VLESS_REALITY_TARGET_PORT="$(normalize_uint "$VLESS_REALITY_TARGET_PORT")"
  if [ -z "${VLESS_REALITY_TARGET:-}" ]; then
    VLESS_REALITY_CAMOUFLAGE_MODE=auto
    reality_select_auto_camouflage_target "$VLESS_REALITY_TARGET_PORT"
    return
  fi
  VLESS_REALITY_CAMOUFLAGE_MODE=custom
  VLESS_REALITY_TARGET="$(reality_normalize_hostname "$VLESS_REALITY_TARGET")"
  reality_valid_public_hostname_syntax "$VLESS_REALITY_TARGET" \
    && reality_validate_target_live "$VLESS_REALITY_TARGET" "$VLESS_REALITY_TARGET_PORT"
}

reality_profile_recommendation() {
  local profile_id="$1" type
  type="$(nb_ingress_profile_json "$profile_id" 2>/dev/null | jq -r .type)" || return 1
  case "$type" in
    public) printf 'recommended' ;;
    mapped|legacy) printf 'warning' ;;
    *) return 1 ;;
  esac
}

reality_generate_server_config() {
  local output="$1" id="$2" listen="$3" port="$4" uuid="$5" private_key="$6"
  local short_id="$7" server_name="$8" target_port="$9" defender_port="${10}"
  reality_valid_uuid "$uuid" && reality_valid_x25519_key "$private_key" \
    && reality_valid_short_id "$short_id" && reality_valid_public_hostname_syntax "$server_name" \
    && nb_valid_port "$port" && nb_valid_port "$target_port" \
    && nb_valid_port "$defender_port" || return 1
  jq -n --arg tag "$(reality_public_inbound_tag "$id")" \
    --arg defender_tag "$(reality_defender_tag "$id")" --arg listen "$listen" \
    --arg port "$port" --arg uuid "$uuid" --arg private_key "$private_key" \
    --arg short_id "$short_id" --arg server_name "$server_name" \
    --arg target_port "$target_port" --arg defender_port "$defender_port" \
    --arg target "127.0.0.1:${defender_port}" \
    --arg min_client_ver "$NOBRAND_REALITY_MIN_CLIENT_VER" \
    --arg dispatch "$NOBRAND_REALITY_DEFENDER_DISPATCH_HOST" \
    --arg redirect "${server_name}:${target_port}" '
    {
      log:{loglevel:"warning"},
      inbounds:[
        {
          tag:$tag,listen:$listen,port:($port|tonumber),protocol:"vless",
          settings:{
            clients:[{id:$uuid,email:"vless-reality@nobrand",flow:"xtls-rprx-vision"}],
            decryption:"none"
          },
          streamSettings:{
            network:"tcp",security:"reality",
            realitySettings:{
              show:false,target:$target,xver:0,minClientVer:$min_client_ver,serverNames:[$server_name],
              privateKey:$private_key,shortIds:[$short_id]
            }
          },
          sniffing:{enabled:true,destOverride:["http","tls","quic"]}
        },
        {
          tag:$defender_tag,listen:"127.0.0.1",port:($defender_port|tonumber),
          protocol:"dokodemo-door",
          settings:{address:$dispatch,port:($target_port|tonumber),network:"tcp"},
          sniffing:{enabled:true,routeOnly:true,destOverride:["tls"]}
        }
      ],
      outbounds:[
        {tag:"PUBLIC_DIRECT",protocol:"freedom"},
        {tag:"DIRECT",protocol:"freedom",settings:{redirect:$redirect}},
        {tag:"BLOCK",protocol:"blackhole"}
      ],
      routing:{rules:[
        {type:"field",ip:["geoip:private"],outboundTag:"BLOCK"},
        {type:"field",network:"tcp",port:"25,135,137,138,139,445,465,587",outboundTag:"BLOCK"},
        {type:"field",protocol:["bittorrent"],outboundTag:"BLOCK"},
        {type:"field",inboundTag:[$defender_tag],domain:["full:"+$server_name],outboundTag:"DIRECT"},
        {type:"field",inboundTag:[$defender_tag],outboundTag:"BLOCK"},
        {type:"field",inboundTag:[$tag],outboundTag:"PUBLIC_DIRECT"}
      ]}
    }
  ' >"$output"
}

reality_generate_state() {
  local output="$1" id="$2" name="$3" listen="$4" port="$5" mode="$6"
  local advertise_host="$7" advertise_port="$8" uuid="$9" public_key="${10}"
  local private_key_path="${11}" short_id="${12}" server_name="${13}" target_port="${14}"
  local fingerprint="${15}" spider_x="${16}" runtime_version="${17}"
  local ingress_profile_id="${18}" defender_port="${19}" created_at="${20:-}"
  local camouflage_mode="${21:-custom}"
  local updated_at recommendation defender_tag
  [ -n "$created_at" ] || created_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  updated_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  recommendation="$(reality_profile_recommendation "$ingress_profile_id")" || return 1
  defender_tag="$(reality_defender_tag "$id")"
  jq -n --arg id "$id" --arg name "$name" --arg listen "$listen" --arg port "$port" \
    --arg mode "$mode" --arg advertise_host "$advertise_host" --arg advertise_port "$advertise_port" \
    --arg uuid "$uuid" --arg public_key "$public_key" --arg private_key_path "$private_key_path" \
    --arg short_id "$short_id" --arg server_name "$server_name" --arg target_port "$target_port" \
    --arg camouflage_mode "$camouflage_mode" \
    --arg fingerprint "$fingerprint" --arg spider_x "$spider_x" --arg runtime "$runtime_version" \
    --arg ingress "$ingress_profile_id" --arg recommendation "$recommendation" \
    --arg defender_port "$defender_port" --arg defender_tag "$defender_tag" \
    --arg defender_dispatch "$NOBRAND_REALITY_DEFENDER_DISPATCH_HOST" \
    --arg created "$created_at" --arg updated "$updated_at" '
    {
      schema_version:3,ownership:"nobrand-v3",protocol:"vless-reality",
      instance_id:$id,name:$name,listen_host:$listen,listen_port:($port|tonumber),
      transport:"tcp",network:"tcp",security:"reality",flow:"xtls-rprx-vision",
      uuid:$uuid,public_key:$public_key,private_key_path:$private_key_path,short_id:$short_id,
      camouflage_mode:$camouflage_mode,server_name:$server_name,target_host:$server_name,
      target_port:($target_port|tonumber),
      defender_enabled:true,defender_protocol:"dokodemo-door",defender_listen:"127.0.0.1",
      defender_port:($defender_port|tonumber),defender_tag:$defender_tag,
      defender_dispatch_host:$defender_dispatch,defender_target_mode:"fixed-outbound-redirect",
      fingerprint:$fingerprint,spider_x:$spider_x,show:false,xver:0,
      advertise_mode:$mode,advertise_host:$advertise_host,
      advertise_port:(if $advertise_port=="" then "" else ($advertise_port|tonumber) end),
      ingress_profile_id:$ingress,profile_recommendation:$recommendation,
      runtime_version:$runtime,enabled:true,created_at:$created,updated_at:$updated
    }
  ' >"$output"
}

reality_state_matches() {
  local state="$1" id="${2:-}"
  jq -e --arg id "$id" \
    --argjson defender_min "$NOBRAND_REALITY_DEFENDER_PORT_MIN" \
    --argjson defender_max "$NOBRAND_REALITY_DEFENDER_PORT_MAX" \
    --argjson default_target_port "$NOBRAND_REALITY_DEFAULT_CAMOUFLAGE_PORT" \
    --arg defender_dispatch "$NOBRAND_REALITY_DEFENDER_DISPATCH_HOST" '
    .schema_version==3 and .ownership=="nobrand-v3" and .protocol=="vless-reality"
    and (.instance_id|test("^r[0-9a-f]{16}$"))
    and ($id=="" or .instance_id==$id)
    and (.name | (type=="string" and length>0))
    and (.listen_host | (type=="string" and length>0))
    and (.listen_port | (type=="number" and .>=1 and .<=65535 and floor==.))
    and .transport=="tcp" and .network=="tcp" and .security=="reality"
    and .flow=="xtls-rprx-vision"
    and (.uuid|test("^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$"))
    and (.public_key|test("^[A-Za-z0-9_-]{43}$"))
    and (.private_key_path | (type=="string" and length>0))
    and (.short_id|test("^(?:[0-9a-fA-F]{2}){1,8}$"))
    and ((.camouflage_mode // "custom")=="auto" or (.camouflage_mode // "custom")=="custom")
    and .server_name==.target_host
    and ((.target_port // $default_target_port) | (type=="number" and .>=1 and .<=65535 and floor==.))
    and .defender_enabled==true and .defender_protocol=="dokodemo-door"
    and .defender_listen=="127.0.0.1"
    and (.defender_port | (type=="number" and .>=$defender_min and .<=$defender_max and floor==.))
    and .defender_tag==("nobrand-vless-reality-"+.instance_id+"-defender")
    and .defender_dispatch_host==$defender_dispatch
    and .defender_target_mode=="fixed-outbound-redirect"
    and .fingerprint=="chrome" and .spider_x=="/" and .show==false and .xver==0
    and ((.advertise_mode=="auto" and .advertise_host=="" and .advertise_port=="") or
         (.advertise_mode=="custom" and (.advertise_host | (type=="string" and length>0))
          and (.advertise_port | (type=="number" and .>=1 and .<=65535 and floor==.))))
    and (.ingress_profile_id | (type=="string" and length>0))
    and (.profile_recommendation=="recommended" or .profile_recommendation=="warning")
    and (.runtime_version | (type=="string" and length>0))
    and (.enabled | type=="boolean")
    and ((.ingress_enforcement // "permissive")=="permissive" or .ingress_enforcement=="strict")
    and ((.ingress_enforcement_method // "wildcard")=="wildcard" or .ingress_enforcement_method=="native-bind")
  ' "$state" >/dev/null 2>&1
}

reality_config_matches_state() {
  local id="$1" state config key_path private_key
  state="$(reality_state_file "$id")" config="$(reality_config_file "$id")"
  reality_state_matches "$state" "$id" || return 1
  key_path="$(jq -r .private_key_path "$state")"
  [ -s "$key_path" ] || return 1
  private_key="$(tr -d '\r\n' <"$key_path")"
  reality_valid_x25519_key "$private_key" || return 1
  jq -e --slurpfile state "$state" --arg private_key "$private_key" \
    --arg min_client_ver "$NOBRAND_REALITY_MIN_CLIENT_VER" \
    --argjson default_target_port "$NOBRAND_REALITY_DEFAULT_CAMOUFLAGE_PORT" '
    (.inbounds|length)==2
    and .inbounds[0].tag==("nobrand-vless-reality-"+$state[0].instance_id+"-in")
    and .inbounds[0].listen==$state[0].listen_host
    and .inbounds[0].port==$state[0].listen_port
    and .inbounds[0].protocol=="vless"
    and .inbounds[0].settings.decryption=="none"
    and .inbounds[0].settings.clients==[{
      id:$state[0].uuid,email:"vless-reality@nobrand",flow:"xtls-rprx-vision"
    }]
    and .inbounds[0].streamSettings.network=="tcp"
    and .inbounds[0].streamSettings.security=="reality"
    and .inbounds[0].streamSettings.realitySettings=={
      show:false,target:("127.0.0.1:"+($state[0].defender_port|tostring)),xver:0,
      minClientVer:$min_client_ver,
      serverNames:[$state[0].server_name],privateKey:$private_key,shortIds:[$state[0].short_id]
    }
    and .inbounds[0].sniffing=={enabled:true,destOverride:["http","tls","quic"]}
    and .inbounds[1]=={
      tag:$state[0].defender_tag,listen:"127.0.0.1",port:$state[0].defender_port,
      protocol:"dokodemo-door",
      settings:{address:$state[0].defender_dispatch_host,port:($state[0].target_port // $default_target_port),network:"tcp"},
      sniffing:{enabled:true,routeOnly:true,destOverride:["tls"]}
    }
    and .outbounds==[
      {tag:"PUBLIC_DIRECT",protocol:"freedom"},
      {tag:"DIRECT",protocol:"freedom",settings:{redirect:($state[0].target_host+":"+(($state[0].target_port // $default_target_port)|tostring))}},
      {tag:"BLOCK",protocol:"blackhole"}
    ]
    and .routing.rules==[
      {type:"field",ip:["geoip:private"],outboundTag:"BLOCK"},
      {type:"field",network:"tcp",port:"25,135,137,138,139,445,465,587",outboundTag:"BLOCK"},
      {type:"field",protocol:["bittorrent"],outboundTag:"BLOCK"},
      {type:"field",inboundTag:[$state[0].defender_tag],domain:["full:"+$state[0].target_host],outboundTag:"DIRECT"},
      {type:"field",inboundTag:[$state[0].defender_tag],outboundTag:"BLOCK"},
      {type:"field",inboundTag:[("nobrand-vless-reality-"+$state[0].instance_id+"-in")],outboundTag:"PUBLIC_DIRECT"}
    ]
  ' "$config" >/dev/null 2>&1
}

reality_effective_endpoint() {
  local id="$1" mode host port listen_port ingress
  mode="$(reality_state_field "$id" advertise_mode)"
  host="$(reality_state_field "$id" advertise_host)"
  port="$(reality_state_field "$id" advertise_port)"
  listen_port="$(reality_state_field "$id" listen_port)"
  ingress="$(reality_state_field "$id" ingress_profile_id)"
  printf '%s|%s' "$(nb_effective_advertise_host "$mode" "$host" "$ingress")" \
    "$(nb_effective_advertise_port "$mode" "$port" "$listen_port" "$ingress")"
}

reality_build_uri() {
  local id="$1" endpoint host port uuid sni fingerprint public_key short_id name
  endpoint="$(reality_effective_endpoint "$id")" || return 1
  host="${endpoint%%|*}"; port="${endpoint#*|}"
  uuid="$(reality_state_field "$id" uuid)"
  sni="$(reality_state_field "$id" server_name)"
  fingerprint="$(reality_state_field "$id" fingerprint)"
  public_key="$(reality_state_field "$id" public_key)"
  short_id="$(reality_state_field "$id" short_id)"
  name="$(urlencode "NoBrand-REALITY-$(reality_state_field "$id" name)")" || return 1
  printf 'vless://%s@%s:%s?security=reality&type=tcp&flow=xtls-rprx-vision&sni=%s&fp=%s&pbk=%s&sid=%s&spx=%%2F#%s' \
    "$uuid" "$(url_host "$host")" "$port" "$(urlencode "$sni")" "$fingerprint" \
    "$(urlencode "$public_key")" "$short_id" "$name"
}

reality_export_xray() {
  local id="$1" socks_port="${2:-18080}" endpoint host port
  endpoint="$(reality_effective_endpoint "$id")" || return 1
  host="${endpoint%%|*}"; port="${endpoint#*|}"
  jq -n --arg host "$host" --arg port "$port" --arg socks_port "$socks_port" \
    --arg uuid "$(reality_state_field "$id" uuid)" \
    --arg server_name "$(reality_state_field "$id" server_name)" \
    --arg fingerprint "$(reality_state_field "$id" fingerprint)" \
    --arg password "$(reality_state_field "$id" public_key)" \
    --arg short_id "$(reality_state_field "$id" short_id)" \
    --arg spider_x "$(reality_state_field "$id" spider_x)" '
    {
      log:{loglevel:"warning"},
      inbounds:[{tag:"local-socks",listen:"127.0.0.1",port:($socks_port|tonumber),
                 protocol:"socks",settings:{udp:true}}],
      outbounds:[{
        tag:"vless-reality-out",protocol:"vless",
        settings:{vnext:[{address:$host,port:($port|tonumber),
          users:[{id:$uuid,encryption:"none",flow:"xtls-rprx-vision"}]}]},
        streamSettings:{network:"tcp",security:"reality",realitySettings:{
          serverName:$server_name,fingerprint:$fingerprint,password:$password,
          shortId:$short_id,spiderX:$spider_x
        }}
      }]
    }
  '
}

reality_export_mihomo() {
  local id="$1" endpoint host port name
  endpoint="$(reality_effective_endpoint "$id")" || return 1
  host="${endpoint%%|*}"; port="${endpoint#*|}"; name="$(reality_state_field "$id" name)"
  cat <<EOF
mixed-port: 7890
allow-lan: false
mode: rule
log-level: warning
proxies:
  - name: "NoBrand-REALITY-${name}"
    type: vless
    server: "${host}"
    port: ${port}
    uuid: "$(reality_state_field "$id" uuid)"
    network: tcp
    tls: true
    udp: true
    flow: xtls-rprx-vision
    servername: "$(reality_state_field "$id" server_name)"
    client-fingerprint: "$(reality_state_field "$id" fingerprint)"
    reality-opts:
      public-key: "$(reality_state_field "$id" public_key)"
      short-id: "$(reality_state_field "$id" short_id)"
proxy-groups:
  - name: NOBRAND
    type: select
    proxies: ["NoBrand-REALITY-${name}"]
rules:
  - MATCH,NOBRAND
EOF
}

reality_export_singbox() {
  local id="$1" endpoint host port tag
  endpoint="$(reality_effective_endpoint "$id")" || return 1
  host="${endpoint%%|*}"; port="${endpoint#*|}"; tag="nobrand-reality-$(reality_state_field "$id" name)"
  jq -n --arg tag "$tag" --arg host "$host" --arg port "$port" \
    --arg uuid "$(reality_state_field "$id" uuid)" \
    --arg server_name "$(reality_state_field "$id" server_name)" \
    --arg fingerprint "$(reality_state_field "$id" fingerprint)" \
    --arg public_key "$(reality_state_field "$id" public_key)" \
    --arg short_id "$(reality_state_field "$id" short_id)" '
    {
      log:{level:"warn",timestamp:true},
      inbounds:[{type:"mixed",tag:"mixed-in",listen:"127.0.0.1",listen_port:1080}],
      outbounds:[{
        type:"vless",tag:$tag,server:$host,server_port:($port|tonumber),uuid:$uuid,
        flow:"xtls-rprx-vision",
        tls:{enabled:true,server_name:$server_name,
          utls:{enabled:true,fingerprint:$fingerprint},
          reality:{enabled:true,public_key:$public_key,short_id:$short_id}}
      }],
      route:{final:$tag}
    }
  '
}

reality_set_endpoint_state() {
  local id="$1" host="$2" port="$3" mode=custom state tmp
  state="$(reality_state_file "$id")"
  reality_state_exists "$id" || return 1
  if [ -z "$host" ]; then
    mode=auto; port=""
  else
    nb_validate_advertise_endpoint "$host" "$port" TCP || return 1
    port="$(normalize_uint "$port")"
  fi
  tmp="$(mktemp_file .reality-state)" || return 1
  jq --arg mode "$mode" --arg host "$host" --arg port "$port" \
    --arg updated "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
    .advertise_mode=$mode | .advertise_host=$host
    | .advertise_port=(if $port=="" then "" else ($port|tonumber) end)
    | .updated_at=$updated
  ' "$state" >"$tmp" && nb_atomic_install_file "$tmp" "$state" 0600
  rm -f "$tmp"
}

reality_apply_camouflage_defaults() {
  VLESS_REALITY_TARGET_PORT="${VLESS_REALITY_TARGET_PORT:-$NOBRAND_REALITY_DEFAULT_CAMOUFLAGE_PORT}"
  if [ -z "${VLESS_REALITY_TARGET:-}" ]; then
    VLESS_REALITY_CAMOUFLAGE_MODE=auto
  else
    VLESS_REALITY_CAMOUFLAGE_MODE=custom
  fi
}

reality_collect_install_requests() {
  local owner profile_type input=""
  nb_prepare_ingress_request || return 1
  nb_prepare_ingress_deployment "$INGRESS_PROFILE_ID" native-bind \
    || die 'VLESS REALITY 无法绑定所选 Ingress 的 Strict 本地地址'
  VLESS_REALITY_NAME="${VLESS_REALITY_NAME:-primary}"
  reality_valid_name "$VLESS_REALITY_NAME" || die 'VLESS REALITY 实例名称无效'
  reality_find_id_by_name "$VLESS_REALITY_NAME" >/dev/null 2>&1 \
    && { t "VLESS REALITY 实例已存在: ${VLESS_REALITY_NAME}" \
      "VLESS REALITY instance already exists: ${VLESS_REALITY_NAME}"; return 2; }

  profile_type="$(nb_ingress_profile_json "$INGRESS_PROFILE_ID" | jq -r .type)"
  if [ "$profile_type" = public ]; then
    info "VLESS REALITY：推荐使用 $(nb_ingress_profile_name "$INGRESS_PROFILE_ID")（Public Profile）"
  else
    warn 'VLESS REALITY 不推荐使用 Mapped / Dedicated Ingress；仍允许继续安装'
  fi

  if [ "${YES:-0}" -ne 1 ] && [ "${VLESS_REALITY_TARGET_CLI:-0}" -eq 0 ]; then
    read_tty input "$(t \
      'REALITY 伪装域名 [auto]: ' \
      'REALITY camouflage host [auto]: ')" || input=""
    VLESS_REALITY_TARGET="$input"
  fi
  if [ "${YES:-0}" -ne 1 ] && [ "${VLESS_REALITY_TARGET_PORT_CLI:-0}" -eq 0 ]; then
    read_tty input "$(t \
      "REALITY 伪装目标端口 [${NOBRAND_REALITY_DEFAULT_CAMOUFLAGE_PORT}]: " \
      "REALITY camouflage target port [${NOBRAND_REALITY_DEFAULT_CAMOUFLAGE_PORT}]: ")" || input=""
    VLESS_REALITY_TARGET_PORT="${input:-$NOBRAND_REALITY_DEFAULT_CAMOUFLAGE_PORT}"
  fi
  reality_apply_camouflage_defaults
  nb_valid_port "$VLESS_REALITY_TARGET_PORT" || die 'REALITY 目标端口必须是 1-65535'
  [ "$VLESS_REALITY_FINGERPRINT" = chrome ] || die '当前 REALITY fingerprint 固定为 chrome'
  [ "$VLESS_REALITY_SPIDER_X" = / ] || die '当前 REALITY spiderX 固定为 /'

  if [ -z "${PORT:-}" ] && [ "${YES:-0}" -ne 1 ]; then
    read_tty input "$(t '实际 TCP 监听端口（manual-only 必填，留空时仅自动策略会分配）: ' \
      'Actual TCP port (required for manual-only; blank only auto-allocates for auto policies): ')" || input=""
    PORT="$input"
  fi
  if [ -z "${PORT:-}" ]; then
    PORT="$(nb_select_available_port TCP "$INGRESS_PROFILE_ID")" \
      || die '所选入口配置没有可用 REALITY TCP 自动端口；manual-only 必须显式使用 --port'
    PORT_AUTO_SELECTED=1
  else
    nb_valid_port "$PORT" || die 'VLESS REALITY 端口必须是 1-65535'
    PORT="$(normalize_uint "$PORT")"
    nb_ingress_port_is_reserved "$INGRESS_PROFILE_ID" "$PORT" \
      && die 'VLESS REALITY 禁止使用所选入口配置的保留端口'
    nb_warn_if_outside_recommended_range "$PORT" "$INGRESS_PROFILE_ID"
    nb_port_available_for_profile "$PORT" TCP "$INGRESS_PROFILE_ID" || {
      owner="$(nb_registry_port_owner TCP "$PORT" 2>/dev/null || true)"
      die "VLESS REALITY TCP/${PORT} 已占用${owner:+，占用方: ${owner}}"
    }
  fi

  if [ "${YES:-0}" -ne 1 ] && [ "${ADVERTISE_CLI:-0}" -eq 0 ]; then
    nb_collect_advertise_endpoint_interactive 'VLESS REALITY' "$PORT" || return 1
  elif [ -z "${ADVERTISE_HOST:-}" ]; then
    nb_require_explicit_endpoint_noninteractive
  else
    nb_validate_advertise_endpoint "$ADVERTISE_HOST" "$ADVERTISE_PORT" TCP \
      || die 'VLESS REALITY Display Endpoint 无效'
  fi

  reality_resolve_camouflage_request \
    || die 'REALITY 伪装候选池已耗尽，或显式目标未通过 TLS 1.3、证书与公网可达性验证'
}

reality_install_rollback() {
  local id="$1" port="$2" runtime_preexisting="$3" template_preexisting="$4"
  reality_remove_service "$id" >/dev/null 2>&1 || true
  nb_firewall_close_pairs "TCP|${port}" >/dev/null 2>&1 || true
  find "$NOBRAND_REALITY_STATE_DIR/$id" -mindepth 1 -maxdepth 1 -delete 2>/dev/null || true
  find "$NOBRAND_REALITY_CONFIG_DIR/$id" -mindepth 1 -maxdepth 1 -delete 2>/dev/null || true
  rmdir "$NOBRAND_REALITY_STATE_DIR/$id" "$NOBRAND_REALITY_CONFIG_DIR/$id" 2>/dev/null || true
  if [ "$template_preexisting" -eq 0 ] && [ -z "$(reality_instance_ids)" ]; then
    reality_remove_service_runtime_if_owned >/dev/null 2>&1 || true
  fi
  if [ "$runtime_preexisting" -eq 0 ] && [ -z "$(reality_instance_ids)" ] \
     && ! hysteria2_state_exists && ! vless_sudoku_state_exists; then
    nobrand_remove_xray_runtime_files >/dev/null 2>&1 || true
  fi
  [ "$(nb_service_manager)" != systemd ] || systemctl daemon-reload >/dev/null 2>&1 || true
}

install_vless_reality() {
  local collect_rc=0 id="" uuid keypair private_key public_key short_id
  local config state key_file config_tmp="" state_tmp="" key_tmp="" mode runtime defender_port
  local runtime_preexisting=0 template_preexisting=0
  require_root
  require_linux
  nobrand_prepare_common
  reality_collect_install_requests || collect_rc=$?
  [ "$collect_rc" -eq 0 ] || { [ "$collect_rc" -eq 2 ] && return 0; return "$collect_rc"; }
  [ ! -x "$NOBRAND_XRAY_BIN" ] || runtime_preexisting=1
  [ ! -e "$NOBRAND_REALITY_SYSTEMD_TEMPLATE" ] || template_preexisting=1
  nobrand_install_xray_runtime 0 || return 1
  runtime="$(nobrand_xray_version 2>/dev/null || true)"
  [ "$runtime" = "$TESTED_XRAY_VERSION" ] \
    || die "VLESS REALITY 需要 NoBrand 管理的 Xray ${TESTED_XRAY_VERSION}；请先执行官方共享 Runtime 升级"

  id="$(reality_generate_instance_id)"
  uuid="$(reality_generate_uuid)" || return 1
  keypair="$(reality_generate_keypair)" || return 1
  private_key="${keypair%%|*}"; public_key="${keypair#*|}"
  [ "$(reality_derive_public_key "$private_key")" = "$public_key" ] || return 1
  short_id="$(reality_generate_short_id)" || return 1
  config="$(reality_config_file "$id")"; state="$(reality_state_file "$id")"
  key_file="$(reality_private_key_file "$id")"
  admin_lock_acquire || return 1
  defender_port="$(reality_select_defender_port "$PORT")" || {
    admin_lock_release
    warn '没有可用且无冲突的 REALITY Defender 回环端口'
    return 1
  }
  nb_lifecycle_mark_protocol_mutation_started vless-reality || {
    admin_lock_release
    return 1
  }
  # Xray 26.3.27 infers the config format from the candidate filename.
  # Keep the transactional file JSON-suffixed just like the authoritative
  # config, otherwise `xray run -test -c` rejects it before parsing.
  mkdir -p "$(dirname "$config")" "$(dirname "$state")" \
    && chmod 0700 "$(dirname "$config")" "$(dirname "$state")" \
    && config_tmp="$(mktemp_file .reality-config.json)" \
    && state_tmp="$(mktemp_file .reality-state)" \
    && key_tmp="$(mktemp_file .reality-key)" || {
      reality_install_rollback "$id" "$PORT" "$runtime_preexisting" "$template_preexisting"
      admin_lock_release
      return 1
    }
  printf '%s\n' "$private_key" >"$key_tmp"
  chmod 0600 "$key_tmp"
  reality_generate_server_config "$config_tmp" "$id" "$INGRESS_LISTEN_HOST" "$PORT" "$uuid" \
    "$private_key" "$short_id" "$VLESS_REALITY_TARGET" "$VLESS_REALITY_TARGET_PORT" "$defender_port" \
    && nobrand_xray_test_config "$config_tmp" || {
      reality_install_rollback "$id" "$PORT" "$runtime_preexisting" "$template_preexisting"
      admin_lock_release
      rm -f "$config_tmp" "$state_tmp" "$key_tmp"
      return 1
    }
  mode="$(nb_endpoint_mode_from_values "$ADVERTISE_HOST")"
  reality_generate_state "$state_tmp" "$id" "$VLESS_REALITY_NAME" "$INGRESS_LISTEN_HOST" "$PORT" "$mode" \
    "$ADVERTISE_HOST" "$ADVERTISE_PORT" "$uuid" "$public_key" "$key_file" "$short_id" \
    "$VLESS_REALITY_TARGET" "$VLESS_REALITY_TARGET_PORT" "$VLESS_REALITY_FINGERPRINT" \
    "$VLESS_REALITY_SPIDER_X" "$runtime" "$INGRESS_PROFILE_ID" "$defender_port" \
    "" "$VLESS_REALITY_CAMOUFLAGE_MODE" \
    && nb_ingress_stamp_state_file "$state_tmp" "$INGRESS_PROFILE_ID" native-bind || {
      reality_install_rollback "$id" "$PORT" "$runtime_preexisting" "$template_preexisting"
      admin_lock_release
      rm -f "$config_tmp" "$state_tmp" "$key_tmp"
      return 1
    }

  if ! nb_port_available_for_profile "$PORT" TCP "$INGRESS_PROFILE_ID" \
     || ! reality_defender_port_available "$defender_port" "$id" "$PORT" \
     || ! nb_atomic_install_file "$key_tmp" "$key_file" 0600 \
     || ! nb_atomic_install_file "$config_tmp" "$config" 0600 \
     || ! nb_atomic_install_file "$state_tmp" "$state" 0600 \
     || ! reality_config_matches_state "$id" \
     || ! reality_install_service_runtime \
     || ! reality_ensure_openrc_service "$id" \
     || ! nb_firewall_open_pairs "TCP|${PORT}" \
     || ! reality_service_action "$id" start \
     || ! nb_wait_for_enforced_listener "$INGRESS_ENFORCEMENT_RESOLVED" "$INGRESS_ENFORCEMENT_METHOD" \
          TCP "$PORT" "$INGRESS_LOCAL_ADDRESS" "vless-reality:${id}" 25 \
     || ! reality_listener_owned_by_service "$id" "$PORT" \
     || ! nb_wait_for_listener_address TCP "$defender_port" 127.0.0.1 25 \
     || ! reality_defender_listener_owned_by_service "$id" "$defender_port" \
     || ! reality_defender_registry_valid; then
    reality_install_rollback "$id" "$PORT" "$runtime_preexisting" "$template_preexisting"
    admin_lock_release
    rm -f "$config_tmp" "$state_tmp" "$key_tmp"
    return 1
  fi
  admin_lock_release
  rm -f "$config_tmp" "$state_tmp" "$key_tmp"
  nobrand_install_manager_script || true
  reality_show "$id"
}

reality_state_set_enabled() {
  local id="$1" value="$2" state tmp
  state="$(reality_state_file "$id")"; tmp="$(mktemp_file .reality-state)" || return 1
  jq --argjson enabled "$value" --arg updated "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '.enabled=$enabled | .updated_at=$updated' "$state" >"$tmp" \
    && nb_atomic_install_file "$tmp" "$state" 0600
  rm -f "$tmp"
}

reality_running() {
  local id="$1" port defender_port policy method address
  reality_state_exists "$id" || return 1
  port="$(reality_state_field "$id" listen_port)"
  defender_port="$(reality_state_field "$id" defender_port)"
  policy="$(reality_state_field "$id" ingress_enforcement 2>/dev/null || printf permissive)"
  method="$(reality_state_field "$id" ingress_enforcement_method 2>/dev/null || printf wildcard)"
  address="$(reality_state_field "$id" ingress_local_address 2>/dev/null || true)"
  reality_service_active "$id" \
    && nb_wait_for_enforced_listener "$policy" "$method" TCP "$port" "$address" "vless-reality:${id}" 1 \
    && reality_listener_owned_by_service "$id" "$port" \
    && nb_wait_for_listener_address TCP "$defender_port" 127.0.0.1 1 \
    && reality_defender_listener_owned_by_service "$id" "$defender_port"
}

reality_apply_ingress_enforcement() {
  local id="$1" state config key_file private_key profile_id port uuid short_id target target_port defender_port
  local candidate_state candidate_config snapshot was_active=0 rc=0
  state="$(reality_state_file "$id")"; config="$(reality_config_file "$id")"
  reality_state_exists "$id" || return 1
  profile_id="$(reality_state_field "$id" ingress_profile_id)"
  nb_prepare_ingress_deployment "$profile_id" native-bind || return 1
  key_file="$(reality_state_field "$id" private_key_path)"
  [ -s "$key_file" ] || return 1
  private_key="$(tr -d '\r\n' <"$key_file")"
  port="$(reality_state_field "$id" listen_port)"
  uuid="$(reality_state_field "$id" uuid)"
  short_id="$(reality_state_field "$id" short_id)"
  target="$(reality_state_field "$id" target_host)"
  target_port="$(reality_state_field "$id" target_port)"
  defender_port="$(reality_state_field "$id" defender_port)"
  candidate_state="$(mktemp_file .reality-ingress-state)" || return 1
  candidate_config="$(mktemp_file .reality-ingress-config.json)" || { rm -f "$candidate_state"; return 1; }
  snapshot="$(mktemp_dir)" || { rm -f "$candidate_state" "$candidate_config"; return 1; }
  cp -a "$state" "$snapshot/state" && cp -a "$config" "$snapshot/config" || rc=1
  if [ "$rc" -eq 0 ]; then
    jq --arg listen "$INGRESS_LISTEN_HOST" '.listen_host=$listen' "$state" >"$candidate_state" \
      && nb_ingress_stamp_state_file "$candidate_state" "$profile_id" native-bind \
      && reality_state_matches "$candidate_state" "$id" \
      && reality_generate_server_config "$candidate_config" "$id" "$INGRESS_LISTEN_HOST" "$port" "$uuid" \
           "$private_key" "$short_id" "$target" "$target_port" "$defender_port" \
      && nobrand_xray_test_config "$candidate_config" || rc=1
  fi
  reality_service_active "$id" && was_active=1
  if [ "$rc" -eq 0 ]; then
    nb_atomic_install_file "$candidate_config" "$config" 0600 \
      && nb_atomic_install_file "$candidate_state" "$state" 0600 \
      && reality_config_matches_state "$id" || rc=1
  fi
  if [ "$rc" -eq 0 ] && [ "$was_active" -eq 1 ]; then
    [ "${NOBRAND_TEST_INGRESS_SERVICE_FAIL:-0}" -eq 0 ] \
      && reality_service_action "$id" restart \
      && [ "${NOBRAND_TEST_INGRESS_LISTENER_FAIL:-0}" -eq 0 ] \
      && reality_running "$id" || rc=1
  fi
  if [ "$rc" -ne 0 ]; then
    nb_atomic_install_file "$snapshot/config" "$config" 0600 >/dev/null 2>&1 || true
    nb_atomic_install_file "$snapshot/state" "$state" 0600 >/dev/null 2>&1 || true
    if [ "$was_active" -eq 1 ]; then
      reality_service_action "$id" restart >/dev/null 2>&1 && reality_running "$id" >/dev/null 2>&1 || true
    else
      reality_service_action "$id" stop >/dev/null 2>&1 || true
    fi
  fi
  rm -f "$candidate_state" "$candidate_config"
  rm -rf -- "$snapshot"
  return "$rc"
}

reality_service_command() {
  local id action="$1" port
  id="$(reality_resolve_instance_id "${VLESS_REALITY_NAME:-}")" \
    || die '请用 --name 指定 VLESS REALITY 实例'
  port="$(reality_state_field "$id" listen_port)"
  case "$action" in
    stop)
      reality_service_action "$id" stop && reality_state_set_enabled "$id" false
      ;;
    start)
      reality_service_action "$id" start \
        && reality_running "$id" \
        && reality_state_set_enabled "$id" true
      ;;
    restart)
      reality_service_action "$id" restart \
        && reality_running "$id"
      ;;
  esac
}

reality_show() {
  local id="$1" endpoint recommendation camouflage
  endpoint="$(reality_effective_endpoint "$id")"
  recommendation="$(reality_state_field "$id" profile_recommendation)"
  case "$recommendation" in recommended) recommendation='推荐' ;; warning) recommendation='允许，但不推荐' ;; esac
  camouflage="$(reality_state_field "$id" camouflage_mode)"
  case "$camouflage" in auto) camouflage='自动' ;; custom) camouflage='自定义' ;; esac
  printf 'VLESS REALITY 实例: %s\n入口配置 / Ingress Profile: %s\n建议: %s\n实际监听 / Actual Listener: %s:%s/TCP\n展示端点 / Display Endpoint: %s:%s\n伪装模式: %s\nServerName: %s\nFlow: xtls-rprx-vision\nUUID: %s\n公钥: %s\nShort ID: %s\nURI: %s\n' \
    "$(reality_state_field "$id" name)" \
    "$(nb_ingress_profile_name "$(reality_state_field "$id" ingress_profile_id)")" \
    "$recommendation" \
    "$(reality_state_field "$id" listen_host)" "$(reality_state_field "$id" listen_port)" "${endpoint%%|*}" "${endpoint#*|}" \
    "$camouflage" "$(reality_state_field "$id" server_name)" \
    "$(reality_state_field "$id" uuid)" \
    "$(reality_state_field "$id" public_key)" "$(reality_state_field "$id" short_id)" \
    "$(reality_build_uri "$id")"
}

reality_export_all() {
  local id="$1"
  printf '%s\n' '===== VLESS URI ====='
  reality_build_uri "$id"
  printf '%s\n' '' '===== XRAY CLIENT JSON ====='
  reality_export_xray "$id"
  printf '%s\n' '' '===== MIHOMO YAML ====='
  reality_export_mihomo "$id"
  printf '%s\n' '' '===== SING-BOX JSON ====='
  reality_export_singbox "$id"
}

reality_node_rows() {
  local id endpoint status
  while IFS= read -r id; do
    endpoint="$(reality_effective_endpoint "$id")"
    status=Stopped
    reality_running "$id" && status=Running
    printf 'VLESS REALITY|%s|%s:%s/TCP|%s|TCP\n' "$(reality_state_field "$id" name)" \
      "${endpoint%%|*}" "${endpoint#*|}" "$status"
  done < <(reality_instance_ids)
}

reality_doctor_one() {
  local id="$1" failed=0 state config key_file private_key derived expected port owner
  local defender_port defender_owner
  state="$(reality_state_file "$id")"; config="$(reality_config_file "$id")"
  key_file="$(reality_state_field "$id" private_key_path 2>/dev/null || true)"
  port="$(reality_state_field "$id" listen_port 2>/dev/null || true)"
  defender_port="$(reality_state_field "$id" defender_port 2>/dev/null || true)"
  reality_state_matches "$state" "$id" && nb_doctor_line PASS "REALITY_STATE $(reality_state_field "$id" name)" \
    || { nb_doctor_line FAIL "REALITY_STATE $(reality_state_field "$id" name 2>/dev/null || printf '%s' "$id")"; failed=1; }
  [ "$(nobrand_xray_version 2>/dev/null || true)" = "$TESTED_XRAY_VERSION" ] \
    && nb_doctor_line PASS "REALITY_XRAY ${TESTED_XRAY_VERSION}" \
    || { nb_doctor_line FAIL "REALITY_XRAY expected ${TESTED_XRAY_VERSION}"; failed=1; }
  reality_config_matches_state "$id" && nobrand_xray_test_config "$config" \
    && nb_doctor_line PASS 'REALITY_CONFIG' \
    || { nb_doctor_line FAIL 'REALITY_CONFIG'; failed=1; }
  nobrand_xray_assets_ready \
    && nb_doctor_line PASS 'REALITY_XRAY_ASSETS private geoip/geosite' \
    || { nb_doctor_line FAIL 'REALITY_XRAY_ASSETS'; failed=1; }
  jq -e --slurpfile state "$state" --arg min_client_ver "$NOBRAND_REALITY_MIN_CLIENT_VER" \
    --argjson default_target_port "$NOBRAND_REALITY_DEFAULT_CAMOUFLAGE_PORT" '
    .inbounds[0].streamSettings.realitySettings.target==("127.0.0.1:"+($state[0].defender_port|tostring))
    and .inbounds[0].streamSettings.realitySettings.minClientVer==$min_client_ver
    and .inbounds[1].tag==$state[0].defender_tag
    and .inbounds[1].listen=="127.0.0.1"
    and .inbounds[1].port==$state[0].defender_port
    and .inbounds[1].protocol=="dokodemo-door"
    and .inbounds[1].settings=={address:$state[0].defender_dispatch_host,port:($state[0].target_port // $default_target_port),network:"tcp"}
    and .inbounds[1].sniffing=={enabled:true,routeOnly:true,destOverride:["tls"]}
    and .routing.rules[3]=={type:"field",inboundTag:[$state[0].defender_tag],domain:["full:"+$state[0].target_host],outboundTag:"DIRECT"}
    and .routing.rules[4]=={type:"field",inboundTag:[$state[0].defender_tag],outboundTag:"BLOCK"}
    and .outbounds[1]=={tag:"DIRECT",protocol:"freedom",settings:{redirect:($state[0].target_host+":"+(($state[0].target_port // $default_target_port)|tostring))}}
  ' "$config" >/dev/null 2>&1 \
      && nb_doctor_line PASS 'REALITY_DEFENDER target/minClientVer/loopback/exact-SNI/catch-all' \
    || { nb_doctor_line FAIL 'REALITY_DEFENDER contract'; failed=1; }
  jq -e '
    .routing.rules[0]=={type:"field",ip:["geoip:private"],outboundTag:"BLOCK"}
    and .routing.rules[1]=={type:"field",network:"tcp",port:"25,135,137,138,139,445,465,587",outboundTag:"BLOCK"}
    and .routing.rules[2]=={type:"field",protocol:["bittorrent"],outboundTag:"BLOCK"}
    and .outbounds[0]=={tag:"PUBLIC_DIRECT",protocol:"freedom"}
    and .outbounds[2]=={tag:"BLOCK",protocol:"blackhole"}
  ' "$config" >/dev/null 2>&1 \
    && nb_doctor_line PASS 'REALITY_DEFENDER private/dangerous-port/bittorrent blocks' \
    || { nb_doctor_line FAIL 'REALITY_DEFENDER safety rules'; failed=1; }
  if [ -s "$key_file" ] && [ "$(stat -c '%a' "$key_file" 2>/dev/null || true)" = 600 ] \
     && [ "$(stat -c '%u:%g' "$key_file" 2>/dev/null || true)" = 0:0 ]; then
    private_key="$(tr -d '\r\n' <"$key_file")"
    derived="$(reality_derive_public_key "$private_key" 2>/dev/null || true)"
    expected="$(reality_state_field "$id" public_key)"
    [ -n "$derived" ] && [ "$derived" = "$expected" ] \
      && nb_doctor_line PASS 'REALITY_KEYS private->public consistency; private mode=0600 owner=root' \
      || { nb_doctor_line FAIL 'REALITY_KEYS public derivation mismatch'; failed=1; }
  else
    nb_doctor_line FAIL 'REALITY_KEYS private key permissions/owner'
    failed=1
  fi
  reality_valid_short_id "$(reality_state_field "$id" short_id)" \
    && [ "$(jq -r '.inbounds[0].streamSettings.realitySettings.shortIds[0]' "$config" 2>/dev/null)" = \
      "$(reality_state_field "$id" short_id)" ] \
    && nb_doctor_line PASS 'REALITY_SHORT_ID' \
    || { nb_doctor_line FAIL 'REALITY_SHORT_ID'; failed=1; }
  reality_valid_public_hostname_syntax "$(reality_state_field "$id" server_name)" \
    && [ "$(reality_state_field "$id" server_name)" = "$(reality_state_field "$id" target_host)" ] \
    && [ "$(reality_state_field "$id" flow)" = xtls-rprx-vision ] \
    && nb_doctor_line PASS 'REALITY_SERVER_NAME_TARGET_FLOW' \
    || { nb_doctor_line FAIL 'REALITY_SERVER_NAME_TARGET_FLOW'; failed=1; }
  if [ "$(reality_state_field "$id" enabled)" = true ]; then
    reality_service_active "$id" && nb_doctor_line PASS 'REALITY_SERVICE' \
      || { nb_doctor_line FAIL 'REALITY_SERVICE'; failed=1; }
    reality_running "$id" \
      && nb_doctor_line PASS "REALITY_LISTENERS public TCP/${port}; defender loopback same-process" \
      || { nb_doctor_line FAIL "REALITY_LISTENERS public TCP/${port}; defender loopback"; failed=1; }
  elif reality_service_active "$id" || nb_port_is_listening TCP "$port" \
       || nb_port_is_listening TCP "$defender_port"; then
    nb_doctor_line FAIL 'REALITY_SERVICE marked stopped but service/listener remains'
    failed=1
  else
    nb_doctor_line PASS 'REALITY_SERVICE intentionally stopped; no residual listeners'
  fi
  owner="$(nb_registry_port_owner TCP "$port" 2>/dev/null || true)"
  [ "$owner" = "vless-reality:${id}" ] && nb_doctor_line PASS 'REALITY_PORT_OWNERSHIP' \
    || { nb_doctor_line FAIL 'REALITY_PORT_OWNERSHIP'; failed=1; }
  nb_firewall_binding_owned TCP "$port" && nb_doctor_line PASS 'REALITY_FIREWALL' \
    || { nb_doctor_line FAIL 'REALITY_FIREWALL'; failed=1; }
  defender_owner="$(reality_defender_port_owner "$defender_port" 2>/dev/null || true)"
  [ "$defender_owner" = "vless-reality-defender:${id}" ] \
    && reality_defender_registry_valid \
    && ! nb_firewall_binding_owned TCP "$defender_port" \
    && nb_doctor_line PASS 'REALITY_DEFENDER_INTERNAL_OWNERSHIP no-public-firewall' \
    || { nb_doctor_line FAIL 'REALITY_DEFENDER_INTERNAL_OWNERSHIP'; failed=1; }
  nb_ingress_profile_json "$(reality_state_field "$id" ingress_profile_id)" >/dev/null 2>&1 \
    && [ "$(reality_profile_recommendation "$(reality_state_field "$id" ingress_profile_id)")" = \
      "$(reality_state_field "$id" profile_recommendation)" ] \
    && nb_doctor_line PASS "REALITY_INGRESS_PROFILE $(nb_ingress_profile_name "$(reality_state_field "$id" ingress_profile_id)")" \
    || { nb_doctor_line FAIL 'REALITY_INGRESS_PROFILE'; failed=1; }
  reality_effective_endpoint "$id" >/dev/null \
    && nb_doctor_line PASS 'REALITY_DISPLAY metadata-only' \
    || { nb_doctor_line FAIL 'REALITY_DISPLAY'; failed=1; }
  return "$failed"
}

reality_doctor_all() {
  local id failed=0 found=0
  while IFS= read -r id; do
    found=1
    reality_doctor_one "$id" || failed=1
  done < <(reality_instance_ids)
  [ "$found" -eq 1 ] || nb_doctor_line INFO 'VLESS REALITY 未安装'
  return "$failed"
}

reality_status() {
  local id endpoint found=0 service defender recommendation camouflage
  while IFS= read -r id; do
    found=1; endpoint="$(reality_effective_endpoint "$id")"
    service="$(reality_service_active "$id" && printf '运行中' || printf '已停止')"
    defender="$(reality_running "$id" && printf '正常' || printf '异常')"
    recommendation="$(reality_state_field "$id" profile_recommendation)"
    case "$recommendation" in recommended) recommendation='推荐' ;; warning) recommendation='允许，但不推荐' ;; esac
    camouflage="$(reality_state_field "$id" camouflage_mode)"
    case "$camouflage" in auto) camouflage='自动' ;; custom) camouflage='自定义' ;; esac
    printf 'VLESS REALITY\n  实例: %s\n  运行时 / Runtime: Xray %s\n  服务: %s\n  防御进程 / Defender: %s\n  实际监听 / Actual Listener: %s:%s/TCP\n  展示端点 / Display Endpoint: %s:%s\n  入口配置 / Ingress Profile: %s（%s）\n  伪装模式: %s\n  服务器名称 / ServerName: %s\n  流控 / Flow: xtls-rprx-vision\n' \
      "$(reality_state_field "$id" name)" "$(reality_state_field "$id" runtime_version)" \
      "$service" "$defender" \
      "$(reality_state_field "$id" listen_host)" "$(reality_state_field "$id" listen_port)" "${endpoint%%|*}" "${endpoint#*|}" \
      "$(nb_ingress_profile_name "$(reality_state_field "$id" ingress_profile_id)")" \
      "$recommendation" "$camouflage" "$(reality_state_field "$id" server_name)"
  done < <(reality_instance_ids)
  [ "$found" -eq 1 ] || t 'VLESS REALITY 未安装' 'VLESS REALITY not installed'
}

remove_vless_reality_instance() {
  local id port config_dir state_dir
  id="$(reality_resolve_instance_id "${VLESS_REALITY_NAME:-}")" \
    || die '请用 --name 指定 VLESS REALITY 实例'
  port="$(reality_state_field "$id" listen_port)"
  config_dir="$(reality_instance_config_dir "$id")"; state_dir="$(dirname "$(reality_state_file "$id")")"
  reality_remove_service "$id" || return 1
  nb_firewall_close_pairs "TCP|${port}" || return 1
  find "$config_dir" -mindepth 1 -maxdepth 1 -delete
  find "$state_dir" -mindepth 1 -maxdepth 1 -delete
  rmdir "$config_dir" "$state_dir" 2>/dev/null || true
  if [ -z "$(reality_instance_ids)" ]; then
    reality_remove_service_runtime_if_owned || return 1
    [ "$(nb_service_manager)" != systemd ] || systemctl daemon-reload
    if ! hysteria2_state_exists && ! vless_sudoku_state_exists; then
      nobrand_remove_xray_runtime_files || return 1
    fi
  fi
}

reality_restore_runtime() {
  local id expected current
  id="$(reality_instance_ids | head -n1)"
  [ -n "$id" ] || return 0
  expected="$(reality_state_field "$id" runtime_version)"
  [ "$expected" = "$TESTED_XRAY_VERSION" ] || return 1
  current="$(nobrand_xray_version 2>/dev/null || true)"
  if [ "$current" != "$expected" ] || ! nobrand_xray_assets_ready; then
    nobrand_install_xray_runtime 1 || return 1
  fi
  reality_defender_registry_valid || return 1
  reality_install_service_runtime || return 1
  while IFS= read -r id; do
    [ "$(reality_state_field "$id" runtime_version)" = "$expected" ] \
      && reality_config_matches_state "$id" \
      && nobrand_xray_test_config "$(reality_config_file "$id")" \
      && reality_ensure_openrc_service "$id" || return 1
  done < <(reality_instance_ids)
}

nobrand_run_vless_reality_action() {
  local id
  case "${VLESS_REALITY_ACTION:-menu}" in
    install)
      if [ "${NOBRAND_MANAGER_SESSION_ACTIVE:-0}" -eq 1 ]; then
        nb_lifecycle_run_protocol_install vless-reality install_vless_reality
      else
        install_vless_reality
      fi
      ;;
    start|stop|restart) reality_service_command "$VLESS_REALITY_ACTION" ;;
    status) reality_status ;;
    doctor) reality_doctor_all ;;
    show)
      id="$(reality_resolve_instance_id "${VLESS_REALITY_NAME:-}")" || die '请用 --name 指定实例'
      reality_show "$id"
      ;;
    export)
      id="$(reality_resolve_instance_id "${VLESS_REALITY_NAME:-}")" || die '请用 --name 指定实例'
      reality_export_all "$id"
      ;;
    set-endpoint)
      id="$(reality_resolve_instance_id "${VLESS_REALITY_NAME:-}")" || die '请用 --name 指定实例'
      reality_set_endpoint_state "$id" "${ADVERTISE_HOST:-}" "${ADVERTISE_PORT:-}"
      ;;
    remove|uninstall) remove_vless_reality_instance ;;
    upgrade) nobrand_upgrade_xray_runtime ;;
    menu) reality_status ;;
    help)
      cat <<'EOF'
nobrand vless-reality install --name NAME [--target HOST] [--target-port PORT]
  [--ingress-profile PROFILE] [--port PORT]
  [--advertise-host HOST --advertise-port PORT | --advertise-auto] [-y]
nobrand vless-reality show|export|status|doctor|start|stop|restart|set-endpoint|remove [--name NAME]
固定协议栈：VLESS + TCP + REALITY + xtls-rprx-vision。推荐使用 Public Profile；
Mapped Profile 仍可使用，但会显示警告。Xray 26.3.27；fingerprint=chrome；spiderX=/。
默认伪装域名：从发布验收过的候选池自动选择，并保存选定结果。
伪装域名与目标端口可分别配置；显式指定的域名不会被自动选择替换。
443 是默认伪装目标端口，不是公网 REALITY 监听端口。
EOF
      ;;
    *) die "未知 VLESS REALITY 操作: ${VLESS_REALITY_ACTION}" ;;
  esac
}
