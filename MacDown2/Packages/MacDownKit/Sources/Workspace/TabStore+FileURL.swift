import FileCore
import Foundation

public extension TabStore {
    private struct RenameChange {
        let index: Int
        let document: FileDocument
        let replacement: FileDocument
    }

    private struct AppliedRecoveryMigration {
        let change: RenameChange
        let rollbackEpoch: UUID
    }

    private enum RecoveryRollbackOutcome {
        case restored
        case mixed
    }

    private enum RecoveryMigrationAttempt {
        case completed([AppliedRecoveryMigration])
        case failed([AppliedRecoveryMigration])
    }

    private enum RenamePublishPlan {
        case publish([RenameChange], [AppliedRecoveryMigration], requiresSessionPublication: Bool)
        case failed
    }

    /// Returns the tab for a standardized file URL, if open.
    func tabID(forFileURL url: URL) -> UUID? {
        tabs.first { tab in
            tab.document.fileURL.map { PhysicalFileIdentity.matches($0, url) } ?? false
        }?.id
    }

    /// Applies an in-app move/rename to an open document. External watcher
    /// events deliberately do not call this; that is E18 territory.
    @discardableResult
    func documentWasRenamed(from old: URL, to new: URL) async -> Bool {
        let oldRoot = old.standardizedFileURL
        let newRoot = new.standardizedFileURL
        var changes: [RenameChange] = []
        for (index, tab) in tabs.enumerated() {
            let document = tab.document
            guard let fileURL = document.fileURL?.standardizedFileURL,
                  let remapped = remappedFileURL(fileURL, from: oldRoot, to: newRoot)
            else { continue }
            do {
                let replacement = try await document.renamed(to: remapped, preparedBy: document.recoveryBuffer)
                await onRenameReplacementPrepared?(document)
                // Epoch minting suspends. If the tab changed while it was
                // suspended, retain the current identity rather than publish
                // this stale replacement over the user's newer text.
                guard isCurrentRenameSource(document, at: index) else { continue }
                changes.append(RenameChange(index: index, document: document, replacement: replacement))
            } catch {
                return false
            }
        }
        switch await migrateDirtyRenameRecoveries(changes) {
        case let .failed(appliedMigrations):
            _ = await rollbackRecoveryMigrations(appliedMigrations)
            _ = await publishRenameSession()
            return false
        case let .completed(appliedMigrations):
            switch await makeRenamePublishPlan(changes, migrations: appliedMigrations) {
            case let .publish(currentChanges, currentMigrations, requiresSessionPublication):
                return await publishRenamedTabs(
                    currentChanges,
                    acknowledging: currentMigrations,
                    requiresSessionPublication: requiresSessionPublication
                )
            case .failed:
                return false
            }
        }
    }

    private func isCurrentRenameSource(_ document: FileDocument, at index: Int) -> Bool {
        guard tabs.indices.contains(index) else { return false }
        let current = tabs[index].document
        return current.id == document.id
            && current.fileURL?.standardizedFileURL == document.fileURL?.standardizedFileURL
            && current.recoveryEpoch == document.recoveryEpoch
            && current.text == document.text
            && current.state == document.state
            && current.mutationGeneration == document.mutationGeneration
    }

    private func migrateDirtyRenameRecoveries(_ changes: [RenameChange]) async -> RecoveryMigrationAttempt {
        var appliedMigrations: [AppliedRecoveryMigration] = []
        for change in changes where change.document.state != .clean {
            let rollbackEpoch: UUID
            do {
                rollbackEpoch = try await change.document.recoveryBuffer.mintRecoveryEpoch()
            } catch {
                return .failed(appliedMigrations)
            }
            let outcome = await change.document.recoveryBuffer.migrateWithOutcome(
                from: change.document.id,
                to: change.replacement.id,
                content: change.replacement.text,
                version: change.replacement.mutationGeneration,
                sourceEpoch: change.document.recoveryEpoch,
                destinationEpoch: change.replacement.recoveryEpoch
            )
            guard outcome.isComplete else {
                return .failed(appliedMigrations)
            }
            appliedMigrations.append(AppliedRecoveryMigration(
                change: change,
                rollbackEpoch: rollbackEpoch
            ))
            await onRenameRecoveryMigrationCompleted?(change.document)
        }
        return .completed(appliedMigrations)
    }

