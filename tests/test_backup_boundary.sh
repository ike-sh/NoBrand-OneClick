#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/testlib.sh"

fixture="$(mktemp -d)"
trap 'rm -rf -- "$fixture"' EXIT
export NOBRAND_STATE_DIR="$fixture/nobrand-oneclick/state"
export NOBRAND_CONFIG_DIR="$fixture/nobrand-oneclick/config"
export NOBRAND_LIB_DIR="$fixture/nobrand-oneclick/lib"
source_installer
eval "$(declare -f nobrand_restore_protocol_runtimes \
  | sed '1s/^nobrand_restore_protocol_runtimes /nobrand_restore_protocol_runtimes_under_test /')"
nobrand_restore_protocol_runtimes() { :; }
nobrand_fresh_restore_runtime_preflight() { :; }
nobrand_remove_fresh_restore_protocol_resources() { :; }
nb_init_state_layout
nobrand_stop_all_services() { :; }
nobrand_start_enabled_services() { :; }

printf '{"value":"original"}\n' >"$NOBRAND_STATE_DIR/owned.json"
printf 'secret-config\n' >"$NOBRAND_CONFIG_DIR/owned.conf"
printf '{"protocol":"vless-sudoku","value":"original"}\n' >"$NOBRAND_VLESS_STATE_FILE"
printf '{"inbounds":[]}\n' >"$NOBRAND_VLESS_CONFIG_FILE"
printf '{"outbounds":[]}\n' >"$NOBRAND_VLESS_CLIENT_FILE"
cat >"$NOBRAND_FORWARD_STATE_FILE" <<'JSON'
{"schema_version":3,"ownership":"nobrand-v3","feature":"port-forward","rules":[
 {"rule_id":"f1111111111111111","name":"backup-forward","note":"","backend":"nftables","enabled":false,
  "protocol":"tcp","listen_host":"0.0.0.0","listen_port":16850,
  "target_host":"203.0.113.10","target_port":443,"display_host":"edge.example.test","display_port":24443,
  "display_mode":"custom","created_at":"2026-08-30T00:00:00Z","updated_at":"2026-08-30T00:00:00Z",
  "ownership_metadata":{"managed_listener":true,"managed_firewall":true},
  "backend_options":{"source_mode":"masquerade"}}
]}
JSON
printf 'owned-forward-ruleset\n' >"$NOBRAND_FORWARD_NFT_RULESET"
mkdir -p "$fixture/external-xray"
printf 'must-not-back-up\n' >"$fixture/external-xray/config.json"
archive="$fixture/nobrand-backup.tar.gz"
nobrand_backup_create "$archive" >/dev/null
assert_file_mode 600 "$archive"
listing="$(tar -tzf "$archive")"
assert_contains "$listing" 'state/owned.json' 'backup state content'
assert_contains "$listing" 'config/owned.conf' 'backup config content'
assert_contains "$listing" 'state/vless-sudoku/state.json' 'backup VLESS state'
assert_contains "$listing" 'state/vless-sudoku/client.json' 'backup VLESS client export'
assert_contains "$listing" 'config/vless-sudoku/config.json' 'backup VLESS config'
assert_not_contains "$listing" 'external-xray' 'Xray-OneClick boundary'
assert_contains "$listing" 'state/forward/state.json' 'backup Forward authoritative state'
assert_contains "$listing" 'config/forward/nftables.nft' 'backup Forward generated ownership artifact'

printf '{"value":"changed"}\n' >"$NOBRAND_STATE_DIR/owned.json"
printf 'changed-config\n' >"$NOBRAND_CONFIG_DIR/owned.conf"
jq '.value="changed"' "$NOBRAND_VLESS_STATE_FILE" >"$fixture/vless.changed"
mv "$fixture/vless.changed" "$NOBRAND_VLESS_STATE_FILE"
jq '(.rules[0].enabled)=true | (.rules[0].display_host)="changed.example.test"' \
  "$NOBRAND_FORWARD_STATE_FILE" >"$fixture/forward.changed"
mv "$fixture/forward.changed" "$NOBRAND_FORWARD_STATE_FILE"
nobrand_backup_restore "$archive" >/dev/null
assert_eq original "$(jq -r .value "$NOBRAND_STATE_DIR/owned.json")" 'restored state'
assert_eq secret-config "$(tr -d '\r\n' <"$NOBRAND_CONFIG_DIR/owned.conf")" 'restored config'
assert_eq original "$(jq -r .value "$NOBRAND_VLESS_STATE_FILE")" 'restored VLESS state'
assert_eq false "$(jq -r '.rules[0].enabled' "$NOBRAND_FORWARD_STATE_FILE")" \
  'restored Forward enabled state'
