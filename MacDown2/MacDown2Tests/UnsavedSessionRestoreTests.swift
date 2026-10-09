import AppSettings
import FileCore
import FileTree
import Foundation
import Highlighting
@testable import MacDown2
import Testing
import Themes
import Workspace

/// Review pass 1: a launch that does not restore the previous session (opened
/// from Finder, "Start with a new document") lost the previous session's
/// unsaved documents — the first autosave overwrote the session file.
@MainActor
struct UnsavedSessionRestoreTests {
    @Test func onlyDirtyAndConflictedTabsAreCarriedAcrossARestoreFreeLaunch() {
        let clean = FileDocument(text: "saved")
        let dirty = FileDocument(text: "saved").updatingText("typed")
        let tabs = [
            WorkspaceTab(id: UUID(), document: clean),
            WorkspaceTab(id: UUID(), document: dirty),
        ]

        let carried = WindowCoordinator.unsavedTabs(in: tabs)

        #expect(carried.map(\.document.id) == [dirty.id])
    }

    @Test func aCleanSessionCarriesNothing() {
        #expect(WindowCoordinator.unsavedTabs(in: [WorkspaceTab(id: UUID(), document: FileDocument(text: "x"))])
            .isEmpty)
    }
}

/// Review pass 2: a normal restore never consumed the launch session, so the first Finder open
/// after launch restored every still-unsaved tab a second time.
@MainActor
struct LaunchSessionConsumptionTests {
    @Test func theLaunchSessionIsHandedOutOnlyOnce() {
        let session = WorkspaceSession(tabs: [], activeTabID: nil)
        let store = StubSessionStore(session: session)
        let preferences = FileTreePreferences()
        let coordinator = WindowCoordinator(
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

        #expect(coordinator.consumeLaunchSession() != nil)
        #expect(coordinator.consumeLaunchSession() == nil)
    }

    private final class StubSessionStore: WorkspaceSessionStoring, @unchecked Sendable {
        let session: WorkspaceSession
        init(session: WorkspaceSession) {
            self.session = session
        }

        func loadSession() -> WorkspaceSession? {
            session
        }

        func saveSession(_: WorkspaceSession) {}
    }
}
