import AppKit
import AppSettings
import FileCore
import FileTree
import Highlighting
@testable import MacDown2
import Testing
import Themes

@MainActor
@Suite("Preview chooser lifecycle")
struct PreviewChooserCloseTests {
    @Test func closedWindowDoesNotStartQueuedChooser() async throws {
        let (controller, document) = makeController()
        let window = try #require(controller.window)
        var calls = 0
        let task = try #require(controller.choosePreviewResourceFolder(for: document) { _, _ in
            calls += 1
            return nil
        })
        window.close()
        #expect(controller.isClosed)
        await task.value
        #expect(calls == 0)
    }

    @Test func switchedDocumentDoesNotStartQueuedChooser() async throws {
        let (controller, document) = makeController()
        defer { controller.close() }
        var calls = 0
        let task = try #require(controller.choosePreviewResourceFolder(for: document) { _, _ in
            calls += 1
            return nil
        })
        controller.model.tabStore.newTab(document: FileCore.FileDocument(
            fileURL: URL(fileURLWithPath: "/tmp/other-preview-fixture.md")
        ))
        await task.value
        #expect(calls == 0)
    }

    @Test func liveWindowStartsQueuedChooser() async throws {
        let (controller, document) = makeController()
        defer { controller.close() }
        var calls = 0
        let task = try #require(controller.choosePreviewResourceFolder(for: document) { _, _ in
            calls += 1
            return nil
        })
        await task.value
        #expect(calls == 1)
    }

    private func makeController() -> (WindowController, FileCore.FileDocument) {
        let preferences = FileTreePreferences()
        let coordinator = WindowCoordinator(
            themeController: ThemeController(),
            grammarRegistry: GrammarRegistry(),
            fileTreePreferences: preferences,
            recentFolderRoots: RecentFolderRoots(preferences: preferences),
            recentFileDocuments: RecentFileDocuments(preferences: preferences),
            appSettings: AppSettingsModel()
        )
        let model = coordinator.makeWindowModel()
        let document = FileCore.FileDocument(fileURL: URL(fileURLWithPath: "/tmp/preview-chooser-fixture.md"))
        model.tabStore.newTab(document: document)
        let controller = WindowController(
            model: model, coordinator: coordinator,
            themeController: coordinator.themeController,
            grammarRegistry: coordinator.grammarRegistry,
            fileTreePreferences: preferences
        )
        return (controller, document)
    }
}
