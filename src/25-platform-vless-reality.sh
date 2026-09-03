# ---------- VLESS REALITY named-instance Xray services ----------

reality_systemd_unit() { printf 'nobrand-vless-reality@%s.service' "$1"; }
reality_openrc_service() { printf 'nobrand-vless-reality-%s' "$1"; }

reality_systemd_template_owned() {
  [ -f "$NOBRAND_REALITY_SYSTEMD_TEMPLATE" ] \
    && grep -qxF '# Managed by NoBrand-OneClick' "$NOBRAND_REALITY_SYSTEMD_TEMPLATE" \
    && grep -qxF "Environment=XRAY_LOCATION_ASSET=${NOBRAND_XRAY_ASSET_DIR}" \
      "$NOBRAND_REALITY_SYSTEMD_TEMPLATE" \
    && grep -qF "ExecStart=${NOBRAND_XRAY_BIN} run -c ${NOBRAND_REALITY_CONFIG_DIR}/%i/config.json" \
      "$NOBRAND_REALITY_SYSTEMD_TEMPLATE"
}

reality_openrc_service_owned() {
  local id="$1" path="${NOBRAND_REALITY_OPENRC_PREFIX}${1}"
  [ -f "$path" ] \
    && grep -qxF '# Managed by NoBrand-OneClick' "$path" \
    && grep -qxF "export XRAY_LOCATION_ASSET=\"${NOBRAND_XRAY_ASSET_DIR}\"" "$path" \
    && grep -qxF "command_args=\"run -c ${NOBRAND_REALITY_CONFIG_DIR}/${id}/config.json\"" "$path"
}

reality_remove_service_runtime_if_owned() {
  if [ -e "$NOBRAND_REALITY_SYSTEMD_TEMPLATE" ]; then
    reality_systemd_template_owned || {
      warn "$(t \
        "拒绝删除不属于 NoBrand 的 VLESS REALITY 服务模板: ${NOBRAND_REALITY_SYSTEMD_TEMPLATE}" \
        "Refusing to remove unowned VLESS REALITY service template: ${NOBRAND_REALITY_SYSTEMD_TEMPLATE}")"
      return 1
    }
    rm -f "$NOBRAND_REALITY_SYSTEMD_TEMPLATE" || return 1
  fi
}

reality_install_service_runtime() {
  local manager tmp
  manager="$(nb_service_manager)"
  case "$manager" in
    systemd)
      if [ -e "$NOBRAND_REALITY_SYSTEMD_TEMPLATE" ] \
         && ! reality_systemd_template_owned; then
        warn "$(t \
          "拒绝替换不属于 NoBrand 的 VLESS REALITY 服务模板: ${NOBRAND_REALITY_SYSTEMD_TEMPLATE}" \
          "Refusing to replace unowned VLESS REALITY service template: ${NOBRAND_REALITY_SYSTEMD_TEMPLATE}")"
        return 1
      fi
      tmp="$(mktemp_file .reality-service)" || return 1
      cat >"$tmp" <<EOF
# Managed by NoBrand-OneClick
[Unit]
Description=NoBrand VLESS REALITY instance %i
Documentation=https://github.com/ike-sh/NoBrand-OneClick
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
Environment=XRAY_LOCATION_ASSET=${NOBRAND_XRAY_ASSET_DIR}
ExecStart=${NOBRAND_XRAY_BIN} run -c ${NOBRAND_REALITY_CONFIG_DIR}/%i/config.json
Restart=on-failure
RestartSec=2
LimitNOFILE=1048576
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_BIND_SERVICE
NoNewPrivileges=true
PrivateTmp=true
ProtectHome=true
ProtectSystem=strict
ReadOnlyPaths=${NOBRAND_REALITY_CONFIG_DIR} ${NOBRAND_XRAY_BIN} ${NOBRAND_XRAY_ASSET_DIR}

[Install]
WantedBy=multi-user.target
EOF
      grep -qF "ExecStart=${NOBRAND_XRAY_BIN} run -c ${NOBRAND_REALITY_CONFIG_DIR}/%i/config.json" "$tmp" \
        && nb_atomic_install_file "$tmp" "$NOBRAND_REALITY_SYSTEMD_TEMPLATE" 0644 \
        || { rm -f "$tmp"; return 1; }
      rm -f "$tmp"
      systemctl daemon-reload
      ;;
    openrc) ;;
    *) return 1 ;;
  esac
}

