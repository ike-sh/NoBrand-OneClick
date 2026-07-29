#!/usr/bin/env bash
# mieru / mita 服务端一键安装脚本
# 作者: ike · https://github.com/ike-sh/mieru-OneClick
# 基于 https://github.com/enfein/mieru
set -euo pipefail

SCRIPT_VERSION="1.9.2"
SCRIPT_AUTHOR="ike"
SCRIPT_REPO="ike-sh/mieru-OneClick"
UPSTREAM_REPO="enfein/mieru"
GITHUB_API="https://api.github.com/repos/${UPSTREAM_REPO}/releases/latest"
GITHUB_DL="https://github.com/${UPSTREAM_REPO}/releases/download"
MITA_BIN="/usr/local/bin/mita"
MITA_REAL_BIN="/usr/local/bin/mita-real"
MITA_MARKER="/etc/mita/.mieru-oneclick"
MITA_STATE="/etc/mita/install-state.env"
MITA_USERS_STATE="${MITA_USERS_STATE:-/etc/mita/users.json}"
MITA_USERS_LOCK="${MITA_USERS_LOCK:-/etc/mita/users.lock}"
MITA_USERS_CRON="${MITA_USERS_CRON:-/etc/cron.d/mita-users}"
MITA_USERS_TIMER="/etc/systemd/system/mita-users-scan.timer"
MITA_USERS_SERVICE="/etc/systemd/system/mita-users-scan.service"
MITA_USERS_LOG="${MITA_USERS_LOG:-/var/log/mita-users.log}"
MITA_USERS_BACKUP_DIR="${MITA_USERS_BACKUP_DIR:-/etc/mita/backups}"
MITA_ADMIN_LOCK="${MITA_ADMIN_LOCK:-/etc/mita/admin.lock}"
MITA_CLIENT_EXPORT_DIR="${MITA_CLIENT_EXPORT_DIR:-/root/mieru-clients}"
MITA_LOGROTATE_CONF="${MITA_LOGROTATE_CONF:-/etc/logrotate.d/mita-oneclick}"
# calendar 重置：days=只改窗口天数；password=微扰密码(默认，更可能清零)；metrics=清 metrics.pb(影响全部用户)
QUOTA_RESET_METHOD="${QUOTA_RESET_METHOD:-password}"
INSTALL_SCRIPT_PATH="/usr/local/bin/install-mita"
MITA_MENU_PATH="/usr/local/bin/mita-menu"
MITA_PROFILE_D="/etc/profile.d/mita-oneclick.sh"
SCRIPT_REPO_RAW="https://raw.githubusercontent.com/ike-sh/mieru-OneClick/v${SCRIPT_VERSION}/install-mita.sh"
OPENRC_SVC="/etc/init.d/mita"
SYSTEMD_SVC="/etc/systemd/system/mita.service"
# 多用户端口池：相对主端口偏移，或 IP 尾号段内扫描
USER_PORT_POOL_START="${USER_PORT_POOL_START:-}"
USER_PORT_POOL_END="${USER_PORT_POOL_END:-}"

ACTION=""
MENU_MODE=0
MENU_SCRIPTS_READY=0
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
USERNAME=""
PASSWORD=""
OP_USER=""
MTU=1400
MULTIPLEXING="MULTIPLEXING_LOW"
TRAFFIC_PATTERN="conservative"
TRAFFIC_SEED=""
TRAFFIC_CLI=0
PORT_CLI=0
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
# tc 限速：出口网卡（空=自动默认路由）；总带宽 ceil 默认 10gbit
TC_IFACE="${TC_IFACE:-}"
TC_ROOT_RATE="${TC_ROOT_RATE:-10gbit}"
TC_HANDLE="${TC_HANDLE:-1}"
TC_INGRESS_HANDLE="${TC_INGRESS_HANDLE:-ffff:}"
# 0=单用户兼容路径；1=使用 users.json 多用户（一用户一口）
MULTI_USER_MODE=0

if [ -z "${BASH_VERSION:-}" ]; then
  echo "[错误] 请使用 bash 运行此脚本" >&2
  if [ -f /etc/alpine-release ]; then
    echo "Alpine 默认无 bash，请先安装后执行（root 无需 sudo）：" >&2
    echo "  apk add --no-cache bash curl" >&2
    echo "  curl -fsSL https://raw.githubusercontent.com/ike-sh/mieru-OneClick/main/install-mita.sh | bash" >&2
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
  --upgrade           升级 mita 至最新版
  --uninstall         卸载 mita
  --status            查看运行状态与配置摘要
  --client-config     查看节点链接并生成客户端 JSON（同 --show）
  --start             启动服务（守护进程 + 代理）
  --stop              停止服务
  --restart           重启服务（守护进程异常时一键恢复）
  --users / user-list 列出代理用户（端口独占）
  --user-add          添加用户（可配合 --user/--password/--port/--package 等）
  --user-del NAME     删除用户并释放端口
  --user-show NAME    查看指定用户节点配置
  --user-set-quota    设置套餐：--user NAME --quota-mb N --quota-days D
  --user-set-expire   设置到期：--user NAME --expire YYYY-MM-DD|+Nd|0
  --user-enable NAME  启用用户
  --user-disable NAME 停用用户（从 mita 配置移除，端口保留）
  --user-scan         扫描到期/日历月配额重置（供 cron/timer）
  --user-quota-reset  手动触发日历月配额重置（可加 -y 强制）
  --user-set-rate     设置带宽：--user NAME --bandwidth Mbps（0=不限，双向）
  --rate-status       查看 tc 限速状态
  --user-usage        查看 mita 用户流量/配额用量（mita get users/quotas）
  --user-export-clients [DIR]  批量导出各用户客户端 JSON/链接
  --user-backup       备份 users.json
  --user-restore FILE 从备份恢复用户状态并 apply + tc
  --user-export [FILE] 导出用户状态 JSON（默认 stdout）
  --user-import FILE  导入用户状态（覆盖前自动备份）
  --doctor / verify   一键验收：服务/用户/配额/tc/定时任务

安装选项：
  --yes, -y           跳过确认
  --port PORT         监听端口（1025-65535）；多用户时作为主用户端口
  --port-range RANGE  监听端口段，如 9000-9010（单用户模式）
  --protocol TCP|UDP|BOTH  传输协议（默认 TCP；BOTH 时 UDP 使用 PORT+1）
  --traffic-pattern LV  流量伪装/抗 DPI：off|conservative|aggressive（默认 conservative）
  --user NAME         代理用户名（安装主用户 / user-add）
  --password PASS     代理密码
  --package NAME      套餐：unlimited|trial|standard|custom（user-add）
  --quota-mb N        流量配额 MB（0=不限；写入 mita quotas）
  --quota-days D      配额滚动窗口天数（默认 30；rolling 模式）
  --quota-mode MODE   rolling|calendar（calendar=每月1日重置计数）
  --expire WHEN       到期：YYYY-MM-DD 或 +30d 或 0/never
  --bandwidth Mbps    带宽限制 Mbps（0=不限；出口+入口按端口 tc）
  --op-user USER      加入 mita 用户组的 Linux 用户
  --enable-bbr        安装后启用 TCP BBR
  --lang en           使用英文提示

其它：
  --dry-run           仅预览，不执行
  --help, -h          显示帮助
  --version           显示版本

快捷命令（子命令不区分大小写）：
  install-mita                    打开菜单
  install-mita status             查看状态
  install-mita reconfigure        重新配置
  install-mita show               查看节点链接
  install-mita users              用户管理列表
  install-mita user-add --user a --password p
  install-mita user-del a
  install-mita restart            重启服务（start/stop 同理）
  mita-menu                       同上（安装后可用）
  登录 shell 下输入 mita          管理子命令不区分大小写；mita start/stop/restart 已走干净启停（含 systemd/openrc）
  其余如 mita run/apply/reload     仍透传官方二进制

一键安装（交互式，Debian/Ubuntu/CentOS 等）：
  curl -fsSL https://raw.githubusercontent.com/ike-sh/mieru-OneClick/main/install-mita.sh | sudo bash

Alpine Linux（无 sudo，需先装 bash）：
  apk add --no-cache bash curl
  curl -fsSL https://raw.githubusercontent.com/ike-sh/mieru-OneClick/main/install-mita.sh | bash

Alpine 一行命令：
  apk add --no-cache bash curl && curl -fsSL https://raw.githubusercontent.com/ike-sh/mieru-OneClick/main/install-mita.sh | bash

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
  t "作者: ${SCRIPT_AUTHOR} · https://github.com/${SCRIPT_REPO}" \
    "Author: ${SCRIPT_AUTHOR} · https://github.com/${SCRIPT_REPO}"
}

while [ $# -gt 0 ]; do
  _arg_lc="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  case "$_arg_lc" in
    --install) ACTION=install ;;
    --reconfigure) ACTION=reconfigure ;;
    --upgrade) ACTION=upgrade ;;
    --uninstall) ACTION=uninstall ;;
    --status) ACTION=status ;;
    --client-config|--show) ACTION=client-config ;;
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
    --doctor|--verify|doctor|verify) ACTION=doctor ;;
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
    install|upgrade|uninstall|status|reconfigure|client-config|show|menu|start|stop|restart|配置|节点|users|user-list|user-add|user-del|user-delete|user-show|user-manage|user-set-quota|user-set-expire|user-enable|user-disable|user-scan|user-quota-reset|user-set-rate|user-set-bandwidth|rate-status|rate-restore|tc-status|tc-restore|user-backup|user-restore|user-export|user-import|user-usage|usage|user-export-clients|doctor|verify|help)
      [ -z "$ACTION" ] && ACTION="$_arg_lc"
      [ "$_arg_lc" = show ] && ACTION=client-config
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
      [ -n "$PORT_RANGE" ] || die "--port-range 需要端口段"
      shift
      ;;
    --protocol)
      PROTOCOL="${2:-}"
      PROTOCOL_CLI=1
      shift
      ;;
    --traffic-pattern|--traffic)
      TRAFFIC_PATTERN="${2:-}"
      TRAFFIC_CLI=1
      shift
      ;;
    --user)
      USERNAME="${2:-}"
      shift
      ;;
    --password)
      PASSWORD="${2:-}"
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
    --version) echo "mieru-OneClick install-mita.sh ${SCRIPT_VERSION} by ${SCRIPT_AUTHOR}"; exit 0 ;;
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
    msg "[dry-run] $*"
  else
    "$@"
  fi
}

# BusyBox mktemp（Alpine）要求 XXXXXX 在模板末尾；GNU 允许中间占位
mktemp_file() {
  local suffix="${1:-}"
  local f
  f="$(mktemp /tmp/mita.XXXXXX 2>/dev/null)" || f="/tmp/mita_$$_${RANDOM}"
  [ -n "$suffix" ] || { printf '%s' "$f"; return; }
  local out="${f}${suffix}"
  if [ "$f" != "$out" ]; then
    mv "$f" "$out" 2>/dev/null || { : >"$out"; rm -f "$f"; }
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
  STAGE="权限检查"
  if [ "$(id -u)" -eq 0 ]; then
    return 0
  fi
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
  case "$PROTOCOL" in
    BOTH)
      if [ -n "$PORT" ]; then
        if [ "$LANG_ZH" -eq 1 ]; then
          printf '%s' "TCP(${PORT}) + UDP($((PORT + 1)))"
        else
          printf '%s' "TCP(${PORT}) + UDP($((PORT + 1)))"
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
  local proto="$1"
  if [ -n "$PORT" ]; then
    if [ "$PROTOCOL" = "BOTH" ] && [ "$proto" = "UDP" ]; then
      printf '%s' "$((PORT + 1))"
    else
      printf '%s' "$PORT"
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

# 收紧敏感文件权限；/etc/mita 必须对 mita 守护进程可写（server.conf.pb）
# 优先 mita:mita 0750；无 mita 用户时 root:mita 0770
harden_mita_permissions() {
  run mkdir -p /etc/mita "$MITA_USERS_BACKUP_DIR" 2>/dev/null || true
  if _has_user mita 2>/dev/null || id mita >/dev/null 2>&1; then
    run chown mita:mita /etc/mita 2>/dev/null || true
    run chmod 0750 /etc/mita 2>/dev/null || true
  elif _has_group mita 2>/dev/null || getent group mita >/dev/null 2>&1; then
    run chown root:mita /etc/mita 2>/dev/null || true
    run chmod 0770 /etc/mita 2>/dev/null || true
  else
    run chmod 0750 /etc/mita 2>/dev/null || true
  fi
  # 敏感状态文件：root 读写即可（管理脚本以 root 运行）
  if [ -f "$MITA_STATE" ]; then
    run chown root:root "$MITA_STATE" 2>/dev/null || true
    run chmod 0600 "$MITA_STATE" 2>/dev/null || true
  fi
  if [ -f "$MITA_USERS_STATE" ]; then
    run chown root:root "$MITA_USERS_STATE" 2>/dev/null || true
    run chmod 0600 "$MITA_USERS_STATE" 2>/dev/null || true
  fi
  [ -d "$MITA_USERS_BACKUP_DIR" ] && run chmod 0700 "$MITA_USERS_BACKUP_DIR" 2>/dev/null || true
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
EOF
  chmod 0644 "$MITA_LOGROTATE_CONF" 2>/dev/null || true
}

# 管理写操作互斥锁（fd 8，引用计数可重入）
admin_lock_acquire() {
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
  warn "$(t '获取管理锁超时，继续执行（可能并发）' 'Admin lock timeout; continuing (may race)')"
  return 0
}

admin_lock_release() {
  [ "${_ADMIN_LOCK_HELD:-0}" -gt 0 ] || return 0
  _ADMIN_LOCK_HELD=$((_ADMIN_LOCK_HELD - 1))
  if [ "$_ADMIN_LOCK_HELD" -le 0 ]; then
    _ADMIN_LOCK_HELD=0
    flock -u 8 2>/dev/null || true
  fi
}

save_install_state() {
  STAGE="保存安装状态"
  run mkdir -p /etc/mita
  {
    _state_kv PORT "$PORT"
    _state_kv PORT_RANGE "$PORT_RANGE"
    _state_kv PROTOCOL "$PROTOCOL"
    _state_kv USERNAME "$USERNAME"
    _state_kv PASSWORD "$PASSWORD"
    _state_kv TRAFFIC_PATTERN "$TRAFFIC_PATTERN"
    _state_kv TRAFFIC_SEED "$TRAFFIC_SEED"
    _state_kv INSTALL_SCRIPT "$INSTALL_SCRIPT_PATH"
    printf 'INSTALL_METHOD=oneclick\n'
  } >"$MITA_STATE"
  harden_mita_permissions
  run touch "$MITA_MARKER"
}

mark_oneclick_install() {
  run mkdir -p /etc/mita
  run touch "$MITA_MARKER"
}

installed_by_oneclick() {
  [ -f "$MITA_MARKER" ]
}

