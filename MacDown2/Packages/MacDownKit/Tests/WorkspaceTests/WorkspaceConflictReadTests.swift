import FileCore
import Foundation
import Testing
@testable import Workspace

@MainActor
struct WorkspaceConflictReadTests {
    @Test(arguments: [false, true])
    func typingDuringConflictReadPreservesAndSavesLiveText(undo: Bool) async throws {
        try await withHeldRead { fixture in
            fixture.store.updateActiveDocument { $0.edited(text: "newer café") }
            if undo {
                fixture.store.updateActiveDocument { $0.edited(text: "local café") }
            }
        } verify: { fixture in
            let expected = undo ? "local café" : "newer café"
            #expect(fixture.model.activeDocument?.text == expected)
            #expect(fixture.model.activeDocument?.state == .clean)
            let disk = try FileStore().read(from: fixture.url).content
            let recovery = try await fixture.recovery.load(for: fixture.original.id)
            #expect(disk == expected)
            #expect(fixture.model.lastError == nil)
            #expect(recovery == nil)
        }
    }

    @Test func anotherTabCanActivateWhileTheOwningSaveCompletes() async throws {
        try await withHeldRead { fixture in
            fixture.store.newTab(document: FileDocument(text: "other", recoveryBuffer: fixture.recovery))
        } verify: { fixture in
            #expect(fixture.store.activeDocument?.text == "other")
            let owner = try #require(fixture.store.tabs.first { $0.id == fixture.tabID }?.document)
            #expect(owner.state == .clean)
            #expect(try FileStore().read(from: fixture.url).content == "local café")
            #expect(fixture.model.lastError == nil)
        }
    }

    @Test(arguments: ["save", "failed save", "reload", "reload then type", "close/reopen", "Save As", "rename"])
    func anObsoleteReadCannotReplaceANewerOutcome(action: String) async throws {
        var expected: FileDocument?
        var expectedError: WorkspaceError?
        try await withHeldRead { fixture in
            // The first operation captured its hook already; newer operations must not be held by it.
            fixture.model.afterSaveConflictRead = nil
            try await apply(action, to: fixture)
            expected = fixture.model.activeDocument
            expectedError = fixture.model.lastError
            if let expected, expected.state != .clean {
                #expect(await fixture.model.recoverySnapshotIsDurable(for: expected))
            }
        } verify: { fixture in
            let current = try #require(fixture.model.activeDocument)
            let expected = try #require(expected)
            expectUnchanged(current, expected, model: fixture.model)
            #expect(fixture.model.lastError?.localizedDescription == expectedError?.localizedDescription)
            let diskURL = action == "rename" ? fixture.directory.appendingPathComponent("moved.md") : fixture.url
            let disk = try FileStore().read(from: diskURL).content
            let expectedDisk = action == "save" ? "newer saved café"
                : action.hasPrefix("reload") ? "external reload" : "baseline"
            #expect(disk == expectedDisk)
            if current.state != .clean {
                #expect(try await fixture.recovery.load(for: current.id, epoch: current.recoveryEpoch) == current.text)
            }
        }
    }

    @Test func aRealConflictKeepsNewTypingAndExternalBytes() async throws {
        try await withHeldRead(externalText: "external") { fixture in
            fixture.store.updateActiveDocument { $0.edited(text: "latest local café") }
        } verify: { fixture in
            let current = try #require(fixture.model.activeDocument)
            #expect(current.text == "latest local café")
            #expect(current.state == .conflict)
            #expect(try FileStore().read(from: fixture.url).content == "external")
            #expect(try await fixture.recovery.load(for: current.id) == "latest local café")
            guard case .unresolvedExternalConflict = fixture.model.lastError else {
                Issue.record("A current conflict must be reported")
                return
            }
        }
    }

    @Test(arguments: ["current", "failed save", "reload", "close"])
    func failedReadsPublishOnlyForTheirCurrentOwner(action: String) async throws {
        var expectedError: WorkspaceError?
        try await withHeldRead(invalidExternalBytes: true) { fixture in
            fixture.model.afterSaveConflictRead = nil
            if action == "close" {
                fixture.store.removeTab(at: 0)
            } else if action != "current" {
                try await apply(action, to: fixture)
            }
            expectedError = fixture.model.lastError
        } verify: { fixture in
            if action == "current" {
                guard case .unresolvedExternalConflict = fixture.model.lastError else {
                    Issue.record("A current failed read must report its unresolved save conflict")
                    return
                }
                #expect(fixture.model.activeDocument?.text == "local café")
                #expect(fixture.model.activeDocument?.state == .dirty)
            } else {
                #expect(fixture.model.lastError?.localizedDescription == expectedError?.localizedDescription)
            }
            let expected = action == "reload" ? Data("external reload".utf8) : Data([0xFF])
            let disk = try Data(contentsOf: fixture.url)
            #expect(disk == expected)
        }
    }

