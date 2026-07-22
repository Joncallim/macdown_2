> **Title:** [EPIC-07] Native Markdown preview: Textual rendering, split view, scroll sync
> **Labels:** `epic`, `markdown` · **Milestone:** M3 — Markdown core · **Depends on:** E06, E04

## Context

Decision D4: native SwiftUI preview via Textual (MIT, Prism-based code
highlighting, math, native selection) — no WKWebView for Markdown. This is the
single biggest perceived-speed and visual-quality win: no web process, crisp
text, glass-friendly.

## Scope

- `Preview` target: `MarkdownPreviewing` protocol + Textual-backed
  implementation (protocol seam isolates Textual's pre-1.0 API)
- Editor | Preview split in the content area: draggable divider, both panes
  collapsible (editor-only, preview-only, split), per-tab layout state.
  *Amended at #28: tabs are native windows (as-built E03), so "per-tab" means
  per window/document, persisted through the session store. The current
  `Preview`/`MarkdownEngine` modules are EPIC-02 placeholders this epic
  replaces.*
- Render pipeline: MarkdownEngine AST → Textual document on debounce
- **Scroll sync**: editor scroll position ↔ preview position via the E06
  source-range index (block-level mapping, monotonic, no feedback loops)
- Preview theme derives from editor theme + system appearance; code blocks use
  Textual's built-in Prism highlighting
- Live update < 150 ms after last keystroke (budget)

## Deliverables

1. Split-view container + per-tab layout persistence
2. Textual-backed preview with theme integration
3. Scroll-sync engine + tests (mapping math); perf test for the 150 ms budget

## Acceptance criteria

- [ ] Typing updates preview within 150 ms (measured, CI)
- [ ] Scrolling editor keeps preview within one viewport of the matching block on the fidelity corpus
- [ ] Preview-only / editor-only / split persist per tab and across relaunch
- [ ] Text selection, link clicking, and images work in preview
- [ ] If Textual fails on a construct, preview degrades gracefully (plain block), never crashes

## Out of scope

HTML format preview (E11), export (E12), Mermaid/advanced contributions (E14).

## Notes

MacDown re-rendered the whole HTML doc into WebKit per keystroke — the native
pipeline should beat it by an order of magnitude. Capture before/after numbers
for release notes.