load_install_state() {
  PORT=""
  PORT_RANGE=""
  PROTOCOL="TCP"
  [ -f "$MITA_STATE" ] || return 0
  local _cli_tp="$TRAFFIC_PATTERN"
  # shellcheck disable=SC1090
  source "$MITA_STATE" 2>/dev/null || true
  # 命令行显式指定 --traffic-pattern 时优先，不被已保存状态覆盖
  [ "${TRAFFIC_CLI:-0}" -eq 1 ] && TRAFFIC_PATTERN="$_cli_tp"
}

install_self_script() {
  STAGE="安装管理脚本"
  local main_url="https://raw.githubusercontent.com/ike-sh/mieru-OneClick/main/install-mita.sh"
  if curl -fsSL --connect-timeout 15 --max-time 60 "$main_url" -o "$INSTALL_SCRIPT_PATH" 2>/dev/null; then
    run chmod 0755 "$INSTALL_SCRIPT_PATH"
  elif [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
    local src_real dest_real
    src_real="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || realpath "${BASH_SOURCE[0]}" 2>/dev/null || printf '%s' "${BASH_SOURCE[0]}")"
    dest_real="$(readlink -f "$INSTALL_SCRIPT_PATH" 2>/dev/null || realpath "$INSTALL_SCRIPT_PATH" 2>/dev/null || printf '%s' "$INSTALL_SCRIPT_PATH")"
    if [ "$src_real" != "$dest_real" ]; then
      run install -m 0755 "${BASH_SOURCE[0]}" "$INSTALL_SCRIPT_PATH"
    fi
  else
    run curl -fsSL "$SCRIPT_REPO_RAW" -o "$INSTALL_SCRIPT_PATH"
    run chmod 0755 "$INSTALL_SCRIPT_PATH"
  fi
  install_mita_wrapper_force
  migrate_mita_binary_layout
  install_mita_shortcuts
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
  echo "  curl -fsSL https://raw.githubusercontent.com/ike-sh/mieru-OneClick/main/install-mita.sh | bash" >&2
  exit 1
fi

  if [ $# -gt 0 ] && [ -x "$INSTALL_MITA" ]; then
    cmd="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
    case "$cmd" in
      menu|install|upgrade|uninstall|status|reconfigure|client-config|show|start|stop|restart|配置|节点|help|\
      users|user-list|user-add|user-del|user-delete|user-show|user-manage|\
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
  echo "[错误] 未找到 mita 二进制；请重新运行安装脚本并选 3) 升级 自动重装：" >&2
  echo "  curl -fsSL https://raw.githubusercontent.com/ike-sh/mieru-OneClick/main/install-mita.sh | sudo bash -s -- upgrade -y" >&2
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
  [ -n "$ver" ] || ver="$(query_latest_version 2>/dev/null || true)"
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
  run dpkg --configure -a 2>/dev/null || true
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
      recover_deb_mita || warn "$(t 'mita 二进制自动修复未成功，请重新运行脚本并选 3) 升级 重新安装' \
        'auto-repair failed; re-run the script and choose 3) Upgrade to reinstall')"
    else
      warn "$(t 'mita 二进制不可用，请重新运行脚本并选 3) 升级 重新安装' \
        'mita binary unavailable; re-run the script and choose 3) Upgrade to reinstall')"
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
  install|upgrade|uninstall|status|reconfigure|client-config|show|menu|start|stop|restart|配置|节点|\
  users|user-list|user-add|user-del|user-delete|user-show|user-manage|\
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
  cat >"$MITA_PROFILE_D" <<'EOF'
# mieru-OneClick：登录 shell 下 mita 管理子命令不区分大小写
mita() {
  local im="/usr/local/bin/install-mita"
  local real="" c
  for c in /usr/local/bin/mita-real /usr/bin/mita; do
    if [ -x "$c" ] && [ "$(head -c 4 "$c" 2>/dev/null || true)" = $'\x7fELF' ]; then
      real="$c"
      break
    fi
  done
  if [ ! -x "$im" ]; then
    [ -n "$real" ] && command "$real" "$@"
    return $?
  fi
  if [ $# -eq 0 ]; then
    "$im"
    return $?
  fi
  local cmd
  cmd="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  case "$cmd" in
    menu|install|upgrade|uninstall|status|reconfigure|client-config|show|start|stop|restart|配置|节点|help|\
    users|user-list|user-add|user-del|user-delete|user-show|user-manage|\
    user-set-quota|user-set-expire|user-enable|user-disable|user-scan|user-quota-reset|\
    user-set-rate|user-set-bandwidth|rate-status|rate-restore|tc-status|tc-restore|\
    user-usage|usage|user-export-clients|user-backup|user-restore|user-export|user-import|\
    doctor|verify)
      shift
      "$im" "$cmd" "$@"
      ;;
    *)
      [ -n "$real" ] && command "$real" "$@"
      ;;
  esac
}
EOF
  run chmod 0644 "$MITA_PROFILE_D"
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
  local body tag
  body="$(curl -fsSL --connect-timeout 15 --max-time 30 "$GITHUB_API")" \
    || die "$(t '无法从 GitHub 获取最新版本' 'Failed to fetch latest release from GitHub')"
  tag="$(printf '%s' "$body" | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
  tag="${tag#v}"
  [ -n "$tag" ] || die "$(t '解析版本号失败' 'Failed to parse release version')"
  printf '%s' "$tag"
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
    warn "$(t "无法下载校验文件，已跳过: ${sha_url}" "Checksum file unavailable, skipped: ${sha_url}")"
    rm -f "$sha_file"
    return 0
  fi
  expected="$(awk '{print $1}' "$sha_file" | head -n1)"
  [ -n "$expected" ] || die "$(t '校验文件格式无效' 'Invalid checksum file')"
  if command -v sha256sum >/dev/null 2>&1; then
    actual="$(sha256sum "$file" | awk '{print $1}')"
  elif command -v shasum >/dev/null 2>&1; then
    actual="$(shasum -a 256 "$file" | awk '{print $1}')"
  else
    warn "$(t '未找到 sha256sum/shasum，跳过完整性校验' 'sha256sum/shasum not found, skipping verify')"
    rm -f "$sha_file"
    return 0
  fi
  rm -f "$sha_file"
  [ "$expected" = "$actual" ] || die "$(t '安装包 SHA256 校验失败' 'Package SHA256 verification failed')"
  t '安装包 SHA256 校验通过' 'Package SHA256 verified'
}

install_alpine_deps() {
  STAGE="安装 Alpine 依赖"
  run apk add --no-cache bash curl tar ca-certificates iptables
  if [ "$(service_manager)" = openrc ]; then
    run apk add --no-cache openrc 2>/dev/null || true
  fi
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
  STAGE="安装软件包"
  case "$pm" in
    deb)
      run dpkg -i "$path" || run apt-get install -f -y
      mark_oneclick_install
      ;;
    rpm)
      run rpm -Uvh --force "$path"
      mark_oneclick_install
      ;;
    alpine)
      install_alpine_deps
      ensure_mita_account
      extract_mita_tarball "$path"
      install_mita_service
      ;;
    *) die "$(t '未知包管理器' 'Unknown package manager')" ;;
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

# 取本机主用 IPv4：优先默认路由出口地址（ip route get 不发包，仅查路由表，
# 内网无外网也可用），回退首个非回环地址。
detect_local_ip() {
  local ip=""
  if command -v ip >/dev/null 2>&1; then
    ip="$(ip route get 1.1.1.1 2>/dev/null | sed -n 's/.*src \([0-9.]*\).*/\1/p' | head -n1)" || true
  fi
  if [ -z "$ip" ]; then
    ip="$(hostname -I 2>/dev/null | tr ' ' '\n' \
      | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | grep -vE '^127\.' | head -n1)" || true
  fi
  printf '%s' "$ip"
}

# 由本机 IP 末位八位组推导端口基数 N*100（要求 N=1-254 且基数≥1025）；不可用返回非0
derive_port_base() {
  local ip n base
  ip="$(detect_local_ip)"
  n="${ip##*.}"
  [[ "$n" =~ ^[0-9]+$ ]] || return 1
  [ "$n" -ge 1 ] && [ "$n" -le 254 ] || return 1
  base=$((n * 100))
  [ "$base" -ge 1025 ] || return 1   # 小尾号兜底：基数落入特权端口段则放弃
  printf '%s' "$base"
}

# 在 IP 尾号端口段内随机取一个可用端口：xx01-xx99（xx00 留给 SSH）；不可用返回非0。
# BOTH 双协议时末两位上限取 98，避免 UDP=主端口+1 溢出到 xx00 或下一机器段。
derive_port_from_ip() {
  local base hi off
  base="$(derive_port_base)" || return 1
  hi=99
  [ "$PROTOCOL" = "BOTH" ] && hi=98
  off=$(( (RANDOM % hi) + 1 ))
  printf '%s' "$((base + off))"
}

valid_port() {
  local p="$1"
  [[ "$p" =~ ^[0-9]+$ ]] || return 1
  [ "$p" -ge 1025 ] && [ "$p" -le 65535 ]
}

valid_port_range() {
  [[ "$1" =~ ^[0-9]+-[0-9]+$ ]] || return 1
  local start end
  start="${1%-*}"
  end="${1#*-}"
  valid_port "$start" && valid_port "$end" && [ "$start" -le "$end" ]
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
  local pkg
  pkg="$(printf '%s' "${USER_PACKAGE:-}" | tr '[:upper:]' '[:lower:]')"
  case "$pkg" in
    ""|none)
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
      ;;
  esac
  [ -n "${USER_QUOTA_DAYS}" ] || USER_QUOTA_DAYS=30
  [ -n "${USER_QUOTA_MB}" ] || USER_QUOTA_MB=0
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
    python3 -c "import datetime;print((datetime.date.today()+datetime.timedelta(days=int('${days}'))).isoformat())" 2>/dev/null
    return 0
  fi
  if [[ "$raw" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
    printf '%s' "$raw"
    return 0
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
  run mkdir -p "$(dirname "$MITA_USERS_STATE")"
  printf '%s\n' '{"version":1,"users":[]}' >"$MITA_USERS_STATE"
  run chmod 0600 "$MITA_USERS_STATE" 2>/dev/null || true
}

users_state_exists() {
  [ -f "$MITA_USERS_STATE" ] && [ -s "$MITA_USERS_STATE" ]
}

users_count() {
  users_state_exists || { printf '0'; return 0; }
  command -v python3 >/dev/null 2>&1 || { printf '0'; return 0; }
  python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(len(d.get("users") or []))' \
    "$MITA_USERS_STATE" 2>/dev/null || printf '0'
}

# 在 flock 下执行 python -c（$1=代码）；环境变量传参
users_py_locked() {
  users_require_python
  run mkdir -p "$(dirname "$MITA_USERS_STATE")" "$(dirname "$MITA_USERS_LOCK")"
  local code="$1"
  if command -v flock >/dev/null 2>&1; then
    flock -w 30 "$MITA_USERS_LOCK" env MITA_USERS_STATE="$MITA_USERS_STATE" \
      _U_NAME="${_U_NAME-}" _U_PASS="${_U_PASS-}" _U_PORT="${_U_PORT-}" _U_PROTO="${_U_PROTO-}" \
      _U_QUOTA_MB="${_U_QUOTA_MB-}" _U_QUOTA_DAYS="${_U_QUOTA_DAYS-}" \
      _U_QUOTA_MODE="${_U_QUOTA_MODE-}" \
      _U_EXPIRE="${_U_EXPIRE-}" _U_PACKAGE="${_U_PACKAGE-}" _U_ENABLED="${_U_ENABLED-}" \
      _U_BW="${_U_BW-}" _U_PRIMARY="${_U_PRIMARY-}" \
      python3 -c "$code"
  else
    MITA_USERS_STATE="$MITA_USERS_STATE" \
      _U_NAME="${_U_NAME-}" _U_PASS="${_U_PASS-}" _U_PORT="${_U_PORT-}" _U_PROTO="${_U_PROTO-}" \
      _U_QUOTA_MB="${_U_QUOTA_MB-}" _U_QUOTA_DAYS="${_U_QUOTA_DAYS-}" \
      _U_QUOTA_MODE="${_U_QUOTA_MODE-}" \
      _U_EXPIRE="${_U_EXPIRE-}" _U_PACKAGE="${_U_PACKAGE-}" _U_ENABLED="${_U_ENABLED-}" \
      _U_BW="${_U_BW-}" _U_PRIMARY="${_U_PRIMARY-}" \
      python3 -c "$code"
  fi
}

normalize_quota_mode() {
  case "$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')" in
    calendar|cal|month|monthly|日历|月|自然月) printf 'calendar' ;;
    *) printf 'rolling' ;;
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
  # 协议经 argv 传入（shell PROTOCOL 未 export 时 os.environ 读不到）
  PROTOCOL="${PROTOCOL:-TCP}" python3 -c '
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
  local p="$1"
  if command -v ss >/dev/null 2>&1; then
    ss -lntu 2>/dev/null | grep -Eq "[:.]${p}\\s" && return 0
  fi
  if command -v netstat >/dev/null 2>&1; then
    netstat -lntu 2>/dev/null | grep -Eq "[:.]${p}\\s" && return 0
  fi
  return 1
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
    if [ "$PROTOCOL" = "BOTH" ]; then
      valid_port "$((prefer + 1))" || { die "$(t '双协议需要主端口 ≤65534' 'Dual protocol needs main port ≤65534')" || return 1; }
    fi
    if port_is_allocated "$prefer"; then
      warn "$(t "端口 ${prefer} 已被其它用户占用" "Port ${prefer} already allocated")"
      return 1
    fi
    if port_is_listening "$prefer"; then
      warn "$(t "端口 ${prefer} 已被系统占用" "Port ${prefer} is in use")"
      return 1
    fi
    if [ "$PROTOCOL" = "BOTH" ] && { port_is_allocated "$((prefer + 1))" || port_is_listening "$((prefer + 1))"; }; then
      warn "$(t "UDP 端口 $((prefer + 1)) 不可用" "UDP port $((prefer + 1)) unavailable")"
      return 1
    fi
    printf '%s' "$prefer"
    return 0
  fi
  users_port_pool_bounds
  p="$_pool_lo"
  while [ "$p" -le "$_pool_hi" ]; do
    if ! port_is_allocated "$p" && ! port_is_listening "$p"; then
      if [ "$PROTOCOL" != "BOTH" ] || { ! port_is_allocated "$((p + 1))" && ! port_is_listening "$((p + 1))"; }; then
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
  if users_state_exists; then
    local n
    n="$(users_count)"
    [ "${n:-0}" -gt 0 ] && return 0
  fi
  run mkdir -p "$(dirname "$MITA_USERS_STATE")"
  python3 -c '
