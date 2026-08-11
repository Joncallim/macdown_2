@testable import FileCore
import Foundation
import Testing
@testable import Workspace

@MainActor
@Test func sessionKeepsLastGoodPublicationWhenDirtyRecoveryCannotBeVerified() async {
    let directory = temporaryDirectory()
    defer { cleanup(directory) }
    let failure = RecoveryWriteFailure()
    let recovery = RecoveryBuffer(
        recoveryDirectory: directory.appendingPathComponent("Recovery"),
        hooks: RecoveryBufferHooks(beforeMarkerWrite: { _ in try failure.fail() })
    )
    let sessions = FakeSessionStore()
    let original = WorkspaceSession(tabs: [TabRecord(id: UUID())])
    sessions.saveSession(original)
    let store = TabStore(sessionStore: sessions, recoveryBuffer: recovery)
    store.newTab()
    store.updateActiveDocument { $0.updatingText("draft") }

    #expect(await !(store.saveSession()))

    #expect(sessions.savedSession == original)
    #expect(store.lastPublishedSession == nil)
}

@MainActor
@Test func dirtyRenameRetainsOldIdentityWhenRecoveryMigrationCannotRetireSource() async throws {
    let directory = temporaryDirectory()
    defer { cleanup(directory) }
    let failure = RecoveryWriteFailure()
    let recovery = RecoveryBuffer(
        recoveryDirectory: directory.appendingPathComponent("Recovery"),
        hooks: RecoveryBufferHooks(beforeRecoveryRemoval: { _ in try failure.fail() })
    )
    let oldURL = directory.appendingPathComponent("old.md")
    let newURL = directory.appendingPathComponent("new.md")
    let document = FileDocument(fileURL: oldURL, recoveryBuffer: recovery).updatingText("draft")
    await document.saveRecovery()
    let sessions = FakeSessionStore()
    let store = TabStore(sessionStore: sessions, recoveryBuffer: recovery)
    store.newTab(document: document)

    #expect(await !(store.documentWasRenamed(from: oldURL, to: newURL)))
    #expect(store.activeDocument?.fileURL == oldURL.standardizedFileURL)
    #expect(try await recovery.load(for: document.id, epoch: document.recoveryEpoch) == "draft")
}

@MainActor
@Test func dirtyRenameUsesTheCoordinatorSessionPublicationBoundaryBeforeAcknowledgement() async throws {
    let directory = temporaryDirectory()
    defer { cleanup(directory) }
    let recovery = RecoveryBuffer(recoveryDirectory: directory.appendingPathComponent("Recovery"))
    let oldURL = directory.appendingPathComponent("old.md")
    let newURL = directory.appendingPathComponent("new.md")
    let document = FileDocument(fileURL: oldURL, recoveryBuffer: recovery).updatingText("draft")
    #expect(await document.persistRecovery())
    let store = TabStore(sessionStore: FakeSessionStore(), recoveryBuffer: recovery)
    store.newTab(document: document)
    var attempted = false
    store.setRenameSessionPublisher {
        attempted = true
        return false
    }

    #expect(await !store.documentWasRenamed(from: oldURL, to: newURL))
    #expect(attempted)
    #expect(store.activeDocument?.fileURL == newURL.standardizedFileURL)
    #expect(try await recovery.load(for: document.id, epoch: document.recoveryEpoch) == "draft")
}

