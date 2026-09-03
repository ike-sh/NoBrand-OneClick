#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/testlib.sh"

fixture="$(mktemp -d)"
trap 'rm -rf -- "$fixture"' EXIT

export NOBRAND_STATE_DIR="$fixture/var/lib/nobrand-oneclick"
export NOBRAND_CONFIG_DIR="$fixture/etc/nobrand-oneclick"
export NOBRAND_LIB_DIR="$fixture/usr/local/lib/nobrand-oneclick"
export NOBRAND_LIFECYCLE_DIR="$fixture/var/lib/nobrand-oneclick-lifecycle"
export NOBRAND_LIFECYCLE_TX_FILE="$NOBRAND_LIFECYCLE_DIR/transaction.env"
export NOBRAND_LIFECYCLE_LOCK_FILE="$fixture/run/nobrand-oneclick/lifecycle.lock"
export NOBRAND_INSTALL_SCRIPT_PATH="$fixture/usr/local/bin/install-nobrand"
export NOBRAND_COMMAND_PATH="$fixture/usr/local/bin/nobrand"
export NOBRAND_SHORT_COMMAND_PATH="$fixture/usr/local/bin/nb"
export NOBRAND_LEGACY_MIERU_STATE_DIR="$fixture/var/lib/mita-oneclick"
export NOBRAND_SNELL_SYSTEMD_TEMPLATE="$fixture/systemd/nobrand-snell@.service"
export NOBRAND_TUIC_SYSTEMD_TEMPLATE="$fixture/systemd/nobrand-tuic@.service"
export NOBRAND_REALM_SYSTEMD_SERVICE="$fixture/systemd/nobrand-realm.service"
export NOBRAND_REALM_OPENRC_SERVICE="$fixture/openrc/nobrand-realm"
export NOBRAND_SSH_CONFIG_MAIN="$fixture/etc/ssh/sshd_config"
export NOBRAND_SSH_CONFIG_DROPIN="$fixture/etc/ssh/sshd_config.d/90-nobrand-ssh-tunnel.conf"
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
export MITA_SOURCE_ONLY=1
export NOBRAND_TEST_MODE=1

