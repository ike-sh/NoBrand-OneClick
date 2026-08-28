# ---------- NoBrand VLESS Sudoku isolated Xray service ----------

nobrand_write_vless_sudoku_service() {
  local manager tmp
  manager="$(nb_service_manager)"
  case "$manager" in
    systemd)
      tmp="$(mktemp_file .service)" || return 1
      cat >"$tmp" <<EOF
# Managed by NoBrand-OneClick
[Unit]
Description=NoBrand Plain VLESS FinalMask Sudoku (Xray-core)
Documentation=https://github.com/ike-sh/NoBrand-OneClick
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=${NOBRAND_VLESS_CONFIG_DIR}
ExecStart=${NOBRAND_XRAY_BIN} run -c ${NOBRAND_VLESS_CONFIG_FILE}
Restart=on-failure
RestartSec=5
LimitNOFILE=1048576
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_BIND_SERVICE
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full
ProtectHome=true
ReadWritePaths=${NOBRAND_VLESS_CONFIG_DIR} ${NOBRAND_VLESS_STATE_DIR}

[Install]
WantedBy=multi-user.target
EOF
      grep -qF "ExecStart=${NOBRAND_XRAY_BIN} run -c ${NOBRAND_VLESS_CONFIG_FILE}" "$tmp" \
        || { rm -f "$tmp"; return 1; }
      install -m 0644 "$tmp" "${NOBRAND_VLESS_SYSTEMD_SERVICE}.new" \
        && mv -f "${NOBRAND_VLESS_SYSTEMD_SERVICE}.new" "$NOBRAND_VLESS_SYSTEMD_SERVICE" \
        || { rm -f "$tmp" "${NOBRAND_VLESS_SYSTEMD_SERVICE}.new"; return 1; }
      rm -f "$tmp"
      systemctl daemon-reload || return 1
      systemctl enable "$NOBRAND_VLESS_SERVICE_NAME" >/dev/null 2>&1
      ;;
    openrc)
      tmp="$(mktemp_file .openrc)" || return 1
      cat >"$tmp" <<EOF
#!/sbin/openrc-run
# Managed by NoBrand-OneClick
name="NoBrand Plain VLESS FinalMask Sudoku"
description="NoBrand Plain VLESS FinalMask Sudoku (Xray-core)"
command="${NOBRAND_XRAY_BIN}"
command_args="run -c ${NOBRAND_VLESS_CONFIG_FILE}"
command_background=true
pidfile="/run/nobrand-vless-sudoku.pid"
output_log="/var/log/nobrand-vless-sudoku.log"
error_log="/var/log/nobrand-vless-sudoku.err"
depend() { use net; after firewall; }
EOF
      install -m 0755 "$tmp" "${NOBRAND_VLESS_OPENRC_SERVICE}.new" \
        && mv -f "${NOBRAND_VLESS_OPENRC_SERVICE}.new" "$NOBRAND_VLESS_OPENRC_SERVICE" \
        || { rm -f "$tmp" "${NOBRAND_VLESS_OPENRC_SERVICE}.new"; return 1; }
      rm -f "$tmp"
      rc-update add "$NOBRAND_VLESS_SERVICE_NAME" default >/dev/null 2>&1
      ;;
    *) return 1 ;;
  esac
}

nobrand_vless_sudoku_service_action() {
  local action="$1" manager
  manager="$(nb_service_manager)"
  case "$manager" in
    systemd)
      [ "$action" != restart ] || systemctl daemon-reload
      systemctl "$action" "$NOBRAND_VLESS_SERVICE_NAME"
      ;;
    openrc) rc-service "$NOBRAND_VLESS_SERVICE_NAME" "$action" ;;
    *) return 1 ;;
  esac
}

nobrand_vless_sudoku_service_active() {
  nb_service_is_active "$NOBRAND_VLESS_SERVICE_NAME" "$NOBRAND_VLESS_SERVICE_NAME"
}

nobrand_remove_vless_sudoku_service() {
  local manager
  manager="$(nb_service_manager)"
  nobrand_vless_sudoku_service_action stop >/dev/null 2>&1 || true
  case "$manager" in
    systemd)
      systemctl disable "$NOBRAND_VLESS_SERVICE_NAME" >/dev/null 2>&1 || true
      rm -f "$NOBRAND_VLESS_SYSTEMD_SERVICE"
      systemctl daemon-reload 2>/dev/null || true
      ;;
    openrc)
      rc-update del "$NOBRAND_VLESS_SERVICE_NAME" default >/dev/null 2>&1 || true
      rm -f "$NOBRAND_VLESS_OPENRC_SERVICE"
      ;;
  esac
}
