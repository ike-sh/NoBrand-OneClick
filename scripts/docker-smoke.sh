#!/usr/bin/env bash
# 本地/CI：在干净 Debian 容器内验证配置输出、isolated-v2 事务、配额与 tc 所有权。
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && { pwd -W 2>/dev/null || pwd; })"

docker run --rm -i --cap-add=NET_ADMIN -v "$ROOT:/work:ro" debian:bookworm-slim bash -s <<'DOCKER_TEST'
set -Eeuo pipefail
apt-get update -qq >/dev/null
apt-get install -y -qq python3 bash curl git jq util-linux iproute2 passwd procps >/dev/null
bash -n /work/install-nobrand.sh

# Keep the exhaustive fault-injection harness, then run a separate container
# lifecycle matrix below.  Docker PASS markers must be earned by their own
# scenario, not inferred from the aggregate unit-harness exit status.
bash /work/tests/test_lifecycle_recovery.sh

# Exercise the production lifecycle wrappers against real files in this
# disposable container. Package installation, daemon control, and firewall
# mutation are the only replaced edges; manager/schema/user-state writes,
# classification, durable checkpoints, reruns, root cleanup, and repair remain
# the production implementations. Each PASS line is emitted immediately after
# its corresponding independent scenario converges.
docker_lifecycle_matrix() (
  local matrix_root=/tmp/nobrand-docker-lifecycle
  local runtime_marker="$matrix_root/mita-runtime.installed"
  local expected actual rc sentinel_hash manager_hash registry_hash users_hash install_state_hash

  export MITA_SOURCE_ONLY=1 NOBRAND_TEST_MODE=1 LANG_ZH=1 YES=1 DRY_RUN=0
  export NOBRAND_STATE_DIR="$matrix_root/nobrand-oneclick/state"
  export NOBRAND_CONFIG_DIR="$matrix_root/nobrand-oneclick/config"
  export NOBRAND_LIB_DIR="$matrix_root/nobrand-oneclick/lib"
  export NOBRAND_LIFECYCLE_DIR="$matrix_root/nobrand-oneclick-lifecycle"
  export NOBRAND_LIFECYCLE_TX_FILE="$NOBRAND_LIFECYCLE_DIR/transaction.env"
  export NOBRAND_LIFECYCLE_LOCK_FILE="$matrix_root/run/nobrand-oneclick/lifecycle.lock"
  export NOBRAND_INSTALL_SCRIPT_PATH="$matrix_root/bin/install-nobrand"
  export NOBRAND_COMMAND_PATH="$matrix_root/bin/nobrand"
  export NOBRAND_SHORT_COMMAND_PATH="$matrix_root/bin/nb"
  export NOBRAND_LEGACY_MIERU_STATE_DIR="$matrix_root/legacy/mita-oneclick"
  export MITA_MANAGER_STATE_DIR="$NOBRAND_STATE_DIR/mieru"
  export MITA_STATE="$MITA_MANAGER_STATE_DIR/install-state.env"
  export MITA_USERS_STATE="$MITA_MANAGER_STATE_DIR/users.json"
  export MITA_USERS_LOCK="$MITA_MANAGER_STATE_DIR/users.lock"
  export MITA_USERS_BACKUP_DIR="$MITA_MANAGER_STATE_DIR/backups"
  export MITA_ADMIN_LOCK="$MITA_MANAGER_STATE_DIR/admin.lock"
  export MITA_MARKER="$MITA_MANAGER_STATE_DIR/.installed"
  export MITA_USERS_CRON="$matrix_root/cron/nobrand-mieru-users"
  export MITA_USERS_TIMER="$matrix_root/systemd/nobrand-mieru-users-scan.timer"
  export MITA_USERS_SERVICE="$matrix_root/systemd/nobrand-mieru-users-scan.service"
  export MITA_USERS_LOG="$matrix_root/log/nobrand-mieru-users.log"
  export MITA_CLIENT_EXPORT_DIR="$matrix_root/client-exports"
  export MITA_LOGROTATE_CONF="$matrix_root/logrotate/nobrand-mieru"
  export MITA_METRICS_FILE="$matrix_root/mita/metrics.pb"
  export MITA_INSTANCES_DIR="$NOBRAND_CONFIG_DIR/mita/instances"
  export MITA_INSTANCE_RUN_DIR="$matrix_root/run/mita-instances"
  export MITA_INSTANCE_METRICS_DIR="$NOBRAND_STATE_DIR/mita-metrics"
  export MITA_INSTANCE_SYSTEMD_TEMPLATE="$matrix_root/systemd/nobrand-mieru@.service"
  export MITA_INSTANCE_TMPFILES="$matrix_root/tmpfiles/nobrand-mieru.conf"
  export MITA_INSTANCE_OPENRC_PREFIX="$matrix_root/openrc/nobrand-mieru-"
  export NOBRAND_SNELL_SYSTEMD_TEMPLATE="$matrix_root/systemd/nobrand-snell@.service"
  export NOBRAND_TUIC_SYSTEMD_TEMPLATE="$matrix_root/systemd/nobrand-tuic@.service"

  # shellcheck source=install-nobrand.sh
  source /work/install-nobrand.sh
  trap - ERR
  YES=1

  matrix_fail() {
    printf 'docker lifecycle matrix: %s\n' "$1" >&2
    return 1
  }

  matrix_assert_eq() {
    expected="$1"
    actual="$2"
    [ "$expected" = "$actual" ] \
      || matrix_fail "$3 (expected=$expected actual=$actual)"
  }

  matrix_expect_state() {
    actual="$(nb_classify_installation_state)"
    matrix_assert_eq "$1" "$actual" "$2"
  }

  matrix_expect_interrupt() {
    local interrupt_log="$matrix_root/expected-interrupt.log"
    set +e
    "$@" >"$interrupt_log" 2>&1
    rc=$?
    set -e
    if [ "$rc" -eq 0 ]; then
      cat "$interrupt_log" >&2
      rm -f -- "$interrupt_log"
      matrix_fail "expected injected interruption from: $*"
      return 1
    fi
    rm -f -- "$interrupt_log"
  }

  matrix_reset() {
    [ "${NOBRAND_LIFECYCLE_LOCK_HELD:-0}" -eq 0 ] \
      || matrix_fail 'scenario leaked the lifecycle lock'
    rm -rf -- "$matrix_root"
    mkdir -p "$matrix_root/bin" "$matrix_root/run"
    chmod 0700 "$matrix_root" "$matrix_root/bin" "$matrix_root/run"
    NOBRAND_LIFECYCLE_ACTIVE=0
    NOBRAND_LIFECYCLE_OPERATION=''
    NOBRAND_LIFECYCLE_SCOPE=''
    NOBRAND_LIFECYCLE_MUTATION_STARTED=0
    NOBRAND_LIFECYCLE_LOCK_HELD=0
    NOBRAND_MANAGER_SESSION_ACTIVE=0
    NOBRAND_INSTALL_CANCELLED=0
    MENU_MODE=0
    ACTION=''
    YES=1
    unset NOBRAND_TEST_INTERRUPT_INSTALL_AT NOBRAND_TEST_INTERRUPT_REPAIR_AT \
      NOBRAND_TEST_INTERRUPT_CONFIGURE_AT NOBRAND_TEST_INTERRUPT_UNINSTALL_AT
  }

  matrix_menu_inputs() {
    : >"$matrix_root/menu-inputs"
    printf '%s\n' "$@" >"$matrix_root/menu-inputs"
    printf '0\n' >"$matrix_root/menu-input-index"
    rm -f -- "$matrix_root/unexpected-menu-read"
  }

  matrix_menu_input_count() {
    cat "$matrix_root/menu-input-index"
  }

  read_tty() {
    local destination="$1" index next input_value
    index="$(cat "$matrix_root/menu-input-index" 2>/dev/null || printf 0)"
    next=$((index + 1))
    input_value="$(sed -n "${next}p" "$matrix_root/menu-inputs" 2>/dev/null || true)"
    [ -n "$input_value" ] || {
      : >"$matrix_root/unexpected-menu-read"
      return 1
    }
    printf '%s\n' "$next" >"$matrix_root/menu-input-index"
    printf -v "$destination" '%s' "$input_value"
  }

  nobrand_print_banner() {
    local count
    nobrand_manager_installation_valid \
      || matrix_fail 'full manager UI became visible before manager validation'
    count="$(cat "$matrix_root/menu-banner-count" 2>/dev/null || printf 0)"
    printf '%s\n' "$((count + 1))" >"$matrix_root/menu-banner-count"
    msg 'NoBrand-OneClick docker manager menu'
  }

  matrix_assert_manager_only() {
    MITA_SOURCE_ONLY=0 nobrand_manager_installation_valid \
      || matrix_fail 'persistent manager validation failed'
    matrix_assert_eq "$NOBRAND_INSTALL_SCRIPT_PATH" \
      "$(readlink "$NOBRAND_COMMAND_PATH")" 'nobrand command target'
    matrix_assert_eq "$NOBRAND_COMMAND_PATH" \
      "$(readlink "$NOBRAND_SHORT_COMMAND_PATH")" 'nb command target'
    cmp -s /work/install-nobrand.sh "$NOBRAND_INSTALL_SCRIPT_PATH" \
      || matrix_fail 'canonical manager is not the exact running installer'
    hash -r
    matrix_assert_eq "${SCRIPT_NAME} ${SCRIPT_VERSION}" \
      "$(PATH="$matrix_root/bin:$PATH" MITA_SOURCE_ONLY=0 nobrand --version | sed -n '1p')" \
      'nobrand PATH version'
    matrix_assert_eq "${SCRIPT_NAME} ${SCRIPT_VERSION}" \
      "$(PATH="$matrix_root/bin:$PATH" MITA_SOURCE_ONLY=0 nb --version | sed -n '1p')" \
      'nb PATH version'
    if nb_authoritative_protocol_state_exists; then
      matrix_fail 'manager-only bootstrap fabricated protocol state'
    fi
    matrix_expect_state CURRENT_COMPLETE 'manager-only state is not complete'
  }

  # Container boundary replacements. These model only effects unavailable in a
  # daemon-free image; the real install/reinstall branches still consume and
  # preserve the state written by users_initialize_primary/save_install_state.
  # Package installation is the only bootstrap boundary replaced here. The
  # first call materializes a durable fixture marker; later calls must observe
  # it instead of representing another package installation.
  ensure_management_dependencies() {
    local count
    if [ ! -e "$matrix_root/dependencies.ready" ]; then
      count="$(cat "$matrix_root/dependency-install-count" 2>/dev/null || printf 0)"
      printf '%s\n' "$((count + 1))" >"$matrix_root/dependency-install-count"
      : >"$matrix_root/dependencies.ready"
    fi
  }
  mita_installed() { [ -f "$runtime_marker" ]; }
  installed_version() { mita_installed && printf '3.35.0'; }
  ensure_install_port_available() { return 0; }
  mieru_prepare_noninteractive_ingress_endpoint() {
    INGRESS_PROFILE_ID="$NOBRAND_LEGACY_INGRESS_PROFILE_ID"
    nb_prepare_ingress_deployment "$INGRESS_PROFILE_ID" firewall
  }
  ensure_config_noninteractive() {
    PORT=26000
    PORT_RANGE=''
    PROTOCOL=TCP
    PROFILE=balanced
    ADVERTISE_HOST=198.51.100.20
    ADVERTISE_PORT=26000
    MTU=1400
    MTU_POLICY=safe
    USERNAME=docker-user
    PASSWORD=docker-password
    TRAFFIC_PATTERN=conservative
    TRAFFIC_SEED=42
    LOW_ENTROPY_MODE=LOW_ENTROPY_MODE_OFF
    MULTIPLEXING=MULTIPLEXING_OFF
    HANDSHAKE_MODE=HANDSHAKE_NO_WAIT
    MIERU_CHANNEL=stable
  }
  mieru_resolve_runtime() {
    MIERU_RUNTIME_RESOLVED_VERSION=3.35.0
    MIERU_RUNTIME_RESOLVED_URL=https://fixture.invalid/mita.deb
    MIERU_RUNTIME_RESOLVED_SHA256=''
    MIERU_RUNTIME_RESOLVED_CHECKSUM_URL=''
  }
  download_package() { printf 'container-runtime-fixture\n' >"$2"; }
  mieru_runtime_snapshot() { printf '%s' "$matrix_root/runtime.snapshot"; }
  install_package() { : >"$runtime_marker"; }
  mieru_assert_runtime_version() { return 0; }
  mieru_runtime_commit() { return 0; }
  add_op_user() { return 0; }
  warn_traffic_unsupported() { return 0; }
  warn_low_entropy_unsupported() { return 0; }
  install_users_scheduler() { return 0; }
  apply_users_config() { return 0; }
  open_firewall_for_pairs() { return 0; }
  close_firewall_for_bindings() { return 0; }
  verify_mita_running() { return 0; }
  isolated_stop_all() { return 0; }
  prune_orphan_instances() { return 0; }
  harden_mita_permissions() { return 0; }
  client_exports_clear_current() { return 0; }
  offer_bbr_fq() { return 0; }
  print_summary() { return 0; }

  # Full-uninstall runtime edges are represented by the explicit marker above;
  # all managed-root and command removal below is performed by production code.
  mita_uninstall_target_present() { mita_installed; }
  do_uninstall() { rm -f -- "$runtime_marker"; }
  ssh_tunnel_state_exists() { return 1; }
  snell_instance_ids() { return 0; }
  hysteria2_state_exists() { return 1; }
  vless_sudoku_state_exists() { return 1; }
  reality_instance_ids() { return 0; }
  tuic_instance_ids() { return 0; }
  reality_remove_service_runtime_if_owned() { return 0; }
  nb_service_manager() { printf 'none'; }
  nb_strict_firewall_clear_all() { return 0; }
  nft() { return 1; }

  # Fresh no-argument execution must install and validate the persistent
  # manager before the first banner, without manufacturing a protocol. A
  # second launch reuses both manager state and the dependency boundary.
  matrix_reset
  matrix_menu_inputs 0
  MITA_SOURCE_ONLY=0 main >/dev/null
  matrix_assert_eq 1 "$(cat "$matrix_root/menu-banner-count")" \
    'fresh bootstrap menu count'
  matrix_assert_eq 1 "$(matrix_menu_input_count)" 'fresh bootstrap menu exit'
  matrix_assert_eq manager "$(nb_lifecycle_scope)" 'fresh bootstrap scope'
  matrix_assert_eq install "$(nb_lifecycle_field OPERATION)" 'fresh bootstrap operation'
  matrix_assert_eq complete "$(nb_lifecycle_field STATUS)" 'fresh bootstrap status'
  matrix_assert_manager_only
  manager_hash="$(sha256sum "$NOBRAND_INSTALL_SCRIPT_PATH")"
  registry_hash="$(sha256sum "$NOBRAND_REGISTRY_FILE")"
  matrix_menu_inputs 0
  ACTION=''
  MITA_SOURCE_ONLY=0 main >/dev/null
  matrix_assert_eq 2 "$(cat "$matrix_root/menu-banner-count")" \
    'second launch menu count'
  matrix_assert_eq 1 "$(cat "$matrix_root/dependency-install-count")" \
    'second launch represented another dependency installation'
  matrix_assert_eq "$manager_hash" "$(sha256sum "$NOBRAND_INSTALL_SCRIPT_PATH")" \
    'second launch changed the exact manager'
  matrix_assert_eq "$registry_hash" "$(sha256sum "$NOBRAND_REGISTRY_FILE")" \
    'second launch changed manager-only registry state'
  matrix_assert_manager_only

  # A recoverable interactive validation failure must leave the already
  # bootstrapped commands usable. Exercise the real nested menu flow, including
  # invalid interface/address re-prompts and a controlled cancel before any
  # Ingress mutation, then launch the installed nb command in a fresh process.
  export NOBRAND_TEST_INTERFACE_ROWS='eth0|192.0.2.40|UP|1'
  export NOBRAND_TEST_DEFAULT_EGRESS='eth0|192.0.2.40'
  matrix_menu_inputs 9 2 Failed-Ingress 1 missing0 eth0 \
    198.51.100.99 192.0.2.40 0 continue 0 0
  ACTION=''
  MITA_SOURCE_ONLY=0 main >"$matrix_root/failed-ingress.out" 2>&1
  matrix_assert_eq 4 "$(cat "$matrix_root/menu-banner-count")" \
    'failed Ingress action did not return to the manager menu'
  matrix_assert_eq 12 "$(matrix_menu_input_count)" \
    'failed Ingress action consumed an unexpected menu path'
  grep -Fq '网络接口不存在或没有可用的非回环 IPv4: missing0' \
    "$matrix_root/failed-ingress.out" \
    || matrix_fail 'invalid interactive interface was not handled in place'
  grep -Fq '该 IPv4 未配置在所选网络接口 eth0 上: 198.51.100.99' \
    "$matrix_root/failed-ingress.out" \
    || matrix_fail 'invalid interactive address was not handled in place'
  ! grep -Fq '非交互模式需要' "$matrix_root/failed-ingress.out" \
    || matrix_fail 'interactive Ingress leaked the noninteractive CLI error'
  if [ -e "$NOBRAND_INGRESS_STATE_FILE" ]; then
    matrix_assert_eq 0 \
      "$(jq '[.profiles[] | select(.name == "Failed-Ingress")] | length' \
        "$NOBRAND_INGRESS_STATE_FILE")" \
      'cancelled interactive Ingress unexpectedly mutated state'
  fi
  matrix_assert_manager_only

  printf '0\n' | env PATH="$matrix_root/bin:$PATH" MITA_SOURCE_ONLY=0 \
    script -qec "$NOBRAND_SHORT_COMMAND_PATH" /dev/null \
    >"$matrix_root/installed-nb.out" 2>&1
  grep -Fq '网络入口 / Ingress' "$matrix_root/installed-nb.out" \
    || matrix_fail 'installed nb did not reopen the no-argument manager menu'
  matrix_assert_manager_only
  printf 'FAILED_UI_ACTION_MANAGER_PERSISTS=PASS\n'
  printf 'INSTALLED_NB_NOARG_REOPEN_GATE=PASS\n'

  # Ingress is manager state, not a protocol prerequisite. Create one valid
  # Profile through the manager-session dispatcher, exit the menu again, and
  # prove the persistent manager remains complete with zero protocols.
  export NOBRAND_TEST_INTERFACE_ROWS='eth0|192.0.2.40|UP|1'
  export NOBRAND_TEST_DEFAULT_EGRESS='eth0|192.0.2.40'
  ingress_menu_reset_requests
  parse_nobrand_ingress_args add --name Bootstrap-Ingress --type public \
    --interface eth0 --address 192.0.2.40 --port-policy manual-only \
    --enforcement permissive --yes
  NOBRAND_MANAGER_SESSION_ACTIVE=1 nobrand_run_ingress_action >/dev/null
  matrix_assert_eq 1 \
    "$(jq '[.profiles[] | select(.name == "Bootstrap-Ingress")] | length' \
      "$NOBRAND_INGRESS_STATE_FILE")" 'Ingress-only Profile persistence'
  matrix_assert_manager_only
  matrix_menu_inputs 0
  ACTION=''
  MITA_SOURCE_ONLY=0 main >/dev/null
  matrix_assert_eq 5 "$(cat "$matrix_root/menu-banner-count")" \
    'Ingress-only manager reopen count'
  matrix_assert_manager_only
  unset NOBRAND_TEST_INTERFACE_ROWS NOBRAND_TEST_DEFAULT_EGRESS
  printf 'FRESH_BOOTSTRAP_MANAGER_GATE=PASS\n'
  printf 'MANAGER_INSTALLED_BEFORE_MAIN_MENU=PASS\n'
  printf 'MANAGER_ONLY_INSTALL_SUPPORTED=PASS\n'
  printf 'ZERO_PROTOCOL_CURRENT_COMPLETE=PASS\n'
  printf 'FRESH_INSTALL_EXIT_MANAGER_PERSISTS=PASS\n'
  printf 'INGRESS_ONLY_MANAGER_PERSISTS=PASS\n'
  printf 'INGRESS_BEFORE_PROTOCOL_SUPPORTED=PASS\n'
  printf 'MANAGER_SECOND_LAUNCH_NO_DEP_REINSTALL=PASS\n'
  printf 'DOCKER_BOOTSTRAP_GATE=PASS\n'

  # Recovery selection must retain manager and Ingress scope. With these
  # fixtures, any accidental Mieru dispatch would create authoritative Mieru
  # state and fail the manager-only assertion below.
  matrix_reset
  nb_lifecycle_begin install prepare 0 0 0 0 0 0 manager
  nb_lifecycle_mark_mutation_started
  matrix_expect_state CURRENT_PARTIAL_INSTALL 'manager recovery fixture classification'
  matrix_menu_inputs 0
  ACTION=''
  YES=1
  MITA_SOURCE_ONLY=0 main >/dev/null
  matrix_assert_eq manager "$(nb_lifecycle_scope)" 'manager recovery completion scope'
  matrix_assert_eq complete "$(nb_lifecycle_field STATUS)" 'manager recovery status'
  matrix_assert_manager_only
  printf 'MANAGER_RECOVERY_SCOPE_GATE=PASS\n'

  matrix_reset
  MITA_SOURCE_ONLY=0 nobrand_manager_bootstrap
  nb_lifecycle_begin configure prepare 0 0 0 0 0 0 ingress
  matrix_expect_state CURRENT_PARTIAL_CONFIGURE 'Ingress recovery fixture classification'
  matrix_menu_inputs 0
  ACTION=''
  YES=1
  MITA_SOURCE_ONLY=0 main >/dev/null
  [ ! -e "$NOBRAND_LIFECYCLE_TX_FILE" ] \
    || matrix_fail 'unmutated Ingress recovery retained lifecycle metadata'
  matrix_expect_state CURRENT_COMPLETE \
    'unmutated Ingress recovery did not return to manager-only complete state'
  matrix_assert_manager_only
  printf 'INGRESS_RECOVERY_SCOPE_GATE=PASS\n'
  printf 'DOCKER_SCOPED_RECOVERY_GATE=PASS\n'

  # A successful global uninstall selected from the loaded unified menu must
  # consume only the menu choice and confirmation, then return from main. A
  # third read would prove that the stale in-memory menu was rendered again.
  matrix_reset
  matrix_menu_inputs 0
  MITA_SOURCE_ONLY=0 main >/dev/null
  matrix_assert_manager_only
  matrix_menu_inputs 16 y
  ACTION=''
  set +e
  MITA_SOURCE_ONLY=0 main >"$matrix_root/global-uninstall.out" 2>&1
  rc=$?
  set -e
  matrix_assert_eq 0 "$rc" 'global uninstall menu process status'
  matrix_assert_eq 2 "$(matrix_menu_input_count)" \
    'global uninstall returned to the stale menu'
  [ ! -e "$matrix_root/unexpected-menu-read" ] \
    || matrix_fail 'global uninstall exposed another menu action'
  matrix_expect_state CLEAN 'global uninstall did not converge clean'
  [ ! -e "$NOBRAND_INSTALL_SCRIPT_PATH" ] \
    && [ ! -e "$NOBRAND_COMMAND_PATH" ] \
    && [ ! -e "$NOBRAND_SHORT_COMMAND_PATH" ] \
    || matrix_fail 'global uninstall retained manager commands'
  printf 'FULL_UNINSTALL_PROCESS_EXIT_GATE=PASS\n'
  printf 'DOCKER_FULL_UNINSTALL_EXIT_GATE=PASS\n'

  matrix_menu_inputs 0
  ACTION=''
  YES=1
  MITA_SOURCE_ONLY=0 main >/dev/null
  matrix_assert_manager_only
  printf 'FULL_UNINSTALL_FRESH_REINSTALL_GATE=PASS\n'

  matrix_reset
  do_install >/dev/null
  matrix_expect_state CURRENT_COMPLETE 'fresh install did not converge'
  matrix_assert_eq install "$(nb_lifecycle_field OPERATION)" 'fresh install operation'
  matrix_assert_eq complete "$(nb_lifecycle_field STATUS)" 'fresh install status'
  nb_schema_v3_file_valid || matrix_fail 'fresh install did not write schema-v3 state'
  mita_v3_install_state_valid || matrix_fail 'fresh install did not write Mieru install state'
  [ "$(users_count)" -eq 1 ] || matrix_fail 'fresh install did not write its primary user'
  printf 'DOCKER_LIFECYCLE_FRESH_INSTALL=PASS\n'

  matrix_reset
  export NOBRAND_TEST_INTERRUPT_INSTALL_AT=runtime-ready
  matrix_expect_interrupt do_install
  matrix_expect_state CURRENT_PARTIAL_INSTALL 'interrupted install classification'
  matrix_assert_eq runtime-ready "$(nb_lifecycle_field LAST_COMPLETED_PHASE)" \
    'interrupted install durable phase'
  unset NOBRAND_TEST_INTERRUPT_INSTALL_AT
  NOBRAND_PROTOCOL_EXPLICIT_RETRY_SCOPE=mieru do_install >/dev/null
  matrix_expect_state CURRENT_COMPLETE 'interrupted install rerun did not converge'
  mita_v3_install_state_valid || matrix_fail 'install rerun did not restore install state'
  printf 'DOCKER_LIFECYCLE_INTERRUPTED_INSTALL_RERUN=PASS\n'

  matrix_reset
  do_install >/dev/null
  printf 'preserve-complete-rerun\n' >"$NOBRAND_STATE_DIR/rerun.sentinel"
  sentinel_hash="$(sha256sum "$NOBRAND_STATE_DIR/rerun.sentinel")"
  manager_hash="$(sha256sum "$NOBRAND_INSTALL_SCRIPT_PATH")"
  registry_hash="$(sha256sum "$NOBRAND_REGISTRY_FILE")"
  users_hash="$(sha256sum "$MITA_USERS_STATE")"
  install_state_hash="$(sha256sum "$MITA_STATE")"
  do_install >/dev/null
  matrix_assert_eq repair "$(nb_lifecycle_field OPERATION)" 'complete rerun operation'
  matrix_assert_eq complete "$(nb_lifecycle_field STATUS)" 'complete rerun status'
  matrix_assert_eq "$sentinel_hash" "$(sha256sum "$NOBRAND_STATE_DIR/rerun.sentinel")" \
    'complete rerun changed existing state'
  matrix_assert_eq "$manager_hash" "$(sha256sum "$NOBRAND_INSTALL_SCRIPT_PATH")" \
    'complete rerun changed manager identity'
  matrix_assert_eq "$registry_hash" "$(sha256sum "$NOBRAND_REGISTRY_FILE")" \
    'complete rerun changed registry bytes'
  matrix_assert_eq "$users_hash" "$(sha256sum "$MITA_USERS_STATE")" \
    'complete rerun changed user-state bytes'
  matrix_assert_eq "$install_state_hash" "$(sha256sum "$MITA_STATE")" \
    'complete rerun changed install-state bytes'
  matrix_expect_state CURRENT_COMPLETE 'complete rerun did not remain complete'
  printf 'DOCKER_LIFECYCLE_COMPLETE_RERUN=PASS\n'

  matrix_reset
  do_install >/dev/null
  printf 'preserve-repair-rerun\n' >"$NOBRAND_STATE_DIR/repair.sentinel"
  sentinel_hash="$(sha256sum "$NOBRAND_STATE_DIR/repair.sentinel")"
  registry_hash="$(sha256sum "$NOBRAND_REGISTRY_FILE")"
  users_hash="$(sha256sum "$MITA_USERS_STATE")"
  export NOBRAND_TEST_INTERRUPT_REPAIR_AT=state-committed
  matrix_expect_interrupt do_install
  matrix_expect_state CURRENT_PARTIAL_REPAIR 'interrupted repair classification'
  matrix_assert_eq state-committed "$(nb_lifecycle_field LAST_COMPLETED_PHASE)" \
    'interrupted repair durable phase'
  unset NOBRAND_TEST_INTERRUPT_REPAIR_AT
  do_install >/dev/null
  matrix_assert_eq "$sentinel_hash" "$(sha256sum "$NOBRAND_STATE_DIR/repair.sentinel")" \
    'repair rerun changed existing state'
  matrix_assert_eq "$registry_hash" "$(sha256sum "$NOBRAND_REGISTRY_FILE")" \
    'repair rerun changed registry bytes'
  matrix_assert_eq "$users_hash" "$(sha256sum "$MITA_USERS_STATE")" \
    'repair rerun changed user-state bytes'
  matrix_expect_state CURRENT_COMPLETE 'interrupted repair rerun did not converge'
  printf 'DOCKER_LIFECYCLE_INTERRUPTED_REPAIR_RERUN=PASS\n'

  matrix_reset
  do_install >/dev/null
  mkdir -p "$NOBRAND_CONFIG_DIR" "$NOBRAND_LIB_DIR"
  printf 'preserve-until-cleanup\n' >"$NOBRAND_CONFIG_DIR/uninstall.sentinel"
  printf 'preserve-until-cleanup\n' >"$NOBRAND_LIB_DIR/uninstall.sentinel"
  export NOBRAND_TEST_INTERRUPT_UNINSTALL_AT=before-config-removal
  matrix_expect_interrupt nobrand_uninstall
  matrix_expect_state CURRENT_PARTIAL_UNINSTALL 'interrupted uninstall classification'
  [ ! -e "$NOBRAND_STATE_DIR" ] || matrix_fail 'uninstall interruption did not cross state removal'
  [ -e "$NOBRAND_CONFIG_DIR/uninstall.sentinel" ] \
    || matrix_fail 'uninstall interruption removed config before its checkpoint'
  [ -e "$NOBRAND_INSTALL_SCRIPT_PATH" ] \
    || matrix_fail 'uninstall interruption removed manager too early'
  unset NOBRAND_TEST_INTERRUPT_UNINSTALL_AT
  nobrand_uninstall >/dev/null
  matrix_expect_state CLEAN 'continued uninstall did not converge to clean'
  [ ! -e "$runtime_marker" ] || matrix_fail 'continued uninstall retained runtime ownership'
  printf 'DOCKER_LIFECYCLE_INTERRUPTED_UNINSTALL_CONTINUE=PASS\n'

  matrix_reset
  do_install >/dev/null
  mkdir -p "$NOBRAND_CONFIG_DIR" "$NOBRAND_LIB_DIR"
  printf 'preserve-through-repair\n' >"$NOBRAND_CONFIG_DIR/repair.sentinel"
  printf 'preserve-through-repair\n' >"$NOBRAND_LIB_DIR/repair.sentinel"
  export NOBRAND_TEST_INTERRUPT_UNINSTALL_AT=before-config-removal
  matrix_expect_interrupt nobrand_uninstall
  matrix_expect_state CURRENT_PARTIAL_UNINSTALL 'repair-direction uninstall classification'
  unset NOBRAND_TEST_INTERRUPT_UNINSTALL_AT
  do_install >/dev/null
  matrix_expect_state CURRENT_COMPLETE 'partial-uninstall repair did not converge'
  [ -e "$NOBRAND_CONFIG_DIR/repair.sentinel" ] \
    || matrix_fail 'partial-uninstall repair discarded config'
  [ -e "$NOBRAND_LIB_DIR/repair.sentinel" ] \
    || matrix_fail 'partial-uninstall repair discarded manager library data'
  [ ! -e "$MITA_STATE" ] && [ ! -e "$MITA_USERS_STATE" ] \
    || matrix_fail 'manager-only partial-uninstall repair fabricated Mieru state'
  [ ! -e "$runtime_marker" ] \
    || matrix_fail 'manager-only partial-uninstall repair fabricated a runtime'
  printf 'DOCKER_LIFECYCLE_INTERRUPTED_UNINSTALL_REPAIR=PASS\n'

  printf 'DOCKER_LIFECYCLE_RECOVERY_GATE=PASS\n'
)
docker_lifecycle_matrix

