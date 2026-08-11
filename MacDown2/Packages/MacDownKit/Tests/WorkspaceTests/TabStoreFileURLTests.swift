import FileCore
import Foundation
import Testing
@testable import Workspace

@MainActor
@Test func documentFileIntentsUseStandardizedURLs() async {
    let store = TabStore(sessionStore: FakeSessionStore())
    let url = URL(fileURLWithPath: "/tmp/../tmp/notes.md")
    let document = FileDocument(fileURL: url, text: "notes")
    store.newTab(document: document)
    #expect(store.activeTabID != nil)
    let id = store.activeTabID ?? UUID()
    #expect(store.tabID(forFileURL: URL(fileURLWithPath: "/tmp/notes.md")) == id)

    #expect(await store.documentWasRenamed(
        from: URL(fileURLWithPath: "/tmp/notes.md"),
        to: URL(fileURLWithPath: "/tmp/notes.txt")
    ))
    #expect(store.activeDocument?.fileURL?.lastPathComponent == "notes.txt")
    #expect(store.documentFileWasDeleted(at: URL(fileURLWithPath: "/tmp/notes.txt")) == .closedCleanTab(id))
}

@MainActor
@Test func folderRenameAndDeletionApplyToDescendantOpenDocuments() async throws {
    let store = TabStore(sessionStore: FakeSessionStore())
    let oldFolder = URL(fileURLWithPath: "/tmp/project", isDirectory: true)
    let oldFile = oldFolder.appendingPathComponent("nested/notes.md")
    let document = FileDocument(fileURL: oldFile, text: "notes")
    store.newTab(document: document)

    let newFolder = URL(fileURLWithPath: "/tmp/renamed-project", isDirectory: true)
    #expect(await store.documentWasRenamed(from: oldFolder, to: newFolder))
    let newFile = newFolder.appendingPathComponent("nested/notes.md")
    #expect(store.activeDocument?.fileURL == newFile.standardizedFileURL)

    let id = store.activeTabID
    #expect(try store.documentFileWasDeleted(at: newFolder) == .closedCleanTab(#require(id)))
}

@MainActor
@Test func folderRenamePreservesDirtyStateForADescendantDocument() async {
    let directory = temporaryDirectory()
    defer { cleanup(directory) }
    let recovery = RecoveryBuffer(recoveryDirectory: directory.appendingPathComponent("Recovery"))
    let store = TabStore(sessionStore: FakeSessionStore(), recoveryBuffer: recovery)
    let oldFolder = URL(fileURLWithPath: "/tmp/dirty-project", isDirectory: true)
    let document = FileDocument(
        fileURL: oldFolder.appendingPathComponent("notes.md"),
        text: "notes",
        recoveryBuffer: recovery
    )
    .updatingText("changed")
    store.newTab(document: document)

    let newFolder = URL(fileURLWithPath: "/tmp/renamed-dirty-project", isDirectory: true)
    #expect(await store.documentWasRenamed(from: oldFolder, to: newFolder))

    #expect(store.activeDocument?.fileURL == newFolder.appendingPathComponent("notes.md").standardizedFileURL)
    #expect(store.activeDocument?.state == .dirty)
}

@MainActor
@Test func tabLookupAndDeletionRecognizeSymlinkAliases() throws {
    let root = temporaryDirectory()
    defer { cleanup(root) }
    let file = root.appendingPathComponent("notes.md")
    let alias = root.appendingPathComponent("notes-alias.md")
    try Data("notes".utf8).write(to: file)
    try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: file)

    let store = TabStore(sessionStore: FakeSessionStore())
    let document = FileDocument(fileURL: file, text: "notes")
    store.newTab(document: document)
    let id = try #require(store.activeTabID)

    #expect(store.tabID(forFileURL: alias) == id)
    #expect(store.documentFileWasDeleted(at: alias) == .closedCleanTab(id))
}

@MainActor
@Test func unresolvedCaseDistinctPathsDoNotRetargetOrCloseEachOther() async {
    let lower = URL(fileURLWithPath: "/case-sensitive-volume/foo.md")
    let upper = URL(fileURLWithPath: "/case-sensitive-volume/FOO.md")
    let renamed = URL(fileURLWithPath: "/case-sensitive-volume/renamed.md")
    let store = TabStore(sessionStore: FakeSessionStore())
    store.newTab(document: FileDocument(fileURL: lower, text: "foo"))
    let id = store.activeTabID

    #expect(await store.documentWasRenamed(from: upper, to: renamed))

    #expect(store.activeDocument?.fileURL == lower.standardizedFileURL)
    #expect(store.documentFileWasDeleted(at: upper) == .notOpen)
    #expect(store.activeTabID == id)
}

@MainActor
@Test func editDuringBatchRenamePreparationKeepsTheCurrentDocumentIdentityAndText() async throws {
    let directory = temporaryDirectory()
    defer { cleanup(directory) }
    let recovery = RecoveryBuffer(recoveryDirectory: directory.appendingPathComponent("Recovery"))
    let sessions = FakeSessionStore()
    let store = TabStore(sessionStore: sessions, recoveryBuffer: recovery)
    let oldFolder = directory.appendingPathComponent("old", isDirectory: true)
    let newFolder = directory.appendingPathComponent("new", isDirectory: true)
    let sourceURL = oldFolder.appendingPathComponent("notes.md")
    let document = FileDocument(fileURL: sourceURL, recoveryBuffer: recovery).updatingText("before rename")
    #expect(await document.persistRecovery())
    store.newTab(document: document)
    store.onRenameReplacementPrepared = { _ in
        store.updateActiveDocument { $0.updatingText("edit during preparation") }
    }

    #expect(await store.documentWasRenamed(from: oldFolder, to: newFolder))

    let current = try #require(store.activeDocument)
    #expect(current.fileURL == sourceURL.standardizedFileURL)
    #expect(current.text == "edit during preparation")
    #expect(current.recoveryEpoch == document.recoveryEpoch)
    #expect(await store.saveSession())
    #expect(try await recovery.load(for: current.id, epoch: current.recoveryEpoch) == current.text)

    let restored = TabStore(sessionStore: sessions, recoveryBuffer: recovery)
    await restored.restoreSessionIfNeeded()
    #expect(restored.activeDocument?.fileURL == sourceURL.standardizedFileURL)
    #expect(restored.activeDocument?.text == current.text)
}

