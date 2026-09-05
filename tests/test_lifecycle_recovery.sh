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
source "$TEST_ROOT/src/90-ui.sh"
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
  NOBRAND_LIFECYCLE_SCOPE=""
  NOBRAND_LIFECYCLE_MUTATION_STARTED=0
  NOBRAND_LIFECYCLE_LOCK_HELD=0
  ACTION=""
  YES=0
  unset NOBRAND_TEST_INTERRUPT_INSTALL_AT NOBRAND_TEST_INTERRUPT_REPAIR_AT \
    NOBRAND_TEST_INTERRUPT_CONFIGURE_AT NOBRAND_TEST_INTERRUPT_UNINSTALL_AT \
    NOBRAND_RECOVERY_EXPECTED_SCOPE NOBRAND_PROTOCOL_EXPLICIT_RETRY_SCOPE \
    NOBRAND_PROTOCOL_CALLBACK_ATTEMPT_MUTATION \
    NOBRAND_RECOVERY_EXPECTED_STATE NOBRAND_RECOVERY_EXPECTED_TX_PRESENT \
    NOBRAND_RECOVERY_EXPECTED_TX_STATUS NOBRAND_RECOVERY_EXPECTED_TX_ID \
    NOBRAND_RECOVERY_EXPECTED_TX_RECORD
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

write_manager_command_chain() {
  mkdir -p "$(dirname "$NOBRAND_COMMAND_PATH")" \
    "$(dirname "$NOBRAND_SHORT_COMMAND_PATH")"
  rm -f -- "$NOBRAND_COMMAND_PATH" "$NOBRAND_SHORT_COMMAND_PATH"
  ln -s "$NOBRAND_INSTALL_SCRIPT_PATH" "$NOBRAND_COMMAND_PATH"
  ln -s "$NOBRAND_COMMAND_PATH" "$NOBRAND_SHORT_COMMAND_PATH"
}

write_complete_manager() {
  write_manager "$1"
  write_manager_command_chain
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

write_lifecycle_v1_fixture() {
  local operation="${1:-install}" phase="${2:-ready-to-validate}"
  local status="${3:-in-progress}"
  mkdir -p "$NOBRAND_LIFECYCLE_DIR"
  chmod 0700 "$NOBRAND_LIFECYCLE_DIR"
  printf '%s\n' \
    'FORMAT=nobrand-lifecycle-v1' \
    "OPERATION=${operation}" \
    "STATUS=${status}" \
    'MANAGER_VERSION=3.2.1' \
    'SCHEMA_GENERATION=3' \
    'TRANSACTION_ID=12345678' \
    'STARTED_AT=2026-01-01T00:00:00Z' \
    "LAST_COMPLETED_PHASE=${phase}" \
    'MIERU_OWNED=0' \
    'MIERU_PRESERVE_PACKAGE=0' \
    'MIERU_PRESERVE_USER=0' \
    'MIERU_PRESERVE_GROUP=0' \
    'MIERU_PRESERVE_SHARED=0' \
    >"$NOBRAND_LIFECYCLE_TX_FILE"
  chmod 0600 "$NOBRAND_LIFECYCLE_TX_FILE"
}

assert_lifecycle_record_rejected() {
  local label="$1"
  if nb_lifecycle_tx_valid; then
    fail "$label was accepted as valid lifecycle metadata"
  fi
  assert_state AMBIGUOUS_OR_FOREIGN "$label fails closed during classification"
}

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
write_complete_manager 3.2.0
assert_state CURRENT_COMPLETE 'schema v3 plus compatible 3.2 manager command chain'

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

# Public v3.2.1 lifecycle-v1 metadata is a fixed 13-field compatibility
# format. Scope and mutation state are inferred only for that exact format;
# extending, truncating, or duplicating it must fail closed.
reset_fixture
write_lifecycle_v1_fixture install ready-to-validate
assert_eq 13 "$(wc -l <"$NOBRAND_LIFECYCLE_TX_FILE" | tr -d '[:space:]')" \
  'lifecycle-v1 exact field count'
nb_lifecycle_tx_valid || fail 'exact public lifecycle-v1 fixture was rejected'
assert_eq '' "$(nb_lifecycle_field SCOPE)" 'lifecycle-v1 stores no scope field'
assert_eq '' "$(nb_lifecycle_field MUTATION_STARTED)" \
  'lifecycle-v1 stores no mutation field'
assert_eq mieru "$(nb_lifecycle_scope)" 'lifecycle-v1 install infers Mieru scope'
assert_eq 1 "$(nb_lifecycle_mutation_started)" \
  'in-progress lifecycle-v1 conservatively infers mutation'
assert_state CURRENT_PARTIAL_INSTALL 'exact lifecycle-v1 install remains recoverable'
v1_valid_record="$fixture/lifecycle-v1-valid.env"
cp "$NOBRAND_LIFECYCLE_TX_FILE" "$v1_valid_record"

cp "$v1_valid_record" "$NOBRAND_LIFECYCLE_TX_FILE"
printf '%s\n' 'SCOPE=mieru' >>"$NOBRAND_LIFECYCLE_TX_FILE"
assert_lifecycle_record_rejected 'lifecycle-v1 record with a v2 scope extension'

cp "$v1_valid_record" "$NOBRAND_LIFECYCLE_TX_FILE"
printf '%s\n' 'STATUS=in-progress' >>"$NOBRAND_LIFECYCLE_TX_FILE"
assert_lifecycle_record_rejected 'lifecycle-v1 record with a duplicate field'

awk -F= '$1 != "MIERU_PRESERVE_SHARED"' "$v1_valid_record" \
  >"$NOBRAND_LIFECYCLE_TX_FILE"
assert_lifecycle_record_rejected 'lifecycle-v1 record with a missing field'

awk -F= 'BEGIN { OFS="=" } $1 == "OPERATION" { $2="configure" } { print }' \
  "$v1_valid_record" >"$NOBRAND_LIFECYCLE_TX_FILE"
assert_lifecycle_record_rejected 'lifecycle-v1 record with a v2-only operation'

reset_fixture
write_lifecycle_v1_fixture repair partial-uninstall-ready-to-validate
nb_lifecycle_tx_valid || fail 'lifecycle-v1 partial-uninstall repair fixture was rejected'
assert_eq global "$(nb_lifecycle_scope)" \
  'lifecycle-v1 partial-uninstall repair infers global scope'
assert_eq 1 "$(nb_lifecycle_mutation_started)" \
  'lifecycle-v1 partial-uninstall repair conservatively infers mutation'
assert_state CURRENT_PARTIAL_REPAIR \
  'lifecycle-v1 partial-uninstall repair remains globally recoverable'
printf 'LIFECYCLE_V1_COMPATIBILITY=PASS\n'

# Protocol mutation hooks are keyed to an active exact-scope transaction, not
# to the presence of a manager-session flag. Outside a transaction they remain
# no-ops so shared runtime upgrade helpers cannot fail.
reset_fixture
unset NOBRAND_MANAGER_SESSION_ACTIVE NOBRAND_PROTOCOL_CALLBACK_ATTEMPT_MUTATION
nb_lifecycle_mark_protocol_mutation_started tuic \
  || fail 'inactive protocol mutation hook was not a no-op'
[ ! -e "$NOBRAND_LIFECYCLE_TX_FILE" ] \
  || fail 'inactive protocol mutation hook created lifecycle metadata'
[ -z "${NOBRAND_PROTOCOL_CALLBACK_ATTEMPT_MUTATION:-}" ] \
  || fail 'inactive protocol mutation hook fabricated attempt proof'
nb_lifecycle_begin install prepare 0 0 0 0 0 0 tuic
nb_lifecycle_mark_protocol_mutation_started tuic \
  || fail 'active direct-wrapper mutation hook failed without manager-session flag'
assert_eq 1 "$(nb_lifecycle_mutation_started)" \
  'active direct-wrapper mutation hook records durable boundary'
assert_eq 1 "$NOBRAND_PROTOCOL_CALLBACK_ATTEMPT_MUTATION" \
  'active direct-wrapper mutation hook records attempt-local proof'

# Shared runtime helpers use the currently active lifecycle scope. During
# global repair they must mark repair:global rather than rejecting the helper
# because its ordinary component owner is TUIC/Snell/Xray.
reset_fixture
nb_lifecycle_begin repair prepare 0 0 0 0 0 0 global
nb_lifecycle_mark_protocol_mutation_started "${NOBRAND_LIFECYCLE_SCOPE:-tuic}" \
  || fail 'shared-runtime mutation hook rejected active repair:global scope'
assert_eq 1 "$(nb_lifecycle_mutation_started)" \
  'shared-runtime mutation hook records repair:global durable boundary'
assert_eq global "$(nb_lifecycle_scope)" \
  'shared-runtime mutation hook preserves repair:global scope'
printf 'PROTOCOL_MUTATION_HOOK_CONTEXT=PASS\n'

# TUIC owns an outer runtime snapshot before entering its instance lock. Every
# post-lock preparation failure must release the lock and remove both that
# snapshot and any candidate config/state files.
run_tuic_install_precommit_failure() {
  local failure_case="$1" failure_rc
  reset_fixture
  (
    # shellcheck disable=SC1091
    source "$TEST_ROOT/src/59-tuic.sh"
    tuic_admin_lock_depth=0
    tuic_rollback_calls=0
    tuic_runtime_snapshot="$fixture/tuic-${failure_case}-runtime-snapshot"

    require_root() { return 0; }
    require_linux() { return 0; }
    nobrand_prepare_common() { return 0; }
    # Consumed indirectly by install_tuic() from the sourced module.
    # shellcheck disable=SC2034,SC2100
    tuic_collect_install_requests() {
      PORT=24443
      TUIC_CHANNEL=stable
      TUIC_VERSION=''
      TUIC_USER=fixture-user
      TUIC_NAME=fixture-instance
      TUIC_SNI=fixture.invalid
      INGRESS_LISTEN_HOST=127.0.0.1
      ADVERTISE_HOST=198.51.100.10
      ADVERTISE_PORT=24443
      INGRESS_PROFILE_ID=fixture-profile
    }
    mktemp_dir() {
      mkdir -p "$tuic_runtime_snapshot"
      printf '%s' "$tuic_runtime_snapshot"
    }
    mktemp_file() {
      local suffix="${1:-}" temporary output
      temporary="$(mktemp "$fixture/tuic-${failure_case}.XXXXXX")" || return 1
      if [ -n "$suffix" ]; then
        output="${temporary}${suffix}"
        mv "$temporary" "$output" || return 1
      else
        output="$temporary"
      fi
      printf '%s' "$output"
    }
    tuic_snapshot_runtime_files() {
      mkdir -p "$1"
      : >"$1/runtime-marker"
    }
    tuic_prepare_runtime_for_install() { return 0; }
    tuic_runtime_version() { printf '1.11.15'; }
    tuic_generate_instance_id() { printf 't1111111111111111'; }
    tuic_generate_user_id() { printf 'u1111111111111111'; }
    tuic_generate_uuid() { printf '11111111-1111-4111-8111-111111111111'; }
    tuic_generate_password() { printf 'fixture-password'; }
    tuic_user_json() { printf '%s' '{}'; }
    admin_lock_acquire() {
      tuic_admin_lock_depth=$((tuic_admin_lock_depth + 1))
    }
    admin_lock_release() {
      tuic_admin_lock_depth=$((tuic_admin_lock_depth - 1))
      [ "$tuic_admin_lock_depth" -ge 0 ]
    }
    tuic_generate_certificate() {
      [ "$failure_case" != certificate ] || return 1
      printf '%s\n' certificate >"$1"
      printf '%s\n' private-key >"$2"
    }
    tuic_generate_server_config() {
      printf '%s\n' '{}' >"$1"
    }
    tuic_validate_config() { [ "$failure_case" != config-validation ]; }
    nb_endpoint_mode_from_values() { printf custom; }
    tuic_generate_state() {
      printf '%s\n' '{}' >"$1"
    }
    nb_ingress_stamp_state_file() { [ "$failure_case" != state-stamp ]; }
    tuic_install_transaction_rollback() {
      tuic_rollback_calls=$((tuic_rollback_calls + 1))
      # Both roots are fixture-bound above; the instance ID is generated by
      # this fixture and is intentionally passed through the production call.
      # shellcheck disable=SC2115
      rm -rf -- "$NOBRAND_TUIC_STATE_DIR/$1" "$NOBRAND_TUIC_CONFIG_DIR/$1"
    }

    set +e
    install_tuic
    failure_rc=$?
    set -e
    [ "$failure_rc" -ne 0 ] \
      || fail "TUIC ${failure_case} failure fixture unexpectedly succeeded"
    assert_eq 0 "$tuic_admin_lock_depth" \
      "TUIC ${failure_case} failure releases admin lock"
    assert_eq 1 "$tuic_rollback_calls" \
      "TUIC ${failure_case} failure invokes rollback exactly once"
    [ ! -e "$tuic_runtime_snapshot" ] \
      || fail "TUIC ${failure_case} failure retained runtime snapshot"
    [ -z "$(find "$fixture" -maxdepth 1 -name "tuic-${failure_case}.*" -print -quit)" ] \
      || fail "TUIC ${failure_case} failure retained candidate temp files"
  )
}

run_tuic_install_precommit_failure certificate
run_tuic_install_precommit_failure config-validation
run_tuic_install_precommit_failure state-stamp
printf 'TUIC_INSTALL_PRECOMMIT_CLEANUP=PASS\n'

# lifecycle-v2 is likewise a closed 15-field schema. These corruptions cover
# unknown, duplicate, missing, and invalid-valued fields independently.
reset_fixture
nb_lifecycle_begin install prepare 0 0 0 0 0 0 snell
nb_lifecycle_tx_valid || fail 'valid lifecycle-v2 fixture was rejected'
v2_valid_record="$fixture/lifecycle-v2-valid.env"
cp "$NOBRAND_LIFECYCLE_TX_FILE" "$v2_valid_record"

cp "$v2_valid_record" "$NOBRAND_LIFECYCLE_TX_FILE"
printf '%s\n' 'UNKNOWN_FIELD=1' >>"$NOBRAND_LIFECYCLE_TX_FILE"
assert_lifecycle_record_rejected 'lifecycle-v2 record with an unknown field'

cp "$v2_valid_record" "$NOBRAND_LIFECYCLE_TX_FILE"
printf '%s\n' 'SCOPE=snell' >>"$NOBRAND_LIFECYCLE_TX_FILE"
assert_lifecycle_record_rejected 'lifecycle-v2 record with a duplicate field'

awk -F= '$1 != "MUTATION_STARTED"' "$v2_valid_record" \
  >"$NOBRAND_LIFECYCLE_TX_FILE"
assert_lifecycle_record_rejected 'lifecycle-v2 record with a missing field'

awk -F= 'BEGIN { OFS="=" } $1 == "MUTATION_STARTED" { $2="maybe" } { print }' \
  "$v2_valid_record" >"$NOBRAND_LIFECYCLE_TX_FILE"
assert_lifecycle_record_rejected 'lifecycle-v2 record with invalid mutation state'
printf 'LIFECYCLE_MALFORMED_FAIL_CLOSED=PASS\n'

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
assert_eq 15 "$(wc -l <"$NOBRAND_LIFECYCLE_TX_FILE" | tr -d '[:space:]')" \
  'transaction field count'
assert_eq nobrand-lifecycle-v2 "$(nb_lifecycle_field FORMAT)" 'transaction format'
assert_eq mieru "$(nb_lifecycle_scope)" 'default v2 transaction scope'
assert_eq 0 "$(nb_lifecycle_mutation_started)" 'transaction starts before mutation'
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
  do_install_impl() {
    nb_lifecycle_mark_protocol_mutation_started mieru
    return 41
  }
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
    write_complete_manager "$SCRIPT_VERSION"
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
  if [ "$phase" = state-layout ]; then
    [ ! -e "$NOBRAND_LIFECYCLE_TX_FILE" ] \
      || fail 'pre-mutation state-layout interruption retained lifecycle metadata'
    assert_state CURRENT_PARTIAL_INSTALL \
      'pre-mutation state-layout interruption leaves manager-layout evidence only'
    (
      stub_standard_lifecycle_install_dependencies
      nobrand_install_manager_script() { write_complete_manager "$SCRIPT_VERSION"; }
      nobrand_manager_installation_valid() { return 0; }
      nobrand_manager_bootstrap >/dev/null
    )
    assert_state CURRENT_COMPLETE \
      'manager bootstrap reconciles pre-mutation state-layout residue'
    (
      stub_standard_lifecycle_install_dependencies
      fresh_mieru_state_ready=0
      mita_v3_install_state_valid() { [ "$fresh_mieru_state_ready" -eq 1 ]; }
      install_fresh_isolated() {
        fresh_mieru_state_ready=1
        write_schema
        write_complete_manager "$SCRIPT_VERSION"
      }
      YES=1
      unset NOBRAND_TEST_INTERRUPT_INSTALL_AT
      do_install >/dev/null
    )
    assert_eq install "$(nb_lifecycle_field OPERATION)" \
      'explicit install after manager recovery uses install scope'
    assert_eq complete "$(nb_lifecycle_field STATUS)" \
      'explicit install after manager recovery completes'
    assert_state CURRENT_COMPLETE \
      'explicit install after pre-mutation interruption converges'
    INSTALL_INTERRUPT_EXERCISED_COUNT=$((INSTALL_INTERRUPT_EXERCISED_COUNT + 1))
    return 0
  fi
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
    if [ "$phase" = runtime-ready ]; then
      NOBRAND_PROTOCOL_EXPLICIT_RETRY_SCOPE=mieru
    fi
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
  write_complete_manager "$SCRIPT_VERSION"
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
  if [ "$phase" = state-layout ]; then
    [ ! -e "$NOBRAND_LIFECYCLE_TX_FILE" ] \
      || fail 'pre-mutation repair state-layout interruption retained lifecycle metadata'
    assert_eq "$repair_state_hash" "$(sha256sum "$NOBRAND_STATE_DIR/repair-preserve")" \
      'pre-mutation repair state-layout interruption preserves state'
    assert_state CURRENT_COMPLETE \
      'pre-mutation repair state-layout interruption restores complete state'
    (
      stub_standard_lifecycle_install_dependencies
      YES=1
      unset NOBRAND_TEST_INTERRUPT_REPAIR_AT
      do_install >/dev/null
    )
    assert_eq repair "$(nb_lifecycle_field OPERATION)" \
      'explicit repair after pre-mutation interruption uses repair operation'
    assert_eq complete "$(nb_lifecycle_field STATUS)" \
      'explicit repair after pre-mutation interruption completes'
    assert_eq "$repair_state_hash" "$(sha256sum "$NOBRAND_STATE_DIR/repair-preserve")" \
      'explicit repair after pre-mutation interruption preserves state'
    assert_state CURRENT_COMPLETE \
      'explicit repair after pre-mutation interruption converges'
    REPAIR_INTERRUPT_EXERCISED_COUNT=$((REPAIR_INTERRUPT_EXERCISED_COUNT + 1))
    return 0
  fi
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
    if [ "$phase" = runtime-ready ]; then
      NOBRAND_PROTOCOL_EXPLICIT_RETRY_SCOPE=mieru
    fi
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
  install_self_script() { write_complete_manager "$SCRIPT_VERSION"; }
  do_install_impl() {
    : >"$NOBRAND_STATE_DIR/unexpected-fresh-install"
    return 99
  }
  nobrand_restore_protocol_runtimes() { return 0; }
  nobrand_start_enabled_services() { return 0; }
  nobrand_doctor() { return 0; }
}

# Reclassifying a partial global uninstall as repair is reversible until the
# repair mutation marker is durable. A failed marker must restore the original
# uninstall transaction byte-for-byte and must not enter either repair path.
reset_fixture
write_schema
write_manager "$SCRIPT_VERSION"
mkdir -p "$(dirname "$NOBRAND_FORWARD_STATE_FILE")"
printf '%s\n' '{"format":"partial-uninstall-marker-fixture"}' \
  >"$NOBRAND_FORWARD_STATE_FILE"
cp "$NOBRAND_FORWARD_STATE_FILE" \
  "$fixture/partial-uninstall-marker-failure.state.expected"
nb_lifecycle_begin uninstall prepare
cp "$NOBRAND_LIFECYCLE_TX_FILE" \
  "$fixture/partial-uninstall-marker-failure.transaction.expected"
(
  stub_partial_uninstall_repair_dependencies
  nb_lifecycle_mark_mutation_started() { return 73; }
  nb_reconcile_partial_uninstall() {
    : >"$fixture/partial-uninstall-marker-failure.unexpected-reconcile"
    return 98
  }
  NOBRAND_LIFECYCLE_LOCK_HELD=0
  YES=1
  set +e
  do_install >/dev/null 2>&1
  partial_uninstall_marker_failure_rc=$?
  set -e
  assert_eq 73 "$partial_uninstall_marker_failure_rc" \
    'partial-uninstall repair mutation-marker failure propagates'
  assert_eq 0 "$NOBRAND_LIFECYCLE_LOCK_HELD" \
    'partial-uninstall repair mutation-marker failure balances lifecycle lock'
)
cmp -s "$fixture/partial-uninstall-marker-failure.transaction.expected" \
  "$NOBRAND_LIFECYCLE_TX_FILE" \
  || fail 'partial-uninstall repair mutation-marker failure changed original transaction bytes'
cmp -s "$fixture/partial-uninstall-marker-failure.state.expected" \
  "$NOBRAND_FORWARD_STATE_FILE" \
  || fail 'partial-uninstall repair mutation-marker failure changed authoritative state bytes'
