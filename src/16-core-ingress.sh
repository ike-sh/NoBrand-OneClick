# ---------- NoBrand Common Core: ingress profiles (schema-v3 optional state) ----------

NOBRAND_LEGACY_INGRESS_PROFILE_ID="legacy-default-route"

nb_ingress_now() {
  date -u +%Y-%m-%dT%H:%M:%SZ
}

nb_ingress_valid_ipv4() {
  local value="${1:-}"
  command -v python3 >/dev/null 2>&1 || {
    [[ "$value" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
    local part
    IFS=. read -r -a _nb_ipv4_parts <<<"$value"
    for part in "${_nb_ipv4_parts[@]}"; do
      [[ "$part" =~ ^[0-9]+$ ]] && [ "$((10#$part))" -le 255 ] || return 1
    done
    return 0
  }
  python3 - "$value" <<'PY' >/dev/null 2>&1
import ipaddress, sys
try:
    value = ipaddress.ip_address(sys.argv[1])
except ValueError:
    raise SystemExit(1)
raise SystemExit(0 if value.version == 4 and not value.is_loopback and not value.is_link_local else 1)
PY
}

# interface|IPv4|state|default-route-marker. Tests may provide exact rows
# through NOBRAND_TEST_INTERFACE_ROWS without changing the host network.
nb_ingress_interface_rows() {
  local default_iface=""
  if [ -n "${NOBRAND_TEST_INTERFACE_ROWS:-}" ]; then
    printf '%s\n' "$NOBRAND_TEST_INTERFACE_ROWS" | sed '/^$/d'
    return 0
  fi
  command -v ip >/dev/null 2>&1 || return 0
  default_iface="$(ip -o -4 route show default 2>/dev/null \
    | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')"
  ip -o -4 addr show scope global 2>/dev/null | awk -v default_iface="$default_iface" '
    {
      iface=$2; sub(/@.*/, "", iface); split($4, address, "/")
      state="UNKNOWN"
      command="ip -o link show dev \"" iface "\" 2>/dev/null"
      if ((command | getline link) > 0) {
        if (link ~ /state UP/) state="UP"; else if (link ~ /state DOWN/) state="DOWN"
      }
      close(command)
      print iface "|" address[1] "|" state "|" (iface==default_iface ? "1" : "0")
    }
  '
}

nb_ingress_interface_exists() {
  local expected="$1" iface _address _state _default
  while IFS='|' read -r iface _address _state _default; do
    [ "$iface" = "$expected" ] && return 0
  done < <(nb_ingress_interface_rows)
  return 1
}

nb_ingress_address_on_interface() {
  local expected_iface="$1" expected_address="$2" iface address _state _default
  nb_ingress_valid_ipv4 "$expected_address" || return 1
  while IFS='|' read -r iface address _state _default; do
    [ "$iface" = "$expected_iface" ] && [ "$address" = "$expected_address" ] && return 0
  done < <(nb_ingress_interface_rows)
  return 1
}

nb_ingress_default_egress() {
  local iface="" address=""
  if [ -n "${NOBRAND_TEST_DEFAULT_EGRESS:-}" ]; then
    printf '%s' "$NOBRAND_TEST_DEFAULT_EGRESS"
    return 0
  fi
  if command -v ip >/dev/null 2>&1; then
    iface="$(ip -o -4 route show default 2>/dev/null \
      | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')"
    address="$(ip -4 route get 1.1.1.1 2>/dev/null \
      | awk '{for(i=1;i<=NF;i++) if($i=="src"){print $(i+1); exit}}')"
  fi
  [ -n "$iface$address" ] || return 1
  printf '%s|%s' "$iface" "$address"
}

nb_ingress_state_valid() {
  local path="${1:-$NOBRAND_INGRESS_STATE_FILE}" address policy display_host
  [ -f "$path" ] && [ ! -L "$path" ] && [ -s "$path" ] || return 1
  jq -e --argjson schema "$NOBRAND_SCHEMA_VERSION" '
    (keys|sort) == ["default_profile_id","feature","ownership","profiles","schema_version"]
    and .schema_version == $schema and .ownership == "nobrand-v3"
    and .feature == "ingress-profiles"
    and ((.default_profile_id == null) or (.default_profile_id|type == "string"))
    and (.profiles|type == "array")
    and (([.profiles[].profile_id]|length) == ([.profiles[].profile_id]|unique|length))
    and (([.profiles[].name]|length) == ([.profiles[].name]|unique|length))
    and ([.profiles[].profile_id] as $ids |
         all(.profiles[];
           . as $profile |
           $profile.name != "legacy-default-route" and $profile.name != "Legacy Default Route"
           and ($ids|index($profile.name)|not)))
    and all(.profiles[];
      ((keys-["ingress_enforcement"]|sort) == ["created_at","display_host_default","display_port","display_port_policy","enabled",
                      "interface","local_address","name","port_policy","profile_id","range_end","range_start",
                      "reserved_ports","type","updated_at"])
      and ((has("ingress_enforcement")|not) or
           (.ingress_enforcement == "permissive" or .ingress_enforcement == "strict"))
      and (.profile_id|type == "string" and test("^i[0-9a-f]{16}$"))
      and (.name|type == "string" and length > 0 and length <= 64 and (test("[[:cntrl:]]")|not))
      and (.type == "public" or .type == "mapped")
      and (.interface|type == "string" and test("^[A-Za-z0-9_.:-]{1,64}$"))
      and (.local_address|type == "string" and length > 0)
      and (.port_policy == "derived-tail" or .port_policy == "custom-range" or .port_policy == "manual-only")
      and (.reserved_ports|type == "array")
      and (all(.reserved_ports[]; type == "number" and floor == . and . >= 1 and . <= 65535))
      and ((.reserved_ports|length) == (.reserved_ports|unique|length))
      and (if .port_policy == "custom-range" then
             (.range_start|type == "number") and (.range_end|type == "number")
             and .range_start >= 1025 and .range_end <= 65535 and .range_start <= .range_end
           else .range_start == null and .range_end == null end)
      and (.display_port_policy == "follow-actual" or .display_port_policy == "custom")
      and (if .display_port_policy == "custom" then
             ((.display_port|type) == "number" and .display_port >= 1 and .display_port <= 65535)
           else .display_port == null end)
      and (.display_host_default|type == "string")
      and (if .type == "mapped" then (.display_host_default|length > 0) else true end)
      and (.enabled|type == "boolean")
      and (.created_at|type == "string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$"))
      and (.updated_at|type == "string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$"))
    )
    and (.default_profile_id as $default |
         if $default == null then true
         else any(.profiles[]; .profile_id == $default and .enabled) end)
  ' "$path" >/dev/null 2>&1 || return 1
  while IFS=$'\t' read -r address policy display_host; do
    nb_ingress_valid_ipv4 "$address" || return 1
    [ "$policy" != derived-tail ] || nb_port_base_for_ip "$address" >/dev/null || return 1
    [ -z "$display_host" ] || valid_advertise_host "$display_host" || return 1
  done < <(jq -r '.profiles[]|[.local_address,.port_policy,.display_host_default]|@tsv' "$path")
}

nb_ingress_ensure_state() {
  local tmp
  nb_init_state_layout || return 1
  if [ -e "$NOBRAND_INGRESS_STATE_FILE" ]; then
    nb_ingress_state_valid || die 'Ingress profile state is invalid; refusing to overwrite it'
    return 0
  fi
  tmp="$(mktemp_file .ingress.json)" || return 1
  jq -n --argjson schema "$NOBRAND_SCHEMA_VERSION" \
    '{schema_version:$schema,ownership:"nobrand-v3",feature:"ingress-profiles",default_profile_id:null,profiles:[]}' \
    >"$tmp" || { rm -f "$tmp"; return 1; }
  nb_atomic_install_file "$tmp" "$NOBRAND_INGRESS_STATE_FILE" 0600
  local rc=$?
  rm -f "$tmp"
  return "$rc"
}

nb_ingress_generate_id() {
  local id attempt=0
  while [ "$attempt" -lt 64 ]; do
    id="i$(openssl rand -hex 8 2>/dev/null || printf '%016x' "$((RANDOM * 32768 + RANDOM))")"
    [[ "$id" =~ ^i[0-9a-f]{16}$ ]] || { attempt=$((attempt + 1)); continue; }
    if [ ! -s "$NOBRAND_INGRESS_STATE_FILE" ] \
       || jq -e --arg id "$id" 'all(.profiles[];.profile_id!=$id)' "$NOBRAND_INGRESS_STATE_FILE" >/dev/null; then
      printf '%s' "$id"
      return 0
    fi
    attempt=$((attempt + 1))
  done
  return 1
}

