# ---------- Port Forward: nftables kernel NAT + official Realm relay ----------

forward_now() {
  date -u +%Y-%m-%dT%H:%M:%SZ
}

forward_normalize_protocol() {
  case "$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')" in
    tcp) printf 'tcp' ;;
    udp) printf 'udp' ;;
    both|tcp+udp|tcp/udp|dual|all) printf 'both' ;;
    *) return 1 ;;
  esac
}

forward_protocol_transports() {
  case "$(forward_normalize_protocol "${1:-}")" in
    tcp) printf 'TCP\n' ;;
    udp) printf 'UDP\n' ;;
    both) printf 'TCP\nUDP\n' ;;
  esac
}

forward_valid_ipv4() {
  local value="${1:-}" a b c d extra segment
  IFS=. read -r a b c d extra <<<"$value"
  [ -z "${extra:-}" ] && [ -n "${d:-}" ] || return 1
  for segment in "$a" "$b" "$c" "$d"; do
    [[ "$segment" =~ ^[0-9]{1,3}$ ]] || return 1
    [ "$((10#$segment))" -le 255 ] || return 1
  done
}

forward_target_valid() {
  local backend="${1:-}" target="${2:-}"
  case "$backend" in
    nftables) forward_valid_ipv4 "$target" ;;
    realm)
      valid_ip_literal "$target" && return 0
      # An IPv4-looking value must be a valid literal; do not reinterpret a
      # malformed address such as 999.2.3.4 as a DNS name.
      [[ "$target" =~ ^[0-9.]+$ ]] && return 1
      valid_domain_name "$target"
      ;;
    *) return 1 ;;
  esac
}

forward_listen_host_valid() {
  local backend="${1:-}" host="${2:-}"
  case "$backend" in
    nftables) forward_valid_ipv4 "$host" ;;
    realm) valid_ip_literal "$host" ;;
    *) return 1 ;;
  esac
}

forward_socket_address_normalize() {
  local value="${1:-}" host port
  [ -n "$value" ] && ! has_control_chars "$value" || return 1
  case "$value" in
    \[*\]:*)
      host="${value#\[}"
      host="${host%%\]*}"
      port="${value##*\]:}"
      [ "$value" = "[${host}]:${port}" ] || return 1
      [[ "$host" == *:* ]] && valid_ip_literal "$host" || return 1
      ;;
    *:*)
      host="${value%:*}"
      port="${value##*:}"
      [ -n "$host" ] || return 1
      valid_ip_literal "$host" || valid_domain_name "$host" || return 1
      ;;
    *) return 1 ;;
  esac
  nb_valid_port "$port" || return 1
  port="$(normalize_uint "$port")" || return 1
  if [[ "$host" == *:* ]]; then
    printf '[%s]:%s' "$host" "$port"
  else
    printf '%s:%s' "$host" "$port"
  fi
}

forward_socket_address_valid() {
  forward_socket_address_normalize "${1:-}" >/dev/null
}

forward_realm_options_valid_json() {
  local options="${1:-}" through interface listen_interface listen_transport remote_transport item
  jq -e '
    (type=="object") and
    (keys|sort)==["balance","dns_mode","dns_nameservers","dns_protocol","extra_targets",
      "interface","listen_interface","listen_transport","proxy_accept","proxy_accept_timeout",
      "proxy_send","proxy_version","remote_transport","tcp_timeout","through","udp_timeout","weights"] and
    (.through|type)=="string" and (.interface|type)=="string" and
    (.listen_interface|type)=="string" and
    (.tcp_timeout|type)=="number" and (.tcp_timeout|floor)==.tcp_timeout and
      .tcp_timeout>=0 and .tcp_timeout<=86400 and
    (.udp_timeout|type)=="number" and (.udp_timeout|floor)==.udp_timeout and
      .udp_timeout>=1 and .udp_timeout<=86400 and
    (.proxy_send|type)=="boolean" and (.proxy_accept|type)=="boolean" and
    (.proxy_version==1 or .proxy_version==2) and
    (.proxy_accept_timeout|type)=="number" and
      (.proxy_accept_timeout|floor)==.proxy_accept_timeout and
      .proxy_accept_timeout>=0 and .proxy_accept_timeout<=86400 and
    (.dns_mode=="system" or .dns_mode=="ipv4_only" or .dns_mode=="ipv6_only" or
      .dns_mode=="ipv4_then_ipv6" or .dns_mode=="ipv6_then_ipv4" or .dns_mode=="ipv4_and_ipv6") and
    (.dns_protocol=="tcp" or .dns_protocol=="udp" or .dns_protocol=="tcp_and_udp") and
    (.dns_nameservers|type)=="array" and
      all(.dns_nameservers[]; type=="string" and length>0 and length<=300 and (test("[[:space:]]")|not)) and
    (.listen_transport|type)=="string" and (.listen_transport|length)<=1024 and
    (.remote_transport|type)=="string" and (.remote_transport|length)<=1024 and
    (.extra_targets|type)=="array" and
      all(.extra_targets[]; type=="string" and length>0 and length<=300 and (test("[[:space:]]")|not)) and
    (.balance=="off" or .balance=="roundrobin" or .balance=="iphash") and
    (.weights|type)=="array" and
      all(.weights[]; type=="number" and floor==. and .>=1 and .<=255) and
    (if .balance=="off" then
       (.extra_targets|length)==0 and (.weights|length)==0
     else
       (.extra_targets|length)>0 and (.weights|length)==(1+(.extra_targets|length))
     end)
  ' <<<"$options" >/dev/null || return 1
  through="$(jq -r .through <<<"$options")"
  [ -z "$through" ] || valid_ip_literal "$through" || return 1
  interface="$(jq -r .interface <<<"$options")"
  listen_interface="$(jq -r .listen_interface <<<"$options")"
  for item in "$interface" "$listen_interface"; do
    [ -z "$item" ] || [[ "$item" =~ ^[A-Za-z0-9_.:-]{1,64}$ ]] || return 1
  done
  listen_transport="$(jq -r .listen_transport <<<"$options")"
  remote_transport="$(jq -r .remote_transport <<<"$options")"
  ! has_control_chars "$listen_transport" && ! has_control_chars "$remote_transport" || return 1
  while IFS= read -r item; do
    forward_socket_address_valid "$item" || return 1
  done < <(jq -r '.dns_nameservers[]' <<<"$options")
  while IFS= read -r item; do
    forward_socket_address_valid "$item" || return 1
  done < <(jq -r '.extra_targets[]' <<<"$options")
}

forward_port_allowed() {
  local port="${1:-}" protocol transport ignore_owner="${3:-}" profile_id="${4:-${INGRESS_PROFILE_ID:-$NOBRAND_LEGACY_INGRESS_PROFILE_ID}}"
  protocol="$(forward_normalize_protocol "${2:-}")" || return 1
  nb_valid_port "$port" || return 1
  nb_ingress_port_is_reserved "$profile_id" "$port" && return 1
  while IFS= read -r transport; do
    nb_port_available_for_profile "$port" "$transport" "$profile_id" "$ignore_owner" || return 1
  done < <(forward_protocol_transports "$protocol")
}

forward_select_available_port() {
  local protocol="$1" profile_id="$2" bounds lo hi selected
  bounds="$(nb_ingress_profile_auto_range "$profile_id" 2>/dev/null)" || return 1
  lo="${bounds%%|*}"; hi="${bounds#*|}"
  selected="$(nb_scan_port_span "$lo" "$hi" forward_port_allowed "$protocol" '' "$profile_id")" || return 1
  printf '%s' "$selected"
}

forward_init_state() {
  local tmp
  [ -e "$NOBRAND_FORWARD_STATE_FILE" ] && return 0
  mkdir -p "$NOBRAND_FORWARD_STATE_DIR" "$NOBRAND_FORWARD_CONFIG_DIR" || return 1
  chmod 0700 "$NOBRAND_FORWARD_STATE_DIR" "$NOBRAND_FORWARD_CONFIG_DIR" || return 1
  tmp="$(mktemp_file .forward-state)" || return 1
  jq -n --argjson schema "$NOBRAND_SCHEMA_VERSION" \
    '{schema_version:$schema,ownership:"nobrand-v3",feature:"port-forward",rules:[]}' >"$tmp" \
    && nb_atomic_install_file "$tmp" "$NOBRAND_FORWARD_STATE_FILE" 0600
  local rc=$?
  rm -f "$tmp"
  return "$rc"
}

