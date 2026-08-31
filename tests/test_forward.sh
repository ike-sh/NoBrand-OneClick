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
export NOBRAND_REALM_BIN="$fixture/lib/bin/realm"
export NOBRAND_REALM_RUNTIME_META="$fixture/state/forward/realm-runtime.json"
export NOBRAND_FORWARD_SYSCTL_STATE="$fixture/state/forward/sysctl.json"
export NOBRAND_FORWARD_SYSCTL_FRAGMENT="$fixture/sysctl.d/90-nobrand-forward.conf"
export NOBRAND_TEST_LOCAL_IPV4=192.0.2.168

source_installer
nb_init_state_layout
forward_init_state

forward_state_valid "$NOBRAND_FORWARD_STATE_FILE" || fail 'fresh Forward state is invalid'
assert_eq 0 "$(jq '.rules|length' "$NOBRAND_FORWARD_STATE_FILE")" 'fresh Forward rule count'

assert_eq tcp "$(forward_normalize_protocol TCP)" 'Forward TCP normalization'
assert_eq udp "$(forward_normalize_protocol udp)" 'Forward UDP normalization'
assert_eq both "$(forward_normalize_protocol TCP+UDP)" 'Forward BOTH normalization'
if forward_normalize_protocol icmp >/dev/null 2>&1; then
  fail 'Forward accepted unsupported ICMP protocol'
fi

forward_target_valid nftables 203.0.113.10 || fail 'nftables rejected IPv4 literal'
if forward_target_valid nftables relay.example.test; then
  fail 'nftables accepted a domain target'
fi
forward_target_valid realm relay.example.test || fail 'Realm rejected domain target'
forward_target_valid realm 2001:db8::10 || fail 'Realm rejected IPv6 target syntax'
for invalid in '' bad_domain 999.2.3.4 'https://example.test' 'host:443' '-bad.example'; do
  if forward_target_valid realm "$invalid"; then
    fail "Realm accepted invalid target: $invalid"
  fi
done
assert_eq '1.1.1.1:53' "$(forward_socket_address_normalize '1.1.1.1:53')" \
  'Realm IPv4 socket address normalization'
assert_eq '[2001:db8::1]:53' "$(forward_socket_address_normalize '2001:db8::1:53')" \
  'Realm unbracketed IPv6 socket address normalization'
assert_eq 'resolver.example.test:53' "$(forward_socket_address_normalize 'resolver.example.test:53')" \
  'Realm domain socket address normalization'
for invalid in '1.1.1.1' '1.1.1.1:0' '1.1.1.1:65536' '[2001:db8::1]' \
  '[2001:db8::1]:bad' 'bad_domain:53' 'https://example.test:53'; do
  if forward_socket_address_valid "$invalid"; then
    fail "Realm accepted invalid socket address: $invalid"
  fi
done

reserved_tail_port="$(nb_port_base_for_ip "$NOBRAND_TEST_LOCAL_IPV4")"
if forward_port_allowed "$reserved_tail_port" tcp; then
  fail 'Forward accepted the reserved xx00 port'
fi
forward_port_allowed 16850 tcp || fail 'Forward rejected an ordinary TCP port'

# A new rule has no previous port/protocol. Keep those comparison operands
# initialized so the normal CLI add path remains valid under set -u.
(
  FORWARD_NAME=add-under-nounset
  FORWARD_NOTE='new rule validation'
  FORWARD_BACKEND=nftables
  FORWARD_PROTOCOL=TCP
  FORWARD_LISTEN_HOST=0.0.0.0
  FORWARD_LISTEN_PORT=16851
  FORWARD_TARGET_HOST=203.0.113.20
  FORWARD_TARGET_PORT=443
  forward_validate_requested_rule
) || fail 'Forward new-rule validation failed under nounset'

# The CLI must explain the supported alternative before rejecting a domain
# target for nftables. Keep this assertion on the requested-rule path so the
# guidance cannot become unreachable behind generic target validation.
domain_guidance="$fixture/nft-domain-guidance.log"
export FORWARD_NAME=nft-domain-guidance
export FORWARD_NOTE='domain guidance regression'
export FORWARD_BACKEND=nftables
export FORWARD_PROTOCOL=TCP
export FORWARD_LISTEN_HOST=0.0.0.0
export FORWARD_LISTEN_PORT=16852
export FORWARD_TARGET_HOST=relay.example.test
export FORWARD_TARGET_PORT=443
if forward_validate_requested_rule >"$domain_guidance" 2>&1; then
  fail 'nftables accepted a domain target on requested-rule validation'
