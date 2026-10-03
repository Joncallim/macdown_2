import FileCore
import Foundation

@MainActor
extension WorkspaceModel {
    func shouldSurfaceSaveFailure(
        for document: FileDocument,
        context: SaveContext,
        error _: Error
    ) -> Bool {
        guard isLatestSave(context),
              let current = tabStore.activeDocument,
              isSameDocumentLifetime(current, document)
        else { return false }
        // Relevance is ownership — the latest save of the same document
        // lifetime — not equality with the attempted text: a failure the user
        // is waiting on must be visible even if they typed (or edited and
        // undid) meanwhile. The document stays dirty and its text, undo
        // history and recovery are untouched (#183 F15).
        return true
    }

    /// The URL Save As should write for the chosen `url`, or `nil` (with `lastError` set) when it
    /// must not. A symbolic-link name saves to the file it points at, as opening one does —
    /// `FileStore`'s publication cannot replace a link. A file another window has open is refused.
    func freeDestination(_ url: URL) -> URL? {
        let resolved = url.resolvingFinalSymlink()
        guard isOpenInAnotherWindow?(resolved) == true else { return resolved }
        lastError = .destinationOpenInAnotherWindow(name: resolved.lastPathComponent)
        return nil
    }

    /// Reads and hashes the destination off the main actor: choosing a very large existing file
    /// would otherwise freeze the UI while it is loaded into memory.
    func saveAsBaseline(of document: FileDocument, at url: URL) async throws -> DestinationBaseline? {
        try await Task.detached(priority: .userInitiated) {
            try document.saveAsBaseline(for: url)
        }.value
    }

    /// After the off-main destination read the user may have typed. That is not a reason to abandon an explicit
    /// command: `applySaveAs` merges later edits into the rebound document. Only a different document (closed,
    /// replaced, another lifetime) cancels.
    func activeDocumentSharesLifetime(with expected: FileDocument) -> Bool {
        guard let active = tabStore.activeDocument else { return false }
        return isSameDocumentLifetime(active, expected)
    }

    func isLatestSave(_ context: SaveContext) -> Bool {
        latestSaveGenerationByDocumentID[context.documentID] == context.generation
    }

    func saveAsReplacement(saved: FileDocument, source: FileDocument, context: SaveContext) -> FileDocument? {
        guard isLatestSave(context), let current = tabStore.activeDocument,
              isSameDocumentLifetime(current, source) else { return nil }
        return isCurrent(source) ? saved : current.rebindingSavedDestination(from: saved)
    }

    func persistReconciledSaveAsRecoveryIfNeeded(
        _ replacement: FileDocument,
        replacing initial: FileDocument
    ) async -> Bool {
        guard !sameSaveAsSnapshot(replacement, initial) else { return true }
        guard await replacement.persistRecovery() else {
            lastError = .recoveryCleanupRequired(replacement.fileURL ?? URL(fileURLWithPath: replacement.id))
            return false
        }
        return true
    }

    func sameSaveAsSnapshot(_ lhs: FileDocument, _ rhs: FileDocument) -> Bool {
        lhs.id == rhs.id && lhs.fileURL?.standardizedFileURL == rhs.fileURL?.standardizedFileURL
            && lhs.recoveryEpoch == rhs.recoveryEpoch && lhs.text.isExactlyEqual(to: rhs.text) && lhs.state == rhs.state
            && lhs.mutationGeneration == rhs.mutationGeneration && lhs.pendingExternalRevision == rhs
            .pendingExternalRevision
    }

    func finalizeSaveAsRecovery(
        _ replacement: FileDocument,
        source document: FileDocument,
        context: SaveContext
    ) async -> SaveAsRecoveryOutcome {
        if replacement.state == .clean || document.id == replacement.id {
            let destinationCleanup = await replacement.recoveryBuffer.removeWithOutcome(
                for: replacement.id, version: replacement.mutationGeneration, epoch: replacement.recoveryEpoch
            )
            guard destinationCleanup.isAbsent else {
                registerPendingRecovery(.remove(for: replacement))
                lastError = recoveryCleanupError(destinationCleanup, document: replacement)
                return .failed
            }
            return .readyToPublish
        }
        let migration = await document.recoveryBuffer.migrateWithOutcome(
            from: document.id, to: replacement.id, content: replacement.text,
            version: replacement.mutationGeneration, sourceEpoch: document.recoveryEpoch,
            destinationEpoch: replacement.recoveryEpoch
        )
        guard migration.isComplete else {
            enqueueSaveAsRetry(.migrate(source: document, destination: replacement), source: document,
                               replacement: replacement, context: context, phase: .publishDestination)
            lastError = recoveryMigrationError(migration, document: document)
            return .failed
        }
        return .migrationPending
    }

