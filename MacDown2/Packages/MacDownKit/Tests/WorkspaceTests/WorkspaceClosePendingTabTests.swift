@testable import FileCore
import Foundation
import Testing
@testable import Workspace

/// Final-head review (ebf6445e) F2: Save/Discard-and-close acted on the ACTIVE tab while `TabStore.resolveClose`
/// closes the PENDING tab, so a batch close (or a tab switch after the request) saved or retired the wrong document
/// and removed the dirty pending tab unwritten.
@MainActor
struct WorkspaceClosePendingTabTests {
    private struct Fixture {
        let directory: URL
        let urlA: URL
        let recovery: RecoveryBuffer
        let store: TabStore
        let model: WorkspaceModel
        let tabA: UUID
        let tabB: UUID
    }

    private func makeFixture() throws -> Fixture {
        let directory = temporaryDirectory()
        let urlA = directory.appendingPathComponent("a.md")
        let urlB = directory.appendingPathComponent("b.md")
        _ = try FileStore().write("A baseline", to: urlA)
        _ = try FileStore().write("B baseline", to: urlB)
        let recovery = RecoveryBuffer(recoveryDirectory: directory.appendingPathComponent("Recovery"))
        let documentA = try FileDocument(fileURL: urlA, recoveryBuffer: recovery).load().edited(text: "A UNSAVED")
        let documentB = try FileDocument(fileURL: urlB, recoveryBuffer: recovery).load()
        let store = TabStore(sessionStore: FakeSessionStore(), recoveryBuffer: recovery)
        store.newTab(document: documentA)
        let tabA = try #require(store.activeTabID)
        store.newTab(document: documentB)
        let tabB = try #require(store.activeTabID)
        let model = WorkspaceModel(tabStore: store, stateStore: FakeStateStore())
        return Fixture(
            directory: directory,
            urlA: urlA,
            recovery: recovery,
            store: store,
            model: model,
            tabA: tabA,
            tabB: tabB
        )
    }

    /// "Close Others" from active clean tab B leaves dirty A pending; Save must save A (or keep it open).
    @Test func saveForABatchClosePendingTabSavesThatTab() async throws {
        let fixture = try makeFixture()
        defer { cleanup(fixture.directory) }
        fixture.store.requestCloseOthers(of: fixture.tabB)
        #expect(fixture.store.pendingCloseTabID == fixture.tabA)

        await fixture.model.resolveClose(.save)

        let aOpen = fixture.store.tabs.contains { $0.id == fixture.tabA }
        let disk = try FileStore().read(from: fixture.urlA).content
        #expect(aOpen || disk == "A UNSAVED", "A was closed but its text was never written (disk: \(disk))")
    }

    /// Single close requested on A, user activates B before answering; Save must not close unsaved A.
    @Test func saveAfterSwitchBeforeResolveKeepsUnsavedTab() async throws {
        let fixture = try makeFixture()
        defer { cleanup(fixture.directory) }
        fixture.store.activate(fixture.tabA)
        fixture.model.requestCloseDocument()
        #expect(fixture.store.pendingCloseTabID == fixture.tabA)
        fixture.store.activate(fixture.tabB)

        await fixture.model.resolveClose(.save)

        let aOpen = fixture.store.tabs.contains { $0.id == fixture.tabA }
        let disk = try FileStore().read(from: fixture.urlA).content
        #expect(aOpen || disk == "A UNSAVED", "A was closed but its text was never written (disk: \(disk))")
    }

    /// Discarding the pending tab must retire ITS recovery, not that of the dirty tab that happens to be active.
    @Test func discardForABatchClosePendingTabKeepsTheActiveDirtyTabsRecovery() async throws {
        let fixture = try makeFixture()
        defer { cleanup(fixture.directory) }
        let activeDirty = try #require(fixture.store.tabs.first { $0.id == fixture.tabB }?.document)
            .edited(text: "B UNSAVED")
        fixture.store.updateDocument(inTab: fixture.tabB) { _ in activeDirty }
        #expect(await activeDirty.persistRecovery())
        fixture.store.requestCloseOthers(of: fixture.tabB)
        #expect(fixture.store.pendingCloseTabID == fixture.tabA)

        await fixture.model.resolveClose(.discard)

        #expect(!fixture.store.tabs.contains { $0.id == fixture.tabA })
        #expect(fixture.store.tabs.contains { $0.id == fixture.tabB })
        let kept = try await fixture.recovery.load(for: activeDirty.id, epoch: activeDirty.recoveryEpoch)
        #expect(kept == "B UNSAVED", "the still-open dirty tab keeps its recovery")
    }
}