forward_state_valid() {
  local state="${1:-$NOBRAND_FORWARD_STATE_FILE}" rule_id backend protocol listen_host options
  local listen_port target_host target_port display_mode display_host display_port transport key
  local forward_seen_ports=""
  [ -s "$state" ] && jq -e '
    (keys|sort)==["feature","ownership","rules","schema_version"] and
    .schema_version==3 and .ownership=="nobrand-v3" and .feature=="port-forward" and
    (.rules|type)=="array" and
    all(.rules[];
      ((keys-["ingress_profile_id","ingress_enforcement","ingress_enforcement_method","ingress_local_address"]|sort)==["backend","backend_options","created_at","display_host","display_mode",
                    "display_port","enabled","listen_host","listen_port","name","note",
                    "ownership_metadata","protocol","rule_id","target_host","target_port","updated_at"]) and
      ((has("ingress_profile_id")|not) or (.ingress_profile_id|type=="string" and length>0)) and
      ((has("ingress_enforcement")|not) or
        (.ingress_enforcement=="permissive" or .ingress_enforcement=="strict")) and
      ((has("ingress_enforcement_method")|not) or
        (.ingress_enforcement_method=="wildcard" or .ingress_enforcement_method=="native-bind" or
         .ingress_enforcement_method=="address-match")) and
      ((has("ingress_local_address")|not) or (.ingress_local_address|type=="string")) and
      (if (.ingress_enforcement // "permissive")=="strict" then
         (.ingress_local_address|type=="string" and length>0) and .listen_host==.ingress_local_address and
         (if .backend=="nftables" then .ingress_enforcement_method=="address-match"
          else .ingress_enforcement_method=="native-bind" end)
       else (.ingress_enforcement_method // "wildcard")=="wildcard" end) and
      (.rule_id|type)=="string" and (.rule_id|test("^f[0-9a-f]{16}$")) and
      (.name|type)=="string" and (.name|length)>0 and (.name|length)<=64 and
        (.name|test("[[:cntrl:]]")|not) and
      (.note|type)=="string" and (.note|length)<=256 and
        (.note|test("[[:cntrl:]]")|not) and
      (.backend=="nftables" or .backend=="realm") and (.enabled|type)=="boolean" and
      (.protocol=="tcp" or .protocol=="udp" or .protocol=="both") and
      (.listen_host|type)=="string" and (.listen_port|type)=="number" and
      (.target_host|type)=="string" and (.target_port|type)=="number" and
      (.display_host|type)=="string" and (.display_port|type)=="number" and
      (.display_mode=="auto" or .display_mode=="custom") and
      (.created_at|type)=="string" and (.created_at|test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")) and
      (.updated_at|type)=="string" and (.updated_at|test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")) and
      (.ownership_metadata|type)=="object" and
      (.ownership_metadata|keys|sort)==["managed_firewall","managed_listener"] and
      (.ownership_metadata.managed_listener|type)=="boolean" and
      (.ownership_metadata.managed_firewall|type)=="boolean" and
      (.backend_options|type)=="object" and
      (if .backend=="nftables" then
         (.backend_options|keys)==["source_mode"] and
         (.backend_options.source_mode=="masquerade" or .backend_options.source_mode=="preserve")
       else
         (.backend_options|keys|sort)==["balance","dns_mode","dns_nameservers","dns_protocol",
           "extra_targets","interface","listen_interface","listen_transport","proxy_accept",
           "proxy_accept_timeout","proxy_send","proxy_version","remote_transport","tcp_timeout",
           "through","udp_timeout","weights"] and
         (.backend_options.through|type)=="string" and
         (.backend_options.interface|type)=="string" and
         (.backend_options.listen_interface|type)=="string" and
         (.backend_options.tcp_timeout|type)=="number" and
         (.backend_options.udp_timeout|type)=="number" and
         (.backend_options.proxy_send|type)=="boolean" and
         (.backend_options.proxy_accept|type)=="boolean" and
         (.backend_options.proxy_version==1 or .backend_options.proxy_version==2) and
         (.backend_options.proxy_accept_timeout|type)=="number" and
         (.backend_options.dns_mode|type)=="string" and
         (.backend_options.dns_protocol|type)=="string" and
         (.backend_options.dns_nameservers|type)=="array" and
         (.backend_options.listen_transport|type)=="string" and
         (.backend_options.remote_transport|type)=="string" and
         (.backend_options.extra_targets|type)=="array" and
         (.backend_options.balance|type)=="string" and
         (.backend_options.weights|type)=="array"
       end)
    ) and
    ([.rules[].rule_id]|length)==([.rules[].rule_id]|unique|length) and
    ([.rules[].name]|length)==([.rules[].name]|unique|length) and
    ([.rules[] | . as $r |
       (if .protocol=="both" then ["TCP","UDP"] elif .protocol=="tcp" then ["TCP"] else ["UDP"] end)[] |
       "\(.)|\($r.listen_port)"] | length)==
    ([.rules[] | . as $r |
       (if .protocol=="both" then ["TCP","UDP"] elif .protocol=="tcp" then ["TCP"] else ["UDP"] end)[] |
       "\(.)|\($r.listen_port)"] | unique | length)
  ' "$state" >/dev/null || return 1

  while IFS=$'\x1f' read -r rule_id backend protocol listen_host listen_port target_host target_port \
    display_mode display_host display_port; do
    forward_listen_host_valid "$backend" "$listen_host" || return 1
    nb_valid_port "$listen_port" && nb_valid_port "$target_port" \
      && valid_advertise_port "$display_port" || return 1
    nb_port_is_tail_base_reserved "$listen_port" && return 1
    forward_target_valid "$backend" "$target_host" || return 1
    if [ "$backend" = realm ]; then
      options="$(jq -c --arg id "$rule_id" '.rules[]|select(.rule_id==$id)|.backend_options' "$state")" \
        || return 1
      forward_realm_options_valid_json "$options" || return 1
    fi
    if [ "$display_mode" = custom ]; then
      valid_advertise_host "$display_host" || return 1
    else
      [ -z "$display_host" ] || return 1
      [ "$display_port" -eq "$listen_port" ] || return 1
    fi
    while IFS= read -r transport; do
      key="${transport}|${listen_port}"
      [ -z "${forward_seen_ports:-}" ] || case "|$forward_seen_ports|" in *"|$key|"*) return 1 ;; esac
      forward_seen_ports="${forward_seen_ports:+${forward_seen_ports}|}${key}"
    done < <(forward_protocol_transports "$protocol")
  done < <(jq -r '.rules[] | [.rule_id,.backend,.protocol,.listen_host,(.listen_port|tostring),
    .target_host,(.target_port|tostring),.display_mode,.display_host,(.display_port|tostring)] | join("\u001f")' "$state")

  # Realm's DNS block is global. Multiple enabled Realm rules may share it,
  # but conflicting values are rejected instead of silently overriding peers.
  [ "$(jq -c '[.rules[] | select(.enabled and .backend=="realm") |
      [.backend_options.dns_mode,.backend_options.dns_protocol,.backend_options.dns_nameservers]] | unique | length' "$state")" -le 1 ] \
    || return 1
}

forward_rule_json() {
  local state="${1:-$NOBRAND_FORWARD_STATE_FILE}" id="$2"
  jq -c --arg id "$id" '.rules[] | select(.rule_id==$id or .name==$id)' "$state" | head -n1
}

forward_resolve_rule_id() {
  local value="${1:-}" state="${2:-$NOBRAND_FORWARD_STATE_FILE}" id
  id="$(jq -r --arg value "$value" '.rules[] | select(.rule_id==$value or .name==$value) | .rule_id' \
    "$state" 2>/dev/null | head -n1)"
  [ -n "$id" ] && [ "$id" != null ] || return 1
  printf '%s' "$id"
}

forward_generate_rule_id() {
  local material digest
  material="$(forward_now)|$$|${RANDOM}|${FORWARD_NAME:-forward}"
  if command -v sha256sum >/dev/null 2>&1; then
    digest="$(printf '%s' "$material" | sha256sum | awk '{print $1}')"
  else
    digest="$(printf '%s' "$material" | openssl dgst -sha256 | awk '{print $NF}')"
  fi
  printf 'f%s' "${digest:0:16}"
}

forward_toml_string() {
  jq -Rn --arg value "${1:-}" '$value'
}

forward_realm_address() {
  local host="$1" port="$2"
  case "$host" in
    *:*) printf '[%s]:%s' "$host" "$port" ;;
    *) printf '%s:%s' "$host" "$port" ;;
  esac
}

forward_generate_realm_config() {
  local state="$1" output="$2" tmp dns_json mode dns_protocol nameservers
  local rule_id protocol listen_host listen_port target_host target_port options
  local no_tcp use_udp through interface listen_interface listen_transport remote_transport
  local tcp_timeout udp_timeout proxy_send proxy_accept proxy_version proxy_accept_timeout
  local extra_targets balance weights endpoint target count
  forward_state_valid "$state" || return 1
  tmp="$(mktemp_file .realm.toml)" || return 1
  {
    printf '# Generated by NoBrand-OneClick; display endpoint metadata is intentionally excluded.\n'
    printf '[log]\nlevel = "warn"\noutput = "stdout"\n\n'
    dns_json="$(jq -c '[.rules[] | select(.enabled and .backend=="realm")][0].backend_options // empty' "$state")"
    if [ -n "$dns_json" ]; then
      mode="$(jq -r '.dns_mode' <<<"$dns_json")"
      dns_protocol="$(jq -r '.dns_protocol' <<<"$dns_json")"
      nameservers="$(jq -c '.dns_nameservers' <<<"$dns_json")"
      if [ "$mode" != system ] || [ "$nameservers" != '[]' ]; then
        printf '[dns]\n'
        [ "$mode" = system ] || printf 'mode = %s\n' "$(forward_toml_string "$mode")"
        printf 'protocol = %s\n' "$(forward_toml_string "$dns_protocol")"
        [ "$nameservers" = '[]' ] || printf 'nameservers = %s\n' "$nameservers"
        printf '\n'
      fi
    fi
    while IFS=$'\t' read -r rule_id protocol listen_host listen_port target_host target_port options; do
      [ -n "$rule_id" ] || continue
      case "$protocol" in
        tcp) no_tcp=false; use_udp=false ;;
        udp) no_tcp=true; use_udp=true ;;
        both) no_tcp=false; use_udp=true ;;
      esac
      endpoint="$(forward_realm_address "$listen_host" "$listen_port")"
      target="$(forward_realm_address "$target_host" "$target_port")"
      through="$(jq -r '.through' <<<"$options")"
      interface="$(jq -r '.interface' <<<"$options")"
      listen_interface="$(jq -r '.listen_interface' <<<"$options")"
      listen_transport="$(jq -r '.listen_transport' <<<"$options")"
      remote_transport="$(jq -r '.remote_transport' <<<"$options")"
      tcp_timeout="$(jq -r '.tcp_timeout' <<<"$options")"
      udp_timeout="$(jq -r '.udp_timeout' <<<"$options")"
      proxy_send="$(jq -r '.proxy_send' <<<"$options")"
      proxy_accept="$(jq -r '.proxy_accept' <<<"$options")"
      proxy_version="$(jq -r '.proxy_version' <<<"$options")"
      proxy_accept_timeout="$(jq -r '.proxy_accept_timeout' <<<"$options")"
      extra_targets="$(jq -c '.extra_targets' <<<"$options")"
      balance="$(jq -r '.balance' <<<"$options")"
      weights="$(jq -c '.weights' <<<"$options")"
      printf '[[endpoints]]\nlisten = %s\nremote = %s\n' \
        "$(forward_toml_string "$endpoint")" "$(forward_toml_string "$target")"
      if [ "$extra_targets" != '[]' ]; then
        printf 'extra_remotes = %s\n' "$extra_targets"
      fi
      if [ "$balance" != off ]; then
        count="$(jq 'length' <<<"$weights")"
        [ "$count" -gt 0 ] || { rm -f "$tmp"; return 1; }
        printf 'balance = %s\n' "$(forward_toml_string "${balance}: $(jq -r 'map(tostring)|join(", ")' <<<"$weights")")"
      fi
      [ -z "$through" ] || printf 'through = %s\n' "$(forward_toml_string "$through")"
      [ -z "$interface" ] || printf 'interface = %s\n' "$(forward_toml_string "$interface")"
      [ -z "$listen_interface" ] || printf 'listen_interface = %s\n' "$(forward_toml_string "$listen_interface")"
      [ -z "$listen_transport" ] || printf 'listen_transport = %s\n' "$(forward_toml_string "$listen_transport")"
      [ -z "$remote_transport" ] || printf 'remote_transport = %s\n' "$(forward_toml_string "$remote_transport")"
      printf '[endpoints.network]\nno_tcp = %s\nuse_udp = %s\n' "$no_tcp" "$use_udp"
      printf 'tcp_timeout = %s\nudp_timeout = %s\n' "$tcp_timeout" "$udp_timeout"
      printf 'send_proxy = %s\nsend_proxy_version = %s\n' "$proxy_send" "$proxy_version"
      printf 'accept_proxy = %s\naccept_proxy_timeout = %s\n\n' "$proxy_accept" "$proxy_accept_timeout"
    done < <(jq -r '.rules | sort_by(.rule_id)[] | select(.enabled and .backend=="realm") |
      [.rule_id,.protocol,.listen_host,(.listen_port|tostring),.target_host,(.target_port|tostring),
       (.backend_options|tojson)] | @tsv' "$state")
  } >"$tmp" || { rm -f "$tmp"; return 1; }
  mkdir -p "$(dirname "$output")" || { rm -f "$tmp"; return 1; }
  install -m 0600 "$tmp" "$output"
  local rc=$?
  rm -f "$tmp"
  return "$rc"
}

forward_generate_nft_ruleset() {
  local state="$1" output="$2" tmp rule_id protocol listen_host listen_port
  local target_host target_port source_mode transport proto match_host original_match_host
  forward_state_valid "$state" || return 1
  tmp="$(mktemp_file .nft)" || return 1
  {
    printf 'table ip %s {\n' "$NOBRAND_FORWARD_NFT_TABLE"
    printf '  comment "Owned by NoBrand-OneClick Port Forward"\n'
    printf '  chain prerouting {\n    type nat hook prerouting priority dstnat; policy accept;\n'
    while IFS=$'\t' read -r rule_id protocol listen_host listen_port target_host target_port source_mode; do
      [ -n "$rule_id" ] || continue
      match_host=""
      [ "$listen_host" = 0.0.0.0 ] || match_host="ip daddr ${listen_host} "
      while IFS= read -r transport; do
        proto="$(printf '%s' "$transport" | tr '[:upper:]' '[:lower:]')"
        printf '    %s%s dport %s counter dnat to %s:%s comment "nobrand:%s:dnat:%s"\n' \
          "$match_host" "$proto" "$listen_port" "$target_host" "$target_port" "$rule_id" "$proto"
      done < <(forward_protocol_transports "$protocol")
    done < <(jq -r '.rules | sort_by(.rule_id)[] | select(.enabled and .backend=="nftables") |
      [.rule_id,.protocol,.listen_host,(.listen_port|tostring),.target_host,(.target_port|tostring),
       .backend_options.source_mode] | @tsv' "$state")
    printf '  }\n'
    printf '  chain postrouting {\n    type nat hook postrouting priority srcnat; policy accept;\n'
    while IFS=$'\t' read -r rule_id protocol listen_host listen_port target_host target_port source_mode; do
      [ "$source_mode" = masquerade ] || continue
      original_match_host=""
      [ "$listen_host" = 0.0.0.0 ] || original_match_host="ct original ip daddr ${listen_host} "
      while IFS= read -r transport; do
        proto="$(printf '%s' "$transport" | tr '[:upper:]' '[:lower:]')"
        printf '    meta l4proto %s %sct original proto-dst %s ip daddr %s %s dport %s counter masquerade comment "nobrand:%s:snat:%s"\n' \
          "$proto" "$original_match_host" "$listen_port" "$target_host" "$proto" "$target_port" "$rule_id" "$proto"
      done < <(forward_protocol_transports "$protocol")
    done < <(jq -r '.rules | sort_by(.rule_id)[] | select(.enabled and .backend=="nftables") |
      [.rule_id,.protocol,.listen_host,(.listen_port|tostring),.target_host,(.target_port|tostring),
       .backend_options.source_mode] | @tsv' "$state")
    printf '  }\n'
    printf '  chain forward {\n    type filter hook forward priority -10; policy accept;\n'
    while IFS=$'\t' read -r rule_id protocol listen_host listen_port target_host target_port source_mode; do
      original_match_host=""
      [ "$listen_host" = 0.0.0.0 ] || original_match_host="ct original ip daddr ${listen_host} "
      while IFS= read -r transport; do
        proto="$(printf '%s' "$transport" | tr '[:upper:]' '[:lower:]')"
        printf '    meta l4proto %s %sct original proto-dst %s ip daddr %s %s dport %s ct status dnat counter accept comment "nobrand:%s:forward:%s"\n' \
          "$proto" "$original_match_host" "$listen_port" "$target_host" "$proto" "$target_port" "$rule_id" "$proto"
      done < <(forward_protocol_transports "$protocol")
    done < <(jq -r '.rules | sort_by(.rule_id)[] | select(.enabled and .backend=="nftables") |
      [.rule_id,.protocol,.listen_host,(.listen_port|tostring),.target_host,(.target_port|tostring),
       .backend_options.source_mode] | @tsv' "$state")
    printf '  }\n}\n'
  } >"$tmp" || { rm -f "$tmp"; return 1; }
  mkdir -p "$(dirname "$output")" || { rm -f "$tmp"; return 1; }
  install -m 0600 "$tmp" "$output"
  local rc=$?
  rm -f "$tmp"
  return "$rc"
}

forward_set_endpoint_state() {
  local selector="$1" mode="$2" host="${3:-}" port="${4:-}" id tmp
  id="$(forward_resolve_rule_id "$selector")" || return 1
  case "$mode" in
    auto)
      host=""
      port="$(jq -r --arg id "$id" '.rules[]|select(.rule_id==$id)|.listen_port' "$NOBRAND_FORWARD_STATE_FILE")"
      ;;
    custom)
      valid_advertise_host "$host" && valid_advertise_port "$port" || return 1
      ;;
    *) return 1 ;;
  esac
  tmp="$(mktemp_file .forward-endpoint)" || return 1
  jq --arg id "$id" --arg mode "$mode" --arg host "$host" --argjson port "$(normalize_uint "$port")" \
    --arg now "$(forward_now)" '
      (.rules[]|select(.rule_id==$id)) |=
        (.display_mode=$mode|.display_host=$host|.display_port=$port|.updated_at=$now)
    ' "$NOBRAND_FORWARD_STATE_FILE" >"$tmp" \
    && forward_state_valid "$tmp" \
    && nb_atomic_install_file "$tmp" "$NOBRAND_FORWARD_STATE_FILE" 0600
  local rc=$?
  rm -f "$tmp"
  return "$rc"
}

