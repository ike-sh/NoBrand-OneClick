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
export NOBRAND_INSTALL_SCRIPT_PATH="$fixture/commands/install-nobrand"
export NOBRAND_COMMAND_PATH="$fixture/commands/nobrand"
export NOBRAND_SHORT_COMMAND_PATH="$fixture/commands/nb"
export NOBRAND_LEGACY_MIERU_STATE_DIR="$fixture/mita-oneclick"
mkdir -p "$(dirname "$NOBRAND_LIFECYCLE_LOCK_FILE")"
chmod 0700 "$(dirname "$NOBRAND_LIFECYCLE_LOCK_FILE")"
source_installer

nb_init_state_layout
nb_schema_v3_file_valid || fail 'fresh state marker must be exact schema v3'
assert_eq 700 "$(stat -c %a "$NOBRAND_STATE_DIR")" 'schema-v3 state root mode'
assert_eq 600 "$(stat -c %a "$NOBRAND_REGISTRY_FILE")" 'schema-v3 state marker mode'
assert_eq 711 "$(stat -c %a "$NOBRAND_CONFIG_DIR")" 'schema-v3 config root is traversable but not listable'
assert_eq 711 "$(stat -c %a "$NOBRAND_SSH_CONFIG_DIR")" 'SSH config root is traversable but not listable'
assert_eq 755 "$(stat -c %a "$NOBRAND_SSH_AUTHORIZED_KEYS_DIR")" 'sshd can traverse authorized-keys directory'
assert_eq 700 "$(stat -c %a "$NOBRAND_TUIC_CONFIG_DIR")" 'TUIC secret config directory remains private'
assert_eq 700 "$(stat -c %a "$NOBRAND_REALITY_STATE_DIR")" 'REALITY state instance root remains private'
assert_eq 700 "$(stat -c %a "$NOBRAND_REALITY_CONFIG_DIR")" 'REALITY secret config instance root remains private'
assert_eq 755 "$(stat -c %a "$NOBRAND_LIB_DIR")" 'runtime library root is service-traversable'
assert_eq 755 "$(stat -c %a "$NOBRAND_BIN_DIR")" 'runtime binary directory is service-traversable'
assert_eq 755 "$(stat -c %a "$NOBRAND_SNELL_RUNTIME_DIR")" 'Snell runtime directory is service-traversable'

mkdir -p "$(dirname "$NOBRAND_INSTALL_SCRIPT_PATH")"
mkdir -p "$NOBRAND_SNELL_STATE_DIR" "$NOBRAND_SNELL_CONFIG_DIR"
printf '%s\n' '{"schema_version":3,"protocol":"snell","psk":"preserve-manager-upgrade"}' \
  >"$NOBRAND_SNELL_STATE_DIR/preserve.json"
printf '%s\n' '[snell-server]' 'psk = preserve-manager-upgrade' \
  >"$NOBRAND_SNELL_CONFIG_DIR/preserve.conf"
protocol_state_before="$(find "$NOBRAND_STATE_DIR" "$NOBRAND_CONFIG_DIR" -type f -print0 | sort -z | xargs -0 sha256sum)"
require_root() { :; }
nobrand_manager_upgrade >/dev/null
protocol_state_after="$(find "$NOBRAND_STATE_DIR" "$NOBRAND_CONFIG_DIR" -type f -print0 | sort -z | xargs -0 sha256sum)"
assert_eq "$protocol_state_before" "$protocol_state_after" 'manager-only upgrade preserves protocol state byte-for-byte'
assert_eq "$NOBRAND_INSTALL_SCRIPT_PATH" "$(readlink "$NOBRAND_COMMAND_PATH")" 'nobrand targets canonical installer'
assert_eq "$NOBRAND_COMMAND_PATH" "$(readlink "$NOBRAND_SHORT_COMMAND_PATH")" 'nb targets nobrand'
[ ! -e "$fixture/commands/mita" ] || fail 'Mita management wrapper must not be installed'
[ ! -e "$fixture/commands/install-mita" ] || fail 'install-mita must not be installed'

legacy="$NOBRAND_LEGACY_MIERU_STATE_DIR"
mkdir -p "$legacy"
printf 'do-not-read-or-change\n' >"$legacy/users.json"
legacy_hash="$(sha256sum "$legacy/users.json")"
NOBRAND_LEGACY_MIERU_STATE_DIR="$legacy" bash "$TEST_ROOT/install-nobrand.sh" --version   | grep -qx 'NoBrand-OneClick 3.2.2' || fail 'version must bypass legacy state'
NOBRAND_LEGACY_MIERU_STATE_DIR="$legacy" bash "$TEST_ROOT/install-nobrand.sh" --help   | grep -q 'NoBrand-OneClick 3.2.2' || fail 'help must bypass legacy state'
if NOBRAND_LEGACY_MIERU_STATE_DIR="$legacy"    NOBRAND_STATE_DIR="$fixture/unused-state"    bash "$TEST_ROOT/install-nobrand.sh" status >/dev/null 2>&1; then
  fail 'stateful action must fail closed when a legacy Mieru root exists'
fi
assert_eq "$legacy_hash" "$(sha256sum "$legacy/users.json")" 'legacy state remains byte-identical'

unknown="$fixture/unknown/nobrand-oneclick"
mkdir -p "$unknown"
printf '{"schema_version":1,"secret":"must-remain"}\n' >"$unknown/state.json"
unknown_hash="$(sha256sum "$unknown/state.json")"
if (
  NOBRAND_STATE_DIR="$unknown"
  NOBRAND_REGISTRY_FILE="$unknown/state.json"
  NOBRAND_LEGACY_MIERU_STATE_DIR="$fixture/no-legacy"
  ensure_manager_state_layout 1
) >/dev/null 2>&1; then
  fail 'unknown NoBrand state schema must fail closed'
fi
assert_eq "$unknown_hash" "$(sha256sum "$unknown/state.json")" 'unknown NoBrand state remains byte-identical'

pass 'schema v3 clean-break, legacy fail-closed behavior, and nobrand/nb topology'
