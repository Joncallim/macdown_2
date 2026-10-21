#!/usr/bin/env python3
"""Verify the attributed Chroma font is the one in the D2 publisher WebAssembly."""

import argparse
import base64
import hashlib
import io
import json
import re
import struct
import tarfile
import zipfile
import zlib
from pathlib import Path

ARCHIVE_SHA = "07de46d856b3e7bbc1d455651fe7045be73083e1d072530e8a1cca99a7b65c02"
SOURCE_SHA = "62b52a13f5eaa92c7ec5cecbdb9fc17871ad98095668967938ffe3ae4ee96a2c"
ENCODED_SHA = "08a76705aa3a34ece73a65398252e0df807f7671231a0d2a3f6fd4719e851380"
WOFF_SHA = "29d9447a83dbf9866aff37f7dc972441302da97f9a242ea0405f60841e9b630f"
WASM_SHA = "7b0d5db9e148d1eba9ab7494a468a79fd92aca93fd3a89cad5876e68097170af"
LICENCE_SHA = "985e76906c34ca203039d0d0aa47237d059de14d7c70c891e7f75171d0258753"
GO_PATH = "github.com/alecthomas/chroma/v2@v2.14.0/formatters/svg/font_liberation_mono.go"
LICENCE = Path(__file__).parents[1] / "licenses/d2--LIBERATION-MONO-OFL.txt"


def require(condition, message):
    if not condition:
        raise ValueError(message)


def digest(data):
    return hashlib.sha256(data).hexdigest()


def font_names(woff):
    require(woff[:4] == b"wOFF", "decoded font is not WOFF")
    number = struct.unpack_from(">H", woff, 12)[0]
    names = {}
    for index in range(number):
        tag, offset, compressed, original, _ = struct.unpack_from(">4sIIII", woff, 44 + index * 20)
        if tag != b"name":
            continue
        table = woff[offset:offset + compressed]
        if compressed < original:
            table = zlib.decompress(table)
        _, count, string_offset = struct.unpack_from(">HHH", table, 0)
        for entry in range(count):
            platform, _, _, name_id, length, start = struct.unpack_from(">HHHHHH", table, 6 + entry * 12)
            if platform != 3 or name_id not in (0, 1, 13):
                continue
            value = table[string_offset + start:string_offset + start + length].decode("utf-16-be")
            names[name_id] = value
    return names


def verify(archive_path, licence_path):
    require(digest(archive_path.read_bytes()) == ARCHIVE_SHA, "reviewed D2 archive hash changed")
    with tarfile.open(archive_path, "r:gz") as bundle:
        source = None
        for member in bundle.getmembers():
            if not re.fullmatch(r"modules/\d{2}/source\.zip", member.name):
                continue
            module = zipfile.ZipFile(io.BytesIO(bundle.extractfile(member).read()))
            if GO_PATH in module.namelist():
                require(source is None, "Chroma font source appears in multiple modules")
                source = module.read(GO_PATH)
        require(source is not None and digest(source) == SOURCE_SHA, "Chroma font source changed")

        header = source.split(b"\n\npackage svg\n", 1)[0]
        require(all(line.startswith(b"//") for line in header.splitlines()), "font licence header changed")
        copied = b"\n".join(
            line[3:] if line.startswith(b"// ") else line[2:]
            for line in header.splitlines()
        ).rstrip() + b"\n"
        licence = licence_path.read_bytes()
        require(digest(licence) == LICENCE_SHA and licence == copied, "font licence is not the source header")

        strings = re.findall(rb"`([A-Za-z0-9+/=]+)`", source)
        require(len(strings) == 1, "expected exactly one encoded WOFF string")
        encoded = strings[0]
        require(len(encoded) == 233248 and digest(encoded) == ENCODED_SHA, "encoded font changed")
        font = base64.b64decode(encoded, validate=True)
        require(len(font) == 174936 and digest(font) == WOFF_SHA, "decoded WOFF changed")
        names = font_names(font)
        require(names.get(1) == "Liberation Mono", "WOFF family name changed")
        require("Google Corporation" in names.get(0, "") and "Red Hat" in names.get(0, ""),
                "WOFF copyright metadata changed")
        require("SIL Open Font License" in names.get(13, ""), "WOFF licence metadata changed")

        publisher = tarfile.open(fileobj=io.BytesIO(bundle.extractfile("publisher/d2-0.1.33.tgz").read()),
                                 mode="r:gz")
        wasm = publisher.extractfile("package/dist/node-cjs/d2.wasm").read()
        second = publisher.extractfile("package/dist/node-esm/d2.wasm").read()
        require(digest(wasm) == WASM_SHA and second == wasm, "publisher WebAssembly changed")
        require(wasm.count(encoded) == 1 and wasm.find(encoded) == 14657061,
                "Chroma font not at the reviewed WebAssembly offset")
    return {"archive_sha256": ARCHIVE_SHA, "chroma_file": GO_PATH, "source_sha256": SOURCE_SHA,
            "encoded_bytes": len(encoded), "woff_bytes": len(font), "woff_sha256": WOFF_SHA,
            "wasm_sha256": WASM_SHA, "wasm_offset": 14657061,
            "font_family": names[1], "licence_sha256": LICENCE_SHA}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--archive", type=Path, required=True)
    parser.add_argument("--licence", type=Path, default=LICENCE)
    options = parser.parse_args()
    print(json.dumps(verify(options.archive, options.licence), indent=2))
