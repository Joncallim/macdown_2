> **Title:** [EPIC-19] First-class math and scientific notation in Markdown
> **Labels:** `epic`, `markdown`, `formats` · **Milestone:** M5 — feature completion before polish · **Depends on:** E10, E12, E14

## Owner summary

MacDown 2 should let a technical writer keep equations as readable text in the Markdown source while showing properly typeset mathematics in preview and exported documents. Math should feel like a native document feature, not a web-page plugin bolted onto the preview.

This epic turns the small math proof originally associated with E14 into a complete user-facing capability. It does **not** turn MacDown 2 into a full TeX distribution or Overleaf replacement.

## Problem

Markdown is excellent for technical prose, but equations quickly become awkward when the editor cannot understand or render mathematical notation. A technical-writing editor should preserve simple, diffable source while producing publication-quality equations.

## Intended outcome

A user can write inline or display math using familiar LaTeX-style notation, see it update in the native preview, navigate between source and rendered output, receive useful errors for malformed expressions, and export the same document to HTML/PDF without losing the mathematics.

## Representative user journeys

1. **Write and preview:** type `$E = mc^2$` or a `$$...$$` display equation and see a correctly typeset result appear in preview without leaving the editor.
2. **Recover from an error:** enter malformed math, receive a local diagnostic associated with that expression rather than a broken document, correct the expression, and see the preview recover automatically.
3. **Navigate:** select or click a rendered equation and return to the corresponding source range; editing the source updates the same rendered block.
4. **Export:** export a document containing equations to HTML and PDF and retain visually correct, high-quality mathematics.
5. **Large document:** edit ordinary prose in a document containing many equations without repeatedly re-rendering unchanged expressions or making typing feel sluggish.

## Scope

- Inline math with `$...$`.
- Display math with `$$...$$`.
- Support `\(...\)` and `\[...\]` if the implementation architecture confirms they can be supported without ambiguous Markdown parsing.
- First-party math rendering through the E14 contribution architecture.
- Theme-aware rendering for light/dark preview.
- Source-range identity so equations participate in source ↔ preview navigation.
- Local diagnostics for malformed expressions; one bad expression must not break the rest of the preview.
- Rendering off the typing-critical path, with cancellation/stale-result handling and cache behaviour defined by the implementation architecture.
- HTML and PDF export with equivalent math output.
- Accessibility labelling/alternative text where the selected renderer can provide it reasonably.
- Test corpus covering ordinary, nested, malformed, Unicode-heavy and pathological equations.

## Explicit non-goals

- Full `.tex` document compilation.
- Shipping or managing a TeX distribution.
- `\documentclass`, arbitrary `\usepackage`, BibTeX/Biber, document-class management or package installation.
- Overleaf-style multi-file project compilation.
- TikZ graphics; diagram work belongs to E20/E21 or a later focused epic.
- Inventing a new mathematical markup language.

## User-visible acceptance criteria

- [ ] Inline and display equations render correctly in the native Markdown preview.
- [ ] A malformed expression shows a useful local failure state without breaking surrounding Markdown or other equations.
- [ ] Correcting malformed math restores the rendered equation automatically.
- [ ] Source ↔ preview navigation identifies the correct equation after nearby edits.
- [ ] Light/dark theme changes update rendered math appropriately.
- [ ] HTML and PDF exports preserve equations with visually reviewed output.
- [ ] Editing a representative large Markdown document with many unchanged equations remains within the epic's Release-build responsiveness budget.
- [ ] The durable document remains ordinary readable Markdown text; rendered output is derived, cached data only.

## Release placement

E19 runs after E14 establishes the first-party contribution seam and after E12 establishes export. It must complete before E15's whole-app visual/accessibility/performance polish and before strings are frozen for E16.

## Architecture gate

Implementation must not begin until `planning/EPIC_STANDARD.md`'s Definition of Ready is satisfied and a current-master `planning/epic-19-implementation.md` has been reviewed. The architecture pass must select and verify the rendering technology, delimiters, cache model, export representation, accessibility behaviour and end-to-end performance budget from the then-current repository.
