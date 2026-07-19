> **Title:** [EPIC-03] Tab system: TabStore, tab bar UI, session restore
> **Labels:** `epic`, `workspace` · **Milestone:** M1 — Skeleton · **Depends on:** E01, E02

## Context

In-app workspace tabs (D2), Xcode/VS Code-style: each tab owns one `FileDocument`
(from E01). Native `NSWindow` tabbing is rejected — it can't compose with a
shared sidebar.

## Scope

- `TabStore`: ordered tabs, active tab, open/activate/close/move/pin APIs;
  dedupes (opening an already-open file activates its tab)
- Tab bar UI: title, dirty dot, close button, context menu (Close, Close Others,
  Close to the Right, Reveal in Sidebar), drag-to-reorder, overflow scrolling
- Shortcuts: ⌘T new tab, ⌘W close, ⌃⇥ / ⌃⇧⇥ cycle, ⌘1…9 jump
- Close-dirty flow: save/discard/cancel sheet per dirty tab (uses E01 machine)
- Session restore: reopen prior tabs + active tab + cursor positions on launch;
  best-effort, never blocks launch, tolerates missing files
- Drag tab out → new window is **out of scope** (single-window product for v1)

## Deliverables

1. `TabStore` in `Workspace` + tab bar SwiftUI view
2. Unit tests: dedupe, reorder, pin, close flows, session serialize/restore
   (incl. corrupted/missing state)
3. XCUITest: open 3 files, edit 1, close it → prompt appears; relaunch restores tabs

## Acceptance criteria

- [ ] Opening the same file twice never creates a second tab
- [ ] Closing a dirty tab always prompts; cancel aborts the close
- [ ] Quit with 5 open tabs → relaunch restores all 5, active tab, scroll/cursor
- [ ] ⌘1…⌘9 and ⌃⇥ navigation match the order shown in the bar
- [ ] Restore with a deleted file: tab dropped, others unaffected, no crash

## Out of scope

Editor content (E04); split editor/preview (E07); drag-out windows.

## Notes

The tab bar is the most visible custom control — keep it stock-looking now
(simple HStack), Liquid Glass treatment comes in E15.
