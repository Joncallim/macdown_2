# H5 profile: where the full-highlighting time goes (branch `dep-trial` only; diagnosis, nothing adopted)

All numbers are **full mode** (Neon unbounded, size fallback disabled: `HighlightedEditor(sizePolicy: { _ in nil })`). Nothing here measures the shipped fallback.

## Environment

- Apple M3 Pro (11 cores, 18 GB), macOS 26.5.1 (25F80), Xcode 26.6 (17F113), Swift 6.3.3.
- Base commit `ea4bc296` (`dep-trial`). Neon `484d6fb9`. Release builds (`-c release -Xswiftc -enable-testing`).
- The machine was **not quiet**: the 1-minute load average was 4.5–13.8 during the session (fileproviderd, mds_stores, WindowServer, a ChatGPT/Codex renderer). No other build or test process was running during any run (`prof.sh`/`build.sh` wait for that). Absolute times are therefore noisier than in `h5-dependency-trials`; shares and counters are the robust results.

## Variants

| name | tree-sitter | SwiftTreeSitter(Layer) | instrumented | experiment |
|---|---|---|---|---|
| stock | `da6fe9be` (0.25.10) | `cbe31cb3` | no | – |
| A | `091c0d7e` (ts_lexer_goto binary search) | `cbe31cb3` | no | – |
| si / ai | as stock / A | as stock | yes (counters) | – |
| se1 / ae1 | as stock / A | as stock | yes | **E1**: `ts_subtree_compare` does not descend into a child pair that is the same subtree pointer |
| si + `H5PROF_E3=64` | stock | stock | yes (+Neon timing) | **E3**: Neon `TextLayoutManagerSystemInterface.applyStyles` drains an autorelease pool every 64 tokens |
| probe (C) | stock + counters | – | yes | **E2**: one tree per paragraph instead of one combined inline tree |

stock and A are the stage-2 trees (`h5-dependency-trials`). Instrumentation (`scripts/instrument_*.py`) adds plain counters/timers printed to stderr when `H5PROF_TS` is set (`H5TS` = one line per `ts_parser_parse`; `H5LL` = LanguageLayer parse/resolve; `H5NEON` = one line per applyStyles). Every experiment is scratch only.

## Commands

- Harness: `scripts/H5ProfileHarnessTests.swift` (scratch test, inlineDense fixture). `H5PROF_MODE=edit`: open, wait quiet, alternate 1-char insert/delete in the middle (`H5PROF_EDITS`, `H5PROF_GAP_MS` apart). `H5PROF_MODE=paste`: open just below 8,192 units, paste `H5PROF_KB` of inlineDense at offset 100 (the `pasteWithoutTheFallback` scenario).
- `scripts/prof.sh <variant> <name> <secs> ENV…` runs the harness and attaches `xcrun xctrace record --template "Time Profiler" --attach <pid>` (1 ms samples) when the harness is ready. `sample(1)` could not read stacks of `swiftpm-testing-helper`.
- `xcrun xctrace export --xpath '…/table[@schema="time-profile"]'` → `scripts/fold.py` (main thread, folded) → `scripts/analyze.py` (inclusive category shares). Traces themselves are not kept (they embed the process environment); folded stacks are in `profiles/`.
- Counters: `TOOL=none prof.sh si|ai|se1|ae1 cnt-… 1 H5PROF_TS=1 …`; summaries: `scripts/summarize_counters.py` → `analysis-counters.txt`.
- Probe: `scripts/probe.c` built with clang against a tree-sitter copy and the vendored markdown_inline grammar → `probe-inline-versions.txt`.

## Sample counts (main thread, 1 ms each)

| profile | samples | workload |
|---|---|---|
| tp-stock-64 | 1,359 | 64 KB, edits (trace window caught ~8 of 20) |
| tp-A-64 | 3,022 | 64 KB, 20 edits |
| tp-stock-256 | 15,057 | 256 KB, 8 edits |
| tp-A-256 | 12,789 | 256 KB, 8 edits |
| tp-ae1-256 | 2,501 | 256 KB, 8 edits (instrumented build) |
| tp-stock-paste1024 | 25,100 | 1 MB paste |
| tp-A-paste1024 | 25,103 | 1 MB paste |
| tp-si-e3-paste1024 | 1,369 | 1 MB paste, E3 |

