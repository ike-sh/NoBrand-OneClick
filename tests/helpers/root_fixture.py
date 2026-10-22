#!/usr/bin/env python3
"""Narrow root executor for audited, temporary regression fixtures only.

This is not a host isolation mechanism. The registered tests redirect files
and mock service/account/network effects. Never register a host mutation here.
"""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
SAFE_PATH = "/usr/sbin:/usr/bin:/sbin:/bin"
ENVIRONMENT_EXIT = 78
HARNESS_EXIT = 70
RESTORE = "runtime-restore"
# All nine need uid 0 paths/ownership only in redirected temporary roots.
# Mapping the caller to namespace uid/gid 0 is sufficient for those operations;
# none requires host systemd, networking, firewall or package capabilities.
FIXTURES = {name: {"required": True, "namespace": True, "requirement": reason}
            for name, reason in (
                ("tests/test_splicore_shell_surface.sh", "manager-bootstrap"),
                ("tests/test_schema_v3.sh", "root-file-ownership"),
                ("tests/test_ingress_profiles.sh", "ingress-root-guard"),
                ("tests/test_ingress_enforcement.sh", "ingress-root-guard"),
                ("tests/test_ingress_enforcement_transaction.sh", "ingress-root-guard"),
                ("tests/test_ssh_tunnel.sh", "watchdog-root-ownership"),
                ("tests/test_ssh_tunnel_transaction.sh", "watchdog-root-ownership"),
                ("tests/test_menu_lifecycle_lock_scope.sh", "menu-root-lock-path"),
                (RESTORE, "restore-root-ownership"),
            )}
PROBE = """import json,os,tempfile
with tempfile.TemporaryDirectory(prefix='nb-root-probe-') as d:
 p=d+'/owner';open(p,'w').close();os.chown(p,0,0);os.chmod(p,0o600)
 print(json.dumps({'euid':os.geteuid(),'ownership':os.stat(p).st_uid==0 and os.stat(p).st_gid==0}))
"""


def clean_environment():
    return {"PATH": SAFE_PATH, "LANG": "C.UTF-8", "LC_ALL": "C.UTF-8",
            "PYTHONDONTWRITEBYTECODE": "1"}


def probe(prefix):
    """Bounded, noninteractive check of actual child identity and operation."""
    try:
        run = subprocess.run([*prefix, "/usr/bin/python3", "-I", "-c", PROBE],
                             env=clean_environment(), capture_output=True, text=True,
                             stdin=subprocess.DEVNULL, timeout=15)
        data = json.loads(run.stdout) if run.returncode == 0 else {}
        uid = data.get("euid")
        return {"exit_code": run.returncode, "euid": uid if type(uid) is int else None,
                "usable": run.returncode == 0 and type(uid) is int and uid == 0 and data.get("ownership") is True}
    except (OSError, ValueError, subprocess.SubprocessError):
        return {"exit_code": None, "euid": None, "usable": False}


def resolve(policy):
    metadata = {"executor": "unavailable", "euid": os.geteuid(), "sudo_available": None,
                "namespace_available": None, "sudo_present": None, "namespace_present": None,
                "fixture_requirement": policy["requirement"], "required_in_profile": policy["required"],
                "namespace_compatible": policy["namespace"], "probes": {},
                "systemd": "NOT_REQUESTED", "network_namespace": "NOT_REQUESTED", "nftables": "NOT_REQUESTED"}
    if os.geteuid() == 0:
        metadata["executor"] = "direct-root"
        return [], metadata
    sudo = shutil.which("sudo", path=SAFE_PATH)
    metadata["sudo_present"] = sudo is not None
    metadata["sudo_available"] = False
    if sudo:
        prefix = [sudo, "-n", "--"]
        metadata["probes"]["sudo"] = result = probe(prefix)
        metadata["sudo_available"] = result["usable"]
        if result["usable"]:
            metadata["executor"] = "sudo"
            return prefix, metadata
    unshare = shutil.which("unshare", path=SAFE_PATH)
    metadata["namespace_present"] = unshare is not None
    if policy["namespace"] and unshare:
        prefix = [unshare, "--user", "--map-root-user"]
        metadata["probes"]["namespace"] = result = probe(prefix)
        metadata["namespace_available"] = result["usable"]
        if result["usable"]:
            metadata["executor"] = "namespace"
            return prefix, metadata
    elif policy["namespace"]:
        metadata["namespace_available"] = False
    return None, metadata


