import FileTree
import Foundation
@testable import MacDown2
import Testing
import UniformTypeIdentifiers

/// Review pass 6: the file-tree drag token expired after 30 s and was consumed by the first drop, so an internal move
/// started on a row that had been idle for half a minute — or after one failed drop — was refused as untrusted.
@MainActor
struct FileTreeInternalDragTests {
    private func model(in root: URL) async -> FileTreeModel {
        let defaults = UserDefaults(suiteName: "FileTreeInternalDragTests-\(UUID().uuidString)") ?? .standard
        let model = FileTreeModel(
            preferences: FileTreePreferences(store: UserDefaultsFileTreePreferenceStore(defaults: defaults)),
            supportedExtensions: ["md"]
        )
        await model.setRoot(root)
        return model
    }

    @Test func aTokenSurvivesAFailedDropAndCanBeUsedAgain() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("a.md")
        try "x".write(to: file, atomically: true, encoding: .utf8)
        let model = await model(in: root)
        let payload = FileTreeInternalDrag.issue(url: file, from: model)

        let first = FileTreeInternalDrag.trustedURL(from: payload, for: model)
        let second = FileTreeInternalDrag.trustedURL(from: payload, for: model)

        #expect(first == file.standardizedFileURL)
        #expect(second == file.standardizedFileURL)
    }

    @Test func anUntrustedPayloadIsStillRefused() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("a.md")
        try "x".write(to: file, atomically: true, encoding: .utf8)
        let model = await model(in: root)

        let untrusted = FileTreeInternalDrag.untrustedPayload(for: file)

        #expect(FileTreeInternalDrag.trustedURL(from: untrusted, for: model) == nil)
    }

    @Test func theDragTypeIsDeclaredAsAnExportedTypeConformingToData() throws {
        let declared = try #require(Bundle(for: AppDelegate.self).object(
            forInfoDictionaryKey: "UTExportedTypeDeclarations"
        ) as? [[String: Any]])
        let identifiers = declared.compactMap { $0["UTTypeIdentifier"] as? String }

        #expect(identifiers.contains("com.joncallim.macdown2.file-tree-item"))
        #expect(UTType.macDownFileTreeItem.conforms(to: .data))
    }
}
