#!/usr/bin/env bash
set -euo pipefail
TEST_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
PYTHONDONTWRITEBYTECODE=1 python3 "$TEST_ROOT/tests/helpers/test_splicore_sudoku.py" test_no_fake_encryption_or_xray_server test_legacy_upgrade_preserves_plain_mode
