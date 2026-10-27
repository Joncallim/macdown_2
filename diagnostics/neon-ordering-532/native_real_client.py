"""Existing real-client fixture on native hosted steps; no process supervisor."""
import json
import os
from pathlib import Path
import re
import shutil
import sys
import native_stage as common
from provenance import assert_build_inputs, verify_files, digest

ROOT = Path(__file__).resolve().parent
SELECTED = 'RealClientOrderingTests.ungatedExecutedQueryAndTwoEditsPreserveOrdering'
REAL_PATCH = 'e77b43ab7e64476c2c3c85e66b772c298736751eadba1d9d8a7640f9aa6035a9'
SOURCE_MANIFEST = '1ebb6d27976b52a96c8082c5a776f7a73d58b8f42c55710b400493f96d7addfb'
GRAMMAR = '50b8c5e61c29fa30e760c7a1cbf24b59970e6233'
EXTRA_TARGETS = (
    'Sources/RangeState/OrderingTrace.swift',
    'Sources/TreeSitterClient/BackgroundProcessor.swift',
    'Sources/TreeSitterClient/BackgroundingLanguageLayerTree.swift',
    'Sources/TreeSitterClient/TreeSitterClient.swift',
    'Tests/TreeSitterClientTests/RealClientOrderingTests.swift',
)
LOCAL = ('rearrange', 'swifttreesitter', 'tree-sitter')


def assemble(neon, target, graph, diagnostic_root=ROOT):
    """Reconstruct the already-tested small package, not another checkout."""
    if target.exists() or target.is_symlink():
        raise ValueError('Prepared package must be fresh')
    patch = diagnostic_root / 'real-client-harness.patch'
    manifest = diagnostic_root / 'real-client-source-SHA256.txt'
    if digest(patch) != REAL_PATCH or digest(manifest) != SOURCE_MANIFEST:
        raise ValueError('Reviewed b1c98f9f recipe changed')
    if [line[6:] for line in patch.read_text().splitlines() if line.startswith('+++ b/')] != list(EXTRA_TARGETS):
        raise ValueError('Unexpected real-client patch targets')
    grammar = neon / 'tree-sitter-swift'
    if common.command('git', 'rev-parse', 'HEAD', cwd=grammar) != GRAMMAR:
        raise ValueError('Pinned Neon test grammar missing or different')
    locations = {item['identity']: Path(item['path']) for item in graph}
    for identity, dirname in zip(LOCAL, ('Rearrange', 'SwiftTreeSitter', 'tree-sitter')):
        if locations[identity] != neon.parent / dirname:
            raise ValueError('Unexpected retained dependency directory')
    target.mkdir()
    for name in ('RangeState', 'TreeSitterClient', 'Neon'):
        shutil.copytree(neon / 'Sources' / name, target / 'Sources' / name)
    tests = target / 'Tests/TreeSitterClientTests'
    tests.mkdir(parents=True)
    shutil.copyfile(neon / 'Tests/TreeSitterClientTests/OrderingDiagnosticsTests.swift',
                    tests / 'OrderingDiagnosticsTests.swift')
    shutil.copyfile(neon / 'LICENSE', target / 'LICENSE')
    (target / 'grammar').symlink_to(grammar, target_is_directory=True)
    template = (diagnostic_root / 'real-client-Package.swift').read_text()
    old = 'let retained = "/tmp/mt-preview-fix-bft-derived-2026-10-26/SourcePackages/checkouts/"'
    if template.count(old) != 1:
        raise ValueError('Unexpected existing package template')
    replacement = 'let retained = ' + json.dumps(str(neon.parent) + '/')
    (target / 'Package.swift').write_text(template.replace(old, replacement))
    # RUNNER_TEMP is outside both Git checkouts; don't allow another nested-root skip.
    probe = __import__('subprocess').run(['git', 'rev-parse', '--show-toplevel'], cwd=target,
        capture_output=True, text=True, timeout=10)
    if probe.returncode == 0:
        raise ValueError('Prepared package must not be inside a Git worktree')
    before = {name: digest(target / name) if (target / name).exists() else None for name in EXTRA_TARGETS}
    common.command('git', 'apply', '--check', str(patch), cwd=target)
    common.command('git', 'apply', str(patch), cwd=target)
    for name, old_hash in before.items():
        if not (target / name).is_file() or digest(target / name) == old_hash:
            raise ValueError('Real-client patch skipped target: ' + name)
    expected = dict((name, value) for value, name in
                    (line.split('  ', 1) for line in manifest.read_text().splitlines()))
    expected['Package.swift'] = digest(target / 'Package.swift')
    actual = {str(path.relative_to(target)): digest(path) for path in target.rglob('*.swift')}
    if actual != expected:
        raise ValueError('Prepared source differs from tested thirty-file manifest')
    return {str((target / name).resolve()): value for name, value in actual.items()}


