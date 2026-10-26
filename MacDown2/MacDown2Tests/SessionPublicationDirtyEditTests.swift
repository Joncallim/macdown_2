import FileCore
import Foundation
@testable import MacDown2
import Testing

extension SessionViewStateRoundTripTests {
    @Test func dirtyEditDuringRecoveryCannotPublishAnOlderTerminationSnapshot() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let sessions = MemorySessionStore()
        let coordinator = try coordinatorWithOneTab(sessions: sessions, directory: directory)
        let controller = try #require(coordinator.controllers.first)
        await coordinator.awaitScheduledSessionSaveForTesting()
        controller.model.tabStore.updateActiveDocument { $0.edited(text: "first edit") }
        controller.updateTitleAndEditedState()
        await coordinator.awaitScheduledSessionSaveForTesting()
        #expect(sessions.publicationCount > 0)
        sessions.session = nil
        sessions.publicationCount = 0
        let firstDocument = try #require(controller.model.activeDocument)
        let firstGate = FirstCallGate()
        let secondGate = FirstCallGate()
        defer {
            firstGate.release()
            secondGate.release()
        }
        var recoveryPasses = 0
        coordinator.afterSessionRecoveryPersisted = {
            recoveryPasses += 1
            if recoveryPasses == 1 {
                await firstGate.pass()
            } else if recoveryPasses == 2 {
                await secondGate.pass()
            }
        }

        let termination = Task { @MainActor in await coordinator.saveSessionForTermination() }
        for _ in 0 ..< 1000 where !firstGate.entered {
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(firstGate.entered)

        // This is the ordinary editor-binding path: dirty -> dirty does not schedule a coordinator session save.
        controller.model.tabStore.updateActiveDocument { $0.edited(text: "second edit") }
        let currentDocument = try #require(controller.model.activeDocument)
        #expect(currentDocument.mutationGeneration > firstDocument.mutationGeneration)
        firstGate.release()
        for _ in 0 ..< 1000 where !secondGate.entered {
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(secondGate.entered)

        #expect(sessions.publicationCount == 0)
        let recovered = try await currentDocument.recoveryBuffer.load(
            for: currentDocument.id, epoch: currentDocument.recoveryEpoch
        )
        #expect(recovered?.isExactlyEqual(to: "second edit") == true)
        secondGate.release()

        #expect(await termination.value.persisted)
        #expect(sessions.publicationCount == 1)
        #expect(sessions.session?.tabs.first?.documentRecoveryEpoch == currentDocument.recoveryEpoch)
    }
}
