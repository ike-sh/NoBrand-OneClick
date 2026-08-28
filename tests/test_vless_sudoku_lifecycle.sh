#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/testlib.sh"

fixture="$(mktemp -d)"
trap 'rm -rf -- "$fixture"' EXIT
export NOBRAND_STATE_DIR="$fixture/nobrand-oneclick/state"
export NOBRAND_CONFIG_DIR="$fixture/nobrand-oneclick/config"
export NOBRAND_LIB_DIR="$fixture/nobrand-oneclick/lib"
export NOBRAND_VLESS_SYSTEMD_SERVICE="$fixture/nobrand-oneclick/systemd/vless.service"
export NOBRAND_VLESS_OPENRC_SERVICE="$fixture/nobrand-oneclick/openrc/vless"
source_installer
nb_init_state_layout

printf '%s\n' '#!/bin/sh' 'case "$1" in version) echo "Xray 26.3.27";; uuid) echo "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee";; *) exit 0;; esac' \
  >"$NOBRAND_XRAY_BIN"
chmod 0755 "$NOBRAND_XRAY_BIN"

mkdir -p "$(dirname "$NOBRAND_VLESS_SYSTEMD_SERVICE")" \
  "$(dirname "$NOBRAND_VLESS_OPENRC_SERVICE")"
nb_service_manager() { printf systemd; }
systemctl() { :; }
nobrand_write_vless_sudoku_service
grep -qF "ExecStart=${NOBRAND_XRAY_BIN} run -c ${NOBRAND_VLESS_CONFIG_FILE}" \
  "$NOBRAND_VLESS_SYSTEMD_SERVICE" || fail 'VLESS systemd unit runtime/config isolation'
case "$(uname -s)" in
  CYGWIN*|MINGW*|MSYS*) printf '[SKIP] Windows filesystem systemd mode assertion\n' ;;
  *) assert_file_mode 644 "$NOBRAND_VLESS_SYSTEMD_SERVICE" ;;
esac
rm -f "$NOBRAND_VLESS_SYSTEMD_SERVICE"
nb_service_manager() { printf openrc; }
rc-update() { :; }
nobrand_write_vless_sudoku_service
grep -qF "command_args=\"run -c ${NOBRAND_VLESS_CONFIG_FILE}\"" \
  "$NOBRAND_VLESS_OPENRC_SERVICE" || fail 'VLESS OpenRC runtime/config isolation'
case "$(uname -s)" in
  CYGWIN*|MINGW*|MSYS*) printf '[SKIP] Windows filesystem OpenRC mode assertion\n' ;;
  *) assert_file_mode 755 "$NOBRAND_VLESS_OPENRC_SERVICE" ;;
esac
rm -f "$NOBRAND_VLESS_OPENRC_SERVICE"
nb_service_manager() { printf systemd; }

service_calls="$fixture/service.calls"
service_active=0
require_root() { :; }
nobrand_prepare_common() { :; }
admin_lock_acquire() { :; }
admin_lock_release() { :; }
nobrand_install_xray_runtime() { :; }
nobrand_xray_test_config() { jq empty "$1" >/dev/null; }
nb_port_available_for_transport() { return 0; }
nb_wait_for_listener() { [ "$service_active" -eq 1 ]; }
nobrand_vless_sudoku_service_active() { [ "$service_active" -eq 1 ]; }
nobrand_vless_sudoku_service_action() {
  printf '%s\n' "$1" >>"$service_calls"
  case "$1" in start|restart) service_active=1 ;; stop) service_active=0 ;; esac
}
nobrand_write_vless_sudoku_service() {
  mkdir -p "$(dirname "$NOBRAND_VLESS_SYSTEMD_SERVICE")"
  printf 'managed-vless-service\n' >"$NOBRAND_VLESS_SYSTEMD_SERVICE"
}
nobrand_remove_vless_sudoku_service() {
  nobrand_vless_sudoku_service_action stop
  rm -f "$NOBRAND_VLESS_SYSTEMD_SERVICE" "$NOBRAND_VLESS_OPENRC_SERVICE"
}
nb_firewall_open_pairs() {
  printf 'test|tcp|%s\n' "${1#TCP|}" >"$NOBRAND_FIREWALL_OWNED_STATE"
}
nb_firewall_close_pairs() { rm -f "$NOBRAND_FIREWALL_OWNED_STATE"; }
nobrand_install_manager_script() { :; }
public_ip() { printf '198.51.100.30'; }

YES=1 PORT=3683 PORT_CLI=1 ADVERTISE_CLI=1 ADVERTISE_AUTO_REQUESTED=0
ADVERTISE_HOST=entry.example.com ADVERTISE_PORT=443
install_vless_sudoku >/dev/null
[ -s "$NOBRAND_VLESS_CONFIG_FILE" ] && [ -s "$NOBRAND_VLESS_STATE_FILE" ] \
  && [ -s "$NOBRAND_VLESS_CLIENT_FILE" ] || fail 'install must atomically commit config/state/client'
