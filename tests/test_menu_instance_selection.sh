#!/usr/bin/env bash
# Native selector fixture globals are consumed by sourced UI functions.
# shellcheck disable=SC2034
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/testlib.sh"
fixture="$(mktemp -d)"
trap 'rm -rf -- "$fixture"' EXIT
export NOBRAND_STATE_DIR="$fixture/state"
export NOBRAND_CONFIG_DIR="$fixture/config"
export NOBRAND_LIB_DIR="$fixture/lib"
export NOBRAND_LIFECYCLE_DIR="$fixture/journal"
export NOBRAND_LIFECYCLE_LOCK_FILE="$fixture/run/lock"
source_installer
mkdir -p "$NOBRAND_STATE_DIR/splicore/generations/test"
ln -s generations/test "$NOBRAND_STATE_DIR/splicore/current"
path="$NOBRAND_STATE_DIR/splicore/current/desired.json"
printf '%s\n' '{"nodes":[{"id":"a","client":{"name":"one"}},{"id":"b","client":{"name":"two"}}]}' >"$path"
nb_splicore_call() { printf '%s\n' '{"nodes":[{"id":"a","name":"one","listener":{"port":31001}},{"id":"b","name":"two","listener":{"port":31002}}]}'; }
reply=two
read_tty() { printf -v "$1" '%s' "$reply"; }
nb_splicore_menu_select tuic >/dev/null
assert_eq two "$TUIC_NAME" 'selector name'
assert_eq b "$NOBRAND_MENU_SELECTION_ID" 'selector ID'
assert_eq 31002 "$NOBRAND_SPLICORE_MENU_PORT" 'selected port'
nobrand_menu_selection_current || fail 'valid selection failed'
printf '\n' >>"$path"
if nobrand_menu_selection_current; then fail 'modified desired state reused selection'; fi
reply=''; if nb_splicore_menu_select tuic >/dev/null; then fail 'ambiguous default selected'; fi
reply=unknown; if nb_splicore_menu_select tuic >/dev/null; then fail 'unknown name selected'; fi
pass 'native instance selection rejects ambiguity and stale state'
