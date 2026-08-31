#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd -P)/testlib.sh"

for dependency in ip nft jq python3 sysctl; do
  command -v "$dependency" >/dev/null 2>&1 || {
    printf '[SKIP] nftables namespace runtime dependency missing: %s\n' "$dependency"
    exit 0
  }
done
[ "$(id -u)" -eq 0 ] || { printf '[SKIP] nftables namespace runtime requires root\n'; exit 0; }
nft list ruleset >/dev/null 2>&1 \
  || { printf '[SKIP] nftables namespace runtime requires CAP_NET_ADMIN\n'; exit 0; }

fixture="$(mktemp -d)"
suffix="${RANDOM}$$"
client_ns="nbfc${suffix}"
forward_ns="nbff${suffix}"
target_ns="nbft${suffix}"
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
export NOBRAND_TEST_LOCAL_IPV4=192.0.2.168

source_installer
nb_init_state_layout
forward_init_state

ip netns add "$client_ns"
ip netns add "$forward_ns"
ip netns add "$target_ns"
ip link add "c${suffix}" type veth peer name "f${suffix}"
ip link add "t${suffix}" type veth peer name "g${suffix}"
ip link set "c${suffix}" netns "$client_ns"
ip link set "f${suffix}" netns "$forward_ns"
ip link set "t${suffix}" netns "$target_ns"
ip link set "g${suffix}" netns "$forward_ns"

ip -n "$client_ns" link set lo up
ip -n "$client_ns" addr add 10.10.0.2/24 dev "c${suffix}"
ip -n "$client_ns" link set "c${suffix}" up
ip -n "$client_ns" route add default via 10.10.0.1

ip -n "$forward_ns" link set lo up
ip -n "$forward_ns" addr add 10.10.0.1/24 dev "f${suffix}"
ip -n "$forward_ns" addr add 10.20.0.1/24 dev "g${suffix}"
ip -n "$forward_ns" link set "f${suffix}" up
ip -n "$forward_ns" link set "g${suffix}" up
ip netns exec "$forward_ns" sysctl -q -w net.ipv4.ip_forward=1

ip -n "$target_ns" link set lo up
ip -n "$target_ns" addr add 10.20.0.2/24 dev "t${suffix}"
ip -n "$target_ns" link set "t${suffix}" up
ip -n "$target_ns" route add default via 10.20.0.1

cat >"$fixture/echo-peer.py" <<'PY'
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
    sock.bind(("10.20.0.2", PORT))
    sock.listen(32)
    while True:
        conn, peer = sock.accept()
        threading.Thread(target=tcp_conn, args=(conn, peer), daemon=True).start()

def udp_server():
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.bind(("10.20.0.2", PORT))
    while True:
        data, peer = sock.recvfrom(65535)
        sock.sendto(peer[0].encode() + b"|" + data, peer)

threading.Thread(target=tcp_server, daemon=True).start()
threading.Thread(target=udp_server, daemon=True).start()
while True:
    time.sleep(3600)
PY
ip netns exec "$target_ns" python3 "$fixture/echo-peer.py" &
server_pid=$!

cat >"$NOBRAND_FORWARD_STATE_FILE" <<'JSON'
{"schema_version":3,"ownership":"nobrand-v3","feature":"port-forward","rules":[
 {"rule_id":"f1111111111111111","name":"nft-both","note":"namespace runtime","backend":"nftables","enabled":true,
  "protocol":"both","listen_host":"10.10.0.1","listen_port":32001,"target_host":"10.20.0.2","target_port":31001,
  "display_host":"","display_port":32001,"display_mode":"auto","created_at":"2026-08-30T00:00:00Z","updated_at":"2026-08-30T00:00:00Z",
  "ownership_metadata":{"managed_listener":true,"managed_firewall":true},"backend_options":{"source_mode":"masquerade"}}
]}
JSON
chmod 0600 "$NOBRAND_FORWARD_STATE_FILE"
forward_generate_nft_ruleset "$NOBRAND_FORWARD_STATE_FILE" "$fixture/masquerade.nft"
ip netns exec "$forward_ns" nft add table ip external_fixture
ip netns exec "$forward_ns" nft -c -f "$fixture/masquerade.nft"
ip netns exec "$forward_ns" nft -f "$fixture/masquerade.nft"

