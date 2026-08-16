> **Title:** [EPIC-14] Extension points: PreviewContribution protocol + user text-filter commands
> **Labels:** `epic`, `formats`, `release` · **Milestone:** M5 — Polish & ship · **Depends on:** E07

## Owner summary

E14 creates the safe extension/contribution infrastructure that later first-party features can use without turning MacDown 2 back into an in-process plugin host. It also gives power users a simple text-filter command system and command palette.

Math and production diagram support are no longer hidden inside this infrastructure epic. E19 owns the complete math experience; E20 owns the diagram platform + Mermaid; E21 adds further engineering diagram languages. That keeps E14 small enough to prove the seam before major product features depend on it.

## Context

Decision D6. The old NSBundle in-process plugin system (`MPPlugIn`) is retired permanently. macOS 1.0 ships two safe layers: first-party preview contributions behind an internal protocol, and user scriptable text filters. A JavaScriptCore-based third-party API is designed here but built post-1.0.

## Scope

- `PreviewContribution` protocol and contribution registry for first-party preview features.
- Contributions receive only the data/capabilities required by their contract and fail independently; a failing contribution degrades its own block/region rather than the document or app.
- Ship **TOC generation** as a real first-party contribution plus a deterministic internal/test contribution that proves registration, isolation, cancellation/publication behaviour and lifecycle without pre-building E19/E20.
- Define the capability surface required by future derived preview content (source identity, diagnostics and derived render output) without selecting math/diagram-specific engines in this epic.
- **Text-filter commands**: executable scripts in `~/Library/Application Support/<App>/Commands/`; selection/document → stdin, replacement ← stdout; surfaced in a Commands menu + palette; environment variables expose file path, selection range and format id.
- Command palette shell (`⌘⇧P`) hosting filters + app commands.
- Design doc: proposed post-1.0 JavaScriptCore extension API (events, block renderers, sandboxing model) — written and reviewed, not implemented.
- Security/failure boundaries for external text-filter processes must be explicit in the implementation architecture.

## Deliverables

1. Contribution protocol/registry + TOC contribution + deterministic isolation/test contribution.
2. Text-filter runner + palette UI; sample scripts in docs.
3. `planning/extension-api-design.md` for the possible post-1.0 JavaScriptCore API.
4. Clear handoff requirements for E19/E20 so those epics can implement first-party math/diagram features without changing the contribution ownership model casually.

## Acceptance criteria

- [ ] A first-party contribution can register, render/publish derived preview content and fail without taking down the rest of the preview.
- [ ] TOC generation works through the contribution path rather than a special-case parallel system.
- [ ] Contribution isolation/cancellation/lifecycle behaviour has deterministic automated coverage.
- [ ] A Python text filter can uppercase a selection end-to-end.
- [ ] Text-filter failure produces a useful user-facing error and never destroys the original selection/document content silently.
- [ ] The command palette can invoke both app commands and discovered text filters.
- [ ] Post-1.0 extension API design is documented and follow-up issues are filed if appropriate.
- [ ] E14 does not claim production math or Mermaid support; those acceptance criteria belong to E19/E20.

## Out of scope

- Production math rendering (E19).
- Mermaid or other diagram renderers (E20/E21).
- Third-party extension loading or distribution/registry UI (post-1.0).
- Reintroducing NSBundle/dylib in-process plugin loading.

## Notes

E14 is an infrastructure epic. Its implementation architecture must follow `planning/EPIC_STANDARD.md` and remain readable as a product-enabling seam rather than accumulating speculative generic plugin abstractions.
