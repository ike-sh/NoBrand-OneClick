# CI fixture capabilities

The ordinary harness stays at its caller's EUID. `tests/helpers/root_fixture.py`
is the single executor for the nine registered mandatory fixture boundaries.
It accepts fixture identifiers, never arbitrary commands.

## Inventory

Categories: A = ordinary temporary files/rendering; B = simulated privileged
effects; C = uid 0 / protected ownership in temporary files. No active CI fixture
requests host service management, network namespaces, packages or host mutation.

| Test entrypoint | Category | Needs uid 0 | Namespace sufficient | sudo sufficient | Reason / boundary |
|---|---|---|---|---|---|
| test_splicore_runtime.sh | A/C | One Python method | Yes | Yes | Only `RuntimeTests.test_product_restore_snapshots_stopped_primary_and_restores_generation`; actual backup/restore and ownership, fixture service driver |
| test_splicore_legacy_refusal.sh | A | No | — | — | Refusal parsing |
| test_splicore_fresh.sh | A/B | No | — | — | Isolated Python state/adapter fixtures |
| test_splicore_cert_lifecycle.sh | A/B | No | — | — | Isolated certificate fixtures |
| test_splicore_shell_surface.sh | C | Yes | Yes | Yes | Real manager bootstrap root guard; redirected manager commands, dependency installation mocked |
| test_splicore_rc4_contract.sh | A | No | — | — | Release contract |
| test_splicore_qualification.sh | A/B | No | — | — | Qualification/diagnostic and synthetic executor tests |
| test_architecture_audit.sh | A | No | — | — | Static architecture checks |
| test_repository_sanitization.sh | A | No | — | — | Literal/secret checks |
| test_schema_v3.sh | C | Yes | Yes | Yes | Manager upgrade validates protected installer ownership; filesystem roots redirected |
| test_common_port.sh | A | No | — | — | Port selection fixtures |
| test_ingress_profiles.sh | C | Yes | Yes | Yes | Actual ingress mutation root guard, temporary state and lock |
| test_ingress_interactive.sh | B | No | — | — | Root guard and administration callbacks explicitly mocked |
| test_ingress_enforcement.sh | C | Yes | Yes | Yes | Actual ingress root guard; rules generated as files, no host firewall apply |
| test_ingress_enforcement_transaction.sh | C | Yes | Yes | Yes | Actual ingress root guard; owner apply callbacks mocked |
| test_forward.sh | A/B | No | — | — | State/rule rendering |
| test_forward_transaction.sh | B | No | — | — | Transaction callbacks |
| test_forward_sysctl.sh | B | No | — | — | sysctl reads/writes mocked |
| test_forward_ownership.sh | B | No | — | — | nft/service commands mocked |
| test_ssh_tunnel.sh | A/C | Yes | Yes | Yes | Endpoint update calls real watchdog ownership preflight; all SSH files redirected, no service/account mutation |
| test_ssh_tunnel_transaction.sh | C | Yes | Yes | Yes | Real uid-0 watchdog/key ownership; temporary SSH config, fake sshd/PIDs, reload/account mutations mocked |
| test_vless_sudoku_golden.sh | A | No | — | — | Golden config rendering |
| test_vless_sudoku_encryption_absence.sh | A | No | — | — | Config validation |
| test_vless_sudoku_lifecycle.sh | B | No | — | — | Service/root/runtime/listener/firewall effects mocked |
| test_cli.sh | A | No | — | — | CLI parsing |
| test_menu.sh | B | No | — | — | Menu callbacks mocked |
| test_menu_lifecycle_lock_scope.sh | B | Yes | Yes | Yes | Actual main() takes the initial lifecycle lock only at uid 0; bootstrap mocked, real temporary flock/signals/FD assertions retained |
| test_menu_instance_selection.sh | B | No | — | — | Selection callbacks |
| test_version_consistency.sh | A | No | — | — | Static version checks |
| test_localization.sh | A | No | — | — | Localization checks |
| splicore_rc4_probe.py | A/B | No | — | — | Temporary loopback/supervisor fixture, all 42 checks retained |

Namespace compatibility applies only to the audited fixture operations: mapping
the caller to uid/gid 0 supports their temporary file ownership checks and root
guards. It does not prove host root, host networking or native service operation.

## Executor contract

1. Current EUID 0: direct child, without sudo recursion.
2. Fixed system-path `sudo -n --`: accept only after a bounded child probe reports
   EUID 0 and successfully creates/chowns/chmods a temporary file.
3. Fixed system-path `unshare --user --map-root-user`: probe the same operations
   only when the individual fixture declares namespace compatibility.
4. Unavailable: do not enter the fixture. Required CI fixtures return 78 with
   `QUALIFICATION_ENVIRONMENT`. A genuinely optional future platform fixture may
   report `OPTIONAL_UNAVAILABLE`; all nine current entries are required.

The child confirms EUID again immediately before fixture execution. A lost root
context returns 78. Executor/cleanup faults return 70 and `TEST_HARNESS_DEFECT`.
Fixture assertion failures retain the fixture exit code and `FIXTURE_FAILED`;
this alone does not establish a product defect. Qualification preserves the
structured environment/harness classification rather than classifying every
nonzero regression exit alike. Successful CI requires all nine complete root
records as well as the original regression completion and coverage gates.

## Security and evidence

Probes never modify host configuration, services, accounts or firewall. The
executor uses `env -i`, a fixed system PATH, fixed locale and Python bytecode
suppression. Child HOME/TMPDIR/system/lifecycle/command paths and the two internal
fixture markers are constructed under new private temporary directories. Tokens,
credentials, shell functions and SSH agents are not inherited. There is no
`sudo -E`, interactive sudo or sudoers modification. Runner sudo is probed; no
additional package is installed for this mechanism.

Privileged tests read a disposable copy of the installer, src, runtime and tests;
they do not execute from or write into the original checkout. Existing fixture
redirections and service/account mocks remain in effect. A short temporary root
for the restore method preserves the product's Unix socket path limit. The child
removes its temporary state and source copy; the parent verifies checkout file
ownership before/after. This depends on the audited fixture mocks/redirections:
it is not an OS sandbox for arbitrary root programs.

The original user writes private `privilege.jsonl` records. The existing seven
sanitized artifact files project only known enums, booleans and integers from
these records, including executor, child EUID, probe exit/identity, requirement,
outcome, cleanup and ownership checks. Probe stderr and environment dumps are
not published. `SYSTEMD`, network namespace and nft capabilities remain separate
`NOT_REQUESTED` facts. Native systemd/OpenRC/arm64 remain pending environment;
nftables port range is N/A — NOT EXPOSED.

The #27 failure proved the old harness continued without root. Neither the exact
historical unshare failure cause nor the unrecoverable #26 cause is established.