forward_nft_client_check() {
  local listen_port="$1" expected_peer="$2" label="$3"
  ip netns exec "$client_ns" python3 - "$listen_port" "$expected_peer" "$label" <<'PY'
import socket
import sys
import time

port = int(sys.argv[1])
expected = sys.argv[2].encode() + b"|" + sys.argv[3].encode()
deadline = time.time() + 10

def tcp():
    while time.time() < deadline:
        try:
            with socket.create_connection(("10.10.0.1", port), timeout=.5) as sock:
                sock.sendall(sys.argv[3].encode())
                return sock.recv(65535) == expected
        except OSError:
            time.sleep(.1)
    return False

def udp():
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.settimeout(.5)
    while time.time() < deadline:
        try:
            sock.sendto(sys.argv[3].encode(), ("10.10.0.1", port))
            data, _ = sock.recvfrom(65535)
            return data == expected
        except OSError:
            time.sleep(.1)
    return False

raise SystemExit(0 if tcp() and udp() else 1)
PY
}

forward_nft_client_check 32001 10.20.0.1 nft-masquerade \
  || fail 'nftables MASQUERADE TCP/UDP data plane failed'

# Preserve Source requires an explicit return path on the target, exactly as
# the product warning states. Keep the MASQUERADE rule active against the same
# target host/port so this also proves one rule's SNAT cannot leak into another.
ip -n "$target_ns" route add 10.10.0.0/24 via 10.20.0.1
jq '.rules += [(.rules[0] |
      .rule_id="f2222222222222222" |
      .name="nft-preserve" |
      .listen_port=32002 |
      .display_port=32002 |
      .backend_options.source_mode="preserve")]' \
  "$NOBRAND_FORWARD_STATE_FILE" >"$fixture/preserve-state.json"
forward_generate_nft_ruleset "$fixture/preserve-state.json" "$fixture/preserve.nft"
grep -Fq 'meta l4proto tcp ct original ip daddr 10.10.0.1 ct original proto-dst 32001 ip daddr 10.20.0.2 tcp dport 31001 counter masquerade' \
  "$fixture/preserve.nft" \
  || fail 'MASQUERADE rule is not scoped to its original listen endpoint'
! grep -Fq 'nobrand:f2222222222222222:snat:' "$fixture/preserve.nft" \
  || fail 'Preserve Source rule unexpectedly generated SNAT'
{
  printf 'delete table ip nobrand_forward_v4\n'
  cat "$fixture/preserve.nft"
} >"$fixture/replace.nft"
ip netns exec "$forward_ns" nft -c -f "$fixture/replace.nft"
ip netns exec "$forward_ns" nft -f "$fixture/replace.nft"
forward_nft_client_check 32001 10.20.0.1 nft-masquerade-overlap \
  || fail 'overlapping MASQUERADE rule lost TCP/UDP data plane'
forward_nft_client_check 32002 10.10.0.2 nft-preserve \
  || fail 'nftables Preserve Source isolation from overlapping MASQUERADE failed'

ip netns exec "$forward_ns" nft list table ip external_fixture >/dev/null \
  || fail 'NoBrand nft apply damaged external fixture table'
ip netns exec "$forward_ns" nft delete table ip nobrand_forward_v4
ip netns exec "$forward_ns" nft list table ip external_fixture >/dev/null \
  || fail 'NoBrand nft uninstall damaged external fixture table'

pass 'nftables namespace TCP, UDP, BOTH, MASQUERADE, Preserve Source, atomic replace, and external-table preservation'
