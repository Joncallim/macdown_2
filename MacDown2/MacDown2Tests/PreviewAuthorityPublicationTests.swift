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
@Suite("Preview authority publication")
struct PreviewAuthorityPublicationTests {
    @Test func windowRevokesBothConsumersBeforeWorkspacePublishesReplacementIdentity() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let sourceURL = folder.appendingPathComponent("source.md")
        try Data("source".utf8).write(to: sourceURL)
        let document = FileDocument(fileURL: sourceURL, text: "source")
        let suiteName = "preview-authority-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let preferences = FileTreePreferences(store: UserDefaultsFileTreePreferenceStore(defaults: defaults))
        let coordinator = WindowCoordinator(
            sessionStore: WorkspaceSessionStore(fileURL: folder.appendingPathComponent("session.json")),
            themeController: ThemeController(), grammarRegistry: GrammarRegistry(),
            fileTreePreferences: preferences,
            recentFolderRoots: RecentFolderRoots(preferences: preferences),
            recentFileDocuments: RecentFileDocuments(preferences: preferences),
            appSettings: AppSettingsModel(store: UserDefaultsAppSettingsStore(defaults: defaults)),
            workspaceStateStore: WorkspaceStateStore(defaults: defaults)
        )
        let model = coordinator.makeWindowModel()
        model.tabStore.newTab(document: document)
        let controller = WindowController(
            model: model, coordinator: coordinator,
            themeController: coordinator.themeController,
            grammarRegistry: coordinator.grammarRegistry, fileTreePreferences: preferences
        )
        coordinator.controllers = [controller]
        defer {
            coordinator.removeController(controller)
            controller.close()
            defaults.removePersistentDomain(forName: suiteName)
        }

        let selection = try #require(PreviewResourceFolderSelection.fixture(
            documentURL: sourceURL, folderURL: folder
        ))
        let owner = controller.previewResourceState
        let origin = try #require(owner.beginSelection(for: document))
        try await owner.install(selection, from: origin) { model.activeDocument }
        let markdown = try #require(owner.beginLoad(for: document, consumer: .markdown))
        let html = try #require(owner.beginLoad(for: document, consumer: .html))
        var didCheckBeforePublication = false
        owner.afterIdentityInvalidation = {
            didCheckBeforePublication = model.activeDocument?.id == document.id
                && markdown.isRevoked && html.isRevoked
                && markdown.acquireUse() == nil && html.acquireUse() == nil
        }

        let replacement = FileDocument(fileURL: folder.appendingPathComponent("saved-as.md"), text: "source")
        model.tabStore.updateActiveDocument { _ in replacement }

        #expect(didCheckBeforePublication)
        #expect(model.activeDocument?.id == replacement.id)
    }
}
