@testable import FileCore
import Foundation
import Testing
@testable import Workspace

@MainActor
@Suite("WorkspaceModelFileOperations")
struct WorkspaceModelFileTests {
    // MARK: - Open file

    @Test func openFileLoadsDocument() async {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let url = directory.appendingPathComponent("doc.md")
        _ = try? FileStore().write("# Hello", to: url)

        let panel = FakeFilePanelProvider()
        panel.nextFileURL = url

        let model = WorkspaceModel(stateStore: FakeStateStore(), panel: panel)
        await model.openFile()

        #expect(model.activeDocument?.text == "# Hello")
        #expect(model.activeDocument?.format.id == "markdown")
        #expect(model.activeDocument?.state == .clean)
    }

    @Test func openFileCancelledLeavesWorkspaceEmpty() async {
        let panel = FakeFilePanelProvider()
        let model = WorkspaceModel(stateStore: FakeStateStore(), panel: panel)
        await model.openFile()
        #expect(model.activeDocument == nil)
    }

    @Test func openFileWhileDirtyOpensNewTabWithoutPrompt() async {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let firstURL = directory.appendingPathComponent("first.md")
        let secondURL = directory.appendingPathComponent("second.md")
        _ = try? FileStore().write("first", to: firstURL)
        _ = try? FileStore().write("second", to: secondURL)

        let panel = FakeFilePanelProvider()
        panel.nextFileURL = firstURL

        let model = WorkspaceModel(stateStore: FakeStateStore(), panel: panel)
        await model.openFile()
        model.tabStore.updateActiveDocument { $0.updatingText("edited") }

        panel.nextFileURL = secondURL
        await model.openFile()

        #expect(model.tabStore.pendingCloseTabID == nil)
        #expect(model.tabStore.tabs.count == 2)
        #expect(model.activeDocument?.text == "second")
    }

    @Test func openSameFileTwiceActivatesExistingTab() async {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let url = directory.appendingPathComponent("doc.md")
        _ = try? FileStore().write("content", to: url)

        let panel = FakeFilePanelProvider()
        panel.nextFileURL = url

        let model = WorkspaceModel(stateStore: FakeStateStore(), panel: panel)
        await model.openFile()
        model.newDocument()
        panel.nextFileURL = url
        await model.openFile()

        #expect(model.tabStore.tabs.count == 2)
        #expect(model.activeDocument?.fileURL == url)
    }

    // MARK: - Save / Save As

    @Test func saveExistingFileWritesToDisk() async throws {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let url = directory.appendingPathComponent("doc.md")
        _ = try? FileStore().write("old", to: url)

        let panel = FakeFilePanelProvider()
        panel.nextFileURL = url

        let model = WorkspaceModel(stateStore: FakeStateStore(), panel: panel)
        await model.openFile()
        model.tabStore.updateActiveDocument { $0.updatingText("new") }

        await model.save()

        #expect(model.activeDocument?.state == .clean)
        let (text, _) = try FileStore().read(from: url)
        #expect(text == "new")
    }

    @Test func saveUntitledUsesSavePanel() async throws {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let url = directory.appendingPathComponent("saved.md")

        let panel = FakeFilePanelProvider()
        panel.nextSaveURL = url

        let model = WorkspaceModel(stateStore: FakeStateStore(), panel: panel)
        model.newDocument()
        model.tabStore.updateActiveDocument { $0.updatingText("content") }

        await model.save()

        #expect(model.activeDocument?.fileURL == url)
        #expect(model.activeDocument?.state == .clean)
        let (text, _) = try FileStore().read(from: url)
        #expect(text == "content")
    }

    @Test func saveCancelledKeepsDocumentOpenAndDirty() async {
        let panel = FakeFilePanelProvider()
        let model = WorkspaceModel(stateStore: FakeStateStore(), panel: panel)
        model.newDocument()
        model.tabStore.updateActiveDocument { $0.updatingText("content") }

        await model.save()

        #expect(model.activeDocument?.fileURL == nil)
        #expect(model.activeDocument?.state == .dirty)
    }

    @Test func saveWithoutDocumentSetsError() async {
        let model = WorkspaceModel(stateStore: FakeStateStore())
        await model.save()

        if case .noActiveDocument = model.lastError {
            // pass
        } else {
            Issue.record("Expected .noActiveDocument, got \(String(describing: model.lastError))")
        }
    }

    @Test func saveToReadOnlyDirectoryFails() async {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let url = directory.appendingPathComponent("doc.md")
        _ = try? FileStore().write("content", to: url)

        var attributes = try? FileManager.default.attributesOfItem(atPath: directory.path)
        attributes?[FileAttributeKey.posixPermissions] = 0o555
        try? FileManager.default.setAttributes(attributes ?? [:], ofItemAtPath: directory.path)
        defer {
            var reset = try? FileManager.default.attributesOfItem(atPath: directory.path)
            reset?[FileAttributeKey.posixPermissions] = 0o755
            try? FileManager.default.setAttributes(reset ?? [:], ofItemAtPath: directory.path)
        }

        let panel = FakeFilePanelProvider()
        panel.nextFileURL = url

        let model = WorkspaceModel(stateStore: FakeStateStore(), panel: panel)
        await model.openFile()
        model.tabStore.updateActiveDocument { $0.updatingText("edited") }

        await model.save()

        #expect(model.activeDocument?.state == .dirty)
        if case .saveFailed = model.lastError {
            // pass
        } else {
            Issue.record("Expected .saveFailed, got \(String(describing: model.lastError))")
        }
    }

