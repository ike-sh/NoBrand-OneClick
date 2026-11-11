#!/usr/bin/env bash
set -euo pipefail
TEST_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
PYTHONDONTWRITEBYTECODE=1 python3 "$TEST_ROOT/tests/helpers/test_splicore_sudoku.py" test_canonical_and_client_roundtrip test_sudoku_parameters_fail_closed
