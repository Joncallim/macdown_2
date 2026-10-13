# App-target tests (MacDown2Tests), three consecutive serial runs

- **Source:** `268bee5f588dc8c8a19eb3b7009040f8c182585a` (master after #470; evidence files added afterwards, no source change). Clean tree.
- **Command (each run):** `xcodegen generate`, `scripts/pin-xcode-package-versions.sh`, then `xcodebuild -project MacDown2.xcodeproj -scheme MacDown2 -destination 'platform=macOS' -onlyUsePackageVersionsFromResolvedFile -enableCodeCoverage NO -parallel-testing-enabled NO -only-testing:MacDown2Tests test` (the CI configuration for the non-UI app-target tests). Run from `MacDown2/`.
- **Dependency lock:** `Package.resolved` sha256 `9c7c1835b89d1248bd156e1caa45c7691098b36ef1aabea35a8974b5c15f8977`.
- **Host:** macOS 26.5.1, arm64, Apple Swift 6.3.3, Xcode 26.6. Debug build, local (not CI).
- **Result:** run 1: 376 tests / 80 suites passed (147.9 s, TEST SUCCEEDED, exit 0); run 2: 376 / 80 passed (147.4 s, exit 0); run 3: 376 / 80 passed (138.2 s, exit 0). No failed, skipped or retried test.
- **Raw artifacts:** `run1.log.gz` … `run3.log.gz` (xcodebuild output with known system-service noise lines — linkd/ViewBridge/accessibility/pboard/RBS — removed; test result lines untouched).

## Limits
- `MacDown2UITests` (native UI tests) are not run here and not run by CI; see `../ui-native-run/` for the one native run (33/33).
- Debug only; one host/OS build; not proof of absence of flakes. Replaces the sets on `d1d8d4e8`, `b848deaa` and `cec1d28e` (identical test counts to `cec1d28e`; the only change since is the ⌘F menu binding and UI tests).
