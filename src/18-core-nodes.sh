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
  cat <<EOF
NoBrand-OneClick 3.2.0 — Multi-Ingress / Mieru / Snell v4-v5 / Hysteria2 / TUIC v5 / VLESS REALITY / VLESS + FinalMask + Sudoku / SSH Tunnel / Port Forward

用法:
  nobrand                         打开统一菜单
  nb                              与 nobrand 完全相同的短别名
  nobrand --version               显示产品版本与作者
  nobrand --help                  显示本帮助
  nobrand status                  综合状态
  nobrand nodes [--protocol P]    查看全部或指定协议节点
  nobrand doctor                  综合诊断（默认不输出 secret）
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
  nobrand mieru user-set-quota|user-set-expire|user-enable|user-disable
  nobrand mieru user-scan|user-quota-reset|user-set-rate|user-usage
  nobrand mieru user-backup|user-restore|user-export|user-import|user-export-clients
  Mieru 参数: --port --protocol --profile --advertise-host --advertise-port --advertise-auto
    --ingress-profile PROFILE
    --mtu --traffic-pattern --low-entropy --multiplexing --handshake-mode
    --mieru-channel --mieru-version --user --password --package --quota-mb
    --quota-days --quota-mode --expire --bandwidth --op-user --enable-bbr --lang

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

  nobrand vless-reality install --name NAME [--target HOST] [--target-port PORT]
      [--ingress-profile PROFILE] [--port PORT]
      [--advertise-host HOST --advertise-port PORT | --advertise-auto] [-y]
      Default camouflage host: auto-select from the release-qualified pool and persist the selected hostname.
      An explicit host is used exactly; host and target port are independently configurable.
      443 is the camouflage target port default, not the public REALITY listen port.
  nobrand vless-reality show|export|status|doctor|start|stop|restart|remove [--name NAME]
  nobrand vless-reality set-endpoint --name NAME
      [--advertise-host HOST --advertise-port PORT | --advertise-auto]

  nobrand tuic install --name NAME --user USER [--port PORT] [--sni SNI]
      [--channel stable|latest | --runtime-version VERSION]
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
  - Snell v5 QUIC 默认关闭；--quic on 才让 NoBrand 管理同号 UDP firewall ownership。
  - 官方 v5 runtime 即使 QUIC 关闭也可能监听同号 UDP；本地 socket 不等于公网 QUIC 已启用。
  - Display Endpoint 只影响客户端输出，不创建 DNAT/IPLC 转发，也不改 listener。
  - 非交互 -y 必须明确给出完整 Display Endpoint 或 --advertise-auto。
  - VLESS Sudoku = plain VLESS + FinalMask(sudoku) + TCP。
  - VLESS REALITY = VLESS + TCP + REALITY + xtls-rprx-vision；public Profile 推荐，mapped 仅警告。
  - VLESS Encryption: NOT USED；不调用密钥生成子命令，不保存加密密钥。
  - TUIC 只支持 v5：official sing-box、UDP/QUIC、每用户独立 UUID + password。
  - SSH Tunnel 复用现有 sshd；允许 -L/-D/-R TCP forwarding，不允许 shell/exec/TTY/SFTP/SCP。
  - SSH Tunnel 使用 AllowTcpForwarding=yes，因此可访问服务器自身可达的 TCP destinations；GatewayPorts=no。
  - SSH Tunnel 不拥有 sshd listener、SSH firewall、host keys 或 admin authentication。
  - Port Forward: nftables 为 IPv4 kernel NAT；Realm 为 official userspace relay，可使用 IP/domain target。
  - Forward 的 Display Endpoint 仅为 metadata；xx00 对 nftables/Realm 和 TCP/UDP 均保留。
  - Ingress 决定端口策略、展示默认值和入口身份；Linux 系统路由继续独立决定 Egress。
  - Ingress Profile 不修改网卡、地址、路由、ip rule、sysctl、SSH 或 provider mapping。
  - PROTOCOL_FEATURE_FREEZE=${PROTOCOL_FEATURE_FREEZE}（VLESS REALITY 是 3.2 最后一个协议功能）。
  - Mieru 官方 runtime 仍名为 mita，但它不是管理命令；管理入口只有 nobrand/nb。
  - v3 state 必须带 schema_version=3；旧 state 不读取、不导入、不删除。
  - 正式安装器: ${NOBRAND_RELEASE_INSTALLER_URL}
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
  ln -sfn "$NOBRAND_INSTALL_SCRIPT_PATH" "$NOBRAND_COMMAND_PATH" || return 1
  ln -sfn "$NOBRAND_COMMAND_PATH" "$NOBRAND_SHORT_COMMAND_PATH" || return 1
  cmp -s "$source_path" "$NOBRAND_INSTALL_SCRIPT_PATH" || return 1
  [ "$(readlink "$NOBRAND_COMMAND_PATH" 2>/dev/null || true)" = "$NOBRAND_INSTALL_SCRIPT_PATH" ] || return 1
  [ "$(readlink "$NOBRAND_SHORT_COMMAND_PATH" 2>/dev/null || true)" = "$NOBRAND_COMMAND_PATH" ] || return 1
}

nobrand_manager_upgrade() {
  require_root
  require_linux
  nobrand_install_manager_script \
    || die 'NoBrand manager install/upgrade failed; protocol state was not modified'
  t "NoBrand unified manager 已从当前 exact installer 安装/升级至 v${SCRIPT_VERSION}" \
    "NoBrand unified manager installed/upgraded from the current exact installer to v${SCRIPT_VERSION}"
}

