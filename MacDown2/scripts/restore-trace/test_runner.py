"""Adapter-level controls: diagnostic I/O must preserve a known test exit."""
from contextlib import ExitStack
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("restore_runner", Path(__file__).with_name("collect.py"))
collector = importlib.util.module_from_spec(spec)
spec.loader.exec_module(collector)


def invoke_main(*, final_write_error=False, log_hash_error=False, original_exit=7):
    with tempfile.TemporaryDirectory() as temporary, ExitStack() as stack:
        base = Path(temporary)
        repo, workspace, output = base / "repo", base / "workspace", base / "output"
        package = repo / "MacDown2/Packages/MacDownKit"
        package.mkdir(parents=True)
        (repo / ".git").mkdir()
        lock = package / "Package.resolved"
        lock.write_text(json.dumps({"pins": [{}] * 22}))
        patch_dir = repo / collector.PATCH_DIRECTORY
        patch_dir.mkdir(parents=True)
        neon_patch, package_patch = patch_dir / "neon.patch", patch_dir / "package.patch"
        neon_patch.write_text("synthetic patch")
        package_patch.write_text("synthetic patch")
        observer_path = repo / "MacDown2/scripts/crash-capture/capture.py"
        observer_path.parent.mkdir(parents=True)
        observer_path.write_text("synthetic observer")
        original_sha = collector.sha256_file

        def export(_repo, work, _out, _run):
            parent = work / "MacDown2/Packages"
            root = parent / "MacDownKit"
            (root / ".build/checkouts/Neon").mkdir(parents=True)
            (root / "Package.resolved").write_bytes(lock.read_bytes())
            return parent

        def sha(path):
            if log_hash_error and path.name == "test.log":
                raise OSError("synthetic post-command hash failure")
            return original_sha(path)

        observed = {"shell_exit_code": original_exit, "processes": [], "observer_errors": {},
                    "coverage": {}, "capture": {"outcome": "no_matching_report"}}
        fake_capture = SimpleNamespace(observed_command=lambda *a, **k: observed)
        fake_spec = SimpleNamespace(name="synthetic_capture", loader=SimpleNamespace(exec_module=lambda module: None))
        stack.enter_context(patch.object(collector.importlib.util, "spec_from_file_location", return_value=fake_spec))
        stack.enter_context(patch.object(collector.importlib.util, "module_from_spec", return_value=fake_capture))
        stack.enter_context(patch.object(sys, "argv", ["collect", "--repo", str(repo), "--workspace", str(workspace), "--output", str(output)]))
        stack.enter_context(patch.dict(os.environ, {}, clear=True))
        stack.enter_context(patch.object(collector, "LOCK_SHA", original_sha(lock)))
        stack.enter_context(patch.object(collector, "git", return_value="synthetic-head"))
        stack.enter_context(patch.object(collector, "source_attestation", return_value={"outcome": "passed", "head_sha": "synthetic-head", "tree_sha": "synthetic-head"}))
        stack.enter_context(patch.object(collector, "archive_packages", side_effect=export))
        stack.enter_context(patch.object(collector, "run_command", return_value={"outcome": "passed"}))
        stack.enter_context(patch.object(collector, "patch_paths", side_effect=lambda p, _: sorted(collector.ALLOWED_PACKAGE_PATCH_PATHS) if p.name == "package.patch" else ["Sources/Neon/Synthetic.swift"]))
        stack.enter_context(patch.object(collector, "patch_numstat", return_value=[]))
        stack.enter_context(patch.object(collector, "snapshot_preimage", return_value={}))
        stack.enter_context(patch.object(collector, "snapshot_files", return_value={}))
        stack.enter_context(patch.object(collector, "apply_patch"))
        stack.enter_context(patch.object(collector, "audit_checkouts", return_value=[{}] * 22))
        stack.enter_context(patch.object(collector, "audit_post_diagnostic_checkouts", return_value=[{}] * 22))
        stack.enter_context(patch.object(collector, "locate_test_bundle", return_value=base / "synthetic.xctest"))
        stack.enter_context(patch.object(collector, "validate_traces", return_value={"outcome": "passed"}))
        stack.enter_context(patch.object(collector, "verify_snapshots", return_value={"outcome": "passed"}))
        stack.enter_context(patch.object(collector, "sha256_file", side_effect=sha))
        if final_write_error:
            stack.enter_context(patch.object(collector, "write_run", side_effect=OSError("synthetic evidence-write failure")))
        result = collector.main()
        record = json.loads((output / "run.json").read_text()) if (output / "run.json").exists() else None
        return result, record


class OriginalExitTests(unittest.TestCase):
    def test_final_write_error_preserves_known_failure(self):
        code, record = invoke_main(final_write_error=True)
        self.assertEqual(code, 7)
        self.assertIsNone(record)

    def test_post_command_log_hash_error_preserves_known_failure(self):
        code, record = invoke_main(log_hash_error=True)
        self.assertEqual(code, 7)
        self.assertEqual(record["original_test_exit"], 7)
        self.assertEqual(record["diagnostic_integrity"], "unavailable")

    def test_diagnostic_failure_is_separate_from_passing_original_command(self):
        code, record = invoke_main(log_hash_error=True, original_exit=0)
        self.assertEqual(code, 0)
        self.assertEqual(record["diagnostic_integrity"], "unavailable")

    def test_closed_stdout_cannot_replace_original_exit_during_shutdown(self):
        child = subprocess.run([sys.executable, "-B", str(Path(__file__)), "--closed-stdout-control"],
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.assertEqual(child.returncode, 7, child.stderr.decode())


if __name__ == "__main__":
    if "--closed-stdout-control" in sys.argv:
        os.close(1)
        raise SystemExit(invoke_main()[0])
    unittest.main()
