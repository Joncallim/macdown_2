# AGENTS.md

## What this repo is

Fork of MacDown hosting the **MacDown 2** rewrite (Swift 6 / SwiftUI,
macOS 26+). The rewrite lives on `master`; the legacy ObjC app survives only
as a read-only porting source in `legacy-reference/`.

## Layout

- `legacy-reference/` — legacy ObjC tree (themes, `MPColor`/`MPUtilities`
  tests, resources). Porting source only. Do not modify.
- `MacDown2/` — the new product.
  - `MacDown2/MacDown2/` — app target sources
  - `MacDown2/MacDown2CLI/` — CLI target sources
  - `MacDown2/Packages/MacDownKit/` — SPM modules (see `planning/MIGRATION_PLAN.md` §4)
  - `MacDown2/project.yml` — XcodeGen spec (regenerate; never hand-edit the xcodeproj)
- `planning/` — migration plan + epic definitions; epics are tracked as issues on
  `Joncallim/macdown_2` (milestones M1–M5).

## Commands (from repo root)

| Task | Command |
|---|---|
| Generate Xcode project | `cd MacDown2 && xcodegen generate` |
| Build app | `xcodebuild -project MacDown2/MacDown2.xcodeproj -scheme MacDown2 -destination 'platform=macOS' build` |
| Build + test package | `cd MacDown2/Packages/MacDownKit && swift build && swift test` |
| Lint | `swiftlint lint --strict MacDown2` |
| Format check | `swiftformat --lint MacDown2` |

## Rules

- macOS 26.0 only; no availability checks.
- Swift 6 + strict concurrency; warnings are fixed, not ignored.
- SPM only; third-party deps pinned and wrapped behind internal protocols
  (see `planning/MIGRATION_PLAN.md` §5).
- One branch per epic (`epic/NN-name`) → PR into `master`.
  CI green + tests included + epic issue referenced.
- Tabs are **native `NSWindow` tabs** (as-built E03): one window = one
  document; `WindowCoordinator` owns the pool. Do not reintroduce an in-app
  tab bar.
- Tests use Swift Testing (`@Test`), not XCTest, for all new code.
