"""Fixed evidence stages; heavy commands and cancellation belong to GitHub."""
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import subprocess
import sys
import time
from analyze_lifecycle_trace import analyze
from crash_reports import collect, fixture_owners
from provenance import assert_workspace, assert_build_inputs, verify_files, digest

ROOT = Path(__file__).resolve().parent
HEAD = 'f5605d9aead306e15ccb1bd8fb4f48b8931c1f76'
LOCK = '7e065900332e02d784b98579400c8dec1967098884db9206acd4d6bd3bcc3d1d'
NEON_PATCH = '8fcd517bcefba2b6704fd19297ea9d5779cf279f04cce994eeb3e0299e3ff986'
NEON_HEAD = 'dabf50c947148c49acd0d321dfe8f3805d10b3da'
HARNESS_PATCH = 'fa4474c116844811a368b82329e1e54c695fab4e4e66efb5302bdd41c918959e'
SELECTED = 'MarkdownLifecycleOrderingDiagnosticTests.restoreLifetimesThenOriginalBelowCutoff'

FILES = (
    'native_stage.py', 'cap_stream.py', 'provenance.py', 'crash_reports.py',
    'analyze_lifecycle_trace.py', 'ordering-diagnostic.patch', 'lifecycle-harness.patch',
    'test_native_helpers.py', 'test_patch_root.py', 'test_lifecycle_helpers.py',
)
PAYLOAD = ['.github/workflows/neon-ordering-532.yml'] + [
    'diagnostics/neon-ordering-532/' + name for name in FILES]
LOGS = ('helper-tests.log', 'dependency-prepare.log', 'lifecycle-compile.log', 'lifecycle-test.log')
CAP = 1024**2
RESERVE = 8 * 1024**3
BUDGET = 4 * 1024**3
STATE_CAP = 24 * 1024
METADATA_CAP = 24 * 1024
META_RESERVATION = 64 * 1024
STEPS = ('PREFLIGHT', 'HELPERS', 'RESOLVE', 'PATCH', 'COMPILE', 'INPUTS', 'SELECTED')


def command(*args, cwd=None):
    # Only fixed Git/toolchain metadata calls, never Swift build/test/process APIs.
    if args[0] not in ('git', 'xcodebuild', 'xcrun') and args != ('swift', '--version'):
        raise ValueError('Non-metadata executable refused')
    return subprocess.run(args, cwd=cwd, check=True, capture_output=True,
                          text=True, timeout=10).stdout.strip()


def write_json(path, value, cap, replace=False):
    data = (json.dumps(value, indent=2, allow_nan=False) + '\n').encode()
    if len(data) > cap:
        raise ValueError('Metadata allocation exceeded: ' + path.name)
    # No followed output links, including existing state on later stages.
    if path.is_symlink() or (path.exists() and not path.is_file()):
        raise ValueError('Unsafe evidence target')
    if path.exists() and not replace:
        raise ValueError('Evidence overwrite refused')
    flags = os.O_WRONLY | os.O_CREAT | os.O_NOFOLLOW
    flags |= os.O_TRUNC if replace else os.O_EXCL
    with os.fdopen(os.open(path, flags, 0o600), 'wb') as handle:
        handle.write(data)


def read_json(path, cap):
    if path.is_symlink() or not path.is_file() or path.stat().st_size > cap:
        raise ValueError('Missing/unsafe/oversized metadata: ' + path.name)
    return json.loads(path.read_bytes())


def paths():
    temp = Path(os.environ['RUNNER_TEMP'])
    workspace = Path(os.environ['GITHUB_WORKSPACE'])
    repo = Path(os.environ['PRODUCT'])
    package = Path(os.environ['PACKAGE'])
    scratch = Path(os.environ['SCRATCH'])
    output = Path(os.environ['EVIDENCE'])
    expected = (workspace / 'product', workspace / 'product/MacDown2/Packages/MacDownKit',
                temp / 'neon532-scratch', temp / 'neon532-evidence')
    canonical = (workspace.resolve() / 'product', workspace.resolve() / 'product/MacDown2/Packages/MacDownKit',
                 temp.resolve() / 'neon532-scratch', temp.resolve() / 'neon532-evidence')
    for actual, wanted, resolved in zip((repo, package, scratch, output), expected, canonical):
        if not actual.is_absolute() or actual != wanted or actual.resolve() != resolved:
            raise ValueError('Noncanonical/redirected hosted path')
    if ROOT != workspace.resolve() / 'diagnostic-source/diagnostics/neon-ordering-532':
        raise ValueError('Diagnostic helper outside exact checkout path')
    return tuple(path.resolve() for path in (repo, package, scratch, output))


