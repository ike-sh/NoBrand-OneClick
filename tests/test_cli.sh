#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/testlib.sh"

parse() {
  local argv0="$1"
  shift
  bash -c '
    set -euo pipefail
    MITA_SOURCE_ONLY=1
    installer="$1"
    shift
    source "$installer"
    printf "%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s\n" "$ACTION" "${SNELL_ACTION:-}" "${SNELL_VERSION:-}" "${SNELL_NAME:-}" "${HY2_ACTION:-}" "${VLESS_SUDOKU_ACTION:-}" "${YES:-0}" "${ADVERTISE_AUTO_REQUESTED:-0}" "${SNELL_QUIC_PROXY:-}" "${SNELL_QUIC_CLI:-0}" "${TUIC_ACTION:-}" "${TUIC_NAME:-}" "${TUIC_USER:-}" "${SSH_TUNNEL_ACTION:-}" "${SSH_TUNNEL_USER:-}"
  ' "$argv0" "$TEST_ROOT/install-nobrand.sh" "$@"
}
parse_forward() {
  bash -c '
    set -euo pipefail
    MITA_SOURCE_ONLY=1
    installer="$1"
    shift
    source "$installer"
    printf "%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s\n" \
      "$ACTION" "$FORWARD_ACTION" "$FORWARD_NAME" "$FORWARD_BACKEND" "$FORWARD_PROTOCOL" \
      "$FORWARD_LISTEN_HOST" "$FORWARD_LISTEN_PORT" "$FORWARD_TARGET_HOST" "$FORWARD_TARGET_PORT" \
      "$ADVERTISE_HOST" "$ADVERTISE_PORT"
  ' test "$TEST_ROOT/install-nobrand.sh" "$@"
}
parse_reality() {
  bash -c '
    set -euo pipefail
    MITA_SOURCE_ONLY=1
    installer="$1"
    shift
    source "$installer"
    printf "%s|%s|%s|%s|%s|%s\n" \
      "$ACTION" "$VLESS_REALITY_ACTION" "$VLESS_REALITY_NAME" \
      "$VLESS_REALITY_TARGET" "$VLESS_REALITY_TARGET_PORT" "$INGRESS_PROFILE"
  ' test "$TEST_ROOT/install-nobrand.sh" "$@"
}

assert_cli_error_text() {
  local expected="$1" forbidden="$2" output=""
  shift 2
  if output="$(bash "$TEST_ROOT/install-nobrand.sh" "$@" 2>&1)"; then
    fail "CLI parser unexpectedly accepted: $*"
  fi
  assert_contains "$output" "$expected" "localized CLI error: $*"
  assert_not_contains "$output" "$forbidden" "removed English CLI error wording: $*"
}

export TEST_ROOT
cli_fixture="$(mktemp -d)"
trap 'rm -rf -- "$cli_fixture"' EXIT

assert_contains "$(parse nobrand status)" 'nobrand-status|' 'canonical nobrand status'
assert_contains "$(parse install-nobrand.sh status)" 'nobrand-status|' 'NoBrand unified status'
assert_contains "$(parse install-nobrand.sh uninstall -y)" 'nobrand-uninstall|' 'NoBrand uninstall routing'
assert_contains "$(parse install-nobrand.sh manager upgrade)" 'nobrand-manager-upgrade|' 'NoBrand manager-only upgrade routing'
assert_contains "$(parse install-nobrand.sh manager install)" 'nobrand-manager-upgrade|' 'NoBrand manager-only install routing'
assert_contains "$(parse install-nobrand.sh mieru users)" 'user-list|' 'NoBrand Mieru delegation'
snell="$(parse install-nobrand.sh snell install --name alice --version 5 --port 3611 --advertise-auto -y)"
assert_eq 'nobrand-snell|install|5|alice|||1|1||0|||||' "$snell" 'Snell CLI parser default QUIC'
snell_quic="$(parse install-nobrand.sh snell install --name alice --version 5 --port 3611 --quic on --advertise-auto -y)"
assert_eq 'nobrand-snell|install|5|alice|||1|1|on|1|||||' "$snell_quic" 'Snell CLI parser QUIC ON'
snell_toggle="$(parse install-nobrand.sh snell set-quic --name alice --quic off -y)"
assert_eq 'nobrand-snell|set-quic|5|alice|||1|0|off|1|||||' "$snell_toggle" 'Snell CLI QUIC toggle'
hy2="$(parse install-nobrand.sh hy2 install --port 3612 --sni www.microsoft.com --advertise-auto -y)"
assert_eq 'nobrand-hy2||5||install||1|1||0|||||' "$hy2" 'HY2 CLI parser'
vless="$(parse install-nobrand.sh vless-sudoku install --port 3613 --advertise-auto -y)"
assert_eq 'nobrand-vless-sudoku||5|||install|1|1||0|||||' "$vless" 'VLESS Sudoku CLI parser'
alias_vless="$(parse install-nobrand.sh sudoku smoke)"
assert_eq 'nobrand-vless-sudoku||5|||smoke|0|0||0|||||' "$alias_vless" 'Sudoku canonical-backend alias'
reality="$(parse_reality vless-reality install --name public --target example.com \
  --target-port 443 --ingress-profile Japan-Public --port 32052 --advertise-auto -y)"
