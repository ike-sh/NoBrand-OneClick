#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/testlib.sh"

if [ "${NOBRAND_MIERU_RUNTIME_INNER:-0}" != 1 ]; then
  [ "$(id -u)" -eq 0 ] \
    || fail 'real Mieru latest-stable runtime test requires root isolation'
  command -v unshare >/dev/null 2>&1 \
    || fail 'real Mieru latest-stable runtime test requires unshare'
  exec unshare -m env \
    NOBRAND_MIERU_RUNTIME_INNER=1 \
    "NOBRAND_RUNTIME_CACHE=${NOBRAND_RUNTIME_CACHE:-/tmp/nobrand-runtime-cache}" \
    bash "$0"
fi

fixture="$(mktemp -d)"
server_pid="" client_pid="" target_pid=""
target_address_added=0
target_host=1.1.1.254
server_socket="$fixture/run/mita.sock"
server_pid_file="$fixture/run/mita.pid"
server_config="$fixture/server.json"
client_config="$fixture/client.json"
client_home="$fixture/client-home"

stop_client() {
  if [ -x "${client_bin:-}" ] && [ -f "$client_config" ]; then
    HOME="$client_home" MIERU_CONFIG_JSON_FILE="$client_config" \
      "$client_bin" stop >/dev/null 2>&1 || true
  fi
  [ -z "$client_pid" ] || kill "$client_pid" >/dev/null 2>&1 || true
  [ -z "$client_pid" ] || wait "$client_pid" >/dev/null 2>&1 || true
  client_pid=""
}

stop_server() {
  if [ -z "$server_pid" ] && [ -s "$server_pid_file" ]; then
    server_pid="$(sed -n '1p' "$server_pid_file")"
  fi
  if [ -x "${MITA_BIN:-}" ] && [ -f "$server_config" ]; then
    MITA_UDS_PATH="$server_socket" MITA_CONFIG_JSON_FILE="$server_config" \
      "$MITA_BIN" stop >/dev/null 2>&1 || true
  fi
  [ -z "$server_pid" ] || kill "$server_pid" >/dev/null 2>&1 || true
  [ -z "$server_pid" ] || wait "$server_pid" >/dev/null 2>&1 || true
  server_pid=""
  rm -f "$server_socket" "$server_pid_file"
}

cleanup() {
  stop_client
  stop_server
  [ -z "$target_pid" ] || kill "$target_pid" >/dev/null 2>&1 || true
  [ -z "$target_pid" ] || wait "$target_pid" >/dev/null 2>&1 || true
  [ "$target_address_added" -eq 0 ] \
    || ip address del "${target_host}/32" dev lo >/dev/null 2>&1 || true
  mountpoint -q /etc/passwd && umount /etc/passwd || true
  mountpoint -q /etc/group && umount /etc/group || true
  rm -rf -- "$fixture"
}
trap cleanup EXIT

for command_name in curl jq tar sha256sum python3 ss ip mount mountpoint umount getent; do
  command -v "$command_name" >/dev/null 2>&1 \
    || fail "Mieru latest-stable runtime dependency missing: $command_name"
done

free_tcp_port() {
  python3 - <<'PY'
import socket
with socket.socket() as stream:
    stream.bind(("127.0.0.1", 0))
    print(stream.getsockname()[1])
PY
}

wait_tcp() {
  local port="$1" attempts="${2:-150}"
  for ((index=0; index<attempts; index++)); do
    ss -lntH "sport = :${port}" | grep -q . && return 0
    sleep 0.1
  done
  return 1
}

wait_socket() {
  local path="$1" attempts="${2:-150}"
  for ((index=0; index<attempts; index++)); do
    [ -S "$path" ] && return 0
    sleep 0.1
  done
  return 1
}

runtime_cache="${NOBRAND_RUNTIME_CACHE:-/tmp/nobrand-runtime-cache}"
mkdir -p "$runtime_cache"

service_uid=49120
service_gid=49120
getent passwd "$service_uid" >/dev/null 2>&1 \
  && fail "Mieru runtime test UID already exists: $service_uid"
getent group "$service_gid" >/dev/null 2>&1 \
  && fail "Mieru runtime test GID already exists: $service_gid"
