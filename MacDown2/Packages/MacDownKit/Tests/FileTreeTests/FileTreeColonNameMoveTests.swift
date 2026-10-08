@testable import FileTree
import Foundation
import Testing

@MainActor
struct FileTreeColonNameMoveTests {
    @Test func aFileWithAColonInItsNameCanBeMovedIntoAFolder() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let folder = root.appendingPathComponent("sub", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("Meeting 10:30.md")
        try "x".write(to: file, atomically: true, encoding: .utf8)
        let model = FileTreeModel(
            preferences: FileTreePreferences(store: MemoryPreferenceStore()),
            supportedExtensions: ["md"]
        )
        await model.setRoot(root)

        let result = try await model.move(file, intoDirectory: folder)

        #expect(result.url.lastPathComponent == "Meeting 10:30.md")
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("Meeting 10:30.md").path))
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }
}