reality_ensure_openrc_service() {
  local id="$1" path tmp
  [ "$(nb_service_manager)" = openrc ] || return 0
  path="${NOBRAND_REALITY_OPENRC_PREFIX}${id}"
  if [ -e "$path" ] && ! reality_openrc_service_owned "$id"; then
    warn "$(t "拒绝替换不属于 NoBrand 的 VLESS REALITY OpenRC 服务: ${path}" \
      "Refusing to replace unowned VLESS REALITY OpenRC service: ${path}")"
    return 1
  fi
  tmp="$(mktemp_file .reality-openrc)" || return 1
  cat >"$tmp" <<EOF
#!/sbin/openrc-run
# Managed by NoBrand-OneClick
name="NoBrand VLESS REALITY ${id}"
command="${NOBRAND_XRAY_BIN}"
command_args="run -c ${NOBRAND_REALITY_CONFIG_DIR}/${id}/config.json"
export XRAY_LOCATION_ASSET="${NOBRAND_XRAY_ASSET_DIR}"
command_background="yes"
pidfile="/run/nobrand-vless-reality-${id}.pid"
output_log="/var/log/nobrand-vless-reality-${id}.log"
error_log="/var/log/nobrand-vless-reality-${id}.err"
depend() { use net; after firewall; }
EOF
  nb_atomic_install_file "$tmp" "$path" 0755 || { rm -f "$tmp"; return 1; }
  rm -f "$tmp"
  rc-update add "$(reality_openrc_service "$id")" default >/dev/null 2>&1
}

reality_service_action() {
  local id="$1" action="$2" manager
  manager="$(nb_service_manager)"
  case "$manager" in
    systemd)
      [ "$action" != start ] \
        || systemctl enable "$(reality_systemd_unit "$id")" >/dev/null 2>&1
      [ "$action" != restart ] || systemctl daemon-reload
      systemctl "$action" "$(reality_systemd_unit "$id")"
      ;;
    openrc)
      reality_ensure_openrc_service "$id" || return 1
      rc-service "$(reality_openrc_service "$id")" "$action"
      ;;
    *) return 1 ;;
  esac
}

reality_service_active() {
  local id="$1"
  nb_service_is_active "$(reality_systemd_unit "$id")" "$(reality_openrc_service "$id")"
}

reality_service_pid() {
  local id="$1" manager pid_file
  manager="$(nb_service_manager)"
  case "$manager" in
    systemd) systemctl show -p MainPID --value "$(reality_systemd_unit "$id")" 2>/dev/null ;;
    openrc)
      pid_file="/run/nobrand-vless-reality-${id}.pid"
      [ -s "$pid_file" ] && cat "$pid_file"
      ;;
  esac
}

reality_listener_owned_by_service() {
  local id="$1" port="$2" expected pid
  expected="$(reality_service_pid "$id" 2>/dev/null || true)"
  [[ "$expected" =~ ^[0-9]+$ ]] && [ "$expected" -gt 1 ] || return 1
  while IFS= read -r pid; do
    [ "$pid" = "$expected" ] && return 0
  done < <(nb_port_listener_pids TCP "$port")
  return 1
}

reality_defender_listener_loopback_only() {
  local port="$1" details
  details="$(nb_port_listener_details TCP "$port" 2>/dev/null || true)"
  [ -n "$details" ] || return 1
  printf '%s\n' "$details" | awk -v port="$port" -v expected="127.0.0.1:${port}" '
    BEGIN { found=0 }
    {
      for (i=1; i<=NF; i++) {
        if ($i ~ (":" port "$") ) {
          if ($i != expected) exit 1
          found=1
          break
        }
      }
    }
    END { exit(found ? 0 : 1) }
  '
}

reality_defender_listener_owned_by_service() {
  local id="$1" port="$2"
  reality_defender_listener_loopback_only "$port" \
    && reality_listener_owned_by_service "$id" "$port"
}

reality_remove_service() {
  local id="$1" manager
  manager="$(nb_service_manager)"
  case "$manager" in
    systemd)
      reality_systemd_template_owned || return 1
      systemctl disable --now "$(reality_systemd_unit "$id")" >/dev/null 2>&1 || true
      ;;
    openrc)
      reality_openrc_service_owned "$id" || return 1
      rc-service "$(reality_openrc_service "$id")" stop >/dev/null 2>&1 || true
      rc-update del "$(reality_openrc_service "$id")" default >/dev/null 2>&1 || true
      rm -f "${NOBRAND_REALITY_OPENRC_PREFIX}${id}"
      ;;
  esac
}