fi
assert_contains "$(cat "$domain_guidance")" \
  'nftables backend currently requires IP target; use Realm backend for domain targets.' \
  'nftables domain rejection includes Realm guidance'

cat >"$NOBRAND_FORWARD_STATE_FILE" <<'JSON'
{
  "schema_version": 3,
  "ownership": "nobrand-v3",
  "feature": "port-forward",
  "rules": [
    {
      "rule_id": "f1111111111111111",
      "name": "kernel-tcp",
      "note": "RFC documentation target",
      "backend": "nftables",
      "enabled": true,
      "protocol": "tcp",
      "listen_host": "0.0.0.0",
      "listen_port": 16850,
      "target_host": "203.0.113.10",
      "target_port": 443,
      "display_host": "edge.example.test",
      "display_port": 443,
      "display_mode": "custom",
      "created_at": "2026-08-30T00:00:00Z",
      "updated_at": "2026-08-30T00:00:00Z",
      "ownership_metadata": {"managed_listener": true, "managed_firewall": true},
      "backend_options": {"source_mode": "masquerade"}
    },
    {
      "rule_id": "f2222222222222222",
      "name": "realm-udp-domain",
      "note": "same numeric port, different transport",
      "backend": "realm",
      "enabled": true,
      "protocol": "udp",
      "listen_host": "0.0.0.0",
      "listen_port": 16850,
      "target_host": "relay.example.test",
      "target_port": 8443,
      "display_host": "",
      "display_port": 16850,
      "display_mode": "auto",
      "created_at": "2026-08-30T00:00:00Z",
      "updated_at": "2026-08-30T00:00:00Z",
      "ownership_metadata": {"managed_listener": true, "managed_firewall": true},
      "backend_options": {
        "through": "",
        "interface": "",
        "listen_interface": "",
        "tcp_timeout": 5,
        "udp_timeout": 30,
        "proxy_send": false,
        "proxy_accept": false,
        "proxy_version": 2,
        "proxy_accept_timeout": 5,
        "dns_mode": "system",
        "dns_protocol": "tcp_and_udp",
        "dns_nameservers": [],
        "listen_transport": "",
        "remote_transport": "",
        "extra_targets": [],
        "balance": "off",
        "weights": []
      }
    }
  ]
}
JSON
chmod 0600 "$NOBRAND_FORWARD_STATE_FILE"

forward_state_valid "$NOBRAND_FORWARD_STATE_FILE" \
  || fail 'valid mixed-backend Forward state was rejected'

for mutation in \
  '(.rules[1].backend_options.dns_nameservers)=["bad"]' \
  '(.rules[1].backend_options.extra_targets)=["bad"]' \
  '(.rules[1].backend_options.balance)="roundrobin"' \
  '(.rules[1].backend_options.udp_timeout)=1.5' \
  '(.rules[1].backend_options.dns_mode)="invented"'; do
  invalid_advanced="$fixture/invalid-advanced-$(printf '%s' "$mutation" | sha256sum | cut -c1-12).json"
  jq "$mutation" "$NOBRAND_FORWARD_STATE_FILE" >"$invalid_advanced"
  if forward_state_valid "$invalid_advanced"; then
    fail "Forward state accepted invalid Realm advanced options: $mutation"
  fi
done

export FORWARD_THROUGH="" FORWARD_INTERFACE="" FORWARD_LISTEN_INTERFACE=""
export FORWARD_TCP_TIMEOUT=5 FORWARD_UDP_TIMEOUT=30 FORWARD_PROXY_SEND=false FORWARD_PROXY_ACCEPT=false
export FORWARD_PROXY_VERSION=2 FORWARD_PROXY_ACCEPT_TIMEOUT=5 FORWARD_DNS_MODE=ipv4_only
export FORWARD_DNS_PROTOCOL=tcp_and_udp FORWARD_DNS_NAMESERVERS='2001:db8::1:53'
export FORWARD_LISTEN_TRANSPORT="" FORWARD_REMOTE_TRANSPORT=""
export FORWARD_EXTRA_TARGETS='target.example.test:443' FORWARD_BALANCE=roundrobin FORWARD_WEIGHTS='2,1'
advanced_options="$(forward_realm_options_json)" || fail 'valid Realm advanced CLI options rejected'
assert_eq '[2001:db8::1]:53' "$(jq -r '.dns_nameservers[0]' <<<"$advanced_options")" \
  'Realm DNS address canonicalization'
assert_eq 'target.example.test:443' "$(jq -r '.extra_targets[0]' <<<"$advanced_options")" \
  'Realm extra target validation'

