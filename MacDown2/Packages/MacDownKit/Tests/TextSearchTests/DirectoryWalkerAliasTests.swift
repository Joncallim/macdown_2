import Foundation
import Testing
@testable import TextSearch

/// Review pass 1: a symlinked directory must not hide the real directory (or
/// vice versa) depending on enumeration order, and package directories are not
/// indexed as files.
struct DirectoryWalkerAliasTests {
    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    @Test func everyAliasOfADirectoryIsIndexedRegardlessOfEnumerationOrder() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let real = root.appendingPathComponent("v2", isDirectory: true)
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        try Data().write(to: real.appendingPathComponent("page.md"))
        // Names sorting before and after "v2" so both enumeration orders occur.
        for name in ["a", "alias", "latest", "z"] {
            try FileManager.default.createSymbolicLink(
                at: root.appendingPathComponent(name), withDestinationURL: real
            )
        }

        let paths = Set(DirectoryWalker().walk(root: root, excludedDirectoryNames: []).map(\.relativePath))

        #expect(paths.contains("v2/page.md"))
        for name in ["a", "alias", "latest", "z"] {
            #expect(paths.contains("\(name)/page.md"), "alias \(name) missing")
        }
    }

    @Test func aSymlinkLoopStillTerminates() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let sub = root.appendingPathComponent("sub", isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        try Data().write(to: sub.appendingPathComponent("f.md"))
        try FileManager.default.createSymbolicLink(
            at: sub.appendingPathComponent("loop"), withDestinationURL: root
        )

        let paths = DirectoryWalker().walk(root: root, excludedDirectoryNames: []).map(\.relativePath)

        #expect(paths.contains("sub/f.md"))
        #expect(paths.count < 50)
    }

    @Test func packageDirectoriesAreNotIndexedAsFiles() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let app = root.appendingPathComponent("Foo.app", isDirectory: true)
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        try Data().write(to: app.appendingPathComponent("inside.txt"))
        try Data().write(to: root.appendingPathComponent("note.md"))

        let paths = DirectoryWalker().walk(root: root, excludedDirectoryNames: []).map(\.relativePath)

        #expect(paths == ["note.md"])
    }
}
