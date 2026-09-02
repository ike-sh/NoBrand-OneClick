# Changelog

## 3.2.0 — Unreleased release candidate

### Added

- Added first-class Ingress Profiles for public and mapped service entries. Profiles record entry identity, selected local interface/IPv4, port policy, reserved ports, Display Endpoint defaults, enablement, and stable profile IDs without managing Linux network configuration.
- Added `derived-tail`, `custom-range`, and `manual-only` port policies, plus explicit default-profile selection and `--ingress-profile` support for Mieru, Snell v4/v5, Hysteria2, TUIC v5, Plain VLESS/Sudoku, SSH Tunnel metadata, and nftables/Realm Forward rules.
- Added Dual VPS / multi-ingress foundations, profile list/show/add/modify/delete/default/Doctor CLI and menu flows, profile-aware status/nodes output, backup/restore coverage, and Debian/Ubuntu/Rocky/Alpine parser/state qualification.
- Added independent named-instance VLESS REALITY with the fixed `VLESS + TCP + REALITY + xtls-rprx-vision` stack, per-instance UUID/X25519 keypair/short ID/target/service/TCP port/firewall/Profile/Display state, enforcement-resolved Xray listeners, and public-Profile recommendation with mapped-Profile warning-only behavior.
- Added standard REALITY `vless://`, current Xray 26.3.27 JSON (`realitySettings.password` for public material), Mihomo 1.19.30 rule-mode YAML, and sing-box 1.13.20 JSON exporters. Complete Mihomo/sing-box configs have no DIRECT member or fallback.
- Added REALITY status/nodes/Doctor, exact key-derivation and config validation, root-only private-key handling, shared-Xray transactional upgrade/rollback, backup/restore, formal removal, unified uninstall, platform-matrix generation, and three-client local runtime qualification.
- Added a per-instance VLESS REALITY loopback defender: the public REALITY `target` points to an automatically owned `127.0.0.1` dokodemo-door listener; exact sniffed SNI alone reaches a fixed redirect to the validated camouflage target, while wrong/no SNI and random probes hit an adjacent catch-all block. Private destinations, selected dangerous TCP ports, and BitTorrent remain blocked before the allow rule.
- Added transactional private Xray `geoip.dat`/`geosite.dat` installation from the same verified 26.3.27 archive, defender listener/same-process acceptance, internal-port collision ownership, Doctor, backup/restore, rollback, removal, and Xray/Mihomo/sing-box anti-probe runtime coverage.
- Added server-side REALITY `minClientVer="0.0.0"` while keeping the field out of all client exporters and URIs.
- Added automatic REALITY camouflage-host selection from an immutable release-qualified pool. Interactive blank host and non-interactive missing host select candidates in randomized order without replacement, validate the actual requested target port, persist both `camouflage_mode="auto"` and the selected hostname, and fail closed with transactional rollback on pool exhaustion. Explicit hosts record `camouflage_mode="custom"`, are used exactly, and never silently fall back to auto. The default camouflage target port remains 443 and remains independent from the public REALITY listener and internal defender ports.
- Added Profile-level `permissive` and `strict` ingress enforcement. Missing enforcement remains permissive; `--enforcement`, explicit `--apply-existing`, and `nobrand ingress apply PROFILE` provide transactional runtime migration.
- Added native strict binds for Snell v4/v5, Hysteria2, VLESS/Sudoku, VLESS REALITY, TUIC, and Realm Forward; destination-address matching for nftables Forward; and a counter-free NoBrand-owned `inet nobrand_ingress` firewall fallback for Mieru runtimes without a server listen-address field.
- Added real network-namespace TCP/UDP cross-entry isolation tests, strict firewall removal/reapply/cleanup coverage, Profile-wide rollback injection, native-listener rollback, Forward strict import/export, and four-platform strict/permissive parsing and generation checks.

### Changed

