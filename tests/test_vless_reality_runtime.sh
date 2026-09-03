#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/testlib.sh"

fixture="$(mktemp -d)"
server_pid="" relay_pid="" target_pid="" private_target_pid="" dangerous_target_pid=""
policy_pid="" client_pid="" target_address_added=0 hosts_changed=0
target_host="1.1.1.254"
reality_server_name="${NOBRAND_REALITY_TEST_SERVER_NAME:-example.com}"
cleanup() {
  for pid in "$client_pid" "$policy_pid" "$relay_pid" "$server_pid" "$target_pid" \
    "$private_target_pid" "$dangerous_target_pid"; do
    [ -z "$pid" ] || kill "$pid" >/dev/null 2>&1 || true
  done
  wait >/dev/null 2>&1 || true
  [ "$target_address_added" -eq 0 ] \
    || ip address del "${target_host}/32" dev lo >/dev/null 2>&1 || true
  [ "$hosts_changed" -eq 0 ] \
    || cp "$fixture/hosts.before" /etc/hosts >/dev/null 2>&1 || true
  if [ "${NOBRAND_KEEP_RUNTIME_FIXTURE:-0}" = 1 ]; then
    printf '[INFO] preserved REALITY runtime fixture: %s\n' "$fixture" >&2
  else
    rm -rf -- "$fixture"
  fi
}
trap cleanup EXIT

export NOBRAND_STATE_DIR="$fixture/nobrand-oneclick/state"
export NOBRAND_CONFIG_DIR="$fixture/nobrand-oneclick/config"
export NOBRAND_LIB_DIR="$fixture/nobrand-oneclick/lib"
export NOBRAND_LIFECYCLE_DIR="$fixture/nobrand-oneclick-lifecycle"
export NOBRAND_LIFECYCLE_TX_FILE="$NOBRAND_LIFECYCLE_DIR/transaction.env"
export NOBRAND_LIFECYCLE_LOCK_FILE="$fixture/run/nobrand-oneclick/lifecycle.lock"
mkdir -p "$(dirname "$NOBRAND_LIFECYCLE_LOCK_FILE")"
chmod 0700 "$(dirname "$NOBRAND_LIFECYCLE_LOCK_FILE")"
export NOBRAND_REALITY_SYSTEMD_TEMPLATE="$fixture/systemd/nobrand-vless-reality@.service"
source_installer
nb_init_state_layout

for command_name in curl jq openssl python3 ss gzip sha256sum dd ip timeout; do
  command -v "$command_name" >/dev/null 2>&1 \
    || fail "REALITY runtime dependency missing: $command_name"
done

free_port() {
  python3 - <<'PY'
import socket
with socket.socket() as sock:
    sock.bind(("127.0.0.1", 0))
    print(sock.getsockname()[1])
PY
}

wait_tcp() {
  local port="$1" attempts="${2:-100}"
  for ((index=0; index<attempts; index++)); do
    ss -lntH "sport = :${port}" | grep -q . && return 0
    sleep 0.1
  done
  return 1
}

stop_process() {
  local pid="${1:-}"
  [ -z "$pid" ] || kill "$pid" >/dev/null 2>&1 || true
  [ -z "$pid" ] || wait "$pid" >/dev/null 2>&1 || true
}

runtime_cache="${NOBRAND_RUNTIME_CACHE:-/tmp/nobrand-runtime-cache}"
mkdir -p "$runtime_cache"
cached_xray="$runtime_cache/xray-${TESTED_XRAY_VERSION}"
cached_xray_assets="$runtime_cache/xray-assets-${TESTED_XRAY_VERSION}"
if [ ! -x "$cached_xray" ] \
   || ! "$cached_xray" version 2>/dev/null | head -n1 | grep -q "^Xray ${TESTED_XRAY_VERSION} " \
   || [ ! -s "$cached_xray_assets/geoip.dat" ] \
   || [ ! -s "$cached_xray_assets/geosite.dat" ]; then
  candidate="$fixture/xray-candidate"
  candidate_assets="$fixture/xray-candidate-assets"
  nobrand_download_xray_candidate "$candidate" "$candidate_assets" \
    || fail 'official Xray REALITY runtime/assets download/digest'
  install -m 0755 "$candidate" "$cached_xray"
  rm -rf -- "$cached_xray_assets"
  install -d -m 0755 "$cached_xray_assets"
  install -m 0644 "$candidate_assets/geoip.dat" "$cached_xray_assets/geoip.dat"
  install -m 0644 "$candidate_assets/geosite.dat" "$cached_xray_assets/geosite.dat"
