#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/testlib.sh"

fixture="$(mktemp -d)"
trap 'rm -rf -- "$fixture"' EXIT
export NOBRAND_STATE_DIR="$fixture/nobrand-oneclick/state"
export NOBRAND_CONFIG_DIR="$fixture/nobrand-oneclick/config"
export NOBRAND_LIB_DIR="$fixture/nobrand-oneclick/lib"
export LANG_ZH=1
source_installer
# Keep this focused test tied to the maintained source modules even before the
# generated installer is rebuilt by the full suite.
# shellcheck disable=SC1091
source "$TEST_ROOT/src/16-core-ingress.sh"
# shellcheck disable=SC1091
source "$TEST_ROOT/src/90-ui.sh"
trap - ERR

input_index=0
inputs=()
set_inputs() { inputs=("$@"); input_index=0; }
read_tty() {
  local destination="$1" prompt="${2:-}"
  printf '%s' "$prompt"
  [ "$input_index" -lt "${#inputs[@]}" ] || return 1
  printf -v "$destination" '%s' "${inputs[$input_index]}"
  input_index=$((input_index + 1))
}
menu_pause() { :; }
nobrand_print_banner() { msg 'NoBrand-OneClick 中文菜单'; }
mita_installed() { return 1; }
load_install_state() { :; }

capture_loop() {
  local menu_function="$1"
  set_inputs 0
  "$menu_function"
}
capture_mieru_menu() {
  local rc=0
  set_inputs 0
  show_menu || rc=$?
  [ "$rc" -eq 2 ]
}

main_output="$(capture_loop nobrand_menu_loop)"
mieru_output="$(capture_mieru_menu)"
snell_output="$(capture_loop snell_menu_loop)"
hy2_output="$(capture_loop hysteria2_menu_loop)"
tuic_output="$(capture_loop tuic_menu_loop)"
reality_output="$(capture_loop vless_reality_menu_loop)"
sudoku_output="$(capture_loop vless_sudoku_menu_loop)"
ssh_output="$(capture_loop ssh_tunnel_menu_loop)"
forward_output="$(capture_loop forward_menu_loop)"
ingress_output="$(capture_loop ingress_menu_loop)"
backup_output="$(capture_loop nobrand_backup_menu_loop)"

assert_contains "$main_output" '端口转发 / Port Forward' 'Chinese-first main Forward label'
assert_contains "$main_output" '查看全部节点' 'Chinese-first main nodes label'
assert_contains "$main_output" 'Doctor / 诊断' 'Chinese-first main Doctor label'
assert_contains "$mieru_output" '状态: 未安装' 'Chinese-first Mieru status'
assert_contains "$mieru_output" '新装 / 安装' 'Chinese-first Mieru install action'
assert_contains "$snell_output" '安装 Snell v5 [推荐]' 'Chinese-first Snell menu'
assert_contains "$snell_output" '删除节点' 'Chinese-first Snell delete action'
assert_contains "$hy2_output" '安装 / 重新部署' 'Chinese-first HY2 menu'
assert_contains "$hy2_output" '删除 Hysteria2' 'Chinese-first HY2 delete action'
assert_contains "$tuic_output" '安装 TUIC v5 实例' 'Chinese-first TUIC menu'
assert_contains "$tuic_output" '用户管理（列出 / 添加 / 删除 / 轮换凭据）' 'Chinese-first TUIC user action'
assert_contains "$reality_output" '安装新实例' 'Chinese-first REALITY menu'
assert_contains "$reality_output" 'Public Ingress：推荐' 'REALITY Ingress guidance'
assert_contains "$sudoku_output" 'VLESS Encryption：未使用（NOT USED）' 'Chinese-first Sudoku notice'
assert_contains "$sudoku_output" '配置冒烟测试 / Smoke' 'Chinese-first Sudoku smoke action'
assert_contains "$ssh_output" '现有 OpenSSH' 'Chinese-first SSH menu'
assert_contains "$ssh_output" '显式导出用户私钥与连接命令' 'Chinese-first SSH export action'
assert_contains "$forward_output" '添加转发规则' 'Chinese-first Forward add action'
assert_contains "$forward_output" '升级官方 Realm Runtime' 'Chinese-first Realm upgrade action'
assert_contains "$ingress_output" '网络入口 / Ingress' 'Chinese-first Ingress menu'
assert_contains "$ingress_output" '应用入口强制策略' 'Chinese-first Ingress enforcement action'
assert_contains "$backup_output" 'NoBrand 备份 / 恢复' 'Chinese-first backup menu'
assert_contains "$backup_output" '从备份恢复' 'Chinese-first restore action'

