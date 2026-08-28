# ---------- Surge official Snell runtime resolver / download / service ----------

snell_arch_asset_name() {
  case "${NOBRAND_TEST_ARCH:-$(uname -m)}" in
    x86_64|amd64) printf 'amd64' ;;
    aarch64|arm64) printf 'aarch64' ;;
    *) return 1 ;;
  esac
}

snell_platform_supported() {
  local major="$1" arch
  case "$major" in 4|5) ;; *) return 1 ;; esac
  arch="$(snell_arch_asset_name)" || return 1
  case "$arch" in amd64|aarch64) return 0 ;; esac
}

# 从 Surge 官方 Markdown 中解析对应 major/arch 的最新 asset。排序支持
# beta -> RC -> GA，避免将 runtime 版本写死在产品源码中。
snell_select_release_from_text() {
  local major="$1" arch="$2" input rc
  case "$major" in 4|5) ;; *) return 1 ;; esac
  input="$(mktemp_file .md)" || return 1
  cat >"$input" || { rm -f "$input"; return 1; }
  python3 - "$major" "$arch" "$input" <<'PY'
import re
import sys

major=int(sys.argv[1])
arch=sys.argv[2]
with open(sys.argv[3], encoding="utf-8") as source:
    text=source.read()
pattern=re.compile(r"https://dl\.nssurge\.com/snell/snell-server-v([^/\s]+)-linux-([A-Za-z0-9_]+)\.zip")

def key(version):
    match=re.fullmatch(r"(\d+(?:\.\d+)*)(.*)", version, re.I)
    if not match:
        return ((0,), 0, 0, version.lower())
    numbers=tuple(int(part) for part in match.group(1).split('.'))
    suffix=match.group(2).lower()
    if not suffix:
        stage, stage_no = 4, 0
    elif suffix.startswith('rc'):
        stage=3
        found=re.search(r"\d+", suffix)
        stage_no=int(found.group()) if found else 1
    elif suffix.startswith('beta') or suffix.startswith('b'):
        stage=2
        found=re.search(r"\d+", suffix)
        stage_no=int(found.group()) if found else 1
    elif suffix.startswith('alpha') or suffix.startswith('a'):
        stage=1
        found=re.search(r"\d+", suffix)
        stage_no=int(found.group()) if found else 1
    else:
        stage, stage_no = 0, 0
    return (numbers, stage, stage_no, suffix)

candidates=[]
for match in pattern.finditer(text):
    version, asset_arch = match.groups()
    if asset_arch != arch:
        continue
    if not re.match(r"^%d(?:\.|$)" % major, version):
        continue
    url="https://dl.nssurge.com/snell/snell-server-v%s-linux-%s.zip" % (version, arch)
    line_start=text.rfind("\n", 0, match.start()) + 1
    line_end=text.find("\n", match.end())
    if line_end < 0:
        line_end=len(text)
    same_line=text[line_start:line_end]
    digest_match=re.search(r"(?i)(?<![0-9a-f])[0-9a-f]{64}(?![0-9a-f])", same_line)
    digest=digest_match.group(0).lower() if digest_match else ""
    candidates.append((key(version), version, url, digest))
if not candidates:
    raise SystemExit(1)
_, version, url, digest=max(candidates)
suffix=re.fullmatch(r"\d+(?:\.\d+)*(.*)", version, re.I).group(1).lower()
if not suffix:
    status="Stable"
elif suffix.startswith("rc"):
    status="RC"
elif suffix.startswith("beta") or suffix.startswith("b"):
    status="Beta"
else:
    status="Experimental"
fields=[version, url, status]
if digest:
    fields.append(digest)
print("\t".join(fields))
PY
  rc=$?
  rm -f "$input"
  return "$rc"
}