    @Test(arguments: ["typing", "save", "close/reopen"])
    func newerOutcomesAfterRecoveryPersistenceKeepTheirOwnError(action: String) async throws {
        var expected: FileDocument?
        try await withHeldRead(externalText: "external") { fixture in
            fixture.model.afterSaveConflictRecoveryPersistence = {
                fixture.model.afterSaveConflictRecoveryPersistence = nil
                fixture.model.afterSaveConflictRead = nil
                do {
                    if action == "typing" {
                        fixture.store.updateActiveDocument { $0.edited(text: "typed after conflict persistence") }
                    } else if action == "save" {
                        let current = try #require(fixture.model.activeDocument)
                        let revision = try #require(current.pendingExternalRevision)
                        fixture.store.updateActiveDocument { $0.keepingLocalChanges(acknowledging: revision) }
                        await fixture.model.save()
                    } else {
                        try await apply(action, to: fixture)
                    }
                    expected = fixture.model.activeDocument
                    if let expected, expected.state != .clean {
                        #expect(await fixture.model.recoverySnapshotIsDurable(for: expected))
                    }
                    fixture.model.lastError = .noActiveDocument
                } catch {
                    Issue.record(error)
                }
            }
        } verify: { fixture in
            let current = try #require(fixture.model.activeDocument)
            try expectUnchanged(current, #require(expected), model: fixture.model)
            guard case .noActiveDocument = fixture.model.lastError else {
                Issue.record("Old conflict completion replaced the newer error")
                return
            }
            if current.state != .clean {
                #expect(try await fixture.recovery.load(for: current.id, epoch: current.recoveryEpoch) == current.text)
            }
            let disk = try FileStore().read(from: fixture.url).content
            #expect(disk == (action == "save" ? "local café" : "external"))
        }
    }
}

@MainActor
private extension WorkspaceConflictReadTests {
    private func apply(_ action: String, to fixture: Fixture) async throws {
        switch action {
        case "save":
            fixture.store.updateActiveDocument { $0.edited(text: "newer saved café") }
            await fixture.model.save()
        case "failed save":
            _ = await fixture.model.saveWithoutDestinationPrompt(encoding: .init(encoding: .ascii, bom: .none))
            #expect(fixture.model.lastError != nil)
        case "reload", "reload then type":
            _ = try FileStore().write("external reload", to: fixture.url)
            let snapshot = try FileStore().readSnapshot(from: fixture.url)
            fixture.store.updateActiveDocument { $0.reloadedFromExternal(snapshot) }
            if action == "reload then type" {
                fixture.store.updateActiveDocument { $0.edited(text: "edited after reload") }
                fixture.model.lastError = .noActiveDocument
            }
        case "close/reopen":
            fixture.store.removeTab(at: 0)
            let replacement = try FileDocument(fileURL: fixture.url, recoveryBuffer: fixture.recovery).load()
            fixture.store.newTab(document: replacement)
            #expect(replacement.recoveryEpoch != fixture.original.recoveryEpoch)
        case "Save As":
            let current = try #require(fixture.model.activeDocument)
            await fixture.model.saveAs(
                to: fixture.directory.appendingPathComponent("saved-as.md"),
                expecting: current
            )
        case "rename":
            let moved = fixture.directory.appendingPathComponent("moved.md")
            try FileManager.default.moveItem(at: fixture.url, to: moved)
            fixture.store.updateActiveDocument { $0.renamed(to: moved) }
        default:
            Issue.record("Unknown fixture action")
        }
    }

    private func expectUnchanged(_ current: FileDocument, _ expected: FileDocument, model: WorkspaceModel) {
        #expect(model.sameSaveAsSnapshot(current, expected))
        #expect(current.lastKnownRevision == expected.lastKnownRevision)
        #expect(current.encoding == expected.encoding)
        #expect(current.recoveryEpoch == expected.recoveryEpoch)
    }

    private func withHeldRead(
        externalText: String? = nil,
        invalidExternalBytes: Bool = false,
        action: (Fixture) async throws -> Void,
        verify: (Fixture) async throws -> Void
    ) async throws {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let fixture = try makeFixture(directory: directory, externalText: externalText,
                                      invalidExternalBytes: invalidExternalBytes)
        let model = fixture.model
        let barrier = DocumentReadBarrier()
        model.afterSaveConflictRead = {
            #expect(!Thread.isMainThread, "conflict reads, hashing and decoding must leave the UI actor available")
            barrier.arriveAndWait()
        }
        defer { barrier.release() }
        let save = Task { await model.save() }
        guard await waitForSignal(wait: { await barrier.waitForArrival() }, onTimeout: { barrier.release() }) else {
            await save.value
            Issue.record("Save did not reach the real held conflict snapshot read")
            return
        }
        do {
            try await action(fixture)
        } catch {
            barrier.release()
            await save.value
            throw error
        }
        barrier.release()
        await save.value
        #expect(!barrier.timedOut)
        do {
            try await verify(fixture)
        } catch {
            throw error
        }
    }

    private func makeFixture(directory: URL, externalText: String?, invalidExternalBytes: Bool) throws -> Fixture {
        let url = directory.appendingPathComponent("document.md")
        _ = try FileStore().write("baseline", to: url)
        let recovery = RecoveryBuffer(recoveryDirectory: directory.appendingPathComponent("Recovery"))
        let document = try FileDocument(fileURL: url, recoveryBuffer: recovery).load().edited(text: "local café")
        let store = TabStore(sessionStore: FakeSessionStore(), recoveryBuffer: recovery)
        // Keep the debounced session autosave disabled throughout this fixture. Only the save/conflict paths
        // under test may persist recovery; unrelated autosave must not repair a stale-operation defect.
        store.saveTask = Task {}
        store.newTab(document: document)
        let tabID = try #require(store.activeTabID)
        let model = WorkspaceModel(tabStore: store, stateStore: FakeStateStore())
        if invalidExternalBytes {
            try Data([0xFF]).write(to: url)
        } else if let externalText {
            _ = try FileStore().write(externalText, to: url)
        } else {
            try FileManager.default.setAttributes(
                [.modificationDate: Date(timeIntervalSinceNow: 3600)], ofItemAtPath: url.path
            )
        }
        return Fixture(directory: directory, url: url, recovery: recovery, original: document,
                       tabID: tabID, store: store, model: model)
    }

    private struct Fixture {
        let directory: URL
        let url: URL
        let recovery: RecoveryBuffer
        let original: FileDocument
        let tabID: UUID
        let store: TabStore
        let model: WorkspaceModel
    }
}
