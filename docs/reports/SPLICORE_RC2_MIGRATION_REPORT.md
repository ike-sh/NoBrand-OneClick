# NoBrand-OneClick Splicore Single-Core Migration Report

Date: 2026-10-17, Asia/Shanghai.

Freeze audit update: the full formal-protocol coverage gate is **BLOCKED**.
The completion statement below applies only to the expressible subset.
Ordinary REALITY and existing HY2 Salamander are not migrated; safe rejection
does not establish full coverage. See the [freeze report](SPLICORE_SINGLE_CORE_FREEZE_REPORT.md).

Blocker closure attempt, 2026-10-18: **SPLICORE MIGRATION BLOCKERS REMAIN**.
Native REALITY flow-none traffic works, but violates the old private-IP policy;
public HY2 still rejects Salamander. Existing profiles are not migrated. Public
rc.2 actually accepts Vision; NoBrand Vision migration remains rejected in this
scope. See the [field mappings and binary evidence](SPLICORE_SINGLE_CORE_BLOCKER_CLOSURE_REPORT.md).
No new freeze or commit was performed.

Continuation verification, 2026-10-18: exact public release source and asset
digests were independently rechecked, and the amd64 blocker probe reproduced
all 30 recorded observations. Both blockers remain OPEN; no additional migration
renderer was enabled. See the closure report's continuation verification.

## Result and qualification

**IMPLEMENTATION COMPLETE / LOCAL VALIDATION PASS / EXTERNAL RUNTIME QUALIFICATION PENDING**

Implementation and local validation are complete for the expressible public
rc.2 configuration subset. This is an uncommitted review candidate, not a
release. Native host and real-client qualification remains pending separately.

No production host was accessed. No native systemd/OpenRC unit was installed.
No old-client wire test is claimed. Contract-incompatible legacy nodes reject
before cutover; they are not reported as successfully migrated.

## Baseline and target

| Field | Value |
|---|---|
| Branch | main |
| HEAD | f98cf70e7159c07826101676a4a08394f0a203f9 |
| NoBrand version | 3.2.6 / v3.2.6; unchanged |
| Initial worktree | clean; no unrelated changes |
| Remote | https://github.com/ike-sh/NoBrand-OneClick.git; main matched at preflight |
| Primary core | Splicore v0.3.0-rc.2, ike-sh/Splicore |
| Public release commit | 926f3274fd44ac618cc276951eefe2d27134f687 |
| Annotated tag object | 9913c1043b87b5f56c2c0d98e38366fd7ad98584 |
| Pin authority | runtime/splicore-release.json, embedded by scripts/build.sh |
| Splicore latest / local build used | NO / NO |
| Qualification | Release Candidate / Experimental; arm64 BUILD ONLY |

Read-only preflight included status, branch, HEAD, log graph, remotes, sorted
tags, and remote main/tag inspection. No applicable AGENTS.md was found.
The detailed original repository/indirect-call inventory is preserved in the
[pre-implementation audit](SPLICORE_PRE_MIGRATION_AUDIT.md).

## Previous core inventory

Defaults: LIB=/usr/local/lib/nobrand-oneclick, STATE=/var/lib/nobrand-oneclick,
CONFIG=/etc/nobrand-oneclick. Existing root overrides remain supported.

| Core | Version/download | Protocols | Service | Renderer and lifecycle |
|---|---|---|---|---|
| Official Mita | enfein/mieru tagged deb/rpm/tar; stable metadata, explicit pin, known-good 3.36.0 | Mieru TCP/UDP/BOTH | nobrand-mieru@ID / nobrand-mieru-ID | write_instance_config; do_install/do_upgrade; preservation ledger uninstall |
| Surge snell-server | Surge release page; dl.nssurge.com per v4/v5 archive | Snell v4/v5 | nobrand-snell@ID / nobrand-snell-ID | snell_generate_server_config; per-major candidate upgrade/rollback |
| Xray 26.3.27 | XTLS/Xray-core tagged zip and pinned hashes | HY2, REALITY, FinalMask/Sudoku | nobrand-hysteria2, nobrand-vless-reality@ID, nobrand-vless-sudoku; OpenRC equivalents | protocol renderers; shared Xray upgrade; final-consumer uninstall |
| sing-box 1.13.20 | SagerNet/sing-box tagged archive; latest previously opt-in | TUIC v5 | nobrand-tuic@ID / nobrand-tuic-ID | tuic_generate_server_config; candidate upgrade/restore |
| Realm 2.9.6 | zhboner/realm tagged musl archive | Port Forward utility | nobrand-realm | existing forward renderer/transaction; retained |
| System OpenSSH | OS package, externally owned | SSH Tunnel | existing sshd | owned policy/account/key transaction; retained |

