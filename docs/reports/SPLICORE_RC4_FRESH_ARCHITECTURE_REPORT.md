# NoBrand-OneClick Splicore rc.4 Fresh Architecture Report

Date: 2026-10-21. Scope: implementation and architecture cleanup; **not a freeze or release**.

## Maintainer Decision

- Legacy multi-core in-place migration: **NOT SUPPORTED**.
- Fresh installation: **SUPPORTED within the qualification limits below**.
- New installations generate new credentials, TLS material and client profiles. Existing legacy client compatibility is not an acceptance requirement.
- Owned legacy evidence causes a read-only refusal before locks, dependency installation, downloads, backups or service actions. Use the matching legacy version to back up/remove it, then clean install.

## Baseline

| Item | Recorded state |
|---|---|
| Branch | `main` |
| HEAD | `f98cf70e7159c07826101676a4a08394f0a203f9` |
| MAIN_HEAD | Same as HEAD |
| Index at start | EMPTY |
| Working tree at start | Existing single-core migration development, including untracked runtime, contracts, probes and historical reports |
| Unrelated changes | None identified; existing applicable work retained |
| Destructive Git operations | No reset, clean, restore, stash or rebase |

The initial status and 16 historical report SHA256 values were recorded privately before edits. All 16 historical reports are byte-identical to that baseline. Their rc.2/rc.3, BLOCKED and PENDING conclusions remain historical evidence, including:

- [single-core migration](SPLICORE_SINGLE_CORE_MIGRATION_REPORT.md)
- [single-core freeze](SPLICORE_SINGLE_CORE_FREEZE_REPORT.md)
- [blocker closure](SPLICORE_SINGLE_CORE_BLOCKER_CLOSURE_REPORT.md)
- [final ownership audit](SPLICORE_FINAL_BLOCKER_OWNERSHIP_AUDIT.md)

## Target Core

| Item | Value |
|---|---|
| Repository | `ike-sh/Splicore` |
| Version | **v0.3.0-rc.4** |
| Public tag commit | `2634ea50d19623591c5db63329a288862726db74` |
| Release | PINNED / Release Candidate / Experimental |
| Manifest | `runtime/splicore-release.json` |
| Latest / branch / unpublished build | NOT USED |
| Active rc.3 integration references | 0 |

