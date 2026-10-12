import AppSettings
import FileCore
import FileTree
import Foundation
import Highlighting
@testable import MacDown2
import Testing
import Themes
import Workspace

/// Round-10 review (304713dd) P2: after #454 dropped the generation guard, a window kept open for a retire of lifetime
/// E1 would still close if the live document had moved to a fresh lifetime E2 (a renew / preserve / move-follow) with
/// the same text and state, leaving the discarded text loadable from E2.
@MainActor
struct WindowControllerEpochCloseTests {
    @Test func closeAfterRetireOfAnOlderLifetimeLeavesTheLiveLifetimeRecovery() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let buffer = RecoveryBuffer(recoveryDirectory: root.appendingPathComponent("Recovery"))
        let defaults = try #require(UserDefaults(suiteName: "epoch-close-\(UUID().uuidString)"))
        let preferences = FileTreePreferences(store: UserDefaultsFileTreePreferenceStore(defaults: defaults))
        let coordinator = WindowCoordinator(
            recoveryBuffer: buffer,
            themeController: ThemeController(),
            grammarRegistry: GrammarRegistry(),
            fileTreePreferences: preferences,
            recentFolderRoots: RecentFolderRoots(preferences: preferences),
            recentFileDocuments: RecentFileDocuments(preferences: preferences),
            appSettings: AppSettingsModel(store: UserDefaultsAppSettingsStore(defaults: defaults)),
            workspaceStateStore: WorkspaceStateStore(defaults: defaults)
        )
        let model = coordinator.makeWindowModel()
        let dirty = FileDocument(text: "base", recoveryBuffer: buffer).updatingText("discarded words")
        #expect(await dirty.persistRecovery())
        model.tabStore.newTab(document: dirty)
        let controller = WindowController(
            model: model, coordinator: coordinator, themeController: coordinator.themeController,
            grammarRegistry: coordinator.grammarRegistry, fileTreePreferences: preferences
        )
        coordinator.controllers = [controller]
        // The user chose Discard: the old lifetime is retired...
        #expect(await controller.externalFileController.retireRecovery(for: dirty).isAbsent)
        // ...while another path (renew / preserve / move-follow) moved the live document to a new persisted lifetime.
        let renewed = try await dirty.withFreshRecoveryLifetime(preparedBy: buffer)
        model.tabStore.updateActiveDocument { _ in renewed }
        #expect(await renewed.persistRecovery())

        await controller.closeAfterRetire(of: dirty)

        let closed = coordinator.controllers.isEmpty
        let leftover = try await buffer.load(for: renewed.id, epoch: renewed.recoveryEpoch)
        #expect(!(closed && leftover != nil), "window closed but the live lifetime still holds the discarded text")
    }
}
