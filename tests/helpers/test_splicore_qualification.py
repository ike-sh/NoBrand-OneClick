#!/usr/bin/env python3
"""Safety and evidence tests for the qualification infrastructure."""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("qualification", ROOT / "scripts/qualify-splicore.py")
q = importlib.util.module_from_spec(spec)
spec.loader.exec_module(q)


class QualificationTests(unittest.TestCase):
    def test_frozen_identity_and_all_protected_bytes(self):
        result = q.review_integrity()
        self.assertEqual(result["unapproved_changes"], 0)
        self.assertEqual(result["historical_reports"], 16)
        with self.assertRaises(q.QualificationFailure): q.frozen_integrity()

    def test_changed_missing_and_symlink_files_reject(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            path = root / "product"
            expected = {"product": hashlib.sha256(b"frozen").hexdigest()}
            path.write_bytes(b"frozen")
            q.verify_files(root, expected)
            path.write_bytes(b"changed")
            with self.assertRaises(q.QualificationFailure): q.verify_files(root, expected)
            path.unlink()
            with self.assertRaises(q.QualificationFailure): q.verify_files(root, expected)
            other = root / "other"
            other.write_bytes(b"frozen")
            path.symlink_to(other)
            with self.assertRaises(q.QualificationFailure): q.verify_files(root, expected)

    def test_workflow_current_read_only_contract(self):
        text = (ROOT / ".github/workflows/ci.yml").read_text()
        self.assertEqual(q.workflow_contract(text)["contract"], "PASS")

    def test_workflow_rejects_write_and_scheduled_privileges(self):
        text = (ROOT / ".github/workflows/ci.yml").read_text()
        for changed in (text.replace("contents: read", "contents: write"),
                        text.replace("  workflow_dispatch:", "  schedule:\n    - cron: '0 0 * * *'"),
                        text.replace("    timeout-minutes: 35", "    permissions:\n      contents: write\n    timeout-minutes: 35"),
                        text.replace("    timeout-minutes: 35", "    services:\n      database: {}\n    timeout-minutes: 35")):
            with self.subTest(changed=changed[:30]), self.assertRaises(q.QualificationFailure):
                q.workflow_contract(changed)

    def test_workflow_rejects_host_changes_and_publication(self):
        text = (ROOT / ".github/workflows/ci.yml").read_text()
        for command in ("docker ps", "systemctl restart nobrand-splicore", "nft flush ruleset", "git push", "gh release create test"):
            changed = text + "\n      - run: " + command + "\n"
            with self.subTest(command=command), self.assertRaises(q.QualificationFailure):
                q.workflow_contract(changed)

    def test_workflow_rejects_mutable_artifact_and_action(self):
        text = (ROOT / ".github/workflows/ci.yml").read_text()
        for changed in (text.replace(q.CHECKOUT, "actions/checkout@main"),
                        text + "\n      - run: curl https://example.invalid/releases/latest\n",
                        text + "\n      - run: curl https://example.invalid/install | bash\n"):
            with self.assertRaises(q.QualificationFailure): q.workflow_contract(changed)

    def test_corrupt_archive_is_not_executed(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            entry = q.sc.RELEASE["assets"]["amd64"]
            (root / "SHA256SUMS").write_text(entry["sha256"] + "  " + entry["name"] + "\n")
            (root / entry["name"]).write_bytes(b"corrupt-public-artifact")
            with patch.object(q.sc, "binary_identity") as identity:
                with self.assertRaises(q.sc.Failure): q.check_assets(root, root / "missing-client.gz")
                identity.assert_not_called()

    def test_partial_log_never_reports_pass(self):
        probe = {"result": "PASS", "checks": {"probe": "PASS"}}
        with self.assertRaises(q.QualificationFailure): q.summarize("[RUN] incomplete\n", probe)

    def test_failed_runtime_never_reports_pass(self):
        log = "[PASS] ShellCheck:\n[PASS] Generated installers\nRan 1 tests in 1s\nRan 1 tests in 1s\n[PASS] NoBrand test suite\n"
        with self.assertRaises(q.QualificationFailure):
            q.summarize(log, {"result": "PASS", "checks": {"negative_probe": "FAIL"}})

    def test_skipped_quality_gate_never_reports_pass(self):
        log = "[SKIP] ShellCheck\nRan 1 tests in 1s\nRan 1 tests in 1s\n[PASS] NoBrand test suite\n"
        with self.assertRaises(q.QualificationFailure):
            q.summarize(log, {"result": "PASS", "checks": {"probe": "PASS"}})

    def test_completion_marker_cannot_hide_missing_baseline_checks(self):
        baseline = json.loads(q.git("show", q.BASE + ":docs/reports/SPLICORE_RC4_FRESH_RUNTIME_PROBE.json"))
        script = q.git("show", q.BASE + ":scripts/test.sh").decode()
        import re
        entries = re.findall(r"^  (tests/\S+\.sh)$", script, re.M) + ["tests/test_splicore_cert_lifecycle.sh", "tests/test_splicore_qualification.sh"]
        log = "".join("[RUN] " + name + "\n" for name in entries)
        log += "[PASS] ShellCheck:\n[PASS] Generated installers\nRan 27 tests in 1s\nRan 10 tests in 1s\nRan 21 tests in 1s\nRan 13 tests in 1s\nUSER_RUNTIME_LITERAL_LEAK_COUNT=0\n[PASS] NoBrand test suite\n"
        self.assertEqual(q.summarize(log, baseline)["runtime_checks"], 42)
        partial = dict(baseline, checks=dict(baseline["checks"]))
        partial["checks"].pop(next(iter(partial["checks"])))
        for changed_log, changed_probe in ((log, partial), (log.replace("[RUN] " + entries[0] + "\n", ""), baseline),
                                            (log.replace("Ran 27 tests", "Ran 26 tests"), baseline)):
            with self.subTest(log=changed_log[:20]), self.assertRaises(q.QualificationFailure):
                q.summarize(changed_log, changed_probe)

    def test_failure_output_excludes_command_stdout(self):
        with tempfile.TemporaryDirectory() as directory:
            log = Path(directory) / "private.log"
            with self.assertRaises(q.QualificationFailure) as failure:
                q.run_logged([sys.executable, "-c", "print('synthetic-private-output'); raise SystemExit(9)"], log, 10)
            self.assertNotIn("synthetic-private-output", str(failure.exception))
            self.assertIn("synthetic-private-output", log.read_text())

    def test_evidence_cannot_overwrite_existing_directory(self):
        with tempfile.TemporaryDirectory() as directory:
            sentinel = Path(directory) / "keep"
            sentinel.write_text("unchanged")
            process = subprocess.run([sys.executable, str(ROOT / "scripts/qualify-splicore.py"), "static", "--evidence", directory],
                                     capture_output=True, text=True, env=dict(os.environ, PYTHONDONTWRITEBYTECODE="1"), timeout=20)
            self.assertEqual(process.returncode, 1)
            self.assertEqual(json.loads(process.stderr)["classification"], "TEST_HARNESS")
            self.assertEqual(sentinel.read_text(), "unchanged")


if __name__ == "__main__":
    unittest.main(verbosity=2)