forward_export_json() {
  local output="${1:-}" tmp
  tmp="$(mktemp_file .forward-export)" || return 1
  jq --arg exported_at "$(forward_now)" '
    {format:"nobrand-forward-export",format_version:1,schema_version:3,
     ownership:"nobrand-v3",exported_at:$exported_at,rules:.rules}
  ' "$NOBRAND_FORWARD_STATE_FILE" >"$tmp" || { rm -f "$tmp"; return 1; }
  if [ -n "$output" ] && [ "$output" != - ]; then
    mkdir -p "$(dirname "$output")" 2>/dev/null || true
    install -m 0600 "$tmp" "$output"
  else
    cat "$tmp"
  fi
  local rc=$?
  rm -f "$tmp"
  return "$rc"
}

forward_import_validate() {
  local input="$1" candidate
  [ -s "$input" ] || return 1
  jq -e '
    (keys|sort)==["exported_at","format","format_version","ownership","rules","schema_version"] and
    .format=="nobrand-forward-export" and .format_version==1 and
    .schema_version==3 and .ownership=="nobrand-v3" and
    (.exported_at|type)=="string" and (.rules|type)=="array"
  ' "$input" >/dev/null || return 1
  candidate="$(mktemp_file .forward-import-state)" || return 1
  jq '{schema_version:.schema_version,ownership:.ownership,feature:"port-forward",rules:.rules}' \
    "$input" >"$candidate" && forward_state_valid "$candidate"
  local rc=$?
  rm -f "$candidate"
  return "$rc"
}

forward_sysctl_snapshot() {
  local snapshot="$1"
  mkdir -p "$snapshot" || return 1
  [ ! -e "$NOBRAND_FORWARD_SYSCTL_STATE" ] \
    || cp -a "$NOBRAND_FORWARD_SYSCTL_STATE" "$snapshot/state.json" || return 1
  [ ! -e "$NOBRAND_FORWARD_SYSCTL_FRAGMENT" ] \
    || cp -a "$NOBRAND_FORWARD_SYSCTL_FRAGMENT" "$snapshot/fragment" || return 1
  if command -v sysctl >/dev/null 2>&1; then
    sysctl -n net.ipv4.ip_forward 2>/dev/null >"$snapshot/live-value" || true
  fi
}

forward_sysctl_state_valid() {
  local state="${1:-$NOBRAND_FORWARD_SYSCTL_STATE}"
  [ -s "$state" ] && jq -e '
    (keys|sort)==["active_rules","changed_by_nobrand","fragment_owned","key","original_value","ownership","schema_version"] and
    .schema_version==3 and .ownership=="nobrand-v3" and .key=="net.ipv4.ip_forward" and
    (.original_value==0 or .original_value==1) and
    (.changed_by_nobrand|type)=="boolean" and
    (.active_rules|type)=="number" and (.active_rules|floor)==.active_rules and .active_rules>=0 and
    .fragment_owned==true
  ' "$state" >/dev/null
}

forward_sysctl_fragment_owned() {
  local fragment="${1:-$NOBRAND_FORWARD_SYSCTL_FRAGMENT}"
  [ -f "$fragment" ] && [ ! -L "$fragment" ] \
    && [ "$(wc -l <"$fragment" | tr -d '[:space:]')" = 2 ] \
    && [ "$(sed -n '1p' "$fragment")" = '# Owned by NoBrand-OneClick Port Forward' ] \
    && [ "$(sed -n '2p' "$fragment")" = 'net.ipv4.ip_forward = 1' ]
}

forward_sysctl_restore_snapshot() {
  local snapshot="$1" value
  if [ -e "$snapshot/state.json" ]; then
    nb_atomic_install_file "$snapshot/state.json" "$NOBRAND_FORWARD_SYSCTL_STATE" 0600 || return 1
  else
    rm -f "$NOBRAND_FORWARD_SYSCTL_STATE"
  fi
  if [ -e "$snapshot/fragment" ]; then
    nb_atomic_install_file "$snapshot/fragment" "$NOBRAND_FORWARD_SYSCTL_FRAGMENT" 0644 || return 1
  else
    rm -f "$NOBRAND_FORWARD_SYSCTL_FRAGMENT"
  fi
  value="$(tr -d '[:space:]' <"$snapshot/live-value" 2>/dev/null || true)"
  case "$value" in 0|1) sysctl -q -w "net.ipv4.ip_forward=${value}" >/dev/null || return 1 ;; esac
}

forward_sysctl_reconcile() {
  local state="$1" count current original changed fragment_owned tmp
  count="$(jq '[.rules[]|select(.enabled and .backend=="nftables")]|length' "$state")" || return 1
  command -v sysctl >/dev/null 2>&1 || { [ "$count" -eq 0 ]; return; }
  current="$(sysctl -n net.ipv4.ip_forward 2>/dev/null | tr -d '[:space:]')"
  case "$current" in 0|1) ;; *) return 1 ;; esac
  if [ "$count" -gt 0 ]; then
    if [ -s "$NOBRAND_FORWARD_SYSCTL_STATE" ]; then
      forward_sysctl_state_valid "$NOBRAND_FORWARD_SYSCTL_STATE" || return 1
      # Unified backup contains NoBrand state/config, while this runtime
      # fragment lives under /etc/sysctl.d and is recreated during restore.
      # A valid ownership state may therefore legitimately outlive a missing
      # fragment.  Recreate only when the path is truly absent; any existing
      # file or symlink must still match the exact NoBrand marker/content.
      if [ -e "$NOBRAND_FORWARD_SYSCTL_FRAGMENT" ] \
         || [ -L "$NOBRAND_FORWARD_SYSCTL_FRAGMENT" ]; then
        forward_sysctl_fragment_owned "$NOBRAND_FORWARD_SYSCTL_FRAGMENT" || return 1
      fi
      original="$(jq -r '.original_value' "$NOBRAND_FORWARD_SYSCTL_STATE")"
      changed="$(jq -r '.changed_by_nobrand' "$NOBRAND_FORWARD_SYSCTL_STATE")"
    else
      [ ! -e "$NOBRAND_FORWARD_SYSCTL_FRAGMENT" ] || return 1
      original="$current"
      changed=false
    fi
    if [ "$current" -ne 1 ]; then
      sysctl -q -w net.ipv4.ip_forward=1 >/dev/null || return 1
      changed=true
    fi
    tmp="$(mktemp_file .forward-sysctl)" || return 1
    printf '# Owned by NoBrand-OneClick Port Forward\nnet.ipv4.ip_forward = 1\n' >"$tmp"
    nb_atomic_install_file "$tmp" "$NOBRAND_FORWARD_SYSCTL_FRAGMENT" 0644 || { rm -f "$tmp"; return 1; }
    rm -f "$tmp"
    tmp="$(mktemp_file .forward-sysctl-state)" || return 1
    jq -n --argjson original "$original" --argjson changed "$changed" --argjson users "$count" \
      '{schema_version:3,ownership:"nobrand-v3",key:"net.ipv4.ip_forward",
        original_value:$original,changed_by_nobrand:$changed,active_rules:$users,fragment_owned:true}' >"$tmp" \
      && nb_atomic_install_file "$tmp" "$NOBRAND_FORWARD_SYSCTL_STATE" 0600
    local rc=$?
    rm -f "$tmp"
    return "$rc"
  fi

  [ -s "$NOBRAND_FORWARD_SYSCTL_STATE" ] || return 0
  forward_sysctl_state_valid "$NOBRAND_FORWARD_SYSCTL_STATE" || return 1
  forward_sysctl_fragment_owned "$NOBRAND_FORWARD_SYSCTL_FRAGMENT" || return 1
  original="$(jq -r '.original_value' "$NOBRAND_FORWARD_SYSCTL_STATE")"
  changed="$(jq -r '.changed_by_nobrand' "$NOBRAND_FORWARD_SYSCTL_STATE")"
  fragment_owned="$(jq -r '.fragment_owned' "$NOBRAND_FORWARD_SYSCTL_STATE")"
  if [ "$changed" = true ] && [ "$current" = 1 ] && [ "$original" = 0 ]; then
    sysctl -q -w net.ipv4.ip_forward=0 >/dev/null || return 1
  fi
  [ "$fragment_owned" != true ] || rm -f "$NOBRAND_FORWARD_SYSCTL_FRAGMENT"
  rm -f "$NOBRAND_FORWARD_SYSCTL_STATE"
}

forward_ensure_nftables_dependency() {
  local pm
  command -v nft >/dev/null 2>&1 && command -v sysctl >/dev/null 2>&1 && return 0
  require_root
  pm="$(detect_pkg_manager)" || return 1
  case "$pm" in
    deb)
      run apt-get update || return 1
      run apt-get install -y nftables procps || return 1
      ;;
    rpm)
      if command -v dnf >/dev/null 2>&1; then
        run dnf install -y nftables procps-ng || return 1
      else
        run yum install -y nftables procps-ng || return 1
      fi
      ;;
    alpine) run apk add --no-cache nftables procps-ng || return 1 ;;
    *) return 1 ;;
  esac
  command -v nft >/dev/null 2>&1 && command -v sysctl >/dev/null 2>&1
}

forward_nft_table_owned() {
  local listing
  command -v nft >/dev/null 2>&1 || return 1
  listing="$(nft list table "$NOBRAND_FORWARD_NFT_FAMILY" "$NOBRAND_FORWARD_NFT_TABLE" 2>/dev/null)" \
    || return 1
  grep -Fq 'comment "Owned by NoBrand-OneClick Port Forward"' <<<"$listing"
}

forward_nft_rule_owned() {
  local id="$1" listing
  command -v nft >/dev/null 2>&1 || return 1
  listing="$(nft list table "$NOBRAND_FORWARD_NFT_FAMILY" "$NOBRAND_FORWARD_NFT_TABLE" 2>/dev/null)" \
    || return 1
  # Do not pipe nft directly into grep -q under pipefail. An early match can
  # close the pipe while nft is still writing and turn a healthy rule into a
  # position-dependent SIGPIPE failure.
  grep -F "nobrand:${id}:dnat:" <<<"$listing" >/dev/null
}

forward_nft_rule_ingress_owned() {
  local id="$1" rule listing enforcement address
  rule="$(forward_rule_json "$NOBRAND_FORWARD_STATE_FILE" "$id")" || return 1
  [ -n "$rule" ] || return 1
  forward_nft_rule_owned "$id" || return 1
  enforcement="$(jq -r '.ingress_enforcement // "permissive"' <<<"$rule")"
  [ "$enforcement" = strict ] || return 0
  address="$(jq -r '.ingress_local_address // empty' <<<"$rule")"
  [ -n "$address" ] || return 1
  listing="$(nft list table "$NOBRAND_FORWARD_NFT_FAMILY" "$NOBRAND_FORWARD_NFT_TABLE" 2>/dev/null)" \
    || return 1
  grep -Fq "ip daddr ${address}" <<<"$listing"
}

