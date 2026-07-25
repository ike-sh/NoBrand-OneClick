#!/usr/bin/env bash
# 本地/CI：Docker 冒烟（需本机已装 docker）
# 用法: bash scripts/docker-smoke.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
docker run --rm --cap-add=NET_ADMIN -v "$ROOT:/work:ro" debian:bookworm-slim bash -c '
set -e
apt-get update -qq >/dev/null
apt-get install -y -qq python3 bash util-linux iproute2 >/dev/null
export MITA_SOURCE_ONLY=1
export MITA_USERS_STATE=/tmp/u.json MITA_USERS_LOCK=/tmp/u.lock
export MITA_USERS_BACKUP_DIR=/tmp/backups MITA_ADMIN_LOCK=/tmp/a.lock
export MITA_USERS_LOG=/tmp/u.log MITA_LOGROTATE_CONF=/tmp/lr.conf
export USER_PORT_POOL_START=26000 USER_PORT_POOL_END=26020
export INSTALL_SCRIPT_PATH=/work/install-mita.sh QUOTA_RESET_METHOD=days
mkdir -p /tmp/backups /etc/logrotate.d
source /work/install-mita.sh
trap - ERR; set +e; set -e
require_root(){ :; }; require_linux(){ :; }; mita_installed(){ return 0; }
mita_bin(){ echo true; }; apply_config(){ :; }; start_mita(){ :; }
public_ip(){ echo 1.2.3.4; }; load_install_state(){ PROTOCOL=TCP; }
port_is_listening(){ return 1; }; mita_supports_traffic_pattern(){ return 1; }
install_users_scheduler(){ install_logrotate_config; harden_mita_permissions; }
service_manager(){ echo none; }; ensure_mita_daemon(){ :; }; wait_mita_socket(){ :; }
print_protocol_outputs(){ :; }; build_clash_yaml_full(){ echo proxies:; }
build_client_json_for(){ echo "{\"u\":\"$USERNAME\"}"; }
generate_share_link_for(){ echo link; }; protocols_for_mode(){ echo TCP; }
proto_lower(){ echo tcp; }
USERNAME=alice PASSWORD=a PORT=26000 PROTOCOL=TCP TRAFFIC_PATTERN=off
MULTI_USER_MODE=0 DRY_RUN=0 YES=1 LANG_ZH=1 MENU_MODE=1
users_migrate_from_primary
USER_QUOTA_MODE=calendar USER_QUOTA_MB=1024 USER_BANDWIDTH_MBPS=10 USER_PACKAGE=custom
users_add bob b 26005 >/dev/null
harden_mita_permissions
test "$(users_count)" -eq 2
python3 -c "import json;d=json.load(open(\"/tmp/u.json\"));
[u.update({\"last_quota_reset\":\"2020-01\"}) for u in d[\"users\"] if u[\"name\"]==\"bob\"];
json.dump(d,open(\"/tmp/u.json\",\"w\"),indent=2)"
cal=$(users_scan_calendar_quota_reset || true)
echo "$cal" | grep -q bob
MITA_CLIENT_EXPORT_DIR=/tmp/clients
out=$(do_user_export_clients 2>/dev/null)
test -d "$out"
admin_lock_acquire; admin_lock_acquire; admin_lock_release; admin_lock_release
if tc_available; then apply_tc_limits; tc qdisc show dev "$(tc_default_iface)" | grep -q htb; fi
do_doctor >/dev/null 2>&1 || true
echo SMOKE_OK
'
echo "docker-smoke: PASS"
