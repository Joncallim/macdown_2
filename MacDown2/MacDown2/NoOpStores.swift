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