for forbidden in \
  'Add rule' 'List rules' 'Show rule' 'Modify rule' 'Switch backend' \
  'Enable rule' 'Disable rule' 'Set Display Endpoint' 'Delete rule' \
  'Export JSON' 'Import JSON' 'Upgrade official Realm runtime'; do
  assert_not_contains "$forward_output" "$forbidden" "removed legacy Forward label: $forbidden"
done

# Exercise nested prompts. Technical names and enum literals are deliberately
# allowed; this test targets human-facing prose instead of banning ASCII.
forward_nested="$({
  public_ip() { return 1; }
  INGRESS_PROFILE_ID=""
  set_inputs demo 1 1 '' 32001 203.0.113.10 443 '' 1 1
  forward_menu_collect_add
})"
assert_contains "$forward_nested" '转发后端：' 'Forward backend prompt'
assert_contains "$forward_nested" '协议：1) TCP' 'Forward protocol prompt'
assert_contains "$forward_nested" '目标地址:' 'Forward target-address prompt'
assert_contains "$forward_nested" '目标端口:' 'Forward target-port prompt'

reality_nested="$({
  nb_prepare_ingress_request() { export INGRESS_PROFILE_ID=i0000000000000001; }
  nb_prepare_ingress_deployment() { :; }
  nb_ingress_profile_json() { printf '%s\n' '{"type":"public"}'; }
  nb_ingress_profile_name() { printf '测试入口'; }
  reality_find_id_by_name() { return 1; }
  nb_ingress_port_is_reserved() { return 1; }
  nb_warn_if_outside_recommended_range() { :; }
  nb_port_available_for_profile() { return 0; }
  reality_resolve_camouflage_request() { :; }
  export VLESS_REALITY_NAME=primary VLESS_REALITY_TARGET="" VLESS_REALITY_TARGET_CLI=0
  export VLESS_REALITY_TARGET_PORT=443 VLESS_REALITY_TARGET_PORT_CLI=0
  export VLESS_REALITY_FINGERPRINT=chrome VLESS_REALITY_SPIDER_X=/
  export PORT="" YES=0 ADVERTISE_CLI=1 ADVERTISE_AUTO_REQUESTED=1
  set_inputs '' '' 32000
  reality_collect_install_requests
})"
assert_contains "$reality_nested" 'REALITY 伪装域名 [auto]:' 'REALITY camouflage-host prompt'
assert_contains "$reality_nested" 'REALITY 伪装目标端口 [443]:' 'REALITY camouflage-port prompt'
assert_contains "$reality_nested" '实际 TCP 监听端口' 'REALITY listener prompt'

ingress_nested="$({
  nb_ingress_interface_rows() { printf 'eth0|192.0.2.10|UP|1\n'; }
  set_inputs Demo 1 eth0 192.0.2.10 2 31001 31020 '' '' 1
  ingress_menu_collect_add
})"
assert_contains "$ingress_nested" '可用非回环 IPv4' 'Ingress interface guidance'
assert_contains "$ingress_nested" '网络接口 / Interface [eth0]:' 'Ingress interface prompt'
assert_contains "$ingress_nested" '本地监听 IPv4 [192.0.2.10]:' 'Ingress local-address prompt'
assert_contains "$ingress_nested" '范围起始端口:' 'Ingress range-start prompt'
assert_contains "$ingress_nested" '入口强制策略' 'Ingress enforcement prompt'

