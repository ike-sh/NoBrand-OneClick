# NoBrand-OneClick Splicore rc.4 Fresh Architecture Freeze Report

Date: 2026-10-21. Scope: one local architecture freeze commit, without remote publication.

## Status

**SPLICORE RC.4 FRESH ARCHITECTURE FROZEN**

| Meaning | Result |
|---|---|
| Implementation | FROZEN |
| Local validation | PASS |
| Public rc.4 runtime qualification | PASS within the completed Linux amd64 loopback campaign |
| External platform qualification | PENDING |

This is not certification for every production platform. The earlier
[acceptance report](SPLICORE_RC4_FRESH_ARCHITECTURE_REPORT.md) remains an unchanged
checkpoint of the review phase; its unstaged/not-frozen Git status describes that
earlier phase. This report records the subsequent freeze.

## Maintainer Policy

- Legacy multi-core in-place migration: **NOT SUPPORTED**.
- Fresh install: **SUPPORTED within the stated qualification limits**.
- Fresh credentials, certificates and client profiles are generated. Old client,
  certificate, port and multi-core service compatibility is outside this contract.
- Freeze adds no features or protocols, changes no Splicore implementation and
  introduces no migration path. Only this report and README freeze metadata were
  added/updated after the final implementation verification.

## Core

| Item | Frozen value |
|---|---|
| Primary | Splicore |
| Version | `v0.3.0-rc.4` |
| Public tag commit | `2634ea50d19623591c5db63329a288862726db74` |
| Release pin | EXACT; `runtime/splicore-release.json` |
| Latest/branch/nightly used | NO |
| Active rc.2/rc.3 integration | NONE |
| Local Splicore source tree / unpublished binary dependency | NONE |

The previously audited public release archives were reused privately. The rerun
download trace contains exactly the rc.4 amd64 archive URL and its `SHA256SUMS`.
The cache replaces HTTPS transfer only; archive, checksum, ELF, extracted binary
digest and executed version identity checks run against the actual public bytes.
The public binary's upstream channel field is `development`; its exact pinned
version, commit, `dirty=false`, platform and digest match the audited release.
See [artifact evidence](SPLICORE_RC4_ARTIFACT_AUDIT.json).

## Architecture

| Responsibility | Owner |
|---|---|
| Deployment, desired config, client profiles, lifecycle | NoBrand orchestrator |
| Mieru, Snell, HY2, TUIC, REALITY | One primary Splicore daemon |
| Architecture marker | `architecture=splicore-native` |
| Core identity in state | `splicore_version=v0.3.0-rc.4` |
| Desired config version | `config_schema=1` |
| Product registry | `schema_version=3` |

Architecture is not inferred from binary existence. Each generation owns native
desired state, DB, master key, control socket config and its verified executable.
Private validation daemons are temporary. Protocol wrappers share one runtime
and do not install separate ordinary proxy cores or own legacy services.
The two standalone installers embed the same runtime/launcher/manifest and are
byte-identical to one another and to the current generated build.

## Legacy Policy

| Gate | Result |
|---|---|
| Owned legacy detection | PASS |
| Detection before locks/packages/downloads/service changes | PASS |
| Automatic migration / partial migration | NO |
| Mutation after detection | NONE |
| Old service stop, config/credential/certificate rewrite | NONE |
| Automatic legacy uninstall | NO |
| Legacy uninstall by new architecture | NOT SUPPORTED; REFUSED |
| Third-party same-name binaries/services claimed | NO |
| Legacy backup import | REFUSED before extraction |

The rerun covers unchanged legacy bytes and zero runtime/service/download effects,
including actual Bash main entrypoints. Legacy doctor/status only detect/report
the unsupported installation. Native uninstall/purge remains repeatable and
bounded to NoBrand-owned native resources; it does not guess at third-party or
legacy ownership. Existing SSH administrator-confirmation and Sudoku/Forward
ownership boundaries remain.

