import Foundation
import Workspace

/// A no-op session store so per-window `TabStore` instances do not compete with
/// the global coordinator when saving the session.
@MainActor
final class NoOpSessionStore: WorkspaceSessionStoring {
    func loadSession() -> WorkspaceSession? {
        nil
    }

    func saveSession(_: WorkspaceSession) {}
}

/// A no-op state store so sidebar state is independent per window.
@MainActor
final class NoOpStateStore: WorkspaceStateStoring {
    var sidebarVisible: Bool = true
    var sidebarSectionExpanded: [String: Bool] = [:]
}