    @Test func ordinarySaveRefusesToOverwriteAnExternalConflict() async throws {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let url = directory.appendingPathComponent("conflict.md")
        let store = FileStore()
        _ = try store.write("baseline", to: url)
        let panel = FakeFilePanelProvider()
        panel.nextFileURL = url
        let model = WorkspaceModel(stateStore: FakeStateStore(), panel: panel)
        await model.openFile()
        model.tabStore.updateActiveDocument { $0.updatingText("local") }
        _ = try store.write("disk", to: url)
        let snapshot = try store.readSnapshot(from: url)
        model.tabStore.updateActiveDocument {
            $0.reconcilingExternalSnapshot(snapshot).document
        }

        await model.save()

        #expect(model.activeDocument?.state == .conflict)
        #expect(try store.read(from: url).content == "disk")
        if case .unresolvedExternalConflict = model.lastError {
            // expected
        } else {
            Issue.record("Expected unresolved external conflict, got \(String(describing: model.lastError))")
        }
    }

    @Test func saveAdoptsAnExternallyReconciledBaselineAfterAnEarlierSave() async throws {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let url = directory.appendingPathComponent("reconciled.md")
        let store = FileStore()
        _ = try store.write("baseline", to: url)
        let panel = FakeFilePanelProvider()
        panel.nextFileURL = url
        let model = WorkspaceModel(stateStore: FakeStateStore(), panel: panel)
        await model.openFile()
        model.tabStore.updateActiveDocument { $0.updatingText("first local") }
        await model.save()
        #expect(model.activeDocument?.state == .clean)

        _ = try store.write("external baseline", to: url)
        let external = try store.readSnapshot(from: url)
        model.tabStore.updateActiveDocument { $0.reconcilingExternalSnapshot(external).document }
        model.tabStore.updateActiveDocument { $0.updatingText("second local") }
        #expect(model.activeDocument?.lastKnownRevision == external.revision)
        #expect(try model.activeDocument?.fileStore.readSnapshot(from: url).revision == external.revision)

        await model.save()

        #expect(model.activeDocument?.state == .clean)
        #expect(try store.read(from: url).content == "second local")
    }

    @Test func saveMergesAcceptedBaselineIntoALaterLocalEdit() async throws {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let url = directory.appendingPathComponent("mid-save-edit.md")
        _ = try FileStore().write("baseline", to: url)
        let barrier = SavePublicationBarrier()
        let delayedStore = FileStore(afterBaselineVerification: { _ in barrier.arriveAndWait() })
        let document = try FileDocument(fileURL: url, fileStore: delayedStore)
            .load()
            .edited(text: "first local")
        let tabStore = TabStore(sessionStore: FakeSessionStore())
        tabStore.newTab(document: document)
        let model = WorkspaceModel(tabStore: tabStore, stateStore: FakeStateStore())

        let save = Task { @MainActor in await model.save() }
        await waitUntil { barrier.hasArrived }
        model.tabStore.updateActiveDocument { $0.edited(text: "second local") }
        barrier.allowPublication()
        await save.value

        #expect(model.activeDocument?.text == "second local")
        #expect(model.activeDocument?.state == .dirty)
        #expect(model.activeDocument?.lastKnownRevision?.sha256 != document.lastKnownRevision?.sha256)
        #expect(try FileStore().read(from: url).content == "first local")

        await model.save()

        #expect(model.activeDocument?.state == .clean)
        #expect(try FileStore().read(from: url).content == "second local")
    }

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
        // This request is intentionally coalesced until Save As has rebound
        // the active descendant, so it cannot write the former source path.
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

final class SavePublicationBarrier: @unchecked Sendable {
    private let lock = NSLock()
    private var arrived = false
    private var didEnterWriterLane = false
    private var shouldWait = true
    private let continuation = DispatchSemaphore(value: 0)
    private var arrivalContinuation: CheckedContinuation<Bool, Never>?
    private var secondSaveContinuation: CheckedContinuation<Bool, Never>?

    var hasArrived: Bool {
        lock.lock()
        defer { lock.unlock() }
        return arrived
    }

    func arriveAndWait() {
        lock.lock()
        arrived = true
        let waits = shouldWait
        shouldWait = false
        let arrivalContinuation = arrivalContinuation
        self.arrivalContinuation = nil
        lock.unlock()
        arrivalContinuation?.resume(returning: true)
        guard waits else { return }
        _ = continuation.wait(timeout: .now() + 3)
    }

    func allowPublication() {
        continuation.signal()
    }

    func waitForFirstPublication() async -> Bool {
        await withCheckedContinuation { continuation in
            lock.lock()
            if arrived {
                lock.unlock()
                continuation.resume(returning: true)
            } else {
                arrivalContinuation = continuation
                lock.unlock()
            }
        }
    }

    func secondSaveEnteredWriterLane() {
        lock.lock()
        didEnterWriterLane = true
        let continuation = secondSaveContinuation
        secondSaveContinuation = nil
        lock.unlock()
        continuation?.resume(returning: true)
    }

    func waitForSecondSaveToEnterWriterLane() async -> Bool {
        await withCheckedContinuation { continuation in
            lock.lock()
            if didEnterWriterLane {
                lock.unlock()
                continuation.resume(returning: true)
            } else {
                secondSaveContinuation = continuation
                lock.unlock()
            }
        }
    }

    func cancelWaiters() {
        lock.lock()
        let arrival = arrivalContinuation
        let second = secondSaveContinuation
        arrivalContinuation = nil
        secondSaveContinuation = nil
        lock.unlock()
        arrival?.resume(returning: false)
        second?.resume(returning: false)
    }

    func cancelAndAllowPublication() {
        cancelWaiters()
        allowPublication()
    }
}
