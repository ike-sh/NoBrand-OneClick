#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd -P)/testlib.sh"

for dependency in ip nft jq python3 sysctl nsenter curl tar sha256sum; do
  command -v "$dependency" >/dev/null 2>&1 || {
    printf '[SKIP] Forward backend-switch runtime dependency missing: %s\n' "$dependency"
    exit 0
  }
done
[ "$(id -u)" -eq 0 ] || { printf '[SKIP] Forward backend-switch runtime requires root\n'; exit 0; }
nft list ruleset >/dev/null 2>&1 \
  || { printf '[SKIP] Forward backend-switch runtime requires CAP_NET_ADMIN\n'; exit 0; }

fixture="$(mktemp -d)"
suffix="${RANDOM}$$"
client_ns="nbsc${suffix:0:8}"
forward_ns="nbsf${suffix:0:8}"
target_ns="nbst${suffix:0:8}"
server_pid=""
cleanup() {
  local rc=$?
  [ -z "$server_pid" ] || kill "$server_pid" 2>/dev/null || true
  wait "$server_pid" 2>/dev/null || true
  ip netns del "$client_ns" 2>/dev/null || true
  ip netns del "$forward_ns" 2>/dev/null || true
  ip netns del "$target_ns" 2>/dev/null || true
  rm -rf -- "$fixture"
  return "$rc"
}
trap cleanup EXIT

# Download and verify the official runtime while the container still has its
# ordinary network namespace. The isolated forwarding namespace intentionally
# has no internet route and receives only this verified NoBrand-owned binary.
export NOBRAND_STATE_DIR="$fixture/state"
export NOBRAND_CONFIG_DIR="$fixture/config"
export NOBRAND_LIB_DIR="$fixture/lib"
export NOBRAND_BIN_DIR="$fixture/lib/bin"
export NOBRAND_FORWARD_STATE_DIR="$fixture/state/forward"
export NOBRAND_FORWARD_STATE_FILE="$fixture/state/forward/state.json"
export NOBRAND_FORWARD_REALM_CONFIG="$fixture/config/forward/realm.toml"
export NOBRAND_FORWARD_NFT_RULESET="$fixture/config/forward/nftables.nft"
export NOBRAND_FORWARD_SYSCTL_STATE="$fixture/state/forward/sysctl.json"
export NOBRAND_FORWARD_SYSCTL_FRAGMENT="$fixture/sysctl.d/90-nobrand-forward.conf"
export NOBRAND_REALM_BIN="$fixture/lib/bin/realm"
export NOBRAND_REALM_RUNTIME_META="$fixture/state/forward/realm-runtime.json"
export NOBRAND_REALM_SYSTEMD_SERVICE="$fixture/systemd/nobrand-realm.service"
export NOBRAND_REALM_OPENRC_SERVICE="$fixture/openrc/nobrand-realm"
export NOBRAND_TEST_LOCAL_IPV4=192.0.2.168
source_installer
nb_init_state_layout
forward_realm_install_runtime stable || fail 'official Realm runtime preparation for backend switch'

ip netns add "$client_ns"
ip netns add "$forward_ns"
ip netns add "$target_ns"
ip link add "c${suffix:0:8}" type veth peer name "f${suffix:0:8}"
ip link add "t${suffix:0:8}" type veth peer name "g${suffix:0:8}"
ip link set "c${suffix:0:8}" netns "$client_ns"
ip link set "f${suffix:0:8}" netns "$forward_ns"
ip link set "t${suffix:0:8}" netns "$target_ns"
ip link set "g${suffix:0:8}" netns "$forward_ns"

ip -n "$client_ns" link set lo up
ip -n "$client_ns" addr add 10.30.0.2/24 dev "c${suffix:0:8}"
ip -n "$client_ns" link set "c${suffix:0:8}" up
ip -n "$client_ns" route add default via 10.30.0.1

ip -n "$forward_ns" link set lo up
ip -n "$forward_ns" addr add 10.30.0.1/24 dev "f${suffix:0:8}"
ip -n "$forward_ns" addr add 10.40.0.1/24 dev "g${suffix:0:8}"
ip -n "$forward_ns" link set "f${suffix:0:8}" up
ip -n "$forward_ns" link set "g${suffix:0:8}" up

ip -n "$target_ns" link set lo up
ip -n "$target_ns" addr add 10.40.0.2/24 dev "t${suffix:0:8}"
ip -n "$target_ns" link set "t${suffix:0:8}" up
ip -n "$target_ns" route add default via 10.40.0.1

cat >"$fixture/echo.py" <<'PY'
import socket
import threading
import time

PORT = 31001

