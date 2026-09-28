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
import re
import shutil
import sys
import tempfile
import unittest
import textwrap
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / "compliance" / "tools"))

import compliance  # noqa: E402

LIB_JS = "MacDown2/Packages/MacDownKit/Sources/Widget/Resources/lib.js"
LIB_LICENCE = "MacDown2/Packages/MacDownKit/Sources/Widget/Resources/LIB-LICENSE.txt"
REMOTE_URL = "https://github.com/example/remote-kit"
REMOTE_REV = "1111111111111111111111111111111111111111"
FONT_BYTES = "OTTO pretend font bytes\n"


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
            "artifact": {
                "required_first_party": ["LICENSE", compliance.NOTICES],
                "registered_extensions": [".js", ".otf", ".wasm"],
            },
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
                    "runtime_resources": [{"name": "lib.js", "sha256": sha("window.lib = 1;\n"), "path": LIB_JS}],
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
                    "runtime_resources": [{"name": "Remote-Font.otf", "sha256": sha(FONT_BYTES), "source": "remote-kit 1.0.0"}],
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

    def make_app(self, *, skip: set[str] = frozenset(), extra: dict[str, str] | None = None) -> Path:
        """A pretend built .app holding what the fixture's contract says ships."""
        app = self.root / "build/Example.app"
        shutil.rmtree(app, ignore_errors=True)
        resources = app / "Contents/Resources"
        (resources / "Remote_Kit.bundle").mkdir(parents=True)
        files = {
            "lib.js": (self.root / LIB_JS).read_text(),
            "Remote_Kit.bundle/Remote-Font.otf": FONT_BYTES,
            "LICENSE": (self.root / "LICENSE").read_text(),
            "THIRD_PARTY_NOTICES.md": (self.root / compliance.NOTICES).read_text(),
            **(extra or {}),
        }
        for name, body in files.items():
            if name not in skip:
                (resources / name).write_text(body, encoding="utf-8")
        return app

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

    # ------------------------------------------------------------ artifact

    def test_complete_artifact_passes_release_check(self) -> None:
        self.assertEqual(self.fx.check(release=True, artifact=self.fx.make_app()).errors, [])

    def test_artifact_missing_vendored_engine_fails(self) -> None:
        self.assertFailsWith("required runtime resource lib.js", artifact=self.fx.make_app(skip={"lib.js"}))

    def test_artifact_missing_dependency_font_fails(self) -> None:
        self.assertFailsWith("required runtime resource Remote-Font.otf", artifact=self.fx.make_app(skip={"Remote_Kit.bundle/Remote-Font.otf"}))

    def test_artifact_with_modified_runtime_resource_fails(self) -> None:
        app = self.fx.make_app(extra={"lib.js": "window.lib = 'patched after build';\n"})
        self.assertFailsWith("required runtime resource lib.js", artifact=app)

    def test_artifact_without_notices_fails(self) -> None:
        self.assertFailsWith("does not contain the generated THIRD_PARTY_NOTICES.md", artifact=self.fx.make_app(skip={"THIRD_PARTY_NOTICES.md"}))

    def test_artifact_with_stale_notices_fails(self) -> None:
        app = self.fx.make_app(extra={"THIRD_PARTY_NOTICES.md": "# an older notices file\n"})
        self.assertFailsWith("does not contain the generated THIRD_PARTY_NOTICES.md", artifact=app)

    def test_artifact_without_first_party_licence_fails(self) -> None:
        self.assertFailsWith("does not contain first-party LICENSE", artifact=self.fx.make_app(skip={"LICENSE"}))

    def test_artifact_shipping_unregistered_font_or_script_fails(self) -> None:
        for name in ("Surprise.otf", "tracker.js", "engine.wasm"):
            with self.subTest(name=name):
                self.assertFailsWith(f"unregistered runtime file: Contents/Resources/{name}", artifact=self.fx.make_app(extra={name: "unknown\n"}))

    def test_artifact_may_ship_first_party_scripts(self) -> None:
        self.fx.write("MacDown2/Packages/MacDownKit/Sources/Widget/Resources/render.js", "render();\n")
        self.fx.inventory["first_party"]["paths"].append("MacDown2/**/render.js")
        self.fx.save()
        self.assertEqual(self.fx.check(artifact=self.fx.make_app(extra={"render.js": "render();\n"})).errors, [])

    def test_stale_runtime_resource_digest_fails_in_tree_mode(self) -> None:
        self.fx.inventory["components"][0]["runtime_resources"][0]["sha256"] = "0" * 64
        self.fx.save()
        self.assertFailsWith("runtime resource digest is stale")

    def test_vendored_bundle_without_runtime_resources_fails(self) -> None:
        del self.fx.inventory["components"][0]["runtime_resources"]
        self.fx.save()
        self.assertFailsWith("must declare runtime_resources")

    def test_missing_artifact_fails(self) -> None:
        self.assertFailsWith("artifact not found", artifact=self.fx.root / "build/Nope.app")

    # ------------------------------------------------------------ manifests

    def test_unregistered_multiline_dependency_fails(self) -> None:
        self.fx.write("MacDown2/Packages/MacDownKit/Package.swift", textwrap.dedent(f"""\
            dependencies: [
                .package(url: "{REMOTE_URL}", exact: "1.0.0"),
                .package(
                    url: "https://github.com/example/sneaky",
                    exact: "2.0.0"
                ),
            ]
            """))
        self.assertFailsWith("dependency https://github.com/example/sneaky is not registered")

    def test_multiline_requirement_change_is_a_stale_mapping(self) -> None:
        self.fx.write("MacDown2/Packages/MacDownKit/Package.swift",
                      f'.package(\n    url: "{REMOTE_URL}",\n    branch: "main"\n)\n')
        self.assertFailsWith("stale mapping")

    def test_range_requirement_never_matches_a_recorded_one(self) -> None:
        self.fx.write("MacDown2/Packages/MacDownKit/Package.swift", f'.package(url: "{REMOTE_URL}", "1.0.0"..<"2.0.0")\n')
        self.assertFailsWith("stale mapping")

    def test_commented_out_dependencies_are_ignored(self) -> None:
        self.fx.write("MacDown2/Packages/MacDownKit/Package.swift", textwrap.dedent(f"""\
            // .package(url: "https://github.com/example/old", exact: "1.0.0"),
            /* .package(
                url: "https://github.com/example/older", exact: "1.0.0") */
            .package(url: "{REMOTE_URL}", exact: "1.0.0"), // "https://not/a/dep"
            """))
        self.assertEqual(self.fx.check().errors, [])

    def test_unrecognised_package_declaration_fails_closed(self) -> None:
        self.fx.write("MacDown2/Packages/MacDownKit/Package.swift",
                      f'.package(url: "{REMOTE_URL}", exact: "1.0.0"),\n.package(id: "example.registry", from: "1.0.0"),\n')
        self.assertFailsWith("unrecognised package declaration")

    def test_unowned_multiline_local_package_fails(self) -> None:
        self.fx.write("MacDown2/Packages/MacDownKit/Package.swift",
                      f'.package(url: "{REMOTE_URL}", exact: "1.0.0"),\n.package(\n    path: "../Sneaky"\n),\n')
        self.assertFailsWith("local package MacDown2/Packages/Sneaky is not owned")

    def test_new_local_package_manifest_is_checked_automatically(self) -> None:
        self.fx.write("MacDown2/Packages/Helper/Package.swift", '.package(url: "https://github.com/example/transitive-sneak", from: "1.0.0")\n')
        self.assertFailsWith("MacDown2/Packages/Helper/Package.swift: dependency https://github.com/example/transitive-sneak is not registered")

    def test_unregistered_xcodegen_package_fails(self) -> None:
        self.fx.write("MacDown2/project.yml", textwrap.dedent("""\
            name: Example
            packages:
              Sneaky:
                url: https://github.com/example/xcodegen-sneak
                from: 1.0.0
            targets: {}
            """))
        self.assertFailsWith("project.yml: package https://github.com/example/xcodegen-sneak is not registered")

    def test_xcodegen_package_outside_the_checked_tree_fails(self) -> None:
        self.fx.write("MacDown2/project.yml", "packages:\n  Outside:\n    path: ../../elsewhere\n")
        self.assertFailsWith("outside MacDown2/")

    def test_unregistered_file_in_existing_target_fails(self) -> None:
        self.fx.write("MacDown2/Packages/MacDownKit/Sources/Widget/vendor.c", "int x;\n")
        self.assertFailsWith("unregistered distributed file")

    def test_generation_is_deterministic(self) -> None:
        inventory = compliance.load_inventory(self.fx.root)
        self.assertEqual(compliance.render_notices(self.fx.root, inventory), compliance.render_notices(self.fx.root, inventory))
        self.assertEqual(compliance.render_sbom(self.fx.root, inventory), compliance.render_sbom(self.fx.root, inventory))


