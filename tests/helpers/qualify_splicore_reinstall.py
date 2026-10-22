#!/usr/bin/env python3
"""Reproduce uninstall/reinstall with verified rc.4 in temporary loopback state.

Exit 1 means IMPLEMENTATION_DEFECT; exit 2 means reproduction infrastructure
failed. This independent qualification is deliberately outside the frozen
passing regression. No host init, package or firewall operations are performed.
"""
import argparse
import contextlib
import datetime
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import socket
import tempfile
from unittest.mock import patch

import splicore_rc4_probe as probe

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("qualification", ROOT / "scripts/qualify-splicore.py")
qualification = importlib.util.module_from_spec(spec)
spec.loader.exec_module(qualification)
sc = probe.sc


def timestamp():
    return datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds")


def case(protocol, removal, artifacts, log):
    with tempfile.TemporaryDirectory(prefix="nb-reinstall-") as directory:
        work = Path(directory)
        environment = {
            "NOBRAND_SYSTEM_ROOT": str(work), "NOBRAND_STATE_DIR": str(work / "s"),
            "NOBRAND_CONFIG_DIR": str(work / "c"), "NOBRAND_LIB_DIR": str(work / "l"),
            "NOBRAND_LIFECYCLE_DIR": str(work / "j"), "NOBRAND_LIFECYCLE_LOCK_FILE": str(work / "lock"),
            "NOBRAND_SPLICORE_FIXTURE": "1", "NOBRAND_SPLICORE_LISTEN": "127.0.0.1",
            "ADVERTISE_HOST": "127.0.0.1", "ADVERTISE_PORT": "", "NOBRAND_GITHUB_PROXY": "",
            "PORT": str(probe.vacant(socket.SOCK_DGRAM)), "HY2_SNI": "probe.example", "TUIC_SNI": "probe.example",
        }
        with patch.dict(os.environ, environment):
            driver = work / "fixture-driver"
            driver.write_text("not executed; local Supervisor substitutes service calls\n")
            runtime = sc.Runtime(adapter="fixture", fixture=driver)
            supervisor = probe.Supervisor(runtime, log)

            def service_call(service, *arguments, **kwargs):
                return supervisor.call(service, *arguments, **kwargs)

            def cli(arguments):
                # Exercise the frozen runtime CLI parser and dispatcher. Discard
                # installation output, which contains synthetic client secrets.
                stream = io.StringIO()
                with contextlib.redirect_stdout(stream):
                    code = sc.main(arguments + ["--adapter", "fixture", "--fixture-driver", str(driver)])
                probe.check(code == 0, "CLI operation failed")
                return json.loads(stream.getvalue())

            install = ["protocol", "--protocol", protocol, "--operation", "install", "--selector", "fresh",
                       "--artifacts", str(artifacts)]
            delete = (["protocol", "--protocol", protocol, "--operation", "uninstall", "--selector", "fresh"]
                      if removal == "protocol-uninstall" else ["uninstall"])
            try:
                with patch.object(sc.Service, "call", service_call):
                    first = cli(install)
                    probe.check(first["result"] == "committed", "first install did not commit")
                    binary = runtime.current.resolve() / "splicore"
                    binary_sha = sc.sha(binary)
                    probe.check(binary_sha == sc.RELEASE["assets"][sc.arch()]["binary_sha256"], "installed public binary differs")
                    removed = cli(delete)
                    probe.check(not runtime.desired()["nodes"], "node remained after uninstall")
                    tls = runtime.config / "splicore/tls"
                    tls_before = {str(p.relative_to(tls)): hashlib.sha256(p.read_bytes()).hexdigest()
                                  for p in tls.rglob("*") if p.is_file()}
                    pointer = str(runtime.target(runtime.current))
                    starts = supervisor.starts
                    result = {"protocol": protocol, "removal": removal, "first_install": "PASS",
                              "remove_result": removed["result"], "nodes_after_remove": 0,
                              "installed_binary_sha256": binary_sha, "retained_tls_files": len(tls_before)}
                    try:
                        cli(install)
                    except sc.Failure as error:
                        probe.check(error.category == "CONFIG_INVALID" and str(error) ==
                                    "certificate directory already exists; explicit certificate reuse required",
                                    "unexpected reproduction failure")
                        probe.check(str(runtime.target(runtime.current)) == pointer and starts == supervisor.starts,
                                    "failed reinstall changed generation or started a service")
                        probe.check(tls_before == {str(p.relative_to(tls)): hashlib.sha256(p.read_bytes()).hexdigest()
                                                  for p in tls.rglob("*") if p.is_file()}, "retained TLS changed")
                        result.update(reinstall="FAIL", cli_equivalent_exit_code=1,
                                      category=error.category, detail=str(error), live_state_after_refusal="UNCHANGED")
                    else:
                        result.update(reinstall="PASS", cli_equivalent_exit_code=0)
                    return result
            finally:
                probe.stop(supervisor.child)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--artifacts", required=True, type=Path)
    parser.add_argument("--evidence", required=True, type=Path)
    args = parser.parse_args()
    os.umask(0o077)
    evidence = args.evidence.resolve()
    if evidence.exists() or (evidence.is_relative_to(ROOT) and not evidence.is_relative_to(ROOT / ".lab")):
        print(json.dumps({"result": "FAIL", "classification": "TEST_HARNESS", "detail": "use a new private evidence directory"}))
        return 2
    evidence.mkdir(parents=True, mode=0o700)
    result = {"started_utc": timestamp(), "scope": "WSL2/Linux amd64 temporary loopback; runtime CLI; local Supervisor",
              "native_service_qualification": "NOT EXECUTED", "cases": []}
    try:
        result["frozen_integrity"] = qualification.frozen_integrity()
        probe.check(sc.arch() == "amd64", "this reproduction requires amd64")
        with (evidence / "private-process.log").open("wb") as log:
            for protocol in ("hysteria2", "tuic"):
                for removal in ("protocol-uninstall", "runtime-uninstall"):
                    result["cases"].append(case(protocol, removal, args.artifacts.resolve(), log))
        failed = any(item["reinstall"] == "FAIL" for item in result["cases"])
        result.update(result="IMPLEMENTATION DEFECT FOUND" if failed else "PASS",
                      classification="IMPLEMENTATION_DEFECT" if failed else None, fix_applied=False)
        code = 1 if failed else 0
    except Exception:
        result.update(result="REPRODUCTION INCOMPLETE", classification="TEST_HARNESS",
                      detail="unexpected setup/command failure; inspect private process evidence")
        code = 2
    result.update(finished_utc=timestamp(), exit_code=code)
    sc.save(evidence / "summary.json", result)
    print(json.dumps(result, indent=2))
    return code


if __name__ == "__main__":
    raise SystemExit(main())
