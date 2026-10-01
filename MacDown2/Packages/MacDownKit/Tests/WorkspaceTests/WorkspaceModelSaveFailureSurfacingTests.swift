@testable import FileCore
import Foundation
import Testing
@testable import Workspace

/// #183 F15 — a Save failure the user is waiting on is shown even when they
/// edited the document while the write was in flight.
@MainActor
@Suite("WorkspaceModel save failure surfacing (#183 F15)")
struct WorkspaceModelSaveFailureSurfacingTests {
    private func failingModel(
        url: URL,
        duringWrite edit: @escaping @MainActor (TabStore) -> Void
    ) throws -> (WorkspaceModel, TabStore) {
        let tabStore = TabStore(sessionStore: FakeSessionStore())
        let failing = FileStore(afterBaselineVerification: { _ in
            DispatchQueue.main.sync { MainActor.assumeIsolated { edit(tabStore) } }
            throw POSIXError(.EACCES)
        })
        try tabStore.newTab(document: FileDocument(fileURL: url, fileStore: failing).load().edited(text: "attempted"))
        return (WorkspaceModel(tabStore: tabStore, stateStore: FakeStateStore()), tabStore)
    }

    @Test func aFailureIsShownEvenIfTheUserTypedWhileTheWriteWasInFlight() async throws {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let url = directory.appendingPathComponent("note.md")
        _ = try FileStore().write("on disk", to: url)
        let (model, _) = try failingModel(url: url) { store in
            store.updateActiveDocument { $0.updatingText("attempted and then typed more") }
        }

        await model.save()

        #expect(model.lastError != nil)
        #expect(model.activeDocument?.text == "attempted and then typed more")
        #expect(model.activeDocument?.state == .dirty)
        #expect(try FileStore().read(from: url).content == "on disk")
    }

    @Test func aFailureIsShownAfterAnEditThatWasUndoneToTheAttemptedText() async throws {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let url = directory.appendingPathComponent("undo.md")
        _ = try FileStore().write("on disk", to: url)
        let (model, _) = try failingModel(url: url) { store in
            store.updateActiveDocument { $0.updatingText("attempted!") }
            store.updateActiveDocument { $0.updatingText("attempted") }
        }

        await model.save()

        #expect(model.lastError != nil)
        #expect(model.activeDocument?.state == .dirty)
    }

    @Test func aSuccessfulSaveShowsNoError() async throws {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let url = directory.appendingPathComponent("newer.md")
        _ = try FileStore().write("on disk", to: url)
        let tabStore = TabStore(sessionStore: FakeSessionStore())
        try tabStore.newTab(document: FileDocument(fileURL: url).load().edited(text: "ok"))
        let model = WorkspaceModel(tabStore: tabStore, stateStore: FakeStateStore())

        await model.save()

        #expect(model.lastError == nil)
        #expect(model.activeDocument?.state == .clean)
    }

    // MARK: - Error ownership: a late success must not erase a newer error

    private final class ModelBox: @unchecked Sendable {
        var model: WorkspaceModel?
    }

    @Test func aSuccessfulSaveDoesNotEraseAnErrorAnotherOperationPublishedMeanwhile() async throws {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let url = directory.appendingPathComponent("owned.md")
        _ = try FileStore().write("on disk", to: url)
        let box = ModelBox()
        let store = FileStore(afterBaselineVerification: { _ in
            DispatchQueue.main.sync {
                MainActor.assumeIsolated { box.model?.lastError = .unresolvedExternalConflict }
            }
        })
        let tabStore = TabStore(sessionStore: FakeSessionStore())
        try tabStore.newTab(document: FileDocument(fileURL: url, fileStore: store).load().edited(text: "saved"))
        let model = WorkspaceModel(tabStore: tabStore, stateStore: FakeStateStore())
        box.model = model

        await model.save()

        #expect(try FileStore().read(from: url).content == "saved")
        guard case .unresolvedExternalConflict? = model.lastError else {
            Issue.record("the newer error was erased: \(String(describing: model.lastError))")
            return
        }
    }

    @Test func clearLastErrorOnlyAppliesWhileTheErrorIsUnchangedSinceTheRevisionWasTaken() {
        let model = WorkspaceModel(tabStore: TabStore(sessionStore: FakeSessionStore()), stateStore: FakeStateStore())
        let before = model.errorRevision
        model.lastError = .noActiveDocument

        model.clearLastError(ifUnchangedSince: before)
        guard case .noActiveDocument? = model.lastError else {
            Issue.record("a changed error must survive a stale clear")
            return
        }

        model.clearLastError(ifUnchangedSince: model.errorRevision)
        #expect(model.lastError == nil)
    }
}