NaiveProxy, standalone mKCP and XHTTP installers are absent. No new protocols
or specialized modes were added.

## Protocol migration matrix

Machine-readable capability authority: `runtime/splicore-release.json`;
`nobrand runtime capabilities` exposes the same record. Field-by-field mapping
and public source evidence: [rc.2 contract](../SPLICORE-RC2-CONTRACT.md).

| Protocol/mode | Target and implementation | Compatibility gate |
|---|---|---|
| Snell v4/v5 | native managed document; PSK/port/version preserved; Surge/Mihomo/sing-box client fields | reject QUIC and PSKs outside rc.2 domain; v5 compatibility adapter old-client traffic pending |
| Mieru TCP/UDP | native document per legacy user/listener; credentials, MTU/mux/handshake exports preserved | traffic off, Low Entropy off, no quota/expiry/rate; no metadata-only enforcement downgrade |
| Mieru BOTH | two linked inbounds in the one daemon; TCP:P + UDP:P+1, paired mutations | same identity/password; pair rollback fixture PASS; old-client wire pending |
| TUIC v5 | native document, preserved UUID/password/cubic/native/zeroRTT, user mutation; Mihomo/sing-box output | prevalidate existing CA/SAN/non-CA leaf/key; current legacy-generated CA leaf rejects unchanged |
| Existing HY2 | whole migration rejects before stopping services | Salamander/obfs password cannot be expressed; no silent plain-HY2 conversion |
| Plain canonical HY2 | native document; tested in four-protocol public-binary graph | not exposed as a replacement for existing obfuscated HY2 |
| VLESS REALITY/Vision | fail closed; no new key or generic Xray fallback | defender/routing/SNI security parity unavailable |
| VLESS FinalMask/Sudoku | retained external pinned Xray | explicit requires_external_xray; Splicore does not own Xray |
| SSH/Forward | existing OpenSSH/nftables/Realm | separate owners; primary port reservations include retained listeners |

Capability restrictions are enforced unsupported configurations. They are not
environmental failures, and are not passed migration acceptance. A host with
one incompatible node remains entirely on its existing deployment.

### Protocol traffic qualification matrix

Local listener checks below are configuration/process evidence only. Every
applicable real-client TCP/UDP, IPv4/IPv6, domain and existing-profile traffic
gate remains **PENDING**; none was exercised by opening a healthy inbound.

| Protocol | Previous core | Public rc.2 local evidence | TCP/UDP traffic | IPv4/IPv6/domain traffic | Existing client profile |
|---|---|---|---|---|---|
| Snell v4/v5 | snell-server | IPv4 TCP inbound healthy; credential/config fixtures | PENDING where applicable | PENDING | PENDING |
| Mieru | Mita | IPv4 TCP inbound healthy; TCP/UDP/BOTH mapping fixtures | PENDING | PENDING | PENDING |
| TUIC v5 | sing-box | IPv4 UDP inbound healthy with valid CA/leaf | PENDING where applicable | PENDING | PENDING |
| Plain canonical HY2 | no equivalent legacy plain profile | IPv4 UDP inbound healthy with valid CA/leaf | PENDING where applicable | PENDING | PENDING |
| Existing obfuscated HY2 | Xray | rejected before cutover; no equivalent obfs | NOT RUN; migration rejected | NOT RUN; migration rejected | NOT RUN; migration rejected |
| Existing REALITY/Vision | Xray | rejected before cutover; security parity unavailable | NOT RUN; migration rejected | NOT RUN; migration rejected | NOT RUN; migration rejected |

Specialized FinalMask/Sudoku remains external Xray and is outside Splicore wire
qualification. No existing unsupported profile is replaced with a weaker one.

## Artifact manager

