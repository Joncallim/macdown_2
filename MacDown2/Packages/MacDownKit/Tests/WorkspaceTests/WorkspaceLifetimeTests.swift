@testable import FileCore
import Foundation
import Testing
@testable import Workspace

@MainActor
@Suite("Workspace managed recovery lifetimes")
struct WorkspaceLifetimeTests {
    @Test func repeatedManagedNewCloseAndRenameCyclesKeepRecoveryMarkersBounded() async throws {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let recovery = RecoveryBuffer(recoveryDirectory: directory.appendingPathComponent("Recovery"))
        let store = TabStore(sessionStore: FakeSessionStore(), recoveryBuffer: recovery)
        let model = WorkspaceModel(tabStore: store, stateStore: FakeStateStore())

        for index in 0 ..< RecoveryBuffer.markerLimit + 8 {
            await model.newManagedDocument()
            guard let document = model.activeDocument else {
                Issue.record("Expected managed document \(index)")
                return
            }
            #expect(RecoveryLifetimeEpoch.generation(for: document.recoveryEpoch.uuidString.lowercased()) != nil)
            model.tabStore.updateActiveDocument { $0.updatingText("draft \(index)") }
            guard let dirty = model.activeDocument else {
                Issue.record("Expected dirty document \(index)")
                return
            }
            #expect(await dirty.persistRecovery())
            model.requestCloseDocument()
            await model.resolveClose(.discard)
            #expect(model.activeDocument == nil)
        }
        #expect(await recovery.retainedMarkerCount <= RecoveryBuffer.markerLimit)

        let firstURL = directory.appendingPathComponent("first.md")
        let secondURL = directory.appendingPathComponent("second.md")
        let thirdURL = directory.appendingPathComponent("third.md")
        try "disk".write(to: firstURL, atomically: true, encoding: .utf8)
        let first = try await FileDocument.create(fileURL: firstURL, recoveryBuffer: recovery)
        let dirty = try first.load().updatingText("rename draft")
        #expect(await dirty.persistRecovery())
        store.newTab(document: dirty)

        #expect(await store.documentWasRenamed(from: firstURL, to: secondURL))
        let second = try #require(store.activeDocument)
        #expect(RecoveryLifetimeEpoch.generation(for: second.recoveryEpoch.uuidString.lowercased()) != nil)
        model.tabStore.updateActiveDocument { $0.updatingText("rename draft 2") }
        #expect(await store.documentWasRenamed(from: secondURL, to: thirdURL))
        let third = try #require(store.activeDocument)
        #expect(RecoveryLifetimeEpoch.generation(for: third.recoveryEpoch.uuidString.lowercased()) != nil)
        #expect(await recovery.retainedMarkerCount <= RecoveryBuffer.markerLimit)
    }

    @Test func dirtySaveAsRedirectRestoresBeforeAcknowledgementAndExpiresAfterSessionPublication() async throws {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let sourceURL = directory.appendingPathComponent("source.md")
        let destinationURL = directory.appendingPathComponent("destination.md")
        try "disk".write(to: sourceURL, atomically: true, encoding: .utf8)

        let recoveryDirectory = directory.appendingPathComponent("Recovery")
        let recovery = RecoveryBuffer(recoveryDirectory: recoveryDirectory)
        let barrier = SavePublicationBarrier()
        let fileStore = FileStore(afterBaselineVerification: { _ in barrier.arriveAndWait() })
        let initial = try await FileDocument.create(
            fileURL: sourceURL,
            fileStore: fileStore,
            recoveryBuffer: recovery
        )
        let document = try initial.load().updatingText("published")
        #expect(await document.persistRecovery())

        let panel = FakeFilePanelProvider()
        panel.nextSaveURL = destinationURL
        let sessions = FakeSessionStore()
        let store = TabStore(sessionStore: sessions, recoveryBuffer: recovery)
        store.newTab(document: document)
        let model = WorkspaceModel(tabStore: store, stateStore: FakeStateStore(), panel: panel)
        let probe = RedirectProbe()
        model.onSaveAsDestinationSessionPublished = { source, destination in
            let restarted = RecoveryBuffer(recoveryDirectory: recoveryDirectory)
            probe.sourceRecovery = try? await restarted.load(for: source.id, epoch: source.recoveryEpoch)
            probe.destinationRecovery = try? await restarted.load(for: destination.id, epoch: destination.recoveryEpoch)
        }

        let saveAs = Task { @MainActor in await model.saveAs() }
        _ = await barrier.waitForFirstPublication()
        model.tabStore.updateActiveDocument { $0.updatingText("edited after publication") }
        barrier.allowPublication()
        await saveAs.value

        let replacement = try #require(model.activeDocument)
        #expect(RecoveryLifetimeEpoch.generation(for: replacement.recoveryEpoch.uuidString.lowercased()) != nil)
        #expect(probe.sourceRecovery == "edited after publication")
        #expect(probe.destinationRecovery == "edited after publication")

        let afterAcknowledgement = RecoveryBuffer(recoveryDirectory: recoveryDirectory)
        #expect(try await afterAcknowledgement.load(for: document.id, epoch: document.recoveryEpoch) == nil)
        #expect(try await afterAcknowledgement.load(for: replacement.id, epoch: replacement.recoveryEpoch)
            == "edited after publication")

