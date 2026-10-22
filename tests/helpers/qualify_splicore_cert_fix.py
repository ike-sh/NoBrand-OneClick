#!/usr/bin/env python3
"""Original four cases plus retained-certificate rc.4 validation and traffic.

Temporary loopback only; no host init, firewall, package or network changes.
Original historical evidence and the original reproducer remain unchanged.
"""
import argparse
import contextlib
import gzip
import io
import json
import os
from pathlib import Path
import socket
import tempfile
from unittest.mock import patch

import qualify_splicore_reinstall as original

probe, q, sc = original.probe, original.qualification, original.sc


def smoke(protocol, removal, artifacts, client, log, echo):
    with tempfile.TemporaryDirectory(prefix="nb-tls-") as directory:
        work = Path(directory)
        environment = {"NOBRAND_SYSTEM_ROOT": str(work), "NOBRAND_STATE_DIR": str(work / "s"),
            "NOBRAND_CONFIG_DIR": str(work / "c"), "NOBRAND_LIB_DIR": str(work / "l"),
            "NOBRAND_LIFECYCLE_DIR": str(work / "j"), "NOBRAND_LIFECYCLE_LOCK_FILE": str(work / "lock"),
            "NOBRAND_SPLICORE_FIXTURE": "1", "NOBRAND_SPLICORE_LISTEN": "127.0.0.1",
            "ADVERTISE_HOST": "127.0.0.1", "ADVERTISE_PORT": "", "TUIC_USER": "synthetic-user",
            "NOBRAND_GITHUB_PROXY": "", "PORT": str(probe.vacant(socket.SOCK_DGRAM)),
            "HY2_SNI": "probe.example", "TUIC_SNI": "probe.example"}
        with patch.dict(os.environ, environment):
            driver = work / "driver"
            driver.write_text("not executed; service calls use local Supervisor\n")
            runtime = sc.Runtime(adapter="fixture", fixture=driver)
            supervisor = probe.Supervisor(runtime, log)

            def call(service, *a, **kw):
                return supervisor.call(service, *a, **kw)

            def cli(arguments):
                with contextlib.redirect_stdout(io.StringIO()):
                    code = sc.main(arguments + ["--adapter", "fixture", "--fixture-driver", str(driver)])
                probe.check(code == 0, "runtime CLI failed")

            install = ["protocol", "--protocol", protocol, "--operation", "install", "--selector", "fresh", "--artifacts", str(artifacts)]
            remove = (["protocol", "--protocol", protocol, "--operation", "uninstall", "--selector", "fresh"]
                      if removal == "protocol-uninstall" else ["uninstall"])
            fingerprints, ca_digests, traffic_checks, validation_checks = [], [], [], []
            try:
                with patch.object(sc.Service, "call", call):
                    for cycle in range(3):
                        cli(install)
                        graph = runtime.desired()
                        current, node = runtime.current.resolve(), graph["nodes"][0]
                        tls = node["document"]["settings"]["tls"]
                        fingerprints.append(sc.leaf_fingerprint(tls))
                        ca_digests.append(sc.sha(Path(tls["certificate_file"]).parent / "ca.pem"))
                        runtime.validate(current, sc.render(graph))
                        validation_checks.append("PASS")
                        profile = sc.client_profiles(node)
                        name = "NoBrand-Hysteria2"
                        if protocol == "tuic":
                            profile, name = profile["profiles"][0], "nobrand-tuic-synthetic-user"
                        probe.traffic(work, client, log, echo, profile["mihomo"], name, udp=True)
                        traffic_checks.append("PASS")
                        if cycle < 2:
                            cli(remove)
                            probe.check(Path(tls["certificate_file"]).is_file(), "uninstall removed retained TLS")
                            if removal == "runtime-uninstall":
                                cli(remove)  # idempotent uninstall, without purge
                    probe.check(len(set(fingerprints)) == 1 and len(set(ca_digests)) == 1, "certificate identity rotated")
                    cli(["purge"])
                    probe.check(not (runtime.config / "splicore/tls").exists(), "purge retained owned TLS")
                    return {"protocol": protocol, "removal": removal, "instance": "fresh",
                            "certificate_mode": "NoBrand-generated private CA and non-CA leaf",
                            "reinstall_cycles": 2, "leaf_fingerprint_before_after": fingerprints,
                            "ca_identity_preserved": True, "native_config_validation": validation_checks,
                            "actual_tcp_udp_traffic": traffic_checks, "runtime_uninstall_twice": removal == "runtime-uninstall",
                            "purge": "PASS", "result": "PASS"}
            finally:
                probe.stop(supervisor.child)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--artifacts", type=Path, required=True)
    parser.add_argument("--mihomo-gzip", type=Path, required=True)
    parser.add_argument("--evidence", type=Path, required=True)
    args = parser.parse_args()
    os.umask(0o077)
    evidence = args.evidence.resolve()
    if evidence.exists() or (evidence.is_relative_to(q.ROOT) and not evidence.is_relative_to(q.ROOT / ".lab")):
        print(json.dumps({"result": "FAIL", "classification": "TEST_HARNESS", "detail": "new private evidence directory required"}))
        return 2
    evidence.mkdir(parents=True, mode=0o700)
    result = {"started_utc": q.timestamp(), "scope": "Linux amd64 WSL2/local loopback only; runtime CLI and local Supervisor",
              "native_systemd": "PENDING ENVIRONMENT", "original_four_cases": [], "runtime_smoke": []}
    try:
        result["integrity"] = q.review_integrity()
        result["artifacts"] = q.check_assets(args.artifacts.resolve(), args.mihomo_gzip.resolve())
        with tempfile.TemporaryDirectory(prefix="nb-client-") as directory, probe.Echo() as echo, (evidence / "private-process.log").open("wb") as log:
            client = Path(directory) / "mihomo"
            with gzip.open(args.mihomo_gzip, "rb") as source:
                sc.atomic(client, source.read(), 0o700)
            for protocol in ("hysteria2", "tuic"):
                for removal in ("protocol-uninstall", "runtime-uninstall"):
                    item = original.case(protocol, removal, args.artifacts.resolve(), log)
                    item.update(case_id="CASE-" + str(len(result["original_four_cases"]) + 1), instance="fresh",
                                certificate_mode="NoBrand-generated private CA and non-CA leaf")
                    result["original_four_cases"].append(item)
                    probe.check(item["reinstall"] == "PASS", "original failing case still fails")
                    result["runtime_smoke"].append(smoke(protocol, removal, args.artifacts.resolve(), client, log, echo))
        result.update(result="PASS", fix_applied=True, exit_code=0)
    except Exception as error:
        result.update(result="FAIL", classification="TEST_HARNESS" if not isinstance(error, (sc.Failure, AssertionError)) else "IMPLEMENTATION_DEFECT",
                      detail="reinstall qualification failed; inspect private evidence", exit_code=1)
    result["finished_utc"] = q.timestamp()
    sc.save(evidence / "summary.json", result)
    print(json.dumps(result, indent=2))
    return result["exit_code"]


if __name__ == "__main__":
    raise SystemExit(main())
