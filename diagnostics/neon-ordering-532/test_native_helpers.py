"""Lightweight native-stage and stream fixtures; never run Swift or signal a process."""
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import cap_stream
import native_stage as stage
import test_patch_root as fixtures
from test_lifecycle_helpers import fixture_log
from crash_reports import crashed_process, collect


class StreamTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='neon-native-stream-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def test_exact_bound_preserves_bytes(self):
        data = b'\0a\r\n' * (stage.CAP // 4)
        path = self.root / 'lifecycle-test.log'
        self.assertEqual(cap_stream.capture(io.BytesIO(data), path), 0)
        self.assertEqual(path.read_bytes(), data)

    def test_overflow_drains_without_signals_and_marks_before_eof(self):
        path = self.root / 'lifecycle-test.log'
        class Source:
            count = 0
            def read(self, count):
                self.count += 1
                if self.count == 66:
                    self_marker = path.with_name(path.name + '.overflow.json')
                    if not self_marker.is_file():
                        raise AssertionError('Overflow not recorded before EOF')
                    return b''
                return b'x' * count
        source = Source()
        self.assertEqual(cap_stream.capture(source, path), 1)
        self.assertEqual(source.count, 66)
        self.assertEqual(path.stat().st_size, stage.CAP)

    def test_refuses_overwrite_and_symlink(self):
        path = self.root / 'lifecycle-test.log'
        path.write_bytes(b'original')
        with self.assertRaises(ValueError): cap_stream.capture(io.BytesIO(b'new'), path)
        path.unlink()
        outside = self.root / 'outside'
        outside.write_bytes(b'original')
        path.symlink_to(outside)
        with self.assertRaises(ValueError): cap_stream.capture(io.BytesIO(b'new'), path)
        self.assertEqual(outside.read_bytes(), b'original')

    def test_unexpected_filename_and_read_failure_fail(self):
        with self.assertRaises(ValueError):
            cap_stream.capture(io.BytesIO(b'x'), self.root / 'random.log')
        class Broken:
            def read(self, count): raise OSError('fixture')
        with self.assertRaises(OSError):
            cap_stream.capture(Broken(), self.root / 'helper-tests.log')

    def test_fixed_shell_pipeline_propagates_producer_and_sink_failure(self):
        for index, producer in enumerate(('printf okay', '(printf okay; exit 7)',
                '"$PYTHON" -c \'import sys; sys.stdout.buffer.write(b"x" * 1048577)\'')):
            temp = self.root / str(index)
            evidence = temp / 'neon532-evidence'
            evidence.mkdir(parents=True)
            script = '''set -euo pipefail
set +e
''' + producer + ''' 2>&1 | "$PYTHON" "$SINK" "$EVIDENCE/lifecycle-test.log"
statuses=("${PIPESTATUS[@]}")
set -e
test "${statuses[0]}" -eq 0 && test "${statuses[1]}" -eq 0
'''
            result = subprocess.run(['/bin/bash', '-c', script], capture_output=True, text=True,
                timeout=10, env=dict(os.environ, RUNNER_TEMP=str(temp), EVIDENCE=str(evidence),
                                    PYTHON=sys.executable, SINK=str(Path(cap_stream.__file__))))
            self.assertEqual(result.returncode, 0 if index == 0 else 1, result.stderr)


class HostedPathTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='neon-native-paths-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.workspace = self.root / 'workspace'
        self.real_temp = self.root / 'real-temp'
        self.real_temp.mkdir()
        self.alias = self.root / 'temp-alias'
        self.alias.symlink_to(self.real_temp, target_is_directory=True)
        env = dict(RUNNER_TEMP=str(self.alias), GITHUB_WORKSPACE=str(self.workspace),
            PRODUCT=str(self.workspace/'product'),
            PACKAGE=str(self.workspace/'product/MacDown2/Packages/MacDownKit'),
            SCRATCH=str(self.alias/'neon532-scratch'), EVIDENCE=str(self.alias/'neon532-evidence'))
        for mock in (patch.dict(os.environ, env),
                     patch.object(stage, 'ROOT', self.workspace/'diagnostic-source/diagnostics/neon-ordering-532')):
            mock.start()
            self.addCleanup(mock.stop)

    def test_environment_root_alias_is_canonicalized(self):
        self.assertEqual(stage.paths()[2:],
            (self.real_temp/'neon532-scratch', self.real_temp/'neon532-evidence'))

    def test_redirected_child_is_still_rejected(self):
        outside = self.root/'outside'
        outside.mkdir()
        (self.real_temp/'neon532-evidence').symlink_to(outside, target_is_directory=True)
        with self.assertRaisesRegex(ValueError, 'redirected'):
            stage.paths()


class EvidenceLimitTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='neon-native-evidence-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def test_metadata_cap_checked_before_write_and_replacement(self):
        path = self.root / 'state.json'
        stage.write_json(path, {'a': 1}, 32)
        before = path.read_bytes()
        with self.assertRaises(ValueError):
            stage.write_json(path, {'big': 'x' * 100}, 32, replace=True)
        self.assertEqual(path.read_bytes(), before)

    def test_no_symlinks_or_unknown_files(self):
        path = self.root / 'state.json'
        path.symlink_to(self.root / 'absent')
        with self.assertRaises(ValueError): stage.audit_evidence(self.root)
        path.unlink()
        (self.root / 'surprise.txt').write_text('x')
        with self.assertRaises(ValueError): stage.audit_evidence(self.root)

    def test_per_file_and_aggregate_caps(self):
        for name in stage.LOGS:
            (self.root / name).write_bytes(b'x' * stage.CAP)
        for index in range(4):
            (self.root / f'crash-{index}.ips').write_bytes(b'x' * stage.CAP)
        self.assertEqual(stage.audit_evidence(self.root), 8 * stage.CAP)
        (self.root / 'toolchain.txt').write_bytes(b'x')
        with self.assertRaisesRegex(ValueError, 'aggregate'):
            stage.audit_evidence(self.root)
        (self.root / 'toolchain.txt').unlink()
        (self.root / stage.LOGS[0]).write_bytes(b'x' * (stage.CAP + 1))
        with self.assertRaisesRegex(ValueError, 'per-file'):
            stage.audit_evidence(self.root)

    def test_nested_pid_is_not_crash_owner(self):
        self.assertIsNone(crashed_process('{"payload":{"pid":42,"procName":"Owned"}}', '.ips'))
        self.assertEqual(crashed_process('{"pid":42,"procName":"Owned"}', '.ips'), (42, 'Owned'))

    def test_crash_collection_requires_fresh_top_level_identity_and_regular_file(self):
        reports = self.root / 'reports'
        output = self.root / 'out'
        reports.mkdir()
        output.mkdir()
        (reports/'owned.ips').write_text('{"pid":42,"procName":"Owned"}')
        (reports/'wrong.ips').write_text('{"pid":42,"procName":"Other"}')
        (reports/'nested.ips').write_text('{"nested":{"pid":42,"procName":"Owned"}}')
        (reports/'link.ips').symlink_to(reports/'owned.ips')
        result = collect(reports, output, 0, {42: {'Owned'}}, grace=0.05)
        self.assertEqual(result['copiedReports'], 1)
        self.assertEqual(result['skipped']['symlink'], 1)
        self.assertEqual(result['skipped']['invalid-or-unowned-top-level-process'], 2)


class NativePreparationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        fixtures.NestedGitPatchTests.setUpClass()

    def setUp(self):
        fixture = fixtures.NestedGitPatchTests(methodName='test_nested_directory_cannot_be_mistaken_for_git_root')
        fixture.setUp()
        self.addCleanup(fixture.doCleanups)
        self.f = fixture
        self.output = fixture.root / 'evidence'
        self.real_command = stage.command
        def metadata_only(*args, cwd=None):
            if args == ('xcodebuild', '-version'): return 'Xcode 26.0.1\nBuild version 17A400'
            if args == ('swift', '--version'): return 'fixture metadata; no compiler'
            if args == ('xcrun', '--find', 'swift'): return '/fixture/swift'
            if args[0] != 'git': raise AssertionError('Unexpected executable')
            return self.real_command(*args, cwd=cwd)
        for name, value in dict(ROOT=fixture.diag, HEAD=fixture.product_head,
                NEON_HEAD=fixture.neon_head, LOCK=fixture.lock_hash,
                NEON_PATCH=__import__('hashlib').sha256(fixture.neon_patch).hexdigest()).items():
            mock = patch.object(stage, name, value)
            mock.start()
            self.addCleanup(mock.stop)
        mocks = (
            patch.object(stage, 'command', side_effect=metadata_only),
            patch.object(stage, 'headroom', return_value=24 * 1024**3),
            patch.object(stage, 'pins_for', side_effect=lambda package: json.loads((package/'Package.resolved').read_text())['pins']),
            patch.object(stage, 'collect', return_value={'fixture': 'no real crash scan'}),
            patch.dict(os.environ, dict(GITHUB_EVENT_NAME='push', GITHUB_RUN_ATTEMPT='1',
                GITHUB_REPOSITORY='Joncallim/macdown_2', GITHUB_SHA=fixture.diag_head,
                GITHUB_REF='refs/heads/diagnostic/532-neon-natural-ordering-2026-10-26',
                **{name+'_OUTCOME': 'success' for name in stage.STEPS})),
        )
        for mock in mocks:
            mock.start()
            self.addCleanup(mock.stop)

    def preflight(self):
        f = self.f
        parked = f.root / 'parked-fixture-dependencies'
        f.scratch.rename(parked)
        stage.preflight(f.repo, f.package, f.scratch, self.output)
        parked.rename(f.scratch)

    def ready(self):
        self.preflight()
        f = self.f
        stage.patch_sources(f.repo, f.package, f.scratch, self.output)
        with patch.object(stage, 'assert_build_inputs', return_value={'fixture': 'compile never invoked'}):
            stage.verify_build(f.repo, f.package, f.scratch, self.output)
        for name in stage.LOGS:
            text = ('Test restoreLifetimesThenOriginalBelowCutoff() started\n' + fixture_log()
                    if name == 'lifecycle-test.log' else 'fixture: no Swift command executed\n')
            (self.output / name).write_text(text)

    def test_full_real_git_preparation_and_instrumented_fixture_verdict(self):
        self.ready()
        self.assertEqual(stage.finish(self.f.repo, self.f.package, self.f.scratch, self.output), 0)
        state = json.loads((self.output/'state.json').read_text())
        self.assertEqual([p['materializedCount'] for p in state['patchApplication']], [8, 5])
        self.assertEqual(len(state['patchedFileHashes']), 13)
        self.assertEqual(json.loads((self.output/'metadata.json').read_text())['outcome'], 'not-reproduced; not-fixed')

    def test_noop_harness_rejected_before_build(self):
        self.preflight()
        f = self.f
        real = stage.command
        def skip(*args, cwd=None):
            if args[:2] == ('git', 'apply') and '--check' not in args and Path(cwd) == f.repo: return ''
            return real(*args, cwd=cwd)
        with patch.object(stage, 'command', side_effect=skip):
            with self.assertRaisesRegex(ValueError, 'unchanged'):
                stage.patch_sources(f.repo, f.package, f.scratch, self.output)

    def test_changed_patch_bytes_rejected(self):
        self.preflight()
        (self.f.diag/'lifecycle-harness.patch').write_text('changed')
        with self.assertRaisesRegex(ValueError, 'patch mismatch'):
            stage.patch_sources(self.f.repo, self.f.package, self.f.scratch, self.output)

    def test_missing_log_fails_even_after_zero_test_exit(self):
        self.ready()
        (self.output/'dependency-prepare.log').unlink()
        self.assertEqual(stage.finish(self.f.repo, self.f.package, self.f.scratch, self.output), 1)
        self.assertIn('Required log missing', (self.output/'metadata.json').read_text())

    def test_overflow_marker_invalidates_verdict(self):
        self.ready()
        (self.output/'lifecycle-test.log.overflow.json').write_text('{"overflow":true}')
        self.assertEqual(stage.finish(self.f.repo, self.f.package, self.f.scratch, self.output), 1)
        self.assertIn('Log truncated', (self.output/'metadata.json').read_text())

    def test_overflow_keeps_owner_correlated_crash_collection_but_still_fails(self):
        self.ready()
        (self.output/'lifecycle-test.log.overflow.json').write_text('{"overflow":true}')
        with patch.object(stage, 'collect', return_value={'fixture':'retained-owned-report'}) as collector:
            self.assertEqual(stage.finish(self.f.repo, self.f.package, self.f.scratch, self.output), 1)
        self.assertEqual(collector.call_args.args[3], {42: {'Owned'}})
        report = json.loads((self.output/'metadata.json').read_text())
        self.assertEqual(report['crashes']['fixture'], 'retained-owned-report')
        self.assertIn('Log truncated', report['failure'])

    def test_failed_stage_never_becomes_success(self):
        self.ready()
        with patch.dict(os.environ, {'SELECTED_OUTCOME': 'failure'}):
            self.assertEqual(stage.finish(self.f.repo, self.f.package, self.f.scratch, self.output), 1)

    def test_incomplete_trace_fails_after_successful_command(self):
        self.ready()
        path = self.output/'lifecycle-test.log'
        path.write_text(path.read_text().replace('NEON_ORDER_TRACE evicted=0', 'NEON_ORDER_TRACE evicted=1'))
        self.assertEqual(stage.finish(self.f.repo, self.f.package, self.f.scratch, self.output), 1)

    def test_wrong_toolchain_and_repeated_preparation_refused(self):
        f = self.f
        with patch.object(stage, 'command', return_value='wrong toolchain'):
            with self.assertRaisesRegex(ValueError, 'toolchain'):
                stage.preflight(f.repo, f.package, f.scratch, self.output)
        self.preflight()
        with self.assertRaisesRegex(ValueError, 'Fresh scratch'):
            stage.preflight(f.repo, f.package, f.scratch, self.output)

    def test_metadata_command_cannot_launch_build_or_signal(self):
        with self.assertRaises(ValueError): self.real_command('swift', 'build')
        with self.assertRaises(ValueError): self.real_command('kill', '123')


if __name__ == '__main__':
    unittest.main()