nb_mieru_instance_running() {
  local instance_id="$1" transport="$2" port="$3" unit service
  unit="nobrand-mieru@${instance_id}.service"
  service="nobrand-mieru-${instance_id}"
  nb_service_is_active "$unit" "$service" || return 1
  case "$transport" in
    BOTH) nb_port_is_listening TCP "$port" && nb_port_is_listening UDP "$((port + 1))" ;;
    *) nb_port_is_listening "$transport" "$port" ;;
  esac
}

# protocol|name|display endpoint|status|transport
nb_mieru_node_rows() {
  local instance_id name port protocol advertise_host advertise_port ingress_profile_id
  local effective_host effective_port status
  [ -s "$MITA_USERS_STATE" ] || return 0
  command -v python3 >/dev/null 2>&1 || return 0
  # Use a non-whitespace delimiter so empty custom endpoint fields keep their
  # column positions before the trailing Profile association.
  while IFS='|' read -r instance_id name port protocol advertise_host advertise_port ingress_profile_id; do
    [ -n "$name" ] || continue
    ingress_profile_id="${ingress_profile_id:-$NOBRAND_LEGACY_INGRESS_PROFILE_ID}"
    if [ -n "$advertise_host" ]; then
      effective_host="$advertise_host"
    else
      effective_host="$(nb_effective_advertise_host auto '' "$ingress_profile_id")"
    fi
    if [ -n "$advertise_port" ]; then
      effective_port="$advertise_port"
    else
      effective_port="$(nb_effective_advertise_port auto '' "$port" "$ingress_profile_id")"
    fi
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
    print("|".join(str(v or "") for v in (
        user.get("instance_id"), user.get("name"), user.get("port"), protocol,
        user.get("advertise_host"), user.get("advertise_port"),
        user.get("ingress_profile_id"))))
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
      tuic_node_rows
      reality_node_rows
      vless_sudoku_node_rows
      ssh_tunnel_node_rows
      forward_node_rows
      ;;
    mieru) nb_mieru_node_rows ;;
    snell) snell_node_rows ;;
    hy2|hysteria2) hysteria2_node_rows ;;
    tuic) tuic_node_rows ;;
    vless-reality|reality) reality_node_rows ;;
    vless-sudoku|sudoku) vless_sudoku_node_rows ;;
    vless) reality_node_rows; vless_sudoku_node_rows ;;
    ssh|ssh-tunnel) ssh_tunnel_node_rows ;;
    forward|port-forward) forward_node_rows ;;
    *) die "--protocol 只支持 mieru、snell、hy2、tuic、vless-reality、vless-sudoku、ssh、forward" ;;
  esac
}

nb_owner_ingress_profile_id() {
  local owner="$1" id
  case "$owner" in
    snell:*) snell_state_field "${owner#snell:}" ingress_profile_id 2>/dev/null || true ;;
    hy2:*) hysteria2_state_field ingress_profile_id 2>/dev/null || true ;;
    vless-sudoku:*) vless_sudoku_state_field ingress_profile_id 2>/dev/null || true ;;
    vless-reality:*) reality_state_field "${owner#vless-reality:}" ingress_profile_id 2>/dev/null || true ;;
    tuic:*) tuic_state_field "${owner#tuic:}" ingress_profile_id 2>/dev/null || true ;;
    forward:*)
      jq -r --arg id "${owner#forward:}" '.rules[]|select(.rule_id==$id)|.ingress_profile_id // empty' \
        "$NOBRAND_FORWARD_STATE_FILE" 2>/dev/null || true
      ;;
    mieru:*)
      id="${owner#mieru:}"
      jq -r --arg id "$id" '.users[]|select((.instance_id // .name // (.port|tostring))==$id)|.ingress_profile_id // empty' \
        "$MITA_USERS_STATE" 2>/dev/null || true
      ;;
  esac
}

nb_owner_state_file() {
  case "$1" in
    snell:*) snell_state_path "${1#snell:}" ;;
    hy2:*) printf '%s' "$NOBRAND_HY2_STATE_FILE" ;;
    vless-sudoku:*) printf '%s' "$NOBRAND_VLESS_STATE_FILE" ;;
    vless-reality:*) reality_state_file "${1#vless-reality:}" ;;
    tuic:*) tuic_state_file "${1#tuic:}" ;;
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
    mieru:*)
      id="${owner#mieru:}"
      jq -r --arg id "$id" '.users[]|select((.instance_id // .name // (.port|tostring))==$id)|.ingress_enforcement // "permissive"' \
        "$MITA_USERS_STATE" 2>/dev/null
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
    mieru:*)
      id="${owner#mieru:}"
      jq -r --arg id "$id" '.users[]|select((.instance_id // .name // (.port|tostring))==$id)|.ingress_enforcement_method // "wildcard"' \
        "$MITA_USERS_STATE" 2>/dev/null
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
    mieru:*)
      id="${owner#mieru:}"
      jq -r --arg id "$id" '.users[]|select((.instance_id // .name // (.port|tostring))==$id)|.ingress_local_address // empty' \
        "$MITA_USERS_STATE" 2>/dev/null
      ;;
    ssh-tunnel:*) return 0 ;;
    *) path="$(nb_owner_state_file "$owner")" && nb_ingress_state_local_address "$path" "$profile_id" ;;
  esac
}