snell_resolve_release() {
  local major="$1" arch page
  case "$major" in 4|5) ;; *) return 1 ;; esac
  arch="$(snell_arch_asset_name)" || return 1
  page="$(mktemp_file .md)" || return 1
  if ! curl -fsSL --connect-timeout 15 --max-time 90 \
      --retry 3 --retry-delay 2 --retry-all-errors \
      -H 'User-Agent: NoBrand-OneClick' "$SNELL_RELEASE_PAGE" -o "$page"; then
    rm -f "$page"
    return 1
  fi
  snell_select_release_from_text "$major" "$arch" <"$page"
  local rc=$?
  rm -f "$page"
  return "$rc"
}

snell_runtime_path() {
  case "$1" in 4|5) ;; *) return 1 ;; esac
  printf '%s/snell-v%s' "$NOBRAND_SNELL_RUNTIME_DIR" "$1"
}

snell_runtime_metadata_path() {
  case "$1" in 4|5) ;; *) return 1 ;; esac
  printf '%s/snell-v%s.runtime.json' "$NOBRAND_SNELL_RUNTIME_DIR" "$1"
}

snell_runtime_reported_version() {
  local binary="$1"
  [ -x "$binary" ] || return 1
  "$binary" --version 2>&1 \
    | sed -nE 's/.*snell-server[[:space:]]+v([^[:space:]]+).*/\1/p' | head -n1
}

snell_runtime_release_version() {
  local major="$1" metadata
  metadata="$(snell_runtime_metadata_path "$major")"
  if [ -s "$metadata" ] && jq -e '.release_version|type=="string" and length>0' "$metadata" >/dev/null 2>&1; then
    jq -r .release_version "$metadata"
  else
    snell_runtime_reported_version "$(snell_runtime_path "$major")"
  fi
}

snell_runtime_release_status() {
  local major="$1" metadata
  metadata="$(snell_runtime_metadata_path "$major")"
  if [ -s "$metadata" ] && jq -e '.status|type=="string" and length>0' "$metadata" >/dev/null 2>&1; then
    jq -r .status "$metadata"
  else
    printf Stable
  fi
}

snell_generate_server_config() {
  local output="$1" major="$2" listen_host="$3" listen_port="$4" psk="$5"
  case "$major" in
    4|5)
      cat >"$output" <<EOF
[snell-server]
listen = ${listen_host}:${listen_port}
psk = ${psk}
ipv6 = false
EOF
      ;;
    *) return 1 ;;
  esac
}

snell_validate_runtime_config() {
  local binary="$1" major="$2" psk="$3" port config log pid ready=0
  port="$(nb_select_available_port TCP)" || return 1
  config="$(mktemp_file .conf)" || return 1
  log="$(mktemp_file .log)" || { rm -f "$config"; return 1; }
  snell_generate_server_config "$config" "$major" 127.0.0.1 "$port" "$psk" \
    || { rm -f "$config" "$log"; return 1; }
  "$binary" -c "$config" >"$log" 2>&1 &
  pid=$!
  local i=0
  while [ "$i" -lt 10 ]; do
    if nb_port_is_listening TCP "$port"; then ready=1; break; fi
    kill -0 "$pid" 2>/dev/null || break
    sleep 1
    i=$((i + 1))
  done
  kill "$pid" >/dev/null 2>&1 || true
  wait "$pid" >/dev/null 2>&1 || true
  if [ "$ready" -ne 1 ]; then
    sed -E 's/(psk[[:space:]]*=[[:space:]]*).*/\1***REDACTED***/I' "$log" >&2 || true
    rm -f "$config" "$log"
    return 1
  fi
  rm -f "$config" "$log"
}

