# Multi-Ingress and Strict Ingress Enforcement — 3.2 Release Candidate

NoBrand-OneClick 3.2.0 is an unreleased release candidate. The current immutable release remains v3.1.0. The 3.2 design represents public, mapped, single-NIC, and multi-NIC service entries without taking ownership of Linux routing.

```text
PROTOCOL_FEATURE_FREEZE=true
SCHEMA_VERSION=3
HOST_GLOBAL_PORT_OWNERSHIP=true
```

## Six separate concepts

These terms are deliberately independent:

| Concept | Controls | Does not control |
|---|---|---|
| Ingress Profile | Entry identity, selected local interface/address, defaults | Linux egress routing |
| Port Policy | Automatic pool and reserved ports | Listener address or Display Host |
| Ingress Enforcement | Whether a managed entry may accept traffic through other local addresses | Provider NAT, return routing, accounting |
| Actual Listener | The socket or nftables destination address used by the data plane | Client-facing metadata |
| Display Endpoint | Host/port written to links, client files, exports, and `nobrand nodes` | Runtime, firewall, service, PID, ownership |
| Forward Target | The destination of a Forward rule | Its ingress address or displayed endpoint |

A mapped Profile can therefore have all three of these addresses without conflating them:

```text
Profile local address = 192.0.2.110
Actual strict listener = 192.0.2.110:11021
Display endpoint       = 203.0.113.50:11021
Forward target         = 198.51.100.80:443
```

The strict listener always uses the Profile local address. It never binds to the Display Host.

## Ingress is not egress

Linux continues to choose outbound traffic from its existing routes and rules. NoBrand creates no default route, `ip rule`, policy-routing table, `fwmark` route, source-routing rule, or `rp_filter` change for Ingress Profiles. It also does not configure interface addresses or provider-side mappings.

Doctor and the interactive menu may show the current default-route interface as read-only information. That observation is not an ingress selection and is never rewritten by strict enforcement.

## Profile model

Each explicit Profile records a stable generated ID and:

- name and `public` or `mapped` type;
- one exact local interface and IPv4 address;
- a port policy, optional automatic range, and reserved ports;
- a default Display Host and Display Port policy;
- `ingress_enforcement`;
- enabled state and timestamps.

An interface with more than one address is unambiguous because the user selects both the interface and the exact address. Add and modify verify the pair; Doctor checks that it remains present.

### `public`

Use `public` when the selected local address can be shown directly to clients. If Display Host is omitted, it defaults to that address. Public describes ingress identity, not egress.

### `mapped`

Use `mapped` when the server receives traffic on one local address while clients connect to another public address or domain. The Profile requires an explicit Display Host. NoBrand does not infer a provider contract from RFC1918 space, interface names, routes, or port patterns.

## Port policies

### `derived-tail`

For a local IPv4 whose final octet is `N`:

```text
base reservation = N × 100
automatic pool   = N × 100 + 1 ... N × 100 + 99
```

For example, `192.0.2.110` derives reserved port `11000` and automatic pool `11001-11099`. This is a local derivation, not proof of any provider mapping. Privileged, invalid, or out-of-range results fail closed and do not fall back to random ports.

### `custom-range`

`custom-range` defines an explicit inclusive automatic pool. Reserved ports may be inside or outside it and are skipped. This makes no assumption about provider numbering.

### `manual-only`

`manual-only` has no automatic pool. A new protocol instance or Forward rule must supply its Actual port. It must still be legal, unreserved, absent from NoBrand ownership, and free at the OS listener boundary.

Manual ports under `derived-tail` and `custom-range` may be outside their automatic pools when otherwise valid. NoBrand warns instead of rewriting them. If a later range edit leaves an existing port outside the current pool, the entry remains intact and Doctor reports it.

## Enforcement policies

Every new explicit Profile stores one of:

```text
permissive
strict
```

`permissive` is the default. A missing `ingress_enforcement` field is also interpreted as `permissive`, preserving schema-v3 Profile and node compatibility without an eager migration.

### Permissive

Permissive keeps the product's established wildcard behavior. A managed service may accept packets delivered to any suitable local address, subject to the host firewall and ordinary Linux networking.

Resolved node state uses:

```json
{
  "ingress_enforcement": "permissive",
  "ingress_enforcement_method": "wildcard"
}
```

### Strict

Strict limits a managed entry to the Profile local address. The mechanism depends on the product's real runtime capability:

