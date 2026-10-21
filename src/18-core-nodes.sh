# ---------- NoBrand Common Core: 入口、节点聚合、状态、Doctor、备份 ----------

nobrand_print_banner() {
  msg ""
  msg '========================================'
  printf '          %s v%s\n' "$SCRIPT_NAME" "$SCRIPT_VERSION"
  msg '========================================'
  t "作者: ${SCRIPT_AUTHOR}" "Author: ${SCRIPT_AUTHOR}"
}

nobrand_version() {
  printf '%s %s\n%s: %s\n' "$SCRIPT_NAME" "$SCRIPT_VERSION" \
    "$(t '作者' 'Author')" "$SCRIPT_AUTHOR"
}

nobrand_usage() {
  cat <<EOF
NoBrand-OneClick 3.2.6 — Multi-Ingress / Mieru / Snell v4-v5 / Hysteria2 / TUIC v5 / VLESS REALITY / VLESS + FinalMask + Sudoku / SSH Tunnel / Port Forward

用法:
  nobrand                         打开统一菜单
  nb                              与 nobrand 完全相同的短别名
  nobrand --version               显示产品版本与作者
  nobrand --help                  显示本帮助
  nobrand status                  综合状态
  nobrand nodes [--protocol P]    查看全部或指定协议节点
  nobrand doctor                  综合诊断（默认不输出 secret）
  nobrand runtime capabilities    查看固定 rc.4 的能力与限制
  nobrand runtime status|doctor|plan|recover|rollback
  nobrand runtime apply|render --file DESIRED.json
  nobrand runtime backup|restore --file BACKUP.tar.gz
  nobrand runtime start|stop|restart|uninstall|purge
  nobrand ingress list|doctor     查看入口配置或执行只读 Ingress Doctor
  nobrand ingress show PROFILE    查看入口配置
  nobrand ingress add             新增 public/mapped 入口配置
  nobrand ingress modify|delete PROFILE
  nobrand ingress set-default PROFILE | unset-default
  nobrand backup create [FILE]    备份 NoBrand schema-v3 全部 state 与配置
  nobrand backup restore FILE     恢复 NoBrand 备份
  nobrand uninstall [-y]          统一卸载 Mieru/Snell/HY2/TUIC/VLESS/SSH/Forward/Common
  nobrand manager install|upgrade 从当前执行的 exact installer 安装/升级统一管理器

  nobrand mieru                    打开完整 Mieru 菜单
  nobrand mieru install|reconfigure|upgrade|uninstall|start|stop|restart
  nobrand mieru status|doctor|perf|show|users
  nobrand mieru user-add|user-del|user-show|user-set-endpoint
  Mieru 参数: --port --protocol --profile --advertise-host --advertise-port --advertise-auto
    user-add 可在交互中选择自动/自定义展示入口；--advertise-host 可省略展示端口并继承新用户的有效端口。
    --ingress-profile PROFILE
    --mtu --traffic-pattern --low-entropy --multiplexing --handshake-mode

  nobrand snell install --name NAME [--version 5|4] [--port PORT] [--quic off]
      [--advertise-host HOST --advertise-port PORT | --advertise-auto] [-y]
  nobrand snell show|status|doctor|start|stop|restart|remove [--name NAME]
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

  nobrand vless-reality install --name NAME [--target HOST] [--target-port PORT]
      [--ingress-profile PROFILE] [--port PORT]
      [--advertise-host HOST --advertise-port PORT | --advertise-auto] [-y]
      默认 cover 为 www.microsoft.com:443；可显式设置可用的 TLS 1.3 cover。
      显式域名会按原值使用；域名与伪装目标端口可分别配置。
      443 是默认伪装目标端口，不是公开 REALITY 监听端口。
  nobrand vless-reality show|export|status|doctor|start|stop|restart|remove [--name NAME]
  nobrand vless-reality set-endpoint --name NAME
      [--advertise-host HOST --advertise-port PORT | --advertise-auto]

  nobrand tuic install --name NAME --user USER [--port PORT] [--sni SNI]
      [--advertise-host HOST --advertise-port PORT | --advertise-auto] [-y]
  nobrand tuic start|stop|restart|status|doctor|show|export|set-endpoint|upgrade-runtime|uninstall
  nobrand tuic user add|delete|list|show|rotate --name NAME [--user USER]

  nobrand ssh install --user USER
      [--advertise-host HOST --advertise-port PORT | --advertise-auto] [-y]
  nobrand ssh status|doctor|show|export|set-endpoint|uninstall
  nobrand ssh user add|delete|list|show|rotate-key [--user USER]
  nobrand ssh confirm-admin --token TOKEN

  nobrand forward add --name NAME --backend nftables|realm --protocol TCP|UDP|BOTH
      --listen 0.0.0.0 --port PORT --target HOST --target-port PORT
  nobrand forward list|doctor|export
  nobrand forward show|delete|modify|enable|disable|set-endpoint|switch-backend RULE
  nobrand forward import FILE

说明:
  - Snell 只支持 v5（默认/推荐）与 v4（兼容）。
  - 普通代理由一个固定 Splicore v0.3.0-rc.4 daemon 管理；Release Candidate / Experimental。
  - 新架构要求 clean install；旧 multi-core 安装只检测并拒绝，不支持原地迁移或新版卸载。
  - REALITY 使用原生 Local Tunnel Guard；HY2 使用新证书和独立 Salamander secret。
  - Mieru 新装可用 --profile iplc 或 --traffic-pattern off；默认 traffic off；balanced/stealth 不支持。
  - Display Endpoint 只影响客户端输出，不创建 DNAT/IPLC 转发，也不改 listener。
  - --advertise-host 接受 IPv4、IPv6 或 ASCII DNS hostname；Host 与 Port 分别填写，配置时不要求域名解析成功。
  - Display Endpoint 不配置 VPS 系统出站 IP、默认路由或 policy routing。
  - 非交互 -y 必须明确给出完整 Display Endpoint 或 --advertise-auto。
  - VLESS Sudoku = plain VLESS + FinalMask(sudoku) + TCP。
  - VLESS REALITY = VLESS + TCP + REALITY + xtls-rprx-vision；public Profile 推荐，mapped 仅警告。
  - VLESS Encryption: NOT USED；不调用密钥生成子命令，不保存加密密钥。
  - TUIC 只支持 v5：Splicore、UDP/QUIC、每用户独立 UUID + password。
  - SSH Tunnel 复用现有 sshd；允许 -L/-D/-R TCP forwarding，不允许 shell/exec/TTY/SFTP/SCP。
  - SSH Tunnel 使用 AllowTcpForwarding=yes，因此可访问服务器自身可达的 TCP destinations；GatewayPorts=no。
  - SSH Tunnel 不拥有 sshd listener、SSH firewall、host keys 或 admin authentication。
  - Port Forward: nftables 为 IPv4 kernel NAT；Realm 为 official userspace relay，可使用 IP/domain target。
  - Forward 的 Display Endpoint 仅为 metadata；xx00 对 nftables/Realm 和 TCP/UDP 均保留。
  - Ingress 决定端口策略、展示默认值和入口身份；Linux 系统路由继续独立决定 Egress。
  - Ingress Profile 不修改网卡、地址、路由、ip rule、sysctl、SSH 或 provider mapping。
  - PROTOCOL_FEATURE_FREEZE=${PROTOCOL_FEATURE_FREEZE}（VLESS REALITY 是 3.2 最后一个协议功能）。
  - 普通安装只下载固定 Splicore；FinalMask/Sudoku 保留已有专用 pinned Xray。
  - FinalMask/Sudoku 仍使用独立 pinned Xray；Splicore 不管理 Xray。
  - v3 state 必须带 schema_version=3；旧 state 不读取、不导入、不删除。
  - 正式安装器: ${NOBRAND_RELEASE_INSTALLER_URL}
EOF
}

nobrand_manager_source_valid() {
  local path="$1"
  [ -r "$path" ] && [ -f "$path" ] || return 1
  grep -qxF 'SCRIPT_NAME="NoBrand-OneClick"' "$path" 2>/dev/null \
    && grep -qxF 'SCRIPT_REPO="ike-sh/NoBrand-OneClick"' "$path" 2>/dev/null \
    && grep -qxF "SCRIPT_VERSION=\"${SCRIPT_VERSION}\"" "$path" 2>/dev/null
}

nobrand_manager_source_path() {
  if [ -n "${BASH_SOURCE[0]:-}" ] \
     && nobrand_manager_source_valid "${BASH_SOURCE[0]}"; then
    printf '%s' "${BASH_SOURCE[0]}"
  elif nobrand_manager_source_valid "$INSTALL_SCRIPT_PATH"; then
    printf '%s' "$INSTALL_SCRIPT_PATH"
  elif nobrand_manager_source_valid "$NOBRAND_INSTALL_SCRIPT_PATH"; then
    printf '%s' "$NOBRAND_INSTALL_SCRIPT_PATH"
  else
    return 1
  fi
}

nobrand_install_manager_script() {
  local source_path="" source_real="" destination_real="" link_tmp=""
  if [ "${DRY_RUN:-0}" -eq 1 ]; then
    t '[演练] 安装 NoBrand 管理器与 nobrand/nb 命令' \
      '[dry-run] install NoBrand manager and nobrand/nb commands'
    return 0
  fi
  source_path="$(nobrand_manager_source_path 2>/dev/null || true)"
  [ -n "$source_path" ] || {
    warn "$(t '找不到当前 NoBrand 单文件安装器，未安装统一快捷命令' \
      'Current NoBrand single-file installer not found; unified shortcuts were not installed')"
    return 1
  }
  source_real="$(readlink -f "$source_path" 2>/dev/null || realpath "$source_path" 2>/dev/null || printf '%s' "$source_path")"
  destination_real="$(readlink -f "$NOBRAND_INSTALL_SCRIPT_PATH" 2>/dev/null \
    || realpath "$NOBRAND_INSTALL_SCRIPT_PATH" 2>/dev/null || printf '%s' "$NOBRAND_INSTALL_SCRIPT_PATH")"
  if [ "$source_real" != "$destination_real" ]; then
    nb_atomic_install_file "$source_path" "$NOBRAND_INSTALL_SCRIPT_PATH" 0755 || return 1
  else
    chmod 0755 "$NOBRAND_INSTALL_SCRIPT_PATH" || return 1
  fi
  mkdir -p "$(dirname "$NOBRAND_COMMAND_PATH")" "$(dirname "$NOBRAND_SHORT_COMMAND_PATH")" \
    || return 1
  link_tmp="$(mktemp "${NOBRAND_COMMAND_PATH}.tmp.XXXXXX")" || return 1
  rm -f "$link_tmp"
  if ! ln -s "$NOBRAND_INSTALL_SCRIPT_PATH" "$link_tmp" \
     || ! mv -f "$link_tmp" "$NOBRAND_COMMAND_PATH"; then
    rm -f "$link_tmp"
    return 1
  fi
  link_tmp="$(mktemp "${NOBRAND_SHORT_COMMAND_PATH}.tmp.XXXXXX")" || return 1
  rm -f "$link_tmp"
  if ! ln -s "$NOBRAND_COMMAND_PATH" "$link_tmp" \
     || ! mv -f "$link_tmp" "$NOBRAND_SHORT_COMMAND_PATH"; then
    rm -f "$link_tmp"
    return 1
  fi
  cmp -s "$source_path" "$NOBRAND_INSTALL_SCRIPT_PATH" || return 1
  [ "$(readlink "$NOBRAND_COMMAND_PATH" 2>/dev/null || true)" = "$NOBRAND_INSTALL_SCRIPT_PATH" ] || return 1
  [ "$(readlink "$NOBRAND_SHORT_COMMAND_PATH" 2>/dev/null || true)" = "$NOBRAND_COMMAND_PATH" ] || return 1
}

