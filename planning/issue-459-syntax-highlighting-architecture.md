# Issue #459 — Syntax-highlighting edit and snapshot architecture

**Status:** source-reviewed architecture and implementation handoff, not a completed fix. No native macOS tests were run for this document.  
**Reviewed baseline:** `master` `52107b389a624a933fe9999bd5b24c0106dff737`, including PR #458.  
**Owning issue:** [#459](https://github.com/Joncallim/macdown_2/issues/459). **Adjacent ownership:** [#203](https://github.com/Joncallim/macdown_2/issues/203) for 1 MB Markdown incremental-parse latency; [#115](https://github.com/Joncallim/macdown_2/issues/115) for release validation; [#148](https://github.com/Joncallim/macdown_2/issues/148) for third-party compliance.

## 1. Owner summary

A mounted-window recovery regression test crashed in SwiftTreeSitter during rapid whole-text replacement. The controller-only recovery tests subsequently avoided the highlighter to isolate recovery behaviour. That test workaround did not fix the highlighting path.

The desired outcome is simple: editing, replacing, undoing, reloading and closing a document must never be undermined by stale syntax highlighting. A failed or delayed highlight must not alter authored text or compromise recovery. Fix the observable causes in the **existing TextKit 2 + Neon + SwiftTreeSitter** architecture, not by replacing the editor or adding a second parser.

The first confirmed source mismatch is a column coordinate expressed in UTF-16 code units where Tree-sitter expects UTF-16 **bytes**. Beyond that, the integration combines coordinates derived from mutable live text with asynchronous immutable parser snapshots, and uses a weakly specified version signal for deciding when to apply completed styling. Those are credible risks but are not yet reproduced defects. The first implementation stage is therefore an **instrumented native reproduction**, not a speculative fork.

**Provisional priority:** P2. A proven Release crash, source loss/corruption, or broken save/recovery is P0; a materially broken core editor with no workaround is P1. Under `planning/RELEASE_HARDENING.md`, any release-relevant P2 must be resolved for #115.

## 2. Baseline, ownership and authority

- `EditorCore.EditorTextSystem` owns the live `NSTextView`, TextKit 2 stack, edit revision, undo, selection and normal text publication. `EditorView.Coordinator` is the edit-binding delegate.
- `Highlighting.NeonSyntaxHighlighter` adapts Neon, maps offsets, applies theme chrome and owns the instance of `TextViewHighlighter`; `SyntaxHighlightStore` caches it by native-tab identity.
- `WindowController` creates per-window editor/highlight stores and disposes them on close. It currently calls `editorStore.evictAll()` before `highlightStore.evictAll()`.
- Pinned Neon revision: `484d6fb9e0c4fb679a1d5f5ddaf2cac2ecf21165` (now at `slsrepo/Neon` after repository redirect).
- Pinned SwiftTreeSitter revision: `cbe31cb3601aa29c1f64b6e4328733511126d6d5` (now at `tree-sitter/swift-tree-sitter`).
- Swift 6 strict concurrency; macOS 26 only; dependencies locked in `MacDown2/Packages/MacDownKit/Package.resolved`. No dependency revision change is authorised by this document alone.
- [Historical E05 architecture](epic-05-implementation.md) `4.5 says `Point.column` is a UTF-16 *code-unit* column. That is incompatible with core Tree-sitter and the pinned Neon's `InputEdit` byte offsets. **This design supersedes only that historic geometry specification and the related test expectations.** Keep the historic document as provenance.

### Evidence grading

| Finding | Grade | What it actually establishes |
|---|---|---|
| Test host aborted with `location is greater than end` during rapid replacement | Reported runtime observation from the round-11 reviewer | Reproduce on real mounted highlighter before diagnosing root cause |
| Host `Point.column` = UTF-16 units; Neon constructs UTF-16 byte positions | **Confirmed source contract mismatch** | Correct with failing-before real-geometry tests |
| `willProcessEditing` can see modified text; Neon derives `pendingOldPoint` through the live transformer | **Confirmed call-path design; effect unproved** | Test whether actual old endpoint comes from the wrong snapshot |
| Neon async one-phase validator does not recheck version after `await` | **Confirmed source defensive gap; effect unproved** | Delayed-token regression and version proof required |
| Host line-offset cache invalidates using an edit revision that may advance after text-storage callbacks | Source-visible ordering risk | Test same-length newline moves and multi-range edits |
| Eviction discards highlighter while work may remain queued | Source-visible lifecycle risk | Prove late-callback behaviour before changing ownership |
| Pinned SwiftTreeSitter's invalid read asserts in Debug and returns `nil` afterward | Confirmed dependency behaviour | Not evidence that Release highlighting stays correct |

No application fix, dependency patch, successful native test, or Release safety conclusion is credited by source inspection alone.

## 3. User journeys and invariants

A user can type inside a fenced Markdown code block; do Replace All, format the whole file or undo; accept external changes; switch syntax modes; and close/reopen a native tab while parsing. The current text must remain complete and immediately editable. Syntax colour may temporarily lag, but eventually corresponds to **the text, grammar and editor instance actually visible**. Malformed or oversized input may fall back to plain text without making source or recovery unsafe.

These are non-negotiable:

1. `FileDocument` / `WorkspaceModel` remain the authority for text state, dirty state, saving and recovery. Highlighting is derived presentation and **cannot write authored text** or create a competing copy of it.
2. `NSRange` and edit lengths are UTF-16 **code units**. Tree-sitter's input byte offsets and `Point.column` are bytes in this UTF-16LE parser pipeline. All values in one `InputEdit` must use compatible units.
3. `startPoint` and `oldEndPoint` refer to the **before** snapshot. `newEndPoint` refers to the **after** snapshot. The immutable edit geometry and corresponding text snapshot move through the async parser in the same order.
4. A style result is usable only for the originating document/text-system identity, text revision and grammar generation; cancellation alone is insufficient without checking a result at its publication point.
5. The app cannot block ordinary typing waiting for a background parser; a bounded syntax fallback must be possible.
6. No new server, telemetry, hosted parser, user-facing string or changes to file encoding/line endings. No broad editor/refactoring work based only on an unproved race.

### Dependency direction

`MacDown2 app → Highlighting → EditorCore / Themes / pinned Neon & SwiftTreeSitter`. The app may coordinate lifecycle; Highlighting owns parser integration. Do not make `EditorCore` import Neon or move editor persistence into Highlighting. A new shared public protocol is not justified without a demonstrated need.

## 4. Existing data flow and exact hazards

```text
Workspace / FileDocument  <-->  EditorView binding
                                     |
                               EditorTextSystem
                               TextKit 2 / NSTextStorage
                                     |
                          NSTextStorageDelegate events
                             willProcess / didProcess
                                     |
                            Neon TextViewHighlighter
                        range+delta / live point callback
                                     |
                        TreeSitterClient / RangeProcessor
                                     |
               immutable ContentSnapshot(string, processedLimit)
                                     |
                  BackgroundingLanguageLayerTree worker
                                     |
                  parser / nested-language sublayer query
                                     |
                       async token / validation result
                                     |
                        TextKit rendering attributes
```

**Boundary A — coordinate units.** The [host transformer](../MacDown2/Packages/MacDownKit/Sources/Highlighting/NeonSyntaxHighlighter.swift) ends with `Point(row: row, column: clamped - lineStart)`. Pinned [Neon edit construction](https://github.com/slsrepo/Neon/blob/484d6fb9e0c4fb679a1d5f5ddaf2cac2ecf21165/Sources/TreeSitterClient/TreeSitter%2BExtensions.swift) multiplies `NSRange` offsets by two but passes points unchanged. Thus the current edit's point columns are under-scaled. Existing [`LocationTransformerTests`](../MacDown2/Packages/MacDownKit/Tests/HighlightingTests/LocationTransformerTests.swift) assert those under-scaled columns.

**Boundary B — time of observation.** Pinned [Neon's storage delegate](https://github.com/slsrepo/Neon/blob/484d6fb9e0c4fb679a1d5f5ddaf2cac2ecf21165/Sources/Neon/TextStorageDelegateBuffer.swift) calls `client.willChangeContent` from `textStorage(_:willProcessEditing:...)`, an edit-**processing** callback rather than a guaranteed pre-mutation snapshot hook. [`BackgroundingLanguageLayerTree`](https://github.com/slsrepo/Neon/blob/484d6fb9e0c4fb679a1d5f5ddaf2cac2ecf21165/Sources/TreeSitterClient/BackgroundingLanguageLayerTree.swift) derives a single pending old point using the host's live text callback. The post-edit point is later derived through that same live callback. Newline edits, interleaved updates and queued parse snapshots can therefore demand incompatible before/after geometry. Determine this empirically before proposing an upstream fix.

**Boundary C — delta semantics.** In [Neon `TextViewHighlighter`](https://github.com/slsrepo/Neon/blob/484d6fb9e0c4fb679a1d5f5ddaf2cac2ecf21165/Sources/Neon/TextViewHighlighter.swift), `didChangeContent` computes `adjustedRange.length = reportedRange.length - delta`. Apple's delegate documentation describes `editedRange` in original-string coordinates, but the actual TextKit 2 event must be measured: do not assume either side's interpretation correct without insert/delete/replace/batch probes.

**Boundary D — snapshot limits.** [Neon `TreeSitterClient`](https://github.com/slsrepo/Neon/blob/484d6fb9e0c4fb679a1d5f5ddaf2cac2ecf21165/Sources/TreeSitterClient/TreeSitterClient.swift) captures a `ContentSnapshot` with a processed-prefix limit, while its point transformer may still read mutable editor text. [SwiftTreeSitter `String+Data`](https://github.com/tree-sitter/swift-tree-sitter/blob/cbe31cb3601aa29c1f64b6e4328733511126d6d5/Sources/SwiftTreeSitter/String%2BData.swift) aborts Debug at `byteOffset / 2 > limit` and returns `nil`. Normal EOF at exactly the limit is distinct from an out-of-limit request. The cause could be stale parse geometry, legitimate prefix parsing, or something else; capture the request before classifying it.

**Boundary E — stale async styling.** Pinned [`TokenSystemValidator`](https://github.com/slsrepo/Neon/blob/484d6fb9e0c4fb679a1d5f5ddaf2cac2ecf21165/Sources/Neon/TokenSystemValidator.swift) checks the content version **before** awaiting tokens and does not recheck **after**. Its [three-phase equivalent](https://github.com/slsrepo/Neon/blob/484d6fb9e0c4fb679a1d5f5ddaf2cac2ecf21165/Sources/Neon/TextSystemInterface%2BValidation.swift) does recheck. The version for `NSTextStorage` is `hashValue` in [`PlatformTextSystem.swift`](https://github.com/slsrepo/Neon/blob/484d6fb9e0c4fb679a1d5f5ddaf2cac2ecf21165/Sources/Neon/PlatformTextSystem.swift), not an explicit incrementing edit generation. Test its behaviour instead of declaring it monotonic.

**Boundary F — teardown.** [`WindowController`](../MacDown2/MacDown2/WindowController.swift) evicts editor systems before highlighters. The host's `tearDown()` drops the Neon highlighter, while pinned Neon schedules async work. The source does not prove every late callback is cancelled or unable to style an old text view; test closed tab/grammar-switch cases.

## 5. Target design and decisions

### D1. Fix host byte geometry without changing app ownership

Keep the existing `SyntaxHighlighting` API, the per-tab store and the cached line-start table *where correct*. In `NeonSyntaxHighlighter.locationTransformer`, calculate:

```swift
let columnInUTF16Units = utf16Offset - lineStartUTF16
let columnInUTF16Bytes = 2 * columnInUTF16Units
return Point(row: row, column: columnInUTF16Bytes)
```

For example, `"a\n😀b"` places `b` at UTF-16 offset 4, with row 1 starting at offset 2: the correct core parser `Point` is `(row: 1, column: 4)` **bytes**, not the current `column: 2`. Check arithmetic/`UInt32` conversion at the valid-size boundary; never silently wrap. Existing tests must be updated **after** a discriminating failing-before expectation is added.

**This fixes unit conversion, not temporal snapshot ownership. Do not close #459 on D1 alone.**

### D2. Native diagnostic spike decides whether the parser API must change

Build a small mounted `EditorTextSystem` + actual `NeonSyntaxHighlighter` test fixture, without `WindowController` and the recovery controller. Install the real TextKit 2 stack, highlighter and grammar. Capture **test-only** data for each edit stage:

- synthetic test document ID; an increasing edit number and grammar ID;
- before and after UTF-16 lengths, line starts, and range/delta delivered by both storage callbacks;
- `startPoint`, `oldEndPoint`, `newEndPoint`, their byte positions and expected before/after snapshots;
- parser `ContentSnapshot` length and processed `limit`, requested `byteOffset`, text revision and queued completion;
- whether the final attributed style was applied or dropped.

No user document text, test diagnostics or private content leaves the process. A test may use a breakpoint/instrumented dependency checkout to capture `String.data(at:limit:...)` arguments without modifying the production library.

First run: insert/delete/replace (including equal-length newline movement), replacing the entire document with empty and nonempty text, undo/redo, multi-range Replace All and an embedded-language Markdown fence. Verify the exact AppKit callback range semantics against the before/after strings. Then force a controlled ordering in which a whole-text replacement happens while the parser owns an earlier snapshot. Persist a deterministic mutation transcript and first failing trace. Fixed sleeps alone are not proof.

**Stop condition:** if this shows correct old/new geometry cannot be supplied through Neon's current public callbacks, escalate before implementing a parser bridge change. The next design must specify the smallest necessary dependency change.

### D3. Snapshot-coherent edit transactions, conditional on D2 evidence

The required conceptual invariant is:

```text
before text snapshot + after text snapshot + actual NSRange/delta
    -> derive start and old-end points from BEFORE
    -> derive new-end point from AFTER
    -> create one immutable InputEdit + after-content snapshot
    -> queue them together in edit order
    -> parse the captured content
    -> accept styling only for the current text and grammar generation
```

A narrowly pinned Neon fix that owns previous/current snapshots is preferable to having an app-level mutable transformer service reconstruct old text from a new `NSTextView.string`. The dependency may require an explicit pre-edit hook, versioned snapshot or safe resynchronisation API. These are **options, not authorisation** to fork today. Preserve the original source of truth in EditorCore, keep all AppKit access on `MainActor`, and move only immutable/`Sendable` snapshots to background parsing.

Capturing a full Swift `String` every keystroke could regress responsiveness and memory; seek existing snapshot reuse or bounded incremental line geometry, and measure before accepting. A full parser reset is at most a bounded recovery from proven invalid geometry, not the standard keystroke path (see #203). An unavailable parser fails closed to editable plain text plus theme chrome.

### D4. Protect async token publication if a real stale-result test fails

Each async token result must carry or be checked against: editor/text-system identity, content revision and language/highlighter generation. Compare after the final `await` and before styling; a text hash alone is not a proven monotonic content generation. Cancellation is useful to reduce work, but a generation check is still required because queued completions can outlive cancellation.

The natural repair is at Neon's one-phase validation boundary, matching the existing three-phase post-await pattern, **provided the generation actually tracks mutations**. If it does not, require a small, explicit version mechanism; don't add an unrelated actor or replace TextKit. Do not commit a dependency fork until a failing regression proves the target API or the upstream fix is clearly required.

### D5. Tear down in ownership order if proven necessary

A highlighter must stop being able to publish to a text system before that text system is disposed. Test in-flight parsing on native-tab close, window close and language switch. If a late completion or retained object is observed, change the minimum host/upstream teardown path: highlighter quiescence and generation invalidation precede editor disposal; a callback after disposal fails safe. Never block the main actor to wait for a worker queue to drain.

## 6. Failure, privacy, performance and compatibility

| Case | Expected outcome |
|---|---|
| Snapshot read outside processed prefix | Find actual mismatch/EOF semantics; no normal Debug abort or false-success highlighting |
| Rapid edits / whole-document shrink | Drop stale results and eventually show correct syntax or plain text |
| Unknown language / grammar error | Existing plain-text-with-chrome behaviour, no content change |
| Late parse after tab/window close | No crash, stale paint, or retained view graph |
| Large or pathological Markdown | Responsive editing; #203 owns unmet 1 MB incremental latency |
| External change while dirty | Existing conflict, save and recovery semantics remain untouched |

**Security:** no network services, external executables, telemetry, production logging of text, or permission changes. **Source fidelity:** no changes to encoding, BOM, line endings, undo semantics or recovery. **Accessibility/localisation:** no new strings or controls; verify no caret, selection or theme regression. **Export:** exact text remains authoritative; colour is derived presentation. A dependency update must be pinned and accompanied by `Package.resolved`, `compliance/inventory.json` and #148 evidence.

## 7. Test matrix

All new package tests use Swift Testing. Every implemented fix requires a **test that fails on the pre-fix source and passes on the fix**; a test that passes both versions is a regression guard, not proof.

| ID | Test | Acceptance |
|---|---|---|
| T1 | Transformer vector tests: ASCII, CJK, emoji/surrogates, LF/CRLF, trailing newline, end offset | Exact UTF-16-byte columns and row count; no old code-unit expectations |
| T2 | Mounted highlighter: insertion, deletion, replacement and unchanged-length newline movement | Native callback ranges, deltas and before/after `InputEdit` geometry agree |
| T3 | Whole-document empty → large → short → empty cycling | No Debug abort; capture formerly invalid read/limit if it occurs |
| T4 | 1 MB Markdown with embedded Swift/JSON, parse queued while document changes | No mixing of old snapshot coordinates and new text |
| T5 | Two or more same-length multi-range replacements | Cache sees correct newline positions throughout; current result eventually styled |
| T6 | Forced asynchronous completion followed by edit/grammar switch | Old tokens never paint current content |
| T7 | Window/tab close/reopen during pending parse | No late paint, exception, retained text view, or wrong highlighter identity |
| T8 | Undo/redo, IME composition, external reload, Finder move, failed-close retry | Exact current source, recovery and dirty state preserved |
| T9 | Unrecognized grammar/parser failure | Editable text with safe no-syntax fallback |
| T10 | Release typing and 1 MB parse/highlight measurements | No material main-actor regression; report #203 separately |

Use a synthetic adversarial corpus: zero-length file; trailing newline; CRLF; length-preserving newline move; emoji after multiline content; very long lines; nested fences; 1 MB Markdown; replace-all; quickly changing grammars; close during background sublayer resolution; large-to-small replacement and repeated undo/redo. When concurrency timing is involved, use a controlled ordering barrier or captured deterministic scheduling seam in tests. Seeded stress replay supplements the controlled test, not replaces it.

**Native execution** is required for the TextKit 2 paths. Reuse the repository's locked toolchain and pass real test names discovered in the project:

```sh
cd MacDown2/Packages/MacDownKit
swift test --force-resolved-versions --filter LocationTransformerTests --no-parallel
swift test --force-resolved-versions --filter HighlightingTests --no-parallel
swift test --force-resolved-versions --no-parallel
swift test -c release --force-resolved-versions --filter HighlightPerformanceTests --no-parallel
cd ../../..
cd MacDown2 && xcodegen generate && cd ..
MacDown2/scripts/pin-xcode-package-versions.sh
xcodebuild -project MacDown2/MacDown2.xcodeproj -scheme MacDown2 \
  -destination 'platform=macOS' -parallel-testing-enabled NO \
  -onlyUsePackageVersionsFromResolvedFile test
xcodebuild -project MacDown2/MacDown2.xcodeproj -scheme MacDown2 \
  -destination 'platform=macOS' -configuration Release \
  -onlyUsePackageVersionsFromResolvedFile build
swiftlint lint --strict MacDown2
swiftformat --lint MacDown2
```

Record first-run failures, exact SHA, commands, macOS version, output and follow-on reruns. Unexecuted UI tests are `unverified`, never inferred to pass. If required by the final regression campaign, repeat **three serial full package and three serial full app-target runs on the final merged source head**; the earlier #457 evidence does not cover a source change after it. Manual native Release dogfood covers large Markdown, syntax changes, external replacement, undo, close/reopen and source fidelity.

## 8. Bounded implementation slices and permitted files

**S0 — Diagnose native geometry and invalid read.** No production changes. Add a mounted-editor/highlighter diagnostic test under `Tests/HighlightingTests/` or existing app-level test infrastructure, tracing real range/limit/geometry under controlled editing. Deliver the first failing test/transcript, classification of `location > end` and a decision whether source-only D1 is sufficient. **Stop** if upstream hooks are required; report the narrow interface needed.

**S1 — Correct byte point columns.** Expected production edit: `Sources/Highlighting/NeonSyntaxHighlighter.swift`; tests: `LocationTransformerTests.swift` and geometry fixture. First show failure under current source. Update point units and tests; run relevant package and mounted tests. **Stop** if fixes require replacing mutable snapshot semantics: hand off to S2 gate, do not fake old points.

**S2 — Repair snapshot coherence only if S0 proves it broken.** Only Highlighting integration/tests initially. If public Neon APIs are insufficient, propose **one** small, version-locked upstream patch (old/new snapshots, ordered edit geometry), with exact dependency compliance changes and a minimal reproduction. No new parser, no complete editor rewrite, no routine full-document parse per keystroke. **Escalate** before altering editor publication or dependency boundaries.

**S3 — Repair proven stale style or teardown.** Narrow version check/cancellation and, if required, highlighter-before-editor eviction. Tests must force an old queued result into a replaced text system or changed grammar and show failing-before evidence. Do not add lifecycle machinery without reproduced need.

**S4 — Release evidence and closure.** Complete targeted package tests, full package/app target, lint/format, pinned Release build, manual dogfood and prescribed serial convergence runs on one final SHA. Reconcile source fidelity, #115 release ledger, any dependency #148 work and separately measured #203 performance. No broad new review campaign after passes converge.

**Likely owned files:** `NeonSyntaxHighlighter.swift`; `SyntaxHighlightStore.swift` only if justified; `LocationTransformerTests.swift`; new mounted-highlighter fixture; `WindowController.swift` only for demonstrated disposal ordering. **Read-only until escalation:** `EditorCore` source, `Workspace`, `FileCore`, recovery code, parser dependencies, compliance manifests and the historic E05 architecture document.

Each implementing PR must say what changed, why, how it works, what to test, risks and limits, and verification with the exact source SHA.

## 9. Definition of Done / stop condition

Close #459 only after:
1. The original failing Debug call is reproduced and explained, then no longer aborts a real mounted editor under the recorded edit replay; any expected EOF handling is classified accurately.
2. Coordinate fixes and any snapshot/lifecycle repair have discriminating failing-before regressions; stale results never override current syntax.
3. Full relevant Debug and Release evidence, source/recovery fidelity, no material typing regression and any final serial-runs requirement are satisfied on one final source commit.
4. Separate #203 performance debt remains explicitly tracked (or separately measured and closed); #115 owns overall release clearance.
5. Remaining fail-safe P3s or test limitations are documented rather than triggering another open-ended review loop.

**Architecture approval does not authorise code changes outside the bounded ownership described above, and this document does not claim implementation/test completion.**
