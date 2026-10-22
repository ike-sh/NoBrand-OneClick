#!/usr/bin/env python3
"""Qualification infrastructure; never changes host init, packages or firewall.

Native campaigns remain in docs/NATIVE-LINUX-QUALIFICATION.md. This executable
campaign runs static checks and the existing temporary loopback regression.
"""
import argparse
import ast
import datetime
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
BASE = "b5440ec41aeed2dd266b3a7008f75a26de63add2"
PARENT = "f98cf70e7159c07826101676a4a08394f0a203f9"
CHECKOUT = "actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683"
UPLOAD = "actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02"
MIHOMO_NAME = "mihomo-linux-amd64-v1.19.30.gz"
MIHOMO_SHA = "cf06ce2c7d1421bdbda14ee4a5b6046672dc35ebf8eecd8e77504ec3c0ed9a84"
SPEC = importlib.util.spec_from_file_location("qualification_runtime", ROOT / "runtime/splicore.py")
sc = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(sc)


class QualificationFailure(Exception):
    def __init__(self, classification, detail):
        self.classification = classification
        super().__init__(detail)


def require(condition, detail, classification="TEST_HARNESS"):
    if not condition:
        raise QualificationFailure(classification, detail)


def git(*arguments):
    return subprocess.check_output(["git", *arguments], cwd=ROOT, timeout=30)


def timestamp():
    return datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds")


def inventory():
    release = {}
    for line in Path("/etc/os-release").read_text().splitlines():
        if "=" in line:
            key, value = line.split("=", 1)
            if key in ("ID", "VERSION_ID"):
                release[key] = value.strip('"')
    versions = {}
    for name in ("systemctl", "openrc", "nft"):
        if shutil.which(name):
            result = subprocess.run([name, "--version"], capture_output=True, text=True, timeout=10)
            lines = result.stdout.splitlines()
            versions[name] = lines[0] if lines else "VERSION UNAVAILABLE"
    wsl = "microsoft" in platform.release().lower()
    return {"os": release, "kernel": platform.release(), "architecture": platform.machine(),
            "pid1": Path("/proc/1/comm").read_text().strip(), "wsl2": wsl,
            "label": "Linux WSL2; loopback only" if wsl else "Linux; disposable host status UNCONFIRMED",
            "versions": versions, "nobrand_commit": git("rev-parse", "HEAD").decode().strip(),
            "splicore_version": sc.RELEASE["version"], "native_runtime": "PENDING ENVIRONMENT"}


def verify_files(root, hashes):
    for name, expected in hashes.items():
        path = root / name
        require(path.is_file() and not path.is_symlink(), "protected file missing or symlink: " + name)
        require(not any(p.is_symlink() for p in path.parents if p != root.parent), "symlink in protected path: " + name)
        require(hashlib.sha256(path.read_bytes()).hexdigest() == expected, "protected file changed: " + name)


def lifecycle_fix_integrity():
    """Accept the reviewed lifecycle fix by exact bytes, never a path exemption."""
    scope = json.loads((ROOT / "tests/fixtures/splicore-rc4-lifecycle-fix.json").read_text())
    require(scope["base_commit"] == "326a3566447b7fb0834affbaee43cfa9594dc1e0"
            and scope["phase"] == "lifecycle-manager-version-fix"
            and set(scope["product_files"]) == {"src/15-core-state.sh"}, "lifecycle fix scope differs")
    verify_files(ROOT, scope["product_files"])
    return scope["product_files"]


