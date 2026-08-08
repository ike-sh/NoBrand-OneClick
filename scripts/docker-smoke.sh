#!/usr/bin/env bash
# 本地/CI：在干净 Debian 容器内验证配置输出、isolated-v2 事务、配额与 tc 所有权。
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && { pwd -W 2>/dev/null || pwd; })"

docker run --rm --cap-add=NET_ADMIN -v "$ROOT:/work:ro" debian:bookworm-slim bash -s <<'DOCKER_TEST'
set -Eeuo pipefail
apt-get update -qq >/dev/null
apt-get install -y -qq python3 bash curl util-linux iproute2 passwd >/dev/null
bash -n /work/install-mita.sh

export MITA_SOURCE_ONLY=1
export MITA_MANAGER_STATE_DIR=/tmp/manager-state
export MITA_STATE=/tmp/manager-state/install-state.env
export MITA_USERS_STATE=/tmp/manager-state/users.json MITA_USERS_LOCK=/tmp/manager-state/users.lock
export MITA_USERS_BACKUP_DIR=/tmp/manager-state/backups MITA_ADMIN_LOCK=/tmp/manager-state/admin.lock
export MITA_USERS_LOG=/tmp/users.log MITA_LOGROTATE_CONF=/tmp/logrotate.conf
export MITA_INSTANCES_DIR=/tmp/instances MITA_INSTANCE_RUN_DIR=/tmp/run
export MITA_INSTANCE_METRICS_DIR=/tmp/metrics
export MITA_INSTANCE_SYSTEMD_TEMPLATE=/tmp/mita-oneclick@.service
export MITA_INSTANCE_RUNNER=/tmp/mita-instance-run
export MITA_INSTANCE_OPENRC_PREFIX=/tmp/mita-oneclick-
export MITA_METRICS_FILE=/tmp/legacy-metrics.pb
export TC_OWNED_STATE=/tmp/manager-state/tc-owned.filters TC_IFACE=eth-test
export MITA_FIREWALL_OWNED_STATE=/tmp/manager-state/firewall-owned.bindings
export BBR_STATE_FILE=/tmp/manager-state/bbr-owned.state
export BBR_BACKUP_FILE=/tmp/manager-state/bbr-sysctl.backup
export USER_PORT_POOL_START=26000 USER_PORT_POOL_END=26020
export INSTALL_SCRIPT_PATH=/work/install-mita.sh QUOTA_RESET_METHOD=metrics
mkdir -p /tmp/manager-state/backups /tmp/instances /tmp/run /tmp/metrics /etc/logrotate.d
chmod 0700 /tmp/manager-state /tmp/manager-state/backups
getent group mita >/dev/null || groupadd --system mita
id mita >/dev/null 2>&1 || useradd --system -g mita -s /usr/sbin/nologin -d /tmp/metrics mita

source /work/install-mita.sh
test "$SCRIPT_VERSION" = 2.2.0
trap - ERR
MITA_STATE=/tmp/manager-state/install-state.env

# RC2 UI：品牌格式恢复；主菜单编号固定，卸载为直接入口，未安装摘要不泄漏默认 Profile/state。
grep -q '^# 作者: ike / https://github.com/ike-sh/mieru-OneClick$' /work/install-mita.sh
grep -q '作者: ${SCRIPT_AUTHOR} / https://github.com/${SCRIPT_REPO}' /work/install-mita.sh
! grep -Eq '主菜单[[:space:]]+[0-9]+|main menu[[:space:]]+[0-9]+|菜单[[:space:]]+\*{0,2}[0-9]+\)' \
  /work/install-mita.sh /work/README.md
(
  LANG_ZH=1 MENU_SCRIPTS_READY=1
  mita_installed(){ return 1; }
  load_install_state(){ PROFILE=custom; MIERU_VERSION=9.9.9; }
  users_count(){ echo 99; }
  installed_version(){ echo 9.9.9; }
  read_tty(){ printf -v "$1" '%s' 0; }
  set +e
  menu_output="$(show_menu)"
  menu_rc=$?
  set -e
  test "$menu_rc" -eq 2
  grep -q '^状态: 未安装$' <<<"$menu_output"
  grep -q '^用户: -$' <<<"$menu_output"
  grep -q '^Profile: -$' <<<"$menu_output"
  grep -q '^Mieru Version: 未安装$' <<<"$menu_output"
  ! grep -q 'Profile: 高级自定义' <<<"$menu_output"
  menu_entries="$(grep -E '^[[:space:]]+[0-9]+\)' <<<"$menu_output")"
  expected_entries="$(cat <<'EOF'
  1) 新装 / 安装
  2) 查看节点
  3) 用户管理
  4) 性能与网络
  5) 重新配置（需先安装）
  6) 服务管理
  7) 备份 / 恢复
  8) 升级
  9) Doctor
 10) 卸载
  0) 退出
EOF
)"
  test "$menu_entries" = "$expected_entries"
)
(
  LANG_ZH=1 MENU_SCRIPTS_READY=1 ACTION=""
  mita_installed(){ return 0; }
  load_install_state(){ :; }
  users_count(){ echo 1; }
  installed_version(){ echo 3.35.0; }
  ensure_management_scripts(){ :; }
  read_tty(){ printf -v "$1" '%s' 10; }
  installed_menu_output_file=/tmp/rc2-installed-menu.out
  show_menu >"$installed_menu_output_file"
  grep -q '^  1) 修复安装$' "$installed_menu_output_file"
  test "$ACTION" = uninstall
)
(
  LANG_ZH=1 ACTION=""
  read_tty(){ printf -v "$1" '%s' 0; }
  set +e
  advanced_output="$(show_advanced_menu)"
  advanced_rc=$?
  set -e
  test "$advanced_rc" -eq 2
  ! grep -q '卸载' <<<"$advanced_output"
  ! grep -Eq '新装 / 安装|修复安装' <<<"$advanced_output"
)
grep -q '确认卸载 mita、OneClick 管理脚本及本项目管理的配置？\[y/N\]:' \
  /work/install-mita.sh

# 安装状态只允许从 root 所有且父目录不可写的常规文件读取。
(
  unsafe_dir=/tmp/unsafe-manager-state
  mkdir -p "$unsafe_dir"
  chmod 0777 "$unsafe_dir"
  printf 'USERNAME=unsafe-state-was-sourced\n' >"$unsafe_dir/install-state.env"
  chmod 0600 "$unsafe_dir/install-state.env"
  MITA_STATE="$unsafe_dir/install-state.env"
  USERNAME=unchanged
  if load_install_state >/dev/null 2>&1; then
    echo "unsafe install state unexpectedly accepted" >&2
    exit 1
  fi
  test "$USERNAME" != unsafe-state-was-sourced
)
(
  real_dir=/tmp/real-manager-state
  link_dir=/tmp/symlink-manager-state
  mkdir -p "$real_dir"
  chmod 0700 "$real_dir"
  ln -s "$real_dir" "$link_dir"
  printf 'USERNAME=symlink-state-was-sourced\n' >"$real_dir/install-state.env"
  chmod 0600 "$real_dir/install-state.env"
  MITA_STATE="$link_dir/install-state.env"
  USERNAME=unchanged
  if load_install_state >/dev/null 2>&1; then
    echo "state under symlink parent unexpectedly accepted" >&2
    exit 1
  fi
  test "$USERNAME" != symlink-state-was-sourced
)

# 旧版 root 状态可迁移；仅存在防火墙状态时也必须触发迁移。
(
  legacy=/tmp/legacy-manager-state
  current=/tmp/migrated-manager-state
  rm -rf "$legacy" "$current"
  mkdir -p "$legacy/backups"
  chmod 0755 "$legacy" "$legacy/backups"
  printf 'PORT=26008\nUSERNAME=migrated\n' >"$legacy/install-state.env"
  printf 'iptables|tcp|26008\n' >"$legacy/firewall-owned.bindings"
  printf '{"version":2,"users":[]}\n' >"$legacy/backups/users_manual.json"
  chmod 0600 "$legacy/install-state.env" "$legacy/firewall-owned.bindings" "$legacy/backups/users_manual.json"
  MITA_MANAGER_STATE_DIR="$current"
  MITA_LEGACY_STATE_DIR="$legacy"
  MITA_LEGACY_STATE="$legacy/install-state.env"
  MITA_LEGACY_USERS_STATE="$legacy/users.json"
  MITA_LEGACY_USERS_BACKUP_DIR="$legacy/backups"
  MITA_LEGACY_FIREWALL_STATE="$legacy/firewall-owned.bindings"
  MITA_LEGACY_TC_STATE="$legacy/tc-owned.filters"
  MITA_LEGACY_MARKER="$legacy/.mieru-oneclick"
  MITA_STATE="$current/install-state.env"
  MITA_USERS_STATE="$current/users.json"
  MITA_USERS_BACKUP_DIR="$current/backups"
  MITA_FIREWALL_OWNED_STATE="$current/firewall-owned.bindings"
  TC_OWNED_STATE="$current/tc-owned.filters"
  MITA_MARKER="$current/.installed"
  ensure_manager_state_layout
  grep -qx 'USERNAME=migrated' "$MITA_STATE"
  grep -qx 'iptables|tcp|26008' "$MITA_FIREWALL_OWNED_STATE"
  test -f "$MITA_USERS_BACKUP_DIR/users_manual.json"
  test ! -e "$MITA_LEGACY_STATE"
  test ! -e "$MITA_LEGACY_FIREWALL_STATE"
  test "$(stat -c %a "$current")" = 700
)
(
  legacy=/tmp/legacy-firewall-only
  current=/tmp/migrated-firewall-only
  rm -rf "$legacy" "$current"
  mkdir -p "$legacy"
  chmod 0755 "$legacy"
  printf 'iptables|tcp|26009\n' >"$legacy/firewall-owned.bindings"
  chmod 0600 "$legacy/firewall-owned.bindings"
  MITA_MANAGER_STATE_DIR="$current"
  MITA_LEGACY_STATE_DIR="$legacy"
  MITA_LEGACY_STATE="$legacy/install-state.env"
  MITA_LEGACY_USERS_STATE="$legacy/users.json"
  MITA_LEGACY_USERS_BACKUP_DIR="$legacy/backups"
  MITA_LEGACY_FIREWALL_STATE="$legacy/firewall-owned.bindings"
  MITA_LEGACY_TC_STATE="$legacy/tc-owned.filters"
  MITA_LEGACY_MARKER="$legacy/.mieru-oneclick"
  MITA_STATE="$current/install-state.env"
  MITA_USERS_STATE="$current/users.json"
  MITA_USERS_BACKUP_DIR="$current/backups"
  MITA_FIREWALL_OWNED_STATE="$current/firewall-owned.bindings"
  TC_OWNED_STATE="$current/tc-owned.filters"
  MITA_MARKER="$current/.installed"
  ensure_manager_state_layout
  grep -qx 'iptables|tcp|26009' "$MITA_FIREWALL_OWNED_STATE"
)

# 空实例集合不能在 ERR trap 中产生伪失败输出。
empty_stop_output="$(
  (
    set -Eeuo pipefail
    trap on_error ERR
    MITA_USERS_STATE=/tmp/no-users.json
    MITA_INSTANCES_DIR=/tmp/no-instances
    mkdir -p "$MITA_INSTANCES_DIR"
    isolated_stop_all
  ) 2>&1
)"
test -z "$empty_stop_output"

# 状态、默认客户端模式与 MTU 策略。
printf "%s\n" \
  "PORT=26000" "PORT_RANGE=" "PROTOCOL=TCP" "MTU=1452" "MTU_POLICY=custom" \
  "ADVERTISE_HOST=" "ADVERTISE_PORT=" \
  "USERNAME=alice" "PASSWORD=alice-pass" "TRAFFIC_PATTERN=off" \
  "LOW_ENTROPY_MODE=LOW_ENTROPY_MODE_OFF" \
  "MULTIPLEXING=MULTIPLEXING_OFF" "HANDSHAKE_MODE=HANDSHAKE_NO_WAIT" >"$MITA_STATE"
chmod 600 "$MITA_STATE"
load_install_state
test "$USERNAME|$PASSWORD|$PORT|$PROTOCOL|$MTU|$MTU_POLICY" = \
  "alice|alice-pass|26000|TCP|1452|custom"
test "$PROFILE|$MIERU_CHANNEL" = "custom|latest"

