@testable import FileCore
import Foundation
import Testing

@Suite("External file reconciliation recovery and identity")
struct ExternalFileChangesRecoveryTests {
    @Test func UUIDLifetimeRecordsDoNotCollideForLegacySanitizationAliases() async throws {
        let fixture = try FixtureFile(text: "disk")
        let recovery = RecoveryBuffer(recoveryDirectory: fixture.directory.appendingPathComponent("Recovery"))
        let firstLifetime = UUID()
        let secondLifetime = UUID()

        try await recovery.save(content: "slash", for: "same/path", version: 1, epoch: firstLifetime)
        try await recovery.save(content: "colon", for: "same:path", version: 1, epoch: secondLifetime)

        #expect(try await recovery.load(for: "same/path", epoch: firstLifetime) == "slash")
        #expect(try await recovery.load(for: "same:path", epoch: secondLifetime) == "colon")
    }

    @Test func exactUUIDLifetimeWinsOverALegacyRecoveryRecord() async throws {
        let fixture = try FixtureFile(text: "disk")
        let directory = fixture.directory.appendingPathComponent("Recovery")
        let recovery = RecoveryBuffer(recoveryDirectory: directory)
        let id = "legacy/path"
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try "legacy".write(
            to: directory.appendingPathComponent("legacy_path.recovery.md"),
            atomically: true,
            encoding: .utf8
        )
        let lifetime = UUID()
        try await recovery.save(content: "current", for: id, version: 1, epoch: lifetime)

        #expect(try await recovery.load(for: id, epoch: lifetime) == "current")
        #expect(try await recovery.load(for: id) == "current")
    }

    @Test func retiringEpochADoesNotDeleteNewerEpochBRecovery() async throws {
        let fixture = try FixtureFile(text: "disk")
        let recovery = RecoveryBuffer(recoveryDirectory: fixture.directory.appendingPathComponent("Recovery"))
        let id = fixture.url.absoluteString

        try await recovery.save(content: "A", for: id, version: 1, epoch: 10)
        try await recovery.save(content: "B", for: id, version: 1, epoch: 11)
        await recovery.retire(for: id, version: 1, epoch: 10)

        #expect(try await recovery.load(for: id, epoch: 10) == nil)
        #expect(try await recovery.load(for: id, epoch: 11) == "B")
        #expect(try await recovery.load(for: id) == "B")
    }

    @Test func markerCollectionCannotAffectANewerExactLifetime() async throws {
        let fixture = try FixtureFile(text: "disk")
        let recovery = RecoveryBuffer(recoveryDirectory: fixture.directory.appendingPathComponent("Recovery"))
        let oldID = "old-lifetime"
        let retiredLifetime = UUID()
        let currentLifetime = UUID()
        try await recovery.save(content: "old", for: oldID, version: 1, epoch: retiredLifetime)
        await recovery.retire(for: oldID, version: 1, epoch: retiredLifetime)
        try await recovery.save(content: "current", for: oldID, version: 1, epoch: currentLifetime)

        for index in 0 ..< 300 {
            let id = "lifetime-\(index)"
            let lifetime = UUID()
            try await recovery.save(content: "value", for: id, version: 1, epoch: lifetime)
            await recovery.retire(for: id, version: 1, epoch: lifetime)
        }
        #expect(await recovery.retainedTombstoneCount <= 256)
        #expect(await recovery.retainedMarkerCount <= 256)

        try await recovery.save(content: "late retired", for: oldID, version: 2, epoch: retiredLifetime)
        #expect(try await recovery.load(for: oldID, epoch: currentLifetime) == "current")
    }

