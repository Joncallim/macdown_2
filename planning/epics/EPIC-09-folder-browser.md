> **Title:** [EPIC-09] Folder browser: lazy file tree, FS watching, CRUD
> **Labels:** `epic`, `workspace` · **Milestone:** M4 — Workspace & formats · **Depends on:** E01, E02, E03

## Context

The sidebar's other half (D2). Opens a folder as the workspace root; files open
in tabs (E03). Unsandboxed (D7) but modeled on security-scoped URLs so future
sandboxing is additive.

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

- [ ] External `touch new.md` in an expanded folder appears < 1 s
- [ ] Deleting the file open in the active tab offers close/discard flow; no crash
- [ ] Renaming an open file updates tab title + save target
- [ ] Watching scoped to expanded folders (no fd leaks, instrumented)
- [ ] Filter toggle hides non-registered extensions immediately

## Out of scope

Git status badges, multi-root workspaces, search-in-folder (v1.x candidates).

## Notes

Same architecture rule as FileCore: pure synchronous model core, async edges.
