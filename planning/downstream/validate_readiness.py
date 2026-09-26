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


def validate(data: object, available: set[str] | None = None) -> list[str]:
    # Shape checks run before set/dict/graph operations; malformed plans fail closed.
    if not isinstance(data, dict):
        return ["manifest must be an object"]
    for key in ("handoffs", "units"):
        if not isinstance(data.get(key), list) or not all(isinstance(x, dict) for x in data[key]):
            return [f"{key} must be a list of objects"]
    if not isinstance(data.get("rules"), dict):
        return ["rules must be an object"]
    for row in data["handoffs"]:
        if type(row.get("issue")) is not int or not isinstance(row.get("path"), str):
            return ["invalid handoff field types"]
    for row in data["units"]:
        if (not isinstance(row.get("id"), str) or not row["id"]
                or type(row.get("issue")) is not int
                or not isinstance(row.get("kind"), str)
                or not isinstance(row.get("requires"), list)
                or not all(isinstance(x, str) and x for x in row["requires"])
                or ("probe" in row and not isinstance(row["probe"], str))):
            return ["invalid unit field types"]
        if set(row) - {"id", "issue", "kind", "requires", "probe"}:
            return ["units cannot contain execution claims or unknown fields"]
        if len(row["requires"]) != len(set(row["requires"])):
            return ["duplicate dependency"]
    errors: list[str] = []
    if type(data.get("schema_version")) is not int or data["schema_version"] != 1:
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
    probes = [row for row in units if row["kind"] == "probe"]
    if len(probes) != len(PROBES) or {row.get("probe") for row in probes} != PROBES:
        errors.append("probe inventory mismatch")
    if any("probe" in row for row in units if row["kind"] != "probe"):
        errors.append("probe label on non-probe unit")
    if not EXPECTED <= {row["issue"] for row in units}:
        errors.append("issue has no execution-plan owner")
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
        "post-e22-rebaseline": {"plan-adoption", "e22-complete"},
        "software-S": {"ui-harness", "html-preview", "external-files", "pdf-integration",
                       "appearance-ui", "finder-assets", "cli", "updater-ui"},
        "owner-public-authorization": {"debt-gate-close"},
        "final-localization": {"software-S", "translation-access", "native-reviewers", "interactive-mac"},
        "private-candidates": {"final-localization", "signing-access"},
        "exact-artifact-V": {"private-candidates", "interactive-mac", "ui-harness"},
        "debt-gate-close": {"exact-artifact-V", "final-localization"},
        "public-promotion-P": {"debt-gate-close", "owner-public-authorization"},
    }
    for node, deps in required_edges.items():
        if not deps <= set(nodes.get(node, {}).get("requires", [])):
            errors.append(f"release guard missing at {node}")
    # Membership and acyclicity alone do not ensure a required probe is upstream.
    def ancestors(node: str) -> set[str]:
        found: set[str] = set()
        pending = list(nodes.get(node, {}).get("requires", []))
        while pending:
            dep = pending.pop()
            if dep in found:
                continue
            found.add(dep)
            pending.extend(nodes.get(dep, {}).get("requires", []))
        return found

    boundaries = {
        "resource-reader": (121, "RESOURCE-OPEN"),
        "anchors-navigation": (117, "ANCHOR-PARSER"),
        "math-integration": (116, "MATH-ADAPTER"),
        "pdf-integration": (118, "PDF-PRINT"),
        "diagram-integration": (79, "DIAGRAM-CONTEXT"),
        "ql-integration": (113, "QL-REPLY"),
    }
    for consumer, (owner, probe_name) in boundaries.items():
        matches = [row for row in probes if row.get("probe") == probe_name]
        if (len(matches) != 1 or matches[0]["issue"] != owner
                or nodes.get(consumer, {}).get("issue") != owner
                or nodes.get(consumer, {}).get("kind") != "implementation"
                or matches[0]["id"] not in ancestors(consumer)):
            errors.append(f"probe prerequisite missing or misowned: {consumer}")
    for row in units:
        if row["kind"] in {"implementation", "probe"} and row["id"] != "post-e22-rebaseline":
            if "post-e22-rebaseline" not in ancestors(row["id"]):
                errors.append(f"post-E22 baseline missing: {row['id']}")
    implementation_ids = {row["id"] for row in units if row["kind"] in {"implementation", "probe"}}
    if not implementation_ids <= ancestors("software-S"):
        errors.append("software-S omits implementation or probe work")
    expected_kinds = {
        "e22-complete": (112, "upstream"), "plan-adoption": (115, "input"),
        "post-e22-rebaseline": (115, "implementation"), "software-S": (115, "gate"),
        "final-localization": (17, "verification"), "private-candidates": (18, "verification"),
        "exact-artifact-V": (115, "verification"), "debt-gate-close": (115, "gate"),
        "owner-public-authorization": (18, "input"), "public-promotion-P": (18, "gate"),
    }
    for node, (owner, kind) in expected_kinds.items():
        row = nodes.get(node, {})
        if row.get("issue") != owner or row.get("kind") != kind:
            errors.append(f"gate or boundary identity changed: {node}")
    if any(row["kind"] == "upstream" and row["id"] != "e22-complete" for row in units):
        errors.append("unrecognized upstream work")
    protected = data.get("protected_work")
    required_protected = {"master", "planning/epic-22-implementation.md", "MacDown2/", ".github/", "design/"}
    if not isinstance(protected, list) or not all(isinstance(x, str) for x in protected):
        errors.append("invalid protected-work list")
    elif not required_protected <= set(protected):
        errors.append("protected work missing")
    rules = data.get("rules", {})
    if rules.get("probe_failure") != "stop_dependent_unit_and_review_narrow_architecture_correction":
        errors.append("probe-failure guard changed")
    if rules.get("whole_issue_closure") != "requires_all_own_acceptance_evidence_not_only_implementation":
        errors.append("issue-closure evidence guard changed")
    if rules.get("public_release_authorized") is not False:
        errors.append("plan cannot authorize publication")
    if rules.get("independent_reviewer_claim") is not False:
        errors.append("self-review cannot claim independent review")
    if rules.get("default_unit_execution") != "not_run":
        errors.append("units cannot inherit an execution pass")
    return errors


