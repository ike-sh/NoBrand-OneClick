# shellcheck shell=bash
# ---------- One NoBrand-owned Splicore artifact, daemon and transaction ----------
# nb_splicore_python is embedded by scripts/build.sh from runtime/splicore.py.
nb_splicore_legacy_notice() {
  cat >&2 <<'NOBRAND_LEGACY_NOTICE'
Legacy NoBrand multi-core installation detected.
Automatic in-place migration is not supported by this version.
No changes were made.

Recommended:
1. Back up current client information.
2. Remove the legacy installation using the matching legacy NoBrand version.
3. Perform a clean installation.
4. Import/use the newly generated client profiles.
NOBRAND_LEGACY_NOTICE
}

nb_splicore_json_marker() {
  [ -f "$1" ] && command -v python3 >/dev/null 2>&1 || return 1
  python3 - "$1" "$2" "$3" <<'NOBRAND_MARKER_PY'
import json, sys
try:
    with open(sys.argv[1], encoding="utf-8") as stream:
        data = json.load(stream)
    valid = isinstance(data, dict) and data.get(sys.argv[2]) == sys.argv[3]
except (OSError, ValueError):
    valid = False
sys.exit(0 if valid else 1)
NOBRAND_MARKER_PY
}

nb_splicore_legacy_preflight() {
  # Read only, dependency free, and before locks, packages, recovery or bootstrap.
  local path registry="${NOBRAND_STATE_DIR}/state.json" system="${NOBRAND_SYSTEM_ROOT:-}"
  local -a owned_paths=(
    "${NOBRAND_STATE_DIR}/mieru/install-state.env" "${NOBRAND_STATE_DIR}/mieru/users.json"
    "${NOBRAND_STATE_DIR}/mieru/.installed" "${NOBRAND_STATE_DIR}/hysteria2/state.json"
    "${NOBRAND_STATE_DIR}/tuic/runtime.json" "${NOBRAND_STATE_DIR}/snell/instances"
    "${NOBRAND_STATE_DIR}/tuic/instances" "${NOBRAND_STATE_DIR}/vless-reality/instances"
    "${NOBRAND_CONFIG_DIR}/hysteria2/config.json" "${NOBRAND_CONFIG_DIR}/vless-reality/instances"
    "${NOBRAND_LIB_DIR}/bin/mita" "${NOBRAND_LIB_DIR}/bin/sing-box"
    "${NOBRAND_LIB_DIR}/bin/hysteria" "${NOBRAND_LIB_DIR}/mieru-instance-run"
    "${NOBRAND_LEGACY_MIERU_STATE_DIR}"
    "${MITA_INSTANCE_SYSTEMD_TEMPLATE}" "${NOBRAND_SNELL_SYSTEMD_TEMPLATE}"
    "${NOBRAND_TUIC_SYSTEMD_TEMPLATE}" "${NOBRAND_REALITY_SYSTEMD_TEMPLATE}"
    "${NOBRAND_HY2_SYSTEMD_SERVICE}" "${NOBRAND_HY2_OPENRC_SERVICE}"
  )
  for path in "${owned_paths[@]}" \
    "${system}"/etc/systemd/system/nobrand-mieru*.service "${system}"/etc/systemd/system/nobrand-mieru*.timer \
    "${system}"/etc/systemd/system/nobrand-snell@*.service "${system}"/etc/systemd/system/nobrand-tuic@*.service \
    "${system}"/etc/systemd/system/nobrand-vless-reality@*.service \
    "${system}"/etc/init.d/nobrand-mieru-* "${system}"/etc/init.d/nobrand-snell-* \
    "${system}"/etc/init.d/nobrand-tuic-* "${system}"/etc/init.d/nobrand-vless-reality-*; do
    case "$path" in /etc/*|/var/lib/mita-oneclick) path="${system}${path}" ;; esac
    if [ -e "$path" ] || [ -L "$path" ]; then
      nb_splicore_legacy_notice
      return 1
    fi
  done
  # The shared Xray binary is also owned by the existing Sudoku exception.
  if { [ -e "$NOBRAND_XRAY_BIN" ] || [ -L "$NOBRAND_XRAY_BIN" ]; } \
     && [ ! -f "$NOBRAND_VLESS_STATE_FILE" ]; then
    nb_splicore_legacy_notice
    return 1
  fi
  if [ -e "$registry" ] || [ -L "$registry" ]; then
    if [ -L "$registry" ] || ! nb_splicore_json_marker "$registry" architecture splicore-native; then
      nb_splicore_legacy_notice
      return 1
    fi
  fi
  path="${NOBRAND_STATE_DIR}/splicore/current"
  if [ -e "$path" ] || [ -L "$path" ]; then
    if [ -L "$path" ]; then
      nb_splicore_json_marker "$path/desired.json" architecture splicore-native || { nb_splicore_legacy_notice; return 1; }
    else
      nb_splicore_json_marker "$path" owner nobrand-splicore-pointer-v1 || { nb_splicore_legacy_notice; return 1; }
    fi
  fi
}

nb_splicore_call() (
  export NOBRAND_STATE_DIR NOBRAND_CONFIG_DIR NOBRAND_LIB_DIR NOBRAND_LIFECYCLE_DIR
  export NOBRAND_LIFECYCLE_LOCK_FILE
  export PORT ADVERTISE_HOST ADVERTISE_PORT USERNAME PASSWORD PROTOCOL MTU
  export MULTIPLEXING HANDSHAKE_MODE TRAFFIC_PATTERN LOW_ENTROPY_MODE
  export USER_QUOTA_MB USER_EXPIRE USER_BANDWIDTH_MBPS USER_PACKAGE
  export PROFILE PROFILE_CLI MTU_CLI MULTIPLEXING_CLI HANDSHAKE_CLI TRAFFIC_CLI LOW_ENTROPY_CLI
  export PROTOCOL_CLI PORT_CLI PASSWORD_CLI ADVERTISE_CLI
  export SNELL_VERSION SNELL_PSK SNELL_QUIC_PROXY TUIC_SNI TUIC_USER HY2_SNI SCRIPT_VERSION
  export VLESS_REALITY_TARGET VLESS_REALITY_TARGET_PORT NOBRAND_SPLICORE_LISTEN NOBRAND_SPLICORE_INGRESS_ID
  NOBRAND_SPLICORE_MANAGER_SOURCE="$(nobrand_manager_source_path 2>/dev/null || true)"
  export NOBRAND_SPLICORE_MANAGER_SOURCE
  command -v python3 >/dev/null 2>&1 || {
    printf '[错误] Splicore 管理需要 python3；请安装项目公共依赖。\n' >&2
    return 1
  }
  nb_splicore_python "$@"
)

nb_splicore_installed() {
  [ -L "${NOBRAND_STATE_DIR}/splicore/current" ] \
    && [ -f "${NOBRAND_STATE_DIR}/splicore/current/desired.json" ] \
    && LC_ALL=C grep -Eq '"architecture"[[:space:]]*:[[:space:]]*"splicore-native"' \
      "${NOBRAND_STATE_DIR}/splicore/current/desired.json"
}

nb_splicore_protocol() {
  nb_splicore_legacy_preflight || return 1
  local protocol="$1" operation="$2" selector="${3:-}"
  local -a runtime_options=()
  if nobrand_ssh_confirmation_pending; then
    nobrand_pending_ssh_confirmation_notice
    return 1
  fi
  if [ "$protocol" = mieru ]; then
    apply_requested_profile_preserving_cli || return 1
    case "${MTU_REQUEST:-}" in
      '') ;;
      safe) MTU=1400 ;;
      auto) printf '[错误] 请先确定 MTU，使用 1280-1500 的显式值。\n' >&2; return 1 ;;
      *) valid_mtu "$MTU_REQUEST" || return 1; MTU="$MTU_REQUEST" ;;
    esac
  fi
  if [ "$operation" = set-endpoint ] || [ "$operation" = user-set-endpoint ]; then
    if [ "${ADVERTISE_CLI:-0}" -eq 0 ] && [ "${YES:-0}" -ne 1 ]; then
      nb_collect_advertise_endpoint_interactive "$protocol" "${NOBRAND_SPLICORE_MENU_PORT:-443}" || return 1
    fi
  fi
  if [ "$operation" = install ] || { [ "$protocol" = mieru ] && [ "$operation" = user-add ]; }; then
    if [ "${DRY_RUN:-0}" -ne 1 ]; then
      require_root || return 1
      if ! command -v python3 >/dev/null 2>&1 || ! command -v openssl >/dev/null 2>&1 \
         || ! command -v jq >/dev/null 2>&1 || ! command -v curl >/dev/null 2>&1; then
        nobrand_prepare_common || return 1
      fi
    fi
    if [ "$protocol" = mieru ]; then
      [ "${MIERU_CHANNEL_CLI:-0}" -eq 0 ] || {
        printf '[错误] 独立 Mita 版本选项不适用于固定的 Splicore；请使用 runtime --version。\n' >&2
        return 1
      }
    fi
    if [ "$protocol" = tuic ] && { [ "${TUIC_CHANNEL:-stable}" != stable ] || [ -n "${TUIC_VERSION:-}" ]; }; then
      printf '[错误] 独立 sing-box 版本选项不适用于固定的 Splicore。\n' >&2
      return 1
    fi
    if [ "${DRY_RUN:-0}" -ne 1 ]; then
      nb_prepare_ingress_request || return 1
      nb_prepare_ingress_deployment "$INGRESS_PROFILE_ID" native-bind || return 1
      NOBRAND_SPLICORE_INGRESS_ID="$INGRESS_PROFILE_ID"
      NOBRAND_SPLICORE_LISTEN="$INGRESS_LISTEN_HOST"
      export NOBRAND_SPLICORE_LISTEN
    fi
    if [ "${YES:-0}" -ne 1 ] && [ "${DRY_RUN:-0}" -ne 1 ]; then
      if [ -z "$selector" ]; then
        read_tty selector "$(t '节点名 [primary]: ' 'Node name [primary]: ')" || return 1
        selector="${selector:-primary}"
      fi
      if [ "$protocol" = mieru ] && [ "${PROFILE_CLI:-0}" -eq 0 ]; then
        choose_profile_interactive || return 1
      fi
    fi
    if [ -z "${PORT:-}" ] && [ "${DRY_RUN:-0}" -ne 1 ]; then
      case "$protocol" in snell|mieru|vless-reality) PORT="$(nb_select_available_port TCP "$INGRESS_PROFILE_ID")" ;; *) PORT="$(nb_select_available_port UDP "$INGRESS_PROFILE_ID")" ;; esac
      [ -n "$PORT" ] || return 1
    fi
    if [ -n "${PORT:-}" ]; then
      nb_valid_port "$PORT" || return 1
      if [ "${DRY_RUN:-0}" -ne 1 ]; then
        nb_ingress_port_is_reserved "$INGRESS_PROFILE_ID" "$PORT" && return 1
      fi
    fi
    if [ "${YES:-0}" -ne 1 ] && [ "${DRY_RUN:-0}" -ne 1 ] && [ "${ADVERTISE_CLI:-0}" -eq 0 ]; then
      nb_collect_advertise_endpoint_interactive "$protocol" "$PORT" || return 1
    fi
    if [ "${ADVERTISE_AUTO_REQUESTED:-0}" -eq 1 ] && [ -z "${ADVERTISE_HOST:-}" ]; then
      if [ "${DRY_RUN:-0}" -eq 1 ]; then
        NOBRAND_SPLICORE_AUTO_HOST=preview.invalid
      else
        NOBRAND_SPLICORE_AUTO_HOST="$(public_ip)" || return 1
      fi
      export NOBRAND_SPLICORE_AUTO_HOST
    fi
  fi
  [ "${DRY_RUN:-0}" -ne 1 ] || runtime_options+=(--dry-run)
  [ -z "${NOBRAND_SPLICORE_ARTIFACTS:-}" ] || runtime_options+=(--artifacts "$NOBRAND_SPLICORE_ARTIFACTS")
  nb_splicore_call protocol --protocol "$protocol" --operation "$operation" \
    --selector "$selector" "${runtime_options[@]}" || return $?
  if { [ "$operation" = install ] || [ "$operation" = user-add ]; } && [ "${DRY_RUN:-0}" -ne 1 ]; then
    nobrand_install_manager_script || return 1
  fi
}

nb_splicore_menu_select() {
  local protocol="$1" data choice="" count only_name selected_id
  nobrand_menu_selection_clear
  data="$(nb_splicore_call protocol --protocol "$protocol" --operation status)" || return 1
  printf '%s\n' "$data" | jq -r '.nodes[] | "  - \(.name) (\(.id))"'
  count="$(printf '%s\n' "$data" | jq '.nodes | length')"
  [ "$count" -gt 0 ] || { warn '尚无 Splicore 节点'; return 1; }
  only_name="$(printf '%s\n' "$data" | jq -r '.nodes[0].name')"
  read_tty choice "$(t '节点名: ' 'Node name: ')${only_name}" || return 1
  if [ -z "$choice" ]; then
    [ "$count" -eq 1 ] || return 1
    choice="$only_name"
  fi
  selected_id="$(printf '%s\n' "$data" | jq -r --arg name "$choice" '.nodes[] | select(.name==$name or .id==$name) | .id')"
  [ -n "$selected_id" ] && [[ "$selected_id" != *$'\n'* ]] || return 1
  NOBRAND_SPLICORE_MENU_PORT="$(printf '%s\n' "$data" | jq -r --arg id "$selected_id" '.nodes[] | select(.id==$id) | .listener.port')"
  export NOBRAND_SPLICORE_MENU_PORT
  nobrand_menu_selection_record splicore "$selected_id" "$choice" "${NOBRAND_STATE_DIR}/splicore/current/desired.json" || return 1
  case "$protocol" in snell) SNELL_NAME="$choice" ;; tuic) TUIC_NAME="$choice" ;; vless-reality) VLESS_REALITY_NAME="$choice" ;; esac
}

nb_splicore_route_main() {
  # Consumed by main after this function returns.
  # shellcheck disable=SC2034
  NOBRAND_SPLICORE_HANDLED=1
  case "${ACTION:-}" in
    nobrand-runtime) nb_splicore_call "${NOBRAND_RUNTIME_ARGS[@]}" ;;
    nobrand-snell)
      [[ "${SNELL_ACTION:-menu}" != menu && "${SNELL_ACTION:-menu}" != help ]] || { NOBRAND_SPLICORE_HANDLED=0; return 0; }
      nb_splicore_protocol snell "$SNELL_ACTION" "${SNELL_NAME:-}"
      ;;
    nobrand-tuic)
      [[ "${TUIC_ACTION:-menu}" != menu && "${TUIC_ACTION:-menu}" != help ]] || { NOBRAND_SPLICORE_HANDLED=0; return 0; }
      nb_splicore_protocol tuic "${TUIC_ACTION:-status}" "${TUIC_NAME:-}"
      ;;
    nobrand-hy2)
      [[ "${HY2_ACTION:-menu}" != menu && "${HY2_ACTION:-menu}" != help ]] || { NOBRAND_SPLICORE_HANDLED=0; return 0; }
      nb_splicore_protocol hysteria2 "$HY2_ACTION" hy2
      ;;
    nobrand-vless-reality)
      [[ "${VLESS_REALITY_ACTION:-menu}" != menu && "${VLESS_REALITY_ACTION:-menu}" != help ]] || { NOBRAND_SPLICORE_HANDLED=0; return 0; }
      nb_splicore_protocol vless-reality "$VLESS_REALITY_ACTION" "${VLESS_REALITY_NAME:-}"
      ;;
    install|reconfigure|upgrade|uninstall|start|stop|restart|user-add|user-del|user-show|user-list|user-enable|user-disable|user-set-endpoint|user-set-quota|user-set-expire|user-set-rate|user-scan|user-quota-reset|profile-config|traffic-config|low-entropy-config|client-modes-config|mtu-config|version-channel)
      nb_splicore_protocol mieru "$ACTION" "${USERNAME:-${USER_DEL_NAME:-${USER_SHOW_NAME:-}}}"
      ;;
    status|doctor|client-config|show)
      nb_splicore_protocol mieru "$ACTION" "${USERNAME:-${USER_SHOW_NAME:-}}"
      ;;
    user-manage) NOBRAND_SPLICORE_HANDLED=0 ;;
    user-*|rate-status|rate-restore)
      nb_splicore_protocol mieru "$ACTION" "${USERNAME:-}"
      ;;
    *) NOBRAND_SPLICORE_HANDLED=0 ;;
  esac
}
