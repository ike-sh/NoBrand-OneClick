run() {
  if [ "$DRY_RUN" -eq 1 ]; then
    local rendered=""
    printf -v rendered '%q ' "$@"
    t "[演练] ${rendered% }" "[dry-run] ${rendered% }"
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

nb_schema_v3_file_valid() {
  local path="${1:-$NOBRAND_REGISTRY_FILE}"
  [ -f "$path" ] && [ ! -L "$path" ] || return 1
  if command -v jq >/dev/null 2>&1; then
    jq -e --argjson schema "$NOBRAND_SCHEMA_VERSION" '
      .schema_version == $schema
      and .project == "NoBrand-OneClick"
      and .ownership == "nobrand-v3"
    ' "$path" >/dev/null 2>&1
  elif command -v python3 >/dev/null 2>&1; then
    python3 - "$path" "$NOBRAND_SCHEMA_VERSION" <<'PY' >/dev/null 2>&1
import json, sys
doc = json.load(open(sys.argv[1], encoding="utf-8"))
raise SystemExit(0 if doc.get("schema_version") == int(sys.argv[2])
                 and doc.get("project") == "NoBrand-OneClick"
                 and doc.get("ownership") == "nobrand-v3" else 1)
PY
  else
    grep -Eq '"schema_version"[[:space:]]*:[[:space:]]*3([,}])' "$path" \
      && grep -Eq '"project"[[:space:]]*:[[:space:]]*"NoBrand-OneClick"' "$path" \
      && grep -Eq '"ownership"[[:space:]]*:[[:space:]]*"nobrand-v3"' "$path"
  fi
}

nb_test_mode_enabled() {
  [ "${MITA_SOURCE_ONLY:-0}" = 1 ] && [ "${NOBRAND_TEST_MODE:-0}" = 1 ]
}

nb_directory_empty() (
  local path="$1" entries
  [ -d "$path" ] && [ ! -L "$path" ] || return 1
  shopt -s dotglob nullglob
  entries=("$path"/*)
  [ "${#entries[@]}" -eq 0 ]
)

nb_directory_has_entries() {
  [ -d "$1" ] && ! nb_directory_empty "$1"
}

nb_installed_manager_version() {
  local path="${1:-$NOBRAND_INSTALL_SCRIPT_PATH}" version
  [ -f "$path" ] && [ ! -L "$path" ] || return 1
  nb_test_mode_enabled || state_file_is_secure "$path" || return 1
  grep -qxF 'SCRIPT_NAME="NoBrand-OneClick"' "$path" 2>/dev/null || return 1
  grep -qxF 'SCRIPT_REPO="ike-sh/NoBrand-OneClick"' "$path" 2>/dev/null || return 1
  version="$(sed -n 's/^SCRIPT_VERSION="\([0-9][0-9.]*\)"$/\1/p' "$path" | sed -n '1p')"
  [[ "$version" =~ ^[0-9]+[.][0-9]+[.][0-9]+$ ]] || return 1
  printf '%s' "$version"
}

nb_command_manager_version() {
  local path="$1" expected_target="$2" target resolved
  if [ -L "$path" ]; then
    target="$(readlink -- "$path" 2>/dev/null || true)"
    [ "$target" = "$expected_target" ] && [ -e "$path" ] || return 1
    resolved="$(readlink -f -- "$path" 2>/dev/null \
      || realpath "$path" 2>/dev/null || true)"
    [ -n "$resolved" ] || return 1
    nb_installed_manager_version "$resolved"
    return
  fi
  nb_installed_manager_version "$path"
}

nb_legacy_signature_version() {
  # Real pre-v3 releases wrote this exact state format below
  # /var/lib/mita-oneclick. Directory or package existence alone is not proof.
  local path="${NOBRAND_LEGACY_MIERU_STATE_DIR}/install-state.env"
  local port port_range protocol install_script range_start range_end key
  local legacy_install_script='/usr/local/bin/install-'mita
  [ -f "$path" ] && [ ! -L "$path" ] || return 1
  nb_test_mode_enabled || state_file_is_secure "$path" || return 1
  for key in INSTALL_METHOD PORT PORT_RANGE PROTOCOL INSTALL_SCRIPT; do
    [ "$(grep -c "^${key}=" "$path" 2>/dev/null || true)" -eq 1 ] || return 1
  done
  grep -qx 'INSTALL_METHOD=oneclick' "$path" 2>/dev/null || return 1
  port="$(sed -n 's/^PORT=//p' "$path")"
  port_range="$(sed -n 's/^PORT_RANGE=//p' "$path")"
  protocol="$(sed -n 's/^PROTOCOL=//p' "$path")"
  install_script="$(sed -n 's/^INSTALL_SCRIPT=//p' "$path")"
  case "$protocol" in TCP|UDP|BOTH) ;; *) return 1 ;; esac
  [ "$install_script" = "$legacy_install_script" ] || return 1
  if [ "$port_range" = "''" ]; then
    [[ "$port" =~ ^[0-9]{1,5}$ ]] || return 1
    [ "$((10#$port))" -ge 1 ] && [ "$((10#$port))" -le 65535 ] || return 1
  elif [ "$port" = "''" ]; then
    [[ "$port_range" =~ ^([0-9]{1,5})-([0-9]{1,5})$ ]] || return 1
    range_start="${BASH_REMATCH[1]}"
    range_end="${BASH_REMATCH[2]}"
    [ "$((10#$range_start))" -ge 1 ] \
      && [ "$((10#$range_end))" -le 65535 ] \
      && [ "$((10#$range_start))" -le "$((10#$range_end))" ] || return 1
  else
    return 1
  fi
  printf 'pre-v3 (INSTALL_METHOD=oneclick)'
}

nb_legacy_state_detected() {
  nb_legacy_signature_version >/dev/null 2>&1
}

nb_normalize_path() {
  local value="${1:-}" normalized="" parent="" base=""
  [ -n "$value" ] || return 1
  case "$value" in
    /*) ;;
    *) value="${PWD%/}/${value}" ;;
  esac
  # Refuse ambiguous lexical traversal when a platform lacks GNU -m support.
  # Lifecycle and destructive roots are expected to be canonical absolute paths.
  case "$value" in
    *'/../'*|*/..|*'/./'*|*/.) return 1 ;;
  esac
  if normalized="$(readlink -m -- "$value" 2>/dev/null)" \
     && [ -n "$normalized" ]; then
    printf '%s' "$normalized"
    return 0
  fi
  if normalized="$(realpath -m -- "$value" 2>/dev/null)" \
     && [ -n "$normalized" ]; then
    printf '%s' "$normalized"
    return 0
  fi

  # BusyBox has no readlink -m, and its realpath may emit partial output while
  # returning failure for unsupported flags. Resolve the nearest existing
  # ancestor instead, then append only the missing path components.
  while [ "$value" != / ] && [ "${value%/}" != "$value" ]; do
    value="${value%/}"
  done
  if [ -e "$value" ] || [ -L "$value" ]; then
    if normalized="$(readlink -f -- "$value" 2>/dev/null)" \
       && [ -n "$normalized" ]; then
      printf '%s' "$normalized"
      return 0
    fi
    if normalized="$(realpath "$value" 2>/dev/null)" \
       && [ -n "$normalized" ]; then
      printf '%s' "$normalized"
      return 0
    fi
    return 1
  fi
  base="${value##*/}"
  parent="${value%/*}"
  [ -n "$base" ] || return 1
  [ -n "$parent" ] || parent=/
  normalized="$(nb_normalize_path "$parent")" || return 1
  if [ "$normalized" = / ]; then
    printf '/%s' "$base"
  else
    printf '%s/%s' "$normalized" "$base"
  fi
}

nb_lifecycle_paths_valid() {
  local lifecycle state config lib tx_parent lock
  lifecycle="$(nb_normalize_path "$NOBRAND_LIFECYCLE_DIR")" || return 1
  state="$(nb_normalize_path "$NOBRAND_STATE_DIR")" || return 1
  config="$(nb_normalize_path "$NOBRAND_CONFIG_DIR")" || return 1
  lib="$(nb_normalize_path "$NOBRAND_LIB_DIR")" || return 1
  lock="$(nb_normalize_path "$NOBRAND_LIFECYCLE_LOCK_FILE")" || return 1
  case "$lifecycle" in
    /*/nobrand-oneclick-lifecycle) ;;
    *) return 1 ;;
  esac
  case "$lifecycle" in
    "$state"|"$state"/*|"$config"|"$config"/*|"$lib"|"$lib"/*) return 1 ;;
  esac
  case "$lock" in
    /run/nobrand-oneclick/lifecycle.lock|*/run/nobrand-oneclick/lifecycle.lock) ;;
    *) return 1 ;;
  esac
  case "$lock" in
    "$lifecycle"|"$lifecycle"/*|"$state"|"$state"/*|"$config"|"$config"/*|"$lib"|"$lib"/*)
      return 1
      ;;
  esac
  tx_parent="$(dirname "$NOBRAND_LIFECYCLE_TX_FILE")"
  tx_parent="$(nb_normalize_path "$tx_parent")" || return 1
  [ "$tx_parent" = "$lifecycle" ]
}

nb_lifecycle_field() {
  local key="$1" path="${2:-$NOBRAND_LIFECYCLE_TX_FILE}"
  awk -F= -v wanted="$key" '$1==wanted {print substr($0, length($1)+2); exit}' "$path" 2>/dev/null
}

nb_lifecycle_phase_valid() {
  local operation="$1" status="$2" phase="$3"
  if [ "$status" = complete ]; then
    case "$operation:$phase" in
      install:complete|repair:complete) return 0 ;;
      *) return 1 ;;
    esac
  fi
  [ "$status" = in-progress ] || return 1
  case "$operation:$phase" in
    install:prepare|install:state-layout|install:runtime-ready|install:state-committed|\
      install:ready-to-validate)
      return 0
      ;;
    repair:prepare|repair:state-layout|repair:runtime-ready|repair:state-committed|\
      repair:manager-ready|repair:ready-to-validate|repair:partial-uninstall-prepare|\
      repair:partial-uninstall-state-layout|repair:partial-uninstall-manager-ready|\
      repair:partial-uninstall-runtimes-reconciled|\
      repair:partial-uninstall-services-reconciled|\
      repair:partial-uninstall-ssh-confirmation-pending|\
      repair:partial-uninstall-state-validated|\
      repair:partial-uninstall-ready-to-validate)
      return 0
      ;;
    uninstall:prepare|uninstall:runtime-removed|uninstall:before-state-removal|\
      uninstall:state-removed|uninstall:before-config-removal|\
      uninstall:config-removed|uninstall:roots-removed|\
      uninstall:before-manager-removal|uninstall:manager-removed|\
      uninstall:before-final-validation)
      return 0
      ;;
  esac
  return 1
}

nb_lifecycle_tx_valid() {
  local path="$NOBRAND_LIFECYCLE_TX_FILE" operation status manager schema txid started phase
  local mieru_owned preserve_package preserve_user preserve_group preserve_shared
  [ -f "$path" ] && [ ! -L "$path" ] || return 1
  nb_lifecycle_paths_valid || return 1
  if ! nb_test_mode_enabled; then
    secure_stat_path "$NOBRAND_LIFECYCLE_DIR" dir || return 1
    secure_stat_path "$path" file || return 1
  fi
  awk -F= '
    BEGIN {
      required["FORMAT"]=1; required["OPERATION"]=1; required["STATUS"]=1;
      required["MANAGER_VERSION"]=1; required["SCHEMA_GENERATION"]=1;
      required["TRANSACTION_ID"]=1; required["STARTED_AT"]=1;
      required["LAST_COMPLETED_PHASE"]=1; required["MIERU_OWNED"]=1;
      required["MIERU_PRESERVE_PACKAGE"]=1; required["MIERU_PRESERVE_USER"]=1;
      required["MIERU_PRESERVE_GROUP"]=1; required["MIERU_PRESERVE_SHARED"]=1
    }
    NF != 2 || !($1 in required) || seen[$1]++ { bad=1 }
    END {
      for (key in required) if (seen[key] != 1) bad=1
      exit bad ? 1 : 0
    }
  ' "$path" || return 1
  [ "$(nb_lifecycle_field FORMAT "$path")" = nobrand-lifecycle-v1 ] || return 1
  operation="$(nb_lifecycle_field OPERATION "$path")"
  status="$(nb_lifecycle_field STATUS "$path")"
  manager="$(nb_lifecycle_field MANAGER_VERSION "$path")"
  schema="$(nb_lifecycle_field SCHEMA_GENERATION "$path")"
  txid="$(nb_lifecycle_field TRANSACTION_ID "$path")"
  started="$(nb_lifecycle_field STARTED_AT "$path")"
  phase="$(nb_lifecycle_field LAST_COMPLETED_PHASE "$path")"
  mieru_owned="$(nb_lifecycle_field MIERU_OWNED "$path")"
  preserve_package="$(nb_lifecycle_field MIERU_PRESERVE_PACKAGE "$path")"
  preserve_user="$(nb_lifecycle_field MIERU_PRESERVE_USER "$path")"
  preserve_group="$(nb_lifecycle_field MIERU_PRESERVE_GROUP "$path")"
  preserve_shared="$(nb_lifecycle_field MIERU_PRESERVE_SHARED "$path")"
  case "$operation" in install|repair|uninstall) ;; *) return 1 ;; esac
  case "$status" in in-progress|complete) ;; *) return 1 ;; esac
  [ "$operation:$status" != uninstall:complete ] || return 1
  case "$manager" in
    3.2.*) ;;
    *) return 1 ;;
  esac
  [ "$schema" = "$NOBRAND_SCHEMA_VERSION" ] || return 1
  [[ "$txid" =~ ^[A-Za-z0-9._-]{8,128}$ ]] || return 1
  [[ "$started" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] || return 1
  [[ "$phase" =~ ^[a-z0-9][a-z0-9._-]{0,63}$ ]] || return 1
  nb_lifecycle_phase_valid "$operation" "$status" "$phase" || return 1
  case "$mieru_owned:$preserve_package:$preserve_user:$preserve_group:$preserve_shared" in
    0:0:0:0:0|1:[01]:[01]:[01]:[01]) ;;
    *) return 1 ;;
  esac
  [ "$operation" = uninstall ] || [ "$mieru_owned:$preserve_package:$preserve_user:$preserve_group:$preserve_shared" = 0:0:0:0:0 ]
}

nb_lifecycle_prepare_dir() {
  nb_lifecycle_paths_valid || {
    die "$(t '生命周期目录不安全，拒绝继续' 'Unsafe lifecycle directory; refusing to continue')" || return 1
    return 1
  }
  if [ -e "$NOBRAND_LIFECYCLE_DIR" ]; then
    [ -d "$NOBRAND_LIFECYCLE_DIR" ] && [ ! -L "$NOBRAND_LIFECYCLE_DIR" ] || return 1
    nb_test_mode_enabled || secure_stat_path "$NOBRAND_LIFECYCLE_DIR" dir || return 1
  else
    mkdir -p "$NOBRAND_LIFECYCLE_DIR" || return 1
    chmod 0700 "$NOBRAND_LIFECYCLE_DIR" || return 1
    chown root:root "$NOBRAND_LIFECYCLE_DIR" 2>/dev/null || true
  fi
}

nb_lifecycle_random_id() {
  local value=""
  if [ -r /dev/urandom ] && command -v od >/dev/null 2>&1; then
    value="$(od -An -N16 -tx1 /dev/urandom 2>/dev/null | tr -d '[:space:]')"
  fi
  [ -n "$value" ] || value="tx-$${RANDOM}${RANDOM}$(date -u +%s 2>/dev/null || printf 0)"
  printf '%s' "$value"
}

nb_lifecycle_write() {
  local operation="$1" status="$2" txid="$3" started="$4" phase="$5" tmp
  local mieru_owned="${6:-0}" preserve_package="${7:-0}" preserve_user="${8:-0}"
  local preserve_group="${9:-0}" preserve_shared="${10:-0}"
  case "$operation" in install|repair|uninstall) ;; *) return 1 ;; esac
  case "$status" in in-progress|complete) ;; *) return 1 ;; esac
  [[ "$txid" =~ ^[A-Za-z0-9._-]{8,128}$ ]] || return 1
  [[ "$started" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] || return 1
  [[ "$phase" =~ ^[a-z0-9][a-z0-9._-]{0,63}$ ]] || return 1
  nb_lifecycle_phase_valid "$operation" "$status" "$phase" || return 1
  case "$mieru_owned:$preserve_package:$preserve_user:$preserve_group:$preserve_shared" in
    0:0:0:0:0|1:[01]:[01]:[01]:[01]) ;;
    *) return 1 ;;
  esac
  [ "$operation" = uninstall ] || [ "$mieru_owned:$preserve_package:$preserve_user:$preserve_group:$preserve_shared" = 0:0:0:0:0 ] || return 1
  nb_lifecycle_prepare_dir || return 1
  tmp="$(mktemp "${NOBRAND_LIFECYCLE_DIR}/.transaction.XXXXXX")" || return 1
  if ! printf '%s\n' \
      'FORMAT=nobrand-lifecycle-v1' \
      "OPERATION=${operation}" \
      "STATUS=${status}" \
      "MANAGER_VERSION=${SCRIPT_VERSION}" \
      "SCHEMA_GENERATION=${NOBRAND_SCHEMA_VERSION}" \
      "TRANSACTION_ID=${txid}" \
      "STARTED_AT=${started}" \
      "LAST_COMPLETED_PHASE=${phase}" \
      "MIERU_OWNED=${mieru_owned}" \
      "MIERU_PRESERVE_PACKAGE=${preserve_package}" \
      "MIERU_PRESERVE_USER=${preserve_user}" \
      "MIERU_PRESERVE_GROUP=${preserve_group}" \
      "MIERU_PRESERVE_SHARED=${preserve_shared}" >"$tmp" \
    || ! chmod 0600 "$tmp"; then
    rm -f "$tmp"
    return 1
  fi
  chown root:root "$tmp" 2>/dev/null || true
  if ! mv -f "$tmp" "$NOBRAND_LIFECYCLE_TX_FILE"; then
    rm -f "$tmp"
    return 1
  fi
}

nb_lifecycle_begin() {
  local operation="$1" phase="${2:-prepare}" txid="" started=""
  local mieru_owned="${3:-0}" preserve_package="${4:-0}" preserve_user="${5:-0}"
  local preserve_group="${6:-0}" preserve_shared="${7:-0}" allow_transition="${8:-0}"
  local existing_operation=""
  [ "${DRY_RUN:-0}" -eq 0 ] || {
    NOBRAND_LIFECYCLE_OPERATION="$operation"
    NOBRAND_LIFECYCLE_ACTIVE=1
    return 0
  }
  if ! nb_test_mode_enabled && [ "$(id -u 2>/dev/null || printf 1)" -ne 0 ]; then
    return 1
  fi
  if nb_lifecycle_tx_valid && [ "$(nb_lifecycle_field STATUS)" = in-progress ]; then
    existing_operation="$(nb_lifecycle_field OPERATION)"
    if [ "$existing_operation" != "$operation" ]; then
      if [ "$allow_transition:$existing_operation:$operation" = 1:uninstall:repair ]; then
        txid="$(nb_lifecycle_random_id)"
        started="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        mieru_owned=0
        preserve_package=0
        preserve_user=0
        preserve_group=0
        preserve_shared=0
      else
        warn "$(t "未完成的 ${existing_operation} 生命周期事务仍在进行，拒绝以 ${operation} 覆盖" \
          "An unfinished ${existing_operation} lifecycle transaction is active; refusing to replace it with ${operation}")"
        return 1
      fi
    else
      txid="$(nb_lifecycle_field TRANSACTION_ID)"
      started="$(nb_lifecycle_field STARTED_AT)"
      mieru_owned="$(nb_lifecycle_field MIERU_OWNED)"
      preserve_package="$(nb_lifecycle_field MIERU_PRESERVE_PACKAGE)"
      preserve_user="$(nb_lifecycle_field MIERU_PRESERVE_USER)"
      preserve_group="$(nb_lifecycle_field MIERU_PRESERVE_GROUP)"
      preserve_shared="$(nb_lifecycle_field MIERU_PRESERVE_SHARED)"
    fi
  else
    txid="$(nb_lifecycle_random_id)"
    started="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  fi
  nb_lifecycle_write "$operation" in-progress "$txid" "$started" "$phase" \
    "$mieru_owned" "$preserve_package" "$preserve_user" "$preserve_group" \
    "$preserve_shared" || return 1
  NOBRAND_LIFECYCLE_OPERATION="$operation"
  NOBRAND_LIFECYCLE_ACTIVE=1
}

nb_lifecycle_mark_phase() {
  local phase="$1" operation txid started status mieru_owned preserve_package
  local preserve_user preserve_group preserve_shared
  [ "${DRY_RUN:-0}" -eq 0 ] || return 0
  nb_lifecycle_tx_valid || return 1
  operation="$(nb_lifecycle_field OPERATION)"
  status="$(nb_lifecycle_field STATUS)"
  txid="$(nb_lifecycle_field TRANSACTION_ID)"
  started="$(nb_lifecycle_field STARTED_AT)"
  mieru_owned="$(nb_lifecycle_field MIERU_OWNED)"
  preserve_package="$(nb_lifecycle_field MIERU_PRESERVE_PACKAGE)"
  preserve_user="$(nb_lifecycle_field MIERU_PRESERVE_USER)"
  preserve_group="$(nb_lifecycle_field MIERU_PRESERVE_GROUP)"
  preserve_shared="$(nb_lifecycle_field MIERU_PRESERVE_SHARED)"
  [ "$status" = in-progress ] || return 1
  nb_lifecycle_write "$operation" in-progress "$txid" "$started" "$phase" \
    "$mieru_owned" "$preserve_package" "$preserve_user" "$preserve_group" \
    "$preserve_shared"
}

nb_lifecycle_complete() {
  local operation="$1" txid started mieru_owned preserve_package preserve_user
  local preserve_group preserve_shared
  [ "${NOBRAND_LIFECYCLE_ACTIVE:-0}" -eq 1 ] || return 0
  if [ "${DRY_RUN:-0}" -eq 1 ]; then
    NOBRAND_LIFECYCLE_ACTIVE=0
    return 0
  fi
  nb_lifecycle_tx_valid || return 1
  [ "$(nb_lifecycle_field OPERATION)" = "$operation" ] || return 1
  txid="$(nb_lifecycle_field TRANSACTION_ID)"
  started="$(nb_lifecycle_field STARTED_AT)"
  mieru_owned="$(nb_lifecycle_field MIERU_OWNED)"
  preserve_package="$(nb_lifecycle_field MIERU_PRESERVE_PACKAGE)"
  preserve_user="$(nb_lifecycle_field MIERU_PRESERVE_USER)"
  preserve_group="$(nb_lifecycle_field MIERU_PRESERVE_GROUP)"
  preserve_shared="$(nb_lifecycle_field MIERU_PRESERVE_SHARED)"
  nb_lifecycle_write "$operation" complete "$txid" "$started" complete \
    "$mieru_owned" "$preserve_package" "$preserve_user" "$preserve_group" \
    "$preserve_shared" || return 1
  NOBRAND_LIFECYCLE_ACTIVE=0
}

nb_lifecycle_clear() {
  if [ "${DRY_RUN:-0}" -eq 0 ]; then
    rm -f "$NOBRAND_LIFECYCLE_TX_FILE" || return 1
    rmdir "$NOBRAND_LIFECYCLE_DIR" 2>/dev/null || true
  fi
  NOBRAND_LIFECYCLE_ACTIVE=0
  NOBRAND_LIFECYCLE_OPERATION=""
}

nb_lifecycle_lock_acquire() {
  local lock_parent lock_root parent_mode path_identity fd_identity
  if [ "${DRY_RUN:-0}" -eq 1 ]; then
    NOBRAND_LIFECYCLE_LOCK_HELD=$((NOBRAND_LIFECYCLE_LOCK_HELD + 1))
    return 0
  fi
  if [ "${NOBRAND_LIFECYCLE_LOCK_HELD:-0}" -gt 0 ]; then
    NOBRAND_LIFECYCLE_LOCK_HELD=$((NOBRAND_LIFECYCLE_LOCK_HELD + 1))
    return 0
  fi
  command -v flock >/dev/null 2>&1 || {
    die "$(t '缺少 flock，无法安全执行安装、修复或卸载' \
      'flock is required for safe install, repair, or uninstall')" || return 1
    return 1
  }
  nb_lifecycle_paths_valid || return 1
  lock_parent="$(dirname "$NOBRAND_LIFECYCLE_LOCK_FILE")"
  lock_root="$(dirname "$lock_parent")"
  if [ -e "$lock_parent" ] || [ -L "$lock_parent" ]; then
    [ -d "$lock_parent" ] && [ ! -L "$lock_parent" ] || return 1
  else
    [ -d "$lock_root" ] && [ ! -L "$lock_root" ] || return 1
    mkdir "$lock_parent" || return 1
    chmod 0700 "$lock_parent" || return 1
    chown root:root "$lock_parent" 2>/dev/null || true
  fi
  if ! nb_test_mode_enabled; then
    secure_stat_path "$lock_parent" dir || return 1
  fi
  parent_mode="$(stat -c '%a' "$lock_parent" 2>/dev/null || true)"
  [ "$parent_mode" = 700 ] || return 1
  if [ -e "$NOBRAND_LIFECYCLE_LOCK_FILE" ] || [ -L "$NOBRAND_LIFECYCLE_LOCK_FILE" ]; then
    [ -f "$NOBRAND_LIFECYCLE_LOCK_FILE" ] && [ ! -L "$NOBRAND_LIFECYCLE_LOCK_FILE" ] || return 1
    nb_test_mode_enabled || secure_stat_path "$NOBRAND_LIFECYCLE_LOCK_FILE" file || return 1
  fi
  exec 7>>"$NOBRAND_LIFECYCLE_LOCK_FILE" || return 1
  chmod 0600 "$NOBRAND_LIFECYCLE_LOCK_FILE" || { exec 7>&-; return 1; }
  chown root:root "$NOBRAND_LIFECYCLE_LOCK_FILE" 2>/dev/null || true
  path_identity="$(stat -c '%d:%i' "$NOBRAND_LIFECYCLE_LOCK_FILE" 2>/dev/null || true)"
  fd_identity="$(stat -Lc '%d:%i' /proc/self/fd/7 2>/dev/null || true)"
  [ -n "$path_identity" ] && [ "$path_identity" = "$fd_identity" ] \
    || { exec 7>&-; return 1; }
  nb_test_mode_enabled || secure_stat_path "$NOBRAND_LIFECYCLE_LOCK_FILE" file \
    || { exec 7>&-; return 1; }
  if ! flock -n 7; then
    exec 7>&-
    die "$(t '检测到另一项 NoBrand 安装、修复或卸载任务正在运行，请稍后重试。' \
      'Another NoBrand install, repair, or uninstall operation is running; try again later.')" || return 1
    return 1
  fi
  NOBRAND_LIFECYCLE_LOCK_HELD=1
}

nb_lifecycle_lock_release() {
  [ "${NOBRAND_LIFECYCLE_LOCK_HELD:-0}" -gt 0 ] || return 0
  NOBRAND_LIFECYCLE_LOCK_HELD=$((NOBRAND_LIFECYCLE_LOCK_HELD - 1))
  [ "${DRY_RUN:-0}" -eq 0 ] || return 0
  if [ "$NOBRAND_LIFECYCLE_LOCK_HELD" -eq 0 ]; then
    flock -u 7 2>/dev/null || true
    exec 7>&-
  fi
}

nb_lifecycle_lock_release_all() {
  local rc=0
  while [ "${NOBRAND_LIFECYCLE_LOCK_HELD:-0}" -gt 0 ]; do
    if ! nb_lifecycle_lock_release; then
      rc=1
      break
    fi
  done
  return "$rc"
}

nb_lifecycle_signal_exit() {
  local signal="$1" exit_status=1
  # Never invoke the generic ERR handler or recursively re-enter this handler.
  # The durable in-progress transaction is intentionally left byte-for-byte
  # intact; interruption recovery reconciles it on the next invocation.
  trap - ERR HUP INT TERM
  case "$signal" in
    HUP) exit_status=129 ;;
    INT) exit_status=130 ;;
    TERM) exit_status=143 ;;
  esac
  nb_lifecycle_lock_release_all >/dev/null 2>&1 || true
  warn "$(t '生命周期操作被信号中断；恢复信息已保留，请重新运行以安全继续。' \
    'The lifecycle operation was interrupted; recovery metadata was preserved. Run it again to continue safely.')" \
    || true
  exit "$exit_status"
}

nb_lifecycle_signal_handlers_install() {
  trap 'nb_lifecycle_signal_exit HUP' HUP
  trap 'nb_lifecycle_signal_exit INT' INT
  trap 'nb_lifecycle_signal_exit TERM' TERM
}

nb_lifecycle_checkpoint() {
  local operation="$1" phase="$2" requested=""
  nb_lifecycle_mark_phase "$phase" || return 1
  nb_test_mode_enabled || return 0
  case "$operation" in
    install) requested="${NOBRAND_TEST_INTERRUPT_INSTALL_AT:-}" ;;
    repair) requested="${NOBRAND_TEST_INTERRUPT_REPAIR_AT:-}" ;;
    uninstall) requested="${NOBRAND_TEST_INTERRUPT_UNINSTALL_AT:-}" ;;
    *) return 1 ;;
  esac
  [ "$requested" != "$phase" ] || return 75
}

nb_classify_installation_state() {
  local operation manager_version="" canonical_manager_version="" command_version="" root
  local lifecycle_valid=0 schema_valid=0 current_evidence=0 backup_restore_valid=0
  local command_path expected_target
  if { [ -e "$NOBRAND_LIFECYCLE_TX_FILE" ] || [ -L "$NOBRAND_LIFECYCLE_TX_FILE" ]; } \
     && ! nb_lifecycle_tx_valid; then
    printf 'AMBIGUOUS_OR_FOREIGN'
    return 0
  fi
  if declare -F nobrand_backup_restore_transaction_present >/dev/null 2>&1 \
     && nobrand_backup_restore_transaction_present; then
    if ! nobrand_backup_restore_transaction_valid; then
      printf 'AMBIGUOUS_OR_FOREIGN'
      return 0
    fi
    backup_restore_valid=1
  fi
  for root in "$NOBRAND_STATE_DIR" "$NOBRAND_CONFIG_DIR" "$NOBRAND_LIB_DIR"; do
    if { [ -e "$root" ] || [ -L "$root" ]; } \
       && { [ ! -d "$root" ] || [ -L "$root" ]; }; then
      printf 'AMBIGUOUS_OR_FOREIGN'
      return 0
    fi
    if [ -d "$root" ] && ! nb_test_mode_enabled && ! secure_stat_path "$root" dir; then
      printf 'AMBIGUOUS_OR_FOREIGN'
      return 0
    fi
  done
  if { [ -e "$NOBRAND_REGISTRY_FILE" ] || [ -L "$NOBRAND_REGISTRY_FILE" ]; } \
     && ! nb_schema_v3_file_valid; then
    printf 'AMBIGUOUS_OR_FOREIGN'
    return 0
  fi
  if nb_lifecycle_tx_valid; then
    lifecycle_valid=1
    current_evidence=1
  fi
  if nb_schema_v3_file_valid; then
    schema_valid=1
    current_evidence=1
  fi
  canonical_manager_version="$(nb_installed_manager_version 2>/dev/null || true)"
  if { [ -e "$NOBRAND_INSTALL_SCRIPT_PATH" ] || [ -L "$NOBRAND_INSTALL_SCRIPT_PATH" ]; } \
     && [ -z "$canonical_manager_version" ]; then
    printf 'AMBIGUOUS_OR_FOREIGN'
    return 0
  fi
  if [ -n "$canonical_manager_version" ]; then
    manager_version="$canonical_manager_version"
    current_evidence=1
  fi
  for command_path in "$NOBRAND_COMMAND_PATH" "$NOBRAND_SHORT_COMMAND_PATH"; do
    [ "$command_path" = "$NOBRAND_COMMAND_PATH" ] \
      && expected_target="$NOBRAND_INSTALL_SCRIPT_PATH" \
      || expected_target="$NOBRAND_COMMAND_PATH"
    if [ -e "$command_path" ] || [ -L "$command_path" ]; then
      command_version="$(nb_command_manager_version "$command_path" "$expected_target" 2>/dev/null)" || {
        printf 'AMBIGUOUS_OR_FOREIGN'
        return 0
      }
      if [ -n "$manager_version" ] && [ "$manager_version" != "$command_version" ]; then
        printf 'AMBIGUOUS_OR_FOREIGN'
        return 0
      fi
      manager_version="$command_version"
      current_evidence=1
    fi
  done
  if [ "$lifecycle_valid" -eq 1 ]; then
    case "$manager_version" in
      ''|3.2.*) ;;
      3.0.*|3.1.*)
        [ "$schema_valid" -eq 1 ] \
          && [ "$(nb_lifecycle_field STATUS)" = in-progress ] \
          && [ "$(nb_lifecycle_field OPERATION)" = repair ] \
          || { printf 'AMBIGUOUS_OR_FOREIGN'; return 0; }
        ;;
      *) printf 'AMBIGUOUS_OR_FOREIGN'; return 0 ;;
    esac
  fi
  if nb_legacy_state_detected; then
    if [ "$current_evidence" -eq 1 ]; then
      printf 'AMBIGUOUS_OR_FOREIGN'
    else
      printf 'LEGACY_UNSUPPORTED'
    fi
    return 0
  fi
  if [ -d "$NOBRAND_LEGACY_MIERU_STATE_DIR" ] \
     && nb_directory_has_entries "$NOBRAND_LEGACY_MIERU_STATE_DIR"; then
    printf 'AMBIGUOUS_OR_FOREIGN'
    return 0
  fi
  if [ "$backup_restore_valid" -eq 1 ]; then
    if [ "$lifecycle_valid" -eq 1 ] \
       && [ "$(nb_lifecycle_field STATUS)" = in-progress ] \
       && [ "$(nb_lifecycle_field OPERATION)" != repair ]; then
      printf 'AMBIGUOUS_OR_FOREIGN'
    elif [ "$schema_valid" -eq 1 ] || [[ "$manager_version" == 3.2.* ]]; then
      printf 'CURRENT_PARTIAL_REPAIR'
    else
      printf 'AMBIGUOUS_OR_FOREIGN'
    fi
    return 0
  fi
  if [ "$lifecycle_valid" -eq 1 ] && [ "$(nb_lifecycle_field STATUS)" = in-progress ]; then
    operation="$(nb_lifecycle_field OPERATION)"
    case "$operation" in
      install) printf 'CURRENT_PARTIAL_INSTALL' ;;
      repair) printf 'CURRENT_PARTIAL_REPAIR' ;;
      uninstall) printf 'CURRENT_PARTIAL_UNINSTALL' ;;
    esac
    return 0
  fi
  if [ "$lifecycle_valid" -eq 1 ] && [ "$(nb_lifecycle_field STATUS)" = complete ] \
     && [ "$schema_valid" -ne 1 ] && [ -z "$manager_version" ]; then
    # A completed transaction is positive current evidence, not proof of a
    # pristine host. With neither schema nor manager identity to reconcile, the
    # completion record is inconsistent and must fail closed. A surviving valid
    # schema can still take the ordinary safe partial-install repair path below.
    printf 'AMBIGUOUS_OR_FOREIGN'
    return 0
  fi
  if [ "$schema_valid" -eq 1 ]; then
    case "$manager_version" in
      3.0.*|3.1.*) printf 'LEGACY_SUPPORTED' ;;
      3.2.*)
        if [ -n "$canonical_manager_version" ]; then
          printf 'CURRENT_COMPLETE'
        else
          printf 'CURRENT_PARTIAL_INSTALL'
        fi
        ;;
      '') printf 'CURRENT_PARTIAL_INSTALL' ;;
      *) printf 'AMBIGUOUS_OR_FOREIGN' ;;
    esac
    return 0
  fi
  if [[ "$manager_version" == 3.2.* ]] \
     && [ -d "$NOBRAND_STATE_DIR" ] && nb_directory_empty "$NOBRAND_STATE_DIR"; then
    # Public v3.2.0 removed this root's contents before an unguarded scan of a
    # possibly absent config root. The still-installed compatible 3.2 manager
    # is positive current identity even after the installer advances to 3.2.1.
    printf 'CURRENT_PARTIAL_UNINSTALL'
    return 0
  fi
  if [ -d "$NOBRAND_STATE_DIR" ] && nb_directory_has_entries "$NOBRAND_STATE_DIR"; then
    printf 'AMBIGUOUS_OR_FOREIGN'
    return 0
  fi
  for root in "$NOBRAND_CONFIG_DIR" "$NOBRAND_LIB_DIR"; do
    if [ -d "$root" ] && nb_directory_has_entries "$root"; then
      printf 'AMBIGUOUS_OR_FOREIGN'
      return 0
    fi
  done
  case "$manager_version" in
    '') printf 'CLEAN' ;;
    *) printf 'AMBIGUOUS_OR_FOREIGN' ;;
  esac
}

nb_fail_legacy_state() {
  local detected
  detected="$(nb_legacy_signature_version 2>/dev/null || printf unknown)"
  die "$(t \
    "检测到无法安全自动迁移的旧版 NoBrand 数据。检测版本: ${detected}；当前安装器: ${SCRIPT_VERSION}。为避免覆盖现有节点、密钥和凭据，安装已停止。请先备份并按升级/迁移说明处理。" \
    "Unsupported legacy NoBrand data was detected (${detected}); installer ${SCRIPT_VERSION} stopped to avoid overwriting nodes, keys, or credentials. Back it up and follow the migration guidance.")" || return 1
}

nb_fail_ambiguous_state() {
  die "$(t \
    '检测到无法确认归属的已有安装数据。为避免覆盖现有配置，本次操作已停止。' \
    'Existing installation data has ambiguous ownership; this operation stopped to avoid overwriting it.')" || return 1
}

nb_install_state_notice() {
  case "${1:-$NOBRAND_INSTALL_STATE}" in
    CURRENT_COMPLETE)
      t '[提示] 检测到已安装的 NoBrand-OneClick。将检查当前安装并修复缺失组件。' \
        '[Info] NoBrand-OneClick is installed. The current installation will be checked and missing components repaired.'
      ;;
    CURRENT_PARTIAL_INSTALL)
      t '[提示] 检测到未完成的 NoBrand-OneClick 安装。将检查现有状态并继续安全修复；不会主动删除现有节点、凭据或入口配置。' \
        '[Info] An incomplete NoBrand-OneClick installation was detected. Existing state will be reconciled without deleting nodes, credentials, or ingress configuration.'
      ;;
    CURRENT_PARTIAL_REPAIR)
      t '[提示] 检测到上一次修复未完成，将根据当前状态继续检查和修复。' \
        '[Info] The previous repair was interrupted; checks and repair will continue from actual current state.'
      ;;
    CURRENT_PARTIAL_UNINSTALL)
      t '[提示] 检测到上一次 NoBrand-OneClick 卸载未完成。可重新运行安装器安全修复，或再次选择完整卸载继续清理剩余的 NoBrand 管理资源。' \
        '[Info] The previous NoBrand-OneClick uninstall was interrupted. Re-run the installer to repair safely, or choose full uninstall again to continue cleaning managed resources.'
      ;;
    LEGACY_SUPPORTED)
      t '[提示] 检测到兼容的 NoBrand 3.0/3.1 schema-v3 状态，将按当前安装器执行安全检查。' \
        '[Info] Compatible NoBrand 3.0/3.1 schema-v3 state was detected and will be checked safely by the current installer.'
      ;;
  esac
}

nb_validate_authoritative_state_boundary() {
  NOBRAND_INSTALL_STATE="$(nb_classify_installation_state)" || return 1
  case "$NOBRAND_INSTALL_STATE" in
    LEGACY_UNSUPPORTED) nb_fail_legacy_state; return 1 ;;
    AMBIGUOUS_OR_FOREIGN) nb_fail_ambiguous_state; return 1 ;;
    CLEAN|CURRENT_COMPLETE|CURRENT_PARTIAL_INSTALL|CURRENT_PARTIAL_REPAIR|\
      CURRENT_PARTIAL_UNINSTALL|LEGACY_SUPPORTED) return 0 ;;
    *) nb_fail_ambiguous_state; return 1 ;;
  esac
}

nb_write_schema_v3_file() {
  local tmp
  tmp="$(mktemp "${NOBRAND_REGISTRY_FILE}.tmp.XXXXXX")" || return 1
  if ! printf '%s\n' \
      "{\"schema_version\":${NOBRAND_SCHEMA_VERSION},\"project\":\"NoBrand-OneClick\",\"ownership\":\"nobrand-v3\",\"author\":\"ike\"}" \
      >"$tmp" \
    || ! chmod 0600 "$tmp" \
    || ! mv -f "$tmp" "$NOBRAND_REGISTRY_FILE"; then
    rm -f "$tmp"
    return 1
  fi
}

ensure_manager_state_layout() {
  local create="${1:-0}" install_state
  [ "${DRY_RUN:-0}" -eq 1 ] && return 0
  install_state="$(nb_classify_installation_state)" || return 1
  case "$install_state" in
    LEGACY_UNSUPPORTED) nb_fail_legacy_state; return 1 ;;
    AMBIGUOUS_OR_FOREIGN) nb_fail_ambiguous_state; return 1 ;;
  esac

  if [ "$create" -eq 1 ] && ! nb_schema_v3_file_valid; then
    mkdir -p "$NOBRAND_STATE_DIR" || return 1
    chmod 0700 "$NOBRAND_STATE_DIR" || return 1
    chown root:root "$NOBRAND_STATE_DIR" 2>/dev/null || true
    nb_write_schema_v3_file || return 1
  elif ! nb_schema_v3_file_valid; then
    return 0
  fi

  mkdir -p "$MITA_MANAGER_STATE_DIR" "$MITA_USERS_BACKUP_DIR" \
    "$NOBRAND_BACKUP_DIR" "$NOBRAND_LOCK_DIR" || return 1
  chmod 0700 "$MITA_MANAGER_STATE_DIR" "$MITA_USERS_BACKUP_DIR" \
    "$NOBRAND_BACKUP_DIR" "$NOBRAND_LOCK_DIR" || return 1
  chown root:root "$MITA_MANAGER_STATE_DIR" "$MITA_USERS_BACKUP_DIR" \
    "$NOBRAND_BACKUP_DIR" "$NOBRAND_LOCK_DIR" 2>/dev/null || true
  chmod 0600 "$NOBRAND_REGISTRY_FILE" 2>/dev/null || return 1
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

/var/log/nobrand-mieru-*.log /var/log/nobrand-mieru-*.err {
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
  if { flock --help 2>&1 || true; } | grep -q -- '-w' \
     && flock -w 120 8; then
    _ADMIN_LOCK_HELD=1
    return 0
  elif ! { flock --help 2>&1 || true; } | grep -q -- '-w' \
       && command -v timeout >/dev/null 2>&1 \
       && timeout 120 flock 8; then
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
    t "[演练] 保存安装状态: $MITA_STATE" "[dry-run] save install state: $MITA_STATE"
    return 0
  fi
  run mkdir -p "$(dirname "$MITA_STATE")"
  state_tmp="$(mktemp "${MITA_STATE}.XXXXXX" 2>/dev/null || mktemp_file .state)"
  if ! {
    _state_kv SCHEMA_VERSION "$NOBRAND_SCHEMA_VERSION"
    _state_kv OWNERSHIP "nobrand-v3"
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
    printf 'INSTALL_METHOD=nobrand-v3\n'
  } >"$state_tmp"; then
    rm -f "$state_tmp"
    return 1
  fi
  if [ "$DRY_RUN" -eq 1 ]; then
    t "[演练] chmod 0600 ${state_tmp}" "[dry-run] chmod 0600 ${state_tmp}"
    t "[演练] mv -f ${state_tmp} ${MITA_STATE}" "[dry-run] mv -f ${state_tmp} ${MITA_STATE}"
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

mita_v3_install_state_valid() {
  local key
  [ -f "$MITA_STATE" ] || return 1
  grep -qx 'SCHEMA_VERSION=3' "$MITA_STATE" 2>/dev/null || return 1
  grep -qx 'OWNERSHIP=nobrand-v3' "$MITA_STATE" 2>/dev/null || return 1
  grep -qx 'INSTALL_METHOD=nobrand-v3' "$MITA_STATE" 2>/dev/null || return 1
  for key in PORT PORT_RANGE PROTOCOL PROFILE ADVERTISE_HOST ADVERTISE_PORT MTU MTU_POLICY \
    USERNAME PASSWORD TRAFFIC_PATTERN TRAFFIC_SEED LOW_ENTROPY_MODE MULTIPLEXING \
    HANDSHAKE_MODE MIERU_CHANNEL MIERU_VERSION INSTALL_SCRIPT; do
    grep -q "^${key}=" "$MITA_STATE" 2>/dev/null || return 1
  done
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
  local pm="${1:-}" path
  installed_by_oneclick && return 0
  run mkdir -p "$MITA_MANAGER_STATE_DIR"
  mita_package_is_installed "$pm" && run touch "$MITA_PRESERVE_PACKAGE_MARKER"
  _has_user mita && run touch "$MITA_PRESERVE_USER_MARKER"
  _has_group mita && run touch "$MITA_PRESERVE_GROUP_MARKER"
  for path in /etc/mita /var/lib/mita /run/mita /var/run/mita /usr/bin/mita \
    /etc/systemd/system/mita.service /lib/systemd/system/mita.service \
    /usr/lib/systemd/system/mita.service /etc/init.d/mita; do
    if [ -e "$path" ] || [ -L "$path" ]; then
      run touch "$MITA_PRESERVE_SHARED_MARKER"
      break
    fi
  done
  run chmod 0600 "$MITA_PRESERVE_PACKAGE_MARKER" "$MITA_PRESERVE_USER_MARKER" \
    "$MITA_PRESERVE_GROUP_MARKER" "$MITA_PRESERVE_SHARED_MARKER" 2>/dev/null || true
}

preexisting_mita_resources_recorded() {
  [ -f "$MITA_PRESERVE_PACKAGE_MARKER" ] \
    || [ -f "$MITA_PRESERVE_USER_MARKER" ] \
    || [ -f "$MITA_PRESERVE_GROUP_MARKER" ] \
    || [ -f "$MITA_PRESERVE_SHARED_MARKER" ]
}

load_install_state() {
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
  mita_v3_install_state_valid || {
    warn "$(t "拒绝读取非 schema v3 的 Mieru 状态: ${MITA_STATE}" \
      "Refusing to read non-schema-v3 Mieru state: ${MITA_STATE}")"
    return 1
  }
  local _cli_tp="$TRAFFIC_PATTERN"
  local _cli_le="$LOW_ENTROPY_MODE"
  local _cli_mux="$MULTIPLEXING"
  local _cli_hs="$HANDSHAKE_MODE"
  # shellcheck disable=SC1090
  source "$MITA_STATE" 2>/dev/null || true
  PROFILE="$(normalize_profile "${PROFILE:-custom}" 2>/dev/null || printf 'custom')"
  MIERU_CHANNEL="$(normalize_mieru_channel "${MIERU_CHANNEL:-stable}" 2>/dev/null || printf 'stable')"
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
