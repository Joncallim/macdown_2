# App-target tests (MacDown2Tests), three consecutive serial runs

- **Source:** `cec1d28e3cc8976221f6e85b54cf2edaf333f426` (master after #468; evidence files added afterwards, no source change). Clean tree.
- **Command (each run):** `xcodegen generate`, `scripts/pin-xcode-package-versions.sh`, then `xcodebuild -project MacDown2.xcodeproj -scheme MacDown2 -destination 'platform=macOS' -onlyUsePackageVersionsFromResolvedFile -enableCodeCoverage NO -parallel-testing-enabled NO -only-testing:MacDown2Tests test` (the CI configuration for the non-UI app-target tests). Run from `MacDown2/`.
- **Dependency lock:** `Package.resolved` sha256 `9c7c1835b89d1248bd156e1caa45c7691098b36ef1aabea35a8974b5c15f8977`.
- **Host:** macOS 26.5.1, arm64, Apple Swift 6.3.3, Xcode 26.6. Debug build, local (not CI).
- **Result:** run 1: 376 tests / 80 suites passed (141.7 s, TEST SUCCEEDED, exit 0); run 2: 376 / 80 passed (138.8 s, exit 0); run 3: 376 / 80 passed (153.3 s, exit 0). No failed, skipped or retried test.
- **Raw artifacts:** `run1.log.gz` … `run3.log.gz` (xcodebuild output with known system-service noise lines — linkd/ViewBridge/accessibility/pboard/RBS — removed; test result lines untouched).

## Limits
- `MacDown2UITests` (native UI tests) are not run here and not run by CI; see `../ui-native-run/` for the one native run (33/33).
- Debug only; one host/OS build; not proof of absence of flakes. Replaces the set on `d1d8d4e8` (and the interim set on `b848deaa`), invalidated by #468 (+1 package test, +6 app tests, product changes in the window/close/find/first-run code).