def frozen_integrity(allow_certificate_fix=False, allow_lifecycle_fix=False):
    lifecycle = lifecycle_fix_integrity() if allow_lifecycle_fix else {}
    manifest = json.loads((ROOT / "tests/fixtures/splicore-rc4-frozen.json").read_text())
    require(manifest["frozen_commit"] == BASE and manifest["sole_parent"] == PARENT, "wrong frozen baseline")
    require(git("rev-list", "--parents", "-n", "1", BASE).decode().split() == [BASE, PARENT], "frozen commit identity differs")
    require(subprocess.run(["git", "merge-base", "--is-ancestor", BASE, "HEAD"], cwd=ROOT,
                           capture_output=True, timeout=30).returncode == 0, "checkout does not descend from frozen commit")
    baseline_paths = git("ls-tree", "-r", "--name-only", BASE).decode().splitlines()
    expected = {p for p in baseline_paths if p.startswith(("src/", "runtime/", "docs/reports/"))
                or p in ("install-nobrand.sh", "dist/install-nobrand.sh", "scripts/build.sh")}
    hashes = dict(manifest["product_files"], **manifest["protected_reports"])
    require(len(manifest["historical_reports"]) == 16 and all(
        hashes.get(p) == h for p, h in manifest["historical_reports"].items()), "historical hash protection differs")
    require(set(hashes) == expected, "protected manifest omits or adds baseline paths")
    query = "\n".join(BASE + ":" + p for p in sorted(hashes)) + "\n"
    raw = subprocess.run(["git", "cat-file", "--batch"], input=query.encode(), cwd=ROOT,
                         stdout=subprocess.PIPE, check=True, timeout=30).stdout
    offset = 0
    for name in sorted(hashes):
        end = raw.index(b"\n", offset)
        header = raw[offset:end].split()
        require(len(header) == 3 and header[1] == b"blob", "baseline blob unavailable")
        size = int(header[2])
        require(hashlib.sha256(raw[end + 1:end + 1 + size]).hexdigest() == hashes[name], "manifest differs from frozen Git bytes: " + name)
        offset = end + size + 2
    permitted = {"runtime/splicore.py", "install-nobrand.sh", "dist/install-nobrand.sh"} if allow_certificate_fix else set()
    permitted.update(lifecycle)
    verify_files(ROOT, {p: h for p, h in hashes.items() if p not in permitted})
    changed = [p for p in sorted(permitted) if hashlib.sha256((ROOT / p).read_bytes()).hexdigest() != hashes[p]]
    return {"product_files": len(manifest["product_files"]), "protected_reports": len(manifest["protected_reports"]),
            "historical_reports": len(manifest["historical_reports"]), "changed": len(changed),
            "authorized_product_changes": changed, "lifecycle_fix_files": sorted(lifecycle), "result": "PASS"}


def review_integrity():
    """Preserve the reviewed certificate/lifecycle fixes by exact scope."""
    result = frozen_integrity(allow_certificate_fix=True, allow_lifecycle_fix=True)
    scope = json.loads((ROOT / "tests/fixtures/splicore-rc4-cert-fix.json").read_text())
    require(scope["frozen_commit"] == BASE and set(scope["permitted_product_paths"]) ==
            {"runtime/splicore.py", "install-nobrand.sh", "dist/install-nobrand.sh"}, "certificate fix scope differs")
    methods = {"certificate_material", "certificate_provenance", "certificate_owner", "certificate", "protocol", "uninstall"}
    require(set(scope["permitted_runtime_methods"]) == methods, "runtime method scope differs")
    trees = [ast.parse(git("show", BASE + ":runtime/splicore.py")), ast.parse((ROOT / "runtime/splicore.py").read_text())]
    for tree in trees:
        runtime = next(n for n in tree.body if isinstance(n, ast.ClassDef) and n.name == "Runtime")
        runtime.body = [n for n in runtime.body if not (isinstance(n, ast.FunctionDef) and n.name in methods)]
    require(ast.dump(trees[0]) == ast.dump(trees[1]), "product change escapes certificate lifecycle methods")
    verify_files(ROOT, scope["preserved_qualification_files"])
    run = subprocess.run(["bash", "scripts/build.sh", "--check"], cwd=ROOT, capture_output=True, timeout=60)
    require(run.returncode == 0, "generated installers differ from reviewed runtime")
    result.update(scope="REVIEWED CERTIFICATE + LIFECYCLE FIXES", unapproved_changes=0,
                  preserved_qualification_files=len(scope["preserved_qualification_files"]))
    return result


