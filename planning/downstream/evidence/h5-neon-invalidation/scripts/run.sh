#!/bin/bash
# Stage C1 runner (scratch only). C = stageC1 dir. deps/c1 = SwiftTreeSitter dcdd9465 (B1+B2) + tree-sitter 0.25.10
# (copies of stage2 deps/B) + Neon git clone with branches c1-stock (484d6fb9), c1-invalidation-buffer (the patch),
# c1-diag-toggles (patch + env toggles C1_STOCK_BUFFER=1 / DIAG_NEON_FIX=1), and task-2 branches.
# pkg = rsync of dep-trial MacDown2/Packages (Package.swift picks up deps/c1/Neon as a path dependency).
# usage: run.sh <debug|release> <neon-branch> <tag> <filter> [ENV=VALUE ...]
set -uo pipefail
C=${C:?}; config=$1; branch=$2; tag=$3; filter=$4; shift 4
while pgrep -q -f "xcodebuild|swift-build|swift-test|xctest" ; do sleep 20; done   # one heavy job at a time
git -C $C/deps/c1/Neon checkout -q "$branch" || exit 1
rsync -a --exclude .build --exclude .swiftpm /Users/jonathanlim/GitHub/macdown_2-deptrial/MacDown2/Packages/ $C/pkg/   # no --delete: keeps the strict-test copy
cd $C/pkg/MacDownKit
flags=(-c $config); [ $config = release ] && flags+=(-Xswiftc -enable-testing)
MACDOWN_DEP_TRIAL_ROOT=$C/deps/c1 swift build "${flags[@]}" --build-tests > $C/logs/build-$config-$branch.log 2>&1 || { tail -20 $C/logs/build-$config-$branch.log; exit 1; }
log=$C/logs/$config-$tag.log
{ echo "# $(date -u +%FT%TZ) config=$config neon=$branch($(git -C $C/deps/c1/Neon rev-parse --short HEAD)) env=$* load=$(sysctl -n vm.loadavg)"
  env "$@" MACDOWN_DEP_TRIAL_ROOT=$C/deps/c1 swift test --skip-build "${flags[@]}" --no-parallel --filter "$filter" 2>&1; echo "# exit=$?"; } > $log
grep -E "H5-INV-SUMMARY|H5-STRICT test|Test run|exit=|Fatal|fatal error|location is greater" $log | cut -c1-300
grep -E "H5-INV case=[a-zA-Z]+ " $log | sed -E 's/ first=.*//; s/ edits=.*//'
