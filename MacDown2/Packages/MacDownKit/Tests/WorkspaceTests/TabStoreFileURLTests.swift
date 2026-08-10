import FileCore
import Foundation
import Testing
@testable import Workspace

@MainActor
@Test func documentFileIntentsUseStandardizedURLs() {
    let store = TabStore(sessionStore: FakeSessionStore())
    let url = URL(fileURLWithPath: "/tmp/../tmp/notes.md")
    let document = FileDocument(fileURL: url, text: "notes")
    store.newTab(document: document)
    #expect(store.activeTabID != nil)
    let id = store.activeTabID ?? UUID()
    #expect(store.tabID(forFileURL: URL(fileURLWithPath: "/tmp/notes.md")) == id)

    store.documentWasRenamed(from: URL(fileURLWithPath: "/tmp/notes.md"), to: URL(fileURLWithPath: "/tmp/notes.txt"))
    #expect(store.activeDocument?.fileURL?.lastPathComponent == "notes.txt")
    #expect(store.documentFileWasDeleted(at: URL(fileURLWithPath: "/tmp/notes.txt")) == .closedCleanTab(id))
}

@MainActor
@Test func folderRenameAndDeletionApplyToDescendantOpenDocuments() throws {
    let store = TabStore(sessionStore: FakeSessionStore())
    let oldFolder = URL(fileURLWithPath: "/tmp/project", isDirectory: true)
    let oldFile = oldFolder.appendingPathComponent("nested/notes.md")
    let document = FileDocument(fileURL: oldFile, text: "notes")
    store.newTab(document: document)

    let newFolder = URL(fileURLWithPath: "/tmp/renamed-project", isDirectory: true)
    store.documentWasRenamed(from: oldFolder, to: newFolder)
    let newFile = newFolder.appendingPathComponent("nested/notes.md")
    #expect(store.activeDocument?.fileURL == newFile.standardizedFileURL)

    let id = store.activeTabID
    #expect(try store.documentFileWasDeleted(at: newFolder) == .closedCleanTab(#require(id)))
}

@MainActor
@Test func folderRenamePreservesDirtyStateForADescendantDocument() {
    let store = TabStore(sessionStore: FakeSessionStore())
    let oldFolder = URL(fileURLWithPath: "/tmp/dirty-project", isDirectory: true)
    let document = FileDocument(fileURL: oldFolder.appendingPathComponent("notes.md"), text: "notes")
        .updatingText("changed")
    store.newTab(document: document)

    let newFolder = URL(fileURLWithPath: "/tmp/renamed-dirty-project", isDirectory: true)
    store.documentWasRenamed(from: oldFolder, to: newFolder)

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
