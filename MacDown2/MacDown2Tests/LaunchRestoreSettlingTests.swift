import AppSettings
import FileCore
import FileTree
import Foundation
import Highlighting
@testable import MacDown2
import Testing
import Themes
import Workspace

/// A second caller of the unsaved-tabs restore found the launch session already consumed and returned at once, so
/// `application(_:openFiles:)` went on to open its file while the first restore was still creating windows: two
/// windows for one document.
@MainActor
struct LaunchRestoreSettlingTests {
    private func makeCoordinatorWithADirtySession() async throws -> (WindowCoordinator, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("doc.md")
        try "on disk".write(to: file, atomically: true, encoding: .utf8)
        let buffer = RecoveryBuffer(recoveryDirectory: root.appendingPathComponent("Recovery"))
        let sessionStore = WorkspaceSessionStore(fileURL: root.appendingPathComponent("session.json"))
        let dirty = try FileDocument(fileURL: file, recoveryBuffer: buffer).load().updatingText("unsaved")
        let previous = TabStore(sessionStore: sessionStore, recoveryBuffer: buffer)
        previous.newTab(document: dirty)
        #expect(await previous.saveSession())

        let defaults = try #require(UserDefaults(suiteName: "launch-settle-\(UUID().uuidString)"))
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
        return (coordinator, root)
    }

    @Test func everyCallerOfTheUnsavedRestoreReturnsOnlyAfterTheWindowsExist() async throws {
        let (coordinator, root) = try await makeCoordinatorWithADirtySession()
        defer {
            coordinator.controllers.forEach { $0.close() }
            try? FileManager.default.removeItem(at: root)
        }

        let callers = (0 ..< 3).map { _ in
            Task { @MainActor in
                await coordinator.restoreUnsavedSessionTabs()
                return coordinator.controllers.count
            }
        }
        var counts: [Int] = []
        for caller in callers {
            await counts.append(caller.value)
        }

        #expect(counts == [1, 1, 1])
    }
}
