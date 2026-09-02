#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/testlib.sh"

python3 - "$TEST_ROOT/src" <<'PY'
import pathlib, re, sys

root = pathlib.Path(sys.argv[1])
files = sorted(root.glob("*.sh"))
texts = {p: p.read_text(encoding="utf-8") for p in files}
joined = "\n".join(texts.values())
defs = []
generated_hook_names = {"depend", "start_pre"}
golden_parity_primitives = {"infer_profile_from_values", "write_server_config"}
for path, text in texts.items():
    for line_no, line in enumerate(text.splitlines(), 1):
        match = re.match(r"^([A-Za-z_][A-Za-z0-9_]*)\(\)\s*\{", line)
        if match:
            if match.group(1) not in generated_hook_names:
                defs.append((match.group(1), path.name, line_no))

by_name = {}
for name, path, line_no in defs:
    by_name.setdefault(name, []).append((path, line_no))
duplicates = {name: sites for name, sites in by_name.items() if len(sites) > 1}
orphans = []
for name, path, line_no in defs:
    if name in golden_parity_primitives:
        continue
    count = len(re.findall(rf"(?<![A-Za-z0-9_]){re.escape(name)}(?![A-Za-z0-9_])", joined))
    if count <= 1:
        orphans.append((name, path, line_no))

if duplicates:
    for name, sites in sorted(duplicates.items()):
        print(f"duplicate function {name}: {sites}", file=sys.stderr)
    raise SystemExit(1)
if orphans:
    for name, path, line_no in orphans:
        print(f"orphan function {name}: {path}:{line_no}", file=sys.stderr)
    raise SystemExit(1)
print("FUNCTION_ORPHAN_COUNT=0")
print("FUNCTION_DUPLICATE_COUNT=0")
print("ACCIDENTAL_OVERRIDE_COUNT=0")
PY

for source_path in "$TEST_ROOT"/src/*.sh; do
  source_name="${source_path##*/}"
  lint_count="$(grep -F -c "source \"\${SOURCE_ROOT}/src/${source_name}\"" \
    "$TEST_ROOT/scripts/shellcheck-src.sh" || true)"
  [ "$lint_count" -eq 1 ] \
    || fail "ShellCheck source model must include src/${source_name} exactly once"
done

for removed in \
  install_mita_systemd install_mita_openrc install_mita_service \
  ensure_mita_daemon wait_mita_socket apply_config collect_ports_from_mita \
  extract_bindings_from_describe mita_sync_user_names mita_actual_user_names \
  mita_delete_user_exact; do
  if grep -R -n -E "^${removed}\\(\\)[[:space:]]*\\{" "$TEST_ROOT/src" >/dev/null; then
    fail "removed default/single-instance API remains: $removed"
  fi
done

if grep -R -n -E 'pkill[[:space:]]+(-[^[:space:]]+[[:space:]]+)*mita|killall[[:space:]]+mita' \
  "$TEST_ROOT/src" >/dev/null; then
  fail 'process-name-wide Mita cleanup remains'
fi
if grep -R -n -E 'install-mita|mita-menu|MITA_LEGACY_|mita-real' \
  "$TEST_ROOT/src" "$TEST_ROOT/scripts" "$TEST_ROOT/.github" >/dev/null; then
  fail 'removed management compatibility or raw-main installation path remains active'
fi
if grep -n -E 'raw\.githubusercontent\.com/ike-sh/NoBrand-OneClick/main' \
  "$TEST_ROOT/README.md" "$TEST_ROOT/CONTRIBUTING.md" "$TEST_ROOT/docs/MODULARIZATION.md" \
  >/dev/null; then
  fail 'raw-main installation path remains in active documentation'
fi
[ ! -e "$TEST_ROOT/install-mita.sh" ] || fail 'second root installer must not exist'
[ ! -e "$TEST_ROOT/dist/install-mita.sh" ] || fail 'second dist installer must not exist'
[ -f "$TEST_ROOT/install-nobrand.sh" ] || fail 'canonical installer missing'
[ -f "$TEST_ROOT/dist/install-nobrand.sh" ] || fail 'canonical dist installer missing'

pass 'dead-code, duplicate-definition, single-installer, and removed-management API audit'