nobrand_manager_installation_valid() {
  local installed="" version_line="" source_path="" source_real="" destination_real=""
  [ -x "$NOBRAND_INSTALL_SCRIPT_PATH" ] \
    && [ -L "$NOBRAND_COMMAND_PATH" ] && [ -L "$NOBRAND_SHORT_COMMAND_PATH" ] \
    || return 1
  [ "$(readlink "$NOBRAND_COMMAND_PATH" 2>/dev/null || true)" = "$NOBRAND_INSTALL_SCRIPT_PATH" ] \
    || return 1
  [ "$(readlink "$NOBRAND_SHORT_COMMAND_PATH" 2>/dev/null || true)" = "$NOBRAND_COMMAND_PATH" ] \
    || return 1
  installed="$(nb_installed_manager_version 2>/dev/null || true)"
  [ "$installed" = "$SCRIPT_VERSION" ] || return 1
  version_line="$("$NOBRAND_COMMAND_PATH" --version 2>/dev/null | sed -n '1p')" || return 1
  [ "$version_line" = "${SCRIPT_NAME} ${SCRIPT_VERSION}" ] || return 1
  source_path="$(nobrand_manager_source_path 2>/dev/null || true)"
  [ -n "$source_path" ] || return 1
  source_real="$(readlink -f "$source_path" 2>/dev/null \
    || realpath "$source_path" 2>/dev/null || printf '%s' "$source_path")"
  destination_real="$(readlink -f "$NOBRAND_INSTALL_SCRIPT_PATH" 2>/dev/null \
    || realpath "$NOBRAND_INSTALL_SCRIPT_PATH" 2>/dev/null \
    || printf '%s' "$NOBRAND_INSTALL_SCRIPT_PATH")"
  [ "$source_real" = "$destination_real" ] \
    || cmp -s "$source_path" "$NOBRAND_INSTALL_SCRIPT_PATH"
}

nobrand_manager_upgrade() {
  nobrand_manager_bootstrap \
    || die "$(t 'NoBrand 管理器安装/升级失败；协议状态未修改' \
      'NoBrand manager install/upgrade failed; protocol state was not modified')"
  t "NoBrand 统一管理器已从当前精确安装器安装/升级至 v${SCRIPT_VERSION}" \
    "NoBrand unified manager installed/upgraded from the current exact installer to v${SCRIPT_VERSION}"
}

nb_all_node_rows() {
  case "${1:-}" in
    ""|all) vless_sudoku_node_rows; ssh_tunnel_node_rows; forward_node_rows ;;
    vless-sudoku|sudoku|vless) vless_sudoku_node_rows ;;
    ssh|ssh-tunnel) ssh_tunnel_node_rows ;;
    forward|port-forward) forward_node_rows ;;
    mieru|snell|hy2|hysteria2|tuic|vless-reality|reality) return 0 ;;
    *) return 1 ;;
  esac
}

nb_owner_ingress_profile_id() {
  local owner="$1" id
  case "$owner" in
    splicore:*) jq -r --arg id "${owner#splicore:}" '.nodes[]|select(.id==$id)|.ingress.profile_id // empty' "${NOBRAND_STATE_DIR}/splicore/current/desired.json" ;;
    vless-sudoku:*) vless_sudoku_state_field ingress_profile_id 2>/dev/null || true ;;
    forward:*)
      jq -r --arg id "${owner#forward:}" '.rules[]|select(.rule_id==$id)|.ingress_profile_id // empty' \
        "$NOBRAND_FORWARD_STATE_FILE" 2>/dev/null || true
      ;;
  esac
}

nb_owner_state_file() {
  case "$1" in
    vless-sudoku:*) printf '%s' "$NOBRAND_VLESS_STATE_FILE" ;;
    *) return 1 ;;
  esac
}

nb_owner_ingress_enforcement() {
  local owner="$1" path id
  case "$owner" in
    forward:*)
      id="${owner#forward:}"
      jq -r --arg id "$id" '.rules[]|select(.rule_id==$id)|.ingress_enforcement // "permissive"' \
        "$NOBRAND_FORWARD_STATE_FILE" 2>/dev/null
      ;;
    ssh-tunnel:*) printf not-applicable ;;
    *) path="$(nb_owner_state_file "$owner")" && nb_ingress_state_enforcement "$path" ;;
  esac
}

nb_owner_ingress_method() {
  local owner="$1" path id
  case "$owner" in
    forward:*)
      id="${owner#forward:}"
      jq -r --arg id "$id" '.rules[]|select(.rule_id==$id)|.ingress_enforcement_method // "wildcard"' \
        "$NOBRAND_FORWARD_STATE_FILE" 2>/dev/null
      ;;
    ssh-tunnel:*) printf system-ssh ;;
    *) path="$(nb_owner_state_file "$owner")" && nb_ingress_state_method "$path" ;;
  esac
}

nb_owner_ingress_local_address() {
  local owner="$1" path id profile_id
  profile_id="$(nb_owner_ingress_profile_id "$owner" 2>/dev/null || true)"
  case "$owner" in
    forward:*)
      id="${owner#forward:}"
      jq -r --arg id "$id" '.rules[]|select(.rule_id==$id)|.ingress_local_address // empty' \
        "$NOBRAND_FORWARD_STATE_FILE" 2>/dev/null
      ;;
    ssh-tunnel:*) return 0 ;;
    *) path="$(nb_owner_state_file "$owner")" && nb_ingress_state_local_address "$path" "$profile_id" ;;
  esac
}

nb_owner_enabled() {
  local owner="$1" path id
  case "$owner" in
    forward:*) id="${owner#forward:}"; jq -r --arg id "$id" '.rules[]|select(.rule_id==$id)|.enabled' "$NOBRAND_FORWARD_STATE_FILE" 2>/dev/null ;;
    ssh-tunnel:*) printf true ;;
    *) path="$(nb_owner_state_file "$owner")" && jq -r '.enabled // true' "$path" 2>/dev/null ;;
  esac
}

nb_node_detail_rows() {
  local filter owner transport port advertise_host advertise_port profile_id display_host display_port enforcement method address actual
  filter="$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')"
  while IFS='|' read -r owner transport port advertise_host advertise_port; do
    [ -n "$owner" ] || continue
    case "$filter:$owner" in
      :*|all:*|mieru:mieru:*|snell:snell:*|hy2:hy2:*|hysteria2:hy2:*|tuic:tuic:*|vless-reality:vless-reality:*|reality:vless-reality:*|vless-sudoku:vless-sudoku:*|sudoku:vless-sudoku:*|vless:vless-*|forward:forward:*|port-forward:forward:*) ;;
      *) continue ;;
    esac
    profile_id="$(nb_owner_ingress_profile_id "$owner")"
    [ -n "$profile_id" ] || profile_id="$NOBRAND_LEGACY_INGRESS_PROFILE_ID"
    if [ -n "$advertise_host" ]; then
      display_host="$advertise_host"
    else
      display_host="$(nb_effective_advertise_host auto '' "$profile_id")"
    fi
    if [ -n "$advertise_port" ]; then
      display_port="$advertise_port"
    else
      display_port="$(nb_effective_advertise_port auto '' "$port" "$profile_id")"
    fi
    enforcement="$(nb_owner_ingress_enforcement "$owner" 2>/dev/null || printf permissive)"
    method="$(nb_owner_ingress_method "$owner" 2>/dev/null || printf wildcard)"
    address="$(nb_owner_ingress_local_address "$owner" 2>/dev/null || true)"
    case "$enforcement:$method" in
      strict:native-bind|strict:address-match) actual="${address}:${port}/${transport}" ;;
      strict:firewall)
        actual="*:${port}/${transport} ($(t "防火墙仅允许 ${address}" "firewall restricted to ${address}"))"
        ;;
      *) actual="*:${port}/${transport}" ;;
    esac
    printf '%s|%s|%s:%s|%s|%s (%s)\n' "$owner" "$actual" "$display_host" "$display_port" \
      "$(nb_ingress_profile_name "$profile_id")" "$enforcement" "$method"
  done < <(nb_registry_rows)
  if { [ -z "$filter" ] || [ "$filter" = all ] || [ "$filter" = ssh ] || [ "$filter" = ssh-tunnel ]; } \
     && ssh_tunnel_state_exists; then
    profile_id="$(ssh_tunnel_state_field ingress_profile_id 2>/dev/null || true)"
    [ -n "$profile_id" ] || profile_id="$NOBRAND_LEGACY_INGRESS_PROFILE_ID"
    while IFS= read -r owner; do
      [ -n "$owner" ] || continue
      printf 'ssh-tunnel:%s|*:%s/TCP (%s)|%s:%s|%s|%s\n' "$owner" \
        "$(ssh_tunnel_state_field real_port)" "$(t '系统 sshd' 'system sshd')" \
        "$(ssh_tunnel_effective_host)" \
        "$(ssh_tunnel_state_field advertise_port)" "$(nb_ingress_profile_name "$profile_id")" \
        "$(t '不适用（系统 sshd）' 'Not applicable (system sshd)')"
    done < <(jq -r '.users[]?.display_name' "$NOBRAND_SSH_STATE_FILE")
  fi
}