    /// Revalidates every captured source after the migration awaits. A stale
    /// source is never replaced by its prepared URL/text snapshot. If its
    /// migration already retired the source lifetime, preserve the current
    /// text under a fresh lifetime before keeping that current identity.
    private func makeRenamePublishPlan(
        _ changes: [RenameChange],
        migrations: [AppliedRecoveryMigration]
    ) async -> RenamePublishPlan {
        let migratedIndexes = Set(migrations.map(\.change.index))
        var reconciledIndexes: Set<Int> = []

        // Preserving one stale tab suspends while it mints and persists a new
        // recovery lifetime. Revalidate the entire batch after every such
        // pass: another tab can change during that await and must not receive
        // its earlier rename snapshot at final publication.
        while true {
            let staleIndexes = Set(changes.compactMap { change in
                !reconciledIndexes.contains(change.index)
                    && !isCurrentRenameSource(change.document, at: change.index)
                    ? change.index
                    : nil
            })
            guard !staleIndexes.isEmpty else {
                let currentChanges = changes.filter { !reconciledIndexes.contains($0.index) }
                // The final session contains either a visible rename
                // replacement or a freshly persisted reconciled identity for
                // every source. Only after that one consistent publication
                // may every completed migration be acknowledged.
                return .publish(
                    currentChanges,
                    migrations,
                    requiresSessionPublication: !reconciledIndexes.isEmpty
                )
            }

            for index in staleIndexes {
                reconciledIndexes.insert(index)
                guard migratedIndexes.contains(index) else { continue }
                guard await preserveCurrentRenameSource(at: index) else {
                    return .failed
                }
            }
        }
    }

    private func preserveCurrentRenameSource(at index: Int) async -> Bool {
        while true {
            guard tabs.indices.contains(index) else { return false }
            let current = tabs[index].document
            do {
                let replacement = try await current.withFreshRecoveryLifetime(preparedBy: current.recoveryBuffer)
                await onRenamePreservationPrepared?(current)
                guard isCurrentRenameSource(current, at: index) else { continue }
                guard await replacement.persistRecovery() else { return false }
                guard isCurrentRenameSource(current, at: index) else { continue }
                tabs[index].document = replacement
                return true
            } catch {
                return false
            }
        }
        return false
    }

    private func publishRenamedTabs(
        _ changes: [RenameChange],
        acknowledging migrations: [AppliedRecoveryMigration],
        requiresSessionPublication: Bool
    ) async -> Bool {
        guard !changes.isEmpty || requiresSessionPublication else { return true }
        for change in changes {
            tabs[change.index].document = change.replacement
        }
        guard await publishRenameSession() else { return false }
        return await acknowledgeRecoveryMigrations(migrations)
    }

    private func publishRenameSession() async -> Bool {
        if let renameSessionPublisher {
            return await renameSessionPublisher()
        }
        return await saveSession()
    }

    private func acknowledgeRecoveryMigrations(_ migrations: [AppliedRecoveryMigration]) async -> Bool {
        for applied in migrations {
            let acknowledged = await applied.change.document.recoveryBuffer.acknowledgeMigration(
                from: applied.change.document.id,
                sourceEpoch: applied.change.document.recoveryEpoch,
                to: applied.change.replacement.id,
                destinationEpoch: applied.change.replacement.recoveryEpoch
            )
            guard acknowledged.isAbsent else { return false }
        }
        return true
    }