## Artifact Security

Exact version resolution, `x86_64/amd64` and `aarch64/arm64` normalization,
`SHA256SUMS`, exact asset checksum, archive member/type/path/size safety, temporary
extraction, ELF architecture, binary digest, executed product/version identity
and atomic publication: **PASS**. Corruption, wrong version/identity, missing
checksum, unsupported architecture and unsafe archive entries fail closed.

| Asset | Archive SHA256 | Binary SHA256 | Scope |
|---|---|---|---|
| linux-amd64 | `9dd1941c817143d18ea1c892a5fc13266c1b209600576946504a9d3c98c62161` | `0a347f06f0d1a17ef37edd779826ad79739217b65f80bf39dc6077f115ac175f` | Public executable and loopback runtime PASS |
| linux-arm64 | `5b5e39bd8e6ef373ebc00e7e3a8a688ce09d0369dc2c4ecfab06ed535d948b64` | `85ec863d21707ac309a4c7a64b3b7228eb34bb0405379db6b569d8d550032a4c` | Static artifact checks; BUILD ONLY / runtime NOT CERTIFIED |

## REALITY

| Gate | Result |
|---|---|
| Native REALITY + Vision | PASS |
| Native Local Tunnel Guard | PASS |
| Protected destination | PASS; fixed cover target, loopback guard |
| Pre-cutover native guard/rule validation | PASS |
| Old Xray defender syntax/compatibility | OUT OF SCOPE |

Guard rules allow the exact approved cover SNI to the fixed destination, followed
immediately by a guard-scoped reject. Sniffed SNI cannot replace that destination.
Authenticated VLESS proxy traffic is not constrained to the cover whitelist.

| Public binary probe | Result |
|---|---|
| Valid newly exported REALITY + Vision client | PASS; proxy traffic succeeds |
| Wrong UUID / short-id / client SNI | PASS; proxy traffic rejected |
| Approved plain TLS | PASS; intended fixed cover responds |
| Unapproved plain TLS SNI | PASS; rejected |
| HTTP / random TCP / malformed TLS / missing or unusable SNI | PASS; fail closed on public and direct guard listeners |
| Arbitrary sniffed SNI / unsafe fallback / open proxy | Not observed; negative probes PASS |

## HY2

| Gate | Result |
|---|---|
| Fresh HY2 on Splicore rc.4 | PASS |
| New private CA and non-CA server leaf | PASS |
| Verified client trust / wrong pin rejection | PASS |
| Salamander / wrong auth and obfs rejection | PASS |
| Legacy CA/leaf migration | OUT OF SCOPE; absent |
| Gecko | Core SUPPORTED / EXPERIMENTAL; NoBrand NOT EXPOSED |
| UDP Port Hopping | Core SUPPORTED; NoBrand NOT EXPOSED |
| Linux nftables server range | PENDING / NOT RUN; default off |

Gecko/port-hopping UI was not added. Fresh REALITY/HY2/Mieru/Snell/TUIC client
profiles agree with native desired config. The pinned public Mihomo v1.19.30
reference client passed traffic, restart and SIGKILL recovery checks for all five
managed inbounds. Only the documented client versions/transports are qualified.

## Single Core

- Primary runtime: **Splicore**, one active ordinary daemon.
- Ordinary legacy core downloads: **0**.
- Unexpected proxy core downloads/runtime paths: **0**.
- Existing FinalMask/Sudoku keeps its dedicated pinned Xray exception; SSH uses
  system OpenSSH and Forward uses Realm/nftables. These are retained special
  features. Ordinary protocols cannot fall back to their runtime downloaders.

## Legacy Code Audit

Repeated case-insensitive searches covered `xray`, `sing-box`, `singbox`,
`hysteria`, `mieru`, `mita`, `legacy` and `migration` in active source/runtime,
generated installers, tests, scripts and documentation. Reference classes:

