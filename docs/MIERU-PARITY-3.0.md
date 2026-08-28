# Mieru parity contract for NoBrand-OneClick 3.0

This document freezes the user-visible Mieru contract that NoBrand-OneClick
3.0 must preserve before any legacy-management code is removed. The authority
is the last immutable Mieru-only release of `ike-sh/mieru-OneClick`:

- tag: `v2.2.1`
- commit: `2b3e2371746a0dd0248887a216d3a45d6ac8e95c`
- project-tested upstream Mieru version: `3.35.0`

The current `ike-sh/mieru-OneClick` remote has since evolved into the NoBrand
repository, so remote `main` is not an independent parity authority. Branding,
manager paths, service names, and schema placement may change in 3.0; protocol
semantics, defaults, generated Mita configuration, and client outputs may not.

Status vocabulary:

- `LOCKED`: behavior and golden expectation extracted from v2.2.1.
- `PASS`: the 3.0 implementation and automated parity test are complete.
- `REAL PASS`: the local parity test passed and the behavior was also exercised
  on the authorized IPLC/Debian lab.

## Feature and parameter inventory

| Old mieru-OneClick feature | Old CLI/menu path | Old state field | Old Mita config output | NoBrand 3.0 equivalent | Parity status |
|---|---|---|---|---|---|
| Fresh install | `--install`, `install`, menu `1` | install marker; all install-state fields; `users.json` | Per-user server JSON applied to a dedicated Mita instance | `nobrand mieru install` and Mieru menu `1` | LOCKED |
| Reconfigure | `--reconfigure`, `reconfigure`, menu `5` | Updates concrete parameter fields and affected user fields | Rebuilds only the requested Mieru configuration | `nobrand mieru reconfigure` | LOCKED |
| Runtime upgrade | `--upgrade`, `upgrade`, menu `8` | `MIERU_CHANNEL`, `MIERU_VERSION` | No wire/config change unless upstream requires it | `nobrand mieru upgrade` | LOCKED |
| Protocol-only uninstall | `--uninstall`, menu `10` | Mieru ownership markers and owned manifests | Removes owned Mieru instances/config | Mieru uninstall action plus project-wide `nobrand uninstall` | LOCKED |
| Start / stop / restart | `--start`, `--stop`, `--restart`; Service menu | Enabled users and stable `instance_id` | Starts/stops each isolated instance without rewriting credentials | `nobrand mieru start|stop|restart` | LOCKED |
| Status | `--status`, Service menu `1` | install state and `users.json` | Read-only `describe config`/service inspection | `nobrand mieru status`; summarized by `nobrand status` | LOCKED |
| Doctor | `--doctor`, `--verify`, menu `9` | All owned manifests | Read-only service/user/quota/tc/firewall checks | `nobrand mieru doctor`; included in `nobrand doctor` | LOCKED |
| Performance diagnostics | `--perf`, Performance menu `1` | none | none; strictly read-only | `nobrand mieru perf` and top-level network menu | LOCKED |
| Profile metadata | `--profile`, Performance menu `2` | `PROFILE` | Profile is metadata; concrete fields below remain authoritative | `nobrand mieru --profile ...` and Mieru Profile menu | LOCKED |
| IPLC profile | `--profile iplc`; aliases `iplc-performance`, `performance`; Profile menu `1` | `PROFILE=iplc`; concrete fields | TCP, MTU 1400, no trafficPattern | Same preset and aliases | LOCKED |
| Balanced profile | `--profile balanced`; aliases `balance`, `default`; Profile menu `2` | `PROFILE=balanced`; concrete fields | TCP, MTU 1400, conservative trafficPattern | Same preset and aliases; default profile | LOCKED |
| Stealth profile | `--profile stealth`; alias `obfuscation`; Profile menu `3` | `PROFILE=stealth`; concrete fields | TCP, MTU 1400, aggressive trafficPattern | Same preset and aliases | LOCKED |
| Custom profile | `--profile custom`; alias `advanced`; Profile menu `4` | `PROFILE=custom`; concrete fields | Exact values selected by the operator | Same fully exposed custom mode | LOCKED |
| Profile reconciliation | Any later concrete-parameter change | `PROFILE` becomes `custom` when values no longer match | Never rewrites concrete values to preserve stale metadata | Same inferred-metadata behavior | LOCKED |
| TCP transport | `--protocol TCP`; interactive transport `1` | `PROTOCOL=TCP`; user `port` | `portBindings[].protocol=TCP` at base port | Same | LOCKED |
| UDP transport | `--protocol UDP`; interactive transport `2` | `PROTOCOL=UDP`; user `port` | `portBindings[].protocol=UDP` at base port | Same | LOCKED |
| BOTH transport | `--protocol BOTH`; interactive transport `3` | `PROTOCOL=BOTH`; user stores base port | TCP at base port and UDP at base port + 1 | Same | LOCKED |
| Manual listener port | `--port PORT` | primary `PORT`; user `port` | Numeric `port`; allowed listener range 1025-65535 | Same, with Common Port ownership checks | LOCKED |
| Deprecated port range rejection | `--port-range RANGE` parses but isolated-v2 rejects it | `PORT_RANGE` retained only for old-state interpretation | No new isolated-v2 config is generated from a range | No public 3.0 install path; fixed negative parity assertion | LOCKED |
| Automatic tail-port allocation | Install/user-add with no `--port` | selected numeric user `port` | Normal numeric binding | Same default-route IPv4 tail algorithm | LOCKED |
| Tail-base reservation | Automatic/manual port validation | not persisted as a user | no binding at `xx00` | Common Port registry reserves `xx00` for both transports | LOCKED |
| Collision detection | Install/user-add/reconfigure | All user ports plus owned registry state | Refuses conflicting binding before apply | Same plus cross-protocol transport-aware registry | LOCKED |
| TCP/UDP ownership independence | Implicit in protocol-aware checks | protocol + port | TCP/P and UDP/P are distinct bindings | Common registry keys `tcp:P` and `udp:P` | LOCKED |
| Username | `--user NAME` | install `USERNAME`; user `name` | `users[].name` | Same option under `nobrand mieru` | LOCKED |
| Password | `--password PASS` | install `PASSWORD`; user `password` | `users[].password` | Same option under `nobrand mieru` | LOCKED |
| Credential validation | All install/user mutations | same fields; 1-64 bytes, no control characters | Exact JSON-escaped value | Same | LOCKED |
| Safe MTU | `--mtu safe`; MTU menu `1` | `MTU=1400`, `MTU_POLICY=safe` | top-level `mtu: 1400`; client JSON/link MTU 1400 | Same and default | LOCKED |
| Automatic MTU | `--mtu auto`; MTU menu `2` | resolved `MTU`, `MTU_POLICY=optimized` | TCP 1400; UDP/BOTH link MTU minus 28/48, clamped 1280-1400 | Same | LOCKED |
| Custom MTU | `--mtu 1280..1500`; MTU menu `3` | exact `MTU`, `MTU_POLICY=custom` | exact top-level `mtu`; exact client JSON/link MTU | Same | LOCKED |
| Multiplexing OFF | `--multiplexing off`; Performance menu `5` | `MULTIPLEXING_OFF` | Client JSON `multiplexing.level`; share/Mihomo field | Same and default | LOCKED |
| Multiplexing LOW | `--multiplexing low` | `MULTIPLEXING_LOW` | Same client outputs | Same | LOCKED |
| Multiplexing MIDDLE | `--multiplexing middle` (also `medium`) | `MULTIPLEXING_MIDDLE` | Same client outputs | Same | LOCKED |
| Multiplexing HIGH | `--multiplexing high` | `MULTIPLEXING_HIGH` | Same client outputs | Same | LOCKED |
| No-wait handshake | `--handshake-mode no-wait`; alias `--handshake`; Performance menu `5` | `HANDSHAKE_NO_WAIT` | Client JSON `handshakeMode`; share/Mihomo field | Same and default | LOCKED |
| Standard handshake | `--handshake-mode standard` | `HANDSHAKE_STANDARD` | Same client outputs | Same | LOCKED |
| Traffic Pattern off | `--traffic-pattern off`; alias `--traffic`; Performance menu `6` | `TRAFFIC_PATTERN=off`; empty seed allowed | No `trafficPattern` in server/client config or exported pattern | Same | LOCKED |
| Traffic Pattern conservative | `--traffic-pattern conservative` | value plus stable `TRAFFIC_SEED` | Printable nonce 4-8, end padding 128, no TCP fragment | Same and default | LOCKED |
| Traffic Pattern aggressive | `--traffic-pattern aggressive` | value plus stable `TRAFFIC_SEED` | Printable nonce 6-12, middle padding 64, end padding 255, TCP fragment maxSleepMs 8 | Same | LOCKED |
| Traffic Pattern version gate | Implicit on apply/export | saved requested value may be turned off when unsupported | Emitted only by Mita >=3.28.0 | Same | LOCKED |
| Low Entropy off | `--low-entropy off`; Performance menu `7` | `LOW_ENTROPY_MODE_OFF` | `trafficPattern.lowEntropy.mode`; forced off when Traffic Pattern is off | Same and default | LOCKED |
| Low Entropy 56 | `--low-entropy 56` | `LOW_ENTROPY_MODE_56` | Exact enum in trafficPattern | Same | LOCKED |
| Low Entropy 48 | `--low-entropy 48` | `LOW_ENTROPY_MODE_48` | Exact enum in trafficPattern | Same | LOCKED |
| Low Entropy 40 | `--low-entropy 40` | `LOW_ENTROPY_MODE_40` | Exact enum in trafficPattern | Same | LOCKED |
| Low Entropy 32 | `--low-entropy 32` | `LOW_ENTROPY_MODE_32` | Exact enum in trafficPattern | Same | LOCKED |
| Low Entropy version gate/warning | Implicit on apply and selection | normalized enum | Emitted only by Mita >=3.35.0; client compatibility warning retained | Same | LOCKED |
| Display Endpoint auto | `--advertise-auto`; user Endpoint menu | empty `advertise_host`, empty `advertise_port` | Never changes Mita server config | Same | LOCKED |
| Display Endpoint host+port | `--advertise-host HOST --advertise-port PORT`; aliases `--entry-ip`, `--entry-port` | user `advertise_host`, `advertise_port` | Never changes Mita server config | Same | LOCKED |
| Display Endpoint host-only update | Old persisted endpoint requires a complete pair; an update can preserve the current/effective port | final pair in the same two fields | Never changes Mita server config | `nobrand mieru user-set-endpoint --advertise-host HOST` merges current/effective port | LOCKED |
| Display Endpoint port-only update | Old persisted endpoint requires a complete pair; an update can preserve the current/effective host | final pair in the same two fields | Never changes Mita server config | `nobrand mieru user-set-endpoint --advertise-port PORT` merges current/effective host | LOCKED |
| IPv4 / IPv6 / domain Endpoint | Endpoint CLI/menu | normalized host and numeric port | Export only; IPv6 is bracketed in `mierus://` | Same validation and formatting | LOCKED |
| Endpoint isolation | User Endpoint action | only the two advertise fields and `updated_at` | Server config/listener/service/firewall/tc/quota unchanged | Same, regression-tested by hashes and service-call count | LOCKED |
| Stable version channel | `--mieru-channel stable`; Advanced menu `1` | `MIERU_CHANNEL=stable`, installed `MIERU_VERSION` | runtime version `3.35.0`; no config-semantic change | Same semantics; Performance menu `9`; fresh-install default | LOCKED |
| Latest version channel | `--mieru-channel latest` | `MIERU_CHANNEL=latest`, resolved `MIERU_VERSION` | current upstream latest; no config-semantic change | Same | LOCKED |
| Exact/pinned version | `--mieru-version VER` | `MIERU_CHANNEL=pinned`, exact `MIERU_VERSION` | exact official package; no config-semantic change | Same | LOCKED |
| Official package integrity | Install/upgrade | ownership markers and installed version | none | Official deb/rpm/tar.gz, SHA-256 verification, package service guard | LOCKED |
| Platforms and architecture | Install | none | none | Debian/Ubuntu deb, RHEL/Rocky rpm, Alpine tar.gz; amd64/arm64 | LOCKED |
| Upstream runtime identity | All runtime actions | owned-package markers | official `mita` behavior | Explicit managed real-Mita path; never a management wrapper | LOCKED |
| Isolated-v2 deployment | First install and all user changes | deployment model plus `users.json` | One server config and one Mita process per enabled user | Same behavior under NoBrand-owned Mieru state | LOCKED |
| Stable instance identity | User creation | user `instance_id`, independent of later name/port metadata | Selects config/socket/metrics/service paths | Same | LOCKED |
| Add user | `--user-add`, `user-add`, User menu `2` | complete user object | Dedicated one-user config and exclusive port | `nobrand mieru user-add` | LOCKED |
| Delete user | `--user-del NAME`, User menu `3` | removes exact user after backup | Removes exact instance; stale credentials explicitly revoked | `nobrand mieru user-del NAME` | LOCKED |
| List/view user | `--users`, `--user-list`, `--user-show`; User menu `1/4` | read-only user fields | read-only | Same | LOCKED |
| Enable/disable user | `--user-enable`, `--user-disable`; User menu `7/8` | `enabled` | Enabled user has an instance/binding; disabled user retains state/port | Same | LOCKED |
| Unlimited package | `--package unlimited` | package; quota 0/0; no expiry | No `quotas` array | Same | LOCKED |
| Trial package | `--package trial` | 10240 MB / 7 days; default `+7d` expiry | one Mita quota entry | Same | LOCKED |
| Standard package | `--package standard` | 102400 MB / 30 days; default `+30d` expiry | one Mita quota entry | Same | LOCKED |
| Custom package | `--package custom --quota-mb N --quota-days D` | exact values | exact quota entry; 30-day fallback for positive quota with omitted days | Same | LOCKED |
| Rolling quota | `--quota-mode rolling` | `quota_mode=rolling`, quota fields | exact `days` and `megabytes` | Same and default | LOCKED |
| Calendar quota | `--quota-mode calendar` | `last_quota_reset`, month-sized `quota_days` | current calendar-month days; per-instance metrics reset | Same | LOCKED |
| Manual quota reset | `--user-quota-reset`; User menu `14` | reset marker transaction | rebuild plus owned per-user metrics reset | Same | LOCKED |
| Quota/expiry scan | `--user-scan`; User menu `9` | `enabled`, reset markers, timestamps | Stops expired instance; applies due calendar resets | Same scheduler and manual action | LOCKED |
| Expiry | `--expire YYYY-MM-DD|+Nd|0`; User menu `6` | `expire_at` | Expired user omitted from active instance set | Same | LOCKED |
| Per-user bandwidth | `--user-set-rate --bandwidth Mbps`; User menu `10` | `bandwidth_mbps` | none in Mita JSON; owned tc filters on dedicated port | Same 0-1000000 Mbps behavior | LOCKED |
| tc status/restore | `--rate-status`, `--tc-status`, `--rate-restore`, `--tc-restore`; old menus | owned tc manifest, pref 42000-42999 | none | Same; Performance menu `8/10`; never replaces an existing root qdisc | LOCKED |
| Usage reporting | `--user-usage`, alias `--usage`; User menu `15` | read-only | Mita users/quotas metrics | Same | LOCKED |
| User-state backup | `--user-backup`; Backup menu `1`, User menu `12` | root-only `users_*.json`, matching install-state snapshot | none | Same function, but only schema-v3 NoBrand state | LOCKED |
| User-state restore/import | `--user-restore FILE`, `--user-import FILE`; Backup menu | validates all fields/endpoints/ports, snapshots, transactional apply | Rebuilds isolated instances from validated state | Same function, accepts only schema-v3 NoBrand backups | LOCKED |
| User-state export | `--user-export [FILE]`; Backup menu | exact current users document | none | Same | LOCKED |
| Batch client export | `--user-export-clients [DIR]`; menus | stable root-only current export paths | none | Same under NoBrand Mieru export root | LOCKED |
| `mierus://` exporter | `--client-config`, `--show`, user view/export | username/password/endpoint/protocol/MTU/mux/handshake plus exported traffic pattern | none | Same fields, ordering-insensitive parity | LOCKED |
| Official Mieru JSON exporter | same | same plus client RPC 8964, SOCKS 1080, HTTP 8080 | none | Same semantic JSON and root-only permissions | LOCKED |
| Mihomo/Clash YAML exporter | same | endpoint, credential, protocol, mux, handshake, optional traffic pattern | none | Same supported fields; no invented MTU field | LOCKED |
| BOTH client outputs | same | base display port | Separate TCP and UDP links/JSON; UDP display port is base + 1 | Same | LOCKED |
| Connection summary | same | all concrete values | none | Same information in Mieru view and unified nodes | LOCKED |
| Unified node projection | n/a in the Mieru-only project | persisted user state, not process-derived secrets | read-only runtime status | `nobrand nodes`, including stopped Mieru users | LOCKED |
| Firewall ownership | Implicit install/reconfigure/user lifecycle | exact owned TCP/UDP bindings | none | Same UFW/firewalld/iptables and IPv4/IPv6 ownership discipline | LOCKED |
| BBR/FQ detect/enable/status/rollback | `--enable-bbr`; Performance menu `4` | owned sysctl state/backup | none | Same local-only safe management | LOCKED |
| systemd and OpenRC | All service actions | stable instance id and owned unit paths | exact per-user config/socket/metrics arguments | Same supported service managers | LOCKED |

