# App-target tests (MacDown2Tests), three consecutive serial runs

- **Source:** `c64da7146b0b839fa2fce580243f4220500fe758` (master after #440; evidence files added afterwards, no source change). Clean tree.
- **Command (each run):** `xcodegen generate`, `scripts/pin-xcode-package-versions.sh`, then `xcodebuild -project MacDown2.xcodeproj -scheme MacDown2 -destination 'platform=macOS' -onlyUsePackageVersionsFromResolvedFile -enableCodeCoverage NO -parallel-testing-enabled NO -only-testing:MacDown2Tests test` (the CI configuration for the non-UI app-target tests). Run from `MacDown2/`.
- **Dependency lock:** `Package.resolved` sha256 `9c7c1835b89d1248bd156e1caa45c7691098b36ef1aabea35a8974b5c15f8977`.
- **Host:** macOS 26.5.1, arm64, Apple Swift 6.3.3, Xcode 26.6. Debug build, local (not CI).
- **Result:** run 1: 364 tests / 75 suites passed (115.7 s, TEST SUCCEEDED, exit 0); run 2: 364 / 75 passed (143.1 s, exit 0); run 3: 364 / 75 passed (126.6 s, exit 0). No failed, skipped or retried test.
- **Raw artifacts:** `run1.log.gz` … `run3.log.gz` (xcodebuild output with known system-service noise lines — linkd/ViewBridge/accessibility/pboard/RBS — removed; test result lines untouched).

## Limits
- `MacDown2UITests` (native UI tests) are **not** run here and are not run by CI; no native UI evidence exists yet.
- Debug only; one host/OS build; not proof of absence of flakes. Replaces the set on `b17bcf15`.
