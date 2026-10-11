# App-target tests (MacDown2Tests), three consecutive serial runs

- **Source:** `2861e1a42b88f5fbb5823824a796630ef487be95` (master after #421; evidence files added afterwards, no source change). Clean tree.
- **Command (each run):** `xcodegen generate`, `scripts/pin-xcode-package-versions.sh`, then `xcodebuild -project MacDown2.xcodeproj -scheme MacDown2 -destination 'platform=macOS' -onlyUsePackageVersionsFromResolvedFile -enableCodeCoverage NO -parallel-testing-enabled NO -only-testing:MacDown2Tests test` (the CI configuration for the non-UI app-target tests).
- **Dependency lock:** `Package.resolved` sha256 `9c7c1835b89d1248bd156e1caa45c7691098b36ef1aabea35a8974b5c15f8977`.
- **Host:** macOS 26.5.1 (25F80), arm64, SDK 26.5, swift-driver version: 1.148.6 Apple Swift version 6.3.3 (swiftlang-6.3, Xcode 26.6. Debug build, local (not CI).
- **Result:** run 1: 363 tests / 74 suites passed (112.4 s, TEST SUCCEEDED, exit 0); run 2: 363 / 74 passed (107.0 s, exit 0); run 3: 363 / 74 passed (112.4 s, exit 0). No failed, skipped or retried test.
- **Raw artifacts:** `run1.log.gz` … `run3.log.gz` (xcodebuild output with known system-service noise lines — linkd/ViewBridge/accessibility/pboard/RBS — removed; test result lines untouched).

## Limits
- `MacDown2UITests` (native UI tests) are **not** run here and are not run by CI; no native UI evidence exists yet.
- Debug only; one host/OS build; not proof of absence of flakes. Replaces the earlier set on `3f1ce29d`.
- Invalidated by any later source, dependency or toolchain change.