def workflow_contract(text):
    import yaml
    workflow = yaml.load(text, Loader=yaml.BaseLoader)
    require(set(workflow["on"]) == {"push", "pull_request", "workflow_dispatch"}, "unexpected workflow trigger")
    require(workflow["permissions"] == {"contents": "read"}, "workflow must have read-only token permissions")
    require(set(workflow["jobs"]) == {"regression"}, "unexpected CI job")
    job = workflow["jobs"]["regression"]
    require(job["runs-on"] == "ubuntu-24.04" and 1 <= int(job["timeout-minutes"]) <= 40, "runner or timeout differs")
    require(not any(k in job for k in ("container", "services", "permissions", "environment")), "unexpected job privilege or external service")
    steps = job["steps"]
    require([s["uses"] for s in steps if "uses" in s] == [CHECKOUT, UPLOAD], "action identity is not the reviewed SHA")
    checkout = next(s for s in steps if "uses" in s)
    require(checkout["with"] == {"fetch-depth": "0", "persist-credentials": "false"}, "checkout must fetch baseline and discard credentials")
    joined = "\n".join(s.get("run", "") for s in steps)
    require('python3 scripts/ci-diagnostics.py run --evidence "$RUNNER_TEMP/nobrand-rc4"' in joined, "CI entrypoint missing")
    require(not any("continue-on-error" in s for s in steps), "CI must propagate failures")
    for name in ("Publish sanitized diagnostics", "Upload sanitized qualification evidence", "Propagate qualification exit status"):
        require(next((s.get("if") for s in steps if s.get("name") == name), None) == "always()", "diagnostics/final status must always run")
    require(next(s.get("run") for s in steps if s.get("name") == "Publish sanitized diagnostics") ==
            'python3 scripts/ci-diagnostics.py publish --evidence "$RUNNER_TEMP/nobrand-rc4"', "sanitized publisher missing")
    require(steps[-1].get("run") == 'python3 scripts/ci-diagnostics.py finish --evidence "$RUNNER_TEMP/nobrand-rc4"', "final exit propagation missing")
    upload = next(s for s in steps if s.get("uses") == UPLOAD)
    spec = importlib.util.spec_from_file_location("ci_contract_diagnostics", ROOT / "scripts/ci-diagnostics.py")
    diagnostics = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(diagnostics)
    require(upload["with"]["path"].splitlines() == ["${{ runner.temp }}/nobrand-rc4/public/" + p for p in diagnostics.PUBLIC_FILES], "artifact must list only reviewed public files")
    require(upload["with"].get("if-no-files-found") == "error" and upload["with"].get("include-hidden-files", "false") == "false", "missing/hidden artifact policy differs")
    require("git diff --exit-code --quiet" in joined, "CI generated-file mutation guard must fail without exposing raw diffs")
    require("actionlint/cmd/actionlint@v1.7.7" in joined, "workflow validator is not pinned")
    require(not re.search(r"\b(?:docker|podman|redis-cli|teleledger)\b|self-hosted|\b(?:git push|gh release|git tag)\b|\b(?:reboot|systemctl|nft)\s", text, re.I), "forbidden host/service/publication action")
    require(not re.search(r"\b(?:secrets|id-token|write-all)\b|(?:releases/latest|latest/download)|curl[^\n]*\|\s*(?:ba)?sh|@(?:main|master)\b", text), "secret, mutable artifact or unverified execution")
    return {"syntax": "PASS", "contract": "PASS", "permissions": "contents: read", "checkout": CHECKOUT,
            "external_run": "PENDING UNTIL PUSH"}


