#!/usr/bin/env bash
# 本地/CI：Docker 冒烟（需本机已装 docker）
# 用法: bash scripts/docker-smoke.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && { pwd -W 2>/dev/null || pwd; })"
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
MITA_STATE=/tmp/install-state.env
printf "%s\n" "PORT=25000" "PORT_RANGE=" "PROTOCOL=TCP" "USERNAME=state-user" "PASSWORD=state-pass" >"$MITA_STATE"
USERNAME="" PASSWORD="" PORT="" PORT_RANGE="" PROTOCOL=TCP
USERNAME_CLI=0 PASSWORD_CLI=0 PORT_CLI=0 PORT_RANGE_CLI=0 PROTOCOL_CLI=0
load_install_state
test "$USERNAME|$PASSWORD|$PORT|$PROTOCOL" = "state-user|state-pass|25000|TCP"
require_root(){ :; }; require_linux(){ :; }; mita_installed(){ return 0; }
mita_bin(){ echo true; }; apply_config(){ :; }; start_mita(){ :; }
public_ip(){ echo 1.2.3.4; }; load_install_state(){ PROTOCOL=TCP; }
port_is_listening(){ return 1; }; mita_supports_traffic_pattern(){ return 1; }
install_users_scheduler(){ install_logrotate_config; harden_mita_permissions; }
service_manager(){ echo none; }; ensure_mita_daemon(){ :; }; wait_mita_socket(){ :; }
print_protocol_outputs(){ :; }
protocols_for_mode(){ echo TCP; }
proto_lower(){ echo tcp; }
USERNAME=alice PASSWORD=a PORT=26000 PROTOCOL=TCP TRAFFIC_PATTERN=off
MULTI_USER_MODE=0 DRY_RUN=0 YES=1 LANG_ZH=1 MENU_MODE=1
test "$(normalize_multiplexing off)" = "MULTIPLEXING_OFF"
test "$(normalize_multiplexing high)" = "MULTIPLEXING_HIGH"
test "$(normalize_handshake_mode no-wait)" = "HANDSHAKE_NO_WAIT"
test "$(normalize_handshake_mode standard)" = "HANDSHAKE_STANDARD"
test "$(normalize_low_entropy_mode off)" = "LOW_ENTROPY_MODE_OFF"
test "$(normalize_low_entropy_mode 56)" = "LOW_ENTROPY_MODE_56"
test "$(normalize_low_entropy_mode 48)" = "LOW_ENTROPY_MODE_48"
TRAFFIC_PATTERN=aggressive LOW_ENTROPY_MODE=LOW_ENTROPY_MODE_OFF TRAFFIC_SEED=42
mita_supports_traffic_pattern(){ return 0; }
mita_supports_low_entropy(){ return 0; }
tp=$(traffic_pattern_json)
echo "$tp" | grep -q "\"mode\": \"LOW_ENTROPY_MODE_OFF\""
LOW_ENTROPY_MODE=LOW_ENTROPY_MODE_56
tp=$(traffic_pattern_json)
echo "$tp" | grep -q "\"mode\": \"LOW_ENTROPY_MODE_56\""
compat_warning=$(warn_low_entropy_client_compat 2>&1)
echo "$compat_warning" | grep -q mihomo
TRAFFIC_PATTERN=off LOW_ENTROPY_MODE=LOW_ENTROPY_MODE_OFF
MULTIPLEXING=MULTIPLEXING_OFF HANDSHAKE_MODE=HANDSHAKE_NO_WAIT
link=$(generate_share_link_for 1.2.3.4 TCP)
echo "$link" | grep -q "^mierus://alice:a@1.2.3.4?"
! echo "$link" | grep -q "@1.2.3.4:26000"
echo "$link" | grep -q "port=26000"
echo "$link" | grep -q "protocol=TCP"
echo "$link" | grep -q "multiplexing=MULTIPLEXING_OFF"
echo "$link" | grep -q "handshake-mode=HANDSHAKE_NO_WAIT"
v6_link=$(generate_share_link_for 2001:db8::1 TCP)
echo "$v6_link" | grep -q "@\\[2001:db8::1\\]?"
bindings=$(extract_bindings_from_describe "{\"portBindings\":[{\"port\":26000,\"protocol\":\"TCP\"},{\"portRange\":\"26010-26020\",\"protocol\":\"UDP\"}]}")
echo "$bindings" | grep -qx "TCP|26000"
echo "$bindings" | grep -qx "UDP|26010-26020"
TRAFFIC_PATTERN=conservative TRAFFIC_SEED=42
json=$(build_client_json_for 1.2.3.4 TCP)
echo "$json" | grep -q "\"level\": \"MULTIPLEXING_OFF\""
echo "$json" | grep -q "\"handshakeMode\": \"HANDSHAKE_NO_WAIT\""
echo "$json" | grep -q "\"trafficPattern\""
python3 -c "import json,sys; assert json.load(sys.stdin)[\"profiles\"][0][\"trafficPattern\"][\"seed\"] == 42" <<<"$json"
USERNAME="user: with/slash" PASSWORD="p\"ass\\word"
json=$(build_client_json_for 1.2.3.4 TCP)
python3 -c "import json,sys; d=json.load(sys.stdin); assert d[\"profiles\"][0][\"user\"] == {\"name\":\"user: with/slash\",\"password\":\"p\\\"ass\\\\word\"}" <<<"$json"
yaml=$(build_clash_yaml_full 1.2.3.4)
grep -q "username: \"user: with/slash\"" <<<"$yaml"
grep -Fq "password: \"p\\\"ass\\\\word\"" <<<"$yaml"
USERNAME=alice PASSWORD=a
export_traffic_pattern_value(){ echo "CCoQARoECAEQCg=="; }
link=$(generate_share_link_for 1.2.3.4 TCP)
echo "$link" | grep -q "traffic-pattern=CCoQARoECAEQCg%3D%3D"
users_migrate_from_primary
USER_QUOTA_MODE=calendar USER_QUOTA_MB=1024 USER_BANDWIDTH_MBPS=10 USER_PACKAGE=custom
users_add bob b 26005 >/dev/null
USER_QUOTA_MODE=rolling USER_QUOTA_MB=0 USER_BANDWIDTH_MBPS=0 USER_PACKAGE=unlimited
users_add "path/name" c 26006 >/dev/null
harden_mita_permissions
test "$(users_count)" -eq 3
cp "$MITA_USERS_STATE" /tmp/overlap.json
python3 -c "import json; p='/tmp/overlap.json'; d=json.load(open(p)); d['users'][0]['port']=26000; d['users'][1]['port']=26001; json.dump(d,open(p,'w'))"
PROTOCOL=BOTH
if users_validate_state_file /tmp/overlap.json; then
  echo "overlapping BOTH ports accepted" >&2
  exit 1
