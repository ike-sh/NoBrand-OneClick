bbr_fq_sysctl_value() {
  local key="$1" path value=""
  if command -v sysctl >/dev/null 2>&1; then
    value="$(sysctl -n "$key" 2>/dev/null || true)"
  else
    path="/proc/sys/${key//./\/}"
    [ -r "$path" ] && value="$(tr -d '\r\n' <"$path" 2>/dev/null || true)"
  fi
  printf '%s' "$value"
}

bbr_fq_enabled() {
  [ "$(bbr_fq_sysctl_value net.ipv4.tcp_congestion_control)" = "bbr" ] \
    && [ "$(bbr_fq_sysctl_value net.core.default_qdisc)" = "fq" ]
}

bbr_fq_active() {
  local dev
  bbr_fq_enabled || return 1
  command -v tc >/dev/null 2>&1 || return 1
  dev="$(tc_default_iface 2>/dev/null || mtu_default_iface 2>/dev/null || true)"
  [ -n "$dev" ] || return 1
  tc qdisc show dev "$dev" 2>/dev/null \
    | grep -Eq '(^|[[:space:]])qdisc[[:space:]]+fq([[:space:]]|$)'
}

report_bbr_fq_status() {
  if bbr_fq_active; then
    t 'TCP BBR 已启用，当前出口网卡正在使用 FQ' \
      'TCP BBR is enabled and the current egress interface is using FQ'
  else
    warn "$(t 'TCP BBR + FQ 默认策略已配置；当前出口网卡尚未使用 FQ，重启系统或重建网卡后生效' \
      'TCP BBR + FQ defaults are configured; the current egress interface is not using FQ yet, so reboot or recreate the interface to activate it')"
  fi
}

bbr_owned_mode() {
  local mode=""
  [ -f "$BBR_STATE_FILE" ] || return 1
  IFS= read -r mode <"$BBR_STATE_FILE" || return 1
  case "$mode" in
    created|replaced) printf '%s' "$mode" ;;
    *) return 1 ;;
  esac
}

write_bbr_state() {
  local mode="$1" old_qdisc="$2" old_cc="$3" tmp
  case "$mode" in created|replaced) ;; *) return 1 ;; esac
  [[ "$old_qdisc" =~ ^[A-Za-z0-9_.-]*$ ]] || return 1
  [[ "$old_cc" =~ ^[A-Za-z0-9_.-]*$ ]] || return 1
  tmp="$(mktemp_file .bbr-state)" || return 1
  printf '%s\n%s\n%s\n' "$mode" "$old_qdisc" "$old_cc" >"$tmp"
  install -d -o root -g root -m 0700 "$NOBRAND_STATE_DIR"
  install -o root -g root -m 0600 "$tmp" "$BBR_STATE_FILE"
  rm -f "$tmp"
}

bbr_conf_is_owned() {
  [ -f "$BBR_SYSCTL_CONF" ] || return 1
  [ "$(sed '/^[[:space:]]*#/d;/^[[:space:]]*$/d' "$BBR_SYSCTL_CONF" 2>/dev/null)" = \
    $'net.core.default_qdisc=fq\nnet.ipv4.tcp_congestion_control=bbr' ]
}

restore_bbr_fq() {
  local backup="$1" old_qdisc="$2" old_cc="$3" had_conf="${4:-1}"
  if [ "$had_conf" -eq 1 ] && [ -n "$backup" ] && [ -f "$backup" ]; then
    install -o root -g root -m 0644 "$backup" "$BBR_SYSCTL_CONF" 2>/dev/null || true
  else
    rm -f "$BBR_SYSCTL_CONF" 2>/dev/null || true
  fi
  [ -n "$old_qdisc" ] \
    && sysctl -q -w "net.core.default_qdisc=${old_qdisc}" >/dev/null 2>&1 || true
  [ -n "$old_cc" ] \
    && sysctl -q -w "net.ipv4.tcp_congestion_control=${old_cc}" >/dev/null 2>&1 || true
  [ -z "$backup" ] || rm -f "$backup"
}

