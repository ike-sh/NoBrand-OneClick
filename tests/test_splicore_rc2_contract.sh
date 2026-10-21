#!/usr/bin/env bash
set -euo pipefail

TEST_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
python3 "${TEST_ROOT}/tests/helpers/splicore_rc2_probe.py" --self-test
printf '[PASS] Splicore rc.2 audit safety helpers (not migration acceptance)\n'
