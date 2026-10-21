import AppSettings
import FileTree
import Foundation
import Highlighting
@testable import MacDown2
import Testing
import TextSearch
import Themes
import Workspace

@MainActor
@Suite("Workspace index root publication")
struct WorkspaceIndexRootPublicationTests {
    private func controllerFixture(index: WorkspaceFileIndex) throws -> ControllerFixture {
        let suiteName = "index-publication-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let preferences = FileTreePreferences(store: UserDefaultsFileTreePreferenceStore(defaults: defaults))
        let stateDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("index-session-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: stateDirectory, withIntermediateDirectories: true)
        let coordinator = WindowCoordinator(
            sessionStore: WorkspaceSessionStore(fileURL: stateDirectory.appendingPathComponent("session.json")),
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
            fileTreePreferences: preferences,
            workspaceFileIndex: index
        )
        coordinator.controllers = [controller]
        return ControllerFixture(
            controller: controller,
            coordinator: coordinator,
            defaults: defaults,
            suiteName: suiteName,
            stateDirectory: stateDirectory
        )
    }

    private func tempRoot(_ files: [String]) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for file in files {
            try Data().write(to: root.appendingPathComponent(file))
        }
        return root
    }

    private func paths(_ controller: WindowController) async -> Set<String> {
        await Set(controller.workspaceFileIndex.allPaths().map(\.relativePath))
    }

    @Test func activationRefreshDuringRootChangeDoesNotUseThePreviousRoot() async throws {
        let rootA = try tempRoot(["a.md"])
        let rootB = try tempRoot(["b.md"])
        defer {
            try? FileManager.default.removeItem(at: rootA)
            try? FileManager.default.removeItem(at: rootB)
        }
        let probe = IndexWalkProbe()
        let fixture = try controllerFixture(index: probe.makeIndex())
        defer { fixture.retire() }
        let controller = fixture.controller
        await controller.setFileTreeRoot(rootA)

        let gate = FolderSearchGate()
        controller.beforeRootRebuild = { await gate.wait() }
        defer { controller.beforeRootRebuild = nil }
        let changingRoot = Task { await controller.setFileTreeRoot(rootB) }
        guard await FolderSearchGate.waitForEntry(gate.entered) else {
            gate.release()
            await changingRoot.value
            Issue.record("the root change did not pause before replacing the file-tree root")
            return
        }

        // A closed search scope makes an accidental publication of the still-
        // current file-tree root observable while the new root request waits.
        controller.folderSearchModel.setRoot(nil)
        await controller.refreshWorkspaceIndex(minInterval: 60)
        #expect(controller.fileTreeModel.rootAccessURL == rootA.standardizedFileURL)
        #expect(controller.folderSearchModel.root == nil)
        #expect(controller.lastWorkspaceIndexRefreshRoot == nil)
        #expect(probe.count == 1)

        gate.release()
        await changingRoot.value

        #expect(controller.fileTreeModel.rootAccessURL == rootB.standardizedFileURL)
        #expect(controller.folderSearchModel.root == rootB.standardizedFileURL)
        #expect(controller.lastWorkspaceIndexRefreshRoot == rootB.standardizedFileURL)
        #expect(probe.count == 2)
        #expect(await paths(controller) == ["b.md"])
    }

    @Test func activationRefreshUsesRootAfterAcceptedFolderRemap() async throws {
        let rootA = try tempRoot(["b.md"])
        let rootB = rootA.deletingLastPathComponent()
            .appendingPathComponent("remapped-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: rootA)
            try? FileManager.default.removeItem(at: rootB)
        }
        let probe = IndexWalkProbe()
        let fixture = try controllerFixture(index: probe.makeIndex())
        defer { fixture.retire() }
        let controller = fixture.controller
        await controller.setFileTreeRoot(rootA)
        #expect(probe.count == 1)

        try FileManager.default.moveItem(at: rootA, to: rootB)
        fixture.coordinator.remapFolderRootsAfterAcceptedMove(from: rootA, to: rootB)
        #expect(controller.fileTreeModel.rootAccessURL == rootB.standardizedFileURL)

        await controller.refreshWorkspaceIndex(minInterval: 60)

        #expect(probe.count == 2)
        #expect(controller.lastWorkspaceIndexRefreshRoot == rootB.standardizedFileURL)
        #expect(await paths(controller) == ["b.md"])
    }
}
