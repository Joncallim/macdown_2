// swift-tools-version: 6.0
import PackageDescription

let retained = "/tmp/mt-preview-fix-bft-derived-2026-10-26/SourcePackages/checkouts/"
let package = Package(
    name: "NeonOrderingDiagnosticValidation",
    platforms: [.macOS(.v10_15)],
    products: [.library(name: "Neon", targets: ["Neon"])],
    dependencies: [
        .package(path: retained + "Rearrange"),
        .package(path: retained + "SwiftTreeSitter"),
        .package(path: retained + "tree-sitter")
    ],
    targets: [
        .target(name: "RangeState", dependencies: [.product(name: "Rearrange", package: "Rearrange")]),
        .target(name: "TreeSitterClient", dependencies: ["RangeState",
            .product(name: "Rearrange", package: "Rearrange"),
            .product(name: "SwiftTreeSitter", package: "SwiftTreeSitter"),
            .product(name: "SwiftTreeSitterLayer", package: "SwiftTreeSitter")]),
        .target(name: "Neon", dependencies: ["RangeState", "TreeSitterClient",
            .product(name: "Rearrange", package: "Rearrange"),
            .product(name: "SwiftTreeSitterLayer", package: "SwiftTreeSitter")]),
        .target(name: "NeonTestsTreeSitterSwift", path: "grammar",
            sources: ["src/parser.c", "src/scanner.c"], publicHeadersPath: "bindings/swift",
            cSettings: [.headerSearchPath("src")]),
        .testTarget(name: "TreeSitterClientTests", dependencies: ["TreeSitterClient", "RangeState", "NeonTestsTreeSitterSwift"])
    ])
