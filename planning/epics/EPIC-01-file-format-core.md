> **Title:** [EPIC-01] File & format core: FileStore, FileFormat registry, document lifecycle
> **Labels:** `epic`, `foundation` · **Milestone:** M1 — Skeleton · **Depends on:** E00

## Context

We are deliberately **not** using NSDocument (D2 workspace model), so the
document lifecycle — open, save, autosave, dirty tracking, close prompts —
is re-implemented here as a small, exhaustively tested state machine. This is
the highest-risk foundation piece (data-loss class bugs) and gates everything.

## Scope

- `FileFormat` registry: UTType, extensions, highlight language id,
  `PreviewCapability` (.rendered / .toggleable / .none); ships with Markdown,
  HTML, JSON + highlight-only entries (JS/TS, Python, Ruby, CSS, YAML, TOML,
  Swift, C/C++, Bash, SQL, XML)
- `FileStore`: read/write with encoding detection (UTF-8 default), atomic saves
- `FileDocument` model: text storage ref, dirty flag, autosave-on-edit
  (debounced write to the real file for existing files; untitled docs keep a
  recovery buffer in Application Support), close-dirty state machine
- UTType declarations + `CFBundleDocumentTypes` for the new product
- One-time external-change detection (file modified on disk while open)

## Deliverables

1. `FileCore` target with the above, public API documented
2. Unit tests: state machine transitions (edit→dirty→save→clean,
   edit→close→prompt→{save,discard,cancel}), encoding round-trips, atomic
   write failure paths, recovery buffer save/restore
3. UTI/plist entries for all registry formats

## Acceptance criteria

- [ ] Force-quit after editing an untitled doc → content restored on relaunch
- [ ] External modification of an open file surfaces a conflict state (no silent overwrite)
- [ ] Save failure (e.g. permissions) never loses the in-memory or recovery copy
- [ ] `FileFormat.format(for: url)` returns correct format for every registered extension
- [ ] Port of `MPStringLookupTests` utilities used by FileCore passes (Swift Testing)

## Out of scope

UI (no menus/panels yet — E02); tabs (E03); folder watching (E09).

## Notes

This replaces the NSDocument/MPDocument IO core (~most of the 1,800-line
MPDocument.m). Keep the state machine pure and synchronous at its core; do IO
at the edges. Design URLs as security-scoped-ready (D7) even though unsandboxed.
