"""Negative controls for the D2 corresponding-source archive verifier."""

import io
import json
import sys
import tarfile
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / "compliance" / "tools"))

import verify_d2_offer  # noqa: E402


class D2OfferVerifierTests(unittest.TestCase):
    def verify_members(self, members, reviewed_manifest=None):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            archive_path = root / "offer.tar.gz"
            graph_path = root / "graph.json"
            shipped_path = root / "browser.js"
            manifest_path = root / "manifest.json"
            graph_path.write_text("{}")
            shipped_path.write_bytes(b"")
            manifest_path.write_bytes(reviewed_manifest if reviewed_manifest is not None
                                      else next((payload for name, payload in members
                                                 if name == "manifest.json"), b""))
            with tarfile.open(archive_path, "w:gz") as archive:
                for name, payload in members:
                    info = tarfile.TarInfo(name)
                    info.size = len(payload)
                    archive.addfile(info, io.BytesIO(payload))
            verify_d2_offer.verify(archive_path, graph_path, shipped_path, manifest_path)

    def test_duplicate_member_is_rejected_before_manifest_use(self):
        manifest = json.dumps({"files": []}).encode()
        with self.assertRaisesRegex(ValueError, "duplicate archive member"):
            self.verify_members([("manifest.json", manifest), ("manifest.json", manifest)])

    def test_traversal_member_is_rejected_without_extraction(self):
        with self.assertRaisesRegex(ValueError, "non-file or unsafe archive member"):
            self.verify_members([("../outside", b"untrusted")])

    def test_archive_manifest_must_match_reviewed_manifest(self):
        with self.assertRaisesRegex(ValueError, "archive manifest differs"):
            self.verify_members([("manifest.json", b"{}")], reviewed_manifest=b"changed")

    def test_manifest_hash_mismatch_is_rejected(self):
        manifest = json.dumps({"files": [{"path": "payload", "size": 3, "sha256": "0" * 64}]}).encode()
        with self.assertRaisesRegex(ValueError, "manifest size/hash mismatch"):
            self.verify_members([("manifest.json", manifest), ("payload", b"abc")])


if __name__ == "__main__":
    unittest.main()
