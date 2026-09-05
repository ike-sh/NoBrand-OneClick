mieru_prepare_noninteractive_ingress_endpoint() {
  # Resolve the explicit/default Profile before enforcing the unattended
  # Display Endpoint guard.  A first-class Profile with a stable display host
  # is sufficient input; legacy-default-route still requires an explicit
  # endpoint or --advertise-auto.
  nb_prepare_ingress_request || return 1
  nb_require_explicit_endpoint_noninteractive
}

nb_authoritative_protocol_state_exists() {
  local path root
  for path in \
    "$MITA_STATE" "$MITA_USERS_STATE" \
    "$NOBRAND_HY2_STATE_FILE" "$NOBRAND_VLESS_STATE_FILE" \
    "$NOBRAND_SSH_STATE_FILE" "$NOBRAND_FORWARD_STATE_FILE"; do
    [ ! -s "$path" ] || return 0
  done
  for root in "$NOBRAND_SNELL_STATE_DIR" "$NOBRAND_REALITY_STATE_DIR" "$NOBRAND_TUIC_STATE_DIR"; do
    [ ! -d "$root" ] || ! nb_directory_has_entries "$root" || return 0
  done
  return 1
}

nb_lifecycle_validate_manager_repair() {
  local installed=""
  nb_schema_v3_file_valid || return 1
  installed="$(nb_installed_manager_version 2>/dev/null || true)"
  [ "$installed" = "$SCRIPT_VERSION" ]
}

nobrand_manager_bootstrap() {
  local state operation scope="" pm rc=0
  local recovery_expected_scope="${NOBRAND_RECOVERY_EXPECTED_SCOPE:-}"
  local recovery_expected_state="${NOBRAND_RECOVERY_EXPECTED_STATE:-}"
  local recovery_expected_tx_present="${NOBRAND_RECOVERY_EXPECTED_TX_PRESENT:-0}"
  local recovery_expected_tx_status="${NOBRAND_RECOVERY_EXPECTED_TX_STATUS:-}"
  local recovery_expected_tx_id="${NOBRAND_RECOVERY_EXPECTED_TX_ID:-}"
  local recovery_expected_tx_record="${NOBRAND_RECOVERY_EXPECTED_TX_RECORD:-}"
  require_root || return 1
  require_linux || return 1
  pm="$(detect_pkg_manager)" || return 1
  ensure_management_dependencies "$pm" || return 1
  nb_lifecycle_lock_acquire || return 1
  state="$(nb_classify_installation_state)" || {
    nb_lifecycle_lock_release
    return 1
  }
  if [ -n "$recovery_expected_scope" ] && [ "$recovery_expected_scope" != manager ]; then
    nb_lifecycle_lock_release
    warn "$(t '原恢复选择不属于管理器范围；拒绝作为新的管理器安装执行。' \
      'The recovery choice is not manager-scoped; refusing to execute it as a new manager install.')"
    return 1
  fi
  if [ -z "$recovery_expected_scope" ] \
     && [ "$state" = CURRENT_COMPLETE ] \
     && nobrand_manager_installation_valid; then
    ensure_manager_state_layout 0 || {
      nb_lifecycle_lock_release
      return 1
    }
    nb_lifecycle_lock_release
    return 0
  fi
  if [ -n "$recovery_expected_scope" ]; then
    [ -n "$recovery_expected_state" ] \
      && [ "$state" = "$recovery_expected_state" ] || {
        nb_lifecycle_lock_release
        warn "$(t '原管理器恢复状态已由其它进程改变；拒绝把旧选择作为新的管理器安装执行。' \
          'The manager recovery state changed in another process; refusing to execute the stale choice as a new manager install.')"
        return 1
      }
    case "$recovery_expected_tx_present" in
      0)
        if [ -e "$NOBRAND_LIFECYCLE_TX_FILE" ] \
           || [ -L "$NOBRAND_LIFECYCLE_TX_FILE" ]; then
          nb_lifecycle_lock_release
          warn "$(t '原管理器残留恢复期间出现了新的生命周期事务；拒绝继续。' \
            'A new lifecycle transaction appeared during manager-residue recovery; refusing to continue.')"
          return 1
        fi
        case "$state" in
          CURRENT_PARTIAL_INSTALL|CURRENT_PARTIAL_REPAIR) operation=repair ;;
          *) nb_lifecycle_lock_release; return 1 ;;
        esac
        ;;
      1)
        nb_lifecycle_tx_valid \
          && [ "$(nb_lifecycle_field STATUS)" = "$recovery_expected_tx_status" ] \
          && [ "$(nb_lifecycle_field TRANSACTION_ID)" = "$recovery_expected_tx_id" ] \
          && [ "$(<"$NOBRAND_LIFECYCLE_TX_FILE")" = "$recovery_expected_tx_record" ] || {
            nb_lifecycle_lock_release
            warn "$(t '原管理器恢复事务已由其它进程改变；拒绝把旧选择作为新的管理器安装执行。' \
              'The manager recovery transaction changed in another process; refusing to execute the stale choice as a new manager install.')"
            return 1
          }
        case "$recovery_expected_tx_status" in
          in-progress)
            [ "$(nb_lifecycle_scope)" = manager ] || {
              nb_lifecycle_lock_release
              return 1
            }
            operation="$(nb_lifecycle_field OPERATION)"
            case "$operation:$state" in
              install:CURRENT_PARTIAL_INSTALL|repair:CURRENT_PARTIAL_REPAIR) ;;
              *) nb_lifecycle_lock_release; return 1 ;;
            esac
            ;;
          complete)
            case "$state" in
              CURRENT_PARTIAL_INSTALL|CURRENT_PARTIAL_REPAIR) operation=repair ;;
              *) nb_lifecycle_lock_release; return 1 ;;
            esac
            ;;
          *) nb_lifecycle_lock_release; return 1 ;;
        esac
        ;;
      *) nb_lifecycle_lock_release; return 1 ;;
    esac
  elif nb_lifecycle_tx_valid && [ "$(nb_lifecycle_field STATUS)" = in-progress ]; then
    scope="$(nb_lifecycle_scope)" || {
      nb_lifecycle_lock_release
      return 1
    }
    [ "$scope" = manager ] || {
      nb_lifecycle_lock_release
      warn "$(t "未完成的 ${scope} 操作必须先按其组件范围恢复" \
        "The unfinished ${scope} operation must be recovered within its component scope first")"
      return 1
    }
    operation="$(nb_lifecycle_field OPERATION)"
    case "$operation" in install|repair) ;; *) nb_lifecycle_lock_release; return 1 ;; esac
  else
    case "$state" in
      CLEAN) operation=install ;;
      CURRENT_COMPLETE|CURRENT_PARTIAL_INSTALL|CURRENT_PARTIAL_REPAIR|LEGACY_SUPPORTED)
        operation=repair
        ;;
      *)
        nb_lifecycle_lock_release
        return 1
        ;;
    esac
  fi
  nb_lifecycle_pre_mutation_snapshot || {
    nb_lifecycle_lock_release
    return 1
  }
  nb_lifecycle_begin "$operation" prepare 0 0 0 0 0 0 manager || {
    nb_lifecycle_pre_mutation_disarm
    nb_lifecycle_lock_release
    return 1
  }
  nb_lifecycle_mark_mutation_started || {
    rc=$?
    nb_lifecycle_restore_pre_mutation || rc=1
  }
  if [ "$rc" -eq 0 ]; then
    ensure_manager_state_layout 1 || rc=$?
  fi
  if [ "$rc" -eq 0 ]; then
    nb_lifecycle_checkpoint "$operation" state-layout 1 || rc=$?
  fi
  if [ "$rc" -eq 0 ]; then
    nobrand_install_manager_script || rc=$?
  fi
  if [ "$rc" -eq 0 ]; then
    nb_lifecycle_checkpoint "$operation" manager-ready || rc=$?
  fi
  if [ "$rc" -eq 0 ]; then
    nobrand_manager_installation_valid || rc=$?
  fi
  if [ "$rc" -eq 0 ]; then
    nb_lifecycle_checkpoint "$operation" ready-to-validate || rc=$?
  fi
  if [ "$rc" -eq 0 ]; then
    nb_lifecycle_validate_manager_repair || rc=$?
  fi
  if [ "$rc" -eq 0 ]; then
    nb_lifecycle_complete "$operation" || rc=$?
  fi
  nb_lifecycle_lock_release
  return "$rc"
}

nobrand_recover_ingress_scope() {
  local operation phase pm rc=0
  require_root || return 1
  require_linux || return 1
  pm="$(detect_pkg_manager)" || return 1
  ensure_management_dependencies "$pm" || return 1
  nb_lifecycle_lock_acquire || return 1
  nb_lifecycle_tx_valid \
    && [ "$(nb_lifecycle_field STATUS)" = in-progress ] \
    && [ "$(nb_lifecycle_scope)" = ingress ] || {
      nb_lifecycle_lock_release
      return 1
    }
  operation="$(nb_lifecycle_field OPERATION)"
  [ "$operation" = configure ] || {
    nb_lifecycle_lock_release
    return 1
  }
  if [ "$(nb_lifecycle_field FORMAT)" = nobrand-lifecycle-v2 ] \
     && [ "$(nb_lifecycle_mutation_started)" = 0 ]; then
    nb_lifecycle_clear || {
      nb_lifecycle_lock_release
      return 1
    }
    nb_lifecycle_lock_release
    t 'Ingress 操作在写入配置前中止；已清除临时恢复信息。' \
      'Ingress stopped before configuration was written; temporary recovery metadata was cleared.'
    return 0
  fi
  phase="$(nb_lifecycle_field LAST_COMPLETED_PHASE)"
  nb_lifecycle_begin configure "$phase" 0 0 0 0 0 0 ingress || {
    nb_lifecycle_lock_release
    return 1
  }
  ensure_manager_state_layout 1 || rc=$?
  if [ "$rc" -eq 0 ] && ! nobrand_manager_installation_valid; then
    warn "$(t '协议操作前的管理器安装无效；请先修复管理器，未执行协议回调。' \
      'The manager installation is invalid before the protocol action; repair the manager first. The protocol callback was not run.')"
    rc=1
  fi
  if [ "$rc" -eq 0 ] && [ -e "$NOBRAND_INGRESS_STATE_FILE" ]; then
    nb_ingress_state_valid || rc=$?
  fi
  if [ "$rc" -eq 0 ] && [ -e "$NOBRAND_INGRESS_FIREWALL_STATE_FILE" ]; then
    nb_strict_firewall_state_valid || rc=$?
  fi
  if [ "$rc" -eq 0 ] && [ "$(nb_lifecycle_mutation_started)" = 1 ]; then
    nobrand_reconcile_ingress_profiles || rc=$?
  fi
  if [ "$rc" -eq 0 ] && [ "$(nb_lifecycle_mutation_started)" = 1 ] \
     && declare -F nb_strict_firewall_restore_authoritative >/dev/null 2>&1; then
    nb_strict_firewall_restore_authoritative || rc=$?
  fi
  if [ "$rc" -eq 0 ]; then
    nb_lifecycle_checkpoint configure ready-to-validate || rc=$?
  fi
  if [ "$rc" -eq 0 ]; then
    nobrand_manager_installation_valid || rc=$?
  fi
  if [ "$rc" -eq 0 ]; then
    nb_lifecycle_complete configure || rc=$?
  fi
  nb_lifecycle_lock_release
  return "$rc"
}

nobrand_reconcile_ingress_profiles() {
  local profile_id profile_ids failed=0
  [ -e "$NOBRAND_INGRESS_STATE_FILE" ] || return 0
  nb_ingress_state_valid || return 1
  profile_ids="$(jq -r '.profiles[].profile_id' "$NOBRAND_INGRESS_STATE_FILE")" || return 1
  while IFS= read -r profile_id; do
    [ -n "$profile_id" ] || continue
    nb_ingress_apply_profile "$profile_id" || failed=1
  done <<<"$profile_ids"
  return "$failed"
}

# Emit an unambiguous record for one authoritative state path.  This manifest
# is hashed before a protocol install callback starts, allowing a later process
# to tell an untouched pre-callback state from a callback that committed state
# but died before the ordinary ready-to-validate checkpoint.
nb_lifecycle_protocol_state_manifest_record() {
  local label="$1" path="$2" size target kind
  if [ -L "$path" ]; then
    target="$(readlink -- "$path")" || return 1
    printf 'L\0%s\0%s\0' "$label" "$target"
  elif [ -f "$path" ]; then
    size="$(wc -c <"$path" | tr -d '[:space:]')" || return 1
    [[ "$size" =~ ^[0-9]+$ ]] || return 1
    printf 'F\0%s\0%s\0' "$label" "$size" || return 1
    command cat -- "$path" || return 1
    printf '\0'
  elif [ -e "$path" ]; then
    kind="$(stat -c '%F' -- "$path" 2>/dev/null || printf other)"
    printf 'O\0%s\0%s\0' "$label" "$kind"
  else
    printf 'A\0%s\0' "$label"
  fi
}

nb_lifecycle_protocol_scope_state_manifest() (
  local scope="$1" root path child name id rules
  local -a paths=() children=()
  LC_ALL=C
  export LC_ALL
  shopt -s nullglob dotglob
  printf 'nobrand-protocol-callback-baseline-v1\0%s\0' "$scope" || return 1
  case "$scope" in
    snell)
      root="$NOBRAND_SNELL_STATE_DIR"
      if [ -L "$root" ] || { [ -e "$root" ] && [ ! -d "$root" ]; }; then
        nb_lifecycle_protocol_state_manifest_record root "$root"
        return
      fi
      paths=("$root"/*)
      for path in "${paths[@]}"; do
        name="${path##*/}"
        nb_lifecycle_protocol_state_manifest_record "$name" "$path" || return 1
      done
      ;;
    hy2)
      nb_lifecycle_protocol_state_manifest_record state.json "$NOBRAND_HY2_STATE_FILE"
      ;;
    tuic|vless-reality)
      if [ "$scope" = tuic ]; then
        root="$NOBRAND_TUIC_STATE_DIR"
      else
        root="$NOBRAND_REALITY_STATE_DIR"
      fi
      if [ -L "$root" ] || { [ -e "$root" ] && [ ! -d "$root" ]; }; then
        nb_lifecycle_protocol_state_manifest_record root "$root"
        return
      fi
      paths=("$root"/*)
      for path in "${paths[@]}"; do
        name="${path##*/}"
        if [ -L "$path" ] || { [ -e "$path" ] && [ ! -d "$path" ]; }; then
          nb_lifecycle_protocol_state_manifest_record "$name" "$path" || return 1
        else
          children=("$path"/*)
          if [ "${#children[@]}" -eq 0 ]; then
            nb_lifecycle_protocol_state_manifest_record "$name" "$path" || return 1
            continue
          fi
          for child in "${children[@]}"; do
            nb_lifecycle_protocol_state_manifest_record \
              "$name/${child##*/}" "$child" || return 1
          done
        fi
      done
      ;;
    vless-sudoku)
      nb_lifecycle_protocol_state_manifest_record state.json "$NOBRAND_VLESS_STATE_FILE"
      ;;
    ssh-tunnel)
      nb_lifecycle_protocol_state_manifest_record state.json "$NOBRAND_SSH_STATE_FILE"
      ;;
    forward)
      # Creating Forward's valid empty state is preparation, not an add
      # commit. Normalize absent and empty to the same logical rule set.
      if [ ! -e "$NOBRAND_FORWARD_STATE_FILE" ] && [ ! -L "$NOBRAND_FORWARD_STATE_FILE" ]; then
        printf 'R\0[]\0'
      elif [ -f "$NOBRAND_FORWARD_STATE_FILE" ] && [ ! -L "$NOBRAND_FORWARD_STATE_FILE" ] \
           && rules="$(jq -cS '
             if .schema_version==3 and .ownership=="nobrand-v3"
                and .feature=="port-forward" and (.rules|type)=="array"
             then .rules else error("invalid Forward state") end
           ' "$NOBRAND_FORWARD_STATE_FILE" 2>/dev/null)"; then
        printf 'R\0%s\0' "$rules"
      else
        nb_lifecycle_protocol_state_manifest_record state.json "$NOBRAND_FORWARD_STATE_FILE"
      fi
      ;;
    *) return 1 ;;
  esac
)

