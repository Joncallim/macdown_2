import CryptoKit
import Foundation

/// Ordered crash-recovery storage keyed by a persisted document lifetime.
///
/// The file name never contains a lossy URL/path sanitisation. It uses a full
/// SHA-256 digest of the document identifier plus the UUID lifetime, so two
/// distinct identifiers cannot alias one another in recovery storage.
public actor RecoveryBuffer {
    public static let shared = RecoveryBuffer()

    static let markerLimit = 256
    let recoveryDirectory: URL
    let hooks: RecoveryBufferHooks?
    var latestMutations: [RecoveryLifetime: RecoveryMutation] = [:]
    var legacyMutations: [String: RecoveryMutation] = [:]
    var activeLifetimes: [String: String] = [:]
    var retiredLifetimes: Set<RecoveryLifetime> = []
    var markerOrder: [RecoveryLifetime] = []
    var fenceLedger = RecoveryFenceLedger()
    var hasLoadedFenceLedger = false

    public init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        recoveryDirectory = appSupport.appendingPathComponent("MacDown 2/Recovery", isDirectory: true)
        hooks = nil
    }

    public init(recoveryDirectory: URL) {
        self.recoveryDirectory = recoveryDirectory
        hooks = nil
    }

    init(recoveryDirectory: URL, beforeSourceRemoval: @escaping @Sendable (URL) throws -> Void) {
        self.recoveryDirectory = recoveryDirectory
        hooks = RecoveryBufferHooks(beforeSourceRemoval: beforeSourceRemoval)
    }

    init(recoveryDirectory: URL, hooks: RecoveryBufferHooks) {
        self.recoveryDirectory = recoveryDirectory
        self.hooks = hooks
    }

    public func save(content: String, for documentID: String, version: UInt? = nil, epoch: UUID? = nil) throws {
        try loadFenceLedgerIfNeeded()
        _ = try save(
            content: content,
            for: documentID,
            version: version,
            epoch: epochIdentifier(epoch),
            replacingActiveLifetime: false
        )
    }

    /// Saves content for the document lifetime that currently owns the live
    /// document. Its durable ownership record rejects a delayed write from a
    /// previously superseded lifetime, including after marker compaction.
    public func saveCurrentLifetime(
        content: String,
        for documentID: String,
        version: UInt,
        epoch: UUID
    ) throws -> Bool {
        try loadFenceLedgerIfNeeded()
        return try save(
            content: content,
            for: documentID,
            version: version,
            epoch: epochIdentifier(epoch),
            replacingActiveLifetime: true
        )
    }

    func save(
        content: String,
        for documentID: String,
        version: UInt?,
        epoch: String?,
        replacingActiveLifetime: Bool
    ) throws -> Bool {
        guard canApply(version, kind: .persist, for: documentID, epoch: epoch),
              try authorizeLifetime(documentID, epoch: epoch, maySupersede: replacingActiveLifetime)
        else { return false }
        try FileManager.default.createDirectory(at: recoveryDirectory, withIntermediateDirectories: true)
        try content.write(to: recoveryURL(for: documentID, epoch: epoch), atomically: true, encoding: .utf8)
        record(version, kind: .persist, for: documentID, epoch: epoch)
        activateLifetime(documentID, epoch: epoch)
        try promoteConsumedLegacyIfSafe(for: documentID, epoch: epoch)
        return true
    }

    /// New session-aware callers provide `epoch`; legacy callers receive the
    /// newest UUID record, falling back to the old pre-lifetime filename.
    public func load(for documentID: String, epoch: UUID? = nil) throws -> String? {
        try loadFenceLedgerIfNeeded()
        guard let url = recoveryURLToLoad(for: documentID, epoch: epochIdentifier(epoch)) else { return nil }
        let content = try String(contentsOf: url, encoding: .utf8)
        try recordConsumedLegacyIfNeeded(documentID: documentID, url: url, content: content)
        return content
    }

    /// Exact crash-recovery artifact for a document lifetime. UI callers use
    /// this only for recovery guidance; it deliberately does not expose a
    /// lexical document URL as though it were a recovery file.
    public func recoveryLocation(for documentID: String, epoch: UUID) -> URL {
        recoveryURL(for: documentID, epoch: epochIdentifier(epoch))
    }

    /// Loads the durable ownership ledger before allocating a managed recovery
    /// lifetime. Document construction must use this rather than minting from
    /// the process-local clock first: a relaunched process can otherwise make
    /// an epoch older than a persisted high-water mark when the wall clock
    /// regresses.
    public func mintRecoveryEpoch() throws -> UUID {
        try loadFenceLedgerIfNeeded()
        return RecoveryLifetimeEpoch.make()
    }

    /// Compatibility removal API. Lifecycle callers should use
    /// `removeWithOutcome` and surface cleanup failures instead of claiming the
    /// recovery record was cleared.
    public func remove(for documentID: String, version: UInt? = nil, epoch: UUID? = nil) {
        _ = removeWithOutcome(for: documentID, version: version, epoch: epoch)
    }

    @discardableResult
    public func removeWithOutcome(
        for documentID: String,
        version: UInt? = nil,
        epoch: UUID? = nil
    ) -> RecoveryCleanupResult {
        let epoch = epochIdentifier(epoch)
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

    public func removeAll() {
        try? FileManager.default.removeItem(at: recoveryDirectory)
        latestMutations.removeAll()
        legacyMutations.removeAll()
        activeLifetimes.removeAll()
        retiredLifetimes.removeAll()
        markerOrder.removeAll()
        fenceLedger = RecoveryFenceLedger()
        hasLoadedFenceLedger = false
    }

    /// Marks exactly one lifetime retired before deleting its recovery. A
    /// failed delete remains observable to callers, while the durable fence
    /// still rejects delayed writes from that lifetime.
    public func retire(for documentID: String, version _: UInt, epoch: UUID) {
        _ = retireWithOutcome(for: documentID, epoch: epoch)
    }

    @discardableResult
    public func retireWithOutcome(for documentID: String, epoch: UUID) -> RecoveryCleanupResult {
        retire(RecoveryLifetime(documentID: documentID, epoch: epoch.uuidString.lowercased()))
    }

    @discardableResult
    func retire(_ lifetime: RecoveryLifetime) -> RecoveryCleanupResult {
        let marker = markLifetimeRetired(lifetime)
        guard marker.isAbsent else { return marker }
        let result = removeRecoveryFile(at: recoveryURL(for: lifetime.documentID, epoch: lifetime.epoch))
        guard result.isAbsent else { return result }
        record(nil, kind: .remove, for: lifetime.documentID, epoch: lifetime.epoch)
        compactMarkers()
        return result
    }

    /// Finalizes a retirement only after the caller has safely removed the
    /// source recovery file. Migration uses this after its staged source
    /// deletion so a failed delete cannot hide the old recovery snapshot.
    @discardableResult
    func markLifetimeRetired(_ lifetime: RecoveryLifetime) -> RecoveryCleanupResult {
        do {
            try loadFenceLedgerIfNeeded()
            try FileManager.default.createDirectory(at: recoveryDirectory, withIntermediateDirectories: true)
            if !isRetired(lifetime) {
                var candidate = fenceLedger
                retainLegacyRetirement(of: lifetime.epoch, documentID: lifetime.documentID, in: &candidate)
                if candidate.currentByDocument[documentDigest(lifetime.documentID)] == lifetime.epoch {
                    candidate.currentByDocument.removeValue(forKey: documentDigest(lifetime.documentID))
                }
                // The ledger is the durable authority. Do not publish either
                // in-memory state or a diagnostic marker until it is on disk.
                try publishFenceLedger(candidate)
                try hooks?.beforeMarkerWrite?(retiredURL(for: lifetime))
                try Data().write(to: retiredURL(for: lifetime), options: .atomic)
                retiredLifetimes.insert(lifetime)
                markerOrder.append(lifetime)
            }
        } catch {
            return .failed(.markerWriteFailed(retiredURL(for: lifetime), errorCode(error)))
        }
        latestMutations[lifetime] = nil
        if activeLifetimes[lifetime.documentID] == lifetime.epoch {
            activeLifetimes[lifetime.documentID] = nil
        }
        return .removed
    }

    public var retainedTombstoneCount: Int {
        markerOrder.count
    }

    public var retainedMarkerCount: Int {
        markerOrder.count
    }

    /// Exact durable ownership records, one per document using the managed
    /// generation protocol. Exposed for regression coverage of ledger bounds.
    public var durableOwnershipCount: Int {
        fenceLedger.highestGenerationByDocument.count
    }

    /// Compatibility wrapper for pre-typed callers. New callers must inspect
    /// `migrateWithOutcome` before retiring the source lifetime.
    @discardableResult
    public func migrate(
        from oldID: String,
        to newID: String,
        content: String,
        version: UInt? = nil,
        sourceEpoch: UUID? = nil,
        destinationEpoch: UUID? = nil
    ) -> Bool {
        migrateWithOutcome(
            from: oldID,
            to: newID,
            content: content,
            version: version,
            sourceEpoch: sourceEpoch,
            destinationEpoch: destinationEpoch
        ).isComplete
    }

    public func migrateWithOutcome(
        from oldID: String,
        to newID: String,
        content: String,
        version: UInt? = nil,
        sourceEpoch: UUID? = nil,
        destinationEpoch: UUID? = nil
    ) -> RecoveryMigrationOutcome {
        do {
            try loadFenceLedgerIfNeeded()
        } catch {
            return .failed(.markerWriteFailed(recoveryFenceURL, errorCode(error)))
        }
        let sourceEpoch = epochIdentifier(sourceEpoch)
        let destinationEpoch = epochIdentifier(destinationEpoch)
        let sourceLifetime = sourceEpoch.map { RecoveryLifetime(documentID: oldID, epoch: $0) }
        let sourceAlreadyRetired = sourceLifetime.map(isRetired) ?? false
        guard oldID != newID,
              sourceAlreadyRetired || canRemoveSource(oldID, version: version, epoch: sourceEpoch)
        else {
            return .rejected
        }
        if let failure = writeMigrationDestination(
            content,
            id: newID,
            version: version,
            epoch: destinationEpoch
        ) {
            return failure
        }
        return retireMigrationSource(
            oldID,
            version: version,
            epoch: sourceEpoch,
            destinationID: newID,
            destinationEpoch: destinationEpoch
        )
    }

    /// Clears a staged source-to-destination redirect only after the caller
    /// has durably published the destination identity. Until this succeeds,
    /// a relaunch restoring the old session identity follows the redirect and
    /// cannot lose the dirty snapshot during a rename/save-as crash window.
    @discardableResult
    public func acknowledgeMigration(
        from oldID: String,
        sourceEpoch: UUID,
        to newID: String,
        destinationEpoch: UUID
    ) -> RecoveryCleanupResult {
        do {
            try loadFenceLedgerIfNeeded()
        } catch {
            return .failed(.markerWriteFailed(recoveryFenceURL, errorCode(error)))
        }
        return finishMigration(
            RecoveryLifetime(documentID: oldID, epoch: epochIdentifier(sourceEpoch) ?? ""),
            destination: RecoveryLifetime(documentID: newID, epoch: epochIdentifier(destinationEpoch) ?? "")
        )
    }
}
