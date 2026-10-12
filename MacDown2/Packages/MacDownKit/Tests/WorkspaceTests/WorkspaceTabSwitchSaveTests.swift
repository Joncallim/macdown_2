@testable import FileCore
import Foundation
import Testing
@testable import Workspace

/// Publication/recovery review (2026-10-11), F2 (P2): a save held at publication while the user switches to another
/// tab was never applied to its own tab (the result handler only looked at the ACTIVE tab). The file on disk then held
/// the saved text while the tab kept its old baseline and stayed dirty, so the user's NEXT save failed its conditional
/// write and was reported as an external-change conflict, and was never written.
@MainActor
struct WorkspaceTabSwitchSaveTests {
    @Test func aSaveCompletedWhileAnotherTabIsActiveIsAppliedToItsOwnTab() async throws {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let urlA = directory.appendingPathComponent("a.md")
        let urlB = directory.appendingPathComponent("b.md")
        _ = try FileStore().write("baseline", to: urlA)
        _ = try FileStore().write("other", to: urlB)
        let recovery = RecoveryBuffer(recoveryDirectory: directory.appendingPathComponent("Recovery"))
        let barrier = SavePublicationBarrier()
        let heldStore = FileStore(afterBaselineVerification: { _ in barrier.arriveAndWait() })
        let documentA = try FileDocument(fileURL: urlA, fileStore: heldStore, recoveryBuffer: recovery)
            .load().edited(text: "A saved")
        let documentB = try FileDocument(fileURL: urlB, recoveryBuffer: recovery).load()
        let store = TabStore(sessionStore: FakeSessionStore(), recoveryBuffer: recovery)
        store.newTab(document: documentA)
        let tabA = try #require(store.activeTabID)
        store.newTab(document: documentB)
        let tabB = try #require(store.activeTabID)
        store.activate(tabA)
        let model = WorkspaceModel(tabStore: store, stateStore: FakeStateStore())
        defer { barrier.cancelAndAllowPublication() }

        let save = Task { await model.save() }
        guard await waitForSignal(
            timeout: .seconds(30),
            wait: { await barrier.waitForFirstPublication() },
            onTimeout: { barrier.cancelWaiters() }
        ) else {
            Issue.record("The save never reached publication")
            return
        }
        store.activate(tabB) // the user switches away while the save is held
        barrier.allowPublication()
        await save.value

        let savedTab = try #require(store.tabs.first { $0.id == tabA }?.document)
        #expect(try FileStore().read(from: urlA).content == "A saved")
        #expect(savedTab.state == .clean, "the completed save must be applied to its own tab")

        // The user returns, edits, and saves again: it must be written, not reported as an external conflict.
        store.activate(tabA)
        model.tabStore.updateActiveDocument { $0.edited(text: "A saved plus more") }
        await model.save()

        #expect(model.activeDocument?.state == .clean)
        #expect(try FileStore().read(from: urlA).content == "A saved plus more")
        #expect(model.lastError == nil)
    }