[ ! -e "$fixture/partial-uninstall-marker-failure.unexpected-reconcile" ] \
  || fail 'partial-uninstall repair mutation-marker failure ran reconciliation'
[ ! -e "$NOBRAND_STATE_DIR/unexpected-fresh-install" ] \
  || fail 'partial-uninstall repair mutation-marker failure ran fresh install callback'
assert_state CURRENT_PARTIAL_UNINSTALL \
  'partial-uninstall repair mutation-marker failure restores original classification'
printf 'PARTIAL_UNINSTALL_PREMUTATION_RESTORE=PASS\n'

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

  NOBRAND_PROTOCOL_EXPLICIT_RETRY_SCOPE=mieru
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
    write_complete_manager "$SCRIPT_VERSION"
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
write_complete_manager "$SCRIPT_VERSION"
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
  install_self_script() { write_complete_manager "$SCRIPT_VERSION"; }
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

# Recovery selection must be driven by the durable operation scope. Exercise
# manager, Ingress, Mieru, a second protocol, Forward, and global recovery
# independently so no route can silently fall back to the historical Mieru
# installer default.
reset_fixture
nb_lifecycle_begin install prepare 0 0 0 0 0 0 manager
manager_route_hash="$(sha256sum "$NOBRAND_LIFECYCLE_TX_FILE")"
nobrand_set_scoped_recovery_action CURRENT_PARTIAL_INSTALL
assert_eq manager "$(nobrand_recovery_scope CURRENT_PARTIAL_INSTALL)" \
  'manager recovery reads durable manager scope'
assert_eq nobrand-manager-bootstrap "$ACTION" 'manager recovery action'
assert_eq "$manager_route_hash" "$(sha256sum "$NOBRAND_LIFECYCLE_TX_FILE")" \
  'manager route selection does not rewrite lifecycle metadata'
printf 'MANAGER_RECOVERY_SCOPE_GATE=PASS\n'

# Manager residue does not necessarily retain an active manager transaction.
# Bind either exact absence or an exact completed lifecycle record at selection,
# repair only that same partial state under lock, and reach the ordinary menu.
for manager_residue_tx in absent complete; do
  reset_fixture
  write_schema
  if [ "$manager_residue_tx" = complete ]; then
    nb_lifecycle_begin install prepare 0 0 0 0 0 0 snell
    nb_lifecycle_mark_mutation_started
    nb_lifecycle_complete install
  fi
  assert_state CURRENT_PARTIAL_INSTALL \
    "${manager_residue_tx} manager residue starts partial"
  (
    id() { [ "${1:-}" = -u ] && printf 0; }
    require_root() { return 0; }
    require_linux() { return 0; }
    detect_pkg_manager() { printf deb; }
    ensure_management_dependencies() { return 0; }
    nb_lifecycle_lock_acquire() { NOBRAND_LIFECYCLE_LOCK_HELD=$((NOBRAND_LIFECYCLE_LOCK_HELD + 1)); }
    nb_lifecycle_lock_release() { NOBRAND_LIFECYCLE_LOCK_HELD=$((NOBRAND_LIFECYCLE_LOCK_HELD - 1)); }
    read_tty() { printf -v "$1" 1; }
    ensure_manager_state_layout() { return 0; }
    nobrand_install_manager_script() {
      printf 'install\n' >>"$fixture/manager-residue-${manager_residue_tx}.install"
      write_complete_manager "$SCRIPT_VERSION"
    }
    nobrand_manager_installation_valid() { return 0; }
    nb_lifecycle_validate_manager_repair() { return 0; }
    nobrand_menu_loop() { : >"$fixture/manager-residue-${manager_residue_tx}.menu"; }
    ACTION=""
    NOBRAND_LIFECYCLE_LOCK_HELD=0
    main >/dev/null
    assert_eq 0 "$NOBRAND_LIFECYCLE_LOCK_HELD" \
      "${manager_residue_tx} manager recovery balances lifecycle lock"
  )
  assert_eq 1 "$(wc -l <"$fixture/manager-residue-${manager_residue_tx}.install" | tr -d '[:space:]')" \
    "${manager_residue_tx} manager residue installs manager exactly once"
  [ -e "$fixture/manager-residue-${manager_residue_tx}.menu" ] \
    || fail "${manager_residue_tx} manager residue did not reach menu"
  assert_state CURRENT_COMPLETE \
    "${manager_residue_tx} manager residue converges to current complete"
  assert_eq repair "$(nb_lifecycle_field OPERATION)" \
    "${manager_residue_tx} manager residue records repair"
  assert_eq manager "$(nb_lifecycle_scope)" \
    "${manager_residue_tx} manager residue records manager scope"
done
printf 'MANAGER_RESIDUE_MAIN_RECOVERY=PASS\n'

# The no-argument recovery prompt is intentionally outside the manager lock.
# Reauthenticate its selected manager transaction after acquiring that lock so
# a concurrent CLEAN transition or new component transaction cannot turn the
# stale choice into a fresh manager install.
for manager_race_mode in clean changed-scope; do
  reset_fixture
  nb_lifecycle_begin install prepare 0 0 0 0 0 0 manager
  nobrand_set_scoped_recovery_action CURRENT_PARTIAL_INSTALL
  manager_race_log="$fixture/manager-race-${manager_race_mode}.log"
  manager_race_expected="$fixture/manager-race-${manager_race_mode}.expected"
  (
    require_root() { return 0; }
    require_linux() { return 0; }
    detect_pkg_manager() { printf deb; }
    ensure_management_dependencies() { return 0; }
    manager_race_applied=0
    nb_lifecycle_lock_acquire() {
      fake_lifecycle_lock_acquire
      if [ "$manager_race_applied" -eq 0 ]; then
        manager_race_applied=1
        nb_lifecycle_clear
        if [ "$manager_race_mode" = changed-scope ]; then
          nb_lifecycle_begin configure prepare 0 0 0 0 0 0 ingress
          cp "$NOBRAND_LIFECYCLE_TX_FILE" "$manager_race_expected"
        fi
      fi
    }
    nb_lifecycle_lock_release() { fake_lifecycle_lock_release; }
    ensure_manager_state_layout() { printf 'layout\n' >>"$manager_race_log"; }
    nobrand_install_manager_script() { printf 'install\n' >>"$manager_race_log"; }
    nobrand_manager_installation_valid() { return 1; }
    set +e
    nobrand_manager_bootstrap >/dev/null 2>&1
    manager_race_rc=$?
    set -e
    [ "$manager_race_rc" -ne 0 ] \
      || fail "stale manager recovery accepted ${manager_race_mode} state"
    assert_eq 0 "$NOBRAND_LIFECYCLE_LOCK_HELD" \
      "stale manager ${manager_race_mode} refusal balances lifecycle lock"
  )
  [ ! -e "$manager_race_log" ] \
    || fail "stale manager ${manager_race_mode} recovery installed manager resources"
  if [ "$manager_race_mode" = clean ]; then
    [ ! -e "$NOBRAND_LIFECYCLE_TX_FILE" ] \
      || fail 'stale manager CLEAN recovery created replacement metadata'
  else
    cmp -s "$manager_race_expected" "$NOBRAND_LIFECYCLE_TX_FILE" \
      || fail 'stale manager recovery changed the concurrent Ingress transaction bytes'
  fi
done
printf 'MANAGER_RECOVERY_TOCTOU_GUARD=PASS\n'

# A manager-residue choice made with no lifecycle file must also reject newly
# ambiguous metadata that appears before the bootstrap acquires its lock.
reset_fixture
write_schema
nobrand_set_scoped_recovery_action CURRENT_PARTIAL_INSTALL
manager_residue_schema_hash="$(sha256sum "$NOBRAND_REGISTRY_FILE")"
manager_residue_ambiguous_expected="$fixture/manager-residue-ambiguous.expected"
printf '%s\n' 'FOREIGN=manager-race' >"$manager_residue_ambiguous_expected"
(
  require_root() { return 0; }
  require_linux() { return 0; }
  detect_pkg_manager() { printf deb; }
  ensure_management_dependencies() { return 0; }
  nb_lifecycle_lock_acquire() {
    fake_lifecycle_lock_acquire
    mkdir -p "$NOBRAND_LIFECYCLE_DIR"
    cp "$manager_residue_ambiguous_expected" "$NOBRAND_LIFECYCLE_TX_FILE"
  }
  nb_lifecycle_lock_release() { fake_lifecycle_lock_release; }
  ensure_manager_state_layout() { : >"$fixture/manager-residue-ambiguous.layout"; }
  nobrand_install_manager_script() { : >"$fixture/manager-residue-ambiguous.install"; }
  NOBRAND_LIFECYCLE_LOCK_HELD=0
  set +e
  nobrand_manager_bootstrap >/dev/null 2>&1
  manager_residue_ambiguous_rc=$?
  set -e
  [ "$manager_residue_ambiguous_rc" -ne 0 ] \
    || fail 'stale manager-residue recovery accepted newly ambiguous metadata'
  assert_eq 0 "$NOBRAND_LIFECYCLE_LOCK_HELD" \
    'ambiguous manager-residue race balances lifecycle lock'
)
cmp -s "$manager_residue_ambiguous_expected" "$NOBRAND_LIFECYCLE_TX_FILE" \
  || fail 'ambiguous manager-residue race changed foreign metadata'
assert_eq "$manager_residue_schema_hash" "$(sha256sum "$NOBRAND_REGISTRY_FILE")" \
  'ambiguous manager-residue race preserves schema bytes'
[ ! -e "$fixture/manager-residue-ambiguous.layout" ] \
  && [ ! -e "$fixture/manager-residue-ambiguous.install" ] \
  || fail 'ambiguous manager-residue race mutated manager layout'
printf 'MANAGER_RESIDUE_TOCTOU_GUARD=PASS\n'

# Beginning manager repair over a completed protocol record is reversible until
# the manager mutation marker itself is durable.
reset_fixture
write_schema
nb_lifecycle_begin install prepare 0 0 0 0 0 0 snell
nb_lifecycle_mark_mutation_started
nb_lifecycle_complete install
cp "$NOBRAND_LIFECYCLE_TX_FILE" "$fixture/manager-marker-failure.expected"
nobrand_set_scoped_recovery_action CURRENT_PARTIAL_INSTALL
(
  require_root() { return 0; }
  require_linux() { return 0; }
  detect_pkg_manager() { printf deb; }
  ensure_management_dependencies() { return 0; }
  nb_lifecycle_lock_acquire() { NOBRAND_LIFECYCLE_LOCK_HELD=$((NOBRAND_LIFECYCLE_LOCK_HELD + 1)); }
  nb_lifecycle_lock_release() { NOBRAND_LIFECYCLE_LOCK_HELD=$((NOBRAND_LIFECYCLE_LOCK_HELD - 1)); }
  nb_lifecycle_mark_mutation_started() { return 72; }
  ensure_manager_state_layout() { : >"$fixture/manager-marker-failure.unexpected-layout"; }
  nobrand_install_manager_script() { : >"$fixture/manager-marker-failure.unexpected-install"; }
  NOBRAND_LIFECYCLE_LOCK_HELD=0
  set +e
  nobrand_manager_bootstrap >/dev/null 2>&1
  manager_marker_failure_rc=$?
  set -e
  assert_eq 72 "$manager_marker_failure_rc" \
    'manager mutation-marker failure propagates'
  assert_eq 0 "$NOBRAND_LIFECYCLE_LOCK_HELD" \
    'manager mutation-marker failure balances lifecycle lock'
)
cmp -s "$fixture/manager-marker-failure.expected" "$NOBRAND_LIFECYCLE_TX_FILE" \
  || fail 'manager mutation-marker failure changed prior completed metadata'
[ ! -e "$fixture/manager-marker-failure.unexpected-layout" ] \
  && [ ! -e "$fixture/manager-marker-failure.unexpected-install" ] \
  || fail 'manager mutation-marker failure changed manager resources'
printf 'MANAGER_PREMUTATION_RESTORE=PASS\n'

reset_fixture
nb_lifecycle_begin configure prepare 0 0 0 0 0 0 ingress
ingress_route_hash="$(sha256sum "$NOBRAND_LIFECYCLE_TX_FILE")"
nobrand_set_scoped_recovery_action CURRENT_PARTIAL_CONFIGURE
assert_eq ingress "$(nobrand_recovery_scope CURRENT_PARTIAL_CONFIGURE)" \
  'Ingress recovery reads durable Ingress scope'
assert_eq nobrand-ingress-recover "$ACTION" 'Ingress recovery action'
assert_eq "$ingress_route_hash" "$(sha256sum "$NOBRAND_LIFECYCLE_TX_FILE")" \
  'Ingress route selection does not rewrite lifecycle metadata'
printf 'INGRESS_RECOVERY_SCOPE_GATE=PASS\n'

reset_fixture
nb_lifecycle_begin install prepare 0 0 0 0 0 0 mieru
nobrand_set_scoped_recovery_action CURRENT_PARTIAL_INSTALL
assert_eq mieru "$(nobrand_recovery_scope CURRENT_PARTIAL_INSTALL)" \
  'Mieru recovery reads durable Mieru scope'
assert_eq install "$ACTION" 'Mieru recovery action'
printf 'MIERU_RECOVERY_SCOPE_GATE=PASS\n'

reset_fixture
unset TUIC_ACTION
nb_lifecycle_begin install prepare 0 0 0 0 0 0 tuic
nobrand_set_scoped_recovery_action CURRENT_PARTIAL_INSTALL
assert_eq tuic "$(nobrand_recovery_scope CURRENT_PARTIAL_INSTALL)" \
  'TUIC recovery reads durable TUIC scope'
assert_eq nobrand-tuic "$ACTION" 'TUIC recovery action'
assert_eq install "${TUIC_ACTION:-}" 'TUIC recovery resumes TUIC install'
printf 'SECOND_PROTOCOL_RECOVERY_SCOPE_GATE=PASS\n'

reset_fixture
unset FORWARD_ACTION
nb_lifecycle_begin install prepare 0 0 0 0 0 0 forward
nobrand_set_scoped_recovery_action CURRENT_PARTIAL_INSTALL
assert_eq forward "$(nobrand_recovery_scope CURRENT_PARTIAL_INSTALL)" \
  'Forward recovery reads durable Forward scope'
assert_eq nobrand-forward "$ACTION" 'Forward recovery action'
assert_eq recover-add "${FORWARD_ACTION:-}" \
  'Forward recovery selects the dedicated recover-add action'
[ "${FORWARD_ACTION:-}" != menu ] \
  || fail 'Forward recovery selected the broad interactive menu'

reset_fixture
nb_lifecycle_begin uninstall prepare 0 0 0 0 0 0 global
nobrand_set_scoped_recovery_action CURRENT_PARTIAL_UNINSTALL
assert_eq global "$(nobrand_recovery_scope CURRENT_PARTIAL_UNINSTALL)" \
  'partial uninstall recovery remains global'