| Check | Result |
|---|---|
| amd64 archive | splicore-v0.3.0-rc.2-linux-amd64.tar.gz |
| amd64 archive SHA256 | bc438dba6d43f016f1f23473495b9af49abb95153bb62ac4d809e85cd472922e |
| amd64 binary SHA256 | 37522b6fe56fe88e1e6e16eed69dd2bf2b3e45a0df628d6cff8fe81ede22e7d1 |
| arm64 archive | splicore-v0.3.0-rc.2-linux-arm64.tar.gz |
| arm64 archive SHA256 | ff79beb51588d9539498976ee2b0697e3243e89dc74e467874a6a143bce5890f |
| arm64 binary SHA256 | 2ffc5445c0ca7274871626b8fef284ff8ebe85e59e273276f533fb11a21753da |
| Official SHA256SUMS | both exact entries verified against immutable pins |
| Architectures | x86_64/amd64 → amd64; aarch64/arm64 → arm64; others fail ARCH_UNSUPPORTED |
| Download | one HTTPS curl adapter; fixed tag URLs; optional HTTPS prefix proxy; TLS redirects only |
| Archive | allowlisted observed files; no absolute/traversal/link/device/duplicate/unexpected entry; size/count limits |
| Binary | ELF architecture and pinned binary digest checked before execution; exact product/version/commit/clean/platform identity |
| Atomicity | private temporary download/staging; fsync files and directories; immutable generation then atomic current pointer |
| Previous good | retained until validated cutover; current/previous plus one recovery reference; bounded pruning |
| Missing/corrupt/partial artifact | reject; no live service mutation |

The public amd64 ELF is static. Its actual channel string is `development`.
The arm64 archive and ELF were inspected, not executed: **BUILD ONLY**.

## Runtime architecture and files

`runtime/splicore.py` is the single standard-library adapter. `src/19-splicore.sh`
bridges existing CLI/menu requests. The build embeds adapter, launcher, and pin
into both standalone installers. No companion source download is required.

```text
STATE/splicore/
  generations/g<uuid>/
    splicore, artifact.json, desired.json, bootstrap.yaml, launch.py
    runtime/state.db, runtime/master.key
    documents/, resource-map.json, daemon.lock
  current -> generations/g...
  previous -> generations/g...
  legacy-migration.tar.gz
LIFECYCLE/splicore-transaction.json
LIFECYCLE/splicore-migration.json
CONFIG/splicore/tls/<node>/    # newly created TUIC certificate/CA/leaf only
```

Existing certificate locations are retained. NoBrand canonical `desired.json`
is authoritative; native SQLite is written only through the public CLI/API.
No direct SQL operations. New binary placement inside each immutable state
generation keeps executable/config/database/pointer rollback together; it is a
documented change from historical LIB/bin runtime placement.

One `nobrand-splicore.service` or OpenRC `nobrand-splicore` owns all ordinary
inbounds. Per-protocol add/remove/enable/disable/reconfigure builds a complete
generation because rc.2 lacks inbound removal. This **restarts the shared
daemon and interrupts all current connections briefly**. It does not emulate
unsupported native DELETE/start/stop APIs.

The service uses root to retain access to existing private root-owned TLS
material and privileged listener ports. systemd retains restart supervision,
NOFILE, private umask, NoNewPrivileges, PrivateTmp, read-only system/home and a
limited writable runtime directory. OpenRC uses supervise-daemon. This is not
an unprivileged service claim.

`launch.py` obtains an inherited process lock, checks a residual Unix entry is
an owned socket, refuses a live socket or unknown errors, and unlinks only a
same-inode ECONNREFUSED stale socket. It then execs Splicore, leaving one core
process. This fixed an observed rc.2 SIGKILL restart failure. It introduces no
additional supervisor or watchdog.

## Migration, rollback, and lifecycle

Discover → redacted plan → artifact/config candidate → offline validate →
private legacy snapshot → journal → stop conflicts → atomically select/start →
apply public plans → inbound/listener health → enable primary/disable legacy →
commit orchestration state. External traffic qualification remains pending.

- Discovery reads actual legacy state. Current ports and credentials remain
  unchanged. Automatic display endpoints reuse existing NoBrand resolution.
- TLS/unknown-field/capability/desired-port/external-owner failures precede any
  stop; stale legacy state and concurrent generation changes reject.