nobrand_nodes() {
  if nb_splicore_installed; then
    nb_splicore_call status --protocol "${NOBRAND_PROTOCOL_FILTER:-}" || return 1
    local retained
    for retained in vless-sudoku ssh forward; do
      [ -z "${NOBRAND_PROTOCOL_FILTER:-}" ] || [ "$NOBRAND_PROTOCOL_FILTER" = "$retained" ] || continue
      nb_all_node_rows "$retained"
    done
    return 0
  fi
  local rows details protocol name endpoint status transport owner actual display ingress enforcement status_display
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
    status_display="$status"
    if [ "$LANG_ZH" -eq 1 ]; then
      case "$status" in
        Running) status_display='运行中' ;;
        Stopped) status_display='已停止' ;;
        Ready) status_display='就绪' ;;
        Healthy) status_display='正常' ;;
        Degraded) status_display='异常' ;;
        Disabled) status_display='已禁用' ;;
      esac
    fi
    printf '%-17s %-17s %-40s %s\n' "$protocol" "$name" "$endpoint" "$status_display"
  done <<<"$rows"
  details="$(nb_node_detail_rows "${NOBRAND_PROTOCOL_FILTER:-}")"
  if [ -n "$details" ]; then
    msg ''
    t '实际监听 / Actual Listener；展示端点 / Display Endpoint；入口配置 / Ingress Profile（展示修改不影响监听）' \
      'Actual / Display / Ingress Profile (display changes do not affect listeners)'
    while IFS='|' read -r owner actual display ingress enforcement; do
      if [ "$LANG_ZH" -eq 1 ]; then
        printf '%s\n  实际监听: %s\n  展示端点: %s\n  入口配置: %s\n  强制策略: %s\n' \
          "$owner" "$actual" "$display" "$ingress" "$enforcement"
      else
        printf '%s\n  Actual: %s\n  Display: %s\n  Ingress: %s\n  Enforcement: %s\n' \
          "$owner" "$actual" "$display" "$ingress" "$enforcement"
      fi
    done <<<"$details"
  fi
}

nobrand_status() {
  nb_splicore_legacy_preflight || return 1
  nb_splicore_call status || return 1
  if vless_sudoku_state_exists; then vless_sudoku_service_command status; fi
  ssh_tunnel_status
  [ ! -s "$NOBRAND_FORWARD_STATE_FILE" ] || forward_list_rules
  return 0
}

nb_doctor_line() {
  local level="$1"
  shift
  printf '[%s] %s\n' "$level" "$*"
}

nobrand_doctor() {
  nb_splicore_legacy_preflight || return 1
  local failed=0
  nb_splicore_call doctor || failed=1
  if vless_sudoku_state_exists; then vless_sudoku_doctor || failed=1; fi
  if ssh_tunnel_state_exists; then ssh_tunnel_doctor || failed=1; fi
  [ ! -s "$NOBRAND_FORWARD_STATE_FILE" ] || forward_doctor || failed=1
  return "$failed"
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
  normalized="$(nb_normalize_path "$value")" \
    || die "${label} 无法安全解析，拒绝破坏性操作: $value"
  case "$normalized" in
    /|/etc|/var|/usr|/usr/local) die "${label} 过宽，拒绝破坏性操作: $normalized" ;;
  esac
  case "$normalized" in
    */nobrand-oneclick|*/nobrand-oneclick/*|*/nobrand-oneclick-*) ;;
    *) die "${label} 不在明确的 NoBrand namespace 中: $normalized" ;;
  esac
  printf '%s' "$normalized"
}

nobrand_backup_restore_transaction_paths_valid() {
  nb_lifecycle_paths_valid || return 1
  [ "$NOBRAND_BACKUP_RESTORE_TX_DIR" = "${NOBRAND_LIFECYCLE_DIR}/backup-restore" ] \
    && [ "$NOBRAND_BACKUP_RESTORE_META_FILE" = "${NOBRAND_BACKUP_RESTORE_TX_DIR}/transaction.env" ] \
    && [ "$NOBRAND_BACKUP_RESTORE_SNAPSHOT_DIR" = "${NOBRAND_BACKUP_RESTORE_TX_DIR}/snapshot" ] \
    && [ "$NOBRAND_BACKUP_RESTORE_ROOTS_MANIFEST" = "${NOBRAND_BACKUP_RESTORE_TX_DIR}/snapshot-roots.manifest" ]
}

nobrand_backup_restore_transaction_present() {
  [ -e "$NOBRAND_BACKUP_RESTORE_TX_DIR" ] || [ -L "$NOBRAND_BACKUP_RESTORE_TX_DIR" ]
}

nobrand_backup_restore_snapshot_manifest_walk() {
  local root="$1" prefix="$2" entry name relative metadata digest
  local -a entries=()
  entries=("$root"/*)
  for entry in "${entries[@]}"; do
    name="${entry##*/}"
    relative="${prefix}${name}"
    if [ -L "$entry" ]; then
      printf 'L\0%s\0' "$relative" || return 1
      readlink -- "$entry" || return 1
      printf '\0' || return 1
    elif [ -d "$entry" ]; then
      metadata="$(stat -c '%u:%g:%a' -- "$entry")" || return 1
      printf 'D\0%s\0%s\0' "$relative" "$metadata" || return 1
      nobrand_backup_restore_snapshot_manifest_walk "$entry" "${relative}/" || return 1
    elif [ -f "$entry" ]; then
      metadata="$(stat -c '%u:%g:%a' -- "$entry")" || return 1
      digest="$(nobrand_sha256_file "$entry" 2>/dev/null)" || return 1
      [[ "$digest" =~ ^[0-9a-f]{64}$ ]] || return 1
      printf 'F\0%s\0%s\0%s\0' "$relative" "$metadata" "$digest" || return 1
    else
      return 1
    fi
  done
}

nobrand_backup_restore_snapshot_manifest_generate() (
  local snapshot_dir="${1:-$NOBRAND_BACKUP_RESTORE_SNAPSHOT_DIR}"
  local label root metadata
  LC_ALL=C
  export LC_ALL
  shopt -s dotglob nullglob
  printf 'nobrand-backup-restore-roots-v1\0' || return 1
  for label in state config; do
    root="$snapshot_dir/$label"
    [ -d "$root" ] && [ ! -L "$root" ] || return 1
    metadata="$(stat -c '%u:%g:%a' -- "$root")" || return 1
    printf 'R\0%s\0%s\0' "$label" "$metadata" || return 1
    nobrand_backup_restore_snapshot_manifest_walk "$root" "${label}/" || return 1
  done
)

nobrand_backup_restore_snapshot_manifest_write_at() {
  local transaction_dir="$1" snapshot_dir="$2" manifest_file="$3" tmp
  [ "$snapshot_dir" = "${transaction_dir}/snapshot" ] \
    && [ "$manifest_file" = "${transaction_dir}/snapshot-roots.manifest" ] \
    || return 1
  [ -d "$transaction_dir" ] && [ ! -L "$transaction_dir" ] \
    || return 1
  tmp="$(mktemp "${transaction_dir}/.snapshot-roots.XXXXXX")" || return 1
  if ! nobrand_backup_restore_snapshot_manifest_generate "$snapshot_dir" >"$tmp" \
     || ! chmod 0600 "$tmp"; then
    rm -f -- "$tmp"
    return 1
  fi
  chown root:root "$tmp" 2>/dev/null || true
  mv -f -- "$tmp" "$manifest_file" || {
    rm -f -- "$tmp"
    return 1
  }
}

nobrand_backup_restore_snapshot_manifest_valid_at() (
  local snapshot_dir="$1" manifest_file="$2"
  set -o pipefail
  [ -f "$manifest_file" ] \
    && [ ! -L "$manifest_file" ] \
    && secure_stat_path "$manifest_file" file \
    && [ "$(stat -c '%a' "$manifest_file" 2>/dev/null)" = 600 ] \
    || return 1
  nobrand_backup_restore_snapshot_manifest_generate "$snapshot_dir" \
    | cmp -s -- "$manifest_file" -
)

nobrand_backup_restore_snapshot_manifest_valid() {
  nobrand_backup_restore_transaction_paths_valid || return 1
  nobrand_backup_restore_snapshot_manifest_valid_at \
    "$NOBRAND_BACKUP_RESTORE_SNAPSHOT_DIR" "$NOBRAND_BACKUP_RESTORE_ROOTS_MANIFEST"
}

nobrand_backup_restore_transaction_valid_at() {
  local transaction_dir="$1" metadata_file="$2" snapshot_dir="$3" manifest_file="$4"
  local status started state_created config_created fresh_restore path
  [ "$metadata_file" = "${transaction_dir}/transaction.env" ] \
    && [ "$snapshot_dir" = "${transaction_dir}/snapshot" ] \
    && [ "$manifest_file" = "${transaction_dir}/snapshot-roots.manifest" ] \
    || return 1
  [ -d "$transaction_dir" ] && [ ! -L "$transaction_dir" ] \
    && [ -d "$snapshot_dir" ] && [ ! -L "$snapshot_dir" ] \
    && [ -f "$metadata_file" ] && [ ! -L "$metadata_file" ] \
    && [ -f "$manifest_file" ] \
    && [ ! -L "$manifest_file" ] \
    || return 1
  secure_stat_path "$NOBRAND_LIFECYCLE_DIR" dir \
    && secure_stat_path "$transaction_dir" dir \
    && secure_stat_path "$snapshot_dir" dir \
    && secure_stat_path "$metadata_file" file \
    && secure_stat_path "$manifest_file" file || return 1
  [ "$(stat -c '%a' "$transaction_dir" 2>/dev/null)" = 700 ] \
    && [ "$(stat -c '%a' "$snapshot_dir" 2>/dev/null)" = 700 ] \
    && [ "$(stat -c '%a' "$metadata_file" 2>/dev/null)" = 600 ] \
    && [ "$(stat -c '%a' "$manifest_file" 2>/dev/null)" = 600 ] \
    || return 1
  awk -F= '
    BEGIN {
      required["FORMAT"]=1; required["STATUS"]=1; required["STARTED_AT"]=1;
      required["STATE_ROOT_CREATED"]=1; required["CONFIG_ROOT_CREATED"]=1;
      required["FRESH_MANAGER_RESTORE"]=1
    }
    NF != 2 || !($1 in required) || seen[$1]++ { bad=1 }
    END {
      for (key in required) if (seen[key] != 1) bad=1
      exit bad ? 1 : 0
    }
  ' "$metadata_file" || return 1
  [ "$(nb_lifecycle_field FORMAT "$metadata_file")" = nobrand-backup-restore-v1 ] \
    || return 1
  status="$(nb_lifecycle_field STATUS "$metadata_file")"
  started="$(nb_lifecycle_field STARTED_AT "$metadata_file")"
  state_created="$(nb_lifecycle_field STATE_ROOT_CREATED "$metadata_file")"
  config_created="$(nb_lifecycle_field CONFIG_ROOT_CREATED "$metadata_file")"
  fresh_restore="$(nb_lifecycle_field FRESH_MANAGER_RESTORE "$metadata_file")"
  case "$status" in
    applying|runtime-applying|rollback-roots|pending-ssh-confirmation) ;;
    *) return 1 ;;
  esac
  [[ "$started" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] \
    || return 1
  case "$state_created:$config_created:$fresh_restore" in
    0:0:0|0:1:0|1:0:0|1:1:1) ;;
    *) return 1 ;;
  esac
  for path in state config ssh-external forward-external; do
    [ -d "$snapshot_dir/$path" ] \
      && [ ! -L "$snapshot_dir/$path" ] || return 1
  done
  nobrand_backup_restore_snapshot_manifest_valid_at "$snapshot_dir" "$manifest_file"
}

