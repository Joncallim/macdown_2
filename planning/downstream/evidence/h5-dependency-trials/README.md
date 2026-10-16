# H5 dependency-fix trials, stage 2 (branch `dep-trial` only; nothing adopted, nothing pushed, nothing sent upstream)

Stage 2 tested the stage-1 scratch patches in the real MacDownKit editor path (Neon + SwiftTreeSitterLayer + vendored TreeSitterMarkdown). **No variant fixes H5. No variant justifies moving or removing the 8,192-unit cut-off.**

## Setup

- **Machine:** Apple M3 Pro (11 cores, 18 GB), macOS 26.5.1 (25F80), Xcode 26.6 (17F113), Swift 6.3.3. Other desktop apps were open (WindowServer, a ChatGPT/Codex renderer). The 1-minute load average at the start of each run is in the header of its log. `run.sh` waited before every run until no other `swift-build`, `swift-test`, `xctest`, `xcodebuild` or testing-helper process was running. Every run started without waiting; the hosted CI run was remote.
- **Base:** `dep-trial` = `integration-final` `5ccfaf89`. Neon is `484d6fb9`.
- **Variants** (`scripts/VARIANTS.txt`). Each is a plain source copy built by `scripts/setup.sh` from the stage-1 branches. The patch files are in `patches/`.

  | variant | SwiftTreeSitter(+Layer) | tree-sitter |
  |---|---|---|
  | stock | `cbe31cb3` (pinned) | `da6fe9be` (0.25.10, pinned) |
  | A | `cbe31cb3` | `091c0d7e` (`ts_lexer_goto` binary search) |
  | B | `dcdd9465` (B1 `2f3b6b6` + B2) | `da6fe9be` |
  | A+B | `dcdd9465` | `091c0d7e` |

  "stock" is also built from local copies, so every variant goes through the same path-dependency build. The B3 experiment was not used.
- **Wiring.** When `MACDOWN_DEP_TRIAL_ROOT=<dir>` is set, `MacDownKit/Package.swift` replaces the SwiftTreeSitter URL dependency with `.package(path: <dir>/SwiftTreeSitter)` and `.package(path: <dir>/tree-sitter)`. The root path dependency overrides Neon's transitive SwiftTreeSitter. When the variable is unset, the manifest resolves exactly as on `integration-final`. Each variant is built in its own scratch copy of `MacDown2/Packages`.
  - SwiftPM warns about the override: "Conflicting identity for swifttreesitter … will be escalated to an error in future versions of SwiftPM". It also warns "dependency 'tree-sitter' is not used by any target". A fork pin would need a different mechanism.
- **Package.resolved.** The committed file is unchanged. In the variant copies, SwiftPM drops the `swifttreesitter` and `tree-sitter` pins (they are local now) and changes `originHash`. The other 18 pins are identical (`scripts/package-resolved-variant.diff`).
- **B2's new `LanguageLayerError.includedRangesRejected`.** No code in MacDownKit or the app switches over `LanguageLayerError`. Neon catches `resolveSublayers` errors generically and only logs them (`os_log` fault "Failed resolve sublayers"). Compile results:
  - All MacDownKit targets and tests compile for B and A+B.
  - The **app** (scheme MacDown2, Debug, unsigned) builds against A+B: `** BUILD SUCCEEDED **` in `logs/app-AB-build-debug.log`. Xcode picks up the environment variable.
  - The unified log contained no "Failed resolve sublayers" fault during the B and A+B runs, so B2 never threw in these tests.

## 1. NeonReplacementEditTests (Debug + Release, every variant)

`scripts/NeonReplacementEditStrictTests.swift` is a scratch copy in which every `withKnownIssue` is a plain `#expect`. It adds two things:
- a test that replaces 600 units with the markup removed, which probes B1's limitation that ranges are not removed when an injection vanishes;
- an `H5-STRICT` divergence summary. `RenderedRun` compares foreground colour and font traits, so any mismatch is a **visible** highlight difference.

