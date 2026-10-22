#!/usr/bin/env bash
set -euo pipefail
PYTHONDONTWRITEBYTECODE=1 python3 "$(dirname "$0")/helpers/test_splicore_cert_lifecycle.py"
