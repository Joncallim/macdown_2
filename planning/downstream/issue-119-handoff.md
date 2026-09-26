# Issue #119 — External-file behavior, watcher lifetime and performance proof

## Owner summary

External edits must either reload a clean document safely or produce a clear conflict without discarding local work. Renames, deletion and formatter storms must not leave hidden polling, stale callbacks or growing background work. This issue primarily completes real behavior/performance evidence; only demonstrated implementation gaps should change the existing save/recovery design.

Reviewed baseline: `83a79a4572e23a781b2cf370dd2b407fe7409d09`, 2026-09-24. #119 had no comments. Use #88's interactive lane and #120's completed logical-save/close UI when collecting final evidence. Leave E22's selection/editor model untouched; use its final navigation/clamping interfaces.

## Actual implementation and evidence boundaries

Read DocumentFileMonitor, DocumentFileProbe, WorkspaceModel's save publication and WindowController's close flows. DocumentFileMonitor owns a parent-directory handle and, when available, a file handle; it is not accurately described as one kernel descriptor per window. It uses a 150 ms debounce, a further 75 ms missing-file confirmation, bounded parent-watcher recovery and explicit Retry rather than idle polling.

The prober already performs snapshot reads in Task.detached. Request/binding generation guards reject stale publication. They do not prove that cancelled detached work stops or that simultaneous outstanding probes are bounded. Same-parent move search checks cheap physical identity before reading matching candidates; do not regress this into hashing every sibling file. Cross-parent discovery is not implemented by scanning the entire filesystem.

## State and ownership contract

Preserve FileCore/FileDocument as the source/revision authority, DocumentFileMonitor as advisory observations, ExternalFileController as the window-bound reconciliation/intent owner, and the existing conditional save/recovery publication path. Watcher events are hints, never sufficient authorization to overwrite disk or silently discard edits.

Every observation carries binding generation, request generation, expected URL and physical revision. Before publication, verify current document lifetime/recovery epoch and the relevant accepted revision. Rebind, Save As, close or later events invalidate old work. Same-parent moves may be adopted only on unambiguous physical identity. A cross-parent move or ambiguous hard-link identity produces the supported unavailable/recovery path; do not promise automatic relocation that the implementation cannot establish.

A clean document may adopt a verified external snapshot. A dirty document preserves its text and exposes a conflict. Own saves are recognized through accepted revision/publication lineage, not a long wall-clock suppression window that also hides external writes. Keep Mine rechecks actual disk state before conditional publication; Use Disk reads/verifies the current external version, not a stale sheet-time buffer. Missing/unreadable resources do not clear unsaved text.

## Complete real-behavior matrix

For each scenario record starting editor bytes/hash, disk bytes/hash, dirty/backing state, document identity, user action, final editor/disk bytes, recovery state and window state:

- Clean in-place write and clean atomic replacement: real editor reload, current revision and preserved/clamped selection/scroll as specified.
- Dirty in-place/atomic replacement: local source unchanged, visible conflict, no unrequested write.
- Own save: no false conflict; a genuine immediately subsequent external edit is still observed.
- Keep Mine then Save: correct local version published only under the current conflict/conditional-write rules.
- Use Disk: newest verified external version adopted; correct editor/recovery/dirty state.
- Deletion, permission loss and non-regular replacement: readable local source retained; destination/retry guidance; no accidental recreation/overwrite from a stale action.
- Same-parent rename, cross-parent move and ambiguous identity: demonstrate the actual supported distinction, including restoration/retry.
- Formatter storm and rapid repeated replacement: final stable revision wins without stale flicker or unbounded probes.
- Close while debounce, missing confirmation, conflict resolution or recovery publication is pending: no late mutation of a removed window and no data loss.
- Native conflict-close sheet Save/Use Disk/Cancel, including file change/deletion while the sheet is open: exercise the actual NSAlert path using #88, not a direct controller call.

Use a separate filesystem actor/process for external writes and explicit barriers in engineering tests. Do not make arbitrary sleep lengths the only proof of ordering. Final public-UI runs use real files and preserve before/after artifacts. Native focus/modal delivery failures remain blocked evidence until the harness is fixed.

## View-state and text fidelity

