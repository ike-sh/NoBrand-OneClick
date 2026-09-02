# VLESS REALITY + Vision — 3.2 Release Candidate

NoBrand-OneClick 3.2.0 is an unreleased release candidate. The immutable current release remains v3.1.0. VLESS REALITY is the final planned protocol feature for 3.2; `PROTOCOL_FEATURE_FREEZE=true` remains set.

## Fixed protocol contract

The product exposes one deliberately narrow, verified combination:

```text
VLESS
+ TCP
+ REALITY
+ XTLS Vision (xtls-rprx-vision)
```

Server invariants are `network=tcp`, `security=reality`, VLESS `decryption=none`, client flow `xtls-rprx-vision`, `show=false`, `xver=0`, `minClientVer="0.0.0"`, and one generated non-empty 16-character hexadecimal short ID. Ingress enforcement changes only the Xray listen address: permissive uses `0.0.0.0`, while strict uses the selected Profile local IPv4 through Xray's native bind. It does not change the REALITY protocol contract.

This is a separate `vless-reality` product. It does not add a mode field to, migrate, rewrite, or share credentials with VLESS/Sudoku. The released Sudoku stack remains plain VLESS + TCP + FinalMask/Sudoku with `security=none`, `encryption=none`, and `decryption=none`.

XHTTP, gRPC, WebSocket, HTTPUpgrade, a separate RAW product choice, XUDP Seed, credential rotation, and other REALITY feature-matrix options are outside this phase.

## Exact Xray contract

NoBrand pins its private managed runtime to official Xray 26.3.27:

| Asset | SHA-256 |
|---|---|
| `Xray-linux-64.zip` | `23cd9af937744d97776ee35ecad4972cf4b2109d1e0fe6be9930467608f7c8ae` |
| `Xray-linux-arm64-v8a.zip` | `4d30283ae614e3057f730f67cd088a42be6fdf91f8639d82cb69e48cde80413c` |

The server uses current `target` semantics and fields `show`, `target`, `xver`, `minClientVer`, `serverNames`, `privateKey`, and `shortIds`; `minClientVer` is fixed to `0.0.0`. `dest` is not emitted, although the exact 26.3.27 loader still accepts the legacy alias. No Xray upgrade is required. `minClientVer` is server-only and is absent from the Xray, Mihomo, and sing-box client exporters and the standard URI. The Xray 26.3.27 client exporter uses `realitySettings.password` for the server X25519 public material. Standard ecosystem URIs continue to use `pbk`.

The same verified official archive supplies all three private runtime files:

```text
/usr/local/lib/nobrand-oneclick/bin/xray
/usr/local/lib/nobrand-oneclick/xray-assets/geoip.dat
/usr/local/lib/nobrand-oneclick/xray-assets/geosite.dat
```

NoBrand passes the private asset directory through `XRAY_LOCATION_ASSET` for config validation and every managed REALITY service. Binary and assets install, upgrade, rollback, and final shared-Xray removal as one owned transaction; system copies and external Xray installations are not reused or removed.

The default client fingerprint is fixed to `chrome`; `spiderX` is fixed to `/`. These values are saved once in state and do not change on export.

## Defender and anti-probe topology

Every REALITY instance has two inbounds in one Xray config and one Xray process:

```text
public VLESS/TCP/REALITY/Vision inbound
        |
        | realitySettings.target = 127.0.0.1:<defender-port>
        v
loopback dokodemo-door defender
        |
        +-- exact sniffed full:<validated-serverName> -> DIRECT fixed redirect
        |
        +-- everything else                         -> BLOCK
```

The defender port is allocated from the internal TCP range `20000-29999`, persisted in instance state, and required to be free from another defender owner, a public Common Port owner, and an OS listener. It is always bound exactly to `127.0.0.1`; it never becomes a Common Port row, Display Endpoint, firewall opening, client field, or public listener. Multiple REALITY instances receive unique defender ports and tags. Ordinary status reports only `Defender: Active|Inactive`; Doctor may inspect the internal contract.

The defender inbound uses the exact Xray 26.3.27 schema:

```json
{
  "protocol": "dokodemo-door",
  "listen": "127.0.0.1",
  "settings": {
    "address": "nobrand.invalid",
    "port": 443,
    "network": "tcp"
  },
  "sniffing": {
    "enabled": true,
    "routeOnly": true,
    "destOverride": ["tls"]
  }
}
```

