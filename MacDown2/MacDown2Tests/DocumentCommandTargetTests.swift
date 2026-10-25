import AppKit
import AppSettings
import FileCore
import FileTree
import Highlighting
@testable import MacDown2
import Testing
import Themes

@MainActor
@Suite("Document command target")
struct DocumentCommandTargetTests {
    private final class VisiblePanel: NSPanel {
        override var isVisible: Bool {
            true
        }
    }

    @Test func dismissedPanelFallsBackToTheManagedMainDocument() throws {
        let preferences = FileTreePreferences()
        let coordinator = WindowCoordinator(
            themeController: ThemeController(),
            grammarRegistry: GrammarRegistry(),
            fileTreePreferences: preferences,
            recentFolderRoots: RecentFolderRoots(preferences: preferences),
            recentFileDocuments: RecentFileDocuments(preferences: preferences),
            appSettings: AppSettingsModel()
        )
        func makeController(_ name: String) -> WindowController {
            let model = coordinator.makeWindowModel()
            model.tabStore.newTab(document: FileDocument(text: "# \(name)\n"))
            return WindowController(
                model: model, coordinator: coordinator,
                themeController: coordinator.themeController,
                grammarRegistry: coordinator.grammarRegistry,
                fileTreePreferences: preferences
            )
        }
        let first = makeController("first")
        let second = makeController("second")
        coordinator.controllers = [first, second]
        defer {
            first.close()
            second.close()
        }
        let firstWindow = try #require(first.window)
        let secondWindow = try #require(second.window)
        let dismissedPanel = NSPanel(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: true)
        let visiblePanel = VisiblePanel(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: true)

        // Save and Export must target the same document, not a stale keyModel
        // from another tab or a window that already closed.
        #expect(coordinator.currentCommandController(keyWindow: dismissedPanel, mainWindow: secondWindow) === second)
        #expect(coordinator.currentCommandController(keyWindow: firstWindow, mainWindow: secondWindow) === first)
        #expect(coordinator.currentCommandController(keyWindow: nil, mainWindow: secondWindow) === second)
        #expect(coordinator.currentCommandController(keyWindow: dismissedPanel, mainWindow: nil) == nil)
        #expect(coordinator.currentCommandController(keyWindow: visiblePanel, mainWindow: secondWindow) == nil)
    }
}
