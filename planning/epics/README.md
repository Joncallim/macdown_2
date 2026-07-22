# Epic Index

Epics for the Swift/SwiftUI rewrite. See `../MIGRATION_PLAN.md` for the full plan.
Each file is formatted as a GitHub issue (title/labels/milestone in the header
block); the live issues are on `Joncallim/macdown_2`.

Resolve strictly in dependency order; the critical path is
**E00 → E01 → E04 → E05 → E06 → E07 → E15 → E17**.
**E18** (added at the mid-point check-in, #28) must land before sustained
dogfooding begins.

> **As-built note (amended at #28):** E02/E03 shipped with **native `NSWindow`
> tabs** — one window = one document, per-window sidebar — superseding the
> original single-window in-app tab bar design. Specs written before that
> change carry an "As built" amendment block; where an amendment conflicts
> with older spec text, the amendment wins.

| Epic | Title | Milestone | Depends on | Status |
|------|-------|-----------|------------|--------|
| E00 | Project foundations | M1 — Skeleton | — | ✅ done |
| E01 | File & format core | M1 — Skeleton | E00 | ✅ done |
| E02 | Workspace shell | M1 — Skeleton | E01 | ✅ done |
| E03 | Tab system | M1 — Skeleton | E01, E02 | ✅ done (native tabs) |
| E04 | EditorCore: NSTextView + TextKit 2 | M2 — Editor | E01 | ✅ done |
| E05 | Tree-sitter highlighting | M2 — Editor | E04 | ✅ done |
| E06 | Markdown engine | M3 — Markdown core | E01 | open |
| E07 | Native preview (Textual) | M3 — Markdown core | E06, E04 | open |
| E08 | Content browser (document outline) | M3 — Markdown core | E06, E02 | open |
| E09 | Folder browser | M4 — Workspace & formats | E01, E02, E03 | open |
| E10 | Editing assists | M2 — Editor | E04 | open |
| E11 | Multi-format: JSON & HTML | M4 — Workspace & formats | E05, E07 | open |
| E12 | Export: HTML & PDF | M4 — Workspace & formats | E06, E11 | open |
| E13 | Settings | M4 — Workspace & formats | E02 | open |
| E14 | Extension points | M5 — Polish & ship | E07 | open |
| E15 | Liquid Glass polish | M5 — Polish & ship | E07, E09 | open |
| E16 | Localization | M5 — Polish & ship | stable strings (late) | open |
| E17 | Distribution & release | M5 — Polish & ship | all | open |
| E18 | Live external-file changes | M4 — Workspace & formats | E01, E03 (as built), E04 | open (added at #28) |