# v2.0/v2.1 install-state migration：仅新增元数据推导，原始真实参数逐项保留。
(
  migration_dir=/tmp/state-migration-v20
  rm -rf "$migration_dir"; mkdir -p "$migration_dir"; chmod 0700 "$migration_dir"
  MITA_STATE="$migration_dir/install-state.env"
  printf '%s\n' \
    'PORT=30000' 'PORT_RANGE=' 'PROTOCOL=TCP' \
    'ADVERTISE_HOST=cm-entry.example.com' 'ADVERTISE_PORT=10086' \
    'MTU=1400' 'MTU_POLICY=safe' 'USERNAME=legacy20' 'PASSWORD=legacy-pass' \
    'TRAFFIC_PATTERN=conservative' 'TRAFFIC_SEED=42' \
    'LOW_ENTROPY_MODE=LOW_ENTROPY_MODE_OFF' \
    'MULTIPLEXING=MULTIPLEXING_OFF' 'HANDSHAKE_MODE=HANDSHAKE_NO_WAIT' >"$MITA_STATE"
  chmod 0600 "$MITA_STATE"
  load_install_state
  test "$PROFILE|$MIERU_CHANNEL" = 'balanced|latest'
  test "$PORT|$PROTOCOL|$ADVERTISE_HOST|$ADVERTISE_PORT|$MTU|$USERNAME|$PASSWORD|$TRAFFIC_PATTERN|$TRAFFIC_SEED|$LOW_ENTROPY_MODE|$MULTIPLEXING|$HANDSHAKE_MODE" = \
    '30000|TCP|cm-entry.example.com|10086|1400|legacy20|legacy-pass|conservative|42|LOW_ENTROPY_MODE_OFF|MULTIPLEXING_OFF|HANDSHAKE_NO_WAIT'
)
(
  migration_dir=/tmp/state-migration-v21
  rm -rf "$migration_dir"; mkdir -p "$migration_dir"; chmod 0700 "$migration_dir"
  MITA_STATE="$migration_dir/install-state.env"
  printf '%s\n' \
    'PORT=31000' 'PORT_RANGE=' 'PROTOCOL=UDP' \
    'ADVERTISE_HOST=2001:db8::20' 'ADVERTISE_PORT=12000' \
    'MTU=1380' 'MTU_POLICY=custom' 'USERNAME=legacy21' 'PASSWORD=legacy-pass-21' \
    'TRAFFIC_PATTERN=aggressive' 'TRAFFIC_SEED=99' \
    'LOW_ENTROPY_MODE=LOW_ENTROPY_MODE_48' \
    'MULTIPLEXING=MULTIPLEXING_HIGH' 'HANDSHAKE_MODE=HANDSHAKE_STANDARD' >"$MITA_STATE"
  chmod 0600 "$MITA_STATE"
  load_install_state
  test "$PROFILE|$MIERU_CHANNEL" = 'custom|latest'
  test "$PORT|$PROTOCOL|$ADVERTISE_HOST|$ADVERTISE_PORT|$MTU|$USERNAME|$PASSWORD|$TRAFFIC_PATTERN|$TRAFFIC_SEED|$LOW_ENTROPY_MODE|$MULTIPLEXING|$HANDSHAKE_MODE" = \
    '31000|UDP|2001:db8::20|12000|1380|legacy21|legacy-pass-21|aggressive|99|LOW_ENTROPY_MODE_48|MULTIPLEXING_HIGH|HANDSHAKE_STANDARD'
)
# stable 升级不得自动切 latest，也不得把已安装的更高版本降级。
(
  upgrade_dir=/tmp/stable-upgrade
  rm -rf "$upgrade_dir"; mkdir -p "$upgrade_dir"; chmod 0700 "$upgrade_dir"
  MITA_MANAGER_STATE_DIR="$upgrade_dir"
  MITA_STATE="$upgrade_dir/install-state.env"
  MITA_USERS_STATE="$upgrade_dir/users.json"
  MITA_MARKER="$upgrade_dir/.installed"
  printf '%s\n' \
    'PORT=30000' 'PORT_RANGE=' 'PROTOCOL=TCP' 'PROFILE=balanced' \
    'ADVERTISE_HOST=cm-entry.example.com' 'ADVERTISE_PORT=10086' \
    'MTU=1400' 'MTU_POLICY=safe' 'USERNAME=stable-user' 'PASSWORD=stable-pass' \
    'TRAFFIC_PATTERN=conservative' 'TRAFFIC_SEED=42' \
    'LOW_ENTROPY_MODE=LOW_ENTROPY_MODE_OFF' \
    'MULTIPLEXING=MULTIPLEXING_OFF' 'HANDSHAKE_MODE=HANDSHAKE_NO_WAIT' \
    'MIERU_CHANNEL=stable' 'MIERU_VERSION=3.35.0' >"$MITA_STATE"
  chmod 0600 "$MITA_STATE"
  require_root(){ :; }
  require_linux(){ :; }
  require_cmd(){ :; }
  detect_pkg_manager(){ echo deb; }
  detect_arch(){ echo amd64; }
  ensure_management_dependencies(){ :; }
  installed_version(){ echo 3.40.0; }
  install_self_script(){ :; }
  download_package(){ touch /tmp/stable-unexpected-download; }
  MENU_MODE=1
  rm -f /tmp/stable-unexpected-download
  do_upgrade >/dev/null
  test ! -e /tmp/stable-unexpected-download
  grep -qx 'MIERU_CHANNEL=stable' "$MITA_STATE"
  grep -qx 'MIERU_VERSION=3.35.0' "$MITA_STATE"
)
test "$(normalize_multiplexing off)" = MULTIPLEXING_OFF
test "$(normalize_handshake_mode no-wait)" = HANDSHAKE_NO_WAIT
test "$(normalize_low_entropy_mode 56)" = LOW_ENTROPY_MODE_56
test "$(normalize_mtu_policy auto)" = optimized
! valid_mtu 1279
valid_mtu 1280
valid_mtu 1500
! valid_mtu 1501
valid_nonnegative_int32 2147483647
! valid_nonnegative_int32 2147483648
valid_bandwidth_mbps 1000000
! valid_bandwidth_mbps 1000001
valid_advertise_port 1
valid_advertise_port 443
valid_advertise_port 65535
! valid_advertise_port 0
! valid_advertise_port 65536
valid_advertise_host 203.0.113.10
valid_advertise_host 2001:db8::1
valid_advertise_host cm-entry.example.com
! valid_advertise_host 'https://cm-entry.example.com'
! valid_advertise_host '-bad.example.com'
test "$(normalize_uint 00008)" = 8
ADVERTISE_HOST=203.0.113.10 ADVERTISE_PORT=443 PROTOCOL=TCP
validate_advertise_endpoint
PROTOCOL=BOTH
! validate_advertise_endpoint_values 203.0.113.10 65535 BOTH >/dev/null 2>&1
ADVERTISE_HOST="" ADVERTISE_PORT=""
PROTOCOL=TCP MTU=1500
calculate_optimized_mtu
test "$MTU|$MTU_POLICY" = "1400|optimized"
mtu_default_iface(){ echo eth-test; }
mtu_iface_value(){ echo 1500; }
mtu_route_family(){ echo IPv4; }
PROTOCOL=UDP
calculate_optimized_mtu
test "$MTU|$MTU_AUTO_LINK|$MTU_AUTO_OVERHEAD" = "1400|1500|28"

# Profile 只设置完整真实参数；反推只做精确匹配，手工偏离后自动变为 custom。
LANG_ZH=1
test "$(profile_label iplc)" = 'IPLC / 专线性能'
test "$(profile_label balanced)" = '普通公网'
test "$(profile_label stealth)" = '强化伪装'
test "$(profile_label custom)" = '高级自定义'
grep -q 'profile=default 是上游客户端的 profileName' /work/install-mita.sh
grep -q 'profile=default.*上游 Mieru 客户端的.*profileName' /work/README.md
apply_profile_values iplc
test "$PROFILE|$PROTOCOL|$MTU|$MULTIPLEXING|$HANDSHAKE_MODE|$TRAFFIC_PATTERN|$LOW_ENTROPY_MODE" = \
  'iplc|TCP|1400|MULTIPLEXING_OFF|HANDSHAKE_NO_WAIT|off|LOW_ENTROPY_MODE_OFF'
test "$(infer_profile_from_values)" = iplc
MTU=1390
profile_reconcile_metadata
test "$PROFILE" = custom
apply_profile_values balanced
test "$(infer_profile_from_values)" = balanced
apply_profile_values stealth
test "$TRAFFIC_PATTERN|$LOW_ENTROPY_MODE|$(infer_profile_from_values)" = \
  'aggressive|LOW_ENTROPY_MODE_OFF|stealth'
(
  MIERU_CHANNEL=stable
  test "$(target_mieru_version)" = "$TESTED_MIERU_VERSION"
  query_latest_version(){ echo 9.9.9; }
  MIERU_CHANNEL=latest
  test "$(target_mieru_version)" = 9.9.9
  MIERU_CHANNEL=pinned MIERU_VERSION=3.40.1
  test "$(target_mieru_version)" = 3.40.1
)
apply_profile_values balanced
MIERU_CHANNEL=latest MIERU_VERSION=""

# trafficPattern、分享链接、官方客户端 JSON 与 mihomo YAML。
mita_supports_traffic_pattern(){ return 0; }
mita_supports_low_entropy(){ return 0; }
installed_version(){ echo 3.35.0; }
TRAFFIC_PATTERN=aggressive TRAFFIC_SEED=42 LOW_ENTROPY_MODE=LOW_ENTROPY_MODE_56
tp="$(traffic_pattern_json)"
grep -q '"unlockAll": false' <<<"$tp"
grep -q '"mode": "LOW_ENTROPY_MODE_56"' <<<"$tp"
compat_warning="$(warn_low_entropy_client_compat 2>&1)"
grep -q mihomo <<<"$compat_warning"
TRAFFIC_PATTERN=off LOW_ENTROPY_MODE=LOW_ENTROPY_MODE_OFF
PROTOCOL=TCP MTU=1400 MTU_POLICY=safe PORT=26000 USERNAME=alice PASSWORD=alice-pass
MULTIPLEXING=MULTIPLEXING_OFF HANDSHAKE_MODE=HANDSHAKE_NO_WAIT
link="$(generate_share_link_for 2001:db8::1 TCP)"
grep -q '^mierus://alice:alice-pass@\[2001:db8::1\]?' <<<"$link"
grep -q 'port=26000' <<<"$link"
grep -q 'mtu=1400' <<<"$link"
grep -q 'multiplexing=MULTIPLEXING_OFF' <<<"$link"
grep -q 'handshake-mode=HANDSHAKE_NO_WAIT' <<<"$link"
json="$(build_client_json_for 1.2.3.4 TCP)"
python3 -c 'import json,sys; d=json.load(sys.stdin); p=d["profiles"][0]; assert p["mtu"]==1400 and p["handshakeMode"]=="HANDSHAKE_NO_WAIT"' <<<"$json"
USERNAME='user: with/slash' PASSWORD='p"ass\word'
yaml="$(build_clash_yaml_full 1.2.3.4)"
grep -q 'username: "user: with/slash"' <<<"$yaml"
grep -Fq 'password: "p\"ass\\word"' <<<"$yaml"

# 自定义入口只改变客户端产物；服务端配置、防火墙提示仍使用真实监听端口。
USERNAME=alice PASSWORD=alice-pass PROTOCOL=TCP PORT=26000 PORT_RANGE=""
ADVERTISE_HOST=203.0.113.10 ADVERTISE_PORT=443
custom_link="$(generate_share_link_for "$ADVERTISE_HOST" TCP)"
grep -q '@203.0.113.10?' <<<"$custom_link"
grep -q 'port=443' <<<"$custom_link"
custom_json="$(build_client_json_for "$ADVERTISE_HOST" TCP)"
python3 -c 'import json,sys; d=json.load(sys.stdin); s=d["profiles"][0]["servers"][0]; assert s["ipAddress"]=="203.0.113.10" and s["portBindings"]==[{"port":443,"protocol":"TCP"}]' <<<"$custom_json"
ADVERTISE_PORT=08
leading_zero_json="$(build_client_json_for "$ADVERTISE_HOST" TCP)"
python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["profiles"][0]["servers"][0]["portBindings"][0]["port"]==8' <<<"$leading_zero_json"
ADVERTISE_PORT=443
custom_yaml="$(build_clash_yaml_full "$ADVERTISE_HOST")"
grep -q 'server: "203.0.113.10"' <<<"$custom_yaml"
grep -q 'port: 443' <<<"$custom_yaml"

