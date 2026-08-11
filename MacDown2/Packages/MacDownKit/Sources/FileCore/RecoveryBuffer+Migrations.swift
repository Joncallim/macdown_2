import Foundation

public extension RecoveryBuffer {
    /// Returns durable redirects that still await verified session
    /// acknowledgement after a crash or failed publication.
    func pendingMigrations() throws -> [RecoveryMigration] {
        try loadFenceLedgerIfNeeded()
        return fenceLedger.migrations.compactMap { key, record in
            guard let colon = key.firstIndex(of: ":"),
                  let byteCount = Int(key[..<colon])
            else { return nil }
            let start = key.index(after: colon)
            guard let separator = key[start...].firstIndex(of: "|"),
                  key[start ..< separator].utf8.count == byteCount
            else { return nil }
            return RecoveryMigration(
                sourceDocumentID: String(key[start ..< separator]),
                sourceEpoch: String(key[key.index(after: separator)...]),
                destinationDocumentID: record.destinationDocumentID,
                destinationEpoch: record.destinationEpoch
            )
        }
    }
}
