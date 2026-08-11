import FileCore
import Foundation

@MainActor
extension WorkspaceModel {
    /// Saves the active document. Untitled documents prompt for a location.
    public func save() async {
        guard let document = tabStore.activeDocument else {
            lastError = .noActiveDocument
            return
        }
        if document.state == .conflict {
            lastError = .unresolvedExternalConflict
            return
        }
        if document.fileURL == nil || isBackingUnavailable(document) {
            await saveAs()
            return
        }
        guard inFlightSaveAsByDocumentID[document.id] == nil else { return }

        let context = beginSave(for: document)
        do {
            let result = try await documentWriter.save(document)
            await applySuccessfulSave(
                result.document,
                originatingFrom: document,
                sourceRevision: result.sourceRevision,
                expectedRevision: result.expectedRevision,
                context: context
            )
            await documentWriter.acknowledge(result)
        } catch {
            guard shouldSurfaceSaveFailure(for: document, context: context, error: error) else { return }
            lastError = workspaceError(for: error)
        }
    }

    /// Saves the active document to a user-chosen location.
    public func saveAs() async {
        guard let document = tabStore.activeDocument else {
            lastError = .noActiveDocument
            return
        }
        let defaultName = document.fileURL?.lastPathComponent
            ?? "Untitled.\(document.format.extensions.first ?? "md")"
        guard let url = await panel.chooseSaveLocation(
            defaultName: defaultName,
            format: document.format
        ), isCurrent(document)
        else { return }
        await publishSaveAs(document, to: url)
    }

    func saveInternalForClose() async {
        guard tabStore.activeDocument != nil else { return }
        await save()
    }

    private func publishSaveAs(_ document: FileDocument, to url: URL) async {
        let context = beginSave(for: document)
        inFlightSaveAsByDocumentID[document.id] = context.generation
        defer {
            if inFlightSaveAsByDocumentID[document.id] == context.generation {
                inFlightSaveAsByDocumentID[document.id] = nil
            }
        }
        do {
            let saved = try await documentWriter.saveAs(document, to: url)
            await applySaveAs(saved, from: document, context: context)
        } catch {
            guard shouldSurfaceSaveFailure(for: document, context: context, error: error) else { return }
            lastError = workspaceError(for: error)
        }
    }

    private func applySaveAs(_ saved: FileDocument, from document: FileDocument, context: SaveContext) async {
        guard let replacement = saveAsReplacement(saved: saved, source: document, context: context) else { return }
        let oldID = document.id
        let recoveryOutcome = await finalizeSaveAsRecovery(replacement, source: document, context: context)
        if case .failed = recoveryOutcome {
            return
        }
        guard let finalReplacement = await prepareSaveAsDestination(
            saved,
            source: document,
            initialReplacement: replacement,
            context: context
        ) else { return }
        if case .migrationPending = recoveryOutcome {
            await onSaveAsDestinationSessionPublished?(document, finalReplacement)
            let acknowledged = await document.recoveryBuffer.acknowledgeMigration(
                from: document.id,
                sourceEpoch: document.recoveryEpoch,
                to: finalReplacement.id,
                destinationEpoch: finalReplacement.recoveryEpoch
            )
            guard acknowledged.isAbsent else {
                enqueueSaveAsRetry(
                    .acknowledgeMigration(source: document, destination: finalReplacement),
                    source: document,
                    replacement: finalReplacement,
                    context: context,
                    phase: .retireSource
                )
                lastError = recoveryCleanupError(acknowledged, document: document)
                return
            }
        }
        guard await retireFormerSaveAsSource(document, replacing: finalReplacement) else { return }
        latestSaveGenerationByDocumentID.removeValue(forKey: oldID)
        await documentWriter.retire(document)
        if pendingRecoveryCleanupActions.isEmpty {
            lastError = nil
        }
    }

    private func prepareSaveAsDestination(
        _ saved: FileDocument,
        source document: FileDocument,
        initialReplacement replacement: FileDocument,
        context: SaveContext
    ) async -> FileDocument? {
        await onSaveAsRecoveryFinalized?()
        guard let reconciled = saveAsReplacement(saved: saved, source: document, context: context) else { return nil }
        guard await persistReconciledSaveAsRecoveryIfNeeded(reconciled, replacing: replacement) else {
            enqueueSaveAsRetry(
                .persist(for: reconciled),
                source: document,
                replacement: reconciled,
                context: context,
                phase: .publishDestination
            )
            return nil
        }
        guard let finalReplacement = saveAsReplacement(saved: saved, source: document, context: context),
              sameSaveAsSnapshot(finalReplacement, reconciled) else { return nil }
        tabStore.updateActiveDocument { _ in finalReplacement }
        guard await publishSaveAsSession() else {
            enqueueSaveAsRetry(
                .publishSession(for: finalReplacement),
                source: document,
                replacement: finalReplacement,
                context: context,
                phase: .publishDestination
            )
            lastError = .recoveryCleanupRequired(finalReplacement.fileURL ?? URL(fileURLWithPath: finalReplacement.id))
            return nil
        }
        return finalReplacement
    }

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
            // Preserving an edit rotates its managed lifetime and atomically
            // replaces this action. Never replay the now-stale action in the
            // same pass: it may otherwise acknowledge or retire the source
            // before the successor identity is session-published.
            guard pendingRecoveryCleanupActions.contains(pending) else {
                continue
            }
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