The shipped file was run unchanged alongside it.

| test (48 KB fixture) | stock | A | B | A+B |
|---|---|---|---|---|
| rapid typing | pass | pass | pass | pass |
| delete a block | pass | pass | pass | pass |
| type, then delete a block in one turn | **fail**, 2 units | fail, 2 | fail, 2 | fail, 2 |
| replace 600-unit selection with inline ranges | **fail**, 60 units | fail, 60 | fail, 60 | fail, 60 |
| replace with markup removed (B1 limit) | **fail**, 33 units | fail, 33 | fail, 33 | fail, 33 |
| widened background typing (Release) | **fail**, 770 units | fail, 770 | fail, 770 | fail, 770 |
| widened background typing (Debug, opt-in) | aborts: `String+Data.swift:20` "location is greater than end" | aborts | aborts | aborts |

The results are identical in Debug and Release, and identical to the unit across all four variants. The shipped file passes everywhere with its 2 (Debug) or 3 (Release) known issues. **The known-issue flips fail for B and A+B.**

Diagnostic: after a failure, `invalidateAll()` re-queries the edited editor's existing parse state.
- One-turn type-then-delete then matches a fresh highlighter. That case is a stale-invalidation defect in Neon. It does not depend on the patches.
- The three replacement cases and the widened case still differ. So in Neon's edit flow the inline parse state itself differs from a fresh parse, even with B1. Stage 1's LanguageLayer-only harness showed B1 giving trees identical to a fresh parse. This candidate cause has not been isolated: the known markdown_inline incremental-reparse divergence, or Neon's sublayer resolution scope.

## 2. Full package suite, Debug (`swift test --skip-build --no-parallel --skip NeonReplacementEditStrictTests`)

- **stock:** 2,580 tests in 342 suites passed, with 2 known issues (228 s).
- **A+B:** the same 2,580 tests passed, with the same 2 known issues (221 s).

There are no failures to attribute to either patch.

## 3. Release benchmarks (fallback disabled; Neon unbounded)

Base command:

```
MACDOWN_DEP_TRIAL_ROOT=deps/<v> <ENV> swift test --skip-build -c release -Xswiftc -enable-testing --no-parallel --filter <Suite>
```

The budget benchmark was run with `MACDOWN_HIGHLIGHT_BUDGET_BENCH=1 MACDOWN_HIGHLIGHT_BUDGET_FIXTURES=ordinary,inlineDense,longLines,unicode`:
- 8–256 KB: two passes, in the order stock→A+B and then reversed;
- 1 MB: one pass.

Edits are 1-character inserts/deletes at the start, middle and end of the document. Stall values pool all positions and passes. n is the sample count: 96 per cell up to 64 KB, 48 at 256 KB, 12 at 1 MB. The full per-fixture table is in `budget-table.md`.

**Worst p95 main-thread stall per edit (ms) across the four fixtures** (budget 50 ms):

| KB | stock | A | B | A+B |
|---|---|---|---|---|
| 8 | 36 | 26 | 36 | 29 |
| 12 | 38 | 41 | 34 | 42 |
| 16 | 48 | 57 | 35 | 37 |
| 24 | 54 | 69 | 66 | 59 |
| 32 | 81 | 98 | 85 | 69 |
| 64 | 175 | 154 | 174 | 159 |
| 256 | 2188 | 1878 | 1937 | 1930 |

**inlineDense, stall p50 / p95 / max (ms), with edit settle median / max (ms):**

| KB (UTF-16 units) | stock | A | B | A+B |
|---|---|---|---|---|
| 8 (8,470) | 18/23/32, settle 0/27 | 18/24/34 | 17/28/46 | 16/26/41 |
| 16 (16,422) | 28/48/50, settle 0/41 | 25/57/86 | 27/35/51 | 26/35/50 |
| 32 (32,974) | 56/81/91 | 53/98/132 | 56/85/88 | 51/69/86 |
| 64 (65,631) | 149/175/184 | 133/154/165 | 148/174/382 | 130/159/416 |
| 256 (262,151) | 1828/2188/2245, settle 1800/1854 | 1514/1878/2086, settle 1365/1802 | 1740/1937/2549 | 1387/1930/2366, settle 1352/2200 |

