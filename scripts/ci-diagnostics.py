#!/usr/bin/env python3
"""Capture qualification privately, publish a safe projection, then restore status.

No test selection or expectations live here. Never upload the private directory.
Free text uses the validation-log field redaction model, extended with PEM/URI
removal, literal suppression and replacement of every discovered sensitive value.
"""
import argparse
import datetime
import json
import os
from pathlib import Path
import platform
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
CANDIDATE = "e90695ba8d2ac98a443d6aa53edd7653356377b2"
BASE = "b5440ec41aeed2dd266b3a7008f75a26de63add2"
PUBLIC_FILES = (
    "summary.json", "failure-summary.json", "regression.sanitized.log",
    "qualification-console.sanitized.log", "command-diagnostics.sanitized.log",
    "environment-summary.json", "test-result-metadata.json",
)
COMMAND_LOGS = ("actionlint", "systemd-unit", "openrc-unit", "regression")
CLASSES = {
    "IMPLEMENTATION_DEFECT", "TEST_HARNESS_DEFECT", "CI_CONFIGURATION_DEFECT",
    "RUNNER_ENVIRONMENT", "NETWORK_TRANSIENT", "UPSTREAM_DEPENDENCY",
    "NON_REPRODUCIBLE", "UNKNOWN",
}
SENSITIVE = r"(?:[A-Za-z0-9_]*?(?:password|passwd|passphrase|token|secret|psk|salamander|private[_-]?key|public[_-]?key|short[_-]?ids?|uuid|authorization|credential)[A-Za-z0-9_]*|auth|username)"
FIELD = re.compile(r"(?i)(?:[\"']?" + SENSITIVE + r"[\"']?\s*[:=]\s*)(\"(?:\\.|[^\"\\])*\"|'(?:\\.|[^'\\])*'|[^\s,}\]]+)")


def now():
    return datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds")


def save(path, value):
    path.write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")
    path.chmod(0o600)


def read(path, missing):
    # Never follow a private-log symlink into unrelated runner files.
    if not path.is_file() or path.is_symlink():
        missing.append(path.name + " was not produced (or is unsafe)")
        return ""
    with path.open("rb") as stream:
        data = stream.read(8 * 1024 * 1024 + 1)
    if len(data) > 8 * 1024 * 1024:
        missing.append(path.name + " exceeded diagnostic size limit; content suppressed")
        return ""
    return data.decode("utf-8", errors="replace")


def document(text, label, missing):
    try:
        result = json.loads(text)
        if isinstance(result, dict):
            return result
    except ValueError:
        pass
    missing.append(label + " missing or malformed")
    return {}


def sanitizer(texts):
    values = set()
    for text in texts:
        # JSON/string-escaped messages need the same field recognition as logs.
        normalized = text.replace('\\"', '"').replace("\\n", "\n")
        for match in re.finditer(r"(?im)\b(?:authorization|proxy-authorization)\s*:\s*(?:Bearer|Basic)\s+([^\s]+)", normalized):
            values.add(match[1])
        for match in FIELD.finditer(normalized):
            value = match[1].strip("\"'")
            if value:
                values.add(value)
    for key, value in os.environ.items():
        if re.fullmatch(SENSITIVE, key, re.I) and value:
            values.add(value)

    def redact(text):
        text = str(text).replace('\\"', '"').replace("\\n", "\n")
        text = re.sub(r"-----BEGIN [^-\n]+-----[\s\S]*?(?:-----END [^-\n]+-----|\Z)", "[PEM REDACTED]", text)
        text = re.sub(r"(?im)\b(?:authorization|proxy-authorization)\s*:.*$", "[AUTHORIZATION REDACTED]", text)
        for value in sorted(values, key=len, reverse=True):
            text = text.replace(value, "[REDACTED]")
        text = FIELD.sub("[SENSITIVE FIELD REDACTED]", text)
        text = re.sub(r"\b[A-Za-z][A-Za-z0-9+.-]*://[^\s<>\"']+", "[URI REDACTED]", text)
        text = re.sub(r"(?i)\b[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}\b", "[UUID REDACTED]", text)
        text = re.sub(r"\b(?:gh[pousr]_[A-Za-z0-9_]+|github_pat_[A-Za-z0-9_]+|eyJ[A-Za-z0-9_.-]+)\b", "[TOKEN REDACTED]", text)
        # Assertion payloads and traceback source lines may contain unlabeled
        # synthetic or real credentials. Retain test names, messages and frames.
        lines = []
        for line in text.splitlines():
            frame = re.fullmatch(r'\s*File "([^"\n]+)", line (\d+)(?:, in ([A-Za-z0-9_<>]+))?', line)
            if frame:
                match = re.search(r"(?:^|/)((?:tests|scripts|runtime)/[A-Za-z0-9_./-]+\.(?:py|sh))$", frame[1])
                path = match[1] if match and (ROOT / match[1]).is_file() else "[external frame]"
                lines.append("  File " + path + ", line " + frame[2] + ", in " + (frame[3] or "UNKNOWN"))
            elif re.match(r"^\s{4,}\S", line):
                lines.append("    [source/value line suppressed]")
            else:
                line = re.sub(r'"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'', "[LITERAL REDACTED]", line)
                lines.append(line)
        # GitHub workflow commands and control characters must stay inert.
        return "\n".join(lines).replace("::", ": :").translate({i: None for i in range(32) if i not in (9, 10)}) + "\n"
    return redact


def status(evidence):
    try:
        path = evidence / "qualification-exit-code"
        if path.is_symlink():
            return None
        value = path.read_text().strip()
        return int(value) if re.fullmatch(r"(?:0|[1-9][0-9]{0,2})", value) and int(value) <= 255 else None
    except OSError:
        return None


def capture(evidence, command=None):
    evidence.mkdir(parents=True, mode=0o700, exist_ok=False)
    command = command or [sys.executable, str(ROOT / "scripts/qualify-splicore.py"), "ci", "--evidence", str(evidence / "private")]
    started = now()
    with (evidence / "qualification-console.log").open("wb") as stream:
        try:
            result = subprocess.run(command, cwd=ROOT, stdout=stream, stderr=subprocess.STDOUT)
            exit_code = result.returncode if result.returncode >= 0 else 128 - result.returncode
        except OSError:
            exit_code = 127
    (evidence / "qualification-exit-code").write_text(str(exit_code) + "\n")
    save(evidence / "capture.json", {"started_utc": started, "finished_utc": now(), "qualification_exit_code": exit_code})
    # This stage records the status. finish() restores it after publication.
    return 0


def identity():
    try:
        sha = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, timeout=10).decode().strip()
        return sha if re.fullmatch(r"[0-9a-f]{40}", sha) else "UNKNOWN"
    except (OSError, subprocess.SubprocessError):
        return "UNKNOWN"


