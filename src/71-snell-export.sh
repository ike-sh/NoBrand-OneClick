# ---------- Snell client exports (Surge / Mihomo / sing-box) ----------

snell_client_values() {
  local id="$1" name major psk endpoint host port
  name="$(snell_state_field "$id" name)"
  major="$(snell_state_field "$id" version)"
  case "$major" in 4|5) ;; *) return 1 ;; esac
  psk="$(snell_state_field "$id" psk)"
  endpoint="$(snell_effective_endpoint "$id")"
  host="${endpoint%%|*}"; port="${endpoint#*|}"
  printf '%s\t%s\t%s\t%s\t%s\n' "$name" "$major" "$psk" "$host" "$port"
}

snell_export_surge() {
  local id="$1" name major psk host port values
  values="$(snell_client_values "$id")" || return 1
  IFS=$'\t' read -r name major psk host port <<<"$values"
  printf '%s = snell, %s, %s, psk = %s, version = %s' "$name" "$host" "$port" "$psk" "$major"
  printf '\n'
}

snell_export_mihomo() {
  local id="$1" name major psk host port values
  values="$(snell_client_values "$id")" || return 1
  IFS=$'\t' read -r name major psk host port <<<"$values"
  case "$major" in
    4|5) ;;
    *) return 1 ;;
  esac
  jq -n --arg name "$name" --arg server "$host" --arg port "$port" --arg psk "$psk" --arg version "$major" -r '
    "- name: " + ($name|tojson) + "\n" +
    "  type: snell\n" +
    "  server: " + ($server|tojson) + "\n" +
    "  port: " + $port + "\n" +
    "  psk: " + ($psk|tojson) + "\n" +
    "  version: " + $version + "\n" +
    "  udp: true"
  '
}

snell_export_singbox() {
  local id="$1" name major psk host port singbox_version values
  values="$(snell_client_values "$id")" || return 1
  IFS=$'\t' read -r name major psk host port <<<"$values"
  case "$major" in
    4) singbox_version=4 ;;
    # 官方 v5 未启用 QUIC Proxy Mode 时与 v4 client wire protocol 兼容；
    # sing-box >=1.14 当前 outbound 用 version=4 表达该兼容语义。
    5) singbox_version=4 ;;
    *) return 1 ;;
  esac
  jq -n --arg tag "$name" --arg server "$host" --arg port "$port" --arg psk "$psk" \
    --arg version "$singbox_version" --arg major "$major" '
      {
        type:"snell",
        tag:$tag,
        server:$server,
        server_port:($port|tonumber),
        version:($version|tonumber),
        psk:$psk
      }
    '
}

snell_print_client_exports() {
  local id="$1" major
  major="$(snell_state_field "$id" version)"
  msg '========================================'
  msg 'Surge'
  msg '========================================'
  snell_export_surge "$id"
  msg ''
  msg '========================================'
  msg 'Mihomo'
  msg '========================================'
  snell_export_mihomo "$id"
  if [ "$major" = 5 ]; then
    msg '说明：udp: true 是 Mihomo 普通 Snell UDP relay 能力；官方 v5 QUIC Proxy Mode 为 NOT VERIFIED。'
  fi
  msg ''
  msg '========================================'
  msg 'sing-box'
  msg '========================================'
  snell_export_singbox "$id"
  if [ "$major" = 5 ]; then
    msg '说明：sing-box version=4 对应 Snell v5 未启用 QUIC Proxy Mode 时的上游兼容语义。'
    msg '说明：sing-box 不支持官方 Snell v5 QUIC Proxy Mode（CLIENT_UNSUPPORTED）。'
  fi
}