enable_bbr_fq() {
  STAGE="启用 TCP BBR + FQ"
  if bbr_fq_enabled; then
    report_bbr_fq_status
    return 0
  fi
  require_cmd sysctl

  local available old_qdisc old_cc tmp backup="" had_conf=0 owned_mode=""
  if command -v modprobe >/dev/null 2>&1; then
    run modprobe tcp_bbr 2>/dev/null || true
    run modprobe sch_fq 2>/dev/null || true
  fi
  available="$(bbr_fq_sysctl_value net.ipv4.tcp_available_congestion_control)"
  case " ${available} " in
    *' bbr '*) ;;
    *)
      die "$(t '当前内核不支持 TCP BBR' 'TCP BBR is not supported by the current kernel')"
      return 1
      ;;
  esac

  old_qdisc="$(bbr_fq_sysctl_value net.core.default_qdisc)"
  old_cc="$(bbr_fq_sysctl_value net.ipv4.tcp_congestion_control)"
  owned_mode="$(bbr_owned_mode 2>/dev/null || true)"
  if [ -e "$BBR_STATE_FILE" ] && [ -z "$owned_mode" ]; then
    die "$(t 'BBR 所有权状态损坏，拒绝覆盖系统 sysctl 配置' \
      'BBR ownership state is invalid; refusing to overwrite system sysctl configuration')"
    return 1
  fi
  if [ -n "$owned_mode" ] && ! bbr_conf_is_owned; then
    die "$(t 'BBR sysctl 文件已被外部修改，拒绝覆盖；请先人工核对' \
      'The BBR sysctl file was modified externally; refusing to overwrite it')"
    return 1
  fi
  if [ -f "$BBR_SYSCTL_CONF" ]; then
    had_conf=1
    backup="$(mktemp_file .bbr-backup)" || return 1
    cp -p "$BBR_SYSCTL_CONF" "$backup" || { rm -f "$backup"; return 1; }
  fi
  tmp="$(mktemp_file .bbr-conf)" || { [ -z "$backup" ] || rm -f "$backup"; return 1; }
  printf '%s\n' \
    'net.core.default_qdisc=fq' \
    'net.ipv4.tcp_congestion_control=bbr' >"$tmp"
  run mkdir -p "$(dirname "$BBR_SYSCTL_CONF")"
  if ! run install -o root -g root -m 0644 "$tmp" "$BBR_SYSCTL_CONF"; then
    rm -f "$tmp"
    [ -z "$backup" ] || rm -f "$backup"
    return 1
  fi
  rm -f "$tmp"

  if ! run sysctl -p "$BBR_SYSCTL_CONF" || ! bbr_fq_enabled; then
    restore_bbr_fq "$backup" "$old_qdisc" "$old_cc" "$had_conf"
    die "$(t '启用 TCP BBR + FQ 失败，已恢复原配置' \
      'Failed to enable TCP BBR + FQ; the previous configuration was restored')"
    return 1
  fi
  if [ -z "$owned_mode" ]; then
    if [ "$had_conf" -eq 1 ]; then
      if ! install -d -o root -g root -m 0700 "$NOBRAND_STATE_DIR" \
         || ! install -o root -g root -m 0600 "$backup" "$BBR_BACKUP_FILE" \
         || ! write_bbr_state replaced "$old_qdisc" "$old_cc"; then
        rm -f "$BBR_STATE_FILE" "$BBR_BACKUP_FILE"
        restore_bbr_fq "$backup" "$old_qdisc" "$old_cc" "$had_conf"
        return 1
      fi
    elif ! write_bbr_state created "$old_qdisc" "$old_cc"; then
      rm -f "$BBR_STATE_FILE" "$BBR_BACKUP_FILE"
      restore_bbr_fq "$backup" "$old_qdisc" "$old_cc" "$had_conf"
      return 1
    fi
  fi
  [ -z "$backup" ] || rm -f "$backup"
  report_bbr_fq_status
}

offer_bbr_fq() {
  if bbr_fq_enabled; then
    t '检测到 TCP BBR + FQ 默认策略已配置，跳过写入' \
      'TCP BBR + FQ defaults are already configured; skipping file changes'
    report_bbr_fq_status
    return 0
  fi
  if [ "$ENABLE_BBR" -eq 1 ]; then
    enable_bbr_fq
  elif confirm '未检测到完整的 TCP BBR + FQ，是否现在启用？[Y/n]: ' \
    'TCP BBR + FQ are not fully enabled. Enable them now? [Y/n]: ' y; then
    enable_bbr_fq
  else
    t '已跳过 TCP BBR + FQ 配置' 'Skipped TCP BBR + FQ configuration'
  fi
}
