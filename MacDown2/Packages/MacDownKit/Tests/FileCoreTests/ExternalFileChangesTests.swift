@testable import FileCore
import Foundation
import Testing

@Suite("External file reconciliation")
struct ExternalFileChangesTests {
    @Test func snapshotUsesExactBytesForSizeAndDigest() throws {
        let fixture = try FixtureFile(text: "abc")
        let snapshot = try FileStore().readSnapshot(from: fixture.url)

        #expect(snapshot.revision.fileSize == 3)
        #expect(snapshot.revision.sha256 == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    @Test func snapshotHonorsUTF16BOMWithoutRetainingItInText() throws {
        let fixture = try FixtureFile()
        let data = Data([0xFF, 0xFE, 0x68, 0x00, 0x69, 0x00])
        try data.write(to: fixture.url)

        let snapshot = try FileStore().readSnapshot(from: fixture.url)

        #expect(snapshot.text == "hi")
        #expect(snapshot.encoding == .utf16LittleEndian)
    }

    @Test func writeReturnsTheRevisionThatSnapshotReads() throws {
        let fixture = try FixtureFile()
        let store = FileStore()
        let written = try store.write("café", to: fixture.url)
        let snapshot = try store.readSnapshot(from: fixture.url)

        #expect(written == snapshot.revision)
        #expect(snapshot.revision.fileSize == "café".utf8.count)
    }

    @Test func directExternalWriterAfterPublicationSurvivesAndLeavesSaveUnaccepted() throws {
        let fixture = try FixtureFile()
        let store = FileStore(afterReplacement: { url in
            try Data("racing".utf8).write(to: url)
        })

        do {
            _ = try store.write("ours", to: fixture.url)
            Issue.record("Expected racing writer to invalidate the save revision")
        } catch {
            guard case .fileChangedDuringRead = error else {
                Issue.record("Expected fileChangedDuringRead, got \(error)")
                return
            }
        }
        #expect(try FileStore().read(from: fixture.url).content == "racing")
    }

