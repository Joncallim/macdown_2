import AppKit
import AppSettings
import FileTree
import Foundation
import Highlighting
@testable import MacDown2
import Testing
import TextSearch
import Themes
import Workspace

/// Existing workspace-index refresh behavior remains intact around the
/// activation freshness optimization.
@MainActor
@Suite("Workspace index refresh behavior")
struct WorkspaceIndexRefreshBehaviorTests {
    private func makeController(
        root: URL,
        index: WorkspaceFileIndex = WorkspaceFileIndex()
    ) async throws -> ControllerFixture {
        let suiteName = "index-refresh-\(UUID().uuidString)"
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
        await controller.setFileTreeRoot(root)
        return ControllerFixture(
            controller: controller,
            coordinator: coordinator,
            defaults: defaults,
            suiteName: suiteName,
            stateDirectory: stateDirectory
        )
    }

    private func paths(_ controller: WindowController) async -> Set<String> {
        await Set(controller.workspaceFileIndex.allPaths().map(\.relativePath))
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

    @Test func aFileAddedByAnotherProgramAppearsAfterTheIndexRefreshes() async throws {
        let root = try tempRoot(["a.md"])
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = try await makeController(root: root)
        defer { fixture.retire() }
        let controller = fixture.controller
        #expect(await paths(controller) == ["a.md"])

        try Data().write(to: root.appendingPathComponent("added-externally.md"))
        await controller.refreshWorkspaceIndex()

        #expect(await paths(controller) == ["a.md", "added-externally.md"])
    }

    @Test func aDeletedFileDisappearsAfterTheIndexRefreshes() async throws {
        let root = try tempRoot(["a.md", "b.md"])
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = try await makeController(root: root)
        defer { fixture.retire() }
        let controller = fixture.controller

        try FileManager.default.removeItem(at: root.appendingPathComponent("b.md"))
        await controller.refreshWorkspaceIndex()

        #expect(await paths(controller) == ["a.md"])
    }

    @Test func theAppsOwnFileOperationsRefreshTheIndexWithoutAnExplicitCall() async throws {
        let root = try tempRoot(["a.md"])
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = try await makeController(root: root)
        defer { fixture.retire() }
        let controller = fixture.controller

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
        let fixture = try await makeController(root: root)
        defer { fixture.retire() }
        let controller = fixture.controller
        await controller.setFileTreeRoot(nil)

        await controller.refreshWorkspaceIndex()

        #expect(await paths(controller).isEmpty)
    }

    @Test func aRefreshWithinTheMinimumIntervalIsSkipped() async throws {
        let root = try tempRoot(["a.md"])
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = try await makeController(root: root)
        defer { fixture.retire() }
        let controller = fixture.controller
        await controller.refreshWorkspaceIndex()
        try Data().write(to: root.appendingPathComponent("late.md"))

        await controller.refreshWorkspaceIndex(minInterval: 60)

        #expect(await paths(controller) == ["a.md"])
    }

    @Test func successfulInitialBuildMakesActivationRefreshSkipTheDuplicateWalk() async throws {
        let root = try tempRoot(["a.md"])
        defer { try? FileManager.default.removeItem(at: root) }
        let probe = IndexWalkProbe()
        let fixture = try await makeController(root: root, index: probe.makeIndex())
        defer { fixture.retire() }
        let controller = fixture.controller
        await controller.refreshWorkspaceIndex(minInterval: 60)

        #expect(probe.count == 1)
        #expect(controller.lastWorkspaceIndexRefresh != nil)
        #expect(await paths(controller) == ["a.md"])
    }

    @Test func failedForcedRefreshInvalidatesFreshnessSoActivationRetries() async throws {
        let root = try tempRoot(["a.md"])
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path)
            try? FileManager.default.removeItem(at: root)
        }
        let probe = IndexWalkProbe(unreadableRoot: root, unreadableWalkNumber: 2)
        let fixture = try await makeController(root: root, index: probe.makeIndex())
        defer { fixture.retire() }
        let controller = fixture.controller
        #expect(probe.count == 1)
        #expect(controller.lastWorkspaceIndexRefresh != nil)
        #expect(await paths(controller) == ["a.md"])

        await controller.refreshWorkspaceIndex()

        guard case .failed = await controller.workspaceFileIndex.state else {
            Issue.record("the forced refresh should fail after access is removed")
            return
        }
        #expect(probe.permissionChangeSucceeded)
        #expect(controller.lastWorkspaceIndexRefresh == nil)
        #expect(controller.lastWorkspaceIndexRefreshRoot == nil)
        #expect(controller.lastWorkspaceIndexRefreshGeneration == nil)

        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path)
        await controller.refreshWorkspaceIndex(minInterval: 60)

        #expect(probe.count == 3)
        #expect(controller.lastWorkspaceIndexRefresh != nil)
        #expect(controller.lastWorkspaceIndexRefreshRoot == root.standardizedFileURL)
        guard case .ready = await controller.workspaceFileIndex.state else {
            Issue.record("activation should rebuild the restored root despite the prior throttle")
            return
        }
        #expect(await paths(controller) == ["a.md"])
    }
}
