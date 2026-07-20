@testable import FileCore
import Foundation
import Testing
@testable import Workspace

// MARK: - Fakes

@MainActor
final class FakeStateStore: WorkspaceStateStoring {
    var sidebarVisible: Bool = true
    var sidebarSectionExpanded: [String: Bool] = [:]
}

// MARK: - Test suite

@MainActor
@Suite("WorkspaceModel")
struct WorkspaceModelTests {
    // MARK: - Command enablement

    @Test func newDocumentCreatesUntitledDocument() {
        let model = WorkspaceModel(stateStore: FakeStateStore())
        model.newDocument()

        #expect(model.hasActiveDocument)
        #expect(model.canClose)
        #expect(model.canSave == false)
        #expect(model.activeDocument?.fileURL == nil)
    }

    @Test func editingUntitledEnablesSave() {
        let model = WorkspaceModel(stateStore: FakeStateStore())
        model.newDocument()
        model.activeDocument = model.activeDocument?.updatingText("hello")

        #expect(model.canSave == true)
    }

    @Test func cleanSavedDocumentCannotSave() {
        let model = WorkspaceModel(stateStore: FakeStateStore())
        model.newDocument()
        #expect(model.canSave == false)
    }

    @Test func noDocumentDisablesSaveAndClose() {
        let model = WorkspaceModel(stateStore: FakeStateStore())
        #expect(model.hasActiveDocument == false)
        #expect(model.canSave == false)
        #expect(model.canClose == false)
    }

    // MARK: - Open file

    @Test func openFileLoadsDocument() async {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let url = directory.appendingPathComponent("doc.md")
        try? FileStore().write("# Hello", to: url)

        let panel = FakeFilePanelProvider()
        panel.nextFileURL = url

        let model = WorkspaceModel(stateStore: FakeStateStore(), panel: panel)
        await model.openFile()

        #expect(model.activeDocument?.text == "# Hello")
        #expect(model.activeDocument?.format.id == "markdown")
        #expect(model.activeDocument?.state == .clean)
    }

    @Test func openFileCancelledLeavesWorkspaceEmpty() async {
        let panel = FakeFilePanelProvider()
        let model = WorkspaceModel(stateStore: FakeStateStore(), panel: panel)
        await model.openFile()
        #expect(model.activeDocument == nil)
    }

    @Test func openFileWhileDirtyPromptsClose() async {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let firstURL = directory.appendingPathComponent("first.md")
        let secondURL = directory.appendingPathComponent("second.md")
        try? FileStore().write("first", to: firstURL)
        try? FileStore().write("second", to: secondURL)

        let panel = FakeFilePanelProvider()
        panel.nextFileURL = firstURL

        let model = WorkspaceModel(stateStore: FakeStateStore(), panel: panel)
        await model.openFile()
        model.activeDocument = model.activeDocument?.updatingText("edited")

        panel.nextFileURL = secondURL
        await model.openFile()

        #expect(model.pendingClose == true)
        #expect(model.activeDocument?.text == "edited")
    }

    // MARK: - Save / Save As

    @Test func saveExistingFileWritesToDisk() async throws {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let url = directory.appendingPathComponent("doc.md")
        try? FileStore().write("old", to: url)

        let panel = FakeFilePanelProvider()
        panel.nextFileURL = url

        let model = WorkspaceModel(stateStore: FakeStateStore(), panel: panel)
        await model.openFile()
        model.activeDocument = model.activeDocument?.updatingText("new")

        await model.save()

        #expect(model.activeDocument?.state == .clean)
        let (text, _) = try FileStore().read(from: url)
        #expect(text == "new")
    }

    @Test func saveUntitledUsesSavePanel() async throws {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let url = directory.appendingPathComponent("saved.md")

        let panel = FakeFilePanelProvider()
        panel.nextSaveURL = url

        let model = WorkspaceModel(stateStore: FakeStateStore(), panel: panel)
        model.newDocument()
        model.activeDocument = model.activeDocument?.updatingText("content")

        await model.save()

        #expect(model.activeDocument?.fileURL == url)
        #expect(model.activeDocument?.state == .clean)
        let (text, _) = try FileStore().read(from: url)
        #expect(text == "content")
    }

    @Test func saveCancelledKeepsDocumentOpenAndDirty() async {
        let panel = FakeFilePanelProvider()
        let model = WorkspaceModel(stateStore: FakeStateStore(), panel: panel)
        model.newDocument()
        model.activeDocument = model.activeDocument?.updatingText("content")

        await model.save()

        #expect(model.activeDocument?.fileURL == nil)
        #expect(model.activeDocument?.state == .dirty)
    }

