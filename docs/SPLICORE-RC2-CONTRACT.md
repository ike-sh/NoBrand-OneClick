# Splicore v0.3.0-rc.2 integration contract

Audit date: 2026-10-17 (Asia/Shanghai).

**Disposition: adapter implemented for the expressible subset; incompatible
legacy configurations fail before cutover.** Local validation and pending real
platform/client qualification are separate. See the
[migration report](reports/SPLICORE_SINGLE_CORE_MIGRATION_REPORT.md).

2026-10-18 blocker recheck: native REALITY flow-none carries payload, but a private
destination counterexample demonstrates missing old policy enforcement. Public
rc.2 also documents and accepts Vision; NoBrand Vision migration is still
rejected in the current scope. HY2 Salamander remains absent and rejected.
See the [closure attempt and exact field mapping](reports/SPLICORE_SINGLE_CORE_BLOCKER_CLOSURE_REPORT.md).

## Public identity

The only target is [ike-sh/Splicore v0.3.0-rc.2](https://github.com/ike-sh/Splicore/releases/tag/v0.3.0-rc.2).
The annotated tag object is `9913c1043b87b5f56c2c0d98e38366fd7ad98584`;
its commit and the published amd64 binary both identify
`926f3274fd44ac618cc276951eefe2d27134f687`. The tag object hash is not a
different source commit. No local Splicore HEAD or unpublished build is used.

The active artifact/capability authority is
[`runtime/splicore-release.json`](../runtime/splicore-release.json), embedded in
the standalone installer. All artifact and expected binary hashes live there.

| uname/architecture | Normalized | Public archive | Qualification |
|---|---|---|---|
| x86_64 / amd64 | amd64 | splicore-v0.3.0-rc.2-linux-amd64.tar.gz | Linux amd64, experimental; NoBrand migration unqualified |
| aarch64 / arm64 | arm64 | splicore-v0.3.0-rc.2-linux-arm64.tar.gz | BUILD ONLY; runtime not qualified |
| Anything else | Rejected | None | ARCH_UNSUPPORTED; no fallback/build/latest |

Both archives and the 212-byte `SHA256SUMS` were obtained from this exact public
release. Manifest lines are a 64-character SHA256, two spaces, and the exact
archive basename. Both checksums matched. The archives have a root `splicore`
regular executable, `LICENSE`, `NOTICE.md`, `THIRD_PARTY_NOTICES.md`, and
`licenses/third-party/...` regular license files. The amd64 executable is a
statically linked Linux ELF64. No dynamic loader or shared libc is needed by
that binary; this is not distribution/runtime certification.

`splicore version --json` reports:

```text
product: Splicore
version: v0.3.0-rc.2
commit: 926f3274fd44ac618cc276951eefe2d27134f687
dirty: false
platform: linux/amd64
build_tags: with_quic,with_utls,with_gvisor
channel: development
api_version: v1
```

The actual product channel string is `development`. Public release qualification
is Release Candidate / experimental, never stable. The release also states that
real hardware and product CLI/API end-to-end qualification are not qualified.

## Configuration and ownership

[Public configuration documentation](https://github.com/ike-sh/Splicore/blob/v0.3.0-rc.2/docs/CONFIGURATION.md)
defines a strict schema-1 YAML **bootstrap**, not a protocol configuration:

```yaml
schema: 1
state_directory: /private/nobrand-splicore/state
key_file: /private/nobrand-splicore/state/master.key
api:
  unix_socket: /private/nobrand-splicore/control.sock
```

The example paths are illustrative. Actual paths are scoped to immutable
NoBrand-owned generations; see [layout](SPLICORE-MIGRATION.md).
Unknown YAML fields, duplicate keys, aliases and multiple documents reject.
Protocol resources and encrypted credentials are stored in SQLite `state.db`.
The matching `master.key` must accompany every database backup/restore. NoBrand
business state must remain a separate authority with an explicit mapping from
NoBrand node IDs to Splicore resource/binding IDs. Never edit SQLite rows to
simulate unsupported resource operations.

The [public CLI](https://github.com/ike-sh/Splicore/blob/v0.3.0-rc.2/docs/CLI.md)
provides:

```text
splicore version --json
splicore validate <bootstrap.yaml>
splicore key init --file <private-master-key>
splicore run --config <bootstrap.yaml>
splicore inbound validate --protocol <name> --file <managed.json>
splicore inbound plan --protocol <name> --config <bootstrap.yaml> --file <managed.json>
splicore inbound apply --protocol <name> --config <bootstrap.yaml> --file <managed.json> --plan <plan.json>
splicore inbound list --config <bootstrap.yaml>
```

Bootstrap validation is offline and does not validate a proxy graph. Inbound
validation is offline and checks typed creation documents. Plan/apply use a
running local control socket; plans bind intent and the current global revision.
Apply builds/starts the actual listener. TLS file/trust checks also occur during
runtime preparation: an accepted offline document is not sufficient proof that
existing certificates will load.

One public binary/daemon can hold multiple native inbound runtimes. The audit
started four loopback inbounds in one OS process using only the public binary.
No separate Mita, sing-box or Xray process was launched by the probe. This proves
that basic process model, not traffic compatibility or NoBrand migration.

## Enforced contract restrictions

### HY2_SALAMANDER — existing HY2 wire configuration cannot be retained

NoBrand `hysteria2_generate_config` always writes UDP FinalMask Salamander;
`hysteria2_build_share_link` and both client exporters always advertise
`obfs=salamander` with the stored password. Installation generates this value.

The pinned [Hysteria2 settings](https://github.com/ike-sh/Splicore/blob/v0.3.0-rc.2/internal/splicore/protocol/hysteria2/hysteria2.go)
declare TLS and optional specialized Hysteria transport, with no obfs field.
The [transport fields](https://github.com/ike-sh/Splicore/blob/v0.3.0-rc.2/internal/splicore/domain/streamtransport/hysteria.go)
also contain no Salamander. Published binary tests reject both a settings-level
obfs field and an obfs field inside Hysteria transport. Plain HY2 succeeds as a
positive control. Removing Salamander would require existing client changes.
The released [transport restrictions](https://github.com/ike-sh/Splicore/blob/926f3274fd44ac618cc276951eefe2d27134f687/docs/architecture/HYSTERIA_TRANSPORT.md#bounds-and-unsupported-wrappers)
explicitly state that Salamander is not implemented; UDP FinalMask is also
unsupported. This is not a field-spelling issue in the NoBrand adapter.

### MIERU_ADVANCED_SETTINGS_AND_QUOTA — current profiles are not equivalent

The pinned [Mieru settings](https://github.com/ike-sh/Splicore/blob/v0.3.0-rc.2/internal/splicore/protocol/mieru/mieru.go)
accept `transport` (one of tcp/udp), `mtu` (1280..1500), and `multiplex`
(default/off/low/middle/high). They use embedded Mieru 3.38.0. There is no managed
setting for the existing NoBrand server traffic-pattern seed/nonce/padding/
fragment settings or Low Entropy. The public binary rejects these settings and
strict quota intent. The current default balanced profile requests conservative
traffic-pattern obfuscation; it cannot simply be described as equivalent.

NoBrand's handshake mode and multiplexing are also part of its existing client
exports. In particular, handshake mode is not an old Mita server setting.
Retaining that client option is a client-output/wire-qualification requirement;
rejecting an invented inbound `handshakeMode` field does not prove that the old
client handshake option itself is incompatible. Do not unnecessarily move
client-only options into the new server document.

NoBrand quota accounting/calendar reset relies on each user's dedicated Mita
`metrics.pb`. Splicore statistics describe authenticated payload per runtime
generation and declare quota/speed/session policy unsupported. Those counters
cannot replace durable existing quota totals/reset semantics without a designed
and verified NoBrand accounting adapter. Expiry, enable/disable, user addition,
rotation and deletion also need application-level lifecycle support. Sending
`policy_mode=metadata_only` would drop enforcement and is not a migration.

A BOTH listener is not accepted in one managed Mieru document. Two inbounds
inside one daemon might preserve the old TCP port and UDP port+1, but shared
identity, mutation, accounting and rollback would need explicit orchestration.
This is a semantic mapping requirement, not evidence that two inbounds are
impossible. The public envelope also caps users at 16 and the service at 64
inbounds; existing deployments must be checked before planning.

### SNELL_QUIC_AND_PSK_DOMAIN — current valid state may be rejected

The pinned [Snell module](https://github.com/ike-sh/Splicore/blob/v0.3.0-rc.2/internal/splicore/protocol/snell/snell.go)
has no QUIC proxy mode. Adding `quic_proxy_enabled` rejects in the public binary.
NoBrand currently supports optional same-port UDP ownership for Snell v5; its
own docs do not claim full QUIC wire qualification. Migration must still not
silently discard the stored option/firewall ownership.

NoBrand admits PSKs of 8..128 characters including punctuation such as `.` and
`:`, while the rc.2 managed profile requires 12..255 bytes from a narrower
alphanumeric/`-_+/=` alphabet. Synthetic eight-character and punctuated PSKs
valid under NoBrand are rejected by rc.2. Rotation is not authorized by upgrade.
Snell v4 and v5 baseline documents validate; rc.2 projects v5 through a v4
compatibility adapter, so the preexisting `version=5` client output needs a
real client test, not an assumed rewrite.

### SERVER_INBOUND_LIFECYCLE — generation replay supplies application lifecycle

The pinned [inbound CLI](https://github.com/ike-sh/Splicore/blob/v0.3.0-rc.2/internal/splicore/cli/inbound.go)
and [server API](https://github.com/ike-sh/Splicore/blob/v0.3.0-rc.2/internal/splicore/api/snell.go)
offer list/get/create/export/display/binding operations, with no server inbound
delete, listener update, or per-inbound start/stop/restart. These are different
from client `local-inbound` operations. Tested unknown CLI actions reject with
an existing inbound ID; `DELETE /api/v1/inbounds/<actual-id>` returns HTTP 405
for all four created protocols.

Binding enable/disable/rotation/deletion exists for some protocols and requires
revision guards; it is not an operation to remove a listener. Snell's declared
mutation capability is unavailable. The NoBrand adapter therefore builds a
complete generation from canonical intent and replays typed documents through
the public CLI. Disabled/removed nodes are absent from that new graph. The
matching vault key and credentials are preserved, with atomic pointers,
transactional rollback and bounded generation retention. Local fixture and
public-binary restart tests cover this application lifecycle. All connections
briefly interrupt on a generation change. No direct SQL or per-protocol daemon
is used. Native supervisor and old-client qualification remain pending.

### TLS_CERTIFICATE_PRESERVATION — existing self-signed certificates fail apply

The test calls the actual NoBrand `tuic_generate_certificate` and
`generate_hysteria2_cert` helpers with temporary synthetic paths. On the tested
Ubuntu/OpenSSL environment they produce self-signed CA certificates without the
SAN leaf identity required by rc.2. Both fail runtime application using the
same published binary; replacing test material with a dedicated CA and a signed
SAN leaf succeeds. Existing files are not changed by this test.

The pinned [TLS material loader](https://github.com/ike-sh/Splicore/blob/v0.3.0-rc.2/internal/splicore/tlsconfig/material.go)
requires an explicit single CA, hostname/chain verification, and a non-CA leaf.
It also requires a private key and its immediate parent to have no group/other
permissions on Linux. Host OpenSSL defaults may differ, so actual legacy
certificates must be inspected; neither renewing every certificate nor dropping
verification is an authorized workaround. Failure at apply after a successful
offline validate is an additional pre-cutover validation concern.

### REALITY_DEFENDER_AND_ROUTING_PARITY — security behavior needs a mapping

NoBrand REALITY is not only UUID/private key/short ID/SNI/port. The existing
renderer adds a loopback dokodemo-door defender, matching-SNI fallback dispatch,
private-IP denial, blocked destination ports and BitTorrent detection.

The pinned [REALITY settings](https://github.com/ike-sh/Splicore/blob/v0.3.0-rc.2/internal/splicore/protocol/vless/settings.go)
represent a public key, short IDs, one server name and a target endpoint.
Server private material can be supplied through `server_secret.private_key`;
keeping the key is expressible. The [native REALITY server](https://github.com/ike-sh/Splicore/blob/v0.3.0-rc.2/protocol/vless/backend/reality.go)
dials the configured target. That alone is not proof of the existing defender
and authenticated/fallback routing restrictions. Mapping needs an actual native
rule/dispatch design and adversarial tests before retiring the defender. The
current external defender must not be left active accidentally, and this scope
does not authorize a new proxy sidecar. Ordinary REALITY cannot be silently
retained as a generic Xray fallback.

## Field ownership and mapping

Legend: **A** equivalent typed field; **B** semantic mapping/qualification;
**C** runtime-specific implementation detail; **D** unsupported contract or
blocking unproven equivalence. A field marked A is not a traffic acceptance pass.

| NoBrand source/options | Canonical owner | rc.2 representation | Class / gate |
|---|---|---|---|
| instance name/ID, schema, ownership, timestamps | NoBrand state | managed name + separate resource-ID map | B; maintain schema-v3 authority |
| listen host/port, strict native bind | NoBrand listener | listener.host / listener.port | A; preserve and check transport collisions |
| Display Host/port, advertise mode | NoBrand endpoint | display_endpoint; retain auto/custom state separately | A/B; no listener changes |
| Ingress Profile/address/enforcement | NoBrand ingress/firewall | exact native bind | B; reject old nft fallback without an equivalent mapping |
| Mieru username/password | NoBrand credential state | users[].username/password | A within narrower input bounds |
| Mieru TCP/UDP/BOTH | NoBrand per-user listener | one tcp/udp inbound, or mapped pair for BOTH | B; preserve TCP:P / UDP:P+1 |
| Mieru MTU/multiplex | NoBrand profile | settings.mtu / settings.multiplex | A/B; normalize values, reject out-of-range |
| Mieru handshake/multiplex client projection | NoBrand client output | retain original client fields, do not invent server fields | B/C; old client wire gate |
| Mieru server/client traffic-pattern/seed, Low Entropy | NoBrand profile | configurable server fields absent | D; no silent drop |
| Mieru quota/total/reset/expiry/package | NoBrand business policy | no equivalent durable metrics/reset contract | B/D; block without enforcement adapter |
| Mieru tc rate filters, per-user metrics.pb | NoBrand tc/accounting | dedicated ports may permit tc; metrics format not portable | B/C; restore tc ownership, do not reset quota |
| Snell version 4/5, PSK | NoBrand node/credential | settings.version / psk | A/B; PSK bounds + old client wire gate |
| Snell quic_proxy_enabled/managed_udp | NoBrand option/firewall | absent | D |
| HY2 auth | NoBrand credential | users[].password | A within credential bounds |
| HY2 SNI/cert/key/h3 | NoBrand TLS | settings.tls / native Hysteria transport | B/D; old certificate acceptance fails |
| HY2 obfs password/Salamander | NoBrand credential + wire option | absent | D; all current HY2 clients affected |
| TUIC version5, cubic, native UDP, zeroRTT=false | NoBrand protocol policy | settings.version/congestion_control/udp_relay_mode/zero_rtt_handshake | A |
| TUIC per-user UUID/password/enable/rotation | NoBrand users | typed users + full generation transaction | A/B; mutations implemented, old-client wire pending |
| TUIC cert/key/SNI/expiry/fingerprint | NoBrand TLS | settings.tls plus retained NoBrand metadata | B/D; original certificate load gate |
| REALITY UUID/private key/public key/short ID | NoBrand credentials | users[].uuid, server_secret.private_key, settings.reality | A; never regenerate on migration |
| REALITY SNI/target host/target port/Vision | NoBrand protocol state | reality.server_name/target, flow=xtls-rprx-vision | A/B; preserve separate display endpoint |
| REALITY fingerprint/spider_x | NoBrand client output | existing client projection retained | C; not server credentials |
| REALITY defender/routing/sniff/private-IP/blocked-port rules | NoBrand security policy | no qualified equivalent mapping | D |
| old binary version, package manager, unit/runner | old runtime deployment | one verified artifact and one daemon service | C/B; snapshot and preserve legacy files |
| enabled/stopped node and remove action | NoBrand lifecycle | complete generation replay | B; shared restart, transactional rollback |
| FinalMask/Sudoku UUID/password/config/service | specialized NoBrand Xray owner | external pinned Xray only | retained; never route through Splicore |
| SSH Tunnel, nftables/Realm forwarding, BBR | existing separate utility owner | outside primary proxy Core conversion | retained |

NaiveProxy, standalone mKCP and XHTTP installers do not exist in the current
NoBrand tree. Native support in Splicore does not authorize adding them.

## Implemented adapter

`runtime/splicore.py` retains existing state/config/lib roots and owns one
service. Each immutable state generation includes the verified binary,
bootstrap, canonical intent, native documents and database/master.key. Keeping
these together makes pointer rollback consistent. Existing certificate paths
stay in place. The public Splicore installer is never executed.

One artifact manager performs exact SHA256SUMS/pin checks, safe staging, ELF
and binary digest checks before execution, full identity checks and atomic
selection. The historical repository had no shared GitHub proxy abstraction;
the primary path now uses one HTTPS adapter with optional prefix proxy. A
mirror never replaces the checksum/pin authority.

Discovery, redacted planning, candidate validation, snapshot, cutover, health
and persistent rollback are implemented. Native traffic qualification remains
separate; old binaries/configs are retained while it is pending. Unified backup
stops the daemon and preserves SQLite/master.key, generations and owned pointer
records. Historical recovery remains scoped; primary operations do not call old
core installers. Cleanup failures are explicit debt.

Status/doctor, protocol/menu routing, backup/restore, upgrade/no-op,
rollback/recover, uninstall/purge and port/firewall integration use the primary
adapter. Unsupported advanced management actions fail explicitly. See the
report for external qualification still pending.

## Reproduction

The probe requires Linux amd64/arm64, Python 3, Bash, OpenSSL and curl. It does
not download or install anything. Place both archives and official `SHA256SUMS`
from the pinned release in a private audit directory, then run from the repo:

```bash
bash tests/test_splicore_rc2_contract.sh
python3 tests/helpers/splicore_rc2_probe.py \
  --artifacts /private/rc2-artifacts \
  --output /private/rc2-contract-probe.json
```

It verifies official checksum entries against the recorded public pin, checks
both archive layouts and ELF architectures, extracts only the verified binary
into a unique temporary directory, and checks exact product/version/commit/
platform identity before execution. The probe uses synthetic credentials,
private files, loopback listeners, no systemd/OpenRC installation and no SQL
edits. It terminates its one daemon and removes its temporary directory.

The default test suite runs only the safety-helper self-tests. Expected
rejections prove enforced compatibility restrictions, not successful legacy
migration acceptance. The [recorded public binary output](reports/SPLICORE_RC2_CONTRACT_PROBE.json)
contains no credentials.
