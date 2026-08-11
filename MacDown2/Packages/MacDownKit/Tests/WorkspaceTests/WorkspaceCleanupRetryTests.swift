@testable import FileCore
import Foundation
import Testing
@testable import Workspace

@MainActor
struct WorkspaceCleanupRetryTests {
    @Test func ordinarySaveCleanupRetryClearsItsExactAction() async throws {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let failure = FailOnceCleanup()
        let recovery = RecoveryBuffer(
            recoveryDirectory: directory.appendingPathComponent("Recovery"),
            hooks: RecoveryBufferHooks(beforeRecoveryRemoval: { _ in try failure.fail() })
        )
        let url = directory.appendingPathComponent("notes.md")
        try "disk".write(to: url, atomically: true, encoding: .utf8)
        let document = try FileDocument(fileURL: url, recoveryBuffer: recovery).load().updatingText("draft")
        #expect(await document.persistRecovery())
        let store = TabStore(sessionStore: FakeSessionStore(), recoveryBuffer: recovery)
        store.newTab(document: document)
        let model = WorkspaceModel(tabStore: store, stateStore: FakeStateStore())

        await model.save()
        #expect(model.hasPendingRecoveryCleanup)
        #expect(model.lastError != nil)
        await model.retryRecoveryCleanup()
        #expect(!model.hasPendingRecoveryCleanup)
        #expect(model.lastError == nil)
    }

    @Test func saveAsDestinationCleanupRetryClearsItsExactAction() async throws {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let failure = FailOnceCleanup()
        let recovery = RecoveryBuffer(
            recoveryDirectory: directory.appendingPathComponent("Recovery"),
            hooks: RecoveryBufferHooks(beforeRecoveryRemoval: { _ in try failure.fail() })
        )
        let sourceURL = directory.appendingPathComponent("source.md")
        let destinationURL = directory.appendingPathComponent("destination.md")
        try "disk".write(to: sourceURL, atomically: true, encoding: .utf8)
        let document = try FileDocument(fileURL: sourceURL, recoveryBuffer: recovery).load().updatingText("draft")
        let panel = FakeFilePanelProvider()
        panel.nextSaveURL = destinationURL
        let store = TabStore(sessionStore: FakeSessionStore(), recoveryBuffer: recovery)
        store.newTab(document: document)
        let model = WorkspaceModel(tabStore: store, stateStore: FakeStateStore(), panel: panel)

        await model.saveAs()
        #expect(model.hasPendingRecoveryCleanup)
        #expect(model.lastError != nil)
        await model.retryRecoveryCleanup()
        #expect(!model.hasPendingRecoveryCleanup)
        #expect(model.lastError == nil)
    }

    @Test func closeRetirementFailureRotatesEditedDocumentBeforeRetryAndRestoresIt() async throws {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let failure = FailOnceRetiredMarker()
        let recoveryDirectory = directory.appendingPathComponent("Recovery")
        let recovery = RecoveryBuffer(
            recoveryDirectory: recoveryDirectory,
            hooks: RecoveryBufferHooks(beforeMarkerWrite: { url in try failure.fail(for: url) })
        )
        let document = FileDocument(recoveryBuffer: recovery).updatingText("draft")
        #expect(await document.persistRecovery())
        let sessions = FakeSessionStore()
        let store = TabStore(sessionStore: sessions, recoveryBuffer: recovery)
        store.newTab(document: document)
        let model = WorkspaceModel(tabStore: store, stateStore: FakeStateStore())

        model.requestCloseDocument()
        await model.resolveClose(.discard)
        #expect(model.hasPendingRecoveryCleanup)
        let rotated = try #require(model.activeDocument)
        #expect(rotated.recoveryEpoch != document.recoveryEpoch)
        #expect(RecoveryLifetimeEpoch.generation(for: rotated.recoveryEpoch.uuidString.lowercased()) != nil)
        #expect(try await recovery.load(for: rotated.id, epoch: rotated.recoveryEpoch) == "draft")

        model.tabStore.updateActiveDocument { $0.updatingText("edited after close failure") }
        #expect(await model.tabStore.saveSession())
        await model.retryRecoveryCleanup()
        #expect(!model.hasPendingRecoveryCleanup)
        #expect(model.lastError == nil)

        let restartedRecovery = RecoveryBuffer(recoveryDirectory: recoveryDirectory)
        let restored = TabStore(sessionStore: sessions, recoveryBuffer: restartedRecovery)
        await restored.restoreSessionIfNeeded()
        #expect(restored.activeDocument?.text == "edited after close failure")
    }

