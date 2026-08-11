@testable import FileCore
import Foundation
import Testing
@testable import Workspace

@MainActor
@Suite("WorkspaceModel recovery and save lifetimes")
struct WorkspaceModelRecoveryTests {
    @Test func discardCloseRetiresTheExactRecoveryLifetime() async throws {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let recovery = RecoveryBuffer(recoveryDirectory: directory.appendingPathComponent("Recovery"))
        let document = FileDocument(text: "draft", recoveryBuffer: recovery).edited(text: "edited")
        await document.saveRecovery()
        let tabStore = TabStore(sessionStore: FakeSessionStore(), recoveryBuffer: recovery)
        tabStore.newTab(document: document)
        let model = WorkspaceModel(tabStore: tabStore, stateStore: FakeStateStore())

        model.requestCloseDocument()
        await model.resolveClose(.discard)

        #expect(model.activeDocument == nil)
        #expect(try await recovery.load(for: document.id, epoch: document.recoveryEpoch) == nil)
        try await recovery.save(
            content: "late",
            for: document.id,
            version: document.mutationGeneration &+ 1,
            epoch: document.recoveryEpoch
        )
        #expect(try await recovery.load(for: document.id, epoch: document.recoveryEpoch) == nil)
    }

    @Test func recoveryRequiredPublicationErrorSurvivesALaterLocalEdit() async throws {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let url = directory.appendingPathComponent("conditional-publication-edit.md")
        _ = try FileStore().write("baseline", to: url)
        let barrier = SavePublicationBarrier()
        let store = FileStore(
            afterBaselineVerification: { url in
                barrier.arriveAndWait()
                try Data("external winner".utf8).write(to: url, options: .atomic)
            },
            conditionalPublicationHooks: ConditionalPublicationTestHooks(
                beforeRollbackSwap: { _, _ in throw POSIXError(.EIO) }
            )
        )
        let document = try FileDocument(fileURL: url, fileStore: store)
            .load()
            .edited(text: "ours")
        let tabStore = TabStore(sessionStore: FakeSessionStore())
        tabStore.newTab(document: document)
        let model = WorkspaceModel(tabStore: tabStore, stateStore: FakeStateStore())

        let save = Task { @MainActor in await model.save() }
        for _ in 0 ..< 200 where !barrier.hasArrived {
            await Task.yield()
        }
        guard barrier.hasArrived else {
            barrier.cancelAndAllowPublication()
            await save.value
            Issue.record("Timed out waiting for conditional publication")
            return
        }
        model.tabStore.updateActiveDocument { $0.edited(text: "newer local") }
        barrier.allowPublication()
        await save.value

        #expect(model.activeDocument?.text == "newer local")
        #expect(model.activeDocument?.state == .dirty)
        if case let .conditionalPublicationRecoveryRequired(recoveryURL) = model.lastError {
            #expect(recoveryURL.lastPathComponent.contains("external-recovery"))
            #expect(try FileStore().read(from: recoveryURL).content == "external winner")
        } else {
            Issue.record("Expected dedicated recovery-required notice after later local edit")
        }
    }

    @Test func saveSurfacesPreservedCompetingPublicationForRecovery() async throws {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let url = directory.appendingPathComponent("conditional-publication.md")
        _ = try FileStore().write("baseline", to: url)
        let store = FileStore(
            afterBaselineVerification: { url in
                try Data("external winner".utf8).write(to: url, options: .atomic)
            },
            conditionalPublicationHooks: ConditionalPublicationTestHooks(
                beforeRollbackSwap: { _, _ in throw POSIXError(.EIO) }
            )
        )
        let document = try FileDocument(fileURL: url, fileStore: store)
            .load()
            .edited(text: "ours")
        let tabStore = TabStore(sessionStore: FakeSessionStore())
        tabStore.newTab(document: document)
        let model = WorkspaceModel(tabStore: tabStore, stateStore: FakeStateStore())

        await model.save()

        #expect(model.activeDocument?.state == .dirty)
        if case let .conditionalPublicationRecoveryRequired(recoveryURL) = model.lastError {
            #expect(recoveryURL.lastPathComponent.contains("external-recovery"))
            #expect(try FileStore().read(from: recoveryURL).content == "external winner")
        } else {
            Issue.record("Expected dedicated conditional-publication recovery error")
        }
    }

    @Test func repeatedSaveAsRetiresFormerLifetimeLineageAndGeneration() async throws {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let initialURL = directory.appendingPathComponent("initial.md")
        _ = try FileStore().write("initial", to: initialURL)
        let panel = FakeFilePanelProvider()
        let tabStore = TabStore(sessionStore: FakeSessionStore())
        let document = try FileDocument(fileURL: initialURL).load().edited(text: "one")
        tabStore.newTab(document: document)
        let model = WorkspaceModel(tabStore: tabStore, stateStore: FakeStateStore(), panel: panel)

        for index in 0 ..< 3 {
            await model.save()
            guard let beforeSaveAs = model.activeDocument else {
                Issue.record("Expected an active document")
                return
            }
            // Completed, non-queued saves compact their accepted lineage
            // immediately; Save As must still retire any residual state.
            #expect(await model.acceptedSaveLineageCount(for: beforeSaveAs) == 0)
            #expect(model.tracksSaveGeneration(for: beforeSaveAs))

            panel.nextSaveURL = directory.appendingPathComponent("save-as-\(index).md")
            await model.saveAs()

            #expect(await model.acceptedSaveLineageCount(for: beforeSaveAs) == 0)
            #expect(!model.tracksSaveGeneration(for: beforeSaveAs))
            model.tabStore.updateActiveDocument { $0.edited(text: "edit-\(index)") }
        }
    }
}
