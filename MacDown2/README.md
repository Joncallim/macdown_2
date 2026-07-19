# MacDown 2

A native Swift/SwiftUI Markdown and code editor for macOS 26+, built on the
MacDown legacy project.

## Requirements

- Xcode 26
- macOS 26.0 deployment target
- Homebrew (for XcodeGen, SwiftLint, SwiftFormat)

## Build

```bash
cd MacDown2 && xcodegen generate
xcodebuild -project MacDown2.xcodeproj -scheme MacDown2 -destination 'platform=macOS' build
```

See [`planning/MIGRATION_PLAN.md`](../planning/MIGRATION_PLAN.md) for the full
architecture and migration plan.