**1 MB** (n = 4 per position). The p50 stall at the start/middle edit positions is:

| fixture | stock | A | B | A+B |
|---|---|---|---|---|
| ordinary | ~1,090 ms | ~420 ms | ~1,100 ms | 430–715 ms |
| unicode (548k units) | ~1,890 ms | ~490 ms | ~1,900 ms | ~485 ms |

Two parts of the 1 MB data are a different kind of measurement:
- The ordinary "end" edit lies beyond Neon's 1,048,576-unit synchronous position, so it runs asynchronously: stall ~1–5 ms, but settle 4.2 s for stock and B and 1.5 s for A and A+B.
- **inlineDense and longLines at 1 MB are not valid measurements of the inline path.** Open settles in about 1 s, and the edits show no highlight activity. The same pattern appears in the earlier `h5-highlight-fallback` evidence. The `hasInlineStylingNearEnd` guard can be satisfied by bold headings from the block grammar.

**KeystrokeStallBenchmarkTests** (StallFixtures, 50 keystrokes 50 ms apart, `MACDOWN_KEYSTROKE_BENCH=1 MACDOWN_KEYSTROKE_BENCH_KB=64,256`). Neon mode, stall p50 / p95 / max (ms):

| KB | stock | A | B | A+B |
|---|---|---|---|---|
| 64 | 65/67/120 | 50/54/75 | 65/79/250 | 50/53/77 |
| 256 | 500/514/565 | 246/254/316 | 496/515/554 | 250/261/315 |

Scratch-only change to this benchmark (`scripts/keystroke-wait-scratch.diff`): its final wait required the styled-token count to rise above the baseline. Alternating insert/delete returns the count to the baseline, so the wait ran into its 900 s timeout; the first stock run was aborted after about 29 minutes. The change only affects how long the last edit's window stays open.

**pasteWithoutTheFallback** (inlineDense pasted into a document just below the cut-off; `MACDOWN_HIGHLIGHT_FALLBACK_BENCH=1`). The variants do not differ beyond noise:

| paste | paste stall | settle | typing afterwards (p50) |
|---|---|---|---|
| 256 KB | 565–583 ms | 1.03–1.10 s | 500–572 ms |
| 1 MB | 17.7–18.4 s | 20.1–20.9 s | 2.47–2.55 s |

## Conclusions

- **A** roughly halves to quarters the large-document keystroke stall:
  - 256 KB StallFixtures: 500 → 246 ms;
  - 1 MB ordinary: 1.09 s → 0.42 s; 1 MB unicode: 1.89 s → 0.49 s.
  - inlineDense at 256 KB improves only about 15 %.

  The result is not flat, and the remaining cost is not attributed: ts_subtree_compare/select_tree and resolveSublayers were not profiled here. Near the cut-off (8–32 KB), A is within run-to-run noise of stock.
- **B** changes neither latency nor any Neon-level highlight result. Its value is correctness at the LanguageLayer level (stage 1) plus making rejection observable (B2). It does not fix the visible divergences.
- **Cut-off: keep 8,192.** No variant keeps the worst p95 below 50 ms with margin above about 16 KB. At 24–32 KB every variant exceeds the budget.

## Still to verify before proposing anything upstream

- Why Neon-level replacement edits still diverge with B1. This needs a LanguageLayer-level reproduction of Neon's exact resolve sequence.
- A profile of the residual cost after A.
- The tree-sitter and SwiftTreeSitter suites on the final patches.
- B1's handling of vanished injections.
- That B2's public API change is acceptable to ChimeHQ.

Any proposal upstream needs the owner's go-ahead.