Authority: [public rc.4 release](https://github.com/ike-sh/Splicore/releases/tag/v0.3.0-rc.4), its checksum assets and tagged source/docs. No local Splicore HEAD was queried. The executable reports the pinned version/commit, `dirty=false`, `linux/amd64`; its upstream build channel field is `development`, as shipped in the public archive. This does not substitute a local build. See [contract](../SPLICORE-RC4-CONTRACT.md) and [artifact evidence](SPLICORE_RC4_ARTIFACT_AUDIT.json).

## Architecture

```text
Clean NoBrand install
        ↓
Native desired state + new credentials/certificates
        ↓
Pinned artifact + private candidate validation
        ↓
One Splicore primary daemon
  ├─ Mieru
  ├─ Snell
  ├─ Hysteria2 + Salamander
  ├─ TUIC v5
  └─ VLESS + REALITY + Vision → native Local Tunnel Guard → fixed cover
```

NoBrand is the orchestrator/configuration layer. Splicore is the ordinary proxy core. State declares `architecture=splicore-native`, `splicore_version=v0.3.0-rc.4`, `config_schema=1`; product registry remains `schema_version=3`. Binary existence alone never establishes architecture identity.

Each committed generation owns its desired state, native DB, master key, control socket configuration and exact executable. The launcher supervises one active daemon. Private validation daemons are temporary; they do not constitute per-protocol production services. The standalone installer embeds runtime/launcher/manifest and works without the source tree.

Existing FinalMask/Sudoku retains its pinned Xray exception; SSH Tunnel and Forward remain separate existing features. No ordinary protocol uses their download paths. Individual Sudoku removal cleans its dedicated private Xray so that a later invocation cannot falsely classify the residual executable as legacy; native Splicore state is verified unchanged.

### Previous work classification

| Class | Retained / removed work | Reason |
|---|---|---|
| A — fresh install | Exact artifact/checksum/archive/identity gates, native builders, fresh TLS, Local Tunnel Guard, client profiles, ownership/ports, redaction, doctor, one service | Required for new installations |
| B — future native upgrade | Atomic generations/pointers, persistent journal, optimistic concurrency, private validation, binary/config/database/key rollback, native backup/restore, bounded retention | Required for Splicore → future reviewed Splicore |
| C — legacy migration only | Old config discovery/conversion; old UUID/PSK/REALITY key/Salamander/certificate/port preservation; legacy service snapshots/stops/restores; old ordinary downloaders; old multi-core rollback; compatible legacy upgrade dispatch; old quota/tc restore | Removed |
| D — tests/reports | Historical audits, old contract docs and retired legacy test files; current native replacements | Historical conclusions preserved; retired tests do not count as current PASS |

The retained common product/SSH/Forward lifecycle transactions are needed for those supported resources. They do not convert a legacy multi-core installation. Ingress Profile reassignment is a current network-policy transaction, not a legacy Core migration.

## Legacy Policy

| Gate | Result |
|---|---|
| Owned legacy detector | PASS |
| Third-party same-name binaries/services | Not claimed; PASS |
| Automatic conversion/migration | NO |
| Mutations after legacy detection | NONE |
| New installer used to uninstall/purge old installation | REFUSED |
| Old backups accepted | NO; native marker checked before extraction |

Owned evidence covers old Mita, Xray, sing-box, Hysteria, ordinary protocol state, service names and non-native registry/current markers. The Sudoku-owned Xray exception remains separate. Tests cover 13 evidence categories across 7 runtime operations, plus 8 actual Bash main entrypoints. They verify unchanged bytes, no artifact request and no service effects. Detection does not search PATH to claim third-party software.

The notice states `Legacy NoBrand multi-core installation detected.`, migration is unsupported, `No changes were made.`, and the clean-install sequence. The `LEGACY_SUPPORTED` repair/install path has been removed.

## Artifact

| Architecture | Public asset | SHA256 | Qualification |
|---|---|---|---|
| amd64 | `splicore-v0.3.0-rc.4-linux-amd64.tar.gz` | `9dd1941c817143d18ea1c892a5fc13266c1b209600576946504a9d3c98c62161` | Actual binary identity and loopback traffic PASS |
| arm64 | `splicore-v0.3.0-rc.4-linux-arm64.tar.gz` | `5b5e39bd8e6ef373ebc00e7e3a8a688ce09d0369dc2c4ecfab06ed535d948b64` | Archive/ELF/pinned binary digest PASS; BUILD ONLY, runtime NOT CERTIFIED |

`x86_64→amd64`, `aarch64→arm64`; missing architecture/asset rejects, without source builds or fallback. Both public archives passed exact SHA256SUMS + independent pin, member count/size/type/path/duplicate checks, ELF architecture and extracted binary digest checks. amd64 `version --json` was executed and checked. arm64 was not executed.

Artifact publication is atomic after validation. Corruption, wrong identity/version, unsupported architecture and unsafe entries are covered by unit tests. HTTPS mirror/proxy requests use the same validation. Extracted license files are inspected as allowed archive content; upstream terms remain applicable.

## REALITY

Native REALITY and Local Tunnel Guard: **PASS**. Old Xray defender field compatibility: **OUT OF SCOPE**.

Renderer uses the public raw TCP/Vision contract, a fresh UUID/X25519 keypair/short-id, `server_secret.private_key`, loopback native `local-inbound` tunnel, bounded TLS route-only sniffing and a fixed target. Canonical UUID v4 guard/rule IDs are required. Rules are scoped to this guard: exact approved SNI → direct, immediately followed by guard → reject. Sniffed SNI never replaces the configured destination.

Candidate validation creates a private temporary daemon, stops its client runtime, then validates/applies the native guard/rules and plans managed inbounds before production cutover. Health checks verify guard authority and routing.

### Probe matrix

Observed using the public rc.4 binary and new exported Mihomo configuration. Evidence: [42-check runtime result](SPLICORE_RC4_FRESH_RUNTIME_PROBE.json).

| Probe | Expected rc.4 contract | Observed behavior | Result |
|---|---|---|---|
| Valid REALITY + Vision | Authenticated proxy works | TCP echo through new exported profile | PASS |
| Wrong UUID | No authenticated proxy | Echo/proxy request fails | PASS |
| Wrong short-id | No authenticated proxy | Echo/proxy request fails | PASS |
| Wrong client SNI | No authenticated proxy | Echo/proxy request fails | PASS |
| Approved ordinary TLS | Allowed cover TLS to fixed target | Intended local TLS cover responds | PASS |
| Unapproved TLS SNI | Guard reject | No TLS cover response | PASS |
| HTTP | Non-TLS fail closed | Public and direct guard listeners close/reset | PASS |
| Random TCP | Non-TLS fail closed | Public and direct guard listeners close/reset | PASS |
| Malformed TLS | Bounded parser rejects | Public and direct guard listeners close/reset | PASS |
| Missing SNI | Unusable TLS authority rejects | Public and direct guard TLS fail | PASS |
| Arbitrary sniffed SNI | Cannot choose forwarding destination | Direct guard rejects unapproved SNI; native graph fixes destination | PASS |

Wrong REALITY credentials may follow the public cover behavior; “safe” means no authenticated proxy access, not that every invalid handshake must have identical TCP behavior. The cover whitelist applies to the guard only. Authenticated VLESS payload remains ordinary proxy traffic, including the local echo used in this test; this is **not** full old defender/private-IP firewall equivalence.

## Vision

Core support: public rc.4 supports VLESS raw TCP + REALITY + `xtls-rprx-vision` (also flow none). NoBrand fresh default: Vision. New-profile traffic/restart/recovery: **PASS**. Unsupported HTTP transport + Vision combinations reject before cutover; no historical migration blocker is applied to fresh REALITY.

## HY2

| Gate | Result |
|---|---|
| Native Hysteria v2 | PASS |
| Fresh private CA + non-CA server leaf | PASS |
| SAN / validity / BasicConstraints / KU / serverAuth / key match / chain | PASS through OpenSSL checks, generated certificate inspection and public native validator |
| New client traffic | TCP + UDP PASS |
| Salamander | PASS; independent fresh auth and obfs secrets |
| Wrong auth / obfs / certificate pin | Rejected; PASS |
| Failed fresh install | Native rollback and new TLS cleanup PASS; HY2 retry and TUIC cleanup covered |
| Legacy certificate preservation | OUT OF SCOPE |
| Gecko | Core SUPPORTED / EXPERIMENTAL; NoBrand NOT EXPOSED |
| UDP hopping | Core SUPPORTED; NoBrand NOT EXPOSED, off by default |
| Linux nftables server range | PENDING external host qualification; NOT RUN |

Default TLS uses a fresh P-256 private CA and 825-day non-CA leaf with critical `CA:FALSE`, digitalSignature, serverAuth and matching SAN. Chain order is leaf then CA; key and directory are private. CA signing key is discarded. Self-signed/private-CA mode is supported; explicitly supplied native TLS files must pass the same checks. No ACME management is claimed.

## Fresh Client Profiles

| Protocol | New-profile qualification |
|---|---|
| REALITY + Vision | TCP PASS initially, after restart and SIGKILL recovery |
| HY2 + Salamander | TCP/UDP PASS initially, after restart and SIGKILL recovery |
| TUIC v5 | TCP/UDP PASS initially, after restart and SIGKILL recovery |
| Snell v5 server | TCP/UDP PASS with public rc.4 v4 client wire projection, in all three phases |
| Mieru | TCP PASS in all three phases; UDP/BOTH renderer/unit contract only |

Mihomo v1.19.30 gzip is digest pinned: `cf06ce2c7d1421bdbda14ee4a5b6046672dc35ebf8eecd8e77504ec3c0ed9a84`. UDP probes use 64 and 512 byte payloads. sing-box export is structurally checked, not newly traffic-qualified here.

HY2/TUIC sing-box profiles include the CA and hostname verification with `insecure=false`. Mihomo profiles use explicit leaf SHA256 pin and `skip-cert-verify=false`; a wrong HY2 pin fails actual traffic. HY2 URI has `insecure=1&pinSHA256=...` for private trust with a mandatory pin. Clients that ignore the pin are unsupported; use the full exported profile. This URI encoding is not a blanket verification bypass.

Snell exports distinguish server version 5 from client wire version 4 according to the tagged implementation. QUIC Proxy Mode is unsupported and no enable menu is offered. Legacy client-profile compatibility: OUT OF SCOPE. Explicit client export is sensitive; status/doctor/plan are redacted.

## Single Core

- Primary Splicore processes: **1**.
- Managed ordinary inbounds: **5** (one of each current protocol in the real campaign).
- Additional native Local Tunnel Guard listeners: **1**, within the same daemon.
- Legacy ordinary runtime processes/downloads: **0**.
- Mieru BOTH is represented by a pair of native inbounds in the same daemon, not a second Core.

## Download Audit

| Artifact | Observed ordinary install requests |
|---|---|
| Splicore rc.4 amd64 archive | YES, exact pinned release |
| rc.4 SHA256SUMS | YES |
| Xray ordinary runtime | NO |
| sing-box | NO |
| Legacy Hysteria | NO |
| Standalone Mita/Mieru | NO |
| Old Snell | NO |
| Unexpected | NONE |

The campaign transports cached public release bytes through the real download boundary and records the two requested release URLs. Artifact checksum/archive/binary/identity validation still executes. It does not claim a fresh network availability test. Ordinary legacy downloaders were removed; specialized Sudoku/Forward paths remain explicit exceptions.

## Service

`nobrand-splicore` is the single ordinary service. No ordinary legacy service is generated. systemd and OpenRC templates are unit tested, including a single supervisor. Actual lifecycle qualification here uses a **local process supervisor** in temporary loopback directories.

Restart: PASS for all five profiles. SIGKILL recovery: PASS for all five profiles. Launcher rejects live/foreign/locked entries before cleanup. Native systemd/OpenRC host acceptance remains PENDING.

## Upgrade Model

| Direction / operation | Result |
|---|---|
| Legacy → Splicore | NOT SUPPORTED IN PLACE |
| Native Splicore → reviewed future manifest | Framework SUPPORTED; no unreviewed future version allowed |
| Same version/config | VERIFY / NO-OP; no restart, real binary campaign PASS |
| Binary identity / rollback | PASS in controlled artifact and generation tests |
| Config rollback | PASS in units and real candidate failure; REALITY/HY2 traffic restored |
| DB / master key rollback and backup | PASS in units |
| Crash journal recovery / concurrent change rejection | PASS in units |

No rc.5 asset or future wire compatibility is certified. The current manifest contains only the current public rc.4 release and no old rc.2 rollback pin. Future releases require review/update of the manifest and qualification. Rollback restores a prior native generation; it never restarts a legacy Core.

## Uninstall

Native uninstall/purge: PASS (units + public binary campaign), idempotent and ownership bounded. Legacy installation: REFUSED / NOT MUTATED. Generic product uninstall retains the SSH administrator-confirmation boundary and existing Sudoku/Forward ownership rules. It is not an old-install cleanup tool.

## Doctor

Splicore-native doctor verifies artifact identity, service/listeners, DB state, certificates and native guard/rules without rewriting generations. Unit/native health checks: PASS. Legacy doctor entry: refusal only; PASS. Status includes native architecture/Core/version and no ordinary legacy Core state or credentials.

## Tests

| Gate | Final result |
|---|---|
| Current Bash acceptance entrypoints | **28 / 28 PASS** |
| Native transaction Python tests | **27 / 27 PASS**, no skips |
| Fresh-policy Python tests | **10 / 10 PASS**, no skips |
| Public rc.4 runtime/security checks | **42 / 42 PASS**, separate local campaign |
| Bash syntax | **111 shell files PASS** |
| ShellCheck | PASS for source model, both installers, scripts and all test files |
| Build consistency | PASS; both standalone installers byte-identical and current |
| Function orphan / duplicate / accidental override audit | 0 / 0 / 0 |
| Candidate public-tree sanitization | PASS; no real secret/binary/bundle/infrastructure matches |
| Historical report hashes | 16 / 16 unchanged |

The complete default suite finished with exit code 0. Structured counts and qualified-code hashes:
[test summary](SPLICORE_RC4_TEST_SUMMARY.json). Its optional real Sudoku Xray validator was not run;
this remains outside the rc.4 campaign. The default runner skips its optional runtime stage, while
the separate recorded public rc.4 campaign passed all 42 checks.

Current scope and the exact list of 28 active / 35 retired Bash files: [test contract](../SPLICORE-RC4-TEST-CONTRACT.md). Historical legacy tests are not represented as passing current acceptance. No arbitrary target count is retained.

Reproduce current local checks with `bash scripts/test.sh`. The real binary campaign is separately reproducible through `scripts/test.sh --runtime` with the two documented public-asset/reference-client paths. Raw process logs and generated credentials remain private and ignored; only sanitized results are included here.

## Security

| Audit | Result |
|---|---|
| Real private keys / credential bundles / runtime archives in candidate public tree | NONE detected by sanitization gate |
| REALITY private key in client output or redacted plan | NONE; tested |
| State/doctor/plan/error summaries | Redacted; no actual credentials in public evidence |
| Artifact checksum/archive/identity | PASS |
| TLS verification | ENABLED; explicit private trust/pin |
| Native backup | 0600, contains private material; not a public attachment |
| Guard arbitrary SNI/open proxy fallback | Not observed; negative probes PASS |
| Full old defender/private-IP policy | Not claimed |

Synthetic credentials appear only in tests. This report and its JSON evidence contain status, public hashes, public URLs and counts, without runtime credentials, private keys, exported profiles or private logs.

## Qualification Limits

| Area | Qualification |
|---|---|
| Linux amd64 | Temporary loopback + local supervisor runtime PASS; public rc.4 remains experimental |
| Native systemd | PENDING actual host acceptance |
| OpenRC | PENDING actual host acceptance |
| arm64 runtime | BUILD ONLY / NOT CERTIFIED; artifact static checks only |
| nftables port-range hopping | PENDING / NOT RUN; default off |
| Existing optional SSH/Forward/Sudoku | Current isolated unit/transaction coverage; no new real-host traffic claim |
| Other client versions / exports | Only the stated Mihomo reference profiles traffic-qualified |

These are external qualification limits allowed by the maintainer decision, not a claim of production certification.

## Production Safety

Production hosts, real customer nodes and real legacy migrations: UNTOUCHED. No SSH access requested. Development-machine init units and network policy were not modified; service discovery tests use an isolated system root. Public archives/tagged source were cached privately; no local Splicore source HEAD was inspected.

## Docker / Redis / TeleLedger

UNTOUCHED / NOT QUERIED.

## Git

- Stage: NONE.
- Commit: NONE; HEAD unchanged.
- Push: NONE.
- Tag: NONE.
- Release: NONE.
- Freeze: NO.
- Index: EMPTY.
- Working tree: changes retained unstaged for maintainer review, including the pre-existing development changes.

Final `git status --short`, `git diff --check`, `git diff --stat`, `git diff --name-status`, index and HEAD audits: PASS. The tracked diff spans 59 files; untracked native runtime, reports and tests are also left unstaged. Generated installer changes account for much of the diff volume.

## Final Result

**SPLICORE RC.4 FRESH ARCHITECTURE READY FOR REVIEW**

## Blockers

None for the fresh architecture implementation/review gate. External host qualification limits remain exactly as listed above.
