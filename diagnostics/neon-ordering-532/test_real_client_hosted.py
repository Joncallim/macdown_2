"""Portable retained-metadata checks; no compiler, app, scheduler or supervisor."""
import hashlib
from pathlib import Path
import unittest
from unittest.mock import patch
import native_real_client as real
from native_real_client import analyze_real, ROOT, REAL_PATCH, SOURCE_MANIFEST


def log(invert=False, missing_execute=False):
    output = ['Test ungatedExecutedQueryAndTwoEditsPreserveOrdering(utf16Units:) started.']
    for index, size in enumerate((4096, 32768), 1):
        events = []
        fixture = f'00000000-0000-0000-0000-{index:012d}'
        def event(processor, phase, op=0, parent=0, expected=0, pending=0, range='0:0', delta=0, limit=-1):
            sequence = len(events) + 1
            events.append(f'NEON_ORDER {sequence} fixture={fixture} client=client{index} processor={processor} '
                f'phase={phase} op={op} parent={parent} expected={expected} pending={pending} '
                f'range={range} delta={delta} limit={limit} retainedDeliveries={1 if phase=="callback" else 0}')
            return sequence
        def worker(phase, op, parent=0): return event('worker', phase, op, parent)
        def mutation(phase, op, version, pending=1):
            return event('range', phase, op, version, version if phase=='compare' else 0,
                         pending, delta=op, limit=size+op)
        mutation('enqueue', 1, 0)
        for phase in ('request','submit','execute','executed','resume','callback'): worker(phase, 2, 1)
        mutation('callback', 1, 0)
        mutation('compare', 1, 0)
        event('owner', 'queryIssued', 8)
        for phase in ('request','submit'): worker(phase, 9, 8)
        execute = worker('executed' if missing_execute else 'execute', 9, 8)
        worker('executed', 9, 8); worker('resume', 9, 8)
        first = mutation('enqueue', 10, 1)
        worker('request', 12, 10); worker('submit', 12, 10)
        second = mutation('enqueue', 13, 2, 2)
        worker('request', 15, 13); worker('submit', 15, 13)
        callback = worker('callback', 9, 8)
        for op, parent in ((12,10),(15,13)):
            for phase in ('execute','executed','resume','callback'): worker(phase, op, parent)
        for op, version in (((13,2),(10,1)) if invert else ((10,1),(13,2))):
            mutation('callback', op, version); mutation('compare', op, version)
        output += [f'REAL_CLIENT_COVERAGE outcome=covered query=9 execute={execute} firstEdit={first} '
            f'secondEdit={second} queryCallback={callback} pending=2',
            f'REAL_CLIENT_TRACE case=executed-pending-{size} gates=unset evicted=0',
            'NEON_ORDER_TRACE evicted=0 capacity=512', *events]
    output += ['Test ungatedExecutedQueryAndTwoEditsPreserveOrdering(utf16Units:) with 2 test cases passed.',
               'Test run with 1 test in 1 suite passed.']
    return '\n'.join(output)


class RealClientEvidenceTests(unittest.TestCase):
    def test_finish_reaches_shared_failure_reporting_before_graph_checks(self):
        with patch.object(real.sys, 'argv', ['native_real_client.py', 'finish']), \
             patch.object(real.common, 'paths', return_value=(Path('/repo'),Path('/product'),Path('/scratch'),Path('/out'))), \
             patch.object(real.common, 'checked_state', side_effect=AssertionError('premature state check')), \
             patch.object(real.common, 'graph_for', side_effect=AssertionError('premature graph check')), \
             patch.object(real.common, 'finish', return_value=1) as finish:
            self.assertEqual(real.main(), 1)
            finish.assert_called_once()

    def test_actual_overlap_not_green_status_only(self):
        result = analyze_real(log())
        self.assertEqual(len(result['cases']), 2)
        self.assertTrue(all(case['pendingAtSecond']==2 for case in result['cases']))

    def test_no_worker_execute_is_rejected(self):
        with self.assertRaises(ValueError): analyze_real(log(missing_execute=True))

    def test_callback_inversion_is_rejected(self):
        with self.assertRaises(ValueError): analyze_real(log(invert=True))

    def test_absent_natural_coverage_is_inconclusive(self):
        with self.assertRaises(ValueError): analyze_real(log()+'\noutcome=inconclusive')

    def test_eviction_and_false_printed_claim_rejected(self):
        for text in (log().replace('NEON_ORDER_TRACE evicted=0','NEON_ORDER_TRACE evicted=1'),
                     log().replace('pending=2\nREAL_CLIENT_TRACE','pending=9\nREAL_CLIENT_TRACE')):
            with self.assertRaises(ValueError): analyze_real(text)

    def test_test_recipe_exact_reviewed_bytes(self):
        self.assertEqual(hashlib.sha256((ROOT/'real-client-harness.patch').read_bytes()).hexdigest(),REAL_PATCH)
        self.assertEqual(hashlib.sha256((ROOT/'real-client-source-SHA256.txt').read_bytes()).hexdigest(),SOURCE_MANIFEST)
        text=(ROOT/'real-client-harness.patch').read_text().split('@@ -0,0 +1,444 @@\n',1)[1]
        source=''.join(line[1:] for line in text.splitlines(keepends=True))
        self.assertEqual(hashlib.sha256(source.encode()).hexdigest(),
            '23ea4a444f2ac37de9bb1cf9cf7dd7ea83ae89a5ffb2f1f17a01851e709e7269')


if __name__ == '__main__':
    unittest.main()