    /// Finishes redirects left by a prior process after the destination
    /// identity is present in the restored session. A failed acknowledgement
    /// remains in the durable ledger for the next activation.
    func acknowledgePendingRecoveryMigrations() async {
        guard let migrations = try? await recoveryBuffer.pendingMigrations() else { return }
        for migration in migrations where tabs.contains(where: {
            $0.document.id == migration.destinationDocumentID
                && $0.document.recoveryEpoch.uuidString.lowercased() == migration.destinationEpoch
        }) {
            guard let sourceEpoch = UUID(uuidString: migration.sourceEpoch),
                  let destinationEpoch = UUID(uuidString: migration.destinationEpoch)
            else { continue }
            _ = await recoveryBuffer.acknowledgeMigration(
                from: migration.sourceDocumentID,
                sourceEpoch: sourceEpoch,
                to: migration.destinationDocumentID,
                destinationEpoch: destinationEpoch
            )
        }
    }

    /// A batch only publishes the renamed documents once every dirty recovery
    /// migration has completed. If a later migration fails, migrate completed
    /// recovery records back under their original document IDs with fresh
    /// lifetimes; the visible tabs keep their original URLs and IDs.
    private func rollbackRecoveryMigrations(_ migrations: [AppliedRecoveryMigration]) async -> RecoveryRollbackOutcome {
        var hasForwardRecovery = false
        for applied in migrations.reversed() {
            let change = applied.change
            let rollback = await change.document.recoveryBuffer.migrateWithOutcome(
                from: change.replacement.id,
                to: change.document.id,
                content: change.document.text,
                version: change.replacement.mutationGeneration,
                sourceEpoch: change.replacement.recoveryEpoch,
                destinationEpoch: applied.rollbackEpoch
            )
            guard rollback.isComplete else {
                // This tab's reverse migration could not retire its forward
                // identity. Refresh and retain only this tab's forward
                // recovery. Continue reversing the others: their successful
                // old identities must not be overwritten by batch-wide
                // forward publication.
                guard await refreshForwardRecovery(afterFailedRollback: change) else {
                    tabs[change.index].document = change.replacement
                    return .mixed
                }
                hasForwardRecovery = true
                continue
            }
            tabs[change.index].document = change.document.withReplacementRecoveryLifetime(applied.rollbackEpoch)
        }
        return hasForwardRecovery ? .mixed : .restored
    }

    private func refreshForwardRecovery(afterFailedRollback change: RenameChange) async -> Bool {
        let refreshed: FileDocument
        do {
            refreshed = try await change.replacement.withFreshRecoveryLifetime(
                preparedBy: change.replacement.recoveryBuffer
            )
        } catch {
            return false
        }
        do {
            guard try await refreshed.recoveryBuffer.saveCurrentLifetime(
                content: refreshed.text,
                for: refreshed.id,
                version: refreshed.mutationGeneration,
                epoch: refreshed.recoveryEpoch
            ) else { return false }
        } catch {
            return false
        }
        tabs[change.index].document = refreshed
        return true
    }

    /// Applies a deletion policy to an open document after the filesystem
    /// mutation was accepted.
    func documentFileWasDeleted(at url: URL) -> DeletedDocumentOutcome {
        let deletedRoot = url.standardizedFileURL
        guard let index = tabs.firstIndex(where: { tab in
            guard let fileURL = tab.document.fileURL?.standardizedFileURL else { return false }
            return PhysicalFileIdentity.matches(fileURL, deletedRoot)
                || fileURL.pathComponents.starts(with: deletedRoot.pathComponents)
        }) else { return .notOpen }
        let id = tabs[index].id
        if tabs[index].document.state == .clean {
            removeTab(at: index)
            persist()
            return .closedCleanTab(id)
        }
        return .needsPrompt(id)
    }

    private func remappedFileURL(_ url: URL, from old: URL, to new: URL) -> URL? {
        if PhysicalFileIdentity.matches(url, old) {
            return new.standardizedFileURL
        }
        let components = url.pathComponents
        guard components.starts(with: old.pathComponents) else { return nil }
        let suffix = components.dropFirst(old.pathComponents.count).joined(separator: "/")
        if suffix.isEmpty {
            return new.standardizedFileURL
        }
        return new.appendingPathComponent(suffix, isDirectory: false).standardizedFileURL
    }
}
