#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/testlib.sh"

fixture="$(mktemp -d)"
trap 'rm -rf -- "$fixture"' EXIT

export NOBRAND_STATE_DIR="$fixture/state"
export NOBRAND_CONFIG_DIR="$fixture/config"
export NOBRAND_LIB_DIR="$fixture/lib"
export MITA_MANAGER_STATE_DIR="$fixture/state/mieru"
source_installer
MENU_MODE=1
DRY_RUN=0
# The generated installer is sourced dynamically by testlib; these are installer inputs.
: "$MENU_MODE" "$DRY_RUN"

release_object() {
  local tag="$1" draft="$2" prerelease="$3" mode="${4:-normal}"
  local version="${tag#v}" asset digest assets
  asset="mita_${version}_amd64.deb"
  digest="$(printf '%064d' 0 | tr '0' 'a')"
  [ "$version" != "$LAST_KNOWN_GOOD_MIERU_VERSION" ] \
    || digest="$LAST_KNOWN_GOOD_MIERU_AMD64_DEB_SHA256"
  case "$mode" in
    normal)
      assets="$(jq -cn --arg asset "$asset" --arg digest "sha256:${digest}" \
        --arg url "${GITHUB_DL}/${tag}/${asset}" \
        --arg checksum "${asset}.sha256.txt" \
        --arg checksum_url "${GITHUB_DL}/${tag}/${asset}.sha256.txt" \
        '[{name:$asset,browser_download_url:$url,digest:$digest},
          {name:$checksum,browser_download_url:$checksum_url,digest:null}]')"
      ;;
    missing-runtime)
      assets="$(jq -cn --arg checksum "${asset}.sha256.txt" \
        --arg checksum_url "${GITHUB_DL}/${tag}/${asset}.sha256.txt" \
        '[{name:$checksum,browser_download_url:$checksum_url,digest:null}]')"
      ;;
    duplicate-runtime)
      assets="$(jq -cn --arg asset "$asset" --arg digest "sha256:${digest}" \
        --arg url "${GITHUB_DL}/${tag}/${asset}" \
        --arg checksum "${asset}.sha256.txt" \
        --arg checksum_url "${GITHUB_DL}/${tag}/${asset}.sha256.txt" \
        '[{name:$asset,browser_download_url:$url,digest:$digest},
          {name:$asset,browser_download_url:$url,digest:$digest},
          {name:$checksum,browser_download_url:$checksum_url,digest:null}]')"
      ;;
    missing-checksum)
      assets="$(jq -cn --arg asset "$asset" --arg digest "sha256:${digest}" \
        --arg url "${GITHUB_DL}/${tag}/${asset}" \
        '[{name:$asset,browser_download_url:$url,digest:$digest}]')"
      ;;
    duplicate-checksum)
      assets="$(jq -cn --arg asset "$asset" --arg digest "sha256:${digest}" \
        --arg url "${GITHUB_DL}/${tag}/${asset}" \
        --arg checksum "${asset}.sha256.txt" \
        --arg checksum_url "${GITHUB_DL}/${tag}/${asset}.sha256.txt" \
        '[{name:$asset,browser_download_url:$url,digest:$digest},
          {name:$checksum,browser_download_url:$checksum_url,digest:null},
          {name:$checksum,browser_download_url:$checksum_url,digest:null}]')"
      ;;
    *) fail "unknown release fixture mode: $mode" ;;
  esac
  jq -cn --arg tag "$tag" --argjson draft "$draft" --argjson prerelease "$prerelease" \
    --argjson assets "$assets" \
    '{tag_name:$tag,draft:$draft,prerelease:$prerelease,assets:$assets}'
}

metadata_array() {
  printf '%s\n' "$@" | jq -sc .
}

MIERU_TEST_RELEASES='[]'
MIERU_TEST_TAG='{}'
MIERU_TEST_FETCH_FAIL=0
mieru_fetch_releases_metadata() {
  [ "$MIERU_TEST_FETCH_FAIL" -eq 0 ] || return 1
  printf '%s\n' "$MIERU_TEST_RELEASES" >"$1"
}
mieru_fetch_tag_metadata() {
  printf '%s\n' "$MIERU_TEST_TAG" >"$2"
}

MIERU_TEST_RELEASES="$(metadata_array \
  "$(release_object v3.36.0 false false)" \
  "$(release_object v3.37.0-rc.1 false true)" \
  "$(release_object v3.38.0 true false)" \
  "$(release_object v3.35.0 false false)")"