assert_eq install "$ACTION" 'global partial-uninstall safe-repair action'
printf 'SCOPED_RECOVERY_ROUTING=PASS\n'

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
  is_mita_elf_binary() { return 1; }
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
nb_lifecycle_begin repair state-committed 0 0 0 0 0 0 mieru
nb_lifecycle_mark_mutation_started
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
write_complete_manager "$SCRIPT_VERSION"
(
  id() { [ "${1:-}" = -u ] && printf 0; }
  nb_lifecycle_lock_acquire() { NOBRAND_LIFECYCLE_LOCK_HELD=$((NOBRAND_LIFECYCLE_LOCK_HELD + 1)); }
  nb_lifecycle_lock_release() { NOBRAND_LIFECYCLE_LOCK_HELD=$((NOBRAND_LIFECYCLE_LOCK_HELD - 1)); }
  detect_pkg_manager() { printf deb; }
  ensure_management_dependencies() { return 0; }
  ensure_manager_state_layout() { return 0; }
  nobrand_manager_installation_valid() { return 0; }
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
write_complete_manager "$SCRIPT_VERSION"
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

# Fresh Mieru reconfigure is armed before request collection but marks only at
# its actual state boundary. Accepting every current value is a no-op and must
# restore the exact prior completed lifecycle record.
reset_fixture
write_schema
write_complete_manager "$SCRIPT_VERSION"
nb_lifecycle_begin install prepare 0 0 0 0 0 0 manager
nb_lifecycle_mark_mutation_started
nb_lifecycle_complete install
mieru_reconfigure_noop_prior="$fixture/mieru-reconfigure-noop.prior"
cp "$NOBRAND_LIFECYCLE_TX_FILE" "$mieru_reconfigure_noop_prior"
(
  require_root() { return 0; }
  require_linux() { return 0; }
  mita_installed() { return 0; }
  nb_lifecycle_lock_acquire() { NOBRAND_LIFECYCLE_LOCK_HELD=$((NOBRAND_LIFECYCLE_LOCK_HELD + 1)); }
  nb_lifecycle_lock_release() { NOBRAND_LIFECYCLE_LOCK_HELD=$((NOBRAND_LIFECYCLE_LOCK_HELD - 1)); }
  do_reconfigure_impl() { : >"$fixture/mieru-reconfigure-noop.called"; }
  nb_lifecycle_validate_manager_repair() { : >"$fixture/mieru-reconfigure-noop.unexpected-validation"; }
  NOBRAND_LIFECYCLE_LOCK_HELD=0
  do_reconfigure
  assert_eq 0 "$NOBRAND_LIFECYCLE_LOCK_HELD" \
    'no-op Mieru reconfigure balances lifecycle lock'
)
[ -e "$fixture/mieru-reconfigure-noop.called" ] \
  || fail 'no-op Mieru reconfigure fixture did not run'
[ ! -e "$fixture/mieru-reconfigure-noop.unexpected-validation" ] \
  || fail 'no-op Mieru reconfigure validated a fabricated repair transaction'
cmp -s "$mieru_reconfigure_noop_prior" "$NOBRAND_LIFECYCLE_TX_FILE" \
  || fail 'no-op Mieru reconfigure changed prior lifecycle metadata'

reset_fixture
write_schema
write_complete_manager "$SCRIPT_VERSION"
nb_lifecycle_begin repair prepare 0 0 0 0 0 0 mieru
(
  require_root() { return 0; }
  require_linux() { return 0; }
  mita_installed() { return 0; }
  nb_lifecycle_lock_acquire() { NOBRAND_LIFECYCLE_LOCK_HELD=$((NOBRAND_LIFECYCLE_LOCK_HELD + 1)); }
  nb_lifecycle_lock_release() { NOBRAND_LIFECYCLE_LOCK_HELD=$((NOBRAND_LIFECYCLE_LOCK_HELD - 1)); }
  do_reconfigure_impl() { : >"$fixture/mieru-unmutated-unexpected-reconfigure"; }
  NOBRAND_RECOVERY_EXPECTED_SCOPE=mieru
  NOBRAND_LIFECYCLE_ACTIVE=0
  NOBRAND_LIFECYCLE_OPERATION=""
  NOBRAND_LIFECYCLE_SCOPE=""
  # Consumed by the sourced recovery function.
  # shellcheck disable=SC2034
  NOBRAND_LIFECYCLE_MUTATION_STARTED=0
  NOBRAND_LIFECYCLE_LOCK_HELD=0
  do_reconfigure >/dev/null
  assert_eq 0 "$NOBRAND_LIFECYCLE_LOCK_HELD" \
    'unmutated Mieru reconfigure recovery balances lifecycle lock'
)
[ ! -e "$fixture/mieru-unmutated-unexpected-reconfigure" ] \
  || fail 'unmutated Mieru recovery invoked reconfigure implementation'
[ ! -e "$NOBRAND_LIFECYCLE_TX_FILE" ] \
  || fail 'unmutated Mieru reconfigure recovery retained lifecycle metadata'

# An explicit Mieru command is a new same-scope request. It clears a stale v2
# mutation-zero transaction and continues immediately as one fresh invocation.
reset_fixture
write_schema
write_complete_manager "$SCRIPT_VERSION"
nb_lifecycle_begin install prepare 0 0 0 0 0 0 mieru
mieru_install_zero_txid="$(nb_lifecycle_field TRANSACTION_ID)"
(
  require_root() { return 0; }
  require_linux() { return 0; }
  require_cmd() { return 0; }
  nb_lifecycle_lock_acquire() { NOBRAND_LIFECYCLE_LOCK_HELD=$((NOBRAND_LIFECYCLE_LOCK_HELD + 1)); }
  nb_lifecycle_lock_release() { NOBRAND_LIFECYCLE_LOCK_HELD=$((NOBRAND_LIFECYCLE_LOCK_HELD - 1)); }
  mieru_install_zero_ready=0
  mita_v3_install_state_valid() { [ "$mieru_install_zero_ready" -eq 1 ]; }
  mita_installed() { return 1; }
  do_install_impl() {
    assert_eq prepare "$(nb_lifecycle_field LAST_COMPLETED_PHASE)" \
      'explicit mutation-zero Mieru install restarts at prepare'
    [ "$(nb_lifecycle_field TRANSACTION_ID)" != "$mieru_install_zero_txid" ] \
      || fail 'explicit mutation-zero Mieru install reused stale transaction identity'
    nb_lifecycle_mark_protocol_mutation_started mieru
    mieru_install_zero_ready=1
    : >"$fixture/mieru-install-zero.called"
  }
  nb_lifecycle_validate_manager_repair() { return 0; }
  users_state_exists() { return 0; }
  users_count() { printf 1; }
  verify_mita_running() { return 0; }
  NOBRAND_PROTOCOL_EXPLICIT_RETRY_SCOPE=mieru
  NOBRAND_LIFECYCLE_LOCK_HELD=0
  do_install
  assert_eq 0 "$NOBRAND_LIFECYCLE_LOCK_HELD" \
    'explicit mutation-zero Mieru install balances lifecycle lock'
)
[ -e "$fixture/mieru-install-zero.called" ] \
  || fail 'explicit mutation-zero Mieru install did not run fresh request'
assert_eq complete "$(nb_lifecycle_field STATUS)" \
  'explicit mutation-zero Mieru install completes fresh transaction'

reset_fixture
write_schema
write_complete_manager "$SCRIPT_VERSION"
nb_lifecycle_begin repair prepare 0 0 0 0 0 0 mieru
mieru_reconfigure_zero_txid="$(nb_lifecycle_field TRANSACTION_ID)"
(
  require_root() { return 0; }
  require_linux() { return 0; }
  mita_installed() { return 0; }
  nb_lifecycle_lock_acquire() { NOBRAND_LIFECYCLE_LOCK_HELD=$((NOBRAND_LIFECYCLE_LOCK_HELD + 1)); }
  nb_lifecycle_lock_release() { NOBRAND_LIFECYCLE_LOCK_HELD=$((NOBRAND_LIFECYCLE_LOCK_HELD - 1)); }
  do_reconfigure_impl() {
    assert_eq prepare "$(nb_lifecycle_field LAST_COMPLETED_PHASE)" \
      'explicit mutation-zero Mieru reconfigure restarts at prepare'
    [ "$(nb_lifecycle_field TRANSACTION_ID)" != "$mieru_reconfigure_zero_txid" ] \
      || fail 'explicit mutation-zero Mieru reconfigure reused stale transaction identity'
    nb_lifecycle_mark_protocol_mutation_started mieru
    : >"$fixture/mieru-reconfigure-zero.called"
  }
  nb_lifecycle_validate_manager_repair() { return 0; }
  mita_v3_install_state_valid() { return 0; }
  verify_mita_running() { return 0; }
  NOBRAND_PROTOCOL_EXPLICIT_RETRY_SCOPE=mieru
  NOBRAND_LIFECYCLE_LOCK_HELD=0
  do_reconfigure
  assert_eq 0 "$NOBRAND_LIFECYCLE_LOCK_HELD" \
    'explicit mutation-zero Mieru reconfigure balances lifecycle lock'
)
[ -e "$fixture/mieru-reconfigure-zero.called" ] \
  || fail 'explicit mutation-zero Mieru reconfigure did not run fresh request'
assert_eq complete "$(nb_lifecycle_field STATUS)" \
  'explicit mutation-zero Mieru reconfigure completes fresh transaction'
printf 'MIERU_EXPLICIT_MUTATION_ZERO_RETRY=PASS\n'

# No-argument repair:mieru recovery has no request to reconstruct. Route it
# through main, clear only the zero-mutation record, and run no protocol callback.
reset_fixture
write_schema
write_complete_manager "$SCRIPT_VERSION"
nb_lifecycle_begin repair prepare 0 0 0 0 0 0 mieru
(
  id() { [ "${1:-}" = -u ] && printf 0; }
  require_root() { return 0; }
  require_linux() { return 0; }
  require_cmd() { return 0; }
  nb_lifecycle_lock_acquire() { NOBRAND_LIFECYCLE_LOCK_HELD=$((NOBRAND_LIFECYCLE_LOCK_HELD + 1)); }
  nb_lifecycle_lock_release() { NOBRAND_LIFECYCLE_LOCK_HELD=$((NOBRAND_LIFECYCLE_LOCK_HELD - 1)); }
  read_tty() { printf -v "$1" 1; }
  print_banner() { :; }
  is_mita_elf_binary() { return 1; }
  do_install_impl() { : >"$fixture/mieru-zero-noarg.unexpected-install"; }
  do_reconfigure_impl() { : >"$fixture/mieru-zero-noarg.unexpected-reconfigure"; }
  nobrand_menu_loop() { : >"$fixture/mieru-zero-noarg.unexpected-menu"; }
  NOBRAND_LIFECYCLE_LOCK_HELD=0
  ACTION=""
  main >/dev/null
  assert_eq 0 "$NOBRAND_LIFECYCLE_LOCK_HELD" \
    'no-argument mutation-zero repair:mieru balances lifecycle lock'
)
[ ! -e "$NOBRAND_LIFECYCLE_TX_FILE" ] \
  || fail 'no-argument mutation-zero repair:mieru retained transaction'
[ ! -e "$fixture/mieru-zero-noarg.unexpected-install" ] \
  && [ ! -e "$fixture/mieru-zero-noarg.unexpected-reconfigure" ] \
  && [ ! -e "$fixture/mieru-zero-noarg.unexpected-menu" ] \
  || fail 'no-argument mutation-zero repair:mieru dispatched unrelated work'
printf 'MIERU_NOARG_MUTATION_ZERO_CLEAR=PASS\n'

# An ambiguous interrupted repair:mieru cannot be routed to a fresh install or
# silently rerun reconfigure defaults. No-argument recovery fails closed; an
# explicit reconfigure may recollect, mutate, validate, and complete its scope.
reset_fixture
write_schema
write_complete_manager "$SCRIPT_VERSION"
nb_lifecycle_begin repair prepare 0 0 0 0 0 0 mieru
nb_lifecycle_mark_mutation_started
cp "$NOBRAND_LIFECYCLE_TX_FILE" "$fixture/mieru-reconfigure-ambiguous.prior"
(
  ACTION=""
  NOBRAND_RECOVERY_EXPECTED_SCOPE=""
  set +e
  nobrand_set_scoped_recovery_action CURRENT_PARTIAL_REPAIR >/dev/null 2>&1
  mieru_ambiguous_route_rc=$?
  set -e
  [ "$mieru_ambiguous_route_rc" -ne 0 ] \
    || fail 'ambiguous repair:mieru was silently routed to an action'
  [ -z "$ACTION" ] || fail 'ambiguous repair:mieru selected a fresh install/reconfigure action'
)
cmp -s "$fixture/mieru-reconfigure-ambiguous.prior" "$NOBRAND_LIFECYCLE_TX_FILE" \
  || fail 'ambiguous Mieru route modified recovery metadata'
(
  require_root() { return 0; }
  require_linux() { return 0; }
  mita_installed() { return 0; }
  nb_lifecycle_lock_acquire() { NOBRAND_LIFECYCLE_LOCK_HELD=$((NOBRAND_LIFECYCLE_LOCK_HELD + 1)); }
  nb_lifecycle_lock_release() { NOBRAND_LIFECYCLE_LOCK_HELD=$((NOBRAND_LIFECYCLE_LOCK_HELD - 1)); }
  do_reconfigure_impl() { : >"$fixture/mieru-reconfigure-unexpected-noarg"; }
  NOBRAND_RECOVERY_EXPECTED_SCOPE=mieru
  set +e
  do_reconfigure >/dev/null 2>&1
  mieru_reconfigure_noarg_rc=$?
  set -e
  [ "$mieru_reconfigure_noarg_rc" -ne 0 ] \
    || fail 'no-argument Mieru reconfigure replayed an ambiguous request'
)
[ ! -e "$fixture/mieru-reconfigure-unexpected-noarg" ] \
  || fail 'no-argument Mieru recovery invoked reconfigure implementation'
cmp -s "$fixture/mieru-reconfigure-ambiguous.prior" "$NOBRAND_LIFECYCLE_TX_FILE" \
  || fail 'no-argument Mieru reconfigure refusal changed transaction bytes'
(
  require_root() { return 0; }
  require_linux() { return 0; }
  mita_installed() { return 0; }
  nb_lifecycle_lock_acquire() { NOBRAND_LIFECYCLE_LOCK_HELD=$((NOBRAND_LIFECYCLE_LOCK_HELD + 1)); }
  nb_lifecycle_lock_release() { NOBRAND_LIFECYCLE_LOCK_HELD=$((NOBRAND_LIFECYCLE_LOCK_HELD - 1)); }
  do_reconfigure_impl() {
    nb_lifecycle_mark_protocol_mutation_started mieru
    : >"$fixture/mieru-reconfigure-explicit.called"
  }
  nb_lifecycle_validate_manager_repair() { return 0; }
  mita_v3_install_state_valid() { return 0; }
  verify_mita_running() { return 0; }
  NOBRAND_RECOVERY_EXPECTED_SCOPE=""
  NOBRAND_PROTOCOL_EXPLICIT_RETRY_SCOPE=mieru
  NOBRAND_LIFECYCLE_LOCK_HELD=0
  do_reconfigure
  assert_eq 0 "$NOBRAND_LIFECYCLE_LOCK_HELD" \
    'explicit Mieru reconfigure recovery balances lifecycle lock'
)
[ -e "$fixture/mieru-reconfigure-explicit.called" ] \
  || fail 'explicit Mieru reconfigure did not recollect/run its scoped action'
assert_eq complete "$(nb_lifecycle_field STATUS)" \
  'explicit Mieru reconfigure recovery completes transaction'
assert_eq repair "$(nb_lifecycle_field OPERATION)" \
  'explicit Mieru reconfigure recovery preserves repair operation'
assert_eq mieru "$(nb_lifecycle_scope)" \
  'explicit Mieru reconfigure recovery preserves Mieru scope'
printf 'MIERU_RECONFIGURE_RECOVERY_BOUNDARY=PASS\n'

# A mutation bit from an earlier attempt is not proof that this invocation made
# progress. A successful callback with no new marker must retain exact metadata.
for mieru_attempt_action in install reconfigure; do
  reset_fixture
  write_schema
  write_complete_manager "$SCRIPT_VERSION"
  nb_lifecycle_begin "$([ "$mieru_attempt_action" = install ] && printf install || printf repair)" \
    prepare 0 0 0 0 0 0 mieru
  nb_lifecycle_mark_mutation_started
  cp "$NOBRAND_LIFECYCLE_TX_FILE" "$fixture/mieru-${mieru_attempt_action}-attempt.expected"
  (
    require_root() { return 0; }
    require_linux() { return 0; }
    require_cmd() { return 0; }
    mita_installed() { return 0; }
    nb_lifecycle_lock_acquire() { NOBRAND_LIFECYCLE_LOCK_HELD=$((NOBRAND_LIFECYCLE_LOCK_HELD + 1)); }
    nb_lifecycle_lock_release() { NOBRAND_LIFECYCLE_LOCK_HELD=$((NOBRAND_LIFECYCLE_LOCK_HELD - 1)); }
    do_install_impl() { : >"$fixture/mieru-install-attempt.called"; }
    do_reconfigure_impl() { : >"$fixture/mieru-reconfigure-attempt.called"; }
    nb_lifecycle_validate_manager_repair() { : >"$fixture/mieru-${mieru_attempt_action}-attempt.unexpected-validation"; }
    NOBRAND_PROTOCOL_EXPLICIT_RETRY_SCOPE=mieru
    NOBRAND_LIFECYCLE_LOCK_HELD=0
    set +e
    "do_${mieru_attempt_action}" >/dev/null 2>&1
    mieru_attempt_rc=$?
    set -e
    [ "$mieru_attempt_rc" -ne 0 ] \
      || fail "Mieru ${mieru_attempt_action} retry accepted an old mutation bit"
    assert_eq 0 "$NOBRAND_LIFECYCLE_LOCK_HELD" \
      "Mieru ${mieru_attempt_action} no-progress retry balances lock"
  )
  [ -e "$fixture/mieru-${mieru_attempt_action}-attempt.called" ] \
    || fail "Mieru ${mieru_attempt_action} attempt-proof fixture did not run callback"
  [ ! -e "$fixture/mieru-${mieru_attempt_action}-attempt.unexpected-validation" ] \
    || fail "Mieru ${mieru_attempt_action} no-progress retry ran validation"
  cmp -s "$fixture/mieru-${mieru_attempt_action}-attempt.expected" \
    "$NOBRAND_LIFECYCLE_TX_FILE" \
    || fail "Mieru ${mieru_attempt_action} no-progress retry changed transaction bytes"
done

# Validation-only repair recovery intentionally needs no marker from this
# invocation: authoritative state is already committed and is only verified.
reset_fixture
write_schema
write_complete_manager "$SCRIPT_VERSION"
nb_lifecycle_begin repair ready-to-validate 0 0 0 0 0 0 mieru
nb_lifecycle_mark_mutation_started
(
  require_root() { return 0; }
  require_linux() { return 0; }
  mita_installed() { return 0; }
  nb_lifecycle_lock_acquire() { NOBRAND_LIFECYCLE_LOCK_HELD=$((NOBRAND_LIFECYCLE_LOCK_HELD + 1)); }
  nb_lifecycle_lock_release() { NOBRAND_LIFECYCLE_LOCK_HELD=$((NOBRAND_LIFECYCLE_LOCK_HELD - 1)); }
  do_reconfigure_impl() { : >"$fixture/mieru-ready-unexpected-reconfigure"; }
  nb_lifecycle_validate_manager_repair() { return 0; }
  mita_v3_install_state_valid() { return 0; }
  verify_mita_running() { return 0; }
  NOBRAND_RECOVERY_EXPECTED_SCOPE=mieru
  NOBRAND_LIFECYCLE_LOCK_HELD=0
  do_reconfigure
  assert_eq 0 "$NOBRAND_LIFECYCLE_LOCK_HELD" \
    'validation-only Mieru reconfigure balances lifecycle lock'
)
[ ! -e "$fixture/mieru-ready-unexpected-reconfigure" ] \
  || fail 'validation-only Mieru reconfigure replayed callback'
assert_eq complete "$(nb_lifecycle_field STATUS)" \
  'validation-only Mieru reconfigure completes after verification'
printf 'MIERU_CALLBACK_ATTEMPT_PROOF=PASS\n'

# Legacy v1 has no mutation bit and repair did not distinguish reinstall from
# reconfigure. Pre-commit records therefore require an explicit action, while a
# ready record is validation-only and never calls the installer implementation.
reset_fixture
write_schema
write_complete_manager "$SCRIPT_VERSION"
write_lifecycle_v1_fixture repair prepare
cp "$NOBRAND_LIFECYCLE_TX_FILE" "$fixture/mieru-v1-ambiguous.prior"
(
  require_root() { return 0; }
  require_linux() { return 0; }
  require_cmd() { return 0; }
  nb_lifecycle_lock_acquire() { NOBRAND_LIFECYCLE_LOCK_HELD=$((NOBRAND_LIFECYCLE_LOCK_HELD + 1)); }
  nb_lifecycle_lock_release() { NOBRAND_LIFECYCLE_LOCK_HELD=$((NOBRAND_LIFECYCLE_LOCK_HELD - 1)); }
  do_install_impl() { : >"$fixture/mieru-v1-unexpected-replay"; }
  NOBRAND_RECOVERY_EXPECTED_SCOPE=mieru
  set +e
  do_install >/dev/null 2>&1
  mieru_v1_ambiguous_rc=$?
  set -e
  [ "$mieru_v1_ambiguous_rc" -ne 0 ] \
    || fail 'legacy ambiguous Mieru record replayed without an explicit action'
)
[ ! -e "$fixture/mieru-v1-unexpected-replay" ] \
  || fail 'legacy ambiguous Mieru recovery called install implementation'
cmp -s "$fixture/mieru-v1-ambiguous.prior" "$NOBRAND_LIFECYCLE_TX_FILE" \
  || fail 'legacy ambiguous Mieru refusal changed transaction bytes'

reset_fixture
write_schema
write_complete_manager "$SCRIPT_VERSION"
write_lifecycle_v1_fixture install ready-to-validate
(
  require_root() { return 0; }
  require_linux() { return 0; }
  require_cmd() { return 0; }
  nb_lifecycle_lock_acquire() { NOBRAND_LIFECYCLE_LOCK_HELD=$((NOBRAND_LIFECYCLE_LOCK_HELD + 1)); }
  nb_lifecycle_lock_release() { NOBRAND_LIFECYCLE_LOCK_HELD=$((NOBRAND_LIFECYCLE_LOCK_HELD - 1)); }
  do_install_impl() { : >"$fixture/mieru-v1-ready-unexpected-replay"; }
  nb_lifecycle_validate_manager_repair() { return 0; }
  mita_v3_install_state_valid() { return 0; }
  users_state_exists() { return 0; }
  users_count() { printf 1; }
  verify_mita_running() { return 0; }
  NOBRAND_RECOVERY_EXPECTED_SCOPE=mieru
  NOBRAND_LIFECYCLE_LOCK_HELD=0
  do_install
  assert_eq 0 "$NOBRAND_LIFECYCLE_LOCK_HELD" \
    'legacy ready Mieru validation balances lifecycle lock'
)
[ ! -e "$fixture/mieru-v1-ready-unexpected-replay" ] \
  || fail 'legacy ready Mieru recovery replayed installer'
assert_eq complete "$(nb_lifecycle_field STATUS)" \
  'legacy ready Mieru recovery completes after validation only'
assert_eq mieru "$(nb_lifecycle_scope)" \
  'legacy ready Mieru validation preserves inferred scope'
printf 'MIERU_V1_FAIL_CLOSED_COMPATIBILITY=PASS\n'

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

# Ingress validation/callback failures before authoritative mutation must not
# manufacture a partial configure state. Once the callback marks mutation, the
# exact configure:ingress transaction must remain available for reconciliation.
reset_fixture
(
  NOBRAND_MANAGER_SESSION_ACTIVE=1
  nb_lifecycle_lock_acquire() { NOBRAND_LIFECYCLE_LOCK_HELD=$((NOBRAND_LIFECYCLE_LOCK_HELD + 1)); }
  nb_lifecycle_lock_release() { NOBRAND_LIFECYCLE_LOCK_HELD=$((NOBRAND_LIFECYCLE_LOCK_HELD - 1)); }
  nobrand_run_ingress_action_unscoped() { return 61; }
  set +e
  nb_lifecycle_run_ingress_action
  ingress_pre_mutation_rc=$?
  set -e
  assert_eq 61 "$ingress_pre_mutation_rc" \
    'pre-mutation Ingress callback failure propagates'
  assert_eq 0 "$NOBRAND_LIFECYCLE_LOCK_HELD" \
    'pre-mutation Ingress callback failure releases the lock'
)
[ ! -e "$NOBRAND_LIFECYCLE_TX_FILE" ] \
  || fail 'pre-mutation Ingress callback failure retained a transaction'
assert_state CLEAN 'pre-mutation Ingress callback failure remains clean'

reset_fixture
(
  NOBRAND_MANAGER_SESSION_ACTIVE=1
  nb_lifecycle_lock_acquire() { NOBRAND_LIFECYCLE_LOCK_HELD=$((NOBRAND_LIFECYCLE_LOCK_HELD + 1)); }
  nb_lifecycle_lock_release() { NOBRAND_LIFECYCLE_LOCK_HELD=$((NOBRAND_LIFECYCLE_LOCK_HELD - 1)); }
  nobrand_run_ingress_action_unscoped() {
    nb_lifecycle_mark_mutation_started
    return 62
  }
  set +e
  nb_lifecycle_run_ingress_action
  ingress_post_mutation_rc=$?
  set -e
  assert_eq 62 "$ingress_post_mutation_rc" \
    'post-mutation Ingress callback failure propagates'
  assert_eq 0 "$NOBRAND_LIFECYCLE_LOCK_HELD" \
    'post-mutation Ingress callback failure releases the lock'
)
nb_lifecycle_tx_valid || fail 'post-mutation Ingress callback failure corrupted recovery metadata'
assert_eq configure "$(nb_lifecycle_field OPERATION)" \
  'post-mutation Ingress callback preserves configure operation'
assert_eq ingress "$(nb_lifecycle_scope)" \
  'post-mutation Ingress callback preserves Ingress scope'
assert_eq 1 "$(nb_lifecycle_mutation_started)" \
  'post-mutation Ingress callback preserves mutation marker'
assert_state CURRENT_PARTIAL_CONFIGURE \
  'post-mutation Ingress callback remains scoped and recoverable'
printf 'INGRESS_CALLBACK_MUTATION_BOUNDARY=PASS\n'

# Fresh Ingress actions snapshot a prior completed lifecycle record. A callback
# failure or successful no-op before its mutation marker restores those bytes.
for ingress_pre_mutation_result in failure noop; do
  reset_fixture
  write_schema
  write_complete_manager "$SCRIPT_VERSION"
  nb_lifecycle_begin install prepare 0 0 0 0 0 0 manager
  nb_lifecycle_mark_mutation_started
  nb_lifecycle_complete install
  cp "$NOBRAND_LIFECYCLE_TX_FILE" \
    "$fixture/ingress-${ingress_pre_mutation_result}.expected"
  (
    NOBRAND_MANAGER_SESSION_ACTIVE=1
    nb_lifecycle_lock_acquire() { NOBRAND_LIFECYCLE_LOCK_HELD=$((NOBRAND_LIFECYCLE_LOCK_HELD + 1)); }
    nb_lifecycle_lock_release() { NOBRAND_LIFECYCLE_LOCK_HELD=$((NOBRAND_LIFECYCLE_LOCK_HELD - 1)); }
    if [ "$ingress_pre_mutation_result" = failure ]; then
      nobrand_run_ingress_action_unscoped() { return 61; }
    else
      nobrand_run_ingress_action_unscoped() { return 0; }
    fi
    NOBRAND_LIFECYCLE_LOCK_HELD=0
    set +e
    nb_lifecycle_run_ingress_action
    ingress_pre_mutation_result_rc=$?
    set -e
    if [ "$ingress_pre_mutation_result" = failure ]; then
      assert_eq 61 "$ingress_pre_mutation_result_rc" \
        'Ingress pre-mutation failure preserves callback status'
    else
      assert_eq 0 "$ingress_pre_mutation_result_rc" \
        'Ingress successful no-op remains successful'
    fi
    assert_eq 0 "$NOBRAND_LIFECYCLE_LOCK_HELD" \
      "Ingress ${ingress_pre_mutation_result} balances lifecycle lock"
  )
  cmp -s "$fixture/ingress-${ingress_pre_mutation_result}.expected" \
    "$NOBRAND_LIFECYCLE_TX_FILE" \
    || fail "Ingress ${ingress_pre_mutation_result} changed prior completed metadata"
done
printf 'INGRESS_PREMUTATION_RESTORE=PASS\n'

# Explicit Ingress intent may replace only a v2 mutation-zero configure record.
# A mutated record is rejected by main before the callback and remains exact.
reset_fixture
write_schema
write_complete_manager "$SCRIPT_VERSION"
nb_lifecycle_begin configure prepare 0 0 0 0 0 0 ingress
ingress_explicit_zero_txid="$(nb_lifecycle_field TRANSACTION_ID)"
(
  # shellcheck disable=SC1091
  source "$TEST_ROOT/src/16-core-ingress.sh"
  id() { [ "${1:-}" = -u ] && printf 0; }
  nb_lifecycle_lock_acquire() { NOBRAND_LIFECYCLE_LOCK_HELD=$((NOBRAND_LIFECYCLE_LOCK_HELD + 1)); }
  nb_lifecycle_lock_release() { NOBRAND_LIFECYCLE_LOCK_HELD=$((NOBRAND_LIFECYCLE_LOCK_HELD - 1)); }
  ensure_manager_state_layout() { return 0; }
  dry_run_should_preview() { return 1; }
  is_mita_elf_binary() { return 1; }
  nobrand_run_ingress_action_unscoped() {
    [ "$(nb_lifecycle_field TRANSACTION_ID)" != "$ingress_explicit_zero_txid" ] \
      || fail 'explicit Ingress retry reused stale transaction identity'
    nb_lifecycle_mark_mutation_started
    printf 'callback\n' >>"$fixture/ingress-explicit-zero.callback"
  }
  ACTION=nobrand-ingress
  INGRESS_ACTION=modify
  NOBRAND_LIFECYCLE_LOCK_HELD=0
  main
  assert_eq 0 "$NOBRAND_LIFECYCLE_LOCK_HELD" \
    'explicit mutation-zero Ingress retry balances lifecycle lock'
)
assert_eq 1 "$(wc -l <"$fixture/ingress-explicit-zero.callback" | tr -d '[:space:]')" \
  'explicit mutation-zero Ingress retry runs callback once'
assert_eq complete "$(nb_lifecycle_field STATUS)" \
  'explicit mutation-zero Ingress retry completes fresh transaction'

reset_fixture
write_schema
write_complete_manager "$SCRIPT_VERSION"
nb_lifecycle_begin configure prepare 0 0 0 0 0 0 ingress
nb_lifecycle_mark_mutation_started
cp "$NOBRAND_LIFECYCLE_TX_FILE" "$fixture/ingress-explicit-mutated.expected"
(
  id() { [ "${1:-}" = -u ] && printf 0; }
  nb_lifecycle_lock_acquire() { NOBRAND_LIFECYCLE_LOCK_HELD=$((NOBRAND_LIFECYCLE_LOCK_HELD + 1)); }
  nb_lifecycle_lock_release() { NOBRAND_LIFECYCLE_LOCK_HELD=$((NOBRAND_LIFECYCLE_LOCK_HELD - 1)); }
  nobrand_run_ingress_action() { : >"$fixture/ingress-explicit-mutated.unexpected"; }
  ACTION=nobrand-ingress
  # Consumed by the main dispatcher when the recovery gate permits dispatch.
  # shellcheck disable=SC2034
  INGRESS_ACTION=modify
  NOBRAND_LIFECYCLE_LOCK_HELD=0
  set +e
  main >/dev/null 2>&1
  ingress_explicit_mutated_rc=$?
  set -e
  [ "$ingress_explicit_mutated_rc" -ne 0 ] \
    || fail 'explicit Ingress action accepted a mutated recovery transaction'
  assert_eq 0 "$NOBRAND_LIFECYCLE_LOCK_HELD" \
    'mutated explicit Ingress refusal balances lifecycle lock'
)
[ ! -e "$fixture/ingress-explicit-mutated.unexpected" ] \
  || fail 'mutated explicit Ingress transaction invoked callback'
cmp -s "$fixture/ingress-explicit-mutated.expected" "$NOBRAND_LIFECYCLE_TX_FILE" \
  || fail 'mutated explicit Ingress refusal changed transaction bytes'
printf 'INGRESS_EXPLICIT_RETRY_GATE=PASS\n'

# A transaction recovered in a fresh process with no committed Ingress mutation
# is temporary intent only. Clear it without reconciliation or validation writes.
reset_fixture
nb_lifecycle_begin configure prepare 0 0 0 0 0 0 ingress
ingress_unmutated_unexpected="$fixture/ingress-unmutated-unexpected"
(
  require_root() { return 0; }
  require_linux() { return 0; }
  detect_pkg_manager() { printf deb; }
  ensure_management_dependencies() { return 0; }
  nb_lifecycle_lock_acquire() { NOBRAND_LIFECYCLE_LOCK_HELD=$((NOBRAND_LIFECYCLE_LOCK_HELD + 1)); }
  nb_lifecycle_lock_release() { NOBRAND_LIFECYCLE_LOCK_HELD=$((NOBRAND_LIFECYCLE_LOCK_HELD - 1)); }
  ensure_manager_state_layout() { : >"$ingress_unmutated_unexpected"; }
  nobrand_reconcile_ingress_profiles() { : >"$ingress_unmutated_unexpected"; }
  NOBRAND_LIFECYCLE_ACTIVE=0
  NOBRAND_LIFECYCLE_OPERATION=""
  NOBRAND_LIFECYCLE_SCOPE=""
  NOBRAND_LIFECYCLE_MUTATION_STARTED=0
  NOBRAND_LIFECYCLE_LOCK_HELD=0
  nobrand_recover_ingress_scope >/dev/null
  assert_eq 0 "$NOBRAND_LIFECYCLE_LOCK_HELD" \
    'unmutated Ingress recovery balances lifecycle lock'
)
[ ! -e "$ingress_unmutated_unexpected" ] \
  || fail 'unmutated Ingress recovery reconciled or initialized manager state'
[ ! -e "$NOBRAND_LIFECYCLE_TX_FILE" ] \
  || fail 'unmutated Ingress recovery retained lifecycle metadata'
printf 'INGRESS_UNMUTATED_RECOVERY_CLEAR=PASS\n'

# A fresh process recovering a mutated Ingress transaction must reactivate the
# existing transaction before completion and reconcile every explicit Profile,
# not merely validate metadata or restore one implicit/default Profile.
reset_fixture
mkdir -p "$(dirname "$NOBRAND_INGRESS_STATE_FILE")"
cat >"$NOBRAND_INGRESS_STATE_FILE" <<'JSON'
{
  "profiles": [
    {"profile_id": "i1111111111111111"},
    {"profile_id": "i2222222222222222"}
  ]
}
JSON
nb_lifecycle_begin configure state-committed 0 0 0 0 0 0 ingress
nb_lifecycle_mark_mutation_started
ingress_recovery_apply_log="$fixture/ingress-recovery-profile-apply.log"
(
  require_root() { return 0; }
  require_linux() { return 0; }
  detect_pkg_manager() { printf deb; }
  ensure_management_dependencies() { return 0; }
  nb_lifecycle_lock_acquire() { NOBRAND_LIFECYCLE_LOCK_HELD=$((NOBRAND_LIFECYCLE_LOCK_HELD + 1)); }
  nb_lifecycle_lock_release() { NOBRAND_LIFECYCLE_LOCK_HELD=$((NOBRAND_LIFECYCLE_LOCK_HELD - 1)); }
  ensure_manager_state_layout() { return 0; }
  nobrand_manager_installation_valid() { return 0; }
  nb_ingress_state_valid() { return 0; }
  nb_ingress_apply_profile() { printf '%s\n' "$1" >>"$ingress_recovery_apply_log"; }
  nb_strict_firewall_restore_authoritative() { return 0; }
  NOBRAND_LIFECYCLE_ACTIVE=0
  NOBRAND_LIFECYCLE_OPERATION=""
  # Consumed by the sourced Ingress recovery wrapper.
  # shellcheck disable=SC2034
  NOBRAND_LIFECYCLE_SCOPE=""
  # shellcheck disable=SC2034
  NOBRAND_LIFECYCLE_MUTATION_STARTED=0
  NOBRAND_LIFECYCLE_LOCK_HELD=0
  nobrand_recover_ingress_scope
  assert_eq 0 "$NOBRAND_LIFECYCLE_LOCK_HELD" \
    'Ingress recovery releases its lifecycle lock'
)
assert_eq $'i1111111111111111\ni2222222222222222' \
  "$(cat "$ingress_recovery_apply_log")" \
  'Ingress recovery reapplies every explicit Profile exactly once'
assert_eq configure "$(nb_lifecycle_field OPERATION)" \
  'Ingress recovery preserves configure operation'
assert_eq ingress "$(nb_lifecycle_scope)" \
  'Ingress recovery preserves Ingress scope'
assert_eq complete "$(nb_lifecycle_field STATUS)" \
  'fresh-process Ingress recovery activates and completes the transaction'
assert_eq complete "$(nb_lifecycle_field LAST_COMPLETED_PHASE)" \
  'Ingress recovery records final completion'
printf 'INGRESS_RECOVERY_RECONCILIATION=PASS\n'

# Recovery must observe producer failures before it can checkpoint or complete
# a mutated Ingress transaction. A failed Profile-ID enumeration may not look
# like an empty Profile set, and a failed reference-row producer may not look
# like an unreferenced Profile.
reset_fixture
mkdir -p "$(dirname "$NOBRAND_INGRESS_STATE_FILE")"
cat >"$NOBRAND_INGRESS_STATE_FILE" <<'JSON'
{"profiles":[{"profile_id":"i1111111111111111"}]}
JSON
nb_lifecycle_begin configure state-committed 0 0 0 0 0 0 ingress
nb_lifecycle_mark_mutation_started
ingress_profile_list_producer_marker="$fixture/ingress-profile-list-producer-failed"
ingress_profile_list_unexpected_apply="$fixture/ingress-profile-list-unexpected-apply"
(
  require_root() { return 0; }
  require_linux() { return 0; }
  detect_pkg_manager() { printf deb; }
  ensure_management_dependencies() { return 0; }
  nb_lifecycle_lock_acquire() { NOBRAND_LIFECYCLE_LOCK_HELD=$((NOBRAND_LIFECYCLE_LOCK_HELD + 1)); }
  nb_lifecycle_lock_release() { NOBRAND_LIFECYCLE_LOCK_HELD=$((NOBRAND_LIFECYCLE_LOCK_HELD - 1)); }
  ensure_manager_state_layout() { return 0; }
  nobrand_manager_installation_valid() { return 0; }
  nb_ingress_state_valid() { return 0; }
  nb_ingress_apply_profile() { : >"$ingress_profile_list_unexpected_apply"; }
  jq() {
    if [ "${1:-}" = -r ] && [ "${2:-}" = '.profiles[].profile_id' ] \
       && [ "${3:-}" = "$NOBRAND_INGRESS_STATE_FILE" ]; then
      printf '%s\n' i1111111111111111
      : >"$ingress_profile_list_producer_marker"
      return 76
    fi
    command jq "$@"
  }
  NOBRAND_LIFECYCLE_ACTIVE=0
  NOBRAND_LIFECYCLE_OPERATION=""
  # Consumed by the sourced Ingress recovery wrapper.
  # shellcheck disable=SC2034
  NOBRAND_LIFECYCLE_SCOPE=""
  # shellcheck disable=SC2034
  NOBRAND_LIFECYCLE_MUTATION_STARTED=0
  NOBRAND_LIFECYCLE_LOCK_HELD=0
  set +e
  nobrand_recover_ingress_scope
  ingress_profile_list_recovery_rc=$?
  set -e
  [ "$ingress_profile_list_recovery_rc" -ne 0 ] \
    || fail 'Ingress Profile-list producer failure was treated as success'
  assert_eq 0 "$NOBRAND_LIFECYCLE_LOCK_HELD" \
    'Ingress Profile-list producer failure releases lifecycle lock'
)
[ -e "$ingress_profile_list_producer_marker" ] \
  || fail 'Ingress recovery did not exercise the Profile-list producer failure'
[ ! -e "$ingress_profile_list_unexpected_apply" ] \
  || fail 'Ingress recovery applied a Profile after Profile-list producer failure'
assert_eq in-progress "$(nb_lifecycle_field STATUS)" \
  'Profile-list producer failure preserves in-progress transaction'
assert_eq state-committed "$(nb_lifecycle_field LAST_COMPLETED_PHASE)" \
  'Profile-list producer failure does not advance lifecycle phase'
assert_eq configure "$(nb_lifecycle_field OPERATION)" \
  'Profile-list producer failure preserves configure operation'
assert_eq ingress "$(nb_lifecycle_scope)" \
  'Profile-list producer failure preserves Ingress scope'
assert_eq 1 "$(nb_lifecycle_mutation_started)" \
  'Profile-list producer failure preserves mutation marker'
assert_state CURRENT_PARTIAL_CONFIGURE \
  'Profile-list producer failure remains recoverable'

reset_fixture
mkdir -p "$(dirname "$NOBRAND_INGRESS_STATE_FILE")"
cat >"$NOBRAND_INGRESS_STATE_FILE" <<'JSON'
{"profiles":[{"profile_id":"i2222222222222222"}]}
JSON
nb_lifecycle_begin configure state-committed 0 0 0 0 0 0 ingress
nb_lifecycle_mark_mutation_started
ingress_reference_producer_marker="$fixture/ingress-reference-producer-failed"
ingress_reference_unexpected_owner="$fixture/ingress-reference-unexpected-owner"
(
  # shellcheck disable=SC1091
  source "$TEST_ROOT/src/16-core-ingress.sh"
  require_root() { return 0; }
  require_linux() { return 0; }
  detect_pkg_manager() { printf deb; }
  ensure_management_dependencies() { return 0; }
  nb_lifecycle_lock_acquire() { NOBRAND_LIFECYCLE_LOCK_HELD=$((NOBRAND_LIFECYCLE_LOCK_HELD + 1)); }
  nb_lifecycle_lock_release() { NOBRAND_LIFECYCLE_LOCK_HELD=$((NOBRAND_LIFECYCLE_LOCK_HELD - 1)); }
  ensure_manager_state_layout() { return 0; }
  nobrand_manager_installation_valid() { return 0; }
  nb_ingress_state_valid() { return 0; }
  nb_ingress_profile_json() { return 0; }
  nb_ingress_profile_reference_rows() {
    printf '%s\n' snell:s1111111111111111
    : >"$ingress_reference_producer_marker"
    return 77
  }
  nb_ingress_apply_owner() { : >"$ingress_reference_unexpected_owner"; }
  NOBRAND_LIFECYCLE_ACTIVE=0
  NOBRAND_LIFECYCLE_OPERATION=""
  # Consumed by the sourced Ingress recovery wrapper.
  # shellcheck disable=SC2034
  NOBRAND_LIFECYCLE_SCOPE=""
  # shellcheck disable=SC2034
  NOBRAND_LIFECYCLE_MUTATION_STARTED=0
  NOBRAND_LIFECYCLE_LOCK_HELD=0
  set +e
  nobrand_recover_ingress_scope
  ingress_reference_recovery_rc=$?
  set -e
  [ "$ingress_reference_recovery_rc" -ne 0 ] \
    || fail 'Ingress reference-row producer failure was treated as success'
  assert_eq 0 "$NOBRAND_LIFECYCLE_LOCK_HELD" \
    'Ingress reference-row producer failure releases lifecycle lock'
)
[ -e "$ingress_reference_producer_marker" ] \
  || fail 'Ingress recovery did not exercise the reference-row producer failure'
[ ! -e "$ingress_reference_unexpected_owner" ] \
  || fail 'Ingress recovery applied an owner after reference-row producer failure'
assert_eq in-progress "$(nb_lifecycle_field STATUS)" \
  'reference-row producer failure preserves in-progress transaction'
assert_eq state-committed "$(nb_lifecycle_field LAST_COMPLETED_PHASE)" \
  'reference-row producer failure does not advance lifecycle phase'
assert_eq configure "$(nb_lifecycle_field OPERATION)" \
  'reference-row producer failure preserves configure operation'
assert_eq ingress "$(nb_lifecycle_scope)" \
  'reference-row producer failure preserves Ingress scope'
assert_eq 1 "$(nb_lifecycle_mutation_started)" \
  'reference-row producer failure preserves mutation marker'
assert_state CURRENT_PARTIAL_CONFIGURE \
  'reference-row producer failure remains recoverable'
printf 'INGRESS_PRODUCER_STATUS_PROPAGATION=PASS\n'

# Protocol wrappers may validate the manager but must never repair it before
# the component mutation boundary. On failure, the exact prior lifecycle record
# is restored and the callback is not reached.
reset_fixture
write_schema
write_complete_manager "$SCRIPT_VERSION"
nb_lifecycle_begin install prepare 0 0 0 0 0 0 manager
nb_lifecycle_mark_mutation_started
nb_lifecycle_complete install
protocol_invalid_manager_prior="$fixture/protocol-invalid-manager.prior"
cp "$NOBRAND_LIFECYCLE_TX_FILE" "$protocol_invalid_manager_prior"
(
  require_root() { return 0; }
  require_linux() { return 0; }
  nb_lifecycle_lock_acquire() { NOBRAND_LIFECYCLE_LOCK_HELD=$((NOBRAND_LIFECYCLE_LOCK_HELD + 1)); }
  nb_lifecycle_lock_release() { NOBRAND_LIFECYCLE_LOCK_HELD=$((NOBRAND_LIFECYCLE_LOCK_HELD - 1)); }
  ensure_manager_state_layout() { : >"$fixture/unexpected-protocol-manager-layout"; }
  nobrand_manager_installation_valid() { return 1; }
  nobrand_install_manager_script() { : >"$fixture/unexpected-protocol-manager-repair"; }
  invalid_manager_callback() { : >"$fixture/unexpected-invalid-manager-callback"; }
  NOBRAND_MANAGER_SESSION_ACTIVE=1
  set +e
  nb_lifecycle_run_protocol_install tuic invalid_manager_callback
  protocol_invalid_manager_rc=$?
  set -e
  [ "$protocol_invalid_manager_rc" -ne 0 ] \
    || fail 'protocol wrapper accepted an invalid manager installation'
  assert_eq 0 "$NOBRAND_LIFECYCLE_LOCK_HELD" \
    'invalid-manager protocol refusal balances lifecycle lock'
)
[ ! -e "$fixture/unexpected-protocol-manager-layout" ] \
  || fail 'protocol wrapper mutated manager layout before callback'
[ ! -e "$fixture/unexpected-protocol-manager-repair" ] \
  || fail 'protocol wrapper repaired manager before callback'
[ ! -e "$fixture/unexpected-invalid-manager-callback" ] \
  || fail 'protocol wrapper ran callback with an invalid manager'
cmp -s "$protocol_invalid_manager_prior" "$NOBRAND_LIFECYCLE_TX_FILE" \
  || fail 'invalid-manager protocol refusal did not restore prior lifecycle metadata'
printf 'PROTOCOL_MANAGER_SCOPE_ISOLATION=PASS\n'

# An unmutated dispatcher recovery has no request to reconstruct and clears
# without invoking the callback. An explicit same-scope command carries fresh
# intent, so it clears the stale record and runs that request immediately.
reset_fixture
write_schema
write_complete_manager "$SCRIPT_VERSION"
nb_lifecycle_begin install prepare 0 0 0 0 0 0 tuic
protocol_unmutated_callback_log="$fixture/protocol-unmutated-callback.log"
(
  require_root() { return 0; }
  require_linux() { return 0; }
  nb_lifecycle_lock_acquire() { NOBRAND_LIFECYCLE_LOCK_HELD=$((NOBRAND_LIFECYCLE_LOCK_HELD + 1)); }
  nb_lifecycle_lock_release() { NOBRAND_LIFECYCLE_LOCK_HELD=$((NOBRAND_LIFECYCLE_LOCK_HELD - 1)); }
  nobrand_manager_installation_valid() { return 0; }
  protocol_unmutated_callback() {
    printf 'called\n' >>"$protocol_unmutated_callback_log"
    nb_lifecycle_mark_protocol_mutation_started tuic
  }
  NOBRAND_MANAGER_SESSION_ACTIVE=1
  NOBRAND_RECOVERY_EXPECTED_SCOPE=tuic
  nb_lifecycle_run_protocol_install tuic protocol_unmutated_callback >/dev/null
  assert_eq 0 "$NOBRAND_LIFECYCLE_LOCK_HELD" \
    'unmutated no-argument protocol recovery balances lifecycle lock'
)
[ ! -e "$protocol_unmutated_callback_log" ] \
  || fail 'unmutated no-argument protocol recovery invoked callback'
[ ! -e "$NOBRAND_LIFECYCLE_TX_FILE" ] \
  || fail 'unmutated no-argument protocol recovery retained metadata'

nb_lifecycle_begin install prepare 0 0 0 0 0 0 tuic
(
  require_root() { return 0; }
  require_linux() { return 0; }
  nb_lifecycle_lock_acquire() { NOBRAND_LIFECYCLE_LOCK_HELD=$((NOBRAND_LIFECYCLE_LOCK_HELD + 1)); }
  nb_lifecycle_lock_release() { NOBRAND_LIFECYCLE_LOCK_HELD=$((NOBRAND_LIFECYCLE_LOCK_HELD - 1)); }
  nobrand_manager_installation_valid() { return 0; }
  protocol_unmutated_callback() {
    printf 'called\n' >>"$protocol_unmutated_callback_log"
    nb_lifecycle_mark_protocol_mutation_started tuic
  }
  NOBRAND_MANAGER_SESSION_ACTIVE=1
  NOBRAND_RECOVERY_EXPECTED_SCOPE=""
  NOBRAND_PROTOCOL_EXPLICIT_RETRY_SCOPE=tuic
  nb_lifecycle_run_protocol_install tuic protocol_unmutated_callback
  assert_eq 0 "$NOBRAND_LIFECYCLE_LOCK_HELD" \
    'explicit unmutated protocol retry balances lifecycle lock'
)
assert_eq 1 "$(wc -l <"$protocol_unmutated_callback_log" | tr -d '[:space:]')" \
  'explicit same-scope retry invokes callback in its first invocation'
assert_eq complete "$(nb_lifecycle_field STATUS)" \
  'explicit same-scope retry completes its fresh transaction'
assert_eq tuic "$(nb_lifecycle_scope)" \
  'explicit same-scope retry remains in TUIC scope'
printf 'PROTOCOL_UNMUTATED_EXPLICIT_RETRY=PASS\n'

# Use the production protocol lifecycle wrapper: once an install has reached
# ready-to-validate, neither an interrupted validation retry nor a failed
# validation retry may call the install callback again or regress the phase.
reset_fixture
protocol_callback_log="$fixture/protocol-ready-validation-callback.log"
(
  require_root() { return 0; }
  require_linux() { return 0; }
  nb_lifecycle_lock_acquire() { NOBRAND_LIFECYCLE_LOCK_HELD=$((NOBRAND_LIFECYCLE_LOCK_HELD + 1)); }
  nb_lifecycle_lock_release() { NOBRAND_LIFECYCLE_LOCK_HELD=$((NOBRAND_LIFECYCLE_LOCK_HELD - 1)); }
  ensure_manager_state_layout() { return 0; }
  nobrand_manager_installation_valid() { return 0; }
  protocol_scope_reconcile_call_count=0
  protocol_scope_reconcile_fail=1
  protocol_scope_validation_call_count=0
  protocol_scope_validation_log="$fixture/protocol-scope-validation.log"
  nb_lifecycle_reconcile_protocol_scope() {
    protocol_scope_reconcile_call_count=$((protocol_scope_reconcile_call_count + 1))
    printf 'reconcile:%s\n' "$1" >>"$protocol_scope_validation_log"
    [ "$protocol_scope_reconcile_fail" -eq 0 ]
  }
  nb_lifecycle_validate_protocol_scope() {
    protocol_scope_validation_call_count=$((protocol_scope_validation_call_count + 1))
    printf 'doctor:%s\n' "$1" >>"$protocol_scope_validation_log"
    [ "$protocol_scope_validation_call_count" -ne 1 ]
  }
  nobrand_install_manager_script() {
    : >"$fixture/unexpected-protocol-manager-reinstall"
    return 0
  }
  protocol_ready_validation_callback() {
    nb_lifecycle_mark_protocol_mutation_started tuic
    printf 'called\n' >>"$protocol_callback_log"
  }
  # Consumed by the sourced protocol lifecycle wrapper.
  # shellcheck disable=SC2034
  NOBRAND_MANAGER_SESSION_ACTIVE=1
  export NOBRAND_TEST_INTERRUPT_INSTALL_AT=ready-to-validate

  set +e
  nb_lifecycle_run_protocol_install tuic protocol_ready_validation_callback
  protocol_initial_interrupt_rc=$?
  set -e
  assert_eq 75 "$protocol_initial_interrupt_rc" \
    'protocol install interrupts after reaching ready-to-validate'
  assert_eq 1 "$(wc -l <"$protocol_callback_log" | tr -d '[:space:]')" \
    'protocol install callback runs exactly once before validation'
  assert_eq ready-to-validate "$(nb_lifecycle_field LAST_COMPLETED_PHASE)" \
    'initial protocol interruption persists ready-to-validate'
  assert_eq 1 "$(nb_lifecycle_mutation_started)" \
    'protocol callback path remains marked as mutating'

  unset NOBRAND_TEST_INTERRUPT_INSTALL_AT
  cp "$NOBRAND_LIFECYCLE_TX_FILE" "$fixture/protocol-ready-before-reconcile.env"
  set +e
  nb_lifecycle_run_protocol_install tuic protocol_ready_validation_callback
  protocol_reconcile_failure_rc=$?
  set -e
  assert_eq 1 "$protocol_reconcile_failure_rc" \
    'validate-only protocol retry propagates reconciliation failure'
  assert_eq 1 "$(wc -l <"$protocol_callback_log" | tr -d '[:space:]')" \
    'failed reconciliation does not rerun callback'
  assert_eq ready-to-validate "$(nb_lifecycle_field LAST_COMPLETED_PHASE)" \
    'failed reconciliation retains ready-to-validate phase'
  assert_eq 0 "$protocol_scope_validation_call_count" \
    'failed reconciliation stops before protocol-scope doctor'
  assert_eq 1 "$protocol_scope_reconcile_call_count" \
    'validate-only retry invokes scoped reconciliation once'
  cmp -s "$fixture/protocol-ready-before-reconcile.env" "$NOBRAND_LIFECYCLE_TX_FILE" \
    || fail 'failed reconciliation modified ready-to-validate metadata'
  assert_eq 0 "$NOBRAND_LIFECYCLE_LOCK_HELD" \
    'failed scoped reconciliation balances lifecycle lock'

  protocol_scope_reconcile_fail=0
  cp "$NOBRAND_LIFECYCLE_TX_FILE" "$fixture/protocol-ready-before-doctor.env"
  set +e
  nb_lifecycle_run_protocol_install tuic protocol_ready_validation_callback
  protocol_validation_failure_rc=$?
  set -e
  assert_eq 1 "$protocol_validation_failure_rc" \
    'validate-only protocol retry propagates validation failure'
  assert_eq 1 "$(wc -l <"$protocol_callback_log" | tr -d '[:space:]')" \
    'failed validate-only retry does not rerun callback'
  assert_eq ready-to-validate "$(nb_lifecycle_field LAST_COMPLETED_PHASE)" \
    'failed validate-only retry does not regress phase'
  assert_eq in-progress "$(nb_lifecycle_field STATUS)" \
    'failed validate-only retry leaves recovery in progress'
  assert_eq 1 "$protocol_scope_validation_call_count" \
    'failed validate-only retry invokes protocol-scope validator once'
  cmp -s "$fixture/protocol-ready-before-doctor.env" "$NOBRAND_LIFECYCLE_TX_FILE" \
    || fail 'failed protocol doctor modified ready-to-validate metadata'
  assert_eq 0 "$NOBRAND_LIFECYCLE_LOCK_HELD" \
    'failed post-reconciliation doctor balances lifecycle lock'

  nb_lifecycle_run_protocol_install tuic protocol_ready_validation_callback
  assert_eq 1 "$(wc -l <"$protocol_callback_log" | tr -d '[:space:]')" \
    'successful later validation still does not rerun callback'
  assert_eq 2 "$protocol_scope_validation_call_count" \
    'successful later retry invokes protocol-scope validator again'
  assert_eq 3 "$protocol_scope_reconcile_call_count" \
    'every validate-only retry reconciles only its recorded scope'
  assert_eq $'reconcile:tuic\nreconcile:tuic\ndoctor:tuic\nreconcile:tuic\ndoctor:tuic' \
    "$(cat "$protocol_scope_validation_log")" \
    'validate-only retries reconcile before doctor in the recorded protocol scope'
  assert_eq complete "$(nb_lifecycle_field STATUS)" \
    'successful validate-only retry completes protocol transaction'
  assert_eq complete "$(nb_lifecycle_field LAST_COMPLETED_PHASE)" \
    'successful validate-only retry records completion'
  assert_eq tuic "$(nb_lifecycle_scope)" \
    'successful validate-only retry preserves protocol scope'
  assert_eq 0 "$NOBRAND_LIFECYCLE_LOCK_HELD" \
    'protocol validation retries leave lock depth balanced'
)
[ ! -e "$fixture/unexpected-protocol-manager-reinstall" ] \
  || fail 'protocol validation retry unexpectedly reinstalled the manager'
nb_lifecycle_tx_valid || fail 'completed validate-only protocol transaction is invalid'
printf 'PROTOCOL_READY_TO_VALIDATE_RETRY=PASS\n'

# A callback may durably commit authoritative state and then fail before its
# ready-to-validate checkpoint. Recovery must recognize the changed valid state,
# validate every committed instance, and never replay the mutating callback.
reset_fixture
tuic_committed_callback_log="$fixture/tuic-committed-callback.log"
tuic_committed_validation_log="$fixture/tuic-committed-validation.log"
(
  require_root() { return 0; }
  require_linux() { return 0; }
  nb_lifecycle_lock_acquire() { NOBRAND_LIFECYCLE_LOCK_HELD=$((NOBRAND_LIFECYCLE_LOCK_HELD + 1)); }
  nb_lifecycle_lock_release() { NOBRAND_LIFECYCLE_LOCK_HELD=$((NOBRAND_LIFECYCLE_LOCK_HELD - 1)); }
  ensure_manager_state_layout() { return 0; }
  nobrand_manager_installation_valid() { return 0; }
  tuic_state_exists() {
    local instance_id="$1"
    printf 'state:%s\n' "$instance_id" >>"$tuic_committed_validation_log"
    jq -e --arg instance_id "$instance_id" \
      '.instance_id==$instance_id and .fixture_valid==true' \
      "$NOBRAND_TUIC_STATE_DIR/$instance_id/state.json" >/dev/null
  }
  tuic_instance_ids() {
    printf '%s\n' t1111111111111111 t2222222222222222
  }
  tuic_doctor_all() {
    jq -e '.instance_id=="t1111111111111111" and .fixture_valid==true' \
      "$NOBRAND_TUIC_STATE_DIR/t1111111111111111/state.json" >/dev/null
    jq -e '.instance_id=="t2222222222222222" and .fixture_valid==true' \
      "$NOBRAND_TUIC_STATE_DIR/t2222222222222222/state.json" >/dev/null
    printf 'doctor\n' >>"$tuic_committed_validation_log"
  }
  nb_lifecycle_reconcile_protocol_scope() {
    assert_eq tuic "$1" 'changed-state reconciliation remains in TUIC scope'
    printf 'reconcile:%s\n' "$1" >>"$tuic_committed_validation_log"
  }
  tuic_commit_then_fail_callback() {
    local instance_id
    printf 'called\n' >>"$tuic_committed_callback_log"
    nb_lifecycle_mark_protocol_mutation_started tuic
    for instance_id in t1111111111111111 t2222222222222222; do
      mkdir -p "$NOBRAND_TUIC_STATE_DIR/$instance_id"
      printf '{"instance_id":"%s","fixture_valid":true}\n' "$instance_id" \
        >"$NOBRAND_TUIC_STATE_DIR/$instance_id/state.json"
    done
    return 71
  }
  # Consumed by the sourced protocol lifecycle wrapper.
  # shellcheck disable=SC2034
  NOBRAND_MANAGER_SESSION_ACTIVE=1
  set +e
  nb_lifecycle_run_protocol_install tuic tuic_commit_then_fail_callback
  tuic_committed_initial_rc=$?
  set -e
  assert_eq 71 "$tuic_committed_initial_rc" \
    'TUIC callback failure after committed multi-instance state propagates'
  tuic_committed_phase="$(nb_lifecycle_field LAST_COMPLETED_PHASE)"
  [[ "$tuic_committed_phase" =~ ^callback-[0-9a-f]{55}$ ]] \
    || fail 'TUIC committed callback did not retain an exact callback fingerprint phase'
  assert_eq 64 "${#tuic_committed_phase}" \
    'TUIC committed callback phase length'
  assert_eq 1 "$(wc -l <"$tuic_committed_callback_log" | tr -d '[:space:]')" \
    'TUIC committed callback runs once before recovery'

  : >"$tuic_committed_validation_log"
  NOBRAND_RECOVERY_EXPECTED_SCOPE=tuic
  nb_lifecycle_run_protocol_install tuic tuic_commit_then_fail_callback
  assert_eq 1 "$(wc -l <"$tuic_committed_callback_log" | tr -d '[:space:]')" \
    'TUIC changed-state recovery does not replay callback'
  assert_eq $'state:t1111111111111111\nstate:t2222222222222222\nreconcile:tuic\nstate:t1111111111111111\nstate:t2222222222222222\ndoctor' \
    "$(cat "$tuic_committed_validation_log")" \
    'TUIC no-argument recovery reconciles its valid scope before doctor'
  [ -f "$NOBRAND_TUIC_STATE_DIR/t1111111111111111/state.json" ] \
    && [ -f "$NOBRAND_TUIC_STATE_DIR/t2222222222222222/state.json" ] \
    || fail 'TUIC recovery removed committed multi-instance state'
  assert_eq complete "$(nb_lifecycle_field STATUS)" \
    'TUIC changed-state recovery completes transaction'
  assert_eq complete "$(nb_lifecycle_field LAST_COMPLETED_PHASE)" \
    'TUIC changed-state recovery records completion'
  assert_eq tuic "$(nb_lifecycle_scope)" \
    'TUIC changed-state recovery preserves scope'
  assert_eq 0 "$NOBRAND_LIFECYCLE_LOCK_HELD" \
    'TUIC changed-state recovery balances lifecycle lock'
)

# Changed malformed state is not an unchanged callback baseline and is not safe
# to validate. It must fail closed before either callback replay or phase writes.
reset_fixture
tuic_malformed_callback_log="$fixture/tuic-malformed-callback.log"
tuic_malformed_unexpected_doctor="$fixture/tuic-malformed-unexpected-doctor"
tuic_malformed_expected_tx="$fixture/tuic-malformed-transaction.expected"
(
  require_root() { return 0; }
  require_linux() { return 0; }
  nb_lifecycle_lock_acquire() { NOBRAND_LIFECYCLE_LOCK_HELD=$((NOBRAND_LIFECYCLE_LOCK_HELD + 1)); }
  nb_lifecycle_lock_release() { NOBRAND_LIFECYCLE_LOCK_HELD=$((NOBRAND_LIFECYCLE_LOCK_HELD - 1)); }
  ensure_manager_state_layout() { return 0; }
  nobrand_manager_installation_valid() { return 0; }
  tuic_state_exists() {
    jq -e . "$NOBRAND_TUIC_STATE_DIR/$1/state.json" >/dev/null 2>&1
  }
  tuic_instance_ids() { printf '%s\n' t3333333333333333; }
  tuic_doctor_all() { : >"$tuic_malformed_unexpected_doctor"; }
  tuic_malformed_callback() {
    printf 'called\n' >>"$tuic_malformed_callback_log"
    nb_lifecycle_mark_protocol_mutation_started tuic
    mkdir -p "$NOBRAND_TUIC_STATE_DIR/t3333333333333333"
    printf '%s\n' '{malformed-json' \
      >"$NOBRAND_TUIC_STATE_DIR/t3333333333333333/state.json"
    return 72
  }
  # Consumed by the sourced protocol lifecycle wrapper.
  # shellcheck disable=SC2034
  NOBRAND_MANAGER_SESSION_ACTIVE=1
  set +e
  nb_lifecycle_run_protocol_install tuic tuic_malformed_callback
  tuic_malformed_initial_rc=$?
  set -e
  assert_eq 72 "$tuic_malformed_initial_rc" \
    'TUIC malformed-state callback failure propagates'
  tuic_malformed_phase="$(nb_lifecycle_field LAST_COMPLETED_PHASE)"
  [[ "$tuic_malformed_phase" =~ ^callback-[0-9a-f]{55}$ ]] \
    || fail 'TUIC malformed-state callback did not retain callback fingerprint phase'
  cp "$NOBRAND_LIFECYCLE_TX_FILE" "$tuic_malformed_expected_tx"

  set +e
  nb_lifecycle_run_protocol_install tuic tuic_malformed_callback
  tuic_malformed_recovery_rc=$?
  set -e
  [ "$tuic_malformed_recovery_rc" -ne 0 ] \
    || fail 'changed malformed TUIC state did not fail closed'
  assert_eq 1 "$(wc -l <"$tuic_malformed_callback_log" | tr -d '[:space:]')" \
    'changed malformed TUIC state does not replay callback'
  [ ! -e "$tuic_malformed_unexpected_doctor" ] \
    || fail 'changed malformed TUIC state reached runtime validation'
  cmp -s "$tuic_malformed_expected_tx" "$NOBRAND_LIFECYCLE_TX_FILE" \
    || fail 'changed malformed TUIC state modified transaction bytes'
  assert_eq "$tuic_malformed_phase" "$(nb_lifecycle_field LAST_COMPLETED_PHASE)" \
    'changed malformed TUIC state preserves callback phase'
  assert_eq in-progress "$(nb_lifecycle_field STATUS)" \
    'changed malformed TUIC state remains in progress'
  assert_eq install "$(nb_lifecycle_field OPERATION)" \
    'changed malformed TUIC state preserves install operation'
  assert_eq tuic "$(nb_lifecycle_scope)" \
    'changed malformed TUIC state preserves scope'
  assert_eq 1 "$(nb_lifecycle_mutation_started)" \
    'changed malformed TUIC state preserves mutation marker'
  nb_lifecycle_tx_valid \
    || fail 'changed malformed TUIC state corrupted transaction metadata'
  assert_eq 0 "$NOBRAND_LIFECYCLE_LOCK_HELD" \
    'changed malformed TUIC recovery balances lifecycle lock'
)
printf 'CALLBACK_COMMIT_REPLAY_GUARD=PASS\n'

# Callback return values are not mutation proof. Both failure and success before
# the callback-owned marker must restore the exact completed lifecycle record.
for callback_no_marker_result in failure success; do
  reset_fixture
  write_schema
  write_complete_manager "$SCRIPT_VERSION"
  nb_lifecycle_begin install prepare 0 0 0 0 0 0 manager
  nb_lifecycle_mark_mutation_started
  nb_lifecycle_complete install
  callback_no_marker_prior="$fixture/callback-no-marker-${callback_no_marker_result}.prior"
  cp "$NOBRAND_LIFECYCLE_TX_FILE" "$callback_no_marker_prior"
  (
    require_root() { return 0; }
    require_linux() { return 0; }
    nb_lifecycle_lock_acquire() { NOBRAND_LIFECYCLE_LOCK_HELD=$((NOBRAND_LIFECYCLE_LOCK_HELD + 1)); }
    nb_lifecycle_lock_release() { NOBRAND_LIFECYCLE_LOCK_HELD=$((NOBRAND_LIFECYCLE_LOCK_HELD - 1)); }
    ensure_manager_state_layout() { return 0; }
    nobrand_manager_installation_valid() { return 0; }
    callback_without_marker() {
      : >"$fixture/callback-no-marker-${callback_no_marker_result}.called"
      [ "$callback_no_marker_result" = success ] || return 78
    }
    NOBRAND_MANAGER_SESSION_ACTIVE=1
    set +e
    nb_lifecycle_run_protocol_install tuic callback_without_marker
    callback_no_marker_rc=$?
    set -e
    if [ "$callback_no_marker_result" = failure ]; then
      assert_eq 78 "$callback_no_marker_rc" \
        'pre-mutation protocol callback failure propagates'
    else
      assert_eq 0 "$callback_no_marker_rc" \
        'successful callback without a mutation marker remains a successful no-op'
    fi
    assert_eq 0 "$NOBRAND_LIFECYCLE_LOCK_HELD" \
      'callback without marker balances lifecycle lock'
  )
  [ -e "$fixture/callback-no-marker-${callback_no_marker_result}.called" ] \
    || fail "${callback_no_marker_result} callback-without-marker fixture did not run"
  cmp -s "$callback_no_marker_prior" "$NOBRAND_LIFECYCLE_TX_FILE" \
    || fail "${callback_no_marker_result} callback without marker changed prior lifecycle metadata"
done
printf 'PROTOCOL_CALLBACK_PREMUTATION_RESTORE=PASS\n'

# MUTATION_STARTED can belong to a previous failed attempt. A successful
# explicit retry that never reaches this attempt's marker must retain the exact
# callback fingerprint and may not validate or complete against baseline state.
reset_fixture
callback_retry_noop_log="$fixture/callback-retry-noop.log"
callback_retry_unexpected_validation="$fixture/callback-retry-unexpected-validation"
(
  require_root() { return 0; }
  require_linux() { return 0; }
  nb_lifecycle_lock_acquire() { NOBRAND_LIFECYCLE_LOCK_HELD=$((NOBRAND_LIFECYCLE_LOCK_HELD + 1)); }
  nb_lifecycle_lock_release() { NOBRAND_LIFECYCLE_LOCK_HELD=$((NOBRAND_LIFECYCLE_LOCK_HELD - 1)); }
  ensure_manager_state_layout() { return 0; }
  nobrand_manager_installation_valid() { return 0; }
  nb_lifecycle_validate_protocol_scope() { : >"$callback_retry_unexpected_validation"; }
  callback_retry_then_noop() {
    local call_count
    printf 'called\n' >>"$callback_retry_noop_log"
    call_count="$(wc -l <"$callback_retry_noop_log" | tr -d '[:space:]')"
    if [ "$call_count" -eq 1 ]; then
      nb_lifecycle_mark_protocol_mutation_started tuic
      return 79
    fi
    return 0
  }
  NOBRAND_MANAGER_SESSION_ACTIVE=1
  set +e
  nb_lifecycle_run_protocol_install tuic callback_retry_then_noop
  callback_retry_initial_rc=$?
  set -e
  assert_eq 79 "$callback_retry_initial_rc" \
    'initial marked callback failure propagates'
  callback_retry_phase="$(nb_lifecycle_field LAST_COMPLETED_PHASE)"
  [[ "$callback_retry_phase" =~ ^callback-[0-9a-f]{55}$ ]] \
    || fail 'marked callback failure did not retain callback fingerprint'
  cp "$NOBRAND_LIFECYCLE_TX_FILE" "$fixture/callback-retry-noop.prior"

  NOBRAND_PROTOCOL_EXPLICIT_RETRY_SCOPE=tuic
  set +e
  nb_lifecycle_run_protocol_install tuic callback_retry_then_noop
  callback_retry_noop_rc=$?
  set -e
  [ "$callback_retry_noop_rc" -ne 0 ] \
    || fail 'no-op explicit retry falsely completed a prior mutation'
  assert_eq 2 "$(wc -l <"$callback_retry_noop_log" | tr -d '[:space:]')" \
    'explicit retry invokes the callback once'
  [ ! -e "$callback_retry_unexpected_validation" ] \
    || fail 'no-op explicit retry reached protocol validation'
  cmp -s "$fixture/callback-retry-noop.prior" "$NOBRAND_LIFECYCLE_TX_FILE" \
    || fail 'no-op explicit retry modified the callback recovery point'
  assert_eq "$callback_retry_phase" "$(nb_lifecycle_field LAST_COMPLETED_PHASE)" \
    'no-op explicit retry preserves callback phase'
  assert_eq in-progress "$(nb_lifecycle_field STATUS)" \
    'no-op explicit retry remains recoverable'
)
printf 'PROTOCOL_CALLBACK_ATTEMPT_PROOF=PASS\n'

# A ready-to-validate transaction still needs whole-scope structural validity.
# A doctor that enumerates only the old valid instance may not hide a malformed
# new matching instance and cause recovery completion.
reset_fixture
mkdir -p "$NOBRAND_TUIC_STATE_DIR/t1111111111111111" \
  "$NOBRAND_TUIC_STATE_DIR/t9999999999999999"
printf '%s\n' '{"instance_id":"t1111111111111111","fixture_valid":true}' \
  >"$NOBRAND_TUIC_STATE_DIR/t1111111111111111/state.json"
printf '%s\n' '{malformed-json' \
  >"$NOBRAND_TUIC_STATE_DIR/t9999999999999999/state.json"
nb_lifecycle_begin install ready-to-validate 0 0 0 0 0 0 tuic
nb_lifecycle_mark_mutation_started
(
  require_root() { return 0; }
  require_linux() { return 0; }
  nb_lifecycle_lock_acquire() { NOBRAND_LIFECYCLE_LOCK_HELD=$((NOBRAND_LIFECYCLE_LOCK_HELD + 1)); }
  nb_lifecycle_lock_release() { NOBRAND_LIFECYCLE_LOCK_HELD=$((NOBRAND_LIFECYCLE_LOCK_HELD - 1)); }
  ensure_manager_state_layout() { return 0; }
  nobrand_manager_installation_valid() { return 0; }
  tuic_state_exists() {
    jq -e --arg instance_id "$1" \
      '.instance_id==$instance_id and .fixture_valid==true' \
      "$NOBRAND_TUIC_STATE_DIR/$1/state.json" >/dev/null 2>&1
  }
  tuic_instance_ids() { printf '%s\n' t1111111111111111; }
  tuic_doctor_all() { : >"$fixture/ready-malformed-unexpected-doctor"; }
  ready_malformed_callback() { : >"$fixture/ready-malformed-unexpected-callback"; }
  NOBRAND_MANAGER_SESSION_ACTIVE=1
  set +e
  nb_lifecycle_run_protocol_install tuic ready_malformed_callback
  ready_malformed_rc=$?
  set -e
  [ "$ready_malformed_rc" -ne 0 ] \
    || fail 'ready-to-validate recovery ignored malformed scoped state'
)
[ ! -e "$fixture/ready-malformed-unexpected-callback" ] \
  || fail 'ready-to-validate malformed recovery replayed callback'
[ ! -e "$fixture/ready-malformed-unexpected-doctor" ] \
  || fail 'ready-to-validate malformed recovery reached doctor'
assert_eq ready-to-validate "$(nb_lifecycle_field LAST_COMPLETED_PHASE)" \
  'structurally invalid ready recovery retains phase'
assert_eq in-progress "$(nb_lifecycle_field STATUS)" \
  'structurally invalid ready recovery remains in progress'
printf 'PROTOCOL_READY_STRUCTURAL_GATE=PASS\n'

# Snell's status enumerator deliberately skips an identity-invalid JSON object.
# Whole-scope recovery must still reject a mixed valid+malformed directory.
reset_fixture
mkdir -p "$NOBRAND_SNELL_STATE_DIR"
printf '%s\n' \
  '{"protocol":"snell","instance_id":"s1111111111111111","name":"fixture-snell","version":4,"psk":"fixture-psk","listen_host":"0.0.0.0","listen_port":31001,"transport":"tcp","advertise_mode":"auto","advertise_host":"","advertise_port":"","enabled":true,"quic_proxy_enabled":false,"managed_udp":false,"runtime_version":"4.1.1","runtime_status":"Stable","created_at":"2026-09-04T00:00:00Z","updated_at":"2026-09-04T00:00:00Z"}' \
  >"$NOBRAND_SNELL_STATE_DIR/s1111111111111111.json"
printf '%s\n' '{}' >"$NOBRAND_SNELL_STATE_DIR/s2222222222222222.json"
nb_lifecycle_begin install ready-to-validate 0 0 0 0 0 0 snell
nb_lifecycle_mark_mutation_started
cp "$NOBRAND_LIFECYCLE_TX_FILE" "$fixture/snell-mixed-structural.expected"
(
  # shellcheck disable=SC1091
  source "$TEST_ROOT/src/16-core-ingress.sh"
  # shellcheck disable=SC1091
  source "$TEST_ROOT/src/25-network-mtu.sh"
  # shellcheck disable=SC1091
  source "$TEST_ROOT/src/16-core-port.sh"
  # shellcheck disable=SC1091
  source "$TEST_ROOT/src/17-core-endpoint.sh"
  # shellcheck disable=SC1091
  source "$TEST_ROOT/src/56-snell.sh"
  require_root() { return 0; }
  require_linux() { return 0; }
  nb_lifecycle_lock_acquire() { NOBRAND_LIFECYCLE_LOCK_HELD=$((NOBRAND_LIFECYCLE_LOCK_HELD + 1)); }
  nb_lifecycle_lock_release() { NOBRAND_LIFECYCLE_LOCK_HELD=$((NOBRAND_LIFECYCLE_LOCK_HELD - 1)); }
  ensure_manager_state_layout() { return 0; }
  nobrand_manager_installation_valid() { return 0; }
  snell_state_valid s1111111111111111 \
    || fail 'mixed Snell fixture valid sibling failed production validation'
  snell_doctor_all() { : >"$fixture/snell-mixed-unexpected-doctor"; }
  snell_mixed_callback() { : >"$fixture/snell-mixed-unexpected-callback"; }
  NOBRAND_MANAGER_SESSION_ACTIVE=1
  set +e
  nb_lifecycle_run_protocol_install snell snell_mixed_callback
  snell_mixed_rc=$?
  set -e
  [ "$snell_mixed_rc" -ne 0 ] \
    || fail 'mixed valid+malformed Snell recovery completed'
)
[ ! -e "$fixture/snell-mixed-unexpected-callback" ] \
  || fail 'mixed malformed Snell recovery replayed callback'
[ ! -e "$fixture/snell-mixed-unexpected-doctor" ] \
  || fail 'mixed malformed Snell recovery reached forgiving doctor enumeration'
cmp -s "$fixture/snell-mixed-structural.expected" "$NOBRAND_LIFECYCLE_TX_FILE" \
  || fail 'mixed malformed Snell recovery changed lifecycle metadata'
printf 'SNELL_MIXED_STRUCTURAL_GATE=PASS\n'

# Recovery reconciles the complete authoritative scope. Persisted disabled
# instances must be stopped and listener-free, while enabled siblings are
# started and receive their normal runtime doctor. No install callback is
# available or replayed at this validation-only checkpoint.
run_disabled_scope_recovery_fixture() {
  local scope="$1" recovery_log
  recovery_log="$fixture/disabled-${scope}.log"
  reset_fixture
  write_schema
  write_complete_manager "$SCRIPT_VERSION"
  nb_lifecycle_begin install ready-to-validate 0 0 0 0 0 0 "$scope"
  nb_lifecycle_mark_mutation_started
  (
    require_root() { return 0; }
    require_linux() { return 0; }
    nb_lifecycle_lock_acquire() { NOBRAND_LIFECYCLE_LOCK_HELD=$((NOBRAND_LIFECYCLE_LOCK_HELD + 1)); }
    nb_lifecycle_lock_release() { NOBRAND_LIFECYCLE_LOCK_HELD=$((NOBRAND_LIFECYCLE_LOCK_HELD - 1)); }
    admin_lock_acquire() { _ADMIN_LOCK_HELD=$((${_ADMIN_LOCK_HELD:-0} + 1)); }
    admin_lock_release() { _ADMIN_LOCK_HELD=$((_ADMIN_LOCK_HELD - 1)); }
    nobrand_manager_installation_valid() { return 0; }
    nb_lifecycle_protocol_scope_state_valid() { return 0; }
    nb_firewall_open_pairs() { printf 'firewall:%s\n' "$1" >>"$recovery_log"; }
    nb_port_is_listening() {
      printf 'probe:%s:%s\n' "$1" "$2" >>"$recovery_log"
      return 1
    }
    nobrand_xray_test_config() { return 0; }

    snell_instance_ids() { printf '%s\n' s0000000000000001 s0000000000000002; }
    snell_state_field() {
      case "$1:$2" in
        s0000000000000001:enabled) printf false ;;
        s0000000000000002:enabled) printf true ;;
        s0000000000000001:listen_port) printf 32101 ;;
        s0000000000000002:listen_port) printf 32102 ;;
        *) return 1 ;;
      esac
    }
    snell_config_matches_state() { return 0; }
    snell_firewall_pairs() { printf 'TCP|%s\n' "$(snell_state_field "$1" listen_port)"; }
    snell_install_service_runtime() { return 0; }
    snell_ensure_openrc_service() { return 0; }
    snell_service_action() { printf 'service:snell:%s:%s\n' "$1" "$2" >>"$recovery_log"; }
    snell_wait_for_required_listeners() { return 0; }
    snell_service_active() { return 1; }
    snell_quic_proxy_enabled() { return 1; }
    snell_doctor_instance() {
      if [ "$(snell_state_field "$1" enabled)" = false ]; then
        ! snell_service_active "$1" && ! nb_port_is_listening TCP "$(snell_state_field "$1" listen_port)" \
          || return 1
      fi
      printf 'doctor:snell:%s\n' "$1" >>"$recovery_log"
    }
    snell_doctor_all() {
      local id
      while IFS= read -r id; do snell_doctor_instance "$id" || return 1; done < <(snell_instance_ids)
    }

    hysteria2_state_exists() { return 0; }
    hysteria2_state_field() {
      case "$1" in enabled) printf false ;; listen_port) printf 32103 ;; *) return 1 ;; esac
    }
    nobrand_write_hy2_service() { return 0; }
    nobrand_hy2_service_action() { printf 'service:hy2:%s\n' "$1" >>"$recovery_log"; }
    nobrand_hy2_service_active() { return 1; }
    hysteria2_running() { return 0; }
    hysteria2_doctor() {
      ! nobrand_hy2_service_active \
        && ! nb_port_is_listening UDP "$(hysteria2_state_field listen_port)" || return 1
      printf 'doctor:hy2\n' >>"$recovery_log"
    }

    tuic_instance_ids() { printf '%s\n' t0000000000000001 t0000000000000002; }
    tuic_state_field() {
      case "$1:$2" in
        t0000000000000001:enabled) printf false ;;
        t0000000000000002:enabled) printf true ;;
        t0000000000000001:listen_port) printf 32104 ;;
        t0000000000000002:listen_port) printf 32105 ;;
        *) return 1 ;;
      esac
    }
    tuic_config_matches_state() { return 0; }
    tuic_config_file() { printf '%s/%s.json' "$fixture" "$1"; }
    tuic_validate_config() { return 0; }
    tuic_restore_runtime() { return 0; }
    tuic_ensure_openrc_service() { return 0; }
    tuic_service_action() { printf 'service:tuic:%s:%s\n' "$1" "$2" >>"$recovery_log"; }
    tuic_running() { return 0; }
    tuic_service_active() { return 1; }
    tuic_doctor_one() {
      if [ "$(tuic_state_field "$1" enabled)" = false ]; then
        ! tuic_service_active "$1" && ! nb_port_is_listening UDP "$(tuic_state_field "$1" listen_port)" \
          || return 1
      fi
      printf 'doctor:tuic:%s\n' "$1" >>"$recovery_log"
    }
    tuic_doctor_all() {
      local id
      while IFS= read -r id; do tuic_doctor_one "$id" || return 1; done < <(tuic_instance_ids)
    }

    reality_instance_ids() { printf '%s\n' r0000000000000001 r0000000000000002; }
    reality_state_field() {
      case "$1:$2" in
        r0000000000000001:enabled) printf false ;;
        r0000000000000002:enabled) printf true ;;
        r0000000000000001:listen_port) printf 32106 ;;
        r0000000000000002:listen_port) printf 32107 ;;
        r0000000000000001:defender_port) printf 32116 ;;
        r0000000000000002:defender_port) printf 32117 ;;
        *) return 1 ;;
      esac
    }
    reality_config_matches_state() { return 0; }
    reality_config_file() { printf '%s/%s.json' "$fixture" "$1"; }
    reality_install_service_runtime() { return 0; }
    reality_ensure_openrc_service() { return 0; }
    reality_service_action() { printf 'service:reality:%s:%s\n' "$1" "$2" >>"$recovery_log"; }
    reality_running() { return 0; }
    reality_service_active() { return 1; }
    reality_doctor_one() {
      if [ "$(reality_state_field "$1" enabled)" = false ]; then
        ! reality_service_active "$1" \
          && ! nb_port_is_listening TCP "$(reality_state_field "$1" listen_port)" \
          && ! nb_port_is_listening TCP "$(reality_state_field "$1" defender_port)" || return 1
      fi
      printf 'doctor:reality:%s\n' "$1" >>"$recovery_log"
    }
    reality_doctor_all() {
      local id
      while IFS= read -r id; do reality_doctor_one "$id" || return 1; done < <(reality_instance_ids)
    }

    vless_sudoku_state_exists() { return 0; }
    vless_sudoku_state_field() {
      case "$1" in enabled) printf false ;; listen_port) printf 32108 ;; *) return 1 ;; esac
    }
    vless_sudoku_server_config_matches() { return 0; }
    vless_sudoku_client_config_matches() { return 0; }
    nobrand_write_vless_sudoku_service() { return 0; }
    nobrand_vless_sudoku_service_action() { printf 'service:sudoku:%s\n' "$1" >>"$recovery_log"; }
    nobrand_vless_sudoku_service_active() { return 1; }
    vless_sudoku_running() { return 0; }
    vless_sudoku_doctor() {
      ! nobrand_vless_sudoku_service_active \
        && ! nb_port_is_listening TCP "$(vless_sudoku_state_field listen_port)" || return 1
      printf 'doctor:sudoku\n' >>"$recovery_log"
    }

    disabled_recovery_unexpected_callback() {
      : >"$fixture/disabled-${scope}-unexpected-callback"
      return 1
    }
    NOBRAND_MANAGER_SESSION_ACTIVE=1
    NOBRAND_LIFECYCLE_LOCK_HELD=0
    _ADMIN_LOCK_HELD=0
    nb_lifecycle_run_protocol_install "$scope" disabled_recovery_unexpected_callback
    assert_eq 0 "$NOBRAND_LIFECYCLE_LOCK_HELD" \
      "disabled ${scope} recovery balances lifecycle lock"
    assert_eq 0 "$_ADMIN_LOCK_HELD" \
      "disabled ${scope} recovery balances admin lock"
  )
  [ ! -e "$fixture/disabled-${scope}-unexpected-callback" ] \
    || fail "disabled ${scope} recovery replayed install callback"
  assert_eq complete "$(nb_lifecycle_field STATUS)" \
    "disabled ${scope} recovery completes"
  case "$scope" in
    snell)
      grep -qxF 'service:snell:s0000000000000001:stop' "$recovery_log" \
        || fail 'disabled Snell sibling was not stopped'
      grep -qxF 'service:snell:s0000000000000002:start' "$recovery_log" \
        || fail 'enabled Snell sibling was not started'
      grep -qxF 'doctor:snell:s0000000000000002' "$recovery_log" \
        || fail 'enabled Snell sibling was not diagnosed'
      grep -qxF 'doctor:snell:s0000000000000001' "$recovery_log" \
        || fail 'disabled Snell sibling missed static doctor checks'
      ;;
    hy2)
      grep -qxF 'service:hy2:stop' "$recovery_log" || fail 'disabled HY2 was not stopped'
      grep -qxF 'doctor:hy2' "$recovery_log" \
        || fail 'disabled HY2 missed static doctor checks'
      ;;
    tuic)
      grep -qxF 'service:tuic:t0000000000000001:stop' "$recovery_log" \
        || fail 'disabled TUIC sibling was not stopped'
      grep -qxF 'service:tuic:t0000000000000002:start' "$recovery_log" \
        || fail 'enabled TUIC sibling was not started'
      grep -qxF 'doctor:tuic:t0000000000000002' "$recovery_log" \
        || fail 'enabled TUIC sibling was not diagnosed'
      grep -qxF 'doctor:tuic:t0000000000000001' "$recovery_log" \
        || fail 'disabled TUIC sibling missed static doctor checks'
      ;;
    vless-reality)
      grep -qxF 'service:reality:r0000000000000001:stop' "$recovery_log" \
        || fail 'disabled REALITY sibling was not stopped'
      grep -qxF 'service:reality:r0000000000000002:start' "$recovery_log" \
        || fail 'enabled REALITY sibling was not started'
      grep -qxF 'doctor:reality:r0000000000000002' "$recovery_log" \
        || fail 'enabled REALITY sibling was not diagnosed'
      grep -qxF 'doctor:reality:r0000000000000001' "$recovery_log" \
        || fail 'disabled REALITY sibling missed static doctor checks'
      ;;
    vless-sudoku)
      grep -qxF 'service:sudoku:stop' "$recovery_log" \
        || fail 'disabled Sudoku was not stopped'
      grep -qxF 'doctor:sudoku' "$recovery_log" \
        || fail 'disabled Sudoku missed static doctor checks'
      ;;
  esac
  grep -q '^probe:' "$recovery_log" \
    || fail "disabled ${scope} recovery did not check for residual listeners"
}

