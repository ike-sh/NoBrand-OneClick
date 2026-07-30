#!/usr/bin/env bash
# 本地/CI：在干净 Debian 容器内验证配置输出、isolated-v2 事务、配额与 tc 所有权。
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && { pwd -W 2>/dev/null || pwd; })"

docker run --rm --cap-add=NET_ADMIN -v "$ROOT:/work:ro" debian:bookworm-slim bash -s <<'DOCKER_TEST'
set -Eeuo pipefail
apt-get update -qq >/dev/null
apt-get install -y -qq python3 bash util-linux iproute2 passwd >/dev/null
bash -n /work/install-mita.sh

export MITA_SOURCE_ONLY=1
export MITA_MANAGER_STATE_DIR=/tmp/manager-state
export MITA_STATE=/tmp/manager-state/install-state.env
export MITA_USERS_STATE=/tmp/manager-state/users.json MITA_USERS_LOCK=/tmp/manager-state/users.lock
export MITA_USERS_BACKUP_DIR=/tmp/manager-state/backups MITA_ADMIN_LOCK=/tmp/manager-state/admin.lock
export MITA_USERS_LOG=/tmp/users.log MITA_LOGROTATE_CONF=/tmp/logrotate.conf
export MITA_INSTANCES_DIR=/tmp/instances MITA_INSTANCE_RUN_DIR=/tmp/run
export MITA_INSTANCE_METRICS_DIR=/tmp/metrics
export MITA_INSTANCE_SYSTEMD_TEMPLATE=/tmp/mita-oneclick@.service
export MITA_INSTANCE_RUNNER=/tmp/mita-instance-run
export MITA_INSTANCE_OPENRC_PREFIX=/tmp/mita-oneclick-
export MITA_METRICS_FILE=/tmp/legacy-metrics.pb
export TC_OWNED_STATE=/tmp/manager-state/tc-owned.filters TC_IFACE=eth-test
export MITA_FIREWALL_OWNED_STATE=/tmp/manager-state/firewall-owned.bindings
export BBR_STATE_FILE=/tmp/manager-state/bbr-owned.state
export BBR_BACKUP_FILE=/tmp/manager-state/bbr-sysctl.backup
export USER_PORT_POOL_START=26000 USER_PORT_POOL_END=26020
export INSTALL_SCRIPT_PATH=/work/install-mita.sh QUOTA_RESET_METHOD=metrics
mkdir -p /tmp/manager-state/backups /tmp/instances /tmp/run /tmp/metrics /etc/logrotate.d
chmod 0700 /tmp/manager-state /tmp/manager-state/backups
getent group mita >/dev/null || groupadd --system mita
id mita >/dev/null 2>&1 || useradd --system -g mita -s /usr/sbin/nologin -d /tmp/metrics mita

source /work/install-mita.sh
trap - ERR
MITA_STATE=/tmp/manager-state/install-state.env

# 安装状态只允许从 root 所有且父目录不可写的常规文件读取。
(
  unsafe_dir=/tmp/unsafe-manager-state
  mkdir -p "$unsafe_dir"
  chmod 0777 "$unsafe_dir"
  printf 'USERNAME=unsafe-state-was-sourced\n' >"$unsafe_dir/install-state.env"
  chmod 0600 "$unsafe_dir/install-state.env"
  MITA_STATE="$unsafe_dir/install-state.env"
  USERNAME=unchanged
  if load_install_state >/dev/null 2>&1; then
    echo "unsafe install state unexpectedly accepted" >&2
    exit 1
  fi
  test "$USERNAME" != unsafe-state-was-sourced
)
(
  real_dir=/tmp/real-manager-state
  link_dir=/tmp/symlink-manager-state
  mkdir -p "$real_dir"
  chmod 0700 "$real_dir"
  ln -s "$real_dir" "$link_dir"
  printf 'USERNAME=symlink-state-was-sourced\n' >"$real_dir/install-state.env"
  chmod 0600 "$real_dir/install-state.env"
  MITA_STATE="$link_dir/install-state.env"
  USERNAME=unchanged
  if load_install_state >/dev/null 2>&1; then
    echo "state under symlink parent unexpectedly accepted" >&2
    exit 1
  fi
  test "$USERNAME" != symlink-state-was-sourced
)

