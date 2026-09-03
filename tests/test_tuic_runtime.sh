#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/testlib.sh"

fixture="$(mktemp -d)"
server_pid="" client_pid="" target_tcp_pid="" target_udp_pid="" mihomo_pid="" relay_pid=""
cleanup() {
  for pid in "$mihomo_pid" "$client_pid" "$server_pid" "$target_tcp_pid" "$target_udp_pid" "$relay_pid"; do
    [ -z "$pid" ] || kill "$pid" >/dev/null 2>&1 || true
  done
  wait >/dev/null 2>&1 || true
  rm -rf -- "$fixture"
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
source_installer
nb_init_state_layout

for command_name in curl jq openssl python3 ss gzip sha256sum; do
  command -v "$command_name" >/dev/null 2>&1 \
    || fail "TUIC runtime dependency missing: $command_name"
done
tuic_protocol_scope_valid || fail 'TUIC v5-only protocol scope constants'

free_port() {
  local protocol="$1"
  python3 - "$protocol" <<'PY'
import socket, sys
kind = socket.SOCK_DGRAM if sys.argv[1] == "udp" else socket.SOCK_STREAM
with socket.socket(socket.AF_INET, kind) as sock:
    sock.bind(("127.0.0.1", 0))
    print(sock.getsockname()[1])
PY
}

wait_tcp() {
  local port="$1" attempts="${2:-50}"
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

runtime="$fixture/sing-box"
tuic_download_runtime_candidate "$runtime" stable "" \
  || fail 'download and verify official sing-box stable runtime'
assert_eq "$TESTED_SING_BOX_SERVER_VERSION" "$(tuic_runtime_version "$runtime")" \
  'official sing-box runtime version'
NOBRAND_SING_BOX_BIN="$runtime"
export NOBRAND_SING_BOX_BIN

server_port="$(free_port udp)"
transport_port="$(free_port udp)"
tcp_target_port="$(free_port tcp)"
udp_target_port="$(free_port udp)"
id=t1111111111111111
cert="$(tuic_cert_file "$id")"
key="$(tuic_key_file "$id")"
state="$(tuic_state_file "$id")"
config="$(tuic_config_file "$id")"
mkdir -p "$(dirname "$state")" "$(dirname "$config")"
tuic_generate_certificate "$cert" "$key" www.microsoft.com
alice_uuid=11111111-1111-4111-8111-111111111111
bob_uuid=22222222-2222-4222-8222-222222222222
alice_password=alice-runtime-secret
bob_password=bob-runtime-secret
users="[$(tuic_user_json u1111111111111111 alice "$alice_uuid" "$alice_password"),$(tuic_user_json u2222222222222222 bob "$bob_uuid" "$bob_password")]"
tuic_generate_server_config "$config" "$id" 127.0.0.1 "$server_port" "$cert" "$key" \
  www.microsoft.com "$users"
tuic_generate_state "$state" "$id" runtime 127.0.0.1 "$server_port" custom \
  127.0.0.1 "$transport_port" www.microsoft.com stable "$TESTED_SING_BOX_SERVER_VERSION" \
  "$cert" "$key" "$users" 2026-08-30T00:00:00Z
tuic_validate_config "$config" "$runtime" || fail 'official sing-box server config check'

python3 "$TEST_ROOT/tests/helpers/socks5_probe.py" echo-server --protocol tcp \
  --port "$tcp_target_port" >"$fixture/tcp-target.log" 2>&1 &
target_tcp_pid=$!
python3 "$TEST_ROOT/tests/helpers/socks5_probe.py" echo-server --protocol udp \
  --port "$udp_target_port" >"$fixture/udp-target.log" 2>&1 &
target_udp_pid=$!
wait_tcp "$tcp_target_port" || fail 'controlled TCP echo target startup'
relay_count_file="$fixture/transport.count"
python3 "$TEST_ROOT/tests/helpers/udp_recording_relay.py" \
  --listen-port "$transport_port" --target-port "$server_port" \
  --count-file "$relay_count_file" >"$fixture/transport-relay.log" 2>&1 &
relay_pid=$!
sleep 0.2
kill -0 "$relay_pid" 2>/dev/null || fail 'controlled TUIC transport relay startup'

start_server() {
  stop_process "$server_pid"
  "$runtime" run -c "$config" >"$fixture/server.log" 2>&1 &
  server_pid=$!
  sleep 0.5
  kill -0 "$server_pid" 2>/dev/null || {
    sed -n '1,100p' "$fixture/server.log" >&2 || true
    fail 'real TUIC server startup'
  }
}

start_singbox_client() {
  local client_config="$1" log="$2"
  stop_process "$client_pid"
  "$runtime" check -c "$client_config" >/dev/null || fail 'sing-box TUIC client config check'
  "$runtime" run -c "$client_config" >"$log" 2>&1 &
  client_pid=$!
  wait_tcp 1080 || {
    sed -n '1,100p' "$log" >&2 || true
    fail 'sing-box TUIC client startup'
  }
}

probe_singbox() {
  python3 "$TEST_ROOT/tests/helpers/socks5_probe.py" tcp --proxy-port 1080 \
    --target-port "$tcp_target_port" --size 131072
  python3 "$TEST_ROOT/tests/helpers/socks5_probe.py" udp --proxy-port 1080 \
    --target-port "$udp_target_port" --sizes 64 512 1200 1400
}

start_server
alice_client="$fixture/alice.json"
bob_client="$fixture/bob.json"
tuic_export_singbox "$id" alice >"$alice_client"
tuic_export_singbox "$id" bob >"$bob_client"
start_singbox_client "$alice_client" "$fixture/alice.log"
probe_singbox || fail 'sing-box Alice TUIC TCP/UDP data plane'
start_singbox_client "$bob_client" "$fixture/bob.log"
probe_singbox || fail 'sing-box Bob TUIC TCP/UDP data plane'
printf '[PASS] sing-box TUIC two-user TCP and SOCKS5 UDP 64/512/1200/1400\n'

wrong_client="$fixture/wrong.json"
jq --arg password "$bob_password" '.outbounds[0].password=$password' "$alice_client" >"$wrong_client"
start_singbox_client "$wrong_client" "$fixture/wrong.log"
if python3 "$TEST_ROOT/tests/helpers/socks5_probe.py" tcp --proxy-port 1080 \
     --target-port "$tcp_target_port" --size 64 --timeout 3 >/dev/null 2>&1; then
  fail 'TUIC mismatched UUID/password must be rejected'
fi
printf '[PASS] TUIC UUID/password isolation\n'

old_server_hash="$(sha256sum "$config")"
old_users_hash="$(jq -cS .users "$state" | sha256sum)"
old_server_pid="$server_pid"
backup_archive="$fixture/tuic-backup.tar.gz"
nobrand_backup_create "$backup_archive" >/dev/null
assert_file_mode 600 "$backup_archive"
backup_cert_hash="$(sha256sum "$cert")"
backup_key_hash="$(sha256sum "$key")"
backup_endpoint_fields="$(jq -cS '[.advertise_mode,.advertise_host,.advertise_port]' "$state")"
tuic_set_endpoint_state "$id" localhost "$server_port"
assert_eq "$old_server_hash" "$(sha256sum "$config")" 'TUIC endpoint config isolation'
assert_eq "$old_users_hash" "$(jq -cS .users "$state" | sha256sum)" 'TUIC endpoint credential isolation'
assert_eq "$old_server_pid" "$server_pid" 'TUIC endpoint PID isolation'
kill -0 "$server_pid" || fail 'TUIC endpoint update keeps server alive'

tuic_service_active() { [ -n "$server_pid" ] && kill -0 "$server_pid" 2>/dev/null; }
tuic_service_pid() { printf '%s' "$server_pid"; }
tuic_listener_owned_by_service() {
  local _id="$1" port="$2" port_hex
  [ -n "$server_pid" ] && kill -0 "$server_pid" 2>/dev/null || return 1
  printf -v port_hex '%04X' "$port"
  grep -qi ":${port_hex}[[:space:]]" "/proc/${server_pid}/net/udp" \
    || grep -qi ":${port_hex}[[:space:]]" "/proc/${server_pid}/net/udp6"
}
tuic_service_action() {
  local _id="$1" action="$2"
  case "$action" in
    restart) start_server ;;
    start) start_server ;;
    stop) stop_process "$server_pid"; server_pid="" ;;
    *) return 1 ;;
  esac
}

