// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MacDownKit",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "FileCore", targets: ["FileCore"]),
        .library(name: "AppSettings", targets: ["AppSettings"]),
        .library(name: "Themes", targets: ["Themes"]),
        .library(name: "Workspace", targets: ["Workspace"]),
        .library(name: "FileTree", targets: ["FileTree"]),
        .library(name: "EditorCore", targets: ["EditorCore"]),
        .library(name: "Highlighting", targets: ["Highlighting"]),
        .library(name: "MarkdownEngine", targets: ["MarkdownEngine"]),
        .library(name: "Preview", targets: ["Preview"]),
        .library(name: "OutlineUI", targets: ["OutlineUI"]),
        .library(name: "JSONSupport", targets: ["JSONSupport"]),
        .library(name: "ExportService", targets: ["ExportService"]),
        .library(name: "Contributions", targets: ["Contributions"]),
        .library(name: "TextFilters", targets: ["TextFilters"]),
    ],
    dependencies: [
        .package(url: "https://github.com/ChimeHQ/SwiftTreeSitter", branch: "main"),
        .package(url: "https://github.com/ChimeHQ/Neon", revision: "484d6fb9e0c4fb679a1d5f5ddaf2cac2ecf21165"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-json", from: "0.24.8"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-html", from: "0.23.2"),
        // EPIC-11 Gate 5 grammars. Every grammar is pinned exactly; see
        // planning/epic-11-implementation.md §7 for the per-grammar evidence.
        //
        // Versions chosen deliberately: the tree-sitter CLI's newer manifest
        // template conditionally includes src/scanner.c via
        // `FileManager.fileExists`, which SwiftPM 6.x evaluates against the
        // bare repository cache (no working files), silently dropping the
        // scanner and breaking the link. The newest tags with fixed-sources
        // manifests are pinned instead; tree-sitter-javascript has no
        // fixed-sources manifest in any tag, so it is vendored locally
        // (Packages/TreeSitterJavaScript).
        .package(url: "https://github.com/tree-sitter-grammars/tree-sitter-yaml", exact: "0.7.0"),
        .package(url: "https://github.com/tree-sitter-grammars/tree-sitter-toml", exact: "0.7.0"),
        .package(path: "../TreeSitterJavaScript"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-typescript", exact: "0.23.2"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-python", exact: "0.23.6"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-ruby", exact: "0.23.1"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-css", exact: "0.23.2"),
        // tree-sitter-swift does not check its generated parser.c into normal
        // tags; the maintainers ship `-with-generated-files` tags for source
        // distribution, which is what the SPM package needs.
        .package(url: "https://github.com/alex-pinkus/tree-sitter-swift", exact: "0.7.3-with-generated-files"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-cpp", exact: "0.23.4"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-bash", exact: "0.25.1"),
        // tree-sitter-sql is vendored locally: DerekStride/tree-sitter-sql
        // never checks in its generated parser.c, so no release builds from
        // source. See Packages/TreeSitterSQL/README.md.
        .package(path: "../TreeSitterSQL"),
        .package(url: "https://github.com/tree-sitter-grammars/tree-sitter-xml", exact: "0.7.0"),
        .package(path: "../TreeSitterMarkdown"),
        .package(url: "https://github.com/swiftlang/swift-markdown", exact: "0.8.0"),
        .package(url: "https://github.com/swiftlang/swift-cmark", exact: "0.8.0"),
        .package(url: "https://github.com/jpsim/Yams", exact: "6.2.2"),
        .package(url: "https://github.com/gonzalezreal/textual", exact: "0.5.0"),
    ],
    targets: [
        .target(name: "FileCore"),
        .target(name: "AppSettings"),
        .target(name: "Themes", resources: [.process("Themes")]),
        .target(name: "Workspace", dependencies: ["FileCore"]),
        .target(name: "FileTree", dependencies: ["FileCore"]),
        .target(name: "EditorCore", dependencies: ["FileCore"]),
        .target(
            name: "Highlighting",
            dependencies: [
                "EditorCore",
                "Themes",
                .product(name: "SwiftTreeSitter", package: "SwiftTreeSitter"),
                .product(name: "SwiftTreeSitterLayer", package: "SwiftTreeSitter"),
                .product(name: "Neon", package: "Neon"),
                .product(name: "TreeSitterMarkdown", package: "TreeSitterMarkdown"),
                .product(name: "TreeSitterJSON", package: "tree-sitter-json"),
                .product(name: "TreeSitterHTML", package: "tree-sitter-html"),
                .product(name: "TreeSitterYAML", package: "tree-sitter-yaml"),
                .product(name: "TreeSitterTOML", package: "tree-sitter-toml"),
                .product(name: "TreeSitterJavaScript", package: "TreeSitterJavaScript"),
                .product(name: "TreeSitterTypeScript", package: "tree-sitter-typescript"),
                .product(name: "TreeSitterPython", package: "tree-sitter-python"),
                .product(name: "TreeSitterRuby", package: "tree-sitter-ruby"),
                .product(name: "TreeSitterCSS", package: "tree-sitter-css"),
                .product(name: "TreeSitterSwift", package: "tree-sitter-swift"),
                .product(name: "TreeSitterCPP", package: "tree-sitter-cpp"),
                .product(name: "TreeSitterBash", package: "tree-sitter-bash"),
                .product(name: "TreeSitterSQL", package: "TreeSitterSQL"),
                .product(name: "TreeSitterXML", package: "tree-sitter-xml"),
            ]
        ),
        .target(
            name: "MarkdownEngine",
            dependencies: [
                .product(name: "Markdown", package: "swift-markdown"),
                .product(name: "Yams", package: "Yams"),
            ]
        ),
        .target(
            name: "Preview",
            dependencies: [
                "MarkdownEngine",
                "Themes",
                "FileCore",
                .product(name: "Textual", package: "textual"),
            ]
        ),
        .target(name: "OutlineUI", dependencies: ["MarkdownEngine", "JSONSupport"]),
        .target(name: "JSONSupport", dependencies: []),
        .target(
            name: "ExportService",
            dependencies: [
                "MarkdownEngine",
                "Themes",
                .product(name: "cmark-gfm", package: "swift-cmark"),
                .product(name: "cmark-gfm-extensions", package: "swift-cmark"),
            ],
            resources: [.process("Resources")]
        ),
        .target(name: "Contributions", dependencies: ["MarkdownEngine"]),
        .target(name: "TextFilters"),

        .testTarget(name: "FileCoreTests", dependencies: ["FileCore"]),
        .testTarget(name: "AppSettingsTests", dependencies: ["AppSettings"]),
        .testTarget(name: "ThemesTests", dependencies: ["Themes"]),
        .testTarget(name: "WorkspaceTests", dependencies: ["Workspace"]),
        .testTarget(name: "FileTreeTests", dependencies: ["FileTree"]),
        .testTarget(name: "EditorCoreTests", dependencies: ["EditorCore", "JSONSupport"]),
        .testTarget(name: "HighlightingTests", dependencies: ["Highlighting"]),
        .testTarget(name: "MarkdownEngineTests", dependencies: ["MarkdownEngine"]),
        .testTarget(name: "PreviewTests", dependencies: ["Preview"]),
        .testTarget(name: "OutlineUITests", dependencies: ["OutlineUI", "JSONSupport"]),
        .testTarget(name: "JSONSupportTests", dependencies: ["JSONSupport"]),
        .testTarget(name: "ExportServiceTests", dependencies: ["ExportService"]),
        .testTarget(name: "ContributionsTests", dependencies: ["Contributions", "MarkdownEngine"]),
        .testTarget(name: "TextFiltersTests", dependencies: ["TextFilters"]),
    ]
)
