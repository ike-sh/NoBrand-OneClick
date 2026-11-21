#!/usr/bin/env bash
# shellcheck disable=SC2034
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/testlib.sh"
source_installer

LANG_ZH=0
NOBRAND_TEST_LOCAL_IPV4=192.0.2.241
NOBRAND_TEST_RANDOM_START=0
PROTOCOL=BOTH
PROTOCOL_CLI=1
ADVERTISE_CLI=1
ADVERTISE_HOST=edge.example
ADVERTISE_PORT=443
nb_splicore_legacy_preflight() { :; }
nobrand_ssh_confirmation_pending() { return 1; }
require_root() { :; }
nobrand_install_manager_script() { :; }
nb_prepare_ingress_request() { INGRESS_PROFILE_ID="$NOBRAND_LEGACY_INGRESS_PROFILE_ID"; }
nb_prepare_ingress_deployment() { INGRESS_LISTEN_HOST=127.0.0.1; }
nb_registry_rows() { :; }
nb_port_is_listening() { [ "$1:$2" = UDP:24102 ]; }
nb_render_client_profiles() { cat; }

read_tty() {
  [ "$1" = PORT ] || fail "Unexpected prompt: $1"
  assert_contains "$2" 'listen port' 'prompt describes the actual port'
  printf -v "$1" '%s' "$requested_port"
}
nb_splicore_call() {
  if [ "$5" = status ]; then
    printf '%s\n' '{"nodes":[
      {"id":"primary","pair":"primary","transport":"tcp","listener":{"host":"::1","port":24110},
       "display_endpoint":{"host":"edge.example","port":443}},
      {"id":"primary-udp","pair":"primary","transport":"udp","listener":{"host":"::1","port":24111},
       "display_endpoint":{"host":"edge.example","port":444}}]}'
    return
  fi
  printf 'listener=%s transport=%s display=%s:%s\n' "$PORT" "$PROTOCOL" "$ADVERTISE_HOST" "$ADVERTISE_PORT"
}

PORT=""
requested_port=24110
out="$(nb_splicore_protocol mieru install fixture)"
assert_contains "$out" 'listener=24110 transport=BOTH display=edge.example:443' 'manual listener'

requested_port=""
out="$(nb_splicore_protocol mieru install fixture)"
assert_contains "$out" 'listener=24102 transport=BOTH display=edge.example:443' 'allocator skips unavailable pair'

requested_port=24100
if (nb_splicore_protocol mieru install fixture) >/dev/null 2>&1; then
  fail "reserved real listen port accepted"
fi

requested_port=24120
out="$(nb_splicore_prompt_port mieru primary-udp)"
assert_contains "$out" '[::1]:24110 /TCP' 'current TCP listener'
assert_contains "$out" '[::1]:24111 /UDP' 'current UDP listener'
assert_contains "$out" 'edge.example:443' 'independent display endpoint'
pass 'Mieru interactive manual and automatic listener ports and BOTH endpoint display'

PROTOCOL_CLI=0
read_tty() {
  case "$1" in
    selector) printf -v "$1" xiaoe ;;
    mode) printf -v "$1" '%s' "$requested_mode" ;;
    PORT) printf -v "$1" '' ;;
    *) fail "Unexpected prompt: $1" ;;
  esac
}
for mode_case in ':TCP:24101' '2:UDP:24101' '3:BOTH:24102'; do
  IFS=: read -r requested_mode expected_mode expected_port <<<"$mode_case"
  out="$(nb_splicore_protocol mieru install)"
  assert_contains "$out" "listener=$expected_port transport=$expected_mode" "interactive $expected_mode allocation"
done
pass 'Mieru defaults to TCP and allocates each selected transport'

ADVERTISE_CLI=0
PORT=7020
public_ip() { printf '%s' 192.0.2.241; }
requested_mode=3
host_inputs=(7010 'edge.example:7099' '999.0.0.1' $'edge.example\t' $'edge\x1f.example' 'relay.invalid')
port_inputs=(0 65535 7099)
host_index=0
port_index=0
read_tty() {
  case "$1" in
    mode) printf -v "$1" '%s' "$requested_mode" ;;
    choice) printf -v "$1" 2 ;;
    host)
      [ "$3" = literal ] || fail 'Host input must preserve whitespace'
      [ "$host_index" -lt "${#host_inputs[@]}" ] || return 1
      printf -v "$1" '%s' "${host_inputs[host_index]}"
      host_index=$((host_index + 1))
      ;;
    port)
      [ "$host_index" -eq "${#host_inputs[@]}" ] || fail 'Port prompted before the Host was valid'
      [ "$port_index" -lt "${#port_inputs[@]}" ] || return 1
      printf -v "$1" '%s' "${port_inputs[port_index]}"
      port_index=$((port_index + 1))
      ;;
    *) fail "Unexpected prompt: $1" ;;
  esac
}
out="$(nb_splicore_protocol mieru install xiaoe 2>&1)"
assert_contains "$out" '7010 looks like a port' 'immediate numeric Host warning'
assert_contains "$out" 'Enter the port separately' 'malformed Host diagnostic'
assert_contains "$out" 'at most 65534 in BOTH mode' 'display Port retry'
assert_contains "$out" 'listener=7020 transport=BOTH display=relay.invalid:7099' 'unresolved DNS accepted'

host_inputs=(7010)
if out="$(nb_splicore_protocol mieru install xiaoe 2>&1)"; then
  fail 'Invalid Host reached the install transaction'
fi
[[ "$out" != *'listener='* ]] || fail 'Invalid Host reached the runtime'
pass 'Client Host retries before Port or the runtime install transaction'
