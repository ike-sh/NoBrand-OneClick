# ---------- NoBrand isolated Xray-core runtime / Hysteria2 service ----------

nobrand_prepare_common() {
  local pm
  require_root
  require_linux
  pm="$(detect_pkg_manager)"
  STAGE="安装 NoBrand 公共依赖"
  case "$pm" in
    deb)
      if ! command -v curl >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1 \
         || ! command -v unzip >/dev/null 2>&1 || ! command -v openssl >/dev/null 2>&1 \
         || ! command -v python3 >/dev/null 2>&1; then
        run apt-get update
        run apt-get install -y curl ca-certificates jq unzip openssl python3 iproute2 util-linux tar
      fi
      ;;
    rpm)
      if command -v dnf >/dev/null 2>&1; then
        run dnf install -y curl ca-certificates jq unzip openssl python3 iproute util-linux tar
      else
        run yum install -y curl ca-certificates jq unzip openssl python3 iproute util-linux tar
      fi
      ;;
    alpine)
      run apk add --no-cache bash curl ca-certificates jq unzip openssl python3 iproute2 util-linux tar libstdc++
      ;;
  esac
  nb_init_state_layout
}

nobrand_xray_arch_asset() {
  case "${NOBRAND_TEST_ARCH:-$(uname -m)}" in
    x86_64|amd64) printf 'Xray-linux-64.zip' ;;
    aarch64|arm64) printf 'Xray-linux-arm64-v8a.zip' ;;
    *) return 1 ;;
  esac
}

nobrand_xray_tested_digest() {
  case "$1" in
    Xray-linux-64.zip) printf '%s' "$TESTED_XRAY_AMD64_SHA256" ;;
    Xray-linux-arm64-v8a.zip) printf '%s' "$TESTED_XRAY_ARM64_SHA256" ;;
    *) return 1 ;;
  esac
}

nobrand_xray_version() {
  local output version
  [ -x "$NOBRAND_XRAY_BIN" ] || return 1
  output="$("$NOBRAND_XRAY_BIN" version 2>/dev/null)" || return 1
  version="$(printf '%s\n' "$output" \
    | sed -nE 's/^Xray[[:space:]]+([^[:space:]]+).*/\1/p' | head -n1)"
  [ -n "$version" ] || return 1
  printf '%s' "$version"
}

