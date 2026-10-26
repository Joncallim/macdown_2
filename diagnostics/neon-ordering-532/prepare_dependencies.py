"""Proposed bounded locked resolution; network access is explicit, not offline."""
import argparse
import json
import shutil
import subprocess
from pathlib import Path
from provenance import assert_workspace, digest
from validate_bounded import run, reserve

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
    metadata = {'lockBefore': expected, 'network': 'SwiftPM may fetch locked repository revisions'}
    try:
        run('dependency-prepare', ['swift', 'package', '--package-path', str(package), '--scratch-path',
            str(args.scratch), '--force-resolved-versions', 'resolve'], 300,
            log_root=args.out, baseline_free=before, disk_budget=4 * 1024**3)
        if digest(lock) != expected:
            raise ValueError('Resolution changed the committed lock')
        metadata['effectiveGraph'] = assert_workspace(args.scratch, json.loads(lock.read_text())['pins'])
        status = 0
    except (Exception, SystemExit) as error:
        metadata['failure'] = str(error)
    finally:
        metadata.update(exitStatus=status, freeAfter=shutil.disk_usage(args.out).free, lockAfter=digest(lock))
        (args.out / 'dependency-metadata.json').write_text(json.dumps(metadata, indent=2) + '\n')
    raise SystemExit(status)

if __name__ == '__main__':
    main()
