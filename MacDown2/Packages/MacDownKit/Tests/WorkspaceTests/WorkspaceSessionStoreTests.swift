import Foundation
import Testing
@testable import Workspace

@MainActor
@Suite("WorkspaceSessionStore")
struct WorkspaceSessionStoreTests {
    @Test func roundTripInTempDirectory() {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let url = directory.appendingPathComponent("session.json")

        let store = WorkspaceSessionStore(fileURL: url)
        let session = WorkspaceSession(
            tabs: [
                TabRecord(id: UUID(), fileURL: URL(fileURLWithPath: "/tmp/a.md"), isPinned: true),
                TabRecord(id: UUID(), untitledDocumentID: "uuid-1", isPinned: false),
            ],
            activeTabID: nil
        )

        store.saveSession(session)
        let loaded = store.loadSession()

        #expect(loaded == session)
    }

    @Test func atomicWriteLeavesNoTempFile() {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let url = directory.appendingPathComponent("session.json")

        let store = WorkspaceSessionStore(fileURL: url)
        store.saveSession(WorkspaceSession())

        let tmpURL = url.appendingPathExtension("tmp")
        #expect(FileManager.default.fileExists(atPath: tmpURL.path) == false)
    }

    /// Regression test: repeated saves to the same file must replace the prior
    /// contents. A previous implementation used a manual temp+`moveItem`, which
    /// fails once the destination exists and silently froze the file at its
    /// first-written value (the UI test caught `activeTabID` never updating).
    @Test func repeatedSaveOverwritesExistingFile() {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let url = directory.appendingPathComponent("session.json")

        let store = WorkspaceSessionStore(fileURL: url)
        let firstActiveID = UUID()
        let secondActiveID = UUID()

        store.saveSession(WorkspaceSession(
            tabs: [TabRecord(id: firstActiveID, fileURL: URL(fileURLWithPath: "/tmp/a.md"))],
            activeTabID: firstActiveID
        ))
        store.saveSession(WorkspaceSession(
            tabs: [TabRecord(id: secondActiveID, fileURL: URL(fileURLWithPath: "/tmp/b.md"))],
            activeTabID: secondActiveID
        ))

        let loaded = store.loadSession()
        #expect(loaded?.activeTabID == secondActiveID)
        #expect(loaded?.tabs.map(\.id) == [secondActiveID])
    }

    @Test func missingFileReturnsNil() {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let url = directory.appendingPathComponent("session.json")

        let store = WorkspaceSessionStore(fileURL: url)
        #expect(store.loadSession() == nil)
    }

    @Test func corruptFileReturnsNil() {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let url = directory.appendingPathComponent("session.json")

        try? "not json".write(to: url, atomically: true, encoding: .utf8)

        let store = WorkspaceSessionStore(fileURL: url)
        #expect(store.loadSession() == nil)
    }

    @Test func unknownVersionReturnsNil() {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let url = directory.appendingPathComponent("session.json")

        let future = WorkspaceSession(version: 999, tabs: [])
        let store = WorkspaceSessionStore(fileURL: url)
        store.saveSession(future)

        #expect(store.loadSession() == nil)
    }
}
