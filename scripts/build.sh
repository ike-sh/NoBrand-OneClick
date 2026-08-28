#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
ROOT_ARTIFACT="${ROOT}/install-nobrand.sh"
DIST_DIR="${ROOT}/dist"
DIST_ARTIFACT="${DIST_DIR}/install-nobrand.sh"

# The order is part of the release format. Do not replace this manifest with a glob.
MODULES=(
  src/00-bootstrap.sh
  src/05-constants.sh
  src/10-cli-prelude.sh
  src/15-core-state.sh
  src/16-core-port.sh
  src/17-core-endpoint.sh
  src/18-core-nodes.sh
  src/20-platform-mieru.sh
  src/21-platform-xray-hy2.sh
  src/22-platform-snell.sh
  src/23-platform-vless-sudoku.sh
  src/25-network-mtu.sh
  src/30-users-instance.sh
  src/35-users-state.sh
  src/40-tc-quota.sh
  src/45-backup-user-actions.sh
  src/50-diagnostics.sh
  src/52-user-actions-ui.sh
  src/55-profile-config.sh
  src/56-snell.sh
  src/57-hysteria2.sh
  src/58-vless-sudoku.sh
  src/60-daemon-firewall-network.sh
  src/65-service-bbr.sh
  src/70-client-export-install.sh
  src/71-snell-export.sh
  src/80-lifecycle.sh
  src/85-status-actions.sh
  src/90-ui.sh
  src/99-main.sh
)

MODE="write"
case "${1:-}" in
  "") ;;
  --check) MODE="check" ;;
  *)
    printf 'usage: %s [--check]\n' "$0" >&2
    exit 2
    ;;
esac
[ "$#" -le 1 ] || {
  printf 'usage: %s [--check]\n' "$0" >&2
  exit 2
}

# Every src/*.sh file is release source and must appear exactly once in the
# ordered manifest. This keeps an accidentally added-but-unbuilt module from
# producing a superficially successful, incomplete installer.
for module in "${MODULES[@]}"; do
  occurrences=0
  for candidate in "${MODULES[@]}"; do
    [ "$candidate" != "$module" ] || occurrences=$((occurrences + 1))
  done
  [ "$occurrences" -eq 1 ] || {
    printf 'build: duplicate module in manifest: %s\n' "$module" >&2
    exit 1
  }
done
for path in "${ROOT}"/src/*.sh; do
  [ -f "$path" ] || continue
  source_module="src/${path##*/}"
  listed=0
  for module in "${MODULES[@]}"; do
    [ "$module" != "$source_module" ] || listed=1
  done
  [ "$listed" -eq 1 ] || {
    printf 'build: source module missing from manifest: %s\n' "$source_module" >&2
    exit 1
  }
done

for module in "${MODULES[@]}"; do
  path="${ROOT}/${module}"
  [ -f "$path" ] && [ -r "$path" ] || {
    printf 'build: missing module: %s\n' "$module" >&2
    exit 1
  }
  first_line=""
  IFS= read -r first_line <"$path" || true
  if [[ "$first_line" == '#!'* ]]; then
    printf 'build: module must not contain a shebang: %s\n' "$module" >&2
    exit 1
  fi
  if LC_ALL=C grep -q "$(printf '\r')" "$path"; then
    printf 'build: module contains CR bytes: %s\n' "$module" >&2
    exit 1
  fi
  last_byte_newlines="$(tail -c 1 "$path" | wc -l | tr -d '[:space:]')"
  [ "$last_byte_newlines" = 1 ] || {
    printf 'build: module must end with LF: %s\n' "$module" >&2
    exit 1
  }
done

tmp="$(mktemp "${ROOT}/.install-nobrand.build.XXXXXX")"
dist_tmp=""
cleanup() {
  [ -z "$tmp" ] || rm -f "$tmp"
  [ -z "$dist_tmp" ] || rm -f "$dist_tmp"
}
trap cleanup EXIT HUP INT TERM

{
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    '# AUTO-GENERATED FILE.' \
    '# Source files live under src/.' \
    '# Do not edit this generated file directly.' \
    '# Run scripts/build.sh after modifying src/.' \
    ''
  first_module=1
  for module in "${MODULES[@]}"; do
    if [ "$first_module" -eq 0 ]; then
      printf '\n'
    fi
    command cat "${ROOT}/${module}"
    first_module=0
  done
} >"$tmp"

command -v chmod >/dev/null 2>&1 && chmod 0644 "$tmp"
"${BASH:-bash}" -n "$tmp"

if [ "$MODE" = check ]; then
  if [ ! -f "$ROOT_ARTIFACT" ] || ! cmp -s "$tmp" "$ROOT_ARTIFACT"; then
    printf 'build: root install-nobrand.sh is stale; run scripts/build.sh\n' >&2
    exit 1
  fi
  if [ ! -f "$DIST_ARTIFACT" ] || ! cmp -s "$tmp" "$DIST_ARTIFACT"; then
    printf 'build: dist/install-nobrand.sh is stale; run scripts/build.sh\n' >&2
    exit 1
  fi
  printf 'build: generated artifacts are current\n'
  exit 0
fi

mkdir -p "$DIST_DIR"
dist_tmp="$(mktemp "${DIST_DIR}/.install-nobrand.build.XXXXXX")"
command cp "$tmp" "$dist_tmp"
command -v chmod >/dev/null 2>&1 && chmod 0644 "$dist_tmp"
mv -f "$dist_tmp" "$DIST_ARTIFACT"
dist_tmp=""
mv -f "$tmp" "$ROOT_ARTIFACT"
tmp=""

cmp -s "$ROOT_ARTIFACT" "$DIST_ARTIFACT"
printf 'build: wrote %s and %s\n' "$ROOT_ARTIFACT" "$DIST_ARTIFACT"
