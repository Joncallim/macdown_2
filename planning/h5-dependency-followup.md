# H5 dependency follow-up plan (defects reproduced in scratch; no fix adopted)

Register row H5 / issue #203. The size-based fallback that shipped with this
plan (PR #479) is a containment measure. It does not fix either problem below.

**Status (2026-10-16).** Both problems were *reproduced in scratch* (sections
"Reproduction results"); the proposed fixes were *tried only in scratch copies*
(a 6-line change in tree-sitter's `lexer.c` for A, a short experiment in
SwiftTreeSitterLayer for B). **No fix is adopted:** nothing is patched in this
repository, no fork exists, nothing was sent upstream. The plan sections below
are the original plan; the "Reproduction results" section records what was
actually run and what is still untested.

Pinned revisions when this plan was written:

- Neon `484d6fb9e0c4fb679a1d5f5ddaf2cac2ecf21165`
- SwiftTreeSitter / SwiftTreeSitterLayer `cbe31cb3601aa29c1f64b6e4328733511126d6d5` (`branch: main`)
- tree-sitter runtime: whatever SwiftTreeSitter resolves at that revision
- vendored `Packages/TreeSitterMarkdown`

## Problem A: inline-layer reparse grows faster than document size

What has been measured (Release, `LanguageLayer.didChangeContent`, one-character
edit): the root block grammar alone takes 8 / 33 / 133 ms at 64 KB / 256 KB /
1 MB. With the resolved `markdown_inline` sublayer it takes 69 ms / 518 ms /
6.2 s. The reconciliation experiment in
`InlineResolutionReconciliationTests` (see the register) shows the cost
appears only once the inline layer has been resolved across the whole
document.

Proposed explanation (from reading the code, not verified): tree-sitter's
`ts_lexer_goto` scans the included-range list linearly on every lexer seek.
The inline layer has roughly one included range per inline-bearing block, so
a reparse costs about O(tokens × ranges).

Plan:

1. **Reproduce before patching.** Write a standalone C harness against the
   exact tree-sitter sources SwiftTreeSitter builds. It parses one inline
   layer with N included ranges and records parse time against N at a fixed
   text size. Separately, profile `ts_lexer_goto` with Instruments
   (Time Profiler, Release) on the 256 KB `inlineDense` fixture. The patch
   step is justified only if `ts_lexer_goto` dominates and the time grows
   with N.
2. **Minimal pinned patch on an isolated branch.** Fork tree-sitter at the
   resolved revision on a branch named for the change. Replace the linear
   included-range scan with a binary search, or remember the last range
   index. Point SwiftTreeSitter at the fork through a pinned revision on a
   separate branch of this repo, never `main`.
3. **Measure correctness first, then latency.** Correctness: run the
   tree-sitter test suite, and check that `NeonReplacementEditTests`'
   control tests and `HighlightingSizeFallbackTests` produce identical
   highlights with and without the patch. Latency: rerun
   `HighlightBudgetBenchmarkTests` and `KeystrokeStallBenchmarkTests` on an
   idle Mac. Report p50/p95/max stall and settle time per size against the
   numbers in the register. Record whatever is measured. Do not predict a
   number in advance.
4. **Prefer upstream.** Open an issue and PR upstream with the C reproducer.
   Keep a fork only while the upstream change is pending, and record its
   revision in the register.

## Problem B: collapsed or overlapping inline ranges after a replacement edit

What has been reproduced (`NeonReplacementEditTests`, a known issue, 5 out of
5 runs in Debug and in Release): replacing a selection whose old text contains
whole inline ranges leaves the inline highlighting different from what a
fresh highlighter produces. Typing and then deleting a block in one
main-actor turn also diverges.

Proposed cause (from reading the code): `ts_tree_edit` collapses included
ranges inside the edit to zero length. `SwiftTreeSitterLayer`'s
`encorporateRanges` keeps them, and the merged list overlaps the newly found
ranges. `ts_parser_set_included_ranges` then returns `false`, SwiftTreeSitter
ignores that, and the inline sublayer keeps its stale ranges.

Plan:

1. **Reproduce before patching.** Add a SwiftTreeSitterLayer-level test (no
   Neon) that performs the replacement edit and asserts on the sublayer's
   included ranges. Also add an assertion, as a debug-only local
   instrumentation patch that is not committed, that
   `ts_parser_set_included_ranges` returned `true`. Confirm the zero-length
   ranges and the rejected call.
2. **Minimal pinned patches on isolated branches,** one per concern:
   - (B1) SwiftTreeSitterLayer: drop zero-length and overlapping ranges in
     `encorporateRanges`, and keep the list sorted and disjoint.
   - (B2) SwiftTreeSitter: surface the `Bool` from
     `ts_parser_set_included_ranges`. Throw or assert instead of ignoring
     it, so this class of bug becomes visible.
3. **Measure.** Flip the `withKnownIssue` tests in `NeonReplacementEditTests`
   to plain expectations on the patched branch and require them to pass.
   Rerun the latency benchmarks above to confirm there is no regression.
   Run the Debug suite as well, since the "location is greater than end"
   assertion is Debug-only.
4. **Prefer upstream.** Send B1 and B2 to ChimeHQ/SwiftTreeSitter with the
   failing test, and pin a fork only while they are pending.

## Only after A and B

Revisit taking the reparse off the main thread. That needs Neon to expose
its `synchronousLengthThreshold` / `synchronousDocumentSize` and to coalesce
queued reparses, or our own client in place of `TreeSitterClient`. Revisit
the size-fallback cut-off too, using the measured numbers. Windowed parsing
(step 2 of the H5 plan) remains a separate design.

## Reproduction results (2026-10-16)

Scratch reproductions only (experiments on copies of the pinned sources; nothing
is patched in this repository, no fork is adopted, nothing was sent upstream).
Sources, results and diffs:
`planning/downstream/evidence/h5-dependency-repro/`. tree-sitter
`da6fe9beb4f7f67beb75914ca8e0d48ae48d6406` (v0.25.10, resolved by SwiftTreeSitter
`cbe31cb3`); vendored `TreeSitterMarkdown` grammar; Release/`-O2`, M3 Pro.

### Problem A: **proven** (synthetic ranges)
A standalone C harness parses 262,144 bytes of `markdown_inline` text split into
N evenly spaced included ranges, then reparses after a one-character edit.
Reparse p50 (stock): 137 ms at N=10, 175 at 1,000, 492 at 10,000, 1,122 at
30,000, 4,739 at 100,000. `ts_lexer_goto` is called about 248k times at every N,
and its loop iterations grow linearly with N (1.4 million at N=10; 1.26 billion
at N=10,000): O(tokens × N). A `sample` profile at N=100,000 puts about 97 % of
samples in `ts_lexer_goto`. A binary-search variant (about 6 lines in
`lexer.c`, `A/ts_lexer_goto_bsearch.diff`) is flat at 136–153 ms for all N and
gives an identical tree hash at N = 10, 1k, 10k and 30k (`A/equiv_A.txt`).
Limits: synthetic, evenly spaced ranges, not the real `inlineDense` fixture; no
Instruments run; the tree-sitter test suite has not been run on the patch. Side
finding: in this harness the reparse of the inline layer costs as much as a full
parse, so almost nothing is reused.

### Problem B: **proven; the stated cause was too narrow**
With SwiftTreeSitterLayer alone (no Neon), a 48 KB document, in a scratch copy
that records the result of `ts_parser_set_included_ranges`:
- Replacing 600 units mid-document: 15 zero-length ranges remain, one old range
  spans the whole replaced region, and the call returned **false** (the rejected list had 1,271 ranges,
  one overlap: `[24598, 25215)` then `[24599, 24626)`). The inline tree differs from a fresh parse (16 ranges only in
  the fresh one, 1 only in the edited one, 3 extra highlight captures).
- Deleting a block, and type-then-delete in one turn: also rejected (38
  zero-length ranges; range lists differ, 1255 vs 1216); highlights happened to
  match in this fixture.
- **Correction:** the ordinary one-character typing edit is also rejected.
  Typing can move an inline node's start (the old range `[24600, 24627)` overlaps the new `[24597, 24627)` in the saved
  output), and `encorporateRanges` drops an old range only when its start equals
  a new range's start, so an overlapping old range survives. Any old range that
  overlaps a new one with a different start triggers the rejection; zero-length
  ranges are one way to get there. Highlights matched only by luck.
