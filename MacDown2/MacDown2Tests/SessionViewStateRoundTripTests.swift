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

/// The coordinator's real session writer/restorer must carry per-tab view
/// state (Preview Mode and Syntax Mode, EPIC-22 Slice 9d) — `TabStore`'s own
/// `currentSession()` is not what the app publishes.
@MainActor
struct SessionViewStateRoundTripTests {
    private final class MemorySessionStore: WorkspaceSessionStoring {
        var session: WorkspaceSession?
        func loadSession() -> WorkspaceSession? {
            session
        }

        func saveSession(_ session: WorkspaceSession) {
            self.session = session
        }
    }

    private func makeCoordinator(sessions: MemorySessionStore, recovery: RecoveryBuffer) -> WindowCoordinator {
        let preferences = FileTreePreferences()
        return WindowCoordinator(
            sessionStore: sessions,
            recoveryBuffer: recovery,
            themeController: ThemeController(),
            grammarRegistry: GrammarRegistry(),
            fileTreePreferences: preferences,
            recentFolderRoots: RecentFolderRoots(preferences: preferences),
            recentFileDocuments: RecentFileDocuments(preferences: preferences),
            appSettings: AppSettingsModel()
        )
    }

    @Test func previewModeAndSyntaxModeSurviveSaveAndRestore() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent("notes.txt")
        try "hello".write(to: fileURL, atomically: true, encoding: .utf8)

        let sessions = MemorySessionStore()
        let recovery = RecoveryBuffer(recoveryDirectory: directory.appendingPathComponent("Recovery"))
        let coordinator = makeCoordinator(sessions: sessions, recovery: recovery)
        let preferences = FileTreePreferences()

        let model = coordinator.makeWindowModel()
        let document = try FileDocument(fileURL: fileURL, recoveryBuffer: recovery).load()
        model.tabStore.newTab(document: document)
        let tabID = try #require(model.tabStore.activeTabID)
        model.tabStore.setPreviewMode(.source, for: tabID)
        model.tabStore.setSyntaxMode("python", for: tabID)
        let controller = WindowController(
            model: model,
            coordinator: coordinator,
            themeController: ThemeController(),
            grammarRegistry: GrammarRegistry(),
            fileTreePreferences: preferences
        )
        coordinator.controllers = [controller]

        #expect(await coordinator.saveSessionResult().persisted)
        let record = try #require(sessions.session?.tabs.first)
        #expect(record.previewMode == .source)
        #expect(record.syntaxOverride == SyntaxModeOverride(modeFormatID: "python", baseFormatID: "plaintext"))

        let restoringStore = TabStore(sessionStore: sessions, recoveryBuffer: recovery)
        await restoringStore.restoreSessionIfNeeded()
        let restoredTab = try #require(restoringStore.tabs.first)
        let restoredController = coordinator.makeRestoredController(tab: restoredTab)
        coordinator.applyRestoredState(controller: restoredController, tab: restoredTab)

        let live = try #require(restoredController.model.tabStore.activeTab)
        #expect(live.previewMode == .source)
        #expect(live.syntaxFormat.id == "python")
        #expect(live.document.format.id == restoredTab.document.format.id)
    }

    @Test func sessionSavesTheEditorsPrimarySelectionNotTheTopmostRange() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent("notes.txt")
        try "alpha beta gamma delta".write(to: fileURL, atomically: true, encoding: .utf8)

        let sessions = MemorySessionStore()
        let recovery = RecoveryBuffer(recoveryDirectory: directory.appendingPathComponent("Recovery"))
        let coordinator = makeCoordinator(sessions: sessions, recovery: recovery)
        let model = coordinator.makeWindowModel()
        try model.tabStore.newTab(document: FileDocument(fileURL: fileURL, recoveryBuffer: recovery).load())
        let tabID = try #require(model.tabStore.activeTabID)
        let controller = WindowController(
            model: model,
            coordinator: coordinator,
            themeController: ThemeController(),
            grammarRegistry: GrammarRegistry(),
            fileTreePreferences: FileTreePreferences()
        )
        coordinator.controllers = [controller]
        let system = try #require(controller.editorStore.existingSystem(for: tabID.uuidString))
        system.selectionSet = EditorSelectionSet(
            ranges: [NSRange(location: 0, length: 5), NSRange(location: 11, length: 5)],
            primaryIndex: 1
        )

        #expect(await coordinator.saveSessionResult().persisted)

        let record = try #require(sessions.session?.tabs.first)
        #expect(record.cursorPosition == 11)
        #expect(record.selectionLength == 5)
    }

    // MARK: - #183 F20: a superseded autosave must not publish its obsolete session

    private func coordinatorWithOneTab(
        sessions: MemorySessionStore,
        directory: URL
    ) throws -> WindowCoordinator {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent("notes.txt")
        try "hello".write(to: fileURL, atomically: true, encoding: .utf8)
        let recovery = RecoveryBuffer(recoveryDirectory: directory.appendingPathComponent("Recovery"))
        let coordinator = makeCoordinator(sessions: sessions, recovery: recovery)
        let model = coordinator.makeWindowModel()
        try model.tabStore.newTab(document: FileDocument(fileURL: fileURL, recoveryBuffer: recovery).load())
        let controller = WindowController(
            model: model,
            coordinator: coordinator,
            themeController: ThemeController(),
            grammarRegistry: GrammarRegistry(),
            fileTreePreferences: FileTreePreferences()
        )
        coordinator.controllers = [controller]
        return coordinator
    }

    @Test func aCancelledAutosaveNeverPublishesItsObsoleteSnapshot() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let sessions = MemorySessionStore()
        let coordinator = try coordinatorWithOneTab(sessions: sessions, directory: directory)

        let autosave = Task { @MainActor in await coordinator.saveSessionResult(isAutosave: true) }
        autosave.cancel()
        _ = await autosave.value

        #expect(sessions.session == nil)
    }

    @Test func anAutosaveThatIsNotSupersededPublishes() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let sessions = MemorySessionStore()
        let coordinator = try coordinatorWithOneTab(sessions: sessions, directory: directory)

        #expect(await coordinator.saveSessionResult(isAutosave: true).persisted)

        #expect(sessions.session?.tabs.count == 1)
    }

    @Test func anExplicitSaveStillPublishesEvenIfItsTaskWasCancelled() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let sessions = MemorySessionStore()
        let coordinator = try coordinatorWithOneTab(sessions: sessions, directory: directory)

        let explicit = Task { @MainActor in await coordinator.saveSessionResult() }
        explicit.cancel()
        _ = await explicit.value

        #expect(sessions.session?.tabs.count == 1)
    }
}