nb_lifecycle_protocol_scope_fingerprint() {
  local scope="$1" digest
  if command -v sha256sum >/dev/null 2>&1; then
    digest="$(nb_lifecycle_protocol_scope_state_manifest "$scope" \
      | sha256sum | awk 'NR==1 { print tolower($1) }')" || return 1
  elif command -v openssl >/dev/null 2>&1; then
    digest="$(nb_lifecycle_protocol_scope_state_manifest "$scope" \
      | openssl dgst -sha256 2>/dev/null | awk 'NR==1 { print tolower($NF) }')" || return 1
  else
    return 1
  fi
  [[ "$digest" =~ ^[0-9a-f]{64}$ ]] || return 1
  printf '%s' "$digest"
}

# Structural validity is deliberately separate from the runtime doctor.  A
# changed but malformed authoritative state fails closed and is never fed back
# through a potentially duplicating install callback.  Runtime validation runs
# after the transaction advances to ready-to-validate and remains retryable.
nb_lifecycle_protocol_scope_state_valid() (
  local scope="$1" root path child name id found=0
  local -a paths=() children=()
  shopt -s nullglob dotglob
  case "$scope" in
    snell)
      root="$NOBRAND_SNELL_STATE_DIR"
      [ ! -L "$root" ] && { [ ! -e "$root" ] || [ -d "$root" ]; } || return 1
      paths=("$root"/*)
      for path in "${paths[@]}"; do
        name="${path##*/}"
        [[ "$name" =~ ^s[0-9a-f]{16}\.json$ ]] || return 1
        found=1
        id="${name%.json}"
        [ -f "$path" ] && [ ! -L "$path" ] || return 1
        snell_state_valid "$id" || return 1
      done
      [ "$found" -eq 1 ]
      ;;
    hy2)
      [ -f "$NOBRAND_HY2_STATE_FILE" ] && [ ! -L "$NOBRAND_HY2_STATE_FILE" ] \
        && hysteria2_state_exists
      ;;
    tuic|vless-reality)
      if [ "$scope" = tuic ]; then
        root="$NOBRAND_TUIC_STATE_DIR"
      else
        root="$NOBRAND_REALITY_STATE_DIR"
      fi
      [ ! -L "$root" ] && { [ ! -e "$root" ] || [ -d "$root" ]; } || return 1
      paths=("$root"/*)
      for path in "${paths[@]}"; do
        name="${path##*/}"
        if [ "$scope" = tuic ]; then
          [[ "$name" =~ ^t[0-9a-f]{16}$ ]] || return 1
        else
          [[ "$name" =~ ^r[0-9a-f]{16}$ ]] || return 1
        fi
        [ -d "$path" ] && [ ! -L "$path" ] || return 1
        children=("$path"/*)
        [ "${#children[@]}" -eq 1 ] || return 1
        child="${children[0]}"
        [ "${child##*/}" = state.json ] || return 1
        found=1
        id="$name"
        [ -f "$child" ] && [ ! -L "$child" ] || return 1
        if [ "$scope" = tuic ]; then
          tuic_state_exists "$id" || return 1
        else
          reality_state_exists "$id" || return 1
        fi
      done
      [ "$found" -eq 1 ]
      ;;
    vless-sudoku)
      [ -f "$NOBRAND_VLESS_STATE_FILE" ] && [ ! -L "$NOBRAND_VLESS_STATE_FILE" ] \
        && vless_sudoku_state_exists && vless_sudoku_state_matches
      ;;
    ssh-tunnel)
      [ -f "$NOBRAND_SSH_STATE_FILE" ] && [ ! -L "$NOBRAND_SSH_STATE_FILE" ] \
        && ssh_tunnel_state_identity_valid \
        && jq -e '
          (.users|type)=="array" and (.users|length)>0
          and .policy_applied==true
          and (.pending_operation // "")==""
          and (.pending_watchdog_token // "")==""
          and (.pending_watchdog_pid // "")==""
          and (.pending_origin_connection // "")==""
        ' "$NOBRAND_SSH_STATE_FILE" >/dev/null
      ;;
    forward)
      [ -f "$NOBRAND_FORWARD_STATE_FILE" ] && [ ! -L "$NOBRAND_FORWARD_STATE_FILE" ] \
        && forward_state_valid "$NOBRAND_FORWARD_STATE_FILE" \
        && jq -e '.rules | length > 0' "$NOBRAND_FORWARD_STATE_FILE" >/dev/null
      ;;
    *) return 1 ;;
  esac
)

nb_lifecycle_ssh_initialization_only() {
  [ -f "$NOBRAND_SSH_STATE_FILE" ] && [ ! -L "$NOBRAND_SSH_STATE_FILE" ] \
    && ssh_tunnel_state_identity_valid \
    && jq -e '
      (.users|type)=="array" and (.users|length)==0
      and .policy_applied==false
      and (.pending_operation // "")==""
      and (.pending_watchdog_token // "")==""
      and (.pending_watchdog_pid // "")==""
      and (.pending_origin_connection // "")==""
    ' "$NOBRAND_SSH_STATE_FILE" >/dev/null \
    && ssh_tunnel_policy_absent \
    && ssh_tunnel_watchdog_directory_empty_valid
}

nb_lifecycle_protocol_recovery_mode() {
  local scope="$1" phase="$2" baseline current
  if [ "$phase" = ready-to-validate ]; then
    [ "$(nb_lifecycle_mutation_started)" = 1 ] || return 1
    printf 'validate'
    return 0
  fi
  if [[ "$phase" =~ ^callback-([0-9a-f]{55})$ ]]; then
    [ "$(nb_lifecycle_mutation_started)" = 1 ] || return 1
    baseline="${BASH_REMATCH[1]}"
    current="$(nb_lifecycle_protocol_scope_fingerprint "$scope")" || return 1
    if [ "${current:0:55}" = "$baseline" ]; then
      printf 'retry'
      return 0
    fi
    if [ "$scope" = ssh-tunnel ] && nb_lifecycle_ssh_initialization_only; then
      warn "$(t \
        'SSH Tunnel 回调后的空状态不足以证明尚未创建系统账户；拒绝自动清理或重放，请保留范围信息并执行人工修复。' \
        'Empty SSH Tunnel state after the callback does not prove that no system account was created; refusing automatic cleanup or replay and retaining scoped metadata for manual repair.')"
      return 1
    fi
    if nb_lifecycle_protocol_scope_state_valid "$scope"; then
      if [ "$scope" = forward ]; then
        # Forward owns a dedicated add-recovery flow and its existing
        # committed-state behavior remains validation-only.
        printf 'validate'
      else
        printf 'validate-changed'
      fi
      return 0
    fi
    warn "$(t "${scope} 安装回调开始后权威状态已变化但无效；拒绝重放安装器，保留范围信息以便修复。" \
      "${scope} authoritative state changed after the install callback began but is invalid; refusing installer replay and retaining scoped recovery metadata.")"
    return 1
  fi
  printf 'retry'
}

nb_lifecycle_protocol_retry_authorized() {
  local scope="$1"
  [ -z "${NOBRAND_RECOVERY_EXPECTED_SCOPE:-}" ] \
    && [ "${NOBRAND_PROTOCOL_EXPLICIT_RETRY_SCOPE:-}" = "$scope" ]
}

# Rebuild only the runtime effects that are deterministically described by the
# recorded protocol state.  Recovery must never invoke an install callback: it
# has neither the original request nor authority to generate replacement
# credentials.  Structural validation intentionally precedes the admin lock
# and every mutating service/firewall action.
nb_lifecycle_reconcile_protocol_scope() {
  local scope="$1" id ids enabled port pairs failed=0
  nb_lifecycle_protocol_scope_state_valid "$scope" || return 1

  case "$scope" in
    forward)
      forward_reconcile_authoritative_state
      return $?
      ;;
    ssh-tunnel)
      # A non-empty, fully committed SSH state can be checked without replaying
      # account/key creation or rewriting administrator access. Earlier or
      # pending states fail the structural gate above and remain fail-closed.
      ssh_tunnel_watchdog_directory_empty_valid || return 1
      ssh_tunnel_group_identity_valid || return 1
      while IFS= read -r user_json; do
        [ -n "$user_json" ] || return 1
        ssh_tunnel_user_identity_valid "$user_json" \
          && ssh_tunnel_user_key_material_valid "$user_json" || return 1
      done < <(jq -c '.users[]' "$NOBRAND_SSH_STATE_FILE")
      return 0
      ;;
    snell|hy2|tuic|vless-reality|vless-sudoku) ;;
    *) return 1 ;;
  esac

  # Complete the read-only preflight for the whole scope before repairing even
  # one unit.  Enumerators are intentionally forgiving for status displays, so
  # recovery additionally requires every derived field/config it will consume.
  case "$scope" in
    snell)
      ids="$(snell_instance_ids)" || return 1
      [ -n "$ids" ] || return 1
      while IFS= read -r id; do
        [ -n "$id" ] || continue
        enabled="$(snell_state_field "$id" enabled 2>/dev/null)" || return 1
        case "$enabled" in true|false) ;; *) return 1 ;; esac
        snell_config_matches_state "$id" || return 1
        snell_firewall_pairs "$id" >/dev/null || return 1
      done <<<"$ids"
      ;;
    hy2)
      enabled="$(hysteria2_state_field enabled 2>/dev/null)" || return 1
      case "$enabled" in true|false) ;; *) return 1 ;; esac
      port="$(hysteria2_state_field listen_port 2>/dev/null)" || return 1
      [[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -ge 1 ] && [ "$port" -le 65535 ] || return 1
      nobrand_xray_test_config "$NOBRAND_HY2_CONFIG_FILE" || return 1
      ;;
    tuic)
      ids="$(tuic_instance_ids)" || return 1
      [ -n "$ids" ] || return 1
      while IFS= read -r id; do
        [ -n "$id" ] || continue
        enabled="$(tuic_state_field "$id" enabled 2>/dev/null)" || return 1
        case "$enabled" in true|false) ;; *) return 1 ;; esac
        port="$(tuic_state_field "$id" listen_port 2>/dev/null)" || return 1
        [[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -ge 1 ] && [ "$port" -le 65535 ] || return 1
        tuic_config_matches_state "$id" || return 1
      done <<<"$ids"
      ;;
    vless-reality)
      ids="$(reality_instance_ids)" || return 1
      [ -n "$ids" ] || return 1
      while IFS= read -r id; do
        [ -n "$id" ] || continue
        enabled="$(reality_state_field "$id" enabled 2>/dev/null)" || return 1
        case "$enabled" in true|false) ;; *) return 1 ;; esac
        port="$(reality_state_field "$id" listen_port 2>/dev/null)" || return 1
        [[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -ge 1 ] && [ "$port" -le 65535 ] || return 1
        reality_config_matches_state "$id" \
          && nobrand_xray_test_config "$(reality_config_file "$id")" || return 1
      done <<<"$ids"
      ;;
    vless-sudoku)
      enabled="$(vless_sudoku_state_field enabled 2>/dev/null)" || return 1
      case "$enabled" in true|false) ;; *) return 1 ;; esac
      port="$(vless_sudoku_state_field listen_port 2>/dev/null)" || return 1
      [[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -ge 1 ] && [ "$port" -le 65535 ] || return 1
      vless_sudoku_server_config_matches \
        && vless_sudoku_client_config_matches \
        && nobrand_xray_test_config "$NOBRAND_VLESS_CONFIG_FILE" || return 1
      ;;
  esac

  admin_lock_acquire || return 1
  case "$scope" in
    snell)
      ids="$(snell_instance_ids)" || failed=1
      [ -n "$ids" ] || failed=1
      [ "$failed" -ne 0 ] || snell_install_service_runtime || failed=1
      while [ "$failed" -eq 0 ] && IFS= read -r id; do
        [ -n "$id" ] || continue
        enabled="$(snell_state_field "$id" enabled 2>/dev/null)" || { failed=1; break; }
        case "$enabled" in true|false) ;; *) failed=1; break ;; esac
        snell_ensure_openrc_service "$id" || { failed=1; break; }
        if [ "$enabled" = true ]; then
          pairs="$(snell_firewall_pairs "$id")" || { failed=1; break; }
          nb_firewall_open_pairs "$pairs" >/dev/null 2>&1 \
            && snell_service_action "$id" start >/dev/null 2>&1 \
            && snell_wait_for_required_listeners "$id" 25 || failed=1
        else
          snell_service_action "$id" stop >/dev/null 2>&1 || failed=1
        fi
      done <<<"$ids"
      ;;
    hy2)
      enabled="$(hysteria2_state_field enabled 2>/dev/null)" || failed=1
      case "$enabled" in true|false) ;; *) failed=1 ;; esac
      if [ "$failed" -eq 0 ]; then
        nobrand_write_hy2_service || failed=1
      fi
      if [ "$failed" -eq 0 ] && [ "$enabled" = true ]; then
        port="$(hysteria2_state_field listen_port)" || failed=1
        [ "$failed" -ne 0 ] \
          || nobrand_xray_test_config "$NOBRAND_HY2_CONFIG_FILE" || failed=1
        [ "$failed" -ne 0 ] \
          || nb_firewall_open_pairs "UDP|${port}" >/dev/null 2>&1 || failed=1
        [ "$failed" -ne 0 ] \
          || nobrand_hy2_service_action start >/dev/null 2>&1 || failed=1
        [ "$failed" -ne 0 ] || hysteria2_running || failed=1
      elif [ "$failed" -eq 0 ]; then
        nobrand_hy2_service_action stop >/dev/null 2>&1 || failed=1
      fi
      ;;
    tuic)
      ids="$(tuic_instance_ids)" || failed=1
      [ -n "$ids" ] || failed=1
      [ "$failed" -ne 0 ] || tuic_restore_runtime >/dev/null 2>&1 || failed=1
      while [ "$failed" -eq 0 ] && IFS= read -r id; do
        [ -n "$id" ] || continue
        enabled="$(tuic_state_field "$id" enabled 2>/dev/null)" || { failed=1; break; }
        case "$enabled" in true|false) ;; *) failed=1; break ;; esac
        tuic_ensure_openrc_service "$id" \
          && tuic_validate_config "$(tuic_config_file "$id")" || { failed=1; break; }
        if [ "$enabled" = true ]; then
          port="$(tuic_state_field "$id" listen_port)" || { failed=1; break; }
          nb_firewall_open_pairs "UDP|${port}" >/dev/null 2>&1 \
            && tuic_service_action "$id" start >/dev/null 2>&1 \
            && tuic_running "$id" || failed=1
        else
          tuic_service_action "$id" stop >/dev/null 2>&1 || failed=1
        fi
      done <<<"$ids"
      ;;
    vless-reality)
      ids="$(reality_instance_ids)" || failed=1
      [ -n "$ids" ] || failed=1
      [ "$failed" -ne 0 ] || reality_install_service_runtime >/dev/null 2>&1 || failed=1
      while [ "$failed" -eq 0 ] && IFS= read -r id; do
        [ -n "$id" ] || continue
        enabled="$(reality_state_field "$id" enabled 2>/dev/null)" || { failed=1; break; }
        case "$enabled" in true|false) ;; *) failed=1; break ;; esac
        reality_ensure_openrc_service "$id" || { failed=1; break; }
        if [ "$enabled" = true ]; then
          port="$(reality_state_field "$id" listen_port)" || { failed=1; break; }
          nb_firewall_open_pairs "TCP|${port}" >/dev/null 2>&1 \
            && reality_service_action "$id" start >/dev/null 2>&1 \
            && reality_running "$id" || failed=1
        else
          reality_service_action "$id" stop >/dev/null 2>&1 || failed=1
        fi
      done <<<"$ids"
      ;;
    vless-sudoku)
      enabled="$(vless_sudoku_state_field enabled 2>/dev/null)" || failed=1
      case "$enabled" in true|false) ;; *) failed=1 ;; esac
      if [ "$failed" -eq 0 ]; then
        nobrand_write_vless_sudoku_service || failed=1
      fi
      if [ "$failed" -eq 0 ] && [ "$enabled" = true ]; then
        port="$(vless_sudoku_state_field listen_port)" || failed=1
        [ "$failed" -ne 0 ] \
          || nb_firewall_open_pairs "TCP|${port}" >/dev/null 2>&1 || failed=1
        [ "$failed" -ne 0 ] \
          || nobrand_vless_sudoku_service_action start >/dev/null 2>&1 || failed=1
        [ "$failed" -ne 0 ] || vless_sudoku_running || failed=1
      elif [ "$failed" -eq 0 ]; then
        nobrand_vless_sudoku_service_action stop >/dev/null 2>&1 || failed=1
      fi
      ;;
  esac
  admin_lock_release
  return "$failed"
}

