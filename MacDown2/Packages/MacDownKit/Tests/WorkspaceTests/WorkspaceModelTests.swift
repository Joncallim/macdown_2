@testable import FileCore
import Foundation
import Testing
@testable import Workspace

@Test func moduleLoads() {
    #expect(WorkspaceModule.moduleName == "Workspace")
}

// MARK: - Test suite

@MainActor
@Suite("WorkspaceModel")
struct WorkspaceModelTests {
    // MARK: - Command enablement

    @Test func newDocumentCreatesUntitledTab() {
        let model = WorkspaceModel(stateStore: FakeStateStore())
        model.newDocument()

        #expect(model.hasActiveDocument)
        #expect(model.canClose)
        #expect(model.canSave == false)
        #expect(model.activeDocument?.fileURL == nil)
        #expect(model.tabStore.tabs.count == 1)
    }

    @Test func editingUntitledEnablesSave() {
        let model = WorkspaceModel(stateStore: FakeStateStore())
        model.newDocument()
        model.tabStore.updateActiveDocument { $0.updatingText("hello") }

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

    // MARK: - New document

    @Test func newDocumentDoesNotPromptWhenDirty() {
        let model = WorkspaceModel(stateStore: FakeStateStore())
        model.newDocument()
        model.tabStore.updateActiveDocument { $0.updatingText("dirty") }

        model.newDocument()

        #expect(model.tabStore.pendingCloseTabID == nil)
        #expect(model.tabStore.tabs.count == 2)
    }

    // MARK: - Close document

    @Test func closeCleanTabRemovesIt() {
        let model = WorkspaceModel(stateStore: FakeStateStore())
        model.newDocument()
        model.requestCloseDocument()

        #expect(model.activeDocument == nil)
        #expect(model.tabStore.tabs.isEmpty)
    }

    @Test func closeDirtyTabPrompts() {
        let model = WorkspaceModel(stateStore: FakeStateStore())
        model.newDocument()
        model.tabStore.updateActiveDocument { $0.updatingText("dirty") }
        model.requestCloseDocument()

        #expect(model.tabStore.pendingCloseTabID != nil)
        #expect(model.activeDocument != nil)
    }

    @Test func closePromptCancelKeepsDocumentDirty() async {
        let model = WorkspaceModel(stateStore: FakeStateStore())
        model.newDocument()
        model.tabStore.updateActiveDocument { $0.updatingText("dirty") }
        model.requestCloseDocument()

        await model.resolveClose(.cancel)

        #expect(model.tabStore.pendingCloseTabID == nil)
        #expect(model.activeDocument?.state == .dirty)
    }

    @Test func closePromptDiscardRemovesDocument() async {
        let model = WorkspaceModel(stateStore: FakeStateStore())
        model.newDocument()
        model.tabStore.updateActiveDocument { $0.updatingText("dirty") }
        model.requestCloseDocument()

        await model.resolveClose(.discard)

        #expect(model.activeDocument == nil)
        #expect(model.tabStore.tabs.isEmpty)
    }

    @Test func closePromptSaveWritesAndCloses() async throws {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let url = directory.appendingPathComponent("doc.md")

        let panel = FakeFilePanelProvider()
        panel.nextSaveURL = url

        let model = WorkspaceModel(stateStore: FakeStateStore(), panel: panel)
        model.newDocument()
        model.tabStore.updateActiveDocument { $0.updatingText("dirty") }
        model.requestCloseDocument()

        await model.resolveClose(.save)

        #expect(model.activeDocument == nil)
        #expect(model.tabStore.tabs.isEmpty)
        let (text, _) = try FileStore().read(from: url)
        #expect(text == "dirty")
    }

    @Test func closePromptSaveCancelledKeepsDocument() async {
        let panel = FakeFilePanelProvider()
        let model = WorkspaceModel(stateStore: FakeStateStore(), panel: panel)
        model.newDocument()
        model.tabStore.updateActiveDocument { $0.updatingText("dirty") }
        model.requestCloseDocument()

        await model.resolveClose(.save)

        #expect(model.activeDocument != nil)
        #expect(model.activeDocument?.state == .dirty)
        #expect(model.tabStore.pendingCloseTabID == nil)
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

    @Test func modelHydratesSectionOrderFromStore() {
        let store = FakeStateStore()
        store.sidebarSectionOrder = ["outline", "folder"]
        let model = WorkspaceModel(stateStore: store)
        #expect(model.sectionOrder == [.outline, .folder])
    }

    @Test func modelDefaultsSectionOrderWhenStoreIsEmpty() {
        let store = FakeStateStore()
        store.sidebarSectionOrder = []
        let model = WorkspaceModel(stateStore: store)
        #expect(model.sectionOrder == SidebarSection.defaultOrder)
    }

    private struct MoveSectionsCase: Sendable {
        let name: String
        let initial: [String]
        let offsets: IndexSet
        let offset: Int
        let expected: [String]
    }

    @Test(arguments: [
        MoveSectionsCase(
            name: "single item to end",
            initial: ["folder", "outline"],
            offsets: IndexSet(integer: 0),
            offset: 2,
            expected: ["outline", "folder"]
        ),
        MoveSectionsCase(
            name: "single item to beginning",
            initial: ["folder", "outline"],
            offsets: IndexSet(integer: 1),
            offset: 0,
            expected: ["outline", "folder"]
        ),
        MoveSectionsCase(
            name: "single item to current position",
            initial: ["folder", "outline"],
            offsets: IndexSet(integer: 0),
            offset: 0,
            expected: ["folder", "outline"]
        ),
        MoveSectionsCase(
            name: "all items moved (empty remaining)",
            initial: ["folder", "outline"],
            offsets: IndexSet([0, 1]),
            offset: 2,
            expected: ["folder", "outline"]
        ),
        MoveSectionsCase(
            name: "out-of-bounds index",
            initial: ["folder", "outline"],
            offsets: IndexSet(integer: 999),
            offset: 0,
            expected: ["folder", "outline"]
        ),
        MoveSectionsCase(
            name: "negative offset clamped to zero",
            initial: ["folder", "outline"],
            offsets: IndexSet(integer: 1),
            offset: -1,
            expected: ["outline", "folder"]
        ),
    ])
    private func modelMoveSectionsUpdatesOrderAndStore(_ testCase: MoveSectionsCase) {
        let store = FakeStateStore()
        store.sidebarSectionOrder = testCase.initial
        let model = WorkspaceModel(stateStore: store)

        model.moveSections(fromOffsets: testCase.offsets, toOffset: testCase.offset)

        #expect(
            model.sectionOrder.map(\.rawValue) == testCase.expected,
            "Test case: \(testCase.name)"
        )
        #expect(
            store.sidebarSectionOrder == testCase.expected,
            "Test case: \(testCase.name)"
        )
    }

    @Test func modelCachesSectionExpansionIndependentlyOfStoreReads() {
        let store = FakeStateStore()
        store.sidebarSectionExpanded = ["folder": false, "outline": true]
        let model = WorkspaceModel(stateStore: store)

        store.sidebarSectionExpanded = [:]

        #expect(model.isSectionExpanded(.folder) == false)
        #expect(model.isSectionExpanded(.outline) == true)
    }
}
