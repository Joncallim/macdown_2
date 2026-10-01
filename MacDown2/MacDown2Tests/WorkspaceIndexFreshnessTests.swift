import AppSettings
import FileTree
import Foundation
import Highlighting
@testable import MacDown2
import Testing
import TextSearch
import Themes
import Workspace

/// #183 F18 — Quick Open / Folder Search follow changes after the folder was
/// opened: external edits (refresh on window activation) and this app's own
/// file operations.
@MainActor
@Suite("Workspace index freshness (#183 F18)")
struct WorkspaceIndexFreshnessTests {
    private func makeController(root: URL) async throws -> WindowController {
        let defaults = try #require(UserDefaults(suiteName: "index-freshness-\(UUID().uuidString)"))
        let preferences = FileTreePreferences(store: UserDefaultsFileTreePreferenceStore(defaults: defaults))
        let coordinator = WindowCoordinator(
            sessionStore: WorkspaceSessionStore(fileURL: root.appendingPathComponent("..session-\(UUID().uuidString)")),
            themeController: ThemeController(),
            grammarRegistry: GrammarRegistry(),
            fileTreePreferences: preferences,
            recentFolderRoots: RecentFolderRoots(preferences: preferences),
            recentFileDocuments: RecentFileDocuments(preferences: preferences),
            appSettings: AppSettingsModel(store: UserDefaultsAppSettingsStore(defaults: defaults)),
            workspaceStateStore: WorkspaceStateStore(defaults: defaults)
        )
        let model = coordinator.makeWindowModel()
        model.newDocument()
        let controller = WindowController(
            model: model,
            coordinator: coordinator,
            themeController: ThemeController(),
            grammarRegistry: GrammarRegistry(),
            fileTreePreferences: preferences
        )
        coordinator.controllers = [controller]
        await controller.setFileTreeRoot(root)
        return controller
    }

    private func paths(_ controller: WindowController) async -> Set<String> {
        await Set(controller.workspaceFileIndex.allPaths().map(\.relativePath))
    }

    private func tempRoot(_ files: [String]) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for file in files {
            try Data().write(to: root.appendingPathComponent(file))
        }
        return root
    }

    @Test func aFileAddedByAnotherProgramAppearsAfterTheIndexRefreshes() async throws {
        let root = try tempRoot(["a.md"])
        defer { try? FileManager.default.removeItem(at: root) }
        let controller = try await makeController(root: root)
        #expect(await paths(controller) == ["a.md"])

        try Data().write(to: root.appendingPathComponent("added-externally.md"))
        await controller.refreshWorkspaceIndex()

        #expect(await paths(controller) == ["a.md", "added-externally.md"])
    }

    @Test func aDeletedFileDisappearsAfterTheIndexRefreshes() async throws {
        let root = try tempRoot(["a.md", "b.md"])
        defer { try? FileManager.default.removeItem(at: root) }
        let controller = try await makeController(root: root)

        try FileManager.default.removeItem(at: root.appendingPathComponent("b.md"))
        await controller.refreshWorkspaceIndex()

        #expect(await paths(controller) == ["a.md"])
    }

    @Test func theAppsOwnFileOperationsRefreshTheIndexWithoutAnExplicitCall() async throws {
        let root = try tempRoot(["a.md"])
        defer { try? FileManager.default.removeItem(at: root) }
        let controller = try await makeController(root: root)

        let created = try await controller.fileTreeModel.createFile(in: root.standardizedFileURL)

        var found = false
        for _ in 0 ..< 200 where !found {
            found = await paths(controller).contains(created.url.lastPathComponent)
            if !found {
                try await Task.sleep(for: .milliseconds(25))
            }
        }
        #expect(found)
    }

    @Test func refreshWithoutAnOpenFolderIsANoOp() async throws {
        let root = try tempRoot([])
        defer { try? FileManager.default.removeItem(at: root) }
        let controller = try await makeController(root: root)
        await controller.setFileTreeRoot(nil)

        await controller.refreshWorkspaceIndex()

        #expect(await paths(controller).isEmpty)
    }

    @Test func aRefreshWithinTheMinimumIntervalIsSkipped() async throws {
        let root = try tempRoot(["a.md"])
        defer { try? FileManager.default.removeItem(at: root) }
        let controller = try await makeController(root: root)
        await controller.refreshWorkspaceIndex()
        try Data().write(to: root.appendingPathComponent("late.md"))

        await controller.refreshWorkspaceIndex(minInterval: 60)

        #expect(await paths(controller) == ["a.md"])
    }
}
