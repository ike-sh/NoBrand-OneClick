firewall_owned_has() {
  local key="$1"
  [ -f "$MITA_FIREWALL_OWNED_STATE" ] \
    && grep -qxF "$key" "$MITA_FIREWALL_OWNED_STATE" 2>/dev/null
}

firewall_owned_add() {
  local key="$1"
  firewall_owned_has "$key" && return 0
  if [ "${DRY_RUN:-0}" -eq 1 ]; then
    t "[演练] 记录自有防火墙规则: $key" "[dry-run] own firewall rule: $key"
    return 0
  fi
  mkdir -p "$(dirname "$MITA_FIREWALL_OWNED_STATE")"
  printf '%s\n' "$key" >>"$MITA_FIREWALL_OWNED_STATE"
  chmod 0600 "$MITA_FIREWALL_OWNED_STATE" 2>/dev/null || true
}

firewall_owned_remove() {
  local key="$1" tmp
  [ -f "$MITA_FIREWALL_OWNED_STATE" ] || return 0
  if [ "${DRY_RUN:-0}" -eq 1 ]; then
    t "[演练] 释放自有防火墙规则: $key" "[dry-run] release firewall rule: $key"
    return 0
  fi
  tmp="${MITA_FIREWALL_OWNED_STATE}.new.$$"
  grep -vxF "$key" "$MITA_FIREWALL_OWNED_STATE" >"$tmp" 2>/dev/null || true
  if [ -s "$tmp" ]; then
    chmod 0600 "$tmp" 2>/dev/null || true
    mv -f "$tmp" "$MITA_FIREWALL_OWNED_STATE"
  else
    rm -f "$tmp" "$MITA_FIREWALL_OWNED_STATE"
  fi
}

iptables_remove_owned_rule() {
  local ipt="$1" proto="$2" p="$3" key
  key="${ipt}|${proto}|${p}"
  firewall_owned_has "$key" || return 0
  command -v "$ipt" >/dev/null 2>&1 || return 1
  if "$ipt" -C INPUT -p "$proto" --dport "$p" -m comment \
      --comment "$MITA_FIREWALL_COMMENT" -j ACCEPT 2>/dev/null; then
    run "$ipt" -D INPUT -p "$proto" --dport "$p" -m comment \
      --comment "$MITA_FIREWALL_COMMENT" -j ACCEPT 2>/dev/null || return 1
  fi
  if "$ipt" -C INPUT -p "$proto" --dport "$p" -m comment \
      --comment "$MITA_FIREWALL_COMMENT" -j ACCEPT 2>/dev/null; then
    return 1
  fi
  firewall_owned_remove "$key"
}

ufw_binding_exists() {
  local spec="$1"
  ufw show added 2>/dev/null | grep -Eq \
    "^ufw[[:space:]]+allow([[:space:]]+in)?[[:space:]]+${spec//./\\.}([[:space:]]|$)"
}

firewall_apply_binding() {
  local fw="$1" action="$2" proto="$3" p="$4" spec key
  spec="$(ufw_rule_spec "$p" "$proto")"
  case "${fw}:${action}" in
    ufw:add)
      key="ufw|${proto}|${p}"
      firewall_owned_has "$key" && return 0
      ufw_binding_exists "$spec" && return 0
      if run ufw allow "$spec"; then
        firewall_owned_add "$key"
      else
        return 1
      fi
      ;;
    ufw:del)
      key="ufw|${proto}|${p}"
      firewall_owned_has "$key" || return 0
      command -v ufw >/dev/null 2>&1 || return 0
      if run ufw --force delete allow "$spec" 2>/dev/null \
         || ! ufw_binding_exists "$spec"; then
        firewall_owned_remove "$key"
      fi
      ;;
    firewalld:add)
      key="firewalld|${proto}|${p}"
      firewall_owned_has "$key" && return 0
      firewall-cmd --permanent --query-port="${p}/${proto}" >/dev/null 2>&1 && return 0
      if run firewall-cmd --permanent --add-port="${p}/${proto}"; then
        firewall_owned_add "$key"
      else
        return 1
      fi
      ;;
    firewalld:del)
      key="firewalld|${proto}|${p}"
      firewall_owned_has "$key" || return 0
      command -v firewall-cmd >/dev/null 2>&1 || return 0
      if run firewall-cmd --permanent --remove-port="${p}/${proto}" 2>/dev/null \
         || ! firewall-cmd --permanent --query-port="${p}/${proto}" >/dev/null 2>&1; then
        firewall_owned_remove "$key"
      fi
      ;;
    iptables:add|iptables:del)
      iptables_accept_port "$p" "$proto" "$action"
      ;;
  esac
}

