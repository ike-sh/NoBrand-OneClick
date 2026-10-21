# Public Splicore v0.3.0-rc.4 contract

Authority: [public release](https://github.com/ike-sh/Splicore/releases/tag/v0.3.0-rc.4), commit `2634ea50d19623591c5db63329a288862726db74`. No local source tree, latest or branch HEAD was used. Central executable/checksum mapping: [`runtime/splicore-release.json`](../runtime/splicore-release.json).

| Architecture | Archive | Archive SHA256 | Qualification |
|---|---|---|---|
| amd64 | splicore-v0.3.0-rc.4-linux-amd64.tar.gz | 9dd1941c817143d18ea1c892a5fc13266c1b209600576946504a9d3c98c62161 | Experimental; local runtime tested |
| arm64 | splicore-v0.3.0-rc.4-linux-arm64.tar.gz | 5b5e39bd8e6ef373ebc00e7e3a8a688ce09d0369dc2c4ecfab06ed535d948b64 | BUILD ONLY / runtime NOT CERTIFIED |

Binary name `splicore`; `version --json` must match product/version/commit/dirty=false/platform and pinned binary digest. `x86_64→amd64`, `aarch64→arm64`; absent artifact rejects. The artifact manager validates SHA256SUMS, the independently pinned archive digest, entry names/types/path safety and binary identity before atomic publication.

## Managed creation and validation

The public [CLI](https://github.com/ike-sh/Splicore/blob/v0.3.0-rc.4/docs/CLI.md) defines `validate BOOTSTRAP`, `inbound validate/plan/apply --protocol ...`, and `client plan/apply --config ... --file ... --plan ...`. NoBrand keeps a private daemon DB/control socket/key per generation; ordinary inbounds share one daemon. Native client resources use canonical UUID v4 IDs, including route rules.

## Local Tunnel Guard

Public authority: [LOCAL_TUNNEL_GUARD](https://github.com/ike-sh/Splicore/blob/v0.3.0-rc.4/docs/protocol/LOCAL_TUNNEL_GUARD.md), [VLESS](https://github.com/ike-sh/Splicore/blob/v0.3.0-rc.4/docs/protocol/VLESS.md) and tagged domain model source.

Creation uses resource `local-inbound`, kind `tunnel`, `listen`, `tunnel.target`, `tunnel.network=tcp`, and `sniffing={enabled:true,protocols:[tls],route_only:true}`. Only literal 127.0.0.1/::1 listeners are accepted. The fixed tunnel target is distinct from sniffed SNI. Network replacement installs consecutive rules: this guard ID + exact approved `sniffed_domains` → direct; this guard ID → reject.

NoBrand REALITY uses protocol CLI `vless`, security `reality`, raw TCP, flow `xtls-rprx-vision`, packet_encoding `xudp`, guard listen as REALITY target, and the private key in root `server_secret.private_key`. It creates guards, routing, then managed REALITY. Validation runs before service cutover. Health checks verify listener/target/sniffing and both exact rules.

The bounded TLS parser rejects malformed/non-TLS/missing SNI. Approved plain TLS reaches the fixed cover. Wrong REALITY credentials do not authenticate a proxy session. Authenticated VLESS traffic is ordinary proxy traffic; this is not field-level old Xray defender/private-IP routing equivalence.

## Other protocols

- HY2 uses native Hysteria transport version 2, TLS and Salamander. Gecko remains experimental/not exposed; hopping supported/not exposed; nftables range requires external host qualification and stays off.
- Mieru TCP/UDP native settings; BOTH is two managed inbounds. Traffic-pattern/low-entropy/accounting options have no NoBrand mapping and reject.
- TUIC v5 uses native TLS, UUID/password and QUIC settings.
- Native Snell server v5 maps `ClientVersion(5)` to v4 client wire in the tagged implementation; TCP/UDP work with v4 client projection. QUIC Proxy Mode is not available. Exports state server and client versions explicitly.
- Existing FinalMask/Sudoku uses its pinned Xray exception. No ordinary protocol invokes that downloader.

Old certificate, credential, service-layout and client-profile compatibility are outside the current contract. Historical rc.2/rc.3 documents and reports retain their original conclusions.
