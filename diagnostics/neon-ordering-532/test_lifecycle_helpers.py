"""Portable metadata-parser fixtures only; never compile or invoke the editor."""
import base64
import unittest
from analyze_lifecycle_trace import analyze


def fixture_log(invert_submission=False, invert_delivery=False):
    lines = ['NEON_SEQUENCE pid=42 phase=restore-start gates=unset']
    events = []
    def event(f, c, p, phase, op=0, parent=0, expected=0, pending=0, delta=0, limit=-1):
        events.append(f'NEON_ORDER {len(events)+1} fixture={f} client={c} processor={p} phase={phase} '
                      f'op={op} parent={parent} expected={expected} pending={pending} range=0:0 '
                      f'delta={delta} limit={limit} retainedDeliveries={1 if phase=="callback" else 0}')
    for i in range(1, 9):
        if i == 7:
            lines += ['NEON_SEQUENCE pid=42 phase=restore-returned gates=unset',
                      'NEON_SEQUENCE pid=42 phase=original-start gates=unset']
        f = f'00000000-0000-0000-0000-{i:012d}'
        lines.append(f'NEON_FIXTURE pid=42 fixture={f} identity64={base64.b64encode(b"Owned").decode()}')
        c, r, w = f'client{i}', f'range{i}', f'worker{i}'
        event(f, 'owner'+c, 'owner'+r, 'born')
        event(f, c, r, 'enqueue', 1, delta=1, limit=1)
        if i == 1:
            for op in (2, 3): event(f, c, w, 'request', op, parent=1 if op==2 else 0)
            order = (3, 2) if invert_submission else (2, 3)
            for op in order: event(f, c, w, 'submit', op, parent=1 if op==2 else 0)
            for op in order:
                for phase in ('execute', 'executed', 'resume'):
                    event(f, c, w, phase, op, parent=1 if op==2 else 0)
            for op in ((3, 2) if invert_delivery else order):
                event(f, c, w, 'callback', op, parent=1 if op==2 else 0)
        else:
            for phase in ('request', 'execute', 'executed', 'callback'):
                event(f, c, w, phase, 2, parent=1)
        event(f, c, r, 'callback', 1, delta=1, limit=1)
        event(f, c, r, 'compare', 1, delta=1, limit=1)
        event(f, 'owner'+c, 'owner'+r, 'retired')
    lines += ['NEON_SEQUENCE pid=42 phase=original-returned gates=unset',
              'NEON_SEQUENCE pid=42 phase=sequence-returned gates=unset',
              'NEON_ORDER_TRACE evicted=0 capacity=4096'] + events
    lines += ['✔ Test run with 1 test in 1 suite passed after 1.0 seconds.']
    return '\n'.join(lines)


class LifecycleTraceTests(unittest.TestCase):
    def test_complete_eight_owner_trace(self):
        self.assertEqual(analyze(fixture_log(), 8)['fixtureCount'], 8)

    def test_submission_inversion(self):
        with self.assertRaises(ValueError): analyze(fixture_log(invert_submission=True), 8)

    def test_delivery_inversion(self):
        with self.assertRaises(ValueError): analyze(fixture_log(invert_delivery=True), 8)

    def test_missing_owner(self):
        text = '\n'.join(l for l in fixture_log().splitlines() if not l.startswith('NEON_FIXTURE '))
        with self.assertRaises(ValueError): analyze(text, 8)

    def test_missing_terminal_evidence(self):
        text = '\n'.join(l for l in fixture_log().splitlines() if not l.startswith('NEON_ORDER '))
        with self.assertRaises(ValueError): analyze(text, 8)

    def test_incorrect_version(self):
        text = '\n'.join(l.replace('parent=0', 'parent=99') if 'phase=enqueue ' in l else l
                         for l in fixture_log().splitlines())
        with self.assertRaises(ValueError): analyze(text, 8)


if __name__ == '__main__':
    unittest.main()
