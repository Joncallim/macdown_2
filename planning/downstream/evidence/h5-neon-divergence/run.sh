#!/bin/bash
# run.sh: setup + run of the diag (scratch only). S = the stage-2 scratch dir (h5-dependency-trials/scripts/setup.sh layout).
# deps/diag = deps/B (SwiftTreeSitter B1+B2, tree-sitter 0.25.10) + Neon 484d6fb9, with the two instrumentation diffs applied;
# pkg/diag = clone of pkg/B with package-swift.diff (Neon as a path dependency) and NeonDivergenceDiagTests.swift added.
# Toggles: DIAG_NEON_FIX=1 (edit invalidations also invalidate Neon's sublayer validator), DIAG_NO_B1=1 (stock range merge).
set -uo pipefail
S=${S:?}; cd $S/pkg/diag/MacDownKit
rm -rf .build/arm64-apple-macosx/*/ModuleCache   # cloned caches are path-bound
MACDOWN_DEP_TRIAL_ROOT=$S/deps/diag swift build -c release -Xswiftc -enable-testing --build-tests
run() { tag=$1; shift; for c in typeThenDelete replace600 replacePlain widened; do
  env "$@" DIAG_TRACE=$S/diaglogs/trace-$c-$tag.log MACDOWN_DEP_TRIAL_ROOT=$S/deps/diag \
    swift test --skip-build -c release -Xswiftc -enable-testing --no-parallel \
    --filter "NeonDivergenceDiagTests/$c" > $S/diaglogs/run-$c-$tag.log 2>&1; done; }
run fix0 DIAG_NEON_FIX=0; run fix1 DIAG_NEON_FIX=1; run fix1-noB1 DIAG_NEON_FIX=1 DIAG_NO_B1=1
