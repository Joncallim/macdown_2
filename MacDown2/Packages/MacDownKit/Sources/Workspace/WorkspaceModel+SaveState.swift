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
}
