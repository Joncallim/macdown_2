"""One original-toolchain compile and ungated actual Markdown lifecycle sequence."""
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import time
from validate_bounded import run, reserve
from crash_reports import collect, fixture_owners
from provenance import assert_workspace, assert_build_inputs, patched_files, verify_files, digest
from analyze_lifecycle_trace import analyze

ROOT = Path(__file__).resolve().parent
HEAD = 'f5605d9aead306e15ccb1bd8fb4f48b8931c1f76'
LOCK = '7e065900332e02d784b98579400c8dec1967098884db9206acd4d6bd3bcc3d1d'
NEON_PATCH = '8fcd517bcefba2b6704fd19297ea9d5779cf279f04cce994eeb3e0299e3ff986'
HARNESS_PATCH = 'fa4474c116844811a368b82329e1e54c695fab4e4e66efb5302bdd41c918959e'
SELECTED = 'MarkdownLifecycleOrderingDiagnosticTests.restoreLifetimesThenOriginalBelowCutoff'
PAYLOAD = ['.github/workflows/neon-ordering-532.yml'] + [
    'diagnostics/neon-ordering-532/' + name for name in (
        'prepare_dependencies.py', 'validate_bounded.py', 'provenance.py', 'crash_reports.py',
        'ordering-diagnostic.patch', 'test_hosted_helpers.py', 'run_lifecycle_hosted.py',
        'lifecycle-harness.patch', 'analyze_lifecycle_trace.py', 'test_lifecycle_helpers.py')]


