# Epic Index

Epics for the Swift/SwiftUI rewrite. See `../MIGRATION_PLAN.md` for the full plan and `../EPIC_STANDARD.md` for the mandatory Definition of Ready, implementation-architecture, slice, Definition of Done and human-readability rules.

The live GitHub issue is the product contract. A current-master `planning/epic-NN-implementation.md` becomes the binding engineering contract only when the epic is ready to start. Implementation slices are execution contracts for workers; they must not require workers to invent architecture.

> **As-built note (amended at #28):** E02/E03 shipped with **native `NSWindow`
> tabs** — one window = one document, per-window sidebar — superseding the
> original single-window in-app tab bar design. Specs written before that
> change carry an "As built" amendment block; where an amendment conflicts
> with older spec text, the amendment wins.

## macOS 1.0 sequencing

The remaining feature sequence is intentionally:

`formats/export/settings → E14 contribution infrastructure → E19 math → E20 diagram platform + Mermaid → E21 engineering diagrams → feature-complete gate → E15 whole-app polish → E16 localisation → E17 distribution`

E20 proves one diagram renderer and the shared rendering/caching/diagnostic/export architecture before E21 adds D2, Graphviz/DOT and WaveDrom.

**No iPad implementation begins before macOS 1.0 is complete and released.** New engine code should avoid unnecessary AppKit coupling when a platform-neutral implementation is equally simple, but the Mac roadmap must not accumulate speculative portability abstractions or UIKit/iPad targets.

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
| E08 | Content browser (document outline) | M3 — Markdown core | E06, E02 | ✅ done (issue #9 closed completed; follow-up issues #34/#36/#37 remain separate) |
| E09 | Folder browser | M4 — Workspace & formats | E01, E02, E03 | ✅ done |
| E10 | Editing assists | M2 — Editor | E04 | ✅ done (issue #11 closed completed; dogfood evidence remains part of release confidence) |
| E11 | Multi-format: JSON, HTML, LaTeX source + language registry | M4 — Workspace & formats | E05, E07 | open |
| E12 | Export: HTML & PDF | M4 — Workspace & formats | E06, E11 | open |
| E13 | Settings | M4 — Workspace & formats | E02 | open |
| E14 | Contribution/extension infrastructure + text filters | M5 — feature completion | E07 | open |
| E19 | First-class math and scientific notation | M5 — feature completion | E10, E12, E14 | open — issue #44 |
| E20 | Native diagram platform + Mermaid | M5 — feature completion | E12, E14 | open — issue #45 |
| E21 | Technical diagrams: D2, Graphviz/DOT, WaveDrom | M5 — feature completion | E20 | open — issue #46 |
| Gate | macOS 1.0 feature-complete audit | before E15 | all major feature epics through E21 | required |
| E15 | Liquid Glass + accessibility + whole-app audit | M5 — polish & ship | E09, E19, E21 + feature-complete gate | open |
| E16 | Localization | M5 — polish & ship | stable strings after E15 | open |
| E17 | Distribution & release | M5 — polish & ship | all macOS 1.0 work | open |
| E18 | Live external-file changes | M4 — Workspace & formats | E01, E03 (as built), E04 | implementation present; hosted CI/sustained dogfooding evidence tracked by its own gate/follow-ups |

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

E18: E01 + E03(as built) + E04; required document-safety/dogfood evidence

E19 + E21 + remaining macOS features
  ─▶ FEATURE-COMPLETE GATE
  ─▶ E15
  ─▶ E16
  ─▶ E17 / macOS 1.0
  ─▶ only then consider iPad epics
```

The exact critical path must be recalculated from live repository state when an epic architecture pass starts; the diagram above is roadmap ordering, not permission to ignore already-shipped dependencies or open regression/follow-up issues.

## Working rules

- Resolve work in dependency order unless the implementation architecture explicitly proves that parallel work is isolated.
- New/revised epics use the product-focused GitHub epic template and `../EPIC_STANDARD.md`.
- Each implementation architecture records its exact baseline SHA and reconciles the issue against live `master`, including relevant open follow-up bugs.
- Feature acceptance criteria require named evidence; package tests alone do not prove complete-app behaviour.
- Architecture/PR/commit prose must remain understandable without the originating agent conversation.
- Residual limitations become explicit follow-up issues rather than disappearing into handoff shorthand.