assert_eq edge.example.test "$(jq -r '.rules[0].display_host' "$NOBRAND_FORWARD_STATE_FILE")" \
  'restored Forward Display Endpoint metadata'

# A manager-only fresh install has no state/config roots.  The same backup
# must restore successfully from that exact zero-state layout without needing
# a dummy protocol action to create the directories first.
rm -rf -- "$NOBRAND_STATE_DIR" "$NOBRAND_CONFIG_DIR"
[ ! -e "$NOBRAND_STATE_DIR" ] && [ ! -e "$NOBRAND_CONFIG_DIR" ] \
  || fail 'fresh-manager restore fixture roots were not removed'
nobrand_backup_restore "$archive" >/dev/null
secure_stat_path "$NOBRAND_STATE_DIR" dir \
  || fail 'fresh-manager restored state root is insecure'
secure_stat_path "$NOBRAND_CONFIG_DIR" dir \
  || fail 'fresh-manager restored config root is insecure'
assert_eq original "$(jq -r .value "$NOBRAND_STATE_DIR/owned.json")" \
  'fresh-manager restore state'
assert_eq secret-config "$(tr -d '\r\n' <"$NOBRAND_CONFIG_DIR/owned.conf")" \
  'fresh-manager restore config'

# Runtime/service reconstruction is a distinct restore phase.  It must cover
# every protocol whose downloadable runtime or service unit is intentionally
# excluded from the archive.
runtime_calls="$fixture/runtime-restore.calls"
(
  users_state_exists() { return 0; }
  users_count() { printf '1'; }
  load_install_state() { printf '%s\n' load-mieru >>"$runtime_calls"; }
  detect_pkg_manager() { printf 'deb'; }
  ensure_management_dependencies() { printf '%s\n' deps-mieru >>"$runtime_calls"; }
  repair_mita_binary_paths() { printf '%s\n' runtime-mieru >>"$runtime_calls"; }
  ensure_mita_account() { printf '%s\n' account-mieru >>"$runtime_calls"; }
  install_instance_runtime() { printf '%s\n' service-mieru >>"$runtime_calls"; }
  snell_instance_ids() { printf '%s\n' s1111111111111111 s2222222222222222; }
  snell_config_matches_state() { :; }
  snell_state_field() { [ "$1" = s1111111111111111 ] && printf '4' || printf '5'; }
  nobrand_prepare_common() { printf '%s\n' deps-common >>"$runtime_calls"; }
  snell_install_runtime() { printf 'runtime-snell-v%s\n' "$1" >>"$runtime_calls"; }
  snell_install_service_runtime() { printf '%s\n' service-snell >>"$runtime_calls"; }
  snell_ensure_openrc_service() { printf '%s\n' service-snell-instance >>"$runtime_calls"; }
  hysteria2_state_exists() { return 0; }
  vless_sudoku_state_exists() { return 0; }
  nobrand_install_xray_runtime() { printf '%s\n' runtime-xray >>"$runtime_calls"; }
  nobrand_xray_validate_managed_configs() { printf '%s\n' validate-xray >>"$runtime_calls"; }
  nobrand_write_hy2_service() { printf '%s\n' service-hy2 >>"$runtime_calls"; }
  nobrand_write_vless_sudoku_service() { printf '%s\n' service-vless >>"$runtime_calls"; }
  tuic_restore_runtime() { printf '%s\n' runtime-tuic >>"$runtime_calls"; }
  forward_realm_restore_runtime() { printf '%s\n' runtime-realm >>"$runtime_calls"; }
  nobrand_restore_protocol_runtimes_under_test
)
for expected_call in \
  load-mieru deps-mieru runtime-mieru account-mieru service-mieru \
  runtime-snell-v4 runtime-snell-v5 service-snell service-snell-instance \
  runtime-xray validate-xray service-hy2 service-vless runtime-tuic runtime-realm; do
  grep -qxF "$expected_call" "$runtime_calls" \
    || fail "manager-only restore omitted runtime/service step: $expected_call"
done

if ( nb_assert_safe_nobrand_root /etc NOBRAND_STATE_DIR >/dev/null 2>&1 ); then
  fail 'restore root /etc must be rejected'
fi
if ( nb_assert_safe_nobrand_root /var NOBRAND_STATE_DIR >/dev/null 2>&1 ); then
  fail 'restore root /var must be rejected'
