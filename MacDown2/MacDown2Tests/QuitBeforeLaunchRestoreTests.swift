import AppSettings
import FileCore
import FileTree
import Foundation
import Highlighting
@testable import MacDown2
import Testing
import Themes
import Workspace

/// Review pass 6: quitting while only the first-run welcome window was up (no restore had run, so no document
/// windows existed) published an EMPTY session over the saved one, orphaning the dirty tabs' recovery files.
@MainActor
struct QuitBeforeLaunchRestoreTests {
    private final class RecordingStore: WorkspaceSessionStoring, @unchecked Sendable {
        var saved: [WorkspaceSession] = []
        let launch: WorkspaceSession
        init(launch: WorkspaceSession) {
            self.launch = launch
        }

        func loadSession() -> WorkspaceSession? {
            saved.last ?? launch
        }

        func saveSession(_ session: WorkspaceSession) {
            saved.append(session)
        }
    }

    private func coordinator(store: RecordingStore) -> WindowCoordinator {
        let preferences = FileTreePreferences()
        return WindowCoordinator(
            sessionStore: store,
            recoveryBuffer: RecoveryBuffer(recoveryDirectory: FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)),
            themeController: ThemeController(),
            grammarRegistry: GrammarRegistry(),
            fileTreePreferences: preferences,
            recentFolderRoots: RecentFolderRoots(preferences: preferences),
            recentFileDocuments: RecentFileDocuments(preferences: preferences),
            appSettings: AppSettingsModel()
        )
    }

    @Test func savingBeforeTheLaunchRestoreLeavesTheSavedSessionAlone() async {
        let savedTab = TabRecord(id: UUID(), untitledDocumentID: UUID().uuidString)
        let store = RecordingStore(launch: WorkspaceSession(tabs: [savedTab], activeTabID: savedTab.id))
        let coordinator = coordinator(store: store)

        let result = await coordinator.saveSessionResult()

        #expect(result.persisted)
        #expect(store.saved.isEmpty)
        #expect(coordinator.consumeLaunchSession()?.tabs.map(\.id) == [savedTab.id])
    }

    @Test func savingAfterTheLaunchSessionWasConsumedPublishesNormally() async {
        let savedTab = TabRecord(id: UUID(), untitledDocumentID: UUID().uuidString)
        let store = RecordingStore(launch: WorkspaceSession(tabs: [savedTab], activeTabID: savedTab.id))
        let coordinator = coordinator(store: store)
        _ = coordinator.consumeLaunchSession()

        _ = await coordinator.saveSessionResult()

        #expect(store.saved.count == 1)
    }
}
