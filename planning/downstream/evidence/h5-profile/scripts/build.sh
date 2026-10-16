#!/bin/bash
# build.sh <variant>: Release build of h5prof/pkg/<v> against h5prof/deps/<v>, after waiting for quiet.
H=$(cd "$(dirname "$0")" && pwd); v=$1
while pgrep -f "swift-build|swift-test|xctest|xcodebuild|swiftpm-testing-helper" >/dev/null; do sleep 10; done
cd $H/pkg/$v/MacDownKit && MACDOWN_DEP_TRIAL_ROOT=$H/deps/$v swift build --build-tests -c release -Xswiftc -enable-testing > $H/logs/build-$v-release.log 2>&1
rc=$?; echo "build $v rc=$rc $(tail -1 $H/logs/build-$v-release.log)"; exit $rc
