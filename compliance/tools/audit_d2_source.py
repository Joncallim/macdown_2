#!/usr/bin/env python3
"""Record reproducible D2 npm/source and js/wasm Go-module evidence.

The Go package graph describes a build from the publisher-reported source
commit. It does not independently identify modules in the published binary.
"""

import argparse
import base64
import hashlib
import json
import pathlib
import tarfile


def fail(message):
    raise ValueError(message)


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def read_json_stream(path):
    source = path.read_text()
    decoder = json.JSONDecoder()
    cursor = 0
    while cursor < len(source):
        while cursor < len(source) and source[cursor].isspace():
            cursor += 1
        if cursor == len(source):
            break
        value, cursor = decoder.raw_decode(source, cursor)
        yield value


def archive_member(archive, name):
    member = archive.extractfile(name)
    if member is None:
        fail(f"Missing archive member: {name}")
    return member.read()


def audit(metadata_path, npm_path, source_path, go_list_path, shipped_path):
    metadata = json.loads(metadata_path.read_text())
    if (metadata.get("name"), metadata.get("version")) != ("@terrastruct/d2", "0.1.33"):
        fail("Unexpected npm package identity")
    revision = metadata.get("gitHead")
    if not isinstance(revision, str) or len(revision) != 40:
        fail("Missing full publisher source revision")

    npm_bytes = npm_path.read_bytes()
    integrity = metadata["dist"]["integrity"]
    actual_integrity = "sha512-" + base64.b64encode(hashlib.sha512(npm_bytes).digest()).decode()
    if actual_integrity != integrity:
        fail("npm tarball does not match registry integrity")
    with tarfile.open(npm_path, "r:gz") as archive:
        upstream = archive_member(archive, "package/dist/browser/index.js")
        wasm = archive_member(archive, "package/dist/node-cjs/d2.wasm")
        other_wasm = archive_member(archive, "package/dist/node-esm/d2.wasm")
    if wasm != other_wasm:
        fail("The two published D2 WebAssembly copies differ")
    shipped = shipped_path.read_bytes()
    old, new = b"export{lw as D2}", b"window.D2=lw;"
    if upstream.count(old) != 1 or shipped != upstream.replace(old, new):
        fail("Shipped D2 browser bundle differs beyond the documented export replacement")

    source_bytes = source_path.read_bytes()
    root = f"d2-{revision}/"
    with tarfile.open(source_path, "r:gz") as archive:
        build_script = archive_member(archive, root + "d2js/js/ci/build.sh")
        go_mod = archive_member(archive, root + "go.mod")
    if b"GOOS=js GOARCH=wasm go build" not in build_script or b"-o main.wasm ./d2js" not in build_script:
        fail("Source build script does not identify the expected js/wasm entry point")
    if b"module oss.terrastruct.com/d2\n" not in go_mod:
        fail("Unexpected D2 Go module")

    packages = list(read_json_stream(go_list_path))
    if not packages or not any(p.get("ImportPath") == "oss.terrastruct.com/d2/d2js" for p in packages):
        fail("Go package graph does not contain the D2 WebAssembly entry point")
    if any(p.get("Error") or p.get("Incomplete") for p in packages):
        fail("Go package graph contains an error or incomplete package")
    modules = {}
    for package in packages:
        module = package.get("Module")
        if not module or module["Path"] == "oss.terrastruct.com/d2":
            continue
        key = (module["Path"], module["Version"])
        if not isinstance(module.get("Sum"), str) or not module["Sum"].startswith("h1:"):
            fail(f"Missing Go module checksum for {key[0]}")
        entry = modules.setdefault(key, {"path": key[0], "version": key[1],
                                         "go_sum": module.get("Sum"), "package_count": 0,
                                         "licence_texts": []})
        if entry["go_sum"] != module.get("Sum"):
            fail(f"Inconsistent Go checksum for {key[0]}")
        entry["package_count"] += 1
        directory = pathlib.Path(module["Dir"])
        if not entry["licence_texts"]:
            candidates = sorted(path for path in directory.iterdir() if path.is_file()
                                and any(word in path.name.lower()
                                        for word in ("licen", "copying", "notice")))
            if not candidates:
                fail(f"No root licence text captured for {key[0]}")
            entry["licence_texts"] = [
                {"filename": path.name, "sha256": sha256(path.read_bytes())}
                for path in candidates
            ]

    return {
        "scope": "publisher-reported source graph, not an independent binary rebuild",
        "npm": {"name": metadata["name"], "version": metadata["version"],
                "registry_integrity": integrity, "tarball_sha256": sha256(npm_bytes),
                "browser_sha256": sha256(upstream), "wasm_sha256": sha256(wasm)},
        "shipped_browser_sha256": sha256(shipped),
        "patch": {"old": old.decode(), "new": new.decode()},
        "source": {"commit": revision, "archive_sha256": sha256(source_bytes),
                   "go_mod_sha256": sha256(go_mod), "build_script_sha256": sha256(build_script),
                   "target": "GOOS=js GOARCH=wasm ./d2js"},
        "go_graph": {"source_sha256": sha256(go_list_path.read_bytes()),
                     "package_count": len(packages), "external_modules": [
            modules[key] for key in sorted(modules)
        ]},
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("metadata", "npm", "source", "go-list", "shipped", "output"):
        parser.add_argument("--" + name, type=pathlib.Path, required=True)
    args = parser.parse_args()
    result = audit(args.metadata, args.npm, args.source, args.go_list, args.shipped)
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")


if __name__ == "__main__":
    main()