# Source the maintained modules directly. Generated installers deliberately
# remain untouched until the repository-wide release gate runs.
# shellcheck disable=SC1091
source "$TEST_ROOT/src/05-constants.sh"
msg() { printf '%s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*" >&2; }
t() { [ "${LANG_ZH:-1}" -eq 1 ] && printf '%s\n' "$1" || printf '%s\n' "$2"; }
die() { printf '[ERROR] %s\n' "$*" >&2; return 1; }
# shellcheck disable=SC1091
source "$TEST_ROOT/src/15-core-state.sh"
# shellcheck disable=SC1091
source "$TEST_ROOT/src/18-core-nodes.sh"
# shellcheck disable=SC1091
source "$TEST_ROOT/src/61-ssh-tunnel.sh"
# shellcheck disable=SC1091
source "$TEST_ROOT/src/80-lifecycle.sh"
# shellcheck disable=SC1091
source "$TEST_ROOT/src/99-main.sh"

BASE_SCRIPT_VERSION="$SCRIPT_VERSION"
V320_RELEASE_COMMIT=7d6aa64e3cacd4d1a395b33fbe926fc934c7269a
V320_RELEASE_SIZE=984394
V320_RELEASE_SHA256=80acfe06b67a7d39e280598b25486b98515c459bd960bb944c05a9ff9e80fe87
V320_RELEASE_CACHE="$fixture/v3.2.0-install-nobrand.sh"

reset_fixture() {
  rm -rf -- "$NOBRAND_STATE_DIR" "$NOBRAND_CONFIG_DIR" "$NOBRAND_LIB_DIR" \
    "$NOBRAND_LIFECYCLE_DIR" "$NOBRAND_LEGACY_MIERU_STATE_DIR" \
    "$(dirname "$NOBRAND_INSTALL_SCRIPT_PATH")" "$fixture/foreign" "$fixture/probe" \
    "$fixture/systemd" "$fixture/openrc"
  mkdir -p "$(dirname "$NOBRAND_LIFECYCLE_LOCK_FILE")"
  chmod 0700 "$(dirname "$NOBRAND_LIFECYCLE_LOCK_FILE")"
  rm -f -- "$NOBRAND_LIFECYCLE_LOCK_FILE"
  SCRIPT_VERSION="$BASE_SCRIPT_VERSION"
  export NOBRAND_LIFECYCLE_ACTIVE=0
  NOBRAND_LIFECYCLE_OPERATION=""
  NOBRAND_LIFECYCLE_LOCK_HELD=0
  ACTION=""
  YES=0
  unset NOBRAND_TEST_INTERRUPT_INSTALL_AT NOBRAND_TEST_INTERRUPT_REPAIR_AT \
    NOBRAND_TEST_INTERRUPT_UNINSTALL_AT
}

write_manager() {
  local version="$1"
  mkdir -p "$(dirname "$NOBRAND_INSTALL_SCRIPT_PATH")"
  printf '%s\n' \
    'SCRIPT_NAME="NoBrand-OneClick"' \
    'SCRIPT_REPO="ike-sh/NoBrand-OneClick"' \
    "SCRIPT_VERSION=\"${version}\"" \
    >"$NOBRAND_INSTALL_SCRIPT_PATH"
  chmod 0755 "$NOBRAND_INSTALL_SCRIPT_PATH"
}

write_v320_release_manager() {
  mkdir -p "$(dirname "$NOBRAND_INSTALL_SCRIPT_PATH")"
  if [ ! -f "$V320_RELEASE_CACHE" ]; then
    git -c safe.directory="$TEST_ROOT" -C "$TEST_ROOT" \
      show "${V320_RELEASE_COMMIT}:install-nobrand.sh" >"$V320_RELEASE_CACHE"
  fi
  cp "$V320_RELEASE_CACHE" "$NOBRAND_INSTALL_SCRIPT_PATH"
  assert_eq "$V320_RELEASE_SIZE" \
    "$(wc -c <"$NOBRAND_INSTALL_SCRIPT_PATH" | tr -d '[:space:]')" \
    'exact v3.2.0 installer fixture size'
  assert_eq "$V320_RELEASE_SHA256" \
    "$(sha256sum "$NOBRAND_INSTALL_SCRIPT_PATH" | awk '{print $1}')" \
    'exact v3.2.0 installer fixture SHA256'
  chmod 0755 "$NOBRAND_INSTALL_SCRIPT_PATH"
}

install_v320_release_fixture() {
  local log="$fixture/v3.2.0-install.log" path

  rm -f -- "$log" "$fixture/v3.2.0-install-complete"
  write_v320_release_manager
  (
    trap - EXIT HUP INT TERM
    set -Eeuo pipefail
    MITA_SOURCE_ONLY=1
    # shellcheck disable=SC1090
    source "$NOBRAND_INSTALL_SCRIPT_PATH"

    # The immutable installer may only observe or create paths below this
    # disposable root. Package, account, service, and firewall effects are
    # replaced below while the historical install orchestration, state layout,
    # user-state writer, install-state writer, and self-install path remain real.
    for path in \
      "$NOBRAND_STATE_DIR" "$NOBRAND_CONFIG_DIR" "$NOBRAND_LIB_DIR" \
      "$NOBRAND_REGISTRY_FILE" "$NOBRAND_BACKUP_DIR" "$NOBRAND_LOCK_DIR" \
      "$NOBRAND_INSTALL_SCRIPT_PATH" "$NOBRAND_COMMAND_PATH" \
      "$NOBRAND_SHORT_COMMAND_PATH" "$NOBRAND_BIN_DIR" \
      "$MITA_MANAGER_STATE_DIR" "$MITA_USERS_BACKUP_DIR" \
      "$MITA_BIN" "$MITA_STATE" "$MITA_USERS_STATE" "$MITA_MARKER"; do
      case "$path" in
        "$fixture"/*) ;;
        *) printf 'unsafe v3.2.0 install fixture path: %s\n' "$path" >&2; exit 97 ;;
      esac
    done

    # Minimal Rocky images do not ship diffutils. The historical self-install
    # uses only `cmp -s`; reproduce that exact check with sha256sum, then verify
    # the installed public artifact again against its immutable digest below.
    cmp() {
      [ "${1:-}" = -s ] || return 2
      shift
      [ "$#" -eq 2 ] || return 2
      [ -f "$1" ] && [ -f "$2" ] || return 1
      [ "$(sha256sum "$1" | awk '{print $1}')" = \
        "$(sha256sum "$2" | awk '{print $1}')" ]
    }
    mktemp_file() { mktemp "$fixture/v3.2.0-tmp.XXXXXX"; }
    require_root() { return 0; }
    require_linux() { return 0; }
    require_cmd() { return 0; }
    detect_pkg_manager() { printf deb; }
    detect_arch() { printf amd64; }
    ensure_management_dependencies() { return 0; }
    mita_installed() { return 1; }
    mieru_prepare_noninteractive_ingress_endpoint() { return 0; }
    ensure_config_noninteractive() { return 0; }
    ensure_install_port_available() { return 0; }
    mieru_resolve_runtime() {
      MIERU_RUNTIME_RESOLVED_VERSION=3.35.0
      MIERU_RUNTIME_RESOLVED_URL=https://fixture.invalid/mita.tar.gz
      MIERU_RUNTIME_RESOLVED_SHA256=''
      MIERU_RUNTIME_RESOLVED_CHECKSUM_URL=''
    }
    download_package() { : >"$2"; }
    mieru_runtime_snapshot() { printf fixture-runtime-snapshot; }
    install_package() {
      mkdir -p "$NOBRAND_BIN_DIR"
      printf '%s\n' 'fixture Mita runtime' >"$MITA_BIN"
      chmod 0755 "$MITA_BIN"
    }
    mieru_assert_runtime_version() { return 0; }
    mieru_runtime_rollback() { return 0; }
    mieru_runtime_commit() { return 0; }
    add_op_user() { return 0; }
    warn_traffic_unsupported() { return 0; }
    warn_low_entropy_unsupported() { return 0; }
    admin_lock_acquire() { return 0; }
    admin_lock_release() { return 0; }
    users_tx_snapshot() { printf fixture-users-snapshot; }
    users_tx_rollback() { return 0; }
    users_tx_commit() { return 0; }
    install_users_scheduler() { return 0; }
    nb_prepare_ingress_deployment() {
      # Consumed by the sourced immutable v3.2.0 installer.
      # shellcheck disable=SC2034
      INGRESS_ENFORCEMENT_RESOLVED=false
      # shellcheck disable=SC2034
      INGRESS_ENFORCEMENT_METHOD=none
      # shellcheck disable=SC2034
      INGRESS_LOCAL_ADDRESS=''
    }
    apply_users_config() {
      mkdir -p "$NOBRAND_CONFIG_DIR/mieru"
      printf '%s\n' 'fixture Mita config' >"$NOBRAND_CONFIG_DIR/mieru/config.json"
    }
    multi_user_port_protocol_pairs() { printf 'TCP|32032\n'; }
    open_firewall_for_pairs() { return 0; }
    verify_mita_running() { return 0; }
    profile_reconcile_metadata() { return 0; }
    harden_mita_permissions() { return 0; }
    client_exports_clear_current() { return 0; }
    install_fresh_rollback() { return 0; }
    offer_bbr_fq() { return 0; }
    print_summary() { : >"$fixture/v3.2.0-install-complete"; }

    USERNAME=v320-fixture
    PASSWORD=v320-fixture-password
    PORT=32032
    PORT_RANGE=''
    PROTOCOL=TCP
    PROFILE=balanced
    ADVERTISE_HOST=127.0.0.1
    ADVERTISE_PORT=32032
    MTU=1400
    MTU_POLICY=auto
    TRAFFIC_PATTERN=off
    TRAFFIC_SEED=''
    LOW_ENTROPY_MODE=LOW_ENTROPY_MODE_OFF
    MULTIPLEXING=MULTIPLEXING_OFF
    HANDSHAKE_MODE=HANDSHAKE_NO_WAIT
    MIERU_CHANNEL=stable
    MIERU_VERSION=''
    YES=1
    # Consumed by the sourced immutable v3.2.0 installer.
    # shellcheck disable=SC2034
    DRY_RUN=0
    do_install
    mita_v3_install_state_valid
  ) >"$log" 2>&1 || {
    sed -n '1,200p' "$log" >&2 || true
    fail 'exact v3.2.0 fixture install failed'
  }

  [ -e "$fixture/v3.2.0-install-complete" ] \
    || fail 'exact v3.2.0 install did not reach its final summary boundary'
  assert_eq "$V320_RELEASE_SIZE" \
    "$(wc -c <"$NOBRAND_INSTALL_SCRIPT_PATH" | tr -d '[:space:]')" \
    'exact v3.2.0 installed manager size'
  assert_eq "$V320_RELEASE_SHA256" \
    "$(sha256sum "$NOBRAND_INSTALL_SCRIPT_PATH" | awk '{print $1}')" \
    'exact v3.2.0 installed manager SHA256'
  assert_eq "$NOBRAND_INSTALL_SCRIPT_PATH" "$(readlink "$NOBRAND_COMMAND_PATH")" \
    'exact v3.2.0 installed nobrand command'
  assert_eq "$NOBRAND_COMMAND_PATH" "$(readlink "$NOBRAND_SHORT_COMMAND_PATH")" \
    'exact v3.2.0 installed nb command'
  nb_schema_v3_file_valid || fail 'exact v3.2.0 install did not create valid schema-v3 state'
  [ -s "$MITA_STATE" ] && [ -s "$MITA_USERS_STATE" ] && [ -s "$MITA_BIN" ] \
    || fail 'exact v3.2.0 install did not create its managed Mieru state'
  [ -d "$NOBRAND_CONFIG_DIR" ] && [ -d "$NOBRAND_LIB_DIR" ] \
    || fail 'exact v3.2.0 install did not create managed config/runtime roots'
  assert_state CURRENT_COMPLETE 'exact v3.2.0 fixture starts from a complete install'
}

reproduce_v320_partial_uninstall() {
  local log="$fixture/v3.2.0-uninstall-reproduction.log" rc path
  install_v320_release_fixture
  rm -rf -- "$NOBRAND_CONFIG_DIR" "$NOBRAND_LIB_DIR"
  set +e
  (
    trap - EXIT HUP INT TERM
    set -Eeuo pipefail
    # Redirect every path touched or probed by the immutable uninstaller into
    # this disposable fixture before sourcing it. Runtime/service/firewall
    # operations are stubbed below; no host resource is reachable.
    NOBRAND_FORWARD_STATE_FILE="$NOBRAND_STATE_DIR/forward/state.json"
    NOBRAND_REALM_RUNTIME_META="$NOBRAND_STATE_DIR/forward/realm-runtime.env"
    NOBRAND_REALM_SYSTEMD_SERVICE="$fixture/systemd/nobrand-realm.service"
    NOBRAND_REALM_OPENRC_SERVICE="$fixture/openrc/nobrand-realm"
    NOBRAND_FIREWALL_OWNED_STATE="$NOBRAND_STATE_DIR/firewall/owned.tsv"
    NOBRAND_INGRESS_FIREWALL_STATE_FILE="$NOBRAND_STATE_DIR/ingress/firewall.json"
    NOBRAND_INGRESS_FIREWALL_RULESET="$NOBRAND_CONFIG_DIR/ingress/firewall.nft"
    MITA_ADMIN_LOCK="$NOBRAND_STATE_DIR/mieru/admin.lock"
    MITA_SOURCE_ONLY=1
    # shellcheck disable=SC1090
    source "$NOBRAND_INSTALL_SCRIPT_PATH"
    # The real IPLC reproduction used GNU readlink -m. BusyBox lacks that
    # option and can otherwise concatenate failed realpath output, causing the
    # immutable uninstaller to stop one find earlier than the reproduced bug.
    if ! readlink -m -- "$fixture/readlink-probe" >/dev/null 2>&1; then
      readlink() {
        if [ "${1:-}" = -m ]; then
          shift
          [ "${1:-}" != -- ] || shift
          python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$1"
        else
          command readlink "$@"
        fi
      }
    fi
    for path in \
      "$NOBRAND_STATE_DIR" "$NOBRAND_CONFIG_DIR" "$NOBRAND_LIB_DIR" \
      "$NOBRAND_INSTALL_SCRIPT_PATH" "$NOBRAND_COMMAND_PATH" "$NOBRAND_SHORT_COMMAND_PATH" \
      "$NOBRAND_SNELL_SYSTEMD_TEMPLATE" "$NOBRAND_TUIC_SYSTEMD_TEMPLATE" \
      "$NOBRAND_FORWARD_STATE_FILE" "$NOBRAND_REALM_RUNTIME_META" \
      "$NOBRAND_REALM_SYSTEMD_SERVICE" "$NOBRAND_REALM_OPENRC_SERVICE" \
      "$NOBRAND_FIREWALL_OWNED_STATE" "$NOBRAND_INGRESS_FIREWALL_STATE_FILE" \
      "$NOBRAND_INGRESS_FIREWALL_RULESET" "$MITA_ADMIN_LOCK"; do
      case "$path" in "$fixture"/*) ;; *) printf 'unsafe v3.2.0 fixture path: %s\n' "$path" >&2; exit 97 ;; esac
    done
    require_root() { return 0; }
    mita_uninstall_target_present() { return 1; }
    ssh_tunnel_state_exists() { return 1; }
    admin_lock_acquire() { return 0; }
    admin_lock_release() { return 0; }
    snell_instance_ids() { return 0; }
    hysteria2_state_exists() { return 1; }
    vless_sudoku_state_exists() { return 1; }
    reality_instance_ids() { return 0; }
    tuic_instance_ids() { return 0; }
    reality_remove_service_runtime_if_owned() { return 0; }
    nb_service_manager() { printf none; }
    nb_strict_firewall_clear_all() { return 0; }
    nft() { return 1; }
    YES=1
    nobrand_uninstall
  ) >"$log" 2>&1
  rc=$?
  set -e
  [ "$rc" -ne 0 ] || fail 'immutable v3.2.0 uninstall unexpectedly crossed missing-config boundary'
  assert_contains "$(cat "$log")" "$NOBRAND_CONFIG_DIR" \
    'immutable v3.2.0 failure identifies absent config root'
  assert_contains "$(cat "$log")" 'No such file or directory' \
    'immutable v3.2.0 reproduces unguarded find failure'
  [ -d "$NOBRAND_STATE_DIR" ] && nb_directory_empty "$NOBRAND_STATE_DIR" \
    || fail 'immutable v3.2.0 did not leave the state root empty'
  [ ! -e "$NOBRAND_CONFIG_DIR" ] || fail 'immutable v3.2.0 recreated absent config root'
  assert_eq "$V320_RELEASE_SIZE" \
    "$(wc -c <"$NOBRAND_INSTALL_SCRIPT_PATH" | tr -d '[:space:]')" \
    'v3.2.0 manager remains after failed uninstall'
  assert_eq "$V320_RELEASE_SHA256" \
    "$(sha256sum "$NOBRAND_INSTALL_SCRIPT_PATH" | awk '{print $1}')" \
    'v3.2.0 manager identity remains after failed uninstall'
}

write_schema() {
  mkdir -p "$NOBRAND_STATE_DIR"
  nb_write_schema_v3_file
}

write_legacy_v22_state() {
  mkdir -p "$NOBRAND_LEGACY_MIERU_STATE_DIR"
  printf '%s\n' \
    'INSTALL_METHOD=oneclick' 'PORT=2088' "PORT_RANGE=''" 'PROTOCOL=TCP' \
    'INSTALL_SCRIPT=/usr/local/bin/install-mita' \
    >"$NOBRAND_LEGACY_MIERU_STATE_DIR/install-state.env"
}

assert_state() {
  local expected="$1" label="$2" actual
  actual="$(nb_classify_installation_state)"
  assert_eq "$expected" "$actual" "$label"
}

fake_lifecycle_lock_acquire() { NOBRAND_LIFECYCLE_LOCK_HELD=1; }
fake_lifecycle_lock_release() { NOBRAND_LIFECYCLE_LOCK_HELD=0; }

# Failed path utilities must never leak their partial stdout into a destructive
# root. This models BusyBox realpath's unsupported -m/-- behavior directly.
(
  portable_parent="$fixture/portable-path-parent"
  portable_root="$portable_parent/nobrand-oneclick/missing"
  mkdir -p "$portable_parent"
  readlink() {
    [ "${1:-}" != -m ] || return 1
    command readlink "$@"
  }
  realpath() {
    if [ "${1:-}" = -m ]; then
      printf '%s\n' partial-output "$portable_root"
      return 1
    fi
    command realpath "$@"
  }
  assert_eq "$portable_root" "$(nb_normalize_path "$portable_root")" \
    'failed normalizer output is discarded'
  assert_eq "$portable_root" \
    "$(nb_assert_safe_nobrand_root "$portable_root" PORTABLE_ROOT)" \
    'portable destructive-root normalization emits one canonical path'
)

reset_fixture
assert_state CLEAN 'empty host'
mkdir -p "$NOBRAND_STATE_DIR" "$NOBRAND_CONFIG_DIR" "$NOBRAND_LIB_DIR" \
  "$NOBRAND_LEGACY_MIERU_STATE_DIR"
assert_state CLEAN 'empty directories are not legacy evidence'

reset_fixture
mkdir -p "$fixture/foreign/usr/bin"
printf '#!/bin/sh\n' >"$fixture/foreign/usr/bin/mita"
assert_state CLEAN 'foreign mita alone is not NoBrand evidence'

reset_fixture
write_schema
write_manager 3.2.0
assert_state CURRENT_COMPLETE 'schema v3 plus compatible 3.2 manager'

for unsafe_root in "$NOBRAND_CONFIG_DIR" "$NOBRAND_LIB_DIR"; do
  reset_fixture
  write_schema
  write_manager 3.2.0
  mkdir -p "$fixture/foreign/root-target"
  ln -s "$fixture/foreign/root-target" "$unsafe_root"
  assert_state AMBIGUOUS_OR_FOREIGN \
    "current evidence cannot bypass live root symlink: $unsafe_root"

  reset_fixture
  write_schema
  write_manager 3.2.0
  mkdir -p "$(dirname "$unsafe_root")"
  ln -s "$fixture/foreign/missing-root-target" "$unsafe_root"
  assert_state AMBIGUOUS_OR_FOREIGN \
    "current evidence cannot bypass dangling root symlink: $unsafe_root"
done

reset_fixture
write_schema
write_manager 3.2.0
ln -s "$NOBRAND_INSTALL_SCRIPT_PATH" "$NOBRAND_COMMAND_PATH"
ln -s "$NOBRAND_COMMAND_PATH" "$NOBRAND_SHORT_COMMAND_PATH"
assert_state CURRENT_COMPLETE 'recognized current command symlink chain'

reset_fixture
mkdir -p "$(dirname "$NOBRAND_COMMAND_PATH")"
ln -s "$NOBRAND_INSTALL_SCRIPT_PATH" "$NOBRAND_COMMAND_PATH"
assert_state AMBIGUOUS_OR_FOREIGN 'dangling nobrand command cannot classify clean'

reset_fixture
mkdir -p "$(dirname "$NOBRAND_SHORT_COMMAND_PATH")"
ln -s "$NOBRAND_COMMAND_PATH" "$NOBRAND_SHORT_COMMAND_PATH"
assert_state AMBIGUOUS_OR_FOREIGN 'dangling nb command cannot classify clean'

reset_fixture
write_schema
write_manager 3.2.0
cp "$NOBRAND_INSTALL_SCRIPT_PATH" "$NOBRAND_COMMAND_PATH"
rm -f "$NOBRAND_INSTALL_SCRIPT_PATH"
assert_state CURRENT_PARTIAL_INSTALL 'owned command script is positive current evidence'

reset_fixture
write_schema
assert_state CURRENT_PARTIAL_INSTALL 'schema written before manager is an interrupted install'

reset_fixture
nb_lifecycle_begin install prepare
assert_state CURRENT_PARTIAL_INSTALL 'install transaction'

reset_fixture
nb_lifecycle_begin repair prepare
assert_state CURRENT_PARTIAL_REPAIR 'repair transaction'

reset_fixture
nb_lifecycle_begin uninstall prepare
assert_state CURRENT_PARTIAL_UNINSTALL 'uninstall transaction'

reset_fixture
nb_lifecycle_begin install prepare
sed -i 's/^LAST_COMPLETED_PHASE=.*/LAST_COMPLETED_PHASE=partial-uninstall-manager-ready/' \
  "$NOBRAND_LIFECYCLE_TX_FILE"
assert_state AMBIGUOUS_OR_FOREIGN 'operation/phase mismatch fails closed'

reset_fixture
nb_lifecycle_begin repair prepare
write_manager 9.9.9
assert_state AMBIGUOUS_OR_FOREIGN 'active transaction cannot mask newer manager conflict'

reset_fixture
nb_lifecycle_begin uninstall prepare
write_manager 3.1.9
assert_state AMBIGUOUS_OR_FOREIGN 'active transaction cannot mask older manager conflict'

reset_fixture
write_schema
write_manager 3.1.9
nb_lifecycle_begin repair prepare
assert_state CURRENT_PARTIAL_REPAIR \
  'supported schema-v3 manager remains eligible during its explicit repair transaction'

reset_fixture
nb_lifecycle_begin uninstall prepare
conflicting_tx_hash="$(sha256sum "$NOBRAND_LIFECYCLE_TX_FILE")"
if nb_lifecycle_begin repair prepare >/dev/null 2>&1; then
  fail 'different lifecycle operation replaced an active uninstall transaction'
fi
assert_eq "$conflicting_tx_hash" "$(sha256sum "$NOBRAND_LIFECYCLE_TX_FILE")" \
  'rejected lifecycle direction change preserves exact transaction bytes'
nb_lifecycle_begin repair partial-uninstall-prepare 0 0 0 0 0 1
assert_eq repair "$(nb_lifecycle_field OPERATION)" \
  'explicit partial-uninstall repair transition is permitted'

reset_fixture
write_schema
write_manager 3.1.9
assert_state LEGACY_SUPPORTED 'compatible 3.1 schema-v3 installation'

reset_fixture
historical_v22="$fixture/v2.2.0-install-mita.sh"
git -c safe.directory="$TEST_ROOT" -C "$TEST_ROOT" \
  show v2.2.0:install-mita.sh >"$historical_v22"
grep -qF 'MITA_MANAGER_STATE_DIR="${MITA_MANAGER_STATE_DIR:-/var/lib/mita-oneclick}"' \
  "$historical_v22" || fail 'v2.2.0 did not prove the legacy state root'
grep -qF 'INSTALL_SCRIPT_PATH="/usr/local/bin/install-mita"' "$historical_v22" \
  || fail 'v2.2.0 did not prove the legacy manager path'
grep -qF '_state_kv INSTALL_SCRIPT "$INSTALL_SCRIPT_PATH"' "$historical_v22" \
  || fail 'v2.2.0 did not write the legacy INSTALL_SCRIPT field'
grep -qF "printf 'INSTALL_METHOD=oneclick\\n'" "$historical_v22" \
  || fail 'v2.2.0 did not write the legacy INSTALL_METHOD field'
write_legacy_v22_state
assert_state LEGACY_UNSUPPORTED 'positive pre-v3 signature'

reset_fixture
write_legacy_v22_state
write_schema
assert_state AMBIGUOUS_OR_FOREIGN 'mixed v2 signature and current schema fail closed'

reset_fixture
write_legacy_v22_state
write_manager 3.2.0
assert_state AMBIGUOUS_OR_FOREIGN 'mixed v2 signature and current manager fail closed'

reset_fixture
write_legacy_v22_state
nb_lifecycle_begin repair prepare
assert_state AMBIGUOUS_OR_FOREIGN 'mixed v2 signature and current transaction fail closed'

reset_fixture
mkdir -p "$NOBRAND_LEGACY_MIERU_STATE_DIR"
printf '%s\n' \
  'INSTALL_METHOD=oneclick' "PORT=''" 'PORT_RANGE=20000-20100' 'PROTOCOL=UDP' \
  'INSTALL_SCRIPT=/usr/local/bin/install-mita' \
  >"$NOBRAND_LEGACY_MIERU_STATE_DIR/install-state.env"
assert_state LEGACY_UNSUPPORTED 'positive pre-v3 port-range signature'

reset_fixture
mkdir -p "$NOBRAND_LEGACY_MIERU_STATE_DIR"
printf '%s\n' 'INSTALL_METHOD=oneclick' 'PORT=2088' \
  >"$NOBRAND_LEGACY_MIERU_STATE_DIR/install-state.env"
assert_state AMBIGUOUS_OR_FOREIGN 'incomplete legacy-looking data is not positive legacy proof'

for malformed in \
  'PORT=not-a-port' \
  'PORT_RANGE=70000-70001' \
  'PROTOCOL=QUIC' \
  'INSTALL_SCRIPT=/tmp/foreign-installer'; do
  reset_fixture
  mkdir -p "$NOBRAND_LEGACY_MIERU_STATE_DIR"
  printf '%s\n' \
    'INSTALL_METHOD=oneclick' 'PORT=2088' "PORT_RANGE=''" 'PROTOCOL=TCP' \
    'INSTALL_SCRIPT=/usr/local/bin/install-mita' \
    >"$NOBRAND_LEGACY_MIERU_STATE_DIR/install-state.env"
  key="${malformed%%=*}"
  sed -i "s|^${key}=.*|${malformed}|" \
    "$NOBRAND_LEGACY_MIERU_STATE_DIR/install-state.env"
  assert_state AMBIGUOUS_OR_FOREIGN "malformed legacy signature: ${key}"
done

reset_fixture
write_schema
write_manager 9.9.9
assert_state AMBIGUOUS_OR_FOREIGN 'unknown manager generation fails closed'

# Execute the top-level install guard for ambiguous and historical evidence.
# Both paths must fail before acquiring a lifecycle lock or mutating any bytes.
reset_fixture
mkdir -p "$(dirname "$NOBRAND_INSTALL_SCRIPT_PATH")"
printf '%s\n' '#!/bin/sh' 'printf "%s\n" foreign-manager' \
  >"$NOBRAND_INSTALL_SCRIPT_PATH"
chmod 0755 "$NOBRAND_INSTALL_SCRIPT_PATH"
ambiguous_manager_hash="$(sha256sum "$NOBRAND_INSTALL_SCRIPT_PATH")"
ambiguous_manager_mode="$(stat -c '%a' "$NOBRAND_INSTALL_SCRIPT_PATH")"
assert_state AMBIGUOUS_OR_FOREIGN 'executable foreign manager fixture classification'
set +e
ambiguous_install_output="$(
  (
    require_root() { return 0; }
    require_linux() { return 0; }
    require_cmd() { return 0; }
    nb_lifecycle_lock_acquire() {
      : >"$fixture/ambiguous-unexpected-lock"
      return 99
    }
    do_install_impl() {
      : >"$fixture/ambiguous-unexpected-install-body"
      return 99
    }
    LANG_ZH=1 do_install
  ) 2>&1
)"
ambiguous_install_rc=$?
set -e
[ "$ambiguous_install_rc" -ne 0 ] || fail 'ambiguous top-level install unexpectedly succeeded'
assert_eq "$ambiguous_manager_hash" "$(sha256sum "$NOBRAND_INSTALL_SCRIPT_PATH")" \
  'ambiguous top-level install preserves fixture bytes'
assert_eq "$ambiguous_manager_mode" "$(stat -c '%a' "$NOBRAND_INSTALL_SCRIPT_PATH")" \
  'ambiguous top-level install preserves fixture mode'
assert_contains "$ambiguous_install_output" \
  '检测到无法确认归属的已有安装数据。为避免覆盖现有配置，本次操作已停止。' \
  'ambiguous top-level install reports ambiguous ownership'
assert_not_contains "$ambiguous_install_output" '旧版' \
  'ambiguous top-level install does not claim legacy evidence'
assert_not_contains "$ambiguous_install_output" '无法安全自动迁移' \
  'ambiguous top-level install does not claim migration evidence'
assert_not_contains "$ambiguous_install_output" '检测版本:' \
  'ambiguous top-level install does not invent a legacy version'
[ ! -e "$NOBRAND_LIFECYCLE_TX_FILE" ] \
  || fail 'ambiguous top-level install created a lifecycle transaction'
[ ! -e "$fixture/ambiguous-unexpected-lock" ] \
  || fail 'ambiguous top-level install acquired the lifecycle lock'
[ ! -e "$fixture/ambiguous-unexpected-install-body" ] \
  || fail 'ambiguous top-level install reached the install body'
printf 'AMBIGUOUS_STATE_FAIL_CLOSED=PASS\n'

reset_fixture
write_legacy_v22_state
legacy_unsupported_state="$NOBRAND_LEGACY_MIERU_STATE_DIR/install-state.env"
legacy_unsupported_hash="$(sha256sum "$legacy_unsupported_state")"
legacy_unsupported_mode="$(stat -c '%a' "$legacy_unsupported_state")"
assert_state LEGACY_UNSUPPORTED 'executable historical unsupported fixture classification'
set +e
legacy_unsupported_output="$(
  (
    require_root() { return 0; }
    require_linux() { return 0; }
    require_cmd() { return 0; }
    nb_lifecycle_lock_acquire() {
      : >"$fixture/legacy-unexpected-lock"
      return 99
    }
    do_install_impl() {
      : >"$fixture/legacy-unexpected-install-body"
      return 99
    }
    LANG_ZH=1 do_install
  ) 2>&1
)"
legacy_unsupported_rc=$?
set -e
[ "$legacy_unsupported_rc" -ne 0 ] \
  || fail 'historical unsupported top-level install unexpectedly succeeded'
assert_eq "$legacy_unsupported_hash" "$(sha256sum "$legacy_unsupported_state")" \
  'historical unsupported top-level install preserves state bytes'
assert_eq "$legacy_unsupported_mode" "$(stat -c '%a' "$legacy_unsupported_state")" \
  'historical unsupported top-level install preserves state mode'
assert_contains "$legacy_unsupported_output" \
  '检测到无法安全自动迁移的旧版 NoBrand 数据。' \
  'historical unsupported top-level install reports legacy evidence'
assert_contains "$legacy_unsupported_output" \
  '检测版本: pre-v3 (INSTALL_METHOD=oneclick)' \
  'historical unsupported top-level install reports detected version'
assert_contains "$legacy_unsupported_output" "当前安装器: ${SCRIPT_VERSION}" \
  'historical unsupported top-level install reports current installer'
assert_not_contains "$legacy_unsupported_output" '无法确认归属' \
  'historical unsupported top-level install is not mislabeled ambiguous'
[ ! -e "$NOBRAND_LIFECYCLE_TX_FILE" ] \
  || fail 'historical unsupported top-level install created a lifecycle transaction'
[ ! -e "$fixture/legacy-unexpected-lock" ] \
  || fail 'historical unsupported top-level install acquired the lifecycle lock'
[ ! -e "$fixture/legacy-unexpected-install-body" ] \
  || fail 'historical unsupported top-level install reached the install body'
printf 'LEGACY_UNSUPPORTED_FAIL_CLOSED=PASS\n'

# A foreign executable named mita on PATH is runtime/package evidence, not
# legacy NoBrand ownership. Exercise that production detection branch and stop
# deterministically before any package, service, or network work.
reset_fixture
foreign_mita_dir="$fixture/foreign/bin"
foreign_mita="$foreign_mita_dir/mita"
mkdir -p "$foreign_mita_dir"
cat >"$foreign_mita" <<EOF
#!/bin/sh
: >"$fixture/foreign-mita-was-executed"
printf '%s\n' foreign-mita
EOF
chmod 0755 "$foreign_mita"
foreign_mita_hash="$(sha256sum "$foreign_mita")"
foreign_mita_mode="$(stat -c '%a' "$foreign_mita")"
assert_state CLEAN 'foreign mita executable alone remains clean'
set +e
foreign_mita_output="$(
  (
    # shellcheck disable=SC1091
    source "$TEST_ROOT/src/20-platform-mieru.sh"
    require_root() { return 0; }
    require_linux() { return 0; }
    require_cmd() { return 0; }
    nb_lifecycle_lock_acquire() { fake_lifecycle_lock_acquire; }
    nb_lifecycle_lock_release() { fake_lifecycle_lock_release; }
    dpkg() { return 1; }
    rpm() { return 1; }
    installed_version() { return 1; }
    detect_pkg_manager() { printf deb; }
    detect_arch() { printf amd64; }
    ensure_management_dependencies() { return 0; }
    mita_preservable_config_exists() { return 1; }
    confirm() { return 0; }
    mieru_prepare_noninteractive_ingress_endpoint() { return 79; }
    download_package() {
      : >"$fixture/foreign-mita-unexpected-runtime-work"
      return 99
    }
    install_package() {
      : >"$fixture/foreign-mita-unexpected-runtime-work"
      return 99
    }
    PATH="$foreign_mita_dir:$PATH"
    export PATH
    YES=1 LANG_ZH=1 do_install
  ) 2>&1
)"
foreign_mita_rc=$?
set -e
[ "$foreign_mita_rc" -ne 0 ] || fail 'foreign mita install path unexpectedly succeeded'
assert_eq "$foreign_mita_hash" "$(sha256sum "$foreign_mita")" \
  'foreign mita install path preserves binary bytes'
