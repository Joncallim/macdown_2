import FileCore
import Foundation

/// Error publication is operation-owned (#183 F15): an operation that suspends
/// (awaited recovery cleanup, retries) may clear the displayed error on success
/// only if no other operation published or cleared one since it began. User
/// dismissal and an operation's own failures still assign `lastError` directly.
@MainActor
extension WorkspaceModel {
    /// Clears `lastError` unless it changed since `revision` was captured.
    func clearLastError(ifUnchangedSince revision: UInt64) {
        guard errorRevision == revision else { return }
        lastError = nil
    }

    /// The outcome of an awaited cleanup: an error to publish, or a clear that
    /// only applies if the displayed error is still the one this operation saw.
    func publishCleanupResult(_ cleanup: RecoveryCleanupResult, document: FileDocument, since revision: UInt64) {
        if cleanup.isAbsent {
            clearLastError(ifUnchangedSince: revision)
        } else {
            lastError = recoveryCleanupError(cleanup, document: document)
        }
    }
}
