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

id4=s4000000000000000
id5=s5000000000000000
id6=s6000000000000000
for spec in "$id4:4:3644" "$id5:5:3655"; do
  IFS=: read -r id major port <<<"$spec"
  runtime="$(snell_runtime_path "$major")"
  printf '#!/bin/sh\necho snell-server v%s.0.1\n' "$major" >"$runtime"
  chmod +x "$runtime"
  snell_generate_state "$(snell_state_path "$id")" "$id" "keep-v${major}" "$major" \
    "psk-v${major}-safe" 0.0.0.0 "$port" auto '' ''
  snell_generate_server_config "$(snell_config_path "$id")" "$major" 0.0.0.0 "$port" "psk-v${major}-safe"
done

# Historical v6 fixtures are deliberately raw: no supported product helper is
# allowed to generate them in 1.3.0.
jq -n --arg id "$id6" '{protocol:"snell",instance_id:$id,name:"remove-v6",version:6,listen_port:3666}' \
  >"$NOBRAND_SNELL_STATE_DIR/$id6.json"
printf '[snell-server]\nlisten = 0.0.0.0:3666\npsk = historical-only\n' \
  >"$NOBRAND_SNELL_CONFIG_DIR/$id6.conf"
printf 'removed runtime\n' >"$NOBRAND_SNELL_RUNTIME_DIR/snell-v6"
printf '{}\n' >"$NOBRAND_SNELL_RUNTIME_DIR/snell-v6.runtime.json"
printf 'unrelated\n' >"$NOBRAND_SNELL_RUNTIME_DIR/keep.me"

service_log="$fixture/services"
firewall_log="$fixture/firewall"
snell_remove_service() { printf '%s\n' "$1" >>"$service_log"; }
nb_firewall_close_pairs() { printf '%s\n' "$1" >>"$firewall_log"; }

snell_migrate_removed_v6
assert_eq "$id6" "$(<"$service_log")" 'migration removes only historical v6 service'
assert_eq 'TCP|3666' "$(<"$firewall_log")" 'migration closes only historical TCP ownership'
[ ! -e "$NOBRAND_SNELL_STATE_DIR/$id6.json" ] || fail 'migration removes historical v6 state'
[ ! -e "$NOBRAND_SNELL_CONFIG_DIR/$id6.conf" ] || fail 'migration removes historical v6 config'
[ ! -e "$NOBRAND_SNELL_RUNTIME_DIR/snell-v6" ] || fail 'migration removes independent v6 runtime'
[ ! -e "$NOBRAND_SNELL_RUNTIME_DIR/snell-v6.runtime.json" ] || fail 'migration removes v6 runtime metadata'
[ -e "$(snell_state_path "$id4")" ] || fail 'migration must retain v4 state'
[ -e "$(snell_state_path "$id5")" ] || fail 'migration must retain v5 state'
[ -e "$(snell_config_path "$id4")" ] || fail 'migration must retain v4 config'
[ -e "$(snell_config_path "$id5")" ] || fail 'migration must retain v5 config'
[ -e "$(snell_runtime_path 4)" ] || fail 'migration must retain v4 runtime'
[ -e "$(snell_runtime_path 5)" ] || fail 'migration must retain v5 runtime'
[ -e "$NOBRAND_SNELL_RUNTIME_DIR/keep.me" ] || fail 'migration must retain unrelated runtime content'

# A mismatched filename/instance id is not safe to act on. Migration must
# fail closed without deleting either the state or the referenced config.
bad_file=s6111111111111111
other_id=s6222222222222222
jq -n --arg id "$other_id" '{protocol:"snell",instance_id:$id,name:"unsafe-v6",version:6,listen_port:3676}' \
  >"$NOBRAND_SNELL_STATE_DIR/$bad_file.json"
printf 'must-retain\n' >"$NOBRAND_SNELL_CONFIG_DIR/$other_id.conf"
printf 'removed runtime\n' >"$NOBRAND_SNELL_RUNTIME_DIR/snell-v6"
if snell_migrate_removed_v6 >/dev/null 2>&1; then
  fail 'mismatched historical v6 identity must fail closed'
fi
[ -e "$NOBRAND_SNELL_STATE_DIR/$bad_file.json" ] || fail 'unsafe v6 state must remain for operator review'
[ -e "$NOBRAND_SNELL_CONFIG_DIR/$other_id.conf" ] || fail 'mismatched config must not be deleted'
[ -e "$NOBRAND_SNELL_RUNTIME_DIR/snell-v6" ] || fail 'runtime removal waits until all historical state is safe'

pass 'Snell v6 product paths are absent and one-time migration is exact'
