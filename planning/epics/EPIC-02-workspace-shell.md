> **Title:** [EPIC-02] Workspace shell: WindowGroup, NavigationSplitView, commands
> **Labels:** `epic`, `foundation`, `workspace` · **Milestone:** M1 — Skeleton · **Depends on:** E01

## Context

Single-window workspace (D2): one `WindowGroup` scene hosting a `WorkspaceModel`.
The sidebar (collapsible) will hold the folder browser (E09) and content
browser (E08); this epic delivers the shell they plug into, plus the app's
command/menu structure.

## Scope

- `@main` App + `WindowGroup` + `WorkspaceModel` (observable)
- `NavigationSplitView`: collapsible sidebar column (placeholder sections:
  "Folder" / "Outline"), content column (placeholder), optional inspector column
- Sidebar toggle toolbar item + ⌃⌘S (or standard) shortcut
- Menu/commands: New File ⌘N, Open… ⌘O, Open Folder… ⌘⇧O, Save ⌘S,
  Save As ⌘⇧S, Close Tab ⌘W — wired to FileCore
- Window restoration (size, sidebar visibility)
- About panel placeholder (new product name)

## Deliverables

1. `App` + `Workspace` targets: shell UI + command routing
2. Placeholder sidebar sections with collapse/expand persistence
3. Unit tests for WorkspaceModel command state (canSave, canClose…)

## Acceptance criteria

- [ ] Launch → empty workspace; ⌘O opens a file into the content area via FileCore
- [ ] Sidebar collapses/expands from toolbar + keyboard; state persists across relaunch
- [ ] All listed menu items exist with correct shortcuts and enable/disable state
- [ ] Window frame + sidebar state restored on relaunch

## Out of scope

Tabs (E03), actual folder tree (E09), outline content (E08), editor (E04).

## Notes

Do not put custom backgrounds behind toolbars/sidebar — Liquid Glass (E15)
needs clean surfaces. Use stock SwiftUI containers now; polish later.
