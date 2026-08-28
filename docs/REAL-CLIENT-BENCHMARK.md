# NoBrand-OneClick 1.3.0 Real Client Benchmark

Validation date: 2026-08-28 (Asia/Shanghai) / 2026-08-27 UTC
Server: IPLC Debian guest
Client: independent Debian host
Forced public entry: `<PUBLIC_ENTRY_IP>`
Result vocabulary: `PASS`, `FAIL`, `CLIENT_UNSUPPORTED`, `NOT VERIFIED`, `ENVIRONMENT BLOCKED`

This report is a credential-free summary. Raw configs, client logs, curl CSVs, packet captures and process samples remain mode `0600`/`0700` under `<LAB_ROOT>`; no secret values, binaries, PCAPs or client bundles are committed to the repository.

Every tested node followed the same provenance chain:

```text
NoBrand authoritative server state
  → NoBrand exporter
  → unmodified IPLC → local ignored lab directory → Debian transfer
  → SHA-256 equality check
  → official client config check
  → real client process and forced local SOCKS/mixed listener
  → public entry packet capture
  → HTTPS / download / upload
```

No proxy or benchmark used `<SSH_PORT>`. Localhost, the IPLC guest address and private addresses were never accepted as a public qualification PASS.

## A. Snell v6 decision

```text
SNELL_V6_FINAL_TEST=FAIL
SNELL_V6_DECISION=REMOVE
```

The single permitted final qualification used the current Surge v6 server, official sing-box 1.14.0-rc.1, a real NoBrand 1.1.0 exporter document and public entry `<PUBLIC_ENTRY_IP>:<LEGACY_SNELL_V6_PORT>`.

| Check | Result |
|---|---:|
| HTTPS | 3/20 (`FAIL`) |
| Download | `FAIL` |
| Upload | `FAIL` |
| Debian public-entry capture | 412 packets |
| IPLC public-entry capture | 372 packets |
| IPLC client→server payload packets | 38 |
| IPLC server→client payload packets | 20 |

The instance `<LEGACY_SNELL_V6_INSTANCE>`, its exact TCP ownership, config, state, service and independent v6 runtime/metadata were removed. Product CLI/menu/resolver/download/service/config/state/export/Doctor/nodes/backup/restore/upgrade paths now reject v6. The remaining v6 references are limited to exact upgrade migration, negative tests and historical release evidence.

## B. Snell v5 QUIC exposure

The official v5 runtime binds same-number TCP and UDP in one process and exposes no server config field such as `quic=true`. NoBrand therefore implements a server-exposure choice, not a fabricated protocol setting.

| State | Canonical path | TCP ownership | UDP ownership | Local runtime UDP socket | Config/service/PSK |
|---|---|---|---|---|---|
| QUIC OFF (default) | TCP | On | Off | May remain; INFO only when same PID | Unchanged |
| QUIC ON | TCP plus opt-in public UDP exposure | On | On, same number | Required; must have same PID as TCP/service | Unchanged |

The real OFF→ON→OFF sequence passed all state, firewall and listener checks. The ON and OFF toggles did not change the service PID, server-config SHA-256 or PSK SHA-256 and did not restart the service. A later explicit recovery-test restart changed only the PID; QUIC state and same-process listeners persisted.

Final deployed state is QUIC OFF: `quic_proxy_enabled=false`, `managed_udp=false`, `TCP/<SNELL_V5_PORT>` owned and `UDP/<SNELL_V5_PORT>` not NoBrand-owned. The official process still has a local same-process UDP socket on that port; that is not public ownership and not QUIC E2E evidence.

## C. Client compatibility

Client versions and official binary hashes:

| Client | Version | Official binary SHA-256 |
|---|---|---|
| Mihomo | 1.19.30, amd64-compatible | `8ad44e28fe72be4640254b96741b677f4074991b99186cc4486a1c28ded02b1a` |
| sing-box | 1.14.0-rc.1 | `dc4464152b4aa70907d96486953fafbc16ab06e6a4265dbc56e2acb2830c0336` |
| Mieru reference | 3.35.0 | Official package |
| Xray reference | 26.3.27 | `8255dd939c34cf966cc91517b6324dd3c8d0bcf49ffac8beca049a38c46845ed` |

The normal Mihomo amd64 asset requires x86-64-v3 and could not start on the Debian CPU. The `amd64-compatible` asset from the same official 1.19.30 release was used. This is CPU/asset compatibility, not a protocol result.

