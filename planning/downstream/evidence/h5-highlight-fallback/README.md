# H5 size-based highlighting fallback: Release benchmarks

- **Source:** `2576414c` (`highlight-fallback` after merging `integration-final` `f2a08fde`). Only docs and evidence were added afterwards; no source changed.
- **Machine:** Apple M3 Pro (11 cores, 18 GB), macOS 26.5.1 (25F80), Xcode 26.6, Swift 6.3.3.
- **Dependencies:** Neon `484d6fb9`, SwiftTreeSitter / SwiftTreeSitterLayer `cbe31cb3`, vendored `TreeSitterMarkdown`.
- **Quiet machine:** each invocation started only when no other `swift-test` / `xctest` / `xcodebuild` / `swift-build` process was running. A watcher sampled every 5 s for build or test processes from other checkouts and found none during any run, so every run was accepted on its first try.
- **Archive:** `release-benchmarks-2576414c.tar.gz` holds `fb-head.txt` (the commit) and one log per invocation:
  - `fb-h-reduced.log`: `HighlightFallbackBenchmarkTests/reducedModeOpenAndEdit`, using the shipped policy. It covers 5 workloads × {12, 32, 64, 128, 256, 1024, 4096} KB of UTF-8, measuring first open and 16 edits each at the start, middle and end.
  - `fb-h-cross.log`: typing one character at a time across the 8,192-unit cut-off.
  - `fb-h-paste.log`: pasting 256 KB, 1 MB and 4 MB into a highlighted document just below the cut-off, then typing.
  - `fb-h-pastefull.log`: the same 256 KB and 1 MB pastes with the fallback disabled, for comparison.
  - `fb-h-full-*.log`: full mode (Neon unbounded) for every workload at {4, 8, 12, 16, 24, 32, 64, 128, 256} KB, plus 1 MB for the ordinary and inline-dense workloads.
  - `fb-h-reconcile.log`: `InlineResolutionReconciliationTests` (the `LanguageLayer` level).
- **Commands:** see the doc comments of the test files named above. The base command is `swift test -c release -Xswiftc -enable-testing --no-parallel --skip-build --filter …`, with the opt-in environment variable that each test file documents.
- **Units:** sizes are generated as UTF-8 bytes. The `utf16=` field gives the UTF-16 code-unit count, which is the unit the cut-off is defined in.
- **Metrics:** "stall" is the longest main-thread stall attributed to each edit. "settle" is the time until highlighting stopped changing, reported separately. In reduced mode, the paste log's "presentation cleared" figure includes the probe's 100 ms monitor warm-up.
