> **Title:** [EPIC-14] Extension points: PreviewContribution protocol + user text-filter commands
> **Labels:** `epic`, `formats`, `release` · **Milestone:** M5 — Polish & ship · **Depends on:** E07

## Context

Decision D6. The old NSBundle in-process plugin system (MPPlugIn) is retired
permanently. v1 ships the two safe layers: first-party preview contributions
behind a protocol, and user scriptable text filters. A JSCore-based third-party
API is *designed* here but built post-v1.

## Scope

- `PreviewContribution` protocol: contributions receive parsed fenced blocks
  and can return custom SwiftUI views; ship built-ins for **math** (Textual
  math), **Mermaid diagrams** (render to SVG via a bundled JS engine evaluated
  in JavaScriptCore, not a web view), and **TOC generation**
- Mermaid contribution must render off-main and cache by source hash
- **Text-filter commands**: executable scripts in
  `~/Library/Application Support/<App>/Commands/`; selection/document → stdin,
  replacement ← stdout; surfaced in a Commands menu + palette; env vars expose
  file path, selection range, format id
- Design doc: proposed v1.x JavaScriptCore extension API (events, block
  renderers, sandboxing model) — written, reviewed, not implemented
- Command palette shell (⌘⇧P) hosting filters + app commands

## Deliverables

1. Protocol + 3 built-in contributions (math, Mermaid, TOC)
2. Text-filter runner + palette UI; sample scripts in docs
3. `planning/extension-api-design.md`

## Acceptance criteria

- [ ] ```mermaid fences render as diagrams in preview without a web view
- [ ] A Python text filter can uppercase a selection end-to-end
- [ ] Contributions are isolated: a failing contribution degrades its block,
      never the app
- [ ] Design doc approved and issues for v1.x extension API filed

## Out of scope

Third-party extension loading, distribution/registry UI (v1.x+).

## Notes

Mermaid via JSCore keeps the no-WKWebView-for-Markdown rule (D4). Evaluate
bundle-size cost of shipping the Mermaid JS; lazy-load it.
