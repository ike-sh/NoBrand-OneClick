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
export MITA_STATE=/tmp/install-state.env
export MITA_USERS_STATE=/tmp/users.json MITA_USERS_LOCK=/tmp/users.lock
export MITA_USERS_BACKUP_DIR=/tmp/backups MITA_ADMIN_LOCK=/tmp/admin.lock
export MITA_USERS_LOG=/tmp/users.log MITA_LOGROTATE_CONF=/tmp/logrotate.conf
export MITA_INSTANCES_DIR=/tmp/instances MITA_INSTANCE_RUN_DIR=/tmp/run
export MITA_INSTANCE_METRICS_DIR=/tmp/metrics
export MITA_INSTANCE_SYSTEMD_TEMPLATE=/tmp/mita-oneclick@.service
export MITA_INSTANCE_RUNNER=/tmp/mita-instance-run
export MITA_INSTANCE_OPENRC_PREFIX=/tmp/mita-oneclick-
export MITA_METRICS_FILE=/tmp/legacy-metrics.pb
export TC_OWNED_STATE=/tmp/tc-owned.filters TC_IFACE=eth-test
export USER_PORT_POOL_START=26000 USER_PORT_POOL_END=26020
export INSTALL_SCRIPT_PATH=/work/install-mita.sh QUOTA_RESET_METHOD=metrics
mkdir -p /tmp/backups /tmp/instances /tmp/run /tmp/metrics /etc/logrotate.d
getent group mita >/dev/null || groupadd --system mita
id mita >/dev/null 2>&1 || useradd --system -g mita -s /usr/sbin/nologin -d /tmp/metrics mita

source /work/install-mita.sh
trap - ERR
MITA_STATE=/tmp/install-state.env

# 状态、默认客户端模式与 MTU 策略。
printf "%s\n" \
  "PORT=26000" "PORT_RANGE=" "PROTOCOL=TCP" "MTU=1452" "MTU_POLICY=custom" \
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

# 构造用户状态；正数 bandwidth 在专属实例模型中必须允许。
require_root(){ :; }
require_linux(){ :; }
mita_installed(){ return 0; }
install_users_scheduler(){ :; }
port_is_listening(){ return 1; }
public_ip(){ echo 1.2.3.4; }
USERNAME=alice PASSWORD=alice-pass PORT=26000 PROTOCOL=TCP
USER_QUOTA_MB=0 USER_QUOTA_DAYS=0 USER_QUOTA_MODE=rolling
USER_PACKAGE=unlimited USER_EXPIRE="" USER_BANDWIDTH_MBPS=0
users_migrate_from_primary
USER_BANDWIDTH_MBPS=10 USER_PACKAGE=custom USER_QUOTA_MB=1024 USER_QUOTA_DAYS=30
users_add bob bob-pass 26005 >/dev/null
test "$(users_count)" -eq 2
python3 -c 'import json; d=json.load(open("/tmp/users.json")); assert all(u.get("instance_id","").startswith("u") for u in d["users"]); assert next(u for u in d["users"] if u["name"]=="bob")["bandwidth_mbps"]==10'

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
python3 -c 'import json; p="/tmp/users.json"; d=json.load(open(p)); u=next(x for x in d["users"] if x["name"]=="bob"); u.update({"quota_mode":"calendar","quota_mb":1024,"quota_days":30,"last_quota_reset":"2020-01"}); json.dump(d,open(p,"w"),indent=2)'
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
iptables(){
  printf 'v4 %s\n' "$*" >>"$FW_LOG"
  case "$*" in
    "-C "*"--comment"*) return 1 ;;
    "-C "*) [ "$IPT_PREEXIST" -eq 1 ] && return 0 || return 1 ;;
  esac
  return 0
}
ip6tables(){
  printf 'v6 %s\n' "$*" >>"$FW_LOG"
  case "$*" in
    "-C "*"--comment"*) return 1 ;;
    "-C "*) [ "$IPT_PREEXIST" -eq 1 ] && return 0 || return 1 ;;
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

# 全部用户同时到期必须停掉全部实例，不能因“最后一个用户”保护而回滚为继续可用。
today="$(date +%F)"
python3 -c 'import json,sys; p="/tmp/users.json"; d=json.load(open(p)); [u.update({"enabled":True,"expire_at":sys.argv[1]}) for u in d["users"]]; json.dump(d,open(p,"w"),indent=2)' "$today"
expired="$(users_scan_expired)"
grep -qx alice <<<"$expired"
grep -qx bob <<<"$expired"
python3 -c 'import json; d=json.load(open("/tmp/users.json")); assert d["users"] and not any(u["enabled"] for u in d["users"])'
python3 -c 'import json; p="/tmp/users.json"; d=json.load(open(p)); next(u for u in d["users"] if u["name"]=="alice")["expire_at"]=""; json.dump(d,open(p,"w"),indent=2)'
USER_SHOW_NAME=alice
do_user_enable >/dev/null
test "$(users_get_field alice enabled)" = 1
grep -qx 'USERNAME=alice' "$MITA_STATE"

# 静态安全边界：双栈防火墙、私有 metrics 挂载和稳定实例环境变量。
grep -q 'for ipt in iptables ip6tables' /work/install-mita.sh
grep -q 'BindPaths=.*MITA_INSTANCE_METRICS_DIR' /work/install-mita.sh
grep -q 'MITA_CONFIG_JSON_FILE=' /work/install-mita.sh
grep -q 'MITA_UDS_PATH=' /work/install-mita.sh

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
rm -f /tmp/dry-run-mutated
do_install(){ touch /tmp/dry-run-mutated; }
repair_mita_binary_paths(){ touch /tmp/dry-run-mutated; }
ACTION=install DRY_RUN=1
main >/tmp/dry-run.out
test ! -e /tmp/dry-run-mutated
grep -q DRY-RUN /tmp/dry-run.out

echo SMOKE_OK
DOCKER_TEST
echo "docker-smoke: PASS"
