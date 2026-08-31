# Port Forward Reference Audit — NoBrand-OneClick 3.1

Status: development reference; not a release claim.

NoBrand-OneClick 3.1 implements Port Forward as a NoBrand Common Network
Feature. It does not install or embed realm-xwPF, does not create a `pf`
command, and does not use `/etc/realm` as authority. No realm-xwPF source code
is copied into NoBrand.

## Audited sources

- realm-xwPF: `zywe03/realm-xwPF`, commit
  `0fa50a98ac4d37a73db93a9281d2563b359b2f88` (2026-08-30 audit).
  The required `README.md`, `xwPF.sh`, `lib/core.sh`, `lib/rules.sh`,
  `lib/server.sh`, `lib/realm.sh`, and `lib/ui.sh` were reviewed. The project
  is MIT licensed, copyright 2025 zywe.
- Realm authority: `zhboner/realm` official stable release `v2.9.6`, commit
  `7e9f44c4b6414079fdd7ed27eea155066df80dd9`, published 2026-08-30.
  Realm is MIT licensed, copyright 2020 zhboner.
- Realm release authority:
  <https://github.com/zhboner/realm/releases/tag/v2.9.6>
- Realm configuration authority:
  <https://github.com/zhboner/realm/blob/v2.9.6/readme.md>

The official `v2.9.6` release is neither draft nor prerelease. Its release
notes describe a load-balancer change and new glibc 2.28 assets. NoBrand uses
only official `zhboner/realm` Release assets and verifies the GitHub-provided
SHA-256 digest before installation.

| Official Linux asset | SHA-256 |
|---|---|
| `realm-x86_64-unknown-linux-gnu.tar.gz` | `b9efc8ccbab5c9f0602ab5ba0a2e00311e7b773944533a8373c00811fb6a1a6b` |
| `realm-x86_64-unknown-linux-musl.tar.gz` | `b1cc335547bea8bb2a88178bef12ec7f2363e36200e7ea1d4e1e67627929bf65` |
| `realm-aarch64-unknown-linux-gnu.tar.gz` | `4b6c059df67a3161369df3133e5ea9e4bd266185c634ccc8990cd5bb8d271786` |
| `realm-aarch64-unknown-linux-musl.tar.gz` | `f4c0318dd86854da483dcb7645b4f39cae2cc3f91c688fef969d53220b949488` |

## realm-xwPF feature audit

| Feature | realm-xwPF behavior | NoBrand 3.1 decision | Implementation status | Reason |
|---|---|---|---|---|
| Runtime management | Downloads an official Realm archive to `/usr/local/bin/realm`; one shared daemon | Use the official archive only, but install to NoBrand's private runtime path and record version/channel/digest ownership | Implemented | Preserve external Realm and fit the Common Binary Manager |
| Rule authority | Shell-sourced `rule-N.conf` files under `/etc/realm/rules` plus `manager.conf` | One schema-v3 NoBrand JSON state under the NoBrand state root | Implemented | Avoid executable state and a second authority |
| Rule CRUD | Interactive add/edit/delete/enable/disable with regenerated config | Provide CLI and menu CRUD with candidate validation and rollback | Implemented | Useful, mature interaction model |
| Notes | Per-rule `RULE_NOTE` | Per-rule `name` and `note` | Implemented | Improves operator identification |
| Multiple endpoints | Coalesces enabled rules into one Realm config and one daemon | One generated NoBrand Realm config and one daemon for every enabled Realm rule | Implemented | Avoid one process per rule |
| TCP / UDP | Global Realm network defaults enable TCP and UDP | Generate endpoint-level `network.no_tcp` and `network.use_udp` so TCP, UDP, and BOTH are exact per rule | Implemented | Prevent one rule from changing another rule's transport ownership |
| Domain remote | Passes a domain to Realm | Pass the domain unchanged to Realm; never pin a one-time DNS answer | Implemented | Realm is the DNS/runtime authority |
| Listen IP | IPv4, IPv6-like values, or interface-shaped input | Support Realm IPv4/IPv6 literals; nftables remains IPv4-only; keep interface separate | Implemented for Realm; nftables IPv6 intentionally unsupported | Avoid ambiguous IP/interface fields |
| Outgoing IP | Maps an address to Realm `through` | Support a validated optional outgoing IP/address | Implemented advanced | Official endpoint field |
| Outgoing interface | Maps a device to Realm `interface` | Support a validated optional outgoing interface | Implemented advanced | Official endpoint field |
| Listen interface | Maps a device to Realm `listen_interface` | Support a validated optional listen interface | Implemented advanced | Official endpoint field |
| Proxy Protocol | Per-rule send/accept combinations for v1/v2 | Keep send and accept separate; OFF by default; validate version 1 or 2 | Implemented advanced | Official network fields; avoids a misleading single switch |
| DNS | Relies on Realm defaults unless external configuration changes it | System/default by default; optional official `dns` fields for custom resolvers | Implemented advanced | Official schema, no pre-resolution |
| Raw / WS / TLS / WSS transport | Builds Realm transport strings for relay/exit roles | Raw is default; expose validated official transport strings and never auto-deploy a remote peer | Implemented advanced; non-raw peer deployment is intentionally omitted | Single-end forwarding remains the core mode |
| Single-end relay | Common relay mode | Full 3.1 core support | Implemented | Release scope |
| Dual-Realm tunnel | Interactive relay/exit pairing model | Do not auto-deploy a remote Realm; document as outside 3.1 core scope | Intentionally omitted from core | Requires coordinated two-host lifecycle and credentials |
| Load balancing | Groups same-listen-port targets into `extra_remotes` with `roundrobin` or `iphash` | Support official multiple remotes, algorithms, and weights only when represented explicitly in NoBrand state | Implemented advanced | Official Realm capability, with full transaction rollback |
| Weights | Emits Realm `balance` weight list | Validate positive integer weights and target count | Implemented advanced | Official Realm capability |
| Automatic failover | External health script, state file, service, and timer rewrite active targets | Do not add it in 3.1 | Intentionally omitted | It is not native basic forwarding and adds another daemon/timer |
| MPTCP | Manages global sysctls and `ip mptcp endpoint` state | Do not manage MPTCP in 3.1 Forward | Intentionally omitted | Global network mutation is outside the basic Forward release gate |
| Traffic dog | Downloads a separate nftables/tc/notification manager | Do not add it in 3.1 | Intentionally omitted | Quotas, Telegram, and monitoring need a separate ownership design |
| Config export | Archives rule files, manager state, health state, and MPTCP state | Export a versioned, validated NoBrand JSON document | Implemented | Portable without adopting xwPF state |
| Config import | Replaces the xwPF rule directory from an archive; optional OCR downloader | Import only validated NoBrand JSON initially; unknown fields fail closed | Implemented | Avoid executing shell state or silently dropping semantics |
| Raw Realm import | Downloads an OCR/import helper | Evaluate separately; never treat an external config as authority | Intentionally omitted from the initial core unless a strict parser is complete | The release gate does not require unsafe or lossy import |
| Service management | One systemd/OpenRC `realm` service | One namespaced `nobrand-realm` service; generated config belongs only to NoBrand | Implemented | Isolation from external Realm |
| Restart behavior | Rewrites active config then restarts | Validate with temporary free listeners while the old service remains active, atomically replace, restart, prove listeners, and roll back on failure | Implemented | Active old config survives candidate failure |
| Port conflict detection | Allows a port already owned by any `realm` process and can let the operator continue past other conflicts | Use the Common transport-aware registry plus listener/PID ownership; never waive an external conflict | Implemented | Same numeric TCP/UDP ports may differ, owners may not |
| Rollback | Limited; several edit/import paths mutate state before restart | Snapshot state/config/runtime effects and restore the old active data plane on failure | Implemented | NoBrand transactional contract |
| Multi-distro | Debian/Ubuntu, Alpine, CentOS/RHEL; systemd/OpenRC | Debian, Ubuntu, Rocky, Alpine with NoBrand's existing platform abstraction | Implemented | Existing product matrix |
| Full uninstall | Stops by process name and removes broad Realm paths and matching temporary/log files | Remove exact NoBrand-owned service/config/runtime/state only | Implemented | External Realm and unrelated firewall/network state survive |

