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
  t "作者: ${SCRIPT_AUTHOR} / https://github.com/${SCRIPT_REPO}" \
    "Author: ${SCRIPT_AUTHOR} / https://github.com/${SCRIPT_REPO}"
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
