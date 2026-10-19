#!/usr/bin/env python3
"""One disposable owned-child crash; never changes host crash-reporting preferences."""
import argparse
import json
from pathlib import Path
import subprocess
import sys

from capture import observed_command

parser = argparse.ArgumentParser()
parser.add_argument('--output', required=True, type=Path)
args = parser.parse_args()
output = args.output.resolve()
output.mkdir(parents=True, exist_ok=False)
source = output / 'probe.c'
source.write_text('''#include <sys/resource.h>
#include <unistd.h>
__attribute__((noinline)) static void synthetic_fault(void) {
    volatile int *pointer = (int *)0;
    *pointer = 42;
}
int main(void) {
    struct rlimit limit = {0, 0};
    setrlimit(RLIMIT_CORE, &limit);
    usleep(800000);
    synthetic_fault();
    return 0;
}
''')
binary = output / 'MostlyTextCrashCaptureProbe'
subprocess.run(['xcrun', 'clang', '-g', '-O0', str(source), '-o', str(binary)], check=True)
result = observed_command([str(binary)], output, lambda: None,
                          [Path.home() / 'Library/Logs/DiagnosticReports', Path('/Library/Logs/DiagnosticReports')])
result['argv'] = [binary.name]
(output / 'run.json').write_text(json.dumps(result, indent=2, sort_keys=True) + '\n')
print('Probe return:', result['return_code'], 'capture:', result['capture']['outcome'], flush=True)
if result['return_code'] != -11 or result['shell_exit_code'] != 139 or result['observer_errors']:
    raise SystemExit('Synthetic process/observer validation failed; retained original result.')
if result['capture']['outcome'] != 'matched':
    raise SystemExit('No attributable synthetic crash report; capture availability remains unverified.')
symbols = [f.get('verified_binary_symbol', '')
           for report in result['capture']['reports'] for f in report['frames']]
if not any('synthetic_fault' in symbol for symbol in symbols):
    raise SystemExit('Owned synthetic stack was not symbolicated; retained partial evidence.')
print('Owned synthetic SIGSEGV report and exact-binary stack verified.')