    @Test func persistRetryRetainsItsExactActionUntilTheCapturedWriteSucceeds() async throws {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let failure = FailOnceCleanup()
        let recovery = RecoveryBuffer(
            recoveryDirectory: directory.appendingPathComponent("Recovery"),
            hooks: RecoveryBufferHooks(beforeMarkerWrite: { _ in try failure.fail() })
        )
        let document = FileDocument(recoveryBuffer: recovery).updatingText("retry persisted text")
        let store = TabStore(sessionStore: FakeSessionStore(), recoveryBuffer: recovery)
        store.newTab(document: document)
        let model = WorkspaceModel(tabStore: store, stateStore: FakeStateStore())
        model.pendingRecoveryCleanupActions.insert(.persist(for: document))

        await model.retryRecoveryCleanup()
        #expect(model.hasPendingRecoveryCleanup)
        #expect(model.lastError != nil)

        await model.retryRecoveryCleanup()
        #expect(!model.hasPendingRecoveryCleanup)
        #expect(try await recovery.load(for: document.id, epoch: document.recoveryEpoch) == "retry persisted text")
    }

    @Test func migrationRetryRetainsItsExactActionUntilTheCapturedMigrationSucceeds() async throws {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let failure = FailOnceCleanup()
        let recovery = RecoveryBuffer(
            recoveryDirectory: directory.appendingPathComponent("Recovery"),
            hooks: RecoveryBufferHooks(beforeSourceRemoval: { _ in try failure.fail() })
        )
        let sourceURL = directory.appendingPathComponent("source.md")
        let destinationURL = directory.appendingPathComponent("destination.md")
        let source = FileDocument(fileURL: sourceURL, recoveryBuffer: recovery).updatingText("source draft")
        let destination = FileDocument(fileURL: destinationURL, recoveryBuffer: recovery).updatingText("migrated draft")
        #expect(await source.persistRecovery())
        let store = TabStore(sessionStore: FakeSessionStore(), recoveryBuffer: recovery)
        store.newTab(document: source)
        let model = WorkspaceModel(tabStore: store, stateStore: FakeStateStore())
        model.pendingRecoveryCleanupActions.insert(.migrate(source: source, destination: destination))

        await model.retryRecoveryCleanup()
        #expect(model.hasPendingRecoveryCleanup)
        #expect(model.lastError != nil)

        await model.retryRecoveryCleanup()
        #expect(!model.hasPendingRecoveryCleanup)
        #expect(try await recovery.load(for: destination.id, epoch: destination.recoveryEpoch) == "migrated draft")
    }

