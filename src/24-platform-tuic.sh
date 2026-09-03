# ---------- official sing-box runtime and isolated TUIC services ----------

tuic_normalize_channel() {
  case "${1:-stable}" in
    stable|latest|pinned) printf '%s' "${1:-stable}" ;;
    *) return 1 ;;
  esac
}

tuic_runtime_asset_name() {
  local version="$1" arch suffix=""
  case "$(uname -m)" in
    x86_64|amd64) arch=amd64 ;;
    aarch64|arm64) arch=arm64 ;;
    *) return 1 ;;
  esac
  [ ! -f /etc/alpine-release ] || suffix=-musl
  printf 'sing-box-%s-linux-%s%s.tar.gz' "$version" "$arch" "$suffix"
}

tuic_tested_runtime_sha256() {
  local asset="$1"
  case "$asset" in
    sing-box-1.13.20-linux-amd64.tar.gz) printf '%s' "$TESTED_SING_BOX_AMD64_SHA256" ;;
    sing-box-1.13.20-linux-arm64.tar.gz) printf '%s' "$TESTED_SING_BOX_ARM64_SHA256" ;;
    sing-box-1.13.20-linux-amd64-musl.tar.gz) printf '%s' "$TESTED_SING_BOX_AMD64_MUSL_SHA256" ;;
    sing-box-1.13.20-linux-arm64-musl.tar.gz) printf '%s' "$TESTED_SING_BOX_ARM64_MUSL_SHA256" ;;
    *) return 1 ;;
  esac
}

