> **Title:** [EPIC-19] First-class math and scientific notation in Markdown
> **Labels:** `epic`, `markdown`, `formats` · **Milestone:** M5 — feature completion before polish · **Depends on:** E10, E12, E14

## Owner summary

MacDown 2 should let a technical writer keep equations as readable text in Markdown while showing properly typeset mathematics in preview and exported documents. Math should feel like a native document feature, not a hosted/web-service plugin bolted onto the preview.

This epic turns the small math proof originally associated with E14 into a complete user-facing capability. It does **not** turn MacDown 2 into a full TeX distribution or Overleaf replacement.

## Problem

Markdown is excellent for technical prose, but equations quickly become awkward when the editor cannot understand or render mathematical notation. A technical-writing editor should preserve simple, diffable source while producing publication-quality equations locally.

## Intended outcome

A user can write inline or display math using familiar LaTeX-style notation, see it update in the native preview, navigate between source and rendered output, receive useful errors for malformed expressions, and export the same document to HTML/PDF without losing the mathematics or requiring an internet connection.

## Representative user journeys

1. **Write and preview:** type `$E = mc^2$` or a `$$...$$` display equation and see a correctly typeset result appear in preview without leaving the editor.
2. **Work offline:** disconnect networking and retain the same first-party math preview/export behaviour.
3. **Recover from an error:** enter malformed math, receive a local diagnostic associated with that expression, correct it, and see the preview recover automatically.
4. **Navigate:** select/click a rendered equation and return to the corresponding source range; editing source updates the same derived block.
5. **Export:** export a document containing equations to HTML/PDF through E12's shared derived-content path with high-quality output.
6. **Large document:** edit prose in a document containing many equations without repeatedly re-rendering unchanged expressions or making typing sluggish.

## Scope

- Inline math with `$...$`.
- Display math with `$$...$$`.
- Support `\(...\)` and `\[...\]` only if architecture confirms unambiguous compatibility.
- First-party math rendering through E14's renderer-neutral contribution architecture and E12's export destination contract.
- Local/offline rendering; document/math source is not uploaded to a hosted rendering service.
- Theme-aware light/dark preview.
- Stable source identity/range for source ↔ preview navigation.
- Local block/expression diagnostics; one bad expression cannot break the document.
- Off-hot-path rendering with cancellation, stale-result suppression and bounded caching.
- HTML/PDF export using the same derived result contract rather than a parallel math exporter.
- Accessibility labelling/alternative representation where the chosen renderer permits it reasonably.
- Ordinary, nested, malformed, Unicode-heavy, pathological and large-document fixtures.

## Explicit non-goals

- Full `.tex` document compilation or TeX distribution/package management.
- `\documentclass`, arbitrary `\usepackage`, BibTeX/Biber or multi-file Overleaf-style projects.
- TikZ graphics.
- Hosted/network math rendering.
- Inventing a new mathematical markup language.

## User-visible acceptance criteria

- [ ] Inline/display equations render correctly in native Markdown preview.
- [ ] First-party math preview/export works with networking unavailable and transmits no document content externally.
- [ ] Malformed math shows a useful local failure state without breaking surrounding Markdown/other equations.
- [ ] Correcting malformed math restores the equation automatically.
- [ ] Source ↔ preview navigation identifies the correct equation after nearby edits.
- [ ] Light/dark theme changes update math appropriately.
- [ ] HTML/PDF exports preserve equations through the E12/E14 shared derived-content contract with visually reviewed output.
- [ ] Editing a representative large Markdown document with many unchanged equations remains within the approved Release-build responsiveness budget.
- [ ] Durable document remains readable Markdown text; rendered output/cache is disposable derived data.

## Release placement

E19 runs after E14 establishes the contribution seam and E12 establishes export. It completes before the feature-complete/E15 gate and before E16 string freeze.

## Architecture gate

Implementation must not begin until `planning/EPIC_STANDARD.md` and `planning/RELEASE_HARDENING.md` are satisfied and a current-master `planning/epic-19-implementation.md` is reviewed. Architecture selects/verifies rendering technology, delimiters, local/offline execution, licensing, cache model, export representation, accessibility and complete-app Release performance.
