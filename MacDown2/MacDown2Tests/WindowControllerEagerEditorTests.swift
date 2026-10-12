import AppSettings
import FileCore
import FileTree
import Foundation
import Highlighting
@testable import MacDown2
import Testing
import Themes
import Workspace

/// Round-7 review (54b06b3a) P2: the window creates the active tab's text system eagerly, before any `EditorView`
/// mounts; a window opened or restored in Preview Only never mounts one, so command edits (Text Filter, snippet,
/// Convert Line Endings) were accepted, applied to the hidden view only, and lost on the next mount.
@MainActor
struct WindowControllerEagerEditorTests {
    @Test func theEagerlyCreatedEditorSystemRefusesCommandEditsUntilAnEditorViewMounts() throws {
        let defaults = try #require(UserDefaults(suiteName: "eager-editor-\(UUID().uuidString)"))
        let preferences = FileTreePreferences(store: UserDefaultsFileTreePreferenceStore(defaults: defaults))
        let coordinator = WindowCoordinator(
            themeController: ThemeController(),
            grammarRegistry: GrammarRegistry(),
            fileTreePreferences: preferences,
            recentFolderRoots: RecentFolderRoots(preferences: preferences),
            recentFileDocuments: RecentFileDocuments(preferences: preferences),
            appSettings: AppSettingsModel(store: UserDefaultsAppSettingsStore(defaults: defaults)),
            workspaceStateStore: WorkspaceStateStore(defaults: defaults)
        )
        let model = coordinator.makeWindowModel()
        model.tabStore.newTab(document: FileDocument(text: "a\r\nb\r\n"))
        let controller = WindowController(
            model: model,
            coordinator: coordinator,
            themeController: coordinator.themeController,
            grammarRegistry: coordinator.grammarRegistry,
            fileTreePreferences: preferences
        )
        coordinator.controllers = [controller]
        defer {
            coordinator.removeController(controller)
            controller.close()
        }
        let tabID = try #require(model.tabStore.activeTab?.id)
        let system = try #require(controller.editorStore.existingSystem(for: tabID.uuidString))

        #expect(system.isDetachedFromEditorView, "no EditorView has mounted yet")
        #expect(!system.canApplyCommandEdit)
        #expect(coordinator.textFilterCoordinator.editingTarget(for: controller) == nil)
    }
}
