import Foundation

public enum ExternalReconciliationDisposition: Sendable, Equatable {
    case noChange
    case metadataAdvanced
    case reloaded
    case localNowMatchesDisk
    case conflicted
    case conflictUpdated
    case conflictClearedToDirty
    case backingUnavailable
}

public struct ExternalReconciliation: Sendable {
    public let document: FileDocument
    public let disposition: ExternalReconciliationDisposition

    public init(document: FileDocument, disposition: ExternalReconciliationDisposition) {
        self.document = document
        self.disposition = disposition
    }
}

public extension FileDocument {
    func reconcilingExternalSnapshot(_ snapshot: FileSnapshot) -> ExternalReconciliation {
        if snapshot.text == text {
            return reconcilingMatchingExternalText(snapshot)
        }

        if snapshot.revision.sha256 == lastKnownRevision?.sha256 {
            var copy = self
            copy.applyExternalState(
                lastKnownRevision: snapshot.revision,
                setLastKnownRevision: true,
                backingState: .available
            )
            if state == .conflict {
                copy.state = .dirty
                copy.applyExternalState(pendingExternalRevision: nil, setPendingExternalRevision: true)
                copy.advanceMutation()
                return ExternalReconciliation(document: copy, disposition: .conflictClearedToDirty)
            }
            copy.advanceMutation()
            return ExternalReconciliation(document: copy, disposition: .metadataAdvanced)
        }

        var copy = self
        switch state {
        case .clean:
            return ExternalReconciliation(document: reloadedFromExternal(snapshot), disposition: .reloaded)
        case .dirty, .promptingClose:
            copy.state = .conflict
            copy.applyExternalState(
                pendingExternalRevision: snapshot.revision,
                setPendingExternalRevision: true,
                backingState: .available
            )
            copy.advanceMutation()
            return ExternalReconciliation(document: copy, disposition: .conflicted)
        case .conflict:
            copy.applyExternalState(
                pendingExternalRevision: snapshot.revision,
                setPendingExternalRevision: true,
                backingState: .available
            )
            copy.advanceMutation()
            return ExternalReconciliation(document: copy, disposition: .conflictUpdated)
        }
    }

    private func reconcilingMatchingExternalText(_ snapshot: FileSnapshot) -> ExternalReconciliation {
        let backingIsAvailable = if case .available = backingState {
            true
        } else {
            false
        }
        guard state != .clean || lastKnownRevision != snapshot.revision || pendingExternalRevision != nil
            || !backingIsAvailable
        else {
            // Avoid an observable replacement for the normal monitor case:
            // the same stable snapshot has already been reconciled.
            return ExternalReconciliation(document: self, disposition: .noChange)
        }
        var copy = self
        copy.state = .clean
        copy.applyExternalState(
            lastKnownRevision: snapshot.revision,
            setLastKnownRevision: true,
            pendingExternalRevision: nil,
            setPendingExternalRevision: true,
            backingState: .available,
            encoding: snapshot.encodingMetadata,
            setEncoding: true
        )
        copy.advanceMutation()
        return ExternalReconciliation(document: copy, disposition: .localNowMatchesDisk)
    }

    func keepingLocalChanges(acknowledging revision: FileRevision) -> FileDocument {
        var copy = self
        copy.applyExternalState(
            lastKnownRevision: revision,
            setLastKnownRevision: true,
            pendingExternalRevision: nil,
            setPendingExternalRevision: true,
            backingState: .available
        )
        copy.state = .dirty
        copy.advanceMutation()
        return copy
    }

    func reloadedFromExternal(_ snapshot: FileSnapshot) -> FileDocument {
        var copy = self
        copy.text = snapshot.text
        copy.applyExternalState(
            lastKnownRevision: snapshot.revision,
            setLastKnownRevision: true,
            pendingExternalRevision: nil,
            setPendingExternalRevision: true,
            backingState: .available,
            encoding: snapshot.encodingMetadata,
            setEncoding: true
        )
        copy.state = .clean
        copy.advanceMutation()
        return copy
    }

    func markingBackingUnavailable(_ issue: FileBackingIssue) -> FileDocument {
        var copy = self
        copy.applyExternalState(
            pendingExternalRevision: nil,
            setPendingExternalRevision: true,
            backingState: .unavailable(issue)
        )
        if state != .dirty {
            copy.state = .dirty
        }
        copy.advanceMutation()
        return copy
    }

    func rebindingExternalMove(to snapshot: FileSnapshot) -> FileDocument {
        // Preserve the old content baseline until the caller reconciles the
        // fresh snapshot. This is what keeps dirty local text safe across a
        // proven rename instead of silently treating the move as a reload.
        renamed(to: snapshot.revision.url)
    }

    /// Merges the baseline accepted by an in-flight save into a later local
    /// edit. The visible text remains the user's newer text and stays dirty,
    /// while the next save is conditional on the revision that was actually
    /// published by the completed write.
    func adoptingSavedBaseline(from saved: FileDocument) -> FileDocument {
        var copy = self
        copy.applyExternalState(
            lastKnownRevision: saved.lastKnownRevision,
            setLastKnownRevision: true,
            pendingExternalRevision: nil,
            setPendingExternalRevision: true,
            backingState: .available
        )
        copy.state = .dirty
        copy.advanceMutation()
        return copy
    }
}
