#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/testlib.sh"

fixture="$(mktemp -d)"
trap 'rm -rf -- "$fixture"' EXIT
export NOBRAND_STATE_DIR="$fixture/nobrand-oneclick/state"
export NOBRAND_CONFIG_DIR="$fixture/nobrand-oneclick/config"
export NOBRAND_LIB_DIR="$fixture/nobrand-oneclick/lib"
export MITA_INSTANCES_DIR="$fixture/mita-instances"
export MITA_INSTANCE_METRICS_DIR="$fixture/mita-metrics"
source_installer
nb_init_state_layout

harden_mita_permissions() { :; }
install_users_scheduler() { :; }
# Installer request globals below are consumed indirectly by initialization.
# shellcheck disable=SC2034
PROFILE=balanced PROTOCOL=TCP PORT=3611 PORT_RANGE=""
# shellcheck disable=SC2034
USERNAME=alice PASSWORD=alice-pass
ADVERTISE_HOST=old.example.com ADVERTISE_PORT=443
# shellcheck disable=SC2034
MTU=1400 MTU_POLICY=safe TRAFFIC_PATTERN=conservative TRAFFIC_SEED=42
# shellcheck disable=SC2034
LOW_ENTROPY_MODE=LOW_ENTROPY_MODE_OFF
# shellcheck disable=SC2034
MULTIPLEXING=MULTIPLEXING_OFF HANDSHAKE_MODE=HANDSHAKE_NO_WAIT
# shellcheck disable=SC2034
MIERU_CHANNEL=stable MIERU_VERSION=3.35.0
users_initialize_primary
save_install_state

instance_id="$(users_get_field alice instance_id)"
mkdir -p "$(dirname "$(instance_config_path "$instance_id")")" "$(dirname "$MITA_BIN")"
printf '{"server":"immutable"}\n' >"$(instance_config_path "$instance_id")"
printf '#!/bin/sh\nexit 0\n' >"$MITA_BIN"
chmod 0755 "$MITA_BIN"
printf 'iptables|tcp|3611\n' >"$MITA_FIREWALL_OWNED_STATE"
printf 'eth0|42001|tcp|3611\n' >"$TC_OWNED_STATE"
mkdir -p "$(instance_metrics_dir "$instance_id")"
printf 'quota-metrics-immutable\n' >"$(instance_metrics_file "$instance_id")"

config_hash="$(sha256sum "$(instance_config_path "$instance_id")")"
runtime_hash="$(sha256sum "$MITA_BIN")"
firewall_hash="$(sha256sum "$MITA_FIREWALL_OWNED_STATE")"
tc_hash="$(sha256sum "$TC_OWNED_STATE")"
quota_hash="$(sha256sum "$(instance_metrics_file "$instance_id")")"

require_root() { :; }
require_linux() { :; }
admin_lock_acquire() { :; }
admin_lock_release() { :; }
public_ip() { printf '198.51.100.50'; }
print_user_outputs() { :; }
nb_port_listener_pids() { printf '12345\n'; }
service_calls="$fixture/service-calls"
apply_users_config() { printf 'apply\n' >>"$service_calls"; return 1; }
instance_start_proxy() { printf 'start\n' >>"$service_calls"; return 1; }
instance_daemon_stop() { printf 'stop\n' >>"$service_calls"; return 1; }

# Endpoint request globals are consumed indirectly by do_user_set_endpoint.
# shellcheck disable=SC2034
USERNAME=alice YES=1 ADVERTISE_CLI=1 ADVERTISE_AUTO_REQUESTED=0
ADVERTISE_HOST=new.example.com ADVERTISE_PORT=""
do_user_set_endpoint >/dev/null
assert_eq new.example.com "$(users_get_field alice advertise_host)" 'host-only endpoint merges host'
assert_eq 443 "$(users_get_field alice advertise_port)" 'host-only endpoint keeps effective port'

# shellcheck disable=SC2034
USERNAME=alice YES=1 ADVERTISE_CLI=1 ADVERTISE_AUTO_REQUESTED=0
ADVERTISE_HOST="" ADVERTISE_PORT=8443
do_user_set_endpoint >/dev/null
assert_eq new.example.com "$(users_get_field alice advertise_host)" 'port-only endpoint keeps effective host'
assert_eq 8443 "$(users_get_field alice advertise_port)" 'port-only endpoint merges port'

# shellcheck disable=SC2034
USERNAME=alice YES=1 ADVERTISE_CLI=1 ADVERTISE_AUTO_REQUESTED=1
# shellcheck disable=SC2034
ADVERTISE_HOST="" ADVERTISE_PORT=""
do_user_set_endpoint >/dev/null
assert_eq "" "$(users_get_field alice advertise_host)" 'endpoint auto clears host'
assert_eq "" "$(users_get_field alice advertise_port)" 'endpoint auto clears port'

assert_eq "$config_hash" "$(sha256sum "$(instance_config_path "$instance_id")")" 'real config isolation'
assert_eq "$runtime_hash" "$(sha256sum "$MITA_BIN")" 'runtime isolation'
assert_eq "$firewall_hash" "$(sha256sum "$MITA_FIREWALL_OWNED_STATE")" 'firewall isolation'
assert_eq "$tc_hash" "$(sha256sum "$TC_OWNED_STATE")" 'tc isolation'
assert_eq "$quota_hash" "$(sha256sum "$(instance_metrics_file "$instance_id")")" 'quota metrics isolation'
assert_eq 12345 "$(nb_port_listener_pids TCP 3611)" 'listener PID isolation'
[ ! -s "$service_calls" ] || fail 'Display Endpoint updates must not apply, stop, start, or restart Mieru'

pass 'Mieru host-only/port-only/auto Display Endpoint updates preserve runtime resources'
