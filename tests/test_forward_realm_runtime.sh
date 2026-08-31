#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd -P)/testlib.sh"

for dependency in curl jq python3 sha256sum tar; do
  command -v "$dependency" >/dev/null 2>&1 || fail "Realm runtime dependency missing: $dependency"
done

fixture="$(mktemp -d)"
realm_pid=""
echo_pid=""
cleanup() {
  local rc=$?
  if [ "$rc" -ne 0 ]; then
    [ ! -s "$fixture/realm.log" ] || { printf '%s\n' '--- realm.log ---' >&2; cat "$fixture/realm.log" >&2; }
    [ ! -s "$fixture/realm-advanced.log" ] || { printf '%s\n' '--- realm-advanced.log ---' >&2; cat "$fixture/realm-advanced.log" >&2; }
  fi
  [ -z "$realm_pid" ] || kill "$realm_pid" 2>/dev/null || true
  [ -z "$echo_pid" ] || kill "$echo_pid" 2>/dev/null || true
  wait "$realm_pid" 2>/dev/null || true
  wait "$echo_pid" 2>/dev/null || true
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
forward_realm_install_runtime stable || fail 'official Realm stable runtime installation failed'
assert_eq "$TESTED_REALM_VERSION" "$(forward_realm_version)" 'official Realm version'
realm_asset="$(jq -r .asset "$NOBRAND_REALM_RUNTIME_META")"
assert_eq "$(forward_realm_tested_digest "$realm_asset")" \
  "$(jq -r .sha256 "$NOBRAND_REALM_RUNTIME_META")" 'official Realm architecture-specific musl digest'

cat >"$fixture/echo.py" <<'PY'
import socket
import threading
import time

PORTS = (21001, 21002, 21003)

def tcp_server(port, family=socket.AF_INET, host="127.0.0.1"):
    sock = socket.socket(family, socket.SOCK_STREAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    if family == socket.AF_INET6:
        sock.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 1)
    sock.bind((host, port))
    sock.listen(32)
    while True:
        conn, _ = sock.accept()
        threading.Thread(target=tcp_conn, args=(conn,), daemon=True).start()

def tcp_conn(conn):
    with conn:
        while True:
            data = conn.recv(65535)
            if not data:
                return
            conn.sendall(data)

def udp_server(port, family=socket.AF_INET, host="127.0.0.1"):
    sock = socket.socket(family, socket.SOCK_DGRAM)
    if family == socket.AF_INET6:
        sock.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 1)
    sock.bind((host, port))
    while True:
        data, peer = sock.recvfrom(65535)
        sock.sendto(data, peer)

for current in PORTS:
    threading.Thread(target=tcp_server, args=(current,), daemon=True).start()
    threading.Thread(target=udp_server, args=(current,), daemon=True).start()
threading.Thread(target=tcp_server, args=(21003, socket.AF_INET6, "::1"), daemon=True).start()
threading.Thread(target=udp_server, args=(21003, socket.AF_INET6, "::1"), daemon=True).start()
while True:
    time.sleep(3600)
PY
python3 "$fixture/echo.py" &
echo_pid=$!

cat >"$NOBRAND_FORWARD_STATE_FILE" <<'JSON'
{"schema_version":3,"ownership":"nobrand-v3","feature":"port-forward","rules":[
 {"rule_id":"f1111111111111111","name":"realm-tcp","note":"runtime tcp","backend":"realm","enabled":true,
  "protocol":"tcp","listen_host":"127.0.0.1","listen_port":22001,"target_host":"127.0.0.1","target_port":21001,
  "display_host":"","display_port":22001,"display_mode":"auto","created_at":"2026-08-30T00:00:00Z","updated_at":"2026-08-30T00:00:00Z",
  "ownership_metadata":{"managed_listener":true,"managed_firewall":true},
  "backend_options":{"through":"","interface":"","listen_interface":"","tcp_timeout":5,"udp_timeout":30,"proxy_send":false,"proxy_accept":false,"proxy_version":2,"proxy_accept_timeout":5,"dns_mode":"system","dns_protocol":"tcp_and_udp","dns_nameservers":[],"listen_transport":"","remote_transport":"","extra_targets":[],"balance":"off","weights":[]}},
 {"rule_id":"f2222222222222222","name":"realm-udp","note":"runtime udp","backend":"realm","enabled":true,
  "protocol":"udp","listen_host":"127.0.0.1","listen_port":22002,"target_host":"127.0.0.1","target_port":21002,
  "display_host":"","display_port":22002,"display_mode":"auto","created_at":"2026-08-30T00:00:00Z","updated_at":"2026-08-30T00:00:00Z",
  "ownership_metadata":{"managed_listener":true,"managed_firewall":true},
  "backend_options":{"through":"","interface":"","listen_interface":"","tcp_timeout":5,"udp_timeout":30,"proxy_send":false,"proxy_accept":false,"proxy_version":2,"proxy_accept_timeout":5,"dns_mode":"system","dns_protocol":"tcp_and_udp","dns_nameservers":[],"listen_transport":"","remote_transport":"","extra_targets":[],"balance":"off","weights":[]}},
 {"rule_id":"f3333333333333333","name":"realm-both-domain","note":"domain and both","backend":"realm","enabled":true,
  "protocol":"both","listen_host":"127.0.0.1","listen_port":22003,"target_host":"localhost","target_port":21003,
  "display_host":"","display_port":22003,"display_mode":"auto","created_at":"2026-08-30T00:00:00Z","updated_at":"2026-08-30T00:00:00Z",
  "ownership_metadata":{"managed_listener":true,"managed_firewall":true},
  "backend_options":{"through":"","interface":"","listen_interface":"","tcp_timeout":5,"udp_timeout":30,"proxy_send":false,"proxy_accept":false,"proxy_version":2,"proxy_accept_timeout":5,"dns_mode":"system","dns_protocol":"tcp_and_udp","dns_nameservers":[],"listen_transport":"","remote_transport":"","extra_targets":[],"balance":"off","weights":[]}}
]}
JSON
chmod 0600 "$NOBRAND_FORWARD_STATE_FILE"
forward_state_valid "$NOBRAND_FORWARD_STATE_FILE" || fail 'Realm runtime fixture state invalid'
forward_generate_realm_config "$NOBRAND_FORWARD_STATE_FILE" "$NOBRAND_FORWARD_REALM_CONFIG"
"$NOBRAND_REALM_BIN" -c "$NOBRAND_FORWARD_REALM_CONFIG" >"$fixture/realm.log" 2>&1 &
realm_pid=$!