## Official Realm v2.9.6 decisions

The official standard build includes Proxy Protocol, load balancing,
WS/TLS/WSS transport, batched UDP, and the multi-threaded runtime. Realm has
no documented standalone config-check or dry-run command. A safe NoBrand
candidate therefore needs all of the following:

1. structural and type validation by NoBrand;
2. replacement of each enabled Realm listener by a validated temporary free port in a probe-only state;
3. a short-lived official Realm process startup probe while the current production service remains active;
4. production config replacement only after the probe succeeds;
5. service/listener acceptance with automatic restoration of the previous
   config and state on failure.

Official endpoint semantics used by NoBrand:

- `listen`: IPv4 or IPv6 socket address;
- `remote`: IPv4, IPv6, or domain socket address;
- `extra_remotes` and `balance`: optional official load balancing;
- `through`: optional outgoing bind address;
- `interface` and `listen_interface`: outgoing/incoming device binding;
- endpoint `network.no_tcp` / `network.use_udp`: exact TCP, UDP, or BOTH mode;
- endpoint `network.send_proxy`, `send_proxy_version`, `accept_proxy`, and
  `accept_proxy_timeout`: explicit Proxy Protocol behavior;
- global `dns`: official resolver mode/protocol/nameserver/cache controls;
- `listen_transport` / `remote_transport`: official transport strings.

The default NoBrand Realm rule remains a raw single-end relay with system DNS,
no Proxy Protocol, no forced outgoing address/interface, and no load balance.

## NoBrand dual-backend boundary

| Concern | nftables | Realm |
|---|---|---|
| Data plane | Kernel DNAT plus optional MASQUERADE | Userspace L4 relay |
| 3.1 target scope | IPv4 literal | IPv4, validated IPv6, or domain |
| Protocol | TCP, UDP, BOTH | TCP, UDP, BOTH |
| Source address | MASQUERADE default; preserve-source advanced | Realm connection/association semantics |
| Runtime process | None | One NoBrand-owned Realm daemon |
| DNS | Not used for target | Realm system/custom DNS |
| Advanced routing | Preserve source | Through IP, interfaces, Proxy Protocol, validated transport/load balance |
| State authority | NoBrand state | NoBrand state |
| Runtime artifact | NoBrand-owned nft table/chains/rules | Generated Realm config |
| Removal boundary | Exact NoBrand table and owned sysctl fragment/state | Exact NoBrand service/config/runtime/state |

## Safety findings carried into implementation

- Never run `nft flush ruleset`, `iptables -F`, or restore a whole-machine
  firewall snapshot.
- nftables generation owns one clearly named NoBrand table and regenerates
  only that table from NoBrand state in one nftables transaction.
- `net.ipv4.ip_forward` is reference-counted from enabled nftables rules.
  Original/effective state and NoBrand fragment ownership are recorded; the
  last rule may restore only a value NoBrand changed.
- Realm config changes do not restart any proxy protocol or reload `sshd`.
- The `xx00` tail-base reservation is rejected through the existing Common
  Port Registry for both backends and both transports.
- Display Endpoint changes are metadata-only and must not regenerate an nft
  rule, restart Realm, or alter the listener/target.
