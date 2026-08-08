# Changelog

## v2.2.0

- Added IPLC/dedicated-line, general public network, enhanced camouflage, and advanced custom profiles while continuing to save the complete concrete Mieru parameters.
- Separated the client-facing endpoint from the backend listener, including IPv4, IPv6, and domain-name exports for IPLC, NAT, port mapping, and other front-end deployments.
- Added read-only `mita perf` diagnostics for Mieru settings, kernel and network state, endpoints, resources, processes, and OneClick-owned traffic limits.
- Strengthened uninstall ownership protection so packages, accounts, firewall rules, and traffic-control resources that OneClick did not create are preserved.
- Modularized the development source under `src/`; releases remain the generated, directly executable single-file `install-mita.sh`, with no runtime dependency on the source modules.
- Expanded migration, lifecycle, export, and Debian/Ubuntu/Rocky/Alpine compatibility coverage. Existing users, state data, and command interfaces remain compatible; upgrading does not overwrite concrete Mieru parameters or saved endpoint values.
