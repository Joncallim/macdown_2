#!/bin/bash
# prof.sh <variant> <name> <sample_secs> [ENV=VAL ...]  (SCRATCH) runs H5ProfileHarnessTests once
# in Release and attaches `sample` (1 ms interval) when the harness writes `ready`.
set -uo pipefail
P=$(cd "$(dirname "$0")" && pwd); v=$1; if [ -d $P/pkg/$1 ]; then T=$P; else T=$P/../stage2; fi; name=$2; secs=$3; shift 3
out=$P/out/$name; rm -rf $out; mkdir -p $out
busy() { pgrep -f "swift-build|swift-test|xctest|xcodebuild|swiftpm-testing-helper" >/dev/null; }
n=0; while busy; do sleep 10; n=$((n+1)); done
{ echo "# variant=$v $(cat $T/deps/$v/VARIANT | tr '\n' ' ')"; echo "# waited=$((n*10))s start=$(date -u +%FT%TZ) load=$(sysctl -n vm.loadavg)"; echo "# env: $* sample_secs=$secs"; } > $out/run.log
cd $T/pkg/$v/MacDownKit
env "$@" H5PROF=1 H5PROF_DIR=$out MACDOWN_DEP_TRIAL_ROOT=$T/deps/$v swift test --skip-build -c release -Xswiftc -enable-testing --no-parallel --filter H5ProfileHarnessTests >> $out/run.log 2>&1 &
tp=$!
while [ ! -f $out/ready ] && kill -0 $tp 2>/dev/null; do sleep 0.2; done
if [ -f $out/ready ]; then pid=$(head -1 $out/ready); echo "# sampling pid=$pid $(ps -o comm= -p $pid)" >> $out/run.log
  if [ "${TOOL:-xctrace}" = none ]; then :; elif [ "${TOOL:-xctrace}" = sample ]; then sample $pid $secs 1 -mayDie -file $out/sample.txt > $out/sample.stdout 2>&1; else xcrun xctrace record --template "Time Profiler" --attach $pid --time-limit ${secs}s --output $out/trace.trace --no-prompt > $out/xctrace.stdout 2>&1; fi; fi
wait $tp; echo "# rc=$? end=$(date -u +%FT%TZ)" >> $out/run.log
grep -E "H5PROF|rc=|sampling|passed|failed" $out/run.log | tail -12