assert_eq "$foreign_mita_mode" "$(stat -c '%a' "$foreign_mita")" \
  'foreign mita install path preserves binary mode'
assert_contains "$foreign_mita_output" '检测到已安装 mita 未知版本' \
  'foreign mita install path detects runtime without claiming ownership'
assert_contains "$foreign_mita_output" \
  '检测到上次安装未完成，且没有可恢复的 OneClick 状态' \
  'foreign mita install path selects incomplete-runtime reconciliation'
assert_not_contains "$foreign_mita_output" '旧版' \
  'foreign mita install path does not claim legacy evidence'
assert_not_contains "$foreign_mita_output" '无法安全自动迁移' \
  'foreign mita install path does not claim migration evidence'
assert_not_contains "$foreign_mita_output" '检测版本:' \
  'foreign mita install path does not invent a legacy version'
[ ! -e "$fixture/foreign-mita-was-executed" ] \
  || fail 'foreign mita detection executed the foreign binary'
[ ! -e "$fixture/foreign-mita-unexpected-runtime-work" ] \
  || fail 'foreign mita fixture reached runtime package work'
assert_state CURRENT_PARTIAL_INSTALL \
  'foreign mita install path retains a resumable current transaction'
printf 'FOREIGN_MITA_CLASSIFICATION=PASS\n'

reset_fixture
nb_lifecycle_begin install prepare
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*)
    printf '[SKIP] POSIX lifecycle mode check on Windows compatibility filesystem\n'
    ;;
  *)
    assert_file_mode 700 "$NOBRAND_LIFECYCLE_DIR"
    assert_file_mode 600 "$NOBRAND_LIFECYCLE_TX_FILE"
    ;;
esac
assert_eq 13 "$(wc -l <"$NOBRAND_LIFECYCLE_TX_FILE" | tr -d '[:space:]')" \
  'transaction field count'
assert_not_contains "$(cat "$NOBRAND_LIFECYCLE_TX_FILE")" 'PASSWORD=' 'transaction secrets'
assert_not_contains "$(cat "$NOBRAND_LIFECYCLE_TX_FILE")" 'PRIVATE_KEY=' 'transaction private key'
nb_lifecycle_checkpoint install state-layout
assert_eq state-layout "$(nb_lifecycle_field LAST_COMPLETED_PHASE)" 'phase update'
nb_lifecycle_complete install
assert_eq complete "$(nb_lifecycle_field STATUS)" 'install completion status'
assert_eq complete "$(nb_lifecycle_field LAST_COMPLETED_PHASE)" 'completion phase'
assert_state AMBIGUOUS_OR_FOREIGN \
  'complete lifecycle metadata without committed schema or manager fails closed'

reset_fixture
write_schema
nb_lifecycle_begin install prepare
nb_lifecycle_complete install
assert_state CURRENT_PARTIAL_INSTALL \
  'complete lifecycle metadata with surviving schema remains safely repairable'

reset_fixture
nb_lifecycle_begin repair prepare
nb_lifecycle_complete repair
assert_eq repair "$(nb_lifecycle_field OPERATION)" 'repair transaction operation'
assert_eq complete "$(nb_lifecycle_field STATUS)" 'repair completion status'

reset_fixture
nb_lifecycle_begin uninstall prepare
nb_lifecycle_clear
[ ! -e "$NOBRAND_LIFECYCLE_TX_FILE" ] || fail 'uninstall transaction must clear'
[ ! -e "$NOBRAND_LIFECYCLE_DIR" ] || fail 'empty lifecycle directory must clear'

reset_fixture
nb_lifecycle_begin install prepare
export NOBRAND_TEST_INTERRUPT_INSTALL_AT=state-layout
set +e
nb_lifecycle_checkpoint install state-layout
checkpoint_rc=$?
set -e
assert_eq 75 "$checkpoint_rc" 'guarded install checkpoint'
(
  nb_lifecycle_mark_phase() { return 0; }
  MITA_SOURCE_ONLY=0 NOBRAND_TEST_MODE=1 \
    nb_lifecycle_checkpoint install state-layout
) || fail 'checkpoint must be inert without both test guards'
(
  nb_lifecycle_mark_phase() { return 0; }
  MITA_SOURCE_ONLY=1 NOBRAND_TEST_MODE=0 \
    nb_lifecycle_checkpoint install state-layout
) || fail 'checkpoint must be inert when test mode is disabled'

reset_fixture
(
  require_root() { return 0; }
  require_linux() { return 0; }
  require_cmd() { return 0; }
  nb_lifecycle_lock_acquire() { fake_lifecycle_lock_acquire; }
  nb_lifecycle_lock_release() { fake_lifecycle_lock_release; }
  do_install_impl() { return 41; }
  set +e
  do_install
  rc=$?
  set -e
  printf '%s' "$rc" >"$fixture/install-failure.rc"
)
assert_eq 41 "$(cat "$fixture/install-failure.rc")" 'install failure propagation'
assert_eq in-progress "$(nb_lifecycle_field STATUS)" 'failed install preserves transaction'
assert_eq install "$(nb_lifecycle_field OPERATION)" 'failed install operation'
assert_state CURRENT_PARTIAL_INSTALL 'failed install remains resumable'

# Exercise every standard install/repair checkpoint through the production
# do_install_impl path. External package, service, and network work is stubbed,
# but state layout, transaction persistence, classification, and checkpoint
# placement remain real.
standard_lifecycle_interrupt_phases=(
  state-layout
  runtime-ready
  state-committed
  ready-to-validate
)
partial_uninstall_repair_interrupt_phases=(
  partial-uninstall-state-layout
  partial-uninstall-manager-ready
  partial-uninstall-runtimes-reconciled
  partial-uninstall-services-reconciled
  partial-uninstall-state-validated
  partial-uninstall-ready-to-validate
)
INSTALL_INTERRUPT_EXERCISED_COUNT=0
REPAIR_INTERRUPT_EXERCISED_COUNT=0
PARTIAL_UNINSTALL_REPAIR_INTERRUPT_EXERCISED_COUNT=0

stub_standard_lifecycle_install_dependencies() {
  require_root() { return 0; }
  require_linux() { return 0; }
  require_cmd() { return 0; }
  nb_lifecycle_lock_acquire() { fake_lifecycle_lock_acquire; }
  nb_lifecycle_lock_release() { fake_lifecycle_lock_release; }
  detect_pkg_manager() { printf deb; }
  detect_arch() { printf amd64; }
  ensure_management_dependencies() { return 0; }
  mita_installed() { return 1; }
  mieru_prepare_noninteractive_ingress_endpoint() { return 0; }
  ensure_config_noninteractive() { return 0; }
  ensure_install_port_available() { return 0; }
  mieru_resolve_runtime() {
    export MIERU_RUNTIME_RESOLVED_VERSION=3.35.0
    export MIERU_RUNTIME_RESOLVED_URL=https://fixture.invalid/mita.tar.gz
    export MIERU_RUNTIME_RESOLVED_SHA256=''
    export MIERU_RUNTIME_RESOLVED_CHECKSUM_URL=''
  }
  download_package() { : >"$2"; }
  mieru_runtime_snapshot() { printf '%s\n' "$fixture/runtime-snapshot"; }
  install_package() { return 0; }
  mieru_assert_runtime_version() { return 0; }
  mieru_runtime_commit() { return 0; }
  add_op_user() { return 0; }
  warn_traffic_unsupported() { return 0; }
  warn_low_entropy_unsupported() { return 0; }
  install_fresh_isolated() {
    write_schema
    write_manager "$SCRIPT_VERSION"
  }
  offer_bbr_fq() { return 0; }
  print_summary() { return 0; }
  mita_v3_install_state_valid() { return 0; }
  users_state_exists() { return 0; }
  users_count() { printf 1; }
  verify_mita_running() { return 0; }
}

# A recognized 3.1 manager with schema-v3 state is a supported repair input.
# Execute the transition and prove state bytes survive while the manager moves
# to the current generation.
reset_fixture
write_schema
write_manager 3.1.9
printf '%s\n' 'supported-repair-state-must-survive' \
  >"$NOBRAND_STATE_DIR/legacy-supported-preserve"
legacy_supported_state_hash="$(
  sha256sum "$NOBRAND_REGISTRY_FILE" "$NOBRAND_STATE_DIR/legacy-supported-preserve"
)"
assert_state LEGACY_SUPPORTED 'executable supported legacy repair starts supported'
(
  stub_standard_lifecycle_install_dependencies
  YES=1
  do_install >/dev/null
)
assert_eq "$legacy_supported_state_hash" "$(
  sha256sum "$NOBRAND_REGISTRY_FILE" "$NOBRAND_STATE_DIR/legacy-supported-preserve"
)" 'supported legacy repair preserves state bytes'
assert_eq "$SCRIPT_VERSION" "$(nb_installed_manager_version)" \
  'supported legacy repair upgrades manager generation'
assert_eq repair "$(nb_lifecycle_field OPERATION)" \
  'supported legacy transition uses repair operation'
assert_eq complete "$(nb_lifecycle_field STATUS)" \
  'supported legacy transition completes repair transaction'
assert_state CURRENT_COMPLETE 'supported legacy repair converges current complete'
printf 'LEGACY_SUPPORTED_REPAIR_TRANSITION=PASS\n'

run_standard_install_interrupt_phase() {
  local phase="$1" rc=0
  reset_fixture
  (
    stub_standard_lifecycle_install_dependencies
    YES=1
    export NOBRAND_TEST_INTERRUPT_INSTALL_AT="$phase"
    set +e
    do_install >/dev/null 2>&1
    rc=$?
    set -e
    [ "$rc" -ne 0 ] || fail "install checkpoint did not interrupt: $phase"
  )
  assert_eq install "$(nb_lifecycle_field OPERATION)" \
    "interrupted install operation: $phase"
  assert_eq in-progress "$(nb_lifecycle_field STATUS)" \
    "interrupted install status: $phase"
  assert_eq "$phase" "$(nb_lifecycle_field LAST_COMPLETED_PHASE)" \
    "interrupted install phase: $phase"
  assert_state CURRENT_PARTIAL_INSTALL "interrupted install classification: $phase"
  (
    stub_standard_lifecycle_install_dependencies
    YES=1
    unset NOBRAND_TEST_INTERRUPT_INSTALL_AT
    do_install >/dev/null
  )
  assert_eq install "$(nb_lifecycle_field OPERATION)" \
    "install rerun operation: $phase"
  assert_eq complete "$(nb_lifecycle_field STATUS)" \
    "install rerun completion: $phase"
  assert_state CURRENT_COMPLETE "install rerun convergence: $phase"
  INSTALL_INTERRUPT_EXERCISED_COUNT=$((INSTALL_INTERRUPT_EXERCISED_COUNT + 1))
}

run_standard_repair_interrupt_phase() {
  local phase="$1" rc=0 repair_state_hash=''
  reset_fixture
  write_schema
  write_manager "$SCRIPT_VERSION"
  printf '%s\n' 'preserved-repair-state' >"$NOBRAND_STATE_DIR/repair-preserve"
  repair_state_hash="$(sha256sum "$NOBRAND_STATE_DIR/repair-preserve")"
  assert_state CURRENT_COMPLETE "repair starts complete: $phase"
  (
    stub_standard_lifecycle_install_dependencies
    YES=1
    export NOBRAND_TEST_INTERRUPT_REPAIR_AT="$phase"
    set +e
    do_install >/dev/null 2>&1
    rc=$?
    set -e
    [ "$rc" -ne 0 ] || fail "repair checkpoint did not interrupt: $phase"
  )
  assert_eq repair "$(nb_lifecycle_field OPERATION)" \
    "interrupted repair operation: $phase"
  assert_eq in-progress "$(nb_lifecycle_field STATUS)" \
    "interrupted repair status: $phase"
  assert_eq "$phase" "$(nb_lifecycle_field LAST_COMPLETED_PHASE)" \
    "interrupted repair phase: $phase"
  assert_state CURRENT_PARTIAL_REPAIR "interrupted repair classification: $phase"
  (
    stub_standard_lifecycle_install_dependencies
    YES=1
    unset NOBRAND_TEST_INTERRUPT_REPAIR_AT
    do_install >/dev/null
  )
  assert_eq repair "$(nb_lifecycle_field OPERATION)" \
    "repair rerun operation: $phase"
  assert_eq complete "$(nb_lifecycle_field STATUS)" \
    "repair rerun completion: $phase"
  assert_eq "$repair_state_hash" "$(sha256sum "$NOBRAND_STATE_DIR/repair-preserve")" \
    "repair rerun preserves state: $phase"
  assert_state CURRENT_COMPLETE "repair rerun convergence: $phase"
  REPAIR_INTERRUPT_EXERCISED_COUNT=$((REPAIR_INTERRUPT_EXERCISED_COUNT + 1))
}

for lifecycle_phase in "${standard_lifecycle_interrupt_phases[@]}"; do
  run_standard_install_interrupt_phase "$lifecycle_phase"
done
for lifecycle_phase in "${standard_lifecycle_interrupt_phases[@]}"; do
  run_standard_repair_interrupt_phase "$lifecycle_phase"
done

stub_partial_uninstall_repair_dependencies() {
  require_root() { return 0; }
  require_linux() { return 0; }
  require_cmd() { return 0; }
  nb_lifecycle_lock_acquire() { fake_lifecycle_lock_acquire; }
  nb_lifecycle_lock_release() { fake_lifecycle_lock_release; }
  ensure_manager_state_layout() { return 0; }
  install_self_script() { write_manager "$SCRIPT_VERSION"; }
  do_install_impl() {
    : >"$NOBRAND_STATE_DIR/unexpected-fresh-install"
    return 99
  }
  nobrand_restore_protocol_runtimes() { return 0; }
  nobrand_start_enabled_services() { return 0; }
  nobrand_doctor() { return 0; }
}