fi
xray="$fixture/xray"
install -m 0755 "$cached_xray" "$xray"
install -d -m 0755 "$NOBRAND_XRAY_ASSET_DIR"
install -m 0644 "$cached_xray_assets/geoip.dat" "$NOBRAND_XRAY_ASSET_DIR/geoip.dat"
install -m 0644 "$cached_xray_assets/geosite.dat" "$NOBRAND_XRAY_ASSET_DIR/geosite.dat"
NOBRAND_XRAY_BIN="$xray"
export NOBRAND_XRAY_BIN NOBRAND_XRAY_ASSET_DIR
assert_eq "$TESTED_XRAY_VERSION" "$(nobrand_xray_version)" 'exact REALITY Xray runtime version'
nobrand_xray_assets_ready || fail 'exact REALITY Xray private assets'

mihomo_gzip="$runtime_cache/mihomo-linux-amd64-v1.19.30.gz"
mihomo_sha=cf06ce2c7d1421bdbda14ee4a5b6046672dc35ebf8eecd8e77504ec3c0ed9a84
if [ ! -s "$mihomo_gzip" ] || [ "$(sha256sum "$mihomo_gzip" | awk '{print $1}')" != "$mihomo_sha" ]; then
  curl -fL --connect-timeout 10 --max-time 300 \
    'https://github.com/MetaCubeX/mihomo/releases/download/v1.19.30/mihomo-linux-amd64-v1.19.30.gz' \
    -o "$mihomo_gzip"
fi
assert_eq "$mihomo_sha" "$(sha256sum "$mihomo_gzip" | awk '{print $1}')" \
  'official Mihomo v1.19.30 digest'
mihomo="$fixture/mihomo"
gzip -dc "$mihomo_gzip" >"$mihomo"
chmod 0755 "$mihomo"

cached_singbox="$runtime_cache/sing-box-${TESTED_SING_BOX_SERVER_VERSION}"
if [ ! -x "$cached_singbox" ] \
   || [ "$(tuic_runtime_version "$cached_singbox" 2>/dev/null || true)" != "$TESTED_SING_BOX_SERVER_VERSION" ]; then
  tuic_download_runtime_candidate "$cached_singbox" stable "" \
    || fail 'official sing-box 1.13.20 REALITY client download/digest'
fi
singbox="$fixture/sing-box"
install -m 0755 "$cached_singbox" "$singbox"
assert_eq "$TESTED_SING_BOX_SERVER_VERSION" "$(tuic_runtime_version "$singbox")" \
  'exact sing-box REALITY client version'

ip -4 address show dev lo | grep -qF " ${target_host}/32" \
  && fail "controlled public-looking loopback address is already present: ${target_host}"
ip address add "${target_host}/32" dev lo
target_address_added=1

server_port="$(free_port)"
relay_port="$(free_port)"
target_port="$(free_port)"
private_target_port="$(free_port)"
defender_port="$(reality_select_defender_port "$server_port")"
xray_socks_port="$(free_port)"
[ "$xray_socks_port" != 7890 ] && [ "$xray_socks_port" != 1080 ] \
  || xray_socks_port="$(free_port)"
ss -lntH 'sport = :7890' | grep -q . && fail 'Mihomo raw exporter port 7890 is already occupied'
ss -lntH 'sport = :1080' | grep -q . && fail 'sing-box raw exporter port 1080 is already occupied'

export NOBRAND_TEST_INTERFACE_ROWS='eth0|192.0.2.50|UP|1'
export NOBRAND_TEST_DEFAULT_EGRESS='eth0|192.0.2.50'
ingress_menu_reset_requests
parse_nobrand_ingress_args add --name Runtime-Public --type public --interface eth0 \
  --address 192.0.2.50 --port-policy manual-only --yes
nobrand_run_ingress_action >/dev/null
ingress_id="$(nb_ingress_profile_id Runtime-Public)"

if ! reality_target_resolves_public "$reality_server_name" 443; then
  # Codex/desktop WSL networking may intentionally synthesize the benchmark
  # 198.18.0.0/15 range while transparently proxying the public TLS endpoint.
  # Accept only that explicit lab condition; production keeps the public-IP
  # check and the real-machine gate must pass it without this override.
  python3 - "$reality_server_name" <<'PY' || fail 'REALITY target resolved to a non-public address outside the local transparent-proxy range'
