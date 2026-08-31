#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "$0")" && pwd -P)/testlib.sh"

fixture="$(mktemp -d)"
trap 'rm -rf -- "$fixture"' EXIT

export NOBRAND_STATE_DIR="$fixture/state"
export NOBRAND_CONFIG_DIR="$fixture/config"
export NOBRAND_LIB_DIR="$fixture/lib"
export NOBRAND_BIN_DIR="$fixture/lib/bin"
export NOBRAND_FORWARD_STATE_DIR="$fixture/state/forward"
export NOBRAND_FORWARD_STATE_FILE="$fixture/state/forward/state.json"
export NOBRAND_FORWARD_REALM_CONFIG="$fixture/config/forward/realm.toml"
export NOBRAND_FORWARD_NFT_RULESET="$fixture/config/forward/nftables.nft"
export NOBRAND_FORWARD_SYSCTL_STATE="$fixture/state/forward/sysctl.json"
export NOBRAND_FORWARD_SYSCTL_FRAGMENT="$fixture/sysctl.d/90-nobrand-forward.conf"
export NOBRAND_REALM_BIN="$fixture/lib/bin/realm"
export NOBRAND_REALM_RUNTIME_META="$fixture/state/forward/realm-runtime.json"
export NOBRAND_REALM_SYSTEMD_SERVICE="$fixture/systemd/nobrand-realm.service"
export NOBRAND_REALM_OPENRC_SERVICE="$fixture/openrc/nobrand-realm"
export NOBRAND_TEST_LOCAL_IPV4=192.0.2.168

source_installer
nb_init_state_layout
forward_init_state

service_manager_kind=systemd
nb_service_manager() { printf '%s' "$service_manager_kind"; }
systemctl() { printf '%s\n' "$*" >>"$fixture/systemctl.log"; }
rc-update() { printf '%s\n' "$*" >>"$fixture/rc-update.log"; }

mkdir -p "$(dirname "$NOBRAND_REALM_SYSTEMD_SERVICE")" "$(dirname "$NOBRAND_REALM_BIN")"
printf '[Service]\nExecStart=/usr/local/bin/external-realm -c /etc/external-realm.toml\n' \
  >"$NOBRAND_REALM_SYSTEMD_SERVICE"
service_hash="$(sha256sum "$NOBRAND_REALM_SYSTEMD_SERVICE")"
if forward_realm_install_service; then
  fail 'NoBrand replaced an unowned same-name Realm service'
fi
assert_eq "$service_hash" "$(sha256sum "$NOBRAND_REALM_SYSTEMD_SERVICE")" \
  'unowned same-name Realm service preserved'

rm -f "$NOBRAND_REALM_SYSTEMD_SERVICE"
forward_realm_install_service || fail 'NoBrand-owned Realm systemd service generation'
forward_realm_service_file_owned || fail 'generated Realm systemd service lacks ownership proof'
assert_contains "$(cat "$NOBRAND_REALM_SYSTEMD_SERVICE")" \
  '# Owned by NoBrand-OneClick Port Forward' 'Realm service ownership marker'

service_manager_kind=openrc
forward_realm_install_service || fail 'NoBrand-owned Realm OpenRC service generation'
forward_realm_service_file_owned || fail 'generated Realm OpenRC service lacks ownership proof'
assert_contains "$(cat "$NOBRAND_REALM_OPENRC_SERVICE")" '#!/sbin/openrc-run' 'Realm OpenRC shebang'
assert_contains "$(cat "$NOBRAND_REALM_OPENRC_SERVICE")" \
  '# Owned by NoBrand-OneClick Port Forward' 'Realm OpenRC ownership marker'
service_manager_kind=systemd

rm -f "$NOBRAND_REALM_SYSTEMD_SERVICE"
printf 'external-private-path-runtime\n' >"$NOBRAND_REALM_BIN"
chmod 0755 "$NOBRAND_REALM_BIN"
curl() { printf 'unexpected-network\n' >"$fixture/curl-called"; return 1; }
if forward_realm_install_runtime stable; then
  fail 'NoBrand replaced an unowned binary in its private Realm path'
fi
[ ! -e "$fixture/curl-called" ] || fail 'Realm ownership rejection happened after network access'
assert_eq external-private-path-runtime "$(cat "$NOBRAND_REALM_BIN")" \
  'unowned private-path Realm binary preserved'

nft() {
  case "$1 $2 $3 $4" in
    'list table ip nobrand_forward_v4')
      printf 'table ip nobrand_forward_v4 {\n  chain external_fixture { }\n}\n'
      ;;
    'delete table ip nobrand_forward_v4') printf 'deleted\n' >"$fixture/nft-deleted" ;;
    *) return 1 ;;
  esac
}
if forward_remove_owned_nft_table; then
  fail 'NoBrand removed an unowned same-name nftables table'
fi
[ ! -e "$fixture/nft-deleted" ] || fail 'unowned nftables table delete was attempted'

nft() {
  case "$1 $2 $3 $4" in
    'list table ip nobrand_forward_v4')
      printf 'table ip nobrand_forward_v4 {\n'
      printf '  tcp dport 32001 dnat comment "nobrand:f1111111111111111:dnat:tcp"\n'
      # Keep writing well past a pipe buffer. The former `nft | grep -q`
      # implementation became a false failure when the match appeared early.
      local i
      for ((i=0; i<20000; i++)); do
        printf '  counter packets %s bytes %s\n' "$i" "$i"
      done
      printf '}\n'
      ;;
    *) return 1 ;;
  esac
}
forward_nft_rule_owned f1111111111111111 \
  || fail 'owned nftables rule failed under pipefail with trailing ruleset output'
if forward_nft_rule_owned f2222222222222222; then
  fail 'unknown nftables rule was accepted as owned'
fi

pass 'Forward external Realm/runtime/service and nftables ownership protection'