for disabled_scope in snell hy2 tuic vless-reality vless-sudoku; do
  run_disabled_scope_recovery_fixture "$disabled_scope"
done
printf 'PROTOCOL_DISABLED_STATE_RECOVERY=PASS\n'

# A non-empty committed SSH state is safe to verify without reconstructing
# accounts, keys, or policy. Cover both the ordinary ready checkpoint and a
# callback fingerprint whose authoritative state changed before interruption.
run_valid_ssh_recovery_fixture() {
  local mode="$1" baseline ssh_log
  ssh_log="$fixture/ssh-${mode}.log"
  reset_fixture
  write_schema
  write_complete_manager "$SCRIPT_VERSION"
  if [ "$mode" = changed-valid ]; then
    baseline="$(nb_lifecycle_protocol_scope_fingerprint ssh-tunnel)"
    nb_lifecycle_begin install "callback-${baseline:0:55}" 0 0 0 0 0 0 ssh-tunnel
  else
    nb_lifecycle_begin install ready-to-validate 0 0 0 0 0 0 ssh-tunnel
  fi
  nb_lifecycle_mark_mutation_started
  mkdir -p "$(dirname "$NOBRAND_SSH_STATE_FILE")"
  printf '%s\n' \
    '{"users":[{"account_id":"a1111111111111111","linux_user":"nbt-fixture"}]}' \
    >"$NOBRAND_SSH_STATE_FILE"
  (
    require_root() { return 0; }
    require_linux() { return 0; }
    nb_lifecycle_lock_acquire() { NOBRAND_LIFECYCLE_LOCK_HELD=$((NOBRAND_LIFECYCLE_LOCK_HELD + 1)); }
    nb_lifecycle_lock_release() { NOBRAND_LIFECYCLE_LOCK_HELD=$((NOBRAND_LIFECYCLE_LOCK_HELD - 1)); }
    nobrand_manager_installation_valid() { return 0; }
    nb_lifecycle_protocol_scope_state_valid() { [ "$1" = ssh-tunnel ]; }
    ssh_tunnel_watchdog_directory_empty_valid() { printf 'watchdog\n' >>"$ssh_log"; }
    ssh_tunnel_group_identity_valid() { printf 'group\n' >>"$ssh_log"; }
    ssh_tunnel_user_identity_valid() { printf 'identity:%s\n' "$(jq -r .account_id <<<"$1")" >>"$ssh_log"; }
    ssh_tunnel_user_key_material_valid() { printf 'keys:%s\n' "$(jq -r .account_id <<<"$1")" >>"$ssh_log"; }
    ssh_tunnel_state_exists() { return 0; }
    ssh_tunnel_doctor() { printf 'doctor\n' >>"$ssh_log"; }
    ssh_recovery_unexpected_callback() { : >"$fixture/ssh-${mode}-unexpected-callback"; }
    NOBRAND_MANAGER_SESSION_ACTIVE=1
    NOBRAND_LIFECYCLE_LOCK_HELD=0
    nb_lifecycle_run_protocol_install ssh-tunnel ssh_recovery_unexpected_callback
    assert_eq 0 "$NOBRAND_LIFECYCLE_LOCK_HELD" \
      "valid SSH ${mode} recovery balances lifecycle lock"
  )
  [ ! -e "$fixture/ssh-${mode}-unexpected-callback" ] \
    || fail "valid SSH ${mode} recovery replayed callback"
  assert_eq $'watchdog\ngroup\nidentity:a1111111111111111\nkeys:a1111111111111111\ndoctor' \
    "$(cat "$ssh_log")" "valid SSH ${mode} recovery is verification-only"
  assert_eq complete "$(nb_lifecycle_field STATUS)" \
    "valid SSH ${mode} recovery completes"
  assert_eq ssh-tunnel "$(nb_lifecycle_scope)" \
    "valid SSH ${mode} recovery preserves scope"
}