bash /work/tests/test_ingress_enforcement.sh
bash /work/tests/test_ingress_enforcement_transaction.sh

export MITA_SOURCE_ONLY=1
export MITA_MANAGER_STATE_DIR=/tmp/manager-state
export MITA_STATE=/tmp/manager-state/install-state.env
export MITA_USERS_STATE=/tmp/manager-state/users.json MITA_USERS_LOCK=/tmp/manager-state/users.lock
export MITA_USERS_BACKUP_DIR=/tmp/manager-state/backups MITA_ADMIN_LOCK=/tmp/manager-state/admin.lock
export MITA_USERS_LOG=/tmp/users.log MITA_LOGROTATE_CONF=/tmp/logrotate.conf
export MITA_INSTANCES_DIR=/tmp/instances MITA_INSTANCE_RUN_DIR=/tmp/run
export MITA_INSTANCE_METRICS_DIR=/tmp/metrics
export MITA_INSTANCE_SYSTEMD_TEMPLATE=/tmp/nobrand-mieru@.service
export MITA_INSTANCE_RUNNER=/tmp/mita-instance-run
export MITA_INSTANCE_OPENRC_PREFIX=/tmp/nobrand-mieru-
export MITA_METRICS_FILE=/tmp/mita-metrics.pb
export TC_OWNED_STATE=/tmp/manager-state/tc-owned.filters TC_IFACE=eth-test
export MITA_FIREWALL_OWNED_STATE=/tmp/manager-state/firewall-owned.bindings
export BBR_STATE_FILE=/tmp/manager-state/bbr-owned.state
export BBR_BACKUP_FILE=/tmp/manager-state/bbr-sysctl.backup
export USER_PORT_POOL_START=26000 USER_PORT_POOL_END=26020
export INSTALL_SCRIPT_PATH=/work/install-nobrand.sh QUOTA_RESET_METHOD=metrics
mkdir -p /tmp/manager-state/backups /tmp/instances /tmp/run /tmp/metrics /etc/logrotate.d
chmod 0700 /tmp/manager-state /tmp/manager-state/backups
getent group mita >/dev/null || groupadd --system mita
id mita >/dev/null 2>&1 || useradd --system -g mita -s /usr/sbin/nologin -d /tmp/metrics mita

