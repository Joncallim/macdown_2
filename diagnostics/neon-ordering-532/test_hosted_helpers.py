import base64
import json
import os
from pathlib import Path
import signal
import sys
import tempfile
import time
import unittest
from unittest.mock import patch
from types import SimpleNamespace

from crash_reports import crashed_process, collect, fixture_owners, read_regular, CAP
from provenance import correlated_events, assert_workspace, assert_build_inputs, verify_files, digest
from validate_bounded import run

class OwnershipTests(unittest.TestCase):
    def test_ips_uses_only_top_level_crashed_process(self):
        body = {'pid': 12, 'procName': 'Other', 'threads': [{'pid': 42, 'procName': 'Owned'}]}
        self.assertEqual(crashed_process('{}\n' + json.dumps(body), '.ips'), (12, 'Other'))
        self.assertIsNone(crashed_process(json.dumps({'threads': [{'pid': 42, 'procName': 'Owned'}]}), '.ips'))
        self.assertIsNone(crashed_process('{broken}', '.ips'))
        self.assertIsNone(crashed_process(json.dumps({'pid': True, 'procName': 'Owned'}), '.ips'))

    def test_fixture_name_and_legacy_header(self):
        name = base64.b64encode(b'Owned').decode()
        owners = fixture_owners(f'NEON_FIXTURE pid=42 fixture=abcd-1234 identity64={name}')
        self.assertEqual(owners, {42: {'Owned'}})
        self.assertEqual(crashed_process('Process: Owned [42]\nThread 0 Crashed:\n', '.crash'), (42, 'Owned'))
        self.assertIsNone(crashed_process('Thread 0 Crashed:\n' * 41 + 'Process: Owned [42]', '.crash'))

    def test_symlink_fifo_oversized_and_wrong_identity_are_recorded(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            reports, output = root / 'reports', root / 'out'
            reports.mkdir(); output.mkdir()
            payload = {'pid': 42, 'procName': 'Owned'}
            (reports / 'valid.ips').write_text(json.dumps(payload))
            (reports / 'nested.ips').write_text(json.dumps({'pid': 9, 'procName': 'Other', 'x': payload}))
            (reports / 'wrong-name.ips').write_text(json.dumps({'pid': 42, 'procName': 'Other'}))
            (reports / 'alias.ips').symlink_to(reports / 'valid.ips')
            os.mkfifo(reports / 'pipe.ips')
            with (reports / 'large.ips').open('wb') as handle:
                handle.truncate(CAP + 1)
            result = collect(reports, output, 0, {42: {'Owned'}}, grace=0.05)
            self.assertEqual(result['copiedReports'], 1)
            for kind in ('symlink', 'nonregular', 'oversized'):
                self.assertEqual(result['skipped'][kind], 1)
            self.assertEqual(result['skipped']['invalid-or-unowned-top-level-process'], 2)

    def test_scan_exhaustion_is_explicit(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); output = root / 'out'; output.mkdir()
            for i in range(257):
                (root / f'{i}.ips').write_text('{}')
            result = collect(root, output, 0, {42: {'Owned'}}, grace=1)
            self.assertEqual(result['scanned'], 256)
            self.assertIn('entry-cap', result['exhaustion'])

    def test_fixture_marker_alone_is_not_an_instrumented_verdict(self):
        with self.assertRaises(ValueError):
            correlated_events('NEON_FIXTURE pid=42 fixture=abcd-1234')

    def test_trace_correlation_requires_same_client_and_mutation(self):
        lines = []
        for fixture in ('a', 'b'):
            lines += [f'NEON_FIXTURE pid=42 fixture={fixture}',
                      f'NEON_ORDER 1 fixture={fixture} client={fixture} processor=r phase=enqueue op={fixture} parent=0',
                      f'NEON_ORDER 2 fixture={fixture} client={fixture} processor=w phase=request op=worker parent={fixture}',
                      f'NEON_ORDER 3 fixture={fixture} client={fixture} processor=w phase=execute op=worker parent={fixture}',
                      f'NEON_ORDER 4 fixture={fixture} client={fixture} processor=r phase=compare op={fixture} expected=0',
                      f'NEON_ORDER 3 fixture={fixture} client={fixture} processor=r phase=callback op={fixture} parent=0']
        self.assertEqual(len(correlated_events('\n'.join(lines))), 2)
        with self.assertRaises(ValueError):
            correlated_events('\n'.join(lines).replace('client=b processor=w', 'client=wrong processor=w'))

    def test_effective_workspace_rejects_redirected_checkout(self):
        with tempfile.TemporaryDirectory() as temporary:
            scratch = Path(temporary)
            item = {'packageRef': {'identity': 'neon', 'kind': 'remoteSourceControl', 'location': 'https://example/Neon'},
                    'state': {'checkoutState': {'revision': 'exact'}}, 'subpath': 'Neon'}
            pins = [{'identity': 'neon', 'location': 'https://example/Neon', 'state': {'revision': 'exact'}}]
            state = scratch / 'workspace-state.json'
            state.write_text(json.dumps({'object': {'dependencies': [item]}}))
            with patch('provenance.subprocess.run', return_value=SimpleNamespace(stdout='exact\n')):
                self.assertEqual(assert_workspace(scratch, pins)[0]['revision'], 'exact')
            item['subpath'] = '../../elsewhere'
            state.write_text(json.dumps({'object': {'dependencies': [item]}}))
            with self.assertRaises(ValueError):
                assert_workspace(scratch, pins)

class WatchdogTests(unittest.TestCase):
    def invoke(self, code, seconds=0.2):
        with tempfile.TemporaryDirectory() as temporary:
            started = time.monotonic()
            with self.assertRaises(SystemExit):
                run('fixture', [sys.executable, '-c', code], seconds,
                    log_root=Path(temporary), disk_budget=128 * CAP)
            self.assertLess(time.monotonic() - started, 10)

    def test_ordinary_success_and_failure_status(self):
        with tempfile.TemporaryDirectory() as temporary:
            run('success', [sys.executable, '-c', 'print("ok")'], 2, log_root=Path(temporary))
            with self.assertRaises(SystemExit) as result:
                run('failure', [sys.executable, '-c', 'raise SystemExit(7)'], 2, log_root=Path(temporary))
            self.assertEqual(result.exception.code, 7)

    def test_log_overflow_is_capped_and_fails(self):
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary)
            with self.assertRaises(SystemExit):
                run('overflow', [sys.executable, '-c',
                    'import sys,time; sys.stdout.buffer.write(b"x"*(2*1024**2)); sys.stdout.flush(); time.sleep(15)'],
                    3, log_root=output)
            self.assertEqual((output / 'overflow.log').stat().st_size, CAP)

    def test_ignores_term_after_closing_pipe(self):
        self.invoke('import os,signal,time; signal.signal(signal.SIGTERM,signal.SIG_IGN); '
                    'os.close(1); os.close(2); time.sleep(15)')

    def test_direct_child_exit_with_descendant_held_pipe(self):
        child = 'import signal,time; signal.signal(signal.SIGTERM,signal.SIG_IGN); time.sleep(15)'
        self.invoke(f'import subprocess,sys; subprocess.Popen([sys.executable,"-c",{child!r}])', seconds=3)

    def test_escaped_descendant_pipe_drain_is_bounded(self):
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary)
            child = 'import time; time.sleep(15)'
            code = (f'import subprocess,sys; p=subprocess.Popen([sys.executable,"-c",{child!r}],'
                    'start_new_session=True); print("OWNED_FIXTURE_PID",p.pid,flush=True)')
            try:
                started = time.monotonic()
                with self.assertRaises(SystemExit):
                    run('escaped', [sys.executable, '-c', code], 3, log_root=output)
                self.assertLess(time.monotonic() - started, 10)
            finally:
                log = output / 'escaped.log'
                if log.exists():
                    for line in log.read_text().splitlines():
                        if line.startswith('OWNED_FIXTURE_PID '):
                            pid = int(line.split()[1])
                            try:
                                if os.getpgid(pid) == pid:
                                    os.killpg(pid, signal.SIGKILL)
                            except ProcessLookupError:
                                pass

