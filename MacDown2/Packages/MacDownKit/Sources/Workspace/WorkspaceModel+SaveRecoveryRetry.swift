import FileCore
import Foundation

@MainActor
extension WorkspaceModel {
    /// Replays only the exact lifetime whose post-publication cleanup failed.
    /// It can never retire a later Save As descendant by pathname alone.
    public func retryRecoveryCleanup() async {
        var failed = false
        let pendingActions = pendingRecoveryCleanupActions
        for pending in pendingActions {
            guard await preserveEditedCleanupDocument(for: pending) else {
                failed = true
                continue
            }
            guard pendingRecoveryCleanupActions.contains(pending) else { continue }
            if let continuation = pendingSaveAsRecoveryContinuations[pending] {
                guard await advanceSaveAsRecoveryRetry(pending, continuation: continuation) else {
                    failed = true
                    lastError = .recoveryCleanupRequired(URL(fileURLWithPath: pending.documentID))
                    continue
                }
                continue
            }
            guard await replayRecoveryAction(pending) else {
                failed = true
                lastError = .recoveryCleanupRequired(URL(fileURLWithPath: pending.documentID))
                continue
            }
            pendingRecoveryCleanupActions.remove(pending)
            pendingSaveAsRecoveryContinuations.removeValue(forKey: pending)
        }
        if !failed, pendingRecoveryCleanupActions.isEmpty {
            lastError = nil
        }
    }

    private func advanceSaveAsRecoveryRetry(
        _ action: PendingRecoveryCleanupAction,
        continuation: SaveAsRecoveryContinuation
    ) async -> Bool {
        if continuation.phase == .retireSource {
            guard await replayRecoveryAction(action) else { return false }
            pendingRecoveryCleanupActions.remove(action)
            pendingSaveAsRecoveryContinuations.removeValue(forKey: action)
            return await retireFormerSaveAsSource(continuation.source, replacing: continuation.replacement)
        }
        if action.kind != .publishSession {
            guard await replayRecoveryAction(action) else { return false }
        }
        guard let replacement = await prepareSaveAsRecoveryContinuation(continuation) else { return false }
        let publicationAction = PendingRecoveryCleanupAction.publishSession(for: replacement)
        let publishedContinuation = continuation
            .withReplacement(replacement)
            .withPhase(.sessionPublished)
        pendingRecoveryCleanupActions.remove(action)
        pendingSaveAsRecoveryContinuations.removeValue(forKey: action)
        pendingRecoveryCleanupActions.insert(publicationAction)
        pendingSaveAsRecoveryContinuations[publicationAction] = publishedContinuation
        guard await replayRecoveryAction(publicationAction) else { return false }
        guard await completePublishedSaveAsRecoveryContinuation(publishedContinuation) else { return false }
        pendingRecoveryCleanupActions.remove(publicationAction)
        pendingSaveAsRecoveryContinuations.removeValue(forKey: publicationAction)
        return true
    }

    private func replayRecoveryAction(_ pending: PendingRecoveryCleanupAction) async -> Bool {
        switch pending.kind {
        case .remove:
            return await tabStore.recoveryBuffer
                .removeWithOutcome(for: pending.documentID, epoch: pending.epoch).isAbsent
        case .retire:
            return await tabStore.recoveryBuffer
                .retireWithOutcome(for: pending.documentID, epoch: pending.epoch).isAbsent
        case .persist:
            guard let recoveryBuffer = pending.recoveryBuffer else { return false }
            do {
                return try await recoveryBuffer.saveCurrentLifetime(
                    content: pending.text,
                    for: pending.documentID,
                    version: pending.mutationGeneration,
                    epoch: pending.epoch
                )
            } catch {
                return false
            }
        case .migrate:
            guard let sourceDocumentID = pending.sourceDocumentID,
                  let sourceEpoch = pending.sourceEpoch,
                  let recoveryBuffer = pending.recoveryBuffer else { return false }
            return await recoveryBuffer.migrateWithOutcome(
                from: sourceDocumentID,
                to: pending.documentID,
                content: pending.text,
                version: pending.mutationGeneration,
                sourceEpoch: sourceEpoch,
                destinationEpoch: pending.epoch
            ).isComplete
        case .acknowledgeMigration:
            guard let sourceDocumentID = pending.sourceDocumentID,
                  let sourceEpoch = pending.sourceEpoch,
                  let recoveryBuffer = pending.recoveryBuffer else { return false }
            return await recoveryBuffer.acknowledgeMigration(
                from: sourceDocumentID,
                sourceEpoch: sourceEpoch,
                to: pending.documentID,
                destinationEpoch: pending.epoch
            ).isAbsent
        case .publishSession:
            return await publishSaveAsSession()
        }
    }

    private func prepareSaveAsRecoveryContinuation(_ continuation: SaveAsRecoveryContinuation) async -> FileDocument? {
        guard let current = tabStore.activeDocument,
              isSameDocumentLifetime(current, continuation.source)
              || isSameDocumentLifetime(current, continuation.replacement) else { return nil }
        let replacement = isSameDocumentLifetime(current, continuation.source)
            ? (isCurrent(continuation.source)
                ? continuation.replacement
                : current.rebindingSavedDestination(from: continuation.replacement))
            : current
        guard await recoverySnapshotIsDurable(for: replacement) else { return nil }
        tabStore.updateActiveDocument { _ in replacement }
        return replacement
    }

    private func completePublishedSaveAsRecoveryContinuation(
        _ continuation: SaveAsRecoveryContinuation
    ) async -> Bool {
        let replacement = continuation.replacement
        let needsAcknowledgement = continuation.phase != .retireSource
            && (continuation.source.id != replacement.id
                || continuation.source.recoveryEpoch != replacement.recoveryEpoch)
        if needsAcknowledgement {
            let acknowledgement = await replacement.recoveryBuffer.acknowledgeMigration(
                from: continuation.source.id,
                sourceEpoch: continuation.source.recoveryEpoch,
                to: replacement.id,
                destinationEpoch: replacement.recoveryEpoch
            )
            guard acknowledgement.isAbsent else {
                lastError = recoveryCleanupError(acknowledgement, document: continuation.source)
                return false
            }
        }
        return await retireFormerSaveAsSource(continuation.source, replacing: replacement)
    }

    func enqueueSaveAsRetry(
        _ action: PendingRecoveryCleanupAction,
        source: FileDocument,
        replacement: FileDocument,
        context: SaveContext,
        phase: SaveAsRecoveryRetryPhase
    ) {
        pendingRecoveryCleanupActions.insert(action)
        pendingSaveAsRecoveryContinuations[action] = SaveAsRecoveryContinuation(
            source: source,
            replacement: replacement,
            context: context,
            phase: phase
        )
    }
}
