#!/bin/bash
# Phase 1+2: per variant, Debug and Release builds plus NeonReplacementEdit{,Strict}Tests. Strictly sequential.
T=$(cd "$(dirname "$0")" && pwd); R=$T/run.sh
for v in stock A B AB; do
  [ -f $T/logs/build-$v-debug.log ] && grep -q '^# rc=0' $T/logs/build-$v-debug.log || $R $v build-$v-debug -- build --build-tests
  $R $v neon-$v-debug -- test --skip-build --no-parallel --filter NeonReplacementEdit
  # Debug opt-in of the widened test (aborts the host on stock per the shipped doc comment)
  $R $v neon-$v-debug-widened MACDOWN_STRICT_WIDENED_DEBUG=1 -- test --skip-build --no-parallel --filter NeonReplacementEditStrictTests/widenedBackgroundTyping
  $R $v build-$v-release -- build --build-tests -c release -Xswiftc -enable-testing
  $R $v neon-$v-release -- test --skip-build -c release -Xswiftc -enable-testing --no-parallel --filter NeonReplacementEdit
done
echo PHASE12-DONE
