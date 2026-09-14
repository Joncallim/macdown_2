import Foundation
import Testing
@testable import Workspace

/// #34: two windows sharing one `WorkspaceStateStore` suite must agree on
/// sidebar section order/expansion live, not just on the next launch.
/// Before this fix, each `WorkspaceModel` cached the store's contents once
/// at `init` and never re-read it, so a second window's own edit applied its
/// drag offsets to a stale copy and silently discarded the first window's
/// change — "last writer wins using out-of-date input," not just "last
/// writer wins." `SidebarLayoutBroadcaster` fixes this by keeping every
/// open window's cache current with every other window's edits.
@MainActor
@Suite("Cross-window sidebar layout propagation (#34)")
struct SidebarLayoutPropagationTests {
    private struct TwoWindows {
        let store: FakeStateStore
        let windowA: WorkspaceModel
        let windowB: WorkspaceModel
    }

    /// Matches production: `WindowCoordinator` owns exactly one
    /// `SidebarLayoutBroadcaster` and passes both it and the same
    /// `WorkspaceStateStore` suite to every window it creates.
    private func makeTwoWindows() -> TwoWindows {
        let store = FakeStateStore()
        let broadcaster = SidebarLayoutBroadcaster()
        return TwoWindows(
            store: store,
            windowA: WorkspaceModel(stateStore: store, layoutBroadcaster: broadcaster),
            windowB: WorkspaceModel(stateStore: store, layoutBroadcaster: broadcaster)
        )
    }

    @Test func reorderingInOneWindowUpdatesAnotherOpenWindowImmediately() {
        let windows = makeTwoWindows()
        #expect(windows.windowB.sectionOrder == [.folder, .outline])

        windows.windowA.moveSections(fromOffsets: [0], toOffset: 2)

        #expect(windows.windowA.sectionOrder == [.outline, .folder])
        #expect(
            windows.windowB.sectionOrder == [.outline, .folder],
            "window B's in-memory cache must follow window A's edit without window B doing anything"
        )
    }

    @Test func expandingASectionInOneWindowUpdatesAnotherOpenWindowImmediately() {
        let windows = makeTwoWindows()
        windows.windowA.setSectionExpanded(.folder, false)
        #expect(windows.windowB.isSectionExpanded(.folder) == false)
    }

    /// Sidebar VISIBILITY (unlike order/expansion) is deliberately
    /// per-window — see `WorkspaceModel.sidebarVisible`'s doc comment and
    /// `WindowCoordinatorPaletteOriginTargetingTests
    /// .toggleSidebarFromAnExplicitOriginTogglesOnlyThatOriginsSidebar`,
    /// which already pins this at the app-target level.
    @Test func hidingTheSidebarInOneWindowDoesNotAffectAnotherOpenWindow() {
        let windows = makeTwoWindows()
        windows.windowA.sidebarVisible = false
        #expect(windows.windowB.sidebarVisible == true)
    }

    /// The exact reproduction from #34: window A reorders, then window B —
    /// whose own drag gesture was computed against whatever it had on
    /// screen — reorders too. Before the fix, B's `moveSections` applied its
    /// offsets to a cache that never learned about A's edit, silently
    /// discarding A's change. After the fix, B's broadcaster-kept-current
    /// cache already reflects A's edit BEFORE B's own drag is applied, so
    /// B's offsets land on the right starting point and the final persisted
    /// order reflects both edits in sequence, not just B's edit undoing A's.
    @Test func aSecondWindowsReorderAppliesOnTopOfTheFirstWindowsEditRatherThanDiscardingIt() {
        let windows = makeTwoWindows()

        // Window A: folder, outline -> outline, folder
        windows.windowA.moveSections(fromOffsets: [0], toOffset: 2)
        #expect(windows.windowB.sectionOrder == [.outline, .folder])

        // Window B now drags the (now-first) item to the end, against its
        // own up-to-date [.outline, .folder] — not the original
        // [.folder, .outline] it was constructed with.
        windows.windowB.moveSections(fromOffsets: [0], toOffset: 2)

        let expected: [SidebarSection] = [.folder, .outline]
        #expect(windows.windowB.sectionOrder == expected)
        #expect(windows.windowA.sectionOrder == expected, "window A must also learn about window B's edit")
        #expect(
            windows.store.sidebarSectionOrder == expected.map(\.rawValue),
            "the persisted value must be window B's edit applied to window A's, not a stale recompute"
        )
    }

    @Test func aWindowClosedBetweenEditsIsNotNotifiedAndDoesNotCrashTheBroadcaster() {
        let store = FakeStateStore()
        let broadcaster = SidebarLayoutBroadcaster()
        var windowA: WorkspaceModel? = WorkspaceModel(stateStore: store, layoutBroadcaster: broadcaster)
        let windowB = WorkspaceModel(stateStore: store, layoutBroadcaster: broadcaster)
        _ = windowA // existence, not value, is what this test needs
        windowA = nil

        windowB.moveSections(fromOffsets: [0], toOffset: 2)

        #expect(windowB.sectionOrder == [.outline, .folder])
    }

    @Test func aWindowWithNoBroadcasterBehavesExactlyAsBeforeThisTypeExisted() {
        let store = FakeStateStore()
        let model = WorkspaceModel(stateStore: store)
        model.moveSections(fromOffsets: [0], toOffset: 2)
        #expect(model.sectionOrder == [.outline, .folder])
        #expect(store.sidebarSectionOrder == ["outline", "folder"])
    }
}
