# ---------- Common egress interface lookup for BBR status ----------

tc_default_iface() {
  local dev=""
  if [ -n "${TC_IFACE:-}" ]; then
    printf '%s' "$TC_IFACE"
    return 0
  fi
  if command -v ip >/dev/null 2>&1; then
    dev="$(ip route 2>/dev/null | awk '/^default/{print $5; exit}')"
    [ -n "$dev" ] || dev="$(ip -br link 2>/dev/null | awk '$1!="lo"{print $1; exit}' | cut -d@ -f1)"
  fi
  printf '%s' "$dev"
}