def record(metadata):
    # Written by the original user, never the privileged child. No free text,
    # hostnames, usernames, environment dump or probe stderr is included.
    serialized = json.dumps(metadata, sort_keys=True)
    path = os.environ.get("NOBRAND_PRIVILEGE_EVIDENCE")
    if path:
        with open(path, "a", encoding="utf-8") as stream:
            stream.write(serialized + "\n")
    print("[PRIVILEGE] " + serialized, flush=True)


def copy_fixture(destination):
    for folder in ("src", "runtime", "tests"):
        source = ROOT / folder
        if any(p.is_symlink() for p in source.rglob("*")):
            raise ValueError("symlink in fixture source")
        shutil.copytree(source, destination / folder, ignore=shutil.ignore_patterns("__pycache__", "*.pyc"))
    source = ROOT / "install-nobrand.sh"
    if source.is_symlink():
        raise ValueError("symlink installer")
    shutil.copyfile(source, destination / source.name)


def fixture_command(name, snapshot):
    if name == RESTORE:
        return ["/usr/bin/python3", "-B", str(snapshot / "tests/helpers/test_splicore_runtime.py"),
                "RuntimeTests.test_product_restore_snapshots_stopped_primary_and_restores_generation"]
    return ["/bin/bash", str(snapshot / name)]


def child(name, workspace):
    """Confirm identity again immediately before entry; clean even on failure."""
    if os.geteuid() != 0:
        shutil.rmtree(workspace / "checkout")
        return {"exit_code": ENVIRONMENT_EXIT, "outcome": "ROOT_CONFIRMATION_FAILED", "euid": os.geteuid(), "cleanup": True}
    snapshot = workspace / "checkout"
    # Restore uses a deliberately short root for Linux Unix socket limits.
    scratch = Path(tempfile.mkdtemp(prefix="n", dir="/tmp"))
    env = clean_environment()
    result = {"exit_code": HARNESS_EXIT, "outcome": "EXECUTOR_ERROR", "euid": 0, "cleanup": False}
    try:
        paths = {"HOME": scratch / "home", "TMPDIR": scratch / "tmp",
                       "NOBRAND_SYSTEM_ROOT": scratch / "system",
                       "NOBRAND_LIFECYCLE_DIR": scratch / "nobrand-oneclick-lifecycle",
                       "NOBRAND_LIFECYCLE_LOCK_FILE": scratch / "run/nobrand-oneclick/lifecycle.lock",
                       "NOBRAND_LEGACY_MIERU_STATE_DIR": scratch / "no-legacy",
                       "NOBRAND_INSTALL_SCRIPT_PATH": scratch / "commands/install-nobrand",
                       "NOBRAND_COMMAND_PATH": scratch / "commands/nobrand",
                 "NOBRAND_SHORT_COMMAND_PATH": scratch / "commands/nb"}
        env.update({key: str(value) for key, value in paths.items()})
        for key in ("HOME", "TMPDIR", "NOBRAND_SYSTEM_ROOT"):
            Path(env[key]).mkdir(mode=0o700)
        env["NOBRAND_ROOT_FIXTURE"] = name
        env["NOBRAND_ROOT_FIXTURE_DIR"] = str(scratch)
        run = subprocess.run(fixture_command(name, snapshot), cwd=snapshot, env=env,
                             stdin=subprocess.DEVNULL, timeout=300)
        result.update(exit_code=run.returncode if run.returncode >= 0 else 128 - run.returncode,
                      outcome="PASS" if run.returncode == 0 else "FIXTURE_FAILED")
    except (OSError, ValueError, subprocess.SubprocessError):
        pass  # Stable harness error; never print arbitrary exception contents.
    finally:
        cleaned = True
        for path in (scratch, snapshot):
            try:
                shutil.rmtree(path)
            except OSError:
                cleaned = False
        result["cleanup"] = cleaned
        if not cleaned:
            result.update(exit_code=HARNESS_EXIT, outcome="EXECUTOR_ERROR")
    return result


