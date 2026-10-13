# App-target tests (MacDown2Tests), three consecutive serial runs

- **Source:** `b848deaa766e639e1d9d479046bde5c06ced1756` (master after #465; evidence files added afterwards, no source change). Clean tree.
- **Command (each run):** `xcodegen generate`, `scripts/pin-xcode-package-versions.sh`, then `xcodebuild -project MacDown2.xcodeproj -scheme MacDown2 -destination 'platform=macOS' -onlyUsePackageVersionsFromResolvedFile -enableCodeCoverage NO -parallel-testing-enabled NO -only-testing:MacDown2Tests test` (the CI configuration for the non-UI app-target tests). Run from `MacDown2/`.
- **Dependency lock:** `Package.resolved` sha256 `9c7c1835b89d1248bd156e1caa45c7691098b36ef1aabea35a8974b5c15f8977`.
- **Host:** macOS 26.5.1, arm64, Apple Swift 6.3.3, Xcode 26.6. Debug build, local (not CI).
- **Result:** run 1: 370 tests / 78 suites passed (121.0 s, TEST SUCCEEDED, exit 0); run 2: 370 / 78 passed (113.6 s, exit 0); run 3: 370 / 78 passed (118.6 s, exit 0). No failed, skipped or retried test.
- **Raw artifacts:** `run1.log.gz` … `run3.log.gz` (xcodebuild output with known system-service noise lines — linkd/ViewBridge/accessibility/pboard/RBS — removed; test result lines untouched).

## Limits
- `MacDown2UITests` (native UI tests) are **not** run here and are not run by CI; no native UI evidence exists yet.
- Debug only; one host/OS build; not proof of absence of flakes. Replaces the set on `d1d8d4e8` (2489 package / 370 app tests), invalidated by #464 (+3 package tests) and #465 (+1 package test).