cp /etc/passwd "$fixture/passwd"
cp /etc/group "$fixture/group"
printf 'mita:x:%s:%s:Mieru runtime fixture:/nonexistent:/usr/sbin/nologin\n' \
  "$service_uid" "$service_gid" >>"$fixture/passwd"
printf 'mita:x:%s:\n' "$service_gid" >>"$fixture/group"
mount --bind "$fixture/passwd" /etc/passwd
mount --bind "$fixture/group" /etc/group
getent passwd mita >/dev/null || fail 'isolated Mieru service account lookup'

official_release_asset() {
  local version="$1" asset="$2" output="$3"
  local metadata="$fixture/release-${version}.json" release count checksum_asset
  local url checksum_url digest actual manifest_digest manifest_name
  if [ ! -s "$metadata" ]; then
    curl -fsSL --connect-timeout 15 --max-time 90 --retry 3 --retry-delay 2 \
      -H 'Accept: application/vnd.github+json' \
      -H 'X-GitHub-Api-Version: 2022-11-28' \
      -H 'User-Agent: NoBrand-OneClick' \
      "https://api.github.com/repos/enfein/mieru/releases/tags/v${version}" \
      -o "$metadata"
  fi
  release="$(jq -ce --arg tag "v${version}" \
    'select(type=="object" and .tag_name==$tag and .draft==false and .prerelease==false)' \
    "$metadata")" || return 1
  checksum_asset="${asset}.sha256.txt"
  count="$(jq -r --arg asset "$asset" \
    '[.assets[]|select(.name==$asset)]|length' <<<"$release")"
  [ "$count" = 1 ] || return 1
  count="$(jq -r --arg asset "$checksum_asset" \
    '[.assets[]|select(.name==$asset)]|length' <<<"$release")"
  [ "$count" = 1 ] || return 1
  url="$(jq -r --arg asset "$asset" \
    '.assets[]|select(.name==$asset)|.browser_download_url' <<<"$release")"
  checksum_url="$(jq -r --arg asset "$checksum_asset" \
    '.assets[]|select(.name==$asset)|.browser_download_url' <<<"$release")"
  digest="$(jq -r --arg asset "$asset" \
    '.assets[]|select(.name==$asset)|.digest // empty' <<<"$release")"
  digest="${digest#sha256:}"
  [[ "$digest" =~ ^[0-9a-f]{64}$ ]] || return 1
  [ "$url" = "https://github.com/enfein/mieru/releases/download/v${version}/${asset}" ] \
    || return 1
  [ "$checksum_url" = "${url}.sha256.txt" ] || return 1
  if [ ! -s "$output" ] \
     || [ "$(sha256sum "$output" | awk '{print $1}')" != "$digest" ]; then
    curl -fL --connect-timeout 15 --max-time 300 --retry 3 --retry-delay 2 \
      "$url" -o "$output"
  fi
  actual="$(sha256sum "$output" | awk '{print $1}')"
  [ "$actual" = "$digest" ] || return 1
  read -r manifest_digest manifest_name < <(
    curl -fsSL --connect-timeout 15 --max-time 90 --retry 3 --retry-delay 2 \
      "$checksum_url" | tr -d '\r'
  )
  manifest_name="${manifest_name#\*}"
  [ "$manifest_digest" = "$digest" ] && [ "$manifest_name" = "$asset" ]
}

export NOBRAND_STATE_DIR="$fixture/nobrand/state"
export NOBRAND_CONFIG_DIR="$fixture/nobrand/config"
export NOBRAND_LIB_DIR="$fixture/nobrand/lib"
export NOBRAND_LEGACY_MIERU_STATE_DIR="$fixture/legacy"
source_installer

server_port="$(free_tcp_port)"
target_port="$(free_tcp_port)"
CLIENT_RPC_PORT="$(free_tcp_port)"
CLIENT_SOCKS5_PORT="$(free_tcp_port)"
mkdir -p "$fixture/run" "$fixture/web" "$client_home"
printf '%s\n' 'nobrand-mieru-runtime' >"$fixture/web/probe"
ip -4 address show dev lo | grep -qF " ${target_host}/32" \
  && fail "controlled public-looking loopback address is already present: ${target_host}"