nb_owner_enabled() {
  local owner="$1" path id
  case "$owner" in
    forward:*) id="${owner#forward:}"; jq -r --arg id "$id" '.rules[]|select(.rule_id==$id)|.enabled' "$NOBRAND_FORWARD_STATE_FILE" 2>/dev/null ;;
    mieru:*) id="${owner#mieru:}"; jq -r --arg id "$id" '.users[]|select((.instance_id // .name // (.port|tostring))==$id)|.enabled' "$MITA_USERS_STATE" 2>/dev/null ;;
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
      strict:firewall) actual="*:${port}/${transport} (firewall restricted to ${address})" ;;
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
      printf 'ssh-tunnel:%s|*:%s/TCP (system sshd)|%s:%s|%s|Not applicable (system sshd)\n' "$owner" \
        "$(ssh_tunnel_state_field real_port)" "$(ssh_tunnel_effective_host)" \
        "$(ssh_tunnel_state_field advertise_port)" "$(nb_ingress_profile_name "$profile_id")"
    done < <(jq -r '.users[]?.display_name' "$NOBRAND_SSH_STATE_FILE")
  fi
}

nobrand_nodes() {
  local rows details protocol name endpoint status transport owner actual display ingress enforcement
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
  details="$(nb_node_detail_rows "${NOBRAND_PROTOCOL_FILTER:-}")"
  if [ -n "$details" ]; then
    msg ''
    t 'Actual / Display / Ingress Profile（展示修改不影响监听）' \
      'Actual / Display / Ingress Profile (display changes do not affect listeners)'
    while IFS='|' read -r owner actual display ingress enforcement; do
      printf '%s\n  Actual: %s\n  Display: %s\n  Ingress: %s\n  Enforcement: %s\n' \
        "$owner" "$actual" "$display" "$ingress" "$enforcement"
    done <<<"$details"
  fi
}