fi
if ( nb_assert_safe_nobrand_root "$fixture/../etc" NOBRAND_STATE_DIR >/dev/null 2>&1 ); then
  fail 'restore root containing .. must be rejected'
fi
safe="$(nb_assert_safe_nobrand_root "$NOBRAND_STATE_DIR" NOBRAND_STATE_DIR)"
assert_eq "$NOBRAND_STATE_DIR" "$safe" 'safe NoBrand namespace'

# Failure after TUIC runtime replacement and SSH Linux-account creation must
# restore external side effects as well as the state/config trees.
export NOBRAND_SSH_CONFIG_MAIN="$fixture/sshd_config"
export NOBRAND_SSH_CONFIG_DROPIN="$fixture/sshd_config.d/90-nobrand-ssh-tunnel.conf"
export NOBRAND_TUIC_SYSTEMD_TEMPLATE="$fixture/systemd/nobrand-tuic@.service"
account_id=a3333333333333333
linux_user=nbt-restore
restore_uid=49001
restore_gid=49000
mkdir -p "$NOBRAND_SSH_KEYS_DIR/$account_id" "$NOBRAND_SSH_AUTHORIZED_KEYS_DIR" \
  "$NOBRAND_SSH_ACCOUNT_MARKER_DIR" "$NOBRAND_TUIC_STATE_DIR/t3333333333333333" \
  "$NOBRAND_TUIC_CONFIG_DIR/t3333333333333333"
ssh-keygen -q -t ed25519 -N '' -f "$NOBRAND_SSH_KEYS_DIR/$account_id/id_ed25519"
fingerprint="$(ssh_tunnel_key_fingerprint "$NOBRAND_SSH_KEYS_DIR/$account_id/id_ed25519.pub")"
restore_user="$(ssh_tunnel_user_json "$account_id" restore "$linux_user" "$restore_uid" \
  "$fingerprint" 2026-08-30T00:00:00Z)"
ssh_tunnel_generate_state "$NOBRAND_SSH_STATE_FILE" custom restore.example.test 443 22 \
  marker-block "$NOBRAND_SSH_CONFIG_MAIN" "[$restore_user]" 2026-08-30T00:00:00Z
jq -n --arg account_id "$account_id" --arg linux_user "$linux_user" --argjson uid "$restore_uid" \
  '{schema_version:3,ownership:"nobrand-v3",account_id:$account_id,linux_user:$linux_user,uid:$uid}' \
  >"$NOBRAND_SSH_ACCOUNT_MARKER_DIR/$linux_user.json"
printf '%s\n' 'staged-authorized-key' >"$NOBRAND_SSH_AUTHORIZED_KEYS_DIR/$linux_user"
printf '%s\n' '{"schema_version":3,"ownership":"nobrand-v3","protocol":"tuic-v5","instance_id":"t3333333333333333","listen_port":24443,"runtime_channel":"stable","runtime_version":"1.13.20","enabled":true}' \
  >"$NOBRAND_TUIC_STATE_DIR/t3333333333333333/state.json"
printf '%s\n' '{"inbounds":[]}' >"$NOBRAND_TUIC_CONFIG_DIR/t3333333333333333/config.json"
rollback_archive="$fixture/nobrand-rollback-modules.tar.gz"
nobrand_backup_create "$rollback_archive" >/dev/null

# Reproduce the exact manager-only layout: neither authoritative root exists.
# This catches rollback paths that accidentally assume a pre-existing schema
# file before external SSH identities have been removed.
rm -rf -- "$NOBRAND_STATE_DIR" "$NOBRAND_CONFIG_DIR"
[ ! -e "$NOBRAND_STATE_DIR" ] && [ ! -e "$NOBRAND_CONFIG_DIR" ] \
  || fail 'rollback fixture did not reach manager-only zero state'
printf '%s\n' 'baseline-sshd-config' >"$NOBRAND_SSH_CONFIG_MAIN"
mkdir -p "$(dirname "$NOBRAND_TUIC_SYSTEMD_TEMPLATE")"
printf '%s\n' 'baseline-tuic-template' >"$NOBRAND_TUIC_SYSTEMD_TEMPLATE"
printf '%s\n' 'baseline-sing-box-runtime' >"$NOBRAND_SING_BOX_BIN"
chmod 0755 "$NOBRAND_SING_BOX_BIN"
baseline_sshd_hash="$(sha256sum "$NOBRAND_SSH_CONFIG_MAIN")"
baseline_runtime_hash="$(sha256sum "$NOBRAND_SING_BOX_BIN")"
baseline_template_hash="$(sha256sum "$NOBRAND_TUIC_SYSTEMD_TEMPLATE")"
simulated_group="$fixture/simulated-group"
simulated_user="$fixture/simulated-user"

