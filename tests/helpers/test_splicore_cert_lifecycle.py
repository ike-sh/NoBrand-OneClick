#!/usr/bin/env python3
"""Managed TLS preservation, ownership and rejection with synthetic material."""
import copy
import hashlib
import os
from pathlib import Path
import shutil
import socket
import unittest
from unittest.mock import patch

import test_splicore_runtime as base

sc = base.sc


class CertificateTests(base.RuntimeTests):
    def setUp(self):
        super().setUp()
        self.env = patch.dict(os.environ, {"PORT": "31232", "ADVERTISE_HOST": "entry.example",
                                         "HY2_SNI": "probe.example", "TUIC_SNI": "probe.example"})
        self.env.start()

    def tearDown(self):
        self.env.stop()
        super().tearDown()

    def install(self, protocol="hysteria2", label="fresh"):
        return self.runtime.protocol(protocol, "install", label)

    def material(self):
        node = self.runtime.desired()["nodes"][0]
        return Path(node["document"]["settings"]["tls"]["certificate_file"]).parent

    def snapshot(self, target):
        return {p.name: (p.lstat().st_mode, p.lstat().st_uid, p.lstat().st_gid, p.read_bytes())
                for p in target.iterdir() if p.is_file() and not p.is_symlink()}

    def retained(self, protocol="hysteria2"):
        self.install(protocol)
        target = self.material()
        self.runtime.protocol(protocol, "uninstall", "fresh")
        return target

    def reject_unchanged(self, target, protocol="hysteria2"):
        before, events, current = self.snapshot(target), self.events(), self.runtime.target(self.runtime.current)
        with self.assertRaises(sc.Failure):
            self.install(protocol)
        self.assertEqual(self.snapshot(target), before)
        self.assertEqual(self.events(), events)
        self.assertEqual(self.runtime.target(self.runtime.current), current)

    def rehash(self, target):
        marker = sc.load(target / "owner.json")
        marker["files"] = {n: sc.sha(target / n) for n in ("certificate.pem", "private.key", "ca.pem")}
        sc.save(target / "owner.json", marker)

    def cycle(self, protocol, removal):
        self.install(protocol)
        target = self.material()
        original = self.snapshot(target)
        for _ in range(2):
            if removal == "protocol":
                self.runtime.protocol(protocol, "uninstall", "fresh")
            else:
                self.runtime.uninstall()
                self.assertEqual(self.runtime.uninstall()["result"], "uninstalled")
            self.assertEqual(self.snapshot(target), original)
            self.assertEqual(self.install(protocol)["result"], "committed")
            self.assertEqual(self.material(), target)
            self.assertEqual(self.snapshot(target), original)
            sc.tls_check(self.runtime.desired()["nodes"][0]["document"]["settings"]["tls"])

    def test_hy2_protocol_remove_two_reinstalls(self):
        self.cycle("hysteria2", "protocol")

    def test_hy2_runtime_uninstall_twice_two_reinstalls(self):
        self.cycle("hysteria2", "runtime")

    def test_tuic_protocol_remove_two_reinstalls(self):
        self.cycle("tuic", "protocol")

    def test_tuic_runtime_uninstall_twice_two_reinstalls(self):
        self.cycle("tuic", "runtime")

    def test_active_instance_collision_preserves_identity(self):
        self.install()
        self.reject_unchanged(self.material())

    def test_purge_then_fresh_mints_new_identity(self):
        for protocol in ("hysteria2", "tuic"):
            with self.subTest(protocol=protocol):
                target = self.retained(protocol)
                old = self.snapshot(target)
                self.runtime.uninstall(True)
                self.assertFalse(target.exists())
                self.assertEqual(self.install(protocol)["result"], "committed")
                self.assertNotEqual(self.snapshot(self.material())["ca.pem"][3], old["ca.pem"][3])
                self.runtime.uninstall(True)

    def test_missing_certificate_key_and_ca_fail_closed(self):
        target = self.retained()
        for name in ("certificate.pem", "private.key", "ca.pem"):
            with self.subTest(name=name):
                path, data = target / name, (target / name).read_bytes()
                path.unlink()
                self.reject_unchanged(target)
                sc.atomic(path, data)

    def test_missing_marker_without_canonical_proof_fails_closed(self):
        target = self.retained()
        (target / "owner.json").unlink()
        for generation in self.runtime.generations.iterdir():
            graph = sc.load(generation / "desired.json")
            graph["nodes"] = []
            sc.save(generation / "desired.json", graph)
        self.reject_unchanged(target)

    def test_pre_marker_native_canonical_adoption_preserves_material(self):
        for protocol in ("hysteria2", "tuic"):
            with self.subTest(protocol=protocol):
                self.install(protocol)
                target = self.material()
                (target / "owner.json").unlink()
                before = self.snapshot(target)
                self.runtime.uninstall()
                self.assertEqual(self.install(protocol)["result"], "committed")
                after = self.snapshot(target)
                self.assertEqual({k: v for k, v in after.items() if k != "owner.json"}, before)
                self.assertTrue((target / "owner.json").is_file())
                self.runtime.uninstall(True)

    def test_marker_survives_canonical_generation_pruning(self):
        target = self.retained()
        for port in range(31233, 31237):
            self.deploy(base.desired(port))
        self.assertFalse(any(n["id"] == target.name for g in self.runtime.generations.iterdir()
                             for n in sc.load(g / "desired.json")["nodes"]))
        before = self.snapshot(target)
        self.assertEqual(self.install()["result"], "committed")
        self.assertEqual(self.snapshot(target), before)

    def test_wrong_instance_and_sni_fail_closed(self):
        target = self.retained()
        for field, value in (("node_id", "foreign"), ("server_name", "other.example")):
            original = sc.load(target / "owner.json")
            bad = dict(original, **{field: value})
            sc.save(target / "owner.json", bad)
            self.reject_unchanged(target)
            sc.save(target / "owner.json", original)
        with patch.dict(os.environ, {"HY2_SNI": "other.example"}):
            self.reject_unchanged(target)

    def test_truncated_material_or_metadata_fail_closed(self):
        target = self.retained()
        for name in ("certificate.pem", "private.key", "ca.pem", "owner.json"):
            data = (target / name).read_bytes()
            sc.atomic(target / name, "truncated")
            self.reject_unchanged(target)
            sc.atomic(target / name, data)

    def test_bad_key_pair_rejected_even_with_updated_owned_hash(self):
        target = self.retained()
        other = self.runtime.certificate("other", "probe.example")
        sc.atomic(target / "private.key", Path(other["private_key_file"]).read_bytes())
        self.rehash(target)
        self.reject_unchanged(target)

    def test_wrong_ca_rejected_even_with_updated_owned_hash(self):
        target = self.retained()
        other = self.runtime.certificate("other", "probe.example")
        sc.atomic(target / "ca.pem", other["ca_certificate"])
        self.rehash(target)
        self.reject_unchanged(target)

    def test_expiry_is_verified_by_openssl(self):
        target = self.retained()
        original = sc.command

        def future_verify(args, *a, **kw):
            # A real OpenSSL verification at a clock beyond the retained CA's
            # lifetime, without altering the host clock or mocking its result.
            if args[:2] == ["openssl", "verify"]:
                args = list(args[:2]) + ["-attime", "2208988800"] + list(args[2:])
            return original(args, *a, **kw)

        with patch.object(sc, "command", side_effect=future_verify):
            self.reject_unchanged(target)

    def test_reuse_requires_san_leaf_eku_and_signing_usage(self):
        target = self.retained()
        work = self.root / "synthetic-ca"
        work.mkdir(mode=0o700)
        ca_config = work / "ca.cnf"
        sc.atomic(ca_config, "[req]\ndistinguished_name=dn\nprompt=no\nx509_extensions=ca\n[dn]\nCN=Synthetic test CA\n[ca]\nbasicConstraints=critical,CA:TRUE\nkeyUsage=critical,keyCertSign,cRLSign\n")
        sc.command(["openssl", "req", "-new", "-x509", "-newkey", "ec", "-pkeyopt", "ec_paramgen_curve:P-256",
                    "-nodes", "-days", "2", "-config", ca_config, "-keyout", work / "ca.key", "-out", work / "ca.pem"])
        sc.command(["openssl", "req", "-new", "-key", target / "private.key", "-subj", "/CN=probe.example", "-out", work / "leaf.csr"])
        valid = {"basicConstraints": "critical,CA:FALSE", "keyUsage": "critical,digitalSignature",
                 "extendedKeyUsage": "serverAuth", "subjectAltName": "DNS:probe.example"}
        for field, value in (("subjectAltName", None), ("subjectAltName", "DNS:wrong.example"),
                             ("extendedKeyUsage", None), ("extendedKeyUsage", "clientAuth"),
                             ("keyUsage", None), ("keyUsage", "critical,keyEncipherment"),
                             ("basicConstraints", "critical,CA:TRUE")):
            with self.subTest(field=field, value=value):
                extensions = dict(valid)
                if value is None: extensions.pop(field)
                else: extensions[field] = value
                sc.atomic(work / "leaf.ext", "".join(k + "=" + v + "\n" for k, v in extensions.items()))
                sc.command(["openssl", "x509", "-req", "-in", work / "leaf.csr", "-CA", work / "ca.pem",
                            "-CAkey", work / "ca.key", "-CAcreateserial", "-days", "1", "-extfile", work / "leaf.ext", "-out", work / "leaf.pem"])
                sc.atomic(target / "certificate.pem", (work / "leaf.pem").read_bytes() + (work / "ca.pem").read_bytes())
                sc.atomic(target / "ca.pem", (work / "ca.pem").read_bytes())
                self.rehash(target)
                self.reject_unchanged(target)

    def test_foreign_directory_never_adopted_or_purged(self):
        self.install()
        target = self.material()
        self.runtime.uninstall(True)
        target.mkdir(parents=True, mode=0o700)
        sc.atomic(target / "sentinel", "synthetic third-party file")
        self.reject_unchanged(target)
        with self.assertRaises(sc.Failure):
            self.runtime.uninstall(True)
        self.assertEqual((target / "sentinel").read_text(), "synthetic third-party file")

    def test_certificate_and_directory_symlinks_fail_closed(self):
        target = self.retained()
        external = self.root / "external"
        external.mkdir(mode=0o700)
        sc.atomic(external / "sentinel", "synthetic foreign material")
        for name in ("certificate.pem", "private.key", "ca.pem", "owner.json"):
            data = (target / name).read_bytes()
            (target / name).unlink()
            (target / name).symlink_to(external / "sentinel")
            self.reject_unchanged(target)
            (target / name).unlink()
            sc.atomic(target / name, data)
        moved = target.with_name("saved")
        target.rename(moved)
        target.symlink_to(external, target_is_directory=True)
        with self.assertRaises(sc.Failure): self.install()
        with self.assertRaises(sc.Failure): self.runtime.uninstall(True)
        self.assertEqual((external / "sentinel").read_text(), "synthetic foreign material")

    def test_hardlink_and_loose_permissions_fail_closed(self):
        target = self.retained()
        for name in ("private.key", "owner.json"):
            link = self.root / "alias"
            link.hardlink_to(target / name)
            self.reject_unchanged(target)
            link.unlink()
        for path in (target, target / "private.key", target / "owner.json"):
            mode = path.stat().st_mode & 0o777
            path.chmod(0o755 if path == target else 0o644)
            self.reject_unchanged(target)
            path.chmod(mode)

    def test_path_traversal_and_symlink_parent_fail_without_writes(self):
        for name in ("", "..", "../escape", "/tmp/escape"):
            with self.assertRaises(sc.Failure): self.runtime.certificate(name, "probe.example")
        self.runtime.config.mkdir(parents=True, exist_ok=True)
        external = self.root / "external"
        external.mkdir()
        (self.runtime.config / "splicore").symlink_to(external, target_is_directory=True)
        with self.assertRaises(sc.Failure): self.runtime.certificate("fresh", "probe.example")
        self.assertEqual(list(external.iterdir()), [])

    def test_reused_tls_survives_failed_reinstall_and_retry(self):
        for protocol in ("hysteria2", "tuic"):
            with self.subTest(protocol=protocol):
                target = self.retained(protocol)
                before = self.snapshot(target)
                (self.root / "fail-health").touch()
                with self.assertRaises(sc.Failure): self.install(protocol)
                self.assertEqual(self.snapshot(target), before)
                self.assertEqual(self.install(protocol)["result"], "committed")
                self.runtime.uninstall(True)

    def test_external_user_certificate_reference_is_not_managed(self):
        tls = self.runtime.certificate("external-source", "probe.example")
        original = Path(tls["certificate_file"]).parent
        external = self.root / "user-certificate"
        shutil.move(original, external)
        tls.update(certificate_file=str(external / "certificate.pem"), private_key_file=str(external / "private.key"))
        before = self.snapshot(external)
        node = {"id": "user-tls", "protocol": "tuic", "document": {"schema": 1,
                "listener": {"host": "127.0.0.1", "port": 31232},
                "display_endpoint": {"host": "entry.example", "port": 31232},
                "settings": {"version": 5, "congestion_control": "cubic", "udp_relay_mode": "native",
                             "zero_rtt_handshake": False, "tls": tls},
                "users": [{"uuid": "22222222-2222-4222-8222-222222222222", "password": "synthetic-user-password"}]}}
        self.runtime.deploy(dict(sc.empty(), nodes=[node]))
        self.runtime.uninstall()
        self.runtime.uninstall(True)
        self.assertEqual(self.snapshot(external), before)


for name in dir(base.RuntimeTests):
    if name.startswith("test_"):
        setattr(CertificateTests, name, None)

if __name__ == "__main__":
    unittest.main(verbosity=2)