# 旧版 root 状态可迁移；仅存在防火墙状态时也必须触发迁移。
(
  legacy=/tmp/legacy-manager-state
  current=/tmp/migrated-manager-state
  rm -rf "$legacy" "$current"
  mkdir -p "$legacy/backups"
  chmod 0755 "$legacy" "$legacy/backups"
  printf 'PORT=26008\nUSERNAME=migrated\n' >"$legacy/install-state.env"
  printf 'iptables|tcp|26008\n' >"$legacy/firewall-owned.bindings"
  printf '{"version":2,"users":[]}\n' >"$legacy/backups/users_manual.json"
  chmod 0600 "$legacy/install-state.env" "$legacy/firewall-owned.bindings" "$legacy/backups/users_manual.json"
  MITA_MANAGER_STATE_DIR="$current"
  MITA_LEGACY_STATE_DIR="$legacy"
  MITA_LEGACY_STATE="$legacy/install-state.env"
  MITA_LEGACY_USERS_STATE="$legacy/users.json"
  MITA_LEGACY_USERS_BACKUP_DIR="$legacy/backups"
  MITA_LEGACY_FIREWALL_STATE="$legacy/firewall-owned.bindings"
  MITA_LEGACY_TC_STATE="$legacy/tc-owned.filters"
  MITA_LEGACY_MARKER="$legacy/.mieru-oneclick"
  MITA_STATE="$current/install-state.env"
  MITA_USERS_STATE="$current/users.json"
  MITA_USERS_BACKUP_DIR="$current/backups"
  MITA_FIREWALL_OWNED_STATE="$current/firewall-owned.bindings"
  TC_OWNED_STATE="$current/tc-owned.filters"
  MITA_MARKER="$current/.installed"
  ensure_manager_state_layout
  grep -qx 'USERNAME=migrated' "$MITA_STATE"
  grep -qx 'iptables|tcp|26008' "$MITA_FIREWALL_OWNED_STATE"
  test -f "$MITA_USERS_BACKUP_DIR/users_manual.json"
  test ! -e "$MITA_LEGACY_STATE"
  test ! -e "$MITA_LEGACY_FIREWALL_STATE"
  test "$(stat -c %a "$current")" = 700
)
(
  legacy=/tmp/legacy-firewall-only
  current=/tmp/migrated-firewall-only
  rm -rf "$legacy" "$current"
  mkdir -p "$legacy"
  chmod 0755 "$legacy"
  printf 'iptables|tcp|26009\n' >"$legacy/firewall-owned.bindings"
  chmod 0600 "$legacy/firewall-owned.bindings"
  MITA_MANAGER_STATE_DIR="$current"
  MITA_LEGACY_STATE_DIR="$legacy"
  MITA_LEGACY_STATE="$legacy/install-state.env"
  MITA_LEGACY_USERS_STATE="$legacy/users.json"
  MITA_LEGACY_USERS_BACKUP_DIR="$legacy/backups"
  MITA_LEGACY_FIREWALL_STATE="$legacy/firewall-owned.bindings"
  MITA_LEGACY_TC_STATE="$legacy/tc-owned.filters"
  MITA_LEGACY_MARKER="$legacy/.mieru-oneclick"
  MITA_STATE="$current/install-state.env"
  MITA_USERS_STATE="$current/users.json"
  MITA_USERS_BACKUP_DIR="$current/backups"
  MITA_FIREWALL_OWNED_STATE="$current/firewall-owned.bindings"
  TC_OWNED_STATE="$current/tc-owned.filters"
  MITA_MARKER="$current/.installed"
  ensure_manager_state_layout
  grep -qx 'iptables|tcp|26009' "$MITA_FIREWALL_OWNED_STATE"
)

# 空实例集合不能在 ERR trap 中产生伪失败输出。
empty_stop_output="$(
  (
    set -Eeuo pipefail
    trap on_error ERR
    MITA_USERS_STATE=/tmp/no-users.json
    MITA_INSTANCES_DIR=/tmp/no-instances
    mkdir -p "$MITA_INSTANCES_DIR"
    isolated_stop_all
  ) 2>&1
)"
test -z "$empty_stop_output"

# 状态、默认客户端模式与 MTU 策略。
printf "%s\n" \
  "PORT=26000" "PORT_RANGE=" "PROTOCOL=TCP" "MTU=1452" "MTU_POLICY=custom" \
  "ADVERTISE_HOST=" "ADVERTISE_PORT=" \
  "USERNAME=alice" "PASSWORD=alice-pass" "TRAFFIC_PATTERN=off" \
  "LOW_ENTROPY_MODE=LOW_ENTROPY_MODE_OFF" \
  "MULTIPLEXING=MULTIPLEXING_OFF" "HANDSHAKE_MODE=HANDSHAKE_NO_WAIT" >"$MITA_STATE"
chmod 600 "$MITA_STATE"
load_install_state
test "$USERNAME|$PASSWORD|$PORT|$PROTOCOL|$MTU|$MTU_POLICY" = \
  "alice|alice-pass|26000|TCP|1452|custom"
test "$(normalize_multiplexing off)" = MULTIPLEXING_OFF
test "$(normalize_handshake_mode no-wait)" = HANDSHAKE_NO_WAIT
test "$(normalize_low_entropy_mode 56)" = LOW_ENTROPY_MODE_56
test "$(normalize_mtu_policy auto)" = optimized
! valid_mtu 1279
valid_mtu 1280
valid_mtu 1500
! valid_mtu 1501
valid_nonnegative_int32 2147483647
! valid_nonnegative_int32 2147483648
valid_bandwidth_mbps 1000000
! valid_bandwidth_mbps 1000001
valid_advertise_port 1
valid_advertise_port 443
valid_advertise_port 65535
! valid_advertise_port 0
! valid_advertise_port 65536
test "$(normalize_uint 00008)" = 8
ADVERTISE_HOST=203.0.113.10 ADVERTISE_PORT=443 PROTOCOL=TCP
validate_advertise_endpoint
PROTOCOL=BOTH
! validate_advertise_endpoint_values 203.0.113.10 65535 BOTH >/dev/null 2>&1
ADVERTISE_HOST="" ADVERTISE_PORT=""
PROTOCOL=TCP MTU=1500
calculate_optimized_mtu
test "$MTU|$MTU_POLICY" = "1400|optimized"
mtu_default_iface(){ echo eth-test; }
mtu_iface_value(){ echo 1500; }
mtu_route_family(){ echo IPv4; }
PROTOCOL=UDP
calculate_optimized_mtu
test "$MTU|$MTU_AUTO_LINK|$MTU_AUTO_OVERHEAD" = "1400|1500|28"

# trafficPattern、分享链接、官方客户端 JSON 与 mihomo YAML。
mita_supports_traffic_pattern(){ return 0; }
mita_supports_low_entropy(){ return 0; }
installed_version(){ echo 3.35.0; }
TRAFFIC_PATTERN=aggressive TRAFFIC_SEED=42 LOW_ENTROPY_MODE=LOW_ENTROPY_MODE_56
tp="$(traffic_pattern_json)"
grep -q '"unlockAll": false' <<<"$tp"
grep -q '"mode": "LOW_ENTROPY_MODE_56"' <<<"$tp"
compat_warning="$(warn_low_entropy_client_compat 2>&1)"
grep -q mihomo <<<"$compat_warning"
TRAFFIC_PATTERN=off LOW_ENTROPY_MODE=LOW_ENTROPY_MODE_OFF
PROTOCOL=TCP MTU=1400 MTU_POLICY=safe PORT=26000 USERNAME=alice PASSWORD=alice-pass
MULTIPLEXING=MULTIPLEXING_OFF HANDSHAKE_MODE=HANDSHAKE_NO_WAIT
link="$(generate_share_link_for 2001:db8::1 TCP)"
grep -q '^mierus://alice:alice-pass@\[2001:db8::1\]?' <<<"$link"
grep -q 'port=26000' <<<"$link"
grep -q 'mtu=1400' <<<"$link"
grep -q 'multiplexing=MULTIPLEXING_OFF' <<<"$link"
grep -q 'handshake-mode=HANDSHAKE_NO_WAIT' <<<"$link"
json="$(build_client_json_for 1.2.3.4 TCP)"
python3 -c 'import json,sys; d=json.load(sys.stdin); p=d["profiles"][0]; assert p["mtu"]==1400 and p["handshakeMode"]=="HANDSHAKE_NO_WAIT"' <<<"$json"
USERNAME='user: with/slash' PASSWORD='p"ass\word'
yaml="$(build_clash_yaml_full 1.2.3.4)"
grep -q 'username: "user: with/slash"' <<<"$yaml"
grep -Fq 'password: "p\"ass\\word"' <<<"$yaml"

