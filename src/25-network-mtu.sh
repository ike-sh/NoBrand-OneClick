normalize_uint() {
  local value="${1:-}"
  [[ "$value" =~ ^[0-9]+$ ]] || return 1
  while [ "${#value}" -gt 1 ] && [ "${value#0}" != "$value" ]; do
    value="${value#0}"
  done
  printf '%s' "$value"
}

# 取本机主用 IPv4：优先默认路由出口地址（ip route get 不发包，仅查路由表，
# 内网无外网也可用），回退首个非回环地址。
valid_port() {
  local p
  p="$(normalize_uint "${1:-}")" || return 1
  [ "${#p}" -le 5 ] && [ "$p" -ge 1025 ] && [ "$p" -le 65535 ]
}

valid_advertise_port() {
  local p
  p="$(normalize_uint "${1:-}")" || return 1
  [ "${#p}" -le 5 ] && [ "$p" -ge 1 ] && [ "$p" -le 65535 ]
}

valid_mtu() {
  local value
  value="$(normalize_uint "${1:-}")" || return 1
  [ "${#value}" -le 4 ] && [ "$value" -ge 1280 ] && [ "$value" -le 1500 ]
}

mtu_default_iface() {
  local dev=""
  if command -v ip >/dev/null 2>&1; then
    dev="$(ip -o route show default 2>/dev/null \
      | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')"
    [ -n "$dev" ] || dev="$(ip -o -6 route show default 2>/dev/null \
      | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')"
    [ -n "$dev" ] || dev="$(ip -br link 2>/dev/null \
      | awk '$1!="lo"{print $1; exit}' | cut -d@ -f1)"
  fi
  if [ -z "$dev" ] && [ -r /proc/net/route ]; then
    dev="$(awk '$2=="00000000"{print $1; exit}' /proc/net/route 2>/dev/null)"
  fi
  printf '%s' "$dev"
}
