> **Title:** [EPIC-12] Export: HTML + PDF, templates and themes
> **Labels:** `epic`, `formats`, `markdown` · **Milestone:** M4 — Workspace & formats · **Depends on:** E06, E11

## Context

Replaces the Handlebars + MPAsset pipeline. HTML export uses swift-cmark's own
HTML renderer (GFM-faithful) rather than re-walking the Textual path — export
fidelity is a different requirement than live preview.

## Scope

- `ExportService` target: Markdown → standalone HTML (embedded or linked CSS),
  templated via a small Swift template layer (port the 2–3 legacy
  `.handlebars` templates to a simple Mustache-equivalent or plain string
  interpolation — no Handlebars dependency)
- PDF export via the print system (NSPrintOperation on a hidden render)
- Front matter support in export (title, metadata) using E06 output
- Port preview CSS themes from `MacDown/Resources` for export styling
- Export panel UI (replaces MPExportPanelAccessoryViewController)

## Deliverables

1. ExportService + template layer, unit-tested
2. Fidelity corpus: N real-world .md files; HTML diffed against old MacDown
   output — differences reviewed and accepted/intended
3. Export panel SwiftUI view

## Acceptance criteria

- [ ] Exported HTML of the fidelity corpus is visually equivalent to old
      MacDown output (reviewed diffs)
- [ ] Exported HTML is self-contained (embedded CSS) when requested
- [ ] PDF export paginates correctly with code blocks unbroken where possible
- [ ] Front matter title lands in `<title>` and document header
- [ ] Port of `MPAssetTests` concepts (asset bundling/embedding) passes

## Out of scope

Custom per-user templates UI (v1.x); ePub/DOCX (never planned).

## Notes

Keep template variables identical in spirit to old MacDown (title, style,
content, scripts) so users migrating custom templates have a mapping guide.
