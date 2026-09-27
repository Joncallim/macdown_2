import AppSettings
import FileTree
import Foundation
import Highlighting
@testable import MacDown2
import Testing
import Themes
import Workspace

/// Mirrors `CommandPaletteStaleOriginTests`' first two cases for
/// `QuickOpenPanel` (EPIC-22 §6.15, Slice 6b): the panel must never keep
/// pointing at a window that has closed, and closing some OTHER window
/// must not disturb it. `QuickOpenPanel` has no per-row staleness
/// equivalent to the palette's app-command/text-filter cases (it has no
/// "rows built once, invoked later" gap of its own kind — `onOpen` already
/// reads `originController.fileTreeModel.rootAccessURL` live, not a
/// captured value, matching `CommandPaletteView`'s own "live closure, not a
/// snapshot" discipline), so only the origin-window-lifecycle cases apply.
@MainActor
@Suite("Quick Open stale origin")
struct QuickOpenStaleOriginTests {
    private static func makeCoordinatorAndController() -> (WindowCoordinator, WindowController) {
        let preferences = FileTreePreferences()
        let coordinator = WindowCoordinator(
            themeController: ThemeController(),
            grammarRegistry: GrammarRegistry(),
            fileTreePreferences: preferences,
            recentFolderRoots: RecentFolderRoots(preferences: preferences),
            appSettings: AppSettingsModel()
        )
        let controller = WindowController(
            model: coordinator.makeWindowModel(),
            coordinator: coordinator,
            themeController: coordinator.themeController,
            grammarRegistry: coordinator.grammarRegistry,
            fileTreePreferences: preferences
        )
        coordinator.controllers = [controller]
        return (coordinator, controller)
    }

    @Test func closingTheOriginWindowDismissesTheOpenPanelAndDoesNotBlockItsDeallocation() {
        let (coordinator, controller) = Self.makeCoordinatorAndController()
        weak var weakPanel: QuickOpenPanel?
        autoreleasepool {
            var panel: QuickOpenPanel? = QuickOpenPanel(
                coordinator: coordinator,
                originController: controller,
                index: controller.workspaceFileIndex
            )
            coordinator.quickOpen = panel
            weakPanel = panel
            #expect(coordinator.quickOpen != nil)

            // The same call every real close path makes
            // (`WindowController+Close.swift`) before actually closing the
            // window.
            coordinator.removeController(controller)

            #expect(coordinator.quickOpen == nil)
            panel = nil
        }

        // `close()` releases the window through AppKit's autorelease pool
        // rather than deallocating it inline, so the pool above — not just
        // dropping the local reference — is what proves nothing else (in
        // particular, nothing keyed off the now-closed `controller`) still
        // keeps the panel alive.
        #expect(weakPanel == nil)
    }

    @Test func removingAnUnrelatedControllerLeavesTheOpenPanelAlone() {
        let (coordinator, controller) = Self.makeCoordinatorAndController()
        let other = WindowController(
            model: coordinator.makeWindowModel(),
            coordinator: coordinator,
            themeController: coordinator.themeController,
            grammarRegistry: coordinator.grammarRegistry,
            fileTreePreferences: coordinator.fileTreePreferences
        )
        coordinator.controllers.append(other)
        let panel = QuickOpenPanel(
            coordinator: coordinator,
            originController: controller,
            index: controller.workspaceFileIndex
        )
        coordinator.quickOpen = panel

        coordinator.removeController(other)

        #expect(coordinator.quickOpen === panel)
    }
}
