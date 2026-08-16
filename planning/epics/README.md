# Epic Index

Epics for the Swift/SwiftUI rewrite. See `../MIGRATION_PLAN.md` for the full plan, `../EPIC_STANDARD.md` for the mandatory Definition of Ready/architecture/slice/Definition of Done rules, and `../RELEASE_HARDENING.md` for cross-epic macOS 1.0 integration and release gates.

The live GitHub issue is the product contract. A current-master `planning/epic-NN-implementation.md` becomes the binding engineering contract only when the epic is ready to start. Implementation slices are execution contracts for workers; they must not require workers to invent architecture.

> **As-built note (amended at #28):** E02/E03 shipped with **native `NSWindow`
> tabs** — one window = one document, per-window sidebar — superseding the
> original single-window in-app tab bar design. Specs written before that
> change carry an "As built" amendment block; where an amendment conflicts
> with older spec text, the amendment wins.

## macOS 1.0 sequencing

The remaining feature sequence is intentionally:

`formats/export/settings → E14 contribution infrastructure → E19 math → E20 diagram platform + Mermaid → E21 renderer admission/integration → feature-complete gate + identity freeze → E15 whole-app polish/first-run → E16 localisation/string freeze → E17 migration/distribution`

E20 proves one diagram renderer and the shared rendering/caching/diagnostic/export architecture. E21 evaluates D2, Graphviz/DOT and WaveDrom individually; a candidate may be rejected for macOS 1.0 when licensing, security, bundle/runtime cost, maintenance or product value does not justify shipping it.

**No iPad implementation begins before macOS 1.0 is complete and released.** New engine code should avoid unnecessary AppKit coupling when a platform-neutral implementation is equally simple, but the Mac roadmap must not accumulate speculative portability abstractions or UIKit/iPad targets.

## Cross-epic release rules

`planning/RELEASE_HARDENING.md` does not add an epic. It binds the existing roadmap on matters that individual epics cannot safely own in isolation:

- first-party editing/preview/math/diagram/export remains local/offline and does not upload document content;
- E12 provides the export destination contract and E14 provides renderer-neutral derived content so Preview/Export do not diverge;
- text-filter commands have bounded execution/output and failure preserves source;
- the feature-complete gate freezes the public identity before E15/E16;
- one release-evidence ledger distinguishes implementation completion from real-app/release proof;
- critical XCUITests must actually execute on macOS 26 before 1.0;
- text round-trip fidelity is explicitly proven;
- E15 finalises first-run/in-app copy, E16 freezes/localises it, E17 must not invent new in-app UI after string freeze;
- E17 rehearses migration of representative real beta/development state into the release identity/update channel;
- no P0/P1 may remain for macOS 1.0.

## Epic table

| Epic | Title | Milestone/phase | Depends on | Status |
|------|-------|-----------------|------------|--------|
| E00 | Project foundations | M1 — Skeleton | — | ✅ done |
| E01 | File & format core | M1 — Skeleton | E00 | ✅ done |
| E02 | Workspace shell | M1 — Skeleton | E01 | ✅ done |
| E03 | Tab system | M1 — Skeleton | E01, E02 | ✅ done (native tabs) |
| E04 | EditorCore: NSTextView + TextKit 2 | M2 — Editor | E01 | ✅ done |
| E05 | Tree-sitter highlighting | M2 — Editor | E04 | ✅ done |
| E06 | Markdown engine | M3 — Markdown core | E01 | ✅ done (issue #7 closed completed) |
| E07 | Native preview (Textual) | M3 — Markdown core | E06, E04 | ✅ done (issue #8 closed completed; follow-up bugs tracked separately) |
| E08 | Content browser (document outline) | M3 — Markdown core | E06, E02 | ✅ done (issue #9 closed completed; follow-up issues tracked separately) |
| E09 | Folder browser | M4 — Workspace & formats | E01, E02, E03 | ✅ done |
| E10 | Editing assists | M2 — Editor | E04 | ✅ done (issue #11 closed completed; dogfood evidence remains part of release confidence) |
| E11 | Multi-format: JSON, HTML, LaTeX source + language registry | M4 — Workspace & formats | E05, E07 | open; existing architecture PR must be reconciled to current contract before implementation |
| E12 | Export: HTML/PDF + shared derived-content destination | M4 — Workspace & formats | E06, E11 | open |
| E13 | Settings | M4 — Workspace & formats | E02 | open |
| E14 | Renderer-neutral first-party contributions + text filters | M5 — feature completion | E07, E12 export contract | open |
| E19 | First-class math and scientific notation | M5 — feature completion | E10, E12, E14 | open — issue #44 |
| E20 | Native diagram platform + Mermaid | M5 — feature completion | E12, E14 | open — issue #45 |
| E21 | Evaluate/integrate D2, Graphviz/DOT, WaveDrom | M5 — feature completion | E20 | open — issue #46; each candidate admitted separately |
| Gate | macOS 1.0 feature-complete audit + public identity freeze | before E15 | all major feature epics through E21 | required; owns release-evidence/text-fidelity/UI-test proof |
| E15 | Liquid Glass + accessibility + whole-app audit + final first-run | M5 — polish & ship | frozen identity, E09, E19, E21 + feature-complete gate | open |
| E16 | Localization + in-app string freeze | M5 — polish & ship | final identity + final E15 in-app UI/copy | open |
| E17 | Stateful migration, distribution & release | M5 — polish & ship | all macOS 1.0 work + E15/E16 | open |
| E18 | Live external-file changes | M4 — Workspace & formats | E01, E03 (as built), E04 | implementation present/issue closed; remaining evidence belongs in release ledger |

## Dependency summary

```text
E00 ─▶ E01 ─▶ E02 ─▶ E03 ─▶ E09
  │      │
  │      ├─▶ E04 ─▶ E05 ─▶ E10
  │      │
  │      └─▶ E06 ─▶ E07 ─▶ E08
  │                   │
  │                   ├─▶ E11 ─▶ E12 ─┐
  │                   │                 ├─▶ E19 ─┐
  │                   └────────▶ E14 ──┤       │
  │                                     └─▶ E20 ─▶ E21
  │
  └────────────────────▶ E13

E18: E01 + E03(as built) + E04; document-safety evidence carried into release ledger

E19 + E21 + remaining Mac features
  ─▶ FEATURE-COMPLETE GATE + IDENTITY FREEZE
  ─▶ E15 (final in-app/first-run polish)
  ─▶ E16 (in-app string freeze)
  ─▶ E17 (state migration + signed/updateable macOS 1.0 release)
  ─▶ only then consider iPad epics
```

The exact critical path must be recalculated from live repository state when an epic architecture pass starts; the diagram above is roadmap ordering, not permission to ignore already-shipped dependencies or open regression/follow-up issues.

## Working rules

- Resolve work in dependency order unless the implementation architecture explicitly proves that parallel work is isolated.
- New/revised epics use the product-focused GitHub epic template, `../EPIC_STANDARD.md`, and applicable `../RELEASE_HARDENING.md` constraints.
- Each implementation architecture records its exact baseline SHA and reconciles the issue against live `master`, including relevant open follow-up bugs and newer cross-epic contracts.
- Older architecture work is not automatically binding after its product/release contract changes; it must be refreshed before implementation.
- Feature acceptance criteria require named evidence; package tests alone do not prove complete-app behaviour.
- Architecture/PR/commit prose must remain understandable without the originating agent conversation.
- Residual limitations become explicit follow-up issues or release-ledger entries rather than disappearing into handoff shorthand.
- The release gate records unknown/unavailable evidence as unverified, never inferred as passed.
