#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/testlib.sh"

if [ "$(id -u)" -ne 0 ]; then
  printf '[SKIP] strict ingress runtime fixture requires root/CAP_NET_ADMIN\n'
  exit 0
fi
for dependency in ip nft python3; do
  if ! command -v "$dependency" >/dev/null 2>&1; then
    printf '[SKIP] strict ingress runtime fixture requires %s\n' "$dependency"
    exit 0
  fi
done

fixture="$(mktemp -d)"
suffix="$$"
server_ns="nbs${suffix}"
client_a_ns="nba${suffix}"
client_b_ns="nbb${suffix}"
server_a_if="nsa${suffix}"; peer_a_if="nca${suffix}"
server_b_if="nsb${suffix}"; peer_b_if="ncb${suffix}"
server_pid=""
namespaces_created=0

cleanup() {
  if [ -n "$server_pid" ]; then
    kill "$server_pid" >/dev/null 2>&1 || true
    wait "$server_pid" >/dev/null 2>&1 || true
  fi
  if [ "$namespaces_created" -eq 1 ]; then
    ip netns del "$client_a_ns" >/dev/null 2>&1 || true
    ip netns del "$client_b_ns" >/dev/null 2>&1 || true
    ip netns del "$server_ns" >/dev/null 2>&1 || true
  fi
  rm -rf -- "$fixture"
}
trap cleanup EXIT

if ! ip netns add "$server_ns" 2>/dev/null; then
  printf '[SKIP] this runtime does not permit disposable network namespaces\n'
  exit 0
fi
namespaces_created=1
ip netns add "$client_a_ns"
ip netns add "$client_b_ns"

ip link add "$server_a_if" type veth peer name "$peer_a_if"
ip link add "$server_b_if" type veth peer name "$peer_b_if"
ip link set "$server_a_if" netns "$server_ns"
ip link set "$peer_a_if" netns "$client_a_ns"
ip link set "$server_b_if" netns "$server_ns"
ip link set "$peer_b_if" netns "$client_b_ns"

ip -n "$server_ns" link set lo up
ip -n "$client_a_ns" link set lo up
ip -n "$client_b_ns" link set lo up
ip -n "$server_ns" addr add 192.0.2.10/24 dev "$server_a_if"
ip -n "$client_a_ns" addr add 192.0.2.20/24 dev "$peer_a_if"
ip -n "$server_ns" addr add 198.51.100.10/24 dev "$server_b_if"
ip -n "$client_b_ns" addr add 198.51.100.20/24 dev "$peer_b_if"
ip -n "$server_ns" link set "$server_a_if" up
ip -n "$client_a_ns" link set "$peer_a_if" up
ip -n "$server_ns" link set "$server_b_if" up
ip -n "$client_b_ns" link set "$peer_b_if" up

port=$((43000 + suffix % 1000))
server_helper="$TEST_ROOT/tests/helpers/ingress_echo_server.py"
probe_helper="$TEST_ROOT/tests/helpers/ingress_probe.py"

probe() {
  local namespace="$1" protocol="$2" host="$3"
  ip netns exec "$namespace" python3 "$probe_helper" \
    --protocol "$protocol" --host "$host" --port "$port" --timeout 0.7
}

wait_allowed_path() {
  local attempt=0
  while [ "$attempt" -lt 30 ]; do
    if probe "$client_a_ns" tcp 192.0.2.10 \
       && probe "$client_a_ns" udp 192.0.2.10; then
      return 0
    fi
    sleep 0.1
    attempt=$((attempt + 1))
  done
  return 1
}

start_server() {
  local bind="$1"
  ip netns exec "$server_ns" python3 "$server_helper" --bind "$bind" \
    --tcp-port "$port" --udp-port "$port" >"$fixture/server.log" 2>&1 &
  server_pid=$!
  wait_allowed_path || fail "echo server failed to accept the allowed path when bound to ${bind}"
}

stop_server() {
  kill "$server_pid" >/dev/null 2>&1 || true
  wait "$server_pid" >/dev/null 2>&1 || true
  server_pid=""
}

# Native bind: only the Profile-A local address owns the socket.
start_server 192.0.2.10
probe "$client_a_ns" tcp 192.0.2.10 || fail 'strict native TCP correct entry failed'
probe "$client_a_ns" udp 192.0.2.10 || fail 'strict native UDP correct entry failed'
if probe "$client_b_ns" tcp 198.51.100.10; then
  fail 'strict native TCP accepted the wrong entry address'
fi
if probe "$client_b_ns" udp 198.51.100.10; then
  fail 'strict native UDP accepted the wrong entry address'
