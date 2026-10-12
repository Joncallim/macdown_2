# Package suite, three consecutive serial runs (unchanged source)

- **Source:** `d2b7e2429af5b980b2d0103a48969e13a73c2ca4` (master after #426; includes the post-fix review fixes #423 probe-loop, #424 Save As tab switch, #425 Find freshness). The evidence files were added on top afterwards (no source, test or dependency change). Clean tree before the runs, no local modifications.
- **Command (each run):** `cd MacDown2/Packages/MacDownKit && swift test --no-parallel --force-resolved-versions` (the CI configuration). **No test was skipped or filtered**, WebKit-hosted suites included.
- **Dependency lock:** `Package.resolved` sha256 `9c7c1835b89d1248bd156e1caa45c7691098b36ef1aabea35a8974b5c15f8977`.
- **Host:** macOS 26.5.1, arm64, Apple Swift 6.3.3 (swiftlang-6.3.3.1.3), swift-driver 1.148.6, Xcode 26.6. Debug build, local (not CI).
- **Result:** run 1: 2465 tests / 317 suites passed (113.8 s, exit 0); run 2: 2465 / 317 passed (109.3 s, exit 0); run 3: 2465 / 317 passed (110.7 s, exit 0). No failed, skipped or retried test.
- **Raw artifacts:** `run1.log.gz` … `run3.log.gz` (full stdout/stderr).

## History this record supersedes
Replaces the set on `2861e1a4` (2462 tests), invalidated by #423–#425 (+3 regression tests). Earlier stalls on this host were traced to AppKit window-transition animations in test windows (#155, fixed by #421).

## Limits
- Debug configuration, one host and OS build; a reproducibility check, not proof of absence of flakes. App-target tests and Release performance tests are separate.
- Invalidated by any later source, dependency or toolchain change.
