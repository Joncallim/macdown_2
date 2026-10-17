# Handoff to Astra (2026-10-18): MostlyText integration + highlighting

Written by Claude (Sonnet) at a bounded checkpoint. **Nothing here authorises a merge to `master`, a release, an upstream submission, or adopting an experimental dependency.** Each statement is labelled with the commit it is about.

## Exact state
| Item | Value |
|---|---|
| `master` | `4aa46bfa` |
| `integration-final` (PR #480, **draft**) | `0d877446` (hosted CI lint, build-and-test, inventory passed on the PR when written; re-confirm on any new head) |
| `dep-trial` (experimental, pushed) | the commit adding this file; parent `b1e97010` (stage C2 checkpoint), before it `4cdbc498` C1, `d11e0d64`, `2c39db7e`, `ea4bc296` |
| `pinyin-ui-tests` (pushed, **not merged, tests never run**) | `39b7dfd2` |
| `checkpoint/janet-integration-bf1a91bf` + tag | preserved handoff checkpoint |
| Worktrees | `/Users/jonathanlim/GitHub/macdown_2` (master), `.../macdown_2-integ` (integration-final), `.../macdown_2-deptrial` (dep-trial); all clean at the checkpoint |
| Open PRs | #480 (draft), #477, #476 (draft), #475, #474 (draft), #473 (draft), #472, #462; each one's relation to `integration-final`: `planning/INTEGRATION_INVENTORY_2026-10-16.md` |
Cleanup record: `/Users/jonathanlim/GitHub/_cleanup-archive/` (deleted branch SHAs, archived orphan sources).

## What is true now (labelled by commit)
- Integration candidate: the Codex lanes, the size-based highlighting fallback (reduce above 8,192 UTF-16 units, restore at or below 6,144 after 2 s idle), gutter and lint fixes. Local gates on `d42f2723`: package 2580 tests/342 suites, MacDown2Tests 393/83, Release app and CLI, native UI 37/37. Hosted CI passed on `c1621581` and later (docs-only since). Release performance suites on `5ccfaf89`: one intermittent failure (63.4 ms vs 50 ms, explained as load-noise outliers; see the inventory addendum), later runs 32/32.
- The fallback is **containment**, not a fix: #203 and #53 stay open. A discarded highlighter's queued validation still costs about 25 ms once after a crossing (measured, inert).
- Dependency findings (scratch, nothing adopted): tree-sitter `ts_lexer_goto` linear scan (patch A, 14 lines; flat reparse versus range count, but not the main cost at app level); the B1/B2 range-merge fix is correct; Neon never re-runs sublayer resolution after edits and mishandles buffered invalidations and the pending-edit bound (the small C1 patches pass their tests in Debug and Release); the dominant keystroke cost at 256 KB is the whole inline-layer reparse with no incremental reuse. Details: `planning/h5-dependency-followup.md`, `planning/downstream/evidence/h5-*`.
- Upstream: tree-sitter's contributing policy forbids agent-opened issues/PRs and agent-written text; `planning/upstream/tree-sitter-lexer-goto/` is a prepared package for a **human** submitter. Not submitted.

## Not done / not proven
- **The Pinyin native IME suite never ran:** the UI runner times out enabling automation mode when the owner is away (3 identical failures; diagnosis, hypothesis and the smallest action in `planning/downstream/evidence/ui-automation-timeout/README.md`). Native CJK coverage so far: none (dead-key only).
- Stage C2 (sublayer resolution) is incomplete: Debug only, the best configuration used experimental toggles, fence open/remove and large-paste cases still wrong, no Release, no baseline performance comparison, no full suite on the patched stack, no independent review (`planning/downstream/evidence/h5-neon-resolve/CHECKPOINT.md`).
- Release gates (signed candidate, notarisation, localisation, compliance): not started, not authorised.
- #476/#477 (diagram theme) conflict with the integration's "neutral light" diagram policy: a product decision for the owner.
- #473/#474 are alternative implementations of areas the Codex lanes already changed; they need a decision.

## Smallest recommended next step for Astra
1. **Owner action first** (nothing else unblocks #480): at CORTANA, unlocked, run the Pinyin suite command in the inventory doc and approve any prompt; merge `pinyin-ui-tests` into `integration-final` only if it passes (fix the tests if they expose real defects).
2. Then re-confirm hosted CI and re-run the Release performance suites on the exact final head, and mark #480 ready for review (it still must not merge without the owner).
3. Experimental highlighting: do **not** continue C2 until the owner decides whether large-document full highlighting is a goal. If yes, the next bounded step is the baseline performance comparison (ordinary documents under 8 KB, Release) for the two small C1 Neon patches only.

## Ownership
Claude stops editing `integration-final` and its worktree once Astra acknowledges ownership (reply in this session or on #480). Claude has made no change to the integration branches since the branch cleanup. The wiki task that follows is documentation only.