close_firewall_for_bindings() {
  local bindings="$1"
  local pp proto p proto_lc
  [ -n "$bindings" ] || return 0

  while IFS= read -r pp; do
    [ -n "$pp" ] || continue
    proto="${pp%%|*}"
    p="${pp#*|}"
    proto_lc="$(proto_lower "$proto")"
    firewall_apply_binding ufw del "$proto_lc" "$p"
    firewall_apply_binding firewalld del "$proto_lc" "$p"
    firewall_apply_binding iptables del "$proto_lc" "$p"
  done <<< "$bindings"

  command -v firewall-cmd >/dev/null 2>&1 \
    && run firewall-cmd --reload 2>/dev/null || true
  persist_iptables_rules
}

ufw_rule_spec() {
  local p="$1"
  local proto="$2"
  if [[ "$p" == *-* ]]; then
    local start="${p%-*}"
    local end="${p#*-}"
    printf '%s:%s/%s' "$start" "$end" "$proto"
  else
    printf '%s/%s' "$p" "$proto"
  fi
}

iptables_accept_port() {
  local p="$1"
  local proto="$2"
  local action="${3:-add}"
  local ipt key
  for ipt in iptables ip6tables; do
    command -v "$ipt" >/dev/null 2>&1 || continue
    if [[ "$p" == *-* ]]; then
      local start end port
      start="${p%-*}"
      end="${p#*-}"
      port="$start"
      while [ "$port" -le "$end" ]; do
        key="${ipt}|${proto}|${port}"
        if [ "$action" = add ]; then
          if "$ipt" -C INPUT -p "$proto" --dport "$port" -m comment \
              --comment "$MITA_FIREWALL_COMMENT" -j ACCEPT 2>/dev/null; then
            firewall_owned_add "$key"
          elif "$ipt" -C INPUT -p "$proto" --dport "$port" -j ACCEPT 2>/dev/null; then
            :
          elif run "$ipt" -I INPUT -p "$proto" --dport "$port" -m comment \
              --comment "$MITA_FIREWALL_COMMENT" -j ACCEPT; then
            firewall_owned_add "$key"
          fi
        elif firewall_owned_has "$key"; then
          iptables_remove_owned_rule "$ipt" "$proto" "$port" || return 1
        fi
        port=$((port + 1))
      done
    else
      key="${ipt}|${proto}|${p}"
      if [ "$action" = add ]; then
        if "$ipt" -C INPUT -p "$proto" --dport "$p" -m comment \
            --comment "$MITA_FIREWALL_COMMENT" -j ACCEPT 2>/dev/null; then
          firewall_owned_add "$key"
        elif "$ipt" -C INPUT -p "$proto" --dport "$p" -j ACCEPT 2>/dev/null; then
          :
        elif run "$ipt" -I INPUT -p "$proto" --dport "$p" -m comment \
            --comment "$MITA_FIREWALL_COMMENT" -j ACCEPT; then
          firewall_owned_add "$key"
        fi
      elif firewall_owned_has "$key"; then
        iptables_remove_owned_rule "$ipt" "$proto" "$p" || return 1
      fi
    fi
  done
}

persist_iptables_rules() {
  if [ -d /etc/iptables ] || [ -f /etc/alpine-release ]; then
    if [ "${DRY_RUN:-0}" -eq 1 ]; then
      t '[演练] 将运行 iptables-save > /etc/iptables/rules.v4' \
        '[dry-run] iptables-save > /etc/iptables/rules.v4'
      return 0
    fi
    local rules_tmp
    rules_tmp="$(mktemp_file .rules.v4)" || return 1
    run mkdir -p /etc/iptables
    if iptables-save >"$rules_tmp" 2>/dev/null; then
      install -m 0600 "$rules_tmp" /etc/iptables/rules.v4 2>/dev/null || true
    fi
    rm -f "$rules_tmp"
    if command -v ip6tables-save >/dev/null 2>&1; then
      rules_tmp="$(mktemp_file .rules.v6)" || return 1
      if ip6tables-save >"$rules_tmp" 2>/dev/null; then
        install -m 0600 "$rules_tmp" /etc/iptables/rules.v6 2>/dev/null || true
      fi
      rm -f "$rules_tmp"
    fi
  fi
}