| Product | Runtime | Strict mechanism | Native bind | Firewall fallback |
|---|---|---|---:|---:|
| Mieru | official latest-stable Mita (qualified 3.36.0) | NoBrand-owned nftables input rule | No | Yes |
| Snell v4 | `snell-server` | Exact local-address listener | Yes | No |
| Snell v5 | `snell-server` | Exact local-address listener for TCP and optional QUIC exposure | Yes | No |
| Hysteria2 | Xray | Exact local-address listener | Yes | No |
| VLESS/Sudoku | Xray | Exact local-address listener | Yes | No |
| VLESS REALITY | Xray | Exact local-address listener | Yes | No |
| TUIC v5 | sing-box | Exact local-address listener | Yes | No |
| Forward nftables | nftables | Destination-address match before DNAT | No socket | No fallback |
| Forward Realm | Realm | Exact local-address listener | Yes | No |
| SSH Tunnel | system OpenSSH `sshd` | `NOT_APPLICABLE_TO_SYSTEM_SSH` | Not applicable | Not applicable |

A native strict node resolves fields such as:

```json
{
  "ingress_enforcement": "strict",
  "ingress_enforcement_method": "native-bind",
  "ingress_local_address": "192.0.2.110"
}
```

NoBrand accepts strict startup only after the exact address is present in the real listener. A wildcard socket does not satisfy native-bind acceptance.

## Mieru firewall fallback

The qualified Mita 3.36.0 server contract, like the earlier 3.35.0 baseline, has no server listen-address field, so NoBrand does not invent an `ipAddress` option. A strict Mieru user retains its validated wildcard runtime and is isolated by the dedicated table:

```text
table inet nobrand_ingress
```

The table's input chain keeps policy `accept`. For each managed strict Mieru port, the generated rule has the equivalent form:

```text
ip daddr != 192.0.2.110 tcp dport 11021 drop
ip daddr != 192.0.2.110 udp dport 11022 drop
```

Only authoritative Mieru strict rows appear there. The rules contain no `counter`; Phase 3 adds neither per-ingress accounting nor hidden quota state. NoBrand regenerates only its owned table, validates candidates before application, and rolls back state and rules together if an update fails.

Backup restore reapplies the authoritative strict table before starting wildcard Mieru services, so restore does not briefly expose a strict listener permissively. Uninstall stops managed Mieru services before clearing this table. External nftables tables and rules are untouched.

Mieru runtime selection is independent of ingress enforcement. The default `stable` channel resolves the highest official strict-semver non-draft/non-prerelease release at install or explicit upgrade time, pins the exact asset/digest/checksum for that transaction, and verifies the installed runtime identity. The release-candidate qualification resolved 3.36.0; it is also the explicit last-known-good used only when live metadata cannot be fetched. A future runtime does not gain native-bind treatment merely because it is newer: NoBrand continues to use this owned firewall fallback until that exact supported server contract is audited and qualified with a real listen-address field.

## Forward strict semantics

A Forward rule keeps Profile, Port Policy, enforcement, Actual ingress, Display Endpoint, and Target separate.

For strict nftables Forward, the generated `prerouting` DNAT rule includes `ip daddr PROFILE_LOCAL_ADDRESS`. Packets delivered to another local address do not match the managed rule. No `iifname` assumption is required, and the Target remains independent.

For strict Realm Forward, the Realm endpoint listens on the Profile local address. The service must be active and its real TCP/UDP listeners must match that exact address before state is committed.

Switching `nftables → Realm → nftables` preserves the Profile, numeric port, protocol, Display metadata, Target, and strict policy. A candidate or listener failure restores the previous backend and data plane. Switching a domain or IPv6 Realm Target to nftables still requires an explicit IPv4 Target.

## Host-global, transport-aware ownership

The Common Port key remains:

```text
transport:port
```

`TCP:P` and `UDP:P` may belong to different entries when the OS allows it. Two owners of the same transport and numeric port are rejected even when their Profiles and strict local addresses differ. Strict enforcement therefore does not introduce same-port reuse across Profiles.

This conservative host-global boundary avoids hidden runtime and migration conflicts and remains unchanged from the earlier foundation.

## Cross-entry isolation

Strict is an ingress acceptance property:

```text
strict Profile A, address A, port P: connect through A:P = accepted
strict Profile A, address A, port P: connect through B:P = rejected
```

The same rule applies to TCP and UDP and to public or mapped Profiles. It does not promise a particular outbound interface; Linux routing still decides egress. If a real topology cannot return traffic correctly without policy routing, qualification must stop rather than silently add it.

## SSH Tunnel exception

SSH Tunnel reuses the system's external `sshd`. NoBrand does not own its listener, port, public firewall, host keys, or administrator access, so Profile strict enforcement is not applied to it:

