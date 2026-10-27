"""Real local Git patch regressions; no compiler, dependency fetch or app process."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

import native_stage as runner

PRODUCT = 'f5605d9aead306e15ccb1bd8fb4f48b8931c1f76'
NEON = 'dabf50c947148c49acd0d321dfe8f3805d10b3da'
PREFIX = 'MacDown2/Packages/MacDownKit'
NEW_HARNESS = runner.HARNESS_TARGETS[-1]


def git(root, *args):
    return subprocess.check_output(['git', *args], cwd=root, stderr=subprocess.STDOUT, timeout=15)


def initialize(root):
    git(root, 'init', '-q')
    git(root, 'add', '.')
    # These overrides affect only this newly created, disposable test repository.
    git(root, '-c', 'user.name=Diagnostic Fixture', '-c', 'user.email=fixture@example.invalid',
        '-c', 'commit.gpgsign=false', '-c', 'core.hooksPath=/dev/null', 'commit', '-qm', 'fixture baseline')


class NestedGitPatchTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        source = os.environ.get('NEON_DIAGNOSTIC_PRODUCT_SOURCE')
        if not source and os.environ.get('GITHUB_WORKSPACE'):
            source = str(Path(os.environ['GITHUB_WORKSPACE']) / 'product')
        if not source:
            raise RuntimeError('Exact product source required; no silent regression-test skip')
        source = Path(source)
        cls.product_files = {p: git(source, 'show', PRODUCT + ':' + PREFIX + '/' + p)
                             for p in runner.HARNESS_TARGETS if p != NEW_HARNESS}
        harness = Path(os.environ.get('NEON_DIAGNOSTIC_HARNESS_PATCH', str(runner.ROOT / 'lifecycle-harness.patch')))
        cls.harness = harness.read_bytes()
        if hashlib.sha256(cls.harness).hexdigest() != runner.HARNESS_PATCH:
            raise RuntimeError('Harness fixture is not the accepted patch')
        actual_neon = os.environ.get('NEON_DIAGNOSTIC_NEON_SOURCE')
        cls.neon_files = {}
        if actual_neon:
            source = Path(actual_neon)
            patch_path = Path(os.environ['NEON_DIAGNOSTIC_NEON_PATCH'])
            cls.neon_patch = patch_path.read_bytes()
            if hashlib.sha256(cls.neon_patch).hexdigest() != runner.NEON_PATCH:
                raise RuntimeError('Neon fixture patch mismatch')
            new_paths = {'Sources/RangeState/OrderingTrace.swift', runner.NEON_TARGETS[-1]}
            cls.neon_files = {p: git(source, 'show', NEON + ':' + p) for p in runner.NEON_TARGETS if p not in new_paths}
            cls.neon_mode = 'actual-pinned-source'
        else:
            # CI runs helpers before dependency fetching. This first-party toy patch
            # exercises the exact Neon path shape without vendoring dependency code.
            chunks = []
            for p in runner.NEON_TARGETS:
                cls.neon_files[p] = b'old fixture\n'
                chunks.append(f'diff --git a/{p} b/{p}\n--- a/{p}\n+++ b/{p}\n@@ -1 +1 @@\n-old fixture\n+new fixture\n')
            cls.neon_patch = ''.join(chunks).encode()
            cls.neon_mode = 'synthetic-path-only-before-fetch'

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='neon-nested-git-')
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()
        self.repo = self.root / 'product'
        self.package = self.repo / PREFIX
        self.scratch = self.root / 'scratch'
        self.neon = self.scratch / 'checkouts/Neon'
        self.diag_repo = self.root / 'diagnostic'
        self.diag = self.diag_repo / 'diagnostics/neon-ordering-532'
        for base, files in ((self.package, self.product_files), (self.neon, self.neon_files)):
            for name, data in files.items():
                target = base / name
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(data)
        initialize(self.neon)
        self.neon_head = git(self.neon, 'rev-parse', 'HEAD').decode().strip()
        pins = [{'identity': 'neon', 'location': 'https://example.invalid/Neon', 'state': {'revision': self.neon_head}}]
        lock = self.package / 'Package.resolved'
        lock.write_text(json.dumps({'pins': pins}))
        initialize(self.repo)
        self.product_head = git(self.repo, 'rev-parse', 'HEAD').decode().strip()
        self.lock_hash = hashlib.sha256(lock.read_bytes()).hexdigest()
        state = {'object': {'dependencies': [{'packageRef': {'identity': 'neon', 'kind': 'remoteSourceControl',
            'location': pins[0]['location']}, 'subpath': 'Neon',
            'state': {'checkoutState': {'revision': self.neon_head}}}]}}
        (self.scratch / 'workspace-state.json').write_text(json.dumps(state))
        for name in runner.PAYLOAD:
            target = self.diag_repo / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text('fixture metadata placeholder\n')
        (self.diag / 'ordering-diagnostic.patch').write_bytes(self.neon_patch)
        (self.diag / 'lifecycle-harness.patch').write_bytes(self.harness)
        initialize(self.diag_repo)
        self.diag_head = git(self.diag_repo, 'rev-parse', 'HEAD').decode().strip()

    def assert_targets(self, application):
        self.assertEqual([a['materializedCount'] for a in application['applications']], [8, 5])
        self.assertEqual(set(application['patchedFileHashes']),
            {str((self.neon / p).resolve()) for p in runner.NEON_TARGETS}
            | {str((self.package / p).resolve()) for p in runner.HARNESS_TARGETS})
        self.assertTrue((self.package / NEW_HARNESS).is_file())

    def test_old_silent_skip_then_exact_root_application(self):
        old = subprocess.run(['git', 'apply', '--unidiff-zero', '--verbose', str(self.diag / 'lifecycle-harness.patch')],
                             cwd=self.package, capture_output=True, text=True, timeout=15)
        self.assertEqual(old.returncode, 0)
        self.assertEqual(old.stderr.count('Skipped patch'), 5)
        self.assertFalse((self.package / NEW_HARNESS).exists())
        self.assertEqual(git(self.repo, 'status', '--porcelain'), b'')
        result = runner.prepare_diagnostic_sources(self.repo, self.neon, self.diag)
        self.assert_targets(result)
        print('PATCH_ROOT_EVIDENCE old_exit=0 skipped=5 old_changes=0 corrected_neon=8 corrected_harness=5 mode='+self.neon_mode)

    def test_zero_successful_application_is_rejected(self):
        real = runner.command
        def no_write(*args, cwd=None):
            if args[:2] == ('git', 'apply') and '--check' not in args and Path(cwd) == self.repo:
                return ''
            return real(*args, cwd=cwd)
        with patch.object(runner, 'command', side_effect=no_write):
            with self.assertRaisesRegex(ValueError, 'unchanged|materialize'):
                runner.prepare_diagnostic_sources(self.repo, self.neon, self.diag)

    def test_partial_application_is_rejected(self):
        real = runner.command
        def partial(*args, cwd=None):
            value = real(*args, cwd=cwd)
            if args[:2] == ('git', 'apply') and '--check' not in args and Path(cwd) == self.repo:
                p = runner.HARNESS_TARGETS[0]
                (self.package / p).write_bytes(self.product_files[p])
            return value
        with patch.object(runner, 'command', side_effect=partial):
            with self.assertRaisesRegex(ValueError, 'unchanged'):
                runner.prepare_diagnostic_sources(self.repo, self.neon, self.diag)

    def test_unexpected_changed_file_is_rejected(self):
        real = runner.command
        def collateral(*args, cwd=None):
            value = real(*args, cwd=cwd)
            if args[:2] == ('git', 'apply') and '--check' not in args and Path(cwd) == self.repo:
                (self.repo / 'unexpected.txt').write_text('fixture only')
            return value
        with patch.object(runner, 'command', side_effect=collateral):
            with self.assertRaisesRegex(ValueError, 'exact target scope'):
                runner.prepare_diagnostic_sources(self.repo, self.neon, self.diag)

    def test_nested_directory_cannot_be_mistaken_for_git_root(self):
        with self.assertRaisesRegex(ValueError, 'clean Git root'):
            runner.prepare_diagnostic_sources(self.package, self.neon, self.diag)

    def test_preflight_failure_leaves_both_repositories_clean(self):
        (self.diag / 'lifecycle-harness.patch').write_bytes(
            self.harness.replace(b'-        sizePolicy:', b'-        impossiblePolicy:', 1))
        with self.assertRaises(subprocess.CalledProcessError):
            runner.prepare_diagnostic_sources(self.repo, self.neon, self.diag)
        self.assertEqual(git(self.repo, 'status', '--porcelain'), b'')
        self.assertEqual(git(self.neon, 'status', '--porcelain'), b'')



if __name__ == '__main__':
    unittest.main()
