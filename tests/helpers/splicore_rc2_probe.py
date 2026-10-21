#!/usr/bin/env python3
"""Qualify public rc.2 artifacts in temporary storage; never install a runtime.

This is an integration audit, not an installer or an alternative state writer.
All credentials are synthetic. No SQLite writes, system service changes, root
access, external destinations, or Splicore source/build tree are required.
"""

import argparse
import copy
import hashlib
import io
import json
import os
from pathlib import Path, PurePosixPath
import platform
import socket
import struct
import subprocess
import tarfile
import tempfile
import time
import unittest


ROOT = Path(__file__).resolve().parents[2]
MANIFEST = ROOT / "runtime/splicore-release.json"


class Rejected(ValueError):
    pass


def architecture(value):
    aliases = {"x86_64": "amd64", "amd64": "amd64",
               "aarch64": "arm64", "arm64": "arm64"}
    if value not in aliases:
        raise Rejected("ARCH_UNSUPPORTED: unsupported architecture")
    return aliases[value]


def checksum_entry(text, asset):
    entries = []
    for line in text.splitlines():
        parts = line.split()
        name = parts[1] if len(parts) == 2 else ""
        if name.startswith("*"):
            name = name[1:]
        if len(parts) == 2 and name == asset:
            entries.append(parts[0])
    if len(entries) != 1 or len(entries[0]) != 64:
        raise Rejected("CHECKSUM_MISMATCH: missing or duplicate exact entry")
    try:
        bytes.fromhex(entries[0])
    except ValueError as exc:
        raise Rejected("CHECKSUM_MISMATCH: malformed digest") from exc
    return entries[0].lower()


def inspect_archive(archive):
    """Allow only the observed release layout, regular files and directories."""
    seen = set()
    total = 0
    members = archive.getmembers()
    if len(members) > 512:
        raise Rejected("ARCHIVE_INVALID: too many entries")
    for member in members:
        name = member.name
        path = PurePosixPath(name)
        if (not name or path.is_absolute() or "\\" in name or ":" in name
                or any(p in (".", "..", "") for p in name.rstrip("/").split("/"))
                or name in seen or not (member.isfile() or member.isdir())):
            raise Rejected("ARCHIVE_INVALID: unsafe entry")
        seen.add(name)
        expected = name in {"splicore", "LICENSE", "NOTICE.md", "THIRD_PARTY_NOTICES.md"}
        license_path = name.startswith("licenses/third-party/")
        directory = member.isdir() and name.rstrip("/") in {"licenses", "licenses/third-party"}
        if not (expected or license_path or directory):
            raise Rejected("ARCHIVE_INVALID: unexpected entry")
        if expected and not member.isfile():
            raise Rejected("ARCHIVE_INVALID: expected regular file")
        total += member.size
        if total > 128 * 1024 * 1024 or member.size < 0:
            raise Rejected("ARCHIVE_INVALID: size limit")
    if "splicore" not in seen:
        raise Rejected("ARCHIVE_INVALID: missing binary")
    return archive.getmember("splicore")


def verify_archive(path, sums, entry):
    expected = checksum_entry(sums, entry["name"])
    if expected != entry["sha256"]:
        raise Rejected("CHECKSUM_MISMATCH: public checksum differs from recorded pin")
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    if digest.hexdigest() != expected:
        raise Rejected("CHECKSUM_MISMATCH: archive corrupted or interrupted")
    with tarfile.open(path, "r:gz") as archive:
        binary = inspect_archive(archive)
        with archive.extractfile(binary) as stream:
            header = stream.read(20)
        if len(header) != 20 or header[:6] != b"\x7fELF\x02\x01":
            raise Rejected("BINARY_IDENTITY: expected Linux ELF64 little endian")
        machine = struct.unpack_from("<H", header, 18)[0]
        wanted = 62 if "amd64" in entry["name"] else 183
        if machine != wanted:
            raise Rejected("BINARY_IDENTITY: wrong architecture")
    return digest.hexdigest()


def run(arguments, success=True, expected_error=None):
    result = subprocess.run([str(a) for a in arguments], capture_output=True,
                            text=True, timeout=20, check=False)
    if (result.returncode == 0) != success:
        # Never include a document, credential or command argument in errors.
        verb = str(arguments[1]) if len(arguments) > 1 else "command"
        if verb == "inbound" and len(arguments) > 2:
            verb += " " + str(arguments[2])
        raise Rejected("CONTRACT: unexpected exit status for " + verb)
    if expected_error is not None and expected_error not in result.stderr:
        raise Rejected("CONTRACT: expected typed rejection was not observed")
    return result.stdout