def checkout_owners():
    owners = {}
    for folder, directories, files in os.walk(ROOT, followlinks=False):
        directories[:] = [d for d in directories if d not in (".git", ".lab", "__pycache__")
                          and not (Path(folder) / d).is_symlink()]
        for name in files:
            path = Path(folder) / name
            if not path.is_symlink():
                owners[str(path.relative_to(ROOT))] = (path.stat().st_uid, path.stat().st_gid)
    return owners


def run_fixture(name, quiet_success=False):
    policy = FIXTURES[name]
    prefix, metadata = resolve(policy)
    metadata["fixture"] = name
    if prefix is None:
        metadata.update(outcome="UNAVAILABLE" if policy["required"] else "OPTIONAL_UNAVAILABLE",
                        classification="QUALIFICATION_ENVIRONMENT" if policy["required"] else "NOT_AVAILABLE",
                        fixture_started=False, exit_code=ENVIRONMENT_EXIT if policy["required"] else 0)
        record(metadata)
        return metadata["exit_code"]
    # Original checkout is read only. All privileged writes occur under /tmp.
    before = checkout_owners()
    with tempfile.TemporaryDirectory(prefix="nb-root-fixture-") as directory:
        workspace = Path(directory)
        snapshot = workspace / "checkout"
        try:
            copy_fixture(snapshot)
            output = workspace / "result.json"
            command = [*prefix, "/usr/bin/env", "-i", *[k + "=" + v for k, v in clean_environment().items()],
                       "/usr/bin/python3", "-B", str(snapshot / "tests/helpers/root_fixture.py"),
                       "_child", name, "--workspace", str(workspace)]
            run = subprocess.run(command, env=clean_environment(), stdin=subprocess.DEVNULL,
                                 capture_output=quiet_success, timeout=330)
            if quiet_success and run.returncode:
                sys.stdout.buffer.write(run.stdout)
                sys.stderr.buffer.write(run.stderr)
            if output.is_file() and not output.is_symlink():
                result = json.loads(output.read_text())
            else:
                result = {"exit_code": HARNESS_EXIT, "outcome": "EXECUTOR_ERROR", "cleanup": False}
            metadata.update(result, fixture_started=result.get("outcome") in ("PASS", "FIXTURE_FAILED"))
            if run.returncode != result.get("exit_code"):
                metadata.update(exit_code=HARNESS_EXIT, outcome="EXECUTOR_ERROR")
            metadata["classification"] = ("QUALIFICATION_ENVIRONMENT" if metadata["outcome"] == "ROOT_CONFIRMATION_FAILED"
                                          else "TEST_HARNESS_DEFECT" if metadata["outcome"] == "EXECUTOR_ERROR"
                                          else "NONE" if metadata["exit_code"] == 0 else "TEST_FAILURE")
            metadata["checkout_ownership_unchanged"] = checkout_owners() == before
            if not metadata["checkout_ownership_unchanged"] or not metadata.get("cleanup"):
                metadata.update(exit_code=HARNESS_EXIT, outcome="EXECUTOR_ERROR", classification="TEST_HARNESS_DEFECT")
        except (OSError, ValueError, subprocess.SubprocessError):
            metadata.update(exit_code=HARNESS_EXIT, outcome="EXECUTOR_ERROR", classification="TEST_HARNESS_DEFECT")
        record(metadata)
        return metadata["exit_code"]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("run", "_child"))
    parser.add_argument("fixture", choices=FIXTURES)
    parser.add_argument("--workspace", type=Path)
    args = parser.parse_args()
    if args.mode == "run":
        return run_fixture(args.fixture)
    workspace = args.workspace.resolve()
    if ROOT != workspace / "checkout" or not workspace.name.startswith("nb-root-fixture-"):
        return HARNESS_EXIT
    try:
        result = child(args.fixture, workspace)
    except (OSError, ValueError, subprocess.SubprocessError):
        result = {"exit_code": HARNESS_EXIT, "outcome": "EXECUTOR_ERROR", "euid": os.geteuid(), "cleanup": False}
    path = workspace / "result.json"
    path.write_text(json.dumps(result))
    path.chmod(0o644)
    return result["exit_code"]


if __name__ == "__main__":
    sys.exit(main())
