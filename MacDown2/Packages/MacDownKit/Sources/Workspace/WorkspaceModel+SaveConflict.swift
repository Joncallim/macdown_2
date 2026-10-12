import FileCore
import Foundation

@MainActor
extension WorkspaceModel {
    func reconcileSaveConflict(
        for document: FileDocument,
        isRetry: Bool,
        destinationPolicy: SaveDestinationPolicy,
        encodingOverride: FileEncodingMetadata?
    ) async -> NonPromptingSaveResult {
        // The owning tab, active or not: the user can switch tabs while the failed write was in flight.
        guard let tabID = owningTabID(of: document),
              let current = tabStore.tabs.first(where: { $0.id == tabID })?.document,
              let url = current.fileURL,
              let snapshot = try? current.fileStore.readSnapshot(from: url, decoding: current.encoding.decodingPolicy)
        else {
            lastError = .unresolvedExternalConflict
            return .handled
        }
        let reconciliation = current.reconcilingExternalSnapshot(snapshot)
        tabStore.updateDocument(inTab: tabID) { _ in reconciliation.document }
        if reconciliation.document.state == .conflict {
            _ = await reconciliation.document.persistRecovery()
            lastError = .unresolvedExternalConflict
            return .handled
        }
        // `.promptingClose` reconciles the same as `.dirty` here (E18: a
        // metadata-only change preserves both states rather than collapsing
        // them). Excluding it would let `saveInternalForClose()` return
        // without ever reaching `.clean`; the close flow then treats that as
        // a failed save and silently reverts to `.dirty` with the prompt
        // dismissed — save-and-close would do nothing and say nothing.
        // An encoding change is a request to rewrite the file even when the
        // text is unedited, so a clean document must still retry it rather
        // than end silently with the old bytes.
        let hasEncodingChange = encodingOverride.map { $0 != reconciliation.document.encoding } ?? false
        guard reconciliation.document.state == .dirty || reconciliation.document.state == .promptingClose
            || hasEncodingChange
        else {
            return .handled
        }
        guard !isRetry else {
            // Something is touching this file's metadata faster than one
            // retry can keep up with. Stop instead of recursing indefinitely,
            // and say so rather than leaving the document dirty with no
            // explanation.
            lastError = workspaceError(for: FileStoreError.fileChangedDuringRead)
            return .handled
        }
        // The write failed only because the on-disk baseline had moved, not
        // because its content actually diverged (a real divergence lands in
        // `.conflict` above). Reconciliation just brought the baseline
        // current, so retry the save the user actually asked for instead of
        // leaving it dirty with no error and no indication anything failed —
        // but only once: a second consecutive metadata-only change means
        // something external is outpacing us, and that deserves a real error
        // rather than another silent attempt. Preserve the caller's
        // destination policy across that retry.
        return await save(
            isRetry: true,
            destinationPolicy: destinationPolicy,
            encodingOverride: encodingOverride,
            target: reconciliation.document
        )
    }
}
