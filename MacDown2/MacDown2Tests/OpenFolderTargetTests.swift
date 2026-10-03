import AppSettings
import FileTree
import Foundation
import Highlighting
@testable import MacDown2
import Testing
import Themes
import Workspace

/// "Open Folder…" silently did nothing unless a document window was the key window (it is not when Settings
/// or the welcome window is key, or when no window is open at all).
@MainActor
struct OpenFolderTargetTests {
    private func makeCoordinator() throws -> WindowCoordinator {
        let defaults = try #require(UserDefaults(suiteName: "open-folder-\(UUID().uuidString)"))
        let preferences = FileTreePreferences(store: UserDefaultsFileTreePreferenceStore(defaults: defaults))
        return WindowCoordinator(
            themeController: ThemeController(),
            grammarRegistry: GrammarRegistry(),
            fileTreePreferences: preferences,
            recentFolderRoots: RecentFolderRoots(preferences: preferences),
            recentFileDocuments: RecentFileDocuments(preferences: preferences),
            appSettings: AppSettingsModel(store: UserDefaultsAppSettingsStore(defaults: defaults)),
            workspaceStateStore: WorkspaceStateStore(defaults: defaults)
        )
    }

    private func makeFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    @Test func withADocumentWindowButNoKeyWindowTheFolderOpensInThatWindow() throws {
        let coordinator = try makeCoordinator()
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let controller = WindowController(
            model: coordinator.makeWindowModel(),
            coordinator: coordinator,
            themeController: coordinator.themeController,
            grammarRegistry: coordinator.grammarRegistry,
            fileTreePreferences: coordinator.fileTreePreferences
        )
        coordinator.controllers = [controller]
        defer { controller.close() }

        coordinator.openFolder(folder)

        #expect(controller.model.folderURL?.standardizedFileURL == folder.standardizedFileURL)
    }

    @Test func withNoWindowAtAllAnUntitledWindowIsCreatedToHoldTheFolder() throws {
        let coordinator = try makeCoordinator()
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        coordinator.openFolder(folder)
        defer { coordinator.controllers.forEach { $0.close() } }

        #expect(coordinator.controllers.count == 1)
        #expect(coordinator.controllers.first?.model.folderURL?.standardizedFileURL == folder.standardizedFileURL)
    }
}