run_valid_ssh_recovery_fixture ready
run_valid_ssh_recovery_fixture changed-valid
printf 'SSH_VALID_STATE_RECOVERY=PASS\n'

# Main marks an explicit Forward add as fresh intent only for a mutation-zero
# transaction. Once mutation started, the dispatcher rejects it byte-for-byte.
reset_fixture
write_schema
write_complete_manager "$SCRIPT_VERSION"
nb_lifecycle_begin install prepare 0 0 0 0 0 0 forward
forward_explicit_zero_txid="$(nb_lifecycle_field TRANSACTION_ID)"
(
  # shellcheck disable=SC1091
  source "$TEST_ROOT/src/62-forward.sh"
  id() { [ "${1:-}" = -u ] && printf 0; }
  require_root() { return 0; }
  require_linux() { return 0; }
  nb_lifecycle_lock_acquire() { NOBRAND_LIFECYCLE_LOCK_HELD=$((NOBRAND_LIFECYCLE_LOCK_HELD + 1)); }
  nb_lifecycle_lock_release() { NOBRAND_LIFECYCLE_LOCK_HELD=$((NOBRAND_LIFECYCLE_LOCK_HELD - 1)); }
  ensure_manager_state_layout() { return 0; }
  dry_run_should_preview() { return 1; }
  is_mita_elf_binary() { return 1; }
  nobrand_manager_installation_valid() { return 0; }
  nobrand_run_forward_action_unscoped() {
    [ "$(nb_lifecycle_field TRANSACTION_ID)" != "$forward_explicit_zero_txid" ] \
      || fail 'explicit Forward retry reused stale transaction identity'
    nb_lifecycle_mark_protocol_mutation_started forward
    printf 'callback\n' >>"$fixture/forward-explicit-zero.callback"
  }
  nb_lifecycle_validate_protocol_scope() { return 0; }
  ACTION=nobrand-forward
  FORWARD_ACTION=add
  NOBRAND_LIFECYCLE_LOCK_HELD=0
  main
  assert_eq 0 "$NOBRAND_LIFECYCLE_LOCK_HELD" \
    'explicit mutation-zero Forward retry balances lifecycle lock'
)
assert_eq 1 "$(wc -l <"$fixture/forward-explicit-zero.callback" | tr -d '[:space:]')" \
  'explicit mutation-zero Forward retry runs callback once'
