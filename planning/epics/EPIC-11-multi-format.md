> **Title:** [EPIC-11] Multi-format support: JSON tools, HTML preview toggle, language registry completion
> **Labels:** `epic`, `formats` · **Milestone:** M4 — Workspace & formats · **Depends on:** E05, E07

## Context

Beyond Markdown (user requirement): JSON gets real tooling, HTML gets a
rendered view, and all remaining registered languages get a polished
highlight-only experience.

## Scope

- **JSON**: validation on debounce (error banner with line/column from
  `JSONSerialization`/`Foundation.JSONParserError`), pretty-print/format
  command, collapsible outline in the content browser (reuses E08 slot:
  key tree via SwiftUI `OutlineGroup`), sort-keys option on format
- **HTML**: source ↔ rendered toggle in the preview pane (rendered uses a
  sandboxed `WKWebView` — this is the only WKWebView in the app); live-ish
  reload on save (not per keystroke)
- **Other languages**: confirm all E05 grammars wired through the FileFormat
  registry; ensure preview pane shows a clean "no preview" state with format
  info (line count, language, encoding)
- Preview router generalizes: per-format `PreviewCapability` honored in UI

## Deliverables

1. JSON validator + formatter + outline model, unit-tested (incl. ports of
   `MPHTMLTabularizeTests` ideas → JSON outline tests)
2. HTML preview toggle + WKWebView host (isolated in `Preview` target)
3. Format registry completeness check + snapshot tests per format

## Acceptance criteria

- [ ] Invalid JSON shows error line/column within the 150 ms debounce
- [ ] Pretty-print is a single undo-able edit
- [ ] JSON outline collapses/expands and jumps like the MD outline
- [ ] HTML toggle renders local files with relative resources; scripts run
      only in the sandboxed web view
- [ ] Every registered extension opens with correct highlighting or a clean
      no-preview state

## Out of scope

JSON Schema validation, HTML source editing assists (v1.x).

## Notes

The WKWebView here is deliberate and scoped — Markdown never touches it (D4).