def run_logged(arguments, log, timeout, classification="TEST_HARNESS", env=None):
    started = timestamp()
    execution = {"command": [str(a) for a in arguments], "started_utc": started, "exit_code": None}
    # Private command metadata survives a failed campaign; no stdout or argv is
    # exposed here. The CI publisher projects and sanitizes this evidence.
    with log.open("wb") as stream:
        try:
            result = subprocess.run([str(a) for a in arguments], cwd=ROOT, env=env,
                                    stdout=stream, stderr=subprocess.STDOUT, timeout=timeout)
            execution["exit_code"] = result.returncode
        except subprocess.TimeoutExpired as exc:
            execution["timed_out"] = True
            raise QualificationFailure("INFRASTRUCTURE", "bounded command timeout; inspect private log: " + log.name) from exc
        finally:
            execution["finished_utc"] = timestamp()
            try:
                sc.save(log.with_suffix(".command.json"), execution)
            except OSError:
                # Diagnostic write failure must not replace the command result.
                pass
    if result.returncode != 0 and env and env.get("NOBRAND_PRIVILEGE_EVIDENCE"):
        path = Path(env["NOBRAND_PRIVILEGE_EVIDENCE"])
        if path.is_file() and not path.is_symlink():
            records = [json.loads(line) for line in path.read_text().splitlines()]
            if any(r.get("classification") == "QUALIFICATION_ENVIRONMENT" for r in records):
                classification = "QUALIFICATION_ENVIRONMENT"
            elif any(r.get("classification") == "TEST_HARNESS_DEFECT" for r in records):
                classification = "TEST_HARNESS_DEFECT"
    require(result.returncode == 0, "command failed; inspect private log: " + log.name, classification)
    return execution


def static_checks(evidence, strict=False):
    result = {"integrity": review_integrity(), "workflow": workflow_contract((ROOT / ".github/workflows/ci.yml").read_text())}
    for folder in ("runtime", "tests/helpers", "scripts"):
        for path in (ROOT / folder).glob("*.py"):
            ast.parse(path.read_text(), filename=str(path))
    result["python_syntax"] = "PASS"
    actionlint = shutil.which("actionlint")
    require(not strict or actionlint, "actionlint is required for CI", "QUALIFICATION_ENVIRONMENT")
    result["actionlint"] = run_logged([actionlint, ".github/workflows/ci.yml"], evidence / "actionlint.log", 90) if actionlint else "SKIP: unavailable"
    with tempfile.TemporaryDirectory(prefix="nb-unit-") as directory:
        temp = Path(directory)
        with patch.dict(os.environ, {"NOBRAND_STATE_DIR": str(temp / "s")}):
            for adapter in ("systemd", "openrc"):
                unit = temp / ("nobrand-splicore.service" if adapter == "systemd" else "nobrand-splicore")
                unit.write_text(sc.Runtime(adapter=adapter).service_text())
                if adapter == "systemd":
                    analyzer = shutil.which("systemd-analyze")
                    require(not strict or analyzer, "systemd-analyze is required for CI", "QUALIFICATION_ENVIRONMENT")
                    result["systemd_unit_verify"] = run_logged([analyzer, "verify", "--man=no", "--generators=no", unit], evidence / "systemd-unit.log", 45) if analyzer else "SKIP: unavailable"
                else:
                    result["openrc_shell_syntax"] = run_logged(["sh", "-n", unit], evidence / "openrc-unit.log", 15)
    result["native_service_runtime"] = "PENDING ENVIRONMENT"
    return result


def check_assets(artifacts, mihomo):
    result = {}
    sums = (artifacts / "SHA256SUMS").read_text(encoding="ascii")
    for architecture, entry in sc.RELEASE["assets"].items():
        archive = artifacts / entry["name"]
        sc.inspect_archive(archive, entry, sums)
        with tarfile.open(archive, "r:gz") as package:
            with package.extractfile("splicore") as stream:
                digest = hashlib.sha256(stream.read()).hexdigest()
        require(digest == entry["binary_sha256"], "public binary digest differs", "INFRASTRUCTURE")
        result[architecture] = {"archive_sha256": sc.sha(archive), "binary_sha256": digest, "static": "PASS", "runtime": "NOT RUN"}
    require(sc.sha(mihomo) == MIHOMO_SHA, "reference client checksum differs", "INFRASTRUCTURE")
    with tempfile.TemporaryDirectory(prefix="nb-artifact-") as directory:
        native = sc.arch()
        identity = sc.artifact(Path(directory) / "splicore", directory=artifacts, target_arch=native)["identity"]
    result[native]["executed_identity"] = identity
    result[native]["runtime"] = "VERSION IDENTITY ONLY; not native service qualification"
    return {"architectures": result, "mihomo_sha256": MIHOMO_SHA, "result": "PASS"}


