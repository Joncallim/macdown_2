# Package suite, three consecutive serial runs (unchanged source)

- **Source:** `b848deaa766e639e1d9d479046bde5c06ced1756` (master after #465; includes the fixes #423–#464 from the post-fix review rounds and the #203 tripwire test (#465)). The evidence files were added on top afterwards (no source, test or dependency change). Clean tree before the runs, no local modifications.
- **Command (each run):** `cd MacDown2/Packages/MacDownKit && swift test --no-parallel --force-resolved-versions` (the CI configuration). **No test was skipped or filtered**, WebKit-hosted suites included.
- **Dependency lock:** `Package.resolved` sha256 `9c7c1835b89d1248bd156e1caa45c7691098b36ef1aabea35a8974b5c15f8977`.
- **Host:** macOS 26.5.1, arm64, Apple Swift 6.3.3 (swiftlang-6.3.3.1.3), swift-driver 1.148.6, Xcode 26.6. Debug build, local (not CI).
- **Result:** run 1: 2493 tests / 327 suites passed (139.9 s, exit 0); run 2: 2493 / 327 passed (131.3 s, exit 0); run 3: 2493 / 327 passed (137.4 s, exit 0). No failed, skipped or retried test.
- **Raw artifacts:** `run1.log.gz` … `run3.log.gz` (full stdout/stderr).

## History this record supersedes
Replaces the set on `d1d8d4e8` (2489 package / 370 app tests), invalidated by #464 (+3 package tests) and #465 (+1 package test).

## Limits
- Debug configuration, one host and OS build; a reproducibility check, not proof of absence of flakes. App-target tests and Release performance tests are separate.
- Invalidated by any later source, dependency or toolchain change.
