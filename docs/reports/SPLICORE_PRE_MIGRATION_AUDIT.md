# Historical pre-implementation Splicore audit

Archived before the adapter was implemented. Statements about absent code below
describe that checkpoint. Current status: [migration report](SPLICORE_SINGLE_CORE_MIGRATION_REPORT.md).
The old fixture is superseded by `runtime/splicore-release.json`.

Date: 2026-10-17, Asia/Shanghai.

## Final Result

**SPLICORE SINGLE-CORE MIGRATION NOT READY**

The public pinned rc.2 contract cannot currently preserve all existing NoBrand
features and lifecycle operations under the requested constraints. Integration
stopped at the pre-cutover compatibility gate. No production runtime adapter,
service consolidation, legacy deletion or migration was applied. Existing
install/upgrade/restore paths still deploy the old runtimes. This report does not
represent them as a completed single-Core implementation.

Completed work: repository/source and indirect-call audit, public release/tag
contract audit, verification of both public artifacts, exact amd64 binary
identity, a reproducible isolated four-protocol daemon probe, concrete negative
compatibility/lifecycle/certificate probes, and targeted safety-helper tests.

## Baseline

| Field | Observed value |
|---|---|
| CURRENT_BRANCH | main |
| CURRENT_HEAD | f98cf70e7159c07826101676a4a08394f0a203f9 |
| CURRENT_VERSION | 3.2.6, local tag v3.2.6 |
| WORKTREE_STATE at start | Clean; `git status --short` empty |
| REMOTE_STATE | origin https://github.com/ike-sh/NoBrand-OneClick.git; cached origin/main and live remote main both match HEAD |
| Version authority | `src/00-bootstrap.sh`, generated root/dist installer |
| Source modules | 37 ordered Bash modules |
| User modifications encountered | None at baseline |

Read-only preflight ran status, branch, HEAD, graph/log -20, remotes, sorted tags
and remote main/tag lookup. No fetch, checkout, reset, clean, restore, stash,
staging, commit, push, tag or release was performed. No applicable AGENTS.md was
found at the workspace or parent paths checked.

### Repository location map

| Concern | Actual implementation |
|---|---|
| Installer/build | `install-nobrand.sh`, `dist/install-nobrand.sh`; ordered `scripts/build.sh` manifest |
| CLI/dispatcher/menu | `src/10-cli-prelude.sh`, `src/18-core-nodes.sh`, `src/99-main.sh`; `src/90-ui.sh`, Mieru user UI `src/52-user-actions-ui.sh` |
| Versions/paths | `src/00-bootstrap.sh`, `src/05-constants.sh` |
| Download/GitHub/architecture | `src/20-platform-mieru.sh`, `21-platform-xray-hy2.sh`, `22-platform-snell.sh`, `24-platform-tuic.sh`; Realm helpers in `src/62-forward.sh`; no unified GitHub proxy helper |
| Service abstraction/templates | `service_manager` in `src/20-platform-mieru.sh`, `nb_service_manager` in `src/17-core-endpoint.sh`; per-Core platform modules, `src/30-users-instance.sh` and `src/65-service-bbr.sh` |
| State/migration/recovery | `src/15-core-state.sh`, `src/30-users-instance.sh`, `src/35-users-state.sh`, `src/80-lifecycle.sh`; existing schema/legacy checks and persistent lifecycle journal |
| Protocol rendering | `src/55-profile-config.sh`, `src/56-snell.sh`, `src/57-hysteria2.sh`, `src/58-vless-sudoku.sh`, `src/59-tuic.sh`, `src/59-vless-reality.sh`; Mieru multi-user renderer in `src/35-users-state.sh` |
| Upgrade/rollback | Per-Core platform/protocol modules, `src/80-lifecycle.sh`, unified restore in `src/18-core-nodes.sh` |
| Backup/uninstall | `src/18-core-nodes.sh`, `src/45-backup-user-actions.sh`, `src/80-lifecycle.sh`; no separate current `purge` CLI/action found |
| Status/doctor/log views | `src/18-core-nodes.sh`, `src/50-diagnostics.sh`, `src/85-status-actions.sh`, protocol-specific status/doctor and journal/OpenRC log helpers |
| Ports/Ingress/firewall | `src/16-core-port.sh`, `src/16-core-ingress.sh`, `src/17-core-endpoint.sh`, `src/60-daemon-firewall-network.sh` |
| Quota/timers/network utilities | `src/40-tc-quota.sh`, `src/25-network-mtu.sh`, `src/61-ssh-tunnel.sh`, `src/62-forward.sh`, `src/65-service-bbr.sh` |
| Client export | `src/70-client-export-install.sh`, `src/71-snell-export.sh`, protocol-specific exporters |
| Tests/docs/CI | `tests/`, `scripts/test.sh`, `scripts/shellcheck-src.sh`, platform/runtime smoke scripts; README, `docs/`, `.github/workflows/ci.yml` (read only) |

