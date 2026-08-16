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
- `planning/EPIC_STANDARD.md` — mandatory Definition of Ready, architecture,
  slice, Definition of Done, and human-readability rules for new epic work.

## Commands (from repo root)

| Task | Command |
|---|---|
| Generate Xcode project | `cd MacDown2 && xcodegen generate` |
| Build app | `xcodebuild -project MacDown2/MacDown2.xcodeproj -scheme MacDown2 -destination 'platform=macOS' build` |
| Build app for dogfooding | same as above + `-configuration Release` — Debug Swift has no optimizations and materially changes how the app feels to type in; judge responsiveness on a Release build, not Debug |
| Build + test package | `cd MacDown2/Packages/MacDownKit && swift build && swift test` |
| Lint | `swiftlint lint --strict MacDown2` |
| Format check | `swiftformat --lint MacDown2` |

## Rules

- macOS 26.0 only; no availability checks.
- Swift 6 + strict concurrency; warnings are fixed, not ignored.
- SPM only; third-party deps pinned and wrapped behind internal protocols
  (see `planning/MIGRATION_PLAN.md` §5).
- One branch per epic (`epic/NN-name`) → PR into `master`.
- Before starting or materially revising an epic, read and follow
  `planning/EPIC_STANDARD.md`.
- An epic must satisfy the Definition of Ready before broad implementation
  begins. The implementation architecture is written from the current live
  `master` state, not copied blindly from an older issue.
- The implementation architecture is binding for the epic branch. Workers may
  make ordinary local coding decisions, but must stop when a false assumption
  would require new architecture, a new cross-module dependency, changed
  product behaviour, weakened tests, or edits outside the authorised area.
- CI green + tests included + epic issue referenced are required for a PR, but
  they are not by themselves the Definition of Done. Release-build evidence,
  required dogfood paths, documentation reconciliation and residual risks must
  also be recorded where applicable.
- Tabs are **native `NSWindow` tabs** (as-built E03): one window = one
  document; `WindowCoordinator` owns the pool. Do not reintroduce an in-app
  tab bar.
- Tests use Swift Testing (`@Test`), not XCTest, for all new package code.
- iPad implementation is explicitly post-macOS-1.0 work. Do not add iPad
  targets, UIKit shells or speculative portability layers before the Mac app is
  feature-complete and released. New engine-level code should avoid gratuitous
  AppKit coupling when a platform-neutral design is equally simple, but do not
  add abstraction solely for a future iPad port.

## Human-readable repository history

The repository must be understandable without access to the chat, prompt or
agent session that produced a change.

- Commit subjects describe the actual outcome in plain English. Epic/slice IDs
  may be appended for traceability but cannot replace the description.
- Avoid agent shorthand such as `E20 S3`, `wire seam`, `follow-up`, `agent
  changes`, or `WIP` as standalone commit subjects.
- When a commit's reason is not obvious, include short `What`, `Why`, and
  `Verification` paragraphs in the commit body.
- PR descriptions lead with: **What this changes**, **Why**, **How it works**,
  **What I should test**, **Risks and limits**, and **Verification**. Technical
  symbol-level detail comes after the human summary.
- Architecture documents begin with an owner summary that states the user
  outcome, rationale, main approach, risks and non-goals in ordinary language.
- Define non-obvious abbreviations and specialised terms on first use.
- Comments and documentation explain durable behaviour and rationale, not the
  temporary orchestration process used to generate the code.

If the owner cannot understand what changed, why it was chosen, what could go
wrong and how to test it without reading the implementation diff, the
communication is not complete.
