#!/usr/bin/env python3
"""Check retained publisher inputs without installing or executing their code."""

import argparse
import base64
import hashlib
import json
from pathlib import Path
import tarfile

VIZ_REVISION = "99da545270e6e7b127a5c7ba65974b8a604a6358"
GRAPHVIZ_REVISION = "06fff22d8e1a2aead6de0042e5e5ec2f7749be29"
EXPAT_REVISION = "12cf0b1f25f026a022fe728ad8f7e3d017285b80"
ARCHIVES = {
    "viz-source-99da545.tar.gz": "27d1aed976e66e56dee2ad9491415c8d3e2a2132d8c7a1372220f17321bf766c",
    "graphviz-16.0.0.tar.gz": "36a1de1aaf5a2023b14f95170a5f8f0b12522d1c305b517fc261966597050749",
    "expat-2.8.4.tar.gz": "b8ece2437692dad44d851c4532723390a5a330990007706be9c8d2b90d294f36",
    "viz-3.30.0.tgz": "4f52d4bd062b38b9ca66de0a4888633c912b745f1f00b9b224c77a1c7d9f1c92",
}


def digest(data):
    return hashlib.sha256(data).hexdigest()


def require(condition, message):
    if not condition:
        raise ValueError(message)


def member(archive, path):
    entry = archive.getmember(path)
    require(entry.isfile(), f"Not an ordinary archive member: {path}")
    return archive.extractfile(entry).read()


def notice_blocks(source, marker, count=1):
    start = source.index(marker)
    end = start
    for _ in range(count):
        end = source.index(b"*/", end) + 2
    return source[start:end] + b"\n"


