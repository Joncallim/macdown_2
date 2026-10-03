import AppSettings
import FileCore
import FileTree
import Foundation
import Highlighting
@testable import MacDown2
import Testing
import Themes
import Workspace

/// Every close path retires the recovery lifetime (async I/O) and then closes. Text typed in that gap used to be
/// discarded without a prompt on the discard/save/conflict/deleted-file paths; only the clean path rechecked.
@MainActor
struct CloseAfterRetireTests {
    private func makeController() throws -> (coordinator: WindowCoordinator, controller: WindowController) {
        let defaults = try #require(UserDefaults(suiteName: "close-after-retire-\(UUID().uuidString)"))
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
        model.tabStore.newTab(document: FileDocument(text: "one"))
        let controller = WindowController(
            model: model,
            coordinator: coordinator,
            themeController: coordinator.themeController,
            grammarRegistry: coordinator.grammarRegistry,
            fileTreePreferences: preferences
        )
        coordinator.controllers = [controller]
        return (coordinator, controller)
    }

    @Test func anUnchangedDocumentClosesTheWindow() throws {
        let (coordinator, controller) = try makeController()
        let retired = try #require(controller.model.activeDocument)

        controller.closeAfterRetire(of: retired)

        #expect(coordinator.controllers.isEmpty)
    }

    @Test func textTypedAfterTheRetireKeepsTheWindowOpen() throws {
        let (coordinator, controller) = try makeController()
        let retired = try #require(controller.model.activeDocument)
        controller.model.tabStore.updateActiveDocument { $0.updatingText("one, then typed") }
        defer {
            coordinator.removeController(controller)
            controller.close()
        }

        controller.closeAfterRetire(of: retired)

        #expect(coordinator.controllers.contains { $0 === controller })
        #expect(controller.model.activeDocument?.text == "one, then typed")
    }
}
