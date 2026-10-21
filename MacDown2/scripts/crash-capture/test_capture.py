"""Synthetic identity, privacy and lifecycle controls; no product tests or host reports."""
import copy
from datetime import datetime, timezone
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import ctypes
import errno
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('crash_capture', Path(__file__).with_name('capture.py'))
module = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = module
spec.loader.exec_module(module)


class CaptureTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.exe = self.root / 'swiftpm-testing-helper'
        self.exe.write_bytes(b'owned helper image')
        self.bundle = self.root / 'MacDownKitPackageTests.xctest'
        self.test_image = self.bundle / 'Contents/MacOS/MacDownKitPackageTests'
        self.test_image.parent.mkdir(parents=True)
        self.test_image.write_bytes(b'owned test image')
        self.birth = 1_792_400_000_123_456
        self.proc = module.Process(123, 100, self.birth, str(self.exe))
        self.owned = module.Owned(self.proc, 'test_helper', (100, self.birth - 1000))
        self.exe_uuid = '11111111-1111-4111-8111-111111111111'
        self.test_uuid = '22222222-2222-4222-8222-222222222222'
        self.owned.images[str(self.exe)] = module.Image(self.exe, module.file_stamp(self.exe), {self.exe_uuid}, 'binaryhash')
        self.owned.bundle_image = module.Image(self.test_image, module.file_stamp(self.test_image), {self.test_uuid}, 'testhash')
        self.body = {
            'pid': 123, 'procPath': str(self.exe), 'procLaunch': self.date(self.birth),
            'captureTime': self.date(self.birth + 500000), 'faultingThread': 0,
            'exception': {'type': 'EXC_BAD_ACCESS', 'signal': 'SIGSEGV', 'secret': 'PRIVATE_EXCEPTION'},
            'termination': {'namespace': 'SIGNAL', 'code': 11, 'indicator': 'PRIVATE_MESSAGE'},
            'environment': {'TOKEN': 'PRIVATE_ENV'}, 'reporterKey': 'PRIVATE_HOST',
            'threads': [{'frames': [{'imageIndex': 1, 'imageOffset': 16, 'symbol': 'syntheticCrash()'},
                                   {'imageIndex': 0, 'imageOffset': 32}],
                         'threadState': {'x0': 'PRIVATE_REGISTER'}, 'name': 'PRIVATE_THREAD'},
                        {'frames': [{'symbol': 'PRIVATE_OTHER_THREAD'}]}],
            'usedImages': [
                {'path': str(self.exe), 'name': self.exe.name, 'uuid': self.exe_uuid, 'base': 1000, 'size': 500, 'arch': 'arm64'},
                {'path': str(self.test_image), 'name': self.test_image.name, 'uuid': self.test_uuid, 'base': 2000, 'size': 500, 'arch': 'arm64'},
                {'path': '/Users/private/SECRET_IMAGE', 'name': 'PRIVATE_UNREFERENCED', 'uuid': self.exe_uuid}],
        }

    def tearDown(self):
        self.tmp.cleanup()

    @staticmethod
    def date(micros):
        sec, remainder = divmod(micros, 1000000)
        return datetime.fromtimestamp(sec, timezone.utc).replace(microsecond=remainder).isoformat()

    def accept(self, body=None):
        return module.attributable(body or self.body, self.owned, self.birth - 1000, self.birth + 1000000)

    def test_helper_and_test_image_have_distinct_verified_uuids(self):
        category, image = self.accept()
        self.assertEqual(category, 'test_process')
        self.assertEqual(image.uuids, {self.exe_uuid})

    def test_pid_reuse_path_and_uuid_mismatches_are_refused(self):
        for change in ('pid', 'birth', 'path', 'exe_uuid', 'test_uuid', 'capture_time'):
            with self.subTest(change=change):
                body = copy.deepcopy(self.body)
                if change == 'pid': body['pid'] += 1
                if change == 'birth': body['procLaunch'] = self.date(self.birth + 2000)
                if change == 'path': body['procPath'] = '/private/unrelated/swiftpm-testing-helper'
                if change == 'exe_uuid': body['usedImages'][0]['uuid'] = self.test_uuid
                if change == 'test_uuid': body['usedImages'][1]['uuid'] = self.exe_uuid
                if change == 'capture_time': body['captureTime'] = self.date(self.birth - 10000000)
                with self.assertRaises(module.Rejected): self.accept(body)

    def test_missing_identity_and_coarse_birth_time_are_not_relaxed(self):
        for key in ('pid', 'procPath', 'procLaunch', 'captureTime', 'usedImages'):
            with self.subTest(key=key):
                body = copy.deepcopy(self.body); body.pop(key)
                with self.assertRaises(module.Rejected): self.accept(body)
        body = copy.deepcopy(self.body)
        body['procLaunch'] = datetime.fromtimestamp(self.birth // 1000000, timezone.utc).isoformat()
        with self.assertRaises(module.Rejected): self.accept(body)

    def test_printed_fraction_precision_allows_only_its_rounding_unit(self):
        body = copy.deepcopy(self.body)
        rounded = self.birth // 1000 * 1000
        body['procLaunch'] = self.date(rounded).replace('.123000', '.123')
        self.accept(body)
        body['procLaunch'] = self.date(rounded - 2000).replace('.121000', '.121')
        with self.assertRaises(module.Rejected): self.accept(body)

    def test_owned_preload_crash_is_distinct_from_loaded_test_crash(self):
        body = copy.deepcopy(self.body); body['usedImages'].pop(1)
        self.assertEqual(self.accept(body)[0], 'owned_helper_before_test_image_loaded')
        self.owned.bundle_image = None
        self.assertEqual(self.accept()[0], 'owned_launcher_before_verified_test_binding')

    def test_explicit_home_redaction_still_requires_all_image_and_process_identity(self):
        body = copy.deepcopy(self.body)
        with patch.object(Path, 'home', return_value=self.root):
            body['procPath'] = '/Users/USER/*/' + self.exe.name
            body['usedImages'][0]['path'] = body['procPath']
            body['usedImages'][1]['path'] = '/Users/USER/*/' + self.test_image.name
            self.assertEqual(self.accept(body)[0], 'test_process')
            for change in ('wrong_uuid', 'wrong_birth', 'other_shape', 'unknown_path', 'wrong_test_uuid', 'ambiguous'):
                altered = copy.deepcopy(body)
                with self.subTest(change=change):
                    if change == 'wrong_uuid': altered['usedImages'][0]['uuid'] = self.test_uuid
                    if change == 'wrong_birth': altered['procLaunch'] = self.date(self.birth + 10000)
                    if change == 'other_shape':
                        altered['procPath'] = '/Users/OTHER/*/' + self.exe.name
                        altered['usedImages'][0]['path'] = altered['procPath']
                    if change == 'unknown_path':
                        altered['procPath'] = '/private/*/' + self.exe.name
                        altered['usedImages'][0]['path'] = altered['procPath']
                    if change == 'wrong_test_uuid': altered['usedImages'][1]['uuid'] = self.exe_uuid
                    if change == 'ambiguous':
                        second = self.root / 'other' / self.exe.name
                        self.owned.images[str(second)] = module.Image(second, (0,0,0,0), {self.exe_uuid}, 'samehash')
                    with self.assertRaises(module.Rejected): self.accept(altered)
            self.owned.images.pop(str(second))
        self.assertIsNone(module.path_binding('/Users/USER/*/swiftpm-testing-helper', Path('/Applications/swiftpm-testing-helper')))

    def test_header_and_body_json_and_single_body_are_supported(self):
        raw = json.dumps({'app_name': 'helper', 'PRIVATE_HEADER': 'not exported'}) + '\n' + json.dumps(self.body)
        header, body = module.decode_report(raw.encode())
        self.assertEqual(header['app_name'], 'helper'); self.assertEqual(body, self.body)
        self.assertEqual(module.decode_report(json.dumps(self.body).encode())[1], self.body)
        with self.assertRaises(json.JSONDecodeError): module.decode_report(raw[:-5].encode())

    def test_entire_export_omits_private_fields_and_unrelated_threads_images(self):
        exported = module.export_stack(self.body, 'test_process', 'digest')
        encoded = json.dumps(exported)
        for forbidden in ('PRIVATE_', '/Users/', str(self.root), 'threadState', 'environment', 'reporterKey'):
            self.assertNotIn(forbidden, encoded)
        self.assertEqual(len(exported['frames']), 2)
        self.assertEqual(len(exported['referenced_images']), 2)
        self.assertEqual(exported['symbolication'], 'unsymbolicated')

    def test_frame_bound_and_path_like_symbol_are_explicit(self):
        body = copy.deepcopy(self.body)
        body['threads'][0]['frames'] = [{'imageIndex': 0, 'imageOffset': 4, 'symbol': '/Users/private/secret'}] * 130
        exported = module.export_stack(body, 'test_process', 'digest')
        self.assertEqual(len(exported['frames']), 128)
        self.assertEqual(exported['frames_omitted'], 2)
        self.assertNotIn('secret', json.dumps(exported))

    def test_symlinks_oversize_and_partial_reports_are_refused(self):
        data = self.root / 'report.ips'; data.write_bytes(b'1234')
        link = self.root / 'link.ips'; link.symlink_to(data)
        with self.assertRaises(OSError): module.read_regular(link)
        with self.assertRaises(module.Rejected): module.read_regular(data, byte_limit=3)
        with patch.object(module.os, 'read', return_value=b'12'):
            with self.assertRaises(module.Rejected): module.read_regular(data)

    def test_candidate_scope_does_not_read_or_record_unrelated_names(self):
        (self.root / 'SomeOtherApp-private.ips').write_text('PRIVATE_UNRELATED')
        own = self.root / 'swiftpm-testing-helper-probe.ips'; own.write_text('{}')
        self.assertEqual(set(module.candidate_stamps([self.root], {'swiftpm-testing-helper'})), {own})
        self.assertEqual(module.candidate_stamps([self.root], {'swiftpm-testing-helper'}, time_after := 10**20), {})

    def test_stale_and_wrong_pid_reports_do_not_escape_in_error_paths(self):
        path = self.root / 'swiftpm-testing-helper-probe.ips'
        body = copy.deepcopy(self.body); body['pid'] = 999; body['PRIVATE_DATA'] = 'PRIVATE_REJECTED'
        path.write_text(json.dumps(body))
        observer = module.Observer(None, lambda: self.bundle); observer.owned[123] = self.owned
        result = module.collect_reports([self.root], {}, observer, 0, 10**20, 0)
        self.assertEqual(result['reports'], [])
        self.assertEqual(result['counters']['unowned_pid'], 1)
        self.assertNotIn('PRIVATE_', json.dumps(result))
        before = module.candidate_stamps([self.root], {'swiftpm-testing-helper'})
        self.assertEqual(module.collect_reports([self.root], before, observer, 0, 10**20, 0)['reports'], [])

    def test_symbolication_uses_only_verified_images_and_never_exports_raw_paths(self):
        exported = module.export_stack(self.body, 'test_process', 'digest')
        with patch.object(module, 'run_text', return_value='ownedSymbol() (in helper) (/Users/private/secret.c:3)') as run:
            module.symbolicate(exported, self.body, self.owned, time.monotonic() + 10)
        self.assertEqual(run.call_count, 2)
        self.assertNotIn('/Users/', json.dumps(exported))
        self.assertTrue(all(f.get('verified_binary_symbol') == 'ownedSymbol()' for f in exported['frames']))

    def test_observer_failure_does_not_replace_original_command_result(self):
        with patch.object(module, 'DarwinProcesses', side_effect=OSError('PRIVATE_ERROR')):
            result = module.observed_command([sys.executable, '-c', 'raise SystemExit(7)'], self.root,
                                              lambda: None, [], report_wait=0)
        self.assertEqual(result['return_code'], 7)
        self.assertEqual(result['shell_exit_code'], 7)
        self.assertNotIn('PRIVATE_ERROR', json.dumps(result))

    def test_post_exit_capture_exception_retains_original_status(self):
        class API:
            def identity(self, pid): return None
            def commands(self): return {}
        with patch.object(module, 'DarwinProcesses', return_value=API()), patch.object(module, 'collect_reports', side_effect=OSError('PRIVATE_ERROR')):
            result = module.observed_command([sys.executable, '-c', 'raise SystemExit(9)'], self.root,
                                              lambda: None, [], report_wait=0.1)
        self.assertEqual(result['return_code'], 9)
        self.assertEqual(result['shell_exit_code'], 9)
        self.assertEqual(result['capture_error_type'], 'OSError')
        self.assertNotIn('PRIVATE_ERROR', json.dumps(result))

    def test_report_text_never_enters_allowlisted_fields(self):
        body = copy.deepcopy(self.body)
        body['threads'][0]['frames'][0]['symbol'] = 'PRIVATE_FRAME_TOKEN'
        body['usedImages'][0].update(name='PRIVATE_IMAGE_TOKEN', arch='PRIVATE_ARCH_TOKEN')
        body['exception'].update(type='PRIVATE_EXCEPTION_TOKEN', signal='PRIVATE_SIGNAL_TOKEN')
        body['termination']['namespace'] = 'PRIVATE_NAMESPACE_TOKEN'
        exported = module.export_stack(body, 'test_process', 'digest')
        self.assertNotIn('PRIVATE_', json.dumps(exported))
        self.assertNotIn('symbol', exported['frames'][0])
        self.assertNotIn('name', exported['referenced_images'][0])

    def test_symbolication_deadline_prevents_tool_calls_and_limits_timeout(self):
        exported = module.export_stack(self.body, 'test_process', 'digest')
        with patch.object(module, 'run_text') as run:
            module.symbolicate(exported, self.body, self.owned, time.monotonic() - 1)
            run.assert_not_called()
        with patch.object(module, 'run_text', return_value='ownedSymbol') as run:
            module.symbolicate(exported, self.body, self.owned, time.monotonic() + 0.1)
            self.assertTrue(all(0 < call.kwargs['timeout'] <= 0.1 for call in run.call_args_list))

    def test_inaccessible_directory_does_not_discard_accessible_candidates(self):
        own = self.root / 'swiftpm-testing-helper-probe.ips'; own.write_text('{}')
        original = module.os.scandir
        with original(self.root) as entries:
            rows = list(entries)
        context = unittest.mock.MagicMock()
        context.__enter__.return_value = iter(rows)
        errors = module.Counter()
        with patch.object(module.os, 'scandir', side_effect=[context, PermissionError('PRIVATE_PATH')]):
            found = module.candidate_stamps([self.root, self.root / 'private'], {'swiftpm-testing-helper'}, errors=errors)
        self.assertEqual(set(found), {own})
        self.assertEqual(errors, {'directory_PermissionError': 1})
        self.assertNotIn('PRIVATE_', json.dumps(errors))

    def test_final_write_failure_preserves_original_exit(self):
        record = {'shell_exit_code': 9, 'processes': [], 'observer_errors': {}}
        output = self.root.parent / (self.root.name + 'write')
        with patch.object(sys, 'argv', ['capture', '--repo', str(self.root), '--output', str(output)]), patch.object(module, 'attest', return_value={'passed': True, 'head': 'same'}), patch.object(module, 'observed_command', return_value=record), patch.dict(os.environ, {}, clear=True), patch.object(Path, 'write_text', side_effect=OSError('PRIVATE_IO')):
            self.assertEqual(module.main(), 9)
        output.rmdir()

    def test_real_closed_stdout_preserves_interpreter_exit(self):
        output = self.root.parent / (self.root.name + 'closedpipe')
        script = f"""
import importlib.util, os, sys
from unittest.mock import patch
spec = importlib.util.spec_from_file_location('capture', {str(Path(module.__file__))!r})
m = importlib.util.module_from_spec(spec); sys.modules[spec.name] = m; spec.loader.exec_module(m)
sys.argv = ['capture', '--repo', {str(self.root)!r}, '--output', {str(output)!r}]
with patch.object(m, 'attest', return_value={{'passed': True, 'head': 'same'}}), patch.object(m, 'observed_command', return_value={{'shell_exit_code': 9, 'processes': [], 'observer_errors': {{}}}}), patch.dict(os.environ, {{}}, clear=True):
    code = m.main()
sys.exit(code)
"""
        child = subprocess.Popen([sys.executable, '-B', '-c', script], stdout=subprocess.PIPE)
        child.stdout.close()
        self.assertEqual(child.wait(timeout=5), 9)
        (output / 'run.json').unlink(); output.rmdir()

    def test_final_process_identity_distinguishes_absence_from_unavailable(self):
        api = object.__new__(module.DarwinProcesses)
        with patch.object(api, 'identity', return_value=self.proc):
            self.assertEqual(api.final_state(self.proc), 'alive_same_birth')
        with patch.object(api, 'identity', return_value=module.Process(123, 100, self.birth + 1, str(self.exe))):
            self.assertEqual(api.final_state(self.proc), 'pid_reused')
        for error, expected in ((errno.ESRCH, 'absent'), (errno.EPERM, 'unavailable'), (0, 'unavailable')):
            def unavailable(pid):
                ctypes.set_errno(error)
                return None
            with patch.object(api, 'identity', side_effect=unavailable):
                self.assertEqual(api.final_state(self.proc), expected)

    def test_helper_requires_exact_macho_flag_and_rejects_wrong_or_ambiguous_arguments(self):
        helper = str(self.exe)
        target = str(self.test_image)
        self.assertTrue(module.test_argument_binding(helper, [helper, '--test-bundle-path', target], self.bundle))
        self.assertTrue(module.test_argument_binding(helper, [helper, '--test-bundle-path=' + target], self.bundle))
        self.assertEqual(module.test_argument_binding(helper, [helper, '--test-bundle-path', str(self.bundle)], self.bundle), 'swift_testing_bundle_flag')
        for args in ([helper, target],
                     [helper, '--test-bundle-path', '/unrelated/MacDownKitPackageTests'],
                     [helper, '--test-bundle-path', target, '--test-bundle-path', target],
                     [helper, '--test-bundle-path', target, '--test-bundle-path']):
            self.assertFalse(module.test_argument_binding(helper, args, self.bundle))
        self.assertTrue(module.test_argument_binding('/usr/bin/xctest', ['xctest', str(self.bundle)], self.bundle))
        self.assertFalse(module.test_argument_binding('/usr/bin/xctest', ['xctest', target], self.bundle))

    def test_launcher_and_xctest_do_not_prove_swift_testing_helper_coverage(self):
        root = {'role': 'launcher', 'executable_images': [{'name': 'swift-package'}]}
        xctest = {'role': 'test_helper', 'argument_binding': 'xctest_bundle_argument', 'executable_images': [{'name': 'xctest'}]}
        helper = {'role': 'test_helper', 'argument_binding': 'swift_testing_macho_flag', 'executable_images': [{'name': 'swiftpm-testing-helper'}]}
        self.assertFalse(module.coverage([root])['swift_testing_helper_observed'])
        self.assertEqual(module.coverage([root, xctest]), {'xctest_observed': True, 'swift_testing_helper_observed': False})
        self.assertTrue(module.coverage([root, xctest, helper])['swift_testing_helper_observed'])

    def test_integrity_requires_target_runtime_and_preserves_passing_command(self):
        for runtime, expected in ((None, 'unavailable'), ('xctest', 'unavailable'), ('swiftpm-testing-helper', 'passed')):
            with self.subTest(runtime=runtime):
                process = {'role': 'launcher' if runtime is None else 'test_helper', 'final_state': 'absent',
                           'argument_binding': {'xctest': 'xctest_bundle_argument', 'swiftpm-testing-helper': 'swift_testing_macho_flag'}.get(runtime),
                           'executable_images': [{'name': runtime or 'swift', 'error': None}], 'test_image': {'error': None}}
                record = {'shell_exit_code': 0, 'processes': [process], 'observer_errors': {}, 'coverage': module.coverage([process])}
                output = self.root.parent / (self.root.name + str(runtime))
                with patch.object(sys, 'argv', ['capture', '--repo', str(self.root), '--output', str(output)]), patch.object(module, 'attest', return_value={'passed': True, 'head': 'same'}), patch.object(module, 'observed_command', return_value=record), patch.dict(os.environ, {}, clear=True):
                    self.assertEqual(module.main(), 0)
                result = json.loads((output / 'run.json').read_text())
                self.assertEqual(result['diagnostic_integrity'], expected)
                (output / 'run.json').unlink(); output.rmdir()

    def test_binary_hashing_and_process_images_are_bounded(self):
        self.assertEqual(module.file_sha(self.exe, time.monotonic() + 1), module.sha(self.exe.read_bytes()))
        with self.assertRaises(module.Rejected): module.file_sha(self.exe, time.monotonic() - 1)
        with patch.object(module, 'MAX_BINARY_BYTES', 1):
            with self.assertRaises(module.Rejected): module.file_sha(self.exe, time.monotonic() + 1)
        with patch.object(module, 'MAX_IMAGES_PER_PROCESS', 1):
            with self.assertRaises(module.Rejected):
                self.owned.observe(module.Process(123, 100, self.birth, str(self.test_image)))


class ObserverLifecycleTests(unittest.TestCase):
    def test_exec_parent_reuse_exact_bundle_and_reparenting(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            launcher = root / 'swift'; launcher.write_bytes(b'a')
            exec_image = root / 'swift-test'; exec_image.write_bytes(b'b')
            helper = root / 'swiftpm-testing-helper'; helper.write_bytes(b'c')
            bundle = root / 'MacDownKitPackageTests.xctest'
            image = bundle / 'Contents/MacOS/MacDownKitPackageTests'; image.parent.mkdir(parents=True); image.write_bytes(b'd')
            identities = {100: module.Process(100, os.getpid(), 1000, str(launcher))}
            commands = {100: (os.getpid(), 'swift test')}
            class API:
                def identity(self, pid): return identities.get(pid)
                def commands(self): return commands.copy()
                def command(self, pid): return commands[pid][1]
            class Child:
                pid = 100
                def poll(self): return None
            observer = module.Observer(API(), lambda: bundle)
            observer.poll(Child())
            identities[100] = module.Process(100, os.getpid(), 1000, str(exec_image))
            identities[200] = module.Process(200, 100, 2000, str(helper))
            commands[200] = (100, str(helper) + ' --test-bundle-path ' + str(image))
            observer.poll(Child())
            self.assertEqual(len(observer.owned[100].images), 2)
            self.assertIn(200, observer.owned)
            identities[200] = module.Process(200, 1, 2000, str(helper)); commands[200] = (1, commands[200][1])
            observer.poll(Child()); self.assertIn(200, observer.owned)
            identities[201] = module.Process(201, 100, 3000, str(helper))
            commands[201] = (100, str(helper) + ' --test-bundle-path /unrelated/bundle.xctest')
            observer.poll(Child()); self.assertNotIn(201, observer.owned)
            identities[100] = module.Process(100, os.getpid(), 9999, str(exec_image))
            observer.poll(Child()); self.assertGreater(observer.errors['root_identity_changed'], 0)
            self.assertEqual(observer.owned[100].process.birth_us, 1000)
            # An unobserved short-lived helper cannot be invented from a later report.
            self.assertNotIn(999, observer.owned)


if __name__ == '__main__':
    unittest.main()
