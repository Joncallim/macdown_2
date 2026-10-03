import FileCore
import Foundation
@testable import MacDown2
import Testing
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
