@testable import FileCore
import Foundation
import Testing
@testable import Workspace

@Suite("DocumentWriter queued saves")
struct WorkspaceModelSaveQueueTests {
    @Test func sequentialSavesCompactAcceptedLineageAfterTerminalAdoption() async throws {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let url = directory.appendingPathComponent("compact-lineage.md")
        _ = try FileStore().write("seed", to: url)
        let writer = DocumentWriter()
        var document = try FileDocument(fileURL: url).load().edited(text: "0")

        // A long editing session must not leave one accepted revision mapping
        // behind for every completed save once no caller is queued.
        for index in 1 ... 2000 {
            let saved = try await writer.save(document)
            await writer.acknowledge(saved)
            #expect(await writer.lineageCount(for: saved.document) == 0)
            document = saved.document.edited(text: "edit-\(index)")
        }

        #expect(try FileStore().read(from: url).content == "edit-1999")
    }

    @Test func queuedSavesCarryAcceptedBaselinesAcrossMultipleEdits() async throws {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let url = directory.appendingPathComponent("queued-saves.md")
        _ = try FileStore().write("baseline", to: url)
        let barrier = SavePublicationBarrier()
        let delayedStore = FileStore(afterBaselineVerification: { _ in barrier.arriveAndWait() })
        let writer = DocumentWriter(onRequestQueued: { barrier.secondSaveEnteredWriterLane() })
        let document = try FileDocument(fileURL: url, fileStore: delayedStore)
            .load()
            .edited(text: "first")
        let thirdDocument = document.edited(text: "second").edited(text: "third")
        let fourthDocument = thirdDocument.edited(text: "fourth")
        defer { barrier.cancelAndAllowPublication() }

        let firstSave = Task { try await writer.save(document) }
        guard await waitForFirstPublication(from: barrier) else {
            Issue.record("First queued save did not reach publication")
            return
        }

        let secondSave = Task { try await writer.save(thirdDocument) }
        guard await waitForSecondWriterEntry(from: barrier) else {
            Issue.record("Second save did not enter the writer lane")
            return
        }
        barrier.allowPublication()
        let first = try await firstSave.value
        let second = try await secondSave.value

        #expect(second.expectedRevision == first.document.lastKnownRevision)
        #expect(try FileStore().read(from: url).content == "third")
        let afterFirst = fourthDocument.adoptingSavedBaseline(from: first.document)
        let afterSecond = afterFirst.adoptingSavedBaseline(from: second.document)
        #expect(afterSecond.text == "fourth")
        #expect(afterSecond.state == .dirty)
        await writer.acknowledge(first)
        await writer.acknowledge(second)
    }

    @Test func completedWriteRetainsLineageUntilTheModelAcknowledgesIt() async throws {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let url = directory.appendingPathComponent("result-acknowledgement.md")
        _ = try FileStore().write("baseline", to: url)
        let writer = DocumentWriter()
        let original = try FileDocument(fileURL: url).load().edited(text: "first")

        let first = try await writer.save(original)
        let secondInput = original.edited(text: "second")
        let second = try await writer.save(secondInput)

        #expect(second.expectedRevision == first.document.lastKnownRevision)
        #expect(try FileStore().read(from: url).content == "second")
        await writer.acknowledge(first)
        await writer.acknowledge(second)
        #expect(await writer.lineageCount(for: second.document) == 0)
    }

    @Test func unacknowledgedResultsRetainReachableExpectedLineage() async throws {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let url = directory.appendingPathComponent("reachable-lineage.md")
        _ = try FileStore().write("baseline", to: url)
        let writer = DocumentWriter()
        let original = try FileDocument(fileURL: url).load().edited(text: "A")

        let first = try await writer.save(original)
        let second = try await writer.save(original.edited(text: "B"))
        await writer.acknowledge(first)

        // C descends from R1 after A has been acknowledged, while B's
        // unacknowledged result has already advanced R1 to R2.
        let third = try await writer.save(first.document.edited(text: "C"))

        #expect(second.expectedRevision == first.document.lastKnownRevision)
        #expect(third.expectedRevision == second.document.lastKnownRevision)
        #expect(try FileStore().read(from: url).content == "C")
        await writer.acknowledge(second)
        await writer.acknowledge(third)
    }

    /// The timeout is a cleanup guard only. Ordering is established by the
    /// writer/file-store continuations, never by elapsed time or yielding.
    private func waitForFirstPublication(from barrier: SavePublicationBarrier) async -> Bool {
        await waitForSignal(
            wait: { await barrier.waitForFirstPublication() },
            cancel: { barrier.cancelWaiters() }
        )
    }

    private func waitForSecondWriterEntry(from barrier: SavePublicationBarrier) async -> Bool {
        await waitForSignal(
            wait: { await barrier.waitForSecondSaveToEnterWriterLane() },
            cancel: { barrier.cancelWaiters() }
        )
    }

    private func waitForSignal(
        wait: @escaping @Sendable () async -> Bool,
        cancel: @escaping @Sendable () -> Void
    ) async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask { await wait() }
            group.addTask {
                try? await Task.sleep(for: .seconds(3))
                return false
            }
            let result = await group.next() ?? false
            if !result {
                cancel()
            }
            group.cancelAll()
            return result
        }
    }
}
