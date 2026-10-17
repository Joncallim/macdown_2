# H5 stage C1: Neon buffered invalidation + Debug "location is greater than end" (branch `dep-trial` only)

Scratch patches to Neon 484d6fb9, tested in the real MacDownKit editor path. Nothing is adopted, nothing was sent upstream, `Package.resolved` and the shipped 8,192-unit fallback are unchanged. **This does not fix the app's H5 divergences** (see "What remains").

## Setup

- Machine: Apple M3 Pro, 18 GB, macOS 26.5.1 (25F80), Xcode 26.6 (17F113), Swift 6.3.3. One heavy job at a time (`run.sh` waits for other build/test processes).
- Deps (`deps/c1` in scratch): SwiftTreeSitter `dcdd9465` (B1+B2) + tree-sitter 0.25.10 (copies of stage-2 `deps/B`), and a git clone of Neon 484d6fb9 with branches:
  - `c1-stock` (484d6fb9), `c1-invalidation-buffer` (task 1 patch), `c2-pending-limit` (task 2 patch, on stock), `c12-both` (both);
  - DIAG only: `c1-diag-toggles` (patch + `C1_STOCK_BUFFER=1` / `DIAG_NEON_FIX=1` = the divergence-evidence resolve toggle), `c1-diag-reentrant`, `c1-diag-trace`, `c12-diag-toggles`.
- Wiring: `MacDownKit/Package.swift` now also uses `$MACDOWN_DEP_TRIAL_ROOT/Neon` as a path dependency when that directory exists (otherwise the Neon pin is unchanged).
- Tests (committed, opt-in): `Tests/HighlightingTests/NeonBufferedInvalidationTests.swift` (`MACDOWN_NEON_INVALIDATION_TRIAL=1`), `NeonPendingEditLimitTests.swift` (`MACDOWN_NEON_PENDING_TRIAL=1`). Neon unit tests are inside the patches.
- Commands: `scripts/run.sh <debug|release> <neon-branch> <tag> <filter> [ENV=..]` (Release adds `-Xswiftc -enable-testing`); `scripts/random-release.sh`, `scripts/task1-debug.sh`, `scripts/task2.sh`. Logs: `logs.tar.gz`.

## Task 1: buffered invalidations not moved through later edits

**Cause.** `TextViewHighlighter` buffers invalidations from `willChangeContent` until a `DispatchQueue.main.async` flush. A later edit in the same turn does not transform the buffered set, so the flush restyles the old offsets.

**Patch** (`patches/neon-c1-0001-*.patch`; +46 source lines, +90 test lines): `RangeInvalidationBuffer.contentChanged(in:delta:)`, called from `didChangeContent` before the client reports the new edit. It moves each buffered range; a range overlapping the edit keeps its surviving part and grows over the replacement text. `RangeTarget.apply(mutations:)` / `RangeMutation.transform(set:)` were not reused: both drop or over-shrink a range partially overlapped by a deletion (unit-tested cases `deletionOverlappingTheStart/End`).

**Tests.** 48 KB fixture, real `NeonSyntaxHighlighter` → `TextViewHighlighter`, every UTF-16 unit compared with a fresh highlighter. Each failing sequence is re-run as a control with one edit per turn; `excessUnits` = units wrong in one turn but right in the control.

| suite | stock Debug | stock Release | patch Debug | patch Release |
|---|---|---|---|---|
| 11 deterministic block-neutral sequences | 6 fail (2, 4, 10, 10, 8, 27 units; all excess, all fresh after `invalidateAll`) | same 6 | **0 fail** | **0 fail** |
| 200 seeded random (2–6 inserts/replacements/deletions, start/middle/end) | 158 differ, **105** with excess | 158 / **105** | 126 differ, **1** with excess (seed 114, 3 units) | 126 / **1** |
| Neon `RangeStateTests` (+9 new) | new tests do not compile (API absent) | — | pass | pass |

Debug and Release give identical numbers.