def local_graph(build, graph):
    expected = {item['identity']: Path(item['path']).resolve() for item in graph if item['identity'] in LOCAL}
    dependencies = json.loads((build / 'workspace-state.json').read_text())['object']['dependencies']
    if len(dependencies) != 3:
        raise ValueError('Prepared package must use only the three retained local dependencies')
    result = []
    for item in dependencies:
        ref = item['packageRef']
        identity = ref['identity']
        if identity not in expected or ref['kind'] != 'fileSystem' or Path(ref['location']).resolve() != expected[identity]:
            raise ValueError('Prepared compiler dependency redirected or remote')
        if common.command('git', 'status', '--porcelain', cwd=expected[identity]):
            raise ValueError('Retained dependency changed during compile')
        result.append({'identity': identity, 'path': str(expected[identity])})
    if len({item['identity'] for item in result}) != 3:
        raise ValueError('Duplicate/missing local compiler identity')
    return sorted(result, key=lambda item: item['identity'])


def analyze_real(text):
    """Verify actual overlap from retained events, not only a green test marker."""
    if ('Test run with 1 test in 1 suite passed' not in text or '✘' in text
            or 'with 2 test cases passed' not in text or 'outcome=inconclusive' in text):
        raise ValueError('Selected two-case experiment incomplete or coverage inconclusive')
    labels = re.findall(r'REAL_CLIENT_TRACE case=executed-pending-(4096|32768) gates=unset evicted=0', text)
    if sorted(labels) != ['32768', '4096']:
        raise ValueError('Both ungated sizes must report zero eviction')
    headers = re.findall(r'NEON_ORDER_TRACE evicted=(\d+) capacity=(\d+)', text)
    if len(headers) != 2 or any(value != ('0', '512') for value in headers):
        raise ValueError('Missing/evicted diagnostic rings')
    groups = {}
    for line in text.splitlines():
        if not line.startswith('NEON_ORDER '):
            continue
        parts = line.split()
        event = dict(token.split('=', 1) for token in parts[2:])
        fixture = event['fixture']
        sequence = int(parts[1])
        previous = groups.setdefault(fixture, {}).get(sequence)
        if previous is not None and previous != event:
            raise ValueError('Conflicting retained event')
        groups[fixture][sequence] = event
    if len(groups) != 2:
        raise ValueError('Need two distinct natural client fixtures')
    coverage = re.findall(r'REAL_CLIENT_COVERAGE outcome=covered query=(\d+) execute=(\d+) firstEdit=(\d+) secondEdit=(\d+) queryCallback=(\d+) pending=(\d+)', text)
    if len(coverage) != 2:
        raise ValueError('Both natural overlap observations required')
    signatures = []
    cases = []
    for fixture, entries in groups.items():
        if sorted(entries) != list(range(1, max(entries) + 1)) or len(entries) > 512:
            raise ValueError('Trace gap or oversized retained window')
        ordered = sorted(entries.items())
        enqueued = [(s, e) for s, e in ordered if e['phase'] == 'enqueue']
        if len(enqueued) != 3:  # one warm-up fill plus the two authored edits
            raise ValueError('Unexpected mutation coverage')
        range_processor = enqueued[0][1]['processor']
        callbacks = [(s, e) for s, e in ordered if e['phase'] == 'callback' and e['processor'] == range_processor]
        if [e['op'] for _, e in callbacks] != [e['op'] for _, e in enqueued]:
            raise ValueError('Mutation completion order/exactly-once mismatch')
        for _, mutation in enqueued:
            completed = [e for _, e in callbacks if e['op'] == mutation['op']]
            compare = [e for _, e in ordered if e['phase'] == 'compare' and e['op'] == mutation['op']
                       and e['processor'] == range_processor and e['client'] == mutation['client']]
            if (len(completed) != 1 or len(compare) != 1
                    or compare[0]['expected'] != mutation['parent']
                    or completed[0]['parent'] != mutation['parent']):
                raise ValueError('Mutation version/exactly-once mismatch')
            for field in ('range', 'delta', 'limit'):
                if compare[0][field] != mutation[field] or completed[0][field] != mutation[field]:
                    raise ValueError('Mutation content mismatch')
        queries = [e for _, e in ordered if e['phase'] == 'queryIssued']
        if len(queries) != 1:
            raise ValueError('Ambiguous labelled query')
        requests = [(s, e) for s, e in ordered if e['phase'] == 'request' and e['parent'] == queries[0]['op']]
        if len(requests) != 1:
            raise ValueError('Missing query-to-worker correlation')
        request = requests[0][1]
        worker = [(s, e) for s, e in ordered if e['processor'] == request['processor']
                  and e['client'] == request['client']]
        requested = [e['op'] for _, e in worker if e['phase'] == 'request']
        for phase in ('execute', 'callback'):
            if [e['op'] for _, e in worker if e['phase'] == phase] != requested:
                raise ValueError('Worker request/execute/callback order mismatch')
        submitted = [e['op'] for _, e in worker if e['phase'] == 'submit']
        if ([value for value in requested if value in submitted] != submitted
                or [e['op'] for _, e in worker if e['phase'] == 'resume'] != submitted):
            raise ValueError('Worker submission/resume mismatch')
        if any(e['retainedDeliveries'] != '1' for _, e in ordered if e['phase'] == 'callback'):
            raise ValueError('Duplicate delivery')
        execute = [s for s, e in worker if e['phase'] == 'execute' and e['op'] == request['op']]
        callback = [s for s, e in worker if e['phase'] == 'callback' and e['op'] == request['op']]
        first, second = enqueued[-2:]
        if len(execute) != 1 or len(callback) != 1 or not execute[0] < first[0] < second[0] < callback[0] or int(second[1]['pending']) < 2:
            raise ValueError('No executed-query/callback-pending two-mutation overlap')
        signature = tuple(map(str, (request['op'], execute[0], first[0], second[0], callback[0], second[1]['pending'])))
        signatures.append(signature)
        finished = [s for s, e in worker if e['phase'] == 'executed' and e['op'] == request['op']]
        cases.append(dict(fixture=fixture, eventCount=len(entries), query=request['op'],
            execute=execute[0], firstEdit=first[0], secondEdit=second[0], callback=callback[0],
            pendingAtSecond=int(second[1]['pending']), workerFinishedBeforeEdits=bool(finished and finished[0] < first[0])))
    if sorted(signatures) != sorted(coverage):
        raise ValueError('Printed coverage differs from actual trace')
    return {'verdict': 'not reproduced; not fixed', 'caseLabels': labels,
            'cases': cases, 'gates': 'unset', 'traceEvictions': 0, 'pendingAtEnd': 0}