tuic_valid_runtime_version() {
  [[ "${1:-}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

tuic_resolve_runtime() {
  local channel version api response tag asset url digest stable_digest
  channel="$(tuic_normalize_channel "${1:-stable}")" || return 1
  version="${2:-}"
  case "$channel" in
    stable) version="$TESTED_SING_BOX_SERVER_VERSION"; api="${NOBRAND_SING_BOX_RELEASE_API}/tags/v${version}" ;;
    latest) api="${NOBRAND_SING_BOX_RELEASE_API}/latest" ;;
    pinned)
      tuic_valid_runtime_version "$version" || return 1
      api="${NOBRAND_SING_BOX_RELEASE_API}/tags/v${version}"
      ;;
  esac
  response="$(curl -fsSL --connect-timeout 10 --max-time 60 \
    -H 'Accept: application/vnd.github+json' -H 'User-Agent: NoBrand-OneClick' "$api")" || return 1
  jq -e '.draft==false and .prerelease==false' <<<"$response" >/dev/null || return 1
  tag="$(jq -r .tag_name <<<"$response")"
  [[ "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
  version="${tag#v}"
  asset="$(tuic_runtime_asset_name "$version")" || return 1
  url="$(jq -r --arg asset "$asset" '.assets[] | select(.name==$asset) | .browser_download_url' \
    <<<"$response" | head -n1)"
  digest="$(jq -r --arg asset "$asset" '.assets[] | select(.name==$asset) | .digest // empty' \
    <<<"$response" | head -n1)"
  digest="${digest#sha256:}"
  [ -n "$url" ] && [[ "$digest" =~ ^[0-9a-f]{64}$ ]] || return 1
  if [ "$channel" = stable ]; then
    stable_digest="$(tuic_tested_runtime_sha256 "$asset")" || return 1
    [ "$digest" = "$stable_digest" ] || return 1
  fi
  TUIC_RUNTIME_RESOLVED_VERSION="$version"
  TUIC_RUNTIME_RESOLVED_URL="$url"
  TUIC_RUNTIME_RESOLVED_SHA256="$digest"
  TUIC_RUNTIME_RESOLVED_ASSET="$asset"
}

tuic_runtime_version() {
  local binary="${1:-$NOBRAND_SING_BOX_BIN}"
  [ -x "$binary" ] || return 1
  "$binary" version 2>/dev/null | awk '$1=="sing-box" && $2=="version" {print $3; exit}'
}

tuic_download_runtime_candidate() {
  local output="$1" channel="${2:-stable}" requested_version="${3:-}" archive extract_dir binary actual_sha actual_version
  tuic_resolve_runtime "$channel" "$requested_version" || return 1
  archive="$(mktemp_file .sing-box.tar.gz)" || return 1
  extract_dir="$(mktemp_dir)" || return 1
  curl -fL --connect-timeout 10 --max-time 300 -H 'User-Agent: NoBrand-OneClick' \
    "$TUIC_RUNTIME_RESOLVED_URL" -o "$archive" || return 1
  actual_sha="$(nobrand_sha256_file "$archive")" || return 1
  [ "$actual_sha" = "$TUIC_RUNTIME_RESOLVED_SHA256" ] || {
    warn "$(t '官方 sing-box 发布摘要不匹配' \
      'official sing-box release digest mismatch')"
    return 1
  }
  tar --no-same-owner -C "$extract_dir" -xzf "$archive" || return 1
  binary="$(find "$extract_dir" -mindepth 2 -maxdepth 2 -type f -name sing-box -print -quit)"
  [ -n "$binary" ] && [ -f "$binary" ] || return 1
  install -m 0755 "$binary" "$output" || return 1
  actual_version="$(tuic_runtime_version "$output")" || return 1
  [ "$actual_version" = "$TUIC_RUNTIME_RESOLVED_VERSION" ] || return 1
  rm -f "$archive"
  rm -rf -- "$extract_dir"
}

tuic_generate_runtime_metadata() {
  local output="$1" channel="$2" version="$3"
  jq -n --arg version "$version" --arg channel "$channel" \
    --arg asset "$TUIC_RUNTIME_RESOLVED_ASSET" --arg source "$TUIC_RUNTIME_RESOLVED_URL" \
    --arg sha256 "$TUIC_RUNTIME_RESOLVED_SHA256" --arg installed "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
    {ownership:"nobrand-v3",consumer:"tuic-v5",version:$version,channel:$channel,
     asset:$asset,source_url:$source,sha256:$sha256,installed_at:$installed}
  ' >"$output"
}

tuic_runtime_metadata_valid() {
  local expected_version="${1:-}" expected_channel="${2:-}"
  [ -s "$NOBRAND_SING_BOX_RUNTIME_META" ] || return 1
  jq -e --arg version "$expected_version" --arg channel "$expected_channel" '
    .ownership=="nobrand-v3" and .consumer=="tuic-v5"
    and ($version=="" or .version==$version)
    and ($channel=="" or .channel==$channel)
    and (.sha256|test("^[0-9a-f]{64}$"))
  ' "$NOBRAND_SING_BOX_RUNTIME_META" >/dev/null
}

tuic_snapshot_runtime_files() {
  local snapshot="$1"
  mkdir -p "$snapshot" || return 1
  if [ -e "$NOBRAND_SING_BOX_BIN" ]; then
    cp -a "$NOBRAND_SING_BOX_BIN" "$snapshot/binary" || return 1
  else
    : >"$snapshot/binary.absent" || return 1
  fi
  if [ -e "$NOBRAND_SING_BOX_RUNTIME_META" ]; then
    cp -a "$NOBRAND_SING_BOX_RUNTIME_META" "$snapshot/metadata" || return 1
  else
    : >"$snapshot/metadata.absent" || return 1
  fi
}

tuic_restore_runtime_files() {
  local snapshot="$1"
  if [ -e "$snapshot/binary" ]; then
    mkdir -p "$(dirname "$NOBRAND_SING_BOX_BIN")" || return 1
    nb_atomic_install_file "$snapshot/binary" "$NOBRAND_SING_BOX_BIN" 0755 || return 1
  elif [ -f "$snapshot/binary.absent" ] && [ ! -L "$snapshot/binary.absent" ]; then
    rm -f "$NOBRAND_SING_BOX_BIN" || return 1
  else
    return 1
  fi
  if [ -e "$snapshot/metadata" ]; then
    mkdir -p "$(dirname "$NOBRAND_SING_BOX_RUNTIME_META")" || return 1
    nb_atomic_install_file "$snapshot/metadata" "$NOBRAND_SING_BOX_RUNTIME_META" 0600 || return 1
  elif [ -f "$snapshot/metadata.absent" ] && [ ! -L "$snapshot/metadata.absent" ]; then
    rm -f "$NOBRAND_SING_BOX_RUNTIME_META" || return 1
  else
    return 1
  fi
}

tuic_snapshot_restore_side_effects() {
  local snapshot="$1"
  mkdir -p "$snapshot/runtime" || return 1
  tuic_snapshot_runtime_files "$snapshot/runtime" || return 1
  if [ -e "$NOBRAND_TUIC_SYSTEMD_TEMPLATE" ]; then
    cp -a "$NOBRAND_TUIC_SYSTEMD_TEMPLATE" "$snapshot/systemd-template" || return 1
  else
    : >"$snapshot/systemd-template.absent" || return 1
  fi
}

tuic_remove_restore_attempt_resources() {
  local id port failed=0
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    port="$(tuic_state_field "$id" listen_port 2>/dev/null || true)"
    tuic_remove_service "$id" || failed=1
    [ -z "$port" ] || nb_firewall_close_pairs "UDP|${port}" || failed=1
  done < <(tuic_instance_ids)
  [ "$failed" -eq 0 ]
}

tuic_restore_side_effect_snapshot() {
  local snapshot="$1" failed=0
  tuic_restore_runtime_files "$snapshot/runtime" || failed=1
  if [ -e "$snapshot/systemd-template" ]; then
    mkdir -p "$(dirname "$NOBRAND_TUIC_SYSTEMD_TEMPLATE")" || failed=1
    cp -a "$snapshot/systemd-template" "$NOBRAND_TUIC_SYSTEMD_TEMPLATE" || failed=1
  elif [ -f "$snapshot/systemd-template.absent" ] \
       && [ ! -L "$snapshot/systemd-template.absent" ]; then
    rm -f "$NOBRAND_TUIC_SYSTEMD_TEMPLATE" || failed=1
  else
    failed=1
  fi
  [ "$(nb_service_manager)" != systemd ] || systemctl daemon-reload >/dev/null 2>&1 || failed=1
  [ "$failed" -eq 0 ]
}

tuic_install_runtime() {
  local channel="${1:-stable}" requested_version="${2:-}" candidate snapshot metadata_tmp version
  candidate="$(mktemp_file .sing-box)" || return 1
  tuic_download_runtime_candidate "$candidate" "$channel" "$requested_version" || return 1
  snapshot="$(mktemp_dir)" || return 1
  tuic_snapshot_runtime_files "$snapshot" || return 1
  mkdir -p "$NOBRAND_BIN_DIR" "$(dirname "$NOBRAND_SING_BOX_RUNTIME_META")" || {
    tuic_restore_runtime_files "$snapshot" || true
    return 1
  }
  chmod 0755 "$NOBRAND_BIN_DIR" || {
    tuic_restore_runtime_files "$snapshot" || true
    return 1
  }
  if ! nb_atomic_install_file "$candidate" "$NOBRAND_SING_BOX_BIN" 0755; then
    tuic_restore_runtime_files "$snapshot" || true
    return 1
  fi
  version="$(tuic_runtime_version)" || {
    tuic_restore_runtime_files "$snapshot" || true
    return 1
  }
  metadata_tmp="$(mktemp_file .tuic-runtime-meta)" || {
    tuic_restore_runtime_files "$snapshot" || true
    return 1
  }
  tuic_generate_runtime_metadata "$metadata_tmp" "$channel" "$version" \
    && nb_atomic_install_file "$metadata_tmp" "$NOBRAND_SING_BOX_RUNTIME_META" 0600 \
    || {
      tuic_restore_runtime_files "$snapshot" || true
      return 1
    }
  rm -f "$candidate" "$metadata_tmp"
  rm -rf -- "$snapshot"
}

tuic_validate_config() {
  local config="$1" binary="${2:-$NOBRAND_SING_BOX_BIN}"
  [ -x "$binary" ] && "$binary" check -c "$config" >/dev/null
}

tuic_systemd_unit() { printf 'nobrand-tuic@%s.service' "$1"; }
tuic_openrc_service() { printf 'nobrand-tuic-%s' "$1"; }

tuic_install_service_runtime() {
  local manager tmp
  manager="$(nb_service_manager)"
  case "$manager" in
    systemd)
      tmp="$(mktemp_file .tuic-service)" || return 1
      cat >"$tmp" <<EOF
[Unit]
Description=NoBrand TUIC v5 instance %i
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=${NOBRAND_SING_BOX_BIN} run -c ${NOBRAND_TUIC_CONFIG_DIR}/%i/config.json
Restart=on-failure
RestartSec=2
NoNewPrivileges=true
PrivateTmp=true
ProtectHome=true
ProtectSystem=strict
ReadOnlyPaths=${NOBRAND_TUIC_CONFIG_DIR} ${NOBRAND_SING_BOX_BIN}

[Install]
WantedBy=multi-user.target
EOF
      nb_atomic_install_file "$tmp" "$NOBRAND_TUIC_SYSTEMD_TEMPLATE" 0644 || return 1
      systemctl daemon-reload
      ;;
    openrc) ;;
    *) return 1 ;;
  esac
}

