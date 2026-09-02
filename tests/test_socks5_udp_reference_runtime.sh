#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/testlib.sh"

sizes=(64 512 900 1000 1100 1150 1180 1190 1200 1210 1250 1300 1350 1400 1450)
fixture="$(mktemp -d)"
runtime_pid=""
echo_pid=""
cleanup() {
  local rc=$?
  [ -z "$runtime_pid" ] || kill "$runtime_pid" >/dev/null 2>&1 || true
  [ -z "$echo_pid" ] || kill "$echo_pid" >/dev/null 2>&1 || true
  wait >/dev/null 2>&1 || true
  rm -rf -- "$fixture"
  return "$rc"
}
trap cleanup EXIT

for dependency in curl jq openssl python3 ss tar; do
  command -v "$dependency" >/dev/null 2>&1 \
    || fail "SOCKS5 UDP reference control dependency missing: $dependency"
done

source_installer

free_port() {
  local protocol="$1"
  python3 - "$protocol" <<'PY'
import socket
import sys

kind = socket.SOCK_DGRAM if sys.argv[1] == "udp" else socket.SOCK_STREAM
with socket.socket(socket.AF_INET, kind) as candidate:
    candidate.bind(("127.0.0.1", 0))
    print(candidate.getsockname()[1])
PY
}

wait_tcp() {
  local port="$1"
  local attempt
  for ((attempt=0; attempt<100; attempt++)); do
    ss -lntH "sport = :${port}" | grep -q . && return 0
    sleep 0.1
  done
  return 1
}

runtime="$fixture/sing-box"
tuic_download_runtime_candidate "$runtime" stable "" \
  || fail 'download and verify official sing-box stable runtime for direct control'
assert_eq "$TESTED_SING_BOX_SERVER_VERSION" "$(tuic_runtime_version "$runtime")" \
  'direct control sing-box version'

proxy_port="$(free_port tcp)"
target_port="$(free_port udp)"
jq -n --argjson proxy_port "$proxy_port" '{
  log: {level: "warn"},
  inbounds: [{type: "mixed", tag: "mixed-in", listen: "127.0.0.1", listen_port: $proxy_port}],
  outbounds: [{type: "direct", tag: "direct"}],
  route: {final: "direct"}
}' >"$fixture/sing-box.json"
"$runtime" check -c "$fixture/sing-box.json" >/dev/null \
  || fail 'sing-box direct control config validation'

python3 "$TEST_ROOT/tests/helpers/socks5_probe.py" echo-server --protocol udp \
  --host 127.0.0.1 --port "$target_port" >"$fixture/echo.log" 2>&1 &
echo_pid=$!
"$runtime" run -c "$fixture/sing-box.json" >"$fixture/sing-box.log" 2>&1 &
runtime_pid=$!
wait_tcp "$proxy_port" || {
  sed -n '1,120p' "$fixture/sing-box.log" >&2 || true
  fail 'sing-box direct SOCKS control startup'
}
kill -0 "$echo_pid" >/dev/null 2>&1 || fail 'UDP echo control startup'

# Byte-level parser controls include the only RFC 1928 framing case in which a
# 27-byte header naturally occurs: ATYP=DOMAIN with a 20-byte domain.
PYTHONDONTWRITEBYTECODE=1 python3 - \
  "$TEST_ROOT/tests/helpers/socks5_udp_reference_probe.py" <<'PY'
import importlib.util
import socket
import struct
import sys

spec = importlib.util.spec_from_file_location("reference_probe", sys.argv[1])
module = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = module
spec.loader.exec_module(module)

payload = b"payload"
ipv4 = b"\0\0\0\1" + socket.inet_pton(socket.AF_INET, "127.0.0.1") + struct.pack("!H", 9) + payload
ipv6 = b"\0\0\0\4" + socket.inet_pton(socket.AF_INET6, "::1") + struct.pack("!H", 9) + payload
domain = b"a" * 20
domain_packet = b"\0\0\0\3" + bytes((len(domain),)) + domain + struct.pack("!H", 9) + payload

assert module.parse_udp_response(ipv4).header_length == 10
assert module.parse_udp_response(ipv6).header_length == 22
assert module.parse_udp_response(domain_packet).header_length == 27
assert module.parse_udp_response(domain_packet).payload == payload
PY

old_matrix=()
for size in "${sizes[@]}"; do
  passed=0
  for ((attempt=1; attempt<=10; attempt++)); do
    if python3 "$TEST_ROOT/tests/helpers/socks5_probe.py" udp \
      --proxy-host 127.0.0.1 --proxy-port "$proxy_port" \
      --target-host 127.0.0.1 --target-port "$target_port" \
      --timeout 3 --sizes "$size" >"$fixture/old-${size}-${attempt}.log" 2>&1; then
      passed=$((passed + 1))
    elif [ "$attempt" -eq 1 ]; then
      sed -n '1,80p' "$fixture/old-${size}-${attempt}.log" >&2 || true
      sed -n '1,120p' "$fixture/sing-box.log" >&2 || true
    fi
  done
  assert_eq 10 "$passed" "old SOCKS5 UDP direct control ${size}"
  old_matrix+=("${size}:10/10")
done

python3 "$TEST_ROOT/tests/helpers/socks5_udp_reference_probe.py" \
  --proxy-host 127.0.0.1 --proxy-port "$proxy_port" \
  --target-host 127.0.0.1 --target-port "$target_port" \
  --timeout 3 --attempts 10 --sizes "${sizes[@]}" \
  >"$fixture/reference.jsonl" \
  || fail 'new RFC 1928 reference probe direct control matrix'

jq -s -e '
  [.[] | select(has("STATUS"))] as $trials |
  ($trials | length) == 150 and
  ([$trials[].STATUS] | unique) == ["PASS"] and
  ([$trials[].SOCKS_HEADER_LENGTH] | unique) == [10] and
  ([$trials[].PAYLOAD_OFFSET] | unique) == [10] and
  ([$trials[].RESPONSE_ATYP] | unique) == ["IPv4"] and
  ([$trials[].DIFFERENCE_COUNT] | unique) == [0]
' "$fixture/reference.jsonl" >/dev/null \
  || fail 'reference probe detailed framing/integrity evidence'

new_matrix=()
for size in "${sizes[@]}"; do
  passed="$(jq -s --argjson size "$size" \
    '[.[] | select(.SIZE == $size and .STATUS == "PASS")] | length' \
    "$fixture/reference.jsonl")"
  assert_eq 10 "$passed" "new reference SOCKS5 UDP direct control ${size}"
  new_matrix+=("${size}:10/10")
done

printf 'OLD_UDP_PROBE_DIRECT_CONTROL=%s\n' "${old_matrix[*]}"
printf 'NEW_REFERENCE_UDP_PROBE_DIRECT_CONTROL=%s\n' "${new_matrix[*]}"
printf 'SOCKS5_HEADER_LENGTHS_SYNTHETIC=IPv4:10,IPv6:22,DOMAIN20:27\n'
printf 'SOCKS5_HEADER_LENGTHS_OBSERVED=10\n'
printf 'SOCKS5_RESPONSE_ATYP_OBSERVED=IPv4\n'
pass 'old and independent RFC 1928 probes: local sing-box direct UDP matrix 15 sizes x 10/10'
