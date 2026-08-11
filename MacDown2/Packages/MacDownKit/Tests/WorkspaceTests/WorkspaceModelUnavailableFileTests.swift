@testable import FileCore
import Foundation
import Testing
@testable import Workspace

@MainActor
@Suite("WorkspaceModel unavailable file save")
struct WorkspaceModelUnavailableFileTests {
    @Test func unavailableDocumentUsesSaveAsInsteadOfRecreatingTheOldPath() async throws {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let oldURL = directory.appendingPathComponent("missing.md")
        let newURL = directory.appendingPathComponent("recovered.md")
        let panel = FakeFilePanelProvider()
        panel.nextSaveURL = newURL
        let document = FileDocument(fileURL: oldURL, text: "keep")
            .updatingText("keep")
            .markingBackingUnavailable(.missingOrMoved)
        let tabStore = TabStore(sessionStore: FakeSessionStore())
        tabStore.newTab(document: document)
        let model = WorkspaceModel(tabStore: tabStore, stateStore: FakeStateStore(), panel: panel)

        await model.save()

        #expect(!FileManager.default.fileExists(atPath: oldURL.path))
        #expect(model.activeDocument?.fileURL == newURL)
        #expect(try FileStore().read(from: newURL).content == "keep")
    }
}
