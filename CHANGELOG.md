# Changelog

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
