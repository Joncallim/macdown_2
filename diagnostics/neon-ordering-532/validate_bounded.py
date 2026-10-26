"""One local compile and focused execution, with disk, time and log caps."""
import os
from pathlib import Path
import selectors
import shutil
import signal
import subprocess
import sys
import time

root = Path(__file__).resolve().parent
scratch = Path('/tmp/neon-ordering-diagnostic-scratch-2026-10-26')
reserve = 8 * 1024**3
budget = 1536 * 1024**2
def run(stage, arguments, seconds, *, log_root=root, baseline_free=None,
        disk_budget=budget, prefix='', environment=None):
    before = shutil.disk_usage(log_root).free if baseline_free is None else baseline_free
    start = time.monotonic()
    log = log_root / (prefix + stage + '.log')
    if log.exists():
        raise SystemExit(f'Refusing to overwrite retained validation log: {log}')
    written = 0
    discarded = 0
    reason = None
    with log.open('wb') as output:
        process = subprocess.Popen(arguments, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                   start_new_session=True, env=environment)
        group = process.pid  # start_new_session gives this command its own group.
        print(f'{stage}: pid={process.pid} pgid={group} argv={arguments}', flush=True)
        selector = selectors.DefaultSelector()
        os.set_blocking(process.stdout.fileno(), False)
        selector.register(process.stdout, selectors.EVENT_READ)
        exited_at = None
        term_at = None
        kill_sent = False

        def group_alive():
            try:
                os.killpg(group, 0)
                return True
            except ProcessLookupError:
                return False

        def send_group(sig):
            try:
                os.killpg(group, sig)
            except ProcessLookupError:
                pass

        try:
            while True:
                now = time.monotonic()
                code = process.poll()
                if code is not None and exited_at is None:
                    exited_at = now
                pipes_open = bool(selector.get_map())
                alive = group_alive()
                if code is not None and not pipes_open and not alive:
                    break

                if term_at is None:
                    free = shutil.disk_usage(log_root).free
                    if free < reserve or before - free > disk_budget or now - start >= seconds:
                        reason = f'bounded stop: free={free}, elapsed={now-start:.1f}s'
                    elif discarded:
                        reason = 'log cap exceeded'
                    elif exited_at is not None and now - exited_at >= 1:
                        reason = 'direct child exited but descendants or output pipe remain'
                    if reason is not None:
                        term_at = now
                        send_group(signal.SIGTERM)

                # These deadlines depend on the owned process group, never on
                # whether its original parent PID is still alive.
                if term_at is not None:
                    if not kill_sent and now >= term_at + 5:
                        send_group(signal.SIGKILL)
                        kill_sent = True
                    if now >= term_at + 7:
                        # A descendant that escaped the group may retain the
                        # pipe. Stop draining at a fixed deadline; do not wait
                        # indefinitely for EOF or signal unrelated groups.
                        if pipes_open:
                            selector.unregister(process.stdout)
                        break

                if pipes_open:
                    for key, _ in selector.select(timeout=0.1):
                        try:
                            data = os.read(key.fileobj.fileno(), 65536)
                        except BlockingIOError:
                            continue
                        if not data:
                            selector.unregister(key.fileobj)
                            continue
                        keep = data[:max(0, 1024**2 - written)]
                        output.write(keep)
                        written += len(keep)
                        discarded += len(data) - len(keep)
                else:
                    time.sleep(0.1)
        except BaseException:
            # The supervisor itself being interrupted must not leave its
            # disposable group running. Cleanup is independently bounded.
            send_group(signal.SIGTERM)
            cleanup_deadline = time.monotonic() + 5
            while group_alive() and time.monotonic() < cleanup_deadline:
                process.poll()
                time.sleep(0.1)
            if group_alive():
                send_group(signal.SIGKILL)
            raise
        finally:
            selector.close()
            process.stdout.close()
        try:
            code = process.wait(timeout=1)
        except subprocess.TimeoutExpired:
            reason = (reason or 'cleanup') + '; direct child unreaped after KILL deadline'
            code = 1
    print(f'{stage}: exit={code} elapsed={time.monotonic()-start:.1f}s discarded_log_bytes={discarded} reason={reason}', flush=True)
    if code or reason or discarded:
        raise SystemExit(code if code > 0 else 1)

def main():
    before = shutil.disk_usage(root).free
    if before - budget < reserve:
        raise SystemExit('Insufficient headroom for budget plus 8 GiB reserve')
    attempt_args = [argument for argument in sys.argv if argument.startswith('--approved-incremental=')]
    attempt = attempt_args[0].split('=', 1)[1] if attempt_args else None
    if attempt is not None and (not attempt.isdigit() or int(attempt) < 2):
        raise SystemExit('Invalid incremental attempt identifier')
    incremental = '--approved-incremental-1' in sys.argv or attempt is not None
    if scratch.exists() and '--resume-sandbox-failure' not in sys.argv and not incremental:
        raise SystemExit('Scratch already exists; inspect before a separately reviewed retry')
    prefix = f'incremental-{attempt}-' if attempt else ('incremental-1-' if incremental else '')
    print(f'BEFORE_FREE_BYTES={before}', flush=True)
    common = ['--package-path', str(root / 'validation'), '--scratch-path', str(scratch)]
    try:
        run('compile', ['swift', 'build', '--build-tests', '--jobs', '2'] + common,
            600, prefix=prefix, baseline_free=before)
        run('focused-tests', ['swift', 'test', '--skip-build', '--no-parallel', '--filter',
            'OrderingDiagnosticsTests'] + common, 60, prefix=prefix, baseline_free=before)
    finally:
        after = shutil.disk_usage(root).free
        print(f'AFTER_FREE_BYTES={after} DELTA_FREE_BYTES={after-before}', flush=True)

if __name__ == '__main__':
    main()
