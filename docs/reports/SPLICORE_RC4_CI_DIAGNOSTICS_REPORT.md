# NoBrand-OneClick Splicore rc.4 CI Diagnostics Report

Date: 2026-10-22 (Asia/Shanghai)

## Product Candidate

Commit: `e90695ba8d2ac98a443d6aa53edd7653356377b2`

Product Changes: **NONE** — all 44 product implementation files remain byte-identical to this candidate. The candidate's sole parent is `b5440ec41aeed2dd266b3a7008f75a26de63add2`.

## Original Run

Run: [39723136658 / #26 / attempt 1](https://github.com/ike-sh/NoBrand-OneClick/actions/runs/39723136658)

Result: **FAIL**, exact candidate on `main`; public qualification exit code 1.

Useful Failure Artifact: **NONE**. The available summary only said `command failed; inspect private log: regression.log`, with legacy classification `TEST_HARNESS`.

Root Cause: **UNKNOWN for the historical run itself**. Its lost regression log cannot be reconstructed. The diagnostics run below identifies an actual failure with the same product bytes; it does not retroactively prove the exact failure point of #26.

## Diagnostics Fix

Branch: `codex/ci-diagnostics-e90695`

Commit: [`ae6f666addbe67112f7e6d8939646cf25fe618ca`](https://github.com/ike-sh/NoBrand-OneClick/commit/ae6f666addbe67112f7e6d8939646cf25fe618ca)

Sole Parent: `e90695ba8d2ac98a443d6aa53edd7653356377b2`

Commit Count above Candidate: **1**

Product Files Changed: **0**

| Workflow / harness file | Diagnostic-only change |
| --- | --- |
| `.github/workflows/ci.yml` | Capture status; always publish and upload safe evidence; finally restore status. Quiet tracked-diff rejection avoids raw diff disclosure. |
| `scripts/ci-diagnostics.py` | New private capture, conservative redaction, explicit public projection, environment metadata, missing-evidence handling and final exit propagation. |
| `scripts/qualify-splicore.py` | Retain private per-command status/argv/timing metadata and update the workflow safety contract. |
| `tests/helpers/test_splicore_qualification.py` | Add 14 diagnostics tests; preserve the original 13 tests unchanged. |

The campaign, static product checks, regression summary assertions and qualification CLI main function are AST-identical to the candidate. `scripts/test.sh`, product test selection and product expectations are unchanged. No dependency, retry, permission, network check or product behavior was changed.

## Diagnostics Improvements

| Requirement | Result / evidence |
| --- | --- |
| Exit Code Preservation | **PASS** — qualification exit 1 and inner regression exit 1 retained. A fixture also preserved qualifier exit 9 separately from inner command exit 23. |
| Always-Run Summary | **PASS** — publication step succeeded in the failing remote run. |
| Sanitized Regression Log | **PASS** — downloaded and inspected `regression.sanitized.log`. |
| Artifact on Failure | **PASS** — official `actions/upload-artifact` succeeded before final failure. |
| Final Failure Propagation | **PASS** — final step exited 1; job and run concluded failure. |
| Missing Evidence Handling | **PASS** — local tests cover missing summary/log/status and partial JSON. Known failure status survives missing evidence; missing status fails closed. |
| Secret Redaction | **PASS** — synthetic password, PSK, token, Salamander, private-key, UUID, authorization, URI, environment-secret and PEM fixtures are absent from public files and publisher console. |

Raw qualification, command and runtime logs stay private. Only these seven named files can upload:

- `summary.json`
- `failure-summary.json`
- `regression.sanitized.log`
- `qualification-console.sanitized.log`
- `command-diagnostics.sanitized.log`
- `environment-summary.json`
- `test-result-metadata.json`

There is no whole-directory archive, raw log upload, `continue-on-error`, test skip addition, or pipe/tee status ambiguity. The capture step deliberately completes after recording the qualification result; its green step status does not mean qualification passed. Final propagation determines its failure after evidence upload. Setup, publication or upload errors also remain failures.

The upload action is pinned to official `actions/upload-artifact` v4.6.2 commit `ea165f8d65b6e75b540449e92b4886f43607fa02`, verified against the official Git tag/API. Token permissions remain `contents: read`. Existing checkout was not upgraded. Both actions emitted the Node 20 compatibility warning while executing successfully under the runner's Node 24 compatibility behavior: **CI MAINTENANCE DEBT**, not the regression cause.

### Local verification

Full qualification: **PASS: LOCAL CI AND LOOPBACK REGRESSION**.

| Gate | Actual result |
| --- | --- |
| Bash entrypoints | 30 |
| Python tests | 86 = 27 + 10 + 22 + 27; no Python skips locally |
| Runtime checks | 42 |
| Shell syntax | 113 files |
| ShellCheck / generated build consistency / repository secret scan | PASS |
| Pinned actionlint / `git diff --check` | PASS |
| Diagnostics tests | 27 total: original 13 + new 14 |
| Real successful evidence publication / final status | PASS / exit 0 |

The existing optional specialized Sudoku Xray validation remains outside the rc.4 campaign; its existing optional skip was not changed. No native service qualification is implied.

## New CI Run

Run: [39727934124 / #27 / attempt 1](https://github.com/ike-sh/NoBrand-OneClick/actions/runs/39727934124)

Workflow: `NoBrand rc.4 validation`, `.github/workflows/ci.yml`, ID `330225927`.

Job: [`regression`, ID 119656072450](https://github.com/ike-sh/NoBrand-OneClick/actions/runs/39727934124/job/119656072450)

Branch: `codex/ci-diagnostics-e90695`

SHA: `ae6f666addbe67112f7e6d8939646cf25fe618ca`

Event: `push`; created `2026-10-22T05:25:23Z`, completed `2026-10-22T05:28:11Z`.

Result: **FAIL**. Summary generation and artifact upload both **succeeded**. Final status propagation **failed with the original exit code 1**, as required. No rerun was performed; the one-rerun authorization only applied if the first run passed.

## Captured Failure

Classification in generated metadata: `UNKNOWN` — legacy `TEST_HARNESS` is intentionally not treated as proof of a root-cause class.

Classification after evidence/code review: **TEST_HARNESS_DEFECT**.

Suite: `tests/test_splicore_shell_surface.sh`.

Case: no named Bash case marker exists. Source review maps the failure to the native manager bootstrap call at **line 21**.

Commands:

1. `bash scripts/test.sh --runtime` — recorded regression subprocess.
2. `bash tests/test_splicore_shell_surface.sh` — last observed suite.
3. `nobrand_manager_bootstrap >/dev/null` — fixture call at line 21; it invokes `require_root` in `src/80-lifecycle.sh:17`.

Exit Code: qualification **1**, regression subprocess **1**; timeout **false**.

Sanitized stderr/stdout retained in the artifact:

```text
[RUN] tests/test_splicore_shell_surface.sh
[错误] 需要 root 权限，请使用 sudo 运行
```

The generic `sanitized_message` field did not recognize this localized error as a named assertion. The preserved sanitized log supplies the exact diagnostic; `failing_case` remains null rather than inventing a case name.

Artifact: **12403828067**, `splicore-rc4-ci-diagnostics-39727934124-1`, 4,910 bytes, exactly the seven reviewed files. Available from the run's artifact section; expiry `2026-11-05T05:28:07Z`.

Downloaded ZIP SHA256, matching the GitHub artifact digest:

`fc7d60f5510c3f94e50147c1a56d45b6bbc86c66b972a143391f73cb4df08ab6`

## Root Cause Decision

Classification: **TEST_HARNESS_DEFECT**.

Evidence:

1. `scripts/test.sh:4-8` tries `unshare --user --map-root-user` for a non-root caller. If that path is unavailable or unsuccessful, execution falls through into the complete suite without enforcing its required root prerequisite. Its probe stderr is discarded.
2. The remote environment reports Ubuntu **24.04**, kernel `6.17.0-1022-azure`, architecture `x86_64`, Python **3.12.3**, runner EUID **1001**, image `20261012.334.1`.
3. Independently of the parent environment metadata, the test child reported `test_product_restore_snapshots_stopped_primary_and_restores_generation ... skipped` and `OK (skipped=1)`. Its unchanged implementation at `tests/helpers/test_splicore_runtime.py:435-436` skips specifically when `os.geteuid() != 0`. The suite therefore did not obtain its required root identity.
4. `tests/test_splicore_shell_surface.sh:21` then enters the real manager bootstrap without a privilege fixture. `src/80-lifecycle.sh:17` calls the unchanged `require_root`; `src/15-core-state.sh:1218-1227` rejects non-root and emits the exact captured message. This is expected product privilege enforcement.
5. Thus the harness continues with an unmet privilege prerequisite, allowing one required test to skip and a subsequent fixture to fail. The CI execution contract currently does not guarantee the root identity those fixtures require. A separate harness/CI fix phase must address this contract; this phase makes no such change.

Runner metadata also reports `unprivileged_userns_clone=1` and `apparmor_restrict_unprivileged_userns=1`. These are context, **not proof of a specific unshare denial**. The exact unshare exit/errno and whether AppArmor caused it were not captured by the unchanged harness. No precise kernel-policy cause is asserted.

Remote progress: the first four Bash entrypoints completed and the fifth failed. Python reported **59** tests (27 + 10 + 22), including **one existing root-dependent skip**; the added diagnostics unit suite and real runtime probe were not reached remotely. The strict qualification summary still rejects Python skips and was not weakened.

No product implementation defect, network transient, missing package or upstream artifact failure is established by this failure. Dependencies, pinned workflow validation, strict static checks, public asset validation, Bash syntax, ShellCheck and generated-build consistency completed before the captured fixture failure. The Node warning is unrelated maintenance debt.

## Product Integrity

e90695 Product Tree: **UNCHANGED**, 44/44 SHA256 matches, explicit product-path Git diff **empty**.

Local `main`, `origin/main` and live remote `refs/heads/main`:

`e90695ba8d2ac98a443d6aa53edd7653356377b2`

Diagnostics local/remote branch:

`ae6f666addbe67112f7e6d8939646cf25fe618ca`

Preserved evidence:

- All **25** tracked historical reports remain byte-identical.
- All **128** existing private evidence files inventoried at phase start remain byte-identical.
- Existing uncommitted reports remain untracked, unchanged, and excluded from the CI commit:

| File | SHA256 |
| --- | --- |
| `SPLICORE_RC4_SECOND_QUALIFICATION_REPORT.md` | `a78f60e36311da1f04c3f25146e9ba1c2c8f637aaeb05e190c60ecd84cdaf31a` |
| `SPLICORE_RC4_SECOND_QUALIFICATION_EVIDENCE.json` | `7cb1145ac774f2db6db98debead21487c10f2240c8ce9a45d8be1473b789b77c` |
| `SPLICORE_RC4_REMOTE_CI_EXECUTION_REPORT.md` | `99b4899c5616bfe5f3b92a02943ef2c23c2db77844473dfcb4d45432612e2db3` |

The old qualification summary's three authorized certificate-file differences are relative to **b5440ec**, predating this phase. They are not diagnostics-phase product modifications; comparison to **e90695** yields zero.

## Qualification Debt

Native systemd: **PENDING ENVIRONMENT**.

OpenRC: **PENDING ENVIRONMENT**; shell syntax/static template checks do not certify native runtime.

arm64: **PENDING ENVIRONMENT**; no native runtime certification.

nftables range: **N/A — NOT EXPOSED**.

Prior result remains **SECOND QUALIFICATION PARTIAL — ENVIRONMENT PENDING**. This CI run does not upgrade it to full qualification.

## Remote

Diagnostics Branch Pushed: **YES**, exact commit, non-force, no follow-tags.

Main Pushed: **NO**.

Merge: **NONE**.

Tag: **NONE created or pushed**.

Release: **NONE**.

This report is intentionally **uncommitted**. No underlying product, harness or runner-privilege fix was attempted after capture. No native qualification was started.

## Evidence Location

Private local root: `.lab/ci-diagnostics-e90695/`.

Key files: `preflight.json`, `flow-audit.md`, `scope-audit.json`, `local-ci/summary.json`, `diagnostics-tests-final.log`, `local-publication/public/`, `staged-review.json`, `product-tree.diff`, `run-final.json`, `jobs-final.json`, `artifacts.json`, `diagnostics-artifact.zip`, `remote-public/`, `root-cause-decision.json`, `final-integrity.json`.

Raw remote job output is retained privately as `remote-run.log`; the public evidence is the seven sanitized/projected files in `remote-public/`.

## Final Result

**CI DIAGNOSTICS COMPLETE — TEST HARNESS DEFECT IDENTIFIED**

Stopped after recording and classifying the failure. Maintainer review is required before a separate fix phase.

## CI Infrastructure Freeze Handoff (2026-10-22)

The sections above preserve the diagnostics phase at
`ae6f666addbe67112f7e6d8939646cf25fe618ca`, including its then-uncommitted
report and unmerged-main state. Those are historical statements. The #26 root
cause remains **UNKNOWN**; #27 remains **TEST_HARNESS_DEFECT**.

The separately reviewed fix is
`70b84eda8601bf9ba01528fa950ad47b339f370f`, whose sole parent is the diagnostics
commit. [Run #28 / 39734118466](https://github.com/ike-sh/NoBrand-OneClick/actions/runs/39734118466)
passed on that exact fix SHA using controlled sudo: nine mandatory root children
had EUID 0, qualification exit 0, and successful cleanup/ownership checks. Its
artifact digest was independently checked again during freeze preparation.

Repository precedent stores qualification reports. This report and the root
harness fix report are archived together in one documentation-only descendant
of the fix, preserving all public commit identities. The new commit's SHA and
fresh **main** CI result belong in
`SPLICORE_RC4_CI_INFRASTRUCTURE_FREEZE_REPORT.md`; #28 is branch baseline evidence.
Node action warnings remain **CI MAINTENANCE DEBT**, nonblocking and unchanged.

Final freeze-phase local rerun: **PASS** on the unchanged harness commit;
30 Bash, 106 Python (27 + 10 + 22 + 27 + 20), 42 runtime, 113 shell syntax.
ShellCheck, build consistency, repository secret/redaction scan, pinned
actionlint, and workflow contract passed. All nine namespace children had EUID
0, successful cleanup and unchanged checkout ownership. The original optional
Sudoku Xray check remains outside this campaign; no required gate was skipped.
