# Native architecture: ordinary protocols use src/19-splicore.sh.

service_manager() {
  if [ -d /run/systemd/system ] && command -v systemctl >/dev/null 2>&1; then
    echo systemd
  elif command -v rc-service >/dev/null 2>&1; then
    echo openrc
  else
    echo none
  fi
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
        && command -v setpriv >/dev/null 2>&1 && command -v flock >/dev/null 2>&1 \
        && return 0
      run apt-get update
      run apt-get install -y curl ca-certificates jq tar coreutils python3 iproute2 procps util-linux
      ;;
    rpm)
      command -v curl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1 \
        && command -v tar >/dev/null 2>&1 && command -v sha256sum >/dev/null 2>&1 \
        && command -v python3 >/dev/null 2>&1 && command -v tc >/dev/null 2>&1 \
        && command -v sysctl >/dev/null 2>&1 && command -v unshare >/dev/null 2>&1 \
        && command -v setpriv >/dev/null 2>&1 && command -v flock >/dev/null 2>&1 \
        && return 0
      if command -v dnf >/dev/null 2>&1; then
        run dnf install -y curl ca-certificates jq tar coreutils python3 iproute procps-ng util-linux
      else
        run yum install -y curl ca-certificates jq tar coreutils python3 iproute procps-ng util-linux
      fi
      ;;
    alpine)
      command -v curl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1 \
        && command -v tar >/dev/null 2>&1 && command -v sha256sum >/dev/null 2>&1 \
        && command -v python3 >/dev/null 2>&1 && command -v tc >/dev/null 2>&1 \
        && command -v sysctl >/dev/null 2>&1 && command -v unshare >/dev/null 2>&1 \
        && command -v setpriv >/dev/null 2>&1 && command -v flock >/dev/null 2>&1 \
        && return 0
      install_alpine_deps
      ;;
  esac
}
