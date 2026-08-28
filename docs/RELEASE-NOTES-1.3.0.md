# NoBrand-OneClick 1.3.0

NoBrand-OneClick 1.3.0 brings Mieru, Snell, Hysteria2 and VLESS/Sudoku under one management surface while preserving each protocol's established runtime behavior.

## Highlights

- Removed Snell v6 after failed public-path qualification.
- Added optional Snell v5 same-port QUIC exposure.
- Added real Mihomo and sing-box client validation.
- Added real upload/download benchmark evidence.
- Preserved Mieru, Hysteria2 and VLESS/Sudoku behavior.
- Unified protocol nodes, status, Doctor, endpoint, port ownership, backup and rollback handling.

## Supported protocols

- Mieru
- Snell v5 — Stable, Recommended and Default
- Snell v4 — Compatibility
- Hysteria2
- Plain VLESS + FinalMask + Sudoku over TCP

Snell v6 is removed. It is not available from the installer, menu, CLI, runtime resolver, exporter, nodes, status, Doctor or upgrade paths.

## Snell v5 and QUIC exposure

Snell v5 can optionally expose same-port UDP for the official QUIC Proxy Mode. The default is **OFF**.

- OFF: NoBrand owns TCP only; `quic_proxy_enabled=false` and `managed_udp=false`.
- ON: NoBrand owns TCP and same-number UDP; `quic_proxy_enabled=true` and `managed_udp=true`.

Some official Snell v5 runtimes may bind an auxiliary same-port UDP socket even when NoBrand public QUIC ownership is OFF. That socket is upstream runtime behavior and is not reported as QUIC Proxy Mode enabled.

Server exposure is not the same as client QUIC wire verification. Mihomo's official QUIC wire remains **NOT VERIFIED**. sing-box's official Snell v5 QUIC Proxy Mode remains **CLIENT_UNSUPPORTED**. Ordinary Snell traffic passing while exposure is ON is not described as QUIC E2E verification.

## Client compatibility

| Protocol | Mihomo | sing-box |
|---|---|---|
| Mieru | Tested | Unsupported |
| Snell v4 | Tested | Tested |
| Snell v5, QUIC OFF | Tested | Tested |
| Hysteria2 | Tested | Tested |
| VLESS/Sudoku | Unsupported | Unsupported |

The reference clients are official Mieru for Mieru and Xray-core for VLESS/Sudoku.

## Upgrade notes

The 1.3.0 upgrade path recognizes historical Snell v6 state only for strict, identity-matched cleanup. It removes only matching historical service, state, config, TCP ownership and independent runtime data. Identity mismatches fail closed. Migration does not infer or remove same-number UDP ownership and cannot delete an unrelated UDP rule.

Legacy Snell v4/v5 state without QUIC fields is normalized to explicit false values without inferring user intent from an upstream runtime socket.

The historical annotated `v1.2.0` tag remains unchanged; 1.3.0 is published under a new `v1.3.0` tag.

## Port and endpoint contracts

- The default-route IPv4 tail-base port `xx00` is reserved for outer SSH or management mapping.
- Automatic proxy allocations use `xx01` through `xx99`.
- Real Endpoint and Display Endpoint are separate. Changing the client-facing display IP or port does not change the real server listener, service, configuration or firewall ownership.

## Validation and benchmark scope

The release includes real IPLC and independent Debian-client evidence using Mihomo, sing-box, official Mieru, Xray-core and official Surge Snell runtimes. Product defaults remain Snell v5 with QUIC exposure OFF and Mihomo as the recommended default client. The most complete conservative lab pairing was Snell v4 with sing-box, including a 137.866 Mbps download median and 53.547 Mbps upload median in that specific lab.

These figures are lab results, not guaranteed speeds or an all-protocol ranking. Some later download runs were blocked by Cloudflare HTTP 429, Mieru encountered a TLS EOF condition, and certain Snell/client combinations showed cold-start sensitivity. The reports preserve `FAIL`, `NOT VERIFIED`, `CLIENT_UNSUPPORTED` and `ENVIRONMENT BLOCKED` outcomes without promoting them to PASS.

## Compatibility and licensing

The Mieru compatibility entry points `install-mita` and `mita` remain available. No third-party runtime binary, client bundle, packet capture or credential is included in the repository or release assets.

NoBrand-OneClick is distributed under GPL-3.0. Upstream attribution and component notices are recorded in `THIRD_PARTY_NOTICES.md`.