# Golden：后端 203.0.113.10:30000 与客户端域名入口 cm-entry.example.com:10086 严格分离。
PORT=30000 ADVERTISE_HOST=cm-entry.example.com ADVERTISE_PORT=10086
domain_link="$(generate_share_link_for "$ADVERTISE_HOST" TCP)"
grep -q '@cm-entry.example.com?' <<<"$domain_link"
grep -q 'port=10086' <<<"$domain_link"
domain_json="$(build_client_json_for "$ADVERTISE_HOST" TCP)"
python3 -c 'import json,sys; s=json.load(sys.stdin)["profiles"][0]["servers"][0]; assert s["ipAddress"]=="" and s["domainName"]=="cm-entry.example.com" and s["portBindings"]==[{"port":10086,"protocol":"TCP"}]' <<<"$domain_json"
domain_yaml="$(build_clash_yaml_full "$ADVERTISE_HOST")"
grep -q 'server: "cm-entry.example.com"' <<<"$domain_yaml"
grep -q 'port: 10086' <<<"$domain_yaml"
domain_server_cfg="$(write_server_config)"
python3 -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); raw=open(p).read(); assert d["portBindings"]==[{"port":30000,"protocol":"TCP"}] and "cm-entry.example.com" not in raw and "10086" not in raw' "$domain_server_cfg"
rm -f "$domain_server_cfg"
domain_fw_hint="$(cloud_firewall_hint)"
grep -q '30000/TCP' <<<"$domain_fw_hint"
! grep -q '10086/TCP' <<<"$domain_fw_hint"

PORT=26000 ADVERTISE_HOST=203.0.113.10 ADVERTISE_PORT=443
printf stale > /root/mieru_client_legacy.json
compact_output="$(print_protocol_outputs "$ADVERTISE_HOST")"
grep -Eq '(已保存|Saved):[[:space:]]+/root/mieru-clients/current/alice_tcp\.json' <<<"$compact_output"
! grep -q '"profiles"' <<<"$compact_output"
test -f /root/mieru-clients/current/alice_tcp.json
first_client_hash="$(sha256sum /root/mieru-clients/current/alice_tcp.json | awk '{print $1}')"
print_protocol_outputs "$ADVERTISE_HOST" >/dev/null
test "$(find /root/mieru-clients/current -maxdepth 1 -type f -name 'alice_tcp.json' | wc -l)" -eq 1
test "$(sha256sum /root/mieru-clients/current/alice_tcp.json | awk '{print $1}')" = "$first_client_hash"
test -z "$(find /root -maxdepth 1 -type f -name 'mieru_client_*.json' -print -quit)"
client_config_output="$(
  public_ip(){ echo 198.51.100.40; }
  generate_client_config
)"
grep -q 'mieru apply config <客户端本地 JSON 路径>' <<<"$client_config_output"
! grep -q 'mieru apply config /root' <<<"$client_config_output"
! grep -q 'mieru_client_.*\*\.json' <<<"$client_config_output"
grep -q '【客户端入口映射】' <<<"$client_config_output"
grep -q '客户端: 203.0.113.10:443/TCP' <<<"$client_config_output"
grep -q -- '-> 后端: 198.51.100.40:26000/TCP' <<<"$client_config_output"

# 显式填写的入口若与探测公网 IP/后端端口相同，不显示独立入口或映射。
(
  PORT=17353 PROTOCOL=TCP ADVERTISE_HOST=192.236.242.173 ADVERTISE_PORT=17353
  public_ip(){ echo 192.236.242.173; }
  print_protocol_outputs(){ :; }
  same_mapping="$(print_client_endpoint_mapping)"
  test -z "$same_mapping"
  same_summary="$(print_summary current)"
  ! grep -q '客户端入口映射' <<<"$same_summary"
)

# 批量导出的人类可读输出也解释独立客户端入口，但客户端文件仍只写入口值。
(
  batch_root=/tmp/rc2-batch-export
  rm -rf "$batch_root"
  mkdir -p "$batch_root"
  MITA_USERS_STATE="$batch_root/users.json"
  MITA_CLIENT_EXPORT_DIR="$batch_root/clients"
  printf '%s\n' '{"version":2,"users":[{"name":"batch-user","password":"batch-pass","port":30000,"enabled":true,"advertise_host":"cm-entry.example.com","advertise_port":10086}]}' >"$MITA_USERS_STATE"
  chmod 0600 "$MITA_USERS_STATE"
  load_install_state(){
    PROTOCOL=TCP PORT=30000 PORT_RANGE="" MTU=1400 MTU_POLICY=safe
    MULTIPLEXING=MULTIPLEXING_OFF HANDSHAKE_MODE=HANDSHAKE_NO_WAIT
    TRAFFIC_PATTERN=off LOW_ENTROPY_MODE=LOW_ENTROPY_MODE_OFF
  }
  users_ensure_loaded(){ :; }
  public_ip(){ echo 192.236.242.173; }
  batch_output="$(do_user_export_clients 2>&1)"
  grep -q '【客户端入口映射】' <<<"$batch_output"
  grep -q '客户端: cm-entry.example.com:10086/TCP' <<<"$batch_output"
  grep -q -- '-> 后端: 192.236.242.173:30000/TCP' <<<"$batch_output"
  python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); s=d["profiles"][0]["servers"][0]; assert s["domainName"]=="cm-entry.example.com" and s["portBindings"][0]["port"]==10086' \
    "$(find "$MITA_CLIENT_EXPORT_DIR" -name 'batch-user_tcp.json' -print -quit)"
)
server_cfg="$(write_server_config)"
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d["portBindings"]==[{"port":26000,"protocol":"TCP"}] and "203.0.113.10" not in open(sys.argv[1]).read()' "$server_cfg"
rm -f "$server_cfg"
firewall_hint="$(cloud_firewall_hint)"
grep -q '26000/TCP' <<<"$firewall_hint"
! grep -q '443/TCP' <<<"$firewall_hint"
PROTOCOL=BOTH
grep -q 'port=443' <<<"$(generate_share_link_for "$ADVERTISE_HOST" TCP)"
grep -q 'port=444' <<<"$(generate_share_link_for "$ADVERTISE_HOST" UDP)"
dual_output="$(print_protocol_outputs "$ADVERTISE_HOST")"
grep -q '/root/mieru-clients/current/alice_tcp.json' <<<"$dual_output"
grep -q '/root/mieru-clients/current/alice_udp.json' <<<"$dual_output"
test -f /root/mieru-clients/current/alice_tcp.json
test -f /root/mieru-clients/current/alice_udp.json
PROTOCOL=TCP
print_protocol_outputs "$ADVERTISE_HOST" >/dev/null
test -f /root/mieru-clients/current/alice_tcp.json
test ! -e /root/mieru-clients/current/alice_udp.json
ADVERTISE_HOST="" ADVERTISE_PORT="" PROTOCOL=TCP

# 主用户改名只删除旧用户名导出；全局客户端参数变化必须失效全部用户导出。
(
  invalidation_dir=/tmp/client-invalidation
  MITA_CLIENT_EXPORT_DIR="$invalidation_dir"
  mkdir -p "$invalidation_dir/current"
  printf stale >"$invalidation_dir/current/old-user_tcp.json"
  printf stale >"$invalidation_dir/current/old-user_udp.json"
  printf keep >"$invalidation_dir/current/bob_tcp.json"
  USERNAME=new-user PROTOCOL=TCP MTU=1400 TRAFFIC_PATTERN=off TRAFFIC_SEED=""
  LOW_ENTROPY_MODE=LOW_ENTROPY_MODE_OFF MULTIPLEXING=MULTIPLEXING_OFF
  HANDSHAKE_MODE=HANDSHAKE_NO_WAIT
  client_exports_after_reconfigure old-user TCP 1400 off "" \
    LOW_ENTROPY_MODE_OFF MULTIPLEXING_OFF HANDSHAKE_NO_WAIT
  test ! -e "$invalidation_dir/current/old-user_tcp.json"
  test ! -e "$invalidation_dir/current/old-user_udp.json"
  test -f "$invalidation_dir/current/bob_tcp.json"
  printf stale >"$invalidation_dir/current/new-user_tcp.json"
  PROTOCOL=UDP
  client_exports_after_reconfigure new-user TCP 1400 off "" \
    LOW_ENTROPY_MODE_OFF MULTIPLEXING_OFF HANDSHAKE_NO_WAIT
  test -z "$(find "$invalidation_dir/current" -maxdepth 1 -type f -name '*.json' -print -quit)"
)

# 安装交互必须始终显示地址和端口问题；公网 IP / 后端端口只能作为默认建议值。
(
  ADVERTISE_HOST="" ADVERTISE_PORT="" ADVERTISE_CLI=0 PORT=26000 PROTOCOL=TCP
  public_ip(){ echo 198.51.100.1; }
  read_tty(){ printf -v "$1" '%s' ''; }
  collect_advertise_endpoint_interactive >/dev/null
  test "$ADVERTISE_HOST|$ADVERTISE_PORT" = '198.51.100.1|26000'
)
(
  ADVERTISE_HOST="" ADVERTISE_PORT="" ADVERTISE_CLI=0 PORT=26000 PROTOCOL=TCP
  public_ip(){ echo 198.51.100.2; }
  advertise_read_count=0
  read_tty(){
    advertise_read_count=$((advertise_read_count + 1))
    if [ "$advertise_read_count" -eq 1 ]; then
      printf -v "$1" '%s' cm-entry.example.com
    else
      printf -v "$1" '%s' 8443
    fi
  }
  collect_advertise_endpoint_interactive >/dev/null
  test "$ADVERTISE_HOST|$ADVERTISE_PORT" = 'cm-entry.example.com|8443'
)
# -y 也不能静默跳过入口确认；必须显式给 endpoint 或 --advertise-auto。
set +e
noninteractive_endpoint_output="$(MITA_SOURCE_ONLY=0 bash /work/install-mita.sh \
  --install -y --port 26000 --user explicit-user --password explicit-pass 2>&1)"
noninteractive_endpoint_rc=$?
set -e
test "$noninteractive_endpoint_rc" -ne 0
grep -q -- '--advertise-host/--advertise-port' <<<"$noninteractive_endpoint_output"

# 端口探测必须区分 TCP/UDP；尾号段选择不得返回已监听端口。
python3 -c 'import socket,time; s=socket.socket(); s.bind(("127.0.0.1",26801)); s.listen(); time.sleep(20)' &
listener_pid=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do
  port_is_listening 26801 TCP && break
  sleep 0.1
done
port_is_listening 26801 TCP
! port_is_listening 26801 UDP
PROTOCOL=TCP
! port_available_for_mode 26801
kill "$listener_pid"
wait "$listener_pid" 2>/dev/null || true
port_available_for_mode 26801
(
  derive_port_base(){ echo 26800; }
  port_is_listening(){ [ "$1" -ne 26899 ]; }
  PROTOCOL=TCP
  test "$(derive_port_from_ip)" = 26899
)
# 自动端口在落盘前被抢占时应自动更换；显式端口则必须拒绝。
(
  PORT=26801 PROTOCOL=TCP PORT_AUTO_SELECTED=1
  port_available_for_mode(){ [ "$1" = 26802 ]; }
  select_available_port(){ echo 26802; }
  ensure_install_port_available >/dev/null
  test "$PORT" = 26802
)
if (
  PORT=26801 PROTOCOL=TCP PORT_AUTO_SELECTED=0
  port_available_for_mode(){ return 1; }
  ensure_install_port_available >/dev/null 2>&1
); then
  echo "explicit occupied port unexpectedly accepted" >&2
  exit 1
fi
(
  MITA_STATE=/tmp/no-install-state.env
  MITA_USERS_STATE=/tmp/no-users-state.json
  ! mita_preservable_config_exists
)

# 构造用户状态；正数 bandwidth 在专属实例模型中必须允许。
require_root(){ :; }
require_linux(){ :; }
mita_installed(){ return 0; }
install_users_scheduler(){ :; }
port_is_listening(){ return 1; }
public_ip(){ echo 1.2.3.4; }
USERNAME=alice PASSWORD=alice-pass PORT=26000 PROTOCOL=TCP
ADVERTISE_HOST=203.0.113.10 ADVERTISE_PORT=443
USER_QUOTA_MB=0 USER_QUOTA_DAYS=0 USER_QUOTA_MODE=rolling
USER_PACKAGE=unlimited USER_EXPIRE="" USER_BANDWIDTH_MBPS=0
users_migrate_from_primary
test "$(users_get_field alice advertise_host)|$(users_get_field alice advertise_port)" = '203.0.113.10|443'
USER_BANDWIDTH_MBPS=10 USER_PACKAGE=custom USER_QUOTA_MB=1024 USER_QUOTA_DAYS=30
users_add bob bob-pass 26005 >/dev/null
test "$(users_count)" -eq 2
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert all(u.get("instance_id","").startswith("u") for u in d["users"]); assert next(u for u in d["users"] if u["name"]=="bob")["bandwidth_mbps"]==10; assert not next(u for u in d["users"] if u["name"]=="bob")["advertise_host"]' "$MITA_USERS_STATE"
user_list_output="$(do_user_list)"
grep -Eq '^alice[[:space:]]+26000[[:space:]]+on[[:space:]]+unlimited[[:space:]]+unlimited[[:space:]]+-' \
  <<<"$user_list_output"