import json, sys, time
path, name, pwd, port, proto = sys.argv[1:6]
port = int(port)
d = {"version": 1, "protocol": proto, "users": [{
    "name": name,
    "password": pwd,
    "port": port,
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
' "$MITA_USERS_STATE" "$USERNAME" "$PASSWORD" "$PORT" "${PROTOCOL:-TCP}"
  run chmod 0600 "$MITA_USERS_STATE" 2>/dev/null || true
  MULTI_USER_MODE=1
  install_users_scheduler 2>/dev/null || true
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
  users_require_python || return 1
  [ -n "$name" ] || { die "$(t '用户名不能为空' 'Username required')" || return 1; }
  [ -n "$password" ] || password="$(random_token)"
  apply_user_package_defaults
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
  local bw="${USER_BANDWIDTH_MBPS:-0}" qmode
  [[ "$bw" =~ ^[0-9]+$ ]] || bw=0
  qmode="$(normalize_quota_mode "${USER_QUOTA_MODE:-rolling}")"
  # 套餐默认 rolling；显式 calendar 保留
  [ -n "${USER_QUOTA_MODE:-}" ] || qmode="rolling"
  _U_NAME="$name" _U_PASS="$password" _U_PORT="$port" _U_PROTO="${PROTOCOL:-TCP}"
  _U_QUOTA_MB="${USER_QUOTA_MB:-0}" _U_QUOTA_DAYS="${USER_QUOTA_DAYS:-0}"
  _U_QUOTA_MODE="$qmode"
  _U_EXPIRE="${expire_at}" _U_PACKAGE="${USER_PACKAGE:-}" _U_BW="$bw"
  set +e
  users_py_locked '
import json, os, time, sys, datetime
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
users.append({
    "name": name,
    "password": password,
    "port": port,
    "enabled": True,
    "quota_mb": qmb,
    "quota_days": qdays if qmb > 0 else 0,
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
  t "已添加用户 ${name} 端口 ${port} 套餐=${USER_PACKAGE:-unlimited} 配额=$(quota_label "${USER_QUOTA_MB:-0}" "${USER_QUOTA_DAYS:-0}") 带宽=${bw}Mbps 到期=${expire_at:-永不过期}" \
    "Added ${name} port ${port} package=${USER_PACKAGE:-unlimited} quota=$(quota_label "${USER_QUOTA_MB:-0}" "${USER_QUOTA_DAYS:-0}") bw=${bw}Mbps expire=${expire_at:-never}" >&2
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
  if [ -n "$tp_section" ] && command -v python3 >/dev/null 2>&1; then
    _CFG="$cfg" _TP="$tp_section" python3 - <<'PY' 2>/dev/null || true
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
  fi
  printf '%s' "$cfg"
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
  # 将 users.json 应用到 mita + 重建 tc（持管理锁；显式释放，避免嵌套 trap 覆盖）
  local cfg enabled_n bin rc=0
  STAGE="应用多用户配置"
  admin_lock_acquire
  if [ "$(users_count)" -eq 0 ]; then
    admin_lock_release
    die "$(t '至少保留一个用户' 'Keep at least one user')" || return 1
  fi
  enabled_n="$(python3 -c '
import json,sys
d=json.load(open(sys.argv[1]))
print(sum(1 for u in (d.get("users") or []) if u.get("enabled", True)))
' "$MITA_USERS_STATE" 2>/dev/null || echo 0)"
  if [ "${enabled_n:-0}" -eq 0 ]; then
    admin_lock_release
    die "$(t '至少保留一个启用中的用户' 'Keep at least one enabled user')" || return 1
  fi
  if ! cfg="$(write_server_config_multi)"; then
    admin_lock_release
    return 1
  fi
  if ! apply_config "$cfg"; then
    admin_lock_release
    return 1
  fi
  bin="$(mita_bin)"
  if "$bin" reload 2>/dev/null; then
    :
  else
    start_mita || rc=1
  fi
  apply_tc_limits 2>/dev/null || true
  harden_mita_permissions 2>/dev/null || true
  admin_lock_release
  return "$rc"
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

# ---------- 阶段3/5：按独占端口 tc 双向限速（出口 HTB sport + 入口 police dport） ----------

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

# 清除本脚本在网卡上创建的 HTB 根 + ingress
tc_clear_root() {
  local dev="$1"
  [ -n "$dev" ] || return 0
  tc qdisc del dev "$dev" root 2>/dev/null || true
  tc qdisc del dev "$dev" ingress 2>/dev/null || true
  tc qdisc del dev "$dev" handle "${TC_INGRESS_HANDLE:-ffff:}" ingress 2>/dev/null || true
}

# Mbps → police rate 字符串；burst ≈ rate/8（最小 10k）
tc_police_burst() {
  local mbps="$1" burst
  burst=$((mbps * 1000 / 8))
  [ "$burst" -lt 10 ] && burst=10
  printf '%sk' "$burst"
}

# 从 users.json 全量重建双向限速（幂等）
# 出口(下载): HTB + u32 match sport=用户端口
# 入口(上传): ingress + u32 match dport=用户端口 + police
apply_tc_limits() {
  local dev handle root_rate has_limit=0 name port bw classid idx=10 burst
  [ "${DRY_RUN:-0}" -eq 1 ] && return 0
  users_state_exists || return 0
  if ! tc_available; then
    if python3 -c '
import json,sys
d=json.load(open(sys.argv[1]))
sys.exit(0 if any(int(u.get("bandwidth_mbps") or 0)>0 for u in (d.get("users") or [])) else 1)
' "$MITA_USERS_STATE" 2>/dev/null; then
      warn "$(t 'tc 不可用，无法应用带宽限速（需 iproute2 + NET_ADMIN/root）' \
        'tc unavailable; cannot apply bandwidth limits (need iproute2 + root/NET_ADMIN)')"
    fi
    return 0
  fi
  dev="$(tc_default_iface)"
  if [ -z "$dev" ]; then
    warn "$(t '无法检测网卡，跳过 tc 限速（可设 TC_IFACE=eth0）' \
      'Cannot detect NIC; skip tc (set TC_IFACE=eth0)')"
    return 0
  fi
  handle="${TC_HANDLE:-1}"
  root_rate="${TC_ROOT_RATE:-10gbit}"

  has_limit="$(python3 -c '
import json,sys
d=json.load(open(sys.argv[1]))
print(1 if any(u.get("enabled",True) and int(u.get("bandwidth_mbps") or 0)>0 for u in (d.get("users") or [])) else 0)
' "$MITA_USERS_STATE" 2>/dev/null || echo 0)"

  tc_clear_root "$dev"
  if [ "$has_limit" != "1" ]; then
    users_log "tc: no rate limits on $dev (cleared egress+ingress)"
    return 0
  fi

  # ---- 出口 HTB ----
  if ! tc qdisc add dev "$dev" root handle "${handle}:" htb default 9999 2>/tmp/mita-tc.err; then
    warn "$(t "tc 创建根 qdisc 失败 ($dev): $(cat /tmp/mita-tc.err 2>/dev/null)" \
      "tc root qdisc failed on $dev")"
    return 1
  fi
  tc class add dev "$dev" parent "${handle}:" classid "${handle}:1" htb rate "$root_rate" ceil "$root_rate" 2>/dev/null || true
  tc class add dev "$dev" parent "${handle}:1" classid "${handle}:9999" htb rate "$root_rate" ceil "$root_rate" 2>/dev/null || true

  # ---- 入口 ingress（失败则仅出口）----
  local ingress_ok=0
  if tc qdisc add dev "$dev" handle "${TC_INGRESS_HANDLE:-ffff:}" ingress 2>/tmp/mita-tc-ing.err; then
    ingress_ok=1
  else
    warn "$(t "tc ingress 创建失败 ($dev)，仅出口限速: $(head -c 200 /tmp/mita-tc-ing.err 2>/dev/null)" \
      "tc ingress failed on $dev; egress only")"
    users_log "tc: ingress unavailable on $dev"
  fi

  idx=10
  while IFS=$'\t' read -r name port bw; do
    [ -n "$port" ] || continue
    [ -n "$bw" ] && [ "$bw" -gt 0 ] 2>/dev/null || continue
    classid="$(printf '%x' "$idx")"
    idx=$((idx + 1))
    burst="$(tc_police_burst "$bw")"

    # 出口 class + sport filter
    if ! tc class add dev "$dev" parent "${handle}:1" classid "${handle}:${classid}" \
        htb rate "${bw}mbit" ceil "${bw}mbit" 2>/tmp/mita-tc.err; then
      warn "$(t "tc class 失败 ${name} ${bw}mbit: $(cat /tmp/mita-tc.err 2>/dev/null)" \
        "tc class failed ${name}")"
      continue
    fi
    tc filter add dev "$dev" protocol ip parent "${handle}:" prio 1 u32 \
      match ip sport "$port" 0xffff flowid "${handle}:${classid}" 2>/dev/null || true
    tc filter add dev "$dev" protocol ipv6 parent "${handle}:" prio 2 u32 \
      match ip6 sport "$port" 0xffff flowid "${handle}:${classid}" 2>/dev/null || true

    # 入口 police + dport filter（上传）
    if [ "$ingress_ok" -eq 1 ]; then
      if ! tc filter add dev "$dev" parent "${TC_INGRESS_HANDLE:-ffff:}" protocol ip prio 1 u32 \
          match ip dport "$port" 0xffff \
          police rate "${bw}mbit" burst "$burst" drop flowid :1 2>/tmp/mita-tc-ingf.err; then
        warn "$(t "入口限速失败 ${name} port=${port}（保留出口）" \
          "ingress police failed ${name} port=${port} (egress kept)")"
      fi
      tc filter add dev "$dev" parent "${TC_INGRESS_HANDLE:-ffff:}" protocol ipv6 prio 2 u32 \
        match ip6 dport "$port" 0xffff \
        police rate "${bw}mbit" burst "$burst" drop flowid :1 2>/dev/null || true
    fi

    if [ "${PROTOCOL:-TCP}" = "BOTH" ]; then
      local up=$((port + 1))
      # 出口 UDP+1（IPv4/IPv6）
      tc filter add dev "$dev" protocol ip parent "${handle}:" prio 1 u32 \
        match ip sport "$up" 0xffff flowid "${handle}:${classid}" 2>/dev/null || true
      tc filter add dev "$dev" protocol ipv6 parent "${handle}:" prio 2 u32 \
        match ip6 sport "$up" 0xffff flowid "${handle}:${classid}" 2>/dev/null || true
      if [ "$ingress_ok" -eq 1 ]; then
        # 入口 UDP+1（IPv4/IPv6）
        tc filter add dev "$dev" parent "${TC_INGRESS_HANDLE:-ffff:}" protocol ip prio 1 u32 \
          match ip dport "$up" 0xffff \
          police rate "${bw}mbit" burst "$burst" drop flowid :1 2>/dev/null || true
        tc filter add dev "$dev" parent "${TC_INGRESS_HANDLE:-ffff:}" protocol ipv6 prio 2 u32 \
          match ip6 dport "$up" 0xffff \
          police rate "${bw}mbit" burst "$burst" drop flowid :1 2>/dev/null || true
      fi
    fi
    if [ "$ingress_ok" -eq 1 ]; then
      users_log "tc: ${name} port=${port} ${bw}mbit egress+ingress class=${handle}:${classid} dev=${dev}"
    else
      users_log "tc: ${name} port=${port} ${bw}mbit egress-only class=${handle}:${classid} dev=${dev}"
    fi
  done < <(python3 -c '
import json,sys
d=json.load(open(sys.argv[1]))
for u in d.get("users") or []:
    if not u.get("enabled", True):
        continue
    bw=int(u.get("bandwidth_mbps") or 0)
    if bw<=0:
        continue
    print("%s\t%s\t%s" % (u.get("name") or "", u.get("port") or "", bw))
' "$MITA_USERS_STATE" 2>/dev/null)

  return 0
}

tc_rate_status() {
  local dev
  dev="$(tc_default_iface)"
  msg ""
  t "【tc 限速状态】网卡: ${dev:-?}（出口 HTB + 入口 police）" \
    "[tc rate status] iface: ${dev:-?} (egress HTB + ingress police)"
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
  msg "--- egress class ---"
  tc class show dev "$dev" 2>/dev/null || true
  msg "--- egress filter ---"
  tc filter show dev "$dev" 2>/dev/null | head -n 30 || true
  msg "--- ingress filter ---"
  tc filter show dev "$dev" parent "${TC_INGRESS_HANDLE:-ffff:}" 2>/dev/null | head -n 30 || true
  msg ""
  t '【用户带宽配置】双向 Mbps' '[User bandwidth] bidirectional Mbps'
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
  users_update_fields "$name" || return 1
  unset _U_ENABLED
}

# 扫描到期：expire_at <= today 且 enabled → 停用；stdout 仅输出被停用的用户名
users_scan_expired() {
  users_require_python || return 1
  users_state_exists || return 0
  local today changed
  today="$(today_ymd)"
  changed="$(USERS_LOG_QUIET=1 python3 -c '
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
' "$MITA_USERS_STATE" "$today" 2>/dev/null || true)"
  if [ -z "$changed" ]; then
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
    apply_users_config >/dev/null 2>&1 || USERS_LOG_QUIET=1 users_log "apply after expire scan failed"
  fi
  printf '%s\n' "$changed"
}

# 日历月配额重置：quota_mode=calendar 且 last_quota_reset != 当月
# 方法（QUOTA_RESET_METHOD）：
#   days     — 仅更新当月天数 + reload（不断线；mita 未必清零累计）
#   password — 微扰密码两次 apply（默认；更可能开启新用户计数，可能短暂断线）
#   metrics  — 删除 /var/lib/mita/metrics.pb 并重启（清全部用户 metrics，最重）
# 仅成功 apply 后才写入 last_quota_reset，避免失败后本月跳过
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
' "$MITA_USERS_STATE" "$1" 2>/dev/null || true
}

_calendar_commit_reset() {
  # 成功后：仅对 _reset_pending 用户写 last_quota_reset，并清 ZWSP
  local ym="$1"
  python3 -c '
import json, sys, time
path, ym = sys.argv[1], sys.argv[2]
d = json.load(open(path))
for u in d.get("users") or []:
    pending = u.pop("_reset_pending", False)
    pw = u.get("password") or ""
    if pw.endswith("\u200b"):
        u["password"] = pw[:-1]
    if pending:
        u["last_quota_reset"] = ym
    u["updated_at"] = int(time.time())
json.dump(d, open(path, "w"), indent=2)
' "$MITA_USERS_STATE" "$ym" 2>/dev/null || true
}

_calendar_abort_reset() {
  # 失败：去掉 pending 与 ZWSP，不写 last_quota_reset
  # 若已向 mita 推送过 ZWSP 密码，调用方应 re-apply
  python3 -c '
import json, sys, time
path = sys.argv[1]
d = json.load(open(path))
for u in d.get("users") or []:
    u.pop("_reset_pending", None)
    pw = u.get("password") or ""
    if pw.endswith("\u200b"):
        u["password"] = pw[:-1]
    u["updated_at"] = int(time.time())
json.dump(d, open(path, "w"), indent=2)
' "$MITA_USERS_STATE" 2>/dev/null || true
}

users_scan_calendar_quota_reset() {
  users_require_python || return 1
  users_state_exists || return 0
  local ym reset_list method ok=0
  ym="$(current_year_month)"
  method="$(printf '%s' "${QUOTA_RESET_METHOD:-password}" | tr '[:upper:]' '[:lower:]')"
  reset_list="$(_calendar_mark_pending "$ym")"
  [ -n "$reset_list" ] || return 0
  local n
  while IFS= read -r n; do
    [ -n "$n" ] || continue
    USERS_LOG_QUIET=1 users_log "calendar quota reset: $n month=$ym method=$method"
  done <<< "$reset_list"

  if ! mita_installed 2>/dev/null; then
    _calendar_commit_reset "$ym"
    printf '%s\n' "$reset_list"
    return 0
  fi

  load_install_state
  MULTI_USER_MODE=1

  case "$method" in
    days)
      if apply_users_config >/dev/null 2>&1; then
        ok=1
      else
        USERS_LOG_QUIET=1 users_log "calendar days-only apply failed"
      fi
      ;;
    metrics)
      if apply_users_config >/dev/null 2>&1; then
        local sm
        sm="$(service_manager 2>/dev/null || echo systemd)"
        case "$sm" in
          systemd) run systemctl stop mita 2>/dev/null || true ;;
          openrc) run rc-service mita stop 2>/dev/null || true ;;
        esac
        run rm -f /var/lib/mita/metrics.pb 2>/dev/null || true
        if start_mita 2>/dev/null; then
          ok=1
          USERS_LOG_QUIET=1 users_log "calendar reset cleared metrics.pb"
        else
          USERS_LOG_QUIET=1 users_log "calendar metrics reset: start_mita failed"
        fi
      fi
      ;;
    password|*)
      # 微扰密码 → apply → 恢复密码 → apply
      local first_applied=0
      python3 -c '
import json,sys
path=sys.argv[1]
d=json.load(open(path))
for u in d.get("users") or []:
    if not u.get("_reset_pending"):
        continue
    pw=u.get("password") or ""
    if not pw.endswith("\u200b"):
        u["password"]=pw+"\u200b"
json.dump(d, open(path,"w"), indent=2)
' "$MITA_USERS_STATE" 2>/dev/null || true
      if apply_users_config >/dev/null 2>&1; then
        first_applied=1
        python3 -c '
import json,sys
path=sys.argv[1]
d=json.load(open(path))
for u in d.get("users") or []:
    if not u.get("_reset_pending"):
        continue
    pw=u.get("password") or ""
    if pw.endswith("\u200b"):
        u["password"]=pw[:-1]
json.dump(d, open(path,"w"), indent=2)
' "$MITA_USERS_STATE" 2>/dev/null || true
        if apply_users_config >/dev/null 2>&1; then
          ok=1
        else
          USERS_LOG_QUIET=1 users_log "calendar password-reset second apply failed"
        fi
      else
        USERS_LOG_QUIET=1 users_log "calendar password-reset first apply failed"
      fi
      # 若第一次已 apply 而整体失败：abort JSON 后必须 re-apply 干净密码
      if [ "$ok" -ne 1 ] && [ "$first_applied" -eq 1 ]; then
        _calendar_abort_reset
        apply_users_config >/dev/null 2>&1 || USERS_LOG_QUIET=1 users_log "calendar password abort re-apply failed"
        USERS_LOG_QUIET=1 users_log "calendar reset aborted after partial apply; will retry next scan"
        return 1
      fi
      ;;
  esac

  if [ "$ok" -eq 1 ]; then
    _calendar_commit_reset "$ym"
    printf '%s\n' "$reset_list"
  else
    _calendar_abort_reset
    USERS_LOG_QUIET=1 users_log "calendar reset aborted; will retry next scan"
    return 1
  fi
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
Description=mita users expire scan and tc rate restore
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=${script_path} user-scan
# 开机恢复按端口 tc 限速
ExecStartPost=${script_path} rate-restore
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
    # 开机 oneshot 恢复 tc
    cat >"/etc/systemd/system/mita-tc-restore.service" <<EOF
[Unit]
Description=Restore mita per-port tc rate limits
After=network-online.target mita.service
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=${script_path} rate-restore
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload 2>/dev/null || true
    systemctl enable --now mita-users-scan.timer 2>/dev/null || true
    systemctl enable mita-tc-restore.service 2>/dev/null || true
    systemctl start mita-tc-restore.service 2>/dev/null || true
    install_logrotate_config 2>/dev/null || true
    harden_mita_permissions 2>/dev/null || true
    users_log "scheduler: systemd timer + mita-tc-restore.service"
    return 0
  fi

  if [ -d /etc/cron.d ]; then
    cat >"$MITA_USERS_CRON" <<EOF
# mita multi-user expire scan (every 15 min) + daily tc restore
*/15 * * * * root ${script_path} user-scan >>${MITA_USERS_LOG} 2>&1
@reboot root sleep 30; ${script_path} rate-restore >>${MITA_USERS_LOG} 2>&1
EOF
    chmod 0644 "$MITA_USERS_CRON" 2>/dev/null || true
    install_logrotate_config 2>/dev/null || true
    harden_mita_permissions 2>/dev/null || true
    users_log "scheduler: cron ${MITA_USERS_CRON}"
    return 0
  fi
  # OpenRC / 无 cron：写入 hint
  install_logrotate_config 2>/dev/null || true
  warn "$(t '未找到 systemd timer 或 /etc/cron.d，请手动定期执行: install-mita user-scan / rate-restore' \
    'No systemd timer or /etc/cron.d; run: install-mita user-scan / rate-restore')"
}