forward_apply_nft_state() {
  local state="$1" candidate batch count
  count="$(jq '[.rules[]|select(.enabled and .backend=="nftables")]|length' "$state")" || return 1
  if [ "$count" -eq 0 ]; then
    if command -v nft >/dev/null 2>&1; then
      forward_remove_owned_nft_table || return 1
    fi
    rm -f "$NOBRAND_FORWARD_NFT_RULESET"
    forward_sysctl_reconcile "$state"
    return $?
  fi
  forward_ensure_nftables_dependency || return 1
  candidate="$(mktemp_file .forward.nft)" || return 1
  batch="$(mktemp_file .forward-batch.nft)" || { rm -f "$candidate"; return 1; }
  forward_generate_nft_ruleset "$state" "$candidate" || { rm -f "$candidate" "$batch"; return 1; }
  {
    if nft list table "$NOBRAND_FORWARD_NFT_FAMILY" "$NOBRAND_FORWARD_NFT_TABLE" >/dev/null 2>&1; then
      forward_nft_table_owned || { rm -f "$candidate" "$batch"; return 1; }
      printf 'delete table %s %s\n' "$NOBRAND_FORWARD_NFT_FAMILY" "$NOBRAND_FORWARD_NFT_TABLE"
    fi
    cat "$candidate"
  } >"$batch"
  nft -c -f "$batch" >/dev/null 2>&1 && nft -f "$batch" \
    && nb_atomic_install_file "$candidate" "$NOBRAND_FORWARD_NFT_RULESET" 0600 \
    && forward_sysctl_reconcile "$state"
  local rc=$?
  rm -f "$candidate" "$batch"
  return "$rc"
}

forward_remove_owned_nft_table() {
  command -v nft >/dev/null 2>&1 || return 0
  nft list table "$NOBRAND_FORWARD_NFT_FAMILY" "$NOBRAND_FORWARD_NFT_TABLE" >/dev/null 2>&1 \
    || return 0
  forward_nft_table_owned || return 1
  nft delete table "$NOBRAND_FORWARD_NFT_FAMILY" "$NOBRAND_FORWARD_NFT_TABLE"
}

forward_firewall_pairs() {
  local state="$1"
  jq -r '.rules[]|select(.enabled and .backend=="realm")|. as $r|
    (if .protocol=="both" then ["TCP","UDP"] elif .protocol=="tcp" then ["TCP"] else ["UDP"] end)[]|
    "\(.)|\($r.listen_port)"' "$state" | LC_ALL=C sort -u
}

forward_firewall_reconcile() {
  local old_state="$1" new_state="$2" old_pairs new_pairs pair close_pairs="" open_pairs=""
  old_pairs="$(forward_firewall_pairs "$old_state")" || return 1
  new_pairs="$(forward_firewall_pairs "$new_state")" || return 1
  while IFS= read -r pair; do
    [ -n "$pair" ] || continue
    grep -qxF "$pair" <<<"$old_pairs" \
      || printf -v open_pairs '%s%s\n' "$open_pairs" "$pair"
  done <<<"$new_pairs"
  while IFS= read -r pair; do
    [ -n "$pair" ] || continue
    grep -qxF "$pair" <<<"$new_pairs" \
      || printf -v close_pairs '%s%s\n' "$close_pairs" "$pair"
  done <<<"$old_pairs"
  [ -z "$open_pairs" ] || nb_firewall_open_pairs "$open_pairs" || return 1
  [ -z "$close_pairs" ] || nb_firewall_close_pairs "$close_pairs" || return 1
}

forward_realm_asset_name() {
  case "$(uname -m)" in
    x86_64|amd64) printf 'realm-x86_64-unknown-linux-musl.tar.gz' ;;
    aarch64|arm64) printf 'realm-aarch64-unknown-linux-musl.tar.gz' ;;
    *) return 1 ;;
  esac
}

forward_realm_tested_digest() {
  case "$1" in
    realm-x86_64-unknown-linux-musl.tar.gz) printf '%s' "$TESTED_REALM_AMD64_MUSL_SHA256" ;;
    realm-aarch64-unknown-linux-musl.tar.gz) printf '%s' "$TESTED_REALM_ARM64_MUSL_SHA256" ;;
    *) return 1 ;;
  esac
}

forward_realm_version() {
  local binary="${1:-$NOBRAND_REALM_BIN}"
  [ -x "$binary" ] || return 1
  "$binary" --version 2>/dev/null | sed -nE 's/.*[Rr]ealm[[:space:]]+([0-9]+\.[0-9]+\.[0-9]+).*/\1/p' | head -n1
}

forward_realm_runtime_metadata_valid() {
  local meta="$NOBRAND_REALM_RUNTIME_META"
  [ -s "$meta" ] && jq -e '
    (keys|sort)==["asset","channel","consumer","installed_at","ownership","schema_version","sha256","source_url","version"] and
    .schema_version==3 and .ownership=="nobrand-v3" and .consumer=="port-forward" and
    (.version|type)=="string" and (.version|test("^[0-9]+\\.[0-9]+\\.[0-9]+$")) and
    (.channel=="stable" or .channel=="latest" or .channel=="pinned") and
    (.asset|type)=="string" and (.asset|test("^realm-(x86_64|aarch64)-unknown-linux-musl\\.tar\\.gz$")) and
    (.source_url|type)=="string" and (.source_url|startswith("https://github.com/zhboner/realm/releases/download/")) and
    (.sha256|type)=="string" and (.sha256|test("^[0-9a-f]{64}$")) and
    (.installed_at|type)=="string"
  ' "$meta" >/dev/null
}

forward_ensure_realm_dependencies() {
  local command_name
  for command_name in curl jq tar sha256sum find; do
    command -v "$command_name" >/dev/null 2>&1 || return 1
  done
}

forward_realm_install_runtime() {
  local channel="${1:-stable}" version="${2:-}" api response tag asset url digest expected
  local archive extract binary actual actual_version meta
  case "$channel" in
    stable) version="$TESTED_REALM_VERSION" ;;
    latest) ;;
    pinned) [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1 ;;
    *) return 1 ;;
  esac
  forward_ensure_realm_dependencies || return 1
  if [ -e "$NOBRAND_REALM_BIN" ] && ! forward_realm_runtime_metadata_valid; then
    warn "Refusing to replace unowned Realm runtime: $NOBRAND_REALM_BIN"
    return 1
  fi
  if [ -e "$NOBRAND_REALM_RUNTIME_META" ] && ! forward_realm_runtime_metadata_valid; then
    warn "Refusing to replace invalid Realm ownership metadata: $NOBRAND_REALM_RUNTIME_META"
    return 1
  fi
  [ "$channel" != latest ] && api="${NOBRAND_REALM_RELEASE_API}/tags/v${version}" \
    || api="${NOBRAND_REALM_RELEASE_API}/latest"
  response="$(curl -fsSL --connect-timeout 10 --max-time 60 \
    -H 'Accept: application/vnd.github+json' -H 'User-Agent: NoBrand-OneClick' "$api")" || return 1
  jq -e '.draft==false and .prerelease==false' <<<"$response" >/dev/null || return 1
  tag="$(jq -r .tag_name <<<"$response")"
  [[ "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
  version="${tag#v}"
  asset="$(forward_realm_asset_name)" || return 1
  url="$(jq -r --arg asset "$asset" '.assets[]|select(.name==$asset)|.browser_download_url' <<<"$response" | head -n1)"
  digest="$(jq -r --arg asset "$asset" '.assets[]|select(.name==$asset)|.digest // empty' <<<"$response" | head -n1)"
  digest="${digest#sha256:}"
  [[ "$digest" =~ ^[0-9a-f]{64}$ ]] && [ -n "$url" ] || return 1
  if [ "$channel" = stable ]; then
    expected="$(forward_realm_tested_digest "$asset")" || return 1
    [ "$digest" = "$expected" ] || return 1
  fi
  archive="$(mktemp_file .realm.tar.gz)" || return 1
  extract="$(mktemp_dir)" || { rm -f "$archive"; return 1; }
  curl -fL --connect-timeout 10 --max-time 300 -H 'User-Agent: NoBrand-OneClick' "$url" -o "$archive" \
    || { rm -f "$archive"; rm -rf -- "$extract"; return 1; }
  actual="$(nobrand_sha256_file "$archive")" || return 1
  [ "$actual" = "$digest" ] || return 1
  tar --no-same-owner -C "$extract" -xzf "$archive" || return 1
  binary="$(find "$extract" -type f -name realm -print -quit)"
  [ -n "$binary" ] || return 1
  chmod 0755 "$binary" || return 1
  actual_version="$(forward_realm_version "$binary")" || return 1
  [ "$actual_version" = "$version" ] || return 1
  nb_atomic_install_file "$binary" "$NOBRAND_REALM_BIN" 0755 || return 1
  meta="$(mktemp_file .realm-meta)" || return 1
  jq -n --arg version "$version" --arg channel "$channel" --arg asset "$asset" \
    --arg source "$url" --arg sha256 "$digest" --arg installed_at "$(forward_now)" '
      {schema_version:3,ownership:"nobrand-v3",consumer:"port-forward",version:$version,
       channel:$channel,asset:$asset,source_url:$source,sha256:$sha256,installed_at:$installed_at}
    ' >"$meta" && nb_atomic_install_file "$meta" "$NOBRAND_REALM_RUNTIME_META" 0600
  local rc=$?
  rm -f "$archive" "$meta"
  rm -rf -- "$extract"
  return "$rc"
}

forward_realm_service_active() {
  forward_realm_service_file_owned || return 1
  nb_service_is_active "$NOBRAND_REALM_SERVICE_NAME" "$NOBRAND_REALM_SERVICE_NAME"
}

forward_realm_service_pid() {
  forward_realm_service_file_owned || return 1
  case "$(nb_service_manager)" in
    systemd) systemctl show -p MainPID --value "$NOBRAND_REALM_SERVICE_NAME" 2>/dev/null ;;
    openrc) [ -s /run/nobrand-realm.pid ] && cat /run/nobrand-realm.pid ;;
  esac
}

forward_realm_service_path() {
  case "$(nb_service_manager)" in
    systemd) printf '%s' "$NOBRAND_REALM_SYSTEMD_SERVICE" ;;
    openrc) printf '%s' "$NOBRAND_REALM_OPENRC_SERVICE" ;;
    *) return 1 ;;
  esac
}

forward_realm_service_file_owned() {
  local path
  path="$(forward_realm_service_path 2>/dev/null)" || return 1
  forward_realm_service_path_owned "$path"
}

forward_realm_service_path_owned() {
  local path="$1"
  [ -f "$path" ] && [ ! -L "$path" ] \
    && grep -Fq 'Owned by NoBrand-OneClick Port Forward' "$path" \
    && grep -Fq "$NOBRAND_REALM_BIN" "$path" \
    && grep -Fq "$NOBRAND_FORWARD_REALM_CONFIG" "$path"
}

forward_realm_install_service() {
  local manager tmp path
  manager="$(nb_service_manager)"
  path="$(forward_realm_service_path)" || return 1
  [ ! -e "$path" ] || forward_realm_service_file_owned || {
    warn "Refusing to replace unowned Realm service: $path"
    return 1
  }
  tmp="$(mktemp_file .realm-service)" || return 1
  case "$manager" in
    systemd)
      cat >"$tmp" <<EOF
# Owned by NoBrand-OneClick Port Forward
[Unit]
Description=NoBrand Realm Port Forward
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=${NOBRAND_REALM_BIN} -c ${NOBRAND_FORWARD_REALM_CONFIG}
Restart=on-failure
RestartSec=2
NoNewPrivileges=true
PrivateTmp=true
ProtectHome=true
ProtectSystem=strict
ReadOnlyPaths=${NOBRAND_REALM_BIN} ${NOBRAND_FORWARD_REALM_CONFIG}

[Install]
WantedBy=multi-user.target
EOF
      nb_atomic_install_file "$tmp" "$NOBRAND_REALM_SYSTEMD_SERVICE" 0644 \
        && systemctl daemon-reload \
        && systemctl enable "$NOBRAND_REALM_SERVICE_NAME" >/dev/null 2>&1
      ;;
    openrc)
      cat >"$tmp" <<EOF
#!/sbin/openrc-run
# Owned by NoBrand-OneClick Port Forward
name="NoBrand Realm Port Forward"
command="${NOBRAND_REALM_BIN}"
command_args="-c ${NOBRAND_FORWARD_REALM_CONFIG}"
command_background="yes"
pidfile="/run/nobrand-realm.pid"
output_log="/var/log/nobrand-realm.log"
error_log="/var/log/nobrand-realm.err"
depend() { use net; after firewall; }
EOF
      nb_atomic_install_file "$tmp" "$NOBRAND_REALM_OPENRC_SERVICE" 0755 \
        && rc-update add "$NOBRAND_REALM_SERVICE_NAME" default >/dev/null 2>&1
      ;;
    *) rm -f "$tmp"; return 1 ;;
  esac
  local rc=$?
  rm -f "$tmp"
  return "$rc"
}