| Class | References and disposition |
|---|---|
| NEW ARCHITECTURE REQUIRED | Native protocol/transport identifiers, client export formats (including Xray/sing-box/Mieru client formats), shared lifecycle/admin/firewall helpers, current Ingress default-route identifier and native Profile reassignment. Historical `MITA_*` journal field names do not implement old runtime migration. |
| LEGACY DETECTOR | Owned old paths/service markers, unsupported-state notices, early preflight, non-native architecture/backup rejection. Read-only refusal only. |
| SPECIAL FEATURE | Dedicated Sudoku Xray constants, downloader, config validator, service, export and owned rollback; retained SSH/Forward components. |
| HISTORICAL REPORT | The original 16 reports, rc.2/rc.3 contracts, old release/parity/scope documents and origin/license notices. Original conclusions remain intact. |
| TEST FIXTURE | Current negative fixtures and retired old tests/probes, external platform/container recipes and their workflow references. They do not run in ordinary installation and are not counted as current runtime PASS. |
| DEAD CODE | **0 unexpected legacy migration implementations**. Removed conversion, legacy certificate import, ordinary core downloaders, multi-core stop/restore and compatible-upgrade APIs remain absent. |

`DEAD LEGACY MIGRATION CODE=0`; `UNEXPECTED LEGACY RUNTIME PATH=0`.
The source orphan/duplicate/accidental-override audit also reports `0 / 0 / 0`.
Generated installer references mirror the verified embedded source. Current
Ingress "migration" means native policy reassignment, not old Core conversion.

The unchanged external CI workflow still names historical campaigns and does not
supply the current optional `--runtime` artifact/reference-client inputs. It was
not executed or certified here. Historical external recipes require review and
platform qualification before a future publication; no such job is claimed PASS.

## Tests

The freeze reran `bash scripts/test.sh --runtime` against the final implementation
and generated installers; exit code **0**. Counts below were read from the actual
runner log, Python summaries, runtime result keys and syntax glob, not copied as
targets from the prior report.

| Gate | Actual result |
|---|---|
| Bash acceptance entrypoints | **28 / 28 PASS** |
| Python native transactions | **27 / 27 PASS**, no skips |
| Python fresh policy | **10 / 10 PASS**, no skips |
| Python total | **37 / 37 PASS** |
| Public rc.4 runtime/security checks | **42 / 42 PASS** |
| Shell syntax | **111 files PASS** |
| ShellCheck | PASS: source model, both installers, scripts and all test files |
| Build consistency | PASS |
| Secret/public-tree scan | PASS; real secret leaks/runtime binaries/bundles detected: 0 |
| Diff whitespace checks | PASS: worktree and staged diff |
| Historical report hashes | **16 / 16 unchanged**, including staged bytes |

The sanitized runtime result is identical to the preserved
[42-check acceptance evidence](SPLICORE_RC4_FRESH_RUNTIME_PROBE.json).
The five code hashes in the earlier [test summary](SPLICORE_RC4_TEST_SUMMARY.json)
still match. The only optional skip is the real Sudoku Xray validator, outside
the native rc.4 campaign; its isolated static/transaction tests passed. Native
platform qualification was not run. Raw logs, archives, credentials and private
runtime state remain ignored and unstaged.

## Historical Reports

Count: **16**. Modified: **NO**. Byte identity: **PRESERVED** against the baseline
recorded before architecture cleanup and checked again during freeze/staged audit.
BLOCKED, rc.2/rc.3, ownership and migration conclusions were not rewritten.
The four current rc.4 acceptance/evidence files were also retained unchanged.

## Upgrade Model

| Contract | Result |
|---|---|
| Legacy multi-core -> Splicore | NOT SUPPORTED |
| Splicore-native -> future reviewed Splicore | Framework SUPPORTED; reviewed manifest required |
| Same version/config | VERIFY / NO-OP; public binary check PASS |
| Atomic binary update / candidate validation | PASS |
| Known-good binary/config/DB/master-key rollback | PASS in native transaction tests |
| Real failed-config rollback and restored traffic | PASS |
| Persistent recovery / concurrent request rejection | PASS |