**Residuals (not this patch).** 125/200 random sequences fail as the one-edit-per-turn control too. Most are parse-state divergences (still wrong after `invalidateAll`): the missing sublayer resolution (`h5-neon-divergence`) and related range staleness. Two single-edit styling gaps also appear (opt-in `MACDOWN_NEON_INV_RESIDUALS=1`, identical before and after): deleting whole blocks styles the preceding fence like the following heading (28 units); typing in the last fenced line leaves its closing fence stale (3 units, the "3 units, fresh after invalidateAll" seeds).
- Seed 114 (3 excess units) differs from its control in parse state, not styling; it is consistent with path-dependent sublayer staleness but was not isolated.
- With the resolve toggle on (`DIAG_NEON_FIX=1`, patch on) 52/200 sequences show excess units. A sample of 13 (styling-stale and small ones) goes to 0 excess with `c1-diag-reentrant`: `endBuffering` sets the state to idle only *after* the flush handler, so invalidations raised during the flush (sublayer resolution inside validation) are unioned into a set that is then discarded. That is a second buffer bug, exposed by the resolve fix; it is not in the patch (`patches/diag-reentrant-flush.diff`, 2 lines; re-entrancy risk not reviewed). The large parse-state excesses under the toggle were not classified.

## Task 2: Debug abort "location is greater than end"

**Root cause: Neon `RangeProcessor.didChangeContent`.** Not the edit widening, not `NeonSyntaxHighlighter.locationTransformer`, not SwiftTreeSitter's conversion. A change of ≥2,048 units is parsed in the background (the widening delegate makes every keystroke one; a large paste does too). A second change made before that completes is clamped to `processedUpperBound`, which excludes the pending delta (trace, `diag-neon-trace.diff`):

```
mutation={22625, 2048} delta=1  limit=49347 postApplyLimit=49348 contentLength=49348
mutation={47300, 2047} delta=0  limit=49347 postApplyLimit=49347 contentLength=49347   <- real delta -1, clamped to 0
read past limit: location=49348 limit=49347   (ts_parser_parse <- LanguageLayer.didChangeContent <- BackgroundingLanguageLayerTree)
```

So the snapshot limit is short by the pending delta (two inserts: limit 49348, content 49349), or a change beyond the stale bound loses its delta; the tree is then longer than the snapshot and tree-sitter reads past it.

**Release.** The assertion is compiled out and `data(at:)` returns nil, which tree-sitter takes as end of input. No crash, but the parse stops short: the last character is dropped and the document tail is mis-highlighted (8 units in `insertThenDelete` / `twoInserts`), and `processedUpperBound` stays off by the lost delta (unit test: 11 for 10-unit content). This can corrupt highlighting until a later edit reparses the tail.

**Patch** (`patches/neon-c2-0001-*.patch`; 5+/3− source lines, +78 test lines): clamp against `processedUpperBound` plus the deltas of pending mutations.

| test | stock Debug | stock Release | patch Debug | patch Release |
|---|---|---|---|---|
| `insertThenDeleteInOneTurn` (tail) | fail, 8 units | fail, 8 | pass | pass |
| `twoInsertsInOneTurnKeepTheDocumentTail` | fail, 8 | fail, 8 | pass | pass |
| `deletingTheLastCharacterAfterABackgroundEdit` | **abort** (String+Data.swift:20) | pass (no visible tail effect) | pass | pass |
| strict `widenedBackgroundTyping` (opt-in Debug) | **abort** | 770 units | 770 units, no abort | 770 |
| Neon `RangeProcessorPendingTests` (2 new) | fail (limit 11≠12; deletion dropped) | — | pass | pass |

The 770 widened units are the missing sublayer resolution: with both patches plus `DIAG_NEON_FIX=1`, strict widened is equal to fresh in Debug. The ~200 mid-document units the pending tests report (not asserted) are the same family. Widened random sequences (Release, 50 seeds, every edit through the background path): all 50 differ from fresh with either Neon (sublayer family); units wrong in one turn but right in the one-edit-per-turn control: stock 47/50 sequences, both patches 12/50 (not classified further).

The Neon suite (Debug and Release) passes on both patch branches. SwiftTreeSitter's assertion is left as is: it flagged a real caller inconsistency.

## Risks

- Both patches change shared Neon state machines. Only RangeState unit tests, the MacDownKit trial tests, and the strict tests were run, not the full MacDownKit suite or the app.
- The buffer transform over-invalidates replacement text (harmless, small cost). It does not fix the re-entrant flush loss.
- The pending-limit fix trusts that pending mutations complete in order (Neon already asserts this).
