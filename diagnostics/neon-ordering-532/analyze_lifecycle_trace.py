"""Validate retained lifetime traces without rerunning tests or altering logs."""
import argparse
from collections import defaultdict
import json
from pathlib import Path
from crash_reports import fixture_owners


def analyze(text, expected_fixtures=8):
    events = {}
    markers = []
    headers = []
    phases = []
    terminal = -1
    last_header = -1
    last_dump = {}
    for index, line in enumerate(text.splitlines()):
        if line.startswith('NEON_ORDER '):
            sequence = int(line.split()[1])
            event = dict(token.split('=', 1) for token in line.split()[2:])
            if sequence in events and events[sequence] != event:
                raise ValueError('Conflicting repeated dump event')
            events[sequence] = event
            last_dump[sequence] = event
        elif line.startswith('NEON_FIXTURE '):
            markers.append(dict(token.split('=', 1) for token in line.split()[1:]))
        elif line.startswith('NEON_ORDER_TRACE '):
            last_header = index
            last_dump = {}
            headers.append(dict(token.split('=', 1) for token in line.split()[1:]))
        elif line.startswith('NEON_SEQUENCE '):
            phase = dict(token.split('=', 1) for token in line.split()[1:])
            phases.append(phase)
            if phase['phase'] == 'sequence-returned':
                terminal = index
    if '✔ Test run with 1 test in 1 suite passed' not in text or '✘' in text:
        raise ValueError('Selected test did not report success')
    stem = 'discarded' if expected_fixtures == 3 else 'restore'
    if [p['phase'] for p in phases] != [stem+'-start', stem+'-returned', 'original-start', 'original-returned', 'sequence-returned']:
        raise ValueError('Missing/incorrect sequence completion')
    if terminal < 0 or last_header <= terminal:
        raise ValueError('No terminal trace dump')
    if not last_dump or last_dump != events:
        raise ValueError('Terminal dump incomplete or inconsistent with prior evidence')
    if not headers or any(h['evicted'] != '0' for h in headers):
        raise ValueError('Missing/evicted trace')
    if sorted(events) != list(range(1, max(events, default=0) + 1)):
        raise ValueError('Trace gap')
    owners = {m['fixture'] for m in markers}
    if (len(owners) != expected_fixtures or len(markers) != expected_fixtures
            or len({m['pid'] for m in markers}) != 1 or owners != {e['fixture'] for e in events.values()}
            or {m['pid'] for m in markers} != {p['pid'] for p in phases}
            or len(fixture_owners(text)) != 1):
        raise ValueError('Missing/ambiguous fixture ownership')
    groups = defaultdict(list)
    for seq, event in sorted(events.items()):
        groups[event['fixture']].append((seq, event))
    fixtures = []
    for fixture, entries in groups.items():
        pending = []
        mutations = []
        by_processor = defaultdict(list)
        for seq, e in entries:
            by_processor[e['processor']].append((seq, e))
            if int(e['retainedDeliveries']) > 1:
                raise ValueError('Duplicate callback delivery')
        for processor, pe in by_processor.items():
            enqueues = [(s, e) for s, e in pe if e['phase'] == 'enqueue']
            if enqueues:
                expected_order = [e['op'] for _, e in enqueues]
                callbacks = [e['op'] for _, e in pe if e['phase'] == 'callback']
                if callbacks != expected_order:
                    raise ValueError('Mutation callback order/exactly-once mismatch')
                for seq, enq in enqueues:
                    cb = [e for _, e in pe if e['phase'] == 'callback' and e['op'] == enq['op']]
                    cmp = [e for _, e in pe if e['phase'] == 'compare' and e['op'] == enq['op']]
                    if len(cb) != 1 or len(cmp) != 1 or cmp[0]['expected'] != cb[0]['parent'] or cb[0]['parent'] != enq['parent']:
                        raise ValueError('Expected/received mutation version mismatch')
                    if any(cmp[0][k] != enq[k] or cb[0][k] != enq[k] for k in ('range', 'delta', 'limit')):
                        raise ValueError('Expected/received mutation content mismatch')
                    workers = [(s, e) for s, e in entries if e['phase'] == 'request' and e['parent'] == enq['op']
                               and e['client'] == enq['client'] and e['processor'] != processor]
                    if len(workers) != 1 or not any(e['phase'] == 'execute' and e['op'] == workers[0][1]['op']
                                                  and e['processor'] == workers[0][1]['processor'] for _, e in entries):
                        raise ValueError('Missing mutation-to-worker execution correlation')
                    cb_seq = next(s for s, e in pe if e['phase'] == 'callback' and e['op'] == enq['op'])
                    compare_seq = next(s for s, e in pe if e['phase'] == 'compare' and e['op'] == enq['op'])
                    worker_cb = next(s for s, e in entries if e['phase'] == 'callback'
                                     and e['op'] == workers[0][1]['op'] and e['processor'] == workers[0][1]['processor'])
                    if not seq < workers[0][0] < worker_cb < cb_seq < compare_seq:
                        raise ValueError('Mutation/worker completion chronology mismatch')
                mutations.extend(expected_order)
            else:
                requests = [(s, e) for s, e in pe if e['phase'] == 'request']
                async_ids = [e['op'] for _, e in pe if e['phase'] == 'submit']
                executed_ids = [e['op'] for _, e in pe if e['phase'] == 'execute' and e['op'] in async_ids]
                delivered_ids = [e['op'] for _, e in pe if e['phase'] == 'callback' and e['op'] in async_ids]
                request_order = [e['op'] for _, e in requests if e['op'] in async_ids]
                if request_order != async_ids or async_ids != executed_ids or async_ids != delivered_ids:
                    raise ValueError('Async submission/execution/delivery order mismatch')
                for _, req in requests:
                    callbacks = [e for _, e in pe if e['phase'] == 'callback' and e['op'] == req['op']]
                    if len(callbacks) != 1:
                        pending.append(req['op'])
                    lifecycle = [(s, e['phase']) for s, e in pe if e['op'] == req['op']]
                    expected_phases = (['request', 'submit', 'execute', 'executed', 'resume', 'callback']
                                       if req['op'] in async_ids else ['request', 'execute', 'executed', 'callback'])
                    if [phase for _, phase in lifecycle] not in (expected_phases, ['request', 'callback']):
                        raise ValueError('Worker operation phase chronology mismatch')
                    # A synchronous nil-value probe may have no execute event.
                for op in async_ids:
                    if sum(e['phase'] == 'resume' and e['op'] == op for _, e in pe) != 1:
                        raise ValueError('Async continuation resume mismatch')
        first = entries[0][1]
        if first['phase'] != 'born':
            raise ValueError('Missing editor fixture birth')
        retired = [s for s, e in entries if e['phase'] == 'retired'
                   and e['client'] == first['client'] and e['processor'] == first['processor']]
        if not mutations or not retired:
            raise ValueError('Missing mutation or fixture retirement coverage')
        fixtures.append(dict(fixture=fixture, eventCount=len(entries),
            parserClients=sorted({e['client'] for _, e in entries if e['phase'] == 'enqueue'}),
            mutationCount=len(mutations), pendingRequests=pending, retirementSequences=retired,
            eventsAfterFirstRetirement=sum(s > min(retired) for s, _ in entries) if retired else None,
            lastSequence=entries[-1][0]))
        if pending:
            raise ValueError('Requests pending in final retained window: ' + str(pending))
    return dict(uniqueEvents=len(events), fixtureCount=len(fixtures), fixtures=fixtures,
                traceEvictions=0, verdict='not reproduced in bounded selected sequence; not production acceptance')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('log', type=Path)
    parser.add_argument('--fixtures', type=int, default=8)
    args = parser.parse_args()
    print(json.dumps(analyze(args.log.read_text(), args.fixtures), indent=2))