| Protocol / mode | Mihomo | sing-box | Reason |
|---|---|---|---|
| Mieru | Supported / Tested | `CLIENT_UNSUPPORTED` | Mihomo implements Mieru; sing-box does not |
| Snell v4 | Supported / Tested | Supported / Tested | Both official configs parsed and ran |
| Snell v5, QUIC OFF | Supported / Tested | Supported / Tested | sing-box uses upstream v4-compatible wire expression |
| Snell v5 official QUIC wire | `NOT VERIFIED` | `CLIENT_UNSUPPORTED` | Mihomo ordinary UDP is not proof of official QUIC; sing-box explicitly lacks the mode |
| Hysteria2 | Supported / Tested | Supported / Tested | Both NoBrand exports parsed and ran |
| VLESS/FinalMask/Sudoku | `CLIENT_UNSUPPORTED` | `CLIENT_UNSUPPORTED` | Neither core implements the exact FinalMask/Sudoku structure |

Unsupported combinations were not converted to ordinary VLESS, hand-written Mieru or another approximate protocol.

## D. Real-user connectivity and restart

All server fields were `<PUBLIC_ENTRY_IP>`; every client used an isolated `<LOCAL_CLIENT_PORT_RANGE>` listener. Main configs used `MATCH → current node` or the equivalent route final. `api.ipify.org` could not provide a reliable direct/proxy comparison, so `egress_diff=unknown`; client route logs and public-entry captures prove the selected proxy path, with no DIRECT fallback.

### QUIC OFF / normal five-protocol deployment

| Protocol | Mode | Core | Config source | HTTPS | Public-entry packets | Result |
|---|---|---|---|---:|---:|---|
| Mieru | TCP | Mihomo | NoBrand exporter | 20/20 | 648 | `PASS` |
| Snell v4 | TCP | Mihomo | NoBrand exporter | 20/20 | 560 | `PASS` |
| Snell v4 | TCP | sing-box | NoBrand exporter | 20/20 | 608 | `PASS` |
| Snell v5 | QUIC OFF | Mihomo | NoBrand exporter | 20/20 | 548 | `PASS` |
| Snell v5 | QUIC OFF | sing-box | NoBrand exporter | 20/20 | 580 | `PASS` after exact server restart |
| Hysteria2 | UDP | Mihomo | NoBrand exporter | 20/20 | 424 | `PASS` |
| Hysteria2 | UDP | sing-box | NoBrand exporter | 20/20 | 521 | `PASS` |

The Snell v5/sing-box raw history is intentionally retained: initial cold start 19/20, second run after warm-up 18/20, and 20/20 after exact server restart. Failures were connect timeouts, and logs still showed the selected `<SNELL_V5_INSTANCE>` outbound, never DIRECT.

### QUIC ON server exposure

| Protocol | Mode | Core | Standard client path | HTTPS | Public packets | Official QUIC wire |
|---|---|---|---|---:|---:|---|
| Snell v5 | QUIC ON | Mihomo | `PASS` | 20/20 | 558 | `NOT VERIFIED` |
| Snell v5 | QUIC ON | sing-box | `FAIL` | final 19/20 | 601 | `CLIENT_UNSUPPORTED` |

These rows test the standard Snell TCP-compatible path while server UDP exposure is ON. They are not QUIC Proxy E2E results. The sing-box bounded history was 18/20 before a server restart, 19/20 immediately after it and 19/20 on the final client-only restart; testing stopped at that bound.

### Reference clients

| Protocol | Role | Core | Config validation | HTTPS | Public packets | Result |
|---|---|---|---|---:|---:|---|
| Mieru | REFERENCE CLIENT | Mieru 3.35.0 | `mieru apply config` | 20/20 | 514 | `PASS` |
| VLESS/Sudoku | REFERENCE CLIENT | Xray 26.3.27 | `xray run -test` | 20/20 | 556 | `PASS` |

### Service and client restart recovery

Each protocol service was precisely restarted. Main PID changed, required listener returned and config/semantic-state hashes remained unchanged. Each client then ran 5 HTTPS requests, was itself stopped/restarted, ran another 5, and attempted 64 MiB down/up.