fi
strict_socket_rows="$(ip netns exec "$server_ns" ss -Hln4tu)"
assert_contains "$strict_socket_rows" "192.0.2.10:${port}" 'strict native socket local address'
assert_not_contains "$strict_socket_rows" "0.0.0.0:${port}" 'strict native socket is not wildcard'
stop_server

# Compatibility mode: the same service contract remains reachable through
# both local addresses when the socket is wildcard.
start_server 0.0.0.0
probe "$client_a_ns" tcp 192.0.2.10 || fail 'permissive TCP Profile-A path failed'
probe "$client_b_ns" tcp 198.51.100.10 || fail 'permissive TCP Profile-B path failed'
probe "$client_a_ns" udp 192.0.2.10 || fail 'permissive UDP Profile-A path failed'
probe "$client_b_ns" udp 198.51.100.10 || fail 'permissive UDP Profile-B path failed'

# Mieru fallback: keep the wildcard socket, but apply the exact owned product
# rules inside the disposable server namespace.
export NOBRAND_STATE_DIR="$fixture/nobrand-oneclick/state"
export NOBRAND_CONFIG_DIR="$fixture/nobrand-oneclick/config"
export NOBRAND_LIB_DIR="$fixture/nobrand-oneclick/lib"
source_installer
nb_init_state_layout
nft() { ip netns exec "$server_ns" /usr/sbin/nft "$@"; }

firewall_candidate="$fixture/mieru-strict.json"
nb_strict_firewall_empty_state >"$firewall_candidate"
jq --argjson port "$port" '.rules=[
  {owner:"mieru:u1111111111111111",ingress_profile_id:"i1111111111111111",local_address:"192.0.2.10",transport:"TCP",port:$port},
  {owner:"mieru:u1111111111111111",ingress_profile_id:"i1111111111111111",local_address:"192.0.2.10",transport:"UDP",port:$port}
]' "$firewall_candidate" >"${firewall_candidate}.next"
mv -f "${firewall_candidate}.next" "$firewall_candidate"
nb_strict_firewall_commit_candidate "$firewall_candidate" \
  || fail 'product strict firewall candidate failed in the disposable namespace'
nb_strict_firewall_rule_owned mieru:u1111111111111111 TCP "$port" 192.0.2.10 \
  || fail 'owned strict TCP firewall rule was not accepted'
nb_strict_firewall_rule_owned mieru:u1111111111111111 UDP "$port" 192.0.2.10 \
  || fail 'owned strict UDP firewall rule was not accepted'
assert_not_contains "$(cat "$NOBRAND_INGRESS_FIREWALL_RULESET")" counter \
  'runtime strict firewall rules contain no ingress accounting counter'

probe "$client_a_ns" tcp 192.0.2.10 || fail 'firewall strict TCP correct entry failed'
probe "$client_a_ns" udp 192.0.2.10 || fail 'firewall strict UDP correct entry failed'
if probe "$client_b_ns" tcp 198.51.100.10; then
  fail 'firewall strict TCP accepted the wrong entry address'
fi
if probe "$client_b_ns" udp 198.51.100.10; then
  fail 'firewall strict UDP accepted the wrong entry address'
fi

nb_strict_firewall_remove_table || fail 'owned strict firewall table removal failed'
probe "$client_b_ns" tcp 198.51.100.10 \
  || fail 'wrong TCP path did not become reachable after owned rule removal'
probe "$client_b_ns" udp 198.51.100.10 \
  || fail 'wrong UDP path did not become reachable after owned rule removal'
nb_strict_firewall_restore_authoritative \
  || fail 'authoritative strict firewall restoration failed'
if probe "$client_b_ns" tcp 198.51.100.10; then
  fail 'restored strict firewall did not isolate the wrong TCP path'
fi
if probe "$client_b_ns" udp 198.51.100.10; then
  fail 'restored strict firewall did not isolate the wrong UDP path'
fi

nb_strict_firewall_clear_all || fail 'strict firewall cleanup failed'
if nft list table "$NOBRAND_INGRESS_NFT_FAMILY" "$NOBRAND_INGRESS_NFT_TABLE" >/dev/null 2>&1; then
  fail 'strict firewall cleanup left the owned table'
fi
probe "$client_b_ns" tcp 198.51.100.10 || fail 'cleanup did not restore permissive TCP reachability'
probe "$client_b_ns" udp 198.51.100.10 || fail 'cleanup did not restore permissive UDP reachability'

pass 'real TCP/UDP native-bind and owned-firewall cross-entry isolation, rule-removal proof, restore, and cleanup'