remove_users_scheduler() {
  if [ -f "$MITA_USERS_TIMER" ] || [ -f "$MITA_USERS_SERVICE" ]; then
    systemctl disable --now mita-users-scan.timer 2>/dev/null || true
    systemctl disable --now mita-tc-restore.service 2>/dev/null || true
    rm -f "$MITA_USERS_TIMER" "$MITA_USERS_SERVICE" /etc/systemd/system/mita-tc-restore.service 2>/dev/null || true
    systemctl daemon-reload 2>/dev/null || true
  fi
  rm -f "$MITA_USERS_CRON" 2>/dev/null || true
  # 清除 tc 规则
  local dev
  dev="$(tc_default_iface 2>/dev/null || true)"
  [ -n "$dev" ] && tc_clear_root "$dev" 2>/dev/null || true
}

# ---------- 阶段4：备份 / 恢复 / 导出导入 / 管理锁 ----------

# 破坏性变更前备份 users.json；成功打印备份路径
users_backup_now() {
  local tag="${1:-auto}" dest ts
  users_state_exists || return 1
  run mkdir -p "$MITA_USERS_BACKUP_DIR"
  ts="$(date +%Y%m%d_%H%M%S 2>/dev/null || echo unknown)"
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
d=os.environ.get("MITA_USERS_BACKUP_DIR", "/etc/mita/backups")
files=sorted(glob.glob(os.path.join(d, "users_*.json")), key=os.path.getmtime, reverse=True)
for f in files[20:]:
    try: os.remove(f)
    except Exception: pass
' 2>/dev/null || true
  fi
  printf '%s' "$dest"
}

users_validate_state_file() {
  local f="$1"
  [ -f "$f" ] || return 1
  python3 -c '
import json,sys
d=json.load(open(sys.argv[1]))
users=d.get("users")
if not isinstance(users, list):
    sys.exit(2)
names=set(); ports=set()
for u in users:
    if not isinstance(u, dict):
        sys.exit(3)
    n=u.get("name") or ""
    if not n:
        sys.exit(4)
    if n in names:
        sys.exit(5)
    names.add(n)
    try:
        p=int(u.get("port"))
    except Exception:
        sys.exit(6)
    if p in ports:
        sys.exit(7)
    ports.add(p)
    # normalize optional fields
    u.setdefault("enabled", True)
    u.setdefault("quota_mb", 0)
    u.setdefault("quota_days", 0)
    u.setdefault("quota_mode", "rolling")
    u.setdefault("last_quota_reset", "")
    u.setdefault("expire_at", "")
    u.setdefault("package", "unlimited")
    u.setdefault("bandwidth_mbps", 0)
d["version"]=int(d.get("version") or 1)
json.dump(d, open(sys.argv[1]+".norm","w"), indent=2)
' "$f" 2>/dev/null || return 1
  if [ -f "${f}.norm" ]; then
    mv -f "${f}.norm" "$f" 2>/dev/null || true
  fi
  return 0
}

users_restore_from_file() {
  local src="$1" bak
  [ -f "$src" ] || { warn "$(t "备份不存在: $src" "Backup not found: $src")"; return 1; }
  local tmp
  tmp="$(mktemp_file .json)"
  cp -f "$src" "$tmp"
  users_validate_state_file "$tmp" || { rm -f "$tmp"; warn "$(t '备份文件格式无效' 'Invalid backup format')"; return 1; }
  admin_lock_acquire
  if users_state_exists; then
    bak="$(users_backup_now pre-restore 2>/dev/null || true)"
    [ -n "$bak" ] && t "恢复前已备份: $bak" "Pre-restore backup: $bak" >&2
  fi
  run mkdir -p "$(dirname "$MITA_USERS_STATE")"
  if command -v install >/dev/null 2>&1; then
    run install -m 0600 "$tmp" "$MITA_USERS_STATE"
  else
    run cp -f "$tmp" "$MITA_USERS_STATE"
    run chmod 0600 "$MITA_USERS_STATE" 2>/dev/null || true
  fi
  rm -f "$tmp"
  MULTI_USER_MODE=1
  users_sync_primary_globals
  if mita_installed 2>/dev/null; then
    if ! apply_users_config; then
      admin_lock_release
      return 1
    fi
    open_firewall_for_pairs "$(multi_user_port_protocol_pairs)" 2>/dev/null || true
  else
    apply_tc_limits 2>/dev/null || true
  fi
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
  [ -n "$f" ] || die "$(t '需要 --user-import FILE' 'Need --user-import FILE')"
  if [ "$YES" -ne 1 ]; then
    confirm '导入将覆盖当前用户配置，是否继续？[y/N]: ' 'Import overwrites current users. Continue? [y/N]: ' n || return 0
  fi
  users_restore_from_file "$f"
}

print_user_outputs() {
  local name="$1"
  local ip password port saved_user saved_pass saved_port
  password="$(users_get_field "$name" password)" || return 1
  port="$(users_get_field "$name" port)" || return 1
  ip="$(public_ip || echo 'YOUR_SERVER_IP')"
  saved_user="$USERNAME"
  saved_pass="$PASSWORD"
  saved_port="$PORT"
  USERNAME="$name"
  PASSWORD="$password"
  PORT="$port"
  msg ""
  t "========== 用户 ${name} ==========" "========== User ${name} =========="
  t "  端口: ${port}" "  Port: ${port}"
  local qmb qdays exp en pkg bw
  qmb="$(users_get_field "$name" quota_mb 2>/dev/null || echo 0)"
  qdays="$(users_get_field "$name" quota_days 2>/dev/null || echo 0)"
  exp="$(users_get_field "$name" expire_at 2>/dev/null || true)"
  en="$(users_get_field "$name" enabled 2>/dev/null || echo 1)"
  pkg="$(users_get_field "$name" package 2>/dev/null || true)"
  bw="$(users_get_field "$name" bandwidth_mbps 2>/dev/null || echo 0)"
  t "  套餐: ${pkg:--}  配额: $(quota_label "$qmb" "$qdays")  带宽: ${bw:-0}Mbps  到期: ${exp:-永不过期}  状态: $([ "$en" = 1 ] && echo on || echo off)" \
    "  Package: ${pkg:--}  Quota: $(quota_label "$qmb" "$qdays")  BW: ${bw:-0}Mbps  Expire: ${exp:-never}  Status: $([ "$en" = 1 ] && echo on || echo off)"
  print_protocol_outputs "$ip"
  msg ""
  t '【连接信息】' '[Connection info]'
  t "  服务器: ${ip}" "  Server:   ${ip}"
  t "  用户名: ${name}" "  Username: ${name}"
  t "  密码:   ${password}" "  Password: ${password}"
  t "  协议:   $(protocol_label)" "  Protocol: $(protocol_label)"
  if [ "$PROTOCOL" = "BOTH" ]; then
    t "  端口:   TCP ${port} / UDP $((port + 1))" "  Ports:    TCP ${port} / UDP $((port + 1))"
  else
    t "  端口:   ${port}" "  Port:     ${port}"
  fi
  if [ -n "$ip" ] && [ "$ip" != "YOUR_SERVER_IP" ]; then
    msg ""
    t '【Clash / mihomo 配置片段】' '[Clash / mihomo snippet]'
    build_clash_yaml_full "$ip"
  fi
  USERNAME="$saved_user"
  PASSWORD="$saved_pass"
  PORT="$saved_port"
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
    case "$fw" in
      ufw) run ufw allow "$(ufw_rule_spec "$p" "$proto_lc")" || true ;;
      firewalld) run firewall-cmd --permanent --add-port="${p}/${proto_lc}" || true ;;
      iptables) iptables_accept_port "$p" "$proto_lc" add ;;
    esac
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
  t '用户名      端口 状态 套餐     配额        模式  带宽  到期' \
    'USER        PORT ST   PACKAGE  QUOTA       MODE  Mbps  EXPIRE'
  t '----------- ---- ---- -------- ----------- ----- ----- ----------' \
    '----------- ---- ---- -------- ----------- ----- ----- ----------'
  python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
for u in d.get("users") or []:
    name = (u.get("name") or "")[:11]
    port = str(u.get("port") or "")
    st = "on" if u.get("enabled", True) else "off"
    pkg = (u.get("package") or "-")[:8]
    qmb = int(u.get("quota_mb") or 0)
    qdays = int(u.get("quota_days") or 0)
    mode = (u.get("quota_mode") or "rolling")[:5]
    if qmb <= 0:
        quota = "unlim"
        mode = "-"
    elif qmb >= 1024:
        quota = "%dG/%dd" % (qmb // 1024, qdays or 30)
    else:
        quota = "%dM/%dd" % (qmb, qdays or 30)
    bw = int(u.get("bandwidth_mbps") or 0)
    bws = str(bw) if bw > 0 else "-"
    exp = (u.get("expire_at") or "never")[:10]
    print(f"{name:<11} {port:<4} {st:<4} {pkg:<8} {quota:<11} {mode:<5} {bws:<5} {exp}")
' "$MITA_USERS_STATE"
  t "共 $(users_count) 个用户（rolling=滚动窗；calendar=每月1日重置）" \
    "Total $(users_count) (rolling window; calendar=reset on 1st)"
}

do_user_add() {
  require_root
  require_linux
  mita_installed || die "$(t 'mita 未安装，请先执行安装' 'mita is not installed; run install first')"
  # CLI 参数先保存，避免被 load_install_state 覆盖
  local name="${USERNAME:-}" password="${PASSWORD:-}" prefer="" new_port
  local saved_pkg="${USER_PACKAGE:-}" saved_qmb="${USER_QUOTA_MB:-}" saved_qd="${USER_QUOTA_DAYS:-}" saved_exp="${USER_EXPIRE:-}" saved_bw="${USER_BANDWIDTH_MBPS:-}"
  if [ "${PORT_CLI:-0}" -eq 1 ] && [ -n "${PORT:-}" ]; then
    prefer="$PORT"
  fi
  load_install_state
  USER_PACKAGE="$saved_pkg"
  USER_QUOTA_MB="$saved_qmb"
  USER_QUOTA_DAYS="$saved_qd"
  USER_EXPIRE="$saved_exp"
  USER_BANDWIDTH_MBPS="$saved_bw"
  if ! users_state_exists || [ "$(users_count)" -eq 0 ]; then
    load_config_from_mita 2>/dev/null || true
    load_credentials_fallback 2>/dev/null || true
    users_migrate_from_primary 2>/dev/null || true
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
      read_tty password "$(t '密码（回车随机）: ' 'Password (Enter=random): ')" || true
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
  admin_lock_acquire
  if ! new_port="$(users_add "$name" "$password" "$prefer")"; then
    admin_lock_release
    return 1
  fi
  if ! apply_users_config; then
    admin_lock_release
    return 1
  fi
  open_firewall_for_pairs "$(multi_user_port_protocol_pairs)"
  save_install_state
  admin_lock_release
  print_user_outputs "$name"
}