run_partial_uninstall_repair_interrupt_phase() {
  local phase="$1" rc=0 preserved_state_hash=''
  reset_fixture
  write_schema
  write_manager "$SCRIPT_VERSION"
  mkdir -p "$(dirname "$NOBRAND_FORWARD_STATE_FILE")"
  printf '%s\n' '{"format":"partial-uninstall-repair-fixture"}' \
    >"$NOBRAND_FORWARD_STATE_FILE"
  preserved_state_hash="$(sha256sum "$NOBRAND_FORWARD_STATE_FILE")"
  nb_lifecycle_begin uninstall prepare
  assert_state CURRENT_PARTIAL_UNINSTALL \
    "partial-uninstall repair interrupt starts resumable: $phase"
  (
    stub_partial_uninstall_repair_dependencies
    YES=1
    export NOBRAND_TEST_INTERRUPT_REPAIR_AT="$phase"
    set +e
    do_install >/dev/null 2>&1
    rc=$?
    set -e
    [ "$rc" -ne 0 ] || fail "partial-uninstall repair checkpoint did not interrupt: $phase"
  )
  assert_eq repair "$(nb_lifecycle_field OPERATION)" \
    "interrupted partial-uninstall repair operation: $phase"
  assert_eq in-progress "$(nb_lifecycle_field STATUS)" \
    "interrupted partial-uninstall repair status: $phase"
  assert_eq "$phase" "$(nb_lifecycle_field LAST_COMPLETED_PHASE)" \
    "interrupted partial-uninstall repair phase: $phase"
  assert_state CURRENT_PARTIAL_REPAIR \
    "interrupted partial-uninstall repair classification: $phase"
  assert_eq "$preserved_state_hash" "$(sha256sum "$NOBRAND_FORWARD_STATE_FILE")" \
    "interrupted partial-uninstall repair preserves state: $phase"
  [ ! -e "$NOBRAND_STATE_DIR/unexpected-fresh-install" ] \
    || fail "partial-uninstall repair invoked fresh install: $phase"
  (
    stub_partial_uninstall_repair_dependencies
    YES=1
    unset NOBRAND_TEST_INTERRUPT_REPAIR_AT
    do_install >/dev/null
  )
  assert_eq repair "$(nb_lifecycle_field OPERATION)" \
    "partial-uninstall repair rerun operation: $phase"
  assert_eq complete "$(nb_lifecycle_field STATUS)" \
    "partial-uninstall repair rerun completion: $phase"
  assert_eq "$preserved_state_hash" "$(sha256sum "$NOBRAND_FORWARD_STATE_FILE")" \
    "partial-uninstall repair rerun preserves state: $phase"
  assert_state CURRENT_COMPLETE \
    "partial-uninstall repair rerun convergence: $phase"
  REPAIR_INTERRUPT_EXERCISED_COUNT=$((REPAIR_INTERRUPT_EXERCISED_COUNT + 1))
  PARTIAL_UNINSTALL_REPAIR_INTERRUPT_EXERCISED_COUNT=$((
    PARTIAL_UNINSTALL_REPAIR_INTERRUPT_EXERCISED_COUNT + 1
  ))
}

for lifecycle_phase in "${partial_uninstall_repair_interrupt_phases[@]}"; do
  run_partial_uninstall_repair_interrupt_phase "$lifecycle_phase"
done

# Exercise two interruptions in one install transaction before the final rerun.
reset_fixture
(
  stub_standard_lifecycle_install_dependencies
  YES=1
  export NOBRAND_TEST_INTERRUPT_INSTALL_AT=runtime-ready
  set +e
  do_install >/dev/null 2>&1
  first_rc=$?
  set -e
  [ "$first_rc" -ne 0 ] || fail 'first successive install interruption did not stop'
  assert_state CURRENT_PARTIAL_INSTALL 'first successive install interruption classification'
  first_txid="$(nb_lifecycle_field TRANSACTION_ID)"

  export NOBRAND_TEST_INTERRUPT_INSTALL_AT=state-committed
  set +e
  do_install >/dev/null 2>&1
  second_rc=$?
  set -e
  [ "$second_rc" -ne 0 ] || fail 'second successive install interruption did not stop'
  assert_state CURRENT_PARTIAL_INSTALL 'second successive install interruption classification'
  assert_eq "$first_txid" "$(nb_lifecycle_field TRANSACTION_ID)" \
    'successive install interruptions retain transaction identity'

  unset NOBRAND_TEST_INTERRUPT_INSTALL_AT
  do_install >/dev/null
)
assert_eq complete "$(nb_lifecycle_field STATUS)" \
  'multiple interrupted install final completion'
assert_state CURRENT_COMPLETE 'multiple interrupted install converges'

# A completed installer is safe on its second and third invocations.
reset_fixture
completed_rerun_log="$fixture/completed-install-reruns.log"
(
  stub_standard_lifecycle_install_dependencies
  install_fresh_isolated() {
    printf '%s\n' "$NOBRAND_LIFECYCLE_OPERATION" >>"$completed_rerun_log"
    write_schema
    write_manager "$SCRIPT_VERSION"
  }
  YES=1
  do_install >/dev/null
  assert_eq install "$(nb_lifecycle_field OPERATION)" 'completed rerun first operation'
  printf '%s\n' 'preserve-across-three-installs' >"$NOBRAND_STATE_DIR/completed-rerun-preserve"
  completed_state_hash="$(sha256sum "$NOBRAND_STATE_DIR/completed-rerun-preserve")"
  completed_manager_hash="$(sha256sum "$NOBRAND_INSTALL_SCRIPT_PATH")"

  do_install >/dev/null
  assert_eq repair "$(nb_lifecycle_field OPERATION)" 'completed rerun second operation'
  assert_eq "$completed_state_hash" \
    "$(sha256sum "$NOBRAND_STATE_DIR/completed-rerun-preserve")" \
    'second installer invocation preserves state'
  assert_eq "$completed_manager_hash" "$(sha256sum "$NOBRAND_INSTALL_SCRIPT_PATH")" \
    'second installer invocation preserves manager identity'

  do_install >/dev/null
  assert_eq repair "$(nb_lifecycle_field OPERATION)" 'completed rerun third operation'
  assert_eq "$completed_state_hash" \
    "$(sha256sum "$NOBRAND_STATE_DIR/completed-rerun-preserve")" \
    'third installer invocation preserves state'
  assert_eq "$completed_manager_hash" "$(sha256sum "$NOBRAND_INSTALL_SCRIPT_PATH")" \
    'third installer invocation preserves manager identity'
)
assert_eq $'install\nrepair\nrepair' "$(cat "$completed_rerun_log")" \
  'completed installer executes exactly three reconciliation bodies'
assert_state CURRENT_COMPLETE 'third completed installer rerun remains complete'

# Preserve a complete, structurally valid node/Profile/backup fixture across
# repeated top-level repair reconciliation. This intentionally uses the real
# existing-install branch, user-state readers, and install-state writer.
reset_fixture
write_schema
write_manager "$SCRIPT_VERSION"
mkdir -p "$(dirname "$MITA_STATE")" "$(dirname "$NOBRAND_INGRESS_STATE_FILE")" \
  "$NOBRAND_BACKUP_DIR" "$NOBRAND_CONFIG_DIR"
(
  run() { "$@"; }
  profile_reconcile_metadata() { return 0; }
  export PORT=26001
  export PORT_RANGE=''
  export PROTOCOL=TCP
  export PROFILE=balanced
  export ADVERTISE_HOST=node-preserve.example.test
  export ADVERTISE_PORT=24443
  export MTU=1400
  export MTU_POLICY=safe
  export USERNAME=preserved-user
  export PASSWORD=preserved-credential
  export TRAFFIC_PATTERN=conservative
  export TRAFFIC_SEED=42
  export LOW_ENTROPY_MODE=LOW_ENTROPY_MODE_OFF
  export MULTIPLEXING=MULTIPLEXING_OFF
  export HANDSHAKE_MODE=HANDSHAKE_NO_WAIT
  export MIERU_CHANNEL=stable
  export MIERU_VERSION=3.35.0
  save_install_state
)
cat >"$MITA_USERS_STATE" <<'JSON'
{
  "version": 2,
  "deployment_model": "isolated-v2",
  "protocol": "TCP",
  "users": [{
    "instance_id": "u1111111111111111",
    "name": "preserved-user",
    "password": "preserved-credential",
    "port": 26001,
    "advertise_host": "node-preserve.example.test",
    "advertise_port": 24443,
    "enabled": true,
    "quota_mb": 0,
    "quota_days": 0,
    "quota_mode": "rolling",
    "last_quota_reset": "",
    "expire_at": "",
    "package": "unlimited",
    "bandwidth_mbps": 0,
    "created_at": 1788048000,
    "updated_at": 1788048000,
    "ingress_profile_id": "i1111111111111111",
    "ingress_enforcement": "strict",
    "ingress_enforcement_method": "native-bind",
    "ingress_local_address": "192.0.2.110"
  }]
}
JSON
chmod 0600 "$MITA_USERS_STATE"
cat >"$NOBRAND_INGRESS_STATE_FILE" <<'JSON'
{
  "schema_version": 3,
  "ownership": "nobrand-v3",
  "feature": "ingress-profiles",
  "default_profile_id": "i1111111111111111",
  "profiles": [{
    "profile_id": "i1111111111111111",
    "name": "Preserve-Strict",
    "type": "public",
    "interface": "eth0",
    "local_address": "192.0.2.110",
    "port_policy": "derived-tail",
    "range_start": null,
    "range_end": null,
    "reserved_ports": [11000],
    "display_host_default": "",
    "display_port_policy": "follow-actual",
    "display_port": null,
    "enabled": true,
    "ingress_enforcement": "strict",
    "created_at": "2026-08-30T00:00:00Z",
    "updated_at": "2026-08-30T00:00:00Z"
  }, {
    "profile_id": "i2222222222222222",
    "name": "Preserve-Permissive",
    "type": "mapped",
    "interface": "eth1",
    "local_address": "198.51.100.40",
    "port_policy": "custom-range",
    "range_start": 30001,
    "range_end": 30020,
    "reserved_ports": [30005],
    "display_host_default": "profile-preserve.example.test",
    "display_port_policy": "custom",
    "display_port": 443,
    "enabled": true,
    "ingress_enforcement": "permissive",
    "created_at": "2026-08-30T00:00:00Z",
    "updated_at": "2026-08-30T00:00:00Z"
  }]
}
JSON
chmod 0600 "$NOBRAND_INGRESS_STATE_FILE"
printf '%s\n' 'backup-config-bytes-must-survive-installer-reruns' \
  >"$NOBRAND_CONFIG_DIR/preserve.conf"
preserve_backup_path="$NOBRAND_BACKUP_DIR/nobrand-backup-preserve.tar.gz"
(
  # shellcheck disable=SC1091
  source "$TEST_ROOT/src/17-core-endpoint.sh"
  # The SSH backup precondition is outside this preservation gate; the archive
  # writer, manifest generation, root copies, and tar creation remain real.
  ssh_tunnel_backup_state_ready() { return 0; }
  nobrand_backup_create "$preserve_backup_path" >/dev/null
)
assert_file_mode 600 "$preserve_backup_path"
preserve_backup_listing="$(tar -tzf "$preserve_backup_path")"
for backup_member in \
  manifest.txt state/ state/state.json state/mieru/install-state.env \
  state/mieru/users.json state/ingress.json config/ config/preserve.conf; do
  assert_contains "$preserve_backup_listing" "$backup_member" \
    "production backup contains ${backup_member}"
done
preserve_backup_manifest="$(tar -xOzf "$preserve_backup_path" manifest.txt)"
assert_contains "$preserve_backup_manifest" 'project=NoBrand-OneClick' \
  'production backup manifest project'
assert_contains "$preserve_backup_manifest" "version=${SCRIPT_VERSION}" \
  'production backup manifest version'
assert_contains "$preserve_backup_manifest" 'schema_version=3' \
  'production backup manifest schema'
assert_contains "$preserve_backup_manifest" 'ownership=nobrand-v3' \
  'production backup manifest ownership'
assert_contains "$preserve_backup_manifest" 'contents=state,config' \
  'production backup manifest contents'

preserve_install_hash="$(sha256sum "$MITA_STATE")"
cp "$MITA_STATE" "$fixture/preserve-install-state.expected"
preserve_node_hash="$(sha256sum "$MITA_USERS_STATE")"
preserve_credential_hash="$(printf '%s' preserved-credential | sha256sum | awk '{print $1}')"
preserve_profile_hash="$(sha256sum "$NOBRAND_INGRESS_STATE_FILE")"
preserve_backup_hash="$(sha256sum "$preserve_backup_path")"
original_mita_v3_validator="$(declare -f mita_v3_install_state_valid)"

(
  # shellcheck disable=SC1091
  source "$TEST_ROOT/src/25-network-mtu.sh"
  # shellcheck disable=SC1091
  source "$TEST_ROOT/src/16-core-port.sh"
  # shellcheck disable=SC1091
  source "$TEST_ROOT/src/16-core-ingress.sh"
  # shellcheck disable=SC1091
  source "$TEST_ROOT/src/30-users-instance.sh"
  # shellcheck disable=SC1091
  source "$TEST_ROOT/src/35-users-state.sh"
  # shellcheck disable=SC1091
  source "$TEST_ROOT/src/55-profile-config.sh"
  # shellcheck disable=SC1091
  source "$TEST_ROOT/src/60-daemon-firewall-network.sh"
  original_users_state_exists="$(declare -f users_state_exists)"
  original_users_count="$(declare -f users_count)"

  # Apply the external-work stubs after sourcing the real readers/validators so
  # later modules cannot replace a harmless test double with a host operation.
  stub_standard_lifecycle_install_dependencies
  eval "$original_mita_v3_validator"
  eval "$original_users_state_exists"
  eval "$original_users_count"

  run() { "$@"; }
  mita_installed() { return 0; }
  installed_version() { printf 3.35.0; }
  mita_preservable_config_exists() {
    mita_v3_install_state_valid \
      && users_isolated_mode \
      && [ "$(users_count)" -gt 0 ]
  }
  confirm() { return 0; }
  install_self_script() { write_manager "$SCRIPT_VERSION"; }
  admin_lock_acquire() { return 0; }
  admin_lock_release() { return 0; }
  isolated_stop_all() { return 0; }
  apply_users_config() { [ -f "$1" ]; }
  prune_orphan_instances() { return 0; }
  profile_reconcile_metadata() { nb_ingress_state_valid; }

  assert_composite_preservation_fixture() {
    mita_v3_install_state_valid || fail 'preserved Mieru install state is invalid'
    users_isolated_mode || fail 'preserved users state is not isolated-v2'
    assert_eq 1 "$(users_count)" 'preserved existing user count'
    nb_ingress_state_valid || fail 'preserved Ingress Profile state is invalid'
    if ! cmp -s "$fixture/preserve-install-state.expected" "$MITA_STATE"; then
      diff -u "$fixture/preserve-install-state.expected" "$MITA_STATE" >&2 || true
      fail 'rerun preserves Mieru install state bytes'
    fi
    assert_eq "$preserve_install_hash" "$(sha256sum "$MITA_STATE")" \
      'rerun preserves Mieru install state hash'
    assert_eq "$preserve_node_hash" "$(sha256sum "$MITA_USERS_STATE")" \
      'rerun preserves existing node/user bytes'
    assert_eq "$preserve_credential_hash" \
      "$(jq -r '.users[0].password' "$MITA_USERS_STATE" | tr -d '\n' | sha256sum | awk '{print $1}')" \
      'rerun preserves existing user credential hash'
    assert_eq 26001 "$(jq -r '.users[0].port' "$MITA_USERS_STATE")" \
      'rerun preserves existing node port'
    assert_eq i1111111111111111 \
      "$(jq -r '.users[0].ingress_profile_id' "$MITA_USERS_STATE")" \
      'rerun preserves node Profile ID'
    assert_eq strict \
      "$(jq -r '.users[0].ingress_enforcement' "$MITA_USERS_STATE")" \
      'rerun preserves node strict enforcement'
    assert_eq 'node-preserve.example.test:24443' \
      "$(jq -r '.users[0] | "\(.advertise_host):\(.advertise_port)"' "$MITA_USERS_STATE")" \
      'rerun preserves node Display Endpoint'
    assert_eq "$preserve_profile_hash" "$(sha256sum "$NOBRAND_INGRESS_STATE_FILE")" \
      'rerun preserves Ingress Profile bytes'
    assert_eq i1111111111111111 \
      "$(jq -r '.default_profile_id' "$NOBRAND_INGRESS_STATE_FILE")" \
      'rerun preserves default Profile'
    assert_eq $'public\teth0\t192.0.2.110\tderived-tail\tstrict' \
      "$(jq -r '.profiles[0] | [.type,.interface,.local_address,.port_policy,.ingress_enforcement] | @tsv' \
        "$NOBRAND_INGRESS_STATE_FILE")" \
      'rerun preserves strict Profile type/interface/address/port policy'
    assert_eq $'mapped\teth1\t198.51.100.40\tcustom-range\tpermissive' \
      "$(jq -r '.profiles[1] | [.type,.interface,.local_address,.port_policy,.ingress_enforcement] | @tsv' \
        "$NOBRAND_INGRESS_STATE_FILE")" \
      'rerun preserves permissive Profile type/interface/address/port policy'
    assert_eq 'profile-preserve.example.test:443' \
      "$(jq -r '.profiles[1] | "\(.display_host_default):\(.display_port)"' \
        "$NOBRAND_INGRESS_STATE_FILE")" \
      'rerun preserves Profile Display Endpoint'
    assert_eq "$preserve_backup_hash" \
      "$(sha256sum "$preserve_backup_path")" \
      'rerun preserves production backup archive bytes'
  }

  export USERNAME_CLI=0 PASSWORD_CLI=0 PORT_CLI=0 PORT_RANGE_CLI=0 PROTOCOL_CLI=0
  export MTU_CLI=0 ADVERTISE_CLI=0 PROFILE_CLI=0 MULTIPLEXING_CLI=0 HANDSHAKE_CLI=0
  export TRAFFIC_CLI=0 LOW_ENTROPY_CLI=0 YES=1
  assert_composite_preservation_fixture
  do_install >/dev/null
  assert_eq repair "$(nb_lifecycle_field OPERATION)" \
    'first preservation rerun uses repair reconciliation'
  assert_composite_preservation_fixture
  do_install >/dev/null
  assert_eq repair "$(nb_lifecycle_field OPERATION)" \
    'second preservation rerun uses repair reconciliation'
  assert_composite_preservation_fixture
)
assert_state CURRENT_COMPLETE 'composite preservation reruns remain complete'
printf 'RERUN_EXISTING_NODE_PRESERVATION=PASS\n'
printf 'RERUN_PROFILE_PRESERVATION=PASS\n'
printf 'RERUN_BACKUP_PRESERVATION=PASS\n'
printf 'INSTALL_RERUN_STATE_PRESERVATION=PASS\n'

