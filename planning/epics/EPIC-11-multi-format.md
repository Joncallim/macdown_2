> **Title:** [EPIC-11] Multi-format support: JSON tools, HTML preview, LaTeX source and language registry
> **Labels:** `epic`, `formats` · **Milestone:** M4 — Workspace & formats · **Depends on:** E05, E07

## Owner summary

MacDown 2 should be a good text editor even when the active file is not Markdown. E11 completes that baseline: JSON gets useful structured tooling, HTML gets an explicit rendered view, LaTeX/TeX source becomes a recognised technical text format, and the remaining supported code/text extensions get correct syntax highlighting and a clear no-preview state.

This epic does **not** compile full LaTeX documents. First-class mathematical notation inside Markdown is E19.

## Problem

The app already presents itself as a workspace-style Markdown **and code** editor, but partial format registration is not enough. A user opening JSON, HTML, TeX or common source files should receive deliberate behaviour rather than accidental Markdown parsing or an ambiguous empty preview.

## Representative user journeys

1. **JSON:** open invalid JSON, see the exact error location, fix it, pretty-print it as one undoable edit, and navigate its outline.
2. **HTML:** edit an HTML file and explicitly switch between source and its sandboxed rendered view.
3. **LaTeX source:** open `.tex`/`.latex` source, receive correct format recognition and syntax highlighting, edit commands/comments/braces as text, and see a clear "no native document preview" state rather than Markdown behaviour.
4. **Other source:** open a registered Python/YAML/Swift/etc. file and receive the correct language highlighting and format information without paying for an unused Markdown parse path.
5. **Save As:** change a document extension/format and have the active parser/highlighter/preview capabilities update consistently.

## Scope

- **JSON**: validation on debounce with useful line/column diagnostics, pretty-print/format command, collapsible outline in the content browser, optional sort-keys behaviour if retained by the implementation architecture.
- **HTML**: source ↔ rendered toggle in the preview pane. Rendered HTML uses a sandboxed `WKWebView`; HTML is the deliberate web-preview exception and does not change D4 for Markdown.
- **LaTeX/TeX source**: register `.tex` and `.latex` (plus any additional conventional extension only if verified during architecture), add appropriate syntax highlighting, and expose format metadata/no-preview behaviour. Editor pairing/indent behaviour may reuse safe generic text editing behaviour but E11 does not build a TeX language server or compiler.
- **Other languages**: complete the grammar/format registry for the supported v1 set. The implementation architecture must reconcile the actual E05 registry and dependency state before choosing exact grammar packages.
- **Preview routing**: format capability decides Markdown preview, HTML rendered view, JSON outline/no-preview, or clean no-preview information. Non-Markdown files must not be fully Markdown-parsed merely because the parser is already present.
- **Save As / format transition** behaviour updates highlighting, editing capabilities and preview routing without reopening the document.
- Preserve the text-fidelity/local-offline invariants in `planning/RELEASE_HARDENING.md`; HTML preview must not turn ordinary local editing into an external network requirement.

## Explicit non-goals

- Full LaTeX compilation or PDF generation from `.tex` source.
- TeX distribution/package management, BibTeX/Biber, `\documentclass` workflow or Overleaf-style projects.
- First-class Markdown math rendering (E19).
- JSON Schema validation.
- HTML-specific editing assists beyond safe general text editing.
- Language-server-protocol integrations.

## User-visible acceptance criteria

- [ ] Invalid JSON shows a useful line/column diagnostic and fixing the source clears it promptly.
- [ ] JSON pretty-print is one undoable edit and the JSON outline navigates correctly.
- [ ] HTML source can be switched to a deliberately sandboxed rendered view with documented local-resource/network behaviour.
- [ ] `.tex`/`.latex` files are recognised as LaTeX/TeX source, receive appropriate highlighting and never enter the Markdown preview/parser path accidentally.
- [ ] Every registered extension opens with its intended highlighting/capabilities or a clear no-preview state containing useful format information.
- [ ] Save As between formats updates active behaviour without requiring app restart/reopen.
- [ ] Large non-Markdown files do not perform a full Markdown parse on every edit when no Markdown-derived feature consumes that result.
- [ ] Format editing/Save As does not gratuitously normalise unrelated encoding/line-ending/final-newline state outside the explicit file-format contract.

## Release placement

E11 completes general format behaviour before E12 export and before the technical-writing feature epics. `.tex` editing is intentionally lightweight; E19 adds equation rendering to Markdown without waiting for a full TeX compiler.

## Architecture reconciliation requirement

The open E11 architecture PR (#43) predates the 2026-08-16 product/release-contract changes. It is **not binding for implementation until refreshed** against the current `master`, this revised E11 contract, `planning/EPIC_STANDARD.md`, `planning/RELEASE_HARDENING.md`, issue #35 and any other relevant live follow-ups.

## Architecture gate

E11 must satisfy both `planning/EPIC_STANDARD.md` and `planning/RELEASE_HARDENING.md` before implementation begins. The refreshed current-master architecture must verify the exact v1 format/grammar set, text-fidelity behaviour and HTML `WKWebView` security/resource/navigation/lifecycle contract.