## Frozen defaults

The following values are release blockers, not suggestions:

```text
PROFILE=balanced
PROTOCOL=TCP
MTU=1400
MTU_POLICY=safe
MULTIPLEXING=MULTIPLEXING_OFF
HANDSHAKE_MODE=HANDSHAKE_NO_WAIT
TRAFFIC_PATTERN=conservative
LOW_ENTROPY_MODE=LOW_ENTROPY_MODE_OFF
MIERU_CHANNEL=stable
TESTED_MIERU_VERSION=3.35.0
CLIENT_RPC_PORT=8964
CLIENT_SOCKS5_PORT=1080
CLIENT_HTTP_PORT=8080
QUOTA_RESET_METHOD=metrics
MITA_DEPLOYMENT_MODEL=isolated-v2
```

## Frozen Mieru user fields

The schema-v3 location/outer envelope may change. Every mature user field must
remain readable, writable, backed up, restored, exported where applicable, and
removed by the Mieru ownership transaction:

```text
instance_id
name
password
port
advertise_host
advertise_port
enabled
quota_mb
quota_days
quota_mode
last_quota_reset
expire_at
package
bandwidth_mbps
created_at
updated_at
```

## Golden-test gates

`tests/test_mieru_parity.sh` and its frozen v2.2.1 fixture must emit all of:

