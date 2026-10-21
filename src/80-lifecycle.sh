nb_lifecycle_validate_manager_repair() {
  local installed=""
  nb_schema_v3_file_valid || return 1
  installed="$(nb_installed_manager_version 2>/dev/null || true)"
  [ "$installed" = "$SCRIPT_VERSION" ]
}

nobrand_manager_bootstrap() {
  nb_splicore_legacy_preflight || return 1
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
      CURRENT_COMPLETE|CURRENT_PARTIAL_INSTALL|CURRENT_PARTIAL_REPAIR)
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
  local scope="$1" rules
  LC_ALL=C
  export LC_ALL
  shopt -s nullglob dotglob
  printf 'nobrand-protocol-callback-baseline-v1\0%s\0' "$scope" || return 1
  case "$scope" in
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
  local scope="$1"
  shopt -s nullglob dotglob
  case "$scope" in
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
  local scope="$1" enabled port failed=0
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
    vless-sudoku) ;;
    *) return 1 ;;
  esac

  # Complete the read-only preflight for the whole scope before repairing even
  # one unit.  Enumerators are intentionally forgiving for status displays, so
  # recovery additionally requires every derived field/config it will consume.
  case "$scope" in
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
