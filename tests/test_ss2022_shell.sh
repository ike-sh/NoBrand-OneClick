#!/usr/bin/env bash
# Drive the shipped parser, menu, instance selection, prompts and runtime adapter.
# Only daemon execution, manager installation, root provisioning and host I/O are fixtures.
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/testlib.sh"
fixture="$(mktemp -d)"
trap 'rm -rf -- "$fixture"' EXIT
export NOBRAND_SYSTEM_ROOT="$fixture/system" NOBRAND_STATE_DIR="$fixture/state" NOBRAND_CONFIG_DIR="$fixture/config" NOBRAND_LIB_DIR="$fixture/lib"
export NOBRAND_TEST_LOCAL_IPV4=192.0.2.192 NOBRAND_TEST_RANDOM_START=0
source_installer
mkdir -p "$NOBRAND_STATE_DIR/splicore/generations/test" "$NOBRAND_SYSTEM_ROOT"
jq -n '{architecture:"splicore-native",owner:"nobrand-splicore-v1",nodes:[{id:"ss-node",protocol:"ss2022",enabled:true,client:{name:"alpha"},document:{listener:{host:"127.0.0.1",port:45010},display_endpoint:{host:"edge.example",port:443},settings:{udp:true}}}]}' >"$NOBRAND_STATE_DIR/splicore/generations/test/desired.json"
ln -s generations/test "$NOBRAND_STATE_DIR/splicore/current"

# Input queue survives the actual per-action subshell and its error/lock wrapper.
queue="$fixture/queue"; log="$fixture/actions"; : >"$log"
read_tty() {
  local value
  IFS= read -r value <"$queue" || fail "scripted input exhausted at $1"
  sed -i '1d' "$queue"
  if [ "$1" = SS2022_KEY ]; then [ "${3:-}" = secret ] || fail 'key prompt must not echo'; fi
  printf -v "$1" '%s' "$value"
}
menu_pause() { :; }
require_root() { :; }
nobrand_install_manager_script() { :; }
nb_port_is_listening() { return 1; }
public_ip() { printf 192.0.2.10; }
nb_splicore_python() {
  local operation="$5" selector="${7:-}" key_set=auto
  [ "$1:$2:$3:$4" = 'protocol:--protocol:ss2022:--operation' ] || fail 'bad runtime CLI shape'
  [ "$#" -eq 5 ] || [ "$6" = --selector ] || fail 'bad runtime selector option'
  [ -z "${SS2022_KEY:-}" ] || key_set=provided
  printf '%s|%s|%s|%s|%s|%s|%s|%s|%s|%s\n' "$operation" "$selector" "$PORT" "${SS2022_METHOD:-}" "${SS2022_UDP:-}" "$key_set" "$ADVERTISE_HOST" "$ADVERTISE_PORT" "${NOBRAND_SPLICORE_EXPORT_FORMAT:-}" "${NOBRAND_SPLICORE_DISPLAY_PORT_POLICY:-}" >>"$log"
  if [ "$operation" = status ]; then
    jq -n '{nodes:[{id:"ss-node",name:"alpha",transport:"tcp",transports:["tcp","udp"],listener:{host:"127.0.0.1",port:45010},display_endpoint:{host:"edge.example",port:443},udp:true}]}'
  else
    printf '{}\n'
  fi
}

# All nine visible SS2022 actions, including the four service verbs and explicit export formats.
# The first selected port is automatic, the second manual and TCP-only; credentials are never logged.
secret_fixture="$(openssl rand -base64 32)"
printf '%s\n' 8 \
  1 fresh-one '' '' '' '' 2 custom.example 444 \
  1 fresh-two 2 2 "$secret_fixture" 45123 2 manual.example 445 \
  2 3 alpha 45020 4 alpha 2 revised.example 446 4 alpha 1 5 alpha '' \
  6 alpha 1 6 alpha 2 6 alpha 3 6 alpha 4 \
  7 alpha 1 7 alpha 2 7 alpha 3 7 alpha 4 8 alpha no 8 alpha yes 9 0 0 >"$queue"
