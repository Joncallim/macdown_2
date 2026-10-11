# App-target tests (MacDown2Tests), three consecutive serial runs

- **Source:** `78294119cdac32b0bb1528f3272977edf0965887` (master after #409). The first run started one commit earlier (`3f1ce29d`) and the two later runs on `78294119cdac32b0bb1528f3272977edf0965887`; the only difference between them is the evidence files added by #409 (no source, test or dependency change).
- **Command (each run):** `xcodegen generate`, `scripts/pin-xcode-package-versions.sh`, then `xcodebuild -project MacDown2.xcodeproj -scheme MacDown2 -destination 'platform=macOS' -onlyUsePackageVersionsFromResolvedFile -enableCodeCoverage NO -parallel-testing-enabled NO -only-testing:MacDown2Tests test` (the CI configuration for the non-UI app-target tests).
- **Dependency lock:** `Package.resolved` sha256 `9c7c1835b89d1248bd156e1caa45c7691098b36ef1aabea35a8974b5c15f8977`.
- **Host:** macOS 26.5.1 (25F80), arm64, SDK 26.5, Xcode 26.6. Debug build, local (not CI).
- **Result:** run 1: 361 tests / 74 suites passed (138.9 s, exit 0, TEST SUCCEEDED); run 2: 361 / 74 passed (144.7 s, exit 0); run 3: 361 / 74 passed (136.4 s, exit 0). No failed, skipped or retried test.
- **Raw artifacts:** `run1.log.gz` … `run3.log.gz` (xcodebuild output with the known system-service noise lines — linkd/ViewBridge/accessibility — removed; test result lines untouched).

## Limits
- `MacDown2UITests` (native UI tests) are **not** run here and are not run by CI; no native UI evidence exists yet.
- Debug only; one host/OS build; a reproducibility check, not proof of absence of flakes.
- Invalidated by any later source, dependency or toolchain change.