def write_json(path, value):
    path.write_text(json.dumps(value), encoding="utf-8")
    path.chmod(0o600)


def vacant_port(kind):
    with socket.socket(socket.AF_INET, kind) as listener:
        listener.bind(("127.0.0.1", 0))
        return listener.getsockname()[1]


def probe(artifacts):
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))["rollback_releases"]["v0.3.0-rc.2"]
    arch = architecture(platform.machine())
    if platform.system() != "Linux":
        raise Rejected("ARCH_UNSUPPORTED: probe requires Linux")
    sums = (artifacts / manifest["checksum_asset"]).read_text(encoding="ascii")
    result = {"version": manifest["version"], "migration_ready": False,
              "artifacts": {}, "checks": {}}
    for target_arch, entry in manifest["assets"].items():
        digest = verify_archive(artifacts / entry["name"], sums, entry)
        result["artifacts"][target_arch] = {"sha256": digest, "archive_safety": "PASS",
                                              "qualification": entry["qualification"]}
    with tempfile.TemporaryDirectory(prefix="nb-splicore-rc2-") as directory:
        work = Path(directory)
        work.chmod(0o700)
        binary = work / "splicore"
        # Extract exactly one already inspected regular file; never extractall.
        with tarfile.open(artifacts / manifest["assets"][arch]["name"], "r:gz") as archive:
            with archive.extractfile("splicore") as source, binary.open("xb") as dest:
                for chunk in iter(lambda: source.read(1024 * 1024), b""):
                    dest.write(chunk)
        binary.chmod(0o700)
        identity = json.loads(run([binary, "version", "--json"]))
        if (identity.get("product") != "Splicore" or identity.get("version") != manifest["version"]
                or identity.get("commit") != manifest["commit"] or identity.get("dirty") is not False
                or identity.get("platform") != "linux/" + arch):
            raise Rejected("BINARY_IDENTITY: release identity differs")
        result["binary_identity"] = identity
        state = work / "state"
        state.mkdir(mode=0o700)
        bootstrap = work / "bootstrap.yaml"
        bootstrap.write_text(f"schema: 1\nstate_directory: {state}\nkey_file: {state}/master.key\n"
                             f"api:\n  unix_socket: {work}/control.sock\n", encoding="utf-8")
        bootstrap.chmod(0o600)
        run([binary, "validate", bootstrap])
        run([binary, "key", "init", "--file", state / "master.key"])
        cert, key = work / "cert.pem", work / "key.pem"
        ca, ca_key, request = work / "ca.pem", work / "ca.key", work / "leaf.csr"
        run(["openssl", "req", "-new", "-x509", "-newkey", "rsa:2048", "-nodes",
             "-days", "1", "-subj", "/CN=Probe CA", "-addext", "basicConstraints=critical,CA:TRUE",
             "-keyout", ca_key, "-out", ca])
        run(["openssl", "req", "-new", "-newkey", "rsa:2048", "-nodes", "-subj", "/CN=probe.example",
             "-keyout", key, "-out", request])
        extensions = work / "leaf.ext"
        extensions.write_text("basicConstraints=critical,CA:FALSE\nsubjectAltName=DNS:probe.example\n"
                              "extendedKeyUsage=serverAuth\n", encoding="ascii")
        run(["openssl", "x509", "-req", "-in", request, "-CA", ca, "-CAkey", ca_key,
             "-CAcreateserial", "-days", "1", "-extfile", extensions, "-out", cert])
        key.chmod(0o600)
        tls = {"server_name": "probe.example", "certificate_file": str(cert),
               "private_key_file": str(key), "ca_certificate": ca.read_text(encoding="ascii")}
        documents = {}
        for protocol in ("hysteria2", "tuic", "mieru"):
            port = vacant_port(socket.SOCK_STREAM if protocol == "mieru" else socket.SOCK_DGRAM)
            document = {"schema": 1, "name": "probe-" + protocol,
                        "listener": {"host": "127.0.0.1", "port": port},
                        "display_endpoint": {"host": "127.0.0.1", "port": port}}
            user = {"account_name": "probe-" + protocol, "password": "synthetic-probe-password"}
            if protocol == "mieru":
                document["settings"] = {"transport": "tcp", "mtu": 1400, "multiplex": "off"}
                user["username"] = "synthetic-probe-user"
            elif protocol == "tuic":
                document["settings"] = {"version": 5, "tls": tls, "congestion_control": "cubic",
                                        "udp_relay_mode": "native", "zero_rtt_handshake": False}
                user["uuid"] = "11111111-1111-4111-8111-111111111111"
            else:
                document["settings"] = {"tls": tls}
            document["users"] = [user]
            documents[protocol] = document
        port = vacant_port(socket.SOCK_STREAM)
        documents["snell"] = {"schema": 1, "account_name": "probe-snell", "name": "probe-snell",
                              "listener": {"host": "127.0.0.1", "port": port},
                              "display_endpoint": {"host": "127.0.0.1", "port": port},
                              "settings": {"version": 5}, "psk": "synthetic-probe-psk"}

        def validate(label, protocol, document, success):
            path = work / "document.json"
            write_json(path, document)
            try:
                run([binary, "inbound", "validate", "--protocol", protocol, "--file", path], success)
            except Rejected as exc:
                raise Rejected("CONTRACT: validation differs for " + label) from exc
            result["checks"][label] = "ACCEPTED" if success else "REJECTED"

        for protocol, document in documents.items():
            validate(protocol + "_base", protocol, document, True)
        hy2 = copy.deepcopy(documents["hysteria2"])
        hy2["settings"]["obfs"] = {"type": "salamander", "password": "synthetic-obfs"}
        validate("hy2_salamander", "hysteria2", hy2, False)
        hy2 = copy.deepcopy(documents["hysteria2"])
        hy2["settings"]["stream_transport"] = {"kind": "hysteria", "hysteria": {
            "version": 2, "obfs": {"type": "salamander", "password": "synthetic-obfs"}}}
        validate("hy2_transport_salamander", "hysteria2", hy2, False)
        for field, value in (("trafficPattern", {"seed": 1}), ("handshakeMode", "HANDSHAKE_NO_WAIT"),
                             ("lowEntropy", {"mode": "LOW_ENTROPY_MODE_OFF"})):
            doc = copy.deepcopy(documents["mieru"])
            doc["settings"][field] = value
            validate("mieru_" + field, "mieru", doc, False)
        doc = copy.deepcopy(documents["mieru"])
        doc["users"][0]["traffic_policy"] = {"quota_bytes": 1024}
        validate("mieru_strict_quota", "mieru", doc, False)
        doc = copy.deepcopy(documents["mieru"])
        doc["settings"]["transport"] = "both"
        validate("mieru_one_listener_both", "mieru", doc, False)
        doc = copy.deepcopy(documents["snell"])
        doc["settings"]["quic_proxy_enabled"] = True
        validate("snell_quic", "snell", doc, False)
        for label, psk in (("short_psk", "12345678"), ("punctuated_psk", "synthetic.psk:12")):
            doc = copy.deepcopy(documents["snell"])
            doc["psk"] = psk
            validate("snell_" + label, "snell", doc, False)
        doc = copy.deepcopy(documents["snell"])
        doc["settings"]["version"] = 4
        validate("snell_v4", "snell", doc, True)
        # Exercise the current NoBrand certificate generators, with private
        # temporary paths and no main/install action. Do not change certificates
        # just to make a candidate pass.
        for protocol in ("tuic", "hysteria2"):
            old_dir = work / ("old-" + protocol)
            old_dir.mkdir(mode=0o700)
            old_cert, old_key = old_dir / "cert.pem", old_dir / "key.pem"
            if protocol == "tuic":
                generation = 'tuic_generate_certificate "$PROBE_CERT" "$PROBE_KEY" probe.example'
            else:
                generation = ('NOBRAND_HY2_CONFIG_DIR="$(dirname "$PROBE_CERT")"; '
                              'NOBRAND_HY2_CERT_FILE="$PROBE_CERT"; NOBRAND_HY2_KEY_FILE="$PROBE_KEY"; '
                              'HY2_SNI=probe.example; generate_hysteria2_cert')
            run(["bash", "-c", 'PROBE_INSTALLER=$1; PROBE_CERT=$2; PROBE_KEY=$3; set --; '
                 'MITA_SOURCE_ONLY=1; source "$PROBE_INSTALLER"; ' + generation,
                 "probe", ROOT / "install-nobrand.sh", old_cert, old_key])
            doc = copy.deepcopy(documents[protocol])
            doc["name"] = "probe-old-certificate-" + protocol
            doc["users"][0]["account_name"] = "probe-old-certificate-" + protocol
            doc["listener"]["port"] = vacant_port(socket.SOCK_DGRAM)
            doc["display_endpoint"]["port"] = doc["listener"]["port"]
            doc["settings"]["tls"] = {"server_name": "probe.example", "certificate_file": str(old_cert),
                                      "private_key_file": str(old_key),
                                      "ca_certificate": old_cert.read_text(encoding="ascii")}
            documents[protocol + "_old_certificate"] = doc
        # Production startup is only in this private directory and on loopback.
        with (work / "daemon.log").open("w", encoding="utf-8") as log:
            daemon = subprocess.Popen([str(binary), "run", "--config", str(bootstrap)],
                                      stdout=log, stderr=log)
            try:
                deadline = time.monotonic() + 10
                while not (work / "control.sock").exists():
                    if daemon.poll() is not None or time.monotonic() > deadline:
                        raise Rejected("SERVICE_START: isolated daemon failed")
                    time.sleep(0.05)
                inbound_ids = []
                for protocol, document in documents.items():
                    if protocol.endswith("_old_certificate"):
                        continue
                    path, plan = work / "document.json", work / "plan.json"
                    write_json(path, document)
                    planned = json.loads(run([binary, "inbound", "plan", "--protocol", protocol,
                                              "--config", bootstrap, "--file", path]))
                    write_json(plan, planned)
                    run([binary, "inbound", "apply", "--protocol", protocol, "--config", bootstrap,
                         "--file", path, "--plan", plan])
                    page = json.loads(run([binary, "inbound", "list", "--config", bootstrap]))
                    if len(page["items"]) != len(inbound_ids) + 1:
                        raise Rejected("HEALTH: inbound count differs")
                    inbound_ids = [item["inbound"]["id"] for item in page["items"]]
                if any(item["health"] != "healthy" for item in page["items"]):
                    raise Rejected("HEALTH: inbound unhealthy")
                result["checks"]["isolated_four_protocol_single_process"] = "PASS (no traffic qualification)"
                result["checks"]["isolated_inbound_count"] = len(page["items"])
                for protocol in ("tuic", "hysteria2"):
                    path, plan = work / "document.json", work / "plan.json"
                    doc = documents[protocol + "_old_certificate"]
                    write_json(path, doc)
                    # Depending on the OpenSSL host defaults, the certificate
                    # is either a CA (rejected at apply) or has no CA anchor
                    # (rejected at plan). Record the precise stage.
                    planned = subprocess.run([str(binary), "inbound", "plan", "--protocol", protocol,
                                              "--config", str(bootstrap), "--file", str(path)],
                                             capture_output=True, text=True, timeout=20, check=False)
                    if planned.returncode == 0:
                        write_json(plan, json.loads(planned.stdout))
                        run([binary, "inbound", "apply", "--protocol", protocol, "--config", bootstrap,
                             "--file", path, "--plan", plan], False, "invalid: command rejected")
                        result["checks"][protocol + "_existing_certificate"] = "REJECTED at apply"
                    else:
                        if "invalid: command rejected" not in planned.stderr:
                            raise Rejected("CONTRACT: certificate plan failed for a different reason")
                        result["checks"][protocol + "_existing_certificate"] = "REJECTED at plan"
                    unchanged = json.loads(run([binary, "inbound", "list", "--config", bootstrap]))
                    if len(unchanged["items"]) != 4:
                        raise Rejected("HEALTH: failed certificate apply changed state")
                for action in ("remove", "delete", "start", "stop", "restart", "update"):
                    run([binary, "inbound", action, "--config", bootstrap, "--id", inbound_ids[0]], False)
                    result["checks"]["inbound_" + action] = "REJECTED for existing inbound ID"
                for item in page["items"]:
                    endpoint = f"http://localhost/api/v1/inbounds/{item['inbound']['id']}"
                    code = run(["curl", "--silent", "--show-error", "--max-time", "5", "--unix-socket",
                                work / "control.sock", "--request", "DELETE", "--output", "/dev/null",
                                "--write-out", "%{http_code}", endpoint])
                    if code != "405":
                        raise Rejected("CONTRACT: unexpected inbound DELETE result")
                result["checks"]["inbound_delete_api"] = "405 Method Not Allowed (all four live resources)"
            finally:
                daemon.terminate()
                try:
                    daemon.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    daemon.kill()
                    daemon.wait(timeout=5)
        result["checks"]["temporary_daemon_stopped"] = "PASS"
    result["checks"]["temporary_directory_removed"] = "PASS"
    return result