@Test func migrationRetiresSourceLifetimeBeforeReportingSuccess() async throws {
    let directory = temporaryDirectory()
    defer { cleanup(directory) }
    let recovery = RecoveryBuffer(recoveryDirectory: directory.appendingPathComponent("Recovery"))
    let source = RecoveryLifetimeEpoch.make()
    let destination = RecoveryLifetimeEpoch.make()
    try await recovery.save(content: "old", for: "source", version: 1, epoch: source)

    let outcome = await recovery.migrateWithOutcome(
        from: "source",
        to: "destination",
        content: "captured text",
        version: 2,
        sourceEpoch: source,
        destinationEpoch: destination
    )

    #expect(outcome.isComplete)
    // Until the caller commits a session containing the destination identity,
    // the old session identity must follow this durable redirect on relaunch.
    let beforeAcknowledgement = RecoveryBuffer(recoveryDirectory: directory.appendingPathComponent("Recovery"))
    #expect(try await beforeAcknowledgement.load(for: "source", epoch: source) == "captured text")
    #expect(try await !(recovery.saveCurrentLifetime(
        content: "late",
        for: "source",
        version: 3,
        epoch: source
    )))
    #expect(try await recovery.load(for: "destination", epoch: destination) == "captured text")
    #expect(await recovery.acknowledgeMigration(
        from: "source",
        sourceEpoch: source,
        to: "destination",
        destinationEpoch: destination
    ).isAbsent)
    let afterAcknowledgement = RecoveryBuffer(recoveryDirectory: directory.appendingPathComponent("Recovery"))
    #expect(try await afterAcknowledgement.load(for: "source", epoch: source) == nil)
}

@MainActor
@Test func batchRenameRollsBackCompletedRecoveryMigrationsOnLaterFailure() async throws {
    let directory = temporaryDirectory()
    defer { cleanup(directory) }
    let failure = FailOnSourceRemoval(invocation: 2)
    let recovery = RecoveryBuffer(
        recoveryDirectory: directory.appendingPathComponent("Recovery"),
        hooks: RecoveryBufferHooks(beforeRecoveryRemoval: { _ in try failure.check() })
    )
    let sessions = FakeSessionStore()
    let store = TabStore(sessionStore: sessions, recoveryBuffer: recovery)
    let oldFolder = directory.appendingPathComponent("old", isDirectory: true)
    let newFolder = directory.appendingPathComponent("new", isDirectory: true)
    let first = FileDocument(
        fileURL: oldFolder.appendingPathComponent("first.md"),
        recoveryBuffer: recovery
    )
    .updatingText("first draft")
    let second = FileDocument(
        fileURL: oldFolder.appendingPathComponent("second.md"),
        recoveryBuffer: recovery
    )
    .updatingText("second draft")
    await first.saveRecovery()
    await second.saveRecovery()
    store.newTab(document: first)
    store.newTab(document: second)

    #expect(await !(store.documentWasRenamed(from: oldFolder, to: newFolder)))
    #expect(store.tabs.map { $0.document.fileURL?.deletingLastPathComponent() } == [oldFolder, oldFolder])
    #expect(store.tabs.map(\.document.id) == [first.id, second.id])
    let restoredFirst = try #require(store.tabs.first?.document)
    let restoredSecond = try #require(store.tabs.last?.document)
    #expect(try await recovery.load(for: restoredFirst.id, epoch: restoredFirst.recoveryEpoch) == "first draft")
    #expect(try await recovery.load(for: restoredSecond.id, epoch: restoredSecond.recoveryEpoch) == "second draft")

    let restoredStore = TabStore(sessionStore: sessions, recoveryBuffer: recovery)
    await restoredStore.restoreSessionIfNeeded()
    #expect(restoredStore.tabs.map { $0.document.fileURL?.deletingLastPathComponent() } == [oldFolder, oldFolder])
    #expect(restoredStore.tabs.map(\.document.text) == ["first draft", "second draft"])
}