valid_ip_literal() {
  local value="${1:-}" a b c d extra colons segment remainder
  local -a parts=()
  [ -n "$value" ] || return 1
  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import ipaddress,sys; ipaddress.ip_address(sys.argv[1])' "$value" 2>/dev/null
    return $?
  fi
  if [[ "$value" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    IFS=. read -r a b c d extra <<< "$value"
    [ -z "${extra:-}" ] || return 1
    for segment in "$a" "$b" "$c" "$d"; do
      [[ "$segment" =~ ^[0-9]{1,3}$ ]] && [ "$segment" -le 255 ] || return 1
    done
    return 0
  fi
  [[ "$value" == *:* ]] || return 1
  [[ "$value" =~ ^[0-9A-Fa-f:]+$ ]] || return 1
  [[ "$value" != *:::* ]] || return 1
  colons="${value//[^:]/}"
  [ "${#colons}" -ge 2 ] && [ "${#colons}" -le 7 ] || return 1
  if [[ "$value" == *::* ]]; then
    remainder="${value#*::}"
    [[ "$remainder" != *::* ]] || return 1
  else
    [ "${#colons}" -eq 7 ] || return 1
  fi
  IFS=: read -r -a parts <<< "$value"
  for segment in "${parts[@]}"; do
    [ "${#segment}" -le 4 ] || return 1
  done
  return 0
}

valid_domain_name() {
  local value="${1:-}" label rest
  [ -n "$value" ] && [ "${#value}" -le 253 ] || return 1
  [[ "$value" != *[[:space:]]* ]] || return 1
  [[ "$value" != *://* && "$value" != *:* && "$value" != /* ]] || return 1
  value="${value%.}"
  [ -n "$value" ] || return 1
  # A dotted decimal quad is an IPv4 candidate, not a DNS name. Reject it
  # here when valid_ip_literal has already rejected its octets.
  [[ ! "$value" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
  rest="$value"
  while true; do
    label="${rest%%.*}"
    [ -n "$label" ] && [ "${#label}" -le 63 ] || return 1
    [[ "$label" =~ ^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?$ ]] || return 1
    [ "$rest" != "$label" ] || break
    rest="${rest#*.}"
  done
}

valid_advertise_host() {
  valid_ip_literal "${1:-}" || valid_domain_name "${1:-}"
}

valid_public_ip_literal() {
  local value="${1:-}"
  valid_ip_literal "$value" || return 1
  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import ipaddress,sys; raise SystemExit(0 if ipaddress.ip_address(sys.argv[1]).is_global else 1)' \
      "$value" 2>/dev/null
    return $?
  fi
  case "$value" in
    10.*|127.*|169.254.*|192.168.*|172.1[6-9].*|172.2[0-9].*|172.3[01].*|\
    100.6[4-9].*|100.[7-9][0-9].*|100.1[01][0-9].*|100.12[0-7].*|\
    ::1|fe8*|fe9*|fea*|feb*|fc*|fd*) return 1 ;;
  esac
  return 0
}

public_ip() {
  local candidate=""
  candidate="$(curl -fsSL --connect-timeout 5 --max-time 10 https://checkip.amazonaws.com 2>/dev/null \
    | head -n1 | tr -d '[:space:]' || true)"
  if valid_public_ip_literal "$candidate"; then
    printf '%s' "$candidate"
    return 0
  fi
  candidate="$(curl -fsSL --connect-timeout 5 --max-time 10 https://api.ip.sb/ip 2>/dev/null \
    | head -n1 | tr -d '[:space:]' || true)"
  if valid_public_ip_literal "$candidate"; then
    printf '%s' "$candidate"
    return 0
  fi
  candidate="$(hostname -I 2>/dev/null | awk '{print $1}' | tr -d '[:space:]' || true)"
  valid_public_ip_literal "$candidate" || return 1
  printf '%s' "$candidate"
}
