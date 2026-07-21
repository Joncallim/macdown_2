# MacDown 2

A native macOS Markdown editor — a ground-up Swift / SwiftUI rewrite built on
TextKit 2, a modular Swift package core, and a modern SwiftUI shell.

> **Status:** early development. Foundations, file/format core, workspace shell,
> and the tab system (EPIC-00 → EPIC-03) are in place. The editor, highlighting,
> markdown engine, and preview are next on the roadmap.

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
│       ├── Workspace         # TabStore, session model
│       ├── EditorCore        # NSTextView + TextKit 2 editor (in progress)
│       ├── MarkdownEngine    # swift-markdown parse actor
│       ├── Preview           # native Markdown preview
│       ├── Themes / Highlighting / OutlineUI / FileTree / AppSettings / ExportService
│       └── …
└── project.yml               # XcodeGen project definition
planning/                     # Epic specs, implementation plans, and hand-off docs
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