nodes_output="$({
  nb_all_node_rows() {
    printf '%s\n' \
      'Mieru/TCP|run|node.example:1|Running|TCP' \
      'Snell/v5|stop|node.example:2|Stopped|TCP' \
      'SSH Tunnel|ready|node.example:3|Ready|TCP' \
      'Port Forward/nftables|healthy|node.example:4|Healthy|TCP' \
      'Port Forward/realm|degraded|node.example:5|Degraded|TCP' \
      'Port Forward/nftables|disabled|node.example:6|Disabled|TCP'
  }
  nb_node_detail_rows() {
    printf '%s\n' 'owner:test|*:1/TCP|node.example:1|测试入口|strict (firewall)'
  }
  nobrand_nodes
})"
for translated_status in 运行中 已停止 就绪 正常 异常 已禁用; do
  assert_contains "$nodes_output" "$translated_status" \
    "Chinese node status: $translated_status"
done
assert_contains "$nodes_output" '实际监听 / Actual Listener' \
  'Chinese-first node-detail heading'
for raw_status in Running Stopped Ready Healthy Degraded Disabled; do
  assert_not_contains "$nodes_output" "$raw_status" \
    "raw node status removed in Chinese mode: $raw_status"
done

status_output="$({
  nb_all_node_rows() {
    printf '%s\n' \
      'Mieru/TCP|run|node.example:1|Running|TCP' \
      'Hysteria2|stop|node.example:2|Stopped|UDP' \
      'SSH Tunnel|ready|node.example:3|Ready|TCP' \
      'Port Forward/nftables|healthy|node.example:4|Healthy|TCP'
  }
  nobrand_status
})"
for translated_status in 已安装 运行中 已停止 就绪 正常; do
  assert_contains "$status_output" "$translated_status" \
    "Chinese aggregate status: $translated_status"
done
for raw_status in Installed Running Stopped Ready Healthy healthy; do
  assert_not_contains "$status_output" "$raw_status" \
    "generic English state removed from Chinese aggregate status: $raw_status"
done

help_output="$(nobrand_usage)"
assert_contains "$help_output" '默认伪装域名：从发行版验证池自动选择' \
  'Chinese-first REALITY help guidance'

localized_status_source="$(
  cat "$TEST_ROOT/src/56-snell.sh" "$TEST_ROOT/src/57-hysteria2.sh" \
    "$TEST_ROOT/src/58-vless-sudoku.sh" "$TEST_ROOT/src/59-tuic.sh" \
    "$TEST_ROOT/src/59-vless-reality.sh"
)"
assert_contains "$localized_status_source" '运行中' 'localized running status'
assert_contains "$localized_status_source" '已停止' 'localized stopped status'

# Keep the maintenance-facing bootstrap/recovery/uninstall wording Chinese-first
# and protect the unreleased documentation boundary.
maintenance_ui_source="$(
  cat "$TEST_ROOT/src/18-core-nodes.sh" "$TEST_ROOT/src/80-lifecycle.sh" \
    "$TEST_ROOT/src/99-main.sh"
)"
assert_contains "$maintenance_ui_source" \
  '未完成的 ${scope} 操作必须先按其组件范围恢复' \
  'Chinese-first scoped bootstrap recovery error'
assert_contains "$maintenance_ui_source" '检测到未完成的完整卸载。请选择恢复操作' \
  'Chinese-first global-uninstall recovery prompt'
assert_contains "$maintenance_ui_source" '资源与 nobrand/nb 已完整删除；外部资源未触碰' \
  'Chinese-first global-uninstall completion message'
assert_contains "$maintenance_ui_source" '可执行 `hash -r` 清除命令缓存' \
  'Chinese-first Bash command-cache guidance'

readme_source="$(<"$TEST_ROOT/README.md")"
assert_contains "$readme_source" '当前稳定版本：[v3.2.2]' \
  'README current stable release boundary'
assert_not_contains "$readme_source" '当前稳定版本：[v3.2.1]' \
  'README must not retain the previous stable release boundary'
assert_contains "$readme_source" \
  '安装器会先原子安装并验证当前管理器及 `nobrand`/`nb` 命令，再打开统一交互菜单' \
  'README install-before-menu contract'
assert_contains "$readme_source" 'NoBrand 支持仅安装管理器而暂不安装任何协议' \
  'README manager-only capability'

pass 'Chinese-first menus, maintenance text, README boundary, nested prompts, and status localization'
