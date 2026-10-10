import AppSettings
import FileCore
import FileTree
import Foundation
import Highlighting
@testable import MacDown2
import Testing
import Themes
import Workspace

/// #183 F01 (tenth review R10-01): the Use-Disk-Version / Reopen-with-Encoding reload captured a disk snapshot, awaited
/// the recovery cleanup, then unconditionally installed it over the active document. An edit, tab switch or Save As
/// during that actor hop was overwritten; and Reopen reported success from the document's revision alone.
@MainActor
struct UseDiskVersionRaceTests {
    private struct Fixture {
        let controller: WindowController
        let coordinator: WindowCoordinator
        let model: WorkspaceModel
        let directory: URL
    }

    private func makeFixture(bytes: Data) throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("doc.txt")
        try bytes.write(to: url)
        let defaults = try #require(UserDefaults(suiteName: "reopen-encoding-\(UUID().uuidString)"))
        let preferences = FileTreePreferences(store: UserDefaultsFileTreePreferenceStore(defaults: defaults))
        let coordinator = WindowCoordinator(
            sessionStore: WorkspaceSessionStore(fileURL: directory.appendingPathComponent("session")),
            themeController: ThemeController(),
            grammarRegistry: GrammarRegistry(),
            fileTreePreferences: preferences,
            recentFolderRoots: RecentFolderRoots(preferences: preferences),
            recentFileDocuments: RecentFileDocuments(preferences: preferences),
            appSettings: AppSettingsModel(store: UserDefaultsAppSettingsStore(defaults: defaults)),
            workspaceStateStore: WorkspaceStateStore(defaults: defaults)
        )
        let model = coordinator.makeWindowModel()
        try model.tabStore.newTab(document: FileDocument(fileURL: url).load())
        let controller = WindowController(
            model: model,
            coordinator: coordinator,
            themeController: ThemeController(),
            grammarRegistry: GrammarRegistry(),
            fileTreePreferences: preferences
        )
        coordinator.controllers = [controller]
        return Fixture(controller: controller, coordinator: coordinator, model: model, directory: directory)
    }

    @Test func anEditDuringTheRecoveryCleanupIsNotOverwrittenByTheReload() async throws {
        let fixture = try makeFixture(bytes: Data("caf\u{E9}".utf8))
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let model = fixture.model
        fixture.controller.externalFileController.afterUseExternalRecoveryCleanup = {
            model.tabStore.updateActiveDocument { $0.updatingText("typed while the cleanup was suspended") }
        }

        let result = await fixture.controller.externalFileController.reopenWithEncoding(.isoLatin1) { _ in true }

        #expect(result == .superseded)
        #expect(model.activeDocument?.text == "typed while the cleanup was suspended")
        #expect(model.activeDocument?.state == .dirty)
        #expect(model.activeDocument?.encoding.encoding == .utf8)
    }

    @Test func aReloadThatIsNotSupersededStillLandsAndIsReportedAsReopened() async throws {
        let fixture = try makeFixture(bytes: Data("caf\u{E9}".utf8))
        defer { try? FileManager.default.removeItem(at: fixture.directory) }

        let result = await fixture.controller.externalFileController.reopenWithEncoding(.isoLatin1) { _ in true }

        #expect(result == .reopened)
        #expect(fixture.model.activeDocument?.encoding.encoding == .isoLatin1)
    }

    // Handoff regression 1 (#375): the other transitions during the held cleanup.

    @Test func aTabSwitchDuringTheRecoveryCleanupLeavesBothDocumentsAlone() async throws {
        let fixture = try makeFixture(bytes: Data("caf\u{E9}".utf8))
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let model = fixture.model
        let originalID = try #require(model.activeDocument?.id)
        let original = try #require(model.activeDocument)
        fixture.controller.externalFileController.afterUseExternalRecoveryCleanup = {
            model.tabStore.newTab(document: FileDocument(text: "other tab text"))
        }

        let result = await fixture.controller.externalFileController.reopenWithEncoding(.isoLatin1) { _ in true }

        #expect(result == .superseded)
        #expect(model.activeDocument?.text == "other tab text", "the newly active tab must not receive the snapshot")
        #expect(model.activeDocument?.encoding.encoding == .utf8)
        let untouched = model.tabStore.tabs.compactMap(\.document).first { $0.id == originalID }
        #expect(untouched?.text == original.text, "the original tab keeps its text")
        #expect(untouched?.encoding.encoding == .utf8, "and its encoding")
    }

    @Test func aRecoveryLifetimeChangeDuringTheCleanupSupersedesTheReload() async throws {
        let fixture = try makeFixture(bytes: Data("caf\u{E9}".utf8))
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let model = fixture.model
        let epochBefore = try #require(model.activeDocument?.recoveryEpoch)
        fixture.controller.externalFileController.afterUseExternalRecoveryCleanup = {
            model.tabStore.updateActiveDocument { $0.withFreshRecoveryLifetime() }
        }

        let result = await fixture.controller.externalFileController.reopenWithEncoding(.isoLatin1) { _ in true }

        #expect(result == .superseded)
        #expect(model.activeDocument?.recoveryEpoch != epochBefore, "the new lifetime is kept, not overwritten")
        #expect(model.activeDocument?.encoding.encoding == .utf8)
    }

    @Test func disposalDuringTheRecoveryCleanupNeverInstallsTheSnapshot() async throws {
        let fixture = try makeFixture(bytes: Data("caf\u{E9}".utf8))
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let model = fixture.model
        let controller = fixture.controller.externalFileController
        let textBefore = try #require(model.activeDocument?.text)
        controller.afterUseExternalRecoveryCleanup = {
            controller.dispose()
        }

        let result = await controller.reopenWithEncoding(.isoLatin1) { _ in true }

        #expect(result != .reopened)
        #expect(model.activeDocument?.text == textBefore)
        #expect(model.activeDocument?.encoding.encoding == .utf8)
    }
}
