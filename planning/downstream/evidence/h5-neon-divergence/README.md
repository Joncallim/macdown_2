# H5: why Neon still diverges with B1+B2 (branch `dep-trial` only; scratch, nothing pushed or sent upstream)

Follow-up to `../h5-dependency-trials/README.md`. That README says the replacement cases "still differ after `invalidateAll()`, so the parse state itself differs". This diagnosis finds that the state differs because **Neon never re-resolves injections after an edit**. It is not a B1 defect, not a tree-sitter incremental-reparse divergence, and not the edit points.

## Method

- **Base.** Variant B (SwiftTreeSitter `dcdd9465` = B1+B2, tree-sitter 0.25.10) plus Neon `484d6fb9`, both copied into `deps/diag` with trace-only instrumentation (`neon-instrumentation.diff`, `swifttreesitter-instrumentation.diff`).
- **Package.** Neon is used as a path dependency (`package-swift.diff`).
- **Test.** `NeonDivergenceDiagTests.swift` runs the four failing strict cases. For each it:
  - records every root-layer call Neon makes, with the exact text that call read;
  - compares the rendered attributes against a fresh highlighter, per UTF-16 unit;
  - compares Neon's edited `LanguageLayer` against a fresh `LanguageLayer`;
  - replays the recorded calls on a new `LanguageLayer` four ways: points as-is or corrected, and with or without a final whole-document `resolveSublayers`;
  - runs `invalidateAll()`, then a whole-document resolve followed by `invalidateAll()`.
- **Build and commands.** Release with `-enable-testing`. The commands are in `run.sh`. The logs are in `logs.tar.gz` (`run-<case>-<tag>.log` plus Neon/layer traces).
- **Toggles.**
  - `DIAG_NEON_FIX=1` passes `sublayers: true` for edit invalidations in `TreeSitterClient.didChange`.
  - `DIAG_NO_B1=1` restores the stock range merge.

## Results (units differing from a fresh highlighter)

| case | as shipped | + invalidateAll | + whole-doc resolve + invalidateAll | DIAG_NEON_FIX | NEON_FIX + stock merge |
|---|---|---|---|---|---|
| type, then delete a block in one turn | 2 | **0** | 0 | 2 | 2 (1 rejection) |
| replace 600 units | 60 | 60 | **0** | **0** | 60 (rejected) |
| replace with markup removed | 33 | 33 | **0** | **0** | 33 (rejected) |
| widened background typing | 770 | 770 | **0** | **0** | 770 (rejected) |

Layer-level replay of Neon's exact call sequence, compared with a fresh `LanguageLayer`:

| case | replay = Neon's layer | replay vs fresh (as-is) | points corrected | + whole-doc resolve |
|---|---|---|---|---|
| replace600 | identical highlights | 3 extra `markup.raw` captures, inline sexp differs | same as as-is | identical |
| replacePlain | identical | 9 extra captures | same | identical |
| widened | identical | 1 extra / 120 missing | same | identical |
| typeThenDelete | identical | 0 (ranges differ, captures equal) | same | identical |

In every case the block (`Markdown`) tree is identical to a fresh parse, and no node has a bad start point.

## Findings

1. **Neon does not call `resolveSublayers` after any edit.**
   - **Proven** by the trace: `client.validateSublayers set=[24665..<25268]` is followed by no `client.resolveSublayers`.
   - **Why.** In `TreeSitterClient.didChange`, edit invalidations go to `handleInvalidation(_, sublayers: false)`. The sublayer validator only hears about the edit through `contentChanged`, and `RangeMutation.transform(set:)` keeps a valid range whose endpoints lie outside the mutation. After open, the valid set is the whole document (`0..<N`), so an interior edit leaves it fully valid.
   - **Consequence.** The inline sublayer reparses with its edited included ranges. For example, replace600 ends up with one range `24667..<25282` spanning fenced code. Its \`\`\` and "fenced code line" are then captured as inline `markup.raw`:
     - edited `c959795,f` vs fresh `c2c2c2c` at 24743..<24760, plus 2 more repeats;
     - in replacePlain, whitespace lines are inline-styled `c173691`;
     - in widened, 113 spans: inline markup unstyled and code spans mis-styled.
   - **Classification:** Neon sublayer-invalidation bug; the tree is stale because resolve is skipped. Fixing only that (`DIAG_NEON_FIX`) makes all three cases fresh-equal.
2. **B1 is required and correct for these flows.**
   - With Neon's resolve forced but the stock merge, `ts_parser_set_included_ranges` rejects the list (collapsed zero-length plus overlapping ranges), and the divergence stays.
   - With B1 the list merges to 1,265 ranges, equal to a fresh parse, including the markup-removed case.
   - No divergence here is attributable to B1. The vanished-injection limitation did not appear: the stale spanning range is overlapped by new ranges and replaced. This is not proven for an edit whose stale range has no overlapping replacement.
3. **One-turn type-then-delete is a styling-only bug.**
   - The tree and highlights equal a fresh parse.
   - `RangeInvalidationBuffer` accumulated `{24667,31}` from typing, then the −1500 deletion arrived before the async flush. The buffered set is not shifted, so Neon re-styles 24667..<24698 of the new text. The real change is now at 23167, so "- " at 23168..<23170 keeps a stale `c333333,f`.
   - **Classification:** Neon invalidation-buffer bug, fixed by `invalidateAll`.
4. **The bad edit points are not a cause.**
   - **Proven** that the points are wrong: Neon computes `oldEndPoint` from post-edit text (the deletion gets `oldEnd=2500@67:2` = the start point), and the app transformer uses UTF-16 columns where tree-sitter expects bytes.
   - **Proven** harmless here: the replay with corrected points gives identical results.

## Hypothesis / not covered

- Other edit shapes: the valid set fragmented by scrolling, or async (≥2,048 units) single edits outside widening.
- Whether `sublayers: true` is the right upstream fix (cost was not measured).
- The Debug abort in widened (`String+Data` "location is greater than end") was not investigated.