source /work/install-nobrand.sh
test "$SCRIPT_VERSION" = 3.2.2
test "$SCRIPT_NAME|$SCRIPT_REPO" = 'NoBrand-OneClick|ike-sh/NoBrand-OneClick'
trap - ERR
MITA_STATE=/tmp/manager-state/install-state.env

# REALITY's container boundary is pure generation: wildcard TCP/REALITY/Vision
# server state/config plus three no-direct client exporters. Runtime data-plane
# qualification remains in scripts/test.sh --runtime.
(
  reality_id="r$(openssl rand -hex 8)"
  reality_uuid="$(tr -d '\r\n' </proc/sys/kernel/random/uuid)"
  reality_private="$(openssl rand -base64 32 | tr '/+' '_-' | tr -d '=\r\n')"
  reality_public="$(openssl rand -base64 32 | tr '/+' '_-' | tr -d '=\r\n')"
  reality_short="$(openssl rand -hex 8)"
  reality_config=/tmp/reality-docker-config.json
  reality_state=/tmp/reality-docker-state.json
  reality_key=/tmp/reality-docker-private.key
  printf '%s\n' "$reality_private" >"$reality_key"
  chmod 0600 "$reality_key"
  reality_generate_server_config "$reality_config" "$reality_id" 0.0.0.0 32052 \
    "$reality_uuid" "$reality_private" "$reality_short" example.com 443 22052
  reality_generate_state "$reality_state" "$reality_id" docker-reality 0.0.0.0 32052 \
    custom 198.51.100.52 32052 "$reality_uuid" "$reality_public" "$reality_key" \
    "$reality_short" example.com 443 chrome / "$TESTED_XRAY_VERSION" \
    "$NOBRAND_LEGACY_INGRESS_PROFILE_ID" 22052 2026-09-01T00:00:00Z
  reality_state_matches "$reality_state" "$reality_id"
  jq -e '.inbounds[0].streamSettings.network=="tcp"
    and .inbounds[0].streamSettings.security=="reality"
    and .inbounds[0].streamSettings.realitySettings.serverNames==["example.com"]
    and .inbounds[0].streamSettings.realitySettings.target=="127.0.0.1:22052"
    and .inbounds[1].listen=="127.0.0.1"
    and .inbounds[1].protocol=="dokodemo-door"
    and .routing.rules[3].domain==["full:example.com"]
    and .routing.rules[4].outboundTag=="BLOCK"' "$reality_config" >/dev/null
  rm -f "$reality_config" "$reality_state" "$reality_key"
)

# RC2 UI：品牌格式恢复；主菜单编号固定，卸载为直接入口，未安装摘要不泄漏默认 Profile/state。
grep -q '^# 作者: ike / https://github.com/ike-sh/NoBrand-OneClick$' /work/install-nobrand.sh
grep -q '作者: ${SCRIPT_AUTHOR} / https://github.com/${SCRIPT_REPO}' /work/install-nobrand.sh
! grep -Eq '主菜单[[:space:]]+[0-9]+|main menu[[:space:]]+[0-9]+|菜单[[:space:]]+\*{0,2}[0-9]+\)' \
  /work/install-nobrand.sh /work/README.md
(
  LANG_ZH=1 MENU_SCRIPTS_READY=1
  mita_installed(){ return 1; }
  load_install_state(){ PROFILE=custom; MIERU_VERSION=9.9.9; }
  users_count(){ echo 99; }
  installed_version(){ echo 9.9.9; }
  read_tty(){ printf -v "$1" '%s' 0; }
  set +e
  menu_output="$(show_menu)"
  menu_rc=$?
  set -e
  test "$menu_rc" -eq 2
  grep -q '^作者: ike / https://github.com/ike-sh/NoBrand-OneClick$' <<<"$menu_output"
  grep -q '^状态: 未安装$' <<<"$menu_output"
  grep -q '^用户: -$' <<<"$menu_output"
  grep -q '^配置预设 / Profile: -$' <<<"$menu_output"
  grep -q '^Mieru 版本: 未安装$' <<<"$menu_output"
  ! grep -q '^配置预设 / Profile: 高级自定义$' <<<"$menu_output"
  menu_entries="$(grep -E '^[[:space:]]+[0-9]+\)' <<<"$menu_output")"
  expected_entries="$(cat <<'EOF'
  1) 新装 / 安装
  2) 查看节点
  3) 用户管理
  4) 性能与网络
  5) 重新配置（需先安装）
  6) 服务管理
  7) 备份 / 恢复
  8) 升级
  9) Doctor / 诊断
 10) 卸载
  0) 退出
EOF
)"
  test "$menu_entries" = "$expected_entries"
)
(
  LANG_ZH=1 MENU_SCRIPTS_READY=1 ACTION=""
  mita_installed(){ return 0; }
  load_install_state(){ :; }
  users_count(){ echo 1; }
  installed_version(){ echo 3.35.0; }
  ensure_management_scripts(){ :; }
  read_tty(){ printf -v "$1" '%s' 10; }
  installed_menu_output_file=/tmp/rc2-installed-menu.out
  show_menu >"$installed_menu_output_file"
  grep -q '^  1) 修复安装$' "$installed_menu_output_file"
  test "$ACTION" = uninstall
)
(
  LANG_ZH=1 ACTION=""
  read_tty(){ printf -v "$1" '%s' 9; }
  show_performance_menu >/dev/null
  test "$ACTION" = version-channel
)
(
  LANG_ZH=1 ACTION=""
  read_tty(){ printf -v "$1" '%s' 10; }
  show_performance_menu >/dev/null
  test "$ACTION" = rate-restore
)
grep -q '确认仅卸载 NoBrand 3 管理的 Mieru 协议资源？\[y/N\]:' \
  /work/install-nobrand.sh

# 安装状态只允许从 root 所有且父目录不可写的常规文件读取。
(
  unsafe_dir=/tmp/unsafe-manager-state
  mkdir -p "$unsafe_dir"
  chmod 0777 "$unsafe_dir"
  printf 'USERNAME=unsafe-state-was-sourced\n' >"$unsafe_dir/install-state.env"
  chmod 0600 "$unsafe_dir/install-state.env"
  MITA_STATE="$unsafe_dir/install-state.env"
  USERNAME=unchanged
  if load_install_state >/dev/null 2>&1; then
    echo "unsafe install state unexpectedly accepted" >&2
    exit 1
  fi
  test "$USERNAME" != unsafe-state-was-sourced
)
(
  real_dir=/tmp/real-manager-state
  link_dir=/tmp/symlink-manager-state
  mkdir -p "$real_dir"
  chmod 0700 "$real_dir"
  ln -s "$real_dir" "$link_dir"
  printf 'USERNAME=symlink-state-was-sourced\n' >"$real_dir/install-state.env"
  chmod 0600 "$real_dir/install-state.env"
  MITA_STATE="$link_dir/install-state.env"
  USERNAME=unchanged
  if load_install_state >/dev/null 2>&1; then
    echo "state under symlink parent unexpectedly accepted" >&2
    exit 1
  fi
  test "$USERNAME" != symlink-state-was-sourced
)

# Clean break: legacy roots are detected but never read, copied, converted,
# deleted, or modified.
(
  legacy=/tmp/legacy-manager-state
  rm -rf "$legacy"; mkdir -p "$legacy"; chmod 0700 "$legacy"
  printf 'must-remain\n' >"$legacy/install-state.env"
  NOBRAND_LEGACY_MIERU_STATE_DIR="$legacy"
  if (ensure_manager_state_layout 0) >/dev/null 2>&1; then
    echo 'legacy state was unexpectedly accepted' >&2
    exit 1
  fi
  grep -qx 'must-remain' "$legacy/install-state.env"
)

# 空实例集合不能在 ERR trap 中产生伪失败输出。
empty_stop_output="$(
  (
    set -Eeuo pipefail
    trap on_error ERR
    MITA_USERS_STATE=/tmp/no-users.json
    MITA_INSTANCES_DIR=/tmp/no-instances
    mkdir -p "$MITA_INSTANCES_DIR"
    isolated_stop_all
  ) 2>&1
)"
test -z "$empty_stop_output"

# 状态、默认客户端模式与 MTU 策略。
printf "%s\n" \
  "SCHEMA_VERSION=3" "OWNERSHIP=nobrand-v3" \
  "PORT=26000" "PORT_RANGE=" "PROTOCOL=TCP" "PROFILE=custom" "MTU=1452" "MTU_POLICY=custom" \
  "ADVERTISE_HOST=" "ADVERTISE_PORT=" \
  "USERNAME=alice" "PASSWORD=alice-pass" "TRAFFIC_PATTERN=off" \
  "TRAFFIC_SEED=" \
  "LOW_ENTROPY_MODE=LOW_ENTROPY_MODE_OFF" \
  "MULTIPLEXING=MULTIPLEXING_OFF" "HANDSHAKE_MODE=HANDSHAKE_NO_WAIT" \
  "MIERU_CHANNEL=stable" "MIERU_VERSION=3.35.0" \
  "INSTALL_SCRIPT=/work/install-nobrand.sh" "INSTALL_METHOD=nobrand-v3" >"$MITA_STATE"
chmod 600 "$MITA_STATE"
load_install_state
test "$USERNAME|$PASSWORD|$PORT|$PROTOCOL|$MTU|$MTU_POLICY" = \
  "alice|alice-pass|26000|TCP|1452|custom"
test "$PROFILE|$MIERU_CHANNEL" = "custom|stable"
# stable 升级不得自动切 latest，也不得把已安装的更高版本降级。
(
  upgrade_dir=/tmp/stable-upgrade
  rm -rf "$upgrade_dir"; mkdir -p "$upgrade_dir"; chmod 0700 "$upgrade_dir"
  MITA_MANAGER_STATE_DIR="$upgrade_dir"
  MITA_STATE="$upgrade_dir/install-state.env"
  MITA_USERS_STATE="$upgrade_dir/users.json"
  MITA_MARKER="$upgrade_dir/.installed"
  printf '%s\n' \
    'SCHEMA_VERSION=3' 'OWNERSHIP=nobrand-v3' \
    'PORT=30000' 'PORT_RANGE=' 'PROTOCOL=TCP' 'PROFILE=balanced' \
    'ADVERTISE_HOST=cm-entry.example.com' 'ADVERTISE_PORT=10086' \
    'MTU=1400' 'MTU_POLICY=safe' 'USERNAME=stable-user' 'PASSWORD=stable-pass' \
    'TRAFFIC_PATTERN=conservative' 'TRAFFIC_SEED=42' \
    'LOW_ENTROPY_MODE=LOW_ENTROPY_MODE_OFF' \
    'MULTIPLEXING=MULTIPLEXING_OFF' 'HANDSHAKE_MODE=HANDSHAKE_NO_WAIT' \
    'MIERU_CHANNEL=stable' 'MIERU_VERSION=3.35.0' \
    'INSTALL_SCRIPT=/work/install-nobrand.sh' 'INSTALL_METHOD=nobrand-v3' >"$MITA_STATE"
  chmod 0600 "$MITA_STATE"
  printf '%s\n' \
    '{"version":2,"deployment_model":"isolated-v2","protocol":"TCP","users":[{"instance_id":"u0000000000000001","name":"stable-user","password":"stable-pass","port":30000,"enabled":true}]}' \
    >"$MITA_USERS_STATE"
  chmod 0600 "$MITA_USERS_STATE"
  touch "$MITA_MARKER"
  require_root(){ :; }
  require_linux(){ :; }
  require_cmd(){ :; }
  mita_installed(){ return 0; }
  detect_pkg_manager(){ echo deb; }
  detect_arch(){ echo amd64; }
  ensure_management_dependencies(){ :; }
  mieru_resolve_runtime(){
    MIERU_RUNTIME_RESOLVED_VERSION=3.36.0
    MIERU_RUNTIME_RESOLVED_URL=https://example.invalid/mita.deb
    MIERU_RUNTIME_RESOLVED_SHA256="$(printf '%064d' 0)"
    MIERU_RUNTIME_RESOLVED_CHECKSUM_URL=https://example.invalid/mita.deb.sha256.txt
  }
  installed_version(){ echo 3.40.0; }
  install_self_script(){ :; }
  admin_lock_acquire(){ :; }
  admin_lock_release(){ :; }
  users_tx_snapshot(){ printf /tmp/stable-upgrade.snapshot; }
  isolated_stop_all(){ :; }
  apply_users_config(){ :; }
  users_tx_commit(){ :; }
  verify_mita_running(){ :; }
  download_package(){ touch /tmp/stable-unexpected-download; }
  MENU_MODE=1
  rm -f /tmp/stable-unexpected-download
  do_upgrade >/dev/null
  test ! -e /tmp/stable-unexpected-download
  grep -qx 'MIERU_CHANNEL=stable' "$MITA_STATE"
  grep -qx 'MIERU_VERSION=3.36.0' "$MITA_STATE"
)
test "$(normalize_multiplexing off)" = MULTIPLEXING_OFF
test "$(normalize_handshake_mode no-wait)" = HANDSHAKE_NO_WAIT
test "$(normalize_low_entropy_mode 56)" = LOW_ENTROPY_MODE_56
test "$(normalize_mtu_policy auto)" = optimized
! valid_mtu 1279
valid_mtu 1280
valid_mtu 1500
! valid_mtu 1501
valid_nonnegative_int32 2147483647
! valid_nonnegative_int32 2147483648
valid_bandwidth_mbps 1000000
! valid_bandwidth_mbps 1000001
valid_advertise_port 1
valid_advertise_port 443
valid_advertise_port 65535
! valid_advertise_port 0
! valid_advertise_port 65536
valid_advertise_host 203.0.113.10
valid_advertise_host 2001:db8::1
valid_advertise_host cm-entry.example.com
! valid_advertise_host 'https://cm-entry.example.com'
! valid_advertise_host '-bad.example.com'
test "$(normalize_uint 00008)" = 8
ADVERTISE_HOST=203.0.113.10 ADVERTISE_PORT=443 PROTOCOL=TCP
validate_advertise_endpoint
PROTOCOL=BOTH
! validate_advertise_endpoint_values 203.0.113.10 65535 BOTH >/dev/null 2>&1
ADVERTISE_HOST="" ADVERTISE_PORT=""
PROTOCOL=TCP MTU=1500
calculate_optimized_mtu
test "$MTU|$MTU_POLICY" = "1400|optimized"
mtu_default_iface(){ echo eth-test; }
mtu_iface_value(){ echo 1500; }
mtu_route_family(){ echo IPv4; }
PROTOCOL=UDP
calculate_optimized_mtu
test "$MTU|$MTU_AUTO_LINK|$MTU_AUTO_OVERHEAD" = "1400|1500|28"

# Profile 只设置完整真实参数；反推只做精确匹配，手工偏离后自动变为 custom。
LANG_ZH=1
test "$(profile_label iplc)" = 'IPLC / 专线性能'
test "$(profile_label balanced)" = '普通公网'
test "$(profile_label stealth)" = '强化伪装'
test "$(profile_label custom)" = '高级自定义'
grep -q 'profile=default 是上游客户端的 profileName' /work/install-nobrand.sh
grep -q 'Mieru 使用官方 Mita runtime，并保留多用户、独立实例' /work/README.md
grep -q '官方 Mieru client JSON' /work/README.md
apply_profile_values iplc
test "$PROFILE|$PROTOCOL|$MTU|$MULTIPLEXING|$HANDSHAKE_MODE|$TRAFFIC_PATTERN|$LOW_ENTROPY_MODE" = \
  'iplc|TCP|1400|MULTIPLEXING_OFF|HANDSHAKE_NO_WAIT|off|LOW_ENTROPY_MODE_OFF'
test "$(infer_profile_from_values)" = iplc
MTU=1390
profile_reconcile_metadata
test "$PROFILE" = custom
apply_profile_values balanced
test "$(infer_profile_from_values)" = balanced
apply_profile_values stealth
test "$TRAFFIC_PATTERN|$LOW_ENTROPY_MODE|$(infer_profile_from_values)" = \
  'aggressive|LOW_ENTROPY_MODE_OFF|stealth'
(
  mieru_resolve_runtime(){
    case "$(normalize_mieru_channel "$1")" in
      stable)
        MIERU_RUNTIME_RESOLVED_VERSION="$TESTED_MIERU_VERSION"
        ;;
      latest)
        MIERU_RUNTIME_RESOLVED_VERSION=9.9.9
        ;;
      pinned)
        MIERU_RUNTIME_RESOLVED_VERSION="$2"
        ;;
    esac
  }
  MIERU_CHANNEL=stable
  mieru_resolve_runtime "$MIERU_CHANNEL" "${MIERU_VERSION:-}" deb amd64
  test "$MIERU_RUNTIME_RESOLVED_VERSION" = "$TESTED_MIERU_VERSION"
  MIERU_CHANNEL=latest
  mieru_resolve_runtime "$MIERU_CHANNEL" "${MIERU_VERSION:-}" deb amd64
  test "$MIERU_RUNTIME_RESOLVED_VERSION" = 9.9.9
  MIERU_CHANNEL=pinned MIERU_VERSION=3.40.1
  mieru_resolve_runtime "$MIERU_CHANNEL" "$MIERU_VERSION" deb amd64
  test "$MIERU_RUNTIME_RESOLVED_VERSION" = 3.40.1
)
apply_profile_values balanced
MIERU_CHANNEL=latest MIERU_VERSION=""

