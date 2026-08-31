# Final protocol scope after 3.1.0

```text
PROTOCOL_FEATURE_FREEZE=true
```

NoBrand-OneClick 3.1.0 has this final protocol and transport set:

| Product module | Runtime | Transport and scope |
|---|---|---|
| Mieru | official Mita runtime | TCP / UDP / BOTH; complete frozen 3.0 parity |
| Snell v5 | official Surge snell-server | TCP by default; optional same-port QUIC public UDP ownership |
| Snell v4 | official Surge snell-server | TCP compatibility |
| Hysteria2 | Xray-core | UDP, TLS, h3, Salamander |
| TUIC v5 | official sing-box | UDP/QUIC, TLS, UUID + password |
| VLESS/Sudoku | Xray-core | plain VLESS + FinalMask/Sudoku over TCP |
| SSH Tunnel | existing system OpenSSH sshd | `-L`/`-D`/`-R` TCP forwarding only |

Snell v5 defaults to QUIC public ownership **OFF**. Optional same-port UDP exposure does not prove the official QUIC Proxy Mode wire; that end-to-end mode remains **NOT VERIFIED**. For VLESS + FinalMask/Sudoku, the Xray reference client is supported; the exact Mihomo and sing-box combinations are unsupported.

Network Feature:

| Feature | Backends | Scope |
|---|---|---|
| Port Forward | nftables / Realm | TCP / UDP / BOTH; nftables IPv4 DNAT/MASQUERADE or Preserve Source; Realm IPv4/IPv6/domain userspace relay |

Explicitly unsupported:

- Snell v1, v2, v3 and v6;
- TUIC v1, v2, v3 and v4;
- hidden compatibility switches or legacy runtimes for those versions;
- VLESS Encryption, ML-KEM, xorpub, server tickets or encryption keypairs;
- native UDP/QUIC forwarding through SSH Tunnel;
- automatic import/migration of old Mieru-OneClick, legacy Mita or NoBrand 1.x state.

The state schema remains exactly `schema_version=3`. SSH Tunnel, TUIC, and Forward are optional modules; the absence of their state is valid and must not mutate a legal 3.0 installation.

The 3.x clean-break policy is explicit:

```text
LEGACY_USER_MIGRATION=false
LEGACY_STATE_IMPORT=false
LEGACY_AUTO_IMPORT=false
LEGACY_AUTO_DELETE=false
LEGACY_MITA_MANAGEMENT_WRAPPER=false
LEGACY_INSTALL_MITA=false
```

Common Port reserves the local tail-base `xx00` and allocates only `xx01-xx99`. Ownership is transport-aware (`tcp:P` / `udp:P`), so the same numeric port may be shared only when transport ownership does not conflict. Forward enforces the `xx00` rejection for nftables and Realm under TCP, UDP, and BOTH.

Forward support boundaries:

- nftables target scope is IPv4 literal only; `IPV6_FORWARD_SUPPORT=UNSUPPORTED` for 3.1.0;
- Realm targets may be IPv4, IPv6, or domain and domains remain domains at runtime;
- automatic failover, traffic dog/Telegram, MPTCP management, raw external Realm import, and dual-host Realm deployment are intentionally outside the 3.1 core scope;
- after 3.1.0, protocol and network-feature expansion is frozen under `PROTOCOL_FEATURE_FREEZE=true`.

Maintenance policy after release:

```text
3.1.x = bugfix / security / compatibility
3.2.x = UI / exporter / Doctor / management improvements
```

Adding another protocol is outside the frozen scope and requires an explicit future product decision rather than an incidental patch.
