# Public Splicore rc.3 contract

Current authority: [v0.3.0-rc.3](https://github.com/ike-sh/Splicore/releases/tag/v0.3.0-rc.3),
commit `72166d2fcda95b943cbae584bdd59876df7d0ed8`, annotated tag
`c4e5f215d9e573f6fbe7e6de929f676cfc4f3658`.
The single machine-readable pin is [the manifest](../runtime/splicore-release.json).
No latest/main or local Splicore build is used. Approved rc.2 entries exist only
for historical upgrade/rollback; [rc.2 evidence](SPLICORE-RC2-CONTRACT.md) remains historical.

## HY2

Native managed inbound settings:

```json
{
  "tls": {
    "server_name": "probe.example",
    "certificate_file": "/private/existing/chain.pem",
    "private_key_file": "/private/existing/key.pem",
    "ca_certificate": "EXISTING CA PEM"
  },
  "stream_transport": {
    "kind": "hysteria",
    "hysteria": {
      "version": 2,
      "obfs": {"type": "salamander", "password": "EXISTING INDEPENDENT OBFUSCATION SECRET"}
    }
  }
}
```

This is the native transport field. `settings.obfs` is invalid. NoBrand keeps
plain HY2 distinct: omitting transport/obfs retains the plain path. A stored
Salamander option cannot silently become plain. Empty/missing secrets reject.
Auth is a separate `users[].password`. Salamander passwords are 1–1024 UTF-8 bytes.

| Capability | Public Core | NoBrand surface / evidence |
|---|---|---|
| Plain HY2 | Supported | Canonical intent; traffic regression |
| Salamander | Supported | Fresh install and compatible old TLS migration; unchanged old profile TCP/domain/UDP |
| Gecko | Supported, experimental | NOT EXPOSED; public validation accepts Gecko and rejects invalid sizes |
| UDP port hopping | Supported | NOT EXPOSED; public node validation of single port, fixed range, mixed randomized ports |
| Linux server port range | Supported | NOT EXPOSED; inbound validation only; never applied locally |

Native Gecko tuning: `min_packet_size`, `max_packet_size`, defaults 512/1200;
minimum >= 14, maximum >= minimum, 163 <= maximum <= 2048. Salamander forbids
these fields. Native UDP client intent uses `ports` as a string, `hop_interval`
(minimum 5 seconds), or `min_hop_interval` / `max_hop_interval` (min >= 5,
max >= min). Modes are exclusive. Single ports, ranges and mixed addressing
are supported. Server `server_port_range` requires the listener at the first
port and cannot coexist with client hopping fields.

[Upstream transport contract](https://github.com/ike-sh/Splicore/blob/72166d2fcda95b943cbae584bdd59876df7d0ed8/docs/architecture/HYSTERIA_TRANSPORT.md):
`hy2://` and `hysteria2://` preserve supported obfuscation and multiple ports.
Intervals and Gecko size tuning require native configuration; NoBrand does not
invent URI parameters. Linux server ranges require nftables and appropriate
network privileges such as CAP_NET_ADMIN. Real qualification is PENDING.

Legacy TLS is never regenerated. NoBrand's old default self-signed CA leaf
cannot satisfy rc.3's non-CA leaf requirement. A compatible fixture uses a valid
leaf/CA bundle at the existing path **before starting the old server**; the
migration preserves bytes, paths and modes. It does not prove migration of the
incompatible default. This remains an explicit implementation/contract blocker.

## REALITY / Vision

Raw TCP + REALITY with `flow: xtls-rprx-vision` is supported by the public Core.
NoBrand's actual old server and clients use that flow. The unchanged old profile
passes a native Vision control, including after restart and SIGKILL/relaunch.
It is not accepted as a migrated product graph: the public native server still
cannot map the old defender/SNI routing, private-IP denial, blocked TCP ports
and BitTorrent denial. Loopback traffic is a concrete policy counterexample.
Both ordinary fresh REALITY and migration therefore reject before core download
or service cutover. No sidecar, host firewall workaround or flow downgrade is used.

## Qualification

[Current closure report](reports/SPLICORE_SINGLE_CORE_BLOCKER_CLOSURE_REPORT.md)
contains artifact hashes, real traffic and transaction evidence. Local WSL
process checks do not certify native init systems, production clients, arm64
runtime or real nftables port-range operation.