forward_realm_service_action() {
  forward_realm_service_file_owned || return 1
  case "$(nb_service_manager)" in
    systemd) systemctl "$1" "$NOBRAND_REALM_SERVICE_NAME" ;;
    openrc) rc-service "$NOBRAND_REALM_SERVICE_NAME" "$1" ;;
    *) return 1 ;;
  esac
}

forward_realm_listener_owned() {
  local state="$1" pid protocol port transport found listen_host enforcement
  pid="$(forward_realm_service_pid 2>/dev/null || true)"
  [[ "$pid" =~ ^[0-9]+$ ]] && [ "$pid" -gt 1 ] || return 1
  while IFS=$'\t' read -r protocol port listen_host enforcement; do
    while IFS= read -r transport; do
      found=0
      while IFS= read -r listener_pid; do
        [ "$listener_pid" != "$pid" ] || found=1
      done < <(nb_port_listener_pids "$transport" "$port")
      [ "$found" -eq 1 ] || return 1
      if [ "$enforcement" = strict ]; then
        nb_listener_has_local_address "$transport" "$port" "$listen_host" || return 1
      fi
    done < <(forward_protocol_transports "$protocol")
  done < <(jq -r '.rules[]|select(.enabled and .backend=="realm")|
    [.protocol,(.listen_port|tostring),.listen_host,(.ingress_enforcement // "permissive")]|@tsv' "$state")
}

forward_realm_probe_config() {
  local config="$1" pid i
  [ -x "$NOBRAND_REALM_BIN" ] || return 1
  "$NOBRAND_REALM_BIN" -c "$config" >/dev/null 2>&1 &
  pid=$!
  i=0
  while [ "$i" -lt 10 ]; do
    if ! kill -0 "$pid" 2>/dev/null; then
      wait "$pid" 2>/dev/null || true
      return 1
    fi
    sleep 0.1
    i=$((i + 1))
  done
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
}

forward_realm_probe_port_available() {
  local port="$1" protocol="$2" used="${3:-}" transport
  case "|$used|" in *"|$port|"*) return 1 ;; esac
  while IFS= read -r transport; do
    nb_port_available_for_transport "$port" "$transport" || return 1
  done < <(forward_protocol_transports "$protocol")
}

forward_generate_realm_probe_config() {
  local state="$1" output="$2" probe_state id protocol port used=""
  probe_state="$(mktemp_file .realm-probe-state)" || return 1
  cp -a "$state" "$probe_state" || { rm -f "$probe_state"; return 1; }
  while IFS=$'\t' read -r id protocol; do
    [ -n "$id" ] || continue
    port="$(nb_scan_port_span 40000 65535 forward_realm_probe_port_available "$protocol" "$used")" \
      || { rm -f "$probe_state"; return 1; }
    used="${used:+${used}|}${port}"
    jq --arg id "$id" --argjson port "$port" '
      (.rules[]|select(.rule_id==$id)) |=
        (.listen_port=$port | if .display_mode=="auto" then .display_port=$port else . end)
    ' "$probe_state" >"${probe_state}.next" \
      && mv -f "${probe_state}.next" "$probe_state" \
      || { rm -f "$probe_state" "${probe_state}.next"; return 1; }
  done < <(jq -r '.rules|sort_by(.rule_id)[]|select(.enabled and .backend=="realm")|
    [.rule_id,.protocol]|@tsv' "$state")
  forward_generate_realm_config "$probe_state" "$output"
  local rc=$?
  rm -f "$probe_state" "${probe_state}.next"
  return "$rc"
}

forward_realm_apply_state() {
  local state="$1" count candidate probe
  count="$(jq '[.rules[]|select(.enabled and .backend=="realm")]|length' "$state")" || return 1
  if [ "$count" -eq 0 ]; then
    forward_realm_service_action stop >/dev/null 2>&1 || true
    rm -f "$NOBRAND_FORWARD_REALM_CONFIG"
    return 0
  fi
  [ -x "$NOBRAND_REALM_BIN" ] || forward_realm_install_runtime stable || return 1
  candidate="$(mktemp_file .realm-candidate.toml)" || return 1
  probe="$(mktemp_file .realm-probe.toml)" || { rm -f "$candidate"; return 1; }
  forward_generate_realm_config "$state" "$candidate" \
    && forward_generate_realm_probe_config "$state" "$probe" \
    && forward_realm_probe_config "$probe" \
    || { rm -f "$candidate" "$probe"; return 1; }
  [ "${NOBRAND_TEST_INGRESS_SERVICE_FAIL:-0}" -eq 0 ] \
    && nb_atomic_install_file "$candidate" "$NOBRAND_FORWARD_REALM_CONFIG" 0600 \
    && forward_realm_install_service \
    && forward_realm_service_action restart \
    && forward_realm_service_active \
    && [ "${NOBRAND_TEST_INGRESS_LISTENER_FAIL:-0}" -eq 0 ] \
    && forward_realm_listener_owned "$state"
  local rc=$?
  rm -f "$candidate" "$probe"
  return "$rc"
}

forward_transaction_commit() {
  local candidate="$1" operation="${2:-modify}" old_backend="${3:-}" new_backend="${4:-}"
  local snapshot old_state failed=0
  forward_state_valid "$candidate" || return 1
  snapshot="$(mktemp_dir)" || return 1
  old_state="$snapshot/old-state.json"
  if [ -s "$NOBRAND_FORWARD_STATE_FILE" ]; then
    cp -a "$NOBRAND_FORWARD_STATE_FILE" "$old_state" || { rm -rf -- "$snapshot"; return 1; }
  else
    jq -n '{schema_version:3,ownership:"nobrand-v3",feature:"port-forward",rules:[]}' >"$old_state"
  fi
  forward_snapshot_restore_side_effects "$snapshot/side-effects" \
    || { rm -rf -- "$snapshot"; return 1; }
  if [ "$operation" = switch-backend ] && [ "$old_backend" = nftables ] && [ "$new_backend" = realm ]; then
    forward_realm_apply_state "$candidate" || failed=1
    [ "$failed" -ne 0 ] || forward_apply_nft_state "$candidate" || failed=1
  else
    forward_apply_nft_state "$candidate" || failed=1
    [ "$failed" -ne 0 ] || forward_realm_apply_state "$candidate" || failed=1
  fi
  [ "$failed" -ne 0 ] || forward_firewall_reconcile "$old_state" "$candidate" || failed=1
  if [ "$failed" -eq 0 ] && nb_atomic_install_file "$candidate" "$NOBRAND_FORWARD_STATE_FILE" 0600; then
    rm -rf -- "$snapshot"
    return 0
  fi
  forward_firewall_reconcile "$candidate" "$old_state" >/dev/null 2>&1 || true
  forward_restore_side_effect_snapshot "$snapshot/side-effects" >/dev/null 2>&1 || true
  forward_realm_apply_state "$old_state" >/dev/null 2>&1 || true
  rm -rf -- "$snapshot"
  return 1
}

forward_csv_strings_json() {
  local value="${1:-}"
  [ -n "$value" ] || { printf '[]'; return 0; }
  jq -Rn --arg value "$value" '$value|split(",")|map(gsub("^[[:space:]]+|[[:space:]]+$";""))|map(select(length>0))'
}

forward_csv_numbers_json() {
  local value="${1:-}"
  [ -n "$value" ] || { printf '[]'; return 0; }
  jq -Rn --arg value "$value" '
    $value|split(",")|map(gsub("^[[:space:]]+|[[:space:]]+$";""))|
    if all(.[]; test("^[0-9]+$") and ((tonumber)>=1) and ((tonumber)<=255))
    then map(tonumber) else error("invalid weight") end
  ' 2>/dev/null
}

forward_csv_socket_addresses_json() {
  local value="${1:-}" raw item normalized result='[]'
  [ -n "$value" ] || { printf '[]'; return 0; }
  raw="$(forward_csv_strings_json "$value")" || return 1
  while IFS= read -r item; do
    normalized="$(forward_socket_address_normalize "$item")" || return 1
    result="$(jq -c --arg value "$normalized" '.+[$value]' <<<"$result")" || return 1
  done < <(jq -r '.[]' <<<"$raw")
  printf '%s' "$result"
}

forward_realm_options_json() {
  local nameservers extra weights
  [ -z "$FORWARD_THROUGH" ] || valid_ip_literal "$FORWARD_THROUGH" || return 1
  for iface in "$FORWARD_INTERFACE" "$FORWARD_LISTEN_INTERFACE"; do
    [ -z "$iface" ] || [[ "$iface" =~ ^[A-Za-z0-9_.:-]{1,64}$ ]] || return 1
  done
  [[ "$FORWARD_TCP_TIMEOUT" =~ ^[0-9]+$ ]] && [ "$FORWARD_TCP_TIMEOUT" -le 86400 ] || return 1
  [[ "$FORWARD_UDP_TIMEOUT" =~ ^[0-9]+$ ]] && [ "$FORWARD_UDP_TIMEOUT" -ge 1 ] \
    && [ "$FORWARD_UDP_TIMEOUT" -le 86400 ] || return 1
  case "$FORWARD_PROXY_SEND" in true|false) ;; *) return 1 ;; esac
  case "$FORWARD_PROXY_ACCEPT" in true|false) ;; *) return 1 ;; esac
  case "$FORWARD_PROXY_VERSION" in 1|2) ;; *) return 1 ;; esac
  [[ "$FORWARD_PROXY_ACCEPT_TIMEOUT" =~ ^[0-9]+$ ]] && [ "$FORWARD_PROXY_ACCEPT_TIMEOUT" -le 86400 ] || return 1
  case "$FORWARD_DNS_MODE" in system|ipv4_only|ipv6_only|ipv4_then_ipv6|ipv6_then_ipv4|ipv4_and_ipv6) ;; *) return 1 ;; esac
  case "$FORWARD_DNS_PROTOCOL" in tcp|udp|tcp_and_udp) ;; *) return 1 ;; esac
  case "$FORWARD_BALANCE" in off|roundrobin|iphash) ;; *) return 1 ;; esac
  [ "${#FORWARD_LISTEN_TRANSPORT}" -le 1024 ] && [ "${#FORWARD_REMOTE_TRANSPORT}" -le 1024 ] || return 1
  ! has_control_chars "$FORWARD_LISTEN_TRANSPORT" && ! has_control_chars "$FORWARD_REMOTE_TRANSPORT" || return 1
  nameservers="$(forward_csv_socket_addresses_json "$FORWARD_DNS_NAMESERVERS")" || return 1
  extra="$(forward_csv_socket_addresses_json "$FORWARD_EXTRA_TARGETS")" || return 1
  weights="$(forward_csv_numbers_json "$FORWARD_WEIGHTS")" || return 1
  jq -e 'all(.[]; type=="string" and length>0 and length<=255 and (test("[[:space:]]")|not))' \
    <<<"$nameservers" >/dev/null || return 1
  jq -e 'all(.[]; type=="string" and length>2 and length<=300 and (test("[[:space:]]")|not))' \
    <<<"$extra" >/dev/null || return 1
  if [ "$FORWARD_BALANCE" = off ]; then
    [ "$weights" = '[]' ] && [ "$extra" = '[]' ] || return 1
  else
    [ "$(jq 'length' <<<"$extra")" -gt 0 ] || return 1
    [ "$(jq 'length' <<<"$weights")" -eq "$((1 + $(jq 'length' <<<"$extra")))" ] || return 1
  fi
  jq -n --arg through "$FORWARD_THROUGH" --arg interface "$FORWARD_INTERFACE" \
    --arg listen_interface "$FORWARD_LISTEN_INTERFACE" \
    --argjson tcp_timeout "$FORWARD_TCP_TIMEOUT" --argjson udp_timeout "$FORWARD_UDP_TIMEOUT" \
    --argjson proxy_send "$FORWARD_PROXY_SEND" --argjson proxy_accept "$FORWARD_PROXY_ACCEPT" \
    --argjson proxy_version "$FORWARD_PROXY_VERSION" \
    --argjson proxy_accept_timeout "$FORWARD_PROXY_ACCEPT_TIMEOUT" \
    --arg dns_mode "$FORWARD_DNS_MODE" --arg dns_protocol "$FORWARD_DNS_PROTOCOL" \
    --argjson dns_nameservers "$nameservers" --arg listen_transport "$FORWARD_LISTEN_TRANSPORT" \
    --arg remote_transport "$FORWARD_REMOTE_TRANSPORT" --argjson extra_targets "$extra" \
    --arg balance "$FORWARD_BALANCE" --argjson weights "$weights" '
      {through:$through,interface:$interface,listen_interface:$listen_interface,
       tcp_timeout:$tcp_timeout,udp_timeout:$udp_timeout,proxy_send:$proxy_send,
       proxy_accept:$proxy_accept,proxy_version:$proxy_version,
       proxy_accept_timeout:$proxy_accept_timeout,dns_mode:$dns_mode,
       dns_protocol:$dns_protocol,dns_nameservers:$dns_nameservers,
       listen_transport:$listen_transport,remote_transport:$remote_transport,
       extra_targets:$extra_targets,balance:$balance,weights:$weights}
    '
}

