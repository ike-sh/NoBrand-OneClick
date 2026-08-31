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

tuic_password='SENSITIVE_TUIC_PASSWORD_3_1_TEST'
tuic_uuid=11111111-2222-4333-8444-555555555555
tuic_id=t1111111111111111
tuic_user="$(tuic_user_json u1111111111111111 output-user "$tuic_uuid" "$tuic_password" \
  2026-08-30T00:00:00Z)"
tuic_cert="$(tuic_cert_file "$tuic_id")"
tuic_key="$(tuic_key_file "$tuic_id")"
mkdir -p "$(dirname "$(tuic_state_file "$tuic_id")")" "$(dirname "$(tuic_config_file "$tuic_id")")"
printf '%s\n' 'not-a-real-certificate' >"$tuic_cert"
printf '%s\n' 'SENSITIVE_TUIC_TLS_KEY_3_1_TEST' >"$tuic_key"
tuic_generate_server_config "$(tuic_config_file "$tuic_id")" "$tuic_id" 0.0.0.0 24443 \
  "$tuic_cert" "$tuic_key" output.example.test "[$tuic_user]"
tuic_generate_state "$(tuic_state_file "$tuic_id")" "$tuic_id" output-instance 0.0.0.0 24443 \
  custom entry.example.test 443 output.example.test stable "$TESTED_SING_BOX_SERVER_VERSION" \
  "$tuic_cert" "$tuic_key" "[$tuic_user]" 2026-08-30T00:00:00Z

ssh_private='SENSITIVE_SSH_PRIVATE_KEY_3_1_TEST'
ssh_account_id=a1111111111111111
ssh_linux_user=nbt-output-user
mkdir -p "$NOBRAND_SSH_KEYS_DIR/$ssh_account_id" "$NOBRAND_SSH_AUTHORIZED_KEYS_DIR"
printf '%s\n' "$ssh_private" >"$NOBRAND_SSH_KEYS_DIR/$ssh_account_id/id_ed25519"
printf '%s\n' 'ssh-ed25519 AAAATEST output-user' \
  >"$NOBRAND_SSH_KEYS_DIR/$ssh_account_id/id_ed25519.pub"
printf '%s\n' 'ssh-ed25519 AAAATEST output-user' >"$NOBRAND_SSH_AUTHORIZED_KEYS_DIR/$ssh_linux_user"
ssh_user="$(ssh_tunnel_user_json "$ssh_account_id" output-user "$ssh_linux_user" 49001 \
  SHA256:output-test 2026-08-30T00:00:00Z)"
ssh_tunnel_generate_state "$NOBRAND_SSH_STATE_FILE" custom entry.example.test 443 22 marker-block \
  "$fixture/sshd_config" "[$ssh_user]" 2026-08-30T00:00:00Z
jq '.policy_applied=true' "$NOBRAND_SSH_STATE_FILE" >"$fixture/ssh-state.tmp"
mv -f "$fixture/ssh-state.tmp" "$NOBRAND_SSH_STATE_FILE"

tuic_service_active() { return 1; }
nb_service_manager() { printf none; }
read_tty() { printf -v "$1" '%s' 0; }
set +e
ordinary_output="$({
  nobrand_status
  nobrand_nodes
  nobrand_doctor
  tuic_status
  ssh_tunnel_status
  nobrand_menu_loop
} 2>&1)"
set -e
for secret in "$tuic_password" "$tuic_uuid" "$ssh_private" 'SENSITIVE_TUIC_TLS_KEY_3_1_TEST'; do
  assert_not_contains "$ordinary_output" "$secret" 'ordinary status/doctor/nodes/menu output secret boundary'
done

tuic_explicit="$(tuic_show_user "$tuic_id" output-user)"
assert_contains "$tuic_explicit" "$tuic_password" 'explicit TUIC show reveals requested credential'
assert_contains "$tuic_explicit" "$tuic_uuid" 'explicit TUIC show reveals requested UUID'
ssh_explicit="$(ssh_tunnel_export_user output-user)"
assert_contains "$ssh_explicit" "$ssh_private" 'explicit SSH export reveals requested private key'

pass 'ordinary status/doctor/nodes/menu output is secret-free; explicit credential actions remain explicit'