def identity(repo, package):
    if (os.environ.get('GITHUB_EVENT_NAME') != 'push'
            or os.environ.get('GITHUB_RUN_ATTEMPT') != '1'
            or os.environ.get('GITHUB_REPOSITORY') != 'Joncallim/macdown_2'
            or os.environ.get('GITHUB_REF') != 'refs/heads/diagnostic/532-neon-natural-ordering-2026-10-26'):
        raise ValueError('Only one approved publication attempt on diagnostic branch')
    if command('xcodebuild', '-version') != 'Xcode 26.0.1\nBuild version 17A400':
        raise ValueError('Exact hosted toolchain required')
    if command('git', 'rev-parse', 'HEAD', cwd=repo) != HEAD:
        raise ValueError('Product HEAD mismatch')
    actual = command('git', 'rev-parse', 'HEAD', cwd=ROOT)
    if actual != os.environ.get('GITHUB_SHA'):
        raise ValueError('Diagnostic event/checkout mismatch')
    if (digest(package / 'Package.resolved') != LOCK
            or digest(ROOT / 'ordering-diagnostic.patch') != NEON_PATCH
            or digest(ROOT / 'lifecycle-harness.patch') != HARNESS_PATCH):
        raise ValueError('Lock or reviewed source patch mismatch')
    return actual


def payload_hashes():
    return {p: digest(ROOT.parents[1] / p) for p in PAYLOAD}


def headroom(repo):
    free = shutil.disk_usage(repo).free
    if free < RESERVE + BUDGET:
        raise ValueError('Need 4GiB stage estimate plus 8GiB reserve')
    return free


def checked_state(repo, package, output):
    state = read_json(output / 'state.json', STATE_CAP)
    if identity(repo, package) != state['actualDiagnosticSHA'] or payload_hashes() != state['payloadHashes']:
        raise ValueError('Diagnostic identity/payload changed between stages')
    return state


def preflight(repo, package, scratch, output):
    actual = identity(repo, package)
    if scratch.exists() or scratch.is_symlink() or output.exists() or output.is_symlink():
        raise ValueError('Fresh scratch/evidence paths required; no retry/overwrite')
    if command('git', 'status', '--porcelain', cwd=repo):
        raise ValueError('Product checkout initially dirty')
    free = headroom(repo)
    output.mkdir(mode=0o700)
    toolchain = b'Xcode 26.0.1\nBuild version 17A400\n'
    with (output / 'toolchain.txt').open('xb') as handle:
        handle.write(toolchain)
    write_json(output / 'state.json', dict(actualProductSHA=HEAD, actualDiagnosticSHA=actual,
        eventSHA=os.environ['GITHUB_SHA'], runID=os.environ.get('GITHUB_RUN_ID'),
        runAttempt=1, ref=os.environ['GITHUB_REF'], eventKind='push',
        eventHead=None, eventBase=None, eventMerge=None,
        runnerImage={name: os.environ.get(name) for name in
                     ('ImageOS', 'ImageVersion', 'RUNNER_OS', 'RUNNER_ARCH')},
        started=time.time(), freeBefore=free,
        toolchain=toolchain.decode().strip(), swiftVersion=command('swift', '--version')[:1024],
        swiftExecutable=command('xcrun', '--find', 'swift')[:1024],
        payloadHashes=payload_hashes(), lockSHA256=LOCK, gates='unset', stage='preflight',
        selected=SELECTED, expectedFixtures=8), STATE_CAP)


def pins_for(package):
    pins = json.loads((package / 'Package.resolved').read_text())['pins']
    if len(pins) != 23 or len({p['identity'] for p in pins}) != 23:
        raise ValueError('Expected all 23 distinct production pins')
    return pins


def graph_for(scratch, package):
    graph = assert_workspace(scratch, pins_for(package))
    neon = [item for item in graph if item['identity'] == 'neon']
    if len(neon) != 1 or neon[0]['revision'] != NEON_HEAD:
        raise ValueError('Effective pinned Neon mismatch')
    return graph, Path(neon[0]['path'])


HARNESS_TARGETS = (
    'Sources/Highlighting/NeonSyntaxHighlighter.swift',
    'Tests/HighlightingTests/KeystrokeStallSupport.swift',
    'Tests/HighlightingTests/SizeFallbackTestSupport.swift',
    'Tests/HighlightingTests/HighlightingSizeFallbackTests.swift',
    'Tests/HighlightingTests/MarkdownLifecycleOrderingDiagnosticTests.swift',
)
NEON_TARGETS = (
    'Sources/RangeState/AwaitableQueue.swift', 'Sources/RangeState/RangeProcessor.swift',
    'Sources/TreeSitterClient/BackgroundProcessor.swift',
    'Sources/TreeSitterClient/BackgroundingLanguageLayerTree.swift',
    'Sources/TreeSitterClient/TreeSitterClient.swift', 'Sources/Neon/TextViewHighlighter.swift',
    'Sources/RangeState/OrderingTrace.swift', 'Tests/TreeSitterClientTests/OrderingDiagnosticsTests.swift',
)


