#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/testlib.sh"
fixture="$(mktemp -d)"
trap 'rm -rf -- "$fixture"' EXIT
export NOBRAND_STATE_DIR="$fixture/state"
export NOBRAND_CONFIG_DIR="$fixture/config"
export NOBRAND_LIB_DIR="$fixture/lib"
source_installer
read_tty() { printf -v "$1" 0; }
for menu in nobrand_menu_loop snell_menu_loop hysteria2_menu_loop tuic_menu_loop vless_reality_menu_loop vless_sudoku_menu_loop ssh_tunnel_menu_loop forward_menu_loop ingress_menu_loop; do
  text="$($menu)"
  if [ "$menu" = nobrand_menu_loop ]; then
    assert_contains "$text" '退出' "localized $menu navigation"
  else
    assert_contains "$text" '返回' "localized $menu navigation"
  fi
done
text="$(snell_menu_set_quic)"
assert_contains "$text" '不支持' 'unsupported capability message'
assert_contains "$(nb_splicore_legacy_notice 2>&1)" 'No changes were made.' 'required legacy notice'
assert_contains "$(cat "$TEST_ROOT/README.md")" '需要干净安装' 'documented clean install policy'
pass 'current menus, capability messages and clean-install policy text'
