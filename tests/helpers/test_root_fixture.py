#!/usr/bin/env python3
"""Capability decisions, fixture boundaries and diagnostic regression tests."""
import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import root_fixture as rf


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


q = load("root_qualification", rf.ROOT / "scripts/qualify-splicore.py")
d = load("root_diagnostics", rf.ROOT / "scripts/ci-diagnostics.py")
POLICY = {"required": True, "namespace": True, "requirement": "manager-bootstrap"}
OK = {"exit_code": 0, "euid": 0, "usable": True}
NO = {"exit_code": 1, "euid": None, "usable": False}


class RootFixtureTests(unittest.TestCase):
    def decision(self, uid=1001, sudo=True, namespace=True, results=(), policy=None):
        def which(name, **_):
            return "/usr/bin/" + name if (sudo if name == "sudo" else namespace) else None
        with patch.object(rf.os, "geteuid", return_value=uid), patch.object(rf.shutil, "which", side_effect=which), \
                patch.object(rf, "probe", side_effect=results) as probe:
            prefix, meta = rf.resolve(policy or POLICY)
            return prefix, meta, probe.call_args_list

    def test_direct_root_never_recurses_or_probes_sudo(self):
        prefix, meta, calls = self.decision(uid=0)
        self.assertEqual(prefix, [])
        self.assertEqual(meta["executor"], "direct-root")
        self.assertEqual(calls, [])

    def test_sudo_precedes_namespace_and_confirms_root(self):
        prefix, meta, calls = self.decision(results=[OK])
        self.assertEqual(prefix, ["/usr/bin/sudo", "-n", "--"])
        self.assertEqual(meta["executor"], "sudo")
        self.assertTrue(meta["sudo_available"])
        self.assertEqual(len(calls), 1)

    def test_sudo_unavailable_namespace_supported(self):
        prefix, meta, _ = self.decision(results=[NO, OK])
        self.assertEqual(prefix, ["/usr/bin/unshare", "--user", "--map-root-user"])
        self.assertEqual(meta["executor"], "namespace")
        self.assertFalse(meta["sudo_available"])
        self.assertTrue(meta["namespace_available"])

    def test_namespace_exists_but_creation_fails(self):
        prefix, meta, _ = self.decision(sudo=False, results=[NO])
        self.assertIsNone(prefix)
        self.assertTrue(meta["namespace_present"])
        self.assertFalse(meta["namespace_available"])

    def test_host_root_policy_never_probes_namespace(self):
        prefix, _, calls = self.decision(sudo=False, policy=dict(POLICY, namespace=False))
        self.assertIsNone(prefix)
        self.assertEqual(calls, [])

    def test_no_executable_means_no_root(self):
        prefix, meta, calls = self.decision(sudo=False, namespace=False)
        self.assertIsNone(prefix)
        self.assertEqual(meta["executor"], "unavailable")
        self.assertEqual(calls, [])

    def test_probe_requires_actual_uid_and_ownership_not_exit_zero(self):
        for data in ({"euid": 1001, "ownership": True}, {"euid": 0, "ownership": False},
                     {"euid": False, "ownership": True}, {}):
            with self.subTest(data=data), patch.object(rf.subprocess, "run", return_value=
                    subprocess.CompletedProcess([], 0, json.dumps(data), "private-error")):
                self.assertFalse(rf.probe(["sudo", "-n"])["usable"])

    def test_probe_is_bounded_clean_and_noninteractive(self):
        with patch.dict(os.environ, {"GITHUB_TOKEN": "synthetic-secret", "SSH_AUTH_SOCK": "/synthetic-agent"}), \
                patch.object(rf.subprocess, "run", return_value=subprocess.CompletedProcess(
                    [], 0, json.dumps({"euid": 0, "ownership": True}), "")) as run:
            self.assertTrue(rf.probe(["sudo", "-n", "--"])["usable"])
            self.assertEqual(run.call_args.kwargs["env"], rf.clean_environment())
            self.assertEqual(run.call_args.kwargs["stdin"], subprocess.DEVNULL)
            self.assertEqual(run.call_args.kwargs["timeout"], 15)

    def test_probe_timeout_or_error_is_unavailable_without_stderr(self):
        for error in (subprocess.TimeoutExpired("probe", 15), OSError("synthetic-secret")):
            with patch.object(rf.subprocess, "run", side_effect=error):
                self.assertEqual(rf.probe([]), {"exit_code": None, "euid": None, "usable": False})

    def test_mandatory_unavailable_never_enters_fixture(self):
        with patch.object(rf, "resolve", return_value=(None, {})), patch.object(rf, "copy_fixture") as copy, \
                patch.object(rf, "record") as record:
            self.assertEqual(rf.run_fixture(rf.RESTORE), 78)
            copy.assert_not_called()
            self.assertEqual(record.call_args.args[0]["classification"], "QUALIFICATION_ENVIRONMENT")
            self.assertFalse(record.call_args.args[0]["fixture_started"])

    def test_optional_unavailable_is_explicit_not_required_skip(self):
        with patch.dict(rf.FIXTURES, {"optional-platform": dict(POLICY, required=False)}), \
                patch.object(rf, "resolve", return_value=(None, {})), patch.object(rf, "record") as record:
            self.assertEqual(rf.run_fixture("optional-platform"), 0)
            self.assertEqual(record.call_args.args[0]["outcome"], "OPTIONAL_UNAVAILABLE")
        self.assertTrue(all(p["required"] for p in rf.FIXTURES.values()))

    def workspace(self, root):
        (root / "checkout").mkdir()
        (root / "checkout/sentinel").write_text("copy only")

    def test_child_confirmation_failure_precedes_fixture(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(rf.os, "geteuid", return_value=1001), \
                patch.object(rf.subprocess, "run") as run:
            root = Path(directory)
            self.workspace(root)
            result = rf.child(rf.RESTORE, root)
            self.assertEqual(result["exit_code"], 78)
            self.assertEqual(result["outcome"], "ROOT_CONFIRMATION_FAILED")
            self.assertTrue(result["cleanup"])
            run.assert_not_called()

    def exercise_child(self, code):
        actual_run = subprocess.run
        scratch_roots = []
        def execute(*args, **kwargs):
            scratch_roots.append(Path(kwargs["env"]["TMPDIR"]).parent)
            return actual_run(*args, **kwargs)
        with tempfile.TemporaryDirectory() as directory, patch.object(rf.os, "geteuid", return_value=0), \
                patch.object(rf.subprocess, "run", side_effect=execute), \
                patch.object(rf, "fixture_command", return_value=["/usr/bin/python3", "-c",
                    "import os,pathlib,sys;assert 'GITHUB_TOKEN' not in os.environ;"
                    "assert 'SSH_AUTH_SOCK' not in os.environ;"
                    "pathlib.Path(os.environ['TMPDIR'],'owned').write_text('fixture');sys.exit(" + str(code) + ")"]):
            root = Path(directory)
            self.workspace(root)
            result = rf.child(rf.RESTORE, root)
            self.assertEqual(len(scratch_roots), 1)
            self.assertFalse(scratch_roots[0].exists())
            self.assertFalse((root / "checkout").exists())
            self.assertTrue(result["cleanup"])
            return result

    def test_child_cleanup_and_success(self):
        with patch.dict(os.environ, {"GITHUB_TOKEN": "synthetic-secret", "SSH_AUTH_SOCK": "/agent"}):
            self.assertEqual(self.exercise_child(0)["outcome"], "PASS")

    def test_fixture_assertion_failure_preserves_exit_and_cleanup(self):
        result = self.exercise_child(23)
        self.assertEqual(result["exit_code"], 23)
        self.assertEqual(result["outcome"], "FIXTURE_FAILED")

    def test_sudo_child_contract_uses_copy_and_clean_env(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "original").write_text("unchanged")
            def execute(command, **kwargs):
                self.assertEqual(command[:5], ["/usr/bin/sudo", "-n", "--", "/usr/bin/env", "-i"])
                self.assertEqual(kwargs["env"], rf.clean_environment())
                self.assertNotIn("sudo -E", " ".join(command))
                workspace = Path(command[-1])
                self.assertNotEqual(workspace.parent, root)
                shutil.rmtree(workspace / "checkout")
                (workspace / "result.json").write_text(json.dumps(
                    {"exit_code": 0, "euid": 0, "outcome": "PASS", "cleanup": True}))
                return subprocess.CompletedProcess(command, 0)
            def copy(destination):
                destination.mkdir()
            with patch.object(rf, "ROOT", root), patch.object(rf, "copy_fixture", side_effect=copy), \
                    patch.object(rf, "resolve", return_value=(["/usr/bin/sudo", "-n", "--"], {"executor": "sudo"})), \
                    patch.object(rf.subprocess, "run", side_effect=execute), patch.object(rf, "record") as record:
                self.assertEqual(rf.run_fixture(rf.RESTORE), 0)
                self.assertTrue(record.call_args.args[0]["checkout_ownership_unchanged"])
                self.assertEqual(record.call_args.args[0]["euid"], 0)

    def test_original_namespace_fallthrough_and_new_block(self):
        old = q.git("show", "ae6f666addbe67112f7e6d8939646cf25fe618ca:scripts/test.sh").decode()
        prelude = old[old.index('if [ "$(id -u)"'):old.index("TEST_SCRIPT_ROOT=")]
        run = subprocess.run(["/bin/bash", "-c", "id(){ echo 1001; }; unshare(){ return 1; };\n" +
                              prelude + "printf fixture-incorrectly-started"], capture_output=True, text=True)
        self.assertEqual(run.returncode, 0)
        self.assertEqual(run.stdout, "fixture-incorrectly-started")
        self.test_mandatory_unavailable_never_enters_fixture()

    def test_original_manager_root_guard_fails_before_fix(self):
        # The real original failure entrypoint, without invoking its executor.
        run = subprocess.run(["/bin/bash", "-c", 'id(){ echo 1001; }; export -f id; exec bash "$0"',
                              str(rf.ROOT / "tests/test_splicore_shell_surface.sh")],
                             capture_output=True, text=True, env=rf.clean_environment(), timeout=30)
        self.assertNotEqual(run.returncode, 0)
        self.assertIn("root", run.stderr + run.stdout)

    def test_environment_classification_survives_qualifier(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            evidence = root / "privilege.jsonl"
            evidence.write_text(json.dumps({"classification": "QUALIFICATION_ENVIRONMENT"}) + "\n")
            with self.assertRaises(q.QualificationFailure) as caught:
                q.run_logged(["/bin/sh", "-c", "exit 78"], root / "regression.log", 5,
                             env=dict(os.environ, NOBRAND_PRIVILEGE_EVIDENCE=str(evidence)))
            self.assertEqual(caught.exception.classification, "QUALIFICATION_ENVIRONMENT")
            self.assertEqual(json.loads((root / "regression.command.json").read_text())["exit_code"], 78)

    def test_public_metadata_is_typed_and_excludes_private_fields(self):
        raw = json.dumps({"fixture": rf.RESTORE, "executor": "sudo", "euid": 0, "sudo_available": True,
                          "outcome": "PASS", "password": "synthetic-secret", "namespace_available": "synthetic-secret",
                          "probes": {"sudo": {"exit_code": 0, "euid": 0, "usable": True, "stderr": "synthetic-secret"}}})
        value = d.privilege_projection(raw + "\ninvalid-partial")
        self.assertEqual(value["executor"], "sudo")
        self.assertEqual(value["fixtures"][0]["euid"], 0)
        self.assertNotIn("synthetic-secret", json.dumps(value))

    def test_environment_failure_is_published_without_losing_status(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "private").mkdir()
            (root / "qualification-exit-code").write_text("1\n")
            (root / "private/summary.json").write_text(json.dumps(
                {"result": "FAIL", "classification": "QUALIFICATION_ENVIRONMENT"}))
            (root / "private/privilege.jsonl").write_text(json.dumps(
                {"fixture": rf.RESTORE, "executor": "unavailable", "outcome": "UNAVAILABLE", "euid": 1001}))
            with contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(d.publish(root), 0)
                self.assertEqual(d.finish(root), 1)
            value = json.loads((root / "public/failure-summary.json").read_text())
            self.assertEqual(value["classification"], "QUALIFICATION_ENVIRONMENT")
            self.assertEqual(value["privilege"]["executor"], "unavailable")


if __name__ == "__main__":
    unittest.main(verbosity=2)
