"""Behavioural tests for release/macos/sign-notarize-dmg.sh.

The script only does real work on a Mac, but its control flow (which mode
tolerates which failure) can be tested anywhere bash runs. Each test copies
the script into a throwaway git repository, puts stub versions of the Apple
tools and of compliance.py on PATH, and runs it.

The invariant under test: --dry-run records an incomplete release gate as
UNVERIFIED and continues; --release-candidate stops on the same condition,
and stops on a failing licence gate before anything is sent to Apple.

Run: python3 -m unittest discover -s compliance/tests
"""

from __future__ import annotations

import os
import shutil
import subprocess
import tempfile
import textwrap
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
SCRIPT = REPO / "release/macos/sign-notarize-dmg.sh"

STUBS = {
    "security": 'echo \'  1) ABCDEF "Developer ID Application: Test Owner (TEAMID1234)"\'',
    "sw_vers": 'echo 26.0',
    "xcodegen": "true",
    "spctl": "true",
    "shasum": 'shift 2; for f in "$@"; do echo "0000  $f"; done',
    "defaults": 'case "$3" in CFBundleShortVersionString) echo 0.1.0;; CFBundleVersion) echo 7;; *) echo com.example.App;; esac',
    "codesign": 'case "$*" in *-d*) printf "Authority=Developer ID Application: Test Owner (TEAMID1234)\\nTimestamp=now\\nflags=0x10000(runtime)\\n" >&2;; esac; true',
    "hdiutil": 'for last in "$@"; do :; done; touch "$last"',
    "ditto": 'if [ "$1" = -c ]; then for last in "$@"; do :; done; touch "$last"; else cp -R "$1" "$2"; fi',
    "xcodebuild": textwrap.dedent("""\
        if [ "$1" = -version ]; then echo "Xcode 26.0"; exit 0; fi
        while [ $# -gt 0 ]; do
          case "$1" in -derivedDataPath) dd="$2"; shift;; -scheme) scheme="$2"; shift;; esac; shift
        done
        out="$dd/Build/Products/Release"; mkdir -p "$out"
        if [ "$scheme" = MacDown2 ]; then mkdir -p "$out/MacDown2.app/Contents"; touch "$out/MacDown2.app/Contents/Info"
        else touch "$out/macdown2"; fi"""),
    "xcrun": textwrap.dedent("""\
        echo "xcrun $*" >> "$CALLS"
        case "$1 $2" in
          "notarytool submit") printf '{"id": "sub-1", "status": "%s"}\\n' "${NOTARY_STATUS:-Accepted}";;
          "notarytool log") [ "${NOTARY_LOG_FAILS:-0}" = 1 ] && exit 1; for last in "$@"; do :; done; echo '{}' > "$last";;
        esac
        true"""),
}

FAKE_COMPLIANCE = textwrap.dedent("""\
    import os, sys
    if os.environ.get("COMPLIANCE_FAILS") == "1":
        print("FAIL: example release-gate failure")
        sys.exit(1)
    print("compliance check (release): passed")
    """)


