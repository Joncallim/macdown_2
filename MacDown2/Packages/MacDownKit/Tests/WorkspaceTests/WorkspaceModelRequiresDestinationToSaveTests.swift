@testable import FileCore
import Foundation
import Testing
@testable import Workspace

/// Fourth-pass coverage for destination routing. The advisory
/// `requiresDestinationToSave` snapshot remains useful for validation, but
/// the explicit-origin command path now uses `saveWithoutDestinationPrompt()`
/// so no race can fall through to the model's ambient panel provider.
@MainActor
@Suite("WorkspaceModel save destination routing")
struct RequiresDestinationToSaveTests {
    @Test func noActiveDocumentDoesNotRequireADestination() {
        let model = WorkspaceModel(stateStore: FakeStateStore())
        #expect(!model.requiresDestinationToSave)
    }

    @Test func anUntitledDocumentRequiresADestination() {
        let model = WorkspaceModel(stateStore: FakeStateStore())
        model.newDocument()
        model.tabStore.updateActiveDocument { $0.updatingText("hello") }

        #expect(model.requiresDestinationToSave)
    }

    @Test func aDocumentWithAnUnavailableBackingRequiresADestination() {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let url = directory.appendingPathComponent("missing.md")
        let document = FileDocument(fileURL: url, text: "keep")
            .updatingText("keep")
            .markingBackingUnavailable(.missingOrMoved)
        let tabStore = TabStore(sessionStore: FakeSessionStore())
        tabStore.newTab(document: document)
        let model = WorkspaceModel(tabStore: tabStore, stateStore: FakeStateStore())

        #expect(model.requiresDestinationToSave)
    }

    @Test func anOrdinaryBackedDocumentDoesNotRequireADestination() {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let url = directory.appendingPathComponent("normal.md")
        try? "keep".write(to: url, atomically: true, encoding: .utf8)
        let document = FileDocument(fileURL: url, text: "keep").updatingText("changed")
        let tabStore = TabStore(sessionStore: FakeSessionStore())
        tabStore.newTab(document: document)
        let model = WorkspaceModel(tabStore: tabStore, stateStore: FakeStateStore())

        #expect(!model.requiresDestinationToSave)
    }

    @Test func nonPromptingSaveReportsUntitledDestinationWithoutTouchingAmbientPanel() async {
        let panel = FakeFilePanelProvider()
        let sentinel = temporaryDirectory().appendingPathComponent("must-not-be-consumed.md")
        defer { cleanup(sentinel.deletingLastPathComponent()) }
        panel.nextSaveURL = sentinel
        let model = WorkspaceModel(stateStore: FakeStateStore(), panel: panel)
        model.newDocument()
        model.tabStore.updateActiveDocument { $0.updatingText("hello") }

        let result = await model.saveWithoutDestinationPrompt()

        #expect(result == .requiresDestination)
        #expect(panel.nextSaveURL == sentinel, "the ambient destination provider must not have been invoked")
    }

    @Test func nonPromptingSaveReportsUnavailableBackingWithoutTouchingAmbientPanel() async {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let missing = directory.appendingPathComponent("missing.md")
        let sentinel = directory.appendingPathComponent("must-not-be-consumed.md")
        let panel = FakeFilePanelProvider()
        panel.nextSaveURL = sentinel
        let document = FileDocument(fileURL: missing, text: "keep")
            .updatingText("changed")
            .markingBackingUnavailable(.missingOrMoved)
        let tabStore = TabStore(sessionStore: FakeSessionStore())
        tabStore.newTab(document: document)
        let model = WorkspaceModel(tabStore: tabStore, stateStore: FakeStateStore(), panel: panel)

        let result = await model.saveWithoutDestinationPrompt()

        #expect(result == .requiresDestination)
        #expect(panel.nextSaveURL == sentinel, "the ambient destination provider must not have been invoked")
    }

    @Test func nonPromptingSaveStillWritesAnOrdinaryBackedDocument() async throws {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let url = directory.appendingPathComponent("normal.md")
        try "before".write(to: url, atomically: true, encoding: .utf8)
        let sentinel = directory.appendingPathComponent("must-not-be-consumed.md")
        let panel = FakeFilePanelProvider()
        panel.nextSaveURL = sentinel
        let document = FileDocument(fileURL: url, text: "before").updatingText("after")
        let tabStore = TabStore(sessionStore: FakeSessionStore())
        tabStore.newTab(document: document)
        let model = WorkspaceModel(tabStore: tabStore, stateStore: FakeStateStore(), panel: panel)

        let result = await model.saveWithoutDestinationPrompt()

        #expect(result == .handled)
        #expect(try String(contentsOf: url, encoding: .utf8) == "after")
        #expect(panel.nextSaveURL == sentinel, "an ordinary Save must not consume an unrelated destination")
    }
}