@MainActor
@Test func batchRenameRevalidatesAllTabsAfterPreservingAnotherStaleTab() async throws {
    let directory = temporaryDirectory()
    defer { cleanup(directory) }
    let recovery = RecoveryBuffer(recoveryDirectory: directory.appendingPathComponent("Recovery"))
    let sessions = FakeSessionStore()
    let store = TabStore(sessionStore: sessions, recoveryBuffer: recovery)
    let oldFolder = directory.appendingPathComponent("old", isDirectory: true)
    let newFolder = directory.appendingPathComponent("new", isDirectory: true)
    let firstURL = oldFolder.appendingPathComponent("first.md")
    let secondURL = oldFolder.appendingPathComponent("second.md")
    let first = FileDocument(fileURL: firstURL, recoveryBuffer: recovery).updatingText("first before rename")
    let second = FileDocument(fileURL: secondURL, recoveryBuffer: recovery).updatingText("second before rename")
    #expect(await first.persistRecovery())
    #expect(await second.persistRecovery())
    store.newTab(document: first)
    store.newTab(document: second)

    store.onRenameRecoveryMigrationCompleted = { document in
        guard document.id == second.id,
              let index = store.tabs.firstIndex(where: { $0.document.id == second.id })
        else { return }
        store.tabs[index].document = store.tabs[index].document.updatingText("second edit before preservation")
    }
    store.onRenamePreservationPrepared = { document in
        guard document.id == second.id,
              let index = store.tabs.firstIndex(where: { $0.document.id == first.id })
        else { return }
        store.tabs[index].document = store.tabs[index].document.updatingText("first edit while second preserves")
    }

    #expect(await store.documentWasRenamed(from: oldFolder, to: newFolder))

    let currentFirst = try #require(store.tabs.first(where: { $0.document.id == first.id })?.document)
    let currentSecond = try #require(store.tabs.first(where: { $0.document.id == second.id })?.document)
    #expect(currentFirst.fileURL == firstURL.standardizedFileURL)
    #expect(currentFirst.text == "first edit while second preserves")
    #expect(currentSecond.fileURL == secondURL.standardizedFileURL)
    #expect(currentSecond.text == "second edit before preservation")
    #expect(try await recovery.load(for: currentFirst.id, epoch: currentFirst.recoveryEpoch) == currentFirst.text)
    #expect(try await recovery.load(for: currentSecond.id, epoch: currentSecond.recoveryEpoch) == currentSecond.text)

    let restored = TabStore(sessionStore: sessions, recoveryBuffer: recovery)
    await restored.restoreSessionIfNeeded()
    #expect(restored.tabs.map(\.document.fileURL) == [firstURL.standardizedFileURL, secondURL.standardizedFileURL])
    #expect(restored.tabs.map(\.document.text) == [
        "first edit while second preserves",
        "second edit before preservation",
    ])
}

@MainActor
@Test func batchRenamePersistsFourSuccessiveStaleReconciliationsBeforeRestart() async throws {
    let directory = temporaryDirectory()
    defer { cleanup(directory) }
    let recovery = RecoveryBuffer(recoveryDirectory: directory.appendingPathComponent("Recovery"))
    let sessions = FakeSessionStore()
    let store = TabStore(sessionStore: sessions, recoveryBuffer: recovery)
    let oldFolder = directory.appendingPathComponent("old", isDirectory: true)
    let newFolder = directory.appendingPathComponent("new", isDirectory: true)
    let sourceURL = oldFolder.appendingPathComponent("notes.md")
    let source = FileDocument(fileURL: sourceURL, recoveryBuffer: recovery).updatingText("before rename")
    #expect(await source.persistRecovery())
    store.newTab(document: source)

    var preservationRaces = 0
    store.onRenameRecoveryMigrationCompleted = { document in
        guard document.id == source.id else { return }
        store.updateActiveDocument { $0.updatingText("stale 0") }
    }
    store.onRenamePreservationPrepared = { document in
        guard document.id == source.id, preservationRaces < 4 else { return }
        preservationRaces += 1
        store.updateActiveDocument { $0.updatingText("stale \(preservationRaces)") }
    }

    #expect(await store.documentWasRenamed(from: oldFolder, to: newFolder))
    #expect(preservationRaces == 4)
    let current = try #require(store.activeDocument)
    #expect(current.fileURL == sourceURL.standardizedFileURL)
    #expect(current.text == "stale 4")
    #expect(try await recovery.load(for: source.id, epoch: source.recoveryEpoch) == nil)
    #expect(try await recovery.load(for: current.id, epoch: current.recoveryEpoch) == current.text)

    let restored = TabStore(sessionStore: sessions, recoveryBuffer: recovery)
    await restored.restoreSessionIfNeeded()
    #expect(restored.activeDocument?.fileURL == sourceURL.standardizedFileURL)
    #expect(restored.activeDocument?.text == "stale 4")
}
