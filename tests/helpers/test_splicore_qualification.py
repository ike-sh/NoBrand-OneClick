#!/usr/bin/env python3
"""Safety and evidence tests for the qualification infrastructure."""
import hashlib
import contextlib
import importlib.util
import io
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
spec = importlib.util.spec_from_file_location("diagnostics", ROOT / "scripts/ci-diagnostics.py")
d = importlib.util.module_from_spec(spec)
spec.loader.exec_module(d)


class QualificationTests(unittest.TestCase):
    def test_frozen_identity_and_all_protected_bytes(self):
        result = q.review_integrity()
        self.assertEqual(result["unapproved_changes"], 0)
        self.assertEqual(result["historical_reports"], 16)
        with self.assertRaises(q.QualificationFailure): q.frozen_integrity()

    def test_lifecycle_fix_accepts_only_exact_reviewed_state_bytes(self):
        self.assertEqual(set(q.lifecycle_fix_integrity()), {"src/15-core-state.sh"})
        scope = (ROOT / "tests/fixtures/splicore-rc4-lifecycle-fix.json").read_bytes()
        for replacement in (b"unauthorized lifecycle change", None, "symlink"):
            with self.subTest(replacement=replacement), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                path = root / "src/15-core-state.sh"
                path.parent.mkdir()
                fixture = root / "tests/fixtures/splicore-rc4-lifecycle-fix.json"
                fixture.parent.mkdir(parents=True)
                fixture.write_bytes(scope)
                if replacement == "symlink":
                    path.symlink_to(ROOT / "src/15-core-state.sh")
                elif replacement is not None:
                    path.write_bytes(replacement)
                with patch.object(q, "ROOT", root), self.assertRaises(q.QualificationFailure):
                    q.lifecycle_fix_integrity()

    def test_lifecycle_fix_cannot_exempt_other_product_paths(self):
        scope = json.loads((ROOT / "tests/fixtures/splicore-rc4-lifecycle-fix.json").read_text())
        for field, value in (("base_commit", q.BASE), ("product_files", {"src/05-constants.sh": "0" * 64})):
            with self.subTest(field=field), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                path = root / "tests/fixtures/splicore-rc4-lifecycle-fix.json"
                path.parent.mkdir(parents=True)
                path.write_text(json.dumps(dict(scope, **{field: value})))
                with patch.object(q, "ROOT", root), self.assertRaises(q.QualificationFailure):
                    q.lifecycle_fix_integrity()

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
        log += "[PASS] ShellCheck:\n[PASS] Generated installers\nRan 27 tests in 1s\nRan 10 tests in 1s\nRan 21 tests in 1s\nRan 13 tests in 1s\nRan 20 tests in 1s\nUSER_RUNTIME_LITERAL_LEAK_COUNT=0\n[PASS] NoBrand test suite\n"
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

    def test_failed_command_retains_exact_exit_and_argv_privately(self):
        with tempfile.TemporaryDirectory() as directory:
            log = Path(directory) / "regression.log"
            command = [sys.executable, "-c", "raise SystemExit(23)"]
            with self.assertRaises(q.QualificationFailure): q.run_logged(command, log, 10)
            metadata = json.loads(log.with_suffix(".command.json").read_text())
            self.assertEqual(metadata["exit_code"], 23)
            self.assertEqual(metadata["command"], command)

    def test_timeout_metadata_does_not_invent_a_subprocess_exit(self):
        with tempfile.TemporaryDirectory() as directory:
            log = Path(directory) / "regression.log"
            with self.assertRaises(q.QualificationFailure):
                q.run_logged([sys.executable, "-c", "import time; time.sleep(5)"], log, .05)
            metadata = json.loads(log.with_suffix(".command.json").read_text())
            self.assertTrue(metadata["timed_out"])
            self.assertIsNone(metadata["exit_code"])

    def test_metadata_write_failure_cannot_mask_original_command_failure(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(q.sc, "save", side_effect=OSError("fixture disk failure")):
            with self.assertRaises(q.QualificationFailure) as failure:
                q.run_logged([sys.executable, "-c", "raise SystemExit(23)"], Path(directory) / "regression.log", 10)
            self.assertIn("command failed", str(failure.exception))

    def diagnostics_fixture(self, parent, exit_code):
        evidence = parent / "evidence"
        fixture = parent / "fixture.py"
        # The child really exits; no mocked returncode or pipeline can hide it.
        fixture.write_text("import pathlib,sys\np=pathlib.Path(sys.argv[1])\np.mkdir()\n"
                           "(p/'summary.json').write_text(sys.argv[2])\n"
                           "(p/'regression.log').write_text(sys.argv[3])\n"
                           "(p/'regression.command.json').write_text(sys.argv[4])\n"
                           "print(sys.argv[3])\nraise SystemExit(int(sys.argv[5]))\n")
        private = evidence / "private"
        log = "[RUN] tests/test_splicore_qualification.sh\nFAIL: test_fixture (__main__.Fixture)\nAssertionError: fixture mismatch\n"
        if exit_code == 0: log = "[RUN] tests/test_splicore_qualification.sh\n[PASS] NoBrand test suite\n"
        command = [sys.executable, str(fixture), str(private), json.dumps({"result": "PASS" if exit_code == 0 else "FAIL", "classification": "TEST_HARNESS"}),
                   log, json.dumps({"command": ["bash", "scripts/test.sh", "--runtime"], "exit_code": 23 if exit_code else 0}), str(exit_code)]
        self.assertEqual(d.capture(evidence, command), 0)
        return evidence

    def test_diagnostic_success_capture_publish_and_final_status(self):
        with tempfile.TemporaryDirectory() as directory:
            evidence = self.diagnostics_fixture(Path(directory), 0)
            with contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(d.publish(evidence), 0)
                self.assertEqual(d.finish(evidence), 0)
            summary = json.loads((evidence / "public/failure-summary.json").read_text())
            self.assertEqual(summary["result"], "PASS")
            self.assertIsNone(summary["failing_suite"])
            self.assertEqual(set(p.name for p in (evidence / "public").iterdir()), set(d.PUBLIC_FILES))

    def test_diagnostic_failure_upload_preparation_preserves_original_status(self):
        with tempfile.TemporaryDirectory() as directory:
            evidence = self.diagnostics_fixture(Path(directory), 9)
            with contextlib.redirect_stdout(io.StringIO()): self.assertEqual(d.publish(evidence), 0)
            final = subprocess.run([sys.executable, str(ROOT / "scripts/ci-diagnostics.py"), "finish", "--evidence", str(evidence)], capture_output=True, timeout=10)
            self.assertEqual(final.returncode, 9)
            summary = json.loads((evidence / "public/failure-summary.json").read_text())
            self.assertEqual(summary["qualification_exit_code"], 9)
            self.assertEqual(summary["command_exit_code"], 23)
            self.assertEqual(summary["failing_suite"], "tests/test_splicore_qualification.sh")
            self.assertEqual(summary["failing_case"], "test_fixture")
            self.assertEqual(summary["failing_command"], ["bash", "scripts/test.sh", "--runtime"])
            self.assertEqual(summary["classification"], "UNKNOWN")
            self.assertEqual(summary["candidate_sha"], d.CANDIDATE)

    def test_diagnostics_missing_summary_and_log_keep_original_failure(self):
        with tempfile.TemporaryDirectory() as directory:
            evidence = self.diagnostics_fixture(Path(directory), 7)
            (evidence / "private/summary.json").unlink()
            (evidence / "private/regression.log").unlink()
            with contextlib.redirect_stdout(io.StringIO()):
                d.publish(evidence)
                self.assertEqual(d.finish(evidence), 7)
            result = json.loads((evidence / "public/failure-summary.json").read_text())
            self.assertTrue(any("regression.log was not produced" in m for m in result["missing_evidence"]))
            self.assertEqual(result["classification"], "UNKNOWN")

    def test_diagnostics_absent_exit_never_reports_success(self):
        with tempfile.TemporaryDirectory() as directory:
            evidence = Path(directory) / "absent"
            with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
                d.publish(evidence)
                self.assertEqual(d.finish(evidence), 1)
            self.assertEqual(json.loads((evidence / "public/summary.json").read_text())["result"], "FAIL")

    def test_diagnostics_malformed_partial_summary_is_reported(self):
        with tempfile.TemporaryDirectory() as directory:
            evidence = self.diagnostics_fixture(Path(directory), 6)
            (evidence / "private/summary.json").write_text('{"result":')
            with contextlib.redirect_stdout(io.StringIO()): d.publish(evidence)
            result = json.loads((evidence / "public/failure-summary.json").read_text())
            self.assertIn("summary.json missing or malformed", result["missing_evidence"])
            self.assertEqual(d.status(evidence), 6)

    def test_partial_command_metadata_is_projected_without_untyped_values(self):
        with tempfile.TemporaryDirectory() as directory:
            evidence = self.diagnostics_fixture(Path(directory), 6)
            (evidence / "private/summary.json").write_text(json.dumps({"classification": ["not-a-classification"]}))
            (evidence / "private/regression.command.json").write_text(json.dumps({"command": None, "exit_code": "untyped-value-must-not-publish"}))
            with contextlib.redirect_stdout(io.StringIO()): d.publish(evidence)
            contents = "".join(p.read_text() for p in (evidence / "public").iterdir())
            self.assertNotIn("untyped-value-must-not-publish", contents)
            summary = json.loads((evidence / "public/failure-summary.json").read_text())
            self.assertIsNone(summary["failing_command"])
            self.assertIsNone(summary["command_exit_code"])
            self.assertEqual(summary["classification"], "UNKNOWN")

    def test_synthetic_secrets_absent_from_all_public_files_and_console(self):
        fields = ("password", "PSK", "token", "salamander", "privateKey", "uuid", "authorization")
        secrets = ["fixture-" + field + "-sensitive-91827" for field in fields]
        pem_body = "SYNTHETIC_PRIVATE_MATERIAL_91827"
        payload = "\n".join(field + "=" + value for field, value in zip(fields, secrets))
        payload += "\n" + "\n".join(secrets)  # Unlabeled repeats must also disappear.
        payload += "\n-----BEGIN " + "PRIVATE KEY-----\n" + pem_body + "\n-----END " + "PRIVATE KEY-----\n"
        payload += "\nAssertionError: expected 'unlabeled-assertion-value-91827'\n"
        with tempfile.TemporaryDirectory() as directory:
            evidence = self.diagnostics_fixture(Path(directory), 9)
            for name in ("regression.log", "private-runtime.log", "actionlint.log"):
                (evidence / "private" / name).write_text(payload)
            (evidence / "qualification-console.log").write_text(payload)
            (evidence / "private/summary.json").write_text(json.dumps({"result": "FAIL", "detail": payload, "unreviewed": secrets}))
            output = io.StringIO()
            with contextlib.redirect_stdout(output): d.publish(evidence)
            contents = output.getvalue() + "".join(p.read_text() for p in (evidence / "public").iterdir())
            for secret in [*secrets, pem_body, "unlabeled-assertion-value-91827"]:
                self.assertNotIn(secret, contents)
            self.assertNotIn("unreviewed", contents)
            self.assertEqual(set(p.name for p in (evidence / "public").iterdir()), set(d.PUBLIC_FILES))

    def test_redaction_preserves_failure_frames_and_suppresses_source(self):
        text = '  File "' + str(ROOT / 'tests/helpers/test_splicore_qualification.py') + '", line 12, in test_fixture\n'
        text += '    print("unlabeled-source-secret")\nAssertionError: diagnostic label\n'
        redacted = d.sanitizer([text])(text)
        self.assertIn("tests/helpers/test_splicore_qualification.py, line 12", redacted)
        self.assertIn("AssertionError: diagnostic label", redacted)
        self.assertNotIn("unlabeled-source-secret", redacted)

    def test_redaction_truncated_pem_uri_bearer_and_environment(self):
        text = "Authorization: Bearer fixture-bearer-91827\nhttps://user:fixture-uri-91827@example.invalid/x\n"
        text += "unlabeled fixture-env-91827\n-----BEGIN " + "EC PRIVATE KEY-----\nfixture-pem-91827"
        with patch.dict(os.environ, {"FIXTURE_TOKEN": "fixture-env-91827"}):
            redacted = d.sanitizer([text])(text)
        for value in ("fixture-bearer-91827", "fixture-uri-91827", "fixture-env-91827", "fixture-pem-91827"):
            self.assertNotIn(value, redacted)

    def test_workflow_cannot_skip_or_widen_publication_or_swallow_exit(self):
        text = (ROOT / ".github/workflows/ci.yml").read_text()
        changes = (text.replace("if: always()", "if: success()"),
                   text.replace("run: python3 scripts/ci-diagnostics.py finish", "run: true #"),
                   text.replace("public/summary.json", "private/summary.json"),
                   text.replace("if-no-files-found: error", "if-no-files-found: ignore"),
                   text.replace("      - name: Publish sanitized diagnostics", "      - continue-on-error: true\n        name: Publish sanitized diagnostics"))
        for changed in changes:
            with self.subTest(changed=changed[-100:]), self.assertRaises(q.QualificationFailure): q.workflow_contract(changed)

    def test_private_log_symlink_is_not_published(self):
        with tempfile.TemporaryDirectory() as directory:
            evidence = self.diagnostics_fixture(Path(directory), 9)
            other = Path(directory) / "unrelated"
            other.write_text("unrelated-sensitive-file")
            log = evidence / "private/regression.log"
            log.unlink(); log.symlink_to(other)
            with contextlib.redirect_stdout(io.StringIO()): d.publish(evidence)
            self.assertNotIn("unrelated-sensitive-file", (evidence / "public/regression.sanitized.log").read_text())


if __name__ == "__main__":
    unittest.main(verbosity=2)
