# ---------- NoBrand Common Core: transport-aware 端口注册表与分配 ----------

nb_normalize_transport() {
  case "$(printf '%s' "${1:-}" | tr '[:lower:]' '[:upper:]')" in
    TCP) printf 'TCP' ;;
    UDP) printf 'UDP' ;;
    *) return 1 ;;
  esac
}

# 手工端口允许 1-65535；自动分配始终从 1025 起。Mieru 自身仍通过
# valid_port 保持原有 1025 下限。
nb_valid_port() {
  local port
  port="$(normalize_uint "${1:-}")" || return 1
  [ "${#port}" -le 5 ] && [ "$port" -ge 1 ] && [ "$port" -le 65535 ]
}

# 默认路由出口优先，避免 Docker bridge/第二网卡抢占端口尾号语义。
nb_detect_local_ipv4() {
  local candidate=""
  if [ -n "${NOBRAND_TEST_LOCAL_IPV4:-}" ]; then
    printf '%s' "$NOBRAND_TEST_LOCAL_IPV4"
    return 0
  fi
  if command -v ip >/dev/null 2>&1; then
    candidate="$(ip -4 route get 1.1.1.1 2>/dev/null \
      | awk '{for(i=1;i<=NF;i++) if($i=="src"){print $(i+1); exit}}')" || true
  fi
  if [ -z "$candidate" ] && command -v ip >/dev/null 2>&1; then
    candidate="$(ip -o -4 route show default 2>/dev/null \
      | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}' \
      | while IFS= read -r iface; do
          [ -n "$iface" ] || continue
          ip -o -4 addr show dev "$iface" scope global 2>/dev/null \
            | awk '{split($4,a,"/"); print a[1]; exit}'
          break
        done)" || true
  fi
  if [ -z "$candidate" ]; then
    candidate="$(hostname -I 2>/dev/null | tr ' ' '\n' \
      | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' \
      | grep -vE '^(127|169\.254)\.' | head -n1)" || true
  fi
  case "$candidate" in
    *.*.*.*) printf '%s' "$candidate" ;;
    *) return 1 ;;
  esac
}

