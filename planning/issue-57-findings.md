# Issue #57 — Open/Save latency, save feedback, and deleted-backing-file recovery

> Baseline: `master` at `36cc44c` (PR #56, EPIC-14B squash-merge), reconciled
> against `epic/14-text-filters` at `90d3472` (pre-existing, unmerged EPIC-14B
> post-review hardening — see §24/§25 of `epic-14-implementation.md`). This
> document is the record for issue #57's own fixes, kept separate from the
> epic-14 log because the issue itself predates and is broader than E14B: it
> covers general Open/Save infrastructure, not text-filter/palette behaviour
> specifically. Where a fix does touch E14B code or invariants, that is called
> out below and cross-referenced.

## Owner summary

1. **What changes for the user?** The command palette (⌘⇧P) opens and becomes
   usable noticeably faster. Saving shows a small "Saving…" spinner while a
   write is genuinely in progress, and a save that fails for a real reason
   (permission denied, disk full, a competing writer) now says so instead of
   leaving the document silently dirty. Closing a window whose file was
   deleted or moved outside the app now labels the button "Save As…" and
   explains why before the destination panel appears, instead of popping an
   unexplained second dialog.
2. **Why now?** Filed during manual verification of PR #56; general
   Open/Save infrastructure, not that PR's own changes.
3. **Main technical approach.** Reproduce first, fix only what the evidence
   supports, and add the missing UI signal (`isSavingActiveDocument`,
   `.saveFailed` banner) that was the real gap behind "no progress
   indication" regardless of the underlying I/O cost.
4. **Main risks/compromises.** The single remaining palette filesystem scan
   (see finding 1) is still synchronous on the main actor; only the
   *duplicate* scan is removed. Manual/Release-app GUI verification of all
   four fixes could not be executed in this session — see "Outstanding gate"
   below.
5. **Deliberately not built.** No change to `FileStore`'s conditional-write
   protocol (three read+hash round trips per save) — that redundancy is a
   deliberate document-safety guard against a racing external writer, not a
   defect, and weakening it is out of scope for a latency/feedback bug fix.

## Symptom 1 — "Open…" is slow from the command palette

**Root cause (confirmed by code inspection, not the window-activation-gap
hypothesis the issue floated):** `CommandPaletteModel.init()`
(`MacDown2/MacDown2/CommandPaletteModel.swift`) called `refreshRows()`
unconditionally, which calls `TextFilterCommandDiscovery.discoverCommands()`
— a synchronous directory listing plus two stat-family syscalls per entry
(`MacDown2/Packages/MacDownKit/Sources/TextFilters/TextFilterCommandDiscovery.swift`)
— **on the main actor**, before `CommandPalettePanel` even has a `contentView`
to show. `CommandPaletteView.onAppear` then called `model.refreshRows()`
again, rescanning the same directory a second time before the palette became
interactive. Both scans sit directly between the ⌘⇧P keypress (or a palette
row click) and the palette becoming usable — the exact "feels unresponsive
before it appears" symptom, and not specific to the "Open…" row itself: every
row was equally delayed.

`NSFilePanelProvider` and `WindowCoordinator.openFile`/`openDocument`
(the plain, non-palette Open path, and what "Open…" itself does once
invoked) were inspected and are **not** the cause: `NSOpenPanel` setup does
no synchronous I/O, and the actual file read (`TabStore.openFileInTab` →
`FileDocument.load()`) already runs inside
`Task.detached(priority: .userInitiated)`, off the main actor. The issue's
own "unconfirmed" hypothesis about a window-activation gap shared with the
palette's own display fix was not reproduced as a separate cause; the
palette's double directory scan fully accounts for the reported symptom.

**Fix:** `CommandPaletteModel.init()` now calls `applyFilter()` (pure,
in-memory) instead of `refreshRows()`. The one real filesystem scan happens
exactly once, from `CommandPaletteView.onAppear`, matching what that
method's own doc comment already claimed ("its one call site is
`CommandPaletteView.onAppear`") but the code did not actually do.

**Tests:** `CommandPaletteModelTests.swift` and
`CommandPaletteStaleOriginTests.swift` had three tests that asserted on
`model.rows` immediately after construction, relying on the removed eager
scan; each now calls `model.refreshRows()` first, matching what a real user
would have triggered via `onAppear` before they could select anything. No
assertion was weakened — each test still proves the same thing it did
before, against the corrected lifecycle.

## Symptom 2a — Save has no progress or failure feedback

**Root cause (confirmed):** the actual write (`DocumentWriter.save`/`saveAs`
→ `FileDocument.saving`/`saveAs` → `FileStore.write`) already runs off the
main actor via `Task.detached(priority: .userInitiated)`, but nothing
observable ever reflected "a save is in flight." Separately,
`WorkspaceError.saveFailed(underlying:)` — the case a genuine write failure
(permission denied, disk full, a losing race against an external writer)
maps to — was reachable and already covered at the model level
(`WorkspaceModelFileTests.saveToReadOnlyDirectoryFails`), but **no view
anywhere rendered it**. A failed save left the document dirty with no
explanation, indistinguishable from Save silently doing nothing.

**Fix:**
- `WorkspaceModel.isSavingActiveDocument` (new, `Workspace` module):
  `true` while a write for the currently active document is genuinely in
  flight — scoped to the actual `documentWriter.save`/`saveAs` call and its
  publication bookkeeping, not time spent waiting on a Save As destination
  panel. Tracked per document ID (`savingDocumentIDs`), following the same
  pattern as the existing `inFlightSaveAsByDocumentID`/`isCreatingDocument`.
- `ContentAreaView`'s document header shows a small `ProgressView` +
  "Saving…" while `isSavingActiveDocument` is true.
- `ContentAreaView` now renders `.saveFailed(underlying:)` as a banner
  (matching the existing `WorkspaceRecoveryRequiredNotice` pattern) with a
  new `FileSaveFailurePresentation` message mapping and a "Retry" button.
  `FileStoreError` has no `LocalizedError` conformance of its own (by
  design — see `FileOpenFailurePresentation`'s doc comment); a
  write-flavoured mapping was added alongside the existing read-flavoured
  one, since "could not be read" is the wrong message for a failed write.

**Tests:** `WorkspaceModelSavingIndicatorTests.swift` (new) covers all four
branches `save()`/`saveAs()` can take — success and failure for each —
confirming the indicator always clears and never gets stuck `true`, the
same risk `WorkspaceModelCreatingDocumentTests.swift` already covers for
`isCreatingDocument`. Verifying the indicator is observably `true` *during*
a slow write (vs. only "clears after") would need a synchronous test hook
into `FileStore`'s write path across an actor boundary; that finer-grained
concurrency test was scoped out as disproportionate to the risk — the
`defer`-based clear is straightforward to verify by inspection and mirrors
an already-trusted pattern in this codebase.

## Symptom 2b/2c — Save "behaves oddly" after the backing file is deleted; closing doesn't offer a plain save-and-close

**Root cause (confirmed):** a document whose backing file is deleted
externally becomes `state == .dirty` with `backingState == .unavailable(_)`
— there is no distinct `FileDocumentState` case for this (by design; see
`FileDocumentState.swift`). `WorkspaceModel.save()` already routes such a
document through `saveAs()` automatically (this was not broken), and
`ExternalFileStatusView` already shows a persistent red banner explaining
"The backing file is unavailable. Save As to keep this copy." with its own
window-correctly-scoped Save As button (this was also not broken).

What *was* broken: `WindowController+Close.swift`'s `presentDirtyCloseSheet`
presented the exact same generic "Unsaved Changes — Save / Cancel / Discard
Changes" alert regardless of `backingState`, and its "Save" button called
the ambient `saveDocument()` → `WorkspaceModel.save()`, which — when the
backing is unavailable — calls `saveAs()`, which presents its panel against
`NSApp.keyWindow` **at the time the panel is presented**, not necessarily
`sender` (the window whose close sheet is running). Every other
close/explicit-origin caller in this codebase was already hardened against
exactly this ambient-resolution hazard during EPIC-14B's post-review passes
(`saveDocumentFromExplicitOrigin()`, `saveWithoutDestinationPrompt()`,
`WorkspaceModel+Saving.swift`'s doc comments) — the close-dialog's Save
button was the one caller that hadn't been. Concretely: clicking "Save" in
the close alert popped a second, unexplained Save As panel; cancelling that
panel left the document dirty with the original alert already dismissed and
no further explanation — the app looked stuck.

**Fix:**
- `presentDirtyCloseSheet` now reads `model.requiresDestinationToSave` and,
  when true, labels the button "Save As…" and changes the informative text
  to explain that the original file is gone before the panel appears —
  turning the destination panel into an expected next step instead of a
  second, unexplained dialog.
- Both `presentDirtyCloseSheet`'s "Save" and `presentConflictCloseSheet`'s
  "Keep My Changes and Save" now call `saveDocumentFromExplicitOrigin()`
  instead of the ambient `saveDocument()`, closing the same window-targeting
  gap the rest of the app's save paths were already closed against. This is
  a **document-safety/window-targeting invariant fix**, not new behaviour:
  it makes the close-dialog's save consistent with the rest of the app
  rather than changing what a successful save does.

**Tests:** `WindowController+Close.swift`'s `NSAlert`/`NSSavePanel`-driven
flow has no existing unit-test coverage (confirmed absent before this
change too — real panels/sheets cannot be driven headlessly, the same
limitation `WindowCoordinatorPaletteOriginTargetingTests.swift` documents
for "Open…"/"Open Folder…"). This fix could not be given new automated
coverage without a larger test-seam refactor (an injectable panel provider
for the close flow) that is out of proportion to a bug fix; it is covered
instead by the manual checklist below.

## Adversarial review pass

An independent adversarial review (8 finder angles: line-by-line scan,
removed-behavior audit, cross-file caller/callee tracing, reuse,
simplification, efficiency, altitude, and repo-conventions) was run against
the diff above before opening the PR. It found four real, confirmed defects
in the fix itself, all corrected here:

1. **Saving indicator used a `Set`, not a reference count.**
   `save(isRetry:destinationPolicy:)` has no reentrancy guard against a
   second, overlapping `save()` for the same document (only
   `inFlightSaveAsByDocumentID` blocks an overlapping *Save As*), and the
   metadata-conflict retry in `reconcileSaveConflict` recurses into a nested
   `save(isRetry: true, ...)` call for the same document while the outer
   call is still unwinding. With a `Set`, whichever overlapping save
   finished first cleared the flag while the other was still genuinely
   writing — reintroducing the exact "looks hung" problem this feature
   exists to solve. Fixed: `savingDocumentIDs: Set<String>` became
   `savingCountByDocumentID: [String: Int]`, incremented/decremented in
   `beginSavingIndicator`/`endSavingIndicator`. Covered by a new test,
   `indicatorStaysTrueWhileASecondOverlappingSaveOfTheSameDocumentIsStillInFlight`.
2. **The close-dialog's explicit-origin routing dropped a resync
   guarantee.** `saveDocumentAsFromExplicitOrigin()` only called
   `externalFileController.synchronize`/`updateTitleAndEditedState()` after
   a completed write — the old ambient `saveDocument()` this replaced called
   them unconditionally, including on a no-op. Once the close dialog started
   calling this function for a backing-unavailable document, cancelling its
   destination panel would skip that resync entirely (no other periodic
   mechanism backstops `synchronize`, unlike `updateTitleAndEditedState`,
   which self-heals via the key-window polling loop). Fixed with a `defer`
   in `saveDocumentAsFromExplicitOrigin()` so every exit path — no active
   document, a cancelled panel, or a completed write — resyncs, matching
   every other Save entry point in this file. This also fixes the same
   latent gap for the palette's pre-existing "Save As…" command, which
   already called this function.
3. **`.fileMissing`'s save-failure message named the wrong thing.**
   `FileStoreError.fileMissing` fires both when the containing folder is
   gone and when the file itself was deleted/moved while its folder is
   untouched — issue #57's own headline scenario — but the message said
   "The file's folder is no longer available." Fixed to name the file, not
   assume the folder.
4. **`WindowController.saveDocument()` became dead code.** Once both
   close-dialog call sites were rerouted to `saveDocumentFromExplicitOrigin()`,
   a repo-wide grep found zero remaining callers of the ambient
   `saveDocument()` — the real ⌘S path already went through
   `saveDocumentFromExplicitOrigin()` via `WindowCoordinator
   +DocumentLifecycle.swift`. Removed rather than left as a
   still-compiling, easy-to-reach-for-by-mistake wrapper around the exact
   window-targeting hazard the rest of this codebase's save paths were
   hardened against.

Two further findings were confirmed as real but deliberately left unfixed:

- **Save As's spinner can clear a little before its own tail bookkeeping
  finishes.** `publishSaveAs`'s active-document identity swap
  (`tabStore.updateActiveDocument` inside `prepareSaveAsDestination`)
  happens *before* `publishSaveAs`'s own `defer` clears the original
  document's entry in `savingCountByDocumentID`. Once the swap lands,
  `isSavingActiveDocument` looks up the *new* (destination-URL-keyed)
  document's ID, which was never recorded as saving, so the spinner can
  read `false` slightly before the remaining recovery-cleanup/session-
  publish/retire-old-lifetime work actually finishes. A correct fix needs
  the "which document ID is this indicator keyed under right now" to be
  visible to and updated by `prepareSaveAsDestination`/`applySaveAs`, which
  are separate functions nested several `await`s deep inside
  `publishSaveAs` — not a local `defer`-adjacent change. Given the actual
  disk write (the part users perceive as slow) remains correctly covered
  and only the fast bookkeeping tail is under-reported, and given this
  exact call chain already carries `planning/epic-14-implementation.md`'s
  own history of multiple P0/P1s found by prior adversarial passes,
  threading that state through by hand was judged a worse risk/reward trade
  than a few milliseconds of early spinner clearing on the successful path.
  Left as a known, accepted limitation rather than a rushed structural
  change to an already extremely delicate pipeline.
- **The close-dialog's button label has a narrow TOCTOU.**
  `model.requiresDestinationToSave` is read once when the alert is built;
  its own doc comment already warns it "is not an atomic routing boundary:
  a backing file can disappear immediately after this property is read."
  If the backing file is deleted while the sheet is still on screen, the
  button can still read "Save" even though clicking it will (correctly and
  safely) route to Save As. The underlying save routing was already
  verified atomic at click time (`saveWithoutDestinationPrompt()` re-checks
  inside the same attempt); only the button's *label* can go stale, and
  only in the narrow window between the alert appearing and the user
  clicking it while an external process deletes the file. Not fixed for
  the same reason `requiresDestinationToSave` itself accepts this
  non-atomicity elsewhere: closing it completely would need re-deriving
  the label at click time inside the `NSAlert` completion handler after
  the fact, which cannot retroactively relabel a button the user already
  saw.

## Deliberately unchanged

- `FileStore.writeLocked`'s up-to-three `readSnapshot` (full read + SHA-256)
  round trips per save (baseline check, pre-publication re-check,
  post-write verification) were profiled and confirmed to be the reason a
  save is not instantaneous for a large file. This is the conditional-write
  protocol that detects a racing external writer and is exactly the
  document-safety invariant `planning/RELEASE_HARDENING.md` §1.3 and the
  epic's non-negotiable invariants require. The fix for "no progress
  indication" is to show that the work is happening (done above), not to
  remove the safety checks that make it take real time.
- The single remaining `TextFilterCommandDiscovery.discoverCommands()` scan
  (now called once instead of twice) is still synchronous on the main
  actor. Making it fully non-blocking (populate app-command rows
  immediately, filter rows asynchronously) would need `discoverTextFilters`
  to become `@Sendable`/async-callable and would change
  `CommandPaletteModel`'s synchronous test contract in
  `CommandPaletteModelTests.swift`. Given the directory this scans
  typically holds a handful of files, and removing the *duplicate* scan is
  the change the evidence actually supports, this was not attempted here —
  flagged as a candidate follow-up if a much larger Commands directory ever
  proves the single scan itself measurably slow in practice.

## Automated evidence (actually executed, this session)

- Package tests: `swift test --no-parallel` (MacDownKit, matching CI's own
  invocation) — **1140/1140 tests across 127 suites pass**, full suite,
  after the adversarial-review fixes above (the extra test is the new
  overlapping-save regression test). `WorkspaceTests` (187/187) and
  `FileCoreTests` (120/120) were additionally run in isolation and 3× under
  full-suite concurrency to rule out the pre-existing flakiness documented
  in CI's own comments in `.github/workflows/ci.yml` (one run flaked on an
  unrelated test under concurrent scheduling; passed cleanly in isolation
  and on three full reruns). A hosted CI run separately hit one flake in
  `recoveryRequiredPublicationErrorSurvivesALaterLocalEdit`
  (`WorkspaceModelRecoveryTests.swift`, a busy-poll barrier test unrelated
  to any file this fix touches) that this session's own full-suite run did
  not reproduce — consistent with the same class of load-sensitive
  flakiness, not a regression from this change.
- App-target tests: `xcodebuild ... -only-testing:MacDown2Tests
  test-without-building`, 115/115 passed (includes
  `WindowCoordinator palette origin targeting`,
  `WindowCoordinatorSaveAsPublicationTests`, `CommandPaletteModelTests`,
  `TextFilterCoordinator`), re-run after the adversarial-review fixes.
- `swiftformat --lint` and `swiftlint lint --strict`: 0 violations across
  427 files.
- `xcodebuild build` for the `MacDown2` app in both Debug and Release
  configurations: succeeded.

## Outstanding gate — manual/Release-app verification not executed

Per `planning/RELEASE_HARDENING.md` §5.3 and this repo's own convention
(see `epic-14-implementation.md` §24: "no interactive session has driven
[the manual UI matrix]. Not inferred passed."), the following require a
real interactive macOS GUI session and were **not** executed in this
session — both `xcodebuild test` against `MacDown2UITests` (failed with
"Timed out while enabling automation mode" — this environment has no
Accessibility/Automation permission granted for UI-test automation) and
the desktop computer-use tool (the user declined the permission prompt)
were attempted and are unavailable here. They are recorded `unverified`,
not inferred passing:

1. Open the command palette (⌘⇧P) repeatedly and confirm it feels
   immediately responsive (no visible delay before the search field is
   focused and rows are selectable).
2. Edit a document large enough that a save takes a perceptible moment
   (or use a throttled/slow disk) and confirm the "Saving…" spinner in the
   header bar appears while the write is in flight and disappears after.
3. Make a save fail for a real reason (e.g. `chmod 555` the containing
   folder), press ⌘S, and confirm the new red "could not be saved" banner
   appears with a working "Retry" button.
4. Delete a document's backing file in Finder while it is open and dirty
   in the app, then close the window: confirm the alert reads "Save As…"
   with the explanatory text, that choosing it presents the destination
   panel bound to *that* window (not another open window — verify with a
   second window open and key), and that cancelling the panel leaves the
   original window open with no further unexplained dialog.
5. Repeat step 4 with two windows open, the *other* window key at the
   moment the close alert's Save/Save As button is clicked, to confirm the
   save/panel targets the closing window, not the key one.