def prepare_assets(destination):
    destination = destination.resolve()
    require(not destination.exists(), "asset destination must be new; existing caches use --artifacts/--mihomo-gzip")
    destination.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    with tempfile.TemporaryDirectory(prefix=".download-", dir=destination.parent) as directory:
        staging = Path(directory)
        base = "https://github.com/" + sc.RELEASE["repository"] + "/releases/download/" + sc.RELEASE["version"] + "/"
        for name in ("SHA256SUMS", *(e["name"] for e in sc.RELEASE["assets"].values())):
            sc.download(base + name, staging / name)
        sc.download("https://github.com/MetaCubeX/mihomo/releases/download/v1.19.30/" + MIHOMO_NAME, staging / MIHOMO_NAME)
        result = check_assets(staging, staging / MIHOMO_NAME)
        destination.mkdir(mode=0o700)
        for path in staging.iterdir():
            shutil.copyfile(path, destination / path.name)
    return result


def summarize(log, probe):
    require(log.endswith("[PASS] NoBrand test suite\n"), "regression completion marker missing")
    require(probe["result"] == "PASS" and probe["checks"] and all(v == "PASS" for v in probe["checks"].values()), "runtime result is incomplete")
    baseline_probe = json.loads(git("show", BASE + ":docs/reports/SPLICORE_RC4_FRESH_RUNTIME_PROBE.json"))
    require(set(probe["checks"]) == set(baseline_probe["checks"]), "frozen runtime checks missing or changed")
    baseline_script = git("show", BASE + ":scripts/test.sh").decode()
    expected_bash = set(re.findall(r"^  (tests/\S+\.sh)$", baseline_script, re.M)) | {"tests/test_splicore_qualification.sh", "tests/test_splicore_cert_lifecycle.sh"}
    actual_bash = re.findall(r"^\[RUN\] (tests/\S+\.sh)$", log, re.M)
    require(set(actual_bash) == expected_bash and len(actual_bash) == len(expected_bash), "frozen Bash entrypoints missing or repeated")
    require("[PASS] ShellCheck:" in log and "[PASS] Generated installers" in log, "quality gate skipped")
    python_runs = [int(n) for n in re.findall(r"^Ran (\d+) tests in .*", log, re.M)]
    require(len(python_runs) >= 5 and python_runs[:2] == [27, 10] and python_runs[2] >= 21 and sum(python_runs[3:-1]) >= 13
            and python_runs[-1] >= 20
            and not re.search(r"^OK \(skipped=|^FAILED|^ERROR:|^Traceback", log, re.M), "Python tests skipped, incomplete or failed")
    return {"result": "PASS", "bash_entrypoints": len(re.findall(r"^\[RUN\] ", log, re.M)),
            "python_runs": python_runs, "python_total": sum(python_runs), "runtime_checks": len(probe["checks"]),
            "shell_syntax_files": sum(len(list(ROOT.glob(p))) for p in ("src/*.sh", "scripts/*.sh", "tests/*.sh", "install-nobrand.sh", "dist/install-nobrand.sh")),
            "shellcheck": "PASS", "build_consistency": "PASS", "secret_scan": "PASS" if "USER_RUNTIME_LITERAL_LEAK_COUNT=0" in log else "MISSING",
            "optional_skips": [line for line in log.splitlines() if "[SKIP]" in line]}


