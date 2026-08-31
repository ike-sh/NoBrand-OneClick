#!/usr/bin/env bash
# 由 platform-smoke.sh 在各发行版容器内调用；只验证不需要 init/firewall 权限的平台边界。
set -Eeuo pipefail

bash -n /work/install-nobrand.sh
platform_fixture="$(mktemp -d)"
sshd_pid=""
cleanup() {
  [ -z "$sshd_pid" ] || kill "$sshd_pid" >/dev/null 2>&1 || true
  [ -z "$sshd_pid" ] || wait "$sshd_pid" >/dev/null 2>&1 || true
  rm -rf -- "$platform_fixture"
}
trap cleanup EXIT
export NOBRAND_STATE_DIR="$platform_fixture/nobrand-oneclick/state"
export NOBRAND_CONFIG_DIR="$platform_fixture/nobrand-oneclick/config"
export NOBRAND_LIB_DIR="$platform_fixture/nobrand-oneclick/lib"
export NOBRAND_SSH_CONFIG_MAIN="$platform_fixture/sshd_config"
export NOBRAND_SSH_CONFIG_DROPIN="$platform_fixture/sshd_config.d/90-nobrand-ssh-tunnel.conf"
export MITA_SOURCE_ONLY=1
# shellcheck source=install-nobrand.sh
source /work/install-nobrand.sh
trap - ERR

test "$SCRIPT_VERSION" = 3.1.0
test "$SCRIPT_NAME|$SCRIPT_REPO" = 'NoBrand-OneClick|ike-sh/NoBrand-OneClick'
case "$(detect_pkg_manager)" in
  deb|rpm|alpine) ;;
  *) echo "unsupported package-manager detection" >&2; exit 1 ;;
esac

apply_profile_values iplc
test "$PROFILE|$PROTOCOL|$MTU|$TRAFFIC_PATTERN|$LOW_ENTROPY_MODE" = \
  'iplc|TCP|1400|off|LOW_ENTROPY_MODE_OFF'
apply_profile_values balanced
test "$(infer_profile_from_values)" = balanced
MTU=1390
profile_reconcile_metadata
test "$PROFILE" = custom

valid_advertise_host 203.0.113.10
valid_advertise_host 2001:db8::1
valid_advertise_host cm-entry.example.com
if valid_advertise_host 'https://cm-entry.example.com'; then
  echo 'URL unexpectedly accepted as advertise host' >&2
  exit 1
fi

PORT=17353 ADVERTISE_HOST=203.0.113.173 ADVERTISE_PORT=17353
if client_endpoint_is_independent 203.0.113.173; then
  echo 'same public endpoint unexpectedly treated as independent' >&2
  exit 1
fi
PORT=30000 ADVERTISE_HOST=cm-entry.example.com ADVERTISE_PORT=10086
client_endpoint_is_independent 203.0.113.173

installed_version(){ echo 3.35.0; }
mita_supports_traffic_pattern(){ return 0; }
mita_supports_low_entropy(){ return 0; }
export USERNAME=platform PASSWORD=platform-pass PROTOCOL=TCP PORT=30000 PORT_RANGE=""
export MTU=1400 MTU_POLICY=safe PROFILE=iplc TRAFFIC_PATTERN=off TRAFFIC_SEED=""
export LOW_ENTROPY_MODE=LOW_ENTROPY_MODE_OFF
export MULTIPLEXING=MULTIPLEXING_OFF HANDSHAKE_MODE=HANDSHAKE_NO_WAIT
export ADVERTISE_HOST=cm-entry.example.com ADVERTISE_PORT=10086

link="$(generate_share_link_for "$ADVERTISE_HOST" TCP)"
grep -q '@cm-entry.example.com?' <<<"$link"
grep -q 'port=10086' <<<"$link"
json="$(build_client_json_for "$ADVERTISE_HOST" TCP)"
python3 -c 'import json,sys; s=json.load(sys.stdin)["profiles"][0]["servers"][0]; assert s["ipAddress"]=="" and s["domainName"]=="cm-entry.example.com" and s["portBindings"][0]["port"]==10086' <<<"$json"
yaml="$(build_clash_yaml_full "$ADVERTISE_HOST")"
grep -q 'server: "cm-entry.example.com"' <<<"$yaml"
grep -q 'port: 10086' <<<"$yaml"
cfg="$(write_server_config)"
python3 -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); raw=open(p).read(); assert d["portBindings"]==[{"port":30000,"protocol":"TCP"}] and "cm-entry.example.com" not in raw and "10086" not in raw' "$cfg"
rm -f "$cfg"

