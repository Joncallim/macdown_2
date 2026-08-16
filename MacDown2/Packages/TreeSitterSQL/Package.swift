// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "TreeSitterSQL",
    platforms: [.macOS(.v26)],
    products: [
        .library(
            name: "TreeSitterSQL",
            targets: [
                "TreeSitterSQL",
                "TreeSitterSQLResources",
            ]
        ),
    ],
    targets: [
        .target(
            name: "TreeSitterSQL",
            dependencies: [],
            path: "Sources/TreeSitterSQL",
            sources: ["src/parser.c", "src/scanner.c"],
            publicHeadersPath: "bindings/swift",
            cSettings: [.headerSearchPath("src")]
        ),
        .target(
            name: "TreeSitterSQLResources",
            dependencies: ["TreeSitterSQL"],
            path: "Sources/TreeSitterSQLResources",
            resources: [.copy("queries")]
        ),
    ],
    cLanguageStandard: .c11
)