`nobrand.invalid` is an internal, intentionally unresolvable dispatch sentinel—not a client hostname, advertised endpoint, camouflage target, or SNI. Directly placing the allowed target hostname in `settings.address` is unsafe for the required semantics on Xray 26.3.27: when plaintext/random input has no sniffable TLS SNI, Xray retains that original dokodemo destination, which could match the hostname allow rule and forward the probe. The sentinel makes no-SNI input unmatchable. Only an exact sniffed `full:<serverName>` rule reaches the `DIRECT` freedom outbound, whose verified `settings.redirect=<validated-target>:<target-port>` fixes the real destination. The immediately following defender-inbound catch-all rule sends every other probe to `BLOCK`.

The complete outbound and routing order is deliberate:

1. `geoip:private` → `BLOCK`.
2. TCP ports `25,135,137,138,139,445,465,587` → `BLOCK`.
3. detected `bittorrent` → `BLOCK`.
4. defender tag plus exact `full:<validated-serverName>` → `DIRECT` fixed redirect.
5. defender tag catch-all → `BLOCK`.
6. authenticated public REALITY inbound → `PUBLIC_DIRECT`.

The first three protections precede the allow rule. The exact allow and catch-all remain adjacent. Authenticated REALITY traffic retains the product's ordinary public proxy behavior through `PUBLIC_DIRECT`; the defender is narrowly for REALITY target/fallback probe handling and does not change the client protocol.

## Instances and state

Each instance receives a stable `r` plus 16-lowercase-hex ID and independent:

- UUID;
- X25519 private/public keypair generated and derived by Xray;
- 16-character hexadecimal short ID;
- target/serverName and target port;
- TCP Actual port and an enforcement-resolved wildcard or exact-address public service listener;
- internal defender port/tag, `127.0.0.1` listen contract, dispatch sentinel, and fixed-redirect target mode;
- systemd/OpenRC service identity;
- Common Port and firewall ownership;
- Ingress Profile association and recommendation metadata;
- Display Endpoint metadata; and
- enabled/runtime-version lifecycle state.

Authoritative paths are:

```text
/var/lib/nobrand-oneclick/vless-reality/instances/<id>/state.json
/etc/nobrand-oneclick/vless-reality/instances/<id>/config.json
/etc/nobrand-oneclick/vless-reality/instances/<id>/private.key
```

The state and config instance directories are root-only `0700`. State, server config, and `private.key` are `0600` and root-owned. State stores the public key and private-key path, never the private key value. Xray requires `privateKey` inside its server config, so both that config and the separate authoritative key file are secrets.

Ordinary `status`, `nodes`, menu, and Doctor output do not print the private key, UUID, public key, short ID, or credential-bearing URI. Explicit `show` and `export` actions reveal client material—UUID, public key, short ID, and URI—but never the private key.

## Ingress Profile and port behavior

Public Profiles are recommended. Mapped/dedicated Profiles display a neutral warning and remain installable because an ordinary public NAT mapping can still be valid.

An Ingress Profile determines the port policy, Profile association, enforcement policy, and automatic Display default. It does not determine egress, alter the default route, add `ip rule`, change `rp_filter`, configure an interface, or change provider mapping. Linux routing continues to determine proxy egress.

REALITY accepts both Profile enforcement policies:

- `permissive` uses `0.0.0.0` and records method `wildcard`;
- `strict` binds Xray to the Profile local address and records method `native-bind`.

Missing enforcement fields remain permissive for legacy schema-v3 state. Strict always uses the Profile local address, never the Display Host. Startup and migration acceptance require an exact-address TCP listener; a wildcard socket does not satisfy strict Doctor or transaction checks.

REALITY owns TCP in the Common Port Registry. Ownership remains host-global and transport-aware even when the listener is strict:

- another `TCP:P` owner conflicts across all Profiles;
- `UDP:P` may coexist with REALITY `TCP:P`;
- a Profile-reserved port is rejected; and
- a `manual-only` Profile requires explicit `--port`.

Example using documentation-only infrastructure values:

```bash
sudo nobrand ingress add --name Example-Public --type public \
  --interface eth0 --address 192.0.2.50 --port-policy manual-only \
  --enforcement strict -y

sudo nobrand vless-reality install --name public-reality \
  --ingress-profile Example-Public --port 32052 --advertise-auto -y

# Independent camouflage overrides when required:
sudo nobrand vless-reality install --name custom-reality \
  --target www.example.com --target-port 8443 \
  --ingress-profile Example-Public --port 32053 --advertise-auto -y
```

## Camouflage target and serverName validation

The default camouflage hostname mode is `auto`; the default camouflage target port is 443. Interactive creation prompts separately with `REALITY camouflage host [auto]` and `REALITY camouflage target port [443]`. A blank interactive host and a missing non-interactive host both request automatic selection. A blank or missing target port uses 443. Host and target port remain independent, so an automatic host may be combined with an explicitly requested non-443 target port.