def tcp_conn(conn, peer):
    with conn:
        data = conn.recv(65535)
        conn.sendall(peer[0].encode() + b"|" + data)

def tcp_server():
    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.bind(("10.40.0.2", PORT))
    sock.listen(32)
    while True:
        conn, peer = sock.accept()
        threading.Thread(target=tcp_conn, args=(conn, peer), daemon=True).start()

def udp_server():
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.bind(("10.40.0.2", PORT))
    while True:
        data, peer = sock.recvfrom(65535)
        sock.sendto(peer[0].encode() + b"|" + data, peer)

threading.Thread(target=tcp_server, daemon=True).start()
threading.Thread(target=udp_server, daemon=True).start()
while True:
    time.sleep(3600)
PY
ip netns exec "$target_ns" python3 "$fixture/echo.py" &
server_pid=$!

ip netns exec "$forward_ns" env \
  NOBRAND_SWITCH_FIXTURE="$fixture" NOBRAND_SWITCH_CLIENT_NS="$client_ns" \
  NOBRAND_SWITCH_INSTALLER="$TEST_ROOT/install-nobrand.sh" \
  NOBRAND_STATE_DIR="$fixture/state" NOBRAND_CONFIG_DIR="$fixture/config" \
  NOBRAND_LIB_DIR="$fixture/lib" NOBRAND_BIN_DIR="$fixture/lib/bin" \
  NOBRAND_FORWARD_STATE_DIR="$fixture/state/forward" \
  NOBRAND_FORWARD_STATE_FILE="$fixture/state/forward/state.json" \
  NOBRAND_FORWARD_REALM_CONFIG="$fixture/config/forward/realm.toml" \
  NOBRAND_FORWARD_NFT_RULESET="$fixture/config/forward/nftables.nft" \
  NOBRAND_FORWARD_SYSCTL_STATE="$fixture/state/forward/sysctl.json" \
  NOBRAND_FORWARD_SYSCTL_FRAGMENT="$fixture/sysctl.d/90-nobrand-forward.conf" \
  NOBRAND_REALM_BIN="$fixture/lib/bin/realm" \
  NOBRAND_REALM_RUNTIME_META="$fixture/state/forward/realm-runtime.json" \
  NOBRAND_REALM_SYSTEMD_SERVICE="$fixture/systemd/nobrand-realm.service" \
  NOBRAND_REALM_OPENRC_SERVICE="$fixture/openrc/nobrand-realm" \
  NOBRAND_TEST_LOCAL_IPV4=192.0.2.168 \
  bash -s <<'INNER'
set -euo pipefail
MITA_SOURCE_ONLY=1 source "$NOBRAND_SWITCH_INSTALLER"
trap - ERR

realm_pid_file="$NOBRAND_SWITCH_FIXTURE/realm.pid"
realm_log="$NOBRAND_SWITCH_FIXTURE/realm-switch.log"

nb_service_manager() { printf systemd; }
systemctl() { :; }
forward_firewall_reconcile() { :; }
forward_realm_install_service() {
  mkdir -p "$(dirname "$NOBRAND_REALM_SYSTEMD_SERVICE")"
  printf '# Owned by NoBrand-OneClick Port Forward\nExecStart=%s -c %s\n' \
    "$NOBRAND_REALM_BIN" "$NOBRAND_FORWARD_REALM_CONFIG" >"$NOBRAND_REALM_SYSTEMD_SERVICE"
}
forward_realm_service_pid() { [ -s "$realm_pid_file" ] && cat "$realm_pid_file"; }
forward_realm_service_active() {
  local pid
  pid="$(forward_realm_service_pid 2>/dev/null || true)"
  [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null
}
forward_realm_service_action() {
  local action="$1" pid
  pid="$(forward_realm_service_pid 2>/dev/null || true)"
  case "$action" in
    stop)
      if [[ "$pid" =~ ^[0-9]+$ ]]; then
        kill "$pid" 2>/dev/null || true
        wait "$pid" 2>/dev/null || true
      fi
      rm -f "$realm_pid_file"
      ;;
    restart|start)
      forward_realm_service_action stop
      "$NOBRAND_REALM_BIN" -c "$NOBRAND_FORWARD_REALM_CONFIG" >"$realm_log" 2>&1 &
      printf '%s\n' "$!" >"$realm_pid_file"
      ;;
    *) return 1 ;;
  esac
}