    func retireFormerSaveAsSource(_ source: FileDocument, replacing destination: FileDocument) async -> Bool {
        guard source.id != destination.id || source.recoveryEpoch != destination.recoveryEpoch else { return true }
        let pending = PendingRecoveryCleanupAction.retire(for: source)
        let outcome = await source.recoveryBuffer.retireWithOutcome(for: source.id, epoch: source.recoveryEpoch)
        guard outcome.isAbsent else {
            registerPendingRecovery(pending)
            lastError = recoveryCleanupError(outcome, document: source)
            return false
        }
        pendingRecoveryCleanupActions.remove(pending)
        return true
    }

    func publishSaveAsSession() async -> Bool {
        if let saveAsSessionPublisher {
            return await saveAsSessionPublisher()
        }
        return await tabStore.saveSession()
    }

    /// A completed migration can already own an identical destination record
    /// at this exact version. `saveCurrentLifetime` correctly rejects that
    /// duplicate write; verify the immutable bytes instead of treating the
    /// no-op as an unsafe recovery failure.
    func recoverySnapshotIsDurable(for document: FileDocument) async -> Bool {
        guard document.state != .clean else { return true }
        if await document.persistRecovery() {
            return true
        }
        do {
            return try await document.recoveryBuffer.load(
                for: document.id,
                epoch: document.recoveryEpoch
            ) == document.text
        } catch {
            return false
        }
    }

    /// A retry must never remove or fence a recovery payload that has become
    /// the active document's newer state. Rotate and persist that state first,
    /// then replay the cleanup against the captured lifetime only.
    func preserveEditedCleanupDocument(for pending: PendingRecoveryCleanupAction) async -> Bool {
        guard let current = tabStore.activeDocument,
              current.id == pending.documentID,
              current.recoveryEpoch == pending.epoch,
              !pending.matches(current)
        else { return true }
        do {
            let replacement = try await current.withFreshRecoveryLifetime(preparedBy: current.recoveryBuffer)
            guard isCurrent(current), await replacement.persistRecovery() else {
                lastError = .recoveryCleanupRequired(current.fileURL ?? URL(fileURLWithPath: current.id))
                return false
            }
            tabStore.updateActiveDocument { _ in replacement }
            guard await rekeySaveAsContinuationIfNeeded(from: pending, to: replacement) else {
                lastError = .recoveryCleanupRequired(replacement.fileURL ?? URL(fileURLWithPath: replacement.id))
                return false
            }
            return true
        } catch {
            lastError = .recoveryCleanupRequired(current.fileURL ?? URL(fileURLWithPath: current.id))
            return false
        }
    }

    /// A retry action is keyed by its immutable captured lifetime. Once a
    /// newer edit has been rotated into a fresh epoch, replace both keys as
    /// one main-actor transaction. The old migration redirect stays durable
    /// until the successor is canonically published and acknowledged.
    private func rekeySaveAsContinuationIfNeeded(
        from action: PendingRecoveryCleanupAction,
        to replacement: FileDocument
    ) async -> Bool {
        guard let continuation = pendingSaveAsRecoveryContinuations[action] else { return false }
        let migration = await replacement.recoveryBuffer.migrateWithOutcome(
            from: continuation.source.id,
            to: replacement.id,
            content: replacement.text,
            version: replacement.mutationGeneration,
            sourceEpoch: continuation.source.recoveryEpoch,
            destinationEpoch: replacement.recoveryEpoch
        )
        guard migration.isComplete else { return false }
        let successor = PendingRecoveryCleanupAction.migrate(source: continuation.source, destination: replacement)
        let successorContinuation = continuation
            .withReplacement(replacement)
            .withPhase(.publishDestination)
        completePendingRecovery(action)
        registerPendingRecovery(successor, continuation: successorContinuation)
        return true
    }

    func cast(_ error: Error) -> FileStoreError {
        error as? FileStoreError ?? .readFailed(underlying: error)
    }

    func workspaceError(for error: Error) -> WorkspaceError {
        let fileStoreError = cast(error)
        if case let .conditionalPublicationRecoveryRequired(url) = fileStoreError {
            return .conditionalPublicationRecoveryRequired(url)
        }
        // Name the encoding the write actually attempted: a queued save can
        // inherit an accepted encoding change (#183 F10).
        if case let .textNotRepresentable(attempted) = fileStoreError {
            return .textNotRepresentable(encodingName: attempted.displayName)
        }
        return .saveFailed(underlying: fileStoreError)
    }

    func recoveryCleanupError(_ result: RecoveryCleanupResult, document: FileDocument) -> WorkspaceError {
        switch result {
        case .removed, .alreadyAbsent:
            .recoveryCleanupRequired(document.fileURL ?? URL(fileURLWithPath: document.id))
        case let .failed(error):
            .recoveryCleanupRequired(recoveryURL(from: error, fallback: document))
        }
    }

