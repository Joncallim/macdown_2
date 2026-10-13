import AppSettings
import FileCore
import FileTree
import Foundation
import Highlighting
@testable import MacDown2
import Testing
import Themes
import Workspace

/// PR #468 review: telling launch that the welcome window already opened a document must skip only the Untitled
/// fallback of an EMPTY session; a real saved session is still restored.
@MainActor
struct WelcomeLaunchSessionTests {
    private func makeCoordinator(root _: URL, buffer: RecoveryBuffer, sessionStore: WorkspaceSessionStore) throws
        -> WindowCoordinator {
        let defaults = try #require(UserDefaults(suiteName: "welcome-launch-\(UUID().uuidString)"))
        let preferences = FileTreePreferences(store: UserDefaultsFileTreePreferenceStore(defaults: defaults))
        return WindowCoordinator(
            sessionStore: sessionStore,
            recoveryBuffer: buffer,
            themeController: ThemeController(),
            grammarRegistry: GrammarRegistry(),
            fileTreePreferences: preferences,
            recentFolderRoots: RecentFolderRoots(preferences: preferences),
            recentFileDocuments: RecentFileDocuments(preferences: preferences),
            appSettings: AppSettingsModel(store: UserDefaultsAppSettingsStore(defaults: defaults)),
            workspaceStateStore: WorkspaceStateStore(defaults: defaults)
        )
    }

    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    @Test func anEmptySessionOpensNoSecondUntitledDocumentWhenOneIsAlreadyOpen() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let buffer = RecoveryBuffer(recoveryDirectory: root.appendingPathComponent("Recovery"))
        let coordinator = try makeCoordinator(
            root: root, buffer: buffer,
            sessionStore: WorkspaceSessionStore(fileURL: root.appendingPathComponent("session.json"))
        )
        defer { coordinator.controllers.forEach { $0.close() } }

        await coordinator.restoreSession(createsUntitledWhenEmpty: false)

        #expect(coordinator.controllers.isEmpty, "the document the welcome choice opened is the only one")
    }

    @Test func anEmptySessionStillOpensUntitledByDefault() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let buffer = RecoveryBuffer(recoveryDirectory: root.appendingPathComponent("Recovery"))
        let coordinator = try makeCoordinator(
            root: root, buffer: buffer,
            sessionStore: WorkspaceSessionStore(fileURL: root.appendingPathComponent("session.json"))
        )
        defer { coordinator.controllers.forEach { $0.close() } }

        await coordinator.restoreSession()

        #expect(coordinator.controllers.count == 1)
    }

    @Test func aRealSavedSessionIsStillRestoredWhenADocumentIsAlreadyOpen() async throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("doc.md")
        try "on disk".write(to: file, atomically: true, encoding: .utf8)
        let buffer = RecoveryBuffer(recoveryDirectory: root.appendingPathComponent("Recovery"))
        let sessionStore = WorkspaceSessionStore(fileURL: root.appendingPathComponent("session.json"))
        let previous = TabStore(sessionStore: sessionStore, recoveryBuffer: buffer)
        try previous.newTab(document: FileDocument(fileURL: file, recoveryBuffer: buffer).load())
        #expect(await previous.saveSession())
        let coordinator = try makeCoordinator(root: root, buffer: buffer, sessionStore: sessionStore)
        defer { coordinator.controllers.forEach { $0.close() } }

        await coordinator.restoreSession(createsUntitledWhenEmpty: false)

        #expect(coordinator.controllers.count == 1, "the saved file tab comes back")
        #expect(coordinator.controllers.first?.model.activeDocument?.fileURL?.lastPathComponent == "doc.md")
    }
}
