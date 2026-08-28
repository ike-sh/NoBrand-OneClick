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

# Request collection: interactive OFF/ON, noninteractive default OFF, and
# final endpoint collection after an auto-selected TCP/UDP port replacement.
snell_platform_supported() { return 0; }
nb_warn_if_outside_recommended_range() { :; }
nb_validate_advertise_endpoint() { return 0; }
nb_endpoint_conflict_owner() { return 1; }
nb_require_explicit_endpoint_noninteractive() { :; }
public_ip() { printf '198.51.100.10'; }
answer=""
read_tty() { printf -v "$1" '%s' "$answer"; }
nb_collect_advertise_endpoint_interactive() {
  printf '%s\n' "$2" >>"$fixture/endpoint-ports"
  ADVERTISE_HOST=entry.example.com
  ADVERTISE_PORT="$2"
}
nb_port_available_for_transport() { return 0; }

reset_request() {
  # Request globals are consumed indirectly by snell_collect_install_requests.
  # shellcheck disable=SC2034
  SNELL_VERSION=5
  SNELL_NAME="$1"
  # shellcheck disable=SC2034
  SNELL_PSK=0123456789abcdef
  SNELL_QUIC_PROXY=""
  SNELL_QUIC_CLI=0
  PORT="$2"
  # shellcheck disable=SC2034
  PORT_AUTO_SELECTED=0
  ADVERTISE_HOST=""
  ADVERTISE_PORT=""
  ADVERTISE_CLI=0
  ADVERTISE_AUTO_REQUESTED=0
}

reset_request interactive-off 3631
answer=""
snell_collect_install_requests 1
assert_eq off "$SNELL_QUIC_PROXY" 'interactive empty choice defaults OFF'

reset_request interactive-on 3632
answer=2
snell_collect_install_requests 1
assert_eq on "$SNELL_QUIC_PROXY" 'interactive choice 2 enables QUIC'

reset_request noninteractive-default 3633
ADVERTISE_HOST=entry.example.com ADVERTISE_PORT=3633 ADVERTISE_CLI=1
snell_collect_install_requests 0
assert_eq off "$SNELL_QUIC_PROXY" 'noninteractive omitted --quic defaults OFF'

reset_request auto-reselect 0
PORT=""
answer=2
nb_select_available_port() { printf 3611; }
nb_port_available_for_transport() {
  [ "$1:$2" != 3611:UDP ]
}
snell_select_available_install_port() { printf 3620; }
snell_collect_install_requests 1
assert_eq 3620 "$PORT" 'QUIC ON reselects a paired TCP/UDP port'
assert_eq 3620 "$(tail -n1 "$fixture/endpoint-ports")" \
  'Display Endpoint collection sees the final reselected port'

if (
  reset_request invalid-v4 3634
  # shellcheck disable=SC2034
  SNELL_VERSION=4 SNELL_QUIC_PROXY=on SNELL_QUIC_CLI=1
  ADVERTISE_HOST=entry.example.com ADVERTISE_PORT=3634 ADVERTISE_CLI=1
  snell_collect_install_requests 0
) >/dev/null 2>&1; then
  fail 'Snell v4 --quic on must be rejected'
fi

# Toggle semantics: only firewall ownership and state may change. The server
# config, service, runtime, listener, endpoint, and PSK stay untouched.
id=s1111111111111111
runtime="$NOBRAND_SNELL_RUNTIME_DIR/snell-v5"
printf '#!/bin/sh\necho snell-server v5.0.1\n' >"$runtime"
chmod +x "$runtime"
snell_generate_state "$(snell_state_path "$id")" "$id" toggle-v5 5 0123456789abcdef \
  0.0.0.0 3640 custom old.example.com 4640 '' false
snell_generate_server_config "$(snell_config_path "$id")" 5 0.0.0.0 3640 0123456789abcdef
config_hash="$(sha256sum "$(snell_config_path "$id")")"
runtime_hash="$(sha256sum "$runtime")"
created_at="$(snell_state_field "$id" created_at)"
psk="$(snell_state_field "$id" psk)"

require_root() { :; }
admin_lock_acquire() { :; }
admin_lock_release() { :; }
snell_service_active() { return 0; }
nb_port_listener_pids() {
  case "$1:$2" in TCP:3640|UDP:3640) printf '640\n' ;; esac
}
snell_print_result() { :; }
service_calls="$fixture/service-calls"
snell_service_action() { printf '%s:%s\n' "$1" "$2" >>"$service_calls"; }
udp_owned=0
firewall_log="$fixture/firewall-log"
nb_firewall_binding_owned() {
  case "$1:$2" in UDP:3640) [ "$udp_owned" -eq 1 ] ;; TCP:3640) return 0 ;; *) return 1 ;; esac
}
nb_firewall_open_pairs() {
  printf 'open:%s\n' "$1" >>"$firewall_log"
  case "$1" in *'UDP|3640'*) udp_owned=1 ;; esac
}
nb_firewall_close_pairs() {
  printf 'close:%s\n' "$1" >>"$firewall_log"
  case "$1" in *'UDP|3640'*) udp_owned=0 ;; esac
}

