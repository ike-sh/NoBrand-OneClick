# NoBrand-OneClick Splicore rc.3 Migration Closure Report

Date: 2026-10-18, Asia/Shanghai. Worktree review candidate; no new freeze.

## Final Result

**SPLICORE MIGRATION BLOCKERS REMAIN**

Salamander is implemented and locally interoperable with unchanged old NoBrand
profiles when the existing TLS material meets the public Core contract.
REALITY policy parity and the old HY2 default TLS contract remain OPEN.
No incompatible certificate, credential, flow or obfuscation setting is replaced
to claim closure. The earlier [BLOCKED freeze](SPLICORE_SINGLE_CORE_FREEZE_REPORT.md),
[rc.2 migration report](SPLICORE_RC2_MIGRATION_REPORT.md) and
[rc.2 closure attempt](SPLICORE_RC2_BLOCKER_CLOSURE_REPORT.md) remain historical evidence.

## Splicore

| Field | Result |
|---|---|
| Pinned | **v0.3.0-rc.3** |
| Repository | [ike-sh/Splicore](https://github.com/ike-sh/Splicore/releases/tag/v0.3.0-rc.3) |
| Release commit | `72166d2fcda95b943cbae584bdd59876df7d0ed8` |
| Annotated tag object | `c4e5f215d9e573f6fbe7e6de929f676cfc4f3658` |
| Latest / main / local build | NOT USED |
| Pin source | `runtime/splicore-release.json`; embedded identically in both installers |
| Previous rc.2 | Approved historical upgrade/rollback fixture only |
| Qualification | Release Candidate / Experimental |

The public tagged source archive was inspected read-only. No local Splicore
checkout was built or modified. Fresh install/update/config paths use rc.3.

## Artifact

| Artifact | SHA256 |
|---|---|
| `splicore-v0.3.0-rc.3-linux-amd64.tar.gz` | `7617de6a08e6e32c47bf084ee485cdff4875f64c25ea9ad281659f03bae3b6af` |
| amd64 executable | `737d5b2b22daafd36940c12192185922b53711e0dc24946327be4119304f1a61` |
| `splicore-v0.3.0-rc.3-linux-arm64.tar.gz` | `eed96ff31b22f130ff46fbe9fc5ad2186bcd7c7fed3e61f2c96c26a658076ef9` |
| arm64 executable | `f5d487f628babf39e0d70edec0dde47b1427100cd5d5ed07240013e91eb38363` |
| `SHA256SUMS` asset | `f946129688a9623b794840c04416d5175922826cc2251783f8d7cbb77807cb24` |

Both downloaded archives match the official checksum asset, recorded immutable
pin and GitHub release-asset digest. Production archive inspection verifies
member paths/types/layout and ELF architecture; extracted executable hashes
match the pin. The actual amd64 executable reports product Splicore, version
v0.3.0-rc.3, full release commit, linux/amd64 and `dirty=false`. Its build tags
include `with_quic`, `with_utls`, `with_gvisor`; its reported channel is
`development`, not silently relabeled stable. arm64 was inspected, not executed.

| Negative gate | Result |
|---|---|
| Corrupted/truncated archive | REJECTED before extraction/execution |
| Wrong-version executable | REJECTED by exact identity |
| Actual rc.2 executable when rc.3 expected | REJECTED |
| Unsupported architecture | FAIL CLOSED |
| Replaced generation executable | REJECTED; regression fixture |

## rc.3 HY2 Capabilities

| Feature | Core | NoBrand |
|---|---|---|
| Salamander | SUPPORTED | Implemented for fresh install and compatible legacy TLS |
| Gecko | SUPPORTED / EXPERIMENTAL | NOT EXPOSED |
| UDP Port Hopping | SUPPORTED | NOT EXPOSED |
| Linux server port range | SUPPORTED BY CORE | NOT EXPOSED; real nftables/CAP_NET_ADMIN qualification PENDING |

Public binary validation covers Gecko, invalid Gecko size, single-port client
intent, fixed interval/range, mixed ports with randomized intervals, conflicting
interval rejection, and a server range. Server ranges are **never applied** in
this campaign. No nftables command or real host firewall change is used. Plain
HY2 remains distinct and passes its own traffic/restart/upgrade checks. These
unexposed new features were absent from old NoBrand and are not freeze blockers.
Native intervals/Gecko sizes are not invented as URI parameters.
See [the current contract](../SPLICORE-RC3-CONTRACT.md).

## REALITY

### Actual legacy fields and disposition

The existing generator has a public raw TCP REALITY/Vision inbound and a
loopback dokodemo-door defender. REALITY's target is that defender. Defender
sniffing routes only the exact configured SNI to the camouflage destination;
other defender requests deny. Global rules deny private IPs, TCP ports
`25,135,137,138,139,445,465,587`, and BitTorrent before the public direct rule.
These are observable server policy, not disposable internal process details.

| Legacy field / behavior | Classification | rc.3 disposition |
|---|---|---|
| `listen_host`, `listen_port` | PRESERVE | Native listener uses same address/port in isolated control |
| advertise mode/host/port, ingress metadata | MAP | Effective display endpoint independent of listener/SNI |
| UUID | PRESERVE | Same `users[].uuid`; no regeneration |
| private key file / server privateKey | PRESERVE | Same X25519 bytes in `server_secret.private_key`; server only |
| public key | PRESERVE | Same `settings.reality.public_key` and old client key |
| short ID | PRESERVE | Same bytes in `short_ids`; no rotation |
| server name | PRESERVE | Same REALITY SNI and old client SNI |
| raw TCP + security REALITY | MAP | Native `transport=tcp`, `security=reality` |
| `xtls-rprx-vision` | MAP | Public Core supports it; unchanged old profile passes native Vision control |
| fingerprint, spiderX, client encryption=none | PRESERVE | Existing old profile retained verbatim |
| `decryption=none` | MAP | Native VLESS framing; no security change |
| `show=false`, `xver=0`, `minClientVer=0.0.0` | MAP | Fixed no-PROXY/no-minimum defaults only; nondefault versions not admitted |
| target_host/port and actual loopback defender target | UNSUPPORTED | A single native target does not preserve both defender dispatch and routing |
| defender enabled/protocol/listen/port/tag/dispatch_host/target_mode | UNSUPPORTED | No equivalent native server mapping; no sidecar retained |
| defender TLS sniffing, exact SNI forward, catch-all deny | UNSUPPORTED | Native target alone cannot establish equivalent behavior |
| public inbound sniffing, private-IP / dangerous-port / BitTorrent deny | UNSUPPORTED | No mapped native server policy for these authenticated target dials |
| schema/ownership/ID/name/enabled/timestamps/runtime/camouflage/recommendation | PRESERVE | Business metadata retained on rejected legacy state; successful product mapping not claimed |
| absence of server PEM TLS material | PRESERVE | Not present in actual legacy REALITY mode; none introduced |

No defender field is classified NO LONGER REQUIRED on the basis of architecture
alone. No equivalent behavior test exists for retiring the old policy.

### Evidence

At the exact public commit, `internal/splicore/engine/native/vless.go` obtains
`underlay.ServerTarget` at line 58. Authenticated TCP targets call
`h.protected.DialContext` at line 317; UDP targets do the same at line 331.
That file is byte-identical to the inspected rc.2 release. The Core's client
route graph does not establish an equivalent server-inbound defender policy.

The unchanged old NoBrand Mihomo Vision profile reaches the loopback echo
service through a native rc.3 Vision control. This is positive wire compatibility
and a concrete **security parity failure** against the legacy `geoip:private`
deny rule. It is not successful migration. No Vision-to-none downgrade is used.
The native control and unchanged profile also pass after normal restart and
SIGKILL/relaunch. Public validation rejects malformed key/short ID/UUID,
unsupported transport and unknown defender/routing fields.

NoBrand migration and fresh REALITY requests reject before download/cutover.
Whole-graph fixtures preserve existing files/modes and active/enabled services.
A successful migrated REALITY rollback is NOT CLAIMED: no policy-equivalent
candidate exists. Fresh REALITY download trace is empty; no ordinary Xray
fallback occurs.

**Result: OPEN — REALITY_SECURITY_POLICY_MAPPING.**

## Salamander

| Legacy field | Mapping / result |
|---|---|
| actual old runtime | Pinned Xray HY2 inbound with FinalMask UDP Salamander; not standalone Hysteria |
| auth | PRESERVE → `users[].password`; independent of obfs secret |
| Salamander enabled | PRESERVE → `settings.stream_transport.kind=hysteria`, version 2, `obfs.type=salamander` |
| obfs password | PRESERVE → `stream_transport.hysteria.obfs.password` |
| listener host/port | PRESERVE; old service and new service use the same UDP port |
| certificate/key | PRESERVE existing file paths, bytes and modes; no migration renewal |
| SNI | PRESERVE → `settings.tls.server_name` |
| h3 / version 2 | MAP to fixed native HY2 defaults |
| client insecure, ALPN, auth, obfs, SNI, endpoint | PRESERVE in unchanged old profile and new exporters |
| display endpoint / ingress / lifecycle fields | MAP effective endpoint; retain old metadata and enabled state |
| unknown old config/state fields | REJECT before mutation; never silently drop |

### Real process and rollback evidence

The fixture calls the actual old NoBrand state/config/client generators and
starts the verified public Xray v26.3.27 server with its generated HY2 config.
The Xray archive SHA256 is
`23cd9af937744d97776ee35ecad4972cf4b2109d1e0fe6be9930467608f7c8ae`;
its executable SHA256 is
`8255dd939c34cf966cc91517b6324dd3c8d0bcf49ffac8beca049a38c46845ed`.
It is an old-server/rollback fixture, never a fresh NoBrand download route.

The same old Mihomo profile, without changing server/port/password/SNI/obfs or
TLS policy, carries TCP payload, domain destination and 64/512-byte UDP echoes
before migration, after migration, after injected candidate failure/rollback,
and after explicit rollback from the committed rc.3 generation. Only its local
client listening port and surrounding test routing are assigned by the harness.
Official Mihomo v1.19.30 gzip SHA256 is
`cf06ce2c7d1421bdbda14ee4a5b6046672dc35ebf8eecd8e77504ec3c0ed9a84`.

The production adapter renders the candidate; the actual public rc.3 executable
validates bootstrap and inbound intent, then plans/applies it. A fixture
supervisor controls only the temporary real subprocesses; transaction state,
backup, artifact checks, validation, commit and rollback use production code.
Bad auth, wrong/missing obfs, and an untrusted-TLS client fail with no payload;
the correct profile continues working. Invalid TLS and duplicate listeners
reject before cutover. Native `port_conflict` rejection leaves the live graph
and traffic intact. A failure injected after real candidate apply restores the
actual old Xray process and client traffic, not only a mocked active flag.

Fresh HY2 creates valid new TLS and independent auth/obfs secrets and downloads
only the exact rc.3 archive and checksum asset. Failed fresh candidates remove
new TLS only after completed rollback and when no live/previous generation
references it, permitting retry; unfinished recovery retains required material.

### Remaining TLS contract blocker

The actual old default `openssl req -new -x509 ... /CN=...` emits a CA leaf
without the SAN required by native Go TLS verification. Public rc.3
`internal/splicore/tlsconfig/material.go` verifies hostname/chain and explicitly
rejects `leaf.IsCA`. NoBrand preflight rejects the unchanged default fixture. Public structural
`inbound validate` accepts its file references; actual material admission rejects
it at plan/apply. The latter must not be inferred from structural validation alone. A compatible test fixture has its valid non-CA
leaf/CA bundle **before the old server starts**; migration never replaces it.

The conservative mapper derives exactly one existing CA from that bundle.
Missing/ambiguous trust anchors, custom server fields, unsafe permissions or
incompatible certificates fail before stopping the old service. Arbitrary
external PKI layouts are not claimed qualified.

The old Xray baseline produced a 1200-byte UDP echo integrity mismatch in WSL.
The recorded compatibility campaign therefore qualifies **64 and 512 bytes**;
larger UDP datagrams remain unqualified. This is not reported as a successful
large-packet test or a newly proven rc.3 regression.

**Result: Salamander mapping/runtime/rollback implemented for compatible TLS;
overall legacy HY2 closure remains OPEN — LEGACY_HY2_TLS_CONTRACT.**

## Single Core

One public rc.3 process simultaneously owns raw REALITY Vision, Salamander HY2,
plain HY2, Snell v5, Mieru TCP and TUIC v5. All six listeners and native health
identities are checked; Vision/Salamander/plain, Mieru TCP and TUIC traffic is checked initially,
after normal restart and after SIGKILL/database/socket recovery. The native
REALITY control bypasses the product policy gate explicitly and is never
persisted as an accepted NoBrand migration graph. This demonstrates Core
coexistence, not full NoBrand protocol migration closure.

Ordinary production legacy-core downloads: **NONE**. Fresh HY2 uses rc.3 only;
fresh REALITY rejects before download. Specialized FinalMask/Sudoku's existing
pinned external Xray boundary and SSH/Forward utilities remain documented.

## Upgrade

Actual public rc.2 → actual public rc.3: config, listener ports, credentials and
master key preserved. The representative graph includes Snell, Mieru, plain HY2
and TUIC. Public candidate validation precedes service stop. An invalid
rc.3 MTU candidate rejects while rc.2 continues carrying traffic. Injected post-apply
failure returns to the actual rc.2 process, verified by identity, health and
unchanged plain-HY2 client traffic. Successful upgrade and explicit rollback to
rc.2 also pass. Same rc.3 + same intent returns verify/no-op with unchanged
current pointer. The manifest explicitly approves rc.2 as rollback history;
normal download/version selection never resolves it.

## Tests

Current runtime evidence: [rc.3 probe](SPLICORE_RC3_RUNTIME_PROBE.json) and
[production process-adapter probe](SPLICORE_RC3_LOCAL_INTEGRATION.json).
**50/50 default Bash entries PASS**; final Python checks **50 PASS**
(4 safety + 32 runtime + 14 migration). **108/108** Bash syntax checks PASS;
ShellCheck **0.9.0 PASS**. Runtime probe reproduces **53 observations**, including
the expected REALITY parity failure. Final sanitization, generated installer
consistency, report links and Git whitespace checks PASS. Nine opt-in host runtime
entries and the standalone reference runtime remain unexecuted. See the
[test summary](SPLICORE_RC3_TEST_SUMMARY.json) and
[reproduction commands](SPLICORE_SINGLE_CORE_MIGRATION_REPORT.md).

## Qualification Limits

| Environment / capability | Result |
|---|---|
| Native Linux systemd | PENDING |
| Native OpenRC | PENDING / N/A |
| Real legacy host migration | PENDING |
| Real old production clients | PENDING |
| Linux arm64 runtime | NOT CERTIFIED; archive/build identity checked only |
| Real nftables/CAP_NET_ADMIN server port range | PENDING; no host table changes |
| Larger HY2 UDP payloads in this WSL path | NOT QUALIFIED |

No production server was requested or accessed. These external host gates are
separate from the two implementation/contract blockers above.

## Git

Branch `main`; HEAD `f98cf70e7159c07826101676a4a08394f0a203f9` unchanged.
Stage **NONE**; Commit **NONE**; Push **NONE**; Tag **NONE**; Release **NONE**.
Index **EMPTY**. Existing migration work and this continuation remain uncommitted.

## Remaining Blockers

1. **REALITY_SECURITY_POLICY_MAPPING:** public rc.3 does not provide a demonstrated
   equivalent for the actual old defender/SNI and authenticated-target deny rules.
2. **LEGACY_HY2_TLS_CONTRACT:** the unchanged default old CA leaf is rejected by
   public rc.3; migration must not regenerate TLS to claim preservation.

**SPLICORE MIGRATION BLOCKERS REMAIN. READY FOR FREEZE REVIEW is not asserted.**
