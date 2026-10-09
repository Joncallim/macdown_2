@testable import FileTree
import Foundation
import Testing

/// Review pass 1: expanding a folder the user cannot read must not raise a
/// modal operation error carrying the watcher's misleading "doesn't exist".
@MainActor
struct FileTreeUnreadableFolderTests {
    @Test func expandingAnUnreadableFolderDoesNotRaiseAnOperationError() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let locked = root.appendingPathComponent("locked", isDirectory: true)
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path)
            try? FileManager.default.removeItem(at: root)
        }
        let model = FileTreeModel(
            preferences: FileTreePreferences(store: MemoryPreferenceStore()),
            supportedExtensions: ["md"]
        )
        await model.setRoot(root)

        await model.expand(locked)

        #expect(model.lastOperationError == nil)
    }
}