nobrand_backup_restore_transaction_valid() {
  nobrand_backup_restore_transaction_paths_valid || return 1
  nobrand_backup_restore_transaction_valid_at \
    "$NOBRAND_BACKUP_RESTORE_TX_DIR" "$NOBRAND_BACKUP_RESTORE_META_FILE" \
    "$NOBRAND_BACKUP_RESTORE_SNAPSHOT_DIR" "$NOBRAND_BACKUP_RESTORE_ROOTS_MANIFEST"
}

nobrand_backup_restore_transaction_write_at() {
  local transaction_dir="$1" metadata_file="$2" snapshot_dir="$3" manifest_file="$4"
  local status="$5" state_created="$6" config_created="$7" fresh_restore="$8"
  local started="${9:-}" tmp
  [ "$metadata_file" = "${transaction_dir}/transaction.env" ] \
    && [ "$snapshot_dir" = "${transaction_dir}/snapshot" ] \
    && [ "$manifest_file" = "${transaction_dir}/snapshot-roots.manifest" ] \
    || return 1
  case "$status" in
    applying|runtime-applying|rollback-roots|pending-ssh-confirmation) ;;
    *) return 1 ;;
  esac
  case "$state_created:$config_created:$fresh_restore" in
    0:0:0|0:1:0|1:0:0|1:1:1) ;;
    *) return 1 ;;
  esac
  if [ -z "$started" ] && [ -f "$metadata_file" ]; then
    started="$(nb_lifecycle_field STARTED_AT "$metadata_file")"
  fi
  [ -n "$started" ] || started="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  [[ "$started" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] \
    || return 1
  [ -d "$transaction_dir" ] && [ ! -L "$transaction_dir" ] \
    || return 1
  nobrand_backup_restore_snapshot_manifest_valid_at "$snapshot_dir" "$manifest_file" \
    || return 1
  tmp="$(mktemp "${transaction_dir}/.transaction.XXXXXX")" || return 1
  if ! printf '%s\n' \
      'FORMAT=nobrand-backup-restore-v1' \
      "STATUS=${status}" \
      "STARTED_AT=${started}" \
      "STATE_ROOT_CREATED=${state_created}" \
      "CONFIG_ROOT_CREATED=${config_created}" \
      "FRESH_MANAGER_RESTORE=${fresh_restore}" >"$tmp" \
     || ! chmod 0600 "$tmp"; then
    rm -f "$tmp"
    return 1
  fi
  chown root:root "$tmp" 2>/dev/null || true
  mv -f -- "$tmp" "$metadata_file" || {
    rm -f "$tmp"
    return 1
  }
}

nobrand_backup_restore_transaction_write() {
  nobrand_backup_restore_transaction_paths_valid || return 1
  nobrand_backup_restore_transaction_write_at \
    "$NOBRAND_BACKUP_RESTORE_TX_DIR" "$NOBRAND_BACKUP_RESTORE_META_FILE" \
    "$NOBRAND_BACKUP_RESTORE_SNAPSHOT_DIR" "$NOBRAND_BACKUP_RESTORE_ROOTS_MANIFEST" \
    "$@"
}

nobrand_backup_restore_transaction_mark_ssh_pending() {
  local status state_created config_created fresh_restore
  nobrand_backup_restore_transaction_present || return 0
  nobrand_backup_restore_transaction_valid || return 1
  status="$(nb_lifecycle_field STATUS "$NOBRAND_BACKUP_RESTORE_META_FILE")"
  [ "$status" != pending-ssh-confirmation ] || return 0
  [ "$status" = runtime-applying ] || return 1
  state_created="$(nb_lifecycle_field STATE_ROOT_CREATED "$NOBRAND_BACKUP_RESTORE_META_FILE")"
  config_created="$(nb_lifecycle_field CONFIG_ROOT_CREATED "$NOBRAND_BACKUP_RESTORE_META_FILE")"
  fresh_restore="$(nb_lifecycle_field FRESH_MANAGER_RESTORE "$NOBRAND_BACKUP_RESTORE_META_FILE")"
  nobrand_backup_restore_transaction_write pending-ssh-confirmation \
    "$state_created" "$config_created" "$fresh_restore"
}

nobrand_backup_restore_staging_cleanup() (
  local entry name
  nobrand_backup_restore_transaction_paths_valid || return 1
  [ -e "$NOBRAND_LIFECYCLE_DIR" ] || return 0
  [ -d "$NOBRAND_LIFECYCLE_DIR" ] && [ ! -L "$NOBRAND_LIFECYCLE_DIR" ] \
    || return 1
  shopt -s nullglob
  for entry in "$NOBRAND_LIFECYCLE_DIR"/.backup-restore.prepare.*; do
    name="${entry##*/}"
    [[ "$name" =~ ^\.backup-restore\.prepare\.[A-Za-z0-9]{6}$ ]] || return 1
    [ -d "$entry" ] && [ ! -L "$entry" ] \
      && [ "$(stat -c '%a' "$entry" 2>/dev/null)" = 700 ] \
      && secure_stat_path "$entry" dir || return 1
    rm -rf -- "$entry" || return 1
  done
)

# A no-op boundary used by the focused transaction test to stop a real child
# process at exact preparation phases. Production callers always continue.
nobrand_backup_restore_prepare_checkpoint() {
  : "$1"
}

nobrand_backup_restore_transaction_prepare() {
  local safe_state="$1" safe_config="$2"
  local state_created="$3" config_created="$4" fresh_restore="$5"
  local status="${6:-applying}" prepare_dir snapshot metadata manifest
  case "$status" in
    applying|runtime-applying|rollback-roots|pending-ssh-confirmation) ;;
    *) return 1 ;;
  esac
  case "$state_created:$config_created:$fresh_restore" in
    0:0:0|0:1:0|1:0:0|1:1:1) ;;
    *) return 1 ;;
  esac
  nobrand_backup_restore_transaction_paths_valid || return 1
  nobrand_backup_restore_transaction_present && return 1
  nb_lifecycle_prepare_dir || return 1
  nobrand_backup_restore_staging_cleanup || return 1
  prepare_dir="$(mktemp -d "${NOBRAND_LIFECYCLE_DIR}/.backup-restore.prepare.XXXXXX")" \
    || return 1
  if ! chmod 0700 "$prepare_dir"; then
    rm -rf -- "$prepare_dir"
    return 1
  fi
  chown root:root "$prepare_dir" 2>/dev/null || true
  snapshot="$prepare_dir/snapshot"
  metadata="$prepare_dir/transaction.env"
  manifest="$prepare_dir/snapshot-roots.manifest"
  if ! mkdir "$snapshot" \
     || ! chmod 0700 "$snapshot"; then
    rm -rf -- "$prepare_dir"
    return 1
  fi
  chown root:root "$snapshot" 2>/dev/null || true
  if ! mkdir "$snapshot/state" "$snapshot/config" "$snapshot/ssh-external" \
      "$snapshot/forward-external"; then
    rm -rf -- "$prepare_dir"
    return 1
  fi
  nobrand_backup_restore_prepare_checkpoint snapshot-directory-ready
  if [ "$state_created" -eq 0 ]; then
    if ! cp -a "$safe_state/." "$snapshot/state/" \
       || ! nobrand_backup_tree_matches "$safe_state" "$snapshot/state"; then
      rm -rf -- "$prepare_dir"
      return 1
    fi
  elif [ -e "$safe_state" ] || [ -L "$safe_state" ]; then
    rm -rf -- "$prepare_dir"
    return 1
  fi
  if [ "$config_created" -eq 0 ]; then
    if ! cp -a "$safe_config/." "$snapshot/config/" \
       || ! nobrand_backup_tree_matches "$safe_config" "$snapshot/config"; then
      rm -rf -- "$prepare_dir"
      return 1
    fi
  elif [ -e "$safe_config" ] || [ -L "$safe_config" ]; then
    rm -rf -- "$prepare_dir"
    return 1
  fi
  nobrand_backup_restore_prepare_checkpoint managed-roots-snapshotted
  if ! ssh_tunnel_snapshot_external_state "$snapshot/ssh-external" \
     || ! forward_snapshot_restore_side_effects "$snapshot/forward-external"; then
    rm -rf -- "$prepare_dir"
    return 1
  fi
  nobrand_backup_restore_prepare_checkpoint external-state-snapshotted
  if ! nobrand_backup_restore_snapshot_manifest_write_at \
      "$prepare_dir" "$snapshot" "$manifest"; then
    rm -rf -- "$prepare_dir"
    return 1
  fi
  nobrand_backup_restore_prepare_checkpoint manifest-ready
  if ! nobrand_backup_restore_transaction_write_at \
      "$prepare_dir" "$metadata" "$snapshot" "$manifest" "$status" \
      "$state_created" "$config_created" "$fresh_restore" \
     || ! nobrand_backup_restore_transaction_valid_at \
      "$prepare_dir" "$metadata" "$snapshot" "$manifest"; then
    rm -rf -- "$prepare_dir"
    return 1
  fi
  nobrand_backup_restore_prepare_checkpoint metadata-ready
  if nobrand_backup_restore_transaction_present \
     || ! mv -T -- "$prepare_dir" "$NOBRAND_BACKUP_RESTORE_TX_DIR"; then
    rm -rf -- "$prepare_dir"
    return 1
  fi
  nobrand_backup_restore_prepare_checkpoint transaction-published
  nobrand_backup_restore_transaction_valid
}

nobrand_backup_restore_transaction_cleanup() {
  nobrand_backup_restore_transaction_paths_valid || return 1
  nobrand_backup_restore_transaction_present || return 0
  [ -d "$NOBRAND_BACKUP_RESTORE_TX_DIR" ] && [ ! -L "$NOBRAND_BACKUP_RESTORE_TX_DIR" ] \
    || return 1
  secure_stat_path "$NOBRAND_BACKUP_RESTORE_TX_DIR" dir || return 1
  rm -rf -- "$NOBRAND_BACKUP_RESTORE_TX_DIR" || return 1
  rmdir "$NOBRAND_LIFECYCLE_DIR" 2>/dev/null || true
}