nb_lifecycle_validate_protocol_scope() {
  local scope="$1"
  # Doctors alone are insufficient for multi-instance scopes because their
  # enumerators intentionally skip malformed entries. Validate every matching
  # authoritative state object before any recovery transaction can complete.
  nb_lifecycle_protocol_scope_state_valid "$scope" || return 1
  case "$scope" in
    snell)
      [ -n "$(snell_instance_ids 2>/dev/null)" ] && snell_doctor_all
      ;;
    hy2)
      hysteria2_state_exists && hysteria2_doctor
      ;;
    tuic)
      [ -n "$(tuic_instance_ids 2>/dev/null)" ] && tuic_doctor_all
      ;;
    vless-reality)
      [ -n "$(reality_instance_ids 2>/dev/null)" ] && reality_doctor_all
      ;;
    vless-sudoku)
      vless_sudoku_state_exists && vless_sudoku_doctor
      ;;
    ssh-tunnel)
      ssh_tunnel_state_exists && ssh_tunnel_doctor
      ;;
    forward)
      forward_state_valid "$NOBRAND_FORWARD_STATE_FILE" \
        && jq -e '.rules | length > 0' "$NOBRAND_FORWARD_STATE_FILE" >/dev/null \
        && forward_doctor
      ;;
    *) return 1 ;;
  esac
}

nb_lifecycle_run_protocol_install() {
  local scope="$1" callback="$2" rc=0 prior_phase="" begin_phase=prepare
  local recovery_mode=retry callback_phase_active=0 fingerprint="" callback_phase=""
  local recovering=0 validate_only=0 callback_rc=0 restore_errexit=0 saved_err_trap=""
  local transaction_preexisting=0 mutation_started=0 recovery_validated=0
  shift 2
  if [ "${NOBRAND_MANAGER_SESSION_ACTIVE:-0}" -ne 1 ]; then
    "$callback" "$@"
    return $?
  fi
  require_root || return 1
  require_linux || return 1
  nb_lifecycle_lock_acquire || return 1
  if [ -n "${NOBRAND_RECOVERY_EXPECTED_SCOPE:-}" ]; then
    [ "$NOBRAND_RECOVERY_EXPECTED_SCOPE" = "$scope" ] \
      && nb_lifecycle_tx_valid \
      && [ "$(nb_lifecycle_field STATUS)" = in-progress ] \
      && [ "$(nb_lifecycle_field OPERATION)" = install ] \
      && [ "$(nb_lifecycle_scope)" = "$scope" ] || {
        nb_lifecycle_lock_release
        warn "$(t '原恢复事务已由其它进程改变；拒绝把旧选择作为新的协议安装执行。' \
          'The recovery transaction changed in another process; refusing to execute the stale choice as a new protocol install.')"
        return 1
      }
  fi
  if nb_lifecycle_tx_valid \
     && [ "$(nb_lifecycle_field STATUS)" = in-progress ] \
     && [ "$(nb_lifecycle_field OPERATION)" = install ] \
     && [ "$(nb_lifecycle_scope)" = "$scope" ]; then
    recovering=1
    transaction_preexisting=1
    prior_phase="$(nb_lifecycle_field LAST_COMPLETED_PHASE)"
    begin_phase="$prior_phase"
    mutation_started="$(nb_lifecycle_mutation_started)" || {
      nb_lifecycle_lock_release
      return 1
    }
    if [ "$mutation_started" = 0 ]; then
      nb_lifecycle_clear || {
        nb_lifecycle_lock_release
        return 1
      }
      if nb_lifecycle_protocol_retry_authorized "$scope"; then
        # This invocation carries a new, explicit same-scope request. Discard
        # the stale unmutated record and execute the current request as a fresh
        # transaction now, rather than requiring a second invocation.
        recovering=0
        transaction_preexisting=0
        prior_phase=""
        begin_phase=prepare
        mutation_started=0
      else
        # No component mutation happened, so there is no request to reconstruct.
        # A no-arg recovery must never turn lost interactive choices into defaults
        # or validate an unrelated pre-existing instance as the requested install.
        nb_lifecycle_lock_release
        t "${scope} 操作在写入协议变更前中止；已清除临时恢复信息，请从管理菜单重新开始。" \
          "${scope} stopped before any protocol change; temporary recovery metadata was cleared. Start it again from the manager menu."
        return 0
      fi
    else
      recovery_mode="$(nb_lifecycle_protocol_recovery_mode "$scope" "$prior_phase")" || {
        nb_lifecycle_lock_release
        return 1
      }
      if [ "$recovery_mode" = retry ] && [ "$scope" = forward ]; then
        nb_lifecycle_lock_release
        warn "$(t \
          'Forward 权威状态未变化，但原始请求与系统前态未持久记录；自动清理或重放并不安全。恢复信息已原样保留，请人工检查后处理。' \
          'Forward authoritative state is unchanged, but the original request and system pre-state were not durably recorded; automatic cleanup or replay is unsafe. Recovery metadata was preserved exactly; inspect the host and resolve it manually.')"
        return 1
      fi
      if [ "$recovery_mode" = retry ] \
         && ! nb_lifecycle_protocol_retry_authorized "$scope"; then
        nb_lifecycle_lock_release
        warn "$(t \
          "${scope} 的原安装参数未写入恢复记录。为避免使用默认值静默重放，请显式重新执行同一组件的安装命令。" \
          "The original ${scope} install request was not stored. To avoid silently replaying defaults, explicitly run the same component install command again.")"
        return 1
      fi
      case "$recovery_mode" in validate|validate-changed) validate_only=1 ;; esac
      [[ "$prior_phase" != callback-* ]] || callback_phase_active=1
    fi
  fi
  if [ "$transaction_preexisting" -eq 0 ]; then
    nb_lifecycle_pre_mutation_snapshot || {
      nb_lifecycle_lock_release
      return 1
    }
  fi
  if [ "$transaction_preexisting" -eq 1 ] && [ "$validate_only" -eq 1 ]; then
    # Keep the durable callback/validation recovery point byte-for-byte until
    # state-driven reconciliation and its doctor both succeed.
    NOBRAND_LIFECYCLE_OPERATION=install
    NOBRAND_LIFECYCLE_SCOPE="$scope"
    NOBRAND_LIFECYCLE_ACTIVE=1
    NOBRAND_LIFECYCLE_MUTATION_STARTED="$mutation_started"
  else
    nb_lifecycle_begin install "$begin_phase" 0 0 0 0 0 0 "$scope" || {
      [ "$transaction_preexisting" -ne 0 ] || nb_lifecycle_pre_mutation_disarm
      nb_lifecycle_lock_release
      return 1
    }
  fi
  if [ "$rc" -eq 0 ] && ! nobrand_manager_installation_valid; then
    # Protocol recovery cannot repair the manager as a side effect. Besides
    # being outside this scope, such a write would destroy the pre-mutation
    # guarantee when the original protocol request is no longer available.
    warn "$(t \
      'NoBrand 管理器当前无效；请先修复管理器，再重试该协议操作。' \
      'The NoBrand manager is invalid; repair the manager before retrying this protocol action.')"
    rc=1
  fi
  if [ "$rc" -eq 0 ] && [ "$validate_only" -eq 1 ]; then
    nb_lifecycle_reconcile_protocol_scope "$scope" || {
      warn "$(t "${scope} 的 state 驱动恢复失败；保留原范围与恢复阶段以便重试。" \
        "State-driven ${scope} reconciliation failed; the original scope and recovery phase were retained for retry.")"
      rc=1
    }
  fi
  if [ "$rc" -eq 0 ] && [ "$validate_only" -eq 1 ]; then
    nb_lifecycle_validate_protocol_scope "$scope" || {
      warn "$(t "${scope} 恢复后的状态或运行时验证失败；保留范围信息以便重试。" \
        "${scope} state or runtime validation failed after recovery; scoped metadata was retained for retry.")"
      rc=1
    }
    [ "$rc" -ne 0 ] || recovery_validated=1
  fi
  if [ "$rc" -eq 0 ] && [ "$validate_only" -eq 0 ] \
     && [ "$callback_phase_active" -eq 0 ]; then
    nb_lifecycle_checkpoint install state-layout || rc=$?
  fi
  if [ "$rc" -eq 0 ] && [ "$validate_only" -eq 0 ] \
     && [ "$callback_phase_active" -eq 0 ]; then
    fingerprint="$(nb_lifecycle_protocol_scope_fingerprint "$scope")" || rc=$?
    if [ "$rc" -eq 0 ]; then
      callback_phase="callback-${fingerprint:0:55}"
      nb_lifecycle_checkpoint install "$callback_phase" || rc=$?
    fi
  fi
  if [ "$rc" -eq 0 ] && [ "$validate_only" -eq 0 ]; then
    # Calling a shell function on the left side of `||` disables errexit for
    # every command in that function. Several established installers rely on
    # the script's fail-fast mode, so run the callback in an isolated simple
    # command while temporarily suppressing only this wrapper's ERR trap.
    case "$-" in *e*) restore_errexit=1 ;; esac
    saved_err_trap="$(trap -p ERR || true)"
    trap - ERR
    set +e
    (
      set -Eeuo pipefail
      NOBRAND_LIFECYCLE_LOCK_FLOOR="${NOBRAND_LIFECYCLE_LOCK_HELD:-0}"
      NOBRAND_LIFECYCLE_PREMUTATION_ARMED="${NOBRAND_LIFECYCLE_PREMUTATION_ARMED:-0}"
      NOBRAND_LIFECYCLE_PREMUTATION_PRIOR_PRESENT="${NOBRAND_LIFECYCLE_PREMUTATION_PRIOR_PRESENT:-0}"
      NOBRAND_LIFECYCLE_PREMUTATION_PRIOR_RECORD="${NOBRAND_LIFECYCLE_PREMUTATION_PRIOR_RECORD:-}"
      NOBRAND_PROTOCOL_CALLBACK_ATTEMPT_MUTATION=0
      nb_lifecycle_signal_handlers_install
      trap 'callback_rc=$?; trap - ERR; exit "$callback_rc"' ERR
      "$callback" "$@"
      # Commit the lifecycle checkpoint in the callback process.  The parent
      # cannot observe a successful callback return before this write is
      # durable. A prior retry transaction may already carry MUTATION_STARTED,
      # so require proof that this callback attempt crossed its own boundary.
      if [ "$NOBRAND_PROTOCOL_CALLBACK_ATTEMPT_MUTATION" -eq 1 ]; then
        nb_lifecycle_checkpoint install ready-to-validate
      fi
    )
    callback_rc=$?
    [ "$restore_errexit" -eq 0 ] || set -e
    if [ -n "$saved_err_trap" ]; then
      eval "$saved_err_trap"
    else
      trap - ERR
    fi
    [ "$callback_rc" -eq 0 ] || rc="$callback_rc"
  fi
  if nb_lifecycle_tx_valid \
     && [ "$(nb_lifecycle_field STATUS)" = in-progress ] \
     && [ "$(nb_lifecycle_field OPERATION)" = install ] \
     && [ "$(nb_lifecycle_scope)" = "$scope" ] \
     && [ "$(nb_lifecycle_mutation_started)" = 1 ]; then
    nb_lifecycle_pre_mutation_disarm
  fi
  if [ "$rc" -ne 0 ] && nb_lifecycle_tx_valid \
     && [ "$(nb_lifecycle_field OPERATION)" = install ] \
     && [ "$(nb_lifecycle_scope)" = "$scope" ] \
     && [ "$(nb_lifecycle_mutation_started)" = 0 ]; then
    nb_lifecycle_restore_pre_mutation || rc=1
  fi
  if [ "$rc" -eq 0 ]; then
    if [ "$validate_only" -eq 1 ]; then
      nb_lifecycle_checkpoint install ready-to-validate || rc=$?
    elif nb_lifecycle_tx_valid && [ "$(nb_lifecycle_mutation_started)" = 0 ]; then
      # A duplicate/existing-instance callback can intentionally be a no-op.
      # It must not complete a fresh transaction against unrelated state.
      nb_lifecycle_restore_pre_mutation || rc=1
    elif ! nb_lifecycle_tx_valid \
         || [ "$(nb_lifecycle_field LAST_COMPLETED_PHASE)" != ready-to-validate ]; then
      # In a recovering callback transaction MUTATION_STARTED may belong to an
      # earlier attempt. Without this attempt's child checkpoint, keep the
      # callback fingerprint and refuse to validate or complete unrelated state.
      warn "$(t \
        "${scope} 本次安装重试未提交新的协议变更；已保留原回调恢复点，未确认现有实例。" \
        "This ${scope} install retry committed no new protocol change; the original callback recovery point was retained and existing instances were not acknowledged.")"
      rc=1
    fi
  fi
  if [ "$rc" -eq 0 ] && [ "${NOBRAND_LIFECYCLE_ACTIVE:-0}" -eq 1 ]; then
    nobrand_manager_installation_valid || rc=$?
  fi
  if [ "$rc" -eq 0 ] && [ "${NOBRAND_LIFECYCLE_ACTIVE:-0}" -eq 1 ] \
     && [ "$recovering" -eq 1 ] && [ "$recovery_validated" -eq 0 ]; then
    nb_lifecycle_validate_protocol_scope "$scope" || {
      warn "$(t "${scope} 恢复后的状态或运行时验证失败；保留范围信息以便重试。" \
        "${scope} state or runtime validation failed after recovery; scoped metadata was retained for retry.")"
      rc=1
    }
  fi
  if [ "$rc" -eq 0 ] && [ "${NOBRAND_LIFECYCLE_ACTIVE:-0}" -eq 1 ]; then
    nb_lifecycle_complete install || rc=$?
  fi
  nb_lifecycle_lock_release
  return "$rc"
}

