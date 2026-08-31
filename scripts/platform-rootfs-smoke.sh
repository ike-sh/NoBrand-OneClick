#!/usr/bin/env bash
# Docker-daemon-free four-platform matrix using official container root filesystems.
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
[ "$(id -u)" -eq 0 ] || {
  printf '%s\n' 'platform-rootfs-smoke requires root inside an isolated mount namespace' >&2
  exit 1
}

for command_name in curl tar mount umount mountpoint chroot; do
  command -v "$command_name" >/dev/null 2>&1 \
    || { printf 'missing platform-rootfs dependency: %s\n' "$command_name" >&2; exit 1; }
done

cache="${NOBRAND_RUNTIME_CACHE:-/tmp/nobrand-runtime-cache}/platform-rootfs"
mkdir -p "$cache"
chmod 0700 "$cache"
crane="$cache/crane"
if [ ! -x "$crane" ]; then
  archive="$cache/go-containerregistry.tar.gz"
  extract_dir="$(mktemp -d)"
  curl -fL --connect-timeout 10 --max-time 300 \
    'https://github.com/google/go-containerregistry/releases/latest/download/go-containerregistry_Linux_x86_64.tar.gz' \
    -o "$archive"
  tar -tzf "$archive" | awk '$0=="crane" {found=1} END {exit found ? 0 : 1}' \
    || { rm -rf -- "$extract_dir"; printf '%s\n' 'crane release archive layout mismatch' >&2; exit 1; }
  tar --no-same-owner -xzf "$archive" -C "$extract_dir" crane
  install -m 0755 "$extract_dir/crane" "$crane"
  rm -rf -- "$extract_dir"
fi
"$crane" version >/dev/null

matrix_root="$(mktemp -d)"
cleanup_all() {
  rm -rf -- "$matrix_root"
}
trap cleanup_all EXIT

cleanup_rootfs_mounts() {
  local rootfs="$1" target
  for target in work sys dev proc; do
    mountpoint -q "$rootfs/$target" && umount -l "$rootfs/$target" || true
  done
}

run_case() {
  local name="$1" image="$2" setup="$3" image_tar rootfs rc=0
  image_tar="$cache/${name}.tar"
  if [ ! -s "$image_tar" ]; then
    "$crane" export "$image" "$image_tar"
  fi
  tar -tf "$image_tar" | awk '
    /^\// || /(^|\/)\.\.($|\/)/ {bad=1}
    END {exit bad ? 1 : 0}
  ' || { printf 'unsafe path in platform image: %s\n' "$image" >&2; return 1; }
  rootfs="$matrix_root/$name"
  mkdir -p "$rootfs"
  tar --numeric-owner -xpf "$image_tar" -C "$rootfs"
  mkdir -p "$rootfs/work" "$rootfs/proc" "$rootfs/dev" "$rootfs/sys" "$rootfs/tmp"
  chmod 1777 "$rootfs/tmp"
  rm -f "$rootfs/etc/resolv.conf"
  cp -L /etc/resolv.conf "$rootfs/etc/resolv.conf"
  mount -t proc proc "$rootfs/proc"
  mount --rbind /dev "$rootfs/dev"
  mount --make-rslave "$rootfs/dev"
  mount --rbind /sys "$rootfs/sys"
  mount --make-rslave "$rootfs/sys"
  mount --bind "$ROOT" "$rootfs/work"
  mount -o remount,bind,ro "$rootfs/work"
  printf '==> %s (%s)\n' "$name" "$image"
  chroot "$rootfs" /bin/sh -ec "$setup; bash /work/scripts/platform-case.sh" || rc=$?
  cleanup_rootfs_mounts "$rootfs"
  [ "$rc" -eq 0 ] || return "$rc"
}

run_case debian docker.io/library/debian:bookworm-slim \
  'apt-get update -qq >/dev/null && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq bash python3 iproute2 jq openssl openssh-server openssh-client passwd procps >/dev/null'
run_case ubuntu docker.io/library/ubuntu:24.04 \
  'apt-get update -qq >/dev/null && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq bash python3 iproute2 jq openssl openssh-server openssh-client passwd procps >/dev/null'
run_case rocky docker.io/library/rockylinux:9 \
  'dnf install -y -q bash python3 iproute jq openssl openssh-server openssh-clients shadow-utils procps-ng >/dev/null'
run_case alpine docker.io/library/alpine:3.20 \
  'apk add --no-cache bash python3 iproute2 jq openssl openssh-server openssh-keygen shadow procps-ng >/dev/null'

printf '%s\n' 'platform-rootfs-smoke: PASS (Debian/Ubuntu/Rocky/Alpine)'
