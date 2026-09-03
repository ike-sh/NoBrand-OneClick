#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/testlib.sh"

fixture="$(mktemp -d)"
trap 'rm -rf -- "$fixture"' EXIT
export NOBRAND_STATE_DIR="$fixture/nobrand-oneclick/state"
export NOBRAND_CONFIG_DIR="$fixture/nobrand-oneclick/config"
export NOBRAND_LIB_DIR="$fixture/nobrand-oneclick/lib"
export NOBRAND_LIFECYCLE_DIR="$fixture/nobrand-oneclick-lifecycle"
export NOBRAND_LIFECYCLE_TX_FILE="$NOBRAND_LIFECYCLE_DIR/transaction.env"
export NOBRAND_LIFECYCLE_LOCK_FILE="$fixture/run/nobrand-oneclick/lifecycle.lock"
mkdir -p "$(dirname "$NOBRAND_LIFECYCLE_LOCK_FILE")"
chmod 0700 "$(dirname "$NOBRAND_LIFECYCLE_LOCK_FILE")"
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
cat >"$NOBRAND_INGRESS_STATE_FILE" <<'JSON'
{
  "schema_version": 3,
  "ownership": "nobrand-v3",
  "feature": "ingress-profiles",
  "default_profile_id": "i1111111111111111",
  "profiles": [{
    "profile_id": "i1111111111111111",
    "name": "Backup-Mapped",
    "type": "mapped",
    "interface": "eth1",
    "local_address": "198.51.100.110",
    "port_policy": "derived-tail",
    "range_start": null,
    "range_end": null,
    "reserved_ports": [11000],
    "display_host_default": "backup-entry.example.test",
    "display_port_policy": "follow-actual",
    "display_port": null,
    "enabled": true,
    "created_at": "2026-09-01T00:00:00Z",
    "updated_at": "2026-09-01T00:00:00Z"
  }]
}
JSON
nb_ingress_state_valid || fail 'backup fixture ingress state is invalid'
reality_id="r$(openssl rand -hex 8)"
reality_uuid="$(tr -d '\r\n' </proc/sys/kernel/random/uuid)"
reality_private="$(openssl rand -base64 32 | tr '/+' '_-' | tr -d '=\r\n')"
reality_public="$(openssl rand -base64 32 | tr '/+' '_-' | tr -d '=\r\n')"
reality_short="$(openssl rand -hex 8)"
reality_key="$(reality_private_key_file "$reality_id")"
mkdir -p "$(dirname "$(reality_state_file "$reality_id")")" \
  "$(reality_instance_config_dir "$reality_id")"
printf '%s\n' "$reality_private" >"$reality_key"
chmod 0600 "$reality_key"
reality_generate_server_config "$(reality_config_file "$reality_id")" "$reality_id" \
  0.0.0.0 32052 "$reality_uuid" "$reality_private" "$reality_short" \
  backup-camouflage.example.com 8443 22052
reality_generate_state "$(reality_state_file "$reality_id")" "$reality_id" backup-reality \
  0.0.0.0 32052 custom reality-backup.example.test 443 "$reality_uuid" "$reality_public" \
  "$reality_key" "$reality_short" backup-camouflage.example.com 8443 chrome / "$TESTED_XRAY_VERSION" \
  i1111111111111111 22052 2026-09-01T00:00:00Z custom
