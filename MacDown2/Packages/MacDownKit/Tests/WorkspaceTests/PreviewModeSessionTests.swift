import FileCore
import Foundation
import Testing
@testable import Workspace

@MainActor
@Suite("PreviewModeSession")
struct PreviewModeSessionTests {
    @Test func tabRecordRoundTripsPreviewMode() throws {
        let record = TabRecord(
            id: UUID(),
            fileURL: URL(fileURLWithPath: "/tmp/doc.html"),
            isPinned: true,
            previewMode: .source
        )
        let data = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(TabRecord.self, from: data)
        #expect(decoded == record)
        #expect(decoded.previewMode == .source)
    }

    @Test func legacyTabRecordDecodesWithoutPreviewMode() throws {
        let id = UUID()
        let json = """
        {"id":"\(id.uuidString)","isPinned":false}
        """
        let data = try #require(json.data(using: .utf8))
        let decoded = try JSONDecoder().decode(TabRecord.self, from: data)
        #expect(decoded.id == id)
        #expect(decoded.previewMode == nil)
    }

    @Test func workspaceTabDefaultsPreviewModeToNil() {
        let tab = WorkspaceTab(document: FileDocument())
        #expect(tab.previewMode == nil)
    }

    @Test func setPreviewModePersistsAcrossSessionRestore() async {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let fileURL = directory.appendingPathComponent("doc.html")
        _ = try? FileStore().write("<p>hi</p>", to: fileURL)

        let sessionStore = WorkspaceSessionStore(fileURL: directory.appendingPathComponent("session.json"))
        let recoveryBuffer = RecoveryBuffer(recoveryDirectory: directory.appendingPathComponent("Recovery"))
        let store = TabStore(sessionStore: sessionStore, recoveryBuffer: recoveryBuffer)
        _ = await store.openFileInTab(fileURL)
        guard let tabID = store.activeTabID else {
            Issue.record("Expected a file tab")
            return
        }

        store.setPreviewMode(.source, for: tabID)
        #expect(store.tabs.first(where: { $0.id == tabID })?.previewMode == .source)
        await store.saveSession()

        let restored = TabStore(sessionStore: sessionStore, recoveryBuffer: recoveryBuffer)
        await restored.restoreSessionIfNeeded()

        #expect(restored.tabs.count == 1)
        #expect(restored.tabs[0].previewMode == .source)
    }

    @Test func togglePinPreservesPreviewMode() async {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let fileURL = directory.appendingPathComponent("doc.html")
        _ = try? FileStore().write("<p>hi</p>", to: fileURL)

        let sessionStore = WorkspaceSessionStore(fileURL: directory.appendingPathComponent("session.json"))
        let recoveryBuffer = RecoveryBuffer(recoveryDirectory: directory.appendingPathComponent("Recovery"))
        let store = TabStore(sessionStore: sessionStore, recoveryBuffer: recoveryBuffer)
        _ = await store.openFileInTab(fileURL)
        guard let tabID = store.activeTabID else {
            Issue.record("Expected a file tab")
            return
        }

        store.setPreviewMode(.rendered, for: tabID)
        store.togglePin(tabID)
        #expect(store.tabs.first(where: { $0.id == tabID })?.previewMode == .rendered)

        // And the mode survives a pin toggle in the other direction.
        store.togglePin(tabID)
        #expect(store.tabs.first(where: { $0.id == tabID })?.previewMode == .rendered)
    }

    @Test func setPreviewModeWritesPreviewModeIntoSession() async {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let fileURL = directory.appendingPathComponent("doc.html")
        _ = try? FileStore().write("<p>hi</p>", to: fileURL)

        let sessionStore = WorkspaceSessionStore(fileURL: directory.appendingPathComponent("session.json"))
        let recoveryBuffer = RecoveryBuffer(recoveryDirectory: directory.appendingPathComponent("Recovery"))
        let store = TabStore(sessionStore: sessionStore, recoveryBuffer: recoveryBuffer)
        _ = await store.openFileInTab(fileURL)
        guard let tabID = store.activeTabID else {
            Issue.record("Expected a file tab")
            return
        }

        store.setPreviewMode(.source, for: tabID)
        await store.saveSession()

        guard let session = sessionStore.loadSession() else {
            Issue.record("Expected a saved session")
            return
        }
        #expect(session.tabs.first?.previewMode == .source)
    }
}
