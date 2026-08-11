import Foundation

extension RecoveryBuffer {
    func writeMigrationDestination(
        _ content: String,
        id: String,
        version: UInt?,
        epoch: String?
    ) -> RecoveryMigrationOutcome? {
        do {
            try FileManager.default.createDirectory(at: recoveryDirectory, withIntermediateDirectories: true)
            let destination = recoveryURL(for: id, epoch: epoch)
            let accepted = destinationAlreadyContains(content, at: destination, for: id, version: version, epoch: epoch)
            if !accepted {
                guard canMigrate(to: id, epoch: epoch),
                      canApply(version, kind: .persist, for: id, epoch: epoch),
                      try authorizeLifetime(id, epoch: epoch, maySupersede: true)
                else { return .rejected }
                try content.write(to: destination, atomically: true, encoding: .utf8)
                guard try String(contentsOf: destination, encoding: .utf8) == content else {
                    return .failed(.verificationFailed(destination))
                }
                record(version, kind: .persist, for: id, epoch: epoch)
                activateLifetime(id, epoch: epoch)
            }
        } catch {
            return .failed(.writeFailed(recoveryURL(for: id, epoch: epoch), errorCode(error)))
        }
        return nil
    }

    func retireMigrationSource(
        _ id: String,
        version: UInt?,
        epoch: String?,
        destinationID: String,
        destinationEpoch: String?
    ) -> RecoveryMigrationOutcome {
        if let epoch {
            let lifetime = RecoveryLifetime(documentID: id, epoch: epoch)
            guard let destinationEpoch else {
                return .failed(.verificationFailed(recoveryURL(for: destinationID, epoch: nil)))
            }
            let destination = RecoveryLifetime(documentID: destinationID, epoch: destinationEpoch)
            let staged = stageMigration(from: lifetime, to: destination)
            guard staged.isAbsent else { return .sourceRetained(staged) }

            let cleanup = removeRecoveryFile(
                at: recoveryURL(for: id, epoch: epoch),
                sourceRemoval: true
            )
            guard cleanup.isAbsent else {
                // A hook can fail after deletion to model a process crash.
                // Keep the durable source→destination record whenever source
                // bytes are already gone so restart recovery follows it.
                if FileManager.default.fileExists(atPath: recoveryURL(for: id, epoch: epoch).path) {
                    // The source bytes survived, so this migration has not
                    // crossed its durable publication boundary. Remove the
                    // staged redirect rather than teaching a later restore to
                    // prefer a destination the caller never published.
                    _ = finishMigration(lifetime, destination: destination)
                    return .sourceRetained(cleanup)
                }
                return .failed(recoveryError(from: cleanup))
            }

            let retirement = markLifetimeRetired(lifetime)
            guard retirement.isAbsent else {
                // Keep the staged intent: source bytes are gone, and a late
                // write must not resurrect this old lifetime.
                return .failed(recoveryError(from: retirement))
            }
            // Migration retirements create the same diagnostic markers as
            // ordinary closes. Compact them here as well so repeated rename
            // and Save As cycles cannot bypass the global marker bound.
            compactMarkers()
            // Deliberately retain the source -> destination redirect. The
            // caller must first durably publish the replacement identity to
            // its session and then explicitly acknowledge this migration.
            // A crash in that interval can still restore the draft through
            // the former session identity.
        } else {
            let cleanup = removeRecoveryFile(at: recoveryURL(for: id, epoch: epoch), sourceRemoval: true)
            guard cleanup.isAbsent else { return .sourceRetained(cleanup) }
            record(version, kind: .remove, for: id, epoch: epoch)
        }
        return .migrated
    }

    private func recoveryError(from outcome: RecoveryCleanupResult) -> RecoveryBufferError {
        if case let .failed(error) = outcome {
            return error
        }
        return .verificationFailed(recoveryDirectory)
    }
}
