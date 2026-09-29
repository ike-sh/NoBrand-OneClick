#!/usr/bin/env bash
# The fixture replaces only operating-system dependency discovery.
# shellcheck disable=SC2034
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/testlib.sh"

fixture="$(mktemp -d)"
trap 'rm -rf -- "$fixture"' EXIT
export NOBRAND_STATE_DIR="$fixture/var/lib/nobrand-oneclick"
export NOBRAND_CONFIG_DIR="$fixture/etc/nobrand-oneclick"
export NOBRAND_LIB_DIR="$fixture/usr/local/lib/nobrand-oneclick"
export NOBRAND_LIFECYCLE_DIR="$fixture/var/lib/nobrand-oneclick-lifecycle"
export NOBRAND_LIFECYCLE_LOCK_FILE="$fixture/run/nobrand-oneclick/lifecycle.lock"
export NOBRAND_INSTALL_SCRIPT_PATH="$fixture/bin/install-nobrand"
export NOBRAND_COMMAND_PATH="$fixture/bin/nobrand"
export NOBRAND_SHORT_COMMAND_PATH="$fixture/bin/nb"
export NOBRAND_TEST_MODE=1
mkdir -p "$(dirname "$NOBRAND_LIFECYCLE_LOCK_FILE")" "$fixture/bin"
chmod 0700 "$(dirname "$NOBRAND_LIFECYCLE_LOCK_FILE")"
source_installer
nb_init_state_layout

id=s1111111111111111
host=edge.example.com
snell_generate_state "$(snell_state_path "$id")" "$id" legacy-node 5 \
  dummy-psk 0.0.0.0 14934 custom "$host" 14934
snell_generate_server_config "$(snell_config_path "$id")" 5 0.0.0.0 14934 dummy-psk
state_before="$(sha256sum "$(snell_state_path "$id")")"
config_before="$(sha256sum "$(snell_config_path "$id")")"

cat >"$NOBRAND_INSTALL_SCRIPT_PATH" <<'SH'
#!/usr/bin/env bash
SCRIPT_NAME="NoBrand-OneClick"
SCRIPT_REPO="ike-sh/NoBrand-OneClick"
SCRIPT_VERSION="3.2.4"
if [ "${1:-}" = --version ]; then printf '%s %s\n' "$SCRIPT_NAME" "$SCRIPT_VERSION"; fi
SH
chmod 0755 "$NOBRAND_INSTALL_SCRIPT_PATH"
ln -s "$NOBRAND_INSTALL_SCRIPT_PATH" "$NOBRAND_COMMAND_PATH"
ln -s "$NOBRAND_COMMAND_PATH" "$NOBRAND_SHORT_COMMAND_PATH"
assert_eq 3.2.4 "$(nb_installed_manager_version)" 'pre-upgrade manager version'
assert_eq CURRENT_COMPLETE "$(nb_classify_installation_state)" \
  '3.2.4 manager and schema-v3 state are recognized'

require_root() { return 0; }
require_linux() { return 0; }
detect_pkg_manager() { printf deb; }
ensure_management_dependencies() { return 0; }
INSTALL_SCRIPT_PATH="$TEST_ROOT/install-nobrand.sh"
nobrand_manager_bootstrap || fail 'direct manager upgrade failed'

assert_eq 3.2.6 "$(nb_installed_manager_version)" 'directly upgraded manager version'
assert_eq 'NoBrand-OneClick 3.2.6' \
  "$("$NOBRAND_COMMAND_PATH" --version | head -n1)" 'installed nobrand version'
assert_eq "$state_before" "$(sha256sum "$(snell_state_path "$id")")" \
  '3.2.4 Snell state preserved byte-for-byte'
assert_eq "$config_before" "$(sha256sum "$(snell_config_path "$id")")" \
  '3.2.4 server config preserved byte-for-byte'
assert_eq "$host" "$(snell_state_field "$id" advertise_host)" \
  'domain Display Endpoint preserved'
assert_contains "$(snell_export_surge "$id")" "snell, $host, 14934" \
  'upgraded manager exports original domain'
assert_eq CURRENT_COMPLETE "$(nb_classify_installation_state)" 'upgraded state complete'
assert_eq complete "$(nb_lifecycle_field STATUS)" 'manager repair completed'
flock -n "$NOBRAND_LIFECYCLE_LOCK_FILE" -c true \
  || fail 'manager upgrade retained lifecycle lock'
pass '3.2.4 manager upgrades directly to 3.2.6 without state, config or domain migration'
