#!/bin/bash
# Phase 3 (Debug full suite, AB and stock) then phase 4 (Release benchmarks). Strictly sequential.
# The scratch-only NeonReplacementEditStrictTests is skipped in the full suite (reported separately).
T=$(cd "$(dirname "$0")" && pwd); R=$T/run.sh
REL="--skip-build -c release -Xswiftc -enable-testing --no-parallel"
for v in AB stock; do
  $R $v suite-$v-debug -- test --skip-build --no-parallel --skip NeonReplacementEditStrictTests
done
FIX=ordinary,inlineDense,longLines,unicode
for pass in 1 2; do
  [ $pass = 1 ] && order="stock A B AB" || order="AB B A stock"
  for v in $order; do
    $R $v bench-budget-small-$v-p$pass MACDOWN_HIGHLIGHT_BUDGET_BENCH=1 MACDOWN_HIGHLIGHT_BUDGET_KB=8,12,16,24,32,64,256 MACDOWN_HIGHLIGHT_BUDGET_FIXTURES=$FIX -- test $REL --filter HighlightBudgetBenchmarkTests
  done
done
for v in stock A B AB; do
  $R $v bench-budget-1m-$v MACDOWN_HIGHLIGHT_BUDGET_BENCH=1 MACDOWN_HIGHLIGHT_BUDGET_KB=1024 MACDOWN_HIGHLIGHT_BUDGET_FIXTURES=$FIX -- test $REL --filter HighlightBudgetBenchmarkTests
done
for v in stock A B AB; do
  $R $v bench-keystroke-$v MACDOWN_KEYSTROKE_BENCH=1 MACDOWN_KEYSTROKE_BENCH_KB=64,256 -- test $REL --filter KeystrokeStallBenchmarkTests
  $R $v bench-pastefull-$v MACDOWN_HIGHLIGHT_FALLBACK_BENCH=1 -- test $REL --filter HighlightFallbackBenchmarkTests/pasteWithoutTheFallback
done
echo PHASE34-DONE
