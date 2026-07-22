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
        .library(name: "ExportService", targets: ["ExportService"]),
    ],
    dependencies: [
        .package(url: "https://github.com/ChimeHQ/SwiftTreeSitter", branch: "main"),
        .package(url: "https://github.com/ChimeHQ/Neon", revision: "484d6fb9e0c4fb679a1d5f5ddaf2cac2ecf21165"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-json", from: "0.24.8"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-html", from: "0.23.2"),
        .package(path: "../TreeSitterMarkdown"),
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
            ]
        ),
        .target(name: "MarkdownEngine", dependencies: ["FileCore"]),
        .target(name: "Preview", dependencies: ["MarkdownEngine", "Themes"]),
        .target(name: "OutlineUI", dependencies: ["MarkdownEngine"]),
        .target(name: "ExportService", dependencies: ["MarkdownEngine", "Themes"]),

        .testTarget(name: "FileCoreTests", dependencies: ["FileCore"]),
        .testTarget(name: "AppSettingsTests", dependencies: ["AppSettings"]),
        .testTarget(name: "ThemesTests", dependencies: ["Themes"]),
        .testTarget(name: "WorkspaceTests", dependencies: ["Workspace"]),
        .testTarget(name: "FileTreeTests", dependencies: ["FileTree"]),
        .testTarget(name: "EditorCoreTests", dependencies: ["EditorCore"]),
        .testTarget(name: "HighlightingTests", dependencies: ["Highlighting"]),
        .testTarget(name: "MarkdownEngineTests", dependencies: ["MarkdownEngine"]),
        .testTarget(name: "PreviewTests", dependencies: ["Preview"]),
        .testTarget(name: "OutlineUITests", dependencies: ["OutlineUI"]),
        .testTarget(name: "ExportServiceTests", dependencies: ["ExportService"]),
    ]
)
