#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/testlib.sh"

source_installer
assert_eq 3.2.6 "$SCRIPT_VERSION" 'authoritative release target'
assert_eq 'NoBrand-OneClick 3.2.6' \
  "$(bash "$TEST_ROOT/install-nobrand.sh" --version | head -n1)" 'installer version'
assert_eq 'NoBrand-OneClick 3.2.6' \
  "$(bash "$TEST_ROOT/dist/install-nobrand.sh" --version | head -n1)" 'dist version'
assert_contains "$(bash "$TEST_ROOT/install-nobrand.sh" --help)" \
  'NoBrand-OneClick 3.2.6' 'help banner version'
assert_contains "$(<"$TEST_ROOT/README.md")" \
  '当前稳定版本：[v3.2.6]' 'README release version'
cmp -s "$TEST_ROOT/install-nobrand.sh" "$TEST_ROOT/dist/install-nobrand.sh" \
  || fail 'installer and dist differ'
if grep -R -n -E 'v?3\.2\.[5]' "$TEST_ROOT/src" "$TEST_ROOT/scripts" \
  "$TEST_ROOT/tests" "$TEST_ROOT/README.md" "$TEST_ROOT/CHANGELOG.md" \
  "$TEST_ROOT/install-nobrand.sh" "$TEST_ROOT/dist/install-nobrand.sh"; then
  fail 'unpublished candidate appears in current product sources'
fi
pass '3.2.6 source, installer, dist, help, README and no unpublished version references'
