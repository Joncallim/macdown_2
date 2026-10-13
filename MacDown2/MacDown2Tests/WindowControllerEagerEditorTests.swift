import AppSettings
import EditorCore
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
///
/// The first real XCUITest run then found the opposite failure: when the editor pane IS shown, SwiftUI mounts the
/// `EditorView` while `WindowController.init` builds the window — before `makeSessionsForActiveTab` runs — and that
/// call re-marked the already-mounted system detached, refusing Bold/Text Filter/snippets for the window's lifetime.
/// The original test only passed because of that bug: it used the default (editor-showing) layout, so its "no
/// EditorView has mounted yet" premise was false. It now opens the tab in Preview Only, where that premise holds.
@MainActor
struct WindowControllerEagerEditorTests {
    @Test func theEagerlyCreatedEditorSystemRefusesCommandEditsUntilAnEditorViewMounts() throws {
        let fixture = try makeController(layout: .previewOnly)
        let (coordinator, controller, system) = (fixture.coordinator, fixture.controller, fixture.system)
        defer {
            coordinator.removeController(controller)
            controller.close()
        }

        #expect(system.isDetachedFromEditorView, "no EditorView has mounted yet")
        #expect(!system.canApplyCommandEdit)
        #expect(coordinator.textFilterCoordinator.editingTarget(for: controller) == nil)
    }

    @Test func anEditorViewMountedWhileTheWindowIsBuiltIsNotReMarkedDetached() throws {
        let fixture = try makeController(layout: .split(fraction: 0.5))
        let (coordinator, controller, system) = (fixture.coordinator, fixture.controller, fixture.system)
        defer {
            coordinator.removeController(controller)
            controller.close()
        }

        #expect(!system.isDetachedFromEditorView, "the editor pane's EditorView mounted during WindowController.init")
        #expect(system.canApplyCommandEdit)
        #expect(coordinator.textFilterCoordinator.editingTarget(for: controller) != nil)
    }

    private func makeController(
        layout: PreviewLayoutMode
    ) throws -> Fixture {
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
        let tabID = try #require(model.tabStore.activeTab?.id)
        model.tabStore.setPreviewLayout(layout, for: tabID)
        let controller = WindowController(
            model: model,
            coordinator: coordinator,
            themeController: coordinator.themeController,
            grammarRegistry: coordinator.grammarRegistry,
            fileTreePreferences: preferences
        )
        coordinator.controllers = [controller]
        let system = try #require(controller.editorStore.existingSystem(for: tabID.uuidString))
        return Fixture(coordinator: coordinator, controller: controller, system: system)
    }

    private struct Fixture {
        let coordinator: WindowCoordinator
        let controller: WindowController
        let system: EditorTextSystem
    }
}
