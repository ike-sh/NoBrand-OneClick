#!/usr/bin/env python3
"""Validate the routing relationships in a generated full Mihomo YAML file.

This validates NoBrand's small generated YAML contract rather than merely
searching for one expected string. Mihomo remains the authoritative full parser
in the runtime regression.
"""

from __future__ import annotations

import json
from pathlib import Path
import re
import sys


def fail(message: str) -> None:
    raise SystemExit(f"Mihomo routing contract failed: {message}")


def yaml_scalar(value: str) -> str:
    value = value.strip()
    if not value:
        fail("empty scalar")
    if value.startswith('"'):
        try:
            parsed = json.loads(value)
        except json.JSONDecodeError as error:
            fail(f"invalid quoted scalar: {error}")
        if not isinstance(parsed, str):
            fail("quoted scalar is not a string")
        return parsed
    return value


def main() -> int:
    if len(sys.argv) != 3:
        fail("usage: assert_mihomo_routing_contract.py CONFIG GROUP")
    path = Path(sys.argv[1])
    expected_group = sys.argv[2]
    lines = path.read_text(encoding="utf-8").splitlines()

    modes: list[str] = []
    proxy_names: set[str] = set()
    groups: dict[str, dict[str, object]] = {}
    rules: list[str] = []
    section = ""
    current_group = ""

    for line_number, raw_line in enumerate(lines, start=1):
        if "\t" in raw_line:
            fail(f"tab indentation at line {line_number}")
        line = raw_line.rstrip()
        if not line or line.lstrip().startswith("#"):
            continue

        if not line.startswith(" "):
            current_group = ""
            if line.startswith("mode:"):
                modes.append(yaml_scalar(line.split(":", 1)[1]))
            section = line[:-1] if line.endswith(":") else ""
            continue

        if section == "proxies":
            match = re.fullmatch(r"  - name:\s*(.+)", line)
            if match:
                proxy_names.add(yaml_scalar(match.group(1)))
            continue

        if section == "proxy-groups":
            group_match = re.fullmatch(r"  - name:\s*(.+)", line)
            if group_match:
                current_group = yaml_scalar(group_match.group(1))
                if current_group in groups:
                    fail(f"duplicate proxy group {current_group}")
                groups[current_group] = {}
                continue
            if not current_group:
                fail(f"proxy-group field without a group at line {line_number}")
            type_match = re.fullmatch(r"    type:\s*(.+)", line)
            if type_match:
                groups[current_group]["type"] = yaml_scalar(type_match.group(1))
                continue
            members_match = re.fullmatch(r"    proxies:\s*(\[.*\])", line)
            if members_match:
                try:
                    members = json.loads(members_match.group(1))
                except json.JSONDecodeError as error:
                    fail(f"invalid group member list: {error}")
                if not isinstance(members, list) or not all(isinstance(item, str) for item in members):
                    fail("group members must be a string list")
                groups[current_group]["proxies"] = members
                continue

        if section == "rules":
            rule_match = re.fullmatch(r"  -\s*(.+)", line)
            if rule_match:
                rules.append(rule_match.group(1).strip())

    if modes != ["rule"]:
        fail(f"expected exactly one top-level rule mode, observed {modes!r}")
    if expected_group not in groups:
        fail(f"missing expected proxy group {expected_group}")
    group = groups[expected_group]
    if group.get("type") != "select":
        fail(f"{expected_group} must be a select group")
    members = group.get("proxies")
    if not isinstance(members, list) or not members:
        fail(f"{expected_group} has no proxy members")
    missing_members = sorted(set(members) - proxy_names)
    if missing_members:
        fail(f"group references undefined proxies: {missing_members!r}")
    if any(member.upper() == "DIRECT" for member in members):
        fail(f"{expected_group} contains a DIRECT fallback")
    expected_rule = f"MATCH,{expected_group}"
    if not rules or rules[-1] != expected_rule:
        fail(f"final rule must be {expected_rule}, observed {rules!r}")
    if any(rule.split(",")[-1].upper() == "DIRECT" for rule in rules):
        fail("rules contain a DIRECT fallback")

    print("MIHOMO_ROUTING_CONTRACT=PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
