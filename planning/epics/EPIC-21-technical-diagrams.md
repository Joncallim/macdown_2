> **Title:** [EPIC-21] Technical and engineering diagrams: D2, Graphviz and WaveDrom
> **Labels:** `epic`, `markdown`, `formats` · **Milestone:** M5 — feature completion before polish · **Depends on:** E20

## Owner summary

Once Mermaid proves the common diagram platform, MacDown 2 should broaden the same text-first experience to diagram languages that are especially useful for technical and engineering documentation.

E21 adds D2 for clean architecture/block diagrams, Graphviz/DOT for formal graphs and dependency structures, and WaveDrom for digital timing/waveform diagrams. These are additional renderers on the E20 platform, not three separate mini-products.

## Problem

Mermaid covers many general diagrams well, but technical writers often need layouts or notation better served by specialised text-based tools. Supporting those tools through one native editor/preview/export experience makes MacDown 2 substantially more useful for engineering documents without turning it into a visual CAD application.

## Intended outcome

A user chooses the most appropriate fenced diagram language, writes readable textual source, and receives the same MacDown 2 behaviours: syntax-aware editing, local diagnostics, vector preview, source navigation, caching, export and failure isolation.

## Representative user journeys

1. **Architecture/block diagram:** write a `d2` fenced block and obtain a polished architecture diagram without leaving Markdown.
2. **Formal graph:** write a `dot`/`graphviz` block for dependencies or a directed graph and obtain deterministic vector output.
3. **Timing diagram:** write a `wavedrom` block and obtain a readable digital timing diagram suitable for engineering documentation.
4. **Mixed document:** keep Mermaid, D2, Graphviz and WaveDrom blocks in the same document; one renderer failure does not affect the others.
5. **Export:** export a mixed technical document to HTML/PDF and preserve all supported diagrams consistently.
6. **Unavailable renderer:** if a renderer cannot run on a particular installation, retain the source and show a clear capability message rather than corrupting or replacing the block.

## Scope

- D2 renderer integrated through the E20 diagram contract.
- Graphviz/DOT renderer integrated through the same contract.
- WaveDrom renderer integrated through the same contract.
- Language aliases and fenced-block detection defined consistently.
- Syntax highlighting/editing support where a maintained grammar or small safe grammar integration is practical.
- The same cancellation, cache, diagnostic, source-mapping, SVG, copy/export and accessibility contracts established by E20.
- Consistent theme behaviour where a renderer exposes a safe/thematically useful option.
- Per-renderer capability metadata so unavailable/unsupported operations degrade clearly.
- A mixed-renderer adversarial corpus and Release-build performance verification.
- Focused diagram preview capable of handling wide/tall engineering diagrams without damaging the main document layout.

## Explicit non-goals

- Full schematic capture with component libraries, electrical-rule checking, netlists, footprints, PCB layout or simulation.
- A drag-and-drop block-diagram canvas.
- PlantUML, TikZ or arbitrary external renderer support in macOS 1.0.
- Bundling a large external runtime without explicit architecture/security/bundle-size review.
- Re-implementing rendering engines in Swift merely to make them look "native".

## User-visible acceptance criteria

- [ ] D2, Graphviz/DOT and WaveDrom fenced blocks render through the same user-facing diagram workflow established by E20.
- [ ] Each renderer can fail independently with a useful block-local diagnostic or capability message.
- [ ] Mixed-renderer documents remain responsive during ordinary editing and do not allow stale render results to replace newer source.
- [ ] Supported renderers produce crisp vector output for preview and export where their underlying engine permits it.
- [ ] Source ↔ preview navigation works consistently across all supported diagram types.
- [ ] Copy/export and HTML/PDF output behave consistently with Mermaid unless a renderer has a documented limitation.
- [ ] A renderer being unavailable never changes or destroys the durable text source.
- [ ] The combined renderer/runtime footprint and startup behaviour meet budgets explicitly approved during the implementation architecture pass.

## Release placement

E21 follows E20 so the common renderer platform is proven with one language before additional engines depend on it. Completion of E21 marks the end of major macOS 1.0 feature development; the repository then enters the feature-complete gate before E15 polish, E16 localisation and E17 distribution.

## Architecture gate

Implementation must not begin until `planning/EPIC_STANDARD.md`'s Definition of Ready is satisfied and a current-master `planning/epic-21-implementation.md` has been reviewed. The architecture pass must separately verify licensing, packaging, execution model, bundle-size cost and security boundary for each renderer while preserving one common MacDown 2 user experience.
