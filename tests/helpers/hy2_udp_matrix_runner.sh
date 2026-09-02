#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 8 ]; then
  printf 'usage: %s <mihomo|sing-box> <binary> <config> <proxy-port> <target-host> <target-port> <output-prefix> <size>...\n' "$0" >&2
  exit 2
fi

kind="$1"
binary="$2"
config="$3"
proxy_port="$4"
target_host="$5"
target_port="$6"
output_prefix="$7"
shift 7
sizes=("$@")
attempts="${ATTEMPTS:-10}"
timeout="${PROBE_TIMEOUT:-5}"
probe="${REFERENCE_PROBE:-$(cd "$(dirname "$0")" && pwd -P)/socks5_udp_reference_probe.py}"
client_pid=""

cleanup() {
  local rc=$?
  [ -z "$client_pid" ] || kill "$client_pid" >/dev/null 2>&1 || true
  [ -z "$client_pid" ] || wait "$client_pid" >/dev/null 2>&1 || true
  return "$rc"
}
trap cleanup EXIT

for command_name in jq python3 ss; do
  command -v "$command_name" >/dev/null 2>&1 || {
    printf 'missing runtime dependency: %s\n' "$command_name" >&2
    exit 2
  }
done
[ -x "$binary" ] || { printf 'client binary is not executable\n' >&2; exit 2; }
[ -r "$config" ] || { printf 'client config is not readable\n' >&2; exit 2; }
[ -r "$probe" ] || { printf 'reference probe is not readable\n' >&2; exit 2; }

case "$kind" in
  mihomo)
    mkdir -p "${output_prefix}.mihomo-home"
    chmod 0700 "${output_prefix}.mihomo-home"
    "$binary" -d "${output_prefix}.mihomo-home" -t -f "$config" >/dev/null
    "$binary" -d "${output_prefix}.mihomo-home" -f "$config" >"${output_prefix}.client.log" 2>&1 &
    ;;
  sing-box)
    "$binary" check -c "$config" >/dev/null
    "$binary" run -c "$config" >"${output_prefix}.client.log" 2>&1 &
    ;;
  *)
    printf 'unsupported client kind: %s\n' "$kind" >&2
    exit 2
    ;;
esac
client_pid=$!

ready=0
for ((index=0; index<150; index++)); do
  if ss -lntH "sport = :${proxy_port}" | grep -q .; then
    ready=1
    break
  fi
  kill -0 "$client_pid" >/dev/null 2>&1 || break
  sleep 0.1
done
if [ "$ready" -ne 1 ]; then
  sed -n '1,120p' "${output_prefix}.client.log" >&2 || true
  printf '%s client did not expose SOCKS port\n' "$kind" >&2
  exit 1
fi

set +e
python3 "$probe" \
  --proxy-host 127.0.0.1 --proxy-port "$proxy_port" \
  --target-host "$target_host" --target-port "$target_port" \
  --attempts "$attempts" --timeout "$timeout" --sizes "${sizes[@]}" \
  >"${output_prefix}.jsonl"
probe_rc=$?
set -e

matrix="$(jq -sr '
  [.[] | select(has("STATUS"))] as $trials |
  ($trials | map(.SIZE) | unique) as $sizes |
  [$sizes[] as $size |
    ($trials | map(select(.SIZE == $size)) |
      reduce .[] as $row ({}; .[$row.STATUS] = ((.[$row.STATUS] // 0) + 1))) as $counts |
    "\($size):PASS=\($counts.PASS // 0),MISMATCH=\($counts.MISMATCH // 0),TIMEOUT=\($counts.TIMEOUT // 0),ERROR=\($counts.ERROR // 0)"
  ] | join(" ")
' "${output_prefix}.jsonl")"
headers="$(jq -sc '[.[] | select(.SOCKS_HEADER_LENGTH != null) | .SOCKS_HEADER_LENGTH] | unique | join(",")' \
  "${output_prefix}.jsonl")"
atyps="$(jq -sc '[.[] | select(.RESPONSE_ATYP != null) | .RESPONSE_ATYP] | unique | join(",")' \
  "${output_prefix}.jsonl")"

printf 'CLIENT_KIND=%s\n' "$kind"
printf 'UDP_MATRIX=%s\n' "$matrix"
printf 'SOCKS_HEADER_LENGTHS_OBSERVED=%s\n' "$headers"
printf 'SOCKS_RESPONSE_ATYPS_OBSERVED=%s\n' "$atyps"
printf 'REFERENCE_PROBE_RC=%s\n' "$probe_rc"
exit "$probe_rc"
