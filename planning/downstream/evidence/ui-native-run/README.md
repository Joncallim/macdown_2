# MacDown2UITests (native XCUITest), one full run

- **Source:** `268bee5f588dc8c8a19eb3b7009040f8c182585a` (master after #470). The evidence files were added afterwards (no source change). Clean tree.
- **Command:** `xcodegen generate`, `scripts/pin-xcode-package-versions.sh`, then `xcodebuild -project MacDown2.xcodeproj -scheme MacDown2 -destination 'platform=macOS' -onlyUsePackageVersionsFromResolvedFile -enableCodeCoverage NO -parallel-testing-enabled NO -only-testing:MacDown2UITests test`, run from `MacDown2/` in an interactive login session (the target drives real keyboard, mouse and focus; CI deliberately excludes it).
- **Result:** 37 tests, 0 failures, 330 s, `** TEST SUCCEEDED **`.
- **Host:** macOS 26.5.1, arm64, Xcode 26.6, Debug build.
- **Raw artifact:** `run1.log.gz` (xcodebuild output; system-service noise lines removed).

## History
The target grew from 33 to 37 tests: #470 added `testCommandFOpensTheFindBar` and three native dead-key composition tests (`DeadKeyCompositionUITests`). An earlier native run on `cec1d28e` passed 33/33.

This was the **first ever** execution of this target. The first run (on `b848deaa`) had 25 passing and **8 failing** tests; six of them were product defects (fixed in #468, one of them a regression from #448), the rest stale tests. Those failures are not retained as evidence; they are described in `planning/CLOSURE_REGISTER.md`.

## Limits
- One run, one host, Debug. Not a statement about flakiness across runs.
- 33 UI tests cover navigation, tabs, external-file changes, preview, first-run, folder browsing and editing assists; they cover dead-key composition (US/ABC layout) but not a CJK input-method engine, print/export panels, or Quick Look.