rows="$(nb_registry_rows)"
assert_contains "$rows" 'forward:f1111111111111111|TCP|16850|edge.example.test|443' \
  'nftables Forward registry row'
assert_contains "$rows" 'forward:f2222222222222222|UDP|16850||16850' \
  'Realm Forward registry row'

realm_candidate="$fixture/realm.toml"
forward_generate_realm_config "$NOBRAND_FORWARD_STATE_FILE" "$realm_candidate"
realm_config="$(cat "$realm_candidate")"
assert_contains "$realm_config" '[[endpoints]]' 'Realm multi-endpoint syntax'
assert_contains "$realm_config" 'listen = "0.0.0.0:16850"' 'Realm listener generation'
assert_contains "$realm_config" 'remote = "relay.example.test:8443"' 'Realm domain remains a domain'
assert_contains "$realm_config" 'no_tcp = true' 'Realm UDP disables TCP'
assert_contains "$realm_config" 'use_udp = true' 'Realm UDP enabled'
assert_not_contains "$realm_config" '203.0.113.10:443' 'nftables rule excluded from Realm config'

nft_candidate="$fixture/nftables.nft"
forward_generate_nft_ruleset "$NOBRAND_FORWARD_STATE_FILE" "$nft_candidate"
nft_config="$(cat "$nft_candidate")"
assert_contains "$nft_config" 'table ip nobrand_forward_v4' 'NoBrand-owned nft table'
assert_contains "$nft_config" 'tcp dport 16850' 'nftables TCP match'
assert_contains "$nft_config" 'dnat to 203.0.113.10:443' 'nftables DNAT target'
assert_contains "$nft_config" 'masquerade' 'nftables default source NAT'
assert_contains "$nft_config" 'nobrand:f1111111111111111:dnat:tcp' 'nftables ownership comment'
assert_not_contains "$nft_config" 'relay.example.test' 'Realm rule excluded from nftables ruleset'

realm_hash_before="$(sha256sum "$realm_candidate" | awk '{print $1}')"
nft_hash_before="$(sha256sum "$nft_candidate" | awk '{print $1}')"
forward_set_endpoint_state f2222222222222222 custom public.example.test 24443
forward_generate_realm_config "$NOBRAND_FORWARD_STATE_FILE" "$fixture/realm-after.toml"
forward_generate_nft_ruleset "$NOBRAND_FORWARD_STATE_FILE" "$fixture/nft-after.nft"
assert_eq "$realm_hash_before" "$(sha256sum "$fixture/realm-after.toml" | awk '{print $1}')" \
  'Realm Display Endpoint does not alter runtime config'
assert_eq "$nft_hash_before" "$(sha256sum "$fixture/nft-after.nft" | awk '{print $1}')" \
  'nftables Display Endpoint does not alter kernel rules'

duplicate="$fixture/duplicate.json"
jq '.rules += [(.rules[0] | .rule_id="f3333333333333333" | .name="duplicate-tcp")]' \
  "$NOBRAND_FORWARD_STATE_FILE" >"$duplicate"
if forward_state_valid "$duplicate"; then
  fail 'Forward state accepted duplicate transport/port ownership'
fi

domain_nft="$fixture/domain-nft.json"
jq '(.rules[0].target_host)="relay.example.test"' "$NOBRAND_FORWARD_STATE_FILE" >"$domain_nft"
if forward_state_valid "$domain_nft"; then
  fail 'Forward state accepted a domain target for nftables'
fi

reserved="$fixture/reserved.json"
jq --argjson port "$reserved_tail_port" '(.rules[0].listen_port)=$port' \
  "$NOBRAND_FORWARD_STATE_FILE" >"$reserved"
if forward_state_valid "$reserved"; then
  fail 'Forward state accepted reserved xx00 ownership'
fi

exported="$fixture/forward-export.json"
forward_export_json "$exported"
forward_import_validate "$exported" || fail 'Forward rejected its own JSON export'
assert_eq nobrand-forward-export "$(jq -r .format "$exported")" 'Forward export format'
assert_eq 2 "$(jq '.rules|length' "$exported")" 'Forward export rule count'

unknown="$fixture/unknown-export.json"
jq '.unexpected=true' "$exported" >"$unknown"
if forward_import_validate "$unknown"; then
  fail 'Forward import silently accepted an unknown top-level field'
fi

# Modify commits are exercised here with a state-only transaction stub.  The
# transaction/runtime behavior has dedicated tests; this regression protects
# the candidate contract that failed on a real machine when an auto-display
# Realm rule changed its listener port.
forward_transaction_commit() {
  local candidate="$1"
  forward_state_valid "$candidate" || return 1
  cp -f "$candidate" "$NOBRAND_FORWARD_STATE_FILE"
}