- Kept `schema_version=3`. Existing 3.1-style schema-v3 state without ingress fields remains valid and byte-stable during read-only startup through the implicit `legacy-default-route` adapter.
- REALITY state without an explicit `target_port` is interpreted read-only as 443, while state without `camouflage_mode` is interpreted as explicit/custom, without rewriting either file. Existing Microsoft or other explicit hostname state remains unchanged even when the hostname is absent from the qualified automatic pool.
- Port ownership remains host-global and transport-aware in both permissive and strict modes. `TCP:P` and `UDP:P` may coexist; two owners of the same transport and numeric port may not, even when their profiles differ.
- Ingress selection now controls actual-port allocation and automatic Display Endpoint metadata independently of the Linux default-route egress. Profiles do not change addresses, routes, policy rules, `rp_filter`, SSH listeners, provider mappings, or unrelated firewall state.
- Strict enforcement always uses the Profile local address, never the Display Host. It does not add policy routing, `fwmark`, routing tables, default-route changes, per-ingress accounting, quotas, shaping, or `rp_filter` changes. SSH Tunnel remains `NOT_APPLICABLE_TO_SYSTEM_SSH` because its listener is the external system sshd.
- Backup restore now establishes authoritative strict Mieru firewall state before starting wildcard Mieru runtimes; uninstall stops Mieru before clearing that owned table. Forward backend switches preserve Profile, port, Display, Target, and enforcement and restore the old data plane on failure.
- Pinned the shared NoBrand Xray runtime to exact 26.3.27 Linux amd64/arm64 assets with official SHA-256 verification. REALITY uses current `target` server semantics; the legacy Sudoku product remains plain VLESS/TCP/FinalMask with `security=none` and no VLESS Encryption.
- Changed default Mieru install/upgrade resolution to the highest official strict-semver stable release (`draft=false`, `prerelease=false`). A transaction pins exact release metadata, platform asset, API digest, official checksum manifest, downloaded bytes, and installed runtime identity; explicit versions remain pinned overrides.
- Qualified Mieru 3.36.0 as the 2026-09-01 latest stable and last-known-good fallback. Only metadata-fetch failure may use that explicit fallback warning; malformed metadata or an invalid/missing/duplicate asset fails closed. Upgrade rollback restores the previous managed binary, users, services, ports, and credentials.
- Set `PROTOCOL_FEATURE_FREEZE=true`: VLESS REALITY is the final planned protocol feature for 3.2.

### Fixed

- Fixed the TUIC Mihomo exporter to use rule mode so exported configurations keep proxy traffic on the selected TUIC transport instead of permitting a direct bypass.
- Fixed Hysteria2 and VLESS/Sudoku automatic Display Endpoint resets so they resolve through each node's stored Ingress Profile rather than falling back to default-route metadata.
- Redacted REALITY `privateKey`, public material, UUID, short IDs, password, and auth values from Xray validation diagnostics, and made REALITY systemd/OpenRC template replacement/removal fail closed for unowned files.
- Fixed first-use ingress and Forward administrative action ordering so the schema-v3 ownership root is initialized before the lock directory; dispatchers preserve exact action failure status and release only their own re-entrant lock level.
- Fixed BusyBox/Alpine administrative locking by using bounded `timeout` around BusyBox `flock`, and fixed interactive enforcement request leakage between Profile menu operations.

### Known limitations

- Hysteria2: Normal HTTPS/TCP use tested PASS. Some larger SOCKS5 UDP datagrams may experience integrity/time-out issues. This is not classified as Dual-specific, and no upstream defect has been confirmed.
- Port Forward: maximum usable raw UDP datagram size depends on the provider, NAT, tunnel, and Internet path. NoBrand transparently forwards application datagrams without fragmenting, resizing, or clamping them; a controlled backend path can therefore pass a tested size that a particular external path drops.

## 3.1.0 — 2026-08-31

### Added