nb_lifecycle_run_ingress_action() {
  local rc=0 lifecycle_format="" mutation_started=0
  if [ "${NOBRAND_MANAGER_SESSION_ACTIVE:-0}" -ne 1 ]; then
    nobrand_run_ingress_action_unscoped
    return $?
  fi
  nb_lifecycle_lock_acquire || return 1
  if nb_lifecycle_tx_valid \
     && [ "$(nb_lifecycle_field STATUS)" = in-progress ]; then
    if [ "$(nb_lifecycle_field OPERATION)" != configure ] \
       || [ "$(nb_lifecycle_scope)" != ingress ]; then
      nb_lifecycle_lock_release
      return 1
    fi
    lifecycle_format="$(nb_lifecycle_field FORMAT)"
    mutation_started="$(nb_lifecycle_mutation_started)" || {
      nb_lifecycle_lock_release
      return 1
    }
    if [ "$lifecycle_format" = nobrand-lifecycle-v2 ] \
       && [ "$mutation_started" = 0 ] \
       && nb_lifecycle_protocol_retry_authorized ingress; then
      nb_lifecycle_clear || {
        nb_lifecycle_lock_release
        return 1
      }
    else
      nb_lifecycle_lock_release
      warn "$(t \
        '现有 Ingress 配置事务不能由当前请求安全重放；已原样保留恢复信息。' \
        'The existing Ingress configure transaction cannot be safely replayed by this request; recovery metadata was preserved exactly.')"
      return 1
    fi
  fi
  nb_lifecycle_pre_mutation_snapshot || {
    nb_lifecycle_lock_release
    return 1
  }
  nb_lifecycle_begin configure prepare 0 0 0 0 0 0 ingress || {
    nb_lifecycle_pre_mutation_disarm
    nb_lifecycle_lock_release
    return 1
  }
  nobrand_run_ingress_action_unscoped || rc=$?
  if [ "$rc" -ne 0 ] \
     && nb_lifecycle_tx_valid \
     && [ "$(nb_lifecycle_field OPERATION)" = configure ] \
     && [ "$(nb_lifecycle_scope)" = ingress ] \
     && [ "$(nb_lifecycle_mutation_started)" = 0 ]; then
    nb_lifecycle_restore_pre_mutation || rc=1
  fi
  if [ "$rc" -eq 0 ] \
     && nb_lifecycle_tx_valid \
     && [ "$(nb_lifecycle_field OPERATION)" = configure ] \
     && [ "$(nb_lifecycle_scope)" = ingress ] \
     && [ "$(nb_lifecycle_mutation_started)" = 0 ]; then
    # A mutating Ingress action that made no durable change is a successful
    # no-op. Do not replace a prior completed lifecycle record with it.
    nb_lifecycle_restore_pre_mutation || rc=1
    nb_lifecycle_lock_release
    return "$rc"
  fi
  if [ "$rc" -eq 0 ]; then
    nb_lifecycle_checkpoint configure state-committed || rc=$?
  fi
  if [ "$rc" -eq 0 ] && [ -e "$NOBRAND_INGRESS_STATE_FILE" ]; then
    nb_ingress_state_valid || rc=$?
  fi
  if [ "$rc" -eq 0 ]; then
    nb_lifecycle_checkpoint configure ready-to-validate || rc=$?
  fi
  if [ "$rc" -eq 0 ]; then
    nb_lifecycle_complete configure || rc=$?
  fi
  nb_lifecycle_lock_release
  return "$rc"
}

nb_reconcile_partial_uninstall() {
  local ssh_pending="" ssh_policy="" ssh_token="" ssh_pid="" ssh_origin=""
  # A durable backup restore in `applying` state may have crashed between
  # clearing and copying state/config. Restore its pre-restore snapshot before
  # ordinary repair is allowed to initialize or infer any authoritative state.
  if declare -F nobrand_backup_restore_transaction_present >/dev/null 2>&1 \
     && nobrand_backup_restore_transaction_present; then
    nobrand_backup_restore_transaction_valid || {
      warn "$(t '备份恢复的持久快照或事务元数据无效；拒绝初始化新状态' \
        'The durable backup-restore snapshot or transaction metadata is invalid; refusing to initialize new state')"
      return 1
    }
    case "$(nb_lifecycle_field STATUS "$NOBRAND_BACKUP_RESTORE_META_FILE")" in
      applying|runtime-applying|rollback-roots)
        nobrand_backup_restore_recover_applying || return $?
        ;;
    esac
  fi
  ensure_manager_state_layout 1 || return 1
  nb_lifecycle_checkpoint repair partial-uninstall-state-layout || return 1
  install_self_script || return 1
  nb_lifecycle_checkpoint repair partial-uninstall-manager-ready || return 1
  if ! nb_authoritative_protocol_state_exists; then
    return 0
  fi
  # Restore only from the protocol state that survived the interrupted
  # uninstall. These routines are state-driven and do not synthesize a fresh
  # Mieru user, node, key, or credential.
  nobrand_restore_protocol_runtimes || return 1
  nb_lifecycle_checkpoint repair partial-uninstall-runtimes-reconciled || return 1
  nobrand_start_enabled_services || return 1
  nb_lifecycle_checkpoint repair partial-uninstall-services-reconciled || return 1
  if [ -e "$NOBRAND_SSH_STATE_FILE" ] || [ -L "$NOBRAND_SSH_STATE_FILE" ]; then
    ssh_tunnel_state_exists || return 1
    ssh_tunnel_state_identity_valid || return 1
    ssh_pending="$(ssh_tunnel_state_field pending_operation 2>/dev/null || true)"
    ssh_policy="$(ssh_tunnel_state_field policy_applied 2>/dev/null || true)"
    ssh_token="$(ssh_tunnel_state_field pending_watchdog_token 2>/dev/null || true)"
    ssh_pid="$(ssh_tunnel_state_field pending_watchdog_pid 2>/dev/null || true)"
    ssh_origin="$(ssh_tunnel_state_field pending_origin_connection 2>/dev/null || true)"
    if [ "$ssh_policy" = false ] && { [ -z "$ssh_pending" ] \
       || [ "$ssh_pending" = uninstall ] || [ "$ssh_pending" = unified-uninstall ]; } \
       && [ -z "$ssh_token" ] && [ -z "$ssh_pid" ] && [ -z "$ssh_origin" ]; then
      ssh_tunnel_restore_system_state || return 1
      ssh_pending="$(ssh_tunnel_state_field pending_operation 2>/dev/null || true)"
      ssh_policy="$(ssh_tunnel_state_field policy_applied 2>/dev/null || true)"
      ssh_token="$(ssh_tunnel_state_field pending_watchdog_token 2>/dev/null || true)"
      ssh_pid="$(ssh_tunnel_state_field pending_watchdog_pid 2>/dev/null || true)"
      ssh_origin="$(ssh_tunnel_state_field pending_origin_connection 2>/dev/null || true)"
    fi
    if [ "$ssh_pending" = restore ]; then
      ssh_tunnel_pending_tuple_valid "$ssh_pending" "$ssh_token" "$ssh_pid" \
        "$ssh_origin" "$ssh_policy" || return 1
      if [ "$ssh_token" = disabled ]; then
        ssh_tunnel_confirm_admin disabled || return 1
        ssh_pending="$(ssh_tunnel_state_field pending_operation 2>/dev/null || true)"
        ssh_policy="$(ssh_tunnel_state_field policy_applied 2>/dev/null || true)"
        ssh_token="$(ssh_tunnel_state_field pending_watchdog_token 2>/dev/null || true)"
        ssh_pid="$(ssh_tunnel_state_field pending_watchdog_pid 2>/dev/null || true)"
        ssh_origin="$(ssh_tunnel_state_field pending_origin_connection 2>/dev/null || true)"
      else
        ssh_tunnel_watchdog_claim_ready "$ssh_token" "$ssh_pid" || return 1
        ssh_tunnel_watchdog_prompt "$ssh_token" || return 1
        if declare -F nobrand_backup_restore_transaction_present >/dev/null 2>&1 \
           && nobrand_backup_restore_transaction_present; then
          nobrand_backup_restore_transaction_mark_ssh_pending || return 1
        fi
        nb_lifecycle_mark_phase partial-uninstall-ssh-confirmation-pending || return 1
        return 0
      fi
    fi
    [ -z "$ssh_pending" ] && [ -z "$ssh_token" ] && [ -z "$ssh_pid" ] \
      && [ -z "$ssh_origin" ] && [ "$ssh_policy" = true ] || return 1
    ssh_tunnel_cleanup_disarmed_watchdogs || return 1
  fi
  if [ -s "$MITA_STATE" ] || [ -s "$MITA_USERS_STATE" ]; then
    mita_v3_install_state_valid || return 1
    users_state_exists && [ "$(users_count)" -gt 0 ] || return 1
    verify_mita_running 1 || return 1
  fi
  nobrand_doctor || return 1
  nb_lifecycle_checkpoint repair partial-uninstall-state-validated || return 1
}

do_install_impl() {
  ensure_manager_state_layout 1
  nb_lifecycle_checkpoint "$NOBRAND_LIFECYCLE_OPERATION" state-layout || return 1

  local pm arch ver url tmp tx runtime_tx reinstall_existing=0 managed_existing=0
  pm="$(detect_pkg_manager)"
  arch="$(detect_arch)"
  ensure_management_dependencies "$pm"

  if mita_installed; then
    local cur
    cur="$(installed_version || true)"
    t "检测到已安装 mita ${cur:-未知版本}" "mita already installed (${cur:-unknown})"
    if mita_preservable_config_exists; then
      t '如需改端口/密码/协议，请选菜单「重新配置」或执行: nobrand mieru reconfigure' \
        'To change port/password/protocol, use menu Reconfigure or: nobrand mieru reconfigure'
      if ! confirm '继续重新下载安装包并保留当前用户/节点配置？[y/N]: ' \
        'Re-download the package and keep the current users/node config? [y/N]: ' n; then
        NOBRAND_INSTALL_CANCELLED=1
        return 0
      fi
      if [ "$USERNAME_CLI" -eq 1 ] || [ "$PASSWORD_CLI" -eq 1 ] \
         || [ "$PORT_CLI" -eq 1 ] || [ "$PORT_RANGE_CLI" -eq 1 ] \
         || [ "$PROTOCOL_CLI" -eq 1 ] || [ "$MTU_CLI" -eq 1 ] \
         || [ "$ADVERTISE_CLI" -eq 1 ] \
         || [ "$PROFILE_CLI" -eq 1 ] \
         || [ "$MULTIPLEXING_CLI" -eq 1 ] || [ "$HANDSHAKE_CLI" -eq 1 ] \
         || [ "$TRAFFIC_CLI" -eq 1 ] || [ "$LOW_ENTROPY_CLI" -eq 1 ]; then
        die "$(t '重装只保留当前配置；如需同时改节点参数，请使用 reconfigure' \
          'Reinstall preserves current config; use reconfigure to change node parameters')"
      fi
      reinstall_existing=1
      load_install_state
      if users_state_exists && [ "$(users_count)" -gt 0 ]; then
        managed_existing=1
        users_sync_primary_globals
      fi
    else
      warn "$(t '检测到上次安装未完成，且没有可恢复的 OneClick 状态；本次将重新生成配置并完成安装' \
        'Previous install is incomplete and has no recoverable OneClick state; configuration will be regenerated')"
      if ! confirm '继续修复并完成安装？[y/N]: ' \
        'Repair and complete the installation? [y/N]: ' n; then
        NOBRAND_INSTALL_CANCELLED=1
        return 0
      fi
    fi
  fi

  if [ "$reinstall_existing" -eq 1 ]; then
    ensure_config_noninteractive
  elif [ "$YES" -eq 1 ]; then
    mieru_prepare_noninteractive_ingress_endpoint || return 1
    ensure_config_noninteractive
  else
    collect_config_interactive
  fi
  [ -z "$PORT_RANGE" ] || die "$(t 'v2 用户专属实例不支持端口段，请改用单端口' \
    'v2 dedicated user instances do not support port ranges; use one port')"
  [ -z "$PORT" ] || PORT="$(normalize_uint "$PORT")"
  if [ "$reinstall_existing" -eq 0 ]; then
    ensure_install_port_available
  fi

  mieru_resolve_runtime "${MIERU_CHANNEL:-stable}" "${MIERU_VERSION:-}" "$pm" "$arch" \
    || die "$(t '无法解析并验证官方 Mieru release' \
      'Failed to resolve and validate the official Mieru release')"
  ver="$MIERU_RUNTIME_RESOLVED_VERSION"
  url="$MIERU_RUNTIME_RESOLVED_URL"
  tmp="$(mktemp_file)"
  download_package "$url" "$tmp" \
    "$MIERU_RUNTIME_RESOLVED_SHA256" \
    "$MIERU_RUNTIME_RESOLVED_CHECKSUM_URL"
  runtime_tx="$(mieru_runtime_snapshot)" || { rm -f "$tmp"; return 1; }
  nb_lifecycle_mark_protocol_mutation_started mieru || {
    rm -f "$tmp"
    mieru_runtime_commit "$runtime_tx" >/dev/null 2>&1 || true
    return 1
  }
  if ! ( install_package "$tmp" "$pm" ) || ! mieru_assert_runtime_version "$ver"; then
    rm -f "$tmp"
    mieru_runtime_rollback "$runtime_tx" 2>/dev/null || true
    die "$(t 'Mieru runtime 安装验证失败，已恢复原有 managed runtime' \
      'Mieru runtime installation validation failed; the previous managed runtime was restored')"
    return 1
  fi
  rm -f "$tmp"
  mieru_runtime_commit "$runtime_tx" || return 1
  MIERU_VERSION="$ver"
  nb_lifecycle_checkpoint "$NOBRAND_LIFECYCLE_OPERATION" runtime-ready || return 1

  add_op_user "$OP_USER"
  warn_traffic_unsupported
  warn_low_entropy_unsupported
  if [ "$managed_existing" -eq 1 ]; then
    install_self_script
    admin_lock_acquire || return 1
    tx="$(users_tx_snapshot)" || { admin_lock_release; return 1; }
    isolated_stop_all
    if ! apply_users_config "$tx"; then
      admin_lock_release
      die "$(t '重装后二次应用专属实例失败；用户状态已回滚' \
        'Failed to reapply dedicated instances after reinstall; user state was rolled back')"
    fi
    if ! verify_mita_running; then
      users_tx_rollback "$tx" 1
      admin_lock_release
      die "$(t '重装后二次启动专属实例失败；用户状态已回滚' \
        'Dedicated instances failed after reinstall; user state was rolled back')"
    fi
    users_sync_primary_globals
    if ! save_install_state; then
      users_tx_rollback "$tx" 1
      admin_lock_release
      die "$(t '重装后保存安装状态失败；用户状态已回滚' \
        'Failed to save install state after reinstall; user state was rolled back')"
    fi
    users_tx_commit "$tx"
    admin_lock_release
  else
    if [ "$reinstall_existing" -eq 0 ]; then
      # 下载/安装期间端口可能被其它进程抢占，落盘前再验一次。
      ensure_install_port_available
    fi
    install_fresh_isolated
  fi
  nb_lifecycle_checkpoint "$NOBRAND_LIFECYCLE_OPERATION" state-committed || return 1

  offer_bbr_fq

  print_summary
}