        let restored = TabStore(sessionStore: sessions, recoveryBuffer: afterAcknowledgement)
        await restored.restoreSessionIfNeeded()
        #expect(restored.activeDocument?.fileURL == destinationURL.standardizedFileURL)
        #expect(restored.activeDocument?.text == "edited after publication")
    }

    @Test func saveAsPreservesAnEditThatArrivesDuringRecoveryFinalization() async throws {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let sourceURL = directory.appendingPathComponent("source.md")
        let destinationURL = directory.appendingPathComponent("destination.md")
        try "disk".write(to: sourceURL, atomically: true, encoding: .utf8)

        let recovery = RecoveryBuffer(recoveryDirectory: directory.appendingPathComponent("Recovery"))
        let initial = try await FileDocument.create(fileURL: sourceURL, recoveryBuffer: recovery)
        let document = try initial.load().updatingText("published text")
        let panel = FakeFilePanelProvider()
        panel.nextSaveURL = destinationURL
        let sessions = FakeSessionStore()
        let store = TabStore(sessionStore: sessions, recoveryBuffer: recovery)
        store.newTab(document: document)
        let model = WorkspaceModel(tabStore: store, stateStore: FakeStateStore(), panel: panel)

        model.onSaveAsRecoveryFinalized = {
            model.tabStore.updateActiveDocument { $0.updatingText("edit during finalization") }
        }

        await model.saveAs()

        let current = try #require(model.activeDocument)
        #expect(current.fileURL == destinationURL.standardizedFileURL)
        #expect(current.text == "edit during finalization")
        #expect(current.state == .dirty)
        #expect(try FileStore().read(from: destinationURL).content == "published text")
        #expect(try await recovery.load(for: current.id, epoch: current.recoveryEpoch)
            == "edit during finalization")

        let restored = TabStore(sessionStore: sessions, recoveryBuffer: recovery)
        await restored.restoreSessionIfNeeded()
        #expect(restored.activeDocument?.fileURL == destinationURL.standardizedFileURL)
        #expect(restored.activeDocument?.text == "edit during finalization")
    }

    @Test func repeatedDirtySaveAsRetiresFormerLifetimesAcrossRestart() async throws {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let recoveryDirectory = directory.appendingPathComponent("Recovery")
        let recovery = RecoveryBuffer(recoveryDirectory: recoveryDirectory)
        var firstLifetime: (id: String, epoch: UUID)?

        for index in 0 ..< RecoveryBuffer.markerLimit + 8 {
            let sourceURL = directory.appendingPathComponent("source-\(index).md")
            let destinationURL = directory.appendingPathComponent("destination-\(index).md")
            try "disk".write(to: sourceURL, atomically: true, encoding: .utf8)
            let initial = try await FileDocument.create(fileURL: sourceURL, recoveryBuffer: recovery)
            let source = try initial.load().updatingText("draft \(index)")
            #expect(await source.persistRecovery())
            if index == 0 {
                firstLifetime = (source.id, source.recoveryEpoch)
            }

            let panel = FakeFilePanelProvider()
            panel.nextSaveURL = destinationURL
            let store = TabStore(sessionStore: FakeSessionStore(), recoveryBuffer: recovery)
            store.newTab(document: source)
            let model = WorkspaceModel(tabStore: store, stateStore: FakeStateStore(), panel: panel)
            await model.saveAs()

            let destination = try #require(model.activeDocument)
            #expect(destination.fileURL == destinationURL.standardizedFileURL)
            #expect(try await recovery.load(for: source.id, epoch: source.recoveryEpoch) == nil)
            #expect(try await !(recovery.saveCurrentLifetime(
                content: "late source write",
                for: source.id,
                version: source.mutationGeneration + 1,
                epoch: source.recoveryEpoch
            )))

            model.tabStore.updateActiveDocument { $0.updatingText("close \(index)") }
            model.requestCloseDocument()
            await model.resolveClose(.discard)
            #expect(model.activeDocument == nil)
        }

        let first = try #require(firstLifetime)
        let restarted = RecoveryBuffer(recoveryDirectory: recoveryDirectory)
        #expect(try await !(restarted.saveCurrentLifetime(
            content: "late after restart",
            for: first.id,
            version: 1,
            epoch: first.epoch
        )))
        #expect(await restarted.durableOwnershipCount <= RecoveryBuffer.markerLimit)
    }

    @Test func saveAsRetirementFailureRemainsRetryableAcrossAnotherSaveAs() async throws {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let failure = FailFirstRetiredMarker()
        let recovery = RecoveryBuffer(
            recoveryDirectory: directory.appendingPathComponent("Recovery"),
            hooks: RecoveryBufferHooks(beforeMarkerWrite: { url in try failure.failOnce(for: url) })
        )
        let sessions = FakeSessionStore()
        let panel = FakeFilePanelProvider()
        let sourceURL = directory.appendingPathComponent("source.md")
        let firstDestination = directory.appendingPathComponent("first.md")
        let secondDestination = directory.appendingPathComponent("second.md")
        try "disk".write(to: sourceURL, atomically: true, encoding: .utf8)
        let initial = try await FileDocument.create(fileURL: sourceURL, recoveryBuffer: recovery)
        let source = try initial.load().updatingText("first draft")
        #expect(await source.persistRecovery())
        let store = TabStore(sessionStore: sessions, recoveryBuffer: recovery)
        store.newTab(document: source)
        let model = WorkspaceModel(tabStore: store, stateStore: FakeStateStore(), panel: panel)

        panel.nextSaveURL = firstDestination
        await model.saveAs()
        #expect(model.hasPendingRecoveryCleanup)
        if case .recoveryCleanupRequired = model.lastError {
        } else {
            Issue.record("Expected post-Save As retirement warning")
        }
        let restartedBeforeRetry = RecoveryBuffer(
            recoveryDirectory: directory.appendingPathComponent("Recovery")
        )
        #expect(try await restartedBeforeRetry.load(for: source.id, epoch: source.recoveryEpoch) == nil)
        #expect(try await !(restartedBeforeRetry.saveCurrentLifetime(
            content: "stale after restart",
            for: source.id,
            version: source.mutationGeneration + 1,
            epoch: source.recoveryEpoch
        )))
        model.requestCloseDocument()
        await model.resolveClose(.discard)
        #expect(model.activeDocument?.fileURL == firstDestination.standardizedFileURL)

        model.tabStore.updateActiveDocument { $0.updatingText("second draft") }
        panel.nextSaveURL = secondDestination
        await model.saveAs()
        #expect(model.hasPendingRecoveryCleanup)

        await model.retryRecoveryCleanup()
        #expect(!model.hasPendingRecoveryCleanup)
        #expect(model.lastError == nil)
        #expect(try await recovery.load(for: source.id, epoch: source.recoveryEpoch) == nil)
        #expect(await recovery.retainedMarkerCount <= RecoveryBuffer.markerLimit)
    }
}

@MainActor
private final class RedirectProbe {
    var sourceRecovery: String?
    var destinationRecovery: String?
}

private final class FailFirstRetiredMarker: @unchecked Sendable {
    private let lock = NSLock()
    private var didFail = false

    func failOnce(for url: URL) throws {
        guard url.pathExtension == "retired" else { return }
        lock.lock()
        defer { lock.unlock() }
        guard !didFail else { return }
        didFail = true
        throw CocoaError(.fileWriteNoPermission)
    }
}
