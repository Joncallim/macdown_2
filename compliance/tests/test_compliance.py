"""Tests for compliance/tools/compliance.py.

Each negative case starts from a small passing fixture tree, breaks exactly
one thing, and asserts that the check fails with the intended message. The
last test runs the real repository check so the committed inventory and
generated files cannot drift.

Run: python3 -m unittest discover -s compliance/tests
"""

from __future__ import annotations

import hashlib
import json
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / "compliance" / "tools"))

import compliance  # noqa: E402

LIB_JS = "MacDown2/Packages/MacDownKit/Sources/Widget/Resources/lib.js"
LIB_LICENCE = "MacDown2/Packages/MacDownKit/Sources/Widget/Resources/LIB-LICENSE.txt"
REMOTE_URL = "https://github.com/example/remote-kit"
REMOTE_REV = "1111111111111111111111111111111111111111"


def sha(text: str) -> str:
    return hashlib.sha256(text.encode()).hexdigest()


class Fixture:
    """A minimal repository that passes `check`."""

    def __init__(self) -> None:
        self.dir = tempfile.TemporaryDirectory()
        self.root = Path(self.dir.name)
        self.write("LICENSE", "MIT first-party licence\n")
        self.write(LIB_JS, "window.lib = 1;\n")
        self.write(LIB_LICENCE, "Example library licence\n")
        self.write("compliance/licenses/remote-kit--LICENSE.txt", "Remote kit licence\n")
        self.write("MacDown2/Packages/MacDownKit/Sources/Widget/Widget.swift", "struct Widget {}\n")
        self.write(
            "MacDown2/Packages/MacDownKit/Package.swift",
            f'dependencies: [\n    .package(url: "{REMOTE_URL}", exact: "1.0.0"),\n]\n',
        )
        self.inventory = {
            "schema": 1,
            "product": {"name": "Example", "version": "1.0.0"},
            "first_party": {"licence": "MIT", "licence_text": "LICENSE", "paths": ["MacDown2/**/*.swift"]},
            "not_distributed": ["MacDown2/**/Package.swift", "MacDown2/**/Package.resolved"],
            "manifests": ["MacDown2/Packages/MacDownKit/Package.swift"],
            "lockfiles": ["MacDown2/Packages/MacDownKit/Package.resolved"],
            "build_only_packages": [],
            "lockfile_enforced": True,
            "components": [
                {
                    "id": "lib",
                    "name": "Example lib",
                    "kind": "vendored-bundle",
                    "version": "2.0.0",
                    "upstream": "https://github.com/example/lib",
                    "revision": "2222222222222222222222222222222222222222",
                    "resolution": "exact",
                    "licence": "MPL-2.0",
                    "copyright": ["Copyright Example"],
                    "licence_texts": [{"path": LIB_LICENCE, "sha256": sha("Example library licence\n")}],
                    "owns": [LIB_JS, LIB_LICENCE],
                    "files": [{"path": LIB_JS, "sha256": sha("window.lib = 1;\n")}],
                    "source_offer": {"required": True, "reason": "MPL-2.0", "location": "https://example.org/src/", "status": "verified"},
                    "provenance": "verified",
                },
                {
                    "id": "remote-kit",
                    "name": "Remote kit",
                    "kind": "swiftpm",
                    "version": "1.0.0",
                    "upstream": REMOTE_URL,
                    "revision": REMOTE_REV,
                    "resolution": "exact",
                    "manifest_requirement": {"exact": "1.0.0"},
                    "licence": "MIT",
                    "copyright": ["Copyright Remote"],
                    "licence_texts": [{"path": "compliance/licenses/remote-kit--LICENSE.txt", "sha256": sha("Remote kit licence\n")}],
                    "provenance": "verified",
                },
            ],
        }
        self.lock(REMOTE_REV)
        self.save()

    def write(self, rel: str, text: str) -> None:
        path = self.root / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")

    def lock(self, revision: str) -> None:
        pins = {"pins": [{"identity": "remote-kit", "location": REMOTE_URL + ".git", "state": {"revision": revision, "version": "1.0.0"}}], "version": 3}
        self.write("MacDown2/Packages/MacDownKit/Package.resolved", json.dumps(pins))

    def save(self) -> None:
        """Write the inventory and regenerate outputs so only the mutation under test differs."""
        self.write("compliance/inventory.json", json.dumps(self.inventory, indent=2))
        compliance.main(["--root", str(self.root), "notices"])
        compliance.main(["--root", str(self.root), "sbom"])

    def check(self, **kwargs) -> compliance.Report:
        return compliance.check(self.root, **kwargs)

    def close(self) -> None:
        self.dir.cleanup()