nb_ingress_legacy_profile_json() {
  local ip iface="" base="" range_start=null range_end=null reserved='[]'
  ip="$(nb_detect_local_ipv4 2>/dev/null || true)"
  if command -v ip >/dev/null 2>&1 && [ -n "$ip" ]; then
    iface="$(ip -o -4 addr show scope global 2>/dev/null \
      | awk -v ip="$ip" '{split($4,a,"/"); if(a[1]==ip){x=$2; sub(/@.*/,"",x); print x; exit}}')"
  fi
  if base="$(nb_port_base_for_ip "$ip" 2>/dev/null)"; then
    range_start=$((base + 1)); range_end=$((base + 99)); reserved="[$base]"
  fi
  jq -n --arg id "$NOBRAND_LEGACY_INGRESS_PROFILE_ID" --arg name 'Legacy Default Route' \
    --arg interface "$iface" --arg address "$ip" --argjson range_start "$range_start" \
    --argjson range_end "$range_end" --argjson reserved "$reserved" '
      {profile_id:$id,name:$name,type:"legacy",interface:$interface,local_address:$address,
       port_policy:"derived-tail",range_start:$range_start,range_end:$range_end,
       reserved_ports:$reserved,display_host_default:"",display_port_policy:"follow-actual",
       display_port:null,ingress_enforcement:"permissive",enabled:true,built_in:true,created_at:"",updated_at:""}
    '
}

nb_ingress_profile_json() {
  local selector="${1:-}" id
  [ -n "$selector" ] || return 1
  if [ "$selector" = "$NOBRAND_LEGACY_INGRESS_PROFILE_ID" ] || [ "$selector" = 'Legacy Default Route' ]; then
    nb_ingress_legacy_profile_json
    return 0
  fi
  nb_ingress_state_valid || return 1
  id="$(jq -r --arg value "$selector" '
    [.profiles[]|select(.profile_id==$value or .name==$value)|.profile_id] as $ids |
    if ($ids|length)==1 then $ids[0] else empty end
  ' "$NOBRAND_INGRESS_STATE_FILE")"
  [ -n "$id" ] || return 1
  jq -c --arg id "$id" '.profiles[]|select(.profile_id==$id)' "$NOBRAND_INGRESS_STATE_FILE"
}

nb_ingress_profile_id() {
  local json
  json="$(nb_ingress_profile_json "$1")" || return 1
  jq -r .profile_id <<<"$json"
}

nb_ingress_default_profile_id() {
  if nb_ingress_state_valid; then
    jq -r '.default_profile_id // empty' "$NOBRAND_INGRESS_STATE_FILE"
  fi
}

# Resolution for a newly-created object: explicit request, then configured
# default, then the immutable 3.1 legacy adapter.
nb_resolve_ingress_profile() {
  local requested="${1:-}" resolved=""
  if [ -n "$requested" ]; then
    resolved="$(nb_ingress_profile_id "$requested" 2>/dev/null || true)"
    [ -n "$resolved" ] || die "Ingress profile not found or ambiguous: ${requested}"
  else
    resolved="$(nb_ingress_default_profile_id 2>/dev/null || true)"
    [ -n "$resolved" ] || resolved="$NOBRAND_LEGACY_INGRESS_PROFILE_ID"
  fi
  local profile
  profile="$(nb_ingress_profile_json "$resolved")" || return 1
  [ "$(jq -r .enabled <<<"$profile")" = true ] || die "Ingress profile is disabled: ${resolved}"
  printf '%s' "$resolved"
}

nb_prepare_ingress_request() {
  INGRESS_PROFILE_ID="$(nb_resolve_ingress_profile "${INGRESS_PROFILE:-}")" || return 1
}

nb_ingress_profile_enforcement() {
  local profile
  profile="$(nb_ingress_profile_json "${1:-}")" || return 1
  jq -r '.ingress_enforcement // "permissive"' <<<"$profile"
}

# Resolve the exact deployment contract for a managed listener.  The
# capability argument is an implementation fact established by the pinned
# runtime audit, not a user-selectable mode.
nb_prepare_ingress_deployment() {
  local profile_id="$1" capability="$2" profile policy address
  profile="$(nb_ingress_profile_json "$profile_id")" || return 1
  policy="$(nb_ingress_profile_enforcement "$profile_id")" || return 1
  address="$(jq -r '.local_address // empty' <<<"$profile")"
  INGRESS_LOCAL_ADDRESS="$address"
  case "$capability" in
    not-applicable)
      INGRESS_ENFORCEMENT_RESOLVED=not-applicable
      INGRESS_ENFORCEMENT_METHOD=system-ssh
      INGRESS_LISTEN_HOST=0.0.0.0
      return 0
      ;;
    native-bind|firewall|address-match) ;;
    *) return 1 ;;
  esac
  case "$policy" in
    permissive)
      INGRESS_ENFORCEMENT_RESOLVED=permissive
      INGRESS_ENFORCEMENT_METHOD=wildcard
      INGRESS_LISTEN_HOST=0.0.0.0
      ;;
    strict)
      [ "$profile_id" != "$NOBRAND_LEGACY_INGRESS_PROFILE_ID" ] || return 1
      nb_ingress_valid_ipv4 "$address" || return 1
      nb_ingress_address_on_interface "$(jq -r .interface <<<"$profile")" "$address" || return 1
      INGRESS_ENFORCEMENT_RESOLVED=strict
      INGRESS_ENFORCEMENT_METHOD="$capability"
      case "$capability" in
        native-bind|address-match) INGRESS_LISTEN_HOST="$address" ;;
        firewall) INGRESS_LISTEN_HOST=0.0.0.0 ;;
      esac
      ;;
    *) return 1 ;;
  esac
}

nb_ingress_stamp_state_file() {
  local path="$1" profile_id="$2" capability="$3" tmp
  [ -s "$path" ] && jq empty "$path" >/dev/null 2>&1 || return 1
  nb_prepare_ingress_deployment "$profile_id" "$capability" || return 1
  tmp="$(mktemp_file .ingress-stamp)" || return 1
  jq --arg policy "$INGRESS_ENFORCEMENT_RESOLVED" --arg method "$INGRESS_ENFORCEMENT_METHOD" \
    --arg address "$INGRESS_LOCAL_ADDRESS" \
    '.ingress_enforcement=$policy | .ingress_enforcement_method=$method | .ingress_local_address=$address' \
    "$path" >"$tmp" && mv -f "$tmp" "$path"
  local rc=$?
  rm -f "$tmp"
  return "$rc"
}

nb_ingress_state_enforcement() {
  jq -r '.ingress_enforcement // "permissive"' "$1" 2>/dev/null
}

nb_ingress_state_method() {
  jq -r '.ingress_enforcement_method // "wildcard"' "$1" 2>/dev/null
}

nb_ingress_state_local_address() {
  local path="$1" profile_id="$2" value
  value="$(jq -r '.ingress_local_address // empty' "$path" 2>/dev/null || true)"
  if [ -z "$value" ]; then
    value="$(nb_ingress_profile_json "$profile_id" 2>/dev/null | jq -r '.local_address // empty' || true)"
  fi
  printf '%s' "$value"
}

nb_listener_has_local_address() {
  local transport="$1" port="$2" address="$3" flags line field
  command -v ss >/dev/null 2>&1 || return 1
  case "$transport" in
    TCP) flags='-Hln4t' ;;
    UDP) flags='-Hln4u' ;;
    *) return 1 ;;
  esac
  while IFS= read -r line; do
    for field in $line; do
      [ "$field" = "${address}:${port}" ] && return 0
    done
  done < <(ss "$flags" 2>/dev/null)
  return 1
}

nb_wait_for_listener_address() {
  local transport="$1" port="$2" address="$3" timeout="${4:-25}" i=0
  while [ "$i" -lt "$timeout" ]; do
    nb_listener_has_local_address "$transport" "$port" "$address" && return 0
    sleep 1
    i=$((i + 1))
  done
  return 1
}

nb_wait_for_enforced_listener() {
  local policy="${1:-permissive}" method="${2:-wildcard}" transport="$3" port="$4" address="$5" owner="$6" timeout="${7:-25}"
  case "$policy:$method" in
    permissive:wildcard) nb_wait_for_listener "$transport" "$port" "$timeout" ;;
    strict:native-bind) nb_wait_for_listener_address "$transport" "$port" "$address" "$timeout" ;;
    strict:firewall)
      nb_wait_for_listener "$transport" "$port" "$timeout" \
        && nb_strict_firewall_rule_owned "$owner" "$transport" "$port" "$address"
      ;;
    *) return 1 ;;
  esac
}

