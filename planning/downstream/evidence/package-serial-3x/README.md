# Package suite, three consecutive serial runs (unchanged source)

- **Source:** `268bee5f588dc8c8a19eb3b7009040f8c182585a` (master after #470; includes the fixes #423–#464, the #203 tripwire (#465), the first native-UI-run fixes (#468) and the ⌘F binding (#470)). The evidence files were added on top afterwards (no source, test or dependency change). Clean tree before the runs, no local modifications.
- **Command (each run):** `cd MacDown2/Packages/MacDownKit && swift test --no-parallel --force-resolved-versions` (the CI configuration). **No test was skipped or filtered**, WebKit-hosted suites included.
- **Dependency lock:** `Package.resolved` sha256 `9c7c1835b89d1248bd156e1caa45c7691098b36ef1aabea35a8974b5c15f8977`.
- **Host:** macOS 26.5.1, arm64, Apple Swift 6.3.3 (swiftlang-6.3.3.1.3), swift-driver 1.148.6, Xcode 26.6. Debug build, local (not CI).
- **Result:** run 1: 2494 tests / 327 suites passed (148.7 s, exit 0); run 2: 2494 / 327 passed (148.2 s, exit 0); run 3: 2494 / 327 passed (151.7 s, exit 0). No failed, skipped or retried test.
- **Raw artifacts:** `run1.log.gz` … `run3.log.gz` (full stdout/stderr).

## History this record supersedes
Replaces the sets on `d1d8d4e8`, `b848deaa` and `cec1d28e` (identical test counts to `cec1d28e`; the only change since is the ⌘F menu binding and UI tests).

## Limits
- Debug configuration, one host and OS build; a reproducibility check, not proof of absence of flakes. App-target tests and Release performance tests are separate.
- Invalidated by any later source, dependency or toolchain change.