assert_eq complete "$(nb_lifecycle_field STATUS)" \
  'explicit mutation-zero Forward retry completes fresh transaction'

reset_fixture
write_schema
write_complete_manager "$SCRIPT_VERSION"
nb_lifecycle_begin install prepare 0 0 0 0 0 0 forward
nb_lifecycle_mark_mutation_started
cp "$NOBRAND_LIFECYCLE_TX_FILE" "$fixture/forward-explicit-mutated.expected"
(
  # shellcheck disable=SC1091
  source "$TEST_ROOT/src/62-forward.sh"
  id() { [ "${1:-}" = -u ] && printf 0; }
  nb_lifecycle_lock_acquire() { NOBRAND_LIFECYCLE_LOCK_HELD=$((NOBRAND_LIFECYCLE_LOCK_HELD + 1)); }
  nb_lifecycle_lock_release() { NOBRAND_LIFECYCLE_LOCK_HELD=$((NOBRAND_LIFECYCLE_LOCK_HELD - 1)); }
  nobrand_run_forward_action() { : >"$fixture/forward-explicit-mutated.unexpected"; }
  ACTION=nobrand-forward
  FORWARD_ACTION=add
  NOBRAND_LIFECYCLE_LOCK_HELD=0
  set +e
  main >/dev/null 2>&1
  forward_explicit_mutated_rc=$?
  set -e
  [ "$forward_explicit_mutated_rc" -ne 0 ] \
    || fail 'explicit Forward add accepted a mutated recovery transaction'
  assert_eq 0 "$NOBRAND_LIFECYCLE_LOCK_HELD" \
    'mutated explicit Forward refusal balances lifecycle lock'
)
[ ! -e "$fixture/forward-explicit-mutated.unexpected" ] \
  || fail 'mutated explicit Forward transaction invoked callback'
