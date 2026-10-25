import AppSettings
import FileCore
import FileTree
import Foundation
import Highlighting
@testable import MacDown2
import Testing
import Themes
import Workspace

@MainActor
@Suite("Disabled validated export origin")
struct ValidatedExportOriginTests {
    @Test func freezesAfterPanelAndRevokesBeforeIdentityPublication() throws {
        let preferences = FileTreePreferences()
        let coordinator = WindowCoordinator(
            themeController: ThemeController(), grammarRegistry: GrammarRegistry(),
            fileTreePreferences: preferences,
            recentFolderRoots: RecentFolderRoots(preferences: preferences),
            recentFileDocuments: RecentFileDocuments(preferences: preferences),
            appSettings: AppSettingsModel()
        )
        let model = coordinator.makeWindowModel()
        let original = FileDocument(text: "initial")
        model.tabStore.newTab(document: original)
        let controller = WindowController(
            model: model, coordinator: coordinator,
            themeController: coordinator.themeController,
            grammarRegistry: coordinator.grammarRegistry,
            fileTreePreferences: preferences
        )
        coordinator.controllers = [controller]
        defer {
            coordinator.removeController(controller)
            controller.close()
        }

        // The panel may suspend before this live value is frozen.
        let origin = try #require(controller.captureValidatedExportOrigin())
        model.tabStore.updateActiveDocument { $0.updatingText("edited during panel") }
        let request = try origin.freezeRequest()
        model.tabStore.updateActiveDocument { $0.updatingText("edited during render") }
        #expect(request.text == "edited during panel")
        #expect(request.sourceGeneration != model.activeDocument?.mutationGeneration)

        var revokedBeforePublication = false
        controller.previewResourceState.afterIdentityInvalidation = {
            revokedBeforePublication = model.activeDocument?.id == original.id
                && (try? origin.lease.checkActive()) == nil
        }
        let replacement = FileDocument(text: "other")
        model.tabStore.updateActiveDocument { _ in replacement }
        #expect(revokedBeforePublication)
        #expect(throws: CancellationError.self) { try origin.freezeRequest() }
    }
}