| Protocol | Core | First start | Client restart | Connectivity | 64 MiB download | 64 MiB upload |
|---|---|---:|---:|---|---|---:|
| Mieru | Mihomo | 5/5 | 5/5 | `PASS` | `ENVIRONMENT BLOCKED` (429) | 56.688 Mbps |
| Snell v4 | Mihomo | 3/5 | 5/5 | `FAIL` | `ENVIRONMENT BLOCKED` (429) | 56.630 Mbps |
| Snell v4 | sing-box | 5/5 | 5/5 | `PASS` | `ENVIRONMENT BLOCKED` (429) | 56.849 Mbps |
| Snell v5 OFF | Mihomo | 5/5 | 5/5 | `PASS` | `ENVIRONMENT BLOCKED` (429) | 56.691 Mbps |
| Snell v5 OFF | sing-box | 5/5 | 5/5 | `PASS` | `ENVIRONMENT BLOCKED` (429) | 57.048 Mbps |
| Hysteria2 | Mihomo | 5/5 | 5/5 | `PASS` | `ENVIRONMENT BLOCKED` (429) | 56.725 Mbps |
| Hysteria2 | sing-box | 5/5 | 5/5 | `PASS` | `ENVIRONMENT BLOCKED` (429) | 56.474 Mbps |
| Mieru | Mieru reference | 5/5 | 5/5 | `PASS` | `ENVIRONMENT BLOCKED` (429) | 54.978 Mbps |
| VLESS/Sudoku | Xray reference | 5/5 | 5/5 | `PASS` | `ENVIRONMENT BLOCKED` (429) | 12.738 Mbps |

The Snell v4/Mihomo 3/5 cold start remains `FAIL`; the subsequent 5/5 client restart does not overwrite it.

## E. 256 MiB throughput

The requested IPLC loopback and private guest benchmark targets were rejected by the deployed Mieru policy. Temporary public HTTP/TLS targets completed TCP handshake but received no client payload. The bounded fallback was `https://speed.cloudflare.com`, forced through SOCKS with `Accept-Encoding: identity`, unique query tokens and serial execution.

Cloudflare rejected a single 256 MiB download with HTTP 403, so each scored download became four sequential 64 MiB pieces. Later the endpoint rate-limited the IPLC egress with HTTP 429. Uploads continued to accept a complete 256 MiB body. Results below preserve those endpoint failures instead of inferring protocol failure.

Values are decimal `MB/s / Mbps`; medians use successful complete runs only and are not promoted to PASS unless all 3/3 completed.

| Protocol | Mode | Core | Download run 1 | Run 2 | Run 3 | Download median | Upload run 1 | Run 2 | Run 3 | Upload median | Classification |
|---|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---|
| Mieru | TCP | Mihomo | 3.624 / 28.994 | FAIL | FAIL | 3.624 / 28.994 | 5.010 / 40.080 | 6.762 / 54.096 | 6.505 / 52.038 | 6.505 / 52.038 | `FAIL` (TLS EOF on fallback) |
| Snell v4 | TCP | Mihomo | 17.421 / 139.372 | 16.990 / 135.917 | 16.856 / 134.851 | 16.990 / 135.917 | 6.740 / 53.924 | 6.621 / 52.967 | 6.250 / 50.000 | 6.621 / 52.967 | `PASS` |
| Snell v4 | TCP | sing-box | 17.233 / 137.866 | 17.533 / 140.265 | 17.066 / 136.531 | 17.233 / 137.866 | 6.640 / 53.116 | 6.769 / 54.151 | 6.693 / 53.547 | 6.693 / 53.547 | `PASS` |
| Snell v5 | QUIC OFF | Mihomo | 17.345 / 138.760 | HTTP 429 | HTTP 429 | 17.345 / 138.760 | 6.744 / 53.950 | 6.749 / 53.989 | 6.777 / 54.215 | 6.749 / 53.989 | `ENVIRONMENT BLOCKED` |
| Snell v5 | QUIC OFF | sing-box | HTTP 429 | HTTP 429 | HTTP 429 | N/A | 6.757 / 54.053 | 6.778 / 54.223 | 6.671 / 53.365 | 6.757 / 54.053 | `ENVIRONMENT BLOCKED` |
| Hysteria2 | UDP | Mihomo | HTTP 429 | HTTP 429 | HTTP 429 | N/A | 6.791 / 54.328 | 6.703 / 53.623 | 6.720 / 53.757 | 6.720 / 53.757 | `ENVIRONMENT BLOCKED` |
| Hysteria2 | UDP | sing-box | HTTP 429 | HTTP 429 | HTTP 429 | N/A | 6.736 / 53.887 | 6.725 / 53.797 | 6.778 / 54.224 | 6.736 / 53.887 | `ENVIRONMENT BLOCKED` |
| Snell v5 | QUIC ON | Mihomo | HTTP 429 | HTTP 429 | HTTP 429 | N/A | 6.749 / 53.991 | 6.721 / 53.766 | 6.770 / 54.164 | 6.749 / 53.991 | `ENVIRONMENT BLOCKED` |
| Snell v5 | QUIC ON | sing-box | N/A | N/A | N/A | N/A | N/A | N/A | N/A | N/A | `FAIL` at 20/20 gate |

