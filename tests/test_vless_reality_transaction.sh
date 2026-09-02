#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/testlib.sh"

fixture="$(mktemp -d)"
trap 'rm -rf -- "$fixture"' EXIT
export NOBRAND_STATE_DIR="$fixture/nobrand-oneclick/state"
export NOBRAND_CONFIG_DIR="$fixture/nobrand-oneclick/config"
export NOBRAND_LIB_DIR="$fixture/nobrand-oneclick/lib"
export NOBRAND_REALITY_SYSTEMD_TEMPLATE="$fixture/systemd/nobrand-vless-reality@.service"
source_installer
eval "$(declare -f nb_atomic_install_file \
  | sed '1s/^nb_atomic_install_file /nb_atomic_install_file_under_test /')"

tx_stage=""
tx_private=""
tx_public=""
firewall_open_log="$fixture/firewall-open.log"
firewall_close_log="$fixture/firewall-close.log"

nobrand_prepare_common() { nb_init_state_layout; }
admin_lock_acquire() { :; }
admin_lock_release() { :; }
nb_port_is_listening() { return 1; }
nb_service_manager() { printf none; }
nobrand_install_manager_script() { :; }
reality_show() { :; }
reality_remove_service() { :; }
hysteria2_state_exists() { return 1; }
vless_sudoku_state_exists() { return 1; }

transaction_collect_success() {
  export VLESS_REALITY_NAME=transaction
  export VLESS_REALITY_TARGET=example.com
  export VLESS_REALITY_TARGET_PORT=443
  export VLESS_REALITY_CAMOUFLAGE_MODE=custom
  export VLESS_REALITY_FINGERPRINT=chrome
  export VLESS_REALITY_SPIDER_X=/
  export INGRESS_PROFILE_ID="$NOBRAND_LEGACY_INGRESS_PROFILE_ID"
  export PORT=33333
  export ADVERTISE_HOST=198.51.100.50
  export ADVERTISE_PORT=33333
}
reality_collect_install_requests() { transaction_collect_success; }

nobrand_install_xray_runtime() {
  [ "$tx_stage" != runtime ] || return 1
  mkdir -p "$(dirname "$NOBRAND_XRAY_BIN")"
  printf '%s\n' '#!/usr/bin/env bash' 'exit 0' >"$NOBRAND_XRAY_BIN"
  chmod 0755 "$NOBRAND_XRAY_BIN"
  mkdir -p "$NOBRAND_XRAY_ASSET_DIR"
  printf 'test-geoip\n' >"$NOBRAND_XRAY_ASSET_DIR/geoip.dat"
  printf 'test-geosite\n' >"$NOBRAND_XRAY_ASSET_DIR/geosite.dat"
}
nobrand_xray_version() { printf '%s' "$TESTED_XRAY_VERSION"; }
reality_generate_keypair() { printf '%s|%s' "$tx_private" "$tx_public"; }
reality_derive_public_key() { printf '%s' "$tx_public"; }
nobrand_xray_test_config() {
  [[ "$1" == *.json ]] || return 1
  [ "$tx_stage" != config_validation ]
}
reality_install_service_runtime() { [ "$tx_stage" != service_template ]; }
reality_ensure_openrc_service() { :; }
nb_firewall_open_pairs() {
  printf '%s\n' "$1" >>"$firewall_open_log"
  [ "$tx_stage" != firewall ]
}
nb_firewall_close_pairs() { printf '%s\n' "$1" >>"$firewall_close_log"; }
reality_service_action() { [ "$tx_stage" != service_start ]; }
nb_wait_for_listener() { [ "$tx_stage" != listener ]; }
nb_wait_for_listener_address() { [ "$tx_stage" != defender_listener ]; }
reality_listener_owned_by_service() { [ "$tx_stage" != pid_ownership ]; }
reality_defender_listener_owned_by_service() { [ "$tx_stage" != defender_pid_ownership ]; }
nb_atomic_install_file() {
  local destination="$2"
  case "$tx_stage:$destination" in
    key_commit:*/private.key|config_commit:*/config.json|state_commit:*/state.json) return 1 ;;
  esac
  nb_atomic_install_file_under_test "$@"
}

reset_transaction_fixture() {
  rm -rf -- "$NOBRAND_STATE_DIR" "$NOBRAND_CONFIG_DIR" "$NOBRAND_LIB_DIR" \
    "$(dirname "$NOBRAND_REALITY_SYSTEMD_TEMPLATE")"
  rm -f "$firewall_open_log" "$firewall_close_log"
  tx_private="$(openssl rand -base64 32 | tr '/+' '_-' | tr -d '=\r\n')"
  tx_public="$(openssl rand -base64 32 | tr '/+' '_-' | tr -d '=\r\n')"
}