Use the E22 authoritative selection/line index for clamping after reload. Test a shorter replacement, deleted selected range, CRLF, tabs, CJK, emoji and combining sequences. Caret/selection must remain a valid current-source range; do not split a grapheme or infer offsets from rendered preview text. Restore scroll only after the new editor layout is ready, using bounded viewport work rather than laying out the entire document.

External reconciliation must preserve supported encoding, line endings, BOM/final-newline semantics and authored bytes under their existing contracts. A dirty local buffer must not be rewritten merely to normalize an externally changed file. FileStore's repeated identity/content checks and recovery lifecycle remain intact.

## Bounded probes and lifecycle tests

Define one active probe plus one replaceable latest pending request per monitor. A shared bounded I/O admission service limits concurrently running snapshot/digest operations across windows; initial worker ceiling four, calibrated in Release. Coalesce newer events into the latest pending request. Cancelling/superseding a request revokes publication immediately, but an in-progress synchronous filesystem call keeps its worker slot until it really drains. Do not spawn a replacement detached task for every cancelled waiter.

Queued work checks current generation before starting; completed work checks it again before publishing. A closed monitor releases queued requests, callbacks and handles. Audit every callback, including contextCallback, on cancel/dispose; the inspected cancel implementation does not explicitly clear that field, so add a lifetime test rather than assuming all closures are released. Partial watcher installation/retry failure must release any new handle and preserve/report the correct health state. Do not mask missing watcher health by returning healthy before both required installations are admitted.

Keep event-driven bounded retry behavior. No recurring full-file digest polling is introduced. Shared folders may still have separate window-bound advisory watchers under the existing architecture; measure them honestly instead of claiming unsupported global deduplication. A larger architectural watcher-sharing change is not required to close an evidence issue unless measured limits demand it.

## Release measurement protocol

Measure 1 MiB and 10 MiB snapshots/digests, same-parent identity search in a large directory, burst replacement, watcher installation/rebinding and 1/10/50-window lifecycle scenarios. Report cold/warm durations, p50/p95/max, file sizes, OS/filesystem/hardware, foreground responsiveness, peak/retained memory, actual descriptor/watcher counts, active/queued probe counts and idle CPU/event activity.

Separate the intentional debounce/confirmation intervals from snapshot/digest processing and UI publication latency. Report the real total user-observed delay too. Instrument main-thread time independently: detached source reads alone do not prove no synchronous read survives in a conflict/close path. The inspected save-conflict reconciliation contains a synchronous readSnapshot call on a MainActor extension; include that path in the audit and move its snapshot work through the same checked asynchronous boundary if a main-thread trace confirms it performs I/O there. Preserve its lifetime/revision checks after the await.

A pass requires no periodic idle scans, no leaked handles after close/rebind, bounded active/pending work, no full sibling-file hashing and no long UI stalls from snapshot work. Calibrate numerical processing targets against the repository's existing performance policy without silently relaxing thresholds. Store raw measurements and a before/after comparison for any optimization. Do not treat one fast unit test as the completed large-file/multi-window Release matrix.

## Implementation order and stop conditions

1. Add deterministic per-scenario tests and lifetime/resource counters behind test/instrumentation seams, leaving product semantics unchanged.
2. Implement bounded probe admission and any proven teardown/off-main gaps. Allowed: FileCore monitor/prober and the narrow ExternalFileController snapshot call paths/tests. No rewrite of conditional saving or recovery schemas.
3. Run the complete GUI matrix after #88/#120 and final E22 selection integration, then the Release performance/lifecycle matrix.
4. Reconcile E18's old manual/performance residuals and #115 using exact evidence IDs, including any stronger superseding tests.

Run strict format/lint, monitor/probe/recovery/save tests, full package tests and Release app build serially. Stop on wrong-version publication, lost local bytes, closing before required recovery acknowledgement, unbounded I/O or a claimed cross-parent capability not supported by evidence.

## Self-review and completion

Review addressed one-watcher versus two-handle terminology, detached-task cancellation not equalling drained work, stale-callback rejection not equalling resource bounds, false own-save suppression, stale Use Disk buffers, cross-parent overclaiming, and synchronous reads hidden in main-actor recovery paths.

#119 closes only with the full real-behavior and measured performance/lifecycle evidence, not with test scaffolding or this document. Environmental blockage is recorded accurately and does not waive a critical matrix row.
