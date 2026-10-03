import Foundation
@testable import MacDown2
import Testing

/// Opens of one file are serialised by key; the key must name the file, not one spelling of its path.
@MainActor
struct OpenSerializationKeyTests {
    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    @Test func aSymlinkedParentDirectorySpellingGetsTheSameKey() throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let real = root.appendingPathComponent("real", isDirectory: true)
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        let file = real.appendingPathComponent("a.md")
        try "x".write(to: file, atomically: true, encoding: .utf8)
        let link = root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)

        #expect(
            WindowCoordinator.openSerializationKey(for: file)
                == WindowCoordinator.openSerializationKey(for: link.appendingPathComponent("a.md"))
        )
    }

    @Test func differentFilesGetDifferentKeys() throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = root.appendingPathComponent("a.md")
        let second = root.appendingPathComponent("b.md")
        try "x".write(to: first, atomically: true, encoding: .utf8)
        try "x".write(to: second, atomically: true, encoding: .utf8)

        #expect(WindowCoordinator.openSerializationKey(for: first) != WindowCoordinator
            .openSerializationKey(for: second))
    }

    @Test func aMissingFileFallsBackToItsPath() {
        let missing = URL(fileURLWithPath: "/tmp/\(UUID().uuidString)/nope.md")

        #expect(WindowCoordinator.openSerializationKey(for: missing) == "path:\(missing.path)")
    }
}