# flock 分支必须传递展示入口字段；重复入口及自定义/自动入口碰撞都应拒绝。
users_set_advertise_endpoint bob 198.51.100.20 8443
test "$(users_get_field bob advertise_host)|$(users_get_field bob advertise_port)" = '198.51.100.20|8443'
users_set_advertise_endpoint bob CM-Entry.Example.com 10086
users_validate_state_file "$MITA_USERS_STATE" TCP 1.2.3.4
test "$(users_get_field bob advertise_host)|$(users_get_field bob advertise_port)" = 'cm-entry.example.com|10086'
users_set_advertise_endpoint bob '' ''
conflict_state=/tmp/users-conflict.json
cp -f "$MITA_USERS_STATE" "$conflict_state"
python3 -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); u=next(x for x in d["users"] if x["name"]=="bob"); u.update({"advertise_host":"203.0.113.10","advertise_port":443}); json.dump(d,open(p,"w"),indent=2)' "$conflict_state"
if users_validate_state_file "$conflict_state" TCP 1.2.3.4; then
  echo "duplicate custom client endpoint unexpectedly accepted" >&2
  exit 1
fi
cp -f "$MITA_USERS_STATE" "$conflict_state"
python3 -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); u=next(x for x in d["users"] if x["name"]=="alice"); u.update({"advertise_host":"1.2.3.4","advertise_port":26005}); json.dump(d,open(p,"w"),indent=2)' "$conflict_state"
if users_validate_state_file "$conflict_state" TCP 1.2.3.4; then
  echo "custom/automatic client endpoint conflict unexpectedly accepted" >&2
  exit 1
fi
rm -f "$conflict_state" "$conflict_state.norm"

# mita perf 必须只读；仅独立入口显示 INFO，同公网 IP/端口不误报。
(
  rm -f /tmp/perf-unexpected-write
  run(){ touch /tmp/perf-unexpected-write; }
  save_install_state(){ touch /tmp/perf-unexpected-write; }
  apply_users_config(){ touch /tmp/perf-unexpected-write; }
  reconcile_isolated_instances(){ touch /tmp/perf-unexpected-write; }
  ensure_mita_daemon(){ touch /tmp/perf-unexpected-write; }
  start_mita(){ touch /tmp/perf-unexpected-write; }
  enable_bbr_fq(){ touch /tmp/perf-unexpected-write; }
  load_install_state(){ :; }
  users_state_exists(){ return 1; }
  installed_version(){ echo 3.35.0; }
  detect_public_ip_family(){ [ "$1" = 4 ] && echo 192.236.242.173 || echo 2606:4700:4700::1111; }
  perf_sysctl_value(){ [ "$1" = net.ipv4.tcp_congestion_control ] && echo bbr || echo fq; }
  tc_default_iface(){ echo eth-test; }
  mtu_iface_value(){ echo 1500; }
  tc(){ echo 'qdisc fq 0: root'; }
  ps(){ printf '1 0.1 1024 mita mita-real run\n'; }
  PORT=17353 PROTOCOL=TCP ADVERTISE_HOST=192.236.242.173 ADVERTISE_PORT=17353
  same_perf_output="$(do_perf)"
  ! grep -q '当前使用独立客户端入口' <<<"$same_perf_output"
  ! grep -q 'An independent client endpoint' <<<"$same_perf_output"

  PORT=30000 PROTOCOL=TCP ADVERTISE_HOST=cm-entry.example.com ADVERTISE_PORT=10086
  perf_output="$(do_perf)"
  grep -q 'Mieru Performance' <<<"$perf_output"
  grep -q 'Backend listen port: 30000' <<<"$perf_output"
  grep -q 'Advertised client address: cm-entry.example.com' <<<"$perf_output"
  grep -q '\[INFO\] 当前使用独立客户端入口' <<<"$perf_output"
  grep -q 'Client: cm-entry.example.com:10086' <<<"$perf_output"
  grep -q 'Backend: 192.236.242.173:30000' <<<"$perf_output"
  ! grep -Eq '\[WARN\].*客户端入口|\[FAIL\].*客户端入口' <<<"$perf_output"
  grep -q '本报告为只读' <<<"$perf_output"
  test ! -e /tmp/perf-unexpected-write
)

# 凭据恢复先使用权威 users.json；只有状态均不可用时才读取最新客户端导出。
(
  MITA_STATE=/tmp/missing-install-state.env
  printf '%s\n' '{"profiles":[{"user":{"name":"stale-user","password":"stale-pass"}}]}' \
    >/root/mieru-clients/current/stale_tcp.json
  USERNAME="" PASSWORD=""
  load_credentials_fallback
  test "$USERNAME|$PASSWORD" = 'alice|alice-pass'
  rm -f /root/mieru-clients/current/stale_tcp.json
)
(
  fallback_dir=/tmp/fallback-client-exports
  rm -rf "$fallback_dir"
  mkdir -p "$fallback_dir/current"
  chmod 0700 "$fallback_dir" "$fallback_dir/current"
  MITA_CLIENT_EXPORT_DIR="$fallback_dir"
  MITA_STATE=/tmp/missing-fallback-install-state.env
  MITA_USERS_STATE=/tmp/missing-fallback-users.json
  printf '%s\n' '{"profiles":[{"user":{"name":"old-user","password":"old-pass"}}]}' \
    >"$fallback_dir/current/old_tcp.json"
  printf '%s\n' '{"profiles":[{"user":{"name":"new-user","password":"new-pass"}}]}' \
    >"$fallback_dir/current/new_tcp.json"
  touch -d '@1' "$fallback_dir/current/old_tcp.json"
  touch -d '@2' "$fallback_dir/current/new_tcp.json"
  USERNAME="" PASSWORD=""
  load_credentials_fallback
  test "$USERNAME|$PASSWORD" = 'new-user|new-pass'
)

# doctor: 无限速用户时规则缺失是正常状态；有限速用户缺规则必须失败。
(
  check(){ printf '%s|%s|%s\n' "$2" "$1" "${3:-}"; }
  users_rate_limited_count(){ echo 0; }
  doctor_tc_output="$(doctor_check_tc_limits)"
  grep -q '^1|rate-limit rules|' <<<"$doctor_tc_output"
  ! grep -q '^0|' <<<"$doctor_tc_output"
)
(
  check(){ printf '%s|%s|%s\n' "$2" "$1" "${3:-}"; }
  users_rate_limited_count(){ echo 1; }
  tc_default_iface(){ echo eth-test; }
  tc(){ :; }
  TC_OWNED_STATE=/tmp/missing-doctor-tc-owned.filters
  rm -f "$TC_OWNED_STATE"
  doctor_tc_output="$(doctor_check_tc_limits)"
  grep -q '^0|clsact|' <<<"$doctor_tc_output"
  grep -q '^0|owned filter manifest|' <<<"$doctor_tc_output"
)

# 状态页只显示运行与监听摘要，不调用 describe config 或暴露密码。
(
  status_bin=/tmp/mock-status-mita
  printf '%s\n' '#!/bin/sh' '[ "${1:-}" = version ] && echo 3.35.0' >"$status_bin"
  chmod 0755 "$status_bin"
  mita_bin(){ echo "$status_bin"; }
  service_manager(){ echo none; }
  users_isolated_mode(){ return 0; }
  users_enabled_instance_rows(){ printf 'u0000000000000001\talice\t26000\n'; }
  load_install_state(){ PROTOCOL=TCP; PASSWORD=alice-pass; }
  instance_cmd(){
    if [ "${2:-}" = status ]; then
      echo 'mita server status is "RUNNING"'
    else
      touch /tmp/status-unexpected-describe
      echo 'password: alice-pass'
    fi
  }
  rm -f /tmp/status-unexpected-describe
  status_output="$(do_status)"
  grep -q 'TCP 26000' <<<"$status_output"
  grep -q '隐藏密码' <<<"$status_output"
  ! grep -q 'alice-pass' <<<"$status_output"
  test ! -e /tmp/status-unexpected-describe
)

# 用真实可执行文件模拟 systemctl，验证包维护脚本只被拦截 mita enable/start。
setup_package_systemctl_mock(){
  local mock_bin="$1"
  rm -rf "$mock_bin"
  mkdir -p "$mock_bin"
  cat >"$mock_bin/systemctl" <<'MOCK_SYSTEMCTL'
#!/bin/sh
printf '%s\n' "$*" >>"$PACKAGE_GUARD_LOG"
case "${1:-}" in
  is-active) [ "${PACKAGE_SERVICE_WAS_ACTIVE:-0}" -eq 1 ] ;;
  *) exit 0 ;;
esac
MOCK_SYSTEMCTL
  chmod 0700 "$mock_bin/systemctl"
  PATH="$mock_bin:$PATH"
  export PATH PACKAGE_GUARD_LOG PACKAGE_SERVICE_WAS_ACTIVE
}

# 原服务未运行时，官方 postinst 可完成，但不得真的 enable/start 默认服务。
(
  PACKAGE_GUARD_LOG=/tmp/package-service-guard.log
  : >"$PACKAGE_GUARD_LOG"
  PACKAGE_SERVICE_WAS_ACTIVE=0
  setup_package_systemctl_mock /tmp/package-systemctl-inactive
  service_manager(){ echo systemd; }
  dpkg(){
    systemctl daemon-reload
    systemctl enable mita.service
    systemctl start mita.service
  }
  mark_oneclick_install(){ :; }
  install_package /tmp/mock-mita.deb deb
  grep -q '^is-active --quiet mita.service$' "$PACKAGE_GUARD_LOG"
  grep -q '^daemon-reload$' "$PACKAGE_GUARD_LOG"
  ! grep -q '^enable mita.service$' "$PACKAGE_GUARD_LOG"
  ! grep -q '^start mita.service$' "$PACKAGE_GUARD_LOG"
)

# 安装前运行中的默认服务必须在包维护脚本结束后恢复一次。
(
  PACKAGE_GUARD_LOG=/tmp/package-service-guard-active.log
  : >"$PACKAGE_GUARD_LOG"
  PACKAGE_SERVICE_WAS_ACTIVE=1
  setup_package_systemctl_mock /tmp/package-systemctl-active
  service_manager(){ echo systemd; }
  dpkg(){
    systemctl enable mita.service
    systemctl start mita.service
  }
  mark_oneclick_install(){ :; }
  install_package /tmp/mock-mita.deb deb
  test "$(grep -c '^start mita.service$' "$PACKAGE_GUARD_LOG")" -eq 1
  ! grep -q '^enable mita.service$' "$PACKAGE_GUARD_LOG"
)

# dpkg 首次失败后，apt-get -f 继承相同代理并可完成半安装修复。
(
  PACKAGE_GUARD_LOG=/tmp/package-service-guard-apt-repair.log
  : >"$PACKAGE_GUARD_LOG"
  PACKAGE_SERVICE_WAS_ACTIVE=0
  setup_package_systemctl_mock /tmp/package-systemctl-apt-repair
  service_manager(){ echo systemd; }
  dpkg(){ return 1; }
  apt-get(){
    systemctl daemon-reload
    systemctl enable mita.service
    systemctl start mita.service
    touch /tmp/package-apt-repair-complete
    return 0
  }
  mark_oneclick_install(){ :; }
  rm -f /tmp/package-apt-repair-complete
  install_package /tmp/mock-mita.deb deb
  test -e /tmp/package-apt-repair-complete
  grep -q '^daemon-reload$' "$PACKAGE_GUARD_LOG"
  ! grep -q '^enable mita.service$' "$PACKAGE_GUARD_LOG"
  ! grep -q '^start mita.service$' "$PACKAGE_GUARD_LOG"
)

