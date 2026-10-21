#!/usr/bin/env bash
# Profile globals are consumed by the sourced ingress implementation.
# shellcheck disable=SC2034
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/testlib.sh"
fixture="$(mktemp -d)"
trap 'rm -rf -- "$fixture"' EXIT
export NOBRAND_STATE_DIR="$fixture/nobrand-oneclick/state"
export NOBRAND_CONFIG_DIR="$fixture/nobrand-oneclick/config"
export NOBRAND_LIB_DIR="$fixture/nobrand-oneclick/lib"
export NOBRAND_TEST_INTERFACE_ROWS=$'eth0|192.0.2.110|UP|1\neth1|198.51.100.41|UP|0'
export NOBRAND_TEST_DEFAULT_EGRESS='eth0|192.0.2.110'
source_installer
nb_init_state_layout
nb_port_is_listening() { return 1; }
ingress_cli() {
  ingress_menu_reset_requests
  parse_nobrand_ingress_args "$@"
  nobrand_run_ingress_action
}
nb_ingress_list >/dev/null
[ ! -e "$NOBRAND_INGRESS_STATE_FILE" ] || fail 'read-only list created state'
ingress_cli add --name Public --type public --interface eth0 --address 192.0.2.110 --port-policy derived-tail --yes >/dev/null
ingress_cli add --name Mapped --type mapped --interface eth1 --address 198.51.100.41 \
  --port-policy custom-range --range-start 30001 --range-end 30020 --reserve 30005 \
  --advertise-host mapped.example --display-port-policy custom --display-port 443 --yes >/dev/null
public_id="$(nb_ingress_profile_id Public)"
mapped_id="$(nb_ingress_profile_id Mapped)"
assert_eq '11001|11099' "$(nb_ingress_profile_auto_range "$public_id")" 'derived range'
assert_eq '30001|30020' "$(nb_ingress_profile_auto_range "$mapped_id")" 'custom range'
assert_eq mapped.example "$(nb_ingress_profile_display_host "$mapped_id")" 'display host'
assert_eq 443 "$(nb_ingress_profile_display_port "$mapped_id" 30001)" 'display port'
NOBRAND_TEST_RANDOM_START=4
assert_eq 30006 "$(nb_select_available_port TCP "$mapped_id")" 'skip reserved'
if ( ingress_cli add --name Bad --type public --interface eth0 --address 198.51.100.41 --port-policy manual-only --yes ) >/dev/null 2>&1; then
  fail 'wrong interface accepted'
fi
# Actual native association blocks deletion and resolves the owner Profile.
generation="$NOBRAND_STATE_DIR/splicore/generations/test"
mkdir -p "$generation"
jq -n --arg profile "$mapped_id" '{nodes:[{id:"native",ingress:{profile_id:$profile}}]}' >"$generation/desired.json"
ln -s generations/test "$NOBRAND_STATE_DIR/splicore/current"
assert_eq splicore:native "$(nb_ingress_profile_reference_rows "$mapped_id")" 'native association'
assert_eq "$mapped_id" "$(nb_owner_ingress_profile_id splicore:native)" 'owner profile'
if ( ingress_cli delete Mapped --yes ) >/dev/null 2>&1; then fail 'referenced Profile deleted'; fi
rm "$NOBRAND_STATE_DIR/splicore/current"
ingress_cli delete Mapped --yes >/dev/null
nb_ingress_state_valid || fail 'invalid state after deletion'
pass 'native ingress association, interface validation, allocation, display metadata and deletion boundary'
