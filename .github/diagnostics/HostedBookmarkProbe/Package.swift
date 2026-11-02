// swift-tools-version: 6.2
import PackageDescription
let package = Package(name: "HostedBookmarkProbe", platforms: [.macOS(.v26)], targets: [.testTarget(name: "ScopeTests")])
