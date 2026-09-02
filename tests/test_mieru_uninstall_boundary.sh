#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/testlib.sh"

fixture="$(mktemp -d)"
trap 'rm -rf -- "$fixture"' EXIT
export NOBRAND_STATE_DIR="$fixture/nobrand-oneclick/state"
export NOBRAND_CONFIG_DIR="$fixture/nobrand-oneclick/config"
export NOBRAND_LIB_DIR="$fixture/nobrand-oneclick/lib"
export NOBRAND_BIN_DIR="$NOBRAND_LIB_DIR/bin"
export NOBRAND_INSTALL_SCRIPT_PATH="$fixture/nobrand-oneclick/commands/install-nobrand"
export NOBRAND_COMMAND_PATH="$fixture/nobrand-oneclick/commands/nobrand"
export NOBRAND_SHORT_COMMAND_PATH="$fixture/nobrand-oneclick/commands/nb"
export MITA_MANAGER_STATE_DIR="$NOBRAND_STATE_DIR/mieru"
export MITA_BIN="$NOBRAND_BIN_DIR/mita"
export MITA_INSTANCES_DIR="$NOBRAND_CONFIG_DIR/mieru/instances"
export MITA_INSTANCE_RUN_DIR="$fixture/nobrand-oneclick/run/mieru"
export MITA_INSTANCE_METRICS_DIR="$fixture/nobrand-oneclick/metrics/mieru"
export MITA_INSTANCE_SYSTEMD_TEMPLATE="$fixture/nobrand-oneclick/systemd/nobrand-mieru@.service"
export MITA_INSTANCE_TMPFILES="$fixture/nobrand-oneclick/tmpfiles/nobrand-mieru.conf"
export MITA_INSTANCE_RUNNER="$NOBRAND_LIB_DIR/mieru-instance-run"
export MITA_INSTANCE_OPENRC_PREFIX="$fixture/nobrand-oneclick/openrc/nobrand-mieru-"
export MITA_USERS_TIMER="$fixture/nobrand-oneclick/systemd/nobrand-mieru-users-scan.timer"
export MITA_USERS_SERVICE="$fixture/nobrand-oneclick/systemd/nobrand-mieru-users-scan.service"
export MITA_USERS_CRON="$fixture/nobrand-oneclick/cron/nobrand-mieru-users"
export MITA_LOGROTATE_CONF="$fixture/nobrand-oneclick/logrotate/nobrand-mieru"
export MITA_USERS_LOG="$fixture/nobrand-oneclick/log/nobrand-mieru-users.log"
export MITA_CLIENT_EXPORT_DIR="$fixture/nobrand-oneclick/exports/mieru"
source_installer

nb_init_state_layout
mkdir -p "$NOBRAND_CONFIG_DIR" "$NOBRAND_BIN_DIR" "$MITA_MANAGER_STATE_DIR" \
  "$MITA_INSTANCES_DIR/u0000000000000001" "$MITA_INSTANCE_RUN_DIR" \
  "$MITA_INSTANCE_METRICS_DIR/u0000000000000001" \
  "$(dirname "$MITA_INSTANCE_SYSTEMD_TEMPLATE")" \
  "$(dirname "$MITA_INSTANCE_TMPFILES")" "$(dirname "$NOBRAND_INSTALL_SCRIPT_PATH")" \
  "$fixture/external-mieru" "$fixture/external-xray" "$fixture/unrelated-service"
chmod 0700 "$MITA_MANAGER_STATE_DIR"
printf '%s\n' \
  'SCHEMA_VERSION=3' 'OWNERSHIP=nobrand-v3' \
  'PORT=26001' 'PORT_RANGE=' 'PROTOCOL=TCP' 'PROFILE=balanced' \
  'ADVERTISE_HOST=' 'ADVERTISE_PORT=' 'MTU=1400' 'MTU_POLICY=safe' \
  'USERNAME=alice' 'PASSWORD=alice-pass' 'TRAFFIC_PATTERN=conservative' \
  'TRAFFIC_SEED=42' 'LOW_ENTROPY_MODE=LOW_ENTROPY_MODE_OFF' \
  'MULTIPLEXING=MULTIPLEXING_OFF' 'HANDSHAKE_MODE=HANDSHAKE_NO_WAIT' \
  'MIERU_CHANNEL=stable' 'MIERU_VERSION=3.35.0' \
  'INSTALL_SCRIPT=/usr/local/bin/install-nobrand' 'INSTALL_METHOD=nobrand-v3' \
  >"$MITA_STATE"