assert_transaction_clean() {
  [ -z "$(reality_instance_ids 2>/dev/null || true)" ] \
    || fail "${tx_stage} rollback left REALITY state"
  [ ! -e "$NOBRAND_XRAY_BIN" ] || fail "${tx_stage} rollback left the newly installed Xray runtime"
  [ ! -e "$NOBRAND_XRAY_ASSET_DIR" ] \
    || fail "${tx_stage} rollback left the newly installed Xray assets"
  if [ -d "$NOBRAND_REALITY_STATE_DIR" ]; then
    [ -z "$(find "$NOBRAND_REALITY_STATE_DIR" -type f -print -quit)" ] \
      || fail "${tx_stage} rollback left a state file"
  fi
  if [ -d "$NOBRAND_REALITY_CONFIG_DIR" ]; then
    [ -z "$(find "$NOBRAND_REALITY_CONFIG_DIR" -type f -print -quit)" ] \
      || fail "${tx_stage} rollback left a config or key file"
  fi
  [ ! -e "$NOBRAND_REALITY_SYSTEMD_TEMPLATE" ] \
    || fail "${tx_stage} rollback left a service template"
  if nb_registry_port_owner TCP 33333 >/dev/null 2>&1; then
    fail "${tx_stage} rollback left Common Port ownership"
  fi
}

for tx_stage in runtime config_validation key_commit config_commit state_commit \
  service_template firewall service_start listener pid_ownership defender_listener defender_pid_ownership; do
  reset_transaction_fixture
  if install_vless_reality >/dev/null 2>&1; then
    fail "REALITY install failure injection unexpectedly passed: ${tx_stage}"
  fi
  assert_transaction_clean
done

tx_stage=auto_pool_exhaustion
reset_transaction_fixture
reality_randomized_auto_candidates() {
  printf '%s\n' www.abmindustriesgroup.com www.oracle.com
}
reality_validate_target_live() { return 1; }
reality_collect_install_requests() {
  VLESS_REALITY_TARGET=""
  VLESS_REALITY_TARGET_PORT=443
  reality_apply_camouflage_defaults
  reality_resolve_camouflage_request
}
if install_vless_reality >/dev/null 2>&1; then
  fail 'exhausted automatic REALITY camouflage pool unexpectedly installed a node'
fi
assert_transaction_clean
printf 'REALITY_AUTO_POOL_EXHAUSTION_ROLLBACK=PASS\n'
reality_collect_install_requests() { transaction_collect_success; }

tx_stage=success
reset_transaction_fixture
install_vless_reality >/dev/null
installed_id="$(reality_instance_ids)"
[[ "$installed_id" =~ ^r[0-9a-f]{16}$ ]] || fail 'successful REALITY transaction instance ID'
reality_state_matches "$(reality_state_file "$installed_id")" "$installed_id" \
  || fail 'successful REALITY transaction state'
reality_config_matches_state "$installed_id" || fail 'successful REALITY transaction config/key parity'
assert_file_mode 600 "$(reality_private_key_file "$installed_id")"
assert_eq '0:0' "$(stat -c '%u:%g' "$(reality_private_key_file "$installed_id")")" \
  'successful REALITY private-key ownership'
assert_eq "vless-reality:${installed_id}" "$(nb_registry_port_owner TCP 33333)" \
  'successful REALITY Common Port ownership'
defender_port="$(reality_state_field "$installed_id" defender_port)"
assert_eq "vless-reality-defender:${installed_id}" "$(reality_defender_port_owner "$defender_port")" \
  'successful REALITY internal defender ownership'
if nb_registry_port_owner TCP "$defender_port" >/dev/null 2>&1; then
  fail 'successful REALITY defender polluted Common Port ownership'
fi

export VLESS_REALITY_NAME=transaction
remove_vless_reality_instance
[ -z "$(reality_instance_ids)" ] || fail 'REALITY formal removal left state'
[ ! -e "$(reality_config_file "$installed_id")" ] || fail 'REALITY formal removal left config'
[ ! -e "$(reality_private_key_file "$installed_id")" ] || fail 'REALITY formal removal left private key'
[ ! -e "$NOBRAND_XRAY_BIN" ] || fail 'last REALITY removal left an otherwise-unused shared Xray runtime'
[ ! -e "$NOBRAND_XRAY_ASSET_DIR" ] || fail 'last REALITY removal left otherwise-unused Xray assets'

pass 'VLESS REALITY runtime/config/key/state/service/firewall/listener/PID rollback and removal transactions'