    func recoveryMigrationError(_ outcome: RecoveryMigrationOutcome, document: FileDocument) -> WorkspaceError {
        switch outcome {
        case let .failed(error):
            .recoveryCleanupRequired(recoveryURL(from: error, fallback: document))
        case let .sourceRetained(result):
            recoveryCleanupError(result, document: document)
        case .migrated, .rejected:
            .recoveryCleanupRequired(document.fileURL ?? URL(fileURLWithPath: document.id))
        }
    }

    func recoveryURL(from error: RecoveryBufferError, fallback _: FileDocument) -> URL {
        switch error {
        case let .markerWriteFailed(url, _), let .removalFailed(url, _), let .writeFailed(url, _),
             let .verificationFailed(url):
            url
        }
    }
}

struct SaveContext: Sendable {
    let documentID: String
    let generation: UInt
    /// `lastError`'s revision when the save began, so a late success cannot
    /// erase an error another operation published meanwhile (#183 F15).
    let errorRevision: UInt64
}

struct PendingRecoveryCleanupAction: Sendable, Hashable {
    enum Kind: Sendable, Hashable {
        case remove, retire, persist, migrate, acknowledgeMigration, publishSession
    }

    let kind: Kind
    let documentID: String
    let epoch: UUID
    let mutationGeneration: UInt
    let text: String
    let state: FileDocumentState
    let sourceDocumentID: String?
    let sourceEpoch: UUID?
    let recoveryBuffer: RecoveryBuffer?

    static func remove(for document: FileDocument) -> Self {
        Self(kind: .remove, document: document)
    }

    static func retire(for document: FileDocument) -> Self {
        Self(kind: .retire, document: document)
    }

    static func persist(for document: FileDocument) -> Self {
        Self(kind: .persist, document: document)
    }

    static func migrate(source: FileDocument, destination: FileDocument) -> Self {
        Self(
            kind: .migrate,
            document: destination,
            source: source
        )
    }

    static func acknowledgeMigration(source: FileDocument, destination: FileDocument) -> Self {
        Self(
            kind: .acknowledgeMigration,
            document: destination,
            source: source
        )
    }

    static func publishSession(for document: FileDocument) -> Self {
        Self(kind: .publishSession, document: document)
    }

    func matches(_ document: FileDocument) -> Bool {
        document.id == documentID && document.recoveryEpoch == epoch
            && document.mutationGeneration == mutationGeneration && document.text.isExactlyEqual(to: text) && document
            .state == state
    }

    /// Identity is the action's kind and the exact lifetime(s) it targets — for
    /// a migration both the source and destination lifetimes. It deliberately
    /// excludes the captured payload (text, mutation, state), which a later
    /// failure for the same lifetime must be able to replace; see
    /// `WorkspaceModel.registerPendingRecovery(_:continuation:)` (#183 F01).
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.kind == rhs.kind && lhs.documentID == rhs.documentID && lhs.epoch == rhs.epoch
            && lhs.sourceDocumentID == rhs.sourceDocumentID && lhs.sourceEpoch == rhs.sourceEpoch
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(kind); hasher.combine(documentID); hasher.combine(epoch)
        hasher.combine(sourceDocumentID); hasher.combine(sourceEpoch)
    }

    /// Whether `other` (same identity) captured the same payload, i.e. the same
    /// document version, so completing one completes the other.
    func hasSamePayload(as other: Self) -> Bool {
        mutationGeneration == other.mutationGeneration && state == other.state && text.isExactlyEqual(to: other.text)
    }

    private init(kind: Kind, document: FileDocument) {
        self.init(kind: kind, document: document, source: nil)
    }

    private init(kind: Kind, document: FileDocument, source: FileDocument?) {
        self.kind = kind; documentID = document.id; epoch = document.recoveryEpoch
        mutationGeneration = document.mutationGeneration; text = document.text; state = document.state
        sourceDocumentID = source?.id; sourceEpoch = source?.recoveryEpoch; recoveryBuffer = document.recoveryBuffer
    }
}

struct SaveAsRecoveryContinuation: Sendable {
    let source: FileDocument
    let replacement: FileDocument
    let context: SaveContext
    let phase: SaveAsRecoveryRetryPhase
    func withPhase(_ phase: SaveAsRecoveryRetryPhase) -> Self {
        Self(
            source: source,
            replacement: replacement,
            context: context,
            phase: phase
        )
    }

    func withReplacement(_ replacement: FileDocument) -> Self {
        Self(
            source: source,
            replacement: replacement,
            context: context,
            phase: phase
        )
    }
}

enum SaveAsRecoveryRetryPhase: Sendable { case publishDestination, sessionPublished, retireSource }
enum SaveAsRecoveryOutcome { case readyToPublish, migrationPending, failed }
