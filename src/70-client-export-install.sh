urlencode() {
  local value="$1"
  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$value"
    return 0
  fi
  if [[ "$value" =~ ^[a-zA-Z0-9._~-]+$ ]]; then
    printf '%s' "$value"
    return 0
  fi
  die "$(t '密码含特殊字符时需要 python3 以生成节点链接' \
    'python3 required to encode special characters in share link')"
}

url_host() {
  local host="$1"
  if [[ "$host" == *:* ]] && [[ "$host" != \[*\] ]]; then
    printf '[%s]' "$host"
  else
    printf '%s' "$host"
  fi
}

nb_render_client_profiles() {
  nb_client_profiles_python "${NOBRAND_STATE_DIR}/splicore/current/desired.json" "${LANG_ZH:-1}"
}
