"""Negative controls for exact-bundle and composed-source evidence (#148)."""

import base64
import hashlib
import io
import json
from pathlib import Path
import sys
import tarfile
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
import source_map_evidence as evidence
import audit_mermaid_bundle as mermaid_audit


def source_map(mappings="AAAA", contents=None):
    return {"version": 3, "sources": ["included.js", "declared-only.js"],
            "sourcesContent": contents or ["abc", "def"], "names": [], "mappings": mappings}


class SourceMapEvidenceTests(unittest.TestCase):
    def test_unmapped_source_list_entry_is_not_inclusion(self):
        positions = list(evidence.mapped_positions(source_map(), "abc"))
        self.assertEqual({position[2] for position in positions}, {0})

    def test_composition_respects_unmapped_region_and_line(self):
        # source 0 at column 0; unmapped at 1; source 1 at 2.
        index = evidence.MappingIndex(source_map("AAAA,C,CCAA"), "abc\ndef")
        self.assertEqual(index.source_at(0, 0), (0, 0, 0))
        self.assertIsNone(index.source_at(0, 1))
        self.assertEqual(index.source_at(0, 2), (1, 0, 0))
        self.assertIsNone(index.source_at(1, 0))

    def test_composition_does_not_use_future_mapping(self):
        index = evidence.MappingIndex(source_map("EAAA"), "abc")
        self.assertIsNone(index.source_at(0, 1))
        self.assertEqual(index.source_at(0, 2), (0, 0, 0))

    def test_composition_rejects_out_of_bounds_query(self):
        index = evidence.MappingIndex(source_map(), "abc")
        for line, column in [(-1, 0), (1, 0), (0, -1), (0, 4)]:
            with self.subTest(line=line, column=column), self.assertRaises(ValueError):
                index.source_at(line, column)

    def test_duplicate_coordinate_cannot_count_an_overwritten_source(self):
        with self.assertRaisesRegex(ValueError, "duplicate generated"):
            list(evidence.mapped_positions(source_map("AAAA,ACAA"), "abc"))

    def test_source_root_cannot_silently_change_package_identity(self):
        data = source_map()
        data["sourceRoot"] = "https://example.org/different-package/"
        with self.assertRaisesRegex(ValueError, "sourceRoot"):
            list(evidence.mapped_positions(data, "abc"))

    def test_utf16_columns_accept_supplementary_unicode(self):
        result = list(evidence.mapped_positions(source_map("EAAE", ["😀x", "z"]), "😀x"))
        self.assertEqual(result, [(0, 2, 0, 0, 2)])

    def test_malformed_mapping_is_rejected(self):
        for raw in ["g", "!", "AA", "AAAAAA", "gggggggggggggg"]:
            with self.subTest(raw=raw), self.assertRaises(ValueError):
                list(evidence.mapped_positions(source_map(raw), "abc"))

    def test_out_of_bounds_mapping_is_rejected(self):
        for raw in ["KAAA", "AEAA", "AACA", "AAAK", "AAAAC", "AAAA,DAAA"]:
            with self.subTest(raw=raw), self.assertRaises(ValueError):
                list(evidence.mapped_positions(source_map(raw), "abc"))

    def test_missing_source_content_is_rejected(self):
        data = source_map()
        data["sourcesContent"][0] = None
        with self.assertRaises(ValueError):
            list(evidence.mapped_positions(data, "abc"))

    def test_changed_shipped_bundle_is_rejected_before_inclusion(self):
        files = {"dist/a.js": b"abc", "dist/a.js.map": json.dumps(source_map()).encode()}
        with self.assertRaisesRegex(ValueError, "differs from official"):
            evidence.verified_bundle_map(b"abd", files, "dist/a.js")
        self.assertEqual(evidence.verified_bundle_map(b"abc", files, "dist/a.js")["sources"][0], "included.js")

    def test_archive_identity_and_integrity_are_independent_checks(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "package.tgz"
            with tarfile.open(path, "w:gz") as archive:
                content = json.dumps({"name": "fixture", "version": "1.0.0"}).encode()
                member = tarfile.TarInfo("package/package.json")
                member.size = len(content)
                archive.addfile(member, io.BytesIO(content))
            body = path.read_bytes()
            metadata = {"name": "fixture", "version": "1.0.0", "dist": {
                "integrity": "sha512-" + base64.b64encode(hashlib.sha512(body).digest()).decode(),
                "shasum": hashlib.sha1(body).hexdigest()}}
            self.assertIn("package.json", evidence.verified_package_files(path, metadata))
            metadata["version"] = "2.0.0"
            with self.assertRaisesRegex(ValueError, "identity differs"):
                evidence.verified_package_files(path, metadata)
            path.write_bytes(body + b"changed")
            with self.assertRaisesRegex(ValueError, "registry integrity"):
                evidence.verified_package_files(path, metadata)

    def test_licence_named_source_tool_is_not_selected_notice_text(self):
        texts = mermaid_audit.selected_texts({"LICENSE": b"MIT text", "license-update.mjs": b"tool code"}, "fixture")
        self.assertEqual([text["archive_path"] for text in texts], ["LICENSE"])

    def test_readme_licence_section_preserves_exact_bytes_and_range(self):
        prefix = b"# FastDom\n\n## License\n\n"
        body = b"(The MIT License)\n\nCopyright Fixture\n"
        texts = mermaid_audit.selected_texts({"README.md": prefix + body}, "fastdom")
        self.assertEqual(texts[0]["byte_start"], len(prefix))
        self.assertEqual(texts[0]["byte_end_exclusive"], len(prefix + body))
        self.assertEqual(texts[0]["sha256"], hashlib.sha256(body).hexdigest())

    def test_peer_suffix_does_not_change_scoped_package_identity(self):
        path = "../../node_modules/.pnpm/@scope+name@1.2.3_peer@4.0.0/node_modules/@scope/name/file.js"
        self.assertEqual(mermaid_audit.package_identity(path), ("@scope/name", "1.2.3", "file.js"))
        with self.assertRaises(ValueError):
            mermaid_audit.package_identity(path.replace("node_modules/@scope/name", "node_modules/wrong"))


if __name__ == "__main__":
    unittest.main()
