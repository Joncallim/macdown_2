@testable import FileCore
import Foundation
import Testing
@testable import Workspace

@MainActor
@Suite("WorkspaceModel Save As operations")
struct WorkspaceModelFileSaveAsTests {
    @Test func saveAsRebindsALaterEditAndDefersOldPathSaves() async throws {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let source = directory.appendingPathComponent("source.md")
        let destination = directory.appendingPathComponent("destination.md")
        _ = try FileStore().write("baseline", to: source)
        let barrier = SavePublicationBarrier()
        let delayedStore = FileStore(afterBaselineVerification: { _ in barrier.arriveAndWait() })
        let document = try FileDocument(fileURL: source, fileStore: delayedStore)
            .load()
            .edited(text: "published")
        let panel = FakeFilePanelProvider()
        panel.nextSaveURL = destination
        let tabStore = TabStore(sessionStore: FakeSessionStore())
        tabStore.newTab(document: document)
        let model = WorkspaceModel(tabStore: tabStore, stateStore: FakeStateStore(), panel: panel)
        await document.saveRecovery()

        let saveAs = Task { @MainActor in await model.saveAs() }
        await waitUntil { barrier.hasArrived }
        model.tabStore.updateActiveDocument { $0.edited(text: "later local") }
        await model.save()
        barrier.allowPublication()
        await saveAs.value

        #expect(model.activeDocument?.fileURL == destination)
        #expect(model.activeDocument?.text == "later local")
        #expect(model.activeDocument?.state == .dirty)
        #expect(try FileStore().read(from: destination).content == "published")
        #expect(try FileStore().read(from: source).content == "baseline")
        #expect(try await document.recoveryBuffer.load(for: document.id, epoch: document.recoveryEpoch) == nil)
        if let rebound = model.activeDocument {
            #expect(try await rebound.recoveryBuffer
                .load(for: rebound.id, epoch: rebound.recoveryEpoch) == "later local")
        }

        await model.save()
        #expect(model.activeDocument?.state == .clean)
        #expect(try FileStore().read(from: destination).content == "later local")
    }

    private func waitUntil(
        _ condition: @escaping @Sendable () -> Bool,
        limit: Int = 200
    ) async {
        for _ in 0 ..< limit {
            if condition() {
                return
            }
            await Task.yield()
        }
        Issue.record("Timed out waiting for delayed save publication")
    }
}