cmp -s "$fixture/forward-explicit-mutated.expected" "$NOBRAND_LIFECYCLE_TX_FILE" \
  || fail 'mutated explicit Forward refusal changed transaction bytes'
printf 'FORWARD_EXPLICIT_RETRY_GATE=PASS\n'

# A fresh-process Forward recovery must clear an unmutated v2 transaction before
# fingerprint classification or input recollection. No callback can run.
reset_fixture
nb_lifecycle_begin install prepare 0 0 0 0 0 0 forward
forward_unmutated_unexpected="$fixture/forward-unmutated-unexpected"
(
  # shellcheck disable=SC1091
  source "$TEST_ROOT/src/62-forward.sh"
  require_root() { return 0; }
  require_linux() { return 0; }
  nb_lifecycle_lock_acquire() { NOBRAND_LIFECYCLE_LOCK_HELD=$((NOBRAND_LIFECYCLE_LOCK_HELD + 1)); }
  nb_lifecycle_lock_release() { NOBRAND_LIFECYCLE_LOCK_HELD=$((NOBRAND_LIFECYCLE_LOCK_HELD - 1)); }
  forward_menu_reset_requests() { : >"$forward_unmutated_unexpected"; }
  forward_menu_collect_add() { : >"$forward_unmutated_unexpected"; }
  nobrand_run_forward_action_unscoped() { : >"$forward_unmutated_unexpected"; }
  NOBRAND_LIFECYCLE_ACTIVE=0
  NOBRAND_LIFECYCLE_OPERATION=""
  NOBRAND_LIFECYCLE_SCOPE=""
  # Consumed by the sourced dedicated recovery function.
  # shellcheck disable=SC2034
  NOBRAND_LIFECYCLE_MUTATION_STARTED=0
  NOBRAND_LIFECYCLE_LOCK_HELD=0
  nobrand_recover_forward_add >/dev/null
  assert_eq 0 "$NOBRAND_LIFECYCLE_LOCK_HELD" \
    'unmutated Forward recovery balances lifecycle lock'
)
[ ! -e "$forward_unmutated_unexpected" ] \
  || fail 'unmutated Forward recovery collected input or invoked callback'
[ ! -e "$NOBRAND_LIFECYCLE_TX_FILE" ] \
  || fail 'unmutated Forward recovery retained lifecycle metadata'
printf 'FORWARD_UNMUTATED_RECOVERY_CLEAR=PASS\n'

# An unchanged post-mutation Forward transaction cannot be reconstructed: the
# original request and pre-state were not recorded. Recovery must preserve the
# transaction byte-for-byte without reset, collection, or callback execution.
reset_fixture
forward_unchanged_baseline="$(nb_lifecycle_protocol_scope_fingerprint forward)"
nb_lifecycle_begin install "callback-${forward_unchanged_baseline:0:55}" 0 0 0 0 0 0 forward
nb_lifecycle_mark_mutation_started
cp "$NOBRAND_LIFECYCLE_TX_FILE" "$fixture/forward-unchanged.expected"
forward_unchanged_log="$fixture/forward-unchanged.log"
forward_unchanged_effects="$fixture/forward-unchanged-effects.log"
(
  # shellcheck disable=SC1091
  source "$TEST_ROOT/src/62-forward.sh"
  require_root() { return 0; }
  require_linux() { return 0; }
  nb_lifecycle_lock_acquire() { NOBRAND_LIFECYCLE_LOCK_HELD=$((NOBRAND_LIFECYCLE_LOCK_HELD + 1)); }
  nb_lifecycle_lock_release() { NOBRAND_LIFECYCLE_LOCK_HELD=$((NOBRAND_LIFECYCLE_LOCK_HELD - 1)); }
  forward_reconcile_authoritative_state() { printf 'reconcile\n' >>"$forward_unchanged_effects"; }
  forward_menu_reset_requests() { printf 'reset\n' >>"$forward_unchanged_effects"; }
  forward_menu_collect_add() { printf 'collect\n' >>"$forward_unchanged_effects"; }
  nobrand_run_forward_action_unscoped() { printf 'callback\n' >>"$forward_unchanged_effects"; }
  NOBRAND_RECOVERY_EXPECTED_SCOPE=forward
  NOBRAND_LIFECYCLE_LOCK_HELD=0
  LANG_ZH=0
  set +e
  nobrand_recover_forward_add >"$forward_unchanged_log" 2>&1
  forward_unchanged_rc=$?
  set -e
  [ "$forward_unchanged_rc" -ne 0 ] \
    || fail 'unchanged mutated Forward recovery did not fail closed'
  assert_eq 0 "$NOBRAND_LIFECYCLE_LOCK_HELD" \
    'unchanged mutated Forward recovery balances lifecycle lock'
)
cmp -s "$fixture/forward-unchanged.expected" "$NOBRAND_LIFECYCLE_TX_FILE" \
  || fail 'unchanged mutated Forward recovery modified lifecycle metadata'
[ ! -e "$forward_unchanged_effects" ] \
  || fail 'unchanged mutated Forward recovery reset, recollected, or replayed'
assert_contains "$(cat "$forward_unchanged_log")" \
  'automatic cleanup or replay is unsafe' \
  'Forward fail-closed message explains why automation is unsafe'
printf 'FORWARD_UNCHANGED_RECOVERY_FAIL_CLOSED=PASS\n'

# The dedicated Forward recovery route must classify changed committed state
# before opening its input collector. Validation-only recovery skips both input
# recollection and replay of the add callback.
reset_fixture
forward_committed_callback_log="$fixture/forward-committed-callback.log"
forward_committed_recollection_log="$fixture/forward-committed-recollection.log"
forward_committed_doctor_log="$fixture/forward-committed-doctor.log"
(
  # shellcheck disable=SC1091
  source "$TEST_ROOT/src/62-forward.sh"
  require_root() { return 0; }
  require_linux() { return 0; }
  nb_lifecycle_lock_acquire() { NOBRAND_LIFECYCLE_LOCK_HELD=$((NOBRAND_LIFECYCLE_LOCK_HELD + 1)); }
  nb_lifecycle_lock_release() { NOBRAND_LIFECYCLE_LOCK_HELD=$((NOBRAND_LIFECYCLE_LOCK_HELD - 1)); }
  ensure_manager_state_layout() { return 0; }
  nobrand_manager_installation_valid() { return 0; }
  nb_lifecycle_reconcile_protocol_scope() {
    assert_eq forward "$1" 'Forward changed-state reconciliation remains scoped'
  }
  forward_state_valid() {
    jq -e '
      .schema_version==3 and .ownership=="nobrand-v3"
      and .feature=="port-forward" and (.rules|type)=="array"
    ' "$1" >/dev/null
  }
  forward_doctor() {
    forward_state_valid "$NOBRAND_FORWARD_STATE_FILE" \
      && jq -e '.rules|length==1' "$NOBRAND_FORWARD_STATE_FILE" >/dev/null
    printf 'doctor\n' >>"$forward_committed_doctor_log"
  }
  forward_menu_reset_requests() {
    printf 'reset\n' >>"$forward_committed_recollection_log"
  }
  forward_menu_collect_add() {
    printf 'collect\n' >>"$forward_committed_recollection_log"
  }
  nobrand_run_forward_action_unscoped() {
    printf 'called\n' >>"$forward_committed_callback_log"
    nb_lifecycle_mark_protocol_mutation_started forward
    mkdir -p "$(dirname "$NOBRAND_FORWARD_STATE_FILE")"
    cat >"$NOBRAND_FORWARD_STATE_FILE" <<'JSON'
{"schema_version":3,"ownership":"nobrand-v3","feature":"port-forward","rules":[{"rule_id":"f1111111111111111"}]}
JSON
    return 73
  }
  # Consumed by the sourced protocol lifecycle wrapper.
  # shellcheck disable=SC2034
  NOBRAND_MANAGER_SESSION_ACTIVE=1
  set +e
  nb_lifecycle_run_protocol_install forward nobrand_run_forward_action_unscoped
  forward_committed_initial_rc=$?
  set -e
  assert_eq 73 "$forward_committed_initial_rc" \
    'Forward callback failure after committed state propagates'
  forward_committed_phase="$(nb_lifecycle_field LAST_COMPLETED_PHASE)"
  [[ "$forward_committed_phase" =~ ^callback-[0-9a-f]{55}$ ]] \
    || fail 'Forward committed callback did not retain callback fingerprint phase'

  nobrand_recover_forward_add
  assert_eq 1 "$(wc -l <"$forward_committed_callback_log" | tr -d '[:space:]')" \
    'Forward changed-state recovery does not replay add callback'
  [ ! -e "$forward_committed_recollection_log" ] \
    || fail 'Forward changed-state recovery recollected add input'
  assert_eq 1 "$(wc -l <"$forward_committed_doctor_log" | tr -d '[:space:]')" \
    'Forward changed-state recovery validates committed state once'
  assert_eq 1 "$(jq -r '.rules|length' "$NOBRAND_FORWARD_STATE_FILE")" \
    'Forward changed-state recovery preserves committed rule'
  assert_eq complete "$(nb_lifecycle_field STATUS)" \
    'Forward changed-state recovery completes transaction'
  assert_eq forward "$(nb_lifecycle_scope)" \
    'Forward changed-state recovery preserves scope'
  assert_eq 0 "$NOBRAND_LIFECYCLE_LOCK_HELD" \
    'Forward changed-state recovery balances nested lifecycle locks'
)
printf 'FORWARD_COMMITTED_RECOVERY_SKIPS_RECOLLECTION=PASS\n'

# Direct Forward add dispatch cannot bypass the fail-closed rule, even if an
# internal caller incorrectly marks the retry as explicit. The valid empty
# state and its exact transaction must remain unchanged.
reset_fixture
mkdir -p "$(dirname "$NOBRAND_FORWARD_STATE_FILE")"
printf '%s\n' \
  '{"schema_version":3,"ownership":"nobrand-v3","feature":"port-forward","rules":[]}' \
  >"$NOBRAND_FORWARD_STATE_FILE"
forward_empty_baseline="$(nb_lifecycle_protocol_scope_fingerprint forward)"
nb_lifecycle_begin install "callback-${forward_empty_baseline:0:55}" 0 0 0 0 0 0 forward
nb_lifecycle_mark_mutation_started
cp "$NOBRAND_LIFECYCLE_TX_FILE" "$fixture/forward-empty.expected"
cp "$NOBRAND_FORWARD_STATE_FILE" "$fixture/forward-empty-state.expected"
forward_direct_log="$fixture/forward-direct.log"
(
  # shellcheck disable=SC1091
  source "$TEST_ROOT/src/62-forward.sh"
  require_root() { return 0; }
  require_linux() { return 0; }
  nb_lifecycle_lock_acquire() { NOBRAND_LIFECYCLE_LOCK_HELD=$((NOBRAND_LIFECYCLE_LOCK_HELD + 1)); }
  nb_lifecycle_lock_release() { NOBRAND_LIFECYCLE_LOCK_HELD=$((NOBRAND_LIFECYCLE_LOCK_HELD - 1)); }
  nobrand_run_forward_action_unscoped() {
    : >"$fixture/forward-direct-unexpected-callback"
  }
  NOBRAND_MANAGER_SESSION_ACTIVE=1
  # Consumed by the sourced lifecycle wrapper.
  # shellcheck disable=SC2034
  NOBRAND_PROTOCOL_EXPLICIT_RETRY_SCOPE=forward
  NOBRAND_LIFECYCLE_LOCK_HELD=0
  LANG_ZH=0
  set +e
  nb_lifecycle_run_protocol_install forward nobrand_run_forward_action_unscoped \
    >"$forward_direct_log" 2>&1
  forward_direct_rc=$?
  set -e
  [ "$forward_direct_rc" -ne 0 ] \
    || fail 'direct Forward add replayed an unchanged mutated transaction'
  assert_eq 0 "$NOBRAND_LIFECYCLE_LOCK_HELD" \
    'direct Forward fail-closed path balances lifecycle lock'
)
cmp -s "$fixture/forward-empty.expected" "$NOBRAND_LIFECYCLE_TX_FILE" \
  || fail 'direct Forward fail-closed path modified lifecycle metadata'
cmp -s "$fixture/forward-empty-state.expected" "$NOBRAND_FORWARD_STATE_FILE" \
  || fail 'direct Forward fail-closed path modified authoritative state'
[ ! -e "$fixture/forward-direct-unexpected-callback" ] \
  || fail 'direct Forward fail-closed path invoked callback'
assert_contains "$(cat "$forward_direct_log")" \
  'automatic cleanup or replay is unsafe' \
  'direct Forward refusal explains why automation is unsafe'
printf 'FORWARD_DIRECT_RETRY_FAIL_CLOSED=PASS\n'

# Model SIGKILL after candidate nft/Realm/firewall effects but before Forward's
# state rename. Because neither the request nor the pre-state is durable, the
# recovery path must leave every effect and the exact transaction untouched.
reset_fixture
write_schema
write_complete_manager "$SCRIPT_VERSION"
forward_crash_baseline="$(nb_lifecycle_protocol_scope_fingerprint forward)"
nb_lifecycle_begin install "callback-${forward_crash_baseline:0:55}" 0 0 0 0 0 0 forward
nb_lifecycle_mark_mutation_started
forward_crash_prior_tx="$fixture/forward-crash-window.prior"
cp "$NOBRAND_LIFECYCLE_TX_FILE" "$forward_crash_prior_tx"
forward_crash_log="$fixture/forward-crash-window.log"
forward_crash_nft="$fixture/forward-candidate-nft"
forward_crash_realm="$fixture/forward-candidate-realm"
forward_crash_firewall="$fixture/forward-candidate-firewall"
: >"$forward_crash_nft"
: >"$forward_crash_realm"
: >"$forward_crash_firewall"
mkdir -p "$(dirname "$NOBRAND_FIREWALL_OWNED_STATE")"
printf '%s\n' 'iptables|tcp|31000' 'iptables|udp|32000' \
  >"$NOBRAND_FIREWALL_OWNED_STATE"
(
  # shellcheck disable=SC1091
  source "$TEST_ROOT/src/62-forward.sh"
  require_root() { return 0; }
  require_linux() { return 0; }
  nb_lifecycle_lock_acquire() { NOBRAND_LIFECYCLE_LOCK_HELD=$((NOBRAND_LIFECYCLE_LOCK_HELD + 1)); }
  nb_lifecycle_lock_release() { NOBRAND_LIFECYCLE_LOCK_HELD=$((NOBRAND_LIFECYCLE_LOCK_HELD - 1)); }
  forward_reconcile_authoritative_state() { printf 'reconcile\n' >>"$forward_crash_log"; }
  forward_apply_nft_state() { printf 'nft\n' >>"$forward_crash_log"; }
  forward_realm_apply_state() { printf 'realm\n' >>"$forward_crash_log"; }
  nb_firewall_open_pairs() { printf 'firewall-open\n' >>"$forward_crash_log"; }
  nb_firewall_close_pairs() { printf 'firewall-close\n' >>"$forward_crash_log"; }
  forward_menu_reset_requests() { printf 'reset-requests\n' >>"$forward_crash_log"; }
  forward_menu_collect_add() { printf 'collect\n' >>"$forward_crash_log"; }
  nobrand_run_forward_action_unscoped() { printf 'callback\n' >>"$forward_crash_log"; }
  forward_doctor() { printf 'doctor\n' >>"$forward_crash_log"; }
  # Consumed by the sourced dedicated recovery function.
  # shellcheck disable=SC2034
  NOBRAND_MANAGER_SESSION_ACTIVE=1
  # shellcheck disable=SC2034
  NOBRAND_RECOVERY_EXPECTED_SCOPE=forward
  NOBRAND_LIFECYCLE_LOCK_HELD=0
  LANG_ZH=0
  set +e
  nobrand_recover_forward_add >"$fixture/forward-crash-window.message" 2>&1
  forward_crash_rc=$?
  set -e
  [ "$forward_crash_rc" -ne 0 ] \
    || fail 'Forward crash-window recovery did not fail closed'
  assert_eq 0 "$NOBRAND_LIFECYCLE_LOCK_HELD" \
    'Forward crash-window fail-closed path balances lifecycle lock'
)
cmp -s "$forward_crash_prior_tx" "$NOBRAND_LIFECYCLE_TX_FILE" \
  || fail 'Forward crash-window recovery modified original metadata'