# A no-argument manager invocation must expose the dedicated recovery route
# before common preparation. In particular, choice 0 must not create the
# managed state/layout that the user explicitly declined to change.
reset_fixture
nb_lifecycle_begin install prepare
(
  id() { [ "${1:-}" = -u ] && printf 0; }
  nb_lifecycle_lock_acquire() { NOBRAND_LIFECYCLE_LOCK_HELD=$((NOBRAND_LIFECYCLE_LOCK_HELD + 1)); }
  nb_lifecycle_lock_release() { NOBRAND_LIFECYCLE_LOCK_HELD=$((NOBRAND_LIFECYCLE_LOCK_HELD - 1)); }
  read_tty() { printf -v "$1" 0; }
  ACTION=""
  main
  assert_eq 0 "$NOBRAND_LIFECYCLE_LOCK_HELD" 'choice-0 outer lock balance'
)
[ ! -e "$NOBRAND_STATE_DIR" ] || fail 'recovery choice 0 created managed state'
[ ! -e "$MITA_MANAGER_STATE_DIR" ] || fail 'recovery choice 0 created manager layout'
assert_state CURRENT_PARTIAL_INSTALL 'recovery choice 0 preserves partial transaction'

reset_fixture
nb_lifecycle_begin install prepare
(
  id() { [ "${1:-}" = -u ] && printf 0; }
  nb_lifecycle_lock_acquire() { NOBRAND_LIFECYCLE_LOCK_HELD=$((NOBRAND_LIFECYCLE_LOCK_HELD + 1)); }
  nb_lifecycle_lock_release() { NOBRAND_LIFECYCLE_LOCK_HELD=$((NOBRAND_LIFECYCLE_LOCK_HELD - 1)); }
  read_tty() { printf -v "$1" 1; }
  print_banner() { :; }
  dry_run_should_preview() { return 1; }
  is_mita_elf_binary() { return 1; }
  do_install() { : >"$fixture/noarg-partial-install"; }
  ACTION=""
  main
)
[ -e "$fixture/noarg-partial-install" ] \
  || fail 'no-argument CURRENT_PARTIAL_INSTALL did not select repair'

reset_fixture
write_schema
write_manager "$SCRIPT_VERSION"
nb_lifecycle_begin repair prepare
(
  id() { [ "${1:-}" = -u ] && printf 0; }
  nb_lifecycle_lock_acquire() { NOBRAND_LIFECYCLE_LOCK_HELD=$((NOBRAND_LIFECYCLE_LOCK_HELD + 1)); }
  nb_lifecycle_lock_release() { NOBRAND_LIFECYCLE_LOCK_HELD=$((NOBRAND_LIFECYCLE_LOCK_HELD - 1)); }
  read_tty() { printf -v "$1" 1; }
  ensure_manager_state_layout() { return 0; }
  print_banner() { :; }
  dry_run_should_preview() { return 1; }
  is_mita_elf_binary() { return 1; }
  do_install() { : >"$fixture/noarg-partial-repair"; }
  ACTION=""
  main
)
[ -e "$fixture/noarg-partial-repair" ] \
  || fail 'no-argument CURRENT_PARTIAL_REPAIR did not select repair'

reset_fixture
nb_lifecycle_begin uninstall prepare
(
  id() { [ "${1:-}" = -u ] && printf 0; }
  nb_lifecycle_lock_acquire() { NOBRAND_LIFECYCLE_LOCK_HELD=$((NOBRAND_LIFECYCLE_LOCK_HELD + 1)); }
  nb_lifecycle_lock_release() { NOBRAND_LIFECYCLE_LOCK_HELD=$((NOBRAND_LIFECYCLE_LOCK_HELD - 1)); }
  read_tty() { printf -v "$1" 2; }
  ensure_manager_state_layout() { return 0; }
  dry_run_should_preview() { return 1; }
  is_mita_elf_binary() { return 1; }
  nobrand_uninstall() { : >"$fixture/noarg-partial-uninstall"; }
  ACTION=""
  main
)
[ -e "$fixture/noarg-partial-uninstall" ] \
  || fail 'no-argument CURRENT_PARTIAL_UNINSTALL did not select continued cleanup'

reset_fixture
write_schema
write_manager "$SCRIPT_VERSION"
(
  id() { [ "${1:-}" = -u ] && printf 0; }
  nb_lifecycle_lock_acquire() { NOBRAND_LIFECYCLE_LOCK_HELD=$((NOBRAND_LIFECYCLE_LOCK_HELD + 1)); }
  nb_lifecycle_lock_release() { NOBRAND_LIFECYCLE_LOCK_HELD=$((NOBRAND_LIFECYCLE_LOCK_HELD - 1)); }
  ensure_manager_state_layout() { return 0; }
  nb_select_partial_recovery_action() { : >"$fixture/unexpected-complete-recovery"; return 1; }
  nobrand_menu_loop() {
    (
      assert_eq 1 "$NOBRAND_LIFECYCLE_LOCK_HELD" 'menu child inherits lifecycle guard'
      : >"$fixture/current-complete-menu"
    )
  }
  ACTION=""
  main
  assert_eq 0 "$NOBRAND_LIFECYCLE_LOCK_HELD" 'menu outer lock balance'
)
[ -e "$fixture/current-complete-menu" ] || fail 'CURRENT_COMPLETE no-argument menu changed'
[ ! -e "$fixture/unexpected-complete-recovery" ] \
  || fail 'CURRENT_COMPLETE was sent through partial recovery UX'

reset_fixture
write_schema
write_manager "$SCRIPT_VERSION"
nb_lifecycle_begin uninstall prepare
pending_ssh_tx_hash="$(sha256sum "$NOBRAND_LIFECYCLE_TX_FILE")"
(
  id() { [ "${1:-}" = -u ] && printf 0; }
  nb_lifecycle_lock_acquire() { NOBRAND_LIFECYCLE_LOCK_HELD=$((NOBRAND_LIFECYCLE_LOCK_HELD + 1)); }
  nb_lifecycle_lock_release() { NOBRAND_LIFECYCLE_LOCK_HELD=$((NOBRAND_LIFECYCLE_LOCK_HELD - 1)); }
  nobrand_ssh_confirmation_pending() { return 0; }
  nobrand_pending_ssh_confirmation_notice() { : >"$fixture/pending-ssh-notice"; }
  nb_select_partial_recovery_action() { : >"$fixture/unexpected-pending-ssh-recovery"; }
  nobrand_menu_loop() { : >"$fixture/unexpected-pending-ssh-menu"; }
  ACTION=""
  main
  assert_eq 0 "$NOBRAND_LIFECYCLE_LOCK_HELD" 'pending SSH confirmation outer lock balance'
)
[ -e "$fixture/pending-ssh-notice" ] || fail 'pending SSH confirmation notice was not shown'
[ ! -e "$fixture/unexpected-pending-ssh-menu" ] \
  || fail 'pending SSH confirmation entered a lock-holding interactive menu'
[ ! -e "$fixture/unexpected-pending-ssh-recovery" ] \
  || fail 'pending SSH confirmation was overwritten by partial-uninstall recovery'
assert_eq "$pending_ssh_tx_hash" "$(sha256sum "$NOBRAND_LIFECYCLE_TX_FILE")" \
  'pending SSH confirmation preserves uninstall transaction'

# Explicit protocol mutations may not bypass an unfinished lifecycle recovery
# route or replace its transaction direction.
for partial_operation in install repair uninstall; do
  reset_fixture
  nb_lifecycle_begin "$partial_operation" prepare
  explicit_partial_hash="$(sha256sum "$NOBRAND_LIFECYCLE_TX_FILE")"
  (
    id() { [ "${1:-}" = -u ] && printf 0; }
    nb_lifecycle_lock_acquire() { NOBRAND_LIFECYCLE_LOCK_HELD=$((NOBRAND_LIFECYCLE_LOCK_HELD + 1)); }
    nb_lifecycle_lock_release() { NOBRAND_LIFECYCLE_LOCK_HELD=$((NOBRAND_LIFECYCLE_LOCK_HELD - 1)); }
    nobrand_run_snell_action() { : >"$fixture/unexpected-explicit-partial-mutation"; }
    ACTION=nobrand-snell
    SNELL_ACTION=install
    if main >/dev/null 2>&1; then
      fail "explicit mutation crossed active ${partial_operation} recovery boundary"
    fi
    assert_eq 0 "$NOBRAND_LIFECYCLE_LOCK_HELD" \
      "explicit ${partial_operation} refusal releases outer lock"
  )
  [ ! -e "$fixture/unexpected-explicit-partial-mutation" ] \
    || fail "explicit mutation dispatched during ${partial_operation} recovery"
  assert_eq "$explicit_partial_hash" "$(sha256sum "$NOBRAND_LIFECYCLE_TX_FILE")" \
    "explicit mutation preserves ${partial_operation} transaction"
done

reset_fixture
nb_lifecycle_begin uninstall prepare
pending_explicit_hash="$(sha256sum "$NOBRAND_LIFECYCLE_TX_FILE")"
(
  id() { [ "${1:-}" = -u ] && printf 0; }
  nb_lifecycle_lock_acquire() { NOBRAND_LIFECYCLE_LOCK_HELD=$((NOBRAND_LIFECYCLE_LOCK_HELD + 1)); }
  nb_lifecycle_lock_release() { NOBRAND_LIFECYCLE_LOCK_HELD=$((NOBRAND_LIFECYCLE_LOCK_HELD - 1)); }
  nobrand_ssh_confirmation_pending() { return 0; }
  nobrand_pending_ssh_confirmation_notice() { :; }
  nobrand_run_snell_action() { : >"$fixture/unexpected-pending-ssh-mutation"; }
  ACTION=nobrand-snell
  # Consumed by main() from the sourced dispatcher.
  # shellcheck disable=SC2034
  SNELL_ACTION=install
  if main >/dev/null 2>&1; then
    fail 'explicit protocol mutation crossed pending SSH confirmation boundary'
  fi
  assert_eq 0 "$NOBRAND_LIFECYCLE_LOCK_HELD" \
    'pending SSH explicit refusal releases outer lock'
)
[ ! -e "$fixture/unexpected-pending-ssh-mutation" ] \
  || fail 'explicit mutation dispatched while SSH confirmation was pending'
assert_eq "$pending_explicit_hash" "$(sha256sum "$NOBRAND_LIFECYCLE_TX_FILE")" \
  'pending SSH explicit refusal preserves transaction bytes'

# Declining a no-op reinstall of a complete installation must restore the
# previous complete transaction byte-for-byte instead of fabricating a repair.
reset_fixture
write_schema
write_manager "$SCRIPT_VERSION"
nb_lifecycle_begin install prepare
nb_lifecycle_complete install
complete_before_decline_hash="$(sha256sum "$NOBRAND_LIFECYCLE_TX_FILE")"
(
  require_root() { return 0; }
  require_linux() { return 0; }
  require_cmd() { return 0; }
  nb_lifecycle_lock_acquire() { NOBRAND_LIFECYCLE_LOCK_HELD=$((NOBRAND_LIFECYCLE_LOCK_HELD + 1)); }
  nb_lifecycle_lock_release() { NOBRAND_LIFECYCLE_LOCK_HELD=$((NOBRAND_LIFECYCLE_LOCK_HELD - 1)); }
  ensure_manager_state_layout() { return 0; }
  detect_pkg_manager() { printf deb; }
  detect_arch() { printf amd64; }
  ensure_management_dependencies() { return 0; }
  mita_installed() { return 0; }
  installed_version() { printf 3.36.0; }
  mita_preservable_config_exists() { return 0; }
  confirm() { return 1; }
  YES=0
  # Consumed by do_install() from the sourced lifecycle module.
  # shellcheck disable=SC2034
  MENU_MODE=0
  do_install >/dev/null
  assert_eq 0 "$NOBRAND_LIFECYCLE_LOCK_HELD" \
    'declined complete reinstall releases lifecycle lock'
)
assert_eq "$complete_before_decline_hash" "$(sha256sum "$NOBRAND_LIFECYCLE_TX_FILE")" \
  'declined complete reinstall preserves complete lifecycle bytes'
assert_state CURRENT_COMPLETE 'declined complete reinstall remains complete'

# Representative protocol dispatch and a nested native lifecycle action both
# retain the main process guard. Locking alone must not create transaction
# metadata for unrelated protocol work.
reset_fixture
(
  id() { [ "${1:-}" = -u ] && printf 0; }
  nb_lifecycle_lock_acquire() { NOBRAND_LIFECYCLE_LOCK_HELD=$((NOBRAND_LIFECYCLE_LOCK_HELD + 1)); }
  nb_lifecycle_lock_release() { NOBRAND_LIFECYCLE_LOCK_HELD=$((NOBRAND_LIFECYCLE_LOCK_HELD - 1)); }
  ensure_manager_state_layout() { return 0; }
  dry_run_should_preview() { return 1; }
  is_mita_elf_binary() { return 1; }
  nobrand_run_snell_action() {
    assert_eq 1 "$NOBRAND_LIFECYCLE_LOCK_HELD" 'protocol mutation lifecycle guard depth'
    [ ! -e "$NOBRAND_LIFECYCLE_TX_FILE" ] || return 1
    : >"$fixture/protocol-dispatched"
  }
  export ACTION=nobrand-snell
  main
  assert_eq 0 "$NOBRAND_LIFECYCLE_LOCK_HELD" 'protocol dispatch outer lock balance'
)
[ -e "$fixture/protocol-dispatched" ] || fail 'representative protocol mutation was not dispatched'
[ ! -e "$NOBRAND_LIFECYCLE_TX_FILE" ] || fail 'protocol guard created lifecycle transaction metadata'

reset_fixture
(
  id() { [ "${1:-}" = -u ] && printf 0; }
  nb_lifecycle_lock_acquire() { NOBRAND_LIFECYCLE_LOCK_HELD=$((NOBRAND_LIFECYCLE_LOCK_HELD + 1)); }
  nb_lifecycle_lock_release() { NOBRAND_LIFECYCLE_LOCK_HELD=$((NOBRAND_LIFECYCLE_LOCK_HELD - 1)); }
  ensure_manager_state_layout() { return 0; }
  print_banner() { :; }
  dry_run_should_preview() { return 1; }
  is_mita_elf_binary() { return 1; }
  do_install() {
    assert_eq 1 "$NOBRAND_LIFECYCLE_LOCK_HELD" 'outer lifecycle guard before nested install'
    nb_lifecycle_lock_acquire
    assert_eq 2 "$NOBRAND_LIFECYCLE_LOCK_HELD" 'nested lifecycle lock depth'
    nb_lifecycle_lock_release
    assert_eq 1 "$NOBRAND_LIFECYCLE_LOCK_HELD" 'nested release retains outer lifecycle guard'
  }
  export ACTION=install
  main
  assert_eq 0 "$NOBRAND_LIFECYCLE_LOCK_HELD" 'nested lifecycle final lock balance'
)

# Exact public v3.2.0 partial-uninstall shape repaired by the full, generated
# v3.2.1 maintenance release. No protocol/user state survives, so only schema
# and manager may be recreated; the normal fresh Mieru installer must not run.
reset_fixture
SCRIPT_VERSION="$BASE_SCRIPT_VERSION"
reproduce_v320_partial_uninstall
assert_state CURRENT_PARTIAL_UNINSTALL 'exact v3.2.0 repair fixture classification'
maintenance_candidate_state="$(
  # shellcheck disable=SC1091
  source "$TEST_ROOT/install-nobrand.sh"
  trap - ERR
  nb_classify_installation_state
)"
assert_eq CURRENT_PARTIAL_UNINSTALL "$maintenance_candidate_state" \
  'generated maintenance candidate classifies exact v3.2.0 partial uninstall'
