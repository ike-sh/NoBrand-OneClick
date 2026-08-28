# NoBrand-OneClick 1.1.0 Release Notes

Release date: 2026-08-27

## Highlights

- Adds **VLESS + FinalMask + Sudoku over TCP** as a plain VLESS deployment backed by Xray-core. VLESS Encryption remains disabled and is not an installation dependency.
- Unifies Mieru, Snell, Hysteria2, and VLESS/Sudoku node, status, Doctor, backup, endpoint, and lifecycle management while preserving each protocol's ownership boundary.
- Keeps `src/` as the only development source and deterministically generates four byte-identical compatibility installers.

## Supported protocols

| Protocol | Product status | Canonical transport |
|---|---|---|
| Mieru | Supported | TCP / UDP / BOTH |
| Snell v4 | Compatibility | TCP |
| Snell v5 | Recommended / Default | TCP |
| Snell v6 | Experimental | TCP |
| Hysteria2 | Supported | UDP |
| VLESS/Sudoku | Supported | TCP |

Snell v5 uses the official Surge `snell-server`. Some official v5 builds open a same-port UDP auxiliary socket from the same process. NoBrand reports this as upstream runtime behavior; it does not enable or manage QUIC Proxy Mode, and canonical ownership remains TCP.

## Compatibility

- The existing `install-mita` and `mita` commands remain available for Mieru workflows.
- `install-nobrand`, `nobrand`, and `nb` provide the unified 1.1.0 interface.
- HY2 and VLESS/Sudoku share the NoBrand-owned Xray binary, but keep separate configs, state, services, processes, and PIDs.
- Existing `/etc/xray`, `xray.service`, `/usr/local/bin/ike`, unknown firewall rules, and the Mieru state namespace are outside top-level NoBrand uninstall ownership.

## Important changes

- The Common Port contract reserves the default-route IPv4 tail-base `xx00` for external NAT/DNAT, SSH, or management use that may be invisible inside the guest. Automatic allocations use `xx01-xx99`; explicit TCP and UDP requests for `xx00` are also rejected.
- **Real Endpoint** is the server's actual listener. **Display Endpoint** is the client-facing host and port used only by node exports and views. Updating Display Endpoint does not change or restart the listener, service, firewall, `tc`, or quota configuration.
- Explicit `enabled=false` state is preserved by all NoBrand protocol state getters.
- The build now rejects omitted or duplicate `src/*.sh` manifest entries.
- `nobrand --version` reports the product version and author; unknown or surplus top-level arguments fail instead of entering an unrelated menu.

## Validation

- Deterministic build, Bash syntax, warning-level ShellCheck, unit, lifecycle, rollback, ownership, runtime resolver, real Xray config, and localhost FinalMask/Sudoku data-plane tests are release gates.
- Real IPLC/Debian validation covered status, nodes, Doctor, true-TTY menus, public SSH protection, endpoint isolation, backup/restore, remove/reinstall, shared Xray isolation, and public data plane.
- The full evidence and retained failure/retest history are in [REAL-LAB-VALIDATION.md](REAL-LAB-VALIDATION.md).

## Known limitations

- Snell v6 remains Experimental. It passed an initial public-path validation, but the maintainer's final simultaneous IPLC runs showed environment-dependent payload filtering after the TCP handshake. Local config/runtime/listener validation and localhost wire testing still passed. This is neither a universal Snell v6 failure nor a production-path guarantee.
- Snell v5's auxiliary UDP socket was observed, but UDP relay application E2E was not run; NoBrand 1.1.0 does not manage that mode.
- Snell v6 does not generate Mihomo configuration. Alpine v6 remains unsupported while the official binary requires glibc/libstdc++.
- Existing `shfmt -d -i 2 -ci` differences are advisory and are not a release blocker; no large mechanical `shfmt -w` rewrite was performed.

## Upgrade notes

- Back up current Mieru data with the established Mieru backup flow and NoBrand-owned Snell/HY2/VLESS/Common data with `nobrand backup create` before upgrading.
- Review `xx00` listener choices: a prior manually chosen tail-base port must be moved into `xx01-xx99` or another free non-reserved port.
- For `-y` installs and endpoint updates, provide either a complete `--advertise-host HOST --advertise-port PORT` pair or `--advertise-auto`.
- Re-run `nobrand doctor` after upgrade. Snell v6's Experimental classification does not depend on whether the currently resolved upstream asset is Beta, RC, or GA.