def command(*args, cwd=None):
    return subprocess.run(args, cwd=cwd, check=True, capture_output=True,
                          text=True, timeout=15).stdout.strip()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--repo', type=Path, required=True)
    parser.add_argument('--scratch', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    repo, scratch, output = args.repo.resolve(), args.scratch.resolve(), args.out.resolve()
    if (os.environ.get('GITHUB_EVENT_NAME') != 'push' or os.environ.get('GITHUB_RUN_ATTEMPT') != '1'
            or os.environ.get('GITHUB_REF') != 'refs/heads/diagnostic/532-neon-natural-ordering-2026-10-26'):
        raise SystemExit('Only the approved publication-triggered first attempt is supported')
    if command('xcodebuild', '-version') != 'Xcode 26.0.1\nBuild version 17A400':
        raise SystemExit('Exact hosted Xcode 26.0.1/17A400 required; no install/fallback')
    if command('git', 'rev-parse', 'HEAD', cwd=repo) != HEAD or command('git', 'status', '--porcelain', cwd=repo):
        raise SystemExit('Clean exact product checkout required')
    diagnostic_head = command('git', 'rev-parse', 'HEAD', cwd=ROOT)
    if diagnostic_head != os.environ.get('GITHUB_SHA'):
        raise SystemExit('Diagnostic checkout must equal the publication event SHA')
    package = repo / 'MacDown2/Packages/MacDownKit'
    lock = package / 'Package.resolved'
    if (digest(lock) != LOCK or digest(ROOT / 'ordering-diagnostic.patch') != NEON_PATCH
            or digest(ROOT / 'lifecycle-harness.patch') != HARNESS_PATCH):
        raise SystemExit('Accepted lock/patch provenance mismatch')
    pins = json.loads(lock.read_text())['pins']
    graph = assert_workspace(scratch, pins)
    found = {p.name.lower(): p for p in (scratch / 'checkouts').iterdir() if p.is_dir()}
    for pin in pins:
        path = found[pin['identity']]
        if command('git', 'status', '--porcelain', cwd=path):
            raise SystemExit('Dependency not initially clean: ' + pin['identity'])
    neon = found['neon']
    if command('git', 'rev-parse', 'HEAD', cwd=neon) != 'dabf50c947148c49acd0d321dfe8f3805d10b3da':
        raise SystemExit('Pinned Neon baseline mismatch')
    initial = shutil.disk_usage(repo).free
    budget = 4 * 1024**3
    if initial - budget < reserve:
        raise SystemExit('Need 4GiB stage budget plus 8GiB reserve')
    output.mkdir(parents=True, exist_ok=True)
    if (output / 'metadata.json').exists():
        raise SystemExit('No overwrite or automatic retry')
    diagnostic_repo = ROOT.parents[1]
    payload_hashes = {p: digest(diagnostic_repo / p) for p in PAYLOAD}
    metadata = dict(actualProductSHA=HEAD, actualDiagnosticSHA=diagnostic_head,
                    eventSHA=os.environ['GITHUB_SHA'], eventKind='push',
                    ref=os.environ['GITHUB_REF'], runID=os.environ.get('GITHUB_RUN_ID'), runAttempt=1,
                    eventHead=None, eventBase=None, eventMerge=None,
                    toolchain='Xcode 26.0.1 / 17A400', swiftVersion=command('swift', '--version'),
                    swiftExecutable=command('xcrun', '--find', 'swift'), resolvedGraph=graph,
                    lockSHA256=LOCK, neonPatchSHA256=NEON_PATCH, harnessPatchSHA256=HARNESS_PATCH,
                    payloadHashes=payload_hashes, gates='unset', selected=SELECTED,
                    expectedFixtures=8, freeBefore=initial, stage='preparation',
                    compileCompleted=False, testCommandCompleted=False)
    started = time.time()
    status = 1
    try:
        command('git', 'apply', '--check', str(ROOT / 'ordering-diagnostic.patch'), cwd=neon)
        command('git', 'apply', '--unidiff-zero', '--check', str(ROOT / 'lifecycle-harness.patch'), cwd=package)
        command('git', 'apply', str(ROOT / 'ordering-diagnostic.patch'), cwd=neon)
        command('git', 'apply', '--unidiff-zero', str(ROOT / 'lifecycle-harness.patch'), cwd=package)
        files = patched_files(neon, ROOT / 'ordering-diagnostic.patch')
        files.update(patched_files(package, ROOT / 'lifecycle-harness.patch'))
        metadata['patchedFileHashes'] = files
        common = ['--package-path', str(package), '--scratch-path', str(scratch), '--force-resolved-versions']
        metadata['stage'] = 'compile'
        run('lifecycle-compile', ['swift', 'build', '--build-tests', '--jobs', '2'] + common,
            600, log_root=output, baseline_free=initial, disk_budget=budget)
        metadata['compileCompleted'] = True
        metadata['workspaceAfterCompile'] = assert_workspace(scratch, pins)
        metadata['buildInputs'] = assert_build_inputs(scratch, neon, repo, files)
        verify_files(files)
        metadata['stage'] = 'selected-sequence'
        run('lifecycle-test', ['swift', 'test', '--skip-build', '--no-parallel', '--filter', SELECTED] + common,
            180, log_root=output, baseline_free=initial, disk_budget=budget,
            environment=dict(os.environ, NEON_ORDER_TRACE='1'))
        metadata['testCommandCompleted'] = True
        text = (output / 'lifecycle-test.log').read_text(errors='replace')
        if not re.search(r'Test restoreLifetimesThenOriginalBelowCutoff\(\) started', text):
            raise ValueError('Selected wrapper did not execute')
        metadata['traceAnalysis'] = analyze(text, 8)
        metadata['workspaceAfterTest'] = assert_workspace(scratch, pins)
        verify_files(files)
        metadata['stage'] = 'complete'
        status = 0
    except (SystemExit, Exception) as error:
        metadata['failure'] = type(error).__name__ + ': ' + str(error)
    finally:
        log = output / 'lifecycle-test.log'
        text = log.read_text(errors='replace') if log.exists() else ''
        metadata['selectedTestExecuted'] = bool(re.search(r'Test restoreLifetimesThenOriginalBelowCutoff\(\) started', text))
        metadata['originalCaseEntered'] = 'phase=original-start gates=unset' in text
        metadata['preconditionObserved'] = 'completed mutation does not match the expected value' in text
        try:
            metadata['crashes'] = collect(Path.home() / 'Library/Logs/DiagnosticReports', output,
                                         started, fixture_owners(text))
            if digest(lock) != LOCK:
                raise ValueError('Production lock changed')
            if 'patchedFileHashes' in metadata:
                verify_files(metadata['patchedFileHashes'])
            if payload_hashes != {p: digest(diagnostic_repo / p) for p in PAYLOAD}:
                raise ValueError('Diagnostic payload changed during execution')
        except Exception as error:
            metadata['collectionOrProvenanceFailure'] = str(error)
            status = 1
        if status == 0:
            outcome = 'not-reproduced; not-fixed'
        elif metadata['preconditionObserved']:
            outcome = 'precondition-reproduced; owner-attribution-needs-trace-review'
        elif not metadata['compileCompleted']:
            outcome = 'compile-or-preparation-failed; selected-sequence-not-run'
        else:
            outcome = 'selected-sequence-or-evidence-failed; no-retry'
        metadata.update(exitStatus=status, outcome=outcome, freeAfter=shutil.disk_usage(repo).free,
                        elapsedSeconds=time.time() - started)
        encoded = json.dumps(metadata, indent=2) + '\n'
        other_metadata = sum(p.stat().st_size for p in output.iterdir() if p.is_file()
                             and p.suffix not in ('.log', '.ips', '.crash') and p.name != 'metadata.json')
        if len(encoded.encode()) + other_metadata > 64 * 1024:
            encoded = json.dumps(dict(exitStatus=1, outcome='metadata-cap-exceeded',
                                      actualProductSHA=HEAD, actualDiagnosticSHA=diagnostic_head)) + '\n'
            status = 1
        (output / 'metadata.json').write_text(encoded)
    raise SystemExit(status)


if __name__ == '__main__':
    main()
