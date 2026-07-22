> **Title:** [EPIC-06] Markdown engine: swift-markdown parse actor, debounce, front matter, source-range index
> **Labels:** `epic`, `markdown` · **Milestone:** M3 — Markdown core · **Depends on:** E01

## Context

Replaces Hoedown (unmaintained C) + LibYAML + the 500 ms NSOperationQueue
debounce with swift-markdown (cmark-gfm based, Apache-2.0) behind a Swift
concurrency pipeline. No incremental parsing exists in swift-markdown — full
re-parse per debounced edit is single-digit ms for typical docs, so this is fine.

## Scope

- `MarkdownEngine` target: `ParseEngine` actor; `Task`-cancellation debounce
  (~150 ms, replacing the old 500 ms)
- GFM options model (tables, task lists, strikethrough, autolinks, footnotes)
  mapped from settings (defaults match MacDown behavior). *Amended at #28:
  E13 (settings) has not landed — ship the options model with hardcoded
  defaults; E13 wires the UI later.*
- YAML front matter extraction via Yams (replaces LibYAML + vendored
  YAML-framework); front matter exposed to preview + export
- **Source-range index**: map AST nodes → source line ranges (feeds scroll
  sync E07 and the content browser E08)
- Engine is pure: `String in → (AST, frontMatter, sourceIndex) out`, fully
  testable without UI

## Deliverables

1. `MarkdownEngine` with public API + options model
2. Unit tests: GFM constructs, front matter variants, source-range accuracy,
   debounce cancellation semantics (rapid edits → single parse)
3. Perf tests: re-parse 1 MB doc < 150 ms total pipeline (CI)

## Acceptance criteria

- [ ] 20 rapid keystrokes trigger ≤ 2 parses (cancellation verified)
- [ ] Tables/task lists/strikethrough/footnotes render in AST per GFM
- [ ] Front matter parsed without appearing in the document AST body
- [ ] Source-range index maps every block node to correct line range on the fidelity corpus fixtures
- [ ] Parse happens off main thread (strict concurrency clean)

## Out of scope

Rendering (E07), HTML generation for export (E12 uses swift-cmark directly).

## Notes

Keep the swift-markdown AST type internal; expose our own `MarkdownDocument`
value type so a future parser swap never touches Preview/OutlineUI.

*Amended at #28:* the current `MarkdownEngine` module is an **EPIC-02
placeholder** (line-based heading/code renderer feeding the placeholder
preview). This epic **replaces** it outright; nothing in the placeholder is an
architectural constraint. Tabs are native windows (as-built E03), so engine
consumers are per-window — one parse pipeline per open document, torn down
with the window.
