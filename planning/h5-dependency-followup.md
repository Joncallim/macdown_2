# H5 dependency follow-up plan (not implemented)

Register row H5 / issue #203. This is a plan only. Nothing here has been
done, and no speed-up is claimed. The size-based fallback that shipped with
this plan is a containment measure. It does not fix either problem below.

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