do_reconfigure_impl() {
  local old_bindings new_bindings close_bindings desired_bindings binding_proto binding_port tx
  local old_port old_port_range old_protocol old_mtu old_mtu_policy old_user old_password
  local old_profile old_traffic old_seed old_low_entropy old_mux old_handshake
  local old_advertise_host old_advertise_port
  local client_state_changed=0
  local requested_port="$PORT" requested_port_range="$PORT_RANGE" requested_protocol="$PROTOCOL"
  local requested_user="$USERNAME" requested_password="$PASSWORD"
  local requested_advertise_host="$ADVERTISE_HOST" requested_advertise_port="$ADVERTISE_PORT"
  local requested_profile="$PROFILE" requested_mtu_request="$MTU_REQUEST"
  local requested_traffic="$TRAFFIC_PATTERN" requested_low_entropy="$LOW_ENTROPY_MODE"
  local requested_mux="$MULTIPLEXING" requested_handshake="$HANDSHAKE_MODE"
  local requested_port_cli="${PORT_CLI:-0}" requested_port_range_cli="${PORT_RANGE_CLI:-0}"
  local requested_protocol_cli="${PROTOCOL_CLI:-0}" requested_user_cli="${USERNAME_CLI:-0}"
  local requested_password_cli="${PASSWORD_CLI:-0}" requested_advertise_cli="${ADVERTISE_CLI:-0}"
  local requested_profile_cli="${PROFILE_CLI:-0}" requested_mtu_cli="${MTU_CLI:-0}"
  local requested_traffic_cli="${TRAFFIC_CLI:-0}" requested_low_entropy_cli="${LOW_ENTROPY_CLI:-0}"
  local requested_mux_cli="${MULTIPLEXING_CLI:-0}" requested_handshake_cli="${HANDSHAKE_CLI:-0}"
  PORT_CLI=0 PORT_RANGE_CLI=0 PROTOCOL_CLI=0 USERNAME_CLI=0 PASSWORD_CLI=0
  ADVERTISE_CLI=0 PROFILE_CLI=0 MTU_CLI=0 TRAFFIC_CLI=0 LOW_ENTROPY_CLI=0
  MULTIPLEXING_CLI=0 HANDSHAKE_CLI=0
  load_install_state
  if users_state_exists && [ "$(users_count)" -gt 0 ]; then
    users_sync_primary_globals
  fi
  old_port="$PORT"; old_port_range="$PORT_RANGE"; old_protocol="$PROTOCOL"
  old_mtu="$MTU"; old_mtu_policy="$MTU_POLICY"
  old_user="$USERNAME"; old_password="$PASSWORD"
  old_advertise_host="$ADVERTISE_HOST"; old_advertise_port="$ADVERTISE_PORT"
  old_profile="$PROFILE"
  old_traffic="$TRAFFIC_PATTERN"; old_seed="$TRAFFIC_SEED"
  old_low_entropy="$LOW_ENTROPY_MODE"; old_mux="$MULTIPLEXING"; old_handshake="$HANDSHAKE_MODE"
  PORT_CLI="$requested_port_cli"; PORT_RANGE_CLI="$requested_port_range_cli"
  PROTOCOL_CLI="$requested_protocol_cli"; USERNAME_CLI="$requested_user_cli"
  PASSWORD_CLI="$requested_password_cli"; ADVERTISE_CLI="$requested_advertise_cli"
  PROFILE_CLI="$requested_profile_cli"; MTU_CLI="$requested_mtu_cli"
  TRAFFIC_CLI="$requested_traffic_cli"; LOW_ENTROPY_CLI="$requested_low_entropy_cli"
  MULTIPLEXING_CLI="$requested_mux_cli"; HANDSHAKE_CLI="$requested_handshake_cli"
  [ "$PORT_CLI" -eq 0 ] || PORT="$requested_port"
  [ "$PORT_RANGE_CLI" -eq 0 ] || PORT_RANGE="$requested_port_range"
  [ "$PROTOCOL_CLI" -eq 0 ] || PROTOCOL="$requested_protocol"
  [ "$USERNAME_CLI" -eq 0 ] || USERNAME="$requested_user"
  [ "$PASSWORD_CLI" -eq 0 ] || PASSWORD="$requested_password"
  [ "$ADVERTISE_CLI" -eq 0 ] || { ADVERTISE_HOST="$requested_advertise_host"; ADVERTISE_PORT="$requested_advertise_port"; }
  [ "$PROFILE_CLI" -eq 0 ] || PROFILE="$requested_profile"
  [ "$MTU_CLI" -eq 0 ] || MTU_REQUEST="$requested_mtu_request"
  [ "$TRAFFIC_CLI" -eq 0 ] || TRAFFIC_PATTERN="$requested_traffic"
  [ "$LOW_ENTROPY_CLI" -eq 0 ] || LOW_ENTROPY_MODE="$requested_low_entropy"
  [ "$MULTIPLEXING_CLI" -eq 0 ] || MULTIPLEXING="$requested_mux"
  [ "$HANDSHAKE_CLI" -eq 0 ] || HANDSHAKE_MODE="$requested_handshake"
  users_isolated_mode || die "$(t 'schema v3 Mieru 状态必须使用 isolated-v2' \
    'Schema-v3 Mieru state must use isolated-v2')"
  old_bindings="$(multi_user_port_protocol_pairs)"

  if [ "$YES" -eq 1 ]; then
    load_config_from_mita
    ensure_config_noninteractive
  else
    collect_reconfigure_interactive
  fi
  [ -z "$PORT_RANGE" ] || die "$(t 'v2 用户专属实例不支持端口段，请改用单端口' \
    'v2 dedicated user instances do not support port ranges; use one port')"
  [ -z "$PORT" ] || PORT="$(normalize_uint "$PORT")"
  validate_advertise_endpoint || die "$(t '自定义客户端入口参数无效' \
    'Invalid custom client entry parameters')"
  [ -z "$ADVERTISE_PORT" ] || ADVERTISE_PORT="$(normalize_uint "$ADVERTISE_PORT")"

  if [ "${PROFILE_CLI:-0}" -eq 0 ] \
     && { [ "$PROTOCOL" != "$old_protocol" ] || [ "$MTU" != "$old_mtu" ] \
       || [ "$MULTIPLEXING" != "$old_mux" ] || [ "$HANDSHAKE_MODE" != "$old_handshake" ] \
       || [ "$TRAFFIC_PATTERN" != "$old_traffic" ] || [ "$LOW_ENTROPY_MODE" != "$old_low_entropy" ]; }; then
    PROFILE=custom
  fi
  profile_reconcile_metadata

  if [ "$ADVERTISE_HOST" != "$old_advertise_host" ] \
     || [ "$ADVERTISE_PORT" != "$old_advertise_port" ] \
     || [ "$MTU_POLICY" != "$old_mtu_policy" ] \
     || [ "$MULTIPLEXING" != "$old_mux" ] \
     || [ "$HANDSHAKE_MODE" != "$old_handshake" ] \
     || [ "$PROFILE" != "$old_profile" ]; then
    client_state_changed=1
  fi

  # 展示入口、客户端握手/多路复用和 MTU 策略文本不改变服务端运行配置。
  # 这些字段单独持久化，避免无意义地重启所有专属实例。
  if [ "$PORT" = "$old_port" ] && [ "$PORT_RANGE" = "$old_port_range" ] \
     && [ "$PROTOCOL" = "$old_protocol" ] && [ "$MTU" = "$old_mtu" ] \
     && [ "$USERNAME" = "$old_user" ] && [ "$PASSWORD" = "$old_password" ] \
     && [ "$TRAFFIC_PATTERN" = "$old_traffic" ] && [ "$TRAFFIC_SEED" = "$old_seed" ] \
     && [ "$LOW_ENTROPY_MODE" = "$old_low_entropy" ]; then
    if [ "$client_state_changed" -eq 0 ]; then
      msg ""
      t '未检测到配置变化；服务未重启' \
        'No configuration changes detected; services were not restarted'
      print_summary current
      return 0
    fi
    local state_only_auto_host="" state_only_mutation_marked=0
    admin_lock_acquire || return 1
    tx="$(users_tx_snapshot)" || { admin_lock_release; return 1; }
    if [ "$ADVERTISE_HOST" != "$old_advertise_host" ] \
       || [ "$ADVERTISE_PORT" != "$old_advertise_port" ]; then
      nb_lifecycle_mark_protocol_mutation_started mieru || {
        users_tx_commit "$tx"
        admin_lock_release
        return 1
      }
      state_only_mutation_marked=1
      if ! users_set_advertise_endpoint "$old_user" "$ADVERTISE_HOST" "$ADVERTISE_PORT"; then
        users_tx_rollback "$tx" 0
        admin_lock_release
        return 1
      fi
    fi
    state_only_auto_host="$(public_ip 2>/dev/null || true)"
    if ! users_validate_state_file "$MITA_USERS_STATE" "$PROTOCOL" "$state_only_auto_host"; then
      users_tx_rollback "$tx" 0
      admin_lock_release
      die "$(t '客户端展示入口与其它用户冲突' \
        'Client display endpoint conflicts with another user')"
    fi
    users_sync_primary_globals
    if [ "$state_only_mutation_marked" -eq 0 ]; then
      nb_lifecycle_mark_protocol_mutation_started mieru || {
        users_tx_commit "$tx"
        admin_lock_release
        return 1
      }
    fi
    if ! save_install_state; then
      users_tx_rollback "$tx" 0
      admin_lock_release
      return 1
    fi
    users_tx_commit "$tx"
    admin_lock_release
    client_exports_after_reconfigure "$old_user" "$old_protocol" "$old_mtu" \
      "$old_traffic" "$old_seed" "$old_low_entropy" "$old_mux" "$old_handshake" \
      2>/dev/null || true
    msg ""
    t '仅客户端参数已更新；服务器运行配置未变化，服务未重启' \
      'Client-only settings were updated; server runtime is unchanged and services were not restarted'
    print_summary current
    return 0
  fi

  if [ -n "${PORT:-}" ]; then
    desired_bindings="$({
      multi_user_port_protocol_pairs
      port_required_bindings "$PORT"
    } | sed '/^[[:space:]]*$/d' | LC_ALL=C sort -u)"
    while IFS='|' read -r binding_proto binding_port; do
      [ -n "$binding_proto" ] && [ -n "$binding_port" ] || continue
      printf '%s\n' "$old_bindings" | grep -qxF "${binding_proto}|${binding_port}" && continue
      if port_is_listening "$binding_port" "$binding_proto"; then
        warn "$(t "新监听 ${binding_proto}/${binding_port} 已被系统其它服务占用" \
          "New listener ${binding_proto}/${binding_port} is already used by another service")"
        port_listener_details "$binding_port" "$binding_proto"
        die "$(t '重新配置已取消，请选择其它端口或协议' \
          'Reconfigure cancelled; choose another port or protocol')"
      fi
    done <<<"$desired_bindings"
  fi

  warn_traffic_unsupported
  warn_low_entropy_unsupported
  # 多用户：协议全局更新；仅当用户显式改了主用户名/密码/端口时同步「主用户」
  # 主用户 = install-state 中的 USERNAME，找不到则 users[0]
  MULTI_USER_MODE=1
  admin_lock_acquire || return 1
  tx="$(users_tx_snapshot)" || { admin_lock_release; return 1; }
  nb_lifecycle_mark_protocol_mutation_started mieru || {
    users_tx_commit "$tx"
    admin_lock_release
    return 1
  }
  _U_NAME="$USERNAME" _U_PASS="$PASSWORD" _U_PORT="$PORT" _U_PROTO="$PROTOCOL"
  _U_ADVERTISE_HOST="$ADVERTISE_HOST" _U_ADVERTISE_PORT="$ADVERTISE_PORT"
  _U_PRIMARY="${old_user}"
  users_py_locked '
import json, os, time
path = os.environ["MITA_USERS_STATE"]
d = json.load(open(path))
name = os.environ.get("_U_NAME") or ""
password = os.environ.get("_U_PASS") or ""
port = os.environ.get("_U_PORT") or ""
proto = os.environ.get("_U_PROTO") or "TCP"
advertise_host = os.environ.get("_U_ADVERTISE_HOST") or ""
advertise_port = os.environ.get("_U_ADVERTISE_PORT") or ""
primary = os.environ.get("_U_PRIMARY") or ""
users = d.get("users") or []
# 定位主用户：优先同名，否则第一个
idx = 0
for i, u in enumerate(users):
    if primary and u.get("name") == primary:
        idx = i
        break
if users:
    u = users[idx]
    old_port = int(u.get("port") or 0)
    if name and name != u.get("name"):
        # 避免与其它用户重名
        if any(x.get("name") == name for j, x in enumerate(users) if j != idx):
            raise SystemExit(2)
        u["name"] = name
    if password and not password.startswith("*"):
        u["password"] = password
    if port and str(port).isdigit():
        new_port = int(port)
        # 端口冲突则拒绝改端口（保留其它用户端口）
        if any(int(x.get("port") or 0) == new_port for j, x in enumerate(users) if j != idx):
            raise SystemExit(3)
        u["port"] = new_port
    u["advertise_host"] = advertise_host
    u["advertise_port"] = int(advertise_port) if advertise_port else ""
    u["updated_at"] = int(time.time())