snell_download_candidate() {
  local major="$1" output="$2" release version url status upstream_sha256 temp candidate reported actual_archive_sha256
  case "$major" in 4|5) ;; *) return 1 ;; esac
  snell_platform_supported "$major" || {
    warn "Snell v${major} on this platform unsupported"
    return 1
  }
  release="$(snell_resolve_release "$major")" || return 1
  IFS=$'\t' read -r version url status upstream_sha256 <<<"$release"
  [[ "$url" = https://dl.nssurge.com/snell/snell-server-v*-linux-*.zip ]] || {
    warn "拒绝非 Surge 官方 HTTPS Snell asset: $url"
    return 1
  }
  temp="$(mktemp_dir)" || return 1
  if ! curl -fL --connect-timeout 15 --max-time 180 \
      --retry 3 --retry-delay 2 --retry-all-errors \
      -H 'User-Agent: NoBrand-OneClick' "$url" -o "$temp/snell.zip"; then
    rm -rf -- "$temp"
    return 1
  fi
  if [ -n "$upstream_sha256" ]; then
    [[ "$upstream_sha256" =~ ^[0-9a-fA-F]{64}$ ]] || { rm -rf -- "$temp"; return 1; }
    actual_archive_sha256="$(nobrand_sha256_file "$temp/snell.zip")" || { rm -rf -- "$temp"; return 1; }
    [ "$actual_archive_sha256" = "$(printf '%s' "$upstream_sha256" | tr '[:upper:]' '[:lower:]')" ] \
      || { warn "Surge Snell upstream SHA-256 mismatch"; rm -rf -- "$temp"; return 1; }
  fi
  if ! unzip -t "$temp/snell.zip" >/dev/null \
     || ! unzip -qo "$temp/snell.zip" -d "$temp/unpacked"; then
    rm -rf -- "$temp"
    return 1
  fi
  candidate="$(find "$temp/unpacked" -type f -name snell-server | head -n1)"
  [ -n "$candidate" ] && [ "$(head -c 4 "$candidate" 2>/dev/null || true)" = $'\x7fELF' ] \
    || { rm -rf -- "$temp"; return 1; }
  chmod 0755 "$candidate" || { rm -rf -- "$temp"; return 1; }
  reported="$(snell_runtime_reported_version "$candidate" 2>/dev/null || true)"
  [[ "$reported" = "$major".* ]] || { rm -rf -- "$temp"; return 1; }
  install -m 0755 "$candidate" "$output" || { rm -rf -- "$temp"; return 1; }
  SNELL_RESOLVED_VERSION="$version"
  SNELL_RESOLVED_URL="$url"
  SNELL_RESOLVED_STATUS="$status"
  SNELL_RESOLVED_SHA256="$(nobrand_sha256_file "$candidate" 2>/dev/null || true)"
  info "Surge official Snell v${version} (${status}) verified; sha256=${SNELL_RESOLVED_SHA256:-unavailable}"
  rm -rf -- "$temp"
}