def prepare_diagnostic_sources(repo, neon, diagnostic_root):
    """Apply only the two known patches from their actual Git roots; prove changes."""
    plans = [
        (Path(neon).resolve(), 'ordering-diagnostic.patch', '', NEON_TARGETS, False),
        (Path(repo).resolve(), 'lifecycle-harness.patch', 'MacDown2/Packages/MacDownKit', HARNESS_TARGETS, True),
    ]
    prepared = []
    for root, name, prefix, targets, zero_context in plans:
        actual_root = Path(command('git', 'rev-parse', '--show-toplevel', cwd=root)).resolve()
        if actual_root != root or command('git', 'status', '--porcelain', cwd=root):
            raise ValueError('Patch needs its clean Git root: ' + str(root))
        patch = (Path(diagnostic_root) / name).resolve()
        declared = [line[6:] for line in patch.read_text().splitlines() if line.startswith('+++ b/')]
        if declared != list(targets) or len(set(declared)) != len(targets):
            raise ValueError('Unexpected/missing patch target set: ' + name)
        base = (root / prefix).resolve()
        if not base.is_relative_to(root):
            raise ValueError('Patch directory escapes Git root')
        before = {}
        for relative in targets:
            parts = PurePosixPath(relative)
            if parts.is_absolute() or '..' in parts.parts:
                raise ValueError('Unsafe patch target')
            path = base / relative
            if path.is_symlink() or not path.resolve().is_relative_to(base):
                raise ValueError('Patch target redirects outside its scope')
            if path.exists() and not path.is_file():
                raise ValueError('Patch target is not a regular file')
            before[relative] = digest(path) if path.exists() else None
        argv = ['git', 'apply']
        if zero_context:
            argv.append('--unidiff-zero')
        if prefix:
            argv.append('--directory=' + prefix)
        # Preflight both patches before either repository is mutated.
        command(*argv, '--check', str(patch), cwd=root)
        prepared.append((root, patch, base, targets, before, argv))
    files = {}
    applications = []
    for root, patch, base, targets, before, argv in prepared:
        command(*argv, str(patch), cwd=root)
        hashes = {}
        for relative in targets:
            path = base / relative
            if path.is_symlink() or not path.is_file() or not path.resolve().is_relative_to(base):
                raise ValueError('Patch failed to materialize regular target: ' + relative)
            value = digest(path)
            if value == before[relative]:
                raise ValueError('Successful git apply left target unchanged: ' + relative)
            hashes[str(path.resolve())] = value
        tracked = command('git', 'diff', '--name-only', '--no-renames', '-z', cwd=root)
        untracked = command('git', 'ls-files', '--others', '--exclude-standard', '-z', cwd=root)
        changed = {p for text in (tracked, untracked) for p in text.split('\0') if p}
        expected = {str((base / relative).relative_to(root)) for relative in targets}
        if changed != expected:
            raise ValueError('Applied file set differs from exact target scope: ' + patch.name)
        files.update(hashes)
        applications.append({'patch': patch.name, 'cwd': str(root),
                             'targets': sorted(expected), 'materializedCount': len(hashes)})
    return {'applications': applications, 'patchedFileHashes': files}



def patch_sources(repo, package, scratch, output):
    state = checked_state(repo, package, output)
    if state['stage'] != 'preflight':
        raise ValueError('Patch stage repeated/out of order')
    headroom(repo)
    graph, neon = graph_for(scratch, package)
    for item in graph:
        if command('git', 'status', '--porcelain', cwd=Path(item['path'])):
            raise ValueError('Dependency initially dirty')
    application = prepare_diagnostic_sources(repo, neon, ROOT)
    state.update(stage='patched', resolvedGraph=graph, neon=str(neon),
                 patchedFileHashes=application['patchedFileHashes'],
                 patchApplication=application['applications'])
    write_json(output / 'state.json', state, STATE_CAP, replace=True)


def verify_build(repo, package, scratch, output):
    state = checked_state(repo, package, output)
    if state['stage'] != 'patched':
        raise ValueError('Build verification repeated/out of order')
    headroom(repo)
    graph, neon = graph_for(scratch, package)
    if graph != state['resolvedGraph']:
        raise ValueError('Effective graph changed')
    verify_files(state['patchedFileHashes'])
    inputs = assert_build_inputs(scratch, neon, repo, state['patchedFileHashes'])
    state.update(stage='ready-for-test', buildInputs=inputs, testSince=time.time())
    write_json(output / 'state.json', state, STATE_CAP, replace=True)


