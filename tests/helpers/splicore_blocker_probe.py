#!/usr/bin/env python3
"""Public rc.2 coverage evidence; no host service or production access.

Positive native controls are deliberately separate from legacy migration.
This probe must never label expected incompatibility as blocker closure.
"""
import argparse
import base64
import copy
import gzip
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import tarfile
import tempfile
import threading
import time
from unittest.mock import patch

import splicore_rc2_probe as contract
from splicore_local_integration import sc

ROOT = Path(__file__).resolve().parents[2]
IDENT = "r0123456789abcdef"
UUID = "11111111-1111-4111-8111-111111111111"
# Same official client asset and digest as test_vless_reality_runtime.sh.
MIHOMO_SHA256 = "cf06ce2c7d1421bdbda14ee4a5b6046672dc35ebf8eecd8e77504ec3c0ed9a84"


def keypair(work):
    pem = work / "synthetic-x25519.pem"
    contract.run(["openssl", "genpkey", "-algorithm", "X25519", "-out", pem])
    private = subprocess.run(["openssl", "pkey", "-in", str(pem), "-outform", "DER"],
                             capture_output=True, check=True, timeout=10).stdout[-32:]
    public = subprocess.run(["openssl", "pkey", "-in", str(pem), "-pubout", "-outform", "DER"],
                            capture_output=True, check=True, timeout=10).stdout[-32:]
    return tuple(base64.urlsafe_b64encode(v).decode().rstrip("=") for v in (private, public))


def legacy_fixture(root, private, public, reality_port=31241, hy2_port=31242,
                   target_port=31443, tls=None):
    """Call the actual existing NoBrand state/config/client generators."""
    environment = dict(os.environ, NOBRAND_STATE_DIR=str(root / "state"),
                       NOBRAND_CONFIG_DIR=str(root / "config"), NOBRAND_LIB_DIR=str(root / "lib"),
                       NOBRAND_LIFECYCLE_DIR=str(root / "journal"),
                       NOBRAND_LIFECYCLE_LOCK_FILE=str(root / "guard"),
                       BLOCKER_ROOT=str(root), BLOCKER_INSTALLER=str(ROOT / "install-nobrand.sh"),
                       BLOCKER_PRIVATE=private, BLOCKER_PUBLIC=public, BLOCKER_UUID=UUID,
                       BLOCKER_REALITY_PORT=str(reality_port), BLOCKER_HY2_PORT=str(hy2_port),
                       BLOCKER_TARGET_PORT=str(target_port), MITA_SOURCE_ONLY="1")
    if tls:
        environment.update(BLOCKER_CERT=tls["certificate_file"], BLOCKER_KEY=tls["private_key_file"])
    script = r'''
set -euo pipefail
source "$BLOCKER_INSTALLER"
trap 'printf "BLOCKER_FIXTURE_LINE=%s\n" "$LINENO" >&2' ERR
nb_init_state_layout
id=r0123456789abcdef
mkdir -p "$(reality_instance_config_dir "$id")" "$(dirname "$(reality_state_file "$id")")"
printf '%s' "$BLOCKER_PRIVATE" >"$(reality_private_key_file "$id")"
chmod 600 "$(reality_private_key_file "$id")"
reality_generate_server_config "$(reality_config_file "$id")" "$id" 127.0.0.1 \
  "$BLOCKER_REALITY_PORT" "$BLOCKER_UUID" "$BLOCKER_PRIVATE" 0123456789abcdef \
  probe.example "$BLOCKER_TARGET_PORT" 39999
# Only the ingress recommendation lookup is stubbed; all protocol generators
# and client exporters below are the real existing NoBrand functions.
reality_profile_recommendation() { printf recommended; }
reality_generate_state "$(reality_state_file "$id")" "$id" synthetic 127.0.0.1 \
  "$BLOCKER_REALITY_PORT" custom 127.0.0.1 "$BLOCKER_REALITY_PORT" "$BLOCKER_UUID" \
  "$BLOCKER_PUBLIC" "$(reality_private_key_file "$id")" 0123456789abcdef probe.example \
  "$BLOCKER_TARGET_PORT" chrome / 26.3.27 fixture 39999
reality_export_xray "$id" >"$BLOCKER_ROOT/legacy-reality-client.json"
reality_export_mihomo "$id" >"$BLOCKER_ROOT/legacy-reality-client.yaml"
mkdir -p "$NOBRAND_HY2_CONFIG_DIR" "$NOBRAND_HY2_STATE_DIR"
if [ -z "${BLOCKER_CERT:-}" ]; then
  HY2_SNI=probe.example
  generate_hysteria2_cert
else
  NOBRAND_HY2_CERT_FILE="$BLOCKER_CERT"
  NOBRAND_HY2_KEY_FILE="$BLOCKER_KEY"
fi
hysteria2_generate_config "$NOBRAND_HY2_CONFIG_FILE" 127.0.0.1 "$BLOCKER_HY2_PORT" \
  synthetic-hy2-auth probe.example synthetic-salamander-secret
hysteria2_generate_state "$NOBRAND_HY2_STATE_FILE" 127.0.0.1 "$BLOCKER_HY2_PORT" \
  synthetic-hy2-auth probe.example synthetic-salamander-secret custom 127.0.0.1 "$BLOCKER_HY2_PORT"
hysteria2_export_singbox >"$BLOCKER_ROOT/legacy-hy2-client.json"
hysteria2_export_mihomo >"$BLOCKER_ROOT/legacy-hy2-client.yaml"
'''
    result = subprocess.run(["bash", "-c", script], env=environment, capture_output=True, timeout=30)
    if result.returncode:
        lines = result.stderr.decode(errors="replace").splitlines()
        location = next((line.partition("=")[2] for line in reversed(lines)
                         if line.startswith("BLOCKER_FIXTURE_LINE=") and line.partition("=")[2].isdigit()), "unknown")
        raise contract.Rejected("LEGACY_FIXTURE: actual NoBrand generators failed at fixture line " + location)
    return {"reality": root / "state/vless-reality/instances" / IDENT / "state.json",
            "hy2": root / "state/hysteria2/state.json"}


