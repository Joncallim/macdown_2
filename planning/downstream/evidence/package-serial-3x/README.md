# Package suite, three consecutive serial runs (unchanged source)

- **Source:** `3f1ce29d8be5deff802900f8b7b5357cb5181b98` (master after #408), clean tree, no local modifications.
- **Command (each run):** `cd MacDown2/Packages/MacDownKit && swift test --no-parallel --force-resolved-versions` (the CI configuration).
- **Dependency lock:** `Package.resolved` sha256 `9c7c1835b89d1248bd156e1caa45c7691098b36ef1aabea35a8974b5c15f8977`, enforced by `--force-resolved-versions`.
- **Host:** macOS 26.5.1 (25F80), arm64, SDK 26.5, swift-driver version: 1.148.6 Apple Swift version 6.3.3 (swiftlang-6.3.3.1.3 cla. Debug build. Idle machine at start of each run (load ≈ 3).
- **Result:** run 1: 2443 tests / 312 suites passed (113.9 s, exit 0); run 2: 2443 / 312 passed (117.3 s, exit 0); run 3: 2443 / 312 passed (114.1 s, exit 0). No failed, skipped or retried test in any run; no retry was used.
- **Raw artifacts:** `run1.log.gz` … `run3.log.gz` (full stdout/stderr).

## Limits
- Debug configuration, one host and OS build; Release performance tests and the app-target suite (`MacDown2Tests`, serial) are separate and not covered here.
- This is a reproducibility check, not statistical proof of absence of flakes. Earlier **parallel** runs of the same suite (not the CI configuration) failed 59 wall-clock-bound tests under load and a run stalled before #406; those runs are *not* part of this evidence and are described in the closure register.
- Invalidated by any later source, dependency or toolchain change.
