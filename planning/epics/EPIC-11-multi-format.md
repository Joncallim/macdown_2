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

- **JSON**: validation on debounce with typed diagnostics, UTF-16 editor
  ranges, and malformed-byte diagnostics; pretty-print/format command;
  collapsible outline in the content browser (reuses the E08 slot through a
  format-neutral outline adapter); sort-keys option on format. Duplicate
  keys are rejected with a stable diagnostic and never silently merged.
- **Encoding**: `FileStore`/`FileSnapshot` capture immutable text plus the
  transient raw bytes used to derive the existing `FileRevision.sha256` string,
  typed BOM, encoding metadata, and revision atomically; raw bytes are not
  retained in `FileSnapshot`/`FileDocument`. Malformed
  bytes return `FileStoreError.decodingFailed([FileDecodingDiagnostic])` with
  zero-based offsets and preserve the prior document/recovery state. Markdown,
  JSON, HTML, and source-only formats preserve detected encoding/BOM and use
  UTF-8 without BOM for new documents. Ordinary save, recovery, external
  replacement, and Save As preserve that metadata; Save As changes it only
  through an explicit destination encoding override.
- **HTML**: source ↔ rendered toggle in the preview pane. The existing
  app-owned `WKWebView` host remains in `DocumentEditorSplitView` for this
  Epic; `Preview` owns policy/request types. v1 disables scripts and denies
  network access, navigation, popups, downloads, forms, storage, and bridges;
  live-ish reload occurs on save, not per keystroke.
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
2. HTML preview toggle and security policy using the existing app-owned
   WKWebView host; `Preview` owns typed policy/request contracts
3. Format registry completeness check + snapshot tests per format

## Acceptance criteria

- [ ] Invalid JSON shows typed error line/column and UTF-16 range within the
      150 ms debounce; malformed UTF-8 reports a byte-offset decoding diagnostic
- [ ] UTF-16 ranges match editor selections at astral, combining-mark, and CRLF
      boundaries
- [ ] Pretty-print is a single undo-able edit
- [ ] JSON outline collapses/expands and jumps like the MD outline; duplicate
      keys reject without publishing an outline
- [ ] HTML toggle renders approved local relative resources through the
      app-owned WKWebView; scripts, network/navigation, popups, downloads, and
      bridges are denied
- [ ] BOM/encoding metadata survives load, edit, recovery, ordinary save, and
      Save As; only an explicit destination encoding override changes it
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

The WKWebView remains deliberate and scoped to HTML — Markdown never touches
it (D4), and the host remains app-owned for this Epic rather than moving into
the `Preview` package.