The QUIC ON sing-box performance block was not run because its required connectivity gate failed; the classification is `FAIL`, not `CLIENT_UNSUPPORTED`, for the ordinary TCP-compatible path. Official QUIC wire remains `CLIENT_UNSUPPORTED` separately.

## F. Raw baseline and efficiency

The temporary public iperf3 port was `<BENCHMARK_PORT>/TCP`, marked `LAB_THROUGHPUT_BASELINE`, and was precisely removed after the test. `<SSH_PORT>` was never used.

| Direction | Run 1 | Run 2 | Run 3 | Median |
|---|---:|---:|---:|---:|
| Debian → IPLC (upload) | 52.223 Mbps | 53.209 Mbps | 54.667 Mbps | 53.209 Mbps |
| IPLC → Debian (download) | 152.979 Mbps | 154.240 Mbps | 149.997 Mbps | 152.979 Mbps |

Only complete 3/3 proxy blocks enter efficiency comparison:

| Protocol / core | Download efficiency | Upload efficiency |
|---|---:|---:|
| Snell v4 / Mihomo | 88.85% | 99.55% |
| Snell v4 / sing-box | 90.12% | 100.64% (normal measurement variance) |

No “fastest protocol” is declared from a partial, blocked or failed block.

## G. QUIC truth status

```text
Snell v5 QUIC server exposure: PASS
Snell v5 QUIC Proxy E2E with Mihomo: NOT VERIFIED
Snell v5 QUIC Proxy E2E with sing-box: CLIENT_UNSUPPORTED
```

Mihomo 20/20 with UDP exposure ON proves only its standard Snell path survived the server setting. It does not prove that Mihomo sent official Snell v5 QUIC wire traffic.

## H. Bugs and regressions

| ID | Severity | Symptom | Root cause | Fix | Regression / real-client result |
|---|---|---|---|---|---|
| NB-120-01 | High | A successful Snell install could enter rollback | Listener/service acceptance condition inverted success semantics | Corrected acceptance flow and rollback boundary | Unit/runtime install acceptance and real v4/v5 listeners PASS |
| NB-120-02 | High | Snell v6 control plane existed despite unusable public data plane | Experimental runtime could handshake but was not reliable on the forced path | Removed v6 product surface; retained exact migration only | Final v6 test 3/20; all removed-path negative tests PASS |
| NB-120-03 | High | Historical v4/v5 state lacked explicit QUIC choice | Old schema predated managed UDP | Atomic boolean normalization; invalid/inconsistent state fails closed | Migration and rollback tests PASS |
| NB-120-04 | High | A broad v6 cleanup could risk same-number UDP owned by another protocol | Historical v6 was TCP-only; UDP ownership cannot be inferred from a socket/rule | Exact filename/instance identity plus TCP-only cleanup | Identity mismatch and unrelated UDP/HY2 regressions PASS |
| NB-120-05 | Medium | Real client exporters could hide/continue after a failed generation step | Return status was not consistently propagated through presentation paths | Propagated failure and corrected upstream-specific fields | Mihomo/sing-box config check and launch round trips PASS |
| LAB-120-01 | Medium | Initial throughput PCAPs consumed several GiB | Full snaplen capture had no packet bound | Preserved SHA/first-1000 sample, removed only verified giant files, then capped to snaplen 96 / 1,000 packets | Disk returned to 25%; no active lab capture remains |
| LAB-120-02 | Low | One v5/Mihomo client peak row used the old summary calculation | Peak field was derived before the harness correction | Recalculated from retained CSV without changing raw evidence | Final value 0.3% / 45088 KiB |

Observed upstream/path limitations are not silently called fixed: v5/sing-box cold-start sensitivity, QUIC ON/sing-box 19/20, Snell v4/Mihomo restart cold-start 3/5, Mieru fallback TLS EOF and Cloudflare 429 remain in the report.

