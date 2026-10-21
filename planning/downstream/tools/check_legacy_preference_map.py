#!/usr/bin/env python3
"""Check #53 declaration coverage, never read or write a preferences domain.

This intentionally parses the pinned MPPreferences header/implementation shape,
not arbitrary Objective-C. A new source shape requires explicit reconciliation.
Passing proves coverage and current destination spelling, not import semantics.
"""

from __future__ import annotations

import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import re
import subprocess


def sha(body: bytes) -> str:
    return hashlib.sha256(body).hexdigest()


def declarations(header: str, implementation: str) -> dict:
    calculated = header.index("// Calculated values.")
    transient = header.index("// Convinience methods.")
    properties = list(re.finditer(r"^@property\s+\([^)]*\)\s+(.*?)\b(\w+)\s*;", header, re.M))
    dynamic = re.findall(r"^@dynamic\s+(\w+)\s*;", implementation, re.M)
    names = [match[2] for match in properties]
    if len(properties) != len(re.findall(r"^@property\b", header, re.M)):
        raise ValueError("unparsed property declaration")
    if len(set(names)) != len(names) or len(set(dynamic)) != len(dynamic):
        raise ValueError("duplicate source declaration")
    if not set(dynamic) <= set(names):
        raise ValueError("dynamic property absent from header")
    result = {}
    for match in properties:
        if match[2] in dynamic:
            kind = "stored"
        elif calculated < match.start() < transient:
            kind = "calculated"
        elif match.start() > transient:
            kind = "transient"
        else:
            raise ValueError("unclassified non-dynamic property")
        result[match[2]] = {"kind": kind, "declaration_type": match[1].strip()}
    return result


def validate(record: dict, header: bytes, implementation: bytes, repo: Path) -> dict:
    if record.get("schema") != 1 or record.get("scope") != "declaration_coverage_only" or record.get("migration_complete") is not False:
        raise ValueError("coverage must not claim migration completion")
    source = record["legacy_source"]
    if sha(header) != source["header_sha256"] or sha(implementation) != source["implementation_sha256"]:
        raise ValueError("legacy source digest mismatch")
    actual = declarations(header.decode(), implementation.decode())
    entries = record["entries"]
    names = [entry["key"] for entry in entries]
    if len(names) != len(set(names)):
        raise ValueError("duplicate disposition key")
    if set(names) != set(actual):
        raise ValueError(f"key coverage mismatch: missing={sorted(set(actual) - set(names))}, extra={sorted(set(names) - set(actual))}")
    allowed = {
        "stored": {"candidate_equivalent", "unconditional_capability", "owned_policy_pending",
                   "legacy_provenance_only", "unsupported_current_surface"},
        "calculated": {"derive_from_stored_value"},
        "transient": {"never_replay"},
    }
    for entry in entries:
        key = entry["key"]
        for field in ("kind", "declaration_type"):
            if entry[field] != actual[key][field]:
                raise ValueError(f"source classification/type mismatch: {key}")
        if entry["disposition"] not in allowed[entry["kind"]]:
            raise ValueError(f"unclassified disposition: {key}")
        if not entry.get("rationale") or not entry.get("owner") or entry.get("implementation_status") != "not_implemented":
            raise ValueError(f"missing rationale/owner or unsupported implementation claim: {key}")
        candidate = entry.get("destination_candidate")
        if entry["disposition"] == "candidate_equivalent":
            if key == "editorShowWordCount":
                raise ValueError("word-count visibility cannot map to whole status-bar visibility")
            if entry.get("destination_source") != "MacDown2/Packages/MacDownKit/Sources/AppSettings/EditorSettings.swift":
                raise ValueError("destination outside inspected settings surface")
            if not isinstance(candidate, str) or not re.fullmatch(r"EditorSettings\.[A-Za-z]\w*", candidate):
                raise ValueError("invalid destination candidate")
            code = (repo / entry["destination_source"]).read_text()
            field = candidate.split(".")[1]
            if not re.search(r"public var " + re.escape(field) + r"\s*:", code):
                raise ValueError(f"destination property absent: {candidate}")
            if not entry.get("semantic_verification"):
                raise ValueError("candidate requires outstanding semantic evidence")
        elif candidate is not None or entry.get("destination_source") is not None:
            raise ValueError("non-equivalent disposition cannot install a destination")
    return {"status": "declaration coverage passed; import remains unimplemented",
            "properties": len(entries), "kinds": dict(Counter(entry["kind"] for entry in entries)),
            "dispositions": dict(Counter(entry["disposition"] for entry in entries))}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, default=Path(__file__).resolve().parents[3])
    parser.add_argument("--map", type=Path)
    parser.add_argument("--header", type=Path)
    parser.add_argument("--implementation", type=Path)
    args = parser.parse_args()
    if bool(args.header) != bool(args.implementation):
        parser.error("supply both captured source files or neither")
    record = json.loads((args.map or args.repo / "planning/downstream/legacy-preference-dispositions.json").read_text())
    source = record["legacy_source"]
    if args.header:
        header, implementation = args.header.read_bytes(), args.implementation.read_bytes()
    else:
        # Read only Git objects already present locally. No checkout, fetch or execution.
        def blob(path):
            return subprocess.check_output(["git", "show", source["commit"] + ":" + path], cwd=args.repo)
        header, implementation = blob(source["header_path"]), blob(source["implementation_path"])
    print(json.dumps(validate(record, header, implementation, args.repo), indent=2))


if __name__ == "__main__":
    main()