import ipaddress
import socket
import sys
addresses = {item[4][0] for item in socket.getaddrinfo(sys.argv[1], 443, type=socket.SOCK_STREAM)}
lab = ipaddress.ip_network("198.18.0.0/15")
raise SystemExit(0 if addresses and all(ipaddress.ip_address(item) in lab for item in addresses) else 1)
PY
  reality_target_resolves_public() { return 0; }
fi
reality_validate_target_live "$reality_server_name" 443 \
  || fail 'REALITY target public/TLS1.3/certificate suitability'
id="r$(openssl rand -hex 8)"
uuid="$(reality_generate_uuid)"
keypair="$(reality_generate_keypair)"
private_key="${keypair%%|*}"
public_key="${keypair#*|}"
short_id="$(reality_generate_short_id)"
second_uuid="$(reality_generate_uuid)"
second_keypair="$(reality_generate_keypair)"
second_short_id="$(reality_generate_short_id)"
[ "$uuid" != "$second_uuid" ] || fail 'independent REALITY instance UUIDs differ'
[ "$keypair" != "$second_keypair" ] || fail 'independent REALITY instance keypairs differ'
[ "$short_id" != "$second_short_id" ] || fail 'independent REALITY instance short IDs differ'
assert_eq "$public_key" "$(reality_derive_public_key "$private_key")" \
  'official Xray private-to-public derivation'

config="$(reality_config_file "$id")"
state="$(reality_state_file "$id")"
key_file="$(reality_private_key_file "$id")"
mkdir -p "$(dirname "$config")" "$(dirname "$state")"
printf '%s\n' "$private_key" >"$key_file"
chmod 0600 "$key_file"
reality_generate_server_config "$config" "$id" 0.0.0.0 "$server_port" "$uuid" \
  "$private_key" "$short_id" "$reality_server_name" 443 "$defender_port"
reality_generate_state "$state" "$id" runtime 0.0.0.0 "$server_port" custom \
  127.0.0.1 "$relay_port" "$uuid" "$public_key" "$key_file" "$short_id" \
  "$reality_server_name" 443 chrome / "$TESTED_XRAY_VERSION" "$ingress_id" "$defender_port" \
  2026-09-01T00:00:00Z
chmod 0600 "$config" "$state"
reality_state_matches "$state" "$id" || fail 'real REALITY state contract'
reality_config_matches_state "$id" || fail 'real REALITY config/state/key contract'
nobrand_xray_test_config "$config" "$xray" || fail 'Xray rejected REALITY server config'
assert_file_mode 600 "$key_file"
assert_eq '0:0' "$(stat -c '%u:%g' "$key_file")" 'real REALITY private-key ownership'

xray_client="$fixture/xray-client.json"
mihomo_dir="$fixture/mihomo-home"
mihomo_config="$mihomo_dir/config.yaml"
singbox_config="$fixture/sing-box-client.json"
mkdir -p "$mihomo_dir"
reality_export_xray "$id" "$xray_socks_port" >"$xray_client"
reality_export_mihomo "$id" >"$mihomo_config"
reality_export_singbox "$id" >"$singbox_config"
nobrand_xray_test_config "$xray_client" "$xray" || fail 'Xray rejected generated REALITY client exporter'
python3 "$TEST_ROOT/tests/helpers/assert_mihomo_routing_contract.py" \
  "$mihomo_config" NOBRAND >/dev/null || fail 'Mihomo REALITY no-direct routing contract'
"$mihomo" -t -f "$mihomo_config" >/dev/null || fail 'Mihomo rejected generated REALITY exporter'
"$singbox" check -c "$singbox_config" >/dev/null || fail 'sing-box rejected generated REALITY exporter'

relay_count_file="$fixture/relay.count"
python3 "$TEST_ROOT/tests/helpers/tcp_recording_relay.py" --listen-port "$relay_port" \
  --target-port "$server_port" --count-file "$relay_count_file" >"$fixture/relay.log" 2>&1 &
relay_pid=$!
wait_tcp "$relay_port" || fail 'REALITY recording transport relay startup'
openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj '/CN=localhost' \
  -keyout "$fixture/target.key" -out "$fixture/target.crt" >/dev/null 2>&1
