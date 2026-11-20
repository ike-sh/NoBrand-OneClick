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
