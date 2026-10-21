#!/usr/bin/env bash
set -euo pipefail
TEST_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
export PYTHONDONTWRITEBYTECODE=1
runtime_system_root="$(mktemp -d)"
trap 'rm -rf -- "$runtime_system_root"' EXIT
export NOBRAND_SYSTEM_ROOT="$runtime_system_root"
python3 "$TEST_ROOT/tests/helpers/test_splicore_runtime.py"
# Copy the distribution alone: embedded Python/manifest must work without src/.
source "$TEST_ROOT/tests/testlib.sh"
workspace="$(mktemp -d)"
trap 'rm -rf -- "$workspace" "$runtime_system_root"' EXIT
cp "$TEST_ROOT/dist/install-nobrand.sh" "$workspace/installer.sh"
output="$(bash "$workspace/installer.sh" runtime capabilities)"
assert_contains "$output" 'v0.3.0-rc.4' 'standalone public pin'
assert_contains "$output" 'requires_external_xray' 'explicit specialized boundary'
source_installer
nb_splicore_protocol() { printf 'primary:%s:%s\n' "$1" "$2"; }
nb_lifecycle_tx_valid() { return 1; }
repair_mita_binary_paths() { fail 'unexpected legacy repair'; }
download_package() { fail 'unexpected Mita download'; }
nobrand_install_xray_runtime() { fail 'unexpected ordinary Xray download'; }
tuic_install_runtime() { fail 'unexpected sing-box download'; }
snell_install_runtime() { fail 'unexpected old Snell download'; }
for route in nobrand-snell nobrand-tuic nobrand-hy2 nobrand-vless-reality install upgrade user-add; do
  # Read by the dynamically sourced dispatcher.
  # shellcheck disable=SC2034
  ACTION="$route" SNELL_ACTION=install TUIC_ACTION=install HY2_ACTION=install VLESS_REALITY_ACTION=install
  output="$(nb_splicore_route_main)"
  assert_contains "$output" 'primary:' "primary route $route"
done
printf '[PASS] Splicore runtime transaction and service fixtures\n'
