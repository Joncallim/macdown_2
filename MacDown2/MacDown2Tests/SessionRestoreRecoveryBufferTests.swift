import AppSettings
import FileCore
import FileTree
import Foundation
import Highlighting
@testable import MacDown2
import Testing
import Themes
import Workspace

/// Session restore must read unsaved text from the coordinator's own recovery
/// buffer, not the process-wide shared one (they differ when it is injected).
@MainActor
struct SessionRestoreRecoveryBufferTests {
    @Test func restoreRecoversUnsavedTextFromTheCoordinatorsRecoveryBuffer() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("doc.md")
        try "on disk".write(to: file, atomically: true, encoding: .utf8)
        let buffer = RecoveryBuffer(recoveryDirectory: root.appendingPathComponent("Recovery"))
        let sessionStore = WorkspaceSessionStore(fileURL: root.appendingPathComponent("session.json"))
        let dirty = try FileDocument(fileURL: file, recoveryBuffer: buffer).load().updatingText("unsaved typing")
        let previous = TabStore(sessionStore: sessionStore, recoveryBuffer: buffer)
        previous.newTab(document: dirty)
        #expect(await previous.saveSession())

        let defaults = try #require(UserDefaults(suiteName: "restore-buffer-\(UUID().uuidString)"))
        let preferences = FileTreePreferences(store: UserDefaultsFileTreePreferenceStore(defaults: defaults))
        let coordinator = WindowCoordinator(
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

        await coordinator.restoreSession()
        defer { coordinator.controllers.forEach { $0.close() } }

        #expect(coordinator.controllers.first?.model.activeDocument?.text == "unsaved typing")
    }
}