# trafficPattern、分享链接、官方客户端 JSON 与 mihomo YAML。
mita_supports_traffic_pattern(){ return 0; }
mita_supports_low_entropy(){ return 0; }
installed_version(){ echo 3.35.0; }
TRAFFIC_PATTERN=aggressive TRAFFIC_SEED=42 LOW_ENTROPY_MODE=LOW_ENTROPY_MODE_56
tp="$(traffic_pattern_json)"
grep -q '"unlockAll": false' <<<"$tp"
grep -q '"mode": "LOW_ENTROPY_MODE_56"' <<<"$tp"
compat_warning="$(warn_low_entropy_client_compat 2>&1)"
grep -q mihomo <<<"$compat_warning"
TRAFFIC_PATTERN=off LOW_ENTROPY_MODE=LOW_ENTROPY_MODE_OFF
PROTOCOL=TCP MTU=1400 MTU_POLICY=safe PORT=26000 USERNAME=alice PASSWORD=alice-pass
MULTIPLEXING=MULTIPLEXING_OFF HANDSHAKE_MODE=HANDSHAKE_NO_WAIT
link="$(generate_share_link_for 2001:db8::1 TCP)"
grep -q '^mierus://alice:alice-pass@\[2001:db8::1\]?' <<<"$link"
grep -q 'port=26000' <<<"$link"
grep -q 'mtu=1400' <<<"$link"
grep -q 'multiplexing=MULTIPLEXING_OFF' <<<"$link"
grep -q 'handshake-mode=HANDSHAKE_NO_WAIT' <<<"$link"
json="$(build_client_json_for 1.2.3.4 TCP)"
python3 -c 'import json,sys; d=json.load(sys.stdin); p=d["profiles"][0]; assert p["mtu"]==1400 and p["handshakeMode"]=="HANDSHAKE_NO_WAIT"' <<<"$json"
USERNAME='user: with/slash' PASSWORD='p"ass\word'
yaml="$(build_clash_yaml_full 1.2.3.4)"
grep -q 'username: "user: with/slash"' <<<"$yaml"
grep -Fq 'password: "p\"ass\\word"' <<<"$yaml"

# 自定义入口只改变客户端产物；服务端配置、防火墙提示仍使用真实监听端口。
USERNAME=alice PASSWORD=alice-pass PROTOCOL=TCP PORT=26000 PORT_RANGE=""
ADVERTISE_HOST=203.0.113.10 ADVERTISE_PORT=443
custom_link="$(generate_share_link_for "$ADVERTISE_HOST" TCP)"
grep -q '@203.0.113.10?' <<<"$custom_link"
grep -q 'port=443' <<<"$custom_link"
custom_json="$(build_client_json_for "$ADVERTISE_HOST" TCP)"
python3 -c 'import json,sys; d=json.load(sys.stdin); s=d["profiles"][0]["servers"][0]; assert s["ipAddress"]=="203.0.113.10" and s["portBindings"]==[{"port":443,"protocol":"TCP"}]' <<<"$custom_json"
ADVERTISE_PORT=08
leading_zero_json="$(build_client_json_for "$ADVERTISE_HOST" TCP)"
python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["profiles"][0]["servers"][0]["portBindings"][0]["port"]==8' <<<"$leading_zero_json"
ADVERTISE_PORT=443
custom_yaml="$(build_clash_yaml_full "$ADVERTISE_HOST")"
grep -q 'server: "203.0.113.10"' <<<"$custom_yaml"
grep -q 'port: 443' <<<"$custom_yaml"

# Golden：后端 203.0.113.10:30000 与客户端域名入口 cm-entry.example.com:10086 严格分离。
PORT=30000 ADVERTISE_HOST=cm-entry.example.com ADVERTISE_PORT=10086
domain_link="$(generate_share_link_for "$ADVERTISE_HOST" TCP)"
grep -q '@cm-entry.example.com?' <<<"$domain_link"
grep -q 'port=10086' <<<"$domain_link"
domain_json="$(build_client_json_for "$ADVERTISE_HOST" TCP)"
python3 -c 'import json,sys; s=json.load(sys.stdin)["profiles"][0]["servers"][0]; assert s["ipAddress"]=="" and s["domainName"]=="cm-entry.example.com" and s["portBindings"]==[{"port":10086,"protocol":"TCP"}]' <<<"$domain_json"
domain_yaml="$(build_clash_yaml_full "$ADVERTISE_HOST")"
grep -q 'server: "cm-entry.example.com"' <<<"$domain_yaml"
grep -q 'port: 10086' <<<"$domain_yaml"
domain_server_cfg="$(write_server_config)"
python3 -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); raw=open(p).read(); assert d["portBindings"]==[{"port":30000,"protocol":"TCP"}] and "cm-entry.example.com" not in raw and "10086" not in raw' "$domain_server_cfg"
rm -f "$domain_server_cfg"
domain_fw_hint="$(cloud_firewall_hint)"
grep -q '30000/TCP' <<<"$domain_fw_hint"
! grep -q '10086/TCP' <<<"$domain_fw_hint"

PORT=26000 ADVERTISE_HOST=203.0.113.10 ADVERTISE_PORT=443
printf stale > /root/nobrand_mieru_client_legacy.json
compact_output="$(print_protocol_outputs "$ADVERTISE_HOST")"
grep -Eq '(已保存|Saved):[[:space:]]+/root/nobrand-mieru-clients/current/alice_tcp\.json' <<<"$compact_output"
! grep -q '"profiles"' <<<"$compact_output"
test -f /root/nobrand-mieru-clients/current/alice_tcp.json
first_client_hash="$(sha256sum /root/nobrand-mieru-clients/current/alice_tcp.json | awk '{print $1}')"
print_protocol_outputs "$ADVERTISE_HOST" >/dev/null
test "$(find /root/nobrand-mieru-clients/current -maxdepth 1 -type f -name 'alice_tcp.json' | wc -l)" -eq 1
test "$(sha256sum /root/nobrand-mieru-clients/current/alice_tcp.json | awk '{print $1}')" = "$first_client_hash"
test -z "$(find /root -maxdepth 1 -type f -name 'mieru_client_*.json' -print -quit)"
client_config_output="$(
  public_ip(){ echo 198.51.100.40; }
  generate_client_config
)"
grep -q 'mieru apply config <客户端本地 JSON 路径>' <<<"$client_config_output"
! grep -q 'mieru apply config /root' <<<"$client_config_output"
! grep -q 'mieru_client_.*\*\.json' <<<"$client_config_output"
grep -q '【客户端入口映射】' <<<"$client_config_output"
grep -q '客户端: 203.0.113.10:443/TCP' <<<"$client_config_output"
grep -q -- '-> 后端: 198.51.100.40:26000/TCP' <<<"$client_config_output"

# 显式填写的入口若与探测公网 IP/后端端口相同，不显示独立入口或映射。
(
  PORT=17353 PROTOCOL=TCP ADVERTISE_HOST=203.0.113.173 ADVERTISE_PORT=17353
  public_ip(){ echo 203.0.113.173; }
  print_protocol_outputs(){ :; }
  same_mapping="$(print_client_endpoint_mapping)"
  test -z "$same_mapping"
  same_summary="$(print_summary current)"
  ! grep -q '客户端入口映射' <<<"$same_summary"
)

# 批量导出的人类可读输出也解释独立客户端入口，但客户端文件仍只写入口值。
(
  batch_root=/tmp/rc2-batch-export
  rm -rf "$batch_root"
  mkdir -p "$batch_root"
  MITA_USERS_STATE="$batch_root/users.json"
  MITA_CLIENT_EXPORT_DIR="$batch_root/clients"
  printf '%s\n' '{"version":2,"users":[{"name":"batch-user","password":"batch-pass","port":30000,"enabled":true,"advertise_host":"cm-entry.example.com","advertise_port":10086}]}' >"$MITA_USERS_STATE"
  chmod 0600 "$MITA_USERS_STATE"
  load_install_state(){
    PROTOCOL=TCP PORT=30000 PORT_RANGE="" MTU=1400 MTU_POLICY=safe
    MULTIPLEXING=MULTIPLEXING_OFF HANDSHAKE_MODE=HANDSHAKE_NO_WAIT
    TRAFFIC_PATTERN=off LOW_ENTROPY_MODE=LOW_ENTROPY_MODE_OFF
  }
  users_ensure_loaded(){ :; }
  public_ip(){ echo 203.0.113.173; }
  batch_output="$(do_user_export_clients 2>&1)"
  grep -q '【客户端入口映射】' <<<"$batch_output"
  grep -q '客户端: cm-entry.example.com:10086/TCP' <<<"$batch_output"
  grep -q -- '-> 后端: 203.0.113.173:30000/TCP' <<<"$batch_output"
  python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); s=d["profiles"][0]["servers"][0]; assert s["domainName"]=="cm-entry.example.com" and s["portBindings"][0]["port"]==10086' \
    "$(find "$MITA_CLIENT_EXPORT_DIR" -name 'batch-user_tcp.json' -print -quit)"
)
server_cfg="$(write_server_config)"
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d["portBindings"]==[{"port":26000,"protocol":"TCP"}] and "203.0.113.10" not in open(sys.argv[1]).read()' "$server_cfg"
rm -f "$server_cfg"
firewall_hint="$(cloud_firewall_hint)"
grep -q '26000/TCP' <<<"$firewall_hint"
! grep -q '443/TCP' <<<"$firewall_hint"
PROTOCOL=BOTH
grep -q 'port=443' <<<"$(generate_share_link_for "$ADVERTISE_HOST" TCP)"
grep -q 'port=444' <<<"$(generate_share_link_for "$ADVERTISE_HOST" UDP)"
dual_output="$(print_protocol_outputs "$ADVERTISE_HOST")"
grep -q '/root/nobrand-mieru-clients/current/alice_tcp.json' <<<"$dual_output"
grep -q '/root/nobrand-mieru-clients/current/alice_udp.json' <<<"$dual_output"
test -f /root/nobrand-mieru-clients/current/alice_tcp.json
test -f /root/nobrand-mieru-clients/current/alice_udp.json
PROTOCOL=TCP
print_protocol_outputs "$ADVERTISE_HOST" >/dev/null
test -f /root/nobrand-mieru-clients/current/alice_tcp.json
test ! -e /root/nobrand-mieru-clients/current/alice_udp.json
ADVERTISE_HOST="" ADVERTISE_PORT="" PROTOCOL=TCP

# 主用户改名只删除旧用户名导出；全局客户端参数变化必须失效全部用户导出。
(
  invalidation_dir=/tmp/client-invalidation
  MITA_CLIENT_EXPORT_DIR="$invalidation_dir"
  mkdir -p "$invalidation_dir/current"
  printf stale >"$invalidation_dir/current/old-user_tcp.json"
  printf stale >"$invalidation_dir/current/old-user_udp.json"
  printf keep >"$invalidation_dir/current/bob_tcp.json"
  USERNAME=new-user PROTOCOL=TCP MTU=1400 TRAFFIC_PATTERN=off TRAFFIC_SEED=""
  LOW_ENTROPY_MODE=LOW_ENTROPY_MODE_OFF MULTIPLEXING=MULTIPLEXING_OFF
  HANDSHAKE_MODE=HANDSHAKE_NO_WAIT
  client_exports_after_reconfigure old-user TCP 1400 off "" \
    LOW_ENTROPY_MODE_OFF MULTIPLEXING_OFF HANDSHAKE_NO_WAIT
  test ! -e "$invalidation_dir/current/old-user_tcp.json"
  test ! -e "$invalidation_dir/current/old-user_udp.json"
  test -f "$invalidation_dir/current/bob_tcp.json"
  printf stale >"$invalidation_dir/current/new-user_tcp.json"
  PROTOCOL=UDP
  client_exports_after_reconfigure new-user TCP 1400 off "" \
    LOW_ENTROPY_MODE_OFF MULTIPLEXING_OFF HANDSHAKE_NO_WAIT
  test -z "$(find "$invalidation_dir/current" -maxdepth 1 -type f -name '*.json' -print -quit)"
)

# 安装交互必须始终显示地址和端口问题；公网 IP / 后端端口只能作为默认建议值。
(
  ADVERTISE_HOST="" ADVERTISE_PORT="" ADVERTISE_CLI=0 PORT=26000 PROTOCOL=TCP
  public_ip(){ echo 198.51.100.1; }
  read_tty(){ printf -v "$1" '%s' ''; }
  collect_advertise_endpoint_interactive >/dev/null
  test "$ADVERTISE_HOST|$ADVERTISE_PORT" = '198.51.100.1|26000'
)
(
  ADVERTISE_HOST="" ADVERTISE_PORT="" ADVERTISE_CLI=0 PORT=26000 PROTOCOL=TCP
  public_ip(){ echo 198.51.100.2; }
  advertise_read_count=0
  read_tty(){
    advertise_read_count=$((advertise_read_count + 1))
    if [ "$advertise_read_count" -eq 1 ]; then
      printf -v "$1" '%s' cm-entry.example.com
    else
      printf -v "$1" '%s' 8443
    fi
  }
  collect_advertise_endpoint_interactive >/dev/null
  test "$ADVERTISE_HOST|$ADVERTISE_PORT" = 'cm-entry.example.com|8443'
)
# -y 也不能静默跳过入口确认；必须显式给 endpoint 或 --advertise-auto。
noninteractive_endpoint_root="$(mktemp -d /tmp/nobrand-endpoint.XXXXXX)"
mkdir -p "$noninteractive_endpoint_root/run/nobrand-oneclick"
chmod 0700 "$noninteractive_endpoint_root" \
  "$noninteractive_endpoint_root/run" \
  "$noninteractive_endpoint_root/run/nobrand-oneclick"
set +e
noninteractive_endpoint_output="$(
  NOBRAND_STATE_DIR="$noninteractive_endpoint_root/state" \
  NOBRAND_CONFIG_DIR="$noninteractive_endpoint_root/config" \
  NOBRAND_LIB_DIR="$noninteractive_endpoint_root/lib" \
  NOBRAND_LIFECYCLE_DIR="$noninteractive_endpoint_root/nobrand-oneclick-lifecycle" \
  NOBRAND_LIFECYCLE_TX_FILE="$noninteractive_endpoint_root/nobrand-oneclick-lifecycle/transaction.env" \
  NOBRAND_LIFECYCLE_LOCK_FILE="$noninteractive_endpoint_root/run/nobrand-oneclick/lifecycle.lock" \
  NOBRAND_INSTALL_SCRIPT_PATH="$noninteractive_endpoint_root/bin/install-nobrand" \
  NOBRAND_COMMAND_PATH="$noninteractive_endpoint_root/bin/nobrand" \
  NOBRAND_SHORT_COMMAND_PATH="$noninteractive_endpoint_root/bin/nb" \
  NOBRAND_LEGACY_MIERU_STATE_DIR="$noninteractive_endpoint_root/legacy/mita-oneclick" \
  MITA_SOURCE_ONLY=0 bash /work/install-nobrand.sh \
    mieru install -y --port 26000 --user explicit-user --password explicit-pass 2>&1
)"
noninteractive_endpoint_rc=$?
set -e
test "$noninteractive_endpoint_rc" -ne 0
grep -q -- '--advertise-host/--advertise-port' <<<"$noninteractive_endpoint_output"
rm -rf -- "$noninteractive_endpoint_root"

# 端口探测必须区分 TCP/UDP；尾号段选择不得返回已监听端口。
python3 -c 'import socket,time; s=socket.socket(); s.bind(("127.0.0.1",26801)); s.listen(); time.sleep(20)' &
listener_pid=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do
  port_is_listening 26801 TCP && break
  sleep 0.1
done
port_is_listening 26801 TCP
! port_is_listening 26801 UDP
PROTOCOL=TCP
! port_available_for_mode 26801
kill "$listener_pid"
wait "$listener_pid" 2>/dev/null || true
port_available_for_mode 26801
(
  derive_port_base(){ echo 26800; }
  nb_port_available_for_profile(){ [ "$1" -eq 26899 ]; }
  PROTOCOL=TCP
  test "$(derive_port_from_ip)" = 26899
)
# 自动端口在落盘前被抢占时应自动更换；显式端口则必须拒绝。
(
  PORT=26801 PROTOCOL=TCP PORT_AUTO_SELECTED=1
  port_available_for_mode(){ [ "$1" = 26802 ]; }
  select_available_port(){ echo 26802; }
  ensure_install_port_available >/dev/null
  test "$PORT" = 26802
)
if (
  PORT=26801 PROTOCOL=TCP PORT_AUTO_SELECTED=0
  port_available_for_mode(){ return 1; }
  ensure_install_port_available >/dev/null 2>&1
); then
  echo "explicit occupied port unexpectedly accepted" >&2
  exit 1
