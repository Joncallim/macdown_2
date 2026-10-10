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

        /// Waits for `count` handled contexts. `bound` only stops a context that never arrives from hanging the run
        /// (the caller then fails on the returned `false`); it is not a product timing threshold.
        @discardableResult
        func waitForCount(_ count: Int, bound: Duration = .seconds(60)) async -> Bool {
            if contexts.count >= count {
                return true
            }
            let timeout = Task { @MainActor [weak self] in
                try? await Task.sleep(for: bound)
                // A cancelled timeout must not release a LATER waiter.
                guard !Task.isCancelled else { return }
                self?.releaseWaiter()
            }
            await withCheckedContinuation { waiter = (count, $0) }
            timeout.cancel()
            return contexts.count >= count
        }

        private func releaseWaiter() {
            guard let waiter else { return }
            self.waiter = nil
            waiter.continuation.resume()
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
        #expect(await fixture.observations.waitForCount(1))

        #expect(
            controller.notice == .none,
            "a successful retry clears the watcher notice and raises no undecodable notice"
        )
        let active = try #require(fixture.model.activeDocument)
        #expect(active.encoding == latin1)
        #expect(active.state == .clean, "the stale automatic UTF-8 policy must not mark the saved file unavailable")

        // A later external edit is still reconciled by the rebound monitor.
        try "caf\u{E9} edited".write(to: fixture.url, atomically: false, encoding: .isoLatin1)
        #expect(await fixture.observations.waitForCount(2))
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

    @Test func aBackToBackSynchronizeThatSkipsTheBindDoesNotCancelTheRetry() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let controller = fixture.controller

        controller.synchronize(with: fixture.captured) // first bind fails; its retry waits on the sleeper
        await fixture.gate.waitUntilEntered()
        try FileManager.default.createDirectory(at: fixture.missingParent, withIntermediateDirectories: true)
        try "text".write(to: fixture.url, atomically: true, encoding: .utf8)
        let loaded = try FileDocument(fileURL: fixture.url).load()
        fixture.model.tabStore.updateActiveDocument { _ in loaded }
        let generationBefore = controller.lifecycleGeneration

        // The URL is already "bound" (the failed first attempt recorded it), so this is skipped: only the baseline is
        // refreshed and the monitor is NOT rebound here. The pending retry must therefore still be alive.
        controller.synchronize(with: loaded)
        #expect(controller.lifecycleGeneration == generationBefore, "a skipped bind must not advance the generation")
        #expect(fixture.observations.contexts.isEmpty, "nothing is bound yet")
        guard case .monitorFailed = controller.notice else {
            Issue
                .record(
                    "the watcher failure must stay visible until the retry recovers it, notice=\(controller.notice)"
                )
            return
        }

        fixture.gate.letRetryRun()
        await controller.bindRetryTask?.value
        await controller.bindTask?.value

        #expect(await fixture.observations.waitForCount(1), "the surviving retry binds the monitor")
        #expect(controller.notice == .none)
        #expect(fixture.model.activeDocument?.state == .clean)
    }

    @Test func anAToBToARoundTripDoesNotLetTheOldRetryRebindTheMonitor() async throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let controller = fixture.controller

        controller.synchronize(with: fixture.captured) // A fails, retry waits
        await fixture.gate.waitUntilEntered()
        try FileManager.default.createDirectory(at: fixture.missingParent, withIntermediateDirectories: true)
        try "a".write(to: fixture.url, atomically: true, encoding: .utf8)
        let otherURL = fixture.directory.appendingPathComponent("other.txt")
        try "b".write(to: otherURL, atomically: true, encoding: .utf8)
        let documentA = try FileDocument(fileURL: fixture.url).load()
        let documentB = try FileDocument(fileURL: otherURL).load()

        fixture.model.tabStore.updateActiveDocument { _ in documentB }
        controller.synchronize(with: documentB) // B binds
        await controller.bindTask?.value
        #expect(await fixture.observations.waitForCount(1), "B bound")
        fixture.model.tabStore.updateActiveDocument { _ in documentA }
        controller.synchronize(with: documentA) // back to A: binds now that the directory exists
        await controller.bindTask?.value
        #expect(await fixture.observations.waitForCount(2), "A bound")
        let generationAtARound = controller.lifecycleGeneration

        fixture.gate.letRetryRun() // the ORIGINAL A retry wakes up
        await controller.bindRetryTask?.value
        await controller.bindTask?.value

        #expect(
            controller.lifecycleGeneration == generationAtARound,
            "the first-A retry belongs to a retired generation"
        )
        #expect(fixture.observations.contexts.count == 2)
        #expect(controller.boundURL == fixture.url.standardizedFileURL)
    }
}
