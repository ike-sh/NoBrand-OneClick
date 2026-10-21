# ---------- 阶段4：备份 / 恢复 / 导出导入 / 管理锁 ----------

open_firewall_for_pairs() {
  local pairs="$1"
  local fw="" pp proto p proto_lc failed=0
  [ -n "$pairs" ] || return 0
  if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q 'Status: active'; then
    fw=ufw
  elif command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
    fw=firewalld
  elif command -v iptables >/dev/null 2>&1; then
    fw=iptables
  else
    return 0
  fi
  while IFS= read -r pp; do
    [ -n "$pp" ] || continue
    proto="${pp%%|*}"
    p="${pp#*|}"
    proto_lc="$(proto_lower "$proto")"
    firewall_apply_binding "$fw" add "$proto_lc" "$p" || failed=1
  done <<< "$pairs"
  case "$fw" in
    firewalld) run firewall-cmd --reload || failed=1 ;;
    iptables) persist_iptables_rules || failed=1 ;;
  esac
  [ "$failed" -eq 0 ]
}
