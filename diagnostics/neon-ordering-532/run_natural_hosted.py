"""Proposed one-shot hosted experiment. Review before execution/publication."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import time
from validate_bounded import run, reserve
from crash_reports import collect, fixture_owners
from provenance import assert_workspace, assert_build_inputs, patched_files, verify_files, correlated_events

ROOT = Path(__file__).resolve().parent
HEAD = 'f5605d9aead306e15ccb1bd8fb4f48b8931c1f76'
NEON = 'dabf50c947148c49acd0d321dfe8f3805d10b3da'
LOCK = '7e065900332e02d784b98579400c8dec1967098884db9206acd4d6bd3bcc3d1d'
PATCH = '148cf91c362b2641dc89aa41bf5591d858d8302d2a2c918d94d8505ba3d17c4f'

def command(*args, cwd=None):
    return subprocess.run(args, cwd=cwd, check=True, capture_output=True,
                          text=True, timeout=15).stdout.strip()

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def collect_crashes(output, since):
    log = output / 'natural-test.log'
    owners = fixture_owners(log.read_text(errors='replace')) if log.exists() else {}
    reports = Path.home() / 'Library/Logs/DiagnosticReports'
    return collect(reports, output, since, owners)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--repo', type=Path, required=True, help='Disposable hosted checkout at exact PR head')
    parser.add_argument('--scratch', type=Path, required=True, help='One prepared SwiftPM scratch with exact retained checkouts')
    parser.add_argument('--out', type=Path, required=True, help='New diagnostic output directory')
    args = parser.parse_args()
    repo, scratch, output = args.repo.resolve(), args.scratch.resolve(), args.out.resolve()
    if command('xcodebuild', '-version') != 'Xcode 26.0.1\nBuild version 17A400':
        raise SystemExit('Expected hosted Xcode 26.0.1/17A400; no toolchain change performed')
    if command('git', 'rev-parse', 'HEAD', cwd=repo) != HEAD or command('git', 'status', '--porcelain', cwd=repo):
        raise SystemExit('Expected clean disposable checkout at exact PR head')
    package = repo / 'MacDown2/Packages/MacDownKit'
    lock = package / 'Package.resolved'
    if digest(lock) != LOCK or digest(ROOT / 'ordering-diagnostic.patch') != PATCH:
        raise SystemExit('Lock or accepted Neon diagnostic patch provenance mismatch')
    expected = json.loads(lock.read_text())['pins']
    # Dependency preparation is an explicit prerequisite, not an implicit
    # resolve/update inside this single-compile experiment.
    checkout_root = scratch / 'checkouts'
    found = {path.name.lower(): path for path in checkout_root.iterdir() if path.is_dir()}
    graph = []
    for pin in expected:
        checkout = found.get(pin['identity'].lower())
        if checkout is None:
            raise SystemExit('Missing pre-resolved checkout: ' + pin['identity'])
        revision = command('git', 'rev-parse', 'HEAD', cwd=checkout)
        if revision != pin['state']['revision'] or command('git', 'status', '--porcelain', cwd=checkout):
            raise SystemExit('Dependency revision/cleanliness mismatch: ' + pin['identity'])
        graph.append({'identity': pin['identity'], 'location': pin['location'],
                      'state': pin['state'], 'checkoutHEAD': revision, 'checkoutPath': str(checkout)})
    neon = found['neon']
    if command('git', 'rev-parse', 'HEAD', cwd=neon) != NEON:
        raise SystemExit('Neon baseline mismatch')
    initial = shutil.disk_usage(repo).free
    budget = 4 * 1024**3
    if initial - budget < reserve:
        raise SystemExit('Insufficient estimated headroom for 4 GiB compile plus 8 GiB reserve')
    output.mkdir(parents=True, exist_ok=True)
    if (output / 'metadata.json').exists():
        raise SystemExit('Refusing to overwrite prior experiment metadata')
    event_path = os.environ.get('GITHUB_EVENT_PATH')
    event = json.loads(Path(event_path).read_text()) if event_path else {}
    pr = event.get('pull_request', {})
    metadata = {'actualCheckoutSHA': HEAD, 'eventSHA': os.environ.get('GITHUB_SHA'),
                'diagnosticCheckoutSHA': command('git', 'rev-parse', 'HEAD', cwd=ROOT),
                'eventKind': os.environ.get('GITHUB_EVENT_NAME'), 'diagnosticRef': os.environ.get('GITHUB_REF'),
                'runID': os.environ.get('GITHUB_RUN_ID'), 'runAttempt': os.environ.get('GITHUB_RUN_ATTEMPT'),
                'eventHead': pr.get('head', {}).get('sha'), 'eventBase': pr.get('base', {}).get('sha'),
                'eventMerge': pr.get('merge_commit_sha'), 'graph': graph,
                'lockSHA256': LOCK, 'neonPatchSHA256': PATCH,
                'harnessPatchSHA256': digest(ROOT / 'natural-harness.patch'), 'freeBefore': initial,
                'toolchain': 'Xcode 26.0.1 / 17A400', 'swiftVersion': command('swift', '--version'),
                'swiftExecutable': command('xcrun', '--find', 'swift'), 'gates': 'unset'}
    started = time.time()
    status = 1
    try:
        metadata['workspaceBeforePatch'] = assert_workspace(scratch, expected)
        command('git', 'apply', '--check', str(ROOT / 'ordering-diagnostic.patch'), cwd=neon)
        command('git', 'apply', '--check', str(ROOT / 'natural-harness.patch'), cwd=repo)
        command('git', 'apply', str(ROOT / 'ordering-diagnostic.patch'), cwd=neon)
        command('git', 'apply', str(ROOT / 'natural-harness.patch'), cwd=repo)
        files = patched_files(neon, ROOT / 'ordering-diagnostic.patch')
        files.update(patched_files(repo, ROOT / 'natural-harness.patch'))
        metadata['patchedFileHashes'] = files
        common = ['--package-path', str(package), '--scratch-path', str(scratch), '--force-resolved-versions']
        run('natural-compile', ['swift', 'build', '--build-tests', '--jobs', '2'] + common,
            600, log_root=output, baseline_free=initial, disk_budget=budget)
        metadata['workspaceAfterCompile'] = assert_workspace(scratch, expected)
        verify_files(files)
        metadata['buildInputs'] = assert_build_inputs(scratch, neon, repo, files)
        environment = dict(os.environ, NEON_ORDER_TRACE='1')
        run('natural-test', ['swift', 'test', '--skip-build', '--no-parallel', '--filter',
            'HighlightingSizeFallbackTests.belowTheCutoffHighlightingMatchesAFreshHighlighter'] + common,
            180, log_root=output, baseline_free=initial, disk_budget=budget, environment=environment)
        text = (output / 'natural-test.log').read_text(errors='replace')
        if not re.search(r'Test belowTheCutoffHighlightingMatchesAFreshHighlighter\(\) started', text):
            raise SystemExit('Selected Swift Testing case did not execute')
        if not re.search(r'Test run with 1 test(?: in| passed)', text):
            raise SystemExit('Expected exactly one executed test')
        metadata['correlatedEvents'] = correlated_events(text)
        metadata['workspaceAfterTest'] = assert_workspace(scratch, expected)
        verify_files(files)
        status = 0
    except SystemExit as error:
        status = error.code if isinstance(error.code, int) and error.code != 0 else 1
        metadata['failure'] = str(error)
    except Exception as error:
        metadata['failure'] = type(error).__name__ + ': ' + str(error)
    finally:
        # Collection errors cannot turn a failed command into success.
        try:
            metadata['crashes'] = collect_crashes(output, started)
        except Exception as error:
            metadata['collectionFailure'] = str(error)
            status = status or 1
        if digest(lock) != LOCK:
            metadata['lockChanged'] = True
            status = status or 1
        if 'patchedFileHashes' in metadata:
            try:
                verify_files(metadata['patchedFileHashes'])
            except Exception as error:
                metadata['patchVerificationFailure'] = str(error)
                status = status or 1
        metadata.update(exitStatus=status, freeAfter=shutil.disk_usage(repo).free,
                        elapsedSeconds=time.time() - started)
        (output / 'metadata.json').write_text(json.dumps(metadata, indent=2) + '\n')
    raise SystemExit(status)

if __name__ == '__main__':
    main()