- Added SSH Tunnel over the machine's existing OpenSSH sshd, with one locked system account and Ed25519 keypair per user, centralized authorized keys, forwarding-only Match policy, `-L`/`-D`/`-R`, `GatewayPorts=no`, host-key fingerprint discovery, strict pinned `known_hosts` export, and explicit private-key export.
- Added a two-phase SSH policy watchdog. Install, update, restore, module uninstall, and unified uninstall require candidate `sshd -t`/`sshd -T`, reload, and confirmation from a brand-new administrator SSH connection before rollback is cancelled or destructive work continues.
- Added TUIC v5 using a NoBrand-owned official sing-box runtime, isolated named instances, multiple UUID/password users, P-256 self-signed TLS, UDP firewall ownership, stable/latest/pinned runtime channels, and Mihomo/sing-box exporters.
- Added Port Forward as a Common Network Feature with a unified schema-v3 rule model, transport-aware Common Port ownership, metadata-only Display Endpoint, CLI/menu CRUD, enable/disable, Doctor, versioned JSON export/import, and transactional backend switching.
- Added an nftables backend for IPv4 TCP/UDP/BOTH DNAT, MASQUERADE default, Preserve Source advanced mode, one marked NoBrand-owned table, atomic candidate application, and ownership/refcount-aware `net.ipv4.ip_forward` persistence.
- Added a Realm backend using the official Realm v2.9.6 musl runtime, GitHub and pinned SHA-256 verification, one `nobrand-realm` systemd/OpenRC daemon, generated multi-endpoint config, IP/IPv6/domain targets, DNS, through/interfaces, Proxy Protocol, transports, extra remotes, load-balancing algorithms, and weights.
- Added real Forward runtime suites for official Realm TCP/UDP/BOTH/domain/multi-rule/advanced configuration, nftables namespace MASQUERADE/Preserve Source and external-table preservation, and nftables→Realm→nftables data-plane switching with induced candidate rollback.
- Added real OpenSSH and TUIC runtime suites. TUIC covers sing-box and Mihomo TCP plus SOCKS5 UDP ASSOCIATE at 64/512/1200/1400 bytes; SSH covers authentication, distinct UID/key isolation, forwarding, session denial, rotation, backup/restore, watchdog, and uninstall.
- Added Docker-daemon-free Debian/Ubuntu/Rocky/Alpine rootfs qualification, repository sanitization, ordinary-output secret checks, and SSH/TUIC install/restore failure injection.

### Changed

- Kept `schema_version=3`; SSH Tunnel, TUIC, and Forward are optional schema-v3 modules, so a valid 3.0 state remains valid and byte-stable when the new modules are absent.
- Unified nodes, status, Doctor, menus, backup/restore, and uninstall now include TUIC v5, SSH Tunnel, Forward nftables, and Forward Realm.
- The shared config root and SSH config root use traverse-only mode 0711 so sshd can read centralized public keys after switching identity; protocol secret directories remain 0700 and secret files remain 0600.
- Unified restore now snapshots and rolls back TUIC runtime/service-template and SSH sshd-config/Linux-account side effects in addition to state/config.
- Unified restore reconstructs Forward's official Realm runtime and restores the nftables table, Realm service/config, sysctl ownership, firewall bindings, and authoritative state transactionally.
- Unified uninstall pauses all other protocol removal until SSH policy removal is confirmed from a new administrator session.

### Fixed

- Fixed TUIC active-service candidate acceptance, which previously interpreted a successful restart/listener/ownership group as transaction failure.
- Fixed complete TUIC shared-runtime rollback after a later instance restart or state commit failure.
- Fixed SSH policy apply/reload and removal rollback, group/user creation cleanup, and account deletion state-write recovery.
- Fixed SSH centralized authorized-key traversal permissions discovered by a real sshd authentication test.
- Fixed service detection in chroot/container environments by requiring a live systemd runtime before choosing `systemctl` reload.
- Fixed jq 1.6 compatibility by avoiding the reserved `label` identifier in SSH user JSON generation.
- Fixed Forward ownership boundaries so same-name external nftables tables, Realm service/runtime paths, and sysctl fragments fail closed instead of being replaced or removed.
- Fixed Realm candidate validation so temporary free listeners are probed without stopping the active Realm data plane first; failed runtime/service/listener acceptance restores every Forward external side effect.
- Fixed Realm advanced validation for DNS nameserver and extra-remote socket addresses, integer timeout/weight bounds, balance target counts, and global DNS consistency.
- Fixed Realm domain/IPv6 to nftables switching so it always requires an explicit IPv4 target and never resolves a domain once and pins the result.
- Fixed `forward modify --port` so an automatic Display Endpoint follows the new listener port while an explicitly customized Display Endpoint remains unchanged.
- Fixed unified Forward restore so a missing NoBrand-owned sysctl fragment is reconstructed from valid ownership state, while a symlink, foreign file, or mismatched content continues to fail closed.

### Validation status

- Final unit/transaction, warning-level ShellCheck, real upstream runtime, deterministic-build, repository-sanitization, and Debian/Ubuntu/Rocky/Alpine platform gates pass.
- Real-machine qualification passes the exact 3.1.0 candidate for upgrade preservation, all supported protocols, TUIC TCP/UDP, SSH Tunnel SOCKS5, nftables/Realm Forward, backend switching and rollback, backup/restore, unified uninstall, fresh reinstall, external-resource preservation, and final production-style health.
- `LOCAL_TEST_GATE=PASS`, `REAL_MACHINE_GATE=PASS`, and `PROTOCOL_FEATURE_FREEZE=true`. Snell v5 QUIC Proxy Mode remains OFF and its official QUIC wire remains NOT VERIFIED.

