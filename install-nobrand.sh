#!/usr/bin/env bash
# AUTO-GENERATED FILE.
# Source files live under src/.
# Do not edit this generated file directly.
# Run scripts/build.sh after modifying src/.

# The menu intentionally mutates globals inside isolated action subshells; the
# parent only consumes exit codes, so SC2030/SC2031 are false positives here.
# shellcheck disable=SC2030,SC2031
# NoBrand-OneClick — Mieru / Snell / Hysteria2 / Plain VLESS Sudoku 工具箱
# 作者: ike / https://github.com/ike-sh/NoBrand-OneClick
# Mieru 母体代码源自 ike-sh/mieru-OneClick (MIT)；Hysteria2 与 VLESS
# FinalMask/Sudoku 逻辑参考 ike-sh/Xray-OneClick (GPL-3.0)。本融合项目按
# GPL-3.0 发布；VLESS 为 plain VLESS/TCP，不使用 VLESS Encryption。
set -euo pipefail
umask 077

SCRIPT_VERSION="1.3.0"
SCRIPT_AUTHOR="ike"
SCRIPT_NAME="NoBrand-OneClick"
SCRIPT_REPO="ike-sh/NoBrand-OneClick"
UPSTREAM_REPO="enfein/mieru"
TESTED_MIERU_VERSION="3.35.0"
GITHUB_API="https://api.github.com/repos/${UPSTREAM_REPO}/releases/latest"
GITHUB_DL="https://github.com/${UPSTREAM_REPO}/releases/download"
MITA_BIN="/usr/local/bin/mita"
MITA_REAL_BIN="/usr/local/bin/mita-real"
MITA_MANAGER_STATE_DIR="${MITA_MANAGER_STATE_DIR:-/var/lib/mita-oneclick}"
MITA_LEGACY_STATE_DIR="/etc/mita"
MITA_LEGACY_MARKER="${MITA_LEGACY_STATE_DIR}/.mieru-oneclick"
MITA_LEGACY_STATE="${MITA_LEGACY_STATE_DIR}/install-state.env"
MITA_LEGACY_USERS_STATE="${MITA_LEGACY_STATE_DIR}/users.json"
MITA_LEGACY_USERS_BACKUP_DIR="${MITA_LEGACY_STATE_DIR}/backups"
MITA_LEGACY_FIREWALL_STATE="${MITA_LEGACY_STATE_DIR}/firewall-owned.bindings"
MITA_LEGACY_TC_STATE="${MITA_LEGACY_STATE_DIR}/tc-owned.filters"
MITA_MARKER="${MITA_MARKER:-${MITA_MANAGER_STATE_DIR}/.installed}"
MITA_STATE="${MITA_STATE:-${MITA_MANAGER_STATE_DIR}/install-state.env}"
MITA_PRESERVE_PACKAGE_MARKER="${MITA_PRESERVE_PACKAGE_MARKER:-${MITA_MANAGER_STATE_DIR}/preserve-preexisting-package}"
MITA_PRESERVE_USER_MARKER="${MITA_PRESERVE_USER_MARKER:-${MITA_MANAGER_STATE_DIR}/preserve-preexisting-user}"
MITA_PRESERVE_GROUP_MARKER="${MITA_PRESERVE_GROUP_MARKER:-${MITA_MANAGER_STATE_DIR}/preserve-preexisting-group}"
MITA_USERS_STATE="${MITA_USERS_STATE:-${MITA_MANAGER_STATE_DIR}/users.json}"
MITA_USERS_LOCK="${MITA_USERS_LOCK:-${MITA_MANAGER_STATE_DIR}/users.lock}"
MITA_USERS_CRON="${MITA_USERS_CRON:-/etc/cron.d/mita-users}"
MITA_USERS_TIMER="/etc/systemd/system/mita-users-scan.timer"
MITA_USERS_SERVICE="/etc/systemd/system/mita-users-scan.service"
MITA_USERS_LOG="${MITA_USERS_LOG:-/var/log/mita-users.log}"
MITA_USERS_BACKUP_DIR="${MITA_USERS_BACKUP_DIR:-${MITA_MANAGER_STATE_DIR}/backups}"
MITA_ADMIN_LOCK="${MITA_ADMIN_LOCK:-${MITA_MANAGER_STATE_DIR}/admin.lock}"
MITA_CLIENT_EXPORT_DIR="${MITA_CLIENT_EXPORT_DIR:-/root/mieru-clients}"
MITA_LOGROTATE_CONF="${MITA_LOGROTATE_CONF:-/etc/logrotate.d/mita-oneclick}"
MITA_FIREWALL_OWNED_STATE="${MITA_FIREWALL_OWNED_STATE:-${MITA_MANAGER_STATE_DIR}/firewall-owned.bindings}"
MITA_FIREWALL_COMMENT="mieru-oneclick"
MITA_METRICS_FILE="${MITA_METRICS_FILE:-/var/lib/mita/metrics.pb}"
BBR_SYSCTL_CONF="${BBR_SYSCTL_CONF:-/etc/sysctl.d/mieru_tcp_bbr.conf}"
BBR_STATE_FILE="${BBR_STATE_FILE:-${MITA_MANAGER_STATE_DIR}/bbr-owned.state}"
BBR_BACKUP_FILE="${BBR_BACKUP_FILE:-${MITA_MANAGER_STATE_DIR}/bbr-sysctl.backup}"
MITA_DEPLOYMENT_MODEL="isolated-v2"
MITA_INSTANCES_DIR="${MITA_INSTANCES_DIR:-/etc/mita/instances}"
MITA_INSTANCE_RUN_DIR="${MITA_INSTANCE_RUN_DIR:-/run/mita-instances}"
MITA_INSTANCE_METRICS_DIR="${MITA_INSTANCE_METRICS_DIR:-/var/lib/mita/instances}"
MITA_INSTANCE_SYSTEMD_TEMPLATE="${MITA_INSTANCE_SYSTEMD_TEMPLATE:-/etc/systemd/system/mita-oneclick@.service}"
MITA_INSTANCE_TMPFILES="${MITA_INSTANCE_TMPFILES:-/etc/tmpfiles.d/mita-oneclick.conf}"
MITA_INSTANCE_OPENRC_PREFIX="${MITA_INSTANCE_OPENRC_PREFIX:-/etc/init.d/mita-oneclick-}"
MITA_INSTANCE_RUNNER="${MITA_INSTANCE_RUNNER:-/usr/local/libexec/mita-instance-run}"
# 上游没有按用户清零指标的 API。isolated-v2 为每个用户挂载独立 metrics.pb，
# calendar 因而可以只重置目标用户；password/days 旧方案不会真正清零，已禁用。
QUOTA_RESET_METHOD="${QUOTA_RESET_METHOD:-metrics}"
INSTALL_SCRIPT_PATH="/usr/local/bin/install-mita"
MITA_MENU_PATH="/usr/local/bin/mita-menu"
MITA_PROFILE_D="/etc/profile.d/mita-oneclick.sh"
SCRIPT_REPO_RAW="https://raw.githubusercontent.com/${SCRIPT_REPO}/v${SCRIPT_VERSION}/install-nobrand.sh"
OPENRC_SVC="/etc/init.d/mita"
SYSTEMD_SVC="/etc/systemd/system/mita.service"

# NoBrand Common Core。Mieru 的权威 state 和 /etc/mita 语义保持不变；这些
# 路径只管理公共 metadata、Snell 与独立的 Xray-core 协议进程。
NOBRAND_STATE_DIR="${NOBRAND_STATE_DIR:-/var/lib/nobrand-oneclick}"
NOBRAND_CONFIG_DIR="${NOBRAND_CONFIG_DIR:-/etc/nobrand-oneclick}"
NOBRAND_LIB_DIR="${NOBRAND_LIB_DIR:-/usr/local/lib/nobrand-oneclick}"
NOBRAND_BIN_DIR="${NOBRAND_BIN_DIR:-${NOBRAND_LIB_DIR}/bin}"
NOBRAND_BACKUP_DIR="${NOBRAND_BACKUP_DIR:-${NOBRAND_STATE_DIR}/backups}"
NOBRAND_LOCK_DIR="${NOBRAND_LOCK_DIR:-${NOBRAND_STATE_DIR}/locks}"
NOBRAND_REGISTRY_FILE="${NOBRAND_REGISTRY_FILE:-${NOBRAND_STATE_DIR}/state.json}"
NOBRAND_FIREWALL_OWNED_STATE="${NOBRAND_FIREWALL_OWNED_STATE:-${NOBRAND_STATE_DIR}/firewall-owned.bindings}"
NOBRAND_FIREWALL_COMMENT="nobrand-oneclick"
NOBRAND_INSTALL_SCRIPT_PATH="${NOBRAND_INSTALL_SCRIPT_PATH:-/usr/local/bin/install-nobrand}"
NOBRAND_COMMAND_PATH="${NOBRAND_COMMAND_PATH:-/usr/local/bin/nobrand}"
NOBRAND_SHORT_COMMAND_PATH="${NOBRAND_SHORT_COMMAND_PATH:-/usr/local/bin/nb}"

NOBRAND_SNELL_STATE_DIR="${NOBRAND_SNELL_STATE_DIR:-${NOBRAND_STATE_DIR}/snell/instances}"
NOBRAND_SNELL_CONFIG_DIR="${NOBRAND_SNELL_CONFIG_DIR:-${NOBRAND_CONFIG_DIR}/snell/instances}"
NOBRAND_SNELL_RUNTIME_DIR="${NOBRAND_SNELL_RUNTIME_DIR:-${NOBRAND_BIN_DIR}/snell}"
NOBRAND_SNELL_SYSTEMD_TEMPLATE="${NOBRAND_SNELL_SYSTEMD_TEMPLATE:-/etc/systemd/system/nobrand-snell@.service}"
NOBRAND_SNELL_OPENRC_PREFIX="${NOBRAND_SNELL_OPENRC_PREFIX:-/etc/init.d/nobrand-snell-}"
NOBRAND_SNELL_RUNNER="${NOBRAND_SNELL_RUNNER:-${NOBRAND_LIB_DIR}/snell-run}"
SNELL_RELEASE_PAGE="https://kb.nssurge.com/surge-knowledge-base/release-notes/snell.md"

NOBRAND_HY2_STATE_DIR="${NOBRAND_HY2_STATE_DIR:-${NOBRAND_STATE_DIR}/hysteria2}"
NOBRAND_HY2_STATE_FILE="${NOBRAND_HY2_STATE_FILE:-${NOBRAND_HY2_STATE_DIR}/state.json}"
NOBRAND_HY2_CONFIG_DIR="${NOBRAND_HY2_CONFIG_DIR:-${NOBRAND_CONFIG_DIR}/hysteria2}"
NOBRAND_HY2_CONFIG_FILE="${NOBRAND_HY2_CONFIG_FILE:-${NOBRAND_HY2_CONFIG_DIR}/config.json}"
NOBRAND_HY2_CERT_FILE="${NOBRAND_HY2_CERT_FILE:-${NOBRAND_HY2_CONFIG_DIR}/hysteria2-cert.pem}"
NOBRAND_HY2_KEY_FILE="${NOBRAND_HY2_KEY_FILE:-${NOBRAND_HY2_CONFIG_DIR}/hysteria2-key.pem}"
NOBRAND_XRAY_BIN="${NOBRAND_XRAY_BIN:-${NOBRAND_BIN_DIR}/xray}"
NOBRAND_XRAY_ASSET_DIR="${NOBRAND_XRAY_ASSET_DIR:-${NOBRAND_LIB_DIR}/xray-assets}"
NOBRAND_HY2_SERVICE_NAME="nobrand-hysteria2"
NOBRAND_HY2_SYSTEMD_SERVICE="${NOBRAND_HY2_SYSTEMD_SERVICE:-/etc/systemd/system/nobrand-hysteria2.service}"
NOBRAND_HY2_OPENRC_SERVICE="${NOBRAND_HY2_OPENRC_SERVICE:-/etc/init.d/nobrand-hysteria2}"
NOBRAND_XRAY_RELEASE_API="https://api.github.com/repos/XTLS/Xray-core/releases/latest"
NOBRAND_HY2_TAG="nobrand-hysteria2-in"

NOBRAND_VLESS_STATE_DIR="${NOBRAND_VLESS_STATE_DIR:-${NOBRAND_STATE_DIR}/vless-sudoku}"
NOBRAND_VLESS_STATE_FILE="${NOBRAND_VLESS_STATE_FILE:-${NOBRAND_VLESS_STATE_DIR}/state.json}"
NOBRAND_VLESS_CLIENT_FILE="${NOBRAND_VLESS_CLIENT_FILE:-${NOBRAND_VLESS_STATE_DIR}/client.json}"
NOBRAND_VLESS_CONFIG_DIR="${NOBRAND_VLESS_CONFIG_DIR:-${NOBRAND_CONFIG_DIR}/vless-sudoku}"
NOBRAND_VLESS_CONFIG_FILE="${NOBRAND_VLESS_CONFIG_FILE:-${NOBRAND_VLESS_CONFIG_DIR}/config.json}"
NOBRAND_VLESS_SERVICE_NAME="nobrand-vless-sudoku"
NOBRAND_VLESS_SYSTEMD_SERVICE="${NOBRAND_VLESS_SYSTEMD_SERVICE:-/etc/systemd/system/nobrand-vless-sudoku.service}"
NOBRAND_VLESS_OPENRC_SERVICE="${NOBRAND_VLESS_OPENRC_SERVICE:-/etc/init.d/nobrand-vless-sudoku}"
NOBRAND_VLESS_TAG="nobrand-vless-sudoku-in"

# Xray-OneClick 57-hysteria2.sh 的原始候选集合，顺序也是非交互默认语义。
NOBRAND_HY2_SNI_CANDIDATES=(
  "www.abmindustriesgroup.com"
  "www.microsoft.com"
  "www.oracle.com"
  "www.ibm.com"
  "www.amazon.com"
  "www.samsung.com"
  "www.nvidia.com"
)
# 多用户端口池：相对主端口偏移，或 IP 尾号段内扫描
USER_PORT_POOL_START="${USER_PORT_POOL_START:-}"
USER_PORT_POOL_END="${USER_PORT_POOL_END:-}"

ACTION=""
MENU_MODE=0
MENU_SCRIPTS_READY=0
MAIN_MENU_ACTIVE=0
USER_MENU_HANDLED_RC=64
UNINSTALL_CANCELLED=0
UNINSTALL_PRESERVE_EXTERNAL=0
UNINSTALL_PRESERVE_PACKAGE=0
UNINSTALL_PRESERVE_USER=0
UNINSTALL_PRESERVE_GROUP=0
MITA_REINSTALL_TRIED=0
YES=0
DRY_RUN=0
LANG_ZH=1
ENABLE_BBR=0
STAGE="初始化"

PORT=""
PORT_RANGE=""
PROTOCOL="TCP"
PROTOCOL_CLI=0
PROFILE="balanced"
PROFILE_CLI=0
ADVERTISE_HOST=""
ADVERTISE_PORT=""
ADVERTISE_CLI=0
USERNAME=""
PASSWORD=""
USERNAME_CLI=0
PASSWORD_CLI=0
OP_USER=""
MTU=1400
MTU_POLICY="safe"
MTU_REQUEST=""
MTU_CLI=0
MTU_AUTO_IFACE=""
MTU_AUTO_LINK=""
MTU_AUTO_FAMILY=""
MTU_AUTO_OVERHEAD=""
MULTIPLEXING="MULTIPLEXING_OFF"
HANDSHAKE_MODE="HANDSHAKE_NO_WAIT"
MULTIPLEXING_CLI=0
HANDSHAKE_CLI=0
TRAFFIC_PATTERN="conservative"
TRAFFIC_SEED=""
TRAFFIC_CLI=0
LOW_ENTROPY_MODE="LOW_ENTROPY_MODE_OFF"
LOW_ENTROPY_CLI=0
MIERU_CHANNEL="stable"
MIERU_CHANNEL_CLI=0
MIERU_VERSION=""
MIERU_VERSION_CLI=0
PORT_CLI=0
PORT_RANGE_CLI=0
PORT_AUTO_SELECTED=0
CLIENT_RPC_PORT=8964
CLIENT_SOCKS5_PORT=1080
CLIENT_HTTP_PORT=8080
USER_DEL_NAME=""
USER_SHOW_NAME=""
USER_QUOTA_MB=""
USER_QUOTA_DAYS=""
USER_QUOTA_MODE=""
USER_EXPIRE=""
USER_PACKAGE=""
USER_BANDWIDTH_MBPS=""
USER_RESTORE_FILE=""
USER_EXPORT_FILE=""
# 脚本只创建 clsact（缺失时）并维护自己记录的 filter；不删除或替换现有 qdisc。
TC_IFACE="${TC_IFACE:-}"
TC_OWNED_STATE="${TC_OWNED_STATE:-${MITA_MANAGER_STATE_DIR}/tc-owned.filters}"
TC_PREF_MIN=42000
TC_PREF_MAX=42999
# 0=首次安装的短暂兼容路径；1=使用 users.json 管理用户专属实例。
MULTI_USER_MODE=0

# NoBrand 顶层 CLI 状态。旧 install-mita/mita 路径仍由原解析器处理。
NOBRAND_ENTRY=0
NOBRAND_ARGS_HANDLED=0
NOBRAND_PROTOCOL_FILTER=""
NOBRAND_BACKUP_ACTION=""
NOBRAND_BACKUP_PATH=""
SNELL_ACTION=""
SNELL_NAME=""
SNELL_VERSION="5"
SNELL_VERSION_CLI=0
SNELL_PSK=""
SNELL_QUIC_PROXY=""
SNELL_QUIC_CLI=0
SNELL_RESOLVED_VERSION=""
SNELL_RESOLVED_URL=""
SNELL_RESOLVED_STATUS=""
SNELL_RESOLVED_SHA256=""
HY2_ACTION=""
HY2_SNI=""
HY2_AUTH=""
HY2_OBFS=""
HY2_LISTEN="0.0.0.0"
VLESS_SUDOKU_ACTION=""
VLESS_SUDOKU_UUID=""
VLESS_SUDOKU_PASSWORD=""
VLESS_SUDOKU_LISTEN="0.0.0.0"
VLESS_SUDOKU_CLIENT_SOCKS_PORT="${VLESS_SUDOKU_CLIENT_SOCKS_PORT:-18080}"
ADVERTISE_AUTO_REQUESTED=0

if [ -z "${BASH_VERSION:-}" ]; then
  echo "[错误] 请使用 bash 运行此脚本" >&2
  if [ -f /etc/alpine-release ]; then
    echo "Alpine 默认无 bash，请先安装后执行（root 无需 sudo）：" >&2
    echo "  apk add --no-cache bash curl" >&2
    echo "  curl -fsSL https://raw.githubusercontent.com/ike-sh/NoBrand-OneClick/main/install-nobrand.sh | bash" >&2
  else
    echo "  curl -fsSL .../install-mita.sh | sudo bash" >&2
  fi
  exit 1
fi

on_error() {
  msg "[错误] 步骤失败: ${STAGE}" >&2
  exit 1
}
trap on_error ERR

usage() {
  cat <<EOF
用法：install-mita.sh [选项]

mieru mita 服务端一键安装 ${SCRIPT_VERSION}
上游项目：https://github.com/${UPSTREAM_REPO}
支持系统：Debian/Ubuntu、RHEL/CentOS/Rocky、Alpine Linux

无参数时显示交互菜单；非交互请指定动作：
  --install           新装 mita（已安装时建议用 --reconfigure）
  --reconfigure       修改端口 / 密码 / 协议（不重装二进制）
  --upgrade           按保存的 stable/latest/pinned 通道升级 mita
  --uninstall         卸载 mita
  --status            查看运行状态与配置摘要
  --client-config     查看节点链接并生成客户端 JSON（同 --show）
  --mtu-config        随时调整 MTU，重启服务并重新输出节点配置
  --start             启动服务（守护进程 + 代理）
  --stop              停止服务
  --restart           重启服务（守护进程异常时一键恢复）
  --users / user-list 列出代理用户及专属实例端口
  --user-add          添加用户（可配合 --user/--password/--port/--package 等）
  --user-del NAME     删除用户并释放端口
  --user-show NAME    查看指定用户节点配置
  --user-set-endpoint 设置展示入口：--user NAME --advertise-host IP --advertise-port PORT；或 --advertise-auto
  --user-set-quota    设置套餐：--user NAME --quota-mb N --quota-days D
  --user-set-expire   设置到期：--user NAME --expire YYYY-MM-DD|+Nd|0
  --user-enable NAME  启用用户
  --user-disable NAME 停用用户（从 mita 配置移除，端口保留）
  --user-scan         扫描到期/日历月配额重置（供 cron/timer）
  --user-quota-reset  手动触发日历月配额重置（可加 -y 强制）
  --user-set-rate     设置专属实例双向限速：--user NAME --bandwidth Mbps（0=不限）
  --rate-status       查看带宽配置和脚本拥有的 tc filter
  --user-usage        查看 mita 用户流量/配额用量（mita get users/quotas）
  --user-export-clients [DIR]  批量导出各用户客户端 JSON/链接
  --user-backup       备份 users.json
  --user-restore FILE 从备份恢复用户状态并 apply + tc
  --user-export [FILE] 导出用户状态 JSON（默认 stdout）
  --user-import FILE  导入用户状态（覆盖前自动备份）
  --doctor / verify   一键验收：服务/用户/配额/tc/定时任务
  --perf              只读性能诊断（不会修改服务、内核、firewall 或 tc）
  --profile-config    选择并应用配置预设

安装选项：
  --yes, -y           跳过确认
  --port PORT         监听端口（1025-65535）；多用户时作为主用户端口
  --port-range RANGE  已弃用；v2 专属实例要求每用户使用单端口
  --protocol TCP|UDP|BOTH  传输协议（默认 TCP；BOTH 时 UDP 使用 PORT+1）
  --profile NAME      配置预设：iplc|balanced|stealth|custom
  --advertise-host HOST 客户端连接入口（IPv4/IPv6/域名；不修改服务端监听）
  --advertise-port PORT 客户端配置展示的入口端口（仅展示，可使用 1-65535）
  --advertise-auto    恢复自动探测公网 IP，并展示服务端监听端口
  --mtu VALUE         MTU 策略/值：safe|auto|1280-1500（默认 safe=1400）
  --traffic-pattern LV  流量伪装/抗 DPI：off|conservative|aggressive（默认 conservative）
  --low-entropy MODE  低熵模式：off|56|48|40|32（性能优先默认 off；56 为需要时的低开销选择）
  --multiplexing MODE  多路复用：off|low|middle|high（默认 off）
  --handshake-mode MODE 握手：no-wait|standard（默认 no-wait）
  --mieru-channel CHANNEL 版本通道：stable|latest（默认 stable）
  --mieru-version VER 精确指定上游版本（高级；通道记为 pinned）
  --user NAME         代理用户名（安装主用户 / user-add）
  --password PASS     代理密码
  --package NAME      套餐：unlimited|trial|standard|custom（user-add）
  --quota-mb N        流量配额 MB（0=不限；写入 mita quotas）
  --quota-days D      配额滚动窗口天数（默认 30；rolling 模式）
  --quota-mode MODE   rolling|calendar（calendar=按月重置该用户专属指标）
  --expire WHEN       到期：YYYY-MM-DD 或 +30d 或 0/never
  --bandwidth Mbps    专属实例双向限速（0=不限）
  --op-user USER      加入 mita 用户组的 Linux 用户
  --enable-bbr        安装后启用 TCP BBR + FQ
  --lang en           使用英文提示

其它：
  --dry-run           仅预览，不执行
  --help, -h          显示帮助
  --version           显示版本

快捷命令（子命令不区分大小写）：
  install-mita                    打开菜单
  install-mita status             查看状态
  install-mita perf               只读性能诊断
  install-mita profile            选择配置预设
  install-mita reconfigure        重新配置
  install-mita show               查看节点链接
  install-mita mtu [auto|数值]    调整 MTU 并重新输出节点配置
  install-mita users              用户管理列表
  install-mita user-add --user a --password p
  install-mita user-del a
  install-mita restart            重启服务（start/stop 同理）
  mita-menu                       同上（安装后可用）
  登录 shell 下输入 mita          管理子命令不区分大小写；mita start/stop/restart 已走干净启停（含 systemd/openrc）
  其余如 mita run/apply/reload     仍透传官方二进制

一键安装（交互式，Debian/Ubuntu/CentOS 等）：
  curl -fsSL https://raw.githubusercontent.com/ike-sh/NoBrand-OneClick/main/install-nobrand.sh | sudo bash

Alpine Linux（无 sudo，需先装 bash）：
  apk add --no-cache bash curl
  curl -fsSL https://raw.githubusercontent.com/ike-sh/NoBrand-OneClick/main/install-nobrand.sh | bash

Alpine 一行命令：
  apk add --no-cache bash curl && curl -fsSL https://raw.githubusercontent.com/ike-sh/NoBrand-OneClick/main/install-nobrand.sh | bash

非交互示例：
  curl -fsSL .../install-mita.sh | sudo bash -s -- --install -y --port 2088 --user alice --password 'secret'
EOF
}

msg() { printf '%s\n' "$*"; }
info() { msg "==> $*"; }
warn() { msg "[警告] $*"; }
die() {
  msg "[错误] $*" >&2
  if [ "${MENU_MODE:-0}" -eq 1 ]; then
    return 1
  fi
  exit 1
}

bail() {
  die "$@" || return 1
}

t() {
  local zh="$1"
  local en="$2"
  if [ "$LANG_ZH" -eq 1 ]; then
    msg "$zh"
  else
    msg "$en"
  fi
}

print_banner() {
  msg ""
  t "mieru mita 服务端一键安装  v${SCRIPT_VERSION}" \
    "mieru mita server one-click installer  v${SCRIPT_VERSION}"
  t "作者: ${SCRIPT_AUTHOR} / https://github.com/${SCRIPT_REPO}" \
    "Author: ${SCRIPT_AUTHOR} / https://github.com/${SCRIPT_REPO}"
}

parse_nobrand_common_option() {
  case "${1:-}" in
    --yes|-y) YES=1 ;;
    --dry-run) DRY_RUN=1 ;;
    --port)
      PORT="${2:-}"
      PORT_CLI=1
      [ -n "$PORT" ] || die "--port 需要端口号"
      return 2
      ;;
    --advertise-host)
      ADVERTISE_HOST="${2:-}"
      ADVERTISE_CLI=1
      ADVERTISE_AUTO_REQUESTED=0
      [ -n "$ADVERTISE_HOST" ] || die "--advertise-host 需要地址"
      return 2
      ;;
    --advertise-port)
      ADVERTISE_PORT="${2:-}"
      ADVERTISE_CLI=1
      ADVERTISE_AUTO_REQUESTED=0
      [ -n "$ADVERTISE_PORT" ] || die "--advertise-port 需要端口"
      return 2
      ;;
    --advertise-auto)
      ADVERTISE_HOST=""
      ADVERTISE_PORT=""
      ADVERTISE_CLI=1
      ADVERTISE_AUTO_REQUESTED=1
      ;;
    *) return 1 ;;
  esac
  return 0
}

parse_nobrand_snell_args() {
  SNELL_ACTION="${1:-menu}"
  [ "$#" -eq 0 ] || shift
  case "$SNELL_ACTION" in
    v4|4) SNELL_ACTION=install; SNELL_VERSION=4; SNELL_VERSION_CLI=1 ;;
    v5|5) SNELL_ACTION=install; SNELL_VERSION=5; SNELL_VERSION_CLI=1 ;;
    add|create) SNELL_ACTION=install ;;
    list|nodes) SNELL_ACTION=show ;;
    delete|uninstall) SNELL_ACTION=remove ;;
    endpoint) SNELL_ACTION=set-endpoint ;;
    quic|set-quic) SNELL_ACTION=set-quic ;;
    menu|install|show|set-endpoint|remove|start|stop|restart|status|doctor|upgrade) ;;
    help|-h|--help) SNELL_ACTION=help ;;
    *) die "未知 Snell 操作: $SNELL_ACTION" ;;
  esac
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --name)
        SNELL_NAME="${2:-}"
        [ -n "$SNELL_NAME" ] || die "--name 需要节点名"
        shift 2
        ;;
      --version)
        SNELL_VERSION="${2:-}"
        SNELL_VERSION_CLI=1
        [ -n "$SNELL_VERSION" ] || die "--version 需要 4 或 5"
        shift 2
        ;;
      --psk)
        SNELL_PSK="${2:-}"
        [ -n "$SNELL_PSK" ] || die "--psk 需要值"
        shift 2
        ;;
      --quic)
        SNELL_QUIC_PROXY="${2:-}"
        SNELL_QUIC_CLI=1
        [ -n "$SNELL_QUIC_PROXY" ] || die "--quic 需要 on 或 off"
        case "$SNELL_QUIC_PROXY" in
          on|off) ;;
          *) die "--quic 只支持 on 或 off" ;;
        esac
        shift 2
        ;;
      *)
        local consumed=0 rc=0
        parse_nobrand_common_option "$1" "${2:-}" || rc=$?
        case "$rc" in
          0) consumed=1 ;;
          2) consumed=2 ;;
          *) die "未知 Snell 参数: $1" ;;
        esac
        shift "$consumed"
        ;;
    esac
  done
  case "$SNELL_VERSION" in
    4|5) ;;
    *) die "Snell 只支持 v4、v5" ;;
  esac
  if [ "$SNELL_VERSION" = 4 ] && [ "$SNELL_QUIC_PROXY" = on ]; then
    die "Snell v4 不支持 QUIC Proxy Mode"
  fi
  ACTION="nobrand-snell"
  NOBRAND_ARGS_HANDLED=1
}

parse_nobrand_hy2_args() {
  HY2_ACTION="${1:-menu}"
  [ "$#" -eq 0 ] || shift
  case "$HY2_ACTION" in
    add|create|reconfigure) HY2_ACTION=install ;;
    nodes) HY2_ACTION=show ;;
    delete|uninstall) HY2_ACTION=remove ;;
    endpoint) HY2_ACTION=set-endpoint ;;
    menu|install|show|set-endpoint|remove|start|stop|restart|status|doctor|upgrade) ;;
    help|-h|--help) HY2_ACTION=help ;;
    *) die "未知 Hysteria2 操作: $HY2_ACTION" ;;
  esac
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --sni)
        HY2_SNI="${2:-}"
        [ -n "$HY2_SNI" ] || die "--sni 需要域名或 IPv4"
        shift 2
        ;;
      *)
        local consumed=0 rc=0
        parse_nobrand_common_option "$1" "${2:-}" || rc=$?
        case "$rc" in
          0) consumed=1 ;;
          2) consumed=2 ;;
          *) die "未知 Hysteria2 参数: $1" ;;
        esac
        shift "$consumed"
        ;;
    esac
  done
  ACTION="nobrand-hy2"
  NOBRAND_ARGS_HANDLED=1
}

parse_nobrand_vless_sudoku_args() {
  VLESS_SUDOKU_ACTION="${1:-menu}"
  [ "$#" -eq 0 ] || shift
  case "$VLESS_SUDOKU_ACTION" in
    add|create|reconfigure) VLESS_SUDOKU_ACTION=install ;;
    nodes) VLESS_SUDOKU_ACTION=show ;;
    delete|uninstall) VLESS_SUDOKU_ACTION=remove ;;
    endpoint) VLESS_SUDOKU_ACTION=set-endpoint ;;
    menu|install|show|set-endpoint|remove|start|stop|restart|status|doctor|smoke|upgrade) ;;
    help|-h|--help) VLESS_SUDOKU_ACTION=help ;;
    *) die "未知 VLESS Sudoku 操作: $VLESS_SUDOKU_ACTION" ;;
  esac
  while [ "$#" -gt 0 ]; do
    local consumed=0 rc=0
    parse_nobrand_common_option "$1" "${2:-}" || rc=$?
    case "$rc" in
      0) consumed=1 ;;
      2) consumed=2 ;;
      *) die "未知 VLESS Sudoku 参数: $1" ;;
    esac
    shift "$consumed"
  done
  ACTION="nobrand-vless-sudoku"
  NOBRAND_ARGS_HANDLED=1
}

detect_nobrand_entry() {
  local entry
  entry="$(basename -- "$0" 2>/dev/null || printf '%s' "$0")"
  case "$entry" in
    install-nobrand.sh|install-nobrand|nobrand|nb) NOBRAND_ENTRY=1 ;;
  esac
  if [ "${1:-}" = nobrand ]; then
    NOBRAND_ENTRY=1
    shift
    set -- "$@"
  fi
  [ "$NOBRAND_ENTRY" -eq 1 ] || return 0
  [ "$#" -gt 0 ] || { NOBRAND_ARGS_HANDLED=1; return 0; }
  case "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" in
    mieru)
      shift
      if [ "$#" -eq 0 ]; then
        ACTION="nobrand-mieru-menu"
        NOBRAND_ARGS_HANDLED=1
      else
        # 将剩余参数交回原 Mieru 解析器，保持兼容 CLI。
        NOBRAND_REPARSED_ARGS=("$@")
      fi
      ;;
    snell)
      shift
      parse_nobrand_snell_args "$@"
      ;;
    hy2|hysteria2)
      shift
      parse_nobrand_hy2_args "$@"
      ;;
    vless-sudoku|sudoku)
      shift
      parse_nobrand_vless_sudoku_args "$@"
      ;;
    status)
      [ "$#" -eq 1 ] || die 'status 不接受参数'
      ACTION=nobrand-status; NOBRAND_ARGS_HANDLED=1
      ;;
    nodes)
      shift
      while [ "$#" -gt 0 ]; do
        case "$1" in
          --protocol)
            NOBRAND_PROTOCOL_FILTER="${2:-}"
            [ -n "$NOBRAND_PROTOCOL_FILTER" ] \
              || die "--protocol 需要 mieru、snell、hy2 或 vless-sudoku"
            shift 2
            ;;
          *) die "未知 nodes 参数: $1" ;;
        esac
      done
      ACTION=nobrand-nodes; NOBRAND_ARGS_HANDLED=1
      ;;
    doctor)
      [ "$#" -eq 1 ] || die 'doctor 不接受参数'
      ACTION=nobrand-doctor; NOBRAND_ARGS_HANDLED=1
      ;;
    backup)
      shift
      NOBRAND_BACKUP_ACTION="${1:-create}"
      [ "$#" -eq 0 ] || shift
      case "$NOBRAND_BACKUP_ACTION" in create|restore|list) ;; *) die "backup 只支持 create、restore、list" ;; esac
      if [ "$#" -gt 0 ]; then
        NOBRAND_BACKUP_PATH="$1"
        shift
      fi
      [ "$#" -eq 0 ] || die "backup 参数过多"
      ACTION=nobrand-backup; NOBRAND_ARGS_HANDLED=1
      ;;
    uninstall|remove)
      shift
      while [ "$#" -gt 0 ]; do
        case "$1" in
          --yes|-y) YES=1; shift ;;
          *) die "未知 uninstall 参数: $1" ;;
        esac
      done
      ACTION=nobrand-uninstall; NOBRAND_ARGS_HANDLED=1
      ;;
    network|bbr)
      [ "$#" -eq 1 ] || die 'network/bbr 不接受参数'
      ACTION=nobrand-network; NOBRAND_ARGS_HANDLED=1
      ;;
    menu)
      [ "$#" -eq 1 ] || die 'menu 不接受参数'
      ACTION=""; NOBRAND_ARGS_HANDLED=1
      ;;
    help|-h|--help)
      [ "$#" -eq 1 ] || die 'help 不接受参数'
      ACTION=nobrand-help; NOBRAND_ARGS_HANDLED=1
      ;;
    version|--version)
      [ "$#" -eq 1 ] || die 'version 不接受参数'
      ACTION=nobrand-version; NOBRAND_ARGS_HANDLED=1
      ;;
    *) die "未知 NoBrand 操作: $1（使用 --help 查看帮助）" ;;
  esac
}

NOBRAND_REPARSED_ARGS=()
detect_nobrand_entry "$@"
if [ "${#NOBRAND_REPARSED_ARGS[@]}" -gt 0 ]; then
  set -- "${NOBRAND_REPARSED_ARGS[@]}"
fi

while [ "$NOBRAND_ARGS_HANDLED" -eq 0 ] && [ $# -gt 0 ]; do
  _arg_lc="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  case "$_arg_lc" in
    --install) ACTION=install ;;
    --reconfigure) ACTION=reconfigure ;;
    --upgrade) ACTION=upgrade ;;
    --uninstall) ACTION=uninstall ;;
    --status) ACTION=status ;;
    --client-config|--show) ACTION=client-config ;;
    --mtu-config|--set-mtu) ACTION="mtu-config" ;;
    --start) ACTION=start ;;
    --stop) ACTION=stop ;;
    --restart) ACTION=restart ;;
    --users|--user-list) ACTION=user-list ;;
    --user-add) ACTION=user-add ;;
    --user-del|--user-delete)
      ACTION=user-del
      USER_DEL_NAME="${2:-}"
      [ -n "$USER_DEL_NAME" ] || die "--user-del 需要用户名"
      shift
      ;;
    --user-show)
      ACTION=user-show
      USER_SHOW_NAME="${2:-}"
      [ -n "$USER_SHOW_NAME" ] || die "--user-show 需要用户名"
      shift
      ;;
    --user-set-quota) ACTION=user-set-quota ;;
    --user-set-expire) ACTION=user-set-expire ;;
    --user-set-endpoint) ACTION=user-set-endpoint ;;
    --user-enable)
      ACTION=user-enable
      USER_SHOW_NAME="${2:-}"
      [ -n "$USER_SHOW_NAME" ] || die "--user-enable 需要用户名"
      shift
      ;;
    --user-disable)
      ACTION=user-disable
      USER_SHOW_NAME="${2:-}"
      [ -n "$USER_SHOW_NAME" ] || die "--user-disable 需要用户名"
      shift
      ;;
    --user-scan) ACTION=user-scan ;;
    --user-quota-reset) ACTION=user-quota-reset ;;
    --user-set-rate|--user-set-bandwidth) ACTION=user-set-rate ;;
    --rate-status|--tc-status) ACTION=rate-status ;;
    --rate-restore|--tc-restore) ACTION=rate-restore ;;
    --user-usage|--usage) ACTION=user-usage ;;
    --user-export-clients)
      ACTION=user-export-clients
      if [ -n "${2:-}" ] && [[ "${2}" != --* ]]; then
        MITA_CLIENT_EXPORT_DIR="${2}"
        shift
      fi
      ;;
    --doctor|--verify) ACTION=doctor ;;
    --perf) ACTION=perf ;;
    --profile-config) ACTION="profile-config" ;;
    --user-backup) ACTION=user-backup ;;
    --user-restore)
      ACTION=user-restore
      USER_RESTORE_FILE="${2:-}"
      [ -n "$USER_RESTORE_FILE" ] || die "--user-restore 需要备份文件路径"
      shift
      ;;
    --user-export)
      ACTION=user-export
      if [ -n "${2:-}" ] && [[ "${2}" != --* ]]; then
        USER_EXPORT_FILE="${2}"
        shift
      else
        USER_EXPORT_FILE=""
      fi
      ;;
    --user-import)
      ACTION=user-import
      USER_RESTORE_FILE="${2:-}"
      [ -n "$USER_RESTORE_FILE" ] || die "--user-import 需要文件路径"
      shift
      ;;
    install|upgrade|uninstall|status|reconfigure|client-config|show|mtu|mtu-config|set-mtu|profile|profile-config|perf|menu|start|stop|restart|配置|节点|users|user-list|user-add|user-del|user-delete|user-show|user-manage|user-set-endpoint|user-set-quota|user-set-expire|user-enable|user-disable|user-scan|user-quota-reset|user-set-rate|user-set-bandwidth|rate-status|rate-restore|tc-status|tc-restore|user-backup|user-restore|user-export|user-import|user-usage|usage|user-export-clients|doctor|verify|help)
      [ -z "$ACTION" ] && ACTION="$_arg_lc"
      [ "$_arg_lc" = show ] && ACTION=client-config
      { [ "$_arg_lc" = mtu ] || [ "$_arg_lc" = set-mtu ]; } && ACTION="mtu-config"
      [ "$_arg_lc" = profile ] && ACTION="profile-config"
      [ "$_arg_lc" = menu ] && ACTION=""
      [ "$_arg_lc" = 配置 ] && ACTION=client-config
      [ "$_arg_lc" = 节点 ] && ACTION=client-config
      [ "$_arg_lc" = users ] && ACTION=user-list
      [ "$_arg_lc" = user-delete ] && ACTION=user-del
      [ "$_arg_lc" = user-manage ] && ACTION=user-manage
      [ "$_arg_lc" = user-set-bandwidth ] && ACTION=user-set-rate
      [ "$_arg_lc" = tc-status ] && ACTION=rate-status
      [ "$_arg_lc" = tc-restore ] && ACTION=rate-restore
      [ "$_arg_lc" = usage ] && ACTION=user-usage
      [ "$_arg_lc" = verify ] && ACTION=doctor
      [ "$_arg_lc" = help ] && ACTION=help
      # 裸子命令后的位置参数：user-del bob / user-restore /path.json
      if [ -n "${2:-}" ] && [[ "${2}" != --* ]]; then
        case "$ACTION" in
          user-del)
            USER_DEL_NAME="${2}"
            shift
            ;;
          user-show|user-enable|user-disable)
            USER_SHOW_NAME="${2}"
            shift
            ;;
          user-restore|user-import)
            USER_RESTORE_FILE="${2}"
            shift
            ;;
          user-export)
            USER_EXPORT_FILE="${2}"
            shift
            ;;
          user-export-clients)
            MITA_CLIENT_EXPORT_DIR="${2}"
            shift
            ;;
          mtu-config)
            MTU_REQUEST="${2}"
            MTU_CLI=1
            shift
            ;;
        esac
      fi
      ;;
    --yes|-y) YES=1 ;;
    --dry-run) DRY_RUN=1 ;;
    --port)
      PORT="${2:-}"
      PORT_CLI=1
      [ -n "$PORT" ] || die "--port 需要端口号"
      shift
      ;;
    --port-range)
      PORT_RANGE="${2:-}"
      PORT_RANGE_CLI=1
      [ -n "$PORT_RANGE" ] || die "--port-range 需要端口段"
      shift
      ;;
    --protocol)
      PROTOCOL="${2:-}"
      PROTOCOL_CLI=1
      shift
      ;;
    --profile)
      PROFILE="${2:-}"
      PROFILE_CLI=1
      [ -n "$PROFILE" ] || die "--profile 需要 iplc、balanced、stealth 或 custom"
      shift
      ;;
    --advertise-host|--entry-ip)
      ADVERTISE_HOST="${2:-}"
      ADVERTISE_CLI=1
      [ -n "$ADVERTISE_HOST" ] || die "--advertise-host 需要入口地址"
      shift
      ;;
    --advertise-port|--entry-port)
      ADVERTISE_PORT="${2:-}"
      ADVERTISE_CLI=1
      [ -n "$ADVERTISE_PORT" ] || die "--advertise-port 需要入口端口"
      shift
      ;;
    --advertise-auto)
      ADVERTISE_HOST=""
      ADVERTISE_PORT=""
      ADVERTISE_CLI=1
      ;;
    --mtu)
      MTU_REQUEST="${2:-}"
      MTU_CLI=1
      [ -n "$MTU_REQUEST" ] || die "--mtu 需要 safe、auto 或 1280-1500 的数值"
      shift
      ;;
    --traffic-pattern|--traffic)
      TRAFFIC_PATTERN="${2:-}"
      TRAFFIC_CLI=1
      shift
      ;;
    --low-entropy)
      LOW_ENTROPY_MODE="${2:-}"
      LOW_ENTROPY_CLI=1
      shift
      ;;
    --multiplexing)
      MULTIPLEXING="${2:-}"
      MULTIPLEXING_CLI=1
      shift
      ;;
    --handshake-mode|--handshake)
      HANDSHAKE_MODE="${2:-}"
      HANDSHAKE_CLI=1
      shift
      ;;
    --mieru-channel)
      MIERU_CHANNEL="${2:-}"
      MIERU_CHANNEL_CLI=1
      [ -n "$MIERU_CHANNEL" ] || die "--mieru-channel 需要 stable 或 latest"
      shift
      ;;
    --mieru-version)
      MIERU_VERSION="${2:-}"
      MIERU_VERSION_CLI=1
      MIERU_CHANNEL="pinned"
      MIERU_CHANNEL_CLI=1
      [ -n "$MIERU_VERSION" ] || die "--mieru-version 需要版本号"
      shift
      ;;
    --user)
      USERNAME="${2:-}"
      USERNAME_CLI=1
      shift
      ;;
    --password)
      PASSWORD="${2:-}"
      PASSWORD_CLI=1
      shift
      ;;
    --package|--plan)
      USER_PACKAGE="${2:-}"
      shift
      ;;
    --quota-mb|--quota)
      USER_QUOTA_MB="${2:-}"
      shift
      ;;
    --quota-days)
      USER_QUOTA_DAYS="${2:-}"
      shift
      ;;
    --quota-mode)
      USER_QUOTA_MODE="${2:-}"
      shift
      ;;
    --expire|--expires)
      USER_EXPIRE="${2:-}"
      shift
      ;;
    --bandwidth|--rate|--mbps)
      USER_BANDWIDTH_MBPS="${2:-}"
      shift
      ;;
    --op-user)
      OP_USER="${2:-}"
      shift
      ;;
    --enable-bbr) ENABLE_BBR=1 ;;
    --lang)
      case "${2:-}" in
        en) LANG_ZH=0 ;;
        zh|*) LANG_ZH=1 ;;
      esac
      shift
      ;;
    --help|-h) usage; exit 0 ;;
    --version) echo "${SCRIPT_NAME} Mieru compatibility installer ${SCRIPT_VERSION} by ${SCRIPT_AUTHOR}"; exit 0 ;;
    *)
      if [[ "$1" == --* ]]; then
        die "未知参数：$1（使用 --help 查看帮助）"
      fi
      ;;
  esac
  shift
done
unset _arg_lc

run() {
  if [ "$DRY_RUN" -eq 1 ]; then
    local rendered=""
    printf -v rendered '%q ' "$@"
    msg "[dry-run] ${rendered% }"
  else
    "$@"
  fi
}

secure_stat_path() {
  local path="$1" expected_type="$2" uid mode
  [ "$expected_type" = dir ] && [ -d "$path" ] && [ ! -L "$path" ] || {
    [ "$expected_type" = file ] && [ -f "$path" ] && [ ! -L "$path" ] || return 1
  }
  uid="$(stat -c '%u' "$path" 2>/dev/null || true)"
  mode="$(stat -c '%a' "$path" 2>/dev/null || true)"
  [ "$uid" = 0 ] && [[ "$mode" =~ ^[0-7]{3,4}$ ]] || return 1
  [ "$((8#$mode & 8#022))" -eq 0 ]
}

state_file_is_secure() {
  local path="$1" parent
  parent="$(dirname "$path")"
  secure_stat_path "$parent" dir && secure_stat_path "$path" file
}

secure_migrate_root_file() {
  local src="$1" dest="$2" mode="${3:-0600}"
  [ -e "$dest" ] && return 0
  [ -f "$src" ] && [ ! -L "$src" ] || return 0
  command -v python3 >/dev/null 2>&1 || {
    warn "$(t "无法安全迁移旧状态（缺少 python3）: ${src}" \
      "Cannot securely migrate legacy state without python3: ${src}")"
    return 1
  }
  python3 - "$src" "$dest" "$mode" <<'PY'
import os, stat, sys, tempfile

src, dest, mode_text = sys.argv[1:4]
flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0)
fd = os.open(src, flags)
try:
    info = os.fstat(fd)
    if not stat.S_ISREG(info.st_mode) or info.st_uid != 0 or info.st_mode & 0o022:
        raise PermissionError("legacy state is not a root-owned protected regular file")
    chunks = []
    while True:
        chunk = os.read(fd, 1024 * 1024)
        if not chunk:
            break
        chunks.append(chunk)
        if sum(map(len, chunks)) > 64 * 1024 * 1024:
            raise ValueError("legacy state is unexpectedly large")
finally:
    os.close(fd)

parent = os.path.dirname(dest)
os.makedirs(parent, mode=0o700, exist_ok=True)
os.chown(parent, 0, 0)
os.chmod(parent, 0o700)
tmp_fd, tmp_path = tempfile.mkstemp(prefix=".migrate-", dir=parent)
try:
    os.fchmod(tmp_fd, int(mode_text, 8))
    os.write(tmp_fd, b"".join(chunks))
    os.fsync(tmp_fd)
    os.close(tmp_fd)
    tmp_fd = -1
    os.replace(tmp_path, dest)
finally:
    if tmp_fd >= 0:
        os.close(tmp_fd)
    try:
        os.unlink(tmp_path)
    except FileNotFoundError:
        pass
PY
}

ensure_manager_state_layout() {
  local create="${1:-0}"
  [ "${DRY_RUN:-0}" -eq 1 ] && return 0
  if [ "$create" -ne 1 ] && [ ! -d "$MITA_MANAGER_STATE_DIR" ] \
     && [ ! -e "$MITA_LEGACY_STATE" ] && [ ! -e "$MITA_LEGACY_USERS_STATE" ] \
     && [ ! -e "$MITA_LEGACY_FIREWALL_STATE" ] && [ ! -e "$MITA_LEGACY_TC_STATE" ] \
     && [ ! -d "$MITA_LEGACY_USERS_BACKUP_DIR" ] && [ ! -e "$MITA_LEGACY_MARKER" ]; then
    return 0
  fi
  install -d -o root -g root -m 0700 "$MITA_MANAGER_STATE_DIR" "$MITA_USERS_BACKUP_DIR"

  secure_migrate_root_file "$MITA_LEGACY_STATE" "$MITA_STATE" 0600
  secure_migrate_root_file "$MITA_LEGACY_USERS_STATE" "$MITA_USERS_STATE" 0600
  secure_migrate_root_file "$MITA_LEGACY_FIREWALL_STATE" "$MITA_FIREWALL_OWNED_STATE" 0600
  secure_migrate_root_file "$MITA_LEGACY_TC_STATE" "$TC_OWNED_STATE" 0600

  local legacy_backup dest
  if [ -d "$MITA_LEGACY_USERS_BACKUP_DIR" ]; then
    for legacy_backup in "$MITA_LEGACY_USERS_BACKUP_DIR"/users_*.json; do
      [ -f "$legacy_backup" ] || continue
      dest="${MITA_USERS_BACKUP_DIR}/$(basename "$legacy_backup")"
      secure_migrate_root_file "$legacy_backup" "$dest" 0600
    done
  fi
  if [ -e "$MITA_LEGACY_MARKER" ] && [ ! -e "$MITA_MARKER" ]; then
    install -o root -g root -m 0600 /dev/null "$MITA_MARKER"
  fi

  [ ! -e "$MITA_STATE" ] || rm -f "$MITA_LEGACY_STATE"
  [ ! -e "$MITA_USERS_STATE" ] || rm -f "$MITA_LEGACY_USERS_STATE"
  [ ! -e "$MITA_FIREWALL_OWNED_STATE" ] || rm -f "$MITA_LEGACY_FIREWALL_STATE"
  [ ! -e "$TC_OWNED_STATE" ] || rm -f "$MITA_LEGACY_TC_STATE"
  rm -f "${MITA_LEGACY_STATE_DIR}/users.lock" "${MITA_LEGACY_STATE_DIR}/admin.lock" 2>/dev/null || true
}

dry_run_action_preview() {
  local action="${1:-unknown}"
  t '========== DRY-RUN：仅预览 ==========' '========== DRY-RUN: preview only =========='
  t "动作: ${action}" "Action: ${action}"
  [ -n "${PORT:-}" ] && t "端口: ${PORT}" "Port: ${PORT}"
  [ -n "${PORT_RANGE:-}" ] && t "端口段: ${PORT_RANGE}" "Port range: ${PORT_RANGE}"
  [ -n "${PROTOCOL:-}" ] && t "协议: ${PROTOCOL}" "Protocol: ${PROTOCOL}"
  [ -n "${MTU_REQUEST:-}" ] && t "MTU 请求: ${MTU_REQUEST}" "MTU request: ${MTU_REQUEST}"
  [ -n "${USERNAME:-}" ] && t "用户: ${USERNAME}" "User: ${USERNAME}"
  if [ -n "${ADVERTISE_HOST:-}" ]; then
    t "客户端展示入口: ${ADVERTISE_HOST}:${ADVERTISE_PORT}" \
      "Client display entry: ${ADVERTISE_HOST}:${ADVERTISE_PORT}"
  fi
  t '未执行命令；未修改配置、账号、服务、软件包、防火墙、tc、定时任务或持久化文件。' \
    'No command was executed; config, users, services, packages, firewall, tc, schedulers, and persistent files were not changed.'
}

dry_run_should_preview() {
  [ "${DRY_RUN:-0}" -eq 1 ] || return 1
  case "${1:-}" in
    help) return 1 ;;
    *) return 0 ;;
  esac
}

# BusyBox mktemp（Alpine）要求 XXXXXX 在模板末尾；GNU 允许中间占位
mktemp_file() {
  local suffix="${1:-}"
  local f="" candidate i
  f="$(mktemp /tmp/mita.XXXXXX 2>/dev/null)" || true
  if [ -z "$f" ]; then
    for i in 1 2 3 4 5; do
      candidate="/tmp/mita.$$.${RANDOM}.${i}"
      if (set -o noclobber; : >"$candidate") 2>/dev/null; then
        f="$candidate"
        break
      fi
    done
  fi
  if [ -z "$f" ]; then
    die "$(t '无法创建安全临时文件' 'Failed to create secure temporary file')" || true
    return 1
  fi
  [ -n "$suffix" ] || { printf '%s' "$f"; return; }
  local out="${f}${suffix}"
  if [ "$f" != "$out" ]; then
    if ! mv "$f" "$out" 2>/dev/null; then
      rm -f "$f"
      die "$(t '无法创建带后缀的安全临时文件' 'Failed to create secure suffixed temporary file')"
      return 1
    fi
  fi
  printf '%s' "$out"
}

mktemp_dir() {
  local d
  d="$(mktemp -d /tmp/mita.XXXXXX 2>/dev/null)" \
    || d="$(mktemp -d 2>/dev/null)" \
    || { d="/tmp/mita_$$_${RANDOM}"; mkdir -p "$d"; }
  printf '%s' "$d"
}

read_tty() {
  local _var="$1"
  local _prompt="${2:-}"
  local _line=""
  if [ -n "$_prompt" ]; then
    if [ -t 0 ]; then
      read -r -p "$_prompt" _line || _line=""
    elif [ -r /dev/tty ]; then
      read -r -p "$_prompt" _line </dev/tty || _line=""
    else
      return 1
    fi
  else
    if [ -t 0 ]; then
      read -r _line || _line=""
    elif [ -r /dev/tty ]; then
      read -r _line </dev/tty || _line=""
    else
      return 1
    fi
  fi
  printf -v "$_var" '%s' "$_line"
}

read_tty_secret() {
  local _var="$1"
  local _prompt="${2:-}"
  local _line=""
  if [ -t 0 ]; then
    read -r -s -p "$_prompt" _line || _line=""
    printf '\n'
  elif [ -r /dev/tty ]; then
    read -r -s -p "$_prompt" _line </dev/tty || _line=""
    printf '\n' >/dev/tty
  else
    return 1
  fi
  printf -v "$_var" '%s' "$_line"
}

confirm() {
  local prompt_zh="$1"
  local prompt_en="$2"
  local default="${3:-y}"
  if [ "$YES" -eq 1 ]; then
    return 0
  fi
  local prompt
  if [ "$LANG_ZH" -eq 1 ]; then
    prompt="$prompt_zh"
  else
    prompt="$prompt_en"
  fi
  local ans=""
  read_tty ans "$prompt" || return 1
  ans="${ans:-$default}"
  case "$ans" in
    y|Y|yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}

require_root() {
  if [ "$(id -u)" -eq 0 ]; then
    return 0
  fi
  STAGE="权限检查"
  if [ -f /etc/alpine-release ]; then
    die "$(t '需要 root 权限；Alpine 请 su - 或 docker exec -u root 后直接 bash 运行（无 sudo）' \
      'Root required; on Alpine use su - or docker exec -u root, then run with bash (no sudo)')"
  fi
  die "$(t '需要 root 权限，请使用 sudo 运行' 'Root privileges required; run with sudo')"
}

require_linux() {
  STAGE="系统检查"
  case "$(uname -s)" in
    Linux) ;;
    *) die "$(t '仅支持 Linux 系统' 'Linux only')" ;;
  esac
}

require_cmd() {
  local c="$1"
  command -v "$c" >/dev/null 2>&1 || die "$(t "缺少命令：${c}" "Missing command: ${c}")"
}

detect_pkg_manager() {
  STAGE="检测包管理器"
  if [ -f /etc/alpine-release ] && command -v apk >/dev/null 2>&1; then
    echo alpine
    return
  fi
  if command -v dpkg >/dev/null 2>&1 && dpkg -l >/dev/null 2>&1; then
    echo deb
    return
  fi
  if command -v rpm >/dev/null 2>&1 && rpm -qa >/dev/null 2>&1; then
    echo rpm
    return
  fi
  die "$(t '未检测到 deb、rpm 或 apk 包管理器' 'No deb, rpm, or apk package manager detected')"
}

_has_group() {
  getent group "$1" >/dev/null 2>&1 || grep -q "^$1:" /etc/group 2>/dev/null
}

_has_user() {
  getent passwd "$1" >/dev/null 2>&1 || grep -q "^$1:" /etc/passwd 2>/dev/null
}

proto_lower() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

normalize_protocol() {
  local v
  v="$(printf '%s' "$1" | tr '[:lower:]' '[:upper:]')"
  case "$v" in
    TCP|UDP|BOTH) printf '%s' "$v" ;;
    DUAL|ALL|双协议) printf '%s' BOTH ;;
    *) return 1 ;;
  esac
}

protocols_for_mode() {
  case "$PROTOCOL" in
    BOTH) printf '%s\n' TCP UDP ;;
    *) printf '%s\n' "$PROTOCOL" ;;
  esac
}

protocol_label() {
  local canonical_port=""
  [ -z "${PORT:-}" ] || canonical_port="$(normalize_uint "$PORT" 2>/dev/null || printf '%s' "$PORT")"
  case "$PROTOCOL" in
    BOTH)
      if [ -n "$PORT" ]; then
        if [ "$LANG_ZH" -eq 1 ]; then
          printf '%s' "TCP(${canonical_port}) + UDP($((canonical_port + 1)))"
        else
          printf '%s' "TCP(${canonical_port}) + UDP($((canonical_port + 1)))"
        fi
      else
        if [ "$LANG_ZH" -eq 1 ]; then
          printf '%s' 'TCP + UDP（同端口段）'
        else
          printf '%s' 'TCP + UDP (same port range)'
        fi
      fi
      ;;
    *) printf '%s' "$PROTOCOL" ;;
  esac
}

port_for_protocol() {
  local proto="$1" canonical_port
  if [ -n "$PORT" ]; then
    canonical_port="$(normalize_uint "$PORT")" || return 1
    if [ "$PROTOCOL" = "BOTH" ] && [ "$proto" = "UDP" ]; then
      printf '%s' "$((canonical_port + 1))"
    else
      printf '%s' "$canonical_port"
    fi
  else
    printf '%s' "$PORT_RANGE"
  fi
}

port_protocol_pairs() {
  local proto p
  while IFS= read -r proto; do
    p="$(port_for_protocol "$proto")"
    if [ -n "$PORT" ]; then
      valid_port "$p" || die "$(t "双协议需要 ${PORT} 与 $((PORT + 1)) 均在 1025-65535" \
        "Dual protocol requires ports ${PORT} and $((PORT + 1)) in 1025-65535")"
    fi
    printf '%s|%s\n' "$proto" "$p"
  done < <(protocols_for_mode)
}

_state_kv() {
  # 安全输出可被 source 还原的 KEY=VALUE：printf %q 处理空格/引号/$/# 等特殊字符
  printf '%s=%s\n' "$1" "$(printf '%q' "${2-}")"
}

has_control_chars() {
  printf '%s' "${1-}" | LC_ALL=C grep -q '[[:cntrl:]]'
}

valid_proxy_identity_part() {
  local value="${1-}"
  [ -n "$value" ] || return 1
  [ "$(printf '%s' "$value" | wc -c | tr -d '[:space:]')" -le 64 ] || return 1
  ! has_control_chars "$value"
}

validate_proxy_credentials() {
  local username="${1-${USERNAME:-}}"
  local password="${2-${PASSWORD:-}}"
  valid_proxy_identity_part "$username" || {
    die "$(t '用户名必须为 1-64 字节且不能包含控制字符' \
      'Username must be 1-64 bytes and contain no control characters')" || return 1
  }
  valid_proxy_identity_part "$password" || {
    die "$(t '密码必须为 1-64 字节且不能包含控制字符' \
      'Password must be 1-64 bytes and contain no control characters')" || return 1
  }
}

json_escape() {
  local value="${1-}"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\b'/\\b}"
  value="${value//$'\f'/\\f}"
  value="${value//$'\n'/\\n}"
  value="${value//$'\r'/\\r}"
  value="${value//$'\t'/\\t}"
  printf '%s' "$value"
}

json_string() {
  printf '"%s"' "$(json_escape "${1-}")"
}

safe_filename_component() {
  local value="${1-}"
  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import sys,urllib.parse; print(urllib.parse.quote(sys.argv[1], safe="._-"))' "$value"
  else
    printf '%s' "$value" | sed 's/[^A-Za-z0-9._-]/_/g'
  fi
}

# /etc/mita 仅保存官方守护进程数据，必须允许 mita 写 server.conf.pb。
# OneClick 的 root 管理状态全部位于独立的 root:root 0700 目录。
harden_mita_permissions() {
  run mkdir -p /etc/mita "$MITA_MANAGER_STATE_DIR" "$MITA_USERS_BACKUP_DIR" 2>/dev/null || true
  if _has_user mita 2>/dev/null || id mita >/dev/null 2>&1; then
    run chown mita:mita /etc/mita 2>/dev/null || true
    run chmod 0750 /etc/mita 2>/dev/null || true
  elif _has_group mita 2>/dev/null || getent group mita >/dev/null 2>&1; then
    run chown root:mita /etc/mita 2>/dev/null || true
    run chmod 0770 /etc/mita 2>/dev/null || true
  else
    run chmod 0750 /etc/mita 2>/dev/null || true
  fi
  run chown root:root "$MITA_MANAGER_STATE_DIR" "$MITA_USERS_BACKUP_DIR" 2>/dev/null || true
  run chmod 0700 "$MITA_MANAGER_STATE_DIR" "$MITA_USERS_BACKUP_DIR" 2>/dev/null || true
  # 敏感状态文件：root 读写即可（管理脚本以 root 运行）。
  if [ -f "$MITA_STATE" ]; then
    run chown root:root "$MITA_STATE" 2>/dev/null || true
    run chmod 0600 "$MITA_STATE" 2>/dev/null || true
  fi
  if [ -f "$MITA_USERS_STATE" ]; then
    run chown root:root "$MITA_USERS_STATE" 2>/dev/null || true
    run chmod 0600 "$MITA_USERS_STATE" 2>/dev/null || true
  fi
  if [ -d "$MITA_INSTANCES_DIR" ]; then
    run chown root:mita "$MITA_INSTANCES_DIR" 2>/dev/null || true
    run chmod 0750 "$MITA_INSTANCES_DIR" 2>/dev/null || true
  fi
  if [ -d "$MITA_USERS_BACKUP_DIR" ]; then
    find "$MITA_USERS_BACKUP_DIR" -type f -name 'users_*.json' -exec chmod 0600 {} \; 2>/dev/null || true
  fi
}

install_logrotate_config() {
  [ "${DRY_RUN:-0}" -eq 1 ] && return 0
  [ -d /etc/logrotate.d ] || return 0
  cat >"$MITA_LOGROTATE_CONF" <<EOF
${MITA_USERS_LOG} {
    weekly
    rotate 8
    compress
    delaycompress
    missingok
    notifempty
    create 0640 root root
}

/var/log/mita-oneclick-*.log /var/log/mita-oneclick-*.err {
    weekly
    rotate 8
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
}
EOF
  chmod 0644 "$MITA_LOGROTATE_CONF" 2>/dev/null || true
}

# 管理写操作互斥锁（fd 8，引用计数可重入）
admin_lock_acquire() {
  if [ "${DRY_RUN:-0}" -eq 1 ]; then
    _ADMIN_LOCK_HELD=$((${_ADMIN_LOCK_HELD:-0} + 1))
    return 0
  fi
  command -v flock >/dev/null 2>&1 || return 0
  run mkdir -p "$(dirname "$MITA_ADMIN_LOCK")"
  if [ "${_ADMIN_LOCK_HELD:-0}" -gt 0 ]; then
    _ADMIN_LOCK_HELD=$((_ADMIN_LOCK_HELD + 1))
    return 0
  fi
  exec 8>"$MITA_ADMIN_LOCK"
  if flock -w 120 8; then
    _ADMIN_LOCK_HELD=1
    return 0
  fi
  exec 8>&-
  die "$(t '获取管理锁超时，操作已取消以避免并发写入' \
    'Admin lock timeout; operation cancelled to prevent concurrent writes')" || return 1
}

admin_lock_release() {
  [ "${_ADMIN_LOCK_HELD:-0}" -gt 0 ] || return 0
  _ADMIN_LOCK_HELD=$((_ADMIN_LOCK_HELD - 1))
  [ "${DRY_RUN:-0}" -eq 1 ] && return 0
  if [ "$_ADMIN_LOCK_HELD" -le 0 ]; then
    _ADMIN_LOCK_HELD=0
    flock -u 8 2>/dev/null || true
    exec 8>&-
  fi
}

save_install_state() {
  STAGE="保存安装状态"
  local state_tmp
  profile_reconcile_metadata
  MIERU_CHANNEL="$(normalize_mieru_channel "${MIERU_CHANNEL:-stable}" 2>/dev/null || printf stable)"
  if [ "${DRY_RUN:-0}" -eq 1 ]; then
    msg "[dry-run] save install state: $MITA_STATE"
    return 0
  fi
  run mkdir -p "$(dirname "$MITA_STATE")"
  state_tmp="$(mktemp "${MITA_STATE}.XXXXXX" 2>/dev/null || mktemp_file .state)"
  if ! {
    _state_kv PORT "$PORT"
    _state_kv PORT_RANGE "$PORT_RANGE"
    _state_kv PROTOCOL "$PROTOCOL"
    _state_kv PROFILE "$PROFILE"
    _state_kv ADVERTISE_HOST "$ADVERTISE_HOST"
    _state_kv ADVERTISE_PORT "$ADVERTISE_PORT"
    _state_kv MTU "$MTU"
    _state_kv MTU_POLICY "$MTU_POLICY"
    _state_kv USERNAME "$USERNAME"
    _state_kv PASSWORD "$PASSWORD"
    _state_kv TRAFFIC_PATTERN "$TRAFFIC_PATTERN"
    _state_kv TRAFFIC_SEED "$TRAFFIC_SEED"
    _state_kv LOW_ENTROPY_MODE "$LOW_ENTROPY_MODE"
    _state_kv MULTIPLEXING "$MULTIPLEXING"
    _state_kv HANDSHAKE_MODE "$HANDSHAKE_MODE"
    _state_kv MIERU_CHANNEL "$MIERU_CHANNEL"
    _state_kv MIERU_VERSION "$MIERU_VERSION"
    _state_kv INSTALL_SCRIPT "$INSTALL_SCRIPT_PATH"
    printf 'INSTALL_METHOD=oneclick\n'
  } >"$state_tmp"; then
    rm -f "$state_tmp"
    return 1
  fi
  if [ "$DRY_RUN" -eq 1 ]; then
    msg "[dry-run] chmod 0600 ${state_tmp}"
    msg "[dry-run] mv -f ${state_tmp} ${MITA_STATE}"
  else
    if ! chmod 0600 "$state_tmp" || ! mv -f "$state_tmp" "$MITA_STATE"; then
      rm -f "$state_tmp"
      return 1
    fi
  fi
  rm -f "$state_tmp"
  harden_mita_permissions
  run touch "$MITA_MARKER"
}

mark_oneclick_install() {
  run mkdir -p "$(dirname "$MITA_MARKER")"
  run touch "$MITA_MARKER"
  run chown root:root "$MITA_MARKER" 2>/dev/null || true
  run chmod 0600 "$MITA_MARKER" 2>/dev/null || true
}

installed_by_oneclick() {
  [ -f "$MITA_MARKER" ]
}

mita_package_is_installed() {
  case "${1:-}" in
    deb) dpkg-query -W -f='${db:Status-Abbrev}' mita 2>/dev/null | grep -q '^ii' ;;
    rpm) rpm -q mita >/dev/null 2>&1 ;;
    *) return 1 ;;
  esac
}

# 首次接管前已存在的包/账号不属于 OneClick。使用独立所有权标记，
# 不改变 install-state.env、users.json 或任何运行配置的 schema。
record_preexisting_mita_resources() {
  local pm="${1:-}"
  installed_by_oneclick && return 0
  run mkdir -p "$MITA_MANAGER_STATE_DIR"
  mita_package_is_installed "$pm" && run touch "$MITA_PRESERVE_PACKAGE_MARKER"
  _has_user mita && run touch "$MITA_PRESERVE_USER_MARKER"
  _has_group mita && run touch "$MITA_PRESERVE_GROUP_MARKER"
  run chmod 0600 "$MITA_PRESERVE_PACKAGE_MARKER" "$MITA_PRESERVE_USER_MARKER" \
    "$MITA_PRESERVE_GROUP_MARKER" 2>/dev/null || true
}

preexisting_mita_resources_recorded() {
  [ -f "$MITA_PRESERVE_PACKAGE_MARKER" ] \
    || [ -f "$MITA_PRESERVE_USER_MARKER" ] \
    || [ -f "$MITA_PRESERVE_GROUP_MARKER" ]
}

load_install_state() {
  local _live_bin="" _live_desc="" _live_mtu=""
  local _cli_port="$PORT"
  local _cli_port_range="$PORT_RANGE"
  local _cli_protocol="$PROTOCOL"
  local _cli_profile="$PROFILE"
  local _cli_advertise_host="$ADVERTISE_HOST"
  local _cli_advertise_port="$ADVERTISE_PORT"
  local _cli_mtu="$MTU"
  local _cli_mtu_policy="$MTU_POLICY"
  local _cli_mtu_request="$MTU_REQUEST"
  local _cli_user="$USERNAME"
  local _cli_password="$PASSWORD"
  local _cli_mieru_channel="$MIERU_CHANNEL"
  local _cli_mieru_version="$MIERU_VERSION"
  PORT=""
  PORT_RANGE=""
  PROTOCOL="TCP"
  PROFILE=""
  ADVERTISE_HOST=""
  ADVERTISE_PORT=""
  MIERU_CHANNEL=""
  MIERU_VERSION=""
  [ -f "$MITA_STATE" ] || return 0
  state_file_is_secure "$MITA_STATE" || {
    warn "$(t "拒绝读取权限不安全的安装状态: ${MITA_STATE}" \
      "Refusing to read install state with unsafe ownership or permissions: ${MITA_STATE}")"
    return 1
  }
  local _cli_tp="$TRAFFIC_PATTERN"
  local _cli_le="$LOW_ENTROPY_MODE"
  local _cli_mux="$MULTIPLEXING"
  local _cli_hs="$HANDSHAKE_MODE"
  # shellcheck disable=SC1090
  source "$MITA_STATE" 2>/dev/null || true
  # v2.1 及更早状态没有 Profile：只根据已保存的完整真实参数反推元数据，
  # 绝不为了匹配预设去覆盖旧参数。字段不全时保守标记 custom。
  if ! grep -q '^PROFILE=' "$MITA_STATE" 2>/dev/null; then
    if grep -q '^PROTOCOL=' "$MITA_STATE" 2>/dev/null \
       && grep -q '^MTU=' "$MITA_STATE" 2>/dev/null \
       && grep -q '^MULTIPLEXING=' "$MITA_STATE" 2>/dev/null \
       && grep -q '^HANDSHAKE_MODE=' "$MITA_STATE" 2>/dev/null \
       && grep -q '^TRAFFIC_PATTERN=' "$MITA_STATE" 2>/dev/null \
       && grep -q '^LOW_ENTROPY_MODE=' "$MITA_STATE" 2>/dev/null; then
      PROFILE="$(infer_profile_from_values)"
    else
      PROFILE="custom"
    fi
  fi
  PROFILE="$(normalize_profile "${PROFILE:-custom}" 2>/dev/null || printf 'custom')"
  # 旧版升级始终跟随 upstream latest；缺少通道时延续该行为，避免升级语义突变。
  if ! grep -q '^MIERU_CHANNEL=' "$MITA_STATE" 2>/dev/null; then
    MIERU_CHANNEL="latest"
  fi
  MIERU_CHANNEL="$(normalize_mieru_channel "${MIERU_CHANNEL:-latest}" 2>/dev/null || printf 'latest')"
  if ! grep -q '^MIERU_VERSION=' "$MITA_STATE" 2>/dev/null; then
    MIERU_VERSION="$(installed_version 2>/dev/null || true)"
  fi
  # 兼容旧状态文件：优先保留正在运行配置中的 MTU，避免后续用户管理重建配置时降回 1400。
  if ! grep -q '^MTU=' "$MITA_STATE" 2>/dev/null; then
    _live_bin="$(mita_bin 2>/dev/null || true)"
    if [ -x "$_live_bin" ]; then
      _live_desc="$("$_live_bin" describe config 2>/dev/null || true)"
      _live_mtu="$(extract_mtu_from_describe "$_live_desc" 2>/dev/null || true)"
      if valid_mtu "$_live_mtu"; then
        MTU="$_live_mtu"
      fi
    fi
  fi
  if ! grep -q '^MTU_POLICY=' "$MITA_STATE" 2>/dev/null; then
    if valid_mtu "${MTU:-}" && [ "$MTU" -ne 1400 ]; then
      MTU_POLICY="custom"
    else
      MTU_POLICY="safe"
    fi
  fi
  # 命令行显式指定 --traffic-pattern 时优先，不被已保存状态覆盖
  [ "${TRAFFIC_CLI:-0}" -eq 1 ] && TRAFFIC_PATTERN="$_cli_tp"
  [ "${LOW_ENTROPY_CLI:-0}" -eq 1 ] && LOW_ENTROPY_MODE="$_cli_le"
  [ "${MULTIPLEXING_CLI:-0}" -eq 1 ] && MULTIPLEXING="$_cli_mux"
  [ "${HANDSHAKE_CLI:-0}" -eq 1 ] && HANDSHAKE_MODE="$_cli_hs"
  [ "${PORT_CLI:-0}" -eq 1 ] && { PORT="$_cli_port"; PORT_RANGE=""; }
  [ "${PORT_RANGE_CLI:-0}" -eq 1 ] && { PORT=""; PORT_RANGE="$_cli_port_range"; }
  [ "${PROTOCOL_CLI:-0}" -eq 1 ] && PROTOCOL="$_cli_protocol"
  [ "${PROFILE_CLI:-0}" -eq 1 ] && PROFILE="$_cli_profile"
  if [ "${ADVERTISE_CLI:-0}" -eq 1 ]; then
    ADVERTISE_HOST="$_cli_advertise_host"
    ADVERTISE_PORT="$_cli_advertise_port"
  fi
  if [ "${MTU_CLI:-0}" -eq 1 ]; then
    MTU="$_cli_mtu"
    MTU_POLICY="$_cli_mtu_policy"
    MTU_REQUEST="$_cli_mtu_request"
  fi
  [ "${USERNAME_CLI:-0}" -eq 1 ] && USERNAME="$_cli_user"
  [ "${PASSWORD_CLI:-0}" -eq 1 ] && PASSWORD="$_cli_password"
  if [ "${MIERU_CHANNEL_CLI:-0}" -eq 1 ]; then
    MIERU_CHANNEL="$_cli_mieru_channel"
  fi
  if [ "${MIERU_VERSION_CLI:-0}" -eq 1 ]; then
    MIERU_VERSION="$_cli_mieru_version"
  fi
  [ -z "${PORT:-}" ] || ! valid_port "$PORT" || PORT="$(normalize_uint "$PORT")"
  [ -z "${ADVERTISE_PORT:-}" ] || ! valid_advertise_port "$ADVERTISE_PORT" \
    || ADVERTISE_PORT="$(normalize_uint "$ADVERTISE_PORT")"
  [ -z "${MTU:-}" ] || ! valid_mtu "$MTU" || MTU="$(normalize_uint "$MTU")"
  return 0
}

# ---------- NoBrand Common Core: transport-aware 端口注册表与分配 ----------

nb_normalize_transport() {
  case "$(printf '%s' "${1:-}" | tr '[:lower:]' '[:upper:]')" in
    TCP) printf 'TCP' ;;
    UDP) printf 'UDP' ;;
    *) return 1 ;;
  esac
}

nb_normalized_port_key() {
  local transport port
  transport="$(nb_normalize_transport "${1:-}")" || return 1
  port="$(normalize_uint "${2:-}")" || return 1
  printf '%s:%s' "$(printf '%s' "$transport" | tr '[:upper:]' '[:lower:]')" "$port"
}

# 手工端口允许 1-65535；自动分配始终从 1025 起。Mieru 自身仍通过
# valid_port 保持原有 1025 下限。
nb_valid_port() {
  local port
  port="$(normalize_uint "${1:-}")" || return 1
  [ "${#port}" -le 5 ] && [ "$port" -ge 1 ] && [ "$port" -le 65535 ]
}

# 默认路由出口优先，避免 Docker bridge/第二网卡抢占端口尾号语义。
nb_detect_local_ipv4() {
  local candidate=""
  if [ -n "${NOBRAND_TEST_LOCAL_IPV4:-}" ]; then
    printf '%s' "$NOBRAND_TEST_LOCAL_IPV4"
    return 0
  fi
  if command -v ip >/dev/null 2>&1; then
    candidate="$(ip -4 route get 1.1.1.1 2>/dev/null \
      | awk '{for(i=1;i<=NF;i++) if($i=="src"){print $(i+1); exit}}')" || true
  fi
  if [ -z "$candidate" ] && command -v ip >/dev/null 2>&1; then
    candidate="$(ip -o -4 route show default 2>/dev/null \
      | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}' \
      | while IFS= read -r iface; do
          [ -n "$iface" ] || continue
          ip -o -4 addr show dev "$iface" scope global 2>/dev/null \
            | awk '{split($4,a,"/"); print a[1]; exit}'
          break
        done)" || true
  fi
  if [ -z "$candidate" ]; then
    candidate="$(hostname -I 2>/dev/null | tr ' ' '\n' \
      | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' \
      | grep -vE '^(127|169\.254)\.' | head -n1)" || true
  fi
  case "$candidate" in
    *.*.*.*) printf '%s' "$candidate" ;;
    *) return 1 ;;
  esac
}

nb_port_base_for_ip() {
  local ip="${1:-}" octet base
  octet="${ip##*.}"
  [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
  [[ "$octet" =~ ^[0-9]+$ ]] || return 1
  [ "$octet" -ge 1 ] && [ "$octet" -le 254 ] || return 1
  base=$((10#$octet * 100))
  [ "$base" -ge 1025 ] && [ "$((base + 99))" -le 65535 ] || return 1
  printf '%s' "$base"
}

nb_tail_port_bounds() {
  local ip="${1:-}" base
  [ -n "$ip" ] || ip="$(nb_detect_local_ipv4)" || return 1
  base="$(nb_port_base_for_ip "$ip")" || return 1
  printf '%s|%s' "$((base + 1))" "$((base + 99))"
}

# 尾号算法只把 base+1..base+99 分配给代理。base（xx00）保留给
# 外部 NAT、SSH 或实验室入口等带外设施；这些占用在 guest 内通常不可见。
# 规则由本机默认路由 IPv4 推导，不包含任何环境专用 IP 或端口常量。
nb_tail_base_reservation_owner() {
  local port ip base
  port="$(normalize_uint "${1:-}")" || return 1
  ip="$(nb_detect_local_ipv4 2>/dev/null || true)"
  [ -n "$ip" ] || return 1
  base="$(nb_port_base_for_ip "$ip" 2>/dev/null || true)"
  [ -n "$base" ] && [ "$port" -eq "$base" ] || return 1
  printf 'common:tail-base:%s' "$ip"
}

nb_port_is_tail_base_reserved() {
  nb_tail_base_reservation_owner "$1" >/dev/null 2>&1
}

# 随机起点 + 环形遍历。check_fn 成功表示端口可用。
nb_scan_port_span() {
  local lo="$1" hi="$2" check_fn="$3"
  shift 3
  local span start index offset port
  [ "$lo" -le "$hi" ] || return 1
  span=$((hi - lo + 1))
  if [ -n "${NOBRAND_TEST_RANDOM_START:-}" ]; then
    start=$((NOBRAND_TEST_RANDOM_START % span))
  else
    start=$((RANDOM % span))
  fi
  index=0
  while [ "$index" -lt "$span" ]; do
    offset=$(((start + index) % span))
    port=$((lo + offset))
    if "$check_fn" "$port" "$@"; then
      printf '%s' "$port"
      return 0
    fi
    index=$((index + 1))
  done
  return 1
}

nb_port_bind_probe_in_use() {
  local transport port
  transport="$(nb_normalize_transport "$1")" || return 2
  port="$(normalize_uint "$2")" || return 2
  command -v python3 >/dev/null 2>&1 || return 2
  python3 - "$transport" "$port" <<'PY'
import errno
import socket
import sys

transport, raw_port = sys.argv[1:3]
port = int(raw_port)
sock_type = socket.SOCK_STREAM if transport == "TCP" else socket.SOCK_DGRAM
attempted = False
for family, address in ((socket.AF_INET6, "::"), (socket.AF_INET, "0.0.0.0")):
    try:
        sock = socket.socket(family, sock_type)
    except OSError:
        continue
    attempted = True
    try:
        if family == socket.AF_INET6:
            try:
                sock.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 0)
            except OSError:
                pass
        sock.bind((address, port))
    except OSError as exc:
        sock.close()
        if exc.errno in (errno.EADDRINUSE, errno.EACCES):
            raise SystemExit(0)
        continue
    sock.close()
raise SystemExit(1 if attempted else 2)
PY
}

# 成功表示该 transport 的端口已有 listener。
nb_port_is_listening() {
  local transport port flags
  transport="$(nb_normalize_transport "$1")" || return 1
  port="$(normalize_uint "$2")" || return 1
  if command -v ss >/dev/null 2>&1; then
    [ "$transport" = TCP ] && flags='-Hlnt' || flags='-Hlnu'
    ss "$flags" 2>/dev/null | awk -v port="$port" '
      { for (i=1; i<=NF; i++) if ($i ~ (":" port "$")) { found=1; exit } }
      END { exit(found ? 0 : 1) }
    '
    return $?
  fi
  if command -v netstat >/dev/null 2>&1; then
    [ "$transport" = TCP ] && flags='-lnt' || flags='-lnu'
    netstat "$flags" 2>/dev/null | awk -v port="$port" '
      { for (i=1; i<=NF; i++) if ($i ~ (":" port "$")) { found=1; exit } }
      END { exit(found ? 0 : 1) }
    '
    return $?
  fi
  nb_port_bind_probe_in_use "$transport" "$port"
}

nb_port_listener_details() {
  local transport port flags
  transport="$(nb_normalize_transport "$1")" || return 0
  port="$(normalize_uint "$2")" || return 0
  if command -v ss >/dev/null 2>&1; then
    [ "$transport" = TCP ] && flags='-Hlntp' || flags='-Hlnup'
    ss "$flags" 2>/dev/null | awk -v port="$port" '
      { for (i=1; i<=NF; i++) if ($i ~ (":" port "$")) { print; break } }
    '
  elif command -v netstat >/dev/null 2>&1; then
    [ "$transport" = TCP ] && flags='-lntp' || flags='-lnup'
    netstat "$flags" 2>/dev/null | awk -v port="$port" '
      { for (i=1; i<=NF; i++) if ($i ~ (":" port "$")) { print; break } }
    '
  fi
}

# Return the socket-owner PIDs reported by ss/netstat. Doctor runs as root on
# supported deployments, so ss normally exposes pid=NNN; the netstat form is
# retained for compatibility. An empty result means ownership was not visible.
nb_port_listener_pids() {
  local details
  details="$(nb_port_listener_details "$1" "$2" 2>/dev/null || true)"
  [ -n "$details" ] || return 0
  printf '%s\n' "$details" \
    | sed -nE \
      -e 's/.*pid=([0-9]+).*/\1/p' \
      -e 's/.*[[:space:]]([0-9]+)\/[^[:space:]]+[[:space:]]*$/\1/p' \
    | LC_ALL=C sort -u
}

# 输出 owner|transport|port|advertise_host|advertise_port。Mieru 仍从原
# /var/lib/mita-oneclick adapter 读取，不复制、不迁移其 state。
nb_registry_rows() {
  command -v python3 >/dev/null 2>&1 || return 0
  NOBRAND_SNELL_STATE_DIR="$NOBRAND_SNELL_STATE_DIR" \
  NOBRAND_HY2_STATE_FILE="$NOBRAND_HY2_STATE_FILE" \
  NOBRAND_VLESS_STATE_FILE="$NOBRAND_VLESS_STATE_FILE" \
  MITA_USERS_STATE="$MITA_USERS_STATE" MITA_STATE="$MITA_STATE" \
  python3 - <<'PY'
import glob
import json
import os
import shlex

def emit(owner, transport, port, host="", advertise_port=""):
    try:
        port = int(port)
    except Exception:
        return
    print("%s|%s|%s|%s|%s" % (owner, transport.upper(), port, host or "", advertise_port or ""))

snell_dir = os.environ.get("NOBRAND_SNELL_STATE_DIR", "")
for path in sorted(glob.glob(os.path.join(snell_dir, "*.json"))):
    try:
        state = json.load(open(path, encoding="utf-8"))
        file_id = os.path.basename(path)[:-5]
        instance_id = str(state.get("instance_id") or "")
        version = state.get("version")
        if state.get("protocol") != "snell" or instance_id != file_id or version not in (4, 5):
            continue
        owner = "snell:" + instance_id
        emit(owner, "TCP", state.get("listen_port"), state.get("advertise_host"), state.get("advertise_port"))
        if version == 5 and state.get("managed_udp") is True:
            emit(owner, "UDP", state.get("listen_port"), state.get("advertise_host"), state.get("advertise_port"))
    except Exception:
        continue

hy2_path = os.environ.get("NOBRAND_HY2_STATE_FILE", "")
if hy2_path and os.path.isfile(hy2_path):
    try:
        state = json.load(open(hy2_path, encoding="utf-8"))
        emit("hy2:default", "UDP", state.get("listen_port"), state.get("advertise_host"), state.get("advertise_port"))
    except Exception:
        pass

vless_path = os.environ.get("NOBRAND_VLESS_STATE_FILE", "")
if vless_path and os.path.isfile(vless_path):
    try:
        state = json.load(open(vless_path, encoding="utf-8"))
        emit("vless-sudoku:default", "TCP", state.get("listen_port"),
             state.get("advertise_host"), state.get("advertise_port"))
    except Exception:
        pass

mita_users = os.environ.get("MITA_USERS_STATE", "")
if mita_users and os.path.isfile(mita_users):
    try:
        state = json.load(open(mita_users, encoding="utf-8"))
        protocol = str(state.get("protocol") or "TCP").upper()
        for user in state.get("users") or []:
            port = int(user.get("port"))
            owner = "mieru:" + str(user.get("instance_id") or user.get("name") or port)
            if protocol == "BOTH":
                emit(owner, "TCP", port, user.get("advertise_host"), user.get("advertise_port"))
                advertised = int(user.get("advertise_port") or port)
                emit(owner, "UDP", port + 1, user.get("advertise_host"), advertised + 1)
            else:
                emit(owner, protocol, port, user.get("advertise_host"), user.get("advertise_port"))
    except Exception:
        pass
PY
  # v1.x 单实例安装可能还没有 users.json。只在原 Mieru 安全检查通过后，
  # 于子 shell 中 source allowlisted 字段，避免污染 NoBrand 当前 globals。
  if [ ! -s "$MITA_USERS_STATE" ] && [ -s "$MITA_STATE" ] \
     && state_file_is_secure "$MITA_STATE"; then
    (
      PORT="" PROTOCOL="TCP" ADVERTISE_HOST="" ADVERTISE_PORT=""
      # shellcheck disable=SC1090
      source "$MITA_STATE" 2>/dev/null || exit 0
      nb_valid_port "${PORT:-}" || exit 0
      case "${PROTOCOL:-TCP}" in
        TCP|UDP)
          printf 'mieru:legacy|%s|%s|%s|%s\n' \
            "$PROTOCOL" "$PORT" "${ADVERTISE_HOST:-}" "${ADVERTISE_PORT:-}"
          ;;
        BOTH)
          [ "$PORT" -le 65534 ] || exit 0
          printf 'mieru:legacy|TCP|%s|%s|%s\n' \
            "$PORT" "${ADVERTISE_HOST:-}" "${ADVERTISE_PORT:-}"
          local_udp_advertise=""
          [ -z "${ADVERTISE_PORT:-}" ] || local_udp_advertise=$((ADVERTISE_PORT + 1))
          printf 'mieru:legacy|UDP|%s|%s|%s\n' \
            "$((PORT + 1))" "${ADVERTISE_HOST:-}" "$local_udp_advertise"
          ;;
      esac
    )
  fi
}

nb_registry_port_owner() {
  local transport port ignore_owner="${3:-}" owner row_transport row_port _rest
  transport="$(nb_normalize_transport "$1")" || return 1
  port="$(normalize_uint "$2")" || return 1
  while IFS='|' read -r owner row_transport row_port _rest; do
    [ -n "$owner" ] || continue
    [ "$owner" = "$ignore_owner" ] && continue
    if [ "$row_transport" = "$transport" ] && [ "$row_port" = "$port" ]; then
      printf '%s' "$owner"
      return 0
    fi
  done < <(nb_registry_rows)
  return 1
}

nb_port_available_for_transport() {
  local port="$1" transport="$2" ignore_owner="${3:-}"
  nb_valid_port "$port" || return 1
  transport="$(nb_normalize_transport "$transport")" || return 1
  nb_port_is_tail_base_reserved "$port" && return 1
  nb_registry_port_owner "$transport" "$port" "$ignore_owner" >/dev/null 2>&1 && return 1
  nb_port_is_listening "$transport" "$port" && return 1
  return 0
}

nb_select_available_port() {
  local transport ip bounds lo hi selected attempt random_value
  transport="$(nb_normalize_transport "$1")" || return 1
  ip="$(nb_detect_local_ipv4 2>/dev/null || true)"
  if bounds="$(nb_tail_port_bounds "$ip" 2>/dev/null)"; then
    lo="${bounds%%|*}"
    hi="${bounds#*|}"
    if selected="$(nb_scan_port_span "$lo" "$hi" nb_port_available_for_transport "$transport")"; then
      printf '%s' "$selected"
      return 0
    fi
  fi
  attempt=0
  while [ "$attempt" -lt 512 ]; do
    if command -v openssl >/dev/null 2>&1; then
      random_value="$(openssl rand -hex 2 2>/dev/null || true)"
      if [[ "$random_value" =~ ^[0-9a-fA-F]{4}$ ]]; then
        selected=$((1025 + 16#$random_value % (65535 - 1025 + 1)))
      else
        selected=$((1025 + RANDOM % (65535 - 1025 + 1)))
      fi
    else
      selected=$((1025 + RANDOM % (65535 - 1025 + 1)))
    fi
    if nb_port_available_for_transport "$selected" "$transport"; then
      printf '%s' "$selected"
      return 0
    fi
    attempt=$((attempt + 1))
  done
  return 1
}

nb_warn_if_outside_recommended_range() {
  local port="$1" ip bounds lo hi
  ip="$(nb_detect_local_ipv4 2>/dev/null || true)"
  bounds="$(nb_tail_port_bounds "$ip" 2>/dev/null || true)"
  [ -n "$bounds" ] || return 0
  lo="${bounds%%|*}"
  hi="${bounds#*|}"
  if nb_port_is_tail_base_reserved "$port"; then
    warn "$(t "指定端口 ${port} 是本机尾号段的保留基准端口，不允许代理绑定" \
      "Port ${port} is the reserved base of this host's tail-port range and cannot be used by a proxy")"
    return 0
  fi
  if [ "$port" -lt "$lo" ] || [ "$port" -gt "$hi" ]; then
    warn "$(t "指定端口 ${port} 不在本机 ${ip} 的推荐段 ${lo}-${hi}；确认空闲后仍允许使用" \
      "Port ${port} is outside the recommended ${lo}-${hi} range for ${ip}; it is still allowed when free")"
  fi
}

nb_describe_port_conflict() {
  local transport="$1" port="$2" owner reservation details
  reservation="$(nb_tail_base_reservation_owner "$port" 2>/dev/null || true)"
  [ -z "$reservation" ] || msg "  reserved owner: ${reservation} (tail-port base; external NAT/SSH ownership may be invisible inside the guest)"
  owner="$(nb_registry_port_owner "$transport" "$port" 2>/dev/null || true)"
  [ -z "$owner" ] || msg "  state owner: ${owner}"
  details="$(nb_port_listener_details "$transport" "$port" 2>/dev/null || true)"
  [ -z "$details" ] || printf '%s\n' "$details" | sed 's/^/  listener: /'
}

# ---------- NoBrand Common Core: state、Endpoint、firewall/service adapters ----------

nb_init_state_layout() {
  local tmp
  if [ "${DRY_RUN:-0}" -eq 1 ]; then
    msg "[dry-run] initialize NoBrand state: $NOBRAND_STATE_DIR"
    return 0
  fi
  mkdir -p "$NOBRAND_STATE_DIR" "$NOBRAND_BACKUP_DIR" "$NOBRAND_LOCK_DIR" \
    "$NOBRAND_SNELL_STATE_DIR" "$NOBRAND_HY2_STATE_DIR" \
    "$NOBRAND_VLESS_STATE_DIR" \
    "$NOBRAND_CONFIG_DIR" "$NOBRAND_SNELL_CONFIG_DIR" "$NOBRAND_HY2_CONFIG_DIR" \
    "$NOBRAND_VLESS_CONFIG_DIR" \
    "$NOBRAND_BIN_DIR" "$NOBRAND_SNELL_RUNTIME_DIR" "$NOBRAND_LIB_DIR" \
    || return 1
  chmod 0700 "$NOBRAND_STATE_DIR" "$NOBRAND_BACKUP_DIR" "$NOBRAND_LOCK_DIR" \
    "$NOBRAND_SNELL_STATE_DIR" "$NOBRAND_HY2_STATE_DIR" \
    "$NOBRAND_VLESS_STATE_DIR" \
    "$NOBRAND_CONFIG_DIR" "$NOBRAND_SNELL_CONFIG_DIR" "$NOBRAND_HY2_CONFIG_DIR" \
    "$NOBRAND_VLESS_CONFIG_DIR" \
    "$NOBRAND_LIB_DIR" "$NOBRAND_BIN_DIR" "$NOBRAND_SNELL_RUNTIME_DIR" || return 1
  if [ ! -f "$NOBRAND_REGISTRY_FILE" ]; then
    tmp="$(mktemp "${NOBRAND_REGISTRY_FILE}.tmp.XXXXXX")" || return 1
    printf '%s\n' '{"version":1,"project":"NoBrand-OneClick","author":"ike"}' >"$tmp" \
      && chmod 0600 "$tmp" && mv -f "$tmp" "$NOBRAND_REGISTRY_FILE" \
      || { rm -f "$tmp"; return 1; }
  fi
  chmod 0600 "$NOBRAND_REGISTRY_FILE" 2>/dev/null || return 1
}

nb_atomic_install_file() {
  local source="$1" destination="$2" mode="${3:-0600}" tmp
  [ -f "$source" ] || return 1
  if [ "${DRY_RUN:-0}" -eq 1 ]; then
    msg "[dry-run] install -m ${mode} ${source} ${destination}"
    return 0
  fi
  mkdir -p "$(dirname "$destination")" || return 1
  tmp="$(mktemp "${destination}.tmp.XXXXXX")" || return 1
  if ! install -m "$mode" "$source" "$tmp" || ! mv -f "$tmp" "$destination"; then
    rm -f "$tmp"
    return 1
  fi
}

nb_normalize_endpoint_host() {
  local host="${1:-}"
  command -v python3 >/dev/null 2>&1 || {
    printf '%s' "$(printf '%s' "${host%.}" | tr '[:upper:]' '[:lower:]')"
    return 0
  }
  python3 - "$host" <<'PY'
import ipaddress
import sys
value=sys.argv[1].strip()
try:
    print(ipaddress.ip_address(value))
except ValueError:
    print(value.rstrip('.').lower())
PY
}

nb_validate_advertise_endpoint() {
  local host="${1:-}" port="${2:-}" transport="${3:-TCP}"
  transport="$(printf '%s' "$transport" | tr '[:lower:]' '[:upper:]')"
  case "$transport" in TCP|UDP|BOTH) ;; *) return 1 ;; esac
  if [ -z "$host" ] && [ -z "$port" ]; then
    return 0
  fi
  [ -n "$host" ] && [ -n "$port" ] || return 1
  valid_advertise_host "$host" || return 1
  valid_advertise_port "$port" || return 1
  [ "$transport" != BOTH ] || [ "$(normalize_uint "$port")" -le 65534 ]
}

nb_endpoint_conflict_owner() {
  local transport host port ignore_owner="${4:-}" auto_host owner row_transport listen_port advertise_host advertise_port
  local normalized expected_host effective_host effective_port
  transport="$(nb_normalize_transport "$1")" || return 1
  host="$2"
  port="$(normalize_uint "$3")" || return 1
  expected_host="$(nb_normalize_endpoint_host "$host")"
  auto_host="$(public_ip 2>/dev/null || true)"
  while IFS='|' read -r owner row_transport listen_port advertise_host advertise_port; do
    [ -n "$owner" ] || continue
    [ "$owner" = "$ignore_owner" ] && continue
    [ "$row_transport" = "$transport" ] || continue
    effective_host="${advertise_host:-$auto_host}"
    effective_port="${advertise_port:-$listen_port}"
    [ -n "$effective_host" ] || continue
    normalized="$(nb_normalize_endpoint_host "$effective_host")"
    if [ "$normalized" = "$expected_host" ] && [ "$effective_port" = "$port" ]; then
      printf '%s' "$owner"
      return 0
    fi
  done < <(nb_registry_rows)
  return 1
}

nb_require_explicit_endpoint_noninteractive() {
  [ "${YES:-0}" -eq 1 ] || return 0
  if [ "${ADVERTISE_AUTO_REQUESTED:-0}" -eq 1 ]; then
    return 0
  fi
  if [ "${ADVERTISE_CLI:-0}" -eq 1 ] && [ -n "${ADVERTISE_HOST:-}" ] && [ -n "${ADVERTISE_PORT:-}" ]; then
    return 0
  fi
  die "$(t '非交互模式必须同时提供 --advertise-host/--advertise-port，或明确使用 --advertise-auto' \
    'Non-interactive mode requires --advertise-host with --advertise-port, or explicit --advertise-auto')"
}

nb_collect_advertise_endpoint_interactive() {
  local protocol_name="$1" listen_port="$2" detected="" choice="" host="" port=""
  detected="$(public_ip 2>/dev/null || true)"
  msg ""
  t "${protocol_name} 真实监听端口: ${listen_port}" "${protocol_name} real listen port: ${listen_port}"
  if [ -n "$detected" ]; then
    t "自动检测到客户端入口建议: ${detected}:${listen_port}" \
      "Detected client entry suggestion: ${detected}:${listen_port}"
  else
    warn "$(t '未检测到公网入口；IPLC/NAT 环境请填写实际前置入口' \
      'No public entry detected; enter the actual IPLC/NAT frontend endpoint')"
  fi
  t '  1) 使用自动入口（以后查看节点时重新探测 host；端口等于真实监听）' \
    '  1) Use auto endpoint (host is detected when viewing; port equals listener)'
  t '  2) 自定义客户端入口（IPLC / NAT / DNAT）' \
    '  2) Custom client endpoint (IPLC / NAT / DNAT)'
  read_tty choice "$(t '请选择 [1-2，默认 1]: ' 'Choose [1-2, default 1]: ')" || choice=""
  case "${choice:-1}" in
    2)
      while true; do
        read_tty host "$(t "客户端入口 Host [${detected:-example.com}]: " \
          "Client entry host [${detected:-example.com}]: ")" || host=""
        host="${host:-$detected}"
        read_tty port "$(t "客户端入口 Port [${listen_port}]: " \
          "Client entry port [${listen_port}]: ")" || port=""
        port="${port:-$listen_port}"
        if nb_validate_advertise_endpoint "$host" "$port"; then
          ADVERTISE_HOST="$host"
          ADVERTISE_PORT="$(normalize_uint "$port")"
          ADVERTISE_CLI=1
          ADVERTISE_AUTO_REQUESTED=0
          return 0
        fi
        warn "$(t '入口必须是有效 IPv4/IPv6/域名与 1-65535 端口' \
          'Endpoint must be a valid IPv4/IPv6/domain and port 1-65535')"
      done
      ;;
    *)
      ADVERTISE_HOST=""
      ADVERTISE_PORT=""
      ADVERTISE_CLI=1
      ADVERTISE_AUTO_REQUESTED=1
      ;;
  esac
}

nb_effective_advertise_host() {
  local mode="${1:-auto}" host="${2:-}"
  if [ "$mode" = custom ] && [ -n "$host" ]; then
    printf '%s' "$host"
  else
    public_ip 2>/dev/null || printf 'YOUR_SERVER_IP'
  fi
}

nb_effective_advertise_port() {
  local mode="${1:-auto}" advertise_port="${2:-}" listen_port="${3:-}"
  if [ "$mode" = custom ] && [ -n "$advertise_port" ]; then
    printf '%s' "$advertise_port"
  else
    printf '%s' "$listen_port"
  fi
}

nb_endpoint_mode_from_values() {
  [ -n "${1:-}" ] && printf 'custom' || printf 'auto'
}

nb_firewall_open_pairs() {
  local pairs="$1"
  local MITA_FIREWALL_OWNED_STATE="$NOBRAND_FIREWALL_OWNED_STATE"
  local MITA_FIREWALL_COMMENT="$NOBRAND_FIREWALL_COMMENT"
  open_firewall_for_pairs "$pairs"
}

nb_firewall_close_pairs() {
  local pairs="$1"
  local MITA_FIREWALL_OWNED_STATE="$NOBRAND_FIREWALL_OWNED_STATE"
  local MITA_FIREWALL_COMMENT="$NOBRAND_FIREWALL_COMMENT"
  close_firewall_for_bindings "$pairs"
}

nb_firewall_binding_owned() {
  local transport="$1" port="$2" proto tool
  proto="$(printf '%s' "$transport" | tr '[:upper:]' '[:lower:]')"
  [ -f "$NOBRAND_FIREWALL_OWNED_STATE" ] || return 1
  while IFS='|' read -r tool row_proto row_port; do
    [ "$row_proto" = "$proto" ] && [ "$row_port" = "$port" ] && return 0
  done <"$NOBRAND_FIREWALL_OWNED_STATE"
  return 1
}

nb_service_manager() {
  service_manager
}

nb_service_is_active() {
  local systemd_unit="$1" openrc_service="$2" manager
  manager="$(nb_service_manager)"
  case "$manager" in
    systemd) systemctl is-active --quiet "$systemd_unit" 2>/dev/null ;;
    openrc) rc-service "$openrc_service" status 2>/dev/null | grep -qiE 'started|running' ;;
    *) return 1 ;;
  esac
}

nb_wait_for_listener() {
  local transport="$1" port="$2" timeout="${3:-20}" elapsed=0
  while [ "$elapsed" -lt "$timeout" ]; do
    nb_port_is_listening "$transport" "$port" && return 0
    sleep 1
    elapsed=$((elapsed + 1))
  done
  return 1
}

# ---------- NoBrand Common Core: 入口、节点聚合、状态、Doctor、备份 ----------

nobrand_print_banner() {
  msg ""
  msg '========================================'
  printf '          %s v%s\n' "$SCRIPT_NAME" "$SCRIPT_VERSION"
  msg '========================================'
  t "Author: ${SCRIPT_AUTHOR}" "Author: ${SCRIPT_AUTHOR}"
}

nobrand_version() {
  printf '%s %s\nAuthor: %s\n' "$SCRIPT_NAME" "$SCRIPT_VERSION" "$SCRIPT_AUTHOR"
}

nobrand_usage() {
  cat <<'EOF'
NoBrand-OneClick — Mieru / Snell v4-v5 / Hysteria2 / VLESS + FinalMask + Sudoku (TCP)

用法:
  nobrand                         打开统一菜单
  nobrand --version               显示产品版本与作者
  nobrand status                  综合状态
  nobrand nodes [--protocol P]    查看全部或指定协议节点
  nobrand doctor                  综合诊断（默认不输出 secret）
  nobrand backup create [FILE]    备份 NoBrand Snell/HY2/VLESS state 与配置
  nobrand backup restore FILE     恢复 NoBrand 备份
  nobrand uninstall [-y]          只删除 NoBrand 的 Snell/HY2/VLESS/Common 内容

  nobrand mieru <原 mita 子命令与参数>
  nobrand snell install --name NAME [--version 5|4] [--port PORT] [--quic on|off]
      [--advertise-host HOST --advertise-port PORT | --advertise-auto] [-y]
  nobrand snell show|status|doctor|start|stop|restart|remove [--name NAME]
  nobrand snell set-quic --name NAME --quic on|off [-y]
  nobrand snell set-endpoint --name NAME
      [--advertise-host HOST --advertise-port PORT | --advertise-auto]

  nobrand hy2 install [--port PORT] [--sni SNI]
      [--advertise-host HOST --advertise-port PORT | --advertise-auto] [-y]
  nobrand hy2 show|status|doctor|start|stop|restart|remove
  nobrand hy2 set-endpoint
      [--advertise-host HOST --advertise-port PORT | --advertise-auto]

  nobrand vless-sudoku install [--port PORT]
      [--advertise-host HOST --advertise-port PORT | --advertise-auto] [-y]
  nobrand vless-sudoku show|status|doctor|smoke|start|stop|restart|remove
  nobrand vless-sudoku set-endpoint
      [--advertise-host HOST --advertise-port PORT | --advertise-auto]

说明:
  - Snell 只支持 v5（默认/推荐）与 v4（兼容）。
  - Snell v5 QUIC 默认关闭；--quic on 才让 NoBrand 管理同号 UDP firewall ownership。
  - 官方 v5 runtime 即使 QUIC 关闭也可能监听同号 UDP；本地 socket 不等于公网 QUIC 已启用。
  - Display Endpoint 只影响客户端输出，不创建 DNAT/IPLC 转发，也不改 listener。
  - 非交互 -y 必须明确给出完整 Display Endpoint 或 --advertise-auto。
  - VLESS Sudoku = plain VLESS + FinalMask(sudoku) + TCP。
  - VLESS Encryption: NOT USED；不调用密钥生成子命令，不保存加密密钥。
EOF
}

nobrand_install_manager_script() {
  local source_path="" source_real="" destination_real=""
  if [ "${DRY_RUN:-0}" -eq 1 ]; then
    msg "[dry-run] install NoBrand manager and nobrand/nb commands"
    return 0
  fi
  if [ -n "${BASH_SOURCE[0]:-}" ] && [ -r "${BASH_SOURCE[0]}" ] \
     && grep -qxF "SCRIPT_NAME=\"NoBrand-OneClick\"" "${BASH_SOURCE[0]}" 2>/dev/null; then
    source_path="${BASH_SOURCE[0]}"
  elif [ -r "$INSTALL_SCRIPT_PATH" ] \
       && grep -qxF "SCRIPT_NAME=\"NoBrand-OneClick\"" "$INSTALL_SCRIPT_PATH" 2>/dev/null; then
    source_path="$INSTALL_SCRIPT_PATH"
  elif [ -r "$NOBRAND_INSTALL_SCRIPT_PATH" ]; then
    source_path="$NOBRAND_INSTALL_SCRIPT_PATH"
  fi
  [ -n "$source_path" ] || {
    warn "$(t '找不到当前 NoBrand 单文件安装器，未安装统一快捷命令' \
      'Current NoBrand single-file installer not found; unified shortcuts were not installed')"
    return 1
  }
  source_real="$(readlink -f "$source_path" 2>/dev/null || realpath "$source_path" 2>/dev/null || printf '%s' "$source_path")"
  destination_real="$(readlink -f "$NOBRAND_INSTALL_SCRIPT_PATH" 2>/dev/null \
    || realpath "$NOBRAND_INSTALL_SCRIPT_PATH" 2>/dev/null || printf '%s' "$NOBRAND_INSTALL_SCRIPT_PATH")"
  if [ "$source_real" != "$destination_real" ]; then
    install -m 0755 "$source_path" "$NOBRAND_INSTALL_SCRIPT_PATH" || return 1
  else
    chmod 0755 "$NOBRAND_INSTALL_SCRIPT_PATH" || return 1
  fi
  local wrapper
  wrapper="$(mktemp_file .sh)" || return 1
  cat >"$wrapper" <<EOF
#!/usr/bin/env bash
exec ${NOBRAND_INSTALL_SCRIPT_PATH} "\$@"
EOF
  chmod 0755 "$wrapper" || { rm -f "$wrapper"; return 1; }
  install -m 0755 "$wrapper" "$NOBRAND_COMMAND_PATH" || { rm -f "$wrapper"; return 1; }
  install -m 0755 "$wrapper" "$NOBRAND_SHORT_COMMAND_PATH" || { rm -f "$wrapper"; return 1; }
  rm -f "$wrapper"
}

nb_mieru_instance_running() {
  local instance_id="$1" transport="$2" port="$3" unit service
  unit="mita-oneclick@${instance_id}.service"
  service="mita-oneclick-${instance_id}"
  nb_service_is_active "$unit" "$service" || return 1
  case "$transport" in
    BOTH) nb_port_is_listening TCP "$port" && nb_port_is_listening UDP "$((port + 1))" ;;
    *) nb_port_is_listening "$transport" "$port" ;;
  esac
}

# protocol|name|display endpoint|status|transport
nb_mieru_legacy_node_rows() {
  local values name port protocol advertise_host advertise_port auto_host effective_host effective_port status
  [ -s "$MITA_STATE" ] && state_file_is_secure "$MITA_STATE" || return 0
  values="$(
    PORT="" PROTOCOL="TCP" ADVERTISE_HOST="" ADVERTISE_PORT="" USERNAME="legacy"
    # shellcheck disable=SC1090
    source "$MITA_STATE" 2>/dev/null || exit 0
    nb_valid_port "${PORT:-}" || exit 0
    case "${PROTOCOL:-TCP}" in TCP|UDP|BOTH) ;; *) exit 0 ;; esac
    printf '%s\t%s\t%s\t%s\t%s' "${USERNAME:-legacy}" "$PORT" "$PROTOCOL" \
      "${ADVERTISE_HOST:-}" "${ADVERTISE_PORT:-}"
  )"
  [ -n "$values" ] || return 0
  IFS=$'\t' read -r name port protocol advertise_host advertise_port <<<"$values"
  auto_host="$(public_ip 2>/dev/null || printf 'YOUR_SERVER_IP')"
  effective_host="${advertise_host:-$auto_host}"
  effective_port="${advertise_port:-$port}"
  status=Stopped
  if nb_service_is_active mita.service mita; then
    case "$protocol" in
      TCP|UDP) nb_port_is_listening "$protocol" "$port" && status=Running ;;
      BOTH) nb_port_is_listening TCP "$port" && nb_port_is_listening UDP "$((port + 1))" && status=Running ;;
    esac
  fi
  if [ "$protocol" = BOTH ]; then
    printf 'Mieru/BOTH|%s|%s:%s (TCP), %s:%s (UDP)|%s|BOTH\n' \
      "$name" "$effective_host" "$effective_port" "$effective_host" "$((effective_port + 1))" "$status"
  else
    printf 'Mieru/%s|%s|%s:%s|%s|%s\n' \
      "$protocol" "$name" "$effective_host" "$effective_port" "$status" "$protocol"
  fi
}

nb_mieru_node_rows() {
  local auto_host instance_id name port protocol advertise_host advertise_port effective_host effective_port status
  if [ ! -s "$MITA_USERS_STATE" ]; then
    nb_mieru_legacy_node_rows
    return 0
  fi
  command -v python3 >/dev/null 2>&1 || return 0
  auto_host="$(public_ip 2>/dev/null || printf 'YOUR_SERVER_IP')"
  while IFS=$'\t' read -r instance_id name port protocol advertise_host advertise_port; do
    [ -n "$name" ] || continue
    effective_host="${advertise_host:-$auto_host}"
    effective_port="${advertise_port:-$port}"
    status=Stopped
    nb_mieru_instance_running "$instance_id" "$protocol" "$port" && status=Running
    if [ "$protocol" = BOTH ]; then
      printf 'Mieru/BOTH|%s|%s:%s (TCP), %s:%s (UDP)|%s|BOTH\n' \
        "$name" "$effective_host" "$effective_port" "$effective_host" "$((effective_port + 1))" "$status"
    else
      printf 'Mieru/%s|%s|%s:%s|%s|%s\n' \
        "$protocol" "$name" "$effective_host" "$effective_port" "$status" "$protocol"
    fi
  done < <(python3 - "$MITA_USERS_STATE" <<'PY'
import json,sys
try:
    state=json.load(open(sys.argv[1], encoding="utf-8"))
except Exception:
    raise SystemExit(0)
protocol=str(state.get("protocol") or "TCP").upper()
for user in state.get("users") or []:
    print("\t".join(str(v or "") for v in (
        user.get("instance_id"), user.get("name"), user.get("port"), protocol,
        user.get("advertise_host"), user.get("advertise_port"))))
PY
  )
}

nb_all_node_rows() {
  local filter
  filter="$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')"
  case "$filter" in
    ""|all)
      nb_mieru_node_rows
      snell_node_rows
      hysteria2_node_rows
      vless_sudoku_node_rows
      ;;
    mieru) nb_mieru_node_rows ;;
    snell) snell_node_rows ;;
    hy2|hysteria2) hysteria2_node_rows ;;
    vless-sudoku|sudoku|vless) vless_sudoku_node_rows ;;
    *) die "--protocol 只支持 mieru、snell、hy2、vless-sudoku" ;;
  esac
}

nobrand_nodes() {
  local rows protocol name endpoint status transport
  rows="$(nb_all_node_rows "${NOBRAND_PROTOCOL_FILTER:-}")"
  nobrand_print_banner
  msg ""
  t '协议              节点              客户端入口                              状态' \
    'Protocol          Node              Client endpoint                         Status'
  msg '--------------------------------------------------------------------------------------'
  if [ -z "$rows" ]; then
    t '暂无持久化节点。' 'No persistent nodes.'
    return 0
  fi
  while IFS='|' read -r protocol name endpoint status transport; do
    [ -n "$protocol" ] || continue
    printf '%-17s %-17s %-40s %s\n' "$protocol" "$name" "$endpoint" "$status"
  done <<<"$rows"
}

nobrand_status() {
  local rows protocol _name _endpoint status _transport
  local mieru_total=0 mieru_running=0 snell_total=0 snell_running=0 hy2_total=0 hy2_running=0
  local vless_total=0 vless_running=0 vless_port=""
  rows="$(nb_all_node_rows)"
  while IFS='|' read -r protocol _name _endpoint status _transport; do
    case "$protocol" in
      Mieru/*) mieru_total=$((mieru_total + 1)); [ "$status" != Running ] || mieru_running=$((mieru_running + 1)) ;;
      Snell*) snell_total=$((snell_total + 1)); [ "$status" != Running ] || snell_running=$((snell_running + 1)) ;;
      Hysteria2) hy2_total=$((hy2_total + 1)); [ "$status" != Running ] || hy2_running=$((hy2_running + 1)) ;;
      VLESS/Sudoku)
        vless_total=$((vless_total + 1))
        [ "$status" != Running ] || vless_running=$((vless_running + 1))
        vless_port="$(vless_sudoku_state_field listen_port 2>/dev/null || true)"
        ;;
    esac
  done <<<"$rows"
  nobrand_print_banner
  msg ""
  printf 'Mieru\n  Installed: %s\n  Users: %s\n  Running: %s/%s\n' \
    "$([ "$mieru_total" -gt 0 ] && printf yes || printf no)" "$mieru_total" "$mieru_running" "$mieru_total"
  printf 'Snell\n  Instances: %s\n  Running: %s/%s\n' "$snell_total" "$snell_running" "$snell_total"
  printf 'Hysteria2\n  Installed: %s\n  Running: %s\n' \
    "$([ "$hy2_total" -gt 0 ] && printf yes || printf no)" \
    "$([ "$hy2_running" -gt 0 ] && printf yes || printf no)"
  printf 'VLESS/Sudoku\n  Installed: %s\n  Running: %s\n  Port: %s\n' \
    "$([ "$vless_total" -gt 0 ] && printf yes || printf no)" \
    "$([ "$vless_running" -gt 0 ] && printf yes || printf no)" \
    "${vless_port:--}"
}

nb_doctor_line() {
  local level="$1"
  shift
  printf '[%s] %s\n' "$level" "$*"
}

nobrand_doctor_common() {
  local failed=0 manager arch_value
  [ "$(id -u 2>/dev/null || printf 1)" -eq 0 ] \
    && nb_doctor_line PASS 'root' || { nb_doctor_line FAIL '需要 root'; failed=1; }
  [ "$(uname -s 2>/dev/null || true)" = Linux ] \
    && nb_doctor_line PASS 'Linux' || { nb_doctor_line FAIL '仅支持 Linux'; failed=1; }
  arch_value="$(uname -m 2>/dev/null || printf unknown)"
  case "$arch_value" in
    x86_64|amd64|aarch64|arm64) nb_doctor_line PASS "arch=${arch_value}" ;;
    *) nb_doctor_line WARN "arch=${arch_value}（Snell 可能不支持）" ;;
  esac
  [ -d "$NOBRAND_STATE_DIR" ] && [ -w "$NOBRAND_STATE_DIR" ] \
    && nb_doctor_line PASS "state writable: $NOBRAND_STATE_DIR" \
    || nb_doctor_line WARN "state 尚未初始化或不可写: $NOBRAND_STATE_DIR"
  command -v ss >/dev/null 2>&1 || command -v netstat >/dev/null 2>&1 \
    && nb_doctor_line PASS 'port tool' || nb_doctor_line WARN '无 ss/netstat，将使用 bind probe'
  if command -v ufw >/dev/null 2>&1; then
    nb_doctor_line PASS 'firewall=ufw'
  elif command -v firewall-cmd >/dev/null 2>&1; then
    nb_doctor_line PASS 'firewall=firewalld'
  elif command -v iptables >/dev/null 2>&1; then
    nb_doctor_line PASS 'firewall=iptables'
  else
    nb_doctor_line WARN '未检测到本地 firewall backend'
  fi
  manager="$(nb_service_manager)"
  [ "$manager" != none ] && nb_doctor_line PASS "service-manager=${manager}" \
    || { nb_doctor_line FAIL '未检测到 systemd/OpenRC'; failed=1; }
  if bbr_fq_active 2>/dev/null; then
    nb_doctor_line PASS 'BBR/FQ active'
  else
    nb_doctor_line INFO 'BBR/FQ not active（可选）'
  fi
  return "$failed"
}

nobrand_doctor() {
  local failed=0
  nobrand_print_banner
  msg ''
  msg 'Common Core'
  nobrand_doctor_common || failed=1
  if mita_installed 2>/dev/null || [ -s "$MITA_USERS_STATE" ]; then
    msg ''
    msg 'Mieru'
    do_doctor || failed=1
  fi
  msg ''
  msg 'Snell'
  snell_doctor_all || failed=1
  msg ''
  msg 'Hysteria2'
  hysteria2_doctor || failed=1
  msg ''
  msg 'VLESS + FinalMask + Sudoku (TCP)'
  vless_sudoku_doctor || failed=1
  [ "$failed" -eq 0 ] || return 1
}

nb_backup_default_path() {
  printf '%s/nobrand-backup-%s.tar.gz' "$NOBRAND_BACKUP_DIR" "$(date +%Y%m%d_%H%M%S)"
}

nb_assert_safe_nobrand_root() {
  local value="${1:-}" label="${2:-path}" normalized
  [ -n "$value" ] || die "${label} 为空，拒绝破坏性操作"
  case "$value" in
    *'..'*) die "${label} 含有 ..，拒绝破坏性操作: $value" ;;
  esac
  normalized="$(readlink -m -- "$value" 2>/dev/null \
    || realpath -m -- "$value" 2>/dev/null || printf '%s' "$value")"
  case "$normalized" in
    /|/etc|/var|/usr|/usr/local) die "${label} 过宽，拒绝破坏性操作: $normalized" ;;
  esac
  case "$normalized" in
    */nobrand-oneclick|*/nobrand-oneclick/*|*/nobrand-oneclick-*) ;;
    *) die "${label} 不在明确的 NoBrand namespace 中: $normalized" ;;
  esac
  printf '%s' "$normalized"
}

nobrand_backup_create() {
  local destination="${1:-}" stage archive_tmp
  nb_init_state_layout || return 1
  [ -n "$destination" ] || destination="$(nb_backup_default_path)"
  stage="$(mktemp_dir)" || return 1
  mkdir -p "$stage/state" "$stage/config" || { rm -rf -- "$stage"; return 1; }
  cp -a "$NOBRAND_STATE_DIR/." "$stage/state/" || { rm -rf -- "$stage"; return 1; }
  cp -a "$NOBRAND_CONFIG_DIR/." "$stage/config/" || { rm -rf -- "$stage"; return 1; }
  cat >"$stage/manifest.txt" <<EOF
project=NoBrand-OneClick
version=${SCRIPT_VERSION}
created_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
contents=state,config
EOF
  archive_tmp="$(mktemp_file .tar.gz)" || { rm -rf -- "$stage"; return 1; }
  if ! tar -C "$stage" -czf "$archive_tmp" manifest.txt state config; then
    rm -f "$archive_tmp"
    rm -rf -- "$stage"
    return 1
  fi
  mkdir -p "$(dirname "$destination")" || { rm -f "$archive_tmp"; rm -rf -- "$stage"; return 1; }
  chmod 0600 "$archive_tmp" || { rm -f "$archive_tmp"; rm -rf -- "$stage"; return 1; }
  mv -f "$archive_tmp" "$destination" || { rm -f "$archive_tmp"; rm -rf -- "$stage"; return 1; }
  rm -rf -- "$stage"
  t "NoBrand 备份已保存: ${destination}" "NoBrand backup saved: ${destination}"
}

nobrand_backup_list() {
  find "$NOBRAND_BACKUP_DIR" -maxdepth 1 -type f -name 'nobrand-backup-*.tar.gz' \
    -print 2>/dev/null | LC_ALL=C sort -r
}

nobrand_backup_restore() {
  local source="$1" stage snapshot safe_state safe_config
  [ -f "$source" ] || die "备份不存在: $source"
  safe_state="$(nb_assert_safe_nobrand_root "$NOBRAND_STATE_DIR" NOBRAND_STATE_DIR)" || return 1
  safe_config="$(nb_assert_safe_nobrand_root "$NOBRAND_CONFIG_DIR" NOBRAND_CONFIG_DIR)" || return 1
  tar -tzf "$source" 2>/dev/null | awk '
    /^\// || /(^|\/)\.\.($|\/)/ { bad=1 }
    END { exit bad ? 1 : 0 }
  ' || die '备份包含不安全路径，拒绝恢复'
  stage="$(mktemp_dir)" || return 1
  tar -C "$stage" -xzf "$source" || { rm -rf -- "$stage"; return 1; }
  grep -qx 'project=NoBrand-OneClick' "$stage/manifest.txt" 2>/dev/null \
    || { rm -rf -- "$stage"; die '不是 NoBrand-OneClick 备份'; }
  find "$stage/state" "$stage/config" -type f -name '*.json' -print0 2>/dev/null \
    | while IFS= read -r -d '' file; do jq empty "$file" >/dev/null || exit 1; done \
    || { rm -rf -- "$stage"; die '备份中存在无效 JSON'; }
  snapshot="$(mktemp_dir)" || { rm -rf -- "$stage"; return 1; }
  mkdir -p "$snapshot/state" "$snapshot/config"
  cp -a "$safe_state/." "$snapshot/state/" 2>/dev/null || true
  cp -a "$safe_config/." "$snapshot/config/" 2>/dev/null || true
  nobrand_stop_all_services 2>/dev/null || true
  if ! find "$safe_state" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + \
     || ! find "$safe_config" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + \
     || ! cp -a "$stage/state/." "$safe_state/" \
     || ! cp -a "$stage/config/." "$safe_config/"; then
    find "$safe_state" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + 2>/dev/null || true
    find "$safe_config" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + 2>/dev/null || true
    cp -a "$snapshot/state/." "$safe_state/" 2>/dev/null || true
    cp -a "$snapshot/config/." "$safe_config/" 2>/dev/null || true
    rm -rf -- "$stage" "$snapshot"
    die '恢复失败，已回滚原 NoBrand state/config'
  fi
  nb_init_state_layout
  if ! snell_migrate_removed_v6; then
    find "$safe_state" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + 2>/dev/null || true
    find "$safe_config" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + 2>/dev/null || true
    cp -a "$snapshot/state/." "$safe_state/" 2>/dev/null || true
    cp -a "$snapshot/config/." "$safe_config/" 2>/dev/null || true
    rm -rf -- "$stage" "$snapshot"
    die '备份包含无法安全迁移的已移除 Snell v6 state；已回滚原 NoBrand state/config'
  fi
  nobrand_start_enabled_services || {
    warn '配置已恢复，但部分服务未能启动；请运行 nobrand doctor'
  }
  rm -rf -- "$stage" "$snapshot"
  t 'NoBrand 备份恢复完成' 'NoBrand backup restored'
}

nobrand_backup_action() {
  case "${NOBRAND_BACKUP_ACTION:-create}" in
    create) nobrand_backup_create "${NOBRAND_BACKUP_PATH:-}" ;;
    list) nobrand_backup_list ;;
    restore)
      [ -n "${NOBRAND_BACKUP_PATH:-}" ] || die 'backup restore 需要文件路径'
      nobrand_backup_restore "$NOBRAND_BACKUP_PATH"
      ;;
  esac
}

nobrand_remove_owned_command() {
  local path="$1"
  [ -f "$path" ] && [ ! -L "$path" ] || return 0
  case "$path" in
    /usr/local/bin/install-nobrand|/usr/local/bin/nobrand|/usr/local/bin/nb|*/nobrand-oneclick/*|*/nobrand-oneclick-*/*) ;;
    *) warn "拒绝删除 NoBrand command allowlist 以外的路径: $path"; return 1 ;;
  esac
  if grep -qF 'NoBrand-OneClick' "$path" 2>/dev/null \
     || grep -qF "$NOBRAND_INSTALL_SCRIPT_PATH" "$path" 2>/dev/null; then
    rm -f "$path"
  else
    warn "拒绝删除内容不属于 NoBrand 的命令: $path"
    return 1
  fi
}

nobrand_uninstall() {
  local id port safe_state safe_config safe_lib pairs="" snell_pairs failed=0
  require_root
  if [ "${YES:-0}" -ne 1 ]; then
    confirm '确认删除 NoBrand 管理的 Snell/HY2/VLESS/Common state？Mieru 数据会保留。[y/N]: ' \
      'Remove NoBrand-managed Snell/HY2/VLESS/Common state? Mieru data is preserved. [y/N]: ' \
      n \
      || { t '已取消' 'Cancelled'; return 0; }
  fi
  safe_state="$(nb_assert_safe_nobrand_root "$NOBRAND_STATE_DIR" NOBRAND_STATE_DIR)" || return 1
  safe_config="$(nb_assert_safe_nobrand_root "$NOBRAND_CONFIG_DIR" NOBRAND_CONFIG_DIR)" || return 1
  safe_lib="$(nb_assert_safe_nobrand_root "$NOBRAND_LIB_DIR" NOBRAND_LIB_DIR)" || return 1
  admin_lock_acquire || return 1
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    port="$(snell_state_field "$id" listen_port 2>/dev/null || true)"
    snell_pairs="$(snell_firewall_pairs "$id" 2>/dev/null || true)"
    snell_remove_service "$id" || failed=1
    [ -z "$snell_pairs" ] || nb_firewall_close_pairs "$snell_pairs" || failed=1
  done < <(snell_instance_ids)
  if hysteria2_state_exists; then
    port="$(hysteria2_state_field listen_port 2>/dev/null || true)"
    nobrand_remove_hy2_service || failed=1
    [ -z "$port" ] || nb_firewall_close_pairs "UDP|${port}" || failed=1
  fi
  if vless_sudoku_state_exists; then
    port="$(vless_sudoku_state_field listen_port 2>/dev/null || true)"
    nobrand_remove_vless_sudoku_service || failed=1
    [ -z "$port" ] || nb_firewall_close_pairs "TCP|${port}" || failed=1
  fi
  # 清理可能由失败事务留下、但仍明确记录为 NoBrand-owned 的 firewall rows。
  if [ -s "$NOBRAND_FIREWALL_OWNED_STATE" ]; then
    while IFS='|' read -r _tool proto row_port; do
      case "$proto" in
        tcp|udp) printf -v pairs '%s%s|%s\n' "$pairs" "$(printf '%s' "$proto" | tr '[:lower:]' '[:upper:]')" "$row_port" ;;
      esac
    done <"$NOBRAND_FIREWALL_OWNED_STATE"
    [ -z "$pairs" ] || nb_firewall_close_pairs "$pairs" || failed=1
  fi
  if [ "$failed" -ne 0 ]; then
    admin_lock_release
    warn 'NoBrand service/firewall 清理未完整完成；保留 state 以便重试'
    return 1
  fi
  case "$NOBRAND_SNELL_SYSTEMD_TEMPLATE" in
    /etc/systemd/system/nobrand-snell@.service) rm -f "$NOBRAND_SNELL_SYSTEMD_TEMPLATE" ;;
  esac
  [ "$(nb_service_manager)" != systemd ] || systemctl daemon-reload 2>/dev/null || true
  find "$safe_state" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
  find "$safe_config" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
  find "$safe_lib" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
  rmdir "$safe_state" "$safe_config" "$safe_lib" 2>/dev/null || true
  nobrand_remove_owned_command "$NOBRAND_COMMAND_PATH" || failed=1
  nobrand_remove_owned_command "$NOBRAND_SHORT_COMMAND_PATH" || failed=1
  nobrand_remove_owned_command "$NOBRAND_INSTALL_SCRIPT_PATH" || failed=1
  admin_lock_release
  [ "$failed" -eq 0 ] || return 1
  t 'NoBrand Snell/HY2/VLESS/Common 内容已删除；Mieru、/etc/xray、xray.service、ike 均未触碰' \
    'NoBrand Snell/HY2/VLESS/Common content removed; Mieru, /etc/xray, xray.service, and ike were untouched'
}

nobrand_stop_all_services() {
  local id
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    snell_service_action "$id" stop >/dev/null 2>&1 || true
  done < <(snell_instance_ids)
  hysteria2_state_exists && nobrand_hy2_service_action stop >/dev/null 2>&1 || true
  vless_sudoku_state_exists \
    && nobrand_vless_sudoku_service_action stop >/dev/null 2>&1 || true
}

nobrand_start_enabled_services() {
  local id enabled port pairs failed=0
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    enabled="$(snell_state_field "$id" enabled 2>/dev/null || printf false)"
    [ "$enabled" = true ] || continue
    port="$(snell_state_field "$id" listen_port)"
    pairs="$(snell_firewall_pairs "$id")"
    nb_firewall_open_pairs "$pairs" >/dev/null 2>&1 \
      && snell_service_action "$id" start >/dev/null 2>&1 \
      && snell_wait_for_required_listeners "$id" 25 || failed=1
  done < <(snell_instance_ids)
  if hysteria2_state_exists \
     && [ "$(hysteria2_state_field enabled 2>/dev/null || printf false)" = true ]; then
    port="$(hysteria2_state_field listen_port)"
    nobrand_hy2_service_action start >/dev/null 2>&1 \
      && nb_wait_for_listener UDP "$port" 25 || failed=1
  fi
  if vless_sudoku_state_exists \
     && [ "$(vless_sudoku_state_field enabled 2>/dev/null || printf false)" = true ]; then
    port="$(vless_sudoku_state_field listen_port)"
    nobrand_vless_sudoku_service_action start >/dev/null 2>&1 \
      && nb_wait_for_listener TCP "$port" 25 || failed=1
  fi
  return "$failed"
}

install_self_script() {
  STAGE="安装管理脚本"
  local main_url="https://raw.githubusercontent.com/ike-sh/NoBrand-OneClick/main/install-nobrand.sh"
  local tmp src_real="" dest_real="" installed=0
  tmp="$(mktemp_file .sh)"
  # 已发布版本优先；下载到临时文件且版本必须精确匹配，避免截断现有脚本或被 main 降级。
  if curl -fsSL --connect-timeout 15 --max-time 60 "$SCRIPT_REPO_RAW" -o "$tmp" 2>/dev/null \
     && grep -qxF "SCRIPT_VERSION=\"${SCRIPT_VERSION}\"" "$tmp"; then
    run install -m 0755 "$tmp" "$INSTALL_SCRIPT_PATH"
    installed=1
  elif [ -n "${BASH_SOURCE[0]:-}" ] && [ -r "${BASH_SOURCE[0]}" ] \
       && grep -qxF "SCRIPT_VERSION=\"${SCRIPT_VERSION}\"" "${BASH_SOURCE[0]}" 2>/dev/null; then
    src_real="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null \
      || realpath "${BASH_SOURCE[0]}" 2>/dev/null || printf '%s' "${BASH_SOURCE[0]}")"
    dest_real="$(readlink -f "$INSTALL_SCRIPT_PATH" 2>/dev/null \
      || realpath "$INSTALL_SCRIPT_PATH" 2>/dev/null || printf '%s' "$INSTALL_SCRIPT_PATH")"
    if [ "$src_real" != "$dest_real" ]; then
      run install -m 0755 "${BASH_SOURCE[0]}" "$INSTALL_SCRIPT_PATH"
    else
      run chmod 0755 "$INSTALL_SCRIPT_PATH"
    fi
    installed=1
  elif curl -fsSL --connect-timeout 15 --max-time 60 "$main_url" -o "$tmp" 2>/dev/null \
       && grep -qxF "SCRIPT_VERSION=\"${SCRIPT_VERSION}\"" "$tmp"; then
    run install -m 0755 "$tmp" "$INSTALL_SCRIPT_PATH"
    installed=1
  fi
  rm -f "$tmp"
  [ "$installed" -eq 1 ] || die "$(t '无法取得与当前版本一致的管理脚本，拒绝用其它版本覆盖' \
    'Could not obtain the exact current manager version; refusing to overwrite with another version')"
  install_mita_wrapper_force
  migrate_mita_binary_layout
  install_mita_shortcuts
  # NoBrand 的统一入口与 Mieru 兼容入口使用同一份生成脚本；保留 install-mita/mita。
  nobrand_install_manager_script || true
}

install_mita_wrapper_force() {
  if is_mita_wrapper "$MITA_BIN"; then
    return 0
  fi
  if mita_installed || [ -f "$MITA_MARKER" ] || [ -x "$INSTALL_SCRIPT_PATH" ]; then
    install_mita_wrapper
  fi
}

ensure_management_scripts() {
  STAGE="更新管理脚本"
  install_self_script
  repair_mita_binary_paths
}

install_mita_wrapper() {
  STAGE="安装 mita 快捷入口"
  cat >"$MITA_BIN" <<'EOF'
#!/usr/bin/env bash
# mieru-OneClick mita wrapper — 无参数打开菜单；管理子命令不区分大小写
INSTALL_MITA="/usr/local/bin/install-mita"

find_mita_real() {
  local c
  for c in /usr/local/bin/mita-real /usr/bin/mita; do
    [ -x "$c" ] || continue
    [ "$(head -c 4 "$c" 2>/dev/null || true)" = $'\x7fELF' ] || continue
    printf '%s' "$c"
    return 0
  done
  return 1
}

MITA_REAL="$(find_mita_real || true)"

if [ $# -eq 0 ]; then
  if [ -x "$INSTALL_MITA" ]; then
    exec "$INSTALL_MITA"
  fi
  echo "[错误] 未找到 install-mita，请先运行一键安装脚本" >&2
  echo "  curl -fsSL https://raw.githubusercontent.com/ike-sh/NoBrand-OneClick/main/install-mita.sh | bash" >&2
  exit 1
fi

  if [ $# -gt 0 ] && [ -x "$INSTALL_MITA" ]; then
    cmd="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
    case "$cmd" in
      menu|install|upgrade|uninstall|status|reconfigure|client-config|show|mtu|mtu-config|set-mtu|profile|profile-config|perf|start|stop|restart|配置|节点|help|\
      users|user-list|user-add|user-del|user-delete|user-show|user-manage|user-set-endpoint|\
      user-set-quota|user-set-expire|user-enable|user-disable|user-scan|user-quota-reset|\
      user-set-rate|user-set-bandwidth|rate-status|rate-restore|tc-status|tc-restore|\
      user-usage|usage|user-export-clients|user-backup|user-restore|user-export|user-import|\
      doctor|verify)
        shift
        exec "$INSTALL_MITA" "$cmd" "$@"
        ;;
    esac
  fi

if [ -z "$MITA_REAL" ]; then
  echo "[错误] 未找到 mita 二进制；请重新运行安装脚本并选择「升级」自动重装：" >&2
  echo "  curl -fsSL https://raw.githubusercontent.com/ike-sh/NoBrand-OneClick/main/install-mita.sh | sudo bash -s -- upgrade -y" >&2
  exit 127
fi
exec "$MITA_REAL" "$@"
EOF
  run chmod 0755 "$MITA_BIN"
  hash -r 2>/dev/null || true
}

# 重新下载官方包并安装，修复缺失的 mita 二进制（deb/rpm）。
# 注意：oneclick 的 deb 来自 GitHub Release，并不在 apt 源里，
# 所以 `apt install --reinstall mita` 必定失败；这里改为脚本自行重下重装。
reinstall_mita_package() {
  [ "${MITA_REINSTALL_TRIED:-0}" -eq 1 ] && return 1
  MITA_REINSTALL_TRIED=1
  command -v curl >/dev/null 2>&1 || return 1
  local pm arch ver url tmp
  pm="$(detect_pkg_manager 2>/dev/null || true)"
  case "$pm" in
    deb|rpm) ;;
    *) return 1 ;;
  esac
  arch="$(detect_arch 2>/dev/null || true)"
  [ -n "$arch" ] || return 1
  ver="$(installed_version 2>/dev/null || true)"
  if [ -z "$ver" ]; then
    load_install_state 2>/dev/null || true
    ver="$(target_mieru_version 2>/dev/null || true)"
  fi
  [ -n "$ver" ] || return 1
  warn "$(t "mita 二进制缺失，正在自动重新下载并安装 v${ver}（apt 源中没有该包）..." \
    "mita binary missing; auto re-downloading and installing v${ver} (not in apt repo)...")"
  url="$(package_url "$ver" "$pm" "$arch" 2>/dev/null || true)"
  [ -n "$url" ] || return 1
  tmp="$(mktemp_file)"
  # 子 shell 包裹：download/install 内部的 die→exit 只会终止子 shell，不会杀掉主流程
  if ( download_package "$url" "$tmp" && install_package "$tmp" "$pm" ); then
    rm -f "$tmp"
    hash -r 2>/dev/null || true
    return 0
  fi
  rm -f "$tmp"
  return 1
}

# Debian/Ubuntu 专用自愈：SSH 断开会让 dpkg 停在半装状态，
# 先 dpkg --configure -a 收尾，再恢复软链或重下重装。
recover_deb_mita() {
  command -v dpkg >/dev/null 2>&1 || return 1
  # dpkg --configure -a 幂等：无中断时为空操作，有中断时完成收尾
  configure_pending_deb_packages 2>/dev/null || true
  local deb_bin
  deb_bin="$(dpkg -L mita 2>/dev/null | grep '/bin/mita$' | head -n1)"
  if [ -n "$deb_bin" ] && [ -x "$deb_bin" ] && [ ! -e /usr/bin/mita ]; then
    run ln -sf "$deb_bin" /usr/bin/mita 2>/dev/null || true
  fi
  is_mita_elf_binary /usr/bin/mita && return 0
  reinstall_mita_package
}

repair_mita_binary_paths() {
  STAGE="修复 mita 二进制路径"
  local is_deb=0
  if command -v dpkg >/dev/null 2>&1; then
    is_deb=1
  fi
  if [ "$is_deb" -eq 1 ]; then
    local deb_bin
    deb_bin="$(dpkg -L mita 2>/dev/null | grep '/bin/mita$' | head -n1)"
    if [ -n "$deb_bin" ] && [ -x "$deb_bin" ] && [ ! -e /usr/bin/mita ]; then
      run ln -sf "$deb_bin" /usr/bin/mita 2>/dev/null || true
    fi
  fi
  if ! is_mita_elf_binary "$(mita_real_bin 2>/dev/null || true)"; then
    if [ "$is_deb" -eq 1 ]; then
      recover_deb_mita || warn "$(t 'mita 二进制自动修复未成功，请重新运行脚本并选择「升级」重新安装' \
        'auto-repair failed; re-run the script and choose Upgrade to reinstall')"
    else
      warn "$(t 'mita 二进制不可用，请重新运行脚本并选择「升级」重新安装' \
        'mita binary unavailable; re-run the script and choose Upgrade to reinstall')"
    fi
  fi
  install_mita_wrapper_force
  hash -r 2>/dev/null || true
}

migrate_mita_binary_layout() {
  STAGE="迁移 mita 二进制布局"
  if [ -f "$MITA_REAL_BIN" ] && ! is_mita_elf_binary "$MITA_REAL_BIN"; then
    run rm -f "$MITA_REAL_BIN"
  fi
  if [ -f "$MITA_BIN" ] && [ ! -f "$MITA_REAL_BIN" ] && is_mita_elf_binary "$MITA_BIN"; then
    run mv "$MITA_BIN" "$MITA_REAL_BIN"
    if [ -L /usr/bin/mita ] && [ "$(readlink -f /usr/bin/mita 2>/dev/null || true)" = "$(readlink -f "$MITA_REAL_BIN" 2>/dev/null || true)" ]; then
      run rm -f /usr/bin/mita
    fi
    run ln -sf "$MITA_REAL_BIN" /usr/bin/mita-real 2>/dev/null || true
    if [ -f "$OPENRC_SVC" ]; then
      install_mita_openrc
    elif [ -f "$SYSTEMD_SVC" ]; then
      install_mita_systemd
    fi
  fi
  install_mita_wrapper_force
}

install_mita_shortcuts() {
  STAGE="安装快捷命令"
  cat >"$MITA_MENU_PATH" <<'EOF'
#!/usr/bin/env bash
# mieru-OneClick 管理快捷入口（子命令不区分大小写）
IM="/usr/local/bin/install-mita"
if [ ! -x "$IM" ]; then
  echo "[错误] 未找到 install-mita，请先完成安装" >&2
  exit 1
fi
if [ $# -eq 0 ]; then
  exec "$IM"
fi
cmd="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
case "$cmd" in
  install|upgrade|uninstall|status|reconfigure|client-config|show|mtu|mtu-config|set-mtu|profile|profile-config|perf|menu|start|stop|restart|配置|节点|\
  users|user-list|user-add|user-del|user-delete|user-show|user-manage|user-set-endpoint|\
  user-set-quota|user-set-expire|user-enable|user-disable|user-scan|user-quota-reset|\
  user-set-rate|user-set-bandwidth|rate-status|rate-restore|tc-status|tc-restore|\
  user-usage|usage|user-export-clients|user-backup|user-restore|user-export|user-import|\
  doctor|verify|help)
    set -- "$cmd" "${@:2}"
    ;;
esac
exec "$IM" "$@"
EOF
  run chmod 0755 "$MITA_MENU_PATH"
  # /usr/local/bin/mita 包装器已完整处理菜单及大小写；profile 函数既重复，
  # 又会在卸载后残留于当前父 shell，故升级时一并移除旧实现。
  run rm -f "$MITA_PROFILE_D"
}

remove_mita_shortcuts() {
  run rm -f "$MITA_MENU_PATH" "$MITA_PROFILE_D"
}

remove_self_script() {
  remove_mita_shortcuts
  if [ -f "$INSTALL_SCRIPT_PATH" ]; then
    run rm -f "$INSTALL_SCRIPT_PATH"
    t "已删除管理脚本 ${INSTALL_SCRIPT_PATH}" "Removed manager script ${INSTALL_SCRIPT_PATH}"
  fi
  if [ -f "$MITA_STATE" ]; then
    run rm -f "$MITA_STATE"
  fi
}

service_manager() {
  if [ -d /run/systemd/system ] && command -v systemctl >/dev/null 2>&1; then
    echo systemd
  elif command -v rc-service >/dev/null 2>&1; then
    echo openrc
  else
    echo none
  fi
}

mita_restart_hint() {
  case "$(service_manager)" in
    systemd) printf '%s' 'systemctl restart mita' ;;
    openrc) printf '%s' 'rc-service mita zap && rc-service mita start' ;;
    *) printf '%s' "$(mita_bin) run &" ;;
  esac
}

mita_log_hint() {
  case "$(service_manager)" in
    systemd) printf '%s' 'journalctl -e -u mita --no-pager' ;;
    openrc) printf '%s' 'tail -n 30 /var/log/mita.err /var/log/mita.log' ;;
    *) printf '%s' 'tail -n 30 /var/log/mita.err /var/log/mita.log' ;;
  esac
}

openrc_mita_status_line() {
  rc-service mita status 2>/dev/null || true
}

openrc_mita_is_crashed() {
  openrc_mita_status_line | grep -qi crashed
}

openrc_mita_is_started() {
  openrc_mita_status_line | grep -qE 'started|running'
}

openrc_mita_recover() {
  if openrc_mita_is_crashed || ! openrc_mita_is_started; then
    run rc-service mita zap 2>/dev/null || true
  fi
  run rc-service mita start 2>/dev/null || run rc-service mita restart 2>/dev/null || true
  sleep 2
}

arch_tar_suffix() {
  local arch="$1"
  case "$arch" in
    amd64) echo linux_amd64 ;;
    arm64) echo linux_arm64 ;;
    *) die "$(t 'Alpine 不支持该架构' 'Unsupported arch for Alpine tarball')" ;;
  esac
}

detect_arch() {
  STAGE="检测 CPU 架构"
  local m
  m="$(uname -m)"
  case "$m" in
    x86_64|amd64) echo amd64 ;;
    aarch64|arm64) echo arm64 ;;
    *) die "$(t "不支持的架构：${m}（仅 amd64/arm64）" "Unsupported arch: ${m} (amd64/arm64 only)")" ;;
  esac
}

query_latest_version() {
  STAGE="查询最新版本"
  require_cmd curl
  local body="" tag="" effective=""
  body="$(curl -fsSL --connect-timeout 15 --max-time 30 "$GITHUB_API" 2>/dev/null || true)"
  tag="$(printf '%s' "$body" | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
  if [ -z "$tag" ]; then
    effective="$(curl -fsSL --connect-timeout 15 --max-time 30 -o /dev/null \
      -w '%{url_effective}' "https://github.com/${UPSTREAM_REPO}/releases/latest" 2>/dev/null || true)"
    tag="${effective##*/}"
  fi
  tag="${tag#v}"
  [[ "$tag" =~ ^[0-9]+([.][0-9]+){2}([.-][0-9A-Za-z.]+)?$ ]] \
    || die "$(t '无法取得合法的最新版本号' 'Failed to obtain a valid latest release version')"
  printf '%s' "$tag"
}

normalize_mieru_channel() {
  case "$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')" in
    stable) printf 'stable' ;;
    latest) printf 'latest' ;;
    pinned|version|custom) printf 'pinned' ;;
    *) return 1 ;;
  esac
}

valid_mieru_version() {
  [[ "${1:-}" =~ ^[0-9]+([.][0-9]+){2}([.-][0-9A-Za-z.]+)?$ ]]
}

target_mieru_version() {
  MIERU_CHANNEL="$(normalize_mieru_channel "${MIERU_CHANNEL:-stable}")" || \
    die "$(t '非法 Mieru 通道（stable/latest）' 'Invalid Mieru channel (stable/latest)')"
  case "$MIERU_CHANNEL" in
    stable) printf '%s' "$TESTED_MIERU_VERSION" ;;
    latest) query_latest_version ;;
    pinned)
      valid_mieru_version "${MIERU_VERSION:-}" || \
        die "$(t 'pinned 通道需要合法的 --mieru-version' \
          'The pinned channel requires a valid --mieru-version')"
      printf '%s' "$MIERU_VERSION"
      ;;
  esac
}

mieru_channel_label() {
  case "$(normalize_mieru_channel "${MIERU_CHANNEL:-stable}" 2>/dev/null || printf stable)" in
    stable) t 'stable（项目测试版）' 'stable (project-tested)' ;;
    latest) t 'latest（上游最新版）' 'latest (upstream newest)' ;;
    pinned) t "pinned (${MIERU_VERSION:-unknown})" "pinned (${MIERU_VERSION:-unknown})" ;;
  esac
}

mita_installed() {
  # ^i[iUFH]: 已安装(ii) 或被中断的半装状态(iU/iF/iH)，后者也需进入修复流程
  if command -v dpkg >/dev/null 2>&1 && dpkg -l mita 2>/dev/null | grep -qE '^i[iUFH]'; then
    return 0
  fi
  if command -v rpm >/dev/null 2>&1 && rpm -q mita >/dev/null 2>&1; then
    return 0
  fi
  [ -x "$MITA_REAL_BIN" ] && [ -f "$MITA_MARKER" ] && return 0
  [ -x "$MITA_BIN" ] && [ -f "$MITA_MARKER" ] && return 0
  command -v mita >/dev/null 2>&1
}

is_mita_wrapper() {
  [ -f "$1" ] || return 1
  head -c 320 "$1" 2>/dev/null | grep -q 'mieru-OneClick mita wrapper'
}

is_mita_elf_binary() {
  [ -f "$1" ] || return 1
  [ "$(head -c 4 "$1" 2>/dev/null || true)" = $'\x7fELF' ]
}

mita_real_bin() {
  if [ -x "$MITA_REAL_BIN" ] && is_mita_elf_binary "$MITA_REAL_BIN"; then
    printf '%s' "$MITA_REAL_BIN"
  elif [ -x /usr/bin/mita ] && is_mita_elf_binary /usr/bin/mita; then
    printf '%s' /usr/bin/mita
  elif [ -x "$MITA_BIN" ] && is_mita_elf_binary "$MITA_BIN"; then
    printf '%s' "$MITA_BIN"
  elif command -v mita-real >/dev/null 2>&1 && is_mita_elf_binary "$(command -v mita-real)"; then
    command -v mita-real
  else
    printf '%s' "$MITA_REAL_BIN"
  fi
}

mita_bin() {
  mita_real_bin
}

installed_version() {
  if mita_installed; then
    "$(mita_bin)" version 2>/dev/null | sed -n '1p' | tr -d 'v'
  fi
}

version_is_current() {
  local current="$1"
  local available="$2"
  [ -n "$current" ] || return 1
  [ "$(printf '%s\n%s' "$current" "$available" | sort -V | tail -n1)" = "$current" ]
}

package_url() {
  local ver="$1"
  local pm="$2"
  local arch="$3"
  case "${pm}:${arch}" in
    deb:amd64) echo "${GITHUB_DL}/v${ver}/mita_${ver}_amd64.deb" ;;
    deb:arm64) echo "${GITHUB_DL}/v${ver}/mita_${ver}_arm64.deb" ;;
    rpm:amd64) echo "${GITHUB_DL}/v${ver}/mita-${ver}-1.x86_64.rpm" ;;
    rpm:arm64) echo "${GITHUB_DL}/v${ver}/mita-${ver}-1.aarch64.rpm" ;;
    alpine:amd64|alpine:arm64)
      echo "${GITHUB_DL}/v${ver}/mita_${ver}_$(arch_tar_suffix "$arch").tar.gz"
      ;;
    *) die "$(t '无法构造下载链接' 'Cannot build download URL')" ;;
  esac
}

download_package() {
  local url="$1"
  local dest="$2"
  STAGE="下载安装包"
  info "$(t "下载 ${url}" "Downloading ${url}")"
  run curl -fL --connect-timeout 30 --retry 3 --retry-delay 2 -o "$dest" "$url"
  [ -s "$dest" ] || die "$(t '下载文件为空' 'Downloaded file is empty')"
  verify_package_sha256 "$dest" "${url}.sha256.txt"
}

verify_package_sha256() {
  local file="$1"
  local sha_url="$2"
  [ "$DRY_RUN" -eq 1 ] && return 0
  STAGE="校验安装包 SHA256"
  local sha_file expected actual
  sha_file="$(mktemp_file .txt)"
  if ! curl -fsSL --connect-timeout 15 --max-time 30 "$sha_url" -o "$sha_file" 2>/dev/null; then
    rm -f "$sha_file"
    die "$(t "无法下载校验文件，已中止安装: ${sha_url}" \
      "Checksum file unavailable; installation aborted: ${sha_url}")"
    return 1
  fi
  expected="$(awk '{print $1}' "$sha_file" | head -n1)"
  [[ "$expected" =~ ^[0-9A-Fa-f]{64}$ ]] || {
    rm -f "$sha_file"
    die "$(t '校验文件格式无效' 'Invalid checksum file')"
    return 1
  }
  expected="$(printf '%s' "$expected" | tr '[:upper:]' '[:lower:]')"
  if command -v sha256sum >/dev/null 2>&1; then
    actual="$(sha256sum "$file" | awk '{print $1}')"
  elif command -v shasum >/dev/null 2>&1; then
    actual="$(shasum -a 256 "$file" | awk '{print $1}')"
  else
    rm -f "$sha_file"
    die "$(t '未找到 sha256sum/shasum，无法安全安装' \
      'sha256sum/shasum not found; cannot install safely')"
    return 1
  fi
  rm -f "$sha_file"
  [ "$expected" = "$actual" ] || die "$(t '安装包 SHA256 校验失败' 'Package SHA256 verification failed')"
  t '安装包 SHA256 校验通过' 'Package SHA256 verified'
}

install_alpine_deps() {
  STAGE="安装 Alpine 依赖"
  run apk add --no-cache bash curl tar ca-certificates iptables iproute2 python3 util-linux
  if [ "$(service_manager)" = openrc ]; then
    run apk add --no-cache openrc 2>/dev/null || true
  fi
}

ensure_management_dependencies() {
  local pm="${1:-$(detect_pkg_manager)}"
  STAGE="安装管理依赖"
  case "$pm" in
    deb)
      command -v python3 >/dev/null 2>&1 && command -v tc >/dev/null 2>&1 \
        && command -v unshare >/dev/null 2>&1 && command -v setpriv >/dev/null 2>&1 && return 0
      run apt-get update
      run apt-get install -y python3 iproute2 util-linux
      ;;
    rpm)
      command -v python3 >/dev/null 2>&1 && command -v tc >/dev/null 2>&1 \
        && command -v unshare >/dev/null 2>&1 && command -v setpriv >/dev/null 2>&1 && return 0
      if command -v dnf >/dev/null 2>&1; then
        run dnf install -y python3 iproute util-linux
      else
        run yum install -y python3 iproute util-linux
      fi
      ;;
    alpine) install_alpine_deps ;;
  esac
}

ensure_mita_account() {
  STAGE="创建 mita 用户"
  if ! _has_group mita; then
    if command -v groupadd >/dev/null 2>&1; then
      run groupadd --system mita
    else
      run addgroup -S mita
    fi
  fi
  if ! _has_user mita; then
    if command -v useradd >/dev/null 2>&1; then
      run useradd --system -g mita -s /sbin/nologin -d /var/lib/mita mita
    else
      run adduser -S -G mita -s /sbin/nologin -h /var/lib/mita mita
    fi
  fi
  run mkdir -p /etc/mita /var/lib/mita /var/run/mita /run/mita
  run chown -R mita:mita /etc/mita /var/lib/mita /var/run/mita /run/mita 2>/dev/null || true
  run chmod 0750 /etc/mita
  run chmod 0755 /var/lib/mita /var/run/mita /run/mita
}

install_mita_systemd() {
  STAGE="安装 systemd 服务"
  local bin
  bin="$(mita_real_bin)"
  cat >"$SYSTEMD_SVC" <<EOF
[Unit]
Description=Mieru proxy server
After=network-online.target
Wants=network-online.target

[Service]
Type=exec
User=mita
Group=mita
ExecStart=${bin} run
Restart=on-failure
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF
  run systemctl daemon-reload
}

install_mita_openrc() {
  STAGE="安装 OpenRC 服务"
  local bin
  bin="$(mita_real_bin)"
  cat >"$OPENRC_SVC" <<EOF
#!/sbin/openrc-run

name="mita"
description="Mieru proxy server"
command="${bin}"
command_args="run"
command_user="mita"
command_background="yes"
pidfile="/run/\${RC_SVCNAME}.pid"
output_log="/var/log/mita.log"
error_log="/var/log/mita.err"
directory="/var/lib/mita"
respawn
respawn_delay 5
respawn_max 0

depend() {
    need net localmount
    after firewall
}

start_pre() {
    checkpath --directory --owner mita:mita --mode 0750 /etc/mita
    checkpath --directory --owner mita:mita --mode 0755 /var/lib/mita /var/run/mita /run/mita
    checkpath --file --owner mita:mita --mode 0644 /var/log/mita.log /var/log/mita.err
}
EOF
  run chmod 0755 "$OPENRC_SVC"
}

install_mita_service() {
  case "$(service_manager)" in
    systemd) install_mita_systemd ;;
    openrc) install_mita_openrc ;;
    *)
      warn "$(t '未检测到 systemd/OpenRC，将仅安装二进制' 'No systemd/OpenRC; binary only')"
      ;;
  esac
}

package_service_guard_begin() {
  local guard_dir
  PACKAGE_SERVICE_GUARD_DIR=""
  PACKAGE_SERVICE_GUARD_REAL_SYSTEMCTL=""
  PACKAGE_SERVICE_GUARD_WAS_ACTIVE=0
  [ "$(service_manager)" = systemd ] || return 0
  PACKAGE_SERVICE_GUARD_REAL_SYSTEMCTL="$(type -P systemctl 2>/dev/null || true)"
  if [ -z "$PACKAGE_SERVICE_GUARD_REAL_SYSTEMCTL" ] \
     || [ ! -x "$PACKAGE_SERVICE_GUARD_REAL_SYSTEMCTL" ]; then
    warn "$(t '无法定位真实 systemctl，已取消软件包安装' \
      'Could not locate the real systemctl; package installation was cancelled')"
    return 1
  fi
  if "$PACKAGE_SERVICE_GUARD_REAL_SYSTEMCTL" is-active --quiet mita.service 2>/dev/null; then
    PACKAGE_SERVICE_GUARD_WAS_ACTIVE=1
  fi
  guard_dir="$(mktemp_dir)" || return 1
  if ! cat >"${guard_dir}/systemctl" <<'EOF'
#!/bin/sh
real="${MITA_REAL_SYSTEMCTL:?}"
action=""
target=0
for arg in "$@"; do
    case "$arg" in
        -*) continue ;;
    esac
    if [ -z "$action" ]; then
        action="$arg"
        continue
    fi
    case "$arg" in
        mita|mita.service) target=1 ;;
    esac
done
if [ "$target" -eq 1 ]; then
    case "$action" in
        enable|reenable|preset|start|restart|try-restart|reload|reload-or-restart|reload-or-try-restart)
            exit 0
            ;;
    esac
fi
exec "$real" "$@"
EOF
  then
    rm -rf -- "$guard_dir"
    return 1
  fi
  if ! chmod 0700 "${guard_dir}/systemctl"; then
    rm -rf -- "$guard_dir"
    return 1
  fi
  PACKAGE_SERVICE_GUARD_DIR="$guard_dir"
}

package_service_guard_run() {
  if [ -n "${PACKAGE_SERVICE_GUARD_DIR:-}" ]; then
    (
      export PATH="${PACKAGE_SERVICE_GUARD_DIR}:${PATH}"
      export MITA_REAL_SYSTEMCTL="$PACKAGE_SERVICE_GUARD_REAL_SYSTEMCTL"
      run "$@"
    )
  else
    run "$@"
  fi
}

package_service_guard_end() {
  local guard_dir="${PACKAGE_SERVICE_GUARD_DIR:-}" restore_rc=0
  if [ -n "$guard_dir" ]; then
    case "$guard_dir" in
      /tmp/mita.*|/tmp/mita_*) rm -rf -- "$guard_dir" || restore_rc=1 ;;
      *)
        warn "$(t '拒绝清理异常的软件包服务保护目录' \
          'Refusing to remove an unexpected package-service guard directory')"
        restore_rc=1
        ;;
    esac
  fi
  if [ "${PACKAGE_SERVICE_GUARD_WAS_ACTIVE:-0}" -eq 1 ] \
     && ! run "$PACKAGE_SERVICE_GUARD_REAL_SYSTEMCTL" start mita.service >/dev/null 2>&1; then
    warn "$(t 'mita.service 安装前正在运行，但软件包安装后无法恢复启动' \
      'mita.service was active before installation but could not be restarted afterward')"
    restore_rc=1
  fi
  PACKAGE_SERVICE_GUARD_DIR=""
  PACKAGE_SERVICE_GUARD_REAL_SYSTEMCTL=""
  PACKAGE_SERVICE_GUARD_WAS_ACTIVE=0
  return "$restore_rc"
}

configure_pending_deb_packages() {
  local configure_rc=0 guard_rc=0
  package_service_guard_begin || return 1
  package_service_guard_run dpkg --configure -a || configure_rc=1
  package_service_guard_end || guard_rc=1
  [ "$configure_rc" -eq 0 ] && [ "$guard_rc" -eq 0 ]
}

extract_mita_tarball() {
  local tarball="$1"
  STAGE="解压 mita 二进制"
  local tmpdir bin
  tmpdir="$(mktemp_dir)"
  run tar -xzf "$tarball" -C "$tmpdir"
  bin="$(find "$tmpdir" -type f -name mita | head -n1)"
  [ -n "$bin" ] || die "$(t '压缩包中未找到 mita 二进制' 'mita binary not found in archive')"
  run install -m 0755 "$bin" "$MITA_REAL_BIN"
  run rm -f /usr/bin/mita /usr/bin/mita-real
  run ln -sf "$MITA_REAL_BIN" /usr/bin/mita-real 2>/dev/null || true
  install_mita_wrapper
  rm -rf "$tmpdir"
  run touch "$MITA_MARKER"
}

install_package() {
  local path="$1"
  local pm="$2"
  local install_rc=0 guard_rc=0
  STAGE="安装软件包"
  record_preexisting_mita_resources "$pm"
  if ! package_service_guard_begin; then
    die "$(t '无法安全准备 mita 软件包安装' \
      'Could not safely prepare the mita package installation')" || return 1
  fi
  case "$pm" in
    deb)
      if ! package_service_guard_run dpkg -i "$path" \
         && ! package_service_guard_run apt-get install -f -y; then
        install_rc=1
      fi
      ;;
    rpm)
      package_service_guard_run rpm -Uvh --force "$path" || install_rc=1
      ;;
    alpine)
      if ! install_alpine_deps \
         || ! ensure_mita_account \
         || ! extract_mita_tarball "$path" \
         || ! install_mita_service; then
        install_rc=1
      fi
      ;;
    *) install_rc=1 ;;
  esac
  package_service_guard_end || guard_rc=1
  if [ "$install_rc" -ne 0 ] || [ "$guard_rc" -ne 0 ]; then
    die "$(t 'mita 软件包安装或原服务状态恢复失败' \
      'The mita package installation or previous service-state restoration failed')" || return 1
  fi
  case "$pm" in
    deb|rpm) mark_oneclick_install ;;
  esac
}

# ---------- NoBrand isolated Xray-core runtime / Hysteria2 service ----------

nobrand_prepare_common() {
  local pm
  require_root
  require_linux
  pm="$(detect_pkg_manager)"
  STAGE="安装 NoBrand 公共依赖"
  case "$pm" in
    deb)
      if ! command -v curl >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1 \
         || ! command -v unzip >/dev/null 2>&1 || ! command -v openssl >/dev/null 2>&1 \
         || ! command -v python3 >/dev/null 2>&1; then
        run apt-get update
        run apt-get install -y curl ca-certificates jq unzip openssl python3 iproute2 util-linux tar
      fi
      ;;
    rpm)
      if command -v dnf >/dev/null 2>&1; then
        run dnf install -y curl ca-certificates jq unzip openssl python3 iproute util-linux tar
      else
        run yum install -y curl ca-certificates jq unzip openssl python3 iproute util-linux tar
      fi
      ;;
    alpine)
      run apk add --no-cache bash curl ca-certificates jq unzip openssl python3 iproute2 util-linux tar libstdc++
      ;;
  esac
  nb_init_state_layout
}

nobrand_xray_arch_asset() {
  case "${NOBRAND_TEST_ARCH:-$(uname -m)}" in
    x86_64|amd64) printf 'Xray-linux-64.zip' ;;
    aarch64|arm64) printf 'Xray-linux-arm64-v8a.zip' ;;
    *) return 1 ;;
  esac
}

nobrand_xray_version() {
  [ -x "$NOBRAND_XRAY_BIN" ] || return 1
  "$NOBRAND_XRAY_BIN" version 2>/dev/null \
    | sed -nE 's/^Xray[[:space:]]+([^[:space:]]+).*/\1/p' | head -n1
}

nobrand_xray_release_info() {
  local asset metadata
  asset="$(nobrand_xray_arch_asset)" || {
    warn "$(t 'NoBrand HY2 的 Xray runtime 仅测试 amd64/arm64' \
      'NoBrand HY2 Xray runtime is tested only on amd64/arm64')"
    return 1
  }
  metadata="$(mktemp_file .json)" || return 1
  if ! curl -fsSL --connect-timeout 15 --max-time 90 \
      --retry 3 --retry-delay 2 --retry-all-errors \
      -H 'Accept: application/vnd.github+json' \
      -H 'User-Agent: NoBrand-OneClick' "$NOBRAND_XRAY_RELEASE_API" -o "$metadata"; then
    rm -f "$metadata"
    return 1
  fi
  jq -r --arg asset "$asset" '
    .tag_name as $version |
    first(.assets[]? | select(.name == $asset)) as $matched |
    select($matched != null) |
    [$version, $matched.browser_download_url, ($matched.digest // "")] | @tsv
  ' "$metadata"
  local rc=$?
  rm -f "$metadata"
  return "$rc"
}

nobrand_sha256_file() {
  local file="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" | awk '{print tolower($1)}'
  else
    openssl dgst -sha256 "$file" 2>/dev/null | awk '{print tolower($NF)}'
  fi
}

nobrand_verify_release_digest() {
  local file="$1" digest="${2:-}" expected actual
  [ -n "$digest" ] || {
    info "$(t '上游 release API 未提供资产 hash；已继续执行 archive/ELF/runtime 校验' \
      'Upstream release API has no asset hash; archive/ELF/runtime validation will still run')"
    return 0
  }
  case "$digest" in
    sha256:*) expected="${digest#sha256:}" ;;
    *) warn "不支持的上游 digest: $digest"; return 1 ;;
  esac
  [[ "$expected" =~ ^[0-9A-Fa-f]{64}$ ]] || return 1
  actual="$(nobrand_sha256_file "$file")" || return 1
  [ "$(printf '%s' "$actual" | tr '[:upper:]' '[:lower:]')" = \
    "$(printf '%s' "$expected" | tr '[:upper:]' '[:lower:]')" ]
}

nobrand_download_xray_candidate() {
  local output="$1" info_line version url digest archive_dir candidate
  info_line="$(nobrand_xray_release_info)" || return 1
  IFS=$'\t' read -r version url digest <<<"$info_line"
  [[ "$url" = https://github.com/XTLS/Xray-core/releases/download/* ]] || {
    warn "拒绝非 XTLS 官方 HTTPS 资产: $url"
    return 1
  }
  archive_dir="$(mktemp_dir)" || return 1
  if ! curl -fL --connect-timeout 15 --max-time 180 \
      --retry 3 --retry-delay 2 --retry-all-errors \
      -H 'User-Agent: NoBrand-OneClick' "$url" -o "$archive_dir/xray.zip" \
     || ! nobrand_verify_release_digest "$archive_dir/xray.zip" "$digest" \
     || ! unzip -t "$archive_dir/xray.zip" >/dev/null \
     || ! unzip -qo "$archive_dir/xray.zip" -d "$archive_dir/unpacked"; then
    rm -rf -- "$archive_dir"
    return 1
  fi
  candidate="$archive_dir/unpacked/xray"
  [ -f "$candidate" ] || candidate="$(find "$archive_dir/unpacked" -type f -name xray | head -n1)"
  [ -n "$candidate" ] && [ -f "$candidate" ] || { rm -rf -- "$archive_dir"; return 1; }
  chmod 0755 "$candidate" || { rm -rf -- "$archive_dir"; return 1; }
  "$candidate" version >/dev/null 2>&1 || { rm -rf -- "$archive_dir"; return 1; }
  install -m 0755 "$candidate" "$output" || { rm -rf -- "$archive_dir"; return 1; }
  info "NoBrand isolated Xray-core asset resolved: ${version}"
  rm -rf -- "$archive_dir"
}

nobrand_install_xray_runtime() {
  local force="${1:-0}" candidate backup="" had_old=0
  if [ -x "$NOBRAND_XRAY_BIN" ] && [ "$force" -ne 1 ]; then
    return 0
  fi
  candidate="$(mktemp_file .xray)" || return 1
  if ! nobrand_download_xray_candidate "$candidate"; then
    rm -f "$candidate"
    warn "$(t 'NoBrand 独立 Xray-core 下载或校验失败' \
      'NoBrand isolated Xray-core download or validation failed')"
    return 1
  fi
  mkdir -p "$(dirname "$NOBRAND_XRAY_BIN")" || { rm -f "$candidate"; return 1; }
  if [ -e "$NOBRAND_XRAY_BIN" ]; then
    backup="$(mktemp "${NOBRAND_XRAY_BIN}.rollback.XXXXXX")" || { rm -f "$candidate"; return 1; }
    rm -f "$backup"
    mv "$NOBRAND_XRAY_BIN" "$backup" || { rm -f "$candidate"; return 1; }
    had_old=1
  fi
  if ! install -m 0755 "$candidate" "${NOBRAND_XRAY_BIN}.new" \
     || ! mv -f "${NOBRAND_XRAY_BIN}.new" "$NOBRAND_XRAY_BIN" \
     || ! nobrand_xray_version >/dev/null; then
    rm -f "$candidate" "${NOBRAND_XRAY_BIN}.new" "$NOBRAND_XRAY_BIN"
    [ "$had_old" -eq 0 ] || mv "$backup" "$NOBRAND_XRAY_BIN" 2>/dev/null || true
    return 1
  fi
  rm -f "$candidate"
  if ! nobrand_xray_validate_managed_configs "$NOBRAND_XRAY_BIN"; then
    rm -f "$NOBRAND_XRAY_BIN"
    [ "$had_old" -eq 0 ] || mv "$backup" "$NOBRAND_XRAY_BIN" 2>/dev/null || true
    return 1
  fi
  rm -f "$backup"
}

nobrand_xray_test_config() {
  local config="$1" binary="${2:-$NOBRAND_XRAY_BIN}" log
  [ -x "$binary" ] && jq empty "$config" >/dev/null 2>&1 || return 1
  log="$(mktemp_file .log)" || return 1
  if ! "$binary" run -test -c "$config" >"$log" 2>&1; then
    warn "$(t 'NoBrand Xray 配置校验失败（已脱敏）:' \
      'NoBrand Xray config validation failed (redacted):')"
    sed -E 's/(auth|password)(["=: ]+)[^," ]+/\1\2***REDACTED***/Ig' "$log" >&2 || true
    rm -f "$log"
    return 1
  fi
  rm -f "$log"
}

nobrand_xray_validate_managed_configs() {
  local binary="${1:-$NOBRAND_XRAY_BIN}" config
  for config in "$NOBRAND_HY2_CONFIG_FILE" "$NOBRAND_VLESS_CONFIG_FILE"; do
    [ -f "$config" ] || continue
    nobrand_xray_test_config "$config" "$binary" || return 1
  done
}

nobrand_restore_xray_upgrade_snapshot() {
  local snapshot="$1" had_runtime="$2" hy2_had_state="$3" vless_had_state="$4"
  local hy2_was_active="$5" vless_was_active="$6"
  if [ "$had_runtime" -eq 1 ]; then
    install -m 0755 "$snapshot/xray" "$NOBRAND_XRAY_BIN" || return 1
  else
    rm -f "$NOBRAND_XRAY_BIN"
  fi
  if [ "$hy2_had_state" -eq 1 ]; then
    cp -a "$snapshot/hy2-state" "$NOBRAND_HY2_STATE_FILE" || return 1
  fi
  if [ "$vless_had_state" -eq 1 ]; then
    cp -a "$snapshot/vless-state" "$NOBRAND_VLESS_STATE_FILE" || return 1
  fi
  if [ "$had_runtime" -eq 1 ]; then
    [ "$hy2_was_active" -eq 0 ] \
      || nobrand_hy2_service_action restart >/dev/null 2>&1 || true
    [ "$vless_was_active" -eq 0 ] \
      || nobrand_vless_sudoku_service_action restart >/dev/null 2>&1 || true
  else
    [ "$hy2_was_active" -eq 0 ] \
      || nobrand_hy2_service_action stop >/dev/null 2>&1 || true
    [ "$vless_was_active" -eq 0 ] \
      || nobrand_vless_sudoku_service_action stop >/dev/null 2>&1 || true
  fi
}

nobrand_upgrade_xray_runtime() {
  local snapshot had_runtime=0 hy2_had_state=0 vless_had_state=0
  local hy2_was_active=0 vless_was_active=0 hy2_port="" vless_port=""
  local failed=0
  nobrand_prepare_common
  admin_lock_acquire || return 1
  snapshot="$(mktemp_dir)" || { admin_lock_release; return 1; }
  if [ -e "$NOBRAND_XRAY_BIN" ]; then
    cp -a "$NOBRAND_XRAY_BIN" "$snapshot/xray" \
      || { rm -rf -- "$snapshot"; admin_lock_release; return 1; }
    had_runtime=1
  fi
  if hysteria2_state_exists; then
    cp -a "$NOBRAND_HY2_STATE_FILE" "$snapshot/hy2-state" \
      || { rm -rf -- "$snapshot"; admin_lock_release; return 1; }
    hy2_had_state=1
    hy2_port="$(hysteria2_state_field listen_port)"
  fi
  if vless_sudoku_state_exists; then
    cp -a "$NOBRAND_VLESS_STATE_FILE" "$snapshot/vless-state" \
      || { rm -rf -- "$snapshot"; admin_lock_release; return 1; }
    vless_had_state=1
    vless_port="$(vless_sudoku_state_field listen_port)"
  fi
  nobrand_hy2_service_active && hy2_was_active=1
  nobrand_vless_sudoku_service_active && vless_was_active=1

  if ! nobrand_install_xray_runtime 1; then
    failed=1
  elif [ "$hy2_was_active" -eq 1 ] \
       && { ! nobrand_hy2_service_action restart \
         || ! nb_wait_for_listener UDP "$hy2_port" 25; }; then
    failed=1
  elif [ "$vless_was_active" -eq 1 ] \
       && { ! nobrand_vless_sudoku_service_action restart \
         || ! nb_wait_for_listener TCP "$vless_port" 25; }; then
    failed=1
  elif ! hysteria2_refresh_runtime_metadata \
       || ! vless_sudoku_refresh_runtime_metadata; then
    failed=1
  fi
  if [ "$failed" -eq 1 ]; then
    nobrand_restore_xray_upgrade_snapshot "$snapshot" "$had_runtime" \
      "$hy2_had_state" "$vless_had_state" "$hy2_was_active" "$vless_was_active" \
      || warn '共享 Xray runtime 回滚不完整；请立即运行 nobrand doctor'
    rm -rf -- "$snapshot"
    admin_lock_release
    warn '共享 Xray 升级或双服务验收失败，已恢复升级前 runtime/state'
    return 1
  fi

  rm -rf -- "$snapshot"
  admin_lock_release
  t 'NoBrand 共享 Xray-core 升级完成；活动 HY2/VLESS 服务均已验收' \
    'NoBrand shared Xray-core upgraded; active HY2/VLESS services passed acceptance'
}

nobrand_write_hy2_service() {
  local manager tmp
  manager="$(nb_service_manager)"
  case "$manager" in
    systemd)
      tmp="$(mktemp_file .service)" || return 1
      cat >"$tmp" <<EOF
# Managed by NoBrand-OneClick
[Unit]
Description=NoBrand Hysteria2 (Xray-core)
Documentation=https://github.com/ike-sh/NoBrand-OneClick
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=${NOBRAND_HY2_CONFIG_DIR}
ExecStart=${NOBRAND_XRAY_BIN} run -c ${NOBRAND_HY2_CONFIG_FILE}
Restart=on-failure
RestartSec=5
LimitNOFILE=1048576
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_BIND_SERVICE
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full
ProtectHome=true
ReadWritePaths=${NOBRAND_HY2_CONFIG_DIR} ${NOBRAND_HY2_STATE_DIR}

[Install]
WantedBy=multi-user.target
EOF
      grep -qF "ExecStart=${NOBRAND_XRAY_BIN} run -c ${NOBRAND_HY2_CONFIG_FILE}" "$tmp" \
        || { rm -f "$tmp"; return 1; }
      install -m 0644 "$tmp" "${NOBRAND_HY2_SYSTEMD_SERVICE}.new" \
        && mv -f "${NOBRAND_HY2_SYSTEMD_SERVICE}.new" "$NOBRAND_HY2_SYSTEMD_SERVICE" \
        || { rm -f "$tmp" "${NOBRAND_HY2_SYSTEMD_SERVICE}.new"; return 1; }
      rm -f "$tmp"
      systemctl daemon-reload
      systemctl enable "$NOBRAND_HY2_SERVICE_NAME" >/dev/null 2>&1
      ;;
    openrc)
      tmp="$(mktemp_file .openrc)" || return 1
      cat >"$tmp" <<EOF
#!/sbin/openrc-run
# Managed by NoBrand-OneClick
name="NoBrand Hysteria2"
description="NoBrand Hysteria2 (Xray-core)"
command="${NOBRAND_XRAY_BIN}"
command_args="run -c ${NOBRAND_HY2_CONFIG_FILE}"
command_background=true
pidfile="/run/nobrand-hysteria2.pid"
output_log="/var/log/nobrand-hysteria2.log"
error_log="/var/log/nobrand-hysteria2.err"
depend() { use net; after firewall; }
EOF
      install -m 0755 "$tmp" "${NOBRAND_HY2_OPENRC_SERVICE}.new" \
        && mv -f "${NOBRAND_HY2_OPENRC_SERVICE}.new" "$NOBRAND_HY2_OPENRC_SERVICE" \
        || { rm -f "$tmp" "${NOBRAND_HY2_OPENRC_SERVICE}.new"; return 1; }
      rm -f "$tmp"
      rc-update add "$NOBRAND_HY2_SERVICE_NAME" default >/dev/null 2>&1
      ;;
    *) return 1 ;;
  esac
}

nobrand_hy2_service_action() {
  local action="$1" manager
  manager="$(nb_service_manager)"
  case "$manager" in
    systemd)
      [ "$action" != restart ] || systemctl daemon-reload
      systemctl "$action" "$NOBRAND_HY2_SERVICE_NAME"
      ;;
    openrc) rc-service "$NOBRAND_HY2_SERVICE_NAME" "$action" ;;
    *) return 1 ;;
  esac
}

nobrand_hy2_service_active() {
  nb_service_is_active "$NOBRAND_HY2_SERVICE_NAME" "$NOBRAND_HY2_SERVICE_NAME"
}

nobrand_remove_hy2_service() {
  local manager
  manager="$(nb_service_manager)"
  nobrand_hy2_service_action stop >/dev/null 2>&1 || true
  case "$manager" in
    systemd)
      systemctl disable "$NOBRAND_HY2_SERVICE_NAME" >/dev/null 2>&1 || true
      rm -f "$NOBRAND_HY2_SYSTEMD_SERVICE"
      systemctl daemon-reload 2>/dev/null || true
      ;;
    openrc)
      rc-update del "$NOBRAND_HY2_SERVICE_NAME" default >/dev/null 2>&1 || true
      rm -f "$NOBRAND_HY2_OPENRC_SERVICE"
      ;;
  esac
}

# ---------- Surge official Snell runtime resolver / download / service ----------

snell_arch_asset_name() {
  case "${NOBRAND_TEST_ARCH:-$(uname -m)}" in
    x86_64|amd64) printf 'amd64' ;;
    aarch64|arm64) printf 'aarch64' ;;
    *) return 1 ;;
  esac
}

snell_platform_supported() {
  local major="$1" arch
  case "$major" in 4|5) ;; *) return 1 ;; esac
  arch="$(snell_arch_asset_name)" || return 1
  case "$arch" in amd64|aarch64) return 0 ;; esac
}

# 从 Surge 官方 Markdown 中解析对应 major/arch 的最新 asset。排序支持
# beta -> RC -> GA，避免将 runtime 版本写死在产品源码中。
snell_select_release_from_text() {
  local major="$1" arch="$2" input rc
  case "$major" in 4|5) ;; *) return 1 ;; esac
  input="$(mktemp_file .md)" || return 1
  cat >"$input" || { rm -f "$input"; return 1; }
  python3 - "$major" "$arch" "$input" <<'PY'
import re
import sys

major=int(sys.argv[1])
arch=sys.argv[2]
with open(sys.argv[3], encoding="utf-8") as source:
    text=source.read()
pattern=re.compile(r"https://dl\.nssurge\.com/snell/snell-server-v([^/\s]+)-linux-([A-Za-z0-9_]+)\.zip")

def key(version):
    match=re.fullmatch(r"(\d+(?:\.\d+)*)(.*)", version, re.I)
    if not match:
        return ((0,), 0, 0, version.lower())
    numbers=tuple(int(part) for part in match.group(1).split('.'))
    suffix=match.group(2).lower()
    if not suffix:
        stage, stage_no = 4, 0
    elif suffix.startswith('rc'):
        stage=3
        found=re.search(r"\d+", suffix)
        stage_no=int(found.group()) if found else 1
    elif suffix.startswith('beta') or suffix.startswith('b'):
        stage=2
        found=re.search(r"\d+", suffix)
        stage_no=int(found.group()) if found else 1
    elif suffix.startswith('alpha') or suffix.startswith('a'):
        stage=1
        found=re.search(r"\d+", suffix)
        stage_no=int(found.group()) if found else 1
    else:
        stage, stage_no = 0, 0
    return (numbers, stage, stage_no, suffix)

candidates=[]
for match in pattern.finditer(text):
    version, asset_arch = match.groups()
    if asset_arch != arch:
        continue
    if not re.match(r"^%d(?:\.|$)" % major, version):
        continue
    url="https://dl.nssurge.com/snell/snell-server-v%s-linux-%s.zip" % (version, arch)
    line_start=text.rfind("\n", 0, match.start()) + 1
    line_end=text.find("\n", match.end())
    if line_end < 0:
        line_end=len(text)
    same_line=text[line_start:line_end]
    digest_match=re.search(r"(?i)(?<![0-9a-f])[0-9a-f]{64}(?![0-9a-f])", same_line)
    digest=digest_match.group(0).lower() if digest_match else ""
    candidates.append((key(version), version, url, digest))
if not candidates:
    raise SystemExit(1)
_, version, url, digest=max(candidates)
suffix=re.fullmatch(r"\d+(?:\.\d+)*(.*)", version, re.I).group(1).lower()
if not suffix:
    status="Stable"
elif suffix.startswith("rc"):
    status="RC"
elif suffix.startswith("beta") or suffix.startswith("b"):
    status="Beta"
else:
    status="Experimental"
fields=[version, url, status]
if digest:
    fields.append(digest)
print("\t".join(fields))
PY
  rc=$?
  rm -f "$input"
  return "$rc"
}

snell_resolve_release() {
  local major="$1" arch page
  case "$major" in 4|5) ;; *) return 1 ;; esac
  arch="$(snell_arch_asset_name)" || return 1
  page="$(mktemp_file .md)" || return 1
  if ! curl -fsSL --connect-timeout 15 --max-time 90 \
      --retry 3 --retry-delay 2 --retry-all-errors \
      -H 'User-Agent: NoBrand-OneClick' "$SNELL_RELEASE_PAGE" -o "$page"; then
    rm -f "$page"
    return 1
  fi
  snell_select_release_from_text "$major" "$arch" <"$page"
  local rc=$?
  rm -f "$page"
  return "$rc"
}

snell_runtime_path() {
  case "$1" in 4|5) ;; *) return 1 ;; esac
  printf '%s/snell-v%s' "$NOBRAND_SNELL_RUNTIME_DIR" "$1"
}

snell_runtime_metadata_path() {
  case "$1" in 4|5) ;; *) return 1 ;; esac
  printf '%s/snell-v%s.runtime.json' "$NOBRAND_SNELL_RUNTIME_DIR" "$1"
}

snell_runtime_reported_version() {
  local binary="$1"
  [ -x "$binary" ] || return 1
  "$binary" --version 2>&1 \
    | sed -nE 's/.*snell-server[[:space:]]+v([^[:space:]]+).*/\1/p' | head -n1
}

snell_runtime_release_version() {
  local major="$1" metadata
  metadata="$(snell_runtime_metadata_path "$major")"
  if [ -s "$metadata" ] && jq -e '.release_version|type=="string" and length>0' "$metadata" >/dev/null 2>&1; then
    jq -r .release_version "$metadata"
  else
    snell_runtime_reported_version "$(snell_runtime_path "$major")"
  fi
}

snell_runtime_release_status() {
  local major="$1" metadata
  metadata="$(snell_runtime_metadata_path "$major")"
  if [ -s "$metadata" ] && jq -e '.status|type=="string" and length>0' "$metadata" >/dev/null 2>&1; then
    jq -r .status "$metadata"
  else
    printf Stable
  fi
}

snell_generate_server_config() {
  local output="$1" major="$2" listen_host="$3" listen_port="$4" psk="$5"
  case "$major" in
    4|5)
      cat >"$output" <<EOF
[snell-server]
listen = ${listen_host}:${listen_port}
psk = ${psk}
ipv6 = false
EOF
      ;;
    *) return 1 ;;
  esac
}

snell_validate_runtime_config() {
  local binary="$1" major="$2" psk="$3" port config log pid ready=0
  port="$(nb_select_available_port TCP)" || return 1
  config="$(mktemp_file .conf)" || return 1
  log="$(mktemp_file .log)" || { rm -f "$config"; return 1; }
  snell_generate_server_config "$config" "$major" 127.0.0.1 "$port" "$psk" \
    || { rm -f "$config" "$log"; return 1; }
  "$binary" -c "$config" >"$log" 2>&1 &
  pid=$!
  local i=0
  while [ "$i" -lt 10 ]; do
    if nb_port_is_listening TCP "$port"; then ready=1; break; fi
    kill -0 "$pid" 2>/dev/null || break
    sleep 1
    i=$((i + 1))
  done
  kill "$pid" >/dev/null 2>&1 || true
  wait "$pid" >/dev/null 2>&1 || true
  if [ "$ready" -ne 1 ]; then
    sed -E 's/(psk[[:space:]]*=[[:space:]]*).*/\1***REDACTED***/I' "$log" >&2 || true
    rm -f "$config" "$log"
    return 1
  fi
  rm -f "$config" "$log"
}

snell_download_candidate() {
  local major="$1" output="$2" release version url status upstream_sha256 temp candidate reported actual_archive_sha256
  case "$major" in 4|5) ;; *) return 1 ;; esac
  snell_platform_supported "$major" || {
    warn "Snell v${major} on this platform unsupported"
    return 1
  }
  release="$(snell_resolve_release "$major")" || return 1
  IFS=$'\t' read -r version url status upstream_sha256 <<<"$release"
  [[ "$url" = https://dl.nssurge.com/snell/snell-server-v*-linux-*.zip ]] || {
    warn "拒绝非 Surge 官方 HTTPS Snell asset: $url"
    return 1
  }
  temp="$(mktemp_dir)" || return 1
  if ! curl -fL --connect-timeout 15 --max-time 180 \
      --retry 3 --retry-delay 2 --retry-all-errors \
      -H 'User-Agent: NoBrand-OneClick' "$url" -o "$temp/snell.zip"; then
    rm -rf -- "$temp"
    return 1
  fi
  if [ -n "$upstream_sha256" ]; then
    [[ "$upstream_sha256" =~ ^[0-9a-fA-F]{64}$ ]] || { rm -rf -- "$temp"; return 1; }
    actual_archive_sha256="$(nobrand_sha256_file "$temp/snell.zip")" || { rm -rf -- "$temp"; return 1; }
    [ "$actual_archive_sha256" = "$(printf '%s' "$upstream_sha256" | tr '[:upper:]' '[:lower:]')" ] \
      || { warn "Surge Snell upstream SHA-256 mismatch"; rm -rf -- "$temp"; return 1; }
  fi
  if ! unzip -t "$temp/snell.zip" >/dev/null \
     || ! unzip -qo "$temp/snell.zip" -d "$temp/unpacked"; then
    rm -rf -- "$temp"
    return 1
  fi
  candidate="$(find "$temp/unpacked" -type f -name snell-server | head -n1)"
  [ -n "$candidate" ] && [ "$(head -c 4 "$candidate" 2>/dev/null || true)" = $'\x7fELF' ] \
    || { rm -rf -- "$temp"; return 1; }
  chmod 0755 "$candidate" || { rm -rf -- "$temp"; return 1; }
  reported="$(snell_runtime_reported_version "$candidate" 2>/dev/null || true)"
  [[ "$reported" = "$major".* ]] || { rm -rf -- "$temp"; return 1; }
  install -m 0755 "$candidate" "$output" || { rm -rf -- "$temp"; return 1; }
  SNELL_RESOLVED_VERSION="$version"
  SNELL_RESOLVED_URL="$url"
  SNELL_RESOLVED_STATUS="$status"
  SNELL_RESOLVED_SHA256="$(nobrand_sha256_file "$candidate" 2>/dev/null || true)"
  info "Surge official Snell v${version} (${status}) verified; sha256=${SNELL_RESOLVED_SHA256:-unavailable}"
  rm -rf -- "$temp"
}

snell_install_runtime() {
  local major="$1" force="${2:-0}" destination metadata candidate backup="" metadata_backup=""
  local had_old=0 had_metadata=0 test_psk metadata_tmp=""
  case "$major" in 4|5) ;; *) return 1 ;; esac
  destination="$(snell_runtime_path "$major")"
  metadata="$(snell_runtime_metadata_path "$major")"
  if [ -x "$destination" ] && [ "$force" -ne 1 ]; then
    return 0
  fi
  candidate="$(mktemp_file .snell)" || return 1
  if ! snell_download_candidate "$major" "$candidate"; then
    rm -f "$candidate"
    return 1
  fi
  test_psk="$(openssl rand -hex 16 2>/dev/null || printf '0123456789abcdef0123456789abcdef')"
  if ! snell_validate_runtime_config "$candidate" "$major" "$test_psk"; then
    rm -f "$candidate"
    warn "Snell v${major} official runtime validation failed"
    return 1
  fi
  mkdir -p "$NOBRAND_SNELL_RUNTIME_DIR" || { rm -f "$candidate"; return 1; }
  if [ -e "$destination" ]; then
    backup="$(mktemp "${destination}.rollback.XXXXXX")" || { rm -f "$candidate"; return 1; }
    rm -f "$backup"
    mv "$destination" "$backup" || { rm -f "$candidate"; return 1; }
    had_old=1
  fi
  if [ -e "$metadata" ]; then
    metadata_backup="$(mktemp "${metadata}.rollback.XXXXXX")" || {
      rm -f "$candidate"
      [ "$had_old" -eq 0 ] || mv "$backup" "$destination" 2>/dev/null || true
      return 1
    }
    cp -a "$metadata" "$metadata_backup" || {
      rm -f "$candidate" "$metadata_backup"
      [ "$had_old" -eq 0 ] || mv "$backup" "$destination" 2>/dev/null || true
      return 1
    }
    had_metadata=1
  fi
  if ! install -m 0755 "$candidate" "${destination}.new" \
     || ! mv -f "${destination}.new" "$destination" \
     || ! snell_runtime_reported_version "$destination" >/dev/null; then
    rm -f "$candidate" "${destination}.new" "$destination"
    [ "$had_old" -eq 0 ] || mv "$backup" "$destination" 2>/dev/null || true
    rm -f "$metadata_backup"
    return 1
  fi
  metadata_tmp="$(mktemp_file .json)" || true
  if [ -z "$metadata_tmp" ] \
     || ! jq -n --arg major "$major" --arg release_version "$SNELL_RESOLVED_VERSION" \
          --arg reported_version "$(snell_runtime_reported_version "$destination")" \
          --arg status "$SNELL_RESOLVED_STATUS" --arg source_url "$SNELL_RESOLVED_URL" \
          --arg sha256 "$SNELL_RESOLVED_SHA256" --arg installed_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
            {
              major:($major|tonumber), release_version:$release_version,
              reported_version:$reported_version, status:$status,
              source_url:$source_url, sha256:$sha256, installed_at:$installed_at
            }
          ' >"$metadata_tmp" \
     || ! nb_atomic_install_file "$metadata_tmp" "$metadata" 0600; then
    rm -f "$candidate" "$metadata_tmp" "$destination"
    [ "$had_old" -eq 0 ] || mv "$backup" "$destination" 2>/dev/null || true
    if [ "$had_metadata" -eq 1 ]; then
      mv -f "$metadata_backup" "$metadata" 2>/dev/null || true
    else
      rm -f "$metadata"
    fi
    return 1
  fi
  rm -f "$candidate" "$metadata_tmp" "$backup" "$metadata_backup"
}

snell_install_service_runtime() {
  local manager tmp
  manager="$(nb_service_manager)"
  mkdir -p "$(dirname "$NOBRAND_SNELL_RUNNER")" || return 1
  tmp="$(mktemp_file .runner)" || return 1
  cat >"$tmp" <<EOF
#!/usr/bin/env bash
set -euo pipefail
id="\${1:-}"
[[ "\$id" =~ ^s[0-9a-f]{16}\$ ]] || exit 64
state="${NOBRAND_SNELL_STATE_DIR}/\${id}.json"
config="${NOBRAND_SNELL_CONFIG_DIR}/\${id}.conf"
[ -r "\$state" ] && [ -r "\$config" ] || exit 66
version="\$(jq -r '.version // empty' "\$state")"
case "\$version" in 4|5) ;; *) exit 65 ;; esac
exec "${NOBRAND_SNELL_RUNTIME_DIR}/snell-v\${version}" -c "\$config"
EOF
  install -m 0755 "$tmp" "${NOBRAND_SNELL_RUNNER}.new" \
    && mv -f "${NOBRAND_SNELL_RUNNER}.new" "$NOBRAND_SNELL_RUNNER" \
    || { rm -f "$tmp" "${NOBRAND_SNELL_RUNNER}.new"; return 1; }
  rm -f "$tmp"
  case "$manager" in
    systemd)
      tmp="$(mktemp_file .service)" || return 1
      cat >"$tmp" <<EOF
# Managed by NoBrand-OneClick
[Unit]
Description=NoBrand Snell instance %i
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
ExecStart=${NOBRAND_SNELL_RUNNER} %i
Restart=on-failure
RestartSec=3
LimitNOFILE=1048576
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_BIND_SERVICE
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full
ProtectHome=true
ReadOnlyPaths=${NOBRAND_SNELL_CONFIG_DIR} ${NOBRAND_SNELL_STATE_DIR} ${NOBRAND_SNELL_RUNTIME_DIR}

[Install]
WantedBy=multi-user.target
EOF
      install -m 0644 "$tmp" "${NOBRAND_SNELL_SYSTEMD_TEMPLATE}.new" \
        && mv -f "${NOBRAND_SNELL_SYSTEMD_TEMPLATE}.new" "$NOBRAND_SNELL_SYSTEMD_TEMPLATE" \
        || { rm -f "$tmp" "${NOBRAND_SNELL_SYSTEMD_TEMPLATE}.new"; return 1; }
      rm -f "$tmp"
      systemctl daemon-reload
      ;;
    openrc) ;;
    *) return 1 ;;
  esac
}

snell_systemd_unit() { printf 'nobrand-snell@%s.service' "$1"; }
snell_openrc_service() { printf 'nobrand-snell-%s' "$1"; }

snell_ensure_openrc_service() {
  local id="$1" path tmp
  [ "$(nb_service_manager)" = openrc ] || return 0
  [[ "$id" =~ ^s[0-9a-f]{16}$ ]] || return 1
  path="${NOBRAND_SNELL_OPENRC_PREFIX}${id}"
  tmp="$(mktemp_file .openrc)" || return 1
  cat >"$tmp" <<EOF
#!/sbin/openrc-run
# Managed by NoBrand-OneClick
name="NoBrand Snell ${id}"
command="${NOBRAND_SNELL_RUNNER}"
command_args="${id}"
command_background=true
pidfile="/run/nobrand-snell-${id}.pid"
output_log="/var/log/nobrand-snell-${id}.log"
error_log="/var/log/nobrand-snell-${id}.err"
depend() { use net; after firewall; }
EOF
  install -m 0755 "$tmp" "${path}.new" && mv -f "${path}.new" "$path" \
    || { rm -f "$tmp" "${path}.new"; return 1; }
  rm -f "$tmp"
}

snell_service_action() {
  local id="$1" action="$2" manager unit service
  manager="$(nb_service_manager)"
  unit="$(snell_systemd_unit "$id")"
  service="$(snell_openrc_service "$id")"
  case "$manager" in
    systemd)
      [ "$action" != restart ] || systemctl daemon-reload
      [ "$action" != start ] && [ "$action" != restart ] \
        || systemctl enable "$unit" >/dev/null 2>&1
      systemctl "$action" "$unit"
      ;;
    openrc)
      snell_ensure_openrc_service "$id" || return 1
      [ "$action" != start ] && [ "$action" != restart ] \
        || rc-update add "$service" default >/dev/null 2>&1
      rc-service "$service" "$action"
      ;;
    *) return 1 ;;
  esac
}

snell_service_active() {
  local id="$1"
  nb_service_is_active "$(snell_systemd_unit "$id")" "$(snell_openrc_service "$id")"
}

snell_remove_service() {
  local id="$1" manager unit service
  manager="$(nb_service_manager)"
  unit="$(snell_systemd_unit "$id")"; service="$(snell_openrc_service "$id")"
  snell_service_action "$id" stop >/dev/null 2>&1 || true
  case "$manager" in
    systemd) systemctl disable "$unit" >/dev/null 2>&1 || true ;;
    openrc)
      rc-update del "$service" default >/dev/null 2>&1 || true
      rm -f "${NOBRAND_SNELL_OPENRC_PREFIX}${id}"
      ;;
  esac
}

# ---------- NoBrand VLESS Sudoku isolated Xray service ----------

nobrand_write_vless_sudoku_service() {
  local manager tmp
  manager="$(nb_service_manager)"
  case "$manager" in
    systemd)
      tmp="$(mktemp_file .service)" || return 1
      cat >"$tmp" <<EOF
# Managed by NoBrand-OneClick
[Unit]
Description=NoBrand Plain VLESS FinalMask Sudoku (Xray-core)
Documentation=https://github.com/ike-sh/NoBrand-OneClick
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=${NOBRAND_VLESS_CONFIG_DIR}
ExecStart=${NOBRAND_XRAY_BIN} run -c ${NOBRAND_VLESS_CONFIG_FILE}
Restart=on-failure
RestartSec=5
LimitNOFILE=1048576
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_BIND_SERVICE
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full
ProtectHome=true
ReadWritePaths=${NOBRAND_VLESS_CONFIG_DIR} ${NOBRAND_VLESS_STATE_DIR}

[Install]
WantedBy=multi-user.target
EOF
      grep -qF "ExecStart=${NOBRAND_XRAY_BIN} run -c ${NOBRAND_VLESS_CONFIG_FILE}" "$tmp" \
        || { rm -f "$tmp"; return 1; }
      install -m 0644 "$tmp" "${NOBRAND_VLESS_SYSTEMD_SERVICE}.new" \
        && mv -f "${NOBRAND_VLESS_SYSTEMD_SERVICE}.new" "$NOBRAND_VLESS_SYSTEMD_SERVICE" \
        || { rm -f "$tmp" "${NOBRAND_VLESS_SYSTEMD_SERVICE}.new"; return 1; }
      rm -f "$tmp"
      systemctl daemon-reload || return 1
      systemctl enable "$NOBRAND_VLESS_SERVICE_NAME" >/dev/null 2>&1
      ;;
    openrc)
      tmp="$(mktemp_file .openrc)" || return 1
      cat >"$tmp" <<EOF
#!/sbin/openrc-run
# Managed by NoBrand-OneClick
name="NoBrand Plain VLESS FinalMask Sudoku"
description="NoBrand Plain VLESS FinalMask Sudoku (Xray-core)"
command="${NOBRAND_XRAY_BIN}"
command_args="run -c ${NOBRAND_VLESS_CONFIG_FILE}"
command_background=true
pidfile="/run/nobrand-vless-sudoku.pid"
output_log="/var/log/nobrand-vless-sudoku.log"
error_log="/var/log/nobrand-vless-sudoku.err"
depend() { use net; after firewall; }
EOF
      install -m 0755 "$tmp" "${NOBRAND_VLESS_OPENRC_SERVICE}.new" \
        && mv -f "${NOBRAND_VLESS_OPENRC_SERVICE}.new" "$NOBRAND_VLESS_OPENRC_SERVICE" \
        || { rm -f "$tmp" "${NOBRAND_VLESS_OPENRC_SERVICE}.new"; return 1; }
      rm -f "$tmp"
      rc-update add "$NOBRAND_VLESS_SERVICE_NAME" default >/dev/null 2>&1
      ;;
    *) return 1 ;;
  esac
}

nobrand_vless_sudoku_service_action() {
  local action="$1" manager
  manager="$(nb_service_manager)"
  case "$manager" in
    systemd)
      [ "$action" != restart ] || systemctl daemon-reload
      systemctl "$action" "$NOBRAND_VLESS_SERVICE_NAME"
      ;;
    openrc) rc-service "$NOBRAND_VLESS_SERVICE_NAME" "$action" ;;
    *) return 1 ;;
  esac
}

nobrand_vless_sudoku_service_active() {
  nb_service_is_active "$NOBRAND_VLESS_SERVICE_NAME" "$NOBRAND_VLESS_SERVICE_NAME"
}

nobrand_remove_vless_sudoku_service() {
  local manager
  manager="$(nb_service_manager)"
  nobrand_vless_sudoku_service_action stop >/dev/null 2>&1 || true
  case "$manager" in
    systemd)
      systemctl disable "$NOBRAND_VLESS_SERVICE_NAME" >/dev/null 2>&1 || true
      rm -f "$NOBRAND_VLESS_SYSTEMD_SERVICE"
      systemctl daemon-reload 2>/dev/null || true
      ;;
    openrc)
      rc-update del "$NOBRAND_VLESS_SERVICE_NAME" default >/dev/null 2>&1 || true
      rm -f "$NOBRAND_VLESS_OPENRC_SERVICE"
      ;;
  esac
}

random_token() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -base64 12 | tr -dc 'a-zA-Z0-9' | head -c 10
  else
    date +%s | sha256sum | head -c 10
  fi
}

random_port() {
  local p
  if command -v shuf >/dev/null 2>&1; then
    p="$(shuf -i 1025-65535 -n 1)"
  elif command -v awk >/dev/null 2>&1; then
    p="$(awk 'BEGIN{srand(); print int(1025 + rand() * (65535 - 1025 + 1))}')"
  else
    p=$((1025 + RANDOM % (65535 - 1025 + 1)))
  fi
  printf '%s' "$p"
}

random_available_port() {
  local p i
  i=0
  while [ "$i" -lt 256 ]; do
    p="$(random_port)"
    if port_available_for_mode "$p"; then
      printf '%s' "$p"
      return 0
    fi
    i=$((i + 1))
  done
  return 1
}

normalize_uint() {
  local value="${1:-}"
  [[ "$value" =~ ^[0-9]+$ ]] || return 1
  while [ "${#value}" -gt 1 ] && [ "${value#0}" != "$value" ]; do
    value="${value#0}"
  done
  printf '%s' "$value"
}

# 取本机主用 IPv4：优先默认路由出口地址（ip route get 不发包，仅查路由表，
# 内网无外网也可用），回退首个非回环地址。
detect_local_ip() {
  nb_detect_local_ipv4
}

# 由本机 IP 末位八位组推导端口基数 N*100（要求 N=1-254 且基数≥1025）；不可用返回非0
derive_port_base() {
  local ip
  ip="$(detect_local_ip)"
  nb_port_base_for_ip "$ip"
}

# 在 IP 尾号端口段内随机取一个可用端口：xx01-xx99（xx00 留给 SSH）；不可用返回非0。
# BOTH 双协议时末两位上限取 98，避免 UDP=主端口+1 溢出到 xx00 或下一机器段。
derive_port_from_ip() {
  local base hi
  base="$(derive_port_base)" || return 1
  hi=99
  [ "$PROTOCOL" = "BOTH" ] && hi=98
  nb_scan_port_span "$((base + 1))" "$((base + hi))" port_available_for_mode
}

valid_port() {
  local p
  p="$(normalize_uint "${1:-}")" || return 1
  [ "${#p}" -le 5 ] && [ "$p" -ge 1025 ] && [ "$p" -le 65535 ]
}

valid_advertise_port() {
  local p
  p="$(normalize_uint "${1:-}")" || return 1
  [ "${#p}" -le 5 ] && [ "$p" -ge 1 ] && [ "$p" -le 65535 ]
}

validate_advertise_endpoint_values() {
  local host="${1:-}" port="${2:-}" protocol="${3:-${PROTOCOL:-TCP}}"
  if [ -z "$host" ] && [ -z "$port" ]; then
    return 0
  fi
  [ -n "$host" ] && [ -n "$port" ] || {
    warn "$(t '自定义客户端入口必须同时提供地址和端口' \
      'Custom client entry requires both a host and a port')"
    return 1
  }
  if ! nb_validate_advertise_endpoint "$host" "$port" "$protocol"; then
    warn "$(t '客户端入口无效；请输入有效 IPv4、IPv6 或域名及 1-65535 端口（双协议主端口 ≤65534）' \
      'Invalid client endpoint; use a valid IPv4, IPv6, or domain and port 1-65535 (dual main port <=65534)')"
    return 1
  fi
}

validate_advertise_endpoint() {
  validate_advertise_endpoint_values "$ADVERTISE_HOST" "$ADVERTISE_PORT" "${PROTOCOL:-TCP}"
}

valid_mtu() {
  local value
  value="$(normalize_uint "${1:-}")" || return 1
  [ "${#value}" -le 4 ] && [ "$value" -ge 1280 ] && [ "$value" -le 1500 ]
}

valid_nonnegative_int32() {
  local value="${1:-}" digits
  [[ "$value" =~ ^0*([0-9]{1,10})$ ]] || return 1
  digits="${BASH_REMATCH[1]}"
  [ "$((10#$digits))" -le 2147483647 ]
}

valid_bandwidth_mbps() {
  local value="${1:-}" digits
  [[ "$value" =~ ^0*([0-9]{1,7})$ ]] || return 1
  digits="${BASH_REMATCH[1]}"
  [ "$((10#$digits))" -le 1000000 ]
}

normalize_mtu_policy() {
  case "$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')" in
    safe|default|保守|安全) printf 'safe' ;;
    auto|optimized|optimised|自动|优化) printf 'optimized' ;;
    custom|manual|自定义|手动) printf 'custom' ;;
    *) return 1 ;;
  esac
}

mtu_policy_label() {
  case "$(normalize_mtu_policy "${MTU_POLICY:-safe}" 2>/dev/null || true)" in
    optimized) t '自动优化' 'Auto optimized' ;;
    custom) t '自定义' 'Custom' ;;
    *) t '安全默认' 'Safe default' ;;
  esac
}

mtu_default_iface() {
  local dev=""
  if command -v ip >/dev/null 2>&1; then
    dev="$(ip -o route show default 2>/dev/null \
      | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')"
    [ -n "$dev" ] || dev="$(ip -o -6 route show default 2>/dev/null \
      | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')"
    [ -n "$dev" ] || dev="$(ip -br link 2>/dev/null \
      | awk '$1!="lo"{print $1; exit}' | cut -d@ -f1)"
  fi
  if [ -z "$dev" ] && [ -r /proc/net/route ]; then
    dev="$(awk '$2=="00000000"{print $1; exit}' /proc/net/route 2>/dev/null)"
  fi
  printf '%s' "$dev"
}

mtu_iface_value() {
  local dev="${1:-}" value=""
  [ -n "$dev" ] || return 1
  if [ -r "/sys/class/net/${dev}/mtu" ]; then
    value="$(tr -dc '0-9' <"/sys/class/net/${dev}/mtu" 2>/dev/null || true)"
  fi
  if ! [[ "$value" =~ ^[0-9]+$ ]] && command -v ip >/dev/null 2>&1; then
    value="$(ip -o link show dev "$dev" 2>/dev/null \
      | awk '{for(i=1;i<=NF;i++) if($i=="mtu"){print $(i+1); exit}}')"
  fi
  [[ "$value" =~ ^[0-9]+$ ]] || return 1
  printf '%s' "$value"
}

mtu_route_family() {
  local dev="${1:-}"
  if command -v ip >/dev/null 2>&1 \
     && ip route get 1.1.1.1 2>/dev/null \
       | awk -v expected="$dev" '
           { for (i=1; i<NF; i++) if ($i=="dev" && $(i+1)==expected) found=1 }
           END { exit(found ? 0 : 1) }
         '; then
    printf 'IPv4'
    return 0
  fi
  if command -v ip >/dev/null 2>&1 \
     && ip -6 route get 2606:4700:4700::1111 2>/dev/null \
       | awk -v expected="$dev" '
           { for (i=1; i<NF; i++) if ($i=="dev" && $(i+1)==expected) found=1 }
           END { exit(found ? 0 : 1) }
         '; then
    printf 'IPv6'
    return 0
  fi
  printf 'unknown'
}

# 自动策略只对 UDP 数据报大小有直接收益；TCP 由流式分片控制，保持 1400。
# mihomo 的 mieru 节点当前没有 mtu 字段，因此自动策略统一封顶 1400；
# 只有明确使用支持同步 MTU 的官方客户端时，才建议手工配置 1401-1500。
calculate_optimized_mtu() {
  local candidate
  MTU_AUTO_IFACE=""
  MTU_AUTO_LINK=""
  MTU_AUTO_FAMILY=""
  MTU_AUTO_OVERHEAD=""
  MTU_POLICY="optimized"
  if [ "${PROTOCOL:-TCP}" = "TCP" ]; then
    MTU=1400
    MTU_AUTO_FAMILY="TCP"
    return 0
  fi
  MTU_AUTO_IFACE="$(mtu_default_iface)"
  MTU_AUTO_LINK="$(mtu_iface_value "$MTU_AUTO_IFACE" 2>/dev/null || true)"
  if ! [[ "$MTU_AUTO_LINK" =~ ^[0-9]+$ ]]; then
    MTU=1400
    return 0
  fi
  MTU_AUTO_FAMILY="$(mtu_route_family "$MTU_AUTO_IFACE")"
  case "$MTU_AUTO_FAMILY" in
    IPv4) MTU_AUTO_OVERHEAD=28 ;;
    *) MTU_AUTO_OVERHEAD=48 ;;
  esac
  candidate=$((MTU_AUTO_LINK - MTU_AUTO_OVERHEAD))
  [ "$candidate" -gt 1400 ] && candidate=1400
  [ "$candidate" -lt 1280 ] && candidate=1280
  MTU="$candidate"
}

resolve_mtu_request() {
  local raw="${MTU_REQUEST:-${MTU_POLICY:-safe}}" normalized=""
  if [[ "$raw" =~ ^[0-9]+$ ]]; then
    valid_mtu "$raw" || {
      die "$(t '非法 MTU：必须为 1280-1500' 'Invalid MTU: expected 1280-1500')" || return 1
    }
    MTU="$(normalize_uint "$raw")"
    MTU_POLICY="custom"
    return 0
  fi
  normalized="$(normalize_mtu_policy "$raw" 2>/dev/null || true)"
  case "$normalized" in
    safe)
      MTU=1400
      MTU_POLICY="safe"
      ;;
    optimized)
      calculate_optimized_mtu
      ;;
    custom)
      valid_mtu "${MTU:-}" || {
        die "$(t '自定义 MTU 必须为 1280-1500' 'Custom MTU must be 1280-1500')" || return 1
      }
      MTU_POLICY="custom"
      ;;
    *)
      die "$(t '--mtu 仅支持 safe、auto 或 1280-1500' \
        '--mtu accepts only safe, auto, or a value from 1280 to 1500')" || return 1
      ;;
  esac
}

print_mtu_selection() {
  t "已选 MTU: ${MTU}（$(mtu_policy_label)）" \
    "Selected MTU: ${MTU} ($(mtu_policy_label))"
  if [ "$MTU_POLICY" = "optimized" ]; then
    if [ "${PROTOCOL:-TCP}" = "TCP" ]; then
      t '  TCP 模式提高 MTU 没有明显收益，自动策略保持 1400' \
        '  Raising MTU has little benefit in TCP mode; auto keeps 1400'
    elif [ -n "$MTU_AUTO_LINK" ]; then
      t "  检测: 网卡 ${MTU_AUTO_IFACE}，链路 MTU ${MTU_AUTO_LINK}，${MTU_AUTO_FAMILY} 开销 ${MTU_AUTO_OVERHEAD}" \
        "  Detected: ${MTU_AUTO_IFACE}, link MTU ${MTU_AUTO_LINK}, ${MTU_AUTO_FAMILY} overhead ${MTU_AUTO_OVERHEAD}"
    else
      warn "$(t '未能读取出口链路 MTU，自动策略已回退到 1400' \
        'Could not read egress link MTU; auto fell back to 1400')"
    fi
  fi
  if [ "${PROTOCOL:-TCP}" = "TCP" ] && [ "$MTU" -gt 1400 ]; then
    warn "$(t 'TCP 模式使用大于 1400 的 MTU 通常没有明显收益，并可能降低复杂网络路径的兼容性' \
      'MTU above 1400 usually offers no clear benefit for TCP and may reduce path compatibility')"
  fi
  if [ "$MTU" -gt 1400 ]; then
    warn "$(t 'mihomo 的 mieru 节点当前不能单独指定 MTU；大于 1400 仅建议用于可同步相同 MTU 的官方 mieru 客户端' \
      'mihomo mieru proxies currently cannot set MTU; values above 1400 are recommended only with official mieru clients configured to the same MTU')"
  fi
}

choose_mtu_interactive() {
  local input="" def=1 custom=""
  if [ "${MTU_CLI:-0}" -eq 1 ]; then
    resolve_mtu_request || return 1
    print_mtu_selection
    return 0
  fi
  case "$(normalize_mtu_policy "${MTU_POLICY:-safe}" 2>/dev/null || true)" in
    optimized) def=2 ;;
    custom) def=3 ;;
    *) def=1 ;;
  esac
  msg ""
  t 'MTU 策略（与 multiplexing、handshake、traffic-pattern 无绑定关系）:' \
    'MTU policy (independent of multiplexing, handshake, and traffic-pattern):'
  t '  1) 安全默认 1400（推荐，跨网络兼容性最好）' \
    '  1) Safe 1400 (recommended, best path compatibility)'
  t '  2) 自动兼容（TCP 保持 1400；UDP/双协议按出口链路计算，兼容 mihomo，最大 1400）' \
    '  2) Auto compatible (TCP stays 1400; UDP/dual uses egress link MTU, mihomo-safe max 1400)'
  t '  3) 自定义 1280-1500' '  3) Custom 1280-1500'
  read_tty input "$(t "请选择 [1-3，默认 ${def}]: " "Choose [1-3, default ${def}]: ")" || input=""
  input="${input:-$def}"
  case "$input" in
    2)
      MTU_REQUEST="auto"
      resolve_mtu_request || return 1
      ;;
    3)
      while true; do
        custom=""
        read_tty custom "$(t "自定义 MTU [${MTU}]: " "Custom MTU [${MTU}]: ")" || custom=""
        custom="${custom:-$MTU}"
        if valid_mtu "$custom"; then
          MTU="$custom"
          MTU_POLICY="custom"
          break
        fi
        warn "$(t '请输入 1280-1500 的整数' 'Enter an integer from 1280 to 1500')"
      done
      ;;
    *)
      MTU=1400
      MTU_POLICY="safe"
      ;;
  esac
  print_mtu_selection
}

# ---------- 多用户（阶段1 端口；阶段2 套餐 quotas + 到期停用） ----------

users_require_python() {
  command -v python3 >/dev/null 2>&1 || die "$(t '多用户管理需要 python3' 'python3 required for multi-user management')"
}

users_log() {
  local line quiet="${USERS_LOG_QUIET:-0}"
  line="$(date '+%Y-%m-%d %H:%M:%S') $*"
  printf '%s\n' "$line" >>"${MITA_USERS_LOG}" 2>/dev/null || true
  [ "$quiet" = "1" ] || msg "$line" >&2
}

# 套餐模板 → 设置 USER_QUOTA_MB / USER_QUOTA_DAYS / 可选默认到期
# unlimited: 0/0；trial: 10GB/7天；standard: 100GB/30天；custom: 用 CLI 值
apply_user_package_defaults() {
  local fill_missing="${1:-1}" pkg
  pkg="$(printf '%s' "${USER_PACKAGE:-}" | tr '[:upper:]' '[:lower:]')"
  case "$pkg" in
    "")
      ;;
    unlimited|unlimit|none|0|无限)
      USER_QUOTA_MB=0
      USER_QUOTA_DAYS=0
      USER_PACKAGE="unlimited"
      ;;
    trial|体验|test)
      [ -n "${USER_QUOTA_MB}" ] || USER_QUOTA_MB=10240
      [ -n "${USER_QUOTA_DAYS}" ] || USER_QUOTA_DAYS=7
      [ -n "${USER_EXPIRE}" ] || USER_EXPIRE="+7d"
      USER_PACKAGE="trial"
      ;;
    standard|std|标准|月包)
      [ -n "${USER_QUOTA_MB}" ] || USER_QUOTA_MB=102400
      [ -n "${USER_QUOTA_DAYS}" ] || USER_QUOTA_DAYS=30
      [ -n "${USER_EXPIRE}" ] || USER_EXPIRE="+30d"
      USER_PACKAGE="standard"
      ;;
    custom|自定义)
      USER_PACKAGE="custom"
      ;;
    *)
      warn "$(t "未知套餐 ${USER_PACKAGE}，忽略（可用 unlimited|trial|standard|custom）" \
        "Unknown package ${USER_PACKAGE}; use unlimited|trial|standard|custom")"
      USER_PACKAGE=""
      return 1
      ;;
  esac
  if [ "$fill_missing" = "1" ]; then
    [ -n "${USER_QUOTA_DAYS}" ] || USER_QUOTA_DAYS=30
    [ -n "${USER_QUOTA_MB}" ] || USER_QUOTA_MB=0
  elif [ -n "${USER_QUOTA_MB}" ]; then
    valid_nonnegative_int32 "$USER_QUOTA_MB" || return 1
    if [ "$USER_QUOTA_MB" -eq 0 ]; then
      USER_QUOTA_DAYS=0
    else
      [ -n "${USER_QUOTA_DAYS}" ] || USER_QUOTA_DAYS=30
    fi
  fi
}

# 解析到期：空/0/never → 空；+Nd → 今天+N天 YYYY-MM-DD；YYYY-MM-DD 原样
parse_expire_date() {
  local raw="$1" days
  raw="$(printf '%s' "$raw" | tr -d '[:space:]')"
  if [ -z "$raw" ] || [ "$raw" = "0" ] || [ "$raw" = "never" ] || [ "$raw" = "none" ] || [ "$raw" = "-" ]; then
    printf ''
    return 0
  fi
  if [[ "$raw" =~ ^\+([0-9]+)[dD]?$ ]]; then
    days="${BASH_REMATCH[1]}"
    if date -u -d "+${days} days" +%Y-%m-%d >/dev/null 2>&1; then
      date -u -d "+${days} days" +%Y-%m-%d
      return 0
    fi
    if date -u -v+"${days}"d +%Y-%m-%d >/dev/null 2>&1; then
      date -u -v+"${days}"d +%Y-%m-%d
      return 0
    fi
    # busybox / python fallback
    if command -v python3 >/dev/null 2>&1; then
      python3 -c "import datetime;print((datetime.date.today()+datetime.timedelta(days=int('${days}'))).isoformat())" 2>/dev/null
      return $?
    fi
    warn "$(t "当前系统无法计算相对日期: $raw" "Cannot calculate relative date on this system: $raw")"
    return 1
  fi
  if [[ "$raw" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
    if [ "$(date -d "$raw" +%Y-%m-%d 2>/dev/null || true)" = "$raw" ]; then
      printf '%s' "$raw"
      return 0
    fi
    if command -v python3 >/dev/null 2>&1 \
       && python3 -c 'import datetime,sys; datetime.date.fromisoformat(sys.argv[1])' "$raw" 2>/dev/null; then
      printf '%s' "$raw"
      return 0
    fi
    warn "$(t "无效日历日期: $raw" "Invalid calendar date: $raw")"
    return 1
  fi
  warn "$(t "无法解析到期日: $raw（用 YYYY-MM-DD 或 +30d）" "Bad expire: $raw (use YYYY-MM-DD or +30d)")"
  return 1
}

# 与 calendar 重置统一用本地日历日（与 mita 服务器本地时间一致）
today_ymd() {
  date +%Y-%m-%d 2>/dev/null || python3 -c 'import datetime;print(datetime.date.today().isoformat())'
}

quota_label() {
  local mb="${1:-0}" days="${2:-0}"
  if [ -z "$mb" ] || [ "$mb" = "0" ] || [ "$mb" = "null" ]; then
    t '不限量' 'unlimited'
    return
  fi
  if [ "$mb" -ge 1024 ] 2>/dev/null; then
    printf '%sGB/%sd' "$((mb / 1024))" "${days:-30}"
  else
    printf '%sMB/%sd' "$mb" "${days:-30}"
  fi
}

users_state_init_empty() {
  if [ "${DRY_RUN:-0}" -eq 1 ]; then
    msg "[dry-run] initialize users state: $MITA_USERS_STATE"
    return 0
  fi
  run mkdir -p "$(dirname "$MITA_USERS_STATE")"
  printf '%s\n' '{"version":2,"users":[]}' >"$MITA_USERS_STATE"
  run chmod 0600 "$MITA_USERS_STATE" 2>/dev/null || true
}

users_state_exists() {
  [ -f "$MITA_USERS_STATE" ] && [ -s "$MITA_USERS_STATE" ]
}

users_tx_snapshot() {
  local snapshot
  snapshot="$(mktemp_file .users.json)" || return 1
  if users_state_exists; then
    cp -f "$MITA_USERS_STATE" "$snapshot" || { rm -f "$snapshot"; return 1; }
  else
    printf '%s\n' '__MITA_USERS_STATE_ABSENT__' >"$snapshot"
  fi
  chmod 0600 "$snapshot" 2>/dev/null || true
  printf '%s' "$snapshot"
}

users_tx_commit() {
  local snapshot="${1:-}"
  [ -n "$snapshot" ] && prune_orphan_instances 2>/dev/null || true
  [ -n "$snapshot" ] && rm -f "$snapshot" 2>/dev/null || true
}

users_tx_restore() {
  local snapshot="${1:-}"
  [ -f "$snapshot" ] || return 1
  if grep -qx '__MITA_USERS_STATE_ABSENT__' "$snapshot" 2>/dev/null; then
    rm -f "$MITA_USERS_STATE" 2>/dev/null || true
    return 2
  fi
  run mkdir -p "$(dirname "$MITA_USERS_STATE")"
  cp -f "$snapshot" "$MITA_USERS_STATE" || return 1
  chmod 0600 "$MITA_USERS_STATE" 2>/dev/null || true
  return 0
}

users_tx_rollback() {
  local snapshot="${1:-}" reapply="${2:-0}" restored=0 restore_rc=0 cfg bin
  [ -n "$snapshot" ] || return 0
  # apply_users_config 失败时会自行消费快照；外层再次回滚应是安全空操作。
  [ -f "$snapshot" ] || return 0
  if users_tx_restore "$snapshot"; then
    restored=1
  else
    restore_rc=$?
    if [ "$restore_rc" -eq 2 ]; then
      restored=2
    else
      warn "$(t '用户状态回滚失败，请从最近备份恢复' \
        'Failed to roll back users state; restore the latest backup')"
    fi
  fi
  if [ "$restored" -gt 0 ] && [ "$reapply" -eq 1 ] && mita_installed 2>/dev/null; then
    MULTI_USER_MODE=1
    if [ "$restored" -eq 2 ]; then
      isolated_stop_all
      default_mita_restore 2>/dev/null || warn "$(t '用户状态已恢复为空，但旧默认服务恢复失败，请立即运行 doctor' \
        'Users state was restored to absent, but the old default service failed to recover; run doctor now')"
      apply_tc_limits 2>/dev/null || true
    elif users_isolated_mode; then
      if ! reconcile_isolated_instances 2>/dev/null; then
        warn "$(t '用户状态已回滚，但专属实例配置重新应用失败，请立即运行 doctor' \
          'Users state was rolled back, but reapplying dedicated instances failed; run doctor now')"
      fi
      apply_tc_limits 2>/dev/null || warn "$(t '用户状态已回滚，但旧限速规则未能完全恢复' \
        'Users state was rolled back, but previous rate filters were not fully restored')"
    else
      # 本次操作可能刚从旧单实例迁移而来，先清理所有已生成的专属实例，
      # 再恢复旧默认服务，避免两套运行时同时占用端口。
      isolated_stop_all
      if cfg="$(write_server_config_multi 2>/dev/null)" \
         && apply_config "$cfg" \
         && mita_sync_users_to_state; then
          bin="$(mita_bin)"
          "$bin" reload 2>/dev/null || start_mita 2>/dev/null || true
          apply_tc_limits 2>/dev/null || true
      else
        warn "$(t '用户状态已回滚，但旧服务端配置重新应用失败，请立即运行 doctor' \
          'Users state was rolled back, but reapplying the old server config failed; run doctor now')"
      fi
    fi
  fi
  users_tx_commit "$snapshot"
}

users_count() {
  users_state_exists || { printf '0'; return 0; }
  command -v python3 >/dev/null 2>&1 || { printf '0'; return 0; }
  python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(len(d.get("users") or []))' \
    "$MITA_USERS_STATE" 2>/dev/null || printf '0'
}

users_rate_limited_count() {
  users_state_exists || { printf '0'; return 0; }
  command -v python3 >/dev/null 2>&1 || { printf '0'; return 0; }
  python3 -c '
import json,sys
d=json.load(open(sys.argv[1]))
print(sum(
    1 for u in (d.get("users") or [])
    if u.get("enabled", True) and int(u.get("bandwidth_mbps") or 0) > 0
))
' "$MITA_USERS_STATE" 2>/dev/null || printf '0'
}

users_deployment_model() {
  users_state_exists || return 1
  python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("deployment_model") or "")' \
    "$MITA_USERS_STATE" 2>/dev/null
}

users_isolated_mode() {
  [ "$(users_deployment_model 2>/dev/null || true)" = "$MITA_DEPLOYMENT_MODEL" ]
}

users_set_deployment_model() {
  local model="$1"
  [ "${DRY_RUN:-0}" -eq 1 ] && {
    msg "[dry-run] set deployment_model=$model in $MITA_USERS_STATE"
    return 0
  }
  _U_DEPLOYMENT_MODEL="$model" users_py_locked '
import json, os
path = os.environ["MITA_USERS_STATE"]
d = json.load(open(path))
model = os.environ.get("_U_DEPLOYMENT_MODEL") or ""
if model:
    d["deployment_model"] = model
else:
    d.pop("deployment_model", None)
json.dump(d, open(path, "w"), indent=2)
'
}

users_enabled_instance_rows() {
  users_state_exists || return 1
  python3 -c '
import json,sys
d=json.load(open(sys.argv[1]))
for u in d.get("users") or []:
    if not u.get("enabled", True):
        continue
    instance_id=str(u.get("instance_id") or "")
    name=str(u.get("name") or "")
    port=int(u.get("port") or 0)
    if instance_id and name and port:
        print(f"{instance_id}\t{name}\t{port}")
' "$MITA_USERS_STATE" 2>/dev/null
}

users_all_instance_ids() {
  users_state_exists || return 0
  python3 -c '
import json,sys
d=json.load(open(sys.argv[1]))
for u in d.get("users") or []:
    instance_id=str(u.get("instance_id") or "")
    if instance_id: print(instance_id)
' "$MITA_USERS_STATE" 2>/dev/null | LC_ALL=C sort -u
}

instance_valid_id() {
  local id="${1:-}"
  [[ "$id" =~ ^u[0-9a-f]{16}$ ]]
}

instance_config_path() { printf '%s/%s/server.json' "$MITA_INSTANCES_DIR" "$1"; }
instance_socket_path() { printf '%s/%s.sock' "$MITA_INSTANCE_RUN_DIR" "$1"; }
instance_metrics_dir() { printf '%s/%s' "$MITA_INSTANCE_METRICS_DIR" "$1"; }
instance_metrics_file() { printf '%s/%s/metrics.pb' "$MITA_INSTANCE_METRICS_DIR" "$1"; }
instance_systemd_unit() { printf 'mita-oneclick@%s.service' "$1"; }
instance_openrc_service() { printf 'mita-oneclick-%s' "$1"; }

instance_cmd() {
  local id="$1"
  shift
  instance_valid_id "$id" || return 1
  env MITA_CONFIG_JSON_FILE="$(instance_config_path "$id")" \
      MITA_UDS_PATH="$(instance_socket_path "$id")" \
      "$(mita_bin)" "$@"
}

instance_wait_socket() {
  local id="$1" timeout="${2:-30}" i=0 sock
  sock="$(instance_socket_path "$id")"
  while [ "$i" -lt "$timeout" ]; do
    [ -S "$sock" ] && return 0
    sleep 1
    i=$((i + 1))
  done
  return 1
}

users_ensure_instance_ids() {
  users_state_exists || return 1
  users_py_locked '
import hashlib,json,os
path=os.environ["MITA_USERS_STATE"]
d=json.load(open(path))
used=set()
for index,u in enumerate(d.get("users") or []):
    current=str(u.get("instance_id") or "")
    if current.startswith("u") and len(current)==17 \
       and all(c in "0123456789abcdef" for c in current[1:]) and current not in used:
        used.add(current)
        continue
    material="%s\0%s\0%s\0%s" % (
        u.get("name") or "", u.get("created_at") or 0, u.get("port") or 0, index
    )
    salt=0
    while True:
        candidate="u"+hashlib.sha256((material+"\0"+str(salt)).encode()).hexdigest()[:16]
        if candidate not in used:
            break
        salt += 1
    u["instance_id"]=candidate
    used.add(candidate)
d["version"]=max(2,int(d.get("version") or 1))
json.dump(d,open(path,"w"),indent=2)
'
}

install_instance_runtime() {
  local sm bin
  sm="$(service_manager)"
  bin="$(mita_real_bin)"
  if [ "${DRY_RUN:-0}" -eq 1 ]; then
    msg "[dry-run] install isolated mita instance runtime ($sm)"
    return 0
  fi
  [ "$sm" != "none" ] || {
    warn "$(t '专属实例模式需要 systemd 或 OpenRC' \
      'Dedicated-instance mode requires systemd or OpenRC')"
    return 1
  }
  run mkdir -p "$MITA_INSTANCES_DIR" "$MITA_INSTANCE_RUN_DIR" \
    "$MITA_INSTANCE_METRICS_DIR" /usr/local/libexec /var/lib/mita
  # 配置子目录/文件属于 mita，但父目录必须至少允许 mita 组穿越。
  run chown root:mita "$MITA_INSTANCES_DIR"
  run chown mita:mita "$MITA_INSTANCE_RUN_DIR" "$MITA_INSTANCE_METRICS_DIR" /var/lib/mita
  run chmod 0750 "$MITA_INSTANCES_DIR" "$MITA_INSTANCE_RUN_DIR" "$MITA_INSTANCE_METRICS_DIR"

  case "$sm" in
    systemd)
      run mkdir -p "$(dirname "$MITA_INSTANCE_TMPFILES")"
      cat >"$MITA_INSTANCE_TMPFILES" <<EOF
d ${MITA_INSTANCE_RUN_DIR} 0750 mita mita -
EOF
      run chmod 0644 "$MITA_INSTANCE_TMPFILES"
      if command -v systemd-tmpfiles >/dev/null 2>&1; then
        run systemd-tmpfiles --create "$MITA_INSTANCE_TMPFILES"
      fi
      cat >"$MITA_INSTANCE_SYSTEMD_TEMPLATE" <<EOF
[Unit]
Description=Mieru dedicated user instance %i
After=network-online.target
Wants=network-online.target

[Service]
Type=exec
User=mita
Group=mita
Environment=MITA_CONFIG_JSON_FILE=${MITA_INSTANCES_DIR}/%i/server.json
Environment=MITA_UDS_PATH=${MITA_INSTANCE_RUN_DIR}/%i.sock
PrivateMounts=true
BindPaths=${MITA_INSTANCE_METRICS_DIR}/%i:/var/lib/mita
ExecStart=${bin} run
Restart=on-failure
RestartSec=2
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF
      run chmod 0644 "$MITA_INSTANCE_SYSTEMD_TEMPLATE"
      run systemctl daemon-reload
      ;;
    openrc)
      if ! command -v unshare >/dev/null 2>&1 \
          || ! command -v mount >/dev/null 2>&1 \
          || ! command -v setpriv >/dev/null 2>&1; then
          warn "$(t 'OpenRC 专属实例需要 util-linux（unshare、mount、setpriv）' \
            'OpenRC dedicated instances require util-linux (unshare, mount, setpriv)')"
          return 1
      fi
      cat >"$MITA_INSTANCE_RUNNER" <<EOF
#!/bin/sh
set -eu
id="\${1:-}"
printf '%s' "\$id" | grep -Eq '^u[0-9a-f]{16}\$' || exit 64
cfg="${MITA_INSTANCES_DIR}/\$id/server.json"
sock="${MITA_INSTANCE_RUN_DIR}/\$id.sock"
metrics="${MITA_INSTANCE_METRICS_DIR}/\$id"
[ -r "\$cfg" ] && [ -d "\$metrics" ] || exit 66
exec unshare --mount --propagation private sh -c '
  set -eu
  mount --bind "\$1" /var/lib/mita
  exec setpriv --reuid=mita --regid=mita --init-groups \
    env MITA_CONFIG_JSON_FILE="\$2" MITA_UDS_PATH="\$3" "\$4" run
' sh "\$metrics" "\$cfg" "\$sock" "${bin}"
EOF
      run chmod 0755 "$MITA_INSTANCE_RUNNER"
      ;;
  esac
}

instance_ensure_openrc_service() {
  local id="$1" svc
  instance_valid_id "$id" || return 1
  [ "$(service_manager)" = "openrc" ] || return 0
  svc="${MITA_INSTANCE_OPENRC_PREFIX}${id}"
  [ "${DRY_RUN:-0}" -eq 1 ] && {
    msg "[dry-run] write OpenRC instance service $svc"
    return 0
  }
  cat >"$svc" <<EOF
#!/sbin/openrc-run

name="mita dedicated instance ${id}"
description="Mieru dedicated user instance ${id}"
command="${MITA_INSTANCE_RUNNER}"
command_args="${id}"
command_background="yes"
pidfile="/run/mita-oneclick-${id}.pid"
output_log="/var/log/mita-oneclick-${id}.log"
error_log="/var/log/mita-oneclick-${id}.err"
respawn
respawn_delay=5
respawn_max=0

depend() {
  need net localmount
  after firewall
}

start_pre() {
  checkpath --directory --owner mita:mita --mode 0750 "${MITA_INSTANCE_RUN_DIR}" "${MITA_INSTANCE_METRICS_DIR}/${id}"
  checkpath --file --owner mita:mita --mode 0640 "/var/log/mita-oneclick-${id}.log" "/var/log/mita-oneclick-${id}.err"
}
EOF
  run chmod 0755 "$svc"
}

write_instance_config() {
  local id="$1" name="$2" port="$3" full tmp final dir
  instance_valid_id "$id" || return 1
  [ -n "$name" ] && valid_port "$port" || return 1
  full="$(write_server_config_multi)" || return 1
  tmp="$(mktemp_file .instance.json)" || { rm -f "$full"; return 1; }
  if ! _INSTANCE_PORT="$port" _INSTANCE_NAME="$name" _INSTANCE_PROTO="${PROTOCOL:-TCP}" \
      python3 - "$MITA_USERS_STATE" "$full" "$tmp" <<'PY'
import json, os, sys
state_path, full_path, out_path = sys.argv[1:4]
instance_port = int(os.environ["_INSTANCE_PORT"])
name = os.environ["_INSTANCE_NAME"]
proto = os.environ.get("_INSTANCE_PROTO", "TCP")
state = json.load(open(state_path))
full = json.load(open(full_path))
user_state = next((
    u for u in state.get("users") or []
    if u.get("enabled", True) and str(u.get("name") or "") == name
       and int(u.get("port") or 0) == instance_port
), None)
user_cfg = next((u for u in full.get("users") or [] if str(u.get("name") or "") == name), None)
if user_state is None or user_cfg is None:
    raise SystemExit(2)
bindings = [{"port": instance_port, "protocol": "TCP" if proto == "BOTH" else proto}]
if proto == "BOTH":
    bindings.append({"port": instance_port + 1, "protocol": "UDP"})
full["portBindings"] = bindings
full["users"] = [user_cfg]
json.dump(full, open(out_path, "w"), indent=2)
PY
  then
    rm -f "$full" "$tmp"
    return 1
  fi
  rm -f "$full"
  dir="${MITA_INSTANCES_DIR}/${id}"
  final="$(instance_config_path "$id")"
  if [ "${DRY_RUN:-0}" -eq 1 ]; then
    msg "[dry-run] install dedicated config $final"
    rm -f "$tmp"
    return 0
  fi
  run mkdir -p "$dir" "$(instance_metrics_dir "$id")" "$MITA_INSTANCE_RUN_DIR"
  run chown mita:mita "$dir" "$(instance_metrics_dir "$id")" "$MITA_INSTANCE_RUN_DIR"
  run chmod 0750 "$dir" "$(instance_metrics_dir "$id")" "$MITA_INSTANCE_RUN_DIR"
  install -o mita -g mita -m 0600 "$tmp" "${final}.new"
  mv -f "${final}.new" "$final"
  rm -f "$tmp"
}

instance_daemon_start() {
  local id="$1" sm unit svc
  instance_valid_id "$id" || return 1
  sm="$(service_manager)"
  case "$sm" in
    systemd)
      unit="$(instance_systemd_unit "$id")"
      run systemctl enable "$unit" >/dev/null 2>&1
      run systemctl restart "$unit"
      ;;
    openrc)
      instance_ensure_openrc_service "$id"
      svc="$(instance_openrc_service "$id")"
      run rc-update add "$svc" default >/dev/null 2>&1 || true
      run rc-service "$svc" restart 2>/dev/null || run rc-service "$svc" start
      ;;
    *) return 1 ;;
  esac
  instance_wait_socket "$id" 30
}

instance_daemon_stop() {
  local id="$1" disable="${2:-0}" sm unit svc
  instance_valid_id "$id" || return 1
  instance_cmd "$id" stop >/dev/null 2>&1 || true
  sm="$(service_manager)"
  case "$sm" in
    systemd)
      unit="$(instance_systemd_unit "$id")"
      run systemctl stop "$unit" >/dev/null 2>&1 || true
      [ "$disable" -eq 1 ] && run systemctl disable "$unit" >/dev/null 2>&1 || true
      ;;
    openrc)
      svc="$(instance_openrc_service "$id")"
      run rc-service "$svc" stop >/dev/null 2>&1 || true
      if [ "$disable" -eq 1 ]; then
        run rc-update del "$svc" default >/dev/null 2>&1 || true
        run rm -f "${MITA_INSTANCE_OPENRC_PREFIX}${id}"
      fi
      ;;
  esac
  run rm -f "$(instance_socket_path "$id")" 2>/dev/null || true
}

instance_log_tail() {
  local id="$1" sm unit
  instance_valid_id "$id" || return 0
  sm="$(service_manager)"
  case "$sm" in
    systemd)
      unit="$(instance_systemd_unit "$id")"
      journalctl -u "$unit" -n 20 --no-pager 2>/dev/null >&2 || true
      ;;
    openrc)
      tail -n 20 "/var/log/mita-oneclick-${id}.err" \
        "/var/log/mita-oneclick-${id}.log" 2>/dev/null >&2 || true
      ;;
  esac
}

instance_start_proxy() {
  local id="$1" status_out
  if ! instance_daemon_start "$id"; then
    instance_log_tail "$id"
    return 1
  fi
  if ! instance_cmd "$id" start >/dev/null 2>&1; then
    instance_log_tail "$id"
    return 1
  fi
  sleep 1
  status_out="$(instance_cmd "$id" status 2>/dev/null || true)"
  if ! printf '%s' "$status_out" | grep -q 'status is "RUNNING"'; then
    instance_log_tail "$id"
    return 1
  fi
  return 0
}

default_mita_stop() {
  local sm bin
  sm="$(service_manager)"
  bin="$(mita_bin)"
  "$bin" stop >/dev/null 2>&1 || true
  case "$sm" in
    systemd)
      run systemctl stop mita >/dev/null 2>&1 || true
      run systemctl disable mita >/dev/null 2>&1 || true
      ;;
    openrc)
      run rc-service mita stop >/dev/null 2>&1 || true
      run rc-update del mita default >/dev/null 2>&1 || true
      ;;
  esac
}

default_mita_restore() {
  local sm bin
  sm="$(service_manager)"
  bin="$(mita_bin)"
  case "$sm" in
    systemd)
      run systemctl enable mita >/dev/null 2>&1 || true
      run systemctl start mita
      ;;
    openrc)
      run rc-update add mita default >/dev/null 2>&1 || true
      run rc-service mita start
      ;;
    *) return 1 ;;
  esac
  wait_mita_socket 30 && "$bin" start >/dev/null 2>&1
}

isolated_stop_all() {
  local id
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    instance_daemon_stop "$id" 1 || true
  done < <(
    {
      users_all_instance_ids 2>/dev/null || true
      for id in "$MITA_INSTANCES_DIR"/*; do
        [ -d "$id" ] || continue
        basename "$id"
      done
    } | grep -E '^u[0-9a-f]{16}$' | LC_ALL=C sort -u || true
  )
}

prune_orphan_instances() {
  local id path all_ids candidates=""
  all_ids="$(users_all_instance_ids 2>/dev/null || true)"
  for path in "$MITA_INSTANCES_DIR"/* "$MITA_INSTANCE_METRICS_DIR"/*; do
    [ -d "$path" ] || continue
    id="$(basename "$path")"
    instance_valid_id "$id" || continue
    candidates="${candidates}${id}"$'\n'
  done
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    grep -qxF "$id" <<<"$all_ids" && continue
    instance_daemon_stop "$id" 1 || true
    run rm -rf "${MITA_INSTANCES_DIR:?}/${id}" "${MITA_INSTANCE_METRICS_DIR:?}/${id}"
  done < <(printf '%s' "$candidates" | sed '/^[[:space:]]*$/d' | LC_ALL=C sort -u)
}

reconcile_isolated_instances() {
  local id name port desired_ids="" existing_ids="" status_out
  users_require_python || return 1
  users_ensure_instance_ids || return 1
  install_instance_runtime || return 1

  while IFS=$'\t' read -r id name port; do
    [ -n "$id" ] && [ -n "$name" ] && [ -n "$port" ] || continue
    write_instance_config "$id" "$name" "$port" || return 1
    instance_ensure_openrc_service "$id" || return 1
    desired_ids="${desired_ids}${id}"$'\n'
  done < <(users_enabled_instance_rows)
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    existing_ids="${existing_ids}${id}"$'\n'
  done < <(
    for id in "$MITA_INSTANCES_DIR"/*; do
      [ -d "$id" ] || continue
      basename "$id"
    done | grep -E '^u[0-9a-f]{16}$' || true
  )

  while IFS= read -r id; do
    [ -n "$id" ] || continue
    if ! instance_start_proxy "$id"; then
      warn "$(t "专属实例 ${id} 启动或验收失败" \
        "Dedicated instance ${id} failed to start or verify")"
      return 1
    fi
  done <<<"$desired_ids"

  while IFS= read -r id; do
    [ -n "$id" ] || continue
    if ! grep -qxF "$id" <<<"$desired_ids"; then
      instance_daemon_stop "$id" 1 || return 1
    fi
  done <<<"$existing_ids"

  while IFS= read -r id; do
    [ -n "$id" ] || continue
    status_out="$(instance_cmd "$id" status 2>/dev/null || true)"
    printf '%s' "$status_out" | grep -q 'status is "RUNNING"' || return 1
  done <<<"$desired_ids"
  return 0
}

ensure_isolated_deployment() {
  local restore_default="${1:-1}" id name port migrated=0
  users_isolated_mode && {
    reconcile_isolated_instances
    return
  }
  users_ensure_instance_ids || return 1
  install_instance_runtime || return 1
  while IFS=$'\t' read -r id name port; do
    [ -n "$id" ] && [ -n "$name" ] && [ -n "$port" ] || continue
    write_instance_config "$id" "$name" "$port" || return 1
  done < <(users_enabled_instance_rows)

  default_mita_stop
  # 旧单实例停止后再复制最终落盘的 metrics，避免迁移窗口丢失最后一小段计数。
  while IFS=$'\t' read -r id name port; do
    [ -n "$id" ] && [ -n "$name" ] && [ -n "$port" ] || continue
    if [ -s "$MITA_METRICS_FILE" ] && [ ! -s "$(instance_metrics_file "$id")" ]; then
      if ! cp -f "$MITA_METRICS_FILE" "$(instance_metrics_file "$id")"; then
        if [ "$restore_default" -eq 1 ]; then
          default_mita_restore || true
        fi
        return 1
      fi
      chown mita:mita "$(instance_metrics_file "$id")" 2>/dev/null || true
      chmod 0600 "$(instance_metrics_file "$id")" 2>/dev/null || true
    fi
  done < <(users_enabled_instance_rows)

  if reconcile_isolated_instances; then
    users_set_deployment_model "$MITA_DEPLOYMENT_MODEL" || {
      isolated_stop_all
      if [ "$restore_default" -eq 1 ]; then
        default_mita_restore || true
      fi
      return 1
    }
    migrated=1
  else
    isolated_stop_all
    if [ "$restore_default" -eq 1 ]; then
      default_mita_restore || true
    fi
    return 1
  fi
  [ "$migrated" -eq 1 ] && users_log "deployment migrated to ${MITA_DEPLOYMENT_MODEL}"
}

# 在 flock 下执行 python -c（$1=代码）；环境变量传参
users_py_locked() {
  users_require_python
  if [ "${DRY_RUN:-0}" -eq 1 ]; then
    msg "[dry-run] update users state: $MITA_USERS_STATE"
    return 0
  fi
  run mkdir -p "$(dirname "$MITA_USERS_STATE")" "$(dirname "$MITA_USERS_LOCK")"
  local code="$1"
  if command -v flock >/dev/null 2>&1; then
    flock -w 30 "$MITA_USERS_LOCK" env MITA_USERS_STATE="$MITA_USERS_STATE" \
      _U_NAME="${_U_NAME-}" _U_PASS="${_U_PASS-}" _U_PORT="${_U_PORT-}" _U_PROTO="${_U_PROTO-}" \
      _U_QUOTA_MB="${_U_QUOTA_MB-}" _U_QUOTA_DAYS="${_U_QUOTA_DAYS-}" \
      _U_QUOTA_MODE="${_U_QUOTA_MODE-}" \
      _U_EXPIRE="${_U_EXPIRE-}" _U_PACKAGE="${_U_PACKAGE-}" _U_ENABLED="${_U_ENABLED-}" \
      _U_BW="${_U_BW-}" _U_PRIMARY="${_U_PRIMARY-}" \
      _U_ADVERTISE_HOST="${_U_ADVERTISE_HOST-}" _U_ADVERTISE_PORT="${_U_ADVERTISE_PORT-}" \
      _U_DEPLOYMENT_MODEL="${_U_DEPLOYMENT_MODEL-}" \
      python3 -c "$code"
  else
    MITA_USERS_STATE="$MITA_USERS_STATE" \
      _U_NAME="${_U_NAME-}" _U_PASS="${_U_PASS-}" _U_PORT="${_U_PORT-}" _U_PROTO="${_U_PROTO-}" \
      _U_QUOTA_MB="${_U_QUOTA_MB-}" _U_QUOTA_DAYS="${_U_QUOTA_DAYS-}" \
      _U_QUOTA_MODE="${_U_QUOTA_MODE-}" \
      _U_EXPIRE="${_U_EXPIRE-}" _U_PACKAGE="${_U_PACKAGE-}" _U_ENABLED="${_U_ENABLED-}" \
      _U_BW="${_U_BW-}" _U_PRIMARY="${_U_PRIMARY-}" \
      _U_ADVERTISE_HOST="${_U_ADVERTISE_HOST-}" _U_ADVERTISE_PORT="${_U_ADVERTISE_PORT-}" \
      _U_DEPLOYMENT_MODEL="${_U_DEPLOYMENT_MODEL-}" \
      python3 -c "$code"
  fi
}

normalize_quota_mode() {
  case "$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')" in
    calendar|cal|month|monthly|日历|月|自然月) printf 'calendar' ;;
    rolling|roll|滚动) printf 'rolling' ;;
    *) return 1 ;;
  esac
}

current_year_month() {
  date +%Y-%m 2>/dev/null || python3 -c 'import datetime;print(datetime.date.today().strftime("%Y-%m"))'
}

users_get_field() {
  # users_get_field <name> <field>
  local name="$1" field="$2"
  users_state_exists || return 1
  python3 -c '
import json, sys
name, field, path = sys.argv[1], sys.argv[2], sys.argv[3]
d = json.load(open(path))
for u in d.get("users") or []:
    if u.get("name") == name:
        v = u.get(field, "")
        if field == "enabled":
            print("1" if v is not False else "0")
        else:
            print(v if v is not None else "")
        sys.exit(0)
sys.exit(1)
' "$name" "$field" "$MITA_USERS_STATE" 2>/dev/null
}

users_name_exists() {
  local name="$1"
  [ -n "$(users_get_field "$name" name 2>/dev/null || true)" ]
}

users_all_ports() {
  users_state_exists || return 0
  # 协议经 argv 传入
  python3 -c '
import json, sys, os
d = json.load(open(sys.argv[1]))
proto = (sys.argv[2] if len(sys.argv) > 2 else "") or os.environ.get("PROTOCOL", "TCP")
for u in d.get("users") or []:
    p = u.get("port")
    if p is None:
        continue
    try:
        p = int(p)
    except Exception:
        continue
    print(p)
    if proto == "BOTH":
        print(p + 1)
' "$MITA_USERS_STATE" "${PROTOCOL:-TCP}" 2>/dev/null
}

port_is_listening() {
  local p="$1" proto="${2:-ANY}"
  case "$proto" in
    TCP|UDP) nb_port_is_listening "$proto" "$p" ;;
    *) nb_port_is_listening TCP "$p" || nb_port_is_listening UDP "$p" ;;
  esac
}

port_required_bindings() {
  local p
  p="$(normalize_uint "$1")" || return 1
  case "${PROTOCOL:-TCP}" in
    UDP) printf 'UDP|%s\n' "$p" ;;
    BOTH)
      printf 'TCP|%s\n' "$p"
      printf 'UDP|%s\n' "$((p + 1))"
      ;;
    *) printf 'TCP|%s\n' "$p" ;;
  esac
}

port_available_for_mode() {
  local p="$1" binding proto bind_port
  valid_port "$p" || return 1
  if [ "${PROTOCOL:-TCP}" = "BOTH" ] && [ "$p" -ge 65535 ]; then
    return 1
  fi
  while IFS='|' read -r proto bind_port; do
    [ -n "$proto" ] && [ -n "$bind_port" ] || continue
    nb_port_is_tail_base_reserved "$bind_port" && return 1
    port_is_listening "$bind_port" "$proto" && return 1
  done < <(port_required_bindings "$p")
  return 0
}

port_listener_details() {
  local p="$1" only_proto="${2:-}" bindings proto bind_port flags line
  command -v ss >/dev/null 2>&1 || return 0
  if [ -n "$only_proto" ]; then
    bindings="${only_proto}|${p}"
  else
    bindings="$(port_required_bindings "$p")"
  fi
  while IFS='|' read -r proto bind_port; do
    [ -n "$proto" ] && [ -n "$bind_port" ] || continue
    if nb_port_is_tail_base_reserved "$bind_port"; then
      nb_describe_port_conflict "$proto" "$bind_port"
      continue
    fi
    case "$proto" in
      TCP) flags="-Hlntp" ;;
      UDP) flags="-Hlnup" ;;
      *) flags="-Hlntup" ;;
    esac
    while IFS= read -r line; do
      [ -n "$line" ] && msg "  ${proto}/${bind_port}: ${line}"
    done < <(ss "$flags" 2>/dev/null | awk -v port="$bind_port" '
      {
        for (i = 1; i <= NF; i++) {
          if ($i ~ (":" port "$")) {
            print
            break
          }
        }
      }
    ')
  done <<<"$bindings"
}

select_available_port() {
  local selected=""
  if selected="$(derive_port_from_ip 2>/dev/null)" && [ -n "$selected" ]; then
    printf '%s' "$selected"
    return 0
  fi
  selected="$(random_available_port 2>/dev/null)" || return 1
  [ -n "$selected" ] || return 1
  printf '%s' "$selected"
}

ensure_install_port_available() {
  local old_port="$PORT" replacement=""
  port_available_for_mode "$PORT" && return 0
  warn "$(t "端口 ${PORT} 与当前 ${PROTOCOL} 监听需求冲突" \
    "Port ${PORT} conflicts with current ${PROTOCOL} listener requirements")"
  port_listener_details "$PORT"
  if [ "${PORT_AUTO_SELECTED:-0}" -eq 1 ]; then
    replacement="$(select_available_port)" || {
      die "$(t '未找到可用监听端口' 'No available listen port found')" || return 1
    }
    PORT="$replacement"
    t "自动端口 ${old_port} 已被占用，改用 ${PORT}" \
      "Auto-selected port ${old_port} became busy; switched to ${PORT}"
    return 0
  fi
  die "$(t "指定端口 ${PORT} 已被占用，请换一个端口" \
    "Requested port ${PORT} is already in use; choose another port")" || return 1
}

port_is_allocated() {
  local p="$1" used
  while IFS= read -r used; do
    [ -n "$used" ] || continue
    [ "$used" = "$p" ] && return 0
  done < <(users_all_ports)
  return 1
}

# 计算端口池起止（写入全局 _pool_lo _pool_hi）
users_port_pool_bounds() {
  if [ -n "${USER_PORT_POOL_START:-}" ] && [ -n "${USER_PORT_POOL_END:-}" ]; then
    _pool_lo="$USER_PORT_POOL_START"
    _pool_hi="$USER_PORT_POOL_END"
    return 0
  fi
  local base
  if base="$(derive_port_base 2>/dev/null)"; then
    _pool_lo=$((base + 1))
    _pool_hi=$((base + 99))
    [ "${PROTOCOL:-TCP}" = "BOTH" ] && _pool_hi=$((base + 98))
    return 0
  fi
  # 无 IP 尾号时：主端口附近 或 默认 20000-29999
  if [ -n "${PORT:-}" ] && valid_port "$PORT"; then
    _pool_lo=$((PORT + 2))
    _pool_hi=$((PORT + 200))
    [ "$_pool_hi" -gt 65535 ] && _pool_hi=65535
    [ "$_pool_lo" -lt 1025 ] && _pool_lo=1025
    return 0
  fi
  _pool_lo=20000
  _pool_hi=29999
}

allocate_user_port() {
  # 可选参数: 首选端口；成功打印端口
  local prefer="${1:-}" p step=1
  [ "${PROTOCOL:-TCP}" = "BOTH" ] && step=2
  if [ -n "$prefer" ]; then
    valid_port "$prefer" || { die "$(t "非法端口: $prefer" "Invalid port: $prefer")" || return 1; }
    prefer="$(normalize_uint "$prefer")"
    if [ "$PROTOCOL" = "BOTH" ]; then
      valid_port "$((prefer + 1))" || { die "$(t '双协议需要主端口 ≤65534' 'Dual protocol needs main port ≤65534')" || return 1; }
    fi
    if port_is_allocated "$prefer"; then
      warn "$(t "端口 ${prefer} 已被其它用户占用" "Port ${prefer} already allocated")"
      return 1
    fi
    if ! port_available_for_mode "$prefer"; then
      warn "$(t "端口 ${prefer} 不满足 ${PROTOCOL} 监听需求" \
        "Port ${prefer} is unavailable for ${PROTOCOL}")"
      port_listener_details "$prefer"
      return 1
    fi
    if [ "$PROTOCOL" = "BOTH" ] && port_is_allocated "$((prefer + 1))"; then
      warn "$(t "UDP 端口 $((prefer + 1)) 不可用" "UDP port $((prefer + 1)) unavailable")"
      return 1
    fi
    printf '%s' "$prefer"
    return 0
  fi
  users_port_pool_bounds
  p="$_pool_lo"
  while [ "$p" -le "$_pool_hi" ]; do
    if ! port_is_allocated "$p" && port_available_for_mode "$p"; then
      if [ "$PROTOCOL" != "BOTH" ] || ! port_is_allocated "$((p + 1))"; then
        printf '%s' "$p"
        return 0
      fi
    fi
    p=$((p + step))
  done
  die "$(t "端口池 ${_pool_lo}-${_pool_hi} 已满，请指定 --port 或扩大池" \
    "Port pool ${_pool_lo}-${_pool_hi} exhausted; pass --port or enlarge pool")" || return 1
}

users_migrate_from_primary() {
  # 将当前 USERNAME/PASSWORD/PORT 写入 users.json（若空）
  users_require_python
  [ -n "${USERNAME:-}" ] || return 0
  [ -n "${PORT:-}" ] || return 0
  admin_lock_acquire || return 1
  if users_state_exists; then
    local n
    n="$(users_count)"
    if [ "${n:-0}" -gt 0 ]; then
      admin_lock_release
      return 0
    fi
  fi
  run mkdir -p "$(dirname "$MITA_USERS_STATE")"
  if ! python3 -c '
import hashlib, json, sys, time
path, name, pwd, port, proto, advertise_host, advertise_port = sys.argv[1:8]
port = int(port)
advertise_port = int(advertise_port) if advertise_port else ""
instance_id = "u" + hashlib.sha256(("%s\0%s" % (name, port)).encode()).hexdigest()[:16]
d = {"version": 2, "protocol": proto, "users": [{
    "instance_id": instance_id,
    "name": name,
    "password": pwd,
    "port": port,
    "advertise_host": advertise_host,
    "advertise_port": advertise_port,
    "enabled": True,
    "quota_mb": 0,
    "quota_days": 0,
    "quota_mode": "rolling",
    "last_quota_reset": "",
    "expire_at": "",
    "package": "unlimited",
    "bandwidth_mbps": 0,
    "created_at": int(time.time()),
    "updated_at": int(time.time()),
}]}
json.dump(d, open(path, "w"), indent=2)
' "$MITA_USERS_STATE" "$USERNAME" "$PASSWORD" "$PORT" "${PROTOCOL:-TCP}" \
    "${ADVERTISE_HOST:-}" "${ADVERTISE_PORT:-}"
  then
    admin_lock_release
    return 1
  fi
  run chmod 0600 "$MITA_USERS_STATE" 2>/dev/null || true
  MULTI_USER_MODE=1
  install_users_scheduler 2>/dev/null || true
  admin_lock_release
}

users_sync_primary_globals() {
  # 用状态库第一个启用用户填充 USERNAME/PASSWORD/PORT（兼容旧摘要）
  users_state_exists || return 0
  local line rest
  line="$(python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
for u in d.get("users") or []:
    if u.get("enabled", True):
        print("%s\t%s\t%s" % (u.get("name") or "", u.get("password") or "", u.get("port") or ""))
        break
' "$MITA_USERS_STATE" 2>/dev/null)" || return 0
  [ -n "$line" ] || return 0
  USERNAME="${line%%$'\t'*}"
  rest="${line#*$'\t'}"
  PASSWORD="${rest%%$'\t'*}"
  PORT="${rest#*$'\t'}"
  ADVERTISE_HOST="$(users_get_field "$USERNAME" advertise_host 2>/dev/null || true)"
  ADVERTISE_PORT="$(users_get_field "$USERNAME" advertise_port 2>/dev/null || true)"
  MULTI_USER_MODE=1
}

users_ensure_loaded() {
  load_install_state
  if users_state_exists && [ "$(users_count)" -gt 0 ]; then
    MULTI_USER_MODE=1
    users_sync_primary_globals
    return 0
  fi
  # 尝试从 mita / 安装状态迁移
  if [ -n "${USERNAME:-}" ] && [ -n "${PORT:-}" ]; then
    users_migrate_from_primary
  fi
}

users_add() {
  local name="$1" password="$2" port_pref="${3:-}" port rc expire_at
  local advertise_host="${4:-}" advertise_port="${5:-}"
  local bw="${USER_BANDWIDTH_MBPS:-0}" qmode
  users_require_python || return 1
  [ -n "$name" ] || { die "$(t '用户名不能为空' 'Username required')" || return 1; }
  [ -n "$password" ] || password="$(random_token)"
  validate_proxy_credentials "$name" "$password" || return 1
  validate_advertise_endpoint_values "$advertise_host" "$advertise_port" "${PROTOCOL:-TCP}" || return 1
  [ -z "$advertise_port" ] || advertise_port="$(normalize_uint "$advertise_port")"
  valid_bandwidth_mbps "$bw" || {
    warn "$(t '带宽必须是 0-1000000 Mbps 的整数' \
      'Bandwidth must be an integer from 0 to 1000000 Mbps')"
    return 1
  }
  apply_user_package_defaults || return 1
  if ! valid_nonnegative_int32 "${USER_QUOTA_MB:-0}" \
     || ! valid_nonnegative_int32 "${USER_QUOTA_DAYS:-0}"; then
    warn "$(t '配额 MB/天数必须是 int32 范围内的非负整数' \
      'Quota MB/days must be non-negative int32 values')"
    return 1
  fi
  expire_at=""
  if [ -n "${USER_EXPIRE:-}" ]; then
    expire_at="$(parse_expire_date "$USER_EXPIRE")" || return 1
  fi
  load_install_state
  if ! users_state_exists || [ "$(users_count)" -eq 0 ]; then
    if [ -n "${USERNAME:-}" ] && [ -n "${PORT:-}" ] && [ -n "${PASSWORD:-}" ]; then
      users_migrate_from_primary
    else
      users_state_init_empty
    fi
  fi
  if users_name_exists "$name"; then
    warn "$(t "用户已存在: $name" "User already exists: $name")"
    return 1
  fi
  if ! port="$(allocate_user_port "$port_pref")"; then
    return 1
  fi
  users_backup_now pre-add >/dev/null 2>&1 || true
  qmode="$(normalize_quota_mode "${USER_QUOTA_MODE:-rolling}")" || {
    warn "$(t '配额模式仅支持 rolling 或 calendar' \
      'Quota mode must be rolling or calendar')"
    return 1
  }
  # 套餐默认 rolling；显式 calendar 保留
  [ -n "${USER_QUOTA_MODE:-}" ] || qmode="rolling"
  _U_NAME="$name" _U_PASS="$password" _U_PORT="$port" _U_PROTO="${PROTOCOL:-TCP}"
  _U_QUOTA_MB="${USER_QUOTA_MB:-0}" _U_QUOTA_DAYS="${USER_QUOTA_DAYS:-0}"
  _U_QUOTA_MODE="$qmode"
  _U_EXPIRE="${expire_at}" _U_PACKAGE="${USER_PACKAGE:-}" _U_BW="$bw"
  _U_ADVERTISE_HOST="$advertise_host" _U_ADVERTISE_PORT="$advertise_port"
  set +e
  users_py_locked '
import json, os, time, sys, datetime, secrets
path = os.environ["MITA_USERS_STATE"]
name = os.environ["_U_NAME"]
password = os.environ["_U_PASS"]
port = int(os.environ["_U_PORT"])
proto = os.environ.get("_U_PROTO", "TCP")
try:
    qmb = int(os.environ.get("_U_QUOTA_MB") or "0")
except Exception:
    qmb = 0
try:
    qdays = int(os.environ.get("_U_QUOTA_DAYS") or "0")
except Exception:
    qdays = 0
try:
    bw = int(os.environ.get("_U_BW") or "0")
except Exception:
    bw = 0
qmode = (os.environ.get("_U_QUOTA_MODE") or "rolling").strip().lower()
if qmode not in ("rolling", "calendar"):
    qmode = "rolling"
expire = (os.environ.get("_U_EXPIRE") or "").strip()
package = (os.environ.get("_U_PACKAGE") or "").strip() or ("custom" if qmb > 0 else "unlimited")
advertise_host = (os.environ.get("_U_ADVERTISE_HOST") or "").strip()
advertise_port = int(os.environ.get("_U_ADVERTISE_PORT")) if os.environ.get("_U_ADVERTISE_PORT") else ""
try:
    d = json.load(open(path))
except Exception:
    d = {"version": 1, "users": []}
users = d.setdefault("users", [])
for u in users:
    if u.get("name") == name:
        sys.exit(2)
    if int(u.get("port") or 0) == port:
        sys.exit(3)
ym = datetime.date.today().strftime("%Y-%m")
used_ids={str(u.get("instance_id") or "") for u in users}
while True:
    instance_id="u"+secrets.token_hex(8)
    if instance_id not in used_ids:
        break
users.append({
    "instance_id": instance_id,
    "name": name,
    "password": password,
    "port": port,
    "advertise_host": advertise_host,
    "advertise_port": advertise_port,
    "enabled": True,
    "quota_mb": qmb,
    "quota_days": (qdays if qdays > 0 else 30) if qmb > 0 else 0,
    "quota_mode": qmode,
    "last_quota_reset": ym if (qmb > 0 and qmode == "calendar") else "",
    "expire_at": expire,
    "package": package,
    "bandwidth_mbps": bw,
    "created_at": int(time.time()),
    "updated_at": int(time.time()),
})
d["protocol"] = proto
json.dump(d, open(path, "w"), indent=2)
'
  rc=$?
  set -e
  if [ "$rc" -eq 2 ]; then
    warn "$(t "用户已存在: $name" "User already exists: $name")"
    return 1
  fi
  if [ "$rc" -eq 3 ]; then
    warn "$(t "端口已被占用: $port" "Port already allocated: $port")"
    return 1
  fi
  if [ "$rc" -ne 0 ]; then
    warn "$(t "写入用户状态失败 ($rc)" "Failed to write user state ($rc)")"
    return 1
  fi
  MULTI_USER_MODE=1
  install_users_scheduler 2>/dev/null || true
  t "已添加用户 ${name}，专属端口 ${port}，套餐=${USER_PACKAGE:-unlimited} 配额=$(quota_label "${USER_QUOTA_MB:-0}" "${USER_QUOTA_DAYS:-0}") 限速=${bw}Mbps 到期=${expire_at:-永不过期}" \
    "Added ${name}; dedicated port ${port}, package=${USER_PACKAGE:-unlimited} quota=$(quota_label "${USER_QUOTA_MB:-0}" "${USER_QUOTA_DAYS:-0}") rate=${bw}Mbps expire=${expire_at:-never}" >&2
  printf '%s' "$port"
}

users_del() {
  local name="$1" freed rc
  users_require_python || return 1
  [ -n "$name" ] || { die "$(t '用户名不能为空' 'Username required')" || return 1; }
  users_state_exists || { die "$(t '无用户状态文件' 'No users state file')" || return 1; }
  users_name_exists "$name" || { die "$(t "用户不存在: $name" "User not found: $name")" || return 1; }
  freed="$(users_get_field "$name" port)"
  users_backup_now pre-del >/dev/null 2>&1 || true
  _U_NAME="$name"
  set +e
  users_py_locked '
import json, os, sys
path = os.environ["MITA_USERS_STATE"]
name = os.environ["_U_NAME"]
d = json.load(open(path))
before = len(d.get("users") or [])
d["users"] = [u for u in (d.get("users") or []) if u.get("name") != name]
if len(d["users"]) == before:
    sys.exit(2)
json.dump(d, open(path, "w"), indent=2)
'
  rc=$?
  set -e
  [ "$rc" -eq 0 ] || { die "$(t "删除失败: $name" "Delete failed: $name")" || return 1; }
  t "已删除用户 ${name}，释放端口 ${freed}" "Deleted user ${name}, freed port ${freed}" >&2
  printf '%s' "$freed"
}

# 从 users.json 生成 portBindings + users 片段路径（完整 server json 由 write_server_config_multi 写）
write_server_config_multi() {
  local cfg tp tp_section=""
  users_require_python
  users_state_exists || die "$(t '无多用户状态' 'No multi-user state')"
  ensure_traffic_seed
  tp="$(traffic_pattern_json '  ')"
  [ -n "$tp" ] && tp_section=",
${tp}"
  cfg="$(mktemp_file .json)"
  if ! MITA_USERS_STATE="$MITA_USERS_STATE" \
    _PROTO="${PROTOCOL:-TCP}" _MTU="${MTU:-1400}" \
    _CFG="$cfg" python3 - <<'PY'
import json, os, sys
path = os.environ["MITA_USERS_STATE"]
proto = os.environ.get("_PROTO", "TCP")
mtu = int(os.environ.get("_MTU", "1400"))
cfg_path = os.environ["_CFG"]
d = json.load(open(path))
users_out = []
bindings = []
seen = set()
for u in d.get("users") or []:
    if not u.get("enabled", True):
        continue
    name = u.get("name") or ""
    password = u.get("password") or ""
    try:
        port = int(u.get("port"))
    except Exception:
        continue
    if not name or not password:
        continue
    entry = {"name": name, "password": password}
    try:
        qmb = int(u.get("quota_mb") or 0)
    except Exception:
        qmb = 0
    try:
        qdays = int(u.get("quota_days") or 0)
    except Exception:
        qdays = 0
    qmode = (u.get("quota_mode") or "rolling").strip().lower()
    if qmb > 0:
        if qmode == "calendar":
            # 自然月：窗口取当月天数（28-31），月初由 user-scan 强制轮换
            import calendar, datetime
            t = datetime.date.today()
            qdays = calendar.monthrange(t.year, t.month)[1]
        elif qdays <= 0:
            qdays = 30
        entry["quotas"] = [{"days": qdays, "megabytes": qmb}]
    users_out.append(entry)
    if proto == "BOTH":
        pairs = [("TCP", port), ("UDP", port + 1)]
    else:
        pairs = [(proto, port)]
    for pr, p in pairs:
        key = (p, pr)
        if key in seen:
            continue
        seen.add(key)
        bindings.append({"port": p, "protocol": pr})
if not users_out:
    sys.stderr.write("no enabled users\n")
    sys.exit(1)
doc = {
    "portBindings": bindings,
    "users": users_out,
    "loggingLevel": "INFO",
    "mtu": mtu,
}
json.dump(doc, open(cfg_path, "w"), indent=2)
PY
  then
    die "$(t '生成多用户配置失败' 'Failed to build multi-user config')"
  fi
  # 追加 trafficPattern（若有）：与单用户路径一致的 JSON 片段
  if [ -n "$tp_section" ]; then
    if ! _CFG="$cfg" _TP="$tp_section" python3 - <<'PY' 2>/dev/null
import json, os, re
cfg = os.environ["_CFG"]
tp = os.environ.get("_TP", "").strip()
if not tp:
    raise SystemExit(0)
if tp.startswith(","):
    tp = tp[1:].strip()
# tp like: "trafficPattern": { ... }
m = re.match(r'"trafficPattern"\s*:\s*(\{.*\})\s*$', tp, re.S)
if not m:
    raise SystemExit(0)
doc = json.load(open(cfg))
doc["trafficPattern"] = json.loads(m.group(1))
json.dump(doc, open(cfg, "w"), indent=2)
PY
    then
      rm -f "$cfg"
      die "$(t '写入 trafficPattern 失败，已中止以避免静默丢失流量模式' \
        'Failed to write trafficPattern; aborted instead of silently dropping the traffic mode')"
    fi
  fi
  printf '%s' "$cfg"
}

users_enabled_names_from_state() {
  users_require_python || return 1
  users_state_exists || return 1
  python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
names = {
    str(u.get("name") or "")
    for u in (d.get("users") or [])
    if u.get("enabled", True) and str(u.get("name") or "")
}
print("\n".join(sorted(names)))
' "$MITA_USERS_STATE" 2>/dev/null
}

mita_actual_user_names() {
  local bin desc
  bin="$(mita_bin)" || return 1
  [ -x "$bin" ] || return 1
  desc="$("$bin" describe config 2>/dev/null)" || return 1
  [ -n "$desc" ] || return 1
  printf '%s' "$desc" | python3 -c '
import json, sys
d = json.load(sys.stdin)
names = {
    str(u.get("name") or "")
    for u in (d.get("users") or [])
    if str(u.get("name") or "")
}
print("\n".join(sorted(names)))
' 2>/dev/null
}

mita_delete_user_exact() {
  local name="$1" bin
  [ -n "$name" ] || return 1
  bin="$(mita_bin)" || return 1
  if [ "${DRY_RUN:-0}" -eq 1 ]; then
    msg "[dry-run] $(printf '%q ' "$bin" delete user "$name")"
    return 0
  fi
  "$bin" delete user "$name" >/dev/null 2>&1
}

# mita apply config 会合并用户而不是替换用户。这里把脚本管理的用户集合
# 显式同步成期望集合，确保删除、停用、到期和事务回滚真正撤销旧凭据。
mita_sync_user_names() {
  local desired_raw="${1:-}" desired actual stale after
  users_require_python || return 1
  desired="$(printf '%s\n' "$desired_raw" | sed '/^[[:space:]]*$/d' | LC_ALL=C sort -u)"
  [ -n "$desired" ] || {
    warn "$(t '拒绝同步空用户集合' 'Refusing to synchronize an empty user set')"
    return 1
  }
  if ! actual="$(mita_actual_user_names)"; then
    warn "$(t '无法读取 mita 实际用户集合，未执行删除' \
      'Cannot read the actual mita user set; no deletion was attempted')"
    return 1
  fi
  stale="$(DESIRED="$desired" ACTUAL="$actual" python3 -c '
import os
desired = set(filter(None, os.environ.get("DESIRED", "").splitlines()))
actual = set(filter(None, os.environ.get("ACTUAL", "").splitlines()))
print("\n".join(sorted(actual - desired)))
' 2>/dev/null)" || return 1
  if [ -n "$stale" ]; then
    local name
    while IFS= read -r name; do
      [ -n "$name" ] || continue
      if ! mita_delete_user_exact "$name"; then
        warn "$(t "无法从 mita 删除旧用户: $name" \
          "Failed to delete stale user from mita: $name")"
        return 1
      fi
      users_log "mita user revoked: $name"
    done <<< "$stale"
  fi
  if [ "${DRY_RUN:-0}" -eq 1 ]; then
    return 0
  fi
  if ! after="$(mita_actual_user_names)"; then
    warn "$(t '删除后无法重新读取 mita 用户集合' \
      'Cannot read the mita user set after synchronization')"
    return 1
  fi
  if ! DESIRED="$desired" ACTUAL="$after" python3 -c '
import os, sys
desired = set(filter(None, os.environ.get("DESIRED", "").splitlines()))
actual = set(filter(None, os.environ.get("ACTUAL", "").splitlines()))
sys.exit(0 if actual == desired else 1)
' 2>/dev/null; then
    warn "$(t 'mita 实际用户与 users.json 启用用户仍不一致' \
      'The actual mita users still differ from enabled users in users.json')"
    return 1
  fi
  return 0
}

mita_sync_users_to_state() {
  local desired
  desired="$(users_enabled_names_from_state)" || return 1
  mita_sync_user_names "$desired"
}

mita_sync_single_user() {
  local name="$1"
  [ -n "$name" ] || return 1
  mita_sync_user_names "$name"
}

multi_user_port_protocol_pairs() {
  # 输出 proto|port 每行（用于防火墙）
  users_state_exists || return 0
  python3 -c '
import json, sys
path, proto = sys.argv[1], sys.argv[2]
d = json.load(open(path))
for u in d.get("users") or []:
    if not u.get("enabled", True):
        continue
    port = int(u.get("port"))
    if proto == "BOTH":
        print(f"TCP|{port}")
        print(f"UDP|{port+1}")
    else:
        print(f"{proto}|{port}")
' "$MITA_USERS_STATE" "${PROTOCOL:-TCP}" 2>/dev/null
}

apply_users_config() {
  # 每个启用用户对应一个独立 mita 实例；端口、认证、配额 metrics 均为专属资源。
  local snapshot="${1:-}" rollback_reapply="${2:-1}" auto_host=""
  STAGE="应用多用户配置"
  admin_lock_acquire || return 1
  auto_host="$(public_ip 2>/dev/null || true)"
  if ! users_validate_state_file "$MITA_USERS_STATE" "${PROTOCOL:-TCP}" "$auto_host"; then
    users_tx_rollback "$snapshot" 0
    admin_lock_release
    warn "$(t 'users.json 校验失败（字段、监听端口或客户端展示入口冲突），未应用到专属实例' \
      'users.json validation failed (fields, listen ports, or client display endpoints conflict); dedicated instances were not changed')"
    return 1
  fi
  if [ "$(users_count)" -eq 0 ]; then
    users_tx_rollback "$snapshot" 0
    admin_lock_release
    warn "$(t '至少保留一个用户' 'Keep at least one user')"
    return 1
  fi
  if ! ensure_isolated_deployment "$rollback_reapply"; then
    users_tx_rollback "$snapshot" "$rollback_reapply"
    admin_lock_release
    return 1
  fi
  if ! apply_tc_limits; then
    users_tx_rollback "$snapshot" "$rollback_reapply"
    admin_lock_release
    return 1
  fi
  harden_mita_permissions 2>/dev/null || true
  admin_lock_release
  return 0
}

# 更新用户字段（不改 name/port/password 除非传入）
users_update_fields() {
  local name="$1"
  users_require_python || return 1
  users_name_exists "$name" || { warn "$(t "用户不存在: $name" "User not found: $name")"; return 1; }
  users_backup_now pre-update >/dev/null 2>&1 || true
  _U_NAME="$name"
  _U_QUOTA_MB="${USER_QUOTA_MB-}"
  _U_QUOTA_DAYS="${USER_QUOTA_DAYS-}"
  _U_QUOTA_MODE="${USER_QUOTA_MODE-}"
  _U_EXPIRE="${USER_EXPIRE-}"
  _U_PACKAGE="${USER_PACKAGE-}"
  _U_ENABLED="${_U_ENABLED-}"
  _U_PASS="${_U_PASS-}"
  _U_BW="${USER_BANDWIDTH_MBPS-}"
  set +e
  users_py_locked '
import json, os, time, sys, datetime
path = os.environ["MITA_USERS_STATE"]
name = os.environ["_U_NAME"]
d = json.load(open(path))
found = None
for u in d.get("users") or []:
    if u.get("name") == name:
        found = u
        break
if found is None:
    sys.exit(2)
# optional fields: empty string means skip; special __CLEAR__ for expire
qm = os.environ.get("_U_QUOTA_MB")
if qm is not None and qm != "":
    try:
        found["quota_mb"] = int(qm)
    except Exception:
        pass
qd = os.environ.get("_U_QUOTA_DAYS")
if qd is not None and qd != "":
    try:
        found["quota_days"] = int(qd)
    except Exception:
        pass
if found.get("quota_mb", 0) <= 0:
    found["quota_mb"] = 0
    found["quota_days"] = 0
qmode = os.environ.get("_U_QUOTA_MODE")
if qmode is not None and qmode != "":
    qmode = qmode.strip().lower()
    if qmode in ("calendar", "cal", "month", "monthly"):
        found["quota_mode"] = "calendar"
        if not found.get("last_quota_reset"):
            found["last_quota_reset"] = datetime.date.today().strftime("%Y-%m")
    else:
        found["quota_mode"] = "rolling"
ex = os.environ.get("_U_EXPIRE")
if ex is not None and ex != "":
    if ex in ("0", "never", "none", "-", "__CLEAR__"):
        found["expire_at"] = ""
    else:
        found["expire_at"] = ex
pkg = os.environ.get("_U_PACKAGE")
if pkg is not None and pkg != "":
    found["package"] = pkg
en = os.environ.get("_U_ENABLED")
if en is not None and en != "":
    found["enabled"] = en in ("1", "true", "True", "yes")
pw = os.environ.get("_U_PASS")
if pw is not None and pw != "":
    found["password"] = pw
bw = os.environ.get("_U_BW")
if bw is not None and bw != "":
    try:
        found["bandwidth_mbps"] = max(0, int(bw))
    except Exception:
        pass
found["updated_at"] = int(time.time())
json.dump(d, open(path, "w"), indent=2)
'
  local rc=$?
  set -e
  [ "$rc" -eq 0 ] || return 1
  return 0
}

users_set_advertise_endpoint() {
  local name="$1" host="${2:-}" port="${3:-}"
  users_name_exists "$name" || return 1
  validate_advertise_endpoint_values "$host" "$port" "${PROTOCOL:-TCP}" || return 1
  [ -z "$port" ] || port="$(normalize_uint "$port")"
  _U_NAME="$name" _U_ADVERTISE_HOST="$host" _U_ADVERTISE_PORT="$port"
  users_py_locked '
import json, os, sys, time
path=os.environ["MITA_USERS_STATE"]
name=os.environ.get("_U_NAME") or ""
host=os.environ.get("_U_ADVERTISE_HOST") or ""
port=os.environ.get("_U_ADVERTISE_PORT") or ""
d=json.load(open(path))
for u in d.get("users") or []:
    if u.get("name") == name:
        u["advertise_host"] = host
        u["advertise_port"] = int(port) if port else ""
        u["updated_at"] = int(time.time())
        json.dump(d, open(path, "w"), indent=2)
        raise SystemExit(0)
raise SystemExit(2)
'
}

# ---------- 专属实例按端口限速（仅管理本脚本拥有的 tc filter） ----------

tc_available() {
  command -v tc >/dev/null 2>&1 || return 1
  tc qdisc show >/dev/null 2>&1 || return 1
  return 0
}

tc_default_iface() {
  local dev=""
  if [ -n "${TC_IFACE:-}" ]; then
    printf '%s' "$TC_IFACE"
    return 0
  fi
  if command -v ip >/dev/null 2>&1; then
    dev="$(ip route 2>/dev/null | awk '/^default/{print $5; exit}')"
    [ -n "$dev" ] || dev="$(ip -br link 2>/dev/null | awk '$1!="lo"{print $1; exit}' | cut -d@ -f1)"
  fi
  printf '%s' "$dev"
}

tc_clear_owned_filters() {
  local state="${1:-$TC_OWNED_STATE}" dev="" dir proto pref _rest
  [ -f "$state" ] || return 0
  dev="$(awk -F'|' '$1=="iface"{print $2; exit}' "$state" 2>/dev/null || true)"
  [ -n "$dev" ] || { rm -f "$state"; return 0; }
  while IFS='|' read -r dir proto pref _rest; do
    [ "$dir" = "ingress" ] || [ "$dir" = "egress" ] || continue
    [[ "$pref" =~ ^[0-9]+$ ]] || continue
    [ "$pref" -ge "$TC_PREF_MIN" ] && [ "$pref" -le "$TC_PREF_MAX" ] || continue
    case "$proto" in ip|ipv6) ;; *) continue ;; esac
    tc filter del dev "$dev" "$dir" protocol "$proto" pref "$pref" 2>/dev/null || true
  done <"$state"
  rm -f "$state"
}

tc_restore_manifest() {
  local state="$1" dev="" dir family pref l4 field port bw burst
  [ -f "$state" ] || return 0
  dev="$(awk -F'|' '$1=="iface"{print $2; exit}' "$state" 2>/dev/null || true)"
  [ -n "$dev" ] || return 1
  while IFS='|' read -r dir family pref l4 field port bw; do
    [ "$dir" = ingress ] || [ "$dir" = egress ] || continue
    [[ "$pref" =~ ^[0-9]+$ && "$port" =~ ^[0-9]+$ && "$bw" =~ ^[0-9]+$ ]] || continue
    burst=$((bw * 128))
    [ "$burst" -lt 64 ] && burst=64
    [ "$burst" -gt 4096 ] && burst=4096
    tc filter add dev "$dev" "$dir" protocol "$family" pref "$pref" flower \
      ip_proto "$l4" "$field" "$port" \
      action police rate "${bw}mbit" burst "${burst}k" conform-exceed drop \
      >/dev/null 2>&1 || return 1
  done <"$state"
}

tc_rollback_filter_update() {
  local partial="$1" previous="${2:-}"
  tc_clear_owned_filters "$partial"
  if [ -n "$previous" ] && [ -f "$previous" ]; then
    tc_restore_manifest "$previous" || true
    mv -f "$previous" "$TC_OWNED_STATE"
  fi
}

tc_add_owned_filter() {
  local state="$1" dev="$2" dir="$3" family="$4" pref="$5"
  local l4="$6" field="$7" port="$8" bw="$9" burst
  burst=$((bw * 128))
  [ "$burst" -lt 64 ] && burst=64
  [ "$burst" -gt 4096 ] && burst=4096
  if ! tc filter add dev "$dev" "$dir" protocol "$family" pref "$pref" flower \
      ip_proto "$l4" "$field" "$port" \
      action police rate "${bw}mbit" burst "${burst}k" conform-exceed drop; then
    return 1
  fi
  printf '%s|%s|%s|%s|%s|%s|%s\n' \
    "$dir" "$family" "$pref" "$l4" "$field" "$port" "$bw" >>"$state"
}

apply_tc_limits() {
  local has_limit=0 dev tmp previous="" pref="$TC_PREF_MIN" name port bw l4 p family dir field
  users_state_exists || {
    tc_clear_owned_filters
    return 0
  }
  has_limit="$(python3 -c '
import json,sys
d=json.load(open(sys.argv[1]))
print(1 if any(u.get("enabled",True) and int(u.get("bandwidth_mbps") or 0)>0 for u in (d.get("users") or [])) else 0)
' "$MITA_USERS_STATE" 2>/dev/null || echo 0)"
  if [ "$has_limit" != "1" ]; then
    tc_clear_owned_filters
    return 0
  fi
  users_isolated_mode || {
    warn "$(t '拒绝应用限速：当前尚未迁移到用户专属实例模型' \
      'Refusing rate limits: deployment has not migrated to dedicated user instances')"
    return 1
  }
  tc_available || {
    warn "$(t '存在限速套餐但 tc/iproute2 不可用' \
      'Rate-limited packages exist but tc/iproute2 is unavailable')"
    return 1
  }
  dev="$(tc_default_iface)"
  [ -n "$dev" ] || {
    warn "$(t '存在限速套餐但无法检测默认网卡；可设置 TC_IFACE' \
      'Rate-limited packages exist but no default NIC was found; set TC_IFACE')"
    return 1
  }
  if ! tc qdisc show dev "$dev" 2>/dev/null | grep -qw clsact; then
    if ! tc qdisc add dev "$dev" clsact 2>/dev/null; then
      warn "$(t "无法安全添加 clsact 到 ${dev}；未删除或替换现有 qdisc" \
        "Cannot safely add clsact to ${dev}; existing qdiscs were not deleted or replaced")"
      return 1
    fi
  fi
  if [ -f "$TC_OWNED_STATE" ]; then
    previous="$(mktemp_file .tc-previous)" || return 1
    cp -f "$TC_OWNED_STATE" "$previous" || { rm -f "$previous"; return 1; }
  fi
  tc_clear_owned_filters
  tmp="$(mktemp_file .tc-filters)" || return 1
  printf 'iface|%s\n' "$dev" >"$tmp"
  while IFS=$'\t' read -r name port bw; do
    [ -n "$name" ] && [ -n "$port" ] && [ "${bw:-0}" -gt 0 ] || continue
    for l4 in $( [ "${PROTOCOL:-TCP}" = "UDP" ] && echo udp || echo tcp ); do
      p="$port"
      for family in ip ipv6; do
        for dir in ingress egress; do
          [ "$dir" = ingress ] && field=dst_port || field=src_port
          [ "$pref" -le "$TC_PREF_MAX" ] || {
            warn "$(t '专属限速规则过多，超出脚本保留的 tc 优先级范围' \
              'Too many dedicated rate rules for the reserved tc preference range')"
            tc_rollback_filter_update "$tmp" "$previous"
            return 1
          }
          if ! tc_add_owned_filter "$tmp" "$dev" "$dir" "$family" "$pref" \
              "$l4" "$field" "$p" "$bw"; then
            warn "$(t "应用 ${name} 的 tc 限速失败；已撤销本次脚本规则" \
              "Failed to apply tc limit for ${name}; this run's owned filters were rolled back")"
            tc_rollback_filter_update "$tmp" "$previous"
            return 1
          fi
          pref=$((pref + 1))
        done
      done
    done
    if [ "${PROTOCOL:-TCP}" = "BOTH" ]; then
      l4=udp
      p=$((port + 1))
      for family in ip ipv6; do
        for dir in ingress egress; do
          [ "$dir" = ingress ] && field=dst_port || field=src_port
          if ! tc_add_owned_filter "$tmp" "$dev" "$dir" "$family" "$pref" \
              "$l4" "$field" "$p" "$bw"; then
            tc_rollback_filter_update "$tmp" "$previous"
            return 1
          fi
          pref=$((pref + 1))
        done
      done
    fi
  done < <(python3 -c '
import json,sys
d=json.load(open(sys.argv[1]))
for u in d.get("users") or []:
    if u.get("enabled",True) and int(u.get("bandwidth_mbps") or 0)>0:
        print("%s\t%s\t%s" % (u.get("name") or "", int(u.get("port") or 0), int(u.get("bandwidth_mbps") or 0)))
' "$MITA_USERS_STATE")
  mv -f "$tmp" "$TC_OWNED_STATE"
  chmod 0600 "$TC_OWNED_STATE" 2>/dev/null || true
  [ -z "$previous" ] || rm -f "$previous"
  users_log "tc: applied dedicated per-user port filters on $dev"
}

tc_rate_status() {
  local dev
  dev="$(tc_default_iface)"
  msg ""
  t '【带宽状态】专属实例按端口限速；仅展示/维护本脚本拥有的 filter' \
    '[Bandwidth status] dedicated-instance port limits; only script-owned filters are managed'
  if ! tc_available; then
    warn "$(t 'tc 不可用' 'tc unavailable')"
    return 1
  fi
  if [ -z "$dev" ]; then
    warn "$(t '未检测到网卡' 'No NIC detected')"
    return 1
  fi
  msg "--- qdisc ---"
  tc qdisc show dev "$dev" 2>/dev/null || true
  msg "--- egress filter ---"
  tc filter show dev "$dev" egress 2>/dev/null | grep -E 'pref 42[0-9]{3}|police' | head -n 60 || true
  msg "--- ingress filter ---"
  tc filter show dev "$dev" ingress 2>/dev/null | grep -E 'pref 42[0-9]{3}|police' | head -n 60 || true
  msg ""
  t '【套餐带宽】0 表示不限速' '[Package bandwidth] 0 means unlimited'
  if users_state_exists; then
    python3 -c '
import json,sys
d=json.load(open(sys.argv[1]))
print("%-16s %-8s %-8s %s" % ("USER","PORT","MBPS","STATUS"))
for u in d.get("users") or []:
    bw=int(u.get("bandwidth_mbps") or 0)
    st="on" if u.get("enabled",True) else "off"
    print("%-16s %-8s %-8s %s" % (u.get("name") or "", u.get("port") or "", bw if bw>0 else "unlim", st))
' "$MITA_USERS_STATE"
  fi
}

users_set_enabled() {
  local name="$1" en="$2"
  _U_ENABLED="$en"
  USER_QUOTA_MB="" USER_QUOTA_DAYS="" USER_EXPIRE="" USER_PACKAGE="" USER_BANDWIDTH_MBPS=""
  if ! users_update_fields "$name"; then
    unset _U_ENABLED
    return 1
  fi
  unset _U_ENABLED
}

# 扫描到期：expire_at <= today 且 enabled → 停用；stdout 仅输出被停用的用户名
users_scan_expired() {
  users_require_python || return 1
  users_state_exists || return 0
  local today changed tx old_pairs new_pairs close_pairs
  admin_lock_acquire || return 1
  tx="$(users_tx_snapshot)" || { admin_lock_release; return 1; }
  old_pairs="$(multi_user_port_protocol_pairs)"
  today="$(today_ymd)"
  if ! changed="$(USERS_LOG_QUIET=1 python3 -c '
import json, sys, time
path, today = sys.argv[1], sys.argv[2]
d = json.load(open(path))
changed = []
for u in d.get("users") or []:
    exp = (u.get("expire_at") or "").strip()
    if not exp:
        continue
    if not u.get("enabled", True):
        continue
    if exp <= today:
        u["enabled"] = False
        u["updated_at"] = int(time.time())
        changed.append(u.get("name") or "")
if changed:
    json.dump(d, open(path, "w"), indent=2)
print("\n".join(changed))
' "$MITA_USERS_STATE" "$today" 2>/dev/null)"; then
    users_tx_rollback "$tx" 0
    admin_lock_release
    return 1
  fi
  if [ -z "$changed" ]; then
    users_tx_commit "$tx"
    admin_lock_release
    return 0
  fi
  local n
  while IFS= read -r n; do
    [ -n "$n" ] || continue
    USERS_LOG_QUIET=1 users_log "expired disable: $n (expire_at<=$today)"
  done <<< "$changed"
  if mita_installed 2>/dev/null; then
    load_install_state
    MULTI_USER_MODE=1
    if ! apply_users_config "$tx" >/dev/null 2>&1; then
      USERS_LOG_QUIET=1 users_log "apply after expire scan failed; users state rolled back"
      admin_lock_release
      return 1
    fi
    new_pairs="$(multi_user_port_protocol_pairs)"
    close_pairs="$(comm -23 \
      <(printf '%s\n' "$old_pairs" | sed '/^[[:space:]]*$/d' | LC_ALL=C sort -u) \
      <(printf '%s\n' "$new_pairs" | sed '/^[[:space:]]*$/d' | LC_ALL=C sort -u))"
    [ -z "$close_pairs" ] || close_firewall_for_bindings "$close_pairs"
    users_sync_primary_globals
    if ! save_install_state; then
      users_tx_rollback "$tx" 1
      open_firewall_for_pairs "$old_pairs"
      admin_lock_release
      return 1
    fi
  fi
  users_tx_commit "$tx"
  admin_lock_release
  printf '%s\n' "$changed"
}

# 日历月配额重置：quota_mode=calendar 且 last_quota_reset != 当月。
# isolated-v2 为每个用户提供独立 metrics.pb，因此只重置待处理用户。
_calendar_mark_pending() {
  # stdout: 待重置用户名列表；不写 last_quota_reset
  python3 -c '
import json, sys, time, datetime, calendar
path, ym = sys.argv[1], sys.argv[2]
d = json.load(open(path))
reset = []
today = datetime.date.today()
mdays = calendar.monthrange(today.year, today.month)[1]
for u in d.get("users") or []:
    if not u.get("enabled", True):
        continue
    try:
        qmb = int(u.get("quota_mb") or 0)
    except Exception:
        qmb = 0
    if qmb <= 0:
        continue
    if (u.get("quota_mode") or "rolling").strip().lower() != "calendar":
        continue
    if (u.get("last_quota_reset") or "").strip() == ym:
        continue
    u["quota_days"] = mdays
    u["updated_at"] = int(time.time())
    u["_reset_pending"] = True
    reset.append(u.get("name") or "")
if reset:
    json.dump(d, open(path, "w"), indent=2)
print("\n".join(reset))
' "$MITA_USERS_STATE" "$1" 2>/dev/null
}

_calendar_commit_reset() {
  # 成功后：仅对 _reset_pending 用户写 last_quota_reset
  local ym="$1"
  python3 -c '
import json, sys, time
path, ym = sys.argv[1], sys.argv[2]
d = json.load(open(path))
for u in d.get("users") or []:
    pending = u.pop("_reset_pending", False)
    if pending:
        u["last_quota_reset"] = ym
    u["updated_at"] = int(time.time())
json.dump(d, open(path, "w"), indent=2)
' "$MITA_USERS_STATE" "$ym" 2>/dev/null
}

users_scan_calendar_quota_reset() {
  users_require_python || return 1
  users_state_exists || return 0
  if [ "${DRY_RUN:-0}" -eq 1 ]; then
    msg "[dry-run] calendar quota scan (no users.json or metrics changes)"
    return 0
  fi
  local ym reset_list method tx
  admin_lock_acquire || return 1
  tx="$(users_tx_snapshot)" || { admin_lock_release; return 1; }
  ym="$(current_year_month)"
  method="$(printf '%s' "${QUOTA_RESET_METHOD:-metrics}" | tr '[:upper:]' '[:lower:]')"
  if ! reset_list="$(_calendar_mark_pending "$ym")"; then
    users_tx_rollback "$tx" 0
    admin_lock_release
    return 1
  fi
  if [ -z "$reset_list" ]; then
    users_tx_commit "$tx"
    admin_lock_release
    return 0
  fi
  local n
  while IFS= read -r n; do
    [ -n "$n" ] || continue
    USERS_LOG_QUIET=1 users_log "calendar quota reset pending: $n month=$ym method=$method"
  done <<< "$reset_list"

  if ! mita_installed 2>/dev/null; then
    users_tx_rollback "$tx" 0
    admin_lock_release
    warn "$(t 'mita 未安装，无法清空真实指标；未记录 calendar 重置成功' \
      'mita is not installed, so real metrics cannot be cleared; calendar reset was not marked successful')"
    return 1
  fi

  if [ "$method" != "metrics" ]; then
    users_tx_rollback "$tx" 0
    admin_lock_release
    warn "$(t "QUOTA_RESET_METHOD=${method} 已禁用：该方法不会清空按用户名累计的指标。请使用 metrics。" \
      "QUOTA_RESET_METHOD=${method} is disabled because it does not clear username-keyed metrics. Use metrics.")"
    return 1
  fi

  # isolated-v2 中每个用户拥有独立 metrics.pb，可只重置到期的 calendar 用户，
  # 不再要求所有有限配额账号在同一时间清零。
  load_install_state
  MULTI_USER_MODE=1
  if ! apply_users_config "$tx" >/dev/null 2>&1; then
    USERS_LOG_QUIET=1 users_log "calendar dedicated instance apply failed"
    admin_lock_release
    return 1
  fi
  users_isolated_mode || {
    users_tx_rollback "$tx" 1
    admin_lock_release
    warn "$(t 'calendar 重置要求 isolated-v2，但迁移后模型未生效' \
      'Calendar reset requires isolated-v2, but migration did not take effect')"
    return 1
  }

  local backup_dir id metric reset_failed=0
  backup_dir="$(mktemp_dir)"
  chmod 0700 "$backup_dir" 2>/dev/null || true
  while IFS= read -r n; do
    [ -n "$n" ] || continue
    id="$(users_get_field "$n" instance_id 2>/dev/null || true)"
    instance_valid_id "$id" || { reset_failed=1; break; }
    metric="$(instance_metrics_file "$id")"
    if ! instance_daemon_stop "$id" 0; then
      reset_failed=1
      break
    fi
    if [ -f "$metric" ]; then
      cp -f "$metric" "${backup_dir}/${id}.pb" || { reset_failed=1; break; }
    else
      : >"${backup_dir}/${id}.absent"
    fi
    if ! rm -f "$metric" || ! instance_start_proxy "$id"; then
      reset_failed=1
      break
    fi
    USERS_LOG_QUIET=1 users_log "calendar reset cleared dedicated metrics: user=$n instance=$id"
  done <<<"$reset_list"

  if [ "$reset_failed" -eq 0 ] && _calendar_commit_reset "$ym"; then
    rm -rf "$backup_dir"
    users_tx_commit "$tx"
    admin_lock_release
    printf '%s\n' "$reset_list"
    return 0
  fi

  while IFS= read -r n; do
    [ -n "$n" ] || continue
    id="$(users_get_field "$n" instance_id 2>/dev/null || true)"
    instance_valid_id "$id" || continue
    metric="$(instance_metrics_file "$id")"
    instance_daemon_stop "$id" 0 || true
    if [ -f "${backup_dir}/${id}.pb" ]; then
      cp -f "${backup_dir}/${id}.pb" "$metric" 2>/dev/null || true
      chown mita:mita "$metric" 2>/dev/null || true
      chmod 0600 "$metric" 2>/dev/null || true
    elif [ -f "${backup_dir}/${id}.absent" ]; then
      rm -f "$metric" 2>/dev/null || true
    fi
  done <<<"$reset_list"
  rm -rf "$backup_dir"
  users_tx_rollback "$tx" 1
  USERS_LOG_QUIET=1 users_log "calendar dedicated metrics reset failed; state and metrics rolled back"
  admin_lock_release
  return 1
}

install_users_scheduler() {
  # systemd timer 优先，否则 cron.d
  [ "${DRY_RUN:-0}" -eq 1 ] && return 0
  local script_path
  script_path="${INSTALL_SCRIPT_PATH}"
  [ -x "$script_path" ] || script_path="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || printf '%s' "${BASH_SOURCE[0]}")"
  [ -n "$script_path" ] || return 0

  if command -v systemctl >/dev/null 2>&1 && [ -d /etc/systemd/system ]; then
    cat >"$MITA_USERS_SERVICE" <<EOF
[Unit]
Description=mita users expire and calendar quota scan
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=${script_path} user-scan
Nice=10
EOF
    cat >"$MITA_USERS_TIMER" <<EOF
[Unit]
Description=Run mita users scan every 15 minutes

[Timer]
OnBootSec=2min
OnUnitActiveSec=15min
AccuracySec=1min
Unit=mita-users-scan.service

[Install]
WantedBy=timers.target
EOF
    systemctl daemon-reload 2>/dev/null || true
    systemctl enable --now mita-users-scan.timer 2>/dev/null || true
    # 清理 v1.9.5 及更早版本创建的、已证明不可作为按用户限速的恢复服务。
    systemctl disable --now mita-tc-restore.service 2>/dev/null || true
    rm -f /etc/systemd/system/mita-tc-restore.service 2>/dev/null || true
    systemctl daemon-reload 2>/dev/null || true
    install_logrotate_config 2>/dev/null || true
    harden_mita_permissions 2>/dev/null || true
    users_log "scheduler: systemd expiry/quota timer"
    return 0
  fi

  if [ -d /etc/cron.d ]; then
    cat >"$MITA_USERS_CRON" <<EOF
# mita multi-user expire / quota scan (every 15 min)
*/15 * * * * root ${script_path} user-scan >>${MITA_USERS_LOG} 2>&1
EOF
    chmod 0644 "$MITA_USERS_CRON" 2>/dev/null || true
    install_logrotate_config 2>/dev/null || true
    harden_mita_permissions 2>/dev/null || true
    users_log "scheduler: cron ${MITA_USERS_CRON}"
    return 0
  fi
  # OpenRC / 无 cron：写入 hint
  install_logrotate_config 2>/dev/null || true
  warn "$(t '未找到 systemd timer 或 /etc/cron.d，请手动定期执行: install-mita user-scan' \
    'No systemd timer or /etc/cron.d; run: install-mita user-scan')"
}

remove_users_scheduler() {
  if [ -f "$MITA_USERS_TIMER" ] || [ -f "$MITA_USERS_SERVICE" ]; then
    systemctl disable --now mita-users-scan.timer 2>/dev/null || true
    systemctl disable --now mita-tc-restore.service 2>/dev/null || true
    rm -f "$MITA_USERS_TIMER" "$MITA_USERS_SERVICE" /etc/systemd/system/mita-tc-restore.service 2>/dev/null || true
    systemctl daemon-reload 2>/dev/null || true
  fi
  rm -f "$MITA_USERS_CRON" 2>/dev/null || true
}

# ---------- 阶段4：备份 / 恢复 / 导出导入 / 管理锁 ----------

# 破坏性变更前备份 users.json；成功打印备份路径
users_backup_now() {
  local tag="${1:-auto}" dest ts
  users_state_exists || return 1
  if [ "${DRY_RUN:-0}" -eq 1 ]; then
    msg "[dry-run] backup users state: $MITA_USERS_STATE"
    return 0
  fi
  run mkdir -p "$MITA_USERS_BACKUP_DIR"
  ts="$(date +%Y%m%d_%H%M%S 2>/dev/null || echo unknown)_$$_${RANDOM}"
  dest="${MITA_USERS_BACKUP_DIR}/users_${tag}_${ts}.json"
  if command -v install >/dev/null 2>&1; then
    run install -m 0600 "$MITA_USERS_STATE" "$dest"
  else
    run cp -f "$MITA_USERS_STATE" "$dest"
    run chmod 0600 "$dest" 2>/dev/null || true
  fi
  # 只保留最近 20 份
  if command -v python3 >/dev/null 2>&1; then
    MITA_USERS_BACKUP_DIR="$MITA_USERS_BACKUP_DIR" python3 -c '
import os, glob
d=os.environ.get("MITA_USERS_BACKUP_DIR", "/var/lib/mita-oneclick/backups")
files=sorted(glob.glob(os.path.join(d, "users_*.json")), key=os.path.getmtime, reverse=True)
for f in files[20:]:
    try: os.remove(f)
    except Exception: pass
' 2>/dev/null || true
  fi
  printf '%s' "$dest"
}

users_validate_state_file() {
  local f="$1" protocol="${2:-${PROTOCOL:-TCP}}" auto_host="${3:-}"
  [ -f "$f" ] || return 1
  python3 -c '
import datetime,ipaddress,json,re,sys
d=json.load(open(sys.argv[1]))
proto=(sys.argv[2] if len(sys.argv)>2 else "TCP").upper()
auto_host=(sys.argv[3] if len(sys.argv)>3 else "").strip()
def normalize_endpoint_host(value):
    value=str(value or "").strip()
    try:
        return str(ipaddress.ip_address(value))
    except Exception:
        pass
    raw=value[:-1] if value.endswith(".") else value
    if not raw or len(raw)>253 or "://" in raw or ":" in raw or "/" in raw:
        raise ValueError("invalid host")
    labels=raw.split(".")
    if any(not label or len(label)>63 or not re.fullmatch(r"[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?", label) for label in labels):
        raise ValueError("invalid host")
    return raw.lower()
if proto not in ("TCP", "UDP", "BOTH"):
    sys.exit(15)
if auto_host:
    try:
        auto_host=str(ipaddress.ip_address(auto_host))
    except Exception:
        auto_host=""
users=d.get("users")
if not isinstance(users, list):
    sys.exit(2)
names=set(); occupied_ports=set(); advertised_endpoints=set()
for u in users:
    if not isinstance(u, dict):
        sys.exit(3)
    n=u.get("name")
    pw=u.get("password")
    if not isinstance(n, str) or not n or len(n.encode()) > 64:
        sys.exit(4)
    if any(ord(c) < 32 or ord(c) == 127 for c in n):
        sys.exit(4)
    if not isinstance(pw, str) or not pw or len(pw.encode()) > 64:
        sys.exit(8)
    if any(ord(c) < 32 or ord(c) == 127 for c in pw):
        sys.exit(8)
    if n in names:
        sys.exit(5)
    names.add(n)
    try:
        p=int(u.get("port"))
    except Exception:
        sys.exit(6)
    if p < 1025 or p > 65535 or (proto == "BOTH" and p > 65534):
        sys.exit(6)
    user_ports=(p, p+1) if proto == "BOTH" else (p,)
    if any(port in occupied_ports for port in user_ports):
        sys.exit(7)
    occupied_ports.update(user_ports)
    advertise_host=str(u.get("advertise_host") or "").strip()
    advertise_port=u.get("advertise_port")
    if bool(advertise_host) != bool(advertise_port):
        sys.exit(17)
    if advertise_host:
        try:
            advertise_host=normalize_endpoint_host(advertise_host)
            advertise_port=int(advertise_port)
        except Exception:
            sys.exit(17)
        if advertise_port < 1 or advertise_port > 65535 or (proto == "BOTH" and advertise_port > 65534):
            sys.exit(17)
    else:
        advertise_port=""
    u["advertise_host"]=advertise_host
    u["advertise_port"]=advertise_port
    effective_host=advertise_host or auto_host
    effective_port=advertise_port if advertise_host else p
    if effective_host:
        endpoint_pairs=(("TCP", effective_port), ("UDP", effective_port+1)) if proto == "BOTH" else ((proto, effective_port),)
        for endpoint_proto, endpoint_port in endpoint_pairs:
            endpoint=(effective_host, endpoint_proto, endpoint_port)
            if endpoint in advertised_endpoints:
                sys.exit(18)
            advertised_endpoints.add(endpoint)
    try:
        qmb=max(0, int(u.get("quota_mb") or 0))
        qdays=max(0, int(u.get("quota_days") or 0))
        bw=max(0, int(u.get("bandwidth_mbps") or 0))
    except Exception:
        sys.exit(9)
    if qmb > 2147483647 or qdays > 2147483647 or bw > 1000000:
        sys.exit(16)
    u["quota_mb"]=qmb
    u["quota_days"]=(qdays if qdays > 0 else 30) if qmb > 0 else 0
    qmode=str(u.get("quota_mode") or "rolling").strip().lower()
    if qmode not in ("rolling","calendar"):
        sys.exit(10)
    u["quota_mode"]=qmode
    enabled=u.get("enabled", True)
    if not isinstance(enabled, bool):
        sys.exit(11)
    u["enabled"]=enabled
    expire=str(u.get("expire_at") or "").strip()
    if expire:
        try:
            datetime.date.fromisoformat(expire)
        except Exception:
            sys.exit(12)
    u["expire_at"]=expire
    last_reset=str(u.get("last_quota_reset") or "").strip()
    if last_reset and (len(last_reset) != 7 or last_reset[4] != "-" or not last_reset.replace("-","").isdigit()):
        sys.exit(13)
    u["last_quota_reset"]=last_reset
    package=str(u.get("package") or ("custom" if qmb > 0 else "unlimited"))
    if len(package.encode()) > 64 or any(ord(c) < 32 or ord(c) == 127 for c in package):
        sys.exit(14)
    u["package"]=package
    u["bandwidth_mbps"]=bw
d["version"]=2
d["protocol"]=proto
json.dump(d, open(sys.argv[1]+".norm","w"), indent=2)
' "$f" "$protocol" "$auto_host" 2>/dev/null || return 1
  if [ -f "${f}.norm" ]; then
    mv -f "${f}.norm" "$f" 2>/dev/null || return 1
  fi
  return 0
}

users_restore_from_file() {
  local src="$1" bak tx tmp imported_protocol
  local old_protocol old_user old_password old_port old_pairs new_pairs close_pairs rollback_close_pairs
  local old_advertise_host old_advertise_port
  [ -f "$src" ] || { warn "$(t "备份不存在: $src" "Backup not found: $src")"; return 1; }
  admin_lock_acquire || return 1
  load_install_state
  old_protocol="${PROTOCOL:-TCP}"
  old_user="${USERNAME:-}"
  old_password="${PASSWORD:-}"
  old_port="${PORT:-}"
  old_advertise_host="${ADVERTISE_HOST:-}"
  old_advertise_port="${ADVERTISE_PORT:-}"
  old_pairs="$(multi_user_port_protocol_pairs)"
  tmp="$(mktemp_file .json)"
  cp -f "$src" "$tmp"
  imported_protocol="$(python3 -c '
import json,sys
d=json.load(open(sys.argv[1]))
print(str(d.get("protocol") or sys.argv[2]).strip().upper())
' "$tmp" "$old_protocol" 2>/dev/null || true)"
  case "$imported_protocol" in
    TCP|UDP|BOTH) ;;
    *)
      rm -f "$tmp"
      admin_lock_release
      warn "$(t '备份中的协议无效（仅支持 TCP/UDP/BOTH）' \
        'Invalid protocol in backup (only TCP/UDP/BOTH are supported)')"
      return 1
      ;;
  esac
  users_validate_state_file "$tmp" "$imported_protocol" || {
    rm -f "$tmp"
    admin_lock_release
    warn "$(t '备份文件格式无效' 'Invalid backup format')"
    return 1
  }
  tx="$(users_tx_snapshot)" || { rm -f "$tmp"; admin_lock_release; return 1; }
  if users_state_exists; then
    bak="$(users_backup_now pre-restore 2>/dev/null || true)"
    [ -n "$bak" ] && t "恢复前已备份: $bak" "Pre-restore backup: $bak" >&2
  fi
  run mkdir -p "$(dirname "$MITA_USERS_STATE")"
  if command -v install >/dev/null 2>&1; then
    if ! run install -m 0600 "$tmp" "$MITA_USERS_STATE"; then
      rm -f "$tmp"
      users_tx_rollback "$tx" 0
      admin_lock_release
      return 1
    fi
  else
    if ! run cp -f "$tmp" "$MITA_USERS_STATE"; then
      rm -f "$tmp"
      users_tx_rollback "$tx" 0
      admin_lock_release
      return 1
    fi
    run chmod 0600 "$MITA_USERS_STATE" 2>/dev/null || true
  fi
  rm -f "$tmp"
  PROTOCOL="$imported_protocol"
  MULTI_USER_MODE=1
  users_sync_primary_globals
  if mita_installed 2>/dev/null; then
    if ! apply_users_config "$tx"; then
      # apply_users_config 已恢复 users.json，但它执行回滚时仍使用导入协议；
      # 这里切回旧协议并再次收敛，保证旧实例与旧端口完整恢复。
      PROTOCOL="$old_protocol"
      USERNAME="$old_user"
      PASSWORD="$old_password"
      PORT="$old_port"
      ADVERTISE_HOST="$old_advertise_host"
      ADVERTISE_PORT="$old_advertise_port"
      if users_isolated_mode; then
        reconcile_isolated_instances 2>/dev/null || true
        apply_tc_limits 2>/dev/null || true
      fi
      admin_lock_release
      return 1
    fi
    new_pairs="$(multi_user_port_protocol_pairs)"
    open_firewall_for_pairs "$new_pairs" 2>/dev/null || true
  else
    new_pairs="$(multi_user_port_protocol_pairs)"
    if ! apply_tc_limits; then
      PROTOCOL="$old_protocol"
      USERNAME="$old_user"
      PASSWORD="$old_password"
      PORT="$old_port"
      ADVERTISE_HOST="$old_advertise_host"
      ADVERTISE_PORT="$old_advertise_port"
      users_tx_rollback "$tx" 0
      admin_lock_release
      return 1
    fi
  fi
  if ! save_install_state; then
    rollback_close_pairs="$(comm -23 \
      <(printf '%s\n' "$new_pairs" | sed '/^[[:space:]]*$/d' | LC_ALL=C sort -u) \
      <(printf '%s\n' "$old_pairs" | sed '/^[[:space:]]*$/d' | LC_ALL=C sort -u))"
    PROTOCOL="$old_protocol"
    USERNAME="$old_user"
    PASSWORD="$old_password"
    PORT="$old_port"
    ADVERTISE_HOST="$old_advertise_host"
    ADVERTISE_PORT="$old_advertise_port"
    if mita_installed 2>/dev/null; then
      users_tx_rollback "$tx" 1
    else
      users_tx_rollback "$tx" 0
    fi
    open_firewall_for_pairs "$old_pairs" 2>/dev/null || true
    [ -z "$rollback_close_pairs" ] || close_firewall_for_bindings "$rollback_close_pairs"
    admin_lock_release
    return 1
  fi
  close_pairs="$(comm -23 \
    <(printf '%s\n' "$old_pairs" | sed '/^[[:space:]]*$/d' | LC_ALL=C sort -u) \
    <(printf '%s\n' "$new_pairs" | sed '/^[[:space:]]*$/d' | LC_ALL=C sort -u))"
  [ -z "$close_pairs" ] || close_firewall_for_bindings "$close_pairs"
  users_tx_commit "$tx"
  client_exports_clear_current 2>/dev/null || true
  admin_lock_release
  t "已从备份恢复用户状态" "Users restored from backup"
}

do_user_backup() {
  require_root
  users_state_exists || die "$(t '无用户状态可备份' 'No users state to backup')"
  local dest
  dest="$(users_backup_now manual)"
  t "已备份: $dest" "Backed up: $dest"
  # 同时备份 install-state 若存在
  if [ -f "$MITA_STATE" ]; then
    local sdest
    sdest="${dest%.json}_install-state.env"
    cp -f "$MITA_STATE" "$sdest" 2>/dev/null || true
    chmod 0600 "$sdest" 2>/dev/null || true
    t "  安装状态: $sdest" "  Install state: $sdest"
  fi
  msg ""
  t '最近备份:' 'Recent backups:'
  # shellcheck disable=SC2012
  ls -1t "$MITA_USERS_BACKUP_DIR"/users_*.json 2>/dev/null | head -n 10 || true
}

do_user_restore() {
  require_root
  local f="${USER_RESTORE_FILE:-}"
  if [ -z "$f" ]; then
    if [ "$YES" -eq 1 ]; then
      die "$(t '需要备份文件路径' 'Backup file path required')"
    fi
    msg ""
    t '可用备份:' 'Available backups:'
    # shellcheck disable=SC2012
    ls -1t "$MITA_USERS_BACKUP_DIR"/users_*.json 2>/dev/null | head -n 15 || true
    read_tty f "$(t '备份文件路径: ' 'Backup file: ')" || true
  fi
  [ -n "$f" ] || die "$(t '需要备份文件路径' 'Backup file path required')"
  if [ "$YES" -ne 1 ]; then
    confirm '确认用该备份覆盖当前用户配置？[y/N]: ' 'Overwrite current users with this backup? [y/N]: ' n || return 0
  fi
  users_restore_from_file "$f"
}

do_user_export() {
  require_root
  users_state_exists || die "$(t '无用户状态' 'No users state')"
  local out="${USER_EXPORT_FILE:-}"
  if [ -n "$out" ]; then
    run mkdir -p "$(dirname "$out")" 2>/dev/null || true
    cp -f "$MITA_USERS_STATE" "$out"
    chmod 0600 "$out" 2>/dev/null || true
    t "已导出: $out" "Exported: $out"
  else
    cat "$MITA_USERS_STATE"
  fi
}

do_user_import() {
  require_root
  local f="${USER_RESTORE_FILE:-}"
  if [ -z "$f" ] && [ "$YES" -ne 1 ]; then
    read_tty f "$(t '导入文件路径: ' 'Import file: ')" || f=""
  fi
  [ -n "$f" ] || die "$(t '需要 --user-import FILE' 'Need --user-import FILE')"
  if [ "$YES" -ne 1 ]; then
    confirm '导入将覆盖当前用户配置，是否继续？[y/N]: ' 'Import overwrites current users. Continue? [y/N]: ' n || return 0
  fi
  users_restore_from_file "$f"
}

print_user_outputs() {
  local name="$1"
  local ip password port saved_user saved_pass saved_port saved_advertise_host saved_advertise_port
  password="$(users_get_field "$name" password)" || return 1
  port="$(users_get_field "$name" port)" || return 1
  saved_user="$USERNAME"
  saved_pass="$PASSWORD"
  saved_port="$PORT"
  saved_advertise_host="$ADVERTISE_HOST"
  saved_advertise_port="$ADVERTISE_PORT"
  USERNAME="$name"
  PASSWORD="$password"
  PORT="$port"
  ADVERTISE_HOST="$(users_get_field "$name" advertise_host 2>/dev/null || true)"
  ADVERTISE_PORT="$(users_get_field "$name" advertise_port 2>/dev/null || true)"
  ip="$(advertised_host || echo 'YOUR_SERVER_IP')"
  msg ""
  t "========== 用户 ${name} ==========" "========== User ${name} =========="
  t "  专属实例端口: ${port}（其它用户凭据无法在此实例认证）" \
    "  Dedicated instance port: ${port} (other users cannot authenticate on this instance)"
  local qmb qdays exp en pkg bw
  qmb="$(users_get_field "$name" quota_mb 2>/dev/null || echo 0)"
  qdays="$(users_get_field "$name" quota_days 2>/dev/null || echo 0)"
  exp="$(users_get_field "$name" expire_at 2>/dev/null || true)"
  en="$(users_get_field "$name" enabled 2>/dev/null || echo 1)"
  pkg="$(users_get_field "$name" package 2>/dev/null || true)"
  bw="$(users_get_field "$name" bandwidth_mbps 2>/dev/null || echo 0)"
  t "  套餐: ${pkg:--}  配额: $(quota_label "$qmb" "$qdays")  双向限速: ${bw:-0}Mbps（0=不限） 到期: ${exp:-永不过期}  状态: $([ "$en" = 1 ] && echo on || echo off)" \
    "  Package: ${pkg:--}  Quota: $(quota_label "$qmb" "$qdays")  Bidirectional rate: ${bw:-0}Mbps (0=unlim) Expire: ${exp:-never}  Status: $([ "$en" = 1 ] && echo on || echo off)"
  print_protocol_outputs "$ip"
  msg ""
  t '【连接信息】' '[Connection info]'
  t "  服务器: ${ip}" "  Server:   ${ip}"
  t "  用户名: ${name}" "  Username: ${name}"
  t "  密码:   ${password}" "  Password: ${password}"
  t "  协议:   $(client_protocol_label)" "  Protocol: $(client_protocol_label)"
  if [ "$PROTOCOL" = "BOTH" ]; then
    t "  入口端口: TCP $(advertised_port_for_protocol TCP) / UDP $(advertised_port_for_protocol UDP)" \
      "  Entry ports: TCP $(advertised_port_for_protocol TCP) / UDP $(advertised_port_for_protocol UDP)"
  else
    t "  入口端口: $(advertised_port_for_protocol "$PROTOCOL")" \
      "  Entry port:  $(advertised_port_for_protocol "$PROTOCOL")"
  fi
  print_client_endpoint_mapping
  if [ -n "$ip" ] && [ "$ip" != "YOUR_SERVER_IP" ]; then
    msg ""
    t '【Clash / mihomo 配置片段】' '[Clash / mihomo snippet]'
    build_clash_yaml_full "$ip"
  fi
  USERNAME="$saved_user"
  PASSWORD="$saved_pass"
  PORT="$saved_port"
  ADVERTISE_HOST="$saved_advertise_host"
  ADVERTISE_PORT="$saved_advertise_port"
}

open_firewall_for_pairs() {
  local pairs="$1"
  local fw="" pp proto p proto_lc
  [ -n "$pairs" ] || return 0
  if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q 'Status: active'; then
    fw=ufw
  elif command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
    fw=firewalld
  elif command -v iptables >/dev/null 2>&1; then
    fw=iptables
  else
    return 0
  fi
  while IFS= read -r pp; do
    [ -n "$pp" ] || continue
    proto="${pp%%|*}"
    p="${pp#*|}"
    proto_lc="$(proto_lower "$proto")"
    firewall_apply_binding "$fw" add "$proto_lc" "$p"
  done <<< "$pairs"
  case "$fw" in
    firewalld) run firewall-cmd --reload || true ;;
    iptables) persist_iptables_rules ;;
  esac
}

do_user_list() {
  require_root
  load_install_state
  users_ensure_loaded
  if ! users_state_exists || [ "$(users_count)" -eq 0 ]; then
    t '（无多用户记录；当前为单用户安装，添加用户后将自动迁移）' \
      '(No multi-user state; single-user install. Adding a user migrates automatically.)'
    if [ -n "${USERNAME:-}" ]; then
      t "  主用户: ${USERNAME}  端口: ${PORT:-?}" "  Primary: ${USERNAME}  port: ${PORT:-?}"
    fi
    return 0
  fi
  msg ""
  t '用户名      端口 状态 套餐      配额      模式  限速  到期' \
    'USER        PORT ST  PACKAGE   QUOTA     MODE  RATE  EXPIRE'
  t '----------- ---- ---- --------- --------- ----- ----- ----------' \
    '----------- ---- ---- --------- --------- ----- ----- ----------'
  python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
for u in d.get("users") or []:
    name = (u.get("name") or "")[:11]
    port = str(u.get("port") or "")
    st = "on" if u.get("enabled", True) else "off"
    pkg = (u.get("package") or "-")[:9]
    qmb = int(u.get("quota_mb") or 0)
    qdays = int(u.get("quota_days") or 0)
    mode = (u.get("quota_mode") or "rolling")[:5]
    if qmb <= 0:
        quota = "unlimited"
        mode = "-"
    elif qmb >= 1024:
        quota = "%dG/%dd" % (qmb // 1024, qdays or 30)
    else:
        quota = "%dM/%dd" % (qmb, qdays or 30)
    bw = int(u.get("bandwidth_mbps") or 0)
    bws = str(bw) if bw > 0 else "-"
    exp = (u.get("expire_at") or "never")[:10]
    print(f"{name:<11} {port:<4} {st:<4} {pkg:<9} {quota:<9} {mode:<5} {bws:<5} {exp}")
' "$MITA_USERS_STATE"
  t "共 $(users_count) 个用户（rolling=滚动窗；calendar=每月1日重置）" \
    "Total $(users_count) (rolling window; calendar=reset on 1st)"
}

do_user_add() {
  require_root
  require_linux
  mita_installed || die "$(t 'mita 未安装，请先执行安装' 'mita is not installed; run install first')"
  # CLI 参数先保存，避免被 load_install_state 覆盖
  local name="${USERNAME:-}" password="${PASSWORD:-}" prefer="" tx
  local requested_advertise_host="${ADVERTISE_HOST:-}" requested_advertise_port="${ADVERTISE_PORT:-}"
  local requested_advertise_cli="${ADVERTISE_CLI:-0}"
  local saved_pkg="${USER_PACKAGE:-}" saved_qmb="${USER_QUOTA_MB:-}" saved_qd="${USER_QUOTA_DAYS:-}" saved_exp="${USER_EXPIRE:-}" saved_bw="${USER_BANDWIDTH_MBPS:-}"
  if [ "${PORT_CLI:-0}" -eq 1 ] && [ -n "${PORT:-}" ]; then
    prefer="$PORT"
  fi
  # --user/--password/--port 描述的是新用户；读取现有主用户时不能让这些 CLI 值覆盖安装状态。
  USERNAME_CLI=0
  PASSWORD_CLI=0
  PORT_CLI=0
  PORT_RANGE_CLI=0
  PROTOCOL_CLI=0
  ADVERTISE_CLI=0
  load_install_state
  USER_PACKAGE="$saved_pkg"
  USER_QUOTA_MB="$saved_qmb"
  USER_QUOTA_DAYS="$saved_qd"
  USER_EXPIRE="$saved_exp"
  USER_BANDWIDTH_MBPS="$saved_bw"
  if [ "$requested_advertise_cli" -ne 1 ]; then
    requested_advertise_host=""
    requested_advertise_port=""
  elif ! validate_advertise_endpoint_values "$requested_advertise_host" \
    "$requested_advertise_port" "${PROTOCOL:-TCP}"; then
    die "$(t '新用户的自定义客户端入口参数无效' \
      'Invalid custom client entry parameters for the new user')"
  fi
  [ -z "$requested_advertise_port" ] \
    || requested_advertise_port="$(normalize_uint "$requested_advertise_port")"
  if ! users_state_exists || [ "$(users_count)" -eq 0 ]; then
    load_config_from_mita || return 1
    load_credentials_fallback 2>/dev/null || true
    users_migrate_from_primary || return 1
    users_state_exists || {
      warn "$(t '无法迁移现有主用户，已取消新增以避免覆盖服务端账号' \
        'Could not migrate the existing primary user; add cancelled to avoid overwriting server accounts')"
      return 1
    }
  fi
  if [ -z "$name" ]; then
    if [ "$YES" -eq 1 ]; then
      name="$(random_token)"
    else
      read_tty name "$(t '新用户名: ' 'New username: ')" || true
    fi
  fi
  if [ -z "$password" ]; then
    if [ "$YES" -eq 1 ]; then
      password="$(random_token)"
    else
      read_tty_secret password "$(t '密码（回车随机）: ' 'Password (Enter=random): ')" || true
      [ -n "$password" ] || password="$(random_token)"
    fi
  fi
  if [ "$YES" -ne 1 ] && [ -z "${USER_PACKAGE}" ] && [ -z "${USER_QUOTA_MB}" ]; then
    local pk=""
    t '套餐: 1)不限量 2)体验10GB/7天 3)标准100GB/30天 4)自定义 5)跳过' \
      'Package: 1)unlimited 2)trial 10GB/7d 3)standard 100GB/30d 4)custom 5)skip'
    read_tty pk "$(t '选择 [1-5，默认1]: ' 'Choose [1-5, default 1]: ')" || pk=1
    case "${pk:-1}" in
      2) USER_PACKAGE=trial ;;
      3) USER_PACKAGE=standard ;;
      4)
        USER_PACKAGE=custom
        read_tty USER_QUOTA_MB "$(t '配额 MB（0=不限）: ' 'Quota MB (0=unlimited): ')" || true
        read_tty USER_QUOTA_DAYS "$(t '滚动天数 [30]: ' 'Rolling days [30]: ')" || true
        read_tty USER_EXPIRE "$(t '到期 YYYY-MM-DD 或 +30d（空=永不过期）: ' 'Expire YYYY-MM-DD or +30d (empty=never): ')" || true
        ;;
      5) ;;
      *) USER_PACKAGE=unlimited ;;
    esac
  fi
  admin_lock_acquire || return 1
  tx="$(users_tx_snapshot)" || { admin_lock_release; return 1; }
  if ! users_add "$name" "$password" "$prefer" \
    "$requested_advertise_host" "$requested_advertise_port" >/dev/null; then
    users_tx_rollback "$tx" 0
    admin_lock_release
    return 1
  fi
  if ! apply_users_config "$tx"; then
    admin_lock_release
    return 1
  fi
  users_sync_primary_globals
  if ! save_install_state; then
    users_tx_rollback "$tx" 1
    admin_lock_release
    return 1
  fi
  open_firewall_for_pairs "$(multi_user_port_protocol_pairs)"
  users_tx_commit "$tx"
  admin_lock_release
  print_user_outputs "$name"
}

do_user_set_quota() {
  require_root
  mita_installed || die "$(t 'mita 未安装' 'mita is not installed')"
  local requested_name="${USERNAME:-}"
  load_install_state
  users_ensure_loaded
  local name="${requested_name:-${USERNAME:-}}"
  [ -n "$name" ] || die "$(t '需要 --user NAME' 'Need --user NAME')"
  users_name_exists "$name" || die "$(t "用户不存在: $name" "User not found: $name")"
  if [ -z "${USER_QUOTA_MB}" ] && [ -z "${USER_QUOTA_DAYS}" ] \
     && [ -z "${USER_PACKAGE}" ] && [ -z "${USER_QUOTA_MODE}" ] \
     && [ -z "${USER_EXPIRE}" ]; then
    die "$(t '需要 --package / --quota-mb / --quota-mode' 'Need --package / --quota-mb / --quota-mode')" || return 1
    return 1
  fi
  if ! apply_user_package_defaults 0; then
    die "$(t '套餐或配额参数无效' 'Invalid package or quota value')" || return 1
    return 1
  fi
  if [ -n "${USER_QUOTA_MB}" ] && ! valid_nonnegative_int32 "$USER_QUOTA_MB"; then
    die "$(t '--quota-mb 必须是 0-2147483647 的整数' \
      '--quota-mb must be an integer from 0 to 2147483647')" || return 1
    return 1
  fi
  if [ -n "${USER_QUOTA_DAYS}" ] && ! valid_nonnegative_int32 "$USER_QUOTA_DAYS"; then
    die "$(t '--quota-days 必须是 0-2147483647 的整数' \
      '--quota-days must be an integer from 0 to 2147483647')" || return 1
    return 1
  fi
  local exp_parsed=""
  if [ -n "${USER_EXPIRE:-}" ]; then
    exp_parsed="$(parse_expire_date "$USER_EXPIRE")" || return 1
    USER_EXPIRE="$exp_parsed"
    [ -z "$USER_EXPIRE" ] && USER_EXPIRE="__CLEAR__"
  fi
  if [ -n "${USER_QUOTA_MODE:-}" ]; then
    USER_QUOTA_MODE="$(normalize_quota_mode "$USER_QUOTA_MODE")" || {
      die "$(t '--quota-mode 仅支持 rolling 或 calendar' \
        '--quota-mode accepts only rolling or calendar')" || return 1
      return 1
    }
  fi
  USER_BANDWIDTH_MBPS=""
  local tx old_pairs new_pairs close_pairs="" disabled_now=0
  admin_lock_acquire || return 1
  tx="$(users_tx_snapshot)" || { admin_lock_release; return 1; }
  old_pairs="$(multi_user_port_protocol_pairs)"
  if ! users_update_fields "$name"; then
    users_tx_rollback "$tx" 0
    admin_lock_release
    return 1
  fi
  if [ -n "$exp_parsed" ]; then
    local today
    today="$(today_ymd)"
    if [[ "$exp_parsed" < "$today" || "$exp_parsed" == "$today" ]]; then
      users_set_enabled "$name" 0 || {
        users_tx_rollback "$tx" 0
        admin_lock_release
        return 1
      }
      disabled_now=1
    fi
  fi
  if ! apply_users_config "$tx"; then
    admin_lock_release
    return 1
  fi
  if [ "$disabled_now" -eq 1 ]; then
    new_pairs="$(multi_user_port_protocol_pairs)"
    close_pairs="$(comm -23 \
      <(printf '%s\n' "$old_pairs" | sed '/^[[:space:]]*$/d' | LC_ALL=C sort -u) \
      <(printf '%s\n' "$new_pairs" | sed '/^[[:space:]]*$/d' | LC_ALL=C sort -u))"
    [ -z "$close_pairs" ] || close_firewall_for_bindings "$close_pairs"
    users_sync_primary_globals
    if ! save_install_state; then
      users_tx_rollback "$tx" 1
      open_firewall_for_pairs "$old_pairs"
      admin_lock_release
      return 1
    fi
  fi
  users_tx_commit "$tx"
  admin_lock_release
  t "已更新 ${name} 配额=$(quota_label "${USER_QUOTA_MB:-0}" "${USER_QUOTA_DAYS:-0}") 模式=${USER_QUOTA_MODE:-keep} 套餐=${USER_PACKAGE:-} 到期=${exp_parsed:-保持}" \
    "Updated ${name} quota=$(quota_label "${USER_QUOTA_MB:-0}" "${USER_QUOTA_DAYS:-0}") mode=${USER_QUOTA_MODE:-keep} package=${USER_PACKAGE:-} expire=${exp_parsed:-keep}"
}

do_user_set_expire() {
  require_root
  mita_installed || die "$(t 'mita 未安装' 'mita is not installed')"
  local requested_name="${USERNAME:-}"
  load_install_state
  users_ensure_loaded
  local name="${requested_name:-${USERNAME:-}}" exp disabled_now=0 disabled_port="" close_pairs=""
  [ -n "$name" ] || die "$(t '需要 --user NAME' 'Need --user NAME')"
  users_name_exists "$name" || die "$(t "用户不存在: $name" "User not found: $name")"
  [ -n "${USER_EXPIRE}" ] || die "$(t '需要 --expire YYYY-MM-DD|+Nd|0' 'Need --expire YYYY-MM-DD|+Nd|0')"
  exp="$(parse_expire_date "$USER_EXPIRE")" || return 1
  USER_EXPIRE="${exp:-__CLEAR__}"
  USER_QUOTA_MB="" USER_QUOTA_DAYS="" USER_PACKAGE="" USER_BANDWIDTH_MBPS=""
  local tx
  admin_lock_acquire || return 1
  tx="$(users_tx_snapshot)" || { admin_lock_release; return 1; }
  if ! users_update_fields "$name"; then
    users_tx_rollback "$tx" 0
    admin_lock_release
    return 1
  fi
  if [ -n "$exp" ]; then
    local today
    today="$(today_ymd)"
    if [[ "$exp" < "$today" || "$exp" == "$today" ]]; then
      if ! users_set_enabled "$name" 0; then
        users_tx_rollback "$tx" 0
        admin_lock_release
        return 1
      fi
      disabled_now=1
      disabled_port="$(users_get_field "$name" port 2>/dev/null || true)"
    fi
  fi
  if ! apply_users_config "$tx"; then
    admin_lock_release
    return 1
  fi
  if [ "$disabled_now" -eq 1 ] && valid_port "$disabled_port"; then
    close_pairs="${PROTOCOL:-TCP}|${disabled_port}"
    [ "$PROTOCOL" != "BOTH" ] || close_pairs="TCP|${disabled_port}"$'\n'"UDP|$((disabled_port + 1))"
    close_firewall_for_bindings "$close_pairs"
    users_sync_primary_globals
    if ! save_install_state; then
      users_tx_rollback "$tx" 1
      open_firewall_for_pairs "$close_pairs"
      admin_lock_release
      return 1
    fi
  fi
  users_tx_commit "$tx"
  admin_lock_release
  t "已设置 ${name} 到期=${exp:-永不过期}" "Set ${name} expire=${exp:-never}"
}

do_user_enable() {
  require_root
  mita_installed || die "$(t 'mita 未安装' 'mita is not installed')"
  load_install_state
  users_ensure_loaded
  local name="${USER_SHOW_NAME:-${USERNAME:-}}"
  [ -n "$name" ] || die "$(t '需要用户名' 'Username required')"
  local exp today tx old_pairs
  admin_lock_acquire || return 1
  tx="$(users_tx_snapshot)" || { admin_lock_release; return 1; }
  exp="$(users_get_field "$name" expire_at 2>/dev/null || true)"
  today="$(today_ymd)"
  if [ -n "$exp" ] && { [[ "$exp" < "$today" ]] || [[ "$exp" == "$today" ]]; }; then
    users_tx_commit "$tx"
    admin_lock_release
    warn "$(t "用户 $name 已到期 ($exp)，请先 --user-set-expire 续期" \
      "User $name expired ($exp); renew with --user-set-expire first")"
    return 1
  fi
  old_pairs="$(multi_user_port_protocol_pairs)"
  if ! users_set_enabled "$name" 1; then
    users_tx_rollback "$tx" 0
    admin_lock_release
    return 1
  fi
  if ! apply_users_config "$tx"; then
    admin_lock_release
    return 1
  fi
  users_sync_primary_globals
  if ! save_install_state; then
    users_tx_rollback "$tx" 1
    open_firewall_for_pairs "$old_pairs"
    admin_lock_release
    return 1
  fi
  open_firewall_for_pairs "$(multi_user_port_protocol_pairs)"
  users_tx_commit "$tx"
  admin_lock_release
  t "已启用用户 $name" "Enabled user $name"
}

do_user_disable() {
  require_root
  mita_installed || die "$(t 'mita 未安装' 'mita is not installed')"
  load_install_state
  users_ensure_loaded
  local name="${USER_SHOW_NAME:-${USERNAME:-}}"
  [ -n "$name" ] || die "$(t '需要用户名' 'Username required')"
  local en_n disabled_port close_pairs tx
  admin_lock_acquire || return 1
  tx="$(users_tx_snapshot)" || { admin_lock_release; return 1; }
  disabled_port="$(users_get_field "$name" port 2>/dev/null || true)"
  en_n="$(python3 -c '
import json,sys
d=json.load(open(sys.argv[1]))
print(sum(1 for u in (d.get("users") or []) if u.get("enabled", True) and u.get("name")!=sys.argv[2]))
' "$MITA_USERS_STATE" "$name" 2>/dev/null || echo 0)"
  if [ "${en_n:-0}" -lt 1 ]; then
    users_tx_commit "$tx"
    admin_lock_release
    die "$(t '不能停用最后一个启用中的用户' 'Cannot disable the last enabled user')"
  fi
  if ! users_set_enabled "$name" 0; then
    users_tx_rollback "$tx" 0
    admin_lock_release
    return 1
  fi
  if ! apply_users_config "$tx"; then
    admin_lock_release
    return 1
  fi
  if valid_port "$disabled_port"; then
    close_pairs="${PROTOCOL:-TCP}|${disabled_port}"
    if [ "$PROTOCOL" = "BOTH" ]; then
      close_pairs="TCP|${disabled_port}"$'\n'"UDP|$((disabled_port + 1))"
    fi
    close_firewall_for_bindings "$close_pairs"
  fi
  users_sync_primary_globals
  if ! save_install_state; then
    users_tx_rollback "$tx" 1
    open_firewall_for_pairs "$close_pairs"
    admin_lock_release
    return 1
  fi
  users_tx_commit "$tx"
  admin_lock_release
  t "已停用用户 $name（端口仍保留，可再 enable）" "Disabled $name (port kept; can re-enable)"
}

do_user_scan() {
  # cron/timer 入口：到期停用 + 日历月配额重置
  require_root 2>/dev/null || true
  load_install_state 2>/dev/null || true
  users_state_exists || return 0
  local out="" cal="" rc=0
  admin_lock_acquire || return 1
  if ! out="$(users_scan_expired)"; then
    warn "$(t '到期用户扫描失败，状态已回滚' 'Expired-user scan failed; state rolled back')"
    rc=1
  fi
  if ! cal="$(users_scan_calendar_quota_reset)"; then
    warn "$(t '日历月配额重置失败，状态已回滚' 'Calendar quota reset failed; state rolled back')"
    rc=1
  fi
  admin_lock_release
  if [ -n "$out" ]; then
    msg "disabled: $(printf '%s' "$out" | tr '\n' ' ')"
  fi
  if [ -n "$cal" ]; then
    msg "quota-reset: $(printf '%s' "$cal" | tr '\n' ' ')"
  fi
  return "$rc"
}

do_user_usage() {
  require_root 2>/dev/null || true
  mita_installed || die "$(t 'mita 未安装' 'mita is not installed')"
  local bin iid iname iport
  bin="$(mita_bin)"
  if users_isolated_mode; then
    while IFS=$'\t' read -r iid iname iport; do
      [ -n "$iid" ] || continue
      msg ""
      t "【${iname} / 专属实例 ${iid}】" "[${iname} / dedicated instance ${iid}]"
      instance_cmd "$iid" get users 2>/dev/null \
        || warn "$(t "${iname}: mita get users 不可用" "${iname}: mita get users unavailable")"
      instance_cmd "$iid" get quotas 2>/dev/null \
        || warn "$(t "${iname}: mita get quotas 不可用" "${iname}: mita get quotas unavailable")"
    done < <(users_enabled_instance_rows)
  else
    ensure_mita_daemon 2>/dev/null || true
    wait_mita_socket 10 2>/dev/null || true
    msg ""
    t '【用户流量】mita get users' '[User traffic] mita get users'
    "$bin" get users 2>/dev/null || warn "$(t 'mita get users 不可用' 'mita get users unavailable')"
    msg ""
    t '【配额用量】mita get quotas' '[Quota usage] mita get quotas'
    "$bin" get quotas 2>/dev/null || warn "$(t 'mita get quotas 不可用' 'mita get quotas unavailable')"
  fi
  msg ""
  t '【本地套餐配置】' '[Local package config]'
  if users_state_exists; then
    python3 -c '
import json,sys
d=json.load(open(sys.argv[1]))
print("%-14s %-6s %-8s %-10s %-8s" % ("USER","PORT","MODE","QUOTA_MB","BW_Mbps"))
for u in d.get("users") or []:
    print("%-14s %-6s %-8s %-10s %-8s" % (
      (u.get("name") or "")[:14],
      u.get("port") or "",
      (u.get("quota_mode") or "rolling")[:8],
      u.get("quota_mb") or 0,
      u.get("bandwidth_mbps") or 0,
    ))
' "$MITA_USERS_STATE"
  fi
}

do_user_export_clients() {
  require_root
  load_install_state
  users_ensure_loaded
  users_state_exists || die "$(t '无用户状态' 'No users state')"
  local dir="${MITA_CLIENT_EXPORT_DIR:-/root/mieru-clients}"
  local ts ip name safe_name backend_ip
  ts="$(date +%Y%m%d_%H%M%S)_$$_${RANDOM}"
  dir="${dir%/}/${ts}"
  run mkdir -p "$dir"
  run chmod 0700 "$dir" 2>/dev/null || true
  load_install_state
  backend_ip="$(public_ip 2>/dev/null || true)"
  t "导出目录: $dir" "Export dir: $dir" >&2
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    local password port saved_u saved_p saved_port saved_advertise_host saved_advertise_port proto f links_file
    password="$(users_get_field "$name" password)" || continue
    port="$(users_get_field "$name" port)" || continue
    saved_u="$USERNAME"; saved_p="$PASSWORD"; saved_port="$PORT"
    saved_advertise_host="$ADVERTISE_HOST"; saved_advertise_port="$ADVERTISE_PORT"
    USERNAME="$name"; PASSWORD="$password"; PORT="$port"
    ADVERTISE_HOST="$(users_get_field "$name" advertise_host 2>/dev/null || true)"
    ADVERTISE_PORT="$(users_get_field "$name" advertise_port 2>/dev/null || true)"
    ip="$(advertised_host || echo 'YOUR_SERVER_IP')"
    prepare_traffic_pattern_export
    safe_name="$(safe_filename_component "$name")"
    [ -n "$safe_name" ] || safe_name="user"
    links_file="${dir}/${safe_name}_links.txt"
    : >"$links_file"
    while IFS= read -r proto; do
      [ -n "$proto" ] || continue
      f="${dir}/${safe_name}_$(proto_lower "$proto").json"
      build_client_json_for "$ip" "$proto" >"$f"
      chmod 0600 "$f" 2>/dev/null || true
      generate_share_link_for "$ip" "$proto" >>"$links_file"
      printf '\n' >>"$links_file"
    done < <(protocols_for_mode)
    chmod 0600 "$links_file" 2>/dev/null || true
    print_client_endpoint_mapping "$backend_ip" >&2
    USERNAME="$saved_u"; PASSWORD="$saved_p"; PORT="$saved_port"
    ADVERTISE_HOST="$saved_advertise_host"; ADVERTISE_PORT="$saved_advertise_port"
    t "  已导出: $name" "  Exported: $name" >&2
  done < <(python3 -c '
import json,sys
d=json.load(open(sys.argv[1]))
for u in d.get("users") or []:
    if u.get("enabled", True):
        print(u.get("name") or "")
' "$MITA_USERS_STATE")
  t "完成: $dir" "Done: $dir" >&2
  printf '%s\n' "$dir"
}

doctor_check_tc_limits() {
  local dev rate_users
  rate_users="$(users_rate_limited_count)"
  if [ "${rate_users:-0}" -eq 0 ]; then
    check "rate-limit rules" 1 "$(t '未配置用户限速，clsact/filter 无需创建' \
      'No users have rate limits; clsact/filter rules are not required')"
  elif ! command -v tc >/dev/null 2>&1; then
    check "tc binary" 0 "$(t "${rate_users} 个限速用户，但 tc 未安装" \
      "${rate_users} rate-limited user(s), but tc is not installed")"
  else
    dev="$(tc_default_iface 2>/dev/null || true)"
    if [ -z "$dev" ]; then
      check "nic detect" 0 "$(t "${rate_users} 个限速用户，但未检测到网卡；可设置 TC_IFACE" \
        "${rate_users} rate-limited user(s), but no interface was detected; set TC_IFACE")"
    else
      check "nic" 1 "$dev"
      if tc qdisc show dev "$dev" 2>/dev/null | grep -qw clsact; then
        check "clsact" 1
      else
        check "clsact" 0 "$(t "${rate_users} 个限速用户，但 clsact 缺失" \
          "${rate_users} rate-limited user(s), but clsact is missing")"
      fi
      if [ -s "$TC_OWNED_STATE" ]; then
        check "owned filter manifest" 1 "$TC_OWNED_STATE"
      else
        check "owned filter manifest" 0 "$(t "${rate_users} 个限速用户，但规则清单缺失" \
          "${rate_users} rate-limited user(s), but the owned-filter manifest is missing")"
      fi
    fi
  fi
}

do_doctor() {
  require_root 2>/dev/null || true
  local pass=0 fail=0 warn_n=0
  check() {
    local name="$1" ok="$2" detail="${3:-}"
    if [ "$ok" = "1" ]; then
      msg "  [PASS] $name${detail:+ — $detail}"
      pass=$((pass + 1))
    elif [ "$ok" = "2" ]; then
      msg "  [WARN] $name${detail:+ — $detail}"
      warn_n=$((warn_n + 1))
    else
      msg "  [FAIL] $name${detail:+ — $detail}"
      fail=$((fail + 1))
    fi
  }
  print_banner
  t '========== 一键验收 doctor ==========' '========== doctor / verify =========='
  msg ""

  t '【环境】' '[Environment]'
  check "root" "$([ "$(id -u 2>/dev/null || echo 1)" -eq 0 ] && echo 1 || echo 0)"
  check "python3" "$(command -v python3 >/dev/null 2>&1 && echo 1 || echo 0)"
  check "tc (iproute2)" "$(command -v tc >/dev/null 2>&1 && echo 1 || echo 2)" "专属端口限速"
  check "flock" "$(command -v flock >/dev/null 2>&1 && echo 1 || echo 2)" "并发锁"

  t '【mita】' '[mita]'
  load_install_state 2>/dev/null || true
  if mita_installed; then
    check "mita installed" 1 "$(installed_version 2>/dev/null || echo ok)"
    local bin st iid iname iport cfg_ok
    bin="$(mita_bin)"
    if users_isolated_mode; then
      check "deployment model" 1 "$MITA_DEPLOYMENT_MODEL"
      if [ "$(service_manager)" = systemd ]; then
        check "instance service template" "$([ -f "$MITA_INSTANCE_SYSTEMD_TEMPLATE" ] && echo 1 || echo 0)"
        check "instance runtime tmpfiles" "$([ -f "$MITA_INSTANCE_TMPFILES" ] && echo 1 || echo 0)"
        if systemctl is-active --quiet mita 2>/dev/null; then
          check "legacy default service" 2 "仍在运行，可能产生端口冲突"
        else
          check "legacy default service inactive" 1
        fi
      else
        check "instance runner" "$([ -x "$MITA_INSTANCE_RUNNER" ] && echo 1 || echo 0)"
      fi
      while IFS=$'\t' read -r iid iname iport; do
        [ -n "$iid" ] || continue
        check "instance ${iname} config" "$([ -r "$(instance_config_path "$iid")" ] && echo 1 || echo 0)" "$iid"
        check "instance ${iname} socket" "$([ -S "$(instance_socket_path "$iid")" ] && echo 1 || echo 0)" "$iid"
        st="$(instance_cmd "$iid" status 2>/dev/null || true)"
        check "instance ${iname} RUNNING" "$(printf '%s' "$st" | grep -q 'status is \"RUNNING\"' && echo 1 || echo 0)" "$iid"
        cfg_ok="$(python3 - "$(instance_config_path "$iid")" "$iname" "$iport" "${PROTOCOL:-TCP}" <<'PY' 2>/dev/null && echo 1 || echo 0
import json,sys
path,name,port,proto=sys.argv[1],sys.argv[2],int(sys.argv[3]),sys.argv[4]
d=json.load(open(path))
users=d.get("users") or []
bindings=d.get("portBindings") or []
expected={(port, "TCP" if proto=="BOTH" else proto)}
if proto=="BOTH": expected.add((port+1,"UDP"))
actual={(int(x.get("port") or 0),x.get("protocol")) for x in bindings}
raise SystemExit(0 if len(users)==1 and users[0].get("name")==name and actual==expected else 1)
PY
)"
        check "instance ${iname} isolation" "$cfg_ok" "one user / dedicated bindings"
        check "instance ${iname} metrics dir" "$([ -d "$(instance_metrics_dir "$iid")" ] && echo 1 || echo 0)" "$iid"
        if instance_cmd "$iid" get users >/dev/null 2>&1; then
          check "instance ${iname} metrics API" 1
        else
          check "instance ${iname} metrics API" 2 "get users unavailable"
        fi
      done < <(users_enabled_instance_rows)
    else
      check "deployment model" 2 "legacy single instance; next managed change will migrate"
      ensure_mita_daemon 2>/dev/null || true
      if wait_mita_socket 8 2>/dev/null; then
        check "daemon socket" 1
      else
        check "daemon socket" 0 "未就绪"
      fi
      st="$("$bin" status 2>/dev/null || true)"
      if printf '%s' "$st" | grep -qi RUNNING; then
        check "proxy RUNNING" 1
      elif printf '%s' "$st" | grep -qi IDLE; then
        check "proxy status" 2 "IDLE（可能未 start）"
      else
        check "proxy status" 2 "${st:-unknown}"
      fi
    fi
  else
    check "mita installed" 0
  fi

  t '【用户状态】' '[Users state]'
  if users_state_exists; then
    check "users.json" 1 "$(users_count) users"
    local en desired_users actual_users user_diff
    en="$(python3 -c '
import json,sys
d=json.load(open(sys.argv[1]))
print(sum(1 for u in (d.get("users") or []) if u.get("enabled",True)))
' "$MITA_USERS_STATE" 2>/dev/null || echo 0)"
    check "enabled users" "$([ "${en:-0}" -ge 1 ] && echo 1 || echo 2)" \
      "$en$([ "${en:-0}" -eq 0 ] && printf ' (all disabled/expired)' || true)"
    if users_isolated_mode; then
      check "user-to-instance mapping" 1 "$en dedicated instances"
    elif mita_installed 2>/dev/null \
       && desired_users="$(users_enabled_names_from_state 2>/dev/null)" \
       && actual_users="$(mita_actual_user_names 2>/dev/null)"; then
      user_diff="$(DESIRED="$desired_users" ACTUAL="$actual_users" python3 -c '
import os
d=set(filter(None,os.environ.get("DESIRED","").splitlines()))
a=set(filter(None,os.environ.get("ACTUAL","").splitlines()))
parts=[]
if a-d: parts.append("stale="+",".join(sorted(a-d)))
if d-a: parts.append("missing="+",".join(sorted(d-a)))
print("; ".join(parts))
' 2>/dev/null || true)"
      if [ -z "$user_diff" ]; then
        check "actual user set" 1 "$en enabled"
      else
        check "actual user set" 0 "$user_diff"
      fi
    else
      check "actual user set" 2 "无法读取 mita 配置"
    fi
    # 目录权限
    local mode
    mode="$(stat -c '%a' /etc/mita 2>/dev/null || stat -f '%OLp' /etc/mita 2>/dev/null || echo '?')"
    if [ "$mode" = "750" ] || [ "$mode" = "0750" ] || [ "$mode" = "770" ] || [ "$mode" = "0770" ] || [ "$mode" = "700" ] || [ "$mode" = "0700" ]; then
      check "/etc/mita mode" 1 "$mode"
    else
      check "/etc/mita mode" 2 "$mode (建议 mita:mita 750)"
    fi
  else
    check "users.json" 2 "单用户或未迁移"
  fi

  t '【防火墙所有权】' '[Firewall ownership]'
  if [ -f "$MITA_FIREWALL_OWNED_STATE" ]; then
    check "owned firewall manifest" 1 "$MITA_FIREWALL_OWNED_STATE"
  else
    check "owned firewall manifest" 2 "未新增本地规则或沿用预先存在的规则"
  fi

  t '【专属实例 tc 限速】' '[Dedicated-instance tc limits]'
  doctor_check_tc_limits

  t '【定时任务】' '[Scheduler]'
  if [ -f "$MITA_USERS_TIMER" ] || systemctl is-enabled mita-users-scan.timer >/dev/null 2>&1; then
    check "systemd timer" 1
  elif [ -f "$MITA_USERS_CRON" ]; then
    check "cron.d" 1 "$MITA_USERS_CRON"
  else
    check "scheduler" 2 "未安装 timer/cron"
  fi
  if [ -f "$MITA_LOGROTATE_CONF" ]; then
    check "logrotate" 1
  else
    check "logrotate" 2 "可选"
  fi

  msg ""
  t "结果: PASS=$pass WARN=$warn_n FAIL=$fail" "Result: PASS=$pass WARN=$warn_n FAIL=$fail"
  if [ "$fail" -gt 0 ]; then
    t '存在失败项，请根据上方提示排查' 'Failures above need attention'
    return 1
  fi
  if [ "$warn_n" -gt 0 ]; then
    t '验收通过（警告可忽略或稍后处理）' 'Verify OK (warnings optional)'
  else
    t '验收通过' 'Verify OK'
  fi
  return 0
}

detect_public_ip_family() {
  local family="${1:-4}" candidate="" curl_flag=-4
  [ "$family" = 6 ] && curl_flag=-6
  candidate="$(curl "$curl_flag" -fsSL --connect-timeout 4 --max-time 8 \
    https://api.ip.sb/ip 2>/dev/null | head -n1 | tr -d '[:space:]' || true)"
  valid_public_ip_literal "$candidate" || return 1
  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import ipaddress,sys; raise SystemExit(0 if ipaddress.ip_address(sys.argv[1]).version==int(sys.argv[2]) else 1)' \
      "$candidate" "$family" 2>/dev/null || return 1
  elif { [ "$family" = 4 ] && [[ "$candidate" == *:* ]]; } \
       || { [ "$family" = 6 ] && [[ "$candidate" != *:* ]]; }; then
    return 1
  fi
  printf '%s' "$candidate"
}

perf_sysctl_value() {
  local key="$1" path="/proc/sys/${1//./\/}"
  if command -v sysctl >/dev/null 2>&1; then
    sysctl -n "$key" 2>/dev/null || true
  elif [ -r "$path" ]; then
    head -n1 "$path" 2>/dev/null || true
  fi
}

do_perf() {
  # 严格只读：本函数不得调用 run/save/apply/reconcile/ensure/start/enable 等写路径。
  local iface="" iface_mtu="" public4="" public6="" cc="" default_qdisc="" qdisc_live=""
  local cpu_cores="" load_now="" memory="" instance_count=0 process_rows="" rate_users=0 tc_state="inactive"
  local bbr_state="disabled" fq_state="disabled" installed="unknown" advertised="auto"
  load_install_state 2>/dev/null || true
  if users_state_exists && [ "$(users_count 2>/dev/null || echo 0)" -gt 0 ]; then
    users_sync_primary_globals
  fi
  profile_reconcile_metadata
  installed="$(installed_version 2>/dev/null || printf unknown)"
  iface="$(tc_default_iface 2>/dev/null || true)"
  [ -z "$iface" ] || iface_mtu="$(mtu_iface_value "$iface" 2>/dev/null || true)"
  public4="$(detect_public_ip_family 4 2>/dev/null || true)"
  public6="$(detect_public_ip_family 6 2>/dev/null || true)"
  cc="$(perf_sysctl_value net.ipv4.tcp_congestion_control)"
  default_qdisc="$(perf_sysctl_value net.core.default_qdisc)"
  [ -z "$iface" ] || qdisc_live="$(tc qdisc show dev "$iface" 2>/dev/null || true)"
  [ "$cc" != bbr ] || bbr_state=enabled
  if [ "$default_qdisc" = fq ] || printf '%s' "$qdisc_live" | grep -qw fq; then
    fq_state=enabled
  fi
  cpu_cores="$(getconf _NPROCESSORS_ONLN 2>/dev/null || true)"
  if [ -z "$cpu_cores" ] && command -v nproc >/dev/null 2>&1; then
    cpu_cores="$(nproc 2>/dev/null || true)"
  fi
  [ -n "$cpu_cores" ] || cpu_cores=unknown
  load_now="$(awk '{print $1" "$2" "$3}' /proc/loadavg 2>/dev/null || printf unknown)"
  memory="$(awk '/^MemTotal:/{t=$2}/^MemAvailable:/{a=$2}END{if(t)printf "%.0f MiB total / %.0f MiB available",t/1024,a/1024}' /proc/meminfo 2>/dev/null || true)"
  [ -n "$memory" ] || memory=unknown
  if users_state_exists; then
    instance_count="$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(sum(1 for u in d.get("users",[]) if u.get("enabled",True)))' \
      "$MITA_USERS_STATE" 2>/dev/null || echo 0)"
    rate_users="$(users_rate_limited_count 2>/dev/null || echo 0)"
  elif mita_installed; then
    instance_count=1
  fi
  if command -v ps >/dev/null 2>&1; then
    process_rows="$(ps -eo pid=,pcpu=,rss=,comm=,args= 2>/dev/null \
      | awk '$4=="mita" || $4=="mita-real" {printf "    PID %-7s CPU %-6s RSS %.1f MiB  %s\n",$1,$2,$3/1024,$4}' \
      | head -n 20 || true)"
  fi
  if [ -s "$TC_OWNED_STATE" ]; then
    tc_state="owned filters recorded"
  elif [ -n "$qdisc_live" ]; then
    tc_state="no OneClick-owned rate filters"
  fi
  if [ -n "${ADVERTISE_HOST:-}" ]; then
    advertised="$(url_host "$ADVERTISE_HOST"):${ADVERTISE_PORT}"
  elif [ -n "$public4" ]; then
    advertised="${public4}:${PORT:-unknown} (auto)"
  elif [ -n "$public6" ]; then
    advertised="[$public6]:${PORT:-unknown} (auto)"
  fi

  msg '========== Mieru Performance ========='
  msg ''
  t 'Profile' 'Profile'
  t "  $(profile_label)" "  $(profile_label)"
  msg ''
  t 'Mieru' 'Mieru'
  t "  Version: ${installed}" "  Version: ${installed}"
  t "  Transport: ${PROTOCOL:-unknown}" "  Transport: ${PROTOCOL:-unknown}"
  t "  MTU: ${MTU:-unknown}" "  MTU: ${MTU:-unknown}"
  t "  Multiplexing: ${MULTIPLEXING:-unknown}" "  Multiplexing: ${MULTIPLEXING:-unknown}"
  t "  Handshake: ${HANDSHAKE_MODE:-unknown}" "  Handshake: ${HANDSHAKE_MODE:-unknown}"
  t "  Traffic Pattern: $(traffic_label)" "  Traffic Pattern: $(traffic_label)"
  t "  Low Entropy: $(low_entropy_label)" "  Low Entropy: $(low_entropy_label)"
  msg ''
  t 'Kernel' 'Kernel'
  t "  TCP congestion control: ${cc:-unknown}" "  TCP congestion control: ${cc:-unknown}"
  t "  Default qdisc: ${default_qdisc:-unknown}" "  Default qdisc: ${default_qdisc:-unknown}"
  t "  BBR status: ${bbr_state}" "  BBR status: ${bbr_state}"
  t "  fq status: ${fq_state}" "  fq status: ${fq_state}"
  msg ''
  t 'Network' 'Network'
  t "  Default interface: ${iface:-unknown}" "  Default interface: ${iface:-unknown}"
  t "  Interface MTU: ${iface_mtu:-unknown}" "  Interface MTU: ${iface_mtu:-unknown}"
  t "  Detected public IPv4: ${public4:-unavailable}" "  Detected public IPv4: ${public4:-unavailable}"
  t "  Detected public IPv6: ${public6:-unavailable}" "  Detected public IPv6: ${public6:-unavailable}"
  msg ''
  t 'Endpoint' 'Endpoint'
  t "  Backend listen address: all interfaces" "  Backend listen address: all interfaces"
  t "  Backend listen port: ${PORT:-unknown}" "  Backend listen port: ${PORT:-unknown}"
  t "  Advertised client address: ${ADVERTISE_HOST:-auto}" "  Advertised client address: ${ADVERTISE_HOST:-auto}"
  t "  Advertised client port: ${ADVERTISE_PORT:-${PORT:-unknown}}" "  Advertised client port: ${ADVERTISE_PORT:-${PORT:-unknown}}"
  if client_endpoint_is_independent "$public4" "$public6"; then
    local backend_endpoint="${public4:-${public6:-<undetected>}}"
    t '  [INFO] 当前使用独立客户端入口' \
      '  [INFO] An independent client endpoint is in use'
    t "    Client: ${advertised}" "    Client: ${advertised}"
    t "    Backend: $(url_host "$backend_endpoint"):${PORT:-unknown}" \
      "    Backend: $(url_host "$backend_endpoint"):${PORT:-unknown}"
  fi
  msg ''
  t 'Resource' 'Resource'
  t "  CPU cores: ${cpu_cores}" "  CPU cores: ${cpu_cores}"
  t "  Current load: ${load_now}" "  Current load: ${load_now}"
  t "  Memory: ${memory}" "  Memory: ${memory}"
  t "  Number of mita instances: ${instance_count}" "  Number of mita instances: ${instance_count}"
  if [ -n "$process_rows" ]; then
    t '  Relevant processes:' '  Relevant processes:'
    msg "$process_rows"
  else
    t '  Relevant processes: none detected' '  Relevant processes: none detected'
  fi
  msg ''
  t 'Traffic Control' 'Traffic Control'
  t '  Global bandwidth limit: not configured by OneClick' \
    '  Global bandwidth limit: not configured by OneClick'
  t "  Per-user bandwidth limits: ${rate_users}" "  Per-user bandwidth limits: ${rate_users}"
  t "  tc status: ${tc_state}" "  tc status: ${tc_state}"
  msg ''
  t 'Warnings' 'Warnings'
  local warning_count=0
  if [ "$(normalize_traffic_pattern "${TRAFFIC_PATTERN:-off}" 2>/dev/null || printf off)" != off ]; then
    warn "$(t 'Traffic Pattern 已开启；性能基准测试时建议关闭后进行 A/B 对比。' \
      'Traffic Pattern is enabled; benchmark with it off for an A/B comparison.')"
    warning_count=$((warning_count + 1))
  fi
  if [ "$(normalize_low_entropy_mode "${LOW_ENTROPY_MODE:-LOW_ENTROPY_MODE_OFF}" 2>/dev/null || true)" != LOW_ENTROPY_MODE_OFF ]; then
    warn "$(t 'Low Entropy 已开启，会增加额外流量。' 'Low Entropy is enabled and adds traffic overhead.')"
    warning_count=$((warning_count + 1))
  fi
  case "${MULTIPLEXING:-MULTIPLEXING_OFF}" in
    MULTIPLEXING_MIDDLE|MULTIPLEXING_HIGH)
      warn "$(t 'Multiplexing MIDDLE/HIGH 可能不适合纯大文件吞吐测试。' \
        'Multiplexing MIDDLE/HIGH may not suit bulk-file throughput tests.')"
      warning_count=$((warning_count + 1))
      ;;
  esac
  if [ "${rate_users:-0}" -gt 0 ] || [ -s "$TC_OWNED_STATE" ]; then
    warn "$(t 'tc 当前存在 OneClick 管理的限速。' 'OneClick-managed tc rate limits are active.')"
    warning_count=$((warning_count + 1))
  fi
  if [[ "${iface_mtu:-}" =~ ^[0-9]+$ ]] && [[ "${MTU:-}" =~ ^[0-9]+$ ]] \
     && { [ "$MTU" -gt "$iface_mtu" ] \
       || { [ "${PROTOCOL:-TCP}" != TCP ] && [ $((MTU + 48)) -gt "$iface_mtu" ]; }; }; then
    warn "$(t '网卡 MTU 与 Mieru MTU/传输开销组合可能存在分片风险。' \
      'Interface MTU versus Mieru MTU/transport overhead may cause fragmentation.')"
    warning_count=$((warning_count + 1))
  fi
  if [ "$bbr_state" != enabled ]; then
    warn "$(t 'BBR 未启用。' 'BBR is not enabled.')"
    warning_count=$((warning_count + 1))
  fi
  if [ "$fq_state" != enabled ]; then
    warn "$(t 'fq 未启用。' 'fq is not enabled.')"
    warning_count=$((warning_count + 1))
  fi
  [ "$warning_count" -gt 0 ] || t '  未发现明显性能限制。' '  No obvious performance limits detected.'
  t '  本报告为只读；未修改任何系统或 Mieru 配置。' \
    '  This report is read-only; no system or Mieru configuration was changed.'
}

do_user_quota_reset() {
  # 手动触发日历月重置（或强制所有 calendar 用户）
  require_root
  load_install_state
  users_ensure_loaded
  local force="${1:-}" cal tx
  admin_lock_acquire || return 1
  tx="$(users_tx_snapshot)" || { admin_lock_release; return 1; }
  if [ "$force" = "force" ] || [ "${YES:-0}" -eq 1 ]; then
    # 清除 last_quota_reset 使本月全部 calendar 用户重跑
    python3 -c '
import json,sys
path=sys.argv[1]
d=json.load(open(path))
for u in d.get("users") or []:
    if (u.get("quota_mode") or "")=="calendar" and int(u.get("quota_mb") or 0)>0:
        u["last_quota_reset"]=""
json.dump(d, open(path,"w"), indent=2)
' "$MITA_USERS_STATE" 2>/dev/null || {
      users_tx_rollback "$tx" 0
      admin_lock_release
      return 1
    }
  fi
  if ! cal="$(users_scan_calendar_quota_reset)"; then
    users_tx_rollback "$tx" 0
    admin_lock_release
    return 1
  fi
  users_tx_commit "$tx"
  admin_lock_release
  if [ -n "$cal" ]; then
    t "已重置日历月配额: $(printf '%s' "$cal" | tr '\n' ' ')" \
      "Calendar quota reset: $(printf '%s' "$cal" | tr '\n' ' ')"
  else
    t '无需重置（无 calendar 用户或本月已重置）' \
      'Nothing to reset (no calendar users or already done this month)'
  fi
}

do_user_set_rate() {
  require_root
  mita_installed || die "$(t 'mita 未安装' 'mita is not installed')"
  local requested_name="${USERNAME:-}"
  load_install_state
  users_ensure_loaded
  local name="${requested_name:-${USERNAME:-}}" bw="${USER_BANDWIDTH_MBPS:-}"
  [ -n "$name" ] || die "$(t '需要 --user NAME' 'Need --user NAME')"
  [ -n "$bw" ] || die "$(t '需要 --bandwidth Mbps（0=不限）' 'Need --bandwidth Mbps (0=unlimited)')"
  valid_bandwidth_mbps "$bw" || die "$(t '带宽须为 0-1000000 Mbps 的整数' \
    'Bandwidth must be an integer from 0 to 1000000 Mbps')"
  users_name_exists "$name" || die "$(t "用户不存在: $name" "User not found: $name")"
  USER_QUOTA_MB="" USER_QUOTA_DAYS="" USER_EXPIRE="" USER_PACKAGE=""
  USER_BANDWIDTH_MBPS="$bw"
  local tx
  admin_lock_acquire || return 1
  tx="$(users_tx_snapshot)" || { admin_lock_release; return 1; }
  if ! users_update_fields "$name"; then
    users_tx_rollback "$tx" 0
    admin_lock_release
    return 1
  fi
  if ! apply_users_config "$tx"; then
    admin_lock_release
    return 1
  fi
  users_tx_commit "$tx"
  admin_lock_release
  t "已更新 ${name} 的专属实例限速: ${bw} Mbps（0=不限）" \
    "Updated dedicated-instance limit for ${name}: ${bw} Mbps (0=unlimited)"
}

do_rate_status() {
  require_root 2>/dev/null || true
  load_install_state 2>/dev/null || true
  tc_rate_status
}

do_rate_restore() {
  require_root 2>/dev/null || true
  load_install_state 2>/dev/null || true
  admin_lock_acquire || return 1
  if ! apply_tc_limits; then
    admin_lock_release
    return 1
  fi
  admin_lock_release
  t '已根据专属实例套餐恢复本脚本拥有的 tc filter；未替换现有 root qdisc' \
    'Restored script-owned tc filters from dedicated packages; existing root qdiscs were not replaced'
}

do_user_del() {
  require_root
  require_linux
  mita_installed || die "$(t 'mita 未安装' 'mita is not installed')"
  load_install_state
  users_ensure_loaded
  local name="${USER_DEL_NAME:-}"
  if [ -z "$name" ]; then
    if [ "$YES" -eq 1 ]; then
      die "$(t '--user-del 需要用户名' '--user-del requires username')"
    fi
    do_user_list
    read_tty name "$(t '要删除的用户名: ' 'Username to delete: ')" || true
  fi
  [ -n "$name" ] || die "$(t '用户名不能为空' 'Username required')"
  local n freed tx close_pairs=""
  admin_lock_acquire || return 1
  tx="$(users_tx_snapshot)" || { admin_lock_release; return 1; }
  n="$(users_count)"
  if [ "${n:-0}" -le 1 ] && users_name_exists "$name"; then
    users_tx_commit "$tx"
    admin_lock_release
    if [ "${MENU_MODE:-0}" -eq 1 ]; then
      warn "$(t '不能删除最后一个用户' 'Cannot delete the last user')"
      return "$USER_MENU_HANDLED_RC"
    fi
    die "$(t '不能删除最后一个用户' 'Cannot delete the last user')"
  fi
  if ! freed="$(users_del "$name")"; then
    users_tx_rollback "$tx" 0
    admin_lock_release
    return 1
  fi
  if ! apply_users_config "$tx"; then
    admin_lock_release
    return 1
  fi
  if [ -n "$freed" ]; then
    close_pairs="${PROTOCOL}|${freed}"
    [ "$PROTOCOL" = "BOTH" ] && close_pairs="TCP|${freed}"$'\n'"UDP|$((freed + 1))"
    close_firewall_for_bindings "$close_pairs"
  fi
  open_firewall_for_pairs "$(multi_user_port_protocol_pairs)"
  users_sync_primary_globals
  if ! save_install_state; then
    users_tx_rollback "$tx" 1
    open_firewall_for_pairs "$close_pairs"
    admin_lock_release
    return 1
  fi
  users_tx_commit "$tx"
  client_export_remove_user "$name" 2>/dev/null || true
  admin_lock_release
  t "完成。已释放端口: ${freed:-?}" "Done. Freed port: ${freed:-?}"
}

do_user_set_endpoint() {
  require_root
  require_linux
  local requested_name="${USERNAME:-}" requested_host="${ADVERTISE_HOST:-}"
  local requested_port="${ADVERTISE_PORT:-}" requested_cli="${ADVERTISE_CLI:-0}"
  local name host port actual_port tx auto_host=""
  USERNAME_CLI=0
  ADVERTISE_CLI=0
  load_install_state
  users_ensure_loaded
  users_state_exists || die "$(t '无用户状态' 'No users state')"
  name="${requested_name:-${USERNAME:-}}"
  if [ -z "$name" ]; then
    [ "$YES" -ne 1 ] || die "$(t '需要 --user NAME' 'Need --user NAME')"
    read_tty name "$(t '用户名: ' 'Username: ')" || true
  fi
  users_name_exists "$name" || die "$(t "用户不存在: $name" "User not found: $name")"
  actual_port="$(users_get_field "$name" port)"

  if [ "$requested_cli" -eq 1 ]; then
    host="$requested_host"
    port="$requested_port"
    validate_advertise_endpoint_values "$host" "$port" "$PROTOCOL" \
      || die "$(t '自定义客户端入口参数无效' 'Invalid custom client entry parameters')"
    [ -z "$port" ] || port="$(normalize_uint "$port")"
  else
    [ "$YES" -ne 1 ] || die "$(t '请提供 --advertise-host/--advertise-port 或 --advertise-auto' \
      'Provide --advertise-host/--advertise-port or --advertise-auto')"
    ADVERTISE_HOST="$(users_get_field "$name" advertise_host 2>/dev/null || true)"
    ADVERTISE_PORT="$(users_get_field "$name" advertise_port 2>/dev/null || true)"
    PORT="$actual_port"
    msg ""
    t "当前客户端入口: $([ -n "$ADVERTISE_HOST" ] && printf '%s:%s' "$ADVERTISE_HOST" "$ADVERTISE_PORT" || printf '自动探测')" \
      "Current client entry: $([ -n "$ADVERTISE_HOST" ] && printf '%s:%s' "$ADVERTISE_HOST" "$ADVERTISE_PORT" || printf 'auto-detect')"
    collect_advertise_endpoint_interactive
    host="$ADVERTISE_HOST"
    port="$ADVERTISE_PORT"
  fi

  admin_lock_acquire || return 1
  tx="$(users_tx_snapshot)" || { admin_lock_release; return 1; }
  if ! users_set_advertise_endpoint "$name" "$host" "$port"; then
    users_tx_rollback "$tx" 0
    admin_lock_release
    return 1
  fi
  auto_host="$(public_ip 2>/dev/null || true)"
  if ! users_validate_state_file "$MITA_USERS_STATE" "$PROTOCOL" "$auto_host"; then
    users_tx_rollback "$tx" 0
    admin_lock_release
    die "$(t '客户端展示入口与其它用户冲突' \
      'Client display endpoint conflicts with another user')"
  fi
  users_sync_primary_globals
  if ! save_install_state; then
    users_tx_rollback "$tx" 0
    admin_lock_release
    return 1
  fi
  users_tx_commit "$tx"
  admin_lock_release
  t "已更新 ${name} 的客户端展示入口；服务端实例未重启" \
    "Updated ${name} client display endpoint; server instance was not restarted"
  print_user_outputs "$name"
}

do_user_show() {
  require_root
  load_install_state
  users_ensure_loaded
  local name="${USER_SHOW_NAME:-}"
  if [ -z "$name" ]; then
    read_tty name "$(t '用户名: ' 'Username: ')" || true
  fi
  users_name_exists "$name" || die "$(t "用户不存在: $name" "User not found: $name")"
  print_user_outputs "$name"
}

do_user_manage() {
  require_root
  MENU_MODE=1
  while true; do
    msg ""
    t '【用户管理】每个账号使用专属 mita 实例、端口、配额 metrics 与可选双向限速' \
      '[Users] every account has a dedicated mita instance, port, quota metrics, and optional bidirectional rate limit'
    msg "  1) 列出用户"
    msg "  2) 添加用户"
    msg "  3) 删除用户"
    msg "  4) 查看用户节点配置"
    msg "  5) 设置套餐/配额"
    msg "  6) 设置到期日"
    msg "  7) 启用用户"
    msg "  8) 停用用户"
    msg "  9) 立即扫描到期+月配额"
    msg "  10) 设置专属实例限速"
    msg "  11) 查看专属限速/tc 状态"
    msg "  12) 备份用户配置"
    msg "  13) 从备份恢复"
    msg "  14) 强制日历月配额重置"
    msg "  15) 查看流量/配额用量"
    msg "  16) 批量导出客户端配置"
    msg "  17) 设置客户端展示入口"
    msg "  18) 返回主菜单"
    local c=""
    read_tty c "$(t '请选择 [1-18]: ' 'Choose [1-18]: ')" || c=""
    c="$(printf '%s' "$c" | tr -d '[:space:]')"
    if [ "$c" = 18 ]; then
      [ "${MAIN_MENU_ACTIVE:-0}" -eq 1 ] && return 3
      return 0
    fi
    local action_rc=0
    set +e
    (
      set -Eeuo pipefail
      trap 'rc=$?; if [ "$rc" -eq 3 ] || [ "$rc" -eq "$USER_MENU_HANDLED_RC" ]; then exit "$rc"; fi; on_error' ERR
      case "$c" in
        1) STAGE="列出用户" ;;
        2) STAGE="添加用户" ;;
        3) STAGE="删除用户" ;;
        4) STAGE="查看用户节点配置" ;;
        5) STAGE="设置用户套餐" ;;
        6) STAGE="设置用户到期日" ;;
        7) STAGE="启用用户" ;;
        8) STAGE="停用用户" ;;
        9) STAGE="扫描用户配额" ;;
        10) STAGE="设置用户限速" ;;
        11) STAGE="查看限速状态" ;;
        12) STAGE="备份用户配置" ;;
        13) STAGE="恢复用户配置" ;;
        14) STAGE="重置用户配额" ;;
        15) STAGE="查看用户用量" ;;
        16) STAGE="导出用户客户端配置" ;;
        17) STAGE="设置用户展示入口" ;;
        *) STAGE="用户管理" ;;
      esac
      case "$c" in
      1) do_user_list ;;
      2)
        USERNAME=""; PASSWORD=""; PORT=""; PORT_CLI=0
        USER_PACKAGE=""; USER_QUOTA_MB=""; USER_QUOTA_DAYS=""; USER_QUOTA_MODE=""; USER_EXPIRE=""; USER_BANDWIDTH_MBPS=""
        local bw_in="" qm_in=""
        read_tty USERNAME "$(t '新用户名: ' 'New username: ')" || true
        read_tty PASSWORD "$(t '密码（回车随机）: ' 'Password (Enter=random): ')" || true
        read_tty bw_in "$(t '带宽 Mbps（回车=不限，双向）: ' 'Bandwidth Mbps (Enter=unlim, both dirs): ')" || true
        USER_BANDWIDTH_MBPS="${bw_in:-0}"
        do_user_add
        ;;
      3)
        USER_DEL_NAME=""
        do_user_del
        ;;
      4)
        USER_SHOW_NAME=""
        do_user_show
        ;;
      5)
        USERNAME=""; USER_PACKAGE=""; USER_QUOTA_MB=""; USER_QUOTA_DAYS=""; USER_QUOTA_MODE=""; USER_EXPIRE=""; USER_BANDWIDTH_MBPS=""
        read_tty USERNAME "$(t '用户名: ' 'Username: ')" || true
        t '1)不限量 2)体验 3)标准 4)自定义' '1)unlimited 2)trial 3)standard 4)custom'
        local pk="" qm_in=""
        read_tty pk "$(t '套餐 [1-4]: ' 'Package [1-4]: ')" || true
        case "$pk" in
          1) USER_PACKAGE=unlimited ;;
          2) USER_PACKAGE=trial ;;
          3) USER_PACKAGE=standard ;;
          4)
            USER_PACKAGE=custom
            read_tty USER_QUOTA_MB "$(t '配额 MB: ' 'Quota MB: ')" || true
            read_tty USER_QUOTA_DAYS "$(t '滚动天数 [30]: ' 'Days [30]: ')" || true
            ;;
        esac
        read_tty qm_in "$(t '配额模式 1)滚动 2)日历月 [1]: ' 'Quota mode 1)rolling 2)calendar [1]: ')" || true
        case "${qm_in:-1}" in
          2) USER_QUOTA_MODE=calendar ;;
          *) USER_QUOTA_MODE=rolling ;;
        esac
        do_user_set_quota
        ;;
      6)
        USERNAME=""; USER_EXPIRE=""; USER_BANDWIDTH_MBPS=""
        read_tty USERNAME "$(t '用户名: ' 'Username: ')" || true
        read_tty USER_EXPIRE "$(t '到期 YYYY-MM-DD / +30d / 0: ' 'Expire YYYY-MM-DD / +30d / 0: ')" || true
        do_user_set_expire
        ;;
      7)
        USER_SHOW_NAME=""
        read_tty USER_SHOW_NAME "$(t '用户名: ' 'Username: ')" || true
        do_user_enable
        ;;
      8)
        USER_SHOW_NAME=""
        read_tty USER_SHOW_NAME "$(t '用户名: ' 'Username: ')" || true
        do_user_disable
        ;;
      9) do_user_scan ;;
      10)
        USERNAME=""; USER_BANDWIDTH_MBPS=""
        read_tty USERNAME "$(t '用户名: ' 'Username: ')" || true
        read_tty USER_BANDWIDTH_MBPS "$(t '带宽 Mbps（0=不限，双向）: ' 'Bandwidth Mbps (0=unlimited, both directions): ')" || true
        do_user_set_rate
        ;;
      11) do_rate_status ;;
      12) do_user_backup ;;
      13)
        USER_RESTORE_FILE=""
        do_user_restore
        ;;
      14)
        local saved_yes="$YES"
        YES=1
        do_user_quota_reset force
        YES="$saved_yes"
        ;;
      15) do_user_usage ;;
      16) do_user_export_clients ;;
      17)
        USERNAME=""; ADVERTISE_HOST=""; ADVERTISE_PORT=""; ADVERTISE_CLI=0
        read_tty USERNAME "$(t '用户名: ' 'Username: ')" || true
        do_user_set_endpoint
        ;;
      *) warn "$(t '无效选择' 'Invalid choice')" ;;
      esac
    )
    action_rc=$?
    set -e
    [ "$action_rc" -ne 3 ] || return 3
    if [ "$action_rc" -ne 0 ] && [ "$action_rc" -ne "$USER_MENU_HANDLED_RC" ]; then
      warn "$(t '用户操作未完成，请根据上方错误重试' \
        'User operation failed; review the error above and retry')"
    fi
    user_menu_pause
  done
}

normalize_profile() {
  case "$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]' | tr '_ ' '--')" in
    iplc|iplc-performance|performance) printf 'iplc' ;;
    balanced|balance|default) printf 'balanced' ;;
    stealth|obfuscation) printf 'stealth' ;;
    custom|advanced) printf 'custom' ;;
    *) return 1 ;;
  esac
}

# Optional argument is part of the public helper API.
# shellcheck disable=SC2120
profile_label() {
  case "$(normalize_profile "${1:-${PROFILE:-custom}}" 2>/dev/null || printf custom)" in
    iplc) t 'IPLC / 专线性能' 'IPLC / Dedicated-line Performance' ;;
    balanced) t '普通公网' 'General Public Network' ;;
    stealth) t '强化伪装' 'Enhanced Camouflage' ;;
    *) t '高级自定义' 'Advanced Custom' ;;
  esac
}

profile_values_match() {
  local expected="$1"
  local proto mtu mux handshake traffic low
  proto="$(normalize_protocol "${PROTOCOL:-TCP}" 2>/dev/null || true)"
  mtu="$(normalize_uint "${MTU:-}" 2>/dev/null || true)"
  mux="$(normalize_multiplexing "${MULTIPLEXING:-}" 2>/dev/null || true)"
  handshake="$(normalize_handshake_mode "${HANDSHAKE_MODE:-}" 2>/dev/null || true)"
  traffic="$(normalize_traffic_pattern "${TRAFFIC_PATTERN:-}" 2>/dev/null || true)"
  low="$(normalize_low_entropy_mode "${LOW_ENTROPY_MODE:-}" 2>/dev/null || true)"
  case "$expected" in
    iplc)
      [ "$proto|$mtu|$mux|$handshake|$traffic|$low" = \
        'TCP|1400|MULTIPLEXING_OFF|HANDSHAKE_NO_WAIT|off|LOW_ENTROPY_MODE_OFF' ]
      ;;
    balanced)
      [ "$proto|$mtu|$mux|$handshake|$traffic|$low" = \
        'TCP|1400|MULTIPLEXING_OFF|HANDSHAKE_NO_WAIT|conservative|LOW_ENTROPY_MODE_OFF' ]
      ;;
    stealth)
      [ "$proto|$mtu|$mux|$handshake|$traffic|$low" = \
        'TCP|1400|MULTIPLEXING_OFF|HANDSHAKE_NO_WAIT|aggressive|LOW_ENTROPY_MODE_OFF' ]
      ;;
    *) return 1 ;;
  esac
}

infer_profile_from_values() {
  local candidate
  for candidate in iplc balanced stealth; do
    if profile_values_match "$candidate"; then
      printf '%s' "$candidate"
      return 0
    fi
  done
  printf 'custom'
}

apply_profile_values() {
  local selected
  selected="$(normalize_profile "${1:-}")" || return 1
  PROFILE="$selected"
  case "$selected" in
    iplc)
      PROTOCOL=TCP
      MTU=1400
      MTU_POLICY=safe
      MULTIPLEXING=MULTIPLEXING_OFF
      HANDSHAKE_MODE=HANDSHAKE_NO_WAIT
      TRAFFIC_PATTERN=off
      LOW_ENTROPY_MODE=LOW_ENTROPY_MODE_OFF
      ;;
    balanced)
      PROTOCOL=TCP
      MTU=1400
      MTU_POLICY=safe
      MULTIPLEXING=MULTIPLEXING_OFF
      HANDSHAKE_MODE=HANDSHAKE_NO_WAIT
      TRAFFIC_PATTERN=conservative
      LOW_ENTROPY_MODE=LOW_ENTROPY_MODE_OFF
      ;;
    stealth)
      PROTOCOL=TCP
      MTU=1400
      MTU_POLICY=safe
      MULTIPLEXING=MULTIPLEXING_OFF
      HANDSHAKE_MODE=HANDSHAKE_NO_WAIT
      TRAFFIC_PATTERN=aggressive
      # Low Entropy 始终是单独确认的高开销高级选项，预设不得自动开启。
      LOW_ENTROPY_MODE=LOW_ENTROPY_MODE_OFF
      ;;
    custom) ;;
  esac
}

apply_requested_profile_preserving_cli() {
  [ "${PROFILE_CLI:-0}" -eq 1 ] || return 0
  local cli_protocol="$PROTOCOL" cli_mtu_request="$MTU_REQUEST"
  local cli_mux="$MULTIPLEXING" cli_handshake="$HANDSHAKE_MODE"
  local cli_traffic="$TRAFFIC_PATTERN" cli_low="$LOW_ENTROPY_MODE"
  apply_profile_values "$PROFILE" || die "$(t '非法 Profile（iplc/balanced/stealth/custom）' \
    'Invalid profile (iplc/balanced/stealth/custom)')"
  [ "${PROTOCOL_CLI:-0}" -eq 0 ] || PROTOCOL="$cli_protocol"
  [ "${MTU_CLI:-0}" -eq 0 ] || MTU_REQUEST="$cli_mtu_request"
  [ "${MULTIPLEXING_CLI:-0}" -eq 0 ] || MULTIPLEXING="$cli_mux"
  [ "${HANDSHAKE_CLI:-0}" -eq 0 ] || HANDSHAKE_MODE="$cli_handshake"
  [ "${TRAFFIC_CLI:-0}" -eq 0 ] || TRAFFIC_PATTERN="$cli_traffic"
  [ "${LOW_ENTROPY_CLI:-0}" -eq 0 ] || LOW_ENTROPY_MODE="$cli_low"
}

profile_reconcile_metadata() {
  PROFILE="$(normalize_profile "${PROFILE:-custom}" 2>/dev/null || printf custom)"
  [ "$PROFILE" = custom ] && return 0
  profile_values_match "$PROFILE" || PROFILE=custom
}

choose_profile_interactive() {
  local input="" def=2
  case "$(normalize_profile "${PROFILE:-balanced}" 2>/dev/null || printf balanced)" in
    iplc) def=1 ;;
    stealth) def=3 ;;
    custom) def=4 ;;
  esac
  msg ""
  t '配置预设（真实参数仍会完整保存；之后单独修改参数会自动变为高级自定义）:' \
    'Configuration profile (full parameters are saved; later manual edits become Advanced Custom):'
  t '  1) IPLC / 专线性能 — IPLC、企业专线、明确允许使用的网络' \
    '  1) IPLC / Dedicated-line Performance — IPLC, enterprise lines, permitted networks'
  t '  2) 普通公网 — 普通 VPS / 公网环境' \
    '  2) General Public Network — ordinary VPS / public networks'
  t '  3) 强化伪装 — 更强 traffic-pattern；Low Entropy 仍默认关闭' \
    '  3) Enhanced Camouflage — stronger traffic-pattern; Low Entropy remains off'
  t '  4) 高级自定义 — 逐项配置全部高级参数' \
    '  4) Advanced Custom — configure every advanced parameter'
  read_tty input "$(t "请选择 [1-4，默认 ${def}]: " "Choose [1-4, default ${def}]: ")" || input=""
  input="${input:-$def}"
  case "$input" in
    1) apply_profile_values iplc ;;
    3) apply_profile_values stealth ;;
    4) PROFILE=custom ;;
    *) apply_profile_values balanced ;;
  esac
  t "已选 Profile: $(profile_label)" "Selected profile: $(profile_label)"
}

choose_protocol_interactive() {
  msg ""
  t '传输协议:' 'Transport protocol:'
  t '  1) TCP（推荐；Clash 设 udp: true 即可）' \
    '  1) TCP (recommended; Clash udp: true is enough)'
  t '  2) UDP' '  2) UDP'
  t '  3) TCP + UDP 双协议（UDP 端口 = TCP 端口 + 1）' \
    '  3) TCP + UDP dual (UDP port = TCP port + 1)'
  msg ""
  local choice=""
  read_tty choice "$(t '请选择协议 [1-3，默认 1]: ' 'Choose protocol [1-3, default 1]: ')" || choice="1"
  choice="${choice:-1}"
  case "$choice" in
    1|TCP|tcp) PROTOCOL="TCP" ;;
    2|UDP|udp) PROTOCOL="UDP" ;;
    3|BOTH|both|双协议) PROTOCOL="BOTH" ;;
    *)
      warn "$(t "无效选择「${choice}」，使用默认 TCP" "Invalid choice \"${choice}\", using TCP")"
      PROTOCOL="TCP"
      ;;
  esac
}

collect_advertise_endpoint_interactive() {
  local input="" candidate="" detected="" auto_selected=0
  local default_host="${ADVERTISE_HOST:-}" default_port="${ADVERTISE_PORT:-${PORT:-}}"
  if [ "${ADVERTISE_CLI:-0}" -eq 1 ]; then
    validate_advertise_endpoint || die "$(t '自定义客户端入口参数无效' \
      'Invalid custom client entry parameters')"
    [ -z "$ADVERTISE_PORT" ] || ADVERTISE_PORT="$(normalize_uint "$ADVERTISE_PORT")"
    return
  fi

  msg ""
  if [ -z "$default_host" ]; then
    detected="$(public_ip 2>/dev/null || true)"
    default_host="$detected"
  fi
  if [ -n "$detected" ]; then
    t "检测到服务器公网 IP: ${detected}" "Detected server public IP: ${detected}"
  fi
  t '客户端入口只用于节点展示/导出，不会修改 mita 监听、firewall 或 tc。' \
    'The client entry is only used in client exports; it never changes mita listeners, firewall, or tc.'
  t '如前面有 IPLC/NAT/端口映射，请在这里填写用户真正连接的入口；输入 auto 可恢复自动探测。' \
    'If IPLC/NAT/port mapping is in front, enter the endpoint clients really use; enter auto to restore auto detection.'

  while true; do
    input=""
    if [ -n "$default_host" ]; then
      read_tty input "$(t "客户端连接时使用的入口地址 [${default_host}]: " \
        "Client entry host [${default_host}]: ")" || input=""
    else
      read_tty input "$(t '客户端连接时使用的入口地址: ' \
        'Client entry host: ')" || input=""
    fi
    candidate="${input:-$default_host}"
    candidate="$(printf '%s' "$candidate" | tr -d '[:space:]')"
    if [ "$(printf '%s' "$candidate" | tr '[:upper:]' '[:lower:]')" = auto ]; then
      auto_selected=1
      ADVERTISE_HOST=""
      break
    fi
    if valid_advertise_host "$candidate"; then
      ADVERTISE_HOST="$candidate"
      break
    fi
    warn "$(t '入口地址无效，请重新输入 IPv4、IPv6 或域名' \
      'Invalid entry host; enter IPv4, IPv6, or a domain name')"
  done

  while true; do
    input=""
    read_tty input "$(t "客户端入口端口 [${default_port}]: " \
      "Client entry port [${default_port}]: ")" || input=""
    candidate="${input:-$default_port}"
    if [ "$auto_selected" -eq 1 ]; then
      if valid_advertise_port "$candidate"; then
        ADVERTISE_PORT=""
        break
      fi
    elif validate_advertise_endpoint_values "$ADVERTISE_HOST" "$candidate" "$PROTOCOL"; then
      ADVERTISE_PORT="$(normalize_uint "$candidate")"
      break
    fi
    warn "$(t '入口端口必须是 1-65535 的整数' \
      'Client entry port must be an integer from 1 to 65535')"
  done

  msg ""
  if [ "$auto_selected" -eq 1 ]; then
    t '客户端入口: 自动探测公网地址并使用实际监听端口' \
      'Client entry: auto-detected public address with the backend listen port'
  elif [ "$PROTOCOL" = "BOTH" ]; then
    t "客户端配置将展示: ${ADVERTISE_HOST}，TCP ${ADVERTISE_PORT} / UDP $((ADVERTISE_PORT + 1))" \
      "Client configs will show: ${ADVERTISE_HOST}, TCP ${ADVERTISE_PORT} / UDP $((ADVERTISE_PORT + 1))"
  else
    t "客户端配置将展示: ${ADVERTISE_HOST}:${ADVERTISE_PORT}" \
      "Client configs will show: ${ADVERTISE_HOST}:${ADVERTISE_PORT}"
  fi
  t "服务端仍使用实际监听端口 ${PORT}；自定义入口不修改 mita、防火墙或 tc 配置" \
    "The server still listens on ${PORT}; the custom entry does not change mita, firewall, or tc settings"
}

normalize_multiplexing() {
  case "$(printf '%s' "${1:-}" | tr '[:lower:]' '[:upper:]')" in
    OFF|0|NO|DISABLED|MULTIPLEXING_OFF) printf 'MULTIPLEXING_OFF' ;;
    LOW|MULTIPLEXING_LOW) printf 'MULTIPLEXING_LOW' ;;
    MIDDLE|MEDIUM|MULTIPLEXING_MIDDLE) printf 'MULTIPLEXING_MIDDLE' ;;
    HIGH|MULTIPLEXING_HIGH) printf 'MULTIPLEXING_HIGH' ;;
    *) return 1 ;;
  esac
}

normalize_handshake_mode() {
  case "$(printf '%s' "${1:-}" | tr '[:lower:]' '[:upper:]' | tr '-' '_')" in
    NO_WAIT|NOWAIT|0RTT|HANDSHAKE_NO_WAIT) printf 'HANDSHAKE_NO_WAIT' ;;
    STANDARD|WAIT|HANDSHAKE_STANDARD) printf 'HANDSHAKE_STANDARD' ;;
    *) return 1 ;;
  esac
}

normalize_low_entropy_mode() {
  case "$(printf '%s' "${1:-}" | tr '[:lower:]' '[:upper:]')" in
    OFF|0|NO|DISABLED|LOW_ENTROPY_MODE_OFF) printf 'LOW_ENTROPY_MODE_OFF' ;;
    56|MODE_56|LOW_ENTROPY_MODE_56) printf 'LOW_ENTROPY_MODE_56' ;;
    48|MODE_48|LOW_ENTROPY_MODE_48) printf 'LOW_ENTROPY_MODE_48' ;;
    40|MODE_40|LOW_ENTROPY_MODE_40) printf 'LOW_ENTROPY_MODE_40' ;;
    32|MODE_32|LOW_ENTROPY_MODE_32) printf 'LOW_ENTROPY_MODE_32' ;;
    *) return 1 ;;
  esac
}

low_entropy_label() {
  case "$(normalize_low_entropy_mode "${LOW_ENTROPY_MODE:-LOW_ENTROPY_MODE_OFF}" 2>/dev/null || true)" in
    LOW_ENTROPY_MODE_56) t '56（约 1.15 倍流量）' '56 (~1.15x traffic)' ;;
    LOW_ENTROPY_MODE_48) t '48（约 1.34 倍流量）' '48 (~1.34x traffic)' ;;
    LOW_ENTROPY_MODE_40) t '40（约 1.6 倍流量）' '40 (~1.6x traffic)' ;;
    LOW_ENTROPY_MODE_32) t '32（约 2 倍流量）' '32 (~2x traffic)' ;;
    *) t '关闭' 'Off' ;;
  esac
}

warn_low_entropy_client_compat() {
  [ "$(normalize_low_entropy_mode "${LOW_ENTROPY_MODE:-LOW_ENTROPY_MODE_OFF}" 2>/dev/null || true)" != "LOW_ENTROPY_MODE_OFF" ] || return 0
  warn "$(t \
    '低熵模式是较新的实验性能力；请确认客户端确实支持 lowEntropy。尚未适配的 mihomo 等客户端可能无法正确使用，不确定时请保持关闭并优先使用官方 mieru 客户端。' \
    'Low entropy is a newer experimental capability. Confirm that the client supports lowEntropy; clients such as mihomo builds without adaptation may not work correctly. Keep it off when unsure and prefer the official mieru client.')"
}

choose_client_modes_interactive() {
  local input="" def=1
  if [ "${MULTIPLEXING_CLI:-0}" -ne 1 ]; then
    case "$(normalize_multiplexing "${MULTIPLEXING:-MULTIPLEXING_OFF}" 2>/dev/null || true)" in
      MULTIPLEXING_LOW) def=2 ;;
      MULTIPLEXING_MIDDLE) def=3 ;;
      MULTIPLEXING_HIGH) def=4 ;;
      *) def=1 ;;
    esac
    msg ""
    t '多路复用模式（默认推荐关闭）:' 'Multiplexing mode (OFF recommended by default):'
    t '  1) MULTIPLEXING_OFF（推荐）' '  1) MULTIPLEXING_OFF (recommended)'
    t '  2) MULTIPLEXING_LOW' '  2) MULTIPLEXING_LOW'
    t '  3) MULTIPLEXING_MIDDLE' '  3) MULTIPLEXING_MIDDLE'
    t '  4) MULTIPLEXING_HIGH' '  4) MULTIPLEXING_HIGH'
    read_tty input "$(t "请选择 [1-4，默认 ${def}]: " "Choose [1-4, default ${def}]: ")" || input=""
    input="${input:-$def}"
    case "$input" in
      2) MULTIPLEXING="MULTIPLEXING_LOW" ;;
      3) MULTIPLEXING="MULTIPLEXING_MIDDLE" ;;
      4) MULTIPLEXING="MULTIPLEXING_HIGH" ;;
      *) MULTIPLEXING="MULTIPLEXING_OFF" ;;
    esac
  fi

  input=""
  def=1
  if [ "${HANDSHAKE_CLI:-0}" -ne 1 ]; then
    [ "$(normalize_handshake_mode "${HANDSHAKE_MODE:-HANDSHAKE_NO_WAIT}" 2>/dev/null || true)" = "HANDSHAKE_STANDARD" ] && def=2
    msg ""
    t '握手模式:' 'Handshake mode:'
    t '  1) HANDSHAKE_NO_WAIT（推荐，0-RTT）' '  1) HANDSHAKE_NO_WAIT (recommended, 0-RTT)'
    t '  2) HANDSHAKE_STANDARD' '  2) HANDSHAKE_STANDARD'
    read_tty input "$(t "请选择 [1-2，默认 ${def}]: " "Choose [1-2, default ${def}]: ")" || input=""
    input="${input:-$def}"
    case "$input" in
      2) HANDSHAKE_MODE="HANDSHAKE_STANDARD" ;;
      *) HANDSHAKE_MODE="HANDSHAKE_NO_WAIT" ;;
    esac
  fi

  msg ""
  t "客户端模式: ${MULTIPLEXING} / ${HANDSHAKE_MODE}" \
    "Client modes: ${MULTIPLEXING} / ${HANDSHAKE_MODE}"
}

choose_low_entropy_interactive() {
  local current input="" def=1 enabled_default="n"
  if [ "$(normalize_traffic_pattern "${TRAFFIC_PATTERN:-conservative}")" = "off" ]; then
    LOW_ENTROPY_MODE="LOW_ENTROPY_MODE_OFF"
    return 0
  fi
  if [ "${LOW_ENTROPY_CLI:-0}" -eq 1 ]; then
    warn_low_entropy_client_compat
    return 0
  fi

  current="$(normalize_low_entropy_mode "${LOW_ENTROPY_MODE:-LOW_ENTROPY_MODE_OFF}" 2>/dev/null || printf 'LOW_ENTROPY_MODE_OFF')"
  [ "$current" != "LOW_ENTROPY_MODE_OFF" ] && enabled_default="y"
  msg ""
  if [ "$enabled_default" = "y" ]; then
    read_tty input "$(t '是否启用低熵模式？会增加流量和 CPU 开销 [Y/n]: ' \
      'Enable low entropy mode? This increases traffic and CPU load [Y/n]: ')" || input=""
    input="${input:-y}"
  else
    read_tty input "$(t '是否启用低熵模式？会增加流量和 CPU 开销 [y/N]: ' \
      'Enable low entropy mode? This increases traffic and CPU load [y/N]: ')" || input=""
    input="${input:-n}"
  fi
  case "$(printf '%s' "$input" | tr '[:upper:]' '[:lower:]')" in
    y|yes|1|是) ;;
    *)
      LOW_ENTROPY_MODE="LOW_ENTROPY_MODE_OFF"
      t '低熵模式: 关闭（推荐默认）' 'Low entropy: Off (recommended default)'
      return 0
      ;;
  esac

  case "$current" in
    LOW_ENTROPY_MODE_48) def=2 ;;
    LOW_ENTROPY_MODE_40) def=3 ;;
    LOW_ENTROPY_MODE_32) def=4 ;;
    *) def=1 ;;
  esac
  msg ""
  t '低熵强度（数字越小，伪装越强，但开销越大）:' \
    'Low entropy strength (smaller means stronger disguise and more overhead):'
  t '  1) 56 —— 需要 Low Entropy 时优先考虑；约增加 15% 数据体积' \
    '  1) 56 — first choice when Low Entropy is needed; about 15% more data'
  t '  2) 48 —— 更强 Low Entropy；流量开销进一步增加（约 34%）' \
    '  2) 48 — stronger Low Entropy; higher traffic overhead (~34%)'
  t '  3) 40 —— 高开销高级模式（约 60%）' \
    '  3) 40 — high-overhead advanced mode (~60%)'
  t '  4) 32 —— 高开销高级模式（约 100%）' \
    '  4) 32 — high-overhead advanced mode (~100%)'
  t '性能优先（IPLC/明确允许 Mieru 的环境）应保持 OFF。' \
    'For performance-first IPLC or explicitly permitted networks, keep this OFF.'
  input=""
  read_tty input "$(t "请选择 [1-4，默认 ${def}]: " "Choose [1-4, default ${def}]: ")" || input=""
  input="${input:-$def}"
  case "$input" in
    2) LOW_ENTROPY_MODE="LOW_ENTROPY_MODE_48" ;;
    3) LOW_ENTROPY_MODE="LOW_ENTROPY_MODE_40" ;;
    4) LOW_ENTROPY_MODE="LOW_ENTROPY_MODE_32" ;;
    *) LOW_ENTROPY_MODE="LOW_ENTROPY_MODE_56" ;;
  esac
  t "低熵模式: $(low_entropy_label)" "Low entropy: $(low_entropy_label)"
  warn_low_entropy_client_compat
}

choose_traffic_pattern_interactive() {
  [ "${TRAFFIC_CLI:-0}" -eq 1 ] && return 0
  local cur def input="" enable_default="y"
  cur="$(normalize_traffic_pattern "${TRAFFIC_PATTERN:-conservative}")"
  [ "$cur" = "off" ] && enable_default="n"
  msg ""
  if [ "$enable_default" = "y" ]; then
    read_tty input "$(t '是否加入 traffic-pattern 流量伪装？[Y/n]: ' \
      'Include traffic-pattern obfuscation? [Y/n]: ')" || input=""
    input="${input:-y}"
  else
    read_tty input "$(t '是否加入 traffic-pattern 流量伪装？[y/N]: ' \
      'Include traffic-pattern obfuscation? [y/N]: ')" || input=""
    input="${input:-n}"
  fi
  case "$(printf '%s' "$input" | tr '[:upper:]' '[:lower:]')" in
    y|yes|1|是) ;;
    *)
      TRAFFIC_PATTERN="off"
      msg ""
      t '已选择不加入 traffic-pattern' 'traffic-pattern will not be included'
      return 0
      ;;
  esac

  def=1
  [ "$cur" = "aggressive" ] && def=2
  msg ""
  t 'traffic-pattern 主要用于改变流量特征，并不是性能优化功能（客户端无需与服务端一致）:' \
    'traffic-pattern changes traffic characteristics; it is not a performance feature (client need not match server):'
  t '  1) 保守 —— 可打印 Nonce + 末尾填充，额外开销较低（推荐）' \
    '  1) Conservative — printable nonce + end padding, lower extra overhead (recommended)'
  t '  2) 激进 —— 再加 TCP 分片 + 全量填充，更隐蔽但增加延迟/降速' \
    '  2) Aggressive — also TCP fragment + full padding, stealthier but slower'
  input=""
  read_tty input "$(t "请选择 [1-2，默认 ${def}]: " "Choose [1-2, default ${def}]: ")" || input=""
  input="${input:-$def}"
  case "$input" in
    2) TRAFFIC_PATTERN="aggressive" ;;
    *) TRAFFIC_PATTERN="conservative" ;;
  esac
  msg ""
  t "已选流量伪装: $(traffic_label)" "Traffic obfuscation: $(traffic_label)"
}

collect_config_interactive() {
  STAGE="交互配置"
  local requested_protocol="$PROTOCOL" requested_mtu="$MTU_REQUEST"
  local requested_mux="$MULTIPLEXING" requested_handshake="$HANDSHAKE_MODE"
  local requested_traffic="$TRAFFIC_PATTERN" requested_low="$LOW_ENTROPY_MODE"
  [ -n "$USERNAME" ] || USERNAME="$(random_token)"
  [ -n "$PASSWORD" ] || PASSWORD="$(random_token)"
  msg ""
  t '已自动生成代理凭据（安装完成后会再次显示）:' \
    'Proxy credentials auto-generated (shown again after install):'
  t "  用户名: ${USERNAME}" "  Username: ${USERNAME}"
  t "  密码:   ${PASSWORD}" "  Password: ${PASSWORD}"

  if [ "${PROFILE_CLI:-0}" -eq 1 ]; then
    apply_requested_profile_preserving_cli
  else
    choose_profile_interactive
    [ "${PROTOCOL_CLI:-0}" -eq 0 ] || PROTOCOL="$requested_protocol"
    [ "${MTU_CLI:-0}" -eq 0 ] || MTU_REQUEST="$requested_mtu"
    [ "${MULTIPLEXING_CLI:-0}" -eq 0 ] || MULTIPLEXING="$requested_mux"
    [ "${HANDSHAKE_CLI:-0}" -eq 0 ] || HANDSHAKE_MODE="$requested_handshake"
    [ "${TRAFFIC_CLI:-0}" -eq 0 ] || TRAFFIC_PATTERN="$requested_traffic"
    [ "${LOW_ENTROPY_CLI:-0}" -eq 0 ] || LOW_ENTROPY_MODE="$requested_low"
  fi

  if [ "$PROTOCOL_CLI" -eq 0 ] && [ "$PROFILE" = custom ]; then
    choose_protocol_interactive
  fi

  msg ""
  if [ -z "$PORT" ] && [ -z "$PORT_RANGE" ]; then
    local default_port input="" candidate="" base="" localip="" segment_hi=99
    localip="$(detect_local_ip)"
    [ "$PROTOCOL" = "BOTH" ] && segment_hi=98
    if base="$(derive_port_base)"; then
      if ! default_port="$(derive_port_from_ip)"; then
        warn "$(t "IP 尾号端口段 $((base + 1))-$((base + segment_hi)) 当前没有可用端口，回退全局随机端口" \
          "No available port in IP-derived range $((base + 1))-$((base + segment_hi)); falling back to a global random port")"
        default_port="$(random_available_port)" \
          || die "$(t '未找到可用监听端口' 'No available listen port found')"
      fi
      t "检测到本机 IP ${localip}，按尾号规则端口段 $((base + 1))-$((base + segment_hi))（${base} 留给 SSH，默认选择已校验的空闲端口）" \
        "Detected local IP ${localip}; range $((base + 1))-$((base + segment_hi)) (${base} reserved for SSH); default is a verified free port"
    else
      default_port="$(random_available_port)" \
        || die "$(t '未找到可用监听端口' 'No available listen port found')"
      warn "$(t "无法按 IP 尾号推导端口（IP=${localip:-未知}，尾号过小或无法识别），回退随机端口" \
        "Cannot derive port from IP last octet (IP=${localip:-unknown}); falling back to random port")"
    fi
    while true; do
      input=""
      read_tty input "$(t "监听端口 [${default_port}]: " "Listen port [${default_port}]: ")" || input=""
      candidate="${input:-$default_port}"
      if ! valid_port "$candidate"; then
        warn "$(t '非法端口，请重新输入' 'Invalid port; try again')"
        continue
      fi
      candidate="$(normalize_uint "$candidate")"
      if [ "$PROTOCOL" = "BOTH" ] && [ "$candidate" -ge 65535 ]; then
        warn "$(t '双协议需要主端口 ≤65534（UDP 使用主端口+1）' \
          'Dual protocol needs main port ≤65534 (UDP uses main port + 1)')"
        continue
      fi
      if ! port_available_for_mode "$candidate"; then
        warn "$(t "端口 ${candidate} 已被占用，请重新输入" \
          "Port ${candidate} is already in use; try again")"
        port_listener_details "$candidate"
        continue
      fi
      PORT="$candidate"
      [ -z "$input" ] && PORT_AUTO_SELECTED=1 || PORT_AUTO_SELECTED=0
      break
    done
    if [ -n "$base" ] && { [ "$PORT" -lt "$((base + 1))" ] || [ "$PORT" -gt "$((base + segment_hi))" ]; }; then
      warn "$(t "注意：端口 ${PORT} 不在 IP 尾号段 $((base + 1))-$((base + segment_hi)) 内，可能与按 IP 分配端口的约定冲突" \
        "Note: port ${PORT} is outside the IP last-octet range $((base + 1))-$((base + segment_hi)); may break the per-IP port convention")"
    fi
  elif [ -n "$PORT" ] && [ -n "$PORT_RANGE" ]; then
    die "$(t '不能同时指定端口与端口段' 'Cannot set both port and port range')"
  fi

  if [ "$PROTOCOL" = "BOTH" ] && [ -n "$PORT" ] && [ "$PORT" -ge 65535 ]; then
    die "$(t '双协议需要主端口 ≤65534（UDP 使用主端口+1）' \
      'Dual protocol needs main port ≤65534 (UDP uses main port + 1)')"
  fi
  msg ""
  t "已选协议: $(protocol_label)" "Selected protocol: $(protocol_label)"
  collect_advertise_endpoint_interactive
  if [ "$PROFILE" = custom ]; then
    choose_mtu_interactive
    choose_client_modes_interactive
    choose_traffic_pattern_interactive
    choose_low_entropy_interactive
  else
    [ "${MTU_CLI:-0}" -eq 0 ] || resolve_mtu_request
    t "预设参数: $(protocol_label) / MTU ${MTU} / ${MULTIPLEXING} / ${HANDSHAKE_MODE}" \
      "Preset parameters: $(protocol_label) / MTU ${MTU} / ${MULTIPLEXING} / ${HANDSHAKE_MODE}"
    t "Traffic Pattern: $(traffic_label)；Low Entropy: $(low_entropy_label)" \
      "Traffic Pattern: $(traffic_label); Low Entropy: $(low_entropy_label)"
  fi
  profile_reconcile_metadata
  ensure_traffic_seed
  validate_proxy_credentials
}

load_config_from_mita() {
  local desc bin bindings live_mtu=""
  local cli_user="$USERNAME" cli_password="$PASSWORD"
  local cli_port="$PORT" cli_port_range="$PORT_RANGE" cli_protocol="$PROTOCOL"
  local cli_advertise_host="$ADVERTISE_HOST" cli_advertise_port="$ADVERTISE_PORT"
  local cli_mtu_request="$MTU_REQUEST"
  load_install_state
  local state_user="$USERNAME" state_password="$PASSWORD"
  local state_port="$PORT" state_port_range="$PORT_RANGE" state_protocol="$PROTOCOL"
  local state_mtu="$MTU" state_mtu_policy="$MTU_POLICY"
  if users_isolated_mode; then
    users_sync_primary_globals
    PORT_RANGE=""
    MTU="$state_mtu"
    MTU_POLICY="$(normalize_mtu_policy "$state_mtu_policy" 2>/dev/null || printf 'safe')"
    [ "${USERNAME_CLI:-0}" -eq 1 ] && USERNAME="$cli_user"
    [ "${PASSWORD_CLI:-0}" -eq 1 ] && PASSWORD="$cli_password"
    [ "${PORT_CLI:-0}" -eq 1 ] && PORT="$cli_port"
    [ "${PORT_RANGE_CLI:-0}" -eq 1 ] && { PORT=""; PORT_RANGE="$cli_port_range"; }
    [ "${PROTOCOL_CLI:-0}" -eq 1 ] && PROTOCOL="$cli_protocol"
    if [ "${ADVERTISE_CLI:-0}" -eq 1 ]; then
      ADVERTISE_HOST="$cli_advertise_host"
      ADVERTISE_PORT="$cli_advertise_port"
    fi
    [ "${MTU_CLI:-0}" -eq 1 ] && MTU_REQUEST="$cli_mtu_request"
    validate_proxy_credentials || return 1
    return 0
  fi
  bin="$(mita_bin)"
  if ! [ -x "$bin" ]; then
    recover_deb_mita 2>/dev/null || true
    bin="$(mita_bin)"
  fi
  if ! [ -x "$bin" ]; then
    bail "$(t '未找到 mita 二进制，自动修复未成功；请重新运行脚本并选择「升级」重新安装' \
      'mita binary not found and auto-repair failed; re-run the script and choose Upgrade')" || return 1
  fi
  desc="$("$bin" describe config 2>/dev/null || true)"
  if [ -z "$desc" ]; then
    bail "$(t '无法读取服务端配置。请先使用「服务管理 → 状态」检查；若守护进程未运行: systemctl restart mita' \
      'Cannot read server config. Use 5) Status; if daemon is down: systemctl restart mita')" || return 1
  fi

  live_mtu="$(extract_mtu_from_describe "$desc" 2>/dev/null || true)"
  MTU="$state_mtu"
  MTU_POLICY="$(normalize_mtu_policy "$state_mtu_policy" 2>/dev/null || printf 'safe')"
  if valid_mtu "$live_mtu"; then
    MTU="$live_mtu"
    if ! grep -q '^MTU_POLICY=' "$MITA_STATE" 2>/dev/null || [ "$state_mtu" != "$live_mtu" ]; then
      if [ "$live_mtu" -eq 1400 ]; then
        MTU_POLICY="safe"
      else
        MTU_POLICY="custom"
      fi
    fi
  fi
  if [ "${MTU_CLI:-0}" -eq 1 ]; then
    MTU_REQUEST="$cli_mtu_request"
  fi

  USERNAME=""
  PASSWORD=""
  if ! command -v python3 >/dev/null 2>&1 \
     && [ -n "$state_user" ] && [ -n "$state_password" ]; then
    USERNAME="$state_user"
    PASSWORD="$state_password"
  else
    parse_user_from_describe "$desc" || true
  fi
  [ -n "$USERNAME" ] || USERNAME="$state_user"
  if [ -z "$PASSWORD" ] || [[ "$PASSWORD" == \** ]]; then
    PASSWORD="$state_password"
  fi
  if [ -z "$USERNAME" ] || [ -z "$PASSWORD" ] || [[ "$PASSWORD" == \** ]]; then
    load_credentials_fallback || true
  fi
  [ "${USERNAME_CLI:-0}" -eq 1 ] && USERNAME="$cli_user"
  [ "${PASSWORD_CLI:-0}" -eq 1 ] && PASSWORD="$cli_password"
  if [ -z "$USERNAME" ]; then
    bail "$(t '配置中缺少用户名' 'Missing username in config')" || return 1
  fi
  if [ -z "$PASSWORD" ]; then
    bail "$(t '密码已哈希存储，无法生成节点链接。请使用「重新配置」设置新密码' \
      'Password is hashed; use 2) Reconfigure to set a new password')" || return 1
  fi
  validate_proxy_credentials || return 1

  bindings="$(extract_bindings_from_describe "$desc")"
  PORT="$state_port"
  PORT_RANGE="$state_port_range"
  PROTOCOL="$state_protocol"
  if [ -n "$bindings" ]; then
    local pp proto p has_tcp=0 has_udp=0 tcp_port="" primary_port="" live_range=""
    PORT=""
    PORT_RANGE=""
    while IFS= read -r pp; do
      [ -n "$pp" ] || continue
      proto="${pp%%|*}"
      p="${pp#*|}"
      case "$proto" in
        TCP)
          has_tcp=1
          if [[ "$p" =~ ^[0-9]+$ ]]; then
            [ -n "$tcp_port" ] || tcp_port="$p"
            [ -n "$primary_port" ] || primary_port="$p"
          elif [[ "$p" == *-* ]] && [ -z "$live_range" ]; then
            live_range="$p"
          fi
          ;;
        UDP)
          has_udp=1
          if [[ "$p" =~ ^[0-9]+$ ]] && [ -z "$primary_port" ]; then
            primary_port="$p"
          elif [[ "$p" == *-* ]] && [ -z "$live_range" ]; then
            live_range="$p"
          fi
          ;;
      esac
    done <<< "$bindings"
    PORT="${tcp_port:-$primary_port}"
    PORT_RANGE="$live_range"
    if [ "$has_tcp" -gt 0 ] && [ "$has_udp" -gt 0 ]; then
      PROTOCOL="BOTH"
    elif [ "$has_udp" -gt 0 ]; then
      PROTOCOL="UDP"
    else
      PROTOCOL="TCP"
    fi
  fi
  [ "${PORT_CLI:-0}" -eq 1 ] && { PORT="$cli_port"; PORT_RANGE=""; }
  [ "${PORT_RANGE_CLI:-0}" -eq 1 ] && { PORT=""; PORT_RANGE="$cli_port_range"; }
  [ "${PROTOCOL_CLI:-0}" -eq 1 ] && PROTOCOL="$cli_protocol"
  if [ -n "$PORT_RANGE" ]; then
    warn "$(t "检测到旧端口段 ${PORT_RANGE}；v2 专属实例将使用其首端口，请在本次重配中确认" \
      "Legacy port range ${PORT_RANGE} detected; v2 dedicated mode will use its first port, confirm it during reconfigure")"
    PORT="${PORT_RANGE%-*}"
    PORT_RANGE=""
  fi
  # 旧安装：状态无 TRAFFIC_PATTERN 记录、且服务端配置本身无 trafficPattern 时，
  # 不在客户端配置/重配里凭空注入（保持与服务端一致）；显式 --traffic-pattern 优先
  if [ "${TRAFFIC_CLI:-0}" -ne 1 ] \
     && ! grep -q '^TRAFFIC_PATTERN=' "$MITA_STATE" 2>/dev/null \
     && ! printf '%s' "$desc" | grep -q '"trafficPattern"'; then
    TRAFFIC_PATTERN="off"
  fi
}

parse_user_from_describe() {
  local desc="$1" line
  [ -n "$desc" ] || return 1
  if command -v python3 >/dev/null 2>&1; then
    line="$(printf '%s' "$desc" | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(1)
users = data.get("users") or []
if not users:
    sys.exit(1)
u = users[0]
name = u.get("name", "") or ""
pwd = u.get("password", "") or ""
print(f"{name}\t{pwd}")
' 2>/dev/null)" || return 1
    USERNAME="${line%%$'\t'*}"
    PASSWORD="${line#*$'\t'}"
    [ -n "$USERNAME" ] && return 0
    return 1
  fi
  USERNAME="$(printf '%s' "$desc" | sed -n 's/.*"name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
  PASSWORD="$(printf '%s' "$desc" | sed -n 's/.*"password"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
  [ -n "$USERNAME" ] && [ -n "$PASSWORD" ]
}

# The state file intentionally sets USERNAME/PASSWORD inside a subshell; only the
# serialized line is consumed in the parent.
# shellcheck disable=SC2030,SC2031
load_credentials_fallback() {
  local line
  if [ -f "$MITA_STATE" ]; then
    state_file_is_secure "$MITA_STATE" || return 1
    line="$(
      (
        local USERNAME="" PASSWORD=""
        # shellcheck disable=SC1090
        source "$MITA_STATE" 2>/dev/null || true
        printf '%s\t%s' "${USERNAME:-}" "${PASSWORD:-}"
      )
    )"
    [ -z "$USERNAME" ] && USERNAME="${line%%$'\t'*}"
    if [ -z "$PASSWORD" ] || [[ "$PASSWORD" == \** ]]; then
      PASSWORD="${line#*$'\t'}"
    fi
  fi
  [ -n "$USERNAME" ] && [ -n "$PASSWORD" ] && [[ "$PASSWORD" != \** ]] && return 0
  if ! command -v python3 >/dev/null 2>&1; then
    return 1
  fi
  # users.json 是管理面的权威状态；安装状态损坏时也不应先从旧客户端导出恢复凭据。
  if users_state_exists && state_file_is_secure "$MITA_USERS_STATE"; then
    line="$(python3 -c '
import json,sys
d=json.load(open(sys.argv[1]))
users=d.get("users") or []
ordered=[u for u in users if u.get("enabled", True)] + [u for u in users if not u.get("enabled", True)]
for u in ordered:
    name=u.get("name") or ""
    password=u.get("password") or ""
    if name and password:
        print(f"{name}\t{password}")
        raise SystemExit(0)
raise SystemExit(1)
' "$MITA_USERS_STATE" 2>/dev/null || true)"
    [ -z "$USERNAME" ] && USERNAME="${line%%$'\t'*}"
    if [ -z "$PASSWORD" ] || [[ "$PASSWORD" == \** ]]; then
      PASSWORD="${line#*$'\t'}"
    fi
    [ -n "$USERNAME" ] && [ -n "$PASSWORD" ] && [[ "$PASSWORD" != \** ]] && return 0
  fi

  # 最后兜底才读取客户端文件，并按 mtime 取最新有效文件，避免恢复到旧密码。
  line="$(CLIENT_CURRENT_DIR="$(client_current_dir)" python3 - <<'PY' 2>/dev/null || true
import glob, json, os

paths = glob.glob(os.path.join(os.environ["CLIENT_CURRENT_DIR"], "*.json"))
paths += glob.glob("/root/mieru_client_*.json")
paths = sorted(set(paths), key=lambda p: os.path.getmtime(p), reverse=True)
for path in paths:
    try:
        data = json.load(open(path))
        if "profiles" in data:
            user = (data.get("profiles") or [{}])[0].get("user") or {}
        else:
            user = (data.get("users") or [{}])[0]
        name = user.get("name") or ""
        password = user.get("password") or ""
        if name and password:
            print(f"{name}\t{password}")
            raise SystemExit(0)
    except Exception:
        continue
raise SystemExit(1)
PY
)"
  [ -z "$USERNAME" ] && USERNAME="${line%%$'\t'*}"
  if [ -z "$PASSWORD" ] || [[ "$PASSWORD" == \** ]]; then
    PASSWORD="${line#*$'\t'}"
  fi
  [ -n "$USERNAME" ] && [ -n "$PASSWORD" ] && [[ "$PASSWORD" != \** ]]
}

collect_reconfigure_interactive() {
  STAGE="重新配置"
  load_config_from_mita
  msg ""
  t '【当前配置】' '[Current config]'
  t "  用户名: ${USERNAME}" "  Username: ${USERNAME}"
  t '  密码:   （已隐藏）' '  Password: (hidden)'
  t "  协议:   $(protocol_label)" "  Protocol: $(protocol_label)"
  t "  MTU:    ${MTU}（$(mtu_policy_label)）" \
    "  MTU:      ${MTU} ($(mtu_policy_label))"
  if [ -n "$PORT" ]; then
    t "  端口:   ${PORT}" "  Port:     ${PORT}"
  else
    t "  端口段: ${PORT_RANGE}" "  Port range: ${PORT_RANGE}"
  fi
  msg ""
  t '留空则保持当前值' 'Press Enter to keep current value'

  local input=""
  read_tty input "$(t "新用户名 [${USERNAME}]: " "New username [${USERNAME}]: ")" || input=""
  [ -n "$input" ] && USERNAME="$input"

  input=""
  read_tty_secret input "$(t '新密码（留空保持当前）: ' 'New password (Enter to keep current): ')" || input=""
  [ -n "$input" ] && PASSWORD="$input"

  if [ "$PROTOCOL_CLI" -eq 0 ]; then
    msg ""
    t '是否更改传输协议？' 'Change transport protocol?'
    t '  1) 保持当前' '  1) Keep current'
    t '  2) 重新选择' '  2) Choose again'
    input=""
    read_tty input "$(t '请选择 [1-2，默认 1]: ' 'Choose [1-2, default 1]: ')" || input="1"
    input="${input:-1}"
    if [ "$input" = "2" ]; then
      choose_protocol_interactive
    fi
  fi

  if [ -z "$PORT_RANGE" ]; then
    msg ""
    input=""
    read_tty input "$(t "新监听端口 [${PORT}]: " "New listen port [${PORT}]: ")" || input=""
    if [ -n "$input" ]; then
      PORT="$input"
      valid_port "$PORT" || die "$(t '非法端口' 'Invalid port')"
      PORT="$(normalize_uint "$PORT")"
    fi
  fi

  if [ "$PROTOCOL" = "BOTH" ] && [ -n "$PORT" ] && [ "$PORT" -ge 65535 ]; then
    die "$(t '双协议需要主端口 ≤65534' 'Dual protocol needs main port ≤65534')"
  fi
  collect_advertise_endpoint_interactive
  choose_mtu_interactive
  choose_client_modes_interactive
  choose_traffic_pattern_interactive
  choose_low_entropy_interactive
  ensure_traffic_seed
  validate_proxy_credentials
  msg ""
  t "将应用协议: $(protocol_label)" "Will apply protocol: $(protocol_label)"
}

ensure_config_noninteractive() {
  STAGE="参数校验"
  apply_requested_profile_preserving_cli
  [ -n "$PORT" ] && [ -n "$PORT_RANGE" ] && \
    die "$(t '--port 与 --port-range 不能同时使用' 'Cannot use --port and --port-range together')"
  [ -n "$USERNAME" ] || USERNAME="$(random_token)"
  [ -n "$PASSWORD" ] || PASSWORD="$(random_token)"
  validate_proxy_credentials
  PROTOCOL="$(normalize_protocol "$PROTOCOL")" || \
    die "$(t '非法协议（仅支持 TCP/UDP/BOTH）' \
      'Invalid protocol (only TCP/UDP/BOTH are supported)')"
  if [ -z "$PORT" ] && [ -z "$PORT_RANGE" ]; then
    PORT="$(select_available_port)" \
      || die "$(t '未找到可用监听端口' 'No available listen port found')"
    PORT_AUTO_SELECTED=1
  fi
  if [ -n "$PORT" ]; then
    valid_port "$PORT" || die "$(t '非法端口' 'Invalid port')"
    PORT="$(normalize_uint "$PORT")"
    local _base
    if _base="$(derive_port_base 2>/dev/null)" \
       && { [ "$PORT" -lt "$((_base + 1))" ] || [ "$PORT" -gt "$((_base + 99))" ]; }; then
      warn "$(t "端口 ${PORT} 不在本机 IP 尾号段 $((_base + 1))-$((_base + 99)) 内（如非本机 IP 可忽略）" \
        "Port ${PORT} is outside this host's IP last-octet range $((_base + 1))-$((_base + 99)) (ignore if intended)")"
    fi
  fi
  if [ -n "$PORT_RANGE" ]; then
    die "$(t 'v2 用户专属实例不支持 --port-range，请使用单个 --port' \
      'v2 dedicated user instances do not support --port-range; use one --port')"
  fi
  if [ "$PROTOCOL" = "BOTH" ] && [ -n "$PORT" ] && [ "$PORT" -ge 65535 ]; then
    die "$(t '双协议需要主端口 ≤65534' 'Dual protocol needs main port ≤65534')"
  fi
  validate_advertise_endpoint || die "$(t '自定义客户端入口参数无效' \
    'Invalid custom client entry parameters')"
  [ -z "$ADVERTISE_PORT" ] || ADVERTISE_PORT="$(normalize_uint "$ADVERTISE_PORT")"
  resolve_mtu_request || return 1
  [ "${MTU_CLI:-0}" -eq 1 ] && print_mtu_selection
  TRAFFIC_PATTERN="$(normalize_traffic_pattern "$TRAFFIC_PATTERN")" || \
    die "$(t '非法 traffic-pattern 模式' 'Invalid traffic-pattern mode')"
  LOW_ENTROPY_MODE="$(normalize_low_entropy_mode "$LOW_ENTROPY_MODE")" || \
    die "$(t '非法低熵模式' 'Invalid low entropy mode')"
  [ "$TRAFFIC_PATTERN" != "off" ] || LOW_ENTROPY_MODE="LOW_ENTROPY_MODE_OFF"
  warn_low_entropy_client_compat
  MULTIPLEXING="$(normalize_multiplexing "$MULTIPLEXING")" || \
    die "$(t '非法 multiplexing 模式' 'Invalid multiplexing mode')"
  HANDSHAKE_MODE="$(normalize_handshake_mode "$HANDSHAKE_MODE")" || \
    die "$(t '非法 handshake mode' 'Invalid handshake mode')"
  profile_reconcile_metadata
  ensure_traffic_seed
}

normalize_traffic_pattern() {
  case "$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')" in
    off|none|no|0|disable|disabled|close|关) printf 'off' ;;
    aggressive|aggr|full|high|强|激进|2) printf 'aggressive' ;;
    conservative|cons|safe|low|保守|1) printf 'conservative' ;;
    *) return 1 ;;
  esac
}

traffic_label() {
  case "$(normalize_traffic_pattern "${TRAFFIC_PATTERN:-conservative}")" in
    off) t '关闭' 'Off' ;;
    aggressive) t '激进' 'Aggressive' ;;
    *) t '保守' 'Conservative' ;;
  esac
}

random_seed() {
  local s=""
  if [ -r /dev/urandom ] && command -v od >/dev/null 2>&1; then
    s="$(od -An -N4 -tu4 /dev/urandom 2>/dev/null | tr -dc '0-9')"
  fi
  [ -n "$s" ] || s=$(( (RANDOM << 15) | RANDOM ))
  printf '%s' "$(( s % 2147483647 ))"
}

# 流量模式自 mita v3.28.0 起支持；旧二进制不识别该字段，需跳过以免 apply 失败
mita_supports_traffic_pattern() {
  local v
  v="$(installed_version 2>/dev/null || true)"
  [ -n "$v" ] || return 1
  [ "$(printf '%s\n%s' "3.28.0" "$v" | sort -V 2>/dev/null | head -n1)" = "3.28.0" ]
}

mita_supports_low_entropy() {
  local v
  v="$(installed_version 2>/dev/null || true)"
  [ -n "$v" ] || return 1
  [ "$(printf '%s\n%s' "3.35.0" "$v" | sort -V 2>/dev/null | head -n1)" = "3.35.0" ]
}

ensure_traffic_seed() {
  [ "$(normalize_traffic_pattern "${TRAFFIC_PATTERN:-conservative}")" = "off" ] && return 0
  [ -n "$TRAFFIC_SEED" ] && return 0
  TRAFFIC_SEED="$(random_seed)"
}

# 选了流量伪装但当前 mita 过旧不支持时给出明确提示（须在二进制就绪后调用）
warn_traffic_unsupported() {
  [ "$(normalize_traffic_pattern "${TRAFFIC_PATTERN:-conservative}")" = "off" ] && return 0
  mita_supports_traffic_pattern && return 0
  warn "$(t '当前 mita 版本不支持流量伪装（需 ≥3.28.0），本次不会写入 trafficPattern；如需启用请先执行「升级」' \
    'Current mita does not support traffic obfuscation (needs >=3.28.0); trafficPattern will be skipped. Use 3) Upgrade to enable.')"
  TRAFFIC_PATTERN="off"
  LOW_ENTROPY_MODE="LOW_ENTROPY_MODE_OFF"
}

warn_low_entropy_unsupported() {
  [ "$(normalize_low_entropy_mode "${LOW_ENTROPY_MODE:-LOW_ENTROPY_MODE_OFF}" 2>/dev/null || true)" = "LOW_ENTROPY_MODE_OFF" ] && return 0
  mita_supports_low_entropy && return 0
  warn "$(t '当前 mita 版本不支持低熵模式（需要 ≥3.35.0），本次将关闭低熵；请先升级后再启用' \
    'Current mita does not support low entropy mode (needs >=3.35.0); it will be disabled. Upgrade first to enable it.')"
  LOW_ENTROPY_MODE="LOW_ENTROPY_MODE_OFF"
}

# 输出缩进后的 "trafficPattern": {...} 片段；off 或旧版 mita 时输出空
traffic_pattern_json() {
  local ind="${1:-  }"
  local level seed low_entropy_section=""
  level="$(normalize_traffic_pattern "${TRAFFIC_PATTERN:-conservative}")"
  [ "$level" = "off" ] && return 0
  mita_supports_traffic_pattern || return 0
  seed="${TRAFFIC_SEED:-0}"
  if mita_supports_low_entropy; then
    low_entropy_section="${ind}  \"lowEntropy\": { \"mode\": \"$(normalize_low_entropy_mode "${LOW_ENTROPY_MODE:-LOW_ENTROPY_MODE_OFF}")\" },
"
  fi
  if [ "$level" = "aggressive" ]; then
    cat <<EOF
${ind}"trafficPattern": {
${ind}  "seed": ${seed},
${ind}  "unlockAll": false,
${low_entropy_section}${ind}  "tcpFragment": { "enable": true, "maxSleepMs": 8 },
${ind}  "nonce": { "type": "NONCE_TYPE_PRINTABLE", "applyToAllUDPPacket": true, "minLen": 6, "maxLen": 12 },
${ind}  "padding": { "maxMiddlePaddingLen": 64, "maxEndPaddingLen": 255 }
${ind}}
EOF
  else
    cat <<EOF
${ind}"trafficPattern": {
${ind}  "seed": ${seed},
${ind}  "unlockAll": false,
${low_entropy_section}${ind}  "nonce": { "type": "NONCE_TYPE_PRINTABLE", "applyToAllUDPPacket": true, "minLen": 4, "maxLen": 8 },
${ind}  "padding": { "maxMiddlePaddingLen": 0, "maxEndPaddingLen": 128 }
${ind}}
EOF
  fi
}

write_server_config() {
  # 首次安装兼容路径；完成后立即迁移到每用户一个配置/实例。
  if [ "${MULTI_USER_MODE:-0}" -eq 1 ] && users_state_exists && [ "$(users_count)" -gt 0 ]; then
    write_server_config_multi
    return
  fi
  local cfg bindings="" proto pp tp tp_section="" user_json password_json
  cfg="$(mktemp_file .json)"
  user_json="$(json_string "$USERNAME")"
  password_json="$(json_string "$PASSWORD")"
  while IFS= read -r pp; do
    proto="${pp%%|*}"
    local p="${pp#*|}"
    local binding
    if [ -n "$PORT" ]; then
      binding=$(cat <<EOB
    {
      "port": ${p},
      "protocol": "${proto}"
    }
EOB
)
    else
      binding=$(cat <<EOB
    {
      "portRange": "${p}",
      "protocol": "${proto}"
    }
EOB
)
    fi
    if [ -n "$bindings" ]; then
      bindings="${bindings},
${binding}"
    else
      bindings="${binding}"
    fi
  done < <(port_protocol_pairs)
  ensure_traffic_seed
  tp="$(traffic_pattern_json '  ')"
  [ -n "$tp" ] && tp_section=",
${tp}"
  cat >"$cfg" <<EOF
{
  "portBindings": [
${bindings}
  ],
  "users": [
    {
      "name": ${user_json},
      "password": ${password_json}
    }
  ],
  "loggingLevel": "INFO",
  "mtu": ${MTU}${tp_section}
}
EOF
  printf '%s' "$cfg"
}

# ---------- Snell v4/v5 multi-instance engine ----------

snell_state_path() {
  local id="${1:-}"
  [[ "$id" =~ ^s[0-9a-f]{16}$ ]] || return 1
  printf '%s/%s.json' "$NOBRAND_SNELL_STATE_DIR" "$id"
}

snell_config_path() {
  local id="${1:-}"
  [[ "$id" =~ ^s[0-9a-f]{16}$ ]] || return 1
  printf '%s/%s.conf' "$NOBRAND_SNELL_CONFIG_DIR" "$id"
}

snell_state_exists() {
  local path
  path="$(snell_state_path "$1")" || return 1
  [ -s "$path" ] && jq empty "$path" >/dev/null 2>&1
}

snell_state_field() {
  local id="$1" field="$2" path
  path="$(snell_state_path "$id")" || return 1
  snell_state_exists "$id" || return 1
  jq -r --arg field "$field" \
    'if has($field) and .[$field] != null then .[$field] else empty end' "$path"
}

snell_instance_ids() {
  local path id
  for path in "$NOBRAND_SNELL_STATE_DIR"/*.json; do
    [ -f "$path" ] || continue
    id="$(basename "$path" .json)"
    [[ "$id" =~ ^s[0-9a-f]{16}$ ]] || continue
    jq -e --arg id "$id" '.instance_id == $id and (.version == 4 or .version == 5)' \
      "$path" >/dev/null 2>&1 || continue
    printf '%s\n' "$id"
  done
}

snell_find_id_by_name() {
  local expected="${1:-}" id
  [ -n "$expected" ] || return 1
  while IFS= read -r id; do
    [ "$(snell_state_field "$id" name 2>/dev/null || true)" = "$expected" ] || continue
    printf '%s' "$id"
    return 0
  done < <(snell_instance_ids)
  return 1
}

snell_resolve_target_id() {
  local target="${1:-}" ids count major
  if [[ "$target" =~ ^s[0-9a-f]{16}$ ]] && snell_state_exists "$target"; then
    major="$(snell_state_field "$target" version 2>/dev/null || true)"
    case "$major" in 4|5) ;; *) return 1 ;; esac
    printf '%s' "$target"
    return 0
  fi
  if [ -n "$target" ]; then
    snell_find_id_by_name "$target"
    return $?
  fi
  ids="$(snell_instance_ids)"
  count="$(printf '%s\n' "$ids" | sed '/^$/d' | wc -l | tr -d '[:space:]')"
  [ "$count" -eq 1 ] || return 1
  printf '%s' "$ids"
}

snell_valid_name() {
  local value="${1:-}"
  valid_proxy_identity_part "$value" || return 1
  case "$value" in *'|'*|*$'\t'*|*$'\n'*|*$'\r'*) return 1 ;; esac
}

snell_valid_psk() {
  local value="${1:-}"
  [ "${#value}" -ge 8 ] && [ "${#value}" -le 128 ] || return 1
  [[ "$value" =~ ^[A-Za-z0-9._~+/@:=,-]+$ ]]
}

snell_generate_psk() {
  local value
  value="$(openssl rand -base64 24 2>/dev/null | tr -d '\r\n')"
  snell_valid_psk "$value" || value="$(openssl rand -hex 24 2>/dev/null || random_token)"
  snell_valid_psk "$value" || return 1
  printf '%s' "$value"
}

snell_generate_instance_id() {
  local id attempt=0
  while [ "$attempt" -lt 64 ]; do
    id="s$(openssl rand -hex 8 2>/dev/null || true)"
    [[ "$id" =~ ^s[0-9a-f]{16}$ ]] || {
      id="s$(printf '%016x' "$((RANDOM * 32768 + RANDOM))")"
    }
    if ! snell_state_exists "$id"; then
      printf '%s' "$id"
      return 0
    fi
    attempt=$((attempt + 1))
  done
  return 1
}

snell_release_status_for_version() {
  local version
  version="$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')"
  case "$version" in
    *rc*) printf RC ;;
    *beta*|v*b[0-9]*|*.*.*b[0-9]*) printf Beta ;;
    *alpha*|v*a[0-9]*|*.*.*a[0-9]*) printf Experimental ;;
    *[!0-9.v]*) printf Experimental ;;
    *) printf Stable ;;
  esac
}

snell_generate_state() {
  local output="$1" id="$2" name="$3" major="$4" psk="$5" listen_host="$6" listen_port="$7"
  local advertise_mode="$8" advertise_host="$9" advertise_port="${10}" created_at="${11:-}"
  local quic_proxy_enabled="${12:-false}"
  local runtime_version runtime_status updated_at
  case "$major" in 4|5) ;; *) return 1 ;; esac
  runtime_version="$(snell_runtime_release_version "$major" 2>/dev/null || printf unknown)"
  runtime_status="$(snell_runtime_release_status "$major" 2>/dev/null || snell_release_status_for_version "$runtime_version")"
  [ -n "$created_at" ] || created_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  updated_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  jq -n --arg id "$id" --arg name "$name" --arg version "$major" --arg psk "$psk" \
    --arg listen_host "$listen_host" --arg listen_port "$listen_port" \
    --arg advertise_mode "$advertise_mode" --arg advertise_host "$advertise_host" \
    --arg advertise_port "$advertise_port" --arg runtime_version "$runtime_version" \
    --arg runtime_status "$runtime_status" --arg created_at "$created_at" --arg updated_at "$updated_at" \
    --argjson quic_proxy_enabled "$quic_proxy_enabled" '
      {
        protocol:"snell",
        instance_id:$id,
        name:$name,
        version:($version|tonumber),
        psk:$psk,
        listen_host:$listen_host,
        listen_port:($listen_port|tonumber),
        transport:"tcp",
        advertise_mode:$advertise_mode,
        advertise_host:$advertise_host,
        advertise_port:(if $advertise_port=="" then "" else ($advertise_port|tonumber) end),
        enabled:true,
        quic_proxy_enabled:$quic_proxy_enabled,
        managed_udp:$quic_proxy_enabled,
        runtime_version:$runtime_version,
        runtime_status:$runtime_status,
        created_at:$created_at,
        updated_at:$updated_at
      }
    ' >"$output"
}

snell_config_matches_state() {
  local id="$1" state config
  state="$(snell_state_path "$id")" || return 1
  config="$(snell_config_path "$id")" || return 1
  [ -s "$state" ] && [ -s "$config" ] || return 1
  python3 - "$state" "$config" <<'PY'
import json
import sys

state=json.load(open(sys.argv[1], encoding="utf-8"))
values={}
section=""
for raw in open(sys.argv[2], encoding="utf-8"):
    line=raw.strip()
    if not line or line.startswith("#") or line.startswith(";"):
        continue
    if line.startswith("[") and line.endswith("]"):
        section=line[1:-1]
        continue
    if "=" not in line:
        raise SystemExit(1)
    key,value=(part.strip() for part in line.split("=",1))
    values[(section,key)]=value
expected="%s:%s" % (state.get("listen_host"), state.get("listen_port"))
if values.get(("snell-server","listen")) != expected:
    raise SystemExit(1)
if values.get(("snell-server","psk")) != state.get("psk"):
    raise SystemExit(1)
version=int(state.get("version"))
if version in (4,5):
    if values.get(("snell-server","ipv6")) != "false":
        raise SystemExit(1)
else:
    raise SystemExit(1)
PY
}

snell_quic_proxy_enabled() {
  local id="$1"
  [ "$(snell_state_field "$id" version 2>/dev/null || true)" = 5 ] || return 1
  [ "$(snell_state_field "$id" quic_proxy_enabled 2>/dev/null || printf false)" = true ]
}

snell_managed_udp_enabled() {
  local id="$1"
  [ "$(snell_state_field "$id" version 2>/dev/null || true)" = 5 ] || return 1
  [ "$(snell_state_field "$id" managed_udp 2>/dev/null || printf false)" = true ]
}

snell_quic_state_consistent() {
  local id="$1" quic managed
  quic="$(snell_state_field "$id" quic_proxy_enabled 2>/dev/null || printf false)"
  managed="$(snell_state_field "$id" managed_udp 2>/dev/null || printf false)"
  case "$quic:$managed" in false:false|true:true) return 0 ;; *) return 1 ;; esac
}

snell_firewall_pairs() {
  local id="$1" port
  port="$(snell_state_field "$id" listen_port)" || return 1
  printf 'TCP|%s\n' "$port"
  snell_managed_udp_enabled "$id" && printf 'UDP|%s\n' "$port"
  return 0
}

snell_install_port_available() {
  local port="$1"
  nb_port_available_for_transport "$port" TCP || return 1
  [ "${SNELL_QUIC_PROXY:-off}" != on ] || nb_port_available_for_transport "$port" UDP
}

snell_select_available_install_port() {
  local ip bounds lo hi selected attempt=0 random_value
  [ "${SNELL_QUIC_PROXY:-off}" = on ] || { nb_select_available_port TCP; return; }
  ip="$(nb_detect_local_ipv4 2>/dev/null || true)"
  if bounds="$(nb_tail_port_bounds "$ip" 2>/dev/null)"; then
    lo="${bounds%%|*}"; hi="${bounds#*|}"
    if selected="$(nb_scan_port_span "$lo" "$hi" snell_install_port_available)"; then
      printf '%s' "$selected"
      return 0
    fi
  fi
  while [ "$attempt" -lt 512 ]; do
    random_value="$(openssl rand -hex 2 2>/dev/null || true)"
    if [[ "$random_value" =~ ^[0-9a-fA-F]{4}$ ]]; then
      selected=$((1025 + 16#$random_value % (65535 - 1025 + 1)))
    else
      selected=$((1025 + RANDOM % (65535 - 1025 + 1)))
    fi
    snell_install_port_available "$selected" && { printf '%s' "$selected"; return 0; }
    attempt=$((attempt + 1))
  done
  return 1
}

snell_effective_endpoint() {
  local id="$1" mode host advertise_port listen_port effective_host effective_port
  mode="$(snell_state_field "$id" advertise_mode)"
  host="$(snell_state_field "$id" advertise_host)"
  advertise_port="$(snell_state_field "$id" advertise_port)"
  listen_port="$(snell_state_field "$id" listen_port)"
  effective_host="$(nb_effective_advertise_host "$mode" "$host")"
  effective_port="$(nb_effective_advertise_port "$mode" "$advertise_port" "$listen_port")"
  printf '%s|%s' "$effective_host" "$effective_port"
}

snell_state_set_enabled() {
  local id="$1" enabled="$2" path tmp
  path="$(snell_state_path "$id")" || return 1
  tmp="$(mktemp_file .json)" || return 1
  if ! jq --argjson enabled "$enabled" --arg updated "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      '.enabled=$enabled | .updated_at=$updated' "$path" >"$tmp" \
     || ! nb_atomic_install_file "$tmp" "$path" 0600; then
    rm -f "$tmp"
    return 1
  fi
  rm -f "$tmp"
}

snell_collect_install_requests() {
  local interactive="$1" detected="" owner quic_choice=""
  case "${SNELL_VERSION:-5}" in 4|5) ;; *) die 'Snell 只支持 v4、v5' ;; esac
  snell_platform_supported "$SNELL_VERSION" \
    || die "当前 OS/arch 不支持官方 Snell v${SNELL_VERSION} runtime"
  if [ -z "${SNELL_NAME:-}" ]; then
    if [ "$interactive" -eq 1 ]; then
      read_tty SNELL_NAME "$(t "节点名 [snell-v${SNELL_VERSION}]: " "Node name [snell-v${SNELL_VERSION}]: ")" || SNELL_NAME=""
    fi
    SNELL_NAME="${SNELL_NAME:-snell-v${SNELL_VERSION}}"
  fi
  snell_valid_name "$SNELL_NAME" || die 'Snell 节点名无效（1-64 字符且不能含控制字符或 |）'
  [ -z "$(snell_find_id_by_name "$SNELL_NAME" 2>/dev/null || true)" ] || die "Snell 节点名已存在: $SNELL_NAME"
  if [ -z "${PORT:-}" ]; then
    PORT="$(nb_select_available_port TCP)" || die '未找到可用 Snell TCP 端口'
    PORT_AUTO_SELECTED=1
  else
    nb_valid_port "$PORT" || die 'Snell 端口必须是 1-65535'
    PORT="$(normalize_uint "$PORT")"
    nb_warn_if_outside_recommended_range "$PORT"
    if ! nb_port_available_for_transport "$PORT" TCP; then
      warn "Snell TCP/${PORT} 已占用"
      nb_describe_port_conflict TCP "$PORT"
      return 1
    fi
  fi
  if [ -z "${SNELL_PSK:-}" ]; then
    SNELL_PSK="$(snell_generate_psk)" || die '无法生成 Snell PSK'
  fi
  snell_valid_psk "$SNELL_PSK" \
    || die 'Snell PSK 必须为 8-128 位安全 ASCII（字母、数字或 ._~+/@:=,-）'
  if [ "$SNELL_VERSION" = 5 ]; then
    if [ "$interactive" -eq 1 ] && [ "${SNELL_QUIC_CLI:-0}" -eq 0 ]; then
      msg ''
      msg '是否启用 Snell v5 QUIC Proxy Mode？'
      msg '  1) 否 [默认 / 推荐兼容]'
      msg '  2) 是 [同时开放 UDP，同端口]'
      read_tty quic_choice "$(t '请选择 [1]: ' 'Choose [1]: ')" || quic_choice=""
      case "$quic_choice" in
        ""|1) SNELL_QUIC_PROXY=off ;;
        2) SNELL_QUIC_PROXY=on ;;
        *) die 'QUIC Proxy Mode 选择无效' ;;
      esac
    else
      SNELL_QUIC_PROXY="${SNELL_QUIC_PROXY:-off}"
    fi
  else
    [ "${SNELL_QUIC_PROXY:-off}" != on ] || die 'Snell v4 不支持 QUIC Proxy Mode'
    SNELL_QUIC_PROXY=off
  fi
  case "$SNELL_QUIC_PROXY" in on|off) ;; *) die 'QUIC Proxy Mode 只支持 on 或 off' ;; esac
  if [ "$SNELL_QUIC_PROXY" = on ] && ! nb_port_available_for_transport "$PORT" UDP; then
    if [ "${PORT_AUTO_SELECTED:-0}" -eq 1 ]; then
      PORT="$(snell_select_available_install_port)" || die '未找到同时可用的 Snell v5 TCP/UDP 同号端口'
    else
      warn "Snell v5 QUIC 需要同号 UDP/${PORT}，但该端口已占用"
      nb_describe_port_conflict UDP "$PORT"
      return 1
    fi
  fi
  detected="$(public_ip 2>/dev/null || true)"
  if [ "$interactive" -eq 1 ] && [ "${ADVERTISE_CLI:-0}" -eq 0 ]; then
    nb_collect_advertise_endpoint_interactive "Snell v${SNELL_VERSION}" "$PORT"
  else
    nb_require_explicit_endpoint_noninteractive
  fi
  nb_validate_advertise_endpoint "$ADVERTISE_HOST" "$ADVERTISE_PORT" TCP \
    || die 'Snell Display Endpoint 无效'
  if [ -n "$ADVERTISE_HOST" ]; then
    owner="$(nb_endpoint_conflict_owner TCP "$ADVERTISE_HOST" "$ADVERTISE_PORT" '' 2>/dev/null || true)"
    [ -z "$owner" ] || die "Snell Display Endpoint 与 ${owner} 冲突"
    if [ "$SNELL_QUIC_PROXY" = on ]; then
      owner="$(nb_endpoint_conflict_owner UDP "$ADVERTISE_HOST" "$ADVERTISE_PORT" '' 2>/dev/null || true)"
      [ -z "$owner" ] || die "Snell QUIC Display Endpoint 与 ${owner} 冲突"
    fi
  fi
  [ -z "$detected" ] || :
}

snell_install_rollback() {
  local id="$1" close_pairs="${2:-}"
  snell_remove_service "$id" >/dev/null 2>&1 || true
  [ -z "$close_pairs" ] || nb_firewall_close_pairs "$close_pairs" >/dev/null 2>&1 || true
  rm -f "$(snell_state_path "$id" 2>/dev/null || true)" \
    "$(snell_config_path "$id" 2>/dev/null || true)"
}

install_snell() {
  local interactive=0 id config_tmp state_tmp mode firewall_pairs new_pairs=""
  local tcp_was_owned=0 udp_was_owned=0
  [ "${YES:-0}" -eq 1 ] || interactive=1
  nobrand_prepare_common
  snell_collect_install_requests "$interactive"
  snell_install_runtime "$SNELL_VERSION" 0 || return 1
  admin_lock_acquire || return 1
  id="$(snell_generate_instance_id)" || { admin_lock_release; return 1; }
  if ! snell_install_port_available "$PORT"; then
    warn "提交前发现 TCP/${PORT} 已被其它实例或进程占用"
    nb_describe_port_conflict TCP "$PORT"
    admin_lock_release
    return 1
  fi
  config_tmp="$(mktemp_file .conf)" || { admin_lock_release; return 1; }
  state_tmp="$(mktemp_file .json)" || { rm -f "$config_tmp"; admin_lock_release; return 1; }
  mode="$(nb_endpoint_mode_from_values "$ADVERTISE_HOST")"
  firewall_pairs="TCP|${PORT}"
  [ "$SNELL_QUIC_PROXY" != on ] || firewall_pairs="${firewall_pairs}"$'\n'"UDP|${PORT}"
  if ! snell_generate_server_config "$config_tmp" "$SNELL_VERSION" 0.0.0.0 "$PORT" "$SNELL_PSK" \
     || ! snell_generate_state "$state_tmp" "$id" "$SNELL_NAME" "$SNELL_VERSION" "$SNELL_PSK" \
          0.0.0.0 "$PORT" "$mode" "$ADVERTISE_HOST" "$ADVERTISE_PORT" "" \
          "$([ "$SNELL_QUIC_PROXY" = on ] && printf true || printf false)" \
     || ! snell_config_matches_state_files "$state_tmp" "$config_tmp"; then
    rm -f "$config_tmp" "$state_tmp"
    admin_lock_release
    return 1
  fi
  nb_firewall_binding_owned TCP "$PORT" && tcp_was_owned=1
  nb_firewall_binding_owned UDP "$PORT" && udp_was_owned=1
  if ! nb_atomic_install_file "$config_tmp" "$(snell_config_path "$id")" 0600 \
     || ! nb_atomic_install_file "$state_tmp" "$(snell_state_path "$id")" 0600 \
     || ! snell_install_service_runtime \
     || ! snell_ensure_openrc_service "$id" \
     || ! nb_firewall_open_pairs "$firewall_pairs"; then
    rm -f "$config_tmp" "$state_tmp"
    nb_firewall_binding_owned TCP "$PORT" && [ "$tcp_was_owned" -eq 0 ] \
      && new_pairs="TCP|${PORT}"
    nb_firewall_binding_owned UDP "$PORT" && [ "$udp_was_owned" -eq 0 ] \
      && new_pairs="${new_pairs}${new_pairs:+$'\n'}UDP|${PORT}"
    snell_install_rollback "$id" "$new_pairs"
    admin_lock_release
    return 1
  fi
  rm -f "$config_tmp" "$state_tmp"
  nb_firewall_binding_owned TCP "$PORT" && [ "$tcp_was_owned" -eq 0 ] \
    && new_pairs="TCP|${PORT}"
  nb_firewall_binding_owned UDP "$PORT" && [ "$udp_was_owned" -eq 0 ] \
    && new_pairs="${new_pairs}${new_pairs:+$'\n'}UDP|${PORT}"
  if ! snell_service_action "$id" start \
     || ! snell_service_active "$id" \
     || ! nb_wait_for_listener TCP "$PORT" 25 \
     || ! { [ "$SNELL_QUIC_PROXY" != on ] || snell_wait_for_quic_listener "$PORT" 25; }; then
    snell_install_rollback "$id" "$new_pairs"
    admin_lock_release
    warn "Snell v${SNELL_VERSION} 启动或 TCP listener 验收失败，已回滚"
    return 1
  fi
  nobrand_install_manager_script || true
  admin_lock_release
  snell_print_result "$id" install
}

# 与 snell_config_matches_state 相同，但用于尚未提交的事务文件。
snell_config_matches_state_files() {
  local state="$1" config="$2"
  python3 - "$state" "$config" <<'PY'
import json
import sys
state=json.load(open(sys.argv[1], encoding="utf-8"))
values={}
section=""
for raw in open(sys.argv[2], encoding="utf-8"):
    line=raw.strip()
    if not line or line.startswith(("#",";")):
        continue
    if line.startswith("[") and line.endswith("]"):
        section=line[1:-1]
    elif "=" in line:
        key,value=(x.strip() for x in line.split("=",1))
        values[(section,key)]=value
    else:
        raise SystemExit(1)
if values.get(("snell-server","listen")) != "%s:%s" % (state["listen_host"],state["listen_port"]):
    raise SystemExit(1)
if values.get(("snell-server","psk")) != state["psk"]:
    raise SystemExit(1)
if state["version"] in (4,5) and values.get(("snell-server","ipv6")) != "false":
    raise SystemExit(1)
PY
}

snell_set_endpoint() {
  local id interactive=0 owner path tmp mode
  require_root
  id="$(snell_resolve_target_id "${SNELL_NAME:-}")" \
    || die '请用 --name 指定唯一存在的 Snell 节点'
  [ "${YES:-0}" -eq 1 ] || interactive=1
  PORT="$(snell_state_field "$id" listen_port)"
  if [ "$interactive" -eq 1 ] && [ "${ADVERTISE_CLI:-0}" -eq 0 ]; then
    nb_collect_advertise_endpoint_interactive "Snell $(snell_state_field "$id" name)" "$PORT"
  else
    nb_require_explicit_endpoint_noninteractive
  fi
  nb_validate_advertise_endpoint "$ADVERTISE_HOST" "$ADVERTISE_PORT" TCP || die 'Display Endpoint 无效'
  if [ -n "$ADVERTISE_HOST" ]; then
    owner="$(nb_endpoint_conflict_owner TCP "$ADVERTISE_HOST" "$ADVERTISE_PORT" "snell:${id}" 2>/dev/null || true)"
    [ -z "$owner" ] || die "Display Endpoint 与 ${owner} 冲突"
    if snell_managed_udp_enabled "$id"; then
      owner="$(nb_endpoint_conflict_owner UDP "$ADVERTISE_HOST" "$ADVERTISE_PORT" "snell:${id}" 2>/dev/null || true)"
      [ -z "$owner" ] || die "QUIC Display Endpoint 与 ${owner} 冲突"
    fi
  fi
  admin_lock_acquire || return 1
  path="$(snell_state_path "$id")"
  tmp="$(mktemp_file .json)" || { admin_lock_release; return 1; }
  mode="$(nb_endpoint_mode_from_values "$ADVERTISE_HOST")"
  if ! jq --arg mode "$mode" --arg host "$ADVERTISE_HOST" --arg port "$ADVERTISE_PORT" \
      --arg updated "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
        .advertise_mode=$mode |
        .advertise_host=$host |
        .advertise_port=(if $port=="" then "" else ($port|tonumber) end) |
        .updated_at=$updated
      ' "$path" >"$tmp" \
     || ! nb_atomic_install_file "$tmp" "$path" 0600; then
    rm -f "$tmp"
    admin_lock_release
    return 1
  fi
  rm -f "$tmp"
  # Display Endpoint 红线：不触碰 config、unit、listener、firewall、tc 或 quota。
  admin_lock_release
  t 'Snell 客户端展示入口已更新；server config/listener/service/firewall 均未改变' \
    'Snell display endpoint updated; server config/listener/service/firewall are unchanged'
  snell_print_result "$id" show
}

snell_state_set_quic() {
  local id="$1" enabled="$2" path tmp
  path="$(snell_state_path "$id")" || return 1
  tmp="$(mktemp_file .json)" || return 1
  if ! jq --argjson enabled "$enabled" --arg updated "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
      .quic_proxy_enabled=$enabled |
      .managed_udp=$enabled |
      .updated_at=$updated
    ' "$path" >"$tmp" \
     || ! nb_atomic_install_file "$tmp" "$path" 0600; then
    rm -f "$tmp"
    return 1
  fi
  rm -f "$tmp"
}

snell_set_quic() {
  local id port desired current udp_was_owned=0 state_consistent=0
  require_root
  id="$(snell_resolve_target_id "${SNELL_NAME:-}")" \
    || die '请用 --name 指定唯一存在的 Snell v5 节点'
  [ "$(snell_state_field "$id" version)" = 5 ] || die 'QUIC Proxy Mode 只适用于 Snell v5'
  desired="${SNELL_QUIC_PROXY:-}"
  if [ -z "$desired" ] && [ "${YES:-0}" -ne 1 ]; then
    read_tty desired "$(t 'QUIC Proxy Mode [on/off]: ' 'QUIC Proxy Mode [on/off]: ')" || desired=""
  fi
  case "$desired" in on|off) ;; *) die '请用 --quic on 或 --quic off 明确选择' ;; esac
  current=off; snell_quic_proxy_enabled "$id" && current=on
  snell_quic_state_consistent "$id" && state_consistent=1
  if [ "$current" = "$desired" ] && [ "$state_consistent" -eq 1 ]; then
    t "Snell v5 QUIC Proxy Mode 已是 ${desired}" "Snell v5 QUIC Proxy Mode is already ${desired}"
    return 0
  fi
  port="$(snell_state_field "$id" listen_port)"
  admin_lock_acquire || return 1
  if [ "$desired" = on ]; then
    if snell_service_active "$id" \
       && ! snell_v5_auxiliary_udp_same_process "$port"; then
      admin_lock_release
      die "Snell v5 同进程 UDP/${port} listener 未通过验收，拒绝开放 QUIC"
    fi
    if ! snell_service_active "$id" \
       && ! nb_port_available_for_transport "$port" UDP; then
      admin_lock_release
      warn "Snell v5 QUIC 需要同号 UDP/${port}，但该端口已占用"
      nb_describe_port_conflict UDP "$port"
      return 1
    fi
    nb_firewall_binding_owned UDP "$port" && udp_was_owned=1
    if ! nb_firewall_open_pairs "UDP|${port}" \
       || ! snell_state_set_quic "$id" true; then
      [ "$udp_was_owned" -eq 1 ] || nb_firewall_close_pairs "UDP|${port}" >/dev/null 2>&1 || true
      admin_lock_release
      return 1
    fi
  else
    if ! nb_firewall_close_pairs "UDP|${port}" \
       || ! snell_state_set_quic "$id" false; then
      nb_firewall_open_pairs "UDP|${port}" >/dev/null 2>&1 || true
      admin_lock_release
      return 1
    fi
  fi
  admin_lock_release
  t "Snell v5 QUIC Proxy Mode: ${desired}；server config/service/PSK 未改变" \
    "Snell v5 QUIC Proxy Mode: ${desired}; server config/service/PSK unchanged"
  snell_print_result "$id" show
}

snell_running() {
  local id="$1" port
  snell_state_exists "$id" || return 1
  port="$(snell_state_field "$id" listen_port)"
  snell_service_active "$id" && nb_port_is_listening TCP "$port"
}

snell_v5_auxiliary_udp_same_process() {
  local port="$1" tcp_pids udp_pids tcp_pid udp_pid
  tcp_pids="$(nb_port_listener_pids TCP "$port")"
  udp_pids="$(nb_port_listener_pids UDP "$port")"
  [ -n "$tcp_pids" ] && [ -n "$udp_pids" ] || return 1
  for udp_pid in $udp_pids; do
    for tcp_pid in $tcp_pids; do
      [ "$udp_pid" != "$tcp_pid" ] || return 0
    done
  done
  return 1
}

snell_wait_for_quic_listener() {
  local port="$1" timeout="${2:-25}" elapsed=0
  while [ "$elapsed" -lt "$timeout" ]; do
    snell_v5_auxiliary_udp_same_process "$port" && return 0
    sleep 1
    elapsed=$((elapsed + 1))
  done
  return 1
}

snell_wait_for_required_listeners() {
  local id="$1" timeout="${2:-25}" port
  port="$(snell_state_field "$id" listen_port)" || return 1
  nb_wait_for_listener TCP "$port" "$timeout" || return 1
  snell_quic_proxy_enabled "$id" || return 0
  snell_wait_for_quic_listener "$port" "$timeout"
}

snell_node_rows() {
  local id name major endpoint host port status quic endpoint_text transport
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    name="$(snell_state_field "$id" name)"
    major="$(snell_state_field "$id" version)"
    endpoint="$(snell_effective_endpoint "$id")"
    host="${endpoint%%|*}"; port="${endpoint#*|}"
    status=Stopped; snell_running "$id" && status=Running
    quic=off; snell_quic_proxy_enabled "$id" && quic=on
    endpoint_text="$(url_host "$host"):${port}/TCP; QUIC Off"
    transport=TCP
    if [ "$quic" = on ]; then
      endpoint_text="$(url_host "$host"):${port}/TCP; QUIC On (UDP same port)"
      transport=TCP+UDP
    fi
    printf 'Snell/v%s|%s|%s|%s|%s\n' "$major" "$name" "$endpoint_text" "$status" "$transport"
  done < <(snell_instance_ids)
}

snell_print_result() {
  local id="$1" context="${2:-show}" name major psk listen_host listen_port endpoint host port status runtime quic
  snell_state_exists "$id" || { t 'Snell 节点不存在' 'Snell node does not exist'; return 1; }
  name="$(snell_state_field "$id" name)"; major="$(snell_state_field "$id" version)"
  psk="$(snell_state_field "$id" psk)"; listen_host="$(snell_state_field "$id" listen_host)"
  listen_port="$(snell_state_field "$id" listen_port)"; runtime="$(snell_state_field "$id" runtime_version)"
  endpoint="$(snell_effective_endpoint "$id")"; host="${endpoint%%|*}"; port="${endpoint#*|}"
  status=Stopped; snell_running "$id" && status=Running
  quic=Disabled; snell_quic_proxy_enabled "$id" && quic=Enabled
  nobrand_print_banner
  msg "$([ "$context" = install ] && printf '部署完成' || printf '节点配置')"
  msg ''
  printf '协议        Snell v%s\n节点        %s\nInstance    %s\n状态        %s\nRuntime     %s\n' \
    "$major" "$name" "$id" "$status" "$runtime"
  msg ''
  printf '真实监听\n  Address   %s\n  Port      %s\n  Transport TCP\n' "$listen_host" "$listen_port"
  printf '  QUIC Proxy %s\n' "$quic"
  [ "$quic" != Enabled ] || printf '  QUIC Transport UDP/%s (same port)\n' "$listen_port"
  msg ''
  printf '客户端入口\n  Host      %s\n  Port      %s\n' "$host" "$port"
  msg ''
  printf '认证\n  PSK       %s\n' "$psk"
  msg ''
  snell_print_client_exports "$id"
}

snell_show() {
  local id found=0
  if [ -n "${SNELL_NAME:-}" ]; then
    id="$(snell_resolve_target_id "$SNELL_NAME")" || die "Snell 节点不存在: $SNELL_NAME"
    snell_print_result "$id" show
    return
  fi
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    [ "$found" -eq 0 ] || msg ''
    snell_print_result "$id" show
    found=1
  done < <(snell_instance_ids)
  [ "$found" -eq 1 ] || t 'Snell 未安装任何节点' 'No Snell nodes are installed'
}

snell_service_command() {
  local action="$1" id port was_enabled firewall_pairs
  id="$(snell_resolve_target_id "${SNELL_NAME:-}")" || die '请用 --name 指定唯一存在的 Snell 节点'
  port="$(snell_state_field "$id" listen_port)"
  was_enabled="$(snell_state_field "$id" enabled)"
  firewall_pairs="$(snell_firewall_pairs "$id")"
  case "$action" in
    start)
      nb_firewall_open_pairs "$firewall_pairs" || return 1
      if ! snell_service_action "$id" start || ! snell_wait_for_required_listeners "$id" 25 \
         || ! snell_state_set_enabled "$id" true; then
        snell_service_action "$id" stop >/dev/null 2>&1 || true
        [ "$was_enabled" = true ] || snell_state_set_enabled "$id" false >/dev/null 2>&1 || true
        return 1
      fi
      ;;
    stop)
      snell_service_action "$id" stop || return 1
      if ! snell_state_set_enabled "$id" false; then
        [ "$was_enabled" != true ] || snell_service_action "$id" start >/dev/null 2>&1 || true
        return 1
      fi
      ;;
    restart)
      snell_service_action "$id" restart && snell_wait_for_required_listeners "$id" 25
      ;;
    status)
      if snell_running "$id"; then msg "Snell $(snell_state_field "$id" name): Running"; else msg "Snell $(snell_state_field "$id" name): Stopped"; return 1; fi
      ;;
  esac
}

remove_snell_instance() {
  local id firewall_pairs
  require_root
  id="$(snell_resolve_target_id "${SNELL_NAME:-}")" || die '请用 --name 指定唯一存在的 Snell 节点'
  firewall_pairs="$(snell_firewall_pairs "$id")"
  admin_lock_acquire || return 1
  snell_remove_service "$id" || { admin_lock_release; return 1; }
  nb_firewall_close_pairs "$firewall_pairs" || { admin_lock_release; return 1; }
  rm -f "$(snell_config_path "$id")" "$(snell_state_path "$id")"
  admin_lock_release
  t "Snell 节点已删除: ${SNELL_NAME:-$id}" "Snell node removed: ${SNELL_NAME:-$id}"
}

snell_doctor_instance() {
  local id="$1" failed=0 name major port endpoint host advertise_port mode runtime actual_runtime quic
  snell_state_exists "$id" || return 1
  case "$(snell_state_field "$id" version 2>/dev/null || true)" in 4|5) ;; *) return 1 ;; esac
  name="$(snell_state_field "$id" name)"; major="$(snell_state_field "$id" version)"
  port="$(snell_state_field "$id" listen_port)"; runtime="$(snell_state_field "$id" runtime_version)"
  printf 'Instance %s (%s, v%s)\n' "$name" "$id" "$major"
  if [ -x "$(snell_runtime_path "$major")" ]; then
    actual_runtime="$(snell_runtime_reported_version "$(snell_runtime_path "$major")" 2>/dev/null || true)"
    [[ "$actual_runtime" = "$major".* ]] \
      && nb_doctor_line PASS "official runtime v${actual_runtime}" \
      || { nb_doctor_line FAIL "runtime major mismatch: ${actual_runtime:-unknown}"; failed=1; }
    [ "$actual_runtime" = "$runtime" ] || nb_doctor_line INFO "state runtime=${runtime}, installed=${actual_runtime}"
  else
    nb_doctor_line FAIL "runtime missing: $(snell_runtime_path "$major")"; failed=1
  fi
  snell_config_matches_state "$id" && nb_doctor_line PASS 'config/state consistency' \
    || { nb_doctor_line FAIL 'config/state consistency'; failed=1; }
  snell_quic_state_consistent "$id" \
    && nb_doctor_line PASS 'QUIC state/managed UDP consistency' \
    || { nb_doctor_line FAIL 'QUIC state/managed UDP consistency'; failed=1; }
  snell_running "$id" && nb_doctor_line PASS "service + TCP/${port}" \
    || { nb_doctor_line FAIL "service/listener TCP/${port}"; failed=1; }
  quic=off; snell_quic_proxy_enabled "$id" && quic=on
  if [ "$major" = 5 ] && [ "$quic" = on ]; then
    snell_v5_auxiliary_udp_same_process "$port" \
      && nb_doctor_line PASS "QUIC Proxy Enabled; same-process UDP/${port} listener" \
      || { nb_doctor_line FAIL "QUIC Proxy Enabled but same-process UDP/${port} listener missing"; failed=1; }
    nb_firewall_binding_owned UDP "$port" \
      && nb_doctor_line PASS "QUIC firewall ownership UDP/${port}" \
      || { nb_doctor_line FAIL "QUIC Proxy Enabled but UDP/${port} firewall ownership missing"; failed=1; }
  elif [ "$major" = 5 ]; then
    nb_doctor_line PASS 'QUIC Proxy Disabled; UDP public ownership OFF'
    if nb_firewall_binding_owned UDP "$port"; then
      nb_doctor_line FAIL "QUIC Proxy Disabled but UDP/${port} is still NoBrand-owned"
      failed=1
    elif nb_port_is_listening UDP "$port"; then
      if snell_v5_auxiliary_udp_same_process "$port"; then
        nb_doctor_line INFO \
          "runtime auxiliary listener UDP/${port} detected; owner=snell-server; public ownership=OFF; canonical ownership=TCP/${port}"
      else
        nb_doctor_line WARN \
          "same-port UDP/${port} listener detected, but ownership could not be matched to the primary Snell process"
      fi
    fi
  fi
  nb_firewall_binding_owned TCP "$port" && nb_doctor_line PASS "firewall ownership TCP/${port}" \
    || nb_doctor_line INFO "firewall rule not owned (pre-existing/no local firewall): TCP/${port}"
  mode="$(snell_state_field "$id" advertise_mode)"; host="$(snell_state_field "$id" advertise_host)"
  advertise_port="$(snell_state_field "$id" advertise_port)"
  nb_validate_advertise_endpoint "$host" "$advertise_port" TCP \
    && nb_doctor_line PASS "display endpoint mode=${mode}" \
    || { nb_doctor_line FAIL 'display endpoint state'; failed=1; }
  endpoint="$(snell_effective_endpoint "$id" 2>/dev/null || true)"
  [ -n "$endpoint" ] || { nb_doctor_line FAIL 'effective endpoint'; failed=1; }
  return "$failed"
}

snell_doctor_all() {
  local id found=0 failed=0
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    snell_doctor_instance "$id" || failed=1
    found=1
  done < <(snell_instance_ids)
  [ "$found" -eq 1 ] || nb_doctor_line INFO 'not installed'
  return "$failed"
}

snell_upgrade_runtime() {
  local major id ids backup="" metadata_backup="" runtime metadata active_ids="" failed=0 port
  nobrand_prepare_common
  if [ -n "${SNELL_NAME:-}" ]; then
    id="$(snell_resolve_target_id "$SNELL_NAME")" || die "Snell 节点不存在: $SNELL_NAME"
    major="$(snell_state_field "$id" version)"
  elif [ "${SNELL_VERSION_CLI:-0}" -eq 1 ]; then
    major="${SNELL_VERSION:-5}"
  else
    major=5
  fi
  case "$major" in 4|5) ;; *) die 'Snell 只支持 v4、v5' ;; esac
  runtime="$(snell_runtime_path "$major")"
  metadata="$(snell_runtime_metadata_path "$major")"
  if [ -e "$runtime" ]; then
    backup="$(mktemp_file .snell-runtime)" || return 1
    cp -a "$runtime" "$backup" || { rm -f "$backup"; return 1; }
  fi
  if [ -e "$metadata" ]; then
    metadata_backup="$(mktemp_file .snell-metadata)" || { rm -f "$backup"; return 1; }
    cp -a "$metadata" "$metadata_backup" || { rm -f "$backup" "$metadata_backup"; return 1; }
  fi
  while IFS= read -r id; do
    [ "$(snell_state_field "$id" version)" = "$major" ] || continue
    snell_service_active "$id" && active_ids="${active_ids}${id}"$'\n'
  done < <(snell_instance_ids)
  admin_lock_acquire || { rm -f "$backup"; return 1; }
  if ! snell_install_runtime "$major" 1; then
    rm -f "$backup"
    admin_lock_release
    return 1
  fi
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    port="$(snell_state_field "$id" listen_port)"
    snell_service_action "$id" restart >/dev/null 2>&1 \
      && snell_wait_for_required_listeners "$id" 25 || { failed=1; break; }
  done <<<"$active_ids"
  if [ "$failed" -eq 1 ]; then
    [ -n "$backup" ] && install -m 0755 "$backup" "$runtime"
    if [ -n "$metadata_backup" ]; then
      install -m 0600 "$metadata_backup" "$metadata"
    else
      rm -f "$metadata"
    fi
    while IFS= read -r id; do [ -z "$id" ] || snell_service_action "$id" restart >/dev/null 2>&1 || true; done <<<"$active_ids"
    rm -f "$backup" "$metadata_backup"
    admin_lock_release
    warn "Snell v${major} 升级后实例验收失败，已恢复旧 runtime"
    return 1
  fi
  ids="$(snell_instance_ids)"
  while IFS= read -r id; do
    [ "$(snell_state_field "$id" version 2>/dev/null || true)" = "$major" ] || continue
    snell_refresh_runtime_metadata "$id" || true
  done <<<"$ids"
  rm -f "$backup" "$metadata_backup"
  admin_lock_release
  t "Snell v${major} runtime 升级完成" "Snell v${major} runtime upgraded"
}

snell_refresh_runtime_metadata() {
  local id="$1" path tmp major runtime status
  path="$(snell_state_path "$id")"; major="$(snell_state_field "$id" version)"
  runtime="$(snell_runtime_release_version "$major")" || return 1
  status="$(snell_runtime_release_status "$major")"
  tmp="$(mktemp_file .json)" || return 1
  jq --arg runtime "$runtime" --arg status "$status" --arg updated "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '.runtime_version=$runtime | .runtime_status=$status | .updated_at=$updated' "$path" >"$tmp" \
    && nb_atomic_install_file "$tmp" "$path" 0600
  local rc=$?
  rm -f "$tmp"
  return "$rc"
}

# One-time 1.3.0 migration: v6 was removed after its final public-path
# qualification failed. Historical state is stopped and removed before any
# normal NoBrand action can expose it again. This is migration cleanup only;
# there is no v6 install, resolver, runner, exporter, or lifecycle path.
snell_migrate_quic_state_fields() {
  local id path tmp enabled
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    path="$(snell_state_path "$id")" || return 1
    if ! jq -e '
        .protocol == "snell" and (.version == 4 or .version == 5) and
        ((has("quic_proxy_enabled") | not) or (.quic_proxy_enabled | type == "boolean")) and
        ((has("managed_udp") | not) or (.managed_udp | type == "boolean")) and
        (if .version == 4 then
           ((.quic_proxy_enabled // false) == false and (.managed_udp // false) == false)
         elif has("quic_proxy_enabled") and has("managed_udp") then
           .quic_proxy_enabled == .managed_udp
         else true end)
      ' "$path" >/dev/null 2>&1; then
      return 1
    fi
    if jq -e 'has("quic_proxy_enabled") and has("managed_udp")' "$path" >/dev/null 2>&1; then
      continue
    fi
    enabled="$(jq -r '
      if .version == 4 then false
      elif has("quic_proxy_enabled") then .quic_proxy_enabled
      elif has("managed_udp") then .managed_udp
      else false end
    ' "$path")" || return 1
    tmp="$(mktemp_file .json)" || return 1
    if ! jq --argjson enabled "$enabled" --arg updated "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
        .quic_proxy_enabled=$enabled |
        .managed_udp=$enabled |
        .updated_at=$updated
      ' "$path" >"$tmp" \
       || ! nb_atomic_install_file "$tmp" "$path" 0600; then
      rm -f "$tmp"
      return 1
    fi
    rm -f "$tmp"
  done < <(snell_instance_ids)
}

snell_migrate_removed_v6() {
  local path id file_id port removed=0 failed=0
  [ -d "$NOBRAND_SNELL_STATE_DIR" ] || {
    rm -f "$NOBRAND_SNELL_RUNTIME_DIR/snell-v6" \
      "$NOBRAND_SNELL_RUNTIME_DIR/snell-v6.runtime.json"
    return 0
  }
  for path in "$NOBRAND_SNELL_STATE_DIR"/*.json; do
    [ -f "$path" ] || continue
    jq -e '.protocol == "snell" and .version == 6' "$path" >/dev/null 2>&1 || continue
    id="$(jq -r '.instance_id // empty' "$path")"
    file_id="$(basename "$path" .json)"
    [[ "$id" =~ ^s[0-9a-f]{16}$ ]] && [ "$file_id" = "$id" ] \
      || { failed=1; continue; }
    port="$(jq -r '.listen_port // empty' "$path")"
    snell_remove_service "$id" || { failed=1; continue; }
    if nb_valid_port "$port"; then
      # Historical NoBrand v6 had TCP-only canonical ownership. Never infer
      # UDP ownership from a same-number rule that may belong to HY2.
      nb_firewall_close_pairs "TCP|${port}" || { failed=1; continue; }
    fi
    rm -f "$(snell_config_path "$id")" "$path" || { failed=1; continue; }
    removed=$((removed + 1))
  done
  [ "$failed" -eq 0 ] || return 1
  snell_migrate_quic_state_fields || return 1
  rm -f "$NOBRAND_SNELL_RUNTIME_DIR/snell-v6" \
    "$NOBRAND_SNELL_RUNTIME_DIR/snell-v6.runtime.json"
  [ "$removed" -eq 0 ] || info "Removed ${removed} deprecated Snell v6 instance(s) during 1.3.0 migration"
}

nobrand_run_snell_action() {
  case "${SNELL_ACTION:-menu}" in
    menu) snell_menu_loop ;;
    install) install_snell ;;
    show) snell_show ;;
    set-endpoint) snell_set_endpoint ;;
    set-quic) snell_set_quic ;;
    remove) remove_snell_instance ;;
    start|stop|restart|status) snell_service_command "$SNELL_ACTION" ;;
    doctor) snell_doctor_all ;;
    upgrade) snell_upgrade_runtime ;;
    help) nobrand_usage ;;
  esac
}

# ---------- Hysteria2 engine: Xray-core v2 inbound parity ----------

hysteria2_state_exists() {
  [ -s "$NOBRAND_HY2_STATE_FILE" ] && jq empty "$NOBRAND_HY2_STATE_FILE" >/dev/null 2>&1
}

hysteria2_state_field() {
  local field="$1"
  hysteria2_state_exists || return 1
  jq -r --arg field "$field" \
    'if has($field) and .[$field] != null then .[$field] else empty end' "$NOBRAND_HY2_STATE_FILE"
}

hysteria2_valid_sni() {
  local value="${1:-}"
  valid_domain_name "$value" || {
    [[ "$value" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] && valid_ip_literal "$value"
  }
}

# 保持 Xray-OneClick lib/57-hysteria2.sh 的 prime256v1、3650 days、CN、
# 0600/0644 与 key-first atomic rollback 语义。
generate_hysteria2_cert() {
  local cert="$NOBRAND_HY2_CERT_FILE" key="$NOBRAND_HY2_KEY_FILE"
  local tmp_cert tmp_key old_key=""
  command -v openssl >/dev/null 2>&1 || {
    warn '[Hysteria2] 需要 openssl 生成自签证书。'
    return 1
  }
  mkdir -p "$NOBRAND_HY2_CONFIG_DIR" || return 1
  chmod 0700 "$NOBRAND_HY2_CONFIG_DIR" || return 1
  tmp_key="$(mktemp "${key}.tmp.XXXXXX")" || return 1
  tmp_cert="$(mktemp "${cert}.tmp.XXXXXX")" || { rm -f "$tmp_key"; return 1; }
  if ! openssl ecparam -genkey -name prime256v1 -out "$tmp_key" 2>/dev/null; then
    rm -f "$tmp_key" "$tmp_cert"
    warn '[Hysteria2] 生成 P-256 私钥失败。'
    return 1
  fi
  if ! openssl req -new -x509 -days 3650 -key "$tmp_key" -out "$tmp_cert" \
      -subj "/CN=${HY2_SNI:-bing.com}" 2>/dev/null; then
    rm -f "$tmp_key" "$tmp_cert"
    warn '[Hysteria2] 生成自签证书失败。'
    return 1
  fi
  chmod 0600 "$tmp_key" && chmod 0644 "$tmp_cert" \
    || { rm -f "$tmp_key" "$tmp_cert"; return 1; }
  if [ -f "$key" ]; then
    old_key="$(mktemp "${key}.rollback.XXXXXX")" \
      || { rm -f "$tmp_key" "$tmp_cert"; return 1; }
    cp -a "$key" "$old_key" \
      || { rm -f "$tmp_key" "$tmp_cert" "$old_key"; return 1; }
  fi
  mv "$tmp_key" "$key" \
    || { rm -f "$tmp_key" "$tmp_cert" "$old_key"; return 1; }
  if ! mv "$tmp_cert" "$cert"; then
    rm -f "$tmp_cert"
    if [ -n "$old_key" ]; then cp -a "$old_key" "$key" || true; else rm -f "$key"; fi
    rm -f "$old_key"
    return 1
  fi
  rm -f "$old_key"
}

hysteria2_generate_config() {
  local output="$1" listen="$2" port="$3" auth="$4" sni="$5" obfs="$6"
  local cert="${7:-$NOBRAND_HY2_CERT_FILE}" key="${8:-$NOBRAND_HY2_KEY_FILE}"
  jq -n --arg tag "$NOBRAND_HY2_TAG" --arg listen "$listen" --arg port "$port" \
    --arg auth "$auth" --arg cert "$cert" --arg key "$key" --arg obfs "$obfs" '
    {
      "log": {"loglevel":"warning"},
      "inbounds": [{
        "tag": $tag,
        "listen": $listen,
        "port": ($port|tonumber),
        "protocol": "hysteria",
        "settings": {
          "version": 2,
          "clients": [{"auth":$auth,"email":"hysteria2@xray"}]
        },
        "streamSettings": {
          "network": "hysteria",
          "security": "tls",
          "tlsSettings": {
            "alpn": ["h3"],
            "certificates": [{"certificateFile":$cert,"keyFile":$key}]
          },
          "hysteriaSettings": {"version":2},
          "finalmask": {
            "udp": [{"type":"salamander","settings":{"password":$obfs}}]
          }
        }
      }],
      "outbounds": [{"tag":"direct","protocol":"freedom"}],
      "routing": {"rules":[]}
    }
  ' >"$output"
}

hysteria2_build_share_link() {
  local auth="${1:-}" host="${2:-}" port="${3:-}" sni="${4:-}" obfs="${5:-}"
  local name="${6:-NoBrand-Hysteria2}" auth_uri host_uri sni_uri obfs_uri name_uri
  [ -n "$auth" ] && [ -n "$host" ] && nb_valid_port "$port" && [ -n "$sni" ] || return 1
  auth_uri="$(urlencode "$auth")" || return 1
  host_uri="$(url_host "$host")"
  sni_uri="$(urlencode "$sni")" || return 1
  obfs_uri="$(urlencode "$obfs")" || return 1
  name_uri="$(urlencode "$name")" || return 1
  printf 'hysteria2://%s@%s:%s?sni=%s&alpn=h3&insecure=1&obfs=salamander&obfs-password=%s#%s' \
    "$auth_uri" "$host_uri" "$port" "$sni_uri" "$obfs_uri" "$name_uri"
}

hysteria2_current_share_link() {
  local auth sni obfs listen_port mode advertise_host advertise_port host port
  hysteria2_state_exists || return 1
  auth="$(hysteria2_state_field auth)"
  sni="$(hysteria2_state_field sni)"
  obfs="$(hysteria2_state_field obfs)"
  listen_port="$(hysteria2_state_field listen_port)"
  mode="$(hysteria2_state_field advertise_mode)"
  advertise_host="$(hysteria2_state_field advertise_host)"
  advertise_port="$(hysteria2_state_field advertise_port)"
  host="$(nb_effective_advertise_host "$mode" "$advertise_host")"
  port="$(nb_effective_advertise_port "$mode" "$advertise_port" "$listen_port")"
  hysteria2_build_share_link "$auth" "$host" "$port" "$sni" "$obfs"
}

hysteria2_export_values() {
  local auth sni obfs listen_port mode advertise_host advertise_port host port
  hysteria2_state_exists || return 1
  auth="$(hysteria2_state_field auth)"
  sni="$(hysteria2_state_field sni)"
  obfs="$(hysteria2_state_field obfs)"
  listen_port="$(hysteria2_state_field listen_port)"
  mode="$(hysteria2_state_field advertise_mode)"
  advertise_host="$(hysteria2_state_field advertise_host)"
  advertise_port="$(hysteria2_state_field advertise_port)"
  host="$(nb_effective_advertise_host "$mode" "$advertise_host")"
  port="$(nb_effective_advertise_port "$mode" "$advertise_port" "$listen_port")"
  printf '%s\t%s\t%s\t%s\t%s\n' "$auth" "$sni" "$obfs" "$host" "$port"
}

hysteria2_export_mihomo() {
  local auth sni obfs host port values
  values="$(hysteria2_export_values)" || return 1
  IFS=$'\t' read -r auth sni obfs host port <<<"$values"
  jq -n --arg server "$host" --arg port "$port" --arg password "$auth" \
    --arg sni "$sni" --arg obfs "$obfs" -r '
      "- name: NoBrand-Hysteria2\n" +
      "  type: hysteria2\n" +
      "  server: " + ($server|tojson) + "\n" +
      "  port: " + $port + "\n" +
      "  password: " + ($password|tojson) + "\n" +
      "  sni: " + ($sni|tojson) + "\n" +
      "  skip-cert-verify: true\n" +
      "  obfs: salamander\n" +
      "  obfs-password: " + ($obfs|tojson)
    '
}

hysteria2_export_singbox() {
  local auth sni obfs host port values
  values="$(hysteria2_export_values)" || return 1
  IFS=$'\t' read -r auth sni obfs host port <<<"$values"
  jq -n --arg server "$host" --arg port "$port" --arg password "$auth" \
    --arg sni "$sni" --arg obfs "$obfs" '
      {
        type:"hysteria2",
        tag:"NoBrand-Hysteria2",
        server:$server,
        server_port:($port|tonumber),
        password:$password,
        obfs:{type:"salamander",password:$obfs},
        tls:{enabled:true,server_name:$sni,insecure:true,alpn:["h3"]}
      }
    '
}

hysteria2_generate_state() {
  local output="$1" listen="$2" port="$3" auth="$4" sni="$5" obfs="$6"
  local advertise_mode="$7" advertise_host="$8" advertise_port="$9"
  local created_at="${10:-}" updated_at link effective_host effective_port runtime_version
  [ -n "$created_at" ] || created_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  updated_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  effective_host="$(nb_effective_advertise_host "$advertise_mode" "$advertise_host")"
  effective_port="$(nb_effective_advertise_port "$advertise_mode" "$advertise_port" "$port")"
  link="$(hysteria2_build_share_link "$auth" "$effective_host" "$effective_port" "$sni" "$obfs")" || return 1
  runtime_version="$(nobrand_xray_version 2>/dev/null || printf unknown)"
  jq -n --arg auth "$auth" --arg sni "$sni" --arg obfs "$obfs" \
    --arg listen "$listen" --arg port "$port" --arg mode "$advertise_mode" \
    --arg advertise_host "$advertise_host" --arg advertise_port "$advertise_port" \
    --arg tag "$NOBRAND_HY2_TAG" --arg link "$link" --arg runtime "$runtime_version" \
    --arg created "$created_at" --arg updated "$updated_at" '
    {
      "protocol":"hysteria2",
      "auth":$auth,
      "sni":$sni,
      "obfs":$obfs,
      "listen_host":$listen,
      "listen_port":($port|tonumber),
      "transport":"udp",
      "advertise_mode":$mode,
      "advertise_host":$advertise_host,
      "advertise_port":(if $advertise_port=="" then "" else ($advertise_port|tonumber) end),
      "tag":$tag,
      "runtime_version":$runtime,
      "link":$link,
      "enabled":true,
      "created_at":$created,
      "updated_at":$updated
    }
  ' >"$output"
}

hysteria2_snapshot_file() {
  local source="$1" destination="$2"
  if [ -e "$source" ]; then cp -a "$source" "$destination"; else printf absent >"${destination}.absent"; fi
}

hysteria2_restore_snapshot_file() {
  local snapshot="$1" destination="$2"
  if [ -f "${snapshot}.absent" ]; then
    rm -f "$destination"
  elif [ -e "$snapshot" ]; then
    mkdir -p "$(dirname "$destination")"
    cp -a "$snapshot" "$destination"
  fi
}

hysteria2_configure_requests() {
  local interactive="${1:-0}" old_port="" conflict_owner=""
  HY2_LISTEN="0.0.0.0"
  hysteria2_state_exists && old_port="$(hysteria2_state_field listen_port 2>/dev/null || true)"
  if [ -z "${PORT:-}" ]; then
    PORT="$(nb_select_available_port UDP)" || die '未找到可用 Hysteria2 UDP 端口'
    PORT_AUTO_SELECTED=1
  else
    nb_valid_port "$PORT" || die 'Hysteria2 端口必须是 1-65535'
    PORT="$(normalize_uint "$PORT")"
    nb_warn_if_outside_recommended_range "$PORT"
    if [ "$PORT" != "$old_port" ] && ! nb_port_available_for_transport "$PORT" UDP 'hy2:default'; then
      warn "Hysteria2 UDP/${PORT} 已占用"
      nb_describe_port_conflict UDP "$PORT"
      return 1
    fi
  fi
  if [ "$interactive" -eq 1 ] && [ "${ADVERTISE_CLI:-0}" -eq 0 ]; then
    nb_collect_advertise_endpoint_interactive Hysteria2 "$PORT"
  else
    nb_require_explicit_endpoint_noninteractive
  fi
  nb_validate_advertise_endpoint "$ADVERTISE_HOST" "$ADVERTISE_PORT" UDP \
    || die 'Hysteria2 Display Endpoint 无效'
  if [ -n "$ADVERTISE_HOST" ]; then
    conflict_owner="$(nb_endpoint_conflict_owner UDP "$ADVERTISE_HOST" "$ADVERTISE_PORT" 'hy2:default' 2>/dev/null || true)"
    [ -z "$conflict_owner" ] || die "Hysteria2 Display Endpoint 与 ${conflict_owner} 冲突"
  fi
  if [ -z "${HY2_SNI:-}" ]; then
    if [ "$interactive" -eq 1 ]; then
      read_tty HY2_SNI "$(t 'Hysteria2 伪装 SNI（回车随机）: ' 'Hysteria2 camouflage SNI (Enter=random): ')" || HY2_SNI=""
      [ -n "$HY2_SNI" ] || HY2_SNI="${NOBRAND_HY2_SNI_CANDIDATES[$((RANDOM % ${#NOBRAND_HY2_SNI_CANDIDATES[@]}))]}"
    else
      HY2_SNI="${NOBRAND_HY2_SNI_CANDIDATES[0]}"
    fi
  fi
  hysteria2_valid_sni "$HY2_SNI" || die 'Hysteria2 SNI 必须是有效域名或 IPv4 地址'
  HY2_AUTH="$(openssl rand -hex 16 2>/dev/null || true)"
  [ -n "$HY2_AUTH" ] || HY2_AUTH="$(random_token)$(random_token)$(random_token)"
  HY2_OBFS="$(openssl rand -hex 16 2>/dev/null || true)"
  [ -n "$HY2_OBFS" ] || HY2_OBFS="$(random_token)$(random_token)$(random_token)"
}

hysteria2_install_rollback() {
  local snapshot="$1" was_active="$2" new_binding_owned="$3"
  nobrand_hy2_service_action stop >/dev/null 2>&1 || true
  [ "$new_binding_owned" -eq 0 ] || nb_firewall_close_pairs "UDP|${PORT}" >/dev/null 2>&1 || true
  hysteria2_restore_snapshot_file "$snapshot/config" "$NOBRAND_HY2_CONFIG_FILE"
  hysteria2_restore_snapshot_file "$snapshot/state" "$NOBRAND_HY2_STATE_FILE"
  hysteria2_restore_snapshot_file "$snapshot/cert" "$NOBRAND_HY2_CERT_FILE"
  hysteria2_restore_snapshot_file "$snapshot/key" "$NOBRAND_HY2_KEY_FILE"
  hysteria2_restore_snapshot_file "$snapshot/service-systemd" "$NOBRAND_HY2_SYSTEMD_SERVICE"
  hysteria2_restore_snapshot_file "$snapshot/service-openrc" "$NOBRAND_HY2_OPENRC_SERVICE"
  hysteria2_restore_snapshot_file "$snapshot/xray" "$NOBRAND_XRAY_BIN"
  [ "$(nb_service_manager)" != systemd ] || systemctl daemon-reload >/dev/null 2>&1 || true
  [ "$was_active" -eq 0 ] || nobrand_hy2_service_action start >/dev/null 2>&1 || true
}

install_hysteria2() {
  local interactive=0 snapshot config_tmp state_tmp advertise_mode old_port="" old_created=""
  local was_active=0 binding_was_owned=0 binding_now_owned=0
  [ "${YES:-0}" -eq 1 ] || interactive=1
  nobrand_prepare_common
  admin_lock_acquire || return 1
  snapshot="$(mktemp_dir)" || { admin_lock_release; return 1; }
  hysteria2_snapshot_file "$NOBRAND_HY2_CONFIG_FILE" "$snapshot/config"
  hysteria2_snapshot_file "$NOBRAND_HY2_STATE_FILE" "$snapshot/state"
  hysteria2_snapshot_file "$NOBRAND_HY2_CERT_FILE" "$snapshot/cert"
  hysteria2_snapshot_file "$NOBRAND_HY2_KEY_FILE" "$snapshot/key"
  hysteria2_snapshot_file "$NOBRAND_HY2_SYSTEMD_SERVICE" "$snapshot/service-systemd"
  hysteria2_snapshot_file "$NOBRAND_HY2_OPENRC_SERVICE" "$snapshot/service-openrc"
  hysteria2_snapshot_file "$NOBRAND_XRAY_BIN" "$snapshot/xray"
  nobrand_hy2_service_active && was_active=1
  if hysteria2_state_exists; then
    old_port="$(hysteria2_state_field listen_port 2>/dev/null || true)"
    old_created="$(hysteria2_state_field created_at 2>/dev/null || true)"
  fi
  if ! nobrand_install_xray_runtime 0 || ! hysteria2_configure_requests "$interactive"; then
    hysteria2_install_rollback "$snapshot" "$was_active" 0
    rm -rf -- "$snapshot"
    admin_lock_release
    return 1
  fi
  nb_firewall_binding_owned UDP "$PORT" && binding_was_owned=1
  if [ "$was_active" -eq 1 ]; then
    nobrand_hy2_service_action stop || {
      hysteria2_install_rollback "$snapshot" "$was_active" 0
      rm -rf -- "$snapshot"; admin_lock_release; return 1;
    }
  fi
  # TOCTOU 二次检测：旧实例同端口需先停止自身 listener。
  if ! nb_port_available_for_transport "$PORT" UDP 'hy2:default'; then
    warn "提交前发现 UDP/${PORT} 已被其它进程占用"
    nb_describe_port_conflict UDP "$PORT"
    hysteria2_install_rollback "$snapshot" "$was_active" 0
    rm -rf -- "$snapshot"; admin_lock_release; return 1
  fi
  if ! generate_hysteria2_cert; then
    hysteria2_install_rollback "$snapshot" "$was_active" 0
    rm -rf -- "$snapshot"; admin_lock_release; return 1
  fi
  config_tmp="$(mktemp_file .json)" || {
    hysteria2_install_rollback "$snapshot" "$was_active" 0
    rm -rf -- "$snapshot"; admin_lock_release; return 1;
  }
  state_tmp="$(mktemp_file .json)" || {
    rm -f "$config_tmp"; hysteria2_install_rollback "$snapshot" "$was_active" 0
    rm -rf -- "$snapshot"; admin_lock_release; return 1;
  }
  advertise_mode="$(nb_endpoint_mode_from_values "$ADVERTISE_HOST")"
  if ! hysteria2_generate_config "$config_tmp" "$HY2_LISTEN" "$PORT" "$HY2_AUTH" "$HY2_SNI" "$HY2_OBFS" \
     || ! nobrand_xray_test_config "$config_tmp" \
     || ! hysteria2_generate_state "$state_tmp" "$HY2_LISTEN" "$PORT" "$HY2_AUTH" "$HY2_SNI" "$HY2_OBFS" \
          "$advertise_mode" "$ADVERTISE_HOST" "$ADVERTISE_PORT" "$old_created" \
     || ! nb_atomic_install_file "$config_tmp" "$NOBRAND_HY2_CONFIG_FILE" 0600 \
     || ! nb_atomic_install_file "$state_tmp" "$NOBRAND_HY2_STATE_FILE" 0600 \
     || ! nobrand_write_hy2_service \
     || ! nb_firewall_open_pairs "UDP|${PORT}"; then
    rm -f "$config_tmp" "$state_tmp"
    nb_firewall_binding_owned UDP "$PORT" && [ "$binding_was_owned" -eq 0 ] && binding_now_owned=1
    hysteria2_install_rollback "$snapshot" "$was_active" "$binding_now_owned"
    rm -rf -- "$snapshot"; admin_lock_release; return 1
  fi
  rm -f "$config_tmp" "$state_tmp"
  nb_firewall_binding_owned UDP "$PORT" && [ "$binding_was_owned" -eq 0 ] && binding_now_owned=1
  if ! nobrand_hy2_service_action restart \
     || ! nobrand_hy2_service_active \
     || ! nb_wait_for_listener UDP "$PORT" 25; then
    hysteria2_install_rollback "$snapshot" "$was_active" "$binding_now_owned"
    rm -rf -- "$snapshot"; admin_lock_release
    warn 'Hysteria2 服务启动或 UDP listener 验收失败，已回滚'
    return 1
  fi
  if [ -n "$old_port" ] && [ "$old_port" != "$PORT" ]; then
    nb_firewall_close_pairs "UDP|${old_port}" || true
  fi
  nobrand_install_manager_script || true
  rm -rf -- "$snapshot"
  admin_lock_release
  print_hysteria2_result install
}

hysteria2_set_endpoint() {
  local interactive=0 tmp mode owner auth sni obfs host port link
  require_root
  hysteria2_state_exists || die 'Hysteria2 未安装'
  [ "${YES:-0}" -eq 1 ] || interactive=1
  PORT="$(hysteria2_state_field listen_port)"
  if [ "$interactive" -eq 1 ] && [ "${ADVERTISE_CLI:-0}" -eq 0 ]; then
    nb_collect_advertise_endpoint_interactive Hysteria2 "$PORT"
  else
    nb_require_explicit_endpoint_noninteractive
  fi
  nb_validate_advertise_endpoint "$ADVERTISE_HOST" "$ADVERTISE_PORT" UDP || die 'Display Endpoint 无效'
  if [ -n "$ADVERTISE_HOST" ]; then
    owner="$(nb_endpoint_conflict_owner UDP "$ADVERTISE_HOST" "$ADVERTISE_PORT" 'hy2:default' 2>/dev/null || true)"
    [ -z "$owner" ] || die "Display Endpoint 与 ${owner} 冲突"
  fi
  admin_lock_acquire || return 1
  tmp="$(mktemp_file .json)" || { admin_lock_release; return 1; }
  mode="$(nb_endpoint_mode_from_values "$ADVERTISE_HOST")"
  auth="$(hysteria2_state_field auth)"
  sni="$(hysteria2_state_field sni)"
  obfs="$(hysteria2_state_field obfs)"
  host="$(nb_effective_advertise_host "$mode" "$ADVERTISE_HOST")"
  port="$(nb_effective_advertise_port "$mode" "$ADVERTISE_PORT" "$PORT")"
  link="$(hysteria2_build_share_link "$auth" "$host" "$port" "$sni" "$obfs")" \
    || { rm -f "$tmp"; admin_lock_release; return 1; }
  if ! jq --arg mode "$mode" --arg host "$ADVERTISE_HOST" --arg port "$ADVERTISE_PORT" \
      --arg link "$link" --arg updated "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
        .advertise_mode=$mode |
        .advertise_host=$host |
        .advertise_port=(if $port=="" then "" else ($port|tonumber) end) |
        .link=$link |
        .updated_at=$updated
      ' "$NOBRAND_HY2_STATE_FILE" >"$tmp" \
     || ! nb_atomic_install_file "$tmp" "$NOBRAND_HY2_STATE_FILE" 0600; then
    rm -f "$tmp"; admin_lock_release; return 1
  fi
  rm -f "$tmp"
  # 红线：本函数不调用 service、firewall、config、tc 或 quota。
  admin_lock_release
  t 'Hysteria2 客户端展示入口已更新；server config/listener/service/firewall 均未改变' \
    'Hysteria2 display endpoint updated; server config/listener/service/firewall are unchanged'
  print_hysteria2_result show
}

hysteria2_running() {
  local port
  hysteria2_state_exists || return 1
  port="$(hysteria2_state_field listen_port)"
  nobrand_hy2_service_active && nb_port_is_listening UDP "$port"
}

hysteria2_state_set_enabled() {
  local enabled="$1" tmp
  tmp="$(mktemp_file .json)" || return 1
  if ! jq --argjson enabled "$enabled" --arg updated "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      '.enabled=$enabled | .updated_at=$updated' "$NOBRAND_HY2_STATE_FILE" >"$tmp" \
     || ! nb_atomic_install_file "$tmp" "$NOBRAND_HY2_STATE_FILE" 0600; then
    rm -f "$tmp"
    return 1
  fi
  rm -f "$tmp"
}

hysteria2_node_rows() {
  local mode advertise_host advertise_port listen_port host port status
  hysteria2_state_exists || return 0
  mode="$(hysteria2_state_field advertise_mode)"
  advertise_host="$(hysteria2_state_field advertise_host)"
  advertise_port="$(hysteria2_state_field advertise_port)"
  listen_port="$(hysteria2_state_field listen_port)"
  host="$(nb_effective_advertise_host "$mode" "$advertise_host")"
  port="$(nb_effective_advertise_port "$mode" "$advertise_port" "$listen_port")"
  status=Stopped; hysteria2_running && status=Running
  printf 'Hysteria2|default|%s:%s/UDP|%s|UDP\n' "$host" "$port" "$status"
}

print_hysteria2_result() {
  local context="${1:-show}" auth sni obfs listen_host listen_port mode advertise_host advertise_port host port status link
  hysteria2_state_exists || { t 'Hysteria2 未安装' 'Hysteria2 is not installed'; return 0; }
  auth="$(hysteria2_state_field auth)"; sni="$(hysteria2_state_field sni)"; obfs="$(hysteria2_state_field obfs)"
  listen_host="$(hysteria2_state_field listen_host)"; listen_port="$(hysteria2_state_field listen_port)"
  mode="$(hysteria2_state_field advertise_mode)"; advertise_host="$(hysteria2_state_field advertise_host)"
  advertise_port="$(hysteria2_state_field advertise_port)"
  host="$(nb_effective_advertise_host "$mode" "$advertise_host")"
  port="$(nb_effective_advertise_port "$mode" "$advertise_port" "$listen_port")"
  status=Stopped; hysteria2_running && status=Running
  link="$(hysteria2_build_share_link "$auth" "$host" "$port" "$sni" "$obfs")"
  nobrand_print_banner
  msg "$( [ "$context" = install ] && printf '部署完成' || printf '节点配置' )"
  msg ''
  printf '协议        Hysteria2\n节点        default\n状态        %s\n' "$status"
  msg ''
  printf '真实监听\n  Address   %s\n  Port      %s\n  Transport UDP\n' "$listen_host" "$listen_port"
  msg ''
  printf '客户端入口\n  Host      %s\n  Port      %s\n  Mode      %s\n' "$host" "$port" "$mode"
  msg ''
  printf '认证\n  Auth      %s\n  SNI       %s\n  Salamander password  %s\n' "$auth" "$sni" "$obfs"
  msg ''
  msg '========================================'
  msg 'Mihomo'
  msg '========================================'
  hysteria2_export_mihomo
  msg ''
  msg '========================================'
  msg 'sing-box'
  msg '========================================'
  hysteria2_export_singbox
  msg '  Certificate: self-signed P-256 / 3650 days; client must use insecure=1.'
  msg ''
  msg '========================================'
  msg '客户端配置'
  msg '========================================'
  msg "$link"
}

hysteria2_service_command() {
  local action="$1" port was_enabled
  hysteria2_state_exists || die 'Hysteria2 未安装'
  port="$(hysteria2_state_field listen_port)"
  was_enabled="$(hysteria2_state_field enabled)"
  case "$action" in
    start)
      nb_firewall_open_pairs "UDP|${port}" || return 1
      if ! nobrand_hy2_service_action start || ! nb_wait_for_listener UDP "$port" 25 \
         || ! hysteria2_state_set_enabled true; then
        nobrand_hy2_service_action stop >/dev/null 2>&1 || true
        [ "$was_enabled" = true ] || hysteria2_state_set_enabled false >/dev/null 2>&1 || true
        return 1
      fi
      ;;
    stop)
      nobrand_hy2_service_action stop || return 1
      if ! hysteria2_state_set_enabled false; then
        [ "$was_enabled" != true ] || nobrand_hy2_service_action start >/dev/null 2>&1 || true
        return 1
      fi
      ;;
    restart) nobrand_hy2_service_action restart && nb_wait_for_listener UDP "$port" 25 ;;
    status)
      if hysteria2_running; then msg 'Hysteria2: Running'; else msg 'Hysteria2: Stopped'; return 1; fi
      ;;
  esac
}

remove_hysteria2_config() {
  local port
  require_root
  hysteria2_state_exists || { t 'Hysteria2 未安装' 'Hysteria2 is not installed'; return 0; }
  port="$(hysteria2_state_field listen_port)"
  admin_lock_acquire || return 1
  nobrand_remove_hy2_service || { admin_lock_release; return 1; }
  nb_firewall_close_pairs "UDP|${port}" || { admin_lock_release; return 1; }
  rm -f "$NOBRAND_HY2_CONFIG_FILE" "$NOBRAND_HY2_STATE_FILE" \
    "$NOBRAND_HY2_CERT_FILE" "$NOBRAND_HY2_KEY_FILE"
  admin_lock_release
  t '已删除 NoBrand 管理的 Hysteria2；未触碰 /etc/xray、xray.service、ike 或 Xray-OneClick' \
    'Removed NoBrand-managed Hysteria2; /etc/xray, xray.service, ike, and Xray-OneClick were untouched'
}

hysteria2_doctor() {
  local failed=0 port mode host advertise_port key_mode cert_cn expected_sni
  if ! hysteria2_state_exists; then
    nb_doctor_line INFO 'not installed'
    return 0
  fi
  port="$(hysteria2_state_field listen_port)"
  [ -x "$NOBRAND_XRAY_BIN" ] && nb_doctor_line PASS "Xray $(nobrand_xray_version 2>/dev/null || printf unknown)" \
    || { nb_doctor_line FAIL 'NoBrand Xray binary'; failed=1; }
  nobrand_xray_test_config "$NOBRAND_HY2_CONFIG_FILE" \
    && nb_doctor_line PASS 'Xray config test' || { nb_doctor_line FAIL 'Xray config test'; failed=1; }
  if openssl ec -in "$NOBRAND_HY2_KEY_FILE" -noout -text 2>/dev/null | grep -q 'ASN1 OID: prime256v1'; then
    key_mode="$(stat -c '%a' "$NOBRAND_HY2_KEY_FILE" 2>/dev/null || true)"
    [ "$key_mode" = 600 ] && nb_doctor_line PASS 'P-256 private key mode=0600' \
      || { nb_doctor_line FAIL "private key mode=${key_mode}"; failed=1; }
  else
    nb_doctor_line FAIL 'P-256 private key'; failed=1
  fi
  if openssl x509 -in "$NOBRAND_HY2_CERT_FILE" -noout >/dev/null 2>&1; then
    cert_cn="$(openssl x509 -in "$NOBRAND_HY2_CERT_FILE" -noout -subject -nameopt RFC2253 2>/dev/null \
      | sed -nE 's/^subject=.*CN=([^,]+).*$/\1/p')"
    expected_sni="$(hysteria2_state_field sni)"
    if [ "$cert_cn" = "$expected_sni" ]; then
      nb_doctor_line PASS "certificate CN=${cert_cn}"
    else
      nb_doctor_line FAIL "certificate CN=${cert_cn:-missing}, state SNI=${expected_sni}"
      failed=1
    fi
  else
    nb_doctor_line FAIL 'certificate'; failed=1
  fi
  hysteria2_running && nb_doctor_line PASS "service + UDP/${port}" \
    || { nb_doctor_line FAIL "service/listener UDP/${port}"; failed=1; }
  nb_firewall_binding_owned UDP "$port" && nb_doctor_line PASS "firewall ownership UDP/${port}" \
    || nb_doctor_line INFO "firewall rule not owned (pre-existing/no local firewall): UDP/${port}"
  mode="$(hysteria2_state_field advertise_mode)"; host="$(hysteria2_state_field advertise_host)"
  advertise_port="$(hysteria2_state_field advertise_port)"
  nb_validate_advertise_endpoint "$host" "$advertise_port" UDP \
    && nb_doctor_line PASS "display endpoint mode=${mode}" \
    || { nb_doctor_line FAIL 'display endpoint state'; failed=1; }
  hysteria2_current_share_link >/dev/null \
    && nb_doctor_line PASS 'hysteria2 URI generation' || { nb_doctor_line FAIL 'URI generation'; failed=1; }
  return "$failed"
}

hysteria2_refresh_runtime_metadata() {
  local tmp runtime
  hysteria2_state_exists || return 0
  runtime="$(nobrand_xray_version)" || return 1
  tmp="$(mktemp_file .json)" || return 1
  jq --arg runtime "$runtime" --arg updated "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '.runtime_version=$runtime | .updated_at=$updated' "$NOBRAND_HY2_STATE_FILE" >"$tmp" \
    && nb_atomic_install_file "$tmp" "$NOBRAND_HY2_STATE_FILE" 0600
  local rc=$?
  rm -f "$tmp"
  return "$rc"
}

hysteria2_upgrade_runtime() {
  nobrand_upgrade_xray_runtime
}

nobrand_run_hy2_action() {
  case "${HY2_ACTION:-menu}" in
    menu) hysteria2_menu_loop ;;
    install) install_hysteria2 ;;
    show) print_hysteria2_result show ;;
    set-endpoint) hysteria2_set_endpoint ;;
    remove) remove_hysteria2_config ;;
    start|stop|restart|status) hysteria2_service_command "$HY2_ACTION" ;;
    doctor) hysteria2_doctor ;;
    upgrade) hysteria2_upgrade_runtime ;;
    help) nobrand_usage ;;
  esac
}

# ---------- Plain VLESS + FinalMask Sudoku over TCP ----------

vless_sudoku_state_exists() {
  [ -s "$NOBRAND_VLESS_STATE_FILE" ] && jq empty "$NOBRAND_VLESS_STATE_FILE" >/dev/null 2>&1
}

vless_sudoku_state_field() {
  local field="$1"
  vless_sudoku_state_exists || return 1
  jq -r --arg field "$field" \
    'if has($field) and .[$field] != null then .[$field] else empty end' "$NOBRAND_VLESS_STATE_FILE"
}

vless_sudoku_finalmask_json() {
  local password="$1"
  [[ "$password" =~ ^[0-9A-Fa-f]{32}$ ]] || return 1
  jq -cn --arg password "$password" '{
    tcp: [{
      type: "sudoku",
      settings: {
        password: $password,
        ascii: "prefer_ascii",
        paddingMin: 0,
        paddingMax: 3
      }
    }]
  }'
}

vless_sudoku_valid_uuid() {
  [[ "${1:-}" =~ ^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$ ]]
}

vless_sudoku_generate_uuid() {
  local value=""
  if [ -x "$NOBRAND_XRAY_BIN" ]; then
    value="$("$NOBRAND_XRAY_BIN" uuid 2>/dev/null | tr -d '\r\n' || true)"
  fi
  if ! vless_sudoku_valid_uuid "$value" && command -v uuidgen >/dev/null 2>&1; then
    value="$(uuidgen 2>/dev/null | tr '[:upper:]' '[:lower:]' | tr -d '\r\n' || true)"
  fi
  if ! vless_sudoku_valid_uuid "$value" && [ -r /proc/sys/kernel/random/uuid ]; then
    value="$(tr -d '\r\n' </proc/sys/kernel/random/uuid)"
  fi
  if ! vless_sudoku_valid_uuid "$value" && command -v openssl >/dev/null 2>&1; then
    value="$(openssl rand -hex 16 2>/dev/null \
      | sed -E 's/(.{8})(.{4})(.{4})(.{4})(.{12})/\1-\2-\3-\4-\5/')"
  fi
  vless_sudoku_valid_uuid "$value" || return 1
  printf '%s' "$value"
}

vless_sudoku_generate_server_config() {
  local output="$1" listen="$2" port="$3" uuid="$4" password="$5" finalmask
  finalmask="$(vless_sudoku_finalmask_json "$password")" || return 1
  jq -n --arg tag "$NOBRAND_VLESS_TAG" --arg listen "$listen" --arg port "$port" \
    --arg uuid "$uuid" --argjson finalmask "$finalmask" '
    {
      "log": {"loglevel":"warning"},
      "inbounds": [{
        "tag": $tag,
        "listen": $listen,
        "port": ($port|tonumber),
        "protocol": "vless",
        "settings": {
          "clients": [{"id":$uuid,"email":"vless-sudoku@nobrand"}],
          "decryption": "none"
        },
        "streamSettings": {
          "network": "tcp",
          "security": "none",
          "finalmask": $finalmask
        },
        "sniffing": {
          "enabled": true,
          "destOverride": ["http","tls"]
        }
      }],
      "outbounds": [{"tag":"direct","protocol":"freedom"}],
      "routing": {"rules":[]}
    }
  ' >"$output"
}

vless_sudoku_build_share_link() {
  local uuid="$1" host="$2" port="$3" finalmask_json="$4"
  local host_uri fm_uri name_uri
  vless_sudoku_valid_uuid "$uuid" && [ -n "$host" ] && nb_valid_port "$port" || return 1
  jq -e '.tcp[0].type == "sudoku"' <<<"$finalmask_json" >/dev/null 2>&1 || return 1
  host_uri="$(url_host "$host")"
  fm_uri="$(urlencode "$finalmask_json")" || return 1
  name_uri="$(urlencode 'NoBrand-VLESS-Sudoku')" || return 1
  printf 'vless://%s@%s:%s?type=tcp&security=none&encryption=none&fm=%s#%s' \
    "$uuid" "$host_uri" "$port" "$fm_uri" "$name_uri"
}

vless_sudoku_generate_client_config() {
  local output="$1" host="$2" port="$3" uuid="$4" password="$5"
  local socks_port="${6:-$VLESS_SUDOKU_CLIENT_SOCKS_PORT}" finalmask
  finalmask="$(vless_sudoku_finalmask_json "$password")" || return 1
  { valid_advertise_host "$host" || [ "$host" = YOUR_SERVER_IP ]; } \
    && nb_valid_port "$port" && nb_valid_port "$socks_port" \
    && vless_sudoku_valid_uuid "$uuid" || return 1
  jq -n --arg host "$host" --arg port "$port" --arg uuid "$uuid" \
    --arg socks_port "$socks_port" --argjson finalmask "$finalmask" '
    {
      "log": {"loglevel":"warning"},
      "inbounds": [{
        "tag":"local-socks",
        "listen":"127.0.0.1",
        "port":($socks_port|tonumber),
        "protocol":"socks",
        "settings":{"udp":true}
      }],
      "outbounds": [{
        "tag":"vless-sudoku-out",
        "protocol":"vless",
        "settings": {
          "vnext": [{
            "address":$host,
            "port":($port|tonumber),
            "users":[{"id":$uuid,"encryption":"none"}]
          }]
        },
        "streamSettings": {
          "network":"tcp",
          "security":"none",
          "finalmask":$finalmask
        }
      }]
    }
  ' >"$output"
}

vless_sudoku_forbidden_absent() {
  local file
  for file in "$@"; do
    [ -f "$file" ] || return 1
    if grep -Eqi 'vlessenc|mlkem|xorpub|server_ticket|enc_method|client_rtt|vless_encryption|vless_decryption' "$file"; then
      return 1
    fi
    jq -e '
      ([.. | objects | to_entries[] |
        select((.key | ascii_downcase) |
          test("^(vlessenc|mlkem|xorpub|server_ticket|enc_method|client_rtt|vless_encryption|vless_decryption|decryption_secret|encryption_secret)$"))]
       | length) == 0 and
      ([.. | objects | to_entries[] |
        select(((.key | ascii_downcase) == "encryption" or
                (.key | ascii_downcase) == "decryption") and
               .value != "none")]
       | length) == 0
    ' "$file" >/dev/null 2>&1 || return 1
  done
}

vless_sudoku_state_matches() {
  local state="${1:-$NOBRAND_VLESS_STATE_FILE}"
  jq -e --arg tag "$NOBRAND_VLESS_TAG" '
    .protocol == "vless-sudoku" and
    (.uuid | type == "string" and test("^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$")) and
    (.listen_host | type == "string" and length > 0) and
    (.listen_port | type == "number" and . >= 1 and . <= 65535 and floor == .) and
    .transport == "tcp" and
    ((.advertise_mode == "auto" and .advertise_host == "" and .advertise_port == "") or
     (.advertise_mode == "custom" and (.advertise_host | type == "string" and length > 0) and
      (.advertise_port | type == "number" and . >= 1 and . <= 65535 and floor == .))) and
    .finalmask_mode == "sudoku" and
    (.finalmask_json.tcp | length) == 1 and
    .finalmask_json.tcp[0].type == "sudoku" and
    (.finalmask_json.tcp[0].settings.password | type == "string" and test("^[0-9A-Fa-f]{32}$")) and
    .finalmask_json.tcp[0].settings.ascii == "prefer_ascii" and
    .finalmask_json.tcp[0].settings.paddingMin == 0 and
    .finalmask_json.tcp[0].settings.paddingMax == 3 and
    .tag == $tag and
    (.runtime_version | type == "string" and length > 0) and
    (.link | type == "string" and startswith("vless://") and contains("type=tcp") and
      contains("security=none") and contains("encryption=none") and contains("fm=")) and
    .client_config == "client.json" and
    (.enabled | type) == "boolean" and
    (.created_at | type == "string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")) and
    (.updated_at | type == "string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$"))
  ' "$state" >/dev/null 2>&1 && vless_sudoku_forbidden_absent "$state"
}

vless_sudoku_server_config_matches() {
  local config="${1:-$NOBRAND_VLESS_CONFIG_FILE}" uuid="${2:-}" port="${3:-}" password="${4:-}"
  local listen="${5:-}"
  [ -n "$uuid" ] || uuid="$(vless_sudoku_state_field uuid)" || return 1
  [ -n "$port" ] || port="$(vless_sudoku_state_field listen_port)" || return 1
  [ -n "$password" ] || password="$(jq -r '.finalmask_json.tcp[0].settings.password // empty' "$NOBRAND_VLESS_STATE_FILE")"
  [ -n "$listen" ] || listen="$(vless_sudoku_state_field listen_host)" || return 1
  jq -e --arg tag "$NOBRAND_VLESS_TAG" --arg uuid "$uuid" --arg port "$port" \
    --arg password "$password" --arg listen "$listen" '
    (.inbounds | length) == 1 and
    .inbounds[0].tag == $tag and
    .inbounds[0].listen == $listen and
    .inbounds[0].protocol == "vless" and
    .inbounds[0].port == ($port|tonumber) and
    .inbounds[0].settings.clients == [{"id":$uuid,"email":"vless-sudoku@nobrand"}] and
    .inbounds[0].settings.decryption == "none" and
    .inbounds[0].streamSettings.network == "tcp" and
    .inbounds[0].streamSettings.security == "none" and
    .inbounds[0].streamSettings.finalmask.tcp == [{
      "type":"sudoku",
      "settings":{
        "password":$password,
        "ascii":"prefer_ascii",
        "paddingMin":0,
        "paddingMax":3
      }
    }]
  ' "$config" >/dev/null 2>&1 && vless_sudoku_forbidden_absent "$config"
}

vless_sudoku_client_config_matches() {
  local config="${1:-$NOBRAND_VLESS_CLIENT_FILE}" host="${2:-}" port="${3:-}"
  local uuid="${4:-}" password="${5:-}"
  [ -n "$host" ] || {
    local mode advertise_host
    mode="$(vless_sudoku_state_field advertise_mode)" || return 1
    advertise_host="$(vless_sudoku_state_field advertise_host)"
    host="$(nb_effective_advertise_host "$mode" "$advertise_host")"
  }
  [ -n "$port" ] || {
    local mode advertise_port listen_port
    mode="$(vless_sudoku_state_field advertise_mode)" || return 1
    advertise_port="$(vless_sudoku_state_field advertise_port)"
    listen_port="$(vless_sudoku_state_field listen_port)"
    port="$(nb_effective_advertise_port "$mode" "$advertise_port" "$listen_port")"
  }
  [ -n "$uuid" ] || uuid="$(vless_sudoku_state_field uuid)" || return 1
  [ -n "$password" ] \
    || password="$(jq -r '.finalmask_json.tcp[0].settings.password // empty' "$NOBRAND_VLESS_STATE_FILE")"
  jq -e --arg host "$host" --arg port "$port" --arg uuid "$uuid" --arg password "$password" '
    .outbounds[0].protocol == "vless" and
    .outbounds[0].settings.vnext[0].address == $host and
    .outbounds[0].settings.vnext[0].port == ($port|tonumber) and
    .outbounds[0].settings.vnext[0].users == [{"id":$uuid,"encryption":"none"}] and
    .outbounds[0].streamSettings.network == "tcp" and
    .outbounds[0].streamSettings.security == "none" and
    .outbounds[0].streamSettings.finalmask.tcp == [{
      "type":"sudoku",
      "settings":{
        "password":$password,
        "ascii":"prefer_ascii",
        "paddingMin":0,
        "paddingMax":3
      }
    }]
  ' "$config" >/dev/null 2>&1 && vless_sudoku_forbidden_absent "$config"
}

vless_sudoku_current_share_link() {
  local uuid listen_port mode advertise_host advertise_port host port finalmask
  vless_sudoku_state_exists || return 1
  uuid="$(vless_sudoku_state_field uuid)"
  listen_port="$(vless_sudoku_state_field listen_port)"
  mode="$(vless_sudoku_state_field advertise_mode)"
  advertise_host="$(vless_sudoku_state_field advertise_host)"
  advertise_port="$(vless_sudoku_state_field advertise_port)"
  host="$(nb_effective_advertise_host "$mode" "$advertise_host")"
  port="$(nb_effective_advertise_port "$mode" "$advertise_port" "$listen_port")"
  finalmask="$(jq -c '.finalmask_json' "$NOBRAND_VLESS_STATE_FILE")" || return 1
  vless_sudoku_build_share_link "$uuid" "$host" "$port" "$finalmask"
}

vless_sudoku_generate_state() {
  local output="$1" listen="$2" port="$3" uuid="$4" password="$5"
  local advertise_mode="$6" advertise_host="$7" advertise_port="$8" created_at="${9:-}"
  local updated_at runtime_version finalmask effective_host effective_port link
  [ -n "$created_at" ] || created_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  updated_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  runtime_version="$(nobrand_xray_version 2>/dev/null || printf unknown)"
  finalmask="$(vless_sudoku_finalmask_json "$password")" || return 1
  effective_host="$(nb_effective_advertise_host "$advertise_mode" "$advertise_host")"
  effective_port="$(nb_effective_advertise_port "$advertise_mode" "$advertise_port" "$port")"
  link="$(vless_sudoku_build_share_link "$uuid" "$effective_host" "$effective_port" "$finalmask")" || return 1
  jq -n --arg uuid "$uuid" --arg listen "$listen" --arg port "$port" \
    --arg mode "$advertise_mode" --arg advertise_host "$advertise_host" \
    --arg advertise_port "$advertise_port" --arg tag "$NOBRAND_VLESS_TAG" \
    --arg runtime "$runtime_version" --arg link "$link" --arg created "$created_at" \
    --arg updated "$updated_at" --argjson finalmask "$finalmask" '
    {
      "protocol":"vless-sudoku",
      "uuid":$uuid,
      "listen_host":$listen,
      "listen_port":($port|tonumber),
      "transport":"tcp",
      "advertise_mode":$mode,
      "advertise_host":$advertise_host,
      "advertise_port":(if $advertise_port=="" then "" else ($advertise_port|tonumber) end),
      "finalmask_mode":"sudoku",
      "finalmask_json":$finalmask,
      "tag":$tag,
      "runtime_version":$runtime,
      "link":$link,
      "client_config":"client.json",
      "enabled":true,
      "created_at":$created,
      "updated_at":$updated
    }
  ' >"$output"
}

vless_sudoku_snapshot_file() {
  local source="$1" destination="$2"
  if [ -e "$source" ]; then cp -a "$source" "$destination"; else printf absent >"${destination}.absent"; fi
}

vless_sudoku_restore_snapshot_file() {
  local snapshot="$1" destination="$2"
  if [ -f "${snapshot}.absent" ]; then
    rm -f "$destination"
  elif [ -e "$snapshot" ]; then
    mkdir -p "$(dirname "$destination")"
    cp -a "$snapshot" "$destination"
  fi
}

vless_sudoku_configure_requests() {
  local interactive="${1:-0}" old_port="" old_password="" conflict_owner=""
  VLESS_SUDOKU_LISTEN="0.0.0.0"
  if vless_sudoku_state_exists; then
    old_port="$(vless_sudoku_state_field listen_port 2>/dev/null || true)"
    VLESS_SUDOKU_UUID="$(vless_sudoku_state_field uuid 2>/dev/null || true)"
    old_password="$(jq -r '.finalmask_json.tcp[0].settings.password // empty' "$NOBRAND_VLESS_STATE_FILE" 2>/dev/null)"
  fi
  if [ -z "${PORT:-}" ]; then
    PORT="$(nb_select_available_port TCP)" || die '未找到可用 VLESS Sudoku TCP 端口'
    PORT_AUTO_SELECTED=1
  else
    nb_valid_port "$PORT" || die 'VLESS Sudoku 端口必须是 1-65535'
    PORT="$(normalize_uint "$PORT")"
    nb_warn_if_outside_recommended_range "$PORT"
    if [ "$PORT" != "$old_port" ] \
       && ! nb_port_available_for_transport "$PORT" TCP 'vless-sudoku:default'; then
      warn "VLESS Sudoku TCP/${PORT} 已占用"
      nb_describe_port_conflict TCP "$PORT"
      return 1
    fi
  fi
  if [ "$interactive" -eq 1 ] && [ "${ADVERTISE_CLI:-0}" -eq 0 ]; then
    nb_collect_advertise_endpoint_interactive 'VLESS Sudoku' "$PORT"
  else
    nb_require_explicit_endpoint_noninteractive
  fi
  nb_validate_advertise_endpoint "$ADVERTISE_HOST" "$ADVERTISE_PORT" TCP \
    || die 'VLESS Sudoku Display Endpoint 无效'
  if [ -n "$ADVERTISE_HOST" ]; then
    conflict_owner="$(nb_endpoint_conflict_owner TCP "$ADVERTISE_HOST" "$ADVERTISE_PORT" \
      'vless-sudoku:default' 2>/dev/null || true)"
    [ -z "$conflict_owner" ] || die "VLESS Sudoku Display Endpoint 与 ${conflict_owner} 冲突"
  fi
  vless_sudoku_valid_uuid "$VLESS_SUDOKU_UUID" \
    || VLESS_SUDOKU_UUID="$(vless_sudoku_generate_uuid)" \
    || die '无法生成 VLESS UUID'
  if [[ "$old_password" =~ ^[0-9A-Fa-f]{32}$ ]]; then
    VLESS_SUDOKU_PASSWORD="$old_password"
  else
    VLESS_SUDOKU_PASSWORD="$(openssl rand -hex 16 2>/dev/null || true)"
    [[ "$VLESS_SUDOKU_PASSWORD" =~ ^[0-9A-Fa-f]{32}$ ]] \
      || die '无法生成 FinalMask Sudoku password'
  fi
}

vless_sudoku_install_rollback() {
  local snapshot="$1" was_active="$2" new_binding_owned="$3"
  nobrand_vless_sudoku_service_action stop >/dev/null 2>&1 || true
  [ "$new_binding_owned" -eq 0 ] \
    || nb_firewall_close_pairs "TCP|${PORT}" >/dev/null 2>&1 || true
  vless_sudoku_restore_snapshot_file "$snapshot/config" "$NOBRAND_VLESS_CONFIG_FILE"
  vless_sudoku_restore_snapshot_file "$snapshot/state" "$NOBRAND_VLESS_STATE_FILE"
  vless_sudoku_restore_snapshot_file "$snapshot/client" "$NOBRAND_VLESS_CLIENT_FILE"
  vless_sudoku_restore_snapshot_file "$snapshot/service-systemd" "$NOBRAND_VLESS_SYSTEMD_SERVICE"
  vless_sudoku_restore_snapshot_file "$snapshot/service-openrc" "$NOBRAND_VLESS_OPENRC_SERVICE"
  vless_sudoku_restore_snapshot_file "$snapshot/xray" "$NOBRAND_XRAY_BIN"
  [ "$(nb_service_manager)" != systemd ] || systemctl daemon-reload >/dev/null 2>&1 || true
  [ "$was_active" -eq 0 ] \
    || nobrand_vless_sudoku_service_action start >/dev/null 2>&1 || true
}

install_vless_sudoku() {
  local interactive=0 snapshot config_tmp state_tmp client_tmp advertise_mode
  local old_port="" old_created="" was_active=0 binding_was_owned=0 binding_now_owned=0
  [ "${YES:-0}" -eq 1 ] || interactive=1
  nobrand_prepare_common
  admin_lock_acquire || return 1
  snapshot="$(mktemp_dir)" || { admin_lock_release; return 1; }
  vless_sudoku_snapshot_file "$NOBRAND_VLESS_CONFIG_FILE" "$snapshot/config"
  vless_sudoku_snapshot_file "$NOBRAND_VLESS_STATE_FILE" "$snapshot/state"
  vless_sudoku_snapshot_file "$NOBRAND_VLESS_CLIENT_FILE" "$snapshot/client"
  vless_sudoku_snapshot_file "$NOBRAND_VLESS_SYSTEMD_SERVICE" "$snapshot/service-systemd"
  vless_sudoku_snapshot_file "$NOBRAND_VLESS_OPENRC_SERVICE" "$snapshot/service-openrc"
  vless_sudoku_snapshot_file "$NOBRAND_XRAY_BIN" "$snapshot/xray"
  nobrand_vless_sudoku_service_active && was_active=1
  if vless_sudoku_state_exists; then
    old_port="$(vless_sudoku_state_field listen_port 2>/dev/null || true)"
    old_created="$(vless_sudoku_state_field created_at 2>/dev/null || true)"
  fi
  if ! nobrand_install_xray_runtime 0 || ! vless_sudoku_configure_requests "$interactive"; then
    vless_sudoku_install_rollback "$snapshot" "$was_active" 0
    rm -rf -- "$snapshot"
    admin_lock_release
    return 1
  fi
  nb_firewall_binding_owned TCP "$PORT" && binding_was_owned=1
  if [ "$was_active" -eq 1 ]; then
    nobrand_vless_sudoku_service_action stop || {
      vless_sudoku_install_rollback "$snapshot" "$was_active" 0
      rm -rf -- "$snapshot"; admin_lock_release; return 1;
    }
  fi
  if ! nb_port_available_for_transport "$PORT" TCP 'vless-sudoku:default'; then
    warn "提交前发现 TCP/${PORT} 已被其它进程占用"
    nb_describe_port_conflict TCP "$PORT"
    vless_sudoku_install_rollback "$snapshot" "$was_active" 0
    rm -rf -- "$snapshot"; admin_lock_release; return 1
  fi
  config_tmp="$(mktemp_file .json)" || {
    vless_sudoku_install_rollback "$snapshot" "$was_active" 0
    rm -rf -- "$snapshot"; admin_lock_release; return 1;
  }
  state_tmp="$(mktemp_file .json)" || {
    rm -f "$config_tmp"; vless_sudoku_install_rollback "$snapshot" "$was_active" 0
    rm -rf -- "$snapshot"; admin_lock_release; return 1;
  }
  client_tmp="$(mktemp_file .json)" || {
    rm -f "$config_tmp" "$state_tmp"; vless_sudoku_install_rollback "$snapshot" "$was_active" 0
    rm -rf -- "$snapshot"; admin_lock_release; return 1;
  }
  advertise_mode="$(nb_endpoint_mode_from_values "$ADVERTISE_HOST")"
  local effective_host effective_port
  effective_host="$(nb_effective_advertise_host "$advertise_mode" "$ADVERTISE_HOST")"
  effective_port="$(nb_effective_advertise_port "$advertise_mode" "$ADVERTISE_PORT" "$PORT")"
  if ! vless_sudoku_generate_server_config "$config_tmp" "$VLESS_SUDOKU_LISTEN" "$PORT" \
       "$VLESS_SUDOKU_UUID" "$VLESS_SUDOKU_PASSWORD" \
     || ! nobrand_xray_test_config "$config_tmp" \
     || ! vless_sudoku_server_config_matches "$config_tmp" "$VLESS_SUDOKU_UUID" "$PORT" \
       "$VLESS_SUDOKU_PASSWORD" "$VLESS_SUDOKU_LISTEN" \
     || ! vless_sudoku_generate_state "$state_tmp" "$VLESS_SUDOKU_LISTEN" "$PORT" \
       "$VLESS_SUDOKU_UUID" "$VLESS_SUDOKU_PASSWORD" "$advertise_mode" \
       "$ADVERTISE_HOST" "$ADVERTISE_PORT" "$old_created" \
     || ! vless_sudoku_generate_client_config "$client_tmp" "$effective_host" "$effective_port" \
       "$VLESS_SUDOKU_UUID" "$VLESS_SUDOKU_PASSWORD" \
     || ! vless_sudoku_client_config_matches "$client_tmp" "$effective_host" "$effective_port" \
       "$VLESS_SUDOKU_UUID" "$VLESS_SUDOKU_PASSWORD" \
     || ! vless_sudoku_state_matches "$state_tmp" \
     || ! nb_atomic_install_file "$config_tmp" "$NOBRAND_VLESS_CONFIG_FILE" 0600 \
     || ! nobrand_write_vless_sudoku_service \
     || ! nb_firewall_open_pairs "TCP|${PORT}"; then
    rm -f "$config_tmp" "$state_tmp" "$client_tmp"
    nb_firewall_binding_owned TCP "$PORT" \
      && [ "$binding_was_owned" -eq 0 ] && binding_now_owned=1
    vless_sudoku_install_rollback "$snapshot" "$was_active" "$binding_now_owned"
    rm -rf -- "$snapshot"; admin_lock_release; return 1
  fi
  rm -f "$config_tmp"
  nb_firewall_binding_owned TCP "$PORT" \
    && [ "$binding_was_owned" -eq 0 ] && binding_now_owned=1
  local service_action=start
  [ "$was_active" -eq 0 ] || service_action=restart
  if ! nobrand_vless_sudoku_service_action "$service_action" \
     || ! nobrand_vless_sudoku_service_active \
     || ! nb_wait_for_listener TCP "$PORT" 25 \
     || ! nb_atomic_install_file "$client_tmp" "$NOBRAND_VLESS_CLIENT_FILE" 0600 \
     || ! nb_atomic_install_file "$state_tmp" "$NOBRAND_VLESS_STATE_FILE" 0600; then
    rm -f "$state_tmp" "$client_tmp"
    vless_sudoku_install_rollback "$snapshot" "$was_active" "$binding_now_owned"
    rm -rf -- "$snapshot"; admin_lock_release
    warn 'VLESS Sudoku 服务、listener 或 state 验收失败，已回滚'
    return 1
  fi
  rm -f "$state_tmp" "$client_tmp"
  if [ -n "$old_port" ] && [ "$old_port" != "$PORT" ]; then
    nb_firewall_close_pairs "TCP|${old_port}" || true
  fi
  nobrand_install_manager_script || true
  rm -rf -- "$snapshot"
  admin_lock_release
  print_vless_sudoku_result install
}

vless_sudoku_set_endpoint() {
  local interactive=0 state_tmp client_tmp snapshot mode owner uuid password host port link finalmask
  require_root
  vless_sudoku_state_exists || die 'VLESS Sudoku 未安装'
  [ "${YES:-0}" -eq 1 ] || interactive=1
  PORT="$(vless_sudoku_state_field listen_port)"
  if [ "$interactive" -eq 1 ] && [ "${ADVERTISE_CLI:-0}" -eq 0 ]; then
    nb_collect_advertise_endpoint_interactive 'VLESS Sudoku' "$PORT"
  else
    nb_require_explicit_endpoint_noninteractive
  fi
  nb_validate_advertise_endpoint "$ADVERTISE_HOST" "$ADVERTISE_PORT" TCP \
    || die 'Display Endpoint 无效'
  if [ -n "$ADVERTISE_HOST" ]; then
    owner="$(nb_endpoint_conflict_owner TCP "$ADVERTISE_HOST" "$ADVERTISE_PORT" \
      'vless-sudoku:default' 2>/dev/null || true)"
    [ -z "$owner" ] || die "Display Endpoint 与 ${owner} 冲突"
  fi
  admin_lock_acquire || return 1
  snapshot="$(mktemp_dir)" || { admin_lock_release; return 1; }
  vless_sudoku_snapshot_file "$NOBRAND_VLESS_STATE_FILE" "$snapshot/state"
  vless_sudoku_snapshot_file "$NOBRAND_VLESS_CLIENT_FILE" "$snapshot/client"
  state_tmp="$(mktemp_file .json)" || { rm -rf -- "$snapshot"; admin_lock_release; return 1; }
  client_tmp="$(mktemp_file .json)" || {
    rm -f "$state_tmp"; rm -rf -- "$snapshot"; admin_lock_release; return 1;
  }
  mode="$(nb_endpoint_mode_from_values "$ADVERTISE_HOST")"
  uuid="$(vless_sudoku_state_field uuid)"
  password="$(jq -r '.finalmask_json.tcp[0].settings.password' "$NOBRAND_VLESS_STATE_FILE")"
  finalmask="$(vless_sudoku_finalmask_json "$password")" || {
    rm -f "$state_tmp" "$client_tmp"; rm -rf -- "$snapshot"; admin_lock_release; return 1;
  }
  host="$(nb_effective_advertise_host "$mode" "$ADVERTISE_HOST")"
  port="$(nb_effective_advertise_port "$mode" "$ADVERTISE_PORT" "$PORT")"
  link="$(vless_sudoku_build_share_link "$uuid" "$host" "$port" "$finalmask")" || {
    rm -f "$state_tmp" "$client_tmp"; rm -rf -- "$snapshot"; admin_lock_release; return 1;
  }
  if ! jq --arg mode "$mode" --arg host "$ADVERTISE_HOST" --arg port "$ADVERTISE_PORT" \
      --arg link "$link" --arg updated "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
        .advertise_mode=$mode |
        .advertise_host=$host |
        .advertise_port=(if $port=="" then "" else ($port|tonumber) end) |
        .link=$link |
        .updated_at=$updated
      ' "$NOBRAND_VLESS_STATE_FILE" >"$state_tmp" \
     || ! vless_sudoku_generate_client_config "$client_tmp" "$host" "$port" "$uuid" "$password" \
     || ! vless_sudoku_client_config_matches "$client_tmp" "$host" "$port" \
     || ! nb_atomic_install_file "$client_tmp" "$NOBRAND_VLESS_CLIENT_FILE" 0600 \
     || ! nb_atomic_install_file "$state_tmp" "$NOBRAND_VLESS_STATE_FILE" 0600; then
    vless_sudoku_restore_snapshot_file "$snapshot/state" "$NOBRAND_VLESS_STATE_FILE"
    vless_sudoku_restore_snapshot_file "$snapshot/client" "$NOBRAND_VLESS_CLIENT_FILE"
    rm -f "$state_tmp" "$client_tmp"; rm -rf -- "$snapshot"; admin_lock_release
    return 1
  fi
  rm -f "$state_tmp" "$client_tmp"; rm -rf -- "$snapshot"
  # 本函数禁止调用 service、firewall 或 server config writer。
  admin_lock_release
  t 'VLESS Sudoku 客户端展示入口已更新；server config/listener/PID/service/firewall 均未改变' \
    'VLESS Sudoku display endpoint updated; server config/listener/PID/service/firewall are unchanged'
  print_vless_sudoku_result show
}

vless_sudoku_running() {
  local port
  vless_sudoku_state_exists || return 1
  port="$(vless_sudoku_state_field listen_port)"
  nobrand_vless_sudoku_service_active && nb_port_is_listening TCP "$port"
}

vless_sudoku_state_set_enabled() {
  local enabled="$1" tmp
  tmp="$(mktemp_file .json)" || return 1
  if ! jq --argjson enabled "$enabled" --arg updated "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      '.enabled=$enabled | .updated_at=$updated' "$NOBRAND_VLESS_STATE_FILE" >"$tmp" \
     || ! nb_atomic_install_file "$tmp" "$NOBRAND_VLESS_STATE_FILE" 0600; then
    rm -f "$tmp"
    return 1
  fi
  rm -f "$tmp"
}

vless_sudoku_node_rows() {
  local mode advertise_host advertise_port listen_port host port status
  vless_sudoku_state_exists || return 0
  mode="$(vless_sudoku_state_field advertise_mode)"
  advertise_host="$(vless_sudoku_state_field advertise_host)"
  advertise_port="$(vless_sudoku_state_field advertise_port)"
  listen_port="$(vless_sudoku_state_field listen_port)"
  host="$(nb_effective_advertise_host "$mode" "$advertise_host")"
  port="$(nb_effective_advertise_port "$mode" "$advertise_port" "$listen_port")"
  status=Stopped; vless_sudoku_running && status=Running
  printf 'VLESS/Sudoku|sudoku|%s:%s/TCP|%s|TCP\n' "$host" "$port" "$status"
}

print_vless_sudoku_result() {
  local context="${1:-show}" uuid listen_host listen_port mode advertise_host advertise_port
  local host port status link finalmask password
  vless_sudoku_state_exists || { t 'VLESS Sudoku 未安装' 'VLESS Sudoku is not installed'; return 0; }
  uuid="$(vless_sudoku_state_field uuid)"
  listen_host="$(vless_sudoku_state_field listen_host)"
  listen_port="$(vless_sudoku_state_field listen_port)"
  mode="$(vless_sudoku_state_field advertise_mode)"
  advertise_host="$(vless_sudoku_state_field advertise_host)"
  advertise_port="$(vless_sudoku_state_field advertise_port)"
  host="$(nb_effective_advertise_host "$mode" "$advertise_host")"
  port="$(nb_effective_advertise_port "$mode" "$advertise_port" "$listen_port")"
  finalmask="$(jq -c '.finalmask_json' "$NOBRAND_VLESS_STATE_FILE")"
  password="$(jq -r '.finalmask_json.tcp[0].settings.password' "$NOBRAND_VLESS_STATE_FILE")"
  link="$(vless_sudoku_current_share_link)"
  status=Stopped; vless_sudoku_running && status=Running
  nobrand_print_banner
  msg ''
  [ "$context" != install ] || t '部署完成' 'Deployment complete'
  msg '协议        Plain VLESS + FinalMask + Sudoku'
  msg '传输        TCP'
  msg 'VLESS Encryption: NOT USED'
  msg "状态        ${status}"
  msg ''
  msg '真实监听'
  msg "  Address   ${listen_host}"
  msg "  Port      ${listen_port}"
  msg ''
  msg '客户端入口'
  msg "  Host      ${host}"
  msg "  Port      ${port}"
  msg "  Mode      ${mode}"
  msg ''
  msg '认证与 FinalMask'
  msg "  UUID      ${uuid}"
  msg "  Mode      sudoku"
  msg "  Password  ${password}"
  msg "  JSON      ${finalmask}"
  msg ''
  msg "Xray client JSON: ${NOBRAND_VLESS_CLIENT_FILE}"
  msg '========================================'
  msg "$link"
}

vless_sudoku_service_command() {
  local action="$1" port was_enabled
  vless_sudoku_state_exists || die 'VLESS Sudoku 未安装'
  port="$(vless_sudoku_state_field listen_port)"
  was_enabled="$(vless_sudoku_state_field enabled)"
  case "$action" in
    start|restart)
      nobrand_xray_test_config "$NOBRAND_VLESS_CONFIG_FILE" || return 1
      nb_firewall_open_pairs "TCP|${port}" || return 1
      if ! nobrand_vless_sudoku_service_action "$action" \
         || ! nb_wait_for_listener TCP "$port" 25 \
         || ! vless_sudoku_state_set_enabled true; then
        nobrand_vless_sudoku_service_action stop >/dev/null 2>&1 || true
        [ "$was_enabled" = true ] || vless_sudoku_state_set_enabled false >/dev/null 2>&1 || true
        return 1
      fi
      ;;
    stop)
      nobrand_vless_sudoku_service_action stop || return 1
      if ! vless_sudoku_state_set_enabled false; then
        [ "$was_enabled" != true ] \
          || nobrand_vless_sudoku_service_action start >/dev/null 2>&1 || true
        return 1
      fi
      ;;
    status)
      if vless_sudoku_running; then msg 'VLESS Sudoku: Running'; else msg 'VLESS Sudoku: Stopped'; return 1; fi
      ;;
  esac
}

remove_vless_sudoku_config() {
  local port
  require_root
  vless_sudoku_state_exists \
    || { t 'VLESS Sudoku 未安装' 'VLESS Sudoku is not installed'; return 0; }
  port="$(vless_sudoku_state_field listen_port)"
  admin_lock_acquire || return 1
  nobrand_remove_vless_sudoku_service || { admin_lock_release; return 1; }
  nb_firewall_close_pairs "TCP|${port}" || { admin_lock_release; return 1; }
  rm -f "$NOBRAND_VLESS_CONFIG_FILE" "$NOBRAND_VLESS_STATE_FILE" "$NOBRAND_VLESS_CLIENT_FILE"
  rmdir "$NOBRAND_VLESS_CONFIG_DIR" "$NOBRAND_VLESS_STATE_DIR" 2>/dev/null || true
  admin_lock_release
  t '已删除 NoBrand VLESS Sudoku；共享 Xray、HY2、Mieru、Snell 与外部 Xray 均保留' \
    'Removed NoBrand VLESS Sudoku; shared Xray, HY2, Mieru, Snell, and external Xray are preserved'
}

vless_sudoku_doctor() {
  local failed=0 port mode host advertise_port uuid password cached_link current_link
  if ! vless_sudoku_state_exists; then
    nb_doctor_line INFO 'not installed'
    return 0
  fi
  port="$(vless_sudoku_state_field listen_port)"
  uuid="$(vless_sudoku_state_field uuid)"
  password="$(jq -r '.finalmask_json.tcp[0].settings.password // empty' "$NOBRAND_VLESS_STATE_FILE")"
  [ -x "$NOBRAND_XRAY_BIN" ] \
    && nb_doctor_line PASS "Xray $(nobrand_xray_version 2>/dev/null || printf unknown)" \
    || { nb_doctor_line FAIL 'NoBrand Xray binary'; failed=1; }
  vless_sudoku_state_matches \
    && nb_doctor_line PASS 'state schema + plain VLESS metadata' \
    || { nb_doctor_line FAIL 'state schema/metadata'; failed=1; }
  vless_sudoku_server_config_matches "$NOBRAND_VLESS_CONFIG_FILE" "$uuid" "$port" "$password" \
    && nb_doctor_line PASS 'plain VLESS + TCP + FinalMask Sudoku config' \
    || { nb_doctor_line FAIL 'server config semantics'; failed=1; }
  nobrand_xray_test_config "$NOBRAND_VLESS_CONFIG_FILE" \
    && nb_doctor_line PASS 'Xray config test' \
    || { nb_doctor_line FAIL 'Xray config test'; failed=1; }
  vless_sudoku_forbidden_absent "$NOBRAND_VLESS_CONFIG_FILE" \
    "$NOBRAND_VLESS_STATE_FILE" "$NOBRAND_VLESS_CLIENT_FILE" \
    && nb_doctor_line PASS 'VLESS Encryption absent' \
    || { nb_doctor_line FAIL 'forbidden encryption dependency/field detected'; failed=1; }
  vless_sudoku_client_config_matches \
    && nb_doctor_line PASS 'Xray client JSON' \
    || { nb_doctor_line FAIL 'Xray client JSON'; failed=1; }
  vless_sudoku_running \
    && nb_doctor_line PASS "service + TCP/${port}" \
    || { nb_doctor_line FAIL "service/listener TCP/${port}"; failed=1; }
  nb_firewall_binding_owned TCP "$port" \
    && nb_doctor_line PASS "firewall ownership TCP/${port}" \
    || nb_doctor_line INFO "firewall rule not owned (pre-existing/no local firewall): TCP/${port}"
  mode="$(vless_sudoku_state_field advertise_mode)"
  host="$(vless_sudoku_state_field advertise_host)"
  advertise_port="$(vless_sudoku_state_field advertise_port)"
  nb_validate_advertise_endpoint "$host" "$advertise_port" TCP \
    && nb_doctor_line PASS "display endpoint mode=${mode}" \
    || { nb_doctor_line FAIL 'display endpoint state'; failed=1; }
  vless_sudoku_current_share_link >/dev/null \
    && nb_doctor_line PASS 'VLESS URL generation' \
    || { nb_doctor_line FAIL 'VLESS URL generation'; failed=1; }
  cached_link="$(vless_sudoku_state_field link 2>/dev/null || true)"
  current_link="$(vless_sudoku_current_share_link 2>/dev/null || true)"
  [ -n "$current_link" ] && [ "$cached_link" = "$current_link" ] \
    && nb_doctor_line PASS 'cached VLESS URL matches state' \
    || { nb_doctor_line FAIL 'cached VLESS URL mismatch'; failed=1; }
  return "$failed"
}

vless_sudoku_smoke() {
  local failed=0
  vless_sudoku_state_exists || { nb_doctor_line INFO 'VLESS Sudoku not installed'; return 0; }
  vless_sudoku_state_matches \
    && nb_doctor_line PASS 'state schema' || { nb_doctor_line FAIL 'state schema'; failed=1; }
  nobrand_xray_test_config "$NOBRAND_VLESS_CONFIG_FILE" \
    && nb_doctor_line PASS 'xray run -test' || { nb_doctor_line FAIL 'xray run -test'; failed=1; }
  vless_sudoku_forbidden_absent "$NOBRAND_VLESS_CONFIG_FILE" \
    "$NOBRAND_VLESS_STATE_FILE" "$NOBRAND_VLESS_CLIENT_FILE" \
    && nb_doctor_line PASS 'VLESS_ENCRYPTION_ENABLED=false' \
    || { nb_doctor_line FAIL 'VLESS Encryption material detected'; failed=1; }
  vless_sudoku_running \
    && nb_doctor_line PASS 'service/listener' || { nb_doctor_line FAIL 'service/listener'; failed=1; }
  return "$failed"
}

vless_sudoku_refresh_runtime_metadata() {
  local tmp runtime
  vless_sudoku_state_exists || return 0
  runtime="$(nobrand_xray_version)" || return 1
  tmp="$(mktemp_file .json)" || return 1
  jq --arg runtime "$runtime" --arg updated "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '.runtime_version=$runtime | .updated_at=$updated' "$NOBRAND_VLESS_STATE_FILE" >"$tmp" \
    && nb_atomic_install_file "$tmp" "$NOBRAND_VLESS_STATE_FILE" 0600
  local rc=$?
  rm -f "$tmp"
  return "$rc"
}

vless_sudoku_upgrade_runtime() {
  nobrand_upgrade_xray_runtime
}

nobrand_run_vless_sudoku_action() {
  case "${VLESS_SUDOKU_ACTION:-menu}" in
    menu) vless_sudoku_menu_loop ;;
    install) install_vless_sudoku ;;
    show) print_vless_sudoku_result show ;;
    set-endpoint) vless_sudoku_set_endpoint ;;
    remove) remove_vless_sudoku_config ;;
    start|stop|restart|status) vless_sudoku_service_command "$VLESS_SUDOKU_ACTION" ;;
    doctor) vless_sudoku_doctor ;;
    smoke) vless_sudoku_smoke ;;
    upgrade) vless_sudoku_upgrade_runtime ;;
    help) nobrand_usage ;;
  esac
}

mita_socket_paths() {
  printf '%s\n' /var/run/mita/mita.sock /run/mita/mita.sock /var/run/mita.sock
}

mita_log_tail() {
  local f
  for f in /var/log/mita.err /var/log/mita.log; do
    if [ -s "$f" ]; then
      warn "$(t "mita 日志 (${f}):" "mita log (${f}):")"
      tail -n 8 "$f" 2>/dev/null | while IFS= read -r line; do
        msg "  $line"
      done
    fi
  done
}

wait_mita_socket() {
  local timeout="${1:-45}" i=0 sock
  while [ "$i" -lt "$timeout" ]; do
    while IFS= read -r sock; do
      [ -S "$sock" ] 2>/dev/null && return 0
    done < <(mita_socket_paths)
    sleep 1
    i=$((i + 1))
  done
  return 1
}

ensure_mita_daemon() {
  if [ "${DRY_RUN:-0}" -eq 1 ]; then
    msg "[dry-run] ensure mita management daemon"
    return 0
  fi
  local sm
  sm="$(service_manager)"
  case "$sm" in
    systemd)
      run systemctl enable mita 2>/dev/null || true
      run systemctl start mita 2>/dev/null || run systemctl restart mita 2>/dev/null || true
      ;;
    openrc)
      run rc-update add mita default 2>/dev/null || true
      openrc_mita_recover
      if ! openrc_mita_is_started; then
        mita_log_tail
      fi
      ;;
    *)
      run "$(mita_bin)" run >/dev/null 2>&1 &
      ;;
  esac
}

apply_config() {
  local cfg="$1"
  STAGE="应用配置"
  local bin err_file i=0
  if [ "${DRY_RUN:-0}" -eq 1 ]; then
    msg "[dry-run] mita apply config $cfg"
    rm -f "$cfg" 2>/dev/null || true
    return 0
  fi
  bin="$(mita_bin)"
  err_file="$(mktemp_file .log)"
  ensure_mita_daemon
  if ! wait_mita_socket 45; then
    warn "$(t 'mita 管理进程未就绪，正在重试 apply config...' \
      'mita management daemon not ready, retrying apply config...')"
    mita_log_tail
  fi
  while [ "$i" -lt 5 ]; do
    : >"$err_file"
    if "$bin" apply config "$cfg" 2>"$err_file"; then
      rm -f "$cfg" "$err_file"
      return 0
    fi
    i=$((i + 1))
    ensure_mita_daemon
    wait_mita_socket 10 || true
    sleep 2
  done
  if [ -s "$err_file" ]; then
    warn "$(t 'mita apply 最后一次错误:' 'Last mita apply error:')"
    tail -n 8 "$err_file" >&2 || true
  fi
  rm -f "$cfg" "$err_file"
  warn "$(t '应用配置失败；原配置未被脚本降级或删改' \
    'Failed to apply config; the script did not downgrade or remove any fields')"
  return 1
}

collect_ports_from_mita() {
  local saved_protocol="" saved_port="" saved_port_range=""
  if [ -f "$MITA_STATE" ]; then
    state_file_is_secure "$MITA_STATE" || return 1
    # shellcheck disable=SC1090
    source "$MITA_STATE" 2>/dev/null || true
    saved_protocol="$PROTOCOL"
    saved_port="$PORT"
    saved_port_range="$PORT_RANGE"
  else
    PORT=""
    PORT_RANGE=""
    PROTOCOL="TCP"
  fi

  local desc bin
  bin="$(mita_bin)"
  desc="$("$bin" describe config 2>/dev/null || true)"
  if [ -z "$desc" ]; then
    if [ -n "$saved_protocol" ]; then
      PROTOCOL="$saved_protocol"
      PORT="$saved_port"
      PORT_RANGE="$saved_port_range"
    fi
    return 0
  fi

  PORT="$(printf '%s' "$desc" | sed -n 's/.*"port"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p' | head -n1)"
  PORT_RANGE="$(printf '%s' "$desc" | sed -n 's/.*"portRange"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
  local tcp_count udp_count
  tcp_count="$(printf '%s' "$desc" | grep -c '"protocol"[[:space:]]*:[[:space:]]*"TCP"' || true)"
  udp_count="$(printf '%s' "$desc" | grep -c '"protocol"[[:space:]]*:[[:space:]]*"UDP"' || true)"
  if [ -n "$saved_protocol" ]; then
    PROTOCOL="$saved_protocol"
  elif [ "$tcp_count" -gt 0 ] && [ "$udp_count" -gt 0 ]; then
    PROTOCOL="BOTH"
  elif [ "$udp_count" -gt 0 ]; then
    PROTOCOL="UDP"
  else
    PROTOCOL="TCP"
  fi
}

# 从 mita describe config 输出解析 MTU；优先 JSON，旧环境无 python3 时用单字段回退。
extract_mtu_from_describe() {
  local desc="$1" value=""
  [ -n "$desc" ] || return 1
  if command -v python3 >/dev/null 2>&1; then
    value="$(printf '%s' "$desc" | python3 -c '
import json, sys
try:
    value = json.load(sys.stdin).get("mtu")
except Exception:
    raise SystemExit(1)
if isinstance(value, int):
    print(value)
' 2>/dev/null || true)"
  else
    value="$(printf '%s' "$desc" \
      | sed -n 's/.*"mtu"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p' \
      | head -n1)"
  fi
  valid_mtu "$value" || return 1
  printf '%s' "$value"
}

# 从 mita describe config 输出解析 portBindings，每行 proto|port_or_range
extract_bindings_from_describe() {
  local desc="$1"
  [ -n "$desc" ] || return 0
  if command -v python3 >/dev/null 2>&1; then
    printf '%s' "$desc" | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for binding in data.get("portBindings", []):
    proto = binding.get("protocol", "TCP")
    if "port" in binding:
        print("{}|{}".format(proto, binding.get("port")))
    elif binding.get("portRange"):
        print("{}|{}".format(proto, binding.get("portRange")))
' 2>/dev/null || true
    return 0
  fi
  printf '%s\n' "$desc" | awk '
    /"protocol"[[:space:]]*:/ {
      value=$0
      sub(/^.*"protocol"[[:space:]]*:[[:space:]]*"/, "", value)
      sub(/".*$/, "", value)
      proto=value
    }
    /"portRange"[[:space:]]*:/ {
      value=$0
      sub(/^.*"portRange"[[:space:]]*:[[:space:]]*"/, "", value)
      sub(/".*$/, "", value)
      port=value
    }
    /"port"[[:space:]]*:/ {
      value=$0
      sub(/^.*"port"[[:space:]]*:[[:space:]]*/, "", value)
      sub(/[^0-9].*$/, "", value)
      port=value
    }
    /}/ {
      if (proto != "" && port != "") print proto "|" port
      proto=""; port=""
    }
  '
}

firewall_owned_has() {
  local key="$1"
  [ -f "$MITA_FIREWALL_OWNED_STATE" ] \
    && grep -qxF "$key" "$MITA_FIREWALL_OWNED_STATE" 2>/dev/null
}

firewall_owned_add() {
  local key="$1"
  firewall_owned_has "$key" && return 0
  if [ "${DRY_RUN:-0}" -eq 1 ]; then
    msg "[dry-run] own firewall rule: $key"
    return 0
  fi
  mkdir -p "$(dirname "$MITA_FIREWALL_OWNED_STATE")"
  printf '%s\n' "$key" >>"$MITA_FIREWALL_OWNED_STATE"
  chmod 0600 "$MITA_FIREWALL_OWNED_STATE" 2>/dev/null || true
}

firewall_owned_remove() {
  local key="$1" tmp
  [ -f "$MITA_FIREWALL_OWNED_STATE" ] || return 0
  if [ "${DRY_RUN:-0}" -eq 1 ]; then
    msg "[dry-run] release firewall rule: $key"
    return 0
  fi
  tmp="${MITA_FIREWALL_OWNED_STATE}.new.$$"
  grep -vxF "$key" "$MITA_FIREWALL_OWNED_STATE" >"$tmp" 2>/dev/null || true
  if [ -s "$tmp" ]; then
    chmod 0600 "$tmp" 2>/dev/null || true
    mv -f "$tmp" "$MITA_FIREWALL_OWNED_STATE"
  else
    rm -f "$tmp" "$MITA_FIREWALL_OWNED_STATE"
  fi
}

iptables_remove_owned_rule() {
  local ipt="$1" proto="$2" p="$3" key
  key="${ipt}|${proto}|${p}"
  firewall_owned_has "$key" || return 0
  command -v "$ipt" >/dev/null 2>&1 || return 1
  if "$ipt" -C INPUT -p "$proto" --dport "$p" -m comment \
      --comment "$MITA_FIREWALL_COMMENT" -j ACCEPT 2>/dev/null; then
    run "$ipt" -D INPUT -p "$proto" --dport "$p" -m comment \
      --comment "$MITA_FIREWALL_COMMENT" -j ACCEPT 2>/dev/null || return 1
  fi
  if "$ipt" -C INPUT -p "$proto" --dport "$p" -m comment \
      --comment "$MITA_FIREWALL_COMMENT" -j ACCEPT 2>/dev/null; then
    return 1
  fi
  firewall_owned_remove "$key"
}

ufw_binding_exists() {
  local spec="$1"
  ufw show added 2>/dev/null | grep -Eq \
    "^ufw[[:space:]]+allow([[:space:]]+in)?[[:space:]]+${spec//./\\.}([[:space:]]|$)"
}

firewall_apply_binding() {
  local fw="$1" action="$2" proto="$3" p="$4" spec key
  spec="$(ufw_rule_spec "$p" "$proto")"
  case "${fw}:${action}" in
    ufw:add)
      key="ufw|${proto}|${p}"
      firewall_owned_has "$key" && return 0
      ufw_binding_exists "$spec" && return 0
      if run ufw allow "$spec"; then
        firewall_owned_add "$key"
      fi
      ;;
    ufw:del)
      key="ufw|${proto}|${p}"
      firewall_owned_has "$key" || return 0
      command -v ufw >/dev/null 2>&1 || return 0
      if run ufw --force delete allow "$spec" 2>/dev/null \
         || ! ufw_binding_exists "$spec"; then
        firewall_owned_remove "$key"
      fi
      ;;
    firewalld:add)
      key="firewalld|${proto}|${p}"
      firewall_owned_has "$key" && return 0
      firewall-cmd --permanent --query-port="${p}/${proto}" >/dev/null 2>&1 && return 0
      if run firewall-cmd --permanent --add-port="${p}/${proto}"; then
        firewall_owned_add "$key"
      fi
      ;;
    firewalld:del)
      key="firewalld|${proto}|${p}"
      firewall_owned_has "$key" || return 0
      command -v firewall-cmd >/dev/null 2>&1 || return 0
      if run firewall-cmd --permanent --remove-port="${p}/${proto}" 2>/dev/null \
         || ! firewall-cmd --permanent --query-port="${p}/${proto}" >/dev/null 2>&1; then
        firewall_owned_remove "$key"
      fi
      ;;
    iptables:add|iptables:del)
      iptables_accept_port "$p" "$proto" "$action"
      ;;
  esac
}

close_firewall_for_bindings() {
  local bindings="$1"
  local pp proto p proto_lc
  [ -n "$bindings" ] || return 0

  while IFS= read -r pp; do
    [ -n "$pp" ] || continue
    proto="${pp%%|*}"
    p="${pp#*|}"
    proto_lc="$(proto_lower "$proto")"
    firewall_apply_binding ufw del "$proto_lc" "$p"
    firewall_apply_binding firewalld del "$proto_lc" "$p"
    firewall_apply_binding iptables del "$proto_lc" "$p"
  done <<< "$bindings"

  command -v firewall-cmd >/dev/null 2>&1 \
    && run firewall-cmd --reload 2>/dev/null || true
  persist_iptables_rules
}

firewall_clear_all_owned() {
  local snapshot tool proto p failed=0
  [ -f "$MITA_FIREWALL_OWNED_STATE" ] || return 0
  snapshot="$(mktemp_file .firewall-owned)" || return 1
  cp -f "$MITA_FIREWALL_OWNED_STATE" "$snapshot" || {
    rm -f "$snapshot"
    return 1
  }
  while IFS='|' read -r tool proto p; do
    [ -n "$tool" ] && [ -n "$proto" ] && [ -n "$p" ] || continue
    case "$tool" in
      ufw|firewalld)
        firewall_apply_binding "$tool" del "$proto" "$p" || failed=1
        ;;
      iptables|ip6tables)
        iptables_remove_owned_rule "$tool" "$proto" "$p" || failed=1
        ;;
      *) failed=1 ;;
    esac
  done <"$snapshot"
  rm -f "$snapshot"
  command -v firewall-cmd >/dev/null 2>&1 \
    && run firewall-cmd --reload 2>/dev/null || true
  persist_iptables_rules || failed=1
  # 只有确认规则已不存在才删除所有权记录；残留记录代表清理未完成。
  [ ! -s "$MITA_FIREWALL_OWNED_STATE" ] || failed=1
  [ "$failed" -eq 0 ]
}

ufw_rule_spec() {
  local p="$1"
  local proto="$2"
  if [[ "$p" == *-* ]]; then
    local start="${p%-*}"
    local end="${p#*-}"
    printf '%s:%s/%s' "$start" "$end" "$proto"
  else
    printf '%s/%s' "$p" "$proto"
  fi
}

iptables_accept_port() {
  local p="$1"
  local proto="$2"
  local action="${3:-add}"
  local ipt key
  for ipt in iptables ip6tables; do
    command -v "$ipt" >/dev/null 2>&1 || continue
    if [[ "$p" == *-* ]]; then
      local start end port
      start="${p%-*}"
      end="${p#*-}"
      port="$start"
      while [ "$port" -le "$end" ]; do
        key="${ipt}|${proto}|${port}"
        if [ "$action" = add ]; then
          if "$ipt" -C INPUT -p "$proto" --dport "$port" -m comment \
              --comment "$MITA_FIREWALL_COMMENT" -j ACCEPT 2>/dev/null; then
            firewall_owned_add "$key"
          elif "$ipt" -C INPUT -p "$proto" --dport "$port" -j ACCEPT 2>/dev/null; then
            :
          elif run "$ipt" -I INPUT -p "$proto" --dport "$port" -m comment \
              --comment "$MITA_FIREWALL_COMMENT" -j ACCEPT; then
            firewall_owned_add "$key"
          fi
        elif firewall_owned_has "$key"; then
          iptables_remove_owned_rule "$ipt" "$proto" "$port" || return 1
        fi
        port=$((port + 1))
      done
    else
      key="${ipt}|${proto}|${p}"
      if [ "$action" = add ]; then
        if "$ipt" -C INPUT -p "$proto" --dport "$p" -m comment \
            --comment "$MITA_FIREWALL_COMMENT" -j ACCEPT 2>/dev/null; then
          firewall_owned_add "$key"
        elif "$ipt" -C INPUT -p "$proto" --dport "$p" -j ACCEPT 2>/dev/null; then
          :
        elif run "$ipt" -I INPUT -p "$proto" --dport "$p" -m comment \
            --comment "$MITA_FIREWALL_COMMENT" -j ACCEPT; then
          firewall_owned_add "$key"
        fi
      elif firewall_owned_has "$key"; then
        iptables_remove_owned_rule "$ipt" "$proto" "$p" || return 1
      fi
    fi
  done
}

persist_iptables_rules() {
  if [ -d /etc/iptables ] || [ -f /etc/alpine-release ]; then
    if [ "${DRY_RUN:-0}" -eq 1 ]; then
      msg "[dry-run] iptables-save > /etc/iptables/rules.v4"
      return 0
    fi
    local rules_tmp
    rules_tmp="$(mktemp_file .rules.v4)" || return 1
    run mkdir -p /etc/iptables
    if iptables-save >"$rules_tmp" 2>/dev/null; then
      install -m 0600 "$rules_tmp" /etc/iptables/rules.v4 2>/dev/null || true
    fi
    rm -f "$rules_tmp"
    if command -v ip6tables-save >/dev/null 2>&1; then
      rules_tmp="$(mktemp_file .rules.v6)" || return 1
      if ip6tables-save >"$rules_tmp" 2>/dev/null; then
        install -m 0600 "$rules_tmp" /etc/iptables/rules.v6 2>/dev/null || true
      fi
      rm -f "$rules_tmp"
    fi
  fi
}

open_firewall() {
  STAGE="配置防火墙"
  local pp proto p proto_lc fw=""
  # 多用户：放行所有用户端口
  if [ "${MULTI_USER_MODE:-0}" -eq 1 ] && users_state_exists && [ "$(users_count)" -gt 0 ]; then
    open_firewall_for_pairs "$(multi_user_port_protocol_pairs)"
    return 0
  fi
  if ! pp="$(port_protocol_pairs | head -n1)" || [ -z "$pp" ]; then
    return 0
  fi

  if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q 'Status: active'; then
    fw=ufw
  elif command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
    fw=firewalld
  elif command -v iptables >/dev/null 2>&1; then
    fw=iptables
  else
    warn "$(t '未检测到本地防火墙工具，请仅在云安全组放行端口' \
      'No local firewall tool found; open ports in cloud security group')"
    return 0
  fi

  while IFS= read -r pp; do
    proto="${pp%%|*}"
    p="${pp#*|}"
    proto_lc="$(proto_lower "$proto")"
    firewall_apply_binding "$fw" add "$proto_lc" "$p"
  done < <(port_protocol_pairs)

  case "$fw" in
    firewalld) run firewall-cmd --reload || true ;;
    iptables) persist_iptables_rules ;;
  esac
}

close_firewall() {
  STAGE="清理防火墙规则"
  local desc bindings bin
  if users_state_exists && [ "$(users_count)" -gt 0 ]; then
    close_firewall_for_bindings "$(multi_user_port_protocol_pairs)"
    return 0
  fi
  bin="$(mita_bin)"
  desc="$("$bin" describe config 2>/dev/null || true)"
  bindings="$(extract_bindings_from_describe "$desc")"
  if [ -n "$bindings" ]; then
    close_firewall_for_bindings "$bindings"
    return 0
  fi
  collect_ports_from_mita
  local pp proto p proto_lc fw=""
  if ! pp="$(port_protocol_pairs | head -n1)" || [ -z "$pp" ]; then
    return 0
  fi

  if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q 'Status: active'; then
    fw=ufw
  elif command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
    fw=firewalld
  elif command -v iptables >/dev/null 2>&1; then
    fw=iptables
  else
    return 0
  fi

  while IFS= read -r pp; do
    proto="${pp%%|*}"
    p="${pp#*|}"
    proto_lc="$(proto_lower "$proto")"
    firewall_apply_binding "$fw" del "$proto_lc" "$p"
  done < <(port_protocol_pairs)

  case "$fw" in
    firewalld) run firewall-cmd --reload 2>/dev/null || true ;;
    iptables) persist_iptables_rules ;;
  esac
}

cloud_firewall_hint() {
  local specs=() pp proto p
  while IFS= read -r pp; do
    proto="${pp%%|*}"
    p="${pp#*|}"
    specs+=("${p}/${proto}")
  done < <(port_protocol_pairs)
  [ "${#specs[@]}" -gt 0 ] || return 0
  local spec
  spec="$(IFS=','; printf '%s' "${specs[*]}")"
  msg ""
  t "【云安全组提醒】请在 VPS/云控制台安全组放行: ${spec}" \
    "[Cloud SG] Allow in provider firewall: ${spec}"
}

valid_ip_literal() {
  local value="${1:-}" a b c d extra colons segment remainder
  local -a parts=()
  [ -n "$value" ] || return 1
  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import ipaddress,sys; ipaddress.ip_address(sys.argv[1])' "$value" 2>/dev/null
    return $?
  fi
  if [[ "$value" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    IFS=. read -r a b c d extra <<< "$value"
    [ -z "${extra:-}" ] || return 1
    for segment in "$a" "$b" "$c" "$d"; do
      [[ "$segment" =~ ^[0-9]{1,3}$ ]] && [ "$segment" -le 255 ] || return 1
    done
    return 0
  fi
  [[ "$value" == *:* ]] || return 1
  [[ "$value" =~ ^[0-9A-Fa-f:]+$ ]] || return 1
  [[ "$value" != *:::* ]] || return 1
  colons="${value//[^:]/}"
  [ "${#colons}" -ge 2 ] && [ "${#colons}" -le 7 ] || return 1
  if [[ "$value" == *::* ]]; then
    remainder="${value#*::}"
    [[ "$remainder" != *::* ]] || return 1
  else
    [ "${#colons}" -eq 7 ] || return 1
  fi
  IFS=: read -r -a parts <<< "$value"
  for segment in "${parts[@]}"; do
    [ "${#segment}" -le 4 ] || return 1
  done
  return 0
}

valid_domain_name() {
  local value="${1:-}" label rest
  [ -n "$value" ] && [ "${#value}" -le 253 ] || return 1
  [[ "$value" != *[[:space:]]* ]] || return 1
  [[ "$value" != *://* && "$value" != *:* && "$value" != /* ]] || return 1
  value="${value%.}"
  [ -n "$value" ] || return 1
  rest="$value"
  while true; do
    label="${rest%%.*}"
    [ -n "$label" ] && [ "${#label}" -le 63 ] || return 1
    [[ "$label" =~ ^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?$ ]] || return 1
    [ "$rest" != "$label" ] || break
    rest="${rest#*.}"
  done
}

valid_advertise_host() {
  valid_ip_literal "${1:-}" || valid_domain_name "${1:-}"
}

valid_public_ip_literal() {
  local value="${1:-}"
  valid_ip_literal "$value" || return 1
  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import ipaddress,sys; raise SystemExit(0 if ipaddress.ip_address(sys.argv[1]).is_global else 1)' \
      "$value" 2>/dev/null
    return $?
  fi
  case "$value" in
    10.*|127.*|169.254.*|192.168.*|172.1[6-9].*|172.2[0-9].*|172.3[01].*|\
    100.6[4-9].*|100.[7-9][0-9].*|100.1[01][0-9].*|100.12[0-7].*|\
    ::1|fe8*|fe9*|fea*|feb*|fc*|fd*) return 1 ;;
  esac
  return 0
}

public_ip() {
  local candidate=""
  candidate="$(curl -fsSL --connect-timeout 5 --max-time 10 https://checkip.amazonaws.com 2>/dev/null \
    | head -n1 | tr -d '[:space:]' || true)"
  if valid_public_ip_literal "$candidate"; then
    printf '%s' "$candidate"
    return 0
  fi
  candidate="$(curl -fsSL --connect-timeout 5 --max-time 10 https://api.ip.sb/ip 2>/dev/null \
    | head -n1 | tr -d '[:space:]' || true)"
  if valid_public_ip_literal "$candidate"; then
    printf '%s' "$candidate"
    return 0
  fi
  candidate="$(hostname -I 2>/dev/null | awk '{print $1}' | tr -d '[:space:]' || true)"
  valid_public_ip_literal "$candidate" || return 1
  printf '%s' "$candidate"
}

endpoint_hosts_equal() {
  local left="${1:-}" right="${2:-}"
  [ -n "$left" ] && [ -n "$right" ] || return 1
  left="${left#\[}"; left="${left%\]}"; left="${left%.}"
  right="${right#\[}"; right="${right%\]}"; right="${right%.}"
  if valid_ip_literal "$left" && valid_ip_literal "$right" \
     && command -v python3 >/dev/null 2>&1; then
    python3 -c 'import ipaddress,sys; raise SystemExit(0 if ipaddress.ip_address(sys.argv[1]) == ipaddress.ip_address(sys.argv[2]) else 1)' \
      "$left" "$right" 2>/dev/null
    return $?
  fi
  [ "$(printf '%s' "$left" | tr '[:upper:]' '[:lower:]')" = \
    "$(printf '%s' "$right" | tr '[:upper:]' '[:lower:]')" ]
}

# 成功表示客户端入口与后端不同；显式填写同一公网 IP/端口不算独立入口。
client_endpoint_is_independent() {
  local advertised_port backend_port candidate
  [ -n "${ADVERTISE_HOST:-}" ] || return 1
  advertised_port="$(normalize_uint "${ADVERTISE_PORT:-${PORT:-}}" 2>/dev/null || printf '%s' "${ADVERTISE_PORT:-${PORT:-}}")"
  backend_port="$(normalize_uint "${PORT:-}" 2>/dev/null || printf '%s' "${PORT:-}")"
  [ "$advertised_port" = "$backend_port" ] || return 0
  for candidate in "$@"; do
    [ -n "$candidate" ] || continue
    endpoint_hosts_equal "$ADVERTISE_HOST" "$candidate" && return 1
  done
  return 0
}

advertised_host() {
  if [ -n "${ADVERTISE_HOST:-}" ]; then
    printf '%s' "$ADVERTISE_HOST"
  else
    public_ip
  fi
}

advertised_port_for_protocol() {
  local proto="$1" canonical_port
  if [ -n "${ADVERTISE_PORT:-}" ]; then
    canonical_port="$(normalize_uint "$ADVERTISE_PORT")" || return 1
    if [ "${PROTOCOL:-TCP}" = "BOTH" ] && [ "$proto" = "UDP" ]; then
      printf '%s' "$((canonical_port + 1))"
    else
      printf '%s' "$canonical_port"
    fi
  else
    port_for_protocol "$proto"
  fi
}

client_protocol_label() {
  if [ "${PROTOCOL:-TCP}" = "BOTH" ]; then
    printf 'TCP(%s) + UDP(%s)' \
      "$(advertised_port_for_protocol TCP)" "$(advertised_port_for_protocol UDP)"
  else
    printf '%s' "${PROTOCOL:-TCP}"
  fi
}

start_mita() {
  STAGE="启动服务"
  if [ "${DRY_RUN:-0}" -eq 1 ]; then
    msg "[dry-run] start mita proxy"
    return 0
  fi
  if users_isolated_mode; then
    local iid iname iport
    while IFS=$'\t' read -r iid iname iport; do
      [ -n "$iid" ] || continue
      if ! instance_start_proxy "$iid"; then
        warn "$(t "用户 ${iname} 的专属实例启动失败（${iid}）" \
          "Dedicated instance for ${iname} failed to start (${iid})")"
        return 1
      fi
    done < <(users_enabled_instance_rows)
    return 0
  fi
  local sm bin _attempt
  sm="$(service_manager)"
  bin="$(mita_bin)"
  if wait_mita_socket 1; then
    "$bin" stop 2>/dev/null || true
    sleep 1
  fi
  ensure_mita_daemon
  if ! wait_mita_socket 45; then
    warn "$(t 'mita 管理套接字未就绪，继续尝试 start...' \
      'mita management socket not ready, retrying start...')"
    mita_log_tail
  fi
  for _attempt in 1 2 3 4 5; do
    if "$bin" start 2>/dev/null; then
      sleep 1
      return 0
    fi
    ensure_mita_daemon
    wait_mita_socket 10 || true
    sleep 2
  done
  warn "$(t "mita start 未成功，请手动执行: $(mita_restart_hint) && mita start" \
    "mita start failed; run: $(mita_restart_hint) && mita start")"
  return 1
}

verify_mita_running() {
  STAGE="验证服务状态"
  local quiet="${1:-0}"
  if [ "${DRY_RUN:-0}" -eq 1 ]; then
    msg "[dry-run] verify mita RUNNING"
    return 0
  fi
  if users_isolated_mode; then
    local iid iname iport istatus failed=0
    while IFS=$'\t' read -r iid iname iport; do
      [ -n "$iid" ] || continue
      istatus="$(instance_cmd "$iid" status 2>/dev/null || true)"
      if ! printf '%s' "$istatus" | grep -q 'status is "RUNNING"'; then
        warn "$(t "用户 ${iname} 的专属实例未处于 RUNNING（${iid}）" \
          "Dedicated instance for ${iname} is not RUNNING (${iid})")"
        failed=1
      fi
    done < <(users_enabled_instance_rows)
    [ "$failed" -eq 0 ] || return 1
    [ "$quiet" -eq 1 ] || \
      t '所有用户专属 mita 实例运行正常' 'All dedicated mita user instances are running'
    return 0
  fi
  local bin status_out _attempt
  bin="$(mita_bin)"
  for _attempt in 1 2 3 4 5; do
    sleep 2
    status_out="$("$bin" status 2>/dev/null || true)"
    if printf '%s' "$status_out" | grep -q 'status is "RUNNING"'; then
      [ "$quiet" -eq 1 ] || t 'mita 服务运行正常' 'mita service is running'
      return 0
    fi
    ensure_mita_daemon
    wait_mita_socket 10 || true
    "$bin" start 2>/dev/null || true
  done
  warn "$(t "mita 未处于 RUNNING 状态，请执行: $(mita_restart_hint) && mita status && mita start" \
    "mita is not RUNNING; run: $(mita_restart_hint) && mita status && mita start")"
  [ -n "$status_out" ] && msg "$status_out"
  return 1
}

add_op_user() {
  local u="$1"
  [ -n "$u" ] || return 0
  STAGE="添加操作用户"
  if id "$u" >/dev/null 2>&1; then
    if command -v usermod >/dev/null 2>&1; then
      run usermod -a -G mita "$u"
    else
      run addgroup "$u" mita 2>/dev/null || true
    fi
    t "已将 ${u} 加入 mita 组（需重新登录生效）" "Added ${u} to mita group (re-login required)"
  else
    warn "$(t "用户 ${u} 不存在，已跳过" "User ${u} not found, skipped")"
  fi
}

bbr_fq_sysctl_value() {
  local key="$1" path value=""
  if command -v sysctl >/dev/null 2>&1; then
    value="$(sysctl -n "$key" 2>/dev/null || true)"
  else
    path="/proc/sys/${key//./\/}"
    [ -r "$path" ] && value="$(tr -d '\r\n' <"$path" 2>/dev/null || true)"
  fi
  printf '%s' "$value"
}

bbr_fq_enabled() {
  [ "$(bbr_fq_sysctl_value net.ipv4.tcp_congestion_control)" = "bbr" ] \
    && [ "$(bbr_fq_sysctl_value net.core.default_qdisc)" = "fq" ]
}

bbr_fq_active() {
  local dev
  bbr_fq_enabled || return 1
  command -v tc >/dev/null 2>&1 || return 1
  dev="$(tc_default_iface 2>/dev/null || mtu_default_iface 2>/dev/null || true)"
  [ -n "$dev" ] || return 1
  tc qdisc show dev "$dev" 2>/dev/null \
    | grep -Eq '(^|[[:space:]])qdisc[[:space:]]+fq([[:space:]]|$)'
}

report_bbr_fq_status() {
  if bbr_fq_active; then
    t 'TCP BBR 已启用，当前出口网卡正在使用 FQ' \
      'TCP BBR is enabled and the current egress interface is using FQ'
  else
    warn "$(t 'TCP BBR + FQ 默认策略已配置；当前出口网卡尚未使用 FQ，重启系统或重建网卡后生效' \
      'TCP BBR + FQ defaults are configured; the current egress interface is not using FQ yet, so reboot or recreate the interface to activate it')"
  fi
}

bbr_owned_mode() {
  local mode=""
  [ -f "$BBR_STATE_FILE" ] || return 1
  IFS= read -r mode <"$BBR_STATE_FILE" || return 1
  case "$mode" in
    created|replaced) printf '%s' "$mode" ;;
    *) return 1 ;;
  esac
}

bbr_state_value() {
  local line="$1" value=""
  value="$(sed -n "${line}p" "$BBR_STATE_FILE" 2>/dev/null || true)"
  [[ "$value" =~ ^[A-Za-z0-9_.-]*$ ]] || return 1
  printf '%s' "$value"
}

write_bbr_state() {
  local mode="$1" old_qdisc="$2" old_cc="$3" tmp
  case "$mode" in created|replaced) ;; *) return 1 ;; esac
  [[ "$old_qdisc" =~ ^[A-Za-z0-9_.-]*$ ]] || return 1
  [[ "$old_cc" =~ ^[A-Za-z0-9_.-]*$ ]] || return 1
  tmp="$(mktemp_file .bbr-state)" || return 1
  printf '%s\n%s\n%s\n' "$mode" "$old_qdisc" "$old_cc" >"$tmp"
  install -d -o root -g root -m 0700 "$MITA_MANAGER_STATE_DIR"
  install -o root -g root -m 0600 "$tmp" "$BBR_STATE_FILE"
  rm -f "$tmp"
}

bbr_conf_is_owned() {
  [ -f "$BBR_SYSCTL_CONF" ] || return 1
  [ "$(sed '/^[[:space:]]*#/d;/^[[:space:]]*$/d' "$BBR_SYSCTL_CONF" 2>/dev/null)" = \
    $'net.core.default_qdisc=fq\nnet.ipv4.tcp_congestion_control=bbr' ]
}

restore_bbr_fq() {
  local backup="$1" old_qdisc="$2" old_cc="$3" had_conf="${4:-1}"
  if [ "$had_conf" -eq 1 ] && [ -n "$backup" ] && [ -f "$backup" ]; then
    install -o root -g root -m 0644 "$backup" "$BBR_SYSCTL_CONF" 2>/dev/null || true
  else
    rm -f "$BBR_SYSCTL_CONF" 2>/dev/null || true
  fi
  [ -n "$old_qdisc" ] \
    && sysctl -q -w "net.core.default_qdisc=${old_qdisc}" >/dev/null 2>&1 || true
  [ -n "$old_cc" ] \
    && sysctl -q -w "net.ipv4.tcp_congestion_control=${old_cc}" >/dev/null 2>&1 || true
  [ -z "$backup" ] || rm -f "$backup"
}

restore_owned_bbr_fq() {
  local mode old_qdisc old_cc
  mode="$(bbr_owned_mode 2>/dev/null || true)"
  [ -n "$mode" ] || return 0
  if ! bbr_conf_is_owned; then
    warn "$(t 'BBR sysctl 文件已被外部修改，拒绝在卸载时删除或覆盖；请先人工核对' \
      'The BBR sysctl file was modified externally; refusing to remove or overwrite it during uninstall')"
    return 1
  fi
  old_qdisc="$(bbr_state_value 2)" || return 1
  old_cc="$(bbr_state_value 3)" || return 1
  case "$mode" in
    created)
      rm -f "$BBR_SYSCTL_CONF"
      ;;
    replaced)
      [ -f "$BBR_BACKUP_FILE" ] || {
        warn "$(t '缺少 BBR 原配置备份，拒绝删除当前 sysctl 文件' \
          'BBR original-config backup is missing; refusing to remove the current sysctl file')"
        return 1
      }
      install -o root -g root -m 0644 "$BBR_BACKUP_FILE" "$BBR_SYSCTL_CONF"
      sysctl -p "$BBR_SYSCTL_CONF" >/dev/null 2>&1 || {
        warn "$(t '原 BBR/sysctl 文件已恢复，但重新应用失败' \
          'The original BBR/sysctl file was restored but could not be reapplied')"
        return 1
      }
      ;;
  esac
  [ -z "$old_qdisc" ] \
    || sysctl -q -w "net.core.default_qdisc=${old_qdisc}" >/dev/null 2>&1 || true
  [ -z "$old_cc" ] \
    || sysctl -q -w "net.ipv4.tcp_congestion_control=${old_cc}" >/dev/null 2>&1 || true
  rm -f "$BBR_STATE_FILE" "$BBR_BACKUP_FILE"
}

enable_bbr_fq() {
  STAGE="启用 TCP BBR + FQ"
  if bbr_fq_enabled; then
    report_bbr_fq_status
    return 0
  fi
  require_cmd sysctl

  local available old_qdisc old_cc tmp backup="" had_conf=0 owned_mode="" new_ownership=0
  if command -v modprobe >/dev/null 2>&1; then
    run modprobe tcp_bbr 2>/dev/null || true
    run modprobe sch_fq 2>/dev/null || true
  fi
  available="$(bbr_fq_sysctl_value net.ipv4.tcp_available_congestion_control)"
  case " ${available} " in
    *' bbr '*) ;;
    *)
      die "$(t '当前内核不支持 TCP BBR' 'TCP BBR is not supported by the current kernel')"
      return 1
      ;;
  esac

  old_qdisc="$(bbr_fq_sysctl_value net.core.default_qdisc)"
  old_cc="$(bbr_fq_sysctl_value net.ipv4.tcp_congestion_control)"
  owned_mode="$(bbr_owned_mode 2>/dev/null || true)"
  if [ -e "$BBR_STATE_FILE" ] && [ -z "$owned_mode" ]; then
    die "$(t 'BBR 所有权状态损坏，拒绝覆盖系统 sysctl 配置' \
      'BBR ownership state is invalid; refusing to overwrite system sysctl configuration')"
    return 1
  fi
  if [ -n "$owned_mode" ] && ! bbr_conf_is_owned; then
    die "$(t 'BBR sysctl 文件已被外部修改，拒绝覆盖；请先人工核对' \
      'The BBR sysctl file was modified externally; refusing to overwrite it')"
    return 1
  fi
  if [ -f "$BBR_SYSCTL_CONF" ]; then
    had_conf=1
    backup="$(mktemp_file .bbr-backup)" || return 1
    cp -p "$BBR_SYSCTL_CONF" "$backup" || { rm -f "$backup"; return 1; }
  fi
  tmp="$(mktemp_file .bbr-conf)" || { [ -z "$backup" ] || rm -f "$backup"; return 1; }
  printf '%s\n' \
    'net.core.default_qdisc=fq' \
    'net.ipv4.tcp_congestion_control=bbr' >"$tmp"
  run mkdir -p "$(dirname "$BBR_SYSCTL_CONF")"
  if ! run install -o root -g root -m 0644 "$tmp" "$BBR_SYSCTL_CONF"; then
    rm -f "$tmp"
    [ -z "$backup" ] || rm -f "$backup"
    return 1
  fi
  rm -f "$tmp"

  if ! run sysctl -p "$BBR_SYSCTL_CONF" || ! bbr_fq_enabled; then
    restore_bbr_fq "$backup" "$old_qdisc" "$old_cc" "$had_conf"
    die "$(t '启用 TCP BBR + FQ 失败，已恢复原配置' \
      'Failed to enable TCP BBR + FQ; the previous configuration was restored')"
    return 1
  fi
  if [ -z "$owned_mode" ]; then
    new_ownership=1
    if [ "$had_conf" -eq 1 ]; then
      if ! install -d -o root -g root -m 0700 "$MITA_MANAGER_STATE_DIR" \
         || ! install -o root -g root -m 0600 "$backup" "$BBR_BACKUP_FILE" \
         || ! write_bbr_state replaced "$old_qdisc" "$old_cc"; then
        rm -f "$BBR_STATE_FILE" "$BBR_BACKUP_FILE"
        restore_bbr_fq "$backup" "$old_qdisc" "$old_cc" "$had_conf"
        return 1
      fi
    elif ! write_bbr_state created "$old_qdisc" "$old_cc"; then
      rm -f "$BBR_STATE_FILE" "$BBR_BACKUP_FILE"
      restore_bbr_fq "$backup" "$old_qdisc" "$old_cc" "$had_conf"
      return 1
    fi
  fi
  [ -z "$backup" ] || rm -f "$backup"
  [ "$new_ownership" -eq 0 ] || harden_mita_permissions 2>/dev/null || true
  report_bbr_fq_status
}

offer_bbr_fq() {
  if bbr_fq_enabled; then
    t '检测到 TCP BBR + FQ 默认策略已配置，跳过写入' \
      'TCP BBR + FQ defaults are already configured; skipping file changes'
    report_bbr_fq_status
    return 0
  fi
  if [ "$ENABLE_BBR" -eq 1 ]; then
    enable_bbr_fq
  elif confirm '未检测到完整的 TCP BBR + FQ，是否现在启用？[Y/n]: ' \
    'TCP BBR + FQ are not fully enabled. Enable them now? [Y/n]: ' y; then
    enable_bbr_fq
  else
    t '已跳过 TCP BBR + FQ 配置' 'Skipped TCP BBR + FQ configuration'
  fi
}

urlencode() {
  local value="$1"
  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$value"
    return 0
  fi
  if [[ "$value" =~ ^[a-zA-Z0-9._~-]+$ ]]; then
    printf '%s' "$value"
    return 0
  fi
  die "$(t '密码含特殊字符时需要 python3 以生成节点链接' \
    'python3 required to encode special characters in share link')"
}

url_host() {
  local host="$1"
  if [[ "$host" == *:* ]] && [[ "$host" != \[*\] ]]; then
    printf '[%s]' "$host"
  else
    printf '%s' "$host"
  fi
}

export_traffic_pattern_value() {
  local bin value="" iid
  if [ "${TRAFFIC_PATTERN_EXPORT_READY:-0}" -eq 1 ]; then
    printf '%s' "${TRAFFIC_PATTERN_EXPORT_CACHE:-}"
    return 0
  fi
  [ "$(normalize_traffic_pattern "${TRAFFIC_PATTERN:-conservative}")" != "off" ] || return 0
  mita_supports_traffic_pattern || return 0
  bin="$(mita_bin)"
  [ -x "$bin" ] || return 0
  if users_isolated_mode && [ -n "${USERNAME:-}" ]; then
    iid="$(users_get_field "$USERNAME" instance_id 2>/dev/null || true)"
    if instance_valid_id "$iid"; then
      value="$(instance_cmd "$iid" export traffic-pattern 2>/dev/null | tr -d '\r\n' || true)"
    fi
  else
    value="$("$bin" export traffic-pattern 2>/dev/null | tr -d '\r\n' || true)"
  fi
  case "$value" in
    ''|*[!A-Za-z0-9+/=]*) return 0 ;;
  esac
  printf '%s' "$value"
}

prepare_traffic_pattern_export() {
  TRAFFIC_PATTERN_EXPORT_READY=0
  TRAFFIC_PATTERN_EXPORT_CACHE="$(export_traffic_pattern_value)"
  TRAFFIC_PATTERN_EXPORT_READY=1
}

generate_share_link_for() {
  local ip="$1"
  local proto="$2"
  local enc_user enc_pass p host query tp enc_tp=""
  enc_user="$(urlencode "$USERNAME")"
  enc_pass="$(urlencode "$PASSWORD")"
  p="$(advertised_port_for_protocol "$proto")"
  # 官方 simple URL 始终要求 port/protocol 在 query 中成对出现。
  # profile=default 是上游客户端的 profileName，不是 OneClick UI 的参数预设 PROFILE。
  host="$(url_host "$ip")"
  tp="$(export_traffic_pattern_value)"
  [ -n "$tp" ] && enc_tp="&traffic-pattern=$(urlencode "$tp")"
  query="handshake-mode=${HANDSHAKE_MODE}&mtu=${MTU}&multiplexing=${MULTIPLEXING}&port=$(urlencode "$p")&profile=default&protocol=${proto}${enc_tp}"
  printf 'mierus://%s:%s@%s?%s' "$enc_user" "$enc_pass" "$host" "$query"
}

build_client_json_for() {
  local ip="$1"
  local proto="$2"
  local p binding tp tp_section="" user_json password_json ip_json domain_json
  p="$(advertised_port_for_protocol "$proto")"
  user_json="$(json_string "$USERNAME")"
  password_json="$(json_string "$PASSWORD")"
  if valid_ip_literal "$ip"; then
    ip_json="$(json_string "$ip")"
    domain_json='""'
  else
    ip_json='""'
    domain_json="$(json_string "$ip")"
  fi
  ensure_traffic_seed
  tp="$(traffic_pattern_json '      ')"
  [ -n "$tp" ] && tp_section=",
${tp}"
  if [ -n "$PORT" ]; then
    binding=$(cat <<EOB
            {
              "port": ${p},
              "protocol": "${proto}"
            }
EOB
)
  else
    binding=$(cat <<EOB
            {
              "portRange": "${p}",
              "protocol": "${proto}"
            }
EOB
)
  fi
  cat <<EOF
{
  "profiles": [
    {
      "profileName": "default",
      "user": {
        "name": ${user_json},
        "password": ${password_json}
      },
      "servers": [
        {
          "ipAddress": ${ip_json},
          "domainName": ${domain_json},
          "portBindings": [
${binding}
          ]
        }
      ],
      "mtu": ${MTU},
      "multiplexing": {
        "level": "${MULTIPLEXING}"
      },
      "handshakeMode": "${HANDSHAKE_MODE}"${tp_section}
    }
  ],
  "activeProfile": "default",
  "rpcPort": ${CLIENT_RPC_PORT},
  "socks5Port": ${CLIENT_SOCKS5_PORT},
  "loggingLevel": "INFO",
  "socks5ListenLAN": false,
  "httpProxyPort": ${CLIENT_HTTP_PORT},
  "httpProxyListenLAN": false
}
EOF
}

build_clash_yaml_entry() {
  local ip="$1"
  local proto="$2"
  local p port_lines name_suffix tp tp_line="" server_yaml user_yaml password_yaml
  p="$(advertised_port_for_protocol "$proto")"
  name_suffix="$(proto_lower "$proto")"
  server_yaml="$(json_string "$ip")"
  user_yaml="$(json_string "$USERNAME")"
  password_yaml="$(json_string "$PASSWORD")"
  tp="$(export_traffic_pattern_value)"
  [ -n "$tp" ] && tp_line="
    traffic-pattern: \"${tp}\""
  if [ -n "$PORT" ]; then
    port_lines="    port: ${p}"
  else
    port_lines="    port-range: ${p}"
  fi
  cat <<EOF
  - name: mieru-mita-${name_suffix}
    type: mieru
    server: ${server_yaml}
${port_lines}
    transport: ${proto}
    udp: true
    username: ${user_yaml}
    password: ${password_yaml}
    multiplexing: ${MULTIPLEXING}
    handshake-mode: ${HANDSHAKE_MODE}${tp_line}
EOF
}

build_clash_yaml() {
  local ip="$1"
  local proto
  while IFS= read -r proto; do
    build_clash_yaml_entry "$ip" "$proto"
  done < <(protocols_for_mode)
}

build_clash_yaml_header() {
  printf '%s\n' 'proxies:'
}

build_clash_yaml_full() {
  local ip="$1"
  build_clash_yaml_header
  build_clash_yaml "$ip"
}

protocol_output_count() {
  local n=0 proto
  while IFS= read -r proto; do
    [ -n "$proto" ] || continue
    n=$((n + 1))
  done < <(protocols_for_mode)
  printf '%s' "$n"
}

client_current_dir() {
  printf '%s/current' "${MITA_CLIENT_EXPORT_DIR%/}"
}

client_json_path_for() {
  local proto="$1" safe_user
  safe_user="$(safe_filename_component "${USERNAME:-user}")"
  [ -n "$safe_user" ] || safe_user=user
  printf '%s/%s_%s.json' "$(client_current_dir)" "$safe_user" "$(proto_lower "$proto")"
}

client_export_remove_user() {
  local name="$1" current_dir safe_user
  current_dir="$(client_current_dir)"
  safe_user="$(safe_filename_component "$name")"
  [ -n "$safe_user" ] || return 0
  run rm -f -- "${current_dir}/${safe_user}_tcp.json" "${current_dir}/${safe_user}_udp.json"
}

client_exports_clear_current() {
  local current_dir
  current_dir="$(client_current_dir)"
  [ -d "$current_dir" ] || return 0
  run rm -f -- "${current_dir}/"*.json
}

client_exports_after_reconfigure() {
  local old_user="$1" old_protocol="$2" old_mtu="$3" old_traffic="$4"
  local old_seed="$5" old_low_entropy="$6" old_mux="$7" old_handshake="$8"
  if [ "${PROTOCOL:-TCP}" != "$old_protocol" ] \
     || [ "${MTU:-1400}" != "$old_mtu" ] \
     || [ "${TRAFFIC_PATTERN:-off}" != "$old_traffic" ] \
     || [ "${TRAFFIC_SEED:-}" != "$old_seed" ] \
     || [ "${LOW_ENTROPY_MODE:-LOW_ENTROPY_MODE_OFF}" != "$old_low_entropy" ] \
     || [ "${MULTIPLEXING:-MULTIPLEXING_OFF}" != "$old_mux" ] \
     || [ "${HANDSHAKE_MODE:-HANDSHAKE_NO_WAIT}" != "$old_handshake" ]; then
    client_exports_clear_current
  elif [ "${USERNAME:-}" != "$old_user" ]; then
    client_export_remove_user "$old_user"
  fi
}

print_json_import_hint() {
  if [ "${PROTOCOL:-TCP}" = "BOTH" ]; then
    t '  先将上方 TCP 或 UDP JSON 下载到客户端，再执行:' \
      '  Download the TCP or UDP JSON shown above to the client, then run:'
  else
    t '  先将上方 JSON 下载到客户端，再执行:' \
      '  Download the JSON shown above to the client, then run:'
  fi
  t '    mieru apply config <客户端本地 JSON 路径>' \
    '    mieru apply config <local-client-JSON-path>'
}

print_protocol_outputs() {
  local ip="$1"
  local proto link cfg_path cfg_tmp multi=0 count current_dir safe_user
  prepare_traffic_pattern_export
  count="$(protocol_output_count)"
  if [ "$count" -gt 1 ]; then
    multi=1
  fi
  current_dir="$(client_current_dir)"
  safe_user="$(safe_filename_component "${USERNAME:-user}")"
  [ -n "$safe_user" ] || safe_user=user
  if [ "$DRY_RUN" -ne 1 ]; then
    install -d -o root -g root -m 0700 "$current_dir"
  fi
  while IFS= read -r proto; do
    [ -n "$proto" ] || continue
    msg ""
    if [ "$multi" -eq 1 ]; then
      t "【${proto} 节点链接】" "[${proto} share link]"
    else
      t '【节点链接】' '[Share link]'
    fi
    link="$(generate_share_link_for "$ip" "$proto")"
    msg "$link"
    cfg_path="$(client_json_path_for "$proto")"
    msg ""
    if [ "$multi" -eq 1 ]; then
      t "【${proto} 客户端 JSON】（供 mieru 客户端使用，勿在服务器 mita apply）" \
        "[${proto} client JSON] (for mieru client only — do NOT mita apply on server)"
    else
      t '【客户端 JSON 配置】（供 mieru 客户端使用，勿在服务器 mita apply）' \
        '[Client JSON] (for mieru client only — do NOT mita apply on server)'
    fi
    if [ "$DRY_RUN" -ne 1 ]; then
      cfg_tmp="$(mktemp "${cfg_path}.XXXXXX")" || return 1
      if ! build_client_json_for "$ip" "$proto" >"$cfg_tmp" \
         || ! chmod 0600 "$cfg_tmp" \
         || ! mv -f "$cfg_tmp" "$cfg_path"; then
        rm -f "$cfg_tmp"
        return 1
      fi
      t "  已保存: ${cfg_path}" "  Saved:  ${cfg_path}"
    else
      t "  将保存: ${cfg_path}" "  Will save: ${cfg_path}"
    fi
  done < <(protocols_for_mode)
  if [ "$DRY_RUN" -ne 1 ]; then
    # v2.1.0 及更早版本的时间戳文件会造成通配符歧义和旧凭据回退，
    # 成功写入稳定文件后清理这些由脚本生成的旧导出。
    rm -f /root/mieru_client_*.json 2>/dev/null || true
    case "${PROTOCOL:-TCP}" in
      TCP) rm -f "${current_dir}/${safe_user}_udp.json" 2>/dev/null || true ;;
      UDP) rm -f "${current_dir}/${safe_user}_tcp.json" 2>/dev/null || true ;;
    esac
  fi
}

print_client_endpoint_mapping() {
  [ -n "${ADVERTISE_HOST:-}" ] || return 0
  local backend_ip="${1:-}" entry_host backend_host
  [ -n "$backend_ip" ] || backend_ip="$(public_ip 2>/dev/null || true)"
  client_endpoint_is_independent "$backend_ip" || return 0
  entry_host="$(url_host "$ADVERTISE_HOST")"
  if [ -n "$backend_ip" ]; then
    backend_host="$(url_host "$backend_ip")"
  else
    backend_host="$(t '<本机可达 IP>' '<server reachable IP>')"
  fi
  msg ""
  t '【客户端入口映射】（仅提示，不修改服务器配置）' \
    '[Client endpoint mapping] (display only; server config is unchanged)'
  if [ "${PROTOCOL:-TCP}" = "BOTH" ]; then
    t "  客户端: TCP ${entry_host}:$(advertised_port_for_protocol TCP) / UDP ${entry_host}:$(advertised_port_for_protocol UDP)" \
      "  Client: TCP ${entry_host}:$(advertised_port_for_protocol TCP) / UDP ${entry_host}:$(advertised_port_for_protocol UDP)"
    t "       -> 后端: TCP ${backend_host}:${PORT} / UDP ${backend_host}:$((PORT + 1))" \
      "       -> Backend: TCP ${backend_host}:${PORT} / UDP ${backend_host}:$((PORT + 1))"
  else
    t "  客户端: ${entry_host}:$(advertised_port_for_protocol "$PROTOCOL")/${PROTOCOL}" \
      "  Client: ${entry_host}:$(advertised_port_for_protocol "$PROTOCOL")/${PROTOCOL}"
    t "       -> 后端: ${backend_host}:${PORT}/${PROTOCOL}" \
      "       -> Backend: ${backend_host}:${PORT}/${PROTOCOL}"
  fi
}

print_summary() {
  local context="${1:-install}" ip
  ip="$(advertised_host || true)"
  msg ""
  case "$context" in
    install) t '========== 安装完成 ==========' '========== Installation complete ==========' ;;
    *) t '========== 当前节点配置 ==========' '========== Current node configuration ==========' ;;
  esac
  if [ -n "$ip" ]; then
    print_protocol_outputs "$ip"
  else
    warn "$(t '未能获取公网 IP，请手动将下方连接信息填入客户端' \
      'Could not detect public IP; use connection info below manually')"
  fi
  msg ""
  t '【连接信息】' '[Connection info]'
  if [ -n "${ADVERTISE_HOST:-}" ]; then
    t "  客户端入口: ${ip:-<未知>}" "  Client entry: ${ip:-<unknown>}"
  else
    t "  服务器: ${ip:-<未知>}" "  Server:   ${ip:-<unknown>}"
  fi
  t "  用户名: ${USERNAME}" "  Username: ${USERNAME}"
  t "  密码:   ${PASSWORD}" "  Password: ${PASSWORD}"
  t "  协议:   $(client_protocol_label)" "  Protocol: $(client_protocol_label)"
  t "  Profile: $(profile_label)" "  Profile:  $(profile_label)"
  t "  MTU:    ${MTU}（$(mtu_policy_label)）" \
    "  MTU:      ${MTU} ($(mtu_policy_label))"
  t "  流量伪装: $(traffic_label)" "  Obfuscation: $(traffic_label)"
  t "  低熵模式: $(low_entropy_label)" "  Low entropy: $(low_entropy_label)"
  t "  多路复用: ${MULTIPLEXING}" "  Multiplexing: ${MULTIPLEXING}"
  t "  握手模式: ${HANDSHAKE_MODE}" "  Handshake: ${HANDSHAKE_MODE}"
  if [ -n "$PORT" ]; then
    if [ "$PROTOCOL" = "BOTH" ]; then
      t "  端口:   TCP $(advertised_port_for_protocol TCP) / UDP $(advertised_port_for_protocol UDP)" \
        "  Ports:    TCP $(advertised_port_for_protocol TCP) / UDP $(advertised_port_for_protocol UDP)"
    else
      t "  端口:   $(advertised_port_for_protocol "$PROTOCOL")" \
        "  Port:     $(advertised_port_for_protocol "$PROTOCOL")"
    fi
  else
    t "  端口段: ${PORT_RANGE}" "  Port range: ${PORT_RANGE}"
  fi
  print_client_endpoint_mapping
  msg ""
  t '导入方式:' 'Import options:'
  if [ "$PROTOCOL" = "BOTH" ]; then
    msg '  mieru import config "<TCP 节点链接>"   # 或分别导入 TCP / UDP 链接'
  else
    msg '  mieru import config "<节点链接>"   # 简单链接不含 socks5Port，全新设备建议用 JSON'
  fi
  print_json_import_hint
  if [ "$PROTOCOL" = "BOTH" ]; then
    msg ''
    t '【客户端提示】双协议已分开输出：TCP 与 UDP 各用对应链接/JSON；' \
      '[Client tip] Dual protocol outputs are split: use matching TCP or UDP link/JSON.'
    t '  v2rayN 导入后传输协议选 tcp 或 udp（勿选「两个都」）。' \
      '  In v2rayN pick transport tcp or udp (not "both").'
  fi
  if [ -n "$ip" ]; then
    msg ""
    t '【Clash / mihomo 配置片段】' '[Clash / mihomo snippet]'
    build_clash_yaml_full "$ip"
  fi
  cloud_firewall_hint
}

generate_client_config() {
  local ip
  ip="$(advertised_host || echo 'YOUR_SERVER_IP')"
  msg ""
  t '========== 节点链接与客户端配置 ==========' \
    '========== Share links & client config =========='
  t "当前 MTU: ${MTU}（$(mtu_policy_label)）" \
    "Current MTU: ${MTU} ($(mtu_policy_label))"
  t 'MTU 已同步写入 mierus:// 节点链接和 mieru 客户端 JSON；mihomo 当前节点字段不单独配置 MTU。' \
    'MTU is included in the mierus:// link and mieru client JSON; current mihomo proxy fields do not expose a separate MTU option.'
  print_protocol_outputs "$ip"
  print_client_endpoint_mapping
  msg ""
  t '【导入方式】' '[How to import]'
  if [ "$PROTOCOL" = "BOTH" ]; then
    msg '  mieru import config "<TCP 节点链接>"   # TCP / UDP 各用对应链接'
  else
    msg '  mieru import config "<节点链接>"   # 一键导入（简单链接）'
  fi
  print_json_import_hint
  msg ""
  t '说明: 上方 mierus:// 为分享链接；JSON 为 mieru 客户端配置（在电脑/手机导入，勿在服务器 mita apply）' \
    'Note: mierus:// is the share link; JSON is for the mieru client on your device — do NOT mita apply on server'
  msg ""
  t '【Clash / mihomo 配置片段】' '[Clash / mihomo snippet]'
  build_clash_yaml_full "$ip"
  cloud_firewall_hint
}

install_fresh_rollback() {
  local snapshot="$1" bindings="${2:-}"
  if [ -n "$bindings" ]; then
    close_firewall_for_bindings "$bindings" 2>/dev/null || true
  fi
  isolated_stop_all 2>/dev/null || true
  tc_clear_owned_filters 2>/dev/null || true
  remove_users_scheduler 2>/dev/null || true
  users_tx_rollback "$snapshot" 0 || true
}

install_fresh_isolated() {
  local tx bindings
  install_self_script
  admin_lock_acquire || return 1
  tx="$(users_tx_snapshot)" || { admin_lock_release; return 1; }
  if ! users_migrate_from_primary; then
    install_fresh_rollback "$tx"
    admin_lock_release
    die "$(t '创建初始用户状态失败' 'Failed to create the initial user state')" || return 1
  fi
  if ! apply_users_config "$tx" 0; then
    install_fresh_rollback "$tx"
    admin_lock_release
    die "$(t '启动首个用户专属实例失败；未启用旧默认服务' \
      'Failed to start the first dedicated user instance; the legacy default service was not enabled')" || return 1
  fi
  bindings="$(multi_user_port_protocol_pairs)"
  if ! open_firewall_for_pairs "$bindings"; then
    install_fresh_rollback "$tx" "$bindings"
    admin_lock_release
    die "$(t '放行专属实例端口失败，安装状态已回滚' \
      'Failed to allow dedicated-instance ports; installation state was rolled back')" || return 1
  fi
  if ! verify_mita_running || ! save_install_state; then
    install_fresh_rollback "$tx" "$bindings"
    admin_lock_release
    die "$(t '专属实例验收或状态保存失败，安装状态已回滚' \
      'Dedicated-instance verification or state persistence failed; installation state was rolled back')" || return 1
  fi
  users_tx_commit "$tx"
  client_exports_clear_current 2>/dev/null || true
  admin_lock_release
}

mita_preservable_config_exists() {
  [ -s "$MITA_STATE" ] && return 0
  users_state_exists && [ "$(users_count)" -gt 0 ]
}

# ---------- Snell client exports (Surge / Mihomo / sing-box) ----------

snell_client_values() {
  local id="$1" name major psk endpoint host port
  name="$(snell_state_field "$id" name)"
  major="$(snell_state_field "$id" version)"
  case "$major" in 4|5) ;; *) return 1 ;; esac
  psk="$(snell_state_field "$id" psk)"
  endpoint="$(snell_effective_endpoint "$id")"
  host="${endpoint%%|*}"; port="${endpoint#*|}"
  printf '%s\t%s\t%s\t%s\t%s\n' "$name" "$major" "$psk" "$host" "$port"
}

snell_export_surge() {
  local id="$1" name major psk host port values
  values="$(snell_client_values "$id")" || return 1
  IFS=$'\t' read -r name major psk host port <<<"$values"
  printf '%s = snell, %s, %s, psk = %s, version = %s' "$name" "$host" "$port" "$psk" "$major"
  printf '\n'
}

snell_export_mihomo() {
  local id="$1" name major psk host port values
  values="$(snell_client_values "$id")" || return 1
  IFS=$'\t' read -r name major psk host port <<<"$values"
  case "$major" in
    4|5) ;;
    *) return 1 ;;
  esac
  jq -n --arg name "$name" --arg server "$host" --arg port "$port" --arg psk "$psk" --arg version "$major" -r '
    "- name: " + ($name|tojson) + "\n" +
    "  type: snell\n" +
    "  server: " + ($server|tojson) + "\n" +
    "  port: " + $port + "\n" +
    "  psk: " + ($psk|tojson) + "\n" +
    "  version: " + $version + "\n" +
    "  udp: true"
  '
}

snell_export_singbox() {
  local id="$1" name major psk host port singbox_version values
  values="$(snell_client_values "$id")" || return 1
  IFS=$'\t' read -r name major psk host port <<<"$values"
  case "$major" in
    4) singbox_version=4 ;;
    # 官方 v5 未启用 QUIC Proxy Mode 时与 v4 client wire protocol 兼容；
    # sing-box >=1.14 当前 outbound 用 version=4 表达该兼容语义。
    5) singbox_version=4 ;;
    *) return 1 ;;
  esac
  jq -n --arg tag "$name" --arg server "$host" --arg port "$port" --arg psk "$psk" \
    --arg version "$singbox_version" --arg major "$major" '
      {
        type:"snell",
        tag:$tag,
        server:$server,
        server_port:($port|tonumber),
        version:($version|tonumber),
        psk:$psk
      }
    '
}

snell_print_client_exports() {
  local id="$1" major
  major="$(snell_state_field "$id" version)"
  msg '========================================'
  msg 'Surge'
  msg '========================================'
  snell_export_surge "$id"
  msg ''
  msg '========================================'
  msg 'Mihomo'
  msg '========================================'
  snell_export_mihomo "$id"
  if [ "$major" = 5 ]; then
    msg '说明：udp: true 是 Mihomo 普通 Snell UDP relay 能力；官方 v5 QUIC Proxy Mode 为 NOT VERIFIED。'
  fi
  msg ''
  msg '========================================'
  msg 'sing-box'
  msg '========================================'
  snell_export_singbox "$id"
  if [ "$major" = 5 ]; then
    msg '说明：sing-box version=4 对应 Snell v5 未启用 QUIC Proxy Mode 时的上游兼容语义。'
    msg '说明：sing-box 不支持官方 Snell v5 QUIC Proxy Mode（CLIENT_UNSUPPORTED）。'
  fi
}

do_install() {
  require_root
  require_linux
  require_cmd curl
  ensure_manager_state_layout 1

  local pm arch ver url tmp tx reinstall_existing=0 managed_existing=0
  pm="$(detect_pkg_manager)"
  arch="$(detect_arch)"
  ensure_management_dependencies "$pm"

  if mita_installed; then
    local cur
    cur="$(installed_version || true)"
    t "检测到已安装 mita ${cur:-未知版本}" "mita already installed (${cur:-unknown})"
    if mita_preservable_config_exists; then
      t '如需改端口/密码/协议，请选菜单「重新配置」或执行: install-mita reconfigure' \
        'To change port/password/protocol, use menu Reconfigure or: install-mita reconfigure'
      if ! confirm '继续重新下载安装包并保留当前用户/节点配置？[y/N]: ' \
        'Re-download the package and keep the current users/node config? [y/N]: ' n; then
        [ "${MENU_MODE:-0}" -eq 1 ] && return 0
        exit 0
      fi
      if [ "$USERNAME_CLI" -eq 1 ] || [ "$PASSWORD_CLI" -eq 1 ] \
         || [ "$PORT_CLI" -eq 1 ] || [ "$PORT_RANGE_CLI" -eq 1 ] \
         || [ "$PROTOCOL_CLI" -eq 1 ] || [ "$MTU_CLI" -eq 1 ] \
         || [ "$ADVERTISE_CLI" -eq 1 ] \
         || [ "$PROFILE_CLI" -eq 1 ] \
         || [ "$MULTIPLEXING_CLI" -eq 1 ] || [ "$HANDSHAKE_CLI" -eq 1 ] \
         || [ "$TRAFFIC_CLI" -eq 1 ] || [ "$LOW_ENTROPY_CLI" -eq 1 ]; then
        die "$(t '重装只保留当前配置；如需同时改节点参数，请使用 reconfigure' \
          'Reinstall preserves current config; use reconfigure to change node parameters')"
      fi
      reinstall_existing=1
      load_install_state
      if users_state_exists && [ "$(users_count)" -gt 0 ]; then
        managed_existing=1
        users_sync_primary_globals
      fi
    else
      warn "$(t '检测到上次安装未完成，且没有可恢复的 OneClick 状态；本次将重新生成配置并完成安装' \
        'Previous install is incomplete and has no recoverable OneClick state; configuration will be regenerated')"
      if ! confirm '继续修复并完成安装？[y/N]: ' \
        'Repair and complete the installation? [y/N]: ' n; then
        [ "${MENU_MODE:-0}" -eq 1 ] && return 0
        exit 0
      fi
    fi
  fi

  if [ "$reinstall_existing" -eq 1 ]; then
    ensure_config_noninteractive
  elif [ "$YES" -eq 1 ]; then
    [ "${ADVERTISE_CLI:-0}" -eq 1 ] || die "$(t \
      '非交互安装必须显式提供 --advertise-host/--advertise-port，或用 --advertise-auto 确认自动入口。' \
      'Non-interactive install requires --advertise-host/--advertise-port, or --advertise-auto to explicitly confirm automatic endpoint selection.')"
    ensure_config_noninteractive
  else
    collect_config_interactive
  fi
  [ -z "$PORT_RANGE" ] || die "$(t 'v2 用户专属实例不支持端口段，请改用单端口' \
    'v2 dedicated user instances do not support port ranges; use one port')"
  [ -z "$PORT" ] || PORT="$(normalize_uint "$PORT")"
  if [ "$reinstall_existing" -eq 0 ]; then
    ensure_install_port_available
  fi

  ver="$(target_mieru_version)"
  url="$(package_url "$ver" "$pm" "$arch")"
  tmp="$(mktemp_file)"
  download_package "$url" "$tmp"
  install_package "$tmp" "$pm"
  rm -f "$tmp"
  MIERU_VERSION="$ver"

  add_op_user "$OP_USER"
  warn_traffic_unsupported
  warn_low_entropy_unsupported
  if [ "$managed_existing" -eq 1 ]; then
    install_self_script
    admin_lock_acquire || return 1
    tx="$(users_tx_snapshot)" || { admin_lock_release; return 1; }
    isolated_stop_all
    if ! apply_users_config "$tx"; then
      admin_lock_release
      die "$(t '重装后二次应用专属实例失败；用户状态已回滚' \
        'Failed to reapply dedicated instances after reinstall; user state was rolled back')"
    fi
    if ! verify_mita_running; then
      users_tx_rollback "$tx" 1
      admin_lock_release
      die "$(t '重装后二次启动专属实例失败；用户状态已回滚' \
        'Dedicated instances failed after reinstall; user state was rolled back')"
    fi
    users_sync_primary_globals
    if ! save_install_state; then
      users_tx_rollback "$tx" 1
      admin_lock_release
      die "$(t '重装后保存安装状态失败；用户状态已回滚' \
        'Failed to save install state after reinstall; user state was rolled back')"
    fi
    users_tx_commit "$tx"
    admin_lock_release
  else
    if [ "$reinstall_existing" -eq 0 ]; then
      # 下载/安装期间端口可能被其它进程抢占，落盘前再验一次。
      ensure_install_port_available
    fi
    install_fresh_isolated
  fi

  offer_bbr_fq

  print_summary
}

do_reconfigure() {
  require_root
  require_linux
  mita_installed || die "$(t 'mita 未安装，请先执行安装' 'mita is not installed; run install first')"

  local old_bindings new_bindings close_bindings desired_bindings binding_proto binding_port desc bin tx
  local old_port old_port_range old_protocol old_mtu old_mtu_policy old_user old_password
  local old_profile old_traffic old_seed old_low_entropy old_mux old_handshake
  local old_advertise_host old_advertise_port
  local client_state_changed=0
  local requested_port="$PORT" requested_port_range="$PORT_RANGE" requested_protocol="$PROTOCOL"
  local requested_user="$USERNAME" requested_password="$PASSWORD"
  local requested_advertise_host="$ADVERTISE_HOST" requested_advertise_port="$ADVERTISE_PORT"
  local requested_profile="$PROFILE" requested_mtu_request="$MTU_REQUEST"
  local requested_traffic="$TRAFFIC_PATTERN" requested_low_entropy="$LOW_ENTROPY_MODE"
  local requested_mux="$MULTIPLEXING" requested_handshake="$HANDSHAKE_MODE"
  local requested_port_cli="${PORT_CLI:-0}" requested_port_range_cli="${PORT_RANGE_CLI:-0}"
  local requested_protocol_cli="${PROTOCOL_CLI:-0}" requested_user_cli="${USERNAME_CLI:-0}"
  local requested_password_cli="${PASSWORD_CLI:-0}" requested_advertise_cli="${ADVERTISE_CLI:-0}"
  local requested_profile_cli="${PROFILE_CLI:-0}" requested_mtu_cli="${MTU_CLI:-0}"
  local requested_traffic_cli="${TRAFFIC_CLI:-0}" requested_low_entropy_cli="${LOW_ENTROPY_CLI:-0}"
  local requested_mux_cli="${MULTIPLEXING_CLI:-0}" requested_handshake_cli="${HANDSHAKE_CLI:-0}"
  PORT_CLI=0 PORT_RANGE_CLI=0 PROTOCOL_CLI=0 USERNAME_CLI=0 PASSWORD_CLI=0
  ADVERTISE_CLI=0 PROFILE_CLI=0 MTU_CLI=0 TRAFFIC_CLI=0 LOW_ENTROPY_CLI=0
  MULTIPLEXING_CLI=0 HANDSHAKE_CLI=0
  load_install_state
  if users_state_exists && [ "$(users_count)" -gt 0 ]; then
    users_sync_primary_globals
  fi
  old_port="$PORT"; old_port_range="$PORT_RANGE"; old_protocol="$PROTOCOL"
  old_mtu="$MTU"; old_mtu_policy="$MTU_POLICY"
  old_user="$USERNAME"; old_password="$PASSWORD"
  old_advertise_host="$ADVERTISE_HOST"; old_advertise_port="$ADVERTISE_PORT"
  old_profile="$PROFILE"
  old_traffic="$TRAFFIC_PATTERN"; old_seed="$TRAFFIC_SEED"
  old_low_entropy="$LOW_ENTROPY_MODE"; old_mux="$MULTIPLEXING"; old_handshake="$HANDSHAKE_MODE"
  PORT_CLI="$requested_port_cli"; PORT_RANGE_CLI="$requested_port_range_cli"
  PROTOCOL_CLI="$requested_protocol_cli"; USERNAME_CLI="$requested_user_cli"
  PASSWORD_CLI="$requested_password_cli"; ADVERTISE_CLI="$requested_advertise_cli"
  PROFILE_CLI="$requested_profile_cli"; MTU_CLI="$requested_mtu_cli"
  TRAFFIC_CLI="$requested_traffic_cli"; LOW_ENTROPY_CLI="$requested_low_entropy_cli"
  MULTIPLEXING_CLI="$requested_mux_cli"; HANDSHAKE_CLI="$requested_handshake_cli"
  [ "$PORT_CLI" -eq 0 ] || PORT="$requested_port"
  [ "$PORT_RANGE_CLI" -eq 0 ] || PORT_RANGE="$requested_port_range"
  [ "$PROTOCOL_CLI" -eq 0 ] || PROTOCOL="$requested_protocol"
  [ "$USERNAME_CLI" -eq 0 ] || USERNAME="$requested_user"
  [ "$PASSWORD_CLI" -eq 0 ] || PASSWORD="$requested_password"
  [ "$ADVERTISE_CLI" -eq 0 ] || { ADVERTISE_HOST="$requested_advertise_host"; ADVERTISE_PORT="$requested_advertise_port"; }
  [ "$PROFILE_CLI" -eq 0 ] || PROFILE="$requested_profile"
  [ "$MTU_CLI" -eq 0 ] || MTU_REQUEST="$requested_mtu_request"
  [ "$TRAFFIC_CLI" -eq 0 ] || TRAFFIC_PATTERN="$requested_traffic"
  [ "$LOW_ENTROPY_CLI" -eq 0 ] || LOW_ENTROPY_MODE="$requested_low_entropy"
  [ "$MULTIPLEXING_CLI" -eq 0 ] || MULTIPLEXING="$requested_mux"
  [ "$HANDSHAKE_CLI" -eq 0 ] || HANDSHAKE_MODE="$requested_handshake"
  bin="$(mita_bin)"
  if users_state_exists && [ "$(users_count)" -gt 0 ]; then
    old_bindings="$(multi_user_port_protocol_pairs)"
  else
    desc="$("$bin" describe config 2>/dev/null || true)"
    old_bindings="$(extract_bindings_from_describe "$desc")"
  fi

  if [ "$YES" -eq 1 ]; then
    load_config_from_mita
    ensure_config_noninteractive
  else
    collect_reconfigure_interactive
  fi
  [ -z "$PORT_RANGE" ] || die "$(t 'v2 用户专属实例不支持端口段，请改用单端口' \
    'v2 dedicated user instances do not support port ranges; use one port')"
  [ -z "$PORT" ] || PORT="$(normalize_uint "$PORT")"
  validate_advertise_endpoint || die "$(t '自定义客户端入口参数无效' \
    'Invalid custom client entry parameters')"
  [ -z "$ADVERTISE_PORT" ] || ADVERTISE_PORT="$(normalize_uint "$ADVERTISE_PORT")"

  if [ "${PROFILE_CLI:-0}" -eq 0 ] \
     && { [ "$PROTOCOL" != "$old_protocol" ] || [ "$MTU" != "$old_mtu" ] \
       || [ "$MULTIPLEXING" != "$old_mux" ] || [ "$HANDSHAKE_MODE" != "$old_handshake" ] \
       || [ "$TRAFFIC_PATTERN" != "$old_traffic" ] || [ "$LOW_ENTROPY_MODE" != "$old_low_entropy" ]; }; then
    PROFILE=custom
  fi
  profile_reconcile_metadata

  if [ "$ADVERTISE_HOST" != "$old_advertise_host" ] \
     || [ "$ADVERTISE_PORT" != "$old_advertise_port" ] \
     || [ "$MTU_POLICY" != "$old_mtu_policy" ] \
     || [ "$MULTIPLEXING" != "$old_mux" ] \
     || [ "$HANDSHAKE_MODE" != "$old_handshake" ] \
     || [ "$PROFILE" != "$old_profile" ]; then
    client_state_changed=1
  fi

  # 展示入口、客户端握手/多路复用和 MTU 策略文本不改变服务端运行配置。
  # 这些字段单独持久化，避免无意义地重启所有专属实例。
  if [ "$PORT" = "$old_port" ] && [ "$PORT_RANGE" = "$old_port_range" ] \
     && [ "$PROTOCOL" = "$old_protocol" ] && [ "$MTU" = "$old_mtu" ] \
     && [ "$USERNAME" = "$old_user" ] && [ "$PASSWORD" = "$old_password" ] \
     && [ "$TRAFFIC_PATTERN" = "$old_traffic" ] && [ "$TRAFFIC_SEED" = "$old_seed" ] \
     && [ "$LOW_ENTROPY_MODE" = "$old_low_entropy" ]; then
    if [ "$client_state_changed" -eq 0 ]; then
      msg ""
      t '未检测到配置变化；服务未重启' \
        'No configuration changes detected; services were not restarted'
      print_summary current
      return 0
    fi
    if users_state_exists && [ "$(users_count)" -gt 0 ]; then
      local state_only_auto_host=""
      admin_lock_acquire || return 1
      tx="$(users_tx_snapshot)" || { admin_lock_release; return 1; }
      if [ "$ADVERTISE_HOST" != "$old_advertise_host" ] \
         || [ "$ADVERTISE_PORT" != "$old_advertise_port" ]; then
        if ! users_set_advertise_endpoint "$old_user" "$ADVERTISE_HOST" "$ADVERTISE_PORT"; then
          users_tx_rollback "$tx" 0
          admin_lock_release
          return 1
        fi
      fi
      state_only_auto_host="$(public_ip 2>/dev/null || true)"
      if ! users_validate_state_file "$MITA_USERS_STATE" "$PROTOCOL" "$state_only_auto_host"; then
        users_tx_rollback "$tx" 0
        admin_lock_release
        die "$(t '客户端展示入口与其它用户冲突' \
          'Client display endpoint conflicts with another user')"
      fi
      users_sync_primary_globals
      if ! save_install_state; then
        users_tx_rollback "$tx" 0
        admin_lock_release
        return 1
      fi
      users_tx_commit "$tx"
      admin_lock_release
    else
      save_install_state
    fi
    client_exports_after_reconfigure "$old_user" "$old_protocol" "$old_mtu" \
      "$old_traffic" "$old_seed" "$old_low_entropy" "$old_mux" "$old_handshake" \
      2>/dev/null || true
    msg ""
    t '仅客户端参数已更新；服务器运行配置未变化，服务未重启' \
      'Client-only settings were updated; server runtime is unchanged and services were not restarted'
    print_summary current
    return 0
  fi

  if [ -n "${PORT:-}" ]; then
    if users_state_exists && [ "$(users_count)" -gt 0 ]; then
      desired_bindings="$({
        multi_user_port_protocol_pairs
        port_required_bindings "$PORT"
      } | sed '/^[[:space:]]*$/d' | LC_ALL=C sort -u)"
    else
      desired_bindings="$(port_required_bindings "$PORT")"
    fi
    while IFS='|' read -r binding_proto binding_port; do
      [ -n "$binding_proto" ] && [ -n "$binding_port" ] || continue
      printf '%s\n' "$old_bindings" | grep -qxF "${binding_proto}|${binding_port}" && continue
      if port_is_listening "$binding_port" "$binding_proto"; then
        warn "$(t "新监听 ${binding_proto}/${binding_port} 已被系统其它服务占用" \
          "New listener ${binding_proto}/${binding_port} is already used by another service")"
        port_listener_details "$binding_port" "$binding_proto"
        die "$(t '重新配置已取消，请选择其它端口或协议' \
          'Reconfigure cancelled; choose another port or protocol')"
      fi
    done <<<"$desired_bindings"
  fi

  warn_traffic_unsupported
  warn_low_entropy_unsupported
  # 多用户：协议全局更新；仅当用户显式改了主用户名/密码/端口时同步「主用户」
  # 主用户 = install-state 中的 USERNAME，找不到则 users[0]
  if users_state_exists && [ "$(users_count)" -gt 0 ]; then
    MULTI_USER_MODE=1
    admin_lock_acquire || return 1
    tx="$(users_tx_snapshot)" || { admin_lock_release; return 1; }
    _U_NAME="$USERNAME" _U_PASS="$PASSWORD" _U_PORT="$PORT" _U_PROTO="$PROTOCOL"
    _U_ADVERTISE_HOST="$ADVERTISE_HOST" _U_ADVERTISE_PORT="$ADVERTISE_PORT"
    _U_PRIMARY="${old_user}"
    users_py_locked '
import json, os, time
path = os.environ["MITA_USERS_STATE"]
d = json.load(open(path))
name = os.environ.get("_U_NAME") or ""
password = os.environ.get("_U_PASS") or ""
port = os.environ.get("_U_PORT") or ""
proto = os.environ.get("_U_PROTO") or "TCP"
advertise_host = os.environ.get("_U_ADVERTISE_HOST") or ""
advertise_port = os.environ.get("_U_ADVERTISE_PORT") or ""
primary = os.environ.get("_U_PRIMARY") or ""
users = d.get("users") or []
# 定位主用户：优先同名，否则第一个
idx = 0
for i, u in enumerate(users):
    if primary and u.get("name") == primary:
        idx = i
        break
if users:
    u = users[idx]
    old_port = int(u.get("port") or 0)
    if name and name != u.get("name"):
        # 避免与其它用户重名
        if any(x.get("name") == name for j, x in enumerate(users) if j != idx):
            raise SystemExit(2)
        u["name"] = name
    if password and not password.startswith("*"):
        u["password"] = password
    if port and str(port).isdigit():
        new_port = int(port)
        # 端口冲突则拒绝改端口（保留其它用户端口）
        if any(int(x.get("port") or 0) == new_port for j, x in enumerate(users) if j != idx):
            raise SystemExit(3)
        u["port"] = new_port
    u["advertise_host"] = advertise_host
    u["advertise_port"] = int(advertise_port) if advertise_port else ""
    u["updated_at"] = int(time.time())
d["protocol"] = proto
json.dump(d, open(path, "w"), indent=2)
' || {
      local prc=$?
      users_tx_rollback "$tx" 0
      admin_lock_release
      if [ "$prc" -eq 2 ]; then
        die "$(t '新用户名与其它用户冲突' 'New username conflicts with another user')"
      elif [ "$prc" -eq 3 ]; then
        die "$(t '新端口已被其它用户占用' 'New port already used by another user')"
      fi
      die "$(t '更新多用户状态失败' 'Failed to update multi-user state')"
    }
    if ! users_validate_state_file "$MITA_USERS_STATE" "$PROTOCOL"; then
      users_tx_rollback "$tx" 0
      admin_lock_release
      die "$(t '新协议/端口组合会造成监听端口或客户端展示入口冲突' \
        'The new protocol/port combination would collide between listeners or client display endpoints')"
    fi
    # 协议变更时所有用户 portBindings 随 PROTOCOL 重建；端口仅主用户可能变
    if ! apply_users_config "$tx"; then
      PORT="$old_port"; PORT_RANGE="$old_port_range"; PROTOCOL="$old_protocol"
      MTU="$old_mtu"; MTU_POLICY="$old_mtu_policy"; PROFILE="$old_profile"
      USERNAME="$old_user"; PASSWORD="$old_password"
      ADVERTISE_HOST="$old_advertise_host"; ADVERTISE_PORT="$old_advertise_port"
      TRAFFIC_PATTERN="$old_traffic"; TRAFFIC_SEED="$old_seed"
      LOW_ENTROPY_MODE="$old_low_entropy"; MULTIPLEXING="$old_mux"; HANDSHAKE_MODE="$old_handshake"
      if users_isolated_mode; then
        reconcile_isolated_instances >/dev/null 2>&1 || true
      fi
      admin_lock_release
      return 1
    fi
    new_bindings="$(multi_user_port_protocol_pairs)"
    open_firewall_for_pairs "$new_bindings"
    if ! verify_mita_running || ! save_install_state; then
      PORT="$old_port"; PORT_RANGE="$old_port_range"; PROTOCOL="$old_protocol"
      MTU="$old_mtu"; MTU_POLICY="$old_mtu_policy"; PROFILE="$old_profile"
      USERNAME="$old_user"; PASSWORD="$old_password"
      ADVERTISE_HOST="$old_advertise_host"; ADVERTISE_PORT="$old_advertise_port"
      TRAFFIC_PATTERN="$old_traffic"; TRAFFIC_SEED="$old_seed"
      LOW_ENTROPY_MODE="$old_low_entropy"; MULTIPLEXING="$old_mux"; HANDSHAKE_MODE="$old_handshake"
      users_tx_rollback "$tx" 1
      open_firewall_for_pairs "$old_bindings"
      close_bindings="$(comm -23 \
        <(printf '%s\n' "$new_bindings" | sed '/^[[:space:]]*$/d' | LC_ALL=C sort -u) \
        <(printf '%s\n' "$old_bindings" | sed '/^[[:space:]]*$/d' | LC_ALL=C sort -u))"
      [ -z "$close_bindings" ] || close_firewall_for_bindings "$close_bindings"
      admin_lock_release
      return 1
    fi
    users_tx_commit "$tx"
    client_exports_after_reconfigure "$old_user" "$old_protocol" "$old_mtu" \
      "$old_traffic" "$old_seed" "$old_low_entropy" "$old_mux" "$old_handshake" \
      2>/dev/null || true
    close_bindings="$(comm -23 \
      <(printf '%s\n' "$old_bindings" | sed '/^[[:space:]]*$/d' | LC_ALL=C sort -u) \
      <(printf '%s\n' "$new_bindings" | sed '/^[[:space:]]*$/d' | LC_ALL=C sort -u))"
    [ -z "$close_bindings" ] || close_firewall_for_bindings "$close_bindings"
    admin_lock_release
  else
    admin_lock_acquire || return 1
    tx="$(users_tx_snapshot)" || { admin_lock_release; return 1; }
    if ! users_migrate_from_primary; then
      PORT="$old_port"; PORT_RANGE="$old_port_range"; PROTOCOL="$old_protocol"
      MTU="$old_mtu"; MTU_POLICY="$old_mtu_policy"; PROFILE="$old_profile"
      USERNAME="$old_user"; PASSWORD="$old_password"
      ADVERTISE_HOST="$old_advertise_host"; ADVERTISE_PORT="$old_advertise_port"
      TRAFFIC_PATTERN="$old_traffic"; TRAFFIC_SEED="$old_seed"
      LOW_ENTROPY_MODE="$old_low_entropy"; MULTIPLEXING="$old_mux"; HANDSHAKE_MODE="$old_handshake"
      users_tx_rollback "$tx" 0
      admin_lock_release
      return 1
    fi
    if ! apply_users_config "$tx"; then
      PORT="$old_port"; PORT_RANGE="$old_port_range"; PROTOCOL="$old_protocol"
      MTU="$old_mtu"; MTU_POLICY="$old_mtu_policy"; PROFILE="$old_profile"
      USERNAME="$old_user"; PASSWORD="$old_password"
      ADVERTISE_HOST="$old_advertise_host"; ADVERTISE_PORT="$old_advertise_port"
      TRAFFIC_PATTERN="$old_traffic"; TRAFFIC_SEED="$old_seed"
      LOW_ENTROPY_MODE="$old_low_entropy"; MULTIPLEXING="$old_mux"; HANDSHAKE_MODE="$old_handshake"
      admin_lock_release
      return 1
    fi
    new_bindings="$(multi_user_port_protocol_pairs)"
    open_firewall_for_pairs "$new_bindings"
    if ! verify_mita_running || ! save_install_state; then
      PORT="$old_port"; PORT_RANGE="$old_port_range"; PROTOCOL="$old_protocol"
      MTU="$old_mtu"; MTU_POLICY="$old_mtu_policy"; PROFILE="$old_profile"
      USERNAME="$old_user"; PASSWORD="$old_password"
      ADVERTISE_HOST="$old_advertise_host"; ADVERTISE_PORT="$old_advertise_port"
      TRAFFIC_PATTERN="$old_traffic"; TRAFFIC_SEED="$old_seed"
      LOW_ENTROPY_MODE="$old_low_entropy"; MULTIPLEXING="$old_mux"; HANDSHAKE_MODE="$old_handshake"
      isolated_stop_all
      users_tx_restore "$tx" >/dev/null 2>&1 || true
      default_mita_restore || true
      open_firewall_for_pairs "$old_bindings"
      close_bindings="$(comm -23 \
        <(printf '%s\n' "$new_bindings" | sed '/^[[:space:]]*$/d' | LC_ALL=C sort -u) \
        <(printf '%s\n' "$old_bindings" | sed '/^[[:space:]]*$/d' | LC_ALL=C sort -u))"
      [ -z "$close_bindings" ] || close_firewall_for_bindings "$close_bindings"
      users_tx_commit "$tx"
      admin_lock_release
      return 1
    fi
    users_tx_commit "$tx"
    client_exports_after_reconfigure "$old_user" "$old_protocol" "$old_mtu" \
      "$old_traffic" "$old_seed" "$old_low_entropy" "$old_mux" "$old_handshake" \
      2>/dev/null || true
    close_bindings="$(comm -23 \
      <(printf '%s\n' "$old_bindings" | sed '/^[[:space:]]*$/d' | LC_ALL=C sort -u) \
      <(printf '%s\n' "$new_bindings" | sed '/^[[:space:]]*$/d' | LC_ALL=C sort -u))"
    [ -z "$close_bindings" ] || close_firewall_for_bindings "$close_bindings"
    admin_lock_release
  fi
  msg ""
  t '========== 重新配置完成 ==========' '========== Reconfigure complete =========='
  if users_state_exists && [ "$(users_count)" -gt 1 ]; then
    t '提示: 多用户模式下「重新配置」只改主用户凭据/端口与全局协议；其它用户端口不变' \
      'Note: multi-user reconfigure updates primary user + global protocol only; other ports unchanged'
  fi
  print_summary current
}

do_upgrade() {
  require_root
  require_linux
  require_cmd curl
  local pm arch ver url tmp tx
  local requested_channel="$MIERU_CHANNEL" requested_version="$MIERU_VERSION"
  local requested_channel_cli="${MIERU_CHANNEL_CLI:-0}" requested_version_cli="${MIERU_VERSION_CLI:-0}"
  pm="$(detect_pkg_manager)"
  arch="$(detect_arch)"
  ensure_management_dependencies "$pm"
  MIERU_CHANNEL_CLI=0 MIERU_VERSION_CLI=0
  load_install_state 2>/dev/null || true
  MIERU_CHANNEL_CLI="$requested_channel_cli"; MIERU_VERSION_CLI="$requested_version_cli"
  if [ "$MIERU_CHANNEL_CLI" -eq 1 ]; then
    MIERU_CHANNEL="$requested_channel"
  fi
  if [ "$MIERU_VERSION_CLI" -eq 1 ]; then
    MIERU_VERSION="$requested_version"
  fi
  ver="$(target_mieru_version)"
  local cur
  cur="$(installed_version || true)"
  if version_is_current "$cur" "$ver"; then
    MIERU_VERSION="$ver"
    install_self_script
    if users_state_exists && [ "$(users_count)" -gt 0 ]; then
      admin_lock_acquire || return 1
      tx="$(users_tx_snapshot)" || { admin_lock_release; return 1; }
      # 即使二进制已是最新版，也要让运行中的实例重新读取最新 unit/runner。
      users_isolated_mode && isolated_stop_all
      if ! apply_users_config "$tx"; then
        admin_lock_release
        return 1
      fi
      users_tx_commit "$tx"
      admin_lock_release
      verify_mita_running
    fi
    [ -f "$MITA_STATE" ] && save_install_state
    t "管理脚本已更新至 v${SCRIPT_VERSION}（mita ${cur} 已满足 $(mieru_channel_label) 目标 ${ver}）" \
      "Manager script updated to v${SCRIPT_VERSION} (mita ${cur} satisfies $(mieru_channel_label) target ${ver})"
    [ "${MENU_MODE:-0}" -eq 1 ] && return 0
    exit 0
  fi
  url="$(package_url "$ver" "$pm" "$arch")"
  tmp="$(mktemp_file)"
  download_package "$url" "$tmp"
  install_package "$tmp" "$pm"
  rm -f "$tmp"
  MIERU_VERSION="$ver"
  install_self_script
  if users_state_exists && [ "$(users_count)" -gt 0 ]; then
    admin_lock_acquire || return 1
    tx="$(users_tx_snapshot)" || { admin_lock_release; return 1; }
    if users_isolated_mode; then
      isolated_stop_all
    else
      default_mita_stop
    fi
    if ! apply_users_config "$tx"; then
      admin_lock_release
      return 1
    fi
    users_tx_commit "$tx"
    admin_lock_release
  else
    run "$(mita_bin)" reload 2>/dev/null || start_mita
  fi
  verify_mita_running
  [ -f "$MITA_STATE" ] && save_install_state
  t "已升级至 ${ver}（$(mieru_channel_label)）" \
    "Upgraded to ${ver} ($(mieru_channel_label))"
}

mita_uninstall_target_present() {
  mita_installed \
    || installed_by_oneclick \
    || [ -e "$MITA_LEGACY_MARKER" ] \
    || [ -d "$MITA_MANAGER_STATE_DIR" ] \
    || [ -x "$INSTALL_SCRIPT_PATH" ] \
    || is_mita_wrapper "$MITA_BIN" \
    || [ -d /etc/mita ] \
    || [ -e "$MITA_INSTANCE_SYSTEMD_TEMPLATE" ] \
    || [ -e "$MITA_USERS_TIMER" ] \
    || [ -e "$MITA_USERS_SERVICE" ]
}

stop_mita_for_uninstall() {
  local bin sm isolated=0
  STAGE="停止 mita 服务"
  bin="$(mita_bin)"
  users_isolated_mode && isolated=1
  isolated_stop_all
  tc_clear_owned_filters 2>/dev/null || true
  if [ "$isolated" -eq 0 ] && [ -x "$bin" ]; then
    run "$bin" stop >/dev/null 2>&1 || true
  fi
  sm="$(service_manager)"
  case "$sm" in
    systemd)
      run systemctl disable --now mita.service 2>/dev/null || true
      run systemctl disable --now mita-users-scan.timer mita-users-scan.service \
        mita-tc-restore.service 2>/dev/null || true
      ;;
    openrc)
      run rc-service mita stop 2>/dev/null || true
      run rc-update del mita default 2>/dev/null || true
      ;;
  esac
  command -v pkill >/dev/null 2>&1 && run pkill -x mita 2>/dev/null || true
}

remove_mita_common() {
  STAGE="删除 mita 文件与账号"
  local preserve_package="${UNINSTALL_PRESERVE_PACKAGE:-0}"
  local preserve_user="${UNINSTALL_PRESERVE_USER:-0}"
  local preserve_group="${UNINSTALL_PRESERVE_GROUP:-0}"
  run rm -f /var/log/mita-oneclick-*.log /var/log/mita-oneclick-*.err
  if [ "$preserve_package" -eq 0 ]; then
    run rm -f /var/log/mita.log /var/log/mita.err
  fi
  run rm -f /root/mieru_client_*.json 2>/dev/null || true
  run rm -rf "$MITA_CLIENT_EXPORT_DIR"
  remove_users_scheduler 2>/dev/null || true
  run rm -f "$MITA_LOGROTATE_CONF" 2>/dev/null || true
  run rm -rf "$MITA_INSTANCES_DIR" "$MITA_INSTANCE_RUN_DIR" \
    "$MITA_INSTANCE_METRICS_DIR" "$MITA_USERS_BACKUP_DIR" "$MITA_MANAGER_STATE_DIR"
  if [ "$preserve_package" -eq 0 ]; then
    run rm -rf /etc/mita /var/lib/mita /run/mita /var/run/mita /var/run/mita.sock
  fi
  run rm -f "$MITA_USERS_STATE" "$MITA_USERS_LOCK" "$MITA_ADMIN_LOCK" \
    "$MITA_FIREWALL_OWNED_STATE" "$TC_OWNED_STATE" "$MITA_STATE"
  run rm -f "$MITA_BIN" "$MITA_REAL_BIN" /usr/bin/mita-real "$MITA_MARKER"
  run rm -f "$MITA_INSTANCE_SYSTEMD_TEMPLATE" "$MITA_INSTANCE_TMPFILES" \
    "$MITA_INSTANCE_RUNNER" "${MITA_INSTANCE_OPENRC_PREFIX}"*
  run rm -f "$MITA_USERS_LOG" 2>/dev/null || true
  if [ "$preserve_package" -eq 0 ] \
     && { ! command -v dpkg >/dev/null 2>&1 || ! dpkg -l mita 2>/dev/null | grep -q '^ii'; }; then
    run rm -f /usr/bin/mita
  fi
  if [ "$preserve_package" -eq 0 ]; then
    run rm -f /lib/systemd/system/mita.service /usr/lib/systemd/system/mita.service \
      "$SYSTEMD_SVC" "$OPENRC_SVC"
  fi
  if [ -d /etc/systemd/system ]; then
    if [ "$preserve_package" -eq 1 ]; then
      find /etc/systemd/system -type l \
        \( -name 'mita-oneclick@*.service' -o -name 'mita-users-scan.timer' \
           -o -name 'mita-tc-restore.service' \) -delete 2>/dev/null || true
    else
      find /etc/systemd/system -type l \
        \( -name 'mita.service' -o -name 'mita-oneclick@*.service' \
           -o -name 'mita-users-scan.timer' -o -name 'mita-tc-restore.service' \) \
        -delete 2>/dev/null || true
    fi
  fi
  run systemctl daemon-reload 2>/dev/null || true
  run systemctl reset-failed 2>/dev/null || true
  remove_self_script
  if [ "$preserve_user" -eq 0 ] && _has_user mita; then
    run deluser mita 2>/dev/null || run userdel mita 2>/dev/null || true
  fi
  if [ "$preserve_group" -eq 0 ] && _has_group mita; then
    run delgroup mita 2>/dev/null || run groupdel mita 2>/dev/null || true
  fi
}

verify_mita_uninstalled() {
  STAGE="验收卸载结果"
  local failed=0 path pattern save_cmd
  local preserve_package="${UNINSTALL_PRESERVE_PACKAGE:-0}"
  local preserve_user="${UNINSTALL_PRESERVE_USER:-0}"
  local preserve_group="${UNINSTALL_PRESERVE_GROUP:-0}"
  if [ "$preserve_package" -eq 0 ] \
     && command -v dpkg-query >/dev/null 2>&1 \
     && dpkg-query -W -f='${db:Status-Abbrev}' mita 2>/dev/null | grep -q .; then
    warn "$(t '卸载验收失败: Debian 软件包记录仍存在' \
      'Uninstall verification failed: Debian package record remains')"
    failed=1
  fi
  if [ "$preserve_package" -eq 0 ] \
     && command -v rpm >/dev/null 2>&1 && rpm -q mita >/dev/null 2>&1; then
    warn "$(t '卸载验收失败: RPM 软件包仍存在' \
      'Uninstall verification failed: RPM package remains')"
    failed=1
  fi
  for path in \
    "$MITA_MANAGER_STATE_DIR" \
    "$MITA_INSTANCES_DIR" "$MITA_INSTANCE_RUN_DIR" "$MITA_INSTANCE_METRICS_DIR" \
    "$MITA_USERS_STATE" "$MITA_USERS_LOCK" "$MITA_USERS_BACKUP_DIR" \
    "$MITA_ADMIN_LOCK" "$MITA_FIREWALL_OWNED_STATE" "$TC_OWNED_STATE" \
    "$MITA_BIN" "$MITA_REAL_BIN" /usr/bin/mita-real \
    "$INSTALL_SCRIPT_PATH" "$MITA_MENU_PATH" "$MITA_PROFILE_D" "$MITA_CLIENT_EXPORT_DIR" \
    "$MITA_INSTANCE_SYSTEMD_TEMPLATE" "$MITA_INSTANCE_TMPFILES" "$MITA_INSTANCE_RUNNER" \
    "$MITA_USERS_TIMER" "$MITA_USERS_SERVICE" "$MITA_USERS_CRON" "$MITA_LOGROTATE_CONF" \
    "$MITA_USERS_LOG" \
    "$BBR_STATE_FILE" "$BBR_BACKUP_FILE"; do
    if [ -e "$path" ] || [ -L "$path" ]; then
      warn "$(t "卸载残留: ${path}" "Uninstall residue: ${path}")"
      failed=1
    fi
  done
  if [ "$preserve_package" -eq 0 ]; then
    for path in /etc/mita /var/lib/mita /run/mita /var/run/mita /usr/bin/mita \
      "$SYSTEMD_SVC" /lib/systemd/system/mita.service /usr/lib/systemd/system/mita.service \
      "$OPENRC_SVC" /var/log/mita.log /var/log/mita.err; do
      if [ -e "$path" ] || [ -L "$path" ]; then
        warn "$(t "卸载残留: ${path}" "Uninstall residue: ${path}")"
        failed=1
      fi
    done
  fi
  for pattern in \
    "${MITA_INSTANCE_OPENRC_PREFIX}*" '/var/log/mita-oneclick-*.log' \
    '/var/log/mita-oneclick-*.err' '/root/mieru_client_*.json'; do
    if compgen -G "$pattern" >/dev/null 2>&1; then
      warn "$(t "卸载仍有匹配残留: ${pattern}" "Uninstall residue matches: ${pattern}")"
      failed=1
    fi
  done
  local systemd_link_names=( -name 'mita-oneclick@*.service' -o -name 'mita-users-scan.timer' \
    -o -name 'mita-tc-restore.service' )
  if [ "$preserve_package" -eq 0 ]; then
    systemd_link_names=( -name 'mita.service' -o "${systemd_link_names[@]}" )
  fi
  if [ -d /etc/systemd/system ] \
     && find /etc/systemd/system -type l \( "${systemd_link_names[@]}" \) \
       -print -quit 2>/dev/null | grep -q .; then
    warn "$(t '卸载残留: systemd wants 目录仍有 mita 符号链接' \
      'Uninstall residue: systemd wants directories still contain mita symlinks')"
    failed=1
  fi
  if command -v pgrep >/dev/null 2>&1 && pgrep -x mita >/dev/null 2>&1; then
    warn "$(t '卸载残留: mita 进程仍在运行' 'Uninstall residue: mita process is still running')"
    failed=1
  fi
  if { [ "$preserve_user" -eq 0 ] && _has_user mita; } \
     || { [ "$preserve_group" -eq 0 ] && _has_group mita; }; then
    warn "$(t '卸载残留: mita 系统用户或用户组仍存在' \
      'Uninstall residue: mita system user or group remains')"
    failed=1
  fi
  for save_cmd in iptables-save ip6tables-save; do
    if command -v "$save_cmd" >/dev/null 2>&1 \
       && "$save_cmd" 2>/dev/null | grep -q -- "$MITA_FIREWALL_COMMENT"; then
      warn "$(t "卸载残留: ${save_cmd} 中仍有 ${MITA_FIREWALL_COMMENT} 规则" \
        "Uninstall residue: ${save_cmd} still contains ${MITA_FIREWALL_COMMENT} rules")"
      failed=1
    fi
  done
  [ "$failed" -eq 0 ]
}

do_uninstall() {
  require_root
  UNINSTALL_CANCELLED=0
  UNINSTALL_PRESERVE_EXTERNAL=0
  UNINSTALL_PRESERVE_PACKAGE=0
  UNINSTALL_PRESERVE_USER=0
  UNINSTALL_PRESERVE_GROUP=0
  mita_uninstall_target_present \
    || die "$(t '未检测到 mita 或 OneClick 残留，无需卸载' \
      'No mita or OneClick residue detected; nothing to uninstall')"
  if ! installed_by_oneclick; then
    warn "$(t '未检测到完整的 OneClick 安装标记；将按残留/官方包清理模式处理' \
      'Complete OneClick marker not found; residual/official package cleanup mode will be used')"
    if ! confirm '仍要继续卸载？[y/N]: ' 'Continue uninstall anyway? [y/N]: ' n; then
      if [ "${MENU_MODE:-0}" -eq 1 ]; then
        UNINSTALL_CANCELLED=1
        return 0
      fi
      exit 0
    fi
  fi
  if ! confirm '确认卸载 mita、OneClick 管理脚本及本项目管理的配置？[y/N]: ' \
    'Uninstall mita, the OneClick manager, and project-managed configuration? [y/N]: ' n; then
    if [ "${MENU_MODE:-0}" -eq 1 ]; then
      UNINSTALL_CANCELLED=1
      return 0
    fi
    exit 0
  fi
  if preexisting_mita_resources_recorded; then
    UNINSTALL_PRESERVE_EXTERNAL=1
    [ -f "$MITA_PRESERVE_PACKAGE_MARKER" ] && UNINSTALL_PRESERVE_PACKAGE=1
    [ -f "$MITA_PRESERVE_USER_MARKER" ] && UNINSTALL_PRESERVE_USER=1
    [ -f "$MITA_PRESERVE_GROUP_MARKER" ] && UNINSTALL_PRESERVE_GROUP=1
    warn "$(t '检测到安装前已存在的 mita 包或系统账号；将按记录分别保留外部资源，预存包的公共目录也会保留，并保持服务停止。' \
      'A pre-existing mita package or system account was recorded; each external resource will be preserved separately, including shared directories for a pre-existing package, and left stopped.')"
  fi
  local pm
  # 必须在停止服务、清理规则和卸载软件包之前确认 BBR 文件仍由本脚本拥有，
  # 避免因人工修改触发保护后留下半卸载状态。
  if ! restore_owned_bbr_fq; then
    bail "$(t 'BBR/FQ 配置已被外部修改，卸载已在删除任何 mita 文件前停止' \
      'BBR/FQ configuration was modified externally; uninstall stopped before removing any mita files')" || return 1
    return 1
  fi
  pm="$(detect_pkg_manager)"
  stop_mita_for_uninstall
  STAGE="清理防火墙规则"
  close_firewall
  firewall_clear_all_owned
  STAGE="卸载 mita 软件包"
  if [ "$UNINSTALL_PRESERVE_PACKAGE" -eq 0 ]; then
    case "$pm" in
      deb)
        if dpkg-query -W mita >/dev/null 2>&1; then
          run dpkg -P mita
        fi
        ;;
      rpm)
        if rpm -q mita >/dev/null 2>&1; then
          run rpm -e mita
        fi
        ;;
      alpine) ;;
    esac
  fi
  remove_mita_common
  if ! verify_mita_uninstalled; then
    warn "$(t '卸载未完全通过验收；已保留上方残留信息，请修复后重试' \
      'Uninstall did not pass verification; review the residue above and retry')"
    return 1
  fi
  if [ "$UNINSTALL_PRESERVE_EXTERNAL" -eq 1 ]; then
    t 'OneClick 管理文件已卸载；安装前存在的 mita 外部资源已保留，服务保持停止。' \
      'OneClick management files were removed; pre-existing mita resources were preserved and left stopped.'
  else
    t 'mita 及安装脚本已完全卸载' 'mita and install script fully removed'
  fi
  t '若当前已打开的旧终端仍显示 mita 是函数，请运行:' \
    'If an already-open shell still reports mita as a function, run:'
  msg '  unset -f mita 2>/dev/null || true; hash -r'
  t '新登录终端不会再加载该函数。' 'New login shells will no longer load that function.'
}

status_binding_text() {
  local port="$1"
  case "${PROTOCOL:-TCP}" in
    BOTH) printf 'TCP %s / UDP %s' "$port" "$((port + 1))" ;;
    UDP) printf 'UDP %s' "$port" ;;
    *) printf 'TCP %s' "$port" ;;
  esac
}

do_status() {
  local bin sm status_out recovered=0 iid iname iport
  bin="$(mita_bin)"
  sm="$(service_manager)"
  if ! mita_installed; then
    t 'mita 未安装' 'mita is not installed'
    [ "${MENU_MODE:-0}" -eq 1 ] && return 1
    exit 1
  fi
  load_install_state 2>/dev/null || true
  msg ""
  t '【版本与配置】' '[Version and configuration]'
  t "  OneClick Version: ${SCRIPT_VERSION}" "  OneClick Version: ${SCRIPT_VERSION}"
  t "  Installed Mieru: $(installed_version 2>/dev/null || printf unknown)" \
    "  Installed Mieru: $(installed_version 2>/dev/null || printf unknown)"
  t "  Channel: $(mieru_channel_label)" "  Channel: $(mieru_channel_label)"
  t "  Tested/Stable Mieru: ${TESTED_MIERU_VERSION}" \
    "  Tested/Stable Mieru: ${TESTED_MIERU_VERSION}"
  t "  Profile: $(profile_label)" "  Profile: $(profile_label)"
  msg ""
  if users_isolated_mode; then
    t '部署模型: 用户专属实例 isolated-v2' 'Deployment: dedicated user instances (isolated-v2)'
    if [ -z "$(users_enabled_instance_rows 2>/dev/null || true)" ]; then
      warn "$(t '当前没有启用中的用户；所有专属实例均应处于停止状态' \
        'No users are enabled; all dedicated instances should be stopped')"
    fi
    while IFS=$'\t' read -r iid iname iport; do
      [ -n "$iid" ] || continue
      msg ""
      t "【${iname} / ${iid}】" "[${iname} / ${iid}]"
      t "  监听: $(status_binding_text "$iport")" \
        "  Listen: $(status_binding_text "$iport")"
      case "$sm" in
        systemd) systemctl status "$(instance_systemd_unit "$iid")" --no-pager 2>/dev/null | head -n 12 || true ;;
        openrc) rc-service "$(instance_openrc_service "$iid")" status 2>/dev/null || true ;;
      esac
      status_out="$(instance_cmd "$iid" status 2>/dev/null || true)"
      msg "${status_out:-status unavailable}"
    done < <(users_enabled_instance_rows)
    msg ""
    t '状态页已隐藏密码；查看或导出节点配置请使用主菜单「查看节点」' \
      'Passwords are hidden on the status page; use View node in the main menu to view or export node configuration'
    return 0
  fi
  case "$sm" in
    systemd) systemctl status mita --no-pager 2>/dev/null || true ;;
    openrc)
      openrc_mita_status_line
      if openrc_mita_is_crashed; then
        warn "$(t 'mita 处于 crashed 状态，正在自动恢复...' 'mita is crashed; auto-recovering...')"
        openrc_mita_recover
        recovered=1
        openrc_mita_status_line
      elif ! openrc_mita_is_started; then
        warn "$(t 'mita 未运行，正在尝试启动...' 'mita is not running; trying to start...')"
        openrc_mita_recover
        recovered=1
        openrc_mita_status_line
      fi
      ;;
    *) true ;;
  esac
  msg ""
  if ! wait_mita_socket 3; then
    if [ "$recovered" -eq 0 ]; then
      ensure_mita_daemon
    fi
    if ! wait_mita_socket 10; then
      warn "$(t "mita 守护进程未就绪，请执行: $(mita_restart_hint)" \
        "mita daemon not ready; run: $(mita_restart_hint)")"
      warn "$(t "查看日志: $(mita_log_hint)" "Check logs: $(mita_log_hint)")"
      mita_log_tail
    fi
  fi
  status_out="$("$bin" status 2>/dev/null || true)"
  if [ -n "$status_out" ]; then
    msg "$status_out"
  fi
  if printf '%s' "$status_out" | grep -qi 'daemon is not running'; then
    warn "$(t "请执行: $(mita_restart_hint)" "Run: $(mita_restart_hint)")"
    warn "$(t "查看日志: $(mita_log_hint)" "Check logs: $(mita_log_hint)")"
  fi
  msg ""
  if [ -n "${PORT:-}" ]; then
    t "监听: $(status_binding_text "$PORT")" \
      "Listen: $(status_binding_text "$PORT")"
  fi
  t '状态页已隐藏密码；查看或导出节点配置请使用主菜单「查看节点」' \
    'Passwords are hidden on the status page; use View node in the main menu to view or export node configuration'
}

do_client_config() {
  require_root
  mita_installed || bail "$(t 'mita 未安装' 'mita is not installed')" || return 1
  repair_mita_binary_paths 2>/dev/null || true
  if ! users_isolated_mode; then
    ensure_mita_daemon
    wait_mita_socket 20 || warn "$(t 'mita 守护进程未就绪，正在尝试继续...' 'mita daemon not ready, trying anyway...')"
  fi
  load_config_from_mita || return 1
  generate_client_config
}

rollback_mtu_change() {
  local restore_mtu="$1" restore_policy="$2" restore_profile="${3:-custom}" rollback_cfg=""
  MTU="$restore_mtu"
  MTU_POLICY="$restore_policy"
  PROFILE="$restore_profile"
  if users_isolated_mode; then
    reconcile_isolated_instances && verify_mita_running
    return
  fi
  rollback_cfg="$(write_server_config 2>/dev/null)" || return 1
  apply_config "$rollback_cfg" \
    && start_mita \
    && verify_mita_running
}

do_mtu_config() {
  require_root || return 1
  require_linux || return 1
  mita_installed || bail "$(t 'mita 未安装，请先安装' 'mita is not installed; run install first')" || return 1
  repair_mita_binary_paths 2>/dev/null || true
  load_config_from_mita || return 1

  local old_mtu="$MTU" old_policy="$MTU_POLICY" old_profile="$PROFILE" cfg=""
  msg ""
  t "当前 MTU: ${old_mtu}（$(mtu_policy_label)）" \
    "Current MTU: ${old_mtu} ($(mtu_policy_label))"
  if [ "${MTU_CLI:-0}" -eq 1 ]; then
    resolve_mtu_request || return 1
    print_mtu_selection
  else
    choose_mtu_interactive || return 1
  fi

  if [ "$MTU" = "$old_mtu" ]; then
    save_install_state
    msg ""
    t "MTU 数值未变化，保持 ${MTU}；下面重新输出当前节点链接和配置。" \
      "MTU is unchanged at ${MTU}; current share links and config follow."
    generate_client_config
    return 0
  fi

  PROFILE=custom

  admin_lock_acquire || return 1
  if users_state_exists && [ "$(users_count)" -gt 0 ]; then
    MULTI_USER_MODE=1
    if ! reconcile_isolated_instances || ! verify_mita_running; then
      warn "$(t "新 MTU ${MTU} 未能正常启动，正在回滚到 ${old_mtu}" \
        "New MTU ${MTU} failed to start; rolling back to ${old_mtu}")"
      rollback_mtu_change "$old_mtu" "$old_policy" "$old_profile" || true
      admin_lock_release
      return 1
    fi
  else
    MULTI_USER_MODE=0
    if ! cfg="$(write_server_config)" || ! apply_config "$cfg" \
        || ! start_mita || ! verify_mita_running; then
      warn "$(t "新 MTU ${MTU} 未能正常启动，正在回滚到 ${old_mtu}" \
        "New MTU ${MTU} failed to start; rolling back to ${old_mtu}")"
      rollback_mtu_change "$old_mtu" "$old_policy" "$old_profile" || true
      admin_lock_release
      return 1
    fi
  fi
  if ! save_install_state; then
    warn "$(t '保存 MTU 状态失败，正在恢复原服务端配置' \
      'Failed to save MTU state; restoring the previous server config')"
    rollback_mtu_change "$old_mtu" "$old_policy" "$old_profile" || \
      warn "$(t '自动回滚未能完全验证，请运行 mita doctor 检查服务' \
        'Automatic rollback could not be fully verified; run mita doctor')"
    admin_lock_release
    return 1
  fi
  admin_lock_release
  client_exports_clear_current 2>/dev/null || true

  msg ""
  t "========== MTU 调整完成：${old_mtu} → ${MTU} ==========" \
    "========== MTU updated: ${old_mtu} -> ${MTU} =========="
  t '服务端配置已重新应用并完成重启；请在客户端重新导入下面的新链接或 JSON。' \
    'Server config was reapplied and restarted; re-import the new link or JSON on clients.'
  generate_client_config
}

do_profile_config() {
  require_root || return 1
  require_linux || return 1
  mita_installed || bail "$(t 'mita 未安装，请先安装' 'mita is not installed; run install first')" || return 1
  repair_mita_binary_paths 2>/dev/null || true
  load_config_from_mita || return 1
  if [ "${PROFILE_CLI:-0}" -eq 1 ]; then
    PROFILE="$(normalize_profile "$PROFILE")" || die "$(t '非法 Profile' 'Invalid profile')"
  else
    choose_profile_interactive
  fi
  if [ "$PROFILE" = custom ]; then
    t '高级自定义将逐项开放现有高级参数。' \
      'Advanced Custom opens all existing advanced parameters.'
    PROFILE_CLI=1
    do_reconfigure
    return
  fi
  apply_profile_values "$PROFILE"
  PROFILE_CLI=1
  PROTOCOL_CLI=1
  MTU_REQUEST="$MTU"; MTU_CLI=1
  MULTIPLEXING_CLI=1
  HANDSHAKE_CLI=1
  TRAFFIC_CLI=1
  LOW_ENTROPY_CLI=1
  local saved_yes="$YES"
  YES=1
  do_reconfigure
  YES="$saved_yes"
}

do_tuning_config() {
  local kind="$1" old_value="" saved_yes="$YES"
  require_root || return 1
  require_linux || return 1
  mita_installed || bail "$(t 'mita 未安装，请先安装' 'mita is not installed; run install first')" || return 1
  repair_mita_binary_paths 2>/dev/null || true
  load_config_from_mita || return 1
  PROFILE=custom
  PROFILE_CLI=1
  case "$kind" in
    client-modes)
      old_value="${MULTIPLEXING}|${HANDSHAKE_MODE}"
      MULTIPLEXING_CLI=0 HANDSHAKE_CLI=0
      choose_client_modes_interactive
      [ "$old_value" != "${MULTIPLEXING}|${HANDSHAKE_MODE}" ] || return 0
      MULTIPLEXING_CLI=1 HANDSHAKE_CLI=1
      ;;
    traffic)
      old_value="${TRAFFIC_PATTERN}|${LOW_ENTROPY_MODE}"
      TRAFFIC_CLI=0
      choose_traffic_pattern_interactive
      [ "$TRAFFIC_PATTERN" != off ] || LOW_ENTROPY_MODE=LOW_ENTROPY_MODE_OFF
      [ "$old_value" != "${TRAFFIC_PATTERN}|${LOW_ENTROPY_MODE}" ] || return 0
      TRAFFIC_CLI=1 LOW_ENTROPY_CLI=1
      ;;
    low-entropy)
      if [ "$(normalize_traffic_pattern "${TRAFFIC_PATTERN:-off}")" = off ]; then
        warn "$(t 'Traffic Pattern 当前为 OFF；Low Entropy 依赖该能力，请先配置 Traffic Pattern。' \
          'Traffic Pattern is OFF; Low Entropy depends on it, so configure Traffic Pattern first.')"
        return 0
      fi
      old_value="$LOW_ENTROPY_MODE"
      LOW_ENTROPY_CLI=0
      choose_low_entropy_interactive
      [ "$old_value" != "$LOW_ENTROPY_MODE" ] || return 0
      LOW_ENTROPY_CLI=1
      ;;
    *) return 1 ;;
  esac
  YES=1
  do_reconfigure
  YES="$saved_yes"
}

do_bbr_config() {
  require_root || return 1
  require_linux || return 1
  report_bbr_fq_status
  offer_bbr_fq
}

do_version_channel_config() {
  require_root || return 1
  load_install_state 2>/dev/null || true
  local input="" version=""
  msg ""
  t "当前通道: $(mieru_channel_label)" "Current channel: $(mieru_channel_label)"
  t "  1) stable — 项目测试版本 ${TESTED_MIERU_VERSION}" \
    "  1) stable — project-tested ${TESTED_MIERU_VERSION}"
  t '  2) latest — 每次升级查询上游最新 release' \
    '  2) latest — query the newest upstream release on each upgrade'
  t '  3) pinned — 指定精确版本（高级）' \
    '  3) pinned — use an exact version (advanced)'
  read_tty input "$(t '请选择 [1-3]: ' 'Choose [1-3]: ')" || input=""
  case "$input" in
    1) MIERU_CHANNEL=stable; MIERU_VERSION="$TESTED_MIERU_VERSION" ;;
    2) MIERU_CHANNEL=latest; MIERU_VERSION="" ;;
    3)
      read_tty version "$(t '精确版本（例如 3.35.0）: ' 'Exact version (for example 3.35.0): ')" || version=""
      valid_mieru_version "$version" || die "$(t '版本号格式无效' 'Invalid version format')"
      MIERU_CHANNEL=pinned; MIERU_VERSION="$version"
      ;;
    *) warn "$(t '已取消通道修改' 'Channel change cancelled')"; return 0 ;;
  esac
  MIERU_CHANNEL_CLI=1
  [ "$MIERU_CHANNEL" != pinned ] || MIERU_VERSION_CLI=1
  do_upgrade
}

do_start() {
  require_root || return 1
  mita_installed || bail "$(t 'mita 未安装，请先安装' 'mita is not installed')" || return 1
  repair_mita_binary_paths 2>/dev/null || true
  start_mita
  verify_mita_running 1
  if users_isolated_mode; then
    t '所有用户专属 mita 实例已启动' 'All dedicated mita user instances started'
  else
    t 'mita 服务已启动' 'mita service started'
  fi
}

do_stop() {
  require_root || return 1
  mita_installed || bail "$(t 'mita 未安装' 'mita is not installed')" || return 1
  local bin sm iid iname iport
  if users_isolated_mode; then
    STAGE="停止专属实例"
    while IFS=$'\t' read -r iid iname iport; do
      [ -n "$iid" ] || continue
      instance_daemon_stop "$iid" 0
    done < <(users_enabled_instance_rows)
    t '所有用户专属 mita 实例已停止' 'All dedicated mita user instances stopped'
    return 0
  fi
  bin="$(mita_bin)"
  sm="$(service_manager)"
  STAGE="停止服务"
  run "$bin" stop 2>/dev/null || true
  case "$sm" in
    systemd) run systemctl stop mita 2>/dev/null || true ;;
    openrc) run rc-service mita stop 2>/dev/null || true ;;
    *) true ;;
  esac
  sleep 1
  t 'mita 服务已停止' 'mita service stopped'
}

do_restart() {
  require_root || return 1
  mita_installed || bail "$(t 'mita 未安装' 'mita is not installed')" || return 1
  repair_mita_binary_paths 2>/dev/null || true
  local sm iid iname iport
  if users_isolated_mode; then
    STAGE="重启专属实例"
    while IFS=$'\t' read -r iid iname iport; do
      [ -n "$iid" ] || continue
      instance_daemon_stop "$iid" 0
      instance_start_proxy "$iid" || return 1
    done < <(users_enabled_instance_rows)
    verify_mita_running 1
    t '所有用户专属 mita 实例已重启' 'All dedicated mita user instances restarted'
    return 0
  fi
  sm="$(service_manager)"
  STAGE="重启服务"
  case "$sm" in
    systemd) run systemctl restart mita 2>/dev/null || true ;;
    openrc)
      run rc-service mita zap 2>/dev/null || true
      run rc-service mita restart 2>/dev/null || run rc-service mita start 2>/dev/null || true
      ;;
    *) true ;;
  esac
  start_mita
  verify_mita_running 1
  t 'mita 服务已重启' 'mita service restarted'
}

menu_pause() {
  local _ignore=""
  msg ""
  read_tty _ignore "$(t '按回车返回主菜单...' 'Press Enter to return to the menu...')" || true
}

user_menu_pause() {
  local _ignore=""
  msg ""
  read_tty _ignore "$(t '按回车返回用户管理菜单...' \
    'Press Enter to return to user management...')" || true
}

menu_run_action() {
  if dry_run_should_preview "$ACTION"; then
    dry_run_action_preview "$ACTION"
    return 0
  fi
  case "$ACTION" in
    install) do_install ;;
    reconfigure) do_reconfigure ;;
    upgrade) do_upgrade ;;
    uninstall)
      do_uninstall
      [ "${UNINSTALL_CANCELLED:-0}" -eq 1 ] && return 0
      # do_uninstall 只有在最终残留验收通过后才返回成功。
      return 2
      ;;
    status) do_status ;;
    client-config) do_client_config ;;
    mtu-config) do_mtu_config ;;
    start) do_start ;;
    stop) do_stop ;;
    restart) do_restart ;;
    user-list) do_user_list ;;
    user-add) do_user_add ;;
    user-del) do_user_del ;;
    user-show) do_user_show ;;
    user-manage) do_user_manage ;;
    user-set-endpoint) do_user_set_endpoint ;;
    user-set-quota) do_user_set_quota ;;
    user-set-expire) do_user_set_expire ;;
    user-enable) do_user_enable ;;
    user-disable) do_user_disable ;;
    user-scan) do_user_scan ;;
    user-quota-reset)
      if [ "${YES:-0}" -eq 1 ]; then
        do_user_quota_reset force
      else
        do_user_quota_reset
      fi
      ;;
    user-set-rate) do_user_set_rate ;;
    rate-status) do_rate_status ;;
    rate-restore) do_rate_restore ;;
    user-usage) do_user_usage ;;
    user-export-clients) do_user_export_clients ;;
    user-backup) do_user_backup ;;
    user-restore) do_user_restore ;;
    user-export) do_user_export ;;
    user-import) do_user_import ;;
    doctor) do_doctor ;;
    perf) do_perf ;;
    profile-config) do_profile_config ;;
    client-modes-config) do_tuning_config client-modes ;;
    traffic-config) do_tuning_config traffic ;;
    low-entropy-config) do_tuning_config low-entropy ;;
    bbr-config) do_bbr_config ;;
    version-channel) do_version_channel_config ;;
    help) usage ;;
    *) warn "$(t '未知操作' 'Unknown action')"; return 1 ;;
  esac
}

menu_loop() {
  MENU_MODE=1
  MAIN_MENU_ACTIVE=1
  trap - ERR
  # 仅当已安装(或半装/损坏状态)时才做二进制修复。否则在「全新系统」上，repair_mita_binary_paths
  # 会因找不到二进制而走 recover_deb_mita → reinstall_mita_package，在显示菜单前就「自动重下安装」mita，
  # 随后用户选「1) 新装安装」时便被误判「检测到已安装」。修复必须放进 mita_installed 守卫内（与非交互路径一致）。
  if [ "${DRY_RUN:-0}" -ne 1 ] && mita_installed; then
    repair_mita_binary_paths 2>/dev/null || true
    ensure_management_scripts || true
    MENU_SCRIPTS_READY=1
  fi
  while true; do
    ACTION=""
    # 安全捕获：set -e 下裸调用 show_menu 返回非0(无效输入)会直接退脚本
    local sm_rc=0
    show_menu || sm_rc=$?
    if [ "$sm_rc" -eq 2 ]; then
      break
    fi
    if [ "$sm_rc" -ne 0 ]; then
      continue
    fi
    # 不能把业务函数放在 if/|| 条件上下文中：Bash 会在整个函数调用链内
    # 抑制 errexit。用独立子 shell 作为简单命令执行，父菜单再读取退出码。
    local rc=0
    set +e
    (
      set -Eeuo pipefail
      trap 'rc=$?; if [ "$rc" -eq 2 ] || [ "$rc" -eq 3 ]; then exit "$rc"; fi; on_error' ERR
      menu_run_action
    )
    rc=$?
    set -e
    if [ "$rc" -eq 2 ]; then
      break
    fi
    if [ "$rc" -eq 3 ]; then
      continue
    fi
    if [ "$rc" -ne 0 ]; then
      warn "$(t '操作未完成，请重试或运行 mita doctor 排查' 'Action failed; retry or run mita doctor')"
    fi
    menu_pause
  done
}

show_performance_menu() {
  msg ""
  t '【性能与网络】' '[Performance and network]'
  msg '  1) 性能诊断（只读）'
  msg '  2) 配置预设 Profile'
  msg '  3) MTU'
  msg '  4) BBR / FQ'
  msg '  5) Multiplexing / Handshake'
  msg '  6) Traffic Pattern'
  msg '  7) Low Entropy'
  msg '  8) 带宽限制状态'
  msg '  0) 返回'
  local choice=""
  read_tty choice "$(t '请选择 [0-8]: ' 'Choose [0-8]: ')" || choice=""
  case "$(printf '%s' "$choice" | tr -d '[:space:]')" in
    1) ACTION=perf ;;
    2) ACTION="profile-config" ;;
    3) ACTION="mtu-config" ;;
    4) ACTION="bbr-config" ;;
    5) ACTION="client-modes-config" ;;
    6) ACTION="traffic-config" ;;
    7) ACTION="low-entropy-config" ;;
    8) ACTION="rate-status" ;;
    0) return 2 ;;
    *) warn "$(t '无效选择' 'Invalid choice')"; return 1 ;;
  esac
}

show_service_menu() {
  msg ""
  t '【服务管理】' '[Service management]'
  msg '  1) 状态'
  msg '  2) 启动'
  msg '  3) 停止'
  msg '  4) 重启'
  msg '  0) 返回'
  local choice=""
  read_tty choice "$(t '请选择 [0-4]: ' 'Choose [0-4]: ')" || choice=""
  case "$(printf '%s' "$choice" | tr -d '[:space:]')" in
    1) ACTION=status ;;
    2) ACTION=start ;;
    3) ACTION=stop ;;
    4) ACTION=restart ;;
    0) return 2 ;;
    *) warn "$(t '无效选择' 'Invalid choice')"; return 1 ;;
  esac
}

show_backup_menu() {
  msg ""
  t '【备份 / 恢复】' '[Backup / restore]'
  msg '  1) 备份用户状态'
  msg '  2) 从备份恢复'
  msg '  3) 导出用户状态 JSON'
  msg '  4) 导入用户状态 JSON'
  msg '  5) 批量导出客户端配置'
  msg '  0) 返回'
  local choice=""
  read_tty choice "$(t '请选择 [0-5]: ' 'Choose [0-5]: ')" || choice=""
  case "$(printf '%s' "$choice" | tr -d '[:space:]')" in
    1) ACTION=user-backup ;;
    2) ACTION="user-restore" ;;
    3) ACTION="user-export" ;;
    4) ACTION="user-import" ;;
    5) ACTION="user-export-clients" ;;
    0) return 2 ;;
    *) warn "$(t '无效选择' 'Invalid choice')"; return 1 ;;
  esac
}

show_advanced_menu() {
  msg ""
  t '【高级设置】' '[Advanced settings]'
  msg '  1) Mieru 版本通道'
  msg '  2) 清理并恢复本项目 tc 规则'
  msg '  3) 帮助 / 全部 CLI 命令'
  msg '  0) 返回'
  local choice=""
  read_tty choice "$(t '请选择 [0-3]: ' 'Choose [0-3]: ')" || choice=""
  case "$(printf '%s' "$choice" | tr -d '[:space:]')" in
    1) ACTION="version-channel" ;;
    2) ACTION="rate-restore" ;;
    3) ACTION=help ;;
    0) return 2 ;;
    *) warn "$(t '无效选择' 'Invalid choice')"; return 1 ;;
  esac
}

show_menu() {
  if [ "${DRY_RUN:-0}" -ne 1 ] \
     && [ "${MENU_SCRIPTS_READY:-0}" -eq 0 ] \
     && mita_installed; then
    ensure_management_scripts || true
    MENU_SCRIPTS_READY=1
  fi
  load_install_state 2>/dev/null || true
  local installed="no" users="-" selected_rc=0 profile_text="-" version_text=""
  if mita_installed; then installed="yes"; fi
  if [ "$installed" = yes ]; then
    users="$(users_count 2>/dev/null || echo 0)"
    profile_text="$(profile_label)"
    version_text="$(installed_version 2>/dev/null || printf '-')"
  else
    version_text="$(t '未安装' 'not installed')"
  fi
  msg ''
  t '========== Mieru OneClick ==========' '========== Mieru OneClick =========='
  t "作者: ${SCRIPT_AUTHOR} / https://github.com/${SCRIPT_REPO}" \
    "Author: ${SCRIPT_AUTHOR} / https://github.com/${SCRIPT_REPO}"
  t "状态: $([ "$installed" = yes ] && printf '已安装' || printf '未安装')" \
    "Status: $([ "$installed" = yes ] && printf 'installed' || printf 'not installed')"
  t "用户: ${users}" "Users: ${users}"
  t "Profile: ${profile_text}" "Profile: ${profile_text}"
  t "Mieru Version: ${version_text}" "Mieru Version: ${version_text}"
  msg ''
  if [ "$installed" = yes ]; then
    msg '  1) 修复安装'
  else
    msg '  1) 新装 / 安装'
  fi
  msg '  2) 查看节点'
  msg '  3) 用户管理'
  msg '  4) 性能与网络'
  if [ "$installed" = yes ]; then
    msg '  5) 重新配置'
  else
    msg '  5) 重新配置（需先安装）'
  fi
  msg '  6) 服务管理'
  msg '  7) 备份 / 恢复'
  msg '  8) 升级'
  msg '  9) Doctor'
  msg ' 10) 卸载'
  msg '  0) 退出'
  msg ""
  t '快捷命令: 直接输入 mita 打开菜单（不区分大小写）' \
    'Quick command: type mita to open menu (case-insensitive)'
  msg ""
  local choice=""
  read_tty choice "$(t '请选择 [0-10]: ' 'Choose [0-10]: ')" || choice=""
  choice="$(printf '%s' "$choice" | tr -d '[:space:]')"
  if [ -z "$choice" ]; then
    warn "$(t '请输入 0-10' 'Enter 0-10')"
    return 1
  fi
  case "$choice" in
    1) ACTION=install ;;
    2) ACTION=client-config ;;
    3) ACTION=user-manage ;;
    4)
      show_performance_menu || selected_rc=$?
      [ "$selected_rc" -eq 0 ] || return 1
      ;;
    5) ACTION=reconfigure ;;
    6)
      show_service_menu || selected_rc=$?
      [ "$selected_rc" -eq 0 ] || return 1
      ;;
    7)
      show_backup_menu || selected_rc=$?
      [ "$selected_rc" -eq 0 ] || return 1
      ;;
    8) ACTION=upgrade ;;
    9) ACTION=doctor ;;
    10) ACTION=uninstall ;;
    0) return 2 ;;
    *)
      warn "$(t '无效选择，请输入 0-10' 'Invalid choice, enter 0-10')"
      return 1
      ;;
  esac
  return 0
}

# ---------- NoBrand unified interactive presentation ----------

nobrand_menu_run() {
  local rc=0
  set +e
  (
    set -Eeuo pipefail
    trap 'rc=$?; on_error' ERR
    "$@"
  )
  rc=$?
  set -e
  if [ "$rc" -ne 0 ]; then
    warn "$(t '操作未完成；请重试或运行 nobrand doctor' \
      'Action did not complete; retry or run nobrand doctor')"
  fi
  return 0
}

snell_menu_select_instance() {
  local id name major found=0 choice=""
  msg ''
  msg 'Snell 节点:'
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    name="$(snell_state_field "$id" name)"
    major="$(snell_state_field "$id" version)"
    printf '  - %s (v%s, %s)\n' "$name" "$major" "$id"
    found=1
  done < <(snell_instance_ids)
  [ "$found" -eq 1 ] || { warn 'Snell 尚无节点'; return 1; }
  read_tty choice "$(t '输入节点名: ' 'Enter node name: ')" || choice=""
  [ -n "$choice" ] && snell_find_id_by_name "$choice" >/dev/null 2>&1 \
    || { warn '节点名不存在'; return 1; }
  SNELL_NAME="$choice"
}

snell_menu_install_version() {
  local version="$1"
  SNELL_VERSION="$version" SNELL_VERSION_CLI=1 SNELL_NAME="" SNELL_PSK=""
  SNELL_QUIC_PROXY="" SNELL_QUIC_CLI=0
  PORT="" PORT_CLI=0 ADVERTISE_HOST="" ADVERTISE_PORT="" ADVERTISE_CLI=0 ADVERTISE_AUTO_REQUESTED=0
  YES=0 SNELL_ACTION=install
  nobrand_menu_run nobrand_run_snell_action
}

snell_menu_set_quic() {
  local choice=""
  snell_menu_select_instance || return 0
  msg '  1) 关闭 QUIC Proxy Mode [默认 / 推荐兼容]'
  msg '  2) 启用 QUIC Proxy Mode [开放同号 UDP]'
  read_tty choice "$(t '请选择 [1-2]: ' 'Choose [1-2]: ')" || choice=""
  case "$choice" in
    1) SNELL_QUIC_PROXY=off ;;
    2) SNELL_QUIC_PROXY=on ;;
    *) warn '无效选择'; return 0 ;;
  esac
  SNELL_QUIC_CLI=1 YES=0 SNELL_ACTION=set-quic
  nobrand_menu_run nobrand_run_snell_action
}

snell_menu_service() {
  local choice=""
  snell_menu_select_instance || return 0
  msg '  1) 状态'
  msg '  2) 启动'
  msg '  3) 停止'
  msg '  4) 重启'
  read_tty choice "$(t '请选择 [1-4]: ' 'Choose [1-4]: ')" || choice=""
  case "$choice" in
    1) SNELL_ACTION=status ;;
    2) SNELL_ACTION=start ;;
    3) SNELL_ACTION=stop ;;
    4) SNELL_ACTION=restart ;;
    *) warn '无效选择'; return 0 ;;
  esac
  nobrand_menu_run nobrand_run_snell_action
}

snell_menu_loop() {
  local choice="" confirm=""
  trap - ERR
  while true; do
    msg ''
    msg '========== Snell =========='
    msg '  1) 安装 Snell v5 [推荐]'
    msg '  2) 安装 Snell v4 [兼容]'
    msg '  3) 查看 Snell 节点'
    msg '  4) QUIC 设置'
    msg '  5) 修改 Display Endpoint'
    msg '  6) 服务管理'
    msg '  7) 升级官方 runtime'
    msg '  8) Doctor'
    msg '  9) 删除节点'
    msg '  0) 返回'
    read_tty choice "$(t '请选择 [0-9]: ' 'Choose [0-9]: ')" || choice=""
    case "$choice" in
      1) snell_menu_install_version 5 ;;
      2) snell_menu_install_version 4 ;;
      3) SNELL_NAME=""; SNELL_ACTION=show; nobrand_menu_run nobrand_run_snell_action ;;
      4) snell_menu_set_quic ;;
      5)
        snell_menu_select_instance || continue
        ADVERTISE_CLI=0 ADVERTISE_AUTO_REQUESTED=0 YES=0 SNELL_ACTION=set-endpoint
        nobrand_menu_run nobrand_run_snell_action
        ;;
      6) snell_menu_service ;;
      7)
        msg '升级版本: 1) v5  2) v4'
        read_tty confirm '请选择 [1-2]: ' || confirm=""
        case "$confirm" in 1) SNELL_VERSION=5 ;; 2) SNELL_VERSION=4 ;; *) warn '无效选择'; continue ;; esac
        SNELL_NAME="" SNELL_ACTION=upgrade
        nobrand_menu_run nobrand_run_snell_action
        ;;
      8) SNELL_ACTION=doctor; nobrand_menu_run nobrand_run_snell_action ;;
      9)
        snell_menu_select_instance || continue
        read_tty confirm "确认删除 ${SNELL_NAME}？输入 yes: " || confirm=""
        [ "$confirm" = yes ] || { warn '已取消'; continue; }
        SNELL_ACTION=remove
        nobrand_menu_run nobrand_run_snell_action
        ;;
      0) return 0 ;;
      *) warn '无效选择' ;;
    esac
    menu_pause
  done
}

hysteria2_menu_loop() {
  local choice="" confirm=""
  trap - ERR
  while true; do
    msg ''
    msg '========== Hysteria2 / Xray-core =========='
    msg '  1) 安装 / 重新部署'
    msg '  2) 查看节点'
    msg '  3) 修改 Display Endpoint'
    msg '  4) 状态'
    msg '  5) 启动'
    msg '  6) 停止'
    msg '  7) 重启'
    msg '  8) 升级 NoBrand 独立 Xray-core'
    msg '  9) Doctor'
    msg ' 10) 删除 Hysteria2'
    msg '  0) 返回'
    read_tty choice "$(t '请选择 [0-10]: ' 'Choose [0-10]: ')" || choice=""
    case "$choice" in
      1)
        PORT="" PORT_CLI=0 HY2_SNI="" ADVERTISE_HOST="" ADVERTISE_PORT=""
        ADVERTISE_CLI=0 ADVERTISE_AUTO_REQUESTED=0 YES=0 HY2_ACTION=install
        nobrand_menu_run nobrand_run_hy2_action
        ;;
      2) HY2_ACTION=show; nobrand_menu_run nobrand_run_hy2_action ;;
      3)
        ADVERTISE_CLI=0 ADVERTISE_AUTO_REQUESTED=0 YES=0 HY2_ACTION=set-endpoint
        nobrand_menu_run nobrand_run_hy2_action
        ;;
      4) HY2_ACTION=status; nobrand_menu_run nobrand_run_hy2_action ;;
      5) HY2_ACTION=start; nobrand_menu_run nobrand_run_hy2_action ;;
      6) HY2_ACTION=stop; nobrand_menu_run nobrand_run_hy2_action ;;
      7) HY2_ACTION=restart; nobrand_menu_run nobrand_run_hy2_action ;;
      8) HY2_ACTION=upgrade; nobrand_menu_run nobrand_run_hy2_action ;;
      9) HY2_ACTION=doctor; nobrand_menu_run nobrand_run_hy2_action ;;
      10)
        read_tty confirm '确认只删除 NoBrand Hysteria2？输入 yes: ' || confirm=""
        [ "$confirm" = yes ] || { warn '已取消'; continue; }
        HY2_ACTION=remove
        nobrand_menu_run nobrand_run_hy2_action
        ;;
      0) return 0 ;;
      *) warn '无效选择' ;;
    esac
    menu_pause
  done
}

vless_sudoku_menu_loop() {
  local choice="" confirm=""
  trap - ERR
  while true; do
    msg ''
    msg '========== Plain VLESS + FinalMask + Sudoku / TCP =========='
    msg 'VLESS Encryption: NOT USED'
    msg '  1) 安装 / 重新配置'
    msg '  2) 查看节点'
    msg '  3) 修改客户端展示入口'
    msg '  4) 状态'
    msg '  5) 启动'
    msg '  6) 停止'
    msg '  7) 重启'
    msg '  8) Doctor'
    msg '  9) Smoke / 配置验证'
    msg ' 10) 升级共享 Xray runtime'
    msg ' 11) 删除'
    msg '  0) 返回'
    read_tty choice "$(t '请选择 [0-11]: ' 'Choose [0-11]: ')" || choice=""
    case "$choice" in
      1)
        PORT="" PORT_CLI=0 VLESS_SUDOKU_UUID="" VLESS_SUDOKU_PASSWORD=""
        ADVERTISE_HOST="" ADVERTISE_PORT="" ADVERTISE_CLI=0 ADVERTISE_AUTO_REQUESTED=0
        YES=0 VLESS_SUDOKU_ACTION=install
        nobrand_menu_run nobrand_run_vless_sudoku_action
        ;;
      2) VLESS_SUDOKU_ACTION=show; nobrand_menu_run nobrand_run_vless_sudoku_action ;;
      3)
        ADVERTISE_HOST="" ADVERTISE_PORT="" ADVERTISE_CLI=0 ADVERTISE_AUTO_REQUESTED=0
        YES=0 VLESS_SUDOKU_ACTION=set-endpoint
        nobrand_menu_run nobrand_run_vless_sudoku_action
        ;;
      4) VLESS_SUDOKU_ACTION=status; nobrand_menu_run nobrand_run_vless_sudoku_action ;;
      5) VLESS_SUDOKU_ACTION=start; nobrand_menu_run nobrand_run_vless_sudoku_action ;;
      6) VLESS_SUDOKU_ACTION=stop; nobrand_menu_run nobrand_run_vless_sudoku_action ;;
      7) VLESS_SUDOKU_ACTION=restart; nobrand_menu_run nobrand_run_vless_sudoku_action ;;
      8) VLESS_SUDOKU_ACTION=doctor; nobrand_menu_run nobrand_run_vless_sudoku_action ;;
      9) VLESS_SUDOKU_ACTION=smoke; nobrand_menu_run nobrand_run_vless_sudoku_action ;;
      10) VLESS_SUDOKU_ACTION=upgrade; nobrand_menu_run nobrand_run_vless_sudoku_action ;;
      11)
        read_tty confirm '确认只删除 NoBrand VLESS Sudoku？输入 yes: ' || confirm=""
        [ "$confirm" = yes ] || { warn '已取消'; continue; }
        VLESS_SUDOKU_ACTION=remove
        nobrand_menu_run nobrand_run_vless_sudoku_action
        ;;
      0) return 0 ;;
      *) warn '无效选择' ;;
    esac
    menu_pause
  done
}

nobrand_backup_menu_loop() {
  local choice="" path=""
  trap - ERR
  while true; do
    msg ''
    msg '========== NoBrand 备份 / 恢复 =========='
    msg '  1) 创建备份'
    msg '  2) 列出备份'
    msg '  3) 从备份恢复'
    msg '  0) 返回'
    read_tty choice "$(t '请选择 [0-3]: ' 'Choose [0-3]: ')" || choice=""
    case "$choice" in
      1)
        NOBRAND_BACKUP_ACTION=create NOBRAND_BACKUP_PATH=""
        nobrand_menu_run nobrand_backup_action
        ;;
      2)
        NOBRAND_BACKUP_ACTION=list NOBRAND_BACKUP_PATH=""
        nobrand_menu_run nobrand_backup_action
        ;;
      3)
        read_tty path "$(t '备份文件绝对路径: ' 'Absolute backup path: ')" || path=""
        [ -n "$path" ] || { warn '备份路径不能为空'; continue; }
        NOBRAND_BACKUP_ACTION=restore NOBRAND_BACKUP_PATH="$path"
        nobrand_menu_run nobrand_backup_action
        ;;
      0) return 0 ;;
      *) warn '无效选择' ;;
    esac
    menu_pause
  done
}

nobrand_menu_loop() {
  local choice=""
  MENU_MODE=1
  trap - ERR
  while true; do
    nobrand_print_banner
    msg ''
    msg '  1) Mieru'
    msg '  2) Snell v4 / v5'
    msg '  3) Hysteria2 (Xray-core)'
    msg '  4) VLESS + FinalMask + Sudoku (TCP)'
    msg '  5) 查看全部节点'
    msg '  6) 综合状态'
    msg '  7) Doctor'
    msg '  8) 性能 / BBR / FQ（Mieru 公共网络工具）'
    msg '  9) 备份 / 恢复'
    msg ' 10) 帮助 / CLI'
    msg ' 11) 卸载 NoBrand Snell/HY2/VLESS/Common（保留 Mieru）'
    msg '  0) 退出'
    read_tty choice "$(t '请选择 [0-11]: ' 'Choose [0-11]: ')" || choice=""
    case "$choice" in
      1) menu_loop ;;
      2) snell_menu_loop ;;
      3) hysteria2_menu_loop ;;
      4) vless_sudoku_menu_loop ;;
      5) NOBRAND_PROTOCOL_FILTER=""; nobrand_menu_run nobrand_nodes; menu_pause ;;
      6) nobrand_menu_run nobrand_status; menu_pause ;;
      7) nobrand_menu_run nobrand_doctor; menu_pause ;;
      8) nobrand_menu_run do_perf; menu_pause ;;
      9) nobrand_backup_menu_loop ;;
      10) nobrand_usage; menu_pause ;;
      11) YES=0; nobrand_menu_run nobrand_uninstall; menu_pause ;;
      0) return 0 ;;
      *) warn '无效选择' ;;
    esac
  done
}

main() {
  if [ "${DRY_RUN:-0}" -ne 1 ] \
     && [ "$(id -u 2>/dev/null || echo 1)" -eq 0 ]; then
    ensure_manager_state_layout
  fi
  if [ "${NOBRAND_ENTRY:-0}" -eq 1 ] \
     && [ "${DRY_RUN:-0}" -ne 1 ] \
     && [ "$(id -u 2>/dev/null || echo 1)" -eq 0 ]; then
    case "${ACTION:-menu}" in
      nobrand-version|nobrand-help) ;;
      *) snell_migrate_removed_v6 || die 'Snell v6 removal migration did not complete safely' ;;
    esac
  fi
  if [ -z "$ACTION" ]; then
    if [ "${NOBRAND_ENTRY:-0}" -eq 1 ]; then
      nobrand_menu_loop
    else
      menu_loop
    fi
    exit 0
  fi
  if [ "$ACTION" != "menu" ] && [[ "$ACTION" != nobrand-* ]]; then
    print_banner
  fi
  if dry_run_should_preview "$ACTION"; then
    dry_run_action_preview "$ACTION"
    return 0
  fi
  if [ "${DRY_RUN:-0}" -ne 1 ] \
     && [ "$(id -u 2>/dev/null || echo 1)" -eq 0 ] \
     && mita_installed; then
    repair_mita_binary_paths 2>/dev/null || true
  fi
  case "$ACTION" in
    install) do_install ;;
    reconfigure) do_reconfigure ;;
    upgrade) do_upgrade ;;
    uninstall) do_uninstall ;;
    status) do_status ;;
    client-config|show) do_client_config ;;
    mtu-config) do_mtu_config ;;
    start) do_start ;;
    stop) do_stop ;;
    restart) do_restart ;;
    user-list) do_user_list ;;
    user-add) do_user_add ;;
    user-del) do_user_del ;;
    user-show) do_user_show ;;
    user-manage) do_user_manage ;;
    user-set-endpoint) do_user_set_endpoint ;;
    user-set-quota) do_user_set_quota ;;
    user-set-expire) do_user_set_expire ;;
    user-enable) do_user_enable ;;
    user-disable) do_user_disable ;;
    user-scan) do_user_scan ;;
    user-quota-reset)
      if [ "${YES:-0}" -eq 1 ]; then
        do_user_quota_reset force
      else
        do_user_quota_reset
      fi
      ;;
    user-set-rate) do_user_set_rate ;;
    rate-status) do_rate_status ;;
    rate-restore) do_rate_restore ;;
    user-usage) do_user_usage ;;
    user-export-clients) do_user_export_clients ;;
    user-backup) do_user_backup ;;
    user-restore) do_user_restore ;;
    user-export) do_user_export ;;
    user-import) do_user_import ;;
    doctor) do_doctor ;;
    perf) do_perf ;;
    profile-config) do_profile_config ;;
    client-modes-config) do_tuning_config client-modes ;;
    traffic-config) do_tuning_config traffic ;;
    low-entropy-config) do_tuning_config low-entropy ;;
    bbr-config) do_bbr_config ;;
    version-channel) do_version_channel_config ;;
    nobrand-status) nobrand_status ;;
    nobrand-nodes) nobrand_nodes ;;
    nobrand-doctor) nobrand_doctor ;;
    nobrand-backup) nobrand_backup_action ;;
    nobrand-uninstall) nobrand_uninstall ;;
    nobrand-network) do_perf ;;
    nobrand-snell) nobrand_run_snell_action ;;
    nobrand-hy2) nobrand_run_hy2_action ;;
    nobrand-vless-sudoku) nobrand_run_vless_sudoku_action ;;
    nobrand-mieru-menu) menu_loop ;;
    nobrand-help) nobrand_usage ;;
    nobrand-version) nobrand_version ;;
    help) usage; exit 0 ;;
    menu)
      menu_loop
      ;;
    *) usage; exit 1 ;;
  esac
}

# 允许被 source 做单测（设置 MITA_SOURCE_ONLY=1）
if [ "${MITA_SOURCE_ONLY:-0}" != "1" ]; then
  main
fi
