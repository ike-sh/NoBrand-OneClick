#!/usr/bin/env python3
"""Exercise the installed adapter with public artifacts, no host service changes."""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import socket
import shutil
import tempfile
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("sc", ROOT / "runtime/splicore.py")
sc = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sc)


def port(kind):
    with socket.socket(socket.AF_INET, kind) as listener:
        listener.bind(("127.0.0.1", 0))
        return listener.getsockname()[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--artifacts", required=True, type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    os.umask(0o077)
    with tempfile.TemporaryDirectory(prefix="sc-") as directory:
        root = Path(directory)
        os.environ.update({"NOBRAND_SYSTEM_ROOT": str(root), "NOBRAND_STATE_DIR": str(root / "s"), "NOBRAND_CONFIG_DIR": str(root / "c"),
                           "NOBRAND_LIB_DIR": str(root / "l"), "NOBRAND_LIFECYCLE_DIR": str(root / "j"),
                           "NOBRAND_LIFECYCLE_LOCK_FILE": str(root / "lock")})
        runtime = sc.Runtime(adapter="process")
        tls = runtime.certificate("test", "probe.example")
        graph = sc.empty()
        used = set()
        for protocol in ("snell", "mieru", "hysteria2", "tuic"):
            kind = socket.SOCK_STREAM if protocol in ("snell", "mieru") else socket.SOCK_DGRAM
            candidate_port = port(kind)
            while candidate_port in used:
                candidate_port = port(kind)
            used.add(candidate_port)
            doc = {"schema": 1, "listener": {"host": "127.0.0.1", "port": candidate_port},
                   "display_endpoint": {"host": "127.0.0.1", "port": candidate_port}}
            if protocol == "snell":
                doc.update({"psk": "synthetic-original-psk", "settings": {"version": 5}})
            else:
                doc["users"] = [{"password": "synthetic-original-password"}]
                if protocol == "mieru":
                    doc["users"][0]["username"] = "synthetic-original-user"
                    doc["settings"] = {"transport": "tcp", "mtu": 1400, "multiplex": "off"}
                elif protocol == "hysteria2":
                    doc["settings"] = {"tls": tls}
                else:
                    doc["users"][0]["uuid"] = "11111111-1111-4111-8111-111111111111"
                    doc["settings"] = {"tls": tls, "version": 5, "congestion_control": "cubic",
                                       "udp_relay_mode": "native", "zero_rtt_handshake": False}
            graph["nodes"].append({"id": protocol, "protocol": protocol, "enabled": True, "document": doc})
        urls = []
        def release_transport(url, destination, proxy=""):
            urls.append({"url": url, "proxy": proxy, "transport": "verified public artifact cache fixture"})
            shutil.copyfile(args.artifacts.resolve() / url.rsplit("/", 1)[1], destination)
        # Exercise the production resolver/checksum/extraction/identity path.
        # Only HTTP transport is replaced; actual public binaries still run.
        with patch.object(sc, "download", side_effect=release_transport):
            outcome = runtime.deploy(graph, probe=True)
        outcome["download_trace"] = urls
        outcome.update({"version": sc.RELEASE["version"], "scope": "private loopback process, public binary, actual runtime adapter",
                        "native_systemd_openrc": "EXTERNAL QUALIFICATION PENDING",
                        "legacy_client_traffic": "EXTERNAL QUALIFICATION PENDING",
                        "temporary_daemon_stopped": True, "active_runtime_pointer_removed": not runtime.current.exists()})
    outcome["temporary_directory_removed"] = not root.exists()
    if args.output:
        sc.save(args.output, outcome)
    print(json.dumps(outcome, indent=2))


if __name__ == "__main__":
    main()
