> **Title:** [EPIC-14] Extension points: first-party contribution seam + user text-filter commands
> **Labels:** `epic`, `formats`, `release` · **Milestone:** M5 — Polish & ship · **Depends on:** E07, E12 export contract

## Owner summary

E14 creates the safe contribution infrastructure that later first-party features can use without turning MacDown 2 back into an in-process plugin host. It also gives power users a simple local text-filter command system and command palette.

The important architectural rule is that the core contribution result is **not a SwiftUI preview view**. A contribution produces renderer-neutral derived content, diagnostics and source identity; Preview and Export adapt that result for their own destinations. This lets E19/E20 render once conceptually and reuse the same result contract for live preview, HTML/PDF export and copy/export actions.

Math and production diagram support remain outside E14. E19 owns the complete math experience; E20 owns the diagram platform + Mermaid; E21 evaluates additional engineering renderers.

## Context

Decision D6. The old NSBundle in-process plugin system (`MPPlugIn`) is retired permanently. macOS 1.0 ships two safe layers: first-party contributions behind an internal protocol, and user-scriptable text filters. A JavaScriptCore-based third-party API may be designed here but remains post-1.0.

E12 owns the export destination contract. E14 must align with it rather than creating a preview-only abstraction that later forces math/diagrams to build parallel rendering paths.

## Scope

- First-party contribution protocol + registry/lifecycle/isolation model.
- Core contribution results expose only the data/capabilities required by the contract: stable source identity/range, derived representation/capability metadata, diagnostics and lifecycle/cancellation state as needed by the architecture.
- SwiftUI views belong at the Preview adapter edge; they are not the only representation a contribution can return.
- Export consumes the same renderer-neutral derived result through E12's export contribution/destination contract.
- A failing contribution degrades only its own block/region and never replaces or destroys the authored source.
- Ship **TOC generation** as a real first-party contribution plus a deterministic internal/test contribution proving registration, isolation, cancellation/publication and preview/export adaptation without pre-building E19/E20.
- Define the capability surface required by later derived technical content without selecting math/diagram engines in this epic.
- **Text-filter commands**: executable local scripts in `~/Library/Application Support/<App>/Commands/`; selection/document → stdin, replacement ← stdout; surfaced in a Commands menu + palette; documented metadata/environment exposes only what the command contract deliberately grants.
- Command palette shell (`⌘⇧P`) hosting filters + app commands.
- Design doc for a possible post-1.0 JavaScriptCore extension API; design only, no third-party loader in macOS 1.0.

## Text-filter security/failure contract

The implementation architecture must freeze concrete limits, but the following behaviour is mandatory:

- launch an executable with structured arguments; never create a shell string by interpolating document text, file paths or user input;
- define the working directory explicitly;
- expose a documented, intentionally bounded environment rather than accidentally inheriting unrestricted process state;
- bound execution time and support cancellation;
- bound captured stdout and stderr;
- perform command work off the main actor so a hung command cannot freeze the app;
- if launch fails, the command exits non-zero, times out, is cancelled or returns unusable replacement output, preserve the original text and surface a useful error;
- replacement is one explicit editor mutation/undoable operation only after successful completion;
- clearly distinguish user-installed commands from built-in first-party functionality;
- first-party document rendering remains local/offline and does not depend on these executable commands.

## Deliverables

1. Contribution protocol/registry + TOC contribution + deterministic isolation/test contribution.
2. Preview adapter and E12-compatible export adapter proving one renderer-neutral result can feed both destinations.
3. Text-filter runner + palette UI; sample scripts and safety behaviour documented.
4. `planning/extension-api-design.md` for the possible post-1.0 JavaScriptCore API.
5. Clear handoff requirements for E19/E20 so those epics can add math/diagram renderers without redesigning contribution ownership casually.

## Acceptance criteria

- [ ] A first-party contribution can publish renderer-neutral derived content/diagnostics/source identity and fail without taking down the rest of the document.
- [ ] The same deterministic test contribution can be consumed by both Preview and Export adapters without duplicating the renderer or requiring a SwiftUI view inside the core contract.
- [ ] TOC generation works through the contribution path rather than a special-case parallel system.
- [ ] Contribution isolation/cancellation/lifecycle behaviour has deterministic automated coverage.
- [ ] A local text filter can uppercase a selection end-to-end as one successful editor mutation.
- [ ] Text-filter launch failure, non-zero exit, timeout, cancellation and oversized/unusable output preserve the original text and show a useful error.
- [ ] Text-filter stdout/stderr/time are bounded according to the architecture contract and command execution cannot block the main actor.
- [ ] No shell interpolation path can turn document content/path text into executable shell syntax.
- [ ] The command palette can invoke both app commands and discovered user filters.
- [ ] Post-1.0 extension API design is documented; E14 does not implement third-party loading.
- [ ] E14 does not claim production math or Mermaid support; those acceptance criteria belong to E19/E20.

## Out of scope

- Production math rendering (E19).
- Mermaid or other diagram renderers (E20/E21).
- Third-party extension loading or distribution/registry UI (post-1.0).
- Reintroducing NSBundle/dylib in-process plugin loading.
- Hosted rendering services.

## Architecture gate

E14 must satisfy `planning/EPIC_STANDARD.md` and `planning/RELEASE_HARDENING.md`. Its architecture must reconcile E12's then-current export contract and explain the contribution model in owner-readable language. It should solve the concrete first-party derived-content and local-command requirements without accumulating a speculative generic plugin framework.