python3 - <<'PY'
import socket
import sys
import time

def tcp(port, payload):
    deadline = time.time() + 10
    while time.time() < deadline:
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=1) as sock:
                sock.sendall(payload)
                return sock.recv(len(payload)) == payload
        except OSError:
            time.sleep(.1)
    return False

def udp(port, payload):
    deadline = time.time() + 10
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.settimeout(.5)
    while time.time() < deadline:
        try:
            sock.sendto(payload, ("127.0.0.1", port))
            data, _ = sock.recvfrom(65535)
            return data == payload
        except OSError:
            time.sleep(.1)
    return False

checks = (
    tcp(22001, b"realm-tcp"),
    udp(22002, b"realm-udp"),
    tcp(22003, b"realm-domain-tcp"),
    udp(22003, b"realm-domain-udp"),
)
print("REALM_DATA_CHECKS=" + ",".join("PASS" if item else "FAIL" for item in checks))
raise SystemExit(0 if all(checks) else 1)
PY
kill -0 "$realm_pid" 2>/dev/null || { cat "$fixture/realm.log" >&2; fail 'Realm exited during data-plane test'; }

# Candidate validation uses temporary free listeners. The active production
# Realm process must remain alive while the official binary probes a candidate.
forward_generate_realm_probe_config "$NOBRAND_FORWARD_STATE_FILE" "$fixture/probe.toml"
assert_not_contains "$(cat "$fixture/probe.toml")" '127.0.0.1:22001' \
  'Realm candidate probe excludes production listener ports'
forward_realm_probe_config "$fixture/probe.toml" || fail 'official Realm temporary-listener candidate probe'
kill -0 "$realm_pid" 2>/dev/null || fail 'candidate probe interrupted active Realm data plane'

kill "$realm_pid" 2>/dev/null || true
wait "$realm_pid" 2>/dev/null || true
realm_pid=""

# Exercise official advanced endpoint fields and load-balancer syntax with a
# real startup/data-plane probe. Both remotes are controlled local echo peers.
jq '(.rules[0].backend_options) |=
      (.through="127.0.0.1" | .interface="lo" | .listen_interface="lo" |
       .tcp_timeout=3 | .udp_timeout=15 |
       .extra_targets=["127.0.0.1:21003"] | .balance="roundrobin" | .weights=[2,1])' \
  "$NOBRAND_FORWARD_STATE_FILE" >"$fixture/advanced.json"
forward_generate_realm_config "$fixture/advanced.json" "$fixture/advanced.toml"
assert_contains "$(cat "$fixture/advanced.toml")" 'balance = "roundrobin: 2, 1"' 'Realm load balance syntax'
"$NOBRAND_REALM_BIN" -c "$fixture/advanced.toml" >"$fixture/realm-advanced.log" 2>&1 &
realm_pid=$!
python3 - <<'PY'
import socket, time
deadline=time.time()+10
while time.time()<deadline:
    try:
        with socket.create_connection(("127.0.0.1",22001),timeout=1) as s:
            s.sendall(b"realm-advanced")
            raise SystemExit(0 if s.recv(64)==b"realm-advanced" else 1)
    except OSError:
        time.sleep(.1)
raise SystemExit(1)
PY

pass 'official Realm v2.9.6 digest, TCP, UDP, BOTH, domain, multi-rule, through/interface, and load balance runtime'