nb_strict_firewall_empty_state() {
  jq -n --argjson schema "$NOBRAND_SCHEMA_VERSION" \
    '{schema_version:$schema,ownership:"nobrand-v3",feature:"ingress-enforcement-firewall",rules:[]}'
}

nb_strict_firewall_state_valid() {
  local path="${1:-$NOBRAND_INGRESS_FIREWALL_STATE_FILE}" owner transport address
  [ -s "$path" ] || return 1
  jq -e --argjson schema "$NOBRAND_SCHEMA_VERSION" '
    (keys|sort)==["feature","ownership","rules","schema_version"] and
    .schema_version==$schema and .ownership=="nobrand-v3" and
    .feature=="ingress-enforcement-firewall" and (.rules|type)=="array" and
    all(.rules[];
      (keys|sort)==["ingress_profile_id","local_address","owner","port","transport"] and
      (.owner|type)=="string" and (.owner|test("^[A-Za-z0-9:._-]{1,128}$")) and
      (.ingress_profile_id|type)=="string" and (.ingress_profile_id|length)>0 and
      (.local_address|type)=="string" and (.local_address|length)>0 and
      (.transport=="TCP" or .transport=="UDP") and
      (.port|type)=="number" and .port>=1 and .port<=65535 and (.port|floor)==.port) and
    ([.rules[]|(.owner+"|"+.transport+"|"+(.port|tostring))]|length)==
      ([.rules[]|(.owner+"|"+.transport+"|"+(.port|tostring))]|unique|length)
  ' "$path" >/dev/null 2>&1 || return 1
  while IFS=$'\t' read -r owner transport address; do
    [ -n "$owner" ] || continue
    nb_ingress_valid_ipv4 "$address" || return 1
    case "$transport" in TCP|UDP) ;; *) return 1 ;; esac
  done < <(jq -r '.rules[]|[.owner,.transport,.local_address]|@tsv' "$path")
}

nb_strict_firewall_table_owned() {
  local listing
  command -v nft >/dev/null 2>&1 || return 1
  listing="$(nft list table "$NOBRAND_INGRESS_NFT_FAMILY" "$NOBRAND_INGRESS_NFT_TABLE" 2>/dev/null)" \
    || return 1
  grep -Fq 'comment "Owned by NoBrand-OneClick Strict Ingress"' <<<"$listing"
}

nb_strict_firewall_remove_table() {
  command -v nft >/dev/null 2>&1 || return 0
  nft list table "$NOBRAND_INGRESS_NFT_FAMILY" "$NOBRAND_INGRESS_NFT_TABLE" >/dev/null 2>&1 \
    || return 0
  nb_strict_firewall_table_owned || return 1
  nft delete table "$NOBRAND_INGRESS_NFT_FAMILY" "$NOBRAND_INGRESS_NFT_TABLE"
}

nb_strict_firewall_ensure_dependency() {
  command -v nft >/dev/null 2>&1 && return 0
  if declare -F forward_ensure_nftables_dependency >/dev/null 2>&1; then
    forward_ensure_nftables_dependency
  else
    return 1
  fi
}

nb_strict_firewall_generate_ruleset() {
  local state="$1" output="$2" tmp owner transport port address proto
  nb_strict_firewall_state_valid "$state" || return 1
  tmp="$(mktemp_file .ingress-firewall.nft)" || return 1
  {
    printf 'table %s %s {\n' "$NOBRAND_INGRESS_NFT_FAMILY" "$NOBRAND_INGRESS_NFT_TABLE"
    printf '  comment "Owned by NoBrand-OneClick Strict Ingress"\n'
    printf '  chain input {\n    type filter hook input priority -10; policy accept;\n'
    while IFS=$'\t' read -r owner transport port address; do
      [ -n "$owner" ] || continue
      proto="$(printf '%s' "$transport" | tr '[:upper:]' '[:lower:]')"
      printf '    ip daddr != %s %s dport %s drop comment "nobrand:strict:%s:%s"\n' \
        "$address" "$proto" "$port" "$owner" "$proto"
    done < <(jq -r '.rules|sort_by(.owner,.transport,.port)[]|
      [.owner,.transport,(.port|tostring),.local_address]|@tsv' "$state")
    printf '  }\n}\n'
  } >"$tmp" || { rm -f "$tmp"; return 1; }
  mkdir -p "$(dirname "$output")" || { rm -f "$tmp"; return 1; }
  install -m 0600 "$tmp" "$output"
  local rc=$?
  rm -f "$tmp"
  return "$rc"
}

nb_strict_firewall_apply_state() {
  local state="$1" count candidate batch
  nb_strict_firewall_state_valid "$state" || return 1
  [ "${NOBRAND_TEST_STRICT_FIREWALL_APPLY_FAIL:-0}" -eq 0 ] || return 1
  count="$(jq '.rules|length' "$state")" || return 1
  if [ "$count" -eq 0 ]; then
    nb_strict_firewall_remove_table || return 1
    rm -f "$NOBRAND_INGRESS_FIREWALL_RULESET"
    return 0
  fi
  nb_strict_firewall_ensure_dependency || return 1
  candidate="$(mktemp_file .ingress-firewall-candidate.nft)" || return 1
  batch="$(mktemp_file .ingress-firewall-batch.nft)" || { rm -f "$candidate"; return 1; }
  nb_strict_firewall_generate_ruleset "$state" "$candidate" || { rm -f "$candidate" "$batch"; return 1; }
  {
    if nft list table "$NOBRAND_INGRESS_NFT_FAMILY" "$NOBRAND_INGRESS_NFT_TABLE" >/dev/null 2>&1; then
      nb_strict_firewall_table_owned || { rm -f "$candidate" "$batch"; return 1; }
      printf 'delete table %s %s\n' "$NOBRAND_INGRESS_NFT_FAMILY" "$NOBRAND_INGRESS_NFT_TABLE"
    fi
    cat "$candidate"
  } >"$batch"
  nft -c -f "$batch" >/dev/null 2>&1 && nft -f "$batch" \
    && nb_atomic_install_file "$candidate" "$NOBRAND_INGRESS_FIREWALL_RULESET" 0600
  local rc=$?
  rm -f "$candidate" "$batch"
  return "$rc"
}

nb_strict_firewall_current_or_empty() {
  local output="$1"
  if [ -e "$NOBRAND_INGRESS_FIREWALL_STATE_FILE" ]; then
    nb_strict_firewall_state_valid "$NOBRAND_INGRESS_FIREWALL_STATE_FILE" || return 1
    cp -a "$NOBRAND_INGRESS_FIREWALL_STATE_FILE" "$output"
  else
    nb_strict_firewall_empty_state >"$output"
  fi
}

nb_strict_firewall_commit_candidate() {
  local candidate="$1" old old_existed=0 rollback_failed=0
  nb_strict_firewall_state_valid "$candidate" || return 1
  old="$(mktemp_file .ingress-firewall-old)" || return 1
  [ ! -e "$NOBRAND_INGRESS_FIREWALL_STATE_FILE" ] || old_existed=1
  nb_strict_firewall_current_or_empty "$old" || { rm -f "$old"; return 1; }
  if nb_strict_firewall_apply_state "$candidate" \
     && nb_atomic_install_file "$candidate" "$NOBRAND_INGRESS_FIREWALL_STATE_FILE" 0600; then
    rm -f "$old"
    return 0
  fi
  nb_strict_firewall_apply_state "$old" >/dev/null 2>&1 || rollback_failed=1
  if [ "$old_existed" -eq 1 ]; then
    nb_atomic_install_file "$old" "$NOBRAND_INGRESS_FIREWALL_STATE_FILE" 0600 >/dev/null 2>&1 \
      || rollback_failed=1
  else
    rm -f "$NOBRAND_INGRESS_FIREWALL_STATE_FILE" || rollback_failed=1
  fi
  rm -f "$old"
  [ "$rollback_failed" -eq 0 ] || warn 'Strict-ingress firewall rollback failed; run doctor immediately'
  return 1
}

nb_strict_firewall_remove_owner() {
  local owner="$1" candidate
  candidate="$(mktemp_file .ingress-firewall-remove)" || return 1
  nb_strict_firewall_current_or_empty "$candidate" || { rm -f "$candidate"; return 1; }
  jq --arg owner "$owner" '.rules|=map(select(.owner!=$owner))' "$candidate" >"${candidate}.next" \
    && mv -f "${candidate}.next" "$candidate" \
    && nb_strict_firewall_commit_candidate "$candidate"
  local rc=$?
  rm -f "$candidate" "${candidate}.next"
  return "$rc"
}

nb_strict_firewall_rule_owned() {
  local owner="$1" transport="$2" port="$3" address="$4" listing proto
  nb_strict_firewall_state_valid "$NOBRAND_INGRESS_FIREWALL_STATE_FILE" || return 1
  jq -e --arg owner "$owner" --arg transport "$transport" --arg address "$address" \
    --argjson port "$port" \
    'any(.rules[];.owner==$owner and .transport==$transport and .port==$port and .local_address==$address)' \
    "$NOBRAND_INGRESS_FIREWALL_STATE_FILE" >/dev/null || return 1
  nb_strict_firewall_table_owned || return 1
  listing="$(nft list table "$NOBRAND_INGRESS_NFT_FAMILY" "$NOBRAND_INGRESS_NFT_TABLE" 2>/dev/null)" \
    || return 1
  proto="$(printf '%s' "$transport" | tr '[:upper:]' '[:lower:]')"
  grep -Fq "nobrand:strict:${owner}:${proto}" <<<"$listing" \
    && grep -Fq "ip daddr != ${address}" <<<"$listing"
}

nb_strict_firewall_clear_all() {
  local empty
  empty="$(mktemp_file .ingress-firewall-empty)" || return 1
  nb_strict_firewall_empty_state >"$empty"
  nb_strict_firewall_commit_candidate "$empty"
  local rc=$?
  rm -f "$empty"
  return "$rc"
}

nb_strict_firewall_restore_authoritative() {
  local state tmp
  if [ -e "$NOBRAND_INGRESS_FIREWALL_STATE_FILE" ]; then
    state="$NOBRAND_INGRESS_FIREWALL_STATE_FILE"
    nb_strict_firewall_state_valid "$state" || return 1
  else
    tmp="$(mktemp_file .ingress-firewall-restore-empty)" || return 1
    nb_strict_firewall_empty_state >"$tmp"
    state="$tmp"
  fi
  nb_strict_firewall_apply_state "$state"
  local rc=$?
  [ -z "${tmp:-}" ] || rm -f "$tmp"
  return "$rc"
}

nb_ingress_profile_name() {
  local profile_id="${1:-}"
  [ -n "$profile_id" ] || { printf 'Legacy Default Route'; return 0; }
  nb_ingress_profile_json "$profile_id" 2>/dev/null | jq -r '.name // "Unknown"' \
    || printf 'Unknown'
}

nb_ingress_profile_display_host() {
  local profile_id="${1:-}" profile
  [ -n "$profile_id" ] || return 1
  [ "$profile_id" != "$NOBRAND_LEGACY_INGRESS_PROFILE_ID" ] || return 1
  profile="$(nb_ingress_profile_json "$profile_id")" || return 1
  jq -r '.display_host_default // empty' <<<"$profile"
}

nb_ingress_profile_display_port() {
  local profile_id="$1" actual_port="$2" profile policy
  profile="$(nb_ingress_profile_json "$profile_id")" || { printf '%s' "$actual_port"; return 0; }
  policy="$(jq -r .display_port_policy <<<"$profile")"
  if [ "$policy" = custom ]; then jq -r .display_port <<<"$profile"; else printf '%s' "$actual_port"; fi
}

nb_ingress_normalize_reserved() {
  local raw="${1:-}" item canonical output="" seen='|'
  raw="${raw//,/ }"
  for item in $raw; do
    canonical="$(normalize_uint "$item" 2>/dev/null || true)"
    nb_valid_port "$canonical" || return 1
    case "$seen" in *"|${canonical}|"*) continue ;; esac
    seen="${seen}${canonical}|"
    output="${output}${output:+,}${canonical}"
  done
  printf '%s' "$output"
}

