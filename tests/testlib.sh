#!/usr/bin/env bash
set -euo pipefail

TEST_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

fail() {
  printf '[FAIL] %s\n' "$*" >&2
  exit 1
}

assert_eq() {
  local expected="$1" actual="$2" label="${3:-value}"
  [ "$expected" = "$actual" ] || fail "${label}: expected '${expected}', got '${actual}'"
}

assert_contains() {
  local haystack="$1" needle="$2" label="${3:-text}"
  case "$haystack" in *"$needle"*) ;; *) fail "${label}: missing '${needle}'" ;; esac
}

assert_not_contains() {
  local haystack="$1" needle="$2" label="${3:-text}"
  case "$haystack" in *"$needle"*) fail "${label}: unexpectedly contains '${needle}'" ;; *) ;; esac
}

assert_file_mode() {
  local expected="$1" path="$2" actual
  actual="$(stat -c '%a' "$path")"
  assert_eq "$expected" "$actual" "mode $path"
}

pass() {
  printf '[PASS] %s\n' "$*"
}

source_installer() {
  set --
  MITA_SOURCE_ONLY=1
  # shellcheck disable=SC1090
  source "${TEST_ROOT}/install-nobrand.sh"
  trap - ERR
}