forward_default_options_json() {
  case "$1" in
    nftables)
      case "$FORWARD_SOURCE_MODE" in masquerade|preserve) ;; *) return 1 ;; esac
      jq -n --arg source_mode "$FORWARD_SOURCE_MODE" '{source_mode:$source_mode}'
      ;;
    realm) forward_realm_options_json ;;
    *) return 1 ;;
  esac
}

forward_prepare_ingress_enforcement() {
  local backend="$1" profile_id="$2" capability
  case "$backend" in
    nftables) capability='address-match' ;;
    realm) capability=native-bind ;;
    *) return 1 ;;
  esac
  nb_prepare_ingress_deployment "$profile_id" "$capability" || return 1
  if [ "$INGRESS_ENFORCEMENT_RESOLVED" = strict ]; then
    FORWARD_LISTEN_HOST="$INGRESS_LISTEN_HOST"
  else
    FORWARD_LISTEN_HOST="${FORWARD_LISTEN_HOST:-0.0.0.0}"
  fi
}

forward_validate_requested_rule() {
  local ignore_owner="${1:-}" transport old_json="${2:-}" old_port="" old_protocol=""
  [ -n "$FORWARD_NAME" ] && [ "${#FORWARD_NAME}" -le 64 ] && ! has_control_chars "$FORWARD_NAME" || return 1
  [ "${#FORWARD_NOTE}" -le 256 ] && ! has_control_chars "$FORWARD_NOTE" || return 1
  case "$FORWARD_BACKEND" in nftables|realm) ;; *) return 1 ;; esac
  FORWARD_PROTOCOL="$(forward_normalize_protocol "$FORWARD_PROTOCOL")" || return 1
  [ -n "${INGRESS_PROFILE_ID:-}" ] || nb_prepare_ingress_request || return 1
  FORWARD_LISTEN_HOST="${FORWARD_LISTEN_HOST:-0.0.0.0}"
  forward_listen_host_valid "$FORWARD_BACKEND" "$FORWARD_LISTEN_HOST" || return 1
  nb_valid_port "$FORWARD_LISTEN_PORT" && nb_valid_port "$FORWARD_TARGET_PORT" || return 1
  FORWARD_LISTEN_PORT="$(normalize_uint "$FORWARD_LISTEN_PORT")"
  FORWARD_TARGET_PORT="$(normalize_uint "$FORWARD_TARGET_PORT")"
  if [ "$FORWARD_BACKEND" = nftables ] && ! forward_valid_ipv4 "$FORWARD_TARGET_HOST"; then
    warn 'nftables backend currently requires IP target; use Realm backend for domain targets.'
    return 1
  fi
  forward_target_valid "$FORWARD_BACKEND" "$FORWARD_TARGET_HOST" || return 1
  if [ -n "$old_json" ]; then
    old_port="$(jq -r .listen_port <<<"$old_json")"
    old_protocol="$(jq -r .protocol <<<"$old_json")"
  fi
  if [ "$old_port" != "$FORWARD_LISTEN_PORT" ] || [ "$old_protocol" != "$FORWARD_PROTOCOL" ]; then
    forward_port_allowed "$FORWARD_LISTEN_PORT" "$FORWARD_PROTOCOL" "$ignore_owner" "$INGRESS_PROFILE_ID" || return 1
  else
    nb_ingress_port_is_reserved "$INGRESS_PROFILE_ID" "$FORWARD_LISTEN_PORT" && return 1
  fi
  return 0
}

forward_requested_display_json() {
  if [ "$ADVERTISE_CLI" -eq 1 ] && [ "$ADVERTISE_AUTO_REQUESTED" -eq 0 ]; then
    valid_advertise_host "$ADVERTISE_HOST" && valid_advertise_port "$ADVERTISE_PORT" || return 1
    jq -n --arg mode custom --arg host "$ADVERTISE_HOST" \
      --argjson port "$(normalize_uint "$ADVERTISE_PORT")" '{mode:$mode,host:$host,port:$port}'
  else
    jq -n --arg mode auto --arg host '' --argjson port "$FORWARD_LISTEN_PORT" \
      '{mode:$mode,host:$host,port:$port}'
  fi
}

forward_add_rule() {
  local id now options display rule candidate
  forward_init_state || return 1
  nb_prepare_ingress_request || return 1
  [ -n "$FORWARD_NAME" ] && [ -n "$FORWARD_BACKEND" ] && [ -n "$FORWARD_PROTOCOL" ] \
    && [ -n "$FORWARD_TARGET_HOST" ] && [ -n "$FORWARD_TARGET_PORT" ] \
    || die 'forward add 非交互模式需要 --name --backend --protocol --target --target-port'
  FORWARD_PROTOCOL="$(forward_normalize_protocol "$FORWARD_PROTOCOL")" || die 'Forward protocol 无效'
  forward_prepare_ingress_enforcement "$FORWARD_BACKEND" "$INGRESS_PROFILE_ID" \
    || die '所选 Ingress strict local address cannot be enforced by Forward'
  if [ -z "$FORWARD_LISTEN_PORT" ]; then
    FORWARD_LISTEN_PORT="$(forward_select_available_port "$FORWARD_PROTOCOL" "$INGRESS_PROFILE_ID")" \
      || die '所选入口配置没有可用 Forward 自动端口；manual-only 必须显式使用 --port'
  fi
  forward_validate_requested_rule || die 'Forward rule 参数无效、端口冲突或命中 xx00 保留端口'
  jq -e --arg name "$FORWARD_NAME" 'all(.rules[];.name!=$name)' "$NOBRAND_FORWARD_STATE_FILE" >/dev/null \
    || die 'Forward rule name 已存在'
  options="$(forward_default_options_json "$FORWARD_BACKEND")" || die 'Forward backend options 无效'
  display="$(forward_requested_display_json)" || die 'Forward Display Endpoint 无效'
  id="$(forward_generate_rule_id)"
  now="$(forward_now)"
  rule="$(jq -n --arg id "$id" --arg name "$FORWARD_NAME" --arg note "$FORWARD_NOTE" \
    --arg backend "$FORWARD_BACKEND" --arg protocol "$FORWARD_PROTOCOL" \
    --arg listen_host "$FORWARD_LISTEN_HOST" --argjson listen_port "$FORWARD_LISTEN_PORT" \
    --arg target_host "$FORWARD_TARGET_HOST" --argjson target_port "$FORWARD_TARGET_PORT" \
    --arg display_mode "$(jq -r .mode <<<"$display")" --arg display_host "$(jq -r .host <<<"$display")" \
    --argjson display_port "$(jq -r .port <<<"$display")" --arg now "$now" \
    --argjson options "$options" --arg ingress_profile_id "$INGRESS_PROFILE_ID" \
    --arg ingress_enforcement "$INGRESS_ENFORCEMENT_RESOLVED" \
    --arg ingress_method "$INGRESS_ENFORCEMENT_METHOD" --arg ingress_address "$INGRESS_LOCAL_ADDRESS" '
      {rule_id:$id,name:$name,note:$note,backend:$backend,enabled:true,protocol:$protocol,
       listen_host:$listen_host,listen_port:$listen_port,target_host:$target_host,target_port:$target_port,
       display_host:$display_host,display_port:$display_port,display_mode:$display_mode,
       created_at:$now,updated_at:$now,
       ownership_metadata:{managed_listener:true,managed_firewall:true},backend_options:$options,
        ingress_profile_id:$ingress_profile_id,ingress_enforcement:$ingress_enforcement,
        ingress_enforcement_method:$ingress_method,ingress_local_address:$ingress_address}
    ')" || return 1
  candidate="$(mktemp_file .forward-add)" || return 1
  jq --argjson rule "$rule" '.rules += [$rule]' "$NOBRAND_FORWARD_STATE_FILE" >"$candidate" \
    && forward_transaction_commit "$candidate" add '' "$FORWARD_BACKEND"
  local rc=$?
  rm -f "$candidate"
  [ "$rc" -ne 0 ] || msg "Forward rule created: ${id} (${FORWARD_NAME})"
  return "$rc"
}

forward_delete_rule() {
  local id old_backend candidate
  id="$(forward_resolve_rule_id "$FORWARD_RULE_ID")" || die 'Forward rule 不存在'
  old_backend="$(jq -r --arg id "$id" '.rules[]|select(.rule_id==$id)|.backend' "$NOBRAND_FORWARD_STATE_FILE")"
  candidate="$(mktemp_file .forward-delete)" || return 1
  jq --arg id "$id" '.rules |= map(select(.rule_id!=$id))' "$NOBRAND_FORWARD_STATE_FILE" >"$candidate" \
    && forward_transaction_commit "$candidate" delete "$old_backend" ''
  local rc=$?
  rm -f "$candidate"
  return "$rc"
}

forward_set_enabled() {
  local enabled="$1" id backend candidate
  id="$(forward_resolve_rule_id "$FORWARD_RULE_ID")" || die 'Forward rule 不存在'
  backend="$(jq -r --arg id "$id" '.rules[]|select(.rule_id==$id)|.backend' "$NOBRAND_FORWARD_STATE_FILE")"
  candidate="$(mktemp_file .forward-enable)" || return 1
  jq --arg id "$id" --argjson enabled "$enabled" --arg now "$(forward_now)" \
    '(.rules[]|select(.rule_id==$id)) |= (.enabled=$enabled|.updated_at=$now)' \
    "$NOBRAND_FORWARD_STATE_FILE" >"$candidate" \
    && forward_transaction_commit "$candidate" enable "$backend" "$backend"
  local rc=$?
  rm -f "$candidate"
  return "$rc"
}

forward_modify_rule() {
  local id old old_backend options candidate new_name new_note new_protocol new_listen_host
  local new_listen_port new_target_host new_target_port display
  local new_display_mode new_display_host new_display_port old_ingress_profile_id
  id="$(forward_resolve_rule_id "$FORWARD_RULE_ID")" || die 'Forward rule 不存在'
  old="$(forward_rule_json "$NOBRAND_FORWARD_STATE_FILE" "$id")"
  old_backend="$(jq -r .backend <<<"$old")"
  old_ingress_profile_id="$(jq -r '.ingress_profile_id // "legacy-default-route"' <<<"$old")"
  if [ "$INGRESS_PROFILE_CLI" -eq 1 ]; then
    INGRESS_PROFILE_ID="$(nb_resolve_ingress_profile "$INGRESS_PROFILE")" || return 1
  else
    INGRESS_PROFILE_ID="$old_ingress_profile_id"
  fi
  [ -z "$FORWARD_BACKEND" ] || [ "$FORWARD_BACKEND" = "$old_backend" ] \
    || die 'modify 不切换 backend；请使用 switch-backend'
  FORWARD_BACKEND="$old_backend"
  new_name="${FORWARD_NAME:-$(jq -r .name <<<"$old")}"
  new_note="${FORWARD_NOTE:-$(jq -r .note <<<"$old")}"
  new_protocol="${FORWARD_PROTOCOL:-$(jq -r .protocol <<<"$old")}"
  new_listen_host="${FORWARD_LISTEN_HOST:-$(jq -r .listen_host <<<"$old")}"
  new_listen_port="${FORWARD_LISTEN_PORT:-$(jq -r .listen_port <<<"$old")}"
  new_target_host="${FORWARD_TARGET_HOST:-$(jq -r .target_host <<<"$old")}"
  new_target_port="${FORWARD_TARGET_PORT:-$(jq -r .target_port <<<"$old")}"
  FORWARD_NAME="$new_name" FORWARD_NOTE="$new_note" FORWARD_PROTOCOL="$new_protocol"
  FORWARD_LISTEN_HOST="$new_listen_host" FORWARD_LISTEN_PORT="$new_listen_port"
  FORWARD_TARGET_HOST="$new_target_host" FORWARD_TARGET_PORT="$new_target_port"
  forward_prepare_ingress_enforcement "$FORWARD_BACKEND" "$INGRESS_PROFILE_ID" \
    || die 'Modified Forward rule cannot enforce the selected Ingress profile'
  if [ "$INGRESS_ENFORCEMENT_RESOLVED" = permissive ] \
     && [ "$(jq -r '.ingress_enforcement // "permissive"' <<<"$old")" = strict ] \
     && [ "${FORWARD_LISTEN_HOST_CLI:-0}" -eq 0 ]; then
    FORWARD_LISTEN_HOST=0.0.0.0
  fi
  forward_validate_requested_rule "forward:${id}" "$old" || die 'Forward 修改参数无效、冲突或命中 xx00'
  if [ "$ADVERTISE_CLI" -eq 1 ]; then
    display="$(forward_requested_display_json)" || die 'Forward Display Endpoint 无效'
    new_display_mode="$(jq -r .mode <<<"$display")"
    new_display_host="$(jq -r .host <<<"$display")"
    new_display_port="$(jq -r .port <<<"$display")"
  elif [ "$(jq -r .display_mode <<<"$old")" = auto ]; then
    # Auto Display Endpoints follow the real listener.  Keeping the previous
    # display_port after a listen-port modification would make the candidate
    # internally inconsistent and forward_state_valid correctly rejects it.
    new_display_mode=auto
    new_display_host=""
    new_display_port="$FORWARD_LISTEN_PORT"
  else
    new_display_mode="$(jq -r .display_mode <<<"$old")"
    new_display_host="$(jq -r .display_host <<<"$old")"
    new_display_port="$(jq -r .display_port <<<"$old")"
  fi
  if [ "$old_backend" = nftables ]; then
    if [ "$FORWARD_SOURCE_MODE_CLI" -eq 1 ]; then
      options="$(forward_default_options_json nftables)" || die 'nftables source mode 无效'
    else
      options="$(jq -c .backend_options <<<"$old")"
    fi
  elif [ "$FORWARD_ADVANCED_CLI" -eq 1 ]; then
    options="$(forward_default_options_json realm)" || die 'Realm advanced options 无效'
  else
    options="$(jq -c .backend_options <<<"$old")"
  fi
  candidate="$(mktemp_file .forward-modify)" || return 1
  jq --arg id "$id" --arg name "$FORWARD_NAME" --arg note "$FORWARD_NOTE" \
    --arg protocol "$FORWARD_PROTOCOL" --arg listen_host "$FORWARD_LISTEN_HOST" \
    --argjson listen_port "$FORWARD_LISTEN_PORT" --arg target_host "$FORWARD_TARGET_HOST" \
    --argjson target_port "$FORWARD_TARGET_PORT" --arg display_mode "$new_display_mode" \
    --arg display_host "$new_display_host" --argjson display_port "$new_display_port" \
    --argjson options "$options" --arg ingress_profile_id "$INGRESS_PROFILE_ID" --arg now "$(forward_now)" \
    --arg ingress_enforcement "$INGRESS_ENFORCEMENT_RESOLVED" \
    --arg ingress_method "$INGRESS_ENFORCEMENT_METHOD" --arg ingress_address "$INGRESS_LOCAL_ADDRESS" '
      (.rules[]|select(.rule_id==$id)) |=
        (.name=$name|.note=$note|.protocol=$protocol|.listen_host=$listen_host|.listen_port=$listen_port|
         .target_host=$target_host|.target_port=$target_port|.display_mode=$display_mode|
         .display_host=$display_host|.display_port=$display_port|.backend_options=$options|
         .ingress_profile_id=$ingress_profile_id|.ingress_enforcement=$ingress_enforcement|
         .ingress_enforcement_method=$ingress_method|.ingress_local_address=$ingress_address|.updated_at=$now)
    ' "$NOBRAND_FORWARD_STATE_FILE" >"$candidate" \
    && forward_transaction_commit "$candidate" modify "$old_backend" "$old_backend"
  local rc=$?
  rm -f "$candidate"
  return "$rc"
}