maintenance_candidate_size="$(wc -c <"$TEST_ROOT/install-nobrand.sh" | tr -d '[:space:]')"
maintenance_candidate_sha256="$(sha256sum "$TEST_ROOT/install-nobrand.sh" | awk '{print $1}')"
(
  # Exercise the generated maintenance artifact itself. Source first, then
  # replace only the external/runtime effects needed for this manager-only
  # repair; its classifier, transaction, self-install, and validation stay real.
  # shellcheck disable=SC1091
  source "$TEST_ROOT/install-nobrand.sh"
  trap - ERR
  cmp() {
    [ "${1:-}" = -s ] || return 2
    shift
    [ "$#" -eq 2 ] || return 2
    [ -f "$1" ] && [ -f "$2" ] || return 1
    [ "$(sha256sum "$1" | awk '{print $1}')" = \
      "$(sha256sum "$2" | awk '{print $1}')" ]
  }
  mktemp_file() { mktemp "$fixture/maintenance-tmp.XXXXXX"; }
  require_root() { return 0; }
  require_linux() { return 0; }
  require_cmd() { return 0; }
  nb_lifecycle_lock_acquire() { fake_lifecycle_lock_acquire; }
  nb_lifecycle_lock_release() { fake_lifecycle_lock_release; }
  do_install_impl() { : >"$fixture/fresh-mieru-called"; return 99; }
  nobrand_restore_protocol_runtimes() { : >"$fixture/protocol-restore-called"; return 99; }
  nobrand_start_enabled_services() { return 99; }
  nobrand_doctor() { return 99; }
  do_install
)
[ ! -e "$fixture/fresh-mieru-called" ] || fail 'partial uninstall fabricated a fresh Mieru node'
[ ! -e "$fixture/protocol-restore-called" ] || fail 'manager-only repair invented protocol state'
[ ! -e "$MITA_STATE" ] || fail 'manager-only repair fabricated Mieru install state'
[ ! -e "$MITA_USERS_STATE" ] || fail 'manager-only repair fabricated Mieru users'
assert_eq repair "$(nb_lifecycle_field OPERATION)" 'partial uninstall repair transaction'
assert_eq complete "$(nb_lifecycle_field STATUS)" 'partial uninstall repair completed'
assert_eq "$maintenance_candidate_size" \
  "$(wc -c <"$NOBRAND_INSTALL_SCRIPT_PATH" | tr -d '[:space:]')" \
  'partial-uninstall repair installs the full maintenance candidate size'
assert_eq "$maintenance_candidate_sha256" \
  "$(sha256sum "$NOBRAND_INSTALL_SCRIPT_PATH" | awk '{print $1}')" \
  'partial-uninstall repair installs the exact maintenance candidate bytes'
assert_eq "$NOBRAND_INSTALL_SCRIPT_PATH" "$(readlink "$NOBRAND_COMMAND_PATH")" \
  'partial-uninstall repair restores the nobrand command'
assert_eq "$NOBRAND_COMMAND_PATH" "$(readlink "$NOBRAND_SHORT_COMMAND_PATH")" \
  'partial-uninstall repair restores the nb command'
assert_contains "$(MITA_SOURCE_ONLY=0 "$NOBRAND_COMMAND_PATH" --version)" \
  "NoBrand-OneClick ${BASE_SCRIPT_VERSION}" \
  'repaired full maintenance manager is executable'
assert_state CURRENT_COMPLETE 'v3.2.0 partial uninstall repaired by maintenance candidate'

# If SSH state survives a partial unified uninstall after its managed policy
# was removed, repair must restore from that state and stop at the fresh-admin
# confirmation boundary. Confirmation owns the later repair resume; lifecycle
# completion is allowed only after the restored policy and doctor pass.
reset_fixture
SCRIPT_VERSION=3.2.1
write_schema
write_manager "$SCRIPT_VERSION"
nb_lifecycle_begin uninstall prepare
mkdir -p "$NOBRAND_SSH_STATE_DIR" "$(dirname "$NOBRAND_SSH_CONFIG_MAIN")"
printf '%s\n' 'Port 2222' >"$NOBRAND_SSH_CONFIG_MAIN"
ssh_repair_user="$(ssh_tunnel_user_json a1111111111111111 repair \
  nbt-repair 49001 SHA256:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA 2026-08-30T00:00:00Z)"
ssh_repair_users="$(jq -cn --argjson user "$ssh_repair_user" '[$user]')"
ssh_tunnel_generate_state "$NOBRAND_SSH_STATE_FILE" custom entry.example.test 443 2222 \
  marker-block "$NOBRAND_SSH_CONFIG_MAIN" "$ssh_repair_users" 2026-08-30T00:00:00Z
ssh_repair_state_tmp="$(mktemp_file .ssh-repair-state)"
jq '
  .policy_applied=false
  | .pending_operation="unified-uninstall"
  | .pending_watchdog_token=""
  | .pending_watchdog_pid=""
  | .pending_origin_connection=""
' "$NOBRAND_SSH_STATE_FILE" >"$ssh_repair_state_tmp"
install -m 0600 "$ssh_repair_state_tmp" "$NOBRAND_SSH_STATE_FILE"
rm -f "$ssh_repair_state_tmp"
ssh_repair_token=0123456789abcdef0123456789abcdef
ssh_repair_origin='192.0.2.10 41000 192.0.2.20 22'
ssh_repair_fresh_origin='198.51.100.10 42000 198.51.100.20 22'
ssh_repair_restore_calls="$fixture/ssh-repair-restore.calls"
ssh_repair_validation_trace="$fixture/ssh-repair-validation.trace"
(
  require_root() { return 0; }
  require_linux() { return 0; }
  require_cmd() { return 0; }
  nb_lifecycle_lock_acquire() { fake_lifecycle_lock_acquire; }
  nb_lifecycle_lock_release() { fake_lifecycle_lock_release; }
  nb_atomic_install_file() {
    local source="$1" destination="$2" mode="${3:-0600}"
    mkdir -p "$(dirname "$destination")" \
      && install -m "$mode" "$source" "$destination"
  }
  install_self_script() { write_manager "$SCRIPT_VERSION"; }
  nobrand_restore_protocol_runtimes() { return 0; }
  nobrand_start_enabled_services() { return 0; }
  ssh_tunnel_watchdog_claim_ready() { return 0; }
  ssh_tunnel_restore_system_state() {
    local state_tmp
    printf 'restore\n' >>"$ssh_repair_restore_calls"
    state_tmp="$(mktemp_file .ssh-restore-pending)" || return 1
    jq --arg token "$ssh_repair_token" --arg origin "${SSH_CONNECTION:-}" '
      .policy_applied=true
      | .pending_operation="restore"
      | .pending_watchdog_token=$token
      | .pending_watchdog_pid="4242"
      | .pending_origin_connection=$origin
    ' "$NOBRAND_SSH_STATE_FILE" >"$state_tmp" \
      && nb_atomic_install_file "$state_tmp" "$NOBRAND_SSH_STATE_FILE" 0600 || {
        rm -f "$state_tmp"
        return 1
      }
    rm -f "$state_tmp"
    mkdir -p "$NOBRAND_SSH_WATCHDOG_DIR"
    chmod 0700 "$NOBRAND_SSH_WATCHDOG_DIR"
    : >"${NOBRAND_SSH_WATCHDOG_DIR}/${ssh_repair_token}.armed"
  }
  ssh_tunnel_sshd_test() {
    assert_eq restore "$(ssh_tunnel_state_field pending_operation)" \
      'fresh-admin confirmation validates the restored SSH operation'
    assert_eq "$ssh_repair_token" "$(ssh_tunnel_state_field pending_watchdog_token)" \
      'fresh-admin confirmation validates the restored SSH watchdog token'
    printf 'policy\n' >>"$ssh_repair_validation_trace"
  }
  nobrand_doctor() {
    assert_eq true "$(ssh_tunnel_state_field policy_applied)" \
      'repair doctor sees the restored SSH policy'
    assert_eq '' "$(ssh_tunnel_state_field pending_operation)" \
      'repair doctor runs after SSH confirmation clears the pending operation'
    assert_eq '' "$(ssh_tunnel_state_field pending_watchdog_token)" \
      'repair doctor runs after SSH confirmation clears the watchdog token'
    assert_eq in-progress "$(nb_lifecycle_field STATUS)" \
      'repair lifecycle remains in progress during doctor validation'
    printf 'doctor\n' >>"$ssh_repair_validation_trace"
  }

  SSH_CONNECTION="$ssh_repair_origin" do_install
  assert_eq 0 "$NOBRAND_LIFECYCLE_LOCK_HELD" \
    'SSH restore confirmation wait releases the lifecycle lock'
  assert_eq 1 "$(wc -l <"$ssh_repair_restore_calls" | tr -d '[:space:]')" \
    'partial-uninstall repair invokes SSH system-state restore once'
  assert_eq restore "$(ssh_tunnel_state_field pending_operation)" \
    'SSH repair persists the restore operation'
  assert_eq true "$(ssh_tunnel_state_field policy_applied)" \
    'SSH repair records its restored policy before confirmation'
  assert_eq "$ssh_repair_token" "$(ssh_tunnel_state_field pending_watchdog_token)" \
    'SSH repair persists a nonempty confirmation token'
  assert_eq repair "$(nb_lifecycle_field OPERATION)" \
    'SSH confirmation wait retains the repair operation'
  assert_eq in-progress "$(nb_lifecycle_field STATUS)" \
    'SSH confirmation wait retains an in-progress repair transaction'
  assert_eq partial-uninstall-ssh-confirmation-pending \
    "$(nb_lifecycle_field LAST_COMPLETED_PHASE)" \
    'SSH confirmation wait records the recovery boundary'
  [ ! -e "$ssh_repair_validation_trace" ] \
    || fail 'SSH confirmation wait ran final policy or doctor validation early'

  SSH_CONNECTION="$ssh_repair_fresh_origin" \
    ssh_tunnel_confirm_admin "$ssh_repair_token" >/dev/null
  assert_eq 0 "$NOBRAND_LIFECYCLE_LOCK_HELD" \
    'fresh-admin repair resume releases the lifecycle lock'
)
assert_eq 1 "$(wc -l <"$ssh_repair_restore_calls" | tr -d '[:space:]')" \
  'confirmed repair resume does not restore SSH state twice'
assert_eq $'policy\ndoctor' "$(cat "$ssh_repair_validation_trace")" \
  'policy validation precedes doctor and lifecycle completion'
assert_eq repair "$(nb_lifecycle_field OPERATION)" \
  'confirmed SSH repair keeps the repair transaction identity'
assert_eq complete "$(nb_lifecycle_field STATUS)" \
  'confirmed SSH repair completes after policy and doctor validation'
assert_state CURRENT_COMPLETE 'confirmed SSH restore converges partial uninstall repair'

# Phase one of SSH-protected unified uninstall is a successful wait, not a
# failed final postcondition. Keep the uninstall transaction for the fresh
# administrator confirmation process to resume.
reset_fixture
write_schema
write_manager "$SCRIPT_VERSION"
(
  require_root() { return 0; }
  nb_lifecycle_lock_acquire() { fake_lifecycle_lock_acquire; }
  nb_lifecycle_lock_release() { fake_lifecycle_lock_release; }
  nobrand_uninstall_impl() { return 0; }
  ssh_tunnel_state_exists() { return 0; }
  ssh_tunnel_state_field() { [ "${1:-}" = pending_operation ] && printf unified-uninstall; }
  nobrand_uninstall_postcondition() {
    : >"$fixture/unexpected-unified-uninstall-postcondition"
    return 1
  }
  YES=1
  nobrand_uninstall
  assert_eq 0 "$NOBRAND_LIFECYCLE_LOCK_HELD" 'pending unified uninstall lock balance'
)
[ ! -e "$fixture/unexpected-unified-uninstall-postcondition" ] \
  || fail 'pending unified uninstall ran the final postcondition'
assert_eq uninstall "$(nb_lifecycle_field OPERATION)" 'pending unified uninstall operation'
assert_eq in-progress "$(nb_lifecycle_field STATUS)" 'pending unified uninstall transaction'
assert_state CURRENT_PARTIAL_UNINSTALL 'pending unified uninstall remains resumable'

stub_uninstall_dependencies() {
  require_root() { return 0; }
  nb_lifecycle_lock_acquire() { fake_lifecycle_lock_acquire; }
  nb_lifecycle_lock_release() { fake_lifecycle_lock_release; }
  mita_uninstall_target_present() { return 1; }
  ssh_tunnel_state_exists() { return 1; }
  admin_lock_acquire() { return 0; }
  admin_lock_release() { return 0; }
  snell_instance_ids() { return 0; }
  hysteria2_state_exists() { return 1; }
  vless_sudoku_state_exists() { return 1; }
  reality_instance_ids() { return 0; }
  tuic_instance_ids() { return 0; }
  reality_remove_service_runtime_if_owned() { return 0; }
  nb_service_manager() { printf none; }
  nb_strict_firewall_clear_all() { return 0; }
  nft() { return 1; }
}

uninstall_interrupt_phases=(
  runtime-removed
  before-state-removal
  state-removed
  before-config-removal
  config-removed
  roots-removed
  before-manager-removal
  manager-removed
  before-final-validation
)
UNINSTALL_INTERRUPT_EXERCISED_COUNT=0

prepare_current_complete_uninstall_fixture() {
  reset_fixture
  write_schema
  write_manager "$SCRIPT_VERSION"
  mkdir -p "$NOBRAND_CONFIG_DIR" "$NOBRAND_LIB_DIR"
  printf '%s\n' 'owned-state' >"$NOBRAND_STATE_DIR/uninstall-owned-state"
  printf '%s\n' 'owned-config' >"$NOBRAND_CONFIG_DIR/uninstall-owned-config"
  printf '%s\n' 'owned-runtime' >"$NOBRAND_LIB_DIR/uninstall-owned-runtime"
  ln -s "$NOBRAND_INSTALL_SCRIPT_PATH" "$NOBRAND_COMMAND_PATH"
  ln -s "$NOBRAND_COMMAND_PATH" "$NOBRAND_SHORT_COMMAND_PATH"
  assert_state CURRENT_COMPLETE 'full-uninstall interruption starts complete'
}

# A complete uninstall must remain idempotent when any one managed resource is
# already absent. All other modeled resources stay populated, and a foreign
# sentinel outside every managed root must survive the real top-level cleanup.
already_absent_resource_cases=(
  config-root
  state-dir
  service
  package
  firewall-owner
  port-owner
  defender-owner
)
ALREADY_ABSENT_RESOURCE_EXERCISED_COUNT=0

