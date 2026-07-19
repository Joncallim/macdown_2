> **Title:** [EPIC-00] Project foundations: Xcode 26 project, SPM modules, CI
> **Labels:** `epic`, `foundation` · **Milestone:** M1 — Skeleton · **Depends on:** —

## Context

Greenfield rewrite as a new product (D5), macOS 26+ only (D1). The ObjC project
(Xcode 9.2-era, CocoaPods, 10.8 deployment target) is reference-only. Everything
new starts here. **Blocker:** product name + bundle ID (open decision O1) — a
codename placeholder is acceptable for this epic.

## Scope

- New Xcode 26 project + workspace, Swift 6 with strict concurrency enabled
- SwiftPM modular target structure per MIGRATION_PLAN §4 (empty-but-compiling targets)
- `rewrite/main` branch; commit `planning/` docs as first commit
- GitHub Actions CI on `macos-26`: build + test on PR and push
- SwiftFormat + SwiftLint configs, wired into CI
- `AGENTS.md` at repo root (build/test commands, module map, conventions)
- MIT LICENSE (carried over), README stub with new product codename

## Deliverables

1. `<Product>.xcodeproj` building an empty window app on macOS 26 SDK
2. SPM package(s) with targets: FileCore, Workspace, EditorCore, Highlighting,
   MarkdownEngine, Preview, OutlineUI, FileTree, ExportService, AppSettings,
   Themes, CLITool (stubs)
3. `.github/workflows/ci.yml` green on the scaffolding PR
4. `AGENTS.md`, `.swiftformat`, `.swiftlint.yml`, updated `.gitignore`

## Acceptance criteria

- [ ] `xcodebuild -scheme <Product> -destination 'platform=macOS' build` succeeds on macos-26 runner
- [ ] `swift test` runs (even if only placeholder tests) and CI is green
- [ ] App launches to an empty window locally on macOS 26
- [ ] `AGENTS.md` documents every command a contributor/agent needs
- [ ] No CocoaPods, no git submodules in the new tree

## Out of scope

Any UI beyond a blank window; file IO; Sparkle; signing/notarization (E17).

## Notes

Set deployment target to 26.0 everywhere from day one — no availability
checks anywhere in the codebase, ever. Strict concurrency on now, not later.
