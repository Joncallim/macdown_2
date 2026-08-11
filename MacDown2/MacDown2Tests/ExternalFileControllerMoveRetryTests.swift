import EditorCore
import FileCore
import Foundation
@testable import MacDown2
import Testing
import Workspace

@MainActor
struct ExternalFileControllerMoveRetryTests {
    @Test func editedDocumentRejectsStaleMoveRetryAndRestoresSourceRecovery() async throws {
        let directory = try moveRetryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let sourceURL = directory.appendingPathComponent("source.md"),
            destinationURL = directory.appendingPathComponent("destination.md")
        try "disk".write(to: sourceURL, atomically: true, encoding: .utf8)

        let recovery = RecoveryBuffer(recoveryDirectory: directory.appendingPathComponent("Recovery"))
        let source = try FileDocument(fileURL: sourceURL, recoveryBuffer: recovery)
            .load()
            .updatingText("draft before failed move")
        #expect(await source.persistRecovery())

        let sessions = WorkspaceSessionStore(fileURL: directory.appendingPathComponent("session.json"))
        let store = TabStore(sessionStore: sessions, recoveryBuffer: recovery)
        store.newTab(document: source)
        let model = WorkspaceModel(tabStore: store)
        let executor = FailFirstMoveMigrationExecutor()
        let controller = ExternalFileController(
            model: model,
            editorStore: EditorTextSystemStore(),
            identity: "stale-move-retry-test",
            recoveryExecutor: executor
        )

        try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
        let movedSnapshot = try source.fileStore.readSnapshot(from: destinationURL)
        await controller.applyMove(movedSnapshot, to: source, model: model)
        #expect(controller.recoveryRetryKind == .migrate)

        let edited = source.updatingText("edit after failed move")
        store.updateActiveDocument { _ in edited }
        controller.persistRecovery(for: edited)
        await controller.drainRecovery()
        #expect(try await recovery.load(for: source.id, epoch: source.recoveryEpoch) == edited.text)

        controller.retryRecoveryCleanup()
        await controller.drainRecovery()

        let active = try #require(model.activeDocument)
        #expect(active.id == source.id)
        #expect(active.fileURL == sourceURL.standardizedFileURL)
        #expect(active.text == edited.text)
        expectStaleMoveRetryIsCleared(controller)
        #expect(try await recovery.load(for: source.id, epoch: source.recoveryEpoch) == edited.text)

        // The Retry button has no stale migration left to replay.
        controller.retryRecoveryCleanup()
        await controller.drainRecovery()
        #expect(controller.recoveryRetryKind == nil)
        #expect(controller.notice == .unavailable(.missingOrMoved))

        await expectRestoredMoveRetrySession(
            sessions: sessions,
            recoveryDirectory: directory.appendingPathComponent("Recovery"),
            sourceURL: sourceURL,
            text: edited.text,
            store: store
        )
    }

    @Test func editDuringInitialMoveMigrationRotatesAndPersistsTheCurrentLifetime() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let sourceURL = directory.appendingPathComponent("source.md")
        let destinationURL = directory.appendingPathComponent("destination.md")
        try "disk".write(to: sourceURL, atomically: true, encoding: .utf8)

        let recovery = RecoveryBuffer(recoveryDirectory: directory.appendingPathComponent("Recovery"))
        let source = try FileDocument(fileURL: sourceURL, recoveryBuffer: recovery)
            .load()
            .updatingText("draft before move")
        #expect(await source.persistRecovery())

        let sessions = WorkspaceSessionStore(fileURL: directory.appendingPathComponent("session.json"))
        let store = TabStore(sessionStore: sessions, recoveryBuffer: recovery)
        store.newTab(document: source)
        let model = WorkspaceModel(tabStore: store)
        let controller = ExternalFileController(
            model: model,
            editorStore: EditorTextSystemStore(),
            identity: "initial-move-race-test"
        )
        controller.onInitialMoveRecoveryPrepared = {
            model.tabStore.updateActiveDocument { $0.updatingText("edit during initial move") }
        }

        try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
        let snapshot = try source.fileStore.readSnapshot(from: destinationURL)
        await controller.applyMove(snapshot, to: source, model: model)

        let current = try #require(model.activeDocument)
        #expect(current.id == source.id)
        #expect(current.fileURL == sourceURL.standardizedFileURL)
        #expect(current.recoveryEpoch != source.recoveryEpoch)
        #expect(current.text == "edit during initial move")
        #expect(try await recovery.load(for: current.id, epoch: current.recoveryEpoch) == current.text)
        #expect(try await recovery.load(for: source.id, epoch: source.recoveryEpoch) != current.text)

        #expect(await store.saveSession())
        let restored = TabStore(sessionStore: sessions, recoveryBuffer: RecoveryBuffer(
            recoveryDirectory: directory.appendingPathComponent("Recovery")
        ))
        await restored.restoreSessionIfNeeded()
        #expect(restored.activeDocument?.recoveryEpoch == current.recoveryEpoch)
        #expect(restored.activeDocument?.text == current.text)
    }
}

private func moveRetryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

@MainActor
private func expectStaleMoveRetryIsCleared(_ controller: ExternalFileController) {
    #expect(controller.recoveryRetryKind == nil)
    #expect(controller.pendingMove == nil)
    #expect(controller.notice == .unavailable(.missingOrMoved))
}

@MainActor
private func expectRestoredMoveRetrySession(
    sessions: WorkspaceSessionStore,
    recoveryDirectory: URL,
    sourceURL: URL,
    text: String,
    store: TabStore
) async {
    #expect(await store.saveSession())
    let restored = TabStore(
        sessionStore: sessions,
        recoveryBuffer: RecoveryBuffer(recoveryDirectory: recoveryDirectory)
    )
    await restored.restoreSessionIfNeeded()
    #expect(restored.activeDocument?.fileURL == sourceURL.standardizedFileURL)
    #expect(restored.activeDocument?.text == text)
}

actor FailFirstMoveMigrationExecutor: RecoveryActionExecuting {
    private var shouldFailMigration = true

    func persist(_ document: FileDocument) async -> Bool {
        await document.persistRecovery()
    }

    func remove(
        _ buffer: RecoveryBuffer,
        id: String,
        version: UInt,
        epoch: UUID
    ) async -> RecoveryCleanupResult {
        await buffer.removeWithOutcome(for: id, version: version, epoch: epoch)
    }

    func migrate(
        _ buffer: RecoveryBuffer,
        oldID: String,
        sourceEpoch: UUID,
        document: FileDocument
    ) async -> RecoveryMigrationOutcome {
        if shouldFailMigration {
            shouldFailMigration = false
            return .failed(.removalFailed(URL(fileURLWithPath: oldID), 5))
        }
        return await buffer.migrateWithOutcome(
            from: oldID,
            to: document.id,
            content: document.text,
            version: document.mutationGeneration,
            sourceEpoch: sourceEpoch,
            destinationEpoch: document.recoveryEpoch
        )
    }

    func retire(_ buffer: RecoveryBuffer, id: String, epoch: UUID) async -> RecoveryCleanupResult {
        await buffer.retireWithOutcome(for: id, epoch: epoch)
    }
}