# Toggle request globals are consumed indirectly by snell_set_quic.
# shellcheck disable=SC2034
SNELL_NAME=toggle-v5 SNELL_QUIC_PROXY=on SNELL_QUIC_CLI=1 YES=1
snell_set_quic >/dev/null
assert_eq true "$(snell_state_field "$id" quic_proxy_enabled)" 'toggle ON state'
assert_eq true "$(snell_state_field "$id" managed_udp)" 'toggle ON managed UDP'
assert_eq 1 "$udp_owned" 'toggle ON firewall ownership'
assert_eq "$config_hash" "$(sha256sum "$(snell_config_path "$id")")" 'toggle ON config isolation'
assert_eq "$runtime_hash" "$(sha256sum "$runtime")" 'toggle ON runtime isolation'
assert_eq "$psk" "$(snell_state_field "$id" psk)" 'toggle ON PSK isolation'
assert_eq "$created_at" "$(snell_state_field "$id" created_at)" 'toggle ON created_at persistence'
[ ! -s "$service_calls" ] || fail 'toggle ON must not restart or rewrite the service'

# Endpoint-only update while QUIC is ON must not touch config/runtime/service/firewall.
firewall_hash="$(sha256sum "$firewall_log")"
# Endpoint request globals are consumed indirectly by snell_set_endpoint.
# shellcheck disable=SC2034
SNELL_NAME=toggle-v5 YES=1 ADVERTISE_CLI=1 ADVERTISE_AUTO_REQUESTED=0
# shellcheck disable=SC2034
ADVERTISE_HOST=new.example.com ADVERTISE_PORT=5640
snell_set_endpoint >/dev/null
assert_eq new.example.com "$(snell_state_field "$id" advertise_host)" 'QUIC ON endpoint host update'
assert_eq 5640 "$(snell_state_field "$id" advertise_port)" 'QUIC ON endpoint port update'
assert_eq "$config_hash" "$(sha256sum "$(snell_config_path "$id")")" 'endpoint config isolation'
assert_eq "$runtime_hash" "$(sha256sum "$runtime")" 'endpoint runtime isolation'
assert_eq "$firewall_hash" "$(sha256sum "$firewall_log")" 'endpoint firewall isolation'
[ ! -s "$service_calls" ] || fail 'endpoint update must not call service actions'

SNELL_QUIC_PROXY=off
snell_set_quic >/dev/null
assert_eq false "$(snell_state_field "$id" quic_proxy_enabled)" 'toggle OFF state'
assert_eq false "$(snell_state_field "$id" managed_udp)" 'toggle OFF managed UDP'
assert_eq 0 "$udp_owned" 'toggle OFF firewall ownership'

# Failed state writes roll firewall state back in both directions.
original_state_set_quic="$(declare -f snell_state_set_quic)"
snell_state_set_quic() { return 1; }
SNELL_QUIC_PROXY=on
if snell_set_quic >/dev/null 2>&1; then
  fail 'toggle enable must fail when state persistence fails'
fi
assert_eq 0 "$udp_owned" 'failed enable closes only the newly opened UDP rule'
assert_eq false "$(snell_state_field "$id" quic_proxy_enabled)" 'failed enable retains OFF state'
eval "$original_state_set_quic"

SNELL_QUIC_PROXY=on
snell_set_quic >/dev/null
assert_eq 1 "$udp_owned" 'precondition for failed disable'
snell_state_set_quic() { return 1; }
SNELL_QUIC_PROXY=off
if snell_set_quic >/dev/null 2>&1; then
  fail 'toggle disable must fail when state persistence fails'
fi
assert_eq 1 "$udp_owned" 'failed disable restores prior UDP ownership'
assert_eq true "$(snell_state_field "$id" quic_proxy_enabled)" 'failed disable retains ON state'
eval "$original_state_set_quic"

# Backups persist both QUIC booleans. Restore is exercised without running
# real services.
nobrand_stop_all_services() { :; }
nobrand_start_enabled_services() { :; }
archive="$fixture/quic-backup.tar.gz"
nobrand_backup_create "$archive" >/dev/null
snell_state_set_quic "$id" false
nobrand_backup_restore "$archive" >/dev/null
assert_eq true "$(snell_state_field "$id" quic_proxy_enabled)" 'backup restores QUIC state'
assert_eq true "$(snell_state_field "$id" managed_udp)" 'backup restores managed UDP state'

# Removal closes exactly the state-owned TCP+UDP pair and removes only this
# instance's state/config/service.
removed_pairs="$fixture/removed-pairs"
snell_remove_service() { printf '%s\n' "$1" >"$fixture/removed-service"; }
nb_firewall_close_pairs() { printf '%s\n' "$1" >"$removed_pairs"; }
# Read indirectly by remove_snell_instance.
# shellcheck disable=SC2034
SNELL_NAME=toggle-v5
remove_snell_instance >/dev/null
assert_eq "$id" "$(<"$fixture/removed-service")" 'remove exact service id'
assert_eq $'TCP|3640\nUDP|3640' "$(<"$removed_pairs")" 'remove exact QUIC firewall pairs'
[ ! -e "$(snell_state_path "$id")" ] || fail 'remove must delete state'
[ ! -e "$(snell_config_path "$id")" ] || fail 'remove must delete config'

# Install rollback also uses the new pair-list contract and never closes an
# unrelated binding.
rollback_id=s2222222222222222
printf '{}\n' >"$(snell_state_path "$rollback_id")"
printf 'temporary\n' >"$(snell_config_path "$rollback_id")"
snell_install_rollback "$rollback_id" $'TCP|3650\nUDP|3650'
assert_eq $'TCP|3650\nUDP|3650' "$(<"$removed_pairs")" 'install rollback pair-list contract'
[ ! -e "$(snell_state_path "$rollback_id")" ] || fail 'install rollback state cleanup'
[ ! -e "$(snell_config_path "$rollback_id")" ] || fail 'install rollback config cleanup'

pass 'Snell v5 QUIC requests, state, firewall, toggle rollback, endpoint, backup, and removal'
