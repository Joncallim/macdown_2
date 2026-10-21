"""Read generated-code provenance without executing JavaScript or installing npm.

A source-map source list is not an inclusion list. Only mapped generated
positions support inclusion; nested bundles require composition through their
own maps and exact byte linkage. These helpers supply evidence, not a claim
that every embedded component or licence obligation has been identified.
"""

from __future__ import annotations

import base64
import bisect
import hashlib
import json
from pathlib import Path
import tarfile

BASE64 = {char: value for value, char in enumerate(
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
)}


def decode_segment(raw: str) -> list[int]:
    values = []
    value = shift = 0
    for char in raw:
        if char not in BASE64:
            raise ValueError("invalid source-map base64 character")
        digit = BASE64[char]
        value |= (digit & 31) << shift
        if digit & 32:
            shift += 5
            if shift > 60:
                raise ValueError("source-map integer exceeds supported range")
        else:
            values.append(-(value >> 1) if value & 1 else value >> 1)
            value = shift = 0
    if shift or len(values) not in (1, 4, 5):
        raise ValueError("invalid or incomplete source-map segment")
    return values


def utf16_line_lengths(text: str) -> list[int]:
    return [len(line.encode("utf-16-le")) // 2 for line in text.split("\n")]


def mapped_positions(data: dict, generated: str):
    """Yield (generated line/column, source index, source line/column).

    Single-field segments explicitly end a prior source association. Retain them
    so composition cannot assign an unmapped generated region to its predecessor.
    Columns are UTF-16 units, including for supplementary Unicode characters.
    """
    if data.get("version") != 3 or data.get("sections") is not None:
        raise ValueError("only ordinary version-3 source maps are supported")
    if data.get("sourceRoot") not in (None, ""):
        raise ValueError("nonempty sourceRoot requires explicit path resolution")
    sources = data.get("sources")
    contents = data.get("sourcesContent")
    names = data.get("names", [])
    if (not isinstance(sources, list) or not isinstance(contents, list)
            or len(sources) != len(contents)
            or any(not isinstance(item, str) for item in sources + contents)
            or not isinstance(names, list) or any(not isinstance(n, str) for n in names)
            or not isinstance(data.get("mappings"), str)):
        raise ValueError("source-map paths, contents, names or mappings are invalid")
    generated_lengths = utf16_line_lengths(generated)
    source_lengths = [utf16_line_lengths(content) for content in contents]
    source = source_line = source_column = name = 0
    for line, text in enumerate(data["mappings"].split(";")):
        generated_column = 0
        previous_column = None
        for raw in text.split(","):
            if not raw:
                continue
            values = decode_segment(raw)
            generated_column += values[0]
            if (values[0] < 0 or line >= len(generated_lengths)
                    or generated_column > generated_lengths[line]):
                raise ValueError("mapping outside generated code or out of order")
            if generated_column == previous_column:
                raise ValueError("duplicate generated coordinate has ambiguous source association")
            previous_column = generated_column
            if len(values) == 1:
                yield line, generated_column, None, None, None
                continue
            source += values[1]
            source_line += values[2]
            source_column += values[3]
            if (not 0 <= source < len(sources)
                    or not 0 <= source_line < len(source_lengths[source])
                    or not 0 <= source_column <= source_lengths[source][source_line]):
                raise ValueError("mapping outside recorded source content")
            if len(values) == 5:
                name += values[4]
                if not 0 <= name < len(names):
                    raise ValueError("mapping name index outside names")
            yield line, generated_column, source, source_line, source_column


class MappingIndex:
    """Greatest-lower-bound lookup on the same generated line only."""

    def __init__(self, data: dict, generated: str):
        self.lines = {}
        self.line_lengths = utf16_line_lengths(generated)
        for position in mapped_positions(data, generated):
            columns, positions = self.lines.setdefault(position[0], ([], []))
            columns.append(position[1])
            positions.append(position)

    def source_at(self, line: int, column: int):
        if not 0 <= line < len(self.line_lengths) or not 0 <= column <= self.line_lengths[line]:
            raise ValueError("composition query outside generated code")
        columns, positions = self.lines.get(line, ([], []))
        index = bisect.bisect_right(columns, column) - 1
        if index < 0 or positions[index][2] is None:
            return None
        return positions[index][2:]


def verified_package_files(archive_path: Path, metadata: dict) -> dict[str, bytes]:
    """Verify registry hashes, then read regular members without extraction.

    This checks the retrieved registry's integrity value; it does not verify a
    Sigstore signature or independently authenticate a publisher attestation.
    """
    body = archive_path.read_bytes()
    algorithm, expected = metadata["dist"]["integrity"].split("-", 1)
    if algorithm not in ("sha512", "sha256", "sha1"):
        raise ValueError("unsupported registry integrity algorithm")
    actual = base64.b64encode(hashlib.new(algorithm, body).digest()).decode()
    if actual != expected or hashlib.sha1(body).hexdigest() != metadata["dist"]["shasum"]:
        raise ValueError("npm archive does not match registry integrity")
    files = {}
    with tarfile.open(archive_path) as archive:
        for member in archive.getmembers():
            if not member.isfile():
                continue
            _, separator, relative = member.name.partition("/")
            if (not separator or not relative or relative.startswith("/")
                    or ".." in relative.split("/") or relative in files):
                raise ValueError("invalid or duplicate npm archive member")
            files[relative] = archive.extractfile(member).read()
    package = json.loads(files["package.json"])
    if (package["name"], package["version"]) != (metadata["name"], metadata["version"]):
        raise ValueError("npm package identity differs from registry metadata")
    return files


def verified_bundle_map(shipped: bytes, files: dict[str, bytes], bundle_path: str) -> dict:
    """Bind the map to the exact shipped file via the same verified archive."""
    if files.get(bundle_path) != shipped:
        raise ValueError("shipped bundle differs from official archive")
    data = json.loads(files[bundle_path + ".map"])
    # Validate all positions before returning a map a caller might compose.
    for _ in mapped_positions(data, shipped.decode("utf-8")):
        pass
    return data