forward_switch_backend() {
  local id old old_backend new_backend options target candidate profile_id
  id="$(forward_resolve_rule_id "$FORWARD_RULE_ID")" || die 'Forward rule 不存在'
  old="$(forward_rule_json "$NOBRAND_FORWARD_STATE_FILE" "$id")"
  old_backend="$(jq -r .backend <<<"$old")"
  new_backend="$FORWARD_BACKEND"
  case "$new_backend" in nftables|realm) ;; *) die 'switch-backend 需要 --backend nftables|realm' ;; esac
  [ "$new_backend" != "$old_backend" ] || die 'Forward rule 已使用该 backend'
  target="${FORWARD_TARGET_HOST:-$(jq -r .target_host <<<"$old")}"
  if [ "$new_backend" = nftables ] && ! forward_valid_ipv4 "$target"; then
    [ -n "$FORWARD_TARGET_HOST" ] \
      || die 'Realm domain/IPv6 切换到 nftables 时必须显式提供 --target IPv4；不会静默解析并固定域名'
  fi
  FORWARD_NAME="$(jq -r .name <<<"$old")"
  FORWARD_NOTE="$(jq -r .note <<<"$old")"
  FORWARD_PROTOCOL="$(jq -r .protocol <<<"$old")"
  FORWARD_LISTEN_HOST="${FORWARD_LISTEN_HOST:-$(jq -r .listen_host <<<"$old")}"
  if [ "$new_backend" = nftables ] && ! forward_valid_ipv4 "$FORWARD_LISTEN_HOST"; then
    FORWARD_LISTEN_HOST=0.0.0.0
  fi
  FORWARD_LISTEN_PORT="$(jq -r .listen_port <<<"$old")"
  FORWARD_TARGET_HOST="$target"
  FORWARD_TARGET_PORT="${FORWARD_TARGET_PORT:-$(jq -r .target_port <<<"$old")}"
  FORWARD_BACKEND="$new_backend"
  profile_id="$(jq -r '.ingress_profile_id // "legacy-default-route"' <<<"$old")"
  forward_prepare_ingress_enforcement "$new_backend" "$profile_id" \
    || die 'Backend switch cannot enforce the retained Ingress profile'
  forward_validate_requested_rule "forward:${id}" "$old" || die 'Backend switch 参数无效'
  options="$(forward_default_options_json "$new_backend")" || die 'Backend options 无效'
  candidate="$(mktemp_file .forward-switch)" || return 1
  jq --arg id "$id" --arg backend "$new_backend" --arg listen_host "$FORWARD_LISTEN_HOST" \
    --arg target_host "$FORWARD_TARGET_HOST" --argjson target_port "$FORWARD_TARGET_PORT" \
    --argjson options "$options" --arg now "$(forward_now)" \
    --arg ingress_enforcement "$INGRESS_ENFORCEMENT_RESOLVED" \
    --arg ingress_method "$INGRESS_ENFORCEMENT_METHOD" --arg ingress_address "$INGRESS_LOCAL_ADDRESS" '
      (.rules[]|select(.rule_id==$id)) |=
       (.backend=$backend|.listen_host=$listen_host|.target_host=$target_host|.target_port=$target_port|
         .backend_options=$options|.ingress_enforcement=$ingress_enforcement|
         .ingress_enforcement_method=$ingress_method|.ingress_local_address=$ingress_address|.updated_at=$now)
    ' "$NOBRAND_FORWARD_STATE_FILE" >"$candidate" \
    && forward_transaction_commit "$candidate" switch-backend "$old_backend" "$new_backend"
  local rc=$?
  rm -f "$candidate"
  return "$rc"
}

forward_apply_ingress_enforcement() {
  local id="$1" rule backend profile_id candidate rc
  rule="$(forward_rule_json "$NOBRAND_FORWARD_STATE_FILE" "$id")" || return 1
  [ -n "$rule" ] || return 1
  backend="$(jq -r .backend <<<"$rule")"
  profile_id="$(jq -r '.ingress_profile_id // "legacy-default-route"' <<<"$rule")"
  FORWARD_LISTEN_HOST="$(jq -r .listen_host <<<"$rule")"
  forward_prepare_ingress_enforcement "$backend" "$profile_id" || return 1
  [ "$INGRESS_ENFORCEMENT_RESOLVED" != permissive ] || FORWARD_LISTEN_HOST=0.0.0.0
  candidate="$(mktemp_file .forward-ingress-apply)" || return 1
  jq --arg id "$id" --arg listen "$FORWARD_LISTEN_HOST" \
    --arg policy "$INGRESS_ENFORCEMENT_RESOLVED" --arg method "$INGRESS_ENFORCEMENT_METHOD" \
    --arg address "$INGRESS_LOCAL_ADDRESS" --arg now "$(forward_now)" '
      (.rules[]|select(.rule_id==$id)) |=
        (.listen_host=$listen|.ingress_enforcement=$policy|
         .ingress_enforcement_method=$method|.ingress_local_address=$address|.updated_at=$now)
    ' "$NOBRAND_FORWARD_STATE_FILE" >"$candidate" \
    && forward_transaction_commit "$candidate" ingress-enforcement "$backend" "$backend"
  rc=$?
  rm -f "$candidate"
  return "$rc"
}

forward_listener_enforcement_owned() {
  local id="$1" rule backend
  rule="$(forward_rule_json "$NOBRAND_FORWARD_STATE_FILE" "$id")" || return 1
  [ -n "$rule" ] || return 1
  backend="$(jq -r .backend <<<"$rule")"
  case "$backend" in
    nftables) forward_nft_rule_ingress_owned "$id" ;;
    realm) forward_realm_service_active && forward_realm_listener_owned "$NOBRAND_FORWARD_STATE_FILE" ;;
    *) return 1 ;;
  esac
}

forward_list_rules() {
  forward_init_state || return 1
  printf '%-18s %-20s %-10s %-6s %-22s %-11s %-28s %s\n' ID NAME BACKEND PROTO LISTEN ENFORCEMENT TARGET STATUS
  jq -r '.rules|sort_by(.rule_id)[]|[.rule_id,.name,.backend,.protocol,
    (.listen_host+":"+(.listen_port|tostring)),(.ingress_enforcement // "permissive"),(.target_host+":"+(.target_port|tostring)),
    (if .enabled then "Enabled" else "Disabled" end)]|@tsv' "$NOBRAND_FORWARD_STATE_FILE" \
    | while IFS=$'\t' read -r id name backend protocol listen enforcement target status; do
        printf '%-18s %-20s %-10s %-6s %-22s %-11s %-28s %s\n' \
          "$id" "$name" "$backend" "$protocol" "$listen" "$enforcement" "$target" "$status"
      done
}

