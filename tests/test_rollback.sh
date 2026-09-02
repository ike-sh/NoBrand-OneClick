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

# A fresh Xray transaction installs the executable and both official private
# assets together under the NoBrand runtime root.
(
  rm -f "$NOBRAND_XRAY_BIN"
  rm -rf -- "$NOBRAND_XRAY_ASSET_DIR"
  nobrand_download_xray_candidate() {
    printf '%s\n' '#!/usr/bin/env sh' \
      "printf 'Xray ${TESTED_XRAY_VERSION} test (go test linux/amd64)\\n'" >"$1"
    chmod 0755 "$1"
    mkdir -p "$2"
    printf 'fresh-geoip\n' >"$2/geoip.dat"
    printf 'fresh-geosite\n' >"$2/geosite.dat"
  }
  nobrand_xray_validate_managed_configs() { :; }
  nobrand_install_xray_runtime 0
)
assert_eq "$TESTED_XRAY_VERSION" "$(nobrand_xray_version)" 'fresh Xray runtime identity'
assert_eq fresh-geoip "$(tr -d '\r\n' <"$NOBRAND_XRAY_ASSET_DIR/geoip.dat")" \
  'fresh Xray geoip asset installation'
assert_eq fresh-geosite "$(tr -d '\r\n' <"$NOBRAND_XRAY_ASSET_DIR/geosite.dat")" \
  'fresh Xray geosite asset installation'
rm -f "$NOBRAND_XRAY_BIN"
rm -rf -- "$NOBRAND_XRAY_ASSET_DIR"

# A candidate that passes its temporary check but fails after replacement must restore the old Snell runtime.
snell_runtime="$(snell_runtime_path 5)"
printf 'old-snell-runtime\n' >"$snell_runtime"
chmod +x "$snell_runtime"
old_snell_hash="$(sha256sum "$snell_runtime")"
(
  snell_download_candidate() { printf 'invalid-new-snell\n' >"$2"; chmod +x "$2"; }
  snell_validate_runtime_config() { return 0; }
  snell_runtime_reported_version() {
    grep -q old-snell-runtime "$1" && { printf 5.0.0; return 0; }
    return 1
  }
  snell_install_runtime 5 1
) >/dev/null 2>&1 && fail 'invalid replacement Snell runtime must fail'
assert_eq "$old_snell_hash" "$(sha256sum "$snell_runtime")" 'Snell binary rollback'

# The same atomic replacement guarantee applies to the isolated Xray runtime.
printf 'old-xray-runtime\n' >"$NOBRAND_XRAY_BIN"
chmod +x "$NOBRAND_XRAY_BIN"
mkdir -p "$NOBRAND_XRAY_ASSET_DIR"
printf 'old-geoip\n' >"$NOBRAND_XRAY_ASSET_DIR/geoip.dat"
printf 'old-geosite\n' >"$NOBRAND_XRAY_ASSET_DIR/geosite.dat"
old_xray_hash="$(sha256sum "$NOBRAND_XRAY_BIN")"
old_geoip_hash="$(sha256sum "$NOBRAND_XRAY_ASSET_DIR/geoip.dat")"
old_geosite_hash="$(sha256sum "$NOBRAND_XRAY_ASSET_DIR/geosite.dat")"
(
  nobrand_download_xray_candidate() {
    printf 'invalid-new-xray\n' >"$1"; chmod +x "$1"
    mkdir -p "$2"
    printf 'candidate-geoip\n' >"$2/geoip.dat"
    printf 'candidate-geosite\n' >"$2/geosite.dat"
  }
  nobrand_xray_version() {
    grep -q old-xray-runtime "$NOBRAND_XRAY_BIN" && { printf 1.0.0; return 0; }
    return 1
  }
  nobrand_install_xray_runtime 1
) >/dev/null 2>&1 && fail 'invalid replacement Xray runtime must fail'
assert_eq "$old_xray_hash" "$(sha256sum "$NOBRAND_XRAY_BIN")" 'Xray binary rollback'
assert_eq "$old_geoip_hash" "$(sha256sum "$NOBRAND_XRAY_ASSET_DIR/geoip.dat")" \
  'Xray geoip asset rollback'
assert_eq "$old_geosite_hash" "$(sha256sum "$NOBRAND_XRAY_ASSET_DIR/geosite.dat")" \
  'Xray geosite asset rollback'

# A valid Xray replacement whose running HY2 service fails acceptance must also restore the old runtime.
jq -n '{protocol:"hysteria2",listen_port:3692,enabled:true,runtime_version:"old"}' >"$NOBRAND_HY2_STATE_FILE"
(
  nobrand_prepare_common() { :; }
  admin_lock_acquire() { :; }
  admin_lock_release() { :; }
  nobrand_hy2_service_active() { return 0; }
  nobrand_install_xray_runtime() { printf 'valid-but-service-fails\n' >"$NOBRAND_XRAY_BIN"; chmod +x "$NOBRAND_XRAY_BIN"; }
  restart_count=0
  nobrand_hy2_service_action() {
    if [ "$1" = restart ]; then
      restart_count=$((restart_count + 1))
      [ "$restart_count" -gt 1 ]
    fi
  }
  nb_wait_for_listener() { return 1; }
  hysteria2_upgrade_runtime
) >/dev/null 2>&1 && fail 'HY2 service acceptance failure must fail the upgrade'
assert_eq "$old_xray_hash" "$(sha256sum "$NOBRAND_XRAY_BIN")" 'Xray service-failure runtime rollback'

