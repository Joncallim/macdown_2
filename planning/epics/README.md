# Epic Index

Epics for the Swift/SwiftUI rewrite. See `../MIGRATION_PLAN.md` for the full plan.
Each file is formatted as a GitHub issue (title/labels/milestone in the header block).

Resolve strictly in dependency order; the critical path is
**E00 → E01 → E04 → E05 → E06 → E07 → E15 → E17**.

| Epic | Title | Milestone | Depends on |
|------|-------|-----------|------------|
| E00 | Project foundations | M1 — Skeleton | — |
| E01 | File & format core | M1 — Skeleton | E00 |
| E02 | Workspace shell | M1 — Skeleton | E01 |
| E03 | Tab system | M1 — Skeleton | E01, E02 |
| E04 | EditorCore: NSTextView + TextKit 2 | M2 — Editor | E01 |
| E05 | Tree-sitter highlighting | M2 — Editor | E04 |
| E06 | Markdown engine | M3 — Markdown core | E01 |
| E07 | Native preview (Textual) | M3 — Markdown core | E06, E04 |
| E08 | Content browser (document outline) | M3 — Markdown core | E06, E02 |
| E09 | Folder browser | M4 — Workspace & formats | E01, E02, E03 |
| E10 | Editing assists | M2 — Editor | E04 |
| E11 | Multi-format: JSON & HTML | M4 — Workspace & formats | E05, E07 |
| E12 | Export: HTML & PDF | M4 — Workspace & formats | E06, E11 |
| E13 | Settings | M4 — Workspace & formats | E02 |
| E14 | Extension points | M5 — Polish & ship | E07 |
| E15 | Liquid Glass polish | M5 — Polish & ship | E07, E09 |
| E16 | Localization | M5 — Polish & ship | stable strings (late) |
| E17 | Distribution & release | M5 — Polish & ship | all |

## Posting to GitHub

Issues are currently **disabled** on the fork. To enable and post:

```bash
gh repo edit Joncallim/macdown --enable-issues
# then, per epic file:
gh issue create --repo Joncallim/macdown \
  --title "<title from file header>" \
  --label epic --label <area> \
  --milestone "<milestone>" \
  --body-file planning/epics/EPIC-XX-*.md
```

(Create labels `epic`, `foundation`, `editor`, `markdown`, `workspace`,
`formats`, `polish`, `release` and milestones M1–M5 first; see MIGRATION_PLAN §6.)
