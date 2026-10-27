"""Bounded incremental checks: signal only directly owned live Popen children."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import selectors
import shutil
import subprocess
import time
ROOT = Path(__file__).resolve().parent
VOLUME = Path('/Volumes/Fast SSD')
OUTPUT = VOLUME / 'CORTANA-Builds/neon-real-client-2026-10-27'
COMMON = VOLUME / 'CORTANA-GitHub/macdown_2/.git'

def command(*args, cwd=None):
    return subprocess.run(args, cwd=cwd, check=True, text=True,
                          capture_output=True, timeout=15).stdout.strip()

def owned_run(name, arguments, seconds, *, environment=None, log_cap=1024**2):
    log = OUTPUT / (name + '.log')
    if log.exists():
        raise SystemExit('Refusing to overwrite retained log ' + str(log))
    started = time.monotonic()
    initial = shutil.disk_usage(VOLUME).free
    reason = None
    discarded = 0
    written = 0
    # No process-group probe/signal. The test child is SwiftPM's actual helper,
    # not a swift-test wrapper or an unrelated testmanager/app process.
    process = subprocess.Popen(arguments, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, env=environment)
    print(f'{name}: owned_pid={process.pid} argv={arguments}', flush=True)
    selector = selectors.DefaultSelector()
    os.set_blocking(process.stdout.fileno(), False)
    selector.register(process.stdout, selectors.EVENT_READ)
    exited = None
    terminated = None
    killed = False
    try:
        with log.open('wb') as output:
            while True:
                now = time.monotonic()
                code = process.poll()
                if code is not None and exited is None:
                    exited = now
                if code is not None and not selector.get_map():
                    break
                free = shutil.disk_usage(VOLUME).free
                if reason is None and (now - started >= seconds or free < 8 * 1024**3
                                       or initial - free > 2 * 1024**3 or discarded):
                    reason = 'time/disk/log bound'
                if exited is not None and now - exited >= 1:
                    reason = reason or 'owned child exited with lingering pipe; bounded drain only'
                    break
                if reason and code is None and terminated is None:
                    # Popen has not been reaped or reused: only this direct child.
                    process.terminate()
                    terminated = now
                if terminated is not None and code is None:
                    if now - terminated >= 5 and not killed:
                        process.kill()
                        killed = True
                    if now - terminated >= 7:
                        reason += '; direct-child cleanup deadline'
                        break
                for key, _ in selector.select(timeout=0.1):
                    data = os.read(key.fileobj.fileno(), 65536)
                    if not data:
                        selector.unregister(key.fileobj)
                    else:
                        keep = data[:max(0, log_cap - written)]
                        output.write(keep)
                        written += len(keep)
                        discarded += len(data) - len(keep)
    finally:
        selector.close()
        process.stdout.close()
    # No fallback signal route on a permission error; let the exact denial surface.
    code = process.poll()
    if code is None:
        reason = reason or 'owned child still active; inspect before any retry'
    result = {'pid': process.pid, 'exitStatus': code, 'elapsedSeconds': time.monotonic() - started,
              'reason': reason, 'discardedBytes': discarded, 'logBytes': written}
    print(json.dumps(result), flush=True)
    return result

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--attempt', type=int, required=True)
    parser.add_argument('--test-filter', default='RealClientOrderingTests')
    args = parser.parse_args()
    if args.attempt < 1 or not os.path.ismount(VOLUME) or not OUTPUT.is_dir():
        raise SystemExit('Expected mounted SSD and existing first-run scratch')
    if Path(command('git', 'rev-parse', '--git-common-dir', cwd=ROOT)).resolve() != COMMON:
        raise SystemExit('Unexpected common Git root')
    command('git', 'merge-base', '--is-ancestor', '42c0e5deb9898847d77357971f34f2931ca10e3a', 'HEAD', cwd=ROOT)
    if command('git', 'symbolic-ref', '--short', 'HEAD', cwd=ROOT) != 'diagnostic/532-neon-natural-ordering-2026-10-26':
        raise SystemExit('Unexpected diagnostic branch')
    metadata_path = OUTPUT / f'incremental-{args.attempt}-metadata.json'
    if metadata_path.exists():
        raise SystemExit('Prior attempt exists; no automatic retry')
    package = ROOT / 'local-validation'
    scratch = OUTPUT / 'scratch'
    before = {str(p.relative_to(package)): hashlib.sha256(p.read_bytes()).hexdigest()
              for p in package.rglob('*.swift')}
    metadata = {'attempt': args.attempt, 'diagnosticHEAD': command('git', 'rev-parse', 'HEAD', cwd=ROOT),
                'base': '42c0e5deb9898847d77357971f34f2931ca10e3a',
                'sourceHashes': before, 'freeBefore': shutil.disk_usage(VOLUME).free,
                'supervision': 'direct owned Popen PID only; no group probes/signals'}
    status = 1
    try:
        build = ['swift', 'build', '--build-tests', '--jobs', '2', '--package-path', str(package),
                 '--scratch-path', str(scratch)]
        metadata['compile'] = owned_run(f'incremental-{args.attempt}-compile', build, 600)
        if metadata['compile']['exitStatus'] != 0 or metadata['compile']['reason']:
            raise SystemExit('Compile did not pass; tests not started')
        bundle = scratch / 'arm64-apple-macosx/debug/NeonOrderingDiagnosticValidationPackageTests.xctest/Contents/MacOS/NeonOrderingDiagnosticValidationPackageTests'
        helper = '/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/libexec/swift/pm/swiftpm-testing-helper'
        tests = [helper, '--test-bundle-path', str(bundle), '--testing-library', 'swift-testing',
                 '--filter', args.test_filter]
        frameworks = '/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/Library/Frameworks'
        if not (Path(frameworks) / 'Testing.framework/Versions/A/Testing').is_file():
            raise SystemExit('Installed Xcode Testing.framework is absent; no fallback')
        environment = dict(os.environ, DYLD_FRAMEWORK_PATH=frameworks)
        metadata['testFrameworkPath'] = frameworks
        metadata['tests'] = owned_run(f'incremental-{args.attempt}-focused-tests', tests, 60, environment=environment)
        test_log = (OUTPUT / f'incremental-{args.attempt}-focused-tests.log').read_text(errors='replace')
        metadata['suiteObserved'] = 'Suite RealClientOrderingTests started' in test_log
        status = 0 if metadata['tests']['exitStatus'] == 0 and not metadata['tests']['reason'] and metadata['suiteObserved'] else 1
    finally:
        metadata['freeAfter'] = shutil.disk_usage(VOLUME).free
        metadata['sourceHashesAfter'] = {str(p.relative_to(package)): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in package.rglob('*.swift')}
        metadata_path.write_text(json.dumps(metadata, indent=2) + '\n')
    raise SystemExit(status)

if __name__ == '__main__':
    main()