# Shared Xray upgrade acceptance is atomic across both active services. If the
# VLESS listener fails after HY2 has already restarted, both state files and the
# runtime must be restored and both services restarted on the old binary.
jq -n '{protocol:"hysteria2",listen_port:3692,enabled:true,runtime_version:"old"}' \
  >"$NOBRAND_HY2_STATE_FILE"
jq -n '{protocol:"vless-sudoku",listen_port:3693,enabled:true,runtime_version:"old"}' \
  >"$NOBRAND_VLESS_STATE_FILE"
old_hy2_state_hash="$(sha256sum "$NOBRAND_HY2_STATE_FILE")"
old_vless_state_hash="$(sha256sum "$NOBRAND_VLESS_STATE_FILE")"
shared_calls="$fixture/shared-upgrade.calls"
(
  nobrand_prepare_common() { :; }
  admin_lock_acquire() { :; }
  admin_lock_release() { :; }
  nobrand_hy2_service_active() { return 0; }
  nobrand_vless_sudoku_service_active() { return 0; }
  nobrand_install_xray_runtime() { printf 'shared-new-runtime\n' >"$NOBRAND_XRAY_BIN"; chmod +x "$NOBRAND_XRAY_BIN"; }
  nobrand_xray_version() { printf '%s' "$TESTED_XRAY_VERSION"; }
  nobrand_hy2_service_action() { printf 'hy2:%s\n' "$1" >>"$shared_calls"; }
  nobrand_vless_sudoku_service_action() { printf 'vless:%s\n' "$1" >>"$shared_calls"; }
  nb_wait_for_listener() { [ "$1" != TCP ]; }
  nobrand_upgrade_xray_runtime
) >/dev/null 2>&1 && fail 'shared upgrade must fail when active VLESS listener acceptance fails'
assert_eq "$old_xray_hash" "$(sha256sum "$NOBRAND_XRAY_BIN")" 'shared Xray runtime rollback'
assert_eq "$old_hy2_state_hash" "$(sha256sum "$NOBRAND_HY2_STATE_FILE")" 'shared HY2 state rollback'
assert_eq "$old_vless_state_hash" "$(sha256sum "$NOBRAND_VLESS_STATE_FILE")" 'shared VLESS state rollback'
assert_eq 2 "$(grep -c '^hy2:restart$' "$shared_calls")" 'HY2 restart on candidate and rollback runtime'
assert_eq 2 "$(grep -c '^vless:restart$' "$shared_calls")" 'VLESS restart on candidate and rollback runtime'

# Two active REALITY instances must be one shared-runtime transaction. A
# failure committing the second instance's runtime metadata restores both
# states, the old Xray binary, and both active services.
reality_one=r1111111111111111
reality_two=r2222222222222222
mkdir -p "$(dirname "$(reality_state_file "$reality_one")")" \
  "$(dirname "$(reality_state_file "$reality_two")")"
jq -n --arg id "$reality_one" \
  '{schema_version:3,ownership:"nobrand-v3",protocol:"vless-reality",instance_id:$id,
    listen_port:3694,runtime_version:"old",enabled:true}' \
  >"$(reality_state_file "$reality_one")"
jq -n --arg id "$reality_two" \
  '{schema_version:3,ownership:"nobrand-v3",protocol:"vless-reality",instance_id:$id,
    listen_port:3695,runtime_version:"old",enabled:true}' \
  >"$(reality_state_file "$reality_two")"
old_reality_one_hash="$(sha256sum "$(reality_state_file "$reality_one")")"
old_reality_two_hash="$(sha256sum "$(reality_state_file "$reality_two")")"
reality_calls="$fixture/reality-shared-upgrade.calls"
(
  nobrand_prepare_common() { :; }
  admin_lock_acquire() { :; }
  admin_lock_release() { :; }
  nobrand_hy2_service_active() { return 1; }
  nobrand_vless_sudoku_service_active() { return 1; }
  reality_service_active() { return 0; }
  nobrand_install_xray_runtime() { printf 'shared-reality-new-runtime\n' >"$NOBRAND_XRAY_BIN"; chmod +x "$NOBRAND_XRAY_BIN"; }
  nobrand_xray_version() { printf '%s' "$TESTED_XRAY_VERSION"; }
  reality_service_action() { printf '%s:%s\n' "$1" "$2" >>"$reality_calls"; }
  nb_wait_for_listener() { :; }
  reality_listener_owned_by_service() { :; }
  hysteria2_refresh_runtime_metadata() { :; }
  vless_sudoku_refresh_runtime_metadata() { :; }
  eval "$(declare -f nb_atomic_install_file \
    | sed '1s/^nb_atomic_install_file /nb_atomic_install_file_before_reality_failure /')"
  nb_atomic_install_file() {
    [ "$2" != "$(reality_state_file "$reality_two")" ] || return 1
    nb_atomic_install_file_before_reality_failure "$@"
  }
  nobrand_upgrade_xray_runtime
) >/dev/null 2>&1 && fail 'shared REALITY upgrade must fail when one state metadata commit fails'
assert_eq "$old_xray_hash" "$(sha256sum "$NOBRAND_XRAY_BIN")" 'multi-REALITY Xray runtime rollback'
assert_eq "$old_reality_one_hash" "$(sha256sum "$(reality_state_file "$reality_one")")" \
  'first REALITY state rollback after second state commit failure'