The production automatic pool is immutable release data, not a runtime download from Xray-OneClick, GitHub, or another API. It contains only discovery candidates that passed the exact NoBrand server topology with Xray 26.3.27 plus authenticated Xray, Mihomo, and sing-box clients during release qualification. A creation transaction randomizes the pool order without replacement and validates each candidate against the actual requested target port. A failed candidate is not retried during that transaction. If the pool is exhausted, creation fails before node, config, service, firewall, public-port, or defender ownership is committed; it never falls back to port 443 or an unqualified hostname.

The v3.2.0 publication qualification matrix is:

| Host | TLS preflight | Xray | Mihomo | sing-box | Automatic pool |
| --- | --- | --- | --- | --- | --- |
| `www.abmindustriesgroup.com` | PASS | PASS | PASS | PASS | included |
| `www.microsoft.com` | PASS | FAIL | not run | not run | excluded |
| `www.oracle.com` | PASS | PASS | PASS | PASS | included |
| `www.ibm.com` | PASS | PASS | PASS | PASS | included |
| `www.amazon.com` | PASS | PASS | PASS | PASS | included |
| `www.samsung.com` | PASS | PASS | PASS | PASS | included |
| `www.nvidia.com` | PASS | PASS | PASS | PASS | included |

The Microsoft authenticated result is retained from the rejected fixed-default candidate because the server protocol topology is unchanged; ordinary TLS success did not qualify it for automatic use. It remains available as an explicit user-supplied hostname and is never silently substituted. The other six rows each completed the same pinned server/defender topology, raw three-client exporters, 20/20 HTTPS checks, 64 MiB download/upload integrity, no-direct failure, restart, backup/restore, anti-probe checks, and formal cleanup.

Explicit `--target`, `--server-name`, or `--sni` uses exactly that normalized hostname and records `camouflage_mode="custom"`. It performs the same hostname, public-DNS, TLS 1.3, certificate, SNI, and actual-port checks; failure closes the transaction and never silently invokes automatic selection. An explicit hostname remains permitted even when it is not in the automatic pool. Existing schema-v3 state is not rewritten merely because its hostname is absent from the current pool.

After automatic selection, authoritative state records both `camouflage_mode="auto"` and the exact chosen `server_name`/`target_host`. Read-only status, nodes, show, export, and Doctor operations consume that value without rerandomizing or modifying state. Restart and ingress reconciliation generate config from the stored value. Backup/restore preserves the origin mode, exact hostname, target port, defender metadata, credentials, Profile, Actual port, and Display Endpoint. Legacy state with no `camouflage_mode` is interpreted as explicit/custom state without a read-only write; legacy state with no `target_port` is still interpreted as 443 without mutation.

The number 443 is the default camouflage target port, not automatically the public REALITY listen port. The public listener, loopback defender port, and camouflage target port remain three independent values. Creation fails closed unless the selected normalized hostname is non-local, resolves only to public addresses, and completes a TLS 1.3 connection on the selected camouflage target port with a matching certificate. The same selected hostname is written to server `serverNames`, client SNI/server-name fields, state, the exact defender domain rule, and the fixed `DIRECT.settings.redirect` destination. The public REALITY inbound itself targets only the owned loopback defender.

Release qualification establishes known-good candidates at publication time; external TLS services may change and permanent availability is not guaranteed. Listing a domain in the technical candidate pool does not imply that its owner endorses, supports, operates, or participates in NoBrand or REALITY.

## Actual versus Display

For a strict node with an exact Actual listener and independent Display metadata:

```text
Actual:  192.0.2.50:32052/TCP
Display: 198.51.100.52:443
Ingress: Example-Public
Enforcement: strict (native-bind)
```

Only Actual owns a local TCP socket, firewall opening, and Common Port row. Display is client/export metadata. `set-endpoint` changes only state metadata; it does not rewrite the Xray server config, private key, UUID, public key, short ID, target, Actual port, service, or Profile association.

The defender is a third, internal endpoint category. Its loopback TCP socket is state-owned and accepted only when the same REALITY Xray PID owns both public and defender listeners. It has no public firewall or Common Port ownership and is never rendered as Actual or Display client metadata.

## Exporters

All exporters are generated directly from authoritative state.

The standard URI contains `security=reality`, `type=tcp`, `flow=xtls-rprx-vision`, `sni`, `fp=chrome`, `pbk`, `sid`, and `spx=%2F`.

The Xray exporter uses VLESS/TCP/REALITY/Vision with current 26.3.27 `password` public material. The Mihomo exporter uses VLESS, `network: tcp`, TLS, Vision flow, `servername`, `client-fingerprint`, and `reality-opts`; its complete configuration fixes `mode: rule`, has a one-member `NOBRAND` group, and routes `MATCH,NOBRAND`. The sing-box exporter uses a VLESS outbound with TLS REALITY and uTLS `chrome`; `route.final` is the proxy tag and no direct outbound exists.

