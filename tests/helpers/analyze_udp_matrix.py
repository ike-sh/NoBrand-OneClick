#!/usr/bin/env python3
"""Summarize reference-probe JSONL without exposing payload or credentials."""

from __future__ import annotations

import argparse
import collections
import json
from pathlib import Path
from typing import Any


STATUSES = ("PASS", "MISMATCH", "TIMEOUT", "ERROR")


def sorted_unique(values: list[Any]) -> list[Any]:
    return sorted({value for value in values if value is not None})


def summarize(path: Path, focus_sizes: set[int]) -> dict[str, Any]:
    trials: list[dict[str, Any]] = []
    with path.open("r", encoding="utf-8") as source:
        for line_number, line in enumerate(source, 1):
            if not line.strip():
                continue
            record = json.loads(line)
            if "STATUS" in record:
                trials.append(record)

    by_size: dict[int, list[dict[str, Any]]] = collections.defaultdict(list)
    for trial in trials:
        by_size[int(trial["SIZE"])].append(trial)

    matrix: dict[str, dict[str, int]] = {}
    failure_profiles: dict[str, dict[str, Any]] = {}
    focus_trials: dict[str, list[dict[str, Any]]] = {}
    for size in sorted(by_size):
        rows = by_size[size]
        counts = collections.Counter(str(row["STATUS"]) for row in rows)
        matrix[str(size)] = {status: counts.get(status, 0) for status in STATUSES}

        mismatches = [row for row in rows if row["STATUS"] == "MISMATCH"]
        if mismatches:
            failure_profiles[str(size)] = {
                "MISMATCH_COUNT": len(mismatches),
                "DIFFERENCE_COUNTS": sorted_unique([row.get("DIFFERENCE_COUNT") for row in mismatches]),
                "FIRST_DIFF_OFFSETS": sorted_unique(
                    [row.get("FIRST_DIFFERING_PAYLOAD_OFFSET") for row in mismatches]
                ),
                "LAST_DIFF_OFFSETS": sorted_unique(
                    [row.get("LAST_DIFFERING_PAYLOAD_OFFSET") for row in mismatches]
                ),
                "EXPECTED_LENGTHS": sorted_unique(
                    [row.get("EXPECTED_PAYLOAD_LENGTH") for row in mismatches]
                ),
                "PARSED_LENGTHS": sorted_unique(
                    [row.get("PARSED_PAYLOAD_LENGTH") for row in mismatches]
                ),
            }

        if size in focus_sizes:
            focus_trials[str(size)] = [
                {
                    "ATTEMPT": row.get("ATTEMPT"),
                    "SEED": row.get("SEED"),
                    "STATUS": row.get("STATUS"),
                    "SOCKS_HEADER_LENGTH": row.get("SOCKS_HEADER_LENGTH"),
                    "EXPECTED_PAYLOAD_LENGTH": row.get("EXPECTED_PAYLOAD_LENGTH"),
                    "PARSED_PAYLOAD_LENGTH": row.get("PARSED_PAYLOAD_LENGTH"),
                    "DIFFERENCE_COUNT": row.get("DIFFERENCE_COUNT"),
                    "FIRST_DIFF": row.get("FIRST_DIFFERING_PAYLOAD_OFFSET"),
                    "LAST_DIFF": row.get("LAST_DIFFERING_PAYLOAD_OFFSET"),
                    "RESPONSE_ATYP": row.get("RESPONSE_ATYP"),
                }
                for row in rows
            ]

    all_pass_sizes = [
        size
        for size, rows in by_size.items()
        if rows and all(row["STATUS"] == "PASS" for row in rows)
    ]
    failing_sizes = [
        size
        for size, rows in by_size.items()
        if any(row["STATUS"] != "PASS" for row in rows)
    ]
    timeout_sizes = [
        size
        for size, rows in by_size.items()
        if any(row["STATUS"] == "TIMEOUT" for row in rows)
    ]

    return {
        "TRIAL_COUNT": len(trials),
        "MATRIX": matrix,
        "SOCKS_HEADER_LENGTHS": sorted_unique(
            [row.get("SOCKS_HEADER_LENGTH") for row in trials]
        ),
        "SOCKS_RESPONSE_ATYPS": sorted_unique([row.get("RESPONSE_ATYP") for row in trials]),
        "LARGEST_ALWAYS_PASS_PAYLOAD": max(all_pass_sizes) if all_pass_sizes else None,
        "FIRST_FAILING_PAYLOAD": min(failing_sizes) if failing_sizes else None,
        "FIRST_TIMEOUT_PAYLOAD": min(timeout_sizes) if timeout_sizes else None,
        "FAILURE_PROFILES": failure_profiles,
        "FOCUS_TRIALS": focus_trials,
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("jsonl", type=Path)
    parser.add_argument("--label", default="UDP_MATRIX")
    parser.add_argument("--focus-size", type=int, action="append", default=[1200])
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    report = {args.label: summarize(args.jsonl, set(args.focus_size))}
    print(json.dumps(report, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