ip address add "${target_host}/32" dev lo
target_address_added=1
python3 -m http.server "$target_port" --bind "$target_host" \
  --directory "$fixture/web" >"$fixture/target.log" 2>&1 &
target_pid=$!
wait_tcp "$target_port" || fail 'controlled Mieru HTTP target startup'

start_server() {
  stop_server
  MITA_UDS_PATH="$server_socket" MITA_CONFIG_JSON_FILE="$server_config" \
    "$MITA_BIN" run >"$fixture/mita.log" 2>&1 &
  server_pid=$!
  printf '%s\n' "$server_pid" >"$server_pid_file"
  wait_socket "$server_socket" || {
    sed -n '1,160p' "$fixture/mita.log" >&2 || true
    return 1
  }
  if ! MITA_UDS_PATH="$server_socket" MITA_CONFIG_JSON_FILE="$server_config" \
      "$MITA_BIN" start >>"$fixture/mita.log" 2>&1; then
    sed -n '1,160p' "$fixture/mita.log" >&2 || true
    return 1
  fi
  wait_tcp "$server_port"
}

start_client() {
  stop_client
  HOME="$client_home" MIERU_CONFIG_JSON_FILE="$client_config" \
    "$client_bin" run >"$fixture/mieru.log" 2>&1 &
  client_pid=$!
  wait_tcp "$CLIENT_RPC_PORT" || {
    sed -n '1,160p' "$fixture/mieru.log" >&2 || true
    return 1
  }
  if ! HOME="$client_home" MIERU_CONFIG_JSON_FILE="$client_config" \
      "$client_bin" start >>"$fixture/mieru.log" 2>&1; then
    sed -n '1,160p' "$fixture/mieru.log" >&2 || true
    return 1
  fi
  wait_tcp "$CLIENT_SOCKS5_PORT"
}

proxy_5_of_5() {
  local index body
  for index in 1 2 3 4 5; do
    body="$(curl -fsS --max-time 20 --noproxy '' \
      --socks5-hostname "127.0.0.1:${CLIENT_SOCKS5_PORT}" \
      "http://${target_host}:${target_port}/probe")" || return 1
    [ "$body" = nobrand-mieru-runtime ] || return 1
  done
}

print_runtime_logs() {
  printf '%s\n' '--- Mita server config ---' >&2
  jq 'del(.users[].password)' "$server_config" >&2 || true
  printf '%s\n' '--- Mieru client config ---' >&2
  jq 'del(.profiles[].user.password)' "$client_config" >&2 || true
  printf '%s\n' '--- Mita runtime log ---' >&2
  sed -n '1,200p' "$fixture/mita.log" >&2 || true
  printf '%s\n' '--- Mieru runtime log ---' >&2
  sed -n '1,200p' "$fixture/mieru.log" >&2 || true
  printf '%s\n' '--- HTTP target log ---' >&2
  sed -n '1,120p' "$fixture/target.log" >&2 || true
}

write_runtime_state() {
  cat >"$MITA_STATE" <<EOF
MIERU_CHANNEL=stable
MIERU_VERSION=${MIERU_VERSION}
PROTOCOL=TCP
PORT=${server_port}
USERNAME=${USERNAME}
PASSWORD=${PASSWORD}
EOF
  chmod 0600 "$MITA_STATE"
}

install_package() {
  local package="$1" package_manager="$2" extracted binary
  [ "$package_manager" = alpine ] || return 1
  extracted="$(mktemp -d)" || return 1
  tar -xzf "$package" -C "$extracted" || { rm -rf -- "$extracted"; return 1; }
  binary="$(find "$extracted" -type f -name mita -print -quit)"
  [ -n "$binary" ] || { rm -rf -- "$extracted"; return 1; }
  install -d -m 0755 "$NOBRAND_BIN_DIR" "$(dirname "$MITA_MARKER")"
  install -m 0755 "$binary" "$MITA_BIN"
  : >"$MITA_MARKER"
  chmod 0600 "$MITA_MARKER"
  rm -rf -- "$extracted"
}

