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
jq -n '{protocol:"snell",instance_id:"s0123456789abcdef",name:"tcp-node",version:5,listen_port:3611,advertise_host:"",advertise_port:"",quic_proxy_enabled:false,managed_udp:false}' \
  >"$NOBRAND_SNELL_STATE_DIR/s0123456789abcdef.json"
assert_eq 'snell:s0123456789abcdef' "$(nb_registry_port_owner TCP 3611)" 'TCP state owner'
nb_registry_port_owner UDP 3611 >/dev/null 2>&1 && fail 'TCP state must not occupy UDP key'
nb_port_is_listening() { return 1; }
nb_port_available_for_transport 3600 TCP && fail 'reserved tail base must reject TCP'
nb_port_available_for_transport 3600 UDP && fail 'reserved tail base must reject UDP'
# Read indirectly by port_available_for_mode from the sourced installer.
# shellcheck disable=SC2034
PROTOCOL=TCP
port_available_for_mode 3600 && fail 'Mieru must reject the reserved tail base'
nb_port_available_for_transport 3611 UDP || fail 'UDP 3611 must remain available when only TCP state owns 3611'
nb_port_available_for_transport 3611 TCP && fail 'TCP 3611 must conflict with Snell state'
jq '.quic_proxy_enabled=true | .managed_udp=true' \
  "$NOBRAND_SNELL_STATE_DIR/s0123456789abcdef.json" >"$fixture/snell-quic.json"
mv "$fixture/snell-quic.json" "$NOBRAND_SNELL_STATE_DIR/s0123456789abcdef.json"
assert_eq 'snell:s0123456789abcdef' "$(nb_registry_port_owner UDP 3611)" 'QUIC state UDP owner'
nb_port_available_for_transport 3611 UDP && fail 'QUIC ON must reserve same-number UDP'

jq -n '{protocol:"vless-sudoku",listen_port:3612,advertise_host:"",advertise_port:""}' \
  >"$NOBRAND_VLESS_STATE_FILE"
jq -n '{protocol:"hysteria2",listen_port:3612,advertise_host:"",advertise_port:""}' \
  >"$NOBRAND_HY2_STATE_FILE"
assert_eq 'vless-sudoku:default' "$(nb_registry_port_owner TCP 3612)" 'VLESS TCP state owner'
assert_eq 'hy2:default' "$(nb_registry_port_owner UDP 3612)" 'HY2 UDP state owner on same number'
nb_port_available_for_transport 3612 TCP && fail 'VLESS must reserve TCP/3612'
nb_port_available_for_transport 3612 UDP && fail 'HY2 must reserve UDP/3612'

rm -f "$NOBRAND_SNELL_STATE_DIR/s0123456789abcdef.json" "$NOBRAND_VLESS_STATE_FILE" \
  "$NOBRAND_HY2_STATE_FILE" "$MITA_USERS_STATE"
mkdir -p "$(dirname "$MITA_STATE")"
chmod 0700 "$(dirname "$MITA_STATE")"
printf 'PORT=3650\nPROTOCOL=BOTH\n' >"$MITA_STATE"
chmod 0600 "$MITA_STATE"
legacy_rows="$(nb_registry_rows)"
[ -z "$legacy_rows" ] || fail 'schema-v3 registry must not read a single-instance state adapter'

unset NOBRAND_TEST_LOCAL_IPV4
nb_detect_local_ipv4() { return 1; }
# Read indirectly by nb_select_available_port from the sourced installer.
# shellcheck disable=SC2034
NOBRAND_TEST_RANDOM_START=0
fallback="$(nb_select_available_port UDP)"
nb_valid_port "$fallback" || fail 'no-IPv4 fallback must return valid port'

pass 'common tail-port allocator and transport-aware registry'