do_user_set_quota() {
  require_root
  mita_installed || die "$(t 'mita 未安装' 'mita is not installed')"
  load_install_state
  users_ensure_loaded
  local name="${USERNAME:-}"
  [ -n "$name" ] || die "$(t '需要 --user NAME' 'Need --user NAME')"
  users_name_exists "$name" || die "$(t "用户不存在: $name" "User not found: $name")"
  apply_user_package_defaults
  if [ -z "${USER_QUOTA_MB}" ] && [ -z "${USER_PACKAGE}" ] && [ -z "${USER_QUOTA_MODE}" ]; then
    die "$(t '需要 --package / --quota-mb / --quota-mode' 'Need --package / --quota-mb / --quota-mode')"
  fi
  local exp_parsed=""
  if [ -n "${USER_EXPIRE:-}" ]; then
    exp_parsed="$(parse_expire_date "$USER_EXPIRE")" || return 1
    USER_EXPIRE="$exp_parsed"
    [ -z "$USER_EXPIRE" ] && USER_EXPIRE="__CLEAR__"
  fi
  if [ -n "${USER_QUOTA_MODE:-}" ]; then
    USER_QUOTA_MODE="$(normalize_quota_mode "$USER_QUOTA_MODE")"
  fi
  USER_BANDWIDTH_MBPS=""
  admin_lock_acquire
  if ! users_update_fields "$name"; then
    admin_lock_release
    return 1
  fi
  if ! apply_users_config; then
    admin_lock_release
    return 1
  fi
  admin_lock_release
  t "已更新 ${name} 配额=$(quota_label "${USER_QUOTA_MB:-0}" "${USER_QUOTA_DAYS:-0}") 模式=${USER_QUOTA_MODE:-keep} 套餐=${USER_PACKAGE:-} 到期=${exp_parsed:-保持}" \
    "Updated ${name} quota=$(quota_label "${USER_QUOTA_MB:-0}" "${USER_QUOTA_DAYS:-0}") mode=${USER_QUOTA_MODE:-keep} package=${USER_PACKAGE:-} expire=${exp_parsed:-keep}"
}

do_user_set_expire() {
  require_root
  mita_installed || die "$(t 'mita 未安装' 'mita is not installed')"
  load_install_state
  users_ensure_loaded
  local name="${USERNAME:-}" exp
  [ -n "$name" ] || die "$(t '需要 --user NAME' 'Need --user NAME')"
  users_name_exists "$name" || die "$(t "用户不存在: $name" "User not found: $name")"
  [ -n "${USER_EXPIRE}" ] || die "$(t '需要 --expire YYYY-MM-DD|+Nd|0' 'Need --expire YYYY-MM-DD|+Nd|0')"
  exp="$(parse_expire_date "$USER_EXPIRE")" || return 1
  USER_EXPIRE="${exp:-__CLEAR__}"
  USER_QUOTA_MB="" USER_QUOTA_DAYS="" USER_PACKAGE="" USER_BANDWIDTH_MBPS=""
  admin_lock_acquire
  if ! users_update_fields "$name"; then
    admin_lock_release
    return 1
  fi
  if [ -n "$exp" ]; then
    local today
    today="$(today_ymd)"
    if [[ "$exp" < "$today" || "$exp" == "$today" ]]; then
      users_set_enabled "$name" 0 || true
    fi
  fi
  if ! apply_users_config; then
    admin_lock_release
    return 1
  fi
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
  local exp today
  exp="$(users_get_field "$name" expire_at 2>/dev/null || true)"
  today="$(today_ymd)"
  if [ -n "$exp" ] && { [[ "$exp" < "$today" ]] || [[ "$exp" == "$today" ]]; }; then
    warn "$(t "用户 $name 已到期 ($exp)，请先 --user-set-expire 续期" \
      "User $name expired ($exp); renew with --user-set-expire first")"
    return 1
  fi
  admin_lock_acquire
  if ! users_set_enabled "$name" 1; then
    admin_lock_release
    return 1
  fi
  if ! apply_users_config; then
    admin_lock_release
    return 1
  fi
  open_firewall_for_pairs "$(multi_user_port_protocol_pairs)"
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
  local en_n
  en_n="$(python3 -c '
import json,sys
d=json.load(open(sys.argv[1]))
print(sum(1 for u in (d.get("users") or []) if u.get("enabled", True) and u.get("name")!=sys.argv[2]))
' "$MITA_USERS_STATE" "$name" 2>/dev/null || echo 0)"
  if [ "${en_n:-0}" -lt 1 ]; then
    die "$(t '不能停用最后一个启用中的用户' 'Cannot disable the last enabled user')"
  fi
  admin_lock_acquire
  if ! users_set_enabled "$name" 0; then
    admin_lock_release
    return 1
  fi
  if ! apply_users_config; then
    admin_lock_release
    return 1
  fi
  admin_lock_release
  t "已停用用户 $name（端口仍保留，可再 enable）" "Disabled $name (port kept; can re-enable)"
}

do_user_scan() {
  # cron/timer 入口：到期停用 + 日历月配额重置
  require_root 2>/dev/null || true
  load_install_state 2>/dev/null || true
  users_state_exists || return 0
  local out="" cal=""
  admin_lock_acquire
  out="$(users_scan_expired || true)"
  cal="$(users_scan_calendar_quota_reset || true)"
  admin_lock_release
  if [ -n "$out" ]; then
    msg "disabled: $(printf '%s' "$out" | tr '\n' ' ')"
  fi
  if [ -n "$cal" ]; then
    msg "quota-reset: $(printf '%s' "$cal" | tr '\n' ' ')"
  fi
}

do_user_usage() {
  require_root 2>/dev/null || true
  mita_installed || die "$(t 'mita 未安装' 'mita is not installed')"
  local bin
  bin="$(mita_bin)"
  ensure_mita_daemon 2>/dev/null || true
  wait_mita_socket 10 2>/dev/null || true
  msg ""
  t '【用户流量】mita get users' '[User traffic] mita get users'
  if ! "$bin" get users 2>/dev/null; then
    warn "$(t 'mita get users 不可用（需较新 mita）' 'mita get users unavailable (need newer mita)')"
  fi
  msg ""
  t '【配额用量】mita get quotas' '[Quota usage] mita get quotas'
  if ! "$bin" get quotas 2>/dev/null; then
    warn "$(t 'mita get quotas 不可用' 'mita get quotas unavailable')"
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
  local ts ip name
  ts="$(date +%Y%m%d_%H%M%S)"
  dir="${dir%/}/${ts}"
  run mkdir -p "$dir"
  run chmod 0700 "$dir" 2>/dev/null || true
  ip="$(public_ip || echo 'YOUR_SERVER_IP')"
  load_install_state
  t "导出目录: $dir" "Export dir: $dir" >&2
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    local password port saved_u saved_p saved_port proto f
    password="$(users_get_field "$name" password)" || continue
    port="$(users_get_field "$name" port)" || continue
    saved_u="$USERNAME"; saved_p="$PASSWORD"; saved_port="$PORT"
    USERNAME="$name"; PASSWORD="$password"; PORT="$port"
    while IFS= read -r proto; do
      [ -n "$proto" ] || continue
      f="${dir}/${name}_$(proto_lower "$proto").json"
      build_client_json_for "$ip" "$proto" >"$f"
      chmod 0600 "$f" 2>/dev/null || true
      generate_share_link_for "$ip" "$proto" >>"${dir}/${name}_links.txt"
      printf '\n' >>"${dir}/${name}_links.txt"
    done < <(protocols_for_mode)
    chmod 0600 "${dir}/${name}_links.txt" 2>/dev/null || true
    USERNAME="$saved_u"; PASSWORD="$saved_p"; PORT="$saved_port"
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

do_doctor() {
  require_root 2>/dev/null || true
  local pass=0 fail=0 warn_n=0
  local check
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
  check "tc (iproute2)" "$(command -v tc >/dev/null 2>&1 && echo 1 || echo 2)" "限速需要"
  check "flock" "$(command -v flock >/dev/null 2>&1 && echo 1 || echo 2)" "并发锁"

  t '【mita】' '[mita]'
  if mita_installed; then
    check "mita installed" 1 "$(installed_version 2>/dev/null || echo ok)"
    local bin st
    bin="$(mita_bin)"
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
    if "$bin" get users >/dev/null 2>&1; then
      check "mita get users" 1
    else
      check "mita get users" 2 "旧版可能无此命令"
    fi
    if "$bin" get quotas >/dev/null 2>&1; then
      check "mita get quotas" 1
    else
      check "mita get quotas" 2
    fi
  else
    check "mita installed" 0
  fi

  t '【用户状态】' '[Users state]'
  load_install_state 2>/dev/null || true
  if users_state_exists; then
    check "users.json" 1 "$(users_count) users"
    local en
    en="$(python3 -c '
import json,sys
d=json.load(open(sys.argv[1]))
print(sum(1 for u in (d.get("users") or []) if u.get("enabled",True)))
' "$MITA_USERS_STATE" 2>/dev/null || echo 0)"
    check "enabled users" "$([ "${en:-0}" -ge 1 ] && echo 1 || echo 0)" "$en"
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

  t '【限速 tc】' '[tc rate]'
  local dev
  dev="$(tc_default_iface 2>/dev/null || true)"
  if ! command -v tc >/dev/null 2>&1; then
    check "tc binary" 2 "未安装"
  elif [ -z "$dev" ]; then
    check "nic detect" 2 "设 TC_IFACE="
  else
    check "nic" 1 "$dev"
    if tc qdisc show dev "$dev" 2>/dev/null | grep -q htb; then
      check "egress HTB" 1
    else
      check "egress HTB" 2 "无规则或未配置带宽"
    fi
    if tc qdisc show dev "$dev" 2>/dev/null | grep -qi ingress; then
      check "ingress qdisc" 1
    else
      check "ingress qdisc" 2 "入口限速未启用"
    fi
  fi

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
  t '验收通过（警告可忽略或稍后处理）' 'Verify OK (warnings optional)'
  return 0
}

do_user_quota_reset() {
  # 手动触发日历月重置（或强制所有 calendar 用户）
  require_root
  load_install_state
  users_ensure_loaded
  local force="${1:-}"
  admin_lock_acquire
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
' "$MITA_USERS_STATE" 2>/dev/null || true
  fi
  local cal
  cal="$(users_scan_calendar_quota_reset || true)"
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
  load_install_state
  users_ensure_loaded
  local name="${USERNAME:-}" bw="${USER_BANDWIDTH_MBPS:-}"
  [ -n "$name" ] || die "$(t '需要 --user NAME' 'Need --user NAME')"
  [ -n "$bw" ] || die "$(t '需要 --bandwidth Mbps（0=不限）' 'Need --bandwidth Mbps (0=unlimited)')"
  [[ "$bw" =~ ^[0-9]+$ ]] || die "$(t '带宽须为非负整数 Mbps' 'Bandwidth must be non-negative integer Mbps')"
  users_name_exists "$name" || die "$(t "用户不存在: $name" "User not found: $name")"
  USER_QUOTA_MB="" USER_QUOTA_DAYS="" USER_EXPIRE="" USER_PACKAGE=""
  USER_BANDWIDTH_MBPS="$bw"
  admin_lock_acquire
  if ! users_update_fields "$name"; then
    admin_lock_release
    return 1
  fi
  apply_tc_limits || true
  admin_lock_release
  t "已设置 ${name} 带宽=${bw}Mbps（0=不限；按端口 tc 出口+入口）" \
    "Set ${name} bandwidth=${bw}Mbps (0=unlimited; egress+ingress tc by port)"
}

do_rate_status() {
  require_root 2>/dev/null || true
  load_install_state 2>/dev/null || true
  tc_rate_status
}

do_rate_restore() {
  require_root 2>/dev/null || true
  load_install_state 2>/dev/null || true
  users_state_exists || return 0
  admin_lock_acquire
  apply_tc_limits || true
  admin_lock_release
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
  local n
  n="$(users_count)"
  if [ "${n:-0}" -le 1 ] && users_name_exists "$name"; then
    die "$(t '不能删除最后一个用户' 'Cannot delete the last user')"
  fi
  local freed
  admin_lock_acquire
  if ! freed="$(users_del "$name")"; then
    admin_lock_release
    return 1
  fi
  if ! apply_users_config; then
    admin_lock_release
    return 1
  fi
  if [ -n "$freed" ]; then
    local close_pairs="TCP|${freed}"
    [ "$PROTOCOL" = "BOTH" ] && close_pairs="${close_pairs}"$'\n'"UDP|$((freed + 1))"
    close_firewall_for_bindings "$close_pairs"
  fi
  open_firewall_for_pairs "$(multi_user_port_protocol_pairs)"
  users_sync_primary_globals
  save_install_state
  admin_lock_release
  t "完成。已释放端口: ${freed:-?}" "Done. Freed port: ${freed:-?}"
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
    t '【用户管理】一用户一口；套餐=滚动配额；到期停用；带宽=tc按端口' \
      '[Users] port/user; quota rolling; expire; bandwidth=tc by port'
    msg "  1) 列出用户"
    msg "  2) 添加用户"
    msg "  3) 删除用户"
    msg "  4) 查看用户节点配置"
    msg "  5) 设置套餐/配额"
    msg "  6) 设置到期日"
    msg "  7) 启用用户"
    msg "  8) 停用用户"
    msg "  9) 立即扫描到期+月配额"
    msg "  10) 设置带宽限速 (Mbps 双向)"
    msg "  11) 查看 tc 限速状态"
    msg "  12) 备份用户配置"
    msg "  13) 从备份恢复"
    msg "  14) 强制日历月配额重置"
    msg "  15) 查看流量/配额用量"
    msg "  16) 批量导出客户端配置"
    msg "  17) 返回主菜单"
    local c=""
    read_tty c "$(t '请选择 [1-17]: ' 'Choose [1-17]: ')" || c=""
    c="$(printf '%s' "$c" | tr -d '[:space:]')"
    case "$c" in
      1) do_user_list ;;
      2)
        USERNAME=""; PASSWORD=""; PORT=""; PORT_CLI=0
        USER_PACKAGE=""; USER_QUOTA_MB=""; USER_QUOTA_DAYS=""; USER_QUOTA_MODE=""; USER_EXPIRE=""; USER_BANDWIDTH_MBPS=""
        YES=0
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
        read_tty USER_BANDWIDTH_MBPS "$(t '带宽 Mbps 双向（0=不限）: ' 'Bandwidth Mbps both dirs (0=unlim): ')" || true
        do_user_set_rate
        ;;
      11) do_rate_status ;;
      12) do_user_backup ;;
      13)
        USER_RESTORE_FILE=""
        do_user_restore
        ;;
      14)
        YES=1
        do_user_quota_reset force
        ;;
      15) do_user_usage ;;
      16) do_user_export_clients ;;
      17) return 0 ;;
      *) warn "$(t '无效选择' 'Invalid choice')" ;;
    esac
    menu_pause
  done
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

