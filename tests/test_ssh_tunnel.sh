#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/testlib.sh"

fixture="$(mktemp -d)"
trap 'rm -rf -- "$fixture"' EXIT
export NOBRAND_STATE_DIR="$fixture/nobrand-oneclick/state"
export NOBRAND_CONFIG_DIR="$fixture/nobrand-oneclick/config"
export NOBRAND_LIB_DIR="$fixture/nobrand-oneclick/lib"
export NOBRAND_SSH_CONFIG_MAIN="$fixture/sshd_config"
export NOBRAND_SSH_CONFIG_DROPIN="$fixture/sshd_config.d/90-nobrand-ssh-tunnel.conf"
export NOBRAND_TEST_LOCAL_IPV4=172.16.1.36
source_installer
nb_init_state_layout
assert_eq 711 "$(stat -c %a "$NOBRAND_CONFIG_DIR")" 'SSH AuthorizedKeysFile config root traversal'
assert_eq 711 "$(stat -c %a "$NOBRAND_SSH_CONFIG_DIR")" 'SSH module config traversal without listing'
assert_eq 755 "$(stat -c %a "$NOBRAND_SSH_AUTHORIZED_KEYS_DIR")" 'SSH authorized-keys directory traversal'

policy="$fixture/policy.conf"
ssh_tunnel_generate_policy "$policy" /usr/sbin/nologin
for expected in \
  'Match Group nobrand-ssh-tunnel' \
  'AuthenticationMethods publickey' \
  'PubkeyAuthentication yes' \
  'PasswordAuthentication no' \
  'KbdInteractiveAuthentication no' \
  "AuthorizedKeysFile ${NOBRAND_SSH_AUTHORIZED_KEYS_DIR}/%u" \
  'AllowTcpForwarding yes' \
  'AllowStreamLocalForwarding no' \
  'GatewayPorts no' \
  'PermitTTY no' \
  'X11Forwarding no' \
  'AllowAgentForwarding no' \
  'PermitTunnel no' \
  'PermitUserRC no' \
  'MaxSessions 0' \
  'ForceCommand /usr/sbin/nologin' \
  'Match all'; do
  sed 's/^[[:space:]]*//' "$policy" | grep -qxF "$expected" \
    || fail "SSH policy missing: $expected"
done
for forbidden in 'Port ' 'ListenAddress ' 'PermitRootLogin ' 'GatewayPorts yes' \
  'AllowTcpForwarding local' 'PermitTTY yes' 'PermitTunnel yes'; do
  grep -qF "$forbidden" "$policy" && fail "SSH policy contains forbidden directive: $forbidden"
done

assert_eq 3600 "$(ssh_tunnel_default_display_port)" 'SSH Display Endpoint tail-base default'

state="$fixture/ssh-state.json"
users='[{"account_id":"a1111111111111111","display_name":"alice","linux_user":"nbt-alice-11111111","uid":61001,"group":"nobrand-ssh-tunnel","key_fingerprint":"SHA256:alice","created_at":"2026-08-30T00:00:00Z"}]'
ssh_tunnel_generate_state "$state" custom entry.example.com 443 22 dropin \
  "$NOBRAND_SSH_CONFIG_DROPIN" "$users" 2026-08-30T00:00:00Z
jq -e '
  .schema_version == 3
  and .ownership == "nobrand-v3"
  and .protocol == "ssh-tunnel"
  and .group == "nobrand-ssh-tunnel"
  and .external_listener == true
  and .managed_listener == false
  and .managed_firewall == false
  and .real_port == 22
  and .advertise_host == "entry.example.com"
  and .advertise_port == 443
  and (.users | length == 1)
' "$state" >/dev/null || fail 'SSH Tunnel schema-v3 optional-module state'

mkdir -p "$NOBRAND_SSH_STATE_DIR" "$NOBRAND_SSH_KEYS_DIR/a1111111111111111" \
  "$NOBRAND_SSH_AUTHORIZED_KEYS_DIR" "$NOBRAND_SSH_ACCOUNT_MARKER_DIR"
cp "$state" "$NOBRAND_SSH_STATE_FILE"
printf '%s\n' 'PRIVATE-KEY-MATERIAL' >"$NOBRAND_SSH_KEYS_DIR/a1111111111111111/id_ed25519"
printf '%s\n' 'ssh-ed25519 AAAATEST alice' >"$NOBRAND_SSH_KEYS_DIR/a1111111111111111/id_ed25519.pub"
printf '%s\n' 'command="/usr/sbin/nologin",no-agent-forwarding,no-X11-forwarding,no-pty ssh-ed25519 AAAATEST alice' \
  >"$NOBRAND_SSH_AUTHORIZED_KEYS_DIR/nbt-alice-11111111"
chmod 0600 "$NOBRAND_SSH_KEYS_DIR/a1111111111111111/id_ed25519"
chmod 0644 "$NOBRAND_SSH_KEYS_DIR/a1111111111111111/id_ed25519.pub" \
  "$NOBRAND_SSH_AUTHORIZED_KEYS_DIR/nbt-alice-11111111"
assert_file_mode 600 "$NOBRAND_SSH_KEYS_DIR/a1111111111111111/id_ed25519"
assert_file_mode 644 "$NOBRAND_SSH_AUTHORIZED_KEYS_DIR/nbt-alice-11111111"

show="$(ssh_tunnel_show_user alice)"
assert_contains "$show" 'nbt-alice-11111111@entry.example.com' 'SSH show connection identity'
assert_contains "$show" 'TCP forwarding: -L / -D / -R' 'SSH show forwarding scope'
assert_not_contains "$show" 'PRIVATE-KEY-MATERIAL' 'SSH show must not reveal private key'

exported="$(ssh_tunnel_export_user alice)"
assert_contains "$exported" 'PRIVATE-KEY-MATERIAL' 'explicit SSH export includes private key'
assert_contains "$exported" '-D 127.0.0.1:1080' 'SSH dynamic-forward command'
assert_contains "$exported" '-L <LOCAL_BIND>:<TARGET_HOST>:<TARGET_PORT>' 'SSH local-forward template'
assert_contains "$exported" '-R <REMOTE_PORT>:<TARGET_HOST>:<TARGET_PORT>' 'SSH remote-forward template'
assert_contains "$exported" 'ExitOnForwardFailure=yes' 'SSH forwarding failure guard'
assert_contains "$exported" 'GatewayPorts=no' 'SSH remote-forward public exposure notice'

old_users_hash="$(jq -cS .users "$NOBRAND_SSH_STATE_FILE" | sha256sum)"
old_policy_hash="$(sha256sum "$policy")"
ssh_tunnel_set_endpoint_state endpoint.example.net 8443
assert_eq "$old_users_hash" "$(jq -cS .users "$NOBRAND_SSH_STATE_FILE" | sha256sum)" \
  'SSH endpoint must not change users'
assert_eq "$old_policy_hash" "$(sha256sum "$policy")" 'SSH endpoint must not change sshd policy'
assert_eq endpoint.example.net "$(jq -r .advertise_host "$NOBRAND_SSH_STATE_FILE")" \
  'SSH endpoint host update'
assert_eq 8443 "$(jq -r .advertise_port "$NOBRAND_SSH_STATE_FILE")" \
  'SSH endpoint port update'

nb_registry_port_owner TCP 22 >/dev/null 2>&1 \
  && fail 'external sshd port must never enter NoBrand proxy-listener registry'
nb_firewall_binding_owned TCP 22 \
  && fail 'external SSH firewall must never be NoBrand-owned'

pass 'SSH Tunnel policy, external ownership, secret boundary, and endpoint isolation'