fi
PROTOCOL=TCP
if parse_expire_date 2025-02-30 >/dev/null 2>&1; then
  echo "invalid calendar date accepted" >&2
  exit 1
fi
python3 -c "import json;d=json.load(open(\"/tmp/u.json\"));
[u.update({\"last_quota_reset\":\"2020-01\"}) for u in d[\"users\"] if u[\"name\"]==\"bob\"];
json.dump(d,open(\"/tmp/u.json\",\"w\"),indent=2)"
cal=$(users_scan_calendar_quota_reset || true)
echo "$cal" | grep -q bob
MITA_CLIENT_EXPORT_DIR=/tmp/clients
out=$(do_user_export_clients 2>/dev/null)
test -d "$out"
test -f "$out/path%2Fname_tcp.json"
test -f "$out/path%2Fname_links.txt"
test ! -d "$out/path"
before=$(sha256sum "$MITA_USERS_STATE" | awk "{print \$1}")
tx=$(users_tx_snapshot)
users_del "path/name" >/dev/null
apply_config(){ return 1; }
if apply_users_config "$tx" >/dev/null 2>&1; then
  echo "failed apply did not fail" >&2
  exit 1
fi
after=$(sha256sum "$MITA_USERS_STATE" | awk "{print \$1}")
test "$before" = "$after"
apply_config(){ :; }
admin_lock_acquire; admin_lock_acquire; admin_lock_release; admin_lock_release
if tc_available; then apply_tc_limits; tc qdisc show dev "$(tc_default_iface)" | grep -q htb; fi
do_doctor >/dev/null 2>&1 || true
tc_available(){ return 1; }
if apply_tc_limits >/dev/null 2>&1; then
  echo "active bandwidth limit succeeded without tc" >&2
  exit 1
fi
echo SMOKE_OK
'
echo "docker-smoke: PASS"