def stop(process):
    if process is not None and process.poll() is None:
        process.terminate()
        try:
            process.wait(timeout=8)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=5)


def wait_port(process, port):
    deadline = time.monotonic() + 10
    while time.monotonic() < deadline and process.poll() is None:
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.2):
                return
        except OSError:
            time.sleep(0.05)
    raise contract.Rejected("RUNTIME: isolated listener did not start")


def probe(artifacts, mihomo_gzip):
    if sys.platform != "linux" or contract.architecture(os.uname().machine) != "amd64":
        raise contract.Rejected("ARCH_UNSUPPORTED: this runtime probe requires Linux amd64")
    manifest = sc.RELEASE["rollback_releases"]["v0.3.0-rc.2"]
    entry = manifest["assets"]["amd64"]
    archive = artifacts / entry["name"]
    contract.verify_archive(archive, (artifacts / "SHA256SUMS").read_text(), entry)
    if hashlib.sha256(mihomo_gzip.read_bytes()).hexdigest() != MIHOMO_SHA256:
        raise contract.Rejected("CHECKSUM_MISMATCH: existing official client fixture")
    evidence = {"version": manifest["version"], "commit": manifest["commit"],
                "archive_sha256": entry["sha256"], "binary_sha256": entry["binary_sha256"],
                "client": "official Mihomo v1.19.30; same pin as existing REALITY fixture",
                "checks": {}, "migration_blockers_closed": False,
                "external_qualification": "PENDING; not exercised"}
    checks = evidence["checks"]
    with tempfile.TemporaryDirectory(prefix="nb-bc-") as directory:
        work = Path(directory)
        work.chmod(0o700)
        binary, client = work / "splicore", work / "mihomo"
        with tarfile.open(archive, "r:gz") as bundle:
            binary.write_bytes(bundle.extractfile("splicore").read())
        if hashlib.sha256(binary.read_bytes()).hexdigest() != entry["binary_sha256"]:
            raise contract.Rejected("BINARY_IDENTITY: binary digest differs before execution")
        binary.chmod(0o700)
        identity = json.loads(contract.run([binary, "version", "--json"]))
        if any(identity.get(k) != v for k, v in {"product": "Splicore", "version": manifest["version"],
                "commit": manifest["commit"], "platform": "linux/amd64", "dirty": False}.items()):
            raise contract.Rejected("BINARY_IDENTITY: exact public identity differs")
        checks["public_binary_identity"] = "PASS"
        with gzip.open(mihomo_gzip, "rb") as source:
            client.write_bytes(source.read())
        client.chmod(0o700)
        environment = {"NOBRAND_STATE_DIR": str(work / "native-owner-state"), "NOBRAND_CONFIG_DIR": str(work / "native-config"),
                       "NOBRAND_LIB_DIR": str(work / "native-lib"), "NOBRAND_LIFECYCLE_DIR": str(work / "native-journal"),
                       "NOBRAND_LIFECYCLE_LOCK_FILE": str(work / "guard")}
        with patch.dict(os.environ, environment):
            runtime = sc.Runtime(adapter="process")
            tls = runtime.certificate("synthetic-control", "probe.example")
        private, public = keypair(work)
        rp, hp, tp = [contract.vacant_port(socket.SOCK_STREAM) for _ in range(3)]
        while len({rp, hp, tp}) != 3:
            rp, hp, tp = [contract.vacant_port(socket.SOCK_STREAM) for _ in range(3)]
        hp = contract.vacant_port(socket.SOCK_DGRAM)
        legacy = legacy_fixture(work, private, public, rp, hp, tp, tls)
        old = json.loads(legacy["reality"].read_text())
        reality = {"schema": 1, "name": "native-reality-control", "listener": {"host": "127.0.0.1", "port": rp},
                   "display_endpoint": {"host": "127.0.0.1", "port": rp},
                   "settings": {"security": "reality", "flow": "none", "transport": "tcp", "packet_encoding": "xudp",
                                "reality": {"public_key": old["public_key"], "short_ids": [old["short_id"]],
                                            "server_name": old["server_name"], "target": {"host": "127.0.0.1", "port": tp}}},
                   "server_secret": {"private_key": private}, "users": [{"account_name": "native-control", "uuid": old["uuid"]}]}
        hy2 = {"schema": 1, "name": "native-hy2-control", "listener": {"host": "127.0.0.1", "port": hp},
               "display_endpoint": {"host": "127.0.0.1", "port": hp}, "settings": {"tls": tls},
               "users": [{"account_name": "native-hy2-control", "password": "synthetic-hy2-auth"}]}
        documents = [("vless", reality), ("hysteria2", hy2)]
        for protocol in ("snell", "mieru", "tuic"):
            kind = socket.SOCK_DGRAM if protocol == "tuic" else socket.SOCK_STREAM
            port = contract.vacant_port(kind)
            while port in {rp, hp, tp} | {d["listener"]["port"] for _, d in documents}:
                port = contract.vacant_port(kind)
            doc = {"schema": 1, "name": "representative-" + protocol,
                   "listener": {"host": "127.0.0.1", "port": port},
                   "display_endpoint": {"host": "127.0.0.1", "port": port}}
            if protocol == "snell":
                doc.update(settings={"version": 5}, psk="synthetic-representative-psk", account_name="representative-snell")
            else:
                doc["users"] = [{"account_name": "representative-" + protocol, "password": "synthetic-representative-password"}]
                if protocol == "mieru":
                    doc["users"][0]["username"] = "synthetic-representative-user"
                    doc["settings"] = {"transport": "tcp", "mtu": 1400, "multiplex": "off"}
                else:
                    doc["users"][0]["uuid"] = UUID
                    doc["settings"] = {"tls": tls, "version": 5, "congestion_control": "cubic",
                                       "udp_relay_mode": "native", "zero_rtt_handshake": False}
            documents.append((protocol, doc))

        def validate(label, protocol, document, accepted):
            path = work / "validate.json"
            contract.write_json(path, document)
            contract.run([binary, "inbound", "validate", "--protocol", protocol, "--file", path], accepted)
            checks[label] = "ACCEPTED" if accepted else "REJECTED"

        validate("reality_flow_none", "vless", reality, True)
        vision = copy.deepcopy(reality)
        vision["settings"]["flow"] = "xtls-rprx-vision"
        validate("public_vision_contract_only_not_nobrand_acceptance", "vless", vision, True)
        for label, mutate in (
            ("reality_invalid_private_key", lambda d: d["server_secret"].update(private_key="invalid")),
            ("reality_missing_private_key_with_public", lambda d: d.pop("server_secret")),
            ("reality_invalid_short_id", lambda d: d["settings"]["reality"].update(short_ids=["xyz"])),
            ("reality_missing_server_name", lambda d: d["settings"]["reality"].pop("server_name")),
            ("reality_bad_destination", lambda d: d["settings"]["reality"].update(target={"host": "", "port": 0})),
            ("reality_malformed_uuid", lambda d: d["users"][0].update(uuid="malformed")),
            ("reality_unknown_security_field", lambda d: d["settings"].update(defender={"enabled": True})),
            ("reality_legacy_routing", lambda d: d.update(routing={"rules": []})),
            ("reality_min_client_ver", lambda d: d["settings"]["reality"].update(min_client_ver="1.8.0")),
        ):
            doc = copy.deepcopy(reality)
            mutate(doc)
            validate(label, "vless", doc, False)
        missing = copy.deepcopy(reality)
        missing.pop("server_secret")
        missing["settings"]["reality"].pop("public_key")
        validate("reality_missing_both_keys_fresh_generation_contract", "vless", missing, True)
        validate("plain_hy2_control", "hysteria2", hy2, True)
        for label, location in (("hy2_salamander_settings", "settings"), ("hy2_salamander_transport", "transport")):
            doc = copy.deepcopy(hy2)
            obfs = {"type": "salamander", "password": "synthetic-salamander-secret"}
            if location == "settings":
                doc["settings"]["obfs"] = obfs
            else:
                doc["settings"]["stream_transport"] = {"kind": "hysteria", "hysteria": {"version": 2, "obfs": obfs}}
            validate(label, "hysteria2", doc, False)
        state = work / "native-state"
        state.mkdir(mode=0o700)
        bootstrap = work / "bootstrap.yaml"
        bootstrap.write_text(f"schema: 1\nstate_directory: {state}\nkey_file: {state}/master.key\napi:\n  unix_socket: {work}/control.sock\n")
        (work / "launch.py").write_text(sc.LAUNCHER)
        contract.run([binary, "key", "init", "--file", state / "master.key"])
        processes = []
        daemon = None
        with (work / "private-runtime.log").open("w") as log:
            try:
                target = subprocess.Popen(["openssl", "s_server", "-accept", f"127.0.0.1:{tp}", "-cert", tls["certificate_file"],
                                           "-key", tls["private_key_file"], "-tls1_3", "-quiet", "-www"], stdout=log, stderr=log)
                processes.append(target)
                wait_port(target, tp)

                def start_daemon():
                    process = subprocess.Popen([sys.executable, str(work / "launch.py")], stdout=log, stderr=log)
                    processes.append(process)
                    deadline = time.monotonic() + 10
                    while time.monotonic() < deadline and process.poll() is None:
                        result = subprocess.run([str(binary), "inbound", "list", "--config", str(bootstrap)],
                                                capture_output=True, timeout=5)
                        if result.returncode == 0:
                            return process
                        time.sleep(0.05)
                    raise contract.Rejected("RUNTIME: isolated control socket did not become ready")

                daemon = start_daemon()
                for protocol, doc in documents:
                    path, plan = work / "document.json", work / "plan.json"
                    contract.write_json(path, doc)
                    contract.write_json(plan, json.loads(contract.run([binary, "inbound", "plan", "--protocol", protocol,
                                                                      "--config", bootstrap, "--file", path])))
                    contract.run([binary, "inbound", "apply", "--protocol", protocol, "--config", bootstrap, "--file", path, "--plan", plan])

                baseline = json.loads(contract.run([binary, "inbound", "list", "--config", bootstrap]))
                for protocol, doc in documents[:2]:
                    conflict = copy.deepcopy(doc)
                    conflict["name"] += "-conflict"
                    conflict["users"][0]["account_name"] += "-conflict"
                    path, plan = work / "conflict.json", work / "conflict-plan.json"
                    contract.write_json(path, conflict)
                    planned = subprocess.run([str(binary), "inbound", "plan", "--protocol", protocol, "--config", str(bootstrap), "--file", str(path)],
                                             capture_output=True, timeout=10)
                    stage = "plan"
                    if planned.returncode == 0:
                        stage = "apply"
                        contract.write_json(plan, json.loads(planned.stdout))
                        contract.run([binary, "inbound", "apply", "--protocol", protocol, "--config", bootstrap,
                                      "--file", path, "--plan", plan], False, "port_conflict")
                    elif b"port_conflict" not in planned.stderr:
                        raise contract.Rejected("PORT_CONFLICT: candidate rejected for a different reason")
                    current = json.loads(contract.run([binary, "inbound", "list", "--config", bootstrap]))
                    # Runtime readings may include statistics. Compare resource
                    # IDs and health rather than counters or timestamps.
                    def graph_identity(page):
                        return sorted((item["inbound"]["id"], item["health"]) for item in page["items"])
                    if graph_identity(current) != graph_identity(baseline):
                        raise contract.Rejected("PORT_CONFLICT: rejected candidate changed the live graph")
                    checks[protocol + "_port_conflict"] = "REJECTED at " + stage + "; live graph unchanged"

                class Handler(BaseHTTPRequestHandler):
                    def do_GET(self):
                        self.send_response(200)
                        self.end_headers()
                        self.wfile.write(b"synthetic-blocker-control")

                    def log_message(self, *_args):
                        pass

                httpd = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
                thread = threading.Thread(target=httpd.serve_forever, daemon=True)
                thread.start()
                try:
                    def traffic(label, profile, success):
                        client_port = contract.vacant_port(socket.SOCK_STREAM)
                        folder = work / label
                        folder.mkdir(mode=0o700)
                        config = folder / "config.yaml"
                        config.write_text(profile.replace("mixed-port: 7890", f"mixed-port: {client_port}"))
                        proc = subprocess.Popen([str(client), "-d", str(folder), "-f", str(config)], stdout=log, stderr=log)
                        processes.append(proc)
                        try:
                            wait_port(proc, client_port)
                            result = subprocess.run(["curl", "--silent", "--show-error", "--noproxy", "", "--max-time", "7",
                                                     "--proxy", f"http://127.0.0.1:{client_port}", f"http://127.0.0.1:{httpd.server_port}/"],
                                                    capture_output=True, timeout=10)
                            passed = result.returncode == 0 and result.stdout == b"synthetic-blocker-control"
                            if passed != success:
                                raise contract.Rejected("TRAFFIC: unexpected outcome for " + label)
                            checks[label] = "PAYLOAD PASS" if passed else "NO PAYLOAD (expected incompatibility)"
                        finally:
                            stop(proc)

                    original_reality = (work / "legacy-reality-client.yaml").read_text()
                    # An explicitly separate native control. Never persist this
                    # change to legacy state, or call it old-profile compatibility.
                    native_reality = original_reality.replace("flow: xtls-rprx-vision", 'flow: ""')
                    fragment = (work / "legacy-hy2-client.yaml").read_text()
                    original_hy2 = ("mixed-port: 7890\nallow-lan: false\nmode: rule\nlog-level: warning\nproxies:\n" +
                                    "\n".join("  " + line for line in fragment.splitlines()) +
                                    "\nproxy-groups:\n  - name: NOBRAND\n    type: select\n    proxies: [NoBrand-Hysteria2]\nrules:\n  - MATCH,NOBRAND\n")
                    native_hy2 = "\n".join(line for line in original_hy2.splitlines()
                                            if "obfs:" not in line and "obfs-password:" not in line) + "\n"
                    traffic("native_reality_flow_none_control", native_reality, True)
                    traffic("unchanged_legacy_vision_to_flow_none", original_reality, False)
                    traffic("native_plain_hy2_control", native_hy2, True)
                    traffic("unchanged_legacy_salamander_to_plain", original_hy2, False)
                    checks["private_destination_security_parity"] = "FAIL: native REALITY control relayed to loopback; legacy policy denies private IP"
                    for action in ("restart", "sigkill_recovery"):
                        if action == "restart":
                            stop(daemon)
                        else:
                            daemon.kill()
                            daemon.wait(timeout=5)
                        daemon = start_daemon()
                        traffic(action + "_native_reality", native_reality, True)
                        traffic(action + "_plain_hy2", native_hy2, True)
                    items = json.loads(contract.run([binary, "inbound", "list", "--config", bootstrap]))["items"]
                    if len(items) != len(documents) or any(item["health"] != "healthy" for item in items):
                        raise contract.Rejected("RUNTIME: native control graph differs")
                    checks["single_splicore_process_five_inbounds"] = "PASS: REALITY flow-none, plain HY2, Snell v5, Mieru TCP, TUIC v5; no Salamander"
                finally:
                    httpd.shutdown()
                    httpd.server_close()
                    thread.join(timeout=5)
            finally:
                for process in reversed(processes):
                    stop(process)
        checks["owned_processes_stopped"] = all(p.poll() is not None for p in processes)
    checks["private_temporary_directory_removed"] = not work.exists()
    return evidence


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--artifacts", required=True, type=Path)
    parser.add_argument("--mihomo-gzip", required=True, type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    os.umask(0o077)
    try:
        result = probe(args.artifacts.resolve(), args.mihomo_gzip.resolve())
    except (contract.Rejected, OSError, ValueError, subprocess.SubprocessError, tarfile.TarError) as exc:
        # No subprocess output, documents, credentials, or command arguments.
        detail = str(exc) if isinstance(exc, contract.Rejected) else "external operation failed"
        print(json.dumps({"probe": "FAIL", "detail": detail, "migration_blockers_closed": False}))
        return 1
    if args.output:
        contract.write_json(args.output, result)
    print(json.dumps(result, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