## 3.0.0 — 2026-08-28

### Unified clean architecture

- Reduced the public surface to one release asset (`install-nobrand.sh`), one canonical command (`nobrand`), and one short symlink (`nb -> nobrand`).
- Removed the second installer, management wrappers named after the Mieru runtime, basename compatibility routing, raw-main installation fallback, and compatibility build artifacts.
- Introduced the authoritative `/var/lib/nobrand-oneclick/` root with an exact `schema_version=3` / `ownership=nobrand-v3` marker and root-only permissions.
- Legacy Mieru and previous NoBrand state now fail closed without being read, imported, converted, deleted, or modified. Help and version remain state-independent.
- Unified backup/restore and uninstall now cover Mieru, Snell, Hysteria2, VLESS/Sudoku, and common owned resources while preserving pre-existing/external resources.

### Full Mieru parity

- Preserved the mature Mieru Profile, TCP/UDP/BOTH, MTU, Multiplexing, Handshake, Traffic Pattern, Low Entropy, version-channel, multi-user, isolated-v2, quota, expiry, tc/rate, BBR/FQ, firewall, exporter, diagnostics, backup, systemd, and OpenRC behavior.
- Added an exhaustive parity inventory plus a frozen v2.2.1 authority fixture and golden tests for defaults, Profiles, Mita server JSON, official client JSON, `mierus://`, Mihomo YAML, Endpoint, and port semantics.
- Moved the official upstream Mita binary to an explicit NoBrand-managed runtime path. The runtime keeps its upstream name but is not a management command.
- Added host-only and port-only Mieru Display Endpoint updates by merging the unchanged effective half into a complete validated pair; Endpoint updates remain isolated from config, PID, listener, firewall, tc, and quota.

### Protocol and safety hardening

- Snell support is strictly v4/v5. Removed active v6 state/runtime/service migration and old QUIC-field migration code; no hidden v1/v2/v3/v6 install path exists.
- Preserved Snell v5 QUIC exposure semantics: OFF by default, TCP always managed, same-number UDP ownership only when explicitly enabled.
- Preserved Xray Hysteria2 semantics and Plain VLESS + FinalMask/Sudoku over TCP with `VLESS_ENCRYPTION_ENABLED=false`.
- Added schema-v3, command-topology, missing-CLI-value, unified-uninstall ownership, and Mieru Endpoint isolation regressions.
- Renamed distribution compatibility smoke entry points to platform smoke tests and updated CI to validate only the canonical artifacts.

## 1.3.0 — 2026-08-28

### Removed

- Removed Snell v6 after its one permitted final public-path qualification returned 3/20 HTTPS and failed both download and upload through the forced public entry.
- Removed active v6 menu, CLI, resolver, download, runtime, config, state, service, exporter, Doctor, nodes, backup/restore and upgrade product paths. Historical migration/negative tests and release records remain intentionally.

### Added

- Added Snell v5 `--quic on|off` installation and `set-quic` controls; non-interactive v5 defaults to OFF when omitted, while v4 rejects QUIC ON.
- Added explicit `quic_proxy_enabled` and `managed_udp` state, same-number UDP ownership, same-process TCP/UDP listener acceptance and Doctor/nodes visibility.
- Added native Hysteria2 Mihomo and sing-box exports and completed NoBrand-exporter → transfer → config-check → real-client round trips.
- Added Mihomo 1.19.30 / sing-box 1.14.0-rc.1 20-request public connectivity, 256 MiB download/upload, restart recovery, packet-capture and resource matrices, plus Mieru/Xray reference-client controls.
- Added exact removed-v6 migration tests and comprehensive QUIC install/toggle/firewall/rollback/endpoint/backup/Doctor tests.

### Changed

- Snell product scope is now v5 Recommended/Default and v4 Compatibility only.
- Snell v5 QUIC OFF owns TCP only even when the official runtime keeps a local auxiliary UDP socket; QUIC ON owns TCP and same-number UDP without rewriting server config, restarting service or rotating PSK.
- Snell v5 automatic port allocation checks both TCP and UDP when QUIC ON is requested.
- sing-box exports a v5 non-QUIC server using its upstream v4-compatible client wire expression; Mihomo ordinary `udp: true` is documented separately from official QUIC Proxy Mode.
- Normalized legacy v4/v5 state to explicit false QUIC fields without inferring user choice from a runtime UDP socket.