d["protocol"] = proto
json.dump(d, open(path, "w"), indent=2)
' || {
    local prc=$?
    users_tx_rollback "$tx" 0
    admin_lock_release
    if [ "$prc" -eq 2 ]; then
      die "$(t '新用户名与其它用户冲突' 'New username conflicts with another user')"
    elif [ "$prc" -eq 3 ]; then
      die "$(t '新端口已被其它用户占用' 'New port already used by another user')"
    fi
    die "$(t '更新多用户状态失败' 'Failed to update multi-user state')"
  }
  if ! users_validate_state_file "$MITA_USERS_STATE" "$PROTOCOL"; then
    users_tx_rollback "$tx" 0
    admin_lock_release
    die "$(t '新协议/端口组合会造成监听端口或客户端展示入口冲突' \
      'The new protocol/port combination would collide between listeners or client display endpoints')"
  fi
  # 协议变更时所有用户 portBindings 随 PROTOCOL 重建；端口仅主用户可能变
  if ! apply_users_config "$tx"; then
    PORT="$old_port"; PORT_RANGE="$old_port_range"; PROTOCOL="$old_protocol"
    MTU="$old_mtu"; MTU_POLICY="$old_mtu_policy"; PROFILE="$old_profile"
    USERNAME="$old_user"; PASSWORD="$old_password"
    ADVERTISE_HOST="$old_advertise_host"; ADVERTISE_PORT="$old_advertise_port"
    TRAFFIC_PATTERN="$old_traffic"; TRAFFIC_SEED="$old_seed"
    LOW_ENTROPY_MODE="$old_low_entropy"; MULTIPLEXING="$old_mux"; HANDSHAKE_MODE="$old_handshake"
    reconcile_isolated_instances >/dev/null 2>&1 || true
    admin_lock_release
    return 1
  fi
  new_bindings="$(multi_user_port_protocol_pairs)"
  open_firewall_for_pairs "$new_bindings"
  if ! verify_mita_running || ! save_install_state; then
    PORT="$old_port"; PORT_RANGE="$old_port_range"; PROTOCOL="$old_protocol"
    MTU="$old_mtu"; MTU_POLICY="$old_mtu_policy"; PROFILE="$old_profile"
    USERNAME="$old_user"; PASSWORD="$old_password"
    ADVERTISE_HOST="$old_advertise_host"; ADVERTISE_PORT="$old_advertise_port"
    TRAFFIC_PATTERN="$old_traffic"; TRAFFIC_SEED="$old_seed"
    LOW_ENTROPY_MODE="$old_low_entropy"; MULTIPLEXING="$old_mux"; HANDSHAKE_MODE="$old_handshake"
    users_tx_rollback "$tx" 1
    open_firewall_for_pairs "$old_bindings"
    close_bindings="$(comm -23 \
      <(printf '%s\n' "$new_bindings" | sed '/^[[:space:]]*$/d' | LC_ALL=C sort -u) \
      <(printf '%s\n' "$old_bindings" | sed '/^[[:space:]]*$/d' | LC_ALL=C sort -u))"
    [ -z "$close_bindings" ] || close_firewall_for_bindings "$close_bindings"
    admin_lock_release
    return 1
  fi
  users_tx_commit "$tx"
  client_exports_after_reconfigure "$old_user" "$old_protocol" "$old_mtu" \
    "$old_traffic" "$old_seed" "$old_low_entropy" "$old_mux" "$old_handshake" \
    2>/dev/null || true
  close_bindings="$(comm -23 \
    <(printf '%s\n' "$old_bindings" | sed '/^[[:space:]]*$/d' | LC_ALL=C sort -u) \
    <(printf '%s\n' "$new_bindings" | sed '/^[[:space:]]*$/d' | LC_ALL=C sort -u))"
  [ -z "$close_bindings" ] || close_firewall_for_bindings "$close_bindings"
  admin_lock_release
  msg ""
  t '========== 重新配置完成 ==========' '========== Reconfigure complete =========='
  if users_state_exists && [ "$(users_count)" -gt 1 ]; then
    t '提示: 多用户模式下「重新配置」只改主用户凭据/端口与全局协议；其它用户端口不变' \
      'Note: multi-user reconfigure updates primary user + global protocol only; other ports unchanged'
  fi
  print_summary current
}

do_install() {
  local operation="" scope=mieru state manager_only=0 partial_uninstall_repair=0 lifecycle_phase="" rc=0
  local recovery_matches=0 validate_only=0 lifecycle_format="" current_mutation=0
  local allow_transition=0 transaction_preexisting=0
  NOBRAND_INSTALL_CANCELLED=0
  require_root
  require_linux
  require_cmd curl
  state="$(nb_classify_installation_state)" || return 1
  case "$state" in
    CLEAN|CURRENT_COMPLETE|CURRENT_PARTIAL_INSTALL|CURRENT_PARTIAL_REPAIR|\
      CURRENT_PARTIAL_UNINSTALL|LEGACY_SUPPORTED) ;;
    CURRENT_PARTIAL_CONFIGURE)
      warn "$(t '未完成的组件配置必须先按其记录范围恢复，拒绝启动 Mieru。' \
        'The incomplete component configuration must be recovered in its recorded scope; refusing to start Mieru.')"
      return 1
      ;;
    LEGACY_UNSUPPORTED) nb_fail_legacy_state; return 1 ;;
    *) nb_fail_ambiguous_state; return 1 ;;
  esac
  nb_lifecycle_lock_acquire || return 1
  # Reclassify while holding the process lock so no competing lifecycle can
  # change the evidence between classification and the transaction write.
  state="$(nb_classify_installation_state)" || {
    nb_lifecycle_lock_release
    return 1
  }
  if [ -n "${NOBRAND_RECOVERY_EXPECTED_SCOPE:-}" ]; then
    case "$NOBRAND_RECOVERY_EXPECTED_SCOPE" in
      mieru)
        if nb_lifecycle_tx_valid \
           && [ "$(nb_lifecycle_field STATUS)" = in-progress ] \
           && [ "$(nb_lifecycle_scope)" = mieru ]; then
          case "$(nb_lifecycle_field OPERATION)" in install|repair) recovery_matches=1 ;; esac
        fi
        ;;
      global)
        if nb_lifecycle_tx_valid \
           && [ "$(nb_lifecycle_field STATUS)" = in-progress ] \
           && [ "$(nb_lifecycle_scope)" = global ]; then
          recovery_matches=1
        elif [ "$state" = CURRENT_PARTIAL_UNINSTALL ]; then
          recovery_matches=1
        elif declare -F nobrand_backup_restore_transaction_present >/dev/null 2>&1 \
             && nobrand_backup_restore_transaction_present \
             && nobrand_backup_restore_transaction_valid; then
          recovery_matches=1
        fi
        ;;
    esac
    if [ "$recovery_matches" -ne 1 ]; then
      nb_lifecycle_lock_release
      warn "$(t '原恢复事务已由其它进程改变；拒绝把旧选择作为新的 Mieru/全局操作执行。' \
        'The recovery transaction changed in another process; refusing to execute the stale choice as a new Mieru/global operation.')"
      return 1
    fi
  fi
  case "$state" in
    CLEAN) operation=install ;;
    CURRENT_COMPLETE|LEGACY_SUPPORTED)
      if mita_v3_install_state_valid 2>/dev/null || mita_installed 2>/dev/null; then
        operation=repair
      else
        operation=install
      fi
      ;;
    CURRENT_PARTIAL_UNINSTALL)
      operation=repair
      scope=global
      ;;
    CURRENT_PARTIAL_INSTALL|CURRENT_PARTIAL_REPAIR)
      if nb_lifecycle_tx_valid && [ "$(nb_lifecycle_field STATUS)" = in-progress ]; then
        scope="$(nb_lifecycle_scope)" || {
          nb_lifecycle_lock_release
          return 1
        }
        case "$scope" in
          mieru)
            transaction_preexisting=1
            operation="$(nb_lifecycle_field OPERATION)"
            lifecycle_format="$(nb_lifecycle_field FORMAT)"
            lifecycle_phase="$(nb_lifecycle_field LAST_COMPLETED_PHASE)"
            current_mutation="$(nb_lifecycle_mutation_started)" || {
              nb_lifecycle_lock_release
              return 1
            }
            if [ "$lifecycle_format" = nobrand-lifecycle-v2 ] \
               && [ "$current_mutation" = 0 ]; then
              nb_lifecycle_clear || {
                nb_lifecycle_lock_release
                return 1
              }
              if [ -n "${NOBRAND_RECOVERY_EXPECTED_SCOPE:-}" ]; then
                nb_lifecycle_lock_release
                t 'Mieru 操作在写入协议变更前中止；已清除临时恢复信息，请从管理菜单重新开始。' \
                  'Mieru stopped before any protocol change; temporary recovery metadata was cleared. Start it again from the manager menu.'
                return 0
              fi
              [ "${NOBRAND_PROTOCOL_EXPLICIT_RETRY_SCOPE:-}" = mieru ] || {
                nb_lifecycle_lock_release
                return 1
              }
              # The current command carries a new explicit Mieru request. Run
              # it now as a fresh invocation instead of making the user retry a
              # second time after clearing stale pre-mutation metadata.
              transaction_preexisting=0
              lifecycle_format=""
              lifecycle_phase=prepare
              current_mutation=0
              if mita_v3_install_state_valid 2>/dev/null || mita_installed 2>/dev/null; then
                operation=repair
              else
                operation=install
              fi
            fi
            if [ "$lifecycle_format" = nobrand-lifecycle-v2 ]; then
              case "$lifecycle_phase" in
                state-committed|ready-to-validate) validate_only=1 ;;
                *)
                  if [ -n "${NOBRAND_RECOVERY_EXPECTED_SCOPE:-}" ]; then
                    nb_lifecycle_lock_release
                    warn "$(t \
                      '原 Mieru 请求未写入恢复记录。为避免使用默认值静默重放，请显式执行 nobrand mieru install；若原操作是重新配置，请执行 nobrand mieru reconfigure。' \
                      'The original Mieru request was not stored. To avoid silently replaying defaults, explicitly run nobrand mieru install, or nobrand mieru reconfigure if that was the original action.')"
                    return 1
                  fi
                  [ "${NOBRAND_PROTOCOL_EXPLICIT_RETRY_SCOPE:-}" = mieru ] || {
                    nb_lifecycle_lock_release
                    return 1
                  }
                  ;;
              esac
            elif [ "$lifecycle_format" = nobrand-lifecycle-v1 ]; then
              # v1 has no mutation marker or reliable install-vs-reconfigure
              # scope. Only phases that prove authoritative state was committed
              # may recover unattended; earlier phases require the operator to
              # choose install or reconfigure explicitly and recollect input.
              case "$lifecycle_phase" in
                state-committed|ready-to-validate) validate_only=1 ;;
                *)
                  if [ -n "${NOBRAND_RECOVERY_EXPECTED_SCOPE:-}" ]; then
                    nb_lifecycle_lock_release
                    warn "$(t \
                      '旧版 Mieru 恢复记录无法证明原操作或参数。请显式执行 nobrand mieru install 或 nobrand mieru reconfigure。' \
                      'The legacy Mieru recovery record cannot prove the original action or request. Explicitly run nobrand mieru install or nobrand mieru reconfigure.')"
                    return 1
                  fi
                  [ "${NOBRAND_PROTOCOL_EXPLICIT_RETRY_SCOPE:-}" = mieru ] || {
                    nb_lifecycle_lock_release
                    return 1
                  }
                  ;;
              esac
            fi
            ;;
          global) operation=repair ;;
          *)
            nb_lifecycle_lock_release
            warn "$(t "未完成的 ${scope} 操作不能由 Mieru 恢复" \
              "The unfinished ${scope} operation cannot be recovered by Mieru")"
            return 1
            ;;
        esac
      elif declare -F nobrand_backup_restore_transaction_present >/dev/null 2>&1 \
           && nobrand_backup_restore_transaction_present; then
        operation=repair
        scope=global
      else
        nb_lifecycle_lock_release
        warn "$(t '检测到缺少组件范围的管理器残留；请先运行无参数安装器修复管理器。' \
          'Manager residue without component scope was detected; run the installer without arguments to repair the manager first.')"
        return 1
      fi
      ;;
    CURRENT_PARTIAL_CONFIGURE)
      nb_lifecycle_lock_release
      return 1
      ;;
    LEGACY_UNSUPPORTED)
      nb_lifecycle_lock_release
      nb_fail_legacy_state
      return 1
      ;;
    *)
      nb_lifecycle_lock_release
      nb_fail_ambiguous_state
      return 1
      ;;
  esac
  if [ "$state" = CURRENT_PARTIAL_UNINSTALL ] || [ "$scope" = global ]; then
    partial_uninstall_repair=1
  elif [ "$state" = CURRENT_PARTIAL_REPAIR ] \
       && declare -F nobrand_backup_restore_transaction_present >/dev/null 2>&1 \
       && nobrand_backup_restore_transaction_present \
       && nobrand_backup_restore_transaction_valid; then
    partial_uninstall_repair=1
  elif [ "$state" = CURRENT_PARTIAL_REPAIR ] && nb_lifecycle_tx_valid \
       && [ "$(nb_lifecycle_field OPERATION)" = repair ]; then
    lifecycle_phase="$(nb_lifecycle_field LAST_COMPLETED_PHASE)"
    case "$lifecycle_phase" in partial-uninstall-*) partial_uninstall_repair=1 ;; esac
  fi
  if [ "$partial_uninstall_repair" -eq 1 ]; then
    lifecycle_phase='partial-uninstall-prepare'
    [ "$state" != CURRENT_PARTIAL_UNINSTALL ] || allow_transition=1
  elif [ -z "$lifecycle_phase" ]; then
    lifecycle_phase=prepare
  fi
  nb_lifecycle_pre_mutation_snapshot || {
    nb_lifecycle_lock_release
    return 1
  }
  nb_lifecycle_begin "$operation" "$lifecycle_phase" 0 0 0 0 0 "$allow_transition" "$scope" || {
    nb_lifecycle_pre_mutation_disarm
    nb_lifecycle_lock_release
    return 1
  }
  if [ "$partial_uninstall_repair" -eq 1 ]; then
    # This is a global lifecycle recovery, not a request to create a fresh
    # Mieru node. State-backed protocols are reconciled individually; if no
    # authoritative node state survived, only manager/schema are repaired.
    manager_only=1
    nb_lifecycle_mark_mutation_started || {
      rc=$?
      nb_lifecycle_restore_pre_mutation || rc=1
      nb_lifecycle_lock_release
      return "$rc"
    }
    nb_reconcile_partial_uninstall
    rc=$?
  elif [ "$validate_only" -eq 0 ]; then
    NOBRAND_PROTOCOL_CALLBACK_ATTEMPT_MUTATION=0
    do_install_impl
    rc=$?
  fi
  if [ "${NOBRAND_INSTALL_CANCELLED:-0}" -eq 1 ]; then
    nb_lifecycle_restore_pre_mutation || {
      nb_lifecycle_lock_release
      return 1
    }
    nb_lifecycle_lock_release
    return 0
  fi
  if [ "$rc" -ne 0 ]; then
    if [ "$partial_uninstall_repair" -eq 0 ] \
       && [ "$validate_only" -eq 0 ] \
       && [ "${NOBRAND_PROTOCOL_CALLBACK_ATTEMPT_MUTATION:-0}" -eq 0 ]; then
      nb_lifecycle_restore_pre_mutation || rc=1
    elif nb_lifecycle_tx_valid && [ "$(nb_lifecycle_mutation_started)" = 0 ]; then
      nb_lifecycle_restore_pre_mutation || rc=1
    fi
    nb_lifecycle_lock_release
    return "$rc"
  fi
  if [ "$partial_uninstall_repair" -eq 0 ] \
     && [ "$validate_only" -eq 0 ] \
     && [ "${NOBRAND_PROTOCOL_CALLBACK_ATTEMPT_MUTATION:-0}" -eq 0 ]; then
    nb_lifecycle_restore_pre_mutation || {
      nb_lifecycle_lock_release
      return 1
    }
    nb_lifecycle_lock_release
    if [ "$transaction_preexisting" -eq 1 ]; then
      warn "$(t \
        'Mieru 本次安装重试未提交新的协议变更；已原样保留先前恢复事务。' \
        'This Mieru install retry committed no new protocol change; the prior recovery transaction was preserved exactly.')"
    fi
    return 1
  fi
  if [ "$partial_uninstall_repair" -eq 1 ] \
     && declare -F ssh_tunnel_state_exists >/dev/null 2>&1 \
     && ssh_tunnel_state_exists \
     && [ "$(ssh_tunnel_state_field pending_operation 2>/dev/null || true)" = restore ] \
     && [ -n "$(ssh_tunnel_state_field pending_watchdog_token 2>/dev/null || true)" ]; then
    nb_lifecycle_lock_release
    return 0
  fi
  if [ "$partial_uninstall_repair" -eq 1 ]; then
    nb_lifecycle_checkpoint "$operation" partial-uninstall-ready-to-validate || {
      rc=$?
      nb_lifecycle_lock_release
      return "$rc"
    }
  else
    nb_lifecycle_checkpoint "$operation" ready-to-validate || {
      rc=$?
      nb_lifecycle_lock_release
      return "$rc"
    }
  fi
  nb_lifecycle_validate_manager_repair || {
    nb_lifecycle_lock_release
    return 1
  }
  if [ "$manager_only" -eq 0 ]; then
    mita_v3_install_state_valid || {
      nb_lifecycle_lock_release
      return 1
    }
    if ! users_state_exists || [ "$(users_count)" -le 0 ]; then
      nb_lifecycle_lock_release
      return 1
    fi
    verify_mita_running 1 || {
      nb_lifecycle_lock_release
      return 1
    }
  fi
  nb_lifecycle_complete "$operation" || {
    nb_lifecycle_lock_release
    return 1
  }
  if declare -F nobrand_backup_restore_transaction_present >/dev/null 2>&1 \
     && nobrand_backup_restore_transaction_present; then
    nobrand_backup_restore_confirmation_finalize repair-accepted || {
      nb_lifecycle_lock_release
      return 1
    }
  fi
  nb_lifecycle_lock_release
}