vless_sudoku_state_matches || fail 'installed VLESS state schema'
vless_sudoku_server_config_matches || fail 'installed server/state semantic parity'
vless_sudoku_client_config_matches || fail 'installed client/state semantic parity'
assert_eq true "$(vless_sudoku_state_field enabled)" 'installed enabled state'
assert_eq 3683 "$(vless_sudoku_state_field listen_port)" 'installed listener port'
assert_eq entry.example.com "$(jq -r '.outbounds[0].settings.vnext[0].address' "$NOBRAND_VLESS_CLIENT_FILE")" \
  'installed client display host'
uuid_before="$(vless_sudoku_state_field uuid)"
password_before="$(jq -r '.finalmask_json.tcp[0].settings.password' "$NOBRAND_VLESS_STATE_FILE")"

# Reinstalling the same node is idempotent for credentials and owned artifacts.
install_vless_sudoku >/dev/null
assert_eq "$uuid_before" "$(vless_sudoku_state_field uuid)" 'idempotent UUID'
assert_eq "$password_before" "$(jq -r '.finalmask_json.tcp[0].settings.password' "$NOBRAND_VLESS_STATE_FILE")" \
  'idempotent Sudoku password'
[ "$(find "$NOBRAND_VLESS_CONFIG_DIR" -type f | wc -l | tr -d ' ')" -eq 1 ] \
  || fail 'idempotent install must not duplicate server configs'

config_hash="$(sha256sum "$NOBRAND_VLESS_CONFIG_FILE")"
service_hash="$(sha256sum "$NOBRAND_VLESS_SYSTEMD_SERVICE")"
firewall_hash="$(sha256sum "$NOBRAND_FIREWALL_OWNED_STATE")"
calls_before="$(wc -l <"$service_calls" | tr -d ' ')"
ADVERTISE_HOST=changed.example.com ADVERTISE_PORT=8443
vless_sudoku_set_endpoint >/dev/null
assert_eq "$config_hash" "$(sha256sum "$NOBRAND_VLESS_CONFIG_FILE")" 'endpoint server-config isolation'
assert_eq "$service_hash" "$(sha256sum "$NOBRAND_VLESS_SYSTEMD_SERVICE")" 'endpoint service isolation'
assert_eq "$firewall_hash" "$(sha256sum "$NOBRAND_FIREWALL_OWNED_STATE")" 'endpoint firewall isolation'
assert_eq "$calls_before" "$(wc -l <"$service_calls" | tr -d ' ')" 'endpoint process isolation'
assert_eq changed.example.com "$(jq -r '.outbounds[0].settings.vnext[0].address' "$NOBRAND_VLESS_CLIENT_FILE")" \
  'endpoint client regeneration'

vless_sudoku_service_command stop
assert_eq false "$(vless_sudoku_state_field enabled)" 'stop state'
[ -s "$NOBRAND_VLESS_CLIENT_FILE" ] || fail 'stop must retain node export'
vless_sudoku_service_command start
assert_eq true "$(vless_sudoku_state_field enabled)" 'start state'
vless_sudoku_service_command restart

printf '{"protocol":"hysteria2"}\n' >"$NOBRAND_HY2_STATE_FILE"
remove_vless_sudoku_config >/dev/null
[ ! -e "$NOBRAND_VLESS_CONFIG_FILE" ] && [ ! -e "$NOBRAND_VLESS_STATE_FILE" ] \
  && [ ! -e "$NOBRAND_VLESS_CLIENT_FILE" ] || fail 'remove must delete only VLESS artifacts'
[ -x "$NOBRAND_XRAY_BIN" ] || fail 'individual VLESS remove must retain shared Xray runtime'
[ -s "$NOBRAND_HY2_STATE_FILE" ] || fail 'individual VLESS remove must retain HY2 state'

# A failure after listener acceptance but before state commit must restore the
# exact pre-install boundary and remove the newly owned firewall binding.
nb_atomic_install_file() {
  local source="$1" destination="$2" mode="${3:-0600}"
  [ "$destination" != "$NOBRAND_VLESS_STATE_FILE" ] || return 1
  mkdir -p "$(dirname "$destination")"
  install -m "$mode" "$source" "$destination"
}
service_active=0
ADVERTISE_HOST=rollback.example.com ADVERTISE_PORT=9443 PORT=3684
if install_vless_sudoku >/dev/null 2>&1; then
  fail 'state-commit failure must fail the VLESS install transaction'
fi
[ ! -e "$NOBRAND_VLESS_CONFIG_FILE" ] && [ ! -e "$NOBRAND_VLESS_STATE_FILE" ] \
  && [ ! -e "$NOBRAND_VLESS_CLIENT_FILE" ] && [ ! -e "$NOBRAND_VLESS_SYSTEMD_SERVICE" ] \
  || fail 'failed install must not leave VLESS config/state/client/service'
[ ! -e "$NOBRAND_FIREWALL_OWNED_STATE" ] || fail 'failed install must close newly owned firewall binding'
[ -x "$NOBRAND_XRAY_BIN" ] && [ -s "$NOBRAND_HY2_STATE_FILE" ] \
  || fail 'failed VLESS install must preserve shared runtime and HY2 state'

pass 'VLESS install/idempotency/endpoint/service/remove and post-listener rollback lifecycle'
