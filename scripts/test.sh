#!/usr/bin/env bash
set -euo pipefail

if [ "$(id -u)" -ne 0 ] && [ "${NOBRAND_TEST_USER_NAMESPACE:-0}" != 1 ]; then
  if command -v unshare >/dev/null 2>&1 && unshare --user --map-root-user true 2>/dev/null; then
    exec env NOBRAND_TEST_USER_NAMESPACE=1 unshare --user --map-root-user bash "$0" "$@"
  fi
fi

TEST_SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$TEST_SCRIPT_ROOT"

# Service discovery must inspect the fixture host, not unrelated development
# machine units. All state/config roots remain controlled by individual tests.
test_system_root="$(mktemp -d)"
trap 'rm -rf -- "$test_system_root"' EXIT
export NOBRAND_SYSTEM_ROOT="$test_system_root"

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
printf '[PASS] Bash syntax: sources, scripts, all test files and both installers\n'
if command -v shellcheck >/dev/null 2>&1; then
  shellcheck -S warning -x scripts/shellcheck-src.sh
  for shellcheck_file in install-nobrand.sh dist/install-nobrand.sh scripts/*.sh tests/*.sh; do
    shellcheck -S warning "$shellcheck_file"
  done
  printf '[PASS] ShellCheck: source model, both installers, scripts and all test files\n'
else
  printf '[SKIP] ShellCheck is unavailable\n'
fi
bash scripts/build.sh --check
printf '[PASS] Generated installers match current source and embedded runtime\n'

# Current native acceptance only; retired legacy fixtures and replacement
# coverage are documented in docs/SPLICORE-RC4-TEST-CONTRACT.md.
unit_tests=(
  tests/test_splicore_runtime.sh
  tests/test_splicore_legacy_refusal.sh
  tests/test_splicore_fresh.sh
  tests/test_splicore_cert_lifecycle.sh
  tests/test_splicore_shell_surface.sh
  tests/test_splicore_rc4_contract.sh
  tests/test_splicore_qualification.sh
  tests/test_architecture_audit.sh
  tests/test_repository_sanitization.sh
  tests/test_schema_v3.sh
  tests/test_common_port.sh
  tests/test_ingress_profiles.sh
  tests/test_ingress_interactive.sh
  tests/test_ingress_enforcement.sh
  tests/test_ingress_enforcement_transaction.sh
  tests/test_forward.sh
  tests/test_forward_transaction.sh
  tests/test_forward_sysctl.sh
  tests/test_forward_ownership.sh
  tests/test_ssh_tunnel.sh
  tests/test_ssh_tunnel_transaction.sh
  tests/test_vless_sudoku_golden.sh
  tests/test_vless_sudoku_encryption_absence.sh
  tests/test_vless_sudoku_lifecycle.sh
  tests/test_cli.sh
  tests/test_menu.sh
  tests/test_menu_lifecycle_lock_scope.sh
  tests/test_menu_instance_selection.sh
  tests/test_version_consistency.sh
  tests/test_localization.sh
)

for test_file in "${unit_tests[@]}"; do
  printf '[RUN] %s\n' "$test_file"
  bash "$test_file"
done

if [ "$run_runtime" -eq 1 ]; then
  : "${NOBRAND_SPLICORE_PUBLIC_ARTIFACTS:?set the directory containing public rc.4 archives and SHA256SUMS}"
  : "${NOBRAND_REFERENCE_MIHOMO_GZIP:?set the pinned reference client gzip path}"
  runtime_evidence="${NOBRAND_RUNTIME_EVIDENCE_DIR:-$(mktemp -d)}"
  mkdir -p "$runtime_evidence"
  PYTHONDONTWRITEBYTECODE=1 python3 tests/helpers/splicore_rc4_probe.py \
    --artifacts "$NOBRAND_SPLICORE_PUBLIC_ARTIFACTS" --mihomo-gzip "$NOBRAND_REFERENCE_MIHOMO_GZIP" \
    --private-log "$runtime_evidence/private-runtime.log" --output "$runtime_evidence/runtime-probe.json"

else
  printf '[SKIP] real runtime integration (run scripts/test.sh --runtime)\n'
fi

printf '[PASS] NoBrand test suite\n'