## Findings

**Keystroke (256 KB inlineDense, 262,151 units).** ≥98 % of the stall is synchronous inside `NSTextStorage processEditing → Neon TreeSitterClient.didChangeContent → LanguageLayer.parse`. Instrumented split per edit (median): block grammar 38 ms (incremental, reuses 523 KB of 524 KB), **inline layer 1,627 ms**, changedSet 16 ms. resolveSublayers, token queries and setRenderingAttributes are ~0 % per keystroke in this harness (invalidated sets of 0–2 units).

Profile shares (inclusive, main thread): stock — `ts_parser__select_children` 69 % (of which `ts_subtree_compare` self 49 %, `ts_subtree_symbol`/`child_count` 20 %), `ts_lexer_goto` 16 %; A — select_children 81 %, lexer_goto 0.4 %.

Root causes (counters, `analysis-counters.txt`):
1. **One combined inline tree with 4,545 included ranges, and no incremental reuse.** tree-sitter only reuses nodes when there is a single stack version (`allow_node_reuse = version_count == 1`). In the inline layer 590,364 of 590,379 advances run with ≥2 versions; `reuse_bytes` = 76 of 524,239. The probe (`probe-inline-versions.txt`) shows that plain text and code spans stay at one version (full reuse). With `*`, `_`, `**` or links, a second version appears at the first delimiter and lasts until about the end of the paragraph. In inline-dense text the versions never get back to one (max 10; only ~15 single-version steps in the whole parse). Every keystroke is a full inline re-lex/re-parse.
2. **`ts_subtree_compare` is O(n) per call** when the two candidate child arrays share almost all subtrees: 909 calls visit 150.8 M nodes at 256 KB (0.62 M at 16 KB, 9.6 M at 64 KB: ×15.5 per ×4 size, quadratic). E1 cuts it to 5,454 nodes; the rendered highlighting is identical (`dump-*` runs).
3. **`ts_lexer_goto` linear scan** over included ranges: 1.02 G iterations at 256 KB (stock), 450 K with A.

| inline parse per keystroke (ms) | 16 KB | 64 KB | 256 KB |
|---|---|---|---|
| stock (si) | 33 | 147 | 1,627 |
| A (ai) | 42 | 127 | 1,600 |
| stock + E1 | 25 | 85 | 523 |
| A + E1 | 23 | 81 | 258 |

Whole edit call, A + E1 at 256 KB: ~300 ms (stock ~1,700 ms). The remainder is a plain full GLR reparse (reduce 29 %, lex 7 %, changedSet 6 %).

E2 (probe, not in the app): parsing each paragraph as its own tree costs ≤ 0.5 ms per tree at every size, against 62 / 335 / 2,701 ms for an incremental reparse of the combined tree (49 KB / 200 KB / 809 KB, stock). The markdown injection query does not ask for `injection.combined`; SwiftTreeSitterLayer combines all injections of one language into one layer anyway.

**1 MB paste.** The paste call returns in 18 ms; the block + inline parses (~2.4 s) run off the main thread. The main-thread stall is **one** Neon `applyStyles` call: 143,461 tokens over 1,048,850 units, 21.1 s in the per-token `setRenderingAttributes` loop, plus ~2.2 s `objc_autoreleasePoolPop` afterwards (TextKit `NSCountableTextRange` creation → `NSConcreteHashTable rehashAround` 79 %). Same for stock and A. Per-token cost: 6.9 µs (64 KB), 7.8 µs (256 KB), 147 µs (1 MB). With E3 it is 6.8 µs at 1 MB: 21,056 → 979 ms; whole main-thread busy time 25.1 s → 1.37 s. In the E3 run, `NeonSyntaxHighlighter.styledFont` (an `NSFont` built per token) is 23.5 % and the highlights query is 20 %.

## Not established

- Why the inline GLR versions never merge (grammar conflicts vs external-scanner state); E2 is a probe on UTF-8 paragraphs, not a SwiftTreeSitterLayer change.
- Behaviour with a real window/scrolling (visible-range validation and resolveSublayers are not exercised by this harness), and other fixtures than inlineDense.
- The identity of the TextKit hash table behind the paste blow-up; only that draining the pool removes it.
- E1/E3 were not run through the full test suites.