old_bob_hash="$(jq -cS '.users[] | select(.name=="bob")' "$state" | sha256sum)"
old_alice_client="$fixture/alice-old.json"
tuic_export_singbox "$id" alice >"$old_alice_client"
tuic_user_rotate "$id" alice
assert_eq "$old_bob_hash" "$(jq -cS '.users[] | select(.name=="bob")' "$state" | sha256sum)" \
  'TUIC Alice rotation preserves Bob credentials'
new_alice_client="$fixture/alice-new.json"
tuic_export_singbox "$id" alice >"$new_alice_client"
start_singbox_client "$old_alice_client" "$fixture/alice-old.log"
if python3 "$TEST_ROOT/tests/helpers/socks5_probe.py" tcp --proxy-port 1080 \
     --target-port "$tcp_target_port" --size 64 --timeout 3 >/dev/null 2>&1; then
  fail 'rotated TUIC credentials must reject old client'
fi
start_singbox_client "$new_alice_client" "$fixture/alice-new.log"
probe_singbox || fail 'rotated TUIC credentials accept new client'

tuic_user_add "$id" charlie
charlie_client="$fixture/charlie.json"
tuic_export_singbox "$id" charlie >"$charlie_client"
start_singbox_client "$charlie_client" "$fixture/charlie.log"
probe_singbox || fail 'new TUIC user real data plane'
tuic_user_delete "$id" charlie
start_singbox_client "$charlie_client" "$fixture/charlie-deleted.log"
if python3 "$TEST_ROOT/tests/helpers/socks5_probe.py" tcp --proxy-port 1080 \
     --target-port "$tcp_target_port" --size 64 --timeout 3 >/dev/null 2>&1; then
  fail 'deleted TUIC credentials must be rejected'
