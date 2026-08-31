#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd -P)/testlib.sh"

fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT

export NOBRAND_STATE_DIR="$fixture/state"
export NOBRAND_CONFIG_DIR="$fixture/config"
export NOBRAND_LIB_DIR="$fixture/lib"
export NOBRAND_BIN_DIR="$fixture/lib/bin"
export NOBRAND_FORWARD_STATE_DIR="$fixture/state/forward"
export NOBRAND_FORWARD_STATE_FILE="$fixture/state/forward/state.json"
export NOBRAND_FORWARD_REALM_CONFIG="$fixture/config/forward/realm.toml"
export NOBRAND_FORWARD_NFT_RULESET="$fixture/config/forward/nftables.nft"
export NOBRAND_FORWARD_SYSCTL_STATE="$fixture/state/forward/sysctl.json"
export NOBRAND_FORWARD_SYSCTL_FRAGMENT="$fixture/sysctl.d/90-nobrand-forward.conf"
export NOBRAND_REALM_BIN="$fixture/lib/bin/realm"
export NOBRAND_REALM_RUNTIME_META="$fixture/state/forward/realm-runtime.json"
export NOBRAND_TEST_LOCAL_IPV4=192.0.2.168

source_installer
nb_init_state_layout
forward_init_state

cat >"$NOBRAND_FORWARD_STATE_FILE" <<'JSON'
{"schema_version":3,"ownership":"nobrand-v3","feature":"port-forward","rules":[
 {"rule_id":"f1111111111111111","name":"old","note":"","backend":"nftables","enabled":true,
  "protocol":"tcp","listen_host":"0.0.0.0","listen_port":16850,
  "target_host":"203.0.113.10","target_port":443,"display_host":"","display_port":16850,
  "display_mode":"auto","created_at":"2026-08-30T00:00:00Z","updated_at":"2026-08-30T00:00:00Z",
  "ownership_metadata":{"managed_listener":true,"managed_firewall":true},
  "backend_options":{"source_mode":"masquerade"}}
]}
JSON
chmod 0600 "$NOBRAND_FORWARD_STATE_FILE"
old_hash="$(sha256sum "$NOBRAND_FORWARD_STATE_FILE")"

candidate="$fixture/candidate.json"
jq '(.rules[0].target_host)="203.0.113.20" | (.rules[0].updated_at)="2026-08-30T01:00:00Z"' \
  "$NOBRAND_FORWARD_STATE_FILE" >"$candidate"

forward_apply_nft_state() { return 1; }
forward_realm_apply_state() { :; }
forward_sysctl_snapshot() { mkdir -p "$1"; }
forward_sysctl_restore_snapshot() { :; }
if forward_transaction_commit "$candidate" modify nftables nftables >/dev/null 2>&1; then
  fail 'Forward transaction succeeded after nftables apply failure'
fi
assert_eq "$old_hash" "$(sha256sum "$NOBRAND_FORWARD_STATE_FILE")" \
  'nftables failure preserves authoritative state'

call_log="$fixture/calls.log"
forward_apply_nft_state() { printf 'nft:%s\n' "$(jq -r '.rules[0].backend' "$1")" >>"$call_log"; }
forward_realm_apply_state() {
  printf 'realm:%s\n' "$(jq -r '.rules[0].backend' "$1")" >>"$call_log"
  [ "$(jq -r '.rules[0].backend' "$1")" != realm ]
}

switch_candidate="$fixture/switch.json"
jq '(.rules[0].backend)="realm" | (.rules[0].backend_options)={
      through:"",interface:"",listen_interface:"",tcp_timeout:5,udp_timeout:30,
      proxy_send:false,proxy_accept:false,proxy_version:2,proxy_accept_timeout:5,
      dns_mode:"system",dns_protocol:"tcp_and_udp",dns_nameservers:[],
      listen_transport:"",remote_transport:"",extra_targets:[],balance:"off",weights:[]
    }' "$NOBRAND_FORWARD_STATE_FILE" >"$switch_candidate"

if forward_transaction_commit "$switch_candidate" switch-backend nftables realm >/dev/null 2>&1; then
  fail 'Forward switch succeeded after Realm candidate failure'
fi
assert_eq "$old_hash" "$(sha256sum "$NOBRAND_FORWARD_STATE_FILE")" \
  'failed backend switch preserves authoritative state'
assert_contains "$(cat "$call_log")" 'realm:realm' 'nftables-to-Realm validates/applies Realm first'

# An IPv6 Realm listener cannot be carried into the IPv4-only nftables
# backend. The switch must explicitly normalize the local listener without
# changing an already valid IPv4 target or resolving a domain.
cat >"$NOBRAND_FORWARD_STATE_FILE" <<'JSON'
{"schema_version":3,"ownership":"nobrand-v3","feature":"port-forward","rules":[
 {"rule_id":"f2222222222222222","name":"realm-ipv6-listen","note":"","backend":"realm","enabled":true,
  "protocol":"tcp","listen_host":"::","listen_port":16851,
  "target_host":"203.0.113.30","target_port":443,"display_host":"","display_port":16851,
  "display_mode":"auto","created_at":"2026-08-30T00:00:00Z","updated_at":"2026-08-30T00:00:00Z",
  "ownership_metadata":{"managed_listener":true,"managed_firewall":true},
  "backend_options":{"through":"","interface":"","listen_interface":"","tcp_timeout":5,"udp_timeout":30,
   "proxy_send":false,"proxy_accept":false,"proxy_version":2,"proxy_accept_timeout":5,
   "dns_mode":"system","dns_protocol":"tcp_and_udp","dns_nameservers":[],
   "listen_transport":"","remote_transport":"","extra_targets":[],"balance":"off","weights":[]}}
]}
JSON
captured_switch="$fixture/captured-switch.json"
forward_transaction_commit() { cp -a "$1" "$captured_switch"; }
export FORWARD_RULE_ID=f2222222222222222 FORWARD_BACKEND=nftables FORWARD_TARGET_HOST=""
export FORWARD_TARGET_PORT="" FORWARD_LISTEN_HOST="" FORWARD_SOURCE_MODE=masquerade
export FORWARD_THROUGH="" FORWARD_INTERFACE="" FORWARD_LISTEN_INTERFACE=""
export FORWARD_TCP_TIMEOUT=5 FORWARD_UDP_TIMEOUT=30 FORWARD_PROXY_SEND=false FORWARD_PROXY_ACCEPT=false
export FORWARD_PROXY_VERSION=2 FORWARD_PROXY_ACCEPT_TIMEOUT=5 FORWARD_DNS_MODE=system
export FORWARD_DNS_PROTOCOL=tcp_and_udp FORWARD_DNS_NAMESERVERS="" FORWARD_LISTEN_TRANSPORT=""
export FORWARD_REMOTE_TRANSPORT="" FORWARD_EXTRA_TARGETS="" FORWARD_BALANCE=off FORWARD_WEIGHTS=""
forward_switch_backend || fail 'Realm IPv6-listener to nftables switch normalization'
assert_eq 0.0.0.0 "$(jq -r '.rules[0].listen_host' "$captured_switch")" \
  'Realm IPv6 listener becomes nftables IPv4 wildcard'
assert_eq 203.0.113.30 "$(jq -r '.rules[0].target_host' "$captured_switch")" \
  'valid IPv4 target is preserved during backend switch'

pass 'Port Forward transaction and backend-switch rollback'
