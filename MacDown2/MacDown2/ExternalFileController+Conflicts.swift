import FileCore
import Workspace

extension ExternalFileController {
    func resolveConflict(_ resolution: ConflictResolution) async {
        guard !disposed,
              let model,
              let document = model.activeDocument,
              document.state == .conflict
        else { return }
        guard resolution != .cancel else {
            notice = .conflict
            return
        }

        let context = OperationContext(document: document, generation: lifecycleGeneration)
        let observation: DocumentFileObservation = if resolution == .keepMine, let latestExternalSnapshot {
            .available(latestExternalSnapshot)
        } else {
            await monitor.snapshotNow()
        }
        guard isCurrent(context, in: model) else { return }

        await applyConflictObservation(observation, resolution: resolution, document: document, model: model)
    }

    private func applyConflictObservation(
        _ observation: DocumentFileObservation,
        resolution: ConflictResolution,
        document: FileDocument,
        model: WorkspaceModel
    ) async {
        switch observation {
        case let .available(snapshot):
            await applyConflictResolution(resolution, snapshot: snapshot, document: document, model: model)
        case let .moved(snapshot):
            await applyMove(snapshot, to: document, model: model)
            guard let rebound = model.activeDocument,
                  rebound.fileURL?.standardizedFileURL == snapshot.revision.url.standardizedFileURL,
                  rebound.state == .conflict
            else { return }
            await applyConflictResolution(resolution, snapshot: snapshot, document: rebound, model: model)
        case let .missing(url):
            guard url.standardizedFileURL == boundURL else { return }
            applyUnavailable(.missingOrMoved, to: document, model: model)
        case let .unavailable(url, issue):
            guard url.standardizedFileURL == boundURL else { return }
            applyUnavailable(issue, to: document, model: model)
        }
    }

    /// What `applyConflictResolution` actually did. Reopen-with-Encoding used to infer success from the document's
    /// disk revision, which an unchanged document can already carry when the recovery cleanup failed.
    enum ConflictApplication: Equatable {
        case applied
        /// The user's document changed (edit, tab switch, Save As, disposal) while recovery cleanup was awaited, so
        /// the captured disk snapshot was NOT installed over it.
        case superseded
        case cleanupBlocked
        case notApplicable
    }

    @discardableResult
    func applyConflictResolution(
        _ resolution: ConflictResolution,
        snapshot: FileSnapshot,
        document: FileDocument,
        model: WorkspaceModel
    ) async -> ConflictApplication {
        switch resolution {
        case .keepMine:
            let replacement = document.keepingLocalChanges(acknowledging: snapshot.revision)
            model.tabStore.updateActiveDocument { _ in replacement }
            latestExternalSnapshot = nil
            persistRecovery(for: replacement)
            notice = .none
            synchronize(with: replacement)
            coordinator?.scheduleSaveSession()
            return .applied
        case .useExternal:
            let replacement = document.reloadedFromExternal(snapshot)
            let cleanup = await replacement.recoveryBuffer.removeWithOutcome(
                for: replacement.id,
                version: replacement.mutationGeneration,
                epoch: replacement.recoveryEpoch
            )
            await afterUseExternalRecoveryCleanup?()
            // Revalidate after the actor hop: the captured snapshot must never overwrite newer state. The comparison
            // is on CONTENT and lifetime (exact scalars), not the mutation counter, which the file monitor also
            // advances without any text change.
            guard !disposed, let current = model.activeDocument,
                  current.id == document.id,
                  current.recoveryEpoch == document.recoveryEpoch,
                  current.text.isExactlyEqual(to: document.text),
                  current.state == document.state
            else {
                // The removal above may have retired the recovery record of text that is no longer current: make the
                // live document's newest text durable again before giving up.
                if let live = model.activeDocument, live.id == document.id, live.state != .clean {
                    persistRecovery(for: live)
                }
                return .superseded
            }
            guard cleanup.isAbsent else {
                await surfaceRecoveryCleanup(
                    cleanup,
                    buffer: replacement.recoveryBuffer,
                    id: replacement.id,
                    epoch: replacement.recoveryEpoch
                )
                return .cleanupBlocked
            }
            model.tabStore.updateActiveDocument { _ in replacement }
            replaceEditorText(with: replacement.text)
            latestExternalSnapshot = nil
            notice = .none
            synchronize(with: replacement)
            coordinator?.scheduleSaveSession()
            return .applied
        case .cancel:
            return .notApplicable
        }
    }
}
