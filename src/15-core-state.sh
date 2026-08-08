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