The local runtime gate validates and launches all three exact generated configurations, proves traffic reaches the configured REALITY transport endpoint, completes 20/20 controlled HTTPS requests per client, verifies 64 MiB download and upload integrity, stops the server and requires every client request to fail, restarts it and requires recovery, then repeats after lifecycle restart and backup/restore. Direct defender controls separately prove expected SNI forwarding, wrong-SNI block, plaintext HTTP/random/malformed-TLS block, private-target block, dangerous-port precedence, BitTorrent rule presence, loopback-only listening, same-process ownership, and cleanup.

## Lifecycle, upgrade, backup, and removal

Candidate config is validated with exact Xray `run -test` and the private asset directory before authoritative commit. Installation transactionally owns key, config, state, service template/instance, public TCP firewall opening, enforcement-resolved public listener, loopback defender allocation/listener, same-PID ownership, and health. The defender creates no firewall rule. Runtime/assets, validation, key/config/state commit, service, firewall, start, exact strict listener, defender listener, or PID-ownership failure rolls the complete attempt back without an internal-port residue.

Changing a referenced Profile from permissive to strict, or changing its local address while strict, requires explicit `nobrand ingress modify ... --apply-existing`. `nobrand ingress apply PROFILE` reconciles an unchanged Profile. A failed Profile-wide migration restores the exact old Profile state and reapplies the previous REALITY listener policy.

Shared Xray upgrade snapshots HY2, VLESS/Sudoku, every REALITY state, the old runtime, private geo assets, and active-service membership. It validates managed configs, restarts and accepts every previously active public/defender listener pair, and commits runtime metadata. Any failure—including a later REALITY state commit—restores the runtime/assets and every state and restarts all formerly active services on the old binary.

Unified backup includes REALITY state, config, private key, public client metadata, public/defender ports and tags, target, routing contract, Profile, and Display metadata. Treat the archive as a root secret. Restore reproduces the exact defender config/state bytes, revalidates config and keys with private assets, rebuilds service runtime, restores only public TCP firewall ownership, starts enabled instances, and verifies both same-PID listeners; acceptance failure rolls the restore back.

Formal instance removal stops only that owned service, removes its internal defender owner/listener, closes only its public TCP firewall row, and removes only its state/config/key. The shared Xray binary and private asset directory are removed only when HY2, VLESS/Sudoku, and every REALITY instance no longer need them. systemd/OpenRC service files are replaced or removed only when their NoBrand ownership markers, exact command paths, and asset environment match.

## Doctor and troubleshooting

`nobrand vless-reality doctor` checks:

- schema-v3 state and fixed protocol fields;
- exact Xray runtime version, official private assets, service asset environment, and `run -test` validation;
- server config/state/private-key parity;
- private-key root ownership and `0600` mode;
- Xray-derived public key versus state public key;
- short ID and serverNames/public-loopback-target/flow consistency;
- defender protocol/listen/port/dispatch/sniffing, exact domain allow, adjacent catch-all block, and fixed redirect;
- global private-address, dangerous-port, and BitTorrent blocks plus `PUBLIC_DIRECT`/`DIRECT`/`BLOCK` outbounds;
- enabled service, MainPID, enforcement-resolved public listener, loopback defender listener, and same-process ownership;
- public TCP Common Port/firewall ownership, internal defender uniqueness, and absence of defender firewall ownership;
- Ingress Profile validity/recommendation; and
- effective Display metadata.

If target validation fails, confirm public DNS answers, outbound TCP to the target port, TLS 1.3 support, and certificate/SNI matching. If the service fails, run Doctor before editing any generated file. A private/public mismatch, invalid short ID, changed service template, occupied port, or config validation error is a hard failure; validator diagnostics redact private/public key material, UUIDs, short IDs, passwords, and auth values.

## Boundaries and known limitation

Phase 3 implements strict REALITY ingress through Xray native address binding. It does not implement source policy routing, per-interface accounting, bandwidth quotas, or same-port reuse across Profiles. It does not change NICs, addresses, routes, `ip rule`, `rp_filter`, SSH, or external mapping. Strict ingress and Display metadata remain independent, and default egress remains a Linux routing decision.

Hysteria2 large proxied UDP remains a separate known-deferred issue and is not a REALITY blocker:

> Normal HTTPS/TCP use tested PASS. Some larger SOCKS5 UDP datagrams may experience integrity/time-out issues. This is not classified as Dual-specific. No upstream defect has been confirmed.