fi
(
  MITA_STATE=/tmp/no-install-state.env
  MITA_USERS_STATE=/tmp/no-users-state.json
  ! mita_preservable_config_exists
)

# 构造用户状态；正数 bandwidth 在专属实例模型中必须允许。
require_root(){ :; }
require_linux(){ :; }
mita_installed(){ return 0; }
install_users_scheduler(){ :; }
port_is_listening(){ return 1; }
public_ip(){ echo 1.2.3.4; }
USERNAME=alice PASSWORD=alice-pass PORT=26000 PROTOCOL=TCP
ADVERTISE_HOST=203.0.113.10 ADVERTISE_PORT=443
USER_QUOTA_MB=0 USER_QUOTA_DAYS=0 USER_QUOTA_MODE=rolling
USER_PACKAGE=unlimited USER_EXPIRE="" USER_BANDWIDTH_MBPS=0
users_initialize_primary
test "$(users_get_field alice advertise_host)|$(users_get_field alice advertise_port)" = '203.0.113.10|443'
USER_BANDWIDTH_MBPS=10 USER_PACKAGE=custom USER_QUOTA_MB=1024 USER_QUOTA_DAYS=30
users_add bob bob-pass 26005 >/dev/null
test "$(users_count)" -eq 2
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert all(u.get("instance_id","").startswith("u") for u in d["users"]); assert next(u for u in d["users"] if u["name"]=="bob")["bandwidth_mbps"]==10; assert not next(u for u in d["users"] if u["name"]=="bob")["advertise_host"]' "$MITA_USERS_STATE"
user_list_output="$(do_user_list)"
grep -Eq '^alice[[:space:]]+26000[[:space:]]+启用[[:space:]]+不限量[[:space:]]+不限量[[:space:]]+-' \
  <<<"$user_list_output"

# flock 分支必须传递展示入口字段；重复入口及自定义/自动入口碰撞都应拒绝。
users_set_advertise_endpoint bob 198.51.100.20 8443
test "$(users_get_field bob advertise_host)|$(users_get_field bob advertise_port)" = '198.51.100.20|8443'
users_set_advertise_endpoint bob CM-Entry.Example.com 10086
users_validate_state_file "$MITA_USERS_STATE" TCP 1.2.3.4
test "$(users_get_field bob advertise_host)|$(users_get_field bob advertise_port)" = 'cm-entry.example.com|10086'
users_set_advertise_endpoint bob '' ''
conflict_state=/tmp/users-conflict.json
cp -f "$MITA_USERS_STATE" "$conflict_state"
python3 -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); u=next(x for x in d["users"] if x["name"]=="bob"); u.update({"advertise_host":"203.0.113.10","advertise_port":443}); json.dump(d,open(p,"w"),indent=2)' "$conflict_state"
if users_validate_state_file "$conflict_state" TCP 1.2.3.4; then
  echo "duplicate custom client endpoint unexpectedly accepted" >&2
  exit 1
fi
cp -f "$MITA_USERS_STATE" "$conflict_state"
python3 -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); u=next(x for x in d["users"] if x["name"]=="alice"); u.update({"advertise_host":"1.2.3.4","advertise_port":26005}); json.dump(d,open(p,"w"),indent=2)' "$conflict_state"
if users_validate_state_file "$conflict_state" TCP 1.2.3.4; then
  echo "custom/automatic client endpoint conflict unexpectedly accepted" >&2
  exit 1
fi
rm -f "$conflict_state" "$conflict_state.norm"

# mita perf 必须只读；仅独立入口显示 INFO，同公网 IP/端口不误报。
(
  rm -f /tmp/perf-unexpected-write
  run(){ touch /tmp/perf-unexpected-write; }
  save_install_state(){ touch /tmp/perf-unexpected-write; }
  apply_users_config(){ touch /tmp/perf-unexpected-write; }
  reconcile_isolated_instances(){ touch /tmp/perf-unexpected-write; }
  ensure_mita_daemon(){ touch /tmp/perf-unexpected-write; }
  start_mita(){ touch /tmp/perf-unexpected-write; }
  enable_bbr_fq(){ touch /tmp/perf-unexpected-write; }
  load_install_state(){ :; }
  users_state_exists(){ return 1; }
  installed_version(){ echo 3.35.0; }
  detect_public_ip_family(){ [ "$1" = 4 ] && echo 203.0.113.173 || echo 2606:4700:4700::1111; }
  perf_sysctl_value(){ [ "$1" = net.ipv4.tcp_congestion_control ] && echo bbr || echo fq; }
  tc_default_iface(){ echo eth-test; }
  mtu_iface_value(){ echo 1500; }
  tc(){ echo 'qdisc fq 0: root'; }
  ps(){ printf '1 0.1 1024 mita run\n'; }
  PORT=17353 PROTOCOL=TCP ADVERTISE_HOST=203.0.113.173 ADVERTISE_PORT=17353
  same_perf_output="$(do_perf)"
  ! grep -q '当前使用独立客户端入口' <<<"$same_perf_output"
  ! grep -q 'An independent client endpoint' <<<"$same_perf_output"

  PORT=30000 PROTOCOL=TCP ADVERTISE_HOST=cm-entry.example.com ADVERTISE_PORT=10086
  perf_output="$(do_perf)"
  grep -q 'Mieru 性能诊断' <<<"$perf_output"
  grep -q '后端监听端口: 30000' <<<"$perf_output"
  grep -q '客户端展示地址 / Display Endpoint: cm-entry.example.com' <<<"$perf_output"
  grep -q '\[INFO\] 当前使用独立客户端入口' <<<"$perf_output"
  grep -q '客户端: cm-entry.example.com:10086' <<<"$perf_output"
  grep -q '后端: 203.0.113.173:30000' <<<"$perf_output"
  ! grep -Eq '\[WARN\].*客户端入口|\[FAIL\].*客户端入口' <<<"$perf_output"
  grep -q '本报告为只读' <<<"$perf_output"
  test ! -e /tmp/perf-unexpected-write
)

# doctor: 无限速用户时规则缺失是正常状态；有限速用户缺规则必须失败。
(
  check(){ printf '%s|%s|%s\n' "$2" "$1" "${3:-}"; }
  users_rate_limited_count(){ echo 0; }
  doctor_tc_output="$(doctor_check_tc_limits)"
  grep -q '^1|用户限速规则|' <<<"$doctor_tc_output"
  ! grep -q '^0|' <<<"$doctor_tc_output"
)
(
  check(){ printf '%s|%s|%s\n' "$2" "$1" "${3:-}"; }
  users_rate_limited_count(){ echo 1; }
  tc_default_iface(){ echo eth-test; }
  tc(){ :; }
  TC_OWNED_STATE=/tmp/missing-doctor-tc-owned.filters
  rm -f "$TC_OWNED_STATE"
  doctor_tc_output="$(doctor_check_tc_limits)"
  grep -q '^0|clsact|' <<<"$doctor_tc_output"
  grep -q '^0|自有 filter 清单|' <<<"$doctor_tc_output"
)

# 状态页只显示运行与监听摘要，不调用 describe config 或暴露密码。
(
  status_bin=/tmp/mock-status-mita
  printf '%s\n' '#!/bin/sh' '[ "${1:-}" = version ] && echo 3.35.0' >"$status_bin"
  chmod 0755 "$status_bin"
  mita_bin(){ echo "$status_bin"; }
  service_manager(){ echo none; }
  users_isolated_mode(){ return 0; }
  users_enabled_instance_rows(){ printf 'u0000000000000001\talice\t26000\n'; }
  load_install_state(){ PROTOCOL=TCP; PASSWORD=alice-pass; }
  instance_cmd(){
    if [ "${2:-}" = status ]; then
      echo 'mita server status is "RUNNING"'
    else
      touch /tmp/status-unexpected-describe
      echo 'password: alice-pass'
    fi
  }
  rm -f /tmp/status-unexpected-describe
  status_output="$(do_status)"
  grep -q 'TCP 26000' <<<"$status_output"
  grep -q '隐藏密码' <<<"$status_output"
  ! grep -q 'alice-pass' <<<"$status_output"
  test ! -e /tmp/status-unexpected-describe
)

# 用真实可执行文件模拟 systemctl，验证包维护脚本只被拦截 mita enable/start。
setup_package_systemctl_mock(){
  local mock_bin="$1"
  rm -rf "$mock_bin"
  mkdir -p "$mock_bin"
  cat >"$mock_bin/systemctl" <<'MOCK_SYSTEMCTL'
#!/bin/sh
printf '%s\n' "$*" >>"$PACKAGE_GUARD_LOG"
case "${1:-}" in
  is-active) [ "${PACKAGE_SERVICE_WAS_ACTIVE:-0}" -eq 1 ] ;;
  *) exit 0 ;;
esac
MOCK_SYSTEMCTL
  chmod 0700 "$mock_bin/systemctl"
  PATH="$mock_bin:$PATH"
  export PATH PACKAGE_GUARD_LOG PACKAGE_SERVICE_WAS_ACTIVE
}

# 原服务未运行时，官方 postinst 可完成，但不得真的 enable/start 默认服务。
(
  PACKAGE_GUARD_LOG=/tmp/package-service-guard.log
  : >"$PACKAGE_GUARD_LOG"
  PACKAGE_SERVICE_WAS_ACTIVE=0
  setup_package_systemctl_mock /tmp/package-systemctl-inactive
  service_manager(){ echo systemd; }
  dpkg(){
    systemctl daemon-reload
    systemctl enable mita.service
    systemctl start mita.service
  }
  refresh_managed_mita_runtime(){ :; }
  mark_oneclick_install(){ :; }
  install_package /tmp/mock-mita.deb deb
  grep -q '^is-active --quiet mita.service$' "$PACKAGE_GUARD_LOG"
  grep -q '^daemon-reload$' "$PACKAGE_GUARD_LOG"
  ! grep -q '^enable mita.service$' "$PACKAGE_GUARD_LOG"
  ! grep -q '^start mita.service$' "$PACKAGE_GUARD_LOG"
)

# 安装前运行中的默认服务必须在包维护脚本结束后恢复一次。
(
  PACKAGE_GUARD_LOG=/tmp/package-service-guard-active.log
  : >"$PACKAGE_GUARD_LOG"
  PACKAGE_SERVICE_WAS_ACTIVE=1
  setup_package_systemctl_mock /tmp/package-systemctl-active
  service_manager(){ echo systemd; }
  dpkg(){
    systemctl enable mita.service
    systemctl start mita.service
  }
  refresh_managed_mita_runtime(){ :; }
  mark_oneclick_install(){ :; }
  install_package /tmp/mock-mita.deb deb
  test "$(grep -c '^start mita.service$' "$PACKAGE_GUARD_LOG")" -eq 1
  ! grep -q '^enable mita.service$' "$PACKAGE_GUARD_LOG"
)

# dpkg 首次失败后，apt-get -f 继承相同代理并可完成半安装修复。
(
  PACKAGE_GUARD_LOG=/tmp/package-service-guard-apt-repair.log
  : >"$PACKAGE_GUARD_LOG"
  PACKAGE_SERVICE_WAS_ACTIVE=0
  setup_package_systemctl_mock /tmp/package-systemctl-apt-repair
  service_manager(){ echo systemd; }
  dpkg(){ return 1; }
  apt-get(){
    systemctl daemon-reload
    systemctl enable mita.service
    systemctl start mita.service
    touch /tmp/package-apt-repair-complete
    return 0
  }
  refresh_managed_mita_runtime(){ :; }
  mark_oneclick_install(){ :; }
  rm -f /tmp/package-apt-repair-complete
  install_package /tmp/mock-mita.deb deb
  test -e /tmp/package-apt-repair-complete
  grep -q '^daemon-reload$' "$PACKAGE_GUARD_LOG"
  ! grep -q '^enable mita.service$' "$PACKAGE_GUARD_LOG"
  ! grep -q '^start mita.service$' "$PACKAGE_GUARD_LOG"
)

# dpkg --configure -a 自愈路径也必须使用代理，并在结束后删除临时目录。
(
  PACKAGE_GUARD_LOG=/tmp/package-service-guard-configure.log
  : >"$PACKAGE_GUARD_LOG"
  PACKAGE_SERVICE_WAS_ACTIVE=0
  setup_package_systemctl_mock /tmp/package-systemctl-configure
  service_manager(){ echo systemd; }
  dpkg(){
    test "$*" = '--configure -a'
    dirname "$(type -P systemctl)" >/tmp/package-configure-guard-dir
    systemctl enable mita.service
    systemctl start mita.service
  }
  configure_pending_deb_packages
  test ! -d "$(cat /tmp/package-configure-guard-dir)"
  ! grep -q '^enable mita.service$' "$PACKAGE_GUARD_LOG"
  ! grep -q '^start mita.service$' "$PACKAGE_GUARD_LOG"
)

# 安装失败也必须恢复旧服务并清理代理目录。
(
  PACKAGE_GUARD_LOG=/tmp/package-service-guard-failure.log
  : >"$PACKAGE_GUARD_LOG"
  PACKAGE_SERVICE_WAS_ACTIVE=1
  setup_package_systemctl_mock /tmp/package-systemctl-failure
  service_manager(){ echo systemd; }
  dpkg(){
    dirname "$(type -P systemctl)" >/tmp/package-failure-guard-dir
    return 1
  }
  apt-get(){ return 1; }
  MENU_MODE=1
  if install_package /tmp/mock-mita.deb deb >/dev/null 2>&1; then
    echo "failed package install unexpectedly succeeded" >&2
    exit 1
  fi
  test ! -d "$(cat /tmp/package-failure-guard-dir)"
  grep -q '^start mita.service$' "$PACKAGE_GUARD_LOG"
)

# 找不到真实 systemctl 时必须在调用包管理器前失败。
(
  PACKAGE_GUARD_LOG=/tmp/package-service-guard-setup-failure.log
  : >"$PACKAGE_GUARD_LOG"
  empty_path=/tmp/package-empty-path
  rm -rf "$empty_path"
  mkdir -p "$empty_path"
  rm -f /tmp/package-unexpected-dpkg
  PATH="$empty_path"
  export PATH
  service_manager(){ echo systemd; }
  dpkg(){ : >/tmp/package-unexpected-dpkg; }
  MENU_MODE=1
  if install_package /tmp/mock-mita.deb deb >/dev/null 2>&1; then
    echo "package install unexpectedly continued without real systemctl" >&2
    exit 1
  fi
  test ! -e /tmp/package-unexpected-dpkg
)

# 独立修改用户展示入口只更新状态，不应用或重启任何服务端实例。
(
  endpoint_state_dir=/tmp/endpoint-only-state
  rm -rf "$endpoint_state_dir"
  mkdir -p "$endpoint_state_dir"
  chmod 0700 "$endpoint_state_dir"
  MITA_STATE="$endpoint_state_dir/install-state.env"
  MITA_USERS_STATE="$endpoint_state_dir/users.json"
  MITA_USERS_LOCK="$endpoint_state_dir/users.lock"
  MITA_ADMIN_LOCK="$endpoint_state_dir/admin.lock"
  cp -f /tmp/manager-state/install-state.env "$MITA_STATE"
  cp -f /tmp/manager-state/users.json "$MITA_USERS_STATE"
  chmod 0600 "$MITA_STATE" "$MITA_USERS_STATE"
  apply_users_config(){ touch /tmp/endpoint-unexpected-apply; }
  instance_start_proxy(){ touch /tmp/endpoint-unexpected-start; }
  isolated_stop_all(){ touch /tmp/endpoint-unexpected-stop; }
  print_user_outputs(){ :; }
  rm -f /tmp/endpoint-unexpected-apply /tmp/endpoint-unexpected-start /tmp/endpoint-unexpected-stop
  USERNAME=bob ADVERTISE_HOST=cm-entry.example.com ADVERTISE_PORT=9443 ADVERTISE_CLI=1
  do_user_set_endpoint >/dev/null
  test "$(users_get_field bob advertise_host)|$(users_get_field bob advertise_port)" = 'cm-entry.example.com|9443'
  test ! -e /tmp/endpoint-unexpected-apply
  test ! -e /tmp/endpoint-unexpected-start
  test ! -e /tmp/endpoint-unexpected-stop
)

# 无 systemd 的容器中模拟实例控制，仅保留真实的单实例 JSON 生成和事务逻辑。
install_instance_runtime(){
  mkdir -p "$MITA_INSTANCES_DIR" "$MITA_INSTANCE_RUN_DIR" "$MITA_INSTANCE_METRICS_DIR"
  chown -R mita:mita "$MITA_INSTANCES_DIR" "$MITA_INSTANCE_RUN_DIR" "$MITA_INSTANCE_METRICS_DIR"
}
instance_ensure_openrc_service(){ :; }
FAIL_INSTANCE_ONCE=0
instance_start_proxy(){
  if [ "$FAIL_INSTANCE_ONCE" -eq 1 ]; then
    FAIL_INSTANCE_ONCE=0
    return 1
  fi
  return 0
}
instance_daemon_stop(){ :; }
instance_cmd(){
  local iid="$1" cmd="$2"
  case "$cmd" in
    status) echo 'mita server status is "RUNNING"' ;;
    get) echo "metrics ${iid}" ;;
    export) echo CCoQARoECAEQCg== ;;
    *) : ;;
  esac
}
harden_mita_permissions(){ :; }
TC_LOG=/tmp/tc.log
: >"$TC_LOG"
TC_FAIL_ONCE=0
tc(){
  printf '%s\n' "$*" >>"$TC_LOG"
  case "$*" in
    "qdisc show"*) echo 'qdisc clsact ffff: dev eth-test' ;;
    *"filter add"*)
      if [ "$TC_FAIL_ONCE" -eq 1 ]; then TC_FAIL_ONCE=0; return 1; fi
      ;;
  esac
  return 0
}

