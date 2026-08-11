import Darwin
import Foundation

extension FileStore {
    /// Publishes a conditional write through an atomic exchange, then verifies
    /// the displaced destination before accepting the new bytes. Every
    /// post-swap exit explicitly owns either our temporary bytes, a confirmed
    /// rollback, or a preserved external recovery file.
    func conditionallyPublish(
        temporaryURL: URL,
        destinationURL: URL,
        expectedRevision: FileRevision,
        hooks: ConditionalPublicationTestHooks?
    ) throws(FileStoreError) {
        var ownership: ConditionalPublicationOwnership = .oursAtTemporary
        let publishedRevision = try readSnapshot(from: temporaryURL).revision
        try renameSwap(temporaryURL, destinationURL)
        ownership = .displacedExternalAtTemporary

        let displaced: FileSnapshot
        do {
            try hooks?.beforeDisplacedRead?(temporaryURL)
            displaced = try readSnapshot(from: temporaryURL)
        } catch {
            guard rollbackDisplacedFile(
                temporaryURL,
                destinationURL,
                publishedRevision: publishedRevision,
                hooks: hooks
            ) else {
                let recoveryURL = preserveDisplacedFile(at: temporaryURL, for: destinationURL)
                ownership = .externalRecoveryPreserved(recoveryURL)
                throw .conditionalPublicationRecoveryRequired(recoveryURL)
            }
            ownership = .rollbackConfirmed
            throw mapWriteError(error)
        }

        guard matchesExpectedBaseline(displaced.revision, expectedRevision) else {
            guard rollbackDisplacedFile(
                temporaryURL,
                destinationURL,
                publishedRevision: publishedRevision,
                hooks: hooks
            ) else {
                let recoveryURL = preserveDisplacedFile(at: temporaryURL, for: destinationURL)
                ownership = .externalRecoveryPreserved(recoveryURL)
                throw .conditionalPublicationRecoveryRequired(recoveryURL)
            }
            ownership = .rollbackConfirmed
            throw .fileChangedDuringRead
        }

        do {
            try FileManager.default.removeItem(at: temporaryURL)
            ownership = .accepted
        } catch {
            throw mapWriteError(error)
        }
        assert(ownership == .accepted)
    }

    private func rollbackDisplacedFile(
        _ temporaryURL: URL,
        _ destinationURL: URL,
        publishedRevision: FileRevision,
        hooks: ConditionalPublicationTestHooks?
    ) -> Bool {
        // A second external writer may have replaced our newly published file.
        // It owns the destination now; preserve the earlier displaced writer
        // instead of swapping either external version away.
        do {
            let destination = try readSnapshot(from: destinationURL)
            guard matchesPublishedObject(destination.revision, publishedRevision) else { return false }
            try hooks?.beforeRollbackSwap?(temporaryURL, destinationURL)
            try renameSwap(temporaryURL, destinationURL)
            // The destination can change after the pre-swap validation. In
            // that case the exchange leaves the newer external object at the
            // temporary path. It must be preserved, never mistaken for our
            // bytes and deleted by the write cleanup path.
            let displacedAfterRollback = try readSnapshot(from: temporaryURL)
            guard matchesPublishedObject(displacedAfterRollback.revision, publishedRevision) else {
                return false
            }
            return true
        } catch {
            return false
        }
    }

    private func preserveDisplacedFile(at temporaryURL: URL, for destinationURL: URL) -> URL {
        let recoveryURL = destinationURL.deletingLastPathComponent().appendingPathComponent(
            ".\(destinationURL.lastPathComponent).external-recovery-\(UUID().uuidString)"
        )
        do {
            try FileManager.default.moveItem(at: temporaryURL, to: recoveryURL)
            return recoveryURL
        } catch {
            // `temporaryURL` still contains the displaced bytes. Its path is
            // returned in the dedicated error and must not be cleaned up.
            return temporaryURL
        }
    }

    private func matchesExpectedBaseline(_ actual: FileRevision, _ expected: FileRevision) -> Bool {
        let identityMatches: Bool = if let actualID = actual.fileObjectID, let expectedID = expected.fileObjectID {
            actualID == expectedID
        } else {
            actual.fileObjectID == nil && expected.fileObjectID == nil
        }
        return identityMatches
            && actual.modificationDate == expected.modificationDate
            && actual.fileSize == expected.fileSize
            && actual.sha256 == expected.sha256
    }

    private func matchesPublishedObject(_ actual: FileRevision, _ published: FileRevision) -> Bool {
        guard let actualID = actual.fileObjectID,
              let publishedID = published.fileObjectID,
              actualID == publishedID
        else { return false }
        return actual.fileSize == published.fileSize && actual.sha256 == published.sha256
    }

    private func renameSwap(_ lhs: URL, _ rhs: URL) throws(FileStoreError) {
        let result = lhs.path.withCString { lhsPath in
            rhs.path.withCString { rhsPath in
                renameatx_np(AT_FDCWD, lhsPath, AT_FDCWD, rhsPath, UInt32(RENAME_SWAP))
            }
        }
        guard result == 0 else {
            throw mapWriteError(POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO))
        }
    }
}

struct ConditionalPublicationTestHooks: Sendable {
    let beforeDisplacedRead: (@Sendable (URL) throws -> Void)?
    let beforeRollbackSwap: (@Sendable (URL, URL) throws -> Void)?

    init(
        beforeDisplacedRead: (@Sendable (URL) throws -> Void)? = nil,
        beforeRollbackSwap: (@Sendable (URL, URL) throws -> Void)? = nil
    ) {
        self.beforeDisplacedRead = beforeDisplacedRead
        self.beforeRollbackSwap = beforeRollbackSwap
    }
}

private enum ConditionalPublicationOwnership: Equatable {
    case oursAtTemporary
    case displacedExternalAtTemporary
    case rollbackConfirmed
    case accepted
    case externalRecoveryPreserved(URL)
}
