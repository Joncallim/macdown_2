> **Title:** [EPIC-12] Export: HTML + PDF, templates, themes and derived-content contract
> **Labels:** `epic`, `formats`, `markdown` · **Milestone:** M4 — Workspace & formats · **Depends on:** E06, E11

## Owner summary

E12 makes export a dependable product capability and the shared destination that later first-party math and diagram features can extend. Ordinary Markdown must export cleanly to standalone HTML and PDF, while the architecture must leave one deliberate path for E19-E21 to supply derived equations/diagrams without building parallel export systems.

E12 does **not** implement math or diagrams. It establishes the export-side contract they later consume.

## Context

Replaces the Handlebars + MPAsset pipeline. HTML export uses a GFM-faithful Markdown HTML path rather than blindly reusing live SwiftUI preview views — export fidelity and live-preview presentation are different concerns.

The 2026-08-16 release-hardening review adds one important cross-epic requirement: E12 and E14 must converge on a reusable derived-content representation so Preview and Export can consume the same first-party render result/diagnostics/source identity rather than each technical-content epic inventing two renderers.

## Representative user journeys

1. Export an ordinary Markdown document to self-contained HTML and open it without MacDown 2 installed.
2. Export the same document to PDF and retain readable pagination, headings, code blocks, images and front matter.
3. Use a preview/export theme consistently without mutating the Markdown source.
4. Later, after E19/E20 land, export a document containing equations/diagrams through the same E12 document-composition pipeline rather than a separate feature-specific exporter.
5. Encounter a failed future derived-content render and receive a deliberate fallback/diagnostic rather than silently dropping source or crashing the export.

## Scope

- `ExportService` target: Markdown → standalone HTML with embedded or linked CSS.
- Small Swift template layer for the legacy template concepts; no Handlebars dependency unless a current architecture review proves it necessary.
- PDF export through the macOS print/render system with deterministic document composition.
- Front matter support in export (title/metadata) using E06 output.
- Export styling/themes migrated deliberately from useful legacy assets.
- Export panel UI and explicit options.
- Asset/reference handling rules for local images/resources.
- A **derived-content export contribution contract** that later first-party features can use. It must accept renderer-neutral derived output/diagnostics/source identity from the E14/E19/E20 path; it must not require those features to return or reconstruct a SwiftUI preview view.
- Failure semantics for a derived block that cannot render: authored source remains intact; the export either emits a documented source/fallback representation or fails the requested export clearly according to the architecture decision. Silent omission is not allowed.
- Export remains local/offline for first-party functionality under `planning/RELEASE_HARDENING.md`.

## Deliverables

1. `ExportService` + template/document-composition layer, unit-tested.
2. Fidelity corpus of representative real-world Markdown documents with reviewed HTML/PDF output.
3. Export panel SwiftUI view.
4. Narrow derived-content destination interface + deterministic fake/test contribution proving that a later renderer can supply output without changing the whole export pipeline.
5. Documented asset/failure policy consumed later by E19-E21.

## Acceptance criteria

- [ ] Exported HTML of the ordinary Markdown fidelity corpus is intentionally equivalent to the approved expected output; differences are reviewed rather than assumed.
- [ ] Exported HTML can be self-contained (embedded CSS/assets where supported/requested).
- [ ] PDF export paginates correctly with code blocks kept together where reasonably possible.
- [ ] Front matter title lands in `<title>` and the intended document header/metadata path.
- [ ] Port of relevant `MPAssetTests` concepts (asset bundling/embedding) passes.
- [ ] A deterministic test derived-content contribution can flow through the export pipeline without special-casing a future math/diagram language.
- [ ] Derived-content failure cannot silently delete authored source from the exported result or crash the application.
- [ ] E12 does not contain production math/Mermaid/D2/Graphviz/WaveDrom rendering logic.
- [ ] Export works without an internet connection and does not transmit document content to a hosted renderer.

## Out of scope

- Production math/diagram rendering (E19-E21).
- Custom per-user templates UI (post-1.0 candidate).
- ePub/DOCX.
- Hosted export/rendering services.

## Architecture gate

E12 must satisfy `planning/EPIC_STANDARD.md` and `planning/RELEASE_HARDENING.md`. Its current-master architecture pass must reconcile the actual Preview/MarkdownEngine/export scaffolding, define the renderer-neutral derived-content destination boundary jointly compatible with E14, and prove ordinary Markdown export before technical-content features depend on it.

## Notes

Keep template variables compatible in spirit with useful old MacDown concepts (title, style, content, assets) so migration guidance is possible, but do not preserve a legacy abstraction merely because it existed.
