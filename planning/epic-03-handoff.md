# EPIC-03 → Implementer Hand-off

> **Full spec:** `planning/epic-03-implementation.md` (read §2 API contracts first — they are binding).
> **Branch:** `epic/03-tab-system` · **Base:** `master` · **Issue:** #4 · PR is draft until §5/§6 are done.

## Context you inherit

- Epic 2 is merged to `master` (PR #23). `rewrite/main` is deleted; **all PRs now target `master`**.
- `WorkspaceModel` is currently single-document (`activeDocument`, `pendingClose`, `pendingAction`) — your TabStore replaces that slot.
- E01 gives you: `FileDocument` value-type state machine (clean/dirty/promptingClose/conflict), `FileStore`, `RecoveryBuffer` (actor, sanitizes any ID).
- CI triggers are fixed on this branch (`rewrite/main` → `master`). The `xcodebuild test` CI step is **yours to add** together with the UITest target — not before (a scheme with no tests fails CI).

## Build order (package first, app second)

1. `WorkspaceSession.swift` + store tests
2. `TabStore.swift` core (tabs/active/new/open/dedupe/navigation) + tests
3. Close flows (single + batch queue) + tests
4. Pin + move + tests
5. Session save/restore + RecoveryBuffer autosave + tests
6. `WorkspaceModel` rewire (compose TabStore; remove `pendingClose`/`pendingAction`) + update E02 tests
7. `TabBarView` + shell wiring + per-tab alert
8. Commands (⌘T, ⌃⇥/⌃⇧⇥, ⌘1…9) + `-UITesting`/`-openFiles` hooks + DEBUG dirty-marking item
9. `MacDown2UITests` target in `project.yml` → `xcodegen generate` → `TabLifecycleUITests`
10. Add `xcodebuild test` step to `ci.yml`

Package suite must be green before you touch the app target.

## Hard rules (review rejects on these)

- `FileDocument` is a value type — always write returned copies back into `tabs[i].document`.
- No prompt on new/open (E02 flow removed); prompt guards closes only. Batch-cancel aborts the whole queue.
- Pinned: always left of unpinned; `moveTab` clamps to pin group; ⌘W no-op on pinned; batch closes skip pinned.
- Dedupe on `standardizedFileURL`; untitled never dedupes. `selectTab(at: 8)` = last tab.
- No AppKit in the package. No new deps. No drag-out windows, no tab-bar glass, no `ContentAreaView` changes.
- Session restore never throws / never blocks launch; missing file → drop tab; corrupt JSON → empty session.
- Tests: Swift Testing (`@Test`) only; temp-dir stores everywhere; never the real session/UserDefaults suites.

## Validate before marking PR ready

```bash
cd MacDown2/Packages/MacDownKit && swift build && swift test
cd ../../.. && swiftformat --lint MacDown2 && swiftlint lint --strict MacDown2
cd MacDown2 && xcodegen generate
xcodebuild -project MacDown2.xcodeproj -scheme MacDown2 -destination 'platform=macOS' build test
xcodebuild -project MacDown2.xcodeproj -scheme macdown2 -destination 'platform=macOS' build
```

## Open decisions (flag on the PR, do not silently resolve)

1. **Cursor/scroll restore is schema-only** (`cursorPosition`/`scrollOffset` fields exist; capture lands with E04's editor — the read-only pane has no cursor). State this in the PR body against the acceptance checklist.
2. If `xcodebuild test` UI tests are flaky on the `macos-15` runner: `continue-on-error: true` + tracking comment, don't block the epic.
3. AGENTS.md + MIGRATION_PLAN.md §7 still reference `rewrite/main` — propose the one-line updates in this PR or a follow-up; owner decides.