    @Test func acknowledgementRetryRetainsItsExactActionUntilTheCapturedAcknowledgementSucceeds() async throws {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let recoveryDirectory = directory.appendingPathComponent("Recovery")
        let seed = RecoveryBuffer(recoveryDirectory: recoveryDirectory)
        let sourceURL = directory.appendingPathComponent("source.md")
        let destinationURL = directory.appendingPathComponent("destination.md")
        let source = FileDocument(fileURL: sourceURL, recoveryBuffer: seed).updatingText("source draft")
        let destination = FileDocument(fileURL: destinationURL, recoveryBuffer: seed).updatingText("destination draft")
        #expect(await source.persistRecovery())
        #expect(await seed.migrateWithOutcome(
            from: source.id,
            to: destination.id,
            content: destination.text,
            version: destination.mutationGeneration,
            sourceEpoch: source.recoveryEpoch,
            destinationEpoch: destination.recoveryEpoch
        ).isComplete)

        let failure = FailOnceCleanup()
        let recovery = RecoveryBuffer(
            recoveryDirectory: recoveryDirectory,
            hooks: RecoveryBufferHooks(beforeMarkerWrite: { _ in try failure.fail() })
        )
        let retrySource = FileDocument(
            fileURL: sourceURL,
            recoveryBuffer: recovery,
            recoveryEpoch: source.recoveryEpoch
        ).updatingText(source.text)
        let retryDestination = FileDocument(
            fileURL: destinationURL,
            recoveryBuffer: recovery,
            recoveryEpoch: destination.recoveryEpoch
        ).updatingText(destination.text)
        let store = TabStore(sessionStore: FakeSessionStore(), recoveryBuffer: recovery)
        store.newTab(document: retryDestination)
        let model = WorkspaceModel(tabStore: store, stateStore: FakeStateStore())
        model.pendingRecoveryCleanupActions.insert(
            .acknowledgeMigration(source: retrySource, destination: retryDestination)
        )

        await model.retryRecoveryCleanup()
        #expect(model.hasPendingRecoveryCleanup)
        #expect(model.lastError != nil)

        await model.retryRecoveryCleanup()
        #expect(!model.hasPendingRecoveryCleanup)
        #expect(try await recovery.load(for: retrySource.id, epoch: retrySource.recoveryEpoch) == nil)
    }

    @Test func retryKeepsMigrationContinuationInstalledWhenSessionPublicationFails() async {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let recovery = RecoveryBuffer(recoveryDirectory: directory.appendingPathComponent("Recovery"))
        let sourceURL = directory.appendingPathComponent("source.md")
        let destinationURL = directory.appendingPathComponent("destination.md")
        let source = FileDocument(fileURL: sourceURL, recoveryBuffer: recovery).updatingText("draft")
        let destination = FileDocument(fileURL: destinationURL, recoveryBuffer: recovery).updatingText("draft")
        #expect(await source.persistRecovery())
        let store = TabStore(sessionStore: FakeSessionStore(), recoveryBuffer: recovery)
        store.newTab(document: source)
        let model = WorkspaceModel(tabStore: store, stateStore: FakeStateStore())
        let migration = PendingRecoveryCleanupAction.migrate(source: source, destination: destination)
        model.pendingRecoveryCleanupActions.insert(migration)
        model.pendingSaveAsRecoveryContinuations[migration] = SaveAsRecoveryContinuation(
            source: source,
            replacement: destination,
            context: SaveContext(documentID: source.id, generation: 1),
            phase: .publishDestination
        )
        let publication = SessionPublicationGate()
        model.saveAsSessionPublisher = { publication.allowsPublication }

        await model.retryRecoveryCleanup()
        #expect(model.hasPendingRecoveryCleanup)
        #expect(model.lastError != nil)
        #expect(model.pendingSaveAsRecoveryContinuations.count == 1)

        publication.allowsPublication = true
        await model.retryRecoveryCleanup()
        #expect(!model.hasPendingRecoveryCleanup)
        #expect(model.lastError == nil)
        #expect(model.activeDocument?.fileURL == destinationURL.standardizedFileURL)
    }

    @Test func editedSaveAsRetryRekeysRedirectBeforeTheNextPublication() async throws {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let recoveryDirectory = directory.appendingPathComponent("Recovery")
        let recovery = RecoveryBuffer(recoveryDirectory: recoveryDirectory)
        let sourceURL = directory.appendingPathComponent("source.md")
        let destinationURL = directory.appendingPathComponent("destination.md")
        let source = FileDocument(fileURL: sourceURL, recoveryBuffer: recovery).updatingText("draft")
        let destination = FileDocument(fileURL: destinationURL, recoveryBuffer: recovery).updatingText("draft")
        #expect(await source.persistRecovery())
        let sessions = FakeSessionStore()
        let store = TabStore(sessionStore: sessions, recoveryBuffer: recovery)
        store.newTab(document: source)
        let model = WorkspaceModel(tabStore: store, stateStore: FakeStateStore())
        let publication = SessionPublicationGate()
        model.saveAsSessionPublisher = {
            guard publication.allowsPublication else { return false }
            return await store.saveSession()
        }
        let migration = PendingRecoveryCleanupAction.migrate(source: source, destination: destination)
        model.pendingRecoveryCleanupActions.insert(migration)
        model.pendingSaveAsRecoveryContinuations[migration] = SaveAsRecoveryContinuation(
            source: source,
            replacement: destination,
            context: SaveContext(documentID: source.id, generation: 1),
            phase: .publishDestination
        )

        await model.retryRecoveryCleanup()
        #expect(model.hasPendingRecoveryCleanup)
        model.tabStore.updateActiveDocument { $0.updatingText("edited after failed publication") }
        publication.allowsPublication = true
        await model.retryRecoveryCleanup()

        #expect(model.hasPendingRecoveryCleanup)
        let relaunched = RecoveryBuffer(recoveryDirectory: recoveryDirectory)
        #expect(try await relaunched
            .load(for: source.id, epoch: source.recoveryEpoch) == "edited after failed publication")
    }
}

private final class FailOnceCleanup: @unchecked Sendable {
    private let lock = NSLock()
    private var didFail = false

    func fail() throws {
        lock.lock()
        defer { lock.unlock() }
        guard !didFail else { return }
        didFail = true
        throw CocoaError(.fileWriteNoPermission)
    }
}

@MainActor
private final class SessionPublicationGate {
    var allowsPublication = false
}

private final class FailOnceRetiredMarker: @unchecked Sendable {
    private let lock = NSLock()
    private var didFail = false

    func fail(for url: URL) throws {
        guard url.pathExtension == "retired" else { return }
        lock.lock()
        defer { lock.unlock() }
        guard !didFail else { return }
        didFail = true
        throw CocoaError(.fileWriteNoPermission)
    }
}
