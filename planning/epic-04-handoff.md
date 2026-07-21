# EPIC-04 → Implementer Hand-off

> **Full spec:** `planning/epic-04-implementation.md` (read §2 API contracts + §3 the
> two hard invariants first — they are binding).
> **Branch:** `epic/04-editorcore` · **Base:** `master` · **Issue:** #5 · PR is **draft**
> until §5/§6 pass. Intended for an OpenCode agent (Kimi 2.7 / DeepSeek V4) to build
> **directly on this branch/PR**.

## Context you inherit

- Epics 00–03 are merged; the repo was re-rooted to **MacDown 2 only** (no upstream
  history). `master` is the base. There is no `epic/03-tab-system` branch anymore.
- E01 gives you `FileCore.FileDocument` — a **value-type** state machine
  (`clean/dirty/promptingClose/conflict`) with `.text`, `.fileURL`, `.state`,
  `load/save/saveAs/autosave`. Your only FileCore change is `edited(text:)` (spec §2.3.1).
- E03 gives you `Workspace.TabStore` (`tabs[i].document`), per-tab session schema with
  `cursorPosition`/`scrollOffset` **currently unpopulated** — you populate them.
- The integration seam is `MacDown2/ContentAreaView.swift:135` (`SourcePane`, a
  read-only `Text`). You replace it with `EditorView`.
- `EditorCore` **may import AppKit** (it is the NSTextView wrapper). No new third-party deps.

## Build order (package first, app second)

1. `EditorConfiguration` + `TextKitStack` (TK2 assembly, TK1 seam) + tests
2. `EditorTextSystem` (TK2 stack + per-tab undo + selection/scroll + `setText`) + tests
3. `EditorTextSystemStore` (cache by `WorkspaceTab.id`; `evict` tears down) + weak-ref leak test
4. `FileDocument.edited(text:)` in FileCore + tests
5. `EditorView` `NSViewRepresentable` (make/update + **keystroke echo-guard**) + tests
6. Word wrap / overscroll / insets / line-height + tests
7. `EditorFind` (stock `NSTextFinder`)
8. `EditorPerformanceTests` — 1 MB / 10 MB / keystroke budgets (spec §2.8)
9. App wiring: `ContentAreaView` write-back; per-window `EditorTextSystemStore` in
   `WindowCoordinator`; `evict` on tab close; caret/scroll → E03 session restore
10. `EditorTypingUITests` + `xcodegen generate`

**Package suite green before you touch the app target.**

## Hard rules (review rejects on these)

- **Value type:** every edit is `tabs[i].document = tabs[i].document.edited(text:)`. Never mutate in place.
- **No echo loop:** `updateNSView` applies model→view text **only** on a real external
  change, guarded by an `isApplyingModelText` flag + value compare. This is the #1 bug.
- **Per-tab text system persists across tab switches** (cached by tab id); **closing a
  tab evicts + deallocates it** (weak-ref test proves it).
- **Viewport-lazy only.** Never force whole-document layout on open — it breaks the 10 MB
  budget. No eager `ensureLayout(for: documentRange)`.
- **Perf/behaviour gates live in `EditorCoreTests` (`swift test`)**, NOT the XCUITest
  target — `xcodebuild test` cannot run on the `macos-15` CI runner (macOS 26 target).
  The XCUITest is `build-for-testing` only in CI; run it locally on macOS 26.
- Keep `EditorTextSystem.contentStorage`/`layoutManager` **stable** — E05 (Highlighting)
  attaches there.
- Swift Testing (`@Test`); temp-dir stores; never real UserDefaults/session suites.
- **No `ci.yml` change needed** — existing `swift test` + UI-test-build steps cover E04.

## Validate before marking PR ready

```bash
cd MacDown2/Packages/MacDownKit && swift build && swift test
cd ../../.. && swiftformat --lint MacDown2 && swiftlint lint --strict MacDown2
cd MacDown2 && xcodegen generate
xcodebuild -project MacDown2.xcodeproj -scheme MacDown2 -destination 'platform=macOS' build build-for-testing
xcodebuild -project MacDown2.xcodeproj -scheme macdown2 -destination 'platform=macOS' build
```

## Open decisions (flag on the PR, do not silently resolve)

1. **Perf budgets** (300 ms open / 50 ms keystroke) are dev-machine targets — calibrate
   on the CI runner and report the measured numbers; apply *documented* headroom, never a silent loosen.
2. **TextKit 1 fallback:** ship the seam + stub only; build a real TK1 path only against a
   concrete misbehaving file.
3. **Undo granularity:** NSTextView default unless product asks for word-level — flag, don't invent.
4. **Store ownership:** per-window via `Environment`; raise a flag before making it a singleton.

## Note on CI for this PR

This PR starts as **architecture docs only** (`planning/**`), which the CI `paths`
filter intentionally ignores — so **expect no checks until the first `MacDown2/**`
commit lands**. Once you push EditorCore code, `lint` + `build-and-test` run automatically
on every push.
