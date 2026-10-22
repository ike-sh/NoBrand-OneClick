#!/usr/bin/env bash
# AUTO-GENERATED FILE.
# Source files live under src/.
# Do not edit this generated file directly.
# Run scripts/build.sh after modifying src/.

nb_splicore_python() {
  python3 - "$@" <<'NOBRAND_SPLICORE_PY'
import json
RELEASE = json.loads(r'''
{
  "repository": "ike-sh/Splicore",
  "version": "v0.3.0-rc.4",
  "commit": "2634ea50d19623591c5db63329a288862726db74",
  "checksum_asset": "SHA256SUMS",
  "qualification": "Release Candidate / Experimental",
  "rollback_releases": {},
  "capabilities": {
    "snell": {
      "managed": true,
      "fresh_install": "v4/v5; QUIC disabled"
    },
    "mieru": {
      "managed": true,
      "fresh_install": "TCP/UDP/BOTH; traffic off; no quota, expiry or rate"
    },
    "tuic": {
      "managed": true,
      "fresh_install": "v5; verified non-CA leaf and explicit CA"
    },
    "hysteria2": {
      "managed": true,
      "salamander": true,
      "gecko": {
        "core": "SUPPORTED / EXPERIMENTAL",
        "nobrand_surface": "NOT EXPOSED"
      },
      "udp_port_hopping": {
        "core": "SUPPORTED",
        "nobrand_surface": "NOT EXPOSED"
      },
      "linux_server_port_range": {
        "core": "SUPPORTED",
        "nobrand_surface": "NOT EXPOSED",
        "qualification": "PENDING EXTERNAL QUALIFICATION; nftables and CAP_NET_ADMIN required"
      },
      "fresh_install": "new private CA and server leaf; verified client trust; native Salamander"
    },
    "vless-reality": {
      "managed": true,
      "core_vision": true,
      "core_flow_none": true,
      "local_tunnel_guard": true,
      "fresh_install": "raw TCP + Vision + native protected destination"
    },
    "vless-sudoku": {
      "managed": false,
      "requires_external_xray": true,
      "scope": "existing specialized pinned Xray exception"
    }
  },
  "assets": {
    "amd64": {
      "name": "splicore-v0.3.0-rc.4-linux-amd64.tar.gz",
      "sha256": "9dd1941c817143d18ea1c892a5fc13266c1b209600576946504a9d3c98c62161",
      "binary_sha256": "0a347f06f0d1a17ef37edd779826ad79739217b65f80bf39dc6077f115ac175f",
      "qualification": "Experimental; external runtime qualification pending"
    },
    "arm64": {
      "name": "splicore-v0.3.0-rc.4-linux-arm64.tar.gz",
      "sha256": "5b5e39bd8e6ef373ebc00e7e3a8a688ce09d0369dc2c4ecfab06ed535d948b64",
      "binary_sha256": "85ec863d21707ac309a4c7a64b3b7228eb34bb0405379db6b569d8d550032a4c",
      "qualification": "BUILD ONLY; runtime qualification pending"
    }
  }
}
''')
LAUNCHER = r'''
"""Single exec launcher: own one daemon and clear only a proven dead socket."""
import errno
import fcntl
import os
from pathlib import Path
import socket
import stat

generation = Path(__file__).resolve().parent
guard = os.open(str(generation / "daemon.lock"), os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
fcntl.flock(guard, fcntl.LOCK_EX | fcntl.LOCK_NB)
os.set_inheritable(guard, True)
control = generation / "control.sock"
try:
    before = control.lstat()
except FileNotFoundError:
    before = None
if before is not None:
    if not stat.S_ISSOCK(before.st_mode) or before.st_uid != os.geteuid():
        raise SystemExit("refuse foreign control socket entry")
    with socket.socket(socket.AF_UNIX) as probe:
        probe.settimeout(1)
        try:
            probe.connect(str(control))
        except OSError as error:
            if error.errno != errno.ECONNREFUSED:
                raise SystemExit("control socket is not proven stale")
        else:
            raise SystemExit("daemon is already active")
    after = control.lstat()
    if (before.st_dev, before.st_ino) != (after.st_dev, after.st_ino):
        raise SystemExit("control socket changed during startup")
    control.unlink()
os.umask(0o077)
binary = str(generation / "splicore")
os.execv(binary, [binary, "run", "--config", str(generation / "bootstrap.yaml")])
'''
"""NoBrand's single-daemon adapter. Embedded into the standalone installer.

Only public CLI/API operations are used. Canonical NoBrand intent is independent
of Splicore's SQLite store. No protocol implementation or direct SQL access.
"""
import argparse
import base64
import secrets
import contextlib
import copy
import datetime
import fcntl
import hashlib
import io
import ipaddress
import json
import os
from pathlib import Path, PurePosixPath
import platform
import re
import shutil
import signal
import socket
import ssl
import stat
import struct
import subprocess
import sys
import tarfile
import tempfile
import time
import uuid
from urllib.parse import quote

try:
    RELEASE
except NameError:
    RELEASE = json.loads(Path(__file__).with_name("splicore-release.json").read_text())
try:
    LAUNCHER
except NameError:
    LAUNCHER = Path(__file__).with_name("splicore-launch.py").read_text()


class Failure(Exception):
    def __init__(self, category, detail):
        self.category = category
        super().__init__(detail)


LEGACY_NOTICE = """Legacy NoBrand multi-core installation detected.
Automatic in-place migration is not supported by this version.
No changes were made.

Recommended:
1. Back up current client information.
2. Remove the legacy installation using the matching legacy NoBrand version.
3. Perform a clean installation.
4. Import/use the newly generated client profiles."""


def require(condition, category, detail):
    if not condition:
        raise Failure(category, detail)


def load(path):
    def unique(pairs):
        out = {}
        for key, value in pairs:
            require(key not in out, "CONFIG_INVALID", "duplicate JSON key")
            out[key] = value
        return out
    return json.loads(Path(path).read_text(encoding="utf-8"), object_pairs_hook=unique)


def sync_dir(path):
    fd = os.open(str(path), os.O_RDONLY | os.O_DIRECTORY)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


def atomic(path, data, mode=0o600):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    require(not path.is_symlink(), "CONFIG_INVALID", "refuse symlink destination")
    fd, name = tempfile.mkstemp(prefix=".candidate-", dir=str(path.parent))
    try:
        os.fchmod(fd, mode)
        with os.fdopen(fd, "wb") as out:
            out.write(data if isinstance(data, bytes) else data.encode("utf-8"))
            out.flush()
            os.fsync(out.fileno())
        os.replace(name, path)
        sync_dir(path.parent)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def save(path, value):
    atomic(path, json.dumps(value, indent=2, sort_keys=True) + "\n")


def sha(path):
    digest = hashlib.sha256()
    with Path(path).open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def remove_file(path):
    try:
        Path(path).unlink()
    except FileNotFoundError:
        pass


def within(path, root):
    try:
        return os.path.commonpath([str(Path(path).resolve()), str(Path(root).resolve())]) == str(Path(root).resolve())
    except ValueError:
        return False


def command(args, category="CONFIG_INVALID", timeout=30, ok=True, env=None):
    try:
        result = subprocess.run([str(a) for a in args], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                timeout=timeout, check=False, env=env)
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise Failure(category, "external command unavailable or timed out") from exc
    if ok:
        # Core CLI errors are redacted by its public contract. Only expose the
        # bounded typed error line; never echo stdout, documents or argv.
        message = result.stderr.decode("utf-8", errors="replace").strip()
        safe_error = message if len(message) <= 300 and re.fullmatch(r"[a-z_]+: [A-Za-z0-9 ,./()_-]+", message) else "external command rejected"
        require(result.returncode == 0, category, safe_error)
    return result


def arch(value=None):
    normalized = {"x86_64": "amd64", "amd64": "amd64", "aarch64": "arm64", "arm64": "arm64"}
    require((value or platform.machine()) in normalized, "ARCH_UNSUPPORTED", "unsupported architecture")
    return normalized[value or platform.machine()]


def inspect_archive(path, entry, sums):
    lines = [line.split() for line in sums.splitlines()]
    matches = [parts[0] for parts in lines if len(parts) == 2 and parts[1] == entry["name"]]
    require(len(matches) == 1 and re.fullmatch(r"[0-9a-fA-F]{64}", matches[0] or ""),
            "CHECKSUM_MISMATCH", "missing, duplicate or malformed exact SHA256SUMS entry")
    require(matches[0].lower() == entry["sha256"] == sha(path),
            "CHECKSUM_MISMATCH", "archive does not match official checksum and immutable pin")
    with tarfile.open(path, "r:gz") as archive:
        members, names, size = archive.getmembers(), set(), 0
        require(len(members) <= 512, "ARCHIVE_INVALID", "too many archive entries")
        for member in members:
            name = member.name
            require(name and not PurePosixPath(name).is_absolute() and "\\" not in name and ":" not in name
                    and all(p not in ("", ".", "..") for p in name.rstrip("/").split("/"))
                    and name not in names and (member.isfile() or member.isdir()),
                    "ARCHIVE_INVALID", "unsafe archive entry")
            names.add(name)
            root_file = name in {"splicore", "LICENSE", "NOTICE.md", "THIRD_PARTY_NOTICES.md"}
            require((root_file and member.isfile()) or name.startswith("licenses/third-party/")
                    or (member.isdir() and name.rstrip("/") in {"licenses", "licenses/third-party"}),
                    "ARCHIVE_INVALID", "unexpected archive entry")
            size += member.size
            require(0 <= member.size and size <= 128 * 1024 * 1024, "ARCHIVE_INVALID", "archive size limit")
        require("splicore" in names, "ARCHIVE_INVALID", "missing binary")
        with archive.extractfile("splicore") as src:
            header = src.read(20)
        require(len(header) == 20 and header[:6] == b"\x7fELF\x02\x01"
                and struct.unpack_from("<H", header, 18)[0] == (62 if "amd64" in entry["name"] else 183),
                "BINARY_IDENTITY", "wrong executable architecture")


def download(url, path, proxy=""):
    require(url.startswith("https://github.com/"), "NETWORK", "unapproved release URL")
    target = url
    if proxy:
        require(proxy.startswith("https://") and not any(c.isspace() for c in proxy),
                "NETWORK", "GitHub proxy requires an HTTPS prefix")
        target = proxy.rstrip("/") + "/" + url
    result = command(["curl", "--fail", "--silent", "--show-error", "--location",
                      "--write-out", "%{http_code}",
                      "--proto", "=https", "--proto-redir", "=https", "--connect-timeout", "15",
                      "--max-time", "180", "--retry", "2", "--output", path, target],
                     "NETWORK", timeout=600, ok=False)
    if result.returncode:
        category = "HTTP" if result.returncode == 22 else "NETWORK"
        if result.returncode == 22 and result.stdout.strip() == b"404":
            category = "ASSET_NOT_FOUND"
        raise Failure(category, "pinned Splicore release download failed")


def binary_identity(binary, target_arch, release=None):
    release = release or RELEASE
    result = command([binary, "version", "--json"], "BINARY_IDENTITY")
    identity = json.loads(result.stdout)
    require(identity.get("product") == "Splicore" and identity.get("version") == release["version"]
            and identity.get("commit") == release["commit"] and identity.get("dirty") is False
            and identity.get("platform") == "linux/" + target_arch,
            "BINARY_IDENTITY", "exact release identity differs")
    return identity


def artifact(destination, directory=None, proxy="", target_arch=None):
    target_arch = target_arch or arch()
    require(target_arch in RELEASE["assets"], "ARCH_UNSUPPORTED", "unsupported architecture")
    entry = RELEASE["assets"][target_arch]
    with tempfile.TemporaryDirectory(prefix="nb-splicore-download-") as tmp:
        staging = Path(tmp)
        archive, sums = staging / entry["name"], staging / RELEASE["checksum_asset"]
        if directory:
            source = Path(directory)
            require((source / entry["name"]).is_file(), "ASSET_NOT_FOUND", "pinned archive missing")
            require((source / RELEASE["checksum_asset"]).is_file(), "CHECKSUM_MISMATCH", "official SHA256SUMS missing")
            shutil.copyfile(source / entry["name"], archive)
            shutil.copyfile(source / RELEASE["checksum_asset"], sums)
        else:
            base = "https://github.com/" + RELEASE["repository"] + "/releases/download/" + RELEASE["version"] + "/"
            download(base + entry["name"], archive, proxy)
            download(base + RELEASE["checksum_asset"], sums, proxy)
        inspect_archive(archive, entry, sums.read_text(encoding="ascii"))
        candidate = staging / "splicore"
        with tarfile.open(archive, "r:gz") as package:
            with package.extractfile("splicore") as src:
                atomic(candidate, src.read(), 0o700)
        require(sha(candidate) == entry["binary_sha256"], "BINARY_IDENTITY", "extracted binary differs from release pin")
        identity = binary_identity(candidate, target_arch)
        atomic(destination, candidate.read_bytes(), 0o700)
    return {"version": RELEASE["version"], "architecture": target_arch,
            "archive_sha256": entry["sha256"], "binary_sha256": sha(destination),
            "identity": identity, "qualification": entry["qualification"]}


def identifier(value):
    require(isinstance(value, str) and re.fullmatch(r"[a-zA-Z0-9][a-zA-Z0-9_-]{0,47}", value),
            "CONFIG_INVALID", "invalid node ID")
    return value


def inspect_backup_archive(path):
    """Reject unsafe entries before any generic product tar extraction."""
    names, total, registry = set(), 0, None
    with tarfile.open(path, "r:gz") as archive:
        for member in archive:
            name = member.name.rstrip("/")
            require(name and not PurePosixPath(name).is_absolute() and "\\" not in name and ":" not in name
                    and all(p not in ("", ".", "..") for p in name.split("/"))
                    and name not in names and (member.isfile() or member.isdir()),
                    "ARCHIVE_INVALID", "unsafe backup entry before extraction")
            require(name == "manifest.txt" or name in ("state", "config") or name.startswith(("state/", "config/")),
                    "ARCHIVE_INVALID", "unexpected product backup root")
            names.add(name)
            total += member.size
            require(len(names) <= 20000 and 0 <= member.size and total <= 1024 * 1024 * 1024,
                    "ARCHIVE_INVALID", "product backup size/count limit")
            if name == "state/state.json":
                require(member.isfile() and member.size <= 1024 * 1024, "ARCHIVE_INVALID", "invalid architecture marker")
                registry = json.loads(archive.extractfile(member).read())
    require({"manifest.txt", "state", "config"}.issubset(names), "ARCHIVE_INVALID", "incomplete product backup")
    require(isinstance(registry, dict) and registry.get("architecture") == "splicore-native",
            "UNSUPPORTED_LEGACY_INSTALLATION", LEGACY_NOTICE)
    require(not any(name.startswith(("state/mieru/", "state/snell/", "state/tuic/", "state/hysteria2/",
                                    "state/vless-reality/", "config/hysteria2/", "config/vless-reality/")) for name in names),
            "UNSUPPORTED_LEGACY_INSTALLATION", LEGACY_NOTICE)


def keys(value, allowed, context):
    require(isinstance(value, dict) and not set(value).difference(allowed),
            "CONFIG_INVALID", "unknown fields in " + context +
            (": " + ", ".join(sorted(set(value).difference(allowed))) if isinstance(value, dict) else ""))


def multiplex(value):
    value = value.lower().replace("multiplexing_", "", 1)
    require(value in ("off", "low", "middle", "high", "default"), "CONFIG_INVALID", "invalid Mieru multiplexing")
    return value


def handshake(value):
    value = {"no-wait": "HANDSHAKE_NO_WAIT", "standard": "HANDSHAKE_STANDARD"}.get(value, value)
    require(value in ("HANDSHAKE_NO_WAIT", "HANDSHAKE_STANDARD"), "CONFIG_INVALID", "invalid Mieru handshake mode")
    return value


def tls_check(tls):
    keys(tls, {"server_name", "certificate_file", "private_key_file", "ca_certificate"}, "TLS")
    require(all(isinstance(tls.get(k), str) and tls[k] for k in
                ("server_name", "certificate_file", "private_key_file", "ca_certificate")),
            "CONFIG_INVALID", "TLS requires certificate/key paths, SNI and explicit CA")
    certificate, key = Path(tls["certificate_file"]), Path(tls["private_key_file"])
    require(certificate.is_file() and key.is_file() and not key.is_symlink(),
            "CONFIG_INVALID", "TLS files unavailable")
    require(stat.S_IMODE(key.stat().st_mode) & 0o077 == 0
            and stat.S_IMODE(key.parent.stat().st_mode) & 0o077 == 0,
            "CONFIG_INVALID", "TLS key and immediate parent require private permissions")
    with tempfile.TemporaryDirectory(prefix="nb-splicore-tls-") as tmp:
        ca = Path(tmp) / "ca.pem"
        atomic(ca, tls["ca_certificate"])
        try:
            ipaddress.ip_address(tls["server_name"])
            verify_name = "-verify_ip"
        except ValueError:
            verify_name = "-verify_hostname"
        command(["openssl", "verify", "-CAfile", ca, "-purpose", "sslserver", verify_name,
                 tls["server_name"], certificate], "CONFIG_INVALID")
        text = command(["openssl", "x509", "-in", certificate, "-noout", "-text"]).stdout
        require(b"CA:TRUE" not in text, "CAPABILITY_UNSUPPORTED", "rc.4 requires a non-CA TLS leaf")
        if b"X509v3 Key Usage:" in text:
            require(b"Digital Signature" in text.split(b"X509v3 Key Usage:", 1)[1].splitlines()[1],
                    "CONFIG_INVALID", "TLS leaf KeyUsage must allow digitalSignature")
        cert_key = command(["openssl", "x509", "-in", certificate, "-noout", "-pubkey"]).stdout
        private_key = command(["openssl", "pkey", "-in", key, "-pubout"]).stdout
        require(cert_key == private_key, "CONFIG_INVALID", "certificate/private key mismatch")


def hysteria_obfs(settings):
    """NoBrand exposes plain/Salamander; other rc.4 capabilities stay explicit."""
    stream = settings.get("stream_transport")
    if stream is None:
        return {"type": "none"}
    keys(stream, {"kind", "hysteria"}, "HY2 stream_transport")
    require(stream.get("kind") == "hysteria", "CONFIG_INVALID", "HY2 requires hysteria transport")
    transport = stream.get("hysteria", {"version": 2})
    keys(transport, {"version", "obfs"}, "NoBrand HY2 transport (Gecko/UDP hopping core support is not exposed)")
    require(type(transport.get("version")) is int and transport["version"] == 2,
            "CONFIG_INVALID", "HY2 transport version must be 2")
    obfs = transport.get("obfs", {"type": "none"})
    keys(obfs, {"type", "password"}, "HY2 obfs")
    require(obfs.get("type") in ("none", "salamander"), "CAPABILITY_UNSUPPORTED",
            "NoBrand exposes none/salamander; rc.4 Gecko is supported experimental but not exposed")
    if obfs["type"] == "none":
        require(not obfs.get("password"), "CONFIG_INVALID", "plain HY2 cannot carry an obfs password")
    else:
        require(isinstance(obfs.get("password"), str) and 1 <= len(obfs["password"].encode()) <= 1024,
                "CONFIG_INVALID", "Salamander requires a nonempty obfs password (1..1024 bytes)")
    return obfs


def dns_name(value):
    require(isinstance(value, str) and 1 <= len(value) <= 253
            and all(re.fullmatch(r"[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?", part)
                    for part in value.split(".")), "CONFIG_INVALID", "invalid cover DNS name")
    try:
        ipaddress.ip_address(value)
    except ValueError:
        return value
    raise Failure("CONFIG_INVALID", "cover SNI requires a DNS name")


def reality_keypair():
    with tempfile.TemporaryDirectory(prefix="nb-reality-key-") as directory:
        pem = Path(directory) / "key.pem"
        command(["openssl", "genpkey", "-algorithm", "X25519", "-out", pem])
        private = command(["openssl", "pkey", "-in", pem, "-outform", "DER"]).stdout[-32:]
        public = command(["openssl", "pkey", "-in", pem, "-pubout", "-outform", "DER"]).stdout[-32:]
        return tuple(base64.urlsafe_b64encode(value).decode().rstrip("=") for value in (private, public))


def available_tcp_port(desired):
    reserved = {n["document"]["listener"]["port"] for n in desired["nodes"]}
    reserved.update(n["guard"]["listen"]["port"] for n in desired["nodes"] if n.get("guard"))
    for _ in range(32):
        with socket.socket() as listener:
            listener.bind(("127.0.0.1", 0))
            port = listener.getsockname()[1]
        if port not in reserved:
            return port
    raise Failure("PORT_CONFLICT", "cannot reserve a local guard port")


def reality_check(node, document):
    settings = document.get("settings", {})
    keys(settings, {"security", "flow", "transport", "packet_encoding", "stream_transport", "reality"}, "REALITY settings")
    require(settings.get("security") == "reality" and settings.get("flow") in ("none", "xtls-rprx-vision")
            and settings.get("transport") == "tcp" and settings.get("packet_encoding") == "xudp"
            and settings.get("stream_transport", {"kind": "tcp"}) == {"kind": "tcp"},
            "CAPABILITY_UNSUPPORTED", "REALITY requires raw TCP; Vision over HTTP transports is unsupported")
    reality = settings.get("reality", {})
    keys(reality, {"server_name", "server_names", "public_key", "short_ids", "target"}, "REALITY")
    guard = node.get("guard", {})
    keys(guard, {"id", "listen", "target", "approved_sni"}, "local tunnel guard")
    require(str(uuid.UUID(guard.get("id", ""))) == guard.get("id") and uuid.UUID(guard["id"]).version == 4,
            "CONFIG_INVALID", "guard ID must be canonical UUID v4")
    listen, target = guard.get("listen", {}), guard.get("target", {})
    for endpoint in (listen, target):
        keys(endpoint, {"host", "port"}, "guard endpoint")
        require(type(endpoint.get("port")) is int and 1 <= endpoint["port"] <= 65535,
                "CONFIG_INVALID", "invalid guard endpoint port")
    require(listen.get("host") in ("127.0.0.1", "::1") and reality.get("target") == listen
            and listen != target, "CONFIG_INVALID", "REALITY must target its loopback guard")
    dns_name(target.get("host"))
    dns_name(reality.get("server_name"))
    approved = guard.get("approved_sni", [])
    names = reality.get("server_names", [reality["server_name"]])
    require(isinstance(approved, list) and 1 <= len(approved) <= 16 and len(set(approved)) == len(approved)
            and set(names) == set(approved) and reality["server_name"] in approved,
            "CONFIG_INVALID", "guard admission must match the configured handshake names")
    for name in approved:
        dns_name(name)
    secret = document.get("server_secret", {})
    keys(secret, {"private_key"}, "server secret")
    require(isinstance(secret.get("private_key"), str) and len(secret["private_key"]) == 43,
            "CONFIG_INVALID", "REALITY requires a private server key")


def guard_mutations(desired):
    mutations, rules, listeners, ids = [], [], set(), set()
    for node in desired["nodes"]:
        if node["protocol"] != "vless-reality" or not node.get("enabled", True):
            continue
        reality_check(node, node["document"])
        guard = node["guard"]
        identity = guard["id"]
        address = (guard["listen"]["host"], guard["listen"]["port"])
        require(identity not in ids and address not in listeners, "PORT_CONFLICT", "duplicate guard identity/listener")
        ids.add(identity)
        listeners.add(address)
        mutations.append({"resource": "local-inbound", "action": "create", "local_inbound": {
            "id": identity, "name": "NoBrand cover " + node["id"], "kind": "tunnel", "listen": guard["listen"],
            "tunnel": {"target": guard["target"], "network": "tcp"},
            "sniffing": {"enabled": True, "protocols": ["tls"], "route_only": True}}})
        for suffix, match, action in (("allow", {"local_inbounds": [identity], "sniffed_domains": guard["approved_sni"]}, "direct"),
                                      ("reject", {"local_inbounds": [identity]}, "reject")):
            rule_id = uuid.UUID(bytes=hashlib.sha256((identity + suffix).encode()).digest()[:16], version=4)
            rules.append({"id": str(rule_id), "name": "NoBrand guard " + suffix,
                          "match": match, "action": {"kind": action}})
    if mutations:
        # Each generation owns a new, empty Core database. This is its complete
        # network graph; ordinary authenticated payloads retain direct routing.
        mutations.append({"resource": "network", "action": "replace", "network": {
            "route": {"rules": rules}, "rule_sets": [], "policy_groups": [], "dns_servers": [],
            "dns_rules": [], "dns": {"enabled": False}}})
    return mutations


def render(desired, validate_tls=True):
    keys(desired, {"schema", "owner", "nodes", "source", "architecture", "splicore_version", "config_schema"}, "desired state")
    require(desired.get("schema") == 1 and desired.get("architecture") == "splicore-native"
            and desired.get("config_schema") == 1 and desired.get("owner") == "nobrand-splicore-v1"
            and isinstance(desired.get("nodes"), list), "CONFIG_INVALID", "invalid NoBrand runtime authority")
    documents, names, occupied = [], set(), []
    for node in desired["nodes"]:
        keys(node, {"id", "protocol", "enabled", "document", "client", "guard", "options", "ingress"}, "node")
        name = identifier(node.get("id"))
        require(name not in names, "CONFIG_INVALID", "duplicate node ID")
        names.add(name)
        require(type(node.get("enabled", True)) is bool, "CONFIG_INVALID", "enabled must be boolean")
        ingress = node.get("ingress", {})
        keys(ingress, {"profile_id"}, "ingress association")
        require(isinstance(ingress.get("profile_id", ""), str), "CONFIG_INVALID", "invalid ingress profile")
        protocol = node.get("protocol")
        capability = RELEASE["capabilities"].get(protocol, {})
        require(capability.get("managed", False), "CAPABILITY_UNSUPPORTED",
                capability.get("integration_blocker", "protocol/security policy is not qualified by rc.4"))
        options = node.get("options", {})
        keys(options, {"traffic_pattern", "low_entropy", "quota_mb", "expire_at", "bandwidth_mbps",
                       "quic_proxy_enabled", "obfs", "ingress_enforcement"}, "capability options")
        require(options.get("traffic_pattern", "off") in ("off", "none")
                and options.get("low_entropy", "off") in ("off", "LOW_ENTROPY_MODE_OFF")
                and options.get("quota_mb", 0) == 0 and not options.get("expire_at")
                and options.get("bandwidth_mbps", 0) == 0
                and not options.get("quic_proxy_enabled") and (protocol == "hysteria2" or not options.get("obfs"))
                and options.get("ingress_enforcement", "native") == "native",
                "CAPABILITY_UNSUPPORTED", "stored protocol/accounting/security option has no rc.4 equivalent")
        document = copy.deepcopy(node.get("document"))
        require(isinstance(document, dict), "CONFIG_INVALID", "managed document required")
        keys(document, {"schema", "name", "account_name", "listener", "display_endpoint", "settings", "users", "psk", "server_secret"}, "managed document")
        require(document.get("schema") == 1, "CONFIG_INVALID", "managed document schema")
        document["name"] = "nb-" + name
        listener = document.get("listener", {})
        keys(listener, {"host", "port"}, "listener")
        require(isinstance(listener.get("port"), int) and 1 <= listener["port"] <= 65535,
                "CONFIG_INVALID", "invalid listener port")
        endpoint = document.get("display_endpoint", {})
        keys(endpoint, {"host", "port"}, "display endpoint")
        require(isinstance(endpoint.get("host"), str) and endpoint["host"]
                and endpoint["host"] not in ("0.0.0.0", "::")
                and not any(c.isspace() or ord(c) < 32 for c in endpoint["host"])
                and type(endpoint.get("port")) is int and 1 <= endpoint["port"] <= 65535,
                "CONFIG_INVALID", "invalid display endpoint")
        try:
            address = ipaddress.ip_address(listener.get("host", ""))
        except ValueError as exc:
            raise Failure("CONFIG_INVALID", "listener requires an IP address") from exc
        settings = document.get("settings", {})
        transport = "tcp" if protocol in ("snell", "vless-reality") else "udp"
        if protocol == "mieru":
            keys(settings, {"transport", "mtu", "multiplex"}, "Mieru settings")
            transport = settings.get("transport")
            require(transport in ("tcp", "udp"), "CONFIG_INVALID", "BOTH requires two mapped inbounds")
        elif protocol == "snell":
            keys(settings, {"version"}, "Snell settings")
            require(settings.get("version") in (4, 5) and isinstance(document.get("psk"), str)
                    and re.fullmatch(r"[A-Za-z0-9_+/=-]{12,128}", document["psk"]),
                    "CAPABILITY_UNSUPPORTED", "stored Snell PSK/version outside rc.4 domain; rotation required explicitly")
            document["account_name"] = "nb-" + name
        elif protocol == "vless-reality":
            reality_check(node, document)
        else:
            allowed = {"tls", "stream_transport"} if protocol == "hysteria2" else {"version", "tls", "congestion_control", "udp_relay_mode", "zero_rtt_handshake"}
            keys(settings, allowed, protocol + " settings")
            if protocol == "hysteria2":
                obfs = hysteria_obfs(settings)
                require(not options.get("obfs") or options["obfs"] == obfs["type"],
                        "CONFIG_INVALID", "stored HY2 obfs option does not match the native document")
            if validate_tls:
                tls_check(settings.get("tls", {}))
        if protocol != "snell":
            users = document.get("users")
            require(isinstance(users, list) and 1 <= len(users) <= 16, "CONFIG_INVALID", "rc.4 supports 1..16 users per inbound")
            for index, user in enumerate(users):
                keys(user, {"account_name", "username", "uuid", "password"}, "managed user")
                # Internal account identity is independent of wire credentials.
                user["account_name"] = "nb-" + name + "-" + str(index)
                if protocol == "vless-reality":
                    require(str(uuid.UUID(user.get("uuid", ""))) == user.get("uuid"), "CONFIG_INVALID", "invalid VLESS UUID")
                else:
                    require(isinstance(user.get("password"), str) and user["password"], "CONFIG_INVALID", "credentials must be explicit")
        for previous_transport, previous_address, previous_port in occupied:
            overlap = address == previous_address or address.is_unspecified or previous_address.is_unspecified
            # Conservatively reserve wildcard IPv6 against IPv4 too.
            require(not (transport == previous_transport and listener["port"] == previous_port and overlap),
                    "PORT_CONFLICT", "overlapping desired listeners")
        occupied.append((transport, address, listener["port"]))
        if not node.get("enabled", True):
            continue
        documents.append((name, "vless" if protocol == "vless-reality" else protocol, document))
    require(len(documents) <= 64, "CONFIG_INVALID", "rc.4 inbound limit exceeded")
    guard_mutations(desired)
    for node in desired["nodes"]:
        if node.get("guard"):
            port = node["guard"]["listen"]["port"]
            require(not any(t == "tcp" and p == port for t, _a, p in occupied),
                    "PORT_CONFLICT", "guard overlaps a protocol listener")
    return documents


def empty():
    return {"schema": 1, "owner": "nobrand-splicore-v1", "nodes": [], "source": "fresh",
            "architecture": "splicore-native", "splicore_version": RELEASE["version"], "config_schema": 1}


def redacted_plan(desired):
    nodes, blockers = [], []
    for node in desired["nodes"]:
        try:
            documents = render(dict(empty(), nodes=[node]))
            nodes.extend({"id": name, "protocol": protocol, "listener": doc["listener"]}
                         for name, protocol, doc in documents)
        except Failure as exc:
            blockers.append({"id": node.get("id"), "category": exc.category, "detail": str(exc)})
    if not blockers:
        try:
            render(desired)
        except Failure as exc:
            blockers.append({"category": exc.category, "detail": str(exc)})
    return {"target": RELEASE["version"], "nodes": nodes, "blockers": blockers,
            "architecture": "splicore-native",
            "rollback": "previous Splicore generation; first install returns to not installed",
            "external_runtime_qualification": "PENDING"}


def leaf_fingerprint(tls):
    pem = Path(tls["certificate_file"]).read_text()
    leaf = re.search(r"-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----", pem, flags=re.S)
    require(leaf, "CONFIG_INVALID", "TLS leaf unavailable for explicit client pin")
    return hashlib.sha256(ssl.PEM_cert_to_DER_cert(leaf.group())).hexdigest()


def client_profiles(node):
    protocol, document = node["protocol"], node["document"]
    settings, endpoint = document["settings"], document["display_endpoint"]
    host, port = endpoint["host"], endpoint["port"]
    name = node.get("client", {}).get("name") or node["id"]
    out = {"id": node["id"], "protocol": protocol}
    if protocol == "snell":
        # Public rc.4 ClientVersion(5)=4: native v5 admits v4 TCP/UDP
        # clients while QUIC Proxy Mode stays unavailable.
        wire = 4
        out["server_version"], out["client_wire_version"] = settings["version"], wire
        out["surge"] = "{} = snell, {}, {}, psk = {}, version = {}".format(name, host, port, document["psk"], wire)
        out["sing_box"] = {"type": "snell", "tag": name, "server": host, "server_port": port, "version": wire, "psk": document["psk"]}
        out["mihomo"] = ("- name: " + json.dumps(name) + "\n  type: snell\n  server: " + json.dumps(host)
                          + "\n  port: " + str(port) + "\n  psk: " + json.dumps(document["psk"])
                          + "\n  version: " + str(wire) + "\n  udp: true\n")
    elif protocol == "hysteria2":
        password = document["users"][0]["password"]
        sni = settings["tls"]["server_name"]
        obfs = hysteria_obfs(settings)
        address = "[" + host + "]" if ":" in host else host
        fingerprint = leaf_fingerprint(settings["tls"])
        out["uri"] = ("hysteria2://" + quote(password, safe="") + "@" + address + ":" + str(port)
                      + "?sni=" + quote(sni, safe="") + "&alpn=h3&insecure=1&pinSHA256=" + fingerprint)
        outbound = {"type": "hysteria2", "tag": "NoBrand-Hysteria2", "server": host, "server_port": port,
                    "password": password, "tls": {"enabled": True, "server_name": sni, "insecure": False,
                    "certificate": settings["tls"]["ca_certificate"], "alpn": ["h3"]}}
        mihomo = ("- name: NoBrand-Hysteria2\n  type: hysteria2\n  server: " + json.dumps(host)
                  + "\n  port: " + str(port) + "\n  password: " + json.dumps(password)
                  + "\n  sni: " + json.dumps(sni) + "\n  alpn: [h3]\n  skip-cert-verify: false\n  fingerprint: "
                  + json.dumps(fingerprint) + "\n  udp: true\n")
        if obfs["type"] == "salamander":
            outbound["obfs"] = copy.deepcopy(obfs)
            out["uri"] += "&obfs=salamander&obfs-password=" + quote(obfs["password"], safe="")
            mihomo += "  obfs: salamander\n  obfs-password: " + json.dumps(obfs["password"]) + "\n"
        out["uri"] += "#" + quote("NoBrand-Hysteria2", safe="")
        out.update(sing_box=outbound, mihomo=mihomo)
        out["trust"] = {"sing_box": "explicit CA and hostname", "mihomo": "SHA256 leaf pin",
                        "uri": "pinSHA256 is mandatory; PKI bypass is bounded by this explicit pin"}
    elif protocol == "vless-reality":
        reality = settings["reality"]
        user = document["users"][0]
        address = "[" + host + "]" if ":" in host else host
        flow = settings["flow"]
        out["uri"] = ("vless://" + user["uuid"] + "@" + address + ":" + str(port)
            + "?encryption=none&security=reality&type=tcp&flow=" + quote(flow, safe="")
            + "&sni=" + quote(reality["server_name"], safe="") + "&fp=chrome&pbk=" + reality["public_key"]
            + "&sid=" + reality["short_ids"][0] + "#" + quote(name, safe=""))
        proxy = {"name": name, "type": "vless", "server": host, "port": port, "uuid": user["uuid"],
                 "tls": True, "servername": reality["server_name"], "client-fingerprint": "chrome",
                 "reality-opts": {"public-key": reality["public_key"], "short-id": reality["short_ids"][0]},
                 "network": "tcp", "udp": flow == "none"}
        if flow != "none":
            proxy["flow"] = flow
        # JSON flow objects are valid YAML; retain the usual proxies envelope.
        out["mihomo"] = "proxies:\n  - " + json.dumps(proxy) + "\n"
        out["xray"] = {"protocol": "vless", "settings": {"vnext": [{"address": host, "port": port,
            "users": [{"id": user["uuid"], "encryption": "none", "flow": flow}]}]}, "streamSettings": {
            "network": "tcp", "security": "reality", "realitySettings": {"serverName": reality["server_name"],
            "fingerprint": "chrome", "publicKey": reality["public_key"], "shortId": reality["short_ids"][0]}}}
    elif protocol == "mieru":
        user = document["users"][0]
        profile = node.get("client", {}).get("profile", {})
        handshake = node.get("client", {}).get("handshake_mode") or profile.get("HANDSHAKE_MODE", "HANDSHAKE_NO_WAIT")
        mux, transport = "MULTIPLEXING_" + settings.get("multiplex", "off").upper(), settings["transport"].upper()
        address = "[" + host + "]" if ":" in host else host
        out["uri"] = ("mierus://" + quote(user["username"], safe="") + ":" + quote(user["password"], safe="") + "@" + address
                      + "?handshake-mode=" + handshake + "&mtu=" + str(settings["mtu"]) + "&multiplexing=" + mux
                      + "&port=" + str(port) + "&profile=default&protocol=" + transport)
        try:
            ipaddress.ip_address(host)
            ip, domain = host, ""
        except ValueError:
            ip, domain = "", host
        out["mieru"] = {"profiles": [{"profileName": "default", "user": {"name": user["username"], "password": user["password"]},
                        "servers": [{"ipAddress": ip, "domainName": domain, "portBindings": [{"port": port, "protocol": transport}]}],
                        "mtu": settings["mtu"], "multiplexing": {"level": mux}, "handshakeMode": handshake}],
                        "activeProfile": "default", "rpcPort": 8964, "socks5Port": 1080, "loggingLevel": "INFO",
                        "socks5ListenLAN": False, "httpProxyPort": 8080, "httpProxyListenLAN": False}
        out["mihomo"] = ("proxies:\n  - name: mieru-mita-" + transport.lower() + "\n    type: mieru\n    server: " + json.dumps(host)
                         + "\n    port: " + str(port) + "\n    transport: " + transport + "\n    udp: true\n    username: " + json.dumps(user["username"])
                         + "\n    password: " + json.dumps(user["password"]) + "\n    multiplexing: " + mux + "\n    handshake-mode: " + handshake + "\n")
    elif protocol == "tuic":
        profiles = []
        names = node.get("client", {}).get("user_names", [])
        if not names and node.get("client", {}).get("users"):
            names = [u["name"] for u in node["client"]["users"]]
        for index, user in enumerate(document["users"]):
            username = names[index] if index < len(names) else str(index)
            tag = "nobrand-tuic-" + username
            outbound = {"type": "tuic", "tag": tag, "server": host, "server_port": port,
                        "uuid": user["uuid"], "password": user["password"], "congestion_control": settings.get("congestion_control", "cubic"),
                        "udp_relay_mode": settings.get("udp_relay_mode", "native"), "zero_rtt_handshake": settings.get("zero_rtt_handshake", False),
                        "tls": {"enabled": True, "server_name": settings["tls"]["server_name"], "insecure": False,
                                "certificate": settings["tls"]["ca_certificate"], "alpn": ["h3"]}}
            mihomo = ("proxies:\n  - name: " + json.dumps(tag) + "\n    type: tuic\n    server: " + json.dumps(host)
                      + "\n    port: " + str(port) + "\n    uuid: " + json.dumps(user["uuid"])
                      + "\n    password: " + json.dumps(user["password"]) + "\n    sni: " + json.dumps(settings["tls"]["server_name"])
                      + "\n    alpn: [h3]\n    skip-cert-verify: false\n    fingerprint: " + json.dumps(leaf_fingerprint(settings["tls"]))
                      + "\n    congestion-controller: " + outbound["congestion_control"]
                      + "\n    udp-relay-mode: " + outbound["udp_relay_mode"]
                      + "\n    reduce-rtt: " + str(outbound["zero_rtt_handshake"]).lower() + "\n    max-udp-relay-packet-size: 1400\n")
            profiles.append({"user": username, "mihomo": mihomo, "sing_box": {"log": {"level": "warn", "timestamp": True},
                             "inbounds": [{"type": "mixed", "tag": "mixed-in", "listen": "127.0.0.1", "listen_port": 1080}],
                             "outbounds": [outbound], "route": {"final": tag}}})
        out["profiles"] = profiles
        out["uri"] = None  # No standardized TUIC v5 URI is invented.
    return out


class Service:
    """One canonical supervisor. Fixture adapter is explicit and never auto-selected."""
    def __init__(self, adapter, generation, fixture=None):
        self.adapter, self.generation, self.fixture = adapter, generation, fixture
        require(adapter in ("systemd", "openrc", "process", "fixture"), "SERVICE_START", "unsupported init system")
        require(adapter != "fixture" or fixture, "SERVICE_START", "fixture driver missing")
        self.child = None
        self.log = None

    def call(self, action, name="nobrand-splicore", ok=True):
        require(name == "nobrand-splicore", "SERVICE_START", "service outside Splicore ownership")
        if self.adapter == "fixture":
            args = [self.fixture, action, name, str(self.generation)]
        elif self.adapter == "systemd":
            unit = name if name.endswith((".timer", ".service")) else name + ".service"
            if action == "reload-manager":
                args = ["systemctl", "daemon-reload"]
            elif action == "enabled":
                args = ["systemctl", "is-enabled", "--quiet", unit]
            elif action == "active":
                args = ["systemctl", "is-active", "--quiet", unit]
            else:
                args = ["systemctl", action, unit]
        elif self.adapter == "openrc":
            if action == "reload-manager":
                return True
            if action in ("enable", "disable", "enabled"):
                if action == "enabled":
                    return (Path("/etc/runlevels/default") / name).exists()
                args = ["rc-update", "add" if action == "enable" else "del", name, "default"]
            else:
                args = ["rc-service", name, "status" if action == "active" else action]
        else:
            require(name == "nobrand-splicore", "SERVICE_START", "process probe cannot control legacy services")
            if action in ("enable", "disable", "reload-manager"):
                return True
            if action in ("enabled", "active"):
                return self.child is not None and self.child.poll() is None
            if action == "stop":
                if self.child is not None and self.child.poll() is None:
                    self.child.terminate()
                    try:
                        self.child.wait(timeout=10)
                    except subprocess.TimeoutExpired:
                        self.child.kill()
                        self.child.wait(timeout=5)
                if self.log:
                    self.log.close()
                    self.log = None
                return True
            if action == "start":
                self.log = (self.generation / "daemon.log").open("ab")
                self.child = subprocess.Popen([sys.executable, str(self.generation / "launch.py")],
                                              stdout=self.log, stderr=self.log, close_fds=True)
                return True
            raise Failure("SERVICE_START", "unsupported local probe operation")
        result = command(args, "SERVICE_START", timeout=45, ok=ok)
        return result.returncode == 0


class Runtime:
    def __init__(self, root=None, adapter=None, fixture=None):
        self.state = Path(root or os.environ.get("NOBRAND_STATE_DIR", "/var/lib/nobrand-oneclick"))
        self.config = Path(os.environ.get("NOBRAND_CONFIG_DIR", "/etc/nobrand-oneclick"))
        self.lib = Path(os.environ.get("NOBRAND_LIB_DIR", "/usr/local/lib/nobrand-oneclick"))
        self.lifecycle = Path(os.environ.get("NOBRAND_LIFECYCLE_DIR", "/var/lib/nobrand-oneclick-lifecycle"))
        self.home = self.state / "splicore"
        self.generations = self.home / "generations"
        self.current = self.home / "current"
        self.previous = self.home / "previous"
        self.transaction = self.lifecycle / "splicore-transaction.json"
        self.adapter = adapter or ("systemd" if Path("/run/systemd/system").is_dir() else "openrc" if Path("/sbin/openrc").exists() else "")
        self.fixture = fixture
        require(self.adapter != "fixture" or os.environ.get("NOBRAND_SPLICORE_FIXTURE") == "1",
                "SERVICE_START", "fixture adapter requires explicit isolated test environment")

    def safe(self):
        for root in (self.state, self.config, self.lib, self.lifecycle):
            require(root.is_absolute() and len(root.parts) >= 3 and root != Path("/"), "CONFIG_INVALID", "unsafe runtime root")
            for part in (root, *root.parents):
                require(not part.is_symlink(), "CONFIG_INVALID", "symlink in managed root")
        for path in (self.home, self.generations, self.config / "splicore", self.config / "splicore/tls"):
            require(not path.is_symlink(), "CONFIG_INVALID", "managed directory replaced by symlink")
        registry = self.state / "state.json"
        if registry.exists():
            record = load(registry)
            require(record.get("schema_version") == 3 and record.get("ownership") == "nobrand-v3"
                    and record.get("project") == "NoBrand-OneClick", "CONFIG_INVALID", "NoBrand authority is ambiguous or foreign")
        elif self.state.exists():
            # These are product namespaces; legacy markers are read-only refusals.
            allowed = {"splicore", "mieru", "snell", "tuic", "hysteria2", "vless-reality", "vless-sudoku",
                       "forward", "ssh", "ssh-tunnel", "ingress", "ingress.json", "ingress-firewall.json", "backups", "firewall-owned.bindings"}
            require(all(p.name in allowed for p in self.state.iterdir()), "CONFIG_INVALID", "unmarked state contains foreign data")

    @contextlib.contextmanager
    def locked(self):
        self.refuse_legacy()
        self.safe()
        self.lifecycle.mkdir(parents=True, exist_ok=True, mode=0o700)
        lock = Path(os.environ.get("NOBRAND_LIFECYCLE_LOCK_FILE", str(self.lifecycle / "splicore.lock")
                                   if self.adapter in ("process", "fixture") else "/run/nobrand-oneclick/lifecycle.lock"))
        lock.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        require(not lock.is_symlink(), "CONFIG_INVALID", "unsafe lock path")
        # Menu actions may already hold the canonical Bash lifecycle guard on
        # descriptor 7. Reuse that open file description instead of deadlocking.
        inherited = False
        try:
            inherited = os.path.samefile("/proc/self/fd/7", lock)
        except OSError:
            pass
        with (os.fdopen(os.dup(7), "a") if inherited else lock.open("a")) as out:
            os.chmod(lock, 0o600)
            try:
                fcntl.flock(out, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError as exc:
                raise Failure("LOCKED", "another runtime transaction is active") from exc
            yield

    def target(self, link):
        if not link.is_symlink():
            require(not link.exists(), "CONFIG_INVALID", "runtime pointer must be an owned symlink")
            return None
        candidate = link.resolve()
        require(candidate.parent == self.generations.resolve() and candidate.is_dir(),
                "CONFIG_INVALID", "runtime pointer escapes managed generations")
        return candidate

    def point(self, link, target):
        self.home.mkdir(parents=True, exist_ok=True, mode=0o700)
        require(target.parent == self.generations and target.is_dir(), "CONFIG_INVALID", "unsafe generation")
        tmp = self.home / (".link-" + uuid.uuid4().hex)
        try:
            tmp.symlink_to("generations/" + target.name, target_is_directory=True)
            os.replace(tmp, link)
            sync_dir(self.home)
        finally:
            if tmp.is_symlink():
                tmp.unlink()

    def desired(self):
        current = self.target(self.current)
        return load(current / "desired.json") if current else empty()

    def legacy_present(self):
        # Only namespaces and service names owned by NoBrand, never PATH names.
        paths = [self.state / name for name in (
            "mieru/install-state.env", "mieru/users.json", "mieru/.installed", "hysteria2/state.json",
            "tuic/runtime.json", "snell/instances", "tuic/instances", "vless-reality/instances")]
        paths += [self.config / "hysteria2/config.json", self.config / "vless-reality/instances"]
        paths += [self.lib / name for name in ("bin/mita", "bin/sing-box", "bin/hysteria", "mieru-instance-run")]
        if not (self.state / "vless-sudoku/state.json").is_file():
            paths.append(self.lib / "bin/xray")
        system = Path(os.environ.get("NOBRAND_SYSTEM_ROOT", "/"))
        paths.append(Path(os.environ.get("NOBRAND_LEGACY_MIERU_STATE_DIR", str(system / "var/lib/mita-oneclick"))))
        for folder, patterns in ((system / "etc/systemd/system", ("nobrand-mieru*.service", "nobrand-mieru*.timer",
                                  "nobrand-snell*.service", "nobrand-tuic*.service", "nobrand-vless-reality*.service",
                                  "nobrand-hysteria2.service")),
                                 (system / "etc/init.d", ("nobrand-mieru*", "nobrand-snell*", "nobrand-tuic*",
                                                      "nobrand-vless-reality*", "nobrand-hysteria2"))):
            for pattern in patterns:
                paths.extend(folder.glob(pattern))
        if any(path.exists() or path.is_symlink() for path in paths):
            return True
        if self.current.exists() or self.current.is_symlink():
            intent = self.current / "desired.json" if self.current.is_symlink() else self.current
            marker, expected = ("architecture", "splicore-native") if self.current.is_symlink() else ("owner", "nobrand-splicore-pointer-v1")
            if not intent.is_file() or load(intent).get(marker) != expected:
                return True
        registry = self.state / "state.json"
        return (registry.exists() or registry.is_symlink()) and (
            registry.is_symlink() or load(registry).get("architecture") != "splicore-native")

    def refuse_legacy(self):
        require(not self.legacy_present(), "UNSUPPORTED_LEGACY_INSTALLATION", LEGACY_NOTICE)

    def port_pairs(self, desired):
        result = set()
        for node in desired["nodes"]:
            protocol, doc = node["protocol"], node["document"]
            transport = doc["settings"]["transport"] if protocol == "mieru" else "tcp" if protocol in ("snell", "vless-reality") else "udp"
            result.add(transport.upper() + "|" + str(doc["listener"]["port"]))
        return result

    def firewall(self, action, pairs):
        if not pairs or self.adapter == "process":
            return
        if self.adapter == "fixture":
            Service(self.adapter, self.target(self.current) or self.home, self.fixture).call("firewall-" + action)
            return
        source = os.environ.get("NOBRAND_SPLICORE_MANAGER_SOURCE", "")
        require(source and Path(source).is_file(), "CONFIG_INVALID", "standalone NoBrand manager source required for firewall ownership adapter")
        require(action in ("open", "close"), "CONFIG_INVALID", "firewall action")
        script = ('manager=$1; bindings=$2; set --; MITA_SOURCE_ONLY=1; source "$manager"; '
                  + 'nb_firewall_' + action + '_pairs "$bindings"')
        command(["bash", "-c", script, "nobrand-firewall", source, "\n".join(sorted(pairs))], "FIREWALL", timeout=60)

    def check_external_ports(self, desired):
        reservations = []
        sudoku = self.state / "vless-sudoku/state.json"
        if sudoku.exists():
            old = load(sudoku)
            reservations.append("TCP|" + str(old["listen_port"]))
        forwarding = self.state / "forward/state.json"
        if forwarding.exists():
            for rule in load(forwarding).get("rules", []):
                for transport in (["TCP", "UDP"] if str(rule.get("protocol")).upper() == "BOTH" else [str(rule.get("protocol")).upper()]):
                    reservations.append(transport + "|" + str(rule.get("listen_port")))
        require(not self.port_pairs(desired).intersection(reservations), "PORT_CONFLICT", "port belongs to retained Sudoku or forwarding state")

    def owned_firewall_pairs(self):
        result = set()
        for path in (self.state / "firewall-owned.bindings", self.state / "mieru/firewall-owned.bindings"):
            if path.exists():
                for line in path.read_text().splitlines():
                    fields = line.split("|")
                    if len(fields) == 3 and fields[1] in ("tcp", "udp") and fields[2].isdigit():
                        result.add(fields[1].upper() + "|" + fields[2])
        return result

    def verify_installed_binary(self, generation):
        metadata = load(generation / "artifact.json")
        release = RELEASE if metadata["version"] == RELEASE["version"] else RELEASE.get("rollback_releases", {}).get(metadata["version"])
        require(release and release.get("version") == metadata["version"], "BINARY_IDENTITY", "generation release is not an approved rollback pin")
        digest = sha(generation / "splicore")
        require(metadata["binary_sha256"] == digest,
                "BINARY_IDENTITY", "installed binary or version changed")
        if self.adapter != "fixture":
            require(digest == release["assets"][metadata["architecture"]]["binary_sha256"],
                    "BINARY_IDENTITY", "binary does not match immutable release pin")
        binary_identity(generation / "splicore", metadata["architecture"], release)
        return metadata

    def adopt_snapshot(self):
        """Recreate only owned pointers/units after the existing product restore.

        All product state/config rollback remains owned by that transaction.
        Archive binaries are checked against a digest derived from verified
        public archives before any executable is invoked.
        """
        with self.locked():
            for link in (self.current, self.previous):
                if link.is_file() and not link.is_symlink():
                    pointer = load(link)
                    require(pointer.get("owner") == "nobrand-splicore-pointer-v1", "CONFIG_INVALID", "invalid backup runtime pointer")
                    generation = self.generations / identifier(pointer["generation"])
                    self.verify_installed_binary(generation)
                    self.point(link, generation)
            current = self.target(self.current)
            require(current, "CONFIG_INVALID", "missing restored generation")
            self.verify_installed_binary(current)
            render(load(current / "desired.json"))
            require(stat.S_IMODE((current / "runtime/master.key").stat().st_mode) & 0o077 == 0,
                    "CONFIG_INVALID", "restored master key is not private")
            atomic(current / "bootstrap.yaml", self.bootstrap_text(current))
            atomic(current / "launch.py", LAUNCHER, 0o700)
            command([current / "splicore", "validate", current / "bootstrap.yaml"])
            self.install_unit()
            Service(self.adapter, current, self.fixture).call("reload-manager")
            return {"result": "snapshot-adopted", "external_runtime_qualification": "PENDING"}

    def rollback(self):
        with self.locked():
            self.recover()
            old, current = self.target(self.previous), self.target(self.current)
            require(current, "ROLLBACK", "no installed generation to roll back")
            require(old, "ROLLBACK", "no previous known-good Splicore generation")
            service = Service(self.adapter, current, self.fixture)
            tx = {"owner": "nobrand-splicore-v1", "adapter": self.adapter, "candidate": current.name,
                  "old": old.name, "active": service.call("active", ok=False),
                  "enabled": service.call("enabled", ok=False),
                  "unit_backup": self.unit_path().read_text() if self.unit_path().exists() else None}
            self.checkpoint(tx, "ROLLING_BACK")
            self.restore_transaction(tx)
            self.point(self.previous, current)
            return {"result": "rolled-back", "generation": old.name}

    def prune_generations(self):
        # Keep current, previous, and any generation referenced by recovery.
        protected = {p for p in (self.target(self.current), self.target(self.previous)) if p}
        if self.transaction.exists():
            tx = load(self.transaction)
            for field in ("candidate", "old", "previous"):
                if tx.get(field):
                    protected.add(self.generations / identifier(tx[field]))
        for path in self.generations.iterdir():
            require(not path.is_symlink() and path.is_dir() and re.fullmatch(r"g[0-9a-f]{32}", path.name)
                    and (path / "artifact.json").is_file(), "CONFIG_INVALID", "unknown generation; cleanup requires review")
            if path not in protected:
                shutil.rmtree(path)

    def restore(self, archive_path, artifacts=None, proxy=""):
        self.refuse_legacy()
        with tempfile.TemporaryDirectory(prefix="nb-splicore-restore-") as directory:
            staging = Path(directory)
            with tarfile.open(archive_path, "r:gz") as archive:
                members, names, total = archive.getmembers(), set(), 0
                require(len(members) <= 512, "ARCHIVE_INVALID", "backup entry limit")
                for member in members:
                    name = member.name
                    require(member.isfile() and not PurePosixPath(name).is_absolute() and "\\" not in name
                            and ":" not in name and all(p not in ("", ".", "..") for p in name.split("/"))
                            and name not in names, "ARCHIVE_INVALID", "unsafe backup entry")
                    names.add(name)
                    total += member.size
                    require(total <= 256 * 1024 * 1024, "ARCHIVE_INVALID", "backup size limit")
                require({"desired.json", "artifact.json", "runtime/master.key"}.issubset(names), "ARCHIVE_INVALID", "incomplete backup")
                # Never execute the archived binary; reverify public artifacts.
                for name in ("desired.json", "runtime/master.key"):
                    with archive.extractfile(name) as src:
                        atomic(staging / name, src.read())
            desired = load(staging / "desired.json")
            desired["source"] = "backup-restore"
            render(desired)
            return self.deploy(desired, artifacts, proxy, key_material=(staging / "runtime/master.key").read_bytes())

    def stop(self):
        with self.locked():
            self.recover()
            current = self.target(self.current)
            require(current, "SERVICE_START", "runtime not installed")
            Service(self.adapter, current, self.fixture).call("stop")
            return {"result": "stopped"}

    def backup(self, destination, unified=False):
        with self.locked():
            self.recover()
            current = self.target(self.current)
            require(current, "CONFIG_INVALID", "runtime not installed")
            self.verify_installed_binary(current)
            service = Service(self.adapter, current, self.fixture)
            active = service.call("active", ok=False)
            if active:
                service.call("stop")
            try:
                destination = Path(destination)
                require(not destination.exists() and not destination.is_symlink(), "CONFIG_INVALID", "backup destination already exists")
                destination.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
                with tempfile.NamedTemporaryFile(dir=str(destination.parent), prefix=".backup-", delete=False) as out:
                    temporary = Path(out.name)
                try:
                    with tarfile.open(temporary, "w:gz") as archive:
                        if unified:
                            text = ("project=NoBrand-OneClick\nversion=" + os.environ.get("SCRIPT_VERSION", "3.2.6")
                                    + "\nschema_version=3\nownership=nobrand-v3\ncontents=state,config\n")
                            info = tarfile.TarInfo("manifest.txt")
                            info.size, info.mode = len(text.encode()), 0o600
                            archive.addfile(info, io.BytesIO(text.encode()))
                            for label, root in (("state", self.state), ("config", self.config)):
                                if not root.exists():
                                    info = tarfile.TarInfo(label)
                                    info.type, info.mode = tarfile.DIRTYPE, 0o700
                                    archive.addfile(info)
                                    continue
                                archive.add(root, arcname=label, recursive=False)
                                for path in sorted(root.rglob("*")):
                                    if path == temporary or path == destination or within(path, self.state / "backups"):
                                        continue
                                    name = label + "/" + str(path.relative_to(root))
                                    if path in (self.current, self.previous) and path.is_symlink():
                                        target = self.target(path)
                                        data = json.dumps({"owner": "nobrand-splicore-pointer-v1", "generation": target.name}).encode()
                                        info = tarfile.TarInfo(name)
                                        info.size, info.mode = len(data), 0o600
                                        archive.addfile(info, io.BytesIO(data))
                                    elif stat.S_ISSOCK(path.lstat().st_mode) and within(path, self.home):
                                        continue
                                    else:
                                        require(not path.is_symlink() and (path.is_file() or path.is_dir()),
                                                "CONFIG_INVALID", "unsupported entry in product backup")
                                        archive.add(path, arcname=name, recursive=False)
                        else:
                            for path in sorted(current.rglob("*")):
                                require(not path.is_symlink(), "CONFIG_INVALID", "symlink in runtime backup")
                                if path.is_file():
                                    archive.add(path, arcname=str(path.relative_to(current)), recursive=False)
                    os.chmod(temporary, 0o600)
                    with temporary.open("rb") as out:
                        os.fsync(out.fileno())
                    os.replace(temporary, destination)
                    sync_dir(destination.parent)
                finally:
                    remove_file(temporary)
            finally:
                if active:
                    service.call("start")
            return {"result": "backup-created", "database_and_key": "included"}

    def certificate_material(self, target, sni):
        """Read managed material without changing its identity or permissions."""
        require(target.is_dir() and not target.is_symlink(), "CONFIG_INVALID", "TLS directory must be a real owned directory; inspect retained state")
        paths = [target, *(target / n for n in ("certificate.pem", "private.key", "ca.pem"))]
        for path in paths:
            require(not path.is_symlink() and path.exists(), "CONFIG_INVALID", "incomplete retained TLS; restore the owned material or explicitly purge it")
            info = path.stat()
            require(info.st_uid == os.geteuid() and info.st_gid == os.getegid()
                    and stat.S_IMODE(info.st_mode) == (0o700 if path == target else 0o600)
                    and (path == target or (stat.S_ISREG(info.st_mode) and info.st_nlink == 1)),
                    "CONFIG_INVALID", "retained TLS ownership, type or private permissions differ; inspect without overwriting")
        return {"server_name": sni, "certificate_file": str(target / "certificate.pem"),
                "private_key_file": str(target / "private.key"), "ca_certificate": (target / "ca.pem").read_text()}

    def certificate_provenance(self, name, tls):
        """Pre-marker rc.4 material needs an exact native canonical reference."""
        if not self.generations.is_dir():
            return None
        for generation in self.generations.iterdir():
            if generation.is_symlink() or not generation.is_dir() or not re.fullmatch(r"g[0-9a-f]{32}", generation.name):
                continue
            paths = [generation / n for n in ("desired.json", "artifact.json")]
            if not all(p.is_file() and not p.is_symlink() and p.stat().st_uid == os.geteuid()
                       and stat.S_IMODE(p.stat().st_mode) == 0o600 for p in paths):
                continue
            graph, artifact_metadata = (load(p) for p in paths)
            if (graph.get("owner") != "nobrand-splicore-v1" or graph.get("architecture") != "splicore-native"
                    or graph.get("config_schema") != 1 or artifact_metadata.get("version") != RELEASE["version"]):
                continue
            for node in graph.get("nodes", []):
                protocol, label = node.get("protocol"), node.get("client", {}).get("name")
                if protocol not in ("hysteria2", "tuic") or not isinstance(label, str):
                    continue
                expected = "n" + hashlib.sha256((protocol + "\0" + label).encode()).hexdigest()[:16]
                recorded = node.get("document", {}).get("settings", {}).get("tls", {})
                sni = recorded.get("server_name")
                if (node.get("id") == name == expected and isinstance(sni, str) and sni
                        and recorded == dict(tls, server_name=sni)
                        and tls["server_name"] in (None, sni)):
                    return sni
        return None

    def certificate_owner(self, target, tls):
        marker, name = target / "owner.json", target.name
        marked = marker.exists() or marker.is_symlink()
        if marked:
            info = marker.lstat()
            require(stat.S_ISREG(info.st_mode) and info.st_nlink == 1 and info.st_uid == os.geteuid()
                    and info.st_gid == os.getegid() and stat.S_IMODE(info.st_mode) == 0o600,
                    "CONFIG_INVALID", "unsafe retained TLS ownership marker; inspect without overwriting")
            recorded = load(marker)
            require(isinstance(recorded, dict), "CONFIG_INVALID", "invalid retained TLS ownership metadata")
            sni = tls["server_name"] if tls["server_name"] is not None else recorded.get("server_name")
        else:
            sni = self.certificate_provenance(name, tls)
            require(sni, "CONFIG_INVALID", "TLS ownership cannot be proven for this instance; directory left untouched")
        require(isinstance(sni, str) and sni, "CONFIG_INVALID", "retained TLS has no server identity")
        owner = {"owner": "nobrand-splicore-tls-v1", "node_id": name, "server_name": sni,
                 "files": {n: sha(target / n) for n in ("certificate.pem", "private.key", "ca.pem")}}
        require(not marked or recorded == owner, "CONFIG_INVALID", "retained TLS instance, SNI or material differs; restore or explicitly purge owned state")
        tls["server_name"] = sni
        return owner, marked

    def certificate(self, name, sni):
        self.refuse_legacy()
        self.safe()
        require(re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9.-]{0,252}", sni), "CONFIG_INVALID", "invalid TLS SNI")
        parent = self.config / "splicore/tls"
        target = parent / identifier(name)
        marker = target / "owner.json"
        if target.exists() or target.is_symlink():
            try:
                tls = self.certificate_material(target, sni)
                owner, marked = self.certificate_owner(target, tls)
                tls_check(tls)
                text = command(["openssl", "x509", "-in", tls["certificate_file"], "-noout", "-text"]).stdout
                require(all(item in text for item in (b"CA:FALSE", b"X509v3 Subject Alternative Name:",
                            b"Digital Signature", b"TLS Web Server Authentication")),
                        "CONFIG_INVALID", "retained TLS leaf extensions do not match the managed certificate policy")
                if not marked:
                    save(marker, owner)
                return tls
            except (OSError, ValueError, TypeError, KeyError) as exc:
                raise Failure("CONFIG_INVALID", "invalid retained TLS or ownership metadata; inspect without overwriting") from exc
        parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        with tempfile.TemporaryDirectory(prefix=".tls-", dir=str(parent)) as directory:
            work = Path(directory)
            ca, ca_key = work / "ca.pem", work / "ca.key"
            cert, key, csr = work / "certificate.pem", work / "private.key", work / "leaf.csr"
            ca_config = work / "ca.cnf"
            atomic(ca_config, "[req]\ndistinguished_name=dn\nprompt=no\nx509_extensions=v3_ca\n"
                   "[dn]\nCN=NoBrand local CA\n[v3_ca]\nbasicConstraints=critical,CA:TRUE\nkeyUsage=critical,keyCertSign,cRLSign\n")
            command(["openssl", "req", "-new", "-x509", "-newkey", "ec", "-pkeyopt", "ec_paramgen_curve:P-256",
                     "-nodes", "-days", "3650", "-config", ca_config, "-extensions", "v3_ca",
                     "-keyout", ca_key, "-out", ca])
            command(["openssl", "req", "-new", "-newkey", "ec", "-pkeyopt", "ec_paramgen_curve:P-256",
                     "-nodes", "-subj", "/CN=" + sni, "-keyout", key, "-out", csr])
            extension = work / "leaf.ext"
            try:
                ipaddress.ip_address(sni)
                san = "IP:"
            except ValueError:
                dns_name(sni)
                san = "DNS:"
            atomic(extension, "basicConstraints=critical,CA:FALSE\nkeyUsage=critical,digitalSignature\nsubjectAltName=" + san + sni + "\nextendedKeyUsage=serverAuth\n")
            command(["openssl", "x509", "-req", "-in", csr, "-CA", ca, "-CAkey", ca_key, "-CAcreateserial",
                     "-days", "825", "-extfile", extension, "-out", cert])
            target.mkdir(mode=0o700)
            atomic(target / cert.name, cert.read_bytes() + ca.read_bytes())
            atomic(target / key.name, key.read_bytes())
            atomic(target / ca.name, ca.read_bytes())
            save(marker, {"owner": "nobrand-splicore-tls-v1", "node_id": name, "server_name": sni,
                          "files": {n: sha(target / n) for n in ("certificate.pem", "private.key", "ca.pem")}})
        return {"server_name": sni, "certificate_file": str(target / "certificate.pem"),
                "private_key_file": str(target / "private.key"), "ca_certificate": (target / "ca.pem").read_text()}

    def protocol(self, protocol, operation, selector="", artifacts=None, proxy="", preview=False):
        self.refuse_legacy()
        created_tls = None
        aliases = {"client-config": "show", "user-del": "remove", "users": "user-list", "user-set-endpoint": "set-endpoint"}
        operation = aliases.get(operation, operation)
        if protocol == "mieru" and operation == "user-add":
            operation = "install"
        installed = self.target(self.current)
        if operation in ("status", "doctor", "menu"):
            result = {"core": "Splicore", "version": RELEASE["version"], "protocol": protocol,
                      "architecture": "splicore-native", "nodes": [],
                      "installed": bool(installed), "qualification": RELEASE["qualification"]}
            if installed:
                result["version"] = load(installed / "artifact.json")["version"]
                result["nodes"] = [{"id": n["id"], "enabled": n.get("enabled", True),
                                     "name": n.get("client", {}).get("name") or n["id"],
                                     "listener": n["document"]["listener"]} for n in self.desired()["nodes"] if n["protocol"] == protocol]
                if operation == "doctor":
                    result.update(self.health(installed))
            return result
        desired = self.desired()
        matching = [node for node in desired["nodes"] if node["protocol"] == protocol
                    and (not selector or node["id"] == selector or node.get("client", {}).get("name") == selector
                         or node.get("client", {}).get("pair") == selector
                         or (protocol == "mieru" and node["document"].get("users", [{}])[0].get("username") == selector))]
        if operation in ("show", "export", "user-show", "user-list"):
            require(matching, "CONFIG_INVALID", "node not found")
            if operation == "user-list":
                return {"nodes": [{"id": n["id"], "enabled": n.get("enabled", True),
                                   "users": n.get("client", {}).get("user_names") or [u.get("username", "") for u in n["document"].get("users", [])]} for n in matching]}
            return {"client_profiles": [client_profiles(n) for n in matching]}
        if operation in ("upgrade", "upgrade-runtime"):
            return redacted_plan(desired) if preview else self.deploy(desired, artifacts, proxy)
        if operation == "install":
            require(not matching, "CONFIG_INVALID", "node already exists; use explicit reconfigure")
            env = os.environ
            label = selector or env.get("USERNAME", "") or "primary"
            require(len(label) <= 64 and not any(ord(c) < 32 or c == "|" for c in label), "CONFIG_INVALID", "invalid node name")
            name = "n" + hashlib.sha256((protocol + "\0" + label).encode()).hexdigest()[:16]
            port = int(env.get("PORT") or 0)
            require(port > 0, "CONFIG_INVALID", "--port is required")
            display_host = env.get("ADVERTISE_HOST") or env.get("NOBRAND_SPLICORE_AUTO_HOST", "")
            require(display_host and display_host not in ("0.0.0.0", "::"), "CONFIG_INVALID", "an explicit or detected display host is required")
            document = {"schema": 1, "listener": {"host": env.get("NOBRAND_SPLICORE_LISTEN", "0.0.0.0"), "port": port},
                        "display_endpoint": {"host": display_host, "port": int(env.get("ADVERTISE_PORT") or port)}}
            node = {"id": name, "protocol": protocol, "enabled": True, "client": {"name": label}, "document": document}
            if protocol in ("hysteria2", "tuic"):
                require(not preview, "CONFIG_INVALID", "fresh TLS preview requires a supplied canonical file with TLS paths")
                tls_path = self.config / "splicore/tls" / name
                retained = tls_path.exists() or tls_path.is_symlink()
                tls = self.certificate(name, env.get("HY2_SNI" if protocol == "hysteria2" else "TUIC_SNI")
                                       or ("bing.com" if protocol == "hysteria2" else "www.microsoft.com"))
                created_tls = None if retained else tls_path
            if env.get("NOBRAND_SPLICORE_INGRESS_ID"):
                node["ingress"] = {"profile_id": env["NOBRAND_SPLICORE_INGRESS_ID"]}
            if protocol == "snell":
                document.update({"settings": {"version": int(env.get("SNELL_VERSION", "5"))},
                                 "psk": env.get("SNELL_PSK") or uuid.uuid4().hex})
                node["options"] = {"quic_proxy_enabled": env.get("SNELL_QUIC_PROXY", "off") in ("on", "true", "1")}
            elif protocol == "mieru":
                require(env.get("PROTOCOL", "TCP").upper() in ("TCP", "UDP", "BOTH"), "CONFIG_INVALID", "invalid Mieru transport")
                document.update({"settings": {"transport": "tcp" if env.get("PROTOCOL", "TCP").upper() == "BOTH" else env.get("PROTOCOL", "TCP").lower(),
                                               "mtu": int(env.get("MTU", "1400")), "multiplex": multiplex(env.get("MULTIPLEXING", "off"))},
                                 "users": [{"username": env.get("USERNAME") or name, "password": env.get("PASSWORD") or uuid.uuid4().hex}]})
                node["options"] = {"traffic_pattern": env.get("TRAFFIC_PATTERN", "conservative"),
                                   "low_entropy": env.get("LOW_ENTROPY_MODE", "LOW_ENTROPY_MODE_OFF"),
                                   "quota_mb": int(env.get("USER_QUOTA_MB") or 0), "expire_at": env.get("USER_EXPIRE", ""),
                                   "bandwidth_mbps": int(env.get("USER_BANDWIDTH_MBPS") or 0)}
                require(env.get("USER_PACKAGE", "") in ("", "unlimited", "custom"), "CAPABILITY_UNSUPPORTED", "quota packages are unsupported by rc.4")
                node["client"].update({"handshake_mode": handshake(env.get("HANDSHAKE_MODE", "HANDSHAKE_NO_WAIT")),
                                         "transport": env.get("PROTOCOL", "TCP").upper(), "pair": name})
                if env.get("PROTOCOL", "TCP").upper() == "BOTH":
                    pair = copy.deepcopy(node)
                    pair["id"] += "-udp"
                    pair["document"]["settings"]["transport"] = "udp"
                    pair["document"]["listener"]["port"] += 1
                    pair["document"]["display_endpoint"]["port"] += 1
                    desired["nodes"].append(pair)
            elif protocol == "vless-reality":
                cover = env.get("VLESS_REALITY_TARGET") or "www.microsoft.com"
                cover_port = int(env.get("VLESS_REALITY_TARGET_PORT") or 443)
                guard_port = available_tcp_port(desired)
                node["guard"] = {"id": str(uuid.uuid4()), "listen": {"host": "127.0.0.1", "port": guard_port},
                                 "target": {"host": cover, "port": cover_port}, "approved_sni": [cover]}
                private, public = reality_keypair()
                document.update({"settings": {"security": "reality", "flow": "xtls-rprx-vision",
                    "transport": "tcp", "packet_encoding": "xudp", "stream_transport": {"kind": "tcp"},
                    "reality": {"public_key": public, "short_ids": [secrets.token_hex(8)],
                                "server_name": cover, "target": node["guard"]["listen"]}},
                    "server_secret": {"private_key": private}, "users": [{"uuid": str(uuid.uuid4())}]})
            elif protocol == "hysteria2":
                document.update({"settings": {"tls": tls,
                                               "stream_transport": {"kind": "hysteria", "hysteria": {"version": 2,
                                                   "obfs": {"type": "salamander", "password": uuid.uuid4().hex}}}},
                                 "users": [{"password": uuid.uuid4().hex}]})
                node["options"] = {"obfs": "salamander"}
            else:
                require(protocol == "tuic", "CAPABILITY_UNSUPPORTED", "unsupported protocol")
                document.update({"settings": {"version": 5, "congestion_control": "cubic", "udp_relay_mode": "native",
                                               "zero_rtt_handshake": False, "tls": tls},
                                 "users": [{"uuid": str(uuid.uuid4()), "password": uuid.uuid4().hex}]})
                node["client"]["user_names"] = [env.get("TUIC_USER") or "primary"]
            desired["nodes"].append(node)
        else:
            require(matching and (selector or len(matching) == 1 or operation in ("uninstall", "start", "stop", "restart")),
                    "CONFIG_INVALID", "select a node by name")
            node = matching[0]
            if operation in ("remove", "uninstall"):
                for member in matching:
                    desired["nodes"].remove(member)
            elif operation in ("start", "stop", "restart", "user-enable", "user-disable"):
                for member in matching:
                    member["enabled"] = operation not in ("stop", "user-disable")
            elif protocol == "tuic" and operation in ("user-add", "user-delete", "user-rotate"):
                client = node.setdefault("client", {})
                original_names = [u["name"] for u in client.get("users", [])]
                names = client.setdefault("user_names", original_names or [str(i) for i in range(len(node["document"]["users"]))])
                name = os.environ.get("TUIC_USER", "")
                require(name, "CONFIG_INVALID", "--user is required")
                if operation == "user-add":
                    require(name not in names, "CONFIG_INVALID", "user already exists")
                    names.append(name)
                    node["document"]["users"].append({"uuid": str(uuid.uuid4()), "password": uuid.uuid4().hex})
                else:
                    require(name in names, "CONFIG_INVALID", "user not found")
                    index = names.index(name)
                    if operation == "user-delete":
                        require(len(names) > 1, "CONFIG_INVALID", "remove the node to delete its last user")
                        names.pop(index)
                        node["document"]["users"].pop(index)
                    else:
                        node["document"]["users"][index] = {"uuid": str(uuid.uuid4()), "password": uuid.uuid4().hex}
            elif operation == "set-endpoint":
                require(os.environ.get("ADVERTISE_HOST"), "CONFIG_INVALID", "explicit display host required")
                base_port = min(n["document"]["listener"]["port"] for n in matching)
                for member in matching:
                    member["document"]["display_endpoint"] = {"host": os.environ["ADVERTISE_HOST"],
                        "port": int(os.environ.get("ADVERTISE_PORT") or base_port) + member["document"]["listener"]["port"] - base_port}
            elif operation == "set-listen":
                for member in matching:
                    member["document"]["listener"]["host"] = os.environ.get("NOBRAND_SPLICORE_LISTEN", "")
            elif protocol == "mieru" and operation in ("reconfigure", "profile-config", "mtu-config", "client-modes-config", "traffic-config", "low-entropy-config"):
                env = os.environ
                profile = env.get("PROFILE_CLI") == "1" and env.get("PROFILE", "custom") != "custom"
                requested = any(env.get(k) == "1" for k in ("PROFILE_CLI", "MTU_CLI", "MULTIPLEXING_CLI", "HANDSHAKE_CLI", "TRAFFIC_CLI", "LOW_ENTROPY_CLI"))
                require(requested, "CONFIG_INVALID", "supply explicit --profile, --mtu, --multiplexing, --handshake-mode or --traffic-pattern")
                require(not profile or all(n["document"]["settings"]["transport"] == env.get("PROTOCOL", "TCP").lower() for n in matching),
                        "CAPABILITY_UNSUPPORTED", "profile transport change requires an explicit canonical listener transaction")
                require(env.get("PASSWORD_CLI") != "1" and env.get("PORT_CLI") != "1" and env.get("PROTOCOL_CLI") != "1"
                        and env.get("ADVERTISE_CLI") != "1", "CAPABILITY_UNSUPPORTED", "listener/credential changes require an explicit canonical file; display changes use set-endpoint")
                for member in matching:
                    settings = member["document"]["settings"]
                    options = member.setdefault("options", {})
                    if profile or env.get("MTU_CLI") == "1":
                        settings["mtu"] = int(env.get("MTU", "1400"))
                    if profile or env.get("MULTIPLEXING_CLI") == "1":
                        settings["multiplex"] = multiplex(env.get("MULTIPLEXING", "off"))
                    if profile or env.get("HANDSHAKE_CLI") == "1":
                        member.setdefault("client", {})["handshake_mode"] = handshake(env.get("HANDSHAKE_MODE", "HANDSHAKE_NO_WAIT"))
                    if profile or env.get("TRAFFIC_CLI") == "1":
                        options["traffic_pattern"] = env.get("TRAFFIC_PATTERN", "conservative")
                    if profile or env.get("LOW_ENTROPY_CLI") == "1":
                        options["low_entropy"] = env.get("LOW_ENTROPY_MODE", "LOW_ENTROPY_MODE_OFF")
            elif protocol == "snell" and operation == "set-quic":
                require(os.environ.get("SNELL_QUIC_PROXY", "off") == "off", "CAPABILITY_UNSUPPORTED", "Snell QUIC is not exposed by rc.4")
                for member in matching:
                    member.setdefault("options", {})["quic_proxy_enabled"] = False
            else:
                raise Failure("CAPABILITY_UNSUPPORTED", "operation needs an explicit supported desired-state change; no legacy fallback")
        if preview:
            return redacted_plan(desired)
        try:
            outcome = self.deploy(desired, artifacts, proxy, force=operation == "restart",
                                  expected_generation=installed.name if installed else "")
        except BaseException:
            # Only remove material minted by this request after a completed
            # rollback. Unfinished recovery may still need the candidate TLS.
            terminal = not self.transaction.exists() or load(self.transaction).get("phase") in ("COMMITTED", "ROLLED_BACK")
            referenced = any(str(created_tls) in (p / "desired.json").read_text()
                             for p in (self.target(self.current), self.target(self.previous)) if p) if created_tls else False
            if created_tls and terminal and not referenced:
                shutil.rmtree(created_tls)
            raise
        if operation == "install":
            outcome["client_profiles"] = [client_profiles(n) for n in desired["nodes"] if n["id"] in (name, name + "-udp")]
        return outcome

    def uninstall(self, purge=False):
        with self.locked():
            self.recover()
            current = self.target(self.current)
            cleanup_debt = []
            # Prove TLS ownership before any destructive purge step. Retained
            # user/foreign material must never become owned merely by its path.
            tls = self.config / "splicore/tls"
            if purge and tls.exists():
                for target in tls.iterdir():
                    identifier(target.name)
                    material = self.certificate_material(target, None)
                    self.certificate_owner(target, material)
            if current:
                service = Service(self.adapter, current, self.fixture)
                service.call("stop")
                service.call("disable")
                path = self.unit_path()
                if path.exists():
                    require(not path.is_symlink() and "# NoBrand-owned Splicore v1" in path.read_text(),
                            "CONFIG_INVALID", "refuse foreign service unit")
                    path.unlink()
                    service.call("reload-manager")
                self.current.unlink()
                try:
                    self.firewall("close", self.port_pairs(load(current / "desired.json")))
                except (Failure, OSError):
                    cleanup_debt.append("owned firewall bindings")
            if purge and self.home.exists():
                self.safe()
                require(self.home.parent == self.state and self.home.name == "splicore", "CONFIG_INVALID", "unsafe purge path")
                for path in self.generations.iterdir() if self.generations.exists() else []:
                    require(path.is_dir() and not path.is_symlink() and (path / "artifact.json").is_file(),
                            "CONFIG_INVALID", "unknown data in generation directory")
                shutil.rmtree(self.home)
                if self.transaction.exists():
                    self.transaction.unlink()
                if tls.exists():
                    require(not tls.is_symlink(), "CONFIG_INVALID", "unsafe owned TLS directory")
                    shutil.rmtree(tls)
            return {"result": "purged" if purge else "uninstalled", "retained_state": not purge, "cleanup_debt": cleanup_debt}

    def unit_path(self):
        override = os.environ.get("NOBRAND_SPLICORE_UNIT")
        if self.adapter == "fixture":
            return self.home / "fixture.service"
        return Path(override) if override else Path("/etc/systemd/system/nobrand-splicore.service" if self.adapter == "systemd" else "/etc/init.d/nobrand-splicore")

    def bootstrap_text(self, generation):
        return ("schema: 1\nstate_directory: " + json.dumps(str(generation / "runtime"))
                + "\nkey_file: " + json.dumps(str(generation / "runtime/master.key"))
                + "\napi:\n  unix_socket: " + json.dumps(str(generation / "control.sock")) + "\n")

    def service_text(self):
        current = self.current
        python = shutil.which("python3")
        require(python and not any(c.isspace() for c in python), "SERVICE_START", "python3 unavailable for owned launcher")
        require(not any(c.isspace() or c in '\"$%`\\' for c in str(current)), "CONFIG_INVALID", "unit path contains unsupported characters")
        if self.adapter == "systemd":
            return ("# NoBrand-owned Splicore v1\n[Unit]\nDescription=NoBrand Splicore\nAfter=network-online.target\nWants=network-online.target\n"
                    "\n[Service]\nType=simple\nUser=root\nGroup=root\nUMask=0077\n"
                    f"WorkingDirectory={current}\nExecStart={python} {current}/launch.py\n"
                    "Restart=on-failure\nRestartSec=3\nLimitNOFILE=1048576\nNoNewPrivileges=true\nPrivateTmp=true\n"
                    "ProtectSystem=strict\nProtectHome=read-only\n"
                    f"ReadWritePaths={self.home}\n\n[Install]\nWantedBy=multi-user.target\n")
        return ("#!/sbin/openrc-run\n# NoBrand-owned Splicore v1\nname=\"NoBrand Splicore\"\n"
                f"command=\"{python}\"\ncommand_args=\"{current}/launch.py\"\n"
                "command_user=\"root:root\"\nsupervisor=\"supervise-daemon\"\nrespawn_delay=3\n"
                "respawn_max=0\nstart_stop_daemon_args=\"--umask 0077\"\n"
                "depend() { need net; }\n")

    def install_unit(self):
        if self.adapter == "process":
            return
        path = self.unit_path()
        require(not path.is_symlink(), "CONFIG_INVALID", "service unit is a symlink")
        if path.exists():
            require("# NoBrand-owned Splicore v1" in path.read_text(), "CONFIG_INVALID", "refuse foreign service unit")
        atomic(path, self.service_text(), 0o644 if self.adapter == "systemd" else 0o755)

    def validate(self, generation, documents):
        binary = generation / "splicore"
        command([binary, "validate", generation / "bootstrap.yaml"])
        for name, protocol, document in documents:
            path = generation / "documents" / (name + ".json")
            save(path, document)
            command([binary, "inbound", "validate", "--protocol", protocol, "--file", path])
        if self.adapter != "fixture" and guard_mutations(load(generation / "desired.json")):
            # Native client validation is a control API operation. Use a private
            # temporary daemon with its client runtime stopped: no public or
            # guard listeners, no production pointers, no service cutover.
            with tempfile.TemporaryDirectory(prefix="sc-check-") as directory:
                work = Path(directory)
                (work / "runtime").mkdir(mode=0o700)
                atomic(work / "runtime/master.key", (generation / "runtime/master.key").read_bytes())
                atomic(work / "bootstrap.yaml", self.bootstrap_text(work))
                with (work / "validation.log").open("wb") as log:
                    child = subprocess.Popen([str(binary), "run", "--config", str(work / "bootstrap.yaml")], stdout=log, stderr=log)
                    try:
                        deadline = time.monotonic() + 10
                        while not (work / "control.sock").exists():
                            require(child.poll() is None and time.monotonic() < deadline,
                                    "CONFIG_INVALID", "native validation daemon unavailable")
                            time.sleep(.05)
                        command([binary, "client", "stop", "--config", work / "bootstrap.yaml"])
                        self.apply_guards(work, binary, load(generation / "desired.json"))
                        for name, protocol, _document in documents:
                            command([binary, "inbound", "plan", "--protocol", protocol, "--config", work / "bootstrap.yaml",
                                     "--file", generation / "documents" / (name + ".json")])
                    finally:
                        child.terminate()
                        try:
                            child.wait(timeout=10)
                        except subprocess.TimeoutExpired:
                            child.kill()
                            child.wait(timeout=5)

    def apply_guards(self, generation, binary, desired):
        bootstrap = generation / "bootstrap.yaml"
        for index, mutation in enumerate(guard_mutations(desired)):
            path, plan = generation / ("guard-" + str(index) + ".json"), generation / "plan.json"
            save(path, mutation)
            result = command([binary, "client", "plan", "--config", bootstrap, "--file", path], ok=False)
            require(result.returncode == 0, "CONFIG_INVALID", "native " + mutation["resource"] + " plan rejected")
            atomic(plan, result.stdout)
            try:
                command([binary, "client", "apply", "--config", bootstrap, "--file", path, "--plan", plan])
            finally:
                remove_file(plan)

    def port_preflight(self, desired, old):
        def bindings(graph):
            result = set()
            for node in graph["nodes"]:
                if not node.get("enabled", True):
                    continue
                protocol, doc = node["protocol"], node["document"]
                transport = doc["settings"]["transport"] if protocol == "mieru" else (
                    "tcp" if protocol in ("snell", "vless-reality") else "udp")
                result.add((transport, doc["listener"]["host"], doc["listener"]["port"]))
                if node.get("guard"):
                    result.add(("tcp", node["guard"]["listen"]["host"], node["guard"]["listen"]["port"]))
            return result
        existing = bindings(load(old / "desired.json")) if old else set()
        for transport, host, port in bindings(desired) - existing:
            with socket.socket(socket.AF_INET6 if ":" in host else socket.AF_INET,
                               socket.SOCK_STREAM if transport == "tcp" else socket.SOCK_DGRAM) as listener:
                try:
                    listener.bind((host, port))
                except OSError as exc:
                    raise Failure("PORT_CONFLICT", "requested listener address/port is unavailable") from exc

    def apply_documents(self, generation, documents, service):
        deadline = time.monotonic() + 15
        control = generation / "control.sock"
        while not control.exists():
            require(time.monotonic() < deadline, "SERVICE_START", "control socket did not appear")
            if service.adapter == "process":
                require(service.child.poll() is None, "SERVICE_START", "isolated daemon exited")
            time.sleep(0.05)
        binary, bootstrap = generation / "splicore", generation / "bootstrap.yaml"
        desired = load(generation / "desired.json")
        self.apply_guards(generation, binary, desired)
        if guard_mutations(desired):
            command([binary, "client", "start", "--config", bootstrap])
        for name, protocol, document in documents:
            path, plan = generation / "documents" / (name + ".json"), generation / "plan.json"
            result = command([binary, "inbound", "plan", "--protocol", protocol, "--config", bootstrap, "--file", path])
            atomic(plan, result.stdout)
            try:
                command([binary, "inbound", "apply", "--protocol", protocol, "--config", bootstrap, "--file", path, "--plan", plan])
            finally:
                remove_file(plan)
        self.health(generation, documents, record=True)

    def health(self, generation, documents=None, record=False):
        documents = documents if documents is not None else render(load(generation / "desired.json"))
        result = command([generation / "splicore", "inbound", "list", "--config", generation / "bootstrap.yaml"], "HEALTH")
        items = json.loads(result.stdout)["items"]
        require(len(items) == len(documents) and all(i.get("health") == "healthy" for i in items), "HEALTH", "inbound health/count differs")
        expected = {d[2]["name"] for d in documents}
        require({item["inbound"]["name"] for item in items} == expected, "HEALTH", "inbound identity differs")
        mapping = {}
        for name, protocol, document in documents:
            inbound = next(item["inbound"] for item in items if item["inbound"]["name"] == document["name"])
            require(len(inbound.get("listeners", [])) == 1 and inbound["listeners"][0]["endpoint"] == document["listener"],
                    "HEALTH", "listener identity differs")
            mapping[name] = inbound["id"]
        if record:
            save(generation / "resource-map.json", mapping)
        guards = guard_mutations(load(generation / "desired.json"))
        if guards:
            client = json.loads(command([generation / "splicore", "client", "status", "--config",
                                         generation / "bootstrap.yaml"], "HEALTH").stdout)
            require(client.get("health") == "healthy" and client["state"]["enabled"],
                    "HEALTH", "native local guard runtime is not healthy")
            expected_guards = [m["local_inbound"] for m in guards if m["resource"] == "local-inbound"]
            actual = client["state"]["local_inbounds"]
            require(len(actual) == len(expected_guards) and all(
                any(a["id"] == e["id"] and a["listen"] == e["listen"] and a.get("tunnel") == e["tunnel"]
                    and a.get("sniffing") == e["sniffing"] for a in actual) for e in expected_guards)
                and client["state"]["network"]["route"]["rules"] == guards[-1]["network"]["route"]["rules"],
                "HEALTH", "native local guard or routing differs from desired intent")
        return {"inbound_count": len(items), "health": "healthy", "local_tunnel_guards": len(guards) - 1 if guards else 0,
                "traffic_qualification": "PENDING"}

    def checkpoint(self, tx, phase):
        tx["phase"] = phase
        save(self.transaction, tx)

    def restore_transaction(self, tx):
        candidate = self.generations / tx["candidate"]
        old = self.generations / tx["old"] if tx.get("old") else None
        if old:
            self.verify_installed_binary(old)
        service = Service(tx["adapter"], candidate, self.fixture)
        require(service.call("stop", ok=False), "ROLLBACK", "candidate stop failed; recovery record retained")
        if old:
            self.point(self.current, old)
        elif self.current.is_symlink():
            self.current.unlink()
            sync_dir(self.home)
        if "previous" in tx:
            if tx.get("previous"):
                self.point(self.previous, self.generations / tx["previous"])
            elif self.previous.is_symlink():
                self.previous.unlink()
        if tx.get("unit_backup") is not None:
            atomic(self.unit_path(), tx["unit_backup"], 0o644 if self.adapter == "systemd" else 0o755)
        elif self.adapter != "process" and self.unit_path().exists():
            require("# NoBrand-owned Splicore v1" in self.unit_path().read_text(), "ROLLBACK", "foreign service unit during rollback")
            self.unit_path().unlink()
        service.call("reload-manager")
        # A first install may have no unit to disable after its removal.
        if old or self.unit_path().exists() or self.adapter in ("process", "fixture"):
            require(service.call("enable" if tx.get("enabled") else "disable", ok=False), "ROLLBACK", "restore enabled state failed")
        if old and tx.get("active"):
            service.generation = old
            service.call("start")
            if self.adapter != "fixture":
                self.wait_health(old)
        registry = self.state / "state.json"
        if tx.get("registry_backup") is not None:
            atomic(registry, tx["registry_backup"])
        elif tx.get("registry_created"):
            remove_file(registry)
        self.firewall("close", set(tx.get("opened_ports", [])))
        self.checkpoint(tx, "ROLLED_BACK")

    def wait_health(self, generation):
        end = time.monotonic() + 15
        while True:
            try:
                return self.health(generation)
            except Failure:
                require(time.monotonic() < end, "HEALTH", "runtime did not recover")
                time.sleep(0.1)

    def recover(self):
        if not self.transaction.exists():
            return {"recovery": "not-needed"}
        tx = load(self.transaction)
        require(tx.get("owner") == "nobrand-splicore-v1" and tx.get("adapter") == self.adapter,
                "ROLLBACK", "transaction owner/init mismatch")
        for field in ("candidate", "old"):
            if tx.get(field):
                identifier(tx[field])
        if tx["phase"] not in ("COMMITTED", "ROLLED_BACK"):
            self.restore_transaction(tx)
        return {"recovery": load(self.transaction)["phase"]}

    def deploy(self, desired, artifacts=None, proxy="", force=False, probe=False, key_material=None, expected_generation=None):
        self.refuse_legacy()
        self.safe()
        desired = copy.deepcopy(desired)
        desired["splicore_version"] = RELEASE["version"]
        documents = render(desired)
        self.check_external_ports(desired)
        require(not probe or self.adapter == "process", "CONFIG_INVALID", "local probe requires process adapter")
        require(self.adapter != "process" or probe, "SERVICE_START", "process adapter is only a temporary validation probe")
        require(self.adapter in ("systemd", "openrc", "fixture", "process"), "SERVICE_START", "systemd/OpenRC unavailable")
        if self.adapter in ("systemd", "openrc"):
            require(os.geteuid() == 0, "SERVICE_START", "service installation requires root")
        with self.locked():
            self.recover()
            old = self.target(self.current)
            require(expected_generation is None or expected_generation == (old.name if old else ""),
                    "STATE_CHANGED", "runtime changed since request was collected; retry with current state")
            require(not probe or old is None, "CONFIG_INVALID", "probe requires an empty private runtime root")
            if old and load(old / "artifact.json")["version"] == RELEASE["version"] and desired == load(old / "desired.json") and not force and key_material is None:
                self.verify_installed_binary(old)
                service = Service(self.adapter, old, self.fixture)
                active = service.call("active", ok=False)
                if active and self.adapter != "fixture":
                    self.health(old)
                return {"result": "same-version-no-op", "version": RELEASE["version"], "active": active}
            self.generations.mkdir(parents=True, exist_ok=True, mode=0o700)
            generation = self.generations / ("g" + uuid.uuid4().hex)
            generation.mkdir(mode=0o700)
            candidate_service = Service(self.adapter, generation, self.fixture)
            tx = None
            try:
                if old and not artifacts and load(old / "artifact.json")["version"] == RELEASE["version"]:
                    metadata = self.verify_installed_binary(old)
                    atomic(generation / "splicore", (old / "splicore").read_bytes(), 0o700)
                    binary_identity(generation / "splicore", metadata["architecture"])
                else:
                    metadata = artifact(generation / "splicore", artifacts, proxy)
                save(generation / "artifact.json", metadata)
                save(generation / "desired.json", desired)
                (generation / "runtime").mkdir(mode=0o700)
                atomic(generation / "bootstrap.yaml", self.bootstrap_text(generation))
                atomic(generation / "launch.py", LAUNCHER, 0o700)
                if key_material is not None:
                    atomic(generation / "runtime/master.key", key_material)
                elif old:
                    shutil.copyfile(old / "runtime/master.key", generation / "runtime/master.key")
                    os.chmod(generation / "runtime/master.key", 0o600)
                else:
                    command([generation / "splicore", "key", "init", "--file", generation / "runtime/master.key"])
                os.chmod(generation / "runtime/master.key", 0o600)
                require(len(str(generation / "control.sock").encode()) < 104, "CONFIG_INVALID", "runtime root exceeds Unix socket path limit")
                self.validate(generation, documents)
                self.port_preflight(desired, old)
                unit = self.unit_path()
                require(self.adapter == "process" or not unit.exists() or (
                    not unit.is_symlink() and "# NoBrand-owned Splicore v1" in unit.read_text()),
                    "CONFIG_INVALID", "refuse foreign service unit before cutover")
                prior_ports = self.port_pairs(load(old / "desired.json")) if old else set()
                added_ports = self.port_pairs(desired) - prior_ports
                tx = {"owner": "nobrand-splicore-v1", "adapter": self.adapter,
                      "candidate": generation.name, "old": old.name if old else None,
                      "previous": self.target(self.previous).name if self.target(self.previous) else None,
                      "active": candidate_service.call("active", ok=False),
                      "enabled": candidate_service.call("enabled", ok=False),
                      "unit_backup": unit.read_text() if self.adapter != "process" and unit.exists() else None,
                      "registry_backup": (self.state / "state.json").read_text() if (self.state / "state.json").exists() else None,
                      "registry_created": not (self.state / "state.json").exists(),
                      "opened_ports": sorted(added_ports - self.owned_firewall_pairs())}
                self.checkpoint(tx, "VALIDATED")
                self.checkpoint(tx, "STOPPING")
                if tx["active"]:
                    candidate_service.call("stop")
                self.checkpoint(tx, "STOPPED")
                self.install_unit()
                self.point(self.current, generation)
                candidate_service.call("reload-manager")
                self.checkpoint(tx, "STARTING")
                candidate_service.call("start")
                if self.adapter != "fixture":
                    self.apply_documents(generation, documents, candidate_service)
                else:
                    # Fixture driver must explicitly validate its expected graph.
                    candidate_service.call("verify")
                self.firewall("open", added_ports)
                self.checkpoint(tx, "VERIFIED")
                if probe:
                    candidate_service.call("stop")
                    candidate_service.call("start")
                    self.wait_health(generation)
                    candidate_service.child.kill()
                    candidate_service.child.wait(timeout=10)
                    candidate_service.call("stop")
                    candidate_service.call("start")
                    self.wait_health(generation)
                    candidate_service.call("stop")
                    self.current.unlink()
                    self.checkpoint(tx, "ROLLED_BACK")
                    return {"result": "local-probe-pass", "inbounds": len(documents), "traffic_qualification": "PENDING",
                            "local_process_restart": "PASS", "local_process_crash_database_recovery": "PASS"}
                candidate_service.call("enable")
                if old:
                    self.point(self.previous, old)
                registry = load(self.state / "state.json") if (self.state / "state.json").exists() else {
                    "schema_version": 3, "ownership": "nobrand-v3", "project": "NoBrand-OneClick", "author": "ike"}
                registry.update(architecture="splicore-native", splicore_version=RELEASE["version"], config_schema=1)
                save(self.state / "state.json", registry)
                self.checkpoint(tx, "COMMITTED")
                cleanup_debt = []
                try:
                    self.firewall("close", prior_ports - self.port_pairs(desired))
                except (Failure, OSError):
                    cleanup_debt.append("retired firewall bindings")
                try:
                    self.prune_generations()
                except (Failure, OSError):
                    cleanup_debt.append("old generations")
                return {"result": "committed", "inbounds": len(documents), "traffic_qualification": "PENDING", "cleanup_debt": cleanup_debt}
            except BaseException:
                if tx and tx.get("phase") != "COMMITTED":
                    try:
                        self.restore_transaction(tx)
                    except (Failure, OSError) as exc:
                        raise Failure("ROLLBACK", "restore failed; persistent transaction retained for recover") from exc
                raise
            finally:
                if self.adapter == "process":
                    candidate_service.call("stop", ok=False)
                if tx is None or probe or tx.get("phase") == "ROLLED_BACK":
                    shutil.rmtree(generation)


def main(argv=None):
    parser = argparse.ArgumentParser(description="NoBrand Splicore runtime manager (pinned RC)")
    parser.add_argument("action", choices=["inspect-backup", "capabilities", "status", "doctor", "render", "apply", "probe", "recover", "unit", "plan",
                                           "rollback", "backup", "restore", "adopt-snapshot", "stop", "start", "restart", "uninstall", "purge", "protocol"])
    parser.add_argument("--file", type=Path)
    parser.add_argument("--artifacts", type=Path)
    parser.add_argument("--proxy", default=os.environ.get("NOBRAND_GITHUB_PROXY", ""))
    parser.add_argument("--adapter", choices=["systemd", "openrc", "process", "fixture"])
    parser.add_argument("--fixture-driver", type=Path)
    parser.add_argument("--force", action="store_true")
    parser.add_argument("--protocol")
    parser.add_argument("--operation")
    parser.add_argument("--selector", default="")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--unified", action="store_true")
    parser.add_argument("--version", default=RELEASE["version"])
    args = parser.parse_args(argv)
    require(args.version == RELEASE["version"], "BINARY_IDENTITY", "version change requires a reviewed release manifest; no implicit downgrade/latest")
    runtime = Runtime(adapter=args.adapter, fixture=args.fixture_driver)
    runtime.refuse_legacy()
    runtime.safe()
    if args.action == "inspect-backup":
        require(args.file, "ARCHIVE_INVALID", "--file product backup is required")
        inspect_backup_archive(args.file)
        result = {"result": "archive-safe-for-extraction"}
    elif args.action == "capabilities":
        result = {"version": RELEASE["version"], "qualification": RELEASE["qualification"], "capabilities": RELEASE["capabilities"]}
    elif args.action in ("render", "apply", "probe", "plan"):
        require(args.file or args.action == "plan", "CONFIG_INVALID", "--file canonical desired state is required")
        desired = load(args.file) if args.file else runtime.desired()
        if args.action in ("render", "plan"):
            # Render writes only to stdout by explicit operator request. Plan is redacted.
            result = {"documents": [{"id": name, "protocol": protocol, "document": doc} for name, protocol, doc in render(desired)]} if args.action == "render" else redacted_plan(desired)
            if args.action == "plan" and result["blockers"]:
                print(json.dumps(result, indent=2))
                return 1
        else:
            result = runtime.deploy(desired, args.artifacts, args.proxy, args.force, args.action == "probe")
    elif args.action == "protocol":
        result = runtime.protocol(args.protocol, args.operation, args.selector, args.artifacts, args.proxy, args.dry_run)
    elif args.action == "rollback":
        result = runtime.rollback()
    elif args.action == "backup":
        require(args.file, "CONFIG_INVALID", "--file backup destination required")
        result = runtime.backup(args.file, args.unified)
    elif args.action == "restore":
        require(args.file, "CONFIG_INVALID", "--file backup source required")
        result = runtime.restore(args.file, args.artifacts, args.proxy)
    elif args.action == "adopt-snapshot":
        result = runtime.adopt_snapshot()
    elif args.action in ("stop", "uninstall", "purge"):
        result = runtime.stop() if args.action == "stop" else runtime.uninstall(args.action == "purge")
    elif args.action in ("start", "restart"):
        with runtime.locked():
            runtime.recover()
            current = runtime.target(runtime.current)
            require(current, "SERVICE_START", "runtime not installed")
            service = Service(runtime.adapter, current, runtime.fixture)
            if args.action == "restart":
                service.call("stop")
            service.call("start")
            result = runtime.wait_health(current)
    elif args.action == "recover":
        with runtime.locked():
            result = runtime.recover()
    elif args.action == "unit":
        require(runtime.adapter in ("systemd", "openrc"), "SERVICE_START", "specify supported init system")
        print(runtime.service_text(), end="")
        return 0
    else:
        current = runtime.target(runtime.current)
        result = {"architecture": "Splicore Native", "architecture_marker": "splicore-native", "core": "Splicore", "version": RELEASE["version"], "qualification": RELEASE["qualification"],
                  "installed": bool(current), "external_runtime_qualification": "PENDING"}
        if current:
            metadata = load(current / "artifact.json")
            result.update({"version": metadata["version"], "pinned_target": RELEASE["version"], "architecture": metadata["architecture"], "generation": current.name,
                           "architecture_qualification": RELEASE["assets"][metadata["architecture"]]["qualification"],
                           "protocols": sorted({n["protocol"] for n in load(current / "desired.json")["nodes"]})})
            result["nodes"] = [{"id": n["id"], "name": n.get("client", {}).get("name") or n["id"],
                                "protocol": n["protocol"], "enabled": n.get("enabled", True),
                                "listener": n["document"]["listener"], "display_endpoint": n["document"]["display_endpoint"]}
                               for n in load(current / "desired.json")["nodes"] if not args.protocol or n["protocol"] == args.protocol]
            result["active"] = Service(runtime.adapter, current, runtime.fixture).call("active", ok=False)
            if args.action == "doctor":
                runtime.verify_installed_binary(current)
                result.update(runtime.health(current))
    print(json.dumps(result, indent=2))
    return 0


if __name__ == "__main__":
    os.umask(0o077)
    def interrupted(_signum, _frame):
        raise Failure("INTERRUPTED", "transaction interrupted; rollback/recovery required")
    for sig in (signal.SIGHUP, signal.SIGINT, signal.SIGTERM):
        signal.signal(sig, interrupted)
    try:
        sys.exit(main())
    except Failure as exc:
        print(json.dumps({"result": "FAIL", "category": exc.category, "detail": str(exc)}), file=sys.stderr)
        sys.exit(1)
    except tarfile.TarError:
        print(json.dumps({"result": "FAIL", "category": "ARCHIVE_INVALID", "detail": "invalid archive"}), file=sys.stderr)
        sys.exit(1)
    except (OSError, ValueError, KeyError, TypeError):
        print(json.dumps({"result": "FAIL", "category": "CONFIG_INVALID", "detail": "invalid external state or operation"}), file=sys.stderr)
        sys.exit(1)
NOBRAND_SPLICORE_PY
}

# The menu intentionally mutates globals inside isolated action subshells; the
# parent only consumes exit codes, so SC2030/SC2031 are false positives here.
# shellcheck disable=SC2030,SC2031
# NoBrand-OneClick — Mieru / Snell / Hysteria2 / TUIC v5 / Plain VLESS Sudoku / SSH Tunnel
# 作者: ike / https://github.com/ike-sh/NoBrand-OneClick
# Mieru 母体代码源自 ike-sh/mieru-OneClick (MIT)；Hysteria2 与 VLESS
# FinalMask/Sudoku 逻辑参考 ike-sh/Xray-OneClick (GPL-3.0)。本融合项目按
# GPL-3.0 发布；VLESS 为 plain VLESS/TCP，不使用 VLESS Encryption。
set -euo pipefail
umask 077

SCRIPT_VERSION="3.2.6"
SCRIPT_AUTHOR="ike"
SCRIPT_NAME="NoBrand-OneClick"
SCRIPT_REPO="ike-sh/NoBrand-OneClick"
NOBRAND_SCHEMA_VERSION=3

# NoBrand 3 has one authoritative product-state root. Lifecycle recovery
# metadata and its process lock deliberately live beside, not below, that
# root so an interrupted full uninstall cannot erase the evidence needed by
# the next invocation.
NOBRAND_STATE_DIR="${NOBRAND_STATE_DIR:-/var/lib/nobrand-oneclick}"
NOBRAND_CONFIG_DIR="${NOBRAND_CONFIG_DIR:-/etc/nobrand-oneclick}"
NOBRAND_LIB_DIR="${NOBRAND_LIB_DIR:-/usr/local/lib/nobrand-oneclick}"
NOBRAND_LIFECYCLE_DIR="${NOBRAND_LIFECYCLE_DIR:-/var/lib/nobrand-oneclick-lifecycle}"
NOBRAND_LIFECYCLE_TX_FILE="${NOBRAND_LIFECYCLE_TX_FILE:-${NOBRAND_LIFECYCLE_DIR}/transaction.env}"
NOBRAND_BACKUP_RESTORE_TX_DIR="${NOBRAND_LIFECYCLE_DIR}/backup-restore"
NOBRAND_BACKUP_RESTORE_META_FILE="${NOBRAND_BACKUP_RESTORE_TX_DIR}/transaction.env"
NOBRAND_BACKUP_RESTORE_SNAPSHOT_DIR="${NOBRAND_BACKUP_RESTORE_TX_DIR}/snapshot"
NOBRAND_BACKUP_RESTORE_ROOTS_MANIFEST="${NOBRAND_BACKUP_RESTORE_TX_DIR}/snapshot-roots.manifest"
NOBRAND_LIFECYCLE_LOCK_FILE="${NOBRAND_LIFECYCLE_LOCK_FILE:-/run/nobrand-oneclick/lifecycle.lock}"
NOBRAND_BIN_DIR="${NOBRAND_BIN_DIR:-${NOBRAND_LIB_DIR}/bin}"
NOBRAND_BACKUP_DIR="${NOBRAND_BACKUP_DIR:-${NOBRAND_STATE_DIR}/backups}"
NOBRAND_LOCK_DIR="${NOBRAND_LOCK_DIR:-${NOBRAND_STATE_DIR}/locks}"
NOBRAND_REGISTRY_FILE="${NOBRAND_REGISTRY_FILE:-${NOBRAND_STATE_DIR}/state.json}"
NOBRAND_INGRESS_STATE_FILE="${NOBRAND_INGRESS_STATE_FILE:-${NOBRAND_STATE_DIR}/ingress.json}"
NOBRAND_INGRESS_FIREWALL_STATE_FILE="${NOBRAND_INGRESS_FIREWALL_STATE_FILE:-${NOBRAND_STATE_DIR}/ingress-firewall.json}"
NOBRAND_INGRESS_FIREWALL_RULESET="${NOBRAND_INGRESS_FIREWALL_RULESET:-${NOBRAND_CONFIG_DIR}/ingress-firewall.nft}"
NOBRAND_INGRESS_NFT_FAMILY="${NOBRAND_INGRESS_NFT_FAMILY:-inet}"
NOBRAND_INGRESS_NFT_TABLE="${NOBRAND_INGRESS_NFT_TABLE:-nobrand_ingress}"
NOBRAND_FIREWALL_OWNED_STATE="${NOBRAND_FIREWALL_OWNED_STATE:-${NOBRAND_STATE_DIR}/firewall-owned.bindings}"
NOBRAND_FIREWALL_COMMENT="nobrand-oneclick"
NOBRAND_INSTALL_SCRIPT_PATH="${NOBRAND_INSTALL_SCRIPT_PATH:-/usr/local/bin/install-nobrand}"
NOBRAND_COMMAND_PATH="${NOBRAND_COMMAND_PATH:-/usr/local/bin/nobrand}"
NOBRAND_SHORT_COMMAND_PATH="${NOBRAND_SHORT_COMMAND_PATH:-/usr/local/bin/nb}"
NOBRAND_RELEASE_INSTALLER_URL="https://github.com/${SCRIPT_REPO}/releases/latest/download/install-nobrand.sh"
# Read-only legacy detector paths; never installed or removed by this version.
NOBRAND_LEGACY_MIERU_STATE_DIR="${NOBRAND_LEGACY_MIERU_STATE_DIR:-/var/lib/mita-oneclick}"

MITA_MANAGER_STATE_DIR="${MITA_MANAGER_STATE_DIR:-${NOBRAND_STATE_DIR}/mieru}"
MITA_ADMIN_LOCK="${MITA_ADMIN_LOCK:-${NOBRAND_LOCK_DIR}/admin.lock}"
MITA_CLIENT_EXPORT_DIR="${MITA_CLIENT_EXPORT_DIR:-/root/nobrand-mieru-clients}"
MITA_FIREWALL_OWNED_STATE="${MITA_FIREWALL_OWNED_STATE:-${MITA_MANAGER_STATE_DIR}/firewall-owned.bindings}"
MITA_FIREWALL_COMMENT="nobrand-mieru"
BBR_SYSCTL_CONF="${BBR_SYSCTL_CONF:-/etc/sysctl.d/mieru_tcp_bbr.conf}"
BBR_STATE_FILE="${BBR_STATE_FILE:-${NOBRAND_STATE_DIR}/bbr-owned.state}"
BBR_BACKUP_FILE="${BBR_BACKUP_FILE:-${NOBRAND_STATE_DIR}/bbr-sysctl.backup}"
MITA_INSTANCE_SYSTEMD_TEMPLATE="${MITA_INSTANCE_SYSTEMD_TEMPLATE:-/etc/systemd/system/nobrand-mieru@.service}"
INSTALL_SCRIPT_PATH="${NOBRAND_INSTALL_SCRIPT_PATH}"
NOBRAND_SNELL_SYSTEMD_TEMPLATE="${NOBRAND_SNELL_SYSTEMD_TEMPLATE:-/etc/systemd/system/nobrand-snell@.service}"

NOBRAND_XRAY_BIN="${NOBRAND_XRAY_BIN:-${NOBRAND_BIN_DIR}/xray}"
NOBRAND_XRAY_ASSET_DIR="${NOBRAND_XRAY_ASSET_DIR:-${NOBRAND_LIB_DIR}/xray-assets}"
NOBRAND_HY2_SYSTEMD_SERVICE="${NOBRAND_HY2_SYSTEMD_SERVICE:-/etc/systemd/system/nobrand-hysteria2.service}"
NOBRAND_HY2_OPENRC_SERVICE="${NOBRAND_HY2_OPENRC_SERVICE:-/etc/init.d/nobrand-hysteria2}"
TESTED_XRAY_VERSION="26.3.27"
TESTED_XRAY_AMD64_SHA256="23cd9af937744d97776ee35ecad4972cf4b2109d1e0fe6be9930467608f7c8ae"
TESTED_XRAY_ARM64_SHA256="4d30283ae614e3057f730f67cd088a42be6fdf91f8639d82cb69e48cde80413c"
NOBRAND_XRAY_RELEASE_API="https://api.github.com/repos/XTLS/Xray-core/releases/tags/v${TESTED_XRAY_VERSION}"

NOBRAND_VLESS_STATE_DIR="${NOBRAND_VLESS_STATE_DIR:-${NOBRAND_STATE_DIR}/vless-sudoku}"
NOBRAND_VLESS_STATE_FILE="${NOBRAND_VLESS_STATE_FILE:-${NOBRAND_VLESS_STATE_DIR}/state.json}"
NOBRAND_VLESS_CLIENT_FILE="${NOBRAND_VLESS_CLIENT_FILE:-${NOBRAND_VLESS_STATE_DIR}/client.json}"
NOBRAND_VLESS_CONFIG_DIR="${NOBRAND_VLESS_CONFIG_DIR:-${NOBRAND_CONFIG_DIR}/vless-sudoku}"
NOBRAND_VLESS_CONFIG_FILE="${NOBRAND_VLESS_CONFIG_FILE:-${NOBRAND_VLESS_CONFIG_DIR}/config.json}"
NOBRAND_VLESS_SERVICE_NAME="nobrand-vless-sudoku"
NOBRAND_VLESS_SYSTEMD_SERVICE="${NOBRAND_VLESS_SYSTEMD_SERVICE:-/etc/systemd/system/nobrand-vless-sudoku.service}"
NOBRAND_VLESS_OPENRC_SERVICE="${NOBRAND_VLESS_OPENRC_SERVICE:-/etc/init.d/nobrand-vless-sudoku}"
NOBRAND_VLESS_TAG="nobrand-vless-sudoku-in"

NOBRAND_REALITY_SYSTEMD_TEMPLATE="${NOBRAND_REALITY_SYSTEMD_TEMPLATE:-/etc/systemd/system/nobrand-vless-reality@.service}"
NOBRAND_REALITY_DEFAULT_CAMOUFLAGE_PORT="443"

NOBRAND_TUIC_SYSTEMD_TEMPLATE="${NOBRAND_TUIC_SYSTEMD_TEMPLATE:-/etc/systemd/system/nobrand-tuic@.service}"

# SSH Tunnel is a policy/account layer around the existing system sshd. It
# owns no listener, host key, package, firewall entry, or administrator key.
NOBRAND_SSH_GROUP="${NOBRAND_SSH_GROUP:-nobrand-ssh-tunnel}"
NOBRAND_SSH_STATE_DIR="${NOBRAND_SSH_STATE_DIR:-${NOBRAND_STATE_DIR}/ssh-tunnel}"
NOBRAND_SSH_STATE_FILE="${NOBRAND_SSH_STATE_FILE:-${NOBRAND_SSH_STATE_DIR}/state.json}"
NOBRAND_SSH_KEYS_DIR="${NOBRAND_SSH_KEYS_DIR:-${NOBRAND_SSH_STATE_DIR}/keys}"
NOBRAND_SSH_WATCHDOG_DIR="${NOBRAND_SSH_WATCHDOG_DIR:-${NOBRAND_SSH_STATE_DIR}/watchdog}"
NOBRAND_SSH_CONFIG_DIR="${NOBRAND_SSH_CONFIG_DIR:-${NOBRAND_CONFIG_DIR}/ssh-tunnel}"
NOBRAND_SSH_AUTHORIZED_KEYS_DIR="${NOBRAND_SSH_AUTHORIZED_KEYS_DIR:-${NOBRAND_SSH_CONFIG_DIR}/authorized_keys}"
NOBRAND_SSH_ACCOUNT_MARKER_DIR="${NOBRAND_SSH_ACCOUNT_MARKER_DIR:-${NOBRAND_SSH_CONFIG_DIR}/accounts}"
NOBRAND_SSH_GROUP_MARKER="${NOBRAND_SSH_GROUP_MARKER:-${NOBRAND_SSH_ACCOUNT_MARKER_DIR}/.group.json}"
NOBRAND_SSH_CONFIG_MAIN="${NOBRAND_SSH_CONFIG_MAIN:-/etc/ssh/sshd_config}"
NOBRAND_SSH_CONFIG_DROPIN="${NOBRAND_SSH_CONFIG_DROPIN:-/etc/ssh/sshd_config.d/90-nobrand-ssh-tunnel.conf}"
NOBRAND_SSH_BLOCK_BEGIN="# BEGIN NOBRAND SSH TUNNEL"
NOBRAND_SSH_BLOCK_END="# END NOBRAND SSH TUNNEL"

# Port Forward is a schema-v3 optional network feature. nftables state is
# confined to one NoBrand-owned table; Realm is installed to the private
# runtime directory and never replaces a system Realm installation.
NOBRAND_FORWARD_STATE_DIR="${NOBRAND_FORWARD_STATE_DIR:-${NOBRAND_STATE_DIR}/forward}"
NOBRAND_FORWARD_STATE_FILE="${NOBRAND_FORWARD_STATE_FILE:-${NOBRAND_FORWARD_STATE_DIR}/state.json}"
NOBRAND_FORWARD_CONFIG_DIR="${NOBRAND_FORWARD_CONFIG_DIR:-${NOBRAND_CONFIG_DIR}/forward}"
NOBRAND_FORWARD_REALM_CONFIG="${NOBRAND_FORWARD_REALM_CONFIG:-${NOBRAND_FORWARD_CONFIG_DIR}/realm.toml}"
NOBRAND_FORWARD_NFT_RULESET="${NOBRAND_FORWARD_NFT_RULESET:-${NOBRAND_FORWARD_CONFIG_DIR}/nftables.nft}"
NOBRAND_FORWARD_SYSCTL_STATE="${NOBRAND_FORWARD_SYSCTL_STATE:-${NOBRAND_FORWARD_STATE_DIR}/sysctl.json}"
NOBRAND_FORWARD_SYSCTL_FRAGMENT="${NOBRAND_FORWARD_SYSCTL_FRAGMENT:-/etc/sysctl.d/90-nobrand-forward.conf}"
NOBRAND_FORWARD_LOCK="${NOBRAND_FORWARD_LOCK:-${NOBRAND_LOCK_DIR}/forward.lock}"
NOBRAND_FORWARD_NFT_FAMILY="ip"
NOBRAND_FORWARD_NFT_TABLE="nobrand_forward_v4"
NOBRAND_REALM_BIN="${NOBRAND_REALM_BIN:-${NOBRAND_BIN_DIR}/realm}"
NOBRAND_REALM_RUNTIME_META="${NOBRAND_REALM_RUNTIME_META:-${NOBRAND_FORWARD_STATE_DIR}/realm-runtime.json}"
NOBRAND_REALM_SERVICE_NAME="nobrand-realm"
NOBRAND_REALM_SYSTEMD_SERVICE="${NOBRAND_REALM_SYSTEMD_SERVICE:-/etc/systemd/system/nobrand-realm.service}"
NOBRAND_REALM_OPENRC_SERVICE="${NOBRAND_REALM_OPENRC_SERVICE:-/etc/init.d/nobrand-realm}"
NOBRAND_REALM_RELEASE_API="https://api.github.com/repos/zhboner/realm/releases"
TESTED_REALM_VERSION="2.9.6"
TESTED_REALM_AMD64_MUSL_SHA256="b1cc335547bea8bb2a88178bef12ec7f2363e36200e7ea1d4e1e67627929bf65"
TESTED_REALM_ARM64_MUSL_SHA256="f4c0318dd86854da483dcb7645b4f39cae2cc3f91c688fef969d53220b949488"
PROTOCOL_FEATURE_FREEZE=true

# 多用户端口池：相对主端口偏移，或 IP 尾号段内扫描
USER_PORT_POOL_START="${USER_PORT_POOL_START:-}"
USER_PORT_POOL_END="${USER_PORT_POOL_END:-}"

ACTION=""
MENU_MODE=0
NOBRAND_INSTALL_STATE=""
NOBRAND_LIFECYCLE_OPERATION=""
NOBRAND_LIFECYCLE_SCOPE=""
NOBRAND_LIFECYCLE_ACTIVE=0
NOBRAND_LIFECYCLE_MUTATION_STARTED=0
NOBRAND_LIFECYCLE_LOCK_HELD=0
NOBRAND_MANAGER_SESSION_ACTIVE=0
NOBRAND_RECOVERY_EXPECTED_SCOPE=""
NOBRAND_RECOVERY_EXPECTED_STATE=""
NOBRAND_RECOVERY_EXPECTED_TX_PRESENT=0
NOBRAND_RECOVERY_EXPECTED_TX_STATUS=""
NOBRAND_RECOVERY_EXPECTED_TX_ID=""
NOBRAND_RECOVERY_EXPECTED_TX_RECORD=""
NOBRAND_MENU_EXIT_SUCCESS=4
YES=0
DRY_RUN=0
LANG_ZH=1
ENABLE_BBR=0
STAGE="初始化"

PORT=""
PORT_RANGE=""
PROTOCOL="TCP"
PROTOCOL_CLI=0
PROFILE="iplc"
PROFILE_CLI=0
ADVERTISE_HOST=""
ADVERTISE_PORT=""
ADVERTISE_CLI=0
USERNAME=""
PASSWORD=""
PASSWORD_CLI=0
OP_USER=""
MTU=1400
MTU_REQUEST=""
MTU_CLI=0
MULTIPLEXING="MULTIPLEXING_OFF"
HANDSHAKE_MODE="HANDSHAKE_NO_WAIT"
MULTIPLEXING_CLI=0
HANDSHAKE_CLI=0
TRAFFIC_PATTERN="off"
TRAFFIC_CLI=0
LOW_ENTROPY_MODE="LOW_ENTROPY_MODE_OFF"
LOW_ENTROPY_CLI=0
MIERU_CHANNEL="stable"
MIERU_CHANNEL_CLI=0
MIERU_VERSION=""
PORT_CLI=0
INGRESS_PROFILE=""
INGRESS_PROFILE_CLI=0
INGRESS_PROFILE_ID=""
USER_DEL_NAME=""
USER_SHOW_NAME=""
USER_QUOTA_MB=""
USER_QUOTA_DAYS=""
USER_QUOTA_MODE=""
USER_EXPIRE=""
USER_PACKAGE=""
USER_BANDWIDTH_MBPS=""
USER_RESTORE_FILE=""
TC_IFACE="${TC_IFACE:-}"

NOBRAND_ARGS_HANDLED=0
NOBRAND_PROTOCOL_FILTER=""
NOBRAND_BACKUP_ACTION=""
NOBRAND_BACKUP_PATH=""
SNELL_ACTION=""
SNELL_NAME=""
SNELL_VERSION="5"
SNELL_PSK=""
SNELL_QUIC_PROXY=""
HY2_ACTION=""
HY2_SNI=""
VLESS_SUDOKU_ACTION=""
VLESS_SUDOKU_UUID=""
VLESS_SUDOKU_PASSWORD=""
VLESS_SUDOKU_LISTEN="0.0.0.0"
VLESS_SUDOKU_CLIENT_SOCKS_PORT="${VLESS_SUDOKU_CLIENT_SOCKS_PORT:-18080}"
VLESS_REALITY_ACTION=""
VLESS_REALITY_NAME=""
VLESS_REALITY_TARGET=""
VLESS_REALITY_TARGET_PORT="$NOBRAND_REALITY_DEFAULT_CAMOUFLAGE_PORT"
TUIC_ACTION=""
TUIC_NAME=""
TUIC_USER=""
TUIC_SNI=""
TUIC_CHANNEL="stable"
TUIC_VERSION=""
TUIC_USER_ACTION=""
SSH_TUNNEL_ACTION=""
SSH_TUNNEL_USER_ACTION=""
SSH_TUNNEL_USER=""
SSH_TUNNEL_WATCHDOG_TOKEN=""
ADVERTISE_AUTO_REQUESTED=0
FORWARD_ACTION=""
FORWARD_RULE_ID=""
FORWARD_NAME=""
FORWARD_NOTE=""
FORWARD_BACKEND=""
FORWARD_PROTOCOL=""
FORWARD_LISTEN_HOST=""
FORWARD_LISTEN_HOST_CLI=0
FORWARD_LISTEN_PORT=""
FORWARD_TARGET_HOST=""
FORWARD_TARGET_PORT=""
FORWARD_SOURCE_MODE="masquerade"
FORWARD_SOURCE_MODE_CLI=0
FORWARD_ADVANCED_CLI=0
FORWARD_IMPORT_FILE=""
FORWARD_EXPORT_FILE=""
FORWARD_THROUGH=""
FORWARD_INTERFACE=""
FORWARD_LISTEN_INTERFACE=""
FORWARD_TCP_TIMEOUT="5"
FORWARD_UDP_TIMEOUT="30"
FORWARD_PROXY_SEND="false"
FORWARD_PROXY_ACCEPT="false"
FORWARD_PROXY_VERSION="2"
FORWARD_PROXY_ACCEPT_TIMEOUT="5"
FORWARD_DNS_MODE="system"
FORWARD_DNS_PROTOCOL="tcp_and_udp"
FORWARD_DNS_NAMESERVERS=""
FORWARD_LISTEN_TRANSPORT=""
FORWARD_REMOTE_TRANSPORT=""
FORWARD_EXTRA_TARGETS=""
FORWARD_BALANCE="off"
FORWARD_WEIGHTS=""
INGRESS_ACTION=""
INGRESS_PROFILE_SELECTOR=""
INGRESS_NAME=""
INGRESS_TYPE=""
INGRESS_INTERFACE=""
INGRESS_ADDRESS=""
INGRESS_PORT_POLICY=""
INGRESS_RANGE_START=""
INGRESS_RANGE_END=""
INGRESS_RESERVED_PORTS=""
INGRESS_DISPLAY_HOST_DEFAULT=""
INGRESS_DISPLAY_PORT_POLICY=""
INGRESS_DISPLAY_PORT=""
INGRESS_ENABLED=""
INGRESS_ENFORCEMENT=""
INGRESS_APPLY_EXISTING=0
INGRESS_ENFORCEMENT_RESOLVED=""
INGRESS_ENFORCEMENT_METHOD=""
INGRESS_LOCAL_ADDRESS=""
INGRESS_LISTEN_HOST=""
INGRESS_NAME_CLI=0
INGRESS_TYPE_CLI=0
INGRESS_INTERFACE_CLI=0
INGRESS_ADDRESS_CLI=0
INGRESS_PORT_POLICY_CLI=0
INGRESS_RANGE_START_CLI=0
INGRESS_RANGE_END_CLI=0
INGRESS_RESERVED_CLI=0
INGRESS_DISPLAY_HOST_CLI=0
INGRESS_DISPLAY_PORT_POLICY_CLI=0
INGRESS_DISPLAY_PORT_CLI=0
INGRESS_ENABLED_CLI=0
INGRESS_ENFORCEMENT_CLI=0

if [ -z "${BASH_VERSION:-}" ]; then
  echo "[错误] 请使用 bash 运行此脚本" >&2
  if [ -f /etc/alpine-release ]; then
    echo "Alpine 默认无 bash，请先安装后执行（root 无需 sudo）：" >&2
    echo "  apk add --no-cache bash curl" >&2
    echo "  curl -fsSLO https://github.com/ike-sh/NoBrand-OneClick/releases/latest/download/install-nobrand.sh" >&2
    echo "  bash install-nobrand.sh" >&2
  else
    echo "  curl -fsSLO https://github.com/ike-sh/NoBrand-OneClick/releases/latest/download/install-nobrand.sh" >&2
    echo "  sudo bash install-nobrand.sh" >&2
  fi
  exit 1
fi

on_error() {
  if declare -F nb_lifecycle_restore_pre_mutation >/dev/null 2>&1 \
     && [ "${NOBRAND_LIFECYCLE_ACTIVE:-0}" -eq 1 ] \
     && nb_lifecycle_tx_valid \
     && [ "$(nb_lifecycle_field STATUS)" = in-progress ] \
     && [ "$(nb_lifecycle_mutation_started)" = 0 ]; then
    nb_lifecycle_restore_pre_mutation >/dev/null 2>&1 || true
  fi
  msg "[错误] 步骤失败: ${STAGE}" >&2
  exit 1
}
trap on_error ERR

usage() {
  cat <<EOF
NoBrand-OneClick ${SCRIPT_VERSION} / Splicore v0.3.0-rc.4
用法 / Usage: nobrand <protocol> <action> [options]
协议 / Protocols: mieru, snell, hy2, tuic, vless-reality, vless-sudoku, ssh, forward
Actions: install, show, status, doctor, start, stop, restart, uninstall
Fresh install: --port PORT --advertise-host HOST -y
Mieru: --protocol TCP|UDP|BOTH --user NAME --password VALUE --mtu 1400
Snell: --version 4|5; QUIC Proxy Mode is unsupported.
REALITY: --target COVER_HOST --target-port 443; native Vision and Local Tunnel Guard.
HY2: --sni HOST; fresh TLS trust and Salamander credentials.
Native state: nobrand runtime status|doctor|backup|restore|rollback
Product backup: nobrand backup create|list|restore --file PATH
Legacy multi-core in-place migration is NOT SUPPORTED. Use a clean installation.
EOF
}

msg() { printf '%s\n' "$*"; }
info() { msg "==> $*"; }
warn() { msg "[警告] $*"; }
die() {
  msg "[错误] $*" >&2
  if [ "${MENU_MODE:-0}" -eq 1 ]; then
    return 1
  fi
  exit 1
}

t() {
  local zh="$1"
  local en="$2"
  if [ "$LANG_ZH" -eq 1 ]; then
    msg "$zh"
  else
    msg "$en"
  fi
}

print_banner() {
  msg ""
  t "NoBrand-OneClick / Mieru  v${SCRIPT_VERSION}" \
    "NoBrand-OneClick / Mieru  v${SCRIPT_VERSION}"
  t "作者: ${SCRIPT_AUTHOR} / https://github.com/${SCRIPT_REPO}" \
    "Author: ${SCRIPT_AUTHOR} / https://github.com/${SCRIPT_REPO}"
}

parse_nobrand_common_option() {
  case "${1:-}" in
    --yes|-y) YES=1 ;;
    --dry-run) DRY_RUN=1 ;;
    --port)
      PORT="${2:-}"
      PORT_CLI=1
      [ -n "$PORT" ] && [[ "$PORT" != --* ]] || die "--port 需要端口号"
      return 2
      ;;
    --ingress-profile)
      INGRESS_PROFILE="${2:-}"
      INGRESS_PROFILE_CLI=1
      [ -n "$INGRESS_PROFILE" ] && [[ "$INGRESS_PROFILE" != --* ]] || die "--ingress-profile 需要入口配置 ID 或名称"
      return 2
      ;;
    --advertise-host)
      ADVERTISE_HOST="${2:-}"
      ADVERTISE_CLI=1
      ADVERTISE_AUTO_REQUESTED=0
      [ -n "$ADVERTISE_HOST" ] && [[ "$ADVERTISE_HOST" != --* ]] || die "--advertise-host 需要地址"
      return 2
      ;;
    --advertise-port)
      ADVERTISE_PORT="${2:-}"
      ADVERTISE_CLI=1
      ADVERTISE_AUTO_REQUESTED=0
      [ -n "$ADVERTISE_PORT" ] && [[ "$ADVERTISE_PORT" != --* ]] || die "--advertise-port 需要端口"
      return 2
      ;;
    --advertise-auto)
      ADVERTISE_HOST=""
      ADVERTISE_PORT=""
      ADVERTISE_CLI=1
      ADVERTISE_AUTO_REQUESTED=1
      ;;
    *) return 1 ;;
  esac
  return 0
}

parse_nobrand_ingress_args() {
  INGRESS_ACTION="${1:-list}"
  [ "$#" -eq 0 ] || shift
  case "$INGRESS_ACTION" in
    create) INGRESS_ACTION=add ;;
    remove) INGRESS_ACTION=delete ;;
    default) INGRESS_ACTION='set-default' ;;
    list|show|add|modify|delete|set-default|unset-default|apply|doctor) ;;
    help|-h|--help) INGRESS_ACTION=help ;;
    *) die "未知 Ingress 操作: $INGRESS_ACTION" ;;
  esac
  if [ "$#" -gt 0 ] && [[ "$1" != --* ]]; then
    case "$INGRESS_ACTION" in show|modify|delete|set-default|apply) INGRESS_PROFILE_SELECTOR="$1"; shift ;; esac
  fi
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --id|--profile)
        INGRESS_PROFILE_SELECTOR="${2:-}"
        [ -n "$INGRESS_PROFILE_SELECTOR" ] && [[ "$INGRESS_PROFILE_SELECTOR" != --* ]] || die "$1 需要入口配置 ID 或名称"
        shift 2
        ;;
      --name)
        [ -n "${2:-}" ] && [[ "${2:-}" != --* ]] || die '--name 需要名称' || return 1
        INGRESS_NAME="$2"; INGRESS_NAME_CLI=1; shift 2
        ;;
      --type)
        [ -n "${2:-}" ] && [[ "${2:-}" != --* ]] || die '--type 需要类型' || return 1
        INGRESS_TYPE="$(printf '%s' "$2" | tr '[:upper:]' '[:lower:]')"; INGRESS_TYPE_CLI=1; shift 2
        ;;
      --interface)
        [ -n "${2:-}" ] && [[ "${2:-}" != --* ]] || die '--interface 需要网卡名' || return 1
        INGRESS_INTERFACE="$2"; INGRESS_INTERFACE_CLI=1; shift 2
        ;;
      --address)
        [ -n "${2:-}" ] && [[ "${2:-}" != --* ]] || die '--address 需要本地 IPv4' || return 1
        INGRESS_ADDRESS="$2"; INGRESS_ADDRESS_CLI=1; shift 2
        ;;
      --port-policy)
        [ -n "${2:-}" ] && [[ "${2:-}" != --* ]] || die '--port-policy 需要端口策略' || return 1
        INGRESS_PORT_POLICY="$(printf '%s' "$2" | tr '_' '-' | tr '[:upper:]' '[:lower:]')"
        INGRESS_PORT_POLICY_CLI=1; shift 2
        ;;
      --range-start) INGRESS_RANGE_START="${2:-}"; INGRESS_RANGE_START_CLI=1; shift 2 ;;
      --range-end) INGRESS_RANGE_END="${2:-}"; INGRESS_RANGE_END_CLI=1; shift 2 ;;
      --reserve|--reserved)
        [ -n "${2:-}" ] && [[ "${2:-}" != --* ]] || die "$1 需要端口或逗号分隔端口"
        INGRESS_RESERVED_PORTS="${INGRESS_RESERVED_PORTS}${INGRESS_RESERVED_PORTS:+,}${2}"
        INGRESS_RESERVED_CLI=1
        shift 2
        ;;
      --advertise-host|--display-host)
        INGRESS_DISPLAY_HOST_DEFAULT="${2:-}"; INGRESS_DISPLAY_HOST_CLI=1
        [ -n "$INGRESS_DISPLAY_HOST_DEFAULT" ] && [[ "$INGRESS_DISPLAY_HOST_DEFAULT" != --* ]] || die "$1 需要地址"
        shift 2
        ;;
      --clear-advertise-host|--clear-display-host) INGRESS_DISPLAY_HOST_DEFAULT=""; INGRESS_DISPLAY_HOST_CLI=1; shift ;;
      --display-port-policy)
        INGRESS_DISPLAY_PORT_POLICY="$(printf '%s' "${2:-}" | tr '_' '-' | tr '[:upper:]' '[:lower:]')"
        INGRESS_DISPLAY_PORT_POLICY_CLI=1; shift 2
        ;;
      --display-port) INGRESS_DISPLAY_PORT="${2:-}"; INGRESS_DISPLAY_PORT_CLI=1; shift 2 ;;
      --enable) INGRESS_ENABLED=true; INGRESS_ENABLED_CLI=1; shift ;;
      --disable) INGRESS_ENABLED=false; INGRESS_ENABLED_CLI=1; shift ;;
      --enforcement)
        INGRESS_ENFORCEMENT="$(printf '%s' "${2:-}" | tr '[:upper:]' '[:lower:]')"
        INGRESS_ENFORCEMENT_CLI=1
        shift 2
        ;;
      --apply-existing) INGRESS_APPLY_EXISTING=1; shift ;;
      --yes|-y) YES=1; shift ;;
      *) die "未知 Ingress 参数: $1" ;;
    esac
  done
  case "$INGRESS_ACTION" in
    show|modify|delete|set-default|apply) [ -n "$INGRESS_PROFILE_SELECTOR" ] || die "${INGRESS_ACTION} 需要入口配置 ID 或名称" ;;
  esac
  if [ "$INGRESS_ACTION" = add ]; then
    [ "$INGRESS_NAME_CLI" -eq 1 ] && [ -n "$INGRESS_NAME" ] \
      && [ "$INGRESS_TYPE_CLI" -eq 1 ] && [ -n "$INGRESS_TYPE" ] \
      && [ "$INGRESS_INTERFACE_CLI" -eq 1 ] && [ -n "$INGRESS_INTERFACE" ] \
      && [ "$INGRESS_ADDRESS_CLI" -eq 1 ] && [ -n "$INGRESS_ADDRESS" ] \
      && [ "$INGRESS_PORT_POLICY_CLI" -eq 1 ] && [ -n "$INGRESS_PORT_POLICY" ] \
      || die 'ingress add 非交互模式需要 --name --type --interface --address --port-policy' \
      || return 1
  fi
  ACTION="nobrand-ingress"
  NOBRAND_ARGS_HANDLED=1
}

parse_nobrand_snell_args() {
  SNELL_ACTION="${1:-menu}"
  [ "$#" -eq 0 ] || shift
  case "$SNELL_ACTION" in
    v4|4) SNELL_ACTION=install; SNELL_VERSION=4; ;;
    v5|5) SNELL_ACTION=install; SNELL_VERSION=5; ;;
    add|create) SNELL_ACTION=install ;;
    list|nodes) SNELL_ACTION=show ;;
    delete|uninstall) SNELL_ACTION=remove ;;
    endpoint) SNELL_ACTION="set-endpoint" ;;
    quic|set-quic) SNELL_ACTION="set-quic" ;;
    menu|install|show|set-endpoint|remove|start|stop|restart|status|doctor|upgrade) ;;
    help|-h|--help) SNELL_ACTION=help ;;
    *) die "未知 Snell 操作: $SNELL_ACTION" ;;
  esac
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --name)
        SNELL_NAME="${2:-}"
        [ -n "$SNELL_NAME" ] || die "--name 需要节点名"
        shift 2
        ;;
      --version)
        SNELL_VERSION="${2:-}"
        [ -n "$SNELL_VERSION" ] || die "--version 需要 4 或 5"
        shift 2
        ;;
      --psk)
        SNELL_PSK="${2:-}"
        [ -n "$SNELL_PSK" ] || die "--psk 需要值"
        shift 2
        ;;
      --quic)
        SNELL_QUIC_PROXY="${2:-}"
        [ -n "$SNELL_QUIC_PROXY" ] || die "--quic 需要 on 或 off"
        case "$SNELL_QUIC_PROXY" in
          on|off) ;;
          *) die "--quic 只支持 on 或 off" ;;
        esac
        shift 2
        ;;
      *)
        local consumed=0 rc=0
        parse_nobrand_common_option "$1" "${2:-}" || rc=$?
        case "$rc" in
          0) consumed=1 ;;
          2) consumed=2 ;;
          *) die "未知 Snell 参数: $1" ;;
        esac
        shift "$consumed"
        ;;
    esac
  done
  case "$SNELL_VERSION" in
    4|5) ;;
    *) die "Snell 只支持 v4、v5" ;;
  esac
  if [ "$SNELL_VERSION" = 4 ] && [ "$SNELL_QUIC_PROXY" = on ]; then
    die "Snell v4 不支持 QUIC Proxy 模式"
  fi
  ACTION="nobrand-snell"
  NOBRAND_ARGS_HANDLED=1
}

parse_nobrand_hy2_args() {
  HY2_ACTION="${1:-menu}"
  [ "$#" -eq 0 ] || shift
  case "$HY2_ACTION" in
    add|create|reconfigure) HY2_ACTION=install ;;
    nodes) HY2_ACTION=show ;;
    delete|uninstall) HY2_ACTION=remove ;;
    endpoint) HY2_ACTION=set-endpoint ;;
    menu|install|show|set-endpoint|remove|start|stop|restart|status|doctor|upgrade) ;;
    help|-h|--help) HY2_ACTION=help ;;
    *) die "未知 Hysteria2 操作: $HY2_ACTION" ;;
  esac
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --sni)
        HY2_SNI="${2:-}"
        [ -n "$HY2_SNI" ] || die "--sni 需要域名或 IPv4"
        shift 2
        ;;
      *)
        local consumed=0 rc=0
        parse_nobrand_common_option "$1" "${2:-}" || rc=$?
        case "$rc" in
          0) consumed=1 ;;
          2) consumed=2 ;;
          *) die "未知 Hysteria2 参数: $1" ;;
        esac
        shift "$consumed"
        ;;
    esac
  done
  ACTION="nobrand-hy2"
  NOBRAND_ARGS_HANDLED=1
}

parse_nobrand_vless_sudoku_args() {
  VLESS_SUDOKU_ACTION="${1:-menu}"
  [ "$#" -eq 0 ] || shift
  case "$VLESS_SUDOKU_ACTION" in
    add|create|reconfigure) VLESS_SUDOKU_ACTION=install ;;
    nodes) VLESS_SUDOKU_ACTION=show ;;
    delete|uninstall) VLESS_SUDOKU_ACTION=remove ;;
    endpoint) VLESS_SUDOKU_ACTION="set-endpoint" ;;
    menu|install|show|set-endpoint|remove|start|stop|restart|status|doctor|smoke|upgrade) ;;
    help|-h|--help) VLESS_SUDOKU_ACTION=help ;;
    *) die "未知 VLESS Sudoku 操作: $VLESS_SUDOKU_ACTION" ;;
  esac
  while [ "$#" -gt 0 ]; do
    local consumed=0 rc=0
    parse_nobrand_common_option "$1" "${2:-}" || rc=$?
    case "$rc" in
      0) consumed=1 ;;
      2) consumed=2 ;;
      *) die "未知 VLESS Sudoku 参数: $1" ;;
    esac
    shift "$consumed"
  done
  ACTION="nobrand-vless-sudoku"
  NOBRAND_ARGS_HANDLED=1
}

parse_nobrand_vless_reality_args() {
  local consumed rc
  VLESS_REALITY_ACTION="${1:-menu}"
  [ "$#" -eq 0 ] || shift
  case "$VLESS_REALITY_ACTION" in
    add|create) VLESS_REALITY_ACTION=install ;;
    nodes) VLESS_REALITY_ACTION=show ;;
    delete) VLESS_REALITY_ACTION=remove ;;
    endpoint) VLESS_REALITY_ACTION=set-endpoint ;;
    menu|install|show|export|set-endpoint|remove|uninstall|start|stop|restart|status|doctor|upgrade) ;;
    help|-h|--help) VLESS_REALITY_ACTION=help ;;
    *) die "未知 VLESS REALITY 操作: $VLESS_REALITY_ACTION" ;;
  esac
  if [ "$#" -gt 0 ] && [[ "$1" != --* ]]; then
    case "$VLESS_REALITY_ACTION" in
      show|export|set-endpoint|remove|uninstall|start|stop|restart|status|doctor)
        VLESS_REALITY_NAME="$1"; shift ;;
    esac
  fi
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --name)
        VLESS_REALITY_NAME="${2:-}"
        [ -n "$VLESS_REALITY_NAME" ] && [[ "$VLESS_REALITY_NAME" != --* ]] \
          || die '--name 需要 VLESS REALITY 实例名称'
        shift 2
        ;;
      --target|--server-name|--sni)
        VLESS_REALITY_TARGET="${2:-}"
        [ -n "$VLESS_REALITY_TARGET" ] && [[ "$VLESS_REALITY_TARGET" != --* ]] \
          || die "$1 需要公网主机名"
        shift 2
        ;;
      --target-port)
        VLESS_REALITY_TARGET_PORT="${2:-}"
        [ -n "$VLESS_REALITY_TARGET_PORT" ] && [[ "$VLESS_REALITY_TARGET_PORT" != --* ]] \
          || die '--target-port 需要端口'
        shift 2
        ;;
      *)
        consumed=0; rc=0
        parse_nobrand_common_option "$1" "${2:-}" || rc=$?
        case "$rc" in
          0) consumed=1 ;;
          2) consumed=2 ;;
          *) die "未知 VLESS REALITY 参数: $1" ;;
        esac
        shift "$consumed"
        ;;
    esac
  done
  ACTION="nobrand-vless-reality"
  NOBRAND_ARGS_HANDLED=1
}

parse_nobrand_tuic_args() {
  local consumed rc
  TUIC_ACTION="${1:-menu}"
  [ "$#" -eq 0 ] || shift
  if [ "$TUIC_ACTION" = user ]; then
    TUIC_USER_ACTION="${1:-list}"
    [ "$#" -eq 0 ] || shift
    case "$TUIC_USER_ACTION" in
      add|create) TUIC_ACTION="user-add" ;;
      delete|del|remove) TUIC_ACTION="user-delete" ;;
      list) TUIC_ACTION="user-list" ;;
      show|export) TUIC_ACTION="user-show" ;;
      rotate|rotate-key) TUIC_ACTION="user-rotate" ;;
      *) die "未知 TUIC 用户操作: $TUIC_USER_ACTION" ;;
    esac
  else
    case "$TUIC_ACTION" in
      add|create) TUIC_ACTION=install ;;
      remove|delete) TUIC_ACTION=uninstall ;;
      endpoint) TUIC_ACTION="set-endpoint" ;;
      upgrade) TUIC_ACTION="upgrade-runtime" ;;
      menu|install|start|stop|restart|status|doctor|show|export|set-endpoint|upgrade-runtime|uninstall) ;;
      help|-h|--help) TUIC_ACTION=help ;;
      *) die "未知 TUIC 操作: $TUIC_ACTION" ;;
    esac
  fi
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --name)
        TUIC_NAME="${2:-}"
        [ -n "$TUIC_NAME" ] && [[ "$TUIC_NAME" != --* ]] || die '--name 需要 TUIC 实例名称'
        shift 2
        ;;
      --user)
        TUIC_USER="${2:-}"
        [ -n "$TUIC_USER" ] && [[ "$TUIC_USER" != --* ]] || die '--user 需要 TUIC 用户名称'
        shift 2
        ;;
      --sni)
        TUIC_SNI="${2:-}"
        [ -n "$TUIC_SNI" ] && [[ "$TUIC_SNI" != --* ]] || die '--sni 需要域名或 IPv4'
        shift 2
        ;;
      --channel)
        TUIC_CHANNEL="${2:-}"
        [ -n "$TUIC_CHANNEL" ] && [[ "$TUIC_CHANNEL" != --* ]] || die '--channel 需要 stable、latest 或 pinned'
        shift 2
        ;;
      --runtime-version|--version)
        TUIC_VERSION="${2:-}"
        TUIC_CHANNEL=pinned
        [ -n "$TUIC_VERSION" ] && [[ "$TUIC_VERSION" != --* ]] || die '--runtime-version 需要精确版本'
        shift 2
        ;;
      *)
        consumed=0 rc=0
        parse_nobrand_common_option "$1" "${2:-}" || rc=$?
        case "$rc" in
          0) consumed=1 ;;
          2) consumed=2 ;;
          *) die "未知 TUIC 参数: $1" ;;
        esac
        shift "$consumed"
        ;;
    esac
  done
  case "$TUIC_CHANNEL" in stable|latest|pinned) ;; *) die 'TUIC 通道只支持 stable、latest、pinned' ;; esac
  ACTION="nobrand-tuic"
  NOBRAND_ARGS_HANDLED=1
}

parse_nobrand_ssh_args() {
  local consumed rc
  SSH_TUNNEL_ACTION="${1:-menu}"
  [ "$#" -eq 0 ] || shift
  if [ "$SSH_TUNNEL_ACTION" = user ]; then
    SSH_TUNNEL_USER_ACTION="${1:-list}"
    [ "$#" -eq 0 ] || shift
    case "$SSH_TUNNEL_USER_ACTION" in
      add|create) SSH_TUNNEL_ACTION="user-add" ;;
      delete|del|remove) SSH_TUNNEL_ACTION="user-delete" ;;
      list) SSH_TUNNEL_ACTION="user-list" ;;
      show) SSH_TUNNEL_ACTION="user-show" ;;
      export) SSH_TUNNEL_ACTION="user-export" ;;
      rotate|rotate-key) SSH_TUNNEL_ACTION="user-rotate-key" ;;
      *) die "未知 SSH Tunnel 用户操作: $SSH_TUNNEL_USER_ACTION" ;;
    esac
  else
    case "$SSH_TUNNEL_ACTION" in
      add|create) SSH_TUNNEL_ACTION=install ;;
      remove|delete) SSH_TUNNEL_ACTION=uninstall ;;
      endpoint) SSH_TUNNEL_ACTION="set-endpoint" ;;
      menu|install|status|doctor|show|export|set-endpoint|confirm-admin|uninstall) ;;
      help|-h|--help) SSH_TUNNEL_ACTION=help ;;
      *) die "未知 SSH Tunnel 操作: $SSH_TUNNEL_ACTION" ;;
    esac
  fi
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --user)
        SSH_TUNNEL_USER="${2:-}"
        [ -n "$SSH_TUNNEL_USER" ] && [[ "$SSH_TUNNEL_USER" != --* ]] || die '--user 需要 SSH Tunnel 用户标签'
        shift 2
        ;;
      --token)
        SSH_TUNNEL_WATCHDOG_TOKEN="${2:-}"
        [ -n "$SSH_TUNNEL_WATCHDOG_TOKEN" ] && [[ "$SSH_TUNNEL_WATCHDOG_TOKEN" != --* ]] \
          || die '--token 需要看门狗令牌'
        shift 2
        ;;
      *)
        consumed=0 rc=0
        parse_nobrand_common_option "$1" "${2:-}" || rc=$?
        case "$rc" in
          0) consumed=1 ;;
          2) consumed=2 ;;
          *) die "未知 SSH Tunnel 参数: $1" ;;
        esac
        shift "$consumed"
        ;;
    esac
  done
  ACTION="nobrand-ssh-tunnel"
  NOBRAND_ARGS_HANDLED=1
}

parse_nobrand_forward_args() {
  local value
  FORWARD_ACTION="${1:-menu}"
  [ "$#" -eq 0 ] || shift
  case "$FORWARD_ACTION" in
    create) FORWARD_ACTION=add ;;
    remove) FORWARD_ACTION=delete ;;
    endpoint) FORWARD_ACTION=set-endpoint ;;
    switch) FORWARD_ACTION=switch-backend ;;
    menu|add|delete|modify|list|show|enable|disable|set-endpoint|switch-backend|doctor|export|import|upgrade-runtime|uninstall) ;;
    help|-h|--help) FORWARD_ACTION=help ;;
    *) die "未知 Port Forward 操作: $FORWARD_ACTION" ;;
  esac
  if [ "$#" -gt 0 ] && [[ "$1" != --* ]]; then
    case "$FORWARD_ACTION" in
      delete|modify|show|enable|disable|set-endpoint|switch-backend)
        FORWARD_RULE_ID="$1"; shift ;;
      export) FORWARD_EXPORT_FILE="$1"; shift ;;
      import) FORWARD_IMPORT_FILE="$1"; shift ;;
    esac
  fi
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --id|--rule|--rule-id)
        FORWARD_RULE_ID="${2:-}"
        [ -n "$FORWARD_RULE_ID" ] && [[ "$FORWARD_RULE_ID" != --* ]] || die "$1 需要规则 ID 或名称"
        shift 2
        ;;
      --name)
        FORWARD_NAME="${2:-}"
        [ -n "$FORWARD_NAME" ] && [[ "$FORWARD_NAME" != --* ]] || die '--name 需要规则名'
        shift 2
        ;;
      --note)
        FORWARD_NOTE="${2:-}"
        [[ -n "${2:-}" && "${2:-}" != --* ]] || die '--note 需要说明文字'
        shift 2
        ;;
      --backend)
        FORWARD_BACKEND="$(printf '%s' "${2:-}" | tr '[:upper:]' '[:lower:]')"
        [ -n "$FORWARD_BACKEND" ] && [[ "$FORWARD_BACKEND" != --* ]] || die '--backend 需要 nftables 或 realm'
        shift 2
        ;;
      --protocol)
        FORWARD_PROTOCOL="${2:-}"
        [ -n "$FORWARD_PROTOCOL" ] && [[ "$FORWARD_PROTOCOL" != --* ]] || die '--protocol 需要 TCP、UDP 或 BOTH'
        shift 2
        ;;
      --listen|--listen-host)
        FORWARD_LISTEN_HOST="${2:-}"
        FORWARD_LISTEN_HOST_CLI=1
        [ -n "$FORWARD_LISTEN_HOST" ] && [[ "$FORWARD_LISTEN_HOST" != --* ]] || die "$1 需要监听地址"
        shift 2
        ;;
      --port|--listen-port)
        FORWARD_LISTEN_PORT="${2:-}"
        [ -n "$FORWARD_LISTEN_PORT" ] && [[ "$FORWARD_LISTEN_PORT" != --* ]] || die "$1 需要监听端口"
        shift 2
        ;;
      --target)
        FORWARD_TARGET_HOST="${2:-}"
        [ -n "$FORWARD_TARGET_HOST" ] && [[ "$FORWARD_TARGET_HOST" != --* ]] || die '--target 需要 IPv4、IPv6 或域名'
        shift 2
        ;;
      --target-port)
        FORWARD_TARGET_PORT="${2:-}"
        [ -n "$FORWARD_TARGET_PORT" ] && [[ "$FORWARD_TARGET_PORT" != --* ]] || die '--target-port 需要端口'
        shift 2
        ;;
      --source-mode)
        FORWARD_SOURCE_MODE="$(printf '%s' "${2:-}" | tr '[:upper:]' '[:lower:]')"
        [ -n "$FORWARD_SOURCE_MODE" ] && [[ "$FORWARD_SOURCE_MODE" != --* ]] || die '--source-mode 需要 masquerade 或 preserve'
        FORWARD_SOURCE_MODE_CLI=1
        shift 2
        ;;
      --through) FORWARD_THROUGH="${2:-}"; [[ -n "${2:-}" && "${2:-}" != --* ]] || die '--through 需要出站 IP'; FORWARD_ADVANCED_CLI=1; shift 2 ;;
      --interface) FORWARD_INTERFACE="${2:-}"; [[ -n "${2:-}" && "${2:-}" != --* ]] || die '--interface 需要网络接口'; FORWARD_ADVANCED_CLI=1; shift 2 ;;
      --listen-interface) FORWARD_LISTEN_INTERFACE="${2:-}"; [[ -n "${2:-}" && "${2:-}" != --* ]] || die '--listen-interface 需要监听网络接口'; FORWARD_ADVANCED_CLI=1; shift 2 ;;
      --tcp-timeout) FORWARD_TCP_TIMEOUT="${2:-}"; [[ -n "${2:-}" && "${2:-}" != --* ]] || die '--tcp-timeout 需要秒数'; FORWARD_ADVANCED_CLI=1; shift 2 ;;
      --udp-timeout) FORWARD_UDP_TIMEOUT="${2:-}"; [[ -n "${2:-}" && "${2:-}" != --* ]] || die '--udp-timeout 需要秒数'; FORWARD_ADVANCED_CLI=1; shift 2 ;;
      --proxy-send) FORWARD_PROXY_SEND="${2:-}"; [[ -n "${2:-}" && "${2:-}" != --* ]] || die '--proxy-send 需要 true 或 false'; FORWARD_ADVANCED_CLI=1; shift 2 ;;
      --proxy-accept) FORWARD_PROXY_ACCEPT="${2:-}"; [[ -n "${2:-}" && "${2:-}" != --* ]] || die '--proxy-accept 需要 true 或 false'; FORWARD_ADVANCED_CLI=1; shift 2 ;;
      --proxy-version) FORWARD_PROXY_VERSION="${2:-}"; [[ -n "${2:-}" && "${2:-}" != --* ]] || die '--proxy-version 需要 1 或 2'; FORWARD_ADVANCED_CLI=1; shift 2 ;;
      --proxy-accept-timeout) FORWARD_PROXY_ACCEPT_TIMEOUT="${2:-}"; [[ -n "${2:-}" && "${2:-}" != --* ]] || die '--proxy-accept-timeout 需要秒数'; FORWARD_ADVANCED_CLI=1; shift 2 ;;
      --dns-mode) FORWARD_DNS_MODE="${2:-}"; [[ -n "${2:-}" && "${2:-}" != --* ]] || die '--dns-mode 需要 Realm DNS 模式'; FORWARD_ADVANCED_CLI=1; shift 2 ;;
      --dns-protocol) FORWARD_DNS_PROTOCOL="${2:-}"; [[ -n "${2:-}" && "${2:-}" != --* ]] || die '--dns-protocol 需要 tcp、udp 或 tcp_and_udp'; FORWARD_ADVANCED_CLI=1; shift 2 ;;
      --dns-nameservers) FORWARD_DNS_NAMESERVERS="${2:-}"; [[ -n "${2:-}" && "${2:-}" != --* ]] || die '--dns-nameservers 需要逗号分隔地址'; FORWARD_ADVANCED_CLI=1; shift 2 ;;
      --listen-transport) FORWARD_LISTEN_TRANSPORT="${2:-}"; [[ -n "${2:-}" && "${2:-}" != --* ]] || die '--listen-transport 需要 Realm 传输字符串'; FORWARD_ADVANCED_CLI=1; shift 2 ;;
      --remote-transport) FORWARD_REMOTE_TRANSPORT="${2:-}"; [[ -n "${2:-}" && "${2:-}" != --* ]] || die '--remote-transport 需要 Realm 传输字符串'; FORWARD_ADVANCED_CLI=1; shift 2 ;;
      --extra-targets) FORWARD_EXTRA_TARGETS="${2:-}"; [[ -n "${2:-}" && "${2:-}" != --* ]] || die '--extra-targets 需要逗号分隔 host:port'; FORWARD_ADVANCED_CLI=1; shift 2 ;;
      --balance) FORWARD_BALANCE="${2:-}"; [[ -n "${2:-}" && "${2:-}" != --* ]] || die '--balance 需要 off、roundrobin 或 iphash'; FORWARD_ADVANCED_CLI=1; shift 2 ;;
      --weights) FORWARD_WEIGHTS="${2:-}"; [[ -n "${2:-}" && "${2:-}" != --* ]] || die '--weights 需要逗号分隔权重'; FORWARD_ADVANCED_CLI=1; shift 2 ;;
      --file)
        value="${2:-}"
        [ -n "$value" ] && [[ "$value" != --* ]] || die '--file 需要路径'
        [ "$FORWARD_ACTION" = import ] && FORWARD_IMPORT_FILE="$value" || FORWARD_EXPORT_FILE="$value"
        shift 2
        ;;
      --advertise-host|--advertise-port|--advertise-auto|--ingress-profile|--yes|-y|--dry-run)
        local consumed=0 rc=0
        parse_nobrand_common_option "$1" "${2:-}" || rc=$?
        case "$rc" in 0) consumed=1 ;; 2) consumed=2 ;; *) die "未知 Forward 参数: $1" ;; esac
        shift "$consumed"
        ;;
      *) die "未知 Forward 参数: $1" ;;
    esac
  done
  ACTION="nobrand-forward"
  NOBRAND_ARGS_HANDLED=1
}

detect_nobrand_entry() {
  # Every shipped executable is the NoBrand parser. There is deliberately no
  # legacy basename branch in the 3.0 public API.
  [ "$#" -gt 0 ] || { NOBRAND_ARGS_HANDLED=1; return 0; }
  case "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" in
    mieru)
      shift
      if [ "$#" -eq 0 ]; then
        ACTION="nobrand-mieru-menu"
        NOBRAND_ARGS_HANDLED=1
      else
        # The mature Mieru option parser is an internal NoBrand subsystem.
        NOBRAND_REPARSED_ARGS=("$@")
      fi
      ;;
    snell)
      shift
      parse_nobrand_snell_args "$@"
      ;;
    hy2|hysteria2)
      shift
      parse_nobrand_hy2_args "$@"
      ;;
    vless-sudoku|sudoku)
      shift
      parse_nobrand_vless_sudoku_args "$@"
      ;;
    vless-reality|reality)
      shift
      parse_nobrand_vless_reality_args "$@"
      ;;
    tuic)
      shift
      parse_nobrand_tuic_args "$@"
      ;;
    ssh|ssh-tunnel)
      shift
      parse_nobrand_ssh_args "$@"
      ;;
    forward|port-forward)
      shift
      parse_nobrand_forward_args "$@"
      ;;
    ingress)
      shift
      parse_nobrand_ingress_args "$@"
      ;;
    runtime)
      shift
      NOBRAND_RUNTIME_ARGS=("$@")
      ACTION="nobrand-runtime"; NOBRAND_ARGS_HANDLED=1
      ;;
    manager)
      shift
      NOBRAND_MANAGER_ACTION="${1:-}"
      [ "$#" -eq 0 ] || shift
      case "$NOBRAND_MANAGER_ACTION" in
        install|upgrade) ;;
        *) die 'manager 只支持 install 或 upgrade' ;;
      esac
      [ "$#" -eq 0 ] || die 'manager install/upgrade 不接受额外参数'
      ACTION="nobrand-manager-upgrade"; NOBRAND_ARGS_HANDLED=1
      ;;
    status)
      [ "$#" -eq 1 ] || die 'status 不接受参数'
      ACTION="nobrand-status"; NOBRAND_ARGS_HANDLED=1
      ;;
    nodes)
      shift
      while [ "$#" -gt 0 ]; do
        case "$1" in
          --protocol)
            NOBRAND_PROTOCOL_FILTER="${2:-}"
            [ -n "$NOBRAND_PROTOCOL_FILTER" ] \
              || die "--protocol 需要 mieru、snell、hy2、tuic、vless-reality、vless-sudoku、ssh 或 forward"
            shift 2
            ;;
          *) die "未知 nodes 参数: $1" ;;
        esac
      done
      ACTION="nobrand-nodes"; NOBRAND_ARGS_HANDLED=1
      ;;
    doctor)
      [ "$#" -eq 1 ] || die 'doctor 不接受参数'
      ACTION="nobrand-doctor"; NOBRAND_ARGS_HANDLED=1
      ;;
    backup)
      shift
      NOBRAND_BACKUP_ACTION="${1:-create}"
      [ "$#" -eq 0 ] || shift
      case "$NOBRAND_BACKUP_ACTION" in create|restore|list) ;; *) die "backup 只支持 create、restore、list" ;; esac
      if [ "$#" -gt 0 ]; then
        NOBRAND_BACKUP_PATH="$1"
        shift
      fi
      [ "$#" -eq 0 ] || die "backup 参数过多"
      ACTION="nobrand-backup"; NOBRAND_ARGS_HANDLED=1
      ;;
    uninstall|remove)
      shift
      while [ "$#" -gt 0 ]; do
        case "$1" in
          --yes|-y) YES=1; shift ;;
          *) die "未知 uninstall 参数: $1" ;;
        esac
      done
      ACTION="nobrand-uninstall"; NOBRAND_ARGS_HANDLED=1
      ;;
    network|bbr)
      [ "$#" -eq 1 ] || die 'network/bbr 不接受参数'
      ACTION="nobrand-network"; NOBRAND_ARGS_HANDLED=1
      ;;
    menu)
      [ "$#" -eq 1 ] || die 'menu 不接受参数'
      ACTION=""; NOBRAND_ARGS_HANDLED=1
      ;;
    help|-h|--help)
      [ "$#" -eq 1 ] || die 'help 不接受参数'
      ACTION="nobrand-help"; NOBRAND_ARGS_HANDLED=1
      ;;
    version|--version)
      [ "$#" -eq 1 ] || die 'version 不接受参数'
      ACTION="nobrand-version"; NOBRAND_ARGS_HANDLED=1
      ;;
    *) die "未知 NoBrand 操作: $1（使用 --help 查看帮助）" ;;
  esac
}

NOBRAND_REPARSED_ARGS=()
detect_nobrand_entry "$@"
if [ "${#NOBRAND_REPARSED_ARGS[@]}" -gt 0 ]; then
  set -- "${NOBRAND_REPARSED_ARGS[@]}"
fi

while [ "$NOBRAND_ARGS_HANDLED" -eq 0 ] && [ $# -gt 0 ]; do
  _arg_lc="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  case "$_arg_lc" in
    --install) ACTION=install ;;
    --reconfigure) ACTION=reconfigure ;;
    --upgrade) ACTION=upgrade ;;
    --uninstall) ACTION=uninstall ;;
    --status) ACTION=status ;;
    --client-config|--show) ACTION="client-config" ;;
    --mtu-config|--set-mtu) ACTION="mtu-config" ;;
    --start) ACTION=start ;;
    --stop) ACTION=stop ;;
    --restart) ACTION=restart ;;
    --users|--user-list) ACTION="user-list" ;;
    --user-add) ACTION="user-add" ;;
    --user-del|--user-delete)
      ACTION="user-del"
      USER_DEL_NAME="${2:-}"
      [ -n "$USER_DEL_NAME" ] || die "--user-del 需要用户名"
      shift
      ;;
    --user-show)
      ACTION="user-show"
      USER_SHOW_NAME="${2:-}"
      [ -n "$USER_SHOW_NAME" ] || die "--user-show 需要用户名"
      shift
      ;;
    --user-set-quota) ACTION="user-set-quota" ;;
    --user-set-expire) ACTION="user-set-expire" ;;
    --user-set-endpoint) ACTION="user-set-endpoint" ;;
    --user-enable)
      ACTION="user-enable"
      USER_SHOW_NAME="${2:-}"
      [ -n "$USER_SHOW_NAME" ] || die "--user-enable 需要用户名"
      shift
      ;;
    --user-disable)
      ACTION="user-disable"
      USER_SHOW_NAME="${2:-}"
      [ -n "$USER_SHOW_NAME" ] || die "--user-disable 需要用户名"
      shift
      ;;
    --user-scan) ACTION="user-scan" ;;
    --user-quota-reset) ACTION="user-quota-reset" ;;
    --user-set-rate|--user-set-bandwidth) ACTION="user-set-rate" ;;
    --rate-status|--tc-status) ACTION="rate-status" ;;
    --rate-restore|--tc-restore) ACTION="rate-restore" ;;
    --user-usage|--usage) ACTION="user-usage" ;;
    --user-export-clients)
      ACTION="user-export-clients"
      if [ -n "${2:-}" ] && [[ "${2}" != --* ]]; then
        MITA_CLIENT_EXPORT_DIR="${2}"
        shift
      fi
      ;;
    --doctor|--verify) ACTION=doctor ;;
    --perf) ACTION=perf ;;
    --profile-config) ACTION="profile-config" ;;
    --user-backup) ACTION="user-backup" ;;
    --user-restore)
      ACTION="user-restore"
      USER_RESTORE_FILE="${2:-}"
      [ -n "$USER_RESTORE_FILE" ] || die "--user-restore 需要备份文件路径"
      shift
      ;;
    --user-export)
      ACTION="user-export"
      if [ -n "${2:-}" ] && [[ "${2}" != --* ]]; then
        shift
      fi
      ;;
    --user-import)
      ACTION="user-import"
      USER_RESTORE_FILE="${2:-}"
      [ -n "$USER_RESTORE_FILE" ] || die "--user-import 需要文件路径"
      shift
      ;;
    install|upgrade|uninstall|status|reconfigure|client-config|show|mtu|mtu-config|set-mtu|profile|profile-config|perf|menu|start|stop|restart|配置|节点|users|user-list|user-add|user-del|user-delete|user-show|user-manage|user-set-endpoint|user-set-quota|user-set-expire|user-enable|user-disable|user-scan|user-quota-reset|user-set-rate|user-set-bandwidth|rate-status|rate-restore|tc-status|tc-restore|user-backup|user-restore|user-export|user-import|user-usage|usage|user-export-clients|doctor|verify|help)
      [ -z "$ACTION" ] && ACTION="$_arg_lc"
      [ "$_arg_lc" = show ] && ACTION="client-config"
      { [ "$_arg_lc" = mtu ] || [ "$_arg_lc" = set-mtu ]; } && ACTION="mtu-config"
      [ "$_arg_lc" = profile ] && ACTION="profile-config"
      [ "$_arg_lc" = menu ] && ACTION=""
      [ "$_arg_lc" = 配置 ] && ACTION="client-config"
      [ "$_arg_lc" = 节点 ] && ACTION="client-config"
      [ "$_arg_lc" = users ] && ACTION="user-list"
      [ "$_arg_lc" = user-delete ] && ACTION="user-del"
      [ "$_arg_lc" = user-manage ] && ACTION="user-manage"
      [ "$_arg_lc" = user-set-bandwidth ] && ACTION="user-set-rate"
      [ "$_arg_lc" = tc-status ] && ACTION="rate-status"
      [ "$_arg_lc" = tc-restore ] && ACTION="rate-restore"
      [ "$_arg_lc" = usage ] && ACTION="user-usage"
      [ "$_arg_lc" = verify ] && ACTION=doctor
      [ "$_arg_lc" = help ] && ACTION=help
      # 裸子命令后的位置参数：user-del bob / user-restore /path.json
      if [ -n "${2:-}" ] && [[ "${2}" != --* ]]; then
        case "$ACTION" in
          user-del)
            USER_DEL_NAME="${2}"
            shift
            ;;
          user-show|user-enable|user-disable)
            USER_SHOW_NAME="${2}"
            shift
            ;;
          user-restore|user-import)
            USER_RESTORE_FILE="${2}"
            shift
            ;;
          user-export)
            shift
            ;;
          user-export-clients)
            MITA_CLIENT_EXPORT_DIR="${2}"
            shift
            ;;
          mtu-config)
            MTU_REQUEST="${2}"
            MTU_CLI=1
            shift
            ;;
        esac
      fi
      ;;
    --yes|-y) YES=1 ;;
    --dry-run) DRY_RUN=1 ;;
    --port)
      PORT="${2:-}"
      PORT_CLI=1
      [ -n "$PORT" ] || die "--port 需要端口号"
      shift
      ;;
    --ingress-profile)
      INGRESS_PROFILE="${2:-}"
      INGRESS_PROFILE_CLI=1
      [ -n "$INGRESS_PROFILE" ] && [[ "$INGRESS_PROFILE" != --* ]] || die "--ingress-profile 需要入口配置 ID 或名称"
      shift
      ;;
    --port-range)
      PORT_RANGE="${2:-}"
      [ -n "$PORT_RANGE" ] || die "--port-range 需要端口段"
      shift
      ;;
    --protocol)
      PROTOCOL="${2:-}"
      PROTOCOL_CLI=1
      [ -n "$PROTOCOL" ] && [[ "$PROTOCOL" != --* ]] || die "--protocol 需要 TCP、UDP 或 BOTH"
      shift
      ;;
    --profile)
      PROFILE="${2:-}"
      PROFILE_CLI=1
      [ -n "$PROFILE" ] || die "--profile 需要 iplc、balanced、stealth 或 custom"
      shift
      ;;
    --advertise-host|--entry-ip)
      ADVERTISE_HOST="${2:-}"
      ADVERTISE_CLI=1
      ADVERTISE_AUTO_REQUESTED=0
      [ -n "$ADVERTISE_HOST" ] || die "--advertise-host 需要入口地址"
      shift
      ;;
    --advertise-port|--entry-port)
      ADVERTISE_PORT="${2:-}"
      ADVERTISE_CLI=1
      ADVERTISE_AUTO_REQUESTED=0
      [ -n "$ADVERTISE_PORT" ] || die "--advertise-port 需要入口端口"
      shift
      ;;
    --advertise-auto)
      ADVERTISE_HOST=""
      ADVERTISE_PORT=""
      ADVERTISE_CLI=1
      ADVERTISE_AUTO_REQUESTED=1
      ;;
    --mtu)
      MTU_REQUEST="${2:-}"
      MTU_CLI=1
      [ -n "$MTU_REQUEST" ] || die "--mtu 需要 safe、auto 或 1280-1500 的数值"
      shift
      ;;
    --traffic-pattern|--traffic)
      TRAFFIC_PATTERN="${2:-}"
      TRAFFIC_CLI=1
      [ -n "$TRAFFIC_PATTERN" ] && [[ "$TRAFFIC_PATTERN" != --* ]] \
        || die "--traffic-pattern 需要 off、conservative 或 aggressive"
      shift
      ;;
    --low-entropy)
      LOW_ENTROPY_MODE="${2:-}"
      LOW_ENTROPY_CLI=1
      [ -n "$LOW_ENTROPY_MODE" ] && [[ "$LOW_ENTROPY_MODE" != --* ]] \
        || die "--low-entropy 需要 off、56、48、40 或 32"
      shift
      ;;
    --multiplexing)
      MULTIPLEXING="${2:-}"
      MULTIPLEXING_CLI=1
      [ -n "$MULTIPLEXING" ] && [[ "$MULTIPLEXING" != --* ]] \
        || die "--multiplexing 需要 off、low、middle 或 high"
      shift
      ;;
    --handshake-mode|--handshake)
      HANDSHAKE_MODE="${2:-}"
      HANDSHAKE_CLI=1
      [ -n "$HANDSHAKE_MODE" ] && [[ "$HANDSHAKE_MODE" != --* ]] \
        || die "--handshake-mode 需要 no-wait 或 standard"
      shift
      ;;
    --mieru-channel)
      MIERU_CHANNEL="${2:-}"
      MIERU_CHANNEL_CLI=1
      [ -n "$MIERU_CHANNEL" ] || die "--mieru-channel 需要 stable 或 latest"
      shift
      ;;
    --mieru-version)
      MIERU_VERSION="${2:-}"
      MIERU_CHANNEL="pinned"
      MIERU_CHANNEL_CLI=1
      [ -n "$MIERU_VERSION" ] || die "--mieru-version 需要版本号"
      shift
      ;;
    --user)
      USERNAME="${2:-}"
      [ -n "$USERNAME" ] && [[ "$USERNAME" != --* ]] || die "--user 需要用户名"
      shift
      ;;
    --password)
      PASSWORD="${2:-}"
      PASSWORD_CLI=1
      [ -n "$PASSWORD" ] && [[ "$PASSWORD" != --* ]] || die "--password 需要值"
      shift
      ;;
    --package|--plan)
      USER_PACKAGE="${2:-}"
      [ -n "$USER_PACKAGE" ] && [[ "$USER_PACKAGE" != --* ]] || die "--package 需要套餐名"
      shift
      ;;
    --quota-mb|--quota)
      USER_QUOTA_MB="${2:-}"
      [ -n "$USER_QUOTA_MB" ] && [[ "$USER_QUOTA_MB" != --* ]] || die "--quota-mb 需要数值"
      shift
      ;;
    --quota-days)
      USER_QUOTA_DAYS="${2:-}"
      [ -n "$USER_QUOTA_DAYS" ] && [[ "$USER_QUOTA_DAYS" != --* ]] || die "--quota-days 需要数值"
      shift
      ;;
    --quota-mode)
      USER_QUOTA_MODE="${2:-}"
      [ -n "$USER_QUOTA_MODE" ] && [[ "$USER_QUOTA_MODE" != --* ]] || die "--quota-mode 需要 rolling 或 calendar"
      shift
      ;;
    --expire|--expires)
      USER_EXPIRE="${2:-}"
      [ -n "$USER_EXPIRE" ] && [[ "$USER_EXPIRE" != --* ]] || die "--expire 需要日期、+Nd 或 0"
      shift
      ;;
    --bandwidth|--rate|--mbps)
      USER_BANDWIDTH_MBPS="${2:-}"
      [ -n "$USER_BANDWIDTH_MBPS" ] && [[ "$USER_BANDWIDTH_MBPS" != --* ]] || die "--bandwidth 需要 Mbps 数值"
      shift
      ;;
    --op-user)
      OP_USER="${2:-}"
      [ -n "$OP_USER" ] && [[ "$OP_USER" != --* ]] || die "--op-user 需要 Linux 用户名"
      shift
      ;;
    --enable-bbr) ENABLE_BBR=1 ;;
    --lang)
      case "${2:-}" in
        en) LANG_ZH=0 ;;
        zh) LANG_ZH=1 ;;
        *) die "--lang 需要 zh 或 en" ;;
      esac
      shift
      ;;
    --help|-h) usage; exit 0 ;;
    --version)
      if [ "$LANG_ZH" -eq 1 ]; then
        printf '%s Mieru %s\n作者: %s\n' "$SCRIPT_NAME" "$SCRIPT_VERSION" "$SCRIPT_AUTHOR"
      else
        printf '%s Mieru %s\nAuthor: %s\n' "$SCRIPT_NAME" "$SCRIPT_VERSION" "$SCRIPT_AUTHOR"
      fi
      exit 0
      ;;
    *)
      if [[ "$1" == --* ]]; then
        die "未知参数：$1（使用 --help 查看帮助）"
      fi
      ;;
  esac
  shift
done
unset _arg_lc

run() {
  if [ "$DRY_RUN" -eq 1 ]; then
    local rendered=""
    printf -v rendered '%q ' "$@"
    t "[演练] ${rendered% }" "[dry-run] ${rendered% }"
  else
    "$@"
  fi
}

secure_stat_path() {
  local path="$1" expected_type="$2" uid mode
  [ "$expected_type" = dir ] && [ -d "$path" ] && [ ! -L "$path" ] || {
    [ "$expected_type" = file ] && [ -f "$path" ] && [ ! -L "$path" ] || return 1
  }
  uid="$(stat -c '%u' "$path" 2>/dev/null || true)"
  mode="$(stat -c '%a' "$path" 2>/dev/null || true)"
  [ "$uid" = 0 ] && [[ "$mode" =~ ^[0-7]{3,4}$ ]] || return 1
  [ "$((8#$mode & 8#022))" -eq 0 ]
}

state_file_is_secure() {
  local path="$1" parent
  parent="$(dirname "$path")"
  secure_stat_path "$parent" dir && secure_stat_path "$path" file
}

nb_schema_v3_file_valid() {
  local path="${1:-$NOBRAND_REGISTRY_FILE}"
  [ -f "$path" ] && [ ! -L "$path" ] || return 1
  if command -v jq >/dev/null 2>&1; then
    jq -e --argjson schema "$NOBRAND_SCHEMA_VERSION" '
      .schema_version == $schema
      and .project == "NoBrand-OneClick"
      and .ownership == "nobrand-v3"
    ' "$path" >/dev/null 2>&1
  elif command -v python3 >/dev/null 2>&1; then
    python3 - "$path" "$NOBRAND_SCHEMA_VERSION" <<'PY' >/dev/null 2>&1
import json, sys
doc = json.load(open(sys.argv[1], encoding="utf-8"))
raise SystemExit(0 if doc.get("schema_version") == int(sys.argv[2])
                 and doc.get("project") == "NoBrand-OneClick"
                 and doc.get("ownership") == "nobrand-v3" else 1)
PY
  else
    grep -Eq '"schema_version"[[:space:]]*:[[:space:]]*3([,}])' "$path" \
      && grep -Eq '"project"[[:space:]]*:[[:space:]]*"NoBrand-OneClick"' "$path" \
      && grep -Eq '"ownership"[[:space:]]*:[[:space:]]*"nobrand-v3"' "$path"
  fi
}

nb_test_mode_enabled() {
  [ "${MITA_SOURCE_ONLY:-0}" = 1 ] && [ "${NOBRAND_TEST_MODE:-0}" = 1 ]
}

nb_directory_empty() (
  local path="$1" entries
  [ -d "$path" ] && [ ! -L "$path" ] || return 1
  shopt -s dotglob nullglob
  entries=("$path"/*)
  [ "${#entries[@]}" -eq 0 ]
)

nb_directory_has_entries() {
  [ -d "$1" ] && ! nb_directory_empty "$1"
}

nb_installed_manager_version() {
  local path="${1:-$NOBRAND_INSTALL_SCRIPT_PATH}" version
  [ -f "$path" ] && [ ! -L "$path" ] || return 1
  nb_test_mode_enabled || state_file_is_secure "$path" || return 1
  grep -qxF 'SCRIPT_NAME="NoBrand-OneClick"' "$path" 2>/dev/null || return 1
  grep -qxF 'SCRIPT_REPO="ike-sh/NoBrand-OneClick"' "$path" 2>/dev/null || return 1
  version="$(sed -n 's/^SCRIPT_VERSION="\([0-9][0-9.]*\)"$/\1/p' "$path" | sed -n '1p')"
  [[ "$version" =~ ^[0-9]+[.][0-9]+[.][0-9]+$ ]] || return 1
  printf '%s' "$version"
}

nb_command_manager_version() {
  local path="$1" expected_target="$2" target resolved
  if [ -L "$path" ]; then
    target="$(readlink -- "$path" 2>/dev/null || true)"
    [ "$target" = "$expected_target" ] && [ -e "$path" ] || return 1
    resolved="$(readlink -f -- "$path" 2>/dev/null \
      || realpath "$path" 2>/dev/null || true)"
    [ -n "$resolved" ] || return 1
    nb_installed_manager_version "$resolved"
    return
  fi
  nb_installed_manager_version "$path"
}

nb_legacy_signature_version() {
  # Real pre-v3 releases wrote this exact state format below
  # /var/lib/mita-oneclick. Directory or package existence alone is not proof.
  local path="${NOBRAND_LEGACY_MIERU_STATE_DIR}/install-state.env"
  local port port_range protocol install_script range_start range_end key
  local legacy_install_script='/usr/local/bin/install-'mita
  [ -f "$path" ] && [ ! -L "$path" ] || return 1
  nb_test_mode_enabled || state_file_is_secure "$path" || return 1
  for key in INSTALL_METHOD PORT PORT_RANGE PROTOCOL INSTALL_SCRIPT; do
    [ "$(grep -c "^${key}=" "$path" 2>/dev/null || true)" -eq 1 ] || return 1
  done
  grep -qx 'INSTALL_METHOD=oneclick' "$path" 2>/dev/null || return 1
  port="$(sed -n 's/^PORT=//p' "$path")"
  port_range="$(sed -n 's/^PORT_RANGE=//p' "$path")"
  protocol="$(sed -n 's/^PROTOCOL=//p' "$path")"
  install_script="$(sed -n 's/^INSTALL_SCRIPT=//p' "$path")"
  case "$protocol" in TCP|UDP|BOTH) ;; *) return 1 ;; esac
  [ "$install_script" = "$legacy_install_script" ] || return 1
  if [ "$port_range" = "''" ]; then
    [[ "$port" =~ ^[0-9]{1,5}$ ]] || return 1
    [ "$((10#$port))" -ge 1 ] && [ "$((10#$port))" -le 65535 ] || return 1
  elif [ "$port" = "''" ]; then
    [[ "$port_range" =~ ^([0-9]{1,5})-([0-9]{1,5})$ ]] || return 1
    range_start="${BASH_REMATCH[1]}"
    range_end="${BASH_REMATCH[2]}"
    [ "$((10#$range_start))" -ge 1 ] \
      && [ "$((10#$range_end))" -le 65535 ] \
      && [ "$((10#$range_start))" -le "$((10#$range_end))" ] || return 1
  else
    return 1
  fi
  printf 'pre-v3 (INSTALL_METHOD=oneclick)'
}

nb_legacy_state_detected() {
  nb_legacy_signature_version >/dev/null 2>&1
}

nb_normalize_path() {
  local value="${1:-}" normalized="" parent="" base=""
  [ -n "$value" ] || return 1
  case "$value" in
    /*) ;;
    *) value="${PWD%/}/${value}" ;;
  esac
  # Refuse ambiguous lexical traversal when a platform lacks GNU -m support.
  # Lifecycle and destructive roots are expected to be canonical absolute paths.
  case "$value" in
    *'/../'*|*/..|*'/./'*|*/.) return 1 ;;
  esac
  if normalized="$(readlink -m -- "$value" 2>/dev/null)" \
     && [ -n "$normalized" ]; then
    printf '%s' "$normalized"
    return 0
  fi
  if normalized="$(realpath -m -- "$value" 2>/dev/null)" \
     && [ -n "$normalized" ]; then
    printf '%s' "$normalized"
    return 0
  fi

  # BusyBox has no readlink -m, and its realpath may emit partial output while
  # returning failure for unsupported flags. Resolve the nearest existing
  # ancestor instead, then append only the missing path components.
  while [ "$value" != / ] && [ "${value%/}" != "$value" ]; do
    value="${value%/}"
  done
  if [ -e "$value" ] || [ -L "$value" ]; then
    if normalized="$(readlink -f -- "$value" 2>/dev/null)" \
       && [ -n "$normalized" ]; then
      printf '%s' "$normalized"
      return 0
    fi
    if normalized="$(realpath "$value" 2>/dev/null)" \
       && [ -n "$normalized" ]; then
      printf '%s' "$normalized"
      return 0
    fi
    return 1
  fi
  base="${value##*/}"
  parent="${value%/*}"
  [ -n "$base" ] || return 1
  [ -n "$parent" ] || parent=/
  normalized="$(nb_normalize_path "$parent")" || return 1
  if [ "$normalized" = / ]; then
    printf '/%s' "$base"
  else
    printf '%s/%s' "$normalized" "$base"
  fi
}

nb_lifecycle_paths_valid() {
  local lifecycle state config lib tx_parent lock
  lifecycle="$(nb_normalize_path "$NOBRAND_LIFECYCLE_DIR")" || return 1
  state="$(nb_normalize_path "$NOBRAND_STATE_DIR")" || return 1
  config="$(nb_normalize_path "$NOBRAND_CONFIG_DIR")" || return 1
  lib="$(nb_normalize_path "$NOBRAND_LIB_DIR")" || return 1
  lock="$(nb_normalize_path "$NOBRAND_LIFECYCLE_LOCK_FILE")" || return 1
  case "$lifecycle" in
    /*/nobrand-oneclick-lifecycle) ;;
    *) return 1 ;;
  esac
  case "$lifecycle" in
    "$state"|"$state"/*|"$config"|"$config"/*|"$lib"|"$lib"/*) return 1 ;;
  esac
  case "$lock" in
    /run/nobrand-oneclick/lifecycle.lock|*/run/nobrand-oneclick/lifecycle.lock) ;;
    *) return 1 ;;
  esac
  case "$lock" in
    "$lifecycle"|"$lifecycle"/*|"$state"|"$state"/*|"$config"|"$config"/*|"$lib"|"$lib"/*)
      return 1
      ;;
  esac
  tx_parent="$(dirname "$NOBRAND_LIFECYCLE_TX_FILE")"
  tx_parent="$(nb_normalize_path "$tx_parent")" || return 1
  [ "$tx_parent" = "$lifecycle" ]
}

nb_lifecycle_field() {
  local key="$1" path="${2:-$NOBRAND_LIFECYCLE_TX_FILE}"
  awk -F= -v wanted="$key" '$1==wanted {print substr($0, length($1)+2); exit}' "$path" 2>/dev/null
}

nb_lifecycle_scope_valid() {
  local operation="$1" scope="$2"
  case "$operation:$scope" in
    install:manager|install:mieru|install:snell|install:hy2|install:tuic|\
      install:vless-reality|install:vless-sudoku|install:ssh-tunnel|install:forward|\
      repair:manager|repair:mieru|repair:global|configure:ingress|uninstall:global)
      return 0
      ;;
  esac
  return 1
}

nb_lifecycle_default_scope() {
  local operation="$1" phase="${2:-prepare}"
  case "$operation" in
    configure) printf 'ingress' ;;
    uninstall) printf 'global' ;;
    repair)
      case "$phase" in partial-uninstall-*) printf 'global' ;; *) printf 'mieru' ;; esac
      ;;
    install) printf 'mieru' ;;
    *) return 1 ;;
  esac
}

# Public v3.2.1 wrote lifecycle-v1 records before component scope existed.
# Its ordinary install/repair writer was Mieru-only; partial-uninstall repair
# and uninstall were global. Keep that exact compatibility boundary rather
# than guessing from protocol files or absence.
nb_lifecycle_v1_scope() {
  local operation="$1" phase="$2"
  case "$operation" in
    uninstall) printf 'global' ;;
    repair)
      case "$phase" in partial-uninstall-*) printf 'global' ;; *) printf 'mieru' ;; esac
      ;;
    install) printf 'mieru' ;;
    *) return 1 ;;
  esac
}

nb_lifecycle_scope() {
  local path="${1:-$NOBRAND_LIFECYCLE_TX_FILE}" format operation phase
  format="$(nb_lifecycle_field FORMAT "$path")"
  case "$format" in
    nobrand-lifecycle-v2) nb_lifecycle_field SCOPE "$path" ;;
    nobrand-lifecycle-v1)
      operation="$(nb_lifecycle_field OPERATION "$path")"
      phase="$(nb_lifecycle_field LAST_COMPLETED_PHASE "$path")"
      nb_lifecycle_v1_scope "$operation" "$phase"
      ;;
    *) return 1 ;;
  esac
}

nb_lifecycle_mutation_started() {
  local path="${1:-$NOBRAND_LIFECYCLE_TX_FILE}" format status
  format="$(nb_lifecycle_field FORMAT "$path")"
  case "$format" in
    nobrand-lifecycle-v2) nb_lifecycle_field MUTATION_STARTED "$path" ;;
    nobrand-lifecycle-v1)
      status="$(nb_lifecycle_field STATUS "$path")"
      [ "$status" = in-progress ] && printf '1' || printf '0'
      ;;
    *) return 1 ;;
  esac
}

nb_lifecycle_phase_valid() {
  local operation="$1" status="$2" phase="$3"
  if [ "$status" = complete ]; then
    case "$operation:$phase" in
      install:complete|repair:complete|configure:complete) return 0 ;;
      *) return 1 ;;
    esac
  fi
  [ "$status" = in-progress ] || return 1
  # Protocol installs persist a truncated SHA-256 of their authoritative
  # pre-callback state in this phase.  The 55 hex digits keep the phase within
  # the existing 64-byte field limit while retaining 220 bits of identity.
  if [ "$operation" = install ] \
     && [[ "$phase" =~ ^callback-[0-9a-f]{55}$ ]]; then
    return 0
  fi
  case "$operation:$phase" in
    install:prepare|install:state-layout|install:manager-ready|install:runtime-ready|\
      install:state-committed|install:ready-to-validate)
      return 0
      ;;
    repair:prepare|repair:state-layout|repair:runtime-ready|repair:state-committed|\
      repair:manager-ready|repair:ready-to-validate|repair:partial-uninstall-prepare|\
      repair:partial-uninstall-state-layout|repair:partial-uninstall-manager-ready|\
      repair:partial-uninstall-runtimes-reconciled|\
      repair:partial-uninstall-services-reconciled|\
      repair:partial-uninstall-ssh-confirmation-pending|\
      repair:partial-uninstall-state-validated|\
      repair:partial-uninstall-ready-to-validate)
      return 0
      ;;
    configure:prepare|configure:state-committed|configure:ready-to-validate)
      return 0
      ;;
    uninstall:prepare|uninstall:runtime-removed|uninstall:before-state-removal|\
      uninstall:state-removed|uninstall:before-config-removal|\
      uninstall:config-removed|uninstall:roots-removed|\
      uninstall:before-manager-removal|uninstall:manager-removed|\
      uninstall:before-final-validation)
      return 0
      ;;
  esac
  return 1
}

nb_lifecycle_tx_valid() {
  local path="$NOBRAND_LIFECYCLE_TX_FILE" format operation scope mutation_started
  local status manager schema txid started phase
  local mieru_owned preserve_package preserve_user preserve_group preserve_shared
  [ -f "$path" ] && [ ! -L "$path" ] || return 1
  nb_lifecycle_paths_valid || return 1
  if ! nb_test_mode_enabled; then
    secure_stat_path "$NOBRAND_LIFECYCLE_DIR" dir || return 1
    secure_stat_path "$path" file || return 1
  fi
  format="$(nb_lifecycle_field FORMAT "$path")"
  case "$format" in
    nobrand-lifecycle-v1)
      awk -F= '
        BEGIN {
          required["FORMAT"]=1; required["OPERATION"]=1; required["STATUS"]=1;
          required["MANAGER_VERSION"]=1; required["SCHEMA_GENERATION"]=1;
          required["TRANSACTION_ID"]=1; required["STARTED_AT"]=1;
          required["LAST_COMPLETED_PHASE"]=1; required["MIERU_OWNED"]=1;
          required["MIERU_PRESERVE_PACKAGE"]=1; required["MIERU_PRESERVE_USER"]=1;
          required["MIERU_PRESERVE_GROUP"]=1; required["MIERU_PRESERVE_SHARED"]=1
        }
        NF != 2 || !($1 in required) || seen[$1]++ { bad=1 }
        END {
          for (key in required) if (seen[key] != 1) bad=1
          exit bad ? 1 : 0
        }
      ' "$path" || return 1
      ;;
    nobrand-lifecycle-v2)
      awk -F= '
        BEGIN {
          required["FORMAT"]=1; required["OPERATION"]=1; required["SCOPE"]=1;
          required["MUTATION_STARTED"]=1; required["STATUS"]=1;
          required["MANAGER_VERSION"]=1; required["SCHEMA_GENERATION"]=1;
          required["TRANSACTION_ID"]=1; required["STARTED_AT"]=1;
          required["LAST_COMPLETED_PHASE"]=1; required["MIERU_OWNED"]=1;
          required["MIERU_PRESERVE_PACKAGE"]=1; required["MIERU_PRESERVE_USER"]=1;
          required["MIERU_PRESERVE_GROUP"]=1; required["MIERU_PRESERVE_SHARED"]=1
        }
        NF != 2 || !($1 in required) || seen[$1]++ { bad=1 }
        END {
          for (key in required) if (seen[key] != 1) bad=1
          exit bad ? 1 : 0
        }
      ' "$path" || return 1
      ;;
    *) return 1 ;;
  esac
  operation="$(nb_lifecycle_field OPERATION "$path")"
  scope="$(nb_lifecycle_scope "$path")" || return 1
  mutation_started="$(nb_lifecycle_mutation_started "$path")" || return 1
  status="$(nb_lifecycle_field STATUS "$path")"
  manager="$(nb_lifecycle_field MANAGER_VERSION "$path")"
  schema="$(nb_lifecycle_field SCHEMA_GENERATION "$path")"
  txid="$(nb_lifecycle_field TRANSACTION_ID "$path")"
  started="$(nb_lifecycle_field STARTED_AT "$path")"
  phase="$(nb_lifecycle_field LAST_COMPLETED_PHASE "$path")"
  mieru_owned="$(nb_lifecycle_field MIERU_OWNED "$path")"
  preserve_package="$(nb_lifecycle_field MIERU_PRESERVE_PACKAGE "$path")"
  preserve_user="$(nb_lifecycle_field MIERU_PRESERVE_USER "$path")"
  preserve_group="$(nb_lifecycle_field MIERU_PRESERVE_GROUP "$path")"
  preserve_shared="$(nb_lifecycle_field MIERU_PRESERVE_SHARED "$path")"
  case "$operation" in install|repair|configure|uninstall) ;; *) return 1 ;; esac
  [ "$format" != nobrand-lifecycle-v1 ] || {
    case "$operation" in install|repair|uninstall) ;; *) return 1 ;; esac
  }
  nb_lifecycle_scope_valid "$operation" "$scope" || return 1
  case "$mutation_started" in 0|1) ;; *) return 1 ;; esac
  case "$status" in in-progress|complete) ;; *) return 1 ;; esac
  [ "$operation:$status" != uninstall:complete ] || return 1
  case "$manager" in
    3.2.*) ;;
    *) return 1 ;;
  esac
  [ "$schema" = "$NOBRAND_SCHEMA_VERSION" ] || return 1
  [[ "$txid" =~ ^[A-Za-z0-9._-]{8,128}$ ]] || return 1
  [[ "$started" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] || return 1
  [[ "$phase" =~ ^[a-z0-9][a-z0-9._-]{0,63}$ ]] || return 1
  nb_lifecycle_phase_valid "$operation" "$status" "$phase" || return 1
  case "$mieru_owned:$preserve_package:$preserve_user:$preserve_group:$preserve_shared" in
    0:0:0:0:0|1:[01]:[01]:[01]:[01]) ;;
    *) return 1 ;;
  esac
  [ "$operation:$scope" = uninstall:global ] \
    || [ "$mieru_owned:$preserve_package:$preserve_user:$preserve_group:$preserve_shared" = 0:0:0:0:0 ]
}

nb_lifecycle_prepare_dir() {
  nb_lifecycle_paths_valid || {
    die "$(t '生命周期目录不安全，拒绝继续' 'Unsafe lifecycle directory; refusing to continue')" || return 1
    return 1
  }
  if [ -e "$NOBRAND_LIFECYCLE_DIR" ]; then
    [ -d "$NOBRAND_LIFECYCLE_DIR" ] && [ ! -L "$NOBRAND_LIFECYCLE_DIR" ] || return 1
    nb_test_mode_enabled || secure_stat_path "$NOBRAND_LIFECYCLE_DIR" dir || return 1
  else
    mkdir -p "$NOBRAND_LIFECYCLE_DIR" || return 1
    chmod 0700 "$NOBRAND_LIFECYCLE_DIR" || return 1
    chown root:root "$NOBRAND_LIFECYCLE_DIR" 2>/dev/null || true
  fi
}

nb_lifecycle_random_id() {
  local value=""
  if [ -r /dev/urandom ] && command -v od >/dev/null 2>&1; then
    value="$(od -An -N16 -tx1 /dev/urandom 2>/dev/null | tr -d '[:space:]')"
  fi
  [ -n "$value" ] || value="tx-$${RANDOM}${RANDOM}$(date -u +%s 2>/dev/null || printf 0)"
  printf '%s' "$value"
}

nb_lifecycle_write() {
  local operation="$1" status="$2" txid="$3" started="$4" phase="$5" tmp
  local mieru_owned="${6:-0}" preserve_package="${7:-0}" preserve_user="${8:-0}"
  local preserve_group="${9:-0}" preserve_shared="${10:-0}"
  local scope="${11:-}" mutation_started="${12:-0}"
  [ -n "$scope" ] || scope="$(nb_lifecycle_default_scope "$operation" "$phase")" || return 1
  case "$operation" in install|repair|configure|uninstall) ;; *) return 1 ;; esac
  nb_lifecycle_scope_valid "$operation" "$scope" || return 1
  case "$mutation_started" in 0|1) ;; *) return 1 ;; esac
  case "$status" in in-progress|complete) ;; *) return 1 ;; esac
  [[ "$txid" =~ ^[A-Za-z0-9._-]{8,128}$ ]] || return 1
  [[ "$started" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] || return 1
  [[ "$phase" =~ ^[a-z0-9][a-z0-9._-]{0,63}$ ]] || return 1
  nb_lifecycle_phase_valid "$operation" "$status" "$phase" || return 1
  case "$mieru_owned:$preserve_package:$preserve_user:$preserve_group:$preserve_shared" in
    0:0:0:0:0|1:[01]:[01]:[01]:[01]) ;;
    *) return 1 ;;
  esac
  [ "$operation:$scope" = uninstall:global ] \
    || [ "$mieru_owned:$preserve_package:$preserve_user:$preserve_group:$preserve_shared" = 0:0:0:0:0 ] \
    || return 1
  nb_lifecycle_prepare_dir || return 1
  tmp="$(mktemp "${NOBRAND_LIFECYCLE_DIR}/.transaction.XXXXXX")" || return 1
  if ! printf '%s\n' \
      'FORMAT=nobrand-lifecycle-v2' \
      "OPERATION=${operation}" \
      "SCOPE=${scope}" \
      "MUTATION_STARTED=${mutation_started}" \
      "STATUS=${status}" \
      "MANAGER_VERSION=${SCRIPT_VERSION}" \
      "SCHEMA_GENERATION=${NOBRAND_SCHEMA_VERSION}" \
      "TRANSACTION_ID=${txid}" \
      "STARTED_AT=${started}" \
      "LAST_COMPLETED_PHASE=${phase}" \
      "MIERU_OWNED=${mieru_owned}" \
      "MIERU_PRESERVE_PACKAGE=${preserve_package}" \
      "MIERU_PRESERVE_USER=${preserve_user}" \
      "MIERU_PRESERVE_GROUP=${preserve_group}" \
      "MIERU_PRESERVE_SHARED=${preserve_shared}" >"$tmp" \
    || ! chmod 0600 "$tmp"; then
    rm -f "$tmp"
    return 1
  fi
  chown root:root "$tmp" 2>/dev/null || true
  if ! mv -f "$tmp" "$NOBRAND_LIFECYCLE_TX_FILE"; then
    rm -f "$tmp"
    return 1
  fi
}

nb_lifecycle_begin() {
  local operation="$1" phase="${2:-prepare}" txid="" started=""
  local mieru_owned="${3:-0}" preserve_package="${4:-0}" preserve_user="${5:-0}"
  local preserve_group="${6:-0}" preserve_shared="${7:-0}" allow_transition="${8:-0}"
  local scope="${9:-}" existing_operation="" existing_scope="" mutation_started=0
  [ -n "$scope" ] || scope="$(nb_lifecycle_default_scope "$operation" "$phase")" || return 1
  nb_lifecycle_scope_valid "$operation" "$scope" || return 1
  [ "${DRY_RUN:-0}" -eq 0 ] || {
    NOBRAND_LIFECYCLE_OPERATION="$operation"
    NOBRAND_LIFECYCLE_SCOPE="$scope"
    NOBRAND_LIFECYCLE_ACTIVE=1
    NOBRAND_LIFECYCLE_MUTATION_STARTED=0
    return 0
  }
  if ! nb_test_mode_enabled && [ "$(id -u 2>/dev/null || printf 1)" -ne 0 ]; then
    return 1
  fi
  if nb_lifecycle_tx_valid && [ "$(nb_lifecycle_field STATUS)" = in-progress ]; then
    existing_operation="$(nb_lifecycle_field OPERATION)"
    existing_scope="$(nb_lifecycle_scope)" || return 1
    if [ "$existing_operation:$existing_scope" != "$operation:$scope" ]; then
      if [ "$allow_transition:$existing_operation:$existing_scope:$operation:$scope" = 1:uninstall:global:repair:global ]; then
        txid="$(nb_lifecycle_random_id)"
        started="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        mieru_owned=0
        preserve_package=0
        preserve_user=0
        preserve_group=0
        preserve_shared=0
      else
        warn "$(t "未完成的 ${existing_operation}:${existing_scope} 生命周期事务仍在进行，拒绝以 ${operation}:${scope} 覆盖" \
          "An unfinished ${existing_operation}:${existing_scope} lifecycle transaction is active; refusing to replace it with ${operation}:${scope}")"
        return 1
      fi
    else
      txid="$(nb_lifecycle_field TRANSACTION_ID)"
      started="$(nb_lifecycle_field STARTED_AT)"
      mieru_owned="$(nb_lifecycle_field MIERU_OWNED)"
      preserve_package="$(nb_lifecycle_field MIERU_PRESERVE_PACKAGE)"
      preserve_user="$(nb_lifecycle_field MIERU_PRESERVE_USER)"
      preserve_group="$(nb_lifecycle_field MIERU_PRESERVE_GROUP)"
      preserve_shared="$(nb_lifecycle_field MIERU_PRESERVE_SHARED)"
      mutation_started="$(nb_lifecycle_mutation_started)" || return 1
    fi
  else
    txid="$(nb_lifecycle_random_id)"
    started="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  fi
  NOBRAND_LIFECYCLE_OPERATION="$operation"
  NOBRAND_LIFECYCLE_SCOPE="$scope"
  NOBRAND_LIFECYCLE_ACTIVE=1
  NOBRAND_LIFECYCLE_MUTATION_STARTED="$mutation_started"
  if ! nb_lifecycle_write "$operation" in-progress "$txid" "$started" "$phase" \
      "$mieru_owned" "$preserve_package" "$preserve_user" "$preserve_group" \
      "$preserve_shared" "$scope" "$mutation_started"; then
    NOBRAND_LIFECYCLE_ACTIVE=0
    NOBRAND_LIFECYCLE_OPERATION=""
    NOBRAND_LIFECYCLE_SCOPE=""
    NOBRAND_LIFECYCLE_MUTATION_STARTED=0
    return 1
  fi
}

nb_lifecycle_mark_phase() {
  local phase="$1" operation txid started status mieru_owned preserve_package
  local preserve_user preserve_group preserve_shared scope mutation_started
  [ "${DRY_RUN:-0}" -eq 0 ] || return 0
  nb_lifecycle_tx_valid || return 1
  operation="$(nb_lifecycle_field OPERATION)"
  status="$(nb_lifecycle_field STATUS)"
  txid="$(nb_lifecycle_field TRANSACTION_ID)"
  started="$(nb_lifecycle_field STARTED_AT)"
  mieru_owned="$(nb_lifecycle_field MIERU_OWNED)"
  preserve_package="$(nb_lifecycle_field MIERU_PRESERVE_PACKAGE)"
  preserve_user="$(nb_lifecycle_field MIERU_PRESERVE_USER)"
  preserve_group="$(nb_lifecycle_field MIERU_PRESERVE_GROUP)"
  preserve_shared="$(nb_lifecycle_field MIERU_PRESERVE_SHARED)"
  scope="$(nb_lifecycle_scope)" || return 1
  mutation_started="$(nb_lifecycle_mutation_started)" || return 1
  [ "$status" = in-progress ] || return 1
  nb_lifecycle_write "$operation" in-progress "$txid" "$started" "$phase" \
    "$mieru_owned" "$preserve_package" "$preserve_user" "$preserve_group" \
    "$preserve_shared" "$scope" "$mutation_started"
}

# A fresh component action can temporarily replace a completed lifecycle
# record before it reaches its first durable component mutation. Keep that
# closed-schema record in memory only so validation failures, cancellation, or
# a handled signal can restore it exactly. Lifecycle records contain no node
# credentials; protocol request values are deliberately never captured here.
nb_lifecycle_pre_mutation_snapshot() {
  local record=""
  NOBRAND_LIFECYCLE_PREMUTATION_ARMED=1
  NOBRAND_LIFECYCLE_PREMUTATION_PRIOR_PRESENT=0
  NOBRAND_LIFECYCLE_PREMUTATION_PRIOR_RECORD=""
  [ "${DRY_RUN:-0}" -eq 0 ] || return 0
  if nb_lifecycle_tx_valid; then
    record="$(<"$NOBRAND_LIFECYCLE_TX_FILE")" || {
      nb_lifecycle_pre_mutation_disarm
      return 1
    }
    [ -n "$record" ] || {
      nb_lifecycle_pre_mutation_disarm
      return 1
    }
    NOBRAND_LIFECYCLE_PREMUTATION_PRIOR_PRESENT=1
    NOBRAND_LIFECYCLE_PREMUTATION_PRIOR_RECORD="$record"
  fi
}

nb_lifecycle_pre_mutation_disarm() {
  NOBRAND_LIFECYCLE_PREMUTATION_ARMED=0
  NOBRAND_LIFECYCLE_PREMUTATION_PRIOR_PRESENT=0
  NOBRAND_LIFECYCLE_PREMUTATION_PRIOR_RECORD=""
}

nb_lifecycle_restore_pre_mutation() {
  local tmp=""
  if [ "${NOBRAND_LIFECYCLE_PREMUTATION_ARMED:-0}" -eq 1 ] \
     && [ "${NOBRAND_LIFECYCLE_PREMUTATION_PRIOR_PRESENT:-0}" -eq 1 ]; then
    nb_lifecycle_prepare_dir || return 1
    tmp="$(mktemp "${NOBRAND_LIFECYCLE_DIR}/.transaction.XXXXXX")" || return 1
    if ! printf '%s\n' "$NOBRAND_LIFECYCLE_PREMUTATION_PRIOR_RECORD" >"$tmp" \
       || ! chmod 0600 "$tmp"; then
      rm -f "$tmp"
      return 1
    fi
    chown root:root "$tmp" 2>/dev/null || true
    if ! mv -f "$tmp" "$NOBRAND_LIFECYCLE_TX_FILE"; then
      rm -f "$tmp"
      return 1
    fi
  else
    nb_lifecycle_clear || return 1
  fi
  NOBRAND_LIFECYCLE_ACTIVE=0
  NOBRAND_LIFECYCLE_OPERATION=""
  NOBRAND_LIFECYCLE_SCOPE=""
  NOBRAND_LIFECYCLE_MUTATION_STARTED=0
  nb_lifecycle_pre_mutation_disarm
}

nb_lifecycle_mark_mutation_started() {
  local operation txid started phase status mieru_owned preserve_package
  local preserve_user preserve_group preserve_shared scope
  [ "${DRY_RUN:-0}" -eq 0 ] || {
    NOBRAND_LIFECYCLE_MUTATION_STARTED=1
    return 0
  }
  nb_lifecycle_tx_valid || return 1
  operation="$(nb_lifecycle_field OPERATION)"
  status="$(nb_lifecycle_field STATUS)"
  txid="$(nb_lifecycle_field TRANSACTION_ID)"
  started="$(nb_lifecycle_field STARTED_AT)"
  phase="$(nb_lifecycle_field LAST_COMPLETED_PHASE)"
  mieru_owned="$(nb_lifecycle_field MIERU_OWNED)"
  preserve_package="$(nb_lifecycle_field MIERU_PRESERVE_PACKAGE)"
  preserve_user="$(nb_lifecycle_field MIERU_PRESERVE_USER)"
  preserve_group="$(nb_lifecycle_field MIERU_PRESERVE_GROUP)"
  preserve_shared="$(nb_lifecycle_field MIERU_PRESERVE_SHARED)"
  scope="$(nb_lifecycle_scope)" || return 1
  [ "$status" = in-progress ] || return 1
  nb_lifecycle_write "$operation" in-progress "$txid" "$started" "$phase" \
    "$mieru_owned" "$preserve_package" "$preserve_user" "$preserve_group" \
    "$preserve_shared" "$scope" 1 || return 1
  NOBRAND_LIFECYCLE_MUTATION_STARTED=1
  nb_lifecycle_pre_mutation_disarm
}

# Protocol installers collect and validate their requests inside the callback
# run by the lifecycle wrapper.  Marking in the wrapper is therefore too early:
# an invalid answer or cancellation would be recorded as a partial install.
# Installers call this immediately before their first durable protocol change.
# Direct module invocations do not own a manager lifecycle and remain no-ops.
nb_lifecycle_mark_protocol_mutation_started() {
  local scope="$1"
  # Module helpers can also be reached by non-lifecycle maintenance actions in
  # or outside a manager process. Only an active scoped transaction turns this
  # into a required lifecycle write; otherwise the hook is deliberately a no-op.
  [ "${NOBRAND_LIFECYCLE_ACTIVE:-0}" -eq 1 ] || return 0
  [ "${NOBRAND_LIFECYCLE_SCOPE:-}" = "$scope" ] || return 1
  case "${NOBRAND_LIFECYCLE_OPERATION:-}" in install|repair) ;; *) return 1 ;; esac
  nb_lifecycle_tx_valid \
    && [ "$(nb_lifecycle_field STATUS)" = in-progress ] \
    && [ "$(nb_lifecycle_scope)" = "$scope" ] || return 1
  case "$(nb_lifecycle_field OPERATION)" in install|repair) ;; *) return 1 ;; esac
  nb_lifecycle_mark_mutation_started || return 1
  # This proof is intentionally process-local. A prior interrupted attempt may
  # already have MUTATION_STARTED=1; recovery may advance past its callback
  # fingerprint only when this invocation reached its own mutation boundary.
  NOBRAND_PROTOCOL_CALLBACK_ATTEMPT_MUTATION=1
}

nb_lifecycle_complete() {
  local operation="$1" txid started mieru_owned preserve_package preserve_user
  local preserve_group preserve_shared scope mutation_started
  [ "${NOBRAND_LIFECYCLE_ACTIVE:-0}" -eq 1 ] || return 0
  if [ "${DRY_RUN:-0}" -eq 1 ]; then
    NOBRAND_LIFECYCLE_ACTIVE=0
    NOBRAND_LIFECYCLE_MUTATION_STARTED=0
    return 0
  fi
  nb_lifecycle_tx_valid || return 1
  [ "$(nb_lifecycle_field OPERATION)" = "$operation" ] || return 1
  txid="$(nb_lifecycle_field TRANSACTION_ID)"
  started="$(nb_lifecycle_field STARTED_AT)"
  mieru_owned="$(nb_lifecycle_field MIERU_OWNED)"
  preserve_package="$(nb_lifecycle_field MIERU_PRESERVE_PACKAGE)"
  preserve_user="$(nb_lifecycle_field MIERU_PRESERVE_USER)"
  preserve_group="$(nb_lifecycle_field MIERU_PRESERVE_GROUP)"
  preserve_shared="$(nb_lifecycle_field MIERU_PRESERVE_SHARED)"
  scope="$(nb_lifecycle_scope)" || return 1
  mutation_started="$(nb_lifecycle_mutation_started)" || return 1
  nb_lifecycle_write "$operation" complete "$txid" "$started" complete \
    "$mieru_owned" "$preserve_package" "$preserve_user" "$preserve_group" \
    "$preserve_shared" "$scope" "$mutation_started" || return 1
  NOBRAND_LIFECYCLE_ACTIVE=0
  NOBRAND_LIFECYCLE_MUTATION_STARTED=0
  nb_lifecycle_pre_mutation_disarm
}

nb_lifecycle_clear() {
  if [ "${DRY_RUN:-0}" -eq 0 ]; then
    rm -f "$NOBRAND_LIFECYCLE_TX_FILE" || return 1
    rmdir "$NOBRAND_LIFECYCLE_DIR" 2>/dev/null || true
  fi
  NOBRAND_LIFECYCLE_ACTIVE=0
  NOBRAND_LIFECYCLE_OPERATION=""
  NOBRAND_LIFECYCLE_SCOPE=""
  NOBRAND_LIFECYCLE_MUTATION_STARTED=0
  nb_lifecycle_pre_mutation_disarm
}

nb_lifecycle_lock_acquire() {
  local lock_parent lock_root parent_mode path_identity fd_identity
  if [ "${DRY_RUN:-0}" -eq 1 ]; then
    NOBRAND_LIFECYCLE_LOCK_HELD=$((NOBRAND_LIFECYCLE_LOCK_HELD + 1))
    return 0
  fi
  if [ "${NOBRAND_LIFECYCLE_LOCK_HELD:-0}" -gt 0 ]; then
    NOBRAND_LIFECYCLE_LOCK_HELD=$((NOBRAND_LIFECYCLE_LOCK_HELD + 1))
    return 0
  fi
  command -v flock >/dev/null 2>&1 || {
    die "$(t '缺少 flock，无法安全执行安装、修复或卸载' \
      'flock is required for safe install, repair, or uninstall')" || return 1
    return 1
  }
  nb_lifecycle_paths_valid || return 1
  lock_parent="$(dirname "$NOBRAND_LIFECYCLE_LOCK_FILE")"
  lock_root="$(dirname "$lock_parent")"
  if [ -e "$lock_parent" ] || [ -L "$lock_parent" ]; then
    [ -d "$lock_parent" ] && [ ! -L "$lock_parent" ] || return 1
  else
    [ -d "$lock_root" ] && [ ! -L "$lock_root" ] || return 1
    mkdir "$lock_parent" || return 1
    chmod 0700 "$lock_parent" || return 1
    chown root:root "$lock_parent" 2>/dev/null || true
  fi
  if ! nb_test_mode_enabled; then
    secure_stat_path "$lock_parent" dir || return 1
  fi
  parent_mode="$(stat -c '%a' "$lock_parent" 2>/dev/null || true)"
  [ "$parent_mode" = 700 ] || return 1
  if [ -e "$NOBRAND_LIFECYCLE_LOCK_FILE" ] || [ -L "$NOBRAND_LIFECYCLE_LOCK_FILE" ]; then
    [ -f "$NOBRAND_LIFECYCLE_LOCK_FILE" ] && [ ! -L "$NOBRAND_LIFECYCLE_LOCK_FILE" ] || return 1
    nb_test_mode_enabled || secure_stat_path "$NOBRAND_LIFECYCLE_LOCK_FILE" file || return 1
  fi
  exec 7>>"$NOBRAND_LIFECYCLE_LOCK_FILE" || return 1
  chmod 0600 "$NOBRAND_LIFECYCLE_LOCK_FILE" || { exec 7>&-; return 1; }
  chown root:root "$NOBRAND_LIFECYCLE_LOCK_FILE" 2>/dev/null || true
  path_identity="$(stat -c '%d:%i' "$NOBRAND_LIFECYCLE_LOCK_FILE" 2>/dev/null || true)"
  fd_identity="$(stat -Lc '%d:%i' /proc/self/fd/7 2>/dev/null || true)"
  [ -n "$path_identity" ] && [ "$path_identity" = "$fd_identity" ] \
    || { exec 7>&-; return 1; }
  nb_test_mode_enabled || secure_stat_path "$NOBRAND_LIFECYCLE_LOCK_FILE" file \
    || { exec 7>&-; return 1; }
  if ! flock -n 7; then
    exec 7>&-
    die "$(t '检测到另一项 NoBrand 安装、修复或卸载任务正在运行，请稍后重试。' \
      'Another NoBrand install, repair, or uninstall operation is running; try again later.')" || return 1
    return 1
  fi
  NOBRAND_LIFECYCLE_LOCK_HELD=1
}

nb_lifecycle_lock_release() {
  [ "${NOBRAND_LIFECYCLE_LOCK_HELD:-0}" -gt 0 ] || return 0
  NOBRAND_LIFECYCLE_LOCK_HELD=$((NOBRAND_LIFECYCLE_LOCK_HELD - 1))
  [ "${DRY_RUN:-0}" -eq 0 ] || return 0
  if [ "$NOBRAND_LIFECYCLE_LOCK_HELD" -eq 0 ]; then
    flock -u 7 2>/dev/null || true
    exec 7>&-
  fi
}

nb_lifecycle_lock_release_all() {
  local floor="${1:-0}" rc=0
  case "$floor" in ''|*[!0-9]*) floor=0 ;; esac
  while [ "${NOBRAND_LIFECYCLE_LOCK_HELD:-0}" -gt "$floor" ]; do
    if ! nb_lifecycle_lock_release; then
      rc=1
      break
    fi
  done
  return "$rc"
}

nb_lifecycle_signal_exit() {
  local signal="$1" exit_status=1 lifecycle_in_progress=0 mutation_started=0
  # Never invoke the generic ERR handler or recursively re-enter this handler.
  trap - ERR HUP INT TERM
  case "$signal" in
    HUP) exit_status=129 ;;
    INT) exit_status=130 ;;
    TERM) exit_status=143 ;;
  esac
  if [ "${NOBRAND_LIFECYCLE_ACTIVE:-0}" -eq 1 ] && nb_lifecycle_tx_valid \
     && [ "$(nb_lifecycle_field STATUS)" = in-progress ]; then
    lifecycle_in_progress=1
    mutation_started="$(nb_lifecycle_mutation_started 2>/dev/null || printf 1)"
  fi
  if [ "$lifecycle_in_progress" -eq 1 ] && [ "$mutation_started" = 0 ]; then
    nb_lifecycle_restore_pre_mutation >/dev/null 2>&1 || true
    warn "$(t '生命周期操作在写入变更前被中断；临时恢复信息已清除。' \
      'The lifecycle operation was interrupted before mutation; temporary recovery metadata was cleared.')" \
      || true
  elif [ "$lifecycle_in_progress" -eq 1 ]; then
    warn "$(t '生命周期操作被信号中断；已保留带组件范围的恢复信息，请重新运行以安全继续。' \
      'The lifecycle operation was interrupted; scoped recovery metadata was preserved. Run it again to continue safely.')" \
      || true
  fi
  # Menu callbacks run in a subshell that inherits the parent's fd 7 open-file
  # description.  Releasing below the inherited count there would unlock the
  # parent's guard as well, so child handlers set a floor before doing work.
  nb_lifecycle_lock_release_all "${NOBRAND_LIFECYCLE_LOCK_FLOOR:-0}" >/dev/null 2>&1 || true
  exit "$exit_status"
}

nb_lifecycle_signal_handlers_install() {
  trap 'nb_lifecycle_signal_exit HUP' HUP
  trap 'nb_lifecycle_signal_exit INT' INT
  trap 'nb_lifecycle_signal_exit TERM' TERM
}

nb_lifecycle_checkpoint() {
  local operation="$1" phase="$2" mutation_started="${3:-}" requested=""
  nb_lifecycle_mark_phase "$phase" || return 1
  if [ "$mutation_started" = 1 ]; then
    nb_lifecycle_mark_mutation_started || return 1
  fi
  nb_test_mode_enabled || return 0
  case "$operation" in
    install) requested="${NOBRAND_TEST_INTERRUPT_INSTALL_AT:-}" ;;
    repair) requested="${NOBRAND_TEST_INTERRUPT_REPAIR_AT:-}" ;;
    configure) requested="${NOBRAND_TEST_INTERRUPT_CONFIGURE_AT:-}" ;;
    uninstall) requested="${NOBRAND_TEST_INTERRUPT_UNINSTALL_AT:-}" ;;
    *) return 1 ;;
  esac
  [ "$requested" != "$phase" ] || return 75
}

nb_classify_installation_state() {
  local operation manager_version="" canonical_manager_version="" command_version="" root
  local lifecycle_valid=0 schema_valid=0 current_evidence=0 backup_restore_valid=0
  local command_path expected_target manager_command_valid=0 short_command_valid=0
  if { [ -e "$NOBRAND_LIFECYCLE_TX_FILE" ] || [ -L "$NOBRAND_LIFECYCLE_TX_FILE" ]; } \
     && ! nb_lifecycle_tx_valid; then
    printf 'AMBIGUOUS_OR_FOREIGN'
    return 0
  fi
  if declare -F nobrand_backup_restore_transaction_present >/dev/null 2>&1 \
     && nobrand_backup_restore_transaction_present; then
    if ! nobrand_backup_restore_transaction_valid; then
      printf 'AMBIGUOUS_OR_FOREIGN'
      return 0
    fi
    backup_restore_valid=1
  fi
  for root in "$NOBRAND_STATE_DIR" "$NOBRAND_CONFIG_DIR" "$NOBRAND_LIB_DIR"; do
    if { [ -e "$root" ] || [ -L "$root" ]; } \
       && { [ ! -d "$root" ] || [ -L "$root" ]; }; then
      printf 'AMBIGUOUS_OR_FOREIGN'
      return 0
    fi
    if [ -d "$root" ] && ! nb_test_mode_enabled && ! secure_stat_path "$root" dir; then
      printf 'AMBIGUOUS_OR_FOREIGN'
      return 0
    fi
  done
  if { [ -e "$NOBRAND_REGISTRY_FILE" ] || [ -L "$NOBRAND_REGISTRY_FILE" ]; } \
     && ! nb_schema_v3_file_valid; then
    printf 'AMBIGUOUS_OR_FOREIGN'
    return 0
  fi
  if nb_lifecycle_tx_valid; then
    lifecycle_valid=1
    current_evidence=1
  fi
  if nb_schema_v3_file_valid; then
    schema_valid=1
    current_evidence=1
  fi
  canonical_manager_version="$(nb_installed_manager_version 2>/dev/null || true)"
  if { [ -e "$NOBRAND_INSTALL_SCRIPT_PATH" ] || [ -L "$NOBRAND_INSTALL_SCRIPT_PATH" ]; } \
     && [ -z "$canonical_manager_version" ]; then
    printf 'AMBIGUOUS_OR_FOREIGN'
    return 0
  fi
  if [ -n "$canonical_manager_version" ]; then
    manager_version="$canonical_manager_version"
    current_evidence=1
  fi
  for command_path in "$NOBRAND_COMMAND_PATH" "$NOBRAND_SHORT_COMMAND_PATH"; do
    [ "$command_path" = "$NOBRAND_COMMAND_PATH" ] \
      && expected_target="$NOBRAND_INSTALL_SCRIPT_PATH" \
      || expected_target="$NOBRAND_COMMAND_PATH"
    if [ -e "$command_path" ] || [ -L "$command_path" ]; then
      command_version="$(nb_command_manager_version "$command_path" "$expected_target" 2>/dev/null)" || {
        printf 'AMBIGUOUS_OR_FOREIGN'
        return 0
      }
      if [ -n "$manager_version" ] && [ "$manager_version" != "$command_version" ]; then
        printf 'AMBIGUOUS_OR_FOREIGN'
        return 0
      fi
      manager_version="$command_version"
      current_evidence=1
      if [ -L "$command_path" ]; then
        if [ "$command_path" = "$NOBRAND_COMMAND_PATH" ]; then
          manager_command_valid=1
        else
          short_command_valid=1
        fi
      fi
    fi
  done
  if [ "$lifecycle_valid" -eq 1 ]; then
    case "$manager_version" in
      ''|3.2.*) ;;
      3.0.*|3.1.*) printf 'LEGACY_UNSUPPORTED'; return 0 ;;
      *) printf 'AMBIGUOUS_OR_FOREIGN'; return 0 ;;
    esac
  fi
  if nb_legacy_state_detected; then
    if [ "$current_evidence" -eq 1 ]; then
      printf 'AMBIGUOUS_OR_FOREIGN'
    else
      printf 'LEGACY_UNSUPPORTED'
    fi
    return 0
  fi
  if [ -d "$NOBRAND_LEGACY_MIERU_STATE_DIR" ] \
     && nb_directory_has_entries "$NOBRAND_LEGACY_MIERU_STATE_DIR"; then
    printf 'AMBIGUOUS_OR_FOREIGN'
    return 0
  fi
  if [ "$backup_restore_valid" -eq 1 ]; then
    if [ "$lifecycle_valid" -eq 1 ] \
       && [ "$(nb_lifecycle_field STATUS)" = in-progress ] \
       && [ "$(nb_lifecycle_field OPERATION)" != repair ]; then
      printf 'AMBIGUOUS_OR_FOREIGN'
    elif [ "$schema_valid" -eq 1 ] || [[ "$manager_version" == 3.2.* ]]; then
      printf 'CURRENT_PARTIAL_REPAIR'
    else
      printf 'AMBIGUOUS_OR_FOREIGN'
    fi
    return 0
  fi
  if [ "$lifecycle_valid" -eq 1 ] && [ "$(nb_lifecycle_field STATUS)" = in-progress ]; then
    operation="$(nb_lifecycle_field OPERATION)"
    case "$operation" in
      install) printf 'CURRENT_PARTIAL_INSTALL' ;;
      repair) printf 'CURRENT_PARTIAL_REPAIR' ;;
      configure) printf 'CURRENT_PARTIAL_CONFIGURE' ;;
      uninstall) printf 'CURRENT_PARTIAL_UNINSTALL' ;;
    esac
    return 0
  fi
  if [ "$lifecycle_valid" -eq 1 ] && [ "$(nb_lifecycle_field STATUS)" = complete ] \
     && [ "$schema_valid" -ne 1 ] && [ -z "$manager_version" ]; then
    # A completed transaction is positive current evidence, not proof of a
    # pristine host. With neither schema nor manager identity to reconcile, the
    # completion record is inconsistent and must fail closed. A surviving valid
    # schema can still take the ordinary safe partial-install repair path below.
    printf 'AMBIGUOUS_OR_FOREIGN'
    return 0
  fi
  if [ "$schema_valid" -eq 1 ]; then
    case "$manager_version" in
      3.0.*|3.1.*) printf 'LEGACY_UNSUPPORTED' ;;
      3.2.*)
        if [ -n "$canonical_manager_version" ] \
           && [ "$manager_command_valid" -eq 1 ] \
           && [ "$short_command_valid" -eq 1 ]; then
          printf 'CURRENT_COMPLETE'
        else
          printf 'CURRENT_PARTIAL_INSTALL'
        fi
        ;;
      '') printf 'CURRENT_PARTIAL_INSTALL' ;;
      *) printf 'AMBIGUOUS_OR_FOREIGN' ;;
    esac
    return 0
  fi
  if [[ "$manager_version" == 3.2.* ]] \
     && [ -d "$NOBRAND_STATE_DIR" ] && nb_directory_empty "$NOBRAND_STATE_DIR"; then
    # Public v3.2.0 removed this root's contents before an unguarded scan of a
    # possibly absent config root. The still-installed compatible 3.2 manager
    # is positive current identity even after the installer advances to 3.2.1.
    printf 'CURRENT_PARTIAL_UNINSTALL'
    return 0
  fi
  if [ -d "$NOBRAND_STATE_DIR" ] && nb_directory_has_entries "$NOBRAND_STATE_DIR"; then
    printf 'AMBIGUOUS_OR_FOREIGN'
    return 0
  fi
  for root in "$NOBRAND_CONFIG_DIR" "$NOBRAND_LIB_DIR"; do
    if [ -d "$root" ] && nb_directory_has_entries "$root"; then
      printf 'AMBIGUOUS_OR_FOREIGN'
      return 0
    fi
  done
  case "$manager_version" in
    '') printf 'CLEAN' ;;
    *) printf 'AMBIGUOUS_OR_FOREIGN' ;;
  esac
}

nb_fail_legacy_state() {
  local detected
  detected="$(nb_legacy_signature_version 2>/dev/null || printf unknown)"
  die "$(t \
    "检测到无法安全自动迁移的旧版 NoBrand 数据。检测版本: ${detected}；当前安装器: ${SCRIPT_VERSION}。为避免覆盖现有节点、密钥和凭据，安装已停止。请先备份并按升级/迁移说明处理。" \
    "Unsupported legacy NoBrand data was detected (${detected}); installer ${SCRIPT_VERSION} stopped to avoid overwriting nodes, keys, or credentials. Use the matching legacy version to back up/remove it, then perform a clean installation.")" || return 1
}

nb_fail_ambiguous_state() {
  die "$(t \
    '检测到无法确认归属的已有安装数据。为避免覆盖现有配置，本次操作已停止。' \
    'Existing installation data has ambiguous ownership; this operation stopped to avoid overwriting it.')" || return 1
}

nb_install_state_notice() {
  case "${1:-$NOBRAND_INSTALL_STATE}" in
    CURRENT_COMPLETE)
      t '[提示] 检测到已安装的 NoBrand-OneClick。将检查当前安装并修复缺失组件。' \
        '[Info] NoBrand-OneClick is installed. The current installation will be checked and missing components repaired.'
      ;;
    CURRENT_PARTIAL_INSTALL)
      t '[提示] 检测到未完成的 NoBrand-OneClick 安装。将检查现有状态并继续安全修复；不会主动删除现有节点、凭据或入口配置。' \
        '[Info] An incomplete NoBrand-OneClick installation was detected. Existing state will be reconciled without deleting nodes, credentials, or ingress configuration.'
      ;;
    CURRENT_PARTIAL_REPAIR)
      t '[提示] 检测到上一次修复未完成，将根据当前状态继续检查和修复。' \
        '[Info] The previous repair was interrupted; checks and repair will continue from actual current state.'
      ;;
    CURRENT_PARTIAL_CONFIGURE)
      t '[提示] 检测到未完成的组件配置，将仅恢复记录的组件，不会启动其它协议安装。' \
        '[Info] An incomplete component configuration was detected. Only its recorded component will be recovered; no other protocol installer will start.'
      ;;
    CURRENT_PARTIAL_UNINSTALL)
      t '[提示] 检测到上一次 NoBrand-OneClick 卸载未完成。可重新运行安装器安全修复，或再次选择完整卸载继续清理剩余的 NoBrand 管理资源。' \
        '[Info] The previous NoBrand-OneClick uninstall was interrupted. Re-run the installer to repair safely, or choose full uninstall again to continue cleaning managed resources.'
      ;;
  esac
}

nb_validate_authoritative_state_boundary() {
  NOBRAND_INSTALL_STATE="$(nb_classify_installation_state)" || return 1
  case "$NOBRAND_INSTALL_STATE" in
    LEGACY_UNSUPPORTED) nb_fail_legacy_state; return 1 ;;
    AMBIGUOUS_OR_FOREIGN) nb_fail_ambiguous_state; return 1 ;;
    CLEAN|CURRENT_COMPLETE|CURRENT_PARTIAL_INSTALL|CURRENT_PARTIAL_REPAIR|\
      CURRENT_PARTIAL_CONFIGURE|CURRENT_PARTIAL_UNINSTALL) return 0 ;;
    *) nb_fail_ambiguous_state; return 1 ;;
  esac
}

nb_write_schema_v3_file() {
  local tmp
  tmp="$(mktemp "${NOBRAND_REGISTRY_FILE}.tmp.XXXXXX")" || return 1
  if ! printf '%s\n' \
      "{\"schema_version\":${NOBRAND_SCHEMA_VERSION},\"project\":\"NoBrand-OneClick\",\"ownership\":\"nobrand-v3\",\"author\":\"ike\",\"architecture\":\"splicore-native\",\"splicore_version\":\"v0.3.0-rc.4\",\"config_schema\":1}" \
      >"$tmp" \
    || ! chmod 0600 "$tmp" \
    || ! mv -f "$tmp" "$NOBRAND_REGISTRY_FILE"; then
    rm -f "$tmp"
    return 1
  fi
}

ensure_manager_state_layout() {
  local create="${1:-0}" install_state
  [ "${DRY_RUN:-0}" -eq 1 ] && return 0
  install_state="$(nb_classify_installation_state)" || return 1
  case "$install_state" in
    LEGACY_UNSUPPORTED) nb_fail_legacy_state; return 1 ;;
    AMBIGUOUS_OR_FOREIGN) nb_fail_ambiguous_state; return 1 ;;
  esac

  if [ "$create" -eq 1 ] && ! nb_schema_v3_file_valid; then
    mkdir -p "$NOBRAND_STATE_DIR" || return 1
    chmod 0700 "$NOBRAND_STATE_DIR" || return 1
    chown root:root "$NOBRAND_STATE_DIR" 2>/dev/null || true
    nb_write_schema_v3_file || return 1
  elif ! nb_schema_v3_file_valid; then
    return 0
  fi

  mkdir -p "$NOBRAND_BACKUP_DIR" "$NOBRAND_LOCK_DIR" || return 1
  chmod 0700 "$NOBRAND_BACKUP_DIR" "$NOBRAND_LOCK_DIR" || return 1
  chown root:root "$NOBRAND_BACKUP_DIR" "$NOBRAND_LOCK_DIR" 2>/dev/null || true
  chmod 0600 "$NOBRAND_REGISTRY_FILE" 2>/dev/null || return 1
}

dry_run_action_preview() {
  local action="${1:-unknown}"
  t '========== DRY-RUN：仅预览 ==========' '========== DRY-RUN: preview only =========='
  t "动作: ${action}" "Action: ${action}"
  [ -n "${PORT:-}" ] && t "端口: ${PORT}" "Port: ${PORT}"
  [ -n "${PORT_RANGE:-}" ] && t "端口段: ${PORT_RANGE}" "Port range: ${PORT_RANGE}"
  [ -n "${PROTOCOL:-}" ] && t "协议: ${PROTOCOL}" "Protocol: ${PROTOCOL}"
  [ -n "${MTU_REQUEST:-}" ] && t "MTU 请求: ${MTU_REQUEST}" "MTU request: ${MTU_REQUEST}"
  [ -n "${USERNAME:-}" ] && t "用户: ${USERNAME}" "User: ${USERNAME}"
  if [ -n "${ADVERTISE_HOST:-}" ]; then
    t "客户端展示入口: ${ADVERTISE_HOST}:${ADVERTISE_PORT}" \
      "Client display entry: ${ADVERTISE_HOST}:${ADVERTISE_PORT}"
  fi
  t '未执行命令；未修改配置、账号、服务、软件包、防火墙、tc、定时任务或持久化文件。' \
    'No command was executed; config, users, services, packages, firewall, tc, schedulers, and persistent files were not changed.'
}

dry_run_should_preview() {
  [ "${DRY_RUN:-0}" -eq 1 ] || return 1
  case "${1:-}" in
    help) return 1 ;;
    *) return 0 ;;
  esac
}

# BusyBox mktemp（Alpine）要求 XXXXXX 在模板末尾；GNU 允许中间占位
mktemp_file() {
  local suffix="${1:-}"
  local f="" candidate i
  f="$(mktemp /tmp/mita.XXXXXX 2>/dev/null)" || true
  if [ -z "$f" ]; then
    for i in 1 2 3 4 5; do
      candidate="/tmp/mita.$$.${RANDOM}.${i}"
      if (set -o noclobber; : >"$candidate") 2>/dev/null; then
        f="$candidate"
        break
      fi
    done
  fi
  if [ -z "$f" ]; then
    die "$(t '无法创建安全临时文件' 'Failed to create secure temporary file')" || true
    return 1
  fi
  [ -n "$suffix" ] || { printf '%s' "$f"; return; }
  local out="${f}${suffix}"
  if [ "$f" != "$out" ]; then
    if ! mv "$f" "$out" 2>/dev/null; then
      rm -f "$f"
      die "$(t '无法创建带后缀的安全临时文件' 'Failed to create secure suffixed temporary file')"
      return 1
    fi
  fi
  printf '%s' "$out"
}

mktemp_dir() {
  local d
  d="$(mktemp -d /tmp/mita.XXXXXX 2>/dev/null)" \
    || d="$(mktemp -d 2>/dev/null)" \
    || { d="/tmp/mita_$$_${RANDOM}"; mkdir -p "$d"; }
  printf '%s' "$d"
}

read_tty() {
  local _var="$1"
  local _prompt="${2:-}"
  local _line=""
  if [ -n "$_prompt" ]; then
    if [ -t 0 ]; then
      read -r -p "$_prompt" _line || _line=""
    elif [ -r /dev/tty ]; then
      read -r -p "$_prompt" _line </dev/tty || _line=""
    else
      return 1
    fi
  else
    if [ -t 0 ]; then
      read -r _line || _line=""
    elif [ -r /dev/tty ]; then
      read -r _line </dev/tty || _line=""
    else
      return 1
    fi
  fi
  printf -v "$_var" '%s' "$_line"
}

confirm() {
  local prompt_zh="$1"
  local prompt_en="$2"
  local default="${3:-y}"
  if [ "$YES" -eq 1 ]; then
    return 0
  fi
  local prompt
  if [ "$LANG_ZH" -eq 1 ]; then
    prompt="$prompt_zh"
  else
    prompt="$prompt_en"
  fi
  local ans=""
  read_tty ans "$prompt" || return 1
  ans="${ans:-$default}"
  case "$ans" in
    y|Y|yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}

require_root() {
  if [ "$(id -u)" -eq 0 ]; then
    return 0
  fi
  STAGE="权限检查"
  if [ -f /etc/alpine-release ]; then
    die "$(t '需要 root 权限；Alpine 请 su - 或 docker exec -u root 后直接 bash 运行（无 sudo）' \
      'Root required; on Alpine use su - or docker exec -u root, then run with bash (no sudo)')"
  fi
  die "$(t '需要 root 权限，请使用 sudo 运行' 'Root privileges required; run with sudo')"
}

require_linux() {
  STAGE="系统检查"
  case "$(uname -s)" in
    Linux) ;;
    *) die "$(t '仅支持 Linux 系统' 'Linux only')" ;;
  esac
}

require_cmd() {
  local c="$1"
  command -v "$c" >/dev/null 2>&1 || die "$(t "缺少命令：${c}" "Missing command: ${c}")"
}

detect_pkg_manager() {
  STAGE="检测包管理器"
  if [ -f /etc/alpine-release ] && command -v apk >/dev/null 2>&1; then
    echo alpine
    return
  fi
  if command -v dpkg >/dev/null 2>&1 && dpkg -l >/dev/null 2>&1; then
    echo deb
    return
  fi
  if command -v rpm >/dev/null 2>&1 && rpm -qa >/dev/null 2>&1; then
    echo rpm
    return
  fi
  die "$(t '未检测到 deb、rpm 或 apk 包管理器' 'No deb, rpm, or apk package manager detected')"
}

_has_group() {
  getent group "$1" >/dev/null 2>&1 || grep -q "^$1:" /etc/group 2>/dev/null
}

_has_user() {
  getent passwd "$1" >/dev/null 2>&1 || grep -q "^$1:" /etc/passwd 2>/dev/null
}

proto_lower() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

has_control_chars() {
  printf '%s' "${1-}" | LC_ALL=C grep -q '[[:cntrl:]]'
}

safe_filename_component() {
  local value="${1-}"
  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import sys,urllib.parse; print(urllib.parse.quote(sys.argv[1], safe="._-"))' "$value"
  else
    printf '%s' "$value" | sed 's/[^A-Za-z0-9._-]/_/g'
  fi
}

admin_lock_acquire() {
  if [ "${DRY_RUN:-0}" -eq 1 ]; then
    _ADMIN_LOCK_HELD=$((${_ADMIN_LOCK_HELD:-0} + 1))
    return 0
  fi
  command -v flock >/dev/null 2>&1 || return 0
  run mkdir -p "$(dirname "$MITA_ADMIN_LOCK")"
  if [ "${_ADMIN_LOCK_HELD:-0}" -gt 0 ]; then
    _ADMIN_LOCK_HELD=$((_ADMIN_LOCK_HELD + 1))
    return 0
  fi
  exec 8>"$MITA_ADMIN_LOCK"
  if { flock --help 2>&1 || true; } | grep -q -- '-w' \
     && flock -w 120 8; then
    _ADMIN_LOCK_HELD=1
    return 0
  elif ! { flock --help 2>&1 || true; } | grep -q -- '-w' \
       && command -v timeout >/dev/null 2>&1 \
       && timeout 120 flock 8; then
    _ADMIN_LOCK_HELD=1
    return 0
  fi
  exec 8>&-
  die "$(t '获取管理锁超时，操作已取消以避免并发写入' \
    'Admin lock timeout; operation cancelled to prevent concurrent writes')" || return 1
}

admin_lock_release() {
  [ "${_ADMIN_LOCK_HELD:-0}" -gt 0 ] || return 0
  _ADMIN_LOCK_HELD=$((_ADMIN_LOCK_HELD - 1))
  [ "${DRY_RUN:-0}" -eq 1 ] && return 0
  if [ "$_ADMIN_LOCK_HELD" -le 0 ]; then
    _ADMIN_LOCK_HELD=0
    flock -u 8 2>/dev/null || true
    exec 8>&-
  fi
}

# ---------- NoBrand Common Core: transport-aware 端口注册表与分配 ----------

nb_normalize_transport() {
  case "$(printf '%s' "${1:-}" | tr '[:lower:]' '[:upper:]')" in
    TCP) printf 'TCP' ;;
    UDP) printf 'UDP' ;;
    *) return 1 ;;
  esac
}

# 手工端口允许 1-65535；自动分配始终从 1025 起。Mieru 自身仍通过
# valid_port 保持原有 1025 下限。
nb_valid_port() {
  local port
  port="$(normalize_uint "${1:-}")" || return 1
  [ "${#port}" -le 5 ] && [ "$port" -ge 1 ] && [ "$port" -le 65535 ]
}

# 默认路由出口优先，避免 Docker bridge/第二网卡抢占端口尾号语义。
nb_detect_local_ipv4() {
  local candidate=""
  if [ -n "${NOBRAND_TEST_LOCAL_IPV4:-}" ]; then
    printf '%s' "$NOBRAND_TEST_LOCAL_IPV4"
    return 0
  fi
  if command -v ip >/dev/null 2>&1; then
    candidate="$(ip -4 route get 1.1.1.1 2>/dev/null \
      | awk '{for(i=1;i<=NF;i++) if($i=="src"){print $(i+1); exit}}')" || true
  fi
  if [ -z "$candidate" ] && command -v ip >/dev/null 2>&1; then
    candidate="$(ip -o -4 route show default 2>/dev/null \
      | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}' \
      | while IFS= read -r iface; do
          [ -n "$iface" ] || continue
          ip -o -4 addr show dev "$iface" scope global 2>/dev/null \
            | awk '{split($4,a,"/"); print a[1]; exit}'
          break
        done)" || true
  fi
  if [ -z "$candidate" ]; then
    candidate="$(hostname -I 2>/dev/null | tr ' ' '\n' \
      | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' \
      | grep -vE '^(127|169\.254)\.' | head -n1)" || true
  fi
  case "$candidate" in
    *.*.*.*) printf '%s' "$candidate" ;;
    *) return 1 ;;
  esac
}

nb_port_base_for_ip() {
  local ip="${1:-}" octet base
  octet="${ip##*.}"
  [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
  [[ "$octet" =~ ^[0-9]+$ ]] || return 1
  [ "$octet" -ge 1 ] && [ "$octet" -le 254 ] || return 1
  base=$((10#$octet * 100))
  [ "$base" -ge 1025 ] && [ "$((base + 99))" -le 65535 ] || return 1
  printf '%s' "$base"
}

nb_tail_port_bounds() {
  local ip="${1:-}" base
  [ -n "$ip" ] || ip="$(nb_detect_local_ipv4)" || return 1
  base="$(nb_port_base_for_ip "$ip")" || return 1
  printf '%s|%s' "$((base + 1))" "$((base + 99))"
}

# 尾号算法只把 base+1..base+99 分配给代理。base（xx00）保留给
# 外部 NAT、SSH 或实验室入口等带外设施；这些占用在 guest 内通常不可见。
# 规则由本机默认路由 IPv4 推导，不包含任何环境专用 IP 或端口常量。
nb_tail_base_reservation_owner() {
  local port ip base
  port="$(normalize_uint "${1:-}")" || return 1
  ip="$(nb_detect_local_ipv4 2>/dev/null || true)"
  [ -n "$ip" ] || return 1
  base="$(nb_port_base_for_ip "$ip" 2>/dev/null || true)"
  [ -n "$base" ] && [ "$port" -eq "$base" ] || return 1
  printf 'common:tail-base:%s' "$ip"
}

nb_port_is_tail_base_reserved() {
  nb_tail_base_reservation_owner "$1" >/dev/null 2>&1
}

# 随机起点 + 环形遍历。check_fn 成功表示端口可用。
nb_scan_port_span() {
  local lo="$1" hi="$2" check_fn="$3"
  shift 3
  local span start index offset port
  [ "$lo" -le "$hi" ] || return 1
  span=$((hi - lo + 1))
  if [ -n "${NOBRAND_TEST_RANDOM_START:-}" ]; then
    start=$((NOBRAND_TEST_RANDOM_START % span))
  else
    start=$((RANDOM % span))
  fi
  index=0
  while [ "$index" -lt "$span" ]; do
    offset=$(((start + index) % span))
    port=$((lo + offset))
    if "$check_fn" "$port" "$@"; then
      printf '%s' "$port"
      return 0
    fi
    index=$((index + 1))
  done
  return 1
}

nb_port_bind_probe_in_use() {
  local transport port
  transport="$(nb_normalize_transport "$1")" || return 2
  port="$(normalize_uint "$2")" || return 2
  command -v python3 >/dev/null 2>&1 || return 2
  python3 - "$transport" "$port" <<'PY'
import errno
import socket
import sys

transport, raw_port = sys.argv[1:3]
port = int(raw_port)
sock_type = socket.SOCK_STREAM if transport == "TCP" else socket.SOCK_DGRAM
attempted = False
for family, address in ((socket.AF_INET6, "::"), (socket.AF_INET, "0.0.0.0")):
    try:
        sock = socket.socket(family, sock_type)
    except OSError:
        continue
    attempted = True
    try:
        if family == socket.AF_INET6:
            try:
                sock.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 0)
            except OSError:
                pass
        sock.bind((address, port))
    except OSError as exc:
        sock.close()
        if exc.errno in (errno.EADDRINUSE, errno.EACCES):
            raise SystemExit(0)
        continue
    sock.close()
raise SystemExit(1 if attempted else 2)
PY
}

# 成功表示该 transport 的端口已有 listener。
nb_port_is_listening() {
  local transport port flags
  transport="$(nb_normalize_transport "$1")" || return 1
  port="$(normalize_uint "$2")" || return 1
  if command -v ss >/dev/null 2>&1; then
    [ "$transport" = TCP ] && flags='-Hlnt' || flags='-Hlnu'
    ss "$flags" 2>/dev/null | awk -v port="$port" '
      { for (i=1; i<=NF; i++) if ($i ~ (":" port "$")) { found=1; exit } }
      END { exit(found ? 0 : 1) }
    '
    return $?
  fi
  if command -v netstat >/dev/null 2>&1; then
    [ "$transport" = TCP ] && flags='-lnt' || flags='-lnu'
    netstat "$flags" 2>/dev/null | awk -v port="$port" '
      { for (i=1; i<=NF; i++) if ($i ~ (":" port "$")) { found=1; exit } }
      END { exit(found ? 0 : 1) }
    '
    return $?
  fi
  nb_port_bind_probe_in_use "$transport" "$port"
}

nb_port_listener_details() {
  local transport port flags
  transport="$(nb_normalize_transport "$1")" || return 0
  port="$(normalize_uint "$2")" || return 0
  if command -v ss >/dev/null 2>&1; then
    [ "$transport" = TCP ] && flags='-Hlntp' || flags='-Hlnup'
    ss "$flags" 2>/dev/null | awk -v port="$port" '
      { for (i=1; i<=NF; i++) if ($i ~ (":" port "$")) { print; break } }
    '
  elif command -v netstat >/dev/null 2>&1; then
    [ "$transport" = TCP ] && flags='-lntp' || flags='-lnup'
    netstat "$flags" 2>/dev/null | awk -v port="$port" '
      { for (i=1; i<=NF; i++) if ($i ~ (":" port "$")) { print; break } }
    '
  fi
}

# Return the socket-owner PIDs reported by ss/netstat. Doctor runs as root on
# supported deployments, so ss normally exposes pid=NNN; the netstat form is
# retained for compatibility. An empty result means ownership was not visible.
nb_port_listener_pids() {
  local details
  details="$(nb_port_listener_details "$1" "$2" 2>/dev/null || true)"
  [ -n "$details" ] || return 0
  printf '%s\n' "$details" \
    | sed -nE \
      -e 's/.*pid=([0-9]+).*/\1/p' \
      -e 's/.*[[:space:]]([0-9]+)\/[^[:space:]]+[[:space:]]*$/\1/p' \
    | LC_ALL=C sort -u
}

# 输出 native/retained-feature owner|transport|port|advertise_host|advertise_port。
nb_registry_rows() {
  command -v python3 >/dev/null 2>&1 || return 0
  NOBRAND_VLESS_STATE_FILE="$NOBRAND_VLESS_STATE_FILE" \
  NOBRAND_FORWARD_STATE_FILE="$NOBRAND_FORWARD_STATE_FILE" \
  NOBRAND_SPLICORE_DESIRED="${NOBRAND_STATE_DIR}/splicore/current/desired.json" \
  python3 - <<'PY'
import json
import os

def emit(owner, transport, port, host="", advertise_port=""):
    try:
        port = int(port)
    except Exception:
        return
    print("%s|%s|%s|%s|%s" % (owner, transport.upper(), port, host or "", advertise_port or ""))

primary_path = os.environ.get("NOBRAND_SPLICORE_DESIRED", "")
primary = bool(primary_path and os.path.isfile(primary_path))
if primary:
    state = json.load(open(primary_path, encoding="utf-8"))
    if state.get("owner") != "nobrand-splicore-v1":
        raise SystemExit(1)
    for node in state["nodes"]:
        doc = node["document"]
        protocol = node["protocol"]
        transport = doc["settings"]["transport"] if protocol == "mieru" else "TCP" if protocol in ("snell", "vless-reality") else "UDP"
        emit(protocol + ":" + node["id"], transport, doc["listener"]["port"],
             doc["display_endpoint"]["host"], doc["display_endpoint"]["port"])
        if node.get("guard"):
            emit("splicore-guard:" + node["id"], "TCP", node["guard"]["listen"]["port"])

vless_path = os.environ.get("NOBRAND_VLESS_STATE_FILE", "")
if vless_path and os.path.isfile(vless_path):
    try:
        state = json.load(open(vless_path, encoding="utf-8"))
        emit("vless-sudoku:default", "TCP", state.get("listen_port"),
             state.get("advertise_host"), state.get("advertise_port"))
    except Exception:
        pass

forward_path = os.environ.get("NOBRAND_FORWARD_STATE_FILE", "")
if forward_path and os.path.isfile(forward_path):
    try:
        state = json.load(open(forward_path, encoding="utf-8"))
        if (state.get("schema_version") == 3 and state.get("ownership") == "nobrand-v3"
                and state.get("feature") == "port-forward"):
            for rule in sorted(state.get("rules") or [], key=lambda item: str(item.get("rule_id") or "")):
                rule_id = str(rule.get("rule_id") or "")
                protocol = str(rule.get("protocol") or "").lower()
                owner = "forward:" + rule_id
                if protocol in ("tcp", "both"):
                    emit(owner, "TCP", rule.get("listen_port"), rule.get("display_host"),
                         rule.get("display_port"))
                if protocol in ("udp", "both"):
                    emit(owner, "UDP", rule.get("listen_port"), rule.get("display_host"),
                         rule.get("display_port"))
    except Exception:
        pass


PY
}

nb_registry_port_owner() {
  local transport port ignore_owner="${3:-}" owner row_transport row_port _rest
  transport="$(nb_normalize_transport "$1")" || return 1
  port="$(normalize_uint "$2")" || return 1
  while IFS='|' read -r owner row_transport row_port _rest; do
    [ -n "$owner" ] || continue
    [ "$owner" = "$ignore_owner" ] && continue
    if [ "$row_transport" = "$transport" ] && [ "$row_port" = "$port" ]; then
      printf '%s' "$owner"
      return 0
    fi
  done < <(nb_registry_rows)
  return 1
}

nb_port_available_for_transport() {
  local port="$1" transport="$2" ignore_owner="${3:-}"
  nb_port_available_for_profile "$port" "$transport" "$NOBRAND_LEGACY_INGRESS_PROFILE_ID" "$ignore_owner"
}

nb_port_available_for_profile() {
  local port="$1" transport="$2" profile_id="${3:-$NOBRAND_LEGACY_INGRESS_PROFILE_ID}" ignore_owner="${4:-}"
  nb_valid_port "$port" || return 1
  transport="$(nb_normalize_transport "$transport")" || return 1
  nb_ingress_profile_json "$profile_id" >/dev/null 2>&1 || return 1
  nb_ingress_port_is_reserved "$profile_id" "$port" && return 1
  nb_registry_port_owner "$transport" "$port" "$ignore_owner" >/dev/null 2>&1 && return 1
  nb_port_is_listening "$transport" "$port" && return 1
  return 0
}

nb_select_available_port() {
  local transport profile_id="${2:-$NOBRAND_LEGACY_INGRESS_PROFILE_ID}" bounds lo hi selected attempt random_value rc=0
  transport="$(nb_normalize_transport "$1")" || return 1
  bounds="$(nb_ingress_profile_auto_range "$profile_id" 2>/dev/null)" || rc=$?
  if [ "$rc" -eq 0 ] && [ -n "$bounds" ]; then
    lo="${bounds%%|*}"
    hi="${bounds#*|}"
    if selected="$(nb_scan_port_span "$lo" "$hi" nb_port_available_for_profile "$transport" "$profile_id")"; then
      printf '%s' "$selected"
      return 0
    fi
  fi
  # Explicit profiles fail closed. manual-only has no pool, while exhausted
  # derived/custom ranges never silently escape into an unrelated random port.
  [ "$profile_id" = "$NOBRAND_LEGACY_INGRESS_PROFILE_ID" ] || return 1
  attempt=0
  while [ "$attempt" -lt 512 ]; do
    if command -v openssl >/dev/null 2>&1; then
      random_value="$(openssl rand -hex 2 2>/dev/null || true)"
      if [[ "$random_value" =~ ^[0-9a-fA-F]{4}$ ]]; then
        selected=$((1025 + 16#$random_value % (65535 - 1025 + 1)))
      else
        selected=$((1025 + RANDOM % (65535 - 1025 + 1)))
      fi
    else
      selected=$((1025 + RANDOM % (65535 - 1025 + 1)))
    fi
    if nb_port_available_for_transport "$selected" "$transport"; then
      printf '%s' "$selected"
      return 0
    fi
    attempt=$((attempt + 1))
  done
  return 1
}

nb_warn_if_outside_recommended_range() {
  local port="$1" profile_id="${2:-$NOBRAND_LEGACY_INGRESS_PROFILE_ID}" profile_name bounds lo hi
  profile_name="$(nb_ingress_profile_name "$profile_id" 2>/dev/null || printf '%s' "$profile_id")"
  bounds="$(nb_ingress_profile_auto_range "$profile_id" 2>/dev/null || true)"
  [ -n "$bounds" ] || return 0
  lo="${bounds%%|*}"
  hi="${bounds#*|}"
  if nb_ingress_port_is_reserved "$profile_id" "$port"; then
    warn "$(t "指定端口 ${port} 是入口配置 ${profile_name} 的保留端口，不允许代理绑定" \
      "Port ${port} is reserved by ingress profile ${profile_name} and cannot be used by a proxy")"
    return 0
  fi
  if [ "$port" -lt "$lo" ] || [ "$port" -gt "$hi" ]; then
    warn "$(t "指定端口 ${port} 不在入口配置 ${profile_name} 的自动段 ${lo}-${hi}；确认空闲后仍允许使用" \
      "Port ${port} is outside ingress profile ${profile_name}'s auto range ${lo}-${hi}; it is still allowed when free")"
  fi
}

nb_describe_port_conflict() {
  local transport="$1" port="$2" profile_id="${3:-$NOBRAND_LEGACY_INGRESS_PROFILE_ID}" owner details
  if nb_ingress_port_is_reserved "$profile_id" "$port"; then
    t "  由入口配置保留: $(nb_ingress_profile_name "$profile_id")" \
      "  reserved by ingress profile: $(nb_ingress_profile_name "$profile_id")"
  fi
  owner="$(nb_registry_port_owner "$transport" "$port" 2>/dev/null || true)"
  [ -z "$owner" ] || t "  状态归属: ${owner}" "  state owner: ${owner}"
  details="$(nb_port_listener_details "$transport" "$port" 2>/dev/null || true)"
  [ -z "$details" ] || {
    if [ "$LANG_ZH" -eq 1 ]; then
      printf '%s\n' "$details" | sed 's/^/  监听进程: /'
    else
      printf '%s\n' "$details" | sed 's/^/  listener: /'
    fi
  }
}

# ---------- NoBrand Common Core: ingress profiles (schema-v3 optional state) ----------

NOBRAND_LEGACY_INGRESS_PROFILE_ID="legacy-default-route"

nb_ingress_now() {
  date -u +%Y-%m-%dT%H:%M:%SZ
}

nb_ingress_valid_ipv4() {
  local value="${1:-}"
  command -v python3 >/dev/null 2>&1 || {
    [[ "$value" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
    local part
    IFS=. read -r -a _nb_ipv4_parts <<<"$value"
    for part in "${_nb_ipv4_parts[@]}"; do
      [[ "$part" =~ ^[0-9]+$ ]] && [ "$((10#$part))" -le 255 ] || return 1
    done
    return 0
  }
  python3 - "$value" <<'PY' >/dev/null 2>&1
import ipaddress, sys
try:
    value = ipaddress.ip_address(sys.argv[1])
except ValueError:
    raise SystemExit(1)
raise SystemExit(0 if value.version == 4 and not value.is_loopback and not value.is_link_local else 1)
PY
}

nb_ingress_is_rfc1918() {
  local value="${1:-}" first second third fourth
  [[ "$value" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
  IFS=. read -r first second third fourth <<<"$value"
  for value in "$first" "$second" "$third" "$fourth"; do
    [[ "$value" =~ ^[0-9]+$ ]] && [ "$((10#$value))" -le 255 ] || return 1
  done
  first=$((10#$first))
  second=$((10#$second))
  [ "$first" -eq 10 ] \
    || { [ "$first" -eq 172 ] && [ "$second" -ge 16 ] && [ "$second" -le 31 ]; } \
    || { [ "$first" -eq 192 ] && [ "$second" -eq 168 ]; }
}

# interface|IPv4|state|default-route-marker. Tests may provide exact rows
# through NOBRAND_TEST_INTERFACE_ROWS without changing the host network.
nb_ingress_interface_rows() {
  local default_iface=""
  if [ -n "${NOBRAND_TEST_INTERFACE_ROWS:-}" ]; then
    printf '%s\n' "$NOBRAND_TEST_INTERFACE_ROWS" | sed '/^$/d'
    return 0
  fi
  command -v ip >/dev/null 2>&1 || return 0
  default_iface="$(ip -o -4 route show default 2>/dev/null \
    | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')"
  ip -o -4 addr show scope global 2>/dev/null | awk -v default_iface="$default_iface" '
    {
      iface=$2; sub(/@.*/, "", iface); split($4, address, "/")
      state="UNKNOWN"
      command="ip -o link show dev \"" iface "\" 2>/dev/null"
      if ((command | getline link) > 0) {
        if (link ~ /state UP/) state="UP"; else if (link ~ /state DOWN/) state="DOWN"
      }
      close(command)
      print iface "|" address[1] "|" state "|" (iface==default_iface ? "1" : "0")
    }
  '
}

nb_ingress_interface_exists() {
  local expected="$1" iface _address _state _default
  if [ "$#" -ge 2 ]; then
    while IFS='|' read -r iface _address _state _default; do
      [ "$iface" = "$expected" ] && return 0
    done <<<"${2-}"
  else
    while IFS='|' read -r iface _address _state _default; do
      [ "$iface" = "$expected" ] && return 0
    done < <(nb_ingress_interface_rows)
  fi
  return 1
}

nb_ingress_address_on_interface() {
  local expected_iface="$1" expected_address="$2" iface address _state _default
  nb_ingress_valid_ipv4 "$expected_address" || return 1
  if [ "$#" -ge 3 ]; then
    while IFS='|' read -r iface address _state _default; do
      [ "$iface" = "$expected_iface" ] && [ "$address" = "$expected_address" ] && return 0
    done <<<"${3-}"
  else
    while IFS='|' read -r iface address _state _default; do
      [ "$iface" = "$expected_iface" ] && [ "$address" = "$expected_address" ] && return 0
    done < <(nb_ingress_interface_rows)
  fi
  return 1
}

nb_ingress_default_egress() {
  local iface="" address=""
  if [ -n "${NOBRAND_TEST_DEFAULT_EGRESS:-}" ]; then
    printf '%s' "$NOBRAND_TEST_DEFAULT_EGRESS"
    return 0
  fi
  if command -v ip >/dev/null 2>&1; then
    iface="$(ip -o -4 route show default 2>/dev/null \
      | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')"
    address="$(ip -4 route get 1.1.1.1 2>/dev/null \
      | awk '{for(i=1;i<=NF;i++) if($i=="src"){print $(i+1); exit}}')"
  fi
  [ -n "$iface$address" ] || return 1
  printf '%s|%s' "$iface" "$address"
}

nb_ingress_state_valid() {
  local path="${1:-$NOBRAND_INGRESS_STATE_FILE}" address policy display_host
  [ -f "$path" ] && [ ! -L "$path" ] && [ -s "$path" ] || return 1
  jq -e --argjson schema "$NOBRAND_SCHEMA_VERSION" '
    (keys|sort) == ["default_profile_id","feature","ownership","profiles","schema_version"]
    and .schema_version == $schema and .ownership == "nobrand-v3"
    and .feature == "ingress-profiles"
    and ((.default_profile_id == null) or (.default_profile_id|type == "string"))
    and (.profiles|type == "array")
    and (([.profiles[].profile_id]|length) == ([.profiles[].profile_id]|unique|length))
    and (([.profiles[].name]|length) == ([.profiles[].name]|unique|length))
    and ([.profiles[].profile_id] as $ids |
         all(.profiles[];
           . as $profile |
           $profile.name != "legacy-default-route" and $profile.name != "Legacy Default Route"
           and ($ids|index($profile.name)|not)))
    and all(.profiles[];
      ((keys-["ingress_enforcement"]|sort) == ["created_at","display_host_default","display_port","display_port_policy","enabled",
                      "interface","local_address","name","port_policy","profile_id","range_end","range_start",
                      "reserved_ports","type","updated_at"])
      and ((has("ingress_enforcement")|not) or
           (.ingress_enforcement == "permissive" or .ingress_enforcement == "strict"))
      and (.profile_id|type == "string" and test("^i[0-9a-f]{16}$"))
      and (.name|type == "string" and length > 0 and length <= 64 and (test("[[:cntrl:]]")|not))
      and (.type == "public" or .type == "mapped")
      and (.interface|type == "string" and test("^[A-Za-z0-9_.:-]{1,64}$"))
      and (.local_address|type == "string" and length > 0)
      and (.port_policy == "derived-tail" or .port_policy == "custom-range" or .port_policy == "manual-only")
      and (.reserved_ports|type == "array")
      and (all(.reserved_ports[]; type == "number" and floor == . and . >= 1 and . <= 65535))
      and ((.reserved_ports|length) == (.reserved_ports|unique|length))
      and (if .port_policy == "custom-range" then
             (.range_start|type == "number") and (.range_end|type == "number")
             and .range_start >= 1025 and .range_end <= 65535 and .range_start <= .range_end
           else .range_start == null and .range_end == null end)
      and (.display_port_policy == "follow-actual" or .display_port_policy == "custom")
      and (if .display_port_policy == "custom" then
             ((.display_port|type) == "number" and .display_port >= 1 and .display_port <= 65535)
           else .display_port == null end)
      and (.display_host_default|type == "string")
      and (if .type == "mapped" then (.display_host_default|length > 0) else true end)
      and (.enabled|type == "boolean")
      and (.created_at|type == "string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$"))
      and (.updated_at|type == "string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$"))
    )
    and (.default_profile_id as $default |
         if $default == null then true
         else any(.profiles[]; .profile_id == $default and .enabled) end)
  ' "$path" >/dev/null 2>&1 || return 1
  while IFS=$'\t' read -r address policy display_host; do
    nb_ingress_valid_ipv4 "$address" || return 1
    [ "$policy" != derived-tail ] || nb_port_base_for_ip "$address" >/dev/null || return 1
    [ -z "$display_host" ] || valid_advertise_host "$display_host" || return 1
  done < <(jq -r '.profiles[]|[.local_address,.port_policy,.display_host_default]|@tsv' "$path")
}

nb_ingress_ensure_state() {
  local tmp
  nb_init_state_layout || return 1
  if [ -e "$NOBRAND_INGRESS_STATE_FILE" ]; then
    nb_ingress_state_valid || die 'Ingress Profile 状态无效；为避免覆盖现有数据，操作已停止' || return 1
    return 0
  fi
  tmp="$(mktemp_file .ingress.json)" || return 1
  jq -n --argjson schema "$NOBRAND_SCHEMA_VERSION" \
    '{schema_version:$schema,ownership:"nobrand-v3",feature:"ingress-profiles",default_profile_id:null,profiles:[]}' \
    >"$tmp" || { rm -f "$tmp"; return 1; }
  nb_atomic_install_file "$tmp" "$NOBRAND_INGRESS_STATE_FILE" 0600
  local rc=$?
  rm -f "$tmp"
  return "$rc"
}

nb_ingress_generate_id() {
  local id attempt=0
  while [ "$attempt" -lt 64 ]; do
    id="i$(openssl rand -hex 8 2>/dev/null || printf '%016x' "$((RANDOM * 32768 + RANDOM))")"
    [[ "$id" =~ ^i[0-9a-f]{16}$ ]] || { attempt=$((attempt + 1)); continue; }
    if [ ! -s "$NOBRAND_INGRESS_STATE_FILE" ] \
       || jq -e --arg id "$id" 'all(.profiles[];.profile_id!=$id)' "$NOBRAND_INGRESS_STATE_FILE" >/dev/null; then
      printf '%s' "$id"
      return 0
    fi
    attempt=$((attempt + 1))
  done
  return 1
}

nb_ingress_legacy_profile_json() {
  local ip iface="" base="" range_start=null range_end=null reserved='[]'
  ip="$(nb_detect_local_ipv4 2>/dev/null || true)"
  if command -v ip >/dev/null 2>&1 && [ -n "$ip" ]; then
    iface="$(ip -o -4 addr show scope global 2>/dev/null \
      | awk -v ip="$ip" '{split($4,a,"/"); if(a[1]==ip){x=$2; sub(/@.*/,"",x); print x; exit}}')"
  fi
  if base="$(nb_port_base_for_ip "$ip" 2>/dev/null)"; then
    range_start=$((base + 1)); range_end=$((base + 99)); reserved="[$base]"
  fi
  jq -n --arg id "$NOBRAND_LEGACY_INGRESS_PROFILE_ID" --arg name 'Legacy Default Route' \
    --arg interface "$iface" --arg address "$ip" --argjson range_start "$range_start" \
    --argjson range_end "$range_end" --argjson reserved "$reserved" '
      {profile_id:$id,name:$name,type:"legacy",interface:$interface,local_address:$address,
       port_policy:"derived-tail",range_start:$range_start,range_end:$range_end,
       reserved_ports:$reserved,display_host_default:"",display_port_policy:"follow-actual",
       display_port:null,ingress_enforcement:"permissive",enabled:true,built_in:true,created_at:"",updated_at:""}
    '
}

nb_ingress_profile_json() {
  local selector="${1:-}" id
  [ -n "$selector" ] || return 1
  if [ "$selector" = "$NOBRAND_LEGACY_INGRESS_PROFILE_ID" ] || [ "$selector" = 'Legacy Default Route' ]; then
    nb_ingress_legacy_profile_json
    return 0
  fi
  nb_ingress_state_valid || return 1
  id="$(jq -r --arg value "$selector" '
    [.profiles[]|select(.profile_id==$value or .name==$value)|.profile_id] as $ids |
    if ($ids|length)==1 then $ids[0] else empty end
  ' "$NOBRAND_INGRESS_STATE_FILE")"
  [ -n "$id" ] || return 1
  jq -c --arg id "$id" '.profiles[]|select(.profile_id==$id)' "$NOBRAND_INGRESS_STATE_FILE"
}

nb_ingress_profile_id() {
  local json
  json="$(nb_ingress_profile_json "$1")" || return 1
  jq -r .profile_id <<<"$json"
}

nb_ingress_default_profile_id() {
  if nb_ingress_state_valid; then
    jq -r '.default_profile_id // empty' "$NOBRAND_INGRESS_STATE_FILE"
  fi
}

# Resolution for a newly-created object: explicit request, then configured
# default, then the immutable 3.1 legacy adapter.
nb_resolve_ingress_profile() {
  local requested="${1:-}" resolved=""
  if [ -n "$requested" ]; then
    resolved="$(nb_ingress_profile_id "$requested" 2>/dev/null || true)"
    [ -n "$resolved" ] || die "找不到 Ingress Profile，或选择结果不唯一: ${requested}" || return 1
  else
    resolved="$(nb_ingress_default_profile_id 2>/dev/null || true)"
    [ -n "$resolved" ] || resolved="$NOBRAND_LEGACY_INGRESS_PROFILE_ID"
  fi
  local profile
  profile="$(nb_ingress_profile_json "$resolved")" || return 1
  [ "$(jq -r .enabled <<<"$profile")" = true ] || die "Ingress Profile 已禁用: ${resolved}" || return 1
  printf '%s' "$resolved"
}

nb_prepare_ingress_request() {
  INGRESS_PROFILE_ID="$(nb_resolve_ingress_profile "${INGRESS_PROFILE:-}")" || return 1
}

nb_ingress_profile_enforcement() {
  local profile
  profile="$(nb_ingress_profile_json "${1:-}")" || return 1
  jq -r '.ingress_enforcement // "permissive"' <<<"$profile"
}

# Resolve the exact deployment contract for a managed listener.  The
# capability argument is an implementation fact established by the pinned
# runtime audit, not a user-selectable mode.
nb_prepare_ingress_deployment() {
  local profile_id="$1" capability="$2" profile policy address
  profile="$(nb_ingress_profile_json "$profile_id")" || return 1
  policy="$(nb_ingress_profile_enforcement "$profile_id")" || return 1
  address="$(jq -r '.local_address // empty' <<<"$profile")"
  INGRESS_LOCAL_ADDRESS="$address"
  case "$capability" in
    not-applicable)
      INGRESS_ENFORCEMENT_RESOLVED=not-applicable
      INGRESS_ENFORCEMENT_METHOD="system-ssh"
      INGRESS_LISTEN_HOST=0.0.0.0
      return 0
      ;;
    native-bind|firewall|address-match) ;;
    *) return 1 ;;
  esac
  case "$policy" in
    permissive)
      INGRESS_ENFORCEMENT_RESOLVED=permissive
      INGRESS_ENFORCEMENT_METHOD=wildcard
      INGRESS_LISTEN_HOST=0.0.0.0
      ;;
    strict)
      [ "$profile_id" != "$NOBRAND_LEGACY_INGRESS_PROFILE_ID" ] || return 1
      nb_ingress_valid_ipv4 "$address" || return 1
      nb_ingress_address_on_interface "$(jq -r .interface <<<"$profile")" "$address" || return 1
      INGRESS_ENFORCEMENT_RESOLVED=strict
      INGRESS_ENFORCEMENT_METHOD="$capability"
      case "$capability" in
        native-bind|address-match) INGRESS_LISTEN_HOST="$address" ;;
        firewall) INGRESS_LISTEN_HOST=0.0.0.0 ;;
      esac
      ;;
    *) return 1 ;;
  esac
}

nb_ingress_stamp_state_file() {
  local path="$1" profile_id="$2" capability="$3" tmp
  [ -s "$path" ] && jq empty "$path" >/dev/null 2>&1 || return 1
  nb_prepare_ingress_deployment "$profile_id" "$capability" || return 1
  tmp="$(mktemp_file .ingress-stamp)" || return 1
  jq --arg policy "$INGRESS_ENFORCEMENT_RESOLVED" --arg method "$INGRESS_ENFORCEMENT_METHOD" \
    --arg address "$INGRESS_LOCAL_ADDRESS" \
    '.ingress_enforcement=$policy | .ingress_enforcement_method=$method | .ingress_local_address=$address' \
    "$path" >"$tmp" && mv -f "$tmp" "$path"
  local rc=$?
  rm -f "$tmp"
  return "$rc"
}

nb_ingress_state_enforcement() {
  jq -r '.ingress_enforcement // "permissive"' "$1" 2>/dev/null
}

nb_ingress_state_method() {
  jq -r '.ingress_enforcement_method // "wildcard"' "$1" 2>/dev/null
}

nb_ingress_state_local_address() {
  local path="$1" profile_id="$2" value
  value="$(jq -r '.ingress_local_address // empty' "$path" 2>/dev/null || true)"
  if [ -z "$value" ]; then
    value="$(nb_ingress_profile_json "$profile_id" 2>/dev/null | jq -r '.local_address // empty' || true)"
  fi
  printf '%s' "$value"
}

nb_listener_has_local_address() {
  local transport="$1" port="$2" address="$3" flags line field
  command -v ss >/dev/null 2>&1 || return 1
  case "$transport" in
    TCP) flags='-Hln4t' ;;
    UDP) flags='-Hln4u' ;;
    *) return 1 ;;
  esac
  while IFS= read -r line; do
    for field in $line; do
      [ "$field" = "${address}:${port}" ] && return 0
    done
  done < <(ss "$flags" 2>/dev/null)
  return 1
}

nb_wait_for_listener_address() {
  local transport="$1" port="$2" address="$3" timeout="${4:-25}" i=0
  while [ "$i" -lt "$timeout" ]; do
    nb_listener_has_local_address "$transport" "$port" "$address" && return 0
    sleep 1
    i=$((i + 1))
  done
  return 1
}

nb_wait_for_enforced_listener() {
  local policy="${1:-permissive}" method="${2:-wildcard}" transport="$3" port="$4" address="$5" owner="$6" timeout="${7:-25}"
  case "$policy:$method" in
    permissive:wildcard) nb_wait_for_listener "$transport" "$port" "$timeout" ;;
    strict:native-bind) nb_wait_for_listener_address "$transport" "$port" "$address" "$timeout" ;;
    strict:firewall)
      nb_wait_for_listener "$transport" "$port" "$timeout" \
        && nb_strict_firewall_rule_owned "$owner" "$transport" "$port" "$address"
      ;;
    *) return 1 ;;
  esac
}

nb_strict_firewall_empty_state() {
  jq -n --argjson schema "$NOBRAND_SCHEMA_VERSION" \
    '{schema_version:$schema,ownership:"nobrand-v3",feature:"ingress-enforcement-firewall",rules:[]}'
}

nb_strict_firewall_state_valid() {
  local path="${1:-$NOBRAND_INGRESS_FIREWALL_STATE_FILE}" owner transport address
  [ -s "$path" ] || return 1
  jq -e --argjson schema "$NOBRAND_SCHEMA_VERSION" '
    (keys|sort)==["feature","ownership","rules","schema_version"] and
    .schema_version==$schema and .ownership=="nobrand-v3" and
    .feature=="ingress-enforcement-firewall" and (.rules|type)=="array" and
    all(.rules[];
      (keys|sort)==["ingress_profile_id","local_address","owner","port","transport"] and
      (.owner|type)=="string" and (.owner|test("^[A-Za-z0-9:._-]{1,128}$")) and
      (.ingress_profile_id|type)=="string" and (.ingress_profile_id|length)>0 and
      (.local_address|type)=="string" and (.local_address|length)>0 and
      (.transport=="TCP" or .transport=="UDP") and
      (.port|type)=="number" and .port>=1 and .port<=65535 and (.port|floor)==.port) and
    ([.rules[]|(.owner+"|"+.transport+"|"+(.port|tostring))]|length)==
      ([.rules[]|(.owner+"|"+.transport+"|"+(.port|tostring))]|unique|length)
  ' "$path" >/dev/null 2>&1 || return 1
  while IFS=$'\t' read -r owner transport address; do
    [ -n "$owner" ] || continue
    nb_ingress_valid_ipv4 "$address" || return 1
    case "$transport" in TCP|UDP) ;; *) return 1 ;; esac
  done < <(jq -r '.rules[]|[.owner,.transport,.local_address]|@tsv' "$path")
}

nb_strict_firewall_table_owned() {
  local listing
  command -v nft >/dev/null 2>&1 || return 1
  listing="$(nft list table "$NOBRAND_INGRESS_NFT_FAMILY" "$NOBRAND_INGRESS_NFT_TABLE" 2>/dev/null)" \
    || return 1
  grep -Fq 'comment "Owned by NoBrand-OneClick Strict Ingress"' <<<"$listing"
}

nb_strict_firewall_remove_table() {
  command -v nft >/dev/null 2>&1 || return 0
  nft list table "$NOBRAND_INGRESS_NFT_FAMILY" "$NOBRAND_INGRESS_NFT_TABLE" >/dev/null 2>&1 \
    || return 0
  nb_strict_firewall_table_owned || return 1
  nft delete table "$NOBRAND_INGRESS_NFT_FAMILY" "$NOBRAND_INGRESS_NFT_TABLE"
}

nb_strict_firewall_ensure_dependency() {
  command -v nft >/dev/null 2>&1 && return 0
  if declare -F forward_ensure_nftables_dependency >/dev/null 2>&1; then
    forward_ensure_nftables_dependency
  else
    return 1
  fi
}

nb_strict_firewall_generate_ruleset() {
  local state="$1" output="$2" tmp owner transport port address proto
  nb_strict_firewall_state_valid "$state" || return 1
  tmp="$(mktemp_file .ingress-firewall.nft)" || return 1
  {
    printf 'table %s %s {\n' "$NOBRAND_INGRESS_NFT_FAMILY" "$NOBRAND_INGRESS_NFT_TABLE"
    printf '  comment "Owned by NoBrand-OneClick Strict Ingress"\n'
    printf '  chain input {\n    type filter hook input priority -10; policy accept;\n'
    while IFS=$'\t' read -r owner transport port address; do
      [ -n "$owner" ] || continue
      proto="$(printf '%s' "$transport" | tr '[:upper:]' '[:lower:]')"
      printf '    ip daddr != %s %s dport %s drop comment "nobrand:strict:%s:%s"\n' \
        "$address" "$proto" "$port" "$owner" "$proto"
    done < <(jq -r '.rules|sort_by(.owner,.transport,.port)[]|
      [.owner,.transport,(.port|tostring),.local_address]|@tsv' "$state")
    printf '  }\n}\n'
  } >"$tmp" || { rm -f "$tmp"; return 1; }
  mkdir -p "$(dirname "$output")" || { rm -f "$tmp"; return 1; }
  install -m 0600 "$tmp" "$output"
  local rc=$?
  rm -f "$tmp"
  return "$rc"
}

nb_strict_firewall_apply_state() {
  local state="$1" count candidate batch
  nb_strict_firewall_state_valid "$state" || return 1
  [ "${NOBRAND_TEST_STRICT_FIREWALL_APPLY_FAIL:-0}" -eq 0 ] || return 1
  count="$(jq '.rules|length' "$state")" || return 1
  if [ "$count" -eq 0 ]; then
    nb_strict_firewall_remove_table || return 1
    rm -f "$NOBRAND_INGRESS_FIREWALL_RULESET"
    return 0
  fi
  nb_strict_firewall_ensure_dependency || return 1
  candidate="$(mktemp_file .ingress-firewall-candidate.nft)" || return 1
  batch="$(mktemp_file .ingress-firewall-batch.nft)" || { rm -f "$candidate"; return 1; }
  nb_strict_firewall_generate_ruleset "$state" "$candidate" || { rm -f "$candidate" "$batch"; return 1; }
  {
    if nft list table "$NOBRAND_INGRESS_NFT_FAMILY" "$NOBRAND_INGRESS_NFT_TABLE" >/dev/null 2>&1; then
      nb_strict_firewall_table_owned || { rm -f "$candidate" "$batch"; return 1; }
      printf 'delete table %s %s\n' "$NOBRAND_INGRESS_NFT_FAMILY" "$NOBRAND_INGRESS_NFT_TABLE"
    fi
    cat "$candidate"
  } >"$batch"
  nft -c -f "$batch" >/dev/null 2>&1 && nft -f "$batch" \
    && nb_atomic_install_file "$candidate" "$NOBRAND_INGRESS_FIREWALL_RULESET" 0600
  local rc=$?
  rm -f "$candidate" "$batch"
  return "$rc"
}

nb_strict_firewall_current_or_empty() {
  local output="$1"
  if [ -e "$NOBRAND_INGRESS_FIREWALL_STATE_FILE" ]; then
    nb_strict_firewall_state_valid "$NOBRAND_INGRESS_FIREWALL_STATE_FILE" || return 1
    cp -a "$NOBRAND_INGRESS_FIREWALL_STATE_FILE" "$output"
  else
    nb_strict_firewall_empty_state >"$output"
  fi
}

nb_strict_firewall_commit_candidate() {
  local candidate="$1" old old_existed=0 rollback_failed=0
  nb_strict_firewall_state_valid "$candidate" || return 1
  old="$(mktemp_file .ingress-firewall-old)" || return 1
  [ ! -e "$NOBRAND_INGRESS_FIREWALL_STATE_FILE" ] || old_existed=1
  nb_strict_firewall_current_or_empty "$old" || { rm -f "$old"; return 1; }
  if nb_strict_firewall_apply_state "$candidate" \
     && nb_atomic_install_file "$candidate" "$NOBRAND_INGRESS_FIREWALL_STATE_FILE" 0600; then
    rm -f "$old"
    return 0
  fi
  nb_strict_firewall_apply_state "$old" >/dev/null 2>&1 || rollback_failed=1
  if [ "$old_existed" -eq 1 ]; then
    nb_atomic_install_file "$old" "$NOBRAND_INGRESS_FIREWALL_STATE_FILE" 0600 >/dev/null 2>&1 \
      || rollback_failed=1
  else
    rm -f "$NOBRAND_INGRESS_FIREWALL_STATE_FILE" || rollback_failed=1
  fi
  rm -f "$old"
  [ "$rollback_failed" -eq 0 ] || warn '严格 Ingress 防火墙回滚失败；请立即运行诊断 / Doctor'
  return 1
}

nb_strict_firewall_rule_owned() {
  local owner="$1" transport="$2" port="$3" address="$4" listing proto
  nb_strict_firewall_state_valid "$NOBRAND_INGRESS_FIREWALL_STATE_FILE" || return 1
  jq -e --arg owner "$owner" --arg transport "$transport" --arg address "$address" \
    --argjson port "$port" \
    'any(.rules[];.owner==$owner and .transport==$transport and .port==$port and .local_address==$address)' \
    "$NOBRAND_INGRESS_FIREWALL_STATE_FILE" >/dev/null || return 1
  nb_strict_firewall_table_owned || return 1
  listing="$(nft list table "$NOBRAND_INGRESS_NFT_FAMILY" "$NOBRAND_INGRESS_NFT_TABLE" 2>/dev/null)" \
    || return 1
  proto="$(printf '%s' "$transport" | tr '[:upper:]' '[:lower:]')"
  grep -Fq "nobrand:strict:${owner}:${proto}" <<<"$listing" \
    && grep -Fq "ip daddr != ${address}" <<<"$listing"
}

nb_strict_firewall_clear_all() {
  local empty
  empty="$(mktemp_file .ingress-firewall-empty)" || return 1
  nb_strict_firewall_empty_state >"$empty"
  nb_strict_firewall_commit_candidate "$empty"
  local rc=$?
  rm -f "$empty"
  return "$rc"
}

nb_strict_firewall_restore_authoritative() {
  local state tmp
  if [ -e "$NOBRAND_INGRESS_FIREWALL_STATE_FILE" ]; then
    state="$NOBRAND_INGRESS_FIREWALL_STATE_FILE"
    nb_strict_firewall_state_valid "$state" || return 1
  else
    tmp="$(mktemp_file .ingress-firewall-restore-empty)" || return 1
    nb_strict_firewall_empty_state >"$tmp"
    state="$tmp"
  fi
  nb_strict_firewall_apply_state "$state"
  local rc=$?
  [ -z "${tmp:-}" ] || rm -f "$tmp"
  return "$rc"
}

nb_ingress_profile_name() {
  local profile_id="${1:-}" name
  if [ -z "$profile_id" ] || [ "$profile_id" = "$NOBRAND_LEGACY_INGRESS_PROFILE_ID" ]; then
    printf '旧版兼容默认路由'
    return 0
  fi
  name="$(nb_ingress_profile_json "$profile_id" 2>/dev/null | jq -r '.name // empty' 2>/dev/null || true)"
  [ -n "$name" ] && printf '%s' "$name" || printf '未知入口配置'
}

nb_ingress_profile_display_host() {
  local profile_id="${1:-}" profile
  [ -n "$profile_id" ] || return 1
  [ "$profile_id" != "$NOBRAND_LEGACY_INGRESS_PROFILE_ID" ] || return 1
  profile="$(nb_ingress_profile_json "$profile_id")" || return 1
  jq -r '.display_host_default // empty' <<<"$profile"
}

nb_ingress_profile_display_port() {
  local profile_id="$1" actual_port="$2" profile policy
  profile="$(nb_ingress_profile_json "$profile_id")" || { printf '%s' "$actual_port"; return 0; }
  policy="$(jq -r .display_port_policy <<<"$profile")"
  if [ "$policy" = custom ]; then jq -r .display_port <<<"$profile"; else printf '%s' "$actual_port"; fi
}

nb_ingress_normalize_reserved() {
  local raw="${1:-}" item canonical output="" seen='|'
  raw="${raw//,/ }"
  for item in $raw; do
    canonical="$(normalize_uint "$item" 2>/dev/null || true)"
    nb_valid_port "$canonical" || return 1
    case "$seen" in *"|${canonical}|"*) continue ;; esac
    seen="${seen}${canonical}|"
    output="${output}${output:+,}${canonical}"
  done
  printf '%s' "$output"
}

nb_ingress_reserved_json() {
  local normalized item json='[]'
  normalized="$(nb_ingress_normalize_reserved "${1:-}")" || return 1
  for item in ${normalized//,/ }; do
    json="$(jq --argjson value "$item" '. + [$value]' <<<"$json")" || return 1
  done
  printf '%s' "$json"
}

nb_ingress_validate_profile_values() {
  local type="$1" interface="$2" address="$3" policy="$4" range_start="$5" range_end="$6"
  local reserved="$7" display_host="$8" display_port_policy="$9" display_port="${10}" enforcement="${11:-permissive}" base item
  local interface_rows="${12-}" interface_rows_supplied=0
  [ "$#" -lt 12 ] || interface_rows_supplied=1
  case "$type" in public|mapped) ;; *) return 1 ;; esac
  if [ "$interface_rows_supplied" -eq 1 ]; then
    nb_ingress_interface_exists "$interface" "$interface_rows" || return 1
    nb_ingress_address_on_interface "$interface" "$address" "$interface_rows" || return 1
  else
    nb_ingress_interface_exists "$interface" || return 1
    nb_ingress_address_on_interface "$interface" "$address" || return 1
  fi
  case "$policy" in
    derived-tail)
      base="$(nb_port_base_for_ip "$address")" || return 1
      [ -z "$range_start$range_end" ] || return 1
      ;;
    custom-range)
      nb_valid_port "$range_start" && nb_valid_port "$range_end" || return 1
      range_start="$(normalize_uint "$range_start")"; range_end="$(normalize_uint "$range_end")"
      [ "$range_start" -ge 1025 ] && [ "$range_start" -le "$range_end" ] || return 1
      ;;
    manual-only) [ -z "$range_start$range_end" ] || return 1 ;;
    *) return 1 ;;
  esac
  reserved="$(nb_ingress_normalize_reserved "$reserved")" || return 1
  for item in ${reserved//,/ }; do nb_valid_port "$item" || return 1; done
  if [ "$type" = mapped ]; then valid_advertise_host "$display_host" || return 1; fi
  [ -z "$display_host" ] || valid_advertise_host "$display_host" || return 1
  case "$display_port_policy" in
    follow-actual) [ -z "$display_port" ] || return 1 ;;
    custom) valid_advertise_port "$display_port" || return 1 ;;
    *) return 1 ;;
  esac
  case "$enforcement" in permissive|strict) ;; *) return 1 ;; esac
}

nb_ingress_reserved_conflicts() {
  local reserved="${1:-}" owner transport port _host _display item
  while IFS='|' read -r owner transport port _host _display; do
    [ -n "$owner" ] || continue
    for item in ${reserved//,/ }; do
      if [ "$port" = "$item" ]; then printf '%s|%s|%s' "$owner" "$transport" "$port"; return 0; fi
    done
  done < <(nb_registry_rows)
  return 1
}

nb_ingress_mark_lifecycle_mutation() {
  if [ "${NOBRAND_LIFECYCLE_ACTIVE:-0}" -eq 1 ] \
     && [ "${NOBRAND_LIFECYCLE_OPERATION:-}" = configure ] \
     && [ "${NOBRAND_LIFECYCLE_SCOPE:-}" = ingress ] \
     && [ "${NOBRAND_LIFECYCLE_MUTATION_STARTED:-0}" -ne 1 ]; then
    nb_lifecycle_mark_mutation_started || return 1
  fi
}

nb_ingress_prepare_add_request() {
  local base="" conflict="" enabled normalized interface_rows=""
  if [ "$#" -ge 1 ]; then
    interface_rows="$1"
  else
    interface_rows="$(nb_ingress_interface_rows)"
  fi
  [ -n "${INGRESS_NAME:-}" ] && [ -n "${INGRESS_TYPE:-}" ] \
    && [ -n "${INGRESS_INTERFACE:-}" ] && [ -n "${INGRESS_ADDRESS:-}" ] \
    && [ -n "${INGRESS_PORT_POLICY:-}" ] \
    || die 'Ingress Profile 需要名称、类型、网络接口、本地 IPv4 和端口策略' \
    || return 1
  [ "${#INGRESS_NAME}" -le 64 ] && ! has_control_chars "$INGRESS_NAME" \
    || die 'Ingress Profile 名称无效' || return 1
  case "$INGRESS_NAME" in
    "$NOBRAND_LEGACY_INGRESS_PROFILE_ID"|'Legacy Default Route')
      die 'Ingress Profile 名称与保留选择器冲突' || return 1
      ;;
  esac
  [[ ! "$INGRESS_NAME" =~ ^i[0-9a-f]{16}$ ]] \
    || die 'Ingress Profile 名称与 Profile ID 命名空间冲突' || return 1

  INGRESS_DISPLAY_PORT_POLICY="${INGRESS_DISPLAY_PORT_POLICY:-follow-actual}"
  INGRESS_ENFORCEMENT="${INGRESS_ENFORCEMENT:-permissive}"
  enabled="${INGRESS_ENABLED:-true}"
  case "$enabled" in
    true|false) INGRESS_ENABLED="$enabled" ;;
    *) die 'Ingress 启用状态无效' || return 1 ;;
  esac
  if [ "$INGRESS_TYPE" = public ] && [ -z "${INGRESS_DISPLAY_HOST_DEFAULT:-}" ]; then
    INGRESS_DISPLAY_HOST_DEFAULT="$INGRESS_ADDRESS"
  fi

  nb_ingress_interface_exists "$INGRESS_INTERFACE" "$interface_rows" \
    || die "网络接口不存在或没有可用的非回环 IPv4: ${INGRESS_INTERFACE}" || return 1
  nb_ingress_address_on_interface "$INGRESS_INTERFACE" "$INGRESS_ADDRESS" "$interface_rows" \
    || die "所选本地 IPv4 未配置在网络接口 ${INGRESS_INTERFACE} 上: ${INGRESS_ADDRESS}" || return 1
  if [ "$INGRESS_PORT_POLICY" = derived-tail ]; then
    base="$(nb_port_base_for_ip "$INGRESS_ADDRESS" 2>/dev/null || true)"
    [ -n "$base" ] \
      || die '此 IPv4 无法使用 derived-tail；请改用 custom-range 或 manual-only' || return 1
    if [ "${INGRESS_RESERVED_CLI:-0}" -eq 0 ]; then
      INGRESS_RESERVED_PORTS="$base"
    fi
  fi

  nb_ingress_validate_profile_values "$INGRESS_TYPE" "$INGRESS_INTERFACE" "$INGRESS_ADDRESS" \
    "$INGRESS_PORT_POLICY" "${INGRESS_RANGE_START:-}" "${INGRESS_RANGE_END:-}" \
    "${INGRESS_RESERVED_PORTS:-}" "${INGRESS_DISPLAY_HOST_DEFAULT:-}" \
    "$INGRESS_DISPLAY_PORT_POLICY" "${INGRESS_DISPLAY_PORT:-}" "$INGRESS_ENFORCEMENT" "$interface_rows" \
    || die 'Ingress Profile 参数无效' || return 1
  normalized="$(nb_ingress_normalize_reserved "${INGRESS_RESERVED_PORTS:-}")" \
    || die 'Ingress 保留端口列表无效' || return 1
  INGRESS_RESERVED_PORTS="$normalized"
  if conflict="$(nb_ingress_reserved_conflicts "$INGRESS_RESERVED_PORTS" 2>/dev/null)"; then
    die "保留端口与现有受管监听冲突: ${conflict}" || return 1
  fi
  return 0
}

nb_ingress_add() {
  local id now reserved_json range_start_json=null range_end_json=null display_port_json=null tmp profile enabled
  require_root || return 1
  nb_ingress_prepare_add_request || return 1
  enabled="$INGRESS_ENABLED"
  if [ -e "$NOBRAND_INGRESS_STATE_FILE" ]; then
    nb_ingress_ensure_state || return 1
    jq -e --arg name "$INGRESS_NAME" 'all(.profiles[];.name!=$name)' "$NOBRAND_INGRESS_STATE_FILE" >/dev/null \
      || die "Ingress Profile 名称已存在: ${INGRESS_NAME}" || return 1
  else
    nb_ingress_mark_lifecycle_mutation || return 1
    nb_ingress_ensure_state || return 1
  fi
  id="$(nb_ingress_generate_id)" || return 1
  now="$(nb_ingress_now)"
  reserved_json="$(nb_ingress_reserved_json "$INGRESS_RESERVED_PORTS")" || return 1
  if [ "$INGRESS_PORT_POLICY" = custom-range ]; then
    range_start_json="$(normalize_uint "$INGRESS_RANGE_START")"
    range_end_json="$(normalize_uint "$INGRESS_RANGE_END")"
  fi
  [ "$INGRESS_DISPLAY_PORT_POLICY" != custom ] || display_port_json="$(normalize_uint "$INGRESS_DISPLAY_PORT")"
  profile="$(jq -n --arg id "$id" --arg name "$INGRESS_NAME" --arg type "$INGRESS_TYPE" \
    --arg interface "$INGRESS_INTERFACE" --arg address "$INGRESS_ADDRESS" \
    --arg policy "$INGRESS_PORT_POLICY" --argjson range_start "$range_start_json" \
    --argjson range_end "$range_end_json" --argjson reserved "$reserved_json" \
    --arg display_host "$INGRESS_DISPLAY_HOST_DEFAULT" \
    --arg display_port_policy "$INGRESS_DISPLAY_PORT_POLICY" --argjson display_port "$display_port_json" \
    --arg enforcement "$INGRESS_ENFORCEMENT" --arg now "$now" --argjson enabled "$enabled" '
      {profile_id:$id,name:$name,type:$type,interface:$interface,local_address:$address,
       port_policy:$policy,range_start:$range_start,range_end:$range_end,reserved_ports:$reserved,
       display_host_default:$display_host,display_port_policy:$display_port_policy,display_port:$display_port,
       ingress_enforcement:$enforcement,enabled:$enabled,created_at:$now,updated_at:$now}
    ')" || return 1
  tmp="$(mktemp_file .ingress-add)" || return 1
  jq --argjson profile "$profile" '.profiles += [$profile]' "$NOBRAND_INGRESS_STATE_FILE" >"$tmp" \
    && nb_ingress_state_valid "$tmp"
  local rc=$?
  if [ "$rc" -eq 0 ]; then
    nb_ingress_mark_lifecycle_mutation \
      && nb_atomic_install_file "$tmp" "$NOBRAND_INGRESS_STATE_FILE" 0600 || rc=$?
  fi
  rm -f "$tmp"
  [ "$rc" -ne 0 ] || printf '已创建 Ingress Profile: %s (%s)\n' "$id" "$INGRESS_NAME"
  return "$rc"
}

nb_ingress_profile_reference_rows() {
  local profile_id="$1"
  NOBRAND_VLESS_STATE_FILE="$NOBRAND_VLESS_STATE_FILE" \
  NOBRAND_SSH_STATE_FILE="$NOBRAND_SSH_STATE_FILE" NOBRAND_FORWARD_STATE_FILE="$NOBRAND_FORWARD_STATE_FILE" \
  NOBRAND_SPLICORE_DESIRED="${NOBRAND_STATE_DIR}/splicore/current/desired.json" python3 - "$profile_id" <<'PY'
import json, os, sys
profile = sys.argv[1]
def load(path):
    try: return json.load(open(path, encoding="utf-8"))
    except Exception: return None
def emit(owner, value):
    if not value: return
    if profile == "*": print(str(value) + "|" + owner)
    elif value == profile: print(owner)
state=load(os.environ.get("NOBRAND_VLESS_STATE_FILE", ""))
if state: emit("vless-sudoku:default", state.get("ingress_profile_id"))
state=load(os.environ.get("NOBRAND_SPLICORE_DESIRED", ""))
if state:
    for node in state.get("nodes", []):
        emit("splicore:" + node["id"], node.get("ingress", {}).get("profile_id"))
state=load(os.environ.get("NOBRAND_SSH_STATE_FILE", ""))
if state:
    emit("ssh-tunnel:policy", state.get("ingress_profile_id"))
    for user in state.get("users") or []:
        emit("ssh-tunnel:" + str(user.get("account_id") or user.get("label")), user.get("ingress_profile_id"))
state=load(os.environ.get("NOBRAND_FORWARD_STATE_FILE", ""))
if state:
    for rule in state.get("rules") or []:
        emit("forward:" + str(rule.get("rule_id")), rule.get("ingress_profile_id"))

PY
}

nb_ingress_delete() {
  local id refs tmp
  require_root || return 1
  id="$(nb_ingress_profile_id "$INGRESS_PROFILE_SELECTOR" 2>/dev/null || true)"
  [ -n "$id" ] && [ "$id" != "$NOBRAND_LEGACY_INGRESS_PROFILE_ID" ] \
    || die '找不到 Ingress Profile，或内置 Profile 不允许删除' || return 1
  refs="$(nb_ingress_profile_reference_rows "$id")"
  [ -z "$refs" ] || { printf 'Ingress Profile 正被以下对象引用:\n%s\n' "$refs" >&2; return 1; }
  tmp="$(mktemp_file .ingress-delete)" || return 1
  jq --arg id "$id" '
    .profiles |= map(select(.profile_id!=$id)) |
    if .default_profile_id==$id then .default_profile_id=null else . end
  ' "$NOBRAND_INGRESS_STATE_FILE" >"$tmp" && nb_ingress_state_valid "$tmp"
  local rc=$?
  if [ "$rc" -eq 0 ]; then
    nb_ingress_mark_lifecycle_mutation \
      && nb_atomic_install_file "$tmp" "$NOBRAND_INGRESS_STATE_FILE" 0600 || rc=$?
  fi
  rm -f "$tmp"
  return "$rc"
}

nb_ingress_modify() {
  local id old name type interface address policy range_start range_end reserved display_host display_policy display_port enabled enforcement
  local old_enforcement old_interface old_address runtime_change=0 refs="" snapshot=""
  local base reserved_json range_start_json=null range_end_json=null display_port_json=null conflict tmp
  require_root || return 1
  id="$(nb_ingress_profile_id "$INGRESS_PROFILE_SELECTOR" 2>/dev/null || true)"
  [ -n "$id" ] && [ "$id" != "$NOBRAND_LEGACY_INGRESS_PROFILE_ID" ] \
    || die '找不到 Ingress Profile，或内置 Profile 不允许修改' || return 1
  old="$(nb_ingress_profile_json "$id")"
  name="$(jq -r .name <<<"$old")"; type="$(jq -r .type <<<"$old")"
  interface="$(jq -r .interface <<<"$old")"; address="$(jq -r .local_address <<<"$old")"
  old_interface="$interface"; old_address="$address"
  policy="$(jq -r .port_policy <<<"$old")"
  range_start="$(jq -r '.range_start // empty' <<<"$old")"; range_end="$(jq -r '.range_end // empty' <<<"$old")"
  reserved="$(jq -r '.reserved_ports|join(",")' <<<"$old")"
  display_host="$(jq -r .display_host_default <<<"$old")"; display_policy="$(jq -r .display_port_policy <<<"$old")"
  display_port="$(jq -r '.display_port // empty' <<<"$old")"; enabled="$(jq -r .enabled <<<"$old")"
  enforcement="$(jq -r '.ingress_enforcement // "permissive"' <<<"$old")"; old_enforcement="$enforcement"
  [ "$INGRESS_NAME_CLI" -eq 0 ] || name="$INGRESS_NAME"
  [ "$INGRESS_TYPE_CLI" -eq 0 ] || type="$INGRESS_TYPE"
  [ "$INGRESS_INTERFACE_CLI" -eq 0 ] || interface="$INGRESS_INTERFACE"
  [ "$INGRESS_ADDRESS_CLI" -eq 0 ] || address="$INGRESS_ADDRESS"
  if [ "$INGRESS_PORT_POLICY_CLI" -eq 1 ]; then
    policy="$INGRESS_PORT_POLICY"; range_start=""; range_end=""
  fi
  [ "$INGRESS_RANGE_START_CLI" -eq 0 ] || range_start="$INGRESS_RANGE_START"
  [ "$INGRESS_RANGE_END_CLI" -eq 0 ] || range_end="$INGRESS_RANGE_END"
  [ "$INGRESS_RESERVED_CLI" -eq 0 ] || reserved="$INGRESS_RESERVED_PORTS"
  [ "$INGRESS_DISPLAY_HOST_CLI" -eq 0 ] || display_host="$INGRESS_DISPLAY_HOST_DEFAULT"
  if [ "$INGRESS_DISPLAY_PORT_POLICY_CLI" -eq 1 ]; then
    display_policy="$INGRESS_DISPLAY_PORT_POLICY"; display_port=""
  fi
  [ "$INGRESS_DISPLAY_PORT_CLI" -eq 0 ] || display_port="$INGRESS_DISPLAY_PORT"
  [ "$INGRESS_ENABLED_CLI" -eq 0 ] || enabled="$INGRESS_ENABLED"
  [ "$INGRESS_ENFORCEMENT_CLI" -eq 0 ] || enforcement="$INGRESS_ENFORCEMENT"
  case "$name" in
    "$NOBRAND_LEGACY_INGRESS_PROFILE_ID"|'Legacy Default Route')
      die 'Ingress Profile 名称与保留选择器冲突' || return 1
      ;;
  esac
  [[ ! "$name" =~ ^i[0-9a-f]{16}$ ]] \
    || die 'Ingress Profile 名称与 Profile ID 命名空间冲突' || return 1
  if [ "$enabled" = false ] \
     && [ "$(nb_ingress_default_profile_id 2>/dev/null || true)" = "$id" ]; then
    die '请先取消默认 Ingress Profile，再将其禁用' || return 1
  fi
  if [ "$policy" = derived-tail ]; then
    base="$(nb_port_base_for_ip "$address" 2>/dev/null || true)"
    [ -n "$base" ] || die '此 IPv4 无法使用 derived-tail；请改用 custom-range 或 manual-only' || return 1
    [ "$INGRESS_PORT_POLICY_CLI" -eq 0 ] || [ "$INGRESS_RESERVED_CLI" -eq 1 ] || reserved="$base"
  fi
  [ "$policy" = custom-range ] || { range_start=""; range_end=""; }
  [ "$display_policy" = custom ] || display_port=""
  nb_ingress_validate_profile_values "$type" "$interface" "$address" "$policy" "$range_start" "$range_end" \
    "$reserved" "$display_host" "$display_policy" "$display_port" "$enforcement" \
    || die '修改后的 Ingress Profile 参数无效' || return 1
  reserved="$(nb_ingress_normalize_reserved "$reserved")" || return 1
  if conflict="$(nb_ingress_reserved_conflicts "$reserved" 2>/dev/null)"; then
    die "保留端口与现有受管监听冲突: ${conflict}" || return 1
  fi
  jq -e --arg id "$id" --arg name "$name" 'all(.profiles[]; .profile_id==$id or .name!=$name)' \
    "$NOBRAND_INGRESS_STATE_FILE" >/dev/null || die "Ingress Profile 名称已存在: ${name}" || return 1
  reserved_json="$(nb_ingress_reserved_json "$reserved")" || return 1
  if [ "$policy" = custom-range ]; then range_start_json="$range_start"; range_end_json="$range_end"; fi
  [ "$display_policy" != custom ] || display_port_json="$display_port"
  if [ "$old_enforcement" != "$enforcement" ] \
     || { [ "$enforcement" = strict ] \
          && { [ "$old_interface" != "$interface" ] || [ "$old_address" != "$address" ]; }; }; then
    runtime_change=1
  fi
  if [ "$runtime_change" -eq 1 ]; then
    refs="$(nb_ingress_profile_reference_rows "$id" | grep -Ev '^ssh-tunnel:' || true)"
    if [ -n "$refs" ] && [ "${INGRESS_APPLY_EXISTING:-0}" -ne 1 ]; then
      printf 'Ingress 强制策略或监听身份变化会影响以下受管节点:\n%s\n' "$refs" >&2
      die '请使用 --apply-existing 重新运行，以明确执行事务迁移' || return 1
    fi
  fi
  tmp="$(mktemp_file .ingress-modify)" || return 1
  jq --arg id "$id" --arg name "$name" --arg type "$type" --arg interface "$interface" --arg address "$address" \
    --arg policy "$policy" --argjson range_start "$range_start_json" --argjson range_end "$range_end_json" \
    --argjson reserved "$reserved_json" --arg display_host "$display_host" --arg display_policy "$display_policy" \
    --argjson display_port "$display_port_json" --arg enforcement "$enforcement" \
    --argjson enabled "$enabled" --arg updated "$(nb_ingress_now)" '
      (.profiles[]|select(.profile_id==$id)) |=
       (.name=$name|.type=$type|.interface=$interface|.local_address=$address|.port_policy=$policy|
        .range_start=$range_start|.range_end=$range_end|.reserved_ports=$reserved|
        .display_host_default=$display_host|.display_port_policy=$display_policy|.display_port=$display_port|
        .ingress_enforcement=$enforcement|.enabled=$enabled|.updated_at=$updated)
    ' "$NOBRAND_INGRESS_STATE_FILE" >"$tmp" \
    && nb_ingress_state_valid "$tmp"
  local rc=$?
  if [ "$rc" -eq 0 ]; then
    snapshot="$(mktemp_file .ingress-profile-rollback)" || rc=1
  fi
  if [ "$rc" -eq 0 ]; then
    cp -a "$NOBRAND_INGRESS_STATE_FILE" "$snapshot" || rc=1
  fi
  if [ "$rc" -eq 0 ]; then
    nb_ingress_mark_lifecycle_mutation \
      && nb_atomic_install_file "$tmp" "$NOBRAND_INGRESS_STATE_FILE" 0600 || rc=1
  fi
  if [ "$rc" -eq 0 ] && [ "$runtime_change" -eq 1 ] && [ -n "$refs" ]; then
    if ! nb_ingress_apply_profile "$id"; then
      nb_atomic_install_file "$snapshot" "$NOBRAND_INGRESS_STATE_FILE" 0600 >/dev/null 2>&1 || true
      nb_ingress_apply_profile "$id" >/dev/null 2>&1 \
        || warn 'Ingress Profile 元数据已恢复，但一个或多个监听回滚失败；请立即运行 Doctor / 诊断'
      rc=1
    fi
  fi
  rm -f "$tmp"
  [ -z "$snapshot" ] || rm -f "$snapshot"
  return "$rc"
}

nb_ingress_set_default() {
  local id tmp
  require_root || return 1
  id="$(nb_ingress_profile_id "$INGRESS_PROFILE_SELECTOR" 2>/dev/null || true)"
  [ -n "$id" ] && [ "$id" != "$NOBRAND_LEGACY_INGRESS_PROFILE_ID" ] \
    || die '默认 Ingress 必须是显式创建且已启用的 Profile' || return 1
  [ "$(nb_ingress_profile_json "$id" | jq -r .enabled)" = true ] \
    || die '已禁用的 Ingress Profile 不能设为默认' || return 1
  nb_ingress_ensure_state || return 1
  tmp="$(mktemp_file .ingress-default)" || return 1
  jq --arg id "$id" '.default_profile_id=$id' "$NOBRAND_INGRESS_STATE_FILE" >"$tmp" \
    && nb_ingress_state_valid "$tmp"
  local rc=$?
  if [ "$rc" -eq 0 ]; then
    nb_ingress_mark_lifecycle_mutation \
      && nb_atomic_install_file "$tmp" "$NOBRAND_INGRESS_STATE_FILE" 0600 || rc=$?
  fi
  rm -f "$tmp"
  return "$rc"
}

nb_ingress_unset_default() {
  local tmp
  require_root || return 1
  if [ -e "$NOBRAND_INGRESS_STATE_FILE" ]; then
    nb_ingress_ensure_state || return 1
  else
    nb_ingress_mark_lifecycle_mutation || return 1
    nb_ingress_ensure_state || return 1
  fi
  tmp="$(mktemp_file .ingress-default)" || return 1
  jq '.default_profile_id=null' "$NOBRAND_INGRESS_STATE_FILE" >"$tmp" \
    && nb_ingress_state_valid "$tmp"
  local rc=$?
  if [ "$rc" -eq 0 ]; then
    nb_ingress_mark_lifecycle_mutation \
      && nb_atomic_install_file "$tmp" "$NOBRAND_INGRESS_STATE_FILE" 0600 || rc=$?
  fi
  rm -f "$tmp"
  return "$rc"
}

nb_ingress_profile_auto_range() {
  local profile_id="$1" profile policy address base
  profile="$(nb_ingress_profile_json "$profile_id")" || return 1
  policy="$(jq -r .port_policy <<<"$profile")"
  case "$policy" in
    derived-tail)
      address="$(jq -r .local_address <<<"$profile")"
      if [ "$profile_id" = "$NOBRAND_LEGACY_INGRESS_PROFILE_ID" ]; then
        nb_tail_port_bounds "$address"
      else
        base="$(nb_port_base_for_ip "$address")" || return 1
        printf '%s|%s' "$((base + 1))" "$((base + 99))"
      fi
      ;;
    custom-range) jq -r '[.range_start,.range_end]|join("|")' <<<"$profile" ;;
    manual-only) return 2 ;;
    *) return 1 ;;
  esac
}

nb_ingress_port_is_reserved() {
  local profile_id="$1" port profile
  port="$(normalize_uint "$2")" || return 1
  if [ -z "$profile_id" ] || [ "$profile_id" = "$NOBRAND_LEGACY_INGRESS_PROFILE_ID" ]; then
    nb_port_is_tail_base_reserved "$port"
    return $?
  fi
  profile="$(nb_ingress_profile_json "$profile_id")" || return 1
  jq -e --argjson port "$port" 'any(.reserved_ports[]; .==$port)' <<<"$profile" >/dev/null
}

nb_ingress_type_label() {
  case "${1:-}" in
    public) printf '公网 / public' ;;
    mapped) printf '映射 / mapped' ;;
    built-in) printf '内置 / built-in' ;;
    *) printf '%s' "${1:-未知}" ;;
  esac
}

nb_ingress_port_policy_label() {
  case "${1:-}" in
    derived-tail) printf '尾号推导 / derived-tail' ;;
    custom-range) printf '自定义范围 / custom-range' ;;
    manual-only) printf '仅手动 / manual-only' ;;
    *) printf '%s' "${1:-未知}" ;;
  esac
}

nb_ingress_enforcement_label() {
  case "${1:-}" in
    permissive) printf '宽松 / permissive' ;;
    strict) printf '严格 / strict' ;;
    *) printf '%s' "${1:-未知}" ;;
  esac
}

nb_ingress_display_port_policy_label() {
  case "${1:-}" in
    follow-actual) printf '跟随实际端口 / follow-actual' ;;
    custom) printf '自定义 / custom' ;;
    *) printf '%s' "${1:-未知}" ;;
  esac
}

nb_ingress_list() {
  local default_id id name type interface address policy enforcement is_default range
  default_id="$(nb_ingress_default_profile_id 2>/dev/null || true)"
  printf '%-19s %-24s %-8s %-12s %-15s %-14s %-11s %-13s %s\n' \
    ID 名称 类型 网络接口 本地地址 端口策略 强制策略 自动范围 默认
  printf '%-19s %-24s %-8s %-12s %-15s %-14s %-11s %-13s %s\n' \
    "$NOBRAND_LEGACY_INGRESS_PROFILE_ID" '旧版兼容默认路由' "$(nb_ingress_type_label built-in)" '(系统)' \
    "$(nb_detect_local_ipv4 2>/dev/null || printf '不可用')" "$(nb_ingress_port_policy_label derived-tail)" \
    "$(nb_ingress_enforcement_label permissive)" \
    "$(nb_ingress_profile_auto_range "$NOBRAND_LEGACY_INGRESS_PROFILE_ID" 2>/dev/null | tr '|' '-' || printf '回退 / fallback')" \
    "$([ -z "$default_id" ] && printf '是' || printf '否')"
  nb_ingress_state_valid || return 0
  while IFS=$'\t' read -r id name type interface address policy enforcement is_default; do
        range="$(nb_ingress_profile_auto_range "$id" 2>/dev/null | tr '|' '-' || printf '仅手动 / manual-only')"
        [ "$is_default" = yes ] && is_default='是' || is_default='否'
        printf '%-19s %-24s %-8s %-12s %-15s %-14s %-11s %-13s %s\n' \
          "$id" "$name" "$(nb_ingress_type_label "$type")" "$interface" "$address" \
          "$(nb_ingress_port_policy_label "$policy")" "$(nb_ingress_enforcement_label "$enforcement")" \
          "$range" "$is_default"
  done < <(jq -r --arg default "$default_id" '.profiles|sort_by(.name)[]|[
    .profile_id,.name,.type,.interface,.local_address,.port_policy,(.ingress_enforcement // "permissive"),
    (if .profile_id==$default then "yes" else "no" end)]|@tsv' "$NOBRAND_INGRESS_STATE_FILE")
}

nb_ingress_show() {
  local profile selector="${INGRESS_PROFILE_SELECTOR:-}" range type policy enforcement display_policy
  profile="$(nb_ingress_profile_json "$selector")" || die "找不到 Ingress Profile: ${selector}" || return 1
  range="$(nb_ingress_profile_auto_range "$(jq -r .profile_id <<<"$profile")" 2>/dev/null | tr '|' '-' || printf '无')"
  type="$(nb_ingress_type_label "$(jq -r .type <<<"$profile")")"
  policy="$(nb_ingress_port_policy_label "$(jq -r .port_policy <<<"$profile")")"
  enforcement="$(nb_ingress_enforcement_label "$(jq -r '.ingress_enforcement // "permissive"' <<<"$profile")")"
  display_policy="$(nb_ingress_display_port_policy_label "$(jq -r .display_port_policy <<<"$profile")")"
  jq -r --arg range "$range" --arg type "$type" --arg policy "$policy" \
    --arg enforcement "$enforcement" --arg display_policy "$display_policy" '
    "ID: \(.profile_id)\n名称: \(.name)\n类型: \($type)\n网络接口 / Interface: \(.interface)\n本地地址: \(.local_address)\n"+
    "端口策略: \($policy)\nIngress 强制策略: \($enforcement)\n自动范围: \($range)\n保留端口: \(.reserved_ports|join(","))\n"+
    "默认展示主机 / Display Host: \(.display_host_default)\n展示端口策略: \($display_policy)"+
    (if .display_port==null then "" else "\n展示端口 / Display Port: \(.display_port)" end)+"\n启用状态: \(if .enabled then "已启用" else "已禁用" end)"
  ' <<<"$profile"
}

nb_ingress_owner_capability() {
  case "$1" in
    splicore:*|vless-sudoku:*) printf native-bind ;;
    forward:*)
      if [ "$(nb_owner_ingress_method "$1" 2>/dev/null || true)" = address-match ]; then
        printf address-match
      elif [ "$(jq -r --arg id "${1#forward:}" '.rules[]|select(.rule_id==$id)|.backend // empty' \
          "$NOBRAND_FORWARD_STATE_FILE" 2>/dev/null || true)" = nftables ]; then
        printf address-match
      else
        printf native-bind
      fi
      ;;
    ssh-tunnel:*) printf not-applicable ;;
    *) return 1 ;;
  esac
}

nb_ingress_apply_owner() {
  local owner="$1"
  case "$owner" in
    splicore:*)
      local profile_id
      profile_id="$(nb_owner_ingress_profile_id "$owner")" || return 1
      nb_prepare_ingress_deployment "$profile_id" native-bind || return 1
      NOBRAND_SPLICORE_LISTEN="$INGRESS_LISTEN_HOST" nb_splicore_call protocol --protocol "$(jq -r --arg id "${owner#splicore:}" '.nodes[]|select(.id==$id)|.protocol' "${NOBRAND_STATE_DIR}/splicore/current/desired.json")" --operation set-listen --selector "${owner#splicore:}"
      ;;
    vless-sudoku:*) vless_sudoku_apply_ingress_enforcement ;;
    forward:*) forward_apply_ingress_enforcement "${owner#forward:}" ;;
    ssh-tunnel:*) return 0 ;;
    *) return 1 ;;
  esac
}

nb_ingress_apply_profile() {
  local profile_id="$1" owner owners failed=0 seen='|'
  nb_ingress_profile_json "$profile_id" >/dev/null || return 1
  owners="$(nb_ingress_profile_reference_rows "$profile_id")" || return 1
  while IFS= read -r owner; do
    [ -n "$owner" ] || continue
    case "$seen" in *"|${owner}|"*) continue ;; esac
    seen="${seen}${owner}|"
    case "$owner" in ssh-tunnel:*) continue ;; esac
    if ! nb_ingress_apply_owner "$owner"; then
      warn "${owner} 的 Ingress 强制策略迁移失败"
      failed=1
      break
    fi
  done <<<"$owners"
  return "$failed"
}

nb_ingress_apply() {
  local id
  require_root || return 1
  id="$(nb_ingress_profile_id "$INGRESS_PROFILE_SELECTOR" 2>/dev/null || true)"
  [ -n "$id" ] && [ "$id" != "$NOBRAND_LEGACY_INGRESS_PROFILE_ID" ] \
    || die '找不到 Ingress Profile，或内置 Profile 不允许应用' || return 1
  nb_ingress_mark_lifecycle_mutation || return 1
  nb_ingress_apply_profile "$id" || return 1
  printf '已应用 Ingress 强制策略: %s (%s)\n' "$id" "$(nb_ingress_profile_name "$id")"
}

nb_ingress_doctor() {
  local failed=0 default_id profile id name interface address policy range port owner refs egress
  local referenced_profile referenced_owner transport key seen='|' profile_id lo hi duplicate_count=0
  local _advertise_host _advertise_port expected_policy expected_method actual_policy actual_method actual_address capability enabled
  if [ ! -e "$NOBRAND_INGRESS_STATE_FILE" ]; then
    nb_doctor_line PASS 'Ingress 状态兼容旧版（没有显式 Profile）'
  elif nb_ingress_state_valid; then
    nb_doctor_line PASS 'Ingress Profile JSON / 状态有效（schema v3）'
  else
    nb_doctor_line FAIL 'Ingress Profile JSON / 状态无效'
    return 1
  fi
  default_id="$(nb_ingress_default_profile_id 2>/dev/null || true)"
  [ -z "$default_id" ] || nb_doctor_line PASS "默认 Ingress Profile 存在: $(nb_ingress_profile_name "$default_id")"
  if nb_ingress_state_valid; then
    while IFS= read -r profile; do
      id="$(jq -r .profile_id <<<"$profile")"; name="$(jq -r .name <<<"$profile")"
      interface="$(jq -r .interface <<<"$profile")"; address="$(jq -r .local_address <<<"$profile")"
      policy="$(jq -r .port_policy <<<"$profile")"
      if nb_ingress_address_on_interface "$interface" "$address"; then
        nb_doctor_line PASS "${name}: ${interface}/${address} 已配置"
      else
        nb_doctor_line FAIL "${name}: 网络接口上不存在该本地地址"
        failed=1
      fi
      expected_policy="$(jq -r '.ingress_enforcement // "permissive"' <<<"$profile")"
      case "$expected_policy" in
        strict) nb_doctor_line PASS "${name}: Ingress 强制策略为严格 / strict" ;;
        permissive) nb_doctor_line INFO "宽松通配监听 / PERMISSIVE_WILDCARD: ${name}" ;;
      esac
      if [ "$policy" = manual-only ]; then
        nb_doctor_line PASS "${name}: 仅手动 / manual-only（不使用自动端口池）"
      elif range="$(nb_ingress_profile_auto_range "$id" 2>/dev/null)"; then
        nb_doctor_line PASS "${name}: 推导 / 显式端口范围 ${range//|/-} 有效"
      else
        nb_doctor_line FAIL "${name}: 自动端口池无效"
        failed=1
      fi
      while IFS= read -r port; do
        [ -n "$port" ] || continue
        owner="$(nb_registry_rows | awk -F'|' -v p="$port" '$3==p{print $1; exit}')"
        [ -z "$owner" ] || { nb_doctor_line FAIL "${name}: 保留端口 ${port} 已被 ${owner} 使用"; failed=1; }
      done < <(jq -r '.reserved_ports[]?' <<<"$profile")
      refs="$(nb_ingress_profile_reference_rows "$id")"
      [ -z "$refs" ] || nb_doctor_line PASS "${name}: Profile 关联信息可读取"
    done < <(jq -c '.profiles[]' "$NOBRAND_INGRESS_STATE_FILE")
  fi
  while IFS='|' read -r referenced_profile referenced_owner; do
    [ -n "$referenced_profile" ] || continue
    if ! nb_ingress_profile_json "$referenced_profile" >/dev/null 2>&1; then
      nb_doctor_line FAIL "${referenced_owner}: 未知 Ingress Profile ${referenced_profile}"
      failed=1
    fi
  done < <(nb_ingress_profile_reference_rows '*')
  while IFS='|' read -r owner transport port _advertise_host _advertise_port; do
    [ -n "$owner" ] || continue
    key="${transport}:${port}"
    case "$seen" in
      *"|${key}|"*)
        nb_doctor_line FAIL "主机全局端口归属重复: ${key} (${owner})"
        failed=1
        duplicate_count=$((duplicate_count + 1))
        ;;
      *) seen="${seen}${key}|" ;;
    esac
    profile_id="$(nb_owner_ingress_profile_id "$owner" 2>/dev/null || true)"
    [ -n "$profile_id" ] || profile_id="$NOBRAND_LEGACY_INGRESS_PROFILE_ID"
    if ! profile="$(nb_ingress_profile_json "$profile_id" 2>/dev/null)"; then
      nb_doctor_line FAIL "${owner}: 未知 Ingress Profile ${profile_id}"
      failed=1
      continue
    fi
    if [ "$profile_id" != "$NOBRAND_LEGACY_INGRESS_PROFILE_ID" ]; then
      policy="$(jq -r .port_policy <<<"$profile")"
      if [ "$policy" != manual-only ] && range="$(nb_ingress_profile_auto_range "$profile_id" 2>/dev/null)"; then
        lo="${range%%|*}"; hi="${range#*|}"
        if { [ "$port" -lt "$lo" ] || [ "$port" -gt "$hi" ]; } \
           && ! nb_ingress_port_is_reserved "$profile_id" "$port"; then
          nb_doctor_line WARN "超出当前自动端口池 / OUTSIDE_CURRENT_AUTO_POOL: ${owner} ${transport}/${port} (${lo}-${hi})"
        fi
      fi
    fi
    case "$owner" in ssh-tunnel:*)
      nb_doctor_line INFO "${owner}: 不适用于系统 SSH / NOT_APPLICABLE_TO_SYSTEM_SSH"
      continue
      ;;
    esac
    expected_policy="$(jq -r '.ingress_enforcement // "permissive"' <<<"$profile")"
    actual_policy="$(nb_owner_ingress_enforcement "$owner" 2>/dev/null || printf permissive)"
    actual_method="$(nb_owner_ingress_method "$owner" 2>/dev/null || printf wildcard)"
    actual_address="$(nb_owner_ingress_local_address "$owner" 2>/dev/null || true)"
    capability="$(nb_ingress_owner_capability "$owner" 2>/dev/null || true)"
    if [ "$expected_policy" = permissive ]; then
      expected_method=wildcard
    else
      expected_method="$capability"
    fi
    if [ "$actual_policy" != "$expected_policy" ] || [ "$actual_method" != "$expected_method" ]; then
      nb_doctor_line FAIL "强制策略漂移 / ENFORCEMENT_DRIFT: ${owner} 期望=${expected_policy}/${expected_method} 实际=${actual_policy}/${actual_method}"
      failed=1
      continue
    fi
    enabled="$(nb_owner_enabled "$owner" 2>/dev/null || printf true)"
    if [ "$expected_policy" = strict ]; then
      if [ -z "$actual_address" ] || [ "$actual_address" != "$(jq -r .local_address <<<"$profile")" ]; then
        nb_doctor_line FAIL "Profile 本地地址缺失 / PROFILE_LOCAL_ADDRESS_MISSING: ${owner}"
        failed=1
      elif [ "$enabled" != true ]; then
        nb_doctor_line PASS "${owner}: 严格 / strict 强制状态有效（节点已禁用）"
      elif [ "$actual_method" = firewall ]; then
        nb_strict_firewall_rule_owned "$owner" "$transport" "$port" "$actual_address" \
          && nb_doctor_line PASS "严格防火墙强制 / STRICT_FIREWALL_ENFORCEMENT: ${owner} ${transport}/${port}" \
          || { nb_doctor_line FAIL "严格防火墙强制 / STRICT_FIREWALL_ENFORCEMENT: ${owner} ${transport}/${port}"; failed=1; }
      elif [ "$actual_method" = address-match ]; then
        forward_listener_enforcement_owned "${owner#forward:}" \
          && nb_doctor_line PASS "严格地址匹配 / STRICT_ADDRESS_MATCH: ${owner} ${transport}/${port} 地址=${actual_address}" \
          || { nb_doctor_line FAIL "严格地址匹配 / STRICT_ADDRESS_MATCH: ${owner} ${transport}/${port}"; failed=1; }
      elif nb_listener_has_local_address "$transport" "$port" "$actual_address"; then
        nb_doctor_line PASS "严格原生绑定 / STRICT_NATIVE_BIND: ${owner} ${transport}/${port} 地址=${actual_address}"
      else
        nb_doctor_line FAIL "严格原生绑定 / STRICT_NATIVE_BIND: ${owner} ${transport}/${port} 缺少精确地址监听"
        failed=1
      fi
    elif [ "$actual_method" = wildcard ]; then
      nb_doctor_line INFO "宽松通配监听 / PERMISSIVE_WILDCARD: ${owner} ${transport}/${port}"
    fi
  done < <(nb_registry_rows)
  if [ -e "$NOBRAND_INGRESS_FIREWALL_STATE_FILE" ] && ! nb_strict_firewall_state_valid; then
    nb_doctor_line FAIL '严格 Ingress 防火墙状态无效'
    failed=1
  fi
  [ "$duplicate_count" -ne 0 ] || nb_doctor_line PASS '主机全局、按传输区分的实际端口归属有效'
  egress="$(nb_ingress_default_egress 2>/dev/null || true)"
  if [ -n "$egress" ]; then
    nb_doctor_line INFO "当前系统默认出口（只读）: ${egress%%|*} / ${egress#*|}"
  else
    nb_doctor_line INFO '当前系统默认出口不可用（仅作只读观察）'
  fi
  [ "$failed" -eq 0 ] && nb_doctor_line PASS 'Ingress 诊断 / Doctor'
  [ "$failed" -eq 0 ]
}

nobrand_run_ingress_action() {
  if nb_splicore_installed; then
    case "${INGRESS_ACTION:-list}" in
      modify|delete|apply)
        printf '[错误] Splicore 节点的入口变更需要显式 canonical 配置事务；拒绝调用旧 Core 的入口重建路径。\n' >&2
        return 1
        ;;
    esac
  fi
  if [ "${INGRESS_ACTION:-list}" = add ]; then
    nb_ingress_prepare_add_request || return 1
  fi
  case "${INGRESS_ACTION:-list}" in
    add|modify|delete|set-default|unset-default|apply)
      if [ "${NOBRAND_MANAGER_SESSION_ACTIVE:-0}" -eq 1 ]; then
        nb_lifecycle_run_ingress_action
      else
        nobrand_run_ingress_action_unscoped
      fi
      ;;
    *) nobrand_run_ingress_action_unscoped ;;
  esac
}

nobrand_run_ingress_action_unscoped() {
  local lock_required=0 rc=0
  case "${INGRESS_ACTION:-list}" in
    add|modify|delete|set-default|unset-default|apply)
      lock_required=1
      require_root || return 1
      admin_lock_acquire || return 1
      ;;
  esac
  case "${INGRESS_ACTION:-list}" in
    list) nb_ingress_list || rc=$? ;;
    show) nb_ingress_show || rc=$? ;;
    add) nb_ingress_add || rc=$? ;;
    modify) nb_ingress_modify || rc=$? ;;
    apply) nb_ingress_apply || rc=$? ;;
    delete) nb_ingress_delete || rc=$? ;;
    set-default) nb_ingress_set_default || rc=$? ;;
    unset-default) nb_ingress_unset_default || rc=$? ;;
    doctor) nb_ingress_doctor || rc=$? ;;
    help) nobrand_usage || rc=$? ;;
    *) rc=2 ;;
  esac
  [ "$lock_required" -eq 0 ] || admin_lock_release
  return "$rc"
}

# ---------- NoBrand Common Core: state、Endpoint、firewall/service adapters ----------

nb_init_state_layout() {
  [ "${DRY_RUN:-0}" -ne 1 ] || return 0
  nb_splicore_legacy_preflight || return 1
  ensure_manager_state_layout 1 || return 1
  mkdir -p "$NOBRAND_BACKUP_DIR" "$NOBRAND_LOCK_DIR" \
    "$NOBRAND_VLESS_STATE_DIR" "$NOBRAND_VLESS_CONFIG_DIR" \
    "$NOBRAND_SSH_STATE_DIR" "$NOBRAND_SSH_KEYS_DIR" "$NOBRAND_SSH_WATCHDOG_DIR" \
    "$NOBRAND_FORWARD_STATE_DIR" "$NOBRAND_FORWARD_CONFIG_DIR" \
    "$NOBRAND_SSH_CONFIG_DIR" "$NOBRAND_SSH_AUTHORIZED_KEYS_DIR" "$NOBRAND_SSH_ACCOUNT_MARKER_DIR" \
    "$NOBRAND_BIN_DIR" || return 1
  chmod 0700 "$NOBRAND_STATE_DIR" "$NOBRAND_BACKUP_DIR" "$NOBRAND_LOCK_DIR" \
    "$NOBRAND_VLESS_STATE_DIR" "$NOBRAND_VLESS_CONFIG_DIR" \
    "$NOBRAND_SSH_STATE_DIR" "$NOBRAND_SSH_KEYS_DIR" "$NOBRAND_SSH_WATCHDOG_DIR" \
    "$NOBRAND_FORWARD_STATE_DIR" "$NOBRAND_FORWARD_CONFIG_DIR" "$NOBRAND_SSH_ACCOUNT_MARKER_DIR" || return 1
  chmod 0711 "$NOBRAND_CONFIG_DIR" "$NOBRAND_SSH_CONFIG_DIR" || return 1
  chmod 0755 "$NOBRAND_SSH_AUTHORIZED_KEYS_DIR" "$NOBRAND_LIB_DIR" "$NOBRAND_BIN_DIR" || return 1
  nb_schema_v3_file_valid && chmod 0600 "$NOBRAND_REGISTRY_FILE"
}

nb_atomic_install_file() {
  local source="$1" destination="$2" mode="${3:-0600}" tmp
  [ -f "$source" ] || return 1
  if [ "${DRY_RUN:-0}" -eq 1 ]; then
    t "[演练] install -m ${mode} ${source} ${destination}" \
      "[dry-run] install -m ${mode} ${source} ${destination}"
    return 0
  fi
  mkdir -p "$(dirname "$destination")" || return 1
  tmp="$(mktemp "${destination}.tmp.XXXXXX")" || return 1
  if ! install -m "$mode" "$source" "$tmp" || ! mv -f "$tmp" "$destination"; then
    rm -f "$tmp"
    return 1
  fi
}

nb_normalize_endpoint_host() {
  local host="${1:-}"
  command -v python3 >/dev/null 2>&1 || {
    printf '%s' "$(printf '%s' "${host%.}" | tr '[:upper:]' '[:lower:]')"
    return 0
  }
  python3 - "$host" <<'PY'
import ipaddress
import sys
value=sys.argv[1].strip()
try:
    print(ipaddress.ip_address(value))
except ValueError:
    print(value.rstrip('.').lower())
PY
}

nb_validate_advertise_endpoint() {
  local host="${1:-}" port="${2:-}" transport="${3:-TCP}"
  transport="$(printf '%s' "$transport" | tr '[:lower:]' '[:upper:]')"
  case "$transport" in TCP|UDP|BOTH) ;; *) return 1 ;; esac
  if [ -z "$host" ] && [ -z "$port" ]; then
    return 0
  fi
  [ -n "$host" ] && [ -n "$port" ] || return 1
  valid_advertise_host "$host" || return 1
  valid_advertise_port "$port" || return 1
  [ "$transport" != BOTH ] || [ "$(normalize_uint "$port")" -le 65534 ]
}

nb_endpoint_conflict_owner() {
  local transport host port ignore_owner="${4:-}" auto_host owner row_transport listen_port advertise_host advertise_port
  local normalized expected_host effective_host effective_port
  transport="$(nb_normalize_transport "$1")" || return 1
  host="$2"
  port="$(normalize_uint "$3")" || return 1
  expected_host="$(nb_normalize_endpoint_host "$host")"
  auto_host="$(public_ip 2>/dev/null || true)"
  while IFS='|' read -r owner row_transport listen_port advertise_host advertise_port; do
    [ -n "$owner" ] || continue
    [ "$owner" = "$ignore_owner" ] && continue
    [ "$row_transport" = "$transport" ] || continue
    effective_host="${advertise_host:-$auto_host}"
    effective_port="${advertise_port:-$listen_port}"
    [ -n "$effective_host" ] || continue
    normalized="$(nb_normalize_endpoint_host "$effective_host")"
    if [ "$normalized" = "$expected_host" ] && [ "$effective_port" = "$port" ]; then
      printf '%s' "$owner"
      return 0
    fi
  done < <(nb_registry_rows)
  return 1
}

nb_require_explicit_endpoint_noninteractive() {
  [ "${YES:-0}" -eq 1 ] || return 0
  # An explicit/default mapped or public ingress profile supplies a stable
  # display host. Its follow-actual policy supplies the listener port.
  if [ -n "${INGRESS_PROFILE_ID:-}" ] \
     && [ "${INGRESS_PROFILE_ID}" != "$NOBRAND_LEGACY_INGRESS_PROFILE_ID" ] \
     && [ -n "$(nb_ingress_profile_display_host "$INGRESS_PROFILE_ID" 2>/dev/null || true)" ]; then
    return 0
  fi
  if [ "${ADVERTISE_AUTO_REQUESTED:-0}" -eq 1 ]; then
    return 0
  fi
  if [ "${ADVERTISE_CLI:-0}" -eq 1 ] && [ -n "${ADVERTISE_HOST:-}" ] && [ -n "${ADVERTISE_PORT:-}" ]; then
    return 0
  fi
  die "$(t '非交互模式必须同时提供 --advertise-host/--advertise-port，或明确使用 --advertise-auto' \
    'Non-interactive mode requires --advertise-host with --advertise-port, or explicit --advertise-auto')"
}

nb_collect_advertise_endpoint_interactive() {
  local protocol_name="$1" listen_port="$2" detected="" choice="" host="" port="" profile_name=""
  detected="$(nb_ingress_profile_display_host "${INGRESS_PROFILE_ID:-}" 2>/dev/null || true)"
  if [ -n "$detected" ]; then
    profile_name="$(nb_ingress_profile_name "$INGRESS_PROFILE_ID")"
  else
    detected="$(public_ip 2>/dev/null || true)"
  fi
  msg ""
  t "${protocol_name} 真实监听端口: ${listen_port}" "${protocol_name} real listen port: ${listen_port}"
  if [ -n "$detected" ]; then
    t "客户端入口建议: ${detected}:$(nb_ingress_profile_display_port "${INGRESS_PROFILE_ID:-$NOBRAND_LEGACY_INGRESS_PROFILE_ID}" "$listen_port")${profile_name:+（来自入口配置 ${profile_name}）}" \
      "Client entry suggestion: ${detected}:$(nb_ingress_profile_display_port "${INGRESS_PROFILE_ID:-$NOBRAND_LEGACY_INGRESS_PROFILE_ID}" "$listen_port")${profile_name:+ (from ingress profile ${profile_name})}"
  else
    warn "$(t '未检测到公网入口；IPLC/NAT 环境请填写实际前置入口' \
      'No public entry detected; enter the actual IPLC/NAT frontend endpoint')"
  fi
  t '  1) 使用自动入口（以后查看节点时重新探测 host；端口等于真实监听）' \
    '  1) Use auto endpoint (host is detected when viewing; port equals listener)'
  t '  2) 自定义客户端入口（IPLC / NAT / DNAT）' \
    '  2) Custom client endpoint (IPLC / NAT / DNAT)'
  read_tty choice "$(t '请选择 [1-2，默认 1]: ' 'Choose [1-2, default 1]: ')" || choice=""
  case "${choice:-1}" in
    2)
      while true; do
        read_tty host "$(t "客户端入口 Host [${detected:-example.com}]: " \
          "Client entry host [${detected:-example.com}]: ")" || host=""
        host="${host:-$detected}"
        read_tty port "$(t "客户端入口 Port [${listen_port}]: " \
          "Client entry port [${listen_port}]: ")" || port=""
        port="${port:-$listen_port}"
        if nb_validate_advertise_endpoint "$host" "$port"; then
          ADVERTISE_HOST="$host"
          ADVERTISE_PORT="$(normalize_uint "$port")"
          ADVERTISE_CLI=1
          ADVERTISE_AUTO_REQUESTED=0
          return 0
        fi
        warn "$(t '入口必须是有效 IPv4/IPv6/域名与 1-65535 端口' \
          'Endpoint must be a valid IPv4/IPv6/domain and port 1-65535')"
      done
      ;;
    *)
      ADVERTISE_HOST=""
      ADVERTISE_PORT=""
      ADVERTISE_CLI=1
      ADVERTISE_AUTO_REQUESTED=1
      ;;
  esac
}

nb_effective_advertise_host() {
  local mode="${1:-auto}" host="${2:-}" profile_id="${3:-}" profile_host=""
  if [ "$mode" = custom ] && [ -n "$host" ]; then
    printf '%s' "$host"
  elif [ -n "$profile_id" ] && [ "$profile_id" != "$NOBRAND_LEGACY_INGRESS_PROFILE_ID" ] \
       && profile_host="$(nb_ingress_profile_display_host "$profile_id" 2>/dev/null)" \
       && [ -n "$profile_host" ]; then
    printf '%s' "$profile_host"
  else
    public_ip 2>/dev/null || printf 'YOUR_SERVER_IP'
  fi
}

nb_effective_advertise_port() {
  local mode="${1:-auto}" advertise_port="${2:-}" listen_port="${3:-}" profile_id="${4:-}"
  if [ "$mode" = custom ] && [ -n "$advertise_port" ]; then
    printf '%s' "$advertise_port"
  elif [ -n "$profile_id" ] && [ "$profile_id" != "$NOBRAND_LEGACY_INGRESS_PROFILE_ID" ]; then
    nb_ingress_profile_display_port "$profile_id" "$listen_port"
  else
    printf '%s' "$listen_port"
  fi
}

nb_endpoint_mode_from_values() {
  [ -n "${1:-}" ] && printf 'custom' || printf 'auto'
}

nb_firewall_open_pairs() {
  local pairs="$1"
  local MITA_FIREWALL_OWNED_STATE="$NOBRAND_FIREWALL_OWNED_STATE"
  local MITA_FIREWALL_COMMENT="$NOBRAND_FIREWALL_COMMENT"
  open_firewall_for_pairs "$pairs"
}

nb_firewall_close_pairs() {
  local pairs="$1"
  local MITA_FIREWALL_OWNED_STATE="$NOBRAND_FIREWALL_OWNED_STATE"
  local MITA_FIREWALL_COMMENT="$NOBRAND_FIREWALL_COMMENT"
  close_firewall_for_bindings "$pairs"
}

nb_firewall_binding_owned() {
  local transport="$1" port="$2" proto _tool row_proto row_port
  proto="$(printf '%s' "$transport" | tr '[:upper:]' '[:lower:]')"
  [ -f "$NOBRAND_FIREWALL_OWNED_STATE" ] || return 1
  while IFS='|' read -r _tool row_proto row_port; do
    [ "$row_proto" = "$proto" ] && [ "$row_port" = "$port" ] && return 0
  done <"$NOBRAND_FIREWALL_OWNED_STATE"
  return 1
}

nb_service_manager() {
  service_manager
}

nb_service_is_active() {
  local systemd_unit="$1" openrc_service="$2" manager
  manager="$(nb_service_manager)"
  case "$manager" in
    systemd) systemctl is-active --quiet "$systemd_unit" 2>/dev/null ;;
    openrc) rc-service "$openrc_service" status 2>/dev/null | grep -qiE 'started|running' ;;
    *) return 1 ;;
  esac
}

nb_wait_for_listener() {
  local transport="$1" port="$2" timeout="${3:-20}" elapsed=0
  while [ "$elapsed" -lt "$timeout" ]; do
    nb_port_is_listening "$transport" "$port" && return 0
    sleep 1
    elapsed=$((elapsed + 1))
  done
  return 1
}

# ---------- NoBrand Common Core: 入口、节点聚合、状态、Doctor、备份 ----------

nobrand_print_banner() {
  msg ""
  msg '========================================'
  printf '          %s v%s\n' "$SCRIPT_NAME" "$SCRIPT_VERSION"
  msg '========================================'
  t "作者: ${SCRIPT_AUTHOR}" "Author: ${SCRIPT_AUTHOR}"
}

nobrand_version() {
  printf '%s %s\n%s: %s\n' "$SCRIPT_NAME" "$SCRIPT_VERSION" \
    "$(t '作者' 'Author')" "$SCRIPT_AUTHOR"
}

nobrand_usage() {
  cat <<EOF
NoBrand-OneClick 3.2.6 — Multi-Ingress / Mieru / Snell v4-v5 / Hysteria2 / TUIC v5 / VLESS REALITY / VLESS + FinalMask + Sudoku / SSH Tunnel / Port Forward

用法:
  nobrand                         打开统一菜单
  nb                              与 nobrand 完全相同的短别名
  nobrand --version               显示产品版本与作者
  nobrand --help                  显示本帮助
  nobrand status                  综合状态
  nobrand nodes [--protocol P]    查看全部或指定协议节点
  nobrand doctor                  综合诊断（默认不输出 secret）
  nobrand runtime capabilities    查看固定 rc.4 的能力与限制
  nobrand runtime status|doctor|plan|recover|rollback
  nobrand runtime apply|render --file DESIRED.json
  nobrand runtime backup|restore --file BACKUP.tar.gz
  nobrand runtime start|stop|restart|uninstall|purge
  nobrand ingress list|doctor     查看入口配置或执行只读 Ingress Doctor
  nobrand ingress show PROFILE    查看入口配置
  nobrand ingress add             新增 public/mapped 入口配置
  nobrand ingress modify|delete PROFILE
  nobrand ingress set-default PROFILE | unset-default
  nobrand backup create [FILE]    备份 NoBrand schema-v3 全部 state 与配置
  nobrand backup restore FILE     恢复 NoBrand 备份
  nobrand uninstall [-y]          统一卸载 Mieru/Snell/HY2/TUIC/VLESS/SSH/Forward/Common
  nobrand manager install|upgrade 从当前执行的 exact installer 安装/升级统一管理器

  nobrand mieru                    打开完整 Mieru 菜单
  nobrand mieru install|reconfigure|upgrade|uninstall|start|stop|restart
  nobrand mieru status|doctor|perf|show|users
  nobrand mieru user-add|user-del|user-show|user-set-endpoint
  Mieru 参数: --port --protocol --profile --advertise-host --advertise-port --advertise-auto
    user-add 可在交互中选择自动/自定义展示入口；--advertise-host 可省略展示端口并继承新用户的有效端口。
    --ingress-profile PROFILE
    --mtu --traffic-pattern --low-entropy --multiplexing --handshake-mode

  nobrand snell install --name NAME [--version 5|4] [--port PORT] [--quic off]
      [--advertise-host HOST --advertise-port PORT | --advertise-auto] [-y]
  nobrand snell show|status|doctor|start|stop|restart|remove [--name NAME]
  nobrand snell set-endpoint --name NAME
      [--advertise-host HOST --advertise-port PORT | --advertise-auto]

  nobrand hy2 install [--port PORT] [--sni SNI]
      [--advertise-host HOST --advertise-port PORT | --advertise-auto] [-y]
  nobrand hy2 show|status|doctor|start|stop|restart|remove
  nobrand hy2 set-endpoint
      [--advertise-host HOST --advertise-port PORT | --advertise-auto]

  nobrand vless-sudoku install [--port PORT]
      [--advertise-host HOST --advertise-port PORT | --advertise-auto] [-y]
  nobrand vless-sudoku show|status|doctor|smoke|start|stop|restart|remove
  nobrand vless-sudoku set-endpoint
      [--advertise-host HOST --advertise-port PORT | --advertise-auto]

  nobrand vless-reality install --name NAME [--target HOST] [--target-port PORT]
      [--ingress-profile PROFILE] [--port PORT]
      [--advertise-host HOST --advertise-port PORT | --advertise-auto] [-y]
      默认 cover 为 www.microsoft.com:443；可显式设置可用的 TLS 1.3 cover。
      显式域名会按原值使用；域名与伪装目标端口可分别配置。
      443 是默认伪装目标端口，不是公开 REALITY 监听端口。
  nobrand vless-reality show|export|status|doctor|start|stop|restart|remove [--name NAME]
  nobrand vless-reality set-endpoint --name NAME
      [--advertise-host HOST --advertise-port PORT | --advertise-auto]

  nobrand tuic install --name NAME --user USER [--port PORT] [--sni SNI]
      [--advertise-host HOST --advertise-port PORT | --advertise-auto] [-y]
  nobrand tuic start|stop|restart|status|doctor|show|export|set-endpoint|upgrade-runtime|uninstall
  nobrand tuic user add|delete|list|show|rotate --name NAME [--user USER]

  nobrand ssh install --user USER
      [--advertise-host HOST --advertise-port PORT | --advertise-auto] [-y]
  nobrand ssh status|doctor|show|export|set-endpoint|uninstall
  nobrand ssh user add|delete|list|show|rotate-key [--user USER]
  nobrand ssh confirm-admin --token TOKEN

  nobrand forward add --name NAME --backend nftables|realm --protocol TCP|UDP|BOTH
      --listen 0.0.0.0 --port PORT --target HOST --target-port PORT
  nobrand forward list|doctor|export
  nobrand forward show|delete|modify|enable|disable|set-endpoint|switch-backend RULE
  nobrand forward import FILE

说明:
  - Snell 只支持 v5（默认/推荐）与 v4（兼容）。
  - 普通代理由一个固定 Splicore v0.3.0-rc.4 daemon 管理；Release Candidate / Experimental。
  - 新架构要求 clean install；旧 multi-core 安装只检测并拒绝，不支持原地迁移或新版卸载。
  - REALITY 使用原生 Local Tunnel Guard；HY2 使用新证书和独立 Salamander secret。
  - Mieru 新装可用 --profile iplc 或 --traffic-pattern off；默认 traffic off；balanced/stealth 不支持。
  - Display Endpoint 只影响客户端输出，不创建 DNAT/IPLC 转发，也不改 listener。
  - --advertise-host 接受 IPv4、IPv6 或 ASCII DNS hostname；Host 与 Port 分别填写，配置时不要求域名解析成功。
  - Display Endpoint 不配置 VPS 系统出站 IP、默认路由或 policy routing。
  - 非交互 -y 必须明确给出完整 Display Endpoint 或 --advertise-auto。
  - VLESS Sudoku = plain VLESS + FinalMask(sudoku) + TCP。
  - VLESS REALITY = VLESS + TCP + REALITY + xtls-rprx-vision；public Profile 推荐，mapped 仅警告。
  - VLESS Encryption: NOT USED；不调用密钥生成子命令，不保存加密密钥。
  - TUIC 只支持 v5：Splicore、UDP/QUIC、每用户独立 UUID + password。
  - SSH Tunnel 复用现有 sshd；允许 -L/-D/-R TCP forwarding，不允许 shell/exec/TTY/SFTP/SCP。
  - SSH Tunnel 使用 AllowTcpForwarding=yes，因此可访问服务器自身可达的 TCP destinations；GatewayPorts=no。
  - SSH Tunnel 不拥有 sshd listener、SSH firewall、host keys 或 admin authentication。
  - Port Forward: nftables 为 IPv4 kernel NAT；Realm 为 official userspace relay，可使用 IP/domain target。
  - Forward 的 Display Endpoint 仅为 metadata；xx00 对 nftables/Realm 和 TCP/UDP 均保留。
  - Ingress 决定端口策略、展示默认值和入口身份；Linux 系统路由继续独立决定 Egress。
  - Ingress Profile 不修改网卡、地址、路由、ip rule、sysctl、SSH 或 provider mapping。
  - PROTOCOL_FEATURE_FREEZE=${PROTOCOL_FEATURE_FREEZE}（VLESS REALITY 是 3.2 最后一个协议功能）。
  - 普通安装只下载固定 Splicore；FinalMask/Sudoku 保留已有专用 pinned Xray。
  - FinalMask/Sudoku 仍使用独立 pinned Xray；Splicore 不管理 Xray。
  - v3 state 必须带 schema_version=3；旧 state 不读取、不导入、不删除。
  - 正式安装器: ${NOBRAND_RELEASE_INSTALLER_URL}
EOF
}

nobrand_manager_source_valid() {
  local path="$1"
  [ -r "$path" ] && [ -f "$path" ] || return 1
  grep -qxF 'SCRIPT_NAME="NoBrand-OneClick"' "$path" 2>/dev/null \
    && grep -qxF 'SCRIPT_REPO="ike-sh/NoBrand-OneClick"' "$path" 2>/dev/null \
    && grep -qxF "SCRIPT_VERSION=\"${SCRIPT_VERSION}\"" "$path" 2>/dev/null
}

nobrand_manager_source_path() {
  if [ -n "${BASH_SOURCE[0]:-}" ] \
     && nobrand_manager_source_valid "${BASH_SOURCE[0]}"; then
    printf '%s' "${BASH_SOURCE[0]}"
  elif nobrand_manager_source_valid "$INSTALL_SCRIPT_PATH"; then
    printf '%s' "$INSTALL_SCRIPT_PATH"
  elif nobrand_manager_source_valid "$NOBRAND_INSTALL_SCRIPT_PATH"; then
    printf '%s' "$NOBRAND_INSTALL_SCRIPT_PATH"
  else
    return 1
  fi
}

nobrand_install_manager_script() {
  local source_path="" source_real="" destination_real="" link_tmp=""
  if [ "${DRY_RUN:-0}" -eq 1 ]; then
    t '[演练] 安装 NoBrand 管理器与 nobrand/nb 命令' \
      '[dry-run] install NoBrand manager and nobrand/nb commands'
    return 0
  fi
  source_path="$(nobrand_manager_source_path 2>/dev/null || true)"
  [ -n "$source_path" ] || {
    warn "$(t '找不到当前 NoBrand 单文件安装器，未安装统一快捷命令' \
      'Current NoBrand single-file installer not found; unified shortcuts were not installed')"
    return 1
  }
  source_real="$(readlink -f "$source_path" 2>/dev/null || realpath "$source_path" 2>/dev/null || printf '%s' "$source_path")"
  destination_real="$(readlink -f "$NOBRAND_INSTALL_SCRIPT_PATH" 2>/dev/null \
    || realpath "$NOBRAND_INSTALL_SCRIPT_PATH" 2>/dev/null || printf '%s' "$NOBRAND_INSTALL_SCRIPT_PATH")"
  if [ "$source_real" != "$destination_real" ]; then
    nb_atomic_install_file "$source_path" "$NOBRAND_INSTALL_SCRIPT_PATH" 0755 || return 1
  else
    chmod 0755 "$NOBRAND_INSTALL_SCRIPT_PATH" || return 1
  fi
  mkdir -p "$(dirname "$NOBRAND_COMMAND_PATH")" "$(dirname "$NOBRAND_SHORT_COMMAND_PATH")" \
    || return 1
  link_tmp="$(mktemp "${NOBRAND_COMMAND_PATH}.tmp.XXXXXX")" || return 1
  rm -f "$link_tmp"
  if ! ln -s "$NOBRAND_INSTALL_SCRIPT_PATH" "$link_tmp" \
     || ! mv -f "$link_tmp" "$NOBRAND_COMMAND_PATH"; then
    rm -f "$link_tmp"
    return 1
  fi
  link_tmp="$(mktemp "${NOBRAND_SHORT_COMMAND_PATH}.tmp.XXXXXX")" || return 1
  rm -f "$link_tmp"
  if ! ln -s "$NOBRAND_COMMAND_PATH" "$link_tmp" \
     || ! mv -f "$link_tmp" "$NOBRAND_SHORT_COMMAND_PATH"; then
    rm -f "$link_tmp"
    return 1
  fi
  cmp -s "$source_path" "$NOBRAND_INSTALL_SCRIPT_PATH" || return 1
  [ "$(readlink "$NOBRAND_COMMAND_PATH" 2>/dev/null || true)" = "$NOBRAND_INSTALL_SCRIPT_PATH" ] || return 1
  [ "$(readlink "$NOBRAND_SHORT_COMMAND_PATH" 2>/dev/null || true)" = "$NOBRAND_COMMAND_PATH" ] || return 1
}

nobrand_manager_installation_valid() {
  local installed="" version_line="" source_path="" source_real="" destination_real=""
  [ -x "$NOBRAND_INSTALL_SCRIPT_PATH" ] \
    && [ -L "$NOBRAND_COMMAND_PATH" ] && [ -L "$NOBRAND_SHORT_COMMAND_PATH" ] \
    || return 1
  [ "$(readlink "$NOBRAND_COMMAND_PATH" 2>/dev/null || true)" = "$NOBRAND_INSTALL_SCRIPT_PATH" ] \
    || return 1
  [ "$(readlink "$NOBRAND_SHORT_COMMAND_PATH" 2>/dev/null || true)" = "$NOBRAND_COMMAND_PATH" ] \
    || return 1
  installed="$(nb_installed_manager_version 2>/dev/null || true)"
  [ "$installed" = "$SCRIPT_VERSION" ] || return 1
  version_line="$("$NOBRAND_COMMAND_PATH" --version 2>/dev/null | sed -n '1p')" || return 1
  [ "$version_line" = "${SCRIPT_NAME} ${SCRIPT_VERSION}" ] || return 1
  source_path="$(nobrand_manager_source_path 2>/dev/null || true)"
  [ -n "$source_path" ] || return 1
  source_real="$(readlink -f "$source_path" 2>/dev/null \
    || realpath "$source_path" 2>/dev/null || printf '%s' "$source_path")"
  destination_real="$(readlink -f "$NOBRAND_INSTALL_SCRIPT_PATH" 2>/dev/null \
    || realpath "$NOBRAND_INSTALL_SCRIPT_PATH" 2>/dev/null \
    || printf '%s' "$NOBRAND_INSTALL_SCRIPT_PATH")"
  [ "$source_real" = "$destination_real" ] \
    || cmp -s "$source_path" "$NOBRAND_INSTALL_SCRIPT_PATH"
}

nobrand_manager_upgrade() {
  nobrand_manager_bootstrap \
    || die "$(t 'NoBrand 管理器安装/升级失败；协议状态未修改' \
      'NoBrand manager install/upgrade failed; protocol state was not modified')"
  t "NoBrand 统一管理器已从当前精确安装器安装/升级至 v${SCRIPT_VERSION}" \
    "NoBrand unified manager installed/upgraded from the current exact installer to v${SCRIPT_VERSION}"
}

nb_all_node_rows() {
  case "${1:-}" in
    ""|all) vless_sudoku_node_rows; ssh_tunnel_node_rows; forward_node_rows ;;
    vless-sudoku|sudoku|vless) vless_sudoku_node_rows ;;
    ssh|ssh-tunnel) ssh_tunnel_node_rows ;;
    forward|port-forward) forward_node_rows ;;
    mieru|snell|hy2|hysteria2|tuic|vless-reality|reality) return 0 ;;
    *) return 1 ;;
  esac
}

nb_owner_ingress_profile_id() {
  local owner="$1" id
  case "$owner" in
    splicore:*) jq -r --arg id "${owner#splicore:}" '.nodes[]|select(.id==$id)|.ingress.profile_id // empty' "${NOBRAND_STATE_DIR}/splicore/current/desired.json" ;;
    vless-sudoku:*) vless_sudoku_state_field ingress_profile_id 2>/dev/null || true ;;
    forward:*)
      jq -r --arg id "${owner#forward:}" '.rules[]|select(.rule_id==$id)|.ingress_profile_id // empty' \
        "$NOBRAND_FORWARD_STATE_FILE" 2>/dev/null || true
      ;;
  esac
}

nb_owner_state_file() {
  case "$1" in
    vless-sudoku:*) printf '%s' "$NOBRAND_VLESS_STATE_FILE" ;;
    *) return 1 ;;
  esac
}

nb_owner_ingress_enforcement() {
  local owner="$1" path id
  case "$owner" in
    forward:*)
      id="${owner#forward:}"
      jq -r --arg id "$id" '.rules[]|select(.rule_id==$id)|.ingress_enforcement // "permissive"' \
        "$NOBRAND_FORWARD_STATE_FILE" 2>/dev/null
      ;;
    ssh-tunnel:*) printf not-applicable ;;
    *) path="$(nb_owner_state_file "$owner")" && nb_ingress_state_enforcement "$path" ;;
  esac
}

nb_owner_ingress_method() {
  local owner="$1" path id
  case "$owner" in
    forward:*)
      id="${owner#forward:}"
      jq -r --arg id "$id" '.rules[]|select(.rule_id==$id)|.ingress_enforcement_method // "wildcard"' \
        "$NOBRAND_FORWARD_STATE_FILE" 2>/dev/null
      ;;
    ssh-tunnel:*) printf system-ssh ;;
    *) path="$(nb_owner_state_file "$owner")" && nb_ingress_state_method "$path" ;;
  esac
}

nb_owner_ingress_local_address() {
  local owner="$1" path id profile_id
  profile_id="$(nb_owner_ingress_profile_id "$owner" 2>/dev/null || true)"
  case "$owner" in
    forward:*)
      id="${owner#forward:}"
      jq -r --arg id "$id" '.rules[]|select(.rule_id==$id)|.ingress_local_address // empty' \
        "$NOBRAND_FORWARD_STATE_FILE" 2>/dev/null
      ;;
    ssh-tunnel:*) return 0 ;;
    *) path="$(nb_owner_state_file "$owner")" && nb_ingress_state_local_address "$path" "$profile_id" ;;
  esac
}

nb_owner_enabled() {
  local owner="$1" path id
  case "$owner" in
    forward:*) id="${owner#forward:}"; jq -r --arg id "$id" '.rules[]|select(.rule_id==$id)|.enabled' "$NOBRAND_FORWARD_STATE_FILE" 2>/dev/null ;;
    ssh-tunnel:*) printf true ;;
    *) path="$(nb_owner_state_file "$owner")" && jq -r '.enabled // true' "$path" 2>/dev/null ;;
  esac
}

nb_node_detail_rows() {
  local filter owner transport port advertise_host advertise_port profile_id display_host display_port enforcement method address actual
  filter="$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')"
  while IFS='|' read -r owner transport port advertise_host advertise_port; do
    [ -n "$owner" ] || continue
    case "$filter:$owner" in
      :*|all:*|mieru:mieru:*|snell:snell:*|hy2:hy2:*|hysteria2:hy2:*|tuic:tuic:*|vless-reality:vless-reality:*|reality:vless-reality:*|vless-sudoku:vless-sudoku:*|sudoku:vless-sudoku:*|vless:vless-*|forward:forward:*|port-forward:forward:*) ;;
      *) continue ;;
    esac
    profile_id="$(nb_owner_ingress_profile_id "$owner")"
    [ -n "$profile_id" ] || profile_id="$NOBRAND_LEGACY_INGRESS_PROFILE_ID"
    if [ -n "$advertise_host" ]; then
      display_host="$advertise_host"
    else
      display_host="$(nb_effective_advertise_host auto '' "$profile_id")"
    fi
    if [ -n "$advertise_port" ]; then
      display_port="$advertise_port"
    else
      display_port="$(nb_effective_advertise_port auto '' "$port" "$profile_id")"
    fi
    enforcement="$(nb_owner_ingress_enforcement "$owner" 2>/dev/null || printf permissive)"
    method="$(nb_owner_ingress_method "$owner" 2>/dev/null || printf wildcard)"
    address="$(nb_owner_ingress_local_address "$owner" 2>/dev/null || true)"
    case "$enforcement:$method" in
      strict:native-bind|strict:address-match) actual="${address}:${port}/${transport}" ;;
      strict:firewall)
        actual="*:${port}/${transport} ($(t "防火墙仅允许 ${address}" "firewall restricted to ${address}"))"
        ;;
      *) actual="*:${port}/${transport}" ;;
    esac
    printf '%s|%s|%s:%s|%s|%s (%s)\n' "$owner" "$actual" "$display_host" "$display_port" \
      "$(nb_ingress_profile_name "$profile_id")" "$enforcement" "$method"
  done < <(nb_registry_rows)
  if { [ -z "$filter" ] || [ "$filter" = all ] || [ "$filter" = ssh ] || [ "$filter" = ssh-tunnel ]; } \
     && ssh_tunnel_state_exists; then
    profile_id="$(ssh_tunnel_state_field ingress_profile_id 2>/dev/null || true)"
    [ -n "$profile_id" ] || profile_id="$NOBRAND_LEGACY_INGRESS_PROFILE_ID"
    while IFS= read -r owner; do
      [ -n "$owner" ] || continue
      printf 'ssh-tunnel:%s|*:%s/TCP (%s)|%s:%s|%s|%s\n' "$owner" \
        "$(ssh_tunnel_state_field real_port)" "$(t '系统 sshd' 'system sshd')" \
        "$(ssh_tunnel_effective_host)" \
        "$(ssh_tunnel_state_field advertise_port)" "$(nb_ingress_profile_name "$profile_id")" \
        "$(t '不适用（系统 sshd）' 'Not applicable (system sshd)')"
    done < <(jq -r '.users[]?.display_name' "$NOBRAND_SSH_STATE_FILE")
  fi
}

nobrand_nodes() {
  if nb_splicore_installed; then
    nb_splicore_call status --protocol "${NOBRAND_PROTOCOL_FILTER:-}" || return 1
    local retained
    for retained in vless-sudoku ssh forward; do
      [ -z "${NOBRAND_PROTOCOL_FILTER:-}" ] || [ "$NOBRAND_PROTOCOL_FILTER" = "$retained" ] || continue
      nb_all_node_rows "$retained"
    done
    return 0
  fi
  local rows details protocol name endpoint status transport owner actual display ingress enforcement status_display
  rows="$(nb_all_node_rows "${NOBRAND_PROTOCOL_FILTER:-}")"
  nobrand_print_banner
  msg ""
  t '协议              节点              客户端入口                              状态' \
    'Protocol          Node              Client endpoint                         Status'
  msg '--------------------------------------------------------------------------------------'
  if [ -z "$rows" ]; then
    t '暂无持久化节点。' 'No persistent nodes.'
    return 0
  fi
  while IFS='|' read -r protocol name endpoint status transport; do
    [ -n "$protocol" ] || continue
    status_display="$status"
    if [ "$LANG_ZH" -eq 1 ]; then
      case "$status" in
        Running) status_display='运行中' ;;
        Stopped) status_display='已停止' ;;
        Ready) status_display='就绪' ;;
        Healthy) status_display='正常' ;;
        Degraded) status_display='异常' ;;
        Disabled) status_display='已禁用' ;;
      esac
    fi
    printf '%-17s %-17s %-40s %s\n' "$protocol" "$name" "$endpoint" "$status_display"
  done <<<"$rows"
  details="$(nb_node_detail_rows "${NOBRAND_PROTOCOL_FILTER:-}")"
  if [ -n "$details" ]; then
    msg ''
    t '实际监听 / Actual Listener；展示端点 / Display Endpoint；入口配置 / Ingress Profile（展示修改不影响监听）' \
      'Actual / Display / Ingress Profile (display changes do not affect listeners)'
    while IFS='|' read -r owner actual display ingress enforcement; do
      if [ "$LANG_ZH" -eq 1 ]; then
        printf '%s\n  实际监听: %s\n  展示端点: %s\n  入口配置: %s\n  强制策略: %s\n' \
          "$owner" "$actual" "$display" "$ingress" "$enforcement"
      else
        printf '%s\n  Actual: %s\n  Display: %s\n  Ingress: %s\n  Enforcement: %s\n' \
          "$owner" "$actual" "$display" "$ingress" "$enforcement"
      fi
    done <<<"$details"
  fi
}

nobrand_status() {
  nb_splicore_legacy_preflight || return 1
  nb_splicore_call status || return 1
  if vless_sudoku_state_exists; then vless_sudoku_service_command status; fi
  ssh_tunnel_status
  [ ! -s "$NOBRAND_FORWARD_STATE_FILE" ] || forward_list_rules
  return 0
}

nb_doctor_line() {
  local level="$1"
  shift
  printf '[%s] %s\n' "$level" "$*"
}

nobrand_doctor() {
  nb_splicore_legacy_preflight || return 1
  local failed=0
  nb_splicore_call doctor || failed=1
  if vless_sudoku_state_exists; then vless_sudoku_doctor || failed=1; fi
  if ssh_tunnel_state_exists; then ssh_tunnel_doctor || failed=1; fi
  [ ! -s "$NOBRAND_FORWARD_STATE_FILE" ] || forward_doctor || failed=1
  return "$failed"
}

nb_backup_default_path() {
  printf '%s/nobrand-backup-%s.tar.gz' "$NOBRAND_BACKUP_DIR" "$(date +%Y%m%d_%H%M%S)"
}

nb_assert_safe_nobrand_root() {
  local value="${1:-}" label="${2:-path}" normalized
  [ -n "$value" ] || die "${label} 为空，拒绝破坏性操作"
  case "$value" in
    *'..'*) die "${label} 含有 ..，拒绝破坏性操作: $value" ;;
  esac
  normalized="$(nb_normalize_path "$value")" \
    || die "${label} 无法安全解析，拒绝破坏性操作: $value"
  case "$normalized" in
    /|/etc|/var|/usr|/usr/local) die "${label} 过宽，拒绝破坏性操作: $normalized" ;;
  esac
  case "$normalized" in
    */nobrand-oneclick|*/nobrand-oneclick/*|*/nobrand-oneclick-*) ;;
    *) die "${label} 不在明确的 NoBrand namespace 中: $normalized" ;;
  esac
  printf '%s' "$normalized"
}

nobrand_backup_restore_transaction_paths_valid() {
  nb_lifecycle_paths_valid || return 1
  [ "$NOBRAND_BACKUP_RESTORE_TX_DIR" = "${NOBRAND_LIFECYCLE_DIR}/backup-restore" ] \
    && [ "$NOBRAND_BACKUP_RESTORE_META_FILE" = "${NOBRAND_BACKUP_RESTORE_TX_DIR}/transaction.env" ] \
    && [ "$NOBRAND_BACKUP_RESTORE_SNAPSHOT_DIR" = "${NOBRAND_BACKUP_RESTORE_TX_DIR}/snapshot" ] \
    && [ "$NOBRAND_BACKUP_RESTORE_ROOTS_MANIFEST" = "${NOBRAND_BACKUP_RESTORE_TX_DIR}/snapshot-roots.manifest" ]
}

nobrand_backup_restore_transaction_present() {
  [ -e "$NOBRAND_BACKUP_RESTORE_TX_DIR" ] || [ -L "$NOBRAND_BACKUP_RESTORE_TX_DIR" ]
}

nobrand_backup_restore_snapshot_manifest_walk() {
  local root="$1" prefix="$2" entry name relative metadata digest
  local -a entries=()
  entries=("$root"/*)
  for entry in "${entries[@]}"; do
    name="${entry##*/}"
    relative="${prefix}${name}"
    if [ -L "$entry" ]; then
      printf 'L\0%s\0' "$relative" || return 1
      readlink -- "$entry" || return 1
      printf '\0' || return 1
    elif [ -d "$entry" ]; then
      metadata="$(stat -c '%u:%g:%a' -- "$entry")" || return 1
      printf 'D\0%s\0%s\0' "$relative" "$metadata" || return 1
      nobrand_backup_restore_snapshot_manifest_walk "$entry" "${relative}/" || return 1
    elif [ -f "$entry" ]; then
      metadata="$(stat -c '%u:%g:%a' -- "$entry")" || return 1
      digest="$(nobrand_sha256_file "$entry" 2>/dev/null)" || return 1
      [[ "$digest" =~ ^[0-9a-f]{64}$ ]] || return 1
      printf 'F\0%s\0%s\0%s\0' "$relative" "$metadata" "$digest" || return 1
    else
      return 1
    fi
  done
}

nobrand_backup_restore_snapshot_manifest_generate() (
  local snapshot_dir="${1:-$NOBRAND_BACKUP_RESTORE_SNAPSHOT_DIR}"
  local label root metadata
  LC_ALL=C
  export LC_ALL
  shopt -s dotglob nullglob
  printf 'nobrand-backup-restore-roots-v1\0' || return 1
  for label in state config; do
    root="$snapshot_dir/$label"
    [ -d "$root" ] && [ ! -L "$root" ] || return 1
    metadata="$(stat -c '%u:%g:%a' -- "$root")" || return 1
    printf 'R\0%s\0%s\0' "$label" "$metadata" || return 1
    nobrand_backup_restore_snapshot_manifest_walk "$root" "${label}/" || return 1
  done
)

nobrand_backup_restore_snapshot_manifest_write_at() {
  local transaction_dir="$1" snapshot_dir="$2" manifest_file="$3" tmp
  [ "$snapshot_dir" = "${transaction_dir}/snapshot" ] \
    && [ "$manifest_file" = "${transaction_dir}/snapshot-roots.manifest" ] \
    || return 1
  [ -d "$transaction_dir" ] && [ ! -L "$transaction_dir" ] \
    || return 1
  tmp="$(mktemp "${transaction_dir}/.snapshot-roots.XXXXXX")" || return 1
  if ! nobrand_backup_restore_snapshot_manifest_generate "$snapshot_dir" >"$tmp" \
     || ! chmod 0600 "$tmp"; then
    rm -f -- "$tmp"
    return 1
  fi
  chown root:root "$tmp" 2>/dev/null || true
  mv -f -- "$tmp" "$manifest_file" || {
    rm -f -- "$tmp"
    return 1
  }
}

nobrand_backup_restore_snapshot_manifest_valid_at() (
  local snapshot_dir="$1" manifest_file="$2"
  set -o pipefail
  [ -f "$manifest_file" ] \
    && [ ! -L "$manifest_file" ] \
    && secure_stat_path "$manifest_file" file \
    && [ "$(stat -c '%a' "$manifest_file" 2>/dev/null)" = 600 ] \
    || return 1
  nobrand_backup_restore_snapshot_manifest_generate "$snapshot_dir" \
    | cmp -s -- "$manifest_file" -
)

nobrand_backup_restore_snapshot_manifest_valid() {
  nobrand_backup_restore_transaction_paths_valid || return 1
  nobrand_backup_restore_snapshot_manifest_valid_at \
    "$NOBRAND_BACKUP_RESTORE_SNAPSHOT_DIR" "$NOBRAND_BACKUP_RESTORE_ROOTS_MANIFEST"
}

nobrand_backup_restore_transaction_valid_at() {
  local transaction_dir="$1" metadata_file="$2" snapshot_dir="$3" manifest_file="$4"
  local status started state_created config_created fresh_restore path
  [ "$metadata_file" = "${transaction_dir}/transaction.env" ] \
    && [ "$snapshot_dir" = "${transaction_dir}/snapshot" ] \
    && [ "$manifest_file" = "${transaction_dir}/snapshot-roots.manifest" ] \
    || return 1
  [ -d "$transaction_dir" ] && [ ! -L "$transaction_dir" ] \
    && [ -d "$snapshot_dir" ] && [ ! -L "$snapshot_dir" ] \
    && [ -f "$metadata_file" ] && [ ! -L "$metadata_file" ] \
    && [ -f "$manifest_file" ] \
    && [ ! -L "$manifest_file" ] \
    || return 1
  secure_stat_path "$NOBRAND_LIFECYCLE_DIR" dir \
    && secure_stat_path "$transaction_dir" dir \
    && secure_stat_path "$snapshot_dir" dir \
    && secure_stat_path "$metadata_file" file \
    && secure_stat_path "$manifest_file" file || return 1
  [ "$(stat -c '%a' "$transaction_dir" 2>/dev/null)" = 700 ] \
    && [ "$(stat -c '%a' "$snapshot_dir" 2>/dev/null)" = 700 ] \
    && [ "$(stat -c '%a' "$metadata_file" 2>/dev/null)" = 600 ] \
    && [ "$(stat -c '%a' "$manifest_file" 2>/dev/null)" = 600 ] \
    || return 1
  awk -F= '
    BEGIN {
      required["FORMAT"]=1; required["STATUS"]=1; required["STARTED_AT"]=1;
      required["STATE_ROOT_CREATED"]=1; required["CONFIG_ROOT_CREATED"]=1;
      required["FRESH_MANAGER_RESTORE"]=1
    }
    NF != 2 || !($1 in required) || seen[$1]++ { bad=1 }
    END {
      for (key in required) if (seen[key] != 1) bad=1
      exit bad ? 1 : 0
    }
  ' "$metadata_file" || return 1
  [ "$(nb_lifecycle_field FORMAT "$metadata_file")" = nobrand-backup-restore-v1 ] \
    || return 1
  status="$(nb_lifecycle_field STATUS "$metadata_file")"
  started="$(nb_lifecycle_field STARTED_AT "$metadata_file")"
  state_created="$(nb_lifecycle_field STATE_ROOT_CREATED "$metadata_file")"
  config_created="$(nb_lifecycle_field CONFIG_ROOT_CREATED "$metadata_file")"
  fresh_restore="$(nb_lifecycle_field FRESH_MANAGER_RESTORE "$metadata_file")"
  case "$status" in
    applying|runtime-applying|rollback-roots|pending-ssh-confirmation) ;;
    *) return 1 ;;
  esac
  [[ "$started" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] \
    || return 1
  case "$state_created:$config_created:$fresh_restore" in
    0:0:0|0:1:0|1:0:0|1:1:1) ;;
    *) return 1 ;;
  esac
  for path in state config ssh-external forward-external; do
    [ -d "$snapshot_dir/$path" ] \
      && [ ! -L "$snapshot_dir/$path" ] || return 1
  done
  nobrand_backup_restore_snapshot_manifest_valid_at "$snapshot_dir" "$manifest_file"
}

nobrand_backup_restore_transaction_valid() {
  nobrand_backup_restore_transaction_paths_valid || return 1
  nobrand_backup_restore_transaction_valid_at \
    "$NOBRAND_BACKUP_RESTORE_TX_DIR" "$NOBRAND_BACKUP_RESTORE_META_FILE" \
    "$NOBRAND_BACKUP_RESTORE_SNAPSHOT_DIR" "$NOBRAND_BACKUP_RESTORE_ROOTS_MANIFEST"
}

nobrand_backup_restore_transaction_write_at() {
  local transaction_dir="$1" metadata_file="$2" snapshot_dir="$3" manifest_file="$4"
  local status="$5" state_created="$6" config_created="$7" fresh_restore="$8"
  local started="${9:-}" tmp
  [ "$metadata_file" = "${transaction_dir}/transaction.env" ] \
    && [ "$snapshot_dir" = "${transaction_dir}/snapshot" ] \
    && [ "$manifest_file" = "${transaction_dir}/snapshot-roots.manifest" ] \
    || return 1
  case "$status" in
    applying|runtime-applying|rollback-roots|pending-ssh-confirmation) ;;
    *) return 1 ;;
  esac
  case "$state_created:$config_created:$fresh_restore" in
    0:0:0|0:1:0|1:0:0|1:1:1) ;;
    *) return 1 ;;
  esac
  if [ -z "$started" ] && [ -f "$metadata_file" ]; then
    started="$(nb_lifecycle_field STARTED_AT "$metadata_file")"
  fi
  [ -n "$started" ] || started="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  [[ "$started" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] \
    || return 1
  [ -d "$transaction_dir" ] && [ ! -L "$transaction_dir" ] \
    || return 1
  nobrand_backup_restore_snapshot_manifest_valid_at "$snapshot_dir" "$manifest_file" \
    || return 1
  tmp="$(mktemp "${transaction_dir}/.transaction.XXXXXX")" || return 1
  if ! printf '%s\n' \
      'FORMAT=nobrand-backup-restore-v1' \
      "STATUS=${status}" \
      "STARTED_AT=${started}" \
      "STATE_ROOT_CREATED=${state_created}" \
      "CONFIG_ROOT_CREATED=${config_created}" \
      "FRESH_MANAGER_RESTORE=${fresh_restore}" >"$tmp" \
     || ! chmod 0600 "$tmp"; then
    rm -f "$tmp"
    return 1
  fi
  chown root:root "$tmp" 2>/dev/null || true
  mv -f -- "$tmp" "$metadata_file" || {
    rm -f "$tmp"
    return 1
  }
}

nobrand_backup_restore_transaction_write() {
  nobrand_backup_restore_transaction_paths_valid || return 1
  nobrand_backup_restore_transaction_write_at \
    "$NOBRAND_BACKUP_RESTORE_TX_DIR" "$NOBRAND_BACKUP_RESTORE_META_FILE" \
    "$NOBRAND_BACKUP_RESTORE_SNAPSHOT_DIR" "$NOBRAND_BACKUP_RESTORE_ROOTS_MANIFEST" \
    "$@"
}

nobrand_backup_restore_transaction_mark_ssh_pending() {
  local status state_created config_created fresh_restore
  nobrand_backup_restore_transaction_present || return 0
  nobrand_backup_restore_transaction_valid || return 1
  status="$(nb_lifecycle_field STATUS "$NOBRAND_BACKUP_RESTORE_META_FILE")"
  [ "$status" != pending-ssh-confirmation ] || return 0
  [ "$status" = runtime-applying ] || return 1
  state_created="$(nb_lifecycle_field STATE_ROOT_CREATED "$NOBRAND_BACKUP_RESTORE_META_FILE")"
  config_created="$(nb_lifecycle_field CONFIG_ROOT_CREATED "$NOBRAND_BACKUP_RESTORE_META_FILE")"
  fresh_restore="$(nb_lifecycle_field FRESH_MANAGER_RESTORE "$NOBRAND_BACKUP_RESTORE_META_FILE")"
  nobrand_backup_restore_transaction_write pending-ssh-confirmation \
    "$state_created" "$config_created" "$fresh_restore"
}

nobrand_backup_restore_staging_cleanup() (
  local entry name
  nobrand_backup_restore_transaction_paths_valid || return 1
  [ -e "$NOBRAND_LIFECYCLE_DIR" ] || return 0
  [ -d "$NOBRAND_LIFECYCLE_DIR" ] && [ ! -L "$NOBRAND_LIFECYCLE_DIR" ] \
    || return 1
  shopt -s nullglob
  for entry in "$NOBRAND_LIFECYCLE_DIR"/.backup-restore.prepare.*; do
    name="${entry##*/}"
    [[ "$name" =~ ^\.backup-restore\.prepare\.[A-Za-z0-9]{6}$ ]] || return 1
    [ -d "$entry" ] && [ ! -L "$entry" ] \
      && [ "$(stat -c '%a' "$entry" 2>/dev/null)" = 700 ] \
      && secure_stat_path "$entry" dir || return 1
    rm -rf -- "$entry" || return 1
  done
)

# A no-op boundary used by the focused transaction test to stop a real child
# process at exact preparation phases. Production callers always continue.
nobrand_backup_restore_prepare_checkpoint() {
  : "$1"
}

nobrand_backup_restore_transaction_prepare() {
  local safe_state="$1" safe_config="$2"
  local state_created="$3" config_created="$4" fresh_restore="$5"
  local status="${6:-applying}" prepare_dir snapshot metadata manifest
  case "$status" in
    applying|runtime-applying|rollback-roots|pending-ssh-confirmation) ;;
    *) return 1 ;;
  esac
  case "$state_created:$config_created:$fresh_restore" in
    0:0:0|0:1:0|1:0:0|1:1:1) ;;
    *) return 1 ;;
  esac
  nobrand_backup_restore_transaction_paths_valid || return 1
  nobrand_backup_restore_transaction_present && return 1
  nb_lifecycle_prepare_dir || return 1
  nobrand_backup_restore_staging_cleanup || return 1
  prepare_dir="$(mktemp -d "${NOBRAND_LIFECYCLE_DIR}/.backup-restore.prepare.XXXXXX")" \
    || return 1
  if ! chmod 0700 "$prepare_dir"; then
    rm -rf -- "$prepare_dir"
    return 1
  fi
  chown root:root "$prepare_dir" 2>/dev/null || true
  snapshot="$prepare_dir/snapshot"
  metadata="$prepare_dir/transaction.env"
  manifest="$prepare_dir/snapshot-roots.manifest"
  if ! mkdir "$snapshot" \
     || ! chmod 0700 "$snapshot"; then
    rm -rf -- "$prepare_dir"
    return 1
  fi
  chown root:root "$snapshot" 2>/dev/null || true
  if ! mkdir "$snapshot/state" "$snapshot/config" "$snapshot/ssh-external" \
      "$snapshot/forward-external"; then
    rm -rf -- "$prepare_dir"
    return 1
  fi
  nobrand_backup_restore_prepare_checkpoint snapshot-directory-ready
  if [ "$state_created" -eq 0 ]; then
    if ! cp -a "$safe_state/." "$snapshot/state/" \
       || ! nobrand_backup_tree_matches "$safe_state" "$snapshot/state"; then
      rm -rf -- "$prepare_dir"
      return 1
    fi
  elif [ -e "$safe_state" ] || [ -L "$safe_state" ]; then
    rm -rf -- "$prepare_dir"
    return 1
  fi
  if [ "$config_created" -eq 0 ]; then
    if ! cp -a "$safe_config/." "$snapshot/config/" \
       || ! nobrand_backup_tree_matches "$safe_config" "$snapshot/config"; then
      rm -rf -- "$prepare_dir"
      return 1
    fi
  elif [ -e "$safe_config" ] || [ -L "$safe_config" ]; then
    rm -rf -- "$prepare_dir"
    return 1
  fi
  nobrand_backup_restore_prepare_checkpoint managed-roots-snapshotted
  if ! ssh_tunnel_snapshot_external_state "$snapshot/ssh-external" \
     || ! forward_snapshot_restore_side_effects "$snapshot/forward-external"; then
    rm -rf -- "$prepare_dir"
    return 1
  fi
  nobrand_backup_restore_prepare_checkpoint external-state-snapshotted
  if ! nobrand_backup_restore_snapshot_manifest_write_at \
      "$prepare_dir" "$snapshot" "$manifest"; then
    rm -rf -- "$prepare_dir"
    return 1
  fi
  nobrand_backup_restore_prepare_checkpoint manifest-ready
  if ! nobrand_backup_restore_transaction_write_at \
      "$prepare_dir" "$metadata" "$snapshot" "$manifest" "$status" \
      "$state_created" "$config_created" "$fresh_restore" \
     || ! nobrand_backup_restore_transaction_valid_at \
      "$prepare_dir" "$metadata" "$snapshot" "$manifest"; then
    rm -rf -- "$prepare_dir"
    return 1
  fi
  nobrand_backup_restore_prepare_checkpoint metadata-ready
  if nobrand_backup_restore_transaction_present \
     || ! mv -T -- "$prepare_dir" "$NOBRAND_BACKUP_RESTORE_TX_DIR"; then
    rm -rf -- "$prepare_dir"
    return 1
  fi
  nobrand_backup_restore_prepare_checkpoint transaction-published
  nobrand_backup_restore_transaction_valid
}

nobrand_backup_restore_transaction_cleanup() {
  nobrand_backup_restore_transaction_paths_valid || return 1
  nobrand_backup_restore_transaction_present || return 0
  [ -d "$NOBRAND_BACKUP_RESTORE_TX_DIR" ] && [ ! -L "$NOBRAND_BACKUP_RESTORE_TX_DIR" ] \
    || return 1
  secure_stat_path "$NOBRAND_BACKUP_RESTORE_TX_DIR" dir || return 1
  rm -rf -- "$NOBRAND_BACKUP_RESTORE_TX_DIR" || return 1
  rmdir "$NOBRAND_LIFECYCLE_DIR" 2>/dev/null || true
}

nobrand_backup_restore_recover_applying() {
  local status state_root_created config_root_created fresh_restore
  local snapshot safe_state safe_config restore_root cleanup_dir
  local cleanup_failed=0 rollback_failed=0 managed_roots_restored=0
  nobrand_backup_restore_transaction_valid || {
    warn "$(t '备份恢复的持久事务元数据无效；恢复快照已保留' \
      'Durable backup-restore transaction metadata is invalid; the recovery snapshot was retained')"
    return 1
  }
  status="$(nb_lifecycle_field STATUS "$NOBRAND_BACKUP_RESTORE_META_FILE")"
  case "$status" in
    applying|runtime-applying|rollback-roots) ;;
    *) return 1 ;;
  esac
  state_root_created="$(nb_lifecycle_field STATE_ROOT_CREATED "$NOBRAND_BACKUP_RESTORE_META_FILE")"
  config_root_created="$(nb_lifecycle_field CONFIG_ROOT_CREATED "$NOBRAND_BACKUP_RESTORE_META_FILE")"
  fresh_restore="$(nb_lifecycle_field FRESH_MANAGER_RESTORE "$NOBRAND_BACKUP_RESTORE_META_FILE")"
  snapshot="$NOBRAND_BACKUP_RESTORE_SNAPSHOT_DIR"
  safe_state="$(nb_assert_safe_nobrand_root "$NOBRAND_STATE_DIR" NOBRAND_STATE_DIR)" \
    || return 1
  safe_config="$(nb_assert_safe_nobrand_root "$NOBRAND_CONFIG_DIR" NOBRAND_CONFIG_DIR)" \
    || return 1

  # A crash can leave either managed root empty or only partly imported. Make
  # only the two exact, validated NoBrand roots available for the idempotent
  # rollback; never initialize a new registry before the snapshot is restored.
  for restore_root in "$safe_state" "$safe_config"; do
    if [ -e "$restore_root" ] || [ -L "$restore_root" ]; then
      [ -d "$restore_root" ] && [ ! -L "$restore_root" ] \
        && secure_stat_path "$restore_root" dir || return 1
    else
      mkdir -p "$restore_root" \
        && chmod 0700 "$restore_root" \
        && chown root:root "$restore_root" 2>/dev/null \
        && secure_stat_path "$restore_root" dir || return 1
    fi
  done

  # An armed/running SSH watchdog can still write its saved state after this
  # process restores the global snapshot. Claim or observe its completion
  # before touching any rollback material; otherwise retain everything.
  if ! ssh_tunnel_cancel_pending_watchdog 2>/dev/null \
     || ! ssh_tunnel_cleanup_disarmed_watchdogs 2>/dev/null; then
    warn "$(t "SSH watchdog 的回滚所有权尚未解决；备份恢复快照保留在: ${snapshot}" \
      "SSH watchdog rollback ownership is unresolved; the backup-restore snapshot is retained at: ${snapshot}")"
    return 75
  fi
  # An imported primary graph may already be serving when a later acceptance
  # fails. Quiesce it before replacing its database or generation directories.
  if nb_splicore_installed; then
    nb_splicore_call stop || return 1
  fi

  # `applying` cannot have crossed the verified-root commit below, so no
  # runtime/external resource was touched. `runtime-applying` still has the
  # imported state needed for exact attempt cleanup. Never advance past it if
  # state-driven cleanup fails: a retry must see the same imported ownership.
  if [ "$status" = runtime-applying ]; then
    if [ "$fresh_restore" -eq 1 ]; then
      nobrand_remove_fresh_restore_protocol_resources 2>/dev/null \
        || cleanup_failed=1
    fi
    forward_remove_restore_attempt_resources 2>/dev/null || cleanup_failed=1
    if [ "$fresh_restore" -eq 1 ]; then
      for cleanup_dir in "$NOBRAND_BIN_DIR" "$NOBRAND_LIB_DIR"; do
        if [ -e "$cleanup_dir" ] || [ -L "$cleanup_dir" ]; then
          [ -d "$cleanup_dir" ] && [ ! -L "$cleanup_dir" ] \
            || cleanup_failed=1
          rmdir "$cleanup_dir" 2>/dev/null || true
        fi
      done
    fi
  fi
  if [ "$cleanup_failed" -ne 0 ]; then
    warn "$(t "中断恢复所创建的资源未能完整清理；导入状态与恢复快照均已保留在: ${snapshot}" \
      "Resources created by the interrupted restore could not be cleaned completely; imported state and the recovery snapshot are retained at: ${snapshot}")"
    return 1
  fi

  if [ "$status" != applying ]; then
    forward_restore_side_effect_snapshot "$snapshot/forward-external" 2>/dev/null \
      || rollback_failed=1
    ssh_tunnel_restore_external_snapshot \
      "$snapshot/ssh-external" "$snapshot/ssh-external/created.log" 2>/dev/null \
      || rollback_failed=1
  fi
  if [ "$status" = runtime-applying ]; then
    # From this durable point onward live state may already be the original
    # snapshot, so retries must not use it as restore-attempt ownership.
    nobrand_backup_restore_transaction_write rollback-roots \
      "$state_root_created" "$config_root_created" "$fresh_restore" || {
      warn "$(t '无法记录备份恢复的回滚阶段；导入状态与恢复快照均已保留' \
        'Could not record the backup-restore rollback phase; imported state and the recovery snapshot were retained')"
      return 1
    }
    status=rollback-roots
  fi

  if nobrand_backup_restore_managed_roots "$safe_state" "$safe_config" "$snapshot"; then
    managed_roots_restored=1
  else
    rollback_failed=1
  fi
  if [ "$managed_roots_restored" -eq 1 ]; then
    if [ "$state_root_created" -eq 1 ]; then
      rmdir "$safe_state" 2>/dev/null || rollback_failed=1
    fi
    if [ "$config_root_created" -eq 1 ]; then
      rmdir "$safe_config" 2>/dev/null || rollback_failed=1
    fi
    if [ "$state_root_created" -eq 0 ] && [ "$config_root_created" -eq 0 ]; then
      nb_init_state_layout 2>/dev/null || rollback_failed=1
      nobrand_start_enabled_services 2>/dev/null || rollback_failed=1
    fi
  fi
  if [ "$rollback_failed" -ne 0 ]; then
    warn "$(t "中断的备份恢复未能完整回滚；唯一恢复快照保留在: ${snapshot}" \
      "The interrupted backup restore could not be rolled back completely; the only recovery snapshot is retained at: ${snapshot}")"
    return 1
  fi
  nobrand_backup_restore_transaction_cleanup || {
    warn "$(t "中断的备份恢复已回滚，但恢复快照无法安全清理，已保留在: ${snapshot}" \
      "The interrupted backup restore was rolled back, but its snapshot could not be safely retired and remains at: ${snapshot}")"
    return 1
  }
}

nobrand_backup_restore_confirmation_finalize() {
  local status
  nobrand_backup_restore_transaction_present || return 0
  nobrand_backup_restore_transaction_valid || {
    warn "$(t '备份恢复的持久事务元数据无效；恢复快照已保留' \
      'Durable backup-restore transaction metadata is invalid; the recovery snapshot was retained')"
    return 1
  }
  status="$(nb_lifecycle_field STATUS "$NOBRAND_BACKUP_RESTORE_META_FILE")"
  if [ "$status" != pending-ssh-confirmation ]; then
    warn "$(t '备份恢复仍处于应用阶段；必须先从持久快照回滚，拒绝清理恢复证据' \
      'The backup restore is still applying; its durable snapshot must be recovered before recovery evidence can be retired')"
    return 1
  fi
  # Only a restore that actually entered SSH confirmation can write this
  # status. Absence is therefore evidence loss, not successful acceptance.
  if ! ssh_tunnel_state_exists \
     || ! ssh_tunnel_state_identity_valid \
     || [ "$(ssh_tunnel_state_field pending_operation 2>/dev/null || true)" != '' ] \
     || [ "$(ssh_tunnel_state_field pending_watchdog_token 2>/dev/null || true)" != '' ] \
     || [ "$(ssh_tunnel_state_field pending_watchdog_pid 2>/dev/null || true)" != '' ] \
     || [ "$(ssh_tunnel_state_field pending_origin_connection 2>/dev/null || true)" != '' ] \
     || [ "$(ssh_tunnel_state_field policy_applied 2>/dev/null || true)" != true ]; then
      warn "$(t 'SSH 验收状态不完整；备份恢复快照已保留' \
        'SSH acceptance state is incomplete; the backup-restore snapshot was retained')"
      return 1
  fi
  nobrand_backup_restore_transaction_cleanup || {
    warn "$(t 'SSH 已确认，但备份恢复快照无法安全清理，已保留供检查' \
      'SSH was confirmed, but the backup-restore snapshot could not be safely retired and was retained for inspection')"
    return 1
  }
}

nobrand_backup_create() {
  local destination="${1:-}" stage archive_tmp
  if nb_splicore_installed; then
    [ -n "$destination" ] || destination="$(nb_backup_default_path)"
    ssh_tunnel_backup_state_ready || return 1
    nb_splicore_call backup --unified --file "$destination"
    return $?
  fi
  if nobrand_backup_restore_transaction_present; then
    die "$(t '存在尚未完成的备份恢复事务；拒绝创建可能误导的新备份' \
      'An unfinished backup-restore transaction exists; refusing to create a misleading new backup')"
    return 1
  fi
  nb_init_state_layout || return 1
  ssh_tunnel_backup_state_ready \
    || die "$(t 'SSH 策略确认或 watchdog 清理完成前不能创建备份' \
      'A backup cannot be created while SSH confirmation or watchdog cleanup is pending')"
  [ -n "$destination" ] || destination="$(nb_backup_default_path)"
  stage="$(mktemp_dir)" || return 1
  mkdir -p "$stage/state" "$stage/config" || { rm -rf -- "$stage"; return 1; }
  cp -a "$NOBRAND_STATE_DIR/." "$stage/state/" || { rm -rf -- "$stage"; return 1; }
  cp -a "$NOBRAND_CONFIG_DIR/." "$stage/config/" || { rm -rf -- "$stage"; return 1; }
  if [ -d "$stage/state/ssh-tunnel/watchdog" ]; then
    rmdir "$stage/state/ssh-tunnel/watchdog" \
      || { rm -rf -- "$stage"; return 1; }
  fi
  cat >"$stage/manifest.txt" <<EOF
project=NoBrand-OneClick
version=${SCRIPT_VERSION}
schema_version=${NOBRAND_SCHEMA_VERSION}
ownership=nobrand-v3
created_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
contents=state,config
EOF
  archive_tmp="$(mktemp_file .tar.gz)" || { rm -rf -- "$stage"; return 1; }
  if ! tar -C "$stage" -czf "$archive_tmp" manifest.txt state config; then
    rm -f "$archive_tmp"
    rm -rf -- "$stage"
    return 1
  fi
  mkdir -p "$(dirname "$destination")" || { rm -f "$archive_tmp"; rm -rf -- "$stage"; return 1; }
  chmod 0600 "$archive_tmp" || { rm -f "$archive_tmp"; rm -rf -- "$stage"; return 1; }
  mv -f "$archive_tmp" "$destination" || { rm -f "$archive_tmp"; rm -rf -- "$stage"; return 1; }
  rm -rf -- "$stage"
  t "NoBrand 备份已保存: ${destination}" "NoBrand backup saved: ${destination}"
}

nobrand_backup_list() {
  find "$NOBRAND_BACKUP_DIR" -maxdepth 1 -type f -name 'nobrand-backup-*.tar.gz' \
    -print 2>/dev/null | LC_ALL=C sort -r
}

# A backup contains authoritative state/config, but deliberately excludes
# downloaded runtimes and service-manager artifacts.  A restore into a
# manager-only installation therefore has to rebuild every runtime/service
# from the restored state before it can start anything.
nobrand_restore_protocol_runtimes() {
  nb_splicore_legacy_preflight || return 1
  if [ -e "${NOBRAND_STATE_DIR}/splicore/current" ] || nb_splicore_installed; then
    nb_splicore_call adopt-snapshot || return 1
  fi
  if vless_sudoku_state_exists; then
    NOBRAND_XRAY_SPECIALIZED=1 nobrand_install_xray_runtime 0 || return 1
    nobrand_write_vless_sudoku_service || return 1
  fi
  forward_realm_restore_runtime
}

nobrand_fresh_restore_runtime_preflight() {
  local staged_state="$1" path
  # Archive ownership and architecture were checked before extraction.
  [ -f "$staged_state/state.json" ] || return 1
  for path in "$NOBRAND_LIB_DIR" "$NOBRAND_VLESS_SYSTEMD_SERVICE" "$NOBRAND_REALM_SYSTEMD_SERVICE"; do
    [ ! -e "$path" ] && [ ! -L "$path" ] || return 1
  done
}

nobrand_remove_fresh_restore_protocol_resources() {
  nb_splicore_legacy_preflight || return 1
  local failed=0 port
  if nb_splicore_installed; then nb_splicore_call purge || failed=1; fi
  if vless_sudoku_state_exists; then
    port="$(vless_sudoku_state_field listen_port 2>/dev/null || true)"
    nobrand_remove_vless_sudoku_service || failed=1
    [ -z "$port" ] || nb_firewall_close_pairs "TCP|${port}" || failed=1
    nobrand_remove_xray_runtime_files || failed=1
  fi
  return "$failed"
}

nobrand_backup_stage_topology_valid() {
  local stage="$1" path unsafe=""
  [ -f "$stage/manifest.txt" ] && [ ! -L "$stage/manifest.txt" ] || return 1
  [ -d "$stage/state" ] && [ ! -L "$stage/state" ] \
    && [ -d "$stage/config" ] && [ ! -L "$stage/config" ] || return 1
  unsafe="$(find "$stage/state" "$stage/config" \
    ! -type f ! -type d -print -quit 2>/dev/null)" || return 1
  [ -z "$unsafe" ] || return 1
  for path in \
    "$stage/state/ssh-tunnel" \
    "$stage/state/ssh-tunnel/keys" \
    "$stage/state/ssh-tunnel/watchdog" \
    "$stage/config/ssh-tunnel" \
    "$stage/config/ssh-tunnel/authorized_keys" \
    "$stage/config/ssh-tunnel/accounts"; do
    if [ -e "$path" ] || [ -L "$path" ]; then
      [ -d "$path" ] && [ ! -L "$path" ] || return 1
    fi
  done
}

nobrand_backup_tree_matches() (
  local expected="$1" actual="$2" entry name counterpart expected_count=0 actual_count=0
  [ -d "$expected" ] && [ ! -L "$expected" ] \
    && [ -d "$actual" ] && [ ! -L "$actual" ] || return 1
  shopt -s dotglob nullglob
  for entry in "$expected"/*; do
    expected_count=$((expected_count + 1))
    name="${entry##*/}"
    counterpart="${actual}/${name}"
    if [ -L "$entry" ]; then
      [ -L "$counterpart" ] \
        && [ "$(readlink "$entry")" = "$(readlink "$counterpart")" ] || return 1
    elif [ -d "$entry" ]; then
      [ -d "$counterpart" ] && [ ! -L "$counterpart" ] \
        && [ "$(stat -c '%u:%g:%a' "$entry")" = "$(stat -c '%u:%g:%a' "$counterpart")" ] \
        && nobrand_backup_tree_matches "$entry" "$counterpart" || return 1
    elif [ -f "$entry" ]; then
      [ -f "$counterpart" ] && [ ! -L "$counterpart" ] \
        && [ "$(stat -c '%u:%g:%a' "$entry")" = "$(stat -c '%u:%g:%a' "$counterpart")" ] \
        && cmp -s "$entry" "$counterpart" || return 1
    else
      return 1
    fi
  done
  for entry in "$actual"/*; do
    actual_count=$((actual_count + 1))
  done
  [ "$expected_count" -eq "$actual_count" ]
)

nobrand_backup_restore_managed_roots() {
  local safe_state="$1" safe_config="$2" snapshot="$3"
  nobrand_backup_restore_snapshot_manifest_valid \
    && find "$safe_state" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + \
    && find "$safe_config" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + \
    && cp -a "$snapshot/state/." "$safe_state/" \
    && cp -a "$snapshot/config/." "$safe_config/" \
    && nobrand_backup_tree_matches "$snapshot/state" "$safe_state" \
    && nobrand_backup_tree_matches "$snapshot/config" "$safe_config"
}

nobrand_backup_restore() {
  local source="$1" stage snapshot safe_state safe_config ssh_restore_log restore_root cleanup_dir
  local state_root_created=0 config_root_created=0 fresh_manager_restore=0
  local restore_failed=0 rollback_failed=0 managed_roots_restored=0
  local ssh_confirmation_pending=0 pending_operation="" pending_token=""
  local ssh_restore_rc=0
  local primary_snapshot_active=0
  if nobrand_backup_restore_transaction_present; then
    if nobrand_backup_restore_transaction_valid; then
      die "$(t "存在尚未完成的备份恢复事务，恢复快照保留在: ${NOBRAND_BACKUP_RESTORE_SNAPSHOT_DIR}" \
        "An unfinished backup-restore transaction exists; its recovery snapshot is retained at: ${NOBRAND_BACKUP_RESTORE_SNAPSHOT_DIR}")"
    else
      die "$(t '检测到无效的备份恢复事务元数据；为避免覆盖恢复证据，操作已停止' \
        'Invalid backup-restore transaction metadata was detected; the operation stopped to preserve recovery evidence')"
    fi
    return 1
  fi
  [ -f "$source" ] || die "备份不存在: $source"
  safe_state="$(nb_assert_safe_nobrand_root "$NOBRAND_STATE_DIR" NOBRAND_STATE_DIR)" || return 1
  safe_config="$(nb_assert_safe_nobrand_root "$NOBRAND_CONFIG_DIR" NOBRAND_CONFIG_DIR)" || return 1
  ssh_tunnel_backup_state_ready \
    || {
      die "$(t '当前 SSH 策略仍在确认中或状态不完整；拒绝启动备份恢复' \
        'The current SSH policy is pending confirmation or incomplete; refusing to start backup restore')"
      return 1
    }
  nb_splicore_call inspect-backup --file "$source" >/dev/null || return 1
  tar -tzf "$source" 2>/dev/null | awk '
    /^\// || /(^|\/)\.\.($|\/)/ { bad=1 }
    END { exit bad ? 1 : 0 }
  ' || die '备份包含不安全路径，拒绝恢复'
  stage="$(mktemp_dir)" || return 1
  tar -C "$stage" -xzf "$source" || { rm -rf -- "$stage"; return 1; }
  nobrand_backup_stage_topology_valid "$stage" \
    || {
      rm -rf -- "$stage"
      die '备份包含不安全的文件类型或目录结构，拒绝恢复'
      return 1
    }
  grep -qx 'project=NoBrand-OneClick' "$stage/manifest.txt" 2>/dev/null \
    || { rm -rf -- "$stage"; die '不是 NoBrand-OneClick 备份'; }
  grep -qx 'schema_version=3' "$stage/manifest.txt" 2>/dev/null \
    && grep -qx 'ownership=nobrand-v3' "$stage/manifest.txt" 2>/dev/null \
    && nb_schema_v3_file_valid "$stage/state/state.json" \
    || { rm -rf -- "$stage"; die '备份不是 NoBrand schema v3，拒绝导入旧 state'; }
  ssh_tunnel_restore_preflight "$stage/state/ssh-tunnel/state.json" \
    || { rm -rf -- "$stage"; die "$(t 'SSH 隧道恢复身份冲突，拒绝覆盖系统用户' \
      'SSH Tunnel restore identity conflict; refusing to overwrite system users')"; }
  if [ -s "$stage/state/forward/state.json" ]; then
    forward_state_valid "$stage/state/forward/state.json" \
      || { rm -rf -- "$stage"; die "$(t '端口转发恢复状态无效' \
        'Port Forward restore state is invalid')"; }
  fi
  if [ -s "$stage/state/ingress.json" ]; then
    nb_ingress_state_valid "$stage/state/ingress.json" \
      || { rm -rf -- "$stage"; die "$(t 'Ingress 入口配置恢复状态无效' \
        'Ingress profile restore state is invalid')"; }
  fi
  if [ -s "$stage/state/ingress-firewall.json" ]; then
    nb_strict_firewall_state_valid "$stage/state/ingress-firewall.json" \
      || { rm -rf -- "$stage"; die "$(t 'Strict Ingress 防火墙恢复状态无效' \
        'Strict-ingress firewall restore state is invalid')"; }
  fi
  find "$stage/state" "$stage/config" -type f -name '*.json' -print0 2>/dev/null \
    | while IFS= read -r -d '' file; do jq empty "$file" >/dev/null || exit 1; done \
    || { rm -rf -- "$stage"; die '备份中存在无效 JSON'; }
  [ -e "$safe_state" ] || [ -L "$safe_state" ] || state_root_created=1
  [ -e "$safe_config" ] || [ -L "$safe_config" ] || config_root_created=1
  if [ "$state_root_created" -eq 1 ] && [ "$config_root_created" -eq 1 ]; then
    fresh_manager_restore=1
    nobrand_fresh_restore_runtime_preflight "$stage/state" \
      || { rm -rf -- "$stage"; die "$(t '仅管理器恢复时发生运行时或系统身份冲突' \
        'Manager-only restore has a runtime or system identity conflict')"; }
  fi
  # Validate any existing roots without changing their ownership or mode.
  # Missing roots remain absent until the complete recovery transaction is
  # atomically published below.
  for restore_root in "$safe_state" "$safe_config"; do
    if [ -e "$restore_root" ] || [ -L "$restore_root" ]; then
      [ -d "$restore_root" ] && [ ! -L "$restore_root" ] \
        && secure_stat_path "$restore_root" dir || {
        rm -rf -- "$stage"
        die "恢复根路径不是安全目录: $restore_root"
      }
    fi
  done
  # A primary generation contains SQLite and a Unix socket. Snapshot only a
  # stopped daemon, after all archive/ownership preflight has succeeded.
  if nb_splicore_installed; then
    primary_snapshot_active="$(nb_splicore_call status | jq -r 'if .active then 1 else 0 end')" || return 1
    nb_splicore_call stop || return 1
  fi
  if ! nobrand_backup_restore_transaction_prepare "$safe_state" "$safe_config" \
      "$state_root_created" "$config_root_created" "$fresh_manager_restore" applying; then
    [ "$primary_snapshot_active" -ne 1 ] || nb_splicore_call start || return 1
    rm -rf -- "$stage"
    return 1
  fi
  snapshot="$NOBRAND_BACKUP_RESTORE_SNAPSHOT_DIR"
  nobrand_backup_restore_transaction_valid || {
    rm -rf -- "$stage"
    warn "$(t "备份恢复事务无法安全校验；恢复快照已保留在: ${snapshot}" \
      "The backup-restore transaction could not be validated safely; its recovery snapshot was retained at: ${snapshot}")"
    return 1
  }
  # Only a fully valid canonical transaction authorizes materializing missing
  # roots or tightening an existing root. Any failure from here is recoverable
  # from the already-published `applying` snapshot.
  for restore_root in "$safe_state" "$safe_config"; do
    if [ -e "$restore_root" ] || [ -L "$restore_root" ]; then
      [ -d "$restore_root" ] && [ ! -L "$restore_root" ] || {
        rm -rf -- "$stage"
        warn "$(t "恢复根路径在事务发布后发生变化；恢复快照已保留在: ${snapshot}" \
          "A restore root changed after transaction publication; the recovery snapshot is retained at: ${snapshot}")"
        return 1
      }
    else
      mkdir -p "$restore_root" || {
        rm -rf -- "$stage"
        warn "$(t "无法创建恢复根路径；恢复快照已保留在: ${snapshot}" \
          "A restore root could not be created; the recovery snapshot is retained at: ${snapshot}")"
        return 1
      }
    fi
    chmod 0700 "$restore_root" \
      && chown root:root "$restore_root" 2>/dev/null \
      && secure_stat_path "$restore_root" dir || {
        rm -rf -- "$stage"
        warn "$(t "无法保护恢复根路径；恢复快照已保留在: ${snapshot}" \
          "A restore root could not be secured; the recovery snapshot is retained at: ${snapshot}")"
        return 1
      }
  done
  ssh_restore_log="$snapshot/ssh-external/created.log"
  if ! nobrand_stop_all_services 2>/dev/null; then
    rollback_failed=0
    if [ "$state_root_created" -eq 1 ]; then
      rmdir "$safe_state" 2>/dev/null || rollback_failed=1
    fi
    if [ "$config_root_created" -eq 1 ]; then
      rmdir "$safe_config" 2>/dev/null || rollback_failed=1
    fi
    if [ "$state_root_created" -eq 0 ] && [ "$config_root_created" -eq 0 ]; then
      nb_init_state_layout 2>/dev/null || rollback_failed=1
      nobrand_start_enabled_services 2>/dev/null || rollback_failed=1
    fi
    if [ "$rollback_failed" -eq 0 ]; then
      nobrand_backup_restore_transaction_cleanup || rollback_failed=1
    fi
    if [ "$rollback_failed" -eq 0 ]; then
      rm -rf -- "$stage" || rollback_failed=1
    fi
    if [ "$rollback_failed" -ne 0 ]; then
      warn "$(t "停止现有服务失败，且原运行状态未能完整恢复；恢复材料保留在: ${snapshot}；导入暂存保留在: ${stage}" \
        "Stopping existing services failed and their original runtime state could not be fully restored; recovery material is retained at: ${snapshot}; import staging is retained at: ${stage}")"
      return 1
    fi
    die "$(t '无法安全停止现有 NoBrand 服务；备份尚未导入' \
      'Existing NoBrand services could not be stopped safely; the backup was not imported')"
    return 1
  fi
  if ! find "$safe_state" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + \
     || ! find "$safe_config" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + \
     || ! cp -a "$stage/state/." "$safe_state/" \
     || ! cp -a "$stage/config/." "$safe_config/" \
     || ! nobrand_backup_tree_matches "$stage/state" "$safe_state" \
     || ! nobrand_backup_tree_matches "$stage/config" "$safe_config"; then
    rollback_failed=0
    nobrand_backup_restore_managed_roots "$safe_state" "$safe_config" "$snapshot" \
      && managed_roots_restored=1 || rollback_failed=1
    if [ "$managed_roots_restored" -eq 1 ] && [ "$state_root_created" -eq 1 ]; then
      rmdir "$safe_state" 2>/dev/null || rollback_failed=1
    fi
    if [ "$managed_roots_restored" -eq 1 ] && [ "$config_root_created" -eq 1 ]; then
      rmdir "$safe_config" 2>/dev/null || rollback_failed=1
    fi
    if [ "$state_root_created" -eq 0 ] && [ "$config_root_created" -eq 0 ]; then
      nb_init_state_layout 2>/dev/null || rollback_failed=1
      nobrand_start_enabled_services 2>/dev/null || rollback_failed=1
    fi
    if [ "$rollback_failed" -ne 0 ]; then
      warn "$(t "导入 state/config 失败且原状态未能完整恢复；唯一恢复快照保留在: ${snapshot}；导入暂存保留在: ${stage}" \
        "Importing state/config failed and the original state could not be fully restored; the only recovery snapshot is retained at: ${snapshot}; import staging is retained at: ${stage}")"
      return 1
    fi
    rm -rf -- "$stage" || {
      warn "$(t "导入失败已回滚，但无法清理导入暂存；恢复快照保留在: ${snapshot}；暂存位于: ${stage}" \
        "The failed import was rolled back, but import staging could not be removed; the recovery snapshot is retained at: ${snapshot}; staging is at: ${stage}")"
      return 1
    }
    nobrand_backup_restore_transaction_cleanup || {
      warn "$(t "导入失败已回滚，但恢复快照无法安全清理，已保留在: ${snapshot}" \
        "The failed import was rolled back, but the recovery snapshot could not be safely removed and remains at: ${snapshot}")"
      return 1
    }
    die '恢复失败，已回滚原 NoBrand state/config'
    return 1
  fi
  if ! nobrand_backup_restore_transaction_write runtime-applying \
      "$state_root_created" "$config_root_created" "$fresh_manager_restore"; then
    restore_failed=1
  elif ! nb_init_state_layout; then
    restore_failed=1
  elif ! ssh_tunnel_prepare_restored_policy_state; then
    restore_failed=1
  elif ! nobrand_restore_protocol_runtimes; then
    restore_failed=1
  elif ssh_tunnel_restore_system_state "$ssh_restore_log"; then
    nobrand_start_enabled_services || restore_failed=1
  else
    ssh_restore_rc=$?
    if [ "$ssh_restore_rc" -eq 75 ]; then
      warn "$(t "SSH watchdog 的回滚所有权尚未解决；为避免并发覆盖，备份回滚已停止。恢复快照保留在: ${snapshot}；导入暂存保留在: ${stage}" \
        "SSH watchdog rollback ownership is unresolved; backup rollback stopped to avoid a concurrent overwrite. Recovery snapshot retained at: ${snapshot}; import staging retained at: ${stage}")"
      return 1
    fi
    restore_failed=1
  fi
  if [ "$restore_failed" -eq 0 ] && ssh_tunnel_state_exists; then
    pending_operation="$(ssh_tunnel_state_field pending_operation 2>/dev/null || true)"
    pending_token="$(ssh_tunnel_state_field pending_watchdog_token 2>/dev/null || true)"
    if [ "$pending_operation" = restore ] && [ -n "$pending_token" ] \
      && [ "$pending_token" != disabled ]; then
      ssh_confirmation_pending=1
      nobrand_backup_restore_transaction_mark_ssh_pending || restore_failed=1
    elif [ -n "$pending_operation" ] || [ -n "$pending_token" ] \
         || [ "$(ssh_tunnel_state_field policy_applied 2>/dev/null || true)" != true ]; then
      restore_failed=1
    fi
  fi
  if [ "$restore_failed" -ne 0 ]; then
    if ! nobrand_backup_restore_recover_applying; then
      warn "$(t "恢复验收失败且回滚未完整完成；唯一恢复快照保留在: ${snapshot}；导入暂存保留在: ${stage}" \
        "Restore acceptance failed and rollback did not complete; the only recovery snapshot is retained at: ${snapshot}; import staging is retained at: ${stage}")"
      return 1
    fi
    rm -rf -- "$stage" || {
      warn "$(t "恢复验收失败已回滚，但导入暂存无法清理: ${stage}" \
        "Restore acceptance failed and was rolled back, but import staging could not be removed: ${stage}")"
      return 1
    }
    die "$(t 'NoBrand 恢复的服务/策略验收失败，state/config 已回滚' \
      'NoBrand restore service/policy acceptance failed; state/config were rolled back')"
    return 1
  fi
  rm -rf -- "$stage" || {
    warn "$(t "备份已导入，但暂存目录无法清理；恢复快照保留在: ${snapshot}；暂存位于: ${stage}" \
      "The backup was imported, but import staging could not be removed; the recovery snapshot is retained at: ${snapshot}; staging is at: ${stage}")"
    return 1
  }
  if [ "$ssh_confirmation_pending" -eq 1 ]; then
    t "NoBrand 备份已导入；全局恢复快照将保留到全新管理员 SSH 连接确认完成: ${snapshot}" \
      "NoBrand backup imported; the global recovery snapshot will be retained until brand-new administrator SSH confirmation completes: ${snapshot}"
    return 0
  fi
  nobrand_backup_restore_transaction_cleanup || {
    warn "$(t "备份已恢复，但持久恢复快照无法安全清理，已保留在: ${snapshot}" \
      "The backup was restored, but its durable recovery snapshot could not be safely retired and remains at: ${snapshot}")"
    return 1
  }
  t 'NoBrand 备份恢复完成' 'NoBrand backup restored'
}

nobrand_backup_action() {
  case "${NOBRAND_BACKUP_ACTION:-create}" in
    create) nobrand_backup_create "${NOBRAND_BACKUP_PATH:-}" ;;
    list) nobrand_backup_list ;;
    restore)
      [ -n "${NOBRAND_BACKUP_PATH:-}" ] \
        || die "$(t '备份恢复需要文件路径' 'Backup restore requires a file path')"
      nobrand_backup_restore "$NOBRAND_BACKUP_PATH"
      ;;
  esac
}

nobrand_remove_owned_command() {
  local path="$1"
  [ -e "$path" ] || [ -L "$path" ] || return 0
  case "$path" in
    "$NOBRAND_INSTALL_SCRIPT_PATH"|"$NOBRAND_COMMAND_PATH"|"$NOBRAND_SHORT_COMMAND_PATH") ;;
    *) warn "拒绝删除 NoBrand command allowlist 以外的路径: $path"; return 1 ;;
  esac
  if [ -L "$path" ]; then
    case "$path:$(readlink "$path" 2>/dev/null || true)" in
      "$NOBRAND_COMMAND_PATH:$NOBRAND_INSTALL_SCRIPT_PATH"|\
      "$NOBRAND_SHORT_COMMAND_PATH:$NOBRAND_COMMAND_PATH") rm -f "$path" ;;
      *) warn "拒绝删除目标不属于 NoBrand 的符号链接: $path"; return 1 ;;
    esac
  elif grep -qF 'NoBrand-OneClick' "$path" 2>/dev/null; then
    rm -f "$path"
  else
    warn "拒绝删除内容不属于 NoBrand 的命令: $path"
    return 1
  fi
}

nobrand_clear_managed_root() {
  local root="$1"
  if [ ! -e "$root" ] && [ ! -L "$root" ]; then
    return 0
  fi
  [ -d "$root" ] && [ ! -L "$root" ] || {
    warn "拒绝清理非目录或符号链接 NoBrand root: $root"
    return 1
  }
  find "$root" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + || return 1
  rmdir "$root" 2>/dev/null || {
    [ ! -e "$root" ] || return 1
  }
}

nobrand_uninstall_postcondition() {
  local path failed=0
  for path in "$NOBRAND_STATE_DIR" "$NOBRAND_CONFIG_DIR" "$NOBRAND_LIB_DIR" \
    "$NOBRAND_SHORT_COMMAND_PATH" "$NOBRAND_COMMAND_PATH" "$NOBRAND_INSTALL_SCRIPT_PATH"; do
    if [ -e "$path" ] || [ -L "$path" ]; then
      warn "完整卸载验收发现 NoBrand 残留: $path"
      failed=1
    fi
  done
  [ "$failed" -eq 0 ]
}

nobrand_uninstall_impl() {
  nb_splicore_legacy_preflight || return 1
  local port safe_state safe_config safe_lib pairs="" failed=0
  safe_state="$(nb_assert_safe_nobrand_root "$NOBRAND_STATE_DIR" NOBRAND_STATE_DIR)" || return 1
  safe_config="$(nb_assert_safe_nobrand_root "$NOBRAND_CONFIG_DIR" NOBRAND_CONFIG_DIR)" || return 1
  safe_lib="$(nb_assert_safe_nobrand_root "$NOBRAND_LIB_DIR" NOBRAND_LIB_DIR)" || return 1
  # Remove the externally shared sshd policy first. With the real watchdog this
  # is a two-phase operation: no other protocol is touched until a brand-new
  # administrator SSH session confirms that system access still works.
  if ssh_tunnel_state_exists; then
    ssh_tunnel_uninstall unified-uninstall || return 1
    if ssh_tunnel_state_exists \
       && [ "$(ssh_tunnel_state_field pending_operation 2>/dev/null || true)" = unified-uninstall ]; then
      t '统一卸载等待全新管理员 SSH 连接确认；确认前其它协议保持不变' \
        'Unified uninstall is waiting for a brand-new administrator SSH connection; other protocols remain unchanged until confirmation'
      return 0
    fi
  fi
  if nb_splicore_installed; then
    nb_splicore_call purge || return 1
  fi
  admin_lock_acquire || return 1
  if [ -s "$NOBRAND_FORWARD_STATE_FILE" ] || [ -s "$NOBRAND_REALM_RUNTIME_META" ] \
     || [ -e "$NOBRAND_REALM_SYSTEMD_SERVICE" ] || [ -e "$NOBRAND_REALM_OPENRC_SERVICE" ]; then
    forward_uninstall || failed=1
  elif command -v nft >/dev/null 2>&1 \
       && nft list table "$NOBRAND_FORWARD_NFT_FAMILY" "$NOBRAND_FORWARD_NFT_TABLE" >/dev/null 2>&1; then
    forward_remove_owned_nft_table || failed=1
  fi
  if vless_sudoku_state_exists; then
    port="$(vless_sudoku_state_field listen_port 2>/dev/null || true)"
    nobrand_remove_vless_sudoku_service || failed=1
    [ -z "$port" ] || nb_firewall_close_pairs "TCP|${port}" || failed=1
  fi
  # 清理可能由失败事务留下、但仍明确记录为 NoBrand-owned 的 firewall rows。
  if [ -s "$NOBRAND_FIREWALL_OWNED_STATE" ]; then
    while IFS='|' read -r _tool proto row_port; do
      case "$proto" in
        tcp|udp) printf -v pairs '%s%s|%s\n' "$pairs" "$(printf '%s' "$proto" | tr '[:lower:]' '[:upper:]')" "$row_port" ;;
      esac
    done <"$NOBRAND_FIREWALL_OWNED_STATE"
    [ -z "$pairs" ] || nb_firewall_close_pairs "$pairs" || failed=1
  fi
  if [ "$failed" -ne 0 ]; then
    admin_lock_release
    warn "$(t 'NoBrand 服务/防火墙清理未完整完成；保留 state 以便重试' \
      'NoBrand service/firewall cleanup was incomplete; state was kept for retry')"
    return 1
  fi
  [ "$(nb_service_manager)" != systemd ] \
    || systemctl daemon-reload 2>/dev/null || failed=1
  if [ "$failed" -ne 0 ]; then
    admin_lock_release
    warn "$(t 'NoBrand 服务运行时清理未完整完成；保留 state/config 及管理器以便安全重试' \
      'NoBrand service-runtime cleanup was incomplete; state/config and manager were kept for a safe retry')"
    return 1
  fi
  admin_lock_release

  nb_strict_firewall_clear_all || return 1
  rm -f "$NOBRAND_INGRESS_FIREWALL_STATE_FILE" "$NOBRAND_INGRESS_FIREWALL_RULESET"
  nb_lifecycle_checkpoint uninstall runtime-removed || return 1

  # State/config/lib roots are exact, validated NoBrand roots. Command removal
  # deliberately happens only after every protocol/resource cleanup succeeds.
  nb_lifecycle_checkpoint uninstall before-state-removal || return 1
  nobrand_clear_managed_root "$safe_state" || return 1
  nb_lifecycle_checkpoint uninstall state-removed || return 1
  nb_lifecycle_checkpoint uninstall before-config-removal || return 1
  nobrand_clear_managed_root "$safe_config" || return 1
  nb_lifecycle_checkpoint uninstall config-removed || return 1
  nobrand_clear_managed_root "$safe_lib" || return 1
  nb_lifecycle_checkpoint uninstall roots-removed || return 1
  nb_lifecycle_checkpoint uninstall before-manager-removal || return 1
  nobrand_remove_owned_command "$NOBRAND_SHORT_COMMAND_PATH" || failed=1
  nobrand_remove_owned_command "$NOBRAND_COMMAND_PATH" || failed=1
  nobrand_remove_owned_command "$NOBRAND_INSTALL_SCRIPT_PATH" || failed=1
  [ "$failed" -eq 0 ] || return 1
  nb_lifecycle_checkpoint uninstall manager-removed || return 1
}

nobrand_uninstall() {
  nb_splicore_legacy_preflight || return 1
  local state rc=0
  require_root || return 1
  if nobrand_backup_restore_transaction_present; then
    die "$(t '备份恢复事务尚未完成；请先通过修复流程完成 SSH 验收，拒绝卸载恢复证据' \
      'A backup-restore transaction is unfinished; complete SSH acceptance through repair before uninstalling recovery evidence')"
    return 1
  fi
  state="$(nb_classify_installation_state)" || return 1
  case "$state" in
    CLEAN)
      t 'NoBrand 管理资源已不存在，无需再次卸载。' \
        'NoBrand-managed resources are already absent; nothing remains to uninstall.'
      return 0
      ;;
    CURRENT_COMPLETE|CURRENT_PARTIAL_INSTALL|CURRENT_PARTIAL_REPAIR|\
      CURRENT_PARTIAL_CONFIGURE)
      nb_schema_v3_file_valid \
        || die '未检测到有效的 NoBrand schema v3 state，拒绝卸载未知资源'
      ;;
    CURRENT_PARTIAL_UNINSTALL) ;;
    LEGACY_UNSUPPORTED) nb_fail_legacy_state; return 1 ;;
    *) nb_fail_ambiguous_state; return 1 ;;
  esac
  if [ "${YES:-0}" -ne 1 ]; then
    confirm '确认完整卸载 NoBrand 3 管理的 Mieru/Snell/HY2/TUIC/VLESS REALITY/VLESS Sudoku/SSH Tunnel/Forward/Common？[y/N]: ' \
      'Completely uninstall NoBrand-3-managed Mieru/Snell/HY2/TUIC/VLESS REALITY/VLESS Sudoku/SSH Tunnel/Forward/Common resources? [y/N]: ' \
      n \
      || { t '已取消' 'Cancelled'; return 0; }
  fi
  nb_lifecycle_lock_acquire || return 1
  state="$(nb_classify_installation_state)" || {
    nb_lifecycle_lock_release
    return 1
  }
  case "$state" in
    CLEAN)
      nb_lifecycle_lock_release
      return 0
      ;;
    CURRENT_COMPLETE|CURRENT_PARTIAL_INSTALL|CURRENT_PARTIAL_REPAIR|\
      CURRENT_PARTIAL_CONFIGURE)
      if ! nb_schema_v3_file_valid; then
        nb_lifecycle_lock_release
        return 1
      fi
      ;;
    CURRENT_PARTIAL_UNINSTALL) ;;
    *)
      nb_lifecycle_lock_release
      nb_fail_ambiguous_state
      return 1
      ;;
  esac
  nb_lifecycle_pre_mutation_snapshot || {
    nb_lifecycle_lock_release
    return 1
  }
  nb_lifecycle_begin uninstall prepare 0 0 0 0 0 0 global || {
    nb_lifecycle_pre_mutation_disarm
    nb_lifecycle_lock_release
    return 1
  }
  nb_lifecycle_mark_mutation_started || {
    rc=$?
    nb_lifecycle_restore_pre_mutation || rc=1
    nb_lifecycle_lock_release
    return "$rc"
  }
  nobrand_uninstall_impl
  rc=$?
  if [ "$rc" -ne 0 ]; then
    nb_lifecycle_lock_release
    return "$rc"
  fi
  # SSH policy removal is deliberately two-phase. The first invocation stops
  # here with an in-progress uninstall transaction; a fresh administrator SSH
  # session confirms access and then resumes this same uninstall. Running the
  # final all-roots-absent postcondition now would misreport the intended wait
  # as a cleanup failure.
  if ssh_tunnel_state_exists \
     && [ "$(ssh_tunnel_state_field pending_operation 2>/dev/null || true)" = unified-uninstall ]; then
    nb_lifecycle_lock_release
    return 0
  fi
  nb_lifecycle_checkpoint uninstall before-final-validation || {
    rc=$?
    nb_lifecycle_lock_release
    return "$rc"
  }
  nobrand_uninstall_postcondition || {
    nb_lifecycle_lock_release
    return 1
  }
  nb_lifecycle_clear || {
    nb_lifecycle_lock_release
    return 1
  }
  nb_lifecycle_lock_release
  t 'NoBrand 3 的 Mieru/Snell/HY2/TUIC/VLESS REALITY/VLESS Sudoku/SSH Tunnel/Forward/Common 资源与 nobrand/nb 已完整删除；外部资源未触碰' \
    'NoBrand 3 Mieru/Snell/HY2/TUIC/VLESS REALITY/VLESS Sudoku/SSH Tunnel/Forward/Common resources and nobrand/nb were removed; external resources were untouched'
  t '如当前 Bash 会话仍缓存 nb/nobrand 路径，可执行 `hash -r` 清除命令缓存。' \
    'If the current Bash session still caches the nb/nobrand path, run `hash -r` to clear its command cache.'
  if [ "${MENU_MODE:-0}" -eq 1 ]; then
    # Status 4 is an ordinary shell status and cannot authenticate this path
    # by itself. The menu wrapper resets and checks this completion marker in
    # the same subprocess, after every global-uninstall postcondition above.
    NOBRAND_MENU_GLOBAL_UNINSTALL_CONFIRMED=1
    return "$NOBRAND_MENU_EXIT_SUCCESS"
  fi
}

nobrand_stop_all_services() {
  nb_splicore_legacy_preflight || return 1
  local failed=0
  if nb_splicore_installed; then nb_splicore_call stop || return 1; fi
  if vless_sudoku_state_exists; then nobrand_vless_sudoku_service_action stop || failed=1; fi
  if [ -s "$NOBRAND_FORWARD_STATE_FILE" ]; then forward_realm_service_action stop || failed=1; fi
  return "$failed"
}

nobrand_start_enabled_services() {
  nb_splicore_legacy_preflight || return 1
  if nb_splicore_installed; then nb_splicore_call start || return 1; fi
  if vless_sudoku_state_exists; then nobrand_vless_sudoku_service_action start || return 1; fi
  forward_realm_restore_runtime
}

# shellcheck shell=bash
# ---------- One NoBrand-owned Splicore artifact, daemon and transaction ----------
# nb_splicore_python is embedded by scripts/build.sh from runtime/splicore.py.
nb_splicore_legacy_notice() {
  cat >&2 <<'NOBRAND_LEGACY_NOTICE'
Legacy NoBrand multi-core installation detected.
Automatic in-place migration is not supported by this version.
No changes were made.

Recommended:
1. Back up current client information.
2. Remove the legacy installation using the matching legacy NoBrand version.
3. Perform a clean installation.
4. Import/use the newly generated client profiles.
NOBRAND_LEGACY_NOTICE
}

nb_splicore_json_marker() {
  [ -f "$1" ] && command -v python3 >/dev/null 2>&1 || return 1
  python3 - "$1" "$2" "$3" <<'NOBRAND_MARKER_PY'
import json, sys
try:
    with open(sys.argv[1], encoding="utf-8") as stream:
        data = json.load(stream)
    valid = isinstance(data, dict) and data.get(sys.argv[2]) == sys.argv[3]
except (OSError, ValueError):
    valid = False
sys.exit(0 if valid else 1)
NOBRAND_MARKER_PY
}

nb_splicore_legacy_preflight() {
  # Read only, dependency free, and before locks, packages, recovery or bootstrap.
  local path registry="${NOBRAND_STATE_DIR}/state.json" system="${NOBRAND_SYSTEM_ROOT:-}"
  local -a owned_paths=(
    "${NOBRAND_STATE_DIR}/mieru/install-state.env" "${NOBRAND_STATE_DIR}/mieru/users.json"
    "${NOBRAND_STATE_DIR}/mieru/.installed" "${NOBRAND_STATE_DIR}/hysteria2/state.json"
    "${NOBRAND_STATE_DIR}/tuic/runtime.json" "${NOBRAND_STATE_DIR}/snell/instances"
    "${NOBRAND_STATE_DIR}/tuic/instances" "${NOBRAND_STATE_DIR}/vless-reality/instances"
    "${NOBRAND_CONFIG_DIR}/hysteria2/config.json" "${NOBRAND_CONFIG_DIR}/vless-reality/instances"
    "${NOBRAND_LIB_DIR}/bin/mita" "${NOBRAND_LIB_DIR}/bin/sing-box"
    "${NOBRAND_LIB_DIR}/bin/hysteria" "${NOBRAND_LIB_DIR}/mieru-instance-run"
    "${NOBRAND_LEGACY_MIERU_STATE_DIR}"
    "${MITA_INSTANCE_SYSTEMD_TEMPLATE}" "${NOBRAND_SNELL_SYSTEMD_TEMPLATE}"
    "${NOBRAND_TUIC_SYSTEMD_TEMPLATE}" "${NOBRAND_REALITY_SYSTEMD_TEMPLATE}"
    "${NOBRAND_HY2_SYSTEMD_SERVICE}" "${NOBRAND_HY2_OPENRC_SERVICE}"
  )
  for path in "${owned_paths[@]}" \
    "${system}"/etc/systemd/system/nobrand-mieru*.service "${system}"/etc/systemd/system/nobrand-mieru*.timer \
    "${system}"/etc/systemd/system/nobrand-snell@*.service "${system}"/etc/systemd/system/nobrand-tuic@*.service \
    "${system}"/etc/systemd/system/nobrand-vless-reality@*.service \
    "${system}"/etc/init.d/nobrand-mieru-* "${system}"/etc/init.d/nobrand-snell-* \
    "${system}"/etc/init.d/nobrand-tuic-* "${system}"/etc/init.d/nobrand-vless-reality-*; do
    case "$path" in /etc/*|/var/lib/mita-oneclick) path="${system}${path}" ;; esac
    if [ -e "$path" ] || [ -L "$path" ]; then
      nb_splicore_legacy_notice
      return 1
    fi
  done
  # The shared Xray binary is also owned by the existing Sudoku exception.
  if { [ -e "$NOBRAND_XRAY_BIN" ] || [ -L "$NOBRAND_XRAY_BIN" ]; } \
     && [ ! -f "$NOBRAND_VLESS_STATE_FILE" ]; then
    nb_splicore_legacy_notice
    return 1
  fi
  if [ -e "$registry" ] || [ -L "$registry" ]; then
    if [ -L "$registry" ] || ! nb_splicore_json_marker "$registry" architecture splicore-native; then
      nb_splicore_legacy_notice
      return 1
    fi
  fi
  path="${NOBRAND_STATE_DIR}/splicore/current"
  if [ -e "$path" ] || [ -L "$path" ]; then
    if [ -L "$path" ]; then
      nb_splicore_json_marker "$path/desired.json" architecture splicore-native || { nb_splicore_legacy_notice; return 1; }
    else
      nb_splicore_json_marker "$path" owner nobrand-splicore-pointer-v1 || { nb_splicore_legacy_notice; return 1; }
    fi
  fi
}

nb_splicore_call() (
  export NOBRAND_STATE_DIR NOBRAND_CONFIG_DIR NOBRAND_LIB_DIR NOBRAND_LIFECYCLE_DIR
  export NOBRAND_LIFECYCLE_LOCK_FILE
  export PORT ADVERTISE_HOST ADVERTISE_PORT USERNAME PASSWORD PROTOCOL MTU
  export MULTIPLEXING HANDSHAKE_MODE TRAFFIC_PATTERN LOW_ENTROPY_MODE
  export USER_QUOTA_MB USER_EXPIRE USER_BANDWIDTH_MBPS USER_PACKAGE
  export PROFILE PROFILE_CLI MTU_CLI MULTIPLEXING_CLI HANDSHAKE_CLI TRAFFIC_CLI LOW_ENTROPY_CLI
  export PROTOCOL_CLI PORT_CLI PASSWORD_CLI ADVERTISE_CLI
  export SNELL_VERSION SNELL_PSK SNELL_QUIC_PROXY TUIC_SNI TUIC_USER HY2_SNI SCRIPT_VERSION
  export VLESS_REALITY_TARGET VLESS_REALITY_TARGET_PORT NOBRAND_SPLICORE_LISTEN NOBRAND_SPLICORE_INGRESS_ID
  NOBRAND_SPLICORE_MANAGER_SOURCE="$(nobrand_manager_source_path 2>/dev/null || true)"
  export NOBRAND_SPLICORE_MANAGER_SOURCE
  command -v python3 >/dev/null 2>&1 || {
    printf '[错误] Splicore 管理需要 python3；请安装项目公共依赖。\n' >&2
    return 1
  }
  nb_splicore_python "$@"
)

nb_splicore_installed() {
  [ -L "${NOBRAND_STATE_DIR}/splicore/current" ] \
    && [ -f "${NOBRAND_STATE_DIR}/splicore/current/desired.json" ] \
    && LC_ALL=C grep -Eq '"architecture"[[:space:]]*:[[:space:]]*"splicore-native"' \
      "${NOBRAND_STATE_DIR}/splicore/current/desired.json"
}

nb_splicore_protocol() {
  nb_splicore_legacy_preflight || return 1
  local protocol="$1" operation="$2" selector="${3:-}"
  local -a runtime_options=()
  if nobrand_ssh_confirmation_pending; then
    nobrand_pending_ssh_confirmation_notice
    return 1
  fi
  if [ "$protocol" = mieru ]; then
    apply_requested_profile_preserving_cli || return 1
    case "${MTU_REQUEST:-}" in
      '') ;;
      safe) MTU=1400 ;;
      auto) printf '[错误] 请先确定 MTU，使用 1280-1500 的显式值。\n' >&2; return 1 ;;
      *) valid_mtu "$MTU_REQUEST" || return 1; MTU="$MTU_REQUEST" ;;
    esac
  fi
  if [ "$operation" = set-endpoint ] || [ "$operation" = user-set-endpoint ]; then
    if [ "${ADVERTISE_CLI:-0}" -eq 0 ] && [ "${YES:-0}" -ne 1 ]; then
      nb_collect_advertise_endpoint_interactive "$protocol" "${NOBRAND_SPLICORE_MENU_PORT:-443}" || return 1
    fi
  fi
  if [ "$operation" = install ] || { [ "$protocol" = mieru ] && [ "$operation" = user-add ]; }; then
    if [ "${DRY_RUN:-0}" -ne 1 ]; then
      require_root || return 1
      if ! command -v python3 >/dev/null 2>&1 || ! command -v openssl >/dev/null 2>&1 \
         || ! command -v jq >/dev/null 2>&1 || ! command -v curl >/dev/null 2>&1; then
        nobrand_prepare_common || return 1
      fi
    fi
    if [ "$protocol" = mieru ]; then
      [ "${MIERU_CHANNEL_CLI:-0}" -eq 0 ] || {
        printf '[错误] 独立 Mita 版本选项不适用于固定的 Splicore；请使用 runtime --version。\n' >&2
        return 1
      }
    fi
    if [ "$protocol" = tuic ] && { [ "${TUIC_CHANNEL:-stable}" != stable ] || [ -n "${TUIC_VERSION:-}" ]; }; then
      printf '[错误] 独立 sing-box 版本选项不适用于固定的 Splicore。\n' >&2
      return 1
    fi
    if [ "${DRY_RUN:-0}" -ne 1 ]; then
      nb_prepare_ingress_request || return 1
      nb_prepare_ingress_deployment "$INGRESS_PROFILE_ID" native-bind || return 1
      NOBRAND_SPLICORE_INGRESS_ID="$INGRESS_PROFILE_ID"
      NOBRAND_SPLICORE_LISTEN="$INGRESS_LISTEN_HOST"
      export NOBRAND_SPLICORE_LISTEN
    fi
    if [ "${YES:-0}" -ne 1 ] && [ "${DRY_RUN:-0}" -ne 1 ]; then
      if [ -z "$selector" ]; then
        read_tty selector "$(t '节点名 [primary]: ' 'Node name [primary]: ')" || return 1
        selector="${selector:-primary}"
      fi
      if [ "$protocol" = mieru ] && [ "${PROFILE_CLI:-0}" -eq 0 ]; then
        choose_profile_interactive || return 1
      fi
    fi
    if [ -z "${PORT:-}" ] && [ "${DRY_RUN:-0}" -ne 1 ]; then
      case "$protocol" in snell|mieru|vless-reality) PORT="$(nb_select_available_port TCP "$INGRESS_PROFILE_ID")" ;; *) PORT="$(nb_select_available_port UDP "$INGRESS_PROFILE_ID")" ;; esac
      [ -n "$PORT" ] || return 1
    fi
    if [ -n "${PORT:-}" ]; then
      nb_valid_port "$PORT" || return 1
      if [ "${DRY_RUN:-0}" -ne 1 ]; then
        nb_ingress_port_is_reserved "$INGRESS_PROFILE_ID" "$PORT" && return 1
      fi
    fi
    if [ "${YES:-0}" -ne 1 ] && [ "${DRY_RUN:-0}" -ne 1 ] && [ "${ADVERTISE_CLI:-0}" -eq 0 ]; then
      nb_collect_advertise_endpoint_interactive "$protocol" "$PORT" || return 1
    fi
    if [ "${ADVERTISE_AUTO_REQUESTED:-0}" -eq 1 ] && [ -z "${ADVERTISE_HOST:-}" ]; then
      if [ "${DRY_RUN:-0}" -eq 1 ]; then
        NOBRAND_SPLICORE_AUTO_HOST=preview.invalid
      else
        NOBRAND_SPLICORE_AUTO_HOST="$(public_ip)" || return 1
      fi
      export NOBRAND_SPLICORE_AUTO_HOST
    fi
  fi
  [ "${DRY_RUN:-0}" -ne 1 ] || runtime_options+=(--dry-run)
  [ -z "${NOBRAND_SPLICORE_ARTIFACTS:-}" ] || runtime_options+=(--artifacts "$NOBRAND_SPLICORE_ARTIFACTS")
  nb_splicore_call protocol --protocol "$protocol" --operation "$operation" \
    --selector "$selector" "${runtime_options[@]}" || return $?
  if { [ "$operation" = install ] || [ "$operation" = user-add ]; } && [ "${DRY_RUN:-0}" -ne 1 ]; then
    nobrand_install_manager_script || return 1
  fi
}

nb_splicore_menu_select() {
  local protocol="$1" data choice="" count only_name selected_id
  nobrand_menu_selection_clear
  data="$(nb_splicore_call protocol --protocol "$protocol" --operation status)" || return 1
  printf '%s\n' "$data" | jq -r '.nodes[] | "  - \(.name) (\(.id))"'
  count="$(printf '%s\n' "$data" | jq '.nodes | length')"
  [ "$count" -gt 0 ] || { warn '尚无 Splicore 节点'; return 1; }
  only_name="$(printf '%s\n' "$data" | jq -r '.nodes[0].name')"
  read_tty choice "$(t '节点名: ' 'Node name: ')${only_name}" || return 1
  if [ -z "$choice" ]; then
    [ "$count" -eq 1 ] || return 1
    choice="$only_name"
  fi
  selected_id="$(printf '%s\n' "$data" | jq -r --arg name "$choice" '.nodes[] | select(.name==$name or .id==$name) | .id')"
  [ -n "$selected_id" ] && [[ "$selected_id" != *$'\n'* ]] || return 1
  NOBRAND_SPLICORE_MENU_PORT="$(printf '%s\n' "$data" | jq -r --arg id "$selected_id" '.nodes[] | select(.id==$id) | .listener.port')"
  export NOBRAND_SPLICORE_MENU_PORT
  nobrand_menu_selection_record splicore "$selected_id" "$choice" "${NOBRAND_STATE_DIR}/splicore/current/desired.json" || return 1
  case "$protocol" in snell) SNELL_NAME="$choice" ;; tuic) TUIC_NAME="$choice" ;; vless-reality) VLESS_REALITY_NAME="$choice" ;; esac
}

nb_splicore_route_main() {
  # Consumed by main after this function returns.
  # shellcheck disable=SC2034
  NOBRAND_SPLICORE_HANDLED=1
  case "${ACTION:-}" in
    nobrand-runtime) nb_splicore_call "${NOBRAND_RUNTIME_ARGS[@]}" ;;
    nobrand-snell)
      [[ "${SNELL_ACTION:-menu}" != menu && "${SNELL_ACTION:-menu}" != help ]] || { NOBRAND_SPLICORE_HANDLED=0; return 0; }
      nb_splicore_protocol snell "$SNELL_ACTION" "${SNELL_NAME:-}"
      ;;
    nobrand-tuic)
      [[ "${TUIC_ACTION:-menu}" != menu && "${TUIC_ACTION:-menu}" != help ]] || { NOBRAND_SPLICORE_HANDLED=0; return 0; }
      nb_splicore_protocol tuic "${TUIC_ACTION:-status}" "${TUIC_NAME:-}"
      ;;
    nobrand-hy2)
      [[ "${HY2_ACTION:-menu}" != menu && "${HY2_ACTION:-menu}" != help ]] || { NOBRAND_SPLICORE_HANDLED=0; return 0; }
      nb_splicore_protocol hysteria2 "$HY2_ACTION" hy2
      ;;
    nobrand-vless-reality)
      [[ "${VLESS_REALITY_ACTION:-menu}" != menu && "${VLESS_REALITY_ACTION:-menu}" != help ]] || { NOBRAND_SPLICORE_HANDLED=0; return 0; }
      nb_splicore_protocol vless-reality "$VLESS_REALITY_ACTION" "${VLESS_REALITY_NAME:-}"
      ;;
    install|reconfigure|upgrade|uninstall|start|stop|restart|user-add|user-del|user-show|user-list|user-enable|user-disable|user-set-endpoint|user-set-quota|user-set-expire|user-set-rate|user-scan|user-quota-reset|profile-config|traffic-config|low-entropy-config|client-modes-config|mtu-config|version-channel)
      nb_splicore_protocol mieru "$ACTION" "${USERNAME:-${USER_DEL_NAME:-${USER_SHOW_NAME:-}}}"
      ;;
    status|doctor|client-config|show)
      nb_splicore_protocol mieru "$ACTION" "${USERNAME:-${USER_SHOW_NAME:-}}"
      ;;
    user-manage) NOBRAND_SPLICORE_HANDLED=0 ;;
    user-*|rate-status|rate-restore)
      nb_splicore_protocol mieru "$ACTION" "${USERNAME:-}"
      ;;
    *) NOBRAND_SPLICORE_HANDLED=0 ;;
  esac
}

# Native architecture: ordinary protocols use src/19-splicore.sh.

service_manager() {
  if [ -d /run/systemd/system ] && command -v systemctl >/dev/null 2>&1; then
    echo systemd
  elif command -v rc-service >/dev/null 2>&1; then
    echo openrc
  else
    echo none
  fi
}

install_alpine_deps() {
  STAGE="安装 Alpine 依赖"
  run apk add --no-cache bash curl tar ca-certificates jq iptables iproute2 python3 procps-ng util-linux
  if [ "$(service_manager)" = openrc ]; then
    run apk add --no-cache openrc 2>/dev/null || true
  fi
}

ensure_management_dependencies() {
  local pm="${1:-$(detect_pkg_manager)}"
  STAGE="安装管理依赖"
  case "$pm" in
    deb)
      command -v curl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1 \
        && command -v tar >/dev/null 2>&1 && command -v sha256sum >/dev/null 2>&1 \
        && command -v python3 >/dev/null 2>&1 && command -v tc >/dev/null 2>&1 \
        && command -v sysctl >/dev/null 2>&1 && command -v unshare >/dev/null 2>&1 \
        && command -v setpriv >/dev/null 2>&1 && command -v flock >/dev/null 2>&1 \
        && return 0
      run apt-get update
      run apt-get install -y curl ca-certificates jq tar coreutils python3 iproute2 procps util-linux
      ;;
    rpm)
      command -v curl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1 \
        && command -v tar >/dev/null 2>&1 && command -v sha256sum >/dev/null 2>&1 \
        && command -v python3 >/dev/null 2>&1 && command -v tc >/dev/null 2>&1 \
        && command -v sysctl >/dev/null 2>&1 && command -v unshare >/dev/null 2>&1 \
        && command -v setpriv >/dev/null 2>&1 && command -v flock >/dev/null 2>&1 \
        && return 0
      if command -v dnf >/dev/null 2>&1; then
        run dnf install -y curl ca-certificates jq tar coreutils python3 iproute procps-ng util-linux
      else
        run yum install -y curl ca-certificates jq tar coreutils python3 iproute procps-ng util-linux
      fi
      ;;
    alpine)
      command -v curl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1 \
        && command -v tar >/dev/null 2>&1 && command -v sha256sum >/dev/null 2>&1 \
        && command -v python3 >/dev/null 2>&1 && command -v tc >/dev/null 2>&1 \
        && command -v sysctl >/dev/null 2>&1 && command -v unshare >/dev/null 2>&1 \
        && command -v setpriv >/dev/null 2>&1 && command -v flock >/dev/null 2>&1 \
        && return 0
      install_alpine_deps
      ;;
  esac
}

# ---------- NoBrand isolated Xray-core runtime / Hysteria2 service ----------

nobrand_prepare_common() {
  local pm
  require_root
  require_linux
  pm="$(detect_pkg_manager)"
  STAGE="安装 NoBrand 公共依赖"
  case "$pm" in
    deb)
      if ! command -v curl >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1 \
         || ! command -v unzip >/dev/null 2>&1 || ! command -v openssl >/dev/null 2>&1 \
         || ! command -v python3 >/dev/null 2>&1; then
        run apt-get update
        run apt-get install -y curl ca-certificates jq unzip openssl python3 iproute2 util-linux tar
      fi
      ;;
    rpm)
      if command -v dnf >/dev/null 2>&1; then
        run dnf install -y curl ca-certificates jq unzip openssl python3 iproute util-linux tar
      else
        run yum install -y curl ca-certificates jq unzip openssl python3 iproute util-linux tar
      fi
      ;;
    alpine)
      run apk add --no-cache bash curl ca-certificates jq unzip openssl python3 iproute2 util-linux tar libstdc++
      ;;
  esac
  nb_init_state_layout
}

nobrand_xray_arch_asset() {
  case "${NOBRAND_TEST_ARCH:-$(uname -m)}" in
    x86_64|amd64) printf 'Xray-linux-64.zip' ;;
    aarch64|arm64) printf 'Xray-linux-arm64-v8a.zip' ;;
    *) return 1 ;;
  esac
}

nobrand_xray_tested_digest() {
  case "$1" in
    Xray-linux-64.zip) printf '%s' "$TESTED_XRAY_AMD64_SHA256" ;;
    Xray-linux-arm64-v8a.zip) printf '%s' "$TESTED_XRAY_ARM64_SHA256" ;;
    *) return 1 ;;
  esac
}

nobrand_xray_version() {
  local output version
  [ -x "$NOBRAND_XRAY_BIN" ] || return 1
  output="$("$NOBRAND_XRAY_BIN" version 2>/dev/null)" || return 1
  version="$(printf '%s\n' "$output" \
    | sed -nE 's/^Xray[[:space:]]+([^[:space:]]+).*/\1/p' | head -n1)"
  [ -n "$version" ] || return 1
  printf '%s' "$version"
}

nobrand_xray_release_info() {
  local asset metadata version url digest expected
  asset="$(nobrand_xray_arch_asset)" || {
    warn "$(t 'NoBrand Sudoku 的 Xray runtime 仅测试 amd64/arm64' \
      'NoBrand Sudoku Xray runtime is tested only on amd64/arm64')"
    return 1
  }
  metadata="$(mktemp_file .json)" || return 1
  if ! curl -fsSL --connect-timeout 15 --max-time 90 \
      --retry 3 --retry-delay 2 --retry-all-errors \
      -H 'Accept: application/vnd.github+json' \
      -H 'User-Agent: NoBrand-OneClick' "$NOBRAND_XRAY_RELEASE_API" -o "$metadata"; then
    rm -f "$metadata"
    return 1
  fi
  IFS=$'\t' read -r version url digest < <(jq -r --arg asset "$asset" '
    .tag_name as $version |
    first(.assets[]? | select(.name == $asset)) as $matched |
    select($matched != null) |
    [$version, $matched.browser_download_url, ($matched.digest // "")] | @tsv
  ' "$metadata")
  local rc=$?
  rm -f "$metadata"
  [ "$rc" -eq 0 ] && [ "$version" = "v${TESTED_XRAY_VERSION}" ] || return 1
  expected="$(nobrand_xray_tested_digest "$asset")" || return 1
  [ "$digest" = "sha256:${expected}" ] || return 1
  printf '%s\t%s\t%s\n' "$version" "$url" "$digest"
}

nobrand_sha256_file() {
  local file="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" | awk '{print tolower($1)}'
  else
    openssl dgst -sha256 "$file" 2>/dev/null | awk '{print tolower($NF)}'
  fi
}

nobrand_verify_release_digest() {
  local file="$1" digest="${2:-}" expected actual
  [ -n "$digest" ] || {
    info "$(t '上游 release API 未提供资产 hash；已继续执行 archive/ELF/runtime 校验' \
      'Upstream release API has no asset hash; archive/ELF/runtime validation will still run')"
    return 0
  }
  case "$digest" in
    sha256:*) expected="${digest#sha256:}" ;;
    *) warn "不支持的上游 digest: $digest"; return 1 ;;
  esac
  [[ "$expected" =~ ^[0-9A-Fa-f]{64}$ ]] || return 1
  actual="$(nobrand_sha256_file "$file")" || return 1
  [ "$(printf '%s' "$actual" | tr '[:upper:]' '[:lower:]')" = \
    "$(printf '%s' "$expected" | tr '[:upper:]' '[:lower:]')" ]
}

nobrand_download_xray_candidate() {
  local output="$1" asset_output_dir="${2:-}" info_line version url digest archive_dir candidate asset
  info_line="$(nobrand_xray_release_info)" || return 1
  IFS=$'\t' read -r version url digest <<<"$info_line"
  [[ "$url" = https://github.com/XTLS/Xray-core/releases/download/* ]] || {
    warn "拒绝非 XTLS 官方 HTTPS 资产: $url"
    return 1
  }
  archive_dir="$(mktemp_dir)" || return 1
  if ! curl -fL --connect-timeout 15 --max-time 180 \
      --retry 3 --retry-delay 2 --retry-all-errors \
      -H 'User-Agent: NoBrand-OneClick' "$url" -o "$archive_dir/xray.zip" \
     || ! nobrand_verify_release_digest "$archive_dir/xray.zip" "$digest" \
     || ! unzip -t "$archive_dir/xray.zip" >/dev/null \
     || ! unzip -qo "$archive_dir/xray.zip" -d "$archive_dir/unpacked"; then
    rm -rf -- "$archive_dir"
    return 1
  fi
  candidate="$archive_dir/unpacked/xray"
  [ -f "$candidate" ] || candidate="$(find "$archive_dir/unpacked" -type f -name xray | head -n1)"
  [ -n "$candidate" ] && [ -f "$candidate" ] || { rm -rf -- "$archive_dir"; return 1; }
  chmod 0755 "$candidate" || { rm -rf -- "$archive_dir"; return 1; }
  "$candidate" version >/dev/null 2>&1 || { rm -rf -- "$archive_dir"; return 1; }
  install -m 0755 "$candidate" "$output" || { rm -rf -- "$archive_dir"; return 1; }
  if [ -n "$asset_output_dir" ]; then
    mkdir -p "$asset_output_dir" || { rm -rf -- "$archive_dir"; return 1; }
    for asset in geoip.dat geosite.dat; do
      [ -s "$archive_dir/unpacked/$asset" ] \
        || { rm -rf -- "$archive_dir"; return 1; }
      install -m 0644 "$archive_dir/unpacked/$asset" "$asset_output_dir/$asset" \
        || { rm -rf -- "$archive_dir"; return 1; }
    done
  fi
  info "$(t "NoBrand 独立 Xray-core 资产已解析: ${version}" \
    "NoBrand isolated Xray-core asset resolved: ${version}")"
  rm -rf -- "$archive_dir"
}

nobrand_xray_asset_dir_safe() {
  [ -n "${NOBRAND_LIB_DIR:-}" ] && [ -n "${NOBRAND_XRAY_ASSET_DIR:-}" ] \
    && [ "$NOBRAND_XRAY_ASSET_DIR" != / ] \
    && [[ "$NOBRAND_XRAY_ASSET_DIR" == "$NOBRAND_LIB_DIR"/* ]]
}

nobrand_xray_assets_ready() {
  nobrand_xray_asset_dir_safe \
    && [ -s "$NOBRAND_XRAY_ASSET_DIR/geoip.dat" ] \
    && [ -s "$NOBRAND_XRAY_ASSET_DIR/geosite.dat" ]
}

nobrand_remove_xray_runtime_files() {
  nobrand_xray_asset_dir_safe || return 1
  rm -f "$NOBRAND_XRAY_BIN" || return 1
  rm -rf -- "$NOBRAND_XRAY_ASSET_DIR"
}

nobrand_install_xray_runtime() {
  local force="${1:-0}" candidate candidate_assets snapshot new_assets
  local had_runtime=0 had_assets=0 replace_runtime=1 rc=0
  nobrand_xray_asset_dir_safe || return 1
  if [ -x "$NOBRAND_XRAY_BIN" ] && nobrand_xray_assets_ready && [ "$force" -ne 1 ]; then
    return 0
  fi
  if [ -x "$NOBRAND_XRAY_BIN" ] && [ "$force" -ne 1 ]; then
    [ "$(nobrand_xray_version 2>/dev/null || true)" = "$TESTED_XRAY_VERSION" ] || return 1
    replace_runtime=0
  fi
  candidate="$(mktemp_file .xray)" || return 1
  candidate_assets="$(mktemp_dir)" || { rm -f "$candidate"; return 1; }
  if ! nobrand_download_xray_candidate "$candidate" "$candidate_assets"; then
    rm -f "$candidate"
    rm -rf -- "$candidate_assets"
    warn "$(t 'NoBrand 独立 Xray-core 下载或校验失败' \
      'NoBrand isolated Xray-core download or validation failed')"
    return 1
  fi
  snapshot="$(mktemp_dir)" || { rm -f "$candidate"; rm -rf -- "$candidate_assets"; return 1; }
  if [ -e "$NOBRAND_XRAY_BIN" ]; then
    cp -a "$NOBRAND_XRAY_BIN" "$snapshot/xray" || rc=1
    had_runtime=1
  fi
  if [ -d "$NOBRAND_XRAY_ASSET_DIR" ] && [ ! -L "$NOBRAND_XRAY_ASSET_DIR" ]; then
    cp -a "$NOBRAND_XRAY_ASSET_DIR" "$snapshot/assets" || rc=1
    had_assets=1
  fi
  new_assets="${NOBRAND_XRAY_ASSET_DIR}.new.$$"
  if [ "$rc" -eq 0 ]; then
    nb_lifecycle_mark_protocol_mutation_started "${NOBRAND_LIFECYCLE_SCOPE:-}" || {
      rm -f "$candidate"
      rm -rf -- "$candidate_assets" "$snapshot"
      return 1
    }
    mkdir -p "$(dirname "$NOBRAND_XRAY_BIN")" "$(dirname "$NOBRAND_XRAY_ASSET_DIR")" \
      && rm -rf -- "$new_assets" \
      && mkdir -p "$new_assets" \
      && install -m 0644 "$candidate_assets/geoip.dat" "$new_assets/geoip.dat" \
      && install -m 0644 "$candidate_assets/geosite.dat" "$new_assets/geosite.dat" || rc=1
  fi
  if [ "$rc" -eq 0 ] && [ "$replace_runtime" -eq 1 ]; then
    install -m 0755 "$candidate" "${NOBRAND_XRAY_BIN}.new" \
      && mv -f "${NOBRAND_XRAY_BIN}.new" "$NOBRAND_XRAY_BIN" \
      && [ "$(nobrand_xray_version 2>/dev/null || true)" = "$TESTED_XRAY_VERSION" ] || rc=1
  fi
  if [ "$rc" -eq 0 ]; then
    rm -rf -- "$NOBRAND_XRAY_ASSET_DIR" \
      && mv "$new_assets" "$NOBRAND_XRAY_ASSET_DIR" \
      && nobrand_xray_assets_ready \
      && nobrand_xray_validate_managed_configs "$NOBRAND_XRAY_BIN" || rc=1
  fi
  rm -f "$candidate" "${NOBRAND_XRAY_BIN}.new"
  rm -rf -- "$candidate_assets" "$new_assets"
  if [ "$rc" -ne 0 ]; then
    rm -f "$NOBRAND_XRAY_BIN"
    [ "$had_runtime" -eq 0 ] || install -m 0755 "$snapshot/xray" "$NOBRAND_XRAY_BIN" 2>/dev/null || true
    rm -rf -- "$NOBRAND_XRAY_ASSET_DIR"
    [ "$had_assets" -eq 0 ] \
      || cp -a "$snapshot/assets" "$NOBRAND_XRAY_ASSET_DIR" 2>/dev/null || true
    rm -rf -- "$snapshot"
    return 1
  fi
  rm -rf -- "$snapshot"
}

nobrand_xray_redact_validation_log() {
  local config="$1" log="$2"
  if ! command -v python3 >/dev/null 2>&1; then
    printf '%s\n' "$(t '[校验详情已隐藏：脱敏器不可用]' \
      '[validation details suppressed: redactor unavailable]')" >&2
    return 0
  fi
  python3 - "$config" "$log" >&2 <<'PY' || {
import json
import re
import sys

config_path, log_path = sys.argv[1:3]
sensitive_keys = {
    "auth", "password", "privatekey", "publickey", "uuid", "shortid", "shortids"
}

try:
    with open(config_path, encoding="utf-8") as handle:
        config = json.load(handle)
    with open(log_path, encoding="utf-8", errors="replace") as handle:
        text = handle.read()
except Exception:
    raise SystemExit(1)

secrets = set()

def collect(value):
    if isinstance(value, dict):
        for key, child in value.items():
            if str(key).casefold() in sensitive_keys:
                values = child if isinstance(child, list) else [child]
                for item in values:
                    if isinstance(item, (str, int, float)) and str(item):
                        secrets.add(str(item))
            collect(child)
    elif isinstance(value, list):
        for child in value:
            collect(child)

collect(config)
for secret in sorted(secrets, key=len, reverse=True):
    text = text.replace(secret, "***REDACTED***")

field = r'(?:auth|password|privateKey|publicKey|uuid|shortId|shortIds)'
text = re.sub(
    rf'(?i)((?:["\']?{field}["\']?)\s*[:=]\s*)(?:"[^"]*"|\'[^\']*\'|[^\s,}}\]]+)',
    lambda match: match.group(1) + '***REDACTED***',
    text,
)
sys.stdout.write(text)
PY
    printf '%s\n' "$(t '[校验详情已隐藏：脱敏失败]' \
      '[validation details suppressed: redaction failed]')" >&2
  }
}

nobrand_xray_test_config() {
  local config="$1" binary="${2:-$NOBRAND_XRAY_BIN}" log
  [ -x "$binary" ] && jq empty "$config" >/dev/null 2>&1 || return 1
  log="$(mktemp_file .log)" || return 1
  if ! XRAY_LOCATION_ASSET="$NOBRAND_XRAY_ASSET_DIR" \
      "$binary" run -test -c "$config" >"$log" 2>&1; then
    warn "$(t 'NoBrand Xray 配置校验失败（已脱敏）:' \
      'NoBrand Xray config validation failed (redacted):')"
    nobrand_xray_redact_validation_log "$config" "$log"
    rm -f "$log"
    return 1
  fi
  rm -f "$log"
}

nobrand_xray_validate_managed_configs() {
  [ ! -f "$NOBRAND_VLESS_CONFIG_FILE" ] || nobrand_xray_test_config "$NOBRAND_VLESS_CONFIG_FILE" "${1:-$NOBRAND_XRAY_BIN}"
}

nobrand_restore_xray_upgrade_snapshot() {
  local snapshot="$1" had_runtime="$2" had_assets="$3" was_active="$4"
  if [ "$had_runtime" = 1 ]; then install -m 0755 "$snapshot/xray" "$NOBRAND_XRAY_BIN" || return 1
  else rm -f "$NOBRAND_XRAY_BIN"; fi
  nobrand_xray_asset_dir_safe || return 1
  rm -rf -- "$NOBRAND_XRAY_ASSET_DIR"
  [ "$had_assets" = 0 ] || cp -a "$snapshot/xray-assets" "$NOBRAND_XRAY_ASSET_DIR" || return 1
  [ ! -f "$snapshot/state" ] || cp -a "$snapshot/state" "$NOBRAND_VLESS_STATE_FILE" || return 1
  [ "$was_active" = 0 ] || nobrand_vless_sudoku_service_action restart
}

nobrand_upgrade_xray_runtime() {
  local snapshot had_runtime=0 had_assets=0 was_active=0 failed=0
  vless_sudoku_state_exists || return 1
  nobrand_prepare_common || return 1
  admin_lock_acquire || return 1
  snapshot="$(mktemp_dir)" || { admin_lock_release; return 1; }
  if [ -f "$NOBRAND_XRAY_BIN" ]; then cp -a "$NOBRAND_XRAY_BIN" "$snapshot/xray" || failed=1; had_runtime=1; fi
  if [ -d "$NOBRAND_XRAY_ASSET_DIR" ]; then cp -a "$NOBRAND_XRAY_ASSET_DIR" "$snapshot/xray-assets" || failed=1; had_assets=1; fi
  cp -a "$NOBRAND_VLESS_STATE_FILE" "$snapshot/state" || failed=1
  nobrand_vless_sudoku_service_active && was_active=1
  if [ "$failed" = 0 ]; then
    nobrand_install_xray_runtime 1 && nobrand_xray_validate_managed_configs || failed=1
    if [ "$failed" = 0 ] && [ "$was_active" = 1 ]; then
      nobrand_vless_sudoku_service_action restart && vless_sudoku_running || failed=1
    fi
    [ "$failed" != 0 ] || vless_sudoku_refresh_runtime_metadata || failed=1
  fi
  if [ "$failed" != 0 ]; then
    nobrand_restore_xray_upgrade_snapshot "$snapshot" "$had_runtime" "$had_assets" "$was_active" || warn 'Sudoku runtime rollback failed'
  fi
  rm -rf -- "$snapshot"
  admin_lock_release
  return "$failed"
}

# Ordinary protocol runtime and exports are managed by the native Splicore adapter.

# ---------- NoBrand VLESS Sudoku isolated Xray service ----------

nobrand_write_vless_sudoku_service() {
  local manager tmp
  manager="$(nb_service_manager)"
  case "$manager" in
    systemd)
      tmp="$(mktemp_file .service)" || return 1
      cat >"$tmp" <<EOF
# Managed by NoBrand-OneClick
[Unit]
Description=NoBrand Plain VLESS FinalMask Sudoku (Xray-core)
Documentation=https://github.com/ike-sh/NoBrand-OneClick
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=${NOBRAND_VLESS_CONFIG_DIR}
ExecStart=${NOBRAND_XRAY_BIN} run -c ${NOBRAND_VLESS_CONFIG_FILE}
Restart=on-failure
RestartSec=5
LimitNOFILE=1048576
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_BIND_SERVICE
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full
ProtectHome=true
ReadWritePaths=${NOBRAND_VLESS_CONFIG_DIR} ${NOBRAND_VLESS_STATE_DIR}

[Install]
WantedBy=multi-user.target
EOF
      grep -qF "ExecStart=${NOBRAND_XRAY_BIN} run -c ${NOBRAND_VLESS_CONFIG_FILE}" "$tmp" \
        || { rm -f "$tmp"; return 1; }
      install -m 0644 "$tmp" "${NOBRAND_VLESS_SYSTEMD_SERVICE}.new" \
        && mv -f "${NOBRAND_VLESS_SYSTEMD_SERVICE}.new" "$NOBRAND_VLESS_SYSTEMD_SERVICE" \
        || { rm -f "$tmp" "${NOBRAND_VLESS_SYSTEMD_SERVICE}.new"; return 1; }
      rm -f "$tmp"
      systemctl daemon-reload || return 1
      systemctl enable "$NOBRAND_VLESS_SERVICE_NAME" >/dev/null 2>&1
      ;;
    openrc)
      tmp="$(mktemp_file .openrc)" || return 1
      cat >"$tmp" <<EOF
#!/sbin/openrc-run
# Managed by NoBrand-OneClick
name="NoBrand Plain VLESS FinalMask Sudoku"
description="NoBrand Plain VLESS FinalMask Sudoku (Xray-core)"
command="${NOBRAND_XRAY_BIN}"
command_args="run -c ${NOBRAND_VLESS_CONFIG_FILE}"
command_background=true
pidfile="/run/nobrand-vless-sudoku.pid"
output_log="/var/log/nobrand-vless-sudoku.log"
error_log="/var/log/nobrand-vless-sudoku.err"
depend() { use net; after firewall; }
EOF
      install -m 0755 "$tmp" "${NOBRAND_VLESS_OPENRC_SERVICE}.new" \
        && mv -f "${NOBRAND_VLESS_OPENRC_SERVICE}.new" "$NOBRAND_VLESS_OPENRC_SERVICE" \
        || { rm -f "$tmp" "${NOBRAND_VLESS_OPENRC_SERVICE}.new"; return 1; }
      rm -f "$tmp"
      rc-update add "$NOBRAND_VLESS_SERVICE_NAME" default >/dev/null 2>&1
      ;;
    *) return 1 ;;
  esac
}

nobrand_vless_sudoku_service_action() {
  local action="$1" manager
  manager="$(nb_service_manager)"
  case "$manager" in
    systemd)
      [ "$action" != restart ] || systemctl daemon-reload
      systemctl "$action" "$NOBRAND_VLESS_SERVICE_NAME"
      ;;
    openrc) rc-service "$NOBRAND_VLESS_SERVICE_NAME" "$action" ;;
    *) return 1 ;;
  esac
}

nobrand_vless_sudoku_service_active() {
  nb_service_is_active "$NOBRAND_VLESS_SERVICE_NAME" "$NOBRAND_VLESS_SERVICE_NAME"
}

nobrand_remove_vless_sudoku_service() {
  local manager
  manager="$(nb_service_manager)"
  nobrand_vless_sudoku_service_action stop >/dev/null 2>&1 || true
  case "$manager" in
    systemd)
      systemctl disable "$NOBRAND_VLESS_SERVICE_NAME" >/dev/null 2>&1 || true
      rm -f "$NOBRAND_VLESS_SYSTEMD_SERVICE"
      systemctl daemon-reload 2>/dev/null || true
      ;;
    openrc)
      rc-update del "$NOBRAND_VLESS_SERVICE_NAME" default >/dev/null 2>&1 || true
      rm -f "$NOBRAND_VLESS_OPENRC_SERVICE"
      ;;
  esac
}

# Ordinary protocol runtime and exports are managed by the native Splicore adapter.

# Ordinary protocol runtime and exports are managed by the native Splicore adapter.

normalize_uint() {
  local value="${1:-}"
  [[ "$value" =~ ^[0-9]+$ ]] || return 1
  while [ "${#value}" -gt 1 ] && [ "${value#0}" != "$value" ]; do
    value="${value#0}"
  done
  printf '%s' "$value"
}

# 取本机主用 IPv4：优先默认路由出口地址（ip route get 不发包，仅查路由表，
# 内网无外网也可用），回退首个非回环地址。
valid_port() {
  local p
  p="$(normalize_uint "${1:-}")" || return 1
  [ "${#p}" -le 5 ] && [ "$p" -ge 1025 ] && [ "$p" -le 65535 ]
}

valid_advertise_port() {
  local p
  p="$(normalize_uint "${1:-}")" || return 1
  [ "${#p}" -le 5 ] && [ "$p" -ge 1 ] && [ "$p" -le 65535 ]
}

valid_mtu() {
  local value
  value="$(normalize_uint "${1:-}")" || return 1
  [ "${#value}" -le 4 ] && [ "$value" -ge 1280 ] && [ "$value" -le 1500 ]
}

mtu_default_iface() {
  local dev=""
  if command -v ip >/dev/null 2>&1; then
    dev="$(ip -o route show default 2>/dev/null \
      | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')"
    [ -n "$dev" ] || dev="$(ip -o -6 route show default 2>/dev/null \
      | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')"
    [ -n "$dev" ] || dev="$(ip -br link 2>/dev/null \
      | awk '$1!="lo"{print $1; exit}' | cut -d@ -f1)"
  fi
  if [ -z "$dev" ] && [ -r /proc/net/route ]; then
    dev="$(awk '$2=="00000000"{print $1; exit}' /proc/net/route 2>/dev/null)"
  fi
  printf '%s' "$dev"
}

# Ordinary protocol state and users are managed by runtime/splicore.py.

# Ordinary protocol state and users are managed by runtime/splicore.py.

# ---------- Common egress interface lookup for BBR status ----------

tc_default_iface() {
  local dev=""
  if [ -n "${TC_IFACE:-}" ]; then
    printf '%s' "$TC_IFACE"
    return 0
  fi
  if command -v ip >/dev/null 2>&1; then
    dev="$(ip route 2>/dev/null | awk '/^default/{print $5; exit}')"
    [ -n "$dev" ] || dev="$(ip -br link 2>/dev/null | awk '$1!="lo"{print $1; exit}' | cut -d@ -f1)"
  fi
  printf '%s' "$dev"
}

# ---------- 阶段4：备份 / 恢复 / 导出导入 / 管理锁 ----------

open_firewall_for_pairs() {
  local pairs="$1"
  local fw="" pp proto p proto_lc failed=0
  [ -n "$pairs" ] || return 0
  if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q 'Status: active'; then
    fw=ufw
  elif command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
    fw=firewalld
  elif command -v iptables >/dev/null 2>&1; then
    fw=iptables
  else
    return 0
  fi
  while IFS= read -r pp; do
    [ -n "$pp" ] || continue
    proto="${pp%%|*}"
    p="${pp#*|}"
    proto_lc="$(proto_lower "$proto")"
    firewall_apply_binding "$fw" add "$proto_lc" "$p" || failed=1
  done <<< "$pairs"
  case "$fw" in
    firewalld) run firewall-cmd --reload || failed=1 ;;
    iptables) persist_iptables_rules || failed=1 ;;
  esac
  [ "$failed" -eq 0 ]
}

do_perf() {
  t '========== 网络诊断（只读） ==========' '========== Network diagnostics (read only) =========='
  nb_splicore_call status || return 1
  report_bbr_fq_status
  ip -brief address show 2>/dev/null || true
  ip route show default 2>/dev/null || true
}

# Native architecture: ordinary protocols use src/19-splicore.sh.

do_user_manage() {
  local choice="" operation="" selector=""
  while true; do
    msg '【Mieru 节点】一个运行时管理多个节点 / Mieru nodes'
    msg '  1) 列出节点'
    msg '  2) 添加节点'
    msg '  3) 删除节点'
    msg '  4) 导出客户端配置'
    msg '  5) 启用节点'
    msg '  6) 停用节点'
    msg '  7) 设置展示端点'
    msg '  0) 返回'
    read_tty choice '请选择 [0-7]: ' || return 0
    selector=""
    case "$choice" in
      0) return 0 ;;
      1) operation=status ;;
      2)
        operation=install
        PORT="" PORT_CLI=0 USERNAME="" PASSWORD=""
        ADVERTISE_HOST="" ADVERTISE_PORT="" ADVERTISE_CLI=0 ADVERTISE_AUTO_REQUESTED=0
        read_tty USERNAME '新节点名: ' || continue
        read_tty PASSWORD '密码（回车随机）: ' || continue
        selector="$USERNAME"
        ;;
      3|4|5|6|7)
        nb_splicore_menu_select mieru || continue
        selector="$NOBRAND_MENU_SELECTION_ID"
        case "$choice" in 3) operation=remove ;; 4) operation=show ;; 5) operation=start ;; 6) operation=stop ;; 7) operation=set-endpoint; ADVERTISE_CLI=0 ;; esac
        ;;
      *) continue ;;
    esac
    YES=0
    nobrand_menu_run nb_splicore_protocol mieru "$operation" "$selector"
  done
}

normalize_profile() {
  case "$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]' | tr '_ ' '--')" in
    iplc|iplc-performance|performance) printf 'iplc' ;;
    balanced|balance|default) printf 'balanced' ;;
    stealth|obfuscation) printf 'stealth' ;;
    custom|advanced) printf 'custom' ;;
    *) return 1 ;;
  esac
}

# Optional argument is part of the public helper API.
# shellcheck disable=SC2120


apply_profile_values() {
  local selected
  selected="$(normalize_profile "${1:-}")" || return 1
  PROFILE="$selected"
  case "$selected" in
    iplc)
      PROTOCOL=TCP
      MTU=1400
      MULTIPLEXING=MULTIPLEXING_OFF
      HANDSHAKE_MODE=HANDSHAKE_NO_WAIT
      TRAFFIC_PATTERN=off
      LOW_ENTROPY_MODE=LOW_ENTROPY_MODE_OFF
      ;;
    balanced)
      PROTOCOL=TCP
      MTU=1400
      MULTIPLEXING=MULTIPLEXING_OFF
      HANDSHAKE_MODE=HANDSHAKE_NO_WAIT
      TRAFFIC_PATTERN=conservative
      LOW_ENTROPY_MODE=LOW_ENTROPY_MODE_OFF
      ;;
    stealth)
      PROTOCOL=TCP
      MTU=1400
      MULTIPLEXING=MULTIPLEXING_OFF
      HANDSHAKE_MODE=HANDSHAKE_NO_WAIT
      TRAFFIC_PATTERN=aggressive
      # Low Entropy 始终是单独确认的高开销高级选项，预设不得自动开启。
      LOW_ENTROPY_MODE=LOW_ENTROPY_MODE_OFF
      ;;
    custom) ;;
  esac
}

apply_requested_profile_preserving_cli() {
  [ "${PROFILE_CLI:-0}" -eq 1 ] || return 0
  local cli_protocol="$PROTOCOL" cli_mtu_request="$MTU_REQUEST"
  local cli_mux="$MULTIPLEXING" cli_handshake="$HANDSHAKE_MODE"
  local cli_traffic="$TRAFFIC_PATTERN" cli_low="$LOW_ENTROPY_MODE"
  apply_profile_values "$PROFILE" || die "$(t '非法配置预设（仅支持 iplc/balanced/stealth/custom）' \
    'Invalid profile (iplc/balanced/stealth/custom)')"
  [ "${PROTOCOL_CLI:-0}" -eq 0 ] || PROTOCOL="$cli_protocol"
  [ "${MTU_CLI:-0}" -eq 0 ] || MTU_REQUEST="$cli_mtu_request"
  [ "${MULTIPLEXING_CLI:-0}" -eq 0 ] || MULTIPLEXING="$cli_mux"
  [ "${HANDSHAKE_CLI:-0}" -eq 0 ] || HANDSHAKE_MODE="$cli_handshake"
  [ "${TRAFFIC_CLI:-0}" -eq 0 ] || TRAFFIC_PATTERN="$cli_traffic"
  [ "${LOW_ENTROPY_CLI:-0}" -eq 0 ] || LOW_ENTROPY_MODE="$cli_low"
}

choose_profile_interactive() {
  t '使用原生 TCP 默认参数；traffic-pattern 与低熵模式当前不支持。' 'Using native TCP defaults; traffic-pattern and low entropy are unsupported.'
  apply_profile_values iplc
}

# Native architecture: ordinary protocols use src/19-splicore.sh.

nobrand_run_snell_action() {
  case "${SNELL_ACTION:-menu}" in
    menu) snell_menu_loop ;;
    help) nobrand_usage ;;
    *) nb_splicore_protocol snell "${SNELL_ACTION:-status}" "${SNELL_NAME:-}" ;;
  esac
}

# Native architecture: ordinary protocols use src/19-splicore.sh.

nobrand_run_hy2_action() {
  case "${HY2_ACTION:-menu}" in
    menu) hysteria2_menu_loop ;;
    help) nobrand_usage ;;
    *) nb_splicore_protocol hysteria2 "${HY2_ACTION:-status}" "hy2" ;;
  esac
}

# ---------- Plain VLESS + FinalMask Sudoku over TCP ----------

vless_sudoku_state_exists() {
  [ -s "$NOBRAND_VLESS_STATE_FILE" ] && jq empty "$NOBRAND_VLESS_STATE_FILE" >/dev/null 2>&1
}

vless_sudoku_state_field() {
  local field="$1"
  vless_sudoku_state_exists || return 1
  jq -r --arg field "$field" \
    'if has($field) and .[$field] != null then .[$field] else empty end' "$NOBRAND_VLESS_STATE_FILE"
}

vless_sudoku_finalmask_json() {
  local password="$1"
  [[ "$password" =~ ^[0-9A-Fa-f]{32}$ ]] || return 1
  jq -cn --arg password "$password" '{
    tcp: [{
      type: "sudoku",
      settings: {
        password: $password,
        ascii: "prefer_ascii",
        paddingMin: 0,
        paddingMax: 3
      }
    }]
  }'
}

vless_sudoku_valid_uuid() {
  [[ "${1:-}" =~ ^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$ ]]
}

vless_sudoku_generate_uuid() {
  local value=""
  if [ -x "$NOBRAND_XRAY_BIN" ]; then
    value="$("$NOBRAND_XRAY_BIN" uuid 2>/dev/null | tr -d '\r\n' || true)"
  fi
  if ! vless_sudoku_valid_uuid "$value" && command -v uuidgen >/dev/null 2>&1; then
    value="$(uuidgen 2>/dev/null | tr '[:upper:]' '[:lower:]' | tr -d '\r\n' || true)"
  fi
  if ! vless_sudoku_valid_uuid "$value" && [ -r /proc/sys/kernel/random/uuid ]; then
    value="$(tr -d '\r\n' </proc/sys/kernel/random/uuid)"
  fi
  if ! vless_sudoku_valid_uuid "$value" && command -v openssl >/dev/null 2>&1; then
    value="$(openssl rand -hex 16 2>/dev/null \
      | sed -E 's/(.{8})(.{4})(.{4})(.{4})(.{12})/\1-\2-\3-\4-\5/')"
  fi
  vless_sudoku_valid_uuid "$value" || return 1
  printf '%s' "$value"
}

vless_sudoku_generate_server_config() {
  local output="$1" listen="$2" port="$3" uuid="$4" password="$5" finalmask
  finalmask="$(vless_sudoku_finalmask_json "$password")" || return 1
  jq -n --arg tag "$NOBRAND_VLESS_TAG" --arg listen "$listen" --arg port "$port" \
    --arg uuid "$uuid" --argjson finalmask "$finalmask" '
    {
      "log": {"loglevel":"warning"},
      "inbounds": [{
        "tag": $tag,
        "listen": $listen,
        "port": ($port|tonumber),
        "protocol": "vless",
        "settings": {
          "clients": [{"id":$uuid,"email":"vless-sudoku@nobrand"}],
          "decryption": "none"
        },
        "streamSettings": {
          "network": "tcp",
          "security": "none",
          "finalmask": $finalmask
        },
        "sniffing": {
          "enabled": true,
          "destOverride": ["http","tls"]
        }
      }],
      "outbounds": [{"tag":"direct","protocol":"freedom"}],
      "routing": {"rules":[]}
    }
  ' >"$output"
}

vless_sudoku_build_share_link() {
  local uuid="$1" host="$2" port="$3" finalmask_json="$4"
  local host_uri fm_uri name_uri
  vless_sudoku_valid_uuid "$uuid" && [ -n "$host" ] && nb_valid_port "$port" || return 1
  jq -e '.tcp[0].type == "sudoku"' <<<"$finalmask_json" >/dev/null 2>&1 || return 1
  host_uri="$(url_host "$host")"
  fm_uri="$(urlencode "$finalmask_json")" || return 1
  name_uri="$(urlencode 'NoBrand-VLESS-Sudoku')" || return 1
  printf 'vless://%s@%s:%s?type=tcp&security=none&encryption=none&fm=%s#%s' \
    "$uuid" "$host_uri" "$port" "$fm_uri" "$name_uri"
}

vless_sudoku_generate_client_config() {
  local output="$1" host="$2" port="$3" uuid="$4" password="$5"
  local socks_port="${6:-$VLESS_SUDOKU_CLIENT_SOCKS_PORT}" finalmask
  finalmask="$(vless_sudoku_finalmask_json "$password")" || return 1
  { valid_advertise_host "$host" || [ "$host" = YOUR_SERVER_IP ]; } \
    && nb_valid_port "$port" && nb_valid_port "$socks_port" \
    && vless_sudoku_valid_uuid "$uuid" || return 1
  jq -n --arg host "$host" --arg port "$port" --arg uuid "$uuid" \
    --arg socks_port "$socks_port" --argjson finalmask "$finalmask" '
    {
      "log": {"loglevel":"warning"},
      "inbounds": [{
        "tag":"local-socks",
        "listen":"127.0.0.1",
        "port":($socks_port|tonumber),
        "protocol":"socks",
        "settings":{"udp":true}
      }],
      "outbounds": [{
        "tag":"vless-sudoku-out",
        "protocol":"vless",
        "settings": {
          "vnext": [{
            "address":$host,
            "port":($port|tonumber),
            "users":[{"id":$uuid,"encryption":"none"}]
          }]
        },
        "streamSettings": {
          "network":"tcp",
          "security":"none",
          "finalmask":$finalmask
        }
      }]
    }
  ' >"$output"
}

vless_sudoku_forbidden_absent() {
  local file
  for file in "$@"; do
    [ -f "$file" ] || return 1
    if grep -Eqi 'vlessenc|mlkem|xorpub|server_ticket|enc_method|client_rtt|vless_encryption|vless_decryption' "$file"; then
      return 1
    fi
    jq -e '
      ([.. | objects | to_entries[] |
        select((.key | ascii_downcase) |
          test("^(vlessenc|mlkem|xorpub|server_ticket|enc_method|client_rtt|vless_encryption|vless_decryption|decryption_secret|encryption_secret)$"))]
       | length) == 0 and
      ([.. | objects | to_entries[] |
        select(((.key | ascii_downcase) == "encryption" or
                (.key | ascii_downcase) == "decryption") and
               .value != "none")]
       | length) == 0
    ' "$file" >/dev/null 2>&1 || return 1
  done
}

vless_sudoku_state_matches() {
  local state="${1:-$NOBRAND_VLESS_STATE_FILE}"
  jq -e --arg tag "$NOBRAND_VLESS_TAG" '
    .protocol == "vless-sudoku" and
    (.uuid | type == "string" and test("^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$")) and
    (.listen_host | type == "string" and length > 0) and
    (.listen_port | type == "number" and . >= 1 and . <= 65535 and floor == .) and
    .transport == "tcp" and
    ((.advertise_mode == "auto" and .advertise_host == "" and .advertise_port == "") or
     (.advertise_mode == "custom" and (.advertise_host | type == "string" and length > 0) and
      (.advertise_port | type == "number" and . >= 1 and . <= 65535 and floor == .))) and
    .finalmask_mode == "sudoku" and
    (.finalmask_json.tcp | length) == 1 and
    .finalmask_json.tcp[0].type == "sudoku" and
    (.finalmask_json.tcp[0].settings.password | type == "string" and test("^[0-9A-Fa-f]{32}$")) and
    .finalmask_json.tcp[0].settings.ascii == "prefer_ascii" and
    .finalmask_json.tcp[0].settings.paddingMin == 0 and
    .finalmask_json.tcp[0].settings.paddingMax == 3 and
    .tag == $tag and
    (.runtime_version | type == "string" and length > 0) and
    (.link | type == "string" and startswith("vless://") and contains("type=tcp") and
      contains("security=none") and contains("encryption=none") and contains("fm=")) and
    .client_config == "client.json" and
    (.enabled | type) == "boolean" and
    (.created_at | type == "string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")) and
    (.updated_at | type == "string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$"))
  ' "$state" >/dev/null 2>&1 && vless_sudoku_forbidden_absent "$state"
}

vless_sudoku_server_config_matches() {
  local config="${1:-$NOBRAND_VLESS_CONFIG_FILE}" uuid="${2:-}" port="${3:-}" password="${4:-}"
  local listen="${5:-}"
  [ -n "$uuid" ] || uuid="$(vless_sudoku_state_field uuid)" || return 1
  [ -n "$port" ] || port="$(vless_sudoku_state_field listen_port)" || return 1
  [ -n "$password" ] || password="$(jq -r '.finalmask_json.tcp[0].settings.password // empty' "$NOBRAND_VLESS_STATE_FILE")"
  [ -n "$listen" ] || listen="$(vless_sudoku_state_field listen_host)" || return 1
  jq -e --arg tag "$NOBRAND_VLESS_TAG" --arg uuid "$uuid" --arg port "$port" \
    --arg password "$password" --arg listen "$listen" '
    (.inbounds | length) == 1 and
    .inbounds[0].tag == $tag and
    .inbounds[0].listen == $listen and
    .inbounds[0].protocol == "vless" and
    .inbounds[0].port == ($port|tonumber) and
    .inbounds[0].settings.clients == [{"id":$uuid,"email":"vless-sudoku@nobrand"}] and
    .inbounds[0].settings.decryption == "none" and
    .inbounds[0].streamSettings.network == "tcp" and
    .inbounds[0].streamSettings.security == "none" and
    .inbounds[0].streamSettings.finalmask.tcp == [{
      "type":"sudoku",
      "settings":{
        "password":$password,
        "ascii":"prefer_ascii",
        "paddingMin":0,
        "paddingMax":3
      }
    }]
  ' "$config" >/dev/null 2>&1 && vless_sudoku_forbidden_absent "$config"
}

vless_sudoku_client_config_matches() {
  local config="${1:-$NOBRAND_VLESS_CLIENT_FILE}" host="${2:-}" port="${3:-}"
  local uuid="${4:-}" password="${5:-}" ingress_profile_id
  ingress_profile_id="$(vless_sudoku_state_field ingress_profile_id 2>/dev/null || true)"
  [ -n "$ingress_profile_id" ] || ingress_profile_id="$NOBRAND_LEGACY_INGRESS_PROFILE_ID"
  [ -n "$host" ] || {
    local mode advertise_host
    mode="$(vless_sudoku_state_field advertise_mode)" || return 1
    advertise_host="$(vless_sudoku_state_field advertise_host)"
    host="$(nb_effective_advertise_host "$mode" "$advertise_host" "$ingress_profile_id")"
  }
  [ -n "$port" ] || {
    local mode advertise_port listen_port
    mode="$(vless_sudoku_state_field advertise_mode)" || return 1
    advertise_port="$(vless_sudoku_state_field advertise_port)"
    listen_port="$(vless_sudoku_state_field listen_port)"
    port="$(nb_effective_advertise_port "$mode" "$advertise_port" "$listen_port" "$ingress_profile_id")"
  }
  [ -n "$uuid" ] || uuid="$(vless_sudoku_state_field uuid)" || return 1
  [ -n "$password" ] \
    || password="$(jq -r '.finalmask_json.tcp[0].settings.password // empty' "$NOBRAND_VLESS_STATE_FILE")"
  jq -e --arg host "$host" --arg port "$port" --arg uuid "$uuid" --arg password "$password" '
    .outbounds[0].protocol == "vless" and
    .outbounds[0].settings.vnext[0].address == $host and
    .outbounds[0].settings.vnext[0].port == ($port|tonumber) and
    .outbounds[0].settings.vnext[0].users == [{"id":$uuid,"encryption":"none"}] and
    .outbounds[0].streamSettings.network == "tcp" and
    .outbounds[0].streamSettings.security == "none" and
    .outbounds[0].streamSettings.finalmask.tcp == [{
      "type":"sudoku",
      "settings":{
        "password":$password,
        "ascii":"prefer_ascii",
        "paddingMin":0,
        "paddingMax":3
      }
    }]
  ' "$config" >/dev/null 2>&1 && vless_sudoku_forbidden_absent "$config"
}

vless_sudoku_current_share_link() {
  local uuid listen_port mode advertise_host advertise_port ingress_profile_id host port finalmask
  vless_sudoku_state_exists || return 1
  uuid="$(vless_sudoku_state_field uuid)"
  listen_port="$(vless_sudoku_state_field listen_port)"
  mode="$(vless_sudoku_state_field advertise_mode)"
  advertise_host="$(vless_sudoku_state_field advertise_host)"
  advertise_port="$(vless_sudoku_state_field advertise_port)"
  ingress_profile_id="$(vless_sudoku_state_field ingress_profile_id 2>/dev/null || true)"
  host="$(nb_effective_advertise_host "$mode" "$advertise_host" "$ingress_profile_id")"
  port="$(nb_effective_advertise_port "$mode" "$advertise_port" "$listen_port" "$ingress_profile_id")"
  finalmask="$(jq -c '.finalmask_json' "$NOBRAND_VLESS_STATE_FILE")" || return 1
  vless_sudoku_build_share_link "$uuid" "$host" "$port" "$finalmask"
}

vless_sudoku_generate_state() {
  local output="$1" listen="$2" port="$3" uuid="$4" password="$5"
  local advertise_mode="$6" advertise_host="$7" advertise_port="$8" created_at="${9:-}"
  local ingress_profile_id="${10:-}"
  local updated_at runtime_version finalmask effective_host effective_port link
  [ -n "$created_at" ] || created_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  updated_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  runtime_version="$(nobrand_xray_version 2>/dev/null || printf unknown)"
  finalmask="$(vless_sudoku_finalmask_json "$password")" || return 1
  effective_host="$(nb_effective_advertise_host "$advertise_mode" "$advertise_host" "$ingress_profile_id")"
  effective_port="$(nb_effective_advertise_port "$advertise_mode" "$advertise_port" "$port" "$ingress_profile_id")"
  link="$(vless_sudoku_build_share_link "$uuid" "$effective_host" "$effective_port" "$finalmask")" || return 1
  jq -n --arg uuid "$uuid" --arg listen "$listen" --arg port "$port" \
    --arg mode "$advertise_mode" --arg advertise_host "$advertise_host" \
    --arg advertise_port "$advertise_port" --arg tag "$NOBRAND_VLESS_TAG" \
    --arg runtime "$runtime_version" --arg link "$link" --arg created "$created_at" \
    --arg updated "$updated_at" --argjson finalmask "$finalmask" --arg ingress_profile_id "$ingress_profile_id" '
    {
      "protocol":"vless-sudoku",
      "uuid":$uuid,
      "listen_host":$listen,
      "listen_port":($port|tonumber),
      "transport":"tcp",
      "advertise_mode":$mode,
      "advertise_host":$advertise_host,
      "advertise_port":(if $advertise_port=="" then "" else ($advertise_port|tonumber) end),
      "finalmask_mode":"sudoku",
      "finalmask_json":$finalmask,
      "tag":$tag,
      "runtime_version":$runtime,
      "link":$link,
      "client_config":"client.json",
      "enabled":true,
      "created_at":$created,
      "updated_at":$updated
    }
    + if $ingress_profile_id=="" then {} else {ingress_profile_id:$ingress_profile_id} end
  ' >"$output"
}

vless_sudoku_snapshot_file() {
  local source="$1" destination="$2"
  if [ -e "$source" ]; then cp -a "$source" "$destination"; else printf absent >"${destination}.absent"; fi
}

vless_sudoku_restore_snapshot_file() {
  local snapshot="$1" destination="$2"
  if [ -f "${snapshot}.absent" ]; then
    rm -f "$destination"
  elif [ -e "$snapshot" ]; then
    mkdir -p "$(dirname "$destination")"
    cp -a "$snapshot" "$destination"
  fi
}

vless_sudoku_configure_requests() {
  local interactive="${1:-0}" old_port="" old_password="" conflict_owner=""
  if vless_sudoku_state_exists && [ "${INGRESS_PROFILE_CLI:-0}" -eq 0 ]; then
    INGRESS_PROFILE_ID="$(vless_sudoku_state_field ingress_profile_id 2>/dev/null || true)"
    [ -n "$INGRESS_PROFILE_ID" ] || INGRESS_PROFILE_ID="$NOBRAND_LEGACY_INGRESS_PROFILE_ID"
  else
    nb_prepare_ingress_request || return 1
  fi
  nb_prepare_ingress_deployment "$INGRESS_PROFILE_ID" native-bind \
    || die 'VLESS Sudoku 无法绑定所选 Ingress 的 Strict 本地地址'
  VLESS_SUDOKU_LISTEN="$INGRESS_LISTEN_HOST"
  if vless_sudoku_state_exists; then
    old_port="$(vless_sudoku_state_field listen_port 2>/dev/null || true)"
    VLESS_SUDOKU_UUID="$(vless_sudoku_state_field uuid 2>/dev/null || true)"
    old_password="$(jq -r '.finalmask_json.tcp[0].settings.password // empty' "$NOBRAND_VLESS_STATE_FILE" 2>/dev/null)"
  fi
  if [ -z "${PORT:-}" ]; then
    PORT="$(nb_select_available_port TCP "$INGRESS_PROFILE_ID")" \
      || die '所选入口配置没有可用 VLESS Sudoku TCP 自动端口；manual-only 必须显式使用 --port'
  else
    nb_valid_port "$PORT" || die 'VLESS Sudoku 端口必须是 1-65535'
    PORT="$(normalize_uint "$PORT")"
    nb_warn_if_outside_recommended_range "$PORT" "$INGRESS_PROFILE_ID"
    if [ "$PORT" != "$old_port" ] \
       && ! nb_port_available_for_profile "$PORT" TCP "$INGRESS_PROFILE_ID" 'vless-sudoku:default'; then
      warn "VLESS Sudoku TCP/${PORT} 已占用"
      nb_describe_port_conflict TCP "$PORT"
      return 1
    fi
  fi
  if [ "$interactive" -eq 1 ] && [ "${ADVERTISE_CLI:-0}" -eq 0 ]; then
    nb_collect_advertise_endpoint_interactive 'VLESS Sudoku' "$PORT"
  else
    nb_require_explicit_endpoint_noninteractive
  fi
  nb_validate_advertise_endpoint "$ADVERTISE_HOST" "$ADVERTISE_PORT" TCP \
    || die 'VLESS Sudoku Display Endpoint 无效'
  if [ -n "$ADVERTISE_HOST" ]; then
    conflict_owner="$(nb_endpoint_conflict_owner TCP "$ADVERTISE_HOST" "$ADVERTISE_PORT" \
      'vless-sudoku:default' 2>/dev/null || true)"
    [ -z "$conflict_owner" ] || die "VLESS Sudoku Display Endpoint 与 ${conflict_owner} 冲突"
  fi
  vless_sudoku_valid_uuid "$VLESS_SUDOKU_UUID" \
    || VLESS_SUDOKU_UUID="$(vless_sudoku_generate_uuid)" \
    || die '无法生成 VLESS UUID'
  if [[ "$old_password" =~ ^[0-9A-Fa-f]{32}$ ]]; then
    VLESS_SUDOKU_PASSWORD="$old_password"
  else
    VLESS_SUDOKU_PASSWORD="$(openssl rand -hex 16 2>/dev/null || true)"
    [[ "$VLESS_SUDOKU_PASSWORD" =~ ^[0-9A-Fa-f]{32}$ ]] \
      || die '无法生成 FinalMask Sudoku 密码'
  fi
}

vless_sudoku_install_rollback() {
  local snapshot="$1" was_active="$2" new_binding_owned="$3"
  nobrand_vless_sudoku_service_action stop >/dev/null 2>&1 || true
  [ "$new_binding_owned" -eq 0 ] \
    || nb_firewall_close_pairs "TCP|${PORT}" >/dev/null 2>&1 || true
  vless_sudoku_restore_snapshot_file "$snapshot/config" "$NOBRAND_VLESS_CONFIG_FILE"
  vless_sudoku_restore_snapshot_file "$snapshot/state" "$NOBRAND_VLESS_STATE_FILE"
  vless_sudoku_restore_snapshot_file "$snapshot/client" "$NOBRAND_VLESS_CLIENT_FILE"
  vless_sudoku_restore_snapshot_file "$snapshot/service-systemd" "$NOBRAND_VLESS_SYSTEMD_SERVICE"
  vless_sudoku_restore_snapshot_file "$snapshot/service-openrc" "$NOBRAND_VLESS_OPENRC_SERVICE"
  vless_sudoku_restore_snapshot_file "$snapshot/xray" "$NOBRAND_XRAY_BIN"
  [ "$(nb_service_manager)" != systemd ] || systemctl daemon-reload >/dev/null 2>&1 || true
  [ "$was_active" -eq 0 ] \
    || nobrand_vless_sudoku_service_action start >/dev/null 2>&1 || true
}

install_vless_sudoku() {
  local interactive=0 snapshot config_tmp state_tmp client_tmp advertise_mode
  local old_port="" old_created="" was_active=0 binding_was_owned=0 binding_now_owned=0
  local rollback_needed=1
  [ "${YES:-0}" -eq 1 ] || interactive=1
  nobrand_prepare_common
  vless_sudoku_configure_requests "$interactive" || return 1
  admin_lock_acquire || return 1
  snapshot="$(mktemp_dir)" || { admin_lock_release; return 1; }
  vless_sudoku_snapshot_file "$NOBRAND_VLESS_CONFIG_FILE" "$snapshot/config"
  vless_sudoku_snapshot_file "$NOBRAND_VLESS_STATE_FILE" "$snapshot/state"
  vless_sudoku_snapshot_file "$NOBRAND_VLESS_CLIENT_FILE" "$snapshot/client"
  vless_sudoku_snapshot_file "$NOBRAND_VLESS_SYSTEMD_SERVICE" "$snapshot/service-systemd"
  vless_sudoku_snapshot_file "$NOBRAND_VLESS_OPENRC_SERVICE" "$snapshot/service-openrc"
  vless_sudoku_snapshot_file "$NOBRAND_XRAY_BIN" "$snapshot/xray"
  nobrand_vless_sudoku_service_active && was_active=1
  if vless_sudoku_state_exists; then
    old_port="$(vless_sudoku_state_field listen_port 2>/dev/null || true)"
    old_created="$(vless_sudoku_state_field created_at 2>/dev/null || true)"
  fi
  if ! nobrand_install_xray_runtime 0; then
    if [ "${NOBRAND_LIFECYCLE_ACTIVE:-0}" -ne 1 ] \
       || [ "$(nb_lifecycle_mutation_started 2>/dev/null || printf 1)" = 1 ]; then
      vless_sudoku_install_rollback "$snapshot" "$was_active" 0
    fi
    rm -rf -- "$snapshot"
    admin_lock_release
    return 1
  fi
  if [ "${NOBRAND_LIFECYCLE_ACTIVE:-0}" -eq 1 ]; then
    rollback_needed="$(nb_lifecycle_mutation_started)" || {
      rm -rf -- "$snapshot"; admin_lock_release; return 1
    }
  fi
  nb_firewall_binding_owned TCP "$PORT" && binding_was_owned=1
  if [ "$was_active" -eq 1 ]; then
    nb_lifecycle_mark_protocol_mutation_started vless-sudoku || {
      rm -rf -- "$snapshot"; admin_lock_release; return 1
    }
    rollback_needed=1
    nobrand_vless_sudoku_service_action stop || {
      vless_sudoku_install_rollback "$snapshot" "$was_active" 0
      rm -rf -- "$snapshot"; admin_lock_release; return 1;
    }
  fi
  if ! nb_port_available_for_profile "$PORT" TCP "$INGRESS_PROFILE_ID" 'vless-sudoku:default'; then
    warn "提交前发现 TCP/${PORT} 已被其它进程占用"
    nb_describe_port_conflict TCP "$PORT"
    [ "$rollback_needed" -eq 0 ] \
      || vless_sudoku_install_rollback "$snapshot" "$was_active" 0
    rm -rf -- "$snapshot"; admin_lock_release; return 1
  fi
  config_tmp="$(mktemp_file .json)" || {
    [ "$rollback_needed" -eq 0 ] \
      || vless_sudoku_install_rollback "$snapshot" "$was_active" 0
    rm -rf -- "$snapshot"; admin_lock_release; return 1;
  }
  state_tmp="$(mktemp_file .json)" || {
    rm -f "$config_tmp"
    [ "$rollback_needed" -eq 0 ] \
      || vless_sudoku_install_rollback "$snapshot" "$was_active" 0
    rm -rf -- "$snapshot"; admin_lock_release; return 1;
  }
  client_tmp="$(mktemp_file .json)" || {
    rm -f "$config_tmp" "$state_tmp"
    [ "$rollback_needed" -eq 0 ] \
      || vless_sudoku_install_rollback "$snapshot" "$was_active" 0
    rm -rf -- "$snapshot"; admin_lock_release; return 1;
  }
  advertise_mode="$(nb_endpoint_mode_from_values "$ADVERTISE_HOST")"
  local effective_host effective_port
  effective_host="$(nb_effective_advertise_host "$advertise_mode" "$ADVERTISE_HOST" "$INGRESS_PROFILE_ID")"
  effective_port="$(nb_effective_advertise_port "$advertise_mode" "$ADVERTISE_PORT" "$PORT" "$INGRESS_PROFILE_ID")"
  if ! vless_sudoku_generate_server_config "$config_tmp" "$VLESS_SUDOKU_LISTEN" "$PORT" \
       "$VLESS_SUDOKU_UUID" "$VLESS_SUDOKU_PASSWORD" \
     || ! nobrand_xray_test_config "$config_tmp" \
     || ! vless_sudoku_server_config_matches "$config_tmp" "$VLESS_SUDOKU_UUID" "$PORT" \
       "$VLESS_SUDOKU_PASSWORD" "$VLESS_SUDOKU_LISTEN" \
     || ! vless_sudoku_generate_state "$state_tmp" "$VLESS_SUDOKU_LISTEN" "$PORT" \
       "$VLESS_SUDOKU_UUID" "$VLESS_SUDOKU_PASSWORD" "$advertise_mode" \
       "$ADVERTISE_HOST" "$ADVERTISE_PORT" "$old_created" "$INGRESS_PROFILE_ID" \
     || ! nb_ingress_stamp_state_file "$state_tmp" "$INGRESS_PROFILE_ID" native-bind \
     || ! vless_sudoku_generate_client_config "$client_tmp" "$effective_host" "$effective_port" \
       "$VLESS_SUDOKU_UUID" "$VLESS_SUDOKU_PASSWORD" \
     || ! vless_sudoku_client_config_matches "$client_tmp" "$effective_host" "$effective_port" \
       "$VLESS_SUDOKU_UUID" "$VLESS_SUDOKU_PASSWORD" \
     || ! vless_sudoku_state_matches "$state_tmp"; then
    rm -f "$config_tmp" "$state_tmp" "$client_tmp"
    [ "$rollback_needed" -eq 0 ] \
      || vless_sudoku_install_rollback "$snapshot" "$was_active" 0
    rm -rf -- "$snapshot"; admin_lock_release; return 1
  fi
  if [ "$was_active" -eq 0 ]; then
    nb_lifecycle_mark_protocol_mutation_started vless-sudoku || {
      rm -f "$config_tmp" "$state_tmp" "$client_tmp"
      [ "$rollback_needed" -eq 0 ] \
        || vless_sudoku_install_rollback "$snapshot" "$was_active" 0
      rm -rf -- "$snapshot"; admin_lock_release; return 1
    }
    rollback_needed=1
  fi
  if ! nb_atomic_install_file "$config_tmp" "$NOBRAND_VLESS_CONFIG_FILE" 0600 \
     || ! nobrand_write_vless_sudoku_service \
     || ! nb_firewall_open_pairs "TCP|${PORT}"; then
    rm -f "$config_tmp" "$state_tmp" "$client_tmp"
    nb_firewall_binding_owned TCP "$PORT" \
      && [ "$binding_was_owned" -eq 0 ] && binding_now_owned=1
    vless_sudoku_install_rollback "$snapshot" "$was_active" "$binding_now_owned"
    rm -rf -- "$snapshot"; admin_lock_release; return 1
  fi
  rm -f "$config_tmp"
  nb_firewall_binding_owned TCP "$PORT" \
    && [ "$binding_was_owned" -eq 0 ] && binding_now_owned=1
  local service_action=start
  [ "$was_active" -eq 0 ] || service_action=restart
  if ! nobrand_vless_sudoku_service_action "$service_action" \
     || ! nobrand_vless_sudoku_service_active \
     || ! nb_wait_for_enforced_listener "$INGRESS_ENFORCEMENT_RESOLVED" "$INGRESS_ENFORCEMENT_METHOD" \
          TCP "$PORT" "$INGRESS_LOCAL_ADDRESS" 'vless-sudoku:default' 25 \
     || ! nb_atomic_install_file "$client_tmp" "$NOBRAND_VLESS_CLIENT_FILE" 0600 \
     || ! nb_atomic_install_file "$state_tmp" "$NOBRAND_VLESS_STATE_FILE" 0600; then
    rm -f "$state_tmp" "$client_tmp"
    vless_sudoku_install_rollback "$snapshot" "$was_active" "$binding_now_owned"
    rm -rf -- "$snapshot"; admin_lock_release
    warn 'VLESS Sudoku 服务、listener 或 state 验收失败，已回滚'
    return 1
  fi
  rm -f "$state_tmp" "$client_tmp"
  if [ -n "$old_port" ] && [ "$old_port" != "$PORT" ]; then
    nb_firewall_close_pairs "TCP|${old_port}" || true
  fi
  nobrand_install_manager_script || true
  rm -rf -- "$snapshot"
  admin_lock_release
  print_vless_sudoku_result install
}

vless_sudoku_set_endpoint() {
  local interactive=0 state_tmp client_tmp snapshot mode owner uuid password host port link finalmask ingress_profile_id
  require_root
  vless_sudoku_state_exists || die 'VLESS Sudoku 未安装'
  [ "${YES:-0}" -eq 1 ] || interactive=1
  PORT="$(vless_sudoku_state_field listen_port)"
  if [ "$interactive" -eq 1 ] && [ "${ADVERTISE_CLI:-0}" -eq 0 ]; then
    nb_collect_advertise_endpoint_interactive 'VLESS Sudoku' "$PORT"
  else
    nb_require_explicit_endpoint_noninteractive
  fi
  nb_validate_advertise_endpoint "$ADVERTISE_HOST" "$ADVERTISE_PORT" TCP \
    || die 'Display Endpoint 无效'
  if [ -n "$ADVERTISE_HOST" ]; then
    owner="$(nb_endpoint_conflict_owner TCP "$ADVERTISE_HOST" "$ADVERTISE_PORT" \
      'vless-sudoku:default' 2>/dev/null || true)"
    [ -z "$owner" ] || die "Display Endpoint 与 ${owner} 冲突"
  fi
  admin_lock_acquire || return 1
  snapshot="$(mktemp_dir)" || { admin_lock_release; return 1; }
  vless_sudoku_snapshot_file "$NOBRAND_VLESS_STATE_FILE" "$snapshot/state"
  vless_sudoku_snapshot_file "$NOBRAND_VLESS_CLIENT_FILE" "$snapshot/client"
  state_tmp="$(mktemp_file .json)" || { rm -rf -- "$snapshot"; admin_lock_release; return 1; }
  client_tmp="$(mktemp_file .json)" || {
    rm -f "$state_tmp"; rm -rf -- "$snapshot"; admin_lock_release; return 1;
  }
  mode="$(nb_endpoint_mode_from_values "$ADVERTISE_HOST")"
  uuid="$(vless_sudoku_state_field uuid)"
  password="$(jq -r '.finalmask_json.tcp[0].settings.password' "$NOBRAND_VLESS_STATE_FILE")"
  ingress_profile_id="$(vless_sudoku_state_field ingress_profile_id 2>/dev/null || true)"
  [ -n "$ingress_profile_id" ] || ingress_profile_id="$NOBRAND_LEGACY_INGRESS_PROFILE_ID"
  finalmask="$(vless_sudoku_finalmask_json "$password")" || {
    rm -f "$state_tmp" "$client_tmp"; rm -rf -- "$snapshot"; admin_lock_release; return 1;
  }
  host="$(nb_effective_advertise_host "$mode" "$ADVERTISE_HOST" "$ingress_profile_id")"
  port="$(nb_effective_advertise_port "$mode" "$ADVERTISE_PORT" "$PORT" "$ingress_profile_id")"
  link="$(vless_sudoku_build_share_link "$uuid" "$host" "$port" "$finalmask")" || {
    rm -f "$state_tmp" "$client_tmp"; rm -rf -- "$snapshot"; admin_lock_release; return 1;
  }
  if ! jq --arg mode "$mode" --arg host "$ADVERTISE_HOST" --arg port "$ADVERTISE_PORT" \
      --arg link "$link" --arg updated "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
        .advertise_mode=$mode |
        .advertise_host=$host |
        .advertise_port=(if $port=="" then "" else ($port|tonumber) end) |
        .link=$link |
        .updated_at=$updated
      ' "$NOBRAND_VLESS_STATE_FILE" >"$state_tmp" \
     || ! vless_sudoku_generate_client_config "$client_tmp" "$host" "$port" "$uuid" "$password" \
     || ! vless_sudoku_client_config_matches "$client_tmp" "$host" "$port" \
     || ! nb_atomic_install_file "$client_tmp" "$NOBRAND_VLESS_CLIENT_FILE" 0600 \
     || ! nb_atomic_install_file "$state_tmp" "$NOBRAND_VLESS_STATE_FILE" 0600; then
    vless_sudoku_restore_snapshot_file "$snapshot/state" "$NOBRAND_VLESS_STATE_FILE"
    vless_sudoku_restore_snapshot_file "$snapshot/client" "$NOBRAND_VLESS_CLIENT_FILE"
    rm -f "$state_tmp" "$client_tmp"; rm -rf -- "$snapshot"; admin_lock_release
    return 1
  fi
  rm -f "$state_tmp" "$client_tmp"; rm -rf -- "$snapshot"
  # 本函数禁止调用 service、firewall 或 server config writer。
  admin_lock_release
  t 'VLESS Sudoku 客户端展示入口已更新；server config/listener/PID/service/firewall 均未改变' \
    'VLESS Sudoku display endpoint updated; server config/listener/PID/service/firewall are unchanged'
  print_vless_sudoku_result show
}

vless_sudoku_running() {
  local port policy method address
  vless_sudoku_state_exists || return 1
  port="$(vless_sudoku_state_field listen_port)"
  policy="$(vless_sudoku_state_field ingress_enforcement 2>/dev/null || printf permissive)"
  method="$(vless_sudoku_state_field ingress_enforcement_method 2>/dev/null || printf wildcard)"
  address="$(vless_sudoku_state_field ingress_local_address 2>/dev/null || true)"
  nobrand_vless_sudoku_service_active \
    && nb_wait_for_enforced_listener "$policy" "$method" TCP "$port" "$address" 'vless-sudoku:default' 1
}

vless_sudoku_apply_ingress_enforcement() {
  local profile_id port uuid password candidate_state candidate_config snapshot was_active=0 rc=0
  vless_sudoku_state_exists || return 1
  profile_id="$(vless_sudoku_state_field ingress_profile_id 2>/dev/null || true)"
  [ -n "$profile_id" ] || profile_id="$NOBRAND_LEGACY_INGRESS_PROFILE_ID"
  nb_prepare_ingress_deployment "$profile_id" native-bind || return 1
  port="$(vless_sudoku_state_field listen_port)"
  uuid="$(vless_sudoku_state_field uuid)"
  password="$(jq -r '.finalmask_json.tcp[0].settings.password // empty' "$NOBRAND_VLESS_STATE_FILE")"
  candidate_state="$(mktemp_file .vless-ingress-state)" || return 1
  candidate_config="$(mktemp_file .vless-ingress-config.json)" || { rm -f "$candidate_state"; return 1; }
  snapshot="$(mktemp_dir)" || { rm -f "$candidate_state" "$candidate_config"; return 1; }
  cp -a "$NOBRAND_VLESS_STATE_FILE" "$snapshot/state" \
    && cp -a "$NOBRAND_VLESS_CONFIG_FILE" "$snapshot/config" || rc=1
  if [ "$rc" -eq 0 ]; then
    jq --arg listen "$INGRESS_LISTEN_HOST" '.listen_host=$listen' "$NOBRAND_VLESS_STATE_FILE" >"$candidate_state" \
      && nb_ingress_stamp_state_file "$candidate_state" "$profile_id" native-bind \
      && vless_sudoku_state_matches "$candidate_state" \
      && vless_sudoku_generate_server_config "$candidate_config" "$INGRESS_LISTEN_HOST" "$port" "$uuid" "$password" \
      && vless_sudoku_server_config_matches "$candidate_config" "$uuid" "$port" "$password" "$INGRESS_LISTEN_HOST" \
      && nobrand_xray_test_config "$candidate_config" || rc=1
  fi
  nobrand_vless_sudoku_service_active && was_active=1
  if [ "$rc" -eq 0 ]; then
    nb_atomic_install_file "$candidate_config" "$NOBRAND_VLESS_CONFIG_FILE" 0600 \
      && nb_atomic_install_file "$candidate_state" "$NOBRAND_VLESS_STATE_FILE" 0600 || rc=1
  fi
  if [ "$rc" -eq 0 ] && [ "$was_active" -eq 1 ]; then
    [ "${NOBRAND_TEST_INGRESS_SERVICE_FAIL:-0}" -eq 0 ] \
      && nobrand_vless_sudoku_service_action restart \
      && [ "${NOBRAND_TEST_INGRESS_LISTENER_FAIL:-0}" -eq 0 ] \
      && vless_sudoku_running || rc=1
  fi
  if [ "$rc" -ne 0 ]; then
    nb_atomic_install_file "$snapshot/config" "$NOBRAND_VLESS_CONFIG_FILE" 0600 >/dev/null 2>&1 || true
    nb_atomic_install_file "$snapshot/state" "$NOBRAND_VLESS_STATE_FILE" 0600 >/dev/null 2>&1 || true
    if [ "$was_active" -eq 1 ]; then
      nobrand_vless_sudoku_service_action restart >/dev/null 2>&1 \
        && vless_sudoku_running >/dev/null 2>&1 || true
    else
      nobrand_vless_sudoku_service_action stop >/dev/null 2>&1 || true
    fi
  fi
  rm -f "$candidate_state" "$candidate_config"
  rm -rf -- "$snapshot"
  return "$rc"
}

vless_sudoku_state_set_enabled() {
  local enabled="$1" tmp
  tmp="$(mktemp_file .json)" || return 1
  if ! jq --argjson enabled "$enabled" --arg updated "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      '.enabled=$enabled | .updated_at=$updated' "$NOBRAND_VLESS_STATE_FILE" >"$tmp" \
     || ! nb_atomic_install_file "$tmp" "$NOBRAND_VLESS_STATE_FILE" 0600; then
    rm -f "$tmp"
    return 1
  fi
  rm -f "$tmp"
}

vless_sudoku_node_rows() {
  local mode advertise_host advertise_port listen_port host port status
  vless_sudoku_state_exists || return 0
  mode="$(vless_sudoku_state_field advertise_mode)"
  advertise_host="$(vless_sudoku_state_field advertise_host)"
  advertise_port="$(vless_sudoku_state_field advertise_port)"
  listen_port="$(vless_sudoku_state_field listen_port)"
  host="$(nb_effective_advertise_host "$mode" "$advertise_host" "$(vless_sudoku_state_field ingress_profile_id 2>/dev/null || true)")"
  port="$(nb_effective_advertise_port "$mode" "$advertise_port" "$listen_port" "$(vless_sudoku_state_field ingress_profile_id 2>/dev/null || true)")"
  status=Stopped; vless_sudoku_running && status=Running
  printf 'VLESS/Sudoku|sudoku|%s:%s/TCP|%s|TCP\n' "$host" "$port" "$status"
}

print_vless_sudoku_result() {
  local context="${1:-show}" uuid listen_host listen_port mode advertise_host advertise_port
  local host port status link finalmask password mode_label
  vless_sudoku_state_exists || { t 'VLESS Sudoku 未安装' 'VLESS Sudoku is not installed'; return 0; }
  uuid="$(vless_sudoku_state_field uuid)"
  listen_host="$(vless_sudoku_state_field listen_host)"
  listen_port="$(vless_sudoku_state_field listen_port)"
  mode="$(vless_sudoku_state_field advertise_mode)"
  advertise_host="$(vless_sudoku_state_field advertise_host)"
  advertise_port="$(vless_sudoku_state_field advertise_port)"
  host="$(nb_effective_advertise_host "$mode" "$advertise_host" "$(vless_sudoku_state_field ingress_profile_id 2>/dev/null || true)")"
  port="$(nb_effective_advertise_port "$mode" "$advertise_port" "$listen_port" "$(vless_sudoku_state_field ingress_profile_id 2>/dev/null || true)")"
  finalmask="$(jq -c '.finalmask_json' "$NOBRAND_VLESS_STATE_FILE")"
  password="$(jq -r '.finalmask_json.tcp[0].settings.password' "$NOBRAND_VLESS_STATE_FILE")"
  link="$(vless_sudoku_current_share_link)"
  status=已停止; vless_sudoku_running && status=运行中
  mode_label="$mode"; case "$mode" in auto) mode_label='自动' ;; custom) mode_label='自定义' ;; esac
  nobrand_print_banner
  msg ''
  [ "$context" != install ] || t '部署完成' 'Deployment complete'
  msg '协议        VLESS + FinalMask + Sudoku'
  msg '传输        TCP'
  msg 'VLESS Encryption：未使用（NOT USED）'
  msg "状态        ${status}"
  msg ''
  msg '实际监听 / Actual Listener'
  msg "  地址      ${listen_host}"
  msg "  端口      ${listen_port}"
  msg ''
  msg '网络入口 / Ingress'
  msg "  入口配置 / Ingress Profile  $(nb_ingress_profile_name "$(vless_sudoku_state_field ingress_profile_id 2>/dev/null || true)")"
  msg ''
  msg '展示端点 / Display Endpoint'
  msg "  主机      ${host}"
  msg "  端口      ${port}"
  msg "  模式      ${mode_label}"
  msg ''
  msg '认证与 FinalMask'
  msg "  UUID      ${uuid}"
  msg "  模式      sudoku"
  msg "  密码      ${password}"
  msg "  JSON      ${finalmask}"
  msg ''
  msg "Xray 客户端 JSON: ${NOBRAND_VLESS_CLIENT_FILE}"
  msg '========================================'
  msg "$link"
}

vless_sudoku_service_command() {
  local action="$1" port was_enabled
  vless_sudoku_state_exists || die 'VLESS Sudoku 未安装'
  port="$(vless_sudoku_state_field listen_port)"
  was_enabled="$(vless_sudoku_state_field enabled)"
  case "$action" in
    start|restart)
      nobrand_xray_test_config "$NOBRAND_VLESS_CONFIG_FILE" || return 1
      nb_firewall_open_pairs "TCP|${port}" || return 1
      if ! nobrand_vless_sudoku_service_action "$action" \
         || ! vless_sudoku_running \
         || ! vless_sudoku_state_set_enabled true; then
        nobrand_vless_sudoku_service_action stop >/dev/null 2>&1 || true
        [ "$was_enabled" = true ] || vless_sudoku_state_set_enabled false >/dev/null 2>&1 || true
        return 1
      fi
      ;;
    stop)
      nobrand_vless_sudoku_service_action stop || return 1
      if ! vless_sudoku_state_set_enabled false; then
        [ "$was_enabled" != true ] \
          || nobrand_vless_sudoku_service_action start >/dev/null 2>&1 || true
        return 1
      fi
      ;;
    status)
      if vless_sudoku_running; then msg 'VLESS Sudoku：运行中'; else msg 'VLESS Sudoku：已停止'; return 1; fi
      ;;
  esac
}

remove_vless_sudoku_config() {
  local port
  require_root
  vless_sudoku_state_exists \
    || { t 'VLESS Sudoku 未安装' 'VLESS Sudoku is not installed'; return 0; }
  port="$(vless_sudoku_state_field listen_port)"
  admin_lock_acquire || return 1
  nobrand_remove_vless_sudoku_service || { admin_lock_release; return 1; }
  nb_firewall_close_pairs "TCP|${port}" || { admin_lock_release; return 1; }
  # Xray is now exclusive to Sudoku. Leaving it without its ownership state
  # would look like an unsupported legacy runtime on the next invocation.
  nobrand_remove_xray_runtime_files || { admin_lock_release; return 1; }
  rm -f "$NOBRAND_VLESS_CONFIG_FILE" "$NOBRAND_VLESS_STATE_FILE" "$NOBRAND_VLESS_CLIENT_FILE"
  rmdir "$NOBRAND_VLESS_CONFIG_DIR" "$NOBRAND_VLESS_STATE_DIR" 2>/dev/null || true
  admin_lock_release
  t '已删除 NoBrand VLESS Sudoku 及其专用 Xray；Splicore 与外部资源保留' \
    'Removed NoBrand VLESS Sudoku and its dedicated Xray; Splicore and external resources are preserved'
}

vless_sudoku_doctor() {
  local failed=0 port mode host advertise_port uuid password cached_link current_link enabled
  if ! vless_sudoku_state_exists; then
    nb_doctor_line INFO 'VLESS Sudoku 未安装'
    return 0
  fi
  port="$(vless_sudoku_state_field listen_port)"
  enabled="$(vless_sudoku_state_field enabled 2>/dev/null || true)"
  case "$enabled" in true|false) ;; *) return 1 ;; esac
  uuid="$(vless_sudoku_state_field uuid)"
  password="$(jq -r '.finalmask_json.tcp[0].settings.password // empty' "$NOBRAND_VLESS_STATE_FILE")"
  [ -x "$NOBRAND_XRAY_BIN" ] \
    && nb_doctor_line PASS "Xray $(nobrand_xray_version 2>/dev/null || printf '未知版本')" \
    || { nb_doctor_line FAIL 'NoBrand Xray 可执行文件'; failed=1; }
  vless_sudoku_state_matches \
    && nb_doctor_line PASS '状态 schema 与 VLESS 元数据有效' \
    || { nb_doctor_line FAIL '状态 schema / 元数据无效'; failed=1; }
  vless_sudoku_server_config_matches "$NOBRAND_VLESS_CONFIG_FILE" "$uuid" "$port" "$password" \
    && nb_doctor_line PASS 'VLESS + TCP + FinalMask Sudoku 配置有效' \
    || { nb_doctor_line FAIL '服务端配置语义无效'; failed=1; }
  nobrand_xray_test_config "$NOBRAND_VLESS_CONFIG_FILE" \
    && nb_doctor_line PASS 'Xray 配置校验' \
    || { nb_doctor_line FAIL 'Xray 配置校验'; failed=1; }
  vless_sudoku_forbidden_absent "$NOBRAND_VLESS_CONFIG_FILE" \
    "$NOBRAND_VLESS_STATE_FILE" "$NOBRAND_VLESS_CLIENT_FILE" \
    && nb_doctor_line PASS 'VLESS Encryption 未使用' \
    || { nb_doctor_line FAIL '检测到禁用的 Encryption 依赖或字段'; failed=1; }
  vless_sudoku_client_config_matches \
    && nb_doctor_line PASS 'Xray 客户端 JSON' \
    || { nb_doctor_line FAIL 'Xray 客户端 JSON'; failed=1; }
  if [ "$enabled" = true ]; then
    vless_sudoku_running \
      && nb_doctor_line PASS "服务与 TCP/${port} 监听正常" \
      || { nb_doctor_line FAIL "服务 / 监听异常: TCP/${port}"; failed=1; }
  elif nobrand_vless_sudoku_service_active || nb_port_is_listening TCP "$port"; then
    nb_doctor_line FAIL "服务标记为已停止，但仍有服务或监听: TCP/${port}"
    failed=1
  else
    nb_doctor_line PASS '服务按状态保持停止，且无残留监听'
  fi
  nb_firewall_binding_owned TCP "$port" \
    && nb_doctor_line PASS "防火墙归属正常: TCP/${port}" \
    || nb_doctor_line INFO "防火墙规则不归 NoBrand 管理（预先存在 / 无本地防火墙）: TCP/${port}"
  mode="$(vless_sudoku_state_field advertise_mode)"
  host="$(vless_sudoku_state_field advertise_host)"
  advertise_port="$(vless_sudoku_state_field advertise_port)"
  nb_validate_advertise_endpoint "$host" "$advertise_port" TCP \
    && nb_doctor_line PASS "展示端点 / Display Endpoint 模式=${mode}" \
    || { nb_doctor_line FAIL '展示端点 / Display Endpoint 状态无效'; failed=1; }
  vless_sudoku_current_share_link >/dev/null \
    && nb_doctor_line PASS 'VLESS URL 生成正常' \
    || { nb_doctor_line FAIL 'VLESS URL 生成失败'; failed=1; }
  cached_link="$(vless_sudoku_state_field link 2>/dev/null || true)"
  current_link="$(vless_sudoku_current_share_link 2>/dev/null || true)"
  [ -n "$current_link" ] && [ "$cached_link" = "$current_link" ] \
    && nb_doctor_line PASS '缓存的 VLESS URL 与状态一致' \
    || { nb_doctor_line FAIL '缓存的 VLESS URL 与状态不一致'; failed=1; }
  return "$failed"
}

vless_sudoku_smoke() {
  local failed=0
  vless_sudoku_state_exists || { nb_doctor_line INFO 'VLESS Sudoku 未安装'; return 0; }
  vless_sudoku_state_matches \
    && nb_doctor_line PASS '状态 schema 有效' || { nb_doctor_line FAIL '状态 schema 无效'; failed=1; }
  nobrand_xray_test_config "$NOBRAND_VLESS_CONFIG_FILE" \
    && nb_doctor_line PASS 'xray run -test' || { nb_doctor_line FAIL 'xray run -test'; failed=1; }
  vless_sudoku_forbidden_absent "$NOBRAND_VLESS_CONFIG_FILE" \
    "$NOBRAND_VLESS_STATE_FILE" "$NOBRAND_VLESS_CLIENT_FILE" \
    && nb_doctor_line PASS 'VLESS_ENCRYPTION_ENABLED=false' \
    || { nb_doctor_line FAIL '检测到 VLESS Encryption 数据'; failed=1; }
  vless_sudoku_running \
    && nb_doctor_line PASS '服务 / 监听正常' || { nb_doctor_line FAIL '服务 / 监听异常'; failed=1; }
  return "$failed"
}

vless_sudoku_refresh_runtime_metadata() {
  local tmp runtime
  vless_sudoku_state_exists || return 0
  runtime="$(nobrand_xray_version)" || return 1
  tmp="$(mktemp_file .json)" || return 1
  jq --arg runtime "$runtime" --arg updated "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '.runtime_version=$runtime | .updated_at=$updated' "$NOBRAND_VLESS_STATE_FILE" >"$tmp" \
    && nb_atomic_install_file "$tmp" "$NOBRAND_VLESS_STATE_FILE" 0600
  local rc=$?
  rm -f "$tmp"
  return "$rc"
}

vless_sudoku_upgrade_runtime() {
  nobrand_upgrade_xray_runtime
}

nobrand_run_vless_sudoku_action() {
  case "${VLESS_SUDOKU_ACTION:-menu}" in
    menu) vless_sudoku_menu_loop ;;
    install)
      if [ "${NOBRAND_MANAGER_SESSION_ACTIVE:-0}" -eq 1 ]; then
        nb_lifecycle_run_protocol_install vless-sudoku install_vless_sudoku
      else
        install_vless_sudoku
      fi
      ;;
    show) print_vless_sudoku_result show ;;
    set-endpoint) vless_sudoku_set_endpoint ;;
    remove) remove_vless_sudoku_config ;;
    start|stop|restart|status) vless_sudoku_service_command "$VLESS_SUDOKU_ACTION" ;;
    doctor) vless_sudoku_doctor ;;
    smoke) vless_sudoku_smoke ;;
    upgrade) vless_sudoku_upgrade_runtime ;;
    help) nobrand_usage ;;
  esac
}

# Native architecture: ordinary protocols use src/19-splicore.sh.

nobrand_run_tuic_action() {
  case "${TUIC_ACTION:-menu}" in
    menu) tuic_menu_loop ;;
    help) nobrand_usage ;;
    *) nb_splicore_protocol tuic "${TUIC_ACTION:-status}" "${TUIC_NAME:-}" ;;
  esac
}

# Native architecture: ordinary protocols use src/19-splicore.sh.

nobrand_run_vless_reality_action() {
  case "${VLESS_REALITY_ACTION:-menu}" in
    menu) vless_reality_menu_loop ;;
    help) nobrand_usage ;;
    *) nb_splicore_protocol vless-reality "${VLESS_REALITY_ACTION:-status}" "${VLESS_REALITY_NAME:-}" ;;
  esac
}

firewall_owned_has() {
  local key="$1"
  [ -f "$MITA_FIREWALL_OWNED_STATE" ] \
    && grep -qxF "$key" "$MITA_FIREWALL_OWNED_STATE" 2>/dev/null
}

firewall_owned_add() {
  local key="$1"
  firewall_owned_has "$key" && return 0
  if [ "${DRY_RUN:-0}" -eq 1 ]; then
    t "[演练] 记录自有防火墙规则: $key" "[dry-run] own firewall rule: $key"
    return 0
  fi
  mkdir -p "$(dirname "$MITA_FIREWALL_OWNED_STATE")"
  printf '%s\n' "$key" >>"$MITA_FIREWALL_OWNED_STATE"
  chmod 0600 "$MITA_FIREWALL_OWNED_STATE" 2>/dev/null || true
}

firewall_owned_remove() {
  local key="$1" tmp
  [ -f "$MITA_FIREWALL_OWNED_STATE" ] || return 0
  if [ "${DRY_RUN:-0}" -eq 1 ]; then
    t "[演练] 释放自有防火墙规则: $key" "[dry-run] release firewall rule: $key"
    return 0
  fi
  tmp="${MITA_FIREWALL_OWNED_STATE}.new.$$"
  grep -vxF "$key" "$MITA_FIREWALL_OWNED_STATE" >"$tmp" 2>/dev/null || true
  if [ -s "$tmp" ]; then
    chmod 0600 "$tmp" 2>/dev/null || true
    mv -f "$tmp" "$MITA_FIREWALL_OWNED_STATE"
  else
    rm -f "$tmp" "$MITA_FIREWALL_OWNED_STATE"
  fi
}

iptables_remove_owned_rule() {
  local ipt="$1" proto="$2" p="$3" key
  key="${ipt}|${proto}|${p}"
  firewall_owned_has "$key" || return 0
  command -v "$ipt" >/dev/null 2>&1 || return 1
  if "$ipt" -C INPUT -p "$proto" --dport "$p" -m comment \
      --comment "$MITA_FIREWALL_COMMENT" -j ACCEPT 2>/dev/null; then
    run "$ipt" -D INPUT -p "$proto" --dport "$p" -m comment \
      --comment "$MITA_FIREWALL_COMMENT" -j ACCEPT 2>/dev/null || return 1
  fi
  if "$ipt" -C INPUT -p "$proto" --dport "$p" -m comment \
      --comment "$MITA_FIREWALL_COMMENT" -j ACCEPT 2>/dev/null; then
    return 1
  fi
  firewall_owned_remove "$key"
}

ufw_binding_exists() {
  local spec="$1"
  ufw show added 2>/dev/null | grep -Eq \
    "^ufw[[:space:]]+allow([[:space:]]+in)?[[:space:]]+${spec//./\\.}([[:space:]]|$)"
}

firewall_apply_binding() {
  local fw="$1" action="$2" proto="$3" p="$4" spec key
  spec="$(ufw_rule_spec "$p" "$proto")"
  case "${fw}:${action}" in
    ufw:add)
      key="ufw|${proto}|${p}"
      firewall_owned_has "$key" && return 0
      ufw_binding_exists "$spec" && return 0
      if run ufw allow "$spec"; then
        firewall_owned_add "$key"
      else
        return 1
      fi
      ;;
    ufw:del)
      key="ufw|${proto}|${p}"
      firewall_owned_has "$key" || return 0
      command -v ufw >/dev/null 2>&1 || return 0
      if run ufw --force delete allow "$spec" 2>/dev/null \
         || ! ufw_binding_exists "$spec"; then
        firewall_owned_remove "$key"
      fi
      ;;
    firewalld:add)
      key="firewalld|${proto}|${p}"
      firewall_owned_has "$key" && return 0
      firewall-cmd --permanent --query-port="${p}/${proto}" >/dev/null 2>&1 && return 0
      if run firewall-cmd --permanent --add-port="${p}/${proto}"; then
        firewall_owned_add "$key"
      else
        return 1
      fi
      ;;
    firewalld:del)
      key="firewalld|${proto}|${p}"
      firewall_owned_has "$key" || return 0
      command -v firewall-cmd >/dev/null 2>&1 || return 0
      if run firewall-cmd --permanent --remove-port="${p}/${proto}" 2>/dev/null \
         || ! firewall-cmd --permanent --query-port="${p}/${proto}" >/dev/null 2>&1; then
        firewall_owned_remove "$key"
      fi
      ;;
    iptables:add|iptables:del)
      iptables_accept_port "$p" "$proto" "$action"
      ;;
  esac
}

close_firewall_for_bindings() {
  local bindings="$1"
  local pp proto p proto_lc
  [ -n "$bindings" ] || return 0

  while IFS= read -r pp; do
    [ -n "$pp" ] || continue
    proto="${pp%%|*}"
    p="${pp#*|}"
    proto_lc="$(proto_lower "$proto")"
    firewall_apply_binding ufw del "$proto_lc" "$p"
    firewall_apply_binding firewalld del "$proto_lc" "$p"
    firewall_apply_binding iptables del "$proto_lc" "$p"
  done <<< "$bindings"

  command -v firewall-cmd >/dev/null 2>&1 \
    && run firewall-cmd --reload 2>/dev/null || true
  persist_iptables_rules
}

ufw_rule_spec() {
  local p="$1"
  local proto="$2"
  if [[ "$p" == *-* ]]; then
    local start="${p%-*}"
    local end="${p#*-}"
    printf '%s:%s/%s' "$start" "$end" "$proto"
  else
    printf '%s/%s' "$p" "$proto"
  fi
}

iptables_accept_port() {
  local p="$1"
  local proto="$2"
  local action="${3:-add}"
  local ipt key
  for ipt in iptables ip6tables; do
    command -v "$ipt" >/dev/null 2>&1 || continue
    if [[ "$p" == *-* ]]; then
      local start end port
      start="${p%-*}"
      end="${p#*-}"
      port="$start"
      while [ "$port" -le "$end" ]; do
        key="${ipt}|${proto}|${port}"
        if [ "$action" = add ]; then
          if "$ipt" -C INPUT -p "$proto" --dport "$port" -m comment \
              --comment "$MITA_FIREWALL_COMMENT" -j ACCEPT 2>/dev/null; then
            firewall_owned_add "$key"
          elif "$ipt" -C INPUT -p "$proto" --dport "$port" -j ACCEPT 2>/dev/null; then
            :
          elif run "$ipt" -I INPUT -p "$proto" --dport "$port" -m comment \
              --comment "$MITA_FIREWALL_COMMENT" -j ACCEPT; then
            firewall_owned_add "$key"
          fi
        elif firewall_owned_has "$key"; then
          iptables_remove_owned_rule "$ipt" "$proto" "$port" || return 1
        fi
        port=$((port + 1))
      done
    else
      key="${ipt}|${proto}|${p}"
      if [ "$action" = add ]; then
        if "$ipt" -C INPUT -p "$proto" --dport "$p" -m comment \
            --comment "$MITA_FIREWALL_COMMENT" -j ACCEPT 2>/dev/null; then
          firewall_owned_add "$key"
        elif "$ipt" -C INPUT -p "$proto" --dport "$p" -j ACCEPT 2>/dev/null; then
          :
        elif run "$ipt" -I INPUT -p "$proto" --dport "$p" -m comment \
            --comment "$MITA_FIREWALL_COMMENT" -j ACCEPT; then
          firewall_owned_add "$key"
        fi
      elif firewall_owned_has "$key"; then
        iptables_remove_owned_rule "$ipt" "$proto" "$p" || return 1
      fi
    fi
  done
}

persist_iptables_rules() {
  if [ -d /etc/iptables ] || [ -f /etc/alpine-release ]; then
    if [ "${DRY_RUN:-0}" -eq 1 ]; then
      t '[演练] 将运行 iptables-save > /etc/iptables/rules.v4' \
        '[dry-run] iptables-save > /etc/iptables/rules.v4'
      return 0
    fi
    local rules_tmp
    rules_tmp="$(mktemp_file .rules.v4)" || return 1
    run mkdir -p /etc/iptables
    if iptables-save >"$rules_tmp" 2>/dev/null; then
      install -m 0600 "$rules_tmp" /etc/iptables/rules.v4 2>/dev/null || true
    fi
    rm -f "$rules_tmp"
    if command -v ip6tables-save >/dev/null 2>&1; then
      rules_tmp="$(mktemp_file .rules.v6)" || return 1
      if ip6tables-save >"$rules_tmp" 2>/dev/null; then
        install -m 0600 "$rules_tmp" /etc/iptables/rules.v6 2>/dev/null || true
      fi
      rm -f "$rules_tmp"
    fi
  fi
}

valid_ip_literal() {
  local value="${1:-}" a b c d extra colons segment remainder
  local -a parts=()
  [ -n "$value" ] || return 1
  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import ipaddress,sys; ipaddress.ip_address(sys.argv[1])' "$value" 2>/dev/null
    return $?
  fi
  if [[ "$value" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    IFS=. read -r a b c d extra <<< "$value"
    [ -z "${extra:-}" ] || return 1
    for segment in "$a" "$b" "$c" "$d"; do
      [[ "$segment" =~ ^[0-9]{1,3}$ ]] && [ "$segment" -le 255 ] || return 1
    done
    return 0
  fi
  [[ "$value" == *:* ]] || return 1
  [[ "$value" =~ ^[0-9A-Fa-f:]+$ ]] || return 1
  [[ "$value" != *:::* ]] || return 1
  colons="${value//[^:]/}"
  [ "${#colons}" -ge 2 ] && [ "${#colons}" -le 7 ] || return 1
  if [[ "$value" == *::* ]]; then
    remainder="${value#*::}"
    [[ "$remainder" != *::* ]] || return 1
  else
    [ "${#colons}" -eq 7 ] || return 1
  fi
  IFS=: read -r -a parts <<< "$value"
  for segment in "${parts[@]}"; do
    [ "${#segment}" -le 4 ] || return 1
  done
  return 0
}

valid_domain_name() {
  local value="${1:-}" label rest
  [ -n "$value" ] && [ "${#value}" -le 253 ] || return 1
  [[ "$value" != *[[:space:]]* ]] || return 1
  [[ "$value" != *://* && "$value" != *:* && "$value" != /* ]] || return 1
  value="${value%.}"
  [ -n "$value" ] || return 1
  # A dotted decimal quad is an IPv4 candidate, not a DNS name. Reject it
  # here when valid_ip_literal has already rejected its octets.
  [[ ! "$value" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
  rest="$value"
  while true; do
    label="${rest%%.*}"
    [ -n "$label" ] && [ "${#label}" -le 63 ] || return 1
    [[ "$label" =~ ^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?$ ]] || return 1
    [ "$rest" != "$label" ] || break
    rest="${rest#*.}"
  done
}

valid_advertise_host() {
  valid_ip_literal "${1:-}" || valid_domain_name "${1:-}"
}

valid_public_ip_literal() {
  local value="${1:-}"
  valid_ip_literal "$value" || return 1
  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import ipaddress,sys; raise SystemExit(0 if ipaddress.ip_address(sys.argv[1]).is_global else 1)' \
      "$value" 2>/dev/null
    return $?
  fi
  case "$value" in
    10.*|127.*|169.254.*|192.168.*|172.1[6-9].*|172.2[0-9].*|172.3[01].*|\
    100.6[4-9].*|100.[7-9][0-9].*|100.1[01][0-9].*|100.12[0-7].*|\
    ::1|fe8*|fe9*|fea*|feb*|fc*|fd*) return 1 ;;
  esac
  return 0
}

public_ip() {
  local candidate=""
  candidate="$(curl -fsSL --connect-timeout 5 --max-time 10 https://checkip.amazonaws.com 2>/dev/null \
    | head -n1 | tr -d '[:space:]' || true)"
  if valid_public_ip_literal "$candidate"; then
    printf '%s' "$candidate"
    return 0
  fi
  candidate="$(curl -fsSL --connect-timeout 5 --max-time 10 https://api.ip.sb/ip 2>/dev/null \
    | head -n1 | tr -d '[:space:]' || true)"
  if valid_public_ip_literal "$candidate"; then
    printf '%s' "$candidate"
    return 0
  fi
  candidate="$(hostname -I 2>/dev/null | awk '{print $1}' | tr -d '[:space:]' || true)"
  valid_public_ip_literal "$candidate" || return 1
  printf '%s' "$candidate"
}

# ---------- SSH Tunnel: existing-OpenSSH policy and dedicated identities ----------

ssh_tunnel_state_exists() {
  [ -s "$NOBRAND_SSH_STATE_FILE" ] && jq empty "$NOBRAND_SSH_STATE_FILE" >/dev/null 2>&1
}

ssh_tunnel_state_absent() {
  [ ! -e "$NOBRAND_SSH_STATE_FILE" ] && [ ! -L "$NOBRAND_SSH_STATE_FILE" ]
}

ssh_tunnel_state_field() {
  local field="$1"
  ssh_tunnel_state_exists || return 1
  jq -r --arg field "$field" \
    'if has($field) and .[$field] != null then .[$field] else empty end' \
    "$NOBRAND_SSH_STATE_FILE"
}

ssh_tunnel_valid_label() {
  local value="${1:-}"
  [ -n "$value" ] || return 1
  [ "$(printf '%s' "$value" | wc -c | tr -d '[:space:]')" -le 64 ] || return 1
  ! has_control_chars "$value" && [[ "$value" != *'|'* ]]
}

ssh_tunnel_generate_account_id() {
  local value
  if command -v openssl >/dev/null 2>&1; then
    value="$(openssl rand -hex 8 2>/dev/null || true)"
  fi
  [ -n "${value:-}" ] || value="$(printf '%08x%08x' "$RANDOM" "$RANDOM")"
  printf 'a%s' "$value"
}

ssh_tunnel_linux_username() {
  local label="$1" account_id="$2" slug
  slug="$(printf '%s' "$label" | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//' | cut -c1-14)"
  [ -n "$slug" ] || slug=user
  printf 'nbt-%s-%s' "$slug" "${account_id#a}" | cut -c1-31
}

ssh_tunnel_nologin_shell() {
  local candidate
  for candidate in /usr/sbin/nologin /sbin/nologin /bin/false; do
    [ -x "$candidate" ] && { printf '%s' "$candidate"; return 0; }
  done
  return 1
}

ssh_tunnel_generate_policy() {
  local output="$1" nologin_shell="${2:-}" auth_pattern
  [ -n "$nologin_shell" ] || nologin_shell="$(ssh_tunnel_nologin_shell)" || return 1
  auth_pattern="${NOBRAND_SSH_AUTHORIZED_KEYS_DIR}/%u"
  cat >"$output" <<EOF
Match Group ${NOBRAND_SSH_GROUP}
    AuthenticationMethods publickey
    PubkeyAuthentication yes
    PasswordAuthentication no
    KbdInteractiveAuthentication no
    AuthorizedKeysFile ${auth_pattern}
    AllowTcpForwarding yes
    AllowStreamLocalForwarding no
    GatewayPorts no
    PermitTTY no
    X11Forwarding no
    AllowAgentForwarding no
    PermitTunnel no
    PermitUserRC no
    MaxSessions 0
    ForceCommand ${nologin_shell}
Match all
EOF
  chmod 0600 "$output" 2>/dev/null || true
}

ssh_tunnel_sshd_binary() {
  local candidate
  for candidate in "${NOBRAND_SSHD_BIN:-}" /usr/sbin/sshd /sbin/sshd; do
    [ -n "$candidate" ] && [ -x "$candidate" ] && { printf '%s' "$candidate"; return 0; }
  done
  command -v sshd 2>/dev/null || return 1
}

ssh_tunnel_sshd_test() {
  local config="${1:-$NOBRAND_SSH_CONFIG_MAIN}" sshd
  sshd="$(ssh_tunnel_sshd_binary)" || return 1
  "$sshd" -t -f "$config"
}

ssh_tunnel_sshd_effective() {
  local config="$1" user="$2" host="${3:-localhost}" addr="${4:-127.0.0.1}" sshd
  sshd="$(ssh_tunnel_sshd_binary)" || return 1
  "$sshd" -T -f "$config" -C "user=${user},host=${host},addr=${addr}"
}

ssh_tunnel_effective_policy_valid() {
  local config="$1" user="$2" effective expected key value
  effective="$(ssh_tunnel_sshd_effective "$config" "$user")" || return 1
  while IFS='|' read -r key expected; do
    value="$(printf '%s\n' "$effective" | awk -v key="$key" '$1==key {$1=""; sub(/^ /,""); print; exit}')"
    [ "$value" = "$expected" ] || {
      warn "SSH Tunnel 生效策略不匹配: ${key}=${value:-缺失}，预期 ${expected}"
      return 1
    }
  done <<EOF
authenticationmethods|publickey
pubkeyauthentication|yes
passwordauthentication|no
kbdinteractiveauthentication|no
allowtcpforwarding|yes
allowstreamlocalforwarding|no
gatewayports|no
permittty|no
x11forwarding|no
allowagentforwarding|no
permittunnel|no
permituserrc|no
maxsessions|0
forcecommand|$(ssh_tunnel_nologin_shell)
EOF
}

ssh_tunnel_detect_real_port() {
  local sshd output
  sshd="$(ssh_tunnel_sshd_binary)" || return 1
  output="$("$sshd" -T -f "$NOBRAND_SSH_CONFIG_MAIN" 2>/dev/null)" || return 1
  printf '%s\n' "$output" | awk '$1=="port" && $2 ~ /^[0-9]+$/ {print $2; exit}'
}

ssh_tunnel_default_display_port() {
  local ip base real_port profile
  if [ -n "${INGRESS_PROFILE_ID:-}" ] \
     && [ "$INGRESS_PROFILE_ID" != "$NOBRAND_LEGACY_INGRESS_PROFILE_ID" ]; then
    profile="$(nb_ingress_profile_json "$INGRESS_PROFILE_ID" 2>/dev/null || true)"
    ip="$(jq -r '.local_address // empty' <<<"$profile" 2>/dev/null || true)"
  else
    ip="$(nb_detect_local_ipv4 2>/dev/null || true)"
  fi
  if [ -n "$ip" ]; then
    base="$(nb_port_base_for_ip "$ip" 2>/dev/null || true)"
    if [ -n "$base" ]; then
      printf '%s' "$base"
      return 0
    fi
  fi
  real_port="$(ssh_tunnel_detect_real_port 2>/dev/null || true)"
  valid_advertise_port "$real_port" || return 1
  printf '%s' "$(normalize_uint "$real_port")"
}

ssh_tunnel_generate_state() {
  local output="$1" advertise_mode="$2" advertise_host="$3" advertise_port="$4"
  local real_port="$5" strategy="$6" managed_path="$7" users="$8" created_at="${9:-}"
  local ingress_profile_id="${10:-}"
  local updated_at
  [ -n "$created_at" ] || created_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  updated_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  jq -n --arg mode "$advertise_mode" --arg host "$advertise_host" \
    --arg advertise_port "$advertise_port" --arg real_port "$real_port" \
    --arg group "$NOBRAND_SSH_GROUP" --arg strategy "$strategy" \
    --arg managed_path "$managed_path" --argjson users "$users" \
    --arg created "$created_at" --arg updated "$updated_at" --arg ingress_profile_id "$ingress_profile_id" '
    {
      schema_version:3,
      ownership:"nobrand-v3",
      protocol:"ssh-tunnel",
      group:$group,
      external_listener:true,
      managed_listener:false,
      managed_firewall:false,
      real_port:($real_port|tonumber),
      advertise_mode:$mode,
      advertise_host:$host,
      advertise_port:($advertise_port|tonumber),
      config_strategy:$strategy,
      managed_config_path:$managed_path,
      policy_applied:false,
      pending_operation:"",
      pending_watchdog_token:"",
      pending_origin_connection:"",
      users:$users,
      created_at:$created,
      updated_at:$updated
    }
    + if $ingress_profile_id=="" then {} else {ingress_profile_id:$ingress_profile_id} end
  ' >"$output"
}

ssh_tunnel_user_json() {
  local account_id="$1" label="$2" linux_user="$3" uid="$4" fingerprint="$5"
  local created_at="${6:-}"
  [ -n "$created_at" ] || created_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  jq -n --arg account_id "$account_id" --arg display_name "$label" --arg linux_user "$linux_user" \
    --arg uid "$uid" --arg group "$NOBRAND_SSH_GROUP" --arg fingerprint "$fingerprint" \
    --arg created "$created_at" '
    {
      account_id:$account_id,
      display_name:$display_name,
      linux_user:$linux_user,
      uid:($uid|tonumber),
      group:$group,
      key_fingerprint:$fingerprint,
      created_at:$created
    }
  '
}

ssh_tunnel_resolve_user_json() {
  local selector="${1:-}"
  ssh_tunnel_state_exists || return 1
  [ -n "$selector" ] || {
    [ "$(jq '.users | length' "$NOBRAND_SSH_STATE_FILE")" -eq 1 ] || return 1
    jq -c '.users[0]' "$NOBRAND_SSH_STATE_FILE"
    return 0
  }
  jq -ce --arg selector "$selector" '
    [.users[] | select(.account_id==$selector or .display_name==$selector or .linux_user==$selector)]
    | if length==1 then .[0] else empty end
  ' "$NOBRAND_SSH_STATE_FILE"
}

ssh_tunnel_account_marker_file() {
  printf '%s/%s.json' "$NOBRAND_SSH_ACCOUNT_MARKER_DIR" "$1"
}

ssh_tunnel_authorized_key_file() {
  printf '%s/%s' "$NOBRAND_SSH_AUTHORIZED_KEYS_DIR" "$1"
}

ssh_tunnel_key_dir() {
  printf '%s/%s' "$NOBRAND_SSH_KEYS_DIR" "$1"
}

ssh_tunnel_public_key_material() {
  local public_key="$1"
  awk '
    NF {
      count++
      if (count != 1 || NF < 2) exit 1
      key_type=$1
      key_blob=$2
    }
    END {
      if (count != 1 || key_type=="" || key_blob=="") exit 1
      print key_type " " key_blob
    }
  ' "$public_key"
}

ssh_tunnel_single_key_fingerprint() {
  local key_file="$1" output fingerprint
  awk 'NF { count++ } END { exit count==1 ? 0 : 1 }' "$key_file" || return 1
  output="$(ssh-keygen -lf "$key_file" -E sha256 2>/dev/null)" || return 1
  fingerprint="$(awk '
    NF {
      count++
      if (count != 1 || length($2) != 50 || index($2,"SHA256:") != 1 ||
          substr($2,8) !~ /^[A-Za-z0-9+\/]+$/) exit 1
      value=$2
    }
    END {
      if (count != 1 || value=="") exit 1
      print value
    }
  ' <<<"$output")" || return 1
  printf '%s\n' "$fingerprint"
}

ssh_tunnel_key_fingerprint() {
  local public_key="$1"
  ssh_tunnel_public_key_material "$public_key" >/dev/null || return 1
  ssh_tunnel_single_key_fingerprint "$public_key"
}

ssh_tunnel_authorized_key_line() {
  local public_key="$1" nologin_shell="$2" key_material
  ssh_tunnel_key_fingerprint "$public_key" >/dev/null || return 1
  key_material="$(ssh_tunnel_public_key_material "$public_key")" || return 1
  printf 'command="%s",no-agent-forwarding,no-X11-forwarding,no-pty %s\n' \
    "$nologin_shell" "$key_material"
}

ssh_tunnel_group_creation_matches() {
  local expected_gid="$1" group_line actual_name actual_gid
  [[ "$expected_gid" =~ ^[0-9]+$ ]] || return 1
  group_line="$(getent group "$NOBRAND_SSH_GROUP" 2>/dev/null || true)"
  [ -n "$group_line" ] || return 1
  IFS=: read -r actual_name _ actual_gid _ <<<"$group_line"
  [ "$actual_name" = "$NOBRAND_SSH_GROUP" ] && [ "$actual_gid" = "$expected_gid" ]
}

ssh_tunnel_create_group() {
  local result_var="${1:-}" gid marker_tmp="" created_group=0 create_rc=0
  [ -z "$result_var" ] || printf -v "$result_var" '%s' 0
  if _has_group "$NOBRAND_SSH_GROUP"; then
    gid="$(getent group "$NOBRAND_SSH_GROUP" 2>/dev/null | awk -F: '{print $3}')"
    jq -e --arg group "$NOBRAND_SSH_GROUP" --arg gid "$gid" '
      .ownership=="nobrand-v3" and .group==$group and .gid==($gid|tonumber)
    ' "$NOBRAND_SSH_GROUP_MARKER" >/dev/null 2>&1
    return $?
  fi
  if command -v groupadd >/dev/null 2>&1; then
    groupadd --system "$NOBRAND_SSH_GROUP" || create_rc=$?
  elif command -v addgroup >/dev/null 2>&1; then
    addgroup -S "$NOBRAND_SSH_GROUP" || create_rc=$?
  else
    return 1
  fi
  if [ "$create_rc" -ne 0 ]; then
    gid="$(getent group "$NOBRAND_SSH_GROUP" 2>/dev/null | awk -F: '{print $3}')"
    if [ -n "$result_var" ] && ssh_tunnel_group_creation_matches "$gid"; then
      printf -v "$result_var" '%s' 1
    fi
    return "$create_rc"
  fi
  created_group=1
  [ -z "$result_var" ] || printf -v "$result_var" '%s' 1
  gid="$(getent group "$NOBRAND_SSH_GROUP" 2>/dev/null | awk -F: '{print $3}')"
  if ! [[ "$gid" =~ ^[0-9]+$ ]] \
     || ! mkdir -p "$NOBRAND_SSH_ACCOUNT_MARKER_DIR" \
     || ! chmod 0700 "$NOBRAND_SSH_ACCOUNT_MARKER_DIR" \
     || ! marker_tmp="$(mktemp_file .ssh-group-marker)" \
     || ! jq -n --arg group "$NOBRAND_SSH_GROUP" --arg gid "$gid" '
    {schema_version:3,ownership:"nobrand-v3",group:$group,gid:($gid|tonumber)}
  ' >"$marker_tmp" \
     || ! nb_atomic_install_file "$marker_tmp" "$NOBRAND_SSH_GROUP_MARKER" 0600; then
    rm -f "$marker_tmp" "$NOBRAND_SSH_GROUP_MARKER"
    if [ "$created_group" -eq 1 ] \
       && ssh_tunnel_delete_group >/dev/null 2>&1; then
      [ -z "$result_var" ] || printf -v "$result_var" '%s' 0
    fi
    return 1
  fi
  rm -f "$marker_tmp"
}

ssh_tunnel_create_group_with_gid() {
  local expected_gid="$1" result_var="${2:-}" actual_gid create_rc=0
  [ -z "$result_var" ] || printf -v "$result_var" '%s' 0
  [[ "$expected_gid" =~ ^[0-9]+$ ]] || return 1
  ! _has_group "$NOBRAND_SSH_GROUP" || return 1
  getent group "$expected_gid" >/dev/null 2>&1 && return 1
  if command -v groupadd >/dev/null 2>&1; then
    groupadd --system --gid "$expected_gid" "$NOBRAND_SSH_GROUP" || create_rc=$?
  elif command -v addgroup >/dev/null 2>&1; then
    addgroup -S -g "$expected_gid" "$NOBRAND_SSH_GROUP" || create_rc=$?
  else
    return 1
  fi
  if [ "$create_rc" -ne 0 ]; then
    if ssh_tunnel_group_creation_matches "$expected_gid"; then
      [ -z "$result_var" ] || printf -v "$result_var" '%s' 1
    fi
    return "$create_rc"
  fi
  [ -z "$result_var" ] || printf -v "$result_var" '%s' 1
  actual_gid="$(getent group "$NOBRAND_SSH_GROUP" 2>/dev/null | awk -F: '{print $3}')"
  [ "$actual_gid" = "$expected_gid" ]
}

ssh_tunnel_delete_group() {
  _has_group "$NOBRAND_SSH_GROUP" || return 0
  if command -v groupdel >/dev/null 2>&1; then
    groupdel "$NOBRAND_SSH_GROUP"
  elif command -v delgroup >/dev/null 2>&1; then
    delgroup "$NOBRAND_SSH_GROUP"
  else
    return 1
  fi
}

ssh_tunnel_group_identity_valid() {
  local gid
  _has_group "$NOBRAND_SSH_GROUP" || return 1
  [ -f "$NOBRAND_SSH_GROUP_MARKER" ] && [ ! -L "$NOBRAND_SSH_GROUP_MARKER" ] \
    && secure_stat_path "$NOBRAND_SSH_GROUP_MARKER" file \
    && [ "$(stat -c '%a' "$NOBRAND_SSH_GROUP_MARKER")" = 600 ] || return 1
  gid="$(getent group "$NOBRAND_SSH_GROUP" 2>/dev/null | awk -F: '{print $3}')"
  jq -e --arg group "$NOBRAND_SSH_GROUP" --arg gid "$gid" '
    .ownership=="nobrand-v3" and .group==$group and .gid==($gid|tonumber)
  ' "$NOBRAND_SSH_GROUP_MARKER" >/dev/null 2>&1
}

ssh_tunnel_create_linux_user() {
  local linux_user="$1" account_id="$2" nologin_shell="$3"
  ! _has_user "$linux_user" || return 1
  if command -v useradd >/dev/null 2>&1; then
    useradd --system --gid "$NOBRAND_SSH_GROUP" --no-create-home --home-dir /nonexistent \
      --shell "$nologin_shell" --comment "NoBrand SSH Tunnel ${account_id}" "$linux_user" || return 1
  elif command -v adduser >/dev/null 2>&1; then
    adduser -S -D -H -G "$NOBRAND_SSH_GROUP" -h /nonexistent -s "$nologin_shell" \
      -g "NoBrand SSH Tunnel ${account_id}" "$linux_user" || return 1
  else
    return 1
  fi
  command -v passwd >/dev/null 2>&1 && passwd -l "$linux_user" >/dev/null 2>&1 || true
}

ssh_tunnel_linux_user_creation_matches() {
  local linux_user="$1" account_id="$2" nologin_shell="$3" expected_uid="$4"
  local passwd_line group_line actual_name actual_uid actual_gid gecos home shell
  local group_name group_gid
  passwd_line="$(getent passwd "$linux_user" 2>/dev/null || true)"
  group_line="$(getent group "$NOBRAND_SSH_GROUP" 2>/dev/null || true)"
  [ -n "$passwd_line" ] && [ -n "$group_line" ] || return 1
  IFS=: read -r actual_name _ actual_uid actual_gid gecos home shell <<<"$passwd_line"
  IFS=: read -r group_name _ group_gid _ <<<"$group_line"
  [ "$actual_name" = "$linux_user" ] \
    && [ "$actual_uid" = "$expected_uid" ] \
    && [ "$group_name" = "$NOBRAND_SSH_GROUP" ] \
    && [ "$actual_gid" = "$group_gid" ] \
    && [ "$gecos" = "NoBrand SSH Tunnel ${account_id}" ] \
    && [ "$home" = /nonexistent ] \
    && [ "$shell" = "$nologin_shell" ]
}

ssh_tunnel_create_linux_user_with_uid() {
  local linux_user="$1" account_id="$2" nologin_shell="$3" expected_uid="$4"
  local result_var="${5:-}" create_rc=0
  [ -z "$result_var" ] || printf -v "$result_var" '%s' 0
  ! _has_user "$linux_user" || return 1
  getent passwd "$expected_uid" >/dev/null 2>&1 && return 1
  if command -v useradd >/dev/null 2>&1; then
    useradd --system --uid "$expected_uid" --gid "$NOBRAND_SSH_GROUP" --no-create-home \
      --home-dir /nonexistent --shell "$nologin_shell" \
      --comment "NoBrand SSH Tunnel ${account_id}" "$linux_user" || create_rc=$?
  elif command -v adduser >/dev/null 2>&1; then
    adduser -S -D -H -u "$expected_uid" -G "$NOBRAND_SSH_GROUP" -h /nonexistent \
      -s "$nologin_shell" -g "NoBrand SSH Tunnel ${account_id}" "$linux_user" || create_rc=$?
  else
    return 1
  fi
  if [ "$create_rc" -ne 0 ]; then
    if ssh_tunnel_linux_user_creation_matches \
      "$linux_user" "$account_id" "$nologin_shell" "$expected_uid"; then
      [ -z "$result_var" ] || printf -v "$result_var" '%s' 1
    fi
    return "$create_rc"
  fi
  [ -z "$result_var" ] || printf -v "$result_var" '%s' 1
  command -v passwd >/dev/null 2>&1 && passwd -l "$linux_user" >/dev/null 2>&1 || true
  [ "$(id -u "$linux_user")" = "$expected_uid" ]
}

ssh_tunnel_delete_linux_user() {
  local linux_user="$1"
  if command -v userdel >/dev/null 2>&1; then
    userdel "$linux_user"
  elif command -v deluser >/dev/null 2>&1; then
    deluser "$linux_user"
  else
    return 1
  fi
}

ssh_tunnel_linux_user_identity_valid() {
  local user_json="$1" linux_user expected_uid expected_group account_id
  local passwd_line actual_uid actual_gid group_gid gecos shell
  linux_user="$(jq -r .linux_user <<<"$user_json")"
  expected_uid="$(jq -r .uid <<<"$user_json")"
  expected_group="$(jq -r .group <<<"$user_json")"
  account_id="$(jq -r .account_id <<<"$user_json")"
  passwd_line="$(getent passwd "$linux_user" 2>/dev/null || true)"
  [ -n "$passwd_line" ] || return 1
  IFS=: read -r _ _ actual_uid actual_gid gecos _ shell <<<"$passwd_line"
  group_gid="$(getent group "$expected_group" 2>/dev/null | awk -F: '{print $3}')"
  [ "$actual_uid" = "$expected_uid" ] && [ "$actual_gid" = "$group_gid" ] || return 1
  [ "$gecos" = "NoBrand SSH Tunnel ${account_id}" ] || return 1
  case "$shell" in /usr/sbin/nologin|/sbin/nologin|/bin/false) ;; *) return 1 ;; esac
}

ssh_tunnel_user_identity_valid() {
  local user_json="$1" linux_user expected_uid account_id expected_fp marker auth_file actual_fp
  ssh_tunnel_linux_user_identity_valid "$user_json" || return 1
  linux_user="$(jq -r .linux_user <<<"$user_json")"
  expected_uid="$(jq -r .uid <<<"$user_json")"
  account_id="$(jq -r .account_id <<<"$user_json")"
  expected_fp="$(jq -r .key_fingerprint <<<"$user_json")"
  marker="$(ssh_tunnel_account_marker_file "$linux_user")"
  [ -f "$marker" ] && [ ! -L "$marker" ] && secure_stat_path "$marker" file \
    && [ "$(stat -c '%a' "$marker")" = 600 ] || return 1
  jq -e --arg account_id "$account_id" --arg linux_user "$linux_user" --arg uid "$expected_uid" \
    '.ownership=="nobrand-v3" and .account_id==$account_id and .linux_user==$linux_user and .uid==($uid|tonumber)' \
    "$marker" >/dev/null 2>&1 || return 1
  auth_file="$(ssh_tunnel_authorized_key_file "$linux_user")"
  [ -f "$auth_file" ] && [ ! -L "$auth_file" ] && [ -s "$auth_file" ] \
    && secure_stat_path "$auth_file" file \
    && [ "$(stat -c '%a' "$auth_file")" = 644 ] || return 1
  actual_fp="$(ssh_tunnel_single_key_fingerprint "$auth_file")" || return 1
  [ "$actual_fp" = "$expected_fp" ]
}

ssh_tunnel_user_key_material_valid() {
  local user_json="$1" account_id expected_fp key_dir private_key public_key
  local actual_fp private_check="" private_output private_material public_material
  account_id="$(jq -r .account_id <<<"$user_json")"
  expected_fp="$(jq -r .key_fingerprint <<<"$user_json")"
  key_dir="$(ssh_tunnel_key_dir "$account_id")"
  private_key="${key_dir}/id_ed25519"
  public_key="${private_key}.pub"
  [ -d "$key_dir" ] && [ ! -L "$key_dir" ] \
    && secure_stat_path "$key_dir" dir \
    && [ "$(stat -c '%a' "$key_dir")" = 700 ] \
    && [ -f "$private_key" ] && [ ! -L "$private_key" ] \
    && secure_stat_path "$private_key" file \
    && [ "$(stat -c '%a' "$private_key")" = 600 ] \
    && [ -f "$public_key" ] && [ ! -L "$public_key" ] \
    && secure_stat_path "$public_key" file || return 1
  actual_fp="$(ssh_tunnel_key_fingerprint "$public_key")" || return 1
  [ "$actual_fp" = "$expected_fp" ] || return 1
  private_check="$(mktemp_file .ssh-private-check)" || return 1
  if ! install -m 0600 "$private_key" "$private_check" \
     || ! private_output="$(ssh-keygen -y -f "$private_check" 2>/dev/null)" \
     || ! private_material="$(ssh_tunnel_public_key_material /dev/stdin <<<"$private_output")"; then
    rm -f "$private_check"
    return 1
  fi
  rm -f "$private_check"
  public_material="$(ssh_tunnel_public_key_material "$public_key")" || return 1
  [ -n "$public_material" ] && [ "$private_material" = "$public_material" ]
}

ssh_tunnel_user_file_destinations_valid() {
  local user_json="$1" linux_user account_id expected_uid expected_fp marker auth_file actual_fp path
  linux_user="$(jq -r .linux_user <<<"$user_json")"
  account_id="$(jq -r .account_id <<<"$user_json")"
  expected_uid="$(jq -r .uid <<<"$user_json")"
  expected_fp="$(jq -r .key_fingerprint <<<"$user_json")"
  marker="$(ssh_tunnel_account_marker_file "$linux_user")"
  auth_file="$(ssh_tunnel_authorized_key_file "$linux_user")"
  for path in "$marker" "$auth_file"; do
    if [ -e "$path" ] || [ -L "$path" ]; then
      [ -f "$path" ] && [ ! -L "$path" ] && secure_stat_path "$path" file || return 1
    fi
  done
  if [ -e "$marker" ]; then
    jq -e --arg account_id "$account_id" --arg linux_user "$linux_user" \
      --arg uid "$expected_uid" '
      .ownership=="nobrand-v3" and .account_id==$account_id
      and .linux_user==$linux_user and .uid==($uid|tonumber)
    ' "$marker" >/dev/null 2>&1 || return 1
  fi
  if [ -e "$auth_file" ]; then
    [ -s "$auth_file" ] || return 1
    actual_fp="$(ssh_tunnel_single_key_fingerprint "$auth_file")" || return 1
    [ "$actual_fp" = "$expected_fp" ] || return 1
  fi
}

ssh_tunnel_reconcile_user_files() {
  local user_json="$1" nologin_shell="$2" linux_user account_id expected_uid expected_fp
  local key_dir private_key public_key actual_fp marker auth_file marker_tmp="" auth_tmp=""
  linux_user="$(jq -r .linux_user <<<"$user_json")"
  account_id="$(jq -r .account_id <<<"$user_json")"
  expected_uid="$(jq -r .uid <<<"$user_json")"
  expected_fp="$(jq -r .key_fingerprint <<<"$user_json")"
  key_dir="$(ssh_tunnel_key_dir "$account_id")"
  private_key="${key_dir}/id_ed25519"
  public_key="${private_key}.pub"
  ssh_tunnel_user_key_material_valid "$user_json" || return 1
  ssh_tunnel_user_file_destinations_valid "$user_json" || return 1
  marker="$(ssh_tunnel_account_marker_file "$linux_user")"
  if [ -e "$marker" ] || [ -L "$marker" ]; then
    [ -f "$marker" ] && [ ! -L "$marker" ] \
      && jq -e --arg account_id "$account_id" --arg linux_user "$linux_user" \
        --arg uid "$expected_uid" '
        .ownership=="nobrand-v3" and .account_id==$account_id
        and .linux_user==$linux_user and .uid==($uid|tonumber)
      ' "$marker" >/dev/null 2>&1 || return 1
  else
    marker_tmp="$(mktemp_file .account-marker)" || return 1
    jq -n --arg account_id "$account_id" --arg linux_user "$linux_user" --arg uid "$expected_uid" '
      {schema_version:3,ownership:"nobrand-v3",account_id:$account_id,
       linux_user:$linux_user,uid:($uid|tonumber)}
    ' >"$marker_tmp" \
      && nb_atomic_install_file "$marker_tmp" "$marker" 0600 || {
        rm -f "$marker_tmp"
        return 1
      }
    rm -f "$marker_tmp"
  fi
  chmod 0600 "$marker" || return 1
  auth_file="$(ssh_tunnel_authorized_key_file "$linux_user")"
  if [ -e "$auth_file" ] || [ -L "$auth_file" ]; then
    [ -f "$auth_file" ] && [ ! -L "$auth_file" ] || return 1
    actual_fp="$(ssh_tunnel_single_key_fingerprint "$auth_file")" || return 1
    [ "$actual_fp" = "$expected_fp" ] || return 1
  fi
  auth_tmp="$(mktemp_file .authorized-key)" || return 1
  if ! ssh_tunnel_authorized_key_line "$public_key" "$nologin_shell" >"$auth_tmp"; then
    rm -f "$auth_tmp"
    return 1
  fi
  if [ ! -e "$auth_file" ] || ! cmp -s "$auth_tmp" "$auth_file"; then
    nb_atomic_install_file "$auth_tmp" "$auth_file" 0644 || {
      rm -f "$auth_tmp"
      return 1
    }
  fi
  rm -f "$auth_tmp"
  chmod 0700 "$key_dir" \
    && chmod 0600 "$private_key" \
    && chmod 0644 "$public_key" "$auth_file" || return 1
  ssh_tunnel_user_identity_valid "$user_json"
}

ssh_tunnel_restore_paths_preflight() {
  local path config_parent
  [ "$NOBRAND_SSH_STATE_DIR" = "${NOBRAND_STATE_DIR}/ssh-tunnel" ] || return 1
  [ "$(dirname "$NOBRAND_SSH_STATE_FILE")" = "$NOBRAND_SSH_STATE_DIR" ] || return 1
  [ "$NOBRAND_SSH_KEYS_DIR" = "${NOBRAND_SSH_STATE_DIR}/keys" ] || return 1
  [ "$NOBRAND_SSH_WATCHDOG_DIR" = "${NOBRAND_SSH_STATE_DIR}/watchdog" ] || return 1
  [ "$NOBRAND_SSH_CONFIG_DIR" = "${NOBRAND_CONFIG_DIR}/ssh-tunnel" ] || return 1
  [ "$NOBRAND_SSH_AUTHORIZED_KEYS_DIR" = "${NOBRAND_SSH_CONFIG_DIR}/authorized_keys" ] || return 1
  [ "$NOBRAND_SSH_ACCOUNT_MARKER_DIR" = "${NOBRAND_SSH_CONFIG_DIR}/accounts" ] || return 1
  [ "$NOBRAND_SSH_GROUP_MARKER" = "${NOBRAND_SSH_ACCOUNT_MARKER_DIR}/.group.json" ] || return 1
  nb_assert_safe_nobrand_root "$NOBRAND_SSH_STATE_DIR" NOBRAND_SSH_STATE_DIR >/dev/null || return 1
  nb_assert_safe_nobrand_root "$NOBRAND_SSH_CONFIG_DIR" NOBRAND_SSH_CONFIG_DIR >/dev/null || return 1
  [ -d "$NOBRAND_STATE_DIR" ] && [ ! -L "$NOBRAND_STATE_DIR" ] \
    && secure_stat_path "$NOBRAND_STATE_DIR" dir \
    && [ "$(stat -c '%a' "$NOBRAND_STATE_DIR")" = 700 ] || return 1
  [ -d "$NOBRAND_SSH_STATE_DIR" ] && [ ! -L "$NOBRAND_SSH_STATE_DIR" ] \
    && secure_stat_path "$NOBRAND_SSH_STATE_DIR" dir \
    && [ "$(stat -c '%a' "$NOBRAND_SSH_STATE_DIR")" = 700 ] || return 1
  secure_stat_path "$NOBRAND_SSH_STATE_FILE" file \
    && [ "$(stat -c '%a' "$NOBRAND_SSH_STATE_FILE")" = 600 ] || return 1
  [ -d "$NOBRAND_SSH_KEYS_DIR" ] && [ ! -L "$NOBRAND_SSH_KEYS_DIR" ] \
    && secure_stat_path "$NOBRAND_SSH_KEYS_DIR" dir \
    && [ "$(stat -c '%a' "$NOBRAND_SSH_KEYS_DIR")" = 700 ] || return 1
  config_parent="$(dirname "$NOBRAND_CONFIG_DIR")"
  [ -d "$config_parent" ] && [ ! -L "$config_parent" ] \
    && secure_stat_path "$config_parent" dir || return 1
  for path in "$NOBRAND_CONFIG_DIR" "$NOBRAND_SSH_CONFIG_DIR" \
    "$NOBRAND_SSH_AUTHORIZED_KEYS_DIR" "$NOBRAND_SSH_ACCOUNT_MARKER_DIR"; do
    if [ -e "$path" ] || [ -L "$path" ]; then
      [ -d "$path" ] && [ ! -L "$path" ] && secure_stat_path "$path" dir || return 1
    fi
  done
  ssh_tunnel_watchdog_directory_preflight || return 1
}

ssh_tunnel_ensure_restore_directories() {
  local path mode
  while IFS='|' read -r path mode; do
    if [ -e "$path" ] || [ -L "$path" ]; then
      [ -d "$path" ] && [ ! -L "$path" ] || return 1
    else
      mkdir "$path" || return 1
    fi
    chmod "$mode" "$path" \
      && chown root:root "$path" 2>/dev/null \
      && secure_stat_path "$path" dir || return 1
  done <<EOF
$NOBRAND_CONFIG_DIR|0711
$NOBRAND_SSH_CONFIG_DIR|0711
$NOBRAND_SSH_AUTHORIZED_KEYS_DIR|0755
$NOBRAND_SSH_ACCOUNT_MARKER_DIR|0700
EOF
}

ssh_tunnel_group_marker_preflight() {
  local expected_gid actual_gid
  if [ ! -e "$NOBRAND_SSH_GROUP_MARKER" ] && [ ! -L "$NOBRAND_SSH_GROUP_MARKER" ]; then
    return 0
  fi
  [ -f "$NOBRAND_SSH_GROUP_MARKER" ] && [ ! -L "$NOBRAND_SSH_GROUP_MARKER" ] \
    && secure_stat_path "$NOBRAND_SSH_GROUP_MARKER" file || return 1
  expected_gid="$(jq -er --arg group "$NOBRAND_SSH_GROUP" '
    select(.schema_version==3 and .ownership=="nobrand-v3" and .group==$group)
    | .gid | select(type=="number" and .>=0 and floor==.)
  ' "$NOBRAND_SSH_GROUP_MARKER" 2>/dev/null)" || return 1
  if _has_group "$NOBRAND_SSH_GROUP"; then
    actual_gid="$(getent group "$NOBRAND_SSH_GROUP" 2>/dev/null | awk -F: '{print $3}')"
    [ "$actual_gid" = "$expected_gid" ]
  else
    ! getent group "$expected_gid" >/dev/null 2>&1
  fi
}

ssh_tunnel_reconcile_group_marker() {
  local marker_tmp="" gid
  _has_group "$NOBRAND_SSH_GROUP" || return 1
  if [ -e "$NOBRAND_SSH_GROUP_MARKER" ] || [ -L "$NOBRAND_SSH_GROUP_MARKER" ]; then
    ssh_tunnel_group_marker_preflight || return 1
    chmod 0600 "$NOBRAND_SSH_GROUP_MARKER"
    return $?
  fi
  gid="$(getent group "$NOBRAND_SSH_GROUP" 2>/dev/null | awk -F: '{print $3}')"
  [[ "$gid" =~ ^[0-9]+$ ]] || return 1
  marker_tmp="$(mktemp_file .ssh-group-marker)" || return 1
  jq -n --arg group "$NOBRAND_SSH_GROUP" --arg gid "$gid" '
    {schema_version:3,ownership:"nobrand-v3",group:$group,gid:($gid|tonumber)}
  ' >"$marker_tmp" \
    && nb_atomic_install_file "$marker_tmp" "$NOBRAND_SSH_GROUP_MARKER" 0600 || {
      rm -f "$marker_tmp"
      return 1
    }
  rm -f "$marker_tmp"
  ssh_tunnel_group_identity_valid || return 1
  chmod 0600 "$NOBRAND_SSH_GROUP_MARKER"
}

ssh_tunnel_add_user_internal() {
  local label="$1" account_id linux_user nologin_shell key_dir private_key public_key
  local fingerprint uid user_json state_tmp marker_tmp auth_tmp created_user=0
  ssh_tunnel_watchdog_mutation_preflight || return $?
  ssh_tunnel_valid_label "$label" || die 'SSH Tunnel 用户标签必须为 1-64 字节且不能含控制字符或 |'
  ssh_tunnel_resolve_user_json "$label" >/dev/null 2>&1 && die "SSH Tunnel 用户已存在: $label"
  account_id="$(ssh_tunnel_generate_account_id)" || return 1
  linux_user="$(ssh_tunnel_linux_username "$label" "$account_id")"
  nologin_shell="$(ssh_tunnel_nologin_shell)" || die '找不到系统 nologin shell'
  ! _has_user "$linux_user" || die "Linux 用户名冲突: $linux_user"
  key_dir="$(ssh_tunnel_key_dir "$account_id")"
  private_key="${key_dir}/id_ed25519"
  public_key="${private_key}.pub"
  mkdir -p "$key_dir" "$NOBRAND_SSH_AUTHORIZED_KEYS_DIR" "$NOBRAND_SSH_ACCOUNT_MARKER_DIR" || return 1
  chmod 0700 "$key_dir" "$NOBRAND_SSH_ACCOUNT_MARKER_DIR" || return 1
  chmod 0755 "$NOBRAND_SSH_AUTHORIZED_KEYS_DIR" || return 1
  ssh-keygen -q -t ed25519 -N '' -C "nobrand:${account_id}" -f "$private_key" || {
    rm -rf -- "$key_dir"
    return 1
  }
  chmod 0600 "$private_key" && chmod 0644 "$public_key" || {
    rm -rf -- "$key_dir"
    return 1
  }
  fingerprint="$(ssh_tunnel_key_fingerprint "$public_key")" || {
    rm -rf -- "$key_dir"
    return 1
  }
  ssh_tunnel_create_linux_user "$linux_user" "$account_id" "$nologin_shell" || {
    rm -rf -- "$key_dir"
    return 1
  }
  created_user=1
  uid="$(id -u "$linux_user")" || {
    ssh_tunnel_delete_linux_user "$linux_user" >/dev/null 2>&1 || true
    rm -rf -- "$key_dir"
    return 1
  }
  user_json="$(ssh_tunnel_user_json "$account_id" "$label" "$linux_user" "$uid" "$fingerprint")"
  auth_tmp="$(mktemp_file .authorized-key)" || {
    ssh_tunnel_delete_linux_user "$linux_user" >/dev/null 2>&1 || true
    rm -rf -- "$key_dir"
    return 1
  }
  marker_tmp="$(mktemp_file .account-marker)" || {
    rm -f "$auth_tmp"
    ssh_tunnel_delete_linux_user "$linux_user" >/dev/null 2>&1 || true
    rm -rf -- "$key_dir"
    return 1
  }
  state_tmp="$(mktemp_file .ssh-state)" || {
    rm -f "$auth_tmp" "$marker_tmp"
    ssh_tunnel_delete_linux_user "$linux_user" >/dev/null 2>&1 || true
    rm -rf -- "$key_dir"
    return 1
  }
  ssh_tunnel_authorized_key_line "$public_key" "$nologin_shell" >"$auth_tmp" \
    && jq -n --arg account_id "$account_id" --arg linux_user "$linux_user" --arg uid "$uid" \
      '{schema_version:3,ownership:"nobrand-v3",account_id:$account_id,linux_user:$linux_user,uid:($uid|tonumber)}' \
      >"$marker_tmp" \
    && jq --argjson user "$user_json" --arg updated "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      '.users += [$user] | .updated_at=$updated' "$NOBRAND_SSH_STATE_FILE" >"$state_tmp" \
    && nb_atomic_install_file "$auth_tmp" "$(ssh_tunnel_authorized_key_file "$linux_user")" 0644 \
    && nb_atomic_install_file "$marker_tmp" "$(ssh_tunnel_account_marker_file "$linux_user")" 0600 \
    && nb_atomic_install_file "$state_tmp" "$NOBRAND_SSH_STATE_FILE" 0600 \
    || {
      rm -f "$auth_tmp" "$marker_tmp" "$state_tmp" \
        "$(ssh_tunnel_authorized_key_file "$linux_user")" \
        "$(ssh_tunnel_account_marker_file "$linux_user")"
      [ "$created_user" -ne 1 ] || ssh_tunnel_delete_linux_user "$linux_user" >/dev/null 2>&1 || true
      find "$key_dir" -mindepth 1 -maxdepth 1 -delete 2>/dev/null || true
      rmdir "$key_dir" 2>/dev/null || true
      return 1
    }
  rm -f "$auth_tmp" "$marker_tmp" "$state_tmp"
  printf '%s' "$account_id"
}

ssh_tunnel_rotate_user_key() {
  local selector="${1:-}" user_json account_id linux_user nologin_shell key_dir new_private
  local new_public new_fp auth_tmp state_tmp snapshot
  ssh_tunnel_watchdog_mutation_preflight || return $?
  user_json="$(ssh_tunnel_resolve_user_json "$selector")" || die '找不到唯一 SSH Tunnel 用户'
  ssh_tunnel_user_identity_valid "$user_json" || die 'SSH Tunnel 用户身份不匹配，拒绝轮换'
  account_id="$(jq -r .account_id <<<"$user_json")"
  linux_user="$(jq -r .linux_user <<<"$user_json")"
  nologin_shell="$(ssh_tunnel_nologin_shell)" || return 1
  key_dir="$(ssh_tunnel_key_dir "$account_id")"
  new_private="$(mktemp "${key_dir}/id_ed25519.new.XXXXXX")" || return 1
  rm -f "$new_private"
  ssh-keygen -q -t ed25519 -N '' -C "nobrand:${account_id}" -f "$new_private" || {
    rm -f "$new_private" "${new_private}.pub"
    return 1
  }
  new_public="${new_private}.pub"
  chmod 0600 "$new_private" && chmod 0644 "$new_public" || {
    rm -f "$new_private" "$new_public"
    return 1
  }
  new_fp="$(ssh_tunnel_key_fingerprint "$new_public")" || {
    rm -f "$new_private" "$new_public"
    return 1
  }
  auth_tmp="$(mktemp_file .authorized-key)" || {
    rm -f "$new_private" "$new_public"
    return 1
  }
  state_tmp="$(mktemp_file .ssh-state)" || {
    rm -f "$new_private" "$new_public" "$auth_tmp"
    return 1
  }
  snapshot="$(mktemp_dir)" || {
    rm -f "$new_private" "$new_public" "$auth_tmp" "$state_tmp"
    return 1
  }
  cp -a "$key_dir/id_ed25519" "$key_dir/id_ed25519.pub" \
    "$(ssh_tunnel_authorized_key_file "$linux_user")" "$NOBRAND_SSH_STATE_FILE" "$snapshot/" || {
      rm -f "$new_private" "$new_public" "$auth_tmp" "$state_tmp"
      rm -rf -- "$snapshot"
      return 1
    }
  ssh_tunnel_authorized_key_line "$new_public" "$nologin_shell" >"$auth_tmp" \
    && jq --arg account_id "$account_id" --arg fingerprint "$new_fp" \
      --arg updated "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      '(.users[] | select(.account_id==$account_id)).key_fingerprint=$fingerprint | .updated_at=$updated' \
      "$NOBRAND_SSH_STATE_FILE" >"$state_tmp" \
    && nb_atomic_install_file "$new_private" "$key_dir/id_ed25519" 0600 \
    && nb_atomic_install_file "$new_public" "$key_dir/id_ed25519.pub" 0644 \
    && nb_atomic_install_file "$auth_tmp" "$(ssh_tunnel_authorized_key_file "$linux_user")" 0644 \
    && nb_atomic_install_file "$state_tmp" "$NOBRAND_SSH_STATE_FILE" 0600 \
    || {
      cp -a "$snapshot/id_ed25519" "$key_dir/id_ed25519" 2>/dev/null || true
      cp -a "$snapshot/id_ed25519.pub" "$key_dir/id_ed25519.pub" 2>/dev/null || true
      cp -a "$snapshot/$linux_user" "$(ssh_tunnel_authorized_key_file "$linux_user")" 2>/dev/null || true
      cp -a "$snapshot/state.json" "$NOBRAND_SSH_STATE_FILE" 2>/dev/null || true
      rm -f "$new_private" "$new_public" "$auth_tmp" "$state_tmp"
      rm -rf -- "$snapshot"
      return 1
    }
  rm -f "$new_private" "$new_public" "$auth_tmp" "$state_tmp"
  rm -rf -- "$snapshot"
}

ssh_tunnel_delete_user_internal() {
  local selector="${1:-}" user_json account_id linux_user uid auth_file state_tmp snapshot nologin_shell
  ssh_tunnel_watchdog_mutation_preflight || return $?
  user_json="$(ssh_tunnel_resolve_user_json "$selector")" || die '找不到唯一 SSH Tunnel 用户'
  ssh_tunnel_user_identity_valid "$user_json" || die 'SSH Tunnel 用户身份不匹配，拒绝删除'
  account_id="$(jq -r .account_id <<<"$user_json")"
  linux_user="$(jq -r .linux_user <<<"$user_json")"
  uid="$(jq -r .uid <<<"$user_json")"
  auth_file="$(ssh_tunnel_authorized_key_file "$linux_user")"
  state_tmp="$(mktemp_file .ssh-state)" || return 1
  snapshot="$(mktemp_dir)" || { rm -f "$state_tmp"; return 1; }
  cp -a "$auth_file" "$NOBRAND_SSH_STATE_FILE" "$snapshot/" || {
    rm -f "$state_tmp"
    rm -rf -- "$snapshot"
    return 1
  }
  jq --arg account_id "$account_id" --arg updated "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '.users |= map(select(.account_id!=$account_id)) | .updated_at=$updated' \
    "$NOBRAND_SSH_STATE_FILE" >"$state_tmp" || {
      rm -f "$state_tmp"
      rm -rf -- "$snapshot"
      return 1
    }
  rm -f "$auth_file"
  pkill -KILL -u "$uid" 2>/dev/null || true
  if ! ssh_tunnel_delete_linux_user "$linux_user"; then
    cp -a "$snapshot/$linux_user" "$auth_file" 2>/dev/null || true
    rm -f "$state_tmp"
    rm -rf -- "$snapshot"
    return 1
  fi
  if ! nb_atomic_install_file "$state_tmp" "$NOBRAND_SSH_STATE_FILE" 0600; then
    nologin_shell="$(ssh_tunnel_nologin_shell 2>/dev/null || true)"
    if [ -n "$nologin_shell" ] \
       && ssh_tunnel_create_linux_user_with_uid "$linux_user" "$account_id" "$nologin_shell" "$uid" \
       && cp -a "$snapshot/$linux_user" "$auth_file"; then
      warn 'SSH Tunnel 状态提交失败；Linux 用户与 authorized_keys 已回滚'
    else
      warn 'SSH Tunnel 状态提交失败且 Linux 用户回滚失败；authorized_keys 保持撤销，所有权标记与密钥保留供恢复'
    fi
    rm -f "$state_tmp"
    rm -rf -- "$snapshot"
    return 1
  fi
  rm -f "$(ssh_tunnel_account_marker_file "$linux_user")" "$state_tmp"
  find "$(ssh_tunnel_key_dir "$account_id")" -mindepth 1 -maxdepth 1 -delete 2>/dev/null || true
  rmdir "$(ssh_tunnel_key_dir "$account_id")" 2>/dev/null || true
  rm -rf -- "$snapshot"
}

ssh_tunnel_dropin_supported() {
  [ "$NOBRAND_SSH_CONFIG_DROPIN" = /etc/ssh/sshd_config.d/90-nobrand-ssh-tunnel.conf ] || return 1
  awk '
    /^[[:space:]]*#/ {next}
    tolower($1)=="match" {exit}
    tolower($1)=="include" {
      for (i=2;i<=NF;i++) if ($i=="/etc/ssh/sshd_config.d/*.conf") found=1
    }
    END {exit(found?0:1)}
  ' "$NOBRAND_SSH_CONFIG_MAIN"
}

ssh_tunnel_state_proves_config_target() {
  local strategy="$1" target="$2" allowed_policy_state="${3:-true}" actual_policy_state
  secure_stat_path "$NOBRAND_SSH_STATE_FILE" file || return 1
  ssh_tunnel_state_identity_valid || return 1
  [ "$(ssh_tunnel_state_field config_strategy 2>/dev/null || true)" = "$strategy" ] \
    && [ "$(ssh_tunnel_state_field managed_config_path 2>/dev/null || true)" = "$target" ] \
    && [ -z "$(ssh_tunnel_state_field pending_operation 2>/dev/null || true)" ] \
    && [ -z "$(ssh_tunnel_state_field pending_watchdog_token 2>/dev/null || true)" ] \
    && [ -z "$(ssh_tunnel_state_field pending_watchdog_pid 2>/dev/null || true)" ] \
    && [ -z "$(ssh_tunnel_state_field pending_origin_connection 2>/dev/null || true)" ] \
    || return 1
  actual_policy_state="$(ssh_tunnel_state_field policy_applied 2>/dev/null || true)"
  case "$allowed_policy_state" in
    any) [ "$actual_policy_state" = true ] || [ "$actual_policy_state" = false ] ;;
    true|false) [ "$actual_policy_state" = "$allowed_policy_state" ] ;;
    *) return 1 ;;
  esac
}

ssh_tunnel_existing_dropin_owned() {
  local target="$1" expected_policy="$2" allowed_policy_state="${3:-true}"
  [ "$target" = "$NOBRAND_SSH_CONFIG_DROPIN" ] || return 1
  [ -f "$target" ] && [ ! -L "$target" ] || return 1
  secure_stat_path "$target" file || return 1
  ssh_tunnel_state_proves_config_target dropin "$target" "$allowed_policy_state" \
    && cmp -s "$expected_policy" "$target"
}

ssh_tunnel_marker_block_matches_policy() {
  local target="$1" expected_policy="$2" extracted
  extracted="$(mktemp_file .ssh-marker-policy)" || return 1
  if ! awk -v begin="$NOBRAND_SSH_BLOCK_BEGIN" -v end="$NOBRAND_SSH_BLOCK_END" '
    $0==begin {
      if (inside || seen_begin) {bad=1; exit}
      inside=1
      seen_begin=1
      next
    }
    $0==end {
      if (!inside || seen_end) {bad=1; exit}
      inside=0
      seen_end=1
      next
    }
    inside {print}
    END {if (bad || inside || seen_begin!=1 || seen_end!=1) exit 2}
  ' "$target" >"$extracted"; then
    rm -f "$extracted"
    return 1
  fi
  if ! cmp -s "$expected_policy" "$extracted"; then
    rm -f "$extracted"
    return 1
  fi
  rm -f "$extracted"
}

ssh_tunnel_existing_marker_block_owned() {
  local target="$1" expected_policy="$2" allowed_policy_state="${3:-true}"
  [ "$target" = "$NOBRAND_SSH_CONFIG_MAIN" ] || return 1
  [ -f "$target" ] && [ ! -L "$target" ] || return 1
  secure_stat_path "$target" file || return 1
  ssh_tunnel_state_proves_config_target marker-block "$target" "$allowed_policy_state" \
    && ssh_tunnel_marker_block_matches_policy "$target" "$expected_policy"
}

ssh_tunnel_apply_target_preflight() {
  local strategy="$1" target="$2" policy="$3" operation="$4"
  case "$strategy" in
    dropin)
      if [ ! -e "$target" ] && [ ! -L "$target" ]; then
        return 0
      fi
      # A fixed-name drop-in is not an ownership boundary by itself. During a
      # restore, accept only the exact policy already proved by current state;
      # a fresh install must require an absent target.
      [ "$operation" = restore ] \
        && ssh_tunnel_existing_dropin_owned "$target" "$policy" any
      ;;
    marker-block)
      [ "$target" = "$NOBRAND_SSH_CONFIG_MAIN" ] \
        && [ -f "$target" ] && [ ! -L "$target" ] \
        && secure_stat_path "$target" file || return 1
      if ! grep -Fqx "$NOBRAND_SSH_BLOCK_BEGIN" "$target" 2>/dev/null \
         && ! grep -Fqx "$NOBRAND_SSH_BLOCK_END" "$target" 2>/dev/null; then
        return 0
      fi
      [ "$operation" = restore ] \
        && ssh_tunnel_existing_marker_block_owned "$target" "$policy" any
      ;;
    *) return 1 ;;
  esac
}

ssh_tunnel_strip_marker_block() {
  local source="$1" output="$2"
  awk -v begin="$NOBRAND_SSH_BLOCK_BEGIN" -v end="$NOBRAND_SSH_BLOCK_END" '
    $0==begin {inside=1; next}
    $0==end {if (!inside) exit 2; inside=0; next}
    !inside {print}
    END {if (inside) exit 2}
  ' "$source" >"$output"
}

ssh_tunnel_build_main_candidate() {
  local policy="$1" output="$2" stripped
  stripped="$(mktemp_file .sshd-main)" || return 1
  if ! ssh_tunnel_strip_marker_block "$NOBRAND_SSH_CONFIG_MAIN" "$stripped"; then
    rm -f "$stripped"
    return 1
  fi
  if ! {
    cat "$stripped"
    printf '\n%s\n' "$NOBRAND_SSH_BLOCK_BEGIN"
    cat "$policy"
    printf '%s\n' "$NOBRAND_SSH_BLOCK_END"
  } >"$output"; then
    rm -f "$stripped"
    return 1
  fi
  rm -f "$stripped"
}

ssh_tunnel_build_dropin_removal_candidate() {
  local output="$1" candidate_root="$2" source_dir source_file candidate_dir replacement
  source_dir="$(dirname "$NOBRAND_SSH_CONFIG_DROPIN")"
  candidate_dir="${candidate_root}/sshd_config.d"
  replacement="${candidate_dir}/*.conf"
  mkdir -p "$candidate_dir" || return 1
  while IFS= read -r source_file; do
    [ "$source_file" = "$NOBRAND_SSH_CONFIG_DROPIN" ] && continue
    cp -a "$source_file" "$candidate_dir/" || return 1
  done < <(find "$source_dir" -maxdepth 1 -type f -name '*.conf' -print 2>/dev/null | LC_ALL=C sort)
  awk -v original='/etc/ssh/sshd_config.d/*.conf' -v replacement="$replacement" '
    {
      if (tolower($1)=="include") {
        changed=0
        for (i=2;i<=NF;i++) if ($i==original) {$i=replacement; changed=1}
        if (changed) {
          line=$1
          for (i=2;i<=NF;i++) line=line " " $i
          print line
          next
        }
      }
      print
    }
  ' "$NOBRAND_SSH_CONFIG_MAIN" >"$output"
}

ssh_tunnel_detect_service() {
  if [ -d /run/systemd/system ] && command -v systemctl >/dev/null 2>&1; then
    systemctl status ssh.service >/dev/null 2>&1 && { printf 'systemd|ssh.service'; return 0; }
    systemctl status sshd.service >/dev/null 2>&1 && { printf 'systemd|sshd.service'; return 0; }
  fi
  if command -v rc-service >/dev/null 2>&1 && rc-service sshd status >/dev/null 2>&1; then
    printf 'openrc|sshd'
    return 0
  fi
  local pid_file pid
  for pid_file in /run/sshd.pid /var/run/sshd.pid; do
    [ -s "$pid_file" ] || continue
    pid="$(cat "$pid_file" 2>/dev/null || true)"
    [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null \
      && { printf 'sighup|%s' "$pid"; return 0; }
  done
  return 1
}

ssh_tunnel_reload() {
  local service kind name
  service="$(ssh_tunnel_detect_service)" || return 1
  kind="${service%%|*}"
  name="${service#*|}"
  case "$kind" in
    systemd) systemctl reload "$name" ;;
    openrc) rc-service "$name" reload ;;
    sighup) kill -HUP "$name" ;;
    *) return 1 ;;
  esac
}

ssh_tunnel_watchdog_token_valid() {
  local token="${1:-}"
  [ "$token" = disabled ] || [[ "$token" =~ ^([0-9a-f]{16}|[0-9a-f]{32})$ ]]
}

ssh_tunnel_watchdog_pid_valid() {
  local pid="${1:-}"
  [ -z "$pid" ] || [[ "$pid" =~ ^[0-9]+$ ]]
}

ssh_tunnel_pending_operation_valid() {
  case "${1:-}" in install|restore|uninstall|unified-uninstall) return 0 ;; esac
  return 1
}

ssh_tunnel_watchdog_pid_matches() {
  local token="$1" pid="${2:-}" script arg
  ssh_tunnel_watchdog_token_valid "$token" && [ "$token" != disabled ] || return 1
  [[ "$pid" =~ ^[0-9]+$ ]] && [ -r "/proc/${pid}/cmdline" ] || return 1
  script="${NOBRAND_SSH_WATCHDOG_DIR}/${token}.rollback.sh"
  while IFS= read -r -d '' arg; do
    [ "$arg" = "$script" ] && return 0
  done <"/proc/${pid}/cmdline"
  return 1
}

ssh_tunnel_watchdog_stop_owned() {
  local token="$1" pid="${2:-}"
  ssh_tunnel_watchdog_pid_matches "$token" "$pid" || return 0
  kill "$pid" 2>/dev/null || true
}

ssh_tunnel_watchdog_cleanup_artifacts() {
  local token="$1" base script
  ssh_tunnel_watchdog_token_valid "$token" && [ "$token" != disabled ] || return 1
  base="${NOBRAND_SSH_WATCHDOG_DIR}/${token}"
  script="${base}.rollback.sh"
  rm -f "${base}.armed" "${base}.backup" "${base}.backup.absent" \
    "${base}.state.backup" "${base}.state.absent" "$script" \
    "${script}.confirmed" "${script}.cancelled"
}

ssh_tunnel_cleanup_disarmed_watchdogs() {
  local active=""
  if [ ! -e "$NOBRAND_SSH_WATCHDOG_DIR" ] && [ ! -L "$NOBRAND_SSH_WATCHDOG_DIR" ]; then
    return 0
  fi
  ssh_tunnel_watchdog_directory_preflight || return 1
  [ "$(stat -c '%a' "$NOBRAND_SSH_WATCHDOG_DIR")" = 700 ] || return 1
  active="$(find "$NOBRAND_SSH_WATCHDOG_DIR" -mindepth 1 -maxdepth 1 \
    \( -name '*.armed' -o -name '*.running' \) -print -quit)" || return 1
  [ -z "$active" ] || return 1
  find "$NOBRAND_SSH_WATCHDOG_DIR" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
}

ssh_tunnel_watchdog_directory_preflight() {
  [ "$NOBRAND_SSH_WATCHDOG_DIR" = "${NOBRAND_SSH_STATE_DIR}/watchdog" ] || return 1
  nb_assert_safe_nobrand_root "$NOBRAND_SSH_WATCHDOG_DIR" NOBRAND_SSH_WATCHDOG_DIR \
    >/dev/null || return 1
  [ -d "$NOBRAND_SSH_STATE_DIR" ] && [ ! -L "$NOBRAND_SSH_STATE_DIR" ] \
    && secure_stat_path "$NOBRAND_SSH_STATE_DIR" dir || return 1
  if [ -e "$NOBRAND_SSH_WATCHDOG_DIR" ] || [ -L "$NOBRAND_SSH_WATCHDOG_DIR" ]; then
    [ -d "$NOBRAND_SSH_WATCHDOG_DIR" ] && [ ! -L "$NOBRAND_SSH_WATCHDOG_DIR" ] \
      && secure_stat_path "$NOBRAND_SSH_WATCHDOG_DIR" dir || return 1
  fi
}

ssh_tunnel_prepare_watchdog_directory() {
  ssh_tunnel_watchdog_directory_preflight || return 1
  if [ ! -e "$NOBRAND_SSH_WATCHDOG_DIR" ]; then
    mkdir "$NOBRAND_SSH_WATCHDOG_DIR" || return 1
  fi
  chmod 0700 "$NOBRAND_SSH_WATCHDOG_DIR" \
    && chown root:root "$NOBRAND_SSH_WATCHDOG_DIR" 2>/dev/null \
    && secure_stat_path "$NOBRAND_SSH_WATCHDOG_DIR" dir \
    && [ "$(stat -c '%a' "$NOBRAND_SSH_WATCHDOG_DIR")" = 700 ]
}

# The armed/running claim is durable before its tuple can be committed to
# state.json. Treat that on-disk claim as an independent transaction boundary:
# after a manager SIGKILL, no later SSH mutation may race the still-authorized
# rollback and then be overwritten by its older snapshot. Fully disarmed
# leftovers remain eligible for the existing bounded cleanup routine.
ssh_tunnel_watchdog_mutation_preflight() {
  local active=""
  if [ "$NOBRAND_SSH_WATCHDOG_DIR" != "${NOBRAND_SSH_STATE_DIR}/watchdog" ]; then
    warn 'SSH watchdog 目录不在受管命名空间内；拒绝修改 SSH 状态'
    return 75
  fi
  if [ ! -e "$NOBRAND_SSH_WATCHDOG_DIR" ] && [ ! -L "$NOBRAND_SSH_WATCHDOG_DIR" ]; then
    return 0
  fi
  if ! ssh_tunnel_watchdog_directory_preflight \
     || [ "$(stat -c '%a' "$NOBRAND_SSH_WATCHDOG_DIR" 2>/dev/null || true)" != 700 ]; then
    warn 'SSH watchdog 目录的归属或权限无效；拒绝修改 SSH 状态'
    return 75
  fi
  active="$(find "$NOBRAND_SSH_WATCHDOG_DIR" -mindepth 1 -maxdepth 1 \
    \( -name '*.armed' -o -name '*.running' \) -print -quit)" || {
      warn '无法检查 SSH watchdog 操作权；拒绝修改 SSH 状态'
      return 75
    }
  [ -z "$active" ] || {
    warn 'SSH watchdog 回滚操作权尚未解决；拒绝并发修改 SSH 状态'
    return 75
  }
}

ssh_tunnel_watchdog_snapshot_pair_valid() {
  local payload="$1" absent="$2" kind="$3"
  if [ -e "$payload" ] || [ -L "$payload" ]; then
    [ ! -e "$absent" ] && [ ! -L "$absent" ] || return 1
    case "$kind" in
      config)
        if [ -L "$payload" ]; then
          return 0
        fi
        secure_stat_path "$payload" file
        ;;
      state) secure_stat_path "$payload" file ;;
      *) return 1 ;;
    esac
  else
    [ -f "$absent" ] && [ ! -L "$absent" ] \
      && secure_stat_path "$absent" file
  fi
}

ssh_tunnel_watchdog_claim_ready() {
  local token="$1" pid="${2:-}" base script armed artifact
  ssh_tunnel_watchdog_token_valid "$token" && [ "$token" != disabled ] || return 1
  [[ "$pid" =~ ^[0-9]+$ ]] && [ "$((10#$pid))" -gt 1 ] || return 1
  ssh_tunnel_watchdog_directory_preflight || return 1
  [ "$(stat -c '%a' "$NOBRAND_SSH_WATCHDOG_DIR")" = 700 ] || return 1
  base="${NOBRAND_SSH_WATCHDOG_DIR}/${token}"
  script="${base}.rollback.sh"
  armed="${base}.armed"
  [ -f "$script" ] && [ ! -L "$script" ] && [ -x "$script" ] \
    && secure_stat_path "$script" file \
    && [ "$(stat -c '%a' "$script")" = 700 ] || return 1
  [ -f "$armed" ] && [ ! -L "$armed" ] \
    && secure_stat_path "$armed" file \
    && [ "$(stat -c '%a' "$armed")" = 600 ] || return 1
  for artifact in "${script}.running" "${script}.confirmed" "${script}.cancelled"; do
    [ ! -e "$artifact" ] && [ ! -L "$artifact" ] || return 1
  done
  ssh_tunnel_watchdog_snapshot_pair_valid "${base}.backup" "${base}.backup.absent" config \
    && ssh_tunnel_watchdog_snapshot_pair_valid \
      "${base}.state.backup" "${base}.state.absent" state \
    && ssh_tunnel_watchdog_pid_matches "$token" "$pid"
}

ssh_tunnel_write_watchdog_script() {
  local timeout="$1" token_file="$2" script="$3" backup="$4" target="$5"
  local sshd="$6" main_config="$7" kind="$8" name="$9" state_backup="${10}"
  local state_absent="${11}" state_file="${12}"
  printf '#!/usr/bin/env bash\nset -eu\n[ "${NOBRAND_SSH_WATCHDOG_NOW:-0}" = 1 ] || sleep %q\n' \
    "$timeout" || return 1
  # Confirmation and rollback compete for one atomic rename. Only the
  # process that owns the resulting claim file may mutate SSH or state.
  printf 'mv -f -- %q %q 2>/dev/null || exit 0\n' \
    "$token_file" "${script}.running" || return 1
  printf 'if [ -e %q ] || [ -L %q ]; then\n' "$backup" "$backup" || return 1
  printf '  { [ -f %q ] || [ -L %q ]; } || exit 1\n' "$backup" "$backup" || return 1
  printf '  rm -f -- %q\n  cp -a -- %q %q\n' "$target" "$backup" "$target" || return 1
  printf 'elif [ -f %q ] && [ ! -L %q ]; then\n' \
    "${backup}.absent" "${backup}.absent" || return 1
  printf '  rm -f -- %q\nelse\n  exit 1\nfi\n' "$target" || return 1
  printf '%q -t -f %q || exit 1\n' "$sshd" "$main_config" || return 1
  case "$kind" in
    systemd) printf 'systemctl reload %q\n' "$name" || return 1 ;;
    openrc) printf 'rc-service %q reload\n' "$name" || return 1 ;;
    sighup) printf 'kill -HUP %q\n' "$name" || return 1 ;;
    *) return 1 ;;
  esac
  printf 'if [ -f %q ] && [ ! -L %q ]; then\n' \
    "$state_backup" "$state_backup" || return 1
  printf '  rm -f -- %q\n  cp -a -- %q %q\n' \
    "$state_file" "$state_backup" "$state_file" || return 1
  printf 'elif [ -f %q ] && [ ! -L %q ]; then\n' \
    "$state_absent" "$state_absent" || return 1
  printf '  rm -f -- %q\nelse\n  exit 1\nfi\n' "$state_file" || return 1
  printf 'rm -f %q %q %q %q %q %q %q\n' "$token_file" "$backup" \
    "${backup}.absent" "$state_backup" "$state_absent" "$script" \
    "${script}.running" || return 1
}

ssh_tunnel_watchdog_begin() {
  local target="$1" operation="$2" token origin service kind name backup script token_file timeout pid
  local state_backup state_absent sshd artifact ready=0 attempts=0
  ssh_tunnel_pending_operation_valid "$operation" || return 1
  ssh_tunnel_watchdog_mutation_preflight || return $?
  [ "${NOBRAND_SSH_WATCHDOG_DISABLED:-0}" != 1 ] \
    || {
      [ "${MITA_SOURCE_ONLY:-0}" = 1 ] || return 1
      printf 'disabled|||%s' "$operation"
      return 0
    }
  ssh_tunnel_prepare_watchdog_directory || return 1
  token="$(openssl rand -hex 16 2>/dev/null || printf '%08x%08x' "$RANDOM" "$RANDOM")"
  ssh_tunnel_watchdog_token_valid "$token" && [ "$token" != disabled ] || return 1
  origin="${SSH_CONNECTION:-}"
  backup="${NOBRAND_SSH_WATCHDOG_DIR}/${token}.backup"
  state_backup="${NOBRAND_SSH_WATCHDOG_DIR}/${token}.state.backup"
  state_absent="${NOBRAND_SSH_WATCHDOG_DIR}/${token}.state.absent"
  script="${NOBRAND_SSH_WATCHDOG_DIR}/${token}.rollback.sh"
  token_file="${NOBRAND_SSH_WATCHDOG_DIR}/${token}.armed"
  for artifact in "$backup" "${backup}.absent" "$state_backup" "$state_absent" \
    "$script" "$token_file" "${script}.running" "${script}.confirmed" "${script}.cancelled"; do
    [ ! -e "$artifact" ] && [ ! -L "$artifact" ] || return 1
  done
  if [ -e "$target" ] || [ -L "$target" ]; then
    [ -f "$target" ] || [ -L "$target" ] || return 1
    cp -a "$target" "$backup" || {
      ssh_tunnel_watchdog_cleanup_artifacts "$token" >/dev/null 2>&1 || true
      return 1
    }
  elif ! : >"${backup}.absent" || ! chmod 0600 "${backup}.absent"; then
    ssh_tunnel_watchdog_cleanup_artifacts "$token" >/dev/null 2>&1 || true
    return 1
  fi
  if [ -e "$NOBRAND_SSH_STATE_FILE" ] || [ -L "$NOBRAND_SSH_STATE_FILE" ]; then
    [ -f "$NOBRAND_SSH_STATE_FILE" ] && [ ! -L "$NOBRAND_SSH_STATE_FILE" ] || {
      ssh_tunnel_watchdog_cleanup_artifacts "$token" >/dev/null 2>&1 || true
      return 1
    }
    cp -a "$NOBRAND_SSH_STATE_FILE" "$state_backup" || {
      ssh_tunnel_watchdog_cleanup_artifacts "$token" >/dev/null 2>&1 || true
      return 1
    }
  else
    : >"$state_absent" && chmod 0600 "$state_absent" || {
      ssh_tunnel_watchdog_cleanup_artifacts "$token" >/dev/null 2>&1 || true
      return 1
    }
  fi
  service="$(ssh_tunnel_detect_service)" || {
    ssh_tunnel_watchdog_cleanup_artifacts "$token" >/dev/null 2>&1 || true
    return 1
  }
  kind="${service%%|*}"
  name="${service#*|}"
  case "$kind" in systemd|openrc|sighup) ;; *)
    ssh_tunnel_watchdog_cleanup_artifacts "$token" >/dev/null 2>&1 || true
    return 1
    ;;
  esac
  [ -n "$name" ] || {
    ssh_tunnel_watchdog_cleanup_artifacts "$token" >/dev/null 2>&1 || true
    return 1
  }
  sshd="$(ssh_tunnel_sshd_binary)" || {
    ssh_tunnel_watchdog_cleanup_artifacts "$token" >/dev/null 2>&1 || true
    return 1
  }
  timeout="${NOBRAND_SSH_WATCHDOG_TIMEOUT:-180}"
  [[ "$timeout" =~ ^[0-9]+$ ]] && [ "$timeout" -ge 30 ] || timeout=180
  if ! ssh_tunnel_write_watchdog_script "$timeout" "$token_file" "$script" "$backup" \
    "$target" "$sshd" "$NOBRAND_SSH_CONFIG_MAIN" "$kind" "$name" \
    "$state_backup" "$state_absent" "$NOBRAND_SSH_STATE_FILE" >"$script"; then
    ssh_tunnel_watchdog_cleanup_artifacts "$token" >/dev/null 2>&1 || true
    return 1
  fi
  chmod 0700 "$script" || {
    ssh_tunnel_watchdog_cleanup_artifacts "$token" >/dev/null 2>&1 || true
    return 1
  }
  : >"$token_file" && chmod 0600 "$token_file" || {
    ssh_tunnel_watchdog_cleanup_artifacts "$token" >/dev/null 2>&1 || true
    return 1
  }
  # The watchdog intentionally outlives this manager process while a fresh
  # administrator connection confirms the SSH policy. Do not let it inherit
  # the lifecycle flock, otherwise that confirmation process cannot start.
  NOBRAND_SSH_WATCHDOG_NOW=0 nohup "$script" 7>&- >/dev/null 2>&1 &
  pid=$!
  while [ "$attempts" -lt 100 ]; do
    if ssh_tunnel_watchdog_claim_ready "$token" "$pid"; then
      ready=1
      break
    fi
    kill -0 "$pid" 2>/dev/null || break
    attempts=$((attempts + 1))
    sleep 0.01
  done
  if [ "$ready" -ne 1 ] || ! ssh_tunnel_watchdog_claim_ready "$token" "$pid"; then
    # Claim cancellation is itself atomic. If rollback already owns the
    # artifacts, leave them untouched and report failure.
    ssh_tunnel_watchdog_cancel "$token" "$pid" >/dev/null 2>&1 || true
    return 1
  fi
  printf '%s|%s|%s|%s' "$token" "$pid" "$origin" "$operation"
}

ssh_tunnel_watchdog_cancel() {
  local token="$1" pid="${2:-}" base script cancelled
  [ "$token" != disabled ] || return 0
  ssh_tunnel_watchdog_token_valid "$token" || return 1
  ssh_tunnel_watchdog_pid_valid "$pid" || return 1
  base="${NOBRAND_SSH_WATCHDOG_DIR}/${token}"
  script="${base}.rollback.sh"
  cancelled="${script}.cancelled"
  if ! mv -f -- "${base}.armed" "$cancelled" 2>/dev/null; then
    # A running rollback or a confirmation owns these artifacts now. Never
    # remove its snapshots or terminate its process.
    [ ! -e "${script}.running" ] && [ ! -e "${script}.confirmed" ] \
      && [ ! -e "$cancelled" ] && [ ! -e "$script" ] && return 0
    return 1
  fi
  ssh_tunnel_watchdog_stop_owned "$token" "$pid"
  ssh_tunnel_watchdog_cleanup_artifacts "$token"
}

ssh_tunnel_watchdog_rollback_now() {
  local token="$1" pid="${2:-}" base script rc=0
  [ "$token" != disabled ] || return 0
  ssh_tunnel_watchdog_token_valid "$token" || return 1
  ssh_tunnel_watchdog_pid_valid "$pid" || return 1
  base="${NOBRAND_SSH_WATCHDOG_DIR}/${token}"
  script="${base}.rollback.sh"
  [ -x "$script" ] || return 1
  # Run the same atomic claimant synchronously before considering process
  # termination. If the sleeping watchdog already won, leave it untouched.
  NOBRAND_SSH_WATCHDOG_NOW=1 bash "$script" || rc=$?
  if [ "$rc" -eq 0 ] && [ ! -e "${script}.running" ] \
     && [ ! -e "${script}.confirmed" ] && [ ! -e "${base}.armed" ]; then
    ssh_tunnel_watchdog_stop_owned "$token" "$pid"
    return 0
  fi
  return 1
}

ssh_tunnel_watchdog_prompt() {
  local token="$1"
  t "SSH policy 已安全 reload；请在 ${NOBRAND_SSH_WATCHDOG_TIMEOUT:-180} 秒内通过全新管理员 SSH 连接运行：" \
    "SSH policy safely reloaded; from a brand-new administrator SSH connection, run within ${NOBRAND_SSH_WATCHDOG_TIMEOUT:-180} seconds:"
  printf '  nobrand ssh confirm-admin --token %s\n' "$token"
}

ssh_tunnel_apply_policy() {
  local validation_user="$1" requested_operation="${2:-install}"
  local policy strategy target candidate watchdog token pid origin operation state_tmp
  ssh_tunnel_watchdog_mutation_preflight || return $?
  policy="$(mktemp_file .ssh-policy)" || return 1
  candidate="$(mktemp_file .sshd-candidate)" || { rm -f "$policy"; return 1; }
  ssh_tunnel_generate_policy "$policy" || { rm -f "$policy" "$candidate"; return 1; }
  if ssh_tunnel_dropin_supported; then
    strategy=dropin
    target="$NOBRAND_SSH_CONFIG_DROPIN"
  else
    strategy="marker-block"
    target="$NOBRAND_SSH_CONFIG_MAIN"
  fi
  if ! ssh_tunnel_apply_target_preflight "$strategy" "$target" "$policy" \
    "$requested_operation"; then
    rm -f "$policy" "$candidate"
    warn 'SSH 配置目标已存在但无法证明归属，或其符号链接拓扑无法安全保留；拒绝修改'
    return 1
  fi
  ssh_tunnel_build_main_candidate "$policy" "$candidate" \
    || { rm -f "$policy" "$candidate"; return 1; }
  ssh_tunnel_sshd_test "$candidate" || {
    rm -f "$policy" "$candidate"
    warn 'SSH 候选配置语法校验失败'
    return 1
  }
  ssh_tunnel_effective_policy_valid "$candidate" "$validation_user" \
    || {
      rm -f "$policy" "$candidate"
      warn 'SSH 候选配置的生效策略校验失败'
      return 1
    }
  state_tmp="$(mktemp_file .ssh-state)" \
    || { rm -f "$policy" "$candidate"; return 1; }
  watchdog="$(ssh_tunnel_watchdog_begin "$target" "$requested_operation")" || {
    rm -f "$policy" "$candidate" "$state_tmp"
    return 1
  }
  IFS='|' read -r token pid origin operation <<<"$watchdog"
  if ! jq --arg strategy "$strategy" --arg path "$target" --arg token "$token" \
    --arg pid "$pid" --arg origin "$origin" --arg operation "$operation" \
    --arg updated "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
    .config_strategy=$strategy | .managed_config_path=$path | .policy_applied=true
    | .pending_operation=$operation | .pending_watchdog_token=$token
    | .pending_watchdog_pid=$pid | .pending_origin_connection=$origin | .updated_at=$updated
  ' "$NOBRAND_SSH_STATE_FILE" >"$state_tmp"; then
    rm -f "$policy" "$candidate" "$state_tmp"
    if ! ssh_tunnel_watchdog_cancel "$token" "$pid"; then
      warn 'SSH watchdog 已取得操作权或无法安全取消；状态与回滚快照已保留'
      return 75
    fi
    return 1
  fi
  mkdir -p "$(dirname "$target")" || {
    rm -f "$policy" "$candidate" "$state_tmp"
    if ! ssh_tunnel_watchdog_cancel "$token" "$pid"; then
      warn 'SSH watchdog 已取得操作权或无法安全取消；状态与回滚快照已保留'
      return 75
    fi
    return 1
  }
  if [ "$strategy" = dropin ]; then
    nb_atomic_install_file "$policy" "$target" 0600 || {
      rm -f "$policy" "$candidate" "$state_tmp"
      if ! ssh_tunnel_watchdog_rollback_now "$token" "$pid"; then
        warn 'SSH watchdog 已取得回滚权或立即回滚未完成；状态与快照已保留'
        return 75
      fi
      return 1
    }
  else
    nb_atomic_install_file "$candidate" "$target" 0600 || {
      rm -f "$policy" "$candidate" "$state_tmp"
      if ! ssh_tunnel_watchdog_rollback_now "$token" "$pid"; then
        warn 'SSH watchdog 已取得回滚权或立即回滚未完成；状态与快照已保留'
        return 75
      fi
      return 1
    }
  fi
  if ! ssh_tunnel_sshd_test "$NOBRAND_SSH_CONFIG_MAIN" \
     || ! ssh_tunnel_effective_policy_valid "$NOBRAND_SSH_CONFIG_MAIN" "$validation_user" \
     || ! ssh_tunnel_reload; then
    warn 'SSH 策略应用或重新加载失败，正在立即回滚'
    rm -f "$policy" "$candidate" "$state_tmp"
    if ! ssh_tunnel_watchdog_rollback_now "$token" "$pid"; then
      warn 'SSH watchdog 已取得回滚权或立即回滚未完成；状态与快照已保留'
      return 75
    fi
    return 1
  fi
  if [ "$token" != disabled ] \
     && ! ssh_tunnel_watchdog_claim_ready "$token" "$pid"; then
    rm -f "$policy" "$candidate" "$state_tmp"
    warn 'SSH watchdog 已取得回滚权或回滚事务已失效；拒绝提交待确认状态'
    return 75
  fi
  if ! nb_atomic_install_file "$state_tmp" "$NOBRAND_SSH_STATE_FILE" 0600; then
    rm -f "$policy" "$candidate" "$state_tmp"
    if ! ssh_tunnel_watchdog_rollback_now "$token" "$pid"; then
      warn 'SSH watchdog 已取得回滚权或立即回滚未完成；状态与快照已保留'
      return 75
    fi
    return 1
  fi
  rm -f "$state_tmp" "$policy" "$candidate"
  if [ "$token" = disabled ]; then
    if ! ssh_tunnel_confirm_admin disabled; then
      warn 'SSH 策略已写入但待确认状态未能完成；已保留状态供安全重试'
      return 75
    fi
  else
    if ! ssh_tunnel_watchdog_prompt "$token"; then
      warn 'SSH 策略仍在等待确认，但确认提示输出失败；已保留 watchdog 状态'
      return 75
    fi
  fi
}

ssh_tunnel_remove_policy() {
  local requested_operation="${1:-uninstall}" strategy target candidate candidate_root="" policy=""
  local watchdog token pid origin operation state_tmp managed_path
  ssh_tunnel_watchdog_mutation_preflight || return $?
  managed_path="$(ssh_tunnel_state_field managed_config_path)" || return 1
  strategy="$(ssh_tunnel_state_field config_strategy)" || return 1
  candidate_root="$(mktemp_dir)" || return 1
  candidate="${candidate_root}/sshd_config"
  policy="$(mktemp_file .ssh-policy)" || {
    rm -rf -- "$candidate_root"
    return 1
  }
  case "$strategy" in
    dropin)
      if [ "$managed_path" != "$NOBRAND_SSH_CONFIG_DROPIN" ] \
         || ! ssh_tunnel_generate_policy "$policy" \
         || ! ssh_tunnel_existing_dropin_owned "$managed_path" "$policy"; then
        rm -f "$policy"
        rm -rf -- "$candidate_root"
        warn 'SSH 受管 drop-in 缺失、已被替换或无法证明归属；拒绝删除'
        return 1
      fi
      if ! ssh_tunnel_build_dropin_removal_candidate "$candidate" "$candidate_root"; then
        rm -f "$policy"
        rm -rf -- "$candidate_root"
        return 1
      fi
      target="$managed_path"
      ;;
    marker-block)
      if [ "$managed_path" != "$NOBRAND_SSH_CONFIG_MAIN" ] \
         || ! ssh_tunnel_generate_policy "$policy" \
         || ! ssh_tunnel_existing_marker_block_owned \
           "$NOBRAND_SSH_CONFIG_MAIN" "$policy"; then
        rm -f "$policy"
        rm -rf -- "$candidate_root"
        warn 'SSH 受管标记块缺失、已被替换或无法证明归属；拒绝移除'
        return 1
      fi
      if ! ssh_tunnel_strip_marker_block "$NOBRAND_SSH_CONFIG_MAIN" "$candidate"; then
        rm -f "$policy"
        rm -rf -- "$candidate_root"
        return 1
      fi
      target="$NOBRAND_SSH_CONFIG_MAIN"
      ;;
    *)
      rm -f "$policy"
      rm -rf -- "$candidate_root"
      warn 'SSH 受管配置策略无效'
      return 1
      ;;
  esac
  ssh_tunnel_sshd_test "$candidate" || {
    rm -f "$policy"
    rm -rf -- "$candidate_root"
    warn 'SSH 策略移除候选配置无法通过 sshd -t'
    return 1
  }
  watchdog="$(ssh_tunnel_watchdog_begin "$target" "$requested_operation")" || {
    rm -f "$policy"
    rm -rf -- "$candidate_root"
    return 1
  }
  IFS='|' read -r token pid origin operation <<<"$watchdog"
  state_tmp="$(mktemp_file .ssh-state)" || {
    rm -f "$policy"
    rm -rf -- "$candidate_root"
    if ! ssh_tunnel_watchdog_cancel "$token" "$pid"; then
      warn 'SSH watchdog 已取得操作权或无法安全取消；状态与回滚快照已保留'
      return 75
    fi
    return 1
  }
  if ! jq --arg token "$token" --arg pid "$pid" --arg origin "$origin" --arg operation "$operation" \
    --arg updated "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
    .policy_applied=false | .pending_operation=$operation | .pending_watchdog_token=$token
    | .pending_watchdog_pid=$pid | .pending_origin_connection=$origin | .updated_at=$updated
  ' "$NOBRAND_SSH_STATE_FILE" >"$state_tmp"; then
    rm -f "$policy" "$state_tmp"
    rm -rf -- "$candidate_root"
    if ! ssh_tunnel_watchdog_cancel "$token" "$pid"; then
      warn 'SSH watchdog 已取得操作权或无法安全取消；状态与回滚快照已保留'
      return 75
    fi
    return 1
  fi
  if [ "$strategy" = dropin ]; then
    rm -f "$target" || {
      rm -f "$policy" "$state_tmp"
      rm -rf -- "$candidate_root"
      if ! ssh_tunnel_watchdog_rollback_now "$token" "$pid"; then
        warn 'SSH watchdog 已取得回滚权或立即回滚未完成；状态与快照已保留'
        return 75
      fi
      return 1
    }
  else
    nb_atomic_install_file "$candidate" "$target" 0600 || {
      rm -f "$policy" "$state_tmp"
      rm -rf -- "$candidate_root"
      if ! ssh_tunnel_watchdog_rollback_now "$token" "$pid"; then
        warn 'SSH watchdog 已取得回滚权或立即回滚未完成；状态与快照已保留'
        return 75
      fi
      return 1
    }
  fi
  if ! ssh_tunnel_sshd_test "$NOBRAND_SSH_CONFIG_MAIN" || ! ssh_tunnel_reload; then
    warn 'SSH 策略移除或重新加载失败，正在立即回滚'
    rm -f "$policy" "$state_tmp"
    rm -rf -- "$candidate_root"
    if ! ssh_tunnel_watchdog_rollback_now "$token" "$pid"; then
      warn 'SSH watchdog 已取得回滚权或立即回滚未完成；状态与快照已保留'
      return 75
    fi
    return 1
  fi
  if [ "$token" != disabled ] \
     && ! ssh_tunnel_watchdog_claim_ready "$token" "$pid"; then
    rm -f "$policy" "$state_tmp"
    rm -rf -- "$candidate_root"
    warn 'SSH watchdog 已取得回滚权或回滚事务已失效；拒绝提交待确认状态'
    return 75
  fi
  if ! nb_atomic_install_file "$state_tmp" "$NOBRAND_SSH_STATE_FILE" 0600; then
    rm -f "$policy" "$state_tmp"
    rm -rf -- "$candidate_root"
    if ! ssh_tunnel_watchdog_rollback_now "$token" "$pid"; then
      warn 'SSH watchdog 已取得回滚权或立即回滚未完成；状态与快照已保留'
      return 75
    fi
    return 1
  fi
  rm -f "$policy" "$state_tmp"
  rm -rf -- "$candidate_root"
  if [ "$token" = disabled ]; then
    if ! ssh_tunnel_confirm_admin disabled; then
      warn 'SSH 策略移除状态已写入但待确认状态未能完成；已保留状态供安全重试'
      return 75
    fi
  else
    if ! ssh_tunnel_watchdog_prompt "$token"; then
      warn 'SSH 策略移除仍在等待确认，但确认提示输出失败；已保留 watchdog 状态'
      return 75
    fi
  fi
}

ssh_tunnel_state_identity_file_valid() {
  local state_file="$1"
  [ -f "$state_file" ] && [ ! -L "$state_file" ] || return 1
  jq -e --arg group "$NOBRAND_SSH_GROUP" --arg main "$NOBRAND_SSH_CONFIG_MAIN" \
    --arg dropin "$NOBRAND_SSH_CONFIG_DROPIN" '
    .schema_version==3 and .ownership=="nobrand-v3" and .protocol=="ssh-tunnel"
    and .external_listener==true and .managed_listener==false and .managed_firewall==false
    and .group==$group and (.policy_applied|type)=="boolean"
    and (.real_port|type)=="number" and .real_port>=1 and .real_port<=65535
    and (.real_port|floor)==.real_port
    and (.advertise_mode=="auto" or .advertise_mode=="custom")
    and (.advertise_host|type)=="string"
    and (.advertise_port|type)=="number" and .advertise_port>=1 and .advertise_port<=65535
    and (.advertise_port|floor)==.advertise_port
    and (.config_strategy=="marker-block" or .config_strategy=="dropin")
    and ((.config_strategy=="marker-block" and .managed_config_path==$main)
      or (.config_strategy=="dropin" and .managed_config_path==$dropin))
    and (.users|type)=="array"
    and all(.users[];
      (.account_id|type)=="string"
      and (.account_id|test("^a([0-9a-f]{16}|[0-9a-f]{32})$"))
      and (.linux_user|type)=="string" and (.linux_user|test("^nbt-[a-z0-9_-]{1,27}$"))
      and (.uid|type)=="number" and .uid>=0 and (.uid|floor)==.uid
      and .group==$group
      and (.key_fingerprint|type)=="string"
      and (.key_fingerprint|test("^SHA256:[A-Za-z0-9+/]{43}$"))
    )
    and ([.users[].account_id]|unique|length)==(.users|length)
    and ([.users[].linux_user]|unique|length)==(.users|length)
    and ([.users[].uid]|unique|length)==(.users|length)
    and ((.pending_operation // "")|type)=="string"
    and ((.pending_watchdog_token // "")|type)=="string"
    and ((.pending_watchdog_pid // "")|type)=="string"
    and ((.pending_origin_connection // "")|type)=="string"
  ' "$state_file" >/dev/null 2>&1
}

ssh_tunnel_state_identity_valid() {
  ssh_tunnel_state_identity_file_valid "$NOBRAND_SSH_STATE_FILE"
}

ssh_tunnel_pending_tuple_valid() {
  local operation="$1" token="$2" pid="${3:-}" origin="${4:-}" policy="$5"
  ssh_tunnel_pending_operation_valid "$operation" || return 1
  [ -n "$token" ] && ssh_tunnel_watchdog_token_valid "$token" || return 1
  ssh_tunnel_watchdog_pid_valid "$pid" || return 1
  if [ "$token" = disabled ]; then
    [ -z "$pid" ] && [ -z "$origin" ] || return 1
  else
    [[ "$pid" =~ ^[0-9]+$ ]] && [ "$((10#$pid))" -gt 1 ] || return 1
  fi
  ! has_control_chars "$origin" || return 1
  case "$operation:$policy" in
    install:true|restore:true|uninstall:false|unified-uninstall:false) return 0 ;;
  esac
  return 1
}

ssh_tunnel_policy_absent() {
  local strategy managed_path
  strategy="$(ssh_tunnel_state_field config_strategy 2>/dev/null || true)"
  managed_path="$(ssh_tunnel_state_field managed_config_path 2>/dev/null || true)"
  case "$strategy" in
    dropin)
      [ "$managed_path" = "$NOBRAND_SSH_CONFIG_DROPIN" ] || return 1
      [ ! -e "$managed_path" ] && [ ! -L "$managed_path" ] || return 1
      ;;
    marker-block)
      [ "$managed_path" = "$NOBRAND_SSH_CONFIG_MAIN" ] || return 1
      ! grep -Fqx "$NOBRAND_SSH_BLOCK_BEGIN" "$NOBRAND_SSH_CONFIG_MAIN" 2>/dev/null \
        && ! grep -Fqx "$NOBRAND_SSH_BLOCK_END" "$NOBRAND_SSH_CONFIG_MAIN" 2>/dev/null \
        || return 1
      ;;
    *) return 1 ;;
  esac
  ssh_tunnel_sshd_test "$NOBRAND_SSH_CONFIG_MAIN"
}

ssh_tunnel_confirm_admin() {
  local supplied="${1:-}" expected pid origin current operation policy state_tmp=""
  local base script confirmed continue_unified=0 resume_repair=0
  require_root
  ssh_tunnel_state_identity_valid || die 'SSH Tunnel 状态无效，拒绝确认 watchdog'
  expected="$(ssh_tunnel_state_field pending_watchdog_token)"
  [ -n "$expected" ] || die '没有待确认的 SSH 策略 watchdog'
  ssh_tunnel_watchdog_token_valid "$expected" || die 'SSH watchdog token 状态无效'
  [ "$supplied" = "$expected" ] || die 'watchdog token 不匹配'
  origin="$(ssh_tunnel_state_field pending_origin_connection 2>/dev/null || true)"
  operation="$(ssh_tunnel_state_field pending_operation 2>/dev/null || true)"
  pid="$(ssh_tunnel_state_field pending_watchdog_pid 2>/dev/null || true)"
  policy="$(ssh_tunnel_state_field policy_applied 2>/dev/null || true)"
  ssh_tunnel_pending_tuple_valid "$operation" "$expected" "$pid" "$origin" "$policy" \
    || die 'SSH watchdog 待确认状态不一致，拒绝继续'
  current="${SSH_CONNECTION:-}"
  if [ "$expected" != disabled ]; then
    [ -n "$current" ] || die '必须从一条全新的管理员 SSH 连接确认 watchdog'
    [ -z "$origin" ] || [ "$current" != "$origin" ] \
      || die '必须从一条全新的管理员 SSH 连接确认 watchdog'
  fi
  ssh_tunnel_sshd_test "$NOBRAND_SSH_CONFIG_MAIN" || return 1
  if [ "$operation" = uninstall ] || [ "$operation" = unified-uninstall ]; then
    ssh_tunnel_policy_absent || die 'SSH 受管策略仍存在或状态不一致，拒绝完成卸载确认'
  fi
  if [ "$expected" != disabled ]; then
    base="${NOBRAND_SSH_WATCHDOG_DIR}/${expected}"
    script="${base}.rollback.sh"
    confirmed="${script}.confirmed"
    if [ -e "$confirmed" ] || [ -L "$confirmed" ]; then
      [ -f "$confirmed" ] && [ ! -L "$confirmed" ] \
        || die 'SSH watchdog 确认标记无效，拒绝继续'
      [ ! -e "${base}.armed" ] && [ ! -L "${base}.armed" ] \
        && [ ! -e "${script}.running" ] && [ ! -L "${script}.running" ] \
        || die 'SSH watchdog 存在冲突的操作权标记，拒绝继续'
    else
      ssh_tunnel_watchdog_claim_ready "$expected" "$pid" \
        || die 'SSH watchdog 进程或回滚快照已失效，拒绝确认'
      if ! mv -f -- "${base}.armed" "$confirmed" 2>/dev/null; then
      if [ -e "${script}.running" ]; then
        die 'SSH 回滚 watchdog 已取得操作权；请等待回滚完成后重试'
      fi
      die 'SSH watchdog 已不再等待确认；状态未更改，请检查回滚结果'
      fi
    fi
  fi
  state_tmp="$(mktemp_file .ssh-state)" || return 1
  jq --arg operation "$operation" --arg updated "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
    .pending_operation=(if ($operation=="uninstall" or $operation=="unified-uninstall")
      then $operation else "" end)
    | .pending_watchdog_token="" | .pending_watchdog_pid=""
    | .pending_origin_connection=""
    | .policy_applied=(if ($operation=="uninstall" or $operation=="unified-uninstall") then false else true end)
    | .updated_at=$updated
  ' "$NOBRAND_SSH_STATE_FILE" >"$state_tmp" \
    && nb_atomic_install_file "$state_tmp" "$NOBRAND_SSH_STATE_FILE" 0600 || {
      rm -f "$state_tmp"
      [ "$expected" = disabled ] || ssh_tunnel_watchdog_stop_owned "$expected" "$pid"
      # Keep the confirmed claim and snapshots. The same token can safely
      # retry the state commit; the rollback process can no longer win.
      return 1
    }
  rm -f "$state_tmp"
  if [ "$expected" != disabled ]; then
    ssh_tunnel_watchdog_stop_owned "$expected" "$pid"
    ssh_tunnel_watchdog_cleanup_artifacts "$expected" || return 1
  fi
  t '全新管理员 SSH 连接已确认；回滚 watchdog 已取消' \
    'Brand-new administrator SSH connection confirmed; rollback watchdog cancelled'
  case "$operation" in
    uninstall) ssh_tunnel_finalize_uninstall uninstall ;;
    unified-uninstall)
      ssh_tunnel_finalize_uninstall unified-uninstall || return 1
      continue_unified=1
      ;;
    restore)
      if [ "$expected" != disabled ] \
         && declare -F nb_lifecycle_tx_valid >/dev/null 2>&1 \
         && nb_lifecycle_tx_valid \
         && [ "$(nb_lifecycle_field STATUS)" = in-progress ] \
         && [ "$(nb_lifecycle_field OPERATION)" = repair ]; then
        resume_repair=1
      fi
      ;;
  esac
  if [ "$continue_unified" -eq 1 ]; then
    YES=1 nobrand_uninstall || return 1
  elif [ "$resume_repair" -eq 1 ]; then
    do_install || return 1
  fi
  if [ "$operation" = restore ] \
     && declare -F nobrand_backup_restore_confirmation_finalize >/dev/null 2>&1; then
    nobrand_backup_restore_confirmation_finalize || return 1
  fi
}

ssh_tunnel_set_endpoint_state() {
  local host="$1" port="$2" mode=custom tmp
  ssh_tunnel_watchdog_mutation_preflight || return $?
  ssh_tunnel_state_exists || die 'SSH Tunnel 未安装'
  if [ -z "$host" ]; then
    mode=auto
    port="$(ssh_tunnel_default_display_port)" || die '无法安全推导 SSH Display Endpoint 端口'
  else
    valid_advertise_host "$host" || die 'SSH Display Endpoint 主机无效'
    valid_advertise_port "$port" || die 'SSH Display Endpoint 端口无效'
    port="$(normalize_uint "$port")"
  fi
  tmp="$(mktemp_file .ssh-state)" || return 1
  jq --arg mode "$mode" --arg host "$host" --arg port "$port" \
    --arg updated "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
    .advertise_mode=$mode | .advertise_host=$host | .advertise_port=($port|tonumber)
    | .updated_at=$updated
  ' "$NOBRAND_SSH_STATE_FILE" >"$tmp" \
    && nb_atomic_install_file "$tmp" "$NOBRAND_SSH_STATE_FILE" 0600
  rm -f "$tmp"
}

ssh_tunnel_effective_host() {
  local mode host ingress_profile_id
  mode="$(ssh_tunnel_state_field advertise_mode)"
  host="$(ssh_tunnel_state_field advertise_host)"
  ingress_profile_id="$(ssh_tunnel_state_field ingress_profile_id 2>/dev/null || true)"
  nb_effective_advertise_host "$mode" "$host" "$ingress_profile_id"
}

ssh_tunnel_host_public_key() {
  local candidate
  for candidate in /etc/ssh/ssh_host_ed25519_key.pub /etc/ssh/ssh_host_ecdsa_key.pub \
    /etc/ssh/ssh_host_rsa_key.pub; do
    [ -s "$candidate" ] && { printf '%s' "$candidate"; return 0; }
  done
  return 1
}

ssh_tunnel_known_hosts_entry() {
  local host="$1" port="$2" public_key key_fields known_host
  public_key="$(ssh_tunnel_host_public_key)" || return 1
  key_fields="$(awk '{print $1" "$2}' "$public_key")"
  known_host="$host"
  [ "$port" = 22 ] || known_host="[${host}]:${port}"
  printf '%s %s' "$known_host" "$key_fields"
}

ssh_tunnel_show_user() {
  local selector="${1:-}" user_json account_id label linux_user host port key_path
  user_json="$(ssh_tunnel_resolve_user_json "$selector")" || return 1
  account_id="$(jq -r .account_id <<<"$user_json")"
  label="$(jq -r .display_name <<<"$user_json")"
  linux_user="$(jq -r .linux_user <<<"$user_json")"
  host="$(ssh_tunnel_effective_host)"
  port="$(ssh_tunnel_state_field advertise_port)"
  key_path="$(ssh_tunnel_key_dir "$account_id")/id_ed25519"
  printf 'SSH Tunnel 用户: %s\nLinux 身份: %s\n入口配置 / Ingress Profile: %s\nIngress 强制策略: 不适用（系统 sshd）\n系统实际监听 / Actual Listener: *:%s/TCP\n展示端点 / Display Endpoint: %s:%s\n' \
    "$label" "$linux_user" "$(nb_ingress_profile_name "$(ssh_tunnel_state_field ingress_profile_id 2>/dev/null || true)")" \
    "$(ssh_tunnel_state_field real_port)" "$host" "$port"
  printf '连接命令: ssh -N -i %s -p %s %s@%s\n' "$key_path" "$port" "$linux_user" "$host"
  printf 'TCP 转发：-L / -D / -R\nGatewayPorts=no；shell / exec / TTY / SFTP / SCP 均已禁用。\n'
}

ssh_tunnel_export_user() {
  local selector="${1:-}" user_json account_id label linux_user host port key_path public_key
  local fingerprint known_hosts
  user_json="$(ssh_tunnel_resolve_user_json "$selector")" || return 1
  account_id="$(jq -r .account_id <<<"$user_json")"
  label="$(jq -r .display_name <<<"$user_json")"
  linux_user="$(jq -r .linux_user <<<"$user_json")"
  host="$(ssh_tunnel_effective_host)"
  port="$(ssh_tunnel_state_field advertise_port)"
  key_path="$(ssh_tunnel_key_dir "$account_id")/id_ed25519"
  public_key="$(ssh_tunnel_host_public_key 2>/dev/null || true)"
  fingerprint='不可用'
  known_hosts='不可用'
  [ -z "$public_key" ] || fingerprint="$(ssh-keygen -lf "$public_key" -E sha256 2>/dev/null || printf '不可用')"
  known_hosts="$(ssh_tunnel_known_hosts_entry "$host" "$port" 2>/dev/null || printf '不可用')"
  printf '%s\n' '===== OPENSSH 私钥（显式导出）====='
  cat "$key_path" || return 1
  printf '%s\n' '===== OPENSSH 私钥结束 =====' ''
  printf '主机密钥指纹: %s\nknown_hosts: %s\n\n' "$fingerprint" "$known_hosts"
  printf 'SOCKS5 命令:\nssh -N -D 127.0.0.1:1080 -i <PRIVATE_KEY> -p %s %s@%s' \
    "$port" "$linux_user" "$host"
  printf ' -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 -o ServerAliveCountMax=3\n\n'
  printf 'LocalForward 模板:\nssh -N -L <LOCAL_BIND>:<TARGET_HOST>:<TARGET_PORT> -i <PRIVATE_KEY> -p %s %s@%s -o ExitOnForwardFailure=yes\n\n' \
    "$port" "$linux_user" "$host"
  printf 'RemoteForward 模板:\nssh -N -R <REMOTE_PORT>:<TARGET_HOST>:<TARGET_PORT> -i <PRIVATE_KEY> -p %s %s@%s -o ExitOnForwardFailure=yes\n' \
    "$port" "$linux_user" "$host"
  printf 'GatewayPorts=no：RemoteForward 仅监听回环地址，不能暴露公网监听。\n\n'
  printf 'OpenSSH 配置:\nHost nobrand-%s\n  HostName %s\n  Port %s\n  User %s\n  IdentityFile <PRIVATE_KEY>\n  IdentitiesOnly yes\n  ExitOnForwardFailure yes\n  ServerAliveInterval 30\n  ServerAliveCountMax 3\n' \
    "$(safe_filename_component "$label")" "$host" "$port" "$linux_user"
}

ssh_tunnel_node_rows() {
  local host port status user_json label
  if ! ssh_tunnel_state_exists; then
    ssh_tunnel_state_absent && return 0
    return 1
  fi
  host="$(ssh_tunnel_effective_host)"
  port="$(ssh_tunnel_state_field advertise_port)"
  status=Stopped
  [ "$(ssh_tunnel_state_field policy_applied 2>/dev/null || printf false)" = true ] && status=Ready
  while IFS= read -r user_json; do
    [ -n "$user_json" ] || continue
    label="$(jq -r .display_name <<<"$user_json")"
    printf 'SSH Tunnel|%s|%s:%s|%s|TCP (external sshd)\n' "$label" "$host" "$port" "$status"
  done < <(jq -c '.users[]?' "$NOBRAND_SSH_STATE_FILE")
}

ssh_tunnel_doctor() {
  local failed=0 user_json managed_path validation_user
  if ! ssh_tunnel_state_exists; then
    if ssh_tunnel_state_absent; then
      nb_doctor_line INFO 'SSH Tunnel 未安装'
      return 0
    fi
    nb_doctor_line FAIL 'SSH Tunnel 权威状态损坏或无法读取'
    return 1
  fi
  ssh_tunnel_sshd_test "$NOBRAND_SSH_CONFIG_MAIN" \
    && nb_doctor_line PASS 'sshd 配置语法有效' \
    || { nb_doctor_line FAIL 'sshd 配置语法无效'; failed=1; }
  managed_path="$(ssh_tunnel_state_field managed_config_path)"
  [ -s "$managed_path" ] && nb_doctor_line PASS '受管 Match 策略存在' \
    || { nb_doctor_line FAIL '缺少受管 Match 策略'; failed=1; }
  ssh_tunnel_group_identity_valid && nb_doctor_line PASS '专用用户组身份有效' \
    || { nb_doctor_line FAIL '专用用户组身份无效'; failed=1; }
  validation_user="$(jq -r '.users[0].linux_user // empty' "$NOBRAND_SSH_STATE_FILE")"
  [ -z "$validation_user" ] || ssh_tunnel_effective_policy_valid "$NOBRAND_SSH_CONFIG_MAIN" "$validation_user" \
    && nb_doctor_line PASS '仅转发生效策略有效' \
    || { nb_doctor_line FAIL '仅转发生效策略无效'; failed=1; }
  while IFS= read -r user_json; do
    ssh_tunnel_user_identity_valid "$user_json" \
      && nb_doctor_line PASS "用户身份有效: $(jq -r .display_name <<<"$user_json")" \
      || { nb_doctor_line FAIL "用户身份无效: $(jq -r .display_name <<<"$user_json")"; failed=1; }
    [ "$(stat -c '%a' "$(ssh_tunnel_key_dir "$(jq -r .account_id <<<"$user_json")")/id_ed25519" 2>/dev/null || true)" = 600 ] \
      && nb_doctor_line PASS "私钥权限有效: $(jq -r .display_name <<<"$user_json")" \
      || { nb_doctor_line FAIL "私钥权限无效: $(jq -r .display_name <<<"$user_json")"; failed=1; }
  done < <(jq -c '.users[]?' "$NOBRAND_SSH_STATE_FILE")
  nb_doctor_line PASS 'external_listener=true managed_listener=false managed_firewall=false'
  nb_doctor_line INFO 'NOT_APPLICABLE_TO_SYSTEM_SSH：系统 sshd / 外部映射入口'
  return "$failed"
}

ssh_tunnel_rollback_empty_install() {
  local group_preexisting="${1:-1}"
  rm -f "$NOBRAND_SSH_STATE_FILE"
  find "$NOBRAND_SSH_KEYS_DIR" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + 2>/dev/null || true
  find "$NOBRAND_SSH_AUTHORIZED_KEYS_DIR" -mindepth 1 -maxdepth 1 -type f -delete 2>/dev/null || true
  find "$NOBRAND_SSH_ACCOUNT_MARKER_DIR" -mindepth 1 -maxdepth 1 -type f \
    ! -name '.group.json' -delete 2>/dev/null || true
  if [ "$group_preexisting" -eq 0 ]; then
    if ssh_tunnel_group_identity_valid; then
      ssh_tunnel_delete_group >/dev/null 2>&1 || return 1
    elif _has_group "$NOBRAND_SSH_GROUP"; then
      return 1
    fi
    rm -f "$NOBRAND_SSH_GROUP_MARKER"
  fi
  rmdir "$NOBRAND_SSH_KEYS_DIR" "$NOBRAND_SSH_AUTHORIZED_KEYS_DIR" \
    "$NOBRAND_SSH_ACCOUNT_MARKER_DIR" "$NOBRAND_SSH_STATE_DIR" \
    "$NOBRAND_SSH_CONFIG_DIR" 2>/dev/null || true
}

ssh_tunnel_install() {
  local label mode host port real_port strategy managed_path users='[]' state_tmp="" account_id linux_user
  local group_preexisting=0 apply_rc=0
  require_root
  require_linux
  ssh_tunnel_watchdog_mutation_preflight || return $?
  nobrand_prepare_common
  nb_prepare_ingress_request || return 1
  command -v ssh-keygen >/dev/null 2>&1 || die 'SSH Tunnel 需要 OpenSSH ssh-keygen'
  ssh_tunnel_sshd_binary >/dev/null || die '未检测到现有 OpenSSH sshd'
  ssh_tunnel_sshd_test "$NOBRAND_SSH_CONFIG_MAIN" || die '现有 sshd_config 无法通过 sshd -t'
  ssh_tunnel_state_exists && { t 'SSH Tunnel 已安装' 'SSH Tunnel is already installed'; return 0; }
  ssh_tunnel_state_absent || die 'SSH Tunnel 权威状态损坏或无法读取，拒绝覆盖'
  label="${SSH_TUNNEL_USER:-default}"
  ssh_tunnel_valid_label "$label" || die 'SSH Tunnel 用户标签无效'
  real_port="$(ssh_tunnel_detect_real_port)" || die '无法读取现有 sshd 生效端口'
  if [ -n "${ADVERTISE_HOST:-}" ]; then
    valid_advertise_host "$ADVERTISE_HOST" || die 'SSH Display Endpoint 主机无效'
    valid_advertise_port "$ADVERTISE_PORT" || die 'SSH Display Endpoint 端口无效'
    mode=custom host="$ADVERTISE_HOST" port="$(normalize_uint "$ADVERTISE_PORT")"
  else
    [ "${YES:-0}" -ne 1 ] || [ "${ADVERTISE_AUTO_REQUESTED:-0}" -eq 1 ] \
      || [ -n "$(nb_ingress_profile_display_host "$INGRESS_PROFILE_ID" 2>/dev/null || true)" ] \
      || die '非交互 SSH 安装必须明确指定 Display Endpoint、--advertise-auto，或选择带展示主机的入口配置'
    mode=auto host=""
    if [ -n "${ADVERTISE_PORT:-}" ]; then
      valid_advertise_port "$ADVERTISE_PORT" || die 'SSH Display Endpoint 端口无效'
      port="$(normalize_uint "$ADVERTISE_PORT")"
    else
      port="$(ssh_tunnel_default_display_port)" \
      || die '无法安全推导 SSH Display Endpoint 端口；请明确指定'
    fi
  fi
  _has_group "$NOBRAND_SSH_GROUP" && group_preexisting=1
  nb_lifecycle_mark_protocol_mutation_started ssh-tunnel || return 1
  ssh_tunnel_create_group || die '无法创建 SSH Tunnel 专用用户组'
  strategy="marker-block" managed_path="$NOBRAND_SSH_CONFIG_MAIN"
  ssh_tunnel_dropin_supported && { strategy=dropin; managed_path="$NOBRAND_SSH_CONFIG_DROPIN"; }
  state_tmp="$(mktemp_file .ssh-state)" || {
    ssh_tunnel_rollback_empty_install "$group_preexisting" || true
    return 1
  }
  ssh_tunnel_generate_state "$state_tmp" "$mode" "$host" "$port" "$real_port" \
    "$strategy" "$managed_path" "$users" "" "$INGRESS_PROFILE_ID" || {
      rm -f "$state_tmp"
      ssh_tunnel_rollback_empty_install "$group_preexisting" || true
      return 1
    }
  nb_atomic_install_file "$state_tmp" "$NOBRAND_SSH_STATE_FILE" 0600 || {
    rm -f "$state_tmp"
    ssh_tunnel_rollback_empty_install "$group_preexisting" || true
    return 1
  }
  rm -f "$state_tmp"
  account_id="$(ssh_tunnel_add_user_internal "$label")" || {
    ssh_tunnel_rollback_empty_install "$group_preexisting" || true
    return 1
  }
  linux_user="$(jq -r --arg account_id "$account_id" '.users[] | select(.account_id==$account_id) | .linux_user' \
    "$NOBRAND_SSH_STATE_FILE")"
  if ssh_tunnel_apply_policy "$linux_user"; then
    :
  else
    apply_rc=$?
    if [ "$apply_rc" -eq 75 ]; then
      warn 'SSH 策略事务的 watchdog 所有权未解决；已保留状态、账户与回滚证据'
      return 75
    fi
    if ! ssh_tunnel_delete_user_internal "$label" >/dev/null 2>&1; then
      warn 'SSH 策略应用失败，且账户回滚不完整；已保留状态以便安全重试'
      return 1
    fi
    ssh_tunnel_rollback_empty_install "$group_preexisting" \
      || warn 'SSH 安装回滚无法删除刚创建的空用户组'
    return "$apply_rc"
  fi
  nobrand_install_manager_script || true
  ssh_tunnel_show_user "$label"
}

ssh_tunnel_status() {
  local policy
  if ! ssh_tunnel_state_exists; then
    ssh_tunnel_state_absent \
      && { t 'SSH Tunnel 未安装' 'SSH Tunnel is not installed'; return 0; }
    die 'SSH Tunnel 权威状态损坏或无法读取'
  fi
  policy="$(ssh_tunnel_state_field policy_applied)"
  [ "$policy" = true ] && policy='已应用' || policy='未应用'
  printf 'SSH Tunnel\n  策略: %s\n  现有 sshd 实际端口: %s\n  展示端点 / Display Endpoint: %s:%s\n  用户数: %s\n' \
    "$policy" "$(ssh_tunnel_state_field real_port)" \
    "$(ssh_tunnel_effective_host)" "$(ssh_tunnel_state_field advertise_port)" \
    "$(jq '.users | length' "$NOBRAND_SSH_STATE_FILE")"
  printf '  入口配置 / Ingress Profile: %s\n' "$(nb_ingress_profile_name "$(ssh_tunnel_state_field ingress_profile_id 2>/dev/null || true)")"
  printf '  资源归属: external_listener=true managed_listener=false managed_firewall=false\n'
}

ssh_tunnel_user_list() {
  if ! ssh_tunnel_state_exists; then
    ssh_tunnel_state_absent && return 0
    return 1
  fi
  jq -r '.users[]? | [.display_name,.linux_user,.key_fingerprint] | @tsv' "$NOBRAND_SSH_STATE_FILE"
}

ssh_tunnel_watchdog_directory_empty_valid() {
  local entry=""
  if [ ! -e "$NOBRAND_SSH_WATCHDOG_DIR" ] && [ ! -L "$NOBRAND_SSH_WATCHDOG_DIR" ]; then
    return 0
  fi
  ssh_tunnel_watchdog_directory_preflight || return 1
  [ "$(stat -c '%a' "$NOBRAND_SSH_WATCHDOG_DIR")" = 700 ] || return 1
  entry="$(find "$NOBRAND_SSH_WATCHDOG_DIR" -mindepth 1 -maxdepth 1 -print -quit)" \
    || return 1
  [ -z "$entry" ]
}

ssh_tunnel_empty_directory_valid() {
  local path="$1" entry=""
  if [ ! -e "$path" ] && [ ! -L "$path" ]; then
    return 0
  fi
  [ -d "$path" ] && [ ! -L "$path" ] || return 1
  entry="$(find "$path" -mindepth 1 -maxdepth 1 -print -quit)" || return 1
  [ -z "$entry" ]
}

ssh_tunnel_uninstalled_layout_valid() {
  local state_root="$1" config_root="$2" entry=""
  if [ -e "$state_root" ] || [ -L "$state_root" ]; then
    [ -d "$state_root" ] && [ ! -L "$state_root" ] || return 1
    entry="$(find "$state_root" -mindepth 1 -maxdepth 1 \
      ! -path "${state_root}/keys" ! -path "${state_root}/watchdog" -print -quit)" \
      || return 1
    [ -z "$entry" ] \
      && ssh_tunnel_empty_directory_valid "${state_root}/keys" \
      && ssh_tunnel_empty_directory_valid "${state_root}/watchdog" || return 1
  fi
  if [ -e "$config_root" ] || [ -L "$config_root" ]; then
    [ -d "$config_root" ] && [ ! -L "$config_root" ] || return 1
    entry="$(find "$config_root" -mindepth 1 -maxdepth 1 \
      ! -path "${config_root}/authorized_keys" ! -path "${config_root}/accounts" -print -quit)" \
      || return 1
    [ -z "$entry" ] \
      && ssh_tunnel_empty_directory_valid "${config_root}/authorized_keys" \
      && ssh_tunnel_empty_directory_valid "${config_root}/accounts" || return 1
  fi
}

ssh_tunnel_backup_state_ready() {
  if ! ssh_tunnel_state_exists; then
    ssh_tunnel_state_absent || return 1
    _has_group "$NOBRAND_SSH_GROUP" && return 1
    ssh_tunnel_watchdog_directory_empty_valid || return 1
    ssh_tunnel_uninstalled_layout_valid "$NOBRAND_SSH_STATE_DIR" "$NOBRAND_SSH_CONFIG_DIR"
    return $?
  fi
  ssh_tunnel_state_identity_valid || return 1
  [ "$(ssh_tunnel_state_field pending_operation 2>/dev/null || true)" = '' ] \
    && [ "$(ssh_tunnel_state_field pending_watchdog_token 2>/dev/null || true)" = '' ] \
    && [ "$(ssh_tunnel_state_field pending_watchdog_pid 2>/dev/null || true)" = '' ] \
    && [ "$(ssh_tunnel_state_field pending_origin_connection 2>/dev/null || true)" = '' ] \
    && [ "$(ssh_tunnel_state_field policy_applied 2>/dev/null || true)" = true ] \
    && ssh_tunnel_watchdog_directory_empty_valid
}

ssh_tunnel_restore_preflight() {
  local staged_state="$1" user_json linux_user expected_uid marker live_users staged_users path
  local staged_root staged_watchdog staged_config_root stage_base entry=""
  staged_root="$(dirname "$staged_state")"
  staged_watchdog="${staged_root}/watchdog"
  stage_base="$(dirname "$(dirname "$staged_root")")"
  staged_config_root="${stage_base}/config/ssh-tunnel"
  if [ ! -e "$staged_state" ] && [ ! -L "$staged_state" ]; then
    ssh_tunnel_uninstalled_layout_valid "$staged_root" "$staged_config_root" || return 1
    ssh_tunnel_state_absent || return 1
    _has_group "$NOBRAND_SSH_GROUP" && return 1
    return 0
  fi
  ssh_tunnel_state_identity_file_valid "$staged_state" || return 1
  if [ -e "$staged_watchdog" ] || [ -L "$staged_watchdog" ]; then
    [ -d "$staged_watchdog" ] && [ ! -L "$staged_watchdog" ] || return 1
    entry="$(find "$staged_watchdog" -mindepth 1 -maxdepth 1 -print -quit)" || return 1
    [ -z "$entry" ] || return 1
  fi
  [ "$(jq -r '.pending_operation // ""' "$staged_state")" = '' ] \
    && [ "$(jq -r '.pending_watchdog_token // ""' "$staged_state")" = '' ] \
    && [ "$(jq -r '.pending_watchdog_pid // ""' "$staged_state")" = '' ] \
    && [ "$(jq -r '.pending_origin_connection // ""' "$staged_state")" = '' ] \
    && [ "$(jq -r .policy_applied "$staged_state")" = true ] || return 1
  if ! ssh_tunnel_state_absent; then
    ssh_tunnel_state_exists && ssh_tunnel_state_identity_valid || return 1
    live_users="$(jq -c '[.users[] | {account_id,linux_user,uid,group}] | sort_by(.account_id)' \
      "$NOBRAND_SSH_STATE_FILE")" || return 1
    staged_users="$(jq -c '[.users[] | {account_id,linux_user,uid,group}] | sort_by(.account_id)' \
      "$staged_state")" || return 1
    [ "$live_users" = "$staged_users" ] || return 1
  fi
  if _has_group "$NOBRAND_SSH_GROUP"; then
    ssh_tunnel_group_identity_valid || return 1
  fi
  while IFS= read -r user_json; do
    linux_user="$(jq -r .linux_user <<<"$user_json")"
    expected_uid="$(jq -r .uid <<<"$user_json")"
    if _has_user "$linux_user"; then
      ssh_tunnel_linux_user_identity_valid "$user_json" || return 1
      # A backup is not proof that an already-existing local identity belongs
      # to NoBrand. Require the current, pre-restore ownership marker.
      marker="$(ssh_tunnel_account_marker_file "$linux_user")"
      for path in "$NOBRAND_SSH_CONFIG_DIR" "$NOBRAND_SSH_ACCOUNT_MARKER_DIR"; do
        [ -d "$path" ] && [ ! -L "$path" ] && secure_stat_path "$path" dir \
          || return 1
      done
      [ -f "$marker" ] && [ ! -L "$marker" ] \
        && secure_stat_path "$marker" file \
        && [ "$(stat -c '%a' "$marker")" = 600 ] || return 1
      jq -e --arg account_id "$(jq -r .account_id <<<"$user_json")" \
        --arg linux_user "$linux_user" --arg uid "$expected_uid" '
        .ownership=="nobrand-v3" and .account_id==$account_id
        and .linux_user==$linux_user and .uid==($uid|tonumber)
      ' "$marker" >/dev/null || return 1
    elif getent passwd "$expected_uid" >/dev/null 2>&1; then
      return 1
    fi
  done < <(jq -c '.users[]?' "$staged_state")
}

ssh_tunnel_reconcile_restored_listener_state() {
  local current_port state_tmp=""
  current_port="$(ssh_tunnel_detect_real_port)" || return 1
  valid_advertise_port "$current_port" || return 1
  current_port="$(normalize_uint "$current_port")"
  # advertise_port may be an explicit external mapping even in auto-host mode.
  # The current schema has no provenance bit, so preserve it exactly.
  if [ "$(ssh_tunnel_state_field real_port)" = "$current_port" ]; then
    return 0
  fi
  state_tmp="$(mktemp_file .ssh-listener-state)" || return 1
  if ! jq --arg real_port "$current_port" \
    --arg updated "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
      .real_port=($real_port|tonumber)
      | .updated_at=$updated
    ' "$NOBRAND_SSH_STATE_FILE" >"$state_tmp" \
    || ! nb_atomic_install_file "$state_tmp" "$NOBRAND_SSH_STATE_FILE" 0600; then
    rm -f "$state_tmp"
    return 1
  fi
  rm -f "$state_tmp"
}

# A backup does not contain the destination host's external sshd configuration.
# Persist a truthful pre-apply state before the watchdog snapshots it, so a
# timeout restores a recoverable partial SSH module instead of claiming that a
# policy missing from the destination is already active.
ssh_tunnel_prepare_restored_policy_state() {
  local state_tmp=""
  ssh_tunnel_watchdog_mutation_preflight || return $?
  if ! ssh_tunnel_state_exists; then
    ssh_tunnel_state_absent && return 0
    return 1
  fi
  ssh_tunnel_state_identity_valid || return 1
  [ "$(ssh_tunnel_state_field pending_operation 2>/dev/null || true)" = '' ] \
    && [ "$(ssh_tunnel_state_field pending_watchdog_token 2>/dev/null || true)" = '' ] \
    && [ "$(ssh_tunnel_state_field pending_watchdog_pid 2>/dev/null || true)" = '' ] \
    && [ "$(ssh_tunnel_state_field pending_origin_connection 2>/dev/null || true)" = '' ] \
    || return 1
  state_tmp="$(mktemp_file .ssh-restore-preapply)" || return 1
  if ! jq --arg updated "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
      .policy_applied=false
      | .pending_operation=""
      | .pending_watchdog_token=""
      | .pending_watchdog_pid=""
      | .pending_origin_connection=""
      | .updated_at=$updated
    ' "$NOBRAND_SSH_STATE_FILE" >"$state_tmp" \
     || ! nb_atomic_install_file "$state_tmp" "$NOBRAND_SSH_STATE_FILE" 0600; then
    rm -f "$state_tmp"
    return 1
  fi
  rm -f "$state_tmp"
  ssh_tunnel_state_identity_valid
}

ssh_tunnel_snapshot_external_state() {
  local snapshot="$1" label path
  mkdir -p "$snapshot" || return 1
  for label in main dropin; do
    case "$label" in
      main) path="$NOBRAND_SSH_CONFIG_MAIN" ;;
      dropin) path="$NOBRAND_SSH_CONFIG_DROPIN" ;;
    esac
    if [ -e "$path" ] || [ -L "$path" ]; then
      [ -f "$path" ] || [ -L "$path" ] || return 1
      cp -a "$path" "$snapshot/$label" || return 1
    else
      : >"$snapshot/${label}.absent" || return 1
    fi
  done
  : >"$snapshot/created.log"
}

ssh_tunnel_log_created_restore_identity() {
  local log="${1:-}" kind="$2" name="$3" numeric_id="$4" account_id="${5:-}"
  [ -n "$log" ] || return 0
  printf '%s|%s|%s|%s\n' "$kind" "$name" "$numeric_id" "$account_id" >>"$log"
}

ssh_tunnel_cancel_pending_watchdog() {
  local token pid
  if ! ssh_tunnel_state_exists; then
    ssh_tunnel_state_absent && return 0
    return 1
  fi
  token="$(ssh_tunnel_state_field pending_watchdog_token 2>/dev/null || true)"
  pid="$(ssh_tunnel_state_field pending_watchdog_pid 2>/dev/null || true)"
  [ -n "$token" ] || return 0
  ssh_tunnel_watchdog_cancel "$token" "$pid"
}

ssh_tunnel_restore_external_snapshot() {
  local snapshot="$1" log="${2:-$1/created.log}" kind name numeric_id account_id
  local passwd_line actual_uid actual_gid gecos group_gid label path failed=0
  if [ -s "$log" ]; then
    while IFS='|' read -r kind name numeric_id account_id; do
      [ "$kind" = USER ] || continue
      passwd_line="$(getent passwd "$name" 2>/dev/null || true)"
      [ -n "$passwd_line" ] || continue
      IFS=: read -r _ _ actual_uid actual_gid gecos _ _ <<<"$passwd_line"
      group_gid="$(getent group "$NOBRAND_SSH_GROUP" 2>/dev/null | awk -F: '{print $3}')"
      if [ "$actual_uid" = "$numeric_id" ] && [ "$actual_gid" = "$group_gid" ] \
         && [ "$gecos" = "NoBrand SSH Tunnel ${account_id}" ]; then
        pkill -KILL -u "$actual_uid" 2>/dev/null || true
        ssh_tunnel_delete_linux_user "$name" || failed=1
      else
        warn "SSH 恢复回滚因身份不匹配而拒绝删除用户: $name"
        failed=1
      fi
    done < <(awk -F'|' '$1=="USER" {line[NR]=$0} END {for (i=NR;i>=1;i--) if (line[i] != "") print line[i]}' "$log")
    while IFS='|' read -r kind name numeric_id _; do
      [ "$kind" = GROUP ] || continue
      if _has_group "$name"; then
        [ "$(getent group "$name" | awk -F: '{print $3}')" = "$numeric_id" ] || {
          warn "SSH 恢复回滚因身份不匹配而拒绝删除用户组: $name"
          failed=1
          continue
        }
        if command -v groupdel >/dev/null 2>&1; then
          groupdel "$name" || failed=1
        elif command -v delgroup >/dev/null 2>&1; then
          delgroup "$name" || failed=1
        else
          failed=1
        fi
      fi
    done <"$log"
  fi
  for label in main dropin; do
    case "$label" in
      main) path="$NOBRAND_SSH_CONFIG_MAIN" ;;
      dropin) path="$NOBRAND_SSH_CONFIG_DROPIN" ;;
    esac
    if [ -e "$snapshot/$label" ] || [ -L "$snapshot/$label" ]; then
      [ -f "$snapshot/$label" ] || [ -L "$snapshot/$label" ] \
        || { failed=1; continue; }
      mkdir -p "$(dirname "$path")" || { failed=1; continue; }
      rm -f -- "$path" || { failed=1; continue; }
      cp -a -- "$snapshot/$label" "$path" || failed=1
    elif [ -f "$snapshot/${label}.absent" ] \
         && [ ! -L "$snapshot/${label}.absent" ]; then
      rm -f "$path" || failed=1
    else
      failed=1
    fi
  done
  if [ -e "$NOBRAND_SSH_CONFIG_MAIN" ] || [ -L "$NOBRAND_SSH_CONFIG_MAIN" ]; then
    ssh_tunnel_sshd_test "$NOBRAND_SSH_CONFIG_MAIN" && ssh_tunnel_reload || failed=1
  fi
  [ "$failed" -eq 0 ]
}

ssh_tunnel_restore_system_state() {
  local transaction_log="${1:-}" user_json linux_user account_id expected_uid nologin_shell
  local validation_user group_preexisting=0 group_marker_preexisting=0 expected_group_gid=""
  local group_gid group_created=0 group_create_rc=0 created_user=0 user_create_rc=0 surviving_users=0
  ssh_tunnel_watchdog_mutation_preflight || return $?
  if ! ssh_tunnel_state_exists; then
    ssh_tunnel_state_absent && return 0
    return 1
  fi
  ssh_tunnel_state_identity_valid || return 1
  [ "$(jq '.users | length' "$NOBRAND_SSH_STATE_FILE")" -gt 0 ] || return 1
  ssh_tunnel_restore_paths_preflight || return 1
  nologin_shell="$(ssh_tunnel_nologin_shell)" || return 1

  _has_group "$NOBRAND_SSH_GROUP" && group_preexisting=1
  if [ -e "$NOBRAND_SSH_GROUP_MARKER" ] || [ -L "$NOBRAND_SSH_GROUP_MARKER" ]; then
    group_marker_preexisting=1
  fi
  ssh_tunnel_group_marker_preflight || return 1
  # Complete the read-only preflight before creating a group, user, marker, or
  # authorized-key file. An occupied historical UID or a replacement account
  # must never be adopted merely because current state still exists.
  while IFS= read -r user_json; do
    linux_user="$(jq -r .linux_user <<<"$user_json")"
    expected_uid="$(jq -r .uid <<<"$user_json")"
    ssh_tunnel_user_key_material_valid "$user_json" || return 1
    ssh_tunnel_user_file_destinations_valid "$user_json" || return 1
    if _has_user "$linux_user"; then
      [ "$group_preexisting" -eq 1 ] || return 1
      ssh_tunnel_linux_user_identity_valid "$user_json" || return 1
      surviving_users=$((surviving_users + 1))
    elif getent passwd "$expected_uid" >/dev/null 2>&1; then
      return 1
    fi
  done < <(jq -c '.users[]?' "$NOBRAND_SSH_STATE_FILE")

  # A surviving group without its ownership marker can be rebound only when a
  # surviving state-listed account proves the exact group GID relationship.
  # With no such account there is no way to distinguish a replacement group.
  if [ "$group_preexisting" -eq 1 ] \
     && [ ! -e "$NOBRAND_SSH_GROUP_MARKER" ] && [ ! -L "$NOBRAND_SSH_GROUP_MARKER" ] \
     && [ "$surviving_users" -eq 0 ]; then
    return 1
  fi

  ssh_tunnel_ensure_restore_directories || return 1
  if [ "$group_preexisting" -eq 0 ]; then
    group_create_rc=0
    group_created=0
    if [ "$group_marker_preexisting" -eq 1 ]; then
      expected_group_gid="$(jq -r .gid "$NOBRAND_SSH_GROUP_MARKER")"
      ssh_tunnel_create_group_with_gid "$expected_group_gid" group_created \
        || group_create_rc=$?
    else
      ssh_tunnel_create_group group_created || group_create_rc=$?
    fi
    group_gid="$(getent group "$NOBRAND_SSH_GROUP" 2>/dev/null | awk -F: '{print $3}')"
    if ! [[ "$group_gid" =~ ^[0-9]+$ ]] && [ -f "$NOBRAND_SSH_GROUP_MARKER" ]; then
      group_gid="$(jq -r '.gid // empty' "$NOBRAND_SSH_GROUP_MARKER" 2>/dev/null || true)"
    fi
    [[ "$group_gid" =~ ^[0-9]+$ ]] || return 1
    if [ "$group_create_rc" -eq 0 ] && [ "$group_created" -eq 0 ]; then
      # Compatibility with restore adapters that predate the result parameter:
      # a successful create call for a name proven absent at preflight is ours.
      group_created=1
    fi
    if [ "$group_created" -eq 1 ]; then
      if ! ssh_tunnel_log_created_restore_identity "$transaction_log" GROUP \
        "$NOBRAND_SSH_GROUP" "$group_gid"; then
        if ssh_tunnel_group_identity_valid \
           && ssh_tunnel_delete_group >/dev/null 2>&1; then
          [ "$group_marker_preexisting" -eq 1 ] || rm -f "$NOBRAND_SSH_GROUP_MARKER"
        fi
        return 1
      fi
    fi
    [ "$group_create_rc" -eq 0 ] || return "$group_create_rc"
  fi
  ssh_tunnel_reconcile_group_marker || return 1

  while IFS= read -r user_json; do
    linux_user="$(jq -r .linux_user <<<"$user_json")"
    account_id="$(jq -r .account_id <<<"$user_json")"
    expected_uid="$(jq -r .uid <<<"$user_json")"
    created_user=0
    if _has_user "$linux_user"; then
      ssh_tunnel_linux_user_identity_valid "$user_json" || return 1
    else
      getent passwd "$expected_uid" >/dev/null 2>&1 && return 1
      user_create_rc=0
      ssh_tunnel_create_linux_user_with_uid \
        "$linux_user" "$account_id" "$nologin_shell" "$expected_uid" created_user \
        || user_create_rc=$?
      if [ "$user_create_rc" -eq 0 ] && [ "$created_user" -eq 0 ]; then
        # Compatibility with older restore adapters that return success without
        # accepting the optional result parameter.
        created_user=1
      fi
      if [ "$created_user" -eq 1 ]; then
        if ! ssh_tunnel_log_created_restore_identity "$transaction_log" USER \
          "$linux_user" "$expected_uid" "$account_id"; then
          ssh_tunnel_linux_user_identity_valid "$user_json" \
            && ssh_tunnel_delete_linux_user "$linux_user" >/dev/null 2>&1 || true
          return 1
        fi
      fi
      [ "$user_create_rc" -eq 0 ] || return "$user_create_rc"
    fi
    ssh_tunnel_linux_user_identity_valid "$user_json" || return 1
    ssh_tunnel_reconcile_user_files "$user_json" "$nologin_shell" || return 1
  done < <(jq -c '.users[]?' "$NOBRAND_SSH_STATE_FILE")
  validation_user="$(jq -r '.users[0].linux_user // empty' "$NOBRAND_SSH_STATE_FILE")"
  [ -n "$validation_user" ] || return 1
  ssh_tunnel_reconcile_restored_listener_state || return 1
  ssh_tunnel_apply_policy "$validation_user" restore
}

ssh_tunnel_uninstall_checkpoint() {
  local phase="$1"
  declare -F nb_test_mode_enabled >/dev/null 2>&1 && nb_test_mode_enabled || return 0
  [ "${NOBRAND_TEST_INTERRUPT_SSH_UNINSTALL_AT:-}" != "$phase" ] || return 75
}

ssh_tunnel_uninstall_roots_valid() {
  local safe_state safe_config active=""
  [ "$(dirname "$NOBRAND_SSH_STATE_FILE")" = "$NOBRAND_SSH_STATE_DIR" ] || return 1
  [ "$NOBRAND_SSH_KEYS_DIR" = "${NOBRAND_SSH_STATE_DIR}/keys" ] || return 1
  [ "$NOBRAND_SSH_WATCHDOG_DIR" = "${NOBRAND_SSH_STATE_DIR}/watchdog" ] || return 1
  [ "$NOBRAND_SSH_AUTHORIZED_KEYS_DIR" = "${NOBRAND_SSH_CONFIG_DIR}/authorized_keys" ] || return 1
  [ "$NOBRAND_SSH_ACCOUNT_MARKER_DIR" = "${NOBRAND_SSH_CONFIG_DIR}/accounts" ] || return 1
  safe_state="$(nb_assert_safe_nobrand_root "$NOBRAND_SSH_STATE_DIR" NOBRAND_SSH_STATE_DIR)" \
    || return 1
  safe_config="$(nb_assert_safe_nobrand_root "$NOBRAND_SSH_CONFIG_DIR" NOBRAND_SSH_CONFIG_DIR)" \
    || return 1
  [ "$safe_state" != "$safe_config" ] || return 1
  case "$safe_state" in "$safe_config"/*) return 1 ;; esac
  case "$safe_config" in "$safe_state"/*) return 1 ;; esac
  [ -d "$safe_state" ] && [ ! -L "$safe_state" ] || return 1
  [ -f "$NOBRAND_SSH_STATE_FILE" ] && [ ! -L "$NOBRAND_SSH_STATE_FILE" ] || return 1
  if [ -e "$safe_config" ] || [ -L "$safe_config" ]; then
    [ -d "$safe_config" ] && [ ! -L "$safe_config" ] || return 1
  fi
  if [ -e "$NOBRAND_SSH_WATCHDOG_DIR" ] || [ -L "$NOBRAND_SSH_WATCHDOG_DIR" ]; then
    [ -d "$NOBRAND_SSH_WATCHDOG_DIR" ] && [ ! -L "$NOBRAND_SSH_WATCHDOG_DIR" ] || return 1
    active="$(find "$NOBRAND_SSH_WATCHDOG_DIR" -mindepth 1 -maxdepth 1 \
      \( -name '*.armed' -o -name '*.running' \) -print -quit)" || return 1
    [ -z "$active" ] || return 1
  fi
}

ssh_tunnel_finalization_state_valid() {
  local expected_operation="${1:-}" pending token pid origin policy
  ssh_tunnel_state_identity_valid || return 1
  pending="$(ssh_tunnel_state_field pending_operation 2>/dev/null || true)"
  token="$(ssh_tunnel_state_field pending_watchdog_token 2>/dev/null || true)"
  pid="$(ssh_tunnel_state_field pending_watchdog_pid 2>/dev/null || true)"
  origin="$(ssh_tunnel_state_field pending_origin_connection 2>/dev/null || true)"
  policy="$(ssh_tunnel_state_field policy_applied 2>/dev/null || true)"
  [ "$policy" = false ] && [ -z "$token" ] && [ -z "$pid" ] && [ -z "$origin" ] || return 1
  case "$pending" in ''|uninstall|unified-uninstall) ;; *) return 1 ;; esac
  if [ -n "$expected_operation" ] && [ -n "$pending" ]; then
    [ "$expected_operation" = "$pending" ] || return 1
  fi
  ssh_tunnel_policy_absent || return 1
  ssh_tunnel_uninstall_roots_valid
}

ssh_tunnel_finalization_identities_valid() {
  local user_json linux_user present_users=0
  while IFS= read -r user_json; do
    linux_user="$(jq -r .linux_user <<<"$user_json")"
    if _has_user "$linux_user"; then
      present_users=$((present_users + 1))
      ssh_tunnel_user_identity_valid "$user_json" || return 1
    fi
  done < <(jq -c '.users[]?' "$NOBRAND_SSH_STATE_FILE")
  if _has_group "$NOBRAND_SSH_GROUP"; then
    ssh_tunnel_group_identity_valid || return 1
  else
    [ "$present_users" -eq 0 ] || return 1
  fi
}

ssh_tunnel_clear_managed_directory() {
  local root="$1"
  if [ ! -e "$root" ] && [ ! -L "$root" ]; then
    return 0
  fi
  [ -d "$root" ] && [ ! -L "$root" ] || return 1
  find "$root" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + || return 1
  rmdir "$root" 2>/dev/null || [ ! -e "$root" ]
}

ssh_tunnel_clear_state_payload() {
  local remaining=""
  find "$NOBRAND_SSH_STATE_DIR" -mindepth 1 -maxdepth 1 \
    ! -path "$NOBRAND_SSH_STATE_FILE" -exec rm -rf -- {} + || return 1
  remaining="$(find "$NOBRAND_SSH_STATE_DIR" -mindepth 1 -maxdepth 1 \
    ! -path "$NOBRAND_SSH_STATE_FILE" -print -quit)" || return 1
  [ -z "$remaining" ]
}

ssh_tunnel_finalize_uninstall() {
  local expected_operation="${1:-}" user_json linux_user uid deleted_count=0 checkpoint_rc=0
  local state_snapshot=""
  ssh_tunnel_watchdog_mutation_preflight || return $?
  ssh_tunnel_finalization_state_valid "$expected_operation" \
    || die 'SSH Tunnel 卸载状态、受管策略或路径不一致，拒绝删除'
  # Validate every still-present identity before the first mutation. Missing
  # state-listed identities are already removed; an unrelated user reusing an
  # old UID is deliberately ignored.
  ssh_tunnel_finalization_identities_valid \
    || die 'SSH Tunnel 用户或用户组身份不匹配，拒绝删除'
  while IFS= read -r user_json; do
    linux_user="$(jq -r .linux_user <<<"$user_json")"
    _has_user "$linux_user" || continue
    # Revalidate immediately before signalling or deleting the account so a
    # replaced same-name identity is never acted upon.
    ssh_tunnel_user_identity_valid "$user_json" \
      || die 'SSH Tunnel 用户身份在卸载期间发生变化，拒绝继续'
    uid="$(jq -r .uid <<<"$user_json")"
    pkill -KILL -u "$uid" 2>/dev/null || true
    ssh_tunnel_delete_linux_user "$linux_user" || return 1
    deleted_count=$((deleted_count + 1))
    if [ "$deleted_count" -eq 1 ]; then
      ssh_tunnel_uninstall_checkpoint after-first-user-deletion || checkpoint_rc=$?
      [ "$checkpoint_rc" -eq 0 ] || return "$checkpoint_rc"
    fi
  done < <(jq -c '.users[]?' "$NOBRAND_SSH_STATE_FILE")
  if _has_group "$NOBRAND_SSH_GROUP"; then
    ssh_tunnel_group_identity_valid \
      || die 'SSH Tunnel 用户组身份在卸载期间发生变化，拒绝继续'
    ssh_tunnel_delete_group || return 1
    ssh_tunnel_uninstall_checkpoint after-group-deletion || checkpoint_rc=$?
    [ "$checkpoint_rc" -eq 0 ] || return "$checkpoint_rc"
  fi
  # Account markers and authorized keys remain as ownership proof until all
  # identities are gone. Then remove config first and authoritative state last.
  ssh_tunnel_clear_managed_directory "$NOBRAND_SSH_CONFIG_DIR" || return 1
  ssh_tunnel_clear_state_payload || return 1
  ssh_tunnel_uninstall_checkpoint before-state-removal || checkpoint_rc=$?
  [ "$checkpoint_rc" -eq 0 ] || return "$checkpoint_rc"
  state_snapshot="$(mktemp_file .ssh-final-state)" || return 1
  cp -a "$NOBRAND_SSH_STATE_FILE" "$state_snapshot" || {
    rm -f "$state_snapshot"
    return 1
  }
  if ! rm -f "$NOBRAND_SSH_STATE_FILE"; then
    rm -f "$state_snapshot"
    return 1
  fi
  if ! rmdir "$NOBRAND_SSH_STATE_DIR" 2>/dev/null; then
    if [ -e "$NOBRAND_SSH_STATE_DIR" ]; then
      nb_atomic_install_file "$state_snapshot" "$NOBRAND_SSH_STATE_FILE" 0600 \
        || warn 'SSH Tunnel 状态根目录清理失败，且权威状态文件恢复失败'
      rm -f "$state_snapshot"
      return 1
    fi
  fi
  rm -f "$state_snapshot"
  t '已删除 NoBrand SSH Tunnel；系统 sshd、端口、防火墙、主机密钥与管理员访问均保留' \
    'Removed NoBrand SSH Tunnel; system sshd/port/firewall/host keys/admin access are preserved'
}

ssh_tunnel_uninstall() {
  local operation="${1:-uninstall}" pending token pid origin policy user_json
  require_root
  case "$operation" in uninstall|unified-uninstall) ;; *) die 'SSH Tunnel 卸载操作无效' ;; esac
  if ! ssh_tunnel_state_exists; then
    ssh_tunnel_state_absent \
      && { t 'SSH Tunnel 未安装' 'SSH Tunnel is not installed'; return 0; }
    die 'SSH Tunnel 权威状态损坏或无法读取，拒绝卸载'
  fi
  ssh_tunnel_state_identity_valid || die 'SSH Tunnel 状态无效，拒绝卸载'
  pending="$(ssh_tunnel_state_field pending_operation 2>/dev/null || true)"
  token="$(ssh_tunnel_state_field pending_watchdog_token 2>/dev/null || true)"
  pid="$(ssh_tunnel_state_field pending_watchdog_pid 2>/dev/null || true)"
  origin="$(ssh_tunnel_state_field pending_origin_connection 2>/dev/null || true)"
  policy="$(ssh_tunnel_state_field policy_applied 2>/dev/null || true)"
  if [ "$pending" = uninstall ] || [ "$pending" = unified-uninstall ]; then
    [ "$pending" = "$operation" ] || die 'SSH Tunnel 卸载必须由原始生命周期操作继续'
    if [ -n "$token" ]; then
      ssh_tunnel_pending_tuple_valid "$pending" "$token" "$pid" "$origin" "$policy" \
        || die 'SSH Tunnel 待确认卸载状态不一致'
      if [ "$token" = disabled ]; then
        ssh_tunnel_confirm_admin disabled
      else
        ssh_tunnel_watchdog_prompt "$token"
      fi
      return $?
    fi
    [ "$policy" = false ] && [ -z "$pid" ] && [ -z "$origin" ] \
      || die 'SSH Tunnel 已确认卸载状态不一致'
    ssh_tunnel_finalize_uninstall "$operation"
    return $?
  fi
  [ -z "$pending" ] || die "SSH 策略仍有待确认操作: $pending"
  [ -z "$token" ] && [ -z "$pid" ] && [ -z "$origin" ] \
    || die 'SSH Tunnel watchdog 状态不一致，拒绝卸载'
  if [ "$policy" = false ]; then
    # Compatibility recovery for a post-confirm state written by an older
    # candidate before it durably retained pending_operation.
    ssh_tunnel_finalize_uninstall "$operation"
    return $?
  fi
  [ "$policy" = true ] || die 'SSH Tunnel 策略状态无效，拒绝卸载'
  while IFS= read -r user_json; do
    ssh_tunnel_user_identity_valid "$user_json" \
      || die 'SSH Tunnel 用户身份不匹配，拒绝卸载'
  done < <(jq -c '.users[]?' "$NOBRAND_SSH_STATE_FILE")
  ssh_tunnel_group_identity_valid || die 'SSH Tunnel 用户组身份不匹配，拒绝卸载'
  ssh_tunnel_remove_policy "$operation"
}

nobrand_run_ssh_tunnel_action() {
  case "${SSH_TUNNEL_ACTION:-menu}" in
    install)
      if [ "${NOBRAND_MANAGER_SESSION_ACTIVE:-0}" -eq 1 ]; then
        nb_lifecycle_run_protocol_install ssh-tunnel ssh_tunnel_install
      else
        ssh_tunnel_install
      fi
      ;;
    status) ssh_tunnel_status ;;
    doctor) ssh_tunnel_doctor ;;
    show) ssh_tunnel_show_user "${SSH_TUNNEL_USER:-}" ;;
    export) ssh_tunnel_export_user "${SSH_TUNNEL_USER:-}" ;;
    set-endpoint) ssh_tunnel_set_endpoint_state "${ADVERTISE_HOST:-}" "${ADVERTISE_PORT:-}" ;;
    confirm-admin) ssh_tunnel_confirm_admin "$SSH_TUNNEL_WATCHDOG_TOKEN" ;;
    user-list) ssh_tunnel_user_list ;;
    user-add) ssh_tunnel_add_user_internal "$SSH_TUNNEL_USER" >/dev/null ;;
    user-show) ssh_tunnel_show_user "$SSH_TUNNEL_USER" ;;
    user-export) ssh_tunnel_export_user "$SSH_TUNNEL_USER" ;;
    user-rotate-key) ssh_tunnel_rotate_user_key "$SSH_TUNNEL_USER" ;;
    user-delete) ssh_tunnel_delete_user_internal "$SSH_TUNNEL_USER" ;;
    uninstall) ssh_tunnel_uninstall ;;
    menu) ssh_tunnel_status ;;
    help)
      cat <<'EOF'
nobrand ssh install|status|doctor|show|export|set-endpoint|uninstall
nobrand ssh user add|delete|list|show|rotate-key
SSH Tunnel 复用现有 OpenSSH sshd，仅允许 -L/-D/-R TCP 转发。
EOF
      ;;
    *) die "未知 SSH Tunnel 操作: ${SSH_TUNNEL_ACTION}" ;;
  esac
}

# ---------- Port Forward: nftables kernel NAT + official Realm relay ----------

forward_now() {
  date -u +%Y-%m-%dT%H:%M:%SZ
}

forward_normalize_protocol() {
  case "$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')" in
    tcp) printf 'tcp' ;;
    udp) printf 'udp' ;;
    both|tcp+udp|tcp/udp|dual|all) printf 'both' ;;
    *) return 1 ;;
  esac
}

forward_protocol_transports() {
  case "$(forward_normalize_protocol "${1:-}")" in
    tcp) printf 'TCP\n' ;;
    udp) printf 'UDP\n' ;;
    both) printf 'TCP\nUDP\n' ;;
  esac
}

forward_valid_ipv4() {
  local value="${1:-}" a b c d extra segment
  IFS=. read -r a b c d extra <<<"$value"
  [ -z "${extra:-}" ] && [ -n "${d:-}" ] || return 1
  for segment in "$a" "$b" "$c" "$d"; do
    [[ "$segment" =~ ^[0-9]{1,3}$ ]] || return 1
    [ "$((10#$segment))" -le 255 ] || return 1
  done
}

forward_target_valid() {
  local backend="${1:-}" target="${2:-}"
  case "$backend" in
    nftables) forward_valid_ipv4 "$target" ;;
    realm)
      valid_ip_literal "$target" && return 0
      # An IPv4-looking value must be a valid literal; do not reinterpret a
      # malformed address such as 999.2.3.4 as a DNS name.
      [[ "$target" =~ ^[0-9.]+$ ]] && return 1
      valid_domain_name "$target"
      ;;
    *) return 1 ;;
  esac
}

forward_listen_host_valid() {
  local backend="${1:-}" host="${2:-}"
  case "$backend" in
    nftables) forward_valid_ipv4 "$host" ;;
    realm) valid_ip_literal "$host" ;;
    *) return 1 ;;
  esac
}

forward_socket_address_normalize() {
  local value="${1:-}" host port
  [ -n "$value" ] && ! has_control_chars "$value" || return 1
  case "$value" in
    \[*\]:*)
      host="${value#\[}"
      host="${host%%\]*}"
      port="${value##*\]:}"
      [ "$value" = "[${host}]:${port}" ] || return 1
      [[ "$host" == *:* ]] && valid_ip_literal "$host" || return 1
      ;;
    *:*)
      host="${value%:*}"
      port="${value##*:}"
      [ -n "$host" ] || return 1
      valid_ip_literal "$host" || valid_domain_name "$host" || return 1
      ;;
    *) return 1 ;;
  esac
  nb_valid_port "$port" || return 1
  port="$(normalize_uint "$port")" || return 1
  if [[ "$host" == *:* ]]; then
    printf '[%s]:%s' "$host" "$port"
  else
    printf '%s:%s' "$host" "$port"
  fi
}

forward_socket_address_valid() {
  forward_socket_address_normalize "${1:-}" >/dev/null
}

forward_realm_options_valid_json() {
  local options="${1:-}" through interface listen_interface listen_transport remote_transport item
  jq -e '
    (type=="object") and
    (keys|sort)==["balance","dns_mode","dns_nameservers","dns_protocol","extra_targets",
      "interface","listen_interface","listen_transport","proxy_accept","proxy_accept_timeout",
      "proxy_send","proxy_version","remote_transport","tcp_timeout","through","udp_timeout","weights"] and
    (.through|type)=="string" and (.interface|type)=="string" and
    (.listen_interface|type)=="string" and
    (.tcp_timeout|type)=="number" and (.tcp_timeout|floor)==.tcp_timeout and
      .tcp_timeout>=0 and .tcp_timeout<=86400 and
    (.udp_timeout|type)=="number" and (.udp_timeout|floor)==.udp_timeout and
      .udp_timeout>=1 and .udp_timeout<=86400 and
    (.proxy_send|type)=="boolean" and (.proxy_accept|type)=="boolean" and
    (.proxy_version==1 or .proxy_version==2) and
    (.proxy_accept_timeout|type)=="number" and
      (.proxy_accept_timeout|floor)==.proxy_accept_timeout and
      .proxy_accept_timeout>=0 and .proxy_accept_timeout<=86400 and
    (.dns_mode=="system" or .dns_mode=="ipv4_only" or .dns_mode=="ipv6_only" or
      .dns_mode=="ipv4_then_ipv6" or .dns_mode=="ipv6_then_ipv4" or .dns_mode=="ipv4_and_ipv6") and
    (.dns_protocol=="tcp" or .dns_protocol=="udp" or .dns_protocol=="tcp_and_udp") and
    (.dns_nameservers|type)=="array" and
      all(.dns_nameservers[]; type=="string" and length>0 and length<=300 and (test("[[:space:]]")|not)) and
    (.listen_transport|type)=="string" and (.listen_transport|length)<=1024 and
    (.remote_transport|type)=="string" and (.remote_transport|length)<=1024 and
    (.extra_targets|type)=="array" and
      all(.extra_targets[]; type=="string" and length>0 and length<=300 and (test("[[:space:]]")|not)) and
    (.balance=="off" or .balance=="roundrobin" or .balance=="iphash") and
    (.weights|type)=="array" and
      all(.weights[]; type=="number" and floor==. and .>=1 and .<=255) and
    (if .balance=="off" then
       (.extra_targets|length)==0 and (.weights|length)==0
     else
       (.extra_targets|length)>0 and (.weights|length)==(1+(.extra_targets|length))
     end)
  ' <<<"$options" >/dev/null || return 1
  through="$(jq -r .through <<<"$options")"
  [ -z "$through" ] || valid_ip_literal "$through" || return 1
  interface="$(jq -r .interface <<<"$options")"
  listen_interface="$(jq -r .listen_interface <<<"$options")"
  for item in "$interface" "$listen_interface"; do
    [ -z "$item" ] || [[ "$item" =~ ^[A-Za-z0-9_.:-]{1,64}$ ]] || return 1
  done
  listen_transport="$(jq -r .listen_transport <<<"$options")"
  remote_transport="$(jq -r .remote_transport <<<"$options")"
  ! has_control_chars "$listen_transport" && ! has_control_chars "$remote_transport" || return 1
  while IFS= read -r item; do
    forward_socket_address_valid "$item" || return 1
  done < <(jq -r '.dns_nameservers[]' <<<"$options")
  while IFS= read -r item; do
    forward_socket_address_valid "$item" || return 1
  done < <(jq -r '.extra_targets[]' <<<"$options")
}

forward_port_allowed() {
  local port="${1:-}" protocol transport ignore_owner="${3:-}" profile_id="${4:-${INGRESS_PROFILE_ID:-$NOBRAND_LEGACY_INGRESS_PROFILE_ID}}"
  protocol="$(forward_normalize_protocol "${2:-}")" || return 1
  nb_valid_port "$port" || return 1
  nb_ingress_port_is_reserved "$profile_id" "$port" && return 1
  while IFS= read -r transport; do
    nb_port_available_for_profile "$port" "$transport" "$profile_id" "$ignore_owner" || return 1
  done < <(forward_protocol_transports "$protocol")
}

forward_select_available_port() {
  local protocol="$1" profile_id="$2" bounds lo hi selected
  bounds="$(nb_ingress_profile_auto_range "$profile_id" 2>/dev/null)" || return 1
  lo="${bounds%%|*}"; hi="${bounds#*|}"
  selected="$(nb_scan_port_span "$lo" "$hi" forward_port_allowed "$protocol" '' "$profile_id")" || return 1
  printf '%s' "$selected"
}

forward_init_state() {
  local tmp
  [ -e "$NOBRAND_FORWARD_STATE_FILE" ] && return 0
  mkdir -p "$NOBRAND_FORWARD_STATE_DIR" "$NOBRAND_FORWARD_CONFIG_DIR" || return 1
  chmod 0700 "$NOBRAND_FORWARD_STATE_DIR" "$NOBRAND_FORWARD_CONFIG_DIR" || return 1
  tmp="$(mktemp_file .forward-state)" || return 1
  jq -n --argjson schema "$NOBRAND_SCHEMA_VERSION" \
    '{schema_version:$schema,ownership:"nobrand-v3",feature:"port-forward",rules:[]}' >"$tmp" \
    && nb_atomic_install_file "$tmp" "$NOBRAND_FORWARD_STATE_FILE" 0600
  local rc=$?
  rm -f "$tmp"
  return "$rc"
}

forward_state_valid() {
  local state="${1:-$NOBRAND_FORWARD_STATE_FILE}" rule_id backend protocol listen_host options
  local listen_port target_host target_port display_mode display_host display_port transport key
  local forward_seen_ports=""
  [ -s "$state" ] && jq -e '
    (keys|sort)==["feature","ownership","rules","schema_version"] and
    .schema_version==3 and .ownership=="nobrand-v3" and .feature=="port-forward" and
    (.rules|type)=="array" and
    all(.rules[];
      ((keys-["ingress_profile_id","ingress_enforcement","ingress_enforcement_method","ingress_local_address"]|sort)==["backend","backend_options","created_at","display_host","display_mode",
                    "display_port","enabled","listen_host","listen_port","name","note",
                    "ownership_metadata","protocol","rule_id","target_host","target_port","updated_at"]) and
      ((has("ingress_profile_id")|not) or (.ingress_profile_id|type=="string" and length>0)) and
      ((has("ingress_enforcement")|not) or
        (.ingress_enforcement=="permissive" or .ingress_enforcement=="strict")) and
      ((has("ingress_enforcement_method")|not) or
        (.ingress_enforcement_method=="wildcard" or .ingress_enforcement_method=="native-bind" or
         .ingress_enforcement_method=="address-match")) and
      ((has("ingress_local_address")|not) or (.ingress_local_address|type=="string")) and
      (if (.ingress_enforcement // "permissive")=="strict" then
         (.ingress_local_address|type=="string" and length>0) and .listen_host==.ingress_local_address and
         (if .backend=="nftables" then .ingress_enforcement_method=="address-match"
          else .ingress_enforcement_method=="native-bind" end)
       else (.ingress_enforcement_method // "wildcard")=="wildcard" end) and
      (.rule_id|type)=="string" and (.rule_id|test("^f[0-9a-f]{16}$")) and
      (.name|type)=="string" and (.name|length)>0 and (.name|length)<=64 and
        (.name|test("[[:cntrl:]]")|not) and
      (.note|type)=="string" and (.note|length)<=256 and
        (.note|test("[[:cntrl:]]")|not) and
      (.backend=="nftables" or .backend=="realm") and (.enabled|type)=="boolean" and
      (.protocol=="tcp" or .protocol=="udp" or .protocol=="both") and
      (.listen_host|type)=="string" and (.listen_port|type)=="number" and
      (.target_host|type)=="string" and (.target_port|type)=="number" and
      (.display_host|type)=="string" and (.display_port|type)=="number" and
      (.display_mode=="auto" or .display_mode=="custom") and
      (.created_at|type)=="string" and (.created_at|test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")) and
      (.updated_at|type)=="string" and (.updated_at|test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")) and
      (.ownership_metadata|type)=="object" and
      (.ownership_metadata|keys|sort)==["managed_firewall","managed_listener"] and
      (.ownership_metadata.managed_listener|type)=="boolean" and
      (.ownership_metadata.managed_firewall|type)=="boolean" and
      (.backend_options|type)=="object" and
      (if .backend=="nftables" then
         (.backend_options|keys)==["source_mode"] and
         (.backend_options.source_mode=="masquerade" or .backend_options.source_mode=="preserve")
       else
         (.backend_options|keys|sort)==["balance","dns_mode","dns_nameservers","dns_protocol",
           "extra_targets","interface","listen_interface","listen_transport","proxy_accept",
           "proxy_accept_timeout","proxy_send","proxy_version","remote_transport","tcp_timeout",
           "through","udp_timeout","weights"] and
         (.backend_options.through|type)=="string" and
         (.backend_options.interface|type)=="string" and
         (.backend_options.listen_interface|type)=="string" and
         (.backend_options.tcp_timeout|type)=="number" and
         (.backend_options.udp_timeout|type)=="number" and
         (.backend_options.proxy_send|type)=="boolean" and
         (.backend_options.proxy_accept|type)=="boolean" and
         (.backend_options.proxy_version==1 or .backend_options.proxy_version==2) and
         (.backend_options.proxy_accept_timeout|type)=="number" and
         (.backend_options.dns_mode|type)=="string" and
         (.backend_options.dns_protocol|type)=="string" and
         (.backend_options.dns_nameservers|type)=="array" and
         (.backend_options.listen_transport|type)=="string" and
         (.backend_options.remote_transport|type)=="string" and
         (.backend_options.extra_targets|type)=="array" and
         (.backend_options.balance|type)=="string" and
         (.backend_options.weights|type)=="array"
       end)
    ) and
    ([.rules[].rule_id]|length)==([.rules[].rule_id]|unique|length) and
    ([.rules[].name]|length)==([.rules[].name]|unique|length) and
    ([.rules[] | . as $r |
       (if .protocol=="both" then ["TCP","UDP"] elif .protocol=="tcp" then ["TCP"] else ["UDP"] end)[] |
       "\(.)|\($r.listen_port)"] | length)==
    ([.rules[] | . as $r |
       (if .protocol=="both" then ["TCP","UDP"] elif .protocol=="tcp" then ["TCP"] else ["UDP"] end)[] |
       "\(.)|\($r.listen_port)"] | unique | length)
  ' "$state" >/dev/null || return 1

  while IFS=$'\x1f' read -r rule_id backend protocol listen_host listen_port target_host target_port \
    display_mode display_host display_port; do
    forward_listen_host_valid "$backend" "$listen_host" || return 1
    nb_valid_port "$listen_port" && nb_valid_port "$target_port" \
      && valid_advertise_port "$display_port" || return 1
    nb_port_is_tail_base_reserved "$listen_port" && return 1
    forward_target_valid "$backend" "$target_host" || return 1
    if [ "$backend" = realm ]; then
      options="$(jq -c --arg id "$rule_id" '.rules[]|select(.rule_id==$id)|.backend_options' "$state")" \
        || return 1
      forward_realm_options_valid_json "$options" || return 1
    fi
    if [ "$display_mode" = custom ]; then
      valid_advertise_host "$display_host" || return 1
    else
      [ -z "$display_host" ] || return 1
      [ "$display_port" -eq "$listen_port" ] || return 1
    fi
    while IFS= read -r transport; do
      key="${transport}|${listen_port}"
      [ -z "${forward_seen_ports:-}" ] || case "|$forward_seen_ports|" in *"|$key|"*) return 1 ;; esac
      forward_seen_ports="${forward_seen_ports:+${forward_seen_ports}|}${key}"
    done < <(forward_protocol_transports "$protocol")
  done < <(jq -r '.rules[] | [.rule_id,.backend,.protocol,.listen_host,(.listen_port|tostring),
    .target_host,(.target_port|tostring),.display_mode,.display_host,(.display_port|tostring)] | join("\u001f")' "$state")

  # Realm's DNS block is global. Multiple enabled Realm rules may share it,
  # but conflicting values are rejected instead of silently overriding peers.
  [ "$(jq -c '[.rules[] | select(.enabled and .backend=="realm") |
      [.backend_options.dns_mode,.backend_options.dns_protocol,.backend_options.dns_nameservers]] | unique | length' "$state")" -le 1 ] \
    || return 1
}

forward_rule_json() {
  local state="${1:-$NOBRAND_FORWARD_STATE_FILE}" id="$2"
  jq -c --arg id "$id" '.rules[] | select(.rule_id==$id or .name==$id)' "$state" | head -n1
}

forward_resolve_rule_id() {
  local value="${1:-}" state="${2:-$NOBRAND_FORWARD_STATE_FILE}" id
  id="$(jq -r --arg value "$value" '.rules[] | select(.rule_id==$value or .name==$value) | .rule_id' \
    "$state" 2>/dev/null | head -n1)"
  [ -n "$id" ] && [ "$id" != null ] || return 1
  printf '%s' "$id"
}

forward_generate_rule_id() {
  local material digest
  material="$(forward_now)|$$|${RANDOM}|${FORWARD_NAME:-forward}"
  if command -v sha256sum >/dev/null 2>&1; then
    digest="$(printf '%s' "$material" | sha256sum | awk '{print $1}')"
  else
    digest="$(printf '%s' "$material" | openssl dgst -sha256 | awk '{print $NF}')"
  fi
  printf 'f%s' "${digest:0:16}"
}

forward_toml_string() {
  jq -Rn --arg value "${1:-}" '$value'
}

forward_realm_address() {
  local host="$1" port="$2"
  case "$host" in
    *:*) printf '[%s]:%s' "$host" "$port" ;;
    *) printf '%s:%s' "$host" "$port" ;;
  esac
}

forward_generate_realm_config() {
  local state="$1" output="$2" tmp dns_json mode dns_protocol nameservers
  local rule_id protocol listen_host listen_port target_host target_port options
  local no_tcp use_udp through interface listen_interface listen_transport remote_transport
  local tcp_timeout udp_timeout proxy_send proxy_accept proxy_version proxy_accept_timeout
  local extra_targets balance weights endpoint target count
  forward_state_valid "$state" || return 1
  tmp="$(mktemp_file .realm.toml)" || return 1
  {
    printf '# Generated by NoBrand-OneClick; display endpoint metadata is intentionally excluded.\n'
    printf '[log]\nlevel = "warn"\noutput = "stdout"\n\n'
    dns_json="$(jq -c '[.rules[] | select(.enabled and .backend=="realm")][0].backend_options // empty' "$state")"
    if [ -n "$dns_json" ]; then
      mode="$(jq -r '.dns_mode' <<<"$dns_json")"
      dns_protocol="$(jq -r '.dns_protocol' <<<"$dns_json")"
      nameservers="$(jq -c '.dns_nameservers' <<<"$dns_json")"
      if [ "$mode" != system ] || [ "$nameservers" != '[]' ]; then
        printf '[dns]\n'
        [ "$mode" = system ] || printf 'mode = %s\n' "$(forward_toml_string "$mode")"
        printf 'protocol = %s\n' "$(forward_toml_string "$dns_protocol")"
        [ "$nameservers" = '[]' ] || printf 'nameservers = %s\n' "$nameservers"
        printf '\n'
      fi
    fi
    while IFS=$'\t' read -r rule_id protocol listen_host listen_port target_host target_port options; do
      [ -n "$rule_id" ] || continue
      case "$protocol" in
        tcp) no_tcp=false; use_udp=false ;;
        udp) no_tcp=true; use_udp=true ;;
        both) no_tcp=false; use_udp=true ;;
      esac
      endpoint="$(forward_realm_address "$listen_host" "$listen_port")"
      target="$(forward_realm_address "$target_host" "$target_port")"
      through="$(jq -r '.through' <<<"$options")"
      interface="$(jq -r '.interface' <<<"$options")"
      listen_interface="$(jq -r '.listen_interface' <<<"$options")"
      listen_transport="$(jq -r '.listen_transport' <<<"$options")"
      remote_transport="$(jq -r '.remote_transport' <<<"$options")"
      tcp_timeout="$(jq -r '.tcp_timeout' <<<"$options")"
      udp_timeout="$(jq -r '.udp_timeout' <<<"$options")"
      proxy_send="$(jq -r '.proxy_send' <<<"$options")"
      proxy_accept="$(jq -r '.proxy_accept' <<<"$options")"
      proxy_version="$(jq -r '.proxy_version' <<<"$options")"
      proxy_accept_timeout="$(jq -r '.proxy_accept_timeout' <<<"$options")"
      extra_targets="$(jq -c '.extra_targets' <<<"$options")"
      balance="$(jq -r '.balance' <<<"$options")"
      weights="$(jq -c '.weights' <<<"$options")"
      printf '[[endpoints]]\nlisten = %s\nremote = %s\n' \
        "$(forward_toml_string "$endpoint")" "$(forward_toml_string "$target")"
      if [ "$extra_targets" != '[]' ]; then
        printf 'extra_remotes = %s\n' "$extra_targets"
      fi
      if [ "$balance" != off ]; then
        count="$(jq 'length' <<<"$weights")"
        [ "$count" -gt 0 ] || { rm -f "$tmp"; return 1; }
        printf 'balance = %s\n' "$(forward_toml_string "${balance}: $(jq -r 'map(tostring)|join(", ")' <<<"$weights")")"
      fi
      [ -z "$through" ] || printf 'through = %s\n' "$(forward_toml_string "$through")"
      [ -z "$interface" ] || printf 'interface = %s\n' "$(forward_toml_string "$interface")"
      [ -z "$listen_interface" ] || printf 'listen_interface = %s\n' "$(forward_toml_string "$listen_interface")"
      [ -z "$listen_transport" ] || printf 'listen_transport = %s\n' "$(forward_toml_string "$listen_transport")"
      [ -z "$remote_transport" ] || printf 'remote_transport = %s\n' "$(forward_toml_string "$remote_transport")"
      printf '[endpoints.network]\nno_tcp = %s\nuse_udp = %s\n' "$no_tcp" "$use_udp"
      printf 'tcp_timeout = %s\nudp_timeout = %s\n' "$tcp_timeout" "$udp_timeout"
      printf 'send_proxy = %s\nsend_proxy_version = %s\n' "$proxy_send" "$proxy_version"
      printf 'accept_proxy = %s\naccept_proxy_timeout = %s\n\n' "$proxy_accept" "$proxy_accept_timeout"
    done < <(jq -r '.rules | sort_by(.rule_id)[] | select(.enabled and .backend=="realm") |
      [.rule_id,.protocol,.listen_host,(.listen_port|tostring),.target_host,(.target_port|tostring),
       (.backend_options|tojson)] | @tsv' "$state")
  } >"$tmp" || { rm -f "$tmp"; return 1; }
  mkdir -p "$(dirname "$output")" || { rm -f "$tmp"; return 1; }
  install -m 0600 "$tmp" "$output"
  local rc=$?
  rm -f "$tmp"
  return "$rc"
}

forward_generate_nft_ruleset() {
  local state="$1" output="$2" tmp rule_id protocol listen_host listen_port
  local target_host target_port source_mode transport proto match_host original_match_host
  forward_state_valid "$state" || return 1
  tmp="$(mktemp_file .nft)" || return 1
  {
    printf 'table ip %s {\n' "$NOBRAND_FORWARD_NFT_TABLE"
    printf '  comment "Owned by NoBrand-OneClick Port Forward"\n'
    printf '  chain prerouting {\n    type nat hook prerouting priority dstnat; policy accept;\n'
    while IFS=$'\t' read -r rule_id protocol listen_host listen_port target_host target_port source_mode; do
      [ -n "$rule_id" ] || continue
      match_host=""
      [ "$listen_host" = 0.0.0.0 ] || match_host="ip daddr ${listen_host} "
      while IFS= read -r transport; do
        proto="$(printf '%s' "$transport" | tr '[:upper:]' '[:lower:]')"
        printf '    %s%s dport %s counter dnat to %s:%s comment "nobrand:%s:dnat:%s"\n' \
          "$match_host" "$proto" "$listen_port" "$target_host" "$target_port" "$rule_id" "$proto"
      done < <(forward_protocol_transports "$protocol")
    done < <(jq -r '.rules | sort_by(.rule_id)[] | select(.enabled and .backend=="nftables") |
      [.rule_id,.protocol,.listen_host,(.listen_port|tostring),.target_host,(.target_port|tostring),
       .backend_options.source_mode] | @tsv' "$state")
    printf '  }\n'
    printf '  chain postrouting {\n    type nat hook postrouting priority srcnat; policy accept;\n'
    while IFS=$'\t' read -r rule_id protocol listen_host listen_port target_host target_port source_mode; do
      [ "$source_mode" = masquerade ] || continue
      original_match_host=""
      [ "$listen_host" = 0.0.0.0 ] || original_match_host="ct original ip daddr ${listen_host} "
      while IFS= read -r transport; do
        proto="$(printf '%s' "$transport" | tr '[:upper:]' '[:lower:]')"
        printf '    meta l4proto %s %sct original proto-dst %s ip daddr %s %s dport %s counter masquerade comment "nobrand:%s:snat:%s"\n' \
          "$proto" "$original_match_host" "$listen_port" "$target_host" "$proto" "$target_port" "$rule_id" "$proto"
      done < <(forward_protocol_transports "$protocol")
    done < <(jq -r '.rules | sort_by(.rule_id)[] | select(.enabled and .backend=="nftables") |
      [.rule_id,.protocol,.listen_host,(.listen_port|tostring),.target_host,(.target_port|tostring),
       .backend_options.source_mode] | @tsv' "$state")
    printf '  }\n'
    printf '  chain forward {\n    type filter hook forward priority -10; policy accept;\n'
    while IFS=$'\t' read -r rule_id protocol listen_host listen_port target_host target_port source_mode; do
      original_match_host=""
      [ "$listen_host" = 0.0.0.0 ] || original_match_host="ct original ip daddr ${listen_host} "
      while IFS= read -r transport; do
        proto="$(printf '%s' "$transport" | tr '[:upper:]' '[:lower:]')"
        printf '    meta l4proto %s %sct original proto-dst %s ip daddr %s %s dport %s ct status dnat counter accept comment "nobrand:%s:forward:%s"\n' \
          "$proto" "$original_match_host" "$listen_port" "$target_host" "$proto" "$target_port" "$rule_id" "$proto"
      done < <(forward_protocol_transports "$protocol")
    done < <(jq -r '.rules | sort_by(.rule_id)[] | select(.enabled and .backend=="nftables") |
      [.rule_id,.protocol,.listen_host,(.listen_port|tostring),.target_host,(.target_port|tostring),
       .backend_options.source_mode] | @tsv' "$state")
    printf '  }\n}\n'
  } >"$tmp" || { rm -f "$tmp"; return 1; }
  mkdir -p "$(dirname "$output")" || { rm -f "$tmp"; return 1; }
  install -m 0600 "$tmp" "$output"
  local rc=$?
  rm -f "$tmp"
  return "$rc"
}

forward_set_endpoint_state() {
  local selector="$1" mode="$2" host="${3:-}" port="${4:-}" id tmp
  id="$(forward_resolve_rule_id "$selector")" || return 1
  case "$mode" in
    auto)
      host=""
      port="$(jq -r --arg id "$id" '.rules[]|select(.rule_id==$id)|.listen_port' "$NOBRAND_FORWARD_STATE_FILE")"
      ;;
    custom)
      valid_advertise_host "$host" && valid_advertise_port "$port" || return 1
      ;;
    *) return 1 ;;
  esac
  tmp="$(mktemp_file .forward-endpoint)" || return 1
  jq --arg id "$id" --arg mode "$mode" --arg host "$host" --argjson port "$(normalize_uint "$port")" \
    --arg now "$(forward_now)" '
      (.rules[]|select(.rule_id==$id)) |=
        (.display_mode=$mode|.display_host=$host|.display_port=$port|.updated_at=$now)
    ' "$NOBRAND_FORWARD_STATE_FILE" >"$tmp" \
    && forward_state_valid "$tmp" \
    && nb_atomic_install_file "$tmp" "$NOBRAND_FORWARD_STATE_FILE" 0600
  local rc=$?
  rm -f "$tmp"
  return "$rc"
}

forward_export_json() {
  local output="${1:-}" tmp
  tmp="$(mktemp_file .forward-export)" || return 1
  jq --arg exported_at "$(forward_now)" '
    {format:"nobrand-forward-export",format_version:1,schema_version:3,
     ownership:"nobrand-v3",exported_at:$exported_at,rules:.rules}
  ' "$NOBRAND_FORWARD_STATE_FILE" >"$tmp" || { rm -f "$tmp"; return 1; }
  if [ -n "$output" ] && [ "$output" != - ]; then
    mkdir -p "$(dirname "$output")" 2>/dev/null || true
    install -m 0600 "$tmp" "$output"
  else
    cat "$tmp"
  fi
  local rc=$?
  rm -f "$tmp"
  return "$rc"
}

forward_import_validate() {
  local input="$1" candidate
  [ -s "$input" ] || return 1
  jq -e '
    (keys|sort)==["exported_at","format","format_version","ownership","rules","schema_version"] and
    .format=="nobrand-forward-export" and .format_version==1 and
    .schema_version==3 and .ownership=="nobrand-v3" and
    (.exported_at|type)=="string" and (.rules|type)=="array"
  ' "$input" >/dev/null || return 1
  candidate="$(mktemp_file .forward-import-state)" || return 1
  jq '{schema_version:.schema_version,ownership:.ownership,feature:"port-forward",rules:.rules}' \
    "$input" >"$candidate" && forward_state_valid "$candidate"
  local rc=$?
  rm -f "$candidate"
  return "$rc"
}

forward_sysctl_snapshot() {
  local snapshot="$1" value
  mkdir -p "$snapshot" || return 1
  if [ -e "$NOBRAND_FORWARD_SYSCTL_STATE" ]; then
    cp -a "$NOBRAND_FORWARD_SYSCTL_STATE" "$snapshot/state.json" || return 1
  else
    : >"$snapshot/state.absent" || return 1
  fi
  if [ -e "$NOBRAND_FORWARD_SYSCTL_FRAGMENT" ]; then
    cp -a "$NOBRAND_FORWARD_SYSCTL_FRAGMENT" "$snapshot/fragment" || return 1
  else
    : >"$snapshot/fragment.absent" || return 1
  fi
  if command -v sysctl >/dev/null 2>&1; then
    value="$(sysctl -n net.ipv4.ip_forward 2>/dev/null)" || return 1
  elif [ -r /proc/sys/net/ipv4/ip_forward ]; then
    value="$(cat /proc/sys/net/ipv4/ip_forward 2>/dev/null)" || return 1
  else
    return 1
  fi
  value="$(printf '%s' "$value" | tr -d '[:space:]')" || return 1
  case "$value" in 0|1) ;; *) return 1 ;; esac
  printf '%s\n' "$value" >"$snapshot/live-value" || return 1
}

forward_sysctl_state_valid() {
  local state="${1:-$NOBRAND_FORWARD_SYSCTL_STATE}"
  [ -s "$state" ] && jq -e '
    (keys|sort)==["active_rules","changed_by_nobrand","fragment_owned","key","original_value","ownership","schema_version"] and
    .schema_version==3 and .ownership=="nobrand-v3" and .key=="net.ipv4.ip_forward" and
    (.original_value==0 or .original_value==1) and
    (.changed_by_nobrand|type)=="boolean" and
    (.active_rules|type)=="number" and (.active_rules|floor)==.active_rules and .active_rules>=0 and
    .fragment_owned==true
  ' "$state" >/dev/null
}

forward_sysctl_fragment_owned() {
  local fragment="${1:-$NOBRAND_FORWARD_SYSCTL_FRAGMENT}"
  [ -f "$fragment" ] && [ ! -L "$fragment" ] \
    && [ "$(wc -l <"$fragment" | tr -d '[:space:]')" = 2 ] \
    && [ "$(sed -n '1p' "$fragment")" = '# Owned by NoBrand-OneClick Port Forward' ] \
    && [ "$(sed -n '2p' "$fragment")" = 'net.ipv4.ip_forward = 1' ]
}

forward_sysctl_restore_snapshot() {
  local snapshot="$1" value="" failed=0
  if [ -e "$snapshot/state.json" ]; then
    nb_atomic_install_file "$snapshot/state.json" "$NOBRAND_FORWARD_SYSCTL_STATE" 0600 || failed=1
  elif [ -f "$snapshot/state.absent" ] && [ ! -L "$snapshot/state.absent" ]; then
    rm -f "$NOBRAND_FORWARD_SYSCTL_STATE" || failed=1
  else
    failed=1
  fi
  if [ -e "$snapshot/fragment" ]; then
    nb_atomic_install_file "$snapshot/fragment" "$NOBRAND_FORWARD_SYSCTL_FRAGMENT" 0644 || failed=1
  elif [ -f "$snapshot/fragment.absent" ] && [ ! -L "$snapshot/fragment.absent" ]; then
    rm -f "$NOBRAND_FORWARD_SYSCTL_FRAGMENT" || failed=1
  else
    failed=1
  fi
  if [ -f "$snapshot/live-value" ] && [ ! -L "$snapshot/live-value" ]; then
    value="$(tr -d '[:space:]' <"$snapshot/live-value" 2>/dev/null)" || failed=1
  else
    failed=1
  fi
  case "$value" in
    0|1)
      if command -v sysctl >/dev/null 2>&1; then
        sysctl -q -w "net.ipv4.ip_forward=${value}" >/dev/null || failed=1
      elif [ -w /proc/sys/net/ipv4/ip_forward ]; then
        printf '%s\n' "$value" >/proc/sys/net/ipv4/ip_forward || failed=1
      else
        failed=1
      fi
      ;;
    *) failed=1 ;;
  esac
  [ "$failed" -eq 0 ]
}

forward_sysctl_reconcile() {
  local state="$1" count current original changed fragment_owned tmp
  count="$(jq '[.rules[]|select(.enabled and .backend=="nftables")]|length' "$state")" || return 1
  command -v sysctl >/dev/null 2>&1 || { [ "$count" -eq 0 ]; return; }
  current="$(sysctl -n net.ipv4.ip_forward 2>/dev/null | tr -d '[:space:]')"
  case "$current" in 0|1) ;; *) return 1 ;; esac
  if [ "$count" -gt 0 ]; then
    if [ -s "$NOBRAND_FORWARD_SYSCTL_STATE" ]; then
      forward_sysctl_state_valid "$NOBRAND_FORWARD_SYSCTL_STATE" || return 1
      # Unified backup contains NoBrand state/config, while this runtime
      # fragment lives under /etc/sysctl.d and is recreated during restore.
      # A valid ownership state may therefore legitimately outlive a missing
      # fragment.  Recreate only when the path is truly absent; any existing
      # file or symlink must still match the exact NoBrand marker/content.
      if [ -e "$NOBRAND_FORWARD_SYSCTL_FRAGMENT" ] \
         || [ -L "$NOBRAND_FORWARD_SYSCTL_FRAGMENT" ]; then
        forward_sysctl_fragment_owned "$NOBRAND_FORWARD_SYSCTL_FRAGMENT" || return 1
      fi
      original="$(jq -r '.original_value' "$NOBRAND_FORWARD_SYSCTL_STATE")"
      changed="$(jq -r '.changed_by_nobrand' "$NOBRAND_FORWARD_SYSCTL_STATE")"
    else
      [ ! -e "$NOBRAND_FORWARD_SYSCTL_FRAGMENT" ] || return 1
      original="$current"
      changed=false
    fi
    if [ "$current" -ne 1 ]; then
      sysctl -q -w net.ipv4.ip_forward=1 >/dev/null || return 1
      changed=true
    fi
    tmp="$(mktemp_file .forward-sysctl)" || return 1
    printf '# Owned by NoBrand-OneClick Port Forward\nnet.ipv4.ip_forward = 1\n' >"$tmp"
    nb_atomic_install_file "$tmp" "$NOBRAND_FORWARD_SYSCTL_FRAGMENT" 0644 || { rm -f "$tmp"; return 1; }
    rm -f "$tmp"
    tmp="$(mktemp_file .forward-sysctl-state)" || return 1
    jq -n --argjson original "$original" --argjson changed "$changed" --argjson users "$count" \
      '{schema_version:3,ownership:"nobrand-v3",key:"net.ipv4.ip_forward",
        original_value:$original,changed_by_nobrand:$changed,active_rules:$users,fragment_owned:true}' >"$tmp" \
      && nb_atomic_install_file "$tmp" "$NOBRAND_FORWARD_SYSCTL_STATE" 0600
    local rc=$?
    rm -f "$tmp"
    return "$rc"
  fi

  [ -s "$NOBRAND_FORWARD_SYSCTL_STATE" ] || return 0
  forward_sysctl_state_valid "$NOBRAND_FORWARD_SYSCTL_STATE" || return 1
  forward_sysctl_fragment_owned "$NOBRAND_FORWARD_SYSCTL_FRAGMENT" || return 1
  original="$(jq -r '.original_value' "$NOBRAND_FORWARD_SYSCTL_STATE")"
  changed="$(jq -r '.changed_by_nobrand' "$NOBRAND_FORWARD_SYSCTL_STATE")"
  fragment_owned="$(jq -r '.fragment_owned' "$NOBRAND_FORWARD_SYSCTL_STATE")"
  if [ "$changed" = true ] && [ "$current" = 1 ] && [ "$original" = 0 ]; then
    sysctl -q -w net.ipv4.ip_forward=0 >/dev/null || return 1
  fi
  [ "$fragment_owned" != true ] || rm -f "$NOBRAND_FORWARD_SYSCTL_FRAGMENT"
  rm -f "$NOBRAND_FORWARD_SYSCTL_STATE"
}

forward_ensure_nftables_dependency() {
  local pm
  command -v nft >/dev/null 2>&1 && command -v sysctl >/dev/null 2>&1 && return 0
  require_root
  pm="$(detect_pkg_manager)" || return 1
  case "$pm" in
    deb)
      run apt-get update || return 1
      run apt-get install -y nftables procps || return 1
      ;;
    rpm)
      if command -v dnf >/dev/null 2>&1; then
        run dnf install -y nftables procps-ng || return 1
      else
        run yum install -y nftables procps-ng || return 1
      fi
      ;;
    alpine) run apk add --no-cache nftables procps-ng || return 1 ;;
    *) return 1 ;;
  esac
  command -v nft >/dev/null 2>&1 && command -v sysctl >/dev/null 2>&1
}

forward_nft_table_owned() {
  local listing
  command -v nft >/dev/null 2>&1 || return 1
  listing="$(nft list table "$NOBRAND_FORWARD_NFT_FAMILY" "$NOBRAND_FORWARD_NFT_TABLE" 2>/dev/null)" \
    || return 1
  grep -Fq 'comment "Owned by NoBrand-OneClick Port Forward"' <<<"$listing"
}

forward_nft_rule_owned() {
  local id="$1" listing
  command -v nft >/dev/null 2>&1 || return 1
  listing="$(nft list table "$NOBRAND_FORWARD_NFT_FAMILY" "$NOBRAND_FORWARD_NFT_TABLE" 2>/dev/null)" \
    || return 1
  # Do not pipe nft directly into grep -q under pipefail. An early match can
  # close the pipe while nft is still writing and turn a healthy rule into a
  # position-dependent SIGPIPE failure.
  grep -F "nobrand:${id}:dnat:" <<<"$listing" >/dev/null
}

forward_nft_rule_ingress_owned() {
  local id="$1" rule listing enforcement address
  rule="$(forward_rule_json "$NOBRAND_FORWARD_STATE_FILE" "$id")" || return 1
  [ -n "$rule" ] || return 1
  forward_nft_rule_owned "$id" || return 1
  enforcement="$(jq -r '.ingress_enforcement // "permissive"' <<<"$rule")"
  [ "$enforcement" = strict ] || return 0
  address="$(jq -r '.ingress_local_address // empty' <<<"$rule")"
  [ -n "$address" ] || return 1
  listing="$(nft list table "$NOBRAND_FORWARD_NFT_FAMILY" "$NOBRAND_FORWARD_NFT_TABLE" 2>/dev/null)" \
    || return 1
  grep -Fq "ip daddr ${address}" <<<"$listing"
}

forward_apply_nft_state() {
  local state="$1" candidate batch count
  count="$(jq '[.rules[]|select(.enabled and .backend=="nftables")]|length' "$state")" || return 1
  if [ "$count" -eq 0 ]; then
    if command -v nft >/dev/null 2>&1; then
      forward_remove_owned_nft_table || return 1
    fi
    rm -f "$NOBRAND_FORWARD_NFT_RULESET"
    forward_sysctl_reconcile "$state"
    return $?
  fi
  forward_ensure_nftables_dependency || return 1
  candidate="$(mktemp_file .forward.nft)" || return 1
  batch="$(mktemp_file .forward-batch.nft)" || { rm -f "$candidate"; return 1; }
  forward_generate_nft_ruleset "$state" "$candidate" || { rm -f "$candidate" "$batch"; return 1; }
  {
    if nft list table "$NOBRAND_FORWARD_NFT_FAMILY" "$NOBRAND_FORWARD_NFT_TABLE" >/dev/null 2>&1; then
      forward_nft_table_owned || { rm -f "$candidate" "$batch"; return 1; }
      printf 'delete table %s %s\n' "$NOBRAND_FORWARD_NFT_FAMILY" "$NOBRAND_FORWARD_NFT_TABLE"
    fi
    cat "$candidate"
  } >"$batch"
  nft -c -f "$batch" >/dev/null 2>&1 && nft -f "$batch" \
    && nb_atomic_install_file "$candidate" "$NOBRAND_FORWARD_NFT_RULESET" 0600 \
    && forward_sysctl_reconcile "$state"
  local rc=$?
  rm -f "$candidate" "$batch"
  return "$rc"
}

forward_remove_owned_nft_table() {
  command -v nft >/dev/null 2>&1 || return 0
  nft list table "$NOBRAND_FORWARD_NFT_FAMILY" "$NOBRAND_FORWARD_NFT_TABLE" >/dev/null 2>&1 \
    || return 0
  forward_nft_table_owned || return 1
  nft delete table "$NOBRAND_FORWARD_NFT_FAMILY" "$NOBRAND_FORWARD_NFT_TABLE"
}

forward_firewall_pairs() {
  local state="$1"
  jq -r '.rules[]|select(.enabled and .backend=="realm")|. as $r|
    (if .protocol=="both" then ["TCP","UDP"] elif .protocol=="tcp" then ["TCP"] else ["UDP"] end)[]|
    "\(.)|\($r.listen_port)"' "$state" | LC_ALL=C sort -u
}

forward_firewall_reconcile() {
  local old_state="$1" new_state="$2" old_pairs new_pairs pair close_pairs="" open_pairs=""
  old_pairs="$(forward_firewall_pairs "$old_state")" || return 1
  new_pairs="$(forward_firewall_pairs "$new_state")" || return 1
  while IFS= read -r pair; do
    [ -n "$pair" ] || continue
    grep -qxF "$pair" <<<"$old_pairs" \
      || printf -v open_pairs '%s%s\n' "$open_pairs" "$pair"
  done <<<"$new_pairs"
  while IFS= read -r pair; do
    [ -n "$pair" ] || continue
    grep -qxF "$pair" <<<"$new_pairs" \
      || printf -v close_pairs '%s%s\n' "$close_pairs" "$pair"
  done <<<"$old_pairs"
  [ -z "$open_pairs" ] || nb_firewall_open_pairs "$open_pairs" || return 1
  [ -z "$close_pairs" ] || nb_firewall_close_pairs "$close_pairs" || return 1
}

forward_realm_asset_name() {
  case "$(uname -m)" in
    x86_64|amd64) printf 'realm-x86_64-unknown-linux-musl.tar.gz' ;;
    aarch64|arm64) printf 'realm-aarch64-unknown-linux-musl.tar.gz' ;;
    *) return 1 ;;
  esac
}

forward_realm_tested_digest() {
  case "$1" in
    realm-x86_64-unknown-linux-musl.tar.gz) printf '%s' "$TESTED_REALM_AMD64_MUSL_SHA256" ;;
    realm-aarch64-unknown-linux-musl.tar.gz) printf '%s' "$TESTED_REALM_ARM64_MUSL_SHA256" ;;
    *) return 1 ;;
  esac
}

forward_realm_version() {
  local binary="${1:-$NOBRAND_REALM_BIN}"
  [ -x "$binary" ] || return 1
  "$binary" --version 2>/dev/null | sed -nE 's/.*[Rr]ealm[[:space:]]+([0-9]+\.[0-9]+\.[0-9]+).*/\1/p' | head -n1
}

forward_realm_runtime_metadata_valid() {
  local meta="$NOBRAND_REALM_RUNTIME_META"
  [ -s "$meta" ] && jq -e '
    (keys|sort)==["asset","channel","consumer","installed_at","ownership","schema_version","sha256","source_url","version"] and
    .schema_version==3 and .ownership=="nobrand-v3" and .consumer=="port-forward" and
    (.version|type)=="string" and (.version|test("^[0-9]+\\.[0-9]+\\.[0-9]+$")) and
    (.channel=="stable" or .channel=="latest" or .channel=="pinned") and
    (.asset|type)=="string" and (.asset|test("^realm-(x86_64|aarch64)-unknown-linux-musl\\.tar\\.gz$")) and
    (.source_url|type)=="string" and (.source_url|startswith("https://github.com/zhboner/realm/releases/download/")) and
    (.sha256|type)=="string" and (.sha256|test("^[0-9a-f]{64}$")) and
    (.installed_at|type)=="string"
  ' "$meta" >/dev/null
}

forward_ensure_realm_dependencies() {
  local command_name
  for command_name in curl jq tar sha256sum find; do
    command -v "$command_name" >/dev/null 2>&1 || return 1
  done
}

forward_realm_install_runtime() {
  local channel="${1:-stable}" version="${2:-}" api response tag asset url digest expected
  local archive extract binary actual actual_version meta
  case "$channel" in
    stable) version="$TESTED_REALM_VERSION" ;;
    latest) ;;
    pinned) [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1 ;;
    *) return 1 ;;
  esac
  forward_ensure_realm_dependencies || return 1
  if [ -e "$NOBRAND_REALM_BIN" ] && ! forward_realm_runtime_metadata_valid; then
    warn "拒绝替换不属于 NoBrand 管理的 Realm Runtime: $NOBRAND_REALM_BIN"
    return 1
  fi
  if [ -e "$NOBRAND_REALM_RUNTIME_META" ] && ! forward_realm_runtime_metadata_valid; then
    warn "拒绝替换归属元数据无效的 Realm Runtime: $NOBRAND_REALM_RUNTIME_META"
    return 1
  fi
  [ "$channel" != latest ] && api="${NOBRAND_REALM_RELEASE_API}/tags/v${version}" \
    || api="${NOBRAND_REALM_RELEASE_API}/latest"
  response="$(curl -fsSL --connect-timeout 10 --max-time 60 \
    -H 'Accept: application/vnd.github+json' -H 'User-Agent: NoBrand-OneClick' "$api")" || return 1
  jq -e '.draft==false and .prerelease==false' <<<"$response" >/dev/null || return 1
  tag="$(jq -r .tag_name <<<"$response")"
  [[ "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
  version="${tag#v}"
  asset="$(forward_realm_asset_name)" || return 1
  url="$(jq -r --arg asset "$asset" '.assets[]|select(.name==$asset)|.browser_download_url' <<<"$response" | head -n1)"
  digest="$(jq -r --arg asset "$asset" '.assets[]|select(.name==$asset)|.digest // empty' <<<"$response" | head -n1)"
  digest="${digest#sha256:}"
  [[ "$digest" =~ ^[0-9a-f]{64}$ ]] && [ -n "$url" ] || return 1
  if [ "$channel" = stable ]; then
    expected="$(forward_realm_tested_digest "$asset")" || return 1
    [ "$digest" = "$expected" ] || return 1
  fi
  archive="$(mktemp_file .realm.tar.gz)" || return 1
  extract="$(mktemp_dir)" || { rm -f "$archive"; return 1; }
  curl -fL --connect-timeout 10 --max-time 300 -H 'User-Agent: NoBrand-OneClick' "$url" -o "$archive" \
    || { rm -f "$archive"; rm -rf -- "$extract"; return 1; }
  actual="$(nobrand_sha256_file "$archive")" || return 1
  [ "$actual" = "$digest" ] || return 1
  tar --no-same-owner -C "$extract" -xzf "$archive" || return 1
  binary="$(find "$extract" -type f -name realm -print -quit)"
  [ -n "$binary" ] || return 1
  chmod 0755 "$binary" || return 1
  actual_version="$(forward_realm_version "$binary")" || return 1
  [ "$actual_version" = "$version" ] || return 1
  nb_atomic_install_file "$binary" "$NOBRAND_REALM_BIN" 0755 || return 1
  meta="$(mktemp_file .realm-meta)" || return 1
  jq -n --arg version "$version" --arg channel "$channel" --arg asset "$asset" \
    --arg source "$url" --arg sha256 "$digest" --arg installed_at "$(forward_now)" '
      {schema_version:3,ownership:"nobrand-v3",consumer:"port-forward",version:$version,
       channel:$channel,asset:$asset,source_url:$source,sha256:$sha256,installed_at:$installed_at}
    ' >"$meta" && nb_atomic_install_file "$meta" "$NOBRAND_REALM_RUNTIME_META" 0600
  local rc=$?
  rm -f "$archive" "$meta"
  rm -rf -- "$extract"
  return "$rc"
}

forward_realm_service_active() {
  forward_realm_service_file_owned || return 1
  nb_service_is_active "$NOBRAND_REALM_SERVICE_NAME" "$NOBRAND_REALM_SERVICE_NAME"
}

forward_realm_service_pid() {
  forward_realm_service_file_owned || return 1
  case "$(nb_service_manager)" in
    systemd) systemctl show -p MainPID --value "$NOBRAND_REALM_SERVICE_NAME" 2>/dev/null ;;
    openrc) [ -s /run/nobrand-realm.pid ] && cat /run/nobrand-realm.pid ;;
  esac
}

forward_realm_service_path() {
  case "$(nb_service_manager)" in
    systemd) printf '%s' "$NOBRAND_REALM_SYSTEMD_SERVICE" ;;
    openrc) printf '%s' "$NOBRAND_REALM_OPENRC_SERVICE" ;;
    *) return 1 ;;
  esac
}

forward_realm_service_file_owned() {
  local path
  path="$(forward_realm_service_path 2>/dev/null)" || return 1
  forward_realm_service_path_owned "$path"
}

forward_realm_service_path_owned() {
  local path="$1"
  [ -f "$path" ] && [ ! -L "$path" ] \
    && grep -Fq 'Owned by NoBrand-OneClick Port Forward' "$path" \
    && grep -Fq "$NOBRAND_REALM_BIN" "$path" \
    && grep -Fq "$NOBRAND_FORWARD_REALM_CONFIG" "$path"
}

forward_realm_install_service() {
  local manager tmp path
  manager="$(nb_service_manager)"
  path="$(forward_realm_service_path)" || return 1
  [ ! -e "$path" ] || forward_realm_service_file_owned || {
    warn "拒绝替换不属于 NoBrand 管理的 Realm 服务: $path"
    return 1
  }
  tmp="$(mktemp_file .realm-service)" || return 1
  case "$manager" in
    systemd)
      cat >"$tmp" <<EOF
# Owned by NoBrand-OneClick Port Forward
[Unit]
Description=NoBrand Realm Port Forward
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=${NOBRAND_REALM_BIN} -c ${NOBRAND_FORWARD_REALM_CONFIG}
Restart=on-failure
RestartSec=2
NoNewPrivileges=true
PrivateTmp=true
ProtectHome=true
ProtectSystem=strict
ReadOnlyPaths=${NOBRAND_REALM_BIN} ${NOBRAND_FORWARD_REALM_CONFIG}

[Install]
WantedBy=multi-user.target
EOF
      nb_atomic_install_file "$tmp" "$NOBRAND_REALM_SYSTEMD_SERVICE" 0644 \
        && systemctl daemon-reload \
        && systemctl enable "$NOBRAND_REALM_SERVICE_NAME" >/dev/null 2>&1
      ;;
    openrc)
      cat >"$tmp" <<EOF
#!/sbin/openrc-run
# Owned by NoBrand-OneClick Port Forward
name="NoBrand Realm Port Forward"
command="${NOBRAND_REALM_BIN}"
command_args="-c ${NOBRAND_FORWARD_REALM_CONFIG}"
command_background="yes"
pidfile="/run/nobrand-realm.pid"
output_log="/var/log/nobrand-realm.log"
error_log="/var/log/nobrand-realm.err"
depend() { use net; after firewall; }
EOF
      nb_atomic_install_file "$tmp" "$NOBRAND_REALM_OPENRC_SERVICE" 0755 \
        && rc-update add "$NOBRAND_REALM_SERVICE_NAME" default >/dev/null 2>&1
      ;;
    *) rm -f "$tmp"; return 1 ;;
  esac
  local rc=$?
  rm -f "$tmp"
  return "$rc"
}

forward_realm_service_action() {
  forward_realm_service_file_owned || return 1
  case "$(nb_service_manager)" in
    systemd) systemctl "$1" "$NOBRAND_REALM_SERVICE_NAME" ;;
    openrc) rc-service "$NOBRAND_REALM_SERVICE_NAME" "$1" ;;
    *) return 1 ;;
  esac
}

forward_realm_listener_owned() {
  local state="$1" pid protocol port transport found listen_host enforcement
  pid="$(forward_realm_service_pid 2>/dev/null || true)"
  [[ "$pid" =~ ^[0-9]+$ ]] && [ "$pid" -gt 1 ] || return 1
  while IFS=$'\t' read -r protocol port listen_host enforcement; do
    while IFS= read -r transport; do
      found=0
      while IFS= read -r listener_pid; do
        [ "$listener_pid" != "$pid" ] || found=1
      done < <(nb_port_listener_pids "$transport" "$port")
      [ "$found" -eq 1 ] || return 1
      if [ "$enforcement" = strict ]; then
        nb_listener_has_local_address "$transport" "$port" "$listen_host" || return 1
      fi
    done < <(forward_protocol_transports "$protocol")
  done < <(jq -r '.rules[]|select(.enabled and .backend=="realm")|
    [.protocol,(.listen_port|tostring),.listen_host,(.ingress_enforcement // "permissive")]|@tsv' "$state")
}

forward_realm_probe_config() {
  local config="$1" pid i
  [ -x "$NOBRAND_REALM_BIN" ] || return 1
  "$NOBRAND_REALM_BIN" -c "$config" 7>&- >/dev/null 2>&1 &
  pid=$!
  i=0
  while [ "$i" -lt 10 ]; do
    if ! kill -0 "$pid" 2>/dev/null; then
      wait "$pid" 2>/dev/null || true
      return 1
    fi
    sleep 0.1
    i=$((i + 1))
  done
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
}

forward_realm_probe_port_available() {
  local port="$1" protocol="$2" used="${3:-}" transport
  case "|$used|" in *"|$port|"*) return 1 ;; esac
  while IFS= read -r transport; do
    nb_port_available_for_transport "$port" "$transport" || return 1
  done < <(forward_protocol_transports "$protocol")
}

forward_generate_realm_probe_config() {
  local state="$1" output="$2" probe_state id protocol port used=""
  probe_state="$(mktemp_file .realm-probe-state)" || return 1
  cp -a "$state" "$probe_state" || { rm -f "$probe_state"; return 1; }
  while IFS=$'\t' read -r id protocol; do
    [ -n "$id" ] || continue
    port="$(nb_scan_port_span 40000 65535 forward_realm_probe_port_available "$protocol" "$used")" \
      || { rm -f "$probe_state"; return 1; }
    used="${used:+${used}|}${port}"
    jq --arg id "$id" --argjson port "$port" '
      (.rules[]|select(.rule_id==$id)) |=
        (.listen_port=$port | if .display_mode=="auto" then .display_port=$port else . end)
    ' "$probe_state" >"${probe_state}.next" \
      && mv -f "${probe_state}.next" "$probe_state" \
      || { rm -f "$probe_state" "${probe_state}.next"; return 1; }
  done < <(jq -r '.rules|sort_by(.rule_id)[]|select(.enabled and .backend=="realm")|
    [.rule_id,.protocol]|@tsv' "$state")
  forward_generate_realm_config "$probe_state" "$output"
  local rc=$?
  rm -f "$probe_state" "${probe_state}.next"
  return "$rc"
}

forward_realm_apply_state() {
  local state="$1" count candidate probe
  count="$(jq '[.rules[]|select(.enabled and .backend=="realm")]|length' "$state")" || return 1
  if [ "$count" -eq 0 ]; then
    forward_realm_service_action stop >/dev/null 2>&1 || true
    rm -f "$NOBRAND_FORWARD_REALM_CONFIG"
    return 0
  fi
  [ -x "$NOBRAND_REALM_BIN" ] || forward_realm_install_runtime stable || return 1
  candidate="$(mktemp_file .realm-candidate.toml)" || return 1
  probe="$(mktemp_file .realm-probe.toml)" || { rm -f "$candidate"; return 1; }
  forward_generate_realm_config "$state" "$candidate" \
    && forward_generate_realm_probe_config "$state" "$probe" \
    && forward_realm_probe_config "$probe" \
    || { rm -f "$candidate" "$probe"; return 1; }
  [ "${NOBRAND_TEST_INGRESS_SERVICE_FAIL:-0}" -eq 0 ] \
    && nb_atomic_install_file "$candidate" "$NOBRAND_FORWARD_REALM_CONFIG" 0600 \
    && forward_realm_install_service \
    && forward_realm_service_action restart \
    && forward_realm_service_active \
    && [ "${NOBRAND_TEST_INGRESS_LISTENER_FAIL:-0}" -eq 0 ] \
    && forward_realm_listener_owned "$state"
  local rc=$?
  rm -f "$candidate" "$probe"
  return "$rc"
}

# Rebuild only effects described by a complete Forward state. Recovery never
# guesses at or deletes effects from an interrupted, unpublished candidate.
forward_reconcile_authoritative_state() {
  local state="$NOBRAND_FORWARD_STATE_FILE" forward_pairs failed=0
  [ -f "$state" ] && [ ! -L "$state" ] && forward_state_valid "$state" || return 1
  forward_pairs="$(forward_firewall_pairs "$state")" || return 1
  admin_lock_acquire || return 1
  forward_apply_nft_state "$state" >/dev/null 2>&1 || failed=1
  [ "$failed" -ne 0 ] \
    || forward_realm_apply_state "$state" >/dev/null 2>&1 || failed=1
  [ "$failed" -ne 0 ] || [ -z "$forward_pairs" ] \
    || nb_firewall_open_pairs "$forward_pairs" >/dev/null 2>&1 || failed=1
  admin_lock_release
  return "$failed"
}

forward_transaction_commit() {
  local candidate="$1" operation="${2:-modify}" old_backend="${3:-}" new_backend="${4:-}"
  local snapshot old_state failed=0 rollback_failed=0
  forward_state_valid "$candidate" || return 1
  snapshot="$(mktemp_dir)" || return 1
  old_state="$snapshot/old-state.json"
  if [ -s "$NOBRAND_FORWARD_STATE_FILE" ]; then
    cp -a "$NOBRAND_FORWARD_STATE_FILE" "$old_state" || { rm -rf -- "$snapshot"; return 1; }
  else
    jq -n '{schema_version:3,ownership:"nobrand-v3",feature:"port-forward",rules:[]}' >"$old_state"
  fi
  forward_snapshot_restore_side_effects "$snapshot/side-effects" \
    || { rm -rf -- "$snapshot"; return 1; }
  if [ "$operation" = switch-backend ] && [ "$old_backend" = nftables ] && [ "$new_backend" = realm ]; then
    forward_realm_apply_state "$candidate" || failed=1
    [ "$failed" -ne 0 ] || forward_apply_nft_state "$candidate" || failed=1
  else
    forward_apply_nft_state "$candidate" || failed=1
    [ "$failed" -ne 0 ] || forward_realm_apply_state "$candidate" || failed=1
  fi
  [ "$failed" -ne 0 ] || forward_firewall_reconcile "$old_state" "$candidate" || failed=1
  if [ "$failed" -eq 0 ] && nb_atomic_install_file "$candidate" "$NOBRAND_FORWARD_STATE_FILE" 0600; then
    rm -rf -- "$snapshot" || return 1
    return 0
  fi
  forward_firewall_reconcile "$candidate" "$old_state" >/dev/null 2>&1 || rollback_failed=1
  forward_restore_side_effect_snapshot "$snapshot/side-effects" >/dev/null 2>&1 || rollback_failed=1
  forward_realm_apply_state "$old_state" >/dev/null 2>&1 || rollback_failed=1
  if [ "$rollback_failed" -ne 0 ]; then
    warn "端口转发回滚未完整完成；恢复快照已保留: $snapshot"
    return 1
  fi
  rm -rf -- "$snapshot" || return 1
  return 1
}

forward_csv_strings_json() {
  local value="${1:-}"
  [ -n "$value" ] || { printf '[]'; return 0; }
  jq -Rn --arg value "$value" '$value|split(",")|map(gsub("^[[:space:]]+|[[:space:]]+$";""))|map(select(length>0))'
}

forward_csv_numbers_json() {
  local value="${1:-}"
  [ -n "$value" ] || { printf '[]'; return 0; }
  jq -Rn --arg value "$value" '
    $value|split(",")|map(gsub("^[[:space:]]+|[[:space:]]+$";""))|
    if all(.[]; test("^[0-9]+$") and ((tonumber)>=1) and ((tonumber)<=255))
    then map(tonumber) else error("invalid weight") end
  ' 2>/dev/null
}

forward_csv_socket_addresses_json() {
  local value="${1:-}" raw item normalized result='[]'
  [ -n "$value" ] || { printf '[]'; return 0; }
  raw="$(forward_csv_strings_json "$value")" || return 1
  while IFS= read -r item; do
    normalized="$(forward_socket_address_normalize "$item")" || return 1
    result="$(jq -c --arg value "$normalized" '.+[$value]' <<<"$result")" || return 1
  done < <(jq -r '.[]' <<<"$raw")
  printf '%s' "$result"
}

forward_realm_options_json() {
  local nameservers extra weights
  [ -z "$FORWARD_THROUGH" ] || valid_ip_literal "$FORWARD_THROUGH" || return 1
  for iface in "$FORWARD_INTERFACE" "$FORWARD_LISTEN_INTERFACE"; do
    [ -z "$iface" ] || [[ "$iface" =~ ^[A-Za-z0-9_.:-]{1,64}$ ]] || return 1
  done
  [[ "$FORWARD_TCP_TIMEOUT" =~ ^[0-9]+$ ]] && [ "$FORWARD_TCP_TIMEOUT" -le 86400 ] || return 1
  [[ "$FORWARD_UDP_TIMEOUT" =~ ^[0-9]+$ ]] && [ "$FORWARD_UDP_TIMEOUT" -ge 1 ] \
    && [ "$FORWARD_UDP_TIMEOUT" -le 86400 ] || return 1
  case "$FORWARD_PROXY_SEND" in true|false) ;; *) return 1 ;; esac
  case "$FORWARD_PROXY_ACCEPT" in true|false) ;; *) return 1 ;; esac
  case "$FORWARD_PROXY_VERSION" in 1|2) ;; *) return 1 ;; esac
  [[ "$FORWARD_PROXY_ACCEPT_TIMEOUT" =~ ^[0-9]+$ ]] && [ "$FORWARD_PROXY_ACCEPT_TIMEOUT" -le 86400 ] || return 1
  case "$FORWARD_DNS_MODE" in system|ipv4_only|ipv6_only|ipv4_then_ipv6|ipv6_then_ipv4|ipv4_and_ipv6) ;; *) return 1 ;; esac
  case "$FORWARD_DNS_PROTOCOL" in tcp|udp|tcp_and_udp) ;; *) return 1 ;; esac
  case "$FORWARD_BALANCE" in off|roundrobin|iphash) ;; *) return 1 ;; esac
  [ "${#FORWARD_LISTEN_TRANSPORT}" -le 1024 ] && [ "${#FORWARD_REMOTE_TRANSPORT}" -le 1024 ] || return 1
  ! has_control_chars "$FORWARD_LISTEN_TRANSPORT" && ! has_control_chars "$FORWARD_REMOTE_TRANSPORT" || return 1
  nameservers="$(forward_csv_socket_addresses_json "$FORWARD_DNS_NAMESERVERS")" || return 1
  extra="$(forward_csv_socket_addresses_json "$FORWARD_EXTRA_TARGETS")" || return 1
  weights="$(forward_csv_numbers_json "$FORWARD_WEIGHTS")" || return 1
  jq -e 'all(.[]; type=="string" and length>0 and length<=255 and (test("[[:space:]]")|not))' \
    <<<"$nameservers" >/dev/null || return 1
  jq -e 'all(.[]; type=="string" and length>2 and length<=300 and (test("[[:space:]]")|not))' \
    <<<"$extra" >/dev/null || return 1
  if [ "$FORWARD_BALANCE" = off ]; then
    [ "$weights" = '[]' ] && [ "$extra" = '[]' ] || return 1
  else
    [ "$(jq 'length' <<<"$extra")" -gt 0 ] || return 1
    [ "$(jq 'length' <<<"$weights")" -eq "$((1 + $(jq 'length' <<<"$extra")))" ] || return 1
  fi
  jq -n --arg through "$FORWARD_THROUGH" --arg interface "$FORWARD_INTERFACE" \
    --arg listen_interface "$FORWARD_LISTEN_INTERFACE" \
    --argjson tcp_timeout "$FORWARD_TCP_TIMEOUT" --argjson udp_timeout "$FORWARD_UDP_TIMEOUT" \
    --argjson proxy_send "$FORWARD_PROXY_SEND" --argjson proxy_accept "$FORWARD_PROXY_ACCEPT" \
    --argjson proxy_version "$FORWARD_PROXY_VERSION" \
    --argjson proxy_accept_timeout "$FORWARD_PROXY_ACCEPT_TIMEOUT" \
    --arg dns_mode "$FORWARD_DNS_MODE" --arg dns_protocol "$FORWARD_DNS_PROTOCOL" \
    --argjson dns_nameservers "$nameservers" --arg listen_transport "$FORWARD_LISTEN_TRANSPORT" \
    --arg remote_transport "$FORWARD_REMOTE_TRANSPORT" --argjson extra_targets "$extra" \
    --arg balance "$FORWARD_BALANCE" --argjson weights "$weights" '
      {through:$through,interface:$interface,listen_interface:$listen_interface,
       tcp_timeout:$tcp_timeout,udp_timeout:$udp_timeout,proxy_send:$proxy_send,
       proxy_accept:$proxy_accept,proxy_version:$proxy_version,
       proxy_accept_timeout:$proxy_accept_timeout,dns_mode:$dns_mode,
       dns_protocol:$dns_protocol,dns_nameservers:$dns_nameservers,
       listen_transport:$listen_transport,remote_transport:$remote_transport,
       extra_targets:$extra_targets,balance:$balance,weights:$weights}
    '
}

forward_default_options_json() {
  case "$1" in
    nftables)
      case "$FORWARD_SOURCE_MODE" in masquerade|preserve) ;; *) return 1 ;; esac
      jq -n --arg source_mode "$FORWARD_SOURCE_MODE" '{source_mode:$source_mode}'
      ;;
    realm) forward_realm_options_json ;;
    *) return 1 ;;
  esac
}

forward_prepare_ingress_enforcement() {
  local backend="$1" profile_id="$2" capability
  case "$backend" in
    nftables) capability='address-match' ;;
    realm) capability=native-bind ;;
    *) return 1 ;;
  esac
  nb_prepare_ingress_deployment "$profile_id" "$capability" || return 1
  if [ "$INGRESS_ENFORCEMENT_RESOLVED" = strict ]; then
    FORWARD_LISTEN_HOST="$INGRESS_LISTEN_HOST"
  else
    FORWARD_LISTEN_HOST="${FORWARD_LISTEN_HOST:-0.0.0.0}"
  fi
}

forward_validate_requested_rule() {
  local ignore_owner="${1:-}" transport old_json="${2:-}" old_port="" old_protocol=""
  [ -n "$FORWARD_NAME" ] && [ "${#FORWARD_NAME}" -le 64 ] && ! has_control_chars "$FORWARD_NAME" || return 1
  [ "${#FORWARD_NOTE}" -le 256 ] && ! has_control_chars "$FORWARD_NOTE" || return 1
  case "$FORWARD_BACKEND" in nftables|realm) ;; *) return 1 ;; esac
  FORWARD_PROTOCOL="$(forward_normalize_protocol "$FORWARD_PROTOCOL")" || return 1
  [ -n "${INGRESS_PROFILE_ID:-}" ] || nb_prepare_ingress_request || return 1
  FORWARD_LISTEN_HOST="${FORWARD_LISTEN_HOST:-0.0.0.0}"
  forward_listen_host_valid "$FORWARD_BACKEND" "$FORWARD_LISTEN_HOST" || return 1
  nb_valid_port "$FORWARD_LISTEN_PORT" && nb_valid_port "$FORWARD_TARGET_PORT" || return 1
  FORWARD_LISTEN_PORT="$(normalize_uint "$FORWARD_LISTEN_PORT")"
  FORWARD_TARGET_PORT="$(normalize_uint "$FORWARD_TARGET_PORT")"
  if [ "$FORWARD_BACKEND" = nftables ] && ! forward_valid_ipv4 "$FORWARD_TARGET_HOST"; then
    warn 'nftables 后端当前要求目标为 IP 地址；域名目标请使用 Realm 后端。'
    return 1
  fi
  forward_target_valid "$FORWARD_BACKEND" "$FORWARD_TARGET_HOST" || return 1
  if [ -n "$old_json" ]; then
    old_port="$(jq -r .listen_port <<<"$old_json")"
    old_protocol="$(jq -r .protocol <<<"$old_json")"
  fi
  if [ "$old_port" != "$FORWARD_LISTEN_PORT" ] || [ "$old_protocol" != "$FORWARD_PROTOCOL" ]; then
    forward_port_allowed "$FORWARD_LISTEN_PORT" "$FORWARD_PROTOCOL" "$ignore_owner" "$INGRESS_PROFILE_ID" || return 1
  else
    nb_ingress_port_is_reserved "$INGRESS_PROFILE_ID" "$FORWARD_LISTEN_PORT" && return 1
  fi
  return 0
}

forward_requested_display_json() {
  if [ "$ADVERTISE_CLI" -eq 1 ] && [ "$ADVERTISE_AUTO_REQUESTED" -eq 0 ]; then
    valid_advertise_host "$ADVERTISE_HOST" && valid_advertise_port "$ADVERTISE_PORT" || return 1
    jq -n --arg mode custom --arg host "$ADVERTISE_HOST" \
      --argjson port "$(normalize_uint "$ADVERTISE_PORT")" '{mode:$mode,host:$host,port:$port}'
  else
    jq -n --arg mode auto --arg host '' --argjson port "$FORWARD_LISTEN_PORT" \
      '{mode:$mode,host:$host,port:$port}'
  fi
}

forward_add_rule() {
  local id now options display rule candidate
  forward_init_state || return 1
  nb_prepare_ingress_request || return 1
  [ -n "$FORWARD_NAME" ] && [ -n "$FORWARD_BACKEND" ] && [ -n "$FORWARD_PROTOCOL" ] \
    && [ -n "$FORWARD_TARGET_HOST" ] && [ -n "$FORWARD_TARGET_PORT" ] \
    || die 'forward add 非交互模式需要 --name --backend --protocol --target --target-port'
  FORWARD_PROTOCOL="$(forward_normalize_protocol "$FORWARD_PROTOCOL")" || die 'Forward 协议无效'
  forward_prepare_ingress_enforcement "$FORWARD_BACKEND" "$INGRESS_PROFILE_ID" \
    || die '端口转发无法实施所选 Ingress 的 Strict 本地地址限制'
  if [ -z "$FORWARD_LISTEN_PORT" ]; then
    FORWARD_LISTEN_PORT="$(forward_select_available_port "$FORWARD_PROTOCOL" "$INGRESS_PROFILE_ID")" \
      || die '所选入口配置没有可用 Forward 自动端口；manual-only 必须显式使用 --port'
  fi
  forward_validate_requested_rule || die '端口转发规则参数无效、端口冲突或命中 xx00 保留端口'
  jq -e --arg name "$FORWARD_NAME" 'all(.rules[];.name!=$name)' "$NOBRAND_FORWARD_STATE_FILE" >/dev/null \
    || die '端口转发规则名称已存在'
  options="$(forward_default_options_json "$FORWARD_BACKEND")" || die '端口转发后端选项无效'
  display="$(forward_requested_display_json)" || die '端口转发展示端点 / Display Endpoint 无效'
  id="$(forward_generate_rule_id)"
  now="$(forward_now)"
  rule="$(jq -n --arg id "$id" --arg name "$FORWARD_NAME" --arg note "$FORWARD_NOTE" \
    --arg backend "$FORWARD_BACKEND" --arg protocol "$FORWARD_PROTOCOL" \
    --arg listen_host "$FORWARD_LISTEN_HOST" --argjson listen_port "$FORWARD_LISTEN_PORT" \
    --arg target_host "$FORWARD_TARGET_HOST" --argjson target_port "$FORWARD_TARGET_PORT" \
    --arg display_mode "$(jq -r .mode <<<"$display")" --arg display_host "$(jq -r .host <<<"$display")" \
    --argjson display_port "$(jq -r .port <<<"$display")" --arg now "$now" \
    --argjson options "$options" --arg ingress_profile_id "$INGRESS_PROFILE_ID" \
    --arg ingress_enforcement "$INGRESS_ENFORCEMENT_RESOLVED" \
    --arg ingress_method "$INGRESS_ENFORCEMENT_METHOD" --arg ingress_address "$INGRESS_LOCAL_ADDRESS" '
      {rule_id:$id,name:$name,note:$note,backend:$backend,enabled:true,protocol:$protocol,
       listen_host:$listen_host,listen_port:$listen_port,target_host:$target_host,target_port:$target_port,
       display_host:$display_host,display_port:$display_port,display_mode:$display_mode,
       created_at:$now,updated_at:$now,
       ownership_metadata:{managed_listener:true,managed_firewall:true},backend_options:$options,
        ingress_profile_id:$ingress_profile_id,ingress_enforcement:$ingress_enforcement,
        ingress_enforcement_method:$ingress_method,ingress_local_address:$ingress_address}
    ')" || return 1
  candidate="$(mktemp_file .forward-add)" || return 1
  jq --argjson rule "$rule" '.rules += [$rule]' "$NOBRAND_FORWARD_STATE_FILE" >"$candidate" \
    && nb_lifecycle_mark_protocol_mutation_started forward \
    && forward_transaction_commit "$candidate" add '' "$FORWARD_BACKEND"
  local rc=$?
  rm -f "$candidate"
  [ "$rc" -ne 0 ] || msg "已创建端口转发规则: ${id} (${FORWARD_NAME})"
  return "$rc"
}

forward_delete_rule() {
  local id old_backend candidate
  id="$(forward_resolve_rule_id "$FORWARD_RULE_ID")" || die '端口转发规则不存在'
  old_backend="$(jq -r --arg id "$id" '.rules[]|select(.rule_id==$id)|.backend' "$NOBRAND_FORWARD_STATE_FILE")"
  candidate="$(mktemp_file .forward-delete)" || return 1
  jq --arg id "$id" '.rules |= map(select(.rule_id!=$id))' "$NOBRAND_FORWARD_STATE_FILE" >"$candidate" \
    && forward_transaction_commit "$candidate" delete "$old_backend" ''
  local rc=$?
  rm -f "$candidate"
  return "$rc"
}

forward_set_enabled() {
  local enabled="$1" id backend candidate
  id="$(forward_resolve_rule_id "$FORWARD_RULE_ID")" || die '端口转发规则不存在'
  backend="$(jq -r --arg id "$id" '.rules[]|select(.rule_id==$id)|.backend' "$NOBRAND_FORWARD_STATE_FILE")"
  candidate="$(mktemp_file .forward-enable)" || return 1
  jq --arg id "$id" --argjson enabled "$enabled" --arg now "$(forward_now)" \
    '(.rules[]|select(.rule_id==$id)) |= (.enabled=$enabled|.updated_at=$now)' \
    "$NOBRAND_FORWARD_STATE_FILE" >"$candidate" \
    && forward_transaction_commit "$candidate" enable "$backend" "$backend"
  local rc=$?
  rm -f "$candidate"
  return "$rc"
}

forward_modify_rule() {
  local id old old_backend options candidate new_name new_note new_protocol new_listen_host
  local new_listen_port new_target_host new_target_port display
  local new_display_mode new_display_host new_display_port old_ingress_profile_id
  id="$(forward_resolve_rule_id "$FORWARD_RULE_ID")" || die '端口转发规则不存在'
  old="$(forward_rule_json "$NOBRAND_FORWARD_STATE_FILE" "$id")"
  old_backend="$(jq -r .backend <<<"$old")"
  old_ingress_profile_id="$(jq -r '.ingress_profile_id // "legacy-default-route"' <<<"$old")"
  if [ "$INGRESS_PROFILE_CLI" -eq 1 ]; then
    INGRESS_PROFILE_ID="$(nb_resolve_ingress_profile "$INGRESS_PROFILE")" || return 1
  else
    INGRESS_PROFILE_ID="$old_ingress_profile_id"
  fi
  [ -z "$FORWARD_BACKEND" ] || [ "$FORWARD_BACKEND" = "$old_backend" ] \
    || die 'modify 不用于切换后端；请使用 switch-backend'
  FORWARD_BACKEND="$old_backend"
  new_name="${FORWARD_NAME:-$(jq -r .name <<<"$old")}"
  new_note="${FORWARD_NOTE:-$(jq -r .note <<<"$old")}"
  new_protocol="${FORWARD_PROTOCOL:-$(jq -r .protocol <<<"$old")}"
  new_listen_host="${FORWARD_LISTEN_HOST:-$(jq -r .listen_host <<<"$old")}"
  new_listen_port="${FORWARD_LISTEN_PORT:-$(jq -r .listen_port <<<"$old")}"
  new_target_host="${FORWARD_TARGET_HOST:-$(jq -r .target_host <<<"$old")}"
  new_target_port="${FORWARD_TARGET_PORT:-$(jq -r .target_port <<<"$old")}"
  FORWARD_NAME="$new_name" FORWARD_NOTE="$new_note" FORWARD_PROTOCOL="$new_protocol"
  FORWARD_LISTEN_HOST="$new_listen_host" FORWARD_LISTEN_PORT="$new_listen_port"
  FORWARD_TARGET_HOST="$new_target_host" FORWARD_TARGET_PORT="$new_target_port"
  forward_prepare_ingress_enforcement "$FORWARD_BACKEND" "$INGRESS_PROFILE_ID" \
    || die '修改后的端口转发规则无法实施所选 Ingress Profile'
  if [ "$INGRESS_ENFORCEMENT_RESOLVED" = permissive ] \
     && [ "$(jq -r '.ingress_enforcement // "permissive"' <<<"$old")" = strict ] \
     && [ "${FORWARD_LISTEN_HOST_CLI:-0}" -eq 0 ]; then
    FORWARD_LISTEN_HOST=0.0.0.0
  fi
  forward_validate_requested_rule "forward:${id}" "$old" || die '端口转发修改参数无效、冲突或命中 xx00'
  if [ "$ADVERTISE_CLI" -eq 1 ]; then
    display="$(forward_requested_display_json)" || die '端口转发展示端点 / Display Endpoint 无效'
    new_display_mode="$(jq -r .mode <<<"$display")"
    new_display_host="$(jq -r .host <<<"$display")"
    new_display_port="$(jq -r .port <<<"$display")"
  elif [ "$(jq -r .display_mode <<<"$old")" = auto ]; then
    # Auto Display Endpoints follow the real listener.  Keeping the previous
    # display_port after a listen-port modification would make the candidate
    # internally inconsistent and forward_state_valid correctly rejects it.
    new_display_mode=auto
    new_display_host=""
    new_display_port="$FORWARD_LISTEN_PORT"
  else
    new_display_mode="$(jq -r .display_mode <<<"$old")"
    new_display_host="$(jq -r .display_host <<<"$old")"
    new_display_port="$(jq -r .display_port <<<"$old")"
  fi
  if [ "$old_backend" = nftables ]; then
    if [ "$FORWARD_SOURCE_MODE_CLI" -eq 1 ]; then
      options="$(forward_default_options_json nftables)" || die 'nftables 源地址模式无效'
    else
      options="$(jq -c .backend_options <<<"$old")"
    fi
  elif [ "$FORWARD_ADVANCED_CLI" -eq 1 ]; then
    options="$(forward_default_options_json realm)" || die 'Realm 高级选项无效'
  else
    options="$(jq -c .backend_options <<<"$old")"
  fi
  candidate="$(mktemp_file .forward-modify)" || return 1
  jq --arg id "$id" --arg name "$FORWARD_NAME" --arg note "$FORWARD_NOTE" \
    --arg protocol "$FORWARD_PROTOCOL" --arg listen_host "$FORWARD_LISTEN_HOST" \
    --argjson listen_port "$FORWARD_LISTEN_PORT" --arg target_host "$FORWARD_TARGET_HOST" \
    --argjson target_port "$FORWARD_TARGET_PORT" --arg display_mode "$new_display_mode" \
    --arg display_host "$new_display_host" --argjson display_port "$new_display_port" \
    --argjson options "$options" --arg ingress_profile_id "$INGRESS_PROFILE_ID" --arg now "$(forward_now)" \
    --arg ingress_enforcement "$INGRESS_ENFORCEMENT_RESOLVED" \
    --arg ingress_method "$INGRESS_ENFORCEMENT_METHOD" --arg ingress_address "$INGRESS_LOCAL_ADDRESS" '
      (.rules[]|select(.rule_id==$id)) |=
        (.name=$name|.note=$note|.protocol=$protocol|.listen_host=$listen_host|.listen_port=$listen_port|
         .target_host=$target_host|.target_port=$target_port|.display_mode=$display_mode|
         .display_host=$display_host|.display_port=$display_port|.backend_options=$options|
         .ingress_profile_id=$ingress_profile_id|.ingress_enforcement=$ingress_enforcement|
         .ingress_enforcement_method=$ingress_method|.ingress_local_address=$ingress_address|.updated_at=$now)
    ' "$NOBRAND_FORWARD_STATE_FILE" >"$candidate" \
    && forward_transaction_commit "$candidate" modify "$old_backend" "$old_backend"
  local rc=$?
  rm -f "$candidate"
  return "$rc"
}

forward_switch_backend() {
  local id old old_backend new_backend options target candidate profile_id
  id="$(forward_resolve_rule_id "$FORWARD_RULE_ID")" || die '端口转发规则不存在'
  old="$(forward_rule_json "$NOBRAND_FORWARD_STATE_FILE" "$id")"
  old_backend="$(jq -r .backend <<<"$old")"
  new_backend="$FORWARD_BACKEND"
  case "$new_backend" in nftables|realm) ;; *) die 'switch-backend 需要 --backend nftables|realm' ;; esac
  [ "$new_backend" != "$old_backend" ] || die '端口转发规则已使用该后端'
  target="${FORWARD_TARGET_HOST:-$(jq -r .target_host <<<"$old")}"
  if [ "$new_backend" = nftables ] && ! forward_valid_ipv4 "$target"; then
    [ -n "$FORWARD_TARGET_HOST" ] \
      || die 'Realm 域名 / IPv6 目标切换到 nftables 时必须显式提供 --target IPv4；不会静默解析并固定域名'
  fi
  FORWARD_NAME="$(jq -r .name <<<"$old")"
  FORWARD_NOTE="$(jq -r .note <<<"$old")"
  FORWARD_PROTOCOL="$(jq -r .protocol <<<"$old")"
  FORWARD_LISTEN_HOST="${FORWARD_LISTEN_HOST:-$(jq -r .listen_host <<<"$old")}"
  if [ "$new_backend" = nftables ] && ! forward_valid_ipv4 "$FORWARD_LISTEN_HOST"; then
    FORWARD_LISTEN_HOST=0.0.0.0
  fi
  FORWARD_LISTEN_PORT="$(jq -r .listen_port <<<"$old")"
  FORWARD_TARGET_HOST="$target"
  FORWARD_TARGET_PORT="${FORWARD_TARGET_PORT:-$(jq -r .target_port <<<"$old")}"
  FORWARD_BACKEND="$new_backend"
  profile_id="$(jq -r '.ingress_profile_id // "legacy-default-route"' <<<"$old")"
  forward_prepare_ingress_enforcement "$new_backend" "$profile_id" \
    || die '切换后端后无法实施原 Ingress Profile'
  forward_validate_requested_rule "forward:${id}" "$old" || die '切换后端参数无效'
  options="$(forward_default_options_json "$new_backend")" || die '后端选项无效'
  candidate="$(mktemp_file .forward-switch)" || return 1
  jq --arg id "$id" --arg backend "$new_backend" --arg listen_host "$FORWARD_LISTEN_HOST" \
    --arg target_host "$FORWARD_TARGET_HOST" --argjson target_port "$FORWARD_TARGET_PORT" \
    --argjson options "$options" --arg now "$(forward_now)" \
    --arg ingress_enforcement "$INGRESS_ENFORCEMENT_RESOLVED" \
    --arg ingress_method "$INGRESS_ENFORCEMENT_METHOD" --arg ingress_address "$INGRESS_LOCAL_ADDRESS" '
      (.rules[]|select(.rule_id==$id)) |=
       (.backend=$backend|.listen_host=$listen_host|.target_host=$target_host|.target_port=$target_port|
         .backend_options=$options|.ingress_enforcement=$ingress_enforcement|
         .ingress_enforcement_method=$ingress_method|.ingress_local_address=$ingress_address|.updated_at=$now)
    ' "$NOBRAND_FORWARD_STATE_FILE" >"$candidate" \
    && forward_transaction_commit "$candidate" switch-backend "$old_backend" "$new_backend"
  local rc=$?
  rm -f "$candidate"
  return "$rc"
}

forward_apply_ingress_enforcement() {
  local id="$1" rule backend profile_id candidate rc
  rule="$(forward_rule_json "$NOBRAND_FORWARD_STATE_FILE" "$id")" || return 1
  [ -n "$rule" ] || return 1
  backend="$(jq -r .backend <<<"$rule")"
  profile_id="$(jq -r '.ingress_profile_id // "legacy-default-route"' <<<"$rule")"
  FORWARD_LISTEN_HOST="$(jq -r .listen_host <<<"$rule")"
  forward_prepare_ingress_enforcement "$backend" "$profile_id" || return 1
  [ "$INGRESS_ENFORCEMENT_RESOLVED" != permissive ] || FORWARD_LISTEN_HOST=0.0.0.0
  candidate="$(mktemp_file .forward-ingress-apply)" || return 1
  jq --arg id "$id" --arg listen "$FORWARD_LISTEN_HOST" \
    --arg policy "$INGRESS_ENFORCEMENT_RESOLVED" --arg method "$INGRESS_ENFORCEMENT_METHOD" \
    --arg address "$INGRESS_LOCAL_ADDRESS" --arg now "$(forward_now)" '
      (.rules[]|select(.rule_id==$id)) |=
        (.listen_host=$listen|.ingress_enforcement=$policy|
         .ingress_enforcement_method=$method|.ingress_local_address=$address|.updated_at=$now)
    ' "$NOBRAND_FORWARD_STATE_FILE" >"$candidate" \
    && forward_transaction_commit "$candidate" ingress-enforcement "$backend" "$backend"
  rc=$?
  rm -f "$candidate"
  return "$rc"
}

forward_listener_enforcement_owned() {
  local id="$1" rule backend
  rule="$(forward_rule_json "$NOBRAND_FORWARD_STATE_FILE" "$id")" || return 1
  [ -n "$rule" ] || return 1
  backend="$(jq -r .backend <<<"$rule")"
  case "$backend" in
    nftables) forward_nft_rule_ingress_owned "$id" ;;
    realm) forward_realm_service_active && forward_realm_listener_owned "$NOBRAND_FORWARD_STATE_FILE" ;;
    *) return 1 ;;
  esac
}

forward_list_rules() {
  forward_init_state || return 1
  printf '%-18s %-20s %-10s %-6s %-22s %-11s %-28s %s\n' ID 名称 后端 协议 实际监听 强制策略 目标 状态
  jq -r '.rules|sort_by(.rule_id)[]|[.rule_id,.name,.backend,.protocol,
    (.listen_host+":"+(.listen_port|tostring)),(.ingress_enforcement // "permissive"),(.target_host+":"+(.target_port|tostring)),
    (.enabled|tostring)]|@tsv' "$NOBRAND_FORWARD_STATE_FILE" \
    | while IFS=$'\t' read -r id name backend protocol listen enforcement target status; do
        [ "$status" = true ] && status='已启用' || status='已禁用'
        printf '%-18s %-20s %-10s %-6s %-22s %-11s %-28s %s\n' \
          "$id" "$name" "$backend" "$protocol" "$listen" "$enforcement" "$target" "$status"
      done
}

forward_node_rows() {
  local auto_host id name backend enabled protocol display_mode display_host display_port listen_port
  local effective_host effective_port status
  [ -s "$NOBRAND_FORWARD_STATE_FILE" ] || return 0
  auto_host="$(public_ip 2>/dev/null || printf 'YOUR_SERVER_IP')"
  local ingress_profile_id
  while IFS=$'\x1f' read -r id name backend enabled protocol display_mode display_host display_port listen_port ingress_profile_id; do
    effective_host="$display_host"
    [ "$display_mode" = custom ] \
      || effective_host="$(nb_effective_advertise_host auto '' "$ingress_profile_id")"
    effective_port="$display_port"
    [ "$display_mode" = custom ] \
      || effective_port="$(nb_effective_advertise_port auto '' "$listen_port" "$ingress_profile_id")"
    status=Disabled
    if [ "$enabled" = true ]; then
      if [ "$backend" = nftables ]; then
        status=Degraded
        forward_nft_rule_owned "$id" && status=Healthy
      else
        status=Degraded
        forward_realm_service_active && status=Healthy
      fi
    fi
    printf 'Port Forward/%s|%s|%s:%s|%s|%s\n' \
      "$backend" "$name" "$effective_host" "$effective_port" "$status" "$(printf '%s' "$protocol" | tr '[:lower:]' '[:upper:]')"
  done < <(jq -r '.rules|sort_by(.rule_id)[]|[.rule_id,.name,.backend,(.enabled|tostring),.protocol,
    .display_mode,.display_host,(.display_port|tostring),(.listen_port|tostring),(.ingress_profile_id // "legacy-default-route")]|join("\u001f")' \
    "$NOBRAND_FORWARD_STATE_FILE")
}

forward_show_rule() {
  local id rule display_host display_port enabled display_mode
  id="$(forward_resolve_rule_id "$FORWARD_RULE_ID")" || die '端口转发规则不存在'
  rule="$(forward_rule_json "$NOBRAND_FORWARD_STATE_FILE" "$id")"
  display_host="$(nb_effective_advertise_host "$(jq -r .display_mode <<<"$rule")" "$(jq -r .display_host <<<"$rule")" "$(jq -r '.ingress_profile_id // "legacy-default-route"' <<<"$rule")")"
  display_port="$(nb_effective_advertise_port "$(jq -r .display_mode <<<"$rule")" \
    "$(jq -r .display_port <<<"$rule")" "$(jq -r .listen_port <<<"$rule")" "$(jq -r '.ingress_profile_id // "legacy-default-route"' <<<"$rule")")"
  enabled="$(jq -r .enabled <<<"$rule")"
  [ "$enabled" = true ] && enabled='已启用' || enabled='已禁用'
  display_mode="$(jq -r .display_mode <<<"$rule")"
  case "$display_mode" in auto) display_mode='自动' ;; custom) display_mode='自定义' ;; esac
  printf 'ID: %s\n名称: %s\n备注: %s\n后端: %s\n状态: %s\n协议: %s\n' \
    "$id" "$(jq -r .name <<<"$rule")" "$(jq -r .note <<<"$rule")" "$(jq -r .backend <<<"$rule")" \
    "$enabled" "$(jq -r .protocol <<<"$rule")"
  printf '实际监听 / Actual Listener: %s:%s\n目标: %s:%s\n展示端点 / Display Endpoint: %s:%s\n展示模式: %s\n' \
    "$(jq -r .listen_host <<<"$rule")" "$(jq -r .listen_port <<<"$rule")" \
    "$(jq -r .target_host <<<"$rule")" "$(jq -r .target_port <<<"$rule")" \
    "$display_host" "$display_port" "$display_mode"
  printf '入口配置 / Ingress Profile: %s\n' "$(nb_ingress_profile_name "$(jq -r '.ingress_profile_id // "legacy-default-route"' <<<"$rule")")"
  printf 'Ingress 强制策略: %s (%s)\nIngress 本地地址: %s\n' \
    "$(jq -r '.ingress_enforcement // "permissive"' <<<"$rule")" \
    "$(jq -r '.ingress_enforcement_method // "wildcard"' <<<"$rule")" \
    "$(jq -r '.ingress_local_address // empty' <<<"$rule")"
  printf '后端选项: %s\n' "$(jq -c .backend_options <<<"$rule")"
}

forward_doctor() {
  local failed=0 id backend enabled protocol port target transport owner count
  forward_state_valid "$NOBRAND_FORWARD_STATE_FILE" || { warn '端口转发状态: FAIL'; return 1; }
  msg '端口转发状态: PASS（schema v3）'
  while IFS=$'\t' read -r id backend enabled protocol port target; do
    owner="forward:${id}"
    while IFS= read -r transport; do
      [ "$(nb_registry_port_owner "$transport" "$port" 2>/dev/null || true)" = "$owner" ] \
        || { warn "${id} 端口登记 ${transport}/${port}: FAIL"; failed=1; }
    done < <(forward_protocol_transports "$protocol")
    forward_target_valid "$backend" "$target" || { warn "${id} 目标地址: FAIL"; failed=1; }
    [ "$enabled" = true ] || continue
    if [ "$backend" = nftables ]; then
      forward_nft_rule_ingress_owned "$id" \
        || { warn "${id} nftables 归属校验: FAIL"; failed=1; }
      [ "$(sysctl -n net.ipv4.ip_forward 2>/dev/null || true)" = 1 ] \
        || { warn "${id} ip_forward: FAIL"; failed=1; }
    else
      forward_realm_service_active || { warn "${id} Realm 服务: FAIL"; failed=1; }
    fi
  done < <(jq -r '.rules[]|[.rule_id,.backend,(.enabled|tostring),.protocol,
    (.listen_port|tostring),.target_host]|@tsv' "$NOBRAND_FORWARD_STATE_FILE")
  count="$(jq '[.rules[]|select(.enabled and .backend=="realm")]|length' "$NOBRAND_FORWARD_STATE_FILE")"
  [ "$count" -eq 0 ] || forward_realm_listener_owned "$NOBRAND_FORWARD_STATE_FILE" \
    || { warn 'Realm 监听归属校验: FAIL'; failed=1; }
  [ "$failed" -eq 0 ] && msg '端口转发 Doctor / 诊断: PASS'
  [ "$failed" -eq 0 ]
}

forward_import_apply() {
  local source="$FORWARD_IMPORT_FILE" candidate
  [ -n "$source" ] || die 'forward import 需要文件路径'
  forward_import_validate "$source" || die 'Forward import 文件无效或包含未知字段'
  candidate="$(mktemp_file .forward-import)" || return 1
  jq '{schema_version:.schema_version,ownership:.ownership,feature:"port-forward",rules:.rules}' "$source" >"$candidate" \
    && forward_transaction_commit "$candidate" import '' ''
  local rc=$?
  rm -f "$candidate"
  return "$rc"
}

forward_realm_restore_runtime() {
  local count channel version
  [ -s "$NOBRAND_FORWARD_STATE_FILE" ] || return 0
  count="$(jq '[.rules[]|select(.backend=="realm")]|length' "$NOBRAND_FORWARD_STATE_FILE")"
  [ "$count" -gt 0 ] || return 0
  if [ -x "$NOBRAND_REALM_BIN" ] && forward_realm_runtime_metadata_valid; then
    return 0
  fi
  forward_realm_runtime_metadata_valid || return 1
  channel="$(jq -r '.channel' "$NOBRAND_REALM_RUNTIME_META")"
  version="$(jq -r '.version' "$NOBRAND_REALM_RUNTIME_META")"
  case "$channel" in
    stable) forward_realm_install_runtime stable ;;
    latest|pinned) forward_realm_install_runtime pinned "$version" ;;
    *) return 1 ;;
  esac
}

forward_snapshot_restore_side_effects() {
  local snapshot="$1" item label path runtime_owned=0
  mkdir -p "$snapshot/sysctl" || return 1
  forward_sysctl_snapshot "$snapshot/sysctl" || return 1
  forward_realm_runtime_metadata_valid && runtime_owned=1
  for item in \
    "binary|$NOBRAND_REALM_BIN" \
    "metadata|$NOBRAND_REALM_RUNTIME_META" \
    "systemd-service|$NOBRAND_REALM_SYSTEMD_SERVICE" \
    "openrc-service|$NOBRAND_REALM_OPENRC_SERVICE"; do
    label="${item%%|*}"; path="${item#*|}"
    if [ -e "$path" ] || [ -L "$path" ]; then
      case "$label" in
        binary|metadata)
          if [ "$runtime_owned" -eq 1 ]; then
            cp -a "$path" "$snapshot/$label" || return 1
          else
            : >"$snapshot/${label}.external" || return 1
          fi
          ;;
        systemd-service|openrc-service)
          if forward_realm_service_path_owned "$path"; then
            cp -a "$path" "$snapshot/$label" || return 1
          else
            : >"$snapshot/${label}.external" || return 1
          fi
          ;;
      esac
    else
      : >"$snapshot/${label}.absent" || return 1
    fi
  done
  if command -v nft >/dev/null 2>&1 \
     && nft list table "$NOBRAND_FORWARD_NFT_FAMILY" "$NOBRAND_FORWARD_NFT_TABLE" >/dev/null 2>&1; then
    if forward_nft_table_owned; then
      # `nft list table` is not a round-trip serialization on every supported
      # nftables version: it may resolve service names and can optimize away
      # the l4proto context required to parse `ct original proto-dst` again.
      # Rebuild the snapshot from the validated authoritative state instead.
      [ -s "$NOBRAND_FORWARD_STATE_FILE" ] \
        && forward_state_valid "$NOBRAND_FORWARD_STATE_FILE" \
        && forward_generate_nft_ruleset "$NOBRAND_FORWARD_STATE_FILE" "$snapshot/nft-table.nft" \
        || return 1
    else
      : >"$snapshot/nft-table.external" || return 1
    fi
  else
    : >"$snapshot/nft-table.absent" || return 1
  fi
}

forward_remove_restore_attempt_resources() {
  local failed=0
  if forward_realm_service_file_owned; then
    forward_realm_service_action stop >/dev/null 2>&1 || failed=1
  fi
  forward_remove_owned_nft_table >/dev/null 2>&1 || failed=1
  [ "$failed" -eq 0 ]
}

forward_restore_side_effect_snapshot() {
  local snapshot="$1" item label path mode failed=0
  forward_remove_restore_attempt_resources || failed=1
  for item in \
    "binary|$NOBRAND_REALM_BIN|0755" \
    "metadata|$NOBRAND_REALM_RUNTIME_META|0600" \
    "systemd-service|$NOBRAND_REALM_SYSTEMD_SERVICE|0644" \
    "openrc-service|$NOBRAND_REALM_OPENRC_SERVICE|0755"; do
    label="${item%%|*}"
    path="${item#*|}"; path="${path%%|*}"
    mode="${item##*|}"
    if [ -f "$snapshot/${label}.external" ] && [ ! -L "$snapshot/${label}.external" ]; then
      :
    elif [ -e "$snapshot/$label" ]; then
      nb_atomic_install_file "$snapshot/$label" "$path" "$mode" || failed=1
    elif [ -f "$snapshot/${label}.absent" ] && [ ! -L "$snapshot/${label}.absent" ]; then
      rm -f "$path" || failed=1
    else
      failed=1
    fi
  done
  if [ -s "$snapshot/nft-table.nft" ]; then
    command -v nft >/dev/null 2>&1 && nft -c -f "$snapshot/nft-table.nft" >/dev/null 2>&1 \
      && nft -f "$snapshot/nft-table.nft" || failed=1
  elif [ -f "$snapshot/nft-table.external" ] && [ ! -L "$snapshot/nft-table.external" ]; then
    :
  elif [ -f "$snapshot/nft-table.absent" ] && [ ! -L "$snapshot/nft-table.absent" ]; then
    :
  else
    failed=1
  fi
  forward_sysctl_restore_snapshot "$snapshot/sysctl" || failed=1
  [ "$(nb_service_manager)" != systemd ] || systemctl daemon-reload >/dev/null 2>&1 || failed=1
  [ "$failed" -eq 0 ]
}

forward_uninstall() {
  local empty service_path
  forward_init_state || return 1
  empty="$(mktemp_file .forward-empty)" || return 1
  jq '.rules=[]' "$NOBRAND_FORWARD_STATE_FILE" >"$empty" \
    && forward_transaction_commit "$empty" uninstall '' '' || { rm -f "$empty"; return 1; }
  rm -f "$empty"
  forward_realm_service_action stop >/dev/null 2>&1 || true
  service_path="$(forward_realm_service_path 2>/dev/null || true)"
  if [ -n "$service_path" ] && forward_realm_service_path_owned "$service_path"; then
    case "$(nb_service_manager)" in
    systemd)
      systemctl disable "$NOBRAND_REALM_SERVICE_NAME" >/dev/null 2>&1 || true
      rm -f "$NOBRAND_REALM_SYSTEMD_SERVICE"
      systemctl daemon-reload >/dev/null 2>&1 || true
      ;;
    openrc)
      rc-update del "$NOBRAND_REALM_SERVICE_NAME" default >/dev/null 2>&1 || true
      rm -f "$NOBRAND_REALM_OPENRC_SERVICE"
      ;;
    esac
  fi
  if forward_realm_runtime_metadata_valid; then
    rm -f "$NOBRAND_REALM_BIN" "$NOBRAND_REALM_RUNTIME_META"
  fi
  forward_remove_owned_nft_table || return 1
  rm -f "$NOBRAND_FORWARD_REALM_CONFIG" "$NOBRAND_FORWARD_NFT_RULESET" "$NOBRAND_FORWARD_STATE_FILE"
  msg '端口转发已卸载；外部 nftables 表与外部 Realm 安装均已保留。'
}

forward_usage() {
  cat <<'EOF'
端口转发 / Port Forward：
  nobrand forward add --name NAME --backend nftables|realm --protocol TCP|UDP|BOTH \
    --listen 0.0.0.0 --port PORT --target HOST --target-port PORT
  nobrand forward list
  nobrand forward show|delete|modify|enable|disable RULE
  nobrand forward set-endpoint RULE --advertise-host HOST --advertise-port PORT
  nobrand forward switch-backend RULE --backend nftables|realm [--target IPv4]
  nobrand forward doctor
  nobrand forward export [FILE]
  nobrand forward import FILE

nftables 目标必须是 IPv4 字面地址；Realm 目标可以是 IPv4、IPv6 或域名。
本地 IPv4 尾号推导的 xx00 基准端口会为所有后端和传输保留。
EOF
}

nobrand_run_forward_action() {
  if [ "${FORWARD_ACTION:-menu}" = recover-add ]; then
    nobrand_recover_forward_add
  elif [ "${FORWARD_ACTION:-menu}" = add ] \
     && [ "${NOBRAND_MANAGER_SESSION_ACTIVE:-0}" -eq 1 ]; then
    nb_lifecycle_run_protocol_install forward nobrand_run_forward_action_unscoped
  else
    nobrand_run_forward_action_unscoped
  fi
}

nobrand_recover_forward_add() {
  local phase="" recovery_mode=retry rc=0 restore_errexit=0 saved_err_trap=""
  require_root || return 1
  require_linux || return 1
  nb_lifecycle_lock_acquire || return 1
  nb_lifecycle_tx_valid \
    && [ "$(nb_lifecycle_field STATUS)" = in-progress ] \
    && [ "$(nb_lifecycle_field OPERATION)" = install ] \
    && [ "$(nb_lifecycle_scope)" = forward ] || {
      nb_lifecycle_lock_release
      return 1
    }
  if [ "$(nb_lifecycle_mutation_started)" = 0 ]; then
    nb_lifecycle_clear || {
      nb_lifecycle_lock_release
      return 1
    }
    nb_lifecycle_lock_release
    t 'Forward 新增操作在写入规则前中止；已清除临时恢复信息，请重新开始。' \
      'Forward add stopped before a rule was written; temporary recovery metadata was cleared. Start again.'
    return 0
  fi
  phase="$(nb_lifecycle_field LAST_COMPLETED_PHASE)"
  recovery_mode="$(nb_lifecycle_protocol_recovery_mode forward "$phase")" || {
    nb_lifecycle_lock_release
    return 1
  }
  if [ "$recovery_mode" = retry ]; then
    nb_lifecycle_lock_release
    warn "$(t \
      'Forward 权威状态未变化，但原始请求与系统前态未持久记录；自动清理或重放并不安全。恢复信息已原样保留，请人工检查后处理。' \
      'Forward authoritative state is unchanged, but the original request and system pre-state were not durably recorded; automatic cleanup or replay is unsafe. Recovery metadata was preserved exactly; inspect the host and resolve it manually.')"
    return 1
  elif [ "$recovery_mode" != validate ]; then
    nb_lifecycle_lock_release
    return 1
  fi
  FORWARD_ACTION=add
  case "$-" in *e*) restore_errexit=1 ;; esac
  saved_err_trap="$(trap -p ERR || true)"
  trap - ERR
  set +e
  nb_lifecycle_run_protocol_install forward nobrand_run_forward_action_unscoped
  rc=$?
  [ "$restore_errexit" -eq 0 ] || set -e
  if [ -n "$saved_err_trap" ]; then
    eval "$saved_err_trap"
  else
    trap - ERR
  fi
  nb_lifecycle_lock_release
  return "$rc"
}

nobrand_run_forward_action_unscoped() {
  local lock_required=0 rc
  case "$FORWARD_ACTION" in
    add|delete|modify|enable|disable|set-endpoint|switch-backend|import|upgrade-runtime|uninstall)
      lock_required=1
      require_root || return 1
      nb_init_state_layout || return 1
      ensure_management_dependencies "$(detect_pkg_manager)" || return 1
      admin_lock_acquire || return 1
      ;;
  esac
  nobrand_run_forward_action_unlocked
  rc=$?
  [ "$lock_required" -eq 0 ] || admin_lock_release
  return "$rc"
}

nobrand_run_forward_action_unlocked() {
  case "$FORWARD_ACTION" in
    menu) forward_menu_loop ;;
    add) forward_add_rule ;;
    delete) [ -n "$FORWARD_RULE_ID" ] || die 'forward delete 需要 RULE'; forward_delete_rule ;;
    modify) [ -n "$FORWARD_RULE_ID" ] || die 'forward modify 需要 RULE'; forward_modify_rule ;;
    list) forward_list_rules ;;
    show) [ -n "$FORWARD_RULE_ID" ] || die 'forward show 需要 RULE'; forward_show_rule ;;
    enable) [ -n "$FORWARD_RULE_ID" ] || die 'forward enable 需要 RULE'; forward_set_enabled true ;;
    disable) [ -n "$FORWARD_RULE_ID" ] || die 'forward disable 需要 RULE'; forward_set_enabled false ;;
    set-endpoint)
      [ -n "$FORWARD_RULE_ID" ] || die 'forward set-endpoint 需要 RULE'
      if [ "$ADVERTISE_AUTO_REQUESTED" -eq 1 ]; then
        forward_set_endpoint_state "$FORWARD_RULE_ID" auto '' ''
      else
        [ "$ADVERTISE_CLI" -eq 1 ] || die 'set-endpoint 需要 --advertise-host/--advertise-port 或 --advertise-auto'
        forward_set_endpoint_state "$FORWARD_RULE_ID" custom "$ADVERTISE_HOST" "$ADVERTISE_PORT"
      fi
      ;;
    switch-backend) [ -n "$FORWARD_RULE_ID" ] || die 'switch-backend 需要 RULE'; forward_switch_backend ;;
    doctor) forward_doctor ;;
    export) forward_export_json "$FORWARD_EXPORT_FILE" ;;
    import) forward_import_apply ;;
    upgrade-runtime) forward_realm_install_runtime stable ;;
    uninstall) forward_uninstall ;;
    help) forward_usage ;;
    *) die "未知 Port Forward 操作: $FORWARD_ACTION" ;;
  esac
}

bbr_fq_sysctl_value() {
  local key="$1" path value=""
  if command -v sysctl >/dev/null 2>&1; then
    value="$(sysctl -n "$key" 2>/dev/null || true)"
  else
    path="/proc/sys/${key//./\/}"
    [ -r "$path" ] && value="$(tr -d '\r\n' <"$path" 2>/dev/null || true)"
  fi
  printf '%s' "$value"
}

bbr_fq_enabled() {
  [ "$(bbr_fq_sysctl_value net.ipv4.tcp_congestion_control)" = "bbr" ] \
    && [ "$(bbr_fq_sysctl_value net.core.default_qdisc)" = "fq" ]
}

bbr_fq_active() {
  local dev
  bbr_fq_enabled || return 1
  command -v tc >/dev/null 2>&1 || return 1
  dev="$(tc_default_iface 2>/dev/null || mtu_default_iface 2>/dev/null || true)"
  [ -n "$dev" ] || return 1
  tc qdisc show dev "$dev" 2>/dev/null \
    | grep -Eq '(^|[[:space:]])qdisc[[:space:]]+fq([[:space:]]|$)'
}

report_bbr_fq_status() {
  if bbr_fq_active; then
    t 'TCP BBR 已启用，当前出口网卡正在使用 FQ' \
      'TCP BBR is enabled and the current egress interface is using FQ'
  else
    warn "$(t 'TCP BBR + FQ 默认策略已配置；当前出口网卡尚未使用 FQ，重启系统或重建网卡后生效' \
      'TCP BBR + FQ defaults are configured; the current egress interface is not using FQ yet, so reboot or recreate the interface to activate it')"
  fi
}

bbr_owned_mode() {
  local mode=""
  [ -f "$BBR_STATE_FILE" ] || return 1
  IFS= read -r mode <"$BBR_STATE_FILE" || return 1
  case "$mode" in
    created|replaced) printf '%s' "$mode" ;;
    *) return 1 ;;
  esac
}

write_bbr_state() {
  local mode="$1" old_qdisc="$2" old_cc="$3" tmp
  case "$mode" in created|replaced) ;; *) return 1 ;; esac
  [[ "$old_qdisc" =~ ^[A-Za-z0-9_.-]*$ ]] || return 1
  [[ "$old_cc" =~ ^[A-Za-z0-9_.-]*$ ]] || return 1
  tmp="$(mktemp_file .bbr-state)" || return 1
  printf '%s\n%s\n%s\n' "$mode" "$old_qdisc" "$old_cc" >"$tmp"
  install -d -o root -g root -m 0700 "$NOBRAND_STATE_DIR"
  install -o root -g root -m 0600 "$tmp" "$BBR_STATE_FILE"
  rm -f "$tmp"
}

bbr_conf_is_owned() {
  [ -f "$BBR_SYSCTL_CONF" ] || return 1
  [ "$(sed '/^[[:space:]]*#/d;/^[[:space:]]*$/d' "$BBR_SYSCTL_CONF" 2>/dev/null)" = \
    $'net.core.default_qdisc=fq\nnet.ipv4.tcp_congestion_control=bbr' ]
}

restore_bbr_fq() {
  local backup="$1" old_qdisc="$2" old_cc="$3" had_conf="${4:-1}"
  if [ "$had_conf" -eq 1 ] && [ -n "$backup" ] && [ -f "$backup" ]; then
    install -o root -g root -m 0644 "$backup" "$BBR_SYSCTL_CONF" 2>/dev/null || true
  else
    rm -f "$BBR_SYSCTL_CONF" 2>/dev/null || true
  fi
  [ -n "$old_qdisc" ] \
    && sysctl -q -w "net.core.default_qdisc=${old_qdisc}" >/dev/null 2>&1 || true
  [ -n "$old_cc" ] \
    && sysctl -q -w "net.ipv4.tcp_congestion_control=${old_cc}" >/dev/null 2>&1 || true
  [ -z "$backup" ] || rm -f "$backup"
}

enable_bbr_fq() {
  STAGE="启用 TCP BBR + FQ"
  if bbr_fq_enabled; then
    report_bbr_fq_status
    return 0
  fi
  require_cmd sysctl

  local available old_qdisc old_cc tmp backup="" had_conf=0 owned_mode=""
  if command -v modprobe >/dev/null 2>&1; then
    run modprobe tcp_bbr 2>/dev/null || true
    run modprobe sch_fq 2>/dev/null || true
  fi
  available="$(bbr_fq_sysctl_value net.ipv4.tcp_available_congestion_control)"
  case " ${available} " in
    *' bbr '*) ;;
    *)
      die "$(t '当前内核不支持 TCP BBR' 'TCP BBR is not supported by the current kernel')"
      return 1
      ;;
  esac

  old_qdisc="$(bbr_fq_sysctl_value net.core.default_qdisc)"
  old_cc="$(bbr_fq_sysctl_value net.ipv4.tcp_congestion_control)"
  owned_mode="$(bbr_owned_mode 2>/dev/null || true)"
  if [ -e "$BBR_STATE_FILE" ] && [ -z "$owned_mode" ]; then
    die "$(t 'BBR 所有权状态损坏，拒绝覆盖系统 sysctl 配置' \
      'BBR ownership state is invalid; refusing to overwrite system sysctl configuration')"
    return 1
  fi
  if [ -n "$owned_mode" ] && ! bbr_conf_is_owned; then
    die "$(t 'BBR sysctl 文件已被外部修改，拒绝覆盖；请先人工核对' \
      'The BBR sysctl file was modified externally; refusing to overwrite it')"
    return 1
  fi
  if [ -f "$BBR_SYSCTL_CONF" ]; then
    had_conf=1
    backup="$(mktemp_file .bbr-backup)" || return 1
    cp -p "$BBR_SYSCTL_CONF" "$backup" || { rm -f "$backup"; return 1; }
  fi
  tmp="$(mktemp_file .bbr-conf)" || { [ -z "$backup" ] || rm -f "$backup"; return 1; }
  printf '%s\n' \
    'net.core.default_qdisc=fq' \
    'net.ipv4.tcp_congestion_control=bbr' >"$tmp"
  run mkdir -p "$(dirname "$BBR_SYSCTL_CONF")"
  if ! run install -o root -g root -m 0644 "$tmp" "$BBR_SYSCTL_CONF"; then
    rm -f "$tmp"
    [ -z "$backup" ] || rm -f "$backup"
    return 1
  fi
  rm -f "$tmp"

  if ! run sysctl -p "$BBR_SYSCTL_CONF" || ! bbr_fq_enabled; then
    restore_bbr_fq "$backup" "$old_qdisc" "$old_cc" "$had_conf"
    die "$(t '启用 TCP BBR + FQ 失败，已恢复原配置' \
      'Failed to enable TCP BBR + FQ; the previous configuration was restored')"
    return 1
  fi
  if [ -z "$owned_mode" ]; then
    if [ "$had_conf" -eq 1 ]; then
      if ! install -d -o root -g root -m 0700 "$NOBRAND_STATE_DIR" \
         || ! install -o root -g root -m 0600 "$backup" "$BBR_BACKUP_FILE" \
         || ! write_bbr_state replaced "$old_qdisc" "$old_cc"; then
        rm -f "$BBR_STATE_FILE" "$BBR_BACKUP_FILE"
        restore_bbr_fq "$backup" "$old_qdisc" "$old_cc" "$had_conf"
        return 1
      fi
    elif ! write_bbr_state created "$old_qdisc" "$old_cc"; then
      rm -f "$BBR_STATE_FILE" "$BBR_BACKUP_FILE"
      restore_bbr_fq "$backup" "$old_qdisc" "$old_cc" "$had_conf"
      return 1
    fi
  fi
  [ -z "$backup" ] || rm -f "$backup"
  report_bbr_fq_status
}

offer_bbr_fq() {
  if bbr_fq_enabled; then
    t '检测到 TCP BBR + FQ 默认策略已配置，跳过写入' \
      'TCP BBR + FQ defaults are already configured; skipping file changes'
    report_bbr_fq_status
    return 0
  fi
  if [ "$ENABLE_BBR" -eq 1 ]; then
    enable_bbr_fq
  elif confirm '未检测到完整的 TCP BBR + FQ，是否现在启用？[Y/n]: ' \
    'TCP BBR + FQ are not fully enabled. Enable them now? [Y/n]: ' y; then
    enable_bbr_fq
  else
    t '已跳过 TCP BBR + FQ 配置' 'Skipped TCP BBR + FQ configuration'
  fi
}

urlencode() {
  local value="$1"
  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$value"
    return 0
  fi
  if [[ "$value" =~ ^[a-zA-Z0-9._~-]+$ ]]; then
    printf '%s' "$value"
    return 0
  fi
  die "$(t '密码含特殊字符时需要 python3 以生成节点链接' \
    'python3 required to encode special characters in share link')"
}

url_host() {
  local host="$1"
  if [[ "$host" == *:* ]] && [[ "$host" != \[*\] ]]; then
    printf '[%s]' "$host"
  else
    printf '%s' "$host"
  fi
}

# Ordinary protocol runtime and exports are managed by the native Splicore adapter.

nb_lifecycle_validate_manager_repair() {
  local installed=""
  nb_schema_v3_file_valid || return 1
  installed="$(nb_installed_manager_version 2>/dev/null || true)"
  [ "$installed" = "$SCRIPT_VERSION" ]
}

nobrand_manager_bootstrap() {
  nb_splicore_legacy_preflight || return 1
  local state operation scope="" pm rc=0
  local recovery_expected_scope="${NOBRAND_RECOVERY_EXPECTED_SCOPE:-}"
  local recovery_expected_state="${NOBRAND_RECOVERY_EXPECTED_STATE:-}"
  local recovery_expected_tx_present="${NOBRAND_RECOVERY_EXPECTED_TX_PRESENT:-0}"
  local recovery_expected_tx_status="${NOBRAND_RECOVERY_EXPECTED_TX_STATUS:-}"
  local recovery_expected_tx_id="${NOBRAND_RECOVERY_EXPECTED_TX_ID:-}"
  local recovery_expected_tx_record="${NOBRAND_RECOVERY_EXPECTED_TX_RECORD:-}"
  require_root || return 1
  require_linux || return 1
  pm="$(detect_pkg_manager)" || return 1
  ensure_management_dependencies "$pm" || return 1
  nb_lifecycle_lock_acquire || return 1
  state="$(nb_classify_installation_state)" || {
    nb_lifecycle_lock_release
    return 1
  }
  if [ -n "$recovery_expected_scope" ] && [ "$recovery_expected_scope" != manager ]; then
    nb_lifecycle_lock_release
    warn "$(t '原恢复选择不属于管理器范围；拒绝作为新的管理器安装执行。' \
      'The recovery choice is not manager-scoped; refusing to execute it as a new manager install.')"
    return 1
  fi
  if [ -z "$recovery_expected_scope" ] \
     && [ "$state" = CURRENT_COMPLETE ] \
     && nobrand_manager_installation_valid; then
    ensure_manager_state_layout 0 || {
      nb_lifecycle_lock_release
      return 1
    }
    nb_lifecycle_lock_release
    return 0
  fi
  if [ -n "$recovery_expected_scope" ]; then
    [ -n "$recovery_expected_state" ] \
      && [ "$state" = "$recovery_expected_state" ] || {
        nb_lifecycle_lock_release
        warn "$(t '原管理器恢复状态已由其它进程改变；拒绝把旧选择作为新的管理器安装执行。' \
          'The manager recovery state changed in another process; refusing to execute the stale choice as a new manager install.')"
        return 1
      }
    case "$recovery_expected_tx_present" in
      0)
        if [ -e "$NOBRAND_LIFECYCLE_TX_FILE" ] \
           || [ -L "$NOBRAND_LIFECYCLE_TX_FILE" ]; then
          nb_lifecycle_lock_release
          warn "$(t '原管理器残留恢复期间出现了新的生命周期事务；拒绝继续。' \
            'A new lifecycle transaction appeared during manager-residue recovery; refusing to continue.')"
          return 1
        fi
        case "$state" in
          CURRENT_PARTIAL_INSTALL|CURRENT_PARTIAL_REPAIR) operation=repair ;;
          *) nb_lifecycle_lock_release; return 1 ;;
        esac
        ;;
      1)
        nb_lifecycle_tx_valid \
          && [ "$(nb_lifecycle_field STATUS)" = "$recovery_expected_tx_status" ] \
          && [ "$(nb_lifecycle_field TRANSACTION_ID)" = "$recovery_expected_tx_id" ] \
          && [ "$(<"$NOBRAND_LIFECYCLE_TX_FILE")" = "$recovery_expected_tx_record" ] || {
            nb_lifecycle_lock_release
            warn "$(t '原管理器恢复事务已由其它进程改变；拒绝把旧选择作为新的管理器安装执行。' \
              'The manager recovery transaction changed in another process; refusing to execute the stale choice as a new manager install.')"
            return 1
          }
        case "$recovery_expected_tx_status" in
          in-progress)
            [ "$(nb_lifecycle_scope)" = manager ] || {
              nb_lifecycle_lock_release
              return 1
            }
            operation="$(nb_lifecycle_field OPERATION)"
            case "$operation:$state" in
              install:CURRENT_PARTIAL_INSTALL|repair:CURRENT_PARTIAL_REPAIR) ;;
              *) nb_lifecycle_lock_release; return 1 ;;
            esac
            ;;
          complete)
            case "$state" in
              CURRENT_PARTIAL_INSTALL|CURRENT_PARTIAL_REPAIR) operation=repair ;;
              *) nb_lifecycle_lock_release; return 1 ;;
            esac
            ;;
          *) nb_lifecycle_lock_release; return 1 ;;
        esac
        ;;
      *) nb_lifecycle_lock_release; return 1 ;;
    esac
  elif nb_lifecycle_tx_valid && [ "$(nb_lifecycle_field STATUS)" = in-progress ]; then
    scope="$(nb_lifecycle_scope)" || {
      nb_lifecycle_lock_release
      return 1
    }
    [ "$scope" = manager ] || {
      nb_lifecycle_lock_release
      warn "$(t "未完成的 ${scope} 操作必须先按其组件范围恢复" \
        "The unfinished ${scope} operation must be recovered within its component scope first")"
      return 1
    }
    operation="$(nb_lifecycle_field OPERATION)"
    case "$operation" in install|repair) ;; *) nb_lifecycle_lock_release; return 1 ;; esac
  else
    case "$state" in
      CLEAN) operation=install ;;
      CURRENT_COMPLETE|CURRENT_PARTIAL_INSTALL|CURRENT_PARTIAL_REPAIR)
        operation=repair
        ;;
      *)
        nb_lifecycle_lock_release
        return 1
        ;;
    esac
  fi
  nb_lifecycle_pre_mutation_snapshot || {
    nb_lifecycle_lock_release
    return 1
  }
  nb_lifecycle_begin "$operation" prepare 0 0 0 0 0 0 manager || {
    nb_lifecycle_pre_mutation_disarm
    nb_lifecycle_lock_release
    return 1
  }
  nb_lifecycle_mark_mutation_started || {
    rc=$?
    nb_lifecycle_restore_pre_mutation || rc=1
  }
  if [ "$rc" -eq 0 ]; then
    ensure_manager_state_layout 1 || rc=$?
  fi
  if [ "$rc" -eq 0 ]; then
    nb_lifecycle_checkpoint "$operation" state-layout 1 || rc=$?
  fi
  if [ "$rc" -eq 0 ]; then
    nobrand_install_manager_script || rc=$?
  fi
  if [ "$rc" -eq 0 ]; then
    nb_lifecycle_checkpoint "$operation" manager-ready || rc=$?
  fi
  if [ "$rc" -eq 0 ]; then
    nobrand_manager_installation_valid || rc=$?
  fi
  if [ "$rc" -eq 0 ]; then
    nb_lifecycle_checkpoint "$operation" ready-to-validate || rc=$?
  fi
  if [ "$rc" -eq 0 ]; then
    nb_lifecycle_validate_manager_repair || rc=$?
  fi
  if [ "$rc" -eq 0 ]; then
    nb_lifecycle_complete "$operation" || rc=$?
  fi
  nb_lifecycle_lock_release
  return "$rc"
}

nobrand_recover_ingress_scope() {
  local operation phase pm rc=0
  require_root || return 1
  require_linux || return 1
  pm="$(detect_pkg_manager)" || return 1
  ensure_management_dependencies "$pm" || return 1
  nb_lifecycle_lock_acquire || return 1
  nb_lifecycle_tx_valid \
    && [ "$(nb_lifecycle_field STATUS)" = in-progress ] \
    && [ "$(nb_lifecycle_scope)" = ingress ] || {
      nb_lifecycle_lock_release
      return 1
    }
  operation="$(nb_lifecycle_field OPERATION)"
  [ "$operation" = configure ] || {
    nb_lifecycle_lock_release
    return 1
  }
  if [ "$(nb_lifecycle_field FORMAT)" = nobrand-lifecycle-v2 ] \
     && [ "$(nb_lifecycle_mutation_started)" = 0 ]; then
    nb_lifecycle_clear || {
      nb_lifecycle_lock_release
      return 1
    }
    nb_lifecycle_lock_release
    t 'Ingress 操作在写入配置前中止；已清除临时恢复信息。' \
      'Ingress stopped before configuration was written; temporary recovery metadata was cleared.'
    return 0
  fi
  phase="$(nb_lifecycle_field LAST_COMPLETED_PHASE)"
  nb_lifecycle_begin configure "$phase" 0 0 0 0 0 0 ingress || {
    nb_lifecycle_lock_release
    return 1
  }
  ensure_manager_state_layout 1 || rc=$?
  if [ "$rc" -eq 0 ] && ! nobrand_manager_installation_valid; then
    warn "$(t '协议操作前的管理器安装无效；请先修复管理器，未执行协议回调。' \
      'The manager installation is invalid before the protocol action; repair the manager first. The protocol callback was not run.')"
    rc=1
  fi
  if [ "$rc" -eq 0 ] && [ -e "$NOBRAND_INGRESS_STATE_FILE" ]; then
    nb_ingress_state_valid || rc=$?
  fi
  if [ "$rc" -eq 0 ] && [ -e "$NOBRAND_INGRESS_FIREWALL_STATE_FILE" ]; then
    nb_strict_firewall_state_valid || rc=$?
  fi
  if [ "$rc" -eq 0 ] && [ "$(nb_lifecycle_mutation_started)" = 1 ]; then
    nobrand_reconcile_ingress_profiles || rc=$?
  fi
  if [ "$rc" -eq 0 ] && [ "$(nb_lifecycle_mutation_started)" = 1 ] \
     && declare -F nb_strict_firewall_restore_authoritative >/dev/null 2>&1; then
    nb_strict_firewall_restore_authoritative || rc=$?
  fi
  if [ "$rc" -eq 0 ]; then
    nb_lifecycle_checkpoint configure ready-to-validate || rc=$?
  fi
  if [ "$rc" -eq 0 ]; then
    nobrand_manager_installation_valid || rc=$?
  fi
  if [ "$rc" -eq 0 ]; then
    nb_lifecycle_complete configure || rc=$?
  fi
  nb_lifecycle_lock_release
  return "$rc"
}

nobrand_reconcile_ingress_profiles() {
  local profile_id profile_ids failed=0
  [ -e "$NOBRAND_INGRESS_STATE_FILE" ] || return 0
  nb_ingress_state_valid || return 1
  profile_ids="$(jq -r '.profiles[].profile_id' "$NOBRAND_INGRESS_STATE_FILE")" || return 1
  while IFS= read -r profile_id; do
    [ -n "$profile_id" ] || continue
    nb_ingress_apply_profile "$profile_id" || failed=1
  done <<<"$profile_ids"
  return "$failed"
}

# Emit an unambiguous record for one authoritative state path.  This manifest
# is hashed before a protocol install callback starts, allowing a later process
# to tell an untouched pre-callback state from a callback that committed state
# but died before the ordinary ready-to-validate checkpoint.
nb_lifecycle_protocol_state_manifest_record() {
  local label="$1" path="$2" size target kind
  if [ -L "$path" ]; then
    target="$(readlink -- "$path")" || return 1
    printf 'L\0%s\0%s\0' "$label" "$target"
  elif [ -f "$path" ]; then
    size="$(wc -c <"$path" | tr -d '[:space:]')" || return 1
    [[ "$size" =~ ^[0-9]+$ ]] || return 1
    printf 'F\0%s\0%s\0' "$label" "$size" || return 1
    command cat -- "$path" || return 1
    printf '\0'
  elif [ -e "$path" ]; then
    kind="$(stat -c '%F' -- "$path" 2>/dev/null || printf other)"
    printf 'O\0%s\0%s\0' "$label" "$kind"
  else
    printf 'A\0%s\0' "$label"
  fi
}

nb_lifecycle_protocol_scope_state_manifest() (
  local scope="$1" rules
  LC_ALL=C
  export LC_ALL
  shopt -s nullglob dotglob
  printf 'nobrand-protocol-callback-baseline-v1\0%s\0' "$scope" || return 1
  case "$scope" in
    vless-sudoku)
      nb_lifecycle_protocol_state_manifest_record state.json "$NOBRAND_VLESS_STATE_FILE"
      ;;
    ssh-tunnel)
      nb_lifecycle_protocol_state_manifest_record state.json "$NOBRAND_SSH_STATE_FILE"
      ;;
    forward)
      # Creating Forward's valid empty state is preparation, not an add
      # commit. Normalize absent and empty to the same logical rule set.
      if [ ! -e "$NOBRAND_FORWARD_STATE_FILE" ] && [ ! -L "$NOBRAND_FORWARD_STATE_FILE" ]; then
        printf 'R\0[]\0'
      elif [ -f "$NOBRAND_FORWARD_STATE_FILE" ] && [ ! -L "$NOBRAND_FORWARD_STATE_FILE" ] \
           && rules="$(jq -cS '
             if .schema_version==3 and .ownership=="nobrand-v3"
                and .feature=="port-forward" and (.rules|type)=="array"
             then .rules else error("invalid Forward state") end
           ' "$NOBRAND_FORWARD_STATE_FILE" 2>/dev/null)"; then
        printf 'R\0%s\0' "$rules"
      else
        nb_lifecycle_protocol_state_manifest_record state.json "$NOBRAND_FORWARD_STATE_FILE"
      fi
      ;;
    *) return 1 ;;
  esac
)

nb_lifecycle_protocol_scope_fingerprint() {
  local scope="$1" digest
  if command -v sha256sum >/dev/null 2>&1; then
    digest="$(nb_lifecycle_protocol_scope_state_manifest "$scope" \
      | sha256sum | awk 'NR==1 { print tolower($1) }')" || return 1
  elif command -v openssl >/dev/null 2>&1; then
    digest="$(nb_lifecycle_protocol_scope_state_manifest "$scope" \
      | openssl dgst -sha256 2>/dev/null | awk 'NR==1 { print tolower($NF) }')" || return 1
  else
    return 1
  fi
  [[ "$digest" =~ ^[0-9a-f]{64}$ ]] || return 1
  printf '%s' "$digest"
}

# Structural validity is deliberately separate from the runtime doctor.  A
# changed but malformed authoritative state fails closed and is never fed back
# through a potentially duplicating install callback.  Runtime validation runs
# after the transaction advances to ready-to-validate and remains retryable.
nb_lifecycle_protocol_scope_state_valid() (
  local scope="$1"
  shopt -s nullglob dotglob
  case "$scope" in
    vless-sudoku)
      [ -f "$NOBRAND_VLESS_STATE_FILE" ] && [ ! -L "$NOBRAND_VLESS_STATE_FILE" ] \
        && vless_sudoku_state_exists && vless_sudoku_state_matches
      ;;
    ssh-tunnel)
      [ -f "$NOBRAND_SSH_STATE_FILE" ] && [ ! -L "$NOBRAND_SSH_STATE_FILE" ] \
        && ssh_tunnel_state_identity_valid \
        && jq -e '
          (.users|type)=="array" and (.users|length)>0
          and .policy_applied==true
          and (.pending_operation // "")==""
          and (.pending_watchdog_token // "")==""
          and (.pending_watchdog_pid // "")==""
          and (.pending_origin_connection // "")==""
        ' "$NOBRAND_SSH_STATE_FILE" >/dev/null
      ;;
    forward)
      [ -f "$NOBRAND_FORWARD_STATE_FILE" ] && [ ! -L "$NOBRAND_FORWARD_STATE_FILE" ] \
        && forward_state_valid "$NOBRAND_FORWARD_STATE_FILE" \
        && jq -e '.rules | length > 0' "$NOBRAND_FORWARD_STATE_FILE" >/dev/null
      ;;
    *) return 1 ;;
  esac
)

nb_lifecycle_ssh_initialization_only() {
  [ -f "$NOBRAND_SSH_STATE_FILE" ] && [ ! -L "$NOBRAND_SSH_STATE_FILE" ] \
    && ssh_tunnel_state_identity_valid \
    && jq -e '
      (.users|type)=="array" and (.users|length)==0
      and .policy_applied==false
      and (.pending_operation // "")==""
      and (.pending_watchdog_token // "")==""
      and (.pending_watchdog_pid // "")==""
      and (.pending_origin_connection // "")==""
    ' "$NOBRAND_SSH_STATE_FILE" >/dev/null \
    && ssh_tunnel_policy_absent \
    && ssh_tunnel_watchdog_directory_empty_valid
}

nb_lifecycle_protocol_recovery_mode() {
  local scope="$1" phase="$2" baseline current
  if [ "$phase" = ready-to-validate ]; then
    [ "$(nb_lifecycle_mutation_started)" = 1 ] || return 1
    printf 'validate'
    return 0
  fi
  if [[ "$phase" =~ ^callback-([0-9a-f]{55})$ ]]; then
    [ "$(nb_lifecycle_mutation_started)" = 1 ] || return 1
    baseline="${BASH_REMATCH[1]}"
    current="$(nb_lifecycle_protocol_scope_fingerprint "$scope")" || return 1
    if [ "${current:0:55}" = "$baseline" ]; then
      printf 'retry'
      return 0
    fi
    if [ "$scope" = ssh-tunnel ] && nb_lifecycle_ssh_initialization_only; then
      warn "$(t \
        'SSH Tunnel 回调后的空状态不足以证明尚未创建系统账户；拒绝自动清理或重放，请保留范围信息并执行人工修复。' \
        'Empty SSH Tunnel state after the callback does not prove that no system account was created; refusing automatic cleanup or replay and retaining scoped metadata for manual repair.')"
      return 1
    fi
    if nb_lifecycle_protocol_scope_state_valid "$scope"; then
      if [ "$scope" = forward ]; then
        # Forward owns a dedicated add-recovery flow and its existing
        # committed-state behavior remains validation-only.
        printf 'validate'
      else
        printf 'validate-changed'
      fi
      return 0
    fi
    warn "$(t "${scope} 安装回调开始后权威状态已变化但无效；拒绝重放安装器，保留范围信息以便修复。" \
      "${scope} authoritative state changed after the install callback began but is invalid; refusing installer replay and retaining scoped recovery metadata.")"
    return 1
  fi
  printf 'retry'
}

nb_lifecycle_protocol_retry_authorized() {
  local scope="$1"
  [ -z "${NOBRAND_RECOVERY_EXPECTED_SCOPE:-}" ] \
    && [ "${NOBRAND_PROTOCOL_EXPLICIT_RETRY_SCOPE:-}" = "$scope" ]
}

# Rebuild only the runtime effects that are deterministically described by the
# recorded protocol state.  Recovery must never invoke an install callback: it
# has neither the original request nor authority to generate replacement
# credentials.  Structural validation intentionally precedes the admin lock
# and every mutating service/firewall action.
nb_lifecycle_reconcile_protocol_scope() {
  local scope="$1" enabled port failed=0
  nb_lifecycle_protocol_scope_state_valid "$scope" || return 1

  case "$scope" in
    forward)
      forward_reconcile_authoritative_state
      return $?
      ;;
    ssh-tunnel)
      # A non-empty, fully committed SSH state can be checked without replaying
      # account/key creation or rewriting administrator access. Earlier or
      # pending states fail the structural gate above and remain fail-closed.
      ssh_tunnel_watchdog_directory_empty_valid || return 1
      ssh_tunnel_group_identity_valid || return 1
      while IFS= read -r user_json; do
        [ -n "$user_json" ] || return 1
        ssh_tunnel_user_identity_valid "$user_json" \
          && ssh_tunnel_user_key_material_valid "$user_json" || return 1
      done < <(jq -c '.users[]' "$NOBRAND_SSH_STATE_FILE")
      return 0
      ;;
    vless-sudoku) ;;
    *) return 1 ;;
  esac

  # Complete the read-only preflight for the whole scope before repairing even
  # one unit.  Enumerators are intentionally forgiving for status displays, so
  # recovery additionally requires every derived field/config it will consume.
  case "$scope" in
    vless-sudoku)
      enabled="$(vless_sudoku_state_field enabled 2>/dev/null)" || return 1
      case "$enabled" in true|false) ;; *) return 1 ;; esac
      port="$(vless_sudoku_state_field listen_port 2>/dev/null)" || return 1
      [[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -ge 1 ] && [ "$port" -le 65535 ] || return 1
      vless_sudoku_server_config_matches \
        && vless_sudoku_client_config_matches \
        && nobrand_xray_test_config "$NOBRAND_VLESS_CONFIG_FILE" || return 1
      ;;
  esac

  admin_lock_acquire || return 1
  case "$scope" in
    vless-sudoku)
      enabled="$(vless_sudoku_state_field enabled 2>/dev/null)" || failed=1
      case "$enabled" in true|false) ;; *) failed=1 ;; esac
      if [ "$failed" -eq 0 ]; then
        nobrand_write_vless_sudoku_service || failed=1
      fi
      if [ "$failed" -eq 0 ] && [ "$enabled" = true ]; then
        port="$(vless_sudoku_state_field listen_port)" || failed=1
        [ "$failed" -ne 0 ] \
          || nb_firewall_open_pairs "TCP|${port}" >/dev/null 2>&1 || failed=1
        [ "$failed" -ne 0 ] \
          || nobrand_vless_sudoku_service_action start >/dev/null 2>&1 || failed=1
        [ "$failed" -ne 0 ] || vless_sudoku_running || failed=1
      elif [ "$failed" -eq 0 ]; then
        nobrand_vless_sudoku_service_action stop >/dev/null 2>&1 || failed=1
      fi
      ;;
  esac
  admin_lock_release
  return "$failed"
}

nb_lifecycle_validate_protocol_scope() {
  local scope="$1"
  # Doctors alone are insufficient for multi-instance scopes because their
  # enumerators intentionally skip malformed entries. Validate every matching
  # authoritative state object before any recovery transaction can complete.
  nb_lifecycle_protocol_scope_state_valid "$scope" || return 1
  case "$scope" in
    vless-sudoku)
      vless_sudoku_state_exists && vless_sudoku_doctor
      ;;
    ssh-tunnel)
      ssh_tunnel_state_exists && ssh_tunnel_doctor
      ;;
    forward)
      forward_state_valid "$NOBRAND_FORWARD_STATE_FILE" \
        && jq -e '.rules | length > 0' "$NOBRAND_FORWARD_STATE_FILE" >/dev/null \
        && forward_doctor
      ;;
    *) return 1 ;;
  esac
}

nb_lifecycle_run_protocol_install() {
  local scope="$1" callback="$2" rc=0 prior_phase="" begin_phase=prepare
  local recovery_mode=retry callback_phase_active=0 fingerprint="" callback_phase=""
  local recovering=0 validate_only=0 callback_rc=0 restore_errexit=0 saved_err_trap=""
  local transaction_preexisting=0 mutation_started=0 recovery_validated=0
  shift 2
  if [ "${NOBRAND_MANAGER_SESSION_ACTIVE:-0}" -ne 1 ]; then
    "$callback" "$@"
    return $?
  fi
  require_root || return 1
  require_linux || return 1
  nb_lifecycle_lock_acquire || return 1
  if [ -n "${NOBRAND_RECOVERY_EXPECTED_SCOPE:-}" ]; then
    [ "$NOBRAND_RECOVERY_EXPECTED_SCOPE" = "$scope" ] \
      && nb_lifecycle_tx_valid \
      && [ "$(nb_lifecycle_field STATUS)" = in-progress ] \
      && [ "$(nb_lifecycle_field OPERATION)" = install ] \
      && [ "$(nb_lifecycle_scope)" = "$scope" ] || {
        nb_lifecycle_lock_release
        warn "$(t '原恢复事务已由其它进程改变；拒绝把旧选择作为新的协议安装执行。' \
          'The recovery transaction changed in another process; refusing to execute the stale choice as a new protocol install.')"
        return 1
      }
  fi
  if nb_lifecycle_tx_valid \
     && [ "$(nb_lifecycle_field STATUS)" = in-progress ] \
     && [ "$(nb_lifecycle_field OPERATION)" = install ] \
     && [ "$(nb_lifecycle_scope)" = "$scope" ]; then
    recovering=1
    transaction_preexisting=1
    prior_phase="$(nb_lifecycle_field LAST_COMPLETED_PHASE)"
    begin_phase="$prior_phase"
    mutation_started="$(nb_lifecycle_mutation_started)" || {
      nb_lifecycle_lock_release
      return 1
    }
    if [ "$mutation_started" = 0 ]; then
      nb_lifecycle_clear || {
        nb_lifecycle_lock_release
        return 1
      }
      if nb_lifecycle_protocol_retry_authorized "$scope"; then
        # This invocation carries a new, explicit same-scope request. Discard
        # the stale unmutated record and execute the current request as a fresh
        # transaction now, rather than requiring a second invocation.
        recovering=0
        transaction_preexisting=0
        prior_phase=""
        begin_phase=prepare
        mutation_started=0
      else
        # No component mutation happened, so there is no request to reconstruct.
        # A no-arg recovery must never turn lost interactive choices into defaults
        # or validate an unrelated pre-existing instance as the requested install.
        nb_lifecycle_lock_release
        t "${scope} 操作在写入协议变更前中止；已清除临时恢复信息，请从管理菜单重新开始。" \
          "${scope} stopped before any protocol change; temporary recovery metadata was cleared. Start it again from the manager menu."
        return 0
      fi
    else
      recovery_mode="$(nb_lifecycle_protocol_recovery_mode "$scope" "$prior_phase")" || {
        nb_lifecycle_lock_release
        return 1
      }
      if [ "$recovery_mode" = retry ] && [ "$scope" = forward ]; then
        nb_lifecycle_lock_release
        warn "$(t \
          'Forward 权威状态未变化，但原始请求与系统前态未持久记录；自动清理或重放并不安全。恢复信息已原样保留，请人工检查后处理。' \
          'Forward authoritative state is unchanged, but the original request and system pre-state were not durably recorded; automatic cleanup or replay is unsafe. Recovery metadata was preserved exactly; inspect the host and resolve it manually.')"
        return 1
      fi
      if [ "$recovery_mode" = retry ] \
         && ! nb_lifecycle_protocol_retry_authorized "$scope"; then
        nb_lifecycle_lock_release
        warn "$(t \
          "${scope} 的原安装参数未写入恢复记录。为避免使用默认值静默重放，请显式重新执行同一组件的安装命令。" \
          "The original ${scope} install request was not stored. To avoid silently replaying defaults, explicitly run the same component install command again.")"
        return 1
      fi
      case "$recovery_mode" in validate|validate-changed) validate_only=1 ;; esac
      [[ "$prior_phase" != callback-* ]] || callback_phase_active=1
    fi
  fi
  if [ "$transaction_preexisting" -eq 0 ]; then
    nb_lifecycle_pre_mutation_snapshot || {
      nb_lifecycle_lock_release
      return 1
    }
  fi
  if [ "$transaction_preexisting" -eq 1 ] && [ "$validate_only" -eq 1 ]; then
    # Keep the durable callback/validation recovery point byte-for-byte until
    # state-driven reconciliation and its doctor both succeed.
    NOBRAND_LIFECYCLE_OPERATION=install
    NOBRAND_LIFECYCLE_SCOPE="$scope"
    NOBRAND_LIFECYCLE_ACTIVE=1
    NOBRAND_LIFECYCLE_MUTATION_STARTED="$mutation_started"
  else
    nb_lifecycle_begin install "$begin_phase" 0 0 0 0 0 0 "$scope" || {
      [ "$transaction_preexisting" -ne 0 ] || nb_lifecycle_pre_mutation_disarm
      nb_lifecycle_lock_release
      return 1
    }
  fi
  if [ "$rc" -eq 0 ] && ! nobrand_manager_installation_valid; then
    # Protocol recovery cannot repair the manager as a side effect. Besides
    # being outside this scope, such a write would destroy the pre-mutation
    # guarantee when the original protocol request is no longer available.
    warn "$(t \
      'NoBrand 管理器当前无效；请先修复管理器，再重试该协议操作。' \
      'The NoBrand manager is invalid; repair the manager before retrying this protocol action.')"
    rc=1
  fi
  if [ "$rc" -eq 0 ] && [ "$validate_only" -eq 1 ]; then
    nb_lifecycle_reconcile_protocol_scope "$scope" || {
      warn "$(t "${scope} 的 state 驱动恢复失败；保留原范围与恢复阶段以便重试。" \
        "State-driven ${scope} reconciliation failed; the original scope and recovery phase were retained for retry.")"
      rc=1
    }
  fi
  if [ "$rc" -eq 0 ] && [ "$validate_only" -eq 1 ]; then
    nb_lifecycle_validate_protocol_scope "$scope" || {
      warn "$(t "${scope} 恢复后的状态或运行时验证失败；保留范围信息以便重试。" \
        "${scope} state or runtime validation failed after recovery; scoped metadata was retained for retry.")"
      rc=1
    }
    [ "$rc" -ne 0 ] || recovery_validated=1
  fi
  if [ "$rc" -eq 0 ] && [ "$validate_only" -eq 0 ] \
     && [ "$callback_phase_active" -eq 0 ]; then
    nb_lifecycle_checkpoint install state-layout || rc=$?
  fi
  if [ "$rc" -eq 0 ] && [ "$validate_only" -eq 0 ] \
     && [ "$callback_phase_active" -eq 0 ]; then
    fingerprint="$(nb_lifecycle_protocol_scope_fingerprint "$scope")" || rc=$?
    if [ "$rc" -eq 0 ]; then
      callback_phase="callback-${fingerprint:0:55}"
      nb_lifecycle_checkpoint install "$callback_phase" || rc=$?
    fi
  fi
  if [ "$rc" -eq 0 ] && [ "$validate_only" -eq 0 ]; then
    # Calling a shell function on the left side of `||` disables errexit for
    # every command in that function. Several established installers rely on
    # the script's fail-fast mode, so run the callback in an isolated simple
    # command while temporarily suppressing only this wrapper's ERR trap.
    case "$-" in *e*) restore_errexit=1 ;; esac
    saved_err_trap="$(trap -p ERR || true)"
    trap - ERR
    set +e
    (
      set -Eeuo pipefail
      NOBRAND_LIFECYCLE_LOCK_FLOOR="${NOBRAND_LIFECYCLE_LOCK_HELD:-0}"
      NOBRAND_LIFECYCLE_PREMUTATION_ARMED="${NOBRAND_LIFECYCLE_PREMUTATION_ARMED:-0}"
      NOBRAND_LIFECYCLE_PREMUTATION_PRIOR_PRESENT="${NOBRAND_LIFECYCLE_PREMUTATION_PRIOR_PRESENT:-0}"
      NOBRAND_LIFECYCLE_PREMUTATION_PRIOR_RECORD="${NOBRAND_LIFECYCLE_PREMUTATION_PRIOR_RECORD:-}"
      NOBRAND_PROTOCOL_CALLBACK_ATTEMPT_MUTATION=0
      nb_lifecycle_signal_handlers_install
      trap 'callback_rc=$?; trap - ERR; exit "$callback_rc"' ERR
      "$callback" "$@"
      # Commit the lifecycle checkpoint in the callback process.  The parent
      # cannot observe a successful callback return before this write is
      # durable. A prior retry transaction may already carry MUTATION_STARTED,
      # so require proof that this callback attempt crossed its own boundary.
      if [ "$NOBRAND_PROTOCOL_CALLBACK_ATTEMPT_MUTATION" -eq 1 ]; then
        nb_lifecycle_checkpoint install ready-to-validate
      fi
    )
    callback_rc=$?
    [ "$restore_errexit" -eq 0 ] || set -e
    if [ -n "$saved_err_trap" ]; then
      eval "$saved_err_trap"
    else
      trap - ERR
    fi
    [ "$callback_rc" -eq 0 ] || rc="$callback_rc"
  fi
  if nb_lifecycle_tx_valid \
     && [ "$(nb_lifecycle_field STATUS)" = in-progress ] \
     && [ "$(nb_lifecycle_field OPERATION)" = install ] \
     && [ "$(nb_lifecycle_scope)" = "$scope" ] \
     && [ "$(nb_lifecycle_mutation_started)" = 1 ]; then
    nb_lifecycle_pre_mutation_disarm
  fi
  if [ "$rc" -ne 0 ] && nb_lifecycle_tx_valid \
     && [ "$(nb_lifecycle_field OPERATION)" = install ] \
     && [ "$(nb_lifecycle_scope)" = "$scope" ] \
     && [ "$(nb_lifecycle_mutation_started)" = 0 ]; then
    nb_lifecycle_restore_pre_mutation || rc=1
  fi
  if [ "$rc" -eq 0 ]; then
    if [ "$validate_only" -eq 1 ]; then
      nb_lifecycle_checkpoint install ready-to-validate || rc=$?
    elif nb_lifecycle_tx_valid && [ "$(nb_lifecycle_mutation_started)" = 0 ]; then
      # A duplicate/existing-instance callback can intentionally be a no-op.
      # It must not complete a fresh transaction against unrelated state.
      nb_lifecycle_restore_pre_mutation || rc=1
    elif ! nb_lifecycle_tx_valid \
         || [ "$(nb_lifecycle_field LAST_COMPLETED_PHASE)" != ready-to-validate ]; then
      # In a recovering callback transaction MUTATION_STARTED may belong to an
      # earlier attempt. Without this attempt's child checkpoint, keep the
      # callback fingerprint and refuse to validate or complete unrelated state.
      warn "$(t \
        "${scope} 本次安装重试未提交新的协议变更；已保留原回调恢复点，未确认现有实例。" \
        "This ${scope} install retry committed no new protocol change; the original callback recovery point was retained and existing instances were not acknowledged.")"
      rc=1
    fi
  fi
  if [ "$rc" -eq 0 ] && [ "${NOBRAND_LIFECYCLE_ACTIVE:-0}" -eq 1 ]; then
    nobrand_manager_installation_valid || rc=$?
  fi
  if [ "$rc" -eq 0 ] && [ "${NOBRAND_LIFECYCLE_ACTIVE:-0}" -eq 1 ] \
     && [ "$recovering" -eq 1 ] && [ "$recovery_validated" -eq 0 ]; then
    nb_lifecycle_validate_protocol_scope "$scope" || {
      warn "$(t "${scope} 恢复后的状态或运行时验证失败；保留范围信息以便重试。" \
        "${scope} state or runtime validation failed after recovery; scoped metadata was retained for retry.")"
      rc=1
    }
  fi
  if [ "$rc" -eq 0 ] && [ "${NOBRAND_LIFECYCLE_ACTIVE:-0}" -eq 1 ]; then
    nb_lifecycle_complete install || rc=$?
  fi
  nb_lifecycle_lock_release
  return "$rc"
}

nb_lifecycle_run_ingress_action() {
  local rc=0 lifecycle_format="" mutation_started=0
  if [ "${NOBRAND_MANAGER_SESSION_ACTIVE:-0}" -ne 1 ]; then
    nobrand_run_ingress_action_unscoped
    return $?
  fi
  nb_lifecycle_lock_acquire || return 1
  if nb_lifecycle_tx_valid \
     && [ "$(nb_lifecycle_field STATUS)" = in-progress ]; then
    if [ "$(nb_lifecycle_field OPERATION)" != configure ] \
       || [ "$(nb_lifecycle_scope)" != ingress ]; then
      nb_lifecycle_lock_release
      return 1
    fi
    lifecycle_format="$(nb_lifecycle_field FORMAT)"
    mutation_started="$(nb_lifecycle_mutation_started)" || {
      nb_lifecycle_lock_release
      return 1
    }
    if [ "$lifecycle_format" = nobrand-lifecycle-v2 ] \
       && [ "$mutation_started" = 0 ] \
       && nb_lifecycle_protocol_retry_authorized ingress; then
      nb_lifecycle_clear || {
        nb_lifecycle_lock_release
        return 1
      }
    else
      nb_lifecycle_lock_release
      warn "$(t \
        '现有 Ingress 配置事务不能由当前请求安全重放；已原样保留恢复信息。' \
        'The existing Ingress configure transaction cannot be safely replayed by this request; recovery metadata was preserved exactly.')"
      return 1
    fi
  fi
  nb_lifecycle_pre_mutation_snapshot || {
    nb_lifecycle_lock_release
    return 1
  }
  nb_lifecycle_begin configure prepare 0 0 0 0 0 0 ingress || {
    nb_lifecycle_pre_mutation_disarm
    nb_lifecycle_lock_release
    return 1
  }
  nobrand_run_ingress_action_unscoped || rc=$?
  if [ "$rc" -ne 0 ] \
     && nb_lifecycle_tx_valid \
     && [ "$(nb_lifecycle_field OPERATION)" = configure ] \
     && [ "$(nb_lifecycle_scope)" = ingress ] \
     && [ "$(nb_lifecycle_mutation_started)" = 0 ]; then
    nb_lifecycle_restore_pre_mutation || rc=1
  fi
  if [ "$rc" -eq 0 ] \
     && nb_lifecycle_tx_valid \
     && [ "$(nb_lifecycle_field OPERATION)" = configure ] \
     && [ "$(nb_lifecycle_scope)" = ingress ] \
     && [ "$(nb_lifecycle_mutation_started)" = 0 ]; then
    # A mutating Ingress action that made no durable change is a successful
    # no-op. Do not replace a prior completed lifecycle record with it.
    nb_lifecycle_restore_pre_mutation || rc=1
    nb_lifecycle_lock_release
    return "$rc"
  fi
  if [ "$rc" -eq 0 ]; then
    nb_lifecycle_checkpoint configure state-committed || rc=$?
  fi
  if [ "$rc" -eq 0 ] && [ -e "$NOBRAND_INGRESS_STATE_FILE" ]; then
    nb_ingress_state_valid || rc=$?
  fi
  if [ "$rc" -eq 0 ]; then
    nb_lifecycle_checkpoint configure ready-to-validate || rc=$?
  fi
  if [ "$rc" -eq 0 ]; then
    nb_lifecycle_complete configure || rc=$?
  fi
  nb_lifecycle_lock_release
  return "$rc"
}

do_bbr_config() {
  require_root || return 1
  require_linux || return 1
  report_bbr_fq_status
  offer_bbr_fq
}

menu_pause() {
  local _ignore=""
  msg ""
  read_tty _ignore "$(t '按回车返回主菜单...' 'Press Enter to return to the menu...')" || true
}

menu_run_action() {
  local runtime_rc=0
  nb_splicore_route_main || runtime_rc=$?
  [ "${NOBRAND_SPLICORE_HANDLED:-0}" -ne 1 ] || return "$runtime_rc"
  case "$ACTION" in
    user-manage) do_user_manage ;;
    perf) do_perf ;;
    bbr-config) do_bbr_config ;;
    help) nobrand_usage ;;
    *) warn 'Unsupported action'; return 1 ;;
  esac
}

menu_loop() {
  MENU_MODE=1
  trap - ERR
  nb_splicore_legacy_preflight || return 1
  while true; do
    ACTION=""
    # 安全捕获：set -e 下裸调用 show_menu 返回非0(无效输入)会直接退脚本
    local sm_rc=0
    show_menu || sm_rc=$?
    if [ "$sm_rc" -eq 2 ]; then
      break
    fi
    if [ "$sm_rc" -ne 0 ]; then
      continue
    fi
    # 不能把业务函数放在 if/|| 条件上下文中：Bash 会在整个函数调用链内
    # 抑制 errexit。用独立子 shell 作为简单命令执行，父菜单再读取退出码。
    local rc=0 action_lock=0
    if [ "${NOBRAND_MANAGER_SESSION_ACTIVE:-0}" -eq 1 ] && [ "$ACTION" != user-manage ]; then
      nb_lifecycle_lock_acquire || return 1
      action_lock=1
      if ! nobrand_menu_state_current; then
        nb_lifecycle_lock_release
        warn "$(t '菜单显示后权威状态已变化；请重新进入管理菜单选择操作。' \
          'Authoritative state changed after the menu was shown; reopen the manager and select the action again.')"
        return 1
      fi
    fi
    set +e
    (
      set -Eeuo pipefail
      NOBRAND_LIFECYCLE_LOCK_FLOOR="${NOBRAND_LIFECYCLE_LOCK_HELD:-0}"
      NOBRAND_LIFECYCLE_ACTIVE=0
      NOBRAND_LIFECYCLE_OPERATION=""
      NOBRAND_LIFECYCLE_SCOPE=""
      NOBRAND_LIFECYCLE_MUTATION_STARTED=0
      nb_lifecycle_signal_handlers_install
      trap 'rc=$?; if [ "$rc" -eq 2 ] || [ "$rc" -eq 3 ]; then exit "$rc"; fi; on_error' ERR
      menu_run_action
    )
    rc=$?
    set -e
    [ "$action_lock" -eq 0 ] || nb_lifecycle_lock_release
    if [ "$rc" -eq 2 ]; then
      break
    fi
    if [ "$rc" -eq 3 ]; then
      continue
    fi
    if [ "$rc" -ne 0 ]; then
      warn "$(t '操作未完成，请重试或运行 nobrand doctor 排查' 'Action failed; retry or run nobrand doctor')"
    fi
    menu_pause
  done
}

show_performance_menu() {
  msg '  1) 网络诊断（只读）'
  msg '  2) BBR / FQ'
  msg '  0) 返回'
  local choice=""
  read_tty choice '请选择 [0-2]: ' || return 2
  case "$choice" in 1) ACTION=perf ;; 2) ACTION=bbr-config ;; 0) return 2 ;; *) return 1 ;; esac
}

show_service_menu() {
  msg ""
  t '【服务管理】' '[Service management]'
  msg '  1) 状态'
  msg '  2) 启动'
  msg '  3) 停止'
  msg '  4) 重启'
  msg '  0) 返回'
  local choice=""
  read_tty choice "$(t '请选择 [0-4]: ' 'Choose [0-4]: ')" || return 2
  case "$(printf '%s' "$choice" | tr -d '[:space:]')" in
    1) ACTION=status ;;
    2) ACTION=start ;;
    3) ACTION=stop ;;
    4) ACTION=restart ;;
    0) return 2 ;;
    *) warn "$(t '无效选择' 'Invalid choice')"; return 1 ;;
  esac
}

show_backup_menu() {
  t '完整新架构备份：nobrand backup create；恢复：nobrand backup restore --file PATH。' \
    'Back up the native architecture with nobrand backup create; restore with nobrand backup restore --file PATH.'
  return 2
}

show_menu() {
  local installed="no" users="-" selected_rc=0 profile_text="native" version_text="v0.3.0-rc.4"
  if nb_splicore_installed; then
    installed=yes
    users="$(nb_splicore_call protocol --protocol mieru --operation status | jq '[.nodes[]?] | length')"
  fi
  msg ''
  t '========== NoBrand-OneClick / Mieru ==========' \
    '========== NoBrand-OneClick / Mieru =========='
  t "作者: ${SCRIPT_AUTHOR} / https://github.com/${SCRIPT_REPO}" \
    "Author: ${SCRIPT_AUTHOR} / https://github.com/${SCRIPT_REPO}"
  t "状态: $([ "$installed" = yes ] && printf '已安装' || printf '未安装')" \
    "Status: $([ "$installed" = yes ] && printf 'installed' || printf 'not installed')"
  t "用户: ${users}" "Users: ${users}"
  t "配置预设 / Profile: ${profile_text}" "Profile: ${profile_text}"
  t "运行时版本: ${version_text}" "Runtime Version: ${version_text}"
  msg ''
  if [ "$installed" = yes ]; then
    msg '  1) 添加节点'
  else
    msg '  1) 新装 / 安装'
  fi
  msg '  2) 查看节点'
  msg '  3) 用户管理'
  msg '  4) 性能与网络'
  if [ "$installed" = yes ]; then
    msg '  5) 调整节点配置（使用显式命令参数）'
  else
    msg '  5) 调整节点配置（使用显式命令参数）'
  fi
  msg '  6) 服务管理'
  msg '  7) 备份 / 恢复'
  msg '  8) 升级'
  msg '  9) Doctor / 诊断'
  msg ' 10) 卸载'
  msg '  0) 退出'
  msg ""
  t '快捷命令: nobrand mieru（nb mieru 同义）' \
    'Quick command: nobrand mieru (or nb mieru)'
  msg ""
  local choice=""
  read_tty choice "$(t '请选择 [0-10]: ' 'Choose [0-10]: ')" || return 2
  choice="$(printf '%s' "$choice" | tr -d '[:space:]')"
  if [ -z "$choice" ]; then
    warn "$(t '请输入 0-10' 'Enter 0-10')"
    return 1
  fi
  case "$choice" in
    1) ACTION=install ;;
    2) ACTION="client-config" ;;
    3) ACTION="user-manage" ;;
    4)
      show_performance_menu || selected_rc=$?
      [ "$selected_rc" -eq 0 ] || return 1
      ;;
    5) nobrand_usage; return 1 ;;
    6)
      show_service_menu || selected_rc=$?
      [ "$selected_rc" -eq 0 ] || return 1
      ;;
    7)
      show_backup_menu || selected_rc=$?
      [ "$selected_rc" -eq 0 ] || return 1
      ;;
    8) ACTION=upgrade ;;
    9) ACTION=doctor ;;
    10) ACTION=uninstall ;;
    0) return 2 ;;
    *)
      warn "$(t '无效选择，请输入 0-10' 'Invalid choice, enter 0-10')"
      return 1
      ;;
  esac
  return 0
}

# ---------- NoBrand unified interactive presentation ----------

nobrand_menu_state_current() {
  if [ -n "${NOBRAND_MENU_EXPECTED_STATE:-}" ]; then
    nb_validate_authoritative_state_boundary || return 1
    [ "$NOBRAND_INSTALL_STATE" = "$NOBRAND_MENU_EXPECTED_STATE" ] || return 1
  fi
  ! nobrand_ssh_confirmation_pending
}

nobrand_menu_selection_clear() {
  NOBRAND_MENU_SELECTION_SCOPE=""
  NOBRAND_MENU_SELECTION_ID=""
  NOBRAND_MENU_SELECTION_NAME=""
  NOBRAND_MENU_SELECTION_HASH=""
}

nobrand_menu_selection_current() {
  local scope="${NOBRAND_MENU_SELECTION_SCOPE:-}" selected_id="${NOBRAND_MENU_SELECTION_ID:-}"
  local selected_name="${NOBRAND_MENU_SELECTION_NAME:-}" expected_hash="${NOBRAND_MENU_SELECTION_HASH:-}"
  local path="${NOBRAND_STATE_DIR}/splicore/current/desired.json" current_hash
  [ -n "$scope" ] || return 0
  [ "$scope" = splicore ] && [ -n "$selected_id" ] && [ -n "$selected_name" ] && [ -n "$expected_hash" ] || return 1
  [ -f "$path" ] && [ ! -L "$path" ] || return 1
  current_hash="$(sha256sum <"$path" | cut -d' ' -f1)" || return 1
  [ "$current_hash" = "$expected_hash" ] || return 1
  jq -e --arg id "$selected_id" --arg name "$selected_name" \
    '.nodes[] | select(.id==$id and (.id==$name or .client.name==$name))' "$path" >/dev/null
}

nobrand_menu_selection_record() {
  local scope="$1" id="$2" name="$3" path="$4"
  nobrand_menu_selection_clear
  [ -f "$path" ] && [ ! -L "$path" ] || return 1
  NOBRAND_MENU_SELECTION_HASH="$(sha256sum <"$path" | cut -d' ' -f1)" || return 1
  NOBRAND_MENU_SELECTION_SCOPE="$scope"
  NOBRAND_MENU_SELECTION_ID="$id"
  NOBRAND_MENU_SELECTION_NAME="$name"
  nobrand_menu_selection_current || { nobrand_menu_selection_clear; return 1; }
}

nobrand_menu_run() {
  local rc=0 restore_errexit=0 callback="${1:-}"
  local menu_lock=0
  local global_uninstall_callback=0 authenticated_exit_rc=125
  local auth_path="" auth_read_fd="" auth_write_fd="" auth_proof=""
  local auth_expected='nobrand-global-uninstall-confirmed-v1'
  if [ "$#" -eq 1 ] && [ "$callback" = nobrand_uninstall ]; then
    global_uninstall_callback=1
    # Separate read/write descriptors keep an out-of-band proof visible to the
    # parent. Unlink immediately so crashes cannot leave an authentication file.
    auth_path="$(mktemp_file)" || {
      warn "$(t '无法创建全局卸载完成验证通道；未执行卸载' \
        'Could not create the global-uninstall completion channel; uninstall was not run')"
      return 0
    }
    if ! exec {auth_read_fd}<"$auth_path"; then
      rm -f -- "$auth_path"
      warn "$(t '无法打开全局卸载完成验证通道；未执行卸载' \
        'Could not open the global-uninstall completion channel; uninstall was not run')"
      return 0
    fi
    if ! exec {auth_write_fd}>"$auth_path"; then
      exec {auth_read_fd}<&-
      rm -f -- "$auth_path"
      warn "$(t '无法打开全局卸载完成验证通道；未执行卸载' \
        'Could not open the global-uninstall completion channel; uninstall was not run')"
      return 0
    fi
    if ! rm -f -- "$auth_path"; then
      exec {auth_write_fd}>&-
      exec {auth_read_fd}<&-
      warn "$(t '无法保护全局卸载完成验证通道；未执行卸载' \
        'Could not secure the global-uninstall completion channel; uninstall was not run')"
      return 0
    fi
    auth_path=""
  fi
  # The menu itself is unlocked. Each action rechecks the authoritative state
  # and any named instance after taking the mutation guard. Global uninstall
  # takes that guard itself after its confirmation prompt.
  if [ "${NOBRAND_MANAGER_SESSION_ACTIVE:-0}" -eq 1 ] \
     && [ "$global_uninstall_callback" -eq 0 ]; then
    nb_lifecycle_lock_acquire || return 1
    menu_lock=1
    if ! nobrand_menu_state_current || ! nobrand_menu_selection_current; then
      nb_lifecycle_lock_release
      nobrand_menu_selection_clear
      warn "$(t '菜单显示后权威状态已变化；请重新进入管理菜单选择操作。' \
        'Authoritative state changed after the menu was shown; reopen the manager and select the action again.')"
      return 1
    fi
  fi
  nobrand_menu_selection_clear
  case "$-" in *e*) restore_errexit=1 ;; esac
  set +e
  (
    set -Eeuo pipefail
    NOBRAND_MENU_GLOBAL_UNINSTALL_CONFIRMED=0
    NOBRAND_LIFECYCLE_LOCK_FLOOR="${NOBRAND_LIFECYCLE_LOCK_HELD:-0}"
    NOBRAND_LIFECYCLE_ACTIVE=0
    NOBRAND_LIFECYCLE_OPERATION=""
    NOBRAND_LIFECYCLE_SCOPE=""
    NOBRAND_LIFECYCLE_MUTATION_STARTED=0
    nb_lifecycle_signal_handlers_install
    # Translate the terminal marker into a private subprocess status and write
    # proof through the unlinked channel. The parent requires both signals.
    trap 'rc=$?; if [ "$rc" -eq "${NOBRAND_MENU_EXIT_SUCCESS:-4}" ] \
      && [ "$global_uninstall_callback" -eq 1 ] \
      && [ "${NOBRAND_MENU_GLOBAL_UNINSTALL_CONFIRMED:-0}" = 1 ]; then \
        if ! printf "%s\n" "$auth_expected" >&"$auth_write_fd"; then \
          on_error; exit 1; \
        fi; \
        exit "$authenticated_exit_rc"; \
      fi; on_error; exit 1' ERR
    "$@"
  )
  rc=$?
  if [ "$global_uninstall_callback" -eq 1 ]; then
    exec {auth_write_fd}>&- 2>/dev/null || true
    IFS= read -r auth_proof <&"$auth_read_fd" || auth_proof=""
    exec {auth_read_fd}<&- 2>/dev/null || true
  fi
  [ "$restore_errexit" -eq 0 ] || set -e
  if [ "$rc" -eq "$authenticated_exit_rc" ] \
     && [ "$global_uninstall_callback" -eq 1 ] \
     && [ "$auth_proof" = "$auth_expected" ]; then
    return "$NOBRAND_MENU_EXIT_SUCCESS"
  fi
  if [ "$rc" -ne 0 ] \
     && nb_lifecycle_tx_valid \
     && [ "$(nb_lifecycle_field STATUS)" = in-progress ] \
     && ! nobrand_ssh_confirmation_pending; then
    warn "$(t '操作在写入变更后中断；已保留组件范围恢复信息，当前管理器将退出。' \
      'The action stopped after mutation; scoped recovery metadata was preserved and this manager will exit.')"
    [ "$menu_lock" -eq 0 ] || nb_lifecycle_lock_release
    nb_lifecycle_lock_release_all >/dev/null 2>&1 || true
    exit 1
  fi
  [ "$menu_lock" -eq 0 ] || nb_lifecycle_lock_release
  if [ "$rc" -ne 0 ]; then
    warn "$(t '操作未完成；请重试或运行 nobrand doctor' \
      'Action did not complete; retry or run nobrand doctor')"
  fi
  return 0
}

snell_menu_select_instance() {
  nb_splicore_menu_select snell
}

snell_menu_install_version() {
  local version="$1"
  SNELL_VERSION="$version" SNELL_NAME="" SNELL_PSK=""
  SNELL_QUIC_PROXY=""
  PORT="" PORT_CLI=0 ADVERTISE_HOST="" ADVERTISE_PORT="" ADVERTISE_CLI=0 ADVERTISE_AUTO_REQUESTED=0
  YES=0 SNELL_ACTION=install
  nobrand_menu_run nobrand_run_snell_action
}

snell_menu_set_quic() {
  t '当前版本不支持 Snell QUIC Proxy Mode；保持关闭。TCP 与普通 UDP 转发可用。' \
    'Snell QUIC Proxy Mode is unsupported and remains off. TCP and ordinary UDP relay are available.'
}

snell_menu_service() {
  local choice=""
  snell_menu_select_instance || return 0
  msg '  1) 状态'
  msg '  2) 启动'
  msg '  3) 停止'
  msg '  4) 重启'
  read_tty choice "$(t '请选择 [1-4]: ' 'Choose [1-4]: ')" || choice=""
  case "$choice" in
    1) SNELL_ACTION=status ;;
    2) SNELL_ACTION=start ;;
    3) SNELL_ACTION=stop ;;
    4) SNELL_ACTION=restart ;;
    *) warn '无效选择'; return 0 ;;
  esac
  nobrand_menu_run nobrand_run_snell_action
}

snell_menu_loop() {
  local choice="" confirm=""
  trap - ERR
  while true; do
    msg ''
    msg '========== Snell =========='
    msg '  1) 安装 Snell v5 [推荐]'
    msg '  2) 安装 Snell v4 [兼容]'
    msg '  3) 查看 Snell 节点'
    msg '  4) QUIC 支持范围'
    msg '  5) 修改展示端点 / Display Endpoint'
    msg '  6) 服务管理'
    msg '  7) 检查运行时更新'
    msg '  8) Doctor / 诊断'
    msg '  9) 删除节点'
    msg '  0) 返回'
    read_tty choice "$(t '请选择 [0-9]: ' 'Choose [0-9]: ')" || return 0
    case "$choice" in
      1) snell_menu_install_version 5 ;;
      2) snell_menu_install_version 4 ;;
      3) SNELL_NAME=""; SNELL_ACTION=show; nobrand_menu_run nobrand_run_snell_action ;;
      4) snell_menu_set_quic ;;
      5)
        snell_menu_select_instance || continue
        ADVERTISE_CLI=0 ADVERTISE_AUTO_REQUESTED=0 YES=0 SNELL_ACTION="set-endpoint"
        nobrand_menu_run nobrand_run_snell_action
        ;;
      6) snell_menu_service ;;
      7)
        msg '升级版本: 1) v5  2) v4'
        read_tty confirm '请选择 [1-2]: ' || confirm=""
        case "$confirm" in 1) SNELL_VERSION=5 ;; 2) SNELL_VERSION=4 ;; *) warn '无效选择'; continue ;; esac
        SNELL_NAME="" SNELL_ACTION=upgrade
        nobrand_menu_run nobrand_run_snell_action
        ;;
      8) SNELL_ACTION=doctor; nobrand_menu_run nobrand_run_snell_action ;;
      9)
        snell_menu_select_instance || continue
        read_tty confirm "确认删除 ${SNELL_NAME}？输入 yes: " || confirm=""
        [ "$confirm" = yes ] || { warn '已取消'; continue; }
        SNELL_ACTION=remove
        nobrand_menu_run nobrand_run_snell_action
        ;;
      0) return 0 ;;
      *) warn '无效选择' ;;
    esac
    menu_pause
  done
}

hysteria2_menu_loop() {
  local choice="" confirm=""
  trap - ERR
  while true; do
    msg ''
    msg '========== Hysteria2 + Salamander =========='
    msg '  1) 安装 / 重新部署'
    msg '  2) 查看节点'
    msg '  3) 修改展示端点 / Display Endpoint'
    msg '  4) 状态'
    msg '  5) 启动'
    msg '  6) 停止'
    msg '  7) 重启'
    msg '  8) 验证 / 升级固定运行时'
    msg '  9) Doctor / 诊断'
    msg ' 10) 删除 Hysteria2'
    msg '  0) 返回'
    read_tty choice "$(t '请选择 [0-10]: ' 'Choose [0-10]: ')" || return 0
    case "$choice" in
      1)
        PORT="" PORT_CLI=0 HY2_SNI="" ADVERTISE_HOST="" ADVERTISE_PORT=""
        ADVERTISE_CLI=0 ADVERTISE_AUTO_REQUESTED=0 YES=0 HY2_ACTION=install
        nobrand_menu_run nobrand_run_hy2_action
        ;;
      2) HY2_ACTION=show; nobrand_menu_run nobrand_run_hy2_action ;;
      3)
        ADVERTISE_CLI=0 ADVERTISE_AUTO_REQUESTED=0 YES=0 HY2_ACTION=set-endpoint
        nobrand_menu_run nobrand_run_hy2_action
        ;;
      4) HY2_ACTION=status; nobrand_menu_run nobrand_run_hy2_action ;;
      5) HY2_ACTION=start; nobrand_menu_run nobrand_run_hy2_action ;;
      6) HY2_ACTION=stop; nobrand_menu_run nobrand_run_hy2_action ;;
      7) HY2_ACTION=restart; nobrand_menu_run nobrand_run_hy2_action ;;
      8) HY2_ACTION=upgrade; nobrand_menu_run nobrand_run_hy2_action ;;
      9) HY2_ACTION=doctor; nobrand_menu_run nobrand_run_hy2_action ;;
      10)
        read_tty confirm '确认只删除 NoBrand Hysteria2？输入 yes: ' || confirm=""
        [ "$confirm" = yes ] || { warn '已取消'; continue; }
        HY2_ACTION=remove
        nobrand_menu_run nobrand_run_hy2_action
        ;;
      0) return 0 ;;
      *) warn '无效选择' ;;
    esac
    menu_pause
  done
}

vless_sudoku_menu_loop() {
  local choice="" confirm=""
  trap - ERR
  while true; do
    msg ''
    msg '========== VLESS + FinalMask + Sudoku（TCP） =========='
    msg 'VLESS Encryption：未使用（NOT USED）'
    msg '  1) 安装 / 重新配置'
    msg '  2) 查看节点'
    msg '  3) 修改客户端展示入口'
    msg '  4) 状态'
    msg '  5) 启动'
    msg '  6) 停止'
    msg '  7) 重启'
    msg '  8) Doctor / 诊断'
    msg '  9) 配置冒烟测试 / Smoke'
    msg ' 10) 验证 / 升级固定运行时'
    msg ' 11) 删除'
    msg '  0) 返回'
    read_tty choice "$(t '请选择 [0-11]: ' 'Choose [0-11]: ')" || return 0
    case "$choice" in
      1)
        PORT="" PORT_CLI=0 VLESS_SUDOKU_UUID="" VLESS_SUDOKU_PASSWORD=""
        ADVERTISE_HOST="" ADVERTISE_PORT="" ADVERTISE_CLI=0 ADVERTISE_AUTO_REQUESTED=0
        YES=0 VLESS_SUDOKU_ACTION=install
        nobrand_menu_run nobrand_run_vless_sudoku_action
        ;;
      2) VLESS_SUDOKU_ACTION=show; nobrand_menu_run nobrand_run_vless_sudoku_action ;;
      3)
        ADVERTISE_HOST="" ADVERTISE_PORT="" ADVERTISE_CLI=0 ADVERTISE_AUTO_REQUESTED=0
        YES=0 VLESS_SUDOKU_ACTION="set-endpoint"
        nobrand_menu_run nobrand_run_vless_sudoku_action
        ;;
      4) VLESS_SUDOKU_ACTION=status; nobrand_menu_run nobrand_run_vless_sudoku_action ;;
      5) VLESS_SUDOKU_ACTION=start; nobrand_menu_run nobrand_run_vless_sudoku_action ;;
      6) VLESS_SUDOKU_ACTION=stop; nobrand_menu_run nobrand_run_vless_sudoku_action ;;
      7) VLESS_SUDOKU_ACTION=restart; nobrand_menu_run nobrand_run_vless_sudoku_action ;;
      8) VLESS_SUDOKU_ACTION=doctor; nobrand_menu_run nobrand_run_vless_sudoku_action ;;
      9) VLESS_SUDOKU_ACTION=smoke; nobrand_menu_run nobrand_run_vless_sudoku_action ;;
      10) VLESS_SUDOKU_ACTION=upgrade; nobrand_menu_run nobrand_run_vless_sudoku_action ;;
      11)
        read_tty confirm '确认只删除 NoBrand VLESS Sudoku？输入 yes: ' || confirm=""
        [ "$confirm" = yes ] || { warn '已取消'; continue; }
        VLESS_SUDOKU_ACTION=remove
        nobrand_menu_run nobrand_run_vless_sudoku_action
        ;;
      0) return 0 ;;
      *) warn '无效选择' ;;
    esac
    menu_pause
  done
}

reality_menu_select_instance() {
  nb_splicore_menu_select vless-reality
}

vless_reality_menu_loop() {
  local choice="" confirm="" selected="" profile_default=""
  trap - ERR
  while true; do
    msg ''
    msg '========== VLESS + TCP + REALITY + XTLS Vision =========='
    msg 'Public Ingress：推荐；Mapped / Dedicated：允许，但会提示警告'
    msg '  1) 安装新实例'
    msg '  2) 查看节点 / URI'
    msg '  3) 导出新 URI / 客户端配置'
    msg '  4) 修改展示端点 / Display Endpoint'
    msg '  5) 状态'
    msg '  6) 启动'
    msg '  7) 停止'
    msg '  8) 重启'
    msg '  9) Doctor / 诊断'
    msg ' 10) 验证 / 升级固定运行时'
    msg ' 11) 删除实例'
    msg '  0) 返回'
    read_tty choice "$(t '请选择 [0-11]: ' 'Choose [0-11]: ')" || return 0
    case "$choice" in
      1)
        PORT="" PORT_CLI=0 VLESS_REALITY_NAME="" VLESS_REALITY_TARGET=""
        VLESS_REALITY_TARGET_PORT="$NOBRAND_REALITY_DEFAULT_CAMOUFLAGE_PORT" \
        ADVERTISE_HOST="" ADVERTISE_PORT="" ADVERTISE_CLI=0 ADVERTISE_AUTO_REQUESTED=0
        INGRESS_PROFILE="" INGRESS_PROFILE_CLI=0 YES=0
        read_tty VLESS_REALITY_NAME '实例名称 [primary]: ' || VLESS_REALITY_NAME=""
        VLESS_REALITY_NAME="${VLESS_REALITY_NAME:-primary}"
        msg ''
        nb_ingress_list
        profile_default="$(nb_ingress_profile_name "$(nb_ingress_default_profile_id 2>/dev/null || true)")"
        read_tty selected "请选择 Ingress Profile [${profile_default}]: " || selected=""
        if [ -n "$selected" ]; then
          INGRESS_PROFILE="$selected"; INGRESS_PROFILE_CLI=1
        fi
        VLESS_REALITY_ACTION=install
        nobrand_menu_run nobrand_run_vless_reality_action
        ;;
      2) reality_menu_select_instance && { VLESS_REALITY_ACTION=show; nobrand_menu_run nobrand_run_vless_reality_action; } ;;
      3) reality_menu_select_instance && { VLESS_REALITY_ACTION="export"; nobrand_menu_run nobrand_run_vless_reality_action; } ;;
      4)
        if reality_menu_select_instance; then
          PORT="$NOBRAND_SPLICORE_MENU_PORT"
          ADVERTISE_HOST="" ADVERTISE_PORT="" ADVERTISE_CLI=0 ADVERTISE_AUTO_REQUESTED=0
          nb_collect_advertise_endpoint_interactive 'VLESS REALITY' "$PORT"
          VLESS_REALITY_ACTION=set-endpoint
          nobrand_menu_run nobrand_run_vless_reality_action
        fi
        ;;
      5) VLESS_REALITY_NAME=""; VLESS_REALITY_ACTION=status; nobrand_menu_run nobrand_run_vless_reality_action ;;
      6) reality_menu_select_instance && { VLESS_REALITY_ACTION=start; nobrand_menu_run nobrand_run_vless_reality_action; } ;;
      7) reality_menu_select_instance && { VLESS_REALITY_ACTION=stop; nobrand_menu_run nobrand_run_vless_reality_action; } ;;
      8) reality_menu_select_instance && { VLESS_REALITY_ACTION=restart; nobrand_menu_run nobrand_run_vless_reality_action; } ;;
      9) VLESS_REALITY_NAME=""; VLESS_REALITY_ACTION=doctor; nobrand_menu_run nobrand_run_vless_reality_action ;;
      10) VLESS_REALITY_ACTION=upgrade; nobrand_menu_run nobrand_run_vless_reality_action ;;
      11)
        if reality_menu_select_instance; then
          read_tty confirm '确认删除该 VLESS REALITY 实例？输入 yes 确认: ' || confirm=""
          [ "$confirm" = yes ] || { warn '已取消'; continue; }
          VLESS_REALITY_ACTION=remove
          nobrand_menu_run nobrand_run_vless_reality_action
        fi
        ;;
      0) return 0 ;;
      *) warn '无效选择' ;;
    esac
    menu_pause
  done
}

tuic_menu_select_instance() {
  nb_splicore_menu_select tuic
}

tuic_menu_loop() {
  local choice="" user="" confirm=""
  trap - ERR
  while true; do
    msg ''
    msg '========== TUIC v5 / Splicore =========='
    msg '  1) 安装 TUIC v5 实例'
    msg '  2) 查看 / 导出用户节点'
    msg '  3) 用户管理（列出 / 添加 / 删除 / 轮换凭据）'
    msg '  4) 修改展示端点 / Display Endpoint'
    msg '  5) 状态'
    msg '  6) 启动'
    msg '  7) 停止'
    msg '  8) 重启'
    msg '  9) 验证 / 升级统一 Splicore Runtime'
    msg ' 10) Doctor / 诊断'
    msg ' 11) 卸载实例'
    msg '  0) 返回'
    read_tty choice '请选择 [0-11]: ' || return 0
    case "$choice" in
      1)
        read_tty TUIC_NAME '实例名称 [primary]: ' || TUIC_NAME=""
        TUIC_NAME="${TUIC_NAME:-primary}"
        read_tty TUIC_USER '首个用户名称 [default]: ' || TUIC_USER=""
        TUIC_USER="${TUIC_USER:-default}"
        PORT="" ADVERTISE_HOST="" ADVERTISE_PORT="" ADVERTISE_CLI=0 ADVERTISE_AUTO_REQUESTED=0
        TUIC_SNI="" TUIC_CHANNEL=stable TUIC_VERSION="" YES=0 TUIC_ACTION=install
        nobrand_menu_run nobrand_run_tuic_action
        ;;
      2)
        tuic_menu_select_instance || continue
        read_tty TUIC_USER '用户名称（仅有一个用户时可留空）: ' || TUIC_USER=""
        TUIC_ACTION="export"; nobrand_menu_run nobrand_run_tuic_action
        ;;
      3)
        tuic_menu_select_instance || continue
        msg '  1) 列出用户  2) 添加用户  3) 删除用户  4) 轮换 UUID + 密码'
        read_tty confirm '请选择 [1-4]: ' || confirm=""
        case "$confirm" in
          1) TUIC_ACTION="user-list" ;;
          2) read_tty user '新用户名称: ' || user=""; TUIC_USER="$user"; TUIC_ACTION="user-add" ;;
          3) read_tty user '要删除的用户名称: ' || user=""; TUIC_USER="$user"; TUIC_ACTION="user-delete" ;;
          4) read_tty user '要轮换凭据的用户名称: ' || user=""; TUIC_USER="$user"; TUIC_ACTION="user-rotate" ;;
          *) warn '无效选择'; continue ;;
        esac
        nobrand_menu_run nobrand_run_tuic_action
        ;;
      4)
        tuic_menu_select_instance || continue
        ADVERTISE_HOST="" ADVERTISE_PORT="" ADVERTISE_CLI=0 ADVERTISE_AUTO_REQUESTED=0
        if nb_splicore_installed; then
          nb_collect_advertise_endpoint_interactive 'TUIC v5' "$NOBRAND_SPLICORE_MENU_PORT"
        else
          nb_collect_advertise_endpoint_interactive 'TUIC v5' "$NOBRAND_SPLICORE_MENU_PORT"
        fi
        TUIC_ACTION="set-endpoint"; nobrand_menu_run nobrand_run_tuic_action
        ;;
      5|6|7|8)
        tuic_menu_select_instance || continue
        case "$choice" in 5) TUIC_ACTION=status ;; 6) TUIC_ACTION=start ;; 7) TUIC_ACTION=stop ;; 8) TUIC_ACTION=restart ;; esac
        nobrand_menu_run nobrand_run_tuic_action
        ;;
      9) TUIC_CHANNEL=stable TUIC_VERSION="" TUIC_ACTION="upgrade-runtime"; nobrand_menu_run nobrand_run_tuic_action ;;
      10) TUIC_ACTION=doctor; nobrand_menu_run nobrand_run_tuic_action ;;
      11)
        tuic_menu_select_instance || continue
        read_tty confirm "确认卸载 ${TUIC_NAME}？输入 yes: " || confirm=""
        [ "$confirm" = yes ] || { warn '已取消'; continue; }
        TUIC_ACTION=uninstall; nobrand_menu_run nobrand_run_tuic_action
        ;;
      0) return 0 ;;
      *) warn '无效选择' ;;
    esac
    menu_pause
  done
}

ssh_tunnel_menu_loop() {
  local choice="" user="" confirm=""
  trap - ERR
  while true; do
    msg ''
    msg '========== SSH Tunnel（现有 OpenSSH） =========='
    msg 'TCP 转发：支持 -L / -D / -R；禁用 shell / exec / TTY / SFTP / SCP；GatewayPorts=no'
    msg '  1) 安装 SSH Tunnel 策略并创建首个用户'
    msg '  2) 查看用户'
    msg '  3) 显式导出用户私钥与连接命令'
    msg '  4) 用户管理（列出 / 添加 / 删除 / 轮换密钥）'
    msg '  5) 修改展示端点 / Display Endpoint'
    msg '  6) 状态'
    msg '  7) Doctor / 诊断'
    msg '  8) 卸载 SSH Tunnel'
    msg '  0) 返回'
    read_tty choice '请选择 [0-8]: ' || return 0
    case "$choice" in
      1)
        read_tty SSH_TUNNEL_USER '首个隧道用户标签 [default]: ' || SSH_TUNNEL_USER=""
        SSH_TUNNEL_USER="${SSH_TUNNEL_USER:-default}"
        ADVERTISE_HOST="" ADVERTISE_PORT="" ADVERTISE_CLI=0 ADVERTISE_AUTO_REQUESTED=0 YES=0
        SSH_TUNNEL_ACTION=install; nobrand_menu_run nobrand_run_ssh_tunnel_action
        ;;
      2|3)
        read_tty user '隧道用户标签（仅有一个用户时可留空）: ' || user=""
        SSH_TUNNEL_USER="$user"
        if [ "$choice" = 2 ]; then
          SSH_TUNNEL_ACTION="show"
        else
          SSH_TUNNEL_ACTION="export"
        fi
        nobrand_menu_run nobrand_run_ssh_tunnel_action
        ;;
      4)
        msg '  1) 列出用户  2) 添加用户  3) 删除用户  4) 轮换密钥'
        read_tty confirm '请选择 [1-4]: ' || confirm=""
        case "$confirm" in
          1) SSH_TUNNEL_ACTION="user-list" ;;
          2) read_tty user '新隧道用户标签: ' || user=""; SSH_TUNNEL_USER="$user"; SSH_TUNNEL_ACTION="user-add" ;;
          3) read_tty user '要删除的隧道用户标签: ' || user=""; SSH_TUNNEL_USER="$user"; SSH_TUNNEL_ACTION="user-delete" ;;
          4) read_tty user '要轮换密钥的隧道用户标签: ' || user=""; SSH_TUNNEL_USER="$user"; SSH_TUNNEL_ACTION="user-rotate-key" ;;
          *) warn '无效选择'; continue ;;
        esac
        nobrand_menu_run nobrand_run_ssh_tunnel_action
        ;;
      5)
        nb_collect_advertise_endpoint_interactive 'SSH Tunnel' "$(ssh_tunnel_state_field advertise_port)"
        SSH_TUNNEL_ACTION="set-endpoint"; nobrand_menu_run nobrand_run_ssh_tunnel_action
        ;;
      6) SSH_TUNNEL_ACTION=status; nobrand_menu_run nobrand_run_ssh_tunnel_action ;;
      7) SSH_TUNNEL_ACTION=doctor; nobrand_menu_run nobrand_run_ssh_tunnel_action ;;
      8)
        read_tty confirm '确认卸载 SSH Tunnel？输入 yes: ' || confirm=""
        [ "$confirm" = yes ] || { warn '已取消'; continue; }
        SSH_TUNNEL_ACTION=uninstall; nobrand_menu_run nobrand_run_ssh_tunnel_action
        ;;
      0) return 0 ;;
      *) warn '无效选择' ;;
    esac
    nobrand_ssh_confirmation_pending && return 0
    menu_pause
  done
}

forward_menu_reset_requests() {
  FORWARD_RULE_ID="" FORWARD_NAME="" FORWARD_NOTE="" FORWARD_BACKEND="" FORWARD_PROTOCOL=""
  FORWARD_LISTEN_HOST="" FORWARD_LISTEN_PORT="" FORWARD_TARGET_HOST="" FORWARD_TARGET_PORT=""
  FORWARD_SOURCE_MODE=masquerade FORWARD_SOURCE_MODE_CLI=0 FORWARD_ADVANCED_CLI=0
  FORWARD_THROUGH="" FORWARD_INTERFACE="" FORWARD_LISTEN_INTERFACE=""
  FORWARD_TCP_TIMEOUT=5 FORWARD_UDP_TIMEOUT=30 FORWARD_PROXY_SEND=false FORWARD_PROXY_ACCEPT=false
  FORWARD_PROXY_VERSION=2 FORWARD_PROXY_ACCEPT_TIMEOUT=5 FORWARD_DNS_MODE=system
  FORWARD_DNS_PROTOCOL=tcp_and_udp FORWARD_DNS_NAMESERVERS="" FORWARD_LISTEN_TRANSPORT=""
  FORWARD_REMOTE_TRANSPORT="" FORWARD_EXTRA_TARGETS="" FORWARD_BALANCE=off FORWARD_WEIGHTS=""
  ADVERTISE_HOST="" ADVERTISE_PORT="" ADVERTISE_CLI=0 ADVERTISE_AUTO_REQUESTED=0 YES=0
}

forward_menu_select_rule() {
  local selector=""
  forward_list_rules
  read_tty selector '请输入规则 ID 或名称: ' || selector=""
  [ -n "$selector" ] && forward_resolve_rule_id "$selector" >/dev/null 2>&1 \
    || { warn '端口转发规则不存在'; return 1; }
  FORWARD_RULE_ID="$selector"
}

forward_menu_collect_add() {
  local choice="" advanced=""
  forward_menu_reset_requests
  read_tty FORWARD_NAME '规则名称: ' || FORWARD_NAME=""
  [ -n "$FORWARD_NAME" ] || { warn '规则名称不能为空'; return 1; }
  msg '转发后端：1) nftables — 内核 NAT（简单 IP 转发）'
  msg '          2) Realm — 用户态中继（域名 / 高级转发）'
  read_tty choice '请选择 [1-2]: ' || choice=""
  case "$choice" in 1) FORWARD_BACKEND=nftables ;; 2) FORWARD_BACKEND=realm ;; *) warn '无效转发后端'; return 1 ;; esac
  msg '协议：1) TCP  2) UDP  3) TCP + UDP'
  read_tty choice '请选择 [1-3]: ' || choice=""
  case "$choice" in 1) FORWARD_PROTOCOL=tcp ;; 2) FORWARD_PROTOCOL=udp ;; 3) FORWARD_PROTOCOL=both ;; *) warn '无效协议'; return 1 ;; esac
  read_tty FORWARD_LISTEN_HOST '监听地址 [0.0.0.0]: ' || FORWARD_LISTEN_HOST=""
  FORWARD_LISTEN_HOST="${FORWARD_LISTEN_HOST:-0.0.0.0}"
  read_tty FORWARD_LISTEN_PORT '监听端口: ' || FORWARD_LISTEN_PORT=""
  read_tty FORWARD_TARGET_HOST '目标地址: ' || FORWARD_TARGET_HOST=""
  read_tty FORWARD_TARGET_PORT '目标端口: ' || FORWARD_TARGET_PORT=""
  read_tty FORWARD_NOTE '备注（可选）: ' || FORWARD_NOTE=""
  if [ "$FORWARD_BACKEND" = nftables ]; then
    msg '源地址模式：1) MASQUERADE（默认）  2) Preserve Source（高级；目标端需要正确回程路由）'
    read_tty choice '请选择 [1-2，默认 1]: ' || choice=""
    case "${choice:-1}" in
      1) FORWARD_SOURCE_MODE=masquerade ;;
      2)
        FORWARD_SOURCE_MODE=preserve
        warn 'Preserve Source 不做 SNAT；目标服务器必须经本转发机正确回程，否则连接会失败。'
        ;;
      *) warn '无效源地址模式'; return 1 ;;
    esac
  else
    read_tty advanced '配置 Realm 高级选项？[y/N]: ' || advanced=""
    case "$advanced" in
      y|Y|yes|YES)
        FORWARD_ADVANCED_CLI=1
        read_tty FORWARD_THROUGH '出站 IP / through（留空使用系统默认）: ' || FORWARD_THROUGH=""
        read_tty FORWARD_INTERFACE '出站网络接口（留空使用系统默认）: ' || FORWARD_INTERFACE=""
        read_tty FORWARD_LISTEN_INTERFACE '监听网络接口（留空使用系统默认）: ' || FORWARD_LISTEN_INTERFACE=""
        read_tty FORWARD_DNS_NAMESERVERS 'DNS 服务器（逗号分隔；留空使用系统默认）: ' || FORWARD_DNS_NAMESERVERS=""
        if [ -n "$FORWARD_DNS_NAMESERVERS" ]; then FORWARD_DNS_MODE=ipv4_and_ipv6; fi
        read_tty FORWARD_EXTRA_TARGETS '额外目标 host:port（逗号分隔；留空表示无）: ' || FORWARD_EXTRA_TARGETS=""
        if [ -n "$FORWARD_EXTRA_TARGETS" ]; then
          read_tty FORWARD_BALANCE '负载均衡方式 [roundrobin/iphash]: ' || FORWARD_BALANCE=""
          read_tty FORWARD_WEIGHTS '权重（包含主目标，逗号分隔）: ' || FORWARD_WEIGHTS=""
        fi
        ;;
    esac
  fi
  nb_collect_advertise_endpoint_interactive 'Port Forward' "$FORWARD_LISTEN_PORT"
}

forward_menu_loop() {
  local choice="" confirm="" backend_choice="" path=""
  trap - ERR
  while true; do
    msg ''
    msg '========== 端口转发 / Port Forward =========='
    msg '  1) 添加转发规则'
    msg '  2) 查看规则列表'
    msg '  3) 查看规则详情'
    msg '  4) 修改规则'
    msg '  5) 切换转发后端'
    msg '  6) 启用规则'
    msg '  7) 禁用规则'
    msg '  8) 设置展示端点 / Display Endpoint'
    msg '  9) 删除规则'
    msg ' 10) Doctor / 诊断'
    msg ' 11) 导出 JSON'
    msg ' 12) 导入 JSON'
    msg ' 13) 升级官方 Realm Runtime'
    msg '  0) 返回'
    read_tty choice '请选择 [0-13]: ' || return 0
    case "$choice" in
      1)
        forward_menu_collect_add || continue
        FORWARD_ACTION=add; nobrand_menu_run nobrand_run_forward_action
        ;;
      2) FORWARD_ACTION=list; nobrand_menu_run nobrand_run_forward_action ;;
      3) forward_menu_reset_requests; forward_menu_select_rule || continue; FORWARD_ACTION=show; nobrand_menu_run nobrand_run_forward_action ;;
      4)
        forward_menu_reset_requests; forward_menu_select_rule || continue
        read_tty FORWARD_TARGET_HOST '新目标地址（留空保持不变）: ' || FORWARD_TARGET_HOST=""
        read_tty FORWARD_TARGET_PORT '新目标端口（留空保持不变）: ' || FORWARD_TARGET_PORT=""
        FORWARD_ACTION=modify; nobrand_menu_run nobrand_run_forward_action
        ;;
      5)
        forward_menu_reset_requests; forward_menu_select_rule || continue
        msg '新转发后端：1) nftables  2) Realm'
        read_tty backend_choice '请选择 [1-2]: ' || backend_choice=""
        case "$backend_choice" in 1) FORWARD_BACKEND=nftables ;; 2) FORWARD_BACKEND=realm ;; *) warn '无效转发后端'; continue ;; esac
        if [ "$FORWARD_BACKEND" = nftables ]; then
          read_tty FORWARD_TARGET_HOST 'nftables IPv4 目标地址（域名规则必须明确填写；留空时保留已有 IPv4）: ' || FORWARD_TARGET_HOST=""
        fi
        FORWARD_ACTION=switch-backend; nobrand_menu_run nobrand_run_forward_action
        ;;
      6|7)
        forward_menu_reset_requests; forward_menu_select_rule || continue
        [ "$choice" = 6 ] && FORWARD_ACTION=enable || FORWARD_ACTION=disable
        nobrand_menu_run nobrand_run_forward_action
        ;;
      8)
        forward_menu_reset_requests; forward_menu_select_rule || continue
        nb_collect_advertise_endpoint_interactive 'Port Forward' \
          "$(jq -r --arg id "$(forward_resolve_rule_id "$FORWARD_RULE_ID")" '.rules[]|select(.rule_id==$id)|.listen_port' "$NOBRAND_FORWARD_STATE_FILE")"
        FORWARD_ACTION=set-endpoint; nobrand_menu_run nobrand_run_forward_action
        ;;
      9)
        forward_menu_reset_requests; forward_menu_select_rule || continue
        read_tty confirm '确认删除此转发规则？输入 yes 确认: ' || confirm=""
        [ "$confirm" = yes ] || { warn '已取消'; continue; }
        FORWARD_ACTION=delete; nobrand_menu_run nobrand_run_forward_action
        ;;
      10) FORWARD_ACTION=doctor; nobrand_menu_run nobrand_run_forward_action ;;
      11)
        read_tty path '导出路径（留空输出到终端）: ' || path=""
        FORWARD_EXPORT_FILE="$path" FORWARD_ACTION=export; nobrand_menu_run nobrand_run_forward_action
        ;;
      12)
        read_tty path '请输入要导入的 JSON 文件路径: ' || path=""
        [ -n "$path" ] || { warn '路径不能为空'; continue; }
        FORWARD_IMPORT_FILE="$path" FORWARD_ACTION=import; nobrand_menu_run nobrand_run_forward_action
        ;;
      13) FORWARD_ACTION=upgrade-runtime; nobrand_menu_run nobrand_run_forward_action ;;
      0) return 0 ;;
      *) warn '无效选择' ;;
    esac
    menu_pause
  done
}

nobrand_backup_menu_loop() {
  local choice="" path=""
  trap - ERR
  while true; do
    msg ''
    msg '========== NoBrand 备份 / 恢复 =========='
    msg '  1) 创建备份'
    msg '  2) 列出备份'
    msg '  3) 从备份恢复'
    msg '  0) 返回'
    read_tty choice "$(t '请选择 [0-3]: ' 'Choose [0-3]: ')" || return 0
    case "$choice" in
      1)
        NOBRAND_BACKUP_ACTION=create NOBRAND_BACKUP_PATH=""
        nobrand_menu_run nobrand_backup_action
        ;;
      2)
        NOBRAND_BACKUP_ACTION=list NOBRAND_BACKUP_PATH=""
        nobrand_menu_run nobrand_backup_action
        ;;
      3)
        read_tty path "$(t '备份文件绝对路径: ' 'Absolute backup path: ')" || path=""
        [ -n "$path" ] || { warn '备份路径不能为空'; continue; }
        NOBRAND_BACKUP_ACTION=restore NOBRAND_BACKUP_PATH="$path"
        nobrand_menu_run nobrand_backup_action
        ;;
      0) return 0 ;;
      *) warn '无效选择' ;;
    esac
    nobrand_ssh_confirmation_pending && return 0
    menu_pause
  done
}

ingress_menu_reset_requests() {
  INGRESS_PROFILE_SELECTOR="" INGRESS_NAME="" INGRESS_TYPE="" INGRESS_INTERFACE="" INGRESS_ADDRESS=""
  INGRESS_PORT_POLICY="" INGRESS_RANGE_START="" INGRESS_RANGE_END="" INGRESS_RESERVED_PORTS=""
  INGRESS_DISPLAY_HOST_DEFAULT="" INGRESS_DISPLAY_PORT_POLICY="" INGRESS_DISPLAY_PORT="" INGRESS_ENABLED=""
  INGRESS_ENFORCEMENT="" INGRESS_APPLY_EXISTING=0
  INGRESS_NAME_CLI=0 INGRESS_TYPE_CLI=0 INGRESS_INTERFACE_CLI=0 INGRESS_ADDRESS_CLI=0
  INGRESS_PORT_POLICY_CLI=0 INGRESS_RANGE_START_CLI=0 INGRESS_RANGE_END_CLI=0 INGRESS_RESERVED_CLI=0
  INGRESS_DISPLAY_HOST_CLI=0 INGRESS_DISPLAY_PORT_POLICY_CLI=0 INGRESS_DISPLAY_PORT_CLI=0 INGRESS_ENABLED_CLI=0
  INGRESS_ENFORCEMENT_CLI=0
}

ingress_menu_select_profile() {
  nb_ingress_list || return 1
  read_tty INGRESS_PROFILE_SELECTOR "$(t '入口配置 ID 或名称: ' 'Ingress profile ID or name: ')" \
    || INGRESS_PROFILE_SELECTOR=""
  [ -n "$INGRESS_PROFILE_SELECTOR" ] || { warn '未选择入口配置'; return 1; }
}

ingress_menu_interface_row_count() {
  local rows="${1:-}" iface _address _state _default count=0
  while IFS='|' read -r iface _address _state _default; do
    [ -n "$iface" ] || continue
    count=$((count + 1))
  done <<<"$rows"
  printf '%s' "$count"
}

ingress_menu_print_interface_rows() {
  local rows="${1:-}" iface address state is_default index=0
  while IFS='|' read -r iface address state is_default; do
    [ -n "$iface" ] || continue
    index=$((index + 1))
    printf '  %s) %s  %s  [%s]%s\n' "$index" "$iface" "$address" "$state" \
      "$([ "$is_default" = 1 ] && printf ' [默认出口/default egress]' || true)"
  done <<<"$rows"
}

ingress_menu_interface_in_rows() {
  local rows="${1:-}" expected="${2:-}" iface _address _state _default
  while IFS='|' read -r iface _address _state _default; do
    [ "$iface" = "$expected" ] && return 0
  done <<<"$rows"
  return 1
}

ingress_menu_pair_in_rows() {
  local rows="${1:-}" expected_iface="${2:-}" expected_address="${3:-}"
  local iface address _state _default
  while IFS='|' read -r iface address _state _default; do
    [ "$iface" = "$expected_iface" ] && [ "$address" = "$expected_address" ] && return 0
  done <<<"$rows"
  return 1
}

ingress_menu_row_at() {
  local rows="${1:-}" wanted="${2:-}" row iface _address _state _default index=0
  while IFS= read -r row; do
    IFS='|' read -r iface _address _state _default <<<"$row"
    [ -n "$iface" ] || continue
    index=$((index + 1))
    if [ "$index" -eq "$wanted" ]; then
      printf '%s' "$row"
      return 0
    fi
  done <<<"$rows"
  return 1
}

ingress_menu_collect_listener() {
  local rows="$1" row_count="$2" selected="" choice="" value=""
  local default_iface="" default_address="" _state _default
  if [ "$row_count" -eq 1 ]; then
    selected="$(ingress_menu_row_at "$rows" 1)" || return 1
    IFS='|' read -r default_iface default_address _state _default <<<"$selected"
    while true; do
      if ! read_tty value "$(t "网络接口 / Interface [${default_iface}]: " "Interface [${default_iface}]: ")"; then
        warn '已取消选择本地监听网络接口'
        return 1
      fi
      [ -n "$value" ] || value="$default_iface"
      if ingress_menu_interface_in_rows "$rows" "$value"; then
        INGRESS_INTERFACE="$value"
        break
      fi
      warn "网络接口不存在或没有可用的非回环 IPv4: ${value}"
    done
    while true; do
      if ! read_tty value "$(t "本地监听 IPv4 [${default_address}]: " "Local listener IPv4 [${default_address}]: ")"; then
        warn '已取消选择本地监听 IPv4'
        return 1
      fi
      [ -n "$value" ] || value="$default_address"
      if ingress_menu_pair_in_rows "$rows" "$INGRESS_INTERFACE" "$value"; then
        INGRESS_ADDRESS="$value"
        break
      fi
      warn "该 IPv4 未配置在所选网络接口 ${INGRESS_INTERFACE} 上: ${value}"
    done
  else
    while true; do
      if ! read_tty choice "$(t "选择本地监听接口/IPv4 [1-${row_count}，m=手动，0=返回]: " \
        "Select local listener interface/IPv4 [1-${row_count}, m=manual, 0=back]: ")"; then
        warn '已取消选择本地监听地址'
        return 1
      fi
      case "$choice" in
        0) return 1 ;;
        m|M|manual|手动)
          while true; do
            if ! read_tty value "$(t '手动网络接口 / Interface（0=返回）: ' 'Manual interface (0=back): ')"; then
              warn '已取消选择本地监听网络接口'
              return 1
            fi
            [ "$value" != 0 ] || return 1
            if ingress_menu_interface_in_rows "$rows" "$value"; then
              INGRESS_INTERFACE="$value"
              break
            fi
            warn "网络接口不存在或没有可用的非回环 IPv4: ${value}"
          done
          while true; do
            if ! read_tty value "$(t '本地监听 IPv4（0=返回）: ' 'Local listener IPv4 (0=back): ')"; then
              warn '已取消选择本地监听 IPv4'
              return 1
            fi
            [ "$value" != 0 ] || return 1
            if ingress_menu_pair_in_rows "$rows" "$INGRESS_INTERFACE" "$value"; then
              INGRESS_ADDRESS="$value"
              break
            fi
            warn "该 IPv4 未配置在所选网络接口 ${INGRESS_INTERFACE} 上: ${value}"
          done
          break
          ;;
        *)
          if [[ "$choice" =~ ^[0-9]+$ ]] \
             && [ "$choice" -ge 1 ] && [ "$choice" -le "$row_count" ]; then
            selected="$(ingress_menu_row_at "$rows" "$choice")" || return 1
            IFS='|' read -r INGRESS_INTERFACE INGRESS_ADDRESS _state _default <<<"$selected"
            break
          fi
          warn '请选择列表编号、m 手动输入，或 0 返回'
          ;;
      esac
    done
  fi
  INGRESS_INTERFACE_CLI=1
  INGRESS_ADDRESS_CLI=1
}

ingress_menu_collect_custom_range() {
  local range_start="" range_end="" normalized_start normalized_end
  while true; do
    if ! read_tty range_start "$(t '范围起始端口: ' 'Range start port: ')" \
       || ! read_tty range_end "$(t '范围结束端口: ' 'Range end port: ')"; then
      warn '已取消自定义端口范围'
      return 1
    fi
    normalized_start="$(normalize_uint "$range_start" 2>/dev/null || true)"
    normalized_end="$(normalize_uint "$range_end" 2>/dev/null || true)"
    if nb_valid_port "$normalized_start" && nb_valid_port "$normalized_end" \
       && [ "$normalized_start" -ge 1025 ] && [ "$normalized_start" -le "$normalized_end" ]; then
      INGRESS_RANGE_START="$normalized_start"
      INGRESS_RANGE_END="$normalized_end"
      INGRESS_RANGE_START_CLI=1
      INGRESS_RANGE_END_CLI=1
      return 0
    fi
    warn '端口范围无效：起始端口必须不小于 1025，且不能大于结束端口'
  done
}

ingress_menu_collect_port_policy() {
  local choice="" fallback=""
  while true; do
    msg '  1) derived-tail（由所选本地 IPv4 尾号推导）'
    msg '  2) custom-range（自定义范围）'
    msg '  3) manual-only（仅手动指定）'
    if ! read_tty choice "$(t '端口策略 [1-3，0=返回]: ' 'Port policy [1-3, 0=back]: ')"; then
      warn '已取消端口策略选择'
      return 1
    fi
    case "$choice" in
      0) return 1 ;;
      1|derived-tail)
        if nb_port_base_for_ip "$INGRESS_ADDRESS" >/dev/null 2>&1; then
          INGRESS_PORT_POLICY='derived-tail'
          break
        fi
        warn '所选本地 IPv4 无法使用 derived-tail。请选择替代策略：'
        msg '  1) custom-range（自定义范围）'
        msg '  2) manual-only（仅手动指定）'
        msg '  0) 返回 Ingress 菜单'
        while true; do
          if ! read_tty fallback "$(t '替代策略 [0-2]: ' 'Fallback policy [0-2]: ')"; then
            warn '已取消端口策略选择'
            return 1
          fi
          case "$fallback" in
            0) return 1 ;;
            1|custom-range)
              INGRESS_PORT_POLICY='custom-range'
              ingress_menu_collect_custom_range || return 1
              break 2
              ;;
            2|manual-only)
              INGRESS_PORT_POLICY='manual-only'
              break 2
              ;;
            *) warn '无效替代策略；请输入 0、1 或 2' ;;
          esac
        done
        ;;
      2|custom-range)
        INGRESS_PORT_POLICY='custom-range'
        ingress_menu_collect_custom_range || return 1
        break
        ;;
      3|manual-only)
        INGRESS_PORT_POLICY='manual-only'
        break
        ;;
      *) warn '无效端口策略；请输入 0-3' ;;
    esac
  done
  INGRESS_PORT_POLICY_CLI=1
}

ingress_menu_collect_add() {
  local choice="" value="" rows="" row_count=0
  rows="$(nb_ingress_interface_rows)"
  row_count="$(ingress_menu_interface_row_count "$rows")"
  if [ "$row_count" -eq 0 ]; then
    t '[错误] 未检测到可用的非回环 IPv4；请先为网络接口配置本地 IPv4' \
      '[error] No eligible non-loopback IPv4 was found; configure a local IPv4 first' >&2
    return 1
  fi
  ingress_menu_reset_requests
  msg ''
  t '可用非回环 IPv4；网络接口 / Interface:（[默认出口] 仅为只读提示，不决定 Ingress）' \
    'Available non-loopback IPv4 interfaces ([default egress] is read-only and does not select Ingress)'
  ingress_menu_print_interface_rows "$rows"
  if ! read_tty INGRESS_NAME "$(t '名称: ' 'Name: ')"; then
    warn '已取消新增入口'
    return 1
  fi
  INGRESS_NAME_CLI=1
  msg '  1) public   2) mapped'
  if ! read_tty choice "$(t '类型 [1-2]: ' 'Type [1-2]: ')"; then
    warn '已取消新增入口'
    return 1
  fi
  case "$choice" in 1|public) INGRESS_TYPE=public ;; 2|mapped) INGRESS_TYPE=mapped ;; *) warn '无效类型'; return 1 ;; esac
  INGRESS_TYPE_CLI=1
  ingress_menu_collect_listener "$rows" "$row_count" || return 1
  if [ "$INGRESS_TYPE" = public ] && nb_ingress_is_rfc1918 "$INGRESS_ADDRESS"; then
    t '[提示] 所选本地 IPv4 为私网地址。' \
      '[hint] The selected local IPv4 is an RFC1918 private address.'
    t '如果客户端通过公网、IPLC、NAT 或端口映射进入，' \
      'If clients enter through the public Internet, IPLC, NAT, or port mapping,'
    t '通常应使用 mapped，并设置 Display Host；当前类型仍保持 public。' \
      'mapped with an explicit Display Host is usually appropriate; the type remains public.'
  fi
  ingress_menu_collect_port_policy || return 1
  if ! read_tty value "$(t '额外保留端口（逗号分隔，可留空）: ' 'Additional reserved ports (comma-separated, optional): ')"; then
    warn '已取消新增入口'
    return 1
  fi
  if [ -n "$value" ]; then INGRESS_RESERVED_PORTS="$value"; INGRESS_RESERVED_CLI=1; fi
  if [ "$INGRESS_TYPE" = mapped ]; then
    while true; do
      if ! read_tty value "$(t '展示入口 / Display Host（mapped 必填；不同于本地监听 IPv4）: ' \
        'Display entry / Display Host (required for mapped; distinct from local listener IPv4): ')"; then
        warn '已取消新增入口'
        return 1
      fi
      if [ -n "$value" ] && valid_advertise_host "$value"; then
        INGRESS_DISPLAY_HOST_DEFAULT="$value"
        INGRESS_DISPLAY_HOST_CLI=1
        break
      fi
      warn 'mapped 入口必须显式填写有效的 Display Host'
    done
  else
    while true; do
      if ! read_tty value "$(t '展示入口 / Display Host（可留空；默认使用本地监听 IPv4）: ' \
        'Display entry / Display Host (optional; defaults to local listener IPv4): ')"; then
        warn '已取消新增入口'
        return 1
      fi
      if [ -z "$value" ]; then
        break
      elif valid_advertise_host "$value"; then
        INGRESS_DISPLAY_HOST_DEFAULT="$value"
        INGRESS_DISPLAY_HOST_CLI=1
        break
      fi
      warn 'Display Host 无效，请重新输入或留空'
    done
  fi
  INGRESS_DISPLAY_PORT_POLICY='follow-actual' INGRESS_DISPLAY_PORT_POLICY_CLI=1
  msg '  1) permissive（兼容 wildcard，默认）   2) strict（限制到 Profile 本地地址）'
  if ! read_tty choice "$(t '入口强制策略 [1-2，默认 1]: ' 'Ingress enforcement [1-2, default 1]: ')"; then
    warn '已取消新增入口'
    return 1
  fi
  case "$choice" in
    ''|1|permissive) INGRESS_ENFORCEMENT=permissive ;;
    2|strict) INGRESS_ENFORCEMENT=strict ;;
    *) warn '无效入口强制策略'; return 1 ;;
  esac
  INGRESS_ENFORCEMENT_CLI=1
  nb_ingress_prepare_add_request "$rows" || return 1
}

ingress_menu_modify() {
  local current value choice current_type current_policy current_display_policy current_enabled current_enforcement
  local effective_policy effective_display_policy effective_enforcement range_start range_end display_port refs
  ingress_menu_reset_requests
  ingress_menu_select_profile || return 1
  current="$(nb_ingress_profile_json "$INGRESS_PROFILE_SELECTOR")" || return 1
  read_tty value "$(t "新名称 [$(jq -r .name <<<"$current")]: " "New name [$(jq -r .name <<<"$current")]: ")" || value=""
  if [ -n "$value" ]; then INGRESS_NAME="$value"; INGRESS_NAME_CLI=1; fi
  current_type="$(jq -r .type <<<"$current")"
  msg '  1) public   2) mapped'
  read_tty choice "$(t "新类型 [${current_type}；留空保持]: " "New type [${current_type}; blank keeps current]: ")" || choice=""
  case "$choice" in
    '') ;;
    1|public) INGRESS_TYPE=public; INGRESS_TYPE_CLI=1 ;;
    2|mapped) INGRESS_TYPE=mapped; INGRESS_TYPE_CLI=1 ;;
    *) warn '无效类型'; return 1 ;;
  esac
  read_tty value "$(t '新网络接口 / Interface（留空保持）: ' 'New interface (blank keeps current): ')" || value=""
  if [ -n "$value" ]; then INGRESS_INTERFACE="$value"; INGRESS_INTERFACE_CLI=1; fi
  read_tty value "$(t '新本地 IPv4（留空保持）: ' 'New local IPv4 (blank keeps current): ')" || value=""
  if [ -n "$value" ]; then INGRESS_ADDRESS="$value"; INGRESS_ADDRESS_CLI=1; fi

  current_policy="$(jq -r .port_policy <<<"$current")"
  msg '  1) derived-tail（按 IPv4 尾号推导）  2) custom-range（自定义范围）  3) manual-only（仅手动指定）'
  read_tty choice "$(t "新端口策略 [${current_policy}；留空保持]: " "New port policy [${current_policy}; blank keeps current]: ")" || choice=""
  case "$choice" in
    '') effective_policy="$current_policy" ;;
    1|derived-tail) INGRESS_PORT_POLICY='derived-tail'; INGRESS_PORT_POLICY_CLI=1; effective_policy='derived-tail' ;;
    2|custom-range) INGRESS_PORT_POLICY='custom-range'; INGRESS_PORT_POLICY_CLI=1; effective_policy='custom-range' ;;
    3|manual-only) INGRESS_PORT_POLICY='manual-only'; INGRESS_PORT_POLICY_CLI=1; effective_policy='manual-only' ;;
    *) warn '无效端口策略'; return 1 ;;
  esac
  if [ "$effective_policy" = custom-range ]; then
    range_start="$(jq -r '.range_start // empty' <<<"$current")"
    range_end="$(jq -r '.range_end // empty' <<<"$current")"
    read_tty value "$(t "范围起始端口 [${range_start:-必填}]: " "Range start [${range_start:-required}]: ")" || value=""
    if [ -n "$value" ]; then range_start="$value"; INGRESS_RANGE_START="$value"; INGRESS_RANGE_START_CLI=1; fi
    read_tty value "$(t "范围结束端口 [${range_end:-必填}]: " "Range end [${range_end:-required}]: ")" || value=""
    if [ -n "$value" ]; then range_end="$value"; INGRESS_RANGE_END="$value"; INGRESS_RANGE_END_CLI=1; fi
    if [ "$INGRESS_PORT_POLICY_CLI" -eq 1 ]; then
      [ -n "$range_start" ] && [ -n "$range_end" ] || { warn 'custom-range 需要起止端口'; return 1; }
      INGRESS_RANGE_START="$range_start" INGRESS_RANGE_END="$range_end"
      INGRESS_RANGE_START_CLI=1 INGRESS_RANGE_END_CLI=1
    fi
  fi
  read_tty value "$(t '新保留端口列表（留空保持，- 清空）: ' 'New reserved-port list (blank keeps current, - clears): ')" || value=""
  if [ "$value" = - ]; then
    INGRESS_RESERVED_PORTS=""; INGRESS_RESERVED_CLI=1
  elif [ -n "$value" ]; then
    INGRESS_RESERVED_PORTS="$value"; INGRESS_RESERVED_CLI=1
  fi
  read_tty value "$(t '新默认展示主机 / Display Host（留空保持，- 清空）: ' 'New default Display Host (blank keeps current, - clears): ')" || value=""
  if [ "$value" = - ]; then
    INGRESS_DISPLAY_HOST_DEFAULT=""; INGRESS_DISPLAY_HOST_CLI=1
  elif [ -n "$value" ]; then
    INGRESS_DISPLAY_HOST_DEFAULT="$value"; INGRESS_DISPLAY_HOST_CLI=1
  fi

  current_display_policy="$(jq -r .display_port_policy <<<"$current")"
  msg '  1) follow-actual（跟随实际监听）  2) custom（自定义）'
  read_tty choice "$(t "新展示端口 / Display Port 策略 [${current_display_policy}；留空保持]: " "New Display Port policy [${current_display_policy}; blank keeps current]: ")" || choice=""
  case "$choice" in
    '') effective_display_policy="$current_display_policy" ;;
    1|follow-actual) INGRESS_DISPLAY_PORT_POLICY='follow-actual'; INGRESS_DISPLAY_PORT_POLICY_CLI=1; effective_display_policy='follow-actual' ;;
    2|custom) INGRESS_DISPLAY_PORT_POLICY=custom; INGRESS_DISPLAY_PORT_POLICY_CLI=1; effective_display_policy=custom ;;
    *) warn '无效 Display Port 策略'; return 1 ;;
  esac
  if [ "$effective_display_policy" = custom ]; then
    display_port="$(jq -r '.display_port // empty' <<<"$current")"
    read_tty value "$(t "新展示端口 / Display Port [${display_port:-必填}]: " "New Display Port [${display_port:-required}]: ")" || value=""
    if [ -n "$value" ]; then display_port="$value"; INGRESS_DISPLAY_PORT="$value"; INGRESS_DISPLAY_PORT_CLI=1; fi
    if [ "$INGRESS_DISPLAY_PORT_POLICY_CLI" -eq 1 ]; then
      [ -n "$display_port" ] || { warn 'custom Display Port 策略需要端口'; return 1; }
      INGRESS_DISPLAY_PORT="$display_port" INGRESS_DISPLAY_PORT_CLI=1
    fi
  fi

  current_enabled="$(jq -r .enabled <<<"$current")"
  read_tty choice "$(t "启用状态 [${current_enabled}；1=启用，2=禁用，留空保持]: " "Enabled [${current_enabled}; 1=enable, 2=disable, blank keeps current]: ")" || choice=""
  case "$choice" in
    '') ;;
    1|true|enable|enabled) INGRESS_ENABLED=true; INGRESS_ENABLED_CLI=1 ;;
    2|false|disable|disabled) INGRESS_ENABLED=false; INGRESS_ENABLED_CLI=1 ;;
    *) warn '无效启用状态'; return 1 ;;
  esac

  current_enforcement="$(jq -r '.ingress_enforcement // "permissive"' <<<"$current")"
  msg '  1) permissive（wildcard）   2) strict（Profile 本地地址）'
  read_tty choice "$(t "入口强制策略 [${current_enforcement}；留空保持]: " "Ingress enforcement [${current_enforcement}; blank keeps current]: ")" || choice=""
  case "$choice" in
    '') effective_enforcement="$current_enforcement" ;;
    1|permissive) INGRESS_ENFORCEMENT=permissive; INGRESS_ENFORCEMENT_CLI=1; effective_enforcement=permissive ;;
    2|strict) INGRESS_ENFORCEMENT=strict; INGRESS_ENFORCEMENT_CLI=1; effective_enforcement=strict ;;
    *) warn '无效入口强制策略'; return 1 ;;
  esac
  if [ "$current_enforcement" != "$effective_enforcement" ] \
     || { [ "$effective_enforcement" = strict ] \
          && { [ "$INGRESS_INTERFACE_CLI" -eq 1 ] || [ "$INGRESS_ADDRESS_CLI" -eq 1 ]; }; }; then
    refs="$(nb_ingress_profile_reference_rows "$(jq -r .profile_id <<<"$current")" | grep -Ev '^ssh-tunnel:' || true)"
    if [ -n "$refs" ]; then
      printf '%s\n' "$refs"
      confirm '事务迁移以上现有节点？[y/N]: ' 'Transactionally migrate these existing nodes? [y/N]: ' n \
        || return 1
      INGRESS_APPLY_EXISTING=1
    fi
  fi
  INGRESS_ACTION=modify
  nobrand_menu_run nobrand_run_ingress_action
}

ingress_menu_loop() {
  local choice=""
  while true; do
    msg ''
    t '【网络入口 / Ingress】' '[Network Ingress]'
    msg '  1) 查看入口'
    msg '  2) 新增入口'
    msg '  3) 修改入口'
    msg '  4) 删除入口'
    msg '  5) 设置默认入口'
    msg '  6) 取消默认入口'
    msg '  7) 应用入口强制策略'
    msg '  8) Doctor / 入口诊断'
    msg '  0) 返回'
    read_tty choice "$(t '请选择 [0-8]: ' 'Choose [0-8]: ')" || return 0
    case "$choice" in
      1) nobrand_menu_run nb_ingress_list ;;
      2)
        if ingress_menu_collect_add; then
          INGRESS_ACTION=add
          nobrand_menu_run nobrand_run_ingress_action
        fi
        ;;
      3)
        if ingress_menu_modify; then
          :
        fi
        ;;
      4)
        ingress_menu_reset_requests
        if ingress_menu_select_profile \
           && confirm '确认删除？[y/N]: ' 'Delete this profile? [y/N]: ' n; then
          INGRESS_ACTION=delete
          nobrand_menu_run nobrand_run_ingress_action
        fi
        ;;
      5)
        ingress_menu_reset_requests
        if ingress_menu_select_profile; then
          INGRESS_ACTION=set-default
          nobrand_menu_run nobrand_run_ingress_action
        fi
        ;;
      6)
        ingress_menu_reset_requests
        INGRESS_ACTION=unset-default
        nobrand_menu_run nobrand_run_ingress_action
        ;;
      7)
        ingress_menu_reset_requests
        if ingress_menu_select_profile; then
          INGRESS_ACTION=apply
          nobrand_menu_run nobrand_run_ingress_action
        fi
        ;;
      8) nobrand_menu_run nb_ingress_doctor ;;
      0) return 0 ;;
      *) warn '无效选择' ;;
    esac
    menu_pause
  done
}

nobrand_menu_loop() {
  local choice="" uninstall_rc=0
  MENU_MODE=1
  trap - ERR
  while true; do
    nobrand_print_banner
    msg ''
    msg '  1) Mieru'
    msg '  2) Snell v4 / v5'
    msg '  3) Hysteria2 + Salamander'
    msg '  4) TUIC v5'
    msg '  5) VLESS REALITY + Vision（TCP；推荐 Public Ingress）'
    msg '  6) VLESS + FinalMask + Sudoku（TCP）'
    msg '  7) SSH Tunnel（现有 OpenSSH）'
    msg '  8) 端口转发 / Port Forward（nftables / Realm）'
    msg '  9) 网络入口 / Ingress'
    msg ' 10) 查看全部节点'
    msg ' 11) 综合状态'
    msg ' 12) Doctor / 诊断'
    msg ' 13) 备份 / 恢复'
    msg ' 14) 性能 / BBR / FQ（Mieru 公共网络工具）'
    msg ' 15) 帮助 / CLI'
    msg ' 16) 卸载 NoBrand-OneClick（全部协议）'
    msg '  0) 退出'
    read_tty choice "$(t '请选择 [0-16]: ' 'Choose [0-16]: ')" || return 0
    case "$choice" in
      1) menu_loop ;;
      2) snell_menu_loop ;;
      3) hysteria2_menu_loop ;;
      4) tuic_menu_loop ;;
      5) vless_reality_menu_loop ;;
      6) vless_sudoku_menu_loop ;;
      7) ssh_tunnel_menu_loop ;;
      8) forward_menu_loop ;;
      9) ingress_menu_loop ;;
      10) NOBRAND_PROTOCOL_FILTER=""; nobrand_menu_run nobrand_nodes; menu_pause ;;
      11) nobrand_menu_run nobrand_status; menu_pause ;;
      12) nobrand_menu_run nobrand_doctor; menu_pause ;;
      13) nobrand_backup_menu_loop ;;
      14) nobrand_menu_run do_perf; menu_pause ;;
      15) nobrand_usage; menu_pause ;;
      16)
        YES=0
        set +e
        nobrand_menu_run nobrand_uninstall
        uninstall_rc=$?
        set -e
        if [ "$uninstall_rc" -eq "${NOBRAND_MENU_EXIT_SUCCESS:-4}" ]; then
          return 0
        fi
        nobrand_ssh_confirmation_pending || menu_pause
        ;;
      0) return 0 ;;
      *) warn '无效选择' ;;
    esac
    if nobrand_ssh_confirmation_pending; then
      nobrand_pending_ssh_confirmation_notice
      return 0
    fi
  done
}

nobrand_ssh_confirmation_pending() {
  local token=""
  declare -F ssh_tunnel_state_exists >/dev/null 2>&1 || return 1
  ssh_tunnel_state_exists 2>/dev/null || return 1
  token="$(ssh_tunnel_state_field pending_watchdog_token 2>/dev/null || true)"
  [ -n "$token" ] && [ "$token" != disabled ]
}

nobrand_pending_ssh_confirmation_notice() {
  local token
  token="$(ssh_tunnel_state_field pending_watchdog_token 2>/dev/null || true)"
  [ -n "$token" ] && [ "$token" != disabled ] || return 1
  t 'SSH 策略正在等待全新管理员连接确认；当前管理菜单将退出以释放生命周期锁。请从全新连接运行：' \
    'SSH policy is awaiting confirmation from a fresh administrator connection. This menu will exit to release the lifecycle lock. Run from the fresh connection:'
  printf '  nobrand ssh confirm-admin --token %s\n' "$token"
}

nobrand_action_is_ssh_confirmation() {
  [ "${ACTION:-}" = nobrand-ssh-tunnel ] \
    && [ "${SSH_TUNNEL_ACTION:-}" = confirm-admin ]
}

nobrand_recovery_action_allowed() {
  local state="$1" action="${2:-}"
  [ -n "$action" ] || return 0
  nobrand_action_is_ssh_confirmation && return 0
  case "$state:$action" in
    CURRENT_PARTIAL_INSTALL:install|CURRENT_PARTIAL_REPAIR:install|\
      CURRENT_PARTIAL_UNINSTALL:install|CURRENT_PARTIAL_UNINSTALL:nobrand-uninstall)
      return 0
      ;;
  esac
  if [ "$state" = CURRENT_PARTIAL_INSTALL ] \
     && [ -n "${NOBRAND_PROTOCOL_EXPLICIT_RETRY_SCOPE:-}" ] \
     && nb_lifecycle_tx_valid \
     && [ "$(nb_lifecycle_field STATUS)" = in-progress ] \
     && [ "$(nb_lifecycle_scope)" = "$NOBRAND_PROTOCOL_EXPLICIT_RETRY_SCOPE" ]; then
    if [ "$NOBRAND_PROTOCOL_EXPLICIT_RETRY_SCOPE" = forward ]; then
      [ "$(nb_lifecycle_field FORMAT)" = nobrand-lifecycle-v2 ] \
        && [ "$(nb_lifecycle_mutation_started)" = 0 ] || return 1
    fi
    return 0
  fi
  if [ "$state:$action" = CURRENT_PARTIAL_CONFIGURE:nobrand-ingress ] \
     && [ "${NOBRAND_PROTOCOL_EXPLICIT_RETRY_SCOPE:-}" = ingress ] \
     && nb_lifecycle_tx_valid \
     && [ "$(nb_lifecycle_field FORMAT)" = nobrand-lifecycle-v2 ] \
     && [ "$(nb_lifecycle_field STATUS)" = in-progress ] \
     && [ "$(nb_lifecycle_field OPERATION)" = configure ] \
     && [ "$(nb_lifecycle_scope)" = ingress ] \
     && [ "$(nb_lifecycle_mutation_started)" = 0 ]; then
    return 0
  fi
  return 1
}

nobrand_recovery_action_refused() {
  local state="$1"
  case "$state" in
    CURRENT_PARTIAL_UNINSTALL)
      warn "$(t \
        '当前完整卸载尚未完成；仅允许安全修复、继续完整卸载或完成待确认的 SSH 管理员验收。' \
        'Full uninstall is incomplete; only safe repair, continued full uninstall, or pending SSH administrator confirmation is allowed.')"
      ;;
    *)
      warn "$(t \
        '当前安装或修复事务尚未完成；仅允许继续安全修复或完成待确认的 SSH 管理员验收。' \
        'An install or repair transaction is incomplete; only safe repair or pending SSH administrator confirmation is allowed.')"
      ;;
  esac
}

nobrand_recovery_scope() {
  local state="${1:-$NOBRAND_INSTALL_STATE}"
  if nb_lifecycle_tx_valid \
     && [ "$(nb_lifecycle_field STATUS)" = in-progress ]; then
    nb_lifecycle_scope
    return $?
  fi
  case "$state" in
    CURRENT_PARTIAL_INSTALL) printf 'manager' ;;
    CURRENT_PARTIAL_REPAIR)
      if declare -F nobrand_backup_restore_transaction_present >/dev/null 2>&1 \
         && nobrand_backup_restore_transaction_present; then
        printf 'global'
      else
        printf 'manager'
      fi
      ;;
    CURRENT_PARTIAL_UNINSTALL) printf 'global' ;;
    *) return 1 ;;
  esac
}

nobrand_set_scoped_recovery_action() {
  local state="${1:-$NOBRAND_INSTALL_STATE}" scope format operation phase mutation_started
  scope="$(nobrand_recovery_scope "$state")" || return 1
  NOBRAND_RECOVERY_EXPECTED_SCOPE="$scope"
  NOBRAND_RECOVERY_EXPECTED_STATE="$state"
  NOBRAND_RECOVERY_EXPECTED_TX_PRESENT=0
  NOBRAND_RECOVERY_EXPECTED_TX_STATUS=""
  NOBRAND_RECOVERY_EXPECTED_TX_ID=""
  NOBRAND_RECOVERY_EXPECTED_TX_RECORD=""
  if [ "$scope" = manager ] && nb_lifecycle_tx_valid; then
    NOBRAND_RECOVERY_EXPECTED_TX_PRESENT=1
    NOBRAND_RECOVERY_EXPECTED_TX_STATUS="$(nb_lifecycle_field STATUS)"
    NOBRAND_RECOVERY_EXPECTED_TX_ID="$(nb_lifecycle_field TRANSACTION_ID)"
    NOBRAND_RECOVERY_EXPECTED_TX_RECORD="$(<"$NOBRAND_LIFECYCLE_TX_FILE")"
  fi
  case "$scope" in
    manager) ACTION=nobrand-manager-bootstrap ;;
    ingress) ACTION=nobrand-ingress-recover ;;
    vless-sudoku) ACTION=nobrand-vless-sudoku; VLESS_SUDOKU_ACTION=install ;;
    ssh-tunnel) ACTION=nobrand-ssh-tunnel; SSH_TUNNEL_ACTION=install ;;
    forward)
      # Forward add parameters are intentionally not copied into lifecycle
      # metadata. Its dedicated route therefore validates committed state or
      # fails closed; it never guesses, recollects, or replays an incomplete add.
      ACTION=nobrand-forward
      FORWARD_ACTION=recover-add
      ;;
    global) ACTION=install ;;
    *) return 1 ;;
  esac
}

nobrand_mark_explicit_protocol_retry() {
  [ -z "${NOBRAND_RECOVERY_EXPECTED_SCOPE:-}" ] || return 0
  case "${ACTION:-}" in
    install) NOBRAND_PROTOCOL_EXPLICIT_RETRY_SCOPE=mieru ;;
    reconfigure) NOBRAND_PROTOCOL_EXPLICIT_RETRY_SCOPE=mieru ;;
    nobrand-snell) [ "${SNELL_ACTION:-}" = install ] && NOBRAND_PROTOCOL_EXPLICIT_RETRY_SCOPE=snell ;;
    nobrand-hy2) [ "${HY2_ACTION:-}" = install ] && NOBRAND_PROTOCOL_EXPLICIT_RETRY_SCOPE=hy2 ;;
    nobrand-tuic) [ "${TUIC_ACTION:-}" = install ] && NOBRAND_PROTOCOL_EXPLICIT_RETRY_SCOPE=tuic ;;
    nobrand-vless-reality)
      [ "${VLESS_REALITY_ACTION:-}" = install ] && NOBRAND_PROTOCOL_EXPLICIT_RETRY_SCOPE=vless-reality
      ;;
    nobrand-vless-sudoku)
      [ "${VLESS_SUDOKU_ACTION:-}" = install ] && NOBRAND_PROTOCOL_EXPLICIT_RETRY_SCOPE=vless-sudoku
      ;;
    nobrand-ssh-tunnel)
      [ "${SSH_TUNNEL_ACTION:-}" = install ] && NOBRAND_PROTOCOL_EXPLICIT_RETRY_SCOPE=ssh-tunnel
      ;;
    nobrand-forward)
      [ "${FORWARD_ACTION:-}" = add ] && NOBRAND_PROTOCOL_EXPLICIT_RETRY_SCOPE=forward
      ;;
    nobrand-ingress)
      case "${INGRESS_ACTION:-}" in
        add|modify|delete|set-default|unset-default|apply)
          NOBRAND_PROTOCOL_EXPLICIT_RETRY_SCOPE=ingress
          ;;
      esac
      ;;
  esac
  return 0
}

nb_select_partial_recovery_action() {
  local state="${1:-$NOBRAND_INSTALL_STATE}" choice=""
  case "$state" in
    CURRENT_PARTIAL_INSTALL|CURRENT_PARTIAL_REPAIR|CURRENT_PARTIAL_CONFIGURE)
      t '检测到未完成的安装或修复。请选择恢复操作：' \
        'An incomplete install or repair was detected. Choose a recovery action:'
      t '  1) 继续安全修复（默认）' '  1) Continue safe repair (default)'
      t '  0) 退出，不做更改' '  0) Exit without changes'
      if [ "${YES:-0}" -eq 1 ]; then
        choice=1
      else
        read_tty choice "$(t '请选择 [0-1]: ' 'Choose [0-1]: ')" || {
          warn "$(t '无法读取恢复选择；未进行任何更改。' \
            'Unable to read a recovery choice; no changes were made.')"
          return 1
        }
      fi
      case "${choice:-1}" in
        1) nobrand_set_scoped_recovery_action "$state" ;;
        0) return 2 ;;
        *) warn "$(t '无效恢复选择' 'Invalid recovery choice')"; return 1 ;;
      esac
      ;;
    CURRENT_PARTIAL_UNINSTALL)
      t '检测到未完成的完整卸载。请选择恢复操作：' \
        'An incomplete full uninstall was detected. Choose a recovery action:'
      t '  1) 安全修复安装（默认；仅恢复仍有权威状态的资源）' \
        '  1) Repair safely (default; restore only resources with authoritative state)'
      t '  2) 继续清理 NoBrand 管理的剩余资源' \
        '  2) Continue cleaning remaining NoBrand-managed resources'
      t '  0) 退出，不做更改' '  0) Exit without changes'
      if [ "${YES:-0}" -eq 1 ]; then
        choice=1
      else
        read_tty choice "$(t '请选择 [0-2]: ' 'Choose [0-2]: ')" || {
          warn "$(t '无法读取恢复选择；未进行任何更改。' \
            'Unable to read a recovery choice; no changes were made.')"
          return 1
        }
      fi
      case "${choice:-1}" in
        1) nobrand_set_scoped_recovery_action "$state" ;;
        2)
          t '[提示] 将继续清理由 NoBrand 管理的剩余资源。' \
            '[Info] Cleanup of remaining NoBrand-managed resources will continue.'
          ACTION=nobrand-uninstall
          ;;
        0) return 2 ;;
        *) warn "$(t '无效恢复选择' 'Invalid recovery choice')"; return 1 ;;
      esac
      ;;
  esac
}

nobrand_action_opens_interactive_menu() {
  case "${ACTION:-}" in
    menu|nobrand-mieru-menu|user-manage) return 0 ;;
    nobrand-snell) [ "${SNELL_ACTION:-menu}" = menu ] ;;
    nobrand-hy2) [ "${HY2_ACTION:-menu}" = menu ] ;;
    nobrand-vless-sudoku) [ "${VLESS_SUDOKU_ACTION:-menu}" = menu ] ;;
    nobrand-forward) [ "${FORWARD_ACTION:-}" = menu ] ;;
    *) return 1 ;;
  esac
}

main() {
  local main_lifecycle_lock=0 main_rc=0 recovery_rc=0 dispatch_rc=0
  local NOBRAND_MANAGER_SESSION_ACTIVE=1
  local NOBRAND_PROTOCOL_EXPLICIT_RETRY_SCOPE=""
  nb_lifecycle_signal_handlers_install
  nobrand_mark_explicit_protocol_retry
  # Help/version are intentionally state-independent. Every other root action
  # detects legacy/unknown state before it can read or mutate protocol data.
  case "${ACTION:-menu}" in
    nobrand-version) nobrand_version; return 0 ;;
    nobrand-help) nobrand_usage; return 0 ;;
  esac
  nb_splicore_legacy_preflight || return 1
  # The primary runtime has its own persistent generation transaction and uses
  # the same lifecycle lock. Route before any legacy repair/download branch.
  if nobrand_ssh_confirmation_pending; then
    case "${ACTION:-}" in
      nobrand-runtime|nobrand-snell|nobrand-tuic|nobrand-hy2|nobrand-vless-reality|install|upgrade|reconfigure)
        nobrand_pending_ssh_confirmation_notice
        return 1
        ;;
    esac
  fi
  local runtime_rc=0
  nb_splicore_route_main || runtime_rc=$?
  if [ "${NOBRAND_SPLICORE_HANDLED:-0}" -eq 1 ]; then
    return "$runtime_rc"
  fi
  # Explicit protocol commands may dispatch mutations directly, so retain the
  # process lock across their common state boundary and dispatcher. A no-arg
  # manager launch is different: bootstrap must install dependencies (including
  # flock) before acquiring its transaction lock. The full menu takes the outer
  # guard only after that bootstrap succeeds.
  if [ "${DRY_RUN:-0}" -ne 1 ] \
     && [ -n "${ACTION:-}" ] \
     && [ "${ACTION:-}" != nobrand-manager-upgrade ] \
     && [ "$(id -u 2>/dev/null || echo 1)" -eq 0 ]; then
    nb_lifecycle_lock_acquire || return 1
    main_lifecycle_lock=1
  fi
  if nb_splicore_installed && [ -z "$ACTION" ] && ! nobrand_manager_installation_valid; then
    nobrand_install_manager_script || return 1
  fi
  nb_validate_authoritative_state_boundary
  case "$NOBRAND_INSTALL_STATE" in
    CURRENT_PARTIAL_INSTALL|CURRENT_PARTIAL_REPAIR|CURRENT_PARTIAL_CONFIGURE|\
      CURRENT_PARTIAL_UNINSTALL)
      nb_install_state_notice "$NOBRAND_INSTALL_STATE"
      ;;
    CURRENT_COMPLETE)
      [ "${ACTION:-menu}" != install ] || nb_install_state_notice "$NOBRAND_INSTALL_STATE"
      ;;
  esac
  # A live SSH rollback watchdog must be confirmed or allowed to roll back
  # before any recovery choice or explicit command can mutate lifecycle state.
  if nobrand_ssh_confirmation_pending; then
    if [ -z "$ACTION" ]; then
      nobrand_pending_ssh_confirmation_notice
      [ "$main_lifecycle_lock" -eq 0 ] || nb_lifecycle_lock_release
      return 0
    fi
    if ! nobrand_action_is_ssh_confirmation; then
      nobrand_pending_ssh_confirmation_notice
      [ "$main_lifecycle_lock" -eq 0 ] || nb_lifecycle_lock_release
      return 1
    fi
  fi
  case "$NOBRAND_INSTALL_STATE" in
    CURRENT_PARTIAL_INSTALL|CURRENT_PARTIAL_REPAIR|CURRENT_PARTIAL_CONFIGURE|\
      CURRENT_PARTIAL_UNINSTALL)
      if ! nobrand_recovery_action_allowed "$NOBRAND_INSTALL_STATE" "$ACTION"; then
        nobrand_recovery_action_refused "$NOBRAND_INSTALL_STATE"
        [ "$main_lifecycle_lock" -eq 0 ] || nb_lifecycle_lock_release
        return 1
      fi
      ;;
  esac
  if [ -z "$ACTION" ]; then
    case "$NOBRAND_INSTALL_STATE" in
      CURRENT_PARTIAL_INSTALL|CURRENT_PARTIAL_REPAIR|CURRENT_PARTIAL_CONFIGURE|\
        CURRENT_PARTIAL_UNINSTALL)
        nb_select_partial_recovery_action "$NOBRAND_INSTALL_STATE" || {
          recovery_rc=$?
          [ "$main_lifecycle_lock" -eq 0 ] || nb_lifecycle_lock_release
          [ "$recovery_rc" -eq 2 ] && return 0
          return "$recovery_rc"
        }
        ;;
    esac
  fi
  if [ "$main_lifecycle_lock" -eq 1 ] \
     && [ "${DRY_RUN:-0}" -ne 1 ] \
     && [ "$(id -u 2>/dev/null || echo 1)" -eq 0 ]; then
    ensure_manager_state_layout 0
  fi
  case "$ACTION" in
    nobrand-manager-bootstrap)
      nobrand_manager_bootstrap || {
        main_rc=$?
        [ "$main_lifecycle_lock" -eq 0 ] || nb_lifecycle_lock_release
        return "$main_rc"
      }
      ACTION=""
      NOBRAND_RECOVERY_EXPECTED_SCOPE=""
      ;;
    nobrand-ingress-recover)
      nobrand_recover_ingress_scope || {
        main_rc=$?
        [ "$main_lifecycle_lock" -eq 0 ] || nb_lifecycle_lock_release
        return "$main_rc"
      }
      ACTION=""
      NOBRAND_RECOVERY_EXPECTED_SCOPE=""
      ;;
  esac
  if [ -z "$ACTION" ]; then
    nobrand_manager_bootstrap || {
      main_rc=$?
      [ "$main_lifecycle_lock" -eq 0 ] || nb_lifecycle_lock_release
      return "$main_rc"
    }
    if [ "$main_lifecycle_lock" -eq 0 ] \
       && [ "${DRY_RUN:-0}" -ne 1 ] \
       && [ "$(id -u 2>/dev/null || echo 1)" -eq 0 ]; then
      nb_lifecycle_lock_acquire || return 1
      main_lifecycle_lock=1
    fi
    NOBRAND_INSTALL_STATE="$(nb_classify_installation_state)" || {
      [ "$main_lifecycle_lock" -eq 0 ] || nb_lifecycle_lock_release
      return 1
    }
    [ "$NOBRAND_INSTALL_STATE" = CURRENT_COMPLETE ] || {
      nb_fail_ambiguous_state
      [ "$main_lifecycle_lock" -eq 0 ] || nb_lifecycle_lock_release
      return 1
    }
    NOBRAND_MENU_EXPECTED_STATE="$NOBRAND_INSTALL_STATE"
    if [ "$main_lifecycle_lock" -eq 1 ]; then
      nb_lifecycle_lock_release
      main_lifecycle_lock=0
    fi
    nobrand_menu_loop
    main_rc=$?
    [ "$main_lifecycle_lock" -eq 0 ] || nb_lifecycle_lock_release
    return "$main_rc"
  fi
  if [ "$ACTION" != "menu" ] && [[ "$ACTION" != nobrand-* ]]; then
    print_banner
  fi
  if dry_run_should_preview "$ACTION"; then
    dry_run_action_preview "$ACTION"
    [ "$main_lifecycle_lock" -eq 0 ] || nb_lifecycle_lock_release
    return 0
  fi
  # Legacy runtime recovery belongs to explicit restore/recovery operations.
  if [ "$main_lifecycle_lock" -eq 1 ] && nobrand_action_opens_interactive_menu; then
    NOBRAND_MENU_EXPECTED_STATE="$NOBRAND_INSTALL_STATE"
    nb_lifecycle_lock_release
    main_lifecycle_lock=0
  fi
  case "$ACTION" in
    user-manage) do_user_manage ;;
    perf) do_perf ;;
    bbr-config) do_bbr_config ;;
    nobrand-status) nobrand_status ;;
    nobrand-nodes) nobrand_nodes ;;
    nobrand-doctor) nobrand_doctor ;;
    nobrand-backup) nobrand_backup_action ;;
    nobrand-uninstall) nobrand_uninstall ;;
    nobrand-manager-upgrade) nobrand_manager_upgrade ;;
    nobrand-network) do_perf ;;
    nobrand-snell) nobrand_run_snell_action ;;
    nobrand-hy2) nobrand_run_hy2_action ;;
    nobrand-vless-sudoku) nobrand_run_vless_sudoku_action ;;
    nobrand-vless-reality) nobrand_run_vless_reality_action ;;
    nobrand-tuic) nobrand_run_tuic_action ;;
    nobrand-ssh-tunnel) nobrand_run_ssh_tunnel_action ;;
    nobrand-forward) nobrand_run_forward_action ;;
    nobrand-ingress) nobrand_run_ingress_action ;;
    nobrand-mieru-menu) menu_loop ;;
    help) usage ;;
    menu)
      menu_loop
      ;;
    *) usage; main_rc=1 ;;
  esac
  dispatch_rc=$?
  [ "$main_rc" -ne 0 ] || main_rc="$dispatch_rc"
  [ "$main_lifecycle_lock" -eq 0 ] || nb_lifecycle_lock_release
  return "$main_rc"
}

# 允许被 source 做单测（设置 MITA_SOURCE_ONLY=1）
if [ "${MITA_SOURCE_ONLY:-0}" != "1" ]; then
  main
fi
