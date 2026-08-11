import Foundation

public extension RecoveryBuffer {
    /// Compatibility seams for pre-UUID tests and recovery records. Production
    /// `FileDocument` always supplies a persisted UUID lifetime.
    func save(content: String, for documentID: String, version: UInt? = nil, epoch: UInt) throws {
        try loadFenceLedgerIfNeeded()
        let lifetime = legacyLifetime(epoch)
        let mayReplace = activeLifetimes[documentID].map { lifetime > $0 } ?? true
        _ = try save(
            content: content,
            for: documentID,
            version: version,
            epoch: lifetime,
            replacingActiveLifetime: mayReplace
        )
    }

    func load(for documentID: String, epoch: UInt) throws -> String? {
        try loadFenceLedgerIfNeeded()
        guard let url = recoveryURLToLoad(for: documentID, epoch: legacyLifetime(epoch)) else { return nil }
        return try String(contentsOf: url, encoding: .utf8)
    }

    func remove(for documentID: String, version: UInt? = nil, epoch: UInt) {
        let epoch = legacyLifetime(epoch)
        _ = removeLegacyWithOutcome(for: documentID, version: version, epoch: epoch)
    }

    func retire(for documentID: String, version _: UInt, epoch: UInt) {
        _ = retire(RecoveryLifetime(documentID: documentID, epoch: legacyLifetime(epoch)))
    }

    @discardableResult
    func migrate(
        from oldID: String,
        to newID: String,
        content: String,
        version: UInt? = nil,
        sourceEpoch: UInt? = nil,
        destinationEpoch: UInt? = nil
    ) -> Bool {
        migrate(
            from: oldID,
            to: newID,
            content: content,
            version: version,
            sourceEpoch: sourceEpoch.map(legacyUUID),
            destinationEpoch: destinationEpoch.map(legacyUUID)
        )
    }

    private func legacyLifetime(_ value: UInt) -> String {
        String(format: "00000000-0000-0000-0000-%012llx", value)
    }

    private func legacyUUID(_ value: UInt) -> UUID {
        let valueString = legacyLifetime(value)
        guard let lifetime = UUID(uuidString: valueString) else {
            preconditionFailure("A fixed-width recovery lifetime must be a valid UUID")
        }
        return lifetime
    }

    private func removeLegacyWithOutcome(
        for documentID: String,
        version: UInt?,
        epoch: String
    ) -> RecoveryCleanupResult {
        do {
            try loadFenceLedgerIfNeeded()
        } catch {
            return .failed(.markerWriteFailed(recoveryFenceURL, errorCode(error)))
        }
        guard canApply(version, kind: .remove, for: documentID, epoch: epoch) else { return .alreadyAbsent }
        let result = removeRecoveryFile(at: recoveryURL(for: documentID, epoch: epoch))
        guard result.isAbsent else { return result }
        record(version, kind: .remove, for: documentID, epoch: epoch)
        return result
    }
}
