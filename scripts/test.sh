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
  tests/test_mieru_latest_stable.sh
  tests/test_mieru_parity.sh
  tests/test_architecture_audit.sh
  tests/test_repository_sanitization.sh
  tests/test_schema_v3.sh
  tests/test_common_port.sh
  tests/test_ingress_profiles.sh
  tests/test_ingress_enforcement.sh
  tests/test_ingress_enforcement_transaction.sh
  tests/test_forward.sh
  tests/test_forward_transaction.sh
  tests/test_forward_sysctl.sh
  tests/test_forward_ownership.sh
  tests/test_tuic_v5.sh
  tests/test_tuic_transaction.sh
  tests/test_vless_reality.sh
  tests/test_vless_reality_transaction.sh
  tests/test_ssh_tunnel.sh
  tests/test_ssh_tunnel_transaction.sh
  tests/test_upgrade_3_0_3_1.sh
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
  tests/test_sensitive_output.sh
  tests/test_backup_boundary.sh
  tests/test_backup_restore_transaction.sh
  tests/test_mieru_uninstall_boundary.sh
  tests/test_uninstall_boundary.sh
  tests/test_rollback.sh
  tests/test_cli.sh
  tests/test_menu.sh
  tests/test_lifecycle_recovery.sh
  tests/test_localization.sh
)
for test_file in "${unit_tests[@]}"; do
  bash "$test_file"
done

if [ "$run_runtime" -eq 1 ]; then
  runtime_tests=(
    tests/test_runtime_integration.sh
    tests/test_mieru_latest_stable_runtime.sh
    tests/test_vless_reality_runtime.sh
    tests/test_tuic_runtime.sh
    tests/test_ssh_runtime.sh
    tests/test_forward_realm_runtime.sh
    tests/test_forward_nft_runtime.sh
    tests/test_forward_backend_switch_runtime.sh
    tests/test_ingress_enforcement_runtime.sh
  )
  for test_file in "${runtime_tests[@]}"; do
    bash "$test_file"
  done
else
  printf '[SKIP] real runtime integration (run scripts/test.sh --runtime)\n'
fi

printf '[PASS] NoBrand test suite\n'