# Fresh install creates isolated-v2 directly and never touches a default service.
(
  fresh=/tmp/fresh-isolated
  rm -rf "$fresh"
  mkdir -p "$fresh/backups" "$fresh/instances" "$fresh/run" "$fresh/metrics"
  chmod 0700 "$fresh" "$fresh/backups"
  MITA_MANAGER_STATE_DIR="$fresh"
  MITA_STATE="$fresh/install-state.env"
  MITA_USERS_STATE="$fresh/users.json"
  MITA_USERS_LOCK="$fresh/users.lock"
  MITA_ADMIN_LOCK="$fresh/admin.lock"
  MITA_USERS_BACKUP_DIR="$fresh/backups"
  MITA_INSTANCES_DIR="$fresh/instances"
  MITA_INSTANCE_RUN_DIR="$fresh/run"
  MITA_INSTANCE_METRICS_DIR="$fresh/metrics"
  MITA_CLIENT_EXPORT_DIR="$fresh/clients"
  TC_OWNED_STATE="$fresh/tc-owned.filters"
  USERNAME=fresh-user PASSWORD=fresh-pass PORT=26100 PORT_RANGE="" PROTOCOL=TCP
  ADVERTISE_HOST="" ADVERTISE_PORT="" MTU=1400 MTU_POLICY=safe
  TRAFFIC_PATTERN=off TRAFFIC_SEED="" LOW_ENTROPY_MODE=LOW_ENTROPY_MODE_OFF
  MULTIPLEXING=MULTIPLEXING_OFF HANDSHAKE_MODE=HANDSHAKE_NO_WAIT
  install_self_script(){ :; }
  install_users_scheduler(){ :; }
  open_firewall_for_pairs(){ touch /tmp/fresh-firewall-opened; }
  close_firewall_for_bindings(){ :; }
  apply_config(){ touch /tmp/fresh-unexpected-default-apply; }
  start_mita(){ touch /tmp/fresh-unexpected-default-start; }
  rm -f /tmp/fresh-firewall-opened \
    /tmp/fresh-unexpected-default-apply \
    /tmp/fresh-unexpected-default-start
  install_fresh_isolated
  test "$(users_deployment_model)" = isolated-v2
  test "$(users_count)" -eq 1
  test -e /tmp/fresh-firewall-opened
  test ! -e /tmp/fresh-unexpected-default-apply
  test ! -e /tmp/fresh-unexpected-default-start
)

# A failed fresh dedicated instance cleans only resources created by the transaction.
(
  fresh=/tmp/fresh-isolated-failure
  rm -rf "$fresh"
  mkdir -p "$fresh/backups" "$fresh/instances" "$fresh/run" "$fresh/metrics"
  chmod 0700 "$fresh" "$fresh/backups"
  MITA_MANAGER_STATE_DIR="$fresh"
  MITA_STATE="$fresh/install-state.env"
  MITA_USERS_STATE="$fresh/users.json"
  MITA_USERS_LOCK="$fresh/users.lock"
  MITA_ADMIN_LOCK="$fresh/admin.lock"
  MITA_USERS_BACKUP_DIR="$fresh/backups"
  MITA_INSTANCES_DIR="$fresh/instances"
  MITA_INSTANCE_RUN_DIR="$fresh/run"
  MITA_INSTANCE_METRICS_DIR="$fresh/metrics"
  MITA_CLIENT_EXPORT_DIR="$fresh/clients"
  TC_OWNED_STATE="$fresh/tc-owned.filters"
  USERNAME=fresh-fail PASSWORD=fresh-pass PORT=26110 PORT_RANGE="" PROTOCOL=TCP
  ADVERTISE_HOST="" ADVERTISE_PORT="" MTU=1400 MTU_POLICY=safe
  TRAFFIC_PATTERN=off TRAFFIC_SEED="" LOW_ENTROPY_MODE=LOW_ENTROPY_MODE_OFF
  MULTIPLEXING=MULTIPLEXING_OFF HANDSHAKE_MODE=HANDSHAKE_NO_WAIT
  install_self_script(){ :; }
  install_users_scheduler(){ touch /tmp/fresh-fail-scheduler-created; }
  remove_users_scheduler(){ touch /tmp/fresh-fail-scheduler-removed; }
  instance_start_proxy(){ return 1; }
  instance_daemon_stop(){ touch /tmp/fresh-fail-instance-stopped; }
  open_firewall_for_pairs(){ touch /tmp/fresh-fail-unexpected-firewall; }
  tc_clear_owned_filters(){ touch /tmp/fresh-fail-tc-cleared; }
  rm -f /tmp/fresh-fail-*
  MENU_MODE=1
  if install_fresh_isolated >/dev/null 2>&1; then
    echo "failed fresh isolated install unexpectedly succeeded" >&2
    exit 1
  fi
  test ! -e "$MITA_USERS_STATE"
  test -e /tmp/fresh-fail-instance-stopped
  test -e /tmp/fresh-fail-scheduler-created
  test -e /tmp/fresh-fail-scheduler-removed
  test -e /tmp/fresh-fail-tc-cleared
  test ! -e /tmp/fresh-fail-unexpected-firewall
)

apply_users_config
test "$(users_deployment_model)" = isolated-v2
python3 - <<'PY'
import glob,json
files=glob.glob("/tmp/instances/*/server.json")
assert len(files)==2
for path in files:
    d=json.load(open(path))
    assert len(d["users"])==1
    assert len(d["portBindings"])==1
    assert "trafficPattern" not in d
PY
TRAFFIC_PATTERN=conservative TRAFFIC_SEED=42 LOW_ENTROPY_MODE=LOW_ENTROPY_MODE_OFF
apply_users_config
python3 -c 'import glob,json; assert all("trafficPattern" in json.load(open(p)) for p in glob.glob("/tmp/instances/*/server.json"))'
TRAFFIC_PATTERN=off
apply_users_config
python3 -c 'import glob,json; assert all("trafficPattern" not in json.load(open(p)) for p in glob.glob("/tmp/instances/*/server.json"))'

setup_reconfigure_fixture(){
  local fixture="$1"
  rm -rf "$fixture"
  mkdir -p "$fixture/backups" "$fixture/clients/current"
  chmod 0700 "$fixture" "$fixture/backups" "$fixture/clients" "$fixture/clients/current"
  MITA_STATE="$fixture/install-state.env"
  MITA_USERS_STATE="$fixture/users.json"
  MITA_USERS_LOCK="$fixture/users.lock"
  MITA_ADMIN_LOCK="$fixture/admin.lock"
  MITA_USERS_BACKUP_DIR="$fixture/backups"
  MITA_CLIENT_EXPORT_DIR="$fixture/clients"
  cp -f /tmp/manager-state/install-state.env "$MITA_STATE"
  cp -f /tmp/manager-state/users.json "$MITA_USERS_STATE"
  chmod 0600 "$MITA_STATE" "$MITA_USERS_STATE"
}

# 完全无变化时必须明确报告 no-op，且不应用服务端配置。
(
  setup_reconfigure_fixture /tmp/reconfigure-noop
  collect_reconfigure_interactive(){ :; }
  apply_users_config(){ touch /tmp/reconfigure-noop-unexpected-apply; }
  print_summary(){ :; }
  rm -f /tmp/reconfigure-noop-unexpected-apply
  reconfigure_output="$(do_reconfigure_impl)"
  grep -q '未检测到配置变化' <<<"$reconfigure_output"
  test ! -e /tmp/reconfigure-noop-unexpected-apply
)

# 客户端全局模式变化不重启服务，但必须失效所有用户的旧导出。
(
  setup_reconfigure_fixture /tmp/reconfigure-client-only
  printf stale >"$(client_current_dir)/alice_tcp.json"
  printf stale >"$(client_current_dir)/bob_tcp.json"
  collect_reconfigure_interactive(){ MULTIPLEXING=MULTIPLEXING_LOW; }
  apply_users_config(){ touch /tmp/reconfigure-client-unexpected-apply; }
  print_summary(){ :; }
  rm -f /tmp/reconfigure-client-unexpected-apply
  reconfigure_output="$(do_reconfigure_impl)"
  grep -q '仅客户端参数已更新' <<<"$reconfigure_output"
  grep -qx 'MULTIPLEXING=MULTIPLEXING_LOW' "$MITA_STATE"
  test -z "$(find "$(client_current_dir)" -maxdepth 1 -type f -name '*.json' -print -quit)"
  test ! -e /tmp/reconfigure-client-unexpected-apply
)

# 应用 Profile 时保存完整真实参数；不是在运行时只保存/推算 PROFILE。
(
  setup_reconfigure_fixture /tmp/reconfigure-profile
  apply_profile_values iplc
  PROFILE_CLI=1 PROTOCOL_CLI=1 MTU_CLI=1 MULTIPLEXING_CLI=1
  HANDSHAKE_CLI=1 TRAFFIC_CLI=1 LOW_ENTROPY_CLI=1
  MTU_REQUEST=1400 YES=1
  print_summary(){ :; }
  do_reconfigure_impl >/dev/null
  grep -qx 'PROFILE=iplc' "$MITA_STATE"
  grep -qx 'PROTOCOL=TCP' "$MITA_STATE"
  grep -qx 'MTU=1400' "$MITA_STATE"
  grep -qx 'MULTIPLEXING=MULTIPLEXING_OFF' "$MITA_STATE"
  grep -qx 'HANDSHAKE_MODE=HANDSHAKE_NO_WAIT' "$MITA_STATE"
  grep -qx 'TRAFFIC_PATTERN=off' "$MITA_STATE"
  grep -qx 'LOW_ENTROPY_MODE=LOW_ENTROPY_MODE_OFF' "$MITA_STATE"
)

# 主用户名变化只清理旧主用户导出，不删除其它用户仍有效的文件。
(
  setup_reconfigure_fixture /tmp/reconfigure-rename
  printf stale >"$(client_current_dir)/alice_tcp.json"
  printf keep >"$(client_current_dir)/bob_tcp.json"
  collect_reconfigure_interactive(){ USERNAME=alice-renamed; }
  apply_users_config(){ :; }
  print_summary(){ :; }
  reconfigure_output="$(do_reconfigure_impl)"
  grep -q '重新配置完成' <<<"$reconfigure_output"
  users_name_exists alice-renamed
  test ! -e "$(client_current_dir)/alice_tcp.json"
  test -f "$(client_current_dir)/bob_tcp.json"
)

# MTU 是全局参数，数值变化后必须失效所有用户的稳定导出。
(
  setup_reconfigure_fixture /tmp/mtu-global-invalidation
  printf stale >"$(client_current_dir)/alice_tcp.json"
  printf stale >"$(client_current_dir)/bob_tcp.json"
  choose_mtu_interactive(){ MTU=1390; MTU_POLICY=custom; }
  reconcile_isolated_instances(){ :; }
  verify_mita_running(){ return 0; }
  generate_client_config(){ :; }
  do_mtu_config >/dev/null
  grep -qx 'MTU=1390' "$MITA_STATE"
  test -z "$(find "$(client_current_dir)" -maxdepth 1 -type f -name '*.json' -print -quit)"
)

# 改端口不能改变实例 ID，也不能丢失专属 metrics。
bob_id="$(users_get_field bob instance_id)"
mkdir -p "$(instance_metrics_dir "$bob_id")"
printf bob-usage >"$(instance_metrics_file "$bob_id")"
_U_NAME=bob _U_PORT=26006 users_py_locked '
import json,os
p=os.environ["MITA_USERS_STATE"]; d=json.load(open(p))
next(u for u in d["users"] if u["name"]==os.environ["_U_NAME"])["port"]=int(os.environ["_U_PORT"])
json.dump(d,open(p,"w"),indent=2)
'
apply_users_config
test "$(users_get_field bob instance_id)" = "$bob_id"
grep -q bob-usage "$(instance_metrics_file "$bob_id")"
python3 -c 'import json,glob; p=glob.glob("/tmp/instances/*/server.json"); d=next(json.load(open(x)) for x in p if json.load(open(x))["users"][0]["name"]=="bob"); assert d["portBindings"][0]["port"]==26006'

# 应用失败必须恢复 users.json，并能重新生成旧实例配置。
before="$(sha256sum "$MITA_USERS_STATE" | awk '{print $1}')"
tx="$(users_tx_snapshot)"
users_del bob >/dev/null
FAIL_INSTANCE_ONCE=1
if apply_users_config "$tx" >/dev/null 2>&1; then
  echo "failed instance reconcile unexpectedly succeeded" >&2
  exit 1
fi
after="$(sha256sum "$MITA_USERS_STATE" | awk '{print $1}')"
test "$before" = "$after"
users_name_exists bob
grep -q bob-usage "$(instance_metrics_file "$bob_id")"
# apply 已消费回滚快照；外层重复调用必须幂等且不再报回滚失败。
users_tx_rollback "$tx" 0

# 不在状态中的实例数据只能在事务提交阶段清理。
orphan_id=u0000000000000001
mkdir -p "$MITA_INSTANCES_DIR/$orphan_id" "$(instance_metrics_dir "$orphan_id")"
printf orphan-usage >"$(instance_metrics_file "$orphan_id")"
orphan_tx="$(users_tx_snapshot)"
users_tx_commit "$orphan_tx"
test ! -d "$(instance_metrics_dir "$orphan_id")"
test ! -d "$MITA_INSTANCES_DIR/$orphan_id"

# 恢复必须采用备份内协议，并同时更新实例配置与 install-state。
cp -f "$MITA_USERS_STATE" /tmp/users-import.json
python3 -c 'import json; p="/tmp/users-import.json"; d=json.load(open(p)); d["protocol"]="UDP"; json.dump(d,open(p,"w"),indent=2)'
mkdir -p /root/nobrand-mieru-clients/current
printf stale > /root/nobrand-mieru-clients/current/alice_tcp.json
printf stale > /root/nobrand-mieru-clients/current/removed-user_udp.json
users_restore_from_file /tmp/users-import.json >/dev/null
test "$PROTOCOL" = UDP
grep -qx 'PROTOCOL=UDP' "$MITA_STATE"
test -z "$(find /root/nobrand-mieru-clients/current -maxdepth 1 -type f -name '*.json' -print -quit)"
python3 - <<'PY'
import glob,json
for path in glob.glob("/tmp/instances/*/server.json"):
    d=json.load(open(path))
    assert {x["protocol"] for x in d["portBindings"]} == {"UDP"}
PY
python3 -c 'import json; p="/tmp/users-import.json"; d=json.load(open(p)); d["protocol"]="INVALID"; json.dump(d,open(p,"w"),indent=2)'
if users_restore_from_file /tmp/users-import.json >/dev/null 2>&1; then
  echo "invalid imported protocol unexpectedly succeeded" >&2
  exit 1
fi

# calendar 只清 bob 的 metrics，不影响 alice。
alice_id="$(users_get_field alice instance_id)"
mkdir -p "$(instance_metrics_dir "$alice_id")" "$(instance_metrics_dir "$bob_id")"
printf alice-usage >"$(instance_metrics_file "$alice_id")"
printf bob-usage >"$(instance_metrics_file "$bob_id")"
python3 -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); u=next(x for x in d["users"] if x["name"]=="bob"); u.update({"quota_mode":"calendar","quota_mb":1024,"quota_days":30,"last_quota_reset":"2020-01"}); json.dump(d,open(p,"w"),indent=2)' "$MITA_USERS_STATE"
cal="$(users_scan_calendar_quota_reset)"
grep -qx bob <<<"$cal"
test ! -e "$(instance_metrics_file "$bob_id")"
grep -q alice-usage "$(instance_metrics_file "$alice_id")"

# 菜单路径传入的目标账号不能被 load_install_state 覆盖成主账号。
USERNAME=bob USER_PACKAGE=unlimited USER_QUOTA_MB="" USER_QUOTA_DAYS=""
USER_QUOTA_MODE=rolling USER_EXPIRE="" USER_BANDWIDTH_MBPS=""
do_user_set_quota >/dev/null
test "$(users_get_field bob quota_mb)" = 0

# 使用假 tc 验证仅管理保留 pref 的 filter，失败会恢复旧 manifest，且从不删除 qdisc。
: >"$TC_LOG"
PROTOCOL=TCP
apply_tc_limits
test -s "$TC_OWNED_STATE"
! grep -Eq 'qdisc (del|replace)|root handle' "$TC_LOG"
tc_before="$(sha256sum "$TC_OWNED_STATE" | awk '{print $1}')"
TC_FAIL_ONCE=1
if apply_tc_limits >/dev/null 2>&1; then
  echo "injected tc failure unexpectedly succeeded" >&2
  exit 1
