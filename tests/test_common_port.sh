#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/testlib.sh"

fixture="$(mktemp -d)"
trap 'rm -rf -- "$fixture"' EXIT
export MITA_MANAGER_STATE_DIR="$fixture/mita-oneclick"
export NOBRAND_STATE_DIR="$fixture/nobrand-oneclick/state"
export NOBRAND_CONFIG_DIR="$fixture/nobrand-oneclick/config"
export NOBRAND_LIB_DIR="$fixture/nobrand-oneclick/lib"
export NOBRAND_LIFECYCLE_DIR="$fixture/nobrand-oneclick-lifecycle"
export NOBRAND_LIFECYCLE_TX_FILE="$NOBRAND_LIFECYCLE_DIR/transaction.env"
export NOBRAND_LIFECYCLE_LOCK_FILE="$fixture/run/nobrand-oneclick/lifecycle.lock"
export NOBRAND_TEST_LOCAL_IPV4=172.16.1.36
mkdir -p "$(dirname "$NOBRAND_LIFECYCLE_LOCK_FILE")"
chmod 0700 "$(dirname "$NOBRAND_LIFECYCLE_LOCK_FILE")"
source_installer

assert_eq 3600 "$(nb_port_base_for_ip 172.16.1.36)" 'tail base'
assert_eq '3601|3699' "$(nb_tail_port_bounds 172.16.1.36)" 'tail bounds'
assert_eq 'common:tail-base:172.16.1.36' "$(nb_tail_base_reservation_owner 3600)" \
  'tail base reservation owner'
nb_port_is_tail_base_reserved 3600 || fail 'tail base must be reserved'
nb_port_is_tail_base_reserved 3601 && fail 'first allocatable tail port must not be reserved'
nb_port_base_for_ip 10.0.0.0 >/dev/null 2>&1 && fail 'octet 0 must fall back'
nb_port_base_for_ip 10.0.0.255 >/dev/null 2>&1 && fail 'octet 255 must fall back'
nb_port_base_for_ip 10.0.0.10 >/dev/null 2>&1 && fail 'privileged tail range must fall back'
NOBRAND_TEST_RANDOM_START=10
check_after_3613() { [ "$1" -eq 3613 ]; }
assert_eq 3613 "$(nb_scan_port_span 3601 3699 check_after_3613)" 'random ring traversal'

nb_init_state_layout
nb_port_is_listening() { return 1; }
nb_port_available_for_transport 3600 TCP && fail 'reserved tail base must reject TCP'
nb_port_available_for_transport 3600 UDP && fail 'reserved tail base must reject UDP'
nb_port_available_for_transport 3611 TCP || fail 'free tail port should be available'

unset NOBRAND_TEST_LOCAL_IPV4
nb_detect_local_ipv4() { return 1; }
# Read indirectly by nb_select_available_port from the sourced installer.
# shellcheck disable=SC2034
NOBRAND_TEST_RANDOM_START=0
fallback="$(nb_select_available_port UDP)"
nb_valid_port "$fallback" || fail 'no-IPv4 fallback must return valid port'

pass 'common tail-port allocator and transport-aware registry'