jq '(.rules[]|select(.rule_id=="f2222222222222222")) |=
  (.display_mode="auto"|.display_host=""|.display_port=.listen_port)' \
  "$NOBRAND_FORWARD_STATE_FILE" >"$fixture/modify-auto.json"
mv -f "$fixture/modify-auto.json" "$NOBRAND_FORWARD_STATE_FILE"

export FORWARD_RULE_ID=f2222222222222222 FORWARD_NAME="" FORWARD_NOTE="" FORWARD_BACKEND=""
export FORWARD_PROTOCOL="" FORWARD_LISTEN_HOST="" FORWARD_LISTEN_PORT=16853
export FORWARD_TARGET_HOST="" FORWARD_TARGET_PORT="" FORWARD_ADVANCED_CLI=0 FORWARD_SOURCE_MODE_CLI=0
export ADVERTISE_CLI=0 ADVERTISE_AUTO_REQUESTED=0 ADVERTISE_HOST="" ADVERTISE_PORT=""
forward_modify_rule || fail 'Forward auto-display listener-port modify failed'
assert_eq 16853 "$(jq -r '.rules[]|select(.rule_id=="f2222222222222222")|.listen_port' \
  "$NOBRAND_FORWARD_STATE_FILE")" 'Forward modified listener port'
assert_eq auto "$(jq -r '.rules[]|select(.rule_id=="f2222222222222222")|.display_mode' \
  "$NOBRAND_FORWARD_STATE_FILE")" 'Forward auto display mode preserved'
assert_eq 16853 "$(jq -r '.rules[]|select(.rule_id=="f2222222222222222")|.display_port' \
  "$NOBRAND_FORWARD_STATE_FILE")" 'Forward auto Display Port follows modified listener'
forward_state_valid "$NOBRAND_FORWARD_STATE_FILE" \
  || fail 'Forward auto-display modify produced invalid state'

export FORWARD_LISTEN_PORT=16854 ADVERTISE_CLI=1 ADVERTISE_AUTO_REQUESTED=0
export ADVERTISE_HOST=public.example.test ADVERTISE_PORT=24454
forward_modify_rule || fail 'Forward modify with an explicit custom Display Endpoint failed'
assert_eq custom "$(jq -r '.rules[]|select(.rule_id=="f2222222222222222")|.display_mode' \
  "$NOBRAND_FORWARD_STATE_FILE")" 'Forward modify switched Display Endpoint to custom'
assert_eq public.example.test "$(jq -r '.rules[]|select(.rule_id=="f2222222222222222")|.display_host' \
  "$NOBRAND_FORWARD_STATE_FILE")" 'Forward modify custom Display Host'
assert_eq 24454 "$(jq -r '.rules[]|select(.rule_id=="f2222222222222222")|.display_port' \
  "$NOBRAND_FORWARD_STATE_FILE")" 'Forward modify custom Display Port'

export FORWARD_LISTEN_PORT=16855 ADVERTISE_CLI=0 ADVERTISE_AUTO_REQUESTED=0
export ADVERTISE_HOST="" ADVERTISE_PORT=""
forward_modify_rule || fail 'Forward custom-display listener-port modify failed'
assert_eq custom "$(jq -r '.rules[]|select(.rule_id=="f2222222222222222")|.display_mode' \
  "$NOBRAND_FORWARD_STATE_FILE")" 'Forward custom display mode preserved without CLI override'
assert_eq 24454 "$(jq -r '.rules[]|select(.rule_id=="f2222222222222222")|.display_port' \
  "$NOBRAND_FORWARD_STATE_FILE")" 'Forward custom Display Port preserved without CLI override'

export FORWARD_LISTEN_PORT=16856 ADVERTISE_CLI=1 ADVERTISE_AUTO_REQUESTED=1
forward_modify_rule || fail 'Forward modify with --advertise-auto semantics failed'
assert_eq auto "$(jq -r '.rules[]|select(.rule_id=="f2222222222222222")|.display_mode' \
  "$NOBRAND_FORWARD_STATE_FILE")" 'Forward modify switched Display Endpoint back to auto'
assert_eq 16856 "$(jq -r '.rules[]|select(.rule_id=="f2222222222222222")|.display_port' \
  "$NOBRAND_FORWARD_STATE_FILE")" 'Forward auto Display Port uses the new listener'
forward_state_valid "$NOBRAND_FORWARD_STATE_FILE" \
  || fail 'Forward explicit auto-display modify produced invalid state'

pass 'Port Forward state, target, port, config, endpoint, and import/export contract'
