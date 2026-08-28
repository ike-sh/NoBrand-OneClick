#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/testlib.sh"

fixture="$(mktemp -d)"
trap 'rm -rf -- "$fixture"' EXIT
export NOBRAND_STATE_DIR="$fixture/nobrand-oneclick/state"
export NOBRAND_CONFIG_DIR="$fixture/nobrand-oneclick/config"
export NOBRAND_LIB_DIR="$fixture/nobrand-oneclick/lib"
export NOBRAND_INSTALL_SCRIPT_PATH="$fixture/nobrand-oneclick/bin/install-nobrand"
export NOBRAND_COMMAND_PATH="$fixture/nobrand-oneclick/bin/nobrand"
export NOBRAND_SHORT_COMMAND_PATH="$fixture/nobrand-oneclick/bin/nb"
source_installer
nb_init_state_layout
mkdir -p "$fixture/mita-oneclick" "$fixture/external-xray" "$(dirname "$NOBRAND_COMMAND_PATH")"
printf 'mita-authoritative\n' >"$fixture/mita-oneclick/users.json"
printf 'external-xray\n' >"$fixture/external-xray/config.json"
printf 'NoBrand-OneClick installer\n' >"$NOBRAND_INSTALL_SCRIPT_PATH"
printf 'exec %s\n' "$NOBRAND_INSTALL_SCRIPT_PATH" >"$NOBRAND_COMMAND_PATH"
printf 'exec %s\n' "$NOBRAND_INSTALL_SCRIPT_PATH" >"$NOBRAND_SHORT_COMMAND_PATH"
printf '{"owned":true}\n' >"$NOBRAND_STATE_DIR/owned.json"
printf 'owned-config\n' >"$NOBRAND_CONFIG_DIR/owned.conf"
printf 'owned-runtime\n' >"$NOBRAND_LIB_DIR/owned.bin"

require_root() { :; }
admin_lock_acquire() { :; }
admin_lock_release() { :; }
nb_service_manager() { printf none; }
systemctl() { :; }
YES=1
nobrand_uninstall >/dev/null
[ ! -e "$NOBRAND_STATE_DIR/owned.json" ] || fail 'NoBrand state must be removed'
[ ! -e "$NOBRAND_CONFIG_DIR/owned.conf" ] || fail 'NoBrand config must be removed'
[ ! -e "$NOBRAND_LIB_DIR/owned.bin" ] || fail 'NoBrand runtime must be removed'
[ ! -e "$NOBRAND_INSTALL_SCRIPT_PATH" ] || fail 'owned NoBrand installer must be removed'
[ ! -e "$NOBRAND_COMMAND_PATH" ] || fail 'owned nobrand command must be removed'
[ ! -e "$NOBRAND_SHORT_COMMAND_PATH" ] || fail 'owned nb command must be removed'
assert_eq mita-authoritative "$(tr -d '\r\n' <"$fixture/mita-oneclick/users.json")" 'Mieru preserved'
assert_eq external-xray "$(tr -d '\r\n' <"$fixture/external-xray/config.json")" 'external Xray preserved'

pass 'NoBrand uninstall ownership boundary preserves Mieru and external Xray'
