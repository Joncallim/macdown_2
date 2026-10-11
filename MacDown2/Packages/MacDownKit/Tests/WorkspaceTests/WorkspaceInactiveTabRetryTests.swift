@testable import FileCore
import Foundation
import Testing
@testable import Workspace

/// Publication/recovery review (2026-10-11), F1 (P1): a failed post-save recovery removal leaves a pending `.remove`.
/// If the user then edits the document and switches to ANOTHER tab, Retry replayed the stale remove against the
/// document's lifetime and deleted the newer, unsaved recovery payload, because the "edited since" guard only looked
/// at the ACTIVE document.
private final class RemovalFailureSwitch: @unchecked Sendable {
    private let lock = NSLock()
    private var failing = true
    func check() throws {
        lock.lock()
        defer { lock.unlock() }
        if failing {
            throw CocoaError(.fileWriteNoPermission)
        }
    }

    func stopFailing() {
        lock.lock()
        failing = false
        lock.unlock()
    }
}

@MainActor
struct WorkspaceInactiveTabRetryTests {
    @Test func aRetryWhileAnotherTabIsActiveDoesNotDeleteTheEditedDocumentsNewerRecovery() async throws {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let urlA = directory.appendingPathComponent("a.md")
        let urlB = directory.appendingPathComponent("b.md")
        _ = try FileStore().write("baseline", to: urlA)
        _ = try FileStore().write("other", to: urlB)
        let removal = RemovalFailureSwitch()
        let recovery = RecoveryBuffer(
            recoveryDirectory: directory.appendingPathComponent("Recovery"),
            hooks: RecoveryBufferHooks(beforeRecoveryRemoval: { _ in try removal.check() })
        )
        let documentA = try FileDocument(fileURL: urlA, recoveryBuffer: recovery).load().edited(text: "A saved")
        #expect(await documentA.persistRecovery())
        let documentB = try FileDocument(fileURL: urlB, recoveryBuffer: recovery).load()
        let store = TabStore(sessionStore: FakeSessionStore(), recoveryBuffer: recovery)
        store.newTab(document: documentA)
        let tabA = try #require(store.activeTabID)
        store.newTab(document: documentB)
        let tabB = try #require(store.activeTabID)
        store.activate(tabA)
        let model = WorkspaceModel(tabStore: store, stateStore: FakeStateStore())

        await model.save() // publishes; removing A's recovery fails, leaving a pending `.remove`
        #expect(model.hasPendingRecoveryCleanup)
        removal.stopFailing()
        model.tabStore.updateActiveDocument { $0.edited(text: "A edited after the save") }
        let edited = try #require(model.activeDocument)
        #expect(await edited.persistRecovery())
        store.activate(tabB) // the user switches away from the edited document

        await model.retryRecoveryCleanup()
        await model.retryRecoveryCleanup() // the second pass replays the (now stale) old-lifetime cleanup

        let live = try #require(store.tabs.first { $0.id == tabA }?.document)
        let surviving = try await recovery.load(for: live.id, epoch: live.recoveryEpoch)
        #expect(surviving == "A edited after the save", "the unsaved edits must still be recoverable for tab A")
        #expect(live.text == "A edited after the save")
        #expect(model.activeDocument?.id == documentB.id, "the retry must not change which tab is active")
    }
}
