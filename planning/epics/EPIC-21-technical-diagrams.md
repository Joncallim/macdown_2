> **Title:** [EPIC-21] Technical and engineering diagrams: evaluate D2, Graphviz and WaveDrom
> **Labels:** `epic`, `markdown`, `formats` · **Milestone:** M5 — feature completion before polish · **Depends on:** E20

## Owner summary

Once Mermaid proves the common diagram platform, E21 evaluates additional text-based diagram languages that could materially improve technical and engineering documentation.

D2, Graphviz/DOT and WaveDrom are **candidates**, not unconditional shipping obligations. Each candidate must pass an explicit admission review for licensing, local/offline execution, security, bundle/runtime cost, maintenance, vector/export quality and integration fit. An evidence-backed rejection is a valid E21 outcome and must not hold macOS 1.0 hostage merely because a renderer name appears in the roadmap.

Accepted renderers plug into the E20 platform and receive the same MacDown 2 behaviours: readable text source, local diagnostics, vector preview, source navigation, caching, export and failure isolation.

## Problem

Mermaid covers many general diagrams well, but technical writers often need layouts or notation better served by specialised text-based tools. Supporting good candidates through one native editor/preview/export experience makes MacDown 2 more useful for engineering documents. Forcing a poor dependency into 1.0 would do the opposite by increasing security, maintenance, startup or bundle-size risk.

## Intended outcome

For every candidate renderer, the repository records one clear decision:

- **accepted** — integrated through E20's common renderer contract and shipped; or
- **rejected for macOS 1.0** — rationale documented, no unnecessary runtime baggage added, authored source remains safe/readable and the app shows an understandable unsupported/capability state when that fence is encountered.

## Representative user journeys

1. **Accepted architecture/block renderer:** write a supported `d2` fence and obtain a polished architecture diagram without leaving Markdown.
2. **Accepted formal graph renderer:** write a supported `dot`/`graphviz` fence and obtain deterministic vector output.
3. **Accepted timing renderer:** write a supported `wavedrom` fence and obtain a readable digital timing diagram.
4. **Mixed document:** combine Mermaid and every accepted E21 renderer; one renderer failure does not affect the others.
5. **Unavailable/rejected renderer:** open a document containing a known but unsupported candidate fence; source remains intact and the UI explains that the capability is unavailable rather than corrupting/replacing it.
6. **Export:** export a mixed technical document and preserve every accepted renderer consistently through the E12/E20 derived-content path.

## Per-renderer admission gate

The current-master architecture pass must record an **accept** or **reject** decision for D2, Graphviz/DOT and WaveDrom separately, based on:

- licensing and redistribution terms;
- ability to execute locally/offline with no document upload;
- security/trust boundary for untrusted diagram source;
- runtime packaging and app bundle-size impact;
- cold-start/lazy-load impact;
- cancellation, timeout and failure-isolation behaviour;
- vector/SVG and HTML/PDF export quality;
- accessibility possibilities/limitations;
- maintenance health/version pinning/upstream risk;
- integration complexity relative to user value.

The implementation must not weaken E20's renderer abstraction or product safety merely to force a candidate to pass.

## Scope

For each **accepted** candidate:

- integrate through the E20 diagram contract;
- define consistent fenced-language aliases/detection;
- add syntax highlighting/editing support where a maintained grammar or small safe integration is practical;
- inherit E20 cancellation, cache, diagnostic, source-mapping, vector, copy/export and accessibility contracts;
- preserve consistent theme behaviour where the renderer exposes a safe/useful option;
- expose capability metadata so unavailable operations degrade clearly;
- include representative/adversarial fixtures and Release-build performance verification;
- ensure focused diagram preview handles wide/tall engineering diagrams without damaging main document layout.

For each **rejected** candidate:

- record the owner-readable rationale and evidence;
- do not bundle its runtime/dependencies;
- preserve source text unchanged;
- show a deliberate unsupported/capability state if the language fence is recognised.

## Explicit non-goals

- Guaranteeing that all three candidate renderers ship.
- Full schematic capture with component libraries, electrical-rule checking, netlists, footprints, PCB layout or simulation.
- A drag-and-drop block-diagram canvas.
- PlantUML, TikZ or arbitrary external renderer support in macOS 1.0.
- Bundling a large external runtime merely to satisfy roadmap wording.
- Re-implementing rendering engines in Swift merely to make them look "native".
- Hosted/cloud rendering as a workaround for local packaging difficulty.

## User-visible acceptance criteria

- [ ] D2, Graphviz/DOT and WaveDrom each have a documented accept/reject decision from the admission gate.
- [ ] Every accepted renderer uses the same user-facing diagram workflow established by E20 rather than a parallel special-case path.
- [ ] Every accepted renderer can fail independently with a useful block-local diagnostic/capability message.
- [ ] Mixed accepted-renderer documents remain responsive during ordinary editing and stale render results cannot replace newer source.
- [ ] Accepted renderers produce crisp vector output for preview/export where the underlying engine permits it.
- [ ] Source ↔ preview navigation works consistently across accepted diagram types.
- [ ] Copy/export and HTML/PDF output behave consistently with Mermaid unless a documented renderer limitation applies.
- [ ] Rejected/unavailable renderers never change or destroy durable text source and do not leave unnecessary bundled runtime baggage.
- [ ] No accepted renderer requires internet access or uploads document content for first-party rendering.
- [ ] Combined accepted-renderer footprint/startup behaviour meets budgets approved during the architecture pass.

## Release placement

E21 follows E20 so the common renderer platform is proven with one language before additional engines depend on it. Completion of E21 means the candidate evaluation/integration work is complete, not necessarily that all candidates shipped. It remains the end of planned major macOS 1.0 feature development before the feature-complete gate, E15 polish, E16 localisation and E17 distribution.

## Architecture gate

Implementation must not begin until `planning/EPIC_STANDARD.md` and `planning/RELEASE_HARDENING.md` are satisfied and a current-master `planning/epic-21-implementation.md` has been reviewed. The architecture pass must perform the admission gate independently for each candidate while preserving one common MacDown 2 user experience for whatever is accepted.
