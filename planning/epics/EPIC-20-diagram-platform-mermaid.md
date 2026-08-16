> **Title:** [EPIC-20] Native diagram platform + Mermaid
> **Labels:** `epic`, `markdown`, `formats` · **Milestone:** M5 — feature completion before polish · **Depends on:** E12, E14

## Owner summary

MacDown 2 should let a user describe a diagram as clean text inside Markdown and see a polished vector diagram in preview. The Markdown file remains readable, diffable and source-control friendly; the visual result is derived by the app.

This epic builds the reusable diagram platform and proves it with one production-quality renderer: Mermaid. Later diagram languages must plug into this platform rather than inventing separate rendering systems.

## Problem

Technical documents often need architecture, process, sequence and state diagrams. Today those diagrams are usually created in another app and pasted in as opaque images, which separates the visual from its source and makes review/version control worse.

## Intended outcome

A user can write a fenced Mermaid block, see a high-quality SVG diagram in preview, receive useful errors when the diagram source is invalid, navigate between source and rendered output, and export the same diagram cleanly to HTML/PDF or as a standalone vector asset.

## Representative user journeys

1. **Create:** type a `mermaid` fenced block for a flowchart and see the rendered diagram update in the preview.
2. **Correct an error:** introduce invalid Mermaid syntax, see a local diagnostic associated with that block, fix the text, and see the diagram recover automatically.
3. **Navigate:** click/select the rendered diagram and jump to its source block; edit the block and retain stable source ↔ preview identity where possible.
4. **Reuse:** copy/export the diagram as SVG and use it outside MacDown 2 without rasterisation.
5. **Export:** export the whole Markdown document to HTML/PDF and preserve the rendered diagram.
6. **Edit at scale:** type elsewhere in a document containing many unchanged diagrams without re-rendering every block or blocking the main thread.

## Scope

- A first-class diagram block model for supported fenced code blocks.
- A renderer abstraction with explicit inputs, outputs, diagnostics, cancellation and capability metadata.
- Mermaid as the first production renderer.
- Derived SVG as the canonical rendered artefact for preview/export where the selected renderer permits it.
- Off-main rendering, cancellation/stale-result suppression and lifecycle teardown.
- Cache by stable inputs such as source + renderer version + theme/options; cache policy/limits are fixed during architecture.
- Local error UI that degrades only the affected diagram block.
- Source-range identity and source ↔ preview navigation.
- Focused/larger diagram preview for detailed diagrams.
- Copy/export SVG; raster export may be included only if it falls out cleanly from the same pipeline.
- Theme-aware diagram rendering where Mermaid supports it without compromising source fidelity.
- HTML/PDF export integration.
- Accessibility labelling for rendered diagrams and useful source fallback.
- Adversarial fixtures including malformed syntax, deeply nested graphs, very large diagrams and rapid source changes.

## Explicit non-goals

- D2, Graphviz/DOT or WaveDrom; those are E21 after this architecture is proven.
- Drag-and-drop visual diagram authoring.
- A Figma/Visio-style canvas.
- Full electronic design automation (EDA), PCB capture or simulation.
- PlantUML or TikZ in v1.
- A generic third-party renderer marketplace; E14 owns the extension design and later releases may expose more of the internal seam.

## User-visible acceptance criteria

- [ ] `mermaid` fenced blocks render as diagrams in the native Markdown preview without turning the Markdown preview into a web view.
- [ ] Rendered output is crisp vector output at arbitrary preview/export scale where Mermaid permits it.
- [ ] Invalid source produces a useful block-local diagnostic and does not break the rest of the document.
- [ ] Fixing invalid source automatically restores the diagram.
- [ ] Source ↔ preview navigation continues to identify the correct diagram after nearby edits.
- [ ] Repeated edits cancel or supersede stale work; an old render never replaces a newer diagram.
- [ ] Unchanged diagrams are not unnecessarily re-rendered during ordinary typing.
- [ ] A user can copy/export a rendered diagram as SVG.
- [ ] HTML and PDF exports preserve diagrams with visually reviewed output.
- [ ] The durable document representation remains ordinary Markdown text; cached SVG is disposable derived data.

## Release placement

E20 runs after E14 provides the contribution seam and after E12 establishes export. It establishes the diagram architecture before E21 adds further technical languages. Both E20 and E21 complete before E15's whole-app polish.

## Architecture gate

Implementation must not begin until `planning/EPIC_STANDARD.md`'s Definition of Ready is satisfied and a current-master `planning/epic-20-implementation.md` has been reviewed. The architecture pass must verify the Mermaid execution model, security boundary, renderer protocol, SVG handling, cache limits, stale-result rules, source identity, export integration and real-app performance budget.
