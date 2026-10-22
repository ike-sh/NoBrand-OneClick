# NoBrand-OneClick Test Harness Root Capability Fix Report

## Product Candidate

`e90695ba8d2ac98a443d6aa53edd7653356377b2`

Product Files Modified: **0 / 44**. All 44 candidate SHA256 hashes were checked.

## Diagnostics Baseline

Diagnostics Commit: `ae6f666addbe67112f7e6d8939646cf25fe618ca`

CI Run: [39727934124, attempt 1](https://github.com/ike-sh/NoBrand-OneClick/actions/runs/39727934124)

Historical Classification: **TEST_HARNESS_DEFECT**, unchanged.

The diagnostics commit remains a distinct ancestor. Its private capture,
always-run sanitized publication/upload, seven-file allowlist and final original
exit propagation remain intact. The workflow is unchanged in this fix.

## Defect

Observed root-required failure: `tests/test_splicore_shell_surface.sh:21` calls
`nobrand_manager_bootstrap`, which calls the product `require_root`. Run #27 had
parent EUID 1001, did not obtain root, and continued to the fixture. The separate
Python restore fixture skipped on nonzero EUID.

Previous acquisition: `scripts/test.sh` attempted to reexecute the entire suite
under `unshare --user --map-root-user`; failure fell through into mandatory root
fixtures. There was no sudo negotiation or explicit environment result.

Exact historical unshare cause: **UNKNOWN**. The observed AppArmor flag does not
prove causality. Original #26's precise failure remains unreconstructable.

Final audited boundaries (all mandatory; namespace and sudo sufficient for the
redirected fixture operations, no host root/service/network qualification):

| Fixture | Actual requirement |
|---|---|
| `test_splicore_shell_surface.sh` | Actual bootstrap root guard, temporary manager commands/state |
| `test_schema_v3.sh` | Actual protected installer/file ownership checks |
| `test_ingress_profiles.sh` | Actual ingress mutation root guard and temporary lock |
| `test_ingress_enforcement.sh` | Actual ingress root guard; firewall rules are files only |
| `test_ingress_enforcement_transaction.sh` | Actual ingress root guard; owner callbacks mocked |
| `test_ssh_tunnel.sh` | Endpoint mutation invokes actual watchdog directory ownership preflight |
| `test_ssh_tunnel_transaction.sh` | Actual uid-0 watchdog/key ownership, fake SSH service and identities |
| `test_menu_lifecycle_lock_scope.sh` | Actual main() initial lock branch is conditional on uid 0; retain real flock/FD/signal assertions |
| `RuntimeTests.test_product_restore_snapshots_stopped_primary_and_restores_generation` | Actual product restore, root-owned temporary transaction roots, fixture service driver |

The complete 30-entrypoint inventory and capability/security contract are in
[`docs/CI-ROOT-FIXTURES.md`](../CI-ROOT-FIXTURES.md).

## New Capability Model

Canonical executor: `tests/helpers/root_fixture.py`, fixed fixture identifiers.

Priority: **direct root → verified noninteractive sudo → proven compatible user
namespace → unavailable**.

Direct Root: no sudo recursion; child EUID checked again before entry.

sudo: fixed system PATH; bounded `sudo -n --` child probe confirms actual EUID 0
and temporary create/chown/chmod, then executes a controlled child. No extra
sudo package was added. Ubuntu availability is probed, never inferred from
`GITHUB_ACTIONS`.

User Namespace: attempted only for explicitly compatible fixtures, after sudo.
Probe records executable presence, exit code, EUID and ownership operation.
This validates temporary uid-0 ownership simulation, not host root capabilities.
Unprobed availability is null/omitted rather than reported as a proven absence.

Unavailable: mandatory fixture never starts; executor returns 78 and structured
`QUALIFICATION_ENVIRONMENT`. Qualification itself preserves its existing final
exit 1 on failure, with the classification retained in sanitized artifacts.

Executor/internal cleanup failure: exit 70, `TEST_HARNESS_DEFECT`. A fixture
assertion failure retains its own exit and `FIXTURE_FAILED` / `TEST_FAILURE`;
that alone does not prove a product defect. Root confirmation loss is explicitly
an environment failure. Native systemd, network namespace and nft capability
facts remain separate `NOT_REQUESTED` values.

## Mandatory Fixture Policy

All nine entries are mandatory. No coverage skips or allowed failures were
introduced. The Python restore skip was replaced by controlled delegation of
only that method, retaining all original restore/rollback assertions. Successful
CI now additionally requires nine complete PASS/EUID-0/cleanup/ownership records.

An optional-policy unit test verifies explicit `OPTIONAL_UNAVAILABLE` semantics;
no current mandatory fixture uses that policy. Original coverage thresholds are
retained, with the new root unit batch required separately.

## Security

Entire Suite Runs As Root: **NO**. Only the audited child boundaries request it.

Narrow Privilege Boundary: **PASS**.

Secrets Preserved Through sudo: **NONE**. Only constructed safe variables are
passed through `env -i`: fixed PATH/locale/bytecode policy and private temporary
HOME/TMPDIR/system/lifecycle/command roots plus internal fixture markers. No
token, credential, shell function or SSH agent propagation; no `sudo -E`,
password prompt, `sudo -S` or sudoers edits.

Checkout Root-owned Files: **NONE introduced**. Privileged children run against
new disposable source copies; original checkout ownership is checked before and
after each fixture. A short dedicated restore root respects Unix socket limits.
The ignored historical `.codex-backup` directory already contained root-owned
files; those were preserved. The final tracked/nonignored checkout scan has no
root-owned files. No historical backup ownership was changed.

Host Mutation: **NONE outside approved temporary fixture state/loopback**.
Existing package/service/account/firewall mocks and redirects remain intact.
This executor is for audited fixtures, not an OS sandbox for arbitrary commands.
Docker, Redis, TeleLedger and production hosts were not used.

The existing seven public artifact files contain only typed projected capability
facts. Probe stderr, arbitrary private JSON, identities and environment dumps are
not newly exposed.

## Tests

Direct root, sudo, sudo unavailable, namespace supported/failure, mandatory and
optional policy, child root confirmation, fixture failure exit propagation,
cleanup, clean environment, original root guard/fallthrough reproduction,
qualification classification and typed sanitized publication: **20 new tests PASS**.

The original diagnostics/qualification helper's 27 tests remain passing.

Two local full-campaign discovery failures were preserved without rewriting:

- `local-ci`: SSH endpoint's real watchdog ownership preflight exposed an omitted
  root boundary; the canonical registration and inventory were corrected.
- `local-ci-final`: the menu test's actual uid-conditioned initial lock branch
  required a root boundary; its real assertions were retained and the fixture
  was registered. No precreated lock or mocked guard bypass was introduced.

The added boundaries passed targeted tests. A third full campaign ran the final
reviewed source in `local-ci-complete`.

Full Bash: **30 PASS**.

Python: **106 PASS**, batches [27, 10, 22, 27, 20].

Runtime: **42 / 42 PASS**, temporary loopback only.

Shell syntax: **113 PASS**.

ShellCheck: **PASS**. Build consistency: **PASS**. Actionlint: **PASS**.
Secret Scan: **PASS**. `git diff --check`: **PASS**.

The preexisting optional real Sudoku Xray validation remains outside the rc.4
campaign unless `NOBRAND_XRAY_TEST_BIN` is supplied. No required Python, manager,
runtime or quality gate was skipped.

Local actual executor: **namespace**, parent EUID 1000; sudo -n probe failed,
namespace child EUID/ownership probe passed. All nine child EUIDs were 0,
cleanup passed, and checkout ownership remained unchanged.

## Harness Commit

Commit: `70b84eda8601bf9ba01528fa950ad47b339f370f`

Sole Parent: `ae6f666addbe67112f7e6d8939646cf25fe618ca`

Exactly one fix commit, explicitly staged nine reviewed files. Historical
uncommitted qualification reports and this final report were not staged.

## New Remote CI

Run: [39734118466 / #28](https://github.com/ike-sh/NoBrand-OneClick/actions/runs/39734118466), attempt 1, job 119675727988.

Workflow: **NoBrand rc.4 validation** (`330225927`).

Branch: `codex/ci-diagnostics-e90695`; event: `push`.

SHA: `70b84eda8601bf9ba01528fa950ad47b339f370f`.

Privilege Executor Selected: **sudo**.

Result: **PASS**.

Runner parent EUID: **1001**. All nine required root children used verified
noninteractive sudo with EUID **0**; every sudo identity/ownership probe exited
0. Every fixture outcome/cleanup/checkout ownership check passed. Namespace
availability was not assumed or needed.

Sanitized metadata confirms 30 Bash entrypoints and Python batches
`[27, 10, 22, 27, 20]` (106 total), with the final suite completion marker.
The unchanged strict campaign also enforced all 42 runtime checks and quality
gates. All captured command exits were 0; qualification exit was **0**. All 11
job steps succeeded, including tracked diff rejection, always-run publication,
artifact upload and final exit propagation. No hidden or allowed failure.
The sanitizer masks the leading free-text PASS label; explicit typed result
PASS and exit 0 remain intact.

Artifact: `splicore-rc4-ci-diagnostics-39734118466-1`, ID `12405829939`.

ZIP SHA256: `a755fb10882c354c0b24bf86b00ba121ce92a35c1dd66c720518b284f6aa63a7`; exact seven safe files validated and retained under
`.lab/root-capability-ae6f666/remote-public/`.

## Failure Classification

**NONE.** The new run passed. Historical #27 remains TEST_HARNESS_DEFECT.

No further fix was stacked after observing the remote result.

## Product Integrity

e90695 product tree: **UNCHANGED, 44/44 hashes**.

Historical protection: **25 tracked report hashes, four existing untracked report
hashes, and 192 preexisting private evidence file hashes unchanged**.

main: `e90695ba8d2ac98a443d6aa53edd7653356377b2`.

origin/main and live remote main: same e90695 SHA.

## Qualification Debt

Native systemd: **PENDING ENVIRONMENT**.

OpenRC: **PENDING ENVIRONMENT**.

arm64: **PENDING ENVIRONMENT**.

nftables port range: **N/A — NOT EXPOSED**.

Checkout action Node warning: **CI MAINTENANCE DEBT**, no unrelated upgrade.

## Git

Diagnostics Branch Pushed: **YES**, one fast-forward, exact fix SHA.

Main Pushed: **NO**. Merge: **NONE**. Tag: **NONE**. Release: **NONE**.

Final evidence report remains uncommitted for maintainer review. The original
four untracked reports remain present and untouched.

## Final Result

**TEST HARNESS ROOT FIX VALIDATED — REMOTE CI PASS**

Stopped after this result; no product fix, merge or native campaign started.

## CI Infrastructure Freeze Handoff (2026-10-22)

The sections above preserve the completed harness phase at
`70b84eda8601bf9ba01528fa950ad47b339f370f`, including its then-uncommitted
report and unmerged-main state. The #28 PASS and #27 TEST_HARNESS_DEFECT
conclusions are unchanged; #26's exact historical cause remains unknown.

Freeze preparation rechecked #28 against the GitHub run/job/artifact APIs:
workflow `330225927`, exact harness SHA, branch `codex/ci-diagnostics-e90695`,
all 11 steps successful, artifact `12405829939`, and matching SHA256
`a755fb10882c354c0b24bf86b00ba121ce92a35c1dd66c720518b284f6aa63a7`.
The product tree remains byte-identical to e90695 (44/44 files).

This report and the diagnostics report are archived together in exactly one
documentation-only child of the harness commit, following existing repository
reporting practice. Its actual SHA, the fast-forward integration and fresh
**main** CI evidence are recorded separately in
`SPLICORE_RC4_CI_INFRASTRUCTURE_FREEZE_REPORT.md`. Branch #28 is baseline evidence
and does not substitute for that final main run. Native systemd, OpenRC and
arm64 remain **PENDING ENVIRONMENT**; nftables range remains
**N/A — NOT EXPOSED**. No tag or release is authorized in this phase.

Final freeze-phase local rerun: **PASS** on the unchanged harness commit;
30 Bash, 106 Python (27 + 10 + 22 + 27 + 20), 42 runtime, 113 shell syntax.
ShellCheck, build consistency, repository secret/redaction scan, pinned
actionlint, and workflow contract passed. All nine namespace children had EUID
0, successful cleanup and unchanged checkout ownership. The original optional
Sudoku Xray check remains outside this campaign; no required gate was skipped.