python3 "$TEST_ROOT/tests/helpers/http_integrity_server.py" --host "$target_host" --port "$target_port" \
  --cert "$fixture/target.crt" --key "$fixture/target.key" \
  >"$fixture/target.log" 2>&1 &
target_pid=$!
for ((index=0; index<100; index++)); do
  ss -lntH | grep -qF "${target_host}:${target_port}" && break
  sleep 0.1
done
ss -lntH | grep -qF "${target_host}:${target_port}" \
  || fail 'REALITY controlled public-looking HTTP integrity target startup'

python3 "$TEST_ROOT/tests/helpers/http_integrity_server.py" --host 127.0.0.1 \
  --port "$private_target_port" --cert "$fixture/target.crt" --key "$fixture/target.key" \
  >"$fixture/private-target.log" 2>&1 &
private_target_pid=$!
wait_tcp "$private_target_port" || fail 'REALITY controlled private target startup'

start_server() {
  stop_process "$server_pid"
  XRAY_LOCATION_ASSET="$NOBRAND_XRAY_ASSET_DIR" \
    "$xray" run -c "$config" >"$fixture/server.log" 2>&1 &
  server_pid=$!
  wait_tcp "$server_port" || {
    sed -n '1,100p' "$fixture/server.log" >&2 || true
    fail 'REALITY Xray server startup'
  }
  wait_tcp "$defender_port" || fail 'REALITY defender listener startup'
  reality_defender_listener_loopback_only "$defender_port" \
    || fail 'REALITY defender listener is not loopback-only'
}

stop_server() {
  stop_process "$server_pid"
  server_pid=""
}

stop_client() {
  stop_process "$client_pid"
  client_pid=""
  sleep 0.2
}

active_socks_port=""
start_client() {
  local client="$1" socks_port
  stop_client
  case "$client" in
    xray)
      socks_port="$xray_socks_port"
      XRAY_LOCATION_ASSET="$NOBRAND_XRAY_ASSET_DIR" \
        "$xray" run -c "$xray_client" >"$fixture/xray-client.log" 2>&1 &
      ;;
    mihomo)
      socks_port=7890
      "$mihomo" -d "$mihomo_dir" -f "$mihomo_config" >"$fixture/mihomo.log" 2>&1 &
      ;;
    singbox)
      socks_port=1080
      "$singbox" run -c "$singbox_config" >"$fixture/sing-box.log" 2>&1 &
      ;;
    *) return 1 ;;
  esac
  client_pid=$!
  wait_tcp "$socks_port" || {
    sed -n '1,120p' "$fixture/${client}-client.log" >&2 || true
    [ "$client" != mihomo ] || sed -n '1,120p' "$fixture/mihomo.log" >&2 || true
    [ "$client" != singbox ] || sed -n '1,120p' "$fixture/sing-box.log" >&2 || true
    fail "${client} REALITY client startup"
  }
  active_socks_port="$socks_port"
}

probe_https() {
  local socks_port="$1" count="$2" _retry succeeded
  for ((attempt=1; attempt<=count; attempt++)); do
    succeeded=0
    for _retry in 1 2 3; do
      if curl -kfsS --max-time 15 --noproxy '' --socks5-hostname "127.0.0.1:${socks_port}" \
          "https://${target_host}:${target_port}/" -o /dev/null; then
        succeeded=1
        break
      fi
      sleep 0.2
    done
    [ "$succeeded" -eq 1 ] || return 1
  done
}

wait_proxy_recovery() {
  local socks_port="$1"
  for ((attempt=1; attempt<=20; attempt++)); do
    if curl -kfsS --max-time 5 --noproxy '' --socks5-hostname "127.0.0.1:${socks_port}" \
        "https://${target_host}:${target_port}/" -o /dev/null 2>/dev/null; then
      return 0
    fi
    sleep 0.5
  done
  return 1
}

blob="$fixture/64m.bin"
dd if=/dev/zero of="$blob" bs=1M count=64 status=none
blob_sha="$(sha256sum "$blob" | awk '{print $1}')"
probe_throughput() {
  local client="$1" socks_port="$2" upload_response
  local downloaded="$fixture/${client}-download.bin"
  curl -kfsS --max-time 180 --noproxy '' --socks5-hostname "127.0.0.1:${socks_port}" \
    "https://${target_host}:${target_port}/blob" -o "$downloaded"
  assert_eq "$blob_sha" "$(sha256sum "$downloaded" | awk '{print $1}')" \
    "${client} REALITY 64 MiB download integrity"
  upload_response="$(curl -kfsS --max-time 180 --noproxy '' \
    --socks5-hostname "127.0.0.1:${socks_port}" --data-binary "@${blob}" \
    "https://${target_host}:${target_port}/upload")"
  assert_eq "67108864:${blob_sha}" "$upload_response" "${client} REALITY 64 MiB upload integrity"
  rm -f "$downloaded"
}

