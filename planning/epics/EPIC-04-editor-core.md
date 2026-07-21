> **Title:** [EPIC-04] EditorCore: NSTextView + TextKit 2 representable, performance baseline
> **Labels:** `epic`, `editor` · **Milestone:** M2 — Editor · **Depends on:** E01

## Context

Decision D3: custom NSTextView + TextKit 2, fastest/smoothest possible.
SwiftUI `TextEditor` is not editor-grade; STTextView is GPL (rejected);
CodeEditSourceEditor is pre-1.0 (rejected). We build the editor we want.

## Scope

- `EditorView`: `NSViewRepresentable` wrapping a configured NSTextView on the
  **TextKit 2** stack (NSTextLayoutManager + NSTextContentStorage + viewport
  layout controller) for lazy layout of large documents
- Two-way binding with `FileDocument` (edit → dirty; external reload → view)
- Core behaviors: word wrap toggle, line-height/insets prefs hooks, overscroll
  (scroll past end, like MPEditorView.scrollsPastEnd), selection persistence,
  find-in-file (stock NSTextFinder is acceptable for v1)
- Per-tab independent undo managers
- Performance harness: perf tests for the budgets below (must run in CI)

## Deliverables

1. `EditorCore` target: `EditorView` + configuration API
2. XCTest performance suite: 1 MB and 10 MB Markdown fixtures
3. Basic XCUITest: type into a tab, content round-trips through FileCore

## Acceptance criteria

- [ ] 1 MB .md opens with text visible < 300 ms; typing stays < 50 ms/keystroke (CI perf test)
- [ ] 10 MB .md opens without beachball (viewport-lazy layout demonstrably active)
- [ ] Undo/redo is per-tab and survives tab switching
- [ ] Word wrap + overscroll preferences take effect immediately
- [ ] No retained-cycle leaks: closing a tab releases its text system (leaks instrument check)

## Out of scope

Syntax highlighting (E05), editing assists (E10), markdown preview (E07).

## Notes

TextKit 2 has known edge-case bugs (STTextView's README catalogs many FB
workarounds — useful reference). Keep a thin adapter so a TextKit 1 fallback
per-document is possible if a pathological file misbehaves.
