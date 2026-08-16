> **Title:** [EPIC-20] Native diagram platform + Mermaid
> **Labels:** `epic`, `markdown`, `formats` · **Milestone:** M5 — feature completion before polish · **Depends on:** E12, E14

## Owner summary

MacDown 2 should let a user describe a diagram as clean text inside Markdown and see a polished vector diagram in preview. The Markdown file remains readable, diffable and source-control friendly; the visual result is locally derived by the app.

This epic builds the reusable diagram platform and proves it with one production-quality renderer: Mermaid. Later diagram languages must plug into this platform rather than inventing separate rendering systems.

Mermaid rendering is a first-party local/offline capability. Difficulty integrating a local renderer is not permission to upload document/diagram source to a hosted service.

## Problem

Technical documents often need architecture, process, sequence and state diagrams. External drawing tools separate the visual from its source and make review/version control worse. A hosted renderer would preserve text source but weaken the product's local-first/privacy model.

## Intended outcome

A user can write a fenced Mermaid block, see a high-quality SVG diagram in preview, receive useful local errors, navigate between source and rendered output, and export the same diagram through the E12/E14 shared derived-content path to HTML/PDF or as a standalone vector asset — all without requiring a network connection.

## Representative user journeys

1. **Create:** type a `mermaid` fenced block and see it update in preview.
2. **Work offline:** disconnect networking and retain first-party Mermaid preview/copy/export behaviour.
3. **Correct an error:** invalid Mermaid syntax yields a block-local diagnostic; fixing source restores the diagram.
4. **Navigate:** click/select the rendered diagram and jump to its source block with stable identity across nearby edits where possible.
5. **Reuse:** copy/export SVG without rasterisation.
6. **Export:** export the whole Markdown document to HTML/PDF through the same derived-content result used by Preview.
7. **Edit at scale:** type elsewhere in a document containing many unchanged diagrams without re-rendering every block or blocking the main actor.

## Scope

- First-class diagram block model for supported fenced code blocks.
- Renderer abstraction with explicit inputs, renderer-neutral outputs, diagnostics, cancellation and capability metadata aligned with E14.
- Mermaid as the first production renderer.
- Local/offline Mermaid execution; no document/diagram upload for first-party rendering.
- Derived SVG as canonical rendered artefact where supported, consumed by Preview/Export adapters rather than separate renderer implementations.
- Off-main rendering, cancellation/stale-result suppression and lifecycle teardown.
- Cache keyed by stable inputs such as source + renderer version + theme/options; architecture fixes limits/eviction.
- Local error UI that degrades only the affected block.
- Source-range identity and source ↔ preview navigation.
- Focused/larger diagram preview for detailed diagrams.
- Copy/export SVG; raster export only if it falls out cleanly from the same pipeline.
- Theme-aware rendering where Mermaid supports it without source-fidelity compromise.
- HTML/PDF export through E12's destination contract.
- Accessibility labelling/useful source fallback.
- Adversarial fixtures: malformed syntax, deeply nested/very large diagrams, rapid source changes, renderer failure/timeout and cache corruption.

## Explicit non-goals

- D2, Graphviz/DOT or WaveDrom; E21 evaluates those after this platform is proven.
- Drag-and-drop visual authoring or a Figma/Visio-style canvas.
- Full EDA/PCB capture/simulation.
- PlantUML or TikZ in v1.
- Generic third-party renderer marketplace.
- Hosted/cloud Mermaid rendering.

## User-visible acceptance criteria

- [ ] `mermaid` fences render in native Markdown preview without turning Markdown preview into a web page.
- [ ] First-party Mermaid preview/export works with networking unavailable and transmits no document/diagram source externally.
- [ ] Output is crisp vector content at preview/export scale where Mermaid permits it.
- [ ] Invalid source produces a useful block-local diagnostic without breaking the document.
- [ ] Fixing invalid source automatically restores the diagram.
- [ ] Source ↔ preview navigation remains correct after nearby edits.
- [ ] Repeated edits cancel/supersede stale work; old output never replaces newer source.
- [ ] Unchanged diagrams are not unnecessarily re-rendered during ordinary typing.
- [ ] User can copy/export SVG.
- [ ] HTML/PDF export consumes the shared E12/E14 derived result rather than a parallel Mermaid exporter.
- [ ] Durable document remains ordinary Markdown text; cached SVG is disposable.

## Release placement

E20 runs after E12/E14 establish export/contribution seams. It proves the diagram architecture before E21 evaluates additional renderers. Both complete before the feature-complete/E15 gate.

## Architecture gate

Implementation must not begin until `planning/EPIC_STANDARD.md` and `planning/RELEASE_HARDENING.md` are satisfied and a current-master `planning/epic-20-implementation.md` is reviewed. Architecture must verify Mermaid's local execution model, licensing/security boundary, renderer protocol, SVG handling, cache limits, stale-result rules, source identity, shared export integration and real-app Release performance.
