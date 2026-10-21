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

    def certificate(self, name, sni):
        self.refuse_legacy()
        require(re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9.-]{0,252}", sni), "CONFIG_INVALID", "invalid TLS SNI")
        parent = self.config / "splicore/tls"
        parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        target = parent / identifier(name)
        require(not target.exists(), "CONFIG_INVALID", "certificate directory already exists; explicit certificate reuse required")
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
                require(not preview, "CONFIG_INVALID", "fresh HY2 preview requires a supplied canonical file with TLS paths")
                tls = self.certificate(name, env.get("HY2_SNI") or "bing.com")
                created_tls = Path(tls["certificate_file"]).parent
                document.update({"settings": {"tls": tls,
                                               "stream_transport": {"kind": "hysteria", "hysteria": {"version": 2,
                                                   "obfs": {"type": "salamander", "password": uuid.uuid4().hex}}}},
                                 "users": [{"password": uuid.uuid4().hex}]})
                node["options"] = {"obfs": "salamander"}
            else:
                require(protocol == "tuic", "CAPABILITY_UNSUPPORTED", "unsupported protocol")
                require(not preview, "CONFIG_INVALID", "fresh TUIC preview requires a supplied canonical file with TLS paths")
                document.update({"settings": {"version": 5, "congestion_control": "cubic", "udp_relay_mode": "native",
                                               "zero_rtt_handshake": False, "tls": self.certificate(name, env.get("TUIC_SNI") or "www.microsoft.com")},
                                 "users": [{"uuid": str(uuid.uuid4()), "password": uuid.uuid4().hex}]})
                created_tls = Path(document["settings"]["tls"]["certificate_file"]).parent
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
                tls = self.config / "splicore/tls"
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