fi
tc_after="$(sha256sum "$TC_OWNED_STATE" | awk '{print $1}')"
test "$tc_before" = "$tc_after"
! grep -Eq 'qdisc (del|replace)|root handle' "$TC_LOG"

# 防火墙只删除带所有权记录的规则；预先存在的同端口规则不得接管或删除。
MITA_FIREWALL_OWNED_STATE=/tmp/firewall-owned.bindings
FW_LOG=/tmp/firewall.log
: >"$FW_LOG"
IPT_PREEXIST=0
IPT_OWNED_EXISTS=0
IPT_DELETE_FAIL=0
iptables(){
  printf 'v4 %s\n' "$*" >>"$FW_LOG"
  case "$*" in
    "-C "*"--comment"*) [ "$IPT_OWNED_EXISTS" -eq 1 ] && return 0 || return 1 ;;
    "-C "*) [ "$IPT_PREEXIST" -eq 1 ] && return 0 || return 1 ;;
    "-I "*"--comment"*) IPT_OWNED_EXISTS=1; return 0 ;;
    "-D "*"--comment"*)
      [ "$IPT_DELETE_FAIL" -eq 1 ] && return 1
      IPT_OWNED_EXISTS=0
      return 0
      ;;
  esac
  return 0
}
ip6tables(){
  printf 'v6 %s\n' "$*" >>"$FW_LOG"
  case "$*" in
    "-C "*"--comment"*) [ "$IPT_OWNED_EXISTS" -eq 1 ] && return 0 || return 1 ;;
    "-C "*) [ "$IPT_PREEXIST" -eq 1 ] && return 0 || return 1 ;;
    "-I "*"--comment"*) IPT_OWNED_EXISTS=1; return 0 ;;
    "-D "*"--comment"*)
      [ "$IPT_DELETE_FAIL" -eq 1 ] && return 1
      IPT_OWNED_EXISTS=0
      return 0
      ;;
  esac
  return 0
}
iptables_accept_port 28000 tcp add
test "$(wc -l <"$MITA_FIREWALL_OWNED_STATE")" -eq 2
grep -q -- '--comment nobrand-mieru' "$FW_LOG"
iptables_accept_port 28000 tcp del
test ! -e "$MITA_FIREWALL_OWNED_STATE"
: >"$FW_LOG"
IPT_PREEXIST=1
iptables_accept_port 28001 tcp add
test ! -e "$MITA_FIREWALL_OWNED_STATE"
! grep -q ' -I ' "$FW_LOG"
iptables_accept_port 28001 tcp del
! grep -q ' -D ' "$FW_LOG"
# 删除失败时必须保留所有权清单并让卸载失败；重试成功后才能清掉清单。
IPT_PREEXIST=0
IPT_OWNED_EXISTS=1
IPT_DELETE_FAIL=1
printf 'iptables|tcp|28002\nip6tables|tcp|28002\n' >"$MITA_FIREWALL_OWNED_STATE"
if firewall_clear_all_owned >/dev/null 2>&1; then
  echo "failed firewall cleanup unexpectedly succeeded" >&2
  exit 1
fi
test "$(wc -l <"$MITA_FIREWALL_OWNED_STATE")" -eq 2
IPT_DELETE_FAIL=0
firewall_clear_all_owned
test ! -e "$MITA_FIREWALL_OWNED_STATE"

# 全部用户同时到期必须停掉全部实例，不能因“最后一个用户”保护而回滚为继续可用。
today="$(date +%F)"
python3 -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); [u.update({"enabled":True,"expire_at":sys.argv[2]}) for u in d["users"]]; json.dump(d,open(p,"w"),indent=2)' "$MITA_USERS_STATE" "$today"
expired="$(users_scan_expired)"
grep -qx alice <<<"$expired"
grep -qx bob <<<"$expired"
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d["users"] and not any(u["enabled"] for u in d["users"])' "$MITA_USERS_STATE"
python3 -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); next(u for u in d["users"] if u["name"]=="alice")["expire_at"]=""; json.dump(d,open(p,"w"),indent=2)' "$MITA_USERS_STATE"
USER_SHOW_NAME=alice
do_user_enable >/dev/null
test "$(users_get_field alice enabled)" = 1
grep -qx 'USERNAME=alice' "$MITA_STATE"
grep -qx 'ADVERTISE_HOST=203.0.113.10' "$MITA_STATE"
grep -qx 'ADVERTISE_PORT=443' "$MITA_STATE"

# 删除用户后只清理该用户的稳定客户端导出。
mkdir -p /root/nobrand-mieru-clients/current
printf keep > /root/nobrand-mieru-clients/current/alice_tcp.json
printf stale > /root/nobrand-mieru-clients/current/bob_tcp.json
printf stale > /root/nobrand-mieru-clients/current/bob_udp.json
USER_DEL_NAME=bob YES=1
do_user_del >/dev/null
test -f /root/nobrand-mieru-clients/current/alice_tcp.json
test ! -e /root/nobrand-mieru-clients/current/bob_tcp.json
test ! -e /root/nobrand-mieru-clients/current/bob_udp.json

# 静态安全边界：双栈防火墙、私有 metrics 挂载和稳定实例环境变量。
grep -q 'for ipt in iptables ip6tables' /work/install-nobrand.sh
grep -q 'BindPaths=.*MITA_INSTANCE_METRICS_DIR' /work/install-nobrand.sh
grep -q 'MITA_CONFIG_JSON_FILE=' /work/install-nobrand.sh
grep -q 'MITA_UDS_PATH=' /work/install-nobrand.sh
grep -Fq 'run chown root:mita "$MITA_INSTANCES_DIR"' /work/install-nobrand.sh
! grep -q 'enable_tcp_bbr.py' /work/install-nobrand.sh
perm_root=/tmp/instance-permission
mkdir -p "$perm_root/u0000000000000002"
chown root:mita "$perm_root"
chown mita:mita "$perm_root/u0000000000000002"
chmod 0750 "$perm_root" "$perm_root/u0000000000000002"
printf '{}' >"$perm_root/u0000000000000002/server.json"
chown mita:mita "$perm_root/u0000000000000002/server.json"
chmod 0600 "$perm_root/u0000000000000002/server.json"
setpriv --reuid=mita --regid=mita --init-groups \
  test -r "$perm_root/u0000000000000002/server.json"

# isolated-v2 卸载只停止专属实例，不调用已停用的默认 mita daemon。
(
  mock_mita=/tmp/mock-default-mita
  printf '%s\n' '#!/bin/sh' 'touch /tmp/unexpected-default-mita-stop' >"$mock_mita"
  chmod 0755 "$mock_mita"
  mita_bin(){ echo "$mock_mita"; }
  users_isolated_mode(){ return 0; }
  isolated_stop_all(){ touch /tmp/isolated-stop-called; }
  tc_clear_owned_filters(){ :; }
  service_manager(){ echo none; }
  rm -f /tmp/unexpected-default-mita-stop /tmp/isolated-stop-called
  stop_mita_for_uninstall
  test -e /tmp/isolated-stop-called
  test ! -e /tmp/unexpected-default-mita-stop
)

# BBR + FQ 已完整启用时不询问；缺项时回车默认执行本地配置。
(
  bbr_fq_enabled(){ return 0; }
  confirm(){ touch /tmp/bbr-unexpected-confirm; return 1; }
  enable_bbr_fq(){ touch /tmp/bbr-unexpected-enable; }
  rm -f /tmp/bbr-unexpected-confirm /tmp/bbr-unexpected-enable
  offer_bbr_fq >/dev/null
  test ! -e /tmp/bbr-unexpected-confirm
  test ! -e /tmp/bbr-unexpected-enable
)
(
  bbr_fq_enabled(){ return 1; }
  read_tty(){ printf -v "$1" '%s' ''; }
  enable_bbr_fq(){ touch /tmp/bbr-default-enable; }
  rm -f /tmp/bbr-default-enable
  ENABLE_BBR=0 YES=0
  offer_bbr_fq >/dev/null
  test -e /tmp/bbr-default-enable
)

# 本地实现写入固定 sysctl；卸载只恢复脚本接管的文件和运行值。
(
  BBR_SYSCTL_CONF=/tmp/mieru_tcp_bbr.conf
  BBR_STATE_FILE=/tmp/manager-state/bbr-created.state
  BBR_BACKUP_FILE=/tmp/manager-state/bbr-created.backup
  test_qdisc=pfifo_fast
  test_cc=cubic
  sysctl(){
    case "${1:-}|${2:-}" in
      '-n|net.core.default_qdisc') printf '%s\n' "$test_qdisc" ;;
      '-n|net.ipv4.tcp_congestion_control') printf '%s\n' "$test_cc" ;;
      '-n|net.ipv4.tcp_available_congestion_control') printf '%s\n' 'reno cubic bbr' ;;
      '-p|'*) test_qdisc=fq; test_cc=bbr ;;
      '-q|-w')
        case "${3:-}" in
          net.core.default_qdisc=*) test_qdisc="${3#*=}" ;;
          net.ipv4.tcp_congestion_control=*) test_cc="${3#*=}" ;;
        esac
        ;;
      *) return 1 ;;
    esac
  }
  modprobe(){ :; }
  rm -f "$BBR_SYSCTL_CONF" "$BBR_STATE_FILE" "$BBR_BACKUP_FILE"
  enable_bbr_fq >/dev/null
  bbr_fq_enabled
  grep -qx 'net.core.default_qdisc=fq' "$BBR_SYSCTL_CONF"
  grep -qx 'net.ipv4.tcp_congestion_control=bbr' "$BBR_SYSCTL_CONF"
  grep -qx created "$BBR_STATE_FILE"
  restore_owned_bbr_fq
  test ! -e "$BBR_SYSCTL_CONF"
  test ! -e "$BBR_STATE_FILE"
  test "$test_qdisc|$test_cc" = 'pfifo_fast|cubic'
)
(
  BBR_SYSCTL_CONF=/tmp/mieru_tcp_bbr-existing.conf
  BBR_STATE_FILE=/tmp/manager-state/bbr-replaced.state
  BBR_BACKUP_FILE=/tmp/manager-state/bbr-replaced.backup
  test_qdisc=fq_codel
  test_cc=cubic
  sysctl(){
    case "${1:-}|${2:-}" in
      '-n|net.core.default_qdisc') printf '%s\n' "$test_qdisc" ;;
      '-n|net.ipv4.tcp_congestion_control') printf '%s\n' "$test_cc" ;;
      '-n|net.ipv4.tcp_available_congestion_control') printf '%s\n' 'reno cubic bbr' ;;
      '-p|'*)
        while IFS='=' read -r key value; do
          case "$key" in
            net.core.default_qdisc) test_qdisc="$value" ;;
            net.ipv4.tcp_congestion_control) test_cc="$value" ;;
          esac
        done <"${2:-$BBR_SYSCTL_CONF}"
        ;;
      '-q|-w')
        case "${3:-}" in
          net.core.default_qdisc=*) test_qdisc="${3#*=}" ;;
          net.ipv4.tcp_congestion_control=*) test_cc="${3#*=}" ;;
        esac
        ;;
      *) return 1 ;;
    esac
  }
  modprobe(){ :; }
  rm -f "$BBR_STATE_FILE" "$BBR_BACKUP_FILE"
  printf '%s\n' 'net.core.default_qdisc=fq_codel' '# keep this original file' >"$BBR_SYSCTL_CONF"
  original_hash="$(sha256sum "$BBR_SYSCTL_CONF" | awk '{print $1}')"
  enable_bbr_fq >/dev/null
  grep -qx replaced "$BBR_STATE_FILE"
  restore_owned_bbr_fq
  test "$(sha256sum "$BBR_SYSCTL_CONF" | awk '{print $1}')" = "$original_hash"
  test "$test_qdisc|$test_cc" = 'fq_codel|cubic'
  test ! -e "$BBR_STATE_FILE"
)
(
  BBR_SYSCTL_CONF=/tmp/mieru_tcp_bbr-external.conf
  BBR_STATE_FILE=/tmp/manager-state/bbr-external.state
  BBR_BACKUP_FILE=/tmp/manager-state/bbr-external.backup
  printf '%s\n' 'net.core.default_qdisc=fq' 'net.ipv4.tcp_congestion_control=bbr' >"$BBR_SYSCTL_CONF"
  write_bbr_state created pfifo_fast cubic
  printf '%s\n' '# changed by administrator' 'net.core.default_qdisc=fq_codel' >"$BBR_SYSCTL_CONF"
  if restore_owned_bbr_fq >/dev/null 2>&1; then
    echo "externally modified BBR config unexpectedly overwritten during uninstall" >&2
    exit 1
  fi
  grep -qx '# changed by administrator' "$BBR_SYSCTL_CONF"
  test -e "$BBR_STATE_FILE"
  rm -f "$BBR_SYSCTL_CONF" "$BBR_STATE_FILE" "$BBR_BACKUP_FILE"
)
(
  BBR_SYSCTL_CONF=/tmp/mieru_tcp_bbr-uninstall-guard.conf
  BBR_STATE_FILE=/tmp/manager-state/bbr-uninstall-guard.state
  BBR_BACKUP_FILE=/tmp/manager-state/bbr-uninstall-guard.backup
  printf '%s\n' 'net.core.default_qdisc=fq' 'net.ipv4.tcp_congestion_control=bbr' >"$BBR_SYSCTL_CONF"
  write_bbr_state created pfifo_fast cubic
  printf '%s\n' '# changed by administrator' >"$BBR_SYSCTL_CONF"
  mita_uninstall_target_present(){ return 0; }
  installed_by_oneclick(){ return 0; }
  confirm(){ return 0; }
  stop_mita_for_uninstall(){ touch /tmp/bbr-guard-unexpected-stop; }
  rm -f /tmp/bbr-guard-unexpected-stop
  set +e
  (set -Eeuo pipefail; do_uninstall >/dev/null 2>&1)
  guarded_uninstall_rc=$?
  set -e
  test "$guarded_uninstall_rc" -ne 0
  test ! -e /tmp/bbr-guard-unexpected-stop
  rm -f "$BBR_SYSCTL_CONF" "$BBR_STATE_FILE" "$BBR_BACKUP_FILE"
)
(
  BBR_SYSCTL_CONF=/tmp/mieru_tcp_bbr-unmanaged.conf
  BBR_STATE_FILE=/tmp/manager-state/bbr-unmanaged.state
  BBR_BACKUP_FILE=/tmp/manager-state/bbr-unmanaged.backup
  printf '%s\n' 'net.core.default_qdisc=fq' >"$BBR_SYSCTL_CONF"
  rm -f "$BBR_STATE_FILE" "$BBR_BACKUP_FILE"
  restore_owned_bbr_fq
  test -e "$BBR_SYSCTL_CONF"
  rm -f "$BBR_SYSCTL_CONF"
)
(
  bbr_fq_enabled(){ return 0; }
  tc_default_iface(){ echo eth-test; }
  tc(){ echo 'qdisc fq 8001: root refcnt 2 limit 10000p buckets 1024 orphan_mask 1023'; }
  bbr_fq_active
  tc(){ echo 'qdisc fq_codel 0: root refcnt 2 limit 10240p'; }
  ! bbr_fq_active
)