def self_test(data: dict, available: set[str]) -> int:
    # Explicit checks remain active under python -O; mutate by identity, not row order.
    def require(condition: bool, message: str) -> None:
        if not condition:
            raise ValueError(message)

    require(not validate(data, available), "valid fixture rejected")
    cases: list[tuple[str, object, str]] = []

    def case(name: str, change, expected: str) -> None:
        mutant = copy.deepcopy(data)
        change(mutant)
        cases.append((name, mutant, expected))

    def unit(plan: dict, name: str) -> dict:
        return next(row for row in plan["units"] if row["id"] == name)

    case("missing issue", lambda x: x["handoffs"].pop(), "issue coverage")
    case("duplicate issue", lambda x: x["handoffs"].append(x["handoffs"][0]), "issue coverage")
    case("unknown dependency", lambda x: unit(x, "plan-adoption").update(requires=["missing"]), "unknown dependency")
    case("cycle", lambda x: unit(x, "plan-adoption").update(requires=["public-promotion-P"]), "dependency cycle")
    case("lost authorization", lambda x: unit(x, "public-promotion-P").update(requires=["debt-gate-close"]), "release guard")
    case("publication claim", lambda x: x["rules"].update(public_release_authorized=True), "authorize publication")
    case("runtime claim", lambda x: x.update(execution_evidence="passed"), "runtime proof")
    case("E22 implementation", lambda x: unit(x, "e22-complete").update(kind="implementation"), "active E22")
    case("duplicate unit", lambda x: x["units"].append(copy.deepcopy(x["units"][0])), "duplicate or invalid unit")
    case("independent review", lambda x: x["rules"].update(independent_reviewer_claim=True), "independent review")
    case("unknown probe", lambda x: unit(x, "resource-open").update(probe="INVENTED"), "probe inventory")
    for name in ("resource-reader", "anchors-navigation", "math-integration", "pdf-integration",
                 "diagram-integration", "ql-integration"):
        case("lost probe " + name, lambda x, n=name: unit(x, n).update(requires=["post-e22-rebaseline"]), "probe prerequisite")
    case("empty software gate", lambda x: unit(x, "software-S").update(requires=[]), "release guard")
    case("lost review input", lambda x: unit(x, "final-localization")["requires"].remove("native-reviewers"), "release guard")
    case("lost translation input", lambda x: unit(x, "final-localization")["requires"].remove("translation-access"), "release guard")
    case("lost signing input", lambda x: unit(x, "private-candidates")["requires"].remove("signing-access"), "release guard")
    case("premature consent", lambda x: unit(x, "owner-public-authorization").update(requires=[]), "release guard")
    case("lost baseline", lambda x: unit(x, "palette").update(requires=[]), "post-E22 baseline")
    case("removed E22 prerequisite", lambda x: unit(x, "post-e22-rebaseline").update(requires=["plan-adoption"]), "release guard")
    case("wrong probe owner", lambda x: unit(x, "resource-open").update(issue=118), "probe prerequisite")
    case("duplicate probe", lambda x: x["units"].append(dict(unit(x, "resource-open"), id="extra-probe")), "probe inventory")
    case("unit fake pass", lambda x: unit(x, "ql-reply").update(status="passed"), "execution claims")
    case("lost protected work", lambda x: x.update(protected_work=[]), "protected work")
    case("probe waiver", lambda x: x["rules"].update(probe_failure="continue"), "probe-failure guard")
    case("closure waiver", lambda x: x["rules"].update(whole_issue_closure="implementation_only"), "issue-closure")
    case("reclassified gate", lambda x: unit(x, "software-S").update(kind="input"), "boundary identity")
    case("invalid requires", lambda x: unit(x, "resource-reader").update(requires="resource-open"), "field types")
    case("malformed units", lambda x: x.update(units=[None]), "list of objects")
    case("boolean schema", lambda x: x.update(schema_version=True), "unsupported schema")
    case("duplicate dependency", lambda x: unit(x, "resource-reader")["requires"].append("resource-open"), "duplicate dependency")
    cases.append(("non-object", [], "must be an object"))
    for name, mutant, expected in cases:
        errors = validate(mutant, available)
        require(any(expected in error for error in errors), f"{name}: intended defect not detected: {errors}")
    require(bool(validate(data, available - {data["handoffs"][0]["path"]})), "missing file accepted")
    reordered = copy.deepcopy(data)
    reordered["units"].reverse()
    reordered["handoffs"].reverse()
    require(not validate(reordered, available), "ordering changed semantics")
    return 3 + len(cases)


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
        available = {p.name for p in args.manifest.parent.glob("issue-*-handoff.md") if p.is_file()}
    errors = validate(data, available)
    if errors:
        raise SystemExit("\n".join(errors))
    test_count = self_test(data, available) if args.self_test else 0
    print(json.dumps({"static_validation": "PASS", "file_presence_source": "supplied_list" if args.file_list else "filesystem", "issues": len(data["handoffs"]),
                      "units": len(data["units"]), "probes_not_run": len(PROBES),
                      "self_tests": test_count,
                      "manifest_sha256": hashlib.sha256(raw).hexdigest(),
                      "manifest_git_blob": hashlib.sha1(b"blob " + str(len(raw)).encode() + b"\0" + raw).hexdigest(),
                      "application_tests_run": 0, "public_release_authorized": False}, indent=2))


if __name__ == "__main__":
    main()
