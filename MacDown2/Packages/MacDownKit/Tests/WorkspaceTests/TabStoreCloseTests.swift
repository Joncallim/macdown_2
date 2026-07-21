import FileCore
import Foundation
import Testing
@testable import Workspace

@MainActor
@Suite("TabStoreClose")
struct TabStoreCloseTests {
    // MARK: - Single close

    @Test func closeCleanActiveTabActivatesLeftNeighbor() {
        let store = TabStore(sessionStore: FakeSessionStore())
        store.newTab() // A
        store.newTab() // B
        store.newTab() // C (active)
        let activeID = store.tabs[2].id

        store.requestClose(activeID)

        #expect(store.tabs.count == 2)
        #expect(store.activeTabID == store.tabs[1].id) // B
    }

    @Test func closeFirstTabActivatesRightNeighbor() {
        let store = TabStore(sessionStore: FakeSessionStore())
        store.newTab()
        let firstID = store.tabs[0].id
        store.newTab()
        store.activate(firstID)

        store.requestClose(firstID)

        #expect(store.tabs.count == 1)
        #expect(store.activeTabID == store.tabs[0].id)
    }

    @Test func closeOnlyTabLeavesNoActiveTab() {
        let store = TabStore(sessionStore: FakeSessionStore())
        store.newTab()
        let id = store.tabs[0].id

        store.requestClose(id)

        #expect(store.tabs.isEmpty)
        #expect(store.activeTabID == nil)
    }

    @Test func closeNonActiveTabDoesNotChangeActiveTab() {
        let store = TabStore(sessionStore: FakeSessionStore())
        store.newTab()
        let firstID = store.tabs[0].id
        store.newTab()
        let secondID = store.tabs[1].id

        store.requestClose(firstID)

        #expect(store.activeTabID == secondID)
        #expect(store.tabs.count == 1)
    }

    @Test func closeDirtyTabSetsPendingClose() {
        let store = TabStore(sessionStore: FakeSessionStore())
        store.newTab()
        let id = store.tabs[0].id
        store.updateActiveDocument { $0.updatingText("dirty") }

        store.requestClose(id)

        #expect(store.pendingCloseTabID == id)
        #expect(store.tabs.count == 1)
    }

    @Test func resolveCloseCancelKeepsDirtyTab() async {
        let store = TabStore(sessionStore: FakeSessionStore())
        store.newTab()
        let id = store.tabs[0].id
        store.updateActiveDocument { $0.updatingText("dirty") }
        store.requestClose(id)

        await store.resolveClose(.cancel)

        #expect(store.pendingCloseTabID == nil)
        #expect(store.tabs.count == 1)
        #expect(store.activeDocument?.state == .dirty)
    }

    @Test func resolveCloseDiscardRemovesDirtyTab() async {
        let store = TabStore(sessionStore: FakeSessionStore())
        store.newTab()
        let id = store.tabs[0].id
        store.updateActiveDocument { $0.updatingText("dirty") }
        store.requestClose(id)

        await store.resolveClose(.discard)

        #expect(store.pendingCloseTabID == nil)
        #expect(store.tabs.isEmpty)
    }

    @Test func resolveCloseSaveClosesWhenSaveSucceeds() async {
        let store = TabStore(sessionStore: FakeSessionStore())
        store.newTab()
        let id = store.tabs[0].id
        store.updateActiveDocument { $0.updatingText("dirty") }
        store.requestClose(id)

        await store.resolveClose(.save) { true }

        #expect(store.pendingCloseTabID == nil)
        #expect(store.tabs.isEmpty)
    }

    @Test func resolveCloseSaveKeepsTabWhenSaveFails() async {
        let store = TabStore(sessionStore: FakeSessionStore())
        store.newTab()
        let id = store.tabs[0].id
        store.updateActiveDocument { $0.updatingText("dirty") }
        store.requestClose(id)

        await store.resolveClose(.save) { false }

        #expect(store.pendingCloseTabID == nil)
        #expect(store.tabs.count == 1)
        #expect(store.activeDocument?.state == .dirty)
    }

    // MARK: - Batch close

    @Test func closeOthersRemovesCleanTabsImmediatelyAndQueuesDirty() async {
        let store = TabStore(sessionStore: FakeSessionStore())
        store.newTab() // A
        let aID = store.tabs[0].id
        store.newTab() // B
        let bID = store.tabs[1].id
        store.newTab() // C
        let cID = store.tabs[2].id
        store.activate(aID)
        store.updateActiveDocument { $0.updatingText("dirty-a") }
        store.activate(bID)
        store.updateActiveDocument { $0.updatingText("dirty-b") }
        store.activate(cID)
        store.updateActiveDocument { $0.updatingText("dirty-c") }

        store.requestCloseOthers(of: aID)

        #expect(store.tabs.count == 3)
        #expect(store.pendingCloseTabID == bID)

        await store.resolveClose(.discard)
        #expect(store.pendingCloseTabID == cID)
        #expect(store.tabs.count == 2)

        await store.resolveClose(.discard)
        #expect(store.pendingCloseTabID == nil)
        #expect(store.tabs.count == 1)
        #expect(store.activeTabID == aID)
    }

    @Test func batchCloseCancelAbortsEntireQueue() async {
        let store = TabStore(sessionStore: FakeSessionStore())
        store.newTab()
        let aID = store.tabs[0].id
        store.newTab()
        let bID = store.tabs[1].id
        store.activate(aID)
        store.updateActiveDocument { $0.updatingText("dirty-a") }
        store.activate(bID)
        store.updateActiveDocument { $0.updatingText("dirty-b") }

        store.requestCloseOthers(of: bID)
        #expect(store.pendingCloseTabID == aID)

        await store.resolveClose(.cancel)

        #expect(store.pendingCloseTabID == nil)
        #expect(store.tabs.count == 2)
        #expect(store.tabs[0].document.state == .dirty)
        #expect(store.tabs[1].document.state == .dirty)
    }

    @Test func closeToTheRightRespectsReferenceIndex() {
        let store = TabStore(sessionStore: FakeSessionStore())
        store.newTab() // 0
        store.newTab() // 1
        store.newTab() // 2
        store.newTab() // 3

        let firstID = store.tabs[0].id
        let secondID = store.tabs[1].id

        store.requestCloseToTheRight(of: secondID)

        #expect(store.tabs.count == 2)
        #expect(store.tabs[0].id == firstID)
        #expect(store.tabs[1].id == secondID)
    }

    @Test func batchCloseSkipsPinned() {
        let store = TabStore(sessionStore: FakeSessionStore())
        store.newTab() // 0
        let firstID = store.tabs[0].id
        store.newTab() // 1
        let pinnedID = store.tabs[1].id
        store.newTab() // 2
        store.togglePin(pinnedID)

        store.requestCloseToTheRight(of: firstID)

        #expect(store.tabs.count == 2)
        #expect(store.tabs[0].id == pinnedID)
        #expect(store.tabs[1].id == firstID)
    }
}
