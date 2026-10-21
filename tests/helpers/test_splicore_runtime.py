#!/usr/bin/env python3
"""Isolated state-machine tests; the service driver never calls a host supervisor."""
import copy
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import hashlib
import io
import struct
import tarfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("splicore_runtime", ROOT / "runtime/splicore.py")
sc = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sc)

FAKE_BINARY = '''#!/usr/bin/env python3
import json,sys,pathlib
args=sys.argv[1:]
if args[:2]==["key","init"]:
    pathlib.Path(args[args.index("--file")+1]).write_bytes(b"synthetic-master-key")
elif args[:2]==["inbound","validate"]:
    doc=json.loads(pathlib.Path(args[args.index("--file")+1]).read_text())
    if doc.get("settings",{}).get("mtu")==999: sys.exit(1)
elif args[:2]==["version","--json"]:
    print(json.dumps(IDENTITY))
elif args[:2]==["inbound","list"]:
    graph=json.loads(pathlib.Path(__file__).with_name("desired.json").read_text())
    print(json.dumps({"items":[{"inbound":{"id":n["id"],"name":"nb-"+n["id"],"listeners":[{"endpoint":n["document"]["listener"]}]},"health":"healthy"} for n in graph["nodes"] if n.get("enabled",True)]}))
'''

DRIVER = '''#!/usr/bin/env python3
import json,os,pathlib,stat,sys
action,name,generation=sys.argv[1:]
root=pathlib.Path(os.environ["SC_FIXTURE_ROOT"])
state=root/"services.json"
d=json.loads(state.read_text()) if state.exists() else {}
item=d.setdefault(name,{"active":False,"enabled":False})
with (root/"service-events").open("a") as out: out.write(action+" "+name+"\\n")
if action in ("active","enabled"): sys.exit(0 if item[action] else 1)
if action=="start":
    if (root/"fail-start").exists():
        (root/"fail-start").unlink(); sys.exit(1)
    item["active"]=True
elif action=="stop":
    item["active"]=False
    control=pathlib.Path(generation)/"control.sock"
    if control.exists() and stat.S_ISSOCK(control.lstat().st_mode): control.unlink()
elif action=="enable": item["enabled"]=True
elif action=="disable": item["enabled"]=False
elif action=="verify":
    if (root/"fail-health").exists():
        (root/"fail-health").unlink(); sys.exit(1)
state.write_text(json.dumps(d))
'''


def desired(port=31231, ident="primary"):
    return dict(sc.empty(), nodes=[{"id": ident, "protocol": "snell", "enabled": True,
                                   "document": {"schema": 1, "psk": "synthetic-fixed-psk",
                                                "listener": {"host": "127.0.0.1", "port": port},
                                                "display_endpoint": {"host": "entry.example", "port": port},
                                                "settings": {"version": 4}}}])


class RuntimeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="sc-")
        self.root = Path(self.temp.name)
        self.environment = patch.dict(os.environ, {
            "NOBRAND_SYSTEM_ROOT": str(self.root), "NOBRAND_STATE_DIR": str(self.root / "state"), "NOBRAND_CONFIG_DIR": str(self.root / "config"),
            "NOBRAND_LIB_DIR": str(self.root / "lib"), "NOBRAND_LIFECYCLE_DIR": str(self.root / "journal"),
            "NOBRAND_LIFECYCLE_LOCK_FILE": str(self.root / "guard"),
            "NOBRAND_SPLICORE_FIXTURE": "1", "SC_FIXTURE_ROOT": str(self.root)})
        self.environment.start()
        self.driver = self.root / "service-driver"
        self.driver.write_text(DRIVER)
        self.driver.chmod(0o700)
        self.runtime = sc.Runtime(adapter="fixture", fixture=self.driver)
        self.artifact_calls = 0
        self.identity = {"product": "Splicore", "version": sc.RELEASE["version"], "commit": sc.RELEASE["commit"],
                         "platform": "linux/" + sc.arch(), "dirty": False}
        self.artifact_patch = patch.object(sc, "artifact", side_effect=self.fake_artifact)
        self.artifact_patch.start()

    def tearDown(self):
        self.artifact_patch.stop()
        self.environment.stop()
        self.temp.cleanup()

    def fake_artifact(self, destination, *_args, **_kwargs):
        self.artifact_calls += 1
        sc.atomic(destination, FAKE_BINARY.replace("IDENTITY", repr(self.identity)), 0o700)
        return {"version": sc.RELEASE["version"], "architecture": sc.arch(),
                "binary_sha256": sc.sha(destination), "archive_sha256": "fixture-only"}

    def events(self):
        path = self.root / "service-events"
        return path.read_text() if path.exists() else ""

    def deploy(self, graph=None, **kwargs):
        return self.runtime.deploy(graph or desired(), **kwargs)

    def test_fresh_install_repeat_and_single_owner(self):
        self.assertEqual(self.deploy()["result"], "committed")
        current = self.runtime.target(self.runtime.current)
        self.assertEqual(self.deploy()["result"], "same-version-no-op")
        self.assertEqual(self.artifact_calls, 1)
        self.assertEqual(self.events().count("start nobrand-splicore\n"), 1)
        self.assertIn("synthetic-fixed-psk", (current / "desired.json").read_text())
        self.assertEqual((current / "runtime/master.key").stat().st_mode & 0o777, 0o600)
        self.assertEqual(sc.load(self.runtime.transaction)["phase"], "COMMITTED")

    def test_config_failure_never_stops_previous(self):
        self.deploy()
        old, events = self.runtime.current.readlink(), self.events()
        graph = desired()
        graph["nodes"][0]["options"] = {"quic_proxy_enabled": True}
        with self.assertRaisesRegex(sc.Failure, "no rc.4 equivalent"):
            self.deploy(graph)
        self.assertEqual(self.runtime.current.readlink(), old)
        self.assertEqual(self.events(), events)



    def test_generation_retention_is_bounded_and_keeps_rollback(self):
        for port in range(31231, 31236):
            self.deploy(desired(port))
        self.assertLessEqual(len(list(self.runtime.generations.iterdir())), 3)
        self.assertTrue(self.runtime.current.resolve().is_dir())
        self.assertTrue(self.runtime.previous.resolve().is_dir())
        self.runtime.rollback()
        self.assertEqual(self.runtime.desired()["nodes"][0]["document"]["listener"]["port"], 31234)


    def test_mieru_supported_reconfigure_preserves_identity(self):
        env = {"PORT": "31231", "ADVERTISE_HOST": "entry.example", "TRAFFIC_PATTERN": "off", "PROTOCOL": "BOTH", "USERNAME": "alice", "PASSWORD": "original-secret"}
        with patch.dict(os.environ, env):
            self.runtime.protocol("mieru", "install", "alice")
        users = [n["document"]["users"] for n in self.runtime.desired()["nodes"]]
        with patch.dict(os.environ, {"MTU_CLI": "1", "MTU": "1380", "HANDSHAKE_CLI": "1", "HANDSHAKE_MODE": "standard"}):
            self.runtime.protocol("mieru", "reconfigure", "alice")
        after = self.runtime.desired()["nodes"]
        self.assertEqual([n["document"]["users"] for n in after], users)
        self.assertTrue(all(n["document"]["settings"]["mtu"] == 1380 for n in after))
        self.assertTrue(all("HANDSHAKE_STANDARD" in sc.client_profiles(n)["uri"] for n in after))

    def test_doctor_health_does_not_write_generation(self):
        from types import SimpleNamespace
        self.deploy()
        current = self.runtime.current.resolve()
        before = {str(p): (p.stat().st_mtime_ns, p.read_bytes()) for p in current.rglob("*") if p.is_file()}
        inbound = {"id": "native-id", "name": "nb-primary", "listeners": [{"endpoint": {"host": "127.0.0.1", "port": 31231}}]}
        with patch.object(sc, "command", return_value=SimpleNamespace(stdout=json.dumps({"items": [{"inbound": inbound, "health": "healthy"}]}).encode())):
            self.runtime.health(current)
        after = {str(p): (p.stat().st_mtime_ns, p.read_bytes()) for p in current.rglob("*") if p.is_file()}
        self.assertEqual(after, before)

    def test_candidate_start_failure_restores_generation_and_active_set(self):
        self.deploy()
        old = self.runtime.current.resolve()
        (self.root / "fail-start").touch()
        with self.assertRaises(sc.Failure):
            self.deploy(desired(31232))
        self.assertEqual(self.runtime.current.resolve(), old)
        self.assertEqual(sc.load(self.runtime.transaction)["phase"], "ROLLED_BACK")
        self.assertTrue(sc.load(self.root / "services.json")["nobrand-splicore"]["active"])



    def test_second_generation_preserves_key_and_can_roll_back(self):
        self.deploy()
        previous = self.runtime.current.resolve()
        key = (previous / "runtime/master.key").read_bytes()
        self.deploy(desired(31232))
        self.assertEqual(self.artifact_calls, 1, "config update reuses verified artifact")
        self.assertEqual((self.runtime.current / "runtime/master.key").read_bytes(), key)
        self.runtime.rollback()
        self.assertEqual(self.runtime.current.resolve(), previous)

    def test_persistent_recovery_after_pointer_swap(self):
        self.deploy()
        old = self.runtime.current.resolve()
        self.deploy(desired(31232))
        tx = sc.load(self.runtime.transaction)
        tx["phase"] = "STARTING"
        sc.save(self.runtime.transaction, tx)
        recreated = sc.Runtime(adapter="fixture", fixture=self.driver)
        with recreated.locked():
            self.assertEqual(recreated.recover()["recovery"], "ROLLED_BACK")
        self.assertEqual(recreated.current.resolve(), old)

    def test_backup_includes_matching_database_key_and_is_private(self):
        self.deploy()
        sc.atomic(self.runtime.current / "runtime/state.db", b"synthetic-stopped-database")
        backup = self.root / "backup.tar.gz"
        self.runtime.backup(backup)
        self.assertEqual(backup.stat().st_mode & 0o777, 0o600)
        import tarfile
        with tarfile.open(backup) as archive:
            self.assertIn("runtime/state.db", archive.getnames())
            self.assertIn("runtime/master.key", archive.getnames())
        self.assertTrue(sc.load(self.root / "services.json")["nobrand-splicore"]["active"])

    def test_unified_backup_and_pointer_adoption(self):
        self.deploy()
        current = self.runtime.current.resolve()
        sc.atomic(self.runtime.state / "retained-state.txt", "other NoBrand business state")
        sc.atomic(self.runtime.config / "retained-config.txt", "other NoBrand config")
        backup = self.root / "product.tar.gz"
        self.runtime.backup(backup, unified=True)
        import tarfile
        with tarfile.open(backup) as archive:
            self.assertTrue(all(not m.issym() and not m.islnk() for m in archive.getmembers()))
            self.assertIn("state/retained-state.txt", archive.getnames())
            self.assertIn("config/retained-config.txt", archive.getnames())
            pointer = json.loads(archive.extractfile("state/splicore/current").read())
        self.runtime.current.unlink()
        sc.save(self.runtime.current, pointer)
        self.runtime.adopt_snapshot()
        self.assertEqual(self.runtime.current.resolve(), current)

    def test_standalone_backup_restore_preserves_credentials_and_key(self):
        self.deploy()
        expected = self.runtime.desired()
        key = (self.runtime.current / "runtime/master.key").read_bytes()
        backup = self.root / "runtime.tar.gz"
        self.runtime.backup(backup)
        self.deploy(desired(31232))
        self.runtime.restore(backup)
        restored = self.runtime.desired()
        self.assertEqual(restored["nodes"], expected["nodes"])
        self.assertEqual((self.runtime.current / "runtime/master.key").read_bytes(), key)

    def test_concurrent_request_does_not_overwrite_newer_generation(self):
        self.deploy()
        old = self.runtime.current.resolve().name
        self.deploy(desired(31232))
        current = self.runtime.current.resolve()
        with self.assertRaisesRegex(sc.Failure, "changed since request"):
            self.runtime.deploy(desired(31233), expected_generation=old)
        self.assertEqual(self.runtime.current.resolve(), current)

    def test_config_validation_failure_precedes_any_service_mutation(self):
        graph = desired()
        graph["nodes"][0] = {"id": "m", "protocol": "mieru", "document": {
            "schema": 1, "listener": {"host": "127.0.0.1", "port": 31231},
            "display_endpoint": {"host": "entry.example", "port": 31231},
            "settings": {"transport": "tcp", "mtu": 999, "multiplex": "off"},
            "users": [{"username": "original-user", "password": "original-password"}]}}
        with self.assertRaises(sc.Failure):
            self.deploy(graph)
        self.assertNotIn("stop ", self.events())

    def test_external_port_ownership_is_checked_before_download(self):
        sc.save(self.runtime.state / "vless-sudoku/state.json", {"listen_port": 31231})
        with self.assertRaisesRegex(sc.Failure, "retained Sudoku"):
            self.deploy()
        self.assertEqual(self.artifact_calls, 0)

    def test_clients_keep_protocol_parameters_and_credentials(self):
        node = desired()["nodes"][0]
        node["document"]["settings"]["version"] = 5
        profiles = sc.client_profiles(node)
        self.assertIn("version = 4", profiles["surge"])
        self.assertEqual(profiles["server_version"], 5)
        self.assertEqual(profiles["sing_box"]["version"], 4)
        self.assertEqual(profiles["sing_box"]["psk"], "synthetic-fixed-psk")

    def test_uninstall_and_purge_are_repeatable_and_preserve_other_state(self):
        self.deploy()
        other = self.runtime.state / "other-feature"
        other.write_text("retain")
        self.runtime.uninstall()
        self.runtime.uninstall()
        self.runtime.uninstall(purge=True)
        self.runtime.uninstall(purge=True)
        self.assertEqual(other.read_text(), "retain")

    def test_unsafe_root_pointer_and_foreign_service_reject(self):
        self.runtime.home.mkdir(parents=True)
        self.runtime.current.symlink_to(self.root)
        with self.assertRaises(sc.Failure):
            self.runtime.desired()
        self.runtime.current.unlink()
        self.runtime.unit_path().write_text("foreign service")
        with self.assertRaises(sc.Failure):
            self.deploy()

    def test_duplicate_ports_are_transport_and_address_aware(self):
        graph = desired()
        second = copy.deepcopy(graph["nodes"][0])
        second["id"] = "other"
        graph["nodes"].append(second)
        with self.assertRaisesRegex(sc.Failure, "overlapping"):
            sc.render(graph)
        second["document"]["listener"]["host"] = "127.0.0.2"
        self.assertEqual(len(sc.render(graph)), 2)
        second["document"]["listener"]["host"] = "0.0.0.0"
        with self.assertRaises(sc.Failure):
            sc.render(graph)

    def test_capability_and_unknown_option_fail_before_artifact(self):
        for options in ({"quota_mb": 1}, {"obfs": "salamander"}, {"traffic_pattern": "conservative"},
                        {"bandwidth_mbps": 1}, {"unknown": "ignored"}):
            graph = desired()
            graph["nodes"][0]["options"] = options
            with self.assertRaises(sc.Failure):
                self.deploy(graph)
        self.assertEqual(self.artifact_calls, 0)

    def test_unsupported_architecture_and_pin_identity(self):
        for value, wanted in (("x86_64", "amd64"), ("amd64", "amd64"), ("aarch64", "arm64"), ("arm64", "arm64")):
            self.assertEqual(sc.arch(value), wanted)
        with self.assertRaises(sc.Failure):
            sc.arch("armv7l")
        self.assertNotIn("latest", sc.RELEASE["version"])

    def test_production_archive_gate_and_corruption(self):
        payload = bytearray(20)
        payload[:6] = b"\x7fELF\x02\x01"
        struct.pack_into("<H", payload, 18, 62)
        path = self.root / "fake-amd64.tar.gz"
        def package(extra=None):
            with tarfile.open(path, "w:gz") as archive:
                info = tarfile.TarInfo("splicore")
                info.size = len(payload)
                archive.addfile(info, io.BytesIO(payload))
                if extra:
                    archive.addfile(extra, io.BytesIO())
            entry = {"name": path.name, "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}
            return entry, entry["sha256"] + "  " + entry["name"] + "\n"
        entry, sums = package()
        sc.inspect_archive(path, entry, sums)
        for invalid in ("/bad", "../bad", "licenses/third-party/../../bad", "unexpected.sh"):
            entry, sums = package(tarfile.TarInfo(invalid))
            with self.assertRaises(sc.Failure):
                sc.inspect_archive(path, entry, sums)
        for kind in (tarfile.SYMTYPE, tarfile.LNKTYPE, tarfile.FIFOTYPE):
            info = tarfile.TarInfo("licenses/third-party/link")
            info.type = kind
            entry, sums = package(info)
            with self.assertRaises(sc.Failure):
                sc.inspect_archive(path, entry, sums)
        entry, sums = package()
        for manifest in ("", sums + sums, "not-a-hash  " + path.name):
            with self.assertRaises(sc.Failure):
                sc.inspect_archive(path, entry, manifest)
        path.write_bytes(b"interrupted archive")
        with self.assertRaisesRegex(sc.Failure, "checksum"):
            sc.inspect_archive(path, entry, sums)

    def test_https_download_and_proxy_share_the_same_gate(self):
        from types import SimpleNamespace
        url = "https://github.com/" + sc.RELEASE["repository"] + "/releases/download/" + sc.RELEASE["version"] + "/SHA256SUMS"
        calls = []
        def invoke(arguments, *_args, **_kwargs):
            calls.append(arguments)
            return SimpleNamespace(returncode=0)
        with patch.object(sc, "command", side_effect=invoke):
            sc.download(url, self.root / "direct")
            sc.download(url, self.root / "proxy", "https://proxy.example")
        self.assertEqual(calls[0][-1], url)
        self.assertEqual(calls[1][-1], "https://proxy.example/" + url)
        self.assertTrue(all("--proto-redir" in call and "=https" in call and "--fail" in call for call in calls))
        self.assertTrue(all("-k" not in call for call in calls))

    def test_service_templates_have_one_supervisor(self):
        for adapter in ("systemd", "openrc"):
            runtime = sc.Runtime(adapter=adapter)
            text = runtime.service_text()
            self.assertEqual(text.count("/launch.py"), 1)
            self.assertNotIn("while true", text)
            self.assertIn("Restart=on-failure" if adapter == "systemd" else 'supervisor="supervise-daemon"', text)

    def test_reviewed_pin_upgrade_and_old_generation_rollback(self):
        self.deploy()
        old = self.runtime.current.resolve()
        previous_release = copy.deepcopy(sc.RELEASE)
        # Synthetic future pin exercises the framework, not rc.4 qualification.
        upgraded = copy.deepcopy(sc.RELEASE)
        upgraded["version"] = "v0.3.0-rc.5-fixture"
        upgraded["rollback_releases"] = {previous_release["version"]: previous_release}
        self.identity["version"] = upgraded["version"]
        with patch.object(sc, "RELEASE", upgraded):
            self.assertEqual(self.deploy()["result"], "committed")
            self.assertEqual(self.artifact_calls, 2)
            self.runtime.rollback()
            self.assertEqual(self.runtime.current.resolve(), old)

    def test_product_archive_rejects_links_before_extraction(self):
        path = self.root / "unsafe-product.tar.gz"
        for kind in (tarfile.SYMTYPE, tarfile.LNKTYPE, tarfile.FIFOTYPE):
            with tarfile.open(path, "w:gz") as archive:
                item = tarfile.TarInfo("state/escape")
                item.type, item.linkname = kind, "/tmp/foreign-target"
                archive.addfile(item)
            with self.assertRaises(sc.Failure):
                sc.inspect_backup_archive(path)

    def test_launcher_rejects_live_foreign_and_locked_entries(self):
        import fcntl
        import socket
        import subprocess
        generation = self.root / "launcher"
        generation.mkdir()
        sc.atomic(generation / "launch.py", sc.LAUNCHER)
        sc.atomic(generation / "splicore", "#!/bin/sh\nexit 0\n", 0o700)
        control = generation / "control.sock"
        def launch():
            return subprocess.run([os.sys.executable, str(generation / "launch.py")], stdout=subprocess.PIPE, stderr=subprocess.PIPE).returncode
        control.write_text("foreign entry")
        self.assertNotEqual(launch(), 0)
        self.assertEqual(control.read_text(), "foreign entry")
        control.unlink()
        with socket.socket(socket.AF_UNIX) as live:
            live.bind(str(control))
            live.listen()
            self.assertNotEqual(launch(), 0)
            self.assertTrue(control.exists())
        # Closing the listener leaves a real stale Unix socket.
        self.assertEqual(launch(), 0)
        self.assertFalse(control.exists())
        with (generation / "daemon.lock").open("a") as guard:
            fcntl.flock(guard, fcntl.LOCK_EX)
            self.assertNotEqual(launch(), 0)

    def test_product_restore_snapshots_stopped_primary_and_restores_generation(self):
        import subprocess
        # Existing product restore fixture conventions require root ownership.
        if os.geteuid() != 0:
            self.skipTest("product restore fixture requires root")
        self.environment.stop()
        self.environment = patch.dict(os.environ, {
            "NOBRAND_SYSTEM_ROOT": str(self.root),
            "NOBRAND_STATE_DIR": str(self.root / "nobrand-oneclick"),
            "NOBRAND_CONFIG_DIR": str(self.root / "nobrand-oneclick-config"),
            "NOBRAND_LIB_DIR": str(self.root / "nobrand-oneclick-lib"),
            "NOBRAND_LIFECYCLE_DIR": str(self.root / "nobrand-oneclick-lifecycle"),
            "NOBRAND_LIFECYCLE_LOCK_FILE": str(self.root / "run/nobrand-oneclick/lifecycle.lock"),
            "NOBRAND_SPLICORE_FIXTURE": "1", "SC_FIXTURE_ROOT": str(self.root),
            "SC_FIXTURE_DRIVER": str(self.driver), "NOBRAND_TEST_MODE": "1"})
        self.environment.start()
        self.runtime = sc.Runtime(adapter="fixture", fixture=self.driver)
        self.deploy()
        backup = self.root / "product.tar.gz"
        self.runtime.backup(backup, unified=True)
        self.deploy(desired(31232))
        import socket
        control = socket.socket(socket.AF_UNIX)
        control.bind(str(self.runtime.current / "control.sock"))
        # Exercise the real Bash product transaction plus actual embedded
        # adapter/adoption; mock only external system/utility service effects.
        script = r'''
set -euo pipefail
MITA_SOURCE_ONLY=1
installer=$1; backup=$2; set --
source "$installer"
trap - ERR
nb_splicore_call() { nb_splicore_python "$@" --adapter fixture --fixture-driver "$SC_FIXTURE_DRIVER"; }
ssh_tunnel_backup_state_ready() { return 0; }
ssh_tunnel_restore_preflight() { return 0; }
ssh_tunnel_snapshot_external_state() { return 0; }
forward_snapshot_restore_side_effects() { return 0; }
ssh_tunnel_cancel_pending_watchdog() { return 0; }
ssh_tunnel_cleanup_disarmed_watchdogs() { return 0; }
ssh_tunnel_restore_external_snapshot() { return 0; }
forward_restore_side_effect_snapshot() { return 0; }
forward_remove_restore_attempt_resources() { return 0; }
ssh_tunnel_prepare_restored_policy_state() { return 0; }
ssh_tunnel_restore_system_state() { return 0; }
forward_realm_restore_runtime() { return 0; }
nb_init_state_layout() { return 0; }
nobrand_start_enabled_services() { nb_splicore_call start; }
nobrand_backup_restore "$backup"
'''
        result = subprocess.run(["bash", "-c", script, "sc-product-restore", str(ROOT / "install-nobrand.sh"), str(backup)],
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=60)
        control.close()
        self.assertEqual(result.returncode, 0, result.stderr.decode()[-5000:])
        self.assertEqual(self.runtime.desired()["nodes"][0]["document"]["listener"]["port"], 31231)
        self.deploy(desired(31232))
        failure = script.replace("nobrand_start_enabled_services() { nb_splicore_call start; }", '''nobrand_start_enabled_services() {
  nb_splicore_call start || return 1
  if [ ! -f "$SC_FIXTURE_ROOT/restore-failed-once" ]; then
    touch "$SC_FIXTURE_ROOT/restore-failed-once"; return 1
  fi
}''')
        result = subprocess.run(["bash", "-c", failure, "sc-product-rollback", str(ROOT / "install-nobrand.sh"), str(backup)],
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=60)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.runtime.desired()["nodes"][0]["document"]["listener"]["port"], 31232)
        self.assertTrue(sc.load(self.root / "services.json")["nobrand-splicore"]["active"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