nb_ingress_reserved_json() {
  local normalized item json='[]'
  normalized="$(nb_ingress_normalize_reserved "${1:-}")" || return 1
  for item in ${normalized//,/ }; do
    json="$(jq --argjson value "$item" '. + [$value]' <<<"$json")" || return 1
  done
  printf '%s' "$json"
}

nb_ingress_validate_profile_values() {
  local type="$1" interface="$2" address="$3" policy="$4" range_start="$5" range_end="$6"
  local reserved="$7" display_host="$8" display_port_policy="$9" display_port="${10}" enforcement="${11:-permissive}" base item
  case "$type" in public|mapped) ;; *) return 1 ;; esac
  nb_ingress_interface_exists "$interface" || return 1
  nb_ingress_address_on_interface "$interface" "$address" || return 1
  case "$policy" in
    derived-tail)
      base="$(nb_port_base_for_ip "$address")" || return 1
      [ -z "$range_start$range_end" ] || return 1
      ;;
    custom-range)
      nb_valid_port "$range_start" && nb_valid_port "$range_end" || return 1
      range_start="$(normalize_uint "$range_start")"; range_end="$(normalize_uint "$range_end")"
      [ "$range_start" -ge 1025 ] && [ "$range_start" -le "$range_end" ] || return 1
      ;;
    manual-only) [ -z "$range_start$range_end" ] || return 1 ;;
    *) return 1 ;;
  esac
  reserved="$(nb_ingress_normalize_reserved "$reserved")" || return 1
  for item in ${reserved//,/ }; do nb_valid_port "$item" || return 1; done
  if [ "$type" = mapped ]; then valid_advertise_host "$display_host" || return 1; fi
  [ -z "$display_host" ] || valid_advertise_host "$display_host" || return 1
  case "$display_port_policy" in
    follow-actual) [ -z "$display_port" ] || return 1 ;;
    custom) valid_advertise_port "$display_port" || return 1 ;;
    *) return 1 ;;
  esac
  case "$enforcement" in permissive|strict) ;; *) return 1 ;; esac
}