fi
printf '[PASS] TUIC credential rotation/add/delete with other-user isolation\n'

tuic_install_service_runtime() { :; }
tuic_ensure_openrc_service() { :; }
tuic_restore_runtime() {
  [ "$(tuic_runtime_version "$runtime")" = "$TESTED_SING_BOX_SERVER_VERSION" ]
}
nb_firewall_open_pairs() { :; }
nb_firewall_close_pairs() { :; }
nobrand_backup_restore "$backup_archive" >"$fixture/restore.out"
assert_eq "$backup_cert_hash" "$(sha256sum "$cert")" 'TUIC restore preserves exact certificate'
assert_eq "$backup_key_hash" "$(sha256sum "$key")" 'TUIC restore preserves exact TLS key'
assert_eq "$old_users_hash" "$(jq -cS .users "$state" | sha256sum)" \
  'TUIC restore recovers exact two-user credentials'
assert_eq "$backup_endpoint_fields" "$(jq -cS '[.advertise_mode,.advertise_host,.advertise_port]' "$state")" \
  'TUIC restore recovers exact Display Endpoint'
start_singbox_client "$old_alice_client" "$fixture/alice-restored.log"
probe_singbox || fail 'restored TUIC credentials accept pre-backup Alice client'
start_singbox_client "$new_alice_client" "$fixture/alice-perturbed-after-restore.log"
if python3 "$TEST_ROOT/tests/helpers/socks5_probe.py" tcp --proxy-port 1080 \
     --target-port "$tcp_target_port" --size 64 --timeout 3 >/dev/null 2>&1; then
  fail 'post-backup perturbed TUIC credentials survived restore'
fi
start_singbox_client "$bob_client" "$fixture/bob-restored.log"
probe_singbox || fail 'TUIC restore preserves Bob data plane'
printf '[PASS] real TUIC backup, credential/endpoint perturbation, restore, and data plane\n'

cert_hash="$(sha256sum "$cert")"
state_credentials="$(jq -cS .users "$state" | sha256sum)"
endpoint_fields="$(jq -cS '[.advertise_mode,.advertise_host,.advertise_port]' "$state")"
tuic_service_action "$id" restart
assert_eq "$cert_hash" "$(sha256sum "$cert")" 'TUIC restart preserves certificate'
assert_eq "$state_credentials" "$(jq -cS .users "$state" | sha256sum)" 'TUIC restart preserves credentials'
assert_eq "$endpoint_fields" "$(jq -cS '[.advertise_mode,.advertise_host,.advertise_port]' "$state")" \
  'TUIC restart preserves endpoint'

# Keep the exact generated Mihomo exporter under parser and data-plane test.
mihomo_dir="$fixture/mihomo"
mkdir -p "$mihomo_dir"
tuic_export_mihomo "$id" bob >"$mihomo_dir/config.yaml"
python3 "$TEST_ROOT/tests/helpers/assert_mihomo_routing_contract.py" \
  "$mihomo_dir/config.yaml" NOBRAND >/dev/null \
  || fail 'generated Mihomo TUIC routing contract'
relay_count_before="$(cat "$relay_count_file")"
mihomo_cache="${NOBRAND_RUNTIME_CACHE:-/tmp/nobrand-runtime-cache}"
mkdir -p "$mihomo_cache"
mihomo_gzip="$mihomo_cache/mihomo-linux-amd64-v1.19.30.gz"
mihomo_sha=cf06ce2c7d1421bdbda14ee4a5b6046672dc35ebf8eecd8e77504ec3c0ed9a84
if [ ! -s "$mihomo_gzip" ] || [ "$(sha256sum "$mihomo_gzip" | awk '{print $1}')" != "$mihomo_sha" ]; then
  curl -fL --connect-timeout 10 --max-time 300 \
    'https://github.com/MetaCubeX/mihomo/releases/download/v1.19.30/mihomo-linux-amd64-v1.19.30.gz' \
    -o "$mihomo_gzip"