No unreviewed future release or rc.5 wire compatibility is certified. Rollback
stays inside the native architecture and never restarts an old multi-core stack.
Doctor/status check Splicore identity/config/service/listeners/certificates,
native REALITY guard and protocol state; unit and local runtime gates pass.

## Qualification Limits

| Area | Qualification |
|---|---|
| Linux amd64 loopback / local process supervisor | PASS within the stated public rc.4 campaign |
| Native systemd runtime | **PENDING** |
| Native OpenRC runtime | **PENDING**; templates supported |
| Linux arm64 runtime | **BUILD ONLY / NOT CERTIFIED** |
| Linux nftables port-range runtime | **PENDING / NOT RUN** |

These are qualification limits, not fresh architecture implementation blockers.
Public rc.4 remains Release Candidate / Experimental.

## Production Safety

Production hosts and real customer nodes: **UNTOUCHED**. No production SSH was
requested. No actual legacy installation was migrated. Tests used temporary
loopback processes and isolated discovery/state roots, with mapped root ownership
in a Linux user namespace. Host init units, accounts and network rules were not
changed. Local Splicore source HEAD was not queried or modified.

## Docker / Redis / TeleLedger

**UNTOUCHED / NOT QUERIED**. Reading repository test/workflow text did not execute
or contact these systems.

## Commit

| Item | Value |
|---|---|
| SHA | The unique commit introducing this report; resolve with the command below |
| Sole parent / BASE_COMMIT | `f98cf70e7159c07826101676a4a08394f0a203f9` |
| Message | `refactor(core): adopt Splicore rc.4 fresh architecture` |
| Commit count above BASE_COMMIT | **1** |
| Files | 104 |
| Insertions | 28387 |
| Deletions | 59677 |

```bash
git log -1 --format=%H -- docs/reports/SPLICORE_RC4_FRESH_ARCHITECTURE_FREEZE_REPORT.md
```

A commit cannot contain its own literal SHA without changing that SHA. This
report therefore uses the resolvable identity above. The full resulting SHA and
sole parent are recorded in the completion response and private post-commit
receipt. No amend or second metadata commit is used.

All staged paths were explicit individual files from the reviewed preflight
inventory plus this report. No directory-wide add was used. The final staged
file list, bytes, statistics, historical hashes, secret/legacy/latest scans and
worktree/index correspondence were checked before the single commit.

## Git

| Item | Final state |
|---|---|
| Working tree | CLEAN |
| Index | EMPTY |
| Branch | `main` |
| main | Same as the freeze commit; already the current branch |
| Pre-freeze HEAD / MAIN_HEAD | `f98cf70e7159c07826101676a4a08394f0a203f9` |
| Parent count | 1; sole parent equals pre-freeze BASE_COMMIT |
| History rewritten | NO |
| Extra branch/main synchronization | NONE required |

Post-commit verification checks status, HEAD/parents, one-commit distance from
BASE_COMMIT, commit stat/summary and graph log. No reset, clean, restore, stash,
rebase, squash, force or history rewriting was performed.

## Remote

| Action | Result |
|---|---|
| Push | NONE |
| Tag | NONE |
| Release | NONE |

Origin configuration was read in preflight; no fetch, remote ref update or
publication was performed. The existing `v3.2.6` tag remains on BASE_COMMIT.

## Final Result

**SPLICORE RC.4 FRESH ARCHITECTURE FROZEN**

## Blockers

**NONE** for this local fresh architecture freeze.

## Qualification Debt

- Native systemd runtime.
- Native OpenRC runtime.
- Linux arm64 runtime.
- Real Linux nftables port-range runtime.
- External CI/platform recipe review and qualification before publication;
  optional real Sudoku validator and additional client combinations remain
  outside the completed native rc.4 campaign.

No next phase was started.
