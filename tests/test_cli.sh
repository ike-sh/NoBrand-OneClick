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
    printf "%s|%s|%s|%s|%s|%s|%s|%s|%s|%s\n" "$ACTION" "${SNELL_ACTION:-}" "${SNELL_VERSION:-}" "${SNELL_NAME:-}" "${HY2_ACTION:-}" "${VLESS_SUDOKU_ACTION:-}" "${YES:-0}" "${ADVERTISE_AUTO_REQUESTED:-0}" "${SNELL_QUIC_PROXY:-}" "${SNELL_QUIC_CLI:-0}"
  ' "$argv0" "$TEST_ROOT/install-nobrand.sh" "$@"
}
export TEST_ROOT
cli_fixture="$(mktemp -d)"
trap 'rm -rf -- "$cli_fixture"' EXIT

assert_contains "$(parse install-mita.sh status)" 'status|' 'install-mita status stays Mieru'
assert_contains "$(parse install-nobrand.sh status)" 'nobrand-status|' 'NoBrand unified status'
assert_contains "$(parse install-nobrand.sh uninstall -y)" 'nobrand-uninstall|' 'NoBrand uninstall routing'
assert_contains "$(parse install-nobrand.sh mieru users)" 'user-list|' 'NoBrand Mieru delegation'
snell="$(parse install-nobrand.sh snell install --name alice --version 5 --port 3611 --advertise-auto -y)"
assert_eq 'nobrand-snell|install|5|alice|||1|1||0' "$snell" 'Snell CLI parser default QUIC'
snell_quic="$(parse install-nobrand.sh snell install --name alice --version 5 --port 3611 --quic on --advertise-auto -y)"
assert_eq 'nobrand-snell|install|5|alice|||1|1|on|1' "$snell_quic" 'Snell CLI parser QUIC ON'
snell_toggle="$(parse install-nobrand.sh snell set-quic --name alice --quic off -y)"
assert_eq 'nobrand-snell|set-quic|5|alice|||1|0|off|1' "$snell_toggle" 'Snell CLI QUIC toggle'
hy2="$(parse install-nobrand.sh hy2 install --port 3612 --sni www.microsoft.com --advertise-auto -y)"
assert_eq 'nobrand-hy2||5||install||1|1||0' "$hy2" 'HY2 CLI parser'
vless="$(parse install-nobrand.sh vless-sudoku install --port 3613 --advertise-auto -y)"
assert_eq 'nobrand-vless-sudoku||5|||install|1|1||0' "$vless" 'VLESS Sudoku CLI parser'
alias_vless="$(parse install-nobrand.sh sudoku smoke)"
assert_eq 'nobrand-vless-sudoku||5|||smoke|0|0||0' "$alias_vless" 'Sudoku canonical-backend alias'

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
assert_contains "$help" 'VLESS Encryption: NOT USED' 'NoBrand plain VLESS help notice'
assert_contains "$help" 'nobrand --version' 'NoBrand version help'

version="$(bash "$TEST_ROOT/install-nobrand.sh" --version)"
assert_eq $'NoBrand-OneClick 1.3.0\nAuthor: ike' "$version" 'NoBrand product version output'
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

pass 'NoBrand/Mieru CLI routing and explicit endpoint enforcement'
