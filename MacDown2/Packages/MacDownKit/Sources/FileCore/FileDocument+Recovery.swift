import Foundation

// MARK: - Recovery mutation

public extension FileDocument {
    /// Returns a new document with `text` updated and the dirty flag set.
    ///
    /// Use this method when replacing text from an external source (e.g.,
    /// recovery-buffer restore) where a no-op change should **not** mark the
    /// document dirty. For user edits, use `edited(text:)` instead.
    func updatingText(_ newText: String) -> FileDocument {
        guard newText != text else { return self }
        var copy = self
        copy.text = newText
        switch copy.state {
        case .clean:
            copy.state = .dirty
        case .dirty, .conflict:
            break
        case .promptingClose:
            // If the user edits while being prompted, return to dirty.
            copy.state = .dirty
        }
        copy.advanceMutation()
        return copy
    }

    /// Persists the current text under the document identity immediately.
    /// Saved documents need this just as much as untitled ones while their
    /// original backing path is unavailable or in conflict.
    func persistRecovery() async -> Bool {
        await (try? recoveryBuffer.saveCurrentLifetime(
            content: text,
            for: id,
            version: mutationGeneration,
            epoch: recoveryEpoch
        )) ?? false
    }

    func saveRecovery() async {
        _ = await persistRecovery()
    }
}