## Resource observations

Server CPU uses `ps %cpu`, a lifetime-average sample rather than an instantaneous peak; RSS is directly usable.

| Server protocol | Samples | Max sampled CPU | Max RSS |
|---|---:|---:|---:|
| Mieru | 2486 | 0.1% | 27048 KiB |
| Snell v4 | 2486 | 0.0% | 15876 KiB |
| Snell v5 | 2486 | 0.8% | 16108 KiB |
| Hysteria2 | 2486 | 0.8% | 50360 KiB |
| VLESS/Sudoku | 2486 | 0.0% | 21860 KiB |

| Client / block | Peak CPU | Peak RSS |
|---|---:|---:|
| Mieru / Mihomo | 6.8% | 60640 KiB |
| Snell v4 / Mihomo | 39.5% | 57352 KiB |
| Snell v4 / sing-box | 36.4% | 65184 KiB |
| Snell v5 OFF / Mihomo | 0.3% | 45088 KiB |
| Snell v5 OFF / sing-box | 5.9% | 64560 KiB |
| Hysteria2 / Mihomo | 63.5% | 59660 KiB |
| Hysteria2 / sing-box | 79.3% | 71772 KiB |
| Snell v5 QUIC ON / Mihomo | 9.5% | 58696 KiB |

## I. Final supported protocols

```text
SUPPORTED_PROTOCOLS:
Mieru
Snell v4
Snell v5
Hysteria2
VLESS/Sudoku
```

Snell v5 remains Recommended/Default with QUIC OFF. Snell v4 remains Compatibility.

## J. Final public nodes

| Protocol | Public Display Endpoint | Transport |
|---|---|---|
| Mieru | `<PUBLIC_ENTRY_IP>:<MIERU_PORT>` | TCP |
| Snell v5 | `<PUBLIC_ENTRY_IP>:<SNELL_V5_PORT>` | TCP; QUIC exposure final OFF |
| Snell v4 | `<PUBLIC_ENTRY_IP>:<SNELL_V4_PORT>` | TCP |
| Hysteria2 | `<PUBLIC_ENTRY_IP>:<HY2_PORT>` | UDP |
| VLESS/Sudoku | `<PUBLIC_ENTRY_IP>:<VLESS_PORT>` | TCP |

Credentials are intentionally omitted.

## K. Final IPLC listeners

```text
<SSH_PORT> = SSH (outer public entry; permanently protected)
<MIERU_PORT>/TCP = Mieru
<SNELL_V5_PORT>/TCP = Snell v5
<SNELL_V5_PORT>/UDP = local official same-process auxiliary socket; NoBrand ownership OFF
<SNELL_V4_PORT>/TCP = Snell v4
<HY2_PORT>/UDP = Hysteria2
<VLESS_PORT>/TCP = VLESS/Sudoku
```

Final audit passed with no benchmark listener/firewall residue, no proxy ownership on `<SSH_PORT>`, no v6 state/config/runtime, and public SSH connectivity PASS at `<PUBLIC_ENTRY_IP>:<SSH_PORT>`.

## L. Release readiness and recommendation

```text
READY WITH KNOWN LIMITATIONS
```

The server product, migration, default QUIC OFF ownership and supported exporter/config paths are release-ready. The qualification is not plain READY because:

- the fallback download endpoint began returning HTTP 429, leaving later protocols without a complete 3-run download comparison;
- Mieru had two fallback TLS EOF download failures;
- Snell v5/sing-box showed cold-start sensitivity, and QUIC ON standard path finished 19/20;
- Snell v4/Mihomo server-restart cold start was 3/5 before client restart recovered to 5/5.

For this specific lab, the most conservative fully measured client pairing is **Snell v4 + sing-box**: 20/20 connectivity, complete 3/3 down/up, 90.12% raw-download efficiency, and 5/5 before/after client restart. This does not change the product default: new Snell installs remain **v5 + QUIC OFF**, with Mihomo as the better-tested default client for that mode. Users requiring official Snell v5 QUIC wire need a client that explicitly implements it; the two mandated Debian cores do not provide verified E2E coverage.

The final four generated installers are byte-identical, 575980 bytes each, with SHA-256 `49f2c77ce11a66fb3bf1a5c8cd722b340717decedeeb57d04d66e7c5207ea9b0`. The same artifact is installed in all four IPLC manager entry paths.