nb_ingress_reserved_conflicts() {
  local reserved="${1:-}" owner transport port _host _display item
  while IFS='|' read -r owner transport port _host _display; do
    [ -n "$owner" ] || continue
    for item in ${reserved//,/ }; do
      if [ "$port" = "$item" ]; then printf '%s|%s|%s' "$owner" "$transport" "$port"; return 0; fi
    done
  done < <(nb_registry_rows)
  return 1
}

nb_ingress_add() {
  local id now base reserved_json range_start_json=null range_end_json=null display_port_json=null tmp profile conflict enabled
  require_root
  [ -n "$INGRESS_NAME" ] && [ -n "$INGRESS_TYPE" ] && [ -n "$INGRESS_INTERFACE" ] \
    && [ -n "$INGRESS_ADDRESS" ] && [ -n "$INGRESS_PORT_POLICY" ] \
    || die 'ingress add requires --name --type --interface --address --port-policy'
  [ "${#INGRESS_NAME}" -le 64 ] && ! has_control_chars "$INGRESS_NAME" || die 'Ingress profile name is invalid'
  case "$INGRESS_NAME" in
    "$NOBRAND_LEGACY_INGRESS_PROFILE_ID"|'Legacy Default Route')
      die 'Ingress profile name conflicts with a reserved profile selector'
      ;;
  esac
  [[ ! "$INGRESS_NAME" =~ ^i[0-9a-f]{16}$ ]] \
    || die 'Ingress profile name conflicts with the profile-ID namespace'
  INGRESS_DISPLAY_PORT_POLICY="${INGRESS_DISPLAY_PORT_POLICY:-follow-actual}"
  INGRESS_ENFORCEMENT="${INGRESS_ENFORCEMENT:-permissive}"
  enabled="${INGRESS_ENABLED:-true}"
  case "$enabled" in true|false) ;; *) die 'Ingress enabled state is invalid' ;; esac
  if [ "$INGRESS_TYPE" = public ] && [ -z "$INGRESS_DISPLAY_HOST_DEFAULT" ]; then
    INGRESS_DISPLAY_HOST_DEFAULT="$INGRESS_ADDRESS"
  fi
  if [ "$INGRESS_PORT_POLICY" = derived-tail ] && [ "$INGRESS_RESERVED_CLI" -eq 0 ]; then
    base="$(nb_port_base_for_ip "$INGRESS_ADDRESS" 2>/dev/null || true)"
    [ -n "$base" ] || die 'Derived-tail is invalid for this IPv4; use custom-range or manual-only'
    INGRESS_RESERVED_PORTS="$base"
  fi
  nb_ingress_validate_profile_values "$INGRESS_TYPE" "$INGRESS_INTERFACE" "$INGRESS_ADDRESS" \
    "$INGRESS_PORT_POLICY" "$INGRESS_RANGE_START" "$INGRESS_RANGE_END" "$INGRESS_RESERVED_PORTS" \
    "$INGRESS_DISPLAY_HOST_DEFAULT" "$INGRESS_DISPLAY_PORT_POLICY" "$INGRESS_DISPLAY_PORT" "$INGRESS_ENFORCEMENT" \
    || die 'Ingress profile values are invalid or the local IPv4 is not assigned to the selected interface'
  INGRESS_RESERVED_PORTS="$(nb_ingress_normalize_reserved "$INGRESS_RESERVED_PORTS")"
  if conflict="$(nb_ingress_reserved_conflicts "$INGRESS_RESERVED_PORTS" 2>/dev/null)"; then
    die "Reserved port conflicts with an existing managed listener: ${conflict}"
  fi
  nb_ingress_ensure_state || return 1
  jq -e --arg name "$INGRESS_NAME" 'all(.profiles[];.name!=$name)' "$NOBRAND_INGRESS_STATE_FILE" >/dev/null \
    || die "Ingress profile name already exists: ${INGRESS_NAME}"
  id="$(nb_ingress_generate_id)" || return 1
  now="$(nb_ingress_now)"
  reserved_json="$(nb_ingress_reserved_json "$INGRESS_RESERVED_PORTS")" || return 1
  if [ "$INGRESS_PORT_POLICY" = custom-range ]; then
    range_start_json="$(normalize_uint "$INGRESS_RANGE_START")"
    range_end_json="$(normalize_uint "$INGRESS_RANGE_END")"
  fi
  [ "$INGRESS_DISPLAY_PORT_POLICY" != custom ] || display_port_json="$(normalize_uint "$INGRESS_DISPLAY_PORT")"
  profile="$(jq -n --arg id "$id" --arg name "$INGRESS_NAME" --arg type "$INGRESS_TYPE" \
    --arg interface "$INGRESS_INTERFACE" --arg address "$INGRESS_ADDRESS" \
    --arg policy "$INGRESS_PORT_POLICY" --argjson range_start "$range_start_json" \
    --argjson range_end "$range_end_json" --argjson reserved "$reserved_json" \
    --arg display_host "$INGRESS_DISPLAY_HOST_DEFAULT" \
    --arg display_port_policy "$INGRESS_DISPLAY_PORT_POLICY" --argjson display_port "$display_port_json" \
    --arg enforcement "$INGRESS_ENFORCEMENT" --arg now "$now" --argjson enabled "$enabled" '
      {profile_id:$id,name:$name,type:$type,interface:$interface,local_address:$address,
       port_policy:$policy,range_start:$range_start,range_end:$range_end,reserved_ports:$reserved,
       display_host_default:$display_host,display_port_policy:$display_port_policy,display_port:$display_port,
       ingress_enforcement:$enforcement,enabled:$enabled,created_at:$now,updated_at:$now}
    ')" || return 1
  tmp="$(mktemp_file .ingress-add)" || return 1
  jq --argjson profile "$profile" '.profiles += [$profile]' "$NOBRAND_INGRESS_STATE_FILE" >"$tmp" \
    && nb_ingress_state_valid "$tmp" && nb_atomic_install_file "$tmp" "$NOBRAND_INGRESS_STATE_FILE" 0600
  local rc=$?
  rm -f "$tmp"
  [ "$rc" -ne 0 ] || printf 'Ingress profile created: %s (%s)\n' "$id" "$INGRESS_NAME"
  return "$rc"
}

nb_ingress_profile_reference_rows() {
  local profile_id="$1"
  NOBRAND_SNELL_STATE_DIR="$NOBRAND_SNELL_STATE_DIR" NOBRAND_HY2_STATE_FILE="$NOBRAND_HY2_STATE_FILE" \
  NOBRAND_VLESS_STATE_FILE="$NOBRAND_VLESS_STATE_FILE" NOBRAND_TUIC_STATE_DIR="$NOBRAND_TUIC_STATE_DIR" \
  NOBRAND_REALITY_STATE_DIR="$NOBRAND_REALITY_STATE_DIR" \
  NOBRAND_SSH_STATE_FILE="$NOBRAND_SSH_STATE_FILE" NOBRAND_FORWARD_STATE_FILE="$NOBRAND_FORWARD_STATE_FILE" \
  MITA_USERS_STATE="$MITA_USERS_STATE" python3 - "$profile_id" <<'PY'
import glob, json, os, sys
profile = sys.argv[1]
def load(path):
    try: return json.load(open(path, encoding="utf-8"))
    except Exception: return None
def emit(owner, value):
    if not value: return
    if profile == "*": print(str(value) + "|" + owner)
    elif value == profile: print(owner)
for path in glob.glob(os.path.join(os.environ.get("NOBRAND_SNELL_STATE_DIR", ""), "*.json")):
    state=load(path)
    if state: emit("snell:" + str(state.get("instance_id") or path), state.get("ingress_profile_id"))
for env, owner in (("NOBRAND_HY2_STATE_FILE","hy2:default"),("NOBRAND_VLESS_STATE_FILE","vless-sudoku:default")):
    state=load(os.environ.get(env,""))
    if state: emit(owner, state.get("ingress_profile_id"))
for path in glob.glob(os.path.join(os.environ.get("NOBRAND_TUIC_STATE_DIR", ""), "*", "state.json")):
    state=load(path)
    if state: emit("tuic:" + str(state.get("instance_id") or path), state.get("ingress_profile_id"))
for path in glob.glob(os.path.join(os.environ.get("NOBRAND_REALITY_STATE_DIR", ""), "*", "state.json")):
    state=load(path)
    if state: emit("vless-reality:" + str(state.get("instance_id") or path), state.get("ingress_profile_id"))
state=load(os.environ.get("NOBRAND_SSH_STATE_FILE", ""))
if state:
    emit("ssh-tunnel:policy", state.get("ingress_profile_id"))
    for user in state.get("users") or []:
        emit("ssh-tunnel:" + str(user.get("account_id") or user.get("label")), user.get("ingress_profile_id"))
state=load(os.environ.get("NOBRAND_FORWARD_STATE_FILE", ""))
if state:
    for rule in state.get("rules") or []:
        emit("forward:" + str(rule.get("rule_id")), rule.get("ingress_profile_id"))
state=load(os.environ.get("MITA_USERS_STATE", ""))
if state:
    for user in state.get("users") or []:
        emit("mieru:" + str(user.get("instance_id") or user.get("name")), user.get("ingress_profile_id"))
PY
}

nb_ingress_delete() {
  local id refs tmp
  require_root
  id="$(nb_ingress_profile_id "$INGRESS_PROFILE_SELECTOR" 2>/dev/null || true)"
  [ -n "$id" ] && [ "$id" != "$NOBRAND_LEGACY_INGRESS_PROFILE_ID" ] || die 'Ingress profile not found or built-in profile cannot be deleted'
  refs="$(nb_ingress_profile_reference_rows "$id")"
  [ -z "$refs" ] || { printf 'Ingress profile is referenced by:\n%s\n' "$refs" >&2; return 1; }
  tmp="$(mktemp_file .ingress-delete)" || return 1
  jq --arg id "$id" '
    .profiles |= map(select(.profile_id!=$id)) |
    if .default_profile_id==$id then .default_profile_id=null else . end
  ' "$NOBRAND_INGRESS_STATE_FILE" >"$tmp" \
    && nb_ingress_state_valid "$tmp" && nb_atomic_install_file "$tmp" "$NOBRAND_INGRESS_STATE_FILE" 0600
  local rc=$?
  rm -f "$tmp"
  return "$rc"
}