detect_pkg_manager() { printf alpine; }
ensure_management_dependencies() { :; }
mieru_prepare_noninteractive_ingress_endpoint() { :; }
ensure_config_noninteractive() { :; }
add_op_user() { :; }
warn_traffic_unsupported() { :; }
warn_low_entropy_unsupported() { :; }
offer_bbr_fq() { :; }
print_summary() { :; }
install_self_script() { :; }

install_fresh_isolated() {
  local generated
  generated="$(write_server_config)" || return 1
  install -m 0600 "$generated" "$server_config"
  rm -f "$generated"
  cat >"$MITA_USERS_STATE" <<EOF
{
  "version": 2,
  "deployment_model": "isolated-v2",
  "protocol": "TCP",
  "users": [
    {
      "instance_id": "u0000000000000001",
      "name": "${USERNAME}",
      "password": "${PASSWORD}",
      "port": ${server_port},
      "enabled": true
    }
  ]
}
EOF
  chmod 0600 "$MITA_USERS_STATE"
  write_runtime_state
  start_server
}

USERNAME=runtime-user
PASSWORD='runtime-password-unchanged'
PORT="$server_port"
PORT_RANGE=""
PROTOCOL=TCP
MTU=1400
PROFILE=balanced
MULTIPLEXING=MULTIPLEXING_OFF
HANDSHAKE_MODE=HANDSHAKE_NO_WAIT
TRAFFIC_PATTERN=off
TRAFFIC_SEED=""
LOW_ENTROPY_MODE=LOW_ENTROPY_MODE_OFF
ADVERTISE_HOST=127.0.0.1
ADVERTISE_PORT="$server_port"
MIERU_CHANNEL=stable
MIERU_VERSION=""
MIERU_CHANNEL_CLI=0
MIERU_VERSION_CLI=0
USERNAME_CLI=1
PASSWORD_CLI=1
PORT_CLI=1
PORT_RANGE_CLI=0
PROTOCOL_CLI=1
MTU_CLI=1
ADVERTISE_CLI=1
PROFILE_CLI=1
MULTIPLEXING_CLI=1
HANDSHAKE_CLI=1
TRAFFIC_CLI=1
LOW_ENTROPY_CLI=1
YES=1
DRY_RUN=0
# The generated installer is sourced dynamically by testlib; do_install consumes
# these globals even though per-file static analysis cannot follow that source.
: "$PORT" "$PORT_RANGE" "$PROTOCOL" "$MTU" "$PROFILE" "$MULTIPLEXING" \
  "$HANDSHAKE_MODE" "$TRAFFIC_PATTERN" "$TRAFFIC_SEED" "$LOW_ENTROPY_MODE" \
  "$ADVERTISE_HOST" "$ADVERTISE_PORT" "$USERNAME_CLI" "$PASSWORD_CLI" \
  "$PORT_CLI" "$PORT_RANGE_CLI" "$PROTOCOL_CLI" "$MTU_CLI" \
  "$ADVERTISE_CLI" "$PROFILE_CLI" "$MULTIPLEXING_CLI" "$HANDSHAKE_CLI" \
  "$TRAFFIC_CLI" "$LOW_ENTROPY_CLI" "$YES" "$DRY_RUN"

do_install >/dev/null
[ "$MIERU_RUNTIME_RESOLUTION_FALLBACK" -eq 0 ] \
  || fail 'fresh default Mieru runtime unexpectedly used fallback metadata'
fresh_version="$MIERU_RUNTIME_RESOLVED_VERSION"
assert_eq "$fresh_version" "$(mieru_runtime_version "$MITA_BIN")" \
  'fresh default managed Mita exact version'

client_asset="mieru_${fresh_version}_linux_amd64.tar.gz"
client_archive="$runtime_cache/$client_asset"
official_release_asset "$fresh_version" "$client_asset" "$client_archive" \
  || fail 'official Mieru client release asset/digest/checksum'
client_extract="$fixture/client-extract"
mkdir -p "$client_extract"
tar -xzf "$client_archive" -C "$client_extract"
client_bin="$(find "$client_extract" -type f -name mieru -print -quit)"
[ -n "$client_bin" ] && chmod 0755 "$client_bin" || fail 'official Mieru client binary extraction'
assert_eq "$fresh_version" "$(mieru_runtime_version "$client_bin")" \
  'official Mieru client exact version'
