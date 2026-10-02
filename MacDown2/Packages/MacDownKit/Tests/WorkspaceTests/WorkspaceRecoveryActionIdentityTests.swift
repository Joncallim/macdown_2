@testable import FileCore
import Foundation
import Testing
@testable import Workspace

/// #183 F01: a pending recovery action is identified by kind + exact lifetime,
/// but carries a payload (text/mutation/state) that a newer failure for the same
/// lifetime must replace — `Set.insert` silently kept the older one.
@MainActor
struct WorkspaceRecoveryActionIdentityTests {
    private func makeModel(recovery: RecoveryBuffer, document: FileDocument) -> WorkspaceModel {
        let store = TabStore(sessionStore: FakeSessionStore(), recoveryBuffer: recovery)
        store.newTab(document: document)
        return WorkspaceModel(tabStore: store, stateStore: FakeStateStore())
    }

    @Test func aNewerFailureForTheSameLifetimeReplacesTheRegisteredPayload() async throws {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let recovery = RecoveryBuffer(recoveryDirectory: directory.appendingPathComponent("Recovery"))
        let older = FileDocument(recoveryBuffer: recovery).updatingText("older")
        let newer = older.updatingText("newer")
        let model = makeModel(recovery: recovery, document: newer)

        model.registerPendingRecovery(.persist(for: older))
        model.registerPendingRecovery(.persist(for: newer))

        #expect(model.pendingRecoveryCleanupActions.count == 1)
        #expect(model.pendingRecoveryCleanupActions.first?.text == "newer")
        await model.retryRecoveryCleanup()
        #expect(!model.hasPendingRecoveryCleanup)
        #expect(try await recovery.load(for: newer.id, epoch: newer.recoveryEpoch) == "newer")
    }

    @Test func completingAStaleReplayLeavesTheNewerRegistrationPending() {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let recovery = RecoveryBuffer(recoveryDirectory: directory.appendingPathComponent("Recovery"))
        let older = FileDocument(recoveryBuffer: recovery).updatingText("older")
        let newer = older.updatingText("newer")
        let model = makeModel(recovery: recovery, document: newer)

        model.registerPendingRecovery(.persist(for: newer)) // registered while the older replay was in flight
        model.completePendingRecovery(.persist(for: older)) // the older replay then finishes

        #expect(model.pendingRecoveryCleanupActions.count == 1)
        #expect(model.pendingRecoveryCleanupActions.first?.text == "newer")
        model.completePendingRecovery(.persist(for: newer))
        #expect(!model.hasPendingRecoveryCleanup)
    }

    @Test func migrationsFromDifferentSourceLifetimesStayDistinct() {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let recovery = RecoveryBuffer(recoveryDirectory: directory.appendingPathComponent("Recovery"))
        let sourceA = FileDocument(recoveryBuffer: recovery).updatingText("a")
        let sourceB = FileDocument(recoveryBuffer: recovery).updatingText("b")
        let destination = FileDocument(
            fileURL: directory.appendingPathComponent("destination.md"), recoveryBuffer: recovery
        ).updatingText("moved")
        let model = makeModel(recovery: recovery, document: destination)

        model.registerPendingRecovery(.migrate(source: sourceA, destination: destination))
        model.registerPendingRecovery(.migrate(source: sourceB, destination: destination))

        #expect(model.pendingRecoveryCleanupActions.count == 2)
    }
}