choose_traffic_pattern_interactive() {
  [ "${TRAFFIC_CLI:-0}" -eq 1 ] && return 0
  local cur def input=""
  cur="$(normalize_traffic_pattern "${TRAFFIC_PATTERN:-conservative}")"
  case "$cur" in off) def=1 ;; aggressive) def=3 ;; *) def=2 ;; esac
  msg ""
  t '流量伪装 / 抗 DPI（客户端无需与服务端一致）:' \
    'Traffic obfuscation / anti-DPI (client need not match server):'
  t '  1) 关闭 —— 仅 mita 内置隐式默认' \
    '  1) Off — mita built-in implicit only'
  t '  2) 保守 —— 可打印 Nonce + 末尾填充，几乎不影响速度（推荐）' \
    '  2) Conservative — printable nonce + end padding, near-zero overhead (recommended)'
  t '  3) 激进 —— 再加 TCP 分片 + 全量填充，更隐蔽但增加延迟/降速' \
    '  3) Aggressive — also TCP fragment + full padding, stealthier but slower'
  read_tty input "$(t "请选择 [1-3，默认 ${def}]: " "Choose [1-3, default ${def}]: ")" || input=""
  input="${input:-$def}"
  case "$input" in
    1) TRAFFIC_PATTERN="off" ;;
    3) TRAFFIC_PATTERN="aggressive" ;;
    *) TRAFFIC_PATTERN="conservative" ;;
  esac
  msg ""
  t "已选流量伪装: $(traffic_label)" "Traffic obfuscation: $(traffic_label)"
}

collect_config_interactive() {
  STAGE="交互配置"
  [ -n "$USERNAME" ] || USERNAME="$(random_token)"
  [ -n "$PASSWORD" ] || PASSWORD="$(random_token)"
  msg ""
  t '已自动生成代理凭据（安装完成后会再次显示）:' \
    'Proxy credentials auto-generated (shown again after install):'
  t "  用户名: ${USERNAME}" "  Username: ${USERNAME}"
  t "  密码:   ${PASSWORD}" "  Password: ${PASSWORD}"

  if [ "$PROTOCOL_CLI" -eq 0 ]; then
    choose_protocol_interactive
  fi

  msg ""
  if [ -z "$PORT" ] && [ -z "$PORT_RANGE" ]; then
    local default_port input="" base="" localip=""
    localip="$(detect_local_ip)"
    if base="$(derive_port_base)"; then
      default_port="$(derive_port_from_ip)"
      t "检测到本机 IP ${localip}，按尾号规则端口段 $((base + 1))-$((base + 99))（${base} 留给 SSH，默认段内随机）" \
        "Detected local IP ${localip}; by last-octet rule port range $((base + 1))-$((base + 99)) (${base} reserved for SSH, random within range)"
    else
      default_port="$(random_port)"
      warn "$(t "无法按 IP 尾号推导端口（IP=${localip:-未知}，尾号过小或无法识别），回退随机端口" \
        "Cannot derive port from IP last octet (IP=${localip:-unknown}); falling back to random port")"
    fi
    if [ "$PROTOCOL" = "BOTH" ] && [ "$default_port" -ge 65535 ]; then
      default_port=65534
    fi
    read_tty input "$(t "监听端口 [${default_port}]: " "Listen port [${default_port}]: ")" || input=""
    PORT="${input:-$default_port}"
    valid_port "$PORT" || die "$(t '非法端口' 'Invalid port')"
    if [ -n "$base" ] && { [ "$PORT" -lt "$((base + 1))" ] || [ "$PORT" -gt "$((base + 99))" ]; }; then
      warn "$(t "注意：端口 ${PORT} 不在 IP 尾号段 $((base + 1))-$((base + 99)) 内，可能与按 IP 分配端口的约定冲突" \
        "Note: port ${PORT} is outside the IP last-octet range $((base + 1))-$((base + 99)); may break the per-IP port convention")"
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
  choose_traffic_pattern_interactive
  ensure_traffic_seed
}

load_config_from_mita() {
  local desc bin bindings
  bin="$(mita_bin)"
  if ! [ -x "$bin" ]; then
    recover_deb_mita 2>/dev/null || true
    bin="$(mita_bin)"
  fi
  if ! [ -x "$bin" ]; then
    bail "$(t '未找到 mita 二进制，自动修复未成功；请重新运行脚本并选 3) 升级 重新安装' \
      'mita binary not found and auto-repair failed; re-run the script and choose 3) Upgrade')" || return 1
  fi
  desc="$("$bin" describe config 2>/dev/null || true)"
  if [ -z "$desc" ]; then
    bail "$(t '无法读取服务端配置。请先选 5) 状态 检查；若守护进程未运行: systemctl restart mita' \
      'Cannot read server config. Use 5) Status; if daemon is down: systemctl restart mita')" || return 1
  fi

  parse_user_from_describe "$desc" || true
  if [ -z "$USERNAME" ] || [ -z "$PASSWORD" ]; then
    load_credentials_fallback
  fi
  if [ -z "$USERNAME" ]; then
    bail "$(t '配置中缺少用户名' 'Missing username in config')" || return 1
  fi
  if [ -z "$PASSWORD" ]; then
    bail "$(t '密码已哈希存储，无法生成节点链接。请选 2) 重新配置 设置新密码' \
      'Password is hashed; use 2) Reconfigure to set a new password')" || return 1
  fi

  bindings="$(extract_bindings_from_describe "$desc")"
  PORT=""
  PORT_RANGE=""
  if [ -n "$bindings" ]; then
    local pp proto p has_tcp=0 has_udp=0 tcp_port=""
    while IFS= read -r pp; do
      [ -n "$pp" ] || continue
      proto="${pp%%|*}"
      p="${pp#*|}"
      case "$proto" in
        TCP)
          has_tcp=1
          if [[ "$p" =~ ^[0-9]+$ ]]; then
            tcp_port="$p"
          elif [[ "$p" == *-* ]]; then
            PORT_RANGE="$p"
          fi
          ;;
        UDP) has_udp=1 ;;
      esac
    done <<< "$bindings"
    [ -n "$tcp_port" ] && PORT="$tcp_port"
    if [ "$has_tcp" -gt 0 ] && [ "$has_udp" -gt 0 ]; then
      PROTOCOL="BOTH"
    elif [ "$has_udp" -gt 0 ]; then
      PROTOCOL="UDP"
    else
      PROTOCOL="TCP"
    fi
  fi
  load_install_state
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

load_credentials_fallback() {
  load_install_state
  [ -n "$USERNAME" ] && [ -n "$PASSWORD" ] && return 0
  local f line
  if ! command -v python3 >/dev/null 2>&1; then
    return 1
  fi
  for f in /root/mieru_client_*.json /root/mieru_client_tcp_*.json /root/mieru_client_udp_*.json; do
    [ -f "$f" ] || continue
    line="$(python3 -c "
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(1)
if 'profiles' in d:
    p = d['profiles'][0]
    u = p.get('user') or {}
    print(f\"{u.get('name','')}\t{u.get('password','')}\")
    sys.exit(0)
users = d.get('users') or []
if users:
    u = users[0]
    print(f\"{u.get('name','')}\t{u.get('password','')}\")
" "$f" 2>/dev/null)" || continue
    [ -z "$USERNAME" ] && USERNAME="${line%%$'\t'*}"
    [ -z "$PASSWORD" ] && PASSWORD="${line#*$'\t'}"
    [ -n "$USERNAME" ] && [ -n "$PASSWORD" ] && return 0
  done
  return 1
}

collect_reconfigure_interactive() {
  STAGE="重新配置"
  load_config_from_mita
  msg ""
  t '【当前配置】' '[Current config]'
  t "  用户名: ${USERNAME}" "  Username: ${USERNAME}"
  t "  密码:   ${PASSWORD}" "  Password: ${PASSWORD}"
  t "  协议:   $(protocol_label)" "  Protocol: $(protocol_label)"
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
  read_tty input "$(t "新密码 [${PASSWORD}]: " "New password [${PASSWORD}]: ")" || input=""
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
    fi
  fi

  if [ "$PROTOCOL" = "BOTH" ] && [ -n "$PORT" ] && [ "$PORT" -ge 65535 ]; then
    die "$(t '双协议需要主端口 ≤65534' 'Dual protocol needs main port ≤65534')"
  fi
  choose_traffic_pattern_interactive
  ensure_traffic_seed
  msg ""
  t "将应用协议: $(protocol_label)" "Will apply protocol: $(protocol_label)"
}

ensure_config_noninteractive() {
  STAGE="参数校验"
  [ -n "$PORT" ] && [ -n "$PORT_RANGE" ] && \
    die "$(t '--port 与 --port-range 不能同时使用' 'Cannot use --port and --port-range together')"
  [ -n "$USERNAME" ] || USERNAME="$(random_token)"
  [ -n "$PASSWORD" ] || PASSWORD="$(random_token)"
  if [ -z "$PORT" ] && [ -z "$PORT_RANGE" ]; then
    if PORT="$(derive_port_from_ip)"; then
      :
    else
      PORT="$(random_port)"
    fi
  fi
  if [ -n "$PORT" ]; then
    valid_port "$PORT" || die "$(t '非法端口' 'Invalid port')"
    local _base
    if _base="$(derive_port_base 2>/dev/null)" \
       && { [ "$PORT" -lt "$((_base + 1))" ] || [ "$PORT" -gt "$((_base + 99))" ]; }; then
      warn "$(t "端口 ${PORT} 不在本机 IP 尾号段 $((_base + 1))-$((_base + 99)) 内（如非本机 IP 可忽略）" \
        "Port ${PORT} is outside this host's IP last-octet range $((_base + 1))-$((_base + 99)) (ignore if intended)")"
    fi
  fi
  if [ -n "$PORT_RANGE" ]; then
    valid_port_range "$PORT_RANGE" || die "$(t '非法端口段' 'Invalid port range')"
  fi
  if normalize_protocol "$PROTOCOL" >/dev/null 2>&1; then
    PROTOCOL="$(normalize_protocol "$PROTOCOL")"
  else
    PROTOCOL="TCP"
  fi
  if [ "$PROTOCOL" = "BOTH" ] && [ -n "$PORT" ] && [ "$PORT" -ge 65535 ]; then
    die "$(t '双协议需要主端口 ≤65534' 'Dual protocol needs main port ≤65534')"
  fi
  TRAFFIC_PATTERN="$(normalize_traffic_pattern "$TRAFFIC_PATTERN")"
  ensure_traffic_seed
}

normalize_traffic_pattern() {
  case "$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')" in
    off|none|no|0|disable|disabled|close|关) printf 'off' ;;
    aggressive|aggr|full|high|强|激进|2) printf 'aggressive' ;;
    *) printf 'conservative' ;;
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

ensure_traffic_seed() {
  [ "$(normalize_traffic_pattern "${TRAFFIC_PATTERN:-conservative}")" = "off" ] && return 0
  [ -n "$TRAFFIC_SEED" ] && return 0
  TRAFFIC_SEED="$(random_seed)"
}

# 选了流量伪装但当前 mita 过旧不支持时给出明确提示（须在二进制就绪后调用）
warn_traffic_unsupported() {
  [ "$(normalize_traffic_pattern "${TRAFFIC_PATTERN:-conservative}")" = "off" ] && return 0
  mita_supports_traffic_pattern && return 0
  warn "$(t '当前 mita 版本不支持流量伪装（需 ≥3.28.0），本次不会写入 trafficPattern；如需启用请先选 3) 升级' \
    'Current mita does not support traffic obfuscation (needs >=3.28.0); trafficPattern will be skipped. Use 3) Upgrade to enable.')"
}

# 输出缩进后的 "trafficPattern": {...} 片段；off 或旧版 mita 时输出空
traffic_pattern_json() {
  local ind="${1:-  }"
  local level seed
  level="$(normalize_traffic_pattern "${TRAFFIC_PATTERN:-conservative}")"
  [ "$level" = "off" ] && return 0
  mita_supports_traffic_pattern || return 0
  seed="${TRAFFIC_SEED:-0}"
  if [ "$level" = "aggressive" ]; then
    cat <<EOF
${ind}"trafficPattern": {
${ind}  "seed": ${seed},
${ind}  "unlockAll": true,
${ind}  "tcpFragment": { "enable": true, "maxSleepMs": 8 },
${ind}  "nonce": { "type": "NONCE_TYPE_PRINTABLE", "applyToAllUDPPacket": true, "minLen": 6, "maxLen": 12 },
${ind}  "padding": { "maxMiddlePaddingLen": 64, "maxEndPaddingLen": 255 }
${ind}}
EOF
  else
    cat <<EOF
${ind}"trafficPattern": {
${ind}  "seed": ${seed},
${ind}  "unlockAll": false,
${ind}  "nonce": { "type": "NONCE_TYPE_PRINTABLE", "applyToAllUDPPacket": true, "minLen": 4, "maxLen": 8 },
${ind}  "padding": { "maxMiddlePaddingLen": 0, "maxEndPaddingLen": 128 }
${ind}}
EOF
  fi
}

# 去掉 trafficPattern 字段后另存一份（mita 过旧时降级应用）；成功打印新路径
strip_traffic_pattern() {
  local src="$1" out
  command -v python3 >/dev/null 2>&1 || return 1
  out="$(mktemp_file .json)"
  if python3 - "$src" "$out" <<'PY' 2>/dev/null
import json, sys
d = json.load(open(sys.argv[1]))
d.pop("trafficPattern", None)
json.dump(d, open(sys.argv[2], "w"), indent=2)
PY
  then
    printf '%s' "$out"
    return 0
  fi
  rm -f "$out" 2>/dev/null || true
  return 1
}