tls_probe_success() {
  local port="$1" sni="$2" log="$3"
  timeout 20 openssl s_client -connect "127.0.0.1:${port}" -servername "$sni" \
    -tls1_3 -brief </dev/null >"$log" 2>&1 \
    && grep -Eq 'Peer certificate|Protocol version: TLSv1\.3' "$log"
}

tls_probe_blocked() {
  local port="$1" sni="$2" log="$3"
  if timeout 8 openssl s_client -connect "127.0.0.1:${port}" -servername "$sni" \
      -tls1_3 -brief </dev/null >"$log" 2>&1 \
     && grep -Eq 'Peer certificate|Protocol version: TLSv1\.3' "$log"; then
    return 1
  fi
}

raw_probe_blocked() {
  local port="$1" payload="$2"
  python3 - "$port" "$payload" <<'PY'
import socket
import sys

port = int(sys.argv[1])
payload = bytes.fromhex(sys.argv[2])
with socket.create_connection(("127.0.0.1", port), timeout=3) as sock:
    sock.settimeout(3)
    sock.sendall(payload)
    try:
        data = sock.recv(4096)
    except (TimeoutError, socket.timeout, ConnectionResetError):
        data = b""
if data:
    sys.stderr.write("unexpected probe response: " + data[:64].hex() + "\n")
raise SystemExit(0 if not data else 1)
PY
}

start_policy_server() {
  local policy_config="$1" policy_port="$2"
  stop_process "$policy_pid"
  XRAY_LOCATION_ASSET="$NOBRAND_XRAY_ASSET_DIR" \
    "$xray" run -c "$policy_config" >"$fixture/policy-server.log" 2>&1 &
  policy_pid=$!
  wait_tcp "$policy_port" || {
    sed -n '1,120p' "$fixture/policy-server.log" >&2 || true
    fail 'REALITY controlled policy server startup'
  }
}

start_server
reality_defender_listener_owned_by_service() {
  local _id="$1" port="$2" pid
  reality_defender_listener_loopback_only "$port" || return 1
  while IFS= read -r pid; do
    [ "$pid" = "$server_pid" ] && return 0
  done < <(nb_port_listener_pids TCP "$port")
  return 1
}
reality_defender_listener_owned_by_service "$id" "$defender_port" \
  || fail 'REALITY public and defender listeners are not owned by the same Xray process'
printf 'REALITY_DEFENDER_CONFIG=PASS\nREALITY_DEFENDER_LOOPBACK_ONLY=PASS\n'

tls_probe_success "$defender_port" "$reality_server_name" "$fixture/defender-expected.log" \
  || fail 'direct REALITY defender expected SNI did not reach the selected TLS target'
tls_probe_success "$server_port" "$reality_server_name" "$fixture/public-invalid-expected.log" \
  || fail 'unauthenticated public REALITY expected SNI did not traverse the defender target'
printf 'REALITY_DEFENDER_EXPECTED_SNI=PASS\n'

# Exercise the exact generated product topology against the controlled TLS
# endpoint on a non-443 port. sslip.io supplies DNS only; the destination is
# the test-owned loopback address above, so no arbitrary third-party port is
# scanned or contacted.
custom_target_host="controlled-reality-target.example"
cp /etc/hosts "$fixture/hosts.before"
printf '%s %s\n' "$target_host" "$custom_target_host" >>/etc/hosts
hosts_changed=1
reality_target_resolves_public "$custom_target_host" "$target_port" \
  || fail 'controlled custom-port hostname did not resolve to the public-looking test address'
custom_public_port="$(free_port)"
custom_defender_port="$(reality_select_defender_port "$custom_public_port")"
custom_port_config="$fixture/custom-port-server.json"
reality_generate_server_config "$custom_port_config" r1111111111111111 127.0.0.1 \
  "$custom_public_port" "$uuid" "$private_key" "$short_id" "$custom_target_host" \
  "$target_port" "$custom_defender_port"