def environment():
    result = {"os": platform.system(), "kernel": platform.release(), "architecture": platform.machine(),
              "python": platform.python_version(), "euid": os.geteuid()}
    for label, path in (("pid1", "/proc/1/comm"), ("uid_map", "/proc/self/uid_map"),
                        ("unprivileged_userns_clone", "/proc/sys/kernel/unprivileged_userns_clone"),
                        ("apparmor_restrict_unprivileged_userns", "/proc/sys/kernel/apparmor_restrict_unprivileged_userns")):
        try: result[label] = Path(path).read_text()[:4096]
        except OSError: result[label] = "UNAVAILABLE"
    for key in ("RUNNER_OS", "RUNNER_ARCH", "ImageOS", "ImageVersion"):
        result[key] = os.environ.get(key, "UNAVAILABLE")
    try:
        for line in Path("/etc/os-release").read_text().splitlines():
            key, _, value = line.partition("=")
            if key in ("ID", "VERSION_ID"):
                result[key] = value.strip('"')
    except OSError:
        result["os_release"] = "UNAVAILABLE"
    for tool in ("bash", "git", "shellcheck", "actionlint"):
        try:
            run = subprocess.run([tool, "--version"], capture_output=True, text=True, timeout=10)
            result[tool] = run.stdout[:2048] if run.returncode == 0 else "VERSION UNAVAILABLE"
        except (OSError, subprocess.SubprocessError):
            result[tool] = "UNAVAILABLE"
    return result