client_check() {
  local label="$1"
  nsenter --net="/var/run/netns/$NOBRAND_SWITCH_CLIENT_NS" \
    python3 - 33001 "$label" <<'PY'
import socket
import sys
import time

port = int(sys.argv[1])
payload = sys.argv[2].encode()
deadline = time.time() + 10

def tcp():
    while time.time() < deadline:
        try:
            with socket.create_connection(("10.30.0.1", port), timeout=.5) as sock:
                sock.sendall(payload)
                return sock.recv(65535).endswith(b"|" + payload)
        except OSError:
            time.sleep(.1)
    return False

def udp():
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.settimeout(.5)
    while time.time() < deadline:
        try:
            sock.sendto(payload, ("10.30.0.1", port))
            data, _ = sock.recvfrom(65535)
            return data.endswith(b"|" + payload)
        except OSError:
            time.sleep(.1)
    return False

raise SystemExit(0 if tcp() and udp() else 1)
PY
}

cleanup_inner() {
  forward_realm_service_action stop >/dev/null 2>&1 || true
}
trap cleanup_inner EXIT

nb_init_state_layout
cat >"$NOBRAND_FORWARD_STATE_FILE" <<'JSON'
{"schema_version":3,"ownership":"nobrand-v3","feature":"port-forward","rules":[
 {"rule_id":"f1111111111111111","name":"runtime-switch","note":"","backend":"nftables","enabled":true,
  "protocol":"both","listen_host":"10.30.0.1","listen_port":33001,
  "target_host":"10.40.0.2","target_port":31001,"display_host":"","display_port":33001,
  "display_mode":"auto","created_at":"2026-08-30T00:00:00Z","updated_at":"2026-08-30T00:00:00Z",
  "ownership_metadata":{"managed_listener":true,"managed_firewall":true},
  "backend_options":{"source_mode":"masquerade"}}
]}
JSON
forward_state_valid "$NOBRAND_FORWARD_STATE_FILE"
forward_apply_nft_state "$NOBRAND_FORWARD_STATE_FILE"
client_check nft-before

realm_candidate="$NOBRAND_SWITCH_FIXTURE/to-realm.json"
jq '(.rules[0].backend)="realm" | (.rules[0].backend_options)={
      through:"",interface:"",listen_interface:"",tcp_timeout:5,udp_timeout:30,
      proxy_send:false,proxy_accept:false,proxy_version:2,proxy_accept_timeout:5,
      dns_mode:"system",dns_protocol:"tcp_and_udp",dns_nameservers:[],
      listen_transport:"",remote_transport:"",extra_targets:[],balance:"off",weights:[]
    }' "$NOBRAND_FORWARD_STATE_FILE" >"$realm_candidate"
forward_transaction_commit "$realm_candidate" switch-backend nftables realm
[ "$(jq -r '.rules[0].backend' "$NOBRAND_FORWARD_STATE_FILE")" = realm ]
forward_realm_service_active
! nft list table ip nobrand_forward_v4 >/dev/null 2>&1
client_check realm-middle

nft_candidate="$NOBRAND_SWITCH_FIXTURE/to-nft.json"
jq '(.rules[0].backend)="nftables" | (.rules[0].backend_options)={source_mode:"masquerade"}' \
  "$NOBRAND_FORWARD_STATE_FILE" >"$nft_candidate"
forward_transaction_commit "$nft_candidate" switch-backend realm nftables
[ "$(jq -r '.rules[0].backend' "$NOBRAND_FORWARD_STATE_FILE")" = nftables ]
! forward_realm_service_active
forward_nft_table_owned
client_check nft-after

state_hash="$(sha256sum "$NOBRAND_FORWARD_STATE_FILE")"
bad_candidate="$NOBRAND_SWITCH_FIXTURE/bad-realm.json"
jq '(.rules[0].backend)="realm" | (.rules[0].listen_host)="192.0.2.250" |
    (.rules[0].backend_options)={through:"",interface:"",listen_interface:"",tcp_timeout:5,udp_timeout:30,
      proxy_send:false,proxy_accept:false,proxy_version:2,proxy_accept_timeout:5,
      dns_mode:"system",dns_protocol:"tcp_and_udp",dns_nameservers:[],
      listen_transport:"",remote_transport:"",extra_targets:[],balance:"off",weights:[]}' \
  "$NOBRAND_FORWARD_STATE_FILE" >"$bad_candidate"
if forward_transaction_commit "$bad_candidate" switch-backend nftables realm; then
  printf '[FAIL] invalid Realm candidate unexpectedly replaced nftables backend\n' >&2
  exit 1
fi
[ "$state_hash" = "$(sha256sum "$NOBRAND_FORWARD_STATE_FILE")" ]
forward_nft_table_owned
client_check nft-rollback

printf '[PASS] real nftables -> Realm -> nftables switch and candidate rollback\n'
INNER

pass 'Forward real backend-switch transaction data plane'