# 自定义入口只改变客户端产物；服务端配置、防火墙提示仍使用真实监听端口。
USERNAME=alice PASSWORD=alice-pass PROTOCOL=TCP PORT=26000 PORT_RANGE=""
ADVERTISE_HOST=203.0.113.10 ADVERTISE_PORT=443
custom_link="$(generate_share_link_for "$ADVERTISE_HOST" TCP)"
grep -q '@203.0.113.10?' <<<"$custom_link"
grep -q 'port=443' <<<"$custom_link"
custom_json="$(build_client_json_for "$ADVERTISE_HOST" TCP)"
python3 -c 'import json,sys; d=json.load(sys.stdin); s=d["profiles"][0]["servers"][0]; assert s["ipAddress"]=="203.0.113.10" and s["portBindings"]==[{"port":443,"protocol":"TCP"}]' <<<"$custom_json"
ADVERTISE_PORT=08
leading_zero_json="$(build_client_json_for "$ADVERTISE_HOST" TCP)"
python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["profiles"][0]["servers"][0]["portBindings"][0]["port"]==8' <<<"$leading_zero_json"
ADVERTISE_PORT=443
custom_yaml="$(build_clash_yaml_full "$ADVERTISE_HOST")"
grep -q 'server: "203.0.113.10"' <<<"$custom_yaml"
grep -q 'port: 443' <<<"$custom_yaml"
compact_output="$(print_protocol_outputs "$ADVERTISE_HOST")"
grep -Eq '(已保存|Saved):[[:space:]]+/root/mieru_client_' <<<"$compact_output"
! grep -q '"profiles"' <<<"$compact_output"
test -n "$(find /root -maxdepth 1 -type f -name 'mieru_client_*.json' -print -quit)"
server_cfg="$(write_server_config)"
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d["portBindings"]==[{"port":26000,"protocol":"TCP"}] and "203.0.113.10" not in open(sys.argv[1]).read()' "$server_cfg"
rm -f "$server_cfg"
firewall_hint="$(cloud_firewall_hint)"
grep -q '26000/TCP' <<<"$firewall_hint"
! grep -q '443/TCP' <<<"$firewall_hint"
PROTOCOL=BOTH
grep -q 'port=443' <<<"$(generate_share_link_for "$ADVERTISE_HOST" TCP)"
grep -q 'port=444' <<<"$(generate_share_link_for "$ADVERTISE_HOST" UDP)"
ADVERTISE_HOST="" ADVERTISE_PORT="" PROTOCOL=TCP

# 安装交互默认保留自动探测；选择自定义时读取独立的展示 IP 和端口。
(
  ADVERTISE_HOST=198.51.100.1 ADVERTISE_PORT=1234 ADVERTISE_CLI=0
  confirm(){ return 1; }
  collect_advertise_endpoint_interactive >/dev/null
  test -z "$ADVERTISE_HOST"
  test -z "$ADVERTISE_PORT"
)
(
  ADVERTISE_HOST="" ADVERTISE_PORT="" ADVERTISE_CLI=0 PORT=26000 PROTOCOL=TCP
  confirm(){ return 0; }
  advertise_read_count=0
  read_tty(){
    advertise_read_count=$((advertise_read_count + 1))
    if [ "$advertise_read_count" -eq 1 ]; then
      printf -v "$1" '%s' 203.0.113.20
    else
      printf -v "$1" '%s' 8443
    fi
  }
  collect_advertise_endpoint_interactive >/dev/null
  test "$ADVERTISE_HOST|$ADVERTISE_PORT" = '203.0.113.20|8443'
)

# 端口探测必须区分 TCP/UDP；尾号段选择不得返回已监听端口。
python3 -c 'import socket,time; s=socket.socket(); s.bind(("127.0.0.1",26801)); s.listen(); time.sleep(20)' &
listener_pid=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do
  port_is_listening 26801 TCP && break
  sleep 0.1
done
port_is_listening 26801 TCP
! port_is_listening 26801 UDP
PROTOCOL=TCP
! port_available_for_mode 26801
kill "$listener_pid"
wait "$listener_pid" 2>/dev/null || true
port_available_for_mode 26801
(
  derive_port_base(){ echo 26800; }
  port_is_listening(){ [ "$1" -ne 26899 ]; }
  PROTOCOL=TCP
  test "$(derive_port_from_ip)" = 26899
)
# 自动端口在落盘前被抢占时应自动更换；显式端口则必须拒绝。
(
  PORT=26801 PROTOCOL=TCP PORT_AUTO_SELECTED=1
  port_available_for_mode(){ [ "$1" = 26802 ]; }
  select_available_port(){ echo 26802; }
  ensure_install_port_available >/dev/null
  test "$PORT" = 26802
)
if (
  PORT=26801 PROTOCOL=TCP PORT_AUTO_SELECTED=0
  port_available_for_mode(){ return 1; }
  ensure_install_port_available >/dev/null 2>&1
); then
  echo "explicit occupied port unexpectedly accepted" >&2
  exit 1
