#!/usr/bin/env python3
"""Reproduce the bounded Mermaid 11.17.2 module/notice evidence offline.

Input is the captured npm evidence layout documented in MERMAID_NESTED_AUDIT.md.
No package is installed or executed; no network or inventory mutation occurs.
The report deliberately remains incomplete for embedded-attribution closure.
"""

from __future__ import annotations

import argparse
from collections import Counter, defaultdict
import hashlib
import json
from pathlib import Path
import re

from source_map_evidence import MappingIndex, mapped_positions, verified_bundle_map, verified_package_files


def sha(body: bytes) -> str:
    return hashlib.sha256(body).hexdigest()


def package_identity(source: str):
    match = re.search(r"/node_modules/\.pnpm/([^/]+)/node_modules/(.+)", source)
    if not match:
        return None
    name, version = match[1].split("_", 1)[0].rsplit("@", 1)
    name = name.replace("+", "/")
    if not match[2].startswith(name + "/"):
        raise ValueError("source-map store identity disagrees with package path")
    return name, version, match[2][len(name) + 1:]


def embedded_sources(files: dict[str, bytes], content_hash: str) -> list[dict]:
    matches = []
    for path, body in sorted(files.items()):
        if not path.endswith(".map"):
            continue
        data = json.loads(body)
        for source, content in zip(data.get("sources", []), data.get("sourcesContent", [])):
            if isinstance(content, str) and sha(content.encode()) == content_hash:
                matches.append({"archive_map": path, "source": source, "map_sha256": sha(body)})
    return matches


def selected_texts(files: dict[str, bytes], name: str) -> list[dict]:
    result = []
    for path, body in sorted(files.items()):
        filename = path.rsplit("/", 1)[-1]
        # Deliberately exclude source tools such as license-update.mjs.
        if re.fullmatch(r"(?i)(license|licence|notice|copying)(?:[._-](?:md|txt|mit|apache|bsd))?", filename):
            result.append({"archive_path": path, "sha256": sha(body), "bytes": len(body),
                           "coverage": "package text; embedded attribution closure remains separate"})
    if name == "fastdom":
        readme = files["README.md"]
        marker = b"## License\n\n"
        start = readme.index(marker) + len(marker)
        body = readme[start:]
        if not body.startswith(b"(The MIT License)\n"):
            raise ValueError("FastDom README licence section differs from inspected evidence")
        result.append({"archive_path": "README.md", "archive_file_sha256": sha(readme),
                       "byte_start": start, "byte_end_exclusive": len(readme),
                       "sha256": sha(body), "bytes": len(body),
                       "coverage": "verbatim complete README licence section"})
    return result


