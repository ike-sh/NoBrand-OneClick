#!/usr/bin/env bash
# 由 compat-smoke.sh 在各发行版容器内调用；只验证不需要 init/firewall 权限的兼容边界。
set -Eeuo pipefail

bash -n /work/install-mita.sh
export MITA_SOURCE_ONLY=1
# shellcheck source=install-mita.sh
source /work/install-mita.sh
trap - ERR

test "$SCRIPT_VERSION" = 1.3.0
test "$SCRIPT_NAME|$SCRIPT_REPO" = 'NoBrand-OneClick|ike-sh/NoBrand-OneClick'
case "$(detect_pkg_manager)" in
  deb|rpm|alpine) ;;
  *) echo "unsupported package-manager detection" >&2; exit 1 ;;
esac

apply_profile_values iplc
test "$PROFILE|$PROTOCOL|$MTU|$TRAFFIC_PATTERN|$LOW_ENTROPY_MODE" = \
  'iplc|TCP|1400|off|LOW_ENTROPY_MODE_OFF'
apply_profile_values balanced
test "$(infer_profile_from_values)" = balanced
MTU=1390
profile_reconcile_metadata
test "$PROFILE" = custom

valid_advertise_host 203.0.113.10
valid_advertise_host 2001:db8::1
valid_advertise_host cm-entry.example.com
if valid_advertise_host 'https://cm-entry.example.com'; then
  echo 'URL unexpectedly accepted as advertise host' >&2
  exit 1
fi

PORT=17353 ADVERTISE_HOST=192.236.242.173 ADVERTISE_PORT=17353
if client_endpoint_is_independent 192.236.242.173; then
  echo 'same public endpoint unexpectedly treated as independent' >&2
  exit 1
fi
PORT=30000 ADVERTISE_HOST=cm-entry.example.com ADVERTISE_PORT=10086
client_endpoint_is_independent 192.236.242.173

installed_version(){ echo 3.35.0; }
mita_supports_traffic_pattern(){ return 0; }
mita_supports_low_entropy(){ return 0; }
USERNAME=compat PASSWORD=compat-pass PROTOCOL=TCP PORT=30000 PORT_RANGE=""
MTU=1400 MTU_POLICY=safe PROFILE=iplc TRAFFIC_PATTERN=off TRAFFIC_SEED=""
LOW_ENTROPY_MODE=LOW_ENTROPY_MODE_OFF
MULTIPLEXING=MULTIPLEXING_OFF HANDSHAKE_MODE=HANDSHAKE_NO_WAIT
ADVERTISE_HOST=cm-entry.example.com ADVERTISE_PORT=10086

link="$(generate_share_link_for "$ADVERTISE_HOST" TCP)"
grep -q '@cm-entry.example.com?' <<<"$link"
grep -q 'port=10086' <<<"$link"
json="$(build_client_json_for "$ADVERTISE_HOST" TCP)"
python3 -c 'import json,sys; s=json.load(sys.stdin)["profiles"][0]["servers"][0]; assert s["ipAddress"]=="" and s["domainName"]=="cm-entry.example.com" and s["portBindings"][0]["port"]==10086' <<<"$json"
yaml="$(build_clash_yaml_full "$ADVERTISE_HOST")"
grep -q 'server: "cm-entry.example.com"' <<<"$yaml"
grep -q 'port: 10086' <<<"$yaml"
cfg="$(write_server_config)"
python3 -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); raw=open(p).read(); assert d["portBindings"]==[{"port":30000,"protocol":"TCP"}] and "cm-entry.example.com" not in raw and "10086" not in raw' "$cfg"
rm -f "$cfg"

echo "compat-case: PASS ($(detect_pkg_manager))"
