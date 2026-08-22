import AppSettings
import EditorCore
import FileCore
import FileTree
import Foundation
import Highlighting
@testable import MacDown2
import Testing
import Themes
import Workspace

@MainActor
struct WindowCoordinatorSaveAsPublicationTests {
    @Test func saveAsRetryPublishesDestinationThroughItsOwnPendingAction() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let sourceURL = directory.appendingPathComponent("source.md")
        let destinationURL = directory.appendingPathComponent("destination.md")
        try "disk".write(to: sourceURL, atomically: true, encoding: .utf8)

        let sessions = ToggleSessionStore()
        let recovery = RecoveryBuffer(recoveryDirectory: directory.appendingPathComponent("Recovery"))
        let preferences = FileTreePreferences()
        let coordinator = WindowCoordinator(
            sessionStore: sessions,
            recoveryBuffer: recovery,
            themeController: ThemeController(),
            grammarRegistry: GrammarRegistry(),
            fileTreePreferences: preferences,
            recentFolderRoots: RecentFolderRoots(preferences: preferences),
            appSettings: AppSettingsModel()
        )
        let panel = FakeFilePanelProvider()
        panel.nextSaveURL = destinationURL
        let model = coordinator.makeWindowModel(panel: panel)
        let document = try FileDocument(fileURL: sourceURL, recoveryBuffer: recovery).load().updatingText("draft")
        model.tabStore.newTab(document: document)
        let controller = WindowController(
            model: model,
            coordinator: coordinator,
            themeController: ThemeController(),
            grammarRegistry: GrammarRegistry(),
            fileTreePreferences: preferences
        )
        coordinator.controllers = [controller]

        await model.saveAs()
        #expect(model.hasPendingRecoveryCleanup)
        #expect(sessions.loadSession() == nil)

        sessions.acceptsWrites = true
        await model.retryRecoveryCleanup()

        #expect(!model.hasPendingRecoveryCleanup)
        #expect(sessions.loadSession()?.tabs.first?.fileURL == destinationURL.standardizedFileURL)
    }

    @Test func saveSessionReportsFailureWhenNoControllerCanOwnAnUnverifiedPublication() async {
        let sessions = ToggleSessionStore()
        let preferences = FileTreePreferences()
        let coordinator = WindowCoordinator(
            sessionStore: sessions,
            themeController: ThemeController(),
            grammarRegistry: GrammarRegistry(),
            fileTreePreferences: preferences,
            recentFolderRoots: RecentFolderRoots(preferences: preferences),
            appSettings: AppSettingsModel()
        )

        let result = await coordinator.saveSessionResult()
        if case .sessionPublicationFailed = result {
        } else {
            Issue.record("Expected an explicit session-publication failure")
        }
        #expect(!result.persisted)
    }
}

@MainActor
private final class ToggleSessionStore: WorkspaceSessionStoring {
    var acceptsWrites = false
    private var storedSession: WorkspaceSession?

    func loadSession() -> WorkspaceSession? {
        storedSession
    }

    func saveSession(_ session: WorkspaceSession) {
        guard acceptsWrites else { return }
        storedSession = session
    }
}