build_client_json_for 127.0.0.1 TCP >"$client_config"
start_client || fail 'official Mieru client startup after fresh default install'
proxy_5_of_5 || {
  print_runtime_logs
  fail 'fresh latest-stable Mieru official-client 5/5 data plane'
}
printf 'MIERU_LATEST_FRESH_INSTALL=PASS\n'
printf 'MIERU_FRESH_DEFAULT_VERSION=%s\n' "$fresh_version"

# Recreate the qualified pre-upgrade baseline with the official 3.35.0 server,
# then invoke NoBrand's upgrade transaction without a destination-version pin.
stop_server
old_asset=mita_3.35.0_linux_amd64.tar.gz
old_archive="$runtime_cache/$old_asset"
official_release_asset 3.35.0 "$old_asset" "$old_archive" \
  || fail 'official Mita 3.35.0 upgrade-baseline asset/digest/checksum'
install_package "$old_archive" alpine
assert_eq 3.35.0 "$(mieru_runtime_version "$MITA_BIN")" 'official pre-upgrade runtime'
MIERU_VERSION=3.35.0
write_runtime_state
start_server || fail 'official Mita 3.35.0 pre-upgrade server startup'
proxy_5_of_5 || {
  print_runtime_logs
  fail 'official Mita 3.35.0 pre-upgrade 5/5 data plane'
}

users_before="$(sha256sum "$MITA_USERS_STATE" | awk '{print $1}')"
server_before="$(sha256sum "$server_config" | awk '{print $1}')"
client_before="$(sha256sum "$client_config" | awk '{print $1}')"
load_install_state() {
  # shellcheck disable=SC1090
  source "$MITA_STATE"
}
mita_v3_install_state_valid() { [ -s "$MITA_STATE" ]; }
isolated_stop_all() { stop_server; }
apply_users_config() { start_server; }
reconcile_isolated_instances() { start_server; }
verify_mita_running() {
  local running_pid
  running_pid="$(sed -n '1p' "$server_pid_file" 2>/dev/null || true)"
  [ -n "$running_pid" ] && kill -0 "$running_pid" && wait_tcp "$server_port" 50
}
save_install_state() { write_runtime_state; }

MIERU_CHANNEL=stable
MIERU_VERSION=""
MIERU_CHANNEL_CLI=1
MIERU_VERSION_CLI=0
: "$MIERU_CHANNEL" "$MIERU_CHANNEL_CLI" "$MIERU_VERSION_CLI"
do_upgrade >/dev/null
[ "$MIERU_RUNTIME_RESOLUTION_FALLBACK" -eq 0 ] \
  || fail 'explicit Mieru upgrade unexpectedly used fallback metadata'
assert_eq "$fresh_version" "$(mieru_runtime_version "$MITA_BIN")" \
  'resolver-selected upgrade managed Mita exact version'
assert_eq "$users_before" "$(sha256sum "$MITA_USERS_STATE" | awk '{print $1}')" \
  'upgrade preserves user state, port, and credentials'
assert_eq "$server_before" "$(sha256sum "$server_config" | awk '{print $1}')" \
  'upgrade preserves server config'
assert_eq "$client_before" "$(sha256sum "$client_config" | awk '{print $1}')" \
  'upgrade preserves client config'
assert_eq runtime-user "$(jq -r '.users[0].name' "$MITA_USERS_STATE")" \
  'upgrade preserves username'
assert_eq runtime-password-unchanged "$(jq -r '.users[0].password' "$MITA_USERS_STATE")" \
  'upgrade preserves credential'
assert_eq "$server_port" "$(jq -r '.users[0].port' "$MITA_USERS_STATE")" \
  'upgrade preserves port'
proxy_5_of_5 || {
  print_runtime_logs
  fail 'resolver-selected latest-stable upgrade 5/5 data plane'
}

printf 'MIERU_LATEST_UPGRADE=PASS\n'
printf 'MIERU_EXPLICIT_UPGRADE_VERSION=%s\n' "$fresh_version"
printf 'MIERU_RUNTIME_VERSION_MATCH=PASS\n'
pass 'real default latest-stable Mieru fresh install, 3.35 upgrade, state preservation, and official-client data plane'