fi
(
  MITA_STATE=/tmp/no-install-state.env
  MITA_USERS_STATE=/tmp/no-users-state.json
  ! mita_preservable_config_exists
)

# 构造用户状态；正数 bandwidth 在专属实例模型中必须允许。
require_root(){ :; }
require_linux(){ :; }
mita_installed(){ return 0; }
install_users_scheduler(){ :; }
port_is_listening(){ return 1; }
public_ip(){ echo 1.2.3.4; }
USERNAME=alice PASSWORD=alice-pass PORT=26000 PROTOCOL=TCP
ADVERTISE_HOST=203.0.113.10 ADVERTISE_PORT=443
USER_QUOTA_MB=0 USER_QUOTA_DAYS=0 USER_QUOTA_MODE=rolling
USER_PACKAGE=unlimited USER_EXPIRE="" USER_BANDWIDTH_MBPS=0
users_migrate_from_primary
test "$(users_get_field alice advertise_host)|$(users_get_field alice advertise_port)" = '203.0.113.10|443'
USER_BANDWIDTH_MBPS=10 USER_PACKAGE=custom USER_QUOTA_MB=1024 USER_QUOTA_DAYS=30
users_add bob bob-pass 26005 >/dev/null
test "$(users_count)" -eq 2
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert all(u.get("instance_id","").startswith("u") for u in d["users"]); assert next(u for u in d["users"] if u["name"]=="bob")["bandwidth_mbps"]==10; assert not next(u for u in d["users"] if u["name"]=="bob")["advertise_host"]' "$MITA_USERS_STATE"

# flock 分支必须传递展示入口字段；重复入口及自定义/自动入口碰撞都应拒绝。
users_set_advertise_endpoint bob 198.51.100.20 8443
test "$(users_get_field bob advertise_host)|$(users_get_field bob advertise_port)" = '198.51.100.20|8443'
users_set_advertise_endpoint bob '' ''
conflict_state=/tmp/users-conflict.json
cp -f "$MITA_USERS_STATE" "$conflict_state"
python3 -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); u=next(x for x in d["users"] if x["name"]=="bob"); u.update({"advertise_host":"203.0.113.10","advertise_port":443}); json.dump(d,open(p,"w"),indent=2)' "$conflict_state"
if users_validate_state_file "$conflict_state" TCP 1.2.3.4; then
  echo "duplicate custom client endpoint unexpectedly accepted" >&2
  exit 1
fi
cp -f "$MITA_USERS_STATE" "$conflict_state"
python3 -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); u=next(x for x in d["users"] if x["name"]=="alice"); u.update({"advertise_host":"1.2.3.4","advertise_port":26005}); json.dump(d,open(p,"w"),indent=2)' "$conflict_state"
if users_validate_state_file "$conflict_state" TCP 1.2.3.4; then
  echo "custom/automatic client endpoint conflict unexpectedly accepted" >&2
  exit 1
fi
rm -f "$conflict_state" "$conflict_state.norm"

# 独立修改用户展示入口只更新状态，不应用或重启任何服务端实例。
(
  endpoint_state_dir=/tmp/endpoint-only-state
  rm -rf "$endpoint_state_dir"
  mkdir -p "$endpoint_state_dir"
  chmod 0700 "$endpoint_state_dir"
  MITA_STATE="$endpoint_state_dir/install-state.env"
  MITA_USERS_STATE="$endpoint_state_dir/users.json"
  MITA_USERS_LOCK="$endpoint_state_dir/users.lock"
  MITA_ADMIN_LOCK="$endpoint_state_dir/admin.lock"
  cp -f /tmp/manager-state/install-state.env "$MITA_STATE"
  cp -f /tmp/manager-state/users.json "$MITA_USERS_STATE"
  chmod 0600 "$MITA_STATE" "$MITA_USERS_STATE"
  apply_users_config(){ touch /tmp/endpoint-unexpected-apply; }
  instance_start_proxy(){ touch /tmp/endpoint-unexpected-start; }
  isolated_stop_all(){ touch /tmp/endpoint-unexpected-stop; }
  print_user_outputs(){ :; }
  rm -f /tmp/endpoint-unexpected-apply /tmp/endpoint-unexpected-start /tmp/endpoint-unexpected-stop
  USERNAME=bob ADVERTISE_HOST=198.51.100.30 ADVERTISE_PORT=9443 ADVERTISE_CLI=1
  do_user_set_endpoint >/dev/null
  test "$(users_get_field bob advertise_host)|$(users_get_field bob advertise_port)" = '198.51.100.30|9443'
  test ! -e /tmp/endpoint-unexpected-apply
  test ! -e /tmp/endpoint-unexpected-start
  test ! -e /tmp/endpoint-unexpected-stop
)

# 无 systemd 的容器中模拟实例控制，仅保留真实的单实例 JSON 生成和事务逻辑。
install_instance_runtime(){
  mkdir -p "$MITA_INSTANCES_DIR" "$MITA_INSTANCE_RUN_DIR" "$MITA_INSTANCE_METRICS_DIR"
  chown -R mita:mita "$MITA_INSTANCES_DIR" "$MITA_INSTANCE_RUN_DIR" "$MITA_INSTANCE_METRICS_DIR"
}
instance_ensure_openrc_service(){ :; }
default_mita_stop(){ :; }
default_mita_restore(){ :; }
FAIL_INSTANCE_ONCE=0
instance_start_proxy(){
  if [ "$FAIL_INSTANCE_ONCE" -eq 1 ]; then
    FAIL_INSTANCE_ONCE=0
    return 1
  fi
  return 0
}
instance_daemon_stop(){ :; }
instance_cmd(){
  local iid="$1" cmd="$2"
  case "$cmd" in
    status) echo 'mita server status is "RUNNING"' ;;
    get) echo "metrics ${iid}" ;;
    export) echo CCoQARoECAEQCg== ;;
    *) : ;;
  esac
}
harden_mita_permissions(){ :; }
TC_LOG=/tmp/tc.log
: >"$TC_LOG"
TC_FAIL_ONCE=0
tc(){
  printf '%s\n' "$*" >>"$TC_LOG"
  case "$*" in
    "qdisc show"*) echo 'qdisc clsact ffff: dev eth-test' ;;
    *"filter add"*)
      if [ "$TC_FAIL_ONCE" -eq 1 ]; then TC_FAIL_ONCE=0; return 1; fi
      ;;
  esac
  return 0
}
apply_users_config
test "$(users_deployment_model)" = isolated-v2
python3 - <<'PY'
import glob,json
files=glob.glob("/tmp/instances/*/server.json")
assert len(files)==2
for path in files:
    d=json.load(open(path))
    assert len(d["users"])==1
    assert len(d["portBindings"])==1
    assert "trafficPattern" not in d