```text
NOT_APPLICABLE_TO_SYSTEM_SSH
```

The Profile continues to supply Display defaults only. A mapped entry can advertise `203.0.113.50:11000` while the real system sshd remains on its existing port. NoBrand does not move or filter sshd.

## CLI and explicit migration

Examples use documentation-only addresses:

```bash
sudo nobrand ingress add --name Example-Mapped --type mapped \
  --interface eth1 --address 192.0.2.110 \
  --port-policy derived-tail --reserve 11000 \
  --advertise-host 203.0.113.50 \
  --display-port-policy follow-actual \
  --enforcement strict -y

sudo nobrand ingress add --name Example-Public --type public \
  --interface eth0 --address 198.51.100.20 \
  --port-policy manual-only --enforcement permissive -y

sudo nobrand ingress set-default Example-Mapped
nobrand ingress list
nobrand ingress show Example-Mapped
nobrand ingress doctor
```

Changing a Profile's enforcement, or changing its local interface/address while it is strict, is runtime-affecting. If non-SSH entries reference it, the change is rejected unless the operator explicitly requests a transactional migration:

```bash
sudo nobrand ingress modify Example-Mapped \
  --enforcement strict --apply-existing -y
```

The migration updates every non-SSH owner. State is committed only after all entries accept the new data plane. If a later owner fails, the exact old Profile JSON is restored and earlier owners receive a compensating old-policy apply.

To reconcile every existing non-SSH owner with the Profile's current policy without editing the Profile:

```bash
sudo nobrand ingress apply Example-Mapped
```

Interactive add defaults to permissive. Interactive modify shows the current policy, lists affected entries for runtime changes, and requires confirmation before applying them.

## Actual and Display output

Unified node output keeps these independent lines:

```text
Actual: 192.0.2.110:11021/UDP
Display: 203.0.113.50:11021
Ingress: Example-Mapped
Enforcement: strict (native-bind)
```

Changing Display metadata does not invoke an enforcement migration, rewrite a listener, restart a service, alter firewall rules, change the Target, or change port ownership.

## Legacy compatibility

`schema_version` remains `3`. A legal 3.1-style state may have no `ingress.json`, no `ingress_profile_id`, and no enforcement fields. It remains readable through:

```text
legacy-default-route
Legacy Default Route
```

Missing Profile or node enforcement resolves to `permissive` and missing method resolves to `wildcard`. Read-only startup, list, status, nodes, and Doctor do not eagerly rewrite legacy state or restart services. If no explicit default is set and a new request omits `--ingress-profile`, the legacy adapter retains the established default-route-address port-basis behavior.

## Doctor, backup, restore, and uninstall

Ingress Doctor validates Profile schema, references, interface/address presence, policy/range/reservations, host-global ownership, and enforcement drift. For an enabled strict owner it proves one of:

- exact native listener address;
- owned Mieru firewall row; or
- owned nftables Forward destination-address match.

Permissive owners are reported explicitly rather than misclassified as strict. SSH is reported as not applicable, not failed.

Unified backup includes Profile enforcement plus resolved node and Forward enforcement state. Restore treats files and external effects as one transaction, applies the strict Mieru firewall before wildcard services, validates native listeners and Forward rules, and rolls back on failure.

Removal and unified uninstall stop owned data planes before removing enforcement artifacts. They never remove interfaces, addresses, routes, policy rules, system sshd, provider mappings, or unrelated firewall state.

## Forward UDP path capability

NoBrand Forward transparently relays application UDP datagrams and does not fragment, resize, clamp, or otherwise transform them. The maximum usable datagram size can depend on the provider, NAT, tunnel, and Internet path. A controlled nftables or Realm backend path may therefore pass an exact payload size even when a particular external path drops that size before it reaches the managed server interface. This environmental path capability is separate from strict-ingress enforcement and from the Hysteria2 proxied-UDP limitation below.

## Deliberately deferred

Phase 3 does not implement:

- policy routing, `ip rule`, new routing tables, `fwmark`, or default-route changes;
- `rp_filter` changes;
- per-interface or per-ingress counters, accounting, quotas, or shaping;
- same-transport same-port reuse across Profiles;
- provider mapping discovery; or
- a 3.2 release.

Hysteria2 large proxied UDP datagrams remain separately known and deferred:

> Normal HTTPS/TCP use tested PASS. Some larger SOCKS5 UDP datagrams may experience integrity/time-out issues. This is not classified as Dual-specific. No upstream defect has been confirmed.