    /// Advances a multi-step Save As retry without ever leaving a completed
    /// primitive action detached from the continuation that still owns the
    /// recovery redirect. On a session failure the atomically replaced
    /// publication action remains installed for the next Retry.
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

        // A publish action is a boundary, not a primitive that may run before
        // the destination replacement is installed. Replay persist/migrate
        // first, then bind and verify the exact destination snapshot.
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
            return await tabStore.recoveryBuffer.removeWithOutcome(
                for: pending.documentID,
                epoch: pending.epoch
            ).isAbsent
        case .retire:
            return await tabStore.recoveryBuffer.retireWithOutcome(
                for: pending.documentID,
                epoch: pending.epoch
            ).isAbsent
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
                  let recoveryBuffer = pending.recoveryBuffer
            else { return false }
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
                  let recoveryBuffer = pending.recoveryBuffer
            else { return false }
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

    private func prepareSaveAsRecoveryContinuation(
        _ continuation: SaveAsRecoveryContinuation
    ) async -> FileDocument? {
        guard let current = tabStore.activeDocument,
              isSameDocumentLifetime(current, continuation.source)
              || isSameDocumentLifetime(current, continuation.replacement)
        else { return nil }
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
            let acknowledgement = await continuation.replacement.recoveryBuffer.acknowledgeMigration(
                from: continuation.source.id,
                sourceEpoch: continuation.source.recoveryEpoch,
                to: continuation.replacement.id,
                destinationEpoch: continuation.replacement.recoveryEpoch
            )
            guard acknowledgement.isAbsent else {
                lastError = recoveryCleanupError(acknowledgement, document: continuation.source)
                return false
            }
        }
        return await retireFormerSaveAsSource(continuation.source, replacing: continuation.replacement)
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

    private func applySuccessfulSave(
        _ saved: FileDocument,
        originatingFrom document: FileDocument,
        sourceRevision: FileRevision?,
        expectedRevision: FileRevision?,
        context: SaveContext
    ) async {
        guard let current = tabStore.activeDocument,
              isSameDocumentLifetime(current, document)
        else { return }
        if isCurrent(document), isLatestSave(context) {
            tabStore.updateActiveDocument { _ in saved }
            let cleanup = await saved.recoveryBuffer.removeWithOutcome(
                for: saved.id,
                version: saved.mutationGeneration,
                epoch: saved.recoveryEpoch
            )
            if !cleanup.isAbsent {
                pendingRecoveryCleanupActions.insert(.remove(for: saved))
            }
            lastError = cleanup.isAbsent ? nil : recoveryCleanupError(cleanup, document: saved)
            return
        }
        guard current.state != .conflict,
              currentReferencesAcceptedSaveInput(
                  current.lastKnownRevision,
                  sourceRevision: sourceRevision,
                  expectedRevision: expectedRevision
              )
        else { return }
        if current.text == saved.text, isLatestSave(context) {
            tabStore.updateActiveDocument { _ in saved }
            let cleanup = await saved.recoveryBuffer.removeWithOutcome(
                for: saved.id,
                version: saved.mutationGeneration,
                epoch: saved.recoveryEpoch
            )
            if !cleanup.isAbsent {
                pendingRecoveryCleanupActions.insert(.remove(for: saved))
            }
            lastError = cleanup.isAbsent ? nil : recoveryCleanupError(cleanup, document: saved)
            return
        }
        let merged = current.adoptingSavedBaseline(from: saved)
        tabStore.updateActiveDocument { _ in merged }
        guard await merged.persistRecovery() else {
            pendingRecoveryCleanupActions.insert(.persist(for: merged))
            lastError = .recoveryCleanupRequired(merged.fileURL ?? URL(fileURLWithPath: merged.id))
            return
        }
        if isLatestSave(context) {
            lastError = nil
        }
    }

    private func beginSave(for document: FileDocument) -> SaveContext {
        nextSaveGeneration &+= 1
        let context = SaveContext(documentID: document.id, generation: nextSaveGeneration)
        latestSaveGenerationByDocumentID[document.id] = context.generation
        return context
    }
}
