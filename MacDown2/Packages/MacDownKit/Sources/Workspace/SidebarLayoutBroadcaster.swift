import Foundation

/// One sidebar-layout edit, propagated between `WorkspaceModel` instances
/// that share the same `WorkspaceStateStoring` suite. Deliberately does NOT
/// include sidebar column visibility — that stays per-window (see
/// `WorkspaceModel.sidebarVisible`'s doc comment).
public enum SidebarLayoutChange: Sendable, Equatable {
    case sectionExpanded(SidebarSection, Bool)
    case sectionOrder([SidebarSection])
}

/// Fans a sidebar-layout edit out to every OTHER open window sharing the same
/// backing store, so the change is visible immediately rather than only on
/// the next launch (#34).
///
/// The backing `WorkspaceStateStore` is a shared `UserDefaults` suite
/// (last-writer-wins), but before this type existed each window's
/// `WorkspaceModel` only ever read it once, at `init`. Two windows reordering
/// sections independently would each apply their own drag offsets to their
/// own stale in-memory copy, so the second window's write would silently
/// discard the first window's change — not "last writer wins", but "last
/// writer wins using out-of-date input." This broadcaster keeps every open
/// window's in-memory cache current, so a `WorkspaceModel` always applies its
/// own edits on top of the latest known layout, not a stale one.
///
/// Deliberately app-wide, not per-window: `WorkspaceStateStore`'s own doc
/// comment already establishes sidebar layout as shared, process-wide state,
/// and #34 asks to make that existing product behaviour actually work
/// correctly across windows rather than replacing it with a new
/// per-window preference model.
///
/// One instance is owned by `WindowCoordinator` and shared by every
/// `WorkspaceModel` it creates. A `WorkspaceModel` constructed without one
/// (every existing unit test) behaves exactly as before — this is additive,
/// opt-in propagation, not a change to `WorkspaceModel`'s default behaviour.
@MainActor
public final class SidebarLayoutBroadcaster {
    private struct WeakModel {
        weak var model: WorkspaceModel?
    }

    private var subscribers: [WeakModel] = []

    public init() {}

    func subscribe(_ model: WorkspaceModel) {
        subscribers.append(WeakModel(model: model))
    }

    /// Notifies every subscriber except `source` and, as a side effect,
    /// drops any entry whose window has since been deallocated — the only
    /// cleanup this type needs, since subscribers are held weakly.
    func broadcast(_ change: SidebarLayoutChange, from source: ObjectIdentifier) {
        subscribers.removeAll { $0.model == nil }
        for entry in subscribers {
            guard let model = entry.model, ObjectIdentifier(model) != source else { continue }
            model.applyRemoteLayoutChange(change)
        }
    }
}
