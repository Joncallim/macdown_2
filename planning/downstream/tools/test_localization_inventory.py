"""Hermetic negative controls for the XCStrings inventory validator."""

import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).parent))
import localization_inventory as subject


class LocalizationInventoryTests(unittest.TestCase):
    fixtures = Path(__file__).parent / "fixtures/localization"

    def fixture(self, name):
        return json.loads((self.fixtures / name).read_text(encoding="utf-8"))

    def make_repo(self, catalog):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        repo = Path(temporary.name)
        path = repo / "MacDown2/MacDown2/Localizable.xcstrings"
        path.parent.mkdir(parents=True)
        path.write_text(json.dumps(catalog), encoding="utf-8")
        return repo

    def test_valid_catalog_passes(self):
        self.assertEqual(subject.validate(self.make_repo(self.fixture("valid.json"))), [])

    def test_missing_placeholder_fails(self):
        errors = subject.validate(self.make_repo(self.fixture("missing-placeholder.json")))
        self.assertTrue(any("placeholders" in error for error in errors))

    def test_extra_placeholder_fails(self):
        errors = subject.validate(self.make_repo(self.fixture("extra-placeholder.json")))
        self.assertTrue(any("placeholders" in error for error in errors))

    def test_type_mismatched_placeholder_fails(self):
        errors = subject.validate(self.make_repo(self.fixture("type-mismatch.json")))
        self.assertTrue(any("placeholders" in error for error in errors))

    def test_plural_without_other_fails(self):
        errors = subject.validate(self.make_repo(self.fixture("plural-without-other.json")))
        self.assertTrue(any("lacks an other variant" in error for error in errors))

    def test_plural_type_mismatch_fails(self):
        catalog = self.fixture("plural-without-other.json")
        catalog["strings"]["%lld file"]["localizations"]["fr"]["substitutions"]["files"]["variations"]["plural"]["other"] = {"stringUnit": {"value": "%files fichiers"}}
        catalog["strings"]["%lld file"]["localizations"]["fr"]["substitutions"] = {
            "files": {"argNum": 1, "formatSpecifier": "@", "variations": {"plural": {"other": {"stringUnit": {"value": "%files fichiers"}}}}}
        }
        errors = subject.validate(self.make_repo(catalog))
        self.assertTrue(any("substitution types" in error for error in errors))

    def test_malformed_catalog_is_rejected(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        repo = Path(temporary.name)
        path = repo / "MacDown2/MacDown2/Localizable.xcstrings"
        path.parent.mkdir(parents=True)
        path.write_text((self.fixtures / "malformed.json").read_text(encoding="utf-8"), encoding="utf-8")
        with self.assertRaisesRegex(subject.CatalogError, "malformed JSON"):
            subject.inventory(repo)


if __name__ == "__main__":
    unittest.main()