nobrand_xray_test_config "$custom_port_config" "$xray" \
  || fail 'Xray rejected exact controlled custom target-port REALITY config'
jq -e --arg host "$custom_target_host" --argjson public "$custom_public_port" \
  --argjson defender "$custom_defender_port" --argjson target "$target_port" '
  .inbounds[0].port==$public
  and .inbounds[0].streamSettings.realitySettings.serverNames==[$host]
  and .inbounds[0].streamSettings.realitySettings.target==("127.0.0.1:"+($defender|tostring))
  and .inbounds[1].listen=="127.0.0.1"
  and .inbounds[1].port==$defender
  and .inbounds[1].settings.port==$target
  and .outbounds[1].settings.redirect==($host+":"+($target|tostring))
  and $public!=$target and $defender!=$target and $public!=$defender
' "$custom_port_config" >/dev/null || fail 'custom target-port/public/defender separation'
start_policy_server "$custom_port_config" "$custom_defender_port"
curl -kfsS --max-time 15 --noproxy '*' \
  --resolve "${custom_target_host}:${custom_defender_port}:127.0.0.1" \
  "https://${custom_target_host}:${custom_defender_port}/" -o /dev/null \
  || fail 'controlled non-443 defender target runtime'
stop_process "$policy_pid"; policy_pid=""
printf 'REALITY_CUSTOM_TARGET_PORT_RUNTIME=PASS\n'

tls_probe_blocked "$defender_port" unexpected.example.invalid "$fixture/defender-wrong-sni.log" \
  || fail 'direct REALITY defender accepted unexpected SNI'
tls_probe_blocked "$server_port" unexpected.example.invalid "$fixture/public-wrong-sni.log" \
  || fail 'public REALITY invalid connection accepted unexpected SNI through defender'
printf 'REALITY_DEFENDER_UNEXPECTED_SNI_BLOCKED=PASS\n'

raw_probe_blocked "$defender_port" \
  474554202f20485454502f312e310d0a486f73743a206578616d706c652e636f6d0d0a0d0a \
  || fail 'direct REALITY defender forwarded plaintext HTTP'
raw_probe_blocked "$server_port" 6e6f6272616e642d72616e646f6d2d70726f6265 \
  || fail 'public REALITY random probe received forwarded data'
raw_probe_blocked "$defender_port" 16030100020100 \
  || fail 'direct REALITY defender forwarded malformed TLS'
printf 'REALITY_DEFENDER_RANDOM_PROBE_BLOCKED=PASS\n'

private_policy_port="$(reality_select_defender_port "$server_port")"
private_policy_config="$fixture/private-policy.json"
jq --arg tag nobrand-reality-private-policy --arg port "$private_policy_port" \
  --arg target_port "$private_target_port" '
  .inbounds=[.inbounds[1]]
  | .inbounds[0].tag=$tag
  | .inbounds[0].port=($port|tonumber)
  | .inbounds[0].settings.address="127.0.0.1"
  | .inbounds[0].settings.port=($target_port|tonumber)
  | (.outbounds[] | select(.tag=="DIRECT") | .settings.redirect)=("127.0.0.1:"+$target_port)
  | .routing.rules[3].inboundTag=[$tag]
  | .routing.rules[3].domain=["full:private-probe.example"]
  | .routing.rules[4].inboundTag=[$tag]
  ' "$config" >"$private_policy_config"
nobrand_xray_test_config "$private_policy_config" "$xray" \
  || fail 'Xray rejected controlled private-target defender policy config'
start_policy_server "$private_policy_config" "$private_policy_port"
tls_probe_blocked "$private_policy_port" private-probe.example "$fixture/private-policy.log" \
  || fail 'REALITY defender geoip:private rule did not block loopback target before exact SNI allow'
stop_process "$policy_pid"; policy_pid=""
printf 'REALITY_DEFENDER_PRIVATE_TARGET_BLOCKED=PASS\n'

if ss -lntH 'sport = :25' | grep -q .; then
  fail 'controlled dangerous-port test requires locally unused TCP/25'
fi
python3 "$TEST_ROOT/tests/helpers/http_integrity_server.py" --host "$target_host" --port 25 \
  --cert "$fixture/target.crt" --key "$fixture/target.key" \
  >"$fixture/dangerous-target.log" 2>&1 &
