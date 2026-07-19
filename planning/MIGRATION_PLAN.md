# MacDown → Swift/SwiftUI Migration Plan

> Status: **approved direction** · Scope: full rewrite as a **new product** · Target: **macOS 26+ only**

This document is the single source of truth for the rewrite. Epics live in
`planning/epics/` and are intended to be posted as GitHub issues on the fork.

---

## 1. Vision

A fast, native, workspace-style Markdown & code editor for macOS 26 "Tahoe":
Swift 6 + SwiftUI, Liquid Glass interface, tabbed editing, collapsible folder
browser, per-document content browser (outline), and first-class support for
JSON, HTML, and other popular languages — not just Markdown.

## 2. Locked Decisions

| # | Decision | Choice |
|---|----------|--------|
| D1 | Deployment floor | **macOS 26+ only** (Xcode 26 SDK, Swift 6, Liquid Glass automatic; no `UIDesignRequiresCompatibility`) |
| D2 | Tab model | **In-app workspace tabs** in a single window (not native window tabs), plus a **content browser** (heading outline of the active document) placed above or below the folder browser |
| D3 | Editor | **Custom NSTextView + TextKit 2** wrapped in `NSViewRepresentable`, **tree-sitter** highlighting (via SwiftTreeSitter). Priority: fastest, smoothest experience |
| D4 | Markdown preview | **Native SwiftUI via Textual** (no WKWebView for Markdown) |
| D5 | Identity | **New product** — new name, bundle ID, icon, appcast. MacDown fork serves as reference + resource donor |
| D6 | Extensions | v1: internal `PreviewContribution` protocol (math/diagrams/TOC built in) + user **text-filter commands** (stdin/stdout scripts). Post-v1: JavaScriptCore extension API. **Never** resurrect NSBundle in-process loading |
| D7 | Sandboxing | **Unsandboxed** for now (direct distribution). `FileTreeModel` still designed around security-scoped URLs so sandboxing is additive later |

## 3. Product Shape

```
┌────────────────────────────────────────────────────────────────┐
│ Toolbar (glass)                              [sidebar toggle]  │
├──────────────┬─────────────────────────────────────────────────┤
│ SIDEBAR      │ Tab bar (pin / dirty dot / close / reorder)     │
│ (collapsible)├──────────────────────────────┬──────────────────┤
│              │                              │                  │
│ ▾ FOLDER     │  Editor                      │  Preview         │
│   browser    │  NSTextView + TextKit 2      │  Textual (MD)    │
│ ──────────── │  + tree-sitter highlight     │  WKWebView(HTML) │
│ ▾ CONTENT    │                              │  Outline (JSON)  │
│   browser    │                              │                  │
│   (headings  │                              │                  │
│   of active  │                              │                  │
│   document)  │                              │                  │
└──────────────┴──────────────────────────────┴──────────────────┘
```

- **Scene model:** single `WindowGroup` + `WorkspaceModel`. **Not** `DocumentGroup`
  (fights the one-window-many-tabs model). Per-tab file state owned by `TabStore`.
- **Document lifecycle is re-implemented** (no NSDocument): autosave-on-edit,
  dirty tracking, close-dirty prompts, session restore. This is a deliberate
  trade; it gets a dedicated state machine + heavy UI tests (EPIC-01/03).

## 4. Module Map (SwiftPM targets)