### Fixed

- Fixed the Snell install acceptance condition that could invert a successful service/listener check into rollback.
- Fixed legacy QUIC state normalization and fail-closed handling for invalid or contradictory boolean state.
- Fixed exact v6 migration ownership boundaries so cleanup never infers same-number UDP ownership or touches an unrelated HY2 rule.
- Fixed exporter return propagation and exporter fields discovered by real Mihomo/sing-box parsing and launch tests.
- Preserved bidirectional transactional rollback when QUIC firewall or state persistence fails.

### Validation

- Docker Debian 12 unit and runtime suites pass, including official Xray 26.3.27 and Surge Snell v4.1.1/v5.0.1 data-plane/listener checks and a removed-v6 negative download assertion.
- The 1.3.0 real-client report records raw baseline, every successful/failed run, HTTP 429 environment blocks, cold-start sensitivity and server/client restart outcomes without promoting unsupported or blocked combinations to PASS.

## 1.1.0 — 2026-08-27

- Added Plain VLESS + FinalMask + Sudoku over TCP with isolated config/state/service and the existing transport-aware Common Port and Display Endpoint layers.
- Reused the NoBrand-owned Xray-core binary while keeping HY2 and VLESS processes, state, config, and services isolated.
- Explicitly removed the planned VLESS Encryption dependency: no key-generation subcommand, encryption/decryption key pair, ML-KEM, xorpub, method, RTT, or ticket state.
- Added Xray client JSON and VLESS URL export using Display Endpoint; endpoint-only updates do not touch server config, listener, service, PID, or firewall.
- Added an atomic shared-Xray upgrade transaction that validates both configs, accepts both active listeners, and restores binary plus both state files on failure.
- Added jq-canonical Xray-OneClick Sudoku golden coverage, Encryption-absence checks, systemd/OpenRC generation, lifecycle/idempotency/remove/rollback tests, and a real Xray FinalMask/Sudoku localhost data plane.
- Added VLESS to unified nodes/status/doctor/backup/uninstall, the top menu, the complete 1–11 protocol submenu, CLI aliases, documentation, and CI.
- Fixed boolean state getters so an explicit `enabled=false` is preserved instead of being mistaken for a missing value.
- Reserved the default-route IPv4 tail block base `xx00` in Common Port so an outer NAT/DNAT SSH or management port that is invisible to guest socket inspection cannot be auto-selected by a proxy.
- Rejected the reserved tail-base `xx00` for explicit TCP and UDP listener requests as well as automatic allocation; the automatic pool remains `xx01-xx99`.
- Documented the official Snell v5 same-port auxiliary UDP listener as upstream runtime behavior while keeping NoBrand canonical ownership, nodes, and firewall management on TCP.
- Kept Snell v6 classified as Experimental independently of upstream Beta/RC/GA labeling, and documented the known environment-dependent public-path behavior without turning it into a static Doctor failure.
- Added a strict NoBrand `--version` response, rejected unknown or surplus top-level CLI arguments, and made the build fail when any `src/*.sh` module is omitted or duplicated in the ordered manifest.
- Completed destructive IPLC/Debian validation, including real TTY, six-protocol 20/20 public E2E, restart/lifecycle/Endpoint/backup/remove-reinstall checks, and final simultaneous regression; the later external Snell v6 public-payload blackhole is retained as `ENVIRONMENT BLOCKED` in the validation report instead of being promoted to PASS.

## 1.0.0 — 2026-08-27

- Fused the mature Mieru OneClick architecture with official Snell v4/v5/v6 and Xray-core Hysteria2.
- Added transport-aware Common Port Registry and strict Real/Display Endpoint separation.
- Preserved Mieru isolated-v2, multi-user, quota, tc, export, backup, service, firewall and CLI behavior.
- Added isolated Xray HY2 with P-256, Salamander, atomic rollback and golden tests.
- Added official Surge Snell resolver, multi-instance services/state, release metadata, exporters and rollback.
- Added unified menu/nodes/status/doctor/backup and Debian/Ubuntu/Rocky/Alpine + real runtime tests.
- Relicensed the fused project under GPL-3.0 while preserving Mieru MIT attribution.
