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

    /// #183 F10: an ordinary save built from a snapshot that predates an accepted
    /// encoding save must not write the old encoding back.
    @Test func aQueuedOrdinarySaveDoesNotRevertAnAcceptedEncodingChoice() async throws {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let url = directory.appendingPathComponent("encoding-lineage.txt")
        try "café".write(to: url, atomically: true, encoding: .utf8)
        let writer = DocumentWriter()
        let latin1 = FileEncodingMetadata(encoding: .isoLatin1, bom: .none)
        let original = try FileDocument(fileURL: url).load().edited(text: "café 1")

        let encodingSave = try await writer.save(original, encodingOverride: latin1)
        let staleSnapshot = original.edited(text: "café 2")
        let queuedOrdinary = try await writer.save(staleSnapshot)

        #expect(queuedOrdinary.document.encoding == latin1)
        #expect(try Data(contentsOf: url) == Data("café 2".data(using: .isoLatin1) ?? Data()))
        await writer.acknowledge(encodingSave)
        await writer.acknowledge(queuedOrdinary)
    }

    /// #183 F10 ↔ F15: a representation failure names the encoding actually
    /// attempted (the inherited one), not the stale queued document's metadata.
    @Test func aRepresentationFailureNamesTheInheritedEncodingActuallyAttempted() async throws {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let url = directory.appendingPathComponent("encoding-failure-label.txt")
        try "café".write(to: url, atomically: true, encoding: .utf8)
        let writer = DocumentWriter()
        let latin1 = FileEncodingMetadata(encoding: .isoLatin1, bom: .none)
        let original = try FileDocument(fileURL: url).load().edited(text: "café 1")
        let encodingSave = try await writer.save(original, encodingOverride: latin1)

        // The stale snapshot still says UTF-8, but the queued save inherits Latin-1,
        // which cannot hold the emoji.
        let staleSnapshot = original.edited(text: "café 😀")
        #expect(staleSnapshot.encoding == .utf8Default)
        do {
            _ = try await writer.save(staleSnapshot)
            Issue.record("expected the save to fail")
        } catch {
            guard case let .textNotRepresentable(attempted) = error else {
                Issue.record("expected .textNotRepresentable, got \(error)")
                return
            }
            #expect(attempted == latin1)
        }
        await writer.acknowledge(encodingSave)
    }

    @Test func anExplicitEncodingOnALaterSaveStillWins() async throws {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let url = directory.appendingPathComponent("encoding-explicit.txt")
        try "cafe".write(to: url, atomically: true, encoding: .utf8)
        let writer = DocumentWriter()
        let latin1 = FileEncodingMetadata(encoding: .isoLatin1, bom: .none)
        let original = try FileDocument(fileURL: url).load().edited(text: "cafe 1")

        let first = try await writer.save(original, encodingOverride: latin1)
        let second = try await writer.save(original.edited(text: "cafe 2"), encodingOverride: .utf8Default)

        #expect(second.document.encoding == .utf8Default)
        await writer.acknowledge(first)
        await writer.acknowledge(second)
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
    /// `waitForSignal` itself lives in `AsyncBarrierWaiting.swift`, shared
    /// with every other test in this target that waits on a
    /// `SavePublicationBarrier`.
    private func waitForFirstPublication(from barrier: SavePublicationBarrier) async -> Bool {
        await waitForSignal(
            timeout: .seconds(3),
            wait: { await barrier.waitForFirstPublication() },
            onTimeout: { barrier.cancelWaiters() }
        )
    }

    private func waitForSecondWriterEntry(from barrier: SavePublicationBarrier) async -> Bool {
        await waitForSignal(
            timeout: .seconds(3),
            wait: { await barrier.waitForSecondSaveToEnterWriterLane() },
            onTimeout: { barrier.cancelWaiters() }
        )
    }
}
