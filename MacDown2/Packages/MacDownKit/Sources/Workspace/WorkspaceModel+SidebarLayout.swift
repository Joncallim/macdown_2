import Foundation

/// Sidebar section order/expansion intents, split out of `WorkspaceModel.swift`
/// to stay under the file_length lint budget (matches
/// `WorkspaceModel+Saving.swift`'s same reason). `sidebarVisible` itself
/// stays in the main file since it is a stored property with its own
/// `didSet`.
public extension WorkspaceModel {
    // MARK: - State store helpers

    func isSectionExpanded(_ section: SidebarSection) -> Bool {
        sectionExpanded[section] ?? true
    }

    func setSectionExpanded(_ section: SidebarSection, _ expanded: Bool) {
        sectionExpanded[section] = expanded
        stateStore.sidebarSectionExpanded[section.rawValue] = expanded
        layoutBroadcaster?.broadcast(.sectionExpanded(section, expanded), from: ObjectIdentifier(self))
    }

    /// Reorders sidebar sections and persists the new order.
    ///
    /// `offsets`/`offset` use the `ForEach.onMove` convention; out-of-range
    /// values are tolerated rather than trapping. Applied to THIS window's
    /// own `sectionOrder` — which `applyRemoteLayoutChange` keeps current
    /// with every other open window's edits — so a drag here always starts
    /// from the latest known layout, not a copy that went stale the moment
    /// another window last wrote to the shared store (#34).
    func moveSections(fromOffsets offsets: IndexSet, toOffset offset: Int) {
        let order = reorder(sectionOrder, fromOffsets: offsets, toOffset: offset)
        sectionOrder = order
        stateStore.sidebarSectionOrder = order.map(\.rawValue)
        layoutBroadcaster?.broadcast(.sectionOrder(order), from: ObjectIdentifier(self))
    }

    /// Applies a sidebar-layout edit made by ANOTHER window sharing this
    /// window's `layoutBroadcaster`. Updates only this window's in-memory
    /// cache — never re-writes `stateStore` (the originating window already
    /// did) and never re-broadcasts (the broadcaster already excludes the
    /// original source, and this is not a new local edit). Direct
    /// dictionary/array mutation here has no `didSet` of its own to guard
    /// against — the persist+broadcast side effects live in
    /// `setSectionExpanded`/`moveSections`, which this method deliberately
    /// does not call.
    internal func applyRemoteLayoutChange(_ change: SidebarLayoutChange) {
        switch change {
        case let .sectionExpanded(section, expanded):
            sectionExpanded[section] = expanded
        case let .sectionOrder(order):
            sectionOrder = order
        }
    }
}