PY
TRAFFIC_PATTERN=conservative TRAFFIC_SEED=42 LOW_ENTROPY_MODE=LOW_ENTROPY_MODE_OFF
apply_users_config
python3 -c 'import glob,json; assert all("trafficPattern" in json.load(open(p)) for p in glob.glob("/tmp/instances/*/server.json"))'
TRAFFIC_PATTERN=off
apply_users_config
python3 -c 'import glob,json; assert all("trafficPattern" not in json.load(open(p)) for p in glob.glob("/tmp/instances/*/server.json"))'

# 改端口不能改变实例 ID，也不能丢失专属 metrics。
bob_id="$(users_get_field bob instance_id)"
mkdir -p "$(instance_metrics_dir "$bob_id")"
printf bob-usage >"$(instance_metrics_file "$bob_id")"
_U_NAME=bob _U_PORT=26006 users_py_locked '
import json,os
p=os.environ["MITA_USERS_STATE"]; d=json.load(open(p))
next(u for u in d["users"] if u["name"]==os.environ["_U_NAME"])["port"]=int(os.environ["_U_PORT"])
json.dump(d,open(p,"w"),indent=2)
'
apply_users_config
test "$(users_get_field bob instance_id)" = "$bob_id"
grep -q bob-usage "$(instance_metrics_file "$bob_id")"
python3 -c 'import json,glob; p=glob.glob("/tmp/instances/*/server.json"); d=next(json.load(open(x)) for x in p if json.load(open(x))["users"][0]["name"]=="bob"); assert d["portBindings"][0]["port"]==26006'

# 应用失败必须恢复 users.json，并能重新生成旧实例配置。
before="$(sha256sum "$MITA_USERS_STATE" | awk '{print $1}')"
tx="$(users_tx_snapshot)"
users_del bob >/dev/null
FAIL_INSTANCE_ONCE=1
if apply_users_config "$tx" >/dev/null 2>&1; then
  echo "failed instance reconcile unexpectedly succeeded" >&2
  exit 1
fi
after="$(sha256sum "$MITA_USERS_STATE" | awk '{print $1}')"
test "$before" = "$after"
users_name_exists bob
grep -q bob-usage "$(instance_metrics_file "$bob_id")"
# apply 已消费回滚快照；外层重复调用必须幂等且不再报回滚失败。
users_tx_rollback "$tx" 0

# 不在状态中的实例数据只能在事务提交阶段清理。
orphan_id=u0000000000000001
mkdir -p "$MITA_INSTANCES_DIR/$orphan_id" "$(instance_metrics_dir "$orphan_id")"
printf orphan-usage >"$(instance_metrics_file "$orphan_id")"
orphan_tx="$(users_tx_snapshot)"
users_tx_commit "$orphan_tx"
test ! -d "$(instance_metrics_dir "$orphan_id")"
test ! -d "$MITA_INSTANCES_DIR/$orphan_id"

# 恢复必须采用备份内协议，并同时更新实例配置与 install-state。
cp -f "$MITA_USERS_STATE" /tmp/users-import.json
python3 -c 'import json; p="/tmp/users-import.json"; d=json.load(open(p)); d["protocol"]="UDP"; json.dump(d,open(p,"w"),indent=2)'
users_restore_from_file /tmp/users-import.json >/dev/null
test "$PROTOCOL" = UDP
grep -qx 'PROTOCOL=UDP' "$MITA_STATE"
python3 - <<'PY'
import glob,json
for path in glob.glob("/tmp/instances/*/server.json"):
    d=json.load(open(path))
    assert {x["protocol"] for x in d["portBindings"]} == {"UDP"}
PY
python3 -c 'import json; p="/tmp/users-import.json"; d=json.load(open(p)); d["protocol"]="INVALID"; json.dump(d,open(p,"w"),indent=2)'
if users_restore_from_file /tmp/users-import.json >/dev/null 2>&1; then
  echo "invalid imported protocol unexpectedly succeeded" >&2
  exit 1
fi

# calendar 只清 bob 的 metrics，不影响 alice。
alice_id="$(users_get_field alice instance_id)"
mkdir -p "$(instance_metrics_dir "$alice_id")" "$(instance_metrics_dir "$bob_id")"
printf alice-usage >"$(instance_metrics_file "$alice_id")"
printf bob-usage >"$(instance_metrics_file "$bob_id")"
python3 -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); u=next(x for x in d["users"] if x["name"]=="bob"); u.update({"quota_mode":"calendar","quota_mb":1024,"quota_days":30,"last_quota_reset":"2020-01"}); json.dump(d,open(p,"w"),indent=2)' "$MITA_USERS_STATE"
cal="$(users_scan_calendar_quota_reset)"
grep -qx bob <<<"$cal"
test ! -e "$(instance_metrics_file "$bob_id")"
grep -q alice-usage "$(instance_metrics_file "$alice_id")"

# 菜单路径传入的目标账号不能被 load_install_state 覆盖成主账号。
USERNAME=bob USER_PACKAGE=unlimited USER_QUOTA_MB="" USER_QUOTA_DAYS=""
USER_QUOTA_MODE=rolling USER_EXPIRE="" USER_BANDWIDTH_MBPS=""
do_user_set_quota >/dev/null
test "$(users_get_field bob quota_mb)" = 0

