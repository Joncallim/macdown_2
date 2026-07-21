import FileCore
import Foundation
import Testing
@testable import Workspace

@MainActor
@Suite("TabStoreCore")
struct TabStoreCoreTests {
    // MARK: - New tab

    @Test func newTabCreatesUntitledActiveTab() {
        let store = TabStore(sessionStore: FakeSessionStore())
        store.newTab()

        #expect(store.tabs.count == 1)
        #expect(store.hasActiveDocument)
        #expect(store.activeDocument?.fileURL == nil)
        #expect(store.activeDocument?.format.id == "markdown")
    }

    @Test func newTabPreservesProvidedIDAndDocument() {
        let store = TabStore(sessionStore: FakeSessionStore())
        let id = UUID()
        let document = FileDocument(text: "restored")

        store.newTab(id: id, document: document)

        #expect(store.tabs.count == 1)
        #expect(store.activeTabID == id)
        #expect(store.activeDocument?.text == "restored")
        #expect(store.activeDocument?.id == document.id)
    }

    @Test func twoNewTabsAreDistinctAndLatestActive() {
        let store = TabStore(sessionStore: FakeSessionStore())
        store.newTab()
        let firstID = store.activeTabID
        store.newTab()
        let secondID = store.activeTabID

        #expect(store.tabs.count == 2)
        #expect(firstID != secondID)
        #expect(store.activeTabID == store.tabs[1].id)
    }

    // MARK: - Open file & dedupe

    @Test func openFileInTabLoadsAndActivates() async {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let url = directory.appendingPathComponent("doc.md")
        try? FileStore().write("# Hello", to: url)

        let store = TabStore(sessionStore: FakeSessionStore())
        let tab = await store.openFileInTab(url)

        #expect(tab != nil)
        #expect(store.tabs.count == 1)
        #expect(store.activeDocument?.text == "# Hello")
        #expect(store.activeDocument?.state == .clean)
    }

    @Test func openSameFileTwiceDoesNotCreateSecondTab() async {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let url = directory.appendingPathComponent("doc.md")
        try? FileStore().write("content", to: url)

        let store = TabStore(sessionStore: FakeSessionStore())
        let first = await store.openFileInTab(url)
        store.newTab()
        let second = await store.openFileInTab(url)

        #expect(store.tabs.count == 2)
        #expect(first?.id == second?.id)
        #expect(store.activeTabID == first?.id)
    }

    @Test func openFileWhileDirtyDoesNotPrompt() async {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let url = directory.appendingPathComponent("doc.md")
        try? FileStore().write("content", to: url)

        let store = TabStore(sessionStore: FakeSessionStore())
        store.newTab()
        store.updateActiveDocument { $0.updatingText("dirty") }

        await store.openFileInTab(url)

        #expect(store.pendingCloseTabID == nil)
        #expect(store.tabs.count == 2)
    }

    @Test func openMissingFileDoesNotCreateTab() async {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let url = directory.appendingPathComponent("missing.md")

        let store = TabStore(sessionStore: FakeSessionStore())
        let tab = await store.openFileInTab(url)

        #expect(tab == nil)
        #expect(store.tabs.isEmpty)
    }

    // MARK: - Pins

    @Test func togglePinMovesToPinnedBlockEnd() {
        let store = TabStore(sessionStore: FakeSessionStore())
        store.newTab() // 0
        store.newTab() // 1
        store.newTab() // 2
        let id = store.tabs[2].id

        store.togglePin(id)

        #expect(store.tabs[0].isPinned)
        #expect(store.tabs[0].id == id)
        #expect(!store.tabs[1].isPinned)
        #expect(!store.tabs[2].isPinned)
    }

    @Test func unpinMovesToUnpinnedBlockStart() {
        let store = TabStore(sessionStore: FakeSessionStore())
        store.newTab()
        let firstID = store.tabs[0].id
        store.togglePin(firstID)
        store.newTab()
        store.newTab()

        store.togglePin(firstID)

        #expect(!store.tabs[0].isPinned)
        #expect(store.tabs[0].id == firstID)
        #expect(!store.tabs[1].isPinned)
        #expect(!store.tabs[2].isPinned)
    }

    @Test func moveTabClampsWithinPinGroup() {
        let store = TabStore(sessionStore: FakeSessionStore())
        store.newTab() // 0
        let id0 = store.tabs[0].id
        store.togglePin(id0)
        store.newTab() // 1
        store.newTab() // 2

        store.moveTab(from: 0, to: 2)
        #expect(store.tabs[0].id == id0)
        #expect(store.tabs[0].isPinned)

        store.moveTab(from: 2, to: 0)
        #expect(store.tabs[0].id == id0)
        #expect(!store.tabs[1].isPinned)
    }

    @Test func cannotClosePinnedTab() {
        let store = TabStore(sessionStore: FakeSessionStore())
        store.newTab()
        let id = store.tabs[0].id
        store.togglePin(id)

        store.requestClose(id)

        #expect(store.tabs.count == 1)
        #expect(store.pendingCloseTabID == nil)
    }

    @Test func canCloseActiveTabFalseWhenPinned() {
        let store = TabStore(sessionStore: FakeSessionStore())
        store.newTab()
        store.togglePin(store.tabs[0].id)
        #expect(store.canCloseActiveTab == false)
    }

    // MARK: - Navigation

    @Test func selectNextAndPreviousWrap() {
        let store = TabStore(sessionStore: FakeSessionStore())
        store.newTab()
        store.newTab()
        store.newTab()

        let first = store.tabs[0].id
        let last = store.tabs[2].id

        store.activate(first)
        store.selectPreviousTab()
        #expect(store.activeTabID == last)

        store.selectNextTab()
        #expect(store.activeTabID == first)
    }

    @Test func selectTabAtEightJumpsToLast() {
        let store = TabStore(sessionStore: FakeSessionStore())
        for _ in 0 ..< 5 {
            store.newTab()
        }
        let last = store.tabs[4].id

        store.selectTab(at: 8)
        #expect(store.activeTabID == last)
    }

    @Test func selectTabOutOfRangeIsNoOp() {
        let store = TabStore(sessionStore: FakeSessionStore())
        store.newTab()
        let id = store.activeTabID

        store.selectTab(at: 3)
        #expect(store.activeTabID == id)
    }
}