# dpkg --configure -a 自愈路径也必须使用代理，并在结束后删除临时目录。
(
  PACKAGE_GUARD_LOG=/tmp/package-service-guard-configure.log
  : >"$PACKAGE_GUARD_LOG"
  PACKAGE_SERVICE_WAS_ACTIVE=0
  setup_package_systemctl_mock /tmp/package-systemctl-configure
  service_manager(){ echo systemd; }
  dpkg(){
    test "$*" = '--configure -a'
    dirname "$(type -P systemctl)" >/tmp/package-configure-guard-dir
    systemctl enable mita.service
    systemctl start mita.service
  }
  configure_pending_deb_packages
  test ! -d "$(cat /tmp/package-configure-guard-dir)"
  ! grep -q '^enable mita.service$' "$PACKAGE_GUARD_LOG"
  ! grep -q '^start mita.service$' "$PACKAGE_GUARD_LOG"
)

# 安装失败也必须恢复旧服务并清理代理目录。
(
  PACKAGE_GUARD_LOG=/tmp/package-service-guard-failure.log
  : >"$PACKAGE_GUARD_LOG"
  PACKAGE_SERVICE_WAS_ACTIVE=1
  setup_package_systemctl_mock /tmp/package-systemctl-failure
  service_manager(){ echo systemd; }
  dpkg(){
    dirname "$(type -P systemctl)" >/tmp/package-failure-guard-dir
    return 1
  }
  apt-get(){ return 1; }
  MENU_MODE=1
  if install_package /tmp/mock-mita.deb deb >/dev/null 2>&1; then
    echo "failed package install unexpectedly succeeded" >&2
    exit 1
  fi
  test ! -d "$(cat /tmp/package-failure-guard-dir)"
  grep -q '^start mita.service$' "$PACKAGE_GUARD_LOG"
)

# 找不到真实 systemctl 时必须在调用包管理器前失败。
(
  PACKAGE_GUARD_LOG=/tmp/package-service-guard-setup-failure.log
  : >"$PACKAGE_GUARD_LOG"
  empty_path=/tmp/package-empty-path
  rm -rf "$empty_path"
  mkdir -p "$empty_path"
  rm -f /tmp/package-unexpected-dpkg
  PATH="$empty_path"
  export PATH
  service_manager(){ echo systemd; }
  dpkg(){ : >/tmp/package-unexpected-dpkg; }
  MENU_MODE=1
  if install_package /tmp/mock-mita.deb deb >/dev/null 2>&1; then
    echo "package install unexpectedly continued without real systemctl" >&2
    exit 1
  fi
  test ! -e /tmp/package-unexpected-dpkg
)

# 独立修改用户展示入口只更新状态，不应用或重启任何服务端实例。
(
  endpoint_state_dir=/tmp/endpoint-only-state
  rm -rf "$endpoint_state_dir"
  mkdir -p "$endpoint_state_dir"
  chmod 0700 "$endpoint_state_dir"
  MITA_STATE="$endpoint_state_dir/install-state.env"
  MITA_USERS_STATE="$endpoint_state_dir/users.json"
  MITA_USERS_LOCK="$endpoint_state_dir/users.lock"
  MITA_ADMIN_LOCK="$endpoint_state_dir/admin.lock"
  cp -f /tmp/manager-state/install-state.env "$MITA_STATE"
  cp -f /tmp/manager-state/users.json "$MITA_USERS_STATE"
  chmod 0600 "$MITA_STATE" "$MITA_USERS_STATE"
  apply_users_config(){ touch /tmp/endpoint-unexpected-apply; }
  instance_start_proxy(){ touch /tmp/endpoint-unexpected-start; }
  isolated_stop_all(){ touch /tmp/endpoint-unexpected-stop; }
  print_user_outputs(){ :; }
  rm -f /tmp/endpoint-unexpected-apply /tmp/endpoint-unexpected-start /tmp/endpoint-unexpected-stop
  USERNAME=bob ADVERTISE_HOST=cm-entry.example.com ADVERTISE_PORT=9443 ADVERTISE_CLI=1
  do_user_set_endpoint >/dev/null
  test "$(users_get_field bob advertise_host)|$(users_get_field bob advertise_port)" = 'cm-entry.example.com|9443'
  test ! -e /tmp/endpoint-unexpected-apply
  test ! -e /tmp/endpoint-unexpected-start
  test ! -e /tmp/endpoint-unexpected-stop
)

# 无 systemd 的容器中模拟实例控制，仅保留真实的单实例 JSON 生成和事务逻辑。
install_instance_runtime(){
  mkdir -p "$MITA_INSTANCES_DIR" "$MITA_INSTANCE_RUN_DIR" "$MITA_INSTANCE_METRICS_DIR"
  chown -R mita:mita "$MITA_INSTANCES_DIR" "$MITA_INSTANCE_RUN_DIR" "$MITA_INSTANCE_METRICS_DIR"
}
instance_ensure_openrc_service(){ :; }
default_mita_stop(){ :; }
default_mita_restore(){ :; }
FAIL_INSTANCE_ONCE=0
instance_start_proxy(){
  if [ "$FAIL_INSTANCE_ONCE" -eq 1 ]; then
    FAIL_INSTANCE_ONCE=0
    return 1
  fi
  return 0
}
instance_daemon_stop(){ :; }
instance_cmd(){
  local iid="$1" cmd="$2"
  case "$cmd" in
    status) echo 'mita server status is "RUNNING"' ;;
    get) echo "metrics ${iid}" ;;
    export) echo CCoQARoECAEQCg== ;;
    *) : ;;
  esac
}
harden_mita_permissions(){ :; }
TC_LOG=/tmp/tc.log
: >"$TC_LOG"
TC_FAIL_ONCE=0
tc(){
  printf '%s\n' "$*" >>"$TC_LOG"
  case "$*" in
    "qdisc show"*) echo 'qdisc clsact ffff: dev eth-test' ;;
    *"filter add"*)
      if [ "$TC_FAIL_ONCE" -eq 1 ]; then TC_FAIL_ONCE=0; return 1; fi
      ;;
  esac
  return 0
}

# 首次安装直接创建 isolated-v2，不应用或启动旧默认单实例。
(
  fresh=/tmp/fresh-isolated
  rm -rf "$fresh"
  mkdir -p "$fresh/backups" "$fresh/instances" "$fresh/run" "$fresh/metrics"
  chmod 0700 "$fresh" "$fresh/backups"
  MITA_MANAGER_STATE_DIR="$fresh"
  MITA_STATE="$fresh/install-state.env"
  MITA_USERS_STATE="$fresh/users.json"
  MITA_USERS_LOCK="$fresh/users.lock"
  MITA_ADMIN_LOCK="$fresh/admin.lock"
  MITA_USERS_BACKUP_DIR="$fresh/backups"
  MITA_INSTANCES_DIR="$fresh/instances"
  MITA_INSTANCE_RUN_DIR="$fresh/run"
  MITA_INSTANCE_METRICS_DIR="$fresh/metrics"
  MITA_CLIENT_EXPORT_DIR="$fresh/clients"
  TC_OWNED_STATE="$fresh/tc-owned.filters"
  USERNAME=fresh-user PASSWORD=fresh-pass PORT=26100 PORT_RANGE="" PROTOCOL=TCP
  ADVERTISE_HOST="" ADVERTISE_PORT="" MTU=1400 MTU_POLICY=safe
  TRAFFIC_PATTERN=off TRAFFIC_SEED="" LOW_ENTROPY_MODE=LOW_ENTROPY_MODE_OFF
  MULTIPLEXING=MULTIPLEXING_OFF HANDSHAKE_MODE=HANDSHAKE_NO_WAIT
  install_self_script(){ :; }
  install_users_scheduler(){ :; }
  open_firewall_for_pairs(){ touch /tmp/fresh-firewall-opened; }
  close_firewall_for_bindings(){ :; }
  default_mita_stop(){ touch /tmp/fresh-default-stopped; }
  default_mita_restore(){ touch /tmp/fresh-unexpected-default-restore; }
  apply_config(){ touch /tmp/fresh-unexpected-default-apply; }
  start_mita(){ touch /tmp/fresh-unexpected-default-start; }
  rm -f /tmp/fresh-firewall-opened /tmp/fresh-default-stopped \
    /tmp/fresh-unexpected-default-restore /tmp/fresh-unexpected-default-apply \
    /tmp/fresh-unexpected-default-start
  install_fresh_isolated
  test "$(users_deployment_model)" = isolated-v2
  test "$(users_count)" -eq 1
  test -e /tmp/fresh-firewall-opened
  test -e /tmp/fresh-default-stopped
  test ! -e /tmp/fresh-unexpected-default-restore
  test ! -e /tmp/fresh-unexpected-default-apply
  test ! -e /tmp/fresh-unexpected-default-start
)

# 首次安装的专属实例启动失败时，不得恢复从未启用的默认服务，并清理运行时资源。
(
  fresh=/tmp/fresh-isolated-failure
  rm -rf "$fresh"
  mkdir -p "$fresh/backups" "$fresh/instances" "$fresh/run" "$fresh/metrics"
  chmod 0700 "$fresh" "$fresh/backups"
  MITA_MANAGER_STATE_DIR="$fresh"
  MITA_STATE="$fresh/install-state.env"
  MITA_USERS_STATE="$fresh/users.json"
  MITA_USERS_LOCK="$fresh/users.lock"
  MITA_ADMIN_LOCK="$fresh/admin.lock"
  MITA_USERS_BACKUP_DIR="$fresh/backups"
  MITA_INSTANCES_DIR="$fresh/instances"
  MITA_INSTANCE_RUN_DIR="$fresh/run"
  MITA_INSTANCE_METRICS_DIR="$fresh/metrics"
  MITA_CLIENT_EXPORT_DIR="$fresh/clients"
  TC_OWNED_STATE="$fresh/tc-owned.filters"
  USERNAME=fresh-fail PASSWORD=fresh-pass PORT=26110 PORT_RANGE="" PROTOCOL=TCP
  ADVERTISE_HOST="" ADVERTISE_PORT="" MTU=1400 MTU_POLICY=safe
  TRAFFIC_PATTERN=off TRAFFIC_SEED="" LOW_ENTROPY_MODE=LOW_ENTROPY_MODE_OFF
  MULTIPLEXING=MULTIPLEXING_OFF HANDSHAKE_MODE=HANDSHAKE_NO_WAIT
  install_self_script(){ :; }
  install_users_scheduler(){ touch /tmp/fresh-fail-scheduler-created; }
  remove_users_scheduler(){ touch /tmp/fresh-fail-scheduler-removed; }
  instance_start_proxy(){ return 1; }
  instance_daemon_stop(){ touch /tmp/fresh-fail-instance-stopped; }
  default_mita_stop(){ touch /tmp/fresh-fail-default-stopped; }
  default_mita_restore(){ touch /tmp/fresh-fail-unexpected-default-restore; }
  open_firewall_for_pairs(){ touch /tmp/fresh-fail-unexpected-firewall; }
  tc_clear_owned_filters(){ touch /tmp/fresh-fail-tc-cleared; }
  rm -f /tmp/fresh-fail-*
  MENU_MODE=1
  if install_fresh_isolated >/dev/null 2>&1; then
    echo "failed fresh isolated install unexpectedly succeeded" >&2
    exit 1
  fi
  test ! -e "$MITA_USERS_STATE"
  test -e /tmp/fresh-fail-default-stopped
  test -e /tmp/fresh-fail-instance-stopped
  test -e /tmp/fresh-fail-scheduler-created
  test -e /tmp/fresh-fail-scheduler-removed
  test -e /tmp/fresh-fail-tc-cleared
  test ! -e /tmp/fresh-fail-unexpected-default-restore
  test ! -e /tmp/fresh-fail-unexpected-firewall
)

apply_users_config
test "$(users_deployment_model)" = isolated-v2
python3 - <<'PY'
import glob,json
files=glob.glob("/tmp/instances/*/server.json")
assert len(files)==2
for path in files:
    d=json.load(open(path))
    assert len(d["users"])==1
    assert len(d["portBindings"])==1
    assert "trafficPattern" not in d
PY
TRAFFIC_PATTERN=conservative TRAFFIC_SEED=42 LOW_ENTROPY_MODE=LOW_ENTROPY_MODE_OFF
apply_users_config
python3 -c 'import glob,json; assert all("trafficPattern" in json.load(open(p)) for p in glob.glob("/tmp/instances/*/server.json"))'
TRAFFIC_PATTERN=off
apply_users_config
python3 -c 'import glob,json; assert all("trafficPattern" not in json.load(open(p)) for p in glob.glob("/tmp/instances/*/server.json"))'

