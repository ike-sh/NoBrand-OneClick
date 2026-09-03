#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/testlib.sh"

python3 - "$TEST_ROOT" <<'PY'
from __future__ import annotations

import pathlib
import re
import subprocess
import sys

root = pathlib.Path(sys.argv[1])
result = subprocess.run(
    ["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z"],
    cwd=root,
    check=True,
    stdout=subprocess.PIPE,
)
paths = [root / item.decode("utf-8") for item in result.stdout.split(b"\0") if item]

private_markers = [
    b"-----BEGIN " + kind + b" PRIVATE KEY-----"
    for kind in (b"OPENSSH", b"RSA", b"EC", b"DSA", b"ENCRYPTED")
]
binary_magics = (b"\x7fELF", b"MZ", b"!<arch>\n", b"\x1f\x8b\x08", b"PK\x03\x04")
bundle_suffixes = (".key", ".p12", ".pfx", ".mobileconfig", ".zip", ".tar.gz", ".deb", ".rpm")
infra_literals = (
    "87" + ".86.22.217",
    "172" + ".16.4.110",
    "211" + ".136.162.188",
    "211" + ".136.162.185",
    "168" + "00",
    "dev" + "-ssh",
)
uuid_literal = re.compile(
    r'["\']uuid["\']\s*:\s*["\'][0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}["\']',
    re.IGNORECASE,
)
password_literal = re.compile(r'["\']password["\']\s*:\s*["\'][^"\']{8,}["\']', re.IGNORECASE)
reality_private_literal = re.compile(
    r'(?:["\']privateKey["\']\s*:\s*["\']|\bprivate_key\s*=\s*["\']?)'
    r'[A-Za-z0-9_-]{43}(?:["\']|\b)',
    re.IGNORECASE,
)

private_hits: list[str] = []
binary_hits: list[str] = []
bundle_hits: list[str] = []
infra_hits: list[str] = []
credential_hits: list[str] = []
reality_private_hits: list[str] = []
for path in paths:
    if not path.is_file():
        continue
    relative = path.relative_to(root).as_posix()
    data = path.read_bytes()
    if any(marker in data for marker in private_markers):
        private_hits.append(relative)
    if data.startswith(binary_magics):
        binary_hits.append(relative)
    if relative.lower().endswith(bundle_suffixes):
        bundle_hits.append(relative)
    text = data.decode("utf-8", errors="ignore")
    if any(literal in text for literal in infra_literals):
        infra_hits.append(relative)
    if not relative.startswith("tests/") and uuid_literal.search(text) and password_literal.search(text):
        credential_hits.append(relative)
    if reality_private_literal.search(text):
        reality_private_hits.append(relative)

problems = {
    "private key": private_hits,
    "runtime/archive binary": binary_hits,
    "client bundle": bundle_hits,
    "real infrastructure literal": infra_hits,
    "literal TUIC credential pair": credential_hits,
    "literal REALITY private key": reality_private_hits,
}
for label, hits in problems.items():
    if hits:
        print(f"{label}: {', '.join(hits)}", file=sys.stderr)
if any(problems.values()):
    raise SystemExit(1)

print("REAL_PRIVATE_KEY_MATCHES=0")
print("REAL_REALITY_PRIVATE_KEY_MATCHES=0")
print("REAL_TUIC_CREDENTIAL_MATCHES=0")
print("REAL_INFRA_MATCHES=0")
print("RUNTIME_BINARY_MATCHES=0")
print("CLIENT_BUNDLE_MATCHES=0")
print("USER_RUNTIME_LITERAL_LEAK_COUNT=0")
PY

pass 'candidate public tree contains no private key, credential bundle, runtime binary, or lab infrastructure literal'
