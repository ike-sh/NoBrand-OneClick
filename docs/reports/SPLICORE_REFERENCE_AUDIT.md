# Remaining core-reference audit

Scope: source, generated installers, runtime adapter, scripts/tests, README and
docs. Search: case-insensitive `sing[-_]?box|xray|mieru|mita|naive|snell-server`,
followed by download/repair/service call-site inspection. Generated installers
contain exact embedded copies of source; their occurrences are not independent
runtime owners. This audit classifies references, not only filenames.

## rc.3 continuation

Current pin is v0.3.0-rc.3. `rc.2` references are retained only as historical
reports, approved rollback metadata and explicit upgrade/rollback fixtures.
Generated installers include the same approved rollback metadata. Active Python
and Bash source contain zero rc.2 references. Current docs discuss rc.2 only
as history. No Splicore latest/main URL is used. The unrelated NoBrand manager
release URL and platform smoke-tool URL are outside Core artifact selection.
See [machine-readable audit](SPLICORE_RC3_STATIC_AUDIT.json).

Fresh HY2 resolves only rc.3. Fresh REALITY rejects its policy blocker with zero
core downloads. Existing Xray in the real HY2 probe is an explicitly verified
old-server/rollback fixture. The current single-core routes do not invoke old
Mita, ordinary Xray, standalone Hysteria or sing-box downloaders.

## Classification

| References / source | Classification | Current reason and call boundary |
|---|---|---|
| src/20-platform-mieru.sh runtime resolver/package/repair helpers | Legacy Migration | explicit historical restore and unfinished legacy transaction reconciliation; management-script helper no longer repairs/downloads Mita |
| src/22-platform-snell.sh, 24-platform-tuic.sh, 25-platform-vless-reality.sh | Legacy Migration | old pinned runtime/config/service recovery; ordinary protocol dispatch intercepted by src/19-splicore.sh |
| src/21-platform-xray-hy2.sh shared Xray downloader/validator | Specialized Xray; Legacy Migration | production specialized Sudoku owner; old HY2/REALITY recovery remains explicit; no primary fallback |
| src/23-platform-vless-sudoku.sh, 58-vless-sudoku.sh | Specialized Xray | existing FinalMask/Sudoku implementation, external pinned Xray; requires_external_xray recorded in central capability authority |
| src/30-users-instance.sh, 35-users-state.sh, 40-tc-quota.sh, 45-backup-user-actions.sh | Legacy Migration | schema-v3 legacy data, metrics, package preservation and rollback; primary routes do not use Mita instances |
| src/52-user-actions-ui.sh, 55-profile-config.sh, 65-service-bbr.sh, 80-lifecycle.sh, 85-status-actions.sh | Legacy Migration; Required Utility | historical UI/recovery/profile contracts; profile normalization, BBR/network utilities remain reusable; unsupported primary user/accounting commands reject |
| src/56-snell.sh, 57-hysteria2.sh, 59-tuic.sh, 59-vless-reality.sh old install/start/upgrade internals | Legacy Migration | public action wrapper intercepts ordinary actions; retained for restore/recovery and old fixture regression |
| src/70-client-export-install.sh, 71-snell-export.sh and client exporters within protocol modules | Required Utility; Legacy Migration | sing-box/Mihomo/Surge/Mieru client formats are not external server downloads; historical exports define compatibility reference |
| src/00-bootstrap.sh, 05-constants.sh, 10-cli-prelude.sh | Legacy Migration; Required Utility | backward-compatible variable/argument names and historical pins; runtime parser owns new primary commands |
| src/15-core-state.sh | Legacy Migration; Required Utility | schema/ownership checks, old lifecycle journal and shared flock; primary uses separate persistent generation record |
| src/16-core-port.sh, 16-core-ingress.sh, 17-core-endpoint.sh, 60-daemon-firewall-network.sh | Required Utility; Legacy Migration | existing port/firewall ownership API, transport normalization and ingress; primary state reserves ports; legacy primary reapply rejects |
| src/18-core-nodes.sh | Legacy Migration; Specialized Xray; Required Utility | primary status/doctor/backup/restore/uninstall branches plus historical reconstruction; specialized Xray and external SSH/Realm retained |
| src/19-splicore.sh, runtime/splicore.py and release manifest | Required Utility; Legacy Migration; Specialized Xray | native Mieru protocol name, client format labels, discovered legacy services, explicit capability gates; exactly one primary artifact resolver |
| src/50-diagnostics.sh, 61-ssh-tunnel.sh, 90-ui.sh, 99-main.sh | Required Utility; Legacy Migration | read-only network/status labels, current routing, preserved administrator safety and historical recovery; no automatic menu/main Mita repair |
| scripts/build.sh, shellcheck-src.sh, test.sh | Required Utility | source manifest, embedded adapter, static/test orchestration |
| scripts/docker-smoke.sh, platform-case.sh; old tests and fixtures | Legacy Migration | historical qualification/test infrastructure; native/Docker runtime harness not invoked this phase |
| tests/helpers/splicore*.py, test_splicore*.sh | Required Utility; Legacy Migration | synthetic test profiles, negative compatibility checks and production adapter fixture tests; no bundled core binaries |
| docs historical contracts/release notes/acceptance reports | Historical Documentation | old immutable behavior and provenance; current migration notices link to active scope |
| README, current migration docs/reports, THIRD_PARTY_NOTICES | Historical Documentation; Required Utility | explicit old/new mapping, unsupported configurations, client formats, release attribution and qualifications |
| install-nobrand.sh, dist/install-nobrand.sh | inherited categories above | generated byte-identical distribution, not extra source/runtime ownership |