nb_ingress_modify() {
  local id old name type interface address policy range_start range_end reserved display_host display_policy display_port enabled enforcement
  local old_enforcement old_interface old_address runtime_change=0 refs="" snapshot=""
  local base reserved_json range_start_json=null range_end_json=null display_port_json=null conflict tmp
  require_root
  id="$(nb_ingress_profile_id "$INGRESS_PROFILE_SELECTOR" 2>/dev/null || true)"
  [ -n "$id" ] && [ "$id" != "$NOBRAND_LEGACY_INGRESS_PROFILE_ID" ] || die 'Ingress profile not found or built-in profile cannot be modified'
  old="$(nb_ingress_profile_json "$id")"
  name="$(jq -r .name <<<"$old")"; type="$(jq -r .type <<<"$old")"
  interface="$(jq -r .interface <<<"$old")"; address="$(jq -r .local_address <<<"$old")"
  old_interface="$interface"; old_address="$address"
  policy="$(jq -r .port_policy <<<"$old")"
  range_start="$(jq -r '.range_start // empty' <<<"$old")"; range_end="$(jq -r '.range_end // empty' <<<"$old")"
  reserved="$(jq -r '.reserved_ports|join(",")' <<<"$old")"
  display_host="$(jq -r .display_host_default <<<"$old")"; display_policy="$(jq -r .display_port_policy <<<"$old")"
  display_port="$(jq -r '.display_port // empty' <<<"$old")"; enabled="$(jq -r .enabled <<<"$old")"
  enforcement="$(jq -r '.ingress_enforcement // "permissive"' <<<"$old")"; old_enforcement="$enforcement"
  [ "$INGRESS_NAME_CLI" -eq 0 ] || name="$INGRESS_NAME"
  [ "$INGRESS_TYPE_CLI" -eq 0 ] || type="$INGRESS_TYPE"
  [ "$INGRESS_INTERFACE_CLI" -eq 0 ] || interface="$INGRESS_INTERFACE"
  [ "$INGRESS_ADDRESS_CLI" -eq 0 ] || address="$INGRESS_ADDRESS"
  if [ "$INGRESS_PORT_POLICY_CLI" -eq 1 ]; then
    policy="$INGRESS_PORT_POLICY"; range_start=""; range_end=""
  fi
  [ "$INGRESS_RANGE_START_CLI" -eq 0 ] || range_start="$INGRESS_RANGE_START"
  [ "$INGRESS_RANGE_END_CLI" -eq 0 ] || range_end="$INGRESS_RANGE_END"
  [ "$INGRESS_RESERVED_CLI" -eq 0 ] || reserved="$INGRESS_RESERVED_PORTS"
  [ "$INGRESS_DISPLAY_HOST_CLI" -eq 0 ] || display_host="$INGRESS_DISPLAY_HOST_DEFAULT"
  if [ "$INGRESS_DISPLAY_PORT_POLICY_CLI" -eq 1 ]; then
    display_policy="$INGRESS_DISPLAY_PORT_POLICY"; display_port=""
  fi
  [ "$INGRESS_DISPLAY_PORT_CLI" -eq 0 ] || display_port="$INGRESS_DISPLAY_PORT"
  [ "$INGRESS_ENABLED_CLI" -eq 0 ] || enabled="$INGRESS_ENABLED"
  [ "$INGRESS_ENFORCEMENT_CLI" -eq 0 ] || enforcement="$INGRESS_ENFORCEMENT"
  case "$name" in
    "$NOBRAND_LEGACY_INGRESS_PROFILE_ID"|'Legacy Default Route')
      die 'Ingress profile name conflicts with a reserved profile selector'
      ;;
  esac
  [[ ! "$name" =~ ^i[0-9a-f]{16}$ ]] \
    || die 'Ingress profile name conflicts with the profile-ID namespace'
  if [ "$enabled" = false ] \
     && [ "$(nb_ingress_default_profile_id 2>/dev/null || true)" = "$id" ]; then
    die 'Unset the default ingress profile before disabling it'
  fi
  if [ "$policy" = derived-tail ]; then
    base="$(nb_port_base_for_ip "$address" 2>/dev/null || true)"
    [ -n "$base" ] || die 'Derived-tail is invalid for this IPv4; use custom-range or manual-only'
    [ "$INGRESS_PORT_POLICY_CLI" -eq 0 ] || [ "$INGRESS_RESERVED_CLI" -eq 1 ] || reserved="$base"
  fi
  [ "$policy" = custom-range ] || { range_start=""; range_end=""; }
  [ "$display_policy" = custom ] || display_port=""
  nb_ingress_validate_profile_values "$type" "$interface" "$address" "$policy" "$range_start" "$range_end" \
    "$reserved" "$display_host" "$display_policy" "$display_port" "$enforcement" \
    || die 'Modified ingress profile values are invalid'
  reserved="$(nb_ingress_normalize_reserved "$reserved")"
  if conflict="$(nb_ingress_reserved_conflicts "$reserved" 2>/dev/null)"; then
    die "Reserved port conflicts with an existing managed listener: ${conflict}"
  fi
  jq -e --arg id "$id" --arg name "$name" 'all(.profiles[]; .profile_id==$id or .name!=$name)' \
    "$NOBRAND_INGRESS_STATE_FILE" >/dev/null || die "Ingress profile name already exists: ${name}"
  reserved_json="$(nb_ingress_reserved_json "$reserved")" || return 1
  if [ "$policy" = custom-range ]; then range_start_json="$range_start"; range_end_json="$range_end"; fi
  [ "$display_policy" != custom ] || display_port_json="$display_port"
  if [ "$old_enforcement" != "$enforcement" ] \
     || { [ "$enforcement" = strict ] \
          && { [ "$old_interface" != "$interface" ] || [ "$old_address" != "$address" ]; }; }; then
    runtime_change=1
  fi
  if [ "$runtime_change" -eq 1 ]; then
    refs="$(nb_ingress_profile_reference_rows "$id" | grep -Ev '^ssh-tunnel:' || true)"
    if [ -n "$refs" ] && [ "${INGRESS_APPLY_EXISTING:-0}" -ne 1 ]; then
      printf 'Ingress enforcement/listen identity change affects managed nodes:\n%s\n' "$refs" >&2
      die 'Re-run with --apply-existing for explicit transactional migration'
    fi
  fi
  tmp="$(mktemp_file .ingress-modify)" || return 1
  jq --arg id "$id" --arg name "$name" --arg type "$type" --arg interface "$interface" --arg address "$address" \
    --arg policy "$policy" --argjson range_start "$range_start_json" --argjson range_end "$range_end_json" \
    --argjson reserved "$reserved_json" --arg display_host "$display_host" --arg display_policy "$display_policy" \
    --argjson display_port "$display_port_json" --arg enforcement "$enforcement" \
    --argjson enabled "$enabled" --arg updated "$(nb_ingress_now)" '
      (.profiles[]|select(.profile_id==$id)) |=
       (.name=$name|.type=$type|.interface=$interface|.local_address=$address|.port_policy=$policy|
        .range_start=$range_start|.range_end=$range_end|.reserved_ports=$reserved|
        .display_host_default=$display_host|.display_port_policy=$display_policy|.display_port=$display_port|
        .ingress_enforcement=$enforcement|.enabled=$enabled|.updated_at=$updated)
    ' "$NOBRAND_INGRESS_STATE_FILE" >"$tmp" \
    && nb_ingress_state_valid "$tmp"
  local rc=$?
  if [ "$rc" -eq 0 ]; then
    snapshot="$(mktemp_file .ingress-profile-rollback)" || rc=1
  fi
  if [ "$rc" -eq 0 ]; then
    cp -a "$NOBRAND_INGRESS_STATE_FILE" "$snapshot" \
      && nb_atomic_install_file "$tmp" "$NOBRAND_INGRESS_STATE_FILE" 0600 || rc=1
  fi
  if [ "$rc" -eq 0 ] && [ "$runtime_change" -eq 1 ] && [ -n "$refs" ]; then
    if ! nb_ingress_apply_profile "$id"; then
      nb_atomic_install_file "$snapshot" "$NOBRAND_INGRESS_STATE_FILE" 0600 >/dev/null 2>&1 || true
      nb_ingress_apply_profile "$id" >/dev/null 2>&1 \
        || warn 'Ingress profile metadata was restored but one or more listener rollbacks failed; run doctor immediately'
      rc=1
    fi
  fi
  rm -f "$tmp"
  [ -z "$snapshot" ] || rm -f "$snapshot"
  return "$rc"
}

nb_ingress_set_default() {
  local id tmp
  require_root
  id="$(nb_ingress_profile_id "$INGRESS_PROFILE_SELECTOR" 2>/dev/null || true)"
  [ -n "$id" ] && [ "$id" != "$NOBRAND_LEGACY_INGRESS_PROFILE_ID" ] || die 'Default ingress must be an enabled explicit profile'
  [ "$(nb_ingress_profile_json "$id" | jq -r .enabled)" = true ] || die 'Disabled ingress profile cannot be the default'
  nb_ingress_ensure_state || return 1
  tmp="$(mktemp_file .ingress-default)" || return 1
  jq --arg id "$id" '.default_profile_id=$id' "$NOBRAND_INGRESS_STATE_FILE" >"$tmp" \
    && nb_ingress_state_valid "$tmp" && nb_atomic_install_file "$tmp" "$NOBRAND_INGRESS_STATE_FILE" 0600
  local rc=$?
  rm -f "$tmp"
  return "$rc"
}

