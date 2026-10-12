import EditorCore
import FileCore
import Foundation
@testable import MacDown2
import Testing
import Workspace

/// Round-11 review (51ac4816) P2: `preserveOpenDocumentAfterFailedClose` and
/// `preserveCurrentDocumentAfterStaleInitialMove`
/// gave up when an edit landed during their epoch mint, after the old lifetime was already retired, stranding the
/// window on it (every recovery write rejected). They now rebase onto the live document like `renewRecoveryLifetime`.
@MainActor
struct PreserveHelperRebaseTests {
    @Test func anEditDuringTheFailedCloseRetryPreservationStillRenewsTheLifetime() async throws {
        var stranded: [Int] = []
        var lost: [Int] = []
        // Offsets in microseconds*250: the reviewer saw the failure at 89-118; sweep that region densely.
        for yields in 80 ..< 125 {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let buffer = RecoveryBuffer(recoveryDirectory: directory.appendingPathComponent("Recovery"))
            let store = TabStore(
                sessionStore: WorkspaceSessionStore(fileURL: directory.appendingPathComponent("session.json")),
                recoveryBuffer: buffer
            )
            let document = FileDocument(text: "draft", recoveryBuffer: buffer).updatingText("draft")
            store.newTab(document: document)
            let model = WorkspaceModel(tabStore: store)
            // The controller is driven directly (no WindowController): a window's highlighter hits a Debug-only
            // `assertionFailure` in SwiftTreeSitter when text is replaced rapidly, which aborts the test host.
            let executor = ScriptedRecoveryExecutor()
            let controller = ExternalFileController(
                model: model, editorStore: EditorTextSystemStore(), identity: "preserve-close-\(yields)",
                recoveryExecutor: executor
            )
            await document.saveRecovery()
            await executor.failNext(.retire)
            #expect(await !(controller.retireRecovery(
                for: document, resumeCloseOnSuccess: true
            )).isAbsent)
            model.tabStore.updateActiveDocument { $0.updatingText("edit one") }
            controller.retryRecoveryCleanup()
            try? await Task.sleep(for: .microseconds(250 * yields))
            model.tabStore.updateActiveDocument { $0.updatingText("edit two \(yields)") }
            await controller.drainRecovery()
            for _ in 0 ..< 200 {
                await Task.yield()
            }
            let current = try #require(model.activeDocument)
            if current.recoveryEpoch == document.recoveryEpoch {
                stranded.append(yields)
            }
            if current.text != "edit two \(yields)" {
                lost.append(yields)
            }
        }
        #expect(stranded.isEmpty, "window left on the retired lifetime at offsets \(stranded)")
        #expect(lost.isEmpty, "edit lost at offsets \(lost)")
    }

    @Test func aSecondEditDuringStaleInitialMovePreservationStillRenewsTheLifetime() async throws {
        var stranded: [Int] = []
        var lost: [Int] = []
        for yields in stride(from: 0, to: 60, by: 6) {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let sourceURL = directory.appendingPathComponent("source.md")
            let destinationURL = directory.appendingPathComponent("destination.md")
            try "disk".write(to: sourceURL, atomically: true, encoding: .utf8)
            let recovery = RecoveryBuffer(recoveryDirectory: directory.appendingPathComponent("Recovery"))
            let source = try FileDocument(fileURL: sourceURL, recoveryBuffer: recovery).load().updatingText("draft")
            #expect(await source.persistRecovery())
            let store = TabStore(
                sessionStore: WorkspaceSessionStore(fileURL: directory.appendingPathComponent("session.json")),
                recoveryBuffer: recovery
            )
            store.newTab(document: source)
            let model = WorkspaceModel(tabStore: store)
            let controller = ExternalFileController(
                model: model,
                editorStore: EditorTextSystemStore(),
                identity: "preserve-rebase-\(yields)"
            )
            var second: Task<Void, Never>?
            controller.onInitialMoveRecoveryPrepared = {
                model.tabStore.updateActiveDocument { $0.updatingText("edit one") }
                second = Task { @MainActor in
                    for _ in 0 ..< yields {
                        await Task.yield()
                    }
                    model.tabStore.updateActiveDocument { $0.updatingText("edit two \(yields)") }
                }
            }
            try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
            let snapshot = try source.fileStore.readSnapshot(from: destinationURL)
            await controller.applyMove(snapshot, to: source, model: model)
            await second?.value
            await controller.drainRecovery()
            let current = try #require(model.activeDocument)
            if current.text != "edit two \(yields)" {
                lost.append(yields)
            }
            // write probe: can the live document persist recovery?
            if current.recoveryEpoch == source.recoveryEpoch,
               await !(current.persistRecovery()) {
                stranded.append(yields)
            }
        }
        #expect(stranded.isEmpty, "left on the retired source lifetime at offsets \(stranded)")
        #expect(lost.isEmpty, "edit lost at offsets \(lost)")
    }

    /// Round-12 review (52107b38) P3: a document that became clean during the epoch mint must not get a recovery
    /// record under the new lifetime (nothing removes it; a later relaunch would restore it as a false conflict).
    @Test func aCleanDocumentIsMovedToTheNewLifetimeWithoutWritingARecoveryRecord() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("a.md")
        try "disk text".write(to: file, atomically: true, encoding: .utf8)
        let buffer = RecoveryBuffer(recoveryDirectory: directory.appendingPathComponent("Recovery"))
        // Edited then saved: clean, with a non-zero mutation generation (a fresh load's version 0 is never recorded).
        let clean = try FileDocument(fileURL: file, recoveryBuffer: buffer).load().edited(text: "saved text").save()
        #expect(clean.state == .clean)
        let store = TabStore(
            sessionStore: WorkspaceSessionStore(fileURL: directory.appendingPathComponent("session.json")),
            recoveryBuffer: buffer
        )
        store.newTab(document: clean)
        let model = WorkspaceModel(tabStore: store)
        let controller = ExternalFileController(model: model, editorStore: EditorTextSystemStore(), identity: "clean")

        await controller.preserveCurrentDocumentAfterStaleInitialMove(in: model)
        await controller.drainRecovery()

        let renewed = try #require(model.activeDocument)
        #expect(renewed.recoveryEpoch != clean.recoveryEpoch, "the window is still moved off the retired lifetime")
        let record = try await buffer.load(for: renewed.id, epoch: renewed.recoveryEpoch)
        #expect(record == nil, "but no recovery record is written for clean text")
    }
}