write_server_config() {
  # 多用户：从 users.json 生成（一用户一口）
  if [ "${MULTI_USER_MODE:-0}" -eq 1 ] && users_state_exists && [ "$(users_count)" -gt 0 ]; then
    write_server_config_multi
    return
  fi
  local cfg bindings="" proto pp tp tp_section=""
  cfg="$(mktemp_file .json)"
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
      "name": "${USERNAME}",
      "password": "${PASSWORD}"
    }
  ],
  "loggingLevel": "INFO",
  "mtu": ${MTU}${tp_section}
}
EOF
  printf '%s' "$cfg"
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
  local bin attempt
  bin="$(mita_bin)"
  ensure_mita_daemon
  if ! wait_mita_socket 45; then
    warn "$(t 'mita 管理进程未就绪，正在重试 apply config...' \
      'mita management daemon not ready, retrying apply config...')"
    mita_log_tail
  fi
  for attempt in 1 2 3 4 5; do
    if "$bin" apply config "$cfg" 2>/dev/null; then
      rm -f "$cfg"
      return 0
    fi
    ensure_mita_daemon
    wait_mita_socket 10 || true
    sleep 2
  done
  # 兜底：若配置含 trafficPattern 且仍失败，可能是 mita 版本过旧不识别该字段，
  # 自动去掉 trafficPattern 后降级应用其余配置，避免整装失败。
  if grep -q '"trafficPattern"' "$cfg" 2>/dev/null; then
    local stripped
    stripped="$(strip_traffic_pattern "$cfg" || true)"
    if [ -n "$stripped" ] && "$bin" apply config "$stripped" 2>/dev/null; then
      warn "$(t '当前 mita 不支持流量伪装(trafficPattern)，已忽略该设置并应用其余配置；如需启用请升级 mita(选 3)。' \
        'This mita build does not support trafficPattern; applied config without it. Upgrade mita (option 3) to enable.')"
      rm -f "$cfg" "$stripped"
      return 0
    fi
    rm -f "$stripped" 2>/dev/null || true
  fi
  "$bin" apply config "$cfg" || die "$(t '应用配置失败' 'Failed to apply config')"
  rm -f "$cfg"
}

collect_ports_from_mita() {
  local saved_protocol="" saved_port="" saved_port_range=""
  if [ -f "$MITA_STATE" ]; then
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
        print(f"{proto}|{binding['port']}")
    elif binding.get("portRange"):
        print(f"{proto}|{binding['portRange']}")
' 2>/dev/null || true
    return 0
  fi
  local line proto p
  while IFS= read -r line; do
    proto="$(printf '%s' "$line" | sed -n 's/.*"protocol"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
    p="$(printf '%s' "$line" | sed -n 's/.*"port"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p')"
    [ -z "$p" ] && p="$(printf '%s' "$line" | sed -n 's/.*"portRange"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
    [ -n "$proto" ] && [ -n "$p" ] && printf '%s|%s\n' "$proto" "$p"
  done < <(printf '%s' "$desc" | grep -E '"port"|"portRange"|"protocol"')
}

close_firewall_for_bindings() {
  local bindings="$1"
  local fw="" pp proto p proto_lc
  [ -n "$bindings" ] || return 0

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
    case "$fw" in
      ufw) run ufw delete allow "$(ufw_rule_spec "$p" "$proto_lc")" 2>/dev/null || true ;;
      firewalld) run firewall-cmd --permanent --remove-port="${p}/${proto_lc}" 2>/dev/null || true ;;
      iptables) iptables_accept_port "$p" "$proto_lc" del ;;
    esac
  done <<< "$bindings"

  case "$fw" in
    firewalld) run firewall-cmd --reload 2>/dev/null || true ;;
    iptables) persist_iptables_rules ;;
  esac
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
  if [[ "$p" == *-* ]]; then
    local start end port
    start="${p%-*}"
    end="${p#*-}"
    port="$start"
    while [ "$port" -le "$end" ]; do
      if [ "$action" = add ]; then
        run iptables -C INPUT -p "$proto" --dport "$port" -j ACCEPT 2>/dev/null \
          || run iptables -I INPUT -p "$proto" --dport "$port" -j ACCEPT || true
      else
        run iptables -D INPUT -p "$proto" --dport "$port" -j ACCEPT 2>/dev/null || true
      fi
      port=$((port + 1))
    done
  else
    if [ "$action" = add ]; then
      run iptables -C INPUT -p "$proto" --dport "$p" -j ACCEPT 2>/dev/null \
        || run iptables -I INPUT -p "$proto" --dport "$p" -j ACCEPT || true
    else
      run iptables -D INPUT -p "$proto" --dport "$p" -j ACCEPT 2>/dev/null || true
    fi
  fi
}

persist_iptables_rules() {
  if [ -d /etc/iptables ] || [ -f /etc/alpine-release ]; then
    run mkdir -p /etc/iptables
    run iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
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
    case "$fw" in
      ufw) run ufw allow "$(ufw_rule_spec "$p" "$proto_lc")" || true ;;
      firewalld) run firewall-cmd --permanent --add-port="${p}/${proto_lc}" || true ;;
      iptables) iptables_accept_port "$p" "$proto_lc" add ;;
    esac
  done < <(port_protocol_pairs)

  case "$fw" in
    firewalld) run firewall-cmd --reload || true ;;
    iptables) persist_iptables_rules ;;
  esac
}

close_firewall() {
  STAGE="清理防火墙规则"
  local desc bindings bin
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
    case "$fw" in
      ufw) run ufw delete allow "$(ufw_rule_spec "$p" "$proto_lc")" 2>/dev/null || true ;;
      firewalld) run firewall-cmd --permanent --remove-port="${p}/${proto_lc}" 2>/dev/null || true ;;
      iptables) iptables_accept_port "$p" "$proto_lc" del ;;
    esac
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

public_ip() {
  curl -fsSL --connect-timeout 5 --max-time 10 https://checkip.amazonaws.com 2>/dev/null \
    || curl -fsSL --connect-timeout 5 --max-time 10 https://api.ip.sb/ip 2>/dev/null \
    || hostname -I 2>/dev/null | awk '{print $1}'
}

start_mita() {
  STAGE="启动服务"
  local sm bin attempt
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
  for attempt in 1 2 3 4 5; do
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
}

verify_mita_running() {
  STAGE="验证服务状态"
  local bin status_out attempt
  bin="$(mita_bin)"
  for attempt in 1 2 3 4 5; do
    sleep 2
    status_out="$("$bin" status 2>/dev/null || true)"
    if printf '%s' "$status_out" | grep -q 'status is "RUNNING"'; then
      t 'mita 服务运行正常' 'mita service is running'
      return 0
    fi
    ensure_mita_daemon
    wait_mita_socket 10 || true
    "$bin" start 2>/dev/null || true
  done
  warn "$(t "mita 未处于 RUNNING 状态，请执行: $(mita_restart_hint) && mita status && mita start" \
    "mita is not RUNNING; run: $(mita_restart_hint) && mita status && mita start")"
  [ -n "$status_out" ] && msg "$status_out"
  return 0
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

enable_tcp_bbr() {
  STAGE="启用 TCP BBR"
  if [ -f /etc/alpine-release ] && ! command -v python3 >/dev/null 2>&1; then
    run apk add --no-cache python3 2>/dev/null || true
  fi
  local url="https://raw.githubusercontent.com/${UPSTREAM_REPO}/refs/heads/main/tools/enable_tcp_bbr.py"
  local tmp
  tmp="$(mktemp_file .py)"
  curl -fsSL -o "$tmp" "$url"
  chmod +x "$tmp"
  if command -v python3 >/dev/null 2>&1; then
    run python3 "$tmp"
  else
    warn "$(t '未找到 python3，跳过 BBR 配置' 'python3 not found, skipping BBR')"
  fi
  rm -f "$tmp"
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

generate_share_link_for() {
  local ip="$1"
  local proto="$2"
  local enc_user enc_pass p host query port_q=""
  enc_user="$(urlencode "$USERNAME")"
  enc_pass="$(urlencode "$PASSWORD")"
  p="$(port_for_protocol "$proto")"
  # 单端口：只写在 authority（@ip:port），query 不再重复 port=
  # 端口段：authority 仅 IP，query 用 port=range（官方 simple 链接约定）
  # BOTH 时 print_protocol_outputs 会为 TCP/UDP 各生成一条链接，每条仍只有一个端口
  if [ -n "$PORT" ]; then
    host="${ip}:${p}"
  else
    host="$ip"
    port_q="&port=${p}"
  fi
  query="handshake-mode=HANDSHAKE_STANDARD&mtu=${MTU}&multiplexing=${MULTIPLEXING}${port_q}&profile=default&protocol=${proto}"
  printf 'mierus://%s:%s@%s?%s' "$enc_user" "$enc_pass" "$host" "$query"
}

build_client_json_for() {
  local ip="$1"
  local proto="$2"
  local p binding tp tp_section=""
  p="$(port_for_protocol "$proto")"
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
        "name": "${USERNAME}",
        "password": "${PASSWORD}"
      },
      "servers": [
        {
          "ipAddress": "${ip}",
          "domainName": "",
          "portBindings": [
${binding}
          ]
        }
      ],
      "mtu": ${MTU},
      "multiplexing": {
        "level": "${MULTIPLEXING}"
      },
      "handshakeMode": "HANDSHAKE_STANDARD"${tp_section}
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
  local p port_lines name_suffix
  p="$(port_for_protocol "$proto")"
  name_suffix="$(proto_lower "$proto")"
  if [ -n "$PORT" ]; then
    port_lines="    port: ${p}"
  else
    port_lines="    port-range: ${p}"
  fi
  cat <<EOF
  - name: mieru-mita-${name_suffix}
    type: mieru
    server: ${ip}
${port_lines}
    transport: ${proto}
    udp: true
    username: ${USERNAME}
    password: ${PASSWORD}
    multiplexing: ${MULTIPLEXING}
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

print_protocol_outputs() {
  local ip="$1"
  local proto link cfg_path ts suffix multi=0 count
  ts="$(date +%Y%m%d_%H%M%S)"
  count="$(protocol_output_count)"
  if [ "$count" -gt 1 ]; then
    multi=1
  fi
  while IFS= read -r proto; do
    [ -n "$proto" ] || continue
    suffix="$(proto_lower "$proto")"
    msg ""
    if [ "$multi" -eq 1 ]; then
      t "【${proto} 节点链接】" "[${proto} share link]"
    else
      t '【节点链接】' '[Share link]'
    fi
    link="$(generate_share_link_for "$ip" "$proto")"
    msg "$link"
    if [ "$multi" -eq 1 ]; then
      cfg_path="/root/mieru_client_${suffix}_${ts}.json"
    else
      cfg_path="/root/mieru_client_${ts}.json"
    fi
    msg ""
    if [ "$multi" -eq 1 ]; then
      t "【${proto} 客户端 JSON】（供 mieru 客户端使用，勿在服务器 mita apply）" \
        "[${proto} client JSON] (for mieru client only — do NOT mita apply on server)"
    else
      t '【客户端 JSON 配置】（供 mieru 客户端使用，勿在服务器 mita apply）' \
        '[Client JSON] (for mieru client only — do NOT mita apply on server)'
    fi
    if [ "$DRY_RUN" -ne 1 ]; then
      build_client_json_for "$ip" "$proto" >"$cfg_path"
      t "  已保存: ${cfg_path}" "  Saved:  ${cfg_path}"
    fi
    msg ""
    build_client_json_for "$ip" "$proto"
  done < <(protocols_for_mode)
}

print_summary() {
  local ip
  ip="$(public_ip || true)"
  msg ""
  t '========== 安装完成 ==========' '========== Installation complete =========='
  if [ -n "$ip" ]; then
    print_protocol_outputs "$ip"
  else
    warn "$(t '未能获取公网 IP，请手动将下方连接信息填入客户端' \
      'Could not detect public IP; use connection info below manually')"
  fi
  msg ""
  t '【连接信息】' '[Connection info]'
  t "  服务器: ${ip:-<未知>}" "  Server:   ${ip:-<unknown>}"
  t "  用户名: ${USERNAME}" "  Username: ${USERNAME}"
  t "  密码:   ${PASSWORD}" "  Password: ${PASSWORD}"
  t "  协议:   $(protocol_label)" "  Protocol: $(protocol_label)"
  t "  流量伪装: $(traffic_label)" "  Obfuscation: $(traffic_label)"
  if [ -n "$PORT" ]; then
    if [ "$PROTOCOL" = "BOTH" ]; then
      t "  端口:   TCP ${PORT} / UDP $((PORT + 1))" "  Ports:    TCP ${PORT} / UDP $((PORT + 1))"
    else
      t "  端口:   ${PORT}" "  Port:     ${PORT}"
    fi
  else
    t "  端口段: ${PORT_RANGE}" "  Port range: ${PORT_RANGE}"
  fi
  msg ""
  t '导入方式:' 'Import options:'
  if [ "$PROTOCOL" = "BOTH" ]; then
    msg '  mieru import config "<TCP 节点链接>"   # 或分别导入 TCP / UDP 链接'
    msg '  mieru apply config /root/mieru_client_tcp_*.json'
    msg '  mieru apply config /root/mieru_client_udp_*.json'
  else
    msg '  mieru import config "<节点链接>"   # 简单链接不含 socks5Port，全新设备建议用 JSON'
    msg '  mieru apply config /root/mieru_client_*.json'
  fi
  if [ "$PROTOCOL" = "BOTH" ]; then
    msg ''
    t '【客户端提示】双协议已分开输出：TCP 与 UDP 各用对应链接/JSON；' \
      '[Client tip] Dual protocol outputs are split: use matching TCP or UDP link/JSON.'
    t '  v2rayN 导入后传输协议选 **tcp** 或 **udp**（勿选「两个都」）。' \
      '  In v2rayN pick transport **tcp** or **udp** (not "both").'
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
  ip="$(public_ip || echo 'YOUR_SERVER_IP')"
  msg ""
  t '========== 节点链接与客户端配置 ==========' \
    '========== Share links & client config =========='
  print_protocol_outputs "$ip"
  msg ""
  t '【导入方式】' '[How to import]'
  if [ "$PROTOCOL" = "BOTH" ]; then
    msg '  mieru import config "<TCP 节点链接>"   # TCP / UDP 各用对应链接'
    msg '  mieru apply config /root/mieru_client_tcp_*.json'
    msg '  mieru apply config /root/mieru_client_udp_*.json'
  else
    msg '  mieru import config "<节点链接>"   # 一键导入（简单链接）'
    msg '  mieru apply config /root/mieru_client_*.json   # 完整 JSON（含 socks5 端口）'
  fi
  msg ""
  t '说明: 上方 mierus:// 为分享链接；JSON 为 mieru **客户端**配置（在电脑/手机导入，勿在服务器 mita apply）' \
    'Note: mierus:// is the share link; JSON is for mieru **client** on your device — do NOT mita apply on server'
  msg ""
  t '【Clash / mihomo 配置片段】' '[Clash / mihomo snippet]'
  build_clash_yaml_full "$ip"
  cloud_firewall_hint
}

do_install() {
  require_root
  require_linux
  require_cmd curl

  local pm arch ver url pkg tmp cfg
  pm="$(detect_pkg_manager)"
  arch="$(detect_arch)"

  if mita_installed; then
    local cur
    cur="$(installed_version || true)"
    t "检测到已安装 mita ${cur:-未知版本}" "mita already installed (${cur:-unknown})"
    t '如需改端口/密码/协议，请选菜单「重新配置」或执行: install-mita reconfigure' \
      'To change port/password/protocol, use menu Reconfigure or: install-mita reconfigure'
    if ! confirm '继续将重新下载安装包并覆盖配置？[y/N]: ' \
      'Continue full reinstall (re-download package)? [y/N]: ' n; then
      [ "${MENU_MODE:-0}" -eq 1 ] && return 0
      exit 0
    fi
  fi

  if [ "$YES" -eq 1 ]; then
    ensure_config_noninteractive
  else
    collect_config_interactive
  fi

  ver="$(query_latest_version)"
  url="$(package_url "$ver" "$pm" "$arch")"
  tmp="$(mktemp_file)"
  download_package "$url" "$tmp"
  install_package "$tmp" "$pm"
  rm -f "$tmp"
  ensure_mita_daemon
  wait_mita_socket 30 || true

  add_op_user "$OP_USER"
  warn_traffic_unsupported
  cfg="$(write_server_config)"
  apply_config "$cfg"
  open_firewall
  start_mita
  verify_mita_running
  install_self_script
  save_install_state
  # 阶段1：安装后写入 users.json，便于后续加用户
  users_migrate_from_primary 2>/dev/null || true

  if [ "$ENABLE_BBR" -eq 1 ]; then
    enable_tcp_bbr
  elif confirm '是否启用 TCP BBR？[y/N]: ' 'Enable TCP BBR? [y/N]: ' n; then
    enable_tcp_bbr
  fi

  print_summary
}

do_reconfigure() {
  require_root
  require_linux
  mita_installed || die "$(t 'mita 未安装，请先执行安装' 'mita is not installed; run install first')"

  local old_bindings desc bin cfg
  bin="$(mita_bin)"
  desc="$("$bin" describe config 2>/dev/null || true)"
  old_bindings="$(extract_bindings_from_describe "$desc")"

  if [ "$YES" -eq 1 ]; then
    load_config_from_mita
    ensure_config_noninteractive
  else
    collect_reconfigure_interactive
  fi

  ensure_mita_daemon
  wait_mita_socket 30 || true
  close_firewall_for_bindings "$old_bindings"
  warn_traffic_unsupported
  # 多用户：协议全局更新；仅当用户显式改了主用户名/密码/端口时同步「主用户」
  # 主用户 = install-state 中的 USERNAME，找不到则 users[0]
  if users_state_exists && [ "$(users_count)" -gt 0 ]; then
    MULTI_USER_MODE=1
    admin_lock_acquire
    _U_NAME="$USERNAME" _U_PASS="$PASSWORD" _U_PORT="$PORT" _U_PROTO="$PROTOCOL"
    _U_PRIMARY="${USERNAME}"
    users_py_locked '
import json, os, time
path = os.environ["MITA_USERS_STATE"]
d = json.load(open(path))
name = os.environ.get("_U_NAME") or ""
password = os.environ.get("_U_PASS") or ""
port = os.environ.get("_U_PORT") or ""
proto = os.environ.get("_U_PROTO") or "TCP"
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
    u["updated_at"] = int(time.time())
d["protocol"] = proto
json.dump(d, open(path, "w"), indent=2)
' || {
      local prc=$?
      admin_lock_release
      if [ "$prc" -eq 2 ]; then
        die "$(t '新用户名与其它用户冲突' 'New username conflicts with another user')"
      elif [ "$prc" -eq 3 ]; then
        die "$(t '新端口已被其它用户占用' 'New port already used by another user')"
      fi
      die "$(t '更新多用户状态失败' 'Failed to update multi-user state')"
    }
    # 协议变更时所有用户 portBindings 随 PROTOCOL 重建；端口仅主用户可能变
    if ! apply_users_config; then
      admin_lock_release
      return 1
    fi
    open_firewall
    start_mita
    verify_mita_running
    save_install_state
    admin_lock_release
  else
    users_migrate_from_primary 2>/dev/null || true
    cfg="$(write_server_config)"
    apply_config "$cfg"
    open_firewall
    start_mita
    verify_mita_running
    save_install_state
  fi
  msg ""
  t '========== 重新配置完成 ==========' '========== Reconfigure complete =========='
  if users_state_exists && [ "$(users_count)" -gt 1 ]; then
    t '提示: 多用户模式下「重新配置」只改主用户凭据/端口与全局协议；其它用户端口不变' \
      'Note: multi-user reconfigure updates primary user + global protocol only; other ports unchanged'
  fi
  print_summary
}

do_upgrade() {
  require_root
  require_linux
  require_cmd curl
  local pm arch ver url tmp
  pm="$(detect_pkg_manager)"
  arch="$(detect_arch)"
  ver="$(query_latest_version)"
  local cur
  cur="$(installed_version || true)"
  if version_is_current "$cur" "$ver"; then
    install_self_script
    t "管理脚本已更新至 v${SCRIPT_VERSION}（mita 二进制 ${cur} 已是最新）" \
      "Manager script updated to v${SCRIPT_VERSION} (mita binary ${cur} is already latest)"
    [ "${MENU_MODE:-0}" -eq 1 ] && return 0
    exit 0
  fi
  url="$(package_url "$ver" "$pm" "$arch")"
  tmp="$(mktemp_file)"
  download_package "$url" "$tmp"
  install_package "$tmp" "$pm"
  rm -f "$tmp"
  install_self_script
  run "$(mita_bin)" reload 2>/dev/null || start_mita
  verify_mita_running
  t "已升级至 ${ver}" "Upgraded to ${ver}"
}

remove_mita_common() {
  local bin
  bin="$(mita_bin)"
  run "$bin" stop 2>/dev/null || true
  case "$(service_manager)" in
    systemd)
      run systemctl stop mita 2>/dev/null || true
      run systemctl disable mita 2>/dev/null || true
      ;;
    openrc)
      run rc-service mita stop 2>/dev/null || true
      run rc-update del mita default 2>/dev/null || true
      ;;
  esac
  run rm -f /var/log/mita.log /var/log/mita.err
  run rm -f /root/mieru_client_*.json /root/mieru_client_tcp_*.json /root/mieru_client_udp_*.json 2>/dev/null || true
  remove_users_scheduler 2>/dev/null || true
  run rm -f "$MITA_LOGROTATE_CONF" 2>/dev/null || true
  run rm -rf /etc/mita /var/lib/mita /var/run/mita /var/run/mita.sock
  run rm -f "$MITA_BIN" "$MITA_REAL_BIN" /usr/bin/mita-real "$MITA_MARKER" "$OPENRC_SVC"
  run rm -f "$MITA_USERS_LOG" 2>/dev/null || true
  if ! command -v dpkg >/dev/null 2>&1 || ! dpkg -l mita 2>/dev/null | grep -q '^ii'; then
    run rm -f /usr/bin/mita
  fi
  run rm -f /lib/systemd/system/mita.service /usr/lib/systemd/system/mita.service "$SYSTEMD_SVC"
  run rm -f /etc/sysctl.d/mieru_tcp_bbr.conf
  run systemctl daemon-reload 2>/dev/null || true
  remove_self_script
  if _has_user mita; then
    run deluser mita 2>/dev/null || run userdel mita 2>/dev/null || true
  fi
  if _has_group mita; then
    run delgroup mita 2>/dev/null || run groupdel mita 2>/dev/null || true
  fi
}