nb_ingress_unset_default() {
  local tmp
  require_root
  nb_ingress_ensure_state || return 1
  tmp="$(mktemp_file .ingress-default)" || return 1
  jq '.default_profile_id=null' "$NOBRAND_INGRESS_STATE_FILE" >"$tmp" \
    && nb_ingress_state_valid "$tmp" && nb_atomic_install_file "$tmp" "$NOBRAND_INGRESS_STATE_FILE" 0600
  local rc=$?
  rm -f "$tmp"
  return "$rc"
}

nb_ingress_profile_auto_range() {
  local profile_id="$1" profile policy address base
  profile="$(nb_ingress_profile_json "$profile_id")" || return 1
  policy="$(jq -r .port_policy <<<"$profile")"
  case "$policy" in
    derived-tail)
      address="$(jq -r .local_address <<<"$profile")"
      if [ "$profile_id" = "$NOBRAND_LEGACY_INGRESS_PROFILE_ID" ]; then
        nb_tail_port_bounds "$address"
      else
        base="$(nb_port_base_for_ip "$address")" || return 1
        printf '%s|%s' "$((base + 1))" "$((base + 99))"
      fi
      ;;
    custom-range) jq -r '[.range_start,.range_end]|join("|")' <<<"$profile" ;;
    manual-only) return 2 ;;
    *) return 1 ;;
  esac
}

nb_ingress_port_is_reserved() {
  local profile_id="$1" port profile
  port="$(normalize_uint "$2")" || return 1
  if [ -z "$profile_id" ] || [ "$profile_id" = "$NOBRAND_LEGACY_INGRESS_PROFILE_ID" ]; then
    nb_port_is_tail_base_reserved "$port"
    return $?
  fi
  profile="$(nb_ingress_profile_json "$profile_id")" || return 1
  jq -e --argjson port "$port" 'any(.reserved_ports[]; .==$port)' <<<"$profile" >/dev/null
}

nb_ingress_list() {
  local default_id id name type interface address policy enforcement is_default range
  default_id="$(nb_ingress_default_profile_id 2>/dev/null || true)"
  printf '%-19s %-24s %-8s %-12s %-15s %-14s %-11s %-13s %s\n' \
    ID NAME TYPE INTERFACE ADDRESS PORT-POLICY ENFORCEMENT AUTO-RANGE DEFAULT
  printf '%-19s %-24s %-8s %-12s %-15s %-14s %-11s %-13s %s\n' \
    "$NOBRAND_LEGACY_INGRESS_PROFILE_ID" 'Legacy Default Route' built-in '(system)' \
    "$(nb_detect_local_ipv4 2>/dev/null || printf unavailable)" derived-tail permissive \
    "$(nb_ingress_profile_auto_range "$NOBRAND_LEGACY_INGRESS_PROFILE_ID" 2>/dev/null | tr '|' '-' || printf fallback)" \
    "$([ -z "$default_id" ] && printf yes || printf no)"
  nb_ingress_state_valid || return 0
  while IFS=$'\t' read -r id name type interface address policy enforcement is_default; do
        range="$(nb_ingress_profile_auto_range "$id" 2>/dev/null | tr '|' '-' || printf manual)"
        printf '%-19s %-24s %-8s %-12s %-15s %-14s %-11s %-13s %s\n' \
          "$id" "$name" "$type" "$interface" "$address" "$policy" "$enforcement" "$range" "$is_default"
  done < <(jq -r --arg default "$default_id" '.profiles|sort_by(.name)[]|[
    .profile_id,.name,.type,.interface,.local_address,.port_policy,(.ingress_enforcement // "permissive"),
    (if .profile_id==$default then "yes" else "no" end)]|@tsv' "$NOBRAND_INGRESS_STATE_FILE")
}

nb_ingress_show() {
  local profile selector="${INGRESS_PROFILE_SELECTOR:-}" range
  profile="$(nb_ingress_profile_json "$selector")" || die "Ingress profile not found: ${selector}"
  range="$(nb_ingress_profile_auto_range "$(jq -r .profile_id <<<"$profile")" 2>/dev/null | tr '|' '-' || printf none)"
  jq -r --arg range "$range" '
    "ID: \(.profile_id)\nName: \(.name)\nType: \(.type)\nInterface: \(.interface)\nLocal address: \(.local_address)\n"+
    "Port policy: \(.port_policy)\nIngress enforcement: \(.ingress_enforcement // "permissive")\nAuto range: \($range)\nReserved: \(.reserved_ports|join(","))\n"+
    "Display host default: \(.display_host_default)\nDisplay port policy: \(.display_port_policy)"+
    (if .display_port==null then "" else "\nDisplay port: \(.display_port)" end)+"\nEnabled: \(.enabled)"
  ' <<<"$profile"
}

nb_ingress_owner_capability() {
  case "$1" in
    mieru:*) printf firewall ;;
    snell:*|hy2:*|vless-sudoku:*|vless-reality:*|tuic:*) printf native-bind ;;
    forward:*)
      if [ "$(nb_owner_ingress_method "$1" 2>/dev/null || true)" = address-match ]; then
        printf address-match
      elif [ "$(jq -r --arg id "${1#forward:}" '.rules[]|select(.rule_id==$id)|.backend // empty' \
          "$NOBRAND_FORWARD_STATE_FILE" 2>/dev/null || true)" = nftables ]; then
        printf address-match
      else
        printf native-bind
      fi
      ;;
    ssh-tunnel:*) printf not-applicable ;;
    *) return 1 ;;
  esac
}

nb_ingress_apply_owner() {
  local owner="$1"
  case "$owner" in
    mieru:*) mieru_apply_ingress_enforcement "${owner#mieru:}" ;;
    snell:*) snell_apply_ingress_enforcement "${owner#snell:}" ;;
    hy2:*) hysteria2_apply_ingress_enforcement ;;
    vless-sudoku:*) vless_sudoku_apply_ingress_enforcement ;;
    vless-reality:*) reality_apply_ingress_enforcement "${owner#vless-reality:}" ;;
    tuic:*) tuic_apply_ingress_enforcement "${owner#tuic:}" ;;
    forward:*) forward_apply_ingress_enforcement "${owner#forward:}" ;;
    ssh-tunnel:*) return 0 ;;
    *) return 1 ;;
  esac
}

nb_ingress_apply_profile() {
  local profile_id="$1" owner failed=0 seen='|'
  nb_ingress_profile_json "$profile_id" >/dev/null || return 1
  while IFS= read -r owner; do
    [ -n "$owner" ] || continue
    case "$seen" in *"|${owner}|"*) continue ;; esac
    seen="${seen}${owner}|"
    case "$owner" in ssh-tunnel:*) continue ;; esac
    if ! nb_ingress_apply_owner "$owner"; then
      warn "Ingress enforcement migration failed for ${owner}"
      failed=1
      break
    fi
  done < <(nb_ingress_profile_reference_rows "$profile_id")
  return "$failed"
}

nb_ingress_apply() {
  local id
  require_root
  id="$(nb_ingress_profile_id "$INGRESS_PROFILE_SELECTOR" 2>/dev/null || true)"
  [ -n "$id" ] && [ "$id" != "$NOBRAND_LEGACY_INGRESS_PROFILE_ID" ] \
    || die 'Ingress profile not found or built-in profile cannot be applied'
  nb_ingress_apply_profile "$id" || return 1
  printf 'Ingress enforcement applied: %s (%s)\n' "$id" "$(nb_ingress_profile_name "$id")"
}