do_reconfigure() {
  local rc=0 transaction_preexisting=0 validate_only=0
  local lifecycle_format="" lifecycle_phase=prepare current_mutation=0
  require_root
  require_linux
  mita_installed || die "$(t 'mita 未安装，请先执行安装' 'mita is not installed; run install first')"
  nb_lifecycle_lock_acquire || return 1
  if nb_lifecycle_tx_valid \
     && [ "$(nb_lifecycle_field STATUS)" = in-progress ] \
     && [ "$(nb_lifecycle_field OPERATION)" = repair ] \
     && [ "$(nb_lifecycle_scope)" = mieru ]; then
    transaction_preexisting=1
    lifecycle_format="$(nb_lifecycle_field FORMAT)"
    lifecycle_phase="$(nb_lifecycle_field LAST_COMPLETED_PHASE)"
    current_mutation="$(nb_lifecycle_mutation_started)" || {
      nb_lifecycle_lock_release
      return 1
    }
    if [ "$lifecycle_format" = nobrand-lifecycle-v2 ] \
       && [ "$current_mutation" = 0 ]; then
      nb_lifecycle_clear || {
        nb_lifecycle_lock_release
        return 1
      }
      if [ -n "${NOBRAND_RECOVERY_EXPECTED_SCOPE:-}" ]; then
        nb_lifecycle_lock_release
        t 'Mieru 重新配置在写入变更前中止；已清除临时恢复信息，请从管理菜单重新开始。' \
          'Mieru reconfigure stopped before any change; temporary recovery metadata was cleared. Start it again from the manager menu.'
        return 0
      fi
      [ "${NOBRAND_PROTOCOL_EXPLICIT_RETRY_SCOPE:-}" = mieru ] || {
        nb_lifecycle_lock_release
        return 1
      }
      transaction_preexisting=0
      lifecycle_format=""
      lifecycle_phase=prepare
      current_mutation=0
    fi
    if [ "$lifecycle_format" = nobrand-lifecycle-v2 ]; then
      case "$lifecycle_phase" in
        ready-to-validate) validate_only=1 ;;
        *)
          if [ -n "${NOBRAND_RECOVERY_EXPECTED_SCOPE:-}" ]; then
            nb_lifecycle_lock_release
            warn "$(t \
              '原 Mieru 重新配置参数未写入恢复记录。为避免使用默认值静默重放，请显式执行 nobrand mieru reconfigure。' \
              'The original Mieru reconfigure request was not stored. To avoid silently replaying defaults, explicitly run nobrand mieru reconfigure.')"
            return 1
          fi
          [ "${NOBRAND_PROTOCOL_EXPLICIT_RETRY_SCOPE:-}" = mieru ] || {
            nb_lifecycle_lock_release
            return 1
          }
          ;;
      esac
    fi
  elif [ -n "${NOBRAND_RECOVERY_EXPECTED_SCOPE:-}" ]; then
    nb_lifecycle_lock_release
    warn "$(t '原恢复事务已由其它进程改变；拒绝执行过期的 Mieru 重新配置恢复。' \
      'The recovery transaction changed in another process; refusing stale Mieru reconfigure recovery.')"
    return 1
  fi
  nb_lifecycle_pre_mutation_snapshot || {
    nb_lifecycle_lock_release
    return 1
  }
  nb_lifecycle_begin repair "$lifecycle_phase" 0 0 0 0 0 0 mieru || {
    nb_lifecycle_pre_mutation_disarm
    nb_lifecycle_lock_release
    return 1
  }
  NOBRAND_PROTOCOL_CALLBACK_ATTEMPT_MUTATION=0
  if [ "$validate_only" -eq 0 ]; then
    do_reconfigure_impl
    rc=$?
  fi
  if [ "$rc" -ne 0 ]; then
    if [ "$validate_only" -eq 0 ] \
       && [ "$NOBRAND_PROTOCOL_CALLBACK_ATTEMPT_MUTATION" -eq 0 ]; then
      nb_lifecycle_restore_pre_mutation || rc=1
    fi
    nb_lifecycle_lock_release
    return "$rc"
  fi
  if [ "$validate_only" -eq 0 ] \
     && [ "$NOBRAND_PROTOCOL_CALLBACK_ATTEMPT_MUTATION" -eq 0 ]; then
    # A user can accept every existing value. That is a successful no-op, not a
    # repair transaction against which unrelated current state may be completed.
    nb_lifecycle_restore_pre_mutation || {
      nb_lifecycle_lock_release
      return 1
    }
    nb_lifecycle_lock_release
    if [ "$transaction_preexisting" -eq 1 ]; then
      warn "$(t \
        'Mieru 本次重新配置重试未提交新的协议变更；已原样保留先前恢复事务。' \
        'This Mieru reconfigure retry committed no new protocol change; the prior recovery transaction was preserved exactly.')"
      return 1
    fi
    return 0
  fi
  nb_lifecycle_checkpoint repair ready-to-validate || {
    rc=$?
    nb_lifecycle_lock_release
    return "$rc"
  }
  nb_lifecycle_validate_manager_repair || {
    nb_lifecycle_lock_release
    return 1
  }
  mita_v3_install_state_valid || {
    nb_lifecycle_lock_release
    return 1
  }
  verify_mita_running 1 || {
    nb_lifecycle_lock_release
    return 1
  }
  nb_lifecycle_complete repair || {
    nb_lifecycle_lock_release
    return 1
  }
  nb_lifecycle_lock_release
}

mieru_upgrade_rollback() {
  local runtime_tx="$1" users_tx="$2" old_channel="$3" old_version="$4" rc=0
  MIERU_CHANNEL="$old_channel"
  MIERU_VERSION="$old_version"
  mieru_runtime_rollback "$runtime_tx" || rc=1
  users_tx_rollback "$users_tx" 0
  isolated_stop_all 2>/dev/null || true
  reconcile_isolated_instances 2>/dev/null || rc=1
  verify_mita_running 2>/dev/null || rc=1
  return "$rc"
}

do_upgrade() {
  require_root
  require_linux
  require_cmd curl
  mita_installed || die "$(t 'mita 未安装，请先执行 fresh install' \
    'mita is not installed; perform a fresh install first')"
  mita_v3_install_state_valid || die "$(t 'schema v3 Mieru 安装状态缺失或损坏，拒绝升级' \
    'Schema-v3 Mieru install state is missing or invalid; refusing upgrade')"
  local pm arch ver url tmp tx runtime_tx cur state_channel state_version
  local requested_channel="$MIERU_CHANNEL" requested_version="$MIERU_VERSION"
  local requested_channel_cli="${MIERU_CHANNEL_CLI:-0}" requested_version_cli="${MIERU_VERSION_CLI:-0}"
  pm="$(detect_pkg_manager)"
  arch="$(detect_arch)"
  ensure_management_dependencies "$pm"
  MIERU_CHANNEL_CLI=0 MIERU_VERSION_CLI=0
  load_install_state
  state_channel="$MIERU_CHANNEL"
  state_version="$MIERU_VERSION"
  users_isolated_mode || die "$(t 'schema v3 Mieru 状态必须使用 isolated-v2' \
    'Schema-v3 Mieru state must use isolated-v2')"
  [ "$(users_count 2>/dev/null || printf 0)" -gt 0 ] \
    || die "$(t 'schema v3 Mieru 用户状态缺失，拒绝升级' \
      'Schema-v3 Mieru user state is missing; refusing upgrade')"
  MIERU_CHANNEL_CLI="$requested_channel_cli"; MIERU_VERSION_CLI="$requested_version_cli"
  if [ "$MIERU_CHANNEL_CLI" -eq 1 ]; then
    MIERU_CHANNEL="$requested_channel"
  fi
  if [ "$MIERU_VERSION_CLI" -eq 1 ]; then
    MIERU_VERSION="$requested_version"
  fi
  mieru_resolve_runtime "${MIERU_CHANNEL:-stable}" "${MIERU_VERSION:-}" "$pm" "$arch" \
    || die "$(t '无法解析并验证官方 Mieru release' \
      'Failed to resolve and validate the official Mieru release')"
  ver="$MIERU_RUNTIME_RESOLVED_VERSION"
  cur="$(installed_version || true)"
  if version_is_current "$cur" "$ver"; then
    MIERU_VERSION="$ver"
    install_self_script
    admin_lock_acquire || return 1
    tx="$(users_tx_snapshot)" || { admin_lock_release; return 1; }
    # 即使二进制已是最新版，也要让运行中的实例重新读取最新 unit/runner。
    isolated_stop_all
    if ! apply_users_config "$tx"; then
      admin_lock_release
      return 1
    fi
    users_tx_commit "$tx"
    admin_lock_release
    verify_mita_running
    [ -f "$MITA_STATE" ] && save_install_state
    t "管理脚本已更新至 v${SCRIPT_VERSION}（mita ${cur} 已满足 $(mieru_channel_label) 目标 ${ver}）" \
      "Manager script updated to v${SCRIPT_VERSION} (mita ${cur} satisfies $(mieru_channel_label) target ${ver})"
    [ "${MENU_MODE:-0}" -eq 1 ] && return 0
    exit 0
  fi
  if [ "${YES:-0}" -ne 1 ] && [ -t 0 ]; then
    t "已安装: ${cur:-未知}" "Installed: ${cur:-unknown}"
    t "最新稳定版: ${ver}" "Latest stable: ${ver}"
    if ! confirm '升级？[Y/n]: ' 'Upgrade? [Y/n]: ' y; then
      [ "${MENU_MODE:-0}" -eq 1 ] && return 0
      exit 0
    fi
  fi
  url="$MIERU_RUNTIME_RESOLVED_URL"
  tmp="$(mktemp_file)"
  download_package "$url" "$tmp" \
    "$MIERU_RUNTIME_RESOLVED_SHA256" \
    "$MIERU_RUNTIME_RESOLVED_CHECKSUM_URL"
  install_self_script
  admin_lock_acquire || { rm -f "$tmp"; return 1; }
  runtime_tx="$(mieru_runtime_snapshot)" \
    || { rm -f "$tmp"; admin_lock_release; return 1; }
  tx="$(users_tx_snapshot)" || {
    rm -f "$tmp"
    mieru_runtime_commit "$runtime_tx" 2>/dev/null || true
    admin_lock_release
    return 1
  }
  if ! ( install_package "$tmp" "$pm" ) || ! mieru_assert_runtime_version "$ver"; then
    rm -f "$tmp"
    mieru_upgrade_rollback "$runtime_tx" "$tx" "$state_channel" "$state_version" \
      || warn "$(t 'Mieru runtime 回滚后服务恢复不完整，请立即运行 doctor' \
        'Mieru services were not fully restored after runtime rollback; run doctor immediately')"
    admin_lock_release
    die "$(t 'Mieru runtime 升级验证失败，已恢复旧 runtime 与节点状态' \
      'Mieru runtime upgrade validation failed; the old runtime and node state were restored')"
    return 1
  fi
  rm -f "$tmp"
  MIERU_VERSION="$ver"
  isolated_stop_all
  if ! ( apply_users_config "$tx" ) \
     || ! verify_mita_running \
     || { [ ! -f "$MITA_STATE" ] || ! save_install_state; }; then
    mieru_upgrade_rollback "$runtime_tx" "$tx" "$state_channel" "$state_version" \
      || warn "$(t 'Mieru runtime 回滚后服务恢复不完整，请立即运行 doctor' \
        'Mieru services were not fully restored after runtime rollback; run doctor immediately')"
    admin_lock_release
    die "$(t 'Mieru 升级应用失败，已恢复旧 runtime、服务与状态' \
      'Mieru upgrade application failed; the old runtime, services, and state were restored')"
    return 1
  fi
  users_tx_commit "$tx"
  mieru_runtime_commit "$runtime_tx" || {
    admin_lock_release
    return 1
  }
  admin_lock_release
  t "已升级至 ${ver}（$(mieru_channel_label)）" \
    "Upgraded to ${ver} ($(mieru_channel_label))"
}

mita_nobrand_specific_residue_present() {
  local path pattern
  for path in "$MITA_BIN" "$MITA_MARKER" "$MITA_STATE" "$MITA_USERS_STATE" \
    "$MITA_INSTANCE_SYSTEMD_TEMPLATE" "$MITA_INSTANCE_TMPFILES" \
    "$MITA_INSTANCE_RUNNER" "$MITA_USERS_TIMER" "$MITA_USERS_SERVICE" \
    "$MITA_USERS_CRON" "$MITA_LOGROTATE_CONF" "$MITA_CLIENT_EXPORT_DIR"; do
    [ ! -e "$path" ] && [ ! -L "$path" ] || return 0
  done
  for pattern in "${MITA_INSTANCE_OPENRC_PREFIX}*" '/var/log/nobrand-mieru-*.log' \
    '/var/log/nobrand-mieru-*.err' '/root/nobrand_mieru_client_*.json'; do
    compgen -G "$pattern" >/dev/null 2>&1 && return 0
  done
  return 1
}

mita_uninstall_ledger_active() {
  nb_lifecycle_tx_valid \
    && [ "$(nb_lifecycle_field STATUS)" = in-progress ] \
    && [ "$(nb_lifecycle_field OPERATION)" = uninstall ] \
    && [ "$(nb_lifecycle_scope)" = global ] \
    && [ "$(nb_lifecycle_field MIERU_OWNED)" = 1 ]
}

