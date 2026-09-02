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

test "$SCRIPT_VERSION" = 3.2.0
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

# Exercise permissive/strict Profile parser and resolved-state generation on
# every supported distribution without touching container addresses or routes.
export NOBRAND_TEST_INTERFACE_ROWS=$'eth0|192.0.2.110|UP|1\neth1|198.51.100.40|UP|0\neth2|203.0.113.20|DOWN|0'
export NOBRAND_TEST_DEFAULT_EGRESS='eth0|192.0.2.110'
[ ! -e "$NOBRAND_INGRESS_STATE_FILE" ]
nb_ingress_list >/dev/null
nb_ingress_doctor >/dev/null
[ ! -e "$NOBRAND_INGRESS_STATE_FILE" ]

platform_ingress_cli() {
  ingress_menu_reset_requests
  parse_nobrand_ingress_args "$@"
  nobrand_run_ingress_action
}

platform_ingress_cli add --name Platform-Derived --type public --interface eth0 \
  --address 192.0.2.110 --port-policy derived-tail --enforcement strict --yes >/dev/null
platform_ingress_cli add --name Platform-Custom --type mapped --interface eth1 \
  --address 198.51.100.40 --port-policy custom-range --range-start 30001 --range-end 30020 \
  --reserve 30005 --advertise-host mapped.example.test --yes >/dev/null
platform_ingress_cli add --name Platform-Manual --type public --interface eth2 \
  --address 203.0.113.20 --port-policy manual-only --reserve 32000 --disable --yes >/dev/null
nb_ingress_state_valid
derived_id="$(nb_ingress_profile_id Platform-Derived)"
custom_id="$(nb_ingress_profile_id Platform-Custom)"
manual_id="$(nb_ingress_profile_id Platform-Manual)"
test "$(nb_ingress_profile_auto_range "$derived_id")" = '11001|11099'
test "$(nb_ingress_profile_auto_range "$custom_id")" = '30001|30020'
test "$(nb_ingress_profile_enforcement "$derived_id")" = strict
test "$(nb_ingress_profile_enforcement "$custom_id")" = permissive
nb_prepare_ingress_deployment "$derived_id" native-bind
test "$INGRESS_ENFORCEMENT_RESOLVED|$INGRESS_ENFORCEMENT_METHOD|$INGRESS_LISTEN_HOST" = \
  'strict|native-bind|192.0.2.110'
nb_prepare_ingress_deployment "$derived_id" firewall
test "$INGRESS_ENFORCEMENT_RESOLVED|$INGRESS_ENFORCEMENT_METHOD|$INGRESS_LISTEN_HOST" = \
  'strict|firewall|0.0.0.0'
if nb_ingress_profile_auto_range "$manual_id" >/dev/null 2>&1; then
  echo 'manual-only profile unexpectedly exposed an automatic range' >&2
  exit 1
fi
test "$(jq -r --arg id "$custom_id" '.profiles[]|select(.profile_id==$id)|[.type,.display_host_default,.reserved_ports[0]]|join("|")' \
  "$NOBRAND_INGRESS_STATE_FILE")" = 'mapped|mapped.example.test|30005'
platform_ingress_cli set-default Platform-Derived >/dev/null
test "$(nb_resolve_ingress_profile '')" = "$derived_id"

# Every protocol parser shares --ingress-profile; one real parser invocation
# here guards that public CLI contract across all four shell/package variants.
# shellcheck disable=SC2034
INGRESS_PROFILE="" PORT="" PORT_AUTO_SELECTED=0 NOBRAND_ARGS_HANDLED=0
parse_nobrand_hy2_args install --ingress-profile Platform-Custom --port 30001 \
  --advertise-host mapped.example.test
test "$INGRESS_PROFILE|$PORT|$ACTION|$NOBRAND_ARGS_HANDLED" = \
  'Platform-Custom|30001|nobrand-hy2|1'

# Exercise REALITY strict native-bind generation without starting init or
# changing the container network.
INGRESS_PROFILE="" PORT="" NOBRAND_ARGS_HANDLED=0
parse_nobrand_vless_reality_args install --name platform-reality --target example.com \
  --target-port 443 --ingress-profile Platform-Derived --port 11052 \
  --advertise-auto --yes
test "$ACTION|$VLESS_REALITY_ACTION|$VLESS_REALITY_NAME|$VLESS_REALITY_TARGET|$PORT" = \
  'nobrand-vless-reality|install|platform-reality|example.com|11052'
reality_id="r$(openssl rand -hex 8)"
reality_uuid="$(tr -d '\r\n' </proc/sys/kernel/random/uuid)"
reality_private="$(openssl rand -base64 32 | tr '/+' '_-' | tr -d '=\r\n')"
reality_public="$(openssl rand -base64 32 | tr '/+' '_-' | tr -d '=\r\n')"
reality_short="$(openssl rand -hex 8)"
reality_config="$(reality_config_file "$reality_id")"
reality_state="$(reality_state_file "$reality_id")"
reality_key="$(reality_private_key_file "$reality_id")"
mkdir -p "$(dirname "$reality_config")" "$(dirname "$reality_state")"
printf '%s\n' "$reality_private" >"$reality_key"
chmod 0600 "$reality_key"
nb_prepare_ingress_deployment "$derived_id" native-bind
reality_generate_server_config "$reality_config" "$reality_id" "$INGRESS_LISTEN_HOST" 11052 \
  "$reality_uuid" "$reality_private" "$reality_short" example.com 443 21052
reality_generate_state "$reality_state" "$reality_id" platform-reality "$INGRESS_LISTEN_HOST" 11052 \
  auto '' '' "$reality_uuid" "$reality_public" "$reality_key" "$reality_short" \
  example.com 443 chrome / "$TESTED_XRAY_VERSION" "$derived_id" 21052 2026-09-01T00:00:00Z
nb_ingress_stamp_state_file "$reality_state" "$derived_id" native-bind
reality_state_matches "$reality_state" "$reality_id"
reality_config_matches_state "$reality_id"
test "$(stat -c '%a:%u:%g' "$reality_key")" = '600:0:0'
test "$(nb_registry_port_owner TCP 11052)" = "vless-reality:${reality_id}"
nb_port_available_for_profile 11052 UDP "$custom_id"
jq -e '
  .inbounds[0].listen=="192.0.2.110"
  and .inbounds[0].protocol=="vless"
  and .inbounds[0].settings.decryption=="none"
  and .inbounds[0].settings.clients[0].flow=="xtls-rprx-vision"
  and .inbounds[0].streamSettings.network=="tcp"
  and .inbounds[0].streamSettings.security=="reality"
  and .inbounds[0].streamSettings.realitySettings.target=="127.0.0.1:21052"
  and .inbounds[1].listen=="127.0.0.1"
  and .inbounds[1].protocol=="dokodemo-door"
' "$reality_config" >/dev/null
reality_export_xray "$reality_id" | jq -e \
  '.outbounds[0].streamSettings.realitySettings.password|type=="string"' >/dev/null
grep -q '^mode: rule$' < <(reality_export_mihomo "$reality_id")
reality_export_singbox "$reality_id" | jq -e \
  '.route.final==.outbounds[0].tag and ([.outbounds[].type]|index("direct")|not)' >/dev/null
printf 'platform-reality: PASS (parser/state/config/export/profile/strict-native-bind)\n'
printf 'platform-ingress: PASS (permissive/strict, native/firewall resolution, default, no read-only migration)\n'
unset NOBRAND_TEST_INTERFACE_ROWS NOBRAND_TEST_DEFAULT_EGRESS
INGRESS_PROFILE=""

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
