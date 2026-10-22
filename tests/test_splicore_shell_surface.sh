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

# Inject the release version independently of canonical release metadata. These
# cases also run when the fix commit is checked out without the v4 version bump.
(
  export NOBRAND_STATE_DIR="$fixture/version-cases/state"
  export NOBRAND_CONFIG_DIR="$fixture/version-cases/config"
  export NOBRAND_LIB_DIR="$fixture/version-cases/lib"
  export NOBRAND_LIFECYCLE_DIR="$fixture/version-cases/nobrand-oneclick-lifecycle"
  export NOBRAND_LIFECYCLE_TX_FILE="$NOBRAND_LIFECYCLE_DIR/transaction.env"
  export NOBRAND_LIFECYCLE_LOCK_FILE="$fixture/version-cases/run/nobrand-oneclick/lifecycle.lock"
  export NOBRAND_INSTALL_SCRIPT_PATH="$fixture/version-cases/bin/install-nobrand"
  export NOBRAND_COMMAND_PATH="$fixture/version-cases/bin/nobrand"
  export NOBRAND_SHORT_COMMAND_PATH="$fixture/version-cases/bin/nb"
  source_installer
  SCRIPT_VERSION=4.0.0
  LANG_ZH=0
  NOBRAND_LIFECYCLE_ACTIVE=0
  mkdir -p "$NOBRAND_STATE_DIR" "$(dirname "$NOBRAND_INSTALL_SCRIPT_PATH")"
  nb_write_schema_v3_file
  printf '%s\n' 'SCRIPT_NAME="NoBrand-OneClick"' 'SCRIPT_REPO="ike-sh/NoBrand-OneClick"' \
    'SCRIPT_VERSION="4.0.0"' >"$NOBRAND_INSTALL_SCRIPT_PATH"
  ln -s "$NOBRAND_INSTALL_SCRIPT_PATH" "$NOBRAND_COMMAND_PATH"
  ln -s "$NOBRAND_COMMAND_PATH" "$NOBRAND_SHORT_COMMAND_PATH"
  nb_lifecycle_begin install prepare 0 0 0 0 0 0 manager
  nb_lifecycle_tx_valid || fail 'current v4 transaction rejected'
  nb_lifecycle_mark_mutation_started
  nb_lifecycle_checkpoint install state-layout
  nb_lifecycle_complete install
  assert_eq CURRENT_COMPLETE "$(nb_classify_installation_state)" 'current v4 native classification'
  cp "$NOBRAND_LIFECYCLE_TX_FILE" "$fixture/valid-v4-transaction"
  cp "$NOBRAND_REGISTRY_FILE" "$fixture/valid-v4-registry"

  version_case_fingerprint() {
    find "$fixture/version-cases" -printf '%y %m %p %l\n' | sort
    find "$fixture/version-cases" -type f -exec sha256sum {} + | sort
  }
  assert_rejected_without_mutation() {
    local label="$1" before
    before="$(version_case_fingerprint)"
    if nb_lifecycle_tx_valid; then fail "$label: transaction accepted"; fi
    assert_eq AMBIGUOUS_OR_FOREIGN "$(nb_classify_installation_state)" "$label: classification"
    if ( nb_validate_authoritative_state_boundary ) >"$fixture/rejected" 2>&1; then
      fail "$label: mutation boundary accepted"
    fi
    assert_contains "$(cat "$fixture/rejected")" 'Unsupported NoBrand lifecycle state' "$label: diagnostic"
    if ( nb_lifecycle_begin repair prepare 0 0 0 0 0 0 manager ) >/dev/null 2>&1; then
      fail "$label: invalid transaction replaced"
    fi
    assert_eq "$before" "$(version_case_fingerprint)" "$label: rejected state remains unchanged"
  }

  for version in 4.0.0 4.0.1 4.1.0; do
    sed "s/^MANAGER_VERSION=.*/MANAGER_VERSION=$version/" "$fixture/valid-v4-transaction" >"$NOBRAND_LIFECYCLE_TX_FILE"
    nb_lifecycle_tx_valid || fail "supported v4 state rejected: $version"
  done
  for version in '' 4 4.0 v4..0 foo v4.0.0 04.0.0 4.00.0 4.0.00 4.0.x 4.0.0-rc.1 4.0.0+build 3.2.6 5.0.0; do
    sed "s/^MANAGER_VERSION=.*/MANAGER_VERSION=$version/" "$fixture/valid-v4-transaction" >"$NOBRAND_LIFECYCLE_TX_FILE"
    assert_rejected_without_mutation "manager version '$version'"
  done
  cp "$fixture/valid-v4-transaction" "$NOBRAND_LIFECYCLE_TX_FILE"

  for operation in repair configure; do
    scope=manager
    [ "$operation" != configure ] || scope=ingress
    nb_lifecycle_begin "$operation" prepare 0 0 0 0 0 0 "$scope"
    nb_lifecycle_mark_mutation_started
    nb_lifecycle_checkpoint "$operation" state-committed
    nb_lifecycle_complete "$operation"
    nb_lifecycle_tx_valid || fail "valid v4 $operation completion rejected"
  done
  for version in 3.2.6 5.0.0; do
    sed -i "s/^SCRIPT_VERSION=.*/SCRIPT_VERSION=\"$version\"/" "$NOBRAND_INSTALL_SCRIPT_PATH"
    assert_eq AMBIGUOUS_OR_FOREIGN "$(nb_classify_installation_state)" 'incompatible installed manager'
  done
  sed -i 's/^SCRIPT_VERSION=.*/SCRIPT_VERSION="4.0.0"/' "$NOBRAND_INSTALL_SCRIPT_PATH"
  for field in '.architecture="multi-core"' '.ownership="foreign"' '.schema_version=4' '.config_schema=2'; do
    jq "$field" "$fixture/valid-v4-registry" >"$NOBRAND_REGISTRY_FILE"
    assert_rejected_without_mutation "registry $field"
  done
  cp "$fixture/valid-v4-registry" "$NOBRAND_REGISTRY_FILE"
  sed 's/^SCHEMA_GENERATION=.*/SCHEMA_GENERATION=4/' "$fixture/valid-v4-transaction" >"$NOBRAND_LIFECYCLE_TX_FILE"
  assert_rejected_without_mutation 'future lifecycle schema'
  sed 's/^FORMAT=.*/FORMAT=nobrand-lifecycle-v3/' "$fixture/valid-v4-transaction" >"$NOBRAND_LIFECYCLE_TX_FILE"
  assert_rejected_without_mutation 'future lifecycle format'
  sed -e 's/^FORMAT=.*/FORMAT=nobrand-lifecycle-v1/' -e '/^SCOPE=/d' -e '/^MUTATION_STARTED=/d' \
    "$fixture/valid-v4-transaction" >"$NOBRAND_LIFECYCLE_TX_FILE"
  assert_rejected_without_mutation 'retired multi-core lifecycle format'
  cp "$fixture/valid-v4-transaction" "$NOBRAND_LIFECYCLE_TX_FILE"

  # Historical v3 multi-core registry and its owned runtime namespace, rather
  # than a native graph with only its version string relabeled as legacy.
  printf '%s\n' '{"schema_version":3,"project":"NoBrand-OneClick","ownership":"nobrand-v3","author":"ike"}' >"$NOBRAND_REGISTRY_FILE"
  mkdir -p "$NOBRAND_STATE_DIR/mieru"
  printf '%s\n' 'SCHEMA_VERSION=3' 'OWNERSHIP=nobrand-v3' 'INSTALL_METHOD=nobrand-v3' >"$NOBRAND_STATE_DIR/mieru/install-state.env"
  before="$(version_case_fingerprint)"
  for action in nobrand-manager-upgrade nobrand-uninstall nobrand-runtime; do
    if ( ACTION="$action"; NOBRAND_RUNTIME_ARGS=(purge); main ) >"$fixture/legacy-version-refusal" 2>&1; then
      fail "legacy lifecycle allowed: $action"
    fi
    assert_contains "$(cat "$fixture/legacy-version-refusal")" 'matching legacy NoBrand version' 'legacy guidance'
    assert_eq "$before" "$(version_case_fingerprint)" 'real v3 multi-core remains unchanged'
  done
  pass 'v4 lifecycle version, architecture, ownership and schema boundaries; legacy/future rejection without mutation'
)
# The standalone installer must reject an old architecture before locks or IO.
rm "$NOBRAND_STATE_DIR/splicore/current"
printf '%s\n' '{"schema_version":3,"ownership":"nobrand-v3"}' >"$NOBRAND_REGISTRY_FILE"
before="$(sha256sum "$NOBRAND_REGISTRY_FILE")"
if ( ACTION=nobrand-manager-upgrade; main ) >"$fixture/refusal" 2>&1; then fail 'legacy manager upgrade accepted'; fi
assert_eq "$before" "$(sha256sum "$NOBRAND_REGISTRY_FILE")" 'legacy bytes unchanged'
assert_contains "$(cat "$fixture/refusal")" 'No changes were made.' 'legacy notice'
# Exercise real manager uninstall checkpoints (including the absent-registry
# tail) and a fresh bootstrap. Only external host firewall/init effects are
# mocked; state/commands, version checks and lifecycle writes remain real.
nb_write_schema_v3_file
nft() { return 1; }
nb_service_manager() { printf fixture; }
nb_strict_firewall_clear_all() { :; }
YES=1
nobrand_uninstall >/dev/null
nobrand_uninstall_postcondition || fail 'manager uninstall retained resources'
assert_eq CLEAN "$(nb_classify_installation_state)" 'uninstall reaches clean state'
nobrand_manager_bootstrap >/dev/null
nobrand_manager_installation_valid || fail 'manager reinstall rejected'
assert_eq CURRENT_COMPLETE "$(nb_classify_installation_state)" 'manager reinstall completes'
pass 'current manager uninstall, missing-registry checkpoints and reinstall'
pass 'native manager, schema, backup, transport registry, guard ports, menu selection and refusal'