snell_install_runtime() {
  local major="$1" force="${2:-0}" destination metadata candidate backup="" metadata_backup=""
  local had_old=0 had_metadata=0 test_psk metadata_tmp=""
  case "$major" in 4|5) ;; *) return 1 ;; esac
  destination="$(snell_runtime_path "$major")"
  metadata="$(snell_runtime_metadata_path "$major")"
  if [ -x "$destination" ] && [ "$force" -ne 1 ]; then
    return 0
  fi
  candidate="$(mktemp_file .snell)" || return 1
  if ! snell_download_candidate "$major" "$candidate"; then
    rm -f "$candidate"
    return 1
  fi
  test_psk="$(openssl rand -hex 16 2>/dev/null || printf '0123456789abcdef0123456789abcdef')"
  if ! snell_validate_runtime_config "$candidate" "$major" "$test_psk"; then
    rm -f "$candidate"
    warn "Snell v${major} official runtime validation failed"
    return 1
  fi
  mkdir -p "$NOBRAND_SNELL_RUNTIME_DIR" || { rm -f "$candidate"; return 1; }
  if [ -e "$destination" ]; then
    backup="$(mktemp "${destination}.rollback.XXXXXX")" || { rm -f "$candidate"; return 1; }
    rm -f "$backup"
    mv "$destination" "$backup" || { rm -f "$candidate"; return 1; }
    had_old=1
  fi
  if [ -e "$metadata" ]; then
    metadata_backup="$(mktemp "${metadata}.rollback.XXXXXX")" || {
      rm -f "$candidate"
      [ "$had_old" -eq 0 ] || mv "$backup" "$destination" 2>/dev/null || true
      return 1
    }
    cp -a "$metadata" "$metadata_backup" || {
      rm -f "$candidate" "$metadata_backup"
      [ "$had_old" -eq 0 ] || mv "$backup" "$destination" 2>/dev/null || true
      return 1
    }
    had_metadata=1
  fi
  if ! install -m 0755 "$candidate" "${destination}.new" \
     || ! mv -f "${destination}.new" "$destination" \
     || ! snell_runtime_reported_version "$destination" >/dev/null; then
    rm -f "$candidate" "${destination}.new" "$destination"
    [ "$had_old" -eq 0 ] || mv "$backup" "$destination" 2>/dev/null || true
    rm -f "$metadata_backup"
    return 1
  fi
  metadata_tmp="$(mktemp_file .json)" || true
  if [ -z "$metadata_tmp" ] \
     || ! jq -n --arg major "$major" --arg release_version "$SNELL_RESOLVED_VERSION" \
          --arg reported_version "$(snell_runtime_reported_version "$destination")" \
          --arg status "$SNELL_RESOLVED_STATUS" --arg source_url "$SNELL_RESOLVED_URL" \
          --arg sha256 "$SNELL_RESOLVED_SHA256" --arg installed_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
            {
              major:($major|tonumber), release_version:$release_version,
              reported_version:$reported_version, status:$status,
              source_url:$source_url, sha256:$sha256, installed_at:$installed_at
            }
          ' >"$metadata_tmp" \
     || ! nb_atomic_install_file "$metadata_tmp" "$metadata" 0600; then
    rm -f "$candidate" "$metadata_tmp" "$destination"
    [ "$had_old" -eq 0 ] || mv "$backup" "$destination" 2>/dev/null || true
    if [ "$had_metadata" -eq 1 ]; then
      mv -f "$metadata_backup" "$metadata" 2>/dev/null || true
    else
      rm -f "$metadata"
    fi
    return 1
  fi
  rm -f "$candidate" "$metadata_tmp" "$backup" "$metadata_backup"
}

snell_install_service_runtime() {
  local manager tmp
  manager="$(nb_service_manager)"
  mkdir -p "$(dirname "$NOBRAND_SNELL_RUNNER")" || return 1
  tmp="$(mktemp_file .runner)" || return 1
  cat >"$tmp" <<EOF
#!/usr/bin/env bash
set -euo pipefail
id="\${1:-}"
[[ "\$id" =~ ^s[0-9a-f]{16}\$ ]] || exit 64
state="${NOBRAND_SNELL_STATE_DIR}/\${id}.json"
config="${NOBRAND_SNELL_CONFIG_DIR}/\${id}.conf"
[ -r "\$state" ] && [ -r "\$config" ] || exit 66
version="\$(jq -r '.version // empty' "\$state")"
case "\$version" in 4|5) ;; *) exit 65 ;; esac
exec "${NOBRAND_SNELL_RUNTIME_DIR}/snell-v\${version}" -c "\$config"
EOF
  install -m 0755 "$tmp" "${NOBRAND_SNELL_RUNNER}.new" \
    && mv -f "${NOBRAND_SNELL_RUNNER}.new" "$NOBRAND_SNELL_RUNNER" \
    || { rm -f "$tmp" "${NOBRAND_SNELL_RUNNER}.new"; return 1; }
  rm -f "$tmp"
  case "$manager" in
    systemd)
      tmp="$(mktemp_file .service)" || return 1
      cat >"$tmp" <<EOF