def audit(root: Path, shipped_path: Path) -> dict:
    mermaid_metadata = json.loads((root / "mermaid-11.17.2-registry.json").read_text())
    if (mermaid_metadata["name"], mermaid_metadata["version"]) != ("mermaid", "11.17.2"):
        raise ValueError("this audit is for Mermaid 11.17.2")
    mermaid_files = verified_package_files(root / "mermaid-11.17.2.tgz", mermaid_metadata)
    shipped = shipped_path.read_bytes()
    outer = verified_bundle_map(shipped, mermaid_files, "dist/mermaid.min.js")
    parser_metadata = json.loads((root / "parser-1.2.1-registry.json").read_text())
    if (parser_metadata["name"], parser_metadata["version"]) != ("@mermaid-js/parser", "1.2.1"):
        raise ValueError("unexpected parser identity")
    parser_files = verified_package_files(root / "parser-1.2.1.tgz", parser_metadata)

    downloads = json.loads((root / "package-downloads.json").read_text())["packages"]
    archives = {}
    metadata = {}
    archive_records = {}
    for record in downloads:
        name, version = record["name"], record["version"]
        key = name, version
        folder = root / "npm-packages" / (name.replace("@", "").replace("/", "__") + "@" + version)
        raw_metadata = (folder / "registry.json").read_bytes()
        meta = json.loads(raw_metadata)
        if (meta["name"], meta["version"]) != key or sha(raw_metadata) != record["registry_sha256"]:
            raise ValueError("candidate registry record changed")
        archive_body = (folder / "package.tgz").read_bytes()
        if sha(archive_body) != record["tarball_sha256"]:
            raise ValueError("candidate archive record changed")
        archives[key] = verified_package_files(folder / "package.tgz", meta)
        metadata[key] = meta
        archive_records[key] = {field: record[field] for field in
                                ("registry_url", "registry_sha256", "tarball_url", "tarball_sha256", "integrity")}

    inner = {}
    indexes = {}
    parser_links = []
    for index, source in enumerate(outer["sources"]):
        if source.startswith("../../parser/"):
            path = source.removeprefix("../../parser/")
            body = outer["sourcesContent"][index].encode()
            data = verified_bundle_map(body, parser_files, path)
            inner[index] = data
            indexes[index] = MappingIndex(data, body.decode())
            parser_links.append({"source": source, "archive_path": path,
                                 "sha256": sha(body), "map_sha256": sha(parser_files[path + ".map"])})

    direct = Counter()
    composed = Counter()
    unresolved = 0
    for _, _, source, line, column in mapped_positions(outer, shipped.decode()):
        if source is None:
            continue
        direct[source] += 1
        if source in indexes:
            position = indexes[source].source_at(line, column)
            if position is None:
                unresolved += 1
            else:
                composed[source, position[0]] += 1

    package_rows = defaultdict(list)
    workspace_sources = 0
    unknown = []

    def add(data, index, count, map_name, basis):
        nonlocal workspace_sources
        source = data["sources"][index]
        content = data["sourcesContent"][index].encode()
        content_hash = sha(content)
        parsed = package_identity(source)
        row = {"source": source, "map": map_name, "sha256": content_hash,
               "generated_references": count, "inclusion_basis": basis}
        if parsed:
            name, version, path = parsed
            files = archives[name, version]
            if files.get(path) == content:
                row["exact_source_link"] = {"archive_path": path}
            else:
                matches = embedded_sources(files, content_hash)
                if not matches:
                    raise ValueError("mapped source has no exact official content link: " + source)
                row["exact_source_link"] = {"archive_embedded_sources": matches}
            package_rows[name, version].append(row)
        elif source.startswith("../../parser/"):
            row["exact_source_link"] = {"archive_path": source.removeprefix("../../parser/")}
            package_rows["@mermaid-js/parser", "1.2.1"].append(row)
        elif source.startswith("webpack://LIB/"):
            matches = embedded_sources(archives["vscode-uri", "3.1.0"], content_hash)
            if not matches:
                raise ValueError("unlinked webpack source")
            row["exact_source_link"] = {"archive_embedded_sources": matches}
            row["version_basis"] = "exact content match against named candidate archive; map path omits version and does not exclude identical content in other releases"
            package_rows["vscode-uri", "3.1.0"].append(row)
            if source.endswith("/node_modules/path-browserify/index.js"):
                if archives["path-browserify", "1.0.1"].get("index.js") != content:
                    raise ValueError("path-browserify content mismatch")
                package_rows["path-browserify", "1.0.1"].append({**row, "exact_source_link": {"archive_path": "index.js"}})
        elif source.startswith(("../src/", "../../../src/")):
            workspace_sources += 1
        else:
            unknown.append(row)

    for index, count in sorted(direct.items()):
        add(outer, index, count, "mermaid.min.js.map", "direct mapped generated position")
    for (parent, index), count in sorted(composed.items()):
        add(inner[parent], index, count, outer["sources"][parent] + ".map", "composed outer-to-parser mapped position")

    packages = []
    for key, sources in sorted(package_rows.items()):
        name, version = key
        texts = selected_texts(archives[key], name)
        if not texts:
            raise ValueError("no package licence text captured for " + name)
        expression = metadata[key].get("license")
        if key == ("khroma", "2.1.0"):
            expression = "MIT"
        packages.append({"name": name, "version": version, **archive_records[key],
                         "version_authority": ("content-matched candidate; original prebundle resolution not proved by this verifier"
                                               if name in ("vscode-uri", "path-browserify") else
                                               "versioned map input path or byte-identical published parser chunks"),
                         "package_license_expression": expression,
                         "license_basis": "official licence text" if name == "khroma" else "official package metadata and captured text",
                         "package_license_texts": texts, "mapped_sources": sources})

    return {"schema": 1, "status": "partial; not nested-notice closure or legal clearance",
            "bundle": {"package": "mermaid@11.17.2", "sha256": sha(shipped),
                       "archive_sha256": sha((root / "mermaid-11.17.2.tgz").read_bytes()),
                       "map_sha256": sha(mermaid_files["dist/mermaid.min.js.map"]),
                       "parser_archive_sha256": sha((root / "parser-1.2.1.tgz").read_bytes()),
                       "release_lock_sha256": sha((root / "pnpm-lock.yaml").read_bytes())},
            "counts": {"candidate_archives_verified": len(archives), "outer_mapped_sources": len(direct),
                       "parser_composed_sources": len(composed), "parser_points_without_inner_mapping": unresolved,
                       "workspace_source_records": workspace_sources, "package_version_records": len(packages),
                       "versioned_map_or_parser_chunk_records": sum(p["name"] not in ("vscode-uri", "path-browserify") for p in packages),
                       "content_matched_candidate_version_records": sum(p["name"] in ("vscode-uri", "path-browserify") for p in packages)},
            "parser_chunk_links": parser_links, "packages": packages, "unclassified_sources": unknown,
            "limits": ["Generated mappings prove source provenance, not semantic reachability.",
                       "Registry hashes are checked; publisher/Sigstore signatures are not verified.",
                       "The release lock is preserved by hash, not parsed or used as inclusion proof by this verifier.",
                       "Exact prebundle matches do not resolve their own nested attribution obligations.",
                       "KaTeX React/Apache and Cytoscape borrowed-code notices remain unresolved.",
                       "Rough.js nested sources and unmapped/generated helper attribution require further evidence.",
                       "Captured package licence texts have not been installed into the distribution inventory."]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--evidence-dir", required=True, type=Path)
    parser.add_argument("--shipped-bundle", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    report = audit(args.evidence_dir, args.shipped_bundle)
    args.output.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    print(json.dumps({"status": report["status"], **report["counts"]}, indent=2))


if __name__ == "__main__":
    main()