nobrand_backup_restore_recover_applying() {
  local status state_root_created config_root_created fresh_restore
  local snapshot safe_state safe_config restore_root cleanup_dir
  local cleanup_failed=0 rollback_failed=0 managed_roots_restored=0
  nobrand_backup_restore_transaction_valid || {
    warn "$(t '备份恢复的持久事务元数据无效；恢复快照已保留' \
      'Durable backup-restore transaction metadata is invalid; the recovery snapshot was retained')"
    return 1
  }
  status="$(nb_lifecycle_field STATUS "$NOBRAND_BACKUP_RESTORE_META_FILE")"
  case "$status" in
    applying|runtime-applying|rollback-roots) ;;
    *) return 1 ;;
  esac
  state_root_created="$(nb_lifecycle_field STATE_ROOT_CREATED "$NOBRAND_BACKUP_RESTORE_META_FILE")"
  config_root_created="$(nb_lifecycle_field CONFIG_ROOT_CREATED "$NOBRAND_BACKUP_RESTORE_META_FILE")"
  fresh_restore="$(nb_lifecycle_field FRESH_MANAGER_RESTORE "$NOBRAND_BACKUP_RESTORE_META_FILE")"
  snapshot="$NOBRAND_BACKUP_RESTORE_SNAPSHOT_DIR"
  safe_state="$(nb_assert_safe_nobrand_root "$NOBRAND_STATE_DIR" NOBRAND_STATE_DIR)" \
    || return 1
  safe_config="$(nb_assert_safe_nobrand_root "$NOBRAND_CONFIG_DIR" NOBRAND_CONFIG_DIR)" \
    || return 1

  # A crash can leave either managed root empty or only partly imported. Make
  # only the two exact, validated NoBrand roots available for the idempotent
  # rollback; never initialize a new registry before the snapshot is restored.
  for restore_root in "$safe_state" "$safe_config"; do
    if [ -e "$restore_root" ] || [ -L "$restore_root" ]; then
      [ -d "$restore_root" ] && [ ! -L "$restore_root" ] \
        && secure_stat_path "$restore_root" dir || return 1
    else
      mkdir -p "$restore_root" \
        && chmod 0700 "$restore_root" \
        && chown root:root "$restore_root" 2>/dev/null \
        && secure_stat_path "$restore_root" dir || return 1
    fi
  done

  # An armed/running SSH watchdog can still write its saved state after this
  # process restores the global snapshot. Claim or observe its completion
  # before touching any rollback material; otherwise retain everything.
  if ! ssh_tunnel_cancel_pending_watchdog 2>/dev/null \
     || ! ssh_tunnel_cleanup_disarmed_watchdogs 2>/dev/null; then
    warn "$(t "SSH watchdog 的回滚所有权尚未解决；备份恢复快照保留在: ${snapshot}" \
      "SSH watchdog rollback ownership is unresolved; the backup-restore snapshot is retained at: ${snapshot}")"
    return 75
  fi
  # An imported primary graph may already be serving when a later acceptance
  # fails. Quiesce it before replacing its database or generation directories.
  if nb_splicore_installed; then
    nb_splicore_call stop || return 1
  fi

  # `applying` cannot have crossed the verified-root commit below, so no
  # runtime/external resource was touched. `runtime-applying` still has the
  # imported state needed for exact attempt cleanup. Never advance past it if
  # state-driven cleanup fails: a retry must see the same imported ownership.
  if [ "$status" = runtime-applying ]; then
    if [ "$fresh_restore" -eq 1 ]; then
      nobrand_remove_fresh_restore_protocol_resources 2>/dev/null \
        || cleanup_failed=1
    fi
    forward_remove_restore_attempt_resources 2>/dev/null || cleanup_failed=1
    if [ "$fresh_restore" -eq 1 ]; then
      for cleanup_dir in "$NOBRAND_BIN_DIR" "$NOBRAND_LIB_DIR"; do
        if [ -e "$cleanup_dir" ] || [ -L "$cleanup_dir" ]; then
          [ -d "$cleanup_dir" ] && [ ! -L "$cleanup_dir" ] \
            || cleanup_failed=1
          rmdir "$cleanup_dir" 2>/dev/null || true
        fi
      done
    fi
  fi
  if [ "$cleanup_failed" -ne 0 ]; then
    warn "$(t "中断恢复所创建的资源未能完整清理；导入状态与恢复快照均已保留在: ${snapshot}" \
      "Resources created by the interrupted restore could not be cleaned completely; imported state and the recovery snapshot are retained at: ${snapshot}")"
    return 1
  fi

  if [ "$status" != applying ]; then
    forward_restore_side_effect_snapshot "$snapshot/forward-external" 2>/dev/null \
      || rollback_failed=1
    ssh_tunnel_restore_external_snapshot \
      "$snapshot/ssh-external" "$snapshot/ssh-external/created.log" 2>/dev/null \
      || rollback_failed=1
  fi
  if [ "$status" = runtime-applying ]; then
    # From this durable point onward live state may already be the original
    # snapshot, so retries must not use it as restore-attempt ownership.
    nobrand_backup_restore_transaction_write rollback-roots \
      "$state_root_created" "$config_root_created" "$fresh_restore" || {
      warn "$(t '无法记录备份恢复的回滚阶段；导入状态与恢复快照均已保留' \
        'Could not record the backup-restore rollback phase; imported state and the recovery snapshot were retained')"
      return 1
    }
    status=rollback-roots
  fi

  if nobrand_backup_restore_managed_roots "$safe_state" "$safe_config" "$snapshot"; then
    managed_roots_restored=1
  else
    rollback_failed=1
  fi
  if [ "$managed_roots_restored" -eq 1 ]; then
    if [ "$state_root_created" -eq 1 ]; then
      rmdir "$safe_state" 2>/dev/null || rollback_failed=1
    fi
    if [ "$config_root_created" -eq 1 ]; then
      rmdir "$safe_config" 2>/dev/null || rollback_failed=1
    fi
    if [ "$state_root_created" -eq 0 ] && [ "$config_root_created" -eq 0 ]; then
      nb_init_state_layout 2>/dev/null || rollback_failed=1
      nobrand_start_enabled_services 2>/dev/null || rollback_failed=1
    fi
  fi
  if [ "$rollback_failed" -ne 0 ]; then
    warn "$(t "中断的备份恢复未能完整回滚；唯一恢复快照保留在: ${snapshot}" \
      "The interrupted backup restore could not be rolled back completely; the only recovery snapshot is retained at: ${snapshot}")"
    return 1
  fi
  nobrand_backup_restore_transaction_cleanup || {
    warn "$(t "中断的备份恢复已回滚，但恢复快照无法安全清理，已保留在: ${snapshot}" \
      "The interrupted backup restore was rolled back, but its snapshot could not be safely retired and remains at: ${snapshot}")"
    return 1
  }
}

nobrand_backup_restore_confirmation_finalize() {
  local status
  nobrand_backup_restore_transaction_present || return 0
  nobrand_backup_restore_transaction_valid || {
    warn "$(t '备份恢复的持久事务元数据无效；恢复快照已保留' \
      'Durable backup-restore transaction metadata is invalid; the recovery snapshot was retained')"
    return 1
  }
  status="$(nb_lifecycle_field STATUS "$NOBRAND_BACKUP_RESTORE_META_FILE")"
  if [ "$status" != pending-ssh-confirmation ]; then
    warn "$(t '备份恢复仍处于应用阶段；必须先从持久快照回滚，拒绝清理恢复证据' \
      'The backup restore is still applying; its durable snapshot must be recovered before recovery evidence can be retired')"
    return 1
  fi
  # Only a restore that actually entered SSH confirmation can write this
  # status. Absence is therefore evidence loss, not successful acceptance.
  if ! ssh_tunnel_state_exists \
     || ! ssh_tunnel_state_identity_valid \
     || [ "$(ssh_tunnel_state_field pending_operation 2>/dev/null || true)" != '' ] \
     || [ "$(ssh_tunnel_state_field pending_watchdog_token 2>/dev/null || true)" != '' ] \
     || [ "$(ssh_tunnel_state_field pending_watchdog_pid 2>/dev/null || true)" != '' ] \
     || [ "$(ssh_tunnel_state_field pending_origin_connection 2>/dev/null || true)" != '' ] \
     || [ "$(ssh_tunnel_state_field policy_applied 2>/dev/null || true)" != true ]; then
      warn "$(t 'SSH 验收状态不完整；备份恢复快照已保留' \
        'SSH acceptance state is incomplete; the backup-restore snapshot was retained')"
      return 1
  fi
  nobrand_backup_restore_transaction_cleanup || {
    warn "$(t 'SSH 已确认，但备份恢复快照无法安全清理，已保留供检查' \
      'SSH was confirmed, but the backup-restore snapshot could not be safely retired and was retained for inspection')"
    return 1
  }
}