class ManifestParserTests(unittest.TestCase):
    def test_single_and_multiline_forms_agree(self) -> None:
        single = '.package(url: "https://github.com/a/b", exact: "1.0.0")\n.package(path: "../X")\n'
        multi = '.package(\n    url: "https://github.com/a/b",\n    exact: "1.0.0"\n)\n.package(\n  path: "../X"\n)\n'
        self.assertEqual(compliance.parse_manifest(single), compliance.parse_manifest(multi))
        self.assertEqual(compliance.parse_manifest(single), ([("https://github.com/a/b", {"exact": "1.0.0"})], ["../X"], []))

    def test_requirement_keywords(self) -> None:
        for requirement, expected in (('exact: "1.0.0"', {"exact": "1.0.0"}), ('from: "1.0.0"', {"from": "1.0.0"}),
                                      ('branch: "main"', {"branch": "main"}), ('revision: "abc"', {"revision": "abc"}),
                                      ('.upToNextMinor(from: "0.25.0")', {"from": "0.25.0", "form": "upToNextMinor"})):
            with self.subTest(requirement=requirement):
                urls, _, _ = compliance.parse_manifest(f'.package(url: "https://github.com/a/b", {requirement})')
                self.assertEqual(urls[0][1], expected)


class RepositoryTests(unittest.TestCase):
    def test_committed_inventory_passes_tree_check(self) -> None:
        report = compliance.check(REPO)
        self.assertEqual(report.errors, [], "\n".join(report.errors))

    def test_every_manifest_dependency_is_parsed(self) -> None:
        """Checks the parser against oracles that don't share its logic.

        1. Every quoted http(s) URL outside a // comment line is a dependency.
        2. The number of `.package(` tokens outside // comment lines equals
           the number of parsed declarations, and none is unrecognised.
        3. Reflowing every declaration onto multiple lines changes nothing.
        """
        for manifest in sorted(REPO.glob("MacDown2/Packages/*/Package.swift")):
            with self.subTest(manifest=manifest.relative_to(REPO).as_posix()):
                text = manifest.read_text(encoding="utf-8")
                code_lines = [line for line in text.splitlines() if not line.lstrip().startswith("//")]
                code = "\n".join(code_lines)
                urls, paths, unknown = compliance.parse_manifest(text)
                self.assertEqual(unknown, [])
                self.assertEqual({u for u, _ in urls}, set(re.findall(r'"(https?://[^"]+)"', code)))
                self.assertEqual(len(urls) + len(paths), len(re.findall(r"\.package\s*\(", code)))
                reflowed = re.sub(r",\s*(url|path|exact|from|branch|revision|name):", r",\n        \1:", text)
                reflowed = reflowed.replace(".package(", ".package(\n        ")
                self.assertNotEqual(reflowed, text)
                self.assertEqual(compliance.parse_manifest(reflowed), (urls, paths, unknown))

    def test_compliance_workflow_cannot_be_skipped_by_path_filters(self) -> None:
        """The check walks the whole tree, so the workflow must run on every change."""
        workflow = (REPO / ".github/workflows/compliance.yml").read_text(encoding="utf-8")
        triggers = workflow.split("\njobs:", 1)[0]
        self.assertNotRegex(triggers, r"(?m)^\s*(paths|paths-ignore|branches-ignore)\s*:")
        self.assertRegex(triggers, r"(?m)^  pull_request:")
        self.assertRegex(triggers, r"(?m)^  push:")
        self.assertIn("python3 compliance/tools/compliance.py check\n", workflow)
        self.assertIn("python3 -m unittest discover -s compliance/tests", workflow)

    def test_every_vendored_bundle_and_math_font_is_in_the_artifact_contract(self) -> None:
        inventory = compliance.load_inventory(REPO)
        by_id = {c["id"]: c for c in inventory["components"]}
        for component in inventory["components"]:
            if component["kind"] == "vendored-bundle":
                self.assertTrue(component.get("runtime_resources"), component["id"])
        fonts = {r["name"] for r in by_id["swiftui-math-fonts"]["runtime_resources"]}
        self.assertEqual(len(fonts), len(by_id["swiftui-math-fonts"]["fonts"]))
        self.assertTrue(all(name.endswith(".otf") for name in fonts))


if __name__ == "__main__":
    unittest.main()