    @Test func saveWithoutDocumentSetsError() async {
        let model = WorkspaceModel(stateStore: FakeStateStore())
        await model.save()

        if case .noActiveDocument = model.lastError {
            // pass
        } else {
            Issue.record("Expected .noActiveDocument, got \(String(describing: model.lastError))")
        }
    }

    // MARK: - Close document

    @Test func closeCleanDocumentRemovesIt() {
        let model = WorkspaceModel(stateStore: FakeStateStore())
        model.newDocument()
        model.requestCloseDocument()

        #expect(model.activeDocument == nil)
        #expect(model.pendingClose == false)
    }

    @Test func closeDirtyDocumentPrompts() {
        let model = WorkspaceModel(stateStore: FakeStateStore())
        model.newDocument()
        model.activeDocument = model.activeDocument?.updatingText("dirty")
        model.requestCloseDocument()

        #expect(model.pendingClose == true)
        #expect(model.activeDocument != nil)
    }

    @Test func closePromptCancelKeepsDocumentDirty() async {
        let model = WorkspaceModel(stateStore: FakeStateStore())
        model.newDocument()
        model.activeDocument = model.activeDocument?.updatingText("dirty")
        model.requestCloseDocument()

        await model.resolveClose(.cancel)

        #expect(model.pendingClose == false)
        #expect(model.activeDocument?.state == .dirty)
    }

    @Test func closePromptDiscardRemovesDocument() async {
        let model = WorkspaceModel(stateStore: FakeStateStore())
        model.newDocument()
        model.activeDocument = model.activeDocument?.updatingText("dirty")
        model.requestCloseDocument()

        await model.resolveClose(.discard)

        #expect(model.activeDocument == nil)
        #expect(model.pendingClose == false)
    }

    @Test func closePromptSaveWritesAndCloses() async throws {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let url = directory.appendingPathComponent("doc.md")

        let panel = FakeFilePanelProvider()
        panel.nextSaveURL = url

        let model = WorkspaceModel(stateStore: FakeStateStore(), panel: panel)
        model.newDocument()
        model.activeDocument = model.activeDocument?.updatingText("dirty")
        model.requestCloseDocument()

        await model.resolveClose(.save)

        #expect(model.activeDocument == nil)
        #expect(model.pendingClose == false)
        let (text, _) = try FileStore().read(from: url)
        #expect(text == "dirty")
    }

    @Test func closePromptSaveCancelledKeepsDocument() async {
        let panel = FakeFilePanelProvider()
        let model = WorkspaceModel(stateStore: FakeStateStore(), panel: panel)
        model.newDocument()
        model.activeDocument = model.activeDocument?.updatingText("dirty")
        model.requestCloseDocument()

        await model.resolveClose(.save)

        #expect(model.activeDocument != nil)
        #expect(model.activeDocument?.state == .dirty)
        #expect(model.pendingClose == false)
    }

    // MARK: - Open folder

    @Test func openFolderRecordsURL() async {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }

        let panel = FakeFilePanelProvider()
        panel.nextFolderURL = directory

        let model = WorkspaceModel(stateStore: FakeStateStore(), panel: panel)
        await model.openFolder()

        #expect(model.folderURL == directory)
        #expect(model.activeDocument == nil)
    }

    // MARK: - State store

    @Test func modelReadsSidebarVisibilityFromStore() {
        let store = FakeStateStore()
        store.sidebarVisible = false
        let model = WorkspaceModel(stateStore: store)
        #expect(model.sidebarVisible == false)
    }

    @Test func modelWritesSidebarVisibilityToStore() {
        let store = FakeStateStore()
        let model = WorkspaceModel(stateStore: store)
        model.sidebarVisible = false
        #expect(store.sidebarVisible == false)
    }

    @Test func modelReadsSectionExpansionFromStore() {
        let store = FakeStateStore()
        store.sidebarSectionExpanded = ["folder": false, "outline": true]
        let model = WorkspaceModel(stateStore: store)
        #expect(model.isSectionExpanded(.folder) == false)
        #expect(model.isSectionExpanded(.outline) == true)
    }

    @Test func modelWritesSectionExpansionToStore() {
        let store = FakeStateStore()
        let model = WorkspaceModel(stateStore: store)
        model.setSectionExpanded(.folder, false)
        #expect(store.sidebarSectionExpanded["folder"] == false)
    }

    // MARK: - Helpers

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
