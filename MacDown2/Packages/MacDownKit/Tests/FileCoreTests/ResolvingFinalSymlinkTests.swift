@testable import FileCore
import Foundation
import Testing

struct ResolvingFinalSymlinkTests {
    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    @Test func aLinkToAFileResolvesToTheFile() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = directory.appendingPathComponent("real.md")
        try "x".write(to: target, atomically: true, encoding: .utf8)
        let absolute = directory.appendingPathComponent("abs-link.md")
        let relative = directory.appendingPathComponent("rel-link.md")
        try FileManager.default.createSymbolicLink(at: absolute, withDestinationURL: target)
        try FileManager.default.createSymbolicLink(atPath: relative.path, withDestinationPath: "real.md")

        #expect(absolute.resolvingFinalSymlink().standardizedFileURL == target.standardizedFileURL)
        #expect(relative.resolvingFinalSymlink().standardizedFileURL == target.standardizedFileURL)
    }

    @Test func chainsResolveAndLoopsOrDanglingLinksAreLeftAlone() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = directory.appendingPathComponent("real.md")
        try "x".write(to: target, atomically: true, encoding: .utf8)
        let hop1 = directory.appendingPathComponent("hop1.md")
        let hop2 = directory.appendingPathComponent("hop2.md")
        try FileManager.default.createSymbolicLink(atPath: hop1.path, withDestinationPath: "real.md")
        try FileManager.default.createSymbolicLink(atPath: hop2.path, withDestinationPath: "hop1.md")
        let loopA = directory.appendingPathComponent("a.md")
        let loopB = directory.appendingPathComponent("b.md")
        try FileManager.default.createSymbolicLink(atPath: loopA.path, withDestinationPath: "b.md")
        try FileManager.default.createSymbolicLink(atPath: loopB.path, withDestinationPath: "a.md")
        let dangling = directory.appendingPathComponent("dangling.md")
        try FileManager.default.createSymbolicLink(atPath: dangling.path, withDestinationPath: "nowhere.md")

        #expect(hop2.resolvingFinalSymlink().standardizedFileURL == target.standardizedFileURL)
        #expect(loopA.resolvingFinalSymlink().lastPathComponent == "a.md")
        // A dangling link resolves to its (missing) target, which then fails to open as missing.
        #expect(dangling.resolvingFinalSymlink().lastPathComponent == "nowhere.md")
        #expect(target.resolvingFinalSymlink().standardizedFileURL == target.standardizedFileURL)
    }
}