# 菜单动作首个错误即停止；dry-run 不触碰持久化状态。
set +e
menu_probe="$(
  (
    set -Eeuo pipefail
    trap 'exit $?' ERR
    do_status(){ false; echo MENU_SHOULD_NOT_CONTINUE; }
    ACTION=status
    menu_run_action
  ) 2>&1
)"
menu_rc=$?
set -e
test "$menu_rc" -ne 0
! grep -q MENU_SHOULD_NOT_CONTINUE <<<"$menu_probe"
# 删除最后一个用户属于业务拒绝：显示警告、留在用户管理，且不触发全局步骤失败。
(
  require_root(){ :; }
  require_linux(){ :; }
  mita_installed(){ return 0; }
  load_install_state(){ :; }
  users_ensure_loaded(){ :; }
  users_count(){ echo 1; }
  users_name_exists(){ return 0; }
  users_tx_snapshot(){ echo snapshot; }
  users_tx_commit(){ :; }
  admin_lock_acquire(){ :; }
  admin_lock_release(){ :; }
  do_user_list(){ :; }
  LANG_ZH=0
  YES=0
  USER_DEL_NAME=""
  menu_choice_count=0
  read_tty(){
    local value="" prompt="${2:-}"
    case "$prompt" in
      *1-18*)
        menu_choice_count=$((menu_choice_count + 1))
        [ "$menu_choice_count" -eq 1 ] && value=3 || value=18
        ;;
      *) value=alice ;;
    esac
    printf -v "$1" '%s' "$value"
  }
  set +e
  user_delete_output="$(MAIN_MENU_ACTIVE=1 do_user_manage 2>&1)"
  user_delete_rc=$?
  set -e
  test "$user_delete_rc" -eq 3
  if ! grep -q '\[警告\] Cannot delete the last user' <<<"$user_delete_output"; then
    printf 'unexpected user deletion output:\n%s\n' "$user_delete_output" >&2
    exit 1
  fi
  ! grep -q '步骤失败' <<<"$user_delete_output"
  test "$(grep -c '^\[Users\]' <<<"$user_delete_output")" -eq 2
)
# 真实子操作错误也必须留在用户管理，并保留准确阶段且停止后续命令。
(
  require_root(){ :; }
  do_user_list(){ false; echo USER_ACTION_SHOULD_NOT_CONTINUE; }
  LANG_ZH=0
  menu_choice_count=0
  read_tty(){
    local value="" prompt="${2:-}"
    if [[ "$prompt" == *1-18* ]]; then
      menu_choice_count=$((menu_choice_count + 1))
      [ "$menu_choice_count" -eq 1 ] && value=1 || value=18
    fi
    printf -v "$1" '%s' "$value"
  }
  set +e
  user_failure_output="$(MAIN_MENU_ACTIVE=1 do_user_manage 2>&1)"
  user_failure_rc=$?
  set -e
  test "$user_failure_rc" -eq 3
  grep -q '步骤失败: 列出用户' <<<"$user_failure_output"
  grep -q 'User operation failed' <<<"$user_failure_output"
  ! grep -q USER_ACTION_SHOULD_NOT_CONTINUE <<<"$user_failure_output"
  test "$(grep -c '^\[Users\]' <<<"$user_failure_output")" -eq 2
)
# 专属实例启动和重启只输出一条对应的最终结果。
(
  require_root(){ :; }
  mita_installed(){ return 0; }
  repair_mita_binary_paths(){ :; }
  start_mita(){ :; }
  users_isolated_mode(){ return 0; }
  verify_mita_running(){ test "${1:-0}" -eq 1; }
  LANG_ZH=0
  start_output="$(do_start)"
  test "$start_output" = 'All dedicated mita user instances started'

  users_enabled_instance_rows(){ printf 'u1\talice\t26000\n'; }
  instance_daemon_stop(){ :; }
  instance_start_proxy(){ :; }
  restart_output="$(do_restart)"
  test "$restart_output" = 'All dedicated mita user instances restarted'
)
# 用户管理 18 在主菜单上下文返回专用码，外层应立即重绘主菜单；独立调用则正常结束。
set +e
(
  MAIN_MENU_ACTIVE=1
  read_tty(){ printf -v "$1" '%s' 18; }
  do_user_manage >/dev/null
)
user_back_rc=$?
set -e
test "$user_back_rc" -eq 3
(
  MAIN_MENU_ACTIVE=0
  read_tty(){ printf -v "$1" '%s' 18; }
  do_user_manage >/dev/null
)
# 覆盖外层 menu_loop：用户管理返回码 3 必须直接重绘，不能落到 menu_pause。
(
  menu_show_count=0
  mita_installed(){ return 1; }
  show_menu(){
    menu_show_count=$((menu_show_count + 1))
    if [ "$menu_show_count" -eq 1 ]; then
      ACTION=user-manage
      return 0
    fi
    return 2
  }
  read_tty(){ printf -v "$1" '%s' 18; }
  menu_pause(){ touch /tmp/user-back-extra-pause; }
  rm -f /tmp/user-back-extra-pause
  menu_loop >/dev/null
  test ! -e /tmp/user-back-extra-pause
)
# 卸载成功通过特殊返回码退出菜单；用户取消则留在菜单且不报错。
set +e
(
  do_uninstall(){ UNINSTALL_CANCELLED=0; }
  ACTION=uninstall
  menu_run_action
)
uninstall_menu_rc=$?
set -e
test "$uninstall_menu_rc" -eq 2
(
  do_uninstall(){ UNINSTALL_CANCELLED=1; }
  ACTION=uninstall
  menu_run_action
)

# 首次接管前已存在的包/系统账号要记录为外部资源；卸载时不得删除包、账号或公共目录。
(
  ownership_dir=/tmp/preexisting-ownership
  rm -rf "$ownership_dir"
  MITA_MANAGER_STATE_DIR="$ownership_dir"
  MITA_MARKER="$ownership_dir/.installed"
  MITA_PRESERVE_PACKAGE_MARKER="$ownership_dir/preserve-preexisting-package"
  MITA_PRESERVE_USER_MARKER="$ownership_dir/preserve-preexisting-user"
  MITA_PRESERVE_GROUP_MARKER="$ownership_dir/preserve-preexisting-group"
  MITA_PRESERVE_SHARED_MARKER="$ownership_dir/preserve-preexisting-shared-runtime"
  installed_by_oneclick(){ return 1; }
  mita_package_is_installed(){ return 0; }
  _has_user(){ return 0; }
  _has_group(){ return 0; }
  run(){ "$@"; }
  record_preexisting_mita_resources deb
  test -f "$MITA_PRESERVE_PACKAGE_MARKER"
  test -f "$MITA_PRESERVE_USER_MARKER"
  test -f "$MITA_PRESERVE_GROUP_MARKER"
  test -f "$MITA_PRESERVE_SHARED_MARKER"
)
(
  UNINSTALL_PRESERVE_EXTERNAL=1
  UNINSTALL_PRESERVE_PACKAGE=1
  UNINSTALL_PRESERVE_USER=1
  UNINSTALL_PRESERVE_GROUP=1
  UNINSTALL_PRESERVE_SHARED=1
  run(){ printf 'RUN %s\n' "$*"; }
  find(){ :; }
  remove_users_scheduler(){ :; }
  preserved_cleanup_log="$(remove_mita_common)"
  ! grep -Eq '(^| )(deluser|userdel|delgroup|groupdel)( |$)' <<<"$preserved_cleanup_log"
  ! grep -Fq 'rm -rf /etc/mita /var/lib/mita' <<<"$preserved_cleanup_log"
  ! grep -Fq '/lib/systemd/system/mita.service' <<<"$preserved_cleanup_log"
  ! grep -Fq '/usr/lib/systemd/system/mita.service' <<<"$preserved_cleanup_log"
  ! grep -Fq '/var/log/mita.log /var/log/mita.err' <<<"$preserved_cleanup_log"
)
# 所有权标记必须逐项生效：只保留预先存在的用户时，OneClick 安装的包资源和组仍会清理。
(
  UNINSTALL_PRESERVE_EXTERNAL=1
  UNINSTALL_PRESERVE_PACKAGE=0
  UNINSTALL_PRESERVE_USER=1
  UNINSTALL_PRESERVE_GROUP=0
  UNINSTALL_PRESERVE_SHARED=0
  run(){ printf 'RUN %s\n' "$*"; }
  find(){ :; }
  dpkg(){ return 1; }
  _has_user(){ return 0; }
  _has_group(){ return 0; }
  remove_users_scheduler(){ :; }
  user_only_cleanup_log="$(remove_mita_common)"
  grep -Fq 'rm -rf /etc/mita /var/lib/mita' <<<"$user_only_cleanup_log"
  ! grep -Fq '/lib/systemd/system/mita.service' <<<"$user_only_cleanup_log"
  ! grep -Fq '/var/log/mita.log /var/log/mita.err' <<<"$user_only_cleanup_log"
  ! grep -Eq '(^| )(deluser|userdel) mita( |$)' <<<"$user_only_cleanup_log"
  grep -Eq '(^| )(delgroup|groupdel) mita( |$)' <<<"$user_only_cleanup_log"
)
(
  ownership_dir=/tmp/preexisting-uninstall
  rm -rf "$ownership_dir"
  mkdir -p "$ownership_dir"
  MITA_PRESERVE_PACKAGE_MARKER="$ownership_dir/preserve-preexisting-package"
  MITA_PRESERVE_USER_MARKER="$ownership_dir/preserve-preexisting-user"
  MITA_PRESERVE_GROUP_MARKER="$ownership_dir/preserve-preexisting-group"
  MITA_PRESERVE_SHARED_MARKER="$ownership_dir/preserve-preexisting-shared-runtime"
  touch "$MITA_PRESERVE_PACKAGE_MARKER" "$MITA_PRESERVE_USER_MARKER" \
    "$MITA_PRESERVE_GROUP_MARKER" "$MITA_PRESERVE_SHARED_MARKER"
  require_root(){ :; }
  mita_uninstall_target_present(){ return 0; }
  installed_by_oneclick(){ return 0; }
  confirm(){ return 0; }
  restore_owned_bbr_fq(){ return 0; }
  detect_pkg_manager(){ echo deb; }
  stop_mita_for_uninstall(){ :; }
  close_firewall(){ :; }
  firewall_clear_all_owned(){ :; }
  remove_mita_common(){
    test "$UNINSTALL_PRESERVE_EXTERNAL" -eq 1
    test "$UNINSTALL_PRESERVE_PACKAGE" -eq 1
    test "$UNINSTALL_PRESERVE_USER" -eq 1
    test "$UNINSTALL_PRESERVE_GROUP" -eq 1
    test "$UNINSTALL_PRESERVE_SHARED" -eq 1
  }
  verify_mita_uninstalled(){ return 0; }
  run(){ printf 'RUN %s\n' "$*"; }
  preserved_uninstall_output="$(do_uninstall)"
  grep -q '外部资源已保留' <<<"$preserved_uninstall_output"
  ! grep -Eq 'dpkg -P mita|rpm -e mita|userdel mita|groupdel mita' <<<"$preserved_uninstall_output"
)

(
  dry_run_root=/tmp/dry-run-nobrand
  rm -rf -- "$dry_run_root"
  NOBRAND_STATE_DIR="$dry_run_root/state"
  NOBRAND_CONFIG_DIR="$dry_run_root/config"
  NOBRAND_LIB_DIR="$dry_run_root/lib"
  NOBRAND_LIFECYCLE_DIR="$dry_run_root/lifecycle"
  NOBRAND_LIFECYCLE_TX_FILE="$NOBRAND_LIFECYCLE_DIR/transaction.env"
  NOBRAND_BACKUP_RESTORE_TX_DIR="$NOBRAND_LIFECYCLE_DIR/backup-restore"
  NOBRAND_BACKUP_RESTORE_META_FILE="$NOBRAND_BACKUP_RESTORE_TX_DIR/transaction.env"
  NOBRAND_BACKUP_RESTORE_SNAPSHOT_DIR="$NOBRAND_BACKUP_RESTORE_TX_DIR/snapshot"
  NOBRAND_BACKUP_RESTORE_ROOTS_MANIFEST="$NOBRAND_BACKUP_RESTORE_TX_DIR/snapshot-roots.manifest"
  NOBRAND_LIFECYCLE_LOCK_FILE="$dry_run_root/run/lifecycle.lock"
  NOBRAND_REGISTRY_FILE="$NOBRAND_STATE_DIR/state.json"
  NOBRAND_INSTALL_SCRIPT_PATH="$dry_run_root/bin/install-nobrand"
  NOBRAND_COMMAND_PATH="$dry_run_root/bin/nobrand"
  NOBRAND_SHORT_COMMAND_PATH="$dry_run_root/bin/nb"
  NOBRAND_LEGACY_MIERU_STATE_DIR="$dry_run_root/legacy-mieru"
  rm -f /tmp/dry-run-mutated
  do_install(){ touch /tmp/dry-run-mutated; }
  repair_mita_binary_paths(){ touch /tmp/dry-run-mutated; }
  ACTION=install DRY_RUN=1
  main >/tmp/dry-run.out
  test ! -e /tmp/dry-run-mutated
  grep -q DRY-RUN /tmp/dry-run.out
)

# 在无软件包、只有 schema-v3 Mieru ownership 残留的半安装状态下，
# 协议卸载必须清理 Mieru，同时保留统一管理器和 nb alias。
(
  fixture=/tmp/half-installed-v3
  rm -rf "$fixture"
  NOBRAND_STATE_DIR="$fixture/state"
  NOBRAND_REGISTRY_FILE="$NOBRAND_STATE_DIR/state.json"
  NOBRAND_BACKUP_DIR="$NOBRAND_STATE_DIR/backups"
  NOBRAND_LOCK_DIR="$NOBRAND_STATE_DIR/locks"
  MITA_MANAGER_STATE_DIR="$NOBRAND_STATE_DIR/mieru"
  MITA_MARKER="$MITA_MANAGER_STATE_DIR/.installed"
  MITA_STATE="$MITA_MANAGER_STATE_DIR/install-state.env"
  MITA_USERS_STATE="$MITA_MANAGER_STATE_DIR/users.json"
  MITA_USERS_LOCK="$MITA_MANAGER_STATE_DIR/users.lock"
  MITA_USERS_BACKUP_DIR="$MITA_MANAGER_STATE_DIR/backups"
  MITA_ADMIN_LOCK="$MITA_MANAGER_STATE_DIR/admin.lock"
  MITA_FIREWALL_OWNED_STATE="$MITA_MANAGER_STATE_DIR/firewall-owned.bindings"
  TC_OWNED_STATE="$MITA_MANAGER_STATE_DIR/tc-owned.filters"
  MITA_INSTANCES_DIR="$fixture/etc/instances"
  MITA_INSTANCE_RUN_DIR="$fixture/run"
  MITA_INSTANCE_METRICS_DIR="$fixture/metrics"
  MITA_CLIENT_EXPORT_DIR="$fixture/exports"
  MITA_BIN="$fixture/lib/bin/mita"
  MITA_INSTANCE_SYSTEMD_TEMPLATE="$fixture/systemd/nobrand-mieru@.service"
  MITA_INSTANCE_TMPFILES="$fixture/tmpfiles/nobrand-mieru.conf"
  MITA_INSTANCE_RUNNER="$fixture/lib/mieru-instance-run"
  MITA_INSTANCE_OPENRC_PREFIX="$fixture/openrc/nobrand-mieru-"
  MITA_USERS_TIMER="$fixture/systemd/nobrand-mieru-users-scan.timer"
  MITA_USERS_SERVICE="$fixture/systemd/nobrand-mieru-users-scan.service"
  MITA_USERS_CRON="$fixture/cron/nobrand-mieru-users"
  MITA_LOGROTATE_CONF="$fixture/logrotate/nobrand-mieru"
  MITA_USERS_LOG="$fixture/log/nobrand-mieru-users.log"
  BBR_STATE_FILE="$MITA_MANAGER_STATE_DIR/bbr-owned.state"
  BBR_BACKUP_FILE="$MITA_MANAGER_STATE_DIR/bbr-sysctl.backup"
  NOBRAND_INSTALL_SCRIPT_PATH="$fixture/commands/install-nobrand"
  NOBRAND_COMMAND_PATH="$fixture/commands/nobrand"
  NOBRAND_SHORT_COMMAND_PATH="$fixture/commands/nb"

  mkdir -p "$NOBRAND_STATE_DIR" "$MITA_MANAGER_STATE_DIR" \
    "$(dirname "$MITA_BIN")" "$(dirname "$MITA_INSTANCE_SYSTEMD_TEMPLATE")" \
    "$(dirname "$NOBRAND_INSTALL_SCRIPT_PATH")"
  chmod 0700 "$NOBRAND_STATE_DIR" "$MITA_MANAGER_STATE_DIR"
  printf '%s\n' \
    '{"schema_version":3,"project":"NoBrand-OneClick","ownership":"nobrand-v3","author":"ike"}' \
    >"$NOBRAND_REGISTRY_FILE"
  chmod 0600 "$NOBRAND_REGISTRY_FILE"
  touch "$MITA_MARKER" "$MITA_BIN" "$MITA_INSTANCE_SYSTEMD_TEMPLATE" \
    "$NOBRAND_INSTALL_SCRIPT_PATH"
  chmod 0755 "$NOBRAND_INSTALL_SCRIPT_PATH"
  ln -s install-nobrand "$NOBRAND_COMMAND_PATH"
  ln -s nobrand "$NOBRAND_SHORT_COMMAND_PATH"

  detect_pkg_manager(){ echo alpine; }
  dpkg(){ return 1; }
  dpkg-query(){ return 1; }
  isolated_stop_all(){ :; }
  tc_clear_owned_filters(){ :; }
  service_manager(){ echo none; }
  close_firewall(){ :; }
  firewall_clear_all_owned(){ :; }
  remove_users_scheduler(){ :; }
  restore_owned_bbr_fq(){ :; }
  verify_mita_uninstalled(){
    test ! -e "$MITA_MANAGER_STATE_DIR"
    test ! -e "$MITA_BIN"
    test ! -e "$MITA_INSTANCE_SYSTEMD_TEMPLATE"
  }
  YES=1 DRY_RUN=0 LANG_ZH=1
  uninstall_output="$(do_uninstall)"
  grep -q 'Mieru 协议资源已卸载' <<<"$uninstall_output"
  test -f "$NOBRAND_REGISTRY_FILE"
  test -x "$NOBRAND_INSTALL_SCRIPT_PATH"
  test "$(readlink "$NOBRAND_COMMAND_PATH")" = install-nobrand
  test "$(readlink "$NOBRAND_SHORT_COMMAND_PATH")" = nobrand
)

echo SMOKE_OK
DOCKER_TEST
echo "docker-smoke: PASS"