nobrand_backup_create() {
  local destination="${1:-}" stage archive_tmp
  if nb_splicore_installed; then
    [ -n "$destination" ] || destination="$(nb_backup_default_path)"
    ssh_tunnel_backup_state_ready || return 1
    nb_splicore_call backup --unified --file "$destination"
    return $?
  fi
  if nobrand_backup_restore_transaction_present; then
    die "$(t '存在尚未完成的备份恢复事务；拒绝创建可能误导的新备份' \
      'An unfinished backup-restore transaction exists; refusing to create a misleading new backup')"
    return 1
  fi
  nb_init_state_layout || return 1
  ssh_tunnel_backup_state_ready \
    || die "$(t 'SSH 策略确认或 watchdog 清理完成前不能创建备份' \
      'A backup cannot be created while SSH confirmation or watchdog cleanup is pending')"
  [ -n "$destination" ] || destination="$(nb_backup_default_path)"
  stage="$(mktemp_dir)" || return 1
  mkdir -p "$stage/state" "$stage/config" || { rm -rf -- "$stage"; return 1; }
  cp -a "$NOBRAND_STATE_DIR/." "$stage/state/" || { rm -rf -- "$stage"; return 1; }
  cp -a "$NOBRAND_CONFIG_DIR/." "$stage/config/" || { rm -rf -- "$stage"; return 1; }
  if [ -d "$stage/state/ssh-tunnel/watchdog" ]; then
    rmdir "$stage/state/ssh-tunnel/watchdog" \
      || { rm -rf -- "$stage"; return 1; }
  fi
  cat >"$stage/manifest.txt" <<EOF
project=NoBrand-OneClick
version=${SCRIPT_VERSION}
schema_version=${NOBRAND_SCHEMA_VERSION}
ownership=nobrand-v3
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

# A backup contains authoritative state/config, but deliberately excludes
# downloaded runtimes and service-manager artifacts.  A restore into a
# manager-only installation therefore has to rebuild every runtime/service
# from the restored state before it can start anything.
nobrand_restore_protocol_runtimes() {
  nb_splicore_legacy_preflight || return 1
  if [ -e "${NOBRAND_STATE_DIR}/splicore/current" ] || nb_splicore_installed; then
    nb_splicore_call adopt-snapshot || return 1
  fi
  if vless_sudoku_state_exists; then
    NOBRAND_XRAY_SPECIALIZED=1 nobrand_install_xray_runtime 0 || return 1
    nobrand_write_vless_sudoku_service || return 1
  fi
  forward_realm_restore_runtime
}

nobrand_fresh_restore_runtime_preflight() {
  local staged_state="$1" path
  # Archive ownership and architecture were checked before extraction.
  [ -f "$staged_state/state.json" ] || return 1
  for path in "$NOBRAND_LIB_DIR" "$NOBRAND_VLESS_SYSTEMD_SERVICE" "$NOBRAND_REALM_SYSTEMD_SERVICE"; do
    [ ! -e "$path" ] && [ ! -L "$path" ] || return 1
  done
}

nobrand_remove_fresh_restore_protocol_resources() {
  nb_splicore_legacy_preflight || return 1
  local failed=0 port
  if nb_splicore_installed; then nb_splicore_call purge || failed=1; fi
  if vless_sudoku_state_exists; then
    port="$(vless_sudoku_state_field listen_port 2>/dev/null || true)"
    nobrand_remove_vless_sudoku_service || failed=1
    [ -z "$port" ] || nb_firewall_close_pairs "TCP|${port}" || failed=1
    nobrand_remove_xray_runtime_files || failed=1
  fi
  return "$failed"
}

nobrand_backup_stage_topology_valid() {
  local stage="$1" path unsafe=""
  [ -f "$stage/manifest.txt" ] && [ ! -L "$stage/manifest.txt" ] || return 1
  [ -d "$stage/state" ] && [ ! -L "$stage/state" ] \
    && [ -d "$stage/config" ] && [ ! -L "$stage/config" ] || return 1
  unsafe="$(find "$stage/state" "$stage/config" \
    ! -type f ! -type d -print -quit 2>/dev/null)" || return 1
  [ -z "$unsafe" ] || return 1
  for path in \
    "$stage/state/ssh-tunnel" \
    "$stage/state/ssh-tunnel/keys" \
    "$stage/state/ssh-tunnel/watchdog" \
    "$stage/config/ssh-tunnel" \
    "$stage/config/ssh-tunnel/authorized_keys" \
    "$stage/config/ssh-tunnel/accounts"; do
    if [ -e "$path" ] || [ -L "$path" ]; then
      [ -d "$path" ] && [ ! -L "$path" ] || return 1
    fi
  done
}

nobrand_backup_tree_matches() (
  local expected="$1" actual="$2" entry name counterpart expected_count=0 actual_count=0
  [ -d "$expected" ] && [ ! -L "$expected" ] \
    && [ -d "$actual" ] && [ ! -L "$actual" ] || return 1
  shopt -s dotglob nullglob
  for entry in "$expected"/*; do
    expected_count=$((expected_count + 1))
    name="${entry##*/}"
    counterpart="${actual}/${name}"
    if [ -L "$entry" ]; then
      [ -L "$counterpart" ] \
        && [ "$(readlink "$entry")" = "$(readlink "$counterpart")" ] || return 1
    elif [ -d "$entry" ]; then
      [ -d "$counterpart" ] && [ ! -L "$counterpart" ] \
        && [ "$(stat -c '%u:%g:%a' "$entry")" = "$(stat -c '%u:%g:%a' "$counterpart")" ] \
        && nobrand_backup_tree_matches "$entry" "$counterpart" || return 1
    elif [ -f "$entry" ]; then
      [ -f "$counterpart" ] && [ ! -L "$counterpart" ] \
        && [ "$(stat -c '%u:%g:%a' "$entry")" = "$(stat -c '%u:%g:%a' "$counterpart")" ] \
        && cmp -s "$entry" "$counterpart" || return 1
    else
      return 1
    fi
  done
  for entry in "$actual"/*; do
    actual_count=$((actual_count + 1))
  done
  [ "$expected_count" -eq "$actual_count" ]
)

nobrand_backup_restore_managed_roots() {
  local safe_state="$1" safe_config="$2" snapshot="$3"
  nobrand_backup_restore_snapshot_manifest_valid \
    && find "$safe_state" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + \
    && find "$safe_config" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + \
    && cp -a "$snapshot/state/." "$safe_state/" \
    && cp -a "$snapshot/config/." "$safe_config/" \
    && nobrand_backup_tree_matches "$snapshot/state" "$safe_state" \
    && nobrand_backup_tree_matches "$snapshot/config" "$safe_config"
}

nobrand_backup_restore() {
  local source="$1" stage snapshot safe_state safe_config ssh_restore_log restore_root cleanup_dir
  local state_root_created=0 config_root_created=0 fresh_manager_restore=0
  local restore_failed=0 rollback_failed=0 managed_roots_restored=0
  local ssh_confirmation_pending=0 pending_operation="" pending_token=""
  local ssh_restore_rc=0
  local primary_snapshot_active=0
  if nobrand_backup_restore_transaction_present; then
    if nobrand_backup_restore_transaction_valid; then
      die "$(t "存在尚未完成的备份恢复事务，恢复快照保留在: ${NOBRAND_BACKUP_RESTORE_SNAPSHOT_DIR}" \
        "An unfinished backup-restore transaction exists; its recovery snapshot is retained at: ${NOBRAND_BACKUP_RESTORE_SNAPSHOT_DIR}")"
    else
      die "$(t '检测到无效的备份恢复事务元数据；为避免覆盖恢复证据，操作已停止' \
        'Invalid backup-restore transaction metadata was detected; the operation stopped to preserve recovery evidence')"
    fi
    return 1
  fi
  [ -f "$source" ] || die "备份不存在: $source"
  safe_state="$(nb_assert_safe_nobrand_root "$NOBRAND_STATE_DIR" NOBRAND_STATE_DIR)" || return 1
  safe_config="$(nb_assert_safe_nobrand_root "$NOBRAND_CONFIG_DIR" NOBRAND_CONFIG_DIR)" || return 1
  ssh_tunnel_backup_state_ready \
    || {
      die "$(t '当前 SSH 策略仍在确认中或状态不完整；拒绝启动备份恢复' \
        'The current SSH policy is pending confirmation or incomplete; refusing to start backup restore')"
      return 1
    }
  nb_splicore_call inspect-backup --file "$source" >/dev/null || return 1
  tar -tzf "$source" 2>/dev/null | awk '
    /^\// || /(^|\/)\.\.($|\/)/ { bad=1 }
    END { exit bad ? 1 : 0 }
  ' || die '备份包含不安全路径，拒绝恢复'
  stage="$(mktemp_dir)" || return 1
  tar -C "$stage" -xzf "$source" || { rm -rf -- "$stage"; return 1; }
  nobrand_backup_stage_topology_valid "$stage" \
    || {
      rm -rf -- "$stage"
      die '备份包含不安全的文件类型或目录结构，拒绝恢复'
      return 1
    }
  grep -qx 'project=NoBrand-OneClick' "$stage/manifest.txt" 2>/dev/null \
    || { rm -rf -- "$stage"; die '不是 NoBrand-OneClick 备份'; }
  grep -qx 'schema_version=3' "$stage/manifest.txt" 2>/dev/null \
    && grep -qx 'ownership=nobrand-v3' "$stage/manifest.txt" 2>/dev/null \
    && nb_schema_v3_file_valid "$stage/state/state.json" \
    || { rm -rf -- "$stage"; die '备份不是 NoBrand schema v3，拒绝导入旧 state'; }
  ssh_tunnel_restore_preflight "$stage/state/ssh-tunnel/state.json" \
    || { rm -rf -- "$stage"; die "$(t 'SSH 隧道恢复身份冲突，拒绝覆盖系统用户' \
      'SSH Tunnel restore identity conflict; refusing to overwrite system users')"; }
  if [ -s "$stage/state/forward/state.json" ]; then
    forward_state_valid "$stage/state/forward/state.json" \
      || { rm -rf -- "$stage"; die "$(t '端口转发恢复状态无效' \
        'Port Forward restore state is invalid')"; }
  fi
  if [ -s "$stage/state/ingress.json" ]; then
    nb_ingress_state_valid "$stage/state/ingress.json" \
      || { rm -rf -- "$stage"; die "$(t 'Ingress 入口配置恢复状态无效' \
        'Ingress profile restore state is invalid')"; }
  fi
  if [ -s "$stage/state/ingress-firewall.json" ]; then
    nb_strict_firewall_state_valid "$stage/state/ingress-firewall.json" \
      || { rm -rf -- "$stage"; die "$(t 'Strict Ingress 防火墙恢复状态无效' \
        'Strict-ingress firewall restore state is invalid')"; }
  fi
  find "$stage/state" "$stage/config" -type f -name '*.json' -print0 2>/dev/null \
    | while IFS= read -r -d '' file; do jq empty "$file" >/dev/null || exit 1; done \
    || { rm -rf -- "$stage"; die '备份中存在无效 JSON'; }
  [ -e "$safe_state" ] || [ -L "$safe_state" ] || state_root_created=1
  [ -e "$safe_config" ] || [ -L "$safe_config" ] || config_root_created=1
  if [ "$state_root_created" -eq 1 ] && [ "$config_root_created" -eq 1 ]; then
    fresh_manager_restore=1
    nobrand_fresh_restore_runtime_preflight "$stage/state" \
      || { rm -rf -- "$stage"; die "$(t '仅管理器恢复时发生运行时或系统身份冲突' \
        'Manager-only restore has a runtime or system identity conflict')"; }
  fi
  # Validate any existing roots without changing their ownership or mode.
  # Missing roots remain absent until the complete recovery transaction is
  # atomically published below.
  for restore_root in "$safe_state" "$safe_config"; do
    if [ -e "$restore_root" ] || [ -L "$restore_root" ]; then
      [ -d "$restore_root" ] && [ ! -L "$restore_root" ] \
        && secure_stat_path "$restore_root" dir || {
        rm -rf -- "$stage"
        die "恢复根路径不是安全目录: $restore_root"
      }
    fi
  done
  # A primary generation contains SQLite and a Unix socket. Snapshot only a
  # stopped daemon, after all archive/ownership preflight has succeeded.
  if nb_splicore_installed; then
    primary_snapshot_active="$(nb_splicore_call status | jq -r 'if .active then 1 else 0 end')" || return 1
    nb_splicore_call stop || return 1
  fi
  if ! nobrand_backup_restore_transaction_prepare "$safe_state" "$safe_config" \
      "$state_root_created" "$config_root_created" "$fresh_manager_restore" applying; then
    [ "$primary_snapshot_active" -ne 1 ] || nb_splicore_call start || return 1
    rm -rf -- "$stage"
    return 1
  fi
  snapshot="$NOBRAND_BACKUP_RESTORE_SNAPSHOT_DIR"
  nobrand_backup_restore_transaction_valid || {
    rm -rf -- "$stage"
    warn "$(t "备份恢复事务无法安全校验；恢复快照已保留在: ${snapshot}" \
      "The backup-restore transaction could not be validated safely; its recovery snapshot was retained at: ${snapshot}")"
    return 1
  }
  # Only a fully valid canonical transaction authorizes materializing missing
  # roots or tightening an existing root. Any failure from here is recoverable
  # from the already-published `applying` snapshot.
  for restore_root in "$safe_state" "$safe_config"; do
    if [ -e "$restore_root" ] || [ -L "$restore_root" ]; then
      [ -d "$restore_root" ] && [ ! -L "$restore_root" ] || {
        rm -rf -- "$stage"
        warn "$(t "恢复根路径在事务发布后发生变化；恢复快照已保留在: ${snapshot}" \
          "A restore root changed after transaction publication; the recovery snapshot is retained at: ${snapshot}")"
        return 1
      }
    else
      mkdir -p "$restore_root" || {
        rm -rf -- "$stage"
        warn "$(t "无法创建恢复根路径；恢复快照已保留在: ${snapshot}" \
          "A restore root could not be created; the recovery snapshot is retained at: ${snapshot}")"
        return 1
      }
    fi
    chmod 0700 "$restore_root" \
      && chown root:root "$restore_root" 2>/dev/null \
      && secure_stat_path "$restore_root" dir || {
        rm -rf -- "$stage"
        warn "$(t "无法保护恢复根路径；恢复快照已保留在: ${snapshot}" \
          "A restore root could not be secured; the recovery snapshot is retained at: ${snapshot}")"
        return 1
      }
  done
  ssh_restore_log="$snapshot/ssh-external/created.log"
  if ! nobrand_stop_all_services 2>/dev/null; then
    rollback_failed=0
    if [ "$state_root_created" -eq 1 ]; then
      rmdir "$safe_state" 2>/dev/null || rollback_failed=1
    fi
    if [ "$config_root_created" -eq 1 ]; then
      rmdir "$safe_config" 2>/dev/null || rollback_failed=1
    fi
    if [ "$state_root_created" -eq 0 ] && [ "$config_root_created" -eq 0 ]; then
      nb_init_state_layout 2>/dev/null || rollback_failed=1
      nobrand_start_enabled_services 2>/dev/null || rollback_failed=1
    fi
    if [ "$rollback_failed" -eq 0 ]; then
      nobrand_backup_restore_transaction_cleanup || rollback_failed=1
    fi
    if [ "$rollback_failed" -eq 0 ]; then
      rm -rf -- "$stage" || rollback_failed=1
    fi
    if [ "$rollback_failed" -ne 0 ]; then
      warn "$(t "停止现有服务失败，且原运行状态未能完整恢复；恢复材料保留在: ${snapshot}；导入暂存保留在: ${stage}" \
        "Stopping existing services failed and their original runtime state could not be fully restored; recovery material is retained at: ${snapshot}; import staging is retained at: ${stage}")"
      return 1
    fi
    die "$(t '无法安全停止现有 NoBrand 服务；备份尚未导入' \
      'Existing NoBrand services could not be stopped safely; the backup was not imported')"
    return 1
  fi
  if ! find "$safe_state" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + \
     || ! find "$safe_config" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + \
     || ! cp -a "$stage/state/." "$safe_state/" \
     || ! cp -a "$stage/config/." "$safe_config/" \
     || ! nobrand_backup_tree_matches "$stage/state" "$safe_state" \
     || ! nobrand_backup_tree_matches "$stage/config" "$safe_config"; then
    rollback_failed=0
    nobrand_backup_restore_managed_roots "$safe_state" "$safe_config" "$snapshot" \
      && managed_roots_restored=1 || rollback_failed=1
    if [ "$managed_roots_restored" -eq 1 ] && [ "$state_root_created" -eq 1 ]; then
      rmdir "$safe_state" 2>/dev/null || rollback_failed=1
    fi
    if [ "$managed_roots_restored" -eq 1 ] && [ "$config_root_created" -eq 1 ]; then
      rmdir "$safe_config" 2>/dev/null || rollback_failed=1
    fi
    if [ "$state_root_created" -eq 0 ] && [ "$config_root_created" -eq 0 ]; then
      nb_init_state_layout 2>/dev/null || rollback_failed=1
      nobrand_start_enabled_services 2>/dev/null || rollback_failed=1
    fi
    if [ "$rollback_failed" -ne 0 ]; then
      warn "$(t "导入 state/config 失败且原状态未能完整恢复；唯一恢复快照保留在: ${snapshot}；导入暂存保留在: ${stage}" \
        "Importing state/config failed and the original state could not be fully restored; the only recovery snapshot is retained at: ${snapshot}; import staging is retained at: ${stage}")"
      return 1
    fi
    rm -rf -- "$stage" || {
      warn "$(t "导入失败已回滚，但无法清理导入暂存；恢复快照保留在: ${snapshot}；暂存位于: ${stage}" \
        "The failed import was rolled back, but import staging could not be removed; the recovery snapshot is retained at: ${snapshot}; staging is at: ${stage}")"
      return 1
    }
    nobrand_backup_restore_transaction_cleanup || {
      warn "$(t "导入失败已回滚，但恢复快照无法安全清理，已保留在: ${snapshot}" \
        "The failed import was rolled back, but the recovery snapshot could not be safely removed and remains at: ${snapshot}")"
      return 1
    }
    die '恢复失败，已回滚原 NoBrand state/config'
    return 1
  fi
  if ! nobrand_backup_restore_transaction_write runtime-applying \
      "$state_root_created" "$config_root_created" "$fresh_manager_restore"; then
    restore_failed=1
  elif ! nb_init_state_layout; then
    restore_failed=1
  elif ! ssh_tunnel_prepare_restored_policy_state; then
    restore_failed=1
  elif ! nobrand_restore_protocol_runtimes; then
    restore_failed=1
  elif ssh_tunnel_restore_system_state "$ssh_restore_log"; then
    nobrand_start_enabled_services || restore_failed=1
  else
    ssh_restore_rc=$?
    if [ "$ssh_restore_rc" -eq 75 ]; then
      warn "$(t "SSH watchdog 的回滚所有权尚未解决；为避免并发覆盖，备份回滚已停止。恢复快照保留在: ${snapshot}；导入暂存保留在: ${stage}" \
        "SSH watchdog rollback ownership is unresolved; backup rollback stopped to avoid a concurrent overwrite. Recovery snapshot retained at: ${snapshot}; import staging retained at: ${stage}")"
      return 1
    fi
    restore_failed=1
  fi
  if [ "$restore_failed" -eq 0 ] && ssh_tunnel_state_exists; then
    pending_operation="$(ssh_tunnel_state_field pending_operation 2>/dev/null || true)"
    pending_token="$(ssh_tunnel_state_field pending_watchdog_token 2>/dev/null || true)"
    if [ "$pending_operation" = restore ] && [ -n "$pending_token" ] \
      && [ "$pending_token" != disabled ]; then
      ssh_confirmation_pending=1
      nobrand_backup_restore_transaction_mark_ssh_pending || restore_failed=1
    elif [ -n "$pending_operation" ] || [ -n "$pending_token" ] \
         || [ "$(ssh_tunnel_state_field policy_applied 2>/dev/null || true)" != true ]; then
      restore_failed=1
    fi
  fi
  if [ "$restore_failed" -ne 0 ]; then
    if ! nobrand_backup_restore_recover_applying; then
      warn "$(t "恢复验收失败且回滚未完整完成；唯一恢复快照保留在: ${snapshot}；导入暂存保留在: ${stage}" \
        "Restore acceptance failed and rollback did not complete; the only recovery snapshot is retained at: ${snapshot}; import staging is retained at: ${stage}")"
      return 1
    fi
    rm -rf -- "$stage" || {
      warn "$(t "恢复验收失败已回滚，但导入暂存无法清理: ${stage}" \
        "Restore acceptance failed and was rolled back, but import staging could not be removed: ${stage}")"
      return 1
    }
    die "$(t 'NoBrand 恢复的服务/策略验收失败，state/config 已回滚' \
      'NoBrand restore service/policy acceptance failed; state/config were rolled back')"
    return 1
  fi
  rm -rf -- "$stage" || {
    warn "$(t "备份已导入，但暂存目录无法清理；恢复快照保留在: ${snapshot}；暂存位于: ${stage}" \
      "The backup was imported, but import staging could not be removed; the recovery snapshot is retained at: ${snapshot}; staging is at: ${stage}")"
    return 1
  }
  if [ "$ssh_confirmation_pending" -eq 1 ]; then
    t "NoBrand 备份已导入；全局恢复快照将保留到全新管理员 SSH 连接确认完成: ${snapshot}" \
      "NoBrand backup imported; the global recovery snapshot will be retained until brand-new administrator SSH confirmation completes: ${snapshot}"
    return 0
  fi
  nobrand_backup_restore_transaction_cleanup || {
    warn "$(t "备份已恢复，但持久恢复快照无法安全清理，已保留在: ${snapshot}" \
      "The backup was restored, but its durable recovery snapshot could not be safely retired and remains at: ${snapshot}")"
    return 1
  }
  t 'NoBrand 备份恢复完成' 'NoBrand backup restored'
}

nobrand_backup_action() {
  case "${NOBRAND_BACKUP_ACTION:-create}" in
    create) nobrand_backup_create "${NOBRAND_BACKUP_PATH:-}" ;;
    list) nobrand_backup_list ;;
    restore)
      [ -n "${NOBRAND_BACKUP_PATH:-}" ] \
        || die "$(t '备份恢复需要文件路径' 'Backup restore requires a file path')"
      nobrand_backup_restore "$NOBRAND_BACKUP_PATH"
      ;;
  esac
}

nobrand_remove_owned_command() {
  local path="$1"
  [ -e "$path" ] || [ -L "$path" ] || return 0
  case "$path" in
    "$NOBRAND_INSTALL_SCRIPT_PATH"|"$NOBRAND_COMMAND_PATH"|"$NOBRAND_SHORT_COMMAND_PATH") ;;
    *) warn "拒绝删除 NoBrand command allowlist 以外的路径: $path"; return 1 ;;
  esac
  if [ -L "$path" ]; then
    case "$path:$(readlink "$path" 2>/dev/null || true)" in
      "$NOBRAND_COMMAND_PATH:$NOBRAND_INSTALL_SCRIPT_PATH"|\
      "$NOBRAND_SHORT_COMMAND_PATH:$NOBRAND_COMMAND_PATH") rm -f "$path" ;;
      *) warn "拒绝删除目标不属于 NoBrand 的符号链接: $path"; return 1 ;;
    esac
  elif grep -qF 'NoBrand-OneClick' "$path" 2>/dev/null; then
    rm -f "$path"
  else
    warn "拒绝删除内容不属于 NoBrand 的命令: $path"
    return 1
  fi
}

nobrand_clear_managed_root() {
  local root="$1"
  if [ ! -e "$root" ] && [ ! -L "$root" ]; then
    return 0
  fi
  [ -d "$root" ] && [ ! -L "$root" ] || {
    warn "拒绝清理非目录或符号链接 NoBrand root: $root"
    return 1
  }
  find "$root" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + || return 1
  rmdir "$root" 2>/dev/null || {
    [ ! -e "$root" ] || return 1
  }
}

nobrand_uninstall_postcondition() {
  local path failed=0
  for path in "$NOBRAND_STATE_DIR" "$NOBRAND_CONFIG_DIR" "$NOBRAND_LIB_DIR" \
    "$NOBRAND_SHORT_COMMAND_PATH" "$NOBRAND_COMMAND_PATH" "$NOBRAND_INSTALL_SCRIPT_PATH"; do
    if [ -e "$path" ] || [ -L "$path" ]; then
      warn "完整卸载验收发现 NoBrand 残留: $path"
      failed=1
    fi
  done
  [ "$failed" -eq 0 ]
}

nobrand_uninstall_impl() {
  nb_splicore_legacy_preflight || return 1
  local port safe_state safe_config safe_lib pairs="" failed=0
  safe_state="$(nb_assert_safe_nobrand_root "$NOBRAND_STATE_DIR" NOBRAND_STATE_DIR)" || return 1
  safe_config="$(nb_assert_safe_nobrand_root "$NOBRAND_CONFIG_DIR" NOBRAND_CONFIG_DIR)" || return 1
  safe_lib="$(nb_assert_safe_nobrand_root "$NOBRAND_LIB_DIR" NOBRAND_LIB_DIR)" || return 1
  # Remove the externally shared sshd policy first. With the real watchdog this
  # is a two-phase operation: no other protocol is touched until a brand-new
  # administrator SSH session confirms that system access still works.
  if ssh_tunnel_state_exists; then
    ssh_tunnel_uninstall unified-uninstall || return 1
    if ssh_tunnel_state_exists \
       && [ "$(ssh_tunnel_state_field pending_operation 2>/dev/null || true)" = unified-uninstall ]; then
      t '统一卸载等待全新管理员 SSH 连接确认；确认前其它协议保持不变' \
        'Unified uninstall is waiting for a brand-new administrator SSH connection; other protocols remain unchanged until confirmation'
      return 0
    fi
  fi
  if nb_splicore_installed; then
    nb_splicore_call purge || return 1
  fi
  admin_lock_acquire || return 1
  if [ -s "$NOBRAND_FORWARD_STATE_FILE" ] || [ -s "$NOBRAND_REALM_RUNTIME_META" ] \
     || [ -e "$NOBRAND_REALM_SYSTEMD_SERVICE" ] || [ -e "$NOBRAND_REALM_OPENRC_SERVICE" ]; then
    forward_uninstall || failed=1
  elif command -v nft >/dev/null 2>&1 \
       && nft list table "$NOBRAND_FORWARD_NFT_FAMILY" "$NOBRAND_FORWARD_NFT_TABLE" >/dev/null 2>&1; then
    forward_remove_owned_nft_table || failed=1
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
    warn "$(t 'NoBrand 服务/防火墙清理未完整完成；保留 state 以便重试' \
      'NoBrand service/firewall cleanup was incomplete; state was kept for retry')"
    return 1
  fi
  [ "$(nb_service_manager)" != systemd ] \
    || systemctl daemon-reload 2>/dev/null || failed=1
  if [ "$failed" -ne 0 ]; then
    admin_lock_release
    warn "$(t 'NoBrand 服务运行时清理未完整完成；保留 state/config 及管理器以便安全重试' \
      'NoBrand service-runtime cleanup was incomplete; state/config and manager were kept for a safe retry')"
    return 1
  fi
  admin_lock_release

  nb_strict_firewall_clear_all || return 1
  rm -f "$NOBRAND_INGRESS_FIREWALL_STATE_FILE" "$NOBRAND_INGRESS_FIREWALL_RULESET"
  nb_lifecycle_checkpoint uninstall runtime-removed || return 1

  # State/config/lib roots are exact, validated NoBrand roots. Command removal
  # deliberately happens only after every protocol/resource cleanup succeeds.
  nb_lifecycle_checkpoint uninstall before-state-removal || return 1
  nobrand_clear_managed_root "$safe_state" || return 1
  nb_lifecycle_checkpoint uninstall state-removed || return 1
  nb_lifecycle_checkpoint uninstall before-config-removal || return 1
  nobrand_clear_managed_root "$safe_config" || return 1
  nb_lifecycle_checkpoint uninstall config-removed || return 1
  nobrand_clear_managed_root "$safe_lib" || return 1
  nb_lifecycle_checkpoint uninstall roots-removed || return 1
  nb_lifecycle_checkpoint uninstall before-manager-removal || return 1
  nobrand_remove_owned_command "$NOBRAND_SHORT_COMMAND_PATH" || failed=1
  nobrand_remove_owned_command "$NOBRAND_COMMAND_PATH" || failed=1
  nobrand_remove_owned_command "$NOBRAND_INSTALL_SCRIPT_PATH" || failed=1
  [ "$failed" -eq 0 ] || return 1
  nb_lifecycle_checkpoint uninstall manager-removed || return 1
}

nobrand_uninstall() {
  nb_splicore_legacy_preflight || return 1
  local state rc=0
  require_root || return 1
  if nobrand_backup_restore_transaction_present; then
    die "$(t '备份恢复事务尚未完成；请先通过修复流程完成 SSH 验收，拒绝卸载恢复证据' \
      'A backup-restore transaction is unfinished; complete SSH acceptance through repair before uninstalling recovery evidence')"
    return 1
  fi
  state="$(nb_classify_installation_state)" || return 1
  case "$state" in
    CLEAN)
      t 'NoBrand 管理资源已不存在，无需再次卸载。' \
        'NoBrand-managed resources are already absent; nothing remains to uninstall.'
      return 0
      ;;
    CURRENT_COMPLETE|CURRENT_PARTIAL_INSTALL|CURRENT_PARTIAL_REPAIR|\
      CURRENT_PARTIAL_CONFIGURE)
      nb_schema_v3_file_valid \
        || die '未检测到有效的 NoBrand schema v3 state，拒绝卸载未知资源'
      ;;
    CURRENT_PARTIAL_UNINSTALL) ;;
    LEGACY_UNSUPPORTED) nb_fail_legacy_state; return 1 ;;
    *) nb_fail_ambiguous_state; return 1 ;;
  esac
  if [ "${YES:-0}" -ne 1 ]; then
    confirm '确认完整卸载 NoBrand 3 管理的 Mieru/Snell/HY2/TUIC/VLESS REALITY/VLESS Sudoku/SSH Tunnel/Forward/Common？[y/N]: ' \
      'Completely uninstall NoBrand-3-managed Mieru/Snell/HY2/TUIC/VLESS REALITY/VLESS Sudoku/SSH Tunnel/Forward/Common resources? [y/N]: ' \
      n \
      || { t '已取消' 'Cancelled'; return 0; }
  fi
  nb_lifecycle_lock_acquire || return 1
  state="$(nb_classify_installation_state)" || {
    nb_lifecycle_lock_release
    return 1
  }
  case "$state" in
    CLEAN)
      nb_lifecycle_lock_release
      return 0
      ;;
    CURRENT_COMPLETE|CURRENT_PARTIAL_INSTALL|CURRENT_PARTIAL_REPAIR|\
      CURRENT_PARTIAL_CONFIGURE)
      if ! nb_schema_v3_file_valid; then
        nb_lifecycle_lock_release
        return 1
      fi
      ;;
    CURRENT_PARTIAL_UNINSTALL) ;;
    *)
      nb_lifecycle_lock_release
      nb_fail_ambiguous_state
      return 1
      ;;
  esac
  nb_lifecycle_pre_mutation_snapshot || {
    nb_lifecycle_lock_release
    return 1
  }
  nb_lifecycle_begin uninstall prepare 0 0 0 0 0 0 global || {
    nb_lifecycle_pre_mutation_disarm
    nb_lifecycle_lock_release
    return 1
  }
  nb_lifecycle_mark_mutation_started || {
    rc=$?
    nb_lifecycle_restore_pre_mutation || rc=1
    nb_lifecycle_lock_release
    return "$rc"
  }
  nobrand_uninstall_impl
  rc=$?
  if [ "$rc" -ne 0 ]; then
    nb_lifecycle_lock_release
    return "$rc"
  fi
  # SSH policy removal is deliberately two-phase. The first invocation stops
  # here with an in-progress uninstall transaction; a fresh administrator SSH
  # session confirms access and then resumes this same uninstall. Running the
  # final all-roots-absent postcondition now would misreport the intended wait
  # as a cleanup failure.
  if ssh_tunnel_state_exists \
     && [ "$(ssh_tunnel_state_field pending_operation 2>/dev/null || true)" = unified-uninstall ]; then
    nb_lifecycle_lock_release
    return 0
  fi
  nb_lifecycle_checkpoint uninstall before-final-validation || {
    rc=$?
    nb_lifecycle_lock_release
    return "$rc"
  }
  nobrand_uninstall_postcondition || {
    nb_lifecycle_lock_release
    return 1
  }
  nb_lifecycle_clear || {
    nb_lifecycle_lock_release
    return 1
  }
  nb_lifecycle_lock_release
  t 'NoBrand 3 的 Mieru/Snell/HY2/TUIC/VLESS REALITY/VLESS Sudoku/SSH Tunnel/Forward/Common 资源与 nobrand/nb 已完整删除；外部资源未触碰' \
    'NoBrand 3 Mieru/Snell/HY2/TUIC/VLESS REALITY/VLESS Sudoku/SSH Tunnel/Forward/Common resources and nobrand/nb were removed; external resources were untouched'
  t '如当前 Bash 会话仍缓存 nb/nobrand 路径，可执行 `hash -r` 清除命令缓存。' \
    'If the current Bash session still caches the nb/nobrand path, run `hash -r` to clear its command cache.'
  if [ "${MENU_MODE:-0}" -eq 1 ]; then
    # Status 4 is an ordinary shell status and cannot authenticate this path
    # by itself. The menu wrapper resets and checks this completion marker in
    # the same subprocess, after every global-uninstall postcondition above.
    NOBRAND_MENU_GLOBAL_UNINSTALL_CONFIRMED=1
    return "$NOBRAND_MENU_EXIT_SUCCESS"
  fi
}

nobrand_stop_all_services() {
  nb_splicore_legacy_preflight || return 1
  local failed=0
  if nb_splicore_installed; then nb_splicore_call stop || return 1; fi
  if vless_sudoku_state_exists; then nobrand_vless_sudoku_service_action stop || failed=1; fi
  if [ -s "$NOBRAND_FORWARD_STATE_FILE" ]; then forward_realm_service_action stop || failed=1; fi
  return "$failed"
}

nobrand_start_enabled_services() {
  nb_splicore_legacy_preflight || return 1
  if nb_splicore_installed; then nb_splicore_call start || return 1; fi
  if vless_sudoku_state_exists; then nobrand_vless_sudoku_service_action start || return 1; fi
  forward_realm_restore_runtime
}
