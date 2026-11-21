#!/usr/bin/env python3
"""Verify the official upgrade, Mieru exports and authenticated SOCKS5 in a private network namespace."""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import socket
import socketserver
import subprocess
import tempfile
import threading
from unittest.mock import patch
from urllib.parse import parse_qs, urlsplit

import yaml

from socks5_probe import address_field, parse_udp_packet, read_reply_address, recv_exact
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


def listener_pair_port():
    for _ in range(32):
        with socket.socket() as tcp, socket.socket(type=socket.SOCK_DGRAM) as udp:
            tcp.bind(("127.0.0.1", 0))
            port = tcp.getsockname()[1]
            try:
                udp.bind(("127.0.0.1", port + 1))
            except OSError:
                continue
            return port
    raise AssertionError("no available Mieru listener pair")


def rejected(category, operation, detail=""):
    try:
        operation()
    except sc.Failure as exc:
        check(exc.category == category and detail in str(exc), "unexpected failure: " + str(exc))
    else:
        raise AssertionError("expected " + category + " " + detail)


def run_upgrade(runtime, previous, official, supervisor, echo):
    old = previous_runtime(runtime.state.parent)
    original_runtime = old.Runtime(adapter="systemd")
    with patch.object(old.Service, "call", lambda service, *a, **kw: supervisor.call(service, *a, **kw)), \
         patch.object(original_runtime, "firewall"):
        for index, (protocol, values) in enumerate((
            ("mieru", {"PROTOCOL": "BOTH", "USERNAME": "fixture-mieru", "TRAFFIC_PATTERN": "off"}),
            ("snell", {}),
            ("hysteria2", {}),
            ("tuic", {}),
            ("vless-reality", {"VLESS_REALITY_TARGET": "localhost", "VLESS_REALITY_TARGET_PORT": "443"}),
            ("vless-sudoku", {}),
        )):
            if protocol == "mieru":
                port = listener_pair_port()
            else:
                port = vacant(socket.SOCK_DGRAM if protocol in ("hysteria2", "tuic") else socket.SOCK_STREAM)
            with patch.dict(os.environ, dict(values, PORT=str(port), ADVERTISE_HOST="edge.example",
                                             ADVERTISE_PORT=str(40000 + index * 10))):
                original_runtime.protocol(protocol, "install", protocol, previous if protocol == "mieru" else None)
    original = runtime.current.resolve()
    nodes = runtime.desired()["nodes"]
    master_key = (original / "runtime/master.key").read_bytes()
    identities = revision_and_ids(runtime)
    check(len(identities[1]) == 7, "v4.1.0 fixture does not contain all six ordinary protocols")

    runtime.protocol("mieru", "upgrade", artifacts=official)
    current = runtime.current.resolve()
    check(current != original and sc.load(current / "artifact.json")["version"] == "v0.6.5",
          "official release did not become current")
    check(runtime.desired()["nodes"] == nodes and revision_and_ids(runtime) == identities,
          "core upgrade changed node or account identity")
    check((current / "runtime/master.key").read_bytes() == master_key, "core upgrade changed the vault key")
    check(runtime.health(current)["inbound_count"] == 7, "existing protocols did not become healthy")
    print("[PASS] Official v0.5.0 → v0.6.5: seven listeners, database identities, vault key and configuration retained")

    runtime.rollback()
    check(runtime.current.resolve() == original and revision_and_ids(runtime) == identities,
          "rollback did not restore the v0.5.0 generation")
    check(runtime.health(original)["inbound_count"] == 7, "previous listeners did not recover")
    print("[PASS] Official v0.5.0 generation, including encrypted Sudoku, restored and healthy")

    socks_port = vacant()
    with patch.dict(os.environ, {"PORT": str(socks_port), "USERNAME": "fixture-local", "SOCKS5_UDP": "on"}):
        runtime.protocol("socks5", "install", "loopback", artifacts=official)
    current = runtime.current.resolve()
    journal = runtime.transaction.read_bytes()
    rejected("STATE_VERSION_UNSUPPORTED", runtime.rollback, "cannot run the configured SOCKS5 nodes")
    check(runtime.current.resolve() == current and runtime.previous.resolve() == original
          and runtime.transaction.read_bytes() == journal, "incompatible rollback changed the transaction or snapshots")
    profile = runtime.protocol("socks5", "export", "loopback")
    udp_exchange(("127.0.0.1", socks_port), profile, echo.udp.server_address, "127.0.0.1")
    print("[PASS] Loopback SOCKS5 UDP with an OS-assigned port; incompatible downgrade refused before cutover")
    runtime.protocol("socks5", "remove", "loopback")

    current = runtime.current.resolve()
    for kind, offset in ((socket.SOCK_STREAM, 0), (socket.SOCK_DGRAM, 1)):
        with socket.socket(type=kind) as occupied:
            occupied.bind(("127.0.0.1", 0))
            if kind == socket.SOCK_STREAM:
                occupied.listen()
            with patch.dict(os.environ, {"PORT": str(occupied.getsockname()[1] - offset)}):
                rejected("PORT_CONFLICT", lambda: runtime.protocol("mieru", "set-port", "mieru"))
            check(runtime.current.resolve() == current and runtime.desired()["nodes"] == nodes,
                  "occupied TCP or UDP port changed the previous Mieru pair")
    requested = listener_pair_port()
    with patch.dict(os.environ, {"PORT": str(requested)}):
        updated = runtime.protocol("mieru", "set-port", "mieru")["listeners"]
    check([(node["transport"], node["listener"]["port"]) for node in updated] ==
          [("tcp", requested), ("udp", requested + 1)], "Mieru did not update both listeners")
    check([node["display_endpoint"] for node in updated] ==
          [node["document"]["display_endpoint"] for node in sorted(
              (n for n in nodes if n["protocol"] == "mieru"), key=sc.listener_transport)],
          "Mieru display endpoints were overwritten")
    print("[PASS] Mieru BOTH rejects occupied TCP and UDP ports; both listeners move together and keep display endpoints")

    for mode, name, host in (("TCP", "tcp-client", "192.0.2.20"), ("UDP", "udp-client", "2001:db8::20"),
                              ("BOTH", "xiaoe", "unresolved.invalid")):
        port = listener_pair_port() if mode == "BOTH" else vacant(socket.SOCK_DGRAM if mode == "UDP" else socket.SOCK_STREAM)
        with patch.dict(os.environ, {"PORT": str(port), "ADVERTISE_HOST": host, "ADVERTISE_PORT": "7099",
                                     "PROTOCOL": mode, "USERNAME": "fixture-auth-" + mode, "TRAFFIC_PATTERN": "off"}):
            installed = runtime.protocol("mieru", "install", name)["client_profiles"][0]
        summary = sorted(runtime.protocol("mieru", "status", name)["nodes"], key=lambda item: item["transport"])
        profile = runtime.protocol("mieru", "export", name)["client_profiles"][0]
        native = profile["mieru"]["profiles"][0]
        proxies = yaml.safe_load(profile["mihomo"])["proxies"]
        transports = ["TCP", "UDP"] if mode == "BOTH" else [mode]
        link = urlsplit(profile["uri"])
        query = parse_qs(link.query)
        check(profile == installed and profile["id"] != name and all(item["name"] == name for item in summary),
              "Mieru display name or stable ID differs after creation")
        check([item["transport"].upper() for item in summary] == transports
              and [item["listener"]["port"] for item in summary] == list(range(port, port + len(transports))),
              "Mieru did not bind the requested transport and port")
        check(profile["mieru"]["activeProfile"] == native["profileName"] == proxies[0]["name"] == name
              and query["profile"] == [name] and link.hostname == host, "Mieru client names or URI host mismatch")
        check([item["transport"] for item in proxies] == query["protocol"] == transports
              and native["servers"][0]["portBindings"] ==
              [{"port": 7099 + i, "protocol": transport} for i, transport in enumerate(transports)]
              and query["port"] == [str(item["port"]) for item in proxies], "Mieru exported incorrect ports or transports")
        check(link.username == native["user"]["name"] == "fixture-auth-" + mode
              and link.password == native["user"]["password"] == proxies[0]["password"], "Mieru authentication differs across formats")
    shown = sc.command(["bash", ROOT / "install-nobrand.sh", "mieru", "show", "--user", "fixture-auth-BOTH"]).stdout
    check(b"xiaoe" in shown and b"profile=xiaoe" in shown, "custom name missing in installer output")
    listed = sc.command(["bash", "-c",
                         'manager=$1; set --; MITA_SOURCE_ONLY=1; source "$manager"; NOBRAND_PROTOCOL_FILTER=mieru; nobrand_nodes',
                         "nobrand-nodes", ROOT / "install-nobrand.sh"]).stdout
    check(sum(node["name"] == "xiaoe" for node in json.loads(listed)["nodes"]) == 2, "custom name missing in node list")
    print("[PASS] Native Mieru TCP, UDP and BOTH creation, xiaoe display name and matching URI/YAML/native authentication")