nb_ingress_doctor() {
  local failed=0 default_id profile id name interface address policy range port owner refs egress
  local referenced_profile referenced_owner transport key seen='|' profile_id lo hi duplicate_count=0
  local _advertise_host _advertise_port expected_policy expected_method actual_policy actual_method actual_address capability enabled
  if [ ! -e "$NOBRAND_INGRESS_STATE_FILE" ]; then
    nb_doctor_line PASS 'Ingress state: legacy-compatible (no explicit profiles)'
  elif nb_ingress_state_valid; then
    nb_doctor_line PASS 'Ingress profile JSON/state valid (schema v3)'
  else
    nb_doctor_line FAIL 'Ingress profile JSON/state invalid'
    return 1
  fi
  default_id="$(nb_ingress_default_profile_id 2>/dev/null || true)"
  [ -z "$default_id" ] || nb_doctor_line PASS "Default ingress profile exists: $(nb_ingress_profile_name "$default_id")"
  if nb_ingress_state_valid; then
    while IFS= read -r profile; do
      id="$(jq -r .profile_id <<<"$profile")"; name="$(jq -r .name <<<"$profile")"
      interface="$(jq -r .interface <<<"$profile")"; address="$(jq -r .local_address <<<"$profile")"
      policy="$(jq -r .port_policy <<<"$profile")"
      if nb_ingress_address_on_interface "$interface" "$address"; then
        nb_doctor_line PASS "${name}: ${interface}/${address} present"
      else
        nb_doctor_line FAIL "${name}: local address is not present on interface"
        failed=1
      fi
      expected_policy="$(jq -r '.ingress_enforcement // "permissive"' <<<"$profile")"
      case "$expected_policy" in
        strict) nb_doctor_line PASS "${name}: ingress enforcement policy strict" ;;
        permissive) nb_doctor_line INFO "PERMISSIVE_WILDCARD: ${name}" ;;
      esac
      if [ "$policy" = manual-only ]; then
        nb_doctor_line PASS "${name}: manual-only (no auto pool)"
      elif range="$(nb_ingress_profile_auto_range "$id" 2>/dev/null)"; then
        nb_doctor_line PASS "${name}: Derived/explicit range ${range//|/-} valid"
      else
        nb_doctor_line FAIL "${name}: auto pool invalid"
        failed=1
      fi
      while IFS= read -r port; do
        [ -n "$port" ] || continue
        owner="$(nb_registry_rows | awk -F'|' -v p="$port" '$3==p{print $1; exit}')"
        [ -z "$owner" ] || { nb_doctor_line FAIL "${name}: reserved ${port} used by ${owner}"; failed=1; }
      done < <(jq -r '.reserved_ports[]?' <<<"$profile")
      refs="$(nb_ingress_profile_reference_rows "$id")"
      [ -z "$refs" ] || nb_doctor_line PASS "${name}: profile associations readable"
    done < <(jq -c '.profiles[]' "$NOBRAND_INGRESS_STATE_FILE")
  fi
  while IFS='|' read -r referenced_profile referenced_owner; do
    [ -n "$referenced_profile" ] || continue
    if ! nb_ingress_profile_json "$referenced_profile" >/dev/null 2>&1; then
      nb_doctor_line FAIL "${referenced_owner}: unknown ingress profile ${referenced_profile}"
      failed=1
    fi
  done < <(nb_ingress_profile_reference_rows '*')
  while IFS='|' read -r owner transport port _advertise_host _advertise_port; do
    [ -n "$owner" ] || continue
    key="${transport}:${port}"
    case "$seen" in
      *"|${key}|"*)
        nb_doctor_line FAIL "Duplicate host-global port ownership: ${key} (${owner})"
        failed=1
        duplicate_count=$((duplicate_count + 1))
        ;;
      *) seen="${seen}${key}|" ;;
    esac
    profile_id="$(nb_owner_ingress_profile_id "$owner" 2>/dev/null || true)"
    [ -n "$profile_id" ] || profile_id="$NOBRAND_LEGACY_INGRESS_PROFILE_ID"
    if ! profile="$(nb_ingress_profile_json "$profile_id" 2>/dev/null)"; then
      nb_doctor_line FAIL "${owner}: unknown ingress profile ${profile_id}"
      failed=1
      continue
    fi
    if [ "$profile_id" != "$NOBRAND_LEGACY_INGRESS_PROFILE_ID" ]; then
      policy="$(jq -r .port_policy <<<"$profile")"
      if [ "$policy" != manual-only ] && range="$(nb_ingress_profile_auto_range "$profile_id" 2>/dev/null)"; then
        lo="${range%%|*}"; hi="${range#*|}"
        if { [ "$port" -lt "$lo" ] || [ "$port" -gt "$hi" ]; } \
           && ! nb_ingress_port_is_reserved "$profile_id" "$port"; then
          nb_doctor_line WARN "OUTSIDE_CURRENT_AUTO_POOL: ${owner} ${transport}/${port} (${lo}-${hi})"
        fi
      fi
    fi
    case "$owner" in ssh-tunnel:*)
      nb_doctor_line INFO "${owner}: NOT_APPLICABLE_TO_SYSTEM_SSH"
      continue
      ;;
    esac
    expected_policy="$(jq -r '.ingress_enforcement // "permissive"' <<<"$profile")"
    actual_policy="$(nb_owner_ingress_enforcement "$owner" 2>/dev/null || printf permissive)"
    actual_method="$(nb_owner_ingress_method "$owner" 2>/dev/null || printf wildcard)"
    actual_address="$(nb_owner_ingress_local_address "$owner" 2>/dev/null || true)"
    capability="$(nb_ingress_owner_capability "$owner" 2>/dev/null || true)"
    if [ "$expected_policy" = permissive ]; then
      expected_method=wildcard
    else
      expected_method="$capability"
    fi
    if [ "$actual_policy" != "$expected_policy" ] || [ "$actual_method" != "$expected_method" ]; then
      nb_doctor_line FAIL "ENFORCEMENT_DRIFT: ${owner} expected=${expected_policy}/${expected_method} actual=${actual_policy}/${actual_method}"
      failed=1
      continue
    fi
    enabled="$(nb_owner_enabled "$owner" 2>/dev/null || printf true)"
    if [ "$expected_policy" = strict ]; then
      if [ -z "$actual_address" ] || [ "$actual_address" != "$(jq -r .local_address <<<"$profile")" ]; then
        nb_doctor_line FAIL "PROFILE_LOCAL_ADDRESS_MISSING: ${owner}"
        failed=1
      elif [ "$enabled" != true ]; then
        nb_doctor_line PASS "${owner}: strict enforcement state valid (node disabled)"
      elif [ "$actual_method" = firewall ]; then
        nb_strict_firewall_rule_owned "$owner" "$transport" "$port" "$actual_address" \
          && nb_doctor_line PASS "STRICT_FIREWALL_ENFORCEMENT: ${owner} ${transport}/${port}" \
          || { nb_doctor_line FAIL "STRICT_FIREWALL_ENFORCEMENT: ${owner} ${transport}/${port}"; failed=1; }
      elif [ "$actual_method" = address-match ]; then
        forward_listener_enforcement_owned "${owner#forward:}" \
          && nb_doctor_line PASS "STRICT_ADDRESS_MATCH: ${owner} ${transport}/${port} address=${actual_address}" \
          || { nb_doctor_line FAIL "STRICT_ADDRESS_MATCH: ${owner} ${transport}/${port}"; failed=1; }
      elif nb_listener_has_local_address "$transport" "$port" "$actual_address"; then
        nb_doctor_line PASS "STRICT_NATIVE_BIND: ${owner} ${transport}/${port} address=${actual_address}"
      else
        nb_doctor_line FAIL "STRICT_NATIVE_BIND: ${owner} ${transport}/${port} missing exact listener"
        failed=1
      fi
    elif [ "$actual_method" = wildcard ]; then
      nb_doctor_line INFO "PERMISSIVE_WILDCARD: ${owner} ${transport}/${port}"
    fi
  done < <(nb_registry_rows)
  if [ -e "$NOBRAND_INGRESS_FIREWALL_STATE_FILE" ] && ! nb_strict_firewall_state_valid; then
    nb_doctor_line FAIL 'Strict-ingress firewall state invalid'
    failed=1
  fi
  [ "$duplicate_count" -ne 0 ] || nb_doctor_line PASS 'Host-global, transport-aware actual port ownership valid'
  egress="$(nb_ingress_default_egress 2>/dev/null || true)"
  if [ -n "$egress" ]; then
    nb_doctor_line INFO "Current system default egress (read-only): ${egress%%|*} / ${egress#*|}"
  else
    nb_doctor_line INFO 'Current system default egress unavailable (read-only observation only)'
  fi
  [ "$failed" -eq 0 ] && nb_doctor_line PASS 'Ingress Doctor'
  [ "$failed" -eq 0 ]
}

nobrand_run_ingress_action() {
  local lock_required=0 rc=0
  case "${INGRESS_ACTION:-list}" in
    add|modify|delete|set-default|unset-default|apply)
      lock_required=1
      require_root || return 1
      nb_init_state_layout || return 1
      admin_lock_acquire || return 1
      ;;
  esac
  case "${INGRESS_ACTION:-list}" in
    list) nb_ingress_list || rc=$? ;;
    show) nb_ingress_show || rc=$? ;;
    add) nb_ingress_add || rc=$? ;;
    modify) nb_ingress_modify || rc=$? ;;
    apply) nb_ingress_apply || rc=$? ;;
    delete) nb_ingress_delete || rc=$? ;;
    set-default) nb_ingress_set_default || rc=$? ;;
    unset-default) nb_ingress_unset_default || rc=$? ;;
    doctor) nb_ingress_doctor || rc=$? ;;
    help) nobrand_usage || rc=$? ;;
    *) rc=2 ;;
  esac
  [ "$lock_required" -eq 0 ] || admin_lock_release
  return "$rc"
}
