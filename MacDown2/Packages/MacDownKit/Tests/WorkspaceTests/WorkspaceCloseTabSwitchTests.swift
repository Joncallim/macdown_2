@testable import FileCore
import Foundation
import Testing
@testable import Workspace

private struct InjectedCloseWriteFailure: Error {}

/// Post-fix review (d2b7e242) F2: Save-and-close judged the save by the ACTIVE tab and retired recovery against the
/// active tab, so switching tabs during a failing save closed the unsaved tab and deleted its recovery.
@MainActor
struct WorkspaceCloseTabSwitchTests {
    /// Save-and-close of dirty tab A; the save is held at publication, the user activates clean tab B, and the save
    /// then FAILS. The close must keep A open (dirty) and keep its recovery.
    @Test func aFailedSaveAndCloseAfterATabSwitchMustNotCloseTheUnsavedTab() async throws {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let urlA = directory.appendingPathComponent("a.md")
        let urlB = directory.appendingPathComponent("b.md")
        _ = try FileStore().write("baseline", to: urlA)
        _ = try FileStore().write("other", to: urlB)
        let recovery = RecoveryBuffer(recoveryDirectory: directory.appendingPathComponent("Recovery"))
        let barrier = SavePublicationBarrier()
        let failingStore = FileStore(afterBaselineVerification: { _ in
            barrier.arriveAndWait()
            throw InjectedCloseWriteFailure()
        })
        let documentA = try FileDocument(fileURL: urlA, fileStore: failingStore, recoveryBuffer: recovery)
            .load().edited(text: "UNSAVED WORK")
        #expect(await documentA.persistRecovery())
        let documentB = try FileDocument(fileURL: urlB, recoveryBuffer: recovery).load()
        let store = TabStore(sessionStore: FakeSessionStore(), recoveryBuffer: recovery)
        store.newTab(document: documentA)
        let tabA = try #require(store.activeTabID)
        store.newTab(document: documentB)
        let tabB = try #require(store.activeTabID)
        store.activate(tabA)
        let model = WorkspaceModel(tabStore: store, stateStore: FakeStateStore())
        defer { barrier.cancelAndAllowPublication() }

        model.requestCloseDocument()
        #expect(store.pendingCloseTabID == tabA)
        let close = Task { await model.resolveClose(.save) }
        guard await waitForSignal(
            timeout: .seconds(30),
            wait: { await barrier.waitForFirstPublication() },
            onTimeout: { barrier.cancelWaiters() }
        ) else {
            Issue.record("The save never reached publication")
            return
        }
        store.activate(tabB) // user clicks another (clean) tab while Save-and-close is writing
        barrier.allowPublication()
        await close.value

        #expect(try FileStore().read(from: urlA).content == "baseline", "the save failed: disk keeps the old text")
        #expect(model.lastError != nil, "the failure is surfaced")
        #expect(store.tabs.contains { $0.id == tabA }, "the unsaved tab must NOT be closed after a failed save")
        let recovered = try await recovery.load(for: documentA.id, epoch: documentA.recoveryEpoch)
        #expect(recovered == "UNSAVED WORK", "the unsaved text's recovery must survive")
    }
}