printf '%s\n' \
  '{"version":2,"deployment_model":"isolated-v2","protocol":"TCP","users":[{"instance_id":"u0000000000000001","name":"alice","password":"alice-pass","port":26001,"enabled":true}]}' \
  >"$MITA_USERS_STATE"
printf '%s\n' \
  '{"schema_version":3,"ownership":"nobrand-v3","feature":"ingress-enforcement-firewall","rules":[{"owner":"mieru:u0000000000000001","ingress_profile_id":"i1111111111111111","transport":"TCP","port":26001,"local_address":"192.0.2.10"},{"owner":"reality:r1111111111111111","ingress_profile_id":"i2222222222222222","transport":"TCP","port":26002,"local_address":"192.0.2.20"}]}' \
  >"$NOBRAND_INGRESS_FIREWALL_STATE_FILE"
chmod 0600 "$MITA_STATE" "$MITA_USERS_STATE"
touch "$MITA_MARKER" "$MITA_BIN" "$MITA_INSTANCE_SYSTEMD_TEMPLATE" \
  "$MITA_INSTANCE_TMPFILES" "$MITA_INSTANCE_RUNNER" \
  "$MITA_PRESERVE_PACKAGE_MARKER" "$MITA_PRESERVE_USER_MARKER" \
  "$MITA_PRESERVE_GROUP_MARKER" "$MITA_PRESERVE_SHARED_MARKER"
chmod 0755 "$MITA_BIN" "$MITA_INSTANCE_RUNNER"
printf 'managed-config\n' >"$MITA_INSTANCES_DIR/u0000000000000001/server.json"
printf 'external-mieru\n' >"$fixture/external-mieru/config.json"
printf 'external-xray\n' >"$fixture/external-xray/config.json"
printf 'unrelated-service\n' >"$fixture/unrelated-service/unit.service"
printf '# NoBrand-OneClick installer\n' >"$NOBRAND_INSTALL_SCRIPT_PATH"
chmod 0755 "$NOBRAND_INSTALL_SCRIPT_PATH"
ln -s "$NOBRAND_INSTALL_SCRIPT_PATH" "$NOBRAND_COMMAND_PATH"
ln -s "$NOBRAND_COMMAND_PATH" "$NOBRAND_SHORT_COMMAND_PATH"

op_log="$fixture/operations.log"
: >"$op_log"
run() {
  printf '%s\n' "$*" >>"$op_log"
  "$@"
}
require_root() { :; }
service_manager() { printf none; }
nb_service_manager() { printf none; }
detect_pkg_manager() { printf alpine; }
isolated_stop_all() { printf 'isolated-stop-owned\n' >>"$op_log"; }
tc_clear_owned_filters() { printf 'tc-clear-owned\n' >>"$op_log"; }
firewall_clear_all_owned() {
  printf 'firewall-clear-owned\n' >>"$op_log"
  rm -f "$MITA_FIREWALL_OWNED_STATE"
}
nb_strict_firewall_apply_state() {
  printf 'strict-firewall-apply\n' >>"$op_log"
}
_has_user() { return 0; }
_has_group() { return 0; }
# Confirmation is consumed indirectly by both uninstall entry points.
# shellcheck disable=SC2034
YES=1

protocol_output="$(do_uninstall)"
assert_contains "$protocol_output" 'Mieru 协议资源已卸载' 'protocol uninstall result'
[ ! -e "$MITA_MANAGER_STATE_DIR" ] || fail 'Mieru manager state must be removed'
[ ! -e "$MITA_BIN" ] || fail 'NoBrand-managed Mita runtime must be removed'
[ ! -e "$MITA_INSTANCES_DIR" ] || fail 'NoBrand-managed Mieru configs must be removed'
[ ! -e "$MITA_INSTANCE_SYSTEMD_TEMPLATE" ] || fail 'NoBrand Mieru service template must be removed'
[ "$(jq -r '.rules | length' "$NOBRAND_INGRESS_FIREWALL_STATE_FILE")" -eq 1 ] \
  || fail 'Mieru uninstall must remove only its strict-ingress rules'
