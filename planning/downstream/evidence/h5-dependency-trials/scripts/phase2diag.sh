#!/bin/bash
T=$(cd "$(dirname "$0")" && pwd); R=$T/run.sh
for v in stock A B AB; do
  cp $T/NeonReplacementEditStrictTests.swift $T/pkg/$v/MacDownKit/Tests/HighlightingTests/
  $R $v build2-$v-debug -- build --build-tests
  $R $v strict2-$v-debug -- test --skip-build --no-parallel --filter NeonReplacementEditStrictTests
  $R $v build2-$v-release -- build --build-tests -c release -Xswiftc -enable-testing
  $R $v strict2-$v-release -- test --skip-build -c release -Xswiftc -enable-testing --no-parallel --filter NeonReplacementEditStrictTests
done
echo DIAG-DONE