assert_eq 'nobrand-vless-reality|install|public|example.com|443|Japan-Public' "$reality" \
  'VLESS REALITY CLI parser'
reality_defaults="$(parse_reality vless-reality install --name defaults \
  --ingress-profile Japan-Public --port 32053 --advertise-auto -y)"
assert_eq 'nobrand-vless-reality|install|defaults||443|Japan-Public' "$reality_defaults" \
  'VLESS REALITY CLI parser accepts omitted camouflage host and port defaults'
reality_alias="$(parse_reality reality export --name public)"
assert_eq 'nobrand-vless-reality|export|public||443|' "$reality_alias" 'REALITY canonical alias'

tuic="$(parse install-nobrand.sh tuic install --name primary --user alice --port 3614 --sni www.microsoft.com --advertise-auto -y)"
assert_eq 'nobrand-tuic||5||||1|1||0|install|primary|alice||' "$tuic" 'TUIC CLI parser'
tuic_user="$(parse install-nobrand.sh tuic user rotate --name primary --user alice)"
assert_eq 'nobrand-tuic||5||||0|0||0|user-rotate|primary|alice||' "$tuic_user" 'TUIC user CLI parser'
ssh_tunnel="$(parse install-nobrand.sh ssh install --user alice --advertise-host entry.example.com --advertise-port 443 -y)"
assert_eq 'nobrand-ssh-tunnel||5||||1|0||0||||install|alice' "$ssh_tunnel" 'SSH Tunnel CLI parser'
ssh_user="$(parse install-nobrand.sh ssh user rotate-key --user alice)"
assert_eq 'nobrand-ssh-tunnel||5||||0|0||0||||user-rotate-key|alice' "$ssh_user" 'SSH Tunnel user CLI parser'
forward="$(parse_forward forward add --name edge --backend realm --protocol BOTH --listen 0.0.0.0 \
  --port 3615 --target relay.example.test --target-port 443 \
  --advertise-host edge.example.test --advertise-port 8443)"
assert_eq 'nobrand-forward|add|edge|realm|BOTH|0.0.0.0|3615|relay.example.test|443|edge.example.test|8443' \
  "$forward" 'Port Forward CLI parser'
forward_switch="$(parse_forward forward switch-backend edge --backend nftables --target 203.0.113.10)"
assert_eq 'nobrand-forward|switch-backend||nftables||||203.0.113.10|||' \
  "$forward_switch" 'Port Forward switch parser'

if parse install-nobrand.sh snell install --name bad --version 3 --advertise-auto -y >/dev/null 2>&1; then
  fail 'Snell v3 must be rejected'
fi
if parse install-nobrand.sh snell install --name bad --version 1 --advertise-auto -y >/dev/null 2>&1; then
  fail 'Snell v1 must be rejected'
fi
if parse install-nobrand.sh snell v6 >/dev/null 2>&1; then
  fail 'Snell v6 alias must be rejected'
fi
if parse install-nobrand.sh snell install --name bad --version 6 --advertise-auto -y >/dev/null 2>&1; then
  fail 'Snell --version 6 must be rejected'
fi
if parse install-nobrand.sh snell install --name bad --version 5 --quic >/dev/null 2>&1; then
  fail 'missing --quic value must be rejected'
fi
if parse install-nobrand.sh snell install --name bad --version 5 --quic invalid >/dev/null 2>&1; then
  fail 'invalid --quic value must be rejected'
fi
if parse install-nobrand.sh snell install --name bad --version 5 --quic yes extra >/dev/null 2>&1; then
  fail 'invalid --quic plus extra argument must be rejected'
fi
if parse install-nobrand.sh snell install --name bad --version 4 --quic on >/dev/null 2>&1; then
  fail 'Snell v4 --quic on must be rejected by CLI parser'
fi
if parse install-nobrand.sh vless-sudoku install --advertise-host >/dev/null 2>&1; then
  fail 'missing --advertise-host value must be rejected without a shift loop'
fi
if parse_reality vless-reality install --target >/dev/null 2>&1; then
  fail 'missing REALITY --target value must be rejected without a shift loop'
fi

if bash -c '
  set --
  MITA_SOURCE_ONLY=1 source "$1"
  trap - ERR
  YES=1 ADVERTISE_CLI=0 ADVERTISE_AUTO_REQUESTED=0 ADVERTISE_HOST="" ADVERTISE_PORT=""
  nb_require_explicit_endpoint_noninteractive
' test "$TEST_ROOT/install-nobrand.sh" >/dev/null 2>&1; then
  fail '-y without explicit Display Endpoint must be rejected'
fi

