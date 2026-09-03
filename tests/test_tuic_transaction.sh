#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/testlib.sh"

fixture="$(mktemp -d)"
trap 'rm -rf -- "$fixture"' EXIT
export NOBRAND_STATE_DIR="$fixture/nobrand-oneclick/state"
export NOBRAND_CONFIG_DIR="$fixture/nobrand-oneclick/config"
export NOBRAND_LIB_DIR="$fixture/nobrand-oneclick/lib"
source_installer
# Exercise the live source fragment without rebuilding the generated installer.
# shellcheck source=../src/24-platform-tuic.sh
source "$TEST_ROOT/src/24-platform-tuic.sh"
nb_init_state_layout

# These globals deliberately override the sourced product functions during
# failure injection. Exporting documents that cross-function test boundary to
# ShellCheck without changing product behavior.
export TUIC_CHANNEL TUIC_VERSION TUIC_RUNTIME_RESOLVED_VERSION \
  TUIC_RUNTIME_RESOLVED_URL TUIC_RUNTIME_RESOLVED_SHA256 TUIC_RUNTIME_RESOLVED_ASSET

make_runtime() {
  local path="$1" version="$2"
  cat >"$path" <<EOF
#!/usr/bin/env bash
case "\${1:-}" in
  version) printf '%s\n' 'sing-box version ${version}' ;;
  check) exit 0 ;;
  *) exit 0 ;;
esac
EOF
  chmod 0755 "$path"
}

mkdir -p "$NOBRAND_BIN_DIR" "$(dirname "$NOBRAND_SING_BOX_RUNTIME_META")"
make_runtime "$NOBRAND_SING_BOX_BIN" 1.0.0
printf '%s\n' '{"ownership":"nobrand-v3","consumer":"tuic-v5","version":"1.0.0","channel":"pinned","asset":"fixture","source_url":"fixture","sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","installed_at":"2026-08-30T00:00:00Z"}' \
  >"$NOBRAND_SING_BOX_RUNTIME_META"
chmod 0600 "$NOBRAND_SING_BOX_RUNTIME_META"

create_instance() {
  local id="$1" name="$2" port="$3" uuid="$4" password="$5" user_id="$6"
  local state config cert key users
  state="$(tuic_state_file "$id")"
  config="$(tuic_config_file "$id")"
  cert="$(tuic_cert_file "$id")"
  key="$(tuic_key_file "$id")"
  users="[$(tuic_user_json "$user_id" alice "$uuid" "$password" 2026-08-30T00:00:00Z)]"
  mkdir -p "$(dirname "$state")" "$(dirname "$config")"
  printf '%s\n' 'fixture-cert' >"$cert"
  printf '%s\n' 'fixture-key' >"$key"
  tuic_generate_server_config "$config" "$id" 0.0.0.0 "$port" "$cert" "$key" example.test "$users"
  tuic_generate_state "$state" "$id" "$name" 0.0.0.0 "$port" custom entry.example.test "$port" \
    example.test pinned 1.0.0 "$cert" "$key" "$users" 2026-08-30T00:00:00Z
}

id_a=t1111111111111111
id_b=t2222222222222222
create_instance "$id_a" primary 3611 11111111-1111-4111-8111-111111111111 alice-secret u1111111111111111
create_instance "$id_b" secondary 3612 22222222-2222-4222-8222-222222222222 bob-secret u2222222222222222

MOCK_NEW_VERSION=2.0.0
tuic_download_runtime_candidate() {
  local output="$1"
  make_runtime "$output" "$MOCK_NEW_VERSION"
  TUIC_RUNTIME_RESOLVED_VERSION="$MOCK_NEW_VERSION"
  TUIC_RUNTIME_RESOLVED_URL="https://example.test/sing-box-${MOCK_NEW_VERSION}.tar.gz"
  TUIC_RUNTIME_RESOLVED_SHA256=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
  TUIC_RUNTIME_RESOLVED_ASSET="sing-box-${MOCK_NEW_VERSION}-linux-amd64.tar.gz"
}
tuic_validate_config() { "$2" check -c "$1" >/dev/null; }
admin_lock_acquire() { return 0; }
admin_lock_release() { return 0; }
tuic_service_active() { return 0; }
nb_wait_for_listener() { return 0; }
tuic_listener_owned_by_service() { return 0; }
restart_log="$fixture/restarts.log"
: >"$restart_log"
FAIL_SECOND=1
tuic_service_action() {
  local id="$1" action="$2" current
  [ "$action" = restart ] || return 0
  current="$(tuic_runtime_version 2>/dev/null || true)"
  printf '%s|%s\n' "$id" "$current" >>"$restart_log"
  if [ "$FAIL_SECOND" -eq 1 ] && [ "$id" = "$id_b" ] && [ "$current" = "$MOCK_NEW_VERSION" ]; then
    return 1
  fi
}