| Target | Responsibility | Replaces (ObjC) |
|---|---|---|
| `App` | `@main`, `WindowGroup`, commands, menus | MPMainController, MainMenu.xib |
| `Workspace` | WorkspaceModel, TabStore, session restore | — (new) |
| `FileCore` | FileStore (open/save/autosave), FileFormat registry, UTI decls | MPDocument (IO parts), Info.plist types |
| `FileTree` | Folder browser model: lazy loading, FS watching, CRUD | — (new) |
| `EditorCore` | NSTextView+TextKit2 representable, viewport layout, assists | MPEditorView, NSTextView+Autocomplete |
| `Highlighting` | SwiftTreeSitter engine, grammar registry, theme engine | peg-markdown-highlight |
| `MarkdownEngine` | swift-markdown parse actor, debounce, front matter, source-range index | MPRenderer, Hoedown, LibYAML |
| `Preview` | Format router: MD→Textual, HTML→WKWebView, JSON→outline; scroll sync | WebView, templates, Prism |
| `OutlineUI` | Content browser (heading tree of active doc) | — (new) |
| `ExportService` | HTML (cmark-gfm renderer) + PDF export, templates | MPAsset, MPExportPanel…, handlebars |
| `AppSettings` | `Settings` scene + `@AppStorage` model | PAPreferences, MASPreferences, 5 XIBs |
| `ExtensionKit` (v1.x) | PreviewContribution protocol, text-filter commands | MPPlugIn (retired) |
| `CLITool` | swift-argument-parser launcher | macdown-cmd, GBCli |
| `Themes` | Ported editor/preview themes | Resources/*.styles, *.css |

## 5. Technology Selections (verified July 2026)

| Concern | Choice | Notes |
|---|---|---|
| Markdown AST | `swiftlang/swift-markdown` 0.8.x (Apache-2.0) | cmark-gfm based; source ranges retained; **no incremental parse** — full re-parse is ms-cheap |
| cmark HTML (export) | `swiftlang/swift-cmark` 0.8.x | Maintained SwiftPM packaging of cmark-gfm |
| MD preview | `gonzalezreal/textual` 0.5.x (MIT) | Pre-1.0 — pin + wrap behind protocol. MarkdownUI is maintenance-mode: rejected |
| Editor highlighting | `ChimeHQ/SwiftTreeSitter` (MIT) + tree-sitter grammars | Incremental, O(edit) re-highlight |
| Attr-string highlighting (fallback) | HighlighterSwift (MIT) | Highlightr unmaintained: rejected |
| YAML front matter | `jpsim/Yams` | Replaces LibYAML + vendored YAML-framework |
| CLI | `apple/swift-argument-parser` | Replaces GBCli |
| Updates | Sparkle **2.x** (EdDSA) | New keys + new appcast (new product) |
| Localization | String Catalogs (`.xcstrings`) + Transifex | Migrate 25 locales |
| CI | GitHub Actions, `macos-26` runner | Travis config is Xcode 10.1-era: retired |

**Dependency policy:** SPM only. Pin exact versions. Wrap every third-party UI
dependency behind an internal protocol so churn (Textual pre-1.0 especially)
never leaks into app code. No CocoaPods, no submodules.

## 6. Epic Roadmap

### Milestones

| Milestone | Goal | Epics |
|---|---|---|
| **M1 — Skeleton** | App launches, opens/saves files in tabs | E00, E01, E02, E03 |
| **M2 — Editor** | World-class text editing + highlighting | E04, E05, E10 |
| **M3 — Markdown core** | Live native preview + content browser | E06, E07, E08 |
| **M4 — Workspace & formats** | Folder browser, JSON/HTML, export, settings | E09, E11, E12, E13 |
| **M5 — Polish & ship** | Extensions seam, glass, l10n, distribution | E14, E15, E16, E17 |

### Dependency graph (critical path in **bold**)

```
E00 ─▶ E01 ─▶ E02 ─▶ E03 ─▶ E09 ─┐
  │      │      │                │
  │      ├─▶ E04 ─▶ E05 ─▶ E10   │
  │      │      │                │
  │      └─▶ E06 ─▶ E07 ─▶ E08   │
  │             │      │         │
  │             │      ├─▶ E14   │
  │             │      │         ▼
  │             │      └──────── E15 ─▶ E17
  │             │                ▲      ▲
  │             └─▶ E11 ─▶ E12 ──┘      │
  │                    (E11 needs E05)  │
  └──────────────── E13 (anytime)    E16 (late, needs stable strings)
```

Critical path: **E00 → E01 → E04 → E05 → E06 → E07 → E15 → E17**.
E06 depends only on E01 and can run parallel to E04/E05 if desired.

## 7. Repository & Branch Strategy

- Work happens in this fork on branch **`rewrite/main`**. `master` (ObjC) stays
  untouched and buildable for reference until 1.0 ships.
- One branch per epic: `epic/NN-short-name` → PR into `rewrite/main`.
  PR requires: CI green, tests added/updated, epic issue referenced.
- Because this is a new product (D5), expect to eventually rename the repo or
  move `rewrite/main` to a fresh repo. Planning docs live in `planning/` and
  ride along.
- Planning files are currently **untracked**; commit them to `rewrite/main`
  when the branch is created (part of E00).

## 8. Performance Budgets (acceptance thresholds)

| Metric | Budget | Verified in |
|---|---|---|
| Cold launch → interactive | < 1 s (M-series) | E00, re-checked E15 |
| Open 1 MB .md → text visible | < 300 ms | E04 perf test |
| Open 1 MB .md → fully highlighted | < 500 ms | E05 perf test |
| Keystroke → highlight update | < 50 ms | E05 perf test |
| Keystroke → preview refresh (debounced) | < 150 ms | E07 perf test |
| Folder with 10k entries → expand | < 200 ms | E09 perf test |
| Memory, 20 typical tabs | < 300 MB | E15 audit |

## 9. Testing Strategy

- **Framework:** Swift Testing for new code; port the 6 ObjC XCTest suites
  (string lookup, color, preferences, assets→export, JS bridge→drop,
  tabularize→JSON outline) during the epics that own each area.
- **Coverage per epic:** every epic lists its test deliverables; CI runs
  `swift test` + app target tests + perf tests on each PR.
- **UI tests (XCUITest):** tab lifecycle, dirty-close prompts, folder CRUD,
  outline jumping — the current app has zero UI tests; the hand-rolled document
  lifecycle makes them mandatory (E01/E03).
- **Fidelity corpus:** a set of real-world .md files rendered by old MacDown vs
  new export, diffed (E12).
- **Environment note:** planning/scaffolding was done on Linux; all builds and
  test runs require a Mac with Xcode 26.

## 10. Risk Register (top items)

| Risk | Mitigation |
|---|---|
| Hand-rolled document lifecycle → data-loss bugs | Autosave-on-edit + state machine + XCUITests (E01/E03); crash-recovery buffer |
| Textual pre-1.0 API churn | Pin version; `MarkdownPreviewing` protocol seam; WKWebView fallback kept for HTML format |
| SwiftTreeSitter grammar packaging friction | Grammar registry isolates build; start with markdown+json+html, grow |
| No incremental parse in swift-markdown | Parse actor + 150 ms cancel-debounce; perf tests on 1 MB/10 MB docs |
| Tab session restore edge cases | Restore is best-effort; never blocks launch; tested with corrupted state |
| New-product zero-day basics (signing, notarize, appcast) | E17 starts early in M5; Sparkle 2 EdDSA keys generated before first beta |
| Scope creep (18 epics) | Strict epic slicing; "out of scope" sections enforced in PR review |

## 11. Release Strategy

- New product name, icon (Icon Composer, Liquid Glass), bundle ID, website.
- Private alpha after M3 (usable Markdown editor), public beta after M4,
  1.0 after M5. Sparkle 2 appcast from first public build.
- MacDown (ObjC) remains available; no forced migration. Optional nicety
  (E13): one-time import of MacDown preferences/themes if detected.

## 12. Open Decisions (must resolve to unblock)

| # | Question | Blocks |
|---|---|---|
| O1 | Product name + bundle ID → **RESOLVED: MacDown 2 / `com.joncallim.macdown2`** (2026-07-19) | E00 (project creation) |
| O2 | Where does the app live long-term: rename this fork, or fresh repo? | E17 (can defer) |
| O3 | Import old MacDown prefs/themes on first run? (nice-to-have) | E13 |
| O4 | Which legacy themes ship in v1? (Resources has ~15 CSS/themes) | E05/E07 |

## 13. Appendix — D6: Extension Design

**Old system (retired):** `MPPlugIn` loads NSBundle code **in-process** with a
`run:` selector, plus JS injected into the preview WebView (MathJax, Mermaid…).
In-process code loading is a stability/security dead end and is not carried over.

**New model, layered:**

1. **v1 — Built-in contributions.** Internal `PreviewContribution` protocol;
   math, diagrams (Mermaid), TOC ship as first-party contributions. Covers ~95%
   of what people used preview plugins for.
2. **v1 — Text-filter commands.** Executable scripts (any language) in
   `~/Library/Application Support/<App>/Commands/`; selected text → stdin,
   replacement ← stdout. Surfaced in menu + palette. Zero API surface,
   BBEdit-style. Cheap to build, huge power-to-weight.
3. **v1.x — JavaScriptCore extensions.** Sandboxed JS hooks:
   `onDidParse(ast)`, custom fenced-block renderers (` ```mermaid ` → SVG),
   commands. Memory-safe, no dylibs, works with native preview.
4. **v2+ (evaluate later):** ExtensionKit out-of-process app extensions —
   Apple's modern framework, heavy; only if the community demands real plugins.

Deliverable in E14: items 1–2 + a written design for item 3.
