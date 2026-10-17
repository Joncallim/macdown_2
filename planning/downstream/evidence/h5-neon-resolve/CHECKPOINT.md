# H5 stage C2 checkpoint (2026-10-18): sublayer-resolution trials, INCOMPLETE

**Experimental only. Nothing here is adopted, merged, released or sent upstream.** Branch `dep-trial` (pushed). The integration candidate (`integration-final`, PR #480 draft)
and its dependency pins (`Package.resolved`) are unchanged; the 8,192 UTF-16-unit highlighting fallback is unchanged and is what ships. The stage-C2 agent stopped at a usage limit
before it wrote its own report; this file is the owner-side record of what exists.

## Heads
- `dep-trial`: see the commit that adds this file (parent `4cdbc498`, stage C1). Previous heads: `d11e0d64` (divergence diagnosis), `2c39db7e` (profile), `ea4bc296` (stage 2 wiring).
- Experimental dependency heads used by the best C2 run (scratch repos, outside this repository; patches saved under `patches/`): SwiftTreeSitter `749058eb` (`c2-resolve-set` = B1+B2 `dcdd9465` + resolve-set patch),
  tree-sitter `091c0d7e` (`a-lexer-goto-bsearch`, patch A), Neon `9c533b9a`/`a0d372f` (`c2-sublayer-resolve` on top of the C1 patches `3edd621` buffer transform and `b94a378` pending-limit).
- Wiring: `MACDOWN_DEP_TRIAL_ROOT=<dir containing SwiftTreeSitter, tree-sitter, Neon>`; unset = production pins.

## Uncommitted files at the checkpoint (now committed on dep-trial)
`Tests/HighlightingTests/NeonSublayerResolveTests.swift`, `NeonSublayerLayerLevelTests.swift` (new, opt-in: `MACDOWN_NEON_RESOLVE_TRIAL=1`), a scratch change to `HighlightBudgetBenchmarkTests.swift` (the keystroke-benchmark wait fix noted in stage 2; scratch only), and this evidence folder.

## What ran (Debug only, one machine: M3 Pro, macOS 26.5.1, Xcode 26.6, Swift 6.3.3)
Deterministic cases through the real Neon highlighter on the 48 KB fixture, compared per UTF-16 unit with a fresh highlighter. Command pattern (see `scripts/combos*.sh`):
`MACDOWN_NEON_RESOLVE_TRIAL=1 MACDOWN_NEON_RES_RANDOM=0 [STS_EXPAND=1 STS_DROP_STALE=1 STS_SKIP_SAME=1] swift test … --filter NeonSublayer…` against the scratch deps.
Summaries: `summaries/sum-*.txt`. The best configuration used three experimental environment toggles inside the SwiftTreeSitter patch (`STS_EXPAND`, `STS_DROP_STALE`, `STS_SKIP_SAME`): **it is not a clean patch yet.**

### Passed (0 differing units) in the best run (`sum-det-expand.txt`)
Replacing inside a paragraph and across a boundary; the 600-unit replacement cases (including markup removed); deleting inside a paragraph, across a boundary, an emphasis, a link, a code span, a fenced block; joining paragraph+list and heading+paragraph; insert inside a paragraph and splitting a paragraph; large delete / large plain replace followed by edits; ten turns with no wait; scroll-window cases `scrollEditInsideWindow` and `scrollLargeEditOutside`.
Without the resolve change (`sum-det-resolveoff.txt`) the 600-unit replace case differed by 60 units: so the change fixes at least that case.

### Failed (still differing from a fresh highlighter)
`deleteParagraph` 2 units; `openFence` 4,536; `removeOpeningFence` 10,132; whole-block deletion 28 (the C1 residual); typing in the last fence 3 (the C1 residual); `largePasteThenSameTurn` 2,358; `largePasteFenceThenTurns` 25,507; `fortyEditsOneTurn` 7,230; scroll cases with the edit in a gap or straddling a window boundary 440-660 units in the visible window; client-level `openFence` / `removeOpeningFence` ≈3,100. Opening or removing a code fence (which changes how everything after it parses) is the clearest failing family; the default configuration (without the toggles) showed `insertSplitParagraph` 20 units and 26 issues overall.
Random sequences: not completed in this run (seeded runs show styling-class residuals, e.g. seeds 98, 101, 103, 108, 111, mostly healed by `invalidateAll`, i.e. stale styling rather than wrong parse state).

### Not tested
Release builds of any C2 test; the performance comparison against the unchanged baseline (stage C2 task B), including ordinary documents below the fallback threshold; the full MacDownKit suite and the app build against the patched stack; the cost of the resolve change; the "second buffer bug" (`endBuffering` ordering) beyond the C1 sample; independent review of any C2 patch.

## Recommendation (smallest next step, for the Astra handoff)
Do **not** adopt any of this. Decide first whether pursuing full large-document highlighting through Neon is worth it at all: the profile shows the dominant keystroke cost is the whole-inline-layer reparse (tree-sitter), which none of these patches addresses; the resolve/invalidation fixes are about correctness of highlights after edits, and open/remove-fence cases remain wrong. If the answer is yes, the next bounded step is to finish TASK B (baseline performance, ordinary documents < 8 KB, Release) with the C1 patches only, because that decides whether the already-small C1 patches (buffer transform, pending limit) are safe to propose. See `ASTRA_HANDOFF.md`.