## Target

| Field | Value |
|---|---|
| Primary Core target | Splicore |
| Pinned Version | v0.3.0-rc.2 |
| Repository | ike-sh/Splicore |
| Release Pin | PASS for public audit artifact selection; installer integration not implemented |
| Latest Used for Splicore | NO |
| Qualification | Release Candidate / Experimental |
| arm64 | BUILD ONLY; runtime not qualified |

Public source: [exact release](https://github.com/ike-sh/Splicore/releases/tag/v0.3.0-rc.2).
The [contract audit](../SPLICORE-RC2-CONTRACT.md) provides source links, field
mapping, constraints and reproduction. The machine readable audit pin is
[`runtime/splicore-release.json`](../../runtime/splicore-release.json) (supersedes the original audit fixture).
It is not wired into the active installer.

## Previous Core Inventory

Paths below are actual default constants, not guessed layouts. `LIB` means
`/usr/local/lib/nobrand-oneclick`; `STATE` means `/var/lib/nobrand-oneclick`;
`CONFIG` means `/etc/nobrand-oneclick`. They are NoBrand-owned namespaces, with
additional ownership guards for system packages and shared Mita resources.

| Core | Version Source | Download Path | Protocols | Service | Config Renderer | Upgrade | Uninstall |
|---|---|---|---|---|---|---|---|
| Official Mita | `mieru_resolve_runtime`: stable/latest resolves official stable metadata; pinned explicit; known-good 3.36.0 fallback/checksums | enfein/mieru tagged release; deb `mita_VERSION_ARCH.deb`, rpm `mita-VERSION-1.{x86_64,aarch64}.rpm`, Alpine `mita_VERSION_linux_ARCH.tar.gz`; package `/usr/bin/mita` copied to `LIB/bin/mita` | Mieru TCP/UDP/BOTH, isolated user instances | `nobrand-mieru@ID.service`; OpenRC `nobrand-mieru-ID`; daemon runs as mita:mita | `write_server_config_multi`, `write_instance_config`; golden `write_server_config` | `do_upgrade`, package snapshot/restore/version verification | `do_uninstall`, `remove_mita_common`; preservation ledger protects preexisting package/user/group/shared resources |
| Surge snell-server | Release markdown `SNELL_RELEASE_PAGE`; resolve v4/v5 separately | dl.nssurge.com/snell/snell-server-vVERSION-linux-ARCH.zip → `LIB/bin/snell/snell-v4` or `snell-v5` | Snell v4/v5; v5 optional same-port UDP ownership | `nobrand-snell@ID.service`; OpenRC `nobrand-snell-ID`; runner `LIB/snell-run` | `snell_generate_server_config` | `snell_upgrade_runtime`, per-major runtime and active-set rollback | `remove_snell_instance`, owned service/config/runtime cleanup |
| Xray-core | `TESTED_XRAY_VERSION=26.3.27`; tag API and pinned hashes | XTLS/Xray-core v26.3.27 `Xray-linux-64.zip` / `Xray-linux-arm64-v8a.zip` → `LIB/bin/xray`; geo assets `LIB/xray-assets` | HY2, VLESS REALITY+Vision, VLESS FinalMask/Sudoku | `nobrand-hysteria2.service`; `nobrand-vless-reality@ID.service`; `nobrand-vless-sudoku.service`; matching OpenRC services | `hysteria2_generate_config`, `reality_generate_server_config`, `vless_sudoku_generate_server_config` | Shared `nobrand_upgrade_xray_runtime`, validate existing configs, restart prior active set, restore snapshots on failure | Per-protocol remove; remove shared runtime only after last consumer; full `nobrand_uninstall_impl` |
| Official sing-box | `TESTED_SING_BOX_SERVER_VERSION=1.13.20`; stable tested pin; latest opt-in; pinned explicit | SagerNet/sing-box tagged release, `sing-box-VERSION-linux-ARCH[-musl].tar.gz` → `LIB/bin/sing-box`, metadata `STATE/tuic/runtime.json` | TUIC v5 | `nobrand-tuic@ID.service`; OpenRC `nobrand-tuic-ID` | `tuic_generate_server_config` | `tuic_upgrade_runtime`, candidate config validation, runtime/meta/state/active-set rollback | `remove_tuic_instance`, final consumer cleanup |
| Realm (network utility) | `TESTED_REALM_VERSION=2.9.6`; stable tested pin / explicit latest/pinned | zhboner/realm tagged musl archive → `LIB/bin/realm` | General port-forward feature TCP/UDP/BOTH | `nobrand-realm.service` / OpenRC `nobrand-realm` | `forward_generate_realm_config` | `forward_realm_install_runtime` through Forward transaction | `forward_uninstall`; owned nft/sysctl/firewall cleanup |
| System OpenSSH | Existing system/package; NoBrand does not own sshd binary or host keys | No proxy-Core download | SSH Tunnel TCP -L/-D/-R | Existing external sshd | NoBrand owned policy block/drop-in and per-user key/account files | Existing SSH policy transaction/watchdog/administrator-confirmation model | `ssh_tunnel_uninstall`, owner-checked account/key/policy cleanup, external daemon retained |

The current external sing-box binary is a TUIC server runtime. Its mentions in
client exports and tests are separate client-format/reference uses. Xray also
generates/derives REALITY X25519 keys and UUIDs, and consumes geoip/geosite data
for the current REALITY filtering policy. These utility dependencies must be
replaced or deliberately mapped when removing ordinary Xray runtime use.

No standalone Naive runtime/installer was found. No standalone mKCP, XHTTP or
ordinary VLESS transport installer was found outside the actual modes above.

### Indirect download and service paths

| Entry point | Indirect runtime dependency |
|---|---|
| Main Mieru install/upgrade | `src/80-lifecycle.sh` → resolver → download_package → install_package → managed Mita copy → isolated instances |
| Mieru repair/start/restart/profile/tuning/client operations | `repair_mita_binary_paths` → package recovery → `reinstall_mita_package` → tagged Mita download if missing |
| Mieru menu/main installed-state repair | `src/90-ui.sh` / `src/99-main.sh` can invoke the same repair branch |
| Snell install/upgrade | `src/56-snell.sh` → `snell_install_runtime` → candidate downloader |
| HY2 install/upgrade | `src/57-hysteria2.sh` → shared Xray install/upgrade |
| REALITY install/restore/upgrade | `src/59-vless-reality.sh` → shared Xray; keypair utility; service template |
| Sudoku install/upgrade | `src/58-vless-sudoku.sh` → shared Xray, specialized retained consumer |
| TUIC install/upgrade/restore | `src/59-tuic.sh` → install/candidate download; missing runtime restore forces state-recorded pinned version |
| Unified backup restore | `nobrand_restore_protocol_runtimes` → Mita repair, Snell v4/v5 install, shared Xray, REALITY/TUIC/Realm restore |
| Recovery and enabled-service restart | `src/80-lifecycle.sh` scope reconcile and `nobrand_start_enabled_services`; may reconstruct runtimes/templates, not merely start services |
| Unified stop/uninstall | `nobrand_stop_all_services`, `nobrand_uninstall_impl`, protocol removes and Mita preservation ledger |

Deleting only protocol download call sites would leave these indirect paths.
No such deletion has been made.

## Current Protocol Inventory and Migration Matrix

| Protocol / mode | Previous Core | Generator / state | Ports and credentials | Dependencies / special behavior | Target status |
|---|---|---|---|---|---|
| Mieru TCP / UDP / BOTH | Mita | `write_instance_config`; `STATE/mieru/users.json`, install-state.env; `/etc/mita/instances/ID/server.json` | Dedicated per-user P; BOTH TCP:P + UDP:P+1; username/password | MTU, mux, handshake, seeded traffic pattern, Low Entropy, expiry, quota/reset, per-user metrics bind mount, tc filters, exports | BLOCKED: advanced profile/quota/lifecycle; BOTH needs explicit pair mapping |
| Snell v4 | Surge Snell v4 | `snell_generate_server_config`; `STATE/snell/instances/ID.json`, `CONFIG/snell/instances/ID.conf` | TCP:P; PSK | Named instance, Display/Ingress, ipv6=false in old server config, official wire clients | Baseline rc.2 document accepted; PSK domain and lifecycle prevent general migration |
| Snell v5 | Surge Snell v5 | Same named-instance model | TCP:P, optional managed UDP:P; PSK | QUIC ownership state; existing version=5 client output; rc.2 v5 uses compatibility adapter | BLOCKED when QUIC/PSK incompatible; client traffic still unqualified |
| Hysteria2 | Xray | `hysteria2_generate_config`; `STATE/hysteria2/state.json`, `CONFIG/hysteria2/config.json` | UDP:P; auth password, Salamander password | TLS/h3, existing self-signed cert/key, URI/Mihomo/sing-box output | BLOCKED: Salamander absent; old certificate load rejected |
| TUIC v5 | sing-box | `tuic_generate_server_config`; `STATE/tuic/instances/ID/state.json`, `CONFIG/tuic/instances/ID/config.json` | UDP:P; per-user UUID/password | TLS/h3, cubic/native, zeroRTT=false, user management, existing certificates | Typed base equivalent; BLOCKED on existing certificate/lifecycle |
| VLESS TCP + REALITY + Vision | Xray | `reality_generate_server_config`; `STATE/vless-reality/instances/ID`, `CONFIG/vless-reality/instances/ID` | TCP:P plus private loopback defender port 20000..29999; UUID, X25519 private/public key, short ID | SNI and target port distinct from Display; auto/custom qualified target; filtering/routing/defender; existing URI/Xray/Mihomo/sing-box output | Key fields expressible; BLOCKED pending defender/routing equivalent and lifecycle |
| VLESS + FinalMask/Sudoku TCP | Xray | `vless_sudoku_generate_server_config`; `STATE/vless-sudoku`, `CONFIG/vless-sudoku` | TCP:P; UUID plus Sudoku password | Plain VLESS, decryption/encryption=none, FinalMask Sudoku, Xray client | RETAIN external pinned Xray; specialized exception already exists |
| SSH Tunnel | Existing sshd | Existing policy/state/key generators | Existing external listener; per-user key; no UDP | Administrator watchdog and confirmation | Required utility; unchanged scope |
| Forward | nftables / Realm | Forward state + nft/Realm generators | TCP/UDP/BOTH listener/target; no proxy credentials | nft IPv4 DNAT; Realm domain/IPv6/options; separate ownership | Required network utility; unchanged scope |

NaiveProxy, mKCP and XHTTP: N/A in current NoBrand feature set; do not add.
Field-by-field A/B/C/D mapping is in the [contract audit](../SPLICORE-RC2-CONTRACT.md#field-ownership-and-mapping).
No field was dropped and no credential, port, TLS file or REALITY key was rotated.
This is preservation by avoiding an unsafe cutover, not a completed migration.

## Retained External Cores

The intended permitted proxy-Core exception is **Xray 26.3.27 for the existing
VLESS + FinalMask/Sudoku mode**. No new specialized mode was added. There is no
new generic Xray fallback and Splicore does not manage Xray.

Actual tree at completion still retains Mita, Surge Snell, ordinary Xray and
sing-box runtime paths because migration is blocked. Those are outstanding
migration work, not accepted exceptions. Realm and external system sshd are
required network/system utilities outside the ordinary proxy-Core conversion.

## Splicore Artifact

| Check | Result / evidence |
|---|---|
| amd64 archive SHA256 | bc438dba6d43f016f1f23473495b9af49abb95153bb62ac4d809e85cd472922e |
| arm64 archive SHA256 | ff79beb51588d9539498976ee2b0697e3243e89dc74e467874a6a143bce5890f |
| Official SHA256SUMS | PASS, both exact filename entries from same pinned release |
| Archive safety | PASS for both archives in qualification helper; reject traversal/absolute/link/special/unexpected runtime entries |
| Binary identity | PASS, amd64 exact product/version/commit/clean/platform |
| libc/dependencies | amd64 static ELF, `ldd`: not a dynamic executable |
| arm64 | ELF machine inspected, archive verified; binary not executed |
| Atomic Install | NOT IMPLEMENTED; no live binary replacement attempted |
| Public Splicore installer executed | NO |
| Candidate executed before checksum | NO; helper verifies archive and identity before protocol probe |

## Architecture / Configuration

| Component | Current result |
|---|---|
| Artifact Manager | Not integrated; audit helper only verifies private artifacts |
| Config Renderer | Public contract documented; existing renderers not converted |
| Runtime Manager | Existing multi-Core managers; no new active unit |
| Protocol modules directly download Core | YES in current implementation; target requirement not achieved |
| Single primary Core | NOT ACHIEVED in NoBrand installer |
| Canonical runtime config | YAML bootstrap + managed JSON + SQLite/key, not sing-box JSON |
| NoBrand authority marker | Existing schema-v3 registry; no splicore marker written |
| Config Validation | Basic typed documents accepted; incompatible options rejected; TLS can fail only at runtime preparation |
| Atomic Config | Not implemented for Splicore; old transaction behavior retained |
| Ports/Credentials preserved | Existing deployments not touched; actual migration untested |
| TLS | Existing NoBrand generated synthetic certificates rejected by rc.2 apply |
| REALITY | Key import expressible; current defender/security mapping not qualified |

### Filesystem, service, scheduler and firewall audit

NoBrand state/config/lib roots and lifecycle sibling directory remain unchanged.
Mieru additionally owns per-instance config, run sockets and metrics under
`/etc/mita`, `/run/mita-instances`, `/var/lib/mita/instances`; package resources
may preexist and are protected by the uninstall ledger. No broad cleanup is safe.

NoBrand produces both systemd and OpenRC service definitions. Mieru uses
mita:mita, environment-selected JSON/socket paths, private mounts and per-user
metrics bind mounts. Current Snell/Xray definitions explicitly use root; TUIC
inherits the service default account. Existing units use restart supervision;
future Splicore service should use one account and retain necessary capabilities,
limits, working paths and restart behavior rather than defaulting to root.

`nobrand-mieru-users-scan.timer` or `/etc/cron.d/nobrand-mieru-users` handles expiry
and calendar quota every 15 minutes. It is a business-policy scheduler, not a
duplicate Core supervisor. SSH watchdog is a separate administrator access
safety mechanism. No ACME/certbot renewal or Core-specific certificate restart
hook was found; current HY2/TUIC certificates are generated locally. No new cron,
watchdog, supervisor or service was installed.

Firewall is already driven by transport/port ownership (`tcp:P`, `udp:P`), with
owned ufw/firewalld/iptables adapters and strict ingress nft policy. Port registry
and ingress enforcement must remain authoritative across Core changes; unchanged
ports must not cause unrelated firewall rebuilds. The audit did not change any
firewall, address, route, sysctl, tc filter or live service.

## Fresh Install / Multi-Protocol

NoBrand fresh Splicore install: **BLOCKED / NOT RUN**.

The isolated contract probe used one public Splicore process with four healthy
loopback inbounds: Snell v5, Mieru TCP, plain HY2 and TUIC v5. All four were
reported healthy by `inbound list`. This excludes Salamander and uses test CA +
SAN leaf certificates; it therefore does not satisfy old client compatibility.
No data-plane traffic certification is claimed.

| Evidence | Result |
|---|---|
| Single isolated Splicore daemon | PASS, 4 native inbounds in one process |
| No extra proxy-Core process created by probe | PASS by launch design; only Splicore plus transient CLI commands |
| NoBrand ordinary download trace | NOT IMPLEMENTED; old downloaders remain |
| Listener isolation / old credentials | NOT traffic-qualified |
| Existing NoBrand client profiles | NOT RUN against new server |
| Fresh installer only downloads Splicore | FAIL target gate: current installer still has old Core branches |

## Download Audit

Read-only public audit requests used these URL families, all pinned:

```text
https://github.com/ike-sh/Splicore/releases/tag/v0.3.0-rc.2
https://api.github.com/repos/ike-sh/Splicore/releases/tags/v0.3.0-rc.2
https://api.github.com/repos/ike-sh/Splicore/git/ref/tags/v0.3.0-rc.2
https://api.github.com/repos/ike-sh/Splicore/git/tags/9913c1043b87b5f56c2c0d98e38366fd7ad98584
https://api.github.com/repos/ike-sh/Splicore/tarball/v0.3.0-rc.2
https://github.com/ike-sh/Splicore/releases/download/v0.3.0-rc.2/SHA256SUMS
https://github.com/ike-sh/Splicore/releases/download/v0.3.0-rc.2/splicore-v0.3.0-rc.2-linux-amd64.tar.gz
https://github.com/ike-sh/Splicore/releases/download/v0.3.0-rc.2/splicore-v0.3.0-rc.2-linux-arm64.tar.gz
```

GitHub's normal HTTPS redirects were followed. The source archive is a read-only
tag reference, not a runtime dependency or local build. No old Core was
downloaded by the contract probe. Existing unit tests use their existing mocks.
This is not a trace of a completed NoBrand fresh deployment.

No shared GitHub proxy/mirror abstraction exists in current `src`; downloaders
use independent curl calls. Proxy-mode artifact identity and failure injection
remain unimplemented. No mirror was treated as checksum authority.

## Legacy Migration / Rollback / Update

| Stage | Result |
|---|---|
| DISCOVER | Repository model inventoried; no live user server inspected |
| BACKUP | Existing backup contract audited; no real deployment backup made |
| PLAN | Blocked on public contract gaps; no executable migration plan emitted |
| BUILD CANDIDATE | Isolated synthetic public-binary candidate only |
| VALIDATE | Positive base and negative compatibility probes complete |
| STOP LEGACY / START SPLICORE | NOT RUN on any deployment |
| VERIFY old traffic | NOT RUN |
| COMMIT / RETIRE OLD SERVICES | NOT RUN |
| Failure rollback | No migration implemented; not accepted by mock-only evidence |
| Same-version upgrade/no-op | Not integrated |
| Explicit upgrade/downgrade | Not integrated; target audit pin remains rc.2 |
| Crash recovery / persistent migration journal | Not integrated |

Current unified backup contains NoBrand state/config and intentionally excludes
downloaded binaries and service definitions. A real migration needs a dedicated
known-good binary/unit/active-enabled snapshot in addition to that archive.
Existing lifecycle lock/recovery records live beside the state root and must
cover the new transaction. Mieru user backups retain the latest 20; unified
archives have no automatic retention pruning. Do not invent a claimed existing
global retention policy.

## Distribution / Service / Uninstall / Purge / Doctor

| Requirement | Result |
|---|---|
| NoBrand Splicore service name/count | N/A; none installed |
| Production process count/orphans | Not measured; no deployment changed |
| Isolated probe process cleanup | PASS; daemon terminated/joined; temporary directory removed |
| systemd restart / crash recovery | NOT RUN for Splicore integration |
| OpenRC | Existing support audited; Splicore integration not tested |
| Debian/Ubuntu/RHEL/Alpine | Current package branches retained; no expanded/narrowed supported set claimed |
| Uninstall / purge | Splicore integration NOT IMPLEMENTED; existing owner/path-safe lifecycle retained |
| Legacy cleanup | None performed |
| Status / doctor | Current multi-Core views; no active Splicore detection/metadata gate |
| Binary/config/version/permissions/listeners/traffic doctor | Required adapter work outstanding |
| Legacy residue | No live inventory; source references remain, see below |

There is no distinct existing `purge` command to preserve. The new Splicore
uninstall/purge policy has not been implemented or advertised.

## Security

| Check | Result |
|---|---|
| Public SHA256 gate | PASS for audit artifacts; exact entries required |
| TLS downloads | HTTPS with normal verification; no insecure download flag |
| Secret leak | No real credentials read or written to the report; all probe material synthetic |
| Temporary directory | Unique private Python temporary directory, cleaned on normal/error exit |
| Archive traversal / absolute path | Rejected in targeted safety tests |
| Symlink / hardlink / FIFO / unexpected runtime entry | Rejected in targeted safety tests |
| Corrupt/interrupted archive | Checksum mismatch rejected before execution in targeted tests |
| Missing/duplicate checksum entry | Rejected in targeted tests |
| Unsupported architecture | Rejected in targeted tests; no fallback |
| Atomic live install / rollback / fsync | Not implemented; not reported PASS |
| Real certificate/credential preservation under migration | Blocked; no unsafe transformation performed |

## Static Audit

Searches included xray, sing-box, singbox, mieru, mita, naive, hysteria, tuic,
snell, vless, reality, core, binary, github, release, download, systemctl and
service across source/scripts/docs/tests and generated artifacts.

| Classification | Remaining references |
|---|---|
| Legacy Migration | Existing legacy-state detection, ownership/preservation checks, rollback/restore logic; necessary to retain. No Splicore migration adapter yet. |
| Specialized Xray | `src/23-platform-vless-sudoku.sh`, `src/58-vless-sudoku.sh`, associated menu/export/tests, pinned shared Xray infrastructure; existing authorized mode. Shared infrastructure still also serves ordinary consumers. |
| Historical Documentation | CHANGELOG, prior release/acceptance docs; historical names remain valid. |
| Required Utility / protocol-client identity | Mieru/Snell/HY2/TUIC/VLESS protocol names; sing-box/Mihomo/Xray client projections/reference tests; system sshd, Realm, BBR and firewall tools. |
| Unexpected for the requested final architecture | **NONZERO**: active Mita, Surge Snell, TUIC sing-box and ordinary HY2/REALITY Xray install/repair/upgrade/restore/service/status/uninstall branches, including generated installers. |

Unexpected runtime references are not zero. No claim is made that single-Core
static acceptance passes. The complete active runtime module families and
indirect call sites are enumerated above; they remain pending because of the
contract blockers. Current NoBrand installer/latest, Mieru/TUIC explicit latest
and Realm latest URLs remain outside the new audit fixture. Splicore audit URLs
contain no latest/main/nightly download path. Unknown audit Core downloads: 0;
NoBrand fresh download acceptance: not reached.

## Tests and Evidence

New safety-helper tests cover architecture normalization/rejection, exact/missing/
duplicate/malformed checksum entries, archive allowlist/path/link/special-file
safety, and corrupt/partial archive rejection. They are included in the ordinary
`scripts/test.sh` unit manifest; the full public-binary probe is explicit opt-in.

Public binary probe result:
[`SPLICORE_RC2_CONTRACT_PROBE.json`](SPLICORE_RC2_CONTRACT_PROBE.json).
Probe completed as an unprivileged user under local Ubuntu 24.04 WSL. It used
verified public assets and no local Splicore build. It applied four healthy base
inbounds, rejected the incompatible options and actual generated certificates,
and observed DELETE HTTP 405 for each real created inbound.

Repository regression: **PASS**, `bash scripts/test.sh` exited **0** under
Ubuntu 24.04 WSL. This includes the generated-installer build/check, Bash syntax
checks, the existing ShellCheck gates, and all **48 Bash unit-test files**.
The new Python self-tests passed all four safety test groups. Existing lifecycle
recovery tests passed all 4 install, 10 repair and 9 uninstall interruption
checkpoints, signal recovery and repeated-rerun checks. Final output:
`[PASS] NoBrand test suite`.

The existing real-runtime integration group was explicitly skipped by the
default suite. These regression results do not certify a Splicore migration,
old-client traffic, service cutover or rollback. No Docker harness was invoked.

An initial unprivileged whole-suite attempt stopped at `test_schema_v3.sh`
because its fixture ownership gate requires root; this is an environment/test
precondition, not a migration regression. A root retry encountered Git's dubious
ownership gate. The successful run used WSL's root account, matching the
repository's existing unit-test CI container user, and process-scoped
`GIT_CONFIG_COUNT` / `safe.directory` settings. No global or repository Git
configuration was changed.

Final repository checks: `git diff --check` passed; the index is empty; HEAD
remains the baseline; source modules and both generated installers have no
diff. All retained changes are migration audit documentation, the pinned audit
fixture/probe and its test-suite entry.

## Final Full Acceptance

| Gate | Result |
|---|---|
| A Fresh amd64 NoBrand install | BLOCKED |
| B Multi-protocol single Splicore runtime | Isolated public Core probe PASS; NoBrand deployment BLOCKED |
| C All migrated protocol critical traffic | NOT RUN |
| D Existing client profile compatibility | BLOCKED / NOT RUN |
| E Legacy multi-Core migration | NOT IMPLEMENTED |
| F Migration failure rollback | NOT IMPLEMENTED |
| G Core upgrade shared framework | NOT IMPLEMENTED |
| H Uninstall | NOT IMPLEMENTED for Splicore |
| I Purge | NOT IMPLEMENTED for Splicore |
| J Doctor | NOT IMPLEMENTED for Splicore |
| K Service restart | NOT RUN for Splicore integration |
| L Crash recovery | NOT RUN for Splicore integration |
| M Checksum corruption | Audit helper rejection PASS; live installer gate absent |
| N Unsupported architecture | Audit helper rejection PASS; live installer gate absent |
| O Repeated install/update | NOT IMPLEMENTED |
| P No unwanted Core download | Probe PASS; active installer requirement not achieved |
| Q No old active service/process residue | No deployment cutover; NOT ACCEPTED |

Traffic matrix for Mieru, Snell v4/v5, HY2, TUIC v5 and REALITY: TCP/UDP/IPv4/
IPv6/domain/old-profile dimensions remain **NOT RUN** for this migration, rather
than being inferred from configuration acceptance. Non-applicable dimensions
must be marked individually when actual traffic tests are implemented.

## Xray Boundary

Ordinary VLESS target: Splicore, but no unsafe automatic fallback was introduced.
Existing FinalMask/Sudoku target: separate pinned external Xray only. No new
FinalMask/Sudoku work was performed. Splicore manages Xray: NO. Existing shared
ordinary Xray paths remain an uncompleted migration item, not an exemption.

## Splicore Repository / Docker / Git

| Item | Result |
|---|---|
| D:/code/Splicore modified | NO; only read-only tag lookup attempted; local rc.2 tag absent |
| Local Splicore working files/builds required | NO |
| Public rc.2 enough to reproduce audit | YES |
| Public rc.2 enough for full requested compatible migration | NO, see blockers |
| Docker Desktop queried/restarted/modified | NO / NO / NO |
| Redis / TeleLedger modified | NO / NO |
| Stage | NONE |
| Commit | NONE |
| Push | NONE |
| Tag | NONE |
| Release | NONE |

## Blockers

All are **SPLICORE RC.2 INTEGRATION BLOCKER** findings for this pinned target:

1. **HY2_SALAMANDER**: current NoBrand always emits Salamander, rc.2 rejects it.
2. **SERVER_INBOUND_LIFECYCLE**: no complete server listener remove/update/stop
   surface for the existing per-node management contract in one shared daemon.
3. **TLS_CERTIFICATE_PRESERVATION**: current generated HY2/TUIC self-signed
   certificates cannot be loaded unchanged in the tested environment.
4. **MIERU_ADVANCED_SETTINGS_AND_QUOTA**: managed advanced traffic settings and
   compatible durable quota/accounting/calendar reset are unavailable; defaults
   and existing enforced packages cannot be silently weakened.
5. **SNELL_QUIC_AND_PSK_DOMAIN**: existing QUIC option and some valid stored PSKs
   cannot be represented unchanged; old v5 client wire needs qualification.
6. **REALITY_DEFENDER_AND_ROUTING_PARITY**: existing security/dispatch/filtering
   behavior has no qualified equivalent mapping; preserving keys alone is
   insufficient.

Resolving these may require a separately released Splicore capability or a
maintainer-approved scope/compatibility decision. This phase neither changes
Splicore nor changes the target pin nor silently drops existing features.
