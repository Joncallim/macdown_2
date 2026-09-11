@testable import FileCore
import Foundation
import Testing
@testable import Workspace

/// `isSavingActiveDocument` (#57) is what the window's header bar reads to
/// show a "Saving…" spinner — before this there was no signal at all, so a
/// save that took a moment looked identical to the app being hung. As with
/// `isCreatingDocument` (`WorkspaceModelCreatingDocumentTests.swift`), the
/// real risk is the flag getting stuck `true` on a failure exit; every
/// branch `save()`/`saveAs()` can take is covered here.
@MainActor
@Suite("WorkspaceModel isSavingActiveDocument")
struct WorkspaceModelSavingIndicatorTests {
    @Test func clearsAfterAnOrdinarySuccessfulSave() async throws {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let url = directory.appendingPathComponent("doc.md")
        _ = try FileStore().write("original", to: url)
        let recovery = RecoveryBuffer(recoveryDirectory: directory.appendingPathComponent("Recovery"))
        let document = try FileDocument(fileURL: url, recoveryBuffer: recovery).load().updatingText("edited")
        let store = TabStore(sessionStore: FakeSessionStore(), recoveryBuffer: recovery)
        store.newTab(document: document)
        let model = WorkspaceModel(tabStore: store, stateStore: FakeStateStore())

        #expect(!model.isSavingActiveDocument)
        await model.save()

        #expect(model.activeDocument?.state == .clean)
        #expect(!model.isSavingActiveDocument)
    }

    @Test func clearsAfterAFailedSave() async {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let url = directory.appendingPathComponent("doc.md")
        _ = try? FileStore().write("original", to: url)
        var attributes = try? FileManager.default.attributesOfItem(atPath: directory.path)
        attributes?[FileAttributeKey.posixPermissions] = 0o555
        try? FileManager.default.setAttributes(attributes ?? [:], ofItemAtPath: directory.path)
        defer {
            var reset = try? FileManager.default.attributesOfItem(atPath: directory.path)
            reset?[FileAttributeKey.posixPermissions] = 0o755
            try? FileManager.default.setAttributes(reset ?? [:], ofItemAtPath: directory.path)
        }
        let recovery = RecoveryBuffer(recoveryDirectory: directory.appendingPathComponent("Recovery"))
        let document = FileDocument(fileURL: url, recoveryBuffer: recovery).updatingText("edited")
        let store = TabStore(sessionStore: FakeSessionStore(), recoveryBuffer: recovery)
        store.newTab(document: document)
        let model = WorkspaceModel(tabStore: store, stateStore: FakeStateStore())

        await model.save()

        #expect(model.activeDocument?.state == .dirty)
        #expect(!model.isSavingActiveDocument)
    }

    @Test func clearsAfterASuccessfulSaveAs() async {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let destination = directory.appendingPathComponent("destination.md")
        let recovery = RecoveryBuffer(recoveryDirectory: directory.appendingPathComponent("Recovery"))
        let panel = FakeFilePanelProvider()
        panel.nextSaveURL = destination
        let store = TabStore(sessionStore: FakeSessionStore(), recoveryBuffer: recovery)
        let document = FileDocument(recoveryBuffer: recovery).updatingText("draft")
        store.newTab(document: document)
        let model = WorkspaceModel(tabStore: store, stateStore: FakeStateStore(), panel: panel)

        #expect(!model.isSavingActiveDocument)
        await model.saveAs()

        #expect(model.activeDocument?.state == .clean)
        #expect(!model.isSavingActiveDocument)
    }

    @Test func clearsAfterAFailedSaveAs() async {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        var attributes = try? FileManager.default.attributesOfItem(atPath: directory.path)
        attributes?[FileAttributeKey.posixPermissions] = 0o555
        try? FileManager.default.setAttributes(attributes ?? [:], ofItemAtPath: directory.path)
        defer {
            var reset = try? FileManager.default.attributesOfItem(atPath: directory.path)
            reset?[FileAttributeKey.posixPermissions] = 0o755
            try? FileManager.default.setAttributes(reset ?? [:], ofItemAtPath: directory.path)
        }
        let destination = directory.appendingPathComponent("destination.md")
        let recovery = RecoveryBuffer(recoveryDirectory: directory.appendingPathComponent("Recovery"))
        let panel = FakeFilePanelProvider()
        panel.nextSaveURL = destination
        let store = TabStore(sessionStore: FakeSessionStore(), recoveryBuffer: recovery)
        let document = FileDocument(recoveryBuffer: recovery).updatingText("draft")
        store.newTab(document: document)
        let model = WorkspaceModel(tabStore: store, stateStore: FakeStateStore(), panel: panel)

        await model.saveAs()

        #expect(model.activeDocument?.state != .clean)
        if case .saveFailed = model.lastError {
        } else {
            Issue.record("Expected .saveFailed, got \(String(describing: model.lastError))")
        }
        #expect(!model.isSavingActiveDocument)
    }
}
