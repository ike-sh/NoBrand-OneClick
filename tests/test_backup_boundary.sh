#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/testlib.sh"

fixture="$(mktemp -d)"
trap 'rm -rf -- "$fixture"' EXIT
export NOBRAND_STATE_DIR="$fixture/nobrand-oneclick/state"
export NOBRAND_CONFIG_DIR="$fixture/nobrand-oneclick/config"
export NOBRAND_LIB_DIR="$fixture/nobrand-oneclick/lib"
source_installer
nb_init_state_layout
nobrand_stop_all_services() { :; }
nobrand_start_enabled_services() { :; }

printf '{"value":"original"}\n' >"$NOBRAND_STATE_DIR/owned.json"
printf 'secret-config\n' >"$NOBRAND_CONFIG_DIR/owned.conf"
printf '{"protocol":"vless-sudoku","value":"original"}\n' >"$NOBRAND_VLESS_STATE_FILE"
printf '{"inbounds":[]}\n' >"$NOBRAND_VLESS_CONFIG_FILE"
printf '{"outbounds":[]}\n' >"$NOBRAND_VLESS_CLIENT_FILE"
mkdir -p "$fixture/external-xray"
printf 'must-not-back-up\n' >"$fixture/external-xray/config.json"
archive="$fixture/nobrand-backup.tar.gz"
nobrand_backup_create "$archive" >/dev/null
assert_file_mode 600 "$archive"
listing="$(tar -tzf "$archive")"
assert_contains "$listing" 'state/owned.json' 'backup state content'
assert_contains "$listing" 'config/owned.conf' 'backup config content'
assert_contains "$listing" 'state/vless-sudoku/state.json' 'backup VLESS state'
assert_contains "$listing" 'state/vless-sudoku/client.json' 'backup VLESS client export'
assert_contains "$listing" 'config/vless-sudoku/config.json' 'backup VLESS config'
assert_not_contains "$listing" 'external-xray' 'Xray-OneClick boundary'

printf '{"value":"changed"}\n' >"$NOBRAND_STATE_DIR/owned.json"
printf 'changed-config\n' >"$NOBRAND_CONFIG_DIR/owned.conf"
jq '.value="changed"' "$NOBRAND_VLESS_STATE_FILE" >"$fixture/vless.changed"
mv "$fixture/vless.changed" "$NOBRAND_VLESS_STATE_FILE"
nobrand_backup_restore "$archive" >/dev/null
assert_eq original "$(jq -r .value "$NOBRAND_STATE_DIR/owned.json")" 'restored state'
assert_eq secret-config "$(tr -d '\r\n' <"$NOBRAND_CONFIG_DIR/owned.conf")" 'restored config'
assert_eq original "$(jq -r .value "$NOBRAND_VLESS_STATE_FILE")" 'restored VLESS state'

if ( nb_assert_safe_nobrand_root /etc NOBRAND_STATE_DIR >/dev/null 2>&1 ); then
  fail 'restore root /etc must be rejected'
fi
if ( nb_assert_safe_nobrand_root /var NOBRAND_STATE_DIR >/dev/null 2>&1 ); then
  fail 'restore root /var must be rejected'
fi
if ( nb_assert_safe_nobrand_root "$fixture/../etc" NOBRAND_STATE_DIR >/dev/null 2>&1 ); then
  fail 'restore root containing .. must be rejected'
fi
safe="$(nb_assert_safe_nobrand_root "$NOBRAND_STATE_DIR" NOBRAND_STATE_DIR)"
assert_eq "$NOBRAND_STATE_DIR" "$safe" 'safe NoBrand namespace'

pass 'NoBrand backup/restore ownership and destructive path boundary'
