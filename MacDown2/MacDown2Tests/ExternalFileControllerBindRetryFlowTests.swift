import EditorCore
import FileCore
import Foundation
@testable import MacDown2
import Testing
import Workspace

/// Handoff regression 4 (#379): drives a REAL first-watch failure (the parent directory does not exist yet) and the
/// controller's retry through a controlled sleeper, instead of only testing the document selector. Observation
/// contexts are awaited through `afterObservationContextHandled`, not slept for.
@MainActor
struct ExternalFileControllerBindRetryFlowTests {
    @MainActor private final class SleeperGate {
        private var entered = false
        private var enteredWaiter: CheckedContinuation<Void, Never>?
        private var release: CheckedContinuation<Void, any Error>?

        func sleep(_: Duration) async throws {
            entered = true
            enteredWaiter?.resume()
            enteredWaiter = nil
            try await withCheckedThrowingContinuation { release = $0 }
        }

        func waitUntilEntered() async {
            if entered {
                return
            }
            await withCheckedContinuation { enteredWaiter = $0 }
        }

        func letRetryRun() {
            release?.resume()
            release = nil
        }
    }

    @MainActor private final class ObservationCounter {
        var contexts: [DocumentFileObservationContext] = []
        private var waiter: (count: Int, continuation: CheckedContinuation<Void, Never>)?

        func record(_ context: DocumentFileObservationContext) {
            contexts.append(context)
            if let waiter, contexts.count >= waiter.count {
                self.waiter = nil
                waiter.continuation.resume()
            }
        }

        func waitForCount(_ count: Int) async {
            if contexts.count >= count {
                return
            }
            await withCheckedContinuation { waiter = (count, $0) }
        }
    }

    private struct Fixture {
        let directory: URL
        let missingParent: URL
        let url: URL
        let model: WorkspaceModel
        let controller: ExternalFileController
        let gate: SleeperGate
        let observations: ObservationCounter
        let captured: FileDocument
    }

    private func makeFixture() throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let missingParent = directory.appendingPathComponent("later")
        let url = missingParent.appendingPathComponent("doc.txt")
        let captured = FileDocument(fileURL: url)
        let recoveryDirectory = directory.appendingPathComponent("Recovery")
        let store = TabStore(
            sessionStore: WorkspaceSessionStore(fileURL: directory.appendingPathComponent("session.json")),
            recoveryBuffer: RecoveryBuffer(recoveryDirectory: recoveryDirectory)
        )
        store.newTab(document: captured)
        let model = WorkspaceModel(tabStore: store)
        let controller = ExternalFileController(
            model: model,
            editorStore: EditorTextSystemStore(),
            identity: "bind-retry-flow-test"
        )
        let gate = SleeperGate()
        let observations = ObservationCounter()
        controller.bindRetrySleep = { try await gate.sleep($0) }
        controller.afterObservationContextHandled = { observations.record($0) }
        return Fixture(
            directory: directory,
            missingParent: missingParent,
            url: url,
            model: model,
            controller: controller,
            gate: gate,
            observations: observations,
            captured: captured
        )
    }

    @Test func theRetryAfterARealFirstWatchFailureUsesTheLiveEncodingPolicy() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let controller = fixture.controller

        controller.synchronize(with: fixture.captured)
        await fixture.gate.waitUntilEntered()
        guard case .monitorFailed = controller.notice else {
            Issue.record("the first watch should have failed (parent directory missing), notice=\(controller.notice)")
            return
        }

        // While the retry waits: the directory appears and a Save with Encoding (Latin-1) succeeds.
        try FileManager.default.createDirectory(at: fixture.missingParent, withIntermediateDirectories: true)
        try "caf\u{E9}".write(to: fixture.url, atomically: true, encoding: .utf8)
        let loaded = try FileDocument(fileURL: fixture.url).load()
        let latin1 = FileEncodingMetadata(encoding: .isoLatin1, bom: .none)
        let live = try loaded.saving(expectedRevision: loaded.lastKnownRevision, encodingOverride: latin1)
        #expect(live.id == fixture.captured.id, "file documents are identified by URL")
        fixture.model.tabStore.updateActiveDocument { _ in live }

        fixture.gate.letRetryRun()
        await controller.bindRetryTask?.value
        await controller.bindTask?.value
        await fixture.observations.waitForCount(1)

        #expect(
            controller.notice == .none,
            "a successful retry clears the watcher notice and raises no undecodable notice"
        )
        let active = try #require(fixture.model.activeDocument)
        #expect(active.encoding == latin1)
        #expect(active.state == .clean, "the stale automatic UTF-8 policy must not mark the saved file unavailable")

        // A later external edit is still reconciled by the rebound monitor.
        try "caf\u{E9} edited".write(to: fixture.url, atomically: false, encoding: .isoLatin1)
        await fixture.observations.waitForCount(2)
        #expect(fixture.model.activeDocument?.text == "caf\u{E9} edited")
    }

    @Test func aRetryForADocumentThatIsNoLongerActiveDoesNotBindAnything() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let controller = fixture.controller

        controller.synchronize(with: fixture.captured)
        await fixture.gate.waitUntilEntered()

        // A different file becomes the active document while the retry waits (A -> B).
        let other = FileDocument(fileURL: fixture.directory.appendingPathComponent("other.txt"))
        fixture.model.tabStore.updateActiveDocument { _ in other }
        try FileManager.default.createDirectory(at: fixture.missingParent, withIntermediateDirectories: true)

        fixture.gate.letRetryRun()
        await controller.bindRetryTask?.value
        await controller.bindTask?.value

        #expect(fixture.observations.contexts.isEmpty, "no monitor may be bound on behalf of the stale document")
    }
}