[ ! -e "$forward_crash_log" ] \
  || fail 'Forward crash-window recovery touched reset, collector, callback, or doctor paths'
[ -e "$forward_crash_nft" ] && [ -e "$forward_crash_realm" ] \
  && [ -e "$forward_crash_firewall" ] \
  || fail 'Forward crash-window recovery changed unprovable candidate effects'
assert_eq $'iptables|tcp|31000\niptables|udp|32000' \
  "$(cat "$NOBRAND_FIREWALL_OWNED_STATE")" \
  'Forward crash-window recovery preserves the firewall ledger exactly'
assert_contains "$(cat "$fixture/forward-crash-window.message")" \
  'automatic cleanup or replay is unsafe' \
  'Forward crash-window refusal explains the missing durable evidence'
printf 'FORWARD_CRASH_WINDOW_FAIL_CLOSED=PASS\n'

# The menu may contain an ordinary failed action, but it must terminate the
# manager process if that action leaves a durable post-mutation transaction.
reset_fixture
menu_post_mutation_marker="$fixture/menu-post-mutation-following-marker"
set +e
(
  trap - ERR
  on_error() { exit 1; }
  menu_post_mutation_failure() {
    nb_lifecycle_begin install prepare 0 0 0 0 0 0 snell
    nb_lifecycle_mark_mutation_started
    return 63
  }
  nobrand_menu_run menu_post_mutation_failure
  : >"$menu_post_mutation_marker"
)
menu_post_mutation_rc=$?
set -e
assert_eq 1 "$menu_post_mutation_rc" \
  'menu exits after an action leaves post-mutation recovery metadata'
[ ! -e "$menu_post_mutation_marker" ] \
  || fail 'menu continued after a post-mutation action failure'
nb_lifecycle_tx_valid || fail 'menu post-mutation failure corrupted lifecycle metadata'
assert_eq install "$(nb_lifecycle_field OPERATION)" \
  'menu post-mutation failure preserves install operation'
assert_eq snell "$(nb_lifecycle_scope)" \
  'menu post-mutation failure preserves protocol scope'
assert_eq 1 "$(nb_lifecycle_mutation_started)" \
  'menu post-mutation failure preserves mutation marker'

reset_fixture
menu_ordinary_failure_marker="$fixture/menu-ordinary-failure-following-marker"
set +e
(
  trap - ERR
  on_error() { exit 1; }
  menu_ordinary_failure() { return 64; }
  nobrand_menu_run menu_ordinary_failure
  : >"$menu_ordinary_failure_marker"
)
menu_ordinary_failure_rc=$?
set -e
assert_eq 0 "$menu_ordinary_failure_rc" \
  'menu contains an ordinary failure with no lifecycle transaction'
[ -e "$menu_ordinary_failure_marker" ] \
  || fail 'ordinary non-transactional menu failure terminated the caller'
[ ! -e "$NOBRAND_LIFECYCLE_TX_FILE" ] \
  || fail 'ordinary menu failure created lifecycle metadata'
printf 'MENU_POST_MUTATION_TERMINATION=PASS\n'

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
  install_self_script() { write_complete_manager "$SCRIPT_VERSION"; }
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

# Full uninstall also preserves a prior completed lifecycle record until its
# own mutation marker succeeds.
prepare_current_complete_uninstall_fixture
nb_lifecycle_begin install prepare 0 0 0 0 0 0 manager
nb_lifecycle_mark_mutation_started
nb_lifecycle_complete install
cp "$NOBRAND_LIFECYCLE_TX_FILE" "$fixture/uninstall-marker-failure.expected"
(
  stub_uninstall_dependencies
  nb_lifecycle_mark_mutation_started() { return 74; }
  nobrand_uninstall_impl() { : >"$fixture/uninstall-marker-failure.unexpected"; }
  YES=1
  set +e
  nobrand_uninstall >/dev/null 2>&1
  uninstall_marker_failure_rc=$?
  set -e
  assert_eq 74 "$uninstall_marker_failure_rc" \
    'full-uninstall mutation-marker failure propagates'
)
cmp -s "$fixture/uninstall-marker-failure.expected" "$NOBRAND_LIFECYCLE_TX_FILE" \
  || fail 'full-uninstall mutation-marker failure changed prior metadata'
[ ! -e "$fixture/uninstall-marker-failure.unexpected" ] \
  || fail 'full-uninstall mutation-marker failure ran cleanup'
assert_state CURRENT_COMPLETE \
  'full-uninstall mutation-marker failure preserves current installation'
printf 'UNINSTALL_PREMUTATION_RESTORE=PASS\n'

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

# A signal delivered immediately after the atomic lifecycle write must see the
# new transaction as active. Before mutation it either removes a fresh record or
# restores the completed record that the caller snapshotted byte-for-byte.
run_begin_atomic_write_signal_case() {
  local prior_record="$1" signal_rc=0
  local expected_record="$fixture/begin-write-signal-${prior_record}.expected"
  reset_fixture
  if [ "$prior_record" = complete ]; then
    write_schema
    write_complete_manager "$SCRIPT_VERSION"
    nb_lifecycle_begin install prepare 0 0 0 0 0 0 manager
    nb_lifecycle_mark_mutation_started
    nb_lifecycle_complete install
    cp "$NOBRAND_LIFECYCLE_TX_FILE" "$expected_record"
  fi
  set +e
  (
    trap - EXIT HUP INT TERM ERR
    nb_lifecycle_signal_handlers_install
    nb_lifecycle_pre_mutation_snapshot
    begin_signal_once=1
    mv() {
      local arg target=""
      for arg in "$@"; do target="$arg"; done
      command mv "$@" || return
      if [ "$target" = "$NOBRAND_LIFECYCLE_TX_FILE" ] \
         && [ "$begin_signal_once" -eq 1 ]; then
        begin_signal_once=0
        kill -INT "$BASHPID"
      fi
    }
    nb_lifecycle_begin configure prepare 0 0 0 0 0 0 ingress
    exit 99
  ) >/dev/null 2>&1
  signal_rc=$?
  set -e
  assert_eq 130 "$signal_rc" \
    "INT immediately after atomic begin write exits conventionally: $prior_record"
  if [ "$prior_record" = absent ]; then
    [ ! -e "$NOBRAND_LIFECYCLE_TX_FILE" ] \
      || fail 'atomic begin-write signal retained a fresh transaction'
    assert_state CLEAN \
      'atomic begin-write signal without prior record leaves CLEAN state'
  else
    cmp -s "$expected_record" "$NOBRAND_LIFECYCLE_TX_FILE" \
      || fail 'atomic begin-write signal did not restore prior completed bytes'
    assert_state CURRENT_COMPLETE \
      'atomic begin-write signal restores prior completed classification'
  fi
}

run_begin_atomic_write_signal_case absent
run_begin_atomic_write_signal_case complete
printf 'BEGIN_ATOMIC_WRITE_SIGNAL_RESTORE=PASS\n'

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

  run_wrapper_premutation_signal_restore() {
    local wrapper_case="$1" wrapper_ready wrapper_prior wrapper_target
    local wrapper_attempt wrapper_rc wrapper_expected_state
    reset_fixture
    wrapper_ready="$fixture/wrapper-signal-${wrapper_case}.ready"
    wrapper_prior="$fixture/wrapper-signal-${wrapper_case}.expected"
    case "$wrapper_case" in
      manager)
        write_schema
        nb_lifecycle_begin install prepare 0 0 0 0 0 0 snell
        nb_lifecycle_mark_mutation_started
        nb_lifecycle_complete install
        wrapper_expected_state=CURRENT_PARTIAL_INSTALL
        ;;
      ingress)
        write_schema
        write_complete_manager "$SCRIPT_VERSION"
        nb_lifecycle_begin install prepare 0 0 0 0 0 0 manager
        nb_lifecycle_mark_mutation_started
        nb_lifecycle_complete install
        wrapper_expected_state=CURRENT_COMPLETE
        ;;
      uninstall)
        prepare_current_complete_uninstall_fixture
        nb_lifecycle_begin install prepare 0 0 0 0 0 0 manager
        nb_lifecycle_mark_mutation_started
        nb_lifecycle_complete install
        wrapper_expected_state=CURRENT_COMPLETE
        ;;
      *) fail "unknown wrapper signal case: $wrapper_case" ;;
    esac
    cp "$NOBRAND_LIFECYCLE_TX_FILE" "$wrapper_prior"
    set +e
    (
      trap - EXIT HUP INT TERM ERR
      wrapper_target="$BASHPID"
      (
        for ((wrapper_attempt = 0; wrapper_attempt < 200; wrapper_attempt++)); do
          [ ! -e "$wrapper_ready" ] || break
          sleep 0.01
        done
        if [ -e "$wrapper_ready" ]; then
          kill -INT "$wrapper_target"
        else
          kill -TERM "$wrapper_target"
        fi
      ) &
      nb_lifecycle_lock_acquire() { NOBRAND_LIFECYCLE_LOCK_HELD=$((NOBRAND_LIFECYCLE_LOCK_HELD + 1)); }
      nb_lifecycle_lock_release() { NOBRAND_LIFECYCLE_LOCK_HELD=$((NOBRAND_LIFECYCLE_LOCK_HELD - 1)); }
      NOBRAND_LIFECYCLE_LOCK_HELD=0
      nb_lifecycle_signal_handlers_install
      case "$wrapper_case" in
        manager)
          require_root() { return 0; }
          require_linux() { return 0; }
          detect_pkg_manager() { printf deb; }
          ensure_management_dependencies() { return 0; }
          nobrand_manager_installation_valid() { return 1; }
          nb_lifecycle_mark_mutation_started() {
            : >"$wrapper_ready"
            while true; do sleep 0.05; done
          }
          ensure_manager_state_layout() { : >"$fixture/wrapper-signal-manager.unexpected"; }
          nobrand_manager_bootstrap
          ;;
        ingress)
          # Consumed by the sourced lifecycle wrapper.
          # shellcheck disable=SC2034
          NOBRAND_MANAGER_SESSION_ACTIVE=1
          nobrand_run_ingress_action_unscoped() {
            : >"$wrapper_ready"
            while true; do sleep 0.05; done
          }
          nb_lifecycle_run_ingress_action
          ;;
        uninstall)
          stub_uninstall_dependencies
          nb_lifecycle_mark_mutation_started() {
            : >"$wrapper_ready"
            while true; do sleep 0.05; done
          }
          nobrand_uninstall_impl() { : >"$fixture/wrapper-signal-uninstall.unexpected"; }
          YES=1
          nobrand_uninstall
          ;;
      esac
    ) >/dev/null 2>&1
    wrapper_rc=$?
    set -e
    assert_eq 130 "$wrapper_rc" \
      "INT interrupts ${wrapper_case} before its mutation marker"
    cmp -s "$wrapper_prior" "$NOBRAND_LIFECYCLE_TX_FILE" \
      || fail "${wrapper_case} pre-mutation signal changed prior metadata"
    assert_state "$wrapper_expected_state" \
      "${wrapper_case} pre-mutation signal restores prior classification"
    [ ! -e "$fixture/wrapper-signal-${wrapper_case}.unexpected" ] \
      || fail "${wrapper_case} pre-mutation signal reached external mutation"
  }

  run_wrapper_premutation_signal_restore manager
  run_wrapper_premutation_signal_restore ingress
  run_wrapper_premutation_signal_restore uninstall
  printf 'WRAPPER_PREMUTATION_SIGNAL_RESTORE=PASS\n'

  run_lifecycle_signal_interruption() {
    local signal_case_operation="$1" signal_case_scope="$2"
    local signal_case_name="$3" signal_case_expected_rc="$4"
    local signal_case_mutated="$5" signal_case_expected_state=""
    local signal_case_ready signal_case_log signal_case_hash_file
    local signal_case_target signal_case_attempt signal_case_rc
    reset_fixture
    signal_case_ready="$fixture/signal-${signal_case_operation}-${signal_case_scope}-${signal_case_name}-${signal_case_mutated}.ready"
    signal_case_log="$fixture/signal-${signal_case_operation}-${signal_case_scope}-${signal_case_name}-${signal_case_mutated}.log"
    signal_case_hash_file="$fixture/signal-${signal_case_operation}-${signal_case_scope}-${signal_case_name}-${signal_case_mutated}.sha256"
    set +e
    (
      trap - EXIT HUP INT TERM ERR
      signal_case_target="$BASHPID"
      (
        for ((signal_case_attempt = 0; signal_case_attempt < 200; signal_case_attempt++)); do
          [ ! -e "$signal_case_ready" ] || break
          sleep 0.01
        done
        if [ -e "$signal_case_ready" ]; then
          kill -s "$signal_case_name" "$signal_case_target"
        else
          kill -TERM "$signal_case_target"
        fi
      ) &
      NOBRAND_LIFECYCLE_LOCK_HELD=0
      nb_lifecycle_lock_acquire
      nb_lifecycle_lock_acquire
      nb_lifecycle_begin "$signal_case_operation" prepare 0 0 0 0 0 0 \
        "$signal_case_scope"
      if [ "$signal_case_mutated" -eq 1 ]; then
        nb_lifecycle_mark_mutation_started
        sha256sum "$NOBRAND_LIFECYCLE_TX_FILE" | awk '{print $1}' \
          >"$signal_case_hash_file"
      fi
      nb_lifecycle_signal_handlers_install
      : >"$signal_case_ready"
      while true; do sleep 0.05; done
    ) >"$signal_case_log" 2>&1
    signal_case_rc=$?
    set -e

    assert_eq "$signal_case_expected_rc" "$signal_case_rc" \
      "$signal_case_name interrupts active ${signal_case_operation}:${signal_case_scope} with the conventional status"
    if [ "$signal_case_mutated" -eq 0 ]; then
      assert_contains "$(cat "$signal_case_log")" '写入变更前被中断' \
        "$signal_case_name reports pre-mutation interruption"
      [ ! -e "$NOBRAND_LIFECYCLE_TX_FILE" ] \
        || fail "$signal_case_name retained an unmutated ${signal_case_operation}:${signal_case_scope} transaction"
      assert_state CLEAN \
        "$signal_case_name pre-mutation interruption leaves no partial state"
    else
      assert_contains "$(cat "$signal_case_log")" '生命周期操作被信号中断' \
        "$signal_case_name reports scoped post-mutation interruption"
      nb_lifecycle_tx_valid \
        || fail "$signal_case_name corrupted ${signal_case_operation}:${signal_case_scope} recovery metadata"
      assert_eq "$signal_case_operation" "$(nb_lifecycle_field OPERATION)" \
        "$signal_case_name preserves lifecycle operation"
      assert_eq "$signal_case_scope" "$(nb_lifecycle_scope)" \
        "$signal_case_name preserves lifecycle scope"
      assert_eq 1 "$(nb_lifecycle_mutation_started)" \
        "$signal_case_name preserves mutation marker"
      assert_eq in-progress "$(nb_lifecycle_field STATUS)" \
        "$signal_case_name preserves recovery status"
      assert_eq prepare "$(nb_lifecycle_field LAST_COMPLETED_PHASE)" \
        "$signal_case_name preserves recovery phase"
      assert_eq "$(cat "$signal_case_hash_file")" \
        "$(sha256sum "$NOBRAND_LIFECYCLE_TX_FILE" | awk '{print $1}')" \
        "$signal_case_name preserves exact scoped transaction bytes"
      case "$signal_case_operation" in
        install) signal_case_expected_state=CURRENT_PARTIAL_INSTALL ;;
        repair) signal_case_expected_state=CURRENT_PARTIAL_REPAIR ;;
        configure) signal_case_expected_state=CURRENT_PARTIAL_CONFIGURE ;;
        uninstall) signal_case_expected_state=CURRENT_PARTIAL_UNINSTALL ;;
      esac
      assert_state "$signal_case_expected_state" \
        "$signal_case_name leaves post-mutation work recoverable"
    fi

    NOBRAND_LIFECYCLE_LOCK_HELD=0
    nb_lifecycle_lock_acquire \
      || fail "$signal_case_name did not release the child process lock"
    nb_lifecycle_lock_release
  }

  run_lifecycle_signal_interruption configure ingress INT 130 0
  run_lifecycle_signal_interruption install snell INT 130 1
  run_lifecycle_signal_interruption repair manager TERM 143 1
  run_lifecycle_signal_interruption uninstall global TERM 143 1

  # Model the menu action subprocess: it inherits the parent's fd 7 and lock
  # count, then acquires one nested lifecycle depth. Its signal cleanup may
  # release only down to that inherited floor.
  reset_fixture
  NOBRAND_LIFECYCLE_LOCK_HELD=0
  nb_lifecycle_lock_acquire
  assert_eq 1 "$NOBRAND_LIFECYCLE_LOCK_HELD" \
    'menu-child floor fixture starts with one parent lock depth'

  run_menu_child_signal_interruption() {
    local menu_signal_mutated="$1" menu_signal_scope="$2"
    local menu_signal_operation="$3" menu_signal_ready menu_signal_log
    local menu_signal_target menu_signal_attempt menu_signal_rc
    menu_signal_ready="$fixture/menu-signal-${menu_signal_scope}-${menu_signal_mutated}.ready"
    menu_signal_log="$fixture/menu-signal-${menu_signal_scope}-${menu_signal_mutated}.log"
    set +e
    (
      trap - EXIT HUP INT TERM ERR
      # Consumed by the sourced signal handler.
      # shellcheck disable=SC2034
      NOBRAND_LIFECYCLE_LOCK_FLOOR="$NOBRAND_LIFECYCLE_LOCK_HELD"
      nb_lifecycle_lock_acquire
      nb_lifecycle_begin "$menu_signal_operation" prepare 0 0 0 0 0 0 \
        "$menu_signal_scope"
      if [ "$menu_signal_mutated" -eq 1 ]; then
        nb_lifecycle_mark_mutation_started
      fi
      menu_signal_target="$BASHPID"
      (
        for ((menu_signal_attempt = 0; menu_signal_attempt < 200; menu_signal_attempt++)); do
          [ ! -e "$menu_signal_ready" ] || break
          sleep 0.01
        done
        if [ -e "$menu_signal_ready" ]; then
          kill -INT "$menu_signal_target"
        else
          kill -TERM "$menu_signal_target"
        fi
      ) &
      nb_lifecycle_signal_handlers_install
      : >"$menu_signal_ready"
      while true; do sleep 0.05; done
    ) >"$menu_signal_log" 2>&1
    menu_signal_rc=$?
    set -e
    assert_eq 130 "$menu_signal_rc" \
      "menu-style child ${menu_signal_operation}:${menu_signal_scope} exits on INT"
  }

  run_menu_child_signal_interruption 0 ingress configure
  [ ! -e "$NOBRAND_LIFECYCLE_TX_FILE" ] \
    || fail 'menu-style child retained its pre-mutation transaction'
  run_menu_child_signal_interruption 1 tuic install
  nb_lifecycle_tx_valid || fail 'menu-style child corrupted its post-mutation transaction'
  assert_eq install "$(nb_lifecycle_field OPERATION)" \
    'menu-style child preserves post-mutation operation'
  assert_eq tuic "$(nb_lifecycle_scope)" \
    'menu-style child preserves post-mutation scope'
  assert_eq 1 "$(nb_lifecycle_mutation_started)" \
    'menu-style child preserves post-mutation marker'
  assert_eq 1 "$NOBRAND_LIFECYCLE_LOCK_HELD" \
    'menu-style child leaves parent lock depth intact'

  set +e
  (
    trap - ERR
    exec 7>&-
    NOBRAND_LIFECYCLE_LOCK_HELD=0
    nb_lifecycle_lock_acquire >/dev/null 2>&1
  )
  menu_floor_contender_rc=$?
  set -e
  [ "$menu_floor_contender_rc" -ne 0 ] \
    || fail 'menu-style child signal handler unlocked the parent lifecycle guard'

  nb_lifecycle_clear
  nb_lifecycle_lock_release
  (
    trap - ERR
    exec 7>&-
    NOBRAND_LIFECYCLE_LOCK_HELD=0
    nb_lifecycle_lock_acquire >/dev/null 2>&1
    nb_lifecycle_lock_release
  ) || fail 'lifecycle contender could not acquire after parent lock release'
  printf 'SIGNAL_INTERRUPTION_RECOVERY=PASS\n'
  printf 'MENU_CHILD_LOCK_FLOOR=PASS\n'
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

standard_impl_checkpoint_count="$(awk '
  /^do_install_impl\(\)/ { in_standard_impl=1 }
  in_standard_impl && /^}/ { in_standard_impl=0 }
  in_standard_impl && /nb_lifecycle_checkpoint "\$NOBRAND_LIFECYCLE_OPERATION"/ { count++ }
  END { print count + 0 }
' "$TEST_ROOT/src/80-lifecycle.sh")"
standard_final_checkpoint_count="$(awk '
  /^do_install\(\)/ { in_standard_install=1 }
  in_standard_install && /^}/ { in_standard_install=0 }
  in_standard_install && /nb_lifecycle_checkpoint "\$operation" ready-to-validate/ { count++ }
  END { print count + 0 }
' "$TEST_ROOT/src/80-lifecycle.sh")"
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