class BuildInputTests(unittest.TestCase):
    def test_actual_neon_source_root_and_patch_survival_are_enforced(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve(); scratch = root / 'scratch'; neon = root / 'Neon'; repo = root / 'repo'
            description = scratch / 'triple/debug/description.json'
            description.parent.mkdir(parents=True)
            commands, files = {}, {}
            for module in ('RangeState', 'TreeSitterClient', 'Neon', 'Highlighting', 'HighlightingTests'):
                if module in ('RangeState', 'TreeSitterClient', 'Neon'):
                    source = neon / 'Sources' / module / 'Source.swift'
                else:
                    source = repo / ('Tests' if module.endswith('Tests') else 'Sources') / module / 'Source.swift'
                source.parent.mkdir(parents=True); source.write_text('// fixture')
                obj = scratch / (module + '.o'); obj.write_bytes(b'fixture')
                files[str(source)] = digest(source)
                commands[module] = {'moduleName': module, 'sources': [str(source)],
                                    'inputs': [{'kind': 'file', 'name': str(source)}], 'objects': [str(obj)]}
            description.write_text(json.dumps({'swiftCommands': commands}))
            self.assertEqual(len(assert_build_inputs(scratch, neon, repo, files)['patchedCompilerInputs']), 5)
            commands['Neon']['sources'] = [str(root / 'alternate/Neon.swift')]
            description.write_text(json.dumps({'swiftCommands': commands}))
            with self.assertRaises(ValueError):
                assert_build_inputs(scratch, neon, repo, files)
            Path(next(iter(files))).write_text('// changed')
            with self.assertRaises(ValueError):
                verify_files(files)

if __name__ == '__main__':
    unittest.main()