assert_eq reality:r1111111111111111 \
  "$(jq -r '.rules[0].owner' "$NOBRAND_INGRESS_FIREWALL_STATE_FILE")" \
  'non-Mieru strict-ingress owner preserved'
assert_contains "$(<"$op_log")" 'strict-firewall-apply' \
  'Mieru uninstall must apply strict-ingress cleanup before deleting user state'
[ -f "$NOBRAND_REGISTRY_FILE" ] || fail 'protocol uninstall must preserve schema-v3 manager state'
[ -x "$NOBRAND_INSTALL_SCRIPT_PATH" ] || fail 'protocol uninstall must preserve installer'
assert_eq "$NOBRAND_INSTALL_SCRIPT_PATH" "$(readlink "$NOBRAND_COMMAND_PATH")" 'nobrand symlink after protocol uninstall'
assert_eq "$NOBRAND_COMMAND_PATH" "$(readlink "$NOBRAND_SHORT_COMMAND_PATH")" 'nb symlink after protocol uninstall'
assert_eq external-mieru "$(tr -d '\r\n' <"$fixture/external-mieru/config.json")" 'external Mieru preserved'
assert_eq external-xray "$(tr -d '\r\n' <"$fixture/external-xray/config.json")" 'external Xray preserved'
assert_eq unrelated-service "$(tr -d '\r\n' <"$fixture/unrelated-service/unit.service")" 'unrelated service preserved'
if grep -Eq '(^|[[:space:]])(pkill|killall|pgrep)([[:space:]]|$)' "$op_log"; then
  fail 'protocol uninstall must not use process-name-wide Mita cleanup'
fi

admin_lock_acquire() { :; }
admin_lock_release() { :; }
unified_output="$(nobrand_uninstall)"
assert_contains "$unified_output" '已完整删除' 'unified uninstall result'
[ ! -e "$NOBRAND_STATE_DIR" ] || fail 'unified uninstall must remove NoBrand state root'
[ ! -e "$NOBRAND_CONFIG_DIR" ] || fail 'unified uninstall must remove NoBrand config root'
[ ! -e "$NOBRAND_LIB_DIR" ] || fail 'unified uninstall must remove NoBrand lib root'
[ ! -e "$NOBRAND_INSTALL_SCRIPT_PATH" ] || fail 'unified uninstall must remove installer last'
[ ! -e "$NOBRAND_COMMAND_PATH" ] || fail 'unified uninstall must remove nobrand command'
[ ! -e "$NOBRAND_SHORT_COMMAND_PATH" ] || fail 'unified uninstall must remove nb alias'
assert_eq external-mieru "$(tr -d '\r\n' <"$fixture/external-mieru/config.json")" 'external Mieru after unified uninstall'
assert_eq external-xray "$(tr -d '\r\n' <"$fixture/external-xray/config.json")" 'external Xray after unified uninstall'

state_line="$(grep -n 'find "$safe_state"' "$TEST_ROOT/install-nobrand.sh" | head -n1 | cut -d: -f1)"
nb_line="$(grep -n 'nobrand_remove_owned_command "$NOBRAND_SHORT_COMMAND_PATH"' "$TEST_ROOT/install-nobrand.sh" | head -n1 | cut -d: -f1)"
nobrand_line="$(grep -n 'nobrand_remove_owned_command "$NOBRAND_COMMAND_PATH"' "$TEST_ROOT/install-nobrand.sh" | head -n1 | cut -d: -f1)"
installer_line="$(grep -n 'nobrand_remove_owned_command "$NOBRAND_INSTALL_SCRIPT_PATH"' "$TEST_ROOT/install-nobrand.sh" | head -n1 | cut -d: -f1)"
[ "$state_line" -lt "$nb_line" ] && [ "$nb_line" -lt "$nobrand_line" ] \
  && [ "$nobrand_line" -lt "$installer_line" ] \
  || fail 'self-removal order must be state -> nb -> nobrand -> installer'

pass 'real Mieru ownership cleanup, external preservation, manager retention, and unified self-removal order'