forward_node_rows() {
  local auto_host id name backend enabled protocol display_mode display_host display_port listen_port
  local effective_host effective_port status
  [ -s "$NOBRAND_FORWARD_STATE_FILE" ] || return 0
  auto_host="$(public_ip 2>/dev/null || printf 'YOUR_SERVER_IP')"
  local ingress_profile_id
  while IFS=$'\x1f' read -r id name backend enabled protocol display_mode display_host display_port listen_port ingress_profile_id; do
    effective_host="$display_host"
    [ "$display_mode" = custom ] \
      || effective_host="$(nb_effective_advertise_host auto '' "$ingress_profile_id")"
    effective_port="$display_port"
    [ "$display_mode" = custom ] \
      || effective_port="$(nb_effective_advertise_port auto '' "$listen_port" "$ingress_profile_id")"
    status=Disabled
    if [ "$enabled" = true ]; then
      if [ "$backend" = nftables ]; then
        status=Degraded
        forward_nft_rule_owned "$id" && status=Healthy
      else
        status=Degraded
        forward_realm_service_active && status=Healthy
      fi
    fi
    printf 'Port Forward/%s|%s|%s:%s|%s|%s\n' \
      "$backend" "$name" "$effective_host" "$effective_port" "$status" "$(printf '%s' "$protocol" | tr '[:lower:]' '[:upper:]')"
  done < <(jq -r '.rules|sort_by(.rule_id)[]|[.rule_id,.name,.backend,(.enabled|tostring),.protocol,
    .display_mode,.display_host,(.display_port|tostring),(.listen_port|tostring),(.ingress_profile_id // "legacy-default-route")]|join("\u001f")' \
    "$NOBRAND_FORWARD_STATE_FILE")
}

forward_show_rule() {
  local id rule display_host display_port
  id="$(forward_resolve_rule_id "$FORWARD_RULE_ID")" || die 'Forward rule 不存在'
  rule="$(forward_rule_json "$NOBRAND_FORWARD_STATE_FILE" "$id")"
  display_host="$(nb_effective_advertise_host "$(jq -r .display_mode <<<"$rule")" "$(jq -r .display_host <<<"$rule")" "$(jq -r '.ingress_profile_id // "legacy-default-route"' <<<"$rule")")"
  display_port="$(nb_effective_advertise_port "$(jq -r .display_mode <<<"$rule")" \
    "$(jq -r .display_port <<<"$rule")" "$(jq -r .listen_port <<<"$rule")" "$(jq -r '.ingress_profile_id // "legacy-default-route"' <<<"$rule")")"
  printf 'ID: %s\nName: %s\nNote: %s\nBackend: %s\nEnabled: %s\nProtocol: %s\n' \
    "$id" "$(jq -r .name <<<"$rule")" "$(jq -r .note <<<"$rule")" "$(jq -r .backend <<<"$rule")" \
    "$(jq -r .enabled <<<"$rule")" "$(jq -r .protocol <<<"$rule")"
  printf 'Real listener: %s:%s\nTarget: %s:%s\nDisplay endpoint: %s:%s\nDisplay mode: %s\n' \
    "$(jq -r .listen_host <<<"$rule")" "$(jq -r .listen_port <<<"$rule")" \
    "$(jq -r .target_host <<<"$rule")" "$(jq -r .target_port <<<"$rule")" \
    "$display_host" "$display_port" "$(jq -r .display_mode <<<"$rule")"
  printf 'Ingress Profile: %s\n' "$(nb_ingress_profile_name "$(jq -r '.ingress_profile_id // "legacy-default-route"' <<<"$rule")")"
  printf 'Ingress Enforcement: %s (%s)\nIngress Local Address: %s\n' \
    "$(jq -r '.ingress_enforcement // "permissive"' <<<"$rule")" \
    "$(jq -r '.ingress_enforcement_method // "wildcard"' <<<"$rule")" \
    "$(jq -r '.ingress_local_address // empty' <<<"$rule")"
  printf 'Backend options: %s\n' "$(jq -c .backend_options <<<"$rule")"
}

forward_doctor() {
  local failed=0 id backend enabled protocol port target transport owner count
  forward_state_valid "$NOBRAND_FORWARD_STATE_FILE" || { warn 'Forward state: FAIL'; return 1; }
  msg 'Forward state: PASS (schema v3)'
  while IFS=$'\t' read -r id backend enabled protocol port target; do
    owner="forward:${id}"
    while IFS= read -r transport; do
      [ "$(nb_registry_port_owner "$transport" "$port" 2>/dev/null || true)" = "$owner" ] \
        || { warn "${id} port registry ${transport}/${port}: FAIL"; failed=1; }
    done < <(forward_protocol_transports "$protocol")
    forward_target_valid "$backend" "$target" || { warn "${id} target: FAIL"; failed=1; }
    [ "$enabled" = true ] || continue
    if [ "$backend" = nftables ]; then
      forward_nft_rule_ingress_owned "$id" \
        || { warn "${id} nft ownership: FAIL"; failed=1; }
      [ "$(sysctl -n net.ipv4.ip_forward 2>/dev/null || true)" = 1 ] \
        || { warn "${id} ip_forward: FAIL"; failed=1; }
    else
      forward_realm_service_active || { warn "${id} Realm service: FAIL"; failed=1; }
    fi
  done < <(jq -r '.rules[]|[.rule_id,.backend,(.enabled|tostring),.protocol,
    (.listen_port|tostring),.target_host]|@tsv' "$NOBRAND_FORWARD_STATE_FILE")
  count="$(jq '[.rules[]|select(.enabled and .backend=="realm")]|length' "$NOBRAND_FORWARD_STATE_FILE")"
  [ "$count" -eq 0 ] || forward_realm_listener_owned "$NOBRAND_FORWARD_STATE_FILE" \
    || { warn 'Realm listener ownership: FAIL'; failed=1; }
  [ "$failed" -eq 0 ] && msg 'Port Forward Doctor: PASS'
  [ "$failed" -eq 0 ]
}

forward_import_apply() {
  local source="$FORWARD_IMPORT_FILE" candidate
  [ -n "$source" ] || die 'forward import 需要文件路径'
  forward_import_validate "$source" || die 'Forward import 文件无效或包含未知字段'
  candidate="$(mktemp_file .forward-import)" || return 1
  jq '{schema_version:.schema_version,ownership:.ownership,feature:"port-forward",rules:.rules}' "$source" >"$candidate" \
    && forward_transaction_commit "$candidate" import '' ''
  local rc=$?
  rm -f "$candidate"
  return "$rc"
}

forward_realm_restore_runtime() {
  local count channel version
  [ -s "$NOBRAND_FORWARD_STATE_FILE" ] || return 0
  count="$(jq '[.rules[]|select(.backend=="realm")]|length' "$NOBRAND_FORWARD_STATE_FILE")"
  [ "$count" -gt 0 ] || return 0
  if [ -x "$NOBRAND_REALM_BIN" ] && forward_realm_runtime_metadata_valid; then
    return 0
  fi
  forward_realm_runtime_metadata_valid || return 1
  channel="$(jq -r '.channel' "$NOBRAND_REALM_RUNTIME_META")"
  version="$(jq -r '.version' "$NOBRAND_REALM_RUNTIME_META")"
  case "$channel" in
    stable) forward_realm_install_runtime stable ;;
    latest|pinned) forward_realm_install_runtime pinned "$version" ;;
    *) return 1 ;;
  esac
}

forward_snapshot_restore_side_effects() {
  local snapshot="$1" item label path runtime_owned=0
  mkdir -p "$snapshot/sysctl" || return 1
  forward_sysctl_snapshot "$snapshot/sysctl" || return 1
  forward_realm_runtime_metadata_valid && runtime_owned=1
  for item in \
    "binary|$NOBRAND_REALM_BIN" \
    "metadata|$NOBRAND_REALM_RUNTIME_META" \
    "systemd-service|$NOBRAND_REALM_SYSTEMD_SERVICE" \
    "openrc-service|$NOBRAND_REALM_OPENRC_SERVICE"; do
    label="${item%%|*}"; path="${item#*|}"
    if [ -e "$path" ] || [ -L "$path" ]; then
      case "$label" in
        binary|metadata)
          if [ "$runtime_owned" -eq 1 ]; then
            cp -a "$path" "$snapshot/$label" || return 1
          else
            : >"$snapshot/${label}.external" || return 1
          fi
          ;;
        systemd-service|openrc-service)
          if forward_realm_service_path_owned "$path"; then
            cp -a "$path" "$snapshot/$label" || return 1
          else
            : >"$snapshot/${label}.external" || return 1
          fi
          ;;
      esac
    else
      : >"$snapshot/${label}.absent" || return 1
    fi
  done
  if command -v nft >/dev/null 2>&1 \
     && nft list table "$NOBRAND_FORWARD_NFT_FAMILY" "$NOBRAND_FORWARD_NFT_TABLE" >/dev/null 2>&1; then
    if forward_nft_table_owned; then
      # `nft list table` is not a round-trip serialization on every supported
      # nftables version: it may resolve service names and can optimize away
      # the l4proto context required to parse `ct original proto-dst` again.
      # Rebuild the snapshot from the validated authoritative state instead.
      [ -s "$NOBRAND_FORWARD_STATE_FILE" ] \
        && forward_state_valid "$NOBRAND_FORWARD_STATE_FILE" \
        && forward_generate_nft_ruleset "$NOBRAND_FORWARD_STATE_FILE" "$snapshot/nft-table.nft" \
        || return 1
    else
      : >"$snapshot/nft-table.external" || return 1
    fi
  else
    : >"$snapshot/nft-table.absent" || return 1
  fi
}

forward_remove_restore_attempt_resources() {
  forward_realm_service_action stop >/dev/null 2>&1 || true
  forward_remove_owned_nft_table >/dev/null 2>&1 || true
}

forward_restore_side_effect_snapshot() {
  local snapshot="$1" item label path mode failed=0
  forward_remove_restore_attempt_resources
  for item in \
    "binary|$NOBRAND_REALM_BIN|0755" \
    "metadata|$NOBRAND_REALM_RUNTIME_META|0600" \
    "systemd-service|$NOBRAND_REALM_SYSTEMD_SERVICE|0644" \
    "openrc-service|$NOBRAND_REALM_OPENRC_SERVICE|0755"; do
    label="${item%%|*}"
    path="${item#*|}"; path="${path%%|*}"
    mode="${item##*|}"
    if [ -e "$snapshot/${label}.external" ]; then
      :
    elif [ -e "$snapshot/$label" ]; then
      nb_atomic_install_file "$snapshot/$label" "$path" "$mode" || failed=1
    else
      rm -f "$path" || failed=1
    fi
  done
  if [ -s "$snapshot/nft-table.nft" ]; then
    command -v nft >/dev/null 2>&1 && nft -c -f "$snapshot/nft-table.nft" >/dev/null 2>&1 \
      && nft -f "$snapshot/nft-table.nft" || failed=1
  fi
  forward_sysctl_restore_snapshot "$snapshot/sysctl" || failed=1
  [ "$(nb_service_manager)" != systemd ] || systemctl daemon-reload >/dev/null 2>&1 || failed=1
  [ "$failed" -eq 0 ]
}

forward_uninstall() {
  local empty service_path
  forward_init_state || return 1
  empty="$(mktemp_file .forward-empty)" || return 1
  jq '.rules=[]' "$NOBRAND_FORWARD_STATE_FILE" >"$empty" \
    && forward_transaction_commit "$empty" uninstall '' '' || { rm -f "$empty"; return 1; }
  rm -f "$empty"
  forward_realm_service_action stop >/dev/null 2>&1 || true
  service_path="$(forward_realm_service_path 2>/dev/null || true)"
  if [ -n "$service_path" ] && forward_realm_service_path_owned "$service_path"; then
    case "$(nb_service_manager)" in
    systemd)
      systemctl disable "$NOBRAND_REALM_SERVICE_NAME" >/dev/null 2>&1 || true
      rm -f "$NOBRAND_REALM_SYSTEMD_SERVICE"
      systemctl daemon-reload >/dev/null 2>&1 || true
      ;;
    openrc)
      rc-update del "$NOBRAND_REALM_SERVICE_NAME" default >/dev/null 2>&1 || true
      rm -f "$NOBRAND_REALM_OPENRC_SERVICE"
      ;;
    esac
  fi
  if forward_realm_runtime_metadata_valid; then
    rm -f "$NOBRAND_REALM_BIN" "$NOBRAND_REALM_RUNTIME_META"
  fi
  forward_remove_owned_nft_table || return 1
  rm -f "$NOBRAND_FORWARD_REALM_CONFIG" "$NOBRAND_FORWARD_NFT_RULESET" "$NOBRAND_FORWARD_STATE_FILE"
  msg 'Port Forward uninstalled; external nftables tables and external Realm installations were preserved.'
}

forward_usage() {
  cat <<'EOF'
Port Forward:
  nobrand forward add --name NAME --backend nftables|realm --protocol TCP|UDP|BOTH \
    --listen 0.0.0.0 --port PORT --target HOST --target-port PORT
  nobrand forward list
  nobrand forward show|delete|modify|enable|disable RULE
  nobrand forward set-endpoint RULE --advertise-host HOST --advertise-port PORT
  nobrand forward switch-backend RULE --backend nftables|realm [--target IPv4]
  nobrand forward doctor
  nobrand forward export [FILE]
  nobrand forward import FILE

nftables targets are IPv4 literals. Realm targets may be IPv4, IPv6, or domains.
The local IPv4 tail base xx00 is reserved for every backend and transport.
EOF
}

nobrand_run_forward_action() {
  local lock_required=0 rc
  case "$FORWARD_ACTION" in
    add|delete|modify|enable|disable|set-endpoint|switch-backend|import|upgrade-runtime|uninstall)
      lock_required=1
      require_root || return 1
      nb_init_state_layout || return 1
      ensure_management_dependencies "$(detect_pkg_manager)" || return 1
      admin_lock_acquire || return 1
      ;;
  esac
  nobrand_run_forward_action_unlocked
  rc=$?
  [ "$lock_required" -eq 0 ] || admin_lock_release
  return "$rc"
}

nobrand_run_forward_action_unlocked() {
  case "$FORWARD_ACTION" in
    menu) forward_menu_loop ;;
    add) forward_add_rule ;;
    delete) [ -n "$FORWARD_RULE_ID" ] || die 'forward delete 需要 RULE'; forward_delete_rule ;;
    modify) [ -n "$FORWARD_RULE_ID" ] || die 'forward modify 需要 RULE'; forward_modify_rule ;;
    list) forward_list_rules ;;
    show) [ -n "$FORWARD_RULE_ID" ] || die 'forward show 需要 RULE'; forward_show_rule ;;
    enable) [ -n "$FORWARD_RULE_ID" ] || die 'forward enable 需要 RULE'; forward_set_enabled true ;;
    disable) [ -n "$FORWARD_RULE_ID" ] || die 'forward disable 需要 RULE'; forward_set_enabled false ;;
    set-endpoint)
      [ -n "$FORWARD_RULE_ID" ] || die 'forward set-endpoint 需要 RULE'
      if [ "$ADVERTISE_AUTO_REQUESTED" -eq 1 ]; then
        forward_set_endpoint_state "$FORWARD_RULE_ID" auto '' ''
      else
        [ "$ADVERTISE_CLI" -eq 1 ] || die 'set-endpoint 需要 --advertise-host/--advertise-port 或 --advertise-auto'
        forward_set_endpoint_state "$FORWARD_RULE_ID" custom "$ADVERTISE_HOST" "$ADVERTISE_PORT"
      fi
      ;;
    switch-backend) [ -n "$FORWARD_RULE_ID" ] || die 'switch-backend 需要 RULE'; forward_switch_backend ;;
    doctor) forward_doctor ;;
    export) forward_export_json "$FORWARD_EXPORT_FILE" ;;
    import) forward_import_apply ;;
    upgrade-runtime) forward_realm_install_runtime stable ;;
    uninstall) forward_uninstall ;;
    help) forward_usage ;;
    *) die "未知 Port Forward 操作: $FORWARD_ACTION" ;;
  esac
}