setup_reconfigure_fixture(){
  local fixture="$1"
  rm -rf "$fixture"
  mkdir -p "$fixture/backups" "$fixture/clients/current"
  chmod 0700 "$fixture" "$fixture/backups" "$fixture/clients" "$fixture/clients/current"
  MITA_STATE="$fixture/install-state.env"
  MITA_USERS_STATE="$fixture/users.json"
  MITA_USERS_LOCK="$fixture/users.lock"
  MITA_ADMIN_LOCK="$fixture/admin.lock"
  MITA_USERS_BACKUP_DIR="$fixture/backups"
  MITA_CLIENT_EXPORT_DIR="$fixture/clients"
  cp -f /tmp/manager-state/install-state.env "$MITA_STATE"
  cp -f /tmp/manager-state/users.json "$MITA_USERS_STATE"
  chmod 0600 "$MITA_STATE" "$MITA_USERS_STATE"
}

# 完全无变化时必须明确报告 no-op，且不应用服务端配置。
(
  setup_reconfigure_fixture /tmp/reconfigure-noop
  collect_reconfigure_interactive(){ :; }
  apply_users_config(){ touch /tmp/reconfigure-noop-unexpected-apply; }
  print_summary(){ :; }
  rm -f /tmp/reconfigure-noop-unexpected-apply
  reconfigure_output="$(do_reconfigure)"
  grep -q '未检测到配置变化' <<<"$reconfigure_output"
  test ! -e /tmp/reconfigure-noop-unexpected-apply
)

# 客户端全局模式变化不重启服务，但必须失效所有用户的旧导出。
(
  setup_reconfigure_fixture /tmp/reconfigure-client-only
  printf stale >"$(client_current_dir)/alice_tcp.json"
  printf stale >"$(client_current_dir)/bob_tcp.json"
  collect_reconfigure_interactive(){ MULTIPLEXING=MULTIPLEXING_LOW; }
  apply_users_config(){ touch /tmp/reconfigure-client-unexpected-apply; }
  print_summary(){ :; }
  rm -f /tmp/reconfigure-client-unexpected-apply
  reconfigure_output="$(do_reconfigure)"
  grep -q '仅客户端参数已更新' <<<"$reconfigure_output"
  grep -qx 'MULTIPLEXING=MULTIPLEXING_LOW' "$MITA_STATE"
  test -z "$(find "$(client_current_dir)" -maxdepth 1 -type f -name '*.json' -print -quit)"
  test ! -e /tmp/reconfigure-client-unexpected-apply
)

# 应用 Profile 时保存完整真实参数；不是在运行时只保存/推算 PROFILE。
(
  setup_reconfigure_fixture /tmp/reconfigure-profile
  apply_profile_values iplc
  PROFILE_CLI=1 PROTOCOL_CLI=1 MTU_CLI=1 MULTIPLEXING_CLI=1
  HANDSHAKE_CLI=1 TRAFFIC_CLI=1 LOW_ENTROPY_CLI=1
  MTU_REQUEST=1400 YES=1
  print_summary(){ :; }
  do_reconfigure >/dev/null
  grep -qx 'PROFILE=iplc' "$MITA_STATE"
  grep -qx 'PROTOCOL=TCP' "$MITA_STATE"
  grep -qx 'MTU=1400' "$MITA_STATE"
  grep -qx 'MULTIPLEXING=MULTIPLEXING_OFF' "$MITA_STATE"
  grep -qx 'HANDSHAKE_MODE=HANDSHAKE_NO_WAIT' "$MITA_STATE"
  grep -qx 'TRAFFIC_PATTERN=off' "$MITA_STATE"
  grep -qx 'LOW_ENTROPY_MODE=LOW_ENTROPY_MODE_OFF' "$MITA_STATE"
)

# 主用户名变化只清理旧主用户导出，不删除其它用户仍有效的文件。
(
  setup_reconfigure_fixture /tmp/reconfigure-rename
  printf stale >"$(client_current_dir)/alice_tcp.json"
  printf keep >"$(client_current_dir)/bob_tcp.json"
  collect_reconfigure_interactive(){ USERNAME=alice-renamed; }
  apply_users_config(){ :; }
  print_summary(){ :; }
  reconfigure_output="$(do_reconfigure)"
  grep -q '重新配置完成' <<<"$reconfigure_output"
  users_name_exists alice-renamed
  test ! -e "$(client_current_dir)/alice_tcp.json"
  test -f "$(client_current_dir)/bob_tcp.json"
)

# MTU 是全局参数，数值变化后必须失效所有用户的稳定导出。
(
  setup_reconfigure_fixture /tmp/mtu-global-invalidation
  printf stale >"$(client_current_dir)/alice_tcp.json"
  printf stale >"$(client_current_dir)/bob_tcp.json"
  choose_mtu_interactive(){ MTU=1390; MTU_POLICY=custom; }
  reconcile_isolated_instances(){ :; }
  verify_mita_running(){ return 0; }
  generate_client_config(){ :; }
  do_mtu_config >/dev/null
  grep -qx 'MTU=1390' "$MITA_STATE"
  test -z "$(find "$(client_current_dir)" -maxdepth 1 -type f -name '*.json' -print -quit)"
)

# 改端口不能改变实例 ID，也不能丢失专属 metrics。
bob_id="$(users_get_field bob instance_id)"
mkdir -p "$(instance_metrics_dir "$bob_id")"
printf bob-usage >"$(instance_metrics_file "$bob_id")"
_U_NAME=bob _U_PORT=26006 users_py_locked '
import json,os
p=os.environ["MITA_USERS_STATE"]; d=json.load(open(p))
next(u for u in d["users"] if u["name"]==os.environ["_U_NAME"])["port"]=int(os.environ["_U_PORT"])
json.dump(d,open(p,"w"),indent=2)
'
apply_users_config
test "$(users_get_field bob instance_id)" = "$bob_id"
grep -q bob-usage "$(instance_metrics_file "$bob_id")"
python3 -c 'import json,glob; p=glob.glob("/tmp/instances/*/server.json"); d=next(json.load(open(x)) for x in p if json.load(open(x))["users"][0]["name"]=="bob"); assert d["portBindings"][0]["port"]==26006'

# 应用失败必须恢复 users.json，并能重新生成旧实例配置。
before="$(sha256sum "$MITA_USERS_STATE" | awk '{print $1}')"
tx="$(users_tx_snapshot)"
users_del bob >/dev/null
FAIL_INSTANCE_ONCE=1
if apply_users_config "$tx" >/dev/null 2>&1; then
  echo "failed instance reconcile unexpectedly succeeded" >&2
  exit 1
fi
after="$(sha256sum "$MITA_USERS_STATE" | awk '{print $1}')"
test "$before" = "$after"
users_name_exists bob
grep -q bob-usage "$(instance_metrics_file "$bob_id")"
# apply 已消费回滚快照；外层重复调用必须幂等且不再报回滚失败。
users_tx_rollback "$tx" 0

# 不在状态中的实例数据只能在事务提交阶段清理。
orphan_id=u0000000000000001
mkdir -p "$MITA_INSTANCES_DIR/$orphan_id" "$(instance_metrics_dir "$orphan_id")"
printf orphan-usage >"$(instance_metrics_file "$orphan_id")"
orphan_tx="$(users_tx_snapshot)"
users_tx_commit "$orphan_tx"
test ! -d "$(instance_metrics_dir "$orphan_id")"
test ! -d "$MITA_INSTANCES_DIR/$orphan_id"

# 恢复必须采用备份内协议，并同时更新实例配置与 install-state。
cp -f "$MITA_USERS_STATE" /tmp/users-import.json
python3 -c 'import json; p="/tmp/users-import.json"; d=json.load(open(p)); d["protocol"]="UDP"; json.dump(d,open(p,"w"),indent=2)'
mkdir -p /root/mieru-clients/current
printf stale > /root/mieru-clients/current/alice_tcp.json
printf stale > /root/mieru-clients/current/removed-user_udp.json
users_restore_from_file /tmp/users-import.json >/dev/null
test "$PROTOCOL" = UDP
grep -qx 'PROTOCOL=UDP' "$MITA_STATE"
test -z "$(find /root/mieru-clients/current -maxdepth 1 -type f -name '*.json' -print -quit)"
python3 - <<'PY'
import glob,json
for path in glob.glob("/tmp/instances/*/server.json"):
    d=json.load(open(path))
    assert {x["protocol"] for x in d["portBindings"]} == {"UDP"}
PY
python3 -c 'import json; p="/tmp/users-import.json"; d=json.load(open(p)); d["protocol"]="INVALID"; json.dump(d,open(p,"w"),indent=2)'
if users_restore_from_file /tmp/users-import.json >/dev/null 2>&1; then
  echo "invalid imported protocol unexpectedly succeeded" >&2
  exit 1
fi

# calendar 只清 bob 的 metrics，不影响 alice。
alice_id="$(users_get_field alice instance_id)"
mkdir -p "$(instance_metrics_dir "$alice_id")" "$(instance_metrics_dir "$bob_id")"
printf alice-usage >"$(instance_metrics_file "$alice_id")"
printf bob-usage >"$(instance_metrics_file "$bob_id")"
python3 -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); u=next(x for x in d["users"] if x["name"]=="bob"); u.update({"quota_mode":"calendar","quota_mb":1024,"quota_days":30,"last_quota_reset":"2020-01"}); json.dump(d,open(p,"w"),indent=2)' "$MITA_USERS_STATE"
cal="$(users_scan_calendar_quota_reset)"
grep -qx bob <<<"$cal"
test ! -e "$(instance_metrics_file "$bob_id")"
grep -q alice-usage "$(instance_metrics_file "$alice_id")"

# 菜单路径传入的目标账号不能被 load_install_state 覆盖成主账号。
USERNAME=bob USER_PACKAGE=unlimited USER_QUOTA_MB="" USER_QUOTA_DAYS=""
USER_QUOTA_MODE=rolling USER_EXPIRE="" USER_BANDWIDTH_MBPS=""
do_user_set_quota >/dev/null
test "$(users_get_field bob quota_mb)" = 0

# 使用假 tc 验证仅管理保留 pref 的 filter，失败会恢复旧 manifest，且从不删除 qdisc。
: >"$TC_LOG"
PROTOCOL=TCP
apply_tc_limits
test -s "$TC_OWNED_STATE"
! grep -Eq 'qdisc (del|replace)|root handle' "$TC_LOG"
tc_before="$(sha256sum "$TC_OWNED_STATE" | awk '{print $1}')"
TC_FAIL_ONCE=1
if apply_tc_limits >/dev/null 2>&1; then
  echo "injected tc failure unexpectedly succeeded" >&2
  exit 1
fi
tc_after="$(sha256sum "$TC_OWNED_STATE" | awk '{print $1}')"
test "$tc_before" = "$tc_after"
! grep -Eq 'qdisc (del|replace)|root handle' "$TC_LOG"

# 防火墙只删除带所有权记录的规则；预先存在的同端口规则不得接管或删除。
MITA_FIREWALL_OWNED_STATE=/tmp/firewall-owned.bindings
FW_LOG=/tmp/firewall.log
: >"$FW_LOG"
IPT_PREEXIST=0
IPT_OWNED_EXISTS=0
IPT_DELETE_FAIL=0
iptables(){
  printf 'v4 %s\n' "$*" >>"$FW_LOG"
  case "$*" in
    "-C "*"--comment"*) [ "$IPT_OWNED_EXISTS" -eq 1 ] && return 0 || return 1 ;;
    "-C "*) [ "$IPT_PREEXIST" -eq 1 ] && return 0 || return 1 ;;
    "-I "*"--comment"*) IPT_OWNED_EXISTS=1; return 0 ;;
    "-D "*"--comment"*)
      [ "$IPT_DELETE_FAIL" -eq 1 ] && return 1
      IPT_OWNED_EXISTS=0
      return 0
      ;;
  esac
  return 0
}
ip6tables(){
  printf 'v6 %s\n' "$*" >>"$FW_LOG"
  case "$*" in
    "-C "*"--comment"*) [ "$IPT_OWNED_EXISTS" -eq 1 ] && return 0 || return 1 ;;
    "-C "*) [ "$IPT_PREEXIST" -eq 1 ] && return 0 || return 1 ;;
    "-I "*"--comment"*) IPT_OWNED_EXISTS=1; return 0 ;;
    "-D "*"--comment"*)
      [ "$IPT_DELETE_FAIL" -eq 1 ] && return 1
      IPT_OWNED_EXISTS=0
      return 0
      ;;
  esac
  return 0
}
iptables_accept_port 28000 tcp add
test "$(wc -l <"$MITA_FIREWALL_OWNED_STATE")" -eq 2
grep -q -- '--comment mieru-oneclick' "$FW_LOG"
iptables_accept_port 28000 tcp del
test ! -e "$MITA_FIREWALL_OWNED_STATE"
: >"$FW_LOG"
IPT_PREEXIST=1
iptables_accept_port 28001 tcp add
test ! -e "$MITA_FIREWALL_OWNED_STATE"
! grep -q ' -I ' "$FW_LOG"
iptables_accept_port 28001 tcp del
! grep -q ' -D ' "$FW_LOG"
# 删除失败时必须保留所有权清单并让卸载失败；重试成功后才能清掉清单。
IPT_PREEXIST=0
IPT_OWNED_EXISTS=1
IPT_DELETE_FAIL=1
printf 'iptables|tcp|28002\nip6tables|tcp|28002\n' >"$MITA_FIREWALL_OWNED_STATE"
if firewall_clear_all_owned >/dev/null 2>&1; then
  echo "failed firewall cleanup unexpectedly succeeded" >&2
  exit 1
