#!/usr/bin/env bash
# Native state fixtures are read by sourced production functions.
# shellcheck disable=SC2034
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/testlib.sh"
fixture="$(mktemp -d)"
trap 'rm -rf -- "$fixture"' EXIT
export NOBRAND_SYSTEM_ROOT="$fixture/system"
export NOBRAND_STATE_DIR="$fixture/nobrand-oneclick/state"
export NOBRAND_CONFIG_DIR="$fixture/nobrand-oneclick/config"
export NOBRAND_LIB_DIR="$fixture/nobrand-oneclick/lib"
export NOBRAND_LIFECYCLE_DIR="$fixture/nobrand-oneclick-lifecycle"
export NOBRAND_LIFECYCLE_LOCK_FILE="$fixture/run/nobrand-oneclick/lifecycle.lock"
export NOBRAND_INSTALL_SCRIPT_PATH="$fixture/bin/install-nobrand"
export NOBRAND_COMMAND_PATH="$fixture/bin/nobrand"
export NOBRAND_SHORT_COMMAND_PATH="$fixture/bin/nb"
export NOBRAND_TEST_MODE=1
mkdir -m 0700 "$fixture/run"
source_installer
ensure_management_dependencies() { :; }
nobrand_manager_bootstrap >/dev/null
nb_init_state_layout
nb_splicore_legacy_preflight || fail 'native manager initialization looks legacy'
assert_eq splicore-native "$(jq -r .architecture "$NOBRAND_REGISTRY_FILE")" 'native registry'
for path in "$NOBRAND_STATE_DIR/snell/instances" "$NOBRAND_STATE_DIR/vless-reality/instances" \
  "$NOBRAND_STATE_DIR/tuic/instances" "$NOBRAND_STATE_DIR/mieru/install-state.env" "$NOBRAND_LIB_DIR/bin/sing-box"; do
  [ ! -e "$path" ] || fail "fresh initialization created old namespace: $path"
done
assert_eq off "$TRAFFIC_PATTERN" 'supported Mieru default'
assert_eq "$NOBRAND_INSTALL_SCRIPT_PATH" "$(readlink "$NOBRAND_COMMAND_PATH")" 'manager command'
nb_splicore_call() { nb_splicore_python "$@"; }
printf 'native-secret-fixture\n' >"$NOBRAND_CONFIG_DIR/fixture.conf"
backup="$fixture/native.tar.gz"
nobrand_backup_create "$backup" >/dev/null
assert_file_mode 600 "$backup"
# The later function is the menu fixture stub; this call uses the real adapter.
# shellcheck disable=SC2218
nb_splicore_call inspect-backup --file "$backup" >/dev/null
assert_contains "$(tar -tzf "$backup")" 'config/fixture.conf' 'native product config backup'
assert_not_contains "$(tar -tzf "$backup")" '/bin/' 'backup omits runtime binaries'
# Registry reads only native ordinary nodes plus retained feature namespaces.
generation="$NOBRAND_STATE_DIR/splicore/generations/synthetic"
mkdir -p "$generation"
jq -n '{schema:1,config_schema:1,architecture:"splicore-native",owner:"nobrand-splicore-v1",nodes:[
 {id:"s1",protocol:"snell",client:{name:"alpha"},document:{listener:{host:"127.0.0.1",port:31001},display_endpoint:{host:"edge.example",port:443},settings:{version:5}}},
 {id:"r1",protocol:"vless-reality",client:{name:"reality"},document:{listener:{host:"127.0.0.1",port:31002},display_endpoint:{host:"edge.example",port:444},settings:{}},guard:{listen:{host:"127.0.0.1",port:31003}}},
 {id:"h1",protocol:"hysteria2",client:{name:"hy2"},document:{listener:{host:"127.0.0.1",port:31001},display_endpoint:{host:"edge.example",port:443},settings:{}}}
]}' >"$generation/desired.json"
ln -s generations/synthetic "$NOBRAND_STATE_DIR/splicore/current"
assert_eq snell:s1 "$(nb_registry_port_owner TCP 31001)" 'native TCP owner'
assert_eq hysteria2:h1 "$(nb_registry_port_owner UDP 31001)" 'native UDP owner'
assert_eq vless-reality:r1 "$(nb_registry_port_owner TCP 31002)" 'REALITY uses TCP'
assert_eq splicore-guard:r1 "$(nb_registry_port_owner TCP 31003)" 'guard port reservation'
# Menus must reject a stale selection before invoking the mutation callback.
read_tty() { printf -v "$1" alpha; }
nb_splicore_call() { printf '%s\n' '{"nodes":[{"id":"s1","name":"alpha","listener":{"port":31001}}]}'; }
nb_splicore_menu_select snell >/dev/null
nobrand_menu_selection_current || fail 'native selection rejected'
jq '.nodes[0].client.name="changed"' "$generation/desired.json" >"$fixture/changed.json"
mv "$fixture/changed.json" "$generation/desired.json"
if nobrand_menu_selection_current; then fail 'stale native menu selection accepted'; fi
# The standalone installer must reject an old architecture before locks or IO.
rm "$NOBRAND_STATE_DIR/splicore/current"
printf '%s\n' '{"schema_version":3,"ownership":"nobrand-v3"}' >"$NOBRAND_REGISTRY_FILE"
before="$(sha256sum "$NOBRAND_REGISTRY_FILE")"
if ( ACTION=nobrand-manager-upgrade; main ) >"$fixture/refusal" 2>&1; then fail 'legacy manager upgrade accepted'; fi
assert_eq "$before" "$(sha256sum "$NOBRAND_REGISTRY_FILE")" 'legacy bytes unchanged'
assert_contains "$(cat "$fixture/refusal")" 'No changes were made.' 'legacy notice'
pass 'native manager, schema, backup, transport registry, guard ports, menu selection and refusal'
