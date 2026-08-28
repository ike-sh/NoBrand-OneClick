#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/testlib.sh"

fixture="$(mktemp -d)"
trap 'rm -rf -- "$fixture"' EXIT
export NOBRAND_STATE_DIR="$fixture/nobrand-oneclick/state"
export NOBRAND_CONFIG_DIR="$fixture/nobrand-oneclick/config"
export NOBRAND_LIB_DIR="$fixture/nobrand-oneclick/lib"
source_installer
nb_init_state_layout

HY2_SNI=cert.example.com
generate_hysteria2_cert
openssl ec -in "$NOBRAND_HY2_KEY_FILE" -noout -text 2>/dev/null | grep -q 'ASN1 OID: prime256v1' \
  || fail 'HY2 key must use prime256v1/P-256'
openssl x509 -in "$NOBRAND_HY2_CERT_FILE" -noout >/dev/null || fail 'HY2 certificate must parse'
subject="$(openssl x509 -in "$NOBRAND_HY2_CERT_FILE" -noout -subject -nameopt RFC2253)"
assert_contains "$subject" 'CN=cert.example.com' 'certificate CN'
assert_file_mode 600 "$NOBRAND_HY2_KEY_FILE"
assert_file_mode 644 "$NOBRAND_HY2_CERT_FILE"
days="$(python3 - "$NOBRAND_HY2_CERT_FILE" <<'PY'
import datetime,ssl,sys
data=ssl._ssl._test_decode_cert(sys.argv[1])
end=datetime.datetime.strptime(data['notAfter'],'%b %d %H:%M:%S %Y %Z').replace(tzinfo=datetime.timezone.utc)
print((end-datetime.datetime.now(datetime.timezone.utc)).days)
PY
)"
[ "$days" -ge 3648 ] && [ "$days" -le 3650 ] || fail "certificate lifetime is ${days} days, expected approximately 3650"

old_key="$(sha256sum "$NOBRAND_HY2_KEY_FILE")"
old_cert="$(sha256sum "$NOBRAND_HY2_CERT_FILE")"
openssl() {
  [ "${1:-}" != ecparam ] || return 1
  command openssl "$@"
}
generate_hysteria2_cert >/dev/null 2>&1 && fail 'forced certificate regeneration failure must fail'
unset -f openssl
assert_eq "$old_key" "$(sha256sum "$NOBRAND_HY2_KEY_FILE")" 'failed regeneration key rollback'
assert_eq "$old_cert" "$(sha256sum "$NOBRAND_HY2_CERT_FILE")" 'failed regeneration cert rollback'

pass 'HY2 P-256 certificate, permissions, lifetime, and rollback'