# The resolver implementation is loaded by source_installer above.
# shellcheck disable=SC2218
mieru_resolve_runtime stable '' deb amd64
assert_eq 3.36.0 "$MIERU_RUNTIME_RESOLVED_VERSION" 'latest stable excludes RC and draft'
assert_eq mita_3.36.0_amd64.deb "$MIERU_RUNTIME_RESOLVED_ASSET" 'resolved platform asset'
assert_eq "$LAST_KNOWN_GOOD_MIERU_AMD64_DEB_SHA256" \
  "$MIERU_RUNTIME_RESOLVED_SHA256" 'known-good API digest'

MIERU_TEST_RELEASES="$(metadata_array \
  "$(release_object v3.37.0 false false)" \
  "$(release_object v3.38.0-rc.1 false true)")"
# shellcheck disable=SC2218
mieru_resolve_runtime latest '' deb amd64
assert_eq 3.37.0 "$MIERU_RUNTIME_RESOLVED_VERSION" 'latest alias selects latest stable'

MIERU_TEST_RELEASES="$(metadata_array "$(release_object v3.37.0-rc.1 false false)")"
if mieru_resolve_runtime stable '' deb amd64; then
  fail 'invalid stable semver must fail closed'
fi

for mode in missing-runtime duplicate-runtime missing-checksum duplicate-checksum; do
  MIERU_TEST_RELEASES="$(metadata_array "$(release_object v3.37.0 false false "$mode")")"
  if mieru_resolve_runtime stable '' deb amd64; then
    fail "release metadata mode $mode must fail closed"
  fi
done

MIERU_TEST_RELEASES="$(metadata_array "$(release_object v3.37.0 false false)")"
if mieru_resolve_runtime stable '' deb ppc64le; then
  fail 'unsupported architecture must fail closed'
fi

MIERU_TEST_FETCH_FAIL=1
fallback_log="$fixture/fallback.log"
# shellcheck disable=SC2218
mieru_resolve_runtime stable '' deb amd64 2>"$fallback_log"
assert_eq 3.36.0 "$MIERU_RUNTIME_RESOLVED_VERSION" 'metadata failure known-good fallback'
assert_eq 1 "$MIERU_RUNTIME_RESOLUTION_FALLBACK" 'fallback transaction marker'
grep -q 'LATEST_RESOLUTION_FAILED' "$fallback_log" || fail 'fallback warning missing failure marker'
grep -q 'USING_LAST_KNOWN_GOOD=3.36.0' "$fallback_log" || fail 'fallback warning missing version'
MIERU_TEST_FETCH_FAIL=0

MIERU_TEST_RELEASES='{malformed'
if mieru_resolve_runtime stable '' deb amd64; then
  fail 'successfully fetched malformed metadata must fail closed'
fi

MIERU_TEST_TAG="$(release_object v3.35.0 false false)"
# shellcheck disable=SC2218
mieru_resolve_runtime pinned 3.35.0 deb amd64
assert_eq 3.35.0 "$MIERU_RUNTIME_RESOLVED_VERSION" 'explicit pinned version override'
assert_eq pinned "$MIERU_RUNTIME_RESOLVED_CHANNEL" 'pinned channel identity'

fake_mita="$fixture/mita"
printf '#!/usr/bin/env sh\nprintf "v3.36.0 linux amd64\\n"\n' >"$fake_mita"
chmod 0755 "$fake_mita"
assert_eq 3.36.0 "$(mieru_runtime_version "$fake_mita")" 'official runtime identity parser'
mieru_assert_runtime_version 3.36.0 "$fake_mita"
if mieru_assert_runtime_version 3.35.0 "$fake_mita" >/dev/null 2>&1; then
  fail 'resolved and installed runtime versions must match exactly'
fi

payload="$fixture/mita.pkg"
manifest="$fixture/mita.pkg.sha256.txt"
printf 'official-mieru-payload\n' >"$payload"
payload_sha="$(nobrand_sha256_file "$payload")"
printf '%s  mita.pkg\n' "$payload_sha" >"$manifest"
curl() {
  local output='' url='' arg
  while [ "$#" -gt 0 ]; do
    arg="$1"; shift
    case "$arg" in
      -o) output="$1"; shift ;;
      http://*|https://*) url="$arg" ;;
    esac
  done
  [ -n "$output" ] || return 1
  case "$url" in
    *.sha256.txt) cp "$manifest" "$output" ;;
    *) cp "$payload" "$output" ;;
  esac
}
downloaded="$fixture/downloaded.pkg"
# shellcheck disable=SC2218
download_package 'https://example.invalid/mita.pkg' "$downloaded" "$payload_sha" \
  'https://example.invalid/mita.pkg.sha256.txt' >/dev/null
