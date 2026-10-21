import EditorCore
import FileCore
import Foundation
@testable import MacDown2
import Testing
import Workspace

@MainActor
struct ExternalFileControllerSaveAsNoticeTests {
    @Test func saveAsClearsTheUnavailableNoticeOnlyAfterTheNewBackingIsPublished() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let sourceURL = directory.appendingPathComponent("source.md")
        let destinationURL = directory.appendingPathComponent("saved-copy.md")
        try "original".write(to: sourceURL, atomically: true, encoding: .utf8)
        let recovery = RecoveryBuffer(recoveryDirectory: directory.appendingPathComponent("Recovery"))
        let source = try FileDocument(fileURL: sourceURL, recoveryBuffer: recovery).load()
            .updatingText("local edit")
        let store = TabStore(
            sessionStore: WorkspaceSessionStore(fileURL: directory.appendingPathComponent("session.json")),
            recoveryBuffer: recovery
        )
        store.newTab(document: source)
        let model = WorkspaceModel(tabStore: store)
        let controller = ExternalFileController(
            model: model, editorStore: EditorTextSystemStore(), identity: "save-as-notice-test"
        )
        controller.boundURL = sourceURL.standardizedFileURL

        try FileManager.default.removeItem(at: sourceURL)
        controller.applyUnavailable(.missingOrMoved, to: source, model: model)
        #expect(controller.notice == .unavailable(.missingOrMoved))

        // A cancelled picker or a failed Save As leaves the original warning in place.
        controller.synchronize(with: model.activeDocument)
        #expect(controller.notice == .unavailable(.missingOrMoved))

        let unavailable = try #require(model.activeDocument)
        await model.saveAs(
            to: directory.appendingPathComponent("missing-parent/failed-copy.md"), expecting: unavailable
        )
        controller.synchronize(with: model.activeDocument)
        #expect(controller.notice == .unavailable(.missingOrMoved))
        #expect(model.activeDocument?.id == unavailable.id)

        await model.saveAs(to: destinationURL, expecting: unavailable)
        let saved = try #require(model.activeDocument)
        #expect(saved.fileURL == destinationURL.standardizedFileURL)
        #expect(saved.backingState == .available)
        #expect(try String(contentsOf: destinationURL, encoding: .utf8) == "local edit")

        controller.synchronize(with: saved)
        #expect(controller.notice == .none)
    }
}
