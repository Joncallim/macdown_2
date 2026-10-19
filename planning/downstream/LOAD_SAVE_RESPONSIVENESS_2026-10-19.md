# Keep document loading and save recovery responsive

## Owner outcome and current evidence

Opening an automatically detected UTF-16 file must not block the UI during its detection scan or steal focus from a newer open request. Folder setup should not immediately repeat its completed workspace scan on activation. Save-conflict recovery should perform file reads, decoding and hashing away from the UI while preserving current edits and save ownership.

These are concrete source-derived defects in existing paths, not a measured explanation of every slow load or save. The 1 MB parser benchmark does not measure file-open latency. Preferences preservation is a separate correction recorded under #53.

Baseline: master `4aa46bfa6b91bf1c1d218b9b1f67480312f66396`; this branch starts at settings correction `91e62f8f` and retains the integration staging history. Independent source review confirmed the three areas below. Existing E18 file fidelity, E22 index/search authority, release-hardening and epic-standard contracts remain binding. No new dependency, file permission, preview authority, format guess, highlighting cutoff or publishing authority is introduced.

## Slice 1: automatic encoding detection

Allocate the open-request generation once at public entry. A private helper carries that identity through the existing single automatic-encoding retry. The synchronous detector's complete read and scan runs inside a detached user-initiated task, just as the existing document load does. Explicit encoding skips automatic detection. Real read/decode errors remain errors. Every suspension before publication is followed by the existing duplicate-tab admission check. An older request may finish opening its own tab, but cannot activate it over a newer open.

The only new internal seam is an optional Sendable callback immediately before detached detection, used to hold that real operation in tests. Production leaves it unset. Tests hold A at detection, complete B on the main actor, and then release A. Both the UTF-8-with-NUL and failed-UTF-8 branches must preserve B's focus and decode A correctly. Additional controls cover explicit encoding and a second open of A completing before the original detection returns. Fixtures use private temporary files and recovery stores.

This slice removes UI-thread work and the retry identity error. It does not eliminate repeated reads, change native-window publication timing, or claim a measured end-to-end loading improvement. Completion requires regressions, strict checks, independent review and final combined-candidate validation.

## Slice 2: workspace index freshness (contract pending implementation)

Record a successful initial rebuild only when its root/request is still current and the window remains open. Activation may then use the existing throttle. Explicit mutations continue to bypass it. Stale, failed or cleared-root completion must never mark a different root fresh or publish old folder-search scope. Keep the existing ordering that supplies search with the completed index. Tests must control/count walks and exercise superseded and cleared roots before completion.

## Slice 3: save-conflict snapshot reads

Pass the original save context through conflict recovery. Require the latest save and its original document lifetime before starting and after an off-main read. A tab switch alone does not cancel it. Before applying any result, re-fetch the owning document and establish its baseline, encoding, pending revision and backing-state lineage; never overwrite newer local text with a captured value. Recheck ownership after recovery persistence.

Admission is baseline-compatible: last-known revision, restored baseline hash, pending external revision, backing state and encoding must still equal those captured before the read. Ordinary newer edits and edit/undo remain admissible when the live state is dirty or prompting-close; reconcile the returned disk snapshot against that live text and conditionally retry it, matching the existing behavior that reconciles current edits after the first write fails. A changed baseline, destination/lifetime or newer save makes the old result obsolete. A changed still-dirty state without an admitted lineage receives a relevant file-changed failure rather than silently claiming a save. A clean externally superseding reload remains untouched. Failed reads likewise publish only while the original save/lifetime and compatible lineage remain relevant. After conflict recovery persistence, publish an unresolved-conflict error only if the reconciled snapshot still owns the current state.

Equal lineage values cannot distinguish every external-state sequence that returns to identical values (an ABA sequence). This bounded policy does not claim to identify exclusively local editing history; it preserves live text and conditional on-disk publication, and rejects directly observed changed-baseline reloads. It introduces no new external-state revision or automatic overwrite authority. An internal optional Sendable callback after the detached snapshot read allows deterministic tests to hold its result; production leaves it unset. Preserve one metadata-only retry, encoding override, destination policy and conditional publication.

Tests must hold a real detached snapshot read and exercise typing, edit/undo, another tab, newer saves, external reload, close/reopen, and destination changes. Safe completion includes preservation of file bytes, live text, recovery and relevant errors. Broad preview-folder permission decisions are unrelated to these bounded corrections.

## Stop conditions and remaining gates

Stop if a change requires destructive reset, weaker fidelity, a new file authority, concurrent heavy builds or a new cross-module dependency. Keep production pins and the 8,192 UTF-16 fallback. No merge to master, release or signing. Actual combined Release performance, hosted integration, native/manual coverage and owner acceptance remain required; #53 and #203 stay open.