fi
test "$(wc -l <"$MITA_FIREWALL_OWNED_STATE")" -eq 2
IPT_DELETE_FAIL=0
firewall_clear_all_owned
test ! -e "$MITA_FIREWALL_OWNED_STATE"

# 全部用户同时到期必须停掉全部实例，不能因“最后一个用户”保护而回滚为继续可用。
today="$(date +%F)"
python3 -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); [u.update({"enabled":True,"expire_at":sys.argv[2]}) for u in d["users"]]; json.dump(d,open(p,"w"),indent=2)' "$MITA_USERS_STATE" "$today"
expired="$(users_scan_expired)"
grep -qx alice <<<"$expired"
grep -qx bob <<<"$expired"
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d["users"] and not any(u["enabled"] for u in d["users"])' "$MITA_USERS_STATE"
python3 -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); next(u for u in d["users"] if u["name"]=="alice")["expire_at"]=""; json.dump(d,open(p,"w"),indent=2)' "$MITA_USERS_STATE"
USER_SHOW_NAME=alice
do_user_enable >/dev/null
test "$(users_get_field alice enabled)" = 1
grep -qx 'USERNAME=alice' "$MITA_STATE"
grep -qx 'ADVERTISE_HOST=203.0.113.10' "$MITA_STATE"
grep -qx 'ADVERTISE_PORT=443' "$MITA_STATE"

# 删除用户后只清理该用户的稳定客户端导出。
mkdir -p /root/mieru-clients/current
printf keep > /root/mieru-clients/current/alice_tcp.json
printf stale > /root/mieru-clients/current/bob_tcp.json
printf stale > /root/mieru-clients/current/bob_udp.json
USER_DEL_NAME=bob YES=1
do_user_del >/dev/null
test -f /root/mieru-clients/current/alice_tcp.json
test ! -e /root/mieru-clients/current/bob_tcp.json
test ! -e /root/mieru-clients/current/bob_udp.json

# 静态安全边界：双栈防火墙、私有 metrics 挂载和稳定实例环境变量。
grep -q 'for ipt in iptables ip6tables' /work/install-mita.sh
grep -q 'BindPaths=.*MITA_INSTANCE_METRICS_DIR' /work/install-mita.sh
grep -q 'MITA_CONFIG_JSON_FILE=' /work/install-mita.sh
grep -q 'MITA_UDS_PATH=' /work/install-mita.sh
grep -Fq 'run chown root:mita "$MITA_INSTANCES_DIR"' /work/install-mita.sh
! grep -q 'enable_tcp_bbr.py' /work/install-mita.sh
perm_root=/tmp/instance-permission
mkdir -p "$perm_root/u0000000000000002"
chown root:mita "$perm_root"
chown mita:mita "$perm_root/u0000000000000002"
chmod 0750 "$perm_root" "$perm_root/u0000000000000002"
printf '{}' >"$perm_root/u0000000000000002/server.json"
chown mita:mita "$perm_root/u0000000000000002/server.json"
chmod 0600 "$perm_root/u0000000000000002/server.json"
setpriv --reuid=mita --regid=mita --init-groups \
  test -r "$perm_root/u0000000000000002/server.json"

# isolated-v2 卸载只停止专属实例，不调用已停用的默认 mita daemon。
(
  mock_mita=/tmp/mock-default-mita
  printf '%s\n' '#!/bin/sh' 'touch /tmp/unexpected-default-mita-stop' >"$mock_mita"
  chmod 0755 "$mock_mita"
  mita_bin(){ echo "$mock_mita"; }
  users_isolated_mode(){ return 0; }
  isolated_stop_all(){ touch /tmp/isolated-stop-called; }
  tc_clear_owned_filters(){ :; }
  service_manager(){ echo none; }
  rm -f /tmp/unexpected-default-mita-stop /tmp/isolated-stop-called
  stop_mita_for_uninstall
  test -e /tmp/isolated-stop-called
  test ! -e /tmp/unexpected-default-mita-stop
)

# BBR + FQ 已完整启用时不询问；缺项时回车默认执行本地配置。
(
  bbr_fq_enabled(){ return 0; }
  confirm(){ touch /tmp/bbr-unexpected-confirm; return 1; }
  enable_bbr_fq(){ touch /tmp/bbr-unexpected-enable; }
  rm -f /tmp/bbr-unexpected-confirm /tmp/bbr-unexpected-enable
  offer_bbr_fq >/dev/null
  test ! -e /tmp/bbr-unexpected-confirm
  test ! -e /tmp/bbr-unexpected-enable
)
(
  bbr_fq_enabled(){ return 1; }
  read_tty(){ printf -v "$1" '%s' ''; }
  enable_bbr_fq(){ touch /tmp/bbr-default-enable; }
  rm -f /tmp/bbr-default-enable
  ENABLE_BBR=0 YES=0
  offer_bbr_fq >/dev/null
  test -e /tmp/bbr-default-enable
)

# 本地实现写入固定 sysctl；卸载只恢复脚本接管的文件和运行值。
(
  BBR_SYSCTL_CONF=/tmp/mieru_tcp_bbr.conf
  BBR_STATE_FILE=/tmp/manager-state/bbr-created.state
  BBR_BACKUP_FILE=/tmp/manager-state/bbr-created.backup
  test_qdisc=pfifo_fast
  test_cc=cubic
  sysctl(){
    case "${1:-}|${2:-}" in
      '-n|net.core.default_qdisc') printf '%s\n' "$test_qdisc" ;;
      '-n|net.ipv4.tcp_congestion_control') printf '%s\n' "$test_cc" ;;
      '-n|net.ipv4.tcp_available_congestion_control') printf '%s\n' 'reno cubic bbr' ;;
      '-p|'*) test_qdisc=fq; test_cc=bbr ;;
      '-q|-w')
        case "${3:-}" in
          net.core.default_qdisc=*) test_qdisc="${3#*=}" ;;
          net.ipv4.tcp_congestion_control=*) test_cc="${3#*=}" ;;
        esac
        ;;
      *) return 1 ;;
    esac
  }
  modprobe(){ :; }
  rm -f "$BBR_SYSCTL_CONF" "$BBR_STATE_FILE" "$BBR_BACKUP_FILE"
  enable_bbr_fq >/dev/null
  bbr_fq_enabled
  grep -qx 'net.core.default_qdisc=fq' "$BBR_SYSCTL_CONF"
  grep -qx 'net.ipv4.tcp_congestion_control=bbr' "$BBR_SYSCTL_CONF"
  grep -qx created "$BBR_STATE_FILE"
  restore_owned_bbr_fq
  test ! -e "$BBR_SYSCTL_CONF"
  test ! -e "$BBR_STATE_FILE"
  test "$test_qdisc|$test_cc" = 'pfifo_fast|cubic'
)
(
  BBR_SYSCTL_CONF=/tmp/mieru_tcp_bbr-existing.conf
  BBR_STATE_FILE=/tmp/manager-state/bbr-replaced.state
  BBR_BACKUP_FILE=/tmp/manager-state/bbr-replaced.backup
  test_qdisc=fq_codel
  test_cc=cubic
  sysctl(){
    case "${1:-}|${2:-}" in
      '-n|net.core.default_qdisc') printf '%s\n' "$test_qdisc" ;;
      '-n|net.ipv4.tcp_congestion_control') printf '%s\n' "$test_cc" ;;
      '-n|net.ipv4.tcp_available_congestion_control') printf '%s\n' 'reno cubic bbr' ;;
      '-p|'*)
        while IFS='=' read -r key value; do
          case "$key" in
            net.core.default_qdisc) test_qdisc="$value" ;;
            net.ipv4.tcp_congestion_control) test_cc="$value" ;;
          esac
        done <"${2:-$BBR_SYSCTL_CONF}"
        ;;
      '-q|-w')
        case "${3:-}" in
          net.core.default_qdisc=*) test_qdisc="${3#*=}" ;;
          net.ipv4.tcp_congestion_control=*) test_cc="${3#*=}" ;;
        esac
        ;;
      *) return 1 ;;
    esac
  }
  modprobe(){ :; }
  rm -f "$BBR_STATE_FILE" "$BBR_BACKUP_FILE"
  printf '%s\n' 'net.core.default_qdisc=fq_codel' '# keep this original file' >"$BBR_SYSCTL_CONF"
  original_hash="$(sha256sum "$BBR_SYSCTL_CONF" | awk '{print $1}')"
  enable_bbr_fq >/dev/null
  grep -qx replaced "$BBR_STATE_FILE"
  restore_owned_bbr_fq
  test "$(sha256sum "$BBR_SYSCTL_CONF" | awk '{print $1}')" = "$original_hash"
  test "$test_qdisc|$test_cc" = 'fq_codel|cubic'
  test ! -e "$BBR_STATE_FILE"
)
(
  BBR_SYSCTL_CONF=/tmp/mieru_tcp_bbr-external.conf
  BBR_STATE_FILE=/tmp/manager-state/bbr-external.state
  BBR_BACKUP_FILE=/tmp/manager-state/bbr-external.backup
  printf '%s\n' 'net.core.default_qdisc=fq' 'net.ipv4.tcp_congestion_control=bbr' >"$BBR_SYSCTL_CONF"
  write_bbr_state created pfifo_fast cubic
  printf '%s\n' '# changed by administrator' 'net.core.default_qdisc=fq_codel' >"$BBR_SYSCTL_CONF"
  if restore_owned_bbr_fq >/dev/null 2>&1; then
    echo "externally modified BBR config unexpectedly overwritten during uninstall" >&2
    exit 1
  fi
  grep -qx '# changed by administrator' "$BBR_SYSCTL_CONF"
  test -e "$BBR_STATE_FILE"
  rm -f "$BBR_SYSCTL_CONF" "$BBR_STATE_FILE" "$BBR_BACKUP_FILE"
)
(
  BBR_SYSCTL_CONF=/tmp/mieru_tcp_bbr-uninstall-guard.conf
  BBR_STATE_FILE=/tmp/manager-state/bbr-uninstall-guard.state
  BBR_BACKUP_FILE=/tmp/manager-state/bbr-uninstall-guard.backup
  printf '%s\n' 'net.core.default_qdisc=fq' 'net.ipv4.tcp_congestion_control=bbr' >"$BBR_SYSCTL_CONF"
  write_bbr_state created pfifo_fast cubic
  printf '%s\n' '# changed by administrator' >"$BBR_SYSCTL_CONF"
  mita_uninstall_target_present(){ return 0; }
  installed_by_oneclick(){ return 0; }
  confirm(){ return 0; }
  stop_mita_for_uninstall(){ touch /tmp/bbr-guard-unexpected-stop; }
  rm -f /tmp/bbr-guard-unexpected-stop
  set +e
  (set -Eeuo pipefail; do_uninstall >/dev/null 2>&1)
  guarded_uninstall_rc=$?
  set -e
  test "$guarded_uninstall_rc" -ne 0
  test ! -e /tmp/bbr-guard-unexpected-stop
  rm -f "$BBR_SYSCTL_CONF" "$BBR_STATE_FILE" "$BBR_BACKUP_FILE"
)
(
  BBR_SYSCTL_CONF=/tmp/mieru_tcp_bbr-unmanaged.conf
  BBR_STATE_FILE=/tmp/manager-state/bbr-unmanaged.state
  BBR_BACKUP_FILE=/tmp/manager-state/bbr-unmanaged.backup
  printf '%s\n' 'net.core.default_qdisc=fq' >"$BBR_SYSCTL_CONF"
  rm -f "$BBR_STATE_FILE" "$BBR_BACKUP_FILE"
  restore_owned_bbr_fq
  test -e "$BBR_SYSCTL_CONF"
  rm -f "$BBR_SYSCTL_CONF"
)
(
  bbr_fq_enabled(){ return 0; }
  tc_default_iface(){ echo eth-test; }
  tc(){ echo 'qdisc fq 8001: root refcnt 2 limit 10000p buckets 1024 orphan_mask 1023'; }
  bbr_fq_active
  tc(){ echo 'qdisc fq_codel 0: root refcnt 2 limit 10240p'; }
  ! bbr_fq_active
)

