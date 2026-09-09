import FileCore
import Foundation

@MainActor
extension WorkspaceModel {
    /// Result of a Save attempt that is forbidden from presenting a
    /// destination picker. The command palette uses this so its explicit
    /// origin remains authoritative even if the document becomes untitled
    /// or its backing disappears immediately before the save starts.
    public enum NonPromptingSaveResult: Sendable, Equatable {
        case handled
        case requiresDestination
    }

    private enum SaveDestinationPolicy {
        case promptIfNeeded
        case reportRequirement
    }

    /// Saves the active document. Untitled documents prompt for a location.
    public func save() async {
        _ = await save(isRetry: false, destinationPolicy: .promptIfNeeded)
    }

    /// Saves without ever invoking this model's ambient file-panel provider.
    /// Returns `.requiresDestination` when the active document has no usable
    /// backing destination; the caller can then present its own explicitly
    /// scoped Save As UI. The policy is threaded through the metadata-conflict
    /// retry too, so no later re-check can silently fall back to an ambient
    /// panel after the caller chose the non-prompting route.
    public func saveWithoutDestinationPrompt() async -> NonPromptingSaveResult {
        await save(isRetry: false, destinationPolicy: .reportRequirement)
    }

    /// Advisory snapshot of whether a Save *right now* needs a destination.
    /// Useful for validation/tests, but not an atomic routing boundary: a
    /// backing file can disappear immediately after this property is read.
    /// Callers that must guarantee they never prompt ambiently should use
    /// `saveWithoutDestinationPrompt()` instead.
    public var requiresDestinationToSave: Bool {
        guard let document = tabStore.activeDocument else { return false }
        return document.fileURL == nil || isBackingUnavailable(document)
    }

    /// - Parameters:
    ///   - isRetry: `true` for the single automatic retry
    ///     `reconcileSaveConflict` makes after a metadata-only external change.
    ///   - destinationPolicy: whether a missing/unavailable destination may
    ///     invoke the model's ambient Save As panel or must be reported back to
    ///     an explicit-origin caller instead.
    private func save(
        isRetry: Bool,
        destinationPolicy: SaveDestinationPolicy
    ) async -> NonPromptingSaveResult {
        guard let document = tabStore.activeDocument else {
            lastError = .noActiveDocument
            return .handled
        }
        if document.state == .conflict {
            lastError = .unresolvedExternalConflict
            return .handled
        }
        if document.fileURL == nil || isBackingUnavailable(document) {
            if destinationPolicy == .promptIfNeeded {
                await saveAs()
                return .handled
            }
            return .requiresDestination
        }
        guard inFlightSaveAsByDocumentID[document.id] == nil else { return .handled }

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
                return await reconcileSaveConflict(
                    for: document,
                    isRetry: isRetry,
                    destinationPolicy: destinationPolicy
                )
            }
            guard shouldSurfaceSaveFailure(for: document, context: context, error: error) else { return .handled }
            lastError = workspaceError(for: error)
        }
        return .handled
    }

    private func reconcileSaveConflict(
        for document: FileDocument,
        isRetry: Bool,
        destinationPolicy: SaveDestinationPolicy
    ) async -> NonPromptingSaveResult {
        guard let current = tabStore.activeDocument,
              isSameDocumentLifetime(current, document),
              let url = current.fileURL,
              let snapshot = try? current.fileStore.readSnapshot(from: url)
        else {
            lastError = .unresolvedExternalConflict
            return .handled
        }
        let reconciliation = current.reconcilingExternalSnapshot(snapshot)
        tabStore.updateActiveDocument { _ in reconciliation.document }
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
        guard reconciliation.document.state == .dirty || reconciliation.document.state == .promptingClose else {
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
        return await save(isRetry: true, destinationPolicy: destinationPolicy)
    }

    /// Saves the active document to a user-chosen location, prompted via
    /// this model's own `panel` — which resolves against `NSApp.keyWindow`
    /// at presentation time unless the caller bound it to a fixed window.
    /// That is exactly right for the real Save As menu item/shortcut
    /// (invoked *from* the key window), but not for a caller — like the
    /// command palette — that captured a specific origin window earlier
    /// and cannot guarantee it is still key by the time this `await`
    /// resolves. Such a caller should use `saveAs(to:)` instead, having
    /// already presented its own panel explicitly against that window.
    public func saveAs() async {
        guard let document = tabStore.activeDocument else {
            lastError = .noActiveDocument
            return
        }
        guard let url = await panel.chooseSaveLocation(
            defaultName: Self.defaultSaveAsName(for: document),
            format: document.format
        )
        else { return }
        await saveAs(to: url)
    }

    /// Saves the active document to an already-chosen `url` — the caller
    /// having already presented (and dismissed) whatever panel it used to
    /// obtain it, explicitly against whichever window it considers the
    /// operation's origin. `Workspace` has no AppKit window type to accept
    /// here; the caller keeps that context and only hands over the result.
    public func saveAs(to url: URL) async {
        guard let document = tabStore.activeDocument, isCurrent(document) else { return }
        await publishSaveAs(document, to: url)
    }

    /// The filename `saveAs()`'s own panel prompt defaults to — exposed so
    /// a caller presenting its own panel (via `saveAs(to:)`) can offer the
    /// same default without duplicating the fallback-extension logic.
    public static func defaultSaveAsName(for document: FileDocument) -> String {
        document.fileURL?.lastPathComponent ?? "Untitled.\(document.format.extensions.first ?? "md")"
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