def publish(evidence):
    evidence.mkdir(parents=True, mode=0o700, exist_ok=True)
    private, public = evidence / "private", evidence / "public"
    if evidence.is_symlink() or private.is_symlink() or public.is_symlink():
        raise ValueError("unsafe diagnostic directory")
    public.mkdir(mode=0o700, exist_ok=False)
    missing = []
    console = read(evidence / "qualification-console.log", missing)
    raw_summary = read(private / "summary.json", missing)
    summary = document(raw_summary, "summary.json", missing)
    regression = read(private / "regression.log", missing)
    if regression and not (private / "regression.command.json").is_file():
        missing.append("regression.command.json was not produced; subprocess status unavailable")
    commands = []
    command_texts = []
    auxiliary = []
    for name in COMMAND_LOGS:
        path = private / (name + ".command.json")
        if path.exists():
            raw = read(path, missing)
            command_texts.append(raw)
            item = document(raw, path.name, missing)
            arguments = item.get("command")
            code = item.get("exit_code")
            commands.append({"log": name + ".log", "command": arguments if isinstance(arguments, list) and all(isinstance(a, str) for a in arguments) else [],
                             "exit_code": code if type(code) is int else None, "timed_out": item.get("timed_out") is True})
        if name != "regression" and (private / (name + ".log")).exists():
            auxiliary.append("=== " + name + " ===\n" + read(private / (name + ".log"), missing))
    if (private / "private-runtime.log").exists():
        auxiliary.append("=== runtime processes ===\n" + read(private / "private-runtime.log", missing))
    env = environment()
    redact = sanitizer([console, raw_summary, regression, *command_texts, *auxiliary, *map(str, env.values())])
    exit_code = status(evidence)
    if exit_code is None:
        missing.append("qualification exit status missing or malformed; final status fails closed")
    failed = [c for c in commands if c.get("exit_code") != 0]
    failure = failed[-1] if failed else {}
    # Legacy TEST_HARNESS only describes where failure was observed; it is
    # insufficient evidence to assign a root cause.
    classification = summary.get("classification", "UNKNOWN")
    classification = classification if isinstance(classification, str) and classification in CLASSES else "UNKNOWN"
    suites = re.findall(r"^\[RUN\] (tests/[A-Za-z0-9_./-]+\.sh)$", regression, re.M)
    cases = re.findall(r"^(?:FAIL|ERROR): ([A-Za-z0-9_.]+)(?: \([^\n]*\))?", regression, re.M)
    messages = [line for line in regression.splitlines() if re.search(r"\[FAIL\]|(?:Error|Exception|Failure):|^FAIL:|^ERROR:", line)]
    sha = identity()
    common = {"candidate_sha": CANDIDATE, "base_sha": BASE, "tested_ci_sha": sha,
              "qualification_exit_code": exit_code, "classification": classification}
    if failure.get("log") == "regression.log":
        suite = suites[-1] if suites else "UNKNOWN"
        if "Traceback (most recent call last):" in regression and "tests/helpers/splicore_rc4_probe.py" in regression:
            suite = "tests/helpers/splicore_rc4_probe.py"
    else:
        suite = "UNKNOWN"
    failure_summary = dict(common, result="PASS" if exit_code == 0 else "FAIL",
                           failing_suite=redact(suite).strip() if exit_code != 0 else None,
                           failing_case=redact(cases[-1]).strip() if cases and exit_code != 0 else None,
                           failing_suite_command=["bash", redact(suite).strip()] if exit_code != 0 and suite.endswith(".sh") else None,
                           failing_command=[redact(a).strip() for a in failure.get("command", [])] or None,
                           command_exit_code=failure.get("exit_code"), timed_out=bool(failure.get("timed_out")),
                           sanitized_message=redact("\n".join(messages[-12:]) or summary.get("detail", "No failure message available")),
                           evidence_files=list(PUBLIC_FILES), missing_evidence=missing)
    save(public / "failure-summary.json", failure_summary)
    # Explicit projection: never serialize arbitrary fields from private JSON.
    save(public / "summary.json", dict(common, result="PASS" if exit_code == 0 else "FAIL",
                                       qualification_result=redact(summary.get("result", "UNAVAILABLE")).strip(),
                                       missing_evidence=missing, evidence_files=list(PUBLIC_FILES)))
    save(public / "environment-summary.json", {k: redact(v).strip() if isinstance(v, str) else v for k, v in env.items()})
    metadata = {"observed_bash_suites": [redact(s).strip() for s in suites], "observed_python_cases": [redact(c).strip() for c in cases],
                "python_runs": [int(n) for n in re.findall(r"^Ran (\d+) tests in ", regression, re.M)],
                "completion_marker": regression.endswith("[PASS] NoBrand test suite\n"),
                "commands": [{"log": c["log"], "exit_code": c.get("exit_code"), "timed_out": bool(c.get("timed_out")),
                              "command": [redact(a).strip() for a in c.get("command", [])]} for c in commands]}
    save(public / "test-result-metadata.json", metadata)
    for name, raw in (("regression.sanitized.log", regression or "regression.log was not produced"),
                      ("qualification-console.sanitized.log", console or "qualification console was not produced"),
                      ("command-diagnostics.sanitized.log", "\n".join(auxiliary) or "No auxiliary command logs produced")):
        (public / name).write_text(redact(raw), encoding="utf-8")
    print(json.dumps(failure_summary, indent=2))
    return 0


def finish(evidence):
    code = status(evidence)
    if code is None:
        print("Qualification status unavailable; refusing to report success", file=sys.stderr)
        return 1
    print("Qualification exit code: " + str(code))
    return code


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("run", "publish", "finish"))
    parser.add_argument("--evidence", type=Path, required=True)
    args = parser.parse_args()
    os.umask(0o077)
    return {"run": capture, "publish": publish, "finish": finish}[args.mode](args.evidence)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError, subprocess.SubprocessError):
        # Do not let exception formatting disclose private data or arguments.
        print("CI diagnostic operation failed; private evidence retained", file=sys.stderr)
        sys.exit(1)