# Real OpenSSH platform boundary: native path/mechanism detection, actual
# system-account creation, policy syntax/effective semantics, and SIGHUP reload.
NOBRAND_SSHD_BIN="$(command -v sshd 2>/dev/null || true)"
[ -n "$NOBRAND_SSHD_BIN" ] && [ -x "$NOBRAND_SSHD_BIN" ] \
  || { echo 'OpenSSH sshd test dependency missing' >&2; exit 1; }
export NOBRAND_SSHD_BIN
native_sshd_config=/etc/ssh/sshd_config
native_dropin=/etc/ssh/sshd_config.d/90-nobrand-ssh-tunnel.conf
saved_main="$NOBRAND_SSH_CONFIG_MAIN"
saved_dropin="$NOBRAND_SSH_CONFIG_DROPIN"
NOBRAND_SSH_CONFIG_MAIN="$native_sshd_config"
NOBRAND_SSH_CONFIG_DROPIN="$native_dropin"
native_strategy='marker-block'
ssh_tunnel_dropin_supported && native_strategy=dropin
NOBRAND_SSH_CONFIG_MAIN="$saved_main"
NOBRAND_SSH_CONFIG_DROPIN="$saved_dropin"

mkdir -p "$platform_fixture/host" /run/sshd
chmod 0755 /run/sshd
ssh-keygen -q -t ed25519 -N '' -f "$platform_fixture/host/ssh_host_ed25519_key"
sshd_port="$(python3 - <<'PY'
import socket
with socket.socket() as sock:
    sock.bind(("127.0.0.1", 0))
    print(sock.getsockname()[1])
PY
)"
cat >"$NOBRAND_SSH_CONFIG_MAIN" <<EOF
Port ${sshd_port}
ListenAddress 127.0.0.1
PidFile /run/sshd.pid
HostKey ${platform_fixture}/host/ssh_host_ed25519_key
StrictModes no
PermitRootLogin no
PubkeyAuthentication yes
PasswordAuthentication no
KbdInteractiveAuthentication no
UseDNS no
X11Forwarding no
AllowAgentForwarding no
PermitTunnel no
PermitUserRC no
Subsystem sftp internal-sftp
EOF
chmod 0600 "$NOBRAND_SSH_CONFIG_MAIN"
ssh_tunnel_sshd_test "$NOBRAND_SSH_CONFIG_MAIN"
"$NOBRAND_SSHD_BIN" -D -e -f "$NOBRAND_SSH_CONFIG_MAIN" \
  >"$platform_fixture/sshd.log" 2>&1 &
sshd_pid=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do
  kill -0 "$sshd_pid" 2>/dev/null && break
  sleep 0.1
done
kill -0 "$sshd_pid" 2>/dev/null || {
  sed -n '1,80p' "$platform_fixture/sshd.log" >&2 || true
  exit 1
}

nb_init_state_layout
ssh_tunnel_create_group
ssh_tunnel_generate_state "$NOBRAND_SSH_STATE_FILE" custom 127.0.0.1 "$sshd_port" \
  "$sshd_port" marker-block "$NOBRAND_SSH_CONFIG_MAIN" '[]' 2026-08-30T00:00:00Z
account_id="$(ssh_tunnel_add_user_internal platform)"
linux_user="$(jq -r --arg id "$account_id" '.users[] | select(.account_id==$id) | .linux_user' \
  "$NOBRAND_SSH_STATE_FILE")"
ssh_tunnel_user_identity_valid "$(ssh_tunnel_resolve_user_json platform)"
NOBRAND_SSH_WATCHDOG_DISABLED=1 ssh_tunnel_apply_policy "$linux_user" platform-test >/dev/null
ssh_tunnel_sshd_test "$NOBRAND_SSH_CONFIG_MAIN"
ssh_tunnel_effective_policy_valid "$NOBRAND_SSH_CONFIG_MAIN" "$linux_user"
detected_service="$(ssh_tunnel_detect_service)"
case "$detected_service" in sighup\|*) ;; *) echo "unexpected SSH reload mechanism: $detected_service" >&2; exit 1 ;; esac
ssh_tunnel_reload
kill -0 "$sshd_pid"
ssh_tunnel_delete_user_internal platform
rm -f "$NOBRAND_SSH_GROUP_MARKER"
ssh_tunnel_delete_group
printf 'platform-ssh: PASS (sshd=%s, config=%s, reload=sighup, account=system-user)\n' \
  "$NOBRAND_SSHD_BIN" "$native_strategy"

echo "platform-case: PASS ($(detect_pkg_manager))"
