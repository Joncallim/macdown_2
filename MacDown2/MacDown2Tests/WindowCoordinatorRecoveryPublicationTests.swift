import FileCore
import Foundation
@testable import MacDown2
import Testing
import Workspace

@MainActor
extension ExternalFileControllerRecoveryTests {
    @Test func terminationRejectsCanonicallyEquivalentButDifferentRecoveryBytes() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let recovery = RecoveryBuffer(recoveryDirectory: directory.appendingPathComponent("Recovery"))
        guard let coordinator = makeCoordinator(directory: directory, recoveryBuffer: recovery) else {
            Issue.record("Unable to create isolated defaults for the coordinator")
            return
        }

        let visible = "e\u{301}"
        let stored = "\u{00E9}"
        #expect(visible == stored)
        #expect(!visible.isExactlyEqual(to: stored))
        let document = FileDocument(recoveryBuffer: recovery).updatingText(visible)
        #expect(try await recovery.saveCurrentLifetime(
            content: stored,
            for: document.id,
            version: document.mutationGeneration,
            epoch: document.recoveryEpoch
        ))

        let model = coordinator.makeWindowModel()
        model.tabStore.newTab(document: document)
        let controller = makeWindowController(model: model, coordinator: coordinator)
        coordinator.controllers = [controller]

        let result = await coordinator.saveSessionResult()
        guard case let .recoveryFailed(failedController) = result else {
            Issue.record("A different recovery byte sequence must block session publication")
            return
        }
        #expect(failedController === controller)
        #expect(WorkspaceSessionStore(fileURL: directory.appendingPathComponent("session")).loadSession() == nil)
        #expect(try await recovery.load(for: document.id, epoch: document.recoveryEpoch)?
            .isExactlyEqual(to: stored) == true)
    }
}