# 使用假 tc 验证仅管理保留 pref 的 filter，失败会恢复旧 manifest，且从不删除 qdisc。
: >"$TC_LOG"
PROTOCOL=TCP
apply_tc_limits
test -s "$TC_OWNED_STATE"
! grep -Eq 'qdisc (del|replace)|root handle' "$TC_LOG"
tc_before="$(sha256sum "$TC_OWNED_STATE" | awk '{print $1}')"
TC_FAIL_ONCE=1
if apply_tc_limits >/dev/null 2>&1; then
  echo "injected tc failure unexpectedly succeeded" >&2
  exit 1
fi
tc_after="$(sha256sum "$TC_OWNED_STATE" | awk '{print $1}')"
test "$tc_before" = "$tc_after"
! grep -Eq 'qdisc (del|replace)|root handle' "$TC_LOG"

# 防火墙只删除带所有权记录的规则；预先存在的同端口规则不得接管或删除。
MITA_FIREWALL_OWNED_STATE=/tmp/firewall-owned.bindings
FW_LOG=/tmp/firewall.log
: >"$FW_LOG"
IPT_PREEXIST=0
IPT_OWNED_EXISTS=0
IPT_DELETE_FAIL=0
iptables(){
  printf 'v4 %s\n' "$*" >>"$FW_LOG"
  case "$*" in
    "-C "*"--comment"*) [ "$IPT_OWNED_EXISTS" -eq 1 ] && return 0 || return 1 ;;
    "-C "*) [ "$IPT_PREEXIST" -eq 1 ] && return 0 || return 1 ;;
    "-I "*"--comment"*) IPT_OWNED_EXISTS=1; return 0 ;;
    "-D "*"--comment"*)
      [ "$IPT_DELETE_FAIL" -eq 1 ] && return 1
      IPT_OWNED_EXISTS=0
      return 0
      ;;
  esac
  return 0
}
ip6tables(){
  printf 'v6 %s\n' "$*" >>"$FW_LOG"
  case "$*" in
    "-C "*"--comment"*) [ "$IPT_OWNED_EXISTS" -eq 1 ] && return 0 || return 1 ;;
    "-C "*) [ "$IPT_PREEXIST" -eq 1 ] && return 0 || return 1 ;;
    "-I "*"--comment"*) IPT_OWNED_EXISTS=1; return 0 ;;
    "-D "*"--comment"*)
      [ "$IPT_DELETE_FAIL" -eq 1 ] && return 1
      IPT_OWNED_EXISTS=0
      return 0
      ;;
  esac
  return 0
}
iptables_accept_port 28000 tcp add
test "$(wc -l <"$MITA_FIREWALL_OWNED_STATE")" -eq 2
grep -q -- '--comment mieru-oneclick' "$FW_LOG"
iptables_accept_port 28000 tcp del
test ! -e "$MITA_FIREWALL_OWNED_STATE"
: >"$FW_LOG"
IPT_PREEXIST=1
iptables_accept_port 28001 tcp add
test ! -e "$MITA_FIREWALL_OWNED_STATE"
! grep -q ' -I ' "$FW_LOG"
iptables_accept_port 28001 tcp del
! grep -q ' -D ' "$FW_LOG"
# 删除失败时必须保留所有权清单并让卸载失败；重试成功后才能清掉清单。
IPT_PREEXIST=0
IPT_OWNED_EXISTS=1
IPT_DELETE_FAIL=1
printf 'iptables|tcp|28002\nip6tables|tcp|28002\n' >"$MITA_FIREWALL_OWNED_STATE"
if firewall_clear_all_owned >/dev/null 2>&1; then
  echo "failed firewall cleanup unexpectedly succeeded" >&2
  exit 1
fi
test "$(wc -l <"$MITA_FIREWALL_OWNED_STATE")" -eq 2
IPT_DELETE_FAIL=0
firewall_clear_all_owned
test ! -e "$MITA_FIREWALL_OWNED_STATE"

# 全部用户同时到期必须停掉全部实例，不能因“最后一个用户”保护而回滚为继续可用。
today="$(date +%F)"
python3 -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); [u.update({"enabled":True,"expire_at":sys.argv[2]}) for u in d["users"]]; json.dump(d,open(p,"w"),indent=2)' "$MITA_USERS_STATE" "$today"
expired="$(users_scan_expired)"
grep -qx alice <<<"$expired"
grep -qx bob <<<"$expired"
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d["users"] and not any(u["enabled"] for u in d["users"])' "$MITA_USERS_STATE"
python3 -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); next(u for u in d["users"] if u["name"]=="alice")["expire_at"]=""; json.dump(d,open(p,"w"),indent=2)' "$MITA_USERS_STATE"
USER_SHOW_NAME=alice
do_user_enable >/dev/null
test "$(users_get_field alice enabled)" = 1
grep -qx 'USERNAME=alice' "$MITA_STATE"
grep -qx 'ADVERTISE_HOST=203.0.113.10' "$MITA_STATE"
grep -qx 'ADVERTISE_PORT=443' "$MITA_STATE"

# 静态安全边界：双栈防火墙、私有 metrics 挂载和稳定实例环境变量。
grep -q 'for ipt in iptables ip6tables' /work/install-mita.sh
grep -q 'BindPaths=.*MITA_INSTANCE_METRICS_DIR' /work/install-mita.sh
grep -q 'MITA_CONFIG_JSON_FILE=' /work/install-mita.sh
grep -q 'MITA_UDS_PATH=' /work/install-mita.sh
grep -Fq 'run chown root:mita "$MITA_INSTANCES_DIR"' /work/install-mita.sh
! grep -q 'enable_tcp_bbr.py' /work/install-mita.sh
perm_root=/tmp/instance-permission
mkdir -p "$perm_root/u0000000000000002"
chown root:mita "$perm_root"
chown mita:mita "$perm_root/u0000000000000002"
chmod 0750 "$perm_root" "$perm_root/u0000000000000002"
printf '{}' >"$perm_root/u0000000000000002/server.json"
chown mita:mita "$perm_root/u0000000000000002/server.json"
chmod 0600 "$perm_root/u0000000000000002/server.json"
setpriv --reuid=mita --regid=mita --init-groups \
  test -r "$perm_root/u0000000000000002/server.json"

