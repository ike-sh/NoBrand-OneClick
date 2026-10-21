# NoBrand-OneClick Splicore Migration Blocker Closure Report

Date: 2026-10-18, Asia/Shanghai.

## Final Result

**SPLICORE MIGRATION BLOCKERS REMAIN**

This is a blocker closure attempt, not another freeze. Both migration blockers
remain OPEN under the fixed public v0.3.0-rc.2 contract. Expected rejection,
native control traffic and unchanged legacy files do not establish successful
migration. The [BLOCKED freeze attempt](SPLICORE_SINGLE_CORE_FREEZE_REPORT.md)
is retained as history. No freeze, staging or commit was performed.

## Baseline

| Field | Observed value |
|---|---|
| HEAD / main | f98cf70e7159c07826101676a4a08394f0a203f9; unchanged |
| Branch | main |
| Index | EMPTY |
| Worktree | existing single-core migration and blocked freeze records; no unrelated changes found |
| Functional baseline | all 125 files in the prior freeze SHA256 snapshot matched before this attempt |
| Target | public ike-sh/Splicore v0.3.0-rc.2, commit 926f3274fd44ac618cc276951eefe2d27134f687 |
| amd64 archive SHA256 | bc438dba6d43f016f1f23473495b9af49abb95153bb62ac4d809e85cd472922e |
| amd64 binary SHA256 | 37522b6fe56fe88e1e6e16eed69dd2bf2b3e45a0df628d6cff8fe81ede22e7d1 |

Preflight ran status, branch, HEAD, log graph, diff whitespace and index checks.
No reset, clean, restore, stash, rebase or history change occurred.

The earlier closure attempt changed five existing functional files: the adapter's specific
rejection diagnostics, its central capability manifest, the default test list
and the two generated installers. Three new test/probe files and the current
reports provide the additional evidence. No new migration renderer was enabled.

### Continuation verification, 2026-10-18

The continuation independently fetched six files from the exact public release
commit: VLESS documentation, Hysteria transport documentation, HY2 settings,
Hysteria transport settings, the native VLESS server and its underlay dialer.
All six match the cached release source byte for byte. Fresh GitHub release API
asset digests match both pinned/cached architecture archives and the cached
official `SHA256SUMS`. No local Splicore checkout or unpublished build was used.
The historical 125-file freeze snapshot differs only in the five existing
functional paths recorded above, with no missing paths.

The public amd64 blocker probe was rerun. All 30 observations match the existing
[sanitized evidence](SPLICORE_BLOCKER_CLOSURE_PROBE.json), including actual
flow-none REALITY/plain-HY2 payload, unchanged-old-profile incompatibility,
private-target policy failure, restart/relaunch, negative validation and cleanup.
`migration_blockers_closed` remains **false**. This continuation changes reports
only; neither a positive Salamander migration nor a REALITY policy mapping has
become available. The complete default-suite replay is recorded in Tests below.

Private replay evidence remains ignored under `.lab/splicore-rc2-audit/`:
`continuation-public-authority.json`, `continuation-blocker-probe.json`,
`continuation-tests.log` and `continuation-source-hashes.json`.

## Original Freeze Blockers

| Mode | Original result | Closure result |
|---|---|---|
| VLESS + REALITY | BLOCKED | OPEN: existing security policy is not mapped; existing profiles require Vision |
| HY2 + Salamander | BLOCKED | OPEN: no native Salamander contract in public rc.2 |

## Current implementation and public authority

Actual NoBrand sources: [REALITY](../../src/59-vless-reality.sh),
[HY2](../../src/57-hysteria2.sh), [primary dispatcher](../../src/19-splicore.sh),
[adapter](../../runtime/splicore.py), [manifest](../../runtime/splicore-release.json).
CLI/menu mutations enter the primary adapter before legacy installers. Discovery
represents both incompatible modes explicitly; render rejects the complete plan
before artifact acquisition or service changes. Existing legacy renderers remain
for detection, historical recovery and fixtures, not ordinary fresh installation.

Public sources were rechecked at the exact released commit:

- [VLESS contract](https://github.com/ike-sh/Splicore/blob/926f3274fd44ac618cc276951eefe2d27134f687/docs/protocol/VLESS.md),
  [settings](https://github.com/ike-sh/Splicore/blob/926f3274fd44ac618cc276951eefe2d27134f687/internal/splicore/protocol/vless/settings.go),
  [creation/key ownership](https://github.com/ike-sh/Splicore/blob/926f3274fd44ac618cc276951eefe2d27134f687/internal/splicore/protocol/vless/creation.go).
- [Native VLESS server](https://github.com/ike-sh/Splicore/blob/926f3274fd44ac618cc276951eefe2d27134f687/internal/splicore/engine/native/vless.go),
  [REALITY handshake](https://github.com/ike-sh/Splicore/blob/926f3274fd44ac618cc276951eefe2d27134f687/protocol/vless/backend/reality.go).
- [HY2 settings/metadata](https://github.com/ike-sh/Splicore/blob/926f3274fd44ac618cc276951eefe2d27134f687/internal/splicore/protocol/hysteria2/hysteria2.go),
  [Hysteria transport fields](https://github.com/ike-sh/Splicore/blob/926f3274fd44ac618cc276951eefe2d27134f687/internal/splicore/domain/streamtransport/hysteria.go).
- [Published Hysteria wrapper restrictions](https://github.com/ike-sh/Splicore/blob/926f3274fd44ac618cc276951eefe2d27134f687/docs/architecture/HYSTERIA_TRANSPORT.md#bounds-and-unsupported-wrappers)
  explicitly exclude Salamander; [FinalMask restrictions](https://github.com/ike-sh/Splicore/blob/926f3274fd44ac618cc276951eefe2d27134f687/docs/architecture/FINALMASK.md#compatibility-restrictions)
  exclude UDP masks. No alternative generic UDP-mask contract was found.

Contract correction: public rc.2 documents and accepts native Vision over raw
TLS/REALITY. Therefore, "Vision unsupported by current Splicore release" would
be inaccurate. NoBrand Vision migration remains REJECTED in this attempt as
requested; no Vision feature was enabled. A missing NoBrand adapter is not
evidence that the public binary lacks Vision.

The [NoBrand capability manifest](../../runtime/splicore-release.json) remains
the application authority: `vless-reality.managed=false`,
`hysteria2.managed=true` for canonical plain mode and `hysteria2.salamander=false`.
It includes the exact integration-blocker reasons used by plan/install errors.

| Profile | Public rc.2 native contract | NoBrand disposition |
|---|---|---|
| VLESS plain / TLS | supported by public VLESS contract | absent from current ordinary installer baseline; not added |
| VLESS REALITY flow-none | validated and payload-tested | migration still rejected for security parity |
| VLESS REALITY Vision | public contract accepts it | NoBrand migration rejected in this scope |
| HY2 plain | validated and payload-tested | canonical path remains distinct from old Salamander profiles |
| HY2 Salamander | absent; both representations reject | migration and ordinary install rejected |
| Existing FinalMask/Sudoku | existing specialized external Xray boundary | unchanged; outside this attempt |

## REALITY

### Legacy config discovered

`reality_generate_state` stores UUID, public key and `private_key_path`, not the
private key value. The private file and legacy server JSON both hold the server
private material. `reality_derive_public_key` uses the existing Xray x25519 helper.
The old generator and every existing client exporter fix flow to
`xtls-rprx-vision`; there is no ordinary flow-none install/profile path in this
NoBrand baseline. A real old profile cannot be relabelled as flow-none.

The server has a public VLESS inbound plus a loopback dokodemo-door defender.
REALITY's actual handshake target is `127.0.0.1:defender_port`. The defender
sniffs TLS SNI, admits the configured name and redirects to
`server_name:target_port`, blocking other defender traffic. Shared rules deny
private IPs, TCP ports 25/135/137/138/139/445/465/587 and BitTorrent. Public
authenticated traffic is separately sent to PUBLIC_DIRECT.

### Mapping

PRESERVE = identical semantic value; DERIVE = deterministic from existing
authority; NORMALIZE = representation only; UNSUPPORTED = no accepted equivalent
in this migration. This inventory is a proposed contract map, not an enabled
renderer or successful migration assertion. No field is silently dropped.

| Old NoBrand field | Public rc.2 field | Existing client field | Rule / disposition |
|---|---|---|---|
| listen_host / listen_port | listener.host / port | independent endpoint | PRESERVE |
| advertise_mode / host / port, ingress profile | display_endpoint plus retained NoBrand metadata | server / port | DERIVE effective display endpoint without changing listener |
| UUID | users[].uuid | id / uuid / URI authority | PRESERVE; no missing-value generation permitted during migration |
| private_key_path and server privateKey | server_secret.private_key | none | PRESERVE existing X25519 bytes, server only |
| public_key | settings.reality.public_key, checked against private key | password (Xray), public-key, pbk | DERIVE/check same existing X25519 public key; no rotation |
| short_id / shortIds | settings.reality.short_ids | shortId / short-id / sid | NORMALIZE hex case only; preserve bytes and nonempty old ID |
| server_name / serverNames[0] | settings.reality.server_name | serverName / servername / sni | PRESERVE |
| target_host / target_port | settings.reality.target supports an endpoint | none | UNSUPPORTED as a complete defender replacement; direct target rewrite loses policy |
| actual loopback REALITY target | settings.reality.target | none | UNSUPPORTED after defender retirement; leaving the old defender is not single-core migration |
| transport/network=tcp, security=reality | settings.transport / security | network=tcp, security=reality | PRESERVE |
| fixed xtls-rprx-vision flow | settings.flow | all old profiles explicitly use Vision | UNSUPPORTED in this NoBrand migration scope; reject, never convert to none |
| hypothetical explicit flow-none | settings.flow=none | separate flow-none profile | PRESERVE only as native control; old policy still lacks a mapping |
| fingerprint=chrome / spider_x=/ | client projection retained separately | fp / fingerprint / spiderX | PRESERVE; never server credentials |
| decryption=none | native VLESS framing | encryption=none in Xray profile | NORMALIZE profile representation; no change to security |
| show=false / xver=0 | no managed member | none | NORMALIZE native default behavior only; no nondefault values admitted |
| minClientVer=0.0.0 | no managed member; adding min_client_ver rejects | none | NORMALIZE no minimum restriction; nondefault values UNSUPPORTED |
| defender_enabled/protocol/listen/port/tag/dispatch_host/target_mode | no qualified server mapping | none | UNSUPPORTED; no sidecar retained |
| sniffing, SNI dispatch, private-IP, blocked ports, protocol routing | no qualified server-inbound rule mapping | none | UNSUPPORTED; security policy cannot be dropped |
| schema/ownership/instance/name/enable/timestamps/camouflage/recommendation/runtime version | separate NoBrand lifecycle metadata/resource map | label only where applicable | PRESERVE business metadata; runtime version records actual target |
| server certificate / key | none for REALITY | public REALITY key, not a PEM certificate | not present in this legacy mode; no certificate renewal |

### Evidence and result

| Gate | Actual result |
|---|---|
| Port, UUID, private key, public key, short ID, SNI preserved | PASS on rejected-plan fixtures; successful migration NOT EXECUTED |
| Public flow-none validation/listener/handshake/TCP application payload | PASS for explicit native control only |
| Unchanged legacy client profile to native flow-none | NO PAYLOAD, as expected; not compatible |
| Security parity | FAIL: a native authenticated REALITY control reaches a loopback HTTP destination denied by the old policy |
| Unknown defender/routing/minimum-client fields | REJECTED by the public binary; not silently ignored |
| Invalid private key/short ID/SNI/destination/UUID | REJECTED by public validation before any cutover |
| Missing private key with existing public key | REJECTED |
| Both keys omitted | public validation ACCEPTS fresh key generation; never an authorized migration mapping |
| Port conflict | typed port_conflict rejection at apply; existing native graph unchanged |
| Vision | NoBrand migration REJECTED; public binary ACCEPTS its contract; no downgrade |
| Rollback from migrated REALITY | NOT EXECUTED; no valid migrated candidate exists |
| NoBrand pre-cutover rejection | PASS; old files/modes, current primary pointer and service active/enabled states unchanged |
| Result | **OPEN — REALITY_SECURITY_POLICY_MAPPING** |

The policy conclusion combines source inspection with an actual private-target
counterexample. The released native server sends authenticated TCP and packet
destinations directly to its `ServerTarget` underlay dialer. The released
[dialer](https://github.com/ike-sh/Splicore/blob/926f3274fd44ac618cc276951eefe2d27134f687/internal/splicore/underlay/factory.go)
provides socket bypass protection, not the old inbound destination/SNI/protocol
policy. Client routing resources do not by themselves establish server inbound
enforcement. No outbound firewall or external defender was substituted.

## Hysteria2 Salamander

### Legacy config and mapping

The actual previous runtime is pinned Xray's `hysteria` inbound, not a standalone
Hysteria executable. The generator always writes UDP FinalMask Salamander.
`auth` and `obfs` are independently generated values; `obfs` in state is the
Salamander password, not an obfs enable flag or HY2 authentication password.
All existing exporters advertise Salamander. No legacy disabled toggle exists.

| Old NoBrand field | Public rc.2 field | Existing client field | Rule / disposition |
|---|---|---|---|
| listen_host / listen_port | listener.host / port | independent server/port | PRESERVE |
| auth / settings.clients[].auth | users[].password | password / URI authority | PRESERVE; never use obfs as auth |
| finalmask.udp[].type=salamander | absent in settings and Hysteria transport | obfs=salamander | UNSUPPORTED |
| state.obfs / finalmask password | absent | obfs.password / obfs-password | UNSUPPORTED; retain old secret, reject migration |
| TLS certificateFile/keyFile | settings.tls.certificate_file/private_key_file | trust metadata only | PRESERVE paths/content/modes; existing material must pass native TLS validation |
| state.sni | settings.tls.server_name | sni / server_name | PRESERVE |
| h3 ALPN, hysteriaSettings.version=2 | native HY2/Hysteria defaults | alpn=h3 | NORMALIZE fixed protocol defaults |
| insecure=1 / skip-cert-verify | retained client-only policy | insecure / skip-cert-verify | PRESERVE old profile; not permission to bypass server TLS checks |
| advertise mode/host/port, ingress | display_endpoint plus NoBrand metadata | server / server_port | DERIVE without renumbering listeners |
| transport=udp, enabled, tag, timestamps, version | native UDP plus NoBrand lifecycle metadata | label where applicable | PRESERVE semantics/ownership |
| bandwidth, masquerade, QUIC tuning, multi-user table | not emitted by current old generator | not emitted | no legacy field to map; none invented |

| Gate | Actual result |
|---|---|
| Auth, Salamander secret, port, TLS files | PASS unchanged on rejected-plan fixtures; successful migration NOT EXECUTED |
| Salamander enabled state | always enabled in actual legacy output; retained by rejection |
| Public Salamander validation | REJECTED at settings.obfs and stream_transport.hysteria.obfs |
| Plain HY2 | distinct native control validates and carries real TCP application payload |
| Unchanged old Salamander client to native plain HY2 | NO PAYLOAD, as expected; not compatible |
| Missing/wrong secret, bad obfs, TLS/auth errors | NoBrand rejects the unsupported mode before cutover; no fine-grained Salamander runtime acceptance claimed |
| Port conflict | typed port_conflict rejection at apply for plain control; graph unchanged |
| TLS default legacy certificate restriction | remains as previously documented; no certificate replaced to claim migration |
| Migrated Salamander runtime / UDP/domain traffic / rollback to old-client traffic | NOT EXECUTED: no valid rc.2 native Salamander candidate |
| Silent downgrade | NO; the explicitly simplified native control is never persisted as legacy or migration state |
| Result | **OPEN — SPLICORE_RC2_HY2_SALAMANDER** |

The public HY2 module explicitly declares no obfs and strictly decodes settings.
The transport's exact field allowlist also has no obfs. This is a
**SPLICORE RC.2 INTEGRATION BLOCKER**, not missing native-host qualification.

## Combined Runtime

One verified public Splicore process held five healthy inbounds: native REALITY
flow-none, plain HY2, Snell v5, Mieru TCP and TUIC v5. REALITY and plain HY2
carried actual application payload through the pinned existing Mihomo client.
The other three are listener/health evidence only in this campaign.

Normal restart and explicit local SIGKILL/relaunch restored payload for both
native controls and all five healthy resources. This uses NoBrand's existing
exec launcher, not native systemd/OpenRC or supervisor certification.
The requested combined REALITY + Salamander migrated graph **cannot be created**;
no combined migration PASS is asserted. Owned processes and temporary storage
were removed at the end.

## Download Audit

| Item | Observed result |
|---|---|
| Splicore | exact public archive, official SHA256SUMS entry and binary digest/identity verified before execution |
| Ordinary Xray / legacy Hysteria / unexpected proxy core | NONE downloaded or launched by fresh/rejected migration paths |
| Positive fresh install of these two old modes | NOT EXECUTED; both remain explicitly rejected |
| Test client | checksum-verified cached official Mihomo v1.19.30, same pin as existing REALITY runtime fixture |
| Local Splicore source build / unpublished HEAD / release upgrade | NONE |

## Service Audit

One direct private Splicore process; zero host unit/service changes. No ordinary
Xray REALITY or legacy HY2 runtime was started. Service fixture tests verify
that rejection preserves the prior active/enabled set and an existing primary.
Successful mode-specific cutover/rollback remains unimplemented, not PASS.

### Static reference classification

| Category | Retained references / evidence |
|---|---|
| LEGACY MIGRATION ONLY | legacy state/config/service detection, private snapshots, historical service/file restore; current discovery explicitly rejects both modes |
| TEST FIXTURE | original state/render/client helpers and dormant old install bodies exercised by legacy tests; new native control helper; no ordinary dispatch reaches the old install bodies |
| HISTORICAL DOC | old REALITY/HY2 scope, public contract audit, prior migration report and BLOCKED freeze facts; current closure status is linked |
| UNEXPECTED | 0 in the reviewed ordinary REALITY/HY2 primary download and service call graph |

Both main and menu dispatch call `nb_splicore_route_main` first; protocol module
dispatchers also return through `nb_splicore_protocol`. Old installer bodies
remain in the source for historical fixtures/recovery. A text search finding
their definitions is not a reachable fresh-install fallback. Generated installers
inherit the same call graph. The earlier full reference classification, including
the unchanged specialized Xray exception, remains in the
[reference audit](SPLICORE_REFERENCE_AUDIT.md).

## Tests

| Check | Result |
|---|---|
| New blocker regression tests | 7 PASS: actual legacy exporters/keys, all-or-nothing rejection, current primary preservation, flow rejection, obfs rejection, plain distinction, fresh zero-core-action rejection |
| Public binary control/negative/traffic campaign | completed; exact results in the sanitized evidence below |
| Full default suite | PASS: 50 default Bash test entries; exit 0 under local WSL root; NOBRAND_RUNTIME_INTEGRATION=0 |
| Existing Python cases inside default suite | 32 runtime unit tests and 4 contract safety tests PASS, no root-only case skipped |
| Syntax / ShellCheck / distribution | PASS: bash -n, ShellCheck warning severity and generated installer build check |
| Lifecycle recovery | PASS: 4 install, 10 repair and 9 uninstall checkpoints, signal recovery and repeated interruptions |
| Static classification / sanitization | PASS: reviewed ordinary-primary UNEXPECTED=0; all seven repository secret/binary/bundle/infrastructure leak counters are 0 |
| Local documentation links / whitespace | PASS: 0 broken local links; git diff --check and new-file trailing-whitespace check clean |

Root and distribution installers are identical, SHA256:
`3d0e94e5bace67c5bdcf3c2eedcf64e97d17972ebeb7f0b3397bdc60fb6c99fe`.

The repository has 60 `test_*.sh` files: 50 default entries, nine opt-in entries
under `scripts/test.sh --runtime`, and one standalone SOCKS5 UDP reference
control. The opt-in host suites and standalone reference control were not run in
this attempt. The separately invoked public-binary blocker probe above supplies
the stated local traffic evidence.

The continuation independently reran `bash scripts/test.sh` through local WSL
root with the same process-scoped Git ownership setting: exit **0**, all 50
default entries PASS. Bash syntax, installed ShellCheck at warning severity,
build consistency, the 32 + 4 + 7 Python cases, and all 4 install / 10 repair /
9 uninstall interruption checkpoints passed. No root-only unit case was skipped.
All 129 functional files in the continuation snapshot remain byte-identical;
the generated installers retain the digest above. The final documentation
sanitization, local-link and whitespace checks passed separately.

The new default test is [test_splicore_migration_blockers.sh](../../tests/test_splicore_migration_blockers.sh).
The native probe is opt-in, requires no new downloads, uses synthetic credentials
and loopback only, and never edits host networking or services:

```bash
python3 tests/helpers/splicore_blocker_probe.py \
  --artifacts /private/public-rc2-artifacts \
  --mihomo-gzip /private/mihomo-linux-amd64-v1.19.30.gz \
  --output /private/blocker-closure-probe.json
```

Sanitized public result: [blocker probe](SPLICORE_BLOCKER_CLOSURE_PROBE.json).
Private full-suite logs stay ignored under `.lab/splicore-rc2-audit/`.
The probe's zero exit status means its contract observations matched expected
outcomes; its `migration_blockers_closed` result is explicitly false.
Two initial invocations stopped at harness prerequisites: the non-root run failed
the existing root-ownership schema fixture and skipped one root-only restore case;
the first root run encountered Git's repository-ownership check. The final complete
run used local WSL root with process-scoped `GIT_CONFIG_COUNT=1`,
`GIT_CONFIG_KEY_0=safe.directory` and
`GIT_CONFIG_VALUE_0=/mnt/d/code/NoBrand-OneClick`. It exited 0, including the
previously skipped case. No assertion or acceptance criterion was weakened and
no global Git configuration was changed.

## Security

Credentials regenerated during migration: **NO**. Ports changed: **NO**.
Private keys in client output/report/result: **NO**. Subprocess diagnostics and
runtime logs stay in private temporary storage and are deleted. The report
contains field names and outcomes, not credentials or fingerprints of real keys.
No production access or credentials were requested. No Docker, Redis, TeleLedger
or `D:\code\Splicore` operation occurred. No sidecar, generic Xray fallback,
new protocol/menu redesign, certificate renewal or Splicore upgrade was added.

## External Qualification

| Scenario | Status |
|---|---|
| Native systemd | PENDING |
| Native OpenRC | PENDING; existing support only |
| Real legacy host | PENDING |
| Real old client deployment | PENDING; local synthetic compatibility counterexamples are separate |
| arm64 runtime | NOT CERTIFIED / BUILD ONLY |

## READY Decision

| Required gate | Current evidence / decision |
|---|---|
| REALITY migration mapping | NOT MET: defender/routing policy has no equivalent mapping |
| REALITY public rc.2 validation | native flow-none control PASS; full legacy mapping NOT AVAILABLE |
| REALITY unchanged old-client local fixture | NOT MET: existing profile uses Vision; no conversion to flow-none permitted |
| REALITY migration rollback | NOT EXECUTED: no valid migrated candidate; pre-cutover preservation PASS separately |
| HY2 Salamander mapping | UNSUPPORTED by fixed public rc.2 |
| Salamander public rc.2 validation | REJECTED in both settings and transport representations |
| Salamander unchanged old-client local fixture | NOT MET: old Salamander profile cannot connect to the plain control |
| Salamander migration rollback | NOT EXECUTED: no valid Salamander candidate |
| Fresh old-core downloads | 0 on rejected paths; successful fresh installation of these modes NOT EXECUTED |
| Single Splicore daemon | five native controls PASS; requested REALITY + Salamander graph NOT AVAILABLE |
| Full default tests | PASS; 50 entries, with scope stated above |
| No silent downgrade | PASS: unsupported plans reject without rewriting identity or wire settings |

The conjunctive closure gate is not satisfied. Passing safety regressions and
native controls does not change either migration blocker to CLOSED.

## Git

Stage = NONE; Commit = NONE; Push = NONE; Tag = NONE; Release = NONE.
Index = EMPTY. HEAD/main unchanged. Working tree remains uncommitted.

## Remaining Blockers

1. **REALITY_SECURITY_POLICY_MAPPING**: implement and qualify an equivalent
   native server security contract before enabling NoBrand REALITY migration.
   The native flow-none control currently violates the old private-IP denial.
   Existing NoBrand profiles also require Vision; this attempt does not authorize
   changing them to flow-none or enabling Vision migration.
2. **SPLICORE_RC2_HY2_SALAMANDER**: fixed public rc.2 lacks equivalent Salamander.
   No NoBrand field adapter can add an absent wire capability. Closing this
   requires an upstream published capability and a separately authorized target
   change; this attempt makes neither change.

**SPLICORE MIGRATION BLOCKERS REMAIN**. Not READY FOR FREEZE REVIEW.