- A shared lifecycle flock protects Bash/Python. Descriptor 7 is reused inside
  menu transactions. Recovery does not overwrite unfinished historical work.
- Snapshot includes owned state/config/lib files, relevant Mita configs and
  service definitions, plus enabled/active set; no log/cache tree. One migration
  archive is retained, with a 512 MiB pre-cutover limit and private permissions.
- Candidate startup or health failure restores pointer/unit/registry and exact
  prior service states. New firewall bindings are rolled back. Unchanged legacy
  files are never deleted or replaced by migration.
- First committed migration can return to legacy without a previous Splicore
  generation. Saved files must still match snapshot hashes; changed external
  files require review before old services are started.
- Later changes use the same deploy/verify/rollback framework and cached pinned
  binary. Same-version/same-configuration is verify/no-op.
- Reviewed future pins retain previous identities in the central manifest's
  rollback_releases map. Synthetic pin-change upgrade/rollback is fixture
  evidence of the framework, not qualification of another release.
- Mieru systemd scan/tc scheduler is stopped/disabled, or owned OpenRC cron is
  saved/removed; rollback restores its prior state.
- Retired firewall/generation cleanup failures become explicit cleanup debt;
  they do not undo a committed healthy daemon.

Legacy binaries/configs are intentionally retained pending real traffic
qualification. No claim of post-traffic legacy binary deletion is made.

## CLI, menu, status, backup, uninstall

Primary protocol mutations route before legacy repair/download paths. Menu
selectors read current canonical nodes and reject stale selection hashes.
Ordinary install does not call standalone Mita, Snell, sing-box or Xray
downloaders. Status/doctor do not resolve latest versions, rotate credentials,
rewrite the resource map, or repair missing legacy cores.

Mieru supported settings use explicit flags; unsupported quota/rate/advanced
operations reject instead of calling old helpers. Ingress modify/delete/apply
reject while primary is present rather than rebuilding legacy runtimes;
explicit canonical transactions express primary listener changes. Network
utility management remains separate.

Unified backup stops primary for a consistent SQLite/master.key pair, includes
state/config and bounded generations, serializes only owned current/previous
pointers, omits sockets/backups. Existing product restore checks archives and
rolls back its own state/config transaction; snapshot adoption revalidates
binary pins before execution and rebuilds owned pointers/launcher/bootstrap/unit.
Separate runtime restore replays desired state using verified artifacts and the
saved master.key. External legacy references are not reactivated by that restore.
Certificate files outside a standalone runtime archive require a unified backup.

Runtime uninstall stops/disables primary and removes its unit/current pointer;
configuration/previous generations remain. Purge removes only owned Splicore
state and newly created TLS directory. Complete product uninstall retains the
existing Mita preservation ledger, specialized Xray and SSH confirmation rules.
Repeated uninstall/purge and preservation of other state pass fixture tests.

## Local validation evidence

| Validation | Result and scope |
|---|---|
| 32 runtime unittest cases | PASS: transaction, first migration rollback/retry, bounded generations, paired Mieru, credentials/settings, product restore rollback, backup/key, concurrency, archive/checksum, launcher and reviewed pin-change fixtures |
| 4 contract safety unittest cases | PASS: architecture mapping, safe archive inspection, exact checksum entries and corrupt/partial download rejection |
| Standalone distribution and primary routing | PASS: installer copied without src; embedded capabilities work; ordinary routes intercepted before legacy download/repair helpers |
| Public contract audit helper | checksum/archive/identity positive and negative probes; recorded contract evidence retained |
| Public amd64 adapter integration | PASS: actual verified release; four healthy native loopback inbounds in one daemon |
| Local process restart | PASS: persisted graph restored after orderly restart |
| Local process SIGKILL/database recovery | PASS: owned stale socket cleanup and graph restoration |
| Download trace | exactly pinned amd64 archive and SHA256SUMS; HTTP transport replaced by public artifact cache fixture |
| Process cleanup | temporary daemon stopped, current pointer removed, temporary directory removed |
| Full default suite | PASS: `bash scripts/test.sh` exited 0; all 49 Bash test files, including the 32 runtime and 4 contract safety cases above |
| Syntax, ShellCheck and distribution build | PASS: `bash -n`, ShellCheck at warning severity, and `scripts/build.sh --check`; generated installers are current and identical |
| Architecture/reference and sanitization audits | PASS: orphan/duplicate/accidental override counts 0; real secret, credential bundle, runtime binary and private infrastructure leak counts 0 |
| Native runtime harness | not invoked; no Docker/production test |