    @Test func retiredRecoveryLifetimesRejectLateWritesAndStayBounded() async throws {
        let fixture = try FixtureFile(text: "disk")
        let recovery = RecoveryBuffer(recoveryDirectory: fixture.directory.appendingPathComponent("Recovery"))

        // Model repeated open/edit/save/close lifetimes. Every late write uses
        // the retired epoch and must be ignored even though the URL-derived
        // recovery identifier is reused.
        for index in 0 ..< 300 {
            let document = try FileDocument(fileURL: fixture.url, recoveryBuffer: recovery)
                .load()
                .edited(text: "edit-\(index)")
            await document.saveRecovery()
            await recovery.retire(
                for: document.id,
                version: document.mutationGeneration,
                epoch: document.recoveryEpoch
            )
            try await recovery.save(
                content: "late-\(index)",
                for: document.id,
                version: document.mutationGeneration &+ 1,
                epoch: document.recoveryEpoch
            )
            #expect(try await recovery.load(for: document.id) == nil)
        }

        #expect(await recovery.retainedTombstoneCount <= 256)

        let reopened = try FileDocument(fileURL: fixture.url, recoveryBuffer: recovery)
            .load()
            .edited(text: "reopened")
        await reopened.saveRecovery()
        #expect(try await recovery.load(for: reopened.id) == "reopened")
    }

    @Test func reopenedSavedDocumentUsesNewRecoveryLifetime() async throws {
        let fixture = try FixtureFile(text: "disk")
        let recoveryDirectory = fixture.directory.appendingPathComponent("Recovery")
        let recovery = RecoveryBuffer(recoveryDirectory: recoveryDirectory)
        let first = try FileDocument(fileURL: fixture.url, recoveryBuffer: recovery).load().edited(text: "first")
        await first.saveRecovery()
        let reopened = try FileDocument(fileURL: fixture.url, recoveryBuffer: recovery).load().edited(text: "reopened")
        await reopened.saveRecovery()
        try await recovery.save(
            content: "late first",
            for: first.id,
            version: first.mutationGeneration &+ 10,
            epoch: first.recoveryEpoch
        )

        #expect(try await recovery.load(for: reopened.id) == "reopened")
    }

    @Test func matchingSnapshotDoesNotAdvanceGenerationOrReplaceTheDocument() throws {
        let fixture = try FixtureFile(text: "disk")
        let document = try FileDocument(fileURL: fixture.url).load()
        let snapshot = try FileStore().readSnapshot(from: fixture.url)

        let reconciliation = document.reconcilingExternalSnapshot(snapshot)

        #expect(reconciliation.disposition == .noChange)
        #expect(reconciliation.document.mutationGeneration == document.mutationGeneration)
        #expect(reconciliation.document.text == document.text)
        #expect(reconciliation.document.lastKnownRevision == document.lastKnownRevision)
        #expect(reconciliation.document.state == document.state)
    }

    @Test func failedRecoveryCleanupCanBeRetriedUntilTheTypedOutcomeIsAbsent() async throws {
        let fixture = try FixtureFile(text: "disk")
        let failure = FailOnce()
        let recovery = RecoveryBuffer(
            recoveryDirectory: fixture.directory.appendingPathComponent("Recovery"),
            hooks: RecoveryBufferHooks(beforeRecoveryRemoval: { _ in try failure.fail() })
        )
        let document = try FileDocument(fileURL: fixture.url, recoveryBuffer: recovery)
            .load()
            .edited(text: "draft")
        await document.saveRecovery()

        let failed = await recovery.removeWithOutcome(
            for: document.id,
            version: document.mutationGeneration,
            epoch: document.recoveryEpoch
        )
        guard case .failed = failed else {
            Issue.record("Expected the first cleanup attempt to remain retryable")
            return
        }
        #expect(try await recovery.load(for: document.id, epoch: document.recoveryEpoch) == "draft")

        let retried = await recovery.removeWithOutcome(
            for: document.id,
            version: document.mutationGeneration,
            epoch: document.recoveryEpoch
        )
        #expect(retried.isAbsent)
        #expect(try await recovery.load(for: document.id, epoch: document.recoveryEpoch) == nil)
    }