reality_state_hash="$(sha256sum "$(reality_state_file "$reality_id")")"
reality_config_hash="$(sha256sum "$(reality_config_file "$reality_id")")"
cat >"$NOBRAND_FORWARD_STATE_FILE" <<'JSON'
{"schema_version":3,"ownership":"nobrand-v3","feature":"port-forward","rules":[
 {"rule_id":"f1111111111111111","name":"backup-forward","note":"","backend":"nftables","enabled":false,
  "protocol":"tcp","listen_host":"0.0.0.0","listen_port":16850,
  "target_host":"203.0.113.10","target_port":443,"display_host":"edge.example.test","display_port":24443,
  "display_mode":"custom","created_at":"2026-08-30T00:00:00Z","updated_at":"2026-08-30T00:00:00Z",
  "ownership_metadata":{"managed_listener":true,"managed_firewall":true},
  "backend_options":{"source_mode":"masquerade"},
  "ingress_profile_id":"i1111111111111111"}
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
assert_contains "$listing" 'state/ingress.json' 'backup Ingress Profiles and default profile'
assert_contains "$listing" "state/vless-reality/instances/${reality_id}/state.json" \
  'backup REALITY authoritative state'
assert_contains "$listing" "config/vless-reality/instances/${reality_id}/config.json" \
  'backup REALITY server config'
assert_contains "$listing" "config/vless-reality/instances/${reality_id}/private.key" \
  'backup REALITY private key'

printf '{"value":"changed"}\n' >"$NOBRAND_STATE_DIR/owned.json"
printf 'changed-config\n' >"$NOBRAND_CONFIG_DIR/owned.conf"
jq '.value="changed"' "$NOBRAND_VLESS_STATE_FILE" >"$fixture/vless.changed"
mv "$fixture/vless.changed" "$NOBRAND_VLESS_STATE_FILE"
jq '(.rules[0].enabled)=true | (.rules[0].display_host)="changed.example.test"' \
  "$NOBRAND_FORWARD_STATE_FILE" >"$fixture/forward.changed"
mv "$fixture/forward.changed" "$NOBRAND_FORWARD_STATE_FILE"
jq '(.profiles[0].display_host_default)="changed-entry.example.test" | .default_profile_id=null' \
  "$NOBRAND_INGRESS_STATE_FILE" >"$fixture/ingress.changed"
mv "$fixture/ingress.changed" "$NOBRAND_INGRESS_STATE_FILE"
printf '%s\n' "$(openssl rand -base64 32 | tr '/+' '_-' | tr -d '=\r\n')" >"$reality_key"
jq '.uuid="00000000-0000-4000-8000-000000000000" | .short_id="aabb"
  | .target_host="changed.example" | .server_name="changed.example"
  | .camouflage_mode="auto" | .listen_port=39999
  | .ingress_profile_id="changed" | .advertise_host="changed.example"' \
  "$(reality_state_file "$reality_id")" >"$fixture/reality.changed"
mv "$fixture/reality.changed" "$(reality_state_file "$reality_id")"
nobrand_backup_restore "$archive" >/dev/null
assert_eq original "$(jq -r .value "$NOBRAND_STATE_DIR/owned.json")" 'restored state'
assert_eq secret-config "$(tr -d '\r\n' <"$NOBRAND_CONFIG_DIR/owned.conf")" 'restored config'
assert_eq original "$(jq -r .value "$NOBRAND_VLESS_STATE_FILE")" 'restored VLESS state'
assert_eq false "$(jq -r '.rules[0].enabled' "$NOBRAND_FORWARD_STATE_FILE")" \
  'restored Forward enabled state'
assert_eq edge.example.test "$(jq -r '.rules[0].display_host' "$NOBRAND_FORWARD_STATE_FILE")" \
  'restored Forward Display Endpoint metadata'
assert_eq i1111111111111111 "$(jq -r .default_profile_id "$NOBRAND_INGRESS_STATE_FILE")" \
  'restored default Ingress Profile'
assert_eq backup-entry.example.test "$(jq -r '.profiles[0].display_host_default' "$NOBRAND_INGRESS_STATE_FILE")" \
  'restored Ingress Profile display metadata'
assert_eq i1111111111111111 "$(jq -r '.rules[0].ingress_profile_id' "$NOBRAND_FORWARD_STATE_FILE")" \
  'restored Forward-profile association'
assert_eq "$reality_private" "$(tr -d '\r\n' <"$reality_key")" 'restored REALITY private key'
assert_eq "$reality_public" "$(reality_state_field "$reality_id" public_key)" 'restored REALITY public key'
assert_eq "$reality_uuid" "$(reality_state_field "$reality_id" uuid)" 'restored REALITY UUID'
assert_eq "$reality_short" "$(reality_state_field "$reality_id" short_id)" 'restored REALITY short ID'
assert_eq backup-camouflage.example.com "$(reality_state_field "$reality_id" server_name)" \
  'restored custom REALITY camouflage host'
assert_eq custom "$(reality_state_field "$reality_id" camouflage_mode)" \
  'restored REALITY camouflage origin mode'
assert_eq 8443 "$(reality_state_field "$reality_id" target_port)" \
  'restored custom REALITY camouflage target port'
assert_eq 32052 "$(reality_state_field "$reality_id" listen_port)" 'restored REALITY port'
assert_eq i1111111111111111 "$(reality_state_field "$reality_id" ingress_profile_id)" \
  'restored REALITY Profile association'
assert_eq reality-backup.example.test "$(reality_state_field "$reality_id" advertise_host)" \
  'restored REALITY Display metadata'
assert_eq 22052 "$(reality_state_field "$reality_id" defender_port)" 'restored REALITY defender port'
assert_eq "$(reality_defender_tag "$reality_id")" \
  "$(reality_state_field "$reality_id" defender_tag)" 'restored REALITY defender tag'
assert_eq "$reality_state_hash" "$(sha256sum "$(reality_state_file "$reality_id")")" \
  'restored REALITY defender state bytes'
assert_eq "$reality_config_hash" "$(sha256sum "$(reality_config_file "$reality_id")")" \
  'restored REALITY defender config/routing bytes'
printf 'CUSTOM_CAMOUFLAGE_BACKUP_RESTORE=PASS\n'
assert_file_mode 600 "$reality_key"

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
assert_eq i1111111111111111 "$(jq -r .default_profile_id "$NOBRAND_INGRESS_STATE_FILE")" \
  'fresh-manager restore ingress state'

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
  reality_restore_runtime() { printf '%s\n' runtime-reality >>"$runtime_calls"; }
  tuic_restore_runtime() { printf '%s\n' runtime-tuic >>"$runtime_calls"; }
  forward_realm_restore_runtime() { printf '%s\n' runtime-realm >>"$runtime_calls"; }
  nobrand_restore_protocol_runtimes_under_test
)
for expected_call in \
  load-mieru deps-mieru runtime-mieru account-mieru service-mieru \
  runtime-snell-v4 runtime-snell-v5 service-snell service-snell-instance \
  runtime-xray validate-xray service-hy2 service-vless runtime-reality runtime-tuic runtime-realm; do
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

# Archive path names alone are insufficient: expected SSH directories must
# remain real directories after extraction. Build otherwise valid archives
# whose SSH state root is a symlink or whose SSH config root is a regular file,
# then prove topology validation stops before layout initialization, tree
# replacement, or any external identity/config operation.
export NOBRAND_SSH_CONFIG_MAIN="$fixture/sshd_config"
export NOBRAND_SSH_CONFIG_DROPIN="$fixture/sshd_config.d/90-nobrand-ssh-tunnel.conf"
printf '%s\n' 'topology-baseline-sshd' >"$NOBRAND_SSH_CONFIG_MAIN"

make_unsafe_ssh_topology_archive() {
  local kind="$1" stage archive
  stage="$fixture/unsafe-ssh-topology/${kind}/stage"
  archive="$fixture/unsafe-ssh-topology/${kind}.tar.gz"
  rm -rf -- "$(dirname "$stage")" "$archive"
  mkdir -p "$stage/state/ssh-tunnel/keys" "$stage/state/ssh-tunnel/watchdog" \
    "$stage/config/ssh-tunnel/authorized_keys" "$stage/config/ssh-tunnel/accounts"
  printf '%s\n' \
    'project=NoBrand-OneClick' \
    'schema_version=3' \
    'ownership=nobrand-v3' \
    >"$stage/manifest.txt"
  printf '%s\n' \
    '{"schema_version":3,"project":"NoBrand-OneClick","ownership":"nobrand-v3"}' \
    >"$stage/state/state.json"
  ssh_tunnel_generate_state "$stage/state/ssh-tunnel/state.json" custom \
    entry.example.test 443 2222 marker-block "$NOBRAND_SSH_CONFIG_MAIN" '[]' \
    2026-08-30T00:00:00Z
  chmod 0700 "$stage/state" "$stage/state/ssh-tunnel" \
    "$stage/state/ssh-tunnel/keys" "$stage/state/ssh-tunnel/watchdog"
  chmod 0711 "$stage/config" "$stage/config/ssh-tunnel"
  chmod 0755 "$stage/config/ssh-tunnel/authorized_keys"
  chmod 0700 "$stage/config/ssh-tunnel/accounts"
  chmod 0600 "$stage/state/state.json" "$stage/state/ssh-tunnel/state.json"
  case "$kind" in
    state-symlink)
      mv "$stage/state/ssh-tunnel" "$stage/state/ssh-tunnel-target"
      ln -s ssh-tunnel-target "$stage/state/ssh-tunnel"
      [ -L "$stage/state/ssh-tunnel" ] \
        || fail 'unsafe backup fixture did not create the SSH state symlink'
      ;;
    config-file)
      rm -rf -- "$stage/config/ssh-tunnel"
      printf '%s\n' 'not-a-directory' >"$stage/config/ssh-tunnel"
      [ -f "$stage/config/ssh-tunnel" ] && [ ! -d "$stage/config/ssh-tunnel" ] \
        || fail 'unsafe backup fixture did not create the SSH config file'
      ;;
    *) fail "unknown unsafe SSH topology fixture: $kind" ;;
  esac
  tar -C "$stage" -czf "$archive" manifest.txt state config
  printf '%s' "$archive"
}