fi
assert_eq "$mihomo_sha" "$(sha256sum "$mihomo_gzip" | awk '{print $1}')" \
  'official Mihomo v1.19.30 gzip digest'
mihomo="$fixture/mihomo-bin"
gzip -dc "$mihomo_gzip" >"$mihomo"
chmod 0755 "$mihomo"
"$mihomo" -t -f "$mihomo_dir/config.yaml" >/dev/null \
  || fail 'generated Mihomo TUIC exporter parser validation'
stop_process "$client_pid"
client_pid=""
"$mihomo" -d "$mihomo_dir" >"$fixture/mihomo.log" 2>&1 &
mihomo_pid=$!
wait_tcp 7890 || {
  sed -n '1,120p' "$fixture/mihomo.log" >&2 || true
  fail 'Mihomo TUIC client startup'
}
python3 "$TEST_ROOT/tests/helpers/socks5_probe.py" tcp --proxy-port 7890 \
  --target-port "$tcp_target_port" --size 131072 \
  || fail 'Mihomo TUIC TCP data plane'
python3 "$TEST_ROOT/tests/helpers/socks5_probe.py" udp --proxy-port 7890 \
  --target-port "$udp_target_port" --sizes 64 512 1200 1400 \
  || fail 'Mihomo TUIC SOCKS5 UDP data plane'
relay_count_after="$(cat "$relay_count_file")"
[ "$relay_count_after" -gt "$relay_count_before" ] \
  || fail 'Mihomo TUIC transport destination packet proof'
printf '[PASS] Mihomo v1.19.30 TUIC parser, transport destination, TCP, and SOCKS5 UDP 64/512/1200/1400\n'

# The controlled echo targets remain reachable directly. Stopping only the
# TUIC server must therefore make the exported Mihomo path fail; otherwise the
# full exporter has silently bypassed its NOBRAND routing contract.
stop_process "$server_pid"
server_pid=""
if python3 "$TEST_ROOT/tests/helpers/socks5_probe.py" tcp --proxy-port 7890 \
     --target-port "$tcp_target_port" --size 64 --timeout 3 >/dev/null 2>&1; then
  fail 'Mihomo TUIC exporter allowed direct fallback with server stopped'
fi
printf '[PASS] Mihomo TUIC exporter has no direct fallback when transport is unavailable\n'

start_server
stop_process "$relay_pid"
relay_pid=""
python3 "$TEST_ROOT/tests/helpers/udp_recording_relay.py" \
  --listen-port "$transport_port" --target-port "$server_port" \
  --count-file "$relay_count_file" >"$fixture/transport-relay-restarted.log" 2>&1 &
relay_pid=$!
sleep 0.2
kill -0 "$relay_pid" 2>/dev/null || fail 'TUIC transport relay recovery'
stop_process "$mihomo_pid"
mihomo_pid=""
"$mihomo" -d "$mihomo_dir" >"$fixture/mihomo-restarted.log" 2>&1 &
mihomo_pid=$!
wait_tcp 7890 || fail 'Mihomo TUIC client restart after transport recovery'
python3 "$TEST_ROOT/tests/helpers/socks5_probe.py" tcp --proxy-port 7890 \
  --target-port "$tcp_target_port" --size 131072 \
  || fail 'Mihomo TUIC data plane after transport recovery'
printf '[PASS] Mihomo TUIC exporter transport recovery\n'

stop_process "$mihomo_pid"
mihomo_pid=""
external_sing_box="$fixture/external-sing-box"
printf '%s\n' 'external-sing-box-must-remain' >"$external_sing_box"
external_hash="$(sha256sum "$external_sing_box")"
tuic_remove_service() { tuic_service_action "$1" stop; }
nb_service_manager() { printf none; }
TUIC_NAME=runtime remove_tuic_instance
[ -z "$(tuic_instance_ids)" ] || fail 'TUIC uninstall left instance state'
[ ! -e "$config" ] || fail 'TUIC uninstall left instance config'
[ ! -e "$NOBRAND_SING_BOX_BIN" ] || fail 'TUIC uninstall left managed sing-box runtime'
[ -z "$server_pid" ] || fail 'TUIC uninstall left managed server process'
assert_eq "$external_hash" "$(sha256sum "$external_sing_box")" \
  'TUIC uninstall preserves external sing-box resource'
printf '[PASS] real TUIC uninstall removes managed runtime/config/state/service and preserves external sing-box\n'

pass 'real official sing-box and Mihomo TUIC v5 runtime integration'