tuic_ensure_openrc_service() {
  local id="$1" path tmp
  [ "$(nb_service_manager)" = openrc ] || return 0
  path="${NOBRAND_TUIC_OPENRC_PREFIX}${id}"
  tmp="$(mktemp_file .tuic-openrc)" || return 1
  cat >"$tmp" <<EOF
#!/sbin/openrc-run
name="NoBrand TUIC v5 ${id}"
command="${NOBRAND_SING_BOX_BIN}"
command_args="run -c ${NOBRAND_TUIC_CONFIG_DIR}/${id}/config.json"
command_background="yes"
pidfile="/run/nobrand-tuic-${id}.pid"
output_log="/var/log/nobrand-tuic-${id}.log"
error_log="/var/log/nobrand-tuic-${id}.err"
depend() { use net; after firewall; }
EOF
  nb_atomic_install_file "$tmp" "$path" 0755 || return 1
  rc-update add "$(tuic_openrc_service "$id")" default >/dev/null 2>&1
}

tuic_service_action() {
  local id="$1" action="$2" manager
  manager="$(nb_service_manager)"
  case "$manager" in
    systemd)
      [ "$action" != start ] || systemctl enable "$(tuic_systemd_unit "$id")" >/dev/null 2>&1
      systemctl "$action" "$(tuic_systemd_unit "$id")"
      ;;
    openrc)
      tuic_ensure_openrc_service "$id" || return 1
      rc-service "$(tuic_openrc_service "$id")" "$action"
      ;;
    *) return 1 ;;
  esac
}

