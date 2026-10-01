# Issue #120 — Save As progress, close prompts and Open latency

## Owner summary

A Save As operation must remain visibly in progress while it transfers document identity and publishes recovery/session state. A file disappearing while a close prompt is open must not leave a misleading button or route saving to the wrong window. Open-panel responsiveness must be measured and improved without weakening file safety or replacing the normal Open command with Quick Open.

Baseline: `83a79a4572e23a781b2cf370dd2b407fe7409d09`, 2026-09-24. Architecture only; implement after the relevant E22 work is stable. Read the final save/close interfaces at implementation start. No changes to E22 slices, FileStore's safety checks or save/recovery authority are authorized here.

## Observed code and boundaries

Read WorkspaceModel+SaveState, WorkspaceModel+Saving including applySaveAs/prepareSaveAsDestination, WindowController+Close and NSFilePanelProvider. #120 had no comments.

The saving indicator is reference-counted by document ID. Save As can publish finalReplacement into tabStore before awaiting publishSaveAsSession, acknowledging migration, retiring the old source and retiring writer lineage. Those are genuine remaining operation phases after the active ID changes. Existing retry and concurrency support must not be simplified to one Boolean.

The dirty-close alert chooses Save versus Save As from a snapshot. Its action already uses saveDocumentFromExplicitOrigin; preserve that correction. The panel provider stores a weak optional origin but falls back to NSApp.keyWindow if it becomes nil. 'No explicit origin' and 'explicit origin was destroyed' must not become the same state.

## Logical save operation

Add an opaque `LogicalSaveOperationID` and a MainActor-owned registry in WorkspaceModel. Each record contains an owner lifetime, a set of participating `(documentID, recoveryEpoch)` identities, phase and terminal state. This is presentation/operation bookkeeping; existing SaveContext generation, accepted revision lineage and FileStore publication checks remain authoritative for correctness.

Begin one logical operation at the accepted save boundary. Pass its token through the one permitted metadata retry and every Save As recovery/session step. A retry is a child attempt of the same operation, not a new independent busy flag. Independent overlapping saves have independent tokens. The public saving state is derived from all active tokens involving the displayed document lifetime, preserving reference-count semantics.

Before tabStore publishes a Save As replacement, add the new lifetime to the same token synchronously on MainActor. Then publish the replacement. Keep the old alias until the logical operation ends, so neither identity observes an artificial idle gap. Only the exact token may remove its aliases; a stale completion cannot clear a newer operation or an unrelated document with a reused path. Use recoveryEpoch/lifetime, not filename or current tab index, to prevent identity reuse errors.

Keep the indicator active through writing, recovery finalization, destination publication, session publication, migration acknowledgement, source retirement and writer acknowledgement/retirement as applicable. Finish exactly once using a scoped/deferred terminal path. Cancellation before any write may stop normally; cancellation after a durable file write must finish the existing safe recovery/publication protocol or expose its recoverable pending state, not abandon it mid-transaction.

A failed operation with a durable pending-recovery action is terminal for active progress: clear the spinner and show the existing recovery-required state. Do not spin forever while waiting for a future user retry, or report 'saved completely' just because file bytes reached disk. A recovery retry creates a new active attempt linked to the retained pending action and the current lifetime, without manufacturing a fresh successful save.

## Presentation and reentrancy

Keep phase strings localized and avoid exposing internal phase names to the user. The existing Saving indicator can remain simple, with a separate persistent recovery warning on failure. Do not announce every phase through VoiceOver or add repeated sheets. Existing close gates for pending recovery cleanup remain intact.

Reserve any UI admission before an asynchronous save/panel action can be re-fired. The destination picker is 'choosing a destination', not evidence that bytes are being written; distinguish panel admission from active saving when deriving UI. Two different windows may save concurrently. Tests must assert that finishing one operation does not clear another's busy state.

## Close-sheet wording and routing