nobrand_menu_loop >"$fixture/out" 2>&1
[ ! -s "$queue" ] || fail 'menu returned before consuming all choices'
assert_not_contains "$(<"$fixture/out")" "$secret_fixture" 'SS2022 interactive log redaction'
assert_not_contains "$(<"$fixture/out")" '操作未完成' 'all menu operations reached the adapter'
assert_contains "$(<"$fixture/out")" '/TCP+UDP' 'selected listener transport display'
expected_labels=$'  1) 创建节点\n  2) 查看节点\n  3) 修改真实监听端口\n  4) 修改客户端展示入口\n  5) 轮换密钥\n  6) 导出客户端配置\n  7) 服务管理\n  8) 删除节点\n  9) Doctor / 诊断\n  0) 返回'
assert_contains "$(<"$fixture/out")" "$expected_labels" 'SS2022 submenu numbers and Chinese labels'
assert_contains "$(<"$log")" 'install|fresh-one|19201|2022-blake3-aes-128-gcm|on|auto|custom.example|444||custom' 'install defaults and automatic port'
assert_contains "$(<"$log")" 'install|fresh-two|45123|2022-blake3-aes-256-gcm|off|provided|manual.example|445||custom' 'manual method, key, transport and port'
assert_contains "$(<"$log")" 'set-port|ss-node|45020|' 'selected real port mutation'
assert_contains "$(<"$log")" 'set-endpoint|ss-node||||auto|revised.example|446||custom' 'custom client endpoint mutation'
assert_contains "$(<"$log")" 'set-endpoint|ss-node||||auto|192.0.2.10|45010||follow-actual' 'automatic display endpoint follows actual port'
for action in rotate-key start stop restart remove; do
  assert_eq 1 "$(grep -c "^$action|ss-node|" "$log")" "exactly one $action on selected node"
done
for fmt in json uri mihomo sing-box; do
  grep -q "^export|ss-node|.*|$fmt|" "$log" || fail "export route for $fmt"
done
grep -q '^doctor||' "$log" || fail 'Doctor route'
printf '%s\n' 0 >"$queue"
LANG_ZH=0 ss2022_menu_loop >"$fixture/en"
assert_contains "$(<"$fixture/en")" $'  3) Change real listen port\n  4) Change client display endpoint\n  5) Rotate key' 'SS2022 English labels'

# CLI dispatch for existing named nodes (each invocation gets fresh option state).
cli() (
  export YES=1
  detect_nobrand_entry ss2022 "$@"; nb_splicore_route_main >/dev/null
  [ "$NOBRAND_SPLICORE_HANDLED" = 1 ] || fail 'protocol CLI bypassed the native route'
)
: >"$log"
for action in status show doctor start stop restart remove; do cli "$action" --name alpha; done
cli rotate-key --name alpha --key "$secret_fixture"
cli set-port --name alpha --port 45120
cli set-endpoint --name alpha --advertise-host cli.example --advertise-port 449
cli set-udp --name alpha --udp off
cli export --name alpha --format sing-box
for action in status show doctor start stop restart remove rotate-key set-port set-endpoint set-udp export; do
  grep -q "^$action|alpha|" "$log" || fail "CLI $action must select the named node"
done
assert_contains "$(<"$log")" 'set-port|alpha|45120|' 'CLI port'
assert_contains "$(<"$log")" 'set-udp|alpha|||off|' 'CLI UDP'
assert_contains "$(<"$log")" 'rotate-key|alpha||||provided|' 'CLI manual rotation'
assert_contains "$(<"$log")" 'set-endpoint|alpha||||auto|cli.example|449||custom' 'CLI custom display endpoint'
assert_contains "$(<"$log")" 'export|alpha||||auto|||sing-box|' 'CLI export format'

# Exercise the actual manager command with --dry-run, not just the option parser.
for method in 2022-blake3-aes-128-gcm 2022-blake3-aes-256-gcm 2022-blake3-chacha20-poly1305; do
  NOBRAND_STATE_DIR="$fixture/empty" bash "$TEST_ROOT/install-nobrand.sh" ss2022 install --name preview --method "$method" --udp off --port 45110 --advertise-host test.example --dry-run -y >"$fixture/plan"
  jq -e . "$fixture/plan" >/dev/null || fail 'runtime preview must be machine-readable'
done
NOBRAND_STATE_DIR="$fixture/empty" bash "$TEST_ROOT/install-nobrand.sh" ss2022 install --advertise-auto --dry-run -y >"$fixture/auto-plan"
jq -e . "$fixture/auto-plan" >/dev/null || fail 'default name, method, transports, key and port in preview'
for args in 'show' 'export' 'set-port --name alpha' 'set-udp --name alpha --udp invalid' 'remove' 'export --name alpha --format unsafe' 'status --key no'; do
  # shellcheck disable=SC2086
  if (detect_nobrand_entry ss2022 $args) >/dev/null 2>&1; then fail "invalid CLI accepted: $args"; fi
done
pass 'SS2022 CLI and bilingual menu, all nine actions, secure prompts, listener/display separation, dual transport and authenticated export choices'
