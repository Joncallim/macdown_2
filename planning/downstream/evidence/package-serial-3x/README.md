# Package suite, three consecutive serial runs (unchanged source)

- **Source:** `45d7966f5f9e0d3194a50c80778243f1b865ba14` (master after #451; includes the fixes #423–#451 from the post-fix review rounds). The evidence files were added on top afterwards (no source, test or dependency change). Clean tree before the runs, no local modifications.
- **Command (each run):** `cd MacDown2/Packages/MacDownKit && swift test --no-parallel --force-resolved-versions` (the CI configuration). **No test was skipped or filtered**, WebKit-hosted suites included.
- **Dependency lock:** `Package.resolved` sha256 `9c7c1835b89d1248bd156e1caa45c7691098b36ef1aabea35a8974b5c15f8977`.
- **Host:** macOS 26.5.1, arm64, Apple Swift 6.3.3 (swiftlang-6.3.3.1.3), swift-driver 1.148.6, Xcode 26.6. Debug build, local (not CI).
- **Result:** run 1: 2488 tests / 326 suites passed (152.3 s, exit 0); run 2: 2488 / 326 passed (145.2 s, exit 0); run 3: 2488 / 326 passed (150.8 s, exit 0). No failed, skipped or retried test.
- **Raw artifacts:** `run1.log.gz` … `run3.log.gz` (full stdout/stderr).

## History this record supersedes
Replaces the set on `bb2775c1` (2487 tests), invalidated by #451 (+1 package test). The package suite is ~30 s slower than before #449 because each recovery-ledger write now really flushes. Earlier stalls on this host were traced to AppKit window-transition animations in test windows (#155, fixed by #421).

## Limits
- Debug configuration, one host and OS build; a reproducibility check, not proof of absence of flakes. App-target tests and Release performance tests are separate.
- Invalidated by any later source, dependency or toolchain change.