TUIC_CHANNEL=pinned
TUIC_VERSION="$MOCK_NEW_VERSION"
old_binary_hash="$(sha256sum "$NOBRAND_SING_BOX_BIN")"
old_metadata_hash="$(sha256sum "$NOBRAND_SING_BOX_RUNTIME_META")"
old_state_a_hash="$(sha256sum "$(tuic_state_file "$id_a")")"
old_state_b_hash="$(sha256sum "$(tuic_state_file "$id_b")")"
if tuic_upgrade_runtime; then
  fail 'TUIC multi-instance restart failure must fail the runtime upgrade'
fi
assert_eq "$old_binary_hash" "$(sha256sum "$NOBRAND_SING_BOX_BIN")" \
  'TUIC runtime failure restores old binary'
assert_eq "$old_metadata_hash" "$(sha256sum "$NOBRAND_SING_BOX_RUNTIME_META")" \
  'TUIC runtime failure restores metadata'
assert_eq "$old_state_a_hash" "$(sha256sum "$(tuic_state_file "$id_a")")" \
  'TUIC runtime failure restores first state'
assert_eq "$old_state_b_hash" "$(sha256sum "$(tuic_state_file "$id_b")")" \
  'TUIC runtime failure restores second state'
assert_contains "$(cat "$restart_log")" "$id_a|1.0.0" \
  'TUIC rollback restarts first active instance on old runtime'
assert_contains "$(cat "$restart_log")" "$id_b|1.0.0" \
  'TUIC rollback restarts second active instance on old runtime'

FAIL_SECOND=0
: >"$restart_log"
tuic_upgrade_runtime
assert_eq 2.0.0 "$(tuic_runtime_version)" 'TUIC successful shared runtime upgrade'
assert_eq 2.0.0 "$(tuic_state_field "$id_a" runtime_version)" \
  'TUIC successful upgrade updates first state'
assert_eq 2.0.0 "$(tuic_state_field "$id_b" runtime_version)" \
  'TUIC successful upgrade updates second state'
assert_eq pinned "$(jq -r .channel "$NOBRAND_SING_BOX_RUNTIME_META")" \
  'TUIC successful upgrade commits runtime metadata'

MOCK_NEW_VERSION=3.0.0
TUIC_VERSION="$MOCK_NEW_VERSION"
before_state_failure_binary="$(sha256sum "$NOBRAND_SING_BOX_BIN")"
before_state_failure_meta="$(sha256sum "$NOBRAND_SING_BOX_RUNTIME_META")"
before_state_failure_a="$(sha256sum "$(tuic_state_file "$id_a")")"
before_state_failure_b="$(sha256sum "$(tuic_state_file "$id_b")")"
eval "$(declare -f nb_atomic_install_file | sed '1s/nb_atomic_install_file/original_nb_atomic_install_file/')"
FAIL_STATE_ONCE=1
nb_atomic_install_file() {
  local source="$1" target="$2" mode="$3"
  if [ "$FAIL_STATE_ONCE" -eq 1 ] && [ "$target" = "$(tuic_state_file "$id_b")" ] \
     && grep -q '3.0.0' "$source" 2>/dev/null; then
    FAIL_STATE_ONCE=0
    return 1
  fi
  original_nb_atomic_install_file "$source" "$target" "$mode"
}
if tuic_upgrade_runtime; then
  fail 'TUIC state commit failure must fail the runtime upgrade'
