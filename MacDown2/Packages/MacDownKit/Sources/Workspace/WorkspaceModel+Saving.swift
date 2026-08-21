import FileCore
import Foundation

@MainActor
extension WorkspaceModel {
    /// Saves the active document. Untitled documents prompt for a location.
    public func save() async {
        await save(isRetry: false)
    }

    /// - Parameter isRetry: `true` for the single automatic retry
    ///   `reconcileSaveConflict` makes after a metadata-only external change.
    ///   Bounds that retry to exactly one attempt so a file whose metadata
    ///   keeps changing (a misbehaving sync client, for example) cannot
    ///   recurse indefinitely.
    private func save(isRetry: Bool) async {
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
            if case FileStoreError.fileChangedDuringRead = error {
                await reconcileSaveConflict(for: document, isRetry: isRetry)
                return
            }
            guard shouldSurfaceSaveFailure(for: document, context: context, error: error) else { return }
            lastError = workspaceError(for: error)
        }
    }

    private func reconcileSaveConflict(for document: FileDocument, isRetry: Bool) async {
        guard let current = tabStore.activeDocument,
              isSameDocumentLifetime(current, document),
              let url = current.fileURL,
              let snapshot = try? current.fileStore.readSnapshot(from: url)
        else {
            lastError = .unresolvedExternalConflict
            return
        }
        let reconciliation = current.reconcilingExternalSnapshot(snapshot)
        tabStore.updateActiveDocument { _ in reconciliation.document }
        if reconciliation.document.state == .conflict {
            _ = await reconciliation.document.persistRecovery()
            lastError = .unresolvedExternalConflict
            return
        }
        guard reconciliation.document.state == .dirty else { return }
        guard !isRetry else {
            // Something is touching this file's metadata faster than one
            // retry can keep up with. Stop instead of recursing indefinitely,
            // and say so rather than leaving the document dirty with no
            // explanation.
            lastError = workspaceError(for: FileStoreError.fileChangedDuringRead)
            return
        }
        // The write failed only because the on-disk baseline had moved, not
        // because its content actually diverged (a real divergence lands in
        // `.conflict` above). Reconciliation just brought the baseline
        // current, so retry the save the user actually asked for instead of
        // leaving it dirty with no error and no indication anything failed —
        // but only once: a second consecutive metadata-only change means
        // something external is outpacing us, and that deserves a real error
        // rather than another silent attempt.
        await save(isRetry: true)
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
