import FileCore

@MainActor
extension WorkspaceModel {
    func isBackingUnavailable(_ document: FileDocument) -> Bool {
        if case .unavailable = document.backingState {
            return true
        }
        return false
    }

    func isCurrent(_ document: FileDocument) -> Bool {
        guard let current = tabStore.activeDocument else { return false }
        return current.id == document.id
            && current.fileURL?.standardizedFileURL == document.fileURL?.standardizedFileURL
            && current.text == document.text
            && current.state == document.state
            && current.mutationGeneration == document.mutationGeneration
    }

    func isSameDocumentLifetime(_ lhs: FileDocument, _ rhs: FileDocument) -> Bool {
        lhs.id == rhs.id
            && lhs.recoveryEpoch == rhs.recoveryEpoch
            && lhs.fileURL?.standardizedFileURL == rhs.fileURL?.standardizedFileURL
    }

    /// A queued save may be admitted only while the current document still
    /// descends from its captured baseline. Revision lineage, rather than an
    /// incidental mutation count, is the authority: local edits retain their
    /// baseline while external reconciliation replaces it.
    func currentReferencesAcceptedSaveInput(
        _ current: FileRevision?,
        sourceRevision: FileRevision?,
        expectedRevision: FileRevision?
    ) -> Bool {
        current == sourceRevision || current == expectedRevision
    }

    func acceptedSaveLineageCount(for document: FileDocument) async -> Int {
        await documentWriter.lineageCount(for: document)
    }

    func tracksSaveGeneration(for document: FileDocument) -> Bool {
        latestSaveGenerationByDocumentID[document.id] != nil
    }

    /// Marks `documentID` as having a save write in flight (#57). Paired with
    /// `endSavingIndicator`, always via `defer`, so it clears on every exit
    /// path — success, failure, or a metadata-conflict retry recursing back
    /// through the same call. Reference-counted (adversarial review finding):
    /// `save(isRetry:destinationPolicy:)` has no reentrancy guard against a
    /// second concurrent `save()` for the same document (only
    /// `inFlightSaveAsByDocumentID` blocks a *Save As* from overlapping), and
    /// the metadata-conflict retry in `reconcileSaveConflict` recurses into a
    /// nested `save(isRetry: true, ...)` call for the same document ID while
    /// the outer call is still unwinding. A plain `Set` would let whichever
    /// overlapping call finishes first clear the flag while the other is
    /// still genuinely writing.
    func beginSavingIndicator(for documentID: String) {
        savingCountByDocumentID[documentID, default: 0] += 1
    }

    func endSavingIndicator(for documentID: String) {
        guard let count = savingCountByDocumentID[documentID] else { return }
        if count > 1 {
            savingCountByDocumentID[documentID] = count - 1
        } else {
            savingCountByDocumentID[documentID] = nil
        }
    }
}
