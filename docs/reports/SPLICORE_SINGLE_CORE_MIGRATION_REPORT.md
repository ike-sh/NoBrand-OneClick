# NoBrand-OneClick Splicore rc.3 Migration Report

Date: 2026-10-18, Asia/Shanghai.

**SPLICORE MIGRATION BLOCKERS REMAIN**

Current integration uses public **v0.3.0-rc.3**, full commit
`72166d2fcda95b943cbae584bdd59876df7d0ed8`. No latest/main, local Splicore build,
new freeze or release is used. The [closure report](SPLICORE_SINGLE_CORE_BLOCKER_CLOSURE_REPORT.md)
contains artifact hashes, field mappings, actual traffic results and remaining blockers.

## Current implementation

- Central artifact pin, official checksum, archive safety, extracted binary hash
  and exact runtime identity all target rc.3. Both installers embed that authority.
- HY2 Salamander maps the actual old Xray/FinalMask configuration to the native
  Hysteria transport. Auth and obfs remain independent, with unchanged port,
  endpoint, SNI and existing TLS paths/content/modes. Unknown legacy fields reject.
- Complete initial migration intent must equal fresh discovery. Supplied candidate
  changes to credentials or listener identity reject before artifact download.
- Fresh HY2 installs Salamander with new valid leaf/CA TLS and independent secrets.
  Failed candidates clean only unreferenced newly minted TLS after terminal rollback.
- Plain HY2 remains independent. Core Gecko (experimental), UDP hopping and Linux
  port ranges are accurately modeled as supported, with NoBrand surface NOT EXPOSED.
- REALITY/Vision is supported by the Core. NoBrand ordinary migration/fresh install
  still rejects the unmapped defender/SNI/private-IP/port/BitTorrent policy.
- The default old HY2 CA leaf is incompatible with native rc.3 TLS. It is preserved
  and rejected, never regenerated to claim migration completion.
- Approved historical rc.2 hashes remain only for upgrade/rollback. Normal
  install/update uses rc.3; actual rc.2 → rc.3 and rollback processes are tested.

NoBrand version remains 3.2.6; this worktree has not been published. Existing
FinalMask/Sudoku stays a specialized external pinned Xray owner. SSH Tunnel and
nftables/Realm Forward retain their original utility boundaries.

## Local evidence

| Evidence | Scope / result |
|---|---|
| [rc.3 runtime probe](SPLICORE_RC3_RUNTIME_PROBE.json) | 53 recorded observations, including explicit expected REALITY policy failure; probe execution PASS |
| [rc.3 production process adapter](SPLICORE_RC3_LOCAL_INTEGRATION.json) | PASS: four representative inbounds, restart, SIGKILL/database/socket recovery and artifact download trace |
| [reference/pin audit](SPLICORE_RC3_STATIC_AUDIT.json) | Unexpected active rc.2 references 0; Splicore latest/main URLs 0 |
| [core reference classification](SPLICORE_REFERENCE_AUDIT.md) | Ordinary legacy core downloads 0 in reviewed current dispatch graph |

The real process campaign uses public rc.3 and rc.2 artifacts and the existing
pinned official Mihomo client. Actual old NoBrand generator output starts a
verified old Xray HY2 server before migration. The unchanged old client profile
passes TCP/domain and 64/512-byte UDP traffic before/after migration and rollback.
Wrong/missing obfs, bad auth, TLS rejection, public port conflict and candidate
failure preserve the working runtime. Existing TLS/state/config hashes and modes
match after rollback.

One native public rc.3 process has six healthy listeners: Vision REALITY,
Salamander HY2, plain HY2, Snell v5, Mieru TCP and TUIC v5. Vision, both HY2 modes,
Mieru TCP and TUIC traffic pass initially, after restart and after SIGKILL/relaunch.
Snell receives listener/identity validation; its client traffic is not certified.
The native REALITY control proves wire compatibility and the private-IP policy
counterexample; it is not persisted as an accepted NoBrand migration graph.

A real invalid rc.3 candidate (Mieru MTU outside the public domain) is rejected
by public inbound validation while actual rc.2 traffic remains working. A
post-apply injected failure exercises automatic rc.2 rollback. Explicit rollback
and successful upgrade preserve desired config, ports, credentials and master key.