nobrand_status() {
  local rows protocol _name _endpoint status _transport
  local mieru_total=0 mieru_running=0 snell_total=0 snell_running=0 hy2_total=0 hy2_running=0
  local tuic_total=0 tuic_running=0 ssh_total=0 ssh_ready=0
  local forward_nft_total=0 forward_nft_healthy=0 forward_realm_total=0 forward_realm_healthy=0
  local vless_total=0 vless_running=0 vless_port="" reality_total=0 reality_running=0
  local ingress_id ingress_name ingress_type
  local ingress_interface ingress_address ingress_policy ingress_host ingress_range
  rows="$(nb_all_node_rows)"
  while IFS='|' read -r protocol _name _endpoint status _transport; do
    case "$protocol" in
      Mieru/*) mieru_total=$((mieru_total + 1)); [ "$status" != Running ] || mieru_running=$((mieru_running + 1)) ;;
      Snell*) snell_total=$((snell_total + 1)); [ "$status" != Running ] || snell_running=$((snell_running + 1)) ;;
      Hysteria2) hy2_total=$((hy2_total + 1)); [ "$status" != Running ] || hy2_running=$((hy2_running + 1)) ;;
      'TUIC v5') tuic_total=$((tuic_total + 1)); [ "$status" != Running ] || tuic_running=$((tuic_running + 1)) ;;
      'SSH Tunnel') ssh_total=$((ssh_total + 1)); [ "$status" != Ready ] || ssh_ready=$((ssh_ready + 1)) ;;
      'Port Forward/nftables')
        forward_nft_total=$((forward_nft_total + 1)); [ "$status" != Healthy ] || forward_nft_healthy=$((forward_nft_healthy + 1))
        ;;
      'Port Forward/realm')
        forward_realm_total=$((forward_realm_total + 1)); [ "$status" != Healthy ] || forward_realm_healthy=$((forward_realm_healthy + 1))
        ;;
      VLESS/Sudoku)
        vless_total=$((vless_total + 1))
        [ "$status" != Running ] || vless_running=$((vless_running + 1))
        vless_port="$(vless_sudoku_state_field listen_port 2>/dev/null || true)"
        ;;
      'VLESS REALITY')
        reality_total=$((reality_total + 1))
        [ "$status" != Running ] || reality_running=$((reality_running + 1))
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
  printf 'TUIC v5\n  Users: %s\n  Running: %s/%s\n' "$tuic_total" "$tuic_running" "$tuic_total"
  printf 'VLESS/Sudoku\n  Installed: %s\n  Running: %s\n  Port: %s\n' \
    "$([ "$vless_total" -gt 0 ] && printf yes || printf no)" \
    "$([ "$vless_running" -gt 0 ] && printf yes || printf no)" \
    "${vless_port:--}"
  printf 'VLESS REALITY\n  Instances: %s\n  Running: %s/%s\n' \
    "$reality_total" "$reality_running" "$reality_total"
  printf 'SSH Tunnel\n  Users: %s\n  Ready: %s/%s\n  Listener ownership: external sshd\n' \
    "$ssh_total" "$ssh_ready" "$ssh_total"
  printf 'Port Forward\n  nftables: %s/%s healthy\n  Realm: %s/%s healthy\n' \
    "$forward_nft_healthy" "$forward_nft_total" "$forward_realm_healthy" "$forward_realm_total"
  msg 'Ingress'
  printf '  Default Profile: %s\n  Explicit profiles: %s\n' \
    "$(nb_ingress_profile_name "$(nb_ingress_default_profile_id 2>/dev/null || true)")" \
    "$([ -s "$NOBRAND_INGRESS_STATE_FILE" ] && jq '.profiles|length' "$NOBRAND_INGRESS_STATE_FILE" 2>/dev/null || printf 0)"
  if nb_ingress_state_valid; then
    while IFS=$'\t' read -r ingress_id ingress_name ingress_type ingress_interface ingress_address ingress_policy ingress_host; do
      ingress_range="$(nb_ingress_profile_auto_range "$ingress_id" 2>/dev/null | tr '|' '-' || printf manual)"
      printf '  %s: %s %s/%s, %s (%s), display=%s\n' \
        "$ingress_name" "$ingress_type" "$ingress_interface" "$ingress_address" \
        "$ingress_policy" "$ingress_range" "${ingress_host:--}"
    done < <(jq -r '.profiles[]|[.profile_id,.name,.type,.interface,.local_address,.port_policy,.display_host_default]|@tsv' \
      "$NOBRAND_INGRESS_STATE_FILE")
  fi
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
  elif command -v nft >/dev/null 2>&1; then
    nb_doctor_line PASS 'firewall=nftables'
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
  msg ''
  msg 'Ingress (read-only; does not verify provider mapping)'
  nb_ingress_doctor || failed=1
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
  msg 'TUIC v5'
  tuic_doctor_all || failed=1
  msg ''
  msg 'VLESS + FinalMask + Sudoku (TCP)'
  vless_sudoku_doctor || failed=1
  msg ''
  msg 'VLESS + TCP + REALITY + XTLS Vision'
  reality_doctor_all || failed=1
  msg ''
  msg 'SSH Tunnel (existing OpenSSH)'
  ssh_tunnel_doctor || failed=1
  if [ -s "$NOBRAND_FORWARD_STATE_FILE" ]; then
    msg ''
    msg 'Port Forward (nftables / Realm)'
    forward_doctor || failed=1
  fi
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
  local id major need_snell4=0 need_snell5=0 pm
  if users_state_exists && [ "$(users_count)" -gt 0 ]; then
    load_install_state || return 1
    pm="$(detect_pkg_manager)" || return 1
    ensure_management_dependencies "$pm" || return 1
    repair_mita_binary_paths || return 1
    ensure_mita_account || return 1
    install_instance_runtime || return 1
  fi

  while IFS= read -r id; do
    [ -n "$id" ] || continue
    snell_config_matches_state "$id" || return 1
    major="$(snell_state_field "$id" version)"
    case "$major" in
      4) need_snell4=1 ;;
      5) need_snell5=1 ;;
      *) return 1 ;;
    esac
  done < <(snell_instance_ids)
  if [ "$need_snell4" -eq 1 ] || [ "$need_snell5" -eq 1 ] \
     || hysteria2_state_exists || vless_sudoku_state_exists \
     || [ -n "$(reality_instance_ids)" ]; then
    nobrand_prepare_common || return 1
  fi
  [ "$need_snell4" -eq 0 ] || snell_install_runtime 4 0 || return 1
  [ "$need_snell5" -eq 0 ] || snell_install_runtime 5 0 || return 1
  if [ "$need_snell4" -eq 1 ] || [ "$need_snell5" -eq 1 ]; then
    snell_install_service_runtime || return 1
    while IFS= read -r id; do
      [ -n "$id" ] || continue
      snell_ensure_openrc_service "$id" || return 1
    done < <(snell_instance_ids)
  fi

  if hysteria2_state_exists || vless_sudoku_state_exists || [ -n "$(reality_instance_ids)" ]; then
    nobrand_install_xray_runtime 0 || return 1
    nobrand_xray_validate_managed_configs || return 1
  fi
  if hysteria2_state_exists; then
    nobrand_write_hy2_service || return 1
  fi
  if vless_sudoku_state_exists; then
    nobrand_write_vless_sudoku_service || return 1
  fi
  reality_restore_runtime || return 1
  tuic_restore_runtime || return 1
  forward_realm_restore_runtime || return 1
}

# The only safe way to synthesize system identities/package resources during
# a manager-only restore is to prove that those product-owned namespaces are
# currently empty.  Existing installations use their normal transaction
# snapshots instead and do not enter this path.
nobrand_fresh_restore_runtime_preflight() {
  local staged_state="$1" users_rel staged_users pm path
  users_rel="${MITA_USERS_STATE#${NOBRAND_STATE_DIR}/}"
  staged_users="${staged_state}/${users_rel}"
  for path in \
    "$NOBRAND_LIB_DIR" \
    "$MITA_INSTANCE_SYSTEMD_TEMPLATE" "$MITA_INSTANCE_TMPFILES" \
    "$NOBRAND_SNELL_SYSTEMD_TEMPLATE" "$NOBRAND_HY2_SYSTEMD_SERVICE" \
    "$NOBRAND_VLESS_SYSTEMD_SERVICE" "$NOBRAND_REALITY_SYSTEMD_TEMPLATE" "$NOBRAND_TUIC_SYSTEMD_TEMPLATE" \
    "$NOBRAND_REALM_SYSTEMD_SERVICE"; do
    [ ! -e "$path" ] && [ ! -L "$path" ] || return 1
  done
  if [ -s "$staged_users" ] && [ "$(jq '.users | length' "$staged_users" 2>/dev/null || printf 0)" -gt 0 ]; then
    pm="$(detect_pkg_manager)" || return 1
    ! mita_package_is_installed "$pm" || return 1
    ! _has_user mita || return 1
    ! _has_group mita || return 1
    ! command -v mita >/dev/null 2>&1 || return 1
    for path in /etc/mita /var/lib/mita /run/mita /var/run/mita /var/run/mita.sock; do
      [ ! -e "$path" ] && [ ! -L "$path" ] || return 1
    done
  fi
}

# This cleanup is used only after the fresh-manager preflight above proved
# that the affected package/accounts/units did not pre-exist.  It must run
# while restored state still exists so every firewall and service identity is
# available for exact cleanup.
nobrand_remove_fresh_restore_protocol_resources() {
  local id port pairs pm failed=0
  if users_state_exists && [ "$(users_count)" -gt 0 ]; then
    isolated_stop_all >/dev/null 2>&1 || failed=1
    firewall_clear_all_owned >/dev/null 2>&1 || failed=1
    tc_clear_owned_filters >/dev/null 2>&1 || true
    pm="$(detect_pkg_manager 2>/dev/null || true)"
    case "$pm" in
      deb)
        if dpkg-query -W mita >/dev/null 2>&1; then
          dpkg -P mita >/dev/null 2>&1 || failed=1
        fi
        ;;
      rpm)
        if rpm -q mita >/dev/null 2>&1; then
          rpm -e mita >/dev/null 2>&1 || failed=1
        fi
        ;;
    esac
    if ! ( UNINSTALL_PRESERVE_PACKAGE=0 UNINSTALL_PRESERVE_USER=0 \
           UNINSTALL_PRESERVE_GROUP=0 UNINSTALL_PRESERVE_SHARED=0 \
           remove_mita_common >/dev/null 2>&1 ); then
      failed=1
    fi
    ! _has_user mita || failed=1
    ! _has_group mita || failed=1
  fi
  nb_strict_firewall_clear_all >/dev/null 2>&1 || failed=1
  rm -f "$NOBRAND_INGRESS_FIREWALL_STATE_FILE" "$NOBRAND_INGRESS_FIREWALL_RULESET"

  while IFS= read -r id; do
    [ -n "$id" ] || continue
    pairs="$(snell_firewall_pairs "$id" 2>/dev/null || true)"
    snell_remove_service "$id" >/dev/null 2>&1 || failed=1
    [ -z "$pairs" ] || nb_firewall_close_pairs "$pairs" >/dev/null 2>&1 || failed=1
  done < <(snell_instance_ids)
  rm -f "$NOBRAND_SNELL_SYSTEMD_TEMPLATE" "$NOBRAND_SNELL_RUNNER" || failed=1
  rm -rf -- "$NOBRAND_SNELL_RUNTIME_DIR" || failed=1

  if hysteria2_state_exists; then
    port="$(hysteria2_state_field listen_port 2>/dev/null || true)"
    nobrand_remove_hy2_service >/dev/null 2>&1 || failed=1
    [ -z "$port" ] || nb_firewall_close_pairs "UDP|${port}" >/dev/null 2>&1 || failed=1
  fi
  if vless_sudoku_state_exists; then
    port="$(vless_sudoku_state_field listen_port 2>/dev/null || true)"
    nobrand_remove_vless_sudoku_service >/dev/null 2>&1 || failed=1
    [ -z "$port" ] || nb_firewall_close_pairs "TCP|${port}" >/dev/null 2>&1 || failed=1
  fi
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    port="$(reality_state_field "$id" listen_port 2>/dev/null || true)"
    reality_remove_service "$id" >/dev/null 2>&1 || failed=1
    [ -z "$port" ] || nb_firewall_close_pairs "TCP|${port}" >/dev/null 2>&1 || failed=1
  done < <(reality_instance_ids)
  reality_remove_service_runtime_if_owned || failed=1
  nobrand_remove_xray_runtime_files || failed=1
  [ "$(nb_service_manager)" != systemd ] || systemctl daemon-reload >/dev/null 2>&1 || failed=1
  rmdir "$NOBRAND_BIN_DIR" "$NOBRAND_LIB_DIR" 2>/dev/null || true
  return "$failed"
}

nobrand_backup_restore() {
  local source="$1" stage snapshot safe_state safe_config ssh_restore_log restore_root
  local state_root_created=0 config_root_created=0 fresh_manager_restore=0
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
  grep -qx 'schema_version=3' "$stage/manifest.txt" 2>/dev/null \
    && grep -qx 'ownership=nobrand-v3' "$stage/manifest.txt" 2>/dev/null \
    && nb_schema_v3_file_valid "$stage/state/state.json" \
    || { rm -rf -- "$stage"; die '备份不是 NoBrand schema v3，拒绝导入旧 state'; }
  ssh_tunnel_restore_preflight "$stage/state/ssh-tunnel/state.json" \
    || { rm -rf -- "$stage"; die 'SSH Tunnel restore identity conflict，拒绝覆盖系统用户'; }
  if [ -s "$stage/state/forward/state.json" ]; then
    forward_state_valid "$stage/state/forward/state.json" \
      || { rm -rf -- "$stage"; die 'Port Forward restore state 无效'; }
  fi
  if [ -s "$stage/state/ingress.json" ]; then
    nb_ingress_state_valid "$stage/state/ingress.json" \
      || { rm -rf -- "$stage"; die 'Ingress profile restore state 无效'; }
  fi
  if [ -s "$stage/state/ingress-firewall.json" ]; then
    nb_strict_firewall_state_valid "$stage/state/ingress-firewall.json" \
      || { rm -rf -- "$stage"; die 'Strict-ingress firewall restore state 无效'; }
  fi
  find "$stage/state" "$stage/config" -type f -name '*.json' -print0 2>/dev/null \
    | while IFS= read -r -d '' file; do jq empty "$file" >/dev/null || exit 1; done \
    || { rm -rf -- "$stage"; die '备份中存在无效 JSON'; }
  [ -e "$safe_state" ] || [ -L "$safe_state" ] || state_root_created=1
  [ -e "$safe_config" ] || [ -L "$safe_config" ] || config_root_created=1
  if [ "$state_root_created" -eq 1 ] && [ "$config_root_created" -eq 1 ]; then
    fresh_manager_restore=1
    nobrand_fresh_restore_runtime_preflight "$stage/state" \
      || { rm -rf -- "$stage"; die 'manager-only restore runtime/system identity conflict'; }
  fi
  # A manager-only fresh install intentionally has no protocol state/config
  # roots yet.  Restore must be able to materialize those two exact NoBrand
  # namespaces, while still rejecting symlinks, non-directories, or insecure
  # pre-existing roots before any destructive replacement begins.
  for restore_root in "$safe_state" "$safe_config"; do
    if [ -e "$restore_root" ] || [ -L "$restore_root" ]; then
      [ -d "$restore_root" ] && [ ! -L "$restore_root" ] \
        || {
          [ "$state_root_created" -eq 0 ] || rmdir "$safe_state" 2>/dev/null || true
          [ "$config_root_created" -eq 0 ] || rmdir "$safe_config" 2>/dev/null || true
          rm -rf -- "$stage"
          die "恢复根路径不是安全目录: $restore_root"
        }
    else
      mkdir -p "$restore_root" \
        || {
          [ "$state_root_created" -eq 0 ] || rmdir "$safe_state" 2>/dev/null || true
          [ "$config_root_created" -eq 0 ] || rmdir "$safe_config" 2>/dev/null || true
          rm -rf -- "$stage"
          die "无法创建恢复根路径: $restore_root"
        }
    fi
    chmod 0700 "$restore_root" \
      && chown root:root "$restore_root" 2>/dev/null \
      || {
        [ "$state_root_created" -eq 0 ] || rmdir "$safe_state" 2>/dev/null || true
        [ "$config_root_created" -eq 0 ] || rmdir "$safe_config" 2>/dev/null || true
        rm -rf -- "$stage"
        die "无法保护恢复根路径: $restore_root"
      }
    secure_stat_path "$restore_root" dir \
      || {
        [ "$state_root_created" -eq 0 ] || rmdir "$safe_state" 2>/dev/null || true
        [ "$config_root_created" -eq 0 ] || rmdir "$safe_config" 2>/dev/null || true
        rm -rf -- "$stage"
        die "恢复根路径权限不安全: $restore_root"
      }
  done
  snapshot="$(mktemp_dir)" || {
    [ "$state_root_created" -eq 0 ] || rmdir "$safe_state" 2>/dev/null || true
    [ "$config_root_created" -eq 0 ] || rmdir "$safe_config" 2>/dev/null || true
    rm -rf -- "$stage"
    return 1
  }
  mkdir -p "$snapshot/state" "$snapshot/config" "$snapshot/ssh-external" "$snapshot/tuic-external" "$snapshot/forward-external"
  cp -a "$safe_state/." "$snapshot/state/" 2>/dev/null || true
  cp -a "$safe_config/." "$snapshot/config/" 2>/dev/null || true
  ssh_tunnel_snapshot_external_state "$snapshot/ssh-external" \
    || {
      [ "$state_root_created" -eq 0 ] || rmdir "$safe_state" 2>/dev/null || true
      [ "$config_root_created" -eq 0 ] || rmdir "$safe_config" 2>/dev/null || true
      rm -rf -- "$stage" "$snapshot"
      return 1
    }
  tuic_snapshot_restore_side_effects "$snapshot/tuic-external" \
    || {
      [ "$state_root_created" -eq 0 ] || rmdir "$safe_state" 2>/dev/null || true
      [ "$config_root_created" -eq 0 ] || rmdir "$safe_config" 2>/dev/null || true
      rm -rf -- "$stage" "$snapshot"
      return 1
    }
  forward_snapshot_restore_side_effects "$snapshot/forward-external" \
    || {
      [ "$state_root_created" -eq 0 ] || rmdir "$safe_state" 2>/dev/null || true
      [ "$config_root_created" -eq 0 ] || rmdir "$safe_config" 2>/dev/null || true
      rm -rf -- "$stage" "$snapshot"
      return 1
    }
  ssh_restore_log="$snapshot/ssh-external/created.log"
  nobrand_stop_all_services 2>/dev/null || true
  if ! find "$safe_state" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + \
     || ! find "$safe_config" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + \
     || ! cp -a "$stage/state/." "$safe_state/" \
     || ! cp -a "$stage/config/." "$safe_config/"; then
    find "$safe_state" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + 2>/dev/null || true
    find "$safe_config" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + 2>/dev/null || true
    cp -a "$snapshot/state/." "$safe_state/" 2>/dev/null || true
    cp -a "$snapshot/config/." "$safe_config/" 2>/dev/null || true
    if [ "$state_root_created" -eq 1 ]; then rmdir "$safe_state" 2>/dev/null || true; fi
    if [ "$config_root_created" -eq 1 ]; then rmdir "$safe_config" 2>/dev/null || true; fi
    if [ "$state_root_created" -eq 0 ] && [ "$config_root_created" -eq 0 ]; then
      nb_init_state_layout 2>/dev/null || true
      nobrand_start_enabled_services 2>/dev/null || true
    fi
    rm -rf -- "$stage" "$snapshot"
    die '恢复失败，已回滚原 NoBrand state/config'
  fi
  nb_init_state_layout
  if ! nobrand_restore_protocol_runtimes \
     || ! ssh_tunnel_restore_system_state "$ssh_restore_log" \
     || ! nobrand_start_enabled_services; then
    ssh_tunnel_cancel_pending_watchdog 2>/dev/null || true
    if [ "$fresh_manager_restore" -eq 1 ]; then
      nobrand_remove_fresh_restore_protocol_resources 2>/dev/null \
        || warn 'Fresh-manager protocol runtime rollback could not remove every owned resource'
    fi
    tuic_remove_restore_attempt_resources 2>/dev/null || true
    forward_remove_restore_attempt_resources 2>/dev/null || true
    # Restore target-side effects while restored ownership metadata still
    # exists.  Clearing state first can make identity-safe cleanup fail-fast.
    tuic_restore_side_effect_snapshot "$snapshot/tuic-external" 2>/dev/null \
      || warn 'TUIC restore rollback could not restore every external side effect'
    forward_restore_side_effect_snapshot "$snapshot/forward-external" 2>/dev/null \
      || warn 'Forward restore rollback could not restore every external side effect'
    ssh_tunnel_restore_external_snapshot "$snapshot/ssh-external" "$ssh_restore_log" 2>/dev/null \
      || warn 'SSH restore rollback could not restore every external side effect'
    if [ "$fresh_manager_restore" -eq 1 ]; then
      rmdir "$NOBRAND_SNELL_RUNTIME_DIR" "$NOBRAND_BIN_DIR" "$NOBRAND_LIB_DIR" 2>/dev/null \
        || true
    fi
    find "$safe_state" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + 2>/dev/null || true
    find "$safe_config" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + 2>/dev/null || true
    cp -a "$snapshot/state/." "$safe_state/" 2>/dev/null || true
    cp -a "$snapshot/config/." "$safe_config/" 2>/dev/null || true
    if [ "$state_root_created" -eq 1 ]; then rmdir "$safe_state" 2>/dev/null || true; fi
    if [ "$config_root_created" -eq 1 ]; then rmdir "$safe_config" 2>/dev/null || true; fi
    if [ "$state_root_created" -eq 0 ] && [ "$config_root_created" -eq 0 ]; then
      nb_init_state_layout 2>/dev/null || true
      nobrand_start_enabled_services 2>/dev/null || true
    fi
    rm -rf -- "$stage" "$snapshot"
    die 'NoBrand restore service/policy acceptance 失败，state/config 已回滚'
  fi
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

nobrand_uninstall() {
  local id port safe_state safe_config safe_lib pairs="" snell_pairs failed=0 had_mieru=0 saved_yes
  require_root
  ensure_manager_state_layout 0
  nb_schema_v3_file_valid || die '未检测到有效的 NoBrand schema v3 state，拒绝卸载未知资源'
  if [ "${YES:-0}" -ne 1 ]; then
    confirm '确认完整卸载 NoBrand 3 管理的 Mieru/Snell/HY2/TUIC/VLESS REALITY/VLESS Sudoku/SSH Tunnel/Forward/Common？[y/N]: ' \
      'Completely uninstall NoBrand-3-managed Mieru/Snell/HY2/TUIC/VLESS REALITY/VLESS Sudoku/SSH Tunnel/Forward/Common resources? [y/N]: ' \
      n \
      || { t '已取消' 'Cancelled'; return 0; }
  fi
  safe_state="$(nb_assert_safe_nobrand_root "$NOBRAND_STATE_DIR" NOBRAND_STATE_DIR)" || return 1
  safe_config="$(nb_assert_safe_nobrand_root "$NOBRAND_CONFIG_DIR" NOBRAND_CONFIG_DIR)" || return 1
  safe_lib="$(nb_assert_safe_nobrand_root "$NOBRAND_LIB_DIR" NOBRAND_LIB_DIR)" || return 1
  mita_uninstall_target_present && had_mieru=1
  # Remove the externally shared sshd policy first. With the real watchdog this
  # is a two-phase operation: no other protocol is touched until a brand-new
  # administrator SSH session confirms that system access still works.
  if ssh_tunnel_state_exists; then
    ssh_tunnel_uninstall unified-uninstall || return 1
    if ssh_tunnel_state_exists \
       && [ "$(ssh_tunnel_state_field pending_operation 2>/dev/null || true)" = unified-uninstall ]; then
      t '统一卸载等待全新管理员 SSH connection 确认；确认前其它协议保持不变' \
        'Unified uninstall is waiting for a brand-new administrator SSH connection; other protocols remain unchanged until confirmation'
      return 0
    fi
  fi
  admin_lock_acquire || return 1
  if [ -s "$NOBRAND_FORWARD_STATE_FILE" ] || [ -s "$NOBRAND_REALM_RUNTIME_META" ] \
     || [ -e "$NOBRAND_REALM_SYSTEMD_SERVICE" ] || [ -e "$NOBRAND_REALM_OPENRC_SERVICE" ]; then
    forward_uninstall || failed=1
  elif command -v nft >/dev/null 2>&1 \
       && nft list table "$NOBRAND_FORWARD_NFT_FAMILY" "$NOBRAND_FORWARD_NFT_TABLE" >/dev/null 2>&1; then
    forward_remove_owned_nft_table || failed=1
  fi
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
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    port="$(reality_state_field "$id" listen_port 2>/dev/null || true)"
    reality_remove_service "$id" || failed=1
    [ -z "$port" ] || nb_firewall_close_pairs "TCP|${port}" || failed=1
  done < <(reality_instance_ids)
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    port="$(tuic_state_field "$id" listen_port 2>/dev/null || true)"
    tuic_remove_service "$id" || failed=1
    [ -z "$port" ] || nb_firewall_close_pairs "UDP|${port}" || failed=1
  done < <(tuic_instance_ids)
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
  case "$NOBRAND_TUIC_SYSTEMD_TEMPLATE" in
    /etc/systemd/system/nobrand-tuic@.service) rm -f "$NOBRAND_TUIC_SYSTEMD_TEMPLATE" ;;
  esac
  reality_remove_service_runtime_if_owned || failed=1
  [ "$(nb_service_manager)" != systemd ] || systemctl daemon-reload 2>/dev/null || true
  admin_lock_release

  if [ "$had_mieru" -eq 1 ]; then
    saved_yes="$YES"
    YES=1
    do_uninstall || { YES="$saved_yes"; return 1; }
    YES="$saved_yes"
  fi
  nb_strict_firewall_clear_all || return 1
  rm -f "$NOBRAND_INGRESS_FIREWALL_STATE_FILE" "$NOBRAND_INGRESS_FIREWALL_RULESET"

  # State/config/lib roots are exact, validated NoBrand roots. Command removal
  # deliberately happens only after every protocol/resource cleanup succeeds.
  find "$safe_state" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
  find "$safe_config" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
  find "$safe_lib" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
  rmdir "$safe_state" "$safe_config" "$safe_lib" 2>/dev/null || true
  nobrand_remove_owned_command "$NOBRAND_SHORT_COMMAND_PATH" || failed=1
  nobrand_remove_owned_command "$NOBRAND_COMMAND_PATH" || failed=1
  nobrand_remove_owned_command "$NOBRAND_INSTALL_SCRIPT_PATH" || failed=1
  [ "$failed" -eq 0 ] || return 1
  t 'NoBrand 3 的 Mieru/Snell/HY2/TUIC/VLESS REALITY/VLESS Sudoku/SSH Tunnel/Forward/Common 资源与 nobrand/nb 已完整删除；外部资源未触碰' \
    'NoBrand 3 Mieru/Snell/HY2/TUIC/VLESS REALITY/VLESS Sudoku/SSH Tunnel/Forward/Common resources and nobrand/nb were removed; external resources were untouched'
}

nobrand_stop_all_services() {
  local id
  users_state_exists && isolated_stop_all >/dev/null 2>&1 || true
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    snell_service_action "$id" stop >/dev/null 2>&1 || true
  done < <(snell_instance_ids)
  hysteria2_state_exists && nobrand_hy2_service_action stop >/dev/null 2>&1 || true
  vless_sudoku_state_exists \
    && nobrand_vless_sudoku_service_action stop >/dev/null 2>&1 || true
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    reality_service_action "$id" stop >/dev/null 2>&1 || true
  done < <(reality_instance_ids)
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    tuic_service_action "$id" stop >/dev/null 2>&1 || true
  done < <(tuic_instance_ids)
  forward_realm_service_action stop >/dev/null 2>&1 || true
}

nobrand_start_enabled_services() {
  local id enabled port pairs failed=0
  nb_strict_firewall_restore_authoritative >/dev/null 2>&1 || failed=1
  if users_state_exists && [ "$(users_count)" -gt 0 ]; then
    if load_install_state \
       && reconcile_isolated_instances >/dev/null 2>&1 \
       && apply_tc_limits >/dev/null 2>&1; then
      pairs="$(multi_user_port_protocol_pairs 2>/dev/null || true)"
      [ -z "$pairs" ] || open_firewall_for_pairs "$pairs" >/dev/null 2>&1 || failed=1
    else
      failed=1
    fi
  fi
  tuic_restore_runtime >/dev/null 2>&1 || {
    [ -z "$(tuic_instance_ids)" ] || failed=1
  }
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
      && hysteria2_running || failed=1
  fi
  if vless_sudoku_state_exists \
     && [ "$(vless_sudoku_state_field enabled 2>/dev/null || printf false)" = true ]; then
    port="$(vless_sudoku_state_field listen_port)"
    nobrand_vless_sudoku_service_action start >/dev/null 2>&1 \
      && vless_sudoku_running || failed=1
  fi
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    enabled="$(reality_state_field "$id" enabled 2>/dev/null || printf false)"
    [ "$enabled" = true ] || continue
    port="$(reality_state_field "$id" listen_port)"
    reality_install_service_runtime >/dev/null 2>&1 \
      && reality_ensure_openrc_service "$id" >/dev/null 2>&1 \
      && reality_config_matches_state "$id" \
      && nobrand_xray_test_config "$(reality_config_file "$id")" \
      && nb_firewall_open_pairs "TCP|${port}" >/dev/null 2>&1 \
      && reality_service_action "$id" start >/dev/null 2>&1 \
      && reality_running "$id" || failed=1
  done < <(reality_instance_ids)
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    enabled="$(tuic_state_field "$id" enabled 2>/dev/null || printf false)"
    [ "$enabled" = true ] || continue
    port="$(tuic_state_field "$id" listen_port)"
    tuic_install_service_runtime >/dev/null 2>&1 \
      && tuic_ensure_openrc_service "$id" >/dev/null 2>&1 \
      && tuic_validate_config "$(tuic_config_file "$id")" \
      && nb_firewall_open_pairs "UDP|${port}" >/dev/null 2>&1 \
      && tuic_service_action "$id" start >/dev/null 2>&1 \
      && tuic_running "$id" || failed=1
  done < <(tuic_instance_ids)
  if [ -s "$NOBRAND_FORWARD_STATE_FILE" ]; then
    forward_realm_restore_runtime >/dev/null 2>&1 \
      && forward_apply_nft_state "$NOBRAND_FORWARD_STATE_FILE" >/dev/null 2>&1 \
      && forward_realm_apply_state "$NOBRAND_FORWARD_STATE_FILE" >/dev/null 2>&1 || failed=1
  fi
  return "$failed"
}
