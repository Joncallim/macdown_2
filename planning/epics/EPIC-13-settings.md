> **Title:** [EPIC-13] Settings: SwiftUI Settings scene, @AppStorage model, migration map
> **Labels:** `epic`, `workspace` · **Milestone:** M4 — Workspace & formats · **Depends on:** E02

## Context

Replaces PAPreferences + MASPreferences + 5 XIB panes with a native SwiftUI
`Settings` scene. ~50 MPPreferences keys need triage: keep / rename / drop.

## Scope

- `AppSettings` target: typed settings model over `@AppStorage`/`AppStorage`
  with observation into the workspace
- Panes (SwiftUI, native macOS 26 look): General, Editor, Markdown (GFM
  toggles feeding E06 options), Preview/Export, Formats
- Key-by-key migration map document from MPPreferences (ObjC) → new keys
- Optional (open decision O3): one-time import of old MacDown preferences if
  `com.uranusjr.macdown` defaults detected
- Settings changes apply live (no relaunch) across open tabs

## Deliverables

1. Settings model + all panes
2. Migration map table in `planning/` + import logic (if O3 approved)
3. Unit tests (port of `MPPreferencesTests` font persistence + new defaults
   matrix test: every key has a default and is read exactly once per launch)

## Acceptance criteria

- [ ] Every setting takes effect without relaunch on already-open tabs
- [ ] Fresh launch uses documented defaults; no orphaned keys
- [ ] Font/theme pickers integrate with the theme system (E05/E07)
- [ ] Migration map reviewed and complete (all ~50 keys accounted for)

## Out of scope

Update-channel prefs (E17 owns Sparkle settings); plugin prefs (E14).

## Notes

This is where old behavior defaults live — default GFM flags must match
MacDown's so documents render identically out of the box.