class SafetyTests(unittest.TestCase):
    def test_architectures(self):
        for value, wanted in (("x86_64", "amd64"), ("amd64", "amd64"),
                              ("aarch64", "arm64"), ("arm64", "arm64")):
            self.assertEqual(architecture(value), wanted)
        for value in ("i386", "armv7l", "", "amd64/../../"):
            with self.assertRaises(Rejected):
                architecture(value)

    def test_checksum_entries(self):
        digest = "ab" * 32
        self.assertEqual(checksum_entry(digest + "  asset.tar.gz\n", "asset.tar.gz"), digest)
        for text in (digest + "  other.tar.gz", digest + "  **asset.tar.gz",
                     (digest + "  asset.tar.gz\n") * 2,
                     "bad  asset.tar.gz", "zz" * 32 + "  asset.tar.gz"):
            with self.assertRaises(Rejected):
                checksum_entry(text, "asset.tar.gz")

    @staticmethod
    def archive(entries):
        data = io.BytesIO()
        with tarfile.open(fileobj=data, mode="w:gz") as archive:
            for name, kind in entries:
                item = tarfile.TarInfo(name)
                item.type = kind
                archive.addfile(item, io.BytesIO())
        data.seek(0)
        return tarfile.open(fileobj=data, mode="r:gz")

    def test_archive_safety(self):
        with self.archive([("splicore", tarfile.REGTYPE)]) as archive:
            self.assertEqual(inspect_archive(archive).name, "splicore")
        for name, kind in (("/splicore", tarfile.REGTYPE), ("../splicore", tarfile.REGTYPE),
                           ("licenses/third-party/../../splicore", tarfile.REGTYPE),
                           ("splicore", tarfile.SYMTYPE), ("splicore", tarfile.LNKTYPE),
                           ("splicore", tarfile.FIFOTYPE), ("extra.sh", tarfile.REGTYPE),
                           ("C:/splicore", tarfile.REGTYPE), ("licenses\\bad", tarfile.REGTYPE)):
            entries = [(name, kind)] if name == "splicore" else [("splicore", tarfile.REGTYPE), (name, kind)]
            with self.archive(entries) as archive:
                with self.assertRaises(Rejected):
                    inspect_archive(archive)
        for entries in ([("LICENSE", tarfile.REGTYPE)],
                        [("splicore", tarfile.REGTYPE), ("splicore", tarfile.REGTYPE)]):
            with self.archive(entries) as archive:
                with self.assertRaises(Rejected):
                    inspect_archive(archive)

    def test_corrupted_or_partial_download(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "asset.tar.gz"
            path.write_bytes(b"partial download")
            entry = {"name": path.name, "sha256": "ab" * 32}
            with self.assertRaisesRegex(Rejected, "CHECKSUM_MISMATCH"):
                verify_archive(path, entry["sha256"] + "  " + path.name, entry)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--artifacts", type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    if args.self_test:
        suite = unittest.defaultTestLoader.loadTestsFromTestCase(SafetyTests)
        return 0 if unittest.TextTestRunner(verbosity=2).run(suite).wasSuccessful() else 1
    if not args.artifacts:
        parser.error("--artifacts must contain both public archives and official SHA256SUMS")
    os.umask(0o077)
    try:
        result = probe(args.artifacts.resolve())
    except (Rejected, OSError, ValueError, tarfile.TarError, subprocess.SubprocessError) as exc:
        # Fixed error categories only; paths/documents may carry operator data.
        detail = str(exc) if isinstance(exc, Rejected) else "external operation failed"
        print(json.dumps({"probe": "FAIL", "category": type(exc).__name__, "detail": detail}))
        return 1
    output = json.dumps(result, indent=2) + "\n"
    if args.output:
        args.output.write_text(output, encoding="utf-8")
        args.output.chmod(0o600)
    print(output, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