# BBR + FQ 已完整启用时不询问；缺项时回车默认执行本地配置。
(
  bbr_fq_enabled(){ return 0; }
  confirm(){ touch /tmp/bbr-unexpected-confirm; return 1; }
  enable_bbr_fq(){ touch /tmp/bbr-unexpected-enable; }
  rm -f /tmp/bbr-unexpected-confirm /tmp/bbr-unexpected-enable
  offer_bbr_fq >/dev/null
  test ! -e /tmp/bbr-unexpected-confirm
  test ! -e /tmp/bbr-unexpected-enable
)
(
  bbr_fq_enabled(){ return 1; }
  read_tty(){ printf -v "$1" '%s' ''; }
  enable_bbr_fq(){ touch /tmp/bbr-default-enable; }
  rm -f /tmp/bbr-default-enable
  ENABLE_BBR=0 YES=0
  offer_bbr_fq >/dev/null
  test -e /tmp/bbr-default-enable
)

# 本地实现写入固定 sysctl；卸载只恢复脚本接管的文件和运行值。
(
  BBR_SYSCTL_CONF=/tmp/mieru_tcp_bbr.conf
  BBR_STATE_FILE=/tmp/manager-state/bbr-created.state
  BBR_BACKUP_FILE=/tmp/manager-state/bbr-created.backup
  test_qdisc=pfifo_fast
  test_cc=cubic
  sysctl(){
    case "${1:-}|${2:-}" in
      '-n|net.core.default_qdisc') printf '%s\n' "$test_qdisc" ;;
      '-n|net.ipv4.tcp_congestion_control') printf '%s\n' "$test_cc" ;;
      '-n|net.ipv4.tcp_available_congestion_control') printf '%s\n' 'reno cubic bbr' ;;
      '-p|'*) test_qdisc=fq; test_cc=bbr ;;
      '-q|-w')
        case "${3:-}" in
          net.core.default_qdisc=*) test_qdisc="${3#*=}" ;;
          net.ipv4.tcp_congestion_control=*) test_cc="${3#*=}" ;;
        esac
        ;;
      *) return 1 ;;
    esac
  }
  modprobe(){ :; }
  rm -f "$BBR_SYSCTL_CONF" "$BBR_STATE_FILE" "$BBR_BACKUP_FILE"
  enable_bbr_fq >/dev/null
  bbr_fq_enabled
  grep -qx 'net.core.default_qdisc=fq' "$BBR_SYSCTL_CONF"
  grep -qx 'net.ipv4.tcp_congestion_control=bbr' "$BBR_SYSCTL_CONF"
  grep -qx created "$BBR_STATE_FILE"
  restore_owned_bbr_fq
  test ! -e "$BBR_SYSCTL_CONF"
  test ! -e "$BBR_STATE_FILE"
  test "$test_qdisc|$test_cc" = 'pfifo_fast|cubic'
)
(
  BBR_SYSCTL_CONF=/tmp/mieru_tcp_bbr-existing.conf
  BBR_STATE_FILE=/tmp/manager-state/bbr-replaced.state
  BBR_BACKUP_FILE=/tmp/manager-state/bbr-replaced.backup
  test_qdisc=fq_codel
  test_cc=cubic
  sysctl(){
    case "${1:-}|${2:-}" in
      '-n|net.core.default_qdisc') printf '%s\n' "$test_qdisc" ;;
      '-n|net.ipv4.tcp_congestion_control') printf '%s\n' "$test_cc" ;;
      '-n|net.ipv4.tcp_available_congestion_control') printf '%s\n' 'reno cubic bbr' ;;
      '-p|'*)
        while IFS='=' read -r key value; do
          case "$key" in
            net.core.default_qdisc) test_qdisc="$value" ;;
            net.ipv4.tcp_congestion_control) test_cc="$value" ;;
          esac
        done <"${2:-$BBR_SYSCTL_CONF}"
        ;;
      '-q|-w')
        case "${3:-}" in
          net.core.default_qdisc=*) test_qdisc="${3#*=}" ;;
          net.ipv4.tcp_congestion_control=*) test_cc="${3#*=}" ;;
        esac
        ;;
      *) return 1 ;;
    esac
  }
  modprobe(){ :; }
  rm -f "$BBR_STATE_FILE" "$BBR_BACKUP_FILE"
  printf '%s\n' 'net.core.default_qdisc=fq_codel' '# keep this original file' >"$BBR_SYSCTL_CONF"
  original_hash="$(sha256sum "$BBR_SYSCTL_CONF" | awk '{print $1}')"
  enable_bbr_fq >/dev/null
  grep -qx replaced "$BBR_STATE_FILE"
  restore_owned_bbr_fq
  test "$(sha256sum "$BBR_SYSCTL_CONF" | awk '{print $1}')" = "$original_hash"
  test "$test_qdisc|$test_cc" = 'fq_codel|cubic'
  test ! -e "$BBR_STATE_FILE"
)
(
  BBR_SYSCTL_CONF=/tmp/mieru_tcp_bbr-external.conf
  BBR_STATE_FILE=/tmp/manager-state/bbr-external.state
  BBR_BACKUP_FILE=/tmp/manager-state/bbr-external.backup
  printf '%s\n' 'net.core.default_qdisc=fq' 'net.ipv4.tcp_congestion_control=bbr' >"$BBR_SYSCTL_CONF"
  write_bbr_state created pfifo_fast cubic
  printf '%s\n' '# changed by administrator' 'net.core.default_qdisc=fq_codel' >"$BBR_SYSCTL_CONF"
  if restore_owned_bbr_fq >/dev/null 2>&1; then
    echo "externally modified BBR config unexpectedly overwritten during uninstall" >&2
    exit 1
  fi
  grep -qx '# changed by administrator' "$BBR_SYSCTL_CONF"
  test -e "$BBR_STATE_FILE"
  rm -f "$BBR_SYSCTL_CONF" "$BBR_STATE_FILE" "$BBR_BACKUP_FILE"
)
(
  BBR_SYSCTL_CONF=/tmp/mieru_tcp_bbr-uninstall-guard.conf
  BBR_STATE_FILE=/tmp/manager-state/bbr-uninstall-guard.state
  BBR_BACKUP_FILE=/tmp/manager-state/bbr-uninstall-guard.backup
  printf '%s\n' 'net.core.default_qdisc=fq' 'net.ipv4.tcp_congestion_control=bbr' >"$BBR_SYSCTL_CONF"
  write_bbr_state created pfifo_fast cubic
  printf '%s\n' '# changed by administrator' >"$BBR_SYSCTL_CONF"
  mita_uninstall_target_present(){ return 0; }
  installed_by_oneclick(){ return 0; }
  confirm(){ return 0; }
  stop_mita_for_uninstall(){ touch /tmp/bbr-guard-unexpected-stop; }
  rm -f /tmp/bbr-guard-unexpected-stop
  set +e
  (set -Eeuo pipefail; do_uninstall >/dev/null 2>&1)
  guarded_uninstall_rc=$?
  set -e
  test "$guarded_uninstall_rc" -ne 0
  test ! -e /tmp/bbr-guard-unexpected-stop
  rm -f "$BBR_SYSCTL_CONF" "$BBR_STATE_FILE" "$BBR_BACKUP_FILE"
)
(
  BBR_SYSCTL_CONF=/tmp/mieru_tcp_bbr-unmanaged.conf
  BBR_STATE_FILE=/tmp/manager-state/bbr-unmanaged.state
  BBR_BACKUP_FILE=/tmp/manager-state/bbr-unmanaged.backup
  printf '%s\n' 'net.core.default_qdisc=fq' >"$BBR_SYSCTL_CONF"
  rm -f "$BBR_STATE_FILE" "$BBR_BACKUP_FILE"
  restore_owned_bbr_fq
  test -e "$BBR_SYSCTL_CONF"
  rm -f "$BBR_SYSCTL_CONF"
)
(
  bbr_fq_enabled(){ return 0; }
  tc_default_iface(){ echo eth-test; }
  tc(){ echo 'qdisc fq 8001: root refcnt 2 limit 10000p buckets 1024 orphan_mask 1023'; }
  bbr_fq_active
  tc(){ echo 'qdisc fq_codel 0: root refcnt 2 limit 10240p'; }
  ! bbr_fq_active
)