def authenticate(sock, profile, accepted=True):
    sock.sendall(b"\x05\x02\x00\x02")
    check(recv_exact(sock, 2) == b"\x05\x02", "server did not insist on RFC 1929")
    user, secret = profile["username"].encode(), profile["password"].encode()
    sock.sendall(b"\x01" + bytes([len(user)]) + user + bytes([len(secret)]) + secret)
    check(recv_exact(sock, 2) == (b"\x01\x00" if accepted else b"\x01\x01"), "unexpected authentication result")
    if not accepted:
        check(not sock.recv(1), "failed authentication left the connection open")


def request(sock, operation, host, port):
    sock.sendall(bytes([5, operation, 0]) + address_field(host) + port.to_bytes(2, "big"))


def tcp_exchange(proxy, profile, target):
    with socket.create_connection(proxy, timeout=3) as sock:
        authenticate(sock, profile)
        request(sock, 1, *target)
        read_reply_address(sock)
        payload = b"authenticated SOCKS5"
        sock.sendall(payload)
        check(recv_exact(sock, len(payload)) == payload, "authenticated TCP payload did not travel end to end")


def udp_exchange(proxy, profile, target, advertised, ports=range(1, 65536)):
    with socket.create_connection(proxy, timeout=3) as control, socket.socket(type=socket.SOCK_DGRAM) as stream:
        stream.bind((control.getsockname()[0], 0))
        stream.settimeout(3)
        authenticate(control, profile)
        request(control, 3, *stream.getsockname())
        host, port = read_reply_address(control)
        check(host == advertised and port in ports, "wrong UDP relay advertisement")
        payload = b"authenticated SOCKS5 UDP"
        packet = b"\x00\x00\x00" + address_field(target[0]) + target[1].to_bytes(2, "big") + payload
        # The fixture routes the announced port to the local bind, as a same-port NAT would.
        stream.sendto(packet, (proxy[0], port))
        check(parse_udp_packet(stream.recv(1024)) == payload, "UDP payload did not travel end to end")


