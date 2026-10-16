// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "ReproB",
    platforms: [.macOS(.v13)],
    dependencies: [.package(name: "SwiftTreeSitter", path: "../vendor/SwiftTreeSitter")],
    targets: [
        .target(name: "TSMarkdown", path: "Sources/TSMarkdown", sources: ["src/parser.c", "src/scanner.c"],
                publicHeadersPath: "include", cSettings: [.headerSearchPath("src")]),
        .target(name: "TSMarkdownInline", path: "Sources/TSMarkdownInline", sources: ["src/parser.c", "src/scanner.c"],
                publicHeadersPath: "include", cSettings: [.headerSearchPath("src")]),
        .executableTarget(name: "Repro",
            dependencies: ["TSMarkdown", "TSMarkdownInline",
                           .product(name: "SwiftTreeSitter", package: "SwiftTreeSitter"),
                           .product(name: "SwiftTreeSitterLayer", package: "SwiftTreeSitter")],
            exclude: ["queries"]),
    ]
)
