#!/usr/bin/env bash
set -euo pipefail
TEST_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
fixture="$(mktemp -d)"
trap 'rm -rf -- "$fixture"' EXIT
export NOBRAND_STATE_DIR="$fixture/state" NOBRAND_CONFIG_DIR="$fixture/config"
export NOBRAND_LIB_DIR="$fixture/lib" NOBRAND_LIFECYCLE_DIR="$fixture/journal"
export NOBRAND_SYSTEM_ROOT="$fixture/system" NOBRAND_LEGACY_MIERU_STATE_DIR="$fixture/old-mieru"
export TEST_INSTALLER="$TEST_ROOT/install-nobrand.sh"
mkdir -p "$NOBRAND_STATE_DIR/mieru"
printf '%s\n' '{"synthetic":"legacy-must-remain-unchanged"}' >"$NOBRAND_STATE_DIR/mieru/users.json"
for action in install upgrade uninstall nobrand-uninstall nobrand-manager-upgrade nobrand-backup nobrand-doctor nobrand-runtime; do
  before="$(find "$fixture" -type f -exec sha256sum {} + | sort)"
  if TEST_ACTION="$action" bash -c '
    MITA_SOURCE_ONLY=1; source "$TEST_INSTALLER"
    ACTION="$TEST_ACTION"; NOBRAND_RUNTIME_ARGS=(purge)
    nb_lifecycle_lock_acquire() { printf "MUTATION lock\n"; return 99; }
    nobrand_prepare_common() { printf "MUTATION packages\n"; return 99; }
    nb_splicore_call() { printf "MUTATION runtime\n"; return 99; }
    nobrand_install_manager_script() { printf "MUTATION manager\n"; return 99; }
    main
  ' >"$fixture-output" 2>&1; then
    printf '[FAIL] legacy action allowed: %s\n' "$action"; exit 1
  fi
  output="$(cat "$fixture-output")"
  [[ "$output" == *'Legacy NoBrand multi-core installation detected.'* ]]
  [[ "$output" == *'No changes were made.'* ]]
  [[ "$output" != *MUTATION* ]]
  after="$(find "$fixture" -type f -exec sha256sum {} + | sort)"
  [ "$before" = "$after" ]
  [ ! -e "$NOBRAND_LIFECYCLE_DIR" ]
  [ ! -e "$NOBRAND_STATE_DIR/splicore" ]
done
rm -f "$fixture-output"
printf '[PASS] CLI refuses legacy before locks/packages/runtime/backup/uninstall; files unchanged\n'
