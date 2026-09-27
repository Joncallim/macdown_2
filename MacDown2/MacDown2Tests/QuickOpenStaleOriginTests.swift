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

    // MARK: - The origin's folder root changes without the window closing

    // A follow-up independent review of this fix flagged that the two
    // tests above only cover `removeController`'s own guard (the window
    // closing) — the actual bug this slice's second review round found and
    // fixed (`WindowController.setFileTreeRoot` calling
    // `closeQuickOpenIfOrigin`) had no permanent regression test of its
    // own. These three close that gap.

    @Test func switchingTheOriginsFolderRootClosesTheOpenPanel() async throws {
        let (coordinator, controller) = Self.makeCoordinatorAndController()
        let firstRoot = try Self.makeTempDirectory()
        let secondRoot = try Self.makeTempDirectory()
        defer {
            try? FileManager.default.removeItem(at: firstRoot)
            try? FileManager.default.removeItem(at: secondRoot)
        }
        await controller.setFileTreeRoot(firstRoot)
        let panel = QuickOpenPanel(
            coordinator: coordinator,
            originController: controller,
            index: controller.workspaceFileIndex
        )
        coordinator.quickOpen = panel

        await controller.setFileTreeRoot(secondRoot)

        #expect(coordinator.quickOpen == nil)
    }

    @Test func closingTheOriginsFolderRootClosesTheOpenPanel() async throws {
        let (coordinator, controller) = Self.makeCoordinatorAndController()
        let root = try Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        await controller.setFileTreeRoot(root)
        let panel = QuickOpenPanel(
            coordinator: coordinator,
            originController: controller,
            index: controller.workspaceFileIndex
        )
        coordinator.quickOpen = panel

        await controller.setFileTreeRoot(nil)

        #expect(coordinator.quickOpen == nil)
    }

    @Test func switchingAnUnrelatedControllersFolderRootLeavesTheOpenPanelAlone() async throws {
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

        let otherRoot = try Self.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: otherRoot) }
        await other.setFileTreeRoot(otherRoot)

        #expect(coordinator.quickOpen === panel)
    }

    private static func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