tuic_service_active() {
  local id="$1"
  nb_service_is_active "$(tuic_systemd_unit "$id")" "$(tuic_openrc_service "$id")"
}

tuic_service_pid() {
  local id="$1" manager pid_file
  manager="$(nb_service_manager)"
  case "$manager" in
    systemd) systemctl show -p MainPID --value "$(tuic_systemd_unit "$id")" 2>/dev/null ;;
    openrc)
      pid_file="/run/nobrand-tuic-${id}.pid"
      [ -s "$pid_file" ] && cat "$pid_file"
      ;;
  esac
}

tuic_listener_owned_by_service() {
  local id="$1" port="$2" expected pid
  expected="$(tuic_service_pid "$id" 2>/dev/null || true)"
  [[ "$expected" =~ ^[0-9]+$ ]] && [ "$expected" -gt 1 ] || return 1
  while IFS= read -r pid; do
    [ "$pid" = "$expected" ] && return 0
  done < <(nb_port_listener_pids UDP "$port")
  return 1
}

tuic_remove_service() {
  local id="$1" manager
  manager="$(nb_service_manager)"
  case "$manager" in
    systemd)
      systemctl disable --now "$(tuic_systemd_unit "$id")" >/dev/null 2>&1 || true
      ;;
    openrc)
      rc-service "$(tuic_openrc_service "$id")" stop >/dev/null 2>&1 || true
      rc-update del "$(tuic_openrc_service "$id")" default >/dev/null 2>&1 || true
      rm -f "${NOBRAND_TUIC_OPENRC_PREFIX}${id}"
      ;;
  esac
}