_has_group() { [ "$1" = "$NOBRAND_SSH_GROUP" ] && [ -s "$simulated_group" ]; }
_has_user() { [ "$1" = "$linux_user" ] && [ -s "$simulated_user" ]; }
getent() {
  case "${1:-}:${2:-}" in
    group:"$NOBRAND_SSH_GROUP") [ -s "$simulated_group" ] && printf '%s:x:%s:\n' "$NOBRAND_SSH_GROUP" "$restore_gid" ;;
    passwd:"$linux_user"|passwd:"$restore_uid")
      [ -s "$simulated_user" ] && printf '%s:x:%s:%s:NoBrand SSH Tunnel %s:/nonexistent:/usr/sbin/nologin\n' \
        "$linux_user" "$restore_uid" "$restore_gid" "$account_id"
      ;;
    *) command getent "$@" ;;
  esac
}
id() {
  if [ "${1:-}" = -u ] && [ "${2:-}" = "$linux_user" ] && [ -s "$simulated_user" ]; then
    printf '%s\n' "$restore_uid"
  else
    command id "$@"
  fi
}
ssh_tunnel_create_group() {
  printf '%s\n' "$restore_gid" >"$simulated_group"
  jq -n --arg group "$NOBRAND_SSH_GROUP" --argjson gid "$restore_gid" \
    '{schema_version:3,ownership:"nobrand-v3",group:$group,gid:$gid}' >"$NOBRAND_SSH_GROUP_MARKER"
}
ssh_tunnel_create_linux_user_with_uid() { printf '%s\n' "$4" >"$simulated_user"; }
ssh_tunnel_delete_linux_user() {
  [ -f "$NOBRAND_SSH_ACCOUNT_MARKER_DIR/$linux_user.json" ] \
    || fail 'SSH external rollback ran after restored ownership metadata was erased'
  rm -f "$simulated_user"
}
groupdel() { rm -f "$simulated_group"; }
pkill() { :; }
ssh_tunnel_sshd_test() { :; }
ssh_tunnel_reload() { :; }
ssh_tunnel_apply_policy() { printf '%s\n' 'staged-sshd-policy' >"$NOBRAND_SSH_CONFIG_MAIN"; }
tuic_restore_runtime() {
  printf '%s\n' 'staged-sing-box-runtime' >"$NOBRAND_SING_BOX_BIN"
  printf '%s\n' 'staged-tuic-template' >"$NOBRAND_TUIC_SYSTEMD_TEMPLATE"
}
nobrand_restore_protocol_runtimes() { tuic_restore_runtime; }
tuic_remove_restore_attempt_resources() { :; }
fresh_cleanup_marker="$fixture/fresh-runtime-cleanup"
nobrand_remove_fresh_restore_protocol_resources() { : >"$fresh_cleanup_marker"; }
nobrand_start_enabled_services() { return 1; }
if ( nobrand_backup_restore "$rollback_archive" >/dev/null 2>&1 ); then
  fail 'restore acceptance failure must fail the transaction'
fi
[ -e "$fresh_cleanup_marker" ] || fail 'fresh-manager runtime rollback was not invoked'
[ ! -e "$simulated_user" ] || fail 'failed restore left a newly created SSH Linux user'
[ ! -e "$simulated_group" ] || fail 'failed restore left a newly created SSH group'
[ ! -e "$NOBRAND_SSH_STATE_FILE" ] || fail 'failed restore left staged SSH state'
[ -z "$(tuic_instance_ids)" ] || fail 'failed restore left staged TUIC state'
[ ! -e "$NOBRAND_STATE_DIR" ] || fail 'failed fresh-manager restore left a state root'
[ ! -e "$NOBRAND_CONFIG_DIR" ] || fail 'failed fresh-manager restore left a config root'
assert_eq "$baseline_sshd_hash" "$(sha256sum "$NOBRAND_SSH_CONFIG_MAIN")" \
  'failed restore restores exact external sshd config'
assert_eq "$baseline_runtime_hash" "$(sha256sum "$NOBRAND_SING_BOX_BIN")" \
  'failed restore restores exact TUIC runtime'
assert_eq "$baseline_template_hash" "$(sha256sum "$NOBRAND_TUIC_SYSTEMD_TEMPLATE")" \
  'failed restore restores exact TUIC service template'

pass 'NoBrand backup/restore ownership, destructive boundary, and external-side-effect rollback'
