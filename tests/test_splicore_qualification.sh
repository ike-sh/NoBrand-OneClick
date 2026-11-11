#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
PYTHONDONTWRITEBYTECODE=1 python3 "$root/tests/helpers/run_historical_qualification.py"
PYTHONDONTWRITEBYTECODE=1 python3 "$root/tests/helpers/test_root_fixture.py"
PYTHONDONTWRITEBYTECODE=1 python3 "$root/tests/helpers/test_splicore_v050_qualification.py"