nb_port_base_for_ip() {
  local ip="${1:-}" octet base
  octet="${ip##*.}"
  [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
  [[ "$octet" =~ ^[0-9]+$ ]] || return 1
  [ "$octet" -ge 1 ] && [ "$octet" -le 254 ] || return 1
  base=$((10#$octet * 100))
  [ "$base" -ge 1025 ] && [ "$((base + 99))" -le 65535 ] || return 1
  printf '%s' "$base"
}

nb_tail_port_bounds() {
  local ip="${1:-}" base
  [ -n "$ip" ] || ip="$(nb_detect_local_ipv4)" || return 1
  base="$(nb_port_base_for_ip "$ip")" || return 1
  printf '%s|%s' "$((base + 1))" "$((base + 99))"
}

# 尾号算法只把 base+1..base+99 分配给代理。base（xx00）保留给
# 外部 NAT、SSH 或实验室入口等带外设施；这些占用在 guest 内通常不可见。
# 规则由本机默认路由 IPv4 推导，不包含任何环境专用 IP 或端口常量。
nb_tail_base_reservation_owner() {
  local port ip base
  port="$(normalize_uint "${1:-}")" || return 1
  ip="$(nb_detect_local_ipv4 2>/dev/null || true)"
  [ -n "$ip" ] || return 1
  base="$(nb_port_base_for_ip "$ip" 2>/dev/null || true)"
  [ -n "$base" ] && [ "$port" -eq "$base" ] || return 1
  printf 'common:tail-base:%s' "$ip"
}

nb_port_is_tail_base_reserved() {
  nb_tail_base_reservation_owner "$1" >/dev/null 2>&1
}

# 随机起点 + 环形遍历。check_fn 成功表示端口可用。
nb_scan_port_span() {
  local lo="$1" hi="$2" check_fn="$3"
  shift 3
  local span start index offset port
  [ "$lo" -le "$hi" ] || return 1
  span=$((hi - lo + 1))
  if [ -n "${NOBRAND_TEST_RANDOM_START:-}" ]; then
    start=$((NOBRAND_TEST_RANDOM_START % span))
  else
    start=$((RANDOM % span))
  fi
  index=0
  while [ "$index" -lt "$span" ]; do
    offset=$(((start + index) % span))
    port=$((lo + offset))
    if "$check_fn" "$port" "$@"; then
      printf '%s' "$port"
      return 0
    fi
    index=$((index + 1))
  done
  return 1
}

nb_port_bind_probe_in_use() {
  local transport port
  transport="$(nb_normalize_transport "$1")" || return 2
  port="$(normalize_uint "$2")" || return 2
  command -v python3 >/dev/null 2>&1 || return 2
  python3 - "$transport" "$port" <<'PY'
import errno
import socket
import sys

transport, raw_port = sys.argv[1:3]
port = int(raw_port)
sock_type = socket.SOCK_STREAM if transport == "TCP" else socket.SOCK_DGRAM
attempted = False
for family, address in ((socket.AF_INET6, "::"), (socket.AF_INET, "0.0.0.0")):
    try:
        sock = socket.socket(family, sock_type)
    except OSError:
        continue
    attempted = True
    try:
        if family == socket.AF_INET6:
            try:
                sock.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 0)
            except OSError:
                pass
        sock.bind((address, port))
    except OSError as exc:
        sock.close()
        if exc.errno in (errno.EADDRINUSE, errno.EACCES):
            raise SystemExit(0)
        continue
    sock.close()
raise SystemExit(1 if attempted else 2)
PY
}

# 成功表示该 transport 的端口已有 listener。
nb_port_is_listening() {
  local transport port flags
  transport="$(nb_normalize_transport "$1")" || return 1
  port="$(normalize_uint "$2")" || return 1
  if command -v ss >/dev/null 2>&1; then
    [ "$transport" = TCP ] && flags='-Hlnt' || flags='-Hlnu'
    ss "$flags" 2>/dev/null | awk -v port="$port" '
      { for (i=1; i<=NF; i++) if ($i ~ (":" port "$")) { found=1; exit } }
      END { exit(found ? 0 : 1) }
    '
    return $?
  fi
  if command -v netstat >/dev/null 2>&1; then
    [ "$transport" = TCP ] && flags='-lnt' || flags='-lnu'
    netstat "$flags" 2>/dev/null | awk -v port="$port" '
      { for (i=1; i<=NF; i++) if ($i ~ (":" port "$")) { found=1; exit } }
      END { exit(found ? 0 : 1) }
    '
    return $?
  fi
  nb_port_bind_probe_in_use "$transport" "$port"
}

nb_port_listener_details() {
  local transport port flags
  transport="$(nb_normalize_transport "$1")" || return 0
  port="$(normalize_uint "$2")" || return 0
  if command -v ss >/dev/null 2>&1; then
    [ "$transport" = TCP ] && flags='-Hlntp' || flags='-Hlnup'
    ss "$flags" 2>/dev/null | awk -v port="$port" '
      { for (i=1; i<=NF; i++) if ($i ~ (":" port "$")) { print; break } }
    '
  elif command -v netstat >/dev/null 2>&1; then
    [ "$transport" = TCP ] && flags='-lntp' || flags='-lnup'
    netstat "$flags" 2>/dev/null | awk -v port="$port" '
      { for (i=1; i<=NF; i++) if ($i ~ (":" port "$")) { print; break } }
    '
  fi
}

# Return the socket-owner PIDs reported by ss/netstat. Doctor runs as root on
# supported deployments, so ss normally exposes pid=NNN; the netstat form is
# retained for compatibility. An empty result means ownership was not visible.
nb_port_listener_pids() {
  local details
  details="$(nb_port_listener_details "$1" "$2" 2>/dev/null || true)"
  [ -n "$details" ] || return 0
  printf '%s\n' "$details" \
    | sed -nE \
      -e 's/.*pid=([0-9]+).*/\1/p' \
      -e 's/.*[[:space:]]([0-9]+)\/[^[:space:]]+[[:space:]]*$/\1/p' \
    | LC_ALL=C sort -u
}

# 输出 owner|transport|port|advertise_host|advertise_port。Mieru only reads
# schema-v3 users.json under the authoritative NoBrand state root.
nb_registry_rows() {
  command -v python3 >/dev/null 2>&1 || return 0
  NOBRAND_SNELL_STATE_DIR="$NOBRAND_SNELL_STATE_DIR" \
  NOBRAND_HY2_STATE_FILE="$NOBRAND_HY2_STATE_FILE" \
  NOBRAND_VLESS_STATE_FILE="$NOBRAND_VLESS_STATE_FILE" \
  NOBRAND_TUIC_STATE_DIR="$NOBRAND_TUIC_STATE_DIR" \
  NOBRAND_FORWARD_STATE_FILE="$NOBRAND_FORWARD_STATE_FILE" \
  MITA_USERS_STATE="$MITA_USERS_STATE" \
  python3 - <<'PY'
import glob
import json
import os
import shlex

def emit(owner, transport, port, host="", advertise_port=""):
    try:
        port = int(port)
    except Exception:
        return
    print("%s|%s|%s|%s|%s" % (owner, transport.upper(), port, host or "", advertise_port or ""))

snell_dir = os.environ.get("NOBRAND_SNELL_STATE_DIR", "")
for path in sorted(glob.glob(os.path.join(snell_dir, "*.json"))):
    try:
        state = json.load(open(path, encoding="utf-8"))
        file_id = os.path.basename(path)[:-5]
        instance_id = str(state.get("instance_id") or "")
        version = state.get("version")
        if state.get("protocol") != "snell" or instance_id != file_id or version not in (4, 5):
            continue
        owner = "snell:" + instance_id
        emit(owner, "TCP", state.get("listen_port"), state.get("advertise_host"), state.get("advertise_port"))
        if version == 5 and state.get("managed_udp") is True:
            emit(owner, "UDP", state.get("listen_port"), state.get("advertise_host"), state.get("advertise_port"))
    except Exception:
        continue

hy2_path = os.environ.get("NOBRAND_HY2_STATE_FILE", "")
if hy2_path and os.path.isfile(hy2_path):
    try:
        state = json.load(open(hy2_path, encoding="utf-8"))
        emit("hy2:default", "UDP", state.get("listen_port"), state.get("advertise_host"), state.get("advertise_port"))
    except Exception:
        pass

vless_path = os.environ.get("NOBRAND_VLESS_STATE_FILE", "")
if vless_path and os.path.isfile(vless_path):
    try:
        state = json.load(open(vless_path, encoding="utf-8"))
        emit("vless-sudoku:default", "TCP", state.get("listen_port"),
             state.get("advertise_host"), state.get("advertise_port"))
    except Exception:
        pass

tuic_dir = os.environ.get("NOBRAND_TUIC_STATE_DIR", "")
for path in sorted(glob.glob(os.path.join(tuic_dir, "*", "state.json"))):
    try:
        state = json.load(open(path, encoding="utf-8"))
        instance_id = str(state.get("instance_id") or "")
        if (state.get("schema_version") != 3 or state.get("ownership") != "nobrand-v3"
                or state.get("protocol") != "tuic" or state.get("tuic_version") != 5
                or os.path.basename(os.path.dirname(path)) != instance_id):
            continue
        emit("tuic:" + instance_id, "UDP", state.get("listen_port"),
             state.get("advertise_host"), state.get("advertise_port"))
    except Exception:
        pass

forward_path = os.environ.get("NOBRAND_FORWARD_STATE_FILE", "")
if forward_path and os.path.isfile(forward_path):
    try:
        state = json.load(open(forward_path, encoding="utf-8"))
        if (state.get("schema_version") == 3 and state.get("ownership") == "nobrand-v3"
                and state.get("feature") == "port-forward"):
            for rule in sorted(state.get("rules") or [], key=lambda item: str(item.get("rule_id") or "")):
                rule_id = str(rule.get("rule_id") or "")
                protocol = str(rule.get("protocol") or "").lower()
                owner = "forward:" + rule_id
                if protocol in ("tcp", "both"):
                    emit(owner, "TCP", rule.get("listen_port"), rule.get("display_host"),
                         rule.get("display_port"))
                if protocol in ("udp", "both"):
                    emit(owner, "UDP", rule.get("listen_port"), rule.get("display_host"),
                         rule.get("display_port"))
    except Exception:
        pass

mita_users = os.environ.get("MITA_USERS_STATE", "")
if mita_users and os.path.isfile(mita_users):
    try:
        state = json.load(open(mita_users, encoding="utf-8"))
        protocol = str(state.get("protocol") or "TCP").upper()
        for user in state.get("users") or []:
            port = int(user.get("port"))
            owner = "mieru:" + str(user.get("instance_id") or user.get("name") or port)
            if protocol == "BOTH":
                emit(owner, "TCP", port, user.get("advertise_host"), user.get("advertise_port"))
                advertised = int(user.get("advertise_port") or port)
                emit(owner, "UDP", port + 1, user.get("advertise_host"), advertised + 1)
            else:
                emit(owner, protocol, port, user.get("advertise_host"), user.get("advertise_port"))
    except Exception:
        pass
PY
}

nb_registry_port_owner() {
  local transport port ignore_owner="${3:-}" owner row_transport row_port _rest
  transport="$(nb_normalize_transport "$1")" || return 1
  port="$(normalize_uint "$2")" || return 1
  while IFS='|' read -r owner row_transport row_port _rest; do
    [ -n "$owner" ] || continue
    [ "$owner" = "$ignore_owner" ] && continue
    if [ "$row_transport" = "$transport" ] && [ "$row_port" = "$port" ]; then
      printf '%s' "$owner"
      return 0
    fi
  done < <(nb_registry_rows)
  return 1
}

nb_port_available_for_transport() {
  local port="$1" transport="$2" ignore_owner="${3:-}"
  nb_valid_port "$port" || return 1
  transport="$(nb_normalize_transport "$transport")" || return 1
  nb_port_is_tail_base_reserved "$port" && return 1
  nb_registry_port_owner "$transport" "$port" "$ignore_owner" >/dev/null 2>&1 && return 1
  nb_port_is_listening "$transport" "$port" && return 1
  return 0
}

nb_select_available_port() {
  local transport ip bounds lo hi selected attempt random_value
  transport="$(nb_normalize_transport "$1")" || return 1
  ip="$(nb_detect_local_ipv4 2>/dev/null || true)"
  if bounds="$(nb_tail_port_bounds "$ip" 2>/dev/null)"; then
    lo="${bounds%%|*}"
    hi="${bounds#*|}"
    if selected="$(nb_scan_port_span "$lo" "$hi" nb_port_available_for_transport "$transport")"; then
      printf '%s' "$selected"
      return 0
    fi
  fi
  attempt=0
  while [ "$attempt" -lt 512 ]; do
    if command -v openssl >/dev/null 2>&1; then
      random_value="$(openssl rand -hex 2 2>/dev/null || true)"
      if [[ "$random_value" =~ ^[0-9a-fA-F]{4}$ ]]; then
        selected=$((1025 + 16#$random_value % (65535 - 1025 + 1)))
      else
        selected=$((1025 + RANDOM % (65535 - 1025 + 1)))
      fi
    else
      selected=$((1025 + RANDOM % (65535 - 1025 + 1)))
    fi
    if nb_port_available_for_transport "$selected" "$transport"; then
      printf '%s' "$selected"
      return 0
    fi
    attempt=$((attempt + 1))
  done
  return 1
}

nb_warn_if_outside_recommended_range() {
  local port="$1" ip bounds lo hi
  ip="$(nb_detect_local_ipv4 2>/dev/null || true)"
  bounds="$(nb_tail_port_bounds "$ip" 2>/dev/null || true)"
  [ -n "$bounds" ] || return 0
  lo="${bounds%%|*}"
  hi="${bounds#*|}"
  if nb_port_is_tail_base_reserved "$port"; then
    warn "$(t "指定端口 ${port} 是本机尾号段的保留基准端口，不允许代理绑定" \
      "Port ${port} is the reserved base of this host's tail-port range and cannot be used by a proxy")"
    return 0
  fi
  if [ "$port" -lt "$lo" ] || [ "$port" -gt "$hi" ]; then
    warn "$(t "指定端口 ${port} 不在本机 ${ip} 的推荐段 ${lo}-${hi}；确认空闲后仍允许使用" \
      "Port ${port} is outside the recommended ${lo}-${hi} range for ${ip}; it is still allowed when free")"
  fi
}

nb_describe_port_conflict() {
  local transport="$1" port="$2" owner reservation details
  reservation="$(nb_tail_base_reservation_owner "$port" 2>/dev/null || true)"
  [ -z "$reservation" ] || msg "  reserved owner: ${reservation} (tail-port base; external NAT/SSH ownership may be invisible inside the guest)"
  owner="$(nb_registry_port_owner "$transport" "$port" 2>/dev/null || true)"
  [ -z "$owner" ] || msg "  state owner: ${owner}"
  details="$(nb_port_listener_details "$transport" "$port" 2>/dev/null || true)"
  [ -z "$details" ] || printf '%s\n' "$details" | sed 's/^/  listener: /'
}
