#!/usr/bin/env bash
set -euo pipefail
TEST_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
export PYTHONDONTWRITEBYTECODE=1
python3 "$TEST_ROOT/tests/helpers/test_splicore_fresh.py"
printf '[PASS] Splicore v0.5.0 fresh architecture, legacy refusal and native guard policy\n'
