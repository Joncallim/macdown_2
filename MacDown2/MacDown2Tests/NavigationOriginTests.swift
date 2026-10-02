import AppSettings
import FileTree
import Foundation
import Highlighting
@testable import MacDown2
import Testing
import Themes
import Workspace

/// #183 F19 — results opened from Quick Open / Folder Search keep the folder's
/// own identity, and a root switch invalidates Quick Open before anything else.
@MainActor
@Suite("Navigation origin (#183 F19)")
struct NavigationOriginTests {
    private func makeController() -> (WindowCoordinator, WindowController) {
        let preferences = FileTreePreferences()
        let coordinator = WindowCoordinator(
            themeController: ThemeController(),
            grammarRegistry: GrammarRegistry(),
            fileTreePreferences: preferences,
            recentFolderRoots: RecentFolderRoots(preferences: preferences),
            recentFileDocuments: RecentFileDocuments(preferences: preferences),
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

    private func tempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func aSymlinkRootKeepsItsLexicalPathForFolderSearchWhileSearchingThePhysicalRoot() async throws {
        let base = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: base) }
        let real = base.appendingPathComponent("real", isDirectory: true)
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        let link = base.appendingPathComponent("link", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        let (_, controller) = makeController()

        await controller.setFileTreeRoot(link, accessURL: real)

        #expect(controller.folderSearchModel.lexicalRoot == link.standardizedFileURL)
        #expect(controller.folderSearchModel.root == controller.fileTreeModel.rootAccessURL)
        #expect(controller.folderSearchModel.root != controller.folderSearchModel.lexicalRoot)
    }

    @Test func clearingTheRootClearsTheLexicalRootToo() async throws {
        let base = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: base) }
        let (_, controller) = makeController()
        await controller.setFileTreeRoot(base)
        #expect(controller.folderSearchModel.lexicalRoot != nil)

        await controller.setFileTreeRoot(nil)

        #expect(controller.folderSearchModel.lexicalRoot == nil)
    }

    @Test func aRootSwitchClosesAnOpenQuickOpenPanel() async throws {
        let first = try tempDirectory()
        let second = try tempDirectory()
        defer {
            try? FileManager.default.removeItem(at: first)
            try? FileManager.default.removeItem(at: second)
        }
        let (coordinator, controller) = makeController()
        await controller.setFileTreeRoot(first)
        let panel = QuickOpenPanel(
            coordinator: coordinator,
            originController: controller,
            index: controller.workspaceFileIndex
        )
        coordinator.quickOpen = panel

        await controller.setFileTreeRoot(second)

        #expect(coordinator.quickOpen == nil)
    }
}
