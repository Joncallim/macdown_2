> **Title:** [EPIC-11] Multi-format support: JSON tools, HTML preview toggle, language registry completion
> **Labels:** `epic`, `formats` · **Milestone:** M4 — Workspace & formats · **Depends on:** E05, E07

## Context

> **As-built status:** A thorough orthogonal planning pass is recorded in
> [`../epic-11-implementation.md`](../epic-11-implementation.md). Epic 11 has
> no production implementation PR yet; implementation must follow its
> sequential gates and security contracts.

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
- **Other languages**: complete the grammar registry. *Amended at #28: E05
  shipped `markdown`, `markdown_inline`, `json`, `html` only. The remaining
  planned grammars (css, javascript, typescript, python, yaml, toml, swift,
  bash, sql, xml, ruby, c, cpp) land here — each is one `case` in
  `GrammarRegistry.buildConfiguration(for:)` + `knownLanguageIDs` and one
  pinned SPM package (or a vendored local package with canonical-capture
  queries, following the `Packages/TreeSitterMarkdown` pattern when upstream
  SPM packaging is missing/broken).* Ensure the preview pane shows a clean
  "no preview" state with format info (line count, language, encoding)
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

The acceptance criteria are gated by the implementation plan. JSON formatting
must use the native one-edit/undo/publication path; HTML resource and
navigation policy must be explicit and tested; grammar packages must be pinned
and proven individually; and all asynchronous results must be generation-
checked before publication.

## Out of scope

JSON Schema validation, HTML source editing assists (v1.x).

## Notes

The WKWebView here is deliberate and scoped — Markdown never touches it (D4).
