#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/testlib.sh"

fixture="$(mktemp -d)"
trap 'rm -rf -- "$fixture"' EXIT
export NOBRAND_STATE_DIR="$fixture/nobrand-oneclick/state"
export NOBRAND_CONFIG_DIR="$fixture/nobrand-oneclick/config"
export NOBRAND_LIB_DIR="$fixture/nobrand-oneclick/lib"
export NOBRAND_LIFECYCLE_DIR="$fixture/nobrand-oneclick-lifecycle"
export NOBRAND_LIFECYCLE_TX_FILE="$NOBRAND_LIFECYCLE_DIR/transaction.env"
export NOBRAND_LIFECYCLE_LOCK_FILE="$fixture/run/nobrand-oneclick/lifecycle.lock"
mkdir -p "$(dirname "$NOBRAND_LIFECYCLE_LOCK_FILE")"
chmod 0700 "$(dirname "$NOBRAND_LIFECYCLE_LOCK_FILE")"
export NOBRAND_INSTALL_SCRIPT_PATH="$fixture/nobrand-oneclick/bin/install-nobrand"
export NOBRAND_COMMAND_PATH="$fixture/nobrand-oneclick/bin/nobrand"
export NOBRAND_SHORT_COMMAND_PATH="$fixture/nobrand-oneclick/bin/nb"
export NOBRAND_LEGACY_MIERU_STATE_DIR="$fixture/legacy-mita-oneclick"
export MITA_USERS_CRON="$fixture/etc/cron.d/nobrand-mieru-users"
export MITA_USERS_TIMER="$fixture/systemd/nobrand-mieru-users-scan.timer"
export MITA_USERS_SERVICE="$fixture/systemd/nobrand-mieru-users-scan.service"
export MITA_USERS_LOG="$NOBRAND_STATE_DIR/mieru/users.log"
export MITA_CLIENT_EXPORT_DIR="$NOBRAND_CONFIG_DIR/mieru/client-exports"
export MITA_LOGROTATE_CONF="$fixture/etc/logrotate.d/nobrand-mieru"
export MITA_METRICS_FILE="$NOBRAND_STATE_DIR/mieru/metrics.pb"
export MITA_INSTANCES_DIR="$NOBRAND_CONFIG_DIR/mieru/instances"
export MITA_INSTANCE_RUN_DIR="$NOBRAND_LIB_DIR/mieru/run"
export MITA_INSTANCE_METRICS_DIR="$NOBRAND_STATE_DIR/mieru/instance-metrics"
export MITA_INSTANCE_SYSTEMD_TEMPLATE="$fixture/systemd/nobrand-mieru@.service"
export MITA_INSTANCE_TMPFILES="$fixture/etc/tmpfiles.d/nobrand-mieru.conf"
export MITA_INSTANCE_OPENRC_PREFIX="$fixture/openrc/nobrand-mieru-"
export MITA_INSTANCE_RUNNER="$NOBRAND_LIB_DIR/mieru-instance-run"
export NOBRAND_REALITY_SYSTEMD_TEMPLATE="$fixture/systemd/nobrand-vless-reality@.service"
source_installer
nb_init_state_layout
mkdir -p "$fixture/mita-oneclick" "$fixture/external-xray" "$(dirname "$NOBRAND_COMMAND_PATH")"
printf 'mita-authoritative\n' >"$fixture/mita-oneclick/users.json"
printf 'external-xray\n' >"$fixture/external-xray/config.json"
printf '%s\n' \
  'SCRIPT_NAME="NoBrand-OneClick"' \
  'SCRIPT_REPO="ike-sh/NoBrand-OneClick"' \
  "SCRIPT_VERSION=\"${SCRIPT_VERSION}\"" \
  >"$NOBRAND_INSTALL_SCRIPT_PATH"
chmod 0755 "$NOBRAND_INSTALL_SCRIPT_PATH"
ln -s "$NOBRAND_INSTALL_SCRIPT_PATH" "$NOBRAND_COMMAND_PATH"
ln -s "$NOBRAND_COMMAND_PATH" "$NOBRAND_SHORT_COMMAND_PATH"
printf '{"owned":true}\n' >"$NOBRAND_STATE_DIR/owned.json"
printf 'owned-config\n' >"$NOBRAND_CONFIG_DIR/owned.conf"
printf 'owned-runtime\n' >"$NOBRAND_LIB_DIR/owned.bin"
reality_id="r$(openssl rand -hex 8)"
mkdir -p "$(dirname "$(reality_state_file "$reality_id")")" \
  "$(reality_instance_config_dir "$reality_id")" "$(dirname "$NOBRAND_REALITY_SYSTEMD_TEMPLATE")"
jq -n --arg id "$reality_id" \
  '{schema_version:3,ownership:"nobrand-v3",protocol:"vless-reality",instance_id:$id}' \
  >"$(reality_state_file "$reality_id")"
printf 'owned-reality-config\n' >"$(reality_config_file "$reality_id")"
cat >"$NOBRAND_REALITY_SYSTEMD_TEMPLATE" <<EOF
# Managed by NoBrand-OneClick
Environment=XRAY_LOCATION_ASSET=${NOBRAND_XRAY_ASSET_DIR}
ExecStart=${NOBRAND_XRAY_BIN} run -c ${NOBRAND_REALITY_CONFIG_DIR}/%i/config.json
EOF

require_root() { :; }
admin_lock_acquire() { :; }
admin_lock_release() { :; }
nb_service_manager() { printf none; }
reality_remove_service() { printf '%s\n' "$1" >"$fixture/reality-service-removed"; }
systemctl() { :; }
mita_uninstall_target_present() { return 0; }
do_uninstall() { printf 'called\n' >"$fixture/mieru-uninstall-called"; }
# Confirmation is consumed indirectly by nobrand_uninstall.
# shellcheck disable=SC2034
YES=1
nobrand_uninstall >/dev/null
[ ! -e "$NOBRAND_STATE_DIR/owned.json" ] || fail 'NoBrand state must be removed'
[ ! -e "$NOBRAND_CONFIG_DIR/owned.conf" ] || fail 'NoBrand config must be removed'
[ ! -e "$NOBRAND_LIB_DIR/owned.bin" ] || fail 'NoBrand runtime must be removed'
[ ! -e "$NOBRAND_INSTALL_SCRIPT_PATH" ] || fail 'owned NoBrand installer must be removed'
[ ! -e "$NOBRAND_COMMAND_PATH" ] || fail 'owned nobrand command must be removed'
[ ! -e "$NOBRAND_SHORT_COMMAND_PATH" ] || fail 'owned nb command must be removed'
[ ! -e "$NOBRAND_REALITY_SYSTEMD_TEMPLATE" ] || fail 'owned REALITY service template must be removed'
assert_eq "$reality_id" "$(<"$fixture/reality-service-removed")" 'REALITY service cleanup integration'
assert_eq mita-authoritative "$(tr -d '\r\n' <"$fixture/mita-oneclick/users.json")" 'external Mieru preserved'
assert_eq external-xray "$(tr -d '\r\n' <"$fixture/external-xray/config.json")" 'external Xray preserved'
[ -s "$fixture/mieru-uninstall-called" ] || fail 'unified uninstall must invoke Mieru owned-resource cleanup'

pass 'unified uninstall removes NoBrand protocols/commands and preserves external Mieru/Xray'