**Unexpected runtime references: 0 in the reviewed ordinary-primary call graph.**
This does not mean zero old strings, zero old functions, or removal of historical
backup reconstruction. Those remain under the stated legacy boundary.

## Indirect-call checks

- Main routes ordinary install/upgrade/mutation before old repair paths.
- Protocol action wrappers and Mieru menu dispatcher use the same primary bridge.
- Primary Snell/TUIC menu selectors read canonical nodes and check selection hash.
- Opening main/Mieru menus no longer invokes Mita binary recovery.
- Unified primary restore adopts pinned generations; old archives deliberately
  retain their historical restore route rather than losing old state.
- Primary batch start/stop retains only specialized Xray and separate Forward
  utility actions; primary doctor detects a retired legacy service reactivated.
- Old `ingress modify/delete/apply` cannot reconstruct ordinary legacy cores
  while primary is installed.
- No generic Xray fallback and no Splicore-owned Xray. Existing specialized
  operations continue to use the project's pinned Xray owner.

## Download evidence

`runtime/splicore.py:artifact` is the sole ordinary-core resolver. The public
binary integration uses the real archive/checksum/ELF/binary/identity gates with
only HTTP transport replaced by an already verified public artifact cache.
[Recorded trace](SPLICORE_LOCAL_INTEGRATION.json) contains exactly:

1. pinned Splicore amd64 tar.gz;
2. the same release's SHA256SUMS.

No external sing-box, Mita, Naive, old Snell or ordinary Xray request occurs in
that trace. Direct/proxy URL composition and HTTPS constraints also have fixture
tests. This is local download-path evidence, not a native host installation.

Splicore latest URLs: **0**. Unknown primary core downloaders: **0**.
Other existing latest references belong to historical recovery, manager release
distribution, or optional Realm utility; they do not resolve primary Splicore.

## Service/process/artifact evidence

Public integration creates four simultaneous native loopback inbounds in one
Splicore process, restarts it, kills/restarts it, verifies the persisted graph,
then stops it and removes all temporary data. It launches no old core process.
The exact scope and cleanup fields are in the recorded JSON. Actual native
systemd/OpenRC service/process auditing remains external qualification pending.

Installed layout has one current binary selected by one owned pointer; previous
and a bounded recovery generation are rollback artifacts. Historical binaries
are retained dormant until real client traffic qualification, and their presence
must not be mistaken for an active ordinary runtime.
