# NoBrand-OneClick 3.0.0

NoBrand-OneClick 3.0.0 is a clean-break release built around one installer, one canonical manager, and one schema-v3 ownership model. It does not automatically migrate legacy users or state.

## Highlights

- One release installer: `install-nobrand.sh`
- One canonical manager: `nobrand`, with `nb` as its short alias
- Full Mieru feature and parameter parity, including Profiles, defaults, multi-user instances, quota, tc/rate limits, Display Endpoints, diagnostics, backup, and client exports
- Snell v5 as the stable, recommended default, with optional official QUIC server exposure; Snell v4 remains available for compatibility
- Hysteria2 over Xray-core
- Plain VLESS with FinalMask/Sudoku over TCP and VLESS Encryption disabled
- Unified nodes, Display Endpoint handling, backup/restore, ownership tracking, and project-wide uninstall
- Clean schema-v3 state with no automatic legacy-user or legacy-state migration

Snell v1, v2, v3, and v6 are unsupported and have no hidden installation path. The former `install-mita.sh` and NoBrand management wrappers named `mita` have been removed; the genuine upstream Mieru runtime continues to use its official `mita` binary name internally.

## Client compatibility

| Protocol | Verified clients | Unsupported or unverified combinations |
|---|---|---|
| Mieru | Mihomo; official Mieru reference client | sing-box unsupported |
| Snell v4 | Mihomo; sing-box | — |
| Snell v5 with public QUIC exposure OFF | Mihomo; sing-box | Official QUIC-wire Linux E2E not verified |
| Hysteria2 | Mihomo; sing-box | — |
| VLESS FinalMask/Sudoku | Xray-core reference client | Mihomo and sing-box unsupported |

Official Snell v5 QUIC server exposure is supported. This release does not claim verified Mihomo official QUIC-wire interoperability, and sing-box does not support official Snell v5 QUIC Proxy Mode.

## Breaking changes

- State and ownership now require the clean schema-v3 model.
- Legacy Mieru/NoBrand state is detected and rejected without being imported, converted, modified, or deleted.
- `install-mita.sh` and NoBrand `mita` management compatibility have been removed.
- `nobrand uninstall` now removes all resources explicitly owned by NoBrand 3.0 across Mieru, Snell, Hysteria2, VLESS/Sudoku, and common state, while preserving external resources.

## Validation

The release passed deterministic builds, syntax and ShellCheck gates, unit and runtime suites, complete Mieru parity gates, four-platform container coverage, ownership and uninstall boundaries, protocol regressions, and non-destructive real-machine health validation.

## Known limitations

1. The Linux client matrix does not provide a verified official Snell v5 QUIC-wire end-to-end implementation.
2. Mihomo and sing-box do not support VLESS FinalMask/Sudoku; Xray-core is the reference client.
3. VLESS/Sudoku showed lower upload throughput in the tested lab despite correct connectivity and data integrity.
4. Snell v5 may require a reasonable connection cadence immediately after a fresh client process starts.
