# NoBrand-OneClick 1.3.0 Release Checklist

Status date: 2026-08-28 (Asia/Shanghai)

Checked items have direct source, automated, container, or real-machine evidence. Publishing steps that necessarily occur after the release commit are verified separately in the final release report.

## Source

- [x] Product version is `1.3.0`; identity is `NoBrand-OneClick`; author is `ike`.
- [x] `src/` remains the only source for all four generated installer names.
- [x] Protocol scope is exactly Mieru, Snell v4/v5, Hysteria2 and VLESS/FinalMask/Sudoku.
- [x] Snell v6 menu/CLI/resolver/download/config/state/service/export/Doctor/nodes/backup/restore/upgrade paths are removed.
- [x] The only production v6 recognition is exact, fail-closed 1.3.0 cleanup of historical state; tests and historical docs remain intentionally.
- [x] Snell v5 defaults QUIC OFF; ON/OFF changes state/firewall only and never rewrites config, restarts service or rotates PSK.
- [x] QUIC ON owns same-number TCP+UDP and accepts only a same-process UDP listener; QUIC OFF owns TCP only.
- [x] Legacy v4/v5 states atomically normalize to explicit boolean QUIC fields without socket inference.
- [x] Plain VLESS + FinalMask + Sudoku/TCP and `Encryption=false` contracts are unchanged.
- [x] HY2 and Mieru server behavior/profile are unchanged.

## Automated tests

- [x] Final Docker Debian 12 `bash scripts/test.sh` passes.
- [x] Final Docker Debian 12 `bash scripts/test.sh --runtime` passes.
- [x] Original Mieru `scripts/docker-smoke.sh` passes.
- [x] Debian/Ubuntu/Rocky/Alpine `scripts/compat-smoke.sh` passes.
- [x] Final `bash -n`, warning-level ShellCheck and `git diff --check` pass.
- [x] Two consecutive builds are byte-reproducible; `scripts/build.sh --check` passes.
- [x] All four generated installers are byte-identical (575980 bytes) with SHA-256 `60b9a7ed810bf7dbd061a15bf8abebc58480f02ee701be50e02b669002c5297a`.
- [x] Removed-v6 negative tests reject CLI/menu/resolver/runtime/config/state/export/nodes paths and verify exact migration boundaries.
- [x] QUIC tests cover interactive/non-interactive OFF/ON, invalid CLI, state, TCP-only/TCP+UDP ownership, toggles, rollback, endpoint, backup/restore, Doctor and nodes.
- [x] HY2 Mihomo/sing-box exporter golden tests pass.

## Real public-path validation

- [x] The one permitted final Snell v6 qualification is complete: 3/20 HTTPS, download FAIL, upload FAIL.
- [x] `SNELL_V6_FINAL_TEST=FAIL` and `SNELL_V6_DECISION=REMOVE` are final; v6 was not retested.
- [x] The IPLC v6 instance, exact TCP ownership, state/config/service and independent runtime were removed without affecting five retained protocols.
- [x] QUIC OFF→ON→OFF proves state/firewall semantics, same-process UDP, unchanged service/config/PSK during toggles and final OFF restoration.
- [x] IPLC exporter → local `<LOCAL_LAB_DIR>` → Debian SHA-256 round trip is identical and all proxy servers use `<PUBLIC_ENTRY_IP>`.
- [x] Mihomo 1.19.30 and sing-box 1.14.0-rc.1 real config checks pass for every supported generated config.
- [x] QUIC OFF public connectivity passes 20/20 for both Snell cores; historical sing-box 19/20 and 18/20 failures remain in raw evidence.
- [x] QUIC ON standard path is 20/20 on Mihomo and final 19/20 on sing-box; this is not labeled QUIC E2E.
- [x] Official Mieru 3.35.0 and Xray 26.3.27 reference clients each pass 20/20 using NoBrand exports.
- [x] Raw public baseline is 152.979 Mbps download / 53.209 Mbps upload (median of three runs).
- [x] Snell v4 completes both-core 3×256 MiB down/up matrices; fallback HTTP 429 and Mieru TLS EOF are classified honestly.
- [x] Restart recovery retains the Snell v4/Mihomo cold-start 3/5 failure; successful later client restart does not overwrite it.
- [x] No test used localhost, guest/private addresses as a public qualification PASS or used `<SSH_PORT>` as a proxy/benchmark.

## Security and cleanup

- [x] No credentials, private keys, SSH material, client bundles, PCAPs or runtime binaries are added to the release tree.
- [x] Local lab and safety-snapshot directories remain ignored.
- [x] No firewall flush, broad service deletion or change to the reference worktree / SSH helper configuration occurred.
- [x] Temporary benchmark HTTP processes/files were precisely removed after PID/cmdline validation; retained scripts/evidence are inert.
- [x] Final IPLC state has five services, v5 QUIC OFF, no v6 product files, no benchmark listener/firewall residue and public SSH/`<SSH_PORT>` PASS.

## Documentation

- [x] README describes five supported protocols, v6 removal, optional v5 same-port UDP exposure and ordinary UDP relay vs official QUIC wire.
- [x] README compatibility labels distinguish Supported/Tested, `CLIENT_UNSUPPORTED` and `NOT VERIFIED`.
- [x] `REAL-CLIENT-BENCHMARK.md` records raw baseline, individual runs, resource/restart results, failures and environment limits without secrets.
- [x] CHANGELOG includes Removed/Added/Changed/Fixed 1.3.0 entries.
- [x] Source audit records official Mihomo/sing-box/Snell evidence and client boundaries.

## Git and release

- [x] Final status/diff review contains only intended source, test, docs, CI and generated-artifact changes; ignored lab evidence is excluded.
- [x] Existing annotated `v1.2.0` is preserved locally and remotely without modification.
- [x] Local tag, remote tag and GitHub Release name `v1.3.0` were available before release work began.
- [x] Release commit content is finalized from the fully audited working tree.
- [ ] Tag `v1.3.0` created — publishing action performed after the release commit.
- [ ] Push / GitHub Release — publishing actions performed after the release commit.
- [x] Final readiness classification is `READY WITH KNOWN LIMITATIONS`.