def campaign(args, evidence):
    require(sc.arch() == "amd64", "pinned reference-client campaign currently requires amd64", "UNSUPPORTED_PLATFORM")
    require(shutil.which("shellcheck"), "ShellCheck is required", "QUALIFICATION_ENVIRONMENT")
    result = {"environment": inventory(), "static": static_checks(evidence, strict=True)}
    if args.artifacts:
        require(args.mihomo_gzip, "--artifacts requires --mihomo-gzip")
        artifacts, mihomo = args.artifacts.resolve(), args.mihomo_gzip.resolve()
        result["artifact_origin"] = "explicit public cache; integrity reverified"
        result["artifacts"] = check_assets(artifacts, mihomo)
    else:
        artifacts = evidence / "assets"
        result["artifacts"] = prepare_assets(artifacts)
        mihomo = artifacts / MIHOMO_NAME
        result["artifact_origin"] = "exact public HTTPS releases; verified before execution"
    env = dict(os.environ, NOBRAND_SPLICORE_PUBLIC_ARTIFACTS=str(artifacts),
               NOBRAND_REFERENCE_MIHOMO_GZIP=str(mihomo), NOBRAND_RUNTIME_EVIDENCE_DIR=str(evidence),
               NOBRAND_PRIVILEGE_EVIDENCE=str(evidence / "privilege.jsonl"), PYTHONDONTWRITEBYTECODE="1")
    result["execution"] = run_logged(["bash", "scripts/test.sh", "--runtime"], evidence / "regression.log", 1800, env=env)
    spec = importlib.util.spec_from_file_location("qualification_root_fixtures", ROOT / "tests/helpers/root_fixture.py")
    fixtures = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(fixtures)
    records = [json.loads(line) for line in (evidence / "privilege.jsonl").read_text().splitlines()]
    require(len(records) == len(fixtures.FIXTURES) and {r.get("fixture") for r in records} == set(fixtures.FIXTURES)
            and all(r.get("outcome") == "PASS" and type(r.get("euid")) is int and r["euid"] == 0
                    and r.get("fixture_started") is True and r.get("cleanup") is True
                    and r.get("checkout_ownership_unchanged") is True for r in records),
            "mandatory privileged fixture evidence missing or incomplete", "TEST_HARNESS_DEFECT")
    result["privilege"] = records
    result["regression"] = summarize((evidence / "regression.log").read_text(), json.loads((evidence / "runtime-probe.json").read_text()))
    require(result["regression"]["secret_scan"] == "PASS", "secret scan completion marker missing")
    result["integrity_after"] = review_integrity()
    result["result"] = "PASS: LOCAL CI AND LOOPBACK REGRESSION"
    result["native_systemd"] = result["native_openrc"] = result["arm64_runtime"] = "PENDING ENVIRONMENT"
    result["nftables_port_range"] = "N/A: CORE CAPABILITY NOT EXPOSED BY NOBRAND"
    result["external_github_actions"] = "PENDING UNTIL PUSH"
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("inventory", "static", "assets", "ci"))
    parser.add_argument("--evidence", type=Path)
    parser.add_argument("--artifacts", type=Path)
    parser.add_argument("--mihomo-gzip", type=Path)
    args = parser.parse_args()
    os.umask(0o077)
    if args.mode == "inventory":
        print(json.dumps(inventory(), indent=2))
        return 0
    require(args.evidence, "--evidence is required; use a private ignored directory")
    evidence = args.evidence.resolve()
    require(not evidence.exists(), "evidence directory must be new for every run")
    if evidence.is_relative_to(ROOT):
        require(evidence.is_relative_to(ROOT / ".lab"), "repository evidence must remain under ignored .lab")
    evidence.mkdir(parents=True, mode=0o700)
    result = {"started_utc": timestamp(), "mode": args.mode}
    try:
        if args.mode == "static": result.update(static_checks(evidence))
        elif args.mode == "assets": result.update(prepare_assets(evidence / "assets"))
        else: result.update(campaign(args, evidence))
        result.setdefault("result", "PASS")
        result["finished_utc"] = timestamp()
        sc.save(evidence / "summary.json", result)
        print(json.dumps(result, indent=2))
        return 0
    except (QualificationFailure, sc.Failure, OSError, ValueError, subprocess.SubprocessError) as exc:
        classification = exc.classification if isinstance(exc, QualificationFailure) else "INFRASTRUCTURE"
        result.update(result="FAIL", classification=classification,
                      detail=str(exc) if isinstance(exc, QualificationFailure) else "external state/command rejected; inspect private evidence",
                      finished_utc=timestamp())
        sc.save(evidence / "summary.json", result)
        print(json.dumps(result, indent=2), file=sys.stderr)
        return 1


if __name__ == "__main__":
    try:
        sys.exit(main())
    except QualificationFailure as error:
        print(json.dumps({"result": "FAIL", "classification": error.classification, "detail": str(error)}), file=sys.stderr)
        sys.exit(1)
