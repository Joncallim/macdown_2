# App-target tests (MacDown2Tests), three consecutive serial runs

- **Source:** `304713ddb7708e71272c8f6847dcc509516f8018` (master after #454; evidence files added afterwards, no source change). Clean tree.
- **Command (each run):** `xcodegen generate`, `scripts/pin-xcode-package-versions.sh`, then `xcodebuild -project MacDown2.xcodeproj -scheme MacDown2 -destination 'platform=macOS' -onlyUsePackageVersionsFromResolvedFile -enableCodeCoverage NO -parallel-testing-enabled NO -only-testing:MacDown2Tests test` (the CI configuration for the non-UI app-target tests). Run from `MacDown2/`.
- **Dependency lock:** `Package.resolved` sha256 `9c7c1835b89d1248bd156e1caa45c7691098b36ef1aabea35a8974b5c15f8977`.
- **Host:** macOS 26.5.1, arm64, Apple Swift 6.3.3, Xcode 26.6. Debug build, local (not CI).
- **Result:** run 1: 366 tests / 76 suites passed (127.1 s, TEST SUCCEEDED, exit 0); run 2: 366 / 76 passed (120.5 s, exit 0); run 3: 366 / 76 passed (127.0 s, exit 0). No failed, skipped or retried test.
- **Raw artifacts:** `run1.log.gz` … `run3.log.gz` (xcodebuild output with known system-service noise lines — linkd/ViewBridge/accessibility/pboard/RBS — removed; test result lines untouched).

## Limits
- `MacDown2UITests` (native UI tests) are **not** run here and are not run by CI; no native UI evidence exists yet.
- Debug only; one host/OS build; not proof of absence of flakes. Replaces the set on `45d7966f`. A preceding attempt on `9f859e9c` failed run 3 once (`discardingADeletedDocumentRetiresItsRecoveryAndClosesTheWindow`); the flake was reproduced, root-caused and fixed in #454, and this set was taken on the fixed head.
