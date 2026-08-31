# TUIC v5 contract for NoBrand-OneClick 3.1

Status: v3.1.0 release contract, qualified 2026-08-31. This document records the upstream audit and the exact product choices implemented for 3.1.0.

## Upstream authorities

- [TUIC protocol specification](https://github.com/tuic-protocol/tuic/blob/master/SPEC.md)
- [sing-box TUIC inbound](https://sing-box.sagernet.org/configuration/inbound/tuic/)
- [sing-box TUIC outbound](https://sing-box.sagernet.org/configuration/outbound/tuic/)
- [Mihomo TUIC proxy schema](https://wiki.metacubex.one/en/config/proxies/tuic/)

NoBrand supports TUIC v5 only. TUIC v1-v4 are rejected; there is no legacy compatibility switch or migration runtime.

## Runtime authority

The tested stable server/client runtime is official sing-box 1.13.20. Stable resolution must match both the GitHub release digest and the pinned tested digest:

| Official asset | SHA-256 |
|---|---|
| `sing-box-1.13.20-linux-amd64.tar.gz` | `646bc01bf128c32a12eb50d8690e387bba7504da7b1d65c704bd53916e38595a` |
| `sing-box-1.13.20-linux-arm64.tar.gz` | `7f8187b1d1d30258cd4fa70892eaa232649f8f28b294078eeac719579e14cf42` |
| `sing-box-1.13.20-linux-amd64-musl.tar.gz` | `ea5c79f74d88db43b58debbd510aac03e8c9432ed6de51b34f67271dddb5d05e` |
| `sing-box-1.13.20-linux-arm64-musl.tar.gz` | `ab37923ee950695edf25733c10e7381b368ab9069617727be06ebd1b1b0e031a` |

`stable` selects 1.13.20. `latest` resolves a non-draft, non-prerelease official release with a published SHA-256 digest. `pinned` requires an exact `x.y.z` official stable tag. An existing multi-instance runtime is never replaced implicitly while adding an instance; runtime replacement requires explicit `upgrade-runtime` and all instances must agree on the current version.

## Canonical server fields

Each named instance generates one sing-box inbound with these deliberate values:

| Field | NoBrand value |
|---|---|
| `type` | `tuic` |
| `listen` | selected real listener, normally `0.0.0.0` |
| `listen_port` | one non-`xx00` UDP port |
| `users[]` | independent `name`, RFC-4122 v4 `uuid`, random 48-hex-character `password` |
| `congestion_control` | `cubic` |
| `zero_rtt_handshake` | `false` |
| TLS | enabled, self-signed ECDSA P-256 certificate and 0600 key |
| TLS server name | configured SNI |
| ALPN | `h3` |
| outbound | direct |

The certificate lifetime is 3650 days and the instance stores its SHA-256 fingerprint and not-after value. TUIC certificates and keys are not shared with Hysteria2. Display Endpoint changes only `advertise_mode`, `advertise_host`, and `advertise_port`; they do not rewrite this server config, restart the process, alter the listener/firewall, rotate credentials, or replace TLS material.

ALPN `h3` is an explicit cross-client compatibility choice used by the tested sing-box and Mihomo configurations. Zero RTT remains disabled to avoid replay-sensitive early-data behavior. UDP relay mode is native. The Mihomo exporter caps `max-udp-relay-packet-size` at 1400; real UDP integrity tests cover 64, 512, 1200, and 1400 bytes.

## Export schemas

The sing-box outbound uses `type=tuic`, Display Endpoint host/port, UUID/password, `cubic`, native UDP relay, zero RTT disabled, and TLS with SNI, `insecure=true`, and ALPN `h3` for the self-signed certificate.

The Mihomo proxy uses `type: tuic`, Display Endpoint host/port, UUID/password, SNI, `alpn: [h3]`, `skip-cert-verify: true`, `reduce-rtt: false`, native UDP relay, cubic congestion control, and a 1400-byte UDP relay packet limit.

The parser/runtime authority for Mihomo qualification is v1.19.30, asset `mihomo-linux-amd64-v1.19.30.gz`, SHA-256 `cf06ce2c7d1421bdbda14ee4a5b6046672dc35ebf8eecd8e77504ec3c0ed9a84`.

No standardized TUIC v5 URI was confirmed in the upstream authorities. NoBrand deliberately returns no URI and never invents a `tuic://` format; Mihomo YAML and sing-box JSON are the canonical exports.

## Ownership and transactions

NoBrand owns only its exact sing-box binary/metadata, `nobrand-tuic@` template or exact OpenRC scripts, instance config/state/certificate, and recorded UDP firewall binding. It does not discover, reuse, stop, upgrade, or delete an external sing-box.

Install validates download digest, runtime version, certificate/config, service start, UDP listener, and same-process listener ownership before commit. User add/delete/rotate validates a complete candidate and preserves every other user. Shared runtime upgrade validates every config before replacement, snapshots binary/metadata/all states, remembers active instances, and rolls everything back if any restart, listener, ownership, or state commit fails. Backup restore re-resolves the exact recorded runtime version and also snapshots runtime/service-template side effects for rollback.
