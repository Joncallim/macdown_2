#!/bin/bash
# run.sh <variant> <logname> [ENV=VAL ...] -- <swift args...>
# Runs one swift command in pkg/<variant>/MacDownKit with MACDOWN_DEP_TRIAL_ROOT=deps/<variant>,
# after waiting until no other build/test process is running. Logs to logs/<logname>.log.
set -uo pipefail
T=$(cd "$(dirname "$0")" && pwd); v=$1; name=$2; shift 2
envs=(); while [ "$1" != "--" ]; do envs+=("$1"); shift; done; shift
log=$T/logs/$name.log
busy() { pgrep -f "swift-build|swift-test|xctest|xcodebuild|swiftpm-testing-helper" >/dev/null; }
n=0; while busy; do sleep 10; n=$((n+1)); done
{
  echo "# variant=$v $(cat $T/deps/$v/VARIANT | tr '\n' ' ')"
  echo "# waited_for_quiet=$((n*10))s start=$(date -u +%FT%TZ) load=$(sysctl -n vm.loadavg)"
  echo "# cmd: ${envs[*]+"${envs[*]}"} MACDOWN_DEP_TRIAL_ROOT=deps/$v swift $*"
} > "$log"
cd $T/pkg/$v/MacDownKit
start=$(date +%s)
env ${envs[@]+"${envs[@]}"} MACDOWN_DEP_TRIAL_ROOT=$T/deps/$v swift "$@" >> "$log" 2>&1
rc=$?
echo "# rc=$rc elapsed=$(( $(date +%s) - start ))s end=$(date -u +%FT%TZ)" >> "$log"
echo "$name rc=$rc $(( $(date +%s) - start ))s"
exit $rc
