# NoBrand-OneClick Splicore Single-Core Migration Freeze Report

Date: 2026-10-17, Asia/Shanghai.

## Final result

**SPLICORE SINGLE-CORE MIGRATION FREEZE BLOCKED**

The requested full protocol-coverage gate is not satisfied. The earlier
`IMPLEMENTATION COMPLETE / LOCAL VALIDATION PASS` describes the expressible
rc.2 subset, not migration of every formally supported ordinary mode.
**EXTERNAL RUNTIME QUALIFICATION PENDING** remains a separate qualification
limit and is not the cause of this freeze decision.

No functional code, version or acceptance assertion was changed for this
freeze audit. Staging and committing are conditional on closing the coverage
gate; neither has been performed.

## Maintainer decision

Decision date: 2026-10-18, Asia/Shanghai.

The maintainer explicitly selected strict section 3 coverage: freeze **BLOCKED**,
retain this report and do not commit. No narrower freeze scope was authorized.
Stage / Commit / Push / Tag / Release remain **NONE**.

Blocker closure follow-up (2026-10-18): both blockers remain OPEN. Public-binary
traffic and negative probes now distinguish native support from old-profile and
security-policy equivalence. See the [closure attempt report](SPLICORE_SINGLE_CORE_BLOCKER_CLOSURE_REPORT.md).
This follow-up does not repeat or change the historical BLOCKED freeze decision.
The 2026-10-18 continuation independently rechecked public release source and
asset digests and replayed the blocker probe with the same 30 observations;
both blockers remain OPEN. No new freeze was attempted.

## Migration status

| Field | Actual result |
|---|---|
| Expressible-subset implementation | COMPLETE |
| Full ordinary-protocol coverage | INCOMPLETE; REALITY and existing Salamander HY2 are not migrated |
| Local validation | PASS; complete default suite rerun exited 0 |
| External runtime qualification | PENDING; not a freeze blocker by itself |
| Full-scope freeze | BLOCKED |

## Baseline

| Field | Observed value |
|---|---|
| Current branch | main |
| BASE_COMMIT / CURRENT_HEAD / MAIN_HEAD | f98cf70e7159c07826101676a4a08394f0a203f9 |
| NoBrand version | 3.2.6 / v3.2.6; unchanged |
| Index | EMPTY |
| Worktree | migration implementation, tests, generated installers and documentation only; uncommitted |
| Remote | origin: https://github.com/ike-sh/NoBrand-OneClick.git (fetch/push) |
| History | no unexpected commit; no rewrite |
| Existing branch model | main reflog records ff-only integration of codex/v3.2.6-final-hardening, codex/v3.2.4-release-gate-fix and codex/issue-1-mieru-endpoint |

Status, branch, HEAD/main, remotes, log graph, index, tracked diff and all
nonignored untracked paths were inspected. No unrelated change or staged file
was found. No reset, clean, restore, stash, rebase or main movement occurred.

## Target core

| Field | Result |
|---|---|
| Core / repository | Splicore / ike-sh/Splicore |
| Version | exact v0.3.0-rc.2 |
| Public commit | 926f3274fd44ac618cc276951eefe2d27134f687 |
| Release | PINNED; Release Candidate / Experimental |
| Actual binary channel | development |
| GitHub Latest for Splicore | NOT USED |
| Local Splicore source/build required | NO |
| Public artifact sufficient | YES for the implemented subset; NO for full existing-mode equivalence |

Authority: [release manifest](../../runtime/splicore-release.json),
[public contract audit](../SPLICORE-RC2-CONTRACT.md).

## Protocol coverage and blocking gate

