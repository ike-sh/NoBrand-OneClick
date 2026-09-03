#!/usr/bin/env bash
# Debian/Ubuntu、RHEL 系与 Alpine 的无 init 平台矩阵。
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && { pwd -W 2>/dev/null || pwd; })"

run_case() {
  local image="$1" setup="$2"
  echo "==> ${image}"
  docker run --rm -v "$ROOT:/work:ro" "$image" sh -ec \
    "${setup}; bash /work/scripts/platform-case.sh"
}

run_case debian:bookworm-slim \
  'apt-get update -qq >/dev/null && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq bash git python3 iproute2 jq openssl openssh-server openssh-client passwd procps >/dev/null'
run_case ubuntu:24.04 \
  'apt-get update -qq >/dev/null && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq bash git python3 iproute2 jq openssl openssh-server openssh-client passwd procps >/dev/null'
run_case rockylinux:9 \
  'dnf install -y -q bash diffutils git python3 iproute jq openssl openssh-server openssh-clients shadow-utils procps-ng >/dev/null'
run_case alpine:3.20 \
  'apk add --no-cache bash git python3 iproute2 jq openssl openssh-server openssh-keygen shadow procps-ng >/dev/null'

echo 'platform-smoke: PASS'