run_already_absent_resource_case() {
  local absent="$1" reality_id=r3333333333333333
  local owned_root="$fixture/owned-resources-${absent}"
  local service_sentinel="$owned_root/nobrand-vless-reality@.service"
  local package_sentinel="$owned_root/mita.package"
  local package_purge_log="$owned_root/package-purge.log"
  local reality_remove_log="$owned_root/reality-remove.calls"
  local firewall_close_log="$owned_root/firewall-close.calls"
  local reality_state="$NOBRAND_REALITY_STATE_DIR/$reality_id/state.json"
  local foreign_sentinel="$fixture/foreign/must-survive"
  local foreign_hash reality_tmp

  prepare_current_complete_uninstall_fixture
  mkdir -p "$owned_root" "$(dirname "$reality_state")" "$fixture/foreign"
  cat >"$service_sentinel" <<EOF
# Managed by NoBrand-OneClick
Environment=XRAY_LOCATION_ASSET=${NOBRAND_XRAY_ASSET_DIR}
ExecStart=${NOBRAND_XRAY_BIN} run -c ${NOBRAND_REALITY_CONFIG_DIR}/%i/config.json
EOF
  printf '%s\n' 'fixture-package-record' >"$package_sentinel"
  printf '%s\n' 'fixture|tcp|31053' >"$NOBRAND_FIREWALL_OWNED_STATE"
  cat >"$reality_state" <<JSON
{
  "schema_version": 3,
  "ownership": "nobrand-v3",
  "protocol": "vless-reality",
  "instance_id": "${reality_id}",
  "listen_port": 32052,
  "defender_enabled": true,
  "defender_port": 22052,
  "defender_tag": "nobrand-vless-reality-${reality_id}-defender"
}
JSON
  printf '%s\n' 'foreign-bytes-must-survive' >"$foreign_sentinel"
  foreign_hash="$(sha256sum "$foreign_sentinel")"

  case "$absent" in
    config-root) rm -rf -- "$NOBRAND_CONFIG_DIR" ;;
    state-dir)
      # The transaction root is deliberately separate from managed state, so a
      # retry can still be identified after an earlier cleanup removed state.
      nb_lifecycle_begin uninstall prepare
      rm -rf -- "$NOBRAND_STATE_DIR"
      ;;
    service) rm -f -- "$service_sentinel" ;;
    package) rm -f -- "$package_sentinel" ;;
    firewall-owner) rm -f -- "$NOBRAND_FIREWALL_OWNED_STATE" ;;
    port-owner)
      reality_tmp="$(mktemp_file .reality-no-port)"
      jq 'del(.listen_port)' "$reality_state" >"$reality_tmp"
      install -m 0600 "$reality_tmp" "$reality_state"
      rm -f -- "$reality_tmp"
      ;;
    defender-owner)
      reality_tmp="$(mktemp_file .reality-no-defender)"
      jq '.defender_enabled=false | del(.defender_port,.defender_tag)' \
        "$reality_state" >"$reality_tmp"
      install -m 0600 "$reality_tmp" "$reality_state"
      rm -f -- "$reality_tmp"
      ;;
    *) fail "unknown already-absent resource fixture: $absent" ;;
  esac

  case "$absent" in
    config-root) [ ! -e "$NOBRAND_CONFIG_DIR" ] || fail 'config-root absence was not prepared' ;;
    state-dir)
      [ ! -e "$NOBRAND_STATE_DIR" ] || fail 'state-dir absence was not prepared'
      assert_state CURRENT_PARTIAL_UNINSTALL \
        'state-dir absence retains separate uninstall recovery transaction'
      ;;
    service) [ ! -e "$service_sentinel" ] || fail 'service absence was not prepared' ;;
    package) [ ! -e "$package_sentinel" ] || fail 'package absence was not prepared' ;;
    firewall-owner)
      [ ! -e "$NOBRAND_FIREWALL_OWNED_STATE" ] \
        || fail 'firewall-owner absence was not prepared'
      ;;
    port-owner|defender-owner)
      (
        # shellcheck disable=SC1091
        source "$TEST_ROOT/src/25-network-mtu.sh"
        # shellcheck disable=SC1091
        source "$TEST_ROOT/src/16-core-port.sh"
        # shellcheck disable=SC1091
        source "$TEST_ROOT/src/59-vless-reality.sh"
        if [ "$absent" = port-owner ]; then
          ! nb_registry_port_owner TCP 32052 >/dev/null 2>&1 \
            || fail 'port-owner absence was not prepared'
          assert_eq "vless-reality-defender:${reality_id}" \
            "$(reality_defender_port_owner 22052)" \
            'port-owner case retains defender ownership'
        else
          assert_eq "vless-reality:${reality_id}" \
            "$(nb_registry_port_owner TCP 32052)" \
            'defender-owner case retains public port ownership'
          ! reality_defender_port_owner 22052 >/dev/null 2>&1 \
            || fail 'defender-owner absence was not prepared'
        fi
      )
      ;;
  esac

  (
    stub_uninstall_dependencies
    # Restore the real Reality ownership readers/enumerator after the generic
    # uninstall stubs, while keeping every service/network side effect inert.
    # shellcheck disable=SC1091
    source "$TEST_ROOT/src/25-network-mtu.sh"
    # shellcheck disable=SC1091
    source "$TEST_ROOT/src/16-core-port.sh"
    # shellcheck disable=SC1091
    source "$TEST_ROOT/src/59-vless-reality.sh"
    export NOBRAND_REALITY_SYSTEMD_TEMPLATE="$service_sentinel"
    # shellcheck disable=SC1091
    source "$TEST_ROOT/src/25-platform-vless-reality.sh"
    reality_remove_service() {
      [ "${1:-}" = "$reality_id" ] \
        || fail "unexpected Reality instance cleanup: ${1:-empty}"
      printf '%s\n' "$1" >>"$reality_remove_log"
    }
    systemctl() { fail "unexpected systemctl in already-absent fixture: $*"; }
    rc-service() { fail "unexpected rc-service in already-absent fixture: $*"; }
    rc-update() { fail "unexpected rc-update in already-absent fixture: $*"; }
    mita_uninstall_target_present() { return 0; }
    installed_by_oneclick() { return 0; }
    confirm() { return 0; }
    preexisting_mita_resources_recorded() { return 1; }
    restore_owned_bbr_fq() { return 0; }
    detect_pkg_manager() { printf deb; }
    stop_mita_for_uninstall() { return 0; }
    firewall_clear_all_owned() { return 0; }
    mieru_clear_strict_firewall() { return 0; }
    dpkg-query() { [ -e "$package_sentinel" ]; }
    run() {
      if [ "${1:-}" = dpkg ] && [ "${2:-}" = -P ] && [ "${3:-}" = mita ]; then
        printf 'purge\n' >>"$package_purge_log"
        rm -f -- "$package_sentinel"
        return 0
      fi
      fail "unexpected command in already-absent uninstall fixture: $*"
    }
    remove_mita_common() { rm -f -- "$MITA_MARKER"; }
    verify_mita_uninstalled() { [ ! -e "$package_sentinel" ]; }
    nb_firewall_close_pairs() {
      [ -n "${1:-}" ] || return 0
      printf '%s\n' "$1" | sed '/^$/d' >>"$firewall_close_log"
      case "$1" in
        *'TCP|31053'*) rm -f -- "$NOBRAND_FIREWALL_OWNED_STATE" ;;
      esac
    }
    if [ "$absent" = state-dir ]; then
      [ -z "$(reality_instance_ids)" ] \
        || fail 'state-dir absence unexpectedly retained a Reality instance'
    else
      assert_eq "$reality_id" "$(reality_instance_ids)" \
        "already-absent ${absent} uses real Reality enumeration"
    fi
    case "$absent" in
      port-owner)
        ! nb_registry_port_owner TCP 32052 >/dev/null 2>&1 \
          || fail 'port-owner cleanup fixture unexpectedly regained public ownership'
        assert_eq "vless-reality-defender:${reality_id}" \
          "$(reality_defender_port_owner 22052)" \
          'port-owner cleanup fixture retains defender ownership'
        ;;
      defender-owner)
        assert_eq "vless-reality:${reality_id}" \
          "$(nb_registry_port_owner TCP 32052)" \
          'defender-owner cleanup fixture retains public ownership'
        ! reality_defender_port_owner 22052 >/dev/null 2>&1 \
          || fail 'defender-owner cleanup fixture unexpectedly regained ownership'
        ;;
    esac
    YES=1
    nobrand_uninstall >/dev/null
  )

  assert_state CLEAN "already-absent ${absent} full uninstall convergence"
  for owned_path in \
    "$NOBRAND_LIFECYCLE_TX_FILE" "$NOBRAND_STATE_DIR" "$NOBRAND_CONFIG_DIR" \
    "$NOBRAND_LIB_DIR" "$NOBRAND_INSTALL_SCRIPT_PATH" "$NOBRAND_COMMAND_PATH" \
    "$NOBRAND_SHORT_COMMAND_PATH" "$service_sentinel" "$package_sentinel" \
    "$NOBRAND_FIREWALL_OWNED_STATE" "$reality_state"; do
    [ ! -e "$owned_path" ] && [ ! -L "$owned_path" ] \
      || fail "already-absent ${absent} retained owned resource: $owned_path"
  done
  assert_eq "$foreign_hash" "$(sha256sum "$foreign_sentinel")" \
    "already-absent ${absent} preserves foreign sentinel"
  if [ "$absent" = state-dir ]; then
    [ ! -e "$reality_remove_log" ] \
      || fail 'state-dir absence invoked Reality instance cleanup'
  else
    assert_eq "$reality_id" "$(cat "$reality_remove_log")" \
      "already-absent ${absent} removes the enumerated Reality instance once"
  fi
  case "$absent" in
    state-dir)
      [ ! -e "$firewall_close_log" ] \
        || fail 'state-dir absence invoked a firewall close'
      ;;
    firewall-owner)
      assert_eq 'TCP|32052' "$(cat "$firewall_close_log")" \
        'firewall-owner absence closes only the Reality public port'
      ;;
    port-owner)
      assert_eq 'TCP|31053' "$(cat "$firewall_close_log")" \
        'port-owner absence closes only the independent firewall row'
      ;;
    *)
      assert_eq $'TCP|32052\nTCP|31053' "$(cat "$firewall_close_log")" \
        "already-absent ${absent} closes public and independent firewall owners"
      ;;
  esac
  [ ! -e "$firewall_close_log" ] \
    || assert_not_contains "$(cat "$firewall_close_log")" '22052' \
      "already-absent ${absent} never treats the loopback defender as a public firewall owner"
  if [ "$absent" = package ]; then
    [ ! -e "$package_purge_log" ] \
      || fail 'already-absent package triggered a package purge'
  else
    assert_eq 1 "$(wc -l <"$package_purge_log" | tr -d '[:space:]')" \
      "already-absent ${absent} purges the modeled owned package once"
  fi
  ALREADY_ABSENT_RESOURCE_EXERCISED_COUNT=$((ALREADY_ABSENT_RESOURCE_EXERCISED_COUNT + 1))
}

for absent_resource in "${already_absent_resource_cases[@]}"; do
  run_already_absent_resource_case "$absent_resource"
done
assert_eq "${#already_absent_resource_cases[@]}" \
  "$ALREADY_ABSENT_RESOURCE_EXERCISED_COUNT" \
  'every already-absent resource case was exercised'
printf 'ALREADY_ABSENT_RESOURCE_MATRIX=PASS\n'

run_standard_uninstall_interrupt_phase() {
  local phase="$1" rc=0
  prepare_current_complete_uninstall_fixture
  (
    stub_uninstall_dependencies
    YES=1
    export NOBRAND_TEST_INTERRUPT_UNINSTALL_AT="$phase"
    set +e
    nobrand_uninstall >/dev/null 2>&1
    rc=$?
    set -e
    [ "$rc" -ne 0 ] || fail "uninstall checkpoint did not interrupt: $phase"
  )
  assert_eq uninstall "$(nb_lifecycle_field OPERATION)" \
    "interrupted uninstall operation: $phase"
  assert_eq in-progress "$(nb_lifecycle_field STATUS)" \
    "interrupted uninstall status: $phase"
  assert_eq "$phase" "$(nb_lifecycle_field LAST_COMPLETED_PHASE)" \
    "interrupted uninstall phase: $phase"
  assert_state CURRENT_PARTIAL_UNINSTALL "interrupted uninstall classification: $phase"
  (
    stub_uninstall_dependencies
    YES=1
    unset NOBRAND_TEST_INTERRUPT_UNINSTALL_AT
    nobrand_uninstall >/dev/null
  )
  assert_state CLEAN "uninstall rerun convergence: $phase"
  [ ! -e "$NOBRAND_LIFECYCLE_TX_FILE" ] \
    || fail "uninstall rerun retained transaction: $phase"
  [ ! -e "$NOBRAND_STATE_DIR" ] \
    || fail "uninstall rerun retained state: $phase"
  [ ! -e "$NOBRAND_CONFIG_DIR" ] \
    || fail "uninstall rerun retained config: $phase"
  [ ! -e "$NOBRAND_LIB_DIR" ] \
    || fail "uninstall rerun retained runtime: $phase"
  [ ! -e "$NOBRAND_INSTALL_SCRIPT_PATH" ] \
    || fail "uninstall rerun retained manager: $phase"
  UNINSTALL_INTERRUPT_EXERCISED_COUNT=$((UNINSTALL_INTERRUPT_EXERCISED_COUNT + 1))
}

for lifecycle_phase in "${uninstall_interrupt_phases[@]}"; do
  run_standard_uninstall_interrupt_phase "$lifecycle_phase"
done

# The Mieru ownership decision must survive independently of the state root.
# This exercises the real top-level ledger capture, removes state at an actual
# uninstall checkpoint, then verifies that the retry still enters Mieru cleanup
# with the original per-resource preservation decisions.
prepare_current_complete_uninstall_fixture
mkdir -p "$MITA_MANAGER_STATE_DIR" "$(dirname "$MITA_BIN")"
touch "$MITA_MARKER" "$MITA_PRESERVE_PACKAGE_MARKER" \
  "$MITA_PRESERVE_USER_MARKER" "$MITA_PRESERVE_GROUP_MARKER" \
  "$MITA_PRESERVE_SHARED_MARKER" "$MITA_BIN"
chmod 0600 "$MITA_MARKER" "$MITA_PRESERVE_PACKAGE_MARKER" \
  "$MITA_PRESERVE_USER_MARKER" "$MITA_PRESERVE_GROUP_MARKER" \
  "$MITA_PRESERVE_SHARED_MARKER"
chmod 0755 "$MITA_BIN"
mieru_ledger_log="$fixture/mieru-uninstall-ledger.log"
(
  stub_uninstall_dependencies
  mita_uninstall_target_present() {
    mita_uninstall_ledger_active || installed_by_oneclick
  }
  do_uninstall() {
    printf '%s|%s|%s|%s|%s\n' \
      "$(nb_lifecycle_field MIERU_OWNED)" \
      "$(nb_lifecycle_field MIERU_PRESERVE_PACKAGE)" \
      "$(nb_lifecycle_field MIERU_PRESERVE_USER)" \
      "$(nb_lifecycle_field MIERU_PRESERVE_GROUP)" \
      "$(nb_lifecycle_field MIERU_PRESERVE_SHARED)" >>"$mieru_ledger_log"
  }
  YES=1
  export NOBRAND_TEST_INTERRUPT_UNINSTALL_AT=state-removed
  set +e
  nobrand_uninstall >/dev/null 2>&1
  rc=$?
  set -e
  [ "$rc" -ne 0 ] || fail 'Mieru ledger fixture did not interrupt after state removal'
)
[ ! -e "$NOBRAND_STATE_DIR" ] || fail 'Mieru ledger fixture retained removed state root'
assert_eq '1|1|1|1|1' "$(
  printf '%s|%s|%s|%s|%s' \
    "$(nb_lifecycle_field MIERU_OWNED)" \
    "$(nb_lifecycle_field MIERU_PRESERVE_PACKAGE)" \
    "$(nb_lifecycle_field MIERU_PRESERVE_USER)" \
    "$(nb_lifecycle_field MIERU_PRESERVE_GROUP)" \
    "$(nb_lifecycle_field MIERU_PRESERVE_SHARED)"
)" 'uninstall transaction preserves Mieru ownership ledger after state removal'
(
  stub_uninstall_dependencies
  mita_uninstall_target_present() {
    mita_uninstall_ledger_active || installed_by_oneclick
  }
  do_uninstall() {
    printf '%s|%s|%s|%s|%s\n' \
      "$(nb_lifecycle_field MIERU_OWNED)" \
      "$(nb_lifecycle_field MIERU_PRESERVE_PACKAGE)" \
      "$(nb_lifecycle_field MIERU_PRESERVE_USER)" \
      "$(nb_lifecycle_field MIERU_PRESERVE_GROUP)" \
      "$(nb_lifecycle_field MIERU_PRESERVE_SHARED)" >>"$mieru_ledger_log"
  }
  YES=1
  unset NOBRAND_TEST_INTERRUPT_UNINSTALL_AT
  nobrand_uninstall >/dev/null
)
assert_eq $'1|1|1|1|1\n1|1|1|1|1' "$(cat "$mieru_ledger_log")" \
  'Mieru cleanup retry consumes the durable ledger after state removal'
assert_state CLEAN 'Mieru ledger uninstall retry converges to CLEAN'

reset_fixture
nb_lifecycle_begin uninstall prepare 1 1 1 1 1
rm -rf -- "$NOBRAND_STATE_DIR" "$NOBRAND_CONFIG_DIR" "$NOBRAND_LIB_DIR"
original_mita_client_export_dir="$MITA_CLIENT_EXPORT_DIR"
MIERU_POSTCONDITION_SENTINEL="$fixture/mieru-postcondition-residue"
MITA_CLIENT_EXPORT_DIR="$MIERU_POSTCONDITION_SENTINEL"
mkdir -p "$MITA_CLIENT_EXPORT_DIR"
if nobrand_uninstall_postcondition >/dev/null 2>&1; then
  fail 'full-uninstall postcondition ignored ledger-owned Mieru residue'
fi
rm -rf -- "$MITA_CLIENT_EXPORT_DIR"
nobrand_uninstall_postcondition \
  || fail 'full-uninstall postcondition rejected a fully removed Mieru ledger'
MITA_CLIENT_EXPORT_DIR="$original_mita_client_export_dir"

run_full_uninstall_runtime_cleanup_failure() {
  local failure="$1" marker="$fixture/${1}.attempted" failure_target="" rc manager_digest

  reset_fixture
  write_schema
  write_manager "$SCRIPT_VERSION"
  mkdir -p "$NOBRAND_CONFIG_DIR" "$NOBRAND_LIB_DIR"
  printf 'preserve-state\n' >"$NOBRAND_STATE_DIR/runtime-cleanup-sentinel"
  printf 'preserve-config\n' >"$NOBRAND_CONFIG_DIR/runtime-cleanup-sentinel"
  printf 'preserve-lib\n' >"$NOBRAND_LIB_DIR/runtime-cleanup-sentinel"
  ln -s "$NOBRAND_INSTALL_SCRIPT_PATH" "$NOBRAND_COMMAND_PATH"
  ln -s "$NOBRAND_COMMAND_PATH" "$NOBRAND_SHORT_COMMAND_PATH"
  manager_digest="$(sha256sum "$NOBRAND_INSTALL_SCRIPT_PATH" | awk '{print $1}')"

  (
    stub_uninstall_dependencies
    case "$failure" in
      reality-runtime)
        reality_remove_service_runtime_if_owned() {
          : >"$marker"
          return 71
        }
        ;;
      snell-template)
        failure_target=/etc/systemd/system/nobrand-snell@.service
        NOBRAND_SNELL_SYSTEMD_TEMPLATE="$failure_target"
        ;;
      tuic-template)
        failure_target=/etc/systemd/system/nobrand-tuic@.service
        NOBRAND_TUIC_SYSTEMD_TEMPLATE="$failure_target"
        ;;
      daemon-reload)
        nb_service_manager() { printf systemd; }
        systemctl() {
          [ "${1:-}" = daemon-reload ] \
            || fail "unexpected systemctl operation during ${failure} injection: $*"
          : >"$marker"
          return 72
        }
        ;;
      *) fail "unknown full-uninstall cleanup failure fixture: $failure" ;;
    esac
    if [ -n "$failure_target" ]; then
      rm() {
        local arg
        for arg in "$@"; do
          if [ "$arg" = "$failure_target" ]; then
            : >"$marker"
            return 73
          fi
        done
        command rm "$@"
      }
    fi
    YES=1
    set +e
    nobrand_uninstall
    rc=$?
    set -e
    [ "$rc" -ne 0 ] \
      || fail "full uninstall ignored ${failure} cleanup failure"
  )

  [ -e "$marker" ] || fail "full uninstall did not reach ${failure} cleanup"
  assert_eq preserve-state "$(cat "$NOBRAND_STATE_DIR/runtime-cleanup-sentinel")" \
    "${failure} preserves state"
  assert_eq preserve-config "$(cat "$NOBRAND_CONFIG_DIR/runtime-cleanup-sentinel")" \
    "${failure} preserves config"
  assert_eq preserve-lib "$(cat "$NOBRAND_LIB_DIR/runtime-cleanup-sentinel")" \
    "${failure} preserves manager library"
  assert_eq "$manager_digest" \
    "$(sha256sum "$NOBRAND_INSTALL_SCRIPT_PATH" | awk '{print $1}')" \
    "${failure} preserves manager bytes"
  assert_eq "$NOBRAND_INSTALL_SCRIPT_PATH" "$(readlink "$NOBRAND_COMMAND_PATH")" \
    "${failure} preserves nobrand command"
  assert_eq "$NOBRAND_COMMAND_PATH" "$(readlink "$NOBRAND_SHORT_COMMAND_PATH")" \
    "${failure} preserves nb command"
  assert_eq uninstall "$(nb_lifecycle_field OPERATION)" \
    "${failure} preserves uninstall recovery operation"
  assert_eq in-progress "$(nb_lifecycle_field STATUS)" \
    "${failure} preserves in-progress uninstall recovery state"
  assert_state CURRENT_PARTIAL_UNINSTALL \
    "${failure} remains a recoverable partial uninstall"
}