The formal baseline includes Mieru, Snell v4/v5 (including its optional QUIC
mode), Hysteria2 with Salamander, TUIC v5, VLESS REALITY/Vision and specialized
FinalMask/Sudoku. SSH and Forward are separate utilities. See the original
[inventory](SPLICORE_PRE_MIGRATION_AUDIT.md#current-protocol-inventory-and-migration-matrix)
and current [migration matrix](SPLICORE_SINGLE_CORE_MIGRATION_REPORT.md#protocol-migration-matrix).

| Protocol / mode | Actual current implementation | Full-scope freeze assessment |
|---|---|---|
| Mieru TCP/UDP/BOTH with expressible settings | Splicore; BOTH is a credential-preserving TCP:P / UDP:P+1 pair in one daemon | supported subset implemented; profile/pair mutations and rollback covered locally |
| Mieru traffic-pattern/Low Entropy/quota/expiry/rate | rejected before cutover; existing deployment retained | formal legacy options are not migrated; not an external-host qualification issue |
| Snell v4/v5 with compatible PSK, QUIC off | Splicore; version/PSK/port preserved | supported subset implemented; v5 wire qualification pending |
| Snell v5 QUIC / valid legacy PSKs outside rc.2 domain | rejected before cutover | formal legacy options are not migrated; no implicit credential rotation |
| TUIC v5 with valid non-CA leaf, SAN, CA and private key | Splicore; UUID/password/port preserved | implemented; existing generated CA-leaf certificates reject unchanged |
| Existing Hysteria2 + Salamander | migration and ordinary install rejected | **BLOCKER: formal ordinary mode is not migrated** |
| Canonical plain Hysteria2 | Splicore; local public-binary smoke passes | does not replace the existing Salamander profile |
| Ordinary VLESS + REALITY + Vision | managed=false; migration and install rejected | **BLOCKER: section 3 explicitly requires this ordinary mode to use Splicore** |
| Existing VLESS + FinalMask/Sudoku | retained independent pinned Xray | legitimate specialized exception; no new specialized mode added |
| SSH Tunnel | existing system OpenSSH | required utility; independent owner |
| Port Forward | nftables / pinned Realm | required network utility; independent owner |
| NaiveProxy, standalone mKCP, XHTTP, plain VLESS installer | absent from the NoBrand baseline | N/A; not added |

Ordinary fresh-install paths that proceed still use only Splicore. Ordinary
fresh paths invoking a legacy core: **0 in the reviewed call graph**. However,
that count does not establish complete coverage: refusing a formal ordinary
mode is not the same as migrating it. An incompatible legacy host remains
entirely on its old deployment. That preserved deployment is not a successfully
committed Splicore migration or an authorized generic Xray fallback.

### Exact blockers

1. **REALITY_COVERAGE**: `runtime/splicore-release.json` marks vless-reality
   unmanaged. `render()` rejects unmanaged protocols and `protocol(..., install)`
   rejects REALITY. UUID/private-key fields alone do not preserve the existing
   loopback defender, SNI dispatch, private-IP/blocked-port and protocol routing
   policy. No equivalent adapter mapping/adversarial acceptance is implemented.
2. **HY2_SALAMANDER_COVERAGE**: existing NoBrand HY2 renderers and client exports
   require Salamander. Public rc.2 settings explicitly declare no obfs and its
   binary rejects both probed Salamander representations. Removing the option
   would change existing client behavior. Plain HY2 does not close this gap.

Other restrictions are recorded separately: Mieru advanced/accounting options,
Snell QUIC and incompatible PSKs, and rejected old TLS material fail before
cutover, as section 12 permits. They are not additional independent blockers in
this decision. Neither safety rejection nor the two whole-mode coverage gaps
above is a real-client or native-host qualification PASS.

These are product/contract coverage gaps under the requested full-scope gate,
not missing native hosts or unexecuted real-client traffic. No weaker security
mapping, generic Xray fallback, sidecar, new protocol, version upgrade or
certificate/credential replacement was introduced to obtain a freeze PASS.

## Artifact and download audit

| Gate | Evidence / result |
|---|---|
| Architecture normalization | x86_64/amd64 -> amd64; aarch64/arm64 -> arm64; others reject |
| SHA256SUMS / exact entries | public amd64 and arm64 entries match immutable manifest hashes |
| Archive safety | allowlisted regular files, traversal/absolute/link/device/duplicate/unexpected entries rejected |
| Binary identity | pinned ELF architecture and binary SHA checked before execution; exact product/version/commit/platform checked |
| Temporary staging / atomic selection | private staging and immutable generation; atomic pointer replacement; known-good rollback fixtures |
| Missing/corrupt/partial artifact | fail before live service mutation |
| Fresh supported ordinary core downloads | Splicore archive plus same-release SHA256SUMS only |
| Non-core dependencies | Bash/Python/curl/OpenSSL/jq/tar/network tools; generated TLS material and local manager script; not additional proxy cores |
| Specialized/utility downloads | pinned Xray only for explicit existing Sudoku; optional pinned Realm utility; outside ordinary core trace |
| Splicore Latest / unknown primary downloader / generic fallback_core=xray | 0 / 0 / NO in the reviewed primary call graph |

Both archive and binary digests are in the central manifest and the migration
report. Freeze contract replay used those public cached archives, not a local
build. Only HTTP transport was substituted with the public artifact cache;
the real artifact/checksum/archive/identity gates ran.

## Runtime acceptance and test inventory

| Check | Current evidence |
|---|---|
| Public amd64 quick smoke | PASS; rerun for this freeze audit |
| Single Splicore process / four inbounds | PASS: Snell v5, Mieru TCP, plain HY2, TUIC v5 |
| Normal restart / SIGKILL database recovery | PASS / PASS; rerun for this audit |
| Probe cleanup | daemon stopped, current pointer and temporary directory removed |
| Full default suite | PASS: freeze replay of `bash scripts/test.sh` exited 0; all 49 Bash test files |
| Runtime unit tests / contract safety tests | 32 PASS / 4 PASS; source inventory independently confirmed and cases included in the default suite |
| Bash syntax / ShellCheck / build | PASS: `bash -n`, ShellCheck at warning severity, generated installer consistency and build check |
| Lifecycle interruption recovery | PASS: 4 install, 10 repair and 9 uninstall checkpoints, plus signal/concurrent-lock recovery |
| Source/distribution integrity | PASS: 125 functional files match the audit SHA256 snapshot; no functional code changed |
| Documentation links / diff whitespace | PASS: 0 broken current local links; git diff --check clean |
| Native runtime harness | NOT INVOKED; NOBRAND_RUNTIME_INTEGRATION=0 |

The four-protocol campaign excludes REALITY entirely and uses plain HY2 rather
than the formal old Salamander mode. It also does not exercise every Mieru
transport/profile, Snell mode or old certificate. It is not an all-protocol
runtime qualification PASS. No actual legacy client traffic was sent.

Local ignored evidence: `.lab/splicore-rc2-audit/freeze-tests.log`,
`freeze-local-integration.json`, `freeze-contract-probe.json` and a 125-file
functional-source/distribution SHA256 snapshot. These logs, archives, binaries,
temporary state and validation directories are not staged.

## Configuration, ownership and lifecycle

| Area | Local implementation / evidence |
|---|---|
| Canonical owner | NoBrand schema-1 desired values -> typed managed documents -> one native SQLite/key generation; no direct SQL edits |
| Primary service | one nobrand-splicore.service or OpenRC nobrand-splicore; protocol modules do not own separate primary daemons |
| Migration | discover/plan/candidate validate/private snapshot/journal -> stop conflicts/start/apply/health -> retire legacy/commit orchestration state |
| Pre-cutover rejection | unsupported options, invalid config/TLS, architecture, artifact/checksum and port conflict gates precede legacy stop |
| Credentials / ports | preserved for expressible fixtures; unsupported cases reject without rotating identities or renumbering ports |
| TLS / REALITY | existing certificate paths retained; invalid old TLS rejected; REALITY rejected without rotating keys or dropping policy |
| Backup | matching stopped SQLite/master.key, owned pointer records and bounded generations; product restore rollback covered |
| Rollback | previous generation and exact active/enabled set restored; first committed migration can restore retained legacy files/services |
| Repeated install/update | verify/no-op or one complete transaction; no duplicate primary service/artifact ownership |
| Shared config changes | complete generation replay; shared daemon restart briefly interrupts all ordinary connections |
| Retired legacy services | zero active expected in compatible migration fixtures; real migrated-host audit PENDING |
| Doctor/status | Splicore actual/pinned version, canonical nodes, service/listener health and reactivated legacy detection; read-only resource-map check |
| Logs | no old View Xray/sing-box/Mieru logs menu found in ordinary UI; native service output belongs to the single primary unit; no new log UI added |
| Certificate renewal hooks | no ACME/certbot/reload hook found; existing generation uses static certificate files; N/A |
| Cron/timer/watchdog | Mieru scan/tc timers retired or owned OpenRC cron saved/removed with rollback restoration; SSH administrator watchdog remains a separate utility |
| Uninstall/purge | owned service/state/TLS removal and dangerous-root/pointer/foreign-owner rejection covered by fixtures; third-party resources preserved |

## Legacy core reference classification

The renewed source/docs/test search and indirect-call review use the existing
[reference audit](SPLICORE_REFERENCE_AUDIT.md), with these required categories:

| Category | Retained references |
|---|---|
| LEGACY MIGRATION | old Mita/Snell/sing-box/ordinary Xray detection, snapshot, explicit historical restore and interrupted legacy recovery; dormant binaries/configs until traffic qualification |
| SPECIALIZED EXTERNAL XRAY | existing FinalMask/Sudoku installer/renderer/service; shared pinned Xray helper only at that explicit boundary or historical recovery |
| HISTORICAL DOC | archived release/scope/audit/reference contracts and the original core inventory; current notices identify historical scope |
| REQUIRED NON-RUNTIME UTILITY | client format names/exports, native protocol identifiers/managed documents, tests/build inputs and separate SSH/Realm/network tools; not separate ordinary legacy core owners |
| UNEXPECTED | 0 in the reviewed ordinary-primary runtime/download call graph; coverage failures above remain separate blockers |

Generated installers inherit their exact source classifications. No claim is
made that all old strings/functions were removed, or that zero unexpected
downloads proves all formal protocols were migrated.

## Existing client compatibility and qualification limits

Existing Client Wire Compatibility:
**IMPLEMENTATION / CONTRACT VALIDATED LOCALLY** for the expressible subset.
**REAL LEGACY CLIENT RUNTIME QUALIFICATION PENDING**.

| Platform / scenario | Qualification |
|---|---|
| Linux amd64 private process | LOCAL RUNTIME PASS |
| Native Linux amd64 systemd | PENDING EXTERNAL QUALIFICATION |
| OpenRC | existing project support and primary fixture implementation retained; native host PENDING |
| Real legacy multi-core host migration | PENDING EXTERNAL QUALIFICATION |
| Real pre-existing client -> migrated service | PENDING EXTERNAL QUALIFICATION |
| Native supervisor crash/restart | PENDING EXTERNAL QUALIFICATION |
| Linux arm64 | public asset/checksum/ELF/build path verified; BUILD ONLY / runtime NOT CERTIFIED |

None of these external pending qualifications is a freeze blocker by itself.
No external platform qualification was attempted during this freeze audit.

## Security and protected resources

SHA256/archive/identity/TLS verification stays enabled. Only synthetic test
credentials are used. Repository secret/binary/credential-bundle scan is part
of the default suite and passed again in the freeze replay: real private-key,
REALITY key, TUIC credential pair, infrastructure literal, runtime binary and
client-bundle match counts are all 0. Final documentation changes are rescanned
before handoff; the final rescan also passed with these zero match counts.

Production hosts/services: UNTOUCHED. Production credentials: NOT REQUESTED.
D:\code\Splicore: UNMODIFIED and not required by the runtime. Docker: NOT
QUERIED / UNMODIFIED. Redis and TeleLedger: UNTOUCHED.

## Commit, Git and remote/release

| Field | Actual state |
|---|---|
| Stage | NONE; coverage gate not satisfied |
| Commit | NOT CREATED |
| SHA / message / parent / committed file counts | N/A; no migration commit exists |
| Intended message if authorized gates close | refactor(core): migrate deployments to Splicore |
| Working tree | DIRTY: migration work and this audit; not falsely reported CLEAN |
| Index | EMPTY |
| main / HEAD | unchanged at baseline f98cf70e7159c07826101676a4a08394f0a203f9 |
| Main ff-only integration | NOT EXECUTED; failed coverage gate |
| Staged/post-commit audits | N/A; no staging/commit performed |
| History rewritten | NO |
| Push / tag / release | NONE / NONE / NONE |

## Blockers

REALITY_COVERAGE and HY2_SALAMANDER_COVERAGE prevent asserting the requested
full-scope freeze. Other explicit option restrictions remain subject to the
pre-cutover rejection contract, separately from these whole-mode gaps.
On 2026-10-18 (Asia/Shanghai), the maintainer explicitly selected strict section 3
coverage and retained the BLOCKED decision and report without committing.
No narrower freeze scope was authorized. Native platform and real-client PENDING
items remain qualification limits, not substitutes for these coverage findings.