nobrand_xray_release_info() {
  local asset metadata version url digest expected
  asset="$(nobrand_xray_arch_asset)" || {
    warn "$(t 'NoBrand Sudoku 的 Xray runtime 仅测试 amd64/arm64' \
      'NoBrand Sudoku Xray runtime is tested only on amd64/arm64')"
    return 1
  }
  metadata="$(mktemp_file .json)" || return 1
  if ! curl -fsSL --connect-timeout 15 --max-time 90 \
      --retry 3 --retry-delay 2 --retry-all-errors \
      -H 'Accept: application/vnd.github+json' \
      -H 'User-Agent: NoBrand-OneClick' "$NOBRAND_XRAY_RELEASE_API" -o "$metadata"; then
    rm -f "$metadata"
    return 1
  fi
  IFS=$'\t' read -r version url digest < <(jq -r --arg asset "$asset" '
    .tag_name as $version |
    first(.assets[]? | select(.name == $asset)) as $matched |
    select($matched != null) |
    [$version, $matched.browser_download_url, ($matched.digest // "")] | @tsv
  ' "$metadata")
  local rc=$?
  rm -f "$metadata"
  [ "$rc" -eq 0 ] && [ "$version" = "v${TESTED_XRAY_VERSION}" ] || return 1
  expected="$(nobrand_xray_tested_digest "$asset")" || return 1
  [ "$digest" = "sha256:${expected}" ] || return 1
  printf '%s\t%s\t%s\n' "$version" "$url" "$digest"
}

nobrand_sha256_file() {
  local file="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" | awk '{print tolower($1)}'
  else
    openssl dgst -sha256 "$file" 2>/dev/null | awk '{print tolower($NF)}'
  fi
}

nobrand_verify_release_digest() {
  local file="$1" digest="${2:-}" expected actual
  [ -n "$digest" ] || {
    info "$(t '上游 release API 未提供资产 hash；已继续执行 archive/ELF/runtime 校验' \
      'Upstream release API has no asset hash; archive/ELF/runtime validation will still run')"
    return 0
  }
  case "$digest" in
    sha256:*) expected="${digest#sha256:}" ;;
    *) warn "不支持的上游 digest: $digest"; return 1 ;;
  esac
  [[ "$expected" =~ ^[0-9A-Fa-f]{64}$ ]] || return 1
  actual="$(nobrand_sha256_file "$file")" || return 1
  [ "$(printf '%s' "$actual" | tr '[:upper:]' '[:lower:]')" = \
    "$(printf '%s' "$expected" | tr '[:upper:]' '[:lower:]')" ]
}

nobrand_download_xray_candidate() {
  local output="$1" asset_output_dir="${2:-}" info_line version url digest archive_dir candidate asset
  info_line="$(nobrand_xray_release_info)" || return 1
  IFS=$'\t' read -r version url digest <<<"$info_line"
  [[ "$url" = https://github.com/XTLS/Xray-core/releases/download/* ]] || {
    warn "拒绝非 XTLS 官方 HTTPS 资产: $url"
    return 1
  }
  archive_dir="$(mktemp_dir)" || return 1
  if ! curl -fL --connect-timeout 15 --max-time 180 \
      --retry 3 --retry-delay 2 --retry-all-errors \
      -H 'User-Agent: NoBrand-OneClick' "$url" -o "$archive_dir/xray.zip" \
     || ! nobrand_verify_release_digest "$archive_dir/xray.zip" "$digest" \
     || ! unzip -t "$archive_dir/xray.zip" >/dev/null \
     || ! unzip -qo "$archive_dir/xray.zip" -d "$archive_dir/unpacked"; then
    rm -rf -- "$archive_dir"
    return 1
  fi
  candidate="$archive_dir/unpacked/xray"
  [ -f "$candidate" ] || candidate="$(find "$archive_dir/unpacked" -type f -name xray | head -n1)"
  [ -n "$candidate" ] && [ -f "$candidate" ] || { rm -rf -- "$archive_dir"; return 1; }
  chmod 0755 "$candidate" || { rm -rf -- "$archive_dir"; return 1; }
  "$candidate" version >/dev/null 2>&1 || { rm -rf -- "$archive_dir"; return 1; }
  install -m 0755 "$candidate" "$output" || { rm -rf -- "$archive_dir"; return 1; }
  if [ -n "$asset_output_dir" ]; then
    mkdir -p "$asset_output_dir" || { rm -rf -- "$archive_dir"; return 1; }
    for asset in geoip.dat geosite.dat; do
      [ -s "$archive_dir/unpacked/$asset" ] \
        || { rm -rf -- "$archive_dir"; return 1; }
      install -m 0644 "$archive_dir/unpacked/$asset" "$asset_output_dir/$asset" \
        || { rm -rf -- "$archive_dir"; return 1; }
    done
  fi
  info "$(t "NoBrand 独立 Xray-core 资产已解析: ${version}" \
    "NoBrand isolated Xray-core asset resolved: ${version}")"
  rm -rf -- "$archive_dir"
}

nobrand_xray_asset_dir_safe() {
  [ -n "${NOBRAND_LIB_DIR:-}" ] && [ -n "${NOBRAND_XRAY_ASSET_DIR:-}" ] \
    && [ "$NOBRAND_XRAY_ASSET_DIR" != / ] \
    && [[ "$NOBRAND_XRAY_ASSET_DIR" == "$NOBRAND_LIB_DIR"/* ]]
}

nobrand_xray_assets_ready() {
  nobrand_xray_asset_dir_safe \
    && [ -s "$NOBRAND_XRAY_ASSET_DIR/geoip.dat" ] \
    && [ -s "$NOBRAND_XRAY_ASSET_DIR/geosite.dat" ]
}

nobrand_remove_xray_runtime_files() {
  nobrand_xray_asset_dir_safe || return 1
  rm -f "$NOBRAND_XRAY_BIN" || return 1
  rm -rf -- "$NOBRAND_XRAY_ASSET_DIR"
}

nobrand_install_xray_runtime() {
  local force="${1:-0}" candidate candidate_assets snapshot new_assets
  local had_runtime=0 had_assets=0 replace_runtime=1 rc=0
  nobrand_xray_asset_dir_safe || return 1
  if [ -x "$NOBRAND_XRAY_BIN" ] && nobrand_xray_assets_ready && [ "$force" -ne 1 ]; then
    return 0
  fi
  if [ -x "$NOBRAND_XRAY_BIN" ] && [ "$force" -ne 1 ]; then
    [ "$(nobrand_xray_version 2>/dev/null || true)" = "$TESTED_XRAY_VERSION" ] || return 1
    replace_runtime=0
  fi
  candidate="$(mktemp_file .xray)" || return 1
  candidate_assets="$(mktemp_dir)" || { rm -f "$candidate"; return 1; }
  if ! nobrand_download_xray_candidate "$candidate" "$candidate_assets"; then
    rm -f "$candidate"
    rm -rf -- "$candidate_assets"
    warn "$(t 'NoBrand 独立 Xray-core 下载或校验失败' \
      'NoBrand isolated Xray-core download or validation failed')"
    return 1
  fi
  snapshot="$(mktemp_dir)" || { rm -f "$candidate"; rm -rf -- "$candidate_assets"; return 1; }
  if [ -e "$NOBRAND_XRAY_BIN" ]; then
    cp -a "$NOBRAND_XRAY_BIN" "$snapshot/xray" || rc=1
    had_runtime=1
  fi
  if [ -d "$NOBRAND_XRAY_ASSET_DIR" ] && [ ! -L "$NOBRAND_XRAY_ASSET_DIR" ]; then
    cp -a "$NOBRAND_XRAY_ASSET_DIR" "$snapshot/assets" || rc=1
    had_assets=1
  fi
  new_assets="${NOBRAND_XRAY_ASSET_DIR}.new.$$"
  if [ "$rc" -eq 0 ]; then
    nb_lifecycle_mark_protocol_mutation_started "${NOBRAND_LIFECYCLE_SCOPE:-}" || {
      rm -f "$candidate"
      rm -rf -- "$candidate_assets" "$snapshot"
      return 1
    }
    mkdir -p "$(dirname "$NOBRAND_XRAY_BIN")" "$(dirname "$NOBRAND_XRAY_ASSET_DIR")" \
      && rm -rf -- "$new_assets" \
      && mkdir -p "$new_assets" \
      && install -m 0644 "$candidate_assets/geoip.dat" "$new_assets/geoip.dat" \
      && install -m 0644 "$candidate_assets/geosite.dat" "$new_assets/geosite.dat" || rc=1
  fi
  if [ "$rc" -eq 0 ] && [ "$replace_runtime" -eq 1 ]; then
    install -m 0755 "$candidate" "${NOBRAND_XRAY_BIN}.new" \
      && mv -f "${NOBRAND_XRAY_BIN}.new" "$NOBRAND_XRAY_BIN" \
      && [ "$(nobrand_xray_version 2>/dev/null || true)" = "$TESTED_XRAY_VERSION" ] || rc=1
  fi
  if [ "$rc" -eq 0 ]; then
    rm -rf -- "$NOBRAND_XRAY_ASSET_DIR" \
      && mv "$new_assets" "$NOBRAND_XRAY_ASSET_DIR" \
      && nobrand_xray_assets_ready \
      && nobrand_xray_validate_managed_configs "$NOBRAND_XRAY_BIN" || rc=1
  fi
  rm -f "$candidate" "${NOBRAND_XRAY_BIN}.new"
  rm -rf -- "$candidate_assets" "$new_assets"
  if [ "$rc" -ne 0 ]; then
    rm -f "$NOBRAND_XRAY_BIN"
    [ "$had_runtime" -eq 0 ] || install -m 0755 "$snapshot/xray" "$NOBRAND_XRAY_BIN" 2>/dev/null || true
    rm -rf -- "$NOBRAND_XRAY_ASSET_DIR"
    [ "$had_assets" -eq 0 ] \
      || cp -a "$snapshot/assets" "$NOBRAND_XRAY_ASSET_DIR" 2>/dev/null || true
    rm -rf -- "$snapshot"
    return 1
  fi
  rm -rf -- "$snapshot"
}

nobrand_xray_redact_validation_log() {
  local config="$1" log="$2"
  if ! command -v python3 >/dev/null 2>&1; then
    printf '%s\n' "$(t '[校验详情已隐藏：脱敏器不可用]' \
      '[validation details suppressed: redactor unavailable]')" >&2
    return 0
  fi
  python3 - "$config" "$log" >&2 <<'PY' || {
import json
import re
import sys

config_path, log_path = sys.argv[1:3]
sensitive_keys = {
    "auth", "password", "privatekey", "publickey", "uuid", "shortid", "shortids"
}

try:
    with open(config_path, encoding="utf-8") as handle:
        config = json.load(handle)
    with open(log_path, encoding="utf-8", errors="replace") as handle:
        text = handle.read()
except Exception:
    raise SystemExit(1)

secrets = set()

def collect(value):
    if isinstance(value, dict):
        for key, child in value.items():
            if str(key).casefold() in sensitive_keys:
                values = child if isinstance(child, list) else [child]
                for item in values:
                    if isinstance(item, (str, int, float)) and str(item):
                        secrets.add(str(item))
            collect(child)
    elif isinstance(value, list):
        for child in value:
            collect(child)

collect(config)
for secret in sorted(secrets, key=len, reverse=True):
    text = text.replace(secret, "***REDACTED***")

field = r'(?:auth|password|privateKey|publicKey|uuid|shortId|shortIds)'
text = re.sub(
    rf'(?i)((?:["\']?{field}["\']?)\s*[:=]\s*)(?:"[^"]*"|\'[^\']*\'|[^\s,}}\]]+)',
    lambda match: match.group(1) + '***REDACTED***',
    text,
)
sys.stdout.write(text)
PY
    printf '%s\n' "$(t '[校验详情已隐藏：脱敏失败]' \
      '[validation details suppressed: redaction failed]')" >&2
  }
}

nobrand_xray_test_config() {
  local config="$1" binary="${2:-$NOBRAND_XRAY_BIN}" log
  [ -x "$binary" ] && jq empty "$config" >/dev/null 2>&1 || return 1
  log="$(mktemp_file .log)" || return 1
  if ! XRAY_LOCATION_ASSET="$NOBRAND_XRAY_ASSET_DIR" \
      "$binary" run -test -c "$config" >"$log" 2>&1; then
    warn "$(t 'NoBrand Xray 配置校验失败（已脱敏）:' \
      'NoBrand Xray config validation failed (redacted):')"
    nobrand_xray_redact_validation_log "$config" "$log"
    rm -f "$log"
    return 1
  fi
  rm -f "$log"
}

nobrand_xray_validate_managed_configs() {
  [ ! -f "$NOBRAND_VLESS_CONFIG_FILE" ] || nobrand_xray_test_config "$NOBRAND_VLESS_CONFIG_FILE" "${1:-$NOBRAND_XRAY_BIN}"
}

nobrand_restore_xray_upgrade_snapshot() {
  local snapshot="$1" had_runtime="$2" had_assets="$3" was_active="$4"
  if [ "$had_runtime" = 1 ]; then install -m 0755 "$snapshot/xray" "$NOBRAND_XRAY_BIN" || return 1
  else rm -f "$NOBRAND_XRAY_BIN"; fi
  nobrand_xray_asset_dir_safe || return 1
  rm -rf -- "$NOBRAND_XRAY_ASSET_DIR"
  [ "$had_assets" = 0 ] || cp -a "$snapshot/xray-assets" "$NOBRAND_XRAY_ASSET_DIR" || return 1
  [ ! -f "$snapshot/state" ] || cp -a "$snapshot/state" "$NOBRAND_VLESS_STATE_FILE" || return 1
  [ "$was_active" = 0 ] || nobrand_vless_sudoku_service_action restart
}

nobrand_upgrade_xray_runtime() {
  local snapshot had_runtime=0 had_assets=0 was_active=0 failed=0
  vless_sudoku_state_exists || return 1
  nobrand_prepare_common || return 1
  admin_lock_acquire || return 1
  snapshot="$(mktemp_dir)" || { admin_lock_release; return 1; }
  if [ -f "$NOBRAND_XRAY_BIN" ]; then cp -a "$NOBRAND_XRAY_BIN" "$snapshot/xray" || failed=1; had_runtime=1; fi
  if [ -d "$NOBRAND_XRAY_ASSET_DIR" ]; then cp -a "$NOBRAND_XRAY_ASSET_DIR" "$snapshot/xray-assets" || failed=1; had_assets=1; fi
  cp -a "$NOBRAND_VLESS_STATE_FILE" "$snapshot/state" || failed=1
  nobrand_vless_sudoku_service_active && was_active=1
  if [ "$failed" = 0 ]; then
    nobrand_install_xray_runtime 1 && nobrand_xray_validate_managed_configs || failed=1
    if [ "$failed" = 0 ] && [ "$was_active" = 1 ]; then
      nobrand_vless_sudoku_service_action restart && vless_sudoku_running || failed=1
    fi
    [ "$failed" != 0 ] || vless_sudoku_refresh_runtime_metadata || failed=1
  fi
  if [ "$failed" != 0 ]; then
    nobrand_restore_xray_upgrade_snapshot "$snapshot" "$had_runtime" "$had_assets" "$was_active" || warn 'Sudoku runtime rollback failed'
  fi
  rm -rf -- "$snapshot"
  admin_lock_release
  return "$failed"
}