assert_eq "$old_reality_two_hash" "$(sha256sum "$(reality_state_file "$reality_two")")" \
  'second REALITY state rollback after its commit failure'
assert_eq 2 "$(grep -c "^${reality_one}:restart$" "$reality_calls")" \
  'first REALITY restart on candidate and rollback runtime'
assert_eq 2 "$(grep -c "^${reality_two}:restart$" "$reality_calls")" \
  'second REALITY restart on candidate and rollback runtime'
rm -rf -- "$(dirname "$(reality_state_file "$reality_one")")" \
  "$(dirname "$(reality_state_file "$reality_two")")"

run_snell_failure_case() (
  set -Eeuo pipefail
  trap - ERR
  case_mode="$1"
  case_root="$fixture/nobrand-oneclick-${case_mode}"
  NOBRAND_STATE_DIR="$case_root/state"
  NOBRAND_CONFIG_DIR="$case_root/config"
  NOBRAND_LIB_DIR="$case_root/lib"
  NOBRAND_BIN_DIR="$NOBRAND_LIB_DIR/bin"
  NOBRAND_SNELL_STATE_DIR="$NOBRAND_STATE_DIR/snell/instances"
  NOBRAND_SNELL_CONFIG_DIR="$NOBRAND_CONFIG_DIR/snell/instances"
  NOBRAND_SNELL_RUNTIME_DIR="$NOBRAND_BIN_DIR/snell"
  NOBRAND_FIREWALL_OWNED_STATE="$NOBRAND_STATE_DIR/firewall-owned.bindings"
  mkdir -p "$NOBRAND_SNELL_STATE_DIR" "$NOBRAND_SNELL_CONFIG_DIR" "$NOBRAND_SNELL_RUNTIME_DIR"
  fixed_id=s1111111111111111
  nobrand_prepare_common() { :; }
  snell_collect_install_requests() {
    # Request globals are consumed indirectly by install_snell.
    # shellcheck disable=SC2034
    SNELL_VERSION=5 SNELL_NAME="failure-${case_mode}" SNELL_PSK=0123456789abcdef
    # shellcheck disable=SC2034
    PORT=3691 ADVERTISE_HOST=entry.example.com ADVERTISE_PORT=443
  }
  snell_install_runtime() { :; }
  admin_lock_acquire() { :; }
  admin_lock_release() { :; }
  snell_generate_instance_id() { printf '%s' "$fixed_id"; }
  snell_runtime_reported_version() { printf 5.0.1; }
  snell_install_service_runtime() { :; }
  snell_ensure_openrc_service() { :; }
  snell_service_active() { return 1; }
  nb_wait_for_listener() { return 1; }
  nobrand_install_manager_script() { :; }
  nb_port_available_for_transport() { [ "$case_mode" != port-race ]; }
  snell_config_matches_state_files() { [ "$case_mode" != config-invalid ]; }
  nb_firewall_open_pairs() {
    [ "$case_mode" != firewall-failure ] || return 1
    printf 'iptables|tcp|3691\n' >"$NOBRAND_FIREWALL_OWNED_STATE"
  }
  nb_firewall_close_pairs() { rm -f "$NOBRAND_FIREWALL_OWNED_STATE"; }
  snell_service_action() {
    [ "$2" != start ] || [ "$case_mode" != service-failure ]
  }
  snell_remove_service() { :; }
  if [ "$case_mode" = state-write ]; then
    nb_atomic_install_file() {
      if [ "$2" = "$NOBRAND_SNELL_STATE_DIR/$fixed_id.json" ]; then return 1; fi
      mkdir -p "$(dirname "$2")"
      install -m "${3:-0600}" "$1" "$2"
    }
  fi
  set +e
  install_snell >/dev/null 2>&1
  install_rc=$?
  set -e
  [ "$install_rc" -ne 0 ] || fail "${case_mode}: failed transaction unexpectedly succeeded"
  [ -z "$(find "$NOBRAND_SNELL_STATE_DIR" -type f -print -quit)" ] || fail "${case_mode}: stale state remains"
  [ -z "$(find "$NOBRAND_SNELL_CONFIG_DIR" -type f -print -quit)" ] || fail "${case_mode}: stale config remains"
  [ ! -e "$NOBRAND_FIREWALL_OWNED_STATE" ] || fail "${case_mode}: stale firewall ownership remains"
)

for mode in config-invalid port-race state-write firewall-failure service-failure; do
  run_snell_failure_case "$mode"
done

pass 'config/port/state/firewall/service and binary rollback matrix'