# Runtime/template integration cleanup is the last boundary before managed
# state, config, libraries, and command entry points may be removed. Every
# failure at that boundary must leave the complete recovery surface intact.
run_full_uninstall_runtime_cleanup_failure reality-runtime
run_full_uninstall_runtime_cleanup_failure snell-template
run_full_uninstall_runtime_cleanup_failure tuic-template
run_full_uninstall_runtime_cleanup_failure daemon-reload

# Continue the exact broken state through the formerly fatal missing-config
# boundary. First inject another interruption there, then rerun to CLEAN.
reset_fixture
SCRIPT_VERSION="$BASE_SCRIPT_VERSION"
reproduce_v320_partial_uninstall
(
  # shellcheck disable=SC1091
  source "$TEST_ROOT/install-nobrand.sh"
  trap - ERR
  stub_uninstall_dependencies
  YES=1
  NOBRAND_TEST_INTERRUPT_UNINSTALL_AT=before-config-removal
  set +e
  nobrand_uninstall
  rc=$?
  set -e
  [ "$rc" -ne 0 ]
)
assert_eq uninstall "$(nb_lifecycle_field OPERATION)" 'interrupted uninstall operation'
assert_eq in-progress "$(nb_lifecycle_field STATUS)" 'interrupted uninstall preserved transaction'
assert_eq before-config-removal "$(nb_lifecycle_field LAST_COMPLETED_PHASE)" \
  'real missing-config boundary checkpoint'
assert_state CURRENT_PARTIAL_UNINSTALL 'second interrupted uninstall remains current partial'
(
  # shellcheck disable=SC1091
  source "$TEST_ROOT/install-nobrand.sh"
  trap - ERR
  stub_uninstall_dependencies
  YES=1
  export NOBRAND_TEST_INTERRUPT_UNINSTALL_AT=before-manager-removal
  set +e
  nobrand_uninstall
  rc=$?
  set -e
  [ "$rc" -ne 0 ] || fail 'second successive uninstall interruption did not stop cleanup'
)
assert_eq before-manager-removal "$(nb_lifecycle_field LAST_COMPLETED_PHASE)" \
  'second uninstall interruption persisted later phase'
assert_state CURRENT_PARTIAL_UNINSTALL 'multiple interrupted uninstall remains current partial'
(
  # shellcheck disable=SC1091
  source "$TEST_ROOT/install-nobrand.sh"
  trap - ERR
  stub_uninstall_dependencies
  export YES=1
  unset NOBRAND_TEST_INTERRUPT_UNINSTALL_AT
  nobrand_uninstall
  nobrand_uninstall
)
assert_state CLEAN 'continued v3.2.0 partial uninstall reaches CLEAN'
[ ! -e "$NOBRAND_LIFECYCLE_TX_FILE" ] || fail 'successful uninstall retained transaction'
[ ! -e "$NOBRAND_STATE_DIR" ] || fail 'successful uninstall retained state root'
[ ! -e "$NOBRAND_CONFIG_DIR" ] || fail 'successful uninstall retained config root'
[ ! -e "$NOBRAND_LIB_DIR" ] || fail 'successful uninstall retained runtime root'
[ ! -e "$NOBRAND_INSTALL_SCRIPT_PATH" ] || fail 'manager was not removed last'
[ ! -e "$NOBRAND_COMMAND_PATH" ] && [ ! -L "$NOBRAND_COMMAND_PATH" ] \
  || fail 'successful uninstall retained nobrand command'
[ ! -e "$NOBRAND_SHORT_COMMAND_PATH" ] && [ ! -L "$NOBRAND_SHORT_COMMAND_PATH" ] \
  || fail 'successful uninstall retained nb command'

reset_fixture
missing_root="$fixture/probe/nobrand-oneclick"
(
  find() { : >"$fixture/find-was-called"; return 73; }
  nobrand_clear_managed_root "$missing_root"
)
[ ! -e "$fixture/find-was-called" ] || fail 'find ran for an already-absent managed root'
mkdir -p "$missing_root"
printf x >"$missing_root/owned"
set +e
(
  find() { return 73; }
  nobrand_clear_managed_root "$missing_root"
)
find_rc=$?
set -e
[ "$find_rc" -ne 0 ] || fail 'real find failure was hidden'
[ -e "$missing_root/owned" ] || fail 'failed find unexpectedly removed data'
nobrand_clear_managed_root "$missing_root"
nobrand_clear_managed_root "$missing_root"

if command -v flock >/dev/null 2>&1; then
  reset_fixture
  lock_parent="$(dirname "$NOBRAND_LIFECYCLE_LOCK_FILE")"
  hostile_parent="$fixture/hostile-lock-parent"
  rm -rf -- "$lock_parent" "$hostile_parent"
  mkdir -p "$hostile_parent"
  chmod 0700 "$hostile_parent"
  ln -s "$hostile_parent" "$lock_parent"
  NOBRAND_LIFECYCLE_LOCK_HELD=0
  if nb_lifecycle_lock_acquire >/dev/null 2>&1; then
    fail 'lifecycle lock accepted a symlink parent'
  fi
  assert_eq 0 "$NOBRAND_LIFECYCLE_LOCK_HELD" \
    'symlink-parent rejection leaves lock depth clear'
  [ ! -e "$hostile_parent/lifecycle.lock" ] \
    || fail 'symlink-parent rejection created a lock outside the managed path'
  rm -f -- "$lock_parent"
  mkdir -p "$lock_parent"
  chmod 0700 "$lock_parent"

  hostile_file="$fixture/hostile-lock-target"
  printf 'preserve\n' >"$hostile_file"
  ln -s "$hostile_file" "$NOBRAND_LIFECYCLE_LOCK_FILE"
  if nb_lifecycle_lock_acquire >/dev/null 2>&1; then
    fail 'lifecycle lock accepted a symlink file'
  fi
  assert_eq 0 "$NOBRAND_LIFECYCLE_LOCK_HELD" \
    'symlink-file rejection leaves lock depth clear'
  assert_eq preserve "$(tr -d '\r\n' <"$hostile_file")" \
    'symlink-file rejection preserves the external target'

  reset_fixture
  ready="$fixture/lock.ready"
  (
    trap - EXIT HUP INT TERM
    NOBRAND_LIFECYCLE_LOCK_HELD=0
    nb_lifecycle_lock_acquire
    nb_lifecycle_begin repair prepare
    : >"$ready"
    while true; do sleep 0.05; done
  ) &
  holder=$!
  for _ in $(seq 1 200); do [ -e "$ready" ] && break; sleep 0.05; done
  [ -e "$ready" ] || fail 'lock holder did not start'
  NOBRAND_LIFECYCLE_LOCK_HELD=0
  set +e
  nb_lifecycle_lock_acquire >/dev/null 2>&1
  lock_rc=$?
  set -e
  [ "$lock_rc" -ne 0 ] || fail 'concurrent lifecycle lock unexpectedly succeeded'
  kill -TERM "$holder"
  wait "$holder" 2>/dev/null || true
  assert_eq repair "$(nb_lifecycle_field OPERATION)" \
    'crashed lock holder preserves transaction operation'
  assert_eq in-progress "$(nb_lifecycle_field STATUS)" \
    'crashed lock holder preserves recovery transaction'
  NOBRAND_LIFECYCLE_LOCK_HELD=0
  lock_reacquired=0
  for ((attempt = 0; attempt < 40; attempt++)); do
    if nb_lifecycle_lock_acquire >/dev/null 2>&1; then
      lock_reacquired=1
      break
    fi
    sleep 0.05
  done
  [ "$lock_reacquired" -eq 1 ] || fail 'stale lifecycle lock did not recover after holder exit'
  nb_lifecycle_lock_release

  run_lifecycle_signal_interruption() {
    local operation="$1" signal="$2" expected_rc="$3" expected_state=""
    local ready_file signal_log signal_rc interrupted_txid recovered_txid
    local transaction_hash_file transaction_hash_before
    local signal_target signal_attempt
    reset_fixture
    ready_file="$fixture/signal-${operation}-${signal}.ready"
    signal_log="$fixture/signal-${operation}-${signal}.log"
    transaction_hash_file="$fixture/signal-${operation}-${signal}.transaction.sha256"
    set +e
    (
      trap - EXIT HUP INT TERM ERR
      signal_target="$BASHPID"
      (
        for ((signal_attempt = 0; signal_attempt < 200; signal_attempt++)); do
          [ ! -e "$ready_file" ] || break
          sleep 0.01
        done
        if [ -e "$ready_file" ]; then
          kill -s "$signal" "$signal_target"
        else
          kill -TERM "$signal_target"
        fi
      ) &
      NOBRAND_LIFECYCLE_LOCK_HELD=0
      nb_lifecycle_lock_acquire
      nb_lifecycle_lock_acquire
      nb_lifecycle_begin "$operation" prepare
      sha256sum "$NOBRAND_LIFECYCLE_TX_FILE" | awk '{print $1}' \
        >"$transaction_hash_file"
      nb_lifecycle_signal_handlers_install
      : >"$ready_file"
      while true; do sleep 0.05; done
    ) >"$signal_log" 2>&1
    signal_rc=$?
    set -e
    assert_eq "$expected_rc" "$signal_rc" \
      "$signal interrupts active $operation with the conventional exit status"
    assert_contains "$(cat "$signal_log")" '生命周期操作被信号中断' \
      "$signal invokes the production lifecycle interruption handler"
    nb_lifecycle_tx_valid \
      || fail "$signal interruption corrupted the $operation lifecycle transaction"
    assert_eq "$operation" "$(nb_lifecycle_field OPERATION)" \
      "$signal interruption preserves $operation transaction identity"
    assert_eq in-progress "$(nb_lifecycle_field STATUS)" \
      "$signal interruption preserves $operation recovery status"
    assert_eq prepare "$(nb_lifecycle_field LAST_COMPLETED_PHASE)" \
      "$signal interruption preserves $operation recovery phase"
    transaction_hash_before="$(cat "$transaction_hash_file")"
    assert_eq "$transaction_hash_before" \
      "$(sha256sum "$NOBRAND_LIFECYCLE_TX_FILE" | awk '{print $1}')" \
      "$signal interruption preserves exact $operation transaction bytes"
    case "$operation" in
      install) expected_state=CURRENT_PARTIAL_INSTALL ;;
      repair) expected_state=CURRENT_PARTIAL_REPAIR ;;
      uninstall) expected_state=CURRENT_PARTIAL_UNINSTALL ;;
    esac
    assert_state "$expected_state" \
      "$signal interruption keeps $operation classifiable for recovery"
    interrupted_txid="$(nb_lifecycle_field TRANSACTION_ID)"

    NOBRAND_LIFECYCLE_LOCK_HELD=0
    nb_lifecycle_lock_acquire \
      || fail "$signal interruption did not release the $operation process lock"
    nb_lifecycle_begin "$operation" prepare
    recovered_txid="$(nb_lifecycle_field TRANSACTION_ID)"
    assert_eq "$interrupted_txid" "$recovered_txid" \
      "$signal recovery resumes the existing $operation transaction"
    case "$operation" in
      install|repair)
        write_schema
        write_manager "$SCRIPT_VERSION"
        nb_lifecycle_complete "$operation"
        expected_state=CURRENT_COMPLETE
        ;;
      uninstall)
        nb_lifecycle_clear
        expected_state=CLEAN
        ;;
    esac
    nb_lifecycle_lock_release
    assert_state "$expected_state" \
      "$signal-interrupted $operation transaction can converge"
  }

  for lifecycle_signal_operation in install repair uninstall; do
    run_lifecycle_signal_interruption "$lifecycle_signal_operation" INT 130
    run_lifecycle_signal_interruption "$lifecycle_signal_operation" TERM 143
  done
  printf 'SIGNAL_INTERRUPTION_RECOVERY=PASS\n'
else
  printf '[SKIP] flock concurrency and signal recovery checks (flock unavailable)\n'
fi

grep -Fq 'nohup "$script" 7>&- >/dev/null 2>&1 &' \
  "$TEST_ROOT/src/61-ssh-tunnel.sh" \
  || fail 'SSH watchdog can inherit the lifecycle lock'
grep -Fq '"$binary" -c "$config" 7>&- >"$log" 2>&1 &' \
  "$TEST_ROOT/src/22-platform-snell.sh" \
  || fail 'Snell probe daemon can inherit the lifecycle lock'
grep -Fq '"$NOBRAND_REALM_BIN" -c "$config" 7>&- >/dev/null 2>&1 &' \
  "$TEST_ROOT/src/62-forward.sh" \
  || fail 'Realm probe daemon can inherit the lifecycle lock'

standard_impl_checkpoint_count="$(grep -F -c \
  'nb_lifecycle_checkpoint "$NOBRAND_LIFECYCLE_OPERATION"' \
  "$TEST_ROOT/src/80-lifecycle.sh")"
standard_final_checkpoint_count="$(grep -F -c \
  'nb_lifecycle_checkpoint "$operation" ready-to-validate' \
  "$TEST_ROOT/src/80-lifecycle.sh")"
standard_source_checkpoint_count=$((
  standard_impl_checkpoint_count + standard_final_checkpoint_count
))
partial_uninstall_repair_source_checkpoint_count="$(grep -E -c \
  'nb_lifecycle_checkpoint (repair|"\$operation") partial-uninstall-' \
  "$TEST_ROOT/src/80-lifecycle.sh")"
repair_source_checkpoint_count=$((
  standard_source_checkpoint_count + partial_uninstall_repair_source_checkpoint_count
))
uninstall_source_checkpoint_count="$(grep -F -c \
  'nb_lifecycle_checkpoint uninstall' "$TEST_ROOT/src/18-core-nodes.sh")"
assert_eq "$standard_source_checkpoint_count" "$INSTALL_INTERRUPT_EXERCISED_COUNT" \
  'every exposed standard install checkpoint was exercised'
assert_eq "$partial_uninstall_repair_source_checkpoint_count" \
  "$PARTIAL_UNINSTALL_REPAIR_INTERRUPT_EXERCISED_COUNT" \
  'every exposed partial-uninstall repair checkpoint was exercised'
assert_eq "$repair_source_checkpoint_count" "$REPAIR_INTERRUPT_EXERCISED_COUNT" \
  'every exposed installer repair checkpoint was exercised'
assert_eq "$uninstall_source_checkpoint_count" "$UNINSTALL_INTERRUPT_EXERCISED_COUNT" \
  'every exposed full-uninstall checkpoint was exercised'
printf 'INSTALL_INTERRUPT_CHECKPOINT_COUNT=%s\n' "$INSTALL_INTERRUPT_EXERCISED_COUNT"
printf 'REPAIR_INTERRUPT_CHECKPOINT_COUNT=%s\n' "$REPAIR_INTERRUPT_EXERCISED_COUNT"
printf 'UNINSTALL_INTERRUPT_CHECKPOINT_COUNT=%s\n' "$UNINSTALL_INTERRUPT_EXERCISED_COUNT"
printf 'INSTALL_INTERRUPT_RERUN_ALL_PASS=PASS\n'
printf 'REPAIR_INTERRUPT_RERUN_ALL_PASS=PASS\n'
printf 'UNINSTALL_INTERRUPT_RERUN_ALL_PASS=PASS\n'
printf 'MULTIPLE_INTERRUPTION_RECOVERY=PASS\n'
printf 'COMPLETED_INSTALL_REPEATED_RERUN=PASS\n'

pass 'lifecycle classifier, recovery transactions, missing-root cleanup, and exact v3.2.0 regression'
