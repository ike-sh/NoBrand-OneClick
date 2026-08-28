#!/usr/bin/env bash
set -euo pipefail

TEST_SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$TEST_SCRIPT_ROOT"

run_runtime=0
case "${1:-}" in
  "") [ "${NOBRAND_RUNTIME_INTEGRATION:-0}" = 1 ] && run_runtime=1 ;;
  --runtime) run_runtime=1 ;;
  *) printf 'usage: %s [--runtime]\n' "$0" >&2; exit 2 ;;
esac

bash scripts/build.sh
for source_file in src/*.sh scripts/*.sh tests/*.sh install-nobrand.sh dist/install-nobrand.sh; do
  bash -n "$source_file"
done
if command -v shellcheck >/dev/null 2>&1; then
  shellcheck -S warning -x scripts/shellcheck-src.sh
  shellcheck -S warning install-nobrand.sh dist/install-nobrand.sh scripts/*.sh tests/*.sh
fi
bash scripts/build.sh --check

unit_tests=(
  tests/test_mieru_parity.sh
  tests/test_architecture_audit.sh
  tests/test_schema_v3.sh
  tests/test_common_port.sh
  tests/test_endpoint_isolation.sh
  tests/test_mieru_endpoint_isolation.sh
  tests/test_hy2_golden.sh
  tests/test_hy2_certificate.sh
  tests/test_vless_sudoku_golden.sh
  tests/test_vless_sudoku_encryption_absence.sh
  tests/test_vless_sudoku_lifecycle.sh
  tests/test_snell.sh
  tests/test_snell_quic.sh
  tests/test_nodes.sh
  tests/test_backup_boundary.sh
  tests/test_mieru_uninstall_boundary.sh
  tests/test_uninstall_boundary.sh
  tests/test_rollback.sh
  tests/test_cli.sh
  tests/test_menu.sh
)
for test_file in "${unit_tests[@]}"; do
  bash "$test_file"
done

if [ "$run_runtime" -eq 1 ]; then
  bash tests/test_runtime_integration.sh
else
  printf '[SKIP] real runtime integration (run scripts/test.sh --runtime)\n'
fi

printf '[PASS] NoBrand test suite\n'