class ComplianceCheckTests(unittest.TestCase):
    def setUp(self) -> None:
        self.fx = Fixture()

    def tearDown(self) -> None:
        self.fx.close()

    def assertFailsWith(self, fragment: str, **kwargs) -> None:
        report = self.fx.check(**kwargs)
        self.assertTrue(any(fragment in e for e in report.errors), f"expected an error containing {fragment!r}, got {report.errors}")

    def test_baseline_fixture_passes_tree_and_release_checks(self) -> None:
        self.assertEqual(self.fx.check().errors, [])
        self.assertEqual(self.fx.check(release=True).errors, [])

    def test_unregistered_component_fails(self) -> None:
        self.fx.write("MacDown2/Packages/MacDownKit/Sources/Widget/Resources/extra.min.js", "window.extra = 1;\n")
        self.assertFailsWith("unregistered distributed file")

    def test_unregistered_swiftpm_dependency_fails(self) -> None:
        self.fx.write(
            "MacDown2/Packages/MacDownKit/Package.swift",
            f'.package(url: "{REMOTE_URL}", exact: "1.0.0"),\n.package(url: "https://github.com/example/new", from: "1.0.0"),\n',
        )
        self.assertFailsWith("is not registered in the inventory")

    def test_unregistered_resolved_package_fails(self) -> None:
        pins = {"pins": [
            {"location": REMOTE_URL, "state": {"revision": REMOTE_REV}},
            {"location": "https://github.com/example/transitive", "state": {"revision": "3" * 40}},
        ]}
        self.fx.write("MacDown2/Packages/MacDownKit/Package.resolved", json.dumps(pins))
        self.assertFailsWith("resolved package https://github.com/example/transitive is not registered")

    def test_deleted_notice_fails(self) -> None:
        (self.fx.root / LIB_LICENCE).unlink()
        self.assertFailsWith("licence/notice text missing")

    def test_edited_notice_fails(self) -> None:
        self.fx.write(LIB_LICENCE, "Truncated\n")
        self.assertFailsWith("licence/notice text changed")

    def test_wrong_digest_fails(self) -> None:
        self.fx.write(LIB_JS, "window.lib = 2;\n")
        self.assertFailsWith("distributed file digest mismatch")

    def test_stale_lockfile_mapping_fails(self) -> None:
        self.fx.lock("4" * 40)
        self.assertFailsWith("stale mapping")

    def test_stale_manifest_mapping_fails(self) -> None:
        self.fx.write("MacDown2/Packages/MacDownKit/Package.swift", f'.package(url: "{REMOTE_URL}", exact: "1.1.0"),\n')
        self.assertFailsWith("stale mapping")

    def test_missing_required_source_location_fails(self) -> None:
        self.fx.inventory["components"][0]["source_offer"]["location"] = ""
        self.fx.save()
        self.assertFailsWith("no source location is recorded")

    def test_unverified_source_location_fails_release_only(self) -> None:
        self.fx.inventory["components"][0]["source_offer"]["status"] = "planned"
        self.fx.save()
        self.assertEqual(self.fx.check().errors, [])
        self.assertFailsWith("not verified by anonymous retrieval", release=True)

    def test_lockfile_findings_are_unverified_until_enforced(self) -> None:
        self.fx.inventory["lockfile_enforced"] = False
        self.fx.save()
        self.fx.lock("4" * 40)
        report = self.fx.check()
        self.assertEqual(report.errors, [])
        self.assertTrue(any("stale mapping" in w for w in report.warnings))
        self.assertFailsWith("stale mapping", release=True)

    def test_missing_lockfile_is_unverified_in_tree_mode_and_fails_release(self) -> None:
        self.fx.inventory["lockfile_enforced"] = False
        self.fx.save()
        (self.fx.root / "MacDown2/Packages/MacDownKit/Package.resolved").unlink()
        report = self.fx.check()
        self.assertEqual(report.errors, [])
        self.assertTrue(any("no Package.resolved" in w for w in report.warnings))
        self.assertFailsWith("no Package.resolved", release=True)

    def test_pending_component_fails_release(self) -> None:
        self.fx.inventory["components"][1]["resolution"] = "pending-lockfile"
        self.fx.inventory["components"][1]["provenance"] = "pending"
        self.fx.save()
        self.assertFailsWith("revision still pending", release=True)

    def test_open_item_fails_release(self) -> None:
        self.fx.inventory["components"][1]["open_items"] = ["needs a look"]
        self.fx.save()
        self.assertFailsWith("open item: needs a look", release=True)

    def test_stale_generated_notices_fail(self) -> None:
        self.fx.inventory["components"][1]["copyright"] = ["Copyright Someone Else"]
        self.fx.write("compliance/inventory.json", json.dumps(self.fx.inventory, indent=2))
        self.assertFailsWith("generated file is stale")

    def test_artifact_missing_bundle_fails(self) -> None:
        app = self.fx.root / "build/Example.app/Contents/Resources"
        app.mkdir(parents=True)
        shutil.copy(self.fx.root / compliance.NOTICES, app / "THIRD_PARTY_NOTICES.md")
        self.assertFailsWith("is not in the artifact", artifact=self.fx.root / "build/Example.app")
        shutil.copy(self.fx.root / LIB_JS, app / "lib.js")
        self.assertEqual(self.fx.check(artifact=self.fx.root / "build/Example.app").errors, [])

    def test_artifact_without_notices_fails(self) -> None:
        app = self.fx.root / "build/Example.app/Contents/Resources"
        app.mkdir(parents=True)
        shutil.copy(self.fx.root / LIB_JS, app / "lib.js")
        self.assertFailsWith("does not contain the generated THIRD_PARTY_NOTICES.md", artifact=self.fx.root / "build/Example.app")

    def test_generation_is_deterministic(self) -> None:
        inventory = compliance.load_inventory(self.fx.root)
        self.assertEqual(compliance.render_notices(self.fx.root, inventory), compliance.render_notices(self.fx.root, inventory))
        self.assertEqual(compliance.render_sbom(self.fx.root, inventory), compliance.render_sbom(self.fx.root, inventory))


class RepositoryTests(unittest.TestCase):
    def test_committed_inventory_passes_tree_check(self) -> None:
        report = compliance.check(REPO)
        self.assertEqual(report.errors, [], "\n".join(report.errors))

    def test_every_manifest_dependency_is_parsed(self) -> None:
        text = (REPO / "MacDown2/Packages/MacDownKit/Package.swift").read_text(encoding="utf-8")
        urls, paths = compliance.parse_manifest(text)
        self.assertEqual(len(urls), text.count(".package(url:"))
        self.assertEqual(len(paths), text.count(".package(path:"))


if __name__ == "__main__":
    unittest.main()
