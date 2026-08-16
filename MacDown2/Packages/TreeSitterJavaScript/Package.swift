// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "TreeSitterJavaScript",
    platforms: [.macOS(.v26)],
    products: [
        .library(
            name: "TreeSitterJavaScript",
            targets: [
                "TreeSitterJavaScript",
                "TreeSitterJavaScriptResources",
            ]
        ),
    ],
    targets: [
        .target(
            name: "TreeSitterJavaScript",
            dependencies: [],
            path: "Sources/TreeSitterJavaScript",
            sources: ["src/parser.c", "src/scanner.c"],
            publicHeadersPath: "bindings/swift",
            cSettings: [.headerSearchPath("src")]
        ),
        .target(
            name: "TreeSitterJavaScriptResources",
            dependencies: ["TreeSitterJavaScript"],
            path: "Sources/TreeSitterJavaScriptResources",
            resources: [.copy("queries")]
        ),
    ],
    cLanguageStandard: .c11
)