# Managed by NoBrand-OneClick
[Unit]
Description=NoBrand Snell instance %i
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
ExecStart=${NOBRAND_SNELL_RUNNER} %i
Restart=on-failure
RestartSec=3
LimitNOFILE=1048576
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_BIND_SERVICE
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full
ProtectHome=true
ReadOnlyPaths=${NOBRAND_SNELL_CONFIG_DIR} ${NOBRAND_SNELL_STATE_DIR} ${NOBRAND_SNELL_RUNTIME_DIR}

[Install]
WantedBy=multi-user.target
EOF
      install -m 0644 "$tmp" "${NOBRAND_SNELL_SYSTEMD_TEMPLATE}.new" \
        && mv -f "${NOBRAND_SNELL_SYSTEMD_TEMPLATE}.new" "$NOBRAND_SNELL_SYSTEMD_TEMPLATE" \
        || { rm -f "$tmp" "${NOBRAND_SNELL_SYSTEMD_TEMPLATE}.new"; return 1; }
      rm -f "$tmp"
      systemctl daemon-reload
      ;;
    openrc) ;;
    *) return 1 ;;
  esac
}

snell_systemd_unit() { printf 'nobrand-snell@%s.service' "$1"; }
snell_openrc_service() { printf 'nobrand-snell-%s' "$1"; }

snell_ensure_openrc_service() {
  local id="$1" path tmp
  [ "$(nb_service_manager)" = openrc ] || return 0
  [[ "$id" =~ ^s[0-9a-f]{16}$ ]] || return 1
  path="${NOBRAND_SNELL_OPENRC_PREFIX}${id}"
  tmp="$(mktemp_file .openrc)" || return 1
  cat >"$tmp" <<EOF
#!/sbin/openrc-run
# Managed by NoBrand-OneClick
name="NoBrand Snell ${id}"
command="${NOBRAND_SNELL_RUNNER}"
command_args="${id}"
command_background=true
pidfile="/run/nobrand-snell-${id}.pid"
output_log="/var/log/nobrand-snell-${id}.log"
error_log="/var/log/nobrand-snell-${id}.err"
depend() { use net; after firewall; }
EOF
  install -m 0755 "$tmp" "${path}.new" && mv -f "${path}.new" "$path" \
    || { rm -f "$tmp" "${path}.new"; return 1; }
  rm -f "$tmp"
}

snell_service_action() {
  local id="$1" action="$2" manager unit service
  manager="$(nb_service_manager)"
  unit="$(snell_systemd_unit "$id")"
  service="$(snell_openrc_service "$id")"
  case "$manager" in
    systemd)
      [ "$action" != restart ] || systemctl daemon-reload
      [ "$action" != start ] && [ "$action" != restart ] \
        || systemctl enable "$unit" >/dev/null 2>&1
      systemctl "$action" "$unit"
      ;;
    openrc)
      snell_ensure_openrc_service "$id" || return 1
      [ "$action" != start ] && [ "$action" != restart ] \
        || rc-update add "$service" default >/dev/null 2>&1
      rc-service "$service" "$action"
      ;;
    *) return 1 ;;
  esac
}

snell_service_active() {
  local id="$1"
  nb_service_is_active "$(snell_systemd_unit "$id")" "$(snell_openrc_service "$id")"
}

snell_remove_service() {
  local id="$1" manager unit service
  manager="$(nb_service_manager)"
  unit="$(snell_systemd_unit "$id")"; service="$(snell_openrc_service "$id")"
  snell_service_action "$id" stop >/dev/null 2>&1 || true
  case "$manager" in
    systemd) systemctl disable "$unit" >/dev/null 2>&1 || true ;;
    openrc)
      rc-update del "$service" default >/dev/null 2>&1 || true
      rm -f "${NOBRAND_SNELL_OPENRC_PREFIX}${id}"
      ;;
  esac
}