# 菜单动作首个错误即停止；dry-run 不触碰持久化状态。
set +e
menu_probe="$(
  (
    set -Eeuo pipefail
    trap 'exit $?' ERR
    do_status(){ false; echo MENU_SHOULD_NOT_CONTINUE; }
    ACTION=status
    menu_run_action
  ) 2>&1
)"
menu_rc=$?
set -e
test "$menu_rc" -ne 0
! grep -q MENU_SHOULD_NOT_CONTINUE <<<"$menu_probe"
# 用户管理 18 在主菜单上下文返回专用码，外层应立即重绘主菜单；独立调用则正常结束。
set +e
(
  MAIN_MENU_ACTIVE=1
  read_tty(){ printf -v "$1" '%s' 18; }
  do_user_manage >/dev/null
)
user_back_rc=$?
set -e
test "$user_back_rc" -eq 3
(
  MAIN_MENU_ACTIVE=0
  read_tty(){ printf -v "$1" '%s' 18; }
  do_user_manage >/dev/null
)
# 覆盖外层 menu_loop：用户管理返回码 3 必须直接重绘，不能落到 menu_pause。
(
  menu_show_count=0
  mita_installed(){ return 1; }
  show_menu(){
    menu_show_count=$((menu_show_count + 1))
    if [ "$menu_show_count" -eq 1 ]; then
      ACTION=user-manage
      return 0
    fi
    return 2
  }
  read_tty(){ printf -v "$1" '%s' 18; }
  menu_pause(){ touch /tmp/user-back-extra-pause; }
  rm -f /tmp/user-back-extra-pause
  menu_loop >/dev/null
  test ! -e /tmp/user-back-extra-pause
)
# 卸载成功通过特殊返回码退出菜单；用户取消则留在菜单且不报错。
set +e
(
  do_uninstall(){ UNINSTALL_CANCELLED=0; }
  ACTION=uninstall
  menu_run_action
)
uninstall_menu_rc=$?
set -e
test "$uninstall_menu_rc" -eq 2
(
  do_uninstall(){ UNINSTALL_CANCELLED=1; }
  ACTION=uninstall
  menu_run_action
)
rm -f /tmp/dry-run-mutated
do_install(){ touch /tmp/dry-run-mutated; }
repair_mita_binary_paths(){ touch /tmp/dry-run-mutated; }
ACTION=install DRY_RUN=1
main >/tmp/dry-run.out
test ! -e /tmp/dry-run-mutated
grep -q DRY-RUN /tmp/dry-run.out

# 在无软件包、只有 OneClick 残留的半安装状态下也能完整卸载并给出父 shell 提示。
mkdir -p /etc/mita /etc/profile.d
touch "$MITA_MARKER" "$MITA_PROFILE_D"
YES=1 DRY_RUN=0
set +e
uninstall_output="$(do_uninstall 2>&1)"
uninstall_rc=$?
set -e
if [ "$uninstall_rc" -ne 0 ]; then
  printf '%s\n' "$uninstall_output" >&2
  exit "$uninstall_rc"
fi
grep -q '完全卸载' <<<"$uninstall_output"
grep -q 'unset -f mita' <<<"$uninstall_output"
! grep -q '\[错误\]' <<<"$uninstall_output"
test ! -e "$MITA_PROFILE_D"

echo SMOKE_OK
DOCKER_TEST
echo "docker-smoke: PASS"
