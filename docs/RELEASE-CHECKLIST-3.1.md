# NoBrand-OneClick 3.1.0 release checklist

Status date: 2026-08-31 (Asia/Shanghai). This checklist records the completed development and qualification evidence for the v3.1.0 release. Commit, annotated-tag, GitHub Release, latest-release and public-asset identities are verified separately by the publication gate.

## Source and architecture

- [x] Candidate identity is 3.1.0; schema remains v3.
- [x] Protocol scope matches `docs/PROTOCOL-SCOPE.md`; `PROTOCOL_FEATURE_FREEZE=true`.
- [x] All seven Mieru 3.0 parity assertions pass.
- [x] Snell v4/v5, HY2 and plain VLESS/FinalMask/Sudoku contracts remain unchanged.
- [x] TUIC v5, SSH Tunnel and Port Forward are schema-v3 optional modules; valid 3.0 optional-empty state compatibility passes.
- [x] An exact-artifact `nobrand manager install|upgrade` path supports Mieru-free 3.0 deployments without mutating protocol state.
- [x] Port Forward has one authoritative NoBrand state, transport-aware Common Port ownership, metadata-only Display Endpoint and transactional CRUD/backend switching.
- [x] nftables is IPv4-literal-only and owns one marked `table ip nobrand_forward_v4`; it never flushes unrelated rules and safely reference-counts `net.ipv4.ip_forward`.
- [x] Realm uses only verified official `zhboner/realm` assets, one private NoBrand runtime/service/config, one daemon for all enabled rules, and preserves external Realm resources.
- [x] Realm domains remain domains; switching to nftables requires an explicit IPv4 target and never pins a one-time DNS result.
- [x] One root installer and one byte-identical dist installer; no `install-mita.sh` artifact.
- [x] Function orphan, duplicate and accidental override counts are zero.

## Focused development evidence

- [x] Warning-level ShellCheck passes for source model, scripts, tests and generated installers.
- [x] Forward state/config/import/export, transaction/backend-switch rollback, sysctl ownership and Realm/nftables external-ownership focused suites pass.
- [x] Unified restore safely recreates an absent NoBrand-owned Forward sysctl fragment from valid ownership state, while an existing mismatched file or symlink remains fail-closed; focused ownership, transaction and backup-boundary regressions pass.
- [x] Forward `modify --port` keeps a custom Display Endpoint unchanged and synchronizes `display_port` when the previous Display Endpoint is automatic; focused regression and real-machine acceptance pass.
- [x] Privileged isolated-network backend-switch runtime passes nftables TCP/UDP/BOTH, Realm TCP/UDP/BOTH, switch-back, and failed-candidate rollback while preserving the active data plane.
- [x] Real TUIC sing-box and Mihomo TCP/UDP data planes pass, including 64/512/1200/1400-byte UDP payloads.
- [x] Real OpenSSH policy, authentication, distinct UID/key isolation, denial matrix, `-L/-D/-R`, GatewayPorts, rotation, backup/restore, watchdog and uninstall pass.
- [x] Restore failure injection rolls back SSH users/group/sshd config and TUIC runtime/service template.
- [x] TUIC download/config/state/firewall/service and shared-runtime rollback matrix passes.
- [x] Ordinary status/Doctor/nodes/menu output is secret-free; credential output requires explicit actions.
- [x] Candidate public tree scans report zero private key, TUIC credential bundle, lab infrastructure literal, runtime binary and client bundle matches.

## Final combined local gate

- [x] Rebuild root/dist installers after all final source and documentation edits; `scripts/build.sh --check` passes.
- [x] `git diff --check`, Bash syntax and warning-level ShellCheck pass on the final generated installers, source, scripts and tests.
- [x] Full `scripts/test.sh` ordinary/unit/transaction/parity suite passes after the final Forward changes.
- [x] Unified `scripts/test.sh --runtime` passes Xray/Snell, TUIC, OpenSSH, nftables, official Realm and real backend switching in one run.
- [x] Standalone privileged nftables namespace acceptance passes TCP, UDP, BOTH, MASQUERADE, Preserve Source and external-table preservation.
- [x] Debian, Ubuntu, Rocky and Alpine platform/rootfs matrices pass.
- [x] Legacy Docker smoke and existing Mieru/protocol regressions pass.
- [x] Architecture/dead-code, repository sanitization, sensitive-output, secret and infrastructure scans pass.
- [x] Final root/dist installers are byte-identical: each is 768316 bytes with SHA-256 `9c320c931edbfa7ca2e3085630e31f63c94a83dfb173ca3152a47a1a09872d6d`.
- [x] `LOCAL_TEST_GATE=PASS` is supported by the complete current-run evidence above.

## Real-machine qualification

- [x] The normal authorized SSH-helper connection path validates the pinned ED25519 host key, decrypts the existing encrypted key credential, authenticates as the configured administrator and executes remote commands without any host-key bypass.
- [x] Capture the current v3.0.0 real-machine baseline and root-only production backup.
- [x] Transfer the exact locally qualified 3.1.0 installer only through the authorized SSH helper.
- [x] Prove 3.0→3.1 credential, Endpoint, port, listener, service and existing-node preservation.
- [x] Prove new administrator SSH access after every sshd policy change.
- [x] Prove SSH Tunnel account authentication, shell denial, `ssh -N -D`, controlled TCP through SOCKS5 for 20/20 attempts, strict client host-key validation and administrator SSH preservation.
- [x] Prove two TUIC users with sing-box and Mihomo over the public path, TCP/UDP, 64/512/1200/1400-byte UDP integrity, credential/Endpoint restore and throughput evidence.
- [x] Prove nftables TCP, UDP and BOTH forwarding, MASQUERADE, Preserve Source, exact owned-table removal and external firewall preservation.
- [x] Prove official Realm TCP, UDP, BOTH, domain target, multi-rule operation, one-daemon ownership and external Realm preservation.
- [x] Prove nftables ↔ Realm backend switching, target re-entry boundary and failed-candidate rollback without state or data-plane loss.
- [x] Prove unified nodes/status/Doctor, root-only backup, perturbation/restore, two-phase unified uninstall, system sshd/admin preservation and external-resource preservation.
- [x] Fresh-install the exact 3.1.0 candidate and leave Mieru, Snell v4, Snell v5 with QUIC OFF, Hysteria2, TUIC v5, VLESS/Sudoku, SSH Tunnel, one nftables Forward rule and one Realm Forward rule.
- [x] Repeat final ordinary-output secret scans, cleanup checks and public-tree/repository sanitization checks.

All real-machine items pass: `REAL_MACHINE_GATE=PASS`. Together with `LOCAL_TEST_GATE=PASS`, the exact candidate is `READY FOR v3.1.0 RELEASE`. Publication must preserve a single identity across main, the annotated `v3.1.0` tag, the GitHub Release, Latest Release, `install-nobrand.sh`, and `SHA256SUMS`.
