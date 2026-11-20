#!/usr/bin/env python3
"""Exercise the pinned upgrade and a separately built SOCKS5 core on loopback."""
import argparse
import copy
import importlib.util
import ipaddress
import json
import os
from pathlib import Path
import socket
import socketserver
import subprocess
import tempfile
import threading
from unittest.mock import patch

from splicore_native_probe import Echo, ROOT, Supervisor, TCP, check, sc, stop, vacant


def previous_runtime(work):
    source = work / "v410"
    source.mkdir()
    for filename in ("splicore.py", "splicore-release.json", "splicore-launch.py"):
        data = subprocess.check_output(["git", "show", f"v4.1.0:runtime/{filename}"], cwd=ROOT)
        (source / filename).write_bytes(data)
    spec = importlib.util.spec_from_file_location("nobrand_v410", source / "splicore.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def revision_and_ids(runtime):
    current = runtime.current.resolve()
    page = json.loads(sc.command([current / "splicore", "inbound", "list",
                                  "--config", current / "bootstrap.yaml"]).stdout)
    return page["snapshot_revision"], {item["inbound"]["id"]: [
        (binding["binding_id"], binding["account_id"]) for binding in item["bindings"]
    ] for item in page["items"]}


def run_upgrade(runtime, previous, official, supervisor):
    old = previous_runtime(runtime.state.parent)
    original_runtime = old.Runtime(adapter="systemd")
    with patch.object(old.Service, "call", lambda service, *a, **kw: supervisor.call(service, *a, **kw)), \
         patch.object(original_runtime, "firewall"):
        for protocol, values in (
            ("mieru", {"PROTOCOL": "BOTH", "USERNAME": "fixture-mieru", "TRAFFIC_PATTERN": "off"}),
            ("snell", {}),
            ("hysteria2", {}),
            ("tuic", {}),
            ("vless-reality", {"VLESS_REALITY_TARGET": "localhost", "VLESS_REALITY_TARGET_PORT": "443"}),
            ("vless-sudoku", {}),
        ):
            if protocol == "mieru":
                for _ in range(32):
                    with socket.socket() as tcp, socket.socket(type=socket.SOCK_DGRAM) as udp:
                        tcp.bind(("127.0.0.1", 0))
                        port = tcp.getsockname()[1]
                        try:
                            udp.bind(("127.0.0.1", port + 1))
                            break
                        except OSError:
                            continue
                else:
                    raise AssertionError("no available Mieru listener pair")
            else:
                port = vacant(socket.SOCK_DGRAM if protocol in ("hysteria2", "tuic") else socket.SOCK_STREAM)
            with patch.dict(os.environ, dict(values, PORT=str(port))):
                original_runtime.protocol(protocol, "install", protocol, previous if protocol == "mieru" else None)
    original = runtime.current.resolve()
    nodes = runtime.desired()["nodes"]
    master_key = (original / "runtime/master.key").read_bytes()
    identities = revision_and_ids(runtime)
    check(len(identities[1]) == 7, "v4.1.0 fixture does not contain all six ordinary protocols")

    runtime.protocol("mieru", "upgrade", artifacts=official)
    current = runtime.current.resolve()
    check(current != original and sc.load(current / "artifact.json")["version"] == "v0.6.4",
          "official release did not become current")
    check(runtime.desired()["nodes"] == nodes and revision_and_ids(runtime) == identities,
          "core upgrade changed node or account identity")
    check((current / "runtime/master.key").read_bytes() == master_key, "core upgrade changed the vault key")
    check(runtime.health(current)["inbound_count"] == 7, "existing protocols did not become healthy")
    print("Official v0.5.0 → v0.6.4: 7 listeners, existing database identities and configuration retained")

    runtime.rollback()
    check(runtime.current.resolve() == original and revision_and_ids(runtime) == identities,
          "rollback did not restore the v0.5.0 generation")
    check(runtime.health(original)["inbound_count"] == 7, "previous listeners did not recover")
    print("Official v0.5.0 generation, including encrypted Sudoku, restored and healthy")

    runtime.protocol("mieru", "upgrade", artifacts=official)
    current = runtime.current.resolve()
    with socket.socket(type=socket.SOCK_DGRAM) as occupied:
        occupied.bind(("127.0.0.1", 0))
        with patch.dict(os.environ, {"PORT": str(occupied.getsockname()[1] - 1)}):
            try:
                runtime.protocol("mieru", "set-port", "mieru")
            except sc.Failure as exc:
                check(exc.category == "PORT_CONFLICT", "expected the unavailable UDP port to be rejected")
            else:
                raise AssertionError("Mieru was allowed to move onto a conflicting UDP port")
        check(runtime.current.resolve() == current and runtime.desired()["nodes"] == nodes,
              "UDP conflict changed the previous Mieru pair")
    with patch.dict(os.environ, {"PORT": str(vacant())}):
        requested = int(os.environ["PORT"])
        updated = runtime.protocol("mieru", "set-port", "mieru")["listeners"]
    check([(node["transport"], node["listener"]["port"]) for node in updated] ==
          [("tcp", requested), ("udp", requested + 1)], "Mieru did not update both listeners")
    check([node["display_endpoint"] for node in updated] ==
          [node["document"]["display_endpoint"] for node in sorted(
              (n for n in nodes if n["protocol"] == "mieru"), key=sc.listener_transport)],
          "Mieru display endpoints were overwritten")
    print("Native Mieru BOTH: occupied UDP port rejected and both listeners moved together")


def receive(sock, count):
    with sock.makefile("rb", buffering=0) as stream:
        data = bytearray()
        while len(data) < count:
            part = stream.read(count - len(data))
            check(part, "unexpected SOCKS5 EOF")
            data.extend(part)
        return bytes(data)


def run_socks5(runtime, binary, echo, log_path):
    identity = json.loads(sc.command([binary, "version", "--json"]).stdout)
    check(identity["version"] == "v0.6.4-dev.socks5", "expected separately versioned development build")
    development = copy.deepcopy(sc.RELEASE)
    development.update(version=identity["version"], commit=identity["commit"], qualification="Local SOCKS5 test build")
    development["assets"][sc.arch()]["binary_sha256"] = digest = sc.sha(binary)
    development["capabilities"]["socks5"] = {"managed": True}

    def local_artifact(path, *_args):
        sc.atomic(path, binary.read_bytes(), 0o700)
        check(sc.sha(path) == digest, "local development binary changed during the test")
        return {"version": development["version"], "architecture": sc.arch(),
                "binary_sha256": digest, "identity": sc.binary_identity(path, sc.arch())}

    def wire(port, username, password, expected=True, command=1, destination=None):
        with socket.create_connection(("127.0.0.1", port), timeout=2) as sock:
            sock.sendall(b"\x05\x02\x00\x02")
            check(receive(sock, 2) == b"\x05\x02", "server did not insist on RFC 1929")
            user, secret = username.encode(), password.encode()
            sock.sendall(b"\x01" + bytes([len(user)]) + user + bytes([len(secret)]) + secret)
            check(receive(sock, 2) == (b"\x01\x00" if expected else b"\x01\x01"), "unexpected authentication result")
            if not expected:
                check(not sock.recv(1), "failed authentication left the connection open")
                return
            host, target_port = destination or ("localhost", echo.tcp.server_address[1])
            try:
                ip = ipaddress.ip_address(host)
            except ValueError:
                address = bytes([3, len(host)]) + host.encode("ascii")
            else:
                address = bytes([1 if ip.version == 4 else 4]) + ip.packed
            sock.sendall(bytes([5, command, 0]) + address + target_port.to_bytes(2, "big"))
            reply = receive(sock, 4)
            check(reply[0] == 5 and reply[1] == (0 if command == 1 else 7), "unexpected CONNECT/UDP ASSOCIATE result")
            receive(sock, 6 if reply[3] == 1 else 18)
            if command == 1:
                sock.sendall(b"authenticated SOCKS5")
                check(receive(sock, 20) == b"authenticated SOCKS5", "payload did not travel over the authenticated connection")

    port, new_port = vacant(), vacant()
    while new_port == port:
        new_port = vacant()
    with patch.object(sc, "RELEASE", development), patch.object(sc, "artifact", local_artifact), \
         patch.dict(os.environ, {"PORT": str(port), "USERNAME": "fixture-user", "PASSWORD": "",
                                 "ADVERTISE_HOST": "edge.example", "ADVERTISE_PORT": "1080"}):
        result = runtime.protocol("socks5", "install", "fixture")
        check("client_profiles" not in result, "installation exposed credentials")
        profile = runtime.protocol("socks5", "export", "fixture")
        secret = profile["password"]
        check(profile["host"] == "edge.example" and profile["port"] == 1080 and profile["authentication_required"]
              and len(secret) >= 32, "generic export lacks the required SOCKS5 parameters")
        check(runtime.protocol("socks5", "show", "fixture")["client_profiles"][0]["connection"] == profile,
              "show and export credentials differ")
        shown = sc.command(["bash", ROOT / "install-nobrand.sh", "socks5", "show", "--name", "fixture"]).stdout
        check(secret.encode() in shown and b"RFC 1929" in shown, "installer show did not render authentication details")
        exported = sc.command(["bash", ROOT / "install-nobrand.sh", "socks5", "export", "--name", "fixture"]).stdout
        check(json.loads(exported) == profile, "installer export did not return the connection JSON")
        for format_name, expected in (("mihomo", {"type": "socks5", "udp": False}),
                                      ("sing-box", {"type": "socks", "network": "tcp", "version": "5"})):
            with patch.dict(os.environ, {"NOBRAND_SPLICORE_EXPORT_FORMAT": format_name}):
                exported = runtime.protocol("socks5", "export", "fixture")
            client = exported["proxies"][0] if format_name == "mihomo" else exported
            check(all(client.get(key) == value for key, value in expected.items()), "client export advertised incorrect capabilities")
        current = runtime.current.resolve()
        resource = sc.load(current / "resource-map.json")
        exported = json.loads(sc.command([current / "splicore", "inbound", "export", "--config", current / "bootstrap.yaml",
                                          "--id", next(iter(resource.values())), "--format", "mihomo",
                                          "--client-version", "1.19.32"]).stdout)
        check(secret in json.dumps(exported), "vault-backed core export failed")
        check(secret.encode() not in (current / "runtime/state.db").read_bytes(), "plaintext password found in core SQLite database")
        check((current / "desired.json").stat().st_mode & 0o777 == 0o600, "desired credentials file is not private")
        with socket.create_connection(("127.0.0.1", port), timeout=2) as sock:
            sock.sendall(b"\x05\x01\x00")
            check(receive(sock, 2) == b"\x05\xff", "anonymous SOCKS5 handshake accepted")
        wire(port, profile["username"], "incorrect-password", expected=False)
        wire(port, profile["username"], secret)
        wire(port, profile["username"], secret, destination=echo.tcp.server_address)
        class IPv6TCP(socketserver.ThreadingTCPServer):
            address_family = socket.AF_INET6
            daemon_threads = True

        with IPv6TCP(("::1", 0), TCP) as server:
            worker = threading.Thread(target=server.serve_forever)
            worker.start()
            try:
                wire(port, profile["username"], secret, destination=server.server_address[:2])
            finally:
                server.shutdown()
                worker.join()
        wire(port, profile["username"], secret, command=3)

        with patch.dict(os.environ, {"PORT": str(new_port)}):
            changed = runtime.protocol("socks5", "set-port", "fixture")["listeners"][0]
        check(changed["listener"]["port"] == new_port and changed["display_endpoint"] == {"host": "edge.example", "port": 1080},
              "moving the SOCKS5 port changed the independent client endpoint")
        with patch.dict(os.environ, {"USERNAME": "renamed-user"}):
            runtime.protocol("socks5", "set-username", "fixture")
        runtime.protocol("socks5", "rotate-password", "fixture")
        latest = runtime.protocol("socks5", "export", "fixture")
        check(latest["username"] == "renamed-user" and latest["password"] != secret, "SOCKS5 credential rotation failed")
        wire(new_port, latest["username"], secret, expected=False)
        wire(new_port, latest["username"], latest["password"])
        for operation in ("status", "doctor"):
            report = json.dumps(runtime.protocol("socks5", operation, "fixture"))
            check(secret not in report and latest["password"] not in report, "diagnostics exposed a SOCKS5 password")
        backup = runtime.state.parent / "socks5-backup.tar.gz"
        runtime.backup(backup)
        check(backup.stat().st_mode & 0o777 == 0o600, "SOCKS5 backup is not private")
        runtime.protocol("socks5", "stop", "fixture")
        check(not runtime.protocol("socks5", "status")["nodes"][0]["enabled"], "SOCKS5 node did not stop")
        with socket.socket() as stopped:
            stopped.settimeout(2)
            check(stopped.connect_ex(("127.0.0.1", new_port)) != 0, "stopped SOCKS5 port remained open")
        runtime.protocol("socks5", "start", "fixture")
        wire(new_port, latest["username"], latest["password"])
        runtime.protocol("socks5", "remove", "fixture")
        check(not runtime.protocol("socks5", "status")["nodes"], "SOCKS5 node survived removal")
        runtime.restore(backup)
        check(runtime.protocol("socks5", "export", "fixture") == latest, "backup restore changed the SOCKS5 credentials")
        wire(new_port, latest["username"], latest["password"])
        logs = log_path.read_bytes()
        check(secret.encode() not in logs and latest["password"].encode() not in logs, "daemon log exposed SOCKS5 passwords")
        runtime.uninstall(purge=True)
        check(not runtime.home.exists(), "unified core purge retained SOCKS5 state")
    print("Development SOCKS5: required authentication, CONNECT, UDP rejection, export, rotation, lifecycle and backup restored")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--previous-artifacts", type=Path, required=True)
    parser.add_argument("--artifacts", type=Path, required=True)
    parser.add_argument("--socks5-binary", type=Path, required=True)
    args = parser.parse_args()
    os.umask(0o077)
    for name in ("upgrade", "socks5"):
        with tempfile.TemporaryDirectory(prefix="sc64-") as directory, Echo() as echo:
            work = Path(directory)
            env = {"NOBRAND_SYSTEM_ROOT": str(work), "NOBRAND_STATE_DIR": str(work / "s"),
                   "NOBRAND_CONFIG_DIR": str(work / "c"), "NOBRAND_LIB_DIR": str(work / "l"),
                   "NOBRAND_LIFECYCLE_DIR": str(work / "j"), "NOBRAND_LIFECYCLE_LOCK_FILE": str(work / "lock"),
                   "NOBRAND_SPLICORE_UNIT": str(work / "unit"), "NOBRAND_SPLICORE_LISTEN": "127.0.0.1",
                   "NOBRAND_SPLICORE_MANAGER_SOURCE": str(ROOT / "install-nobrand.sh"),
                   "NOBRAND_TEST_LOCAL_IPV4": "192.0.2.241", "ADVERTISE_HOST": "127.0.0.1", "ADVERTISE_PORT": ""}
            log_path = work / "daemon.log"
            with patch.dict(os.environ, env), log_path.open("wb") as log:
                runtime = sc.Runtime(adapter="systemd")
                supervisor = Supervisor(runtime, log)
                try:
                    with patch.object(sc.Service, "call", lambda service, *a, **kw: supervisor.call(service, *a, **kw)), \
                         patch.object(runtime, "firewall"):
                        if name == "upgrade":
                            run_upgrade(runtime, args.previous_artifacts, args.artifacts, supervisor)
                        else:
                            run_socks5(runtime, args.socks5_binary, echo, log_path)
                finally:
                    stop(supervisor.child)


if __name__ == "__main__":
    main()
