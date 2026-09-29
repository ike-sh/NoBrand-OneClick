#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/testlib.sh"

fixture="$(mktemp -d)"
trap 'rm -rf -- "$fixture"' EXIT
export NOBRAND_STATE_DIR="$fixture/state"
export NOBRAND_CONFIG_DIR="$fixture/config"
export NOBRAND_LIB_DIR="$fixture/lib"
export NOBRAND_LIFECYCLE_DIR="$fixture/nobrand-oneclick-lifecycle"
export NOBRAND_LIFECYCLE_LOCK_FILE="$fixture/run/nobrand-oneclick/lifecycle.lock"
export NOBRAND_TEST_MODE=1
mkdir -m 0700 "$fixture/run"
source_installer
# The focused test uses source even before build regeneration.
# shellcheck disable=SC1091
source "$TEST_ROOT/src/90-ui.sh"
trap - ERR

reply=""
read_tty() { printf -v "$1" '%s' "$reply"; }
# Read by the dynamically sourced manager state guard.
# shellcheck disable=SC2034
nb_validate_authoritative_state_boundary() { NOBRAND_INSTALL_STATE=CURRENT_COMPLETE; }
nobrand_ssh_confirmation_pending() { return 1; }

write_instance() {
  local scope="$1" id="$2" name="$3" path=""
  case "$scope" in
    snell)
      path="$(snell_state_path "$id")"
      mkdir -p "$(dirname "$path")"
      jq -n --arg id "$id" --arg name "$name" \
        '{instance_id:$id,version:5,name:$name,listen_port:14934}' >"$path"
      ;;
    reality)
      path="$(reality_state_file "$id")"
      mkdir -p "$(dirname "$path")"
      jq -n --arg id "$id" --arg name "$name" \
        '{schema_version:3,ownership:"nobrand-v3",protocol:"vless-reality",instance_id:$id,name:$name}' >"$path"
      ;;
    tuic)
      path="$(tuic_state_file "$id")"
      mkdir -p "$(dirname "$path")"
      jq -n --arg id "$id" --arg name "$name" \
        '{schema_version:3,ownership:"nobrand-v3",protocol:"tuic",tuic_version:5,instance_id:$id,name:$name}' >"$path"
      ;;
  esac
}

select_instance() {
  local scope="$1"
  case "$scope" in
    snell) snell_menu_select_instance ;;
    reality) reality_menu_select_instance ;;
    tuic) tuic_menu_select_instance ;;
  esac
}

expect_selection() {
  local scope="$1" input="$2" expected_name="$3" expected_id="$4"
  reply="$input"
  select_instance "$scope" >"$fixture/selection.out" 2>&1 \
    || fail "$scope rejected valid selection: $input"
  assert_eq "$expected_name" "$NOBRAND_MENU_SELECTION_NAME" "$scope selected name"
  assert_eq "$expected_id" "$NOBRAND_MENU_SELECTION_ID" "$scope selected ID"
  nobrand_menu_selection_current || fail "$scope selected stale instance"
}

expect_rejection() {
  local scope="$1" input="$2"
  reply="$input"
  if select_instance "$scope" >"$fixture/selection.out" 2>&1; then
    fail "$scope accepted unsafe selection: $input"
  fi
  [ -z "${NOBRAND_MENU_SELECTION_SCOPE:-}" ] || fail "$scope retained rejected selection"
}

snell_one=saaaaaaaaaaaaaaaa
snell_two=s1111111111111111
reality_one=r1111111111111111
reality_two=r2222222222222222
tuic_one=t1111111111111111
tuic_two=t2222222222222222

expect_rejection snell ''
expect_rejection reality ''
expect_rejection tuic ''

write_instance snell "$snell_one" '测试-节点甲'
write_instance reality "$reality_one" 'Tokyo IPLC 01'
write_instance tuic "$tuic_one" 'TUIC $East #1'
expect_selection snell '' '测试-节点甲' "$snell_one"
expect_selection snell '测试-节点甲' '测试-节点甲' "$snell_one"
expect_rejection snell 'wrong node'
expect_selection reality '' 'Tokyo IPLC 01' "$reality_one"
expect_selection reality 'Tokyo IPLC 01' 'Tokyo IPLC 01' "$reality_one"
expect_rejection reality 'wrong node'
expect_selection tuic '' 'TUIC $East #1' "$tuic_one"
expect_selection tuic 'TUIC $East #1' 'TUIC $East #1' "$tuic_one"
expect_rejection tuic 'wrong node'