do_uninstall() {
  require_root
  mita_installed || die "$(t 'mita 未安装' 'mita is not installed')"
  if ! installed_by_oneclick; then
    warn "$(t '未检测到本脚本安装标记；若仅使用官方 deb/rpm，卸载范围可能不同' \
      'OneClick install marker not found; official package uninstall may differ')"
    if ! confirm '仍要继续卸载？[y/N]: ' 'Continue uninstall anyway? [y/N]: ' n; then
      [ "${MENU_MODE:-0}" -eq 1 ] && return 0
      exit 0
    fi
  fi
  if ! confirm '确认卸载 mita、管理脚本及全部配置？[y/N]: ' \
    'Uninstall mita, manager script, and all config? [y/N]: ' n; then
    [ "${MENU_MODE:-0}" -eq 1 ] && return 0
    exit 0
  fi
  local pm
  pm="$(detect_pkg_manager)"
  close_firewall
  case "$pm" in
    deb) run dpkg -P mita 2>/dev/null || true ;;
    rpm) run rpm -e mita 2>/dev/null || true ;;
    alpine) ;;
  esac
  remove_mita_common
  t 'mita 及安装脚本已完全卸载' 'mita and install script fully removed'
}

do_status() {
  local bin sm status_out recovered=0
  bin="$(mita_bin)"
  sm="$(service_manager)"
  if ! mita_installed; then
    t 'mita 未安装' 'mita is not installed'
    [ "${MENU_MODE:-0}" -eq 1 ] && return 1
    exit 1
  fi
  msg ""
  "$bin" version 2>/dev/null || true
  msg ""
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
  "$bin" describe config 2>/dev/null || true
}

do_client_config() {
  require_root
  mita_installed || bail "$(t 'mita 未安装' 'mita is not installed')" || return 1
  repair_mita_binary_paths 2>/dev/null || true
  ensure_mita_daemon
  wait_mita_socket 20 || warn "$(t 'mita 守护进程未就绪，正在尝试继续...' 'mita daemon not ready, trying anyway...')"
  load_config_from_mita || return 1
  generate_client_config
}

do_start() {
  require_root || return 1
  mita_installed || bail "$(t 'mita 未安装，请先安装' 'mita is not installed')" || return 1
  repair_mita_binary_paths 2>/dev/null || true
  start_mita
  verify_mita_running
  t 'mita 服务已启动' 'mita service started'
}

do_stop() {
  require_root || return 1
  mita_installed || bail "$(t 'mita 未安装' 'mita is not installed')" || return 1
  local bin sm
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
  local sm
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
  verify_mita_running
  t 'mita 服务已重启' 'mita service restarted'
}

menu_pause() {
  local _ignore=""
  msg ""
  read_tty _ignore "$(t '按回车返回主菜单...' 'Press Enter to return to the menu...')" || true
}

menu_run_action() {
  local rc=0
  case "$ACTION" in
    install) do_install || rc=1 ;;
    reconfigure) do_reconfigure || rc=1 ;;
    upgrade) do_upgrade || rc=1 ;;
    uninstall)
      if do_uninstall; then
        mita_installed || return 2
      else
        rc=1
      fi
      ;;
    status) do_status || rc=1 ;;
    client-config) do_client_config || rc=1 ;;
    start) do_start || rc=1 ;;
    stop) do_stop || rc=1 ;;
    restart) do_restart || rc=1 ;;
    user-list) do_user_list || rc=1 ;;
    user-add) do_user_add || rc=1 ;;
    user-del) do_user_del || rc=1 ;;
    user-show) do_user_show || rc=1 ;;
    user-manage) do_user_manage || rc=1 ;;
    user-set-quota) do_user_set_quota || rc=1 ;;
    user-set-expire) do_user_set_expire || rc=1 ;;
    user-enable) do_user_enable || rc=1 ;;
    user-disable) do_user_disable || rc=1 ;;
    user-scan) do_user_scan || rc=1 ;;
    user-quota-reset)
      if [ "${YES:-0}" -eq 1 ]; then
        do_user_quota_reset force || rc=1
      else
        do_user_quota_reset || rc=1
      fi
      ;;
    user-set-rate) do_user_set_rate || rc=1 ;;
    rate-status) do_rate_status || rc=1 ;;
    rate-restore) do_rate_restore || rc=1 ;;
    user-usage) do_user_usage || rc=1 ;;
    user-export-clients) do_user_export_clients || rc=1 ;;
    user-backup) do_user_backup || rc=1 ;;
    user-restore) do_user_restore || rc=1 ;;
    user-export) do_user_export || rc=1 ;;
    user-import) do_user_import || rc=1 ;;
    doctor) do_doctor || rc=1 ;;
    help) usage; rc=0 ;;
    *) warn "$(t '未知操作' 'Unknown action')"; return 1 ;;
  esac
  return "$rc"
}

menu_loop() {
  MENU_MODE=1
  trap - ERR
  # 仅当已安装(或半装/损坏状态)时才做二进制修复。否则在「全新系统」上，repair_mita_binary_paths
  # 会因找不到二进制而走 recover_deb_mita → reinstall_mita_package，在显示菜单前就「自动重下安装」mita，
  # 随后用户选「1) 新装安装」时便被误判「检测到已安装」。修复必须放进 mita_installed 守卫内（与非交互路径一致）。
  if mita_installed; then
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
    if menu_run_action; then
      :
    else
      local rc=$?
      if [ "$rc" -eq 2 ]; then
        break
      fi
      warn "$(t '操作未完成，请重试或选 5) 状态 排查' 'Action failed; retry or use 5) Status')"
    fi
    menu_pause
  done
}

show_menu() {
  if [ "${MENU_SCRIPTS_READY:-0}" -eq 0 ] && mita_installed; then
    ensure_management_scripts || true
    MENU_SCRIPTS_READY=1
  fi
  print_banner
  msg "  1) 新装 / 安装"
  msg "  2) 重新配置（端口 / 密码 / 协议）"
  msg "  3) 升级"
  msg "  4) 卸载"
  msg "  5) 状态"
  msg "  6) 查看节点链接 / 客户端配置"
  msg "  7) 启动服务"
  msg "  8) 停止服务"
  msg "  9) 重启服务"
  msg "  10) 用户管理（增删 / 套餐 / 限速）"
  msg "  11) 一键验收 doctor"
  msg "  12) 退出"
  msg ""
  t '快捷命令: 直接输入 mita 打开菜单（不区分大小写）' \
    'Quick command: type mita to open menu (case-insensitive)'
  msg ""
  local choice=""
  read_tty choice "$(t '请选择 [1-12]: ' 'Choose [1-12]: ')" || choice=""
  choice="$(printf '%s' "$choice" | tr -d '[:space:]')"
  if [ -z "$choice" ]; then
    warn "$(t '请输入 1-12' 'Enter 1-12')"
    return 1
  fi
  case "$choice" in
    1) ACTION=install ;;
    2) ACTION=reconfigure ;;
    3) ACTION=upgrade ;;
    4) ACTION=uninstall ;;
    5) ACTION=status ;;
    6) ACTION=client-config ;;
    7) ACTION=start ;;
    8) ACTION=stop ;;
    9) ACTION=restart ;;
    10) ACTION=user-manage ;;
    11) ACTION=doctor ;;
    12) return 2 ;;
    *)
      warn "$(t '无效选择，请输入 1-12' 'Invalid choice, enter 1-12')"
      return 1
      ;;
  esac
  return 0
}

main() {
  if [ -z "$ACTION" ]; then
    menu_loop
    exit 0
  fi
  if [ "$(id -u 2>/dev/null || echo 1)" -eq 0 ] && mita_installed; then
    repair_mita_binary_paths 2>/dev/null || true
  fi
  if [ "$ACTION" != "menu" ]; then
    print_banner
  fi
  case "$ACTION" in
    install) do_install ;;
    reconfigure) do_reconfigure ;;
    upgrade) do_upgrade ;;
    uninstall) do_uninstall ;;
    status) do_status ;;
    client-config|show) do_client_config ;;
    start) do_start ;;
    stop) do_stop ;;
    restart) do_restart ;;
    user-list) do_user_list ;;
    user-add) do_user_add ;;
    user-del) do_user_del ;;
    user-show) do_user_show ;;
    user-manage) do_user_manage ;;
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
