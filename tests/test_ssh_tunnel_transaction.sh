#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/testlib.sh"

fixture="$(mktemp -d)"
fake_service_pid=""
cleanup() {
  [ -z "$fake_service_pid" ] || kill "$fake_service_pid" >/dev/null 2>&1 || true
  [ -z "$fake_service_pid" ] || wait "$fake_service_pid" >/dev/null 2>&1 || true
  rm -rf -- "$fixture"
}
trap cleanup EXIT
export NOBRAND_STATE_DIR="$fixture/nobrand-oneclick/state"
export NOBRAND_CONFIG_DIR="$fixture/nobrand-oneclick/config"
export NOBRAND_LIB_DIR="$fixture/nobrand-oneclick/lib"
export NOBRAND_SSH_CONFIG_MAIN="$fixture/sshd_config"
export NOBRAND_SSH_CONFIG_DROPIN="$fixture/sshd_config.d/90-nobrand-ssh-tunnel.conf"
export NOBRAND_SSH_WATCHDOG_TIMEOUT=30
source_installer
nb_init_state_layout

fake_sshd="$fixture/sshd"
cat >"$fake_sshd" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod 0755 "$fake_sshd"
( trap : HUP; while :; do sleep 1; done ) &
fake_service_pid=$!
ssh_tunnel_sshd_binary() { printf '%s' "$fake_sshd"; }
ssh_tunnel_detect_service() { printf 'sighup|%s' "$fake_service_pid"; }
ssh_tunnel_reload() { return 0; }
ssh_tunnel_sshd_test() { return 0; }
ssh_tunnel_effective_policy_valid() { return 0; }

mkdir -p "$NOBRAND_SSH_STATE_DIR"
printf '%s\n' 'Port 2222' >"$NOBRAND_SSH_CONFIG_MAIN"
printf '%s\n' '{"schema_version":3,"ownership":"nobrand-v3","protocol":"ssh-tunnel","policy_applied":false,"pending_operation":"","pending_watchdog_token":"","users":[]}' \
  >"$NOBRAND_SSH_STATE_FILE"
chmod 0600 "$NOBRAND_SSH_STATE_FILE"

config_hash="$(sha256sum "$NOBRAND_SSH_CONFIG_MAIN")"
state_hash="$(sha256sum "$NOBRAND_SSH_STATE_FILE")"
watchdog="$(ssh_tunnel_watchdog_begin "$NOBRAND_SSH_CONFIG_MAIN" install)"
IFS='|' read -r token pid _origin operation <<<"$watchdog"
assert_eq install "$operation" 'SSH watchdog operation identity'
printf '%s\n' 'BROKEN CONFIG' >"$NOBRAND_SSH_CONFIG_MAIN"
printf '%s\n' '{"broken":true}' >"$NOBRAND_SSH_STATE_FILE"
ssh_tunnel_watchdog_rollback_now "$token" "$pid"
assert_eq "$config_hash" "$(sha256sum "$NOBRAND_SSH_CONFIG_MAIN")" \
  'SSH watchdog restores exact config snapshot'
assert_eq "$state_hash" "$(sha256sum "$NOBRAND_SSH_STATE_FILE")" \
  'SSH watchdog restores exact state snapshot'

policy="$fixture/policy"
ssh_tunnel_generate_policy "$policy" /usr/sbin/nologin
{
  printf '%s\n' 'Port 2222'
  printf '%s\n' "$NOBRAND_SSH_BLOCK_BEGIN"
  cat "$policy"
  printf '%s\n' "$NOBRAND_SSH_BLOCK_END"
} >"$NOBRAND_SSH_CONFIG_MAIN"
users='[]'
ssh_tunnel_generate_state "$NOBRAND_SSH_STATE_FILE" custom entry.example.test 443 2222 marker-block \
  "$NOBRAND_SSH_CONFIG_MAIN" "$users" 2026-08-30T00:00:00Z
jq '.policy_applied=true' "$NOBRAND_SSH_STATE_FILE" >"$fixture/state.tmp"
mv -f "$fixture/state.tmp" "$NOBRAND_SSH_STATE_FILE"
chmod 0600 "$NOBRAND_SSH_STATE_FILE"
before_remove_config="$(sha256sum "$NOBRAND_SSH_CONFIG_MAIN")"
before_remove_state="$(sha256sum "$NOBRAND_SSH_STATE_FILE")"
remove_output="$(ssh_tunnel_remove_policy uninstall)"
assert_contains "$remove_output" 'nobrand ssh confirm-admin --token' \
  'SSH uninstall requires new-admin confirmation'
