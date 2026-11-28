#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/testlib.sh"

source_installer
assert_eq 4.3.0 "$SCRIPT_VERSION" 'authoritative release target'
assert_eq 'NoBrand-OneClick 4.3.0' \
  "$(bash "$TEST_ROOT/install-nobrand.sh" --version | head -n1)" 'installer version'
assert_eq 'NoBrand-OneClick 4.3.0' \
  "$(bash "$TEST_ROOT/dist/install-nobrand.sh" --version | head -n1)" 'dist version'
assert_contains "$(bash "$TEST_ROOT/install-nobrand.sh" --help)" \
  'NoBrand-OneClick 4.3.0' 'help banner version'
assert_contains "$(<"$TEST_ROOT/README.md")" \
  "当前稳定版本：[v${SCRIPT_VERSION}](https://github.com/${SCRIPT_REPO}/releases/tag/v${SCRIPT_VERSION})" 'README release version and tag URL'
for asset in install-nobrand.sh SHA256SUMS; do
  assert_contains "$(<"$TEST_ROOT/README.md")" \
    "https://github.com/${SCRIPT_REPO}/releases/download/v${SCRIPT_VERSION}/${asset}" "README published $asset release URL"
done
grep -Eq "^## ${SCRIPT_VERSION//./\\.} - [0-9]{4}-[0-9]{2}-[0-9]{2}$" "$TEST_ROOT/CHANGELOG.md" \
  || fail 'CHANGELOG missing dated release heading'
cmp -s "$TEST_ROOT/install-nobrand.sh" "$TEST_ROOT/dist/install-nobrand.sh" \
  || fail 'installer and dist differ'
if grep -R -n -E 'v?3\.2\.[5]' "$TEST_ROOT/src" "$TEST_ROOT/scripts" \
  "$TEST_ROOT/tests" "$TEST_ROOT/README.md" "$TEST_ROOT/CHANGELOG.md" \
  "$TEST_ROOT/install-nobrand.sh" "$TEST_ROOT/dist/install-nobrand.sh"; then
  fail 'unpublished candidate appears in current product sources'
fi
pass '4.3.0 source, installers, help, published README URLs and dated CHANGELOG match'
