install_self_script() {
  STAGE="安装管理脚本"
  local tmp src_real="" dest_real="" installed=0
  tmp="$(mktemp_file .sh)"
  # An unpublished development build must install the exact local artifact
  # that is being executed. Released builds may fall back only to the latest
  # GitHub Release asset; raw main is deliberately not an installation source.
  if [ -n "${BASH_SOURCE[0]:-}" ] && [ -r "${BASH_SOURCE[0]}" ] \
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
  elif [ -r "$INSTALL_SCRIPT_PATH" ] \
       && grep -qxF "SCRIPT_VERSION=\"${SCRIPT_VERSION}\"" "$INSTALL_SCRIPT_PATH" 2>/dev/null; then
    run chmod 0755 "$INSTALL_SCRIPT_PATH"
    installed=1
  elif curl -fsSL --connect-timeout 15 --max-time 60 "$NOBRAND_RELEASE_INSTALLER_URL" -o "$tmp" 2>/dev/null \
       && grep -qxF "SCRIPT_VERSION=\"${SCRIPT_VERSION}\"" "$tmp"; then
    run install -m 0755 "$tmp" "$INSTALL_SCRIPT_PATH"
    installed=1
  fi
  rm -f "$tmp"
  [ "$installed" -eq 1 ] || die "$(t '无法取得与当前版本一致的管理脚本，拒绝用其它版本覆盖' \
    'Could not obtain the exact current manager version; refusing to overwrite with another version')"
  nobrand_install_manager_script
}

ensure_management_scripts() {
  STAGE="更新管理脚本"
  install_self_script
  repair_mita_binary_paths
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
  if is_mita_elf_binary "$MITA_PACKAGE_BIN"; then
    refresh_managed_mita_runtime
    return $?
  fi
  reinstall_mita_package && refresh_managed_mita_runtime
}

refresh_managed_mita_runtime() {
  local package_bin="${1:-$MITA_PACKAGE_BIN}"
  is_mita_elf_binary "$package_bin" || return 1
  run install -d -o root -g root -m 0755 "$NOBRAND_LIB_DIR" "$NOBRAND_BIN_DIR"
  run install -m 0755 "$package_bin" "$MITA_BIN"
  is_mita_elf_binary "$MITA_BIN"
}

repair_mita_binary_paths() {
  STAGE="修复 mita 二进制路径"
  if ! is_mita_elf_binary "$MITA_BIN"; then
    if is_mita_elf_binary "$MITA_PACKAGE_BIN"; then
      refresh_managed_mita_runtime || return 1
    elif command -v dpkg >/dev/null 2>&1; then
      recover_deb_mita || warn "$(t 'mita 二进制自动修复未成功，请重新运行脚本并选择「升级」重新安装' \
        'auto-repair failed; re-run the script and choose Upgrade to reinstall')"
    else
      reinstall_mita_package && refresh_managed_mita_runtime || warn "$(t \
        'mita 二进制不可用，请执行 nobrand mieru upgrade 重新安装' \
        'mita binary unavailable; run nobrand mieru upgrade to reinstall')"
    fi
  fi
  is_mita_elf_binary "$MITA_BIN"
  hash -r 2>/dev/null || true
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

is_mita_elf_binary() {
  [ -f "$1" ] || return 1
  [ "$(head -c 4 "$1" 2>/dev/null || true)" = $'\x7fELF' ]
}

mita_real_bin() {
  printf '%s' "$MITA_BIN"
}

mita_bin() {
  printf '%s' "$MITA_BIN"
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
  run apk add --no-cache bash curl tar ca-certificates jq iptables iproute2 python3 procps-ng util-linux
  if [ "$(service_manager)" = openrc ]; then
    run apk add --no-cache openrc 2>/dev/null || true
  fi
}

ensure_management_dependencies() {
  local pm="${1:-$(detect_pkg_manager)}"
  STAGE="安装管理依赖"
  case "$pm" in
    deb)
      command -v curl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1 \
        && command -v tar >/dev/null 2>&1 && command -v sha256sum >/dev/null 2>&1 \
        && command -v python3 >/dev/null 2>&1 && command -v tc >/dev/null 2>&1 \
        && command -v sysctl >/dev/null 2>&1 && command -v unshare >/dev/null 2>&1 \
        && command -v setpriv >/dev/null 2>&1 && return 0
      run apt-get update
      run apt-get install -y curl ca-certificates jq tar coreutils python3 iproute2 procps util-linux
      ;;
    rpm)
      command -v curl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1 \
        && command -v tar >/dev/null 2>&1 && command -v sha256sum >/dev/null 2>&1 \
        && command -v python3 >/dev/null 2>&1 && command -v tc >/dev/null 2>&1 \
        && command -v sysctl >/dev/null 2>&1 && command -v unshare >/dev/null 2>&1 \
        && command -v setpriv >/dev/null 2>&1 && return 0
      if command -v dnf >/dev/null 2>&1; then
        run dnf install -y curl ca-certificates jq tar coreutils python3 iproute procps-ng util-linux
      else
        run yum install -y curl ca-certificates jq tar coreutils python3 iproute procps-ng util-linux
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
  run install -d -o root -g root -m 0755 "$NOBRAND_LIB_DIR" "$NOBRAND_BIN_DIR"
  run install -m 0755 "$bin" "$MITA_BIN"
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
         || ! extract_mita_tarball "$path"; then
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
    deb|rpm)
      refresh_managed_mita_runtime "$MITA_PACKAGE_BIN" \
        || die "$(t '无法把官方 mita runtime 安装到 NoBrand 管理路径' \
          'Could not install the official mita runtime into the NoBrand-managed path')"
      mark_oneclick_install
      ;;
  esac
}