Public `inbound validate` is structural: default old TLS file references can
pass it. NoBrand's material preflight rejects the old CA leaf; actual native
plan/apply material admission also rejects it without changing the working graph.

The old Xray baseline showed an integrity mismatch for a 1200-byte UDP echo in
this WSL environment. Larger datagrams are unqualified; no large-payload pass or
new rc.3 regression is claimed. No production environment is involved.

## Tests

All **50 default Bash entries PASS** under the isolated WSL root fixture.
Shell syntax: **108 files PASS**. ShellCheck **0.9.0 PASS**, covering the ordered
source graph and 70 direct shell files. Generated installer consistency PASS.
Final Splicore Python subtests: **50 PASS** (4 historical safety, 32 runtime,
14 rc.3 migration). The 32+14 focused tests were rerun after the final migration
identity guard change; all 46 passed. Public runtime probe: **53 observations**
reproduced, including the explicit expected REALITY policy counterexample.
The production process-adapter probe, final repository sanitization, report
links, Python parse checks and Git whitespace/index checks PASS.

The test inventory has 60 `test_*.sh` files: 50 default entries were executed;
9 opt-in native/host runtime entries and 1 standalone SOCKS5 UDP reference entry
were not run. Their qualification is not inferred from local process tests.
See [test summary and log digests](SPLICORE_RC3_TEST_SUMMARY.json).

## Reproduction

Default Bash/security/contract tests, syntax, ShellCheck and build consistency:

```bash
PYTHONDONTWRITEBYTECODE=1 NOBRAND_RUNTIME_INTEGRATION=0 bash scripts/test.sh
```

The ownership fixtures require root in the isolated test environment. Runtime
probe prerequisites are the exact verified public rc.3 artifacts, approved
historical rc.2 artifacts, official pinned Mihomo gzip, and verified old Xray
fixture. No host supervisor or firewall operations are performed by this probe:

```bash
PYTHONDONTWRITEBYTECODE=1 python3 tests/helpers/splicore_rc3_probe.py \
  --artifacts /private/rc3-artifacts \
  --rc2-artifacts /private/historical-rc2-artifacts \
  --mihomo-gzip /private/mihomo-linux-amd64-v1.19.30.gz \
  --legacy-xray /private/verified-xray-v26.3.27 \
  --output /private/rc3-probe.json

PYTHONDONTWRITEBYTECODE=1 python3 tests/helpers/splicore_local_integration.py \
  --artifacts /private/rc3-artifacts --output /private/rc3-process.json
```

Artifact downloads in the process probes substitute only HTTP transport with
verified public cache files; production resolver/checksum/archive/executable
identity gates still execute. The real public files were independently downloaded
and checked before the campaign. The pinned old Xray is used only as a previous
runtime, never through the fresh NoBrand downloader.

## Historical evidence

The old [migration report](SPLICORE_RC2_MIGRATION_REPORT.md),
[rc.2 contract](../SPLICORE-RC2-CONTRACT.md),
[rc.2 blocker attempt](SPLICORE_RC2_BLOCKER_CLOSURE_REPORT.md),
[BLOCKED freeze report](SPLICORE_SINGLE_CORE_FREEZE_REPORT.md), and their existing
JSON probes remain history. Their rc.2 limitations are not current rc.3 claims.
The two prior reports were copied intact before replacing their current filenames.
The historical probe helpers explicitly select the approved old manifest entry.

## Qualification and Git

Native systemd: PENDING. Native OpenRC: PENDING / N/A. Real legacy host and old
production-client traffic: PENDING. Linux arm64 runtime: NOT CERTIFIED. Real
nftables/CAP_NET_ADMIN server ranges: PENDING. These host qualifications are
separate from the remaining REALITY policy and default HY2 TLS contract blockers.

Branch main, HEAD `f98cf70e7159c07826101676a4a08394f0a203f9` unchanged.
Stage / Commit / Push / Tag / Release: **NONE**. Index: **EMPTY**.
No production access or new freeze was performed.
