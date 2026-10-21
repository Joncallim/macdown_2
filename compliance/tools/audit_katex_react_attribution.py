#!/usr/bin/env python3
"""Verify the React-derived KaTeX helpers mapped into shipped Mermaid output."""

import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path

from source_map_evidence import mapped_positions, verified_bundle_map, verified_package_files


REACT_COMMIT = "95d82cacd6e9cc6a2fe6366d79510cc9133886cb"
REACT_LICENSE_SHA256 = "c71d239df91726fc519c6eb72d318ec65820627232b2f796219e87dcf35d0ab4"
REACT_ESCAPE_SHA256 = "e688204a98227682553270149ec5574dc2f55755d70f1eb3d305e247c1d68d2f"
REACT_HYPHENATE_SHA256 = "0d715b8369793db1a46d30e8b62a4bd5d096ceff6a7ff403eeb6ae479d40251f"


def digest(body):
    return hashlib.sha256(body).hexdigest()


def checked_file(path, expected):
    body = path.read_bytes()
    if digest(body) != expected:
        raise ValueError(f"Source digest changed: {path.name}")
    return body


def audit(evidence, shipped_path, licence_path):
    mermaid_meta = json.loads((evidence / "mermaid-11.17.2-registry.json").read_text())
    if (mermaid_meta.get("name"), mermaid_meta.get("version")) != ("mermaid", "11.17.2"):
        raise ValueError("Unexpected Mermaid registry identity")
    mermaid = verified_package_files(evidence / "mermaid-11.17.2.tgz", mermaid_meta)
    shipped = shipped_path.read_bytes()
    source_map = verified_bundle_map(shipped, mermaid, "dist/mermaid.min.js")

    katex_dir = evidence / "npm-packages/katex@0.16.47"
    katex_meta = json.loads((katex_dir / "registry.json").read_text())
    if (katex_meta.get("name"), katex_meta.get("version")) != ("katex", "0.16.47"):
        raise ValueError("Unexpected KaTeX registry identity")
    katex = verified_package_files(katex_dir / "package.tgz", katex_meta)
    source_name = "../../../node_modules/.pnpm/katex@0.16.47/node_modules/katex/dist/katex.mjs"
    source_index = source_map["sources"].index(source_name)
    source = source_map["sourcesContent"][source_index].encode()
    if source != katex["dist/katex.mjs"]:
        raise ValueError("Mapped KaTeX source differs from the official package")
    if (b"hyphenate and escape adapted from Facebook's React under Apache 2 license" not in source
            or b"var hyphenate = str => str.replace(uppercase, \"-$1\").toLowerCase();" not in source
            or b"var escape = text => String(text).replace(ESCAPE_REGEX, match => ESCAPE_LOOKUP[match]);" not in source):
        raise ValueError("KaTeX borrowed-code attribution or helpers changed")

    references = Counter()
    for _, _, index, line, _ in mapped_positions(source_map, shipped.decode()):
        if index == source_index and line in (68, 80):  # zero-based KaTeX lines 69 and 81
            references[line + 1] += 1
    if not references[69] or not references[81]:
        raise ValueError("Both borrowed helpers must map to generated Mermaid output")

    react_escape = checked_file(evidence / "react-v0.11.0-escape.js", REACT_ESCAPE_SHA256)
    react_hyphenate = checked_file(evidence / "react-v0.11.0-hyphenate.js", REACT_HYPHENATE_SHA256)
    react_licence = checked_file(evidence / "react-v0.11.0-LICENSE.txt", REACT_LICENSE_SHA256)
    if licence_path.read_bytes() != react_licence:
        raise ValueError("Distributed React Apache text differs from the reference source")
    if (b"Copyright 2013-2014 Facebook, Inc." not in react_escape
            or b"Copyright 2013-2014 Facebook, Inc." not in react_hyphenate
            or b"Licensed under the Apache License, Version 2.0" not in react_escape
            or b"Licensed under the Apache License, Version 2.0" not in react_hyphenate
            or b"function hyphenate(string)" not in react_hyphenate
            or b"function escapeTextForBrowser(text)" not in react_escape):
        raise ValueError("React Apache-era helper source does not match the recorded attribution")

    return {
        "scope": "mapped KaTeX helper attribution only; other Mermaid nested code remains open",
        "react_reference_commit": REACT_COMMIT,
        "react_reference_license_sha256": REACT_LICENSE_SHA256,
        "katex_archive_sha256": digest((katex_dir / "package.tgz").read_bytes()),
        "katex_mapped_source_sha256": digest(source),
        "mermaid_shipped_sha256": digest(shipped),
        "generated_mapping_references": dict(sorted(references.items())),
        "adaptation_limit": "React v0.11.0 matches the credited Apache-era helpers; KaTeX does not name an exact original React revision",
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--evidence-dir", type=Path, required=True)
    parser.add_argument("--shipped", type=Path, required=True)
    parser.add_argument("--licence", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    args.output.write_text(json.dumps(audit(args.evidence_dir, args.shipped, args.licence),
                                      indent=2, sort_keys=True) + "\n")


if __name__ == "__main__":
    main()
