# MacDown 2

A native macOS Markdown editor — a ground-up Swift / SwiftUI rewrite built on
TextKit 2, a modular Swift package core, and a modern SwiftUI shell.

> **Status:** early development. Foundations, file/format core, workspace shell,
> native window tabs, the TextKit 2 editor, and tree-sitter highlighting with a
> theme system (EPIC-00 → EPIC-05) are in place. The markdown engine (E06),
> native preview (E07), and live external-file changes (E18) are next.
> The current Markdown preview is a temporary placeholder renderer, and
> performance numbers are package-level, not yet full-app-path measurements.

## Requirements

- macOS 26.0 or later
- Xcode 26 (Swift 6.2 toolchain, strict concurrency)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) — the `.xcodeproj` is generated, not committed

## Repository layout

```
MacDown2/
├── MacDown2/                 # App target (SwiftUI shell)
├── MacDown2CLI/              # `macdown2` command-line tool
├── MacDown2UITests/          # XCUITest target
├── Packages/MacDownKit/      # Swift package — all logic lives here
│   └── Sources/
│       ├── FileCore          # FileStore, FileFormat registry, document lifecycle
│       ├── Workspace         # Per-window model + session restore (native NSWindow tabs)
│       ├── EditorCore        # NSTextView + TextKit 2 editor
│       ├── Highlighting      # Tree-sitter engine (markdown/json/html), Neon-backed
│       ├── Themes            # Theme model + Tomorrow Light/Dark, live switching
│       ├── MarkdownEngine    # PLACEHOLDER — swift-markdown parse actor arrives in E06
│       ├── Preview           # PLACEHOLDER — native Textual preview arrives in E07
│       ├── OutlineUI / FileTree / AppSettings / ExportService   # stubs for E08/E09/E13/E12
│       └── …
├── Packages/TreeSitterMarkdown  # Vendored markdown + markdown-inline grammars
└── project.yml               # XcodeGen project definition
planning/                     # Epic specs and implementation plans
legacy-reference/             # Legacy ObjC MacDown — read-only porting source
```

## Building

```bash
# 1. Logic package — build + test (all unit tests live here)
cd MacDown2/Packages/MacDownKit
swift build
swift test

# 2. Generate the Xcode project
cd ../..
xcodegen generate

# 3. Build the app and the CLI
xcodebuild -project MacDown2.xcodeproj -scheme MacDown2  -destination 'platform=macOS' build
xcodebuild -project MacDown2.xcodeproj -scheme macdown2  -destination 'platform=macOS' build
```

## Linting

```bash
swiftformat --lint MacDown2
swiftlint   lint --strict MacDown2
```

CI (`.github/workflows/ci.yml`) runs the lint, package tests, and app/CLI builds
on every push and PR to `master`.

## Roadmap

Development is organised into epics, each tracked as a GitHub issue with a spec in
[`planning/epics/`](planning/epics/) and a detailed implementation plan in
[`planning/`](planning/). See [`planning/MIGRATION_PLAN.md`](planning/MIGRATION_PLAN.md)
for the overall plan.

## License

MacDown 2 is free and open-source software, released under the [MIT License](LICENSE).

It is an open-source **fork and successor of [MacDown](https://github.com/MacDownApp/macdown)**,
the original macOS Markdown editor by Tzu-ping Chung and contributors (also MIT-licensed).
The original copyright notice is retained in [`LICENSE`](LICENSE).