    @Test func recoveryMigrationUsesNewLifetimeAndRemovesSourceOnlyAfterPersistence() async throws {
        let fixture = try FixtureFile(text: "disk")
        let recovery = RecoveryBuffer(recoveryDirectory: fixture.directory.appendingPathComponent("Recovery"))
        let original = try FileDocument(fileURL: fixture.url, recoveryBuffer: recovery)
            .load()
            .edited(text: "local")
        await original.saveRecovery()
        let movedURL = fixture.directory.appendingPathComponent("moved.md")
        let moved = original.renamed(to: movedURL)

        #expect(moved.recoveryEpoch != original.recoveryEpoch)
        let migrated = await recovery.migrate(
            from: original.id,
            to: moved.id,
            content: moved.text,
            version: moved.mutationGeneration,
            sourceEpoch: original.recoveryEpoch,
            destinationEpoch: moved.recoveryEpoch
        )

        #expect(migrated)
        let acknowledgement = await recovery.acknowledgeMigration(
            from: original.id,
            sourceEpoch: original.recoveryEpoch,
            to: moved.id,
            destinationEpoch: moved.recoveryEpoch
        )
        #expect(acknowledgement.isAbsent)
        #expect(try await recovery.load(for: original.id) == nil)
        #expect(try await recovery.load(for: moved.id) == "local")
    }

    @Test func recoveryMigrationPersistsCapturedTextWhenSourceIsMissingOrStale() async throws {
        let fixture = try FixtureFile(text: "disk")
        let recovery = RecoveryBuffer(recoveryDirectory: fixture.directory.appendingPathComponent("Recovery"))

        let missingSource = await recovery.migrate(
            from: "missing-source",
            to: "destination",
            content: "captured current text",
            version: 3,
            sourceEpoch: 1,
            destinationEpoch: 2
        )

        #expect(missingSource)
        #expect(try await recovery.load(for: "destination") == "captured current text")

        try await recovery.save(content: "stale source", for: "stale", version: 1, epoch: 1)
        let staleSource = await recovery.migrate(
            from: "stale",
            to: "new-destination",
            content: "captured newer text",
            version: 2,
            sourceEpoch: 1,
            destinationEpoch: 2
        )

        #expect(staleSource)
        #expect(try await recovery.load(for: "new-destination") == "captured newer text")
    }

    @Test func recoveryMigrationRetriesSourceDeletionAfterDestinationWasAccepted() async throws {
        let fixture = try FixtureFile(text: "disk")
        let failure = RecoveryDeletionFailure()
        let recovery = RecoveryBuffer(
            recoveryDirectory: fixture.directory.appendingPathComponent("Recovery"),
            beforeSourceRemoval: { url in try failure.failOnce(for: url) }
        )
        try await recovery.save(content: "old", for: "old", version: 1, epoch: 1)

        let firstAttempt = await recovery.migrate(
            from: "old",
            to: "new",
            content: "captured",
            version: 2,
            sourceEpoch: 1,
            destinationEpoch: 2
        )

        #expect(!firstAttempt)
        #expect(try await recovery.load(for: "old") == "old")
        #expect(try await recovery.load(for: "new") == "captured")

        let retry = await recovery.migrate(
            from: "old",
            to: "new",
            content: "captured",
            version: 2,
            sourceEpoch: 1,
            destinationEpoch: 2
        )

        #expect(retry)
        #expect(try await recovery.load(for: "old") == nil)
        #expect(try await recovery.load(for: "new") == "captured")
    }
}

final class FailOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var remaining = 1

    func fail() throws {
        lock.lock()
        defer { lock.unlock() }
        guard remaining > 0 else { return }
        remaining -= 1
        throw POSIXError(.EIO)
    }
}

private final class RecoveryDeletionFailure: @unchecked Sendable {
    private let lock = NSLock()
    private var remainingFailures = 1

    func failOnce(for _: URL) throws {
        lock.lock()
        defer { lock.unlock() }
        guard remainingFailures > 0 else { return }
        remainingFailures -= 1
        throw POSIXError(.EACCES)
    }
}