Chosen policy: use a stable primary action label, 'Save Changes', for dirty-close prompts whether an in-place write or a destination picker may follow. The explanatory text states that a location may be requested if the original file is unavailable. This avoids adding a file-watcher-driven mutation of a live NSAlert and remains truthful if the backing state changes after presentation. Retain Cancel and Discard Changes with their existing safety semantics. Update catalog and UI expectations together.

The button expresses intent, not a preselected save implementation. On activation, use the existing explicit-origin save path, which revalidates destination availability at execution. Never use the stale needsDestination flag to decide where to write. Keep the existing presented-context checks and conflict reconciliation; if content/lifetime changed, reevaluate the close flow rather than discarding a different document. Cancel must preserve content and restore normal focus. Recovery failure must leave the window open.

Represent panel origin as an enum: applicationInitiated or explicit weak window/lifetime. Resolve an application-level origin once at invocation. An explicit origin disappearing cancels the panel request; it must not fall back to another key window. Complete every panel continuation once on OK, Cancel, close/dispose or presentation failure. Do not keep a dead window alive solely to make a stale action succeed.

## Open-panel measurement and bounded optimization

Instrument command receipt, panel construction, configuration, first presentation and user-visible readiness separately using signposts. Measure Release first invocation after launch and subsequent invocations on a named macOS 26 machine; record median/p95 and event-loop stalls. Historical 110–140 ms construction timings are context, not current proof.

Keep a fresh configured NSOpenPanel per request by default. Do not cache a sheet with old delegates, directory URLs, selected files or security access. The allowed optimization is one idle, nonpresented warm-up allocation after initial UI is ready, immediately released. Ship it only if a controlled cold/warm comparison demonstrates a meaningful improvement without delaying launch or increasing retained state; otherwise record the measured platform cost and omit speculative warm-up. Do not run repeated hidden panel construction or background-thread AppKit allocation.

Give prompt feedback through the existing command/busy affordance where actual measured latency makes it visible. Schedule presentation on the normal main-run-loop path; do not claim Task.yield guarantees a painted frame. Do not remove file checks, suppress errors, auto-select a destination or replace Open with E22 Quick Open. Any remaining significant workflow delay must be classified against the release gate rather than excused solely as 'system overhead'.

## Tests, implementation sequence and stop conditions

1. Add token-registry tests with controllable continuations at each Save As await. Verify old -> new ID transfer while publishSaveAsSession, migration acknowledgement and source retirement are suspended. Existing WorkspaceModelSavingIndicatorTests and Save As publication/recovery tests remain the regression base.
2. Cover nested metadata retry, two overlapping saves, two windows, stale completion, cancellation before/after file commit, source close, destination replacement, failed session write, failed source retirement and a later successful recovery retry. Assert indicator history, actual document state, disk bytes and recovery/session state, not just final false.
3. Wire the registry without changing save semantics. Allowed: Workspace operation bookkeeping/helpers, existing save/retry call sites and tests. Stop if a token is being used to bypass revision/lifetime checks.
4. Apply stable close wording and explicit-origin panel behavior in the app; add real tests for deletion/move while the prompt or picker is open, focus switching and origin destruction. No foreign-window fallback.
5. Run the Open-panel measurement, apply only the bounded demonstrated optimization, and publish raw timings. Execute affected/full package tests, strict format/lint, Release app build and real saving/close/Open journeys through #88.

## Self-review and completion

Review addressed a busy-state gap at active-ID replacement; nested retries clearing a Boolean; stale lifetime aliases; indefinite spinning on queued recovery work; cancellation abandoning a committed save; an explicit weak window silently becoming ambient; and prewarming a reusable panel with stale access/selection state.

The architecture changes progress ownership and truthful UI, not FileStore guarantees. #120 closes only when all three issue areas have implementation/evidence and #115 is reconciled. No timings, GUI behavior or tests are claimed passed by this document.