    /// Cross-boundary review F2 (P2): Save As finalisation looked only at the ACTIVE tab, so a Save As held at
    /// publication while the user switched tabs wrote the file but never rebound its own tab to the new destination
    /// (the tab stayed dirty and pointed at the old file).
    @Test func aSaveAsCompletedWhileAnotherTabIsActiveRebindsItsOwnTab() async throws {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let urlA = directory.appendingPathComponent("a.md")
        let urlB = directory.appendingPathComponent("b.md")
        let destination = directory.appendingPathComponent("renamed.md")
        _ = try FileStore().write("baseline", to: urlA)
        _ = try FileStore().write("other", to: urlB)
        let recovery = RecoveryBuffer(recoveryDirectory: directory.appendingPathComponent("Recovery"))
        let barrier = SavePublicationBarrier()
        let heldStore = FileStore(afterBaselineVerification: { _ in barrier.arriveAndWait() })
        let documentA = try FileDocument(fileURL: urlA, fileStore: heldStore, recoveryBuffer: recovery)
            .load().edited(text: "A saved as")
        let documentB = try FileDocument(fileURL: urlB, recoveryBuffer: recovery).load()
        let store = TabStore(sessionStore: FakeSessionStore(), recoveryBuffer: recovery)
        store.newTab(document: documentA)
        let tabA = try #require(store.activeTabID)
        store.newTab(document: documentB)
        let tabB = try #require(store.activeTabID)
        store.activate(tabA)
        let model = WorkspaceModel(tabStore: store, stateStore: FakeStateStore())
        defer { barrier.cancelAndAllowPublication() }

        let saveAs = Task { await model.saveAs(to: destination, expecting: documentA) }
        guard await waitForSignal(
            timeout: .seconds(30),
            wait: { await barrier.waitForFirstPublication() },
            onTimeout: { barrier.cancelWaiters() }
        ) else {
            Issue.record("The Save As never reached publication")
            return
        }
        store.activate(tabB)
        barrier.allowPublication()
        await saveAs.value

        let rebound = try #require(store.tabs.first { $0.id == tabA }?.document)
        #expect(try FileStore().read(from: destination).content == "A saved as")
        #expect(rebound.fileURL?.standardizedFileURL == destination.standardizedFileURL,
                "the completed Save As must rebind its own tab")
        #expect(rebound.state == .clean)
        #expect(store.activeTabID == tabB, "finalisation must not steal or alter the active tab")
        #expect(store.tabs.first { $0.id == tabB }?.document.fileURL?.standardizedFileURL == urlB.standardizedFileURL)
    }

    /// Post-fix review (d2b7e242) F3: a metadata-only external change detected during a save is reconciled and the
    /// save retried; both looked only at the ACTIVE tab, so after a tab switch the owning tab's baseline stayed stale
    /// and the retry saved (or refused) the wrong document.
    @Test func aMetadataOnlyConflictReconciledAfterATabSwitchIsAppliedToItsOwnTab() async throws {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let urlA = directory.appendingPathComponent("a.md")
        let urlB = directory.appendingPathComponent("b.md")
        _ = try FileStore().write("baseline", to: urlA)
        _ = try FileStore().write("other", to: urlB)
        let recovery = RecoveryBuffer(recoveryDirectory: directory.appendingPathComponent("Recovery"))
        let barrier = SavePublicationBarrier()
        let heldStore = FileStore(afterBaselineVerification: { _ in barrier.arriveAndWait() })
        let documentA = try FileDocument(fileURL: urlA, fileStore: heldStore, recoveryBuffer: recovery)
            .load().edited(text: "A saved")
        let documentB = try FileDocument(fileURL: urlB, recoveryBuffer: recovery).load()
        let store = TabStore(sessionStore: FakeSessionStore(), recoveryBuffer: recovery)
        store.newTab(document: documentA)
        let tabA = try #require(store.activeTabID)
        store.newTab(document: documentB)
        let tabB = try #require(store.activeTabID)
        store.activate(tabA)
        let model = WorkspaceModel(tabStore: store, stateStore: FakeStateStore())
        defer { barrier.cancelAndAllowPublication() }

        let save = Task { await model.save() }
        guard await waitForSignal(
            timeout: .seconds(30),
            wait: { await barrier.waitForFirstPublication() },
            onTimeout: { barrier.cancelWaiters() }
        ) else {
            Issue.record("The save never reached publication")
            return
        }
        store.activate(tabB)
        // Metadata-only change: same bytes, new modification time.
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: 3600)],
            ofItemAtPath: urlA.path
        )
        barrier.allowPublication()
        await save.value

        let owner = try #require(store.tabs.first { $0.id == tabA }?.document)
        #expect(try FileStore().read(from: urlA).content == "A saved", "the retry must save the owning tab")
        #expect(owner.state == .clean)
        #expect(model.lastError == nil)
        #expect(store.tabs.first { $0.id == tabB }?.document.text == "other")
    }
}
