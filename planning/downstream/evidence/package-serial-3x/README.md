# Package suite, three consecutive serial runs (unchanged source)

- **Source:** `2861e1a42b88f5fbb5823824a796630ef487be95` (master after #421); the evidence files were added on top of it afterwards (no source, test or dependency change). Clean tree, no local modifications.
- **Command (each run):** `cd MacDown2/Packages/MacDownKit && swift test --no-parallel --force-resolved-versions` (the CI configuration). **No test was skipped or filtered**, WebKit-hosted suites included.
- **Dependency lock:** `Package.resolved` sha256 `9c7c1835b89d1248bd156e1caa45c7691098b36ef1aabea35a8974b5c15f8977`.
- **Host:** macOS 26.5.1 (25F80), arm64, SDK 26.5, swift-driver version: 1.148.6 Apple Swift version 6.3.3 (swiftlang-6.3. Debug build, local (not CI).
- **Result:** run 1: 2462 tests / 317 suites passed (100.4 s, exit 0); run 2: 2462 / 317 passed (98.1 s, exit 0); run 3: 2462 / 317 passed (97.8 s, exit 0). No failed, skipped or retried test.
- **Raw artifacts:** `run1.log.gz` … `run3.log.gz` (full stdout/stderr).

## History this record supersedes
These runs replace the earlier set on `3f1ce29d`, which predated #411–#421 and is invalidated for the final head. Between them, runs of the same suite stalled indefinitely on this host. Root cause (stack-sampled): AppKit window-transition animations created by test windows run as blocking `NSAnimation`s that never complete headlessly, each stranding a dispatch worker until libdispatch's 64-thread soft limit starved the process (#155; fix #421: `animationBehavior = .none` on test windows). With it, the previously stalling command completed on every attempt.

## Limits
- Debug configuration, one host and OS build; a reproducibility check, not proof of absence of flakes. App-target tests and Release performance tests are separate.
- Invalidated by any later source, dependency or toolchain change.
