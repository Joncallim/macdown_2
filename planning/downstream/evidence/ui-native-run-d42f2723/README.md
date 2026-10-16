# Native UI run on the combined integration head

- **Head:** `d42f27233efc78c3cd2aa47c7900b5aad1e75503` (`integration-final`), clean worktree.
- **Result:** `-only-testing:MacDown2UITests`: 37 tests, 0 failures, 319.7 s; `** TEST SUCCEEDED **`.
- **Command:** from `MacDown2/`, `scripts/pin-xcode-package-versions.sh`, then `xcodebuild -project MacDown2.xcodeproj -scheme MacDown2 -destination 'platform=macOS' -onlyUsePackageVersionsFromResolvedFile -enableCodeCoverage NO -parallel-testing-enabled NO -only-testing:MacDown2UITests test`, on the user's Mac (CORTANA, macOS 26.5.1, Xcode 26.6) with the screen free.
- **Not covered:** a native CJK input-method engine (dead-key composition only), Release-performance suites on this head.