def audit_evidence(output):
    metadata_names = {'state.json': STATE_CAP, 'metadata.json': METADATA_CAP, 'toolchain.txt': 1024}
    metadata_names.update({name + '.overflow.json': 1024 for name in LOGS})
    total = 0
    meta = 0
    crash_count = 0
    for path in output.iterdir():
        if path.is_symlink() or not path.is_file():
            raise ValueError('Nonregular evidence')
        size = path.stat().st_size
        if path.name in LOGS:
            cap = CAP
        elif path.name in metadata_names:
            cap = metadata_names[path.name]
            meta += size
        elif re.fullmatch(r'crash-[0-7]\.(ips|crash)', path.name):
            cap = CAP
            crash_count += 1
        else:
            raise ValueError('Unexpected evidence filename: ' + path.name)
        if size > cap:
            raise ValueError('Evidence per-file cap exceeded')
        total += size
    if meta > META_RESERVATION or total > 8 * CAP or crash_count > 8:
        raise ValueError('Evidence aggregate cap exceeded')
    return total


def finish(repo, package, scratch, output):
    report = dict(outcome='incomplete; no race verdict', exitStatus=1,
        stages={name: os.environ.get(name + '_OUTCOME', 'missing') for name in STEPS})
    status = 1
    try:
        audit_evidence(output)
        state = checked_state(repo, package, output)
        report.update(actualProductSHA=state['actualProductSHA'],
                      actualDiagnosticSHA=state['actualDiagnosticSHA'],
                      eventSHA=state['eventSHA'], runID=state['runID'])
        # Preserve attributable crash evidence even when the retained log is truncated.
        # Truncation remains fatal below; it can never establish a passing verdict.
        test_log = output / 'lifecycle-test.log'
        text = (test_log.read_text(errors='replace') if not test_log.is_symlink()
                and test_log.is_file() and test_log.stat().st_size <= CAP else '')
        report.update(selectedTestExecuted=bool(re.search(
            r'Test restoreLifetimesThenOriginalBelowCutoff\(\) started', text)),
            originalCaseEntered='phase=original-start gates=unset' in text,
            preconditionObserved='completed mutation does not match the expected value' in text)
        report['crashes'] = collect(Path.home() / 'Library/Logs/DiagnosticReports', output,
            state.get('testSince', state['started']), fixture_owners(text))
        logs = {}
        for name in LOGS:
            path = output / name
            if path.is_symlink() or not path.is_file() or path.stat().st_size > CAP:
                raise ValueError('Required log missing/unsafe/oversized: ' + name)
            if (output / (name + '.overflow.json')).exists():
                raise ValueError('Log truncated: ' + name)
            logs[name] = path.read_text(errors='replace')
        if (output / 'toolchain.txt').read_bytes() != b'Xcode 26.0.1\nBuild version 17A400\n':
            raise ValueError('Toolchain evidence missing or changed')
        if state['stage'] != 'ready-for-test' or any(value != 'success' for value in report['stages'].values()):
            raise ValueError('Preparation/compile/test did not all succeed')
        if not report['selectedTestExecuted'] or not report['originalCaseEntered']:
            raise ValueError('Actual selected/original cases not observed')
        if graph_for(scratch, package)[0] != state['resolvedGraph']:
            raise ValueError('Effective graph changed after test')
        verify_files(state['patchedFileHashes'])
        report['traceAnalysis'] = analyze(text, 8)
        headroom(repo)
        report.update(outcome='not-reproduced; not-fixed', exitStatus=0)
        status = 0
    except Exception as error:
        report['failure'] = (type(error).__name__ + ': ' + str(error))[:512]
        if report.get('preconditionObserved'):
            report['outcome'] = 'precondition observed; attribution requires trace review'
    try:
        report['freeAfter'] = shutil.disk_usage(repo).free
        write_json(output / 'metadata.json', report, METADATA_CAP)
        audit_evidence(output)
    except Exception as error:
        print('evidence-finalization-failed: ' + type(error).__name__, file=sys.stderr)
        return 1
    return status


def main():
    try:
        if len(sys.argv) != 2 or sys.argv[1] not in ('preflight', 'patch', 'verify-build', 'finish'):
            raise ValueError('Fixed evidence stage required')
        repo, package, scratch, output = paths()
        stage = sys.argv[1]
        if stage == 'finish':
            return finish(repo, package, scratch, output)
        if stage == 'preflight':
            preflight(repo, package, scratch, output)
        elif stage == 'patch':
            patch_sources(repo, package, scratch, output)
        else:
            verify_build(repo, package, scratch, output)
        print('native-evidence-stage=' + stage + ' success')
        return 0
    except Exception as error:
        print('native-evidence-stage-failed: ' + type(error).__name__ + ': ' + str(error)[:512], file=sys.stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