Evidence: [local adapter result](SPLICORE_LOCAL_INTEGRATION.json),
[public contract result](SPLICORE_RC2_CONTRACT_PROBE.json).
Local transport substitution is explicitly labelled; it is not a claim of a
native host install or old-client wire traffic.

An earlier full run caught omitted README bootstrap and manager-only wording.
The documentation was restored with the existing assertions retained; the
focused localization test and then the entire default suite passed. The final
local log is `.lab/splicore-rc2-audit/final-tests-verified.log` (ignored local
evidence). Lifecycle recovery exercised 4 install, 10 repair and 9 uninstall
interruption checkpoints, plus signal and concurrent-lock recovery.

## Static and download audit

Remaining references are classified in
[reference audit](SPLICORE_REFERENCE_AUDIT.md). Historical restore/recovery paths
remain deliberately executable; ordinary new primary paths are intercepted.
This is a compatibility boundary, not deletion of all old source.

Expected primary core URLs:

```text
https://github.com/ike-sh/Splicore/releases/download/v0.3.0-rc.2/splicore-v0.3.0-rc.2-linux-amd64.tar.gz
https://github.com/ike-sh/Splicore/releases/download/v0.3.0-rc.2/SHA256SUMS
```

arm64 selects its exact recorded filename. No Splicore latest/branch URL,
generic Xray fallback, remote installer, or unverified mirror authority.

## External runtime qualification pending

These are external platform qualification limits, **not implementation
blockers**, as directed by the maintainer:

- Real Linux amd64 systemd install qualification.
- Real Linux amd64 OpenRC qualification (already supported by NoBrand).
- Real legacy multi-core → Splicore host migration.
- Real client → migrated Splicore traffic and existing profile compatibility.
- Real service crash/restart qualification on a native Linux host.

arm64 remains BUILD ONLY and additionally needs real runtime qualification.
No unexecuted test above is PASS; the old client's wire options remain intact
without claiming they have been qualified.

### Requested acceptance mapping

| Gate | Local evidence / external status |
|---|---|
| A Fresh amd64 install | artifact/config/transaction/service fixture PASS; native install pending |
| B Multi-protocol single runtime | actual public binary, four native inbounds in one daemon PASS |
| C Critical protocol traffic | real client traffic PENDING; inbound health is not traffic |
| D Existing profile compatibility | credential/parameter preservation fixtures PASS; old-client wire PENDING |
| E Legacy multi-core migration | discovery/pair mapping/cutover fixtures PASS; real host migration PENDING |
| F Failed migration rollback | startup/health/interruption and old enabled/active restoration fixtures PASS; real traffic restoration PENDING |
| G Core update framework | verify/no-op and synthetic reviewed-pin upgrade/rollback fixtures PASS |
| H/I Uninstall/purge | repeated owned-namespace fixtures PASS; native host qualification PENDING |
| J Doctor | identity/graph/legacy-active detection and read-only resource map checks; native host PENDING |
| K/L Restart/crash recovery | actual private process restart/SIGKILL database recovery PASS; native supervisor PENDING |
| M/N Checksum/unsupported architecture | negative gates PASS, live state unchanged |
| O Repeated install/update | no-op/one service/artifact reuse fixtures PASS |
| P No unwanted core download | resolver trace and primary CLI/menu route fixtures PASS |
| Q No old active residue | isolated one-daemon process and fixture legacy retirement PASS; real migrated host audit PENDING |

## Boundaries and git

| Operation | Result |
|---|---|
| D:\\code\\Splicore modified / needed at runtime | NO / NO |
| Docker queried / restarted / modified | NO / NO / NO |
| Redis / TeleLedger / production modified | NO / NO / NO |
| Stage | NONE |
| Commit | NONE |
| Push | NONE |
| Tag | NONE |
| Release | NONE |

## Implementation blockers

None identified in the implemented expressible subset after local validation.
The full formal-protocol freeze has the coverage blockers recorded in the
freeze report. External platform and real-client qualifications remain PENDING.
Unsupported public rc.2 configurations continue to fail closed before cutover.