dangerous_target_pid=$!
for ((index=0; index<100; index++)); do
  ss -lntH | grep -qF "${target_host}:25" && break
  sleep 0.1
done
ss -lntH | grep -qF "${target_host}:25" || fail 'controlled dangerous-port TLS target startup'
dangerous_policy_port="$(reality_select_defender_port "$server_port")"
dangerous_policy_config="$fixture/dangerous-policy.json"
jq --arg tag nobrand-reality-dangerous-policy --arg port "$dangerous_policy_port" \
  --arg address "$target_host" '
  .inbounds=[.inbounds[1]]
  | .inbounds[0].tag=$tag
  | .inbounds[0].port=($port|tonumber)
  | .inbounds[0].settings.address=$address
  | .inbounds[0].settings.port=25
  | (.outbounds[] | select(.tag=="DIRECT") | .settings.redirect)=($address+":25")
  | .routing.rules[3].inboundTag=[$tag]
  | .routing.rules[3].domain=["full:dangerous-probe.example"]
  | .routing.rules[4].inboundTag=[$tag]
  ' "$config" >"$dangerous_policy_config"
nobrand_xray_test_config "$dangerous_policy_config" "$xray" \
  || fail 'Xray rejected controlled dangerous-port defender policy config'
start_policy_server "$dangerous_policy_config" "$dangerous_policy_port"
tls_probe_blocked "$dangerous_policy_port" dangerous-probe.example "$fixture/dangerous-policy.log" \
  || fail 'REALITY defender dangerous TCP port rule did not run before exact SNI allow'
stop_process "$policy_pid"; policy_pid=""
stop_process "$dangerous_target_pid"; dangerous_target_pid=""
jq -e '.routing.rules[1].port=="25,135,137,138,139,445,465,587"
  and .routing.rules[2].protocol==["bittorrent"]' "$config" >/dev/null \
  || fail 'REALITY defender dangerous-port/BitTorrent rule set changed'
printf 'REALITY_DEFENDER_DANGEROUS_PORT_RULES=PASS\nREALITY_DEFENDER_BITTORRENT_RULE=PASS\n'

runtime_clients="${NOBRAND_REALITY_RUNTIME_CLIENTS:-xray mihomo singbox}"
for client in $runtime_clients; do
  count_before="$(<"$relay_count_file")"
  start_client "$client"
  socks_port="$active_socks_port"
  wait_proxy_recovery "$socks_port" || fail "${client} REALITY initial transport readiness"
  probe_https "$socks_port" 20 || fail "${client} REALITY HTTPS 20/20"
  probe_throughput "$client" "$socks_port"
  count_after="$(<"$relay_count_file")"
  [ "$count_after" -gt "$count_before" ] || fail "${client} did not use the REALITY transport endpoint"
  stop_server
  if curl -kfsS --max-time 5 --noproxy '' --socks5-hostname "127.0.0.1:${socks_port}" \
      "https://${target_host}:${target_port}/" >/dev/null 2>&1; then
    fail "${client} REALITY exporter allowed a DIRECT fallback"
  fi
  start_server
  wait_proxy_recovery "$socks_port" || fail "${client} REALITY transport did not recover after restart"
  probe_https "$socks_port" 5 || fail "${client} REALITY recovery after no-direct stop"
  printf '[PASS] %s REALITY parser/launch, HTTPS 20/20, 64 MiB down/up, transport, no-direct, recovery\n' "$client"
done
stop_client

credential_snapshot="$(jq -cS '[.uuid,.public_key,.short_id,.camouflage_mode,.server_name,.target_port,.listen_port,.ingress_profile_id,.advertise_mode,.advertise_host,.advertise_port,.defender_port,.defender_tag,.defender_protocol,.defender_listen]' "$state")"
key_hash="$(sha256sum "$key_file")"
config_hash="$(sha256sum "$config")"
old_server_pid="$server_pid"
start_server
[ "$server_pid" != "$old_server_pid" ] || fail 'REALITY restart did not change PID'
assert_eq "$key_hash" "$(sha256sum "$key_file")" 'REALITY restart preserves private key'
assert_eq "$config_hash" "$(sha256sum "$config")" 'REALITY restart preserves config'
assert_eq "$credential_snapshot" \
  "$(jq -cS '[.uuid,.public_key,.short_id,.camouflage_mode,.server_name,.target_port,.listen_port,.ingress_profile_id,.advertise_mode,.advertise_host,.advertise_port,.defender_port,.defender_tag,.defender_protocol,.defender_listen]' "$state")" \
  'REALITY restart preserves credentials/port/Profile/Display'