write_instance snell "$snell_two" 'Tokyo IPLC 01'
write_instance reality "$reality_two" '大阪 #2'
write_instance tuic "$tuic_two" '测试-节点甲'
expect_rejection snell ''
expect_rejection reality ''
expect_rejection tuic ''
expect_selection snell 'Tokyo IPLC 01' 'Tokyo IPLC 01' "$snell_two"
expect_selection reality '大阪 #2' '大阪 #2' "$reality_two"
expect_selection tuic '测试-节点甲' '测试-节点甲' "$tuic_two"
pass 'Snell, REALITY, and TUIC selectors handle zero, one, multiple, and exact names'

# A selection is a snapshot: changing the selected instance after the prompt
# must stop the callback after the lifecycle lock has been acquired.
rm -f "$(snell_state_path "$snell_two")"
expect_selection snell '' '测试-节点甲' "$snell_one"
NOBRAND_MANAGER_SESSION_ACTIVE=1
# Read by the dynamically sourced menu wrapper.
# shellcheck disable=SC2034
NOBRAND_MENU_EXPECTED_STATE=CURRENT_COMPLETE
fixture_action() { : >"$fixture/action-ran"; }
jq '.advertise_mode="custom" | .advertise_host="edge.example.com" | .advertise_port=24443' \
  "$(snell_state_path "$snell_one")" >"$fixture/changed.json"
mv "$fixture/changed.json" "$(snell_state_path "$snell_one")"
if nobrand_menu_run fixture_action >"$fixture/stale.out" 2>&1; then
  fail 'stale Snell state was accepted'
fi
assert_contains "$(cat "$fixture/stale.out")" '菜单显示后权威状态已变化' \
  'stale selection rejection reason'
[ ! -e "$fixture/action-ran" ] || fail 'stale selection reached action'
flock -n "$NOBRAND_LIFECYCLE_LOCK_FILE" -c true || fail 'stale selection retained lock'
expect_selection snell '' '测试-节点甲' "$snell_one"
if ! nobrand_menu_run fixture_action >"$fixture/fresh.out" 2>&1; then
  cat "$fixture/fresh.out" >&2
  fail 'fresh selected action failed'
fi
[ -e "$fixture/action-ran" ] || fail 'fresh selection did not reach action'
flock -n "$NOBRAND_LIFECYCLE_LOCK_FILE" -c true || fail 'fresh selection retained lock'
pass 'stale domain Display Endpoint selection is rejected after lock acquisition'

# Reproduce the field path: Snell submenu -> Display Endpoint -> lone instance
# -> Enter. The callback sees the real listener port and the selected name.
# Read by the dynamically sourced menu wrapper.
# shellcheck disable=SC2034
NOBRAND_MANAGER_SESSION_ACTIVE=0
jq '.listen_port=24443' "$(snell_state_path "$snell_one")" >"$fixture/changed.json"
mv "$fixture/changed.json" "$(snell_state_path "$snell_one")"
snell_endpoint_action() {
  printf '%s|%s|%s\n' "$SNELL_ACTION" "$SNELL_NAME" \
    "$(snell_state_field "$snell_one" listen_port)" >"$fixture/endpoint-call"
}
nobrand_run_snell_action() { snell_endpoint_action; }
menu_pause() { :; }
replies=(5 '' 0)
reply_index=0
read_tty() {
  [ "$reply_index" -lt "${#replies[@]}" ] || return 1
  printf -v "$1" '%s' "${replies[$reply_index]}"
  reply_index=$((reply_index + 1))
}
snell_menu_loop >"$fixture/endpoint.out" 2>&1
assert_eq 'set-endpoint|测试-节点甲|24443' "$(cat "$fixture/endpoint-call")" \
  'Snell Display Endpoint callback after Enter'
pass 'single Snell node Enter continues to Display Endpoint action'
