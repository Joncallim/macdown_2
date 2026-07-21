import FileCore
import Foundation
import Testing
@testable import Workspace

@MainActor
@Suite("TabStoreSession")
struct TabStoreSessionTests {
    @Test func sessionRoundTripRestoresTabsOrderAndActiveTab() async {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let fileURL = directory.appendingPathComponent("saved.md")
        try? FileStore().write("file", to: fileURL)

        let sessionStore = WorkspaceSessionStore(fileURL: directory.appendingPathComponent("session.json"))
        let store = TabStore(sessionStore: sessionStore)
        store.newTab()
        store.updateActiveDocument { $0.updatingText("untitled") }
        let untitledID = store.tabs[0].id
        _ = await store.openFileInTab(fileURL)
        guard let fileTabID = store.activeTabID else {
            Issue.record("Expected file tab to be active")
            return
        }
        store.togglePin(fileTabID)
        store.activate(untitledID)

        await store.saveSession()

        let restored = TabStore(sessionStore: sessionStore)
        await restored.restoreSessionIfNeeded()

        #expect(restored.tabs.count == 2)
        #expect(restored.tabs[0].id == fileTabID)
        #expect(restored.tabs[0].document.fileURL == fileURL)
        #expect(restored.tabs[0].document.text == "file")
        #expect(restored.tabs[0].document.state == .clean)
        #expect(restored.tabs[0].isPinned)
        #expect(restored.tabs[1].id == untitledID)
        #expect(restored.tabs[1].document.fileURL == nil)
        #expect(restored.tabs[1].document.text == "untitled")
        #expect(restored.tabs[1].document.state == .dirty)
        #expect(restored.activeTabID == untitledID)
    }

    @Test func restoreDropsMissingFileTab() async {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let fileURL = directory.appendingPathComponent("gone.md")
        let sessionStore = WorkspaceSessionStore(fileURL: directory.appendingPathComponent("session.json"))
        let store = TabStore(sessionStore: sessionStore)
        store.newTab()
        let untitledID = store.tabs[0].id
        store.updateActiveDocument { $0.updatingText("untitled") }
        await store.saveSession()

        guard var session = sessionStore.loadSession() else {
            Issue.record("Expected session to be saved")
            return
        }
        session.tabs.append(TabRecord(id: UUID(), fileURL: fileURL, isPinned: false))
        sessionStore.saveSession(session)

        let restored = TabStore(sessionStore: sessionStore)
        await restored.restoreSessionIfNeeded()

        #expect(restored.tabs.count == 1)
        #expect(restored.tabs.first?.id == untitledID)
    }

    @Test func restoreDropsUntitledWithoutRecovery() async {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let sessionStore = WorkspaceSessionStore(fileURL: directory.appendingPathComponent("session.json"))
        sessionStore.saveSession(WorkspaceSession(
            tabs: [TabRecord(id: UUID(), untitledDocumentID: "no-such-buffer", isPinned: false)],
            activeTabID: nil
        ))

        let store = TabStore(sessionStore: sessionStore)
        await store.restoreSessionIfNeeded()

        #expect(store.tabs.isEmpty)
    }

    @Test func restoreCorruptSessionIsEmpty() async {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let url = directory.appendingPathComponent("session.json")
        try? "not json".write(to: url, atomically: true, encoding: .utf8)

        let store = TabStore(sessionStore: WorkspaceSessionStore(fileURL: url))
        await store.restoreSessionIfNeeded()

        #expect(store.tabs.isEmpty)
    }

    @Test func saveSessionAutosavesDirtyFileTab() async {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let fileURL = directory.appendingPathComponent("doc.md")
        try? FileStore().write("disk", to: fileURL)

        let sessionStore = WorkspaceSessionStore(fileURL: directory.appendingPathComponent("session.json"))
        let store = TabStore(sessionStore: sessionStore)
        _ = await store.openFileInTab(fileURL)
        store.updateActiveDocument { $0.updatingText("dirty") }

        await store.saveSession()

        let recovered = try? await RecoveryBuffer.shared.load(for: store.tabs[0].document.id)
        #expect(recovered == "dirty")
    }

    @Test func saveSessionAutosavesUntitledDirtyTab() async {
        let store = TabStore(sessionStore: FakeSessionStore())
        store.newTab()
        store.updateActiveDocument { $0.updatingText("untitled dirty") }

        await store.saveSession()

        let recovered = try? await RecoveryBuffer.shared.load(for: store.tabs[0].document.id)
        #expect(recovered == "untitled dirty")
    }
}
