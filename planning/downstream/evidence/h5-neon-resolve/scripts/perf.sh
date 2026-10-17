#!/bin/bash
# Stage C2 Release benchmarks, interleaved base/final (ABBA). C must be set.
cd $C; cp run.sh .run-p.sh
F="MACDOWN_HIGHLIGHT_BUDGET_FIXTURES=ordinary,inlineDense,longLines,unicode"
small() { ./.run-p.sh $1 release perf-small-$2 HighlightBudgetBenchmarkTests MACDOWN_HIGHLIGHT_BUDGET_BENCH=1 MACDOWN_HIGHLIGHT_BUDGET_KB=1,2,4,6,8 $F > /dev/null 2>&1; }
shipped() { ./.run-p.sh $1 release perf-shipped-$2 HighlightBudgetBenchmarkTests MACDOWN_HIGHLIGHT_BUDGET_BENCH=1 MACDOWN_HIGHLIGHT_BUDGET_POLICY=shipped MACDOWN_HIGHLIGHT_BUDGET_KB=1,2,4,6,8,16,32 $F > /dev/null 2>&1; }
large() { ./.run-p.sh $1 release perf-large-$2 HighlightBudgetBenchmarkTests MACDOWN_HIGHLIGHT_BUDGET_BENCH=1 MACDOWN_HIGHLIGHT_BUDGET_KB=16,32,64,256 $F > /dev/null 2>&1; }
keys() { ./.run-p.sh $1 release perf-keys-$2 KeystrokeStallBenchmarkTests MACDOWN_KEYSTROKE_BENCH=1 MACDOWN_KEYSTROKE_BENCH_KB=1,2,4,8,64,256 > /dev/null 2>&1; }
small base 1; small final 1; small final 2; small base 2
shipped base 1; shipped final 1; shipped final 2; shipped base 2
keys base 1; keys final 1; keys final 2; keys base 2
large base 1; large final 1; large final 2; large base 2
# cost of the resolve fix and of its alternatives (same binary, diag toggles; STS resolve-set behaviour on)
A="MACDOWN_HIGHLIGHT_BUDGET_BENCH=1 MACDOWN_HIGHLIGHT_BUDGET_KB=4,8,32,64 MACDOWN_HIGHLIGHT_BUDGET_FIXTURES=ordinary,inlineDense STS_EXPAND=1 STS_DROP_STALE=1 STS_SKIP_SAME=1"
for pass in 1 2; do for mode in off span all edited; do
  NEON_BRANCH=c2-diag ./.run-p.sh c2 release perf-alt-$mode-$pass HighlightBudgetBenchmarkTests $A NEON_RESOLVE=$mode > /dev/null 2>&1
done; done
for mode in off span all; do
  ./.run-p.sh c2 release perf-altkeys-$mode KeystrokeStallBenchmarkTests MACDOWN_KEYSTROKE_BENCH=1 MACDOWN_KEYSTROKE_BENCH_KB=8,64 STS_EXPAND=1 STS_DROP_STALE=1 STS_SKIP_SAME=1 NEON_RESOLVE=$mode > /dev/null 2>&1
done
# skip-same off (the resolve fix without the reparse skip) for the record
./.run-p.sh c2 release perf-alt-noskip-1 HighlightBudgetBenchmarkTests $A NEON_RESOLVE=span STS_SKIP_SAME=0 > /dev/null 2>&1
echo PERFDONE