def audit(inputs, repo):
    archives = {}
    for name, expected in ARCHIVES.items():
        data = (inputs / name).read_bytes()
        require(digest(data) == expected, f"Archive digest mismatch: {name}")
        archives[name] = {"bytes": len(data), "sha256": expected}

    def metadata(name):
        return json.loads((inputs / name).read_text())

    npm = metadata("npm-viz-3.30.0.json")
    data = (inputs / "viz-3.30.0.tgz").read_bytes()
    require(npm["dist"]["integrity"] == "sha512-" + base64.b64encode(hashlib.sha512(data).digest()).decode(), "npm integrity mismatch")
    require(npm["gitHead"] == VIZ_REVISION, "npm source revision mismatch")
    require(metadata("viz-release-ref.json")["object"]["sha"] == VIZ_REVISION, "Viz.js release ref mismatch")
    require(metadata("graphviz-tag.json")["commit"]["id"] == GRAPHVIZ_REVISION, "Graphviz release ref mismatch")
    require(metadata("expat-annotated-tag.json")["object"]["sha"] == EXPAT_REVISION, "Expat release ref mismatch")
    expat_asset = next(a for a in metadata("expat-release.json")["assets"] if a["name"] == "expat-2.8.4.tar.gz")
    require(expat_asset["digest"] == "sha256:" + ARCHIVES["expat-2.8.4.tar.gz"], "Expat publisher digest mismatch")
    graphviz_asset = next(a for a in metadata("graphviz-package-files.json") if a["file_name"] == "graphviz-16.0.0.tar.gz")
    require(graphviz_asset["file_sha256"] == ARCHIVES["graphviz-16.0.0.tar.gz"], "Graphviz publisher digest mismatch")

    resource = repo / "MacDown2/Packages/MacDownKit/Sources/GraphvizRendering/Resources"
    with tarfile.open(inputs / "viz-3.30.0.tgz") as npm_archive, tarfile.open(inputs / "viz-source-99da545.tar.gz") as source:
        bundle = member(npm_archive, "package/dist/viz-global.js")
        require(bundle == (resource / "viz-global.js").read_bytes(), "Shipped bundle differs from npm")
        backend = member(npm_archive, "package/lib/backend.js")
        provenance_bytes = member(npm_archive, "package/lib/provenance.json")
        provenance = json.loads(provenance_bytes)
        require(provenance["subject"] == [{"name": "backend.js", "digest": {"sha256": digest(backend)}}], "Backend provenance subject mismatch")
        definition = provenance["predicate"]["buildDefinition"]
        args = definition["externalParameters"]["request"]["root"]["request"]["args"]
        require(args["vcs:revision"] == VIZ_REVISION, "Backend provenance source revision mismatch")
        dependencies = definition["resolvedDependencies"]
        for name in ("expat-2.8.4.tar.gz", "graphviz-16.0.0.tar.gz"):
            dep = next(d for d in dependencies if d["uri"].endswith("/" + name))
            require(dep["digest"]["sha256"] == ARCHIVES[name], f"Build input mismatch: {name}")

        prefix = f"viz-js-{VIZ_REVISION}/"
        source_files = {}
        for path in ("LICENSE", "package-lock.json", "packages/viz/package.json", "packages/viz/Makefile", "packages/viz/rollup.config.js", "packages/viz/backend/Dockerfile", "packages/viz/backend/viz.c", "packages/viz/backend/pre.js", ".github/workflows/viz-build.yml", ".github/workflows/viz-publish.yml"):
            source_files[path] = digest(member(source, prefix + path))
        wrapper_files = []
        for entry in npm_archive.getmembers():
            if entry.isfile() and entry.name.startswith(("package/src/", "package/types/")):
                path = entry.name.removeprefix("package/")
                require(member(npm_archive, entry.name) == member(source, prefix + "packages/viz/" + path), f"Wrapper source mismatch: {path}")
                wrapper_files.append(path)
        require(member(source, prefix + "LICENSE") == (resource / "VIZJS-LICENSE.txt").read_bytes(), "Viz.js licence mismatch")
        dockerfile = member(source, prefix + "packages/viz/backend/Dockerfile").decode()
        require("-lexpat" in dockerfile and "R_2_8_4/expat-2.8.4.tar.gz" in dockerfile, "Expat link input missing")
        require("-lgvplugin_neato_layout" in dockerfile, "Neato plugin link input missing")

    with tarfile.open(inputs / "expat-2.8.4.tar.gz") as source:
        expat_license = member(source, "expat-2.8.4/COPYING")
        require(expat_license == (repo / "compliance/licenses/expat--COPYING.txt").read_bytes(), "Expat licence mismatch")
    with tarfile.open(inputs / "graphviz-16.0.0.tar.gz") as source:
        graphviz_license = member(source, "graphviz-16.0.0/COPYING")
        require(graphviz_license == (resource / "GRAPHVIZ-EPL-LICENSE.txt").read_bytes(), "Graphviz licence mismatch")
        graphviz_prefix = "graphviz-16.0.0/"
        plugin_make = member(source, graphviz_prefix + "plugin/neato_layout/Makefile.am")
        neatogen_make = member(source, graphviz_prefix + "lib/neatogen/Makefile.am")
        overlap = member(source, graphviz_prefix + "lib/neatogen/overlap.c")
        rbtree_make = member(source, graphviz_prefix + "lib/rbtree/Makefile.am")
        rbtree_source = member(source, graphviz_prefix + "lib/rbtree/red_black_tree.c")
        rbtree_license = member(source, graphviz_prefix + "lib/rbtree/LICENSE")
        require(b"lib/rbtree/librbtree_C.la" in plugin_make
                and b"lib/neatogen/libneatogen_C.la" in plugin_make,
                "Neato plugin no longer links the tree and layout libraries")
        require(b"overlap.c" in neatogen_make and b"RBTreeCreate" in overlap
                and b"RBTreeInsert" in overlap and b"RBTreeDestroy" in overlap,
                "Neato overlap source no longer uses red-black tree code")
        require(b"librbtree_C_la_SOURCES = red_black_tree.c" in rbtree_make
                and b"RBTreeCreate" in rbtree_source,
                "Red-black tree source build path changed")
        require(rbtree_license == (repo / "compliance/licenses/graphviz-rbtree--LICENSE.txt").read_bytes(),
                "Graphviz red-black tree licence mismatch")

        common_make = member(source, graphviz_prefix + "lib/common/Makefile.am")
        gvc_make = member(source, graphviz_prefix + "lib/gvc/Makefile.am")
        ellipse = member(source, graphviz_prefix + "lib/common/ellipse.c")
        randomkit_source = member(source, graphviz_prefix + "lib/neatogen/randomkit.c")
        randomkit_header = member(source, graphviz_prefix + "lib/neatogen/randomkit.h")
        require("-lgvc" in dockerfile and b"lib/common/libcommon_C.la" in gvc_make
                and b"ellipse.c" in common_make,
                "Graphviz common ellipse source build path changed")
        require(b"randomkit.c" in neatogen_make and b"lib/neatogen/libneatogen_C.la" in plugin_make,
                "Graphviz Neato Random kit source build path changed")
        ellipse_notice = notice_blocks(ellipse, b"/* This code is derived", count=2)
        randomkit_source_notice = notice_blocks(randomkit_source, b"/*\n * Copyright (c) 2003-2005")
        randomkit_header_notice = notice_blocks(randomkit_header, b"/*\n * Copyright (c) 2003-2005")
        for notice, path in (
            (ellipse_notice, "graphviz-ellipse--LUC-MAISONOBE.txt"),
            (randomkit_source_notice, "graphviz-randomkit--SOURCE-NOTICE.txt"),
            (randomkit_header_notice, "graphviz-randomkit--HEADER-NOTICE.txt"),
        ):
            require(notice == (repo / "compliance/licenses" / path).read_bytes(),
                    f"Graphviz nested source notice mismatch: {path}")

    return {
        "status": "passed",
        "archives": archives,
        "viz_revision": VIZ_REVISION,
        "graphviz_revision": GRAPHVIZ_REVISION,
        "expat_revision": EXPAT_REVISION,
        "shipped_bundle_sha256": digest(bundle),
        "npm_sha512_integrity_matches": True,
        "wrapper_source_files_match": sorted(wrapper_files),
        "backend_sha256": digest(backend),
        "backend_publisher_provenance_sha256": digest(provenance_bytes),
        "backend_publisher_dependencies": dependencies,
        "build_source_sha256": source_files,
        "expat_copying_sha256": digest(expat_license),
        "graphviz_copying_sha256": digest(graphviz_license),
        "rbtree_source_linkage": {
            "plugin_makefile_sha256": digest(plugin_make),
            "neatogen_makefile_sha256": digest(neatogen_make),
            "overlap_source_sha256": digest(overlap),
            "rbtree_makefile_sha256": digest(rbtree_make),
            "rbtree_source_sha256": digest(rbtree_source),
            "rbtree_license_sha256": digest(rbtree_license),
        },
        "other_nested_source_linkage": {
            "common_makefile_sha256": digest(common_make),
            "gvc_makefile_sha256": digest(gvc_make),
            "ellipse_source_sha256": digest(ellipse),
            "ellipse_notice_sha256": digest(ellipse_notice),
            "randomkit_source_sha256": digest(randomkit_source),
            "randomkit_header_sha256": digest(randomkit_header),
            "randomkit_source_notice_sha256": digest(randomkit_source_notice),
            "randomkit_header_notice_sha256": digest(randomkit_header_notice),
        },
        "limits": ["Publisher provenance was cross-checked, not signature-verified.", "Source build files establish a path to the red-black tree library, not its exact contribution to the published WebAssembly.", "No independent rebuild or exhaustive linked-code licence audit.", "No public corresponding-source offer or signed-app verification."],
    }


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--inputs", type=Path, required=True)
    parser.add_argument("--repo", type=Path, default=Path(__file__).resolve().parents[3])
    args = parser.parse_args()
    print(json.dumps(audit(args.inputs, args.repo), indent=2, sort_keys=True))