class ReleaseScriptModeTests(unittest.TestCase):
    def setUp(self) -> None:
        if shutil.which("bash") is None or shutil.which("git") is None:
            self.skipTest("needs bash and git")
        self.tmp = tempfile.TemporaryDirectory()
        base = Path(self.tmp.name)
        self.repo = base / "repo"
        (self.repo / "release/macos").mkdir(parents=True)
        (self.repo / "compliance/tools").mkdir(parents=True)
        (self.repo / "MacDown2").mkdir()
        shutil.copy(SCRIPT, self.repo / "release/macos/sign-notarize-dmg.sh")
        (self.repo / "compliance/tools/compliance.py").write_text(FAKE_COMPLIANCE)
        (self.repo / ".gitignore").write_text("build/\n")
        bin_dir = base / "bin"
        bin_dir.mkdir()
        for name, body in STUBS.items():
            stub = bin_dir / name
            stub.write_text("#!/usr/bin/env bash\n" + body + "\n")
            stub.chmod(0o755)
        self.calls = base / "calls.log"
        self.calls.touch()
        git = ["git", "-C", str(self.repo)]
        subprocess.run([*git, "init", "-q"], check=True)
        subprocess.run([*git, "add", "-A"], check=True)
        subprocess.run([*git, "-c", "user.name=t", "-c", "user.email=t@e", "commit", "-qm", "init"], check=True)
        self.env = {**os.environ, "PATH": f"{bin_dir}{os.pathsep}{os.environ['PATH']}", "CALLS": str(self.calls),
                    "TEAM_ID": "TEAMID1234", "NOTARY_PROFILE": "profile", "OUT": str(base / "out")}
        self.out = base / "out"

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def run_script(self, *args: str, **env: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(["bash", str(self.repo / "release/macos/sign-notarize-dmg.sh"), *args],
                              env={**self.env, **env}, capture_output=True, text=True, timeout=60)

    def summary(self) -> str:
        return (self.out / "evidence/summary.txt").read_text()

    def test_mode_is_required(self) -> None:
        result = self.run_script()
        self.assertEqual(result.returncode, 2)
        self.assertIn("usage:", result.stderr)

    def test_preflight_builds_signs_and_submits_nothing(self) -> None:
        result = self.run_script("--preflight-only")
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertFalse((self.out / "DerivedData").exists())
        self.assertNotIn("notarytool submit", self.calls.read_text())

    def test_dry_run_records_failed_licence_gate_and_log_as_unverified_and_continues(self) -> None:
        result = self.run_script("--dry-run", COMPLIANCE_FAILS="1", NOTARY_LOG_FAILS="1")
        self.assertEqual(result.returncode, 0, result.stdout)
        summary = self.summary()
        self.assertIn("UNVERIFIED (dry run): licence gate", summary)
        self.assertIn("notarisation log app: NOT captured", summary)
        self.assertIn("UNVERIFIED (dry run): the notarisation log for app", summary)
        self.assertTrue((self.out / "MacDown2-0.1.0-7-dryrun.dmg").exists())

    def test_release_candidate_stops_on_licence_gate_before_contacting_apple(self) -> None:
        result = self.run_script("--release-candidate", COMPLIANCE_FAILS="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("STOP: licence gate", result.stdout)
        self.assertNotIn("notarytool submit", self.calls.read_text())

    def test_release_candidate_stops_when_notarisation_log_is_missing(self) -> None:
        result = self.run_script("--release-candidate", NOTARY_LOG_FAILS="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("STOP: the notarisation log for app", result.stdout)

    def test_rejected_notarisation_stops_every_mode_and_keeps_the_log(self) -> None:
        for mode in ("--dry-run", "--release-candidate"):
            with self.subTest(mode=mode):
                shutil.rmtree(self.out, ignore_errors=True)
                result = self.run_script(mode, NOTARY_STATUS="Invalid")
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("returned 'Invalid'", result.stdout)
                self.assertTrue((self.out / "evidence/notary-app-log.json").exists())

    def test_release_candidate_requires_a_clean_tree(self) -> None:
        (self.repo / "untracked.txt").write_text("dirty\n")
        result = self.run_script("--release-candidate")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("clean working tree", result.stdout)

    def test_release_candidate_passes_when_every_gate_passes(self) -> None:
        result = self.run_script("--release-candidate")
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn("licence gate: passed", self.summary())
        self.assertNotIn("UNVERIFIED", self.summary())
        self.assertTrue((self.out / "MacDown2-0.1.0-7.dmg").exists())
        sums = (self.out / "evidence/SHA256SUMS").read_text()
        self.assertIn("macdown2.zip", sums.split("# not distributed")[0])


if __name__ == "__main__":
    unittest.main()