assert_eq uninstall "$(ssh_tunnel_state_field pending_operation)" \
  'SSH uninstall persists pending operation'
assert_eq false "$(ssh_tunnel_state_field policy_applied)" \
  'SSH uninstall marks policy removed while watchdog is armed'
assert_not_contains "$(cat "$NOBRAND_SSH_CONFIG_MAIN")" "$NOBRAND_SSH_BLOCK_BEGIN" \
  'SSH uninstall removes only managed marker block before confirmation'
token="$(ssh_tunnel_state_field pending_watchdog_token)"
pid="$(ssh_tunnel_state_field pending_watchdog_pid)"
ssh_tunnel_watchdog_rollback_now "$token" "$pid"
assert_eq "$before_remove_config" "$(sha256sum "$NOBRAND_SSH_CONFIG_MAIN")" \
  'unconfirmed SSH uninstall restores managed policy'
assert_eq "$before_remove_state" "$(sha256sum "$NOBRAND_SSH_STATE_FILE")" \
  'unconfirmed SSH uninstall restores exact module state'

ssh_tunnel_reload() { return 1; }
if ssh_tunnel_apply_policy nobody install >/dev/null 2>&1; then
  fail 'SSH reload failure must fail the policy transaction'
fi
assert_eq "$before_remove_config" "$(sha256sum "$NOBRAND_SSH_CONFIG_MAIN")" \
  'SSH reload failure immediately restores config'
assert_eq "$before_remove_state" "$(sha256sum "$NOBRAND_SSH_STATE_FILE")" \
  'SSH reload failure immediately restores state'

# Early identity-creation failures must not leave an orphan group, Linux user,
# key directory, authorized key, or account marker.
simulated_group="$fixture/simulated-group"
simulated_user="$fixture/simulated-user"
fail_destination=""
_has_group() { [ -s "$simulated_group" ]; }
_has_user() { [ -s "$simulated_user" ] && [ "$(cat "$simulated_user")" = "$1" ]; }
groupadd() { printf '%s\n' 49000 >"$simulated_group"; }
groupdel() { rm -f "$simulated_group"; }
getent() {
  case "${1:-}" in
    group) [ -s "$simulated_group" ] && printf '%s:x:49000:\n' "$NOBRAND_SSH_GROUP" ;;
    *) command getent "$@" ;;
  esac
}
ssh_tunnel_create_linux_user() { printf '%s\n' "$1" >"$simulated_user"; }
ssh_tunnel_delete_linux_user() { rm -f "$simulated_user"; }
id() {
  if [ "${1:-}" = -u ] && [ -s "$simulated_user" ] && [ "$(cat "$simulated_user")" = "${2:-}" ]; then
    printf '%s\n' 49001
  else
    command id "$@"
  fi
}
nb_atomic_install_file() {
  local source="$1" destination="$2" mode="${3:-0600}"
  [ "$destination" != "$fail_destination" ] || return 1
  mkdir -p "$(dirname "$destination")" && install -m "$mode" "$source" "$destination"
}

rm -f "$NOBRAND_SSH_GROUP_MARKER"
fail_destination="$NOBRAND_SSH_GROUP_MARKER"
if ssh_tunnel_create_group; then
  fail 'SSH group marker failure must fail group creation'
fi
[ ! -e "$simulated_group" ] || fail 'SSH group marker failure left an orphan group'
[ ! -e "$NOBRAND_SSH_GROUP_MARKER" ] || fail 'SSH group marker failure left a marker'

fail_destination="$NOBRAND_SSH_STATE_FILE"
if ssh_tunnel_add_user_internal transaction-user >/dev/null 2>&1; then
  fail 'SSH state commit failure must fail user creation'
fi
[ ! -e "$simulated_user" ] || fail 'SSH state commit failure left an orphan Linux user'
[ -z "$(find "$NOBRAND_SSH_KEYS_DIR" -mindepth 1 -maxdepth 1 -print -quit)" ] \
  || fail 'SSH state commit failure left private-key material'
[ -z "$(find "$NOBRAND_SSH_AUTHORIZED_KEYS_DIR" -mindepth 1 -maxdepth 1 -type f -print -quit)" ] \
  || fail 'SSH state commit failure left an authorized key'
[ -z "$(find "$NOBRAND_SSH_ACCOUNT_MARKER_DIR" -mindepth 1 -maxdepth 1 -type f \
  ! -name .group.json -print -quit)" ] || fail 'SSH state commit failure left an account marker'

pass 'SSH policy watchdog, two-phase uninstall, and identity/apply rollback transactions'
