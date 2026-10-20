#!/usr/bin/env python3
"""Check a prepared D2 source-review archive against recorded source evidence.

This checks archive identity and completeness. It does not prove that the npm
publisher built the WebAssembly from the reported source commit, audit every
nested licence obligation, or make an unpublished archive publicly available.
"""

import argparse
import hashlib
import io
import json
import pathlib
import tarfile
import zipfile


def require(condition, message):
    if not condition:
        raise ValueError(message)


def digest(data):
    return hashlib.sha256(data).hexdigest()


def safe_name(name):
    path = pathlib.PurePosixPath(name)
    return bool(name) and not path.is_absolute() and ".." not in path.parts and str(path) == name


def verify(archive_path, graph_path, shipped_path, manifest_path):
    graph = json.loads(graph_path.read_text())
    with tarfile.open(archive_path, "r:gz") as archive:
        members = archive.getmembers()
        names = [member.name for member in members]
        require(len(names) == len(set(names)), "duplicate archive member")
        require(all(member.isfile() and safe_name(member.name) for member in members),
                "non-file or unsafe archive member")
        contents = {member.name: archive.extractfile(member).read() for member in members}

    require("manifest.json" in contents, "missing offer manifest")
    require(contents["manifest.json"] == manifest_path.read_bytes(),
            "archive manifest differs from reviewed manifest")
    manifest = json.loads(contents["manifest.json"])
    files = manifest["files"]
    expected = {entry["path"] for entry in files}
    require(len(expected) == len(files), "duplicate manifest path")
    require(expected | {"manifest.json"} == set(contents), "archive and manifest file sets differ")
    for entry in files:
        path = entry["path"]
        require(safe_name(path), f"unsafe manifest path: {path}")
        data = contents[path]
        require(len(data) == entry["size"] and digest(data) == entry["sha256"],
                f"manifest size/hash mismatch: {path}")

    source = graph["source"]
    npm = graph["npm"]
    require(manifest["source_commit"] == source["commit"], "source revision mismatch")
    require(digest(contents["upstream/d2-source-581c9109.tar.gz"]) == source["archive_sha256"],
            "upstream source archive mismatch")
    require(digest(contents["publisher/d2-0.1.33.tgz"]) == npm["tarball_sha256"],
            "publisher npm archive mismatch")
    shipped = shipped_path.read_bytes()
    require(digest(shipped) == graph["shipped_browser_sha256"],
            "shipped D2 browser mismatch")
    patch = contents["patches/d2-browser.patch"]
    require(graph["patch"]["old"].encode() in patch and graph["patch"]["new"].encode() in patch,
            "recorded export replacement missing from patch")
    with tarfile.open(fileobj=io.BytesIO(contents["publisher/d2-0.1.33.tgz"]), mode="r:gz") as publisher:
        browser = publisher.extractfile("package/dist/browser/index.js").read()
    old, new = graph["patch"]["old"].encode(), graph["patch"]["new"].encode()
    require(digest(browser) == npm["browser_sha256"] and browser.count(old) == 1
            and browser.replace(old, new) == shipped, "published browser/patch/shipped bytes differ")
    with tarfile.open(fileobj=io.BytesIO(contents["upstream/d2-source-581c9109.tar.gz"]),
                      mode="r:gz") as upstream:
        root = f"d2-{source['commit']}/"
        go_mod = upstream.extractfile(root + "go.mod").read()
        build = upstream.extractfile(root + "d2js/js/ci/build.sh").read()
    require(digest(go_mod) == source["go_mod_sha256"]
            and digest(build) == source["build_script_sha256"],
            "source build inputs differ from recorded graph")

    modules = graph["go_graph"]["external_modules"]
    order = manifest["module_order"]
    require(len(modules) == len(order) == 16, "external module count mismatch")
    for index, (module, item) in enumerate(zip(modules, order, strict=True), 1):
        directory = f"modules/{index:02d}"
        require(item["directory"] == directory, f"module order mismatch: {index}")
        for key in ("path", "version", "go_sum"):
            require(item[key] == module[key], f"module {index} {key} mismatch")
        source_zip = contents[f"{directory}/source.zip"]
        with zipfile.ZipFile(io.BytesIO(source_zip)) as zipped:
            for license_entry in module["licence_texts"]:
                filename = license_entry["filename"]
                candidates = [name for name in zipped.namelist()
                              if name.endswith("/" + filename)
                              and name.count("/") == module["path"].count("/") + 1]
                require(len(candidates) == 1, f"module {index} root licence missing/ambiguous")
                license_bytes = zipped.read(candidates[0])
                require(digest(license_bytes) == license_entry["sha256"],
                        f"module {index} source licence mismatch")
                require(contents[f"{directory}/{filename}"] == license_bytes,
                        f"module {index} copied licence mismatch")

    return {"archive_sha256": digest(archive_path.read_bytes()),
            "source_commit": source["commit"], "files": len(files), "external_modules": len(modules)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("archive", type=pathlib.Path)
    parser.add_argument("--graph", type=pathlib.Path,
                        default=pathlib.Path("compliance/evidence/d2-0.1.33/source-graph.json"))
    parser.add_argument("--shipped", type=pathlib.Path,
                        default=pathlib.Path(
                            "MacDown2/Packages/MacDownKit/Sources/D2Rendering/Resources/d2-browser.js"
                        ))
    parser.add_argument("--manifest", type=pathlib.Path,
                        default=pathlib.Path("compliance/evidence/d2-0.1.33/offer-manifest.json"))
    args = parser.parse_args()
    print(json.dumps(verify(args.archive, args.graph, args.shipped, args.manifest),
                     indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