mita_uninstall_ledger_capture() {
  local preserve_package=0 preserve_user=0 preserve_group=0 preserve_shared=0
  if nb_schema_v3_file_valid && [ -f "$MITA_MARKER" ] && [ ! -L "$MITA_MARKER" ]; then
    [ ! -f "$MITA_PRESERVE_PACKAGE_MARKER" ] || preserve_package=1
    [ ! -f "$MITA_PRESERVE_USER_MARKER" ] || preserve_user=1
    [ ! -f "$MITA_PRESERVE_GROUP_MARKER" ] || preserve_group=1
    [ ! -f "$MITA_PRESERVE_SHARED_MARKER" ] || preserve_shared=1
    printf '1|%s|%s|%s|%s' "$preserve_package" "$preserve_user" \
      "$preserve_group" "$preserve_shared"
  elif mita_nobrand_specific_residue_present; then
    # Exact NoBrand-named artifacts are positive ownership evidence, but a
    # missing authoritative marker cannot prove ownership of the upstream
    # package, shared directories, or generic mita account. Preserve them.
    printf '1|1|1|1|1'
  else
    printf '0|0|0|0|0'
  fi
}

mita_uninstall_target_present() {
  mita_uninstall_ledger_active && return 0
  nb_schema_v3_file_valid || return 1
  installed_by_oneclick \
    || [ -s "$MITA_USERS_STATE" ] \
    || [ -s "$MITA_STATE" ] \
    || [ -x "$MITA_BIN" ] \
    || [ -e "$MITA_INSTANCE_SYSTEMD_TEMPLATE" ] \
    || [ -e "$MITA_USERS_TIMER" ] \
    || [ -e "$MITA_USERS_SERVICE" ]
}

stop_mita_for_uninstall() {
  local sm
  STAGE="停止 mita 服务"
  isolated_stop_all
  tc_clear_owned_filters 2>/dev/null || true
  sm="$(service_manager)"
  case "$sm" in
    systemd)
      run systemctl disable --now nobrand-mieru-users-scan.timer \
        nobrand-mieru-users-scan.service nobrand-mieru-tc-restore.service 2>/dev/null || true
      ;;
    openrc) ;;
  esac
}

remove_mita_common() {
  STAGE="删除 mita 文件与账号"
  local preserve_package="${UNINSTALL_PRESERVE_PACKAGE:-0}"
  local preserve_user="${UNINSTALL_PRESERVE_USER:-0}"
  local preserve_group="${UNINSTALL_PRESERVE_GROUP:-0}"
  local preserve_shared="${UNINSTALL_PRESERVE_SHARED:-0}"
  run rm -f /var/log/nobrand-mieru-*.log /var/log/nobrand-mieru-*.err
  run rm -f /root/nobrand_mieru_client_*.json 2>/dev/null || true
  run rm -rf "$MITA_CLIENT_EXPORT_DIR"
  remove_users_scheduler 2>/dev/null || true
  run rm -f "$MITA_LOGROTATE_CONF" 2>/dev/null || true
  run rm -rf "$MITA_INSTANCES_DIR" "$MITA_INSTANCE_RUN_DIR" \
    "$MITA_INSTANCE_METRICS_DIR" "$MITA_USERS_BACKUP_DIR" "$MITA_MANAGER_STATE_DIR"
  if [ "$preserve_shared" -eq 0 ]; then
    run rm -rf /etc/mita /var/lib/mita /run/mita /var/run/mita /var/run/mita.sock
  fi
  run rm -f "$MITA_USERS_STATE" "$MITA_USERS_LOCK" "$MITA_ADMIN_LOCK" \
    "$MITA_FIREWALL_OWNED_STATE" "$TC_OWNED_STATE" "$MITA_STATE"
  run rm -f "$MITA_BIN" "$MITA_MARKER"
  run rm -f "$MITA_INSTANCE_SYSTEMD_TEMPLATE" "$MITA_INSTANCE_TMPFILES" \
    "$MITA_INSTANCE_RUNNER" "${MITA_INSTANCE_OPENRC_PREFIX}"*
  run rm -f "$MITA_USERS_LOG" 2>/dev/null || true
  if [ -d /etc/systemd/system ]; then
    find /etc/systemd/system -type l \
      \( -name 'nobrand-mieru@*.service' -o -name 'nobrand-mieru-users-scan.timer' \
         -o -name 'nobrand-mieru-tc-restore.service' \) -delete 2>/dev/null || true
  fi
  run systemctl daemon-reload 2>/dev/null || true
  run systemctl reset-failed 2>/dev/null || true
  if [ "$preserve_user" -eq 0 ] && _has_user mita; then
    run deluser mita 2>/dev/null || run userdel mita 2>/dev/null || true
  fi
  if [ "$preserve_group" -eq 0 ] && _has_group mita; then
    run delgroup mita 2>/dev/null || run groupdel mita 2>/dev/null || true
  fi
}

verify_mita_uninstalled() {
  STAGE="验收卸载结果"
  local failed=0 path pattern save_cmd
  local preserve_package="${UNINSTALL_PRESERVE_PACKAGE:-0}"
  local preserve_user="${UNINSTALL_PRESERVE_USER:-0}"
  local preserve_group="${UNINSTALL_PRESERVE_GROUP:-0}"
  local preserve_shared="${UNINSTALL_PRESERVE_SHARED:-0}"
  if [ "$preserve_package" -eq 0 ] \
     && command -v dpkg-query >/dev/null 2>&1 \
     && dpkg-query -W -f='${db:Status-Abbrev}' mita 2>/dev/null | grep -q .; then
    warn "$(t '卸载验收失败: Debian 软件包记录仍存在' \
      'Uninstall verification failed: Debian package record remains')"
    failed=1
  fi
  if [ "$preserve_package" -eq 0 ] \
     && command -v rpm >/dev/null 2>&1 && rpm -q mita >/dev/null 2>&1; then
    warn "$(t '卸载验收失败: RPM 软件包仍存在' \
      'Uninstall verification failed: RPM package remains')"
    failed=1
  fi
  for path in \
    "$MITA_MANAGER_STATE_DIR" \
    "$MITA_INSTANCES_DIR" "$MITA_INSTANCE_RUN_DIR" "$MITA_INSTANCE_METRICS_DIR" \
    "$MITA_USERS_STATE" "$MITA_USERS_LOCK" "$MITA_USERS_BACKUP_DIR" \
    "$MITA_ADMIN_LOCK" "$MITA_FIREWALL_OWNED_STATE" "$TC_OWNED_STATE" \
    "$MITA_BIN" "$MITA_CLIENT_EXPORT_DIR" \
    "$MITA_INSTANCE_SYSTEMD_TEMPLATE" "$MITA_INSTANCE_TMPFILES" "$MITA_INSTANCE_RUNNER" \
    "$MITA_USERS_TIMER" "$MITA_USERS_SERVICE" "$MITA_USERS_CRON" "$MITA_LOGROTATE_CONF" \
    "$MITA_USERS_LOG" \
    "$BBR_STATE_FILE" "$BBR_BACKUP_FILE"; do
    if [ -e "$path" ] || [ -L "$path" ]; then
      warn "$(t "卸载残留: ${path}" "Uninstall residue: ${path}")"
      failed=1
    fi
  done
  if [ "$preserve_shared" -eq 0 ]; then
    for path in /etc/mita /var/lib/mita /run/mita /var/run/mita; do
      if [ -e "$path" ] || [ -L "$path" ]; then
        warn "$(t "卸载残留: ${path}" "Uninstall residue: ${path}")"
        failed=1
      fi
    done
  fi
  for pattern in \
    "${MITA_INSTANCE_OPENRC_PREFIX}*" '/var/log/nobrand-mieru-*.log' \
    '/var/log/nobrand-mieru-*.err' '/root/nobrand_mieru_client_*.json'; do
    if compgen -G "$pattern" >/dev/null 2>&1; then
      warn "$(t "卸载仍有匹配残留: ${pattern}" "Uninstall residue matches: ${pattern}")"
      failed=1
    fi
  done
  local systemd_link_names=( -name 'nobrand-mieru@*.service' \
    -o -name 'nobrand-mieru-users-scan.timer' -o -name 'nobrand-mieru-tc-restore.service' )
  if [ -d /etc/systemd/system ] \
     && find /etc/systemd/system -type l \( "${systemd_link_names[@]}" \) \
       -print -quit 2>/dev/null | grep -q .; then
    warn "$(t '卸载残留: systemd wants 目录仍有 mita 符号链接' \
      'Uninstall residue: systemd wants directories still contain mita symlinks')"
    failed=1
  fi
  if { [ "$preserve_user" -eq 0 ] && _has_user mita; } \
     || { [ "$preserve_group" -eq 0 ] && _has_group mita; }; then
    warn "$(t '卸载残留: mita 系统用户或用户组仍存在' \
      'Uninstall residue: mita system user or group remains')"
    failed=1
  fi
  for save_cmd in iptables-save ip6tables-save; do
    if command -v "$save_cmd" >/dev/null 2>&1 \
       && "$save_cmd" 2>/dev/null | grep -q -- "$MITA_FIREWALL_COMMENT"; then
      warn "$(t "卸载残留: ${save_cmd} 中仍有 ${MITA_FIREWALL_COMMENT} 规则" \
        "Uninstall residue: ${save_cmd} still contains ${MITA_FIREWALL_COMMENT} rules")"
      failed=1
    fi
  done
  if [ -e "$NOBRAND_INGRESS_FIREWALL_STATE_FILE" ]; then
    if ! nb_strict_firewall_state_valid "$NOBRAND_INGRESS_FIREWALL_STATE_FILE"; then
      warn "$(t '卸载验收失败: Strict Ingress 防火墙状态无效' \
        'Uninstall verification failed: Strict Ingress firewall state is invalid')"
      failed=1
    elif jq -e 'any(.rules[]; .owner | startswith("mieru:"))' \
      "$NOBRAND_INGRESS_FIREWALL_STATE_FILE" >/dev/null; then
      warn "$(t '卸载残留: Strict Ingress 中仍有 Mieru 所有者规则' \
        'Uninstall residue: Strict Ingress still contains Mieru-owned rules')"
      failed=1
    fi
  fi
  [ "$failed" -eq 0 ]
}

do_uninstall() {
  local ledger_owned=0
  require_root
  UNINSTALL_CANCELLED=0
  UNINSTALL_PRESERVE_EXTERNAL=0
  UNINSTALL_PRESERVE_PACKAGE=0
  UNINSTALL_PRESERVE_USER=0
  UNINSTALL_PRESERVE_GROUP=0
  UNINSTALL_PRESERVE_SHARED=0
  mita_uninstall_target_present \
    || die "$(t '未检测到 mita 或 OneClick 残留，无需卸载' \
      'No mita or OneClick residue detected; nothing to uninstall')"
  mita_uninstall_ledger_active && ledger_owned=1
  if ! installed_by_oneclick && [ "$ledger_owned" -ne 1 ]; then
    die "$(t '缺少 schema v3 Mieru ownership 标记，拒绝清理未知资源' \
      'Schema-v3 Mieru ownership marker is missing; refusing to clean unknown resources')"
  fi
  if ! confirm '确认仅卸载 NoBrand 3 管理的 Mieru 协议资源？[y/N]: ' \
    'Uninstall only NoBrand-3-managed Mieru protocol resources? [y/N]: ' n; then
    if [ "${MENU_MODE:-0}" -eq 1 ]; then
      UNINSTALL_CANCELLED=1
      return 0
    fi
    exit 0
  fi
  if [ "$ledger_owned" -eq 1 ]; then
    UNINSTALL_PRESERVE_PACKAGE="$(nb_lifecycle_field MIERU_PRESERVE_PACKAGE)"
    UNINSTALL_PRESERVE_USER="$(nb_lifecycle_field MIERU_PRESERVE_USER)"
    UNINSTALL_PRESERVE_GROUP="$(nb_lifecycle_field MIERU_PRESERVE_GROUP)"
    UNINSTALL_PRESERVE_SHARED="$(nb_lifecycle_field MIERU_PRESERVE_SHARED)"
    if [ "$UNINSTALL_PRESERVE_PACKAGE" -eq 1 ] \
       || [ "$UNINSTALL_PRESERVE_USER" -eq 1 ] \
       || [ "$UNINSTALL_PRESERVE_GROUP" -eq 1 ] \
       || [ "$UNINSTALL_PRESERVE_SHARED" -eq 1 ]; then
      UNINSTALL_PRESERVE_EXTERNAL=1
    fi
  elif preexisting_mita_resources_recorded; then
    UNINSTALL_PRESERVE_EXTERNAL=1
    [ -f "$MITA_PRESERVE_PACKAGE_MARKER" ] && UNINSTALL_PRESERVE_PACKAGE=1
    [ -f "$MITA_PRESERVE_USER_MARKER" ] && UNINSTALL_PRESERVE_USER=1
    [ -f "$MITA_PRESERVE_GROUP_MARKER" ] && UNINSTALL_PRESERVE_GROUP=1
    [ -f "$MITA_PRESERVE_SHARED_MARKER" ] && UNINSTALL_PRESERVE_SHARED=1
    warn "$(t '检测到安装前已存在的 mita 包或系统账号；将按记录分别保留外部资源，预存包的公共目录也会保留，并保持服务停止。' \
      'A pre-existing mita package or system account was recorded; each external resource will be preserved separately, including shared directories for a pre-existing package, and left stopped.')"
  fi
  local pm
  # 必须在停止服务、清理规则和卸载软件包之前确认 BBR 文件仍由本脚本拥有，
  # 避免因人工修改触发保护后留下半卸载状态。
  if ! restore_owned_bbr_fq; then
    bail "$(t 'BBR/FQ 配置已被外部修改，卸载已在删除任何 mita 文件前停止' \
      'BBR/FQ configuration was modified externally; uninstall stopped before removing any mita files')" || return 1
    return 1
  fi
  pm="$(detect_pkg_manager)"
  stop_mita_for_uninstall
  STAGE="清理防火墙规则"
  firewall_clear_all_owned
  STAGE="清理 Strict Ingress 防火墙规则"
  mieru_clear_strict_firewall
  STAGE="卸载 mita 软件包"
  if [ "$UNINSTALL_PRESERVE_PACKAGE" -eq 0 ]; then
    case "$pm" in
      deb)
        if dpkg-query -W mita >/dev/null 2>&1; then
          run dpkg -P mita
        fi
        ;;
      rpm)
        if rpm -q mita >/dev/null 2>&1; then
          run rpm -e mita
        fi
        ;;
      alpine) ;;
    esac
  fi
  remove_mita_common
  if ! verify_mita_uninstalled; then
    warn "$(t '卸载未完全通过验收；已保留上方残留信息，请修复后重试' \
      'Uninstall did not pass verification; review the residue above and retry')"
    return 1
  fi
  if [ "$UNINSTALL_PRESERVE_EXTERNAL" -eq 1 ]; then
    t 'NoBrand 管理的 Mieru 文件已卸载；安装前存在的 mita 外部资源已保留。' \
      'NoBrand-managed Mieru files were removed; pre-existing mita resources were preserved.'
  else
    t 'NoBrand 3 管理的 Mieru runtime 与协议资源已卸载' \
      'The NoBrand-3-managed Mieru runtime and protocol resources were removed'
  fi
  if [ "${UNINSTALL_CONTEXT:-protocol}" != global ]; then
    t 'Mieru 协议资源已卸载；nobrand/nb 管理命令仍保留。' \
      'Mieru protocol resources were removed; nobrand/nb management commands remain.'
  fi
}