- An experimental B1 (drop empty ranges and old ranges overlapping a new one)
  gives 0 rejections, range lists and S-expressions identical to a fresh parse,
  and no highlight difference in every scenario tried (`B/results_B_release_B1sketch.txt`).
Not done: the patches have not been run against Neon or `NeonReplacementEditTests`
(the `withKnownIssue` flip), nor under Debug.

### Patch size and maintenance (for the fork decision)
- A: about 6 lines in tree-sitter C (`lexer.c`). Upstream is tree-sitter itself.
- B1: about 5–10 lines in SwiftTreeSitterLayer `encorporateRanges` (a sort-and-merge
  pass would avoid the O(old × new) filter in the sketch). B2: about 3 lines in
  `Parser.includedRanges`; throwing would change a public API, asserting would not.
  Upstream is ChimeHQ/SwiftTreeSitter.
- Total patch under ~25 lines across two upstreams. Recommendation: upstream first,
  pin a fork revision only while a PR is pending. **Not done and needs the owner's
  go-ahead: opening upstream issues/PRs (outward-facing), adopting any fork.**

### Next steps (in order, none started)
1. Apply A and B1/B2 on isolated local branches; run the tree-sitter and
   SwiftTreeSitter test suites, flip the `NeonReplacementEditTests` known issues,
   then `HighlightBudgetBenchmarkTests` and `KeystrokeStallBenchmarkTests` in Release.
