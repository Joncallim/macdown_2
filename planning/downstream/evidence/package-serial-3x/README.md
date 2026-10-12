# Package suite, three consecutive serial runs (unchanged source)

- **Source:** `6e146d8978d4de2d66da3ef6626177d85b502516` (master after #444; includes the fixes #423–#444 from the post-fix review rounds). The evidence files were added on top afterwards (no source, test or dependency change). Clean tree before the runs, no local modifications.
- **Command (each run):** `cd MacDown2/Packages/MacDownKit && swift test --no-parallel --force-resolved-versions` (the CI configuration). **No test was skipped or filtered**, WebKit-hosted suites included.
- **Dependency lock:** `Package.resolved` sha256 `9c7c1835b89d1248bd156e1caa45c7691098b36ef1aabea35a8974b5c15f8977`.
- **Host:** macOS 26.5.1, arm64, Apple Swift 6.3.3 (swiftlang-6.3.3.1.3), swift-driver 1.148.6, Xcode 26.6. Debug build, local (not CI).
- **Result:** run 1: 2482 tests / 323 suites passed (117.2 s, exit 0); run 2: 2482 / 323 passed (111.6 s, exit 0); run 3: 2482 / 323 passed (112.0 s, exit 0). No failed, skipped or retried test.
- **Raw artifacts:** `run1.log.gz` … `run3.log.gz` (full stdout/stderr).

## History this record supersedes
Replaces the set on `c64da714` (2479 tests), invalidated by #443–#444 (+3 package tests). Earlier stalls on this host were traced to AppKit window-transition animations in test windows (#155, fixed by #421).

## Limits
- Debug configuration, one host and OS build; a reproducibility check, not proof of absence of flakes. App-target tests and Release performance tests are separate.
- Invalidated by any later source, dependency or toolchain change.