```text
MIERU_PARAMETER_PARITY=PASS
MIERU_DEFAULT_PARITY=PASS
MIERU_PROFILE_PARITY=PASS
MIERU_CONFIG_PARITY=PASS
MIERU_EXPORT_PARITY=PASS
MIERU_ENDPOINT_PARITY=PASS
MIERU_PORT_PARITY=PASS
```

Legacy management/install/state migration code may be removed only after these
gates pass against the 3.0 implementation and the inventory rows above have no
missing 3.0 equivalent.

## NoBrand 3.0 final qualification

The `LOCKED` value in the inventory is the immutable v2.2.1 contract status,
not an unfinished implementation status. NoBrand-OneClick 3.0.0 has now passed
every inventory row locally, and the user-visible parameter matrix has also
been exercised on the authorized IPLC/Debian lab.

```text
MIERU_PARAMETER_PARITY=PASS
MIERU_DEFAULT_PARITY=PASS
MIERU_PROFILE_PARITY=PASS
MIERU_CONFIG_PARITY=PASS
MIERU_EXPORT_PARITY=PASS
MIERU_ENDPOINT_PARITY=PASS
MIERU_PORT_PARITY=PASS

MIERU_ALL_OLD_PARAMETERS_PRESERVED=true
MIERU_OLD_DEFAULTS_PRESERVED=true
MIERU_MULTIUSER=true
MIERU_QUOTA=true
MIERU_TC=true
MIERU_ENDPOINT=true
```

Real-machine coverage included all four profiles; TCP, UDP, and BOTH;
safe/auto/custom MTU; every multiplexing and handshake mode; every traffic
pattern and low-entropy value; automatic and custom Display Endpoints;
isolated-v2 multi-user instances; quota, expiry, and tc/rate operations;
stable/latest/pinned version-channel resolution; client exports; service
start/stop/restart; Doctor/performance diagnostics; backup/restore; and
protocol-only plus unified ownership cleanup.