    @Test func conditionalWriteRefusesAnExternallyAdvancedBaseline() throws {
        let fixture = try FixtureFile(text: "baseline")
        let store = FileStore()
        let baseline = try store.readSnapshot(from: fixture.url).revision
        _ = try store.write("external", to: fixture.url)

        #expect(throws: FileStoreError.self) {
            try store.write("local", to: fixture.url, expectedRevision: baseline)
        }
        #expect(try store.read(from: fixture.url).content == "external")
    }

    @Test func conditionalWriteKeepsExternalBytesWrittenBeforePublication() throws {
        let fixture = try FixtureFile(text: "baseline")
        let store = FileStore(beforePublication: { url in
            try Data("external winner".utf8).write(to: url, options: .atomic)
        })
        let loaded = try FileDocument(fileURL: fixture.url, fileStore: store).load()
        let dirty = loaded.edited(text: "ours")

        do {
            _ = try dirty.save()
            Issue.record("Expected the external writer to invalidate the conditional save")
        } catch {
            guard case .fileChangedDuringRead = error else {
                Issue.record("Expected fileChangedDuringRead, got \(error)")
                return
            }
        }
        #expect(dirty.state == .dirty)
        #expect(try String(contentsOf: fixture.url, encoding: .utf8) == "external winner")
    }

    @Test func conditionalSwapRestoresDirectWriteBetweenVerificationAndPublication() throws {
        let fixture = try FixtureFile(text: "baseline")
        let store = FileStore(afterBaselineVerification: { url in
            try Data("direct external winner".utf8).write(to: url, options: .atomic)
        })
        let dirty = try FileDocument(fileURL: fixture.url, fileStore: store)
            .load()
            .edited(text: "ours")

        do {
            _ = try dirty.save()
            Issue.record("Expected a direct writer in the publication gap to invalidate the save")
        } catch {
            guard case .fileChangedDuringRead = error else {
                Issue.record("Expected fileChangedDuringRead, got \(error)")
                return
            }
        }

        #expect(dirty.state == .dirty)
        #expect(try String(contentsOf: fixture.url, encoding: .utf8) == "direct external winner")
    }

    @Test func cooperatingWriterCannotPublishInsideTheBaselineToReplaceBoundary() throws {
        let fixture = try FixtureFile(text: "baseline")
        let url = fixture.url
        let baseline = try FileStore().readSnapshot(from: url).revision
        let verified = DispatchSemaphore(value: 0)
        let writerQueued = DispatchSemaphore(value: 0)
        let permitReplacement = DispatchSemaphore(value: 0)
        let local = FileStore(afterBaselineVerification: { _ in
            verified.signal()
            _ = writerQueued.wait(timeout: .now() + 1)
            _ = permitReplacement.wait(timeout: .now() + 1)
        })

        let results = FileStoreTestErrors()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            defer { group.leave() }
            do {
                _ = try local.write("local", to: url, expectedRevision: baseline)
            } catch {
                results.local = error
            }
        }
        #expect(verified.wait(timeout: .now() + 1) == .success)
        group.enter()
        DispatchQueue.global().async {
            defer { group.leave() }
            writerQueued.signal()
            do {
                _ = try FileStore().write("external", to: url)
            } catch {
                results.external = error
            }
        }
        permitReplacement.signal()

        #expect(group.wait(timeout: .now() + 1) == .success)
        #expect(results.local == nil)
        #expect(results.external == nil)
        #expect(try String(contentsOf: url, encoding: .utf8) == "external")
    }

    @Test func mutationGenerationRejectsAnABAConflictResolutionContext() throws {
        let fixture = try FixtureFile(text: "disk")
        let loaded = try FileDocument(fileURL: fixture.url).load()
        let first = loaded.edited(text: "local")
        let returnedText = first.edited(text: "disk")

        #expect(returnedText.text == loaded.text)
        #expect(returnedText.mutationGeneration > loaded.mutationGeneration)
    }

    @Test func recoveryRemovalWinsOverAnEarlierSameGenerationPersist() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let recovery = RecoveryBuffer(recoveryDirectory: directory)

        try await recovery.save(content: "stale", for: "document", version: 7)
        await recovery.remove(for: "document", version: 7)
        try await recovery.save(content: "stale", for: "document", version: 7)

        #expect(try await recovery.load(for: "document") == nil)
    }

    @Test func newerDocumentEpochSupersedesLateRecoveryFromPreviousLifetime() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let recovery = RecoveryBuffer(recoveryDirectory: directory)

        try await recovery.save(content: "old", for: "same-url", version: 9, epoch: 1)
        try await recovery.save(content: "reopened", for: "same-url", version: 1, epoch: 2)
        try await recovery.save(content: "late old", for: "same-url", version: 99, epoch: 1)

        #expect(try await recovery.load(for: "same-url") == "reopened")
    }

    @Test func failedRecoveryPersistCanRetryTheSameVersion() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("not a directory".utf8).write(to: directory)
        let recovery = RecoveryBuffer(recoveryDirectory: directory)

        do {
            try await recovery.save(content: "retry", for: "document", version: 7, epoch: 1)
            Issue.record("Expected persistence into a regular file to fail")
        } catch {
            // The failed write must not consume version 7.
        }
        try FileManager.default.removeItem(at: directory)
        try await recovery.save(content: "retry", for: "document", version: 7, epoch: 1)

        #expect(try await recovery.load(for: "document") == "retry")
    }

    @Test func migrationKeepsSourceWhenDestinationHasANewerEpoch() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let recovery = RecoveryBuffer(recoveryDirectory: directory)
        try await recovery.save(content: "source", for: "old", version: 1, epoch: 2)
        try await recovery.save(content: "destination", for: "new", version: 1, epoch: 3)

        let migrated = await recovery.migrate(
            from: "old",
            to: "new",
            content: "source",
            version: 2,
            sourceEpoch: 2,
            destinationEpoch: 2
        )

        #expect(!migrated)
        #expect(try await recovery.load(for: "old") == "source")
        #expect(try await recovery.load(for: "new") == "destination")
    }

    @Test func dirtyDocumentConflictsWithoutLosingLocalText() throws {
        let fixture = try FixtureFile(text: "disk")
        let store = FileStore()
        let loaded = try FileDocument(fileURL: fixture.url).load()
        let dirty = loaded.updatingText("local")
        _ = try store.write("external", to: fixture.url)

        let reconciliation = try dirty.reconcilingExternalSnapshot(store.readSnapshot(from: fixture.url))

        #expect(reconciliation.disposition == .conflicted)
        #expect(reconciliation.document.text == "local")
        #expect(reconciliation.document.state == .conflict)
        #expect(reconciliation.document.pendingExternalRevision != nil)
    }

    @Test func identicalDiskTextAcknowledgesAndCleansConflict() throws {
        let fixture = try FixtureFile(text: "disk")
        let store = FileStore()
        let loaded = try FileDocument(fileURL: fixture.url).load()
        let dirty = loaded.updatingText("local")
        _ = try store.write("external", to: fixture.url)
        let conflicted = try dirty.reconcilingExternalSnapshot(store.readSnapshot(from: fixture.url)).document
        _ = try store.write("local", to: fixture.url)

        let reconciliation = try conflicted.reconcilingExternalSnapshot(store.readSnapshot(from: fixture.url))

        #expect(reconciliation.disposition == .localNowMatchesDisk)
        #expect(reconciliation.document.state == .clean)
        #expect(reconciliation.document.pendingExternalRevision == nil)
    }

    @Test func revertingDiskToBaselineClearsConflictToDirty() throws {
        let fixture = try FixtureFile(text: "baseline")
        let store = FileStore()
        let loaded = try FileDocument(fileURL: fixture.url).load()
        let dirty = loaded.updatingText("local")
        _ = try store.write("external", to: fixture.url)
        let conflicted = try dirty.reconcilingExternalSnapshot(store.readSnapshot(from: fixture.url)).document
        _ = try store.write("baseline", to: fixture.url)

        let reconciliation = try conflicted.reconcilingExternalSnapshot(store.readSnapshot(from: fixture.url))

        #expect(reconciliation.disposition == .conflictClearedToDirty)
        #expect(reconciliation.document.state == .dirty)
        #expect(reconciliation.document.text == "local")
    }

    @Test func keepingLocalChangesAcknowledgesTheLatestDiskRevision() throws {
        let fixture = try FixtureFile(text: "disk")
        let store = FileStore()
        let loaded = try FileDocument(fileURL: fixture.url).load().updatingText("local")
        _ = try store.write("external", to: fixture.url)
        let snapshot = try store.readSnapshot(from: fixture.url)
        let conflicted = loaded.reconcilingExternalSnapshot(snapshot).document

        let kept = conflicted.keepingLocalChanges(acknowledging: snapshot.revision)
        let repeated = kept.reconcilingExternalSnapshot(snapshot)

        #expect(kept.state == .dirty)
        #expect(kept.pendingExternalRevision == nil)
        #expect(repeated.disposition == .metadataAdvanced)
    }
}

final class FixtureFile {
    let directory: URL
    let url: URL

    init(text: String? = nil) throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appendingPathComponent("document.md")
        if let text {
            _ = try FileStore().write(text, to: url)
        }
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }
}

private final class FileStoreTestErrors: @unchecked Sendable {
    private let lock = NSLock()
    private var localError: Error?
    private var externalError: Error?

    var local: Error? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return localError
        }
        set {
            lock.lock()
            localError = newValue
            lock.unlock()
        }
    }

    var external: Error? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return externalError
        }
        set {
            lock.lock()
            externalError = newValue
            lock.unlock()
        }
    }
}
