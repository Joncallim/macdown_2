import FileCore
import Foundation
import Workspace

extension ExternalFileController {
    var recoveryRetryKind: RecoveryRetryKind? {
        guard let recoveryRetryAction else { return nil }
        switch recoveryRetryAction {
        case .persist:
            return .persist
        case .remove:
            return .remove
        case .migrate:
            return .migrate
        case .retire:
            return .retire
        }
    }

    func prepareMoveRecovery(from document: FileDocument, to replacement: FileDocument) async -> Bool {
        let action: RecoveryAction
        let context: RecoveryActionContext
        if replacement.state == .dirty || replacement.state == .conflict {
            action = .migrate(
                document.recoveryBuffer,
                oldID: document.id,
                sourceEpoch: document.recoveryEpoch,
                document: replacement,
                ownerID: document.id,
                ownerEpoch: document.recoveryEpoch,
                lifecycleGeneration
            )
            context = RecoveryActionContext(
                action: action,
                id: document.id,
                epoch: document.recoveryEpoch,
                generation: lifecycleGeneration
            )
            return await performRecoveryMigration(
                document.recoveryBuffer,
                oldID: document.id,
                sourceEpoch: document.recoveryEpoch,
                document: replacement,
                context: context
            ).isComplete
        }
        action = .remove(
            document.recoveryBuffer,
            document.id,
            replacement.mutationGeneration,
            document.recoveryEpoch,
            lifecycleGeneration
        )
        context = RecoveryActionContext(
            action: action,
            id: document.id,
            epoch: document.recoveryEpoch,
            generation: lifecycleGeneration
        )
        return await performRecoveryRemoval(
            document.recoveryBuffer,
            version: replacement.mutationGeneration,
            context: context
        ).isAbsent
    }

    struct PendingMove {
        let context: OperationContext
        let source: FileDocument
        let replacement: FileDocument
        let snapshot: FileSnapshot
    }

    struct PendingClose {
        let documentID: String
        let epoch: UUID
        let mutationGeneration: UInt
        let lifecycleGeneration: UInt

        init(document: FileDocument, lifecycleGeneration: UInt) {
            documentID = document.id
            epoch = document.recoveryEpoch
            mutationGeneration = document.mutationGeneration
            self.lifecycleGeneration = lifecycleGeneration
        }
    }

    func resumePendingClose(after action: RecoveryAction) async {
        guard case let .retire(_, id, epoch, generation) = action,
              let pendingClose,
              pendingClose.documentID == id,
              pendingClose.epoch == epoch,
              pendingClose.lifecycleGeneration == generation,
              lifecycleGeneration == generation,
              let model,
              let current = model.activeDocument,
              current.id == id,
              current.recoveryEpoch == epoch
        else { return }
        self.pendingClose = nil
        guard current.mutationGeneration == pendingClose.mutationGeneration else {
            await preserveOpenDocumentAfterFailedClose(current, model: model)
            return
        }
        owner?.completeCloseAfterRecoveryRetry(
            documentID: pendingClose.documentID,
            recoveryEpoch: pendingClose.epoch,
            mutationGeneration: pendingClose.mutationGeneration
        )
    }

    /// The document a bind retry must (re)install: the LIVE one when it is still the captured document's file.
    static func bindRetryDocument(live: FileDocument?, captured: FileDocument, url: URL) -> FileDocument? {
        guard let live, live.id == captured.id, live.fileURL?.standardizedFileURL == url else { return nil }
        return live
    }

    func scheduleBindRetry(for document: FileDocument, generation: UInt) {
        guard let url = document.fileURL?.standardizedFileURL, bindRetryAttempt < 3 else { return }
        bindRetryAttempt += 1
        let attempt = bindRetryAttempt
        bindRetryTask?.cancel()
        bindRetryTask = Task { @MainActor [weak self] in
            do {
                guard let sleep = self?.bindRetrySleep else { return }
                try await sleep(.milliseconds(250 * (1 << (attempt - 1))))
            } catch {
                return
            }
            guard let self, isBindingCurrent(generation: generation, url: url) else { return }
            // Retry with the LIVE document (its current encoding policy and revision), not the one captured when the
            // watcher first failed: a successful Save with Encoding in the meantime changed the policy, and
            // reinstalling the old one made the monitor report the saved file undecodable (and the document dirty).
            guard let live = Self.bindRetryDocument(live: model?.activeDocument, captured: document, url: url) else {
                return
            }
            boundURL = nil
            synchronize(with: live)
        }
    }

    private func preserveOpenDocumentAfterFailedClose(_ document: FileDocument, model: WorkspaceModel) async {
        do {
            let originalContext = OperationContext(document: document, generation: lifecycleGeneration)
            let replacement = try await document.withFreshRecoveryLifetime(preparedBy: document.recoveryBuffer)
            guard isCurrent(originalContext, in: model) else { return }

            // The old lifetime was retired by the successful retry. Make the
            // fresh lifetime current before persistence so a failed write has
            // an exact, retryable owner rather than leaving the visible
            // document attached to a retired recovery key.
            model.tabStore.updateActiveDocument { _ in replacement }
            synchronize(with: replacement)

            let action = RecoveryAction.persist(replacement, lifecycleGeneration)
            let replacementContext = OperationContext(document: replacement, generation: lifecycleGeneration)
            guard await recoveryExecutor.persist(replacement) else {
                guard isCurrent(replacementContext, in: model) else { return }
                recoveryRetryAction = action
                let location = await replacement.recoveryBuffer.recoveryLocation(
                    for: replacement.id,
                    epoch: replacement.recoveryEpoch
                )
                notice = .recoveryCleanup(location)
                return
            }
            coordinator?.scheduleSaveSession()
        } catch {
            let location = await document.recoveryBuffer.recoveryLocation(
                for: document.id,
                epoch: document.recoveryEpoch
            )
            notice = .recoveryCleanup(location)
        }
    }

    /// A move recovery migration may finish just as a user edit replaces its
    /// source snapshot. The old lifetime is then retired, so preserve the
    /// currently visible text under a new managed lifetime instead of leaving
    /// the active document attached to the retired source epoch.
    func preserveCurrentDocumentAfterStaleInitialMove(in model: WorkspaceModel) async {
        guard let current = model.activeDocument else {
            pendingMove = nil
            return
        }
        let context = OperationContext(document: current, generation: lifecycleGeneration)
        do {
            let replacement = try await current.withFreshRecoveryLifetime(preparedBy: current.recoveryBuffer)
            guard isCurrent(context, in: model) else {
                pendingMove = nil
                return
            }
            model.tabStore.updateActiveDocument { _ in replacement }
            pendingMove = nil
            synchronize(with: replacement)

            let action = RecoveryAction.persist(replacement, lifecycleGeneration)
            let replacementContext = OperationContext(document: replacement, generation: lifecycleGeneration)
            guard await recoveryExecutor.persist(replacement) else {
                guard isCurrent(replacementContext, in: model) else { return }
                recoveryRetryAction = action
                notice = await .recoveryCleanup(replacement.recoveryBuffer.recoveryLocation(
                    for: replacement.id,
                    epoch: replacement.recoveryEpoch
                ))
                return
            }
            coordinator?.scheduleSaveSession()
        } catch {
            pendingMove = nil
            notice = await .recoveryCleanup(current.recoveryBuffer.recoveryLocation(
                for: current.id,
                epoch: current.recoveryEpoch
            ))
        }
    }
}