def unsupported_request(proxy, profile, operation):
    with socket.create_connection(proxy, timeout=3) as sock:
        authenticate(sock, profile)
        request(sock, operation, "0.0.0.0", 0)
        check(recv_exact(sock, 2) == b"\x05\x07", "unsupported SOCKS5 request was accepted")


def check_exports(runtime, expected):
    profile = runtime.protocol("socks5", "export", "fixture")
    check(profile["authentication_required"] and profile["udp"] == expected, "generic export capabilities differ")
    for fmt in ("mihomo", "sing-box"):
        exported = json.loads(sc.command(["bash", ROOT / "install-nobrand.sh", "socks5", "export",
                                         "--name", "fixture", "--format", fmt]).stdout)
        client = exported["proxies"][0] if fmt == "mihomo" else exported
        check(client["username"] == profile["username"] and client["password"] == profile["password"],
              "SOCKS5 export omitted authentication")
        if fmt == "mihomo":
            check(client["type"] == "socks5" and client["udp"] == expected, "Mihomo UDP flag differs")
        else:
            check(client["type"] == "socks" and client["version"] == "5"
                  and client.get("network") == (None if expected else "tcp"), "sing-box UDP network differs")
    return profile


def run_socks5(runtime, official, echo, log_path, bind):
    profile_id = "i0000000000000001"
    time = "2026-01-01T00:00:00Z"
    ingress_file = runtime.state / "ingress.json"
    sc.save(ingress_file, {
        "schema_version": 3, "ownership": "nobrand-v3", "feature": "ingress-profiles", "default_profile_id": None,
        "profiles": [{"profile_id": profile_id, "name": "Private fixture", "type": "mapped", "interface": "lo",
                      "local_address": bind, "ingress_enforcement": "strict", "port_policy": "manual-only",
                      "range_start": None, "range_end": None, "reserved_ports": [22207], "enabled": True,
                      "display_host_default": "edge.example", "display_port_policy": "custom", "display_port": 1080,
                      "created_at": time, "updated_at": time}]
    })
    port = vacant()
    node = "fixture"
    proxy = (bind, port)
    env = {"PORT": str(port), "USERNAME": "fixture-user", "PASSWORD": "", "ADVERTISE_HOST": "edge.example",
           "ADVERTISE_PORT": "1080", "NOBRAND_SPLICORE_LISTEN": bind, "NOBRAND_SPLICORE_INGRESS_ID": profile_id}

    def operate(operation, **options):
        with patch.dict(os.environ, options):
            return runtime.protocol("socks5", operation, node)

    with patch.dict(os.environ, env):
        rejected("CONFIG_INVALID", lambda: operate("install"), "--allow-cleartext-remote")
        check(not runtime.current.exists(), "rejected cleartext install changed active state")
        with patch.dict(os.environ, {"SOCKS5_ALLOW_CLEARTEXT_REMOTE": "1"}):
            installed = runtime.protocol("socks5", "install", node, artifacts=official)
        check("client_profiles" not in installed, "installation exposed credentials")
        profile = check_exports(runtime, False)
        secret = profile["password"]
        check(profile["host"] == "edge.example" and profile["port"] == 1080 and len(secret) >= 32,
              "generic export lacks the required SOCKS5 parameters")
        shown = sc.command(["bash", ROOT / "install-nobrand.sh", "socks5", "show", "--name", node]).stdout
        check(secret.encode() in shown and b"RFC 1929" in shown, "explicit show did not render authentication details")
        current = runtime.current.resolve()
        resource = sc.load(current / "resource-map.json")
        exported = json.loads(sc.command([current / "splicore", "inbound", "export", "--config", current / "bootstrap.yaml",
                                          "--id", next(iter(resource.values())), "--format", "mihomo",
                                          "--client-version", "1.19.32"]).stdout)
        check(secret in json.dumps(exported), "vault-backed Core export failed")
        check(secret.encode() not in (current / "runtime/state.db").read_bytes(), "plaintext password found in Core database")
        check((current / "desired.json").stat().st_mode & 0o777 == 0o600, "desired credentials file is not private")
        with socket.create_connection(proxy, timeout=3) as sock:
            sock.sendall(b"\x05\x01\x00")
            check(recv_exact(sock, 2) == b"\x05\xff", "anonymous SOCKS5 handshake accepted")
        with socket.create_connection(proxy, timeout=3) as sock:
            authenticate(sock, dict(profile, password="incorrect-password"), accepted=False)
        tcp_exchange(proxy, profile, ("localhost", echo.tcp.server_address[1]))
        tcp_exchange(proxy, profile, echo.tcp.server_address)

        class IPv6TCP(socketserver.ThreadingTCPServer):
            address_family = socket.AF_INET6
            daemon_threads = True

        with IPv6TCP(("::1", 0), TCP) as server:
            worker = threading.Thread(target=server.serve_forever)
            worker.start()
            try:
                tcp_exchange(proxy, profile, server.server_address[:2])
            finally:
                server.shutdown()
                worker.join()
        unsupported_request(proxy, profile, 3)
        unsupported_request(proxy, profile, 2)
        print("[PASS] SOCKS5 RFC 1929 forced; anonymous and wrong credentials rejected; TCP CONNECT to IPs and domain works")

        rejected("CONFIG_INVALID", lambda: operate("set-udp", SOCKS5_UDP="on"), "--udp-advertise")
        with socket.socket(type=socket.SOCK_DGRAM) as occupied:
            occupied.bind((bind, 22202))
            rejected("PORT_CONFLICT", lambda: operate("set-udp", SOCKS5_UDP="on",
                     SOCKS5_UDP_ADVERTISE=bind, SOCKS5_UDP_PORT_RANGE="22201-22203"))
        rejected("PORT_CONFLICT", lambda: operate("set-udp", SOCKS5_UDP="on",
                 SOCKS5_UDP_ADVERTISE=bind, SOCKS5_UDP_PORT_RANGE="22206-22207"), "reserved by its ingress profile")
        check(runtime.current.resolve() == current, "rejected UDP enable changed the active generation")
        operate("set-udp", SOCKS5_UDP="on", SOCKS5_UDP_LISTEN=bind,
                SOCKS5_UDP_ADVERTISE="relay.example", SOCKS5_UDP_PORT_RANGE="22201-22203")
        profile = check_exports(runtime, True)
        udp_exchange(proxy, profile, echo.udp.server_address, "relay.example", range(22201, 22204))
        check(runtime.owned_firewall_pairs() == {f"TCP|{port}", "UDP|22201-22203"}, "UDP range firewall ownership differs")
        rows = sc.command(["bash", "-c", 'manager=$1; set --; MITA_SOURCE_ONLY=1; source "$manager"; nb_registry_rows',
                           "nobrand-registry", ROOT / "install-nobrand.sh"]).stdout.decode()
        check(all(f"|UDP|{p}|relay.example|{p}" in rows for p in range(22201, 22204)), "UDP ports missing in the registry")
        current = runtime.current.resolve()
        with patch.dict(os.environ, {"PORT": "22202", "PROTOCOL": "UDP", "TRAFFIC_PATTERN": "off"}):
            rejected("PORT_CONFLICT", lambda: runtime.protocol("mieru", "install", "udp-conflict"), "relay")
        rejected("CONFIG_INVALID", lambda: operate("set-udp-relay", SOCKS5_UDP_LISTEN="0.0.0.0"), "strict ingress address")
        check(runtime.current.resolve() == current, "rejected relay edit changed the active generation")
        ingress = sc.load(ingress_file)
        ingress["profiles"][0]["ingress_enforcement"] = "permissive"
        sc.save(ingress_file, ingress)
        operate("set-udp-relay", SOCKS5_UDP_LISTEN="0.0.0.0")
        ingress["profiles"][0]["ingress_enforcement"] = "strict"
        sc.save(ingress_file, ingress)
        rejected("CONFIG_INVALID", lambda: operate("set-listen"), "strict ingress address")
        operate("set-udp-relay", SOCKS5_UDP_LISTEN=bind)
        current = runtime.current.resolve()

        firewall = runtime.firewall

        def fail_after_open(action, pairs):
            firewall(action, pairs)
            if action == "open" and "UDP|22202-22204" in pairs:
                raise sc.Failure("FIREWALL", "synthetic firewall failure after adding the replacement range")

        with patch.object(runtime, "firewall", side_effect=fail_after_open):
            rejected("FIREWALL", lambda: operate("set-udp-relay", SOCKS5_UDP_PORT_RANGE="22202-22204"))
        check(runtime.current.resolve() == current and sc.load(runtime.transaction)["phase"] == "ROLLED_BACK"
              and runtime.owned_firewall_pairs() == {f"TCP|{port}", "UDP|22201-22203"},
              "failed relay edit did not restore previous firewall ownership and generation")
        udp_exchange(proxy, profile, echo.udp.server_address, "relay.example", range(22201, 22204))

        operate("set-udp-relay", SOCKS5_UDP_ADVERTISE=bind, SOCKS5_UDP_PORT_RANGE="22202-22204")
        check(runtime.owned_firewall_pairs() == {f"TCP|{port}", "UDP|22202-22204"}, "relay edit left stale firewall ownership")
        udp_exchange(proxy, profile, echo.udp.server_address, bind, range(22202, 22205))
        operate("set-udp", SOCKS5_UDP="off")
        check_exports(runtime, False)
        check(runtime.owned_firewall_pairs() == {f"TCP|{port}"}, "UDP disable retained the firewall range")
        unsupported_request(proxy, profile, 3)
        tcp_exchange(proxy, profile, echo.tcp.server_address)
        print("[PASS] SOCKS5 UDP relay, exports, registry, range conflicts, strict bind, firewall updates and rollback")

        operate("set-udp", SOCKS5_UDP="on", SOCKS5_UDP_ADVERTISE=bind, SOCKS5_UDP_PORT_RANGE="22202-22204")
        new_port = vacant()
        while new_port == port:
            new_port = vacant()
        changed = operate("set-port", PORT=str(new_port))["listeners"][0]
        proxy = (bind, new_port)
        check(changed["listener"]["port"] == new_port and changed["display_endpoint"] == {"host": "edge.example", "port": 1080},
              "moving the SOCKS5 port changed the independent client endpoint")
        operate("set-username", USERNAME="renamed-user")
        operate("rotate-password")
        latest = check_exports(runtime, True)
        check(latest["username"] == "renamed-user" and latest["password"] != secret, "SOCKS5 credentials did not rotate")
        with socket.create_connection(proxy, timeout=3) as sock:
            authenticate(sock, dict(latest, password=secret), accepted=False)
        for operation in ("status", "doctor"):
            report = json.dumps(operate(operation))
            check(secret not in report and latest["password"] not in report, "diagnostics exposed a SOCKS5 password")
        backup = runtime.state.parent / "socks5-backup.tar.gz"
        runtime.backup(backup)
        check(backup.stat().st_mode & 0o777 == 0o600, "SOCKS5 backup is not private")
        operate("stop")
        check(not operate("status")["nodes"][0]["enabled"] and not runtime.owned_firewall_pairs(), "SOCKS5 stop retained active ownership")
        with socket.socket() as stopped:
            stopped.settimeout(3)
            check(stopped.connect_ex(proxy) != 0, "stopped SOCKS5 port remained open")
        operate("start")
        udp_exchange(proxy, latest, echo.udp.server_address, bind, range(22202, 22205))
        operate("remove")
        check(not operate("status")["nodes"] and not runtime.owned_firewall_pairs(), "SOCKS5 node survived removal")
        runtime.restore(backup, artifacts=official)
        check(operate("export") == latest, "backup restore changed the SOCKS5 credentials or UDP flag")
        tcp_exchange(proxy, latest, echo.tcp.server_address)
        udp_exchange(proxy, latest, echo.udp.server_address, bind, range(22202, 22205))
        runtime.stop()
        check(not runtime.owned_firewall_pairs(), "whole-runtime stop retained SOCKS5 bindings")
        runtime.start()
        check(runtime.owned_firewall_pairs() == {f"TCP|{new_port}", "UDP|22202-22204"},
              "whole-runtime start did not restore SOCKS5 bindings")
        udp_exchange(proxy, latest, echo.udp.server_address, bind, range(22202, 22205))
        logs = log_path.read_bytes()
        check(secret.encode() not in logs and latest["password"].encode() not in logs, "daemon log exposed SOCKS5 passwords")
        runtime.uninstall(purge=True)
        check(not runtime.home.exists() and not runtime.owned_firewall_pairs(), "unified runtime purge retained SOCKS5 resources")
        print("[PASS] SOCKS5 username/password rotation, redaction, port change, stop/start, remove and backup restore")


def simulate_firewall(runtime, action, pairs):
    """Model the host backend while exercising NoBrand's exact range transactions."""
    if not pairs:
        return
    owned = runtime.owned_firewall_pairs()
    updated = owned | pairs if action == "open" else owned - pairs
    lines = ("iptables|" + row.lower() + "\n" for row in sorted(updated))
    sc.atomic(runtime.state / "firewall-owned.bindings", "".join(lines))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--previous-artifacts", type=Path, required=True)
    parser.add_argument("--artifacts", type=Path, required=True)
    parser.add_argument("--relay-address", default="192.0.2.90", help="non-loopback fixture address already assigned in the test namespace")
    args = parser.parse_args()
    os.umask(0o077)
    for name in ("upgrade", "socks5"):
        with tempfile.TemporaryDirectory(prefix="sc65-") as directory, Echo() as echo:
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
                         patch.object(runtime, "firewall", side_effect=lambda *a: simulate_firewall(runtime, *a)):
                        if name == "upgrade":
                            run_upgrade(runtime, args.previous_artifacts, args.artifacts, supervisor, echo)
                        else:
                            run_socks5(runtime, args.artifacts, echo, log_path, args.relay_address)
                finally:
                    stop(supervisor.child)


if __name__ == "__main__":
    main()
