> **Title:** [EPIC-08] Content browser: heading outline of the active document
> **Labels:** `epic`, `workspace`, `markdown` · **Milestone:** M3 — Markdown core · **Depends on:** E06, E02

## Context

User-requested addition (D2): a collapsible **content browser** in the sidebar
(above or below the folder browser) listing the active document's section
headings for quick jumping — the per-document counterpart to the folder browser.

## Scope

- `OutlineUI` target: heading tree built from the E06 AST (H1–H6, nested,
  collapsible), Setext + ATX support
- Sidebar placement: below the folder browser by default; section order
  persisted and user-rearrangeable
- Click heading → editor jumps (scroll + cursor + brief highlight); current
  section auto-highlighted as you scroll/edit (via source-range index)
- Live updates from the same debounced parse; graceful empty state for
  non-Markdown formats ("No outline available" — JSON outline arrives in E11)
- Keyboard: ⌃⌘O focus outline, arrows navigate, Return jumps

## Deliverables

1. Outline view + model, wired to active-tab switching
2. Unit tests: tree building incl. skipped levels (H1→H3), code-block headings
   ignored, front matter ignored
3. XCUITest: click outline item → editor scrolls to section

## Acceptance criteria

- [ ] Headings inside fenced code blocks never appear in the outline
- [ ] Outline updates within the same 150 ms debounce as the preview
- [ ] Switching tabs swaps outline instantly (cached per tab)
- [ ] Section order (folder above/below outline) persists across relaunch
- [ ] Full keyboard navigation works

## Out of scope

TOC insertion into exported HTML (E12/E14); JSON outline (E11).

## Notes

A differentiator — old MacDown has nothing like it. Keep it cheap: the E06
source-range index does the heavy lifting.