topology_state_hash="$(sha256sum "$NOBRAND_STATE_DIR/owned.json")"
topology_config_hash="$(sha256sum "$NOBRAND_CONFIG_DIR/owned.conf")"
topology_sshd_hash="$(sha256sum "$NOBRAND_SSH_CONFIG_MAIN")"
for unsafe_ssh_topology in state-symlink config-file; do
  unsafe_ssh_archive="$(make_unsafe_ssh_topology_archive "$unsafe_ssh_topology")"
  unsafe_ssh_markers="$fixture/unsafe-ssh-topology/${unsafe_ssh_topology}/markers"
  mkdir -p "$unsafe_ssh_markers"
  if (
    nb_init_state_layout() { : >"$unsafe_ssh_markers/layout"; }
    nobrand_stop_all_services() { : >"$unsafe_ssh_markers/services-stopped"; }
    ssh_tunnel_snapshot_external_state() { : >"$unsafe_ssh_markers/external-snapshot"; }
    tuic_snapshot_restore_side_effects() { : >"$unsafe_ssh_markers/tuic-snapshot"; }
    forward_snapshot_restore_side_effects() { : >"$unsafe_ssh_markers/forward-snapshot"; }
    nobrand_restore_protocol_runtimes() { : >"$unsafe_ssh_markers/runtime"; }
    ssh_tunnel_restore_system_state() { : >"$unsafe_ssh_markers/ssh-restore"; }
    nobrand_start_enabled_services() { : >"$unsafe_ssh_markers/services-started"; }
    ssh_tunnel_create_group() { : >"$unsafe_ssh_markers/group-created"; }
    ssh_tunnel_create_linux_user_with_uid() { : >"$unsafe_ssh_markers/user-created"; }
    ssh_tunnel_apply_policy() { : >"$unsafe_ssh_markers/policy-applied"; }
    ssh_tunnel_restore_external_snapshot() { : >"$unsafe_ssh_markers/external-restored"; }
    _has_group() { return 1; }
    _has_user() { return 1; }
    nobrand_backup_restore "$unsafe_ssh_archive" >/dev/null 2>&1
  ); then
    fail "backup restore accepted unsafe staged SSH topology: $unsafe_ssh_topology"
  fi
  [ -z "$(find "$unsafe_ssh_markers" -mindepth 1 -maxdepth 1 -print -quit)" ] \
    || fail "unsafe staged SSH topology crossed the pre-mutation boundary: $unsafe_ssh_topology"
  assert_eq "$topology_state_hash" "$(sha256sum "$NOBRAND_STATE_DIR/owned.json")" \
    "unsafe SSH topology preserves live state: $unsafe_ssh_topology"
  assert_eq "$topology_config_hash" "$(sha256sum "$NOBRAND_CONFIG_DIR/owned.conf")" \
    "unsafe SSH topology preserves live config: $unsafe_ssh_topology"
  assert_eq "$topology_sshd_hash" "$(sha256sum "$NOBRAND_SSH_CONFIG_MAIN")" \
    "unsafe SSH topology preserves external sshd config: $unsafe_ssh_topology"
done

# Failure after TUIC runtime replacement and SSH Linux-account creation must
# restore external side effects as well as the state/config trees.
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
jq '.policy_applied=true' "$NOBRAND_SSH_STATE_FILE" >"$fixture/ssh-backup-ready.json"
mv -f "$fixture/ssh-backup-ready.json" "$NOBRAND_SSH_STATE_FILE"
chmod 0600 "$NOBRAND_SSH_STATE_FILE"
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
forward_remove_restore_attempt_resources() { :; }
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
