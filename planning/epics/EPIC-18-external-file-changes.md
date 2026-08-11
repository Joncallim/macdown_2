> **Title:** [EPIC-18] Live external-file changes: watcher, auto-reload, conflict flow
> **Labels:** `epic`, `foundation` · **Milestone:** M4 — Workspace & formats · **Depends on:** E01, E03 (as built), E04

## Context

Added at the mid-point check-in (#28): live external-file changes are a core
document-lifecycle capability required before sustained dogfooding — not a
speculative extra. FileCore now owns the external-file monitor, immutable
snapshot probe, and document-reconciliation path. The app binds that monitor
per native document window, re-arms it after replacement/move/parent recovery,
and presents the existing conflict state without creating a second conflict
system. Local implementation and validation are review-ready; sustained
dogfooding and hosted CI remain publication gates.

## Required user behaviour (from #28 §4)

- **Clean document** + external change → the editor updates promptly, no
  reopen or manual refresh; cursor/selection and scroll are preserved where
  possible — no unnecessary jumps.
- **Dirty document** + external change → local edits are never silently
  overwritten; the document enters `.conflict` and the user gets a safe
  resolution path (keep mine / use external / cancel — the existing
  `ConflictResolution` model).
- **Self-saves** are ignored/coalesced: MacDown 2's own writes never produce
  a false conflict.
- **Atomic saves** by other apps (write-temp + rename-over-original) are
  detected reliably.
- **Deletion, rename/move, permission loss, rapid repeated saves** are
  surfaced predictably — a state or subtle status UI, never a crash, silent
  blank, or data loss.
- Subtle status UI where useful; clean automatic reloads are not interrupted
  by dialogs.

## Scope

- Document watcher inside the **FileCore boundary** with a narrow interface
  into Workspace/UI. Evaluate `DispatchSource` (vnode) vs
  `NSFilePresenter`/file coordination: a plain vnode source on the file
  misses atomic-replace (the watched inode goes away) unless re-armed on the
  parent directory — whichever mechanism is chosen must pass the
  atomic-replacement test below. Occasional mtime polling alone is not
  acceptable.
- Watcher lifecycle tied to the document: armed on open/save-as, re-armed
  after rename detection, torn down on close/window teardown
  (`windowWillClose`), cancellation-safe under Swift concurrency.
- Debounce/coalesce rapid external writes; skip no-op notifications
  (compare modification date + size, or content hash, before reloading).
- Self-save suppression integrated with `FileDocument.save()`/`saveAs(_:)`
  (e.g., expected-mtime bookkeeping around our own writes).
- Reload path preserves editor state: capture selection/scroll from
  `EditorTextSystem`, apply the new text via a **new dedicated FileCore
  transition** (e.g. `reloadedFromExternal(text:modificationDate:)`) that
  sets the text, refreshes `lastKnownModificationDate`, and leaves the state
  `.clean`; then restore selection/scroll clamped to the new length.
  `updatingText(_:)` is **not** that path — it deliberately marks a `.clean`
  document `.dirty` (user-edit semantics), which would make an automatic,
  disk-matching reload appear dirty and trigger bogus close prompts. Add a
  regression test asserting a clean reload ends `.clean`.

## Deliverables

1. Watcher + document integration in FileCore/Workspace, per-window wiring
2. Conflict UI (sheet or subtle banner) driving `resolveConflict(_:)`
3. Unit + integration tests (below); UI test for the dirty-conflict flow

## Acceptance criteria (minimum tests from #28 §4)

- [x] Clean document reloads after an external edit
- [x] Dirty document enters `.conflict` and preserves local text
- [x] Application save does not trigger a false external conflict
- [x] Atomic replacement (temp file + rename) is detected
- [x] Deletion and rename/move are surfaced safely
- [x] Rapid external writes are debounced/coalesced
- [x] Selection and scroll preservation verified at the mounted AppKit editor seam

The UI suite covers clean reload, dirty-conflict resolution, and conflict-close
using the disk version. `XCUIElement` does not reliably expose an
`NSTextView`'s UTF-16 selection or clip-view offset, so that exact viewport
contract is exercised by deterministic `EditorTextSystem` tests with a mounted
`NSScrollView`, not a timing-sensitive accessibility assertion.

## Out of scope

Directory-tree watching for the folder browser (E09 owns the tree UI; share
low-level plumbing if convenient). Merge/diff UI for conflicts (v1.x
candidate). iCloud/OneDrive-specific coordination beyond what file
coordination gives for free.

## Notes

This is a data-loss-sensitive subsystem: correctness beats elegance
(#28 §5). Keep the watcher event → document mutation path synchronous and
testable; IO and event sources live at the edges like the rest of FileCore.