2. Only then revisit the 8,192-unit cut-off and the off-main-thread question.

### How to re-run, and what the saved output does and does not show
- **A:** `A/run_A.sh <tree-sitter checkout at TS_REVISION> MacDown2/Packages/TreeSitterMarkdown <workdir>`
  (needs only a C compiler). It builds stock, counter-instrumented and
  binary-search variants from the same sources. Example from the repository
  root, after a package resolve:
  `planning/downstream/evidence/h5-dependency-repro/A/run_A.sh MacDown2/Packages/MacDownKit/.build/checkouts/tree-sitter MacDown2/Packages/TreeSitterMarkdown /tmp/repoA`.
  Re-run on 2026-10-16 (second run): stock p50 reparse 139 / 177 / 512 / 1,194 ms at N = 10 / 1,000 / 10,000 /
  30,000; binary search 141–157 ms at every N; goto iterations 1,364,897 (N=10)
  to 1,256,776,080 (N=10,000) over about 248k calls (`A/instr_counts_rerun.txt`
  and the first run in `A/results_A.txt`; the earlier "1.4 million / 1.26 billion"
  were these figures rounded). Timings vary by a few percent between runs.
- **B:** `B/run_B.sh <SwiftTreeSitter checkout at SWIFTTREESITTER_REVISION> MacDown2/Packages/TreeSitterMarkdown <workdir>`
  (builds a SwiftPM package; needs network the first time to resolve
  tree-sitter). Saved reruns: `B/rerun_stock.txt` (every scenario `rejected=1`;
  zero-length ranges 0 / 15 / 38 / 38) and `B/rerun_B1.txt` (every scenario
  `rejected=0`, no zero-length ranges, no highlight difference); identical to the
  original `B/results_B_release.txt` verdict rows.
- **Not reproducible from the saved material, and why:** the `sample` profile
  (about 97 % in `ts_lexer_goto`) is saved as text from one run
  (`A/sample_N100000_noinline.txt`) but is not scripted; the "incremental reparse
  costs as much as a full parse" side finding comes from the same harness
  columns (`full_*` vs `edit_*`) and was not examined further.
- **Grammar and dependency versions:** tree-sitter `da6fe9be...` (v0.25.10,
  `A/../TS_REVISION`), SwiftTreeSitter `cbe31cb3...` (`B/SWIFTTREESITTER_REVISION`),
  vendored `Packages/TreeSitterMarkdown` of this repository at the commit that
  contains this file. The B fixture is the 48 KB document in `B/main.swift`
  (a copy of `StallFixtures`); the A text is synthetic.