@MainActor
@Test func batchRenamePublishesForwardRecoveryWhenReverseMigrationAlsoFails() async {
    let directory = temporaryDirectory()
    defer { cleanup(directory) }
    let failure = FailOnSourceRemoval(invocations: [2, 3])
    let recovery = RecoveryBuffer(
        recoveryDirectory: directory.appendingPathComponent("Recovery"),
        hooks: RecoveryBufferHooks(beforeRecoveryRemoval: { _ in try failure.check() })
    )
    let sessions = FakeSessionStore()
    let store = TabStore(sessionStore: sessions, recoveryBuffer: recovery)
    let oldFolder = directory.appendingPathComponent("old", isDirectory: true)
    let newFolder = directory.appendingPathComponent("new", isDirectory: true)
    let first = FileDocument(
        fileURL: oldFolder.appendingPathComponent("first.md"),
        recoveryBuffer: recovery
    )
    .updatingText("first draft")
    let second = FileDocument(
        fileURL: oldFolder.appendingPathComponent("second.md"),
        recoveryBuffer: recovery
    )
    .updatingText("second draft")
    await first.saveRecovery()
    await second.saveRecovery()
    store.newTab(document: first)
    store.newTab(document: second)

    #expect(await !(store.documentWasRenamed(from: oldFolder, to: newFolder)))
    #expect(store.tabs.map { $0.document.fileURL?.deletingLastPathComponent() } == [newFolder, oldFolder])
    #expect(store.tabs.map(\.document.text) == ["first draft", "second draft"])

    let restoredStore = TabStore(sessionStore: sessions, recoveryBuffer: recovery)
    await restoredStore.restoreSessionIfNeeded()
    #expect(restoredStore.tabs.map { $0.document.fileURL?.deletingLastPathComponent() } == [newFolder, oldFolder])
    #expect(restoredStore.tabs.map(\.document.text) == ["first draft", "second draft"])
}

@MainActor
@Test func batchRenameRetainsSuccessfulRollbacksWhenALaterReverseFails() async {
    let directory = temporaryDirectory()
    defer { cleanup(directory) }
    // The third forward migration fails. Reversing the second succeeds, then
    // reversing the first fails. This is deliberately a three-descendant
    // batch so the mixed result cannot be hidden by all-forward publication.
    let failure = FailOnSourceRemoval(invocations: [3, 5])
    let recovery = RecoveryBuffer(
        recoveryDirectory: directory.appendingPathComponent("Recovery"),
        hooks: RecoveryBufferHooks(beforeRecoveryRemoval: { _ in try failure.check() })
    )
    let sessions = FakeSessionStore()
    let store = TabStore(sessionStore: sessions, recoveryBuffer: recovery)
    let oldFolder = directory.appendingPathComponent("old", isDirectory: true)
    let newFolder = directory.appendingPathComponent("new", isDirectory: true)
    let documents = ["first", "second", "third"].map { name in
        FileDocument(
            fileURL: oldFolder.appendingPathComponent("\(name).md"),
            recoveryBuffer: recovery
        )
        .updatingText("\(name) draft")
    }
    for document in documents {
        await document.saveRecovery()
        store.newTab(document: document)
    }

    #expect(await !(store.documentWasRenamed(from: oldFolder, to: newFolder)))
    #expect(store.tabs.map { $0.document.fileURL?.deletingLastPathComponent() } == [
        newFolder, oldFolder, oldFolder,
    ])
    #expect(store.tabs.map(\.document.text) == ["first draft", "second draft", "third draft"])

    let restored = TabStore(sessionStore: sessions, recoveryBuffer: recovery)
    await restored.restoreSessionIfNeeded()
    #expect(restored.tabs.map { $0.document.fileURL?.deletingLastPathComponent() } == [
        newFolder, oldFolder, oldFolder,
    ])
    #expect(restored.tabs.map(\.document.text) == ["first draft", "second draft", "third draft"])
}

private final class RecoveryWriteFailure: @unchecked Sendable {
    private let lock = NSLock()
    private var shouldFail = true

    func fail() throws {
        lock.lock()
        defer { lock.unlock() }
        guard shouldFail else { return }
        shouldFail = false
        throw POSIXError(.EACCES)
    }
}

private final class FailOnSourceRemoval: @unchecked Sendable {
    private let lock = NSLock()
    private let failingInvocations: Set<Int>
    private var invocation = 0

    init(invocation: Int) {
        failingInvocations = [invocation]
    }

    init(invocations: Set<Int>) {
        failingInvocations = invocations
    }

    func check() throws {
        lock.lock()
        defer { lock.unlock() }
        invocation += 1
        guard failingInvocations.contains(invocation) else { return }
        throw POSIXError(.EACCES)
    }
}