for client in $runtime_clients; do
  start_client "$client"
  socks_port="$active_socks_port"
  wait_proxy_recovery "$socks_port" || fail "${client} REALITY readiness after service restart"
  probe_https "$socks_port" 5 || fail "${client} REALITY 5/5 after service restart"
done
stop_client
printf '[PASS] REALITY restart changed PID and all clients recovered 5/5 with state preserved\n'

reality_service_active() { [ -n "$server_pid" ] && kill -0 "$server_pid" 2>/dev/null; }
reality_service_pid() { printf '%s' "$server_pid"; }
nb_firewall_binding_owned() { [ "$1:$2" = "TCP:${server_port}" ]; }
doctor_output="$(reality_doctor_one "$id")" || {
  printf '%s\n' "$doctor_output" >&2
  fail 'real REALITY Doctor'
}
for check in REALITY_CONFIG REALITY_XRAY_ASSETS REALITY_DEFENDER REALITY_KEYS REALITY_LISTENER \
  REALITY_FIREWALL REALITY_DEFENDER_INTERNAL_OWNERSHIP REALITY_PORT_OWNERSHIP \
  REALITY_INGRESS_PROFILE REALITY_DISPLAY; do
  assert_contains "$doctor_output" "[PASS] ${check}" "real REALITY Doctor ${check}"
done
assert_not_contains "$doctor_output" "$private_key" 'real REALITY Doctor private-key secrecy'

backup="$fixture/reality-backup.tar.gz"
nobrand_backup_create "$backup" >/dev/null
backup_state_hash="$(sha256sum "$state")"
backup_config_hash="$(sha256sum "$config")"
backup_key_hash="$(sha256sum "$key_file")"
printf '%s\n' "${second_keypair%%|*}" >"$key_file"
jq '.uuid="00000000-0000-4000-8000-000000000000" | .short_id="aabb" | .camouflage_mode="auto"
  | .listen_port=39999 | .advertise_host="changed.example"' "$state" >"$fixture/state.changed"
mv "$fixture/state.changed" "$state"
stop_server
nobrand_stop_all_services() { stop_server; }
nobrand_restore_protocol_runtimes() { nobrand_xray_test_config "$config" "$xray"; }
nobrand_start_enabled_services() { start_server; }
nobrand_backup_restore "$backup" >/dev/null
assert_eq "$backup_state_hash" "$(sha256sum "$state")" 'REALITY restore exact state'
assert_eq "$backup_config_hash" "$(sha256sum "$config")" 'REALITY restore exact config'
assert_eq "$backup_key_hash" "$(sha256sum "$key_file")" 'REALITY restore exact private key'
for client in $runtime_clients; do
  start_client "$client"
  socks_port="$active_socks_port"
  wait_proxy_recovery "$socks_port" || fail "${client} REALITY readiness after backup restore"
  probe_https "$socks_port" 5 || fail "${client} REALITY 5/5 after backup restore"
done
stop_client
printf '[PASS] REALITY formal backup/restore preserved credentials/Profile/Display and all clients recovered 5/5\n'
printf 'REALITY_DEFENDER_RESTORE=PASS\n'

reality_remove_service() { stop_server; }
nb_firewall_close_pairs() { :; }
export VLESS_REALITY_NAME=runtime
remove_vless_reality_instance
[ -z "$(reality_instance_ids)" ] || fail 'REALITY runtime test formal removal state cleanup'
[ ! -e "$config" ] && [ ! -e "$key_file" ] || fail 'REALITY runtime test formal removal secret cleanup'
[ ! -e "$NOBRAND_XRAY_ASSET_DIR" ] || fail 'REALITY runtime test formal removal Xray asset cleanup'
if nb_port_is_listening TCP "$defender_port"; then
  fail 'REALITY runtime test formal removal left defender listener'
fi
if reality_defender_port_owner "$defender_port" >/dev/null 2>&1; then
  fail 'REALITY runtime test formal removal left defender ownership'
fi
printf 'REALITY_DEFENDER_REMOVE_CLEANUP=PASS\n'

pass 'VLESS REALITY exact Xray/Mihomo/sing-box local runtime, no-direct, throughput, restart, Doctor, backup/restore, and cleanup'
