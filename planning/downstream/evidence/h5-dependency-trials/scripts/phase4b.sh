#!/bin/bash
T=$(cd "$(dirname "$0")" && pwd); R=$T/run.sh
REL="--skip-build -c release -Xswiftc -enable-testing --no-parallel"
for v in stock A B AB; do $R $v build3-$v-release -- build --build-tests -c release -Xswiftc -enable-testing; done
for v in stock A B AB; do
  $R $v bench-keystroke-$v MACDOWN_KEYSTROKE_BENCH=1 MACDOWN_KEYSTROKE_BENCH_KB=64,256 -- test $REL --filter KeystrokeStallBenchmarkTests
done
for v in stock A B AB; do
  $R $v bench-pastefull-$v MACDOWN_HIGHLIGHT_FALLBACK_BENCH=1 -- test $REL --filter HighlightFallbackBenchmarkTests/pasteWithoutTheFallback
done
echo PHASE4B-DONE