def main():
    try:
        repo, product, scratch, output = common.paths()
        mode = sys.argv[1]
        target = scratch / 'real-client-package'
        build = scratch / 'real-client-build'
        if mode == 'finish':
            def extra(current):
                graph, neon = common.graph_for(scratch, product)
                verify_files(current['inputNeonHashes'])
                if local_graph(build, graph) != current['localCompilerGraph']:
                    raise ValueError('Local compiler graph changed')
                if common.command('git', 'rev-parse', 'HEAD', cwd=neon/'tree-sitter-swift') != GRAMMAR:
                    raise ValueError('Grammar changed')
                return {'localGraphVerified': True, 'grammarRevision': GRAMMAR}
            return common.finish(repo, product, scratch, output, trace_analyzer=analyze_real,
                selected_pattern=r'Test ungatedExecutedQueryAndTwoEditsPreserveOrdering\(',
                original_marker=None, extra_verification=extra)
        if mode == 'preflight':
            common.preflight(repo, product, scratch, output)
            state = common.read_json(output / 'state.json', common.STATE_CAP)
            state.update(selected=SELECTED, expectedFixtures=2, recipe='existing real-client, b1c98f9f')
        else:
            state = common.checked_state(repo, product, output)
            graph, neon = common.graph_for(scratch, product)
            if mode == 'patch':
                if state['stage'] != 'preflight':
                    raise ValueError('Preparation repeated/out of order')
                common.headroom(repo)
                for item in graph:
                    if common.command('git', 'status', '--porcelain', cwd=Path(item['path'])):
                        raise ValueError('Dependency initially dirty')
                application = common.prepare_diagnostic_sources(repo, neon, ROOT, plans=[
                    (neon, 'ordering-diagnostic.patch', '', common.NEON_TARGETS, False)])
                files = assemble(neon, target, graph)
                state.update(stage='patched', resolvedGraph=graph, inputNeonHashes=application['patchedFileHashes'],
                    patchedFileHashes=files, grammarRevision=GRAMMAR, packageTemplateSHA256=digest(ROOT/'real-client-Package.swift'))
            elif mode == 'verify-build':
                if state['stage'] != 'patched':
                    raise ValueError('Build verification repeated/out of order')
                verify_files(state['patchedFileHashes'])
                state['localCompilerGraph'] = local_graph(build, graph)
                state['buildInputs'] = assert_build_inputs(build, target, repo, state['patchedFileHashes'],
                    modules=('RangeState', 'TreeSitterClient', 'Neon', 'TreeSitterClientTests'))
                yaml = build / 'debug.yaml'
                if yaml.stat().st_size > 4 * 1024**2:
                    raise ValueError('Oversized compiler input plan')
                plan = yaml.read_text()
                if any(str(target/'grammar/src'/name) not in plan for name in ('parser.c', 'scanner.c')):
                    raise ValueError('Pinned grammar missing from actual compiler plan')
                state.update(stage='ready-for-test', testSince=__import__('time').time())
            else:
                raise ValueError('Fixed evidence stage required')
        common.write_json(output / 'state.json', state, common.STATE_CAP, replace=True)
        print('real-client-native-stage=' + mode + ' success')
        return 0
    except Exception as error:
        print('real-client-native-stage-failed: ' + type(error).__name__ + ': ' + str(error)[:512], file=sys.stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