assert_eq "$payload_sha" "$(nobrand_sha256_file "$downloaded")" 'downloaded bytes identity'
if download_package 'https://example.invalid/mita.pkg' "$downloaded" \
    "$(printf '%064d' 0)" 'https://example.invalid/mita.pkg.sha256.txt' >/dev/null 2>&1; then
  fail 'API digest mismatch must fail closed'
fi

# Controlled upgrade failure: the package step replaces the managed binary
# with a version that does not match the pinned release. The transaction must
# put the old runtime and the exact user/state files back before returning.
upgrade="$fixture/upgrade"
mkdir -p "$upgrade/bin" "$upgrade/state"
MITA_BIN="$upgrade/bin/mita"
NOBRAND_BIN_DIR="$upgrade/bin"
: "$NOBRAND_BIN_DIR"
MITA_MARKER="$upgrade/state/.installed"
MITA_STATE="$upgrade/state/install-state.env"
MITA_USERS_STATE="$upgrade/state/users.json"
printf '#!/usr/bin/env sh\nprintf "v3.35.0 linux amd64\\n"\n' >"$MITA_BIN"
chmod 0755 "$MITA_BIN"
touch "$MITA_MARKER"
printf 'original-install-state\n' >"$MITA_STATE"
printf '%s\n' \
  '{"version":2,"deployment_model":"isolated-v2","protocol":"TCP","users":[{"instance_id":"u0000000000000001","name":"alice","password":"unchanged-secret","port":30000,"enabled":true}]}' \
  >"$MITA_USERS_STATE"
runtime_before="$(nobrand_sha256_file "$MITA_BIN")"
state_before="$(nobrand_sha256_file "$MITA_STATE")"
users_before="$(nobrand_sha256_file "$MITA_USERS_STATE")"

require_root() { :; }
require_linux() { :; }
require_cmd() { :; }
mita_installed() { return 0; }
mita_v3_install_state_valid() { return 0; }
detect_pkg_manager() { printf deb; }
detect_arch() { printf amd64; }
ensure_management_dependencies() { :; }
load_install_state() {
  MIERU_CHANNEL=stable
  MIERU_VERSION=3.35.0
  : "$MIERU_CHANNEL" "$MIERU_VERSION"
}
users_isolated_mode() { return 0; }
users_count() { printf 1; }
installed_version() { printf 3.35.0; }
mieru_resolve_runtime() {
  MIERU_RUNTIME_RESOLVED_VERSION=3.36.0
  MIERU_RUNTIME_RESOLVED_URL=https://example.invalid/mita.deb
  MIERU_RUNTIME_RESOLVED_SHA256="$LAST_KNOWN_GOOD_MIERU_AMD64_DEB_SHA256"
  MIERU_RUNTIME_RESOLVED_CHECKSUM_URL=https://example.invalid/mita.deb.sha256.txt
  MIERU_RUNTIME_RESOLVED_CHANNEL=stable
  : "$MIERU_RUNTIME_RESOLVED_URL" "$MIERU_RUNTIME_RESOLVED_CHECKSUM_URL" \
    "$MIERU_RUNTIME_RESOLVED_CHANNEL"
}
download_package() { printf 'candidate-package\n' >"$2"; }
install_package() {
  printf '#!/usr/bin/env sh\nprintf "v0.0.0 bad-candidate\\n"\n' >"$MITA_BIN"
  chmod 0755 "$MITA_BIN"
}
install_self_script() { :; }
admin_lock_acquire() { :; }
admin_lock_release() { :; }
isolated_stop_all() { :; }
reconcile_isolated_instances() {
  [ "$(mieru_runtime_version "$MITA_BIN")" = 3.35.0 ] || return 1
  touch "$upgrade/service-restored"
}
verify_mita_running() {
  [ "$(mieru_runtime_version "$MITA_BIN")" = 3.35.0 ]
}
YES=1
: "$YES"
if do_upgrade >/dev/null 2>&1; then
  fail 'controlled bad runtime candidate must fail the upgrade'
fi
assert_eq "$runtime_before" "$(nobrand_sha256_file "$MITA_BIN")" 'upgrade rollback old runtime'
assert_eq "$state_before" "$(nobrand_sha256_file "$MITA_STATE")" 'upgrade rollback install state'
assert_eq "$users_before" "$(nobrand_sha256_file "$MITA_USERS_STATE")" 'upgrade rollback users, ports, and credentials'
[ -f "$upgrade/service-restored" ] || fail 'upgrade rollback did not restore old service instances'

pass 'Mieru latest-stable resolver, integrity, runtime identity, and upgrade rollback'