# 菜单动作首个错误即停止；dry-run 不触碰持久化状态。
set +e
menu_probe="$(
  (
    set -Eeuo pipefail
    trap 'exit $?' ERR
    do_status(){ false; echo MENU_SHOULD_NOT_CONTINUE; }
    ACTION=status
    menu_run_action
  ) 2>&1
)"
menu_rc=$?
set -e
test "$menu_rc" -ne 0
! grep -q MENU_SHOULD_NOT_CONTINUE <<<"$menu_probe"
# 删除最后一个用户属于业务拒绝：显示警告、留在用户管理，且不触发全局步骤失败。
(
  require_root(){ :; }
  require_linux(){ :; }
  mita_installed(){ return 0; }
  load_install_state(){ :; }
  users_ensure_loaded(){ :; }
  users_count(){ echo 1; }
  users_name_exists(){ return 0; }
  users_tx_snapshot(){ echo snapshot; }
  users_tx_commit(){ :; }
  admin_lock_acquire(){ :; }
  admin_lock_release(){ :; }
  do_user_list(){ :; }
  LANG_ZH=0
  YES=0
  USER_DEL_NAME=""
  menu_choice_count=0
  read_tty(){
    local value="" prompt="${2:-}"
    case "$prompt" in
      *1-18*)
        menu_choice_count=$((menu_choice_count + 1))
        [ "$menu_choice_count" -eq 1 ] && value=3 || value=18
        ;;
      *) value=alice ;;
    esac
    printf -v "$1" '%s' "$value"
  }
  set +e
  user_delete_output="$(MAIN_MENU_ACTIVE=1 do_user_manage 2>&1)"
  user_delete_rc=$?
  set -e
  test "$user_delete_rc" -eq 3
  if ! grep -q '\[警告\] Cannot delete the last user' <<<"$user_delete_output"; then
    printf 'unexpected user deletion output:\n%s\n' "$user_delete_output" >&2
    exit 1
  fi
  ! grep -q '步骤失败' <<<"$user_delete_output"
  test "$(grep -c '^\[Users\]' <<<"$user_delete_output")" -eq 2
)
# 真实子操作错误也必须留在用户管理，并保留准确阶段且停止后续命令。
(
  require_root(){ :; }
  do_user_list(){ false; echo USER_ACTION_SHOULD_NOT_CONTINUE; }
  LANG_ZH=0
  menu_choice_count=0
  read_tty(){
    local value="" prompt="${2:-}"
    if [[ "$prompt" == *1-18* ]]; then
      menu_choice_count=$((menu_choice_count + 1))
      [ "$menu_choice_count" -eq 1 ] && value=1 || value=18
    fi
    printf -v "$1" '%s' "$value"
  }
  set +e
  user_failure_output="$(MAIN_MENU_ACTIVE=1 do_user_manage 2>&1)"
  user_failure_rc=$?
  set -e
  test "$user_failure_rc" -eq 3
  grep -q '步骤失败: 列出用户' <<<"$user_failure_output"
  grep -q 'User operation failed' <<<"$user_failure_output"
  ! grep -q USER_ACTION_SHOULD_NOT_CONTINUE <<<"$user_failure_output"
  test "$(grep -c '^\[Users\]' <<<"$user_failure_output")" -eq 2
)
# 专属实例启动和重启只输出一条对应的最终结果。
(
  require_root(){ :; }
  mita_installed(){ return 0; }
  repair_mita_binary_paths(){ :; }
  start_mita(){ :; }
  users_isolated_mode(){ return 0; }
  verify_mita_running(){ test "${1:-0}" -eq 1; }
  LANG_ZH=0
  start_output="$(do_start)"
  test "$start_output" = 'All dedicated mita user instances started'

  users_enabled_instance_rows(){ printf 'u1\talice\t26000\n'; }
  instance_daemon_stop(){ :; }
  instance_start_proxy(){ :; }
  restart_output="$(do_restart)"
  test "$restart_output" = 'All dedicated mita user instances restarted'
)
# 用户管理 18 在主菜单上下文返回专用码，外层应立即重绘主菜单；独立调用则正常结束。
set +e
(
  MAIN_MENU_ACTIVE=1
  read_tty(){ printf -v "$1" '%s' 18; }
  do_user_manage >/dev/null
)
user_back_rc=$?
set -e
test "$user_back_rc" -eq 3
(
  MAIN_MENU_ACTIVE=0
  read_tty(){ printf -v "$1" '%s' 18; }
  do_user_manage >/dev/null
)
# 覆盖外层 menu_loop：用户管理返回码 3 必须直接重绘，不能落到 menu_pause。
(
  menu_show_count=0
  mita_installed(){ return 1; }
  show_menu(){
    menu_show_count=$((menu_show_count + 1))
    if [ "$menu_show_count" -eq 1 ]; then
      ACTION=user-manage
      return 0
    fi
    return 2
  }
  read_tty(){ printf -v "$1" '%s' 18; }
  menu_pause(){ touch /tmp/user-back-extra-pause; }
  rm -f /tmp/user-back-extra-pause
  menu_loop >/dev/null
  test ! -e /tmp/user-back-extra-pause
)
# 卸载成功通过特殊返回码退出菜单；用户取消则留在菜单且不报错。
set +e
(
  do_uninstall(){ UNINSTALL_CANCELLED=0; }
  ACTION=uninstall
  menu_run_action
)
uninstall_menu_rc=$?
set -e
test "$uninstall_menu_rc" -eq 2
(
  do_uninstall(){ UNINSTALL_CANCELLED=1; }
  ACTION=uninstall
  menu_run_action
)

# 首次接管前已存在的包/系统账号要记录为外部资源；卸载时不得删除包、账号或公共目录。
(
  ownership_dir=/tmp/preexisting-ownership
  rm -rf "$ownership_dir"
  MITA_MANAGER_STATE_DIR="$ownership_dir"
  MITA_MARKER="$ownership_dir/.installed"
  MITA_PRESERVE_PACKAGE_MARKER="$ownership_dir/preserve-preexisting-package"
  MITA_PRESERVE_USER_MARKER="$ownership_dir/preserve-preexisting-user"
  MITA_PRESERVE_GROUP_MARKER="$ownership_dir/preserve-preexisting-group"
  installed_by_oneclick(){ return 1; }
  mita_package_is_installed(){ return 0; }
  _has_user(){ return 0; }
  _has_group(){ return 0; }
  run(){ "$@"; }
  record_preexisting_mita_resources deb
  test -f "$MITA_PRESERVE_PACKAGE_MARKER"
  test -f "$MITA_PRESERVE_USER_MARKER"
  test -f "$MITA_PRESERVE_GROUP_MARKER"
)
(
  UNINSTALL_PRESERVE_EXTERNAL=1
  UNINSTALL_PRESERVE_PACKAGE=1
  UNINSTALL_PRESERVE_USER=1
  UNINSTALL_PRESERVE_GROUP=1
  run(){ printf 'RUN %s\n' "$*"; }
  find(){ :; }
  remove_users_scheduler(){ :; }
  remove_self_script(){ :; }
  preserved_cleanup_log="$(remove_mita_common)"
  ! grep -Eq '(^| )(deluser|userdel|delgroup|groupdel)( |$)' <<<"$preserved_cleanup_log"
  ! grep -Fq 'rm -rf /etc/mita /var/lib/mita' <<<"$preserved_cleanup_log"
  ! grep -Fq '/lib/systemd/system/mita.service' <<<"$preserved_cleanup_log"
  ! grep -Fq '/usr/lib/systemd/system/mita.service' <<<"$preserved_cleanup_log"
  ! grep -Fq '/var/log/mita.log /var/log/mita.err' <<<"$preserved_cleanup_log"
)
# 所有权标记必须逐项生效：只保留预先存在的用户时，OneClick 安装的包资源和组仍会清理。
(
  UNINSTALL_PRESERVE_EXTERNAL=1
  UNINSTALL_PRESERVE_PACKAGE=0
  UNINSTALL_PRESERVE_USER=1
  UNINSTALL_PRESERVE_GROUP=0
  run(){ printf 'RUN %s\n' "$*"; }
  find(){ :; }
  dpkg(){ return 1; }
  _has_user(){ return 0; }
  _has_group(){ return 0; }
  remove_users_scheduler(){ :; }
  remove_self_script(){ :; }
  user_only_cleanup_log="$(remove_mita_common)"
  grep -Fq 'rm -rf /etc/mita /var/lib/mita' <<<"$user_only_cleanup_log"
  grep -Fq '/lib/systemd/system/mita.service' <<<"$user_only_cleanup_log"
  grep -Fq '/var/log/mita.log /var/log/mita.err' <<<"$user_only_cleanup_log"
  ! grep -Eq '(^| )(deluser|userdel) mita( |$)' <<<"$user_only_cleanup_log"
  grep -Eq '(^| )(delgroup|groupdel) mita( |$)' <<<"$user_only_cleanup_log"
)
(
  ownership_dir=/tmp/preexisting-uninstall
  rm -rf "$ownership_dir"
  mkdir -p "$ownership_dir"
  MITA_PRESERVE_PACKAGE_MARKER="$ownership_dir/preserve-preexisting-package"
  MITA_PRESERVE_USER_MARKER="$ownership_dir/preserve-preexisting-user"
  MITA_PRESERVE_GROUP_MARKER="$ownership_dir/preserve-preexisting-group"
  touch "$MITA_PRESERVE_PACKAGE_MARKER" "$MITA_PRESERVE_USER_MARKER" "$MITA_PRESERVE_GROUP_MARKER"
  require_root(){ :; }
  mita_uninstall_target_present(){ return 0; }
  installed_by_oneclick(){ return 0; }
  confirm(){ return 0; }
  restore_owned_bbr_fq(){ return 0; }
  detect_pkg_manager(){ echo deb; }
  stop_mita_for_uninstall(){ :; }
  close_firewall(){ :; }
  firewall_clear_all_owned(){ :; }
  remove_mita_common(){
    test "$UNINSTALL_PRESERVE_EXTERNAL" -eq 1
    test "$UNINSTALL_PRESERVE_PACKAGE" -eq 1
    test "$UNINSTALL_PRESERVE_USER" -eq 1
    test "$UNINSTALL_PRESERVE_GROUP" -eq 1
  }
  verify_mita_uninstalled(){ return 0; }
  run(){ printf 'RUN %s\n' "$*"; }
  preserved_uninstall_output="$(do_uninstall)"
  grep -q '外部资源已保留' <<<"$preserved_uninstall_output"
  ! grep -Eq 'dpkg -P mita|rpm -e mita|userdel mita|groupdel mita' <<<"$preserved_uninstall_output"
)

rm -f /tmp/dry-run-mutated
do_install(){ touch /tmp/dry-run-mutated; }
repair_mita_binary_paths(){ touch /tmp/dry-run-mutated; }
ACTION=install DRY_RUN=1
main >/tmp/dry-run.out
test ! -e /tmp/dry-run-mutated
grep -q DRY-RUN /tmp/dry-run.out

# 在无软件包、只有 OneClick 残留的半安装状态下也能完整卸载并给出父 shell 提示。
rm -f "$MITA_PRESERVE_PACKAGE_MARKER" "$MITA_PRESERVE_USER_MARKER" \
  "$MITA_PRESERVE_GROUP_MARKER"
detect_pkg_manager(){ echo alpine; }
dpkg(){ return 1; }
dpkg-query(){ return 1; }
mkdir -p /etc/mita /etc/profile.d
touch "$MITA_MARKER" "$MITA_PROFILE_D"
YES=1 DRY_RUN=0 LANG_ZH=1
set +e
uninstall_output="$(do_uninstall 2>&1)"
uninstall_rc=$?
set -e
if [ "$uninstall_rc" -ne 0 ]; then
  printf '%s\n' "$uninstall_output" >&2
  exit "$uninstall_rc"
fi
if ! grep -q '完全卸载' <<<"$uninstall_output"; then
  printf 'unexpected uninstall output:\n%s\n' "$uninstall_output" >&2
  exit 1
fi
grep -q 'unset -f mita' <<<"$uninstall_output"
! grep -q '\[错误\]' <<<"$uninstall_output"
test ! -e "$MITA_PROFILE_D"

echo SMOKE_OK
DOCKER_TEST
echo "docker-smoke: PASS"