fi
assert_eq "$before_state_failure_binary" "$(sha256sum "$NOBRAND_SING_BOX_BIN")" \
  'TUIC state failure restores previous binary'
assert_eq "$before_state_failure_meta" "$(sha256sum "$NOBRAND_SING_BOX_RUNTIME_META")" \
  'TUIC state failure restores previous metadata'
assert_eq "$before_state_failure_a" "$(sha256sum "$(tuic_state_file "$id_a")")" \
  'TUIC state failure restores first state'
assert_eq "$before_state_failure_b" "$(sha256sum "$(tuic_state_file "$id_b")")" \
  'TUIC state failure restores second state'

run_tuic_install_failure_case() (
  set -euo pipefail
  local case_mode="$1" case_fixture
  case_fixture="$(mktemp -d)"
  trap 'rm -rf -- "$case_fixture"' EXIT
  NOBRAND_STATE_DIR="$case_fixture/nobrand-oneclick/state"
  NOBRAND_CONFIG_DIR="$case_fixture/nobrand-oneclick/config"
  NOBRAND_LIB_DIR="$case_fixture/nobrand-oneclick/lib"
  NOBRAND_TUIC_STATE_DIR="$NOBRAND_STATE_DIR/tuic/instances"
  NOBRAND_TUIC_CONFIG_DIR="$NOBRAND_CONFIG_DIR/tuic/instances"
  NOBRAND_BIN_DIR="$NOBRAND_LIB_DIR/bin"
  NOBRAND_SING_BOX_BIN="$NOBRAND_BIN_DIR/sing-box"
  NOBRAND_SING_BOX_RUNTIME_META="$NOBRAND_STATE_DIR/tuic/runtime.json"
  export NOBRAND_TUIC_SYSTEMD_TEMPLATE="$case_fixture/systemd/nobrand-tuic@.service"
  NOBRAND_FIREWALL_OWNED_STATE="$NOBRAND_STATE_DIR/firewall-owned.bindings"
  source_installer
  nb_init_state_layout

  tuic_collect_install_requests() {
    export PORT=24445
    export TUIC_NAME="failure-${case_mode}"
    export TUIC_USER=alice
    export TUIC_SNI=example.test
    export TUIC_CHANNEL=stable
    export TUIC_VERSION=""
    export ADVERTISE_HOST=entry.example.test
    export ADVERTISE_PORT=24445
  }
  nobrand_prepare_common() { :; }
  admin_lock_acquire() { :; }
  admin_lock_release() { :; }
  nb_port_available_for_transport() { :; }
  nb_service_manager() { printf none; }
  tuic_download_runtime_candidate() {
    local output="$1"
    [ "$case_mode" != download-failure ] || return 1
    make_runtime "$output" 9.0.0
    TUIC_RUNTIME_RESOLVED_VERSION=9.0.0
    TUIC_RUNTIME_RESOLVED_URL=https://example.test/sing-box-9.0.0.tar.gz
    TUIC_RUNTIME_RESOLVED_SHA256=cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
    TUIC_RUNTIME_RESOLVED_ASSET=sing-box-9.0.0-linux-amd64.tar.gz
  }
  tuic_validate_config() { [ "$case_mode" != config-failure ]; }
  tuic_install_service_runtime() { :; }
  tuic_ensure_openrc_service() { :; }
  nb_firewall_open_pairs() {
    [ "$case_mode" != firewall-failure ] || return 1
    printf '%s\n' 'iptables|udp|24445' >"$NOBRAND_FIREWALL_OWNED_STATE"
  }
  nb_firewall_close_pairs() { rm -f "$NOBRAND_FIREWALL_OWNED_STATE"; }
  service_marker="$case_fixture/service-active"
  tuic_service_action() {
    local _id="$1" action="$2"
    case "$action" in
      start)
        [ "$case_mode" != service-failure ] || return 1
        : >"$service_marker"
        ;;
      stop) rm -f "$service_marker" ;;
    esac
  }
  tuic_remove_service() { rm -f "$service_marker"; }
  nb_wait_for_listener() { :; }
  tuic_listener_owned_by_service() { :; }
  nobrand_install_manager_script() { :; }
  tuic_show_user() { :; }
  eval "$(declare -f nb_atomic_install_file | sed '1s/nb_atomic_install_file/original_install_atomic/')"
  nb_atomic_install_file() {
    local source="$1" destination="$2" mode="$3"
    if [ "$case_mode" = state-failure ] \
       && [[ "$destination" = "$NOBRAND_TUIC_STATE_DIR"/*/state.json ]]; then
      return 1
    fi
    original_install_atomic "$source" "$destination" "$mode"
  }

  if ( install_tuic >/dev/null 2>&1 ); then
    fail "TUIC ${case_mode} unexpectedly succeeded"
  fi
  [ -z "$(tuic_instance_ids)" ] || fail "TUIC ${case_mode} left instance state"
  [ -z "$(find "$NOBRAND_TUIC_CONFIG_DIR" -type f -print -quit)" ] \
    || fail "TUIC ${case_mode} left config/certificate material"
  [ ! -e "$NOBRAND_SING_BOX_BIN" ] || fail "TUIC ${case_mode} left managed runtime"
  [ ! -e "$NOBRAND_SING_BOX_RUNTIME_META" ] || fail "TUIC ${case_mode} left runtime metadata"
  [ ! -e "$NOBRAND_FIREWALL_OWNED_STATE" ] || fail "TUIC ${case_mode} left firewall ownership"
  [ ! -e "$service_marker" ] || fail "TUIC ${case_mode} left a service"
)

for failure_mode in download-failure config-failure state-failure firewall-failure service-failure; do
  run_tuic_install_failure_case "$failure_mode"
done

# Snapshot helpers run below callers' `if`/`||` guards, where Bash suppresses
# errexit for the whole call chain. Every snapshot write and removal therefore
# has to return explicitly instead of relying on a later command not masking it.
run_tuic_snapshot_failure_regressions() (
  set -euo pipefail
  local case_fixture snapshot
  case_fixture="$(mktemp -d)"
  trap 'rm -rf -- "$case_fixture"' EXIT
  NOBRAND_SING_BOX_BIN="$case_fixture/live/sing-box"
  NOBRAND_SING_BOX_RUNTIME_META="$case_fixture/live/runtime.json"
  mkdir -p "$(dirname "$NOBRAND_SING_BOX_BIN")"
  printf '%s\n' runtime >"$NOBRAND_SING_BOX_BIN"
  printf '%s\n' metadata >"$NOBRAND_SING_BOX_RUNTIME_META"

  snapshot="$case_fixture/copy-failure"
  cp() {
    local arg
    for arg in "$@"; do
      [ "$arg" != "$NOBRAND_SING_BOX_BIN" ] || return 71
    done
    command cp "$@"
  }
  if tuic_snapshot_runtime_files "$snapshot" 2>/dev/null; then
    fail 'TUIC runtime snapshot masked a binary copy failure'
  fi
  unset -f cp

  NOBRAND_SING_BOX_BIN="$case_fixture/live/missing-sing-box"
  snapshot="$case_fixture/marker-failure"
  mkdir -p "$snapshot/binary.absent"
  if tuic_snapshot_runtime_files "$snapshot" 2>/dev/null; then
    fail 'TUIC runtime snapshot masked an absent-marker write failure'
  fi

  NOBRAND_SING_BOX_BIN="$case_fixture/live/sing-box"
  snapshot="$case_fixture/remove-failure"
  mkdir -p "$snapshot"
  : >"$snapshot/binary.absent"
  command cp "$NOBRAND_SING_BOX_RUNTIME_META" "$snapshot/metadata"
  rm() {
    local arg
    for arg in "$@"; do
      [ "$arg" != "$NOBRAND_SING_BOX_BIN" ] || return 72
    done
    command rm "$@"
  }
  if tuic_restore_runtime_files "$snapshot" 2>/dev/null; then
    fail 'TUIC runtime restore masked a binary removal failure'
  fi
)
run_tuic_snapshot_failure_regressions

pass 'TUIC install/upgrade runtime, state, config, firewall, and service rollback transactions'
