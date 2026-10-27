"""Proposed bounded locked resolution; network access is explicit, not offline."""
import argparse
import json
import math
import re
import time
import shutil
import subprocess
from pathlib import Path
from provenance import assert_workspace, digest
from validate_bounded import run, reserve


def summarize_fetches(text):
    """Bounded public-repository metadata, not per-byte activity or stall proof."""
    starts = re.findall(r'^Fetching (https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)\s*$', text, re.M)
    done = re.findall(r'^Fetched (https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+) from cache \(([0-9]+(?:\.[0-9]+)?)s\)', text, re.M)
    valid_starts = [url for url in starts if len(url) <= 256]
    reported = []
    skipped = len(starts) - len(valid_starts)
    for url, duration in done:
        if len(url) > 256 or len(duration) > 16:
            skipped += 1
            continue
        seconds = float(duration)
        if not math.isfinite(seconds) or not 0 <= seconds <= 3600:
            skipped += 1
            continue
        reported.append({'url': url, 'reportedSeconds': seconds})
    completed = {item['url'] for item in reported}
    outstanding = [url for url in valid_starts if url not in completed]
    retained = reported[:32]
    result = {'fetchStarts': len(starts), 'fetchCompletions': len(done),
            'workingCopyStarts': len(re.findall(r'^Creating working copy', text, re.M)),
            'outstandingAtLogEnd': outstanding[:max(0, 32 - len(retained))],
            'reportedFetches': retained, 'skippedMalformedFields': skipped,
            'summaryCapped': len(reported) + len(outstanding) > 32 or skipped > 0,
            'limitation': 'untimestamped delegate logs; durations are not additive wall time or proof of network activity'}
    if len(json.dumps(result, allow_nan=False).encode()) > 12 * 1024:
        result.update(reportedFetches=[], outstandingAtLogEnd=[], summaryCapped=True,
                      summaryByteCapExceeded=True)
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--repo', type=Path, required=True)
    parser.add_argument('--scratch', type=Path, required=True)
    parser.add_argument('--out', type=Path, required=True)
    args = parser.parse_args()
    if subprocess.check_output(['xcodebuild', '-version'], text=True, timeout=10).strip() != 'Xcode 26.0.1\nBuild version 17A400':
        raise SystemExit('Exact hosted toolchain required')
    if args.scratch.exists():
        raise SystemExit('Dependency preparation requires a new scratch path')
    args.out.mkdir(parents=True, exist_ok=True)
    if (args.out / 'dependency-metadata.json').exists():
        raise SystemExit('Refusing to overwrite dependency evidence')
    head = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=args.repo, text=True, timeout=10).strip()
    if head != 'f5605d9aead306e15ccb1bd8fb4f48b8931c1f76':
        raise SystemExit('Exact product checkout required before dependency preparation')
    package = args.repo / 'MacDown2/Packages/MacDownKit'
    lock = package / 'Package.resolved'
    expected = '7e065900332e02d784b98579400c8dec1967098884db9206acd4d6bd3bcc3d1d'
    before = shutil.disk_usage(args.out).free
    if digest(lock) != expected or before - 4 * 1024**3 < reserve:
        raise SystemExit('Lock/headroom precondition failed')
    status = 1
    metadata = {'lockBefore': expected, 'network': 'SwiftPM may fetch locked repository revisions',
                'resolveDeadlineSeconds': 480, 'phase': 'resolve'}
    started = time.monotonic()
    resolve_elapsed = None
    try:
        run('dependency-prepare', ['swift', 'package', '--package-path', str(package), '--scratch-path',
            str(args.scratch), '--force-resolved-versions', 'resolve'], 480,
            log_root=args.out, baseline_free=before, disk_budget=4 * 1024**3)
        resolve_elapsed = time.monotonic() - started
        metadata['phase'] = 'verify-workspace'
        if digest(lock) != expected:
            raise ValueError('Resolution changed the committed lock')
        metadata['effectiveGraph'] = assert_workspace(args.scratch, json.loads(lock.read_text())['pins'])
        metadata['phase'] = 'complete'
        status = 0
    except (Exception, SystemExit) as error:
        metadata['failure'] = str(error)
    finally:
        metadata['resolveElapsedSeconds'] = resolve_elapsed if resolve_elapsed is not None else time.monotonic() - started
        log = args.out / 'dependency-prepare.log'
        if log.is_file():
            try:
                with log.open('r', errors='replace') as handle:
                    metadata['fetchSummary'] = summarize_fetches(handle.read(1024**2))
            except OSError as error:
                metadata['fetchSummaryError'] = type(error).__name__
        metadata.update(exitStatus=status, freeAfter=shutil.disk_usage(args.out).free, lockAfter=digest(lock))
        encoded = json.dumps(metadata, indent=2, allow_nan=False) + '\n'
        if len(encoded.encode()) > 24 * 1024:
            status = 1
            encoded = json.dumps({'exitStatus': 1, 'failure': 'setup metadata cap exceeded',
                                  'originalFailure': str(metadata.get('failure', ''))[:512],
                                  'phase': metadata['phase'], 'lockBefore': expected,
                                  'lockAfter': metadata['lockAfter'], 'resolveDeadlineSeconds': 480}) + '\n'
        (args.out / 'dependency-metadata.json').write_text(encoded)
    raise SystemExit(status)


if __name__ == '__main__':
    main()
