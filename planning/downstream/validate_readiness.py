#!/usr/bin/env python3
"""Validate architecture coverage and ordering, never application readiness."""
import argparse
import copy
import hashlib
import json
import re
from pathlib import Path

EXPECTED = {17, 18, 53, 79, 88, 113, 115, 116, 117, 118, 119, 120, 121}
PROBES = {"RESOURCE-OPEN", "ANCHOR-PARSER", "MATH-ADAPTER", "PDF-PRINT", "DIAGRAM-CONTEXT", "QL-REPLY"}


def validate(data: dict, available: set[str] | None = None) -> list[str]:
    errors: list[str] = []
    if data.get("schema_version") != 1:
        errors.append("unsupported schema")
    for key in ("reviewed_master", "original_architecture"):
        if not re.fullmatch(r"[0-9a-f]{40}", str(data.get(key, ""))):
            errors.append(f"invalid {key}")
    if data.get("scope") != "architecture_readiness_only" or data.get("execution_evidence") != "not_run":
        errors.append("architecture manifest cannot claim runtime proof")
    handoffs = data.get("handoffs", [])
    issues = [row.get("issue") for row in handoffs]
    if set(issues) != EXPECTED or len(issues) != len(EXPECTED):
        errors.append("incomplete or duplicate issue coverage")
    for row in handoffs:
        path = row.get("path", "")
        if path != f"issue-{row.get('issue')}-handoff.md":
            errors.append(f"invalid handoff path: {path}")
        if available is not None and path not in available:
            errors.append(f"missing handoff file: {path}")
    units = data.get("units", [])
    ids = [row.get("id") for row in units]
    if len(ids) != len(set(ids)) or any(not isinstance(x, str) or not x for x in ids):
        errors.append("duplicate or invalid unit id")
    nodes = {row.get("id"): row for row in units}
    kinds = {"input", "upstream", "probe", "implementation", "verification", "gate"}
    for row in units:
        if row.get("kind") not in kinds:
            errors.append(f"unknown unit kind: {row.get('id')}")
        if row.get("issue") not in EXPECTED | {112}:
            errors.append(f"unknown issue owner: {row.get('id')}")
        for dep in row.get("requires", []):
            if dep not in nodes:
                errors.append(f"unknown dependency {dep}")
        if row.get("issue") == 112 and row.get("kind") != "upstream":
            errors.append("active E22 may only be an upstream dependency")
    if {row.get("probe") for row in units if row.get("kind") == "probe"} != PROBES:
        errors.append("probe inventory mismatch")
    visiting: set[str] = set()
    visited: set[str] = set()

    def walk(node: str) -> None:
        if node in visiting:
            raise ValueError(f"dependency cycle at {node}")
        if node in visited or node not in nodes:
            return
        visiting.add(node)
        for dep in nodes[node].get("requires", []):
            walk(dep)
        visiting.remove(node)
        visited.add(node)

    try:
        for node in nodes:
            walk(node)
    except ValueError as exc:
        errors.append(str(exc))
    # Preserve the exact ordering that breaks the former localization loop.
    required_edges = {
        "final-localization": {"software-S"},
        "private-candidates": {"final-localization", "signing-access"},
        "exact-artifact-V": {"private-candidates", "interactive-mac"},
        "debt-gate-close": {"exact-artifact-V", "final-localization"},
        "public-promotion-P": {"debt-gate-close", "owner-public-authorization"},
    }
    for node, deps in required_edges.items():
        if not deps <= set(nodes.get(node, {}).get("requires", [])):
            errors.append(f"release guard missing at {node}")
    rules = data.get("rules", {})
    if rules.get("public_release_authorized") is not False:
        errors.append("plan cannot authorize publication")
    if rules.get("independent_reviewer_claim") is not False:
        errors.append("self-review cannot claim independent review")
    if rules.get("default_unit_execution") != "not_run":
        errors.append("units cannot inherit an execution pass")
    return errors


def self_test(data: dict, available: set[str]) -> int:
    if not __debug__:
        raise ValueError("Self-tests require assertions; run Python without -O.")
    assert not validate(data, available), "valid fixture rejected"
    mutations = []
    a = copy.deepcopy(data); a["handoffs"].pop(); mutations.append(a)
    a = copy.deepcopy(data); a["handoffs"].append(a["handoffs"][0]); mutations.append(a)
    a = copy.deepcopy(data); a["units"][0]["requires"] = ["missing"]; mutations.append(a)
    a = copy.deepcopy(data); a["units"][0]["requires"] = ["public-promotion-P"]; mutations.append(a)
    a = copy.deepcopy(data); a["units"][-1]["requires"] = ["debt-gate-close"]; mutations.append(a)
    a = copy.deepcopy(data); a["rules"]["public_release_authorized"] = True; mutations.append(a)
    a = copy.deepcopy(data); a["execution_evidence"] = "passed"; mutations.append(a)
    a = copy.deepcopy(data); a["units"][1]["kind"] = "implementation"; mutations.append(a)
    a = copy.deepcopy(data); a["units"][13]["id"] = a["units"][12]["id"]; mutations.append(a)
    a = copy.deepcopy(data); a["rules"]["independent_reviewer_claim"] = True; mutations.append(a)
    a = copy.deepcopy(data); a["units"][12]["probe"] = "INVENTED"; mutations.append(a)
    for index, mutant in enumerate(mutations, 1):
        assert validate(mutant, available), f"bad fixture {index} accepted"
    assert validate(data, available - {data["handoffs"][0]["path"]}), "missing file accepted"
    return 1 + len(mutations) + 1


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifest", type=Path)
    parser.add_argument("--file-list", type=Path, help="One actual repository-relative handoff basename per line")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    raw = args.manifest.read_bytes()
    data = json.loads(raw)
    if args.file_list:
        available = set(args.file_list.read_text().splitlines())
    else:
        available = {p.name for p in args.manifest.parent.glob("issue-*-handoff.md")}
    errors = validate(data, available)
    if errors:
        raise SystemExit("\n".join(errors))
    test_count = self_test(data, available) if args.self_test else 0
    print(json.dumps({"static_validation": "PASS", "issues": len(data["handoffs"]),
                      "units": len(data["units"]), "probes_not_run": len(PROBES),
                      "self_tests": test_count,
                      "manifest_sha256": hashlib.sha256(raw).hexdigest(),
                      "manifest_git_blob": hashlib.sha1(b"blob " + str(len(raw)).encode() + b"\0" + raw).hexdigest(),
                      "application_tests_run": 0, "public_release_authorized": False}, indent=2))


if __name__ == "__main__":
    main()