help="$(bash "$TEST_ROOT/install-nobrand.sh" --help)"
assert_contains "$help" 'NoBrand-OneClick' 'NoBrand help entry'
assert_contains "$help" 'Snell v4-v5' 'NoBrand help protocols'
assert_not_contains "$help" 'Snell v6' 'NoBrand help removed v6'
assert_contains "$help" 'set-quic' 'NoBrand help QUIC toggle'
assert_contains "$help" 'VLESS + FinalMask + Sudoku' 'NoBrand VLESS help protocol'
assert_contains "$help" 'VLESS REALITY' 'NoBrand REALITY help protocol'
assert_contains "$help" 'nobrand vless-reality install' 'NoBrand REALITY CLI help'
assert_contains "$help" 'VLESS Encryption: NOT USED' 'NoBrand plain VLESS help notice'
assert_contains "$help" 'nobrand tuic install' 'NoBrand TUIC v5 help'
assert_contains "$help" 'nobrand ssh install' 'NoBrand SSH Tunnel help'
assert_contains "$help" 'nobrand forward add' 'NoBrand Port Forward help'
assert_contains "$help" 'PROTOCOL_FEATURE_FREEZE=true' 'NoBrand feature freeze help'
assert_contains "$help" 'TUIC 只支持 v5' 'NoBrand TUIC generation scope'
assert_contains "$help" 'AllowTcpForwarding=yes' 'NoBrand SSH forwarding tradeoff'
assert_contains "$help" 'nobrand --version' 'NoBrand version help'
assert_contains "$help" 'nobrand manager install|upgrade' 'NoBrand exact-artifact manager upgrade help'

if parse install-nobrand.sh manager >/dev/null 2>&1; then
  fail 'manager action must be explicit'
fi
if parse install-nobrand.sh manager upgrade extra >/dev/null 2>&1; then
  fail 'manager upgrade must reject extra arguments'
fi

version="$(bash "$TEST_ROOT/install-nobrand.sh" --version)"
assert_eq $'NoBrand-OneClick 3.2.1\n作者: ike' "$version" 'NoBrand Chinese-first version output'
english_version="$(bash -c '
  installer="$1"
  set --
  MITA_SOURCE_ONLY=1 source "$installer"
  LANG_ZH=0 nobrand_version
' test "$TEST_ROOT/install-nobrand.sh")"
assert_eq $'NoBrand-OneClick 3.2.1\nAuthor: ike' "$english_version" \
  'NoBrand English version output'
mieru_version="$(bash "$TEST_ROOT/install-nobrand.sh" mieru --version)"
assert_eq $'NoBrand-OneClick Mieru 3.2.1\n作者: ike' "$mieru_version" \
  'Mieru Chinese-first version output'
mieru_english_version="$(bash "$TEST_ROOT/install-nobrand.sh" mieru --lang en --version)"
assert_eq $'NoBrand-OneClick Mieru 3.2.1\nAuthor: ike' "$mieru_english_version" \
  'Mieru English version output'
cp "$TEST_ROOT/install-nobrand.sh" "$cli_fixture/nb"
short_version="$(bash "$cli_fixture/nb" --version)"
assert_eq "$version" "$short_version" 'nb version alias'

if bash "$TEST_ROOT/install-nobrand.sh" unknown-command </dev/null >/dev/null 2>&1; then
  fail 'unknown NoBrand command must fail'
fi
if bash "$TEST_ROOT/install-nobrand.sh" status extra >/dev/null 2>&1; then
  fail 'status extra argument must fail'
fi
if bash "$TEST_ROOT/install-nobrand.sh" --version extra >/dev/null 2>&1; then
  fail 'version extra argument must fail'
fi

assert_cli_error_text '--name 需要 VLESS REALITY 实例名称' 'instance name' \
  vless-reality install --name
assert_cli_error_text '未知 TUIC 用户操作: invalid' 'TUIC user 操作' \
  tuic user invalid
assert_cli_error_text 'TUIC 通道只支持 stable、latest、pinned' 'TUIC channel' \
  tuic install --channel invalid
assert_cli_error_text '--token 需要看门狗令牌' 'watchdog token' \
  ssh confirm-admin --token
assert_cli_error_text '--rule 需要规则 ID 或名称' 'rule ID or name' \
  forward show --rule
assert_cli_error_text '--interface 需要网络接口' '需要 interface' \
  forward add --interface
assert_cli_error_text '--dns-mode 需要 Realm DNS 模式' 'Realm DNS mode' \
  forward add --dns-mode
assert_cli_error_text '--listen-transport 需要 Realm 传输字符串' 'transport string' \
  forward add --listen-transport

for option in --protocol --traffic-pattern --low-entropy --multiplexing --handshake-mode \
  --user --password --package --quota-mb --quota-days --quota-mode --expire \
  --bandwidth --op-user --lang; do
  if parse nobrand mieru install "$option" >/dev/null 2>&1; then
    fail "missing value for ${option} must fail clearly"
  fi
done

for option in --backend --protocol --listen --port --target --target-port --name; do
  if parse_forward forward add "$option" >/dev/null 2>&1; then
    fail "missing Forward value for ${option} must fail clearly"
  fi
done

pass 'NoBrand/Mieru CLI routing and explicit endpoint enforcement'
