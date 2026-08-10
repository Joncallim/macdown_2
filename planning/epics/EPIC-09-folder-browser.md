> **Title:** [EPIC-09] Folder browser: lazy file tree, FS watching, CRUD
> **Labels:** `epic`, `workspace` · **Milestone:** M4 — Workspace & formats · **Depends on:** E01, E02, E03

> **Status:** Implemented and merged in PR #38. The folder browser is now part
> of the MacDown 2 application, including the lazy tree, directory watching,
> filtering, drag/drop, and recoverable CRUD described below.

## Context

The sidebar's other half (D2). Opens a folder as the workspace root; files open
in tabs (E03). Unsandboxed (D7) but modeled on security-scoped URLs so future
sandboxing is additive.

> **Amended at #28:** the sidebar is per window (as-built E03) — the folder
> root is per-window state, and "opens in tab" means a new native tab in the
> same window's tab group via `WindowCoordinator` (which already dedupes).
> The `DispatchSource` watching in this epic covers the **directory tree UI
> only**; watching *open documents* for external changes (reload/conflict) is
> **E18** — share low-level watcher plumbing if convenient, but E18 owns the
> document-lifecycle semantics and must not depend on this epic.

## Scope

- `FileTree` target: `FileTreeModel` — lazy children loading on expand,
  folders-first sort option, hidden-files toggle
- FS watching via `DispatchSource` on expanded directories (coalesced; re-scan
  on window focus); external create/rename/delete reflected < 1 s
- CRUD: context menu + keyboard — new file/folder, inline rename, duplicate,
  move (drag within tree + drag in from Finder), delete to Trash with confirm
- "Supported files only" filter toggle (uses FileFormat registry)
- Click opens in tab (single/double per pref); "Reveal Active File" command
- Root switching via Open Folder… ⌘⇧O + recent roots list

## Deliverables

1. FileTreeModel + SwiftUI outline view in the sidebar
2. Unit tests: tree diffing on FS events, sort/filter, CRUD against temp dirs
3. Perf test: 10k-entry folder expand < 200 ms
4. XCUITest: create file in sidebar → opens in tab

## Acceptance criteria

- [x] External `touch new.md` in an expanded folder appears < 1 s
- [x] Deleting the file open in the active tab offers close/discard flow; no crash
- [x] Renaming an open file updates tab title + save target
- [x] Watching scoped to expanded folders (no fd leaks, instrumented)
- [x] Filter toggle hides non-registered extensions immediately

## Out of scope

Git status badges, multi-root workspaces, search-in-folder (v1.x candidates).

## Notes

Same architecture rule as FileCore: pure synchronous model core, async edges.

## Implementation record

Epic 9 was delivered on `epic/09-folder-browser` and merged through PR #38.
The Release package suite passed 469 tests across 50 suites, including the
10k-entry folder benchmark and watcher lifecycle coverage. The Release app
build, strict SwiftLint, SwiftFormat, and diff checks also passed. Focused UI
test execution reached the runner but remained subject to the host's
automation-mode initialization timeout before test cases could start.
