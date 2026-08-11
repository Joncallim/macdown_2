import CryptoKit
import Foundation

extension RecoveryBuffer {
    func canApply(_ version: UInt?, kind: RecoveryMutation.Kind, for id: String, epoch: String?) -> Bool {
        guard let epoch else {
            guard let version, let latest = legacyMutations[id] else { return true }
            if version != latest.version {
                return version > latest.version
            }
            return kind == .remove && latest.kind == .persist
        }
        let lifetime = RecoveryLifetime(documentID: id, epoch: epoch)
        guard !isRetired(lifetime), let version else { return !isRetired(lifetime) }
        guard let latest = latestMutations[lifetime] else { return true }
        if version != latest.version {
            return version > latest.version
        }
        return kind == .remove && latest.kind == .persist
    }

    func canRemoveSource(_ id: String, version: UInt?, epoch: String?) -> Bool {
        guard let epoch else { return true }
        let lifetime = RecoveryLifetime(documentID: id, epoch: epoch)
        guard !isRetired(lifetime), let version, let latest = latestMutations[lifetime] else {
            return !isRetired(lifetime)
        }
        return version >= latest.version
    }

    func record(_ version: UInt?, kind: RecoveryMutation.Kind, for id: String, epoch: String?) {
        guard let version else { return }
        if let epoch {
            latestMutations[RecoveryLifetime(documentID: id, epoch: epoch)] = RecoveryMutation(
                version: version,
                kind: kind
            )
        } else {
            legacyMutations[id] = RecoveryMutation(version: version, kind: kind)
        }
    }

    func activateLifetime(_ id: String, epoch: String?) {
        guard let epoch else { return }
        activeLifetimes[id] = epoch
    }

    /// The fence ledger is authoritative after diagnostic `.retired` files are
    /// compacted. A lifetime already observed as old can never claim ownership
    /// again; a new lifetime may deliberately supersede the current owner.
    func authorizeLifetime(_ id: String, epoch: String?, maySupersede: Bool) throws -> Bool {
        guard let epoch else { return true }
        let lifetime = RecoveryLifetime(documentID: id, epoch: epoch)
        let documentKey = documentDigest(id)
        let generation = RecoveryLifetimeEpoch.generation(for: epoch)
        var candidate = fenceLedger
        let isPreviouslySeen = isRetired(lifetime)
            || fenceLedger.knownLifetimes.contains(lifetime.fenceKey)
        if let current = fenceLedger.currentByDocument[documentKey] {
            if current == epoch {
                return true
            }
            if isPreviouslySeen {
                return false
            }
            guard maySupersede else { return false }
            if isStaleGeneration(generation, for: documentKey) {
                return false
            }
            retainLegacyRetirement(of: current, documentID: id, in: &candidate)
        } else if isPreviouslySeen {
            // No current owner is not permission to revive an old one. This
            // remains true after a restart and after diagnostic marker files
            // have been compacted; the durable ledger is the authority.
            return false
        } else if isStaleGeneration(generation, for: documentKey) {
            return false
        }
        candidate.currentByDocument[documentKey] = epoch
        if let generation {
            candidate.highestGenerationByDocument[documentKey] = generation
            candidate.globalHighestGeneration = max(candidate.globalHighestGeneration, generation)
            compactInactiveManagedOwnership(in: &candidate)
        } else {
            candidate.knownLifetimes.insert(lifetime.fenceKey)
        }
        // Authorisation is a durable ownership hand-off. An I/O failure must
        // leave this actor exactly as it was so the same lifetime can retry.
        try publishFenceLedger(candidate)
        return true
    }

    private func isStaleGeneration(_ generation: UInt64?, for documentKey: String) -> Bool {
        guard let generation else { return false }
        let documentHighWater = fenceLedger.highestGenerationByDocument[documentKey, default: 0]
        return generation <= max(documentHighWater, fenceLedger.globalHighestGeneration)
    }

    func canMigrate(to id: String, epoch: String?) -> Bool {
        guard let epoch else { return true }
        if let active = activeLifetimes[id] {
            return active == epoch
        }
        let current = fenceLedger.currentByDocument[documentDigest(id)]
        return current == nil || current == epoch
    }

    func destinationAlreadyContains(
        _ content: String,
        at url: URL,
        for id: String,
        version: UInt?,
        epoch: String?
    ) -> Bool {
        guard let version, let epoch,
              latestMutations[RecoveryLifetime(documentID: id, epoch: epoch)] == RecoveryMutation(
                  version: version,
                  kind: .persist
              ),
              let stored = try? String(contentsOf: url, encoding: .utf8)
        else { return false }
        return stored == content
    }

    func recoveryURLToLoad(for id: String, epoch: String?) -> URL? {
        if let epoch {
            return recoveryURLToLoad(
                for: RecoveryLifetime(documentID: id, epoch: epoch),
                visited: []
            )
        }
        let prefix = "\(documentDigest(id))."
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: recoveryDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        let current = urls
            .filter { $0.lastPathComponent.hasPrefix(prefix) && $0.pathExtension == "md" }
            .filter { !isRetiredURL($0, documentID: id) }
            .max { modificationDate(of: $0) < modificationDate(of: $1) }
        if let current {
            return current
        }
        let legacy = legacyRecoveryURL(for: id)
        return FileManager.default.fileExists(atPath: legacy.path) ? legacy : nil
    }

    /// Follows durable migration redirects until it finds the surviving
    /// recovery artifact. A rename rollback may stage A -> B -> C before a
    /// session can publish C, so one redirect hop is not sufficient after a
    /// restart. `visited` makes corrupt/cyclic ledgers fail closed.
    private func recoveryURLToLoad(
        for lifetime: RecoveryLifetime,
        visited: Set<RecoveryLifetime>
    ) -> URL? {
        guard !visited.contains(lifetime) else { return nil }
        let url = recoveryURL(for: lifetime.documentID, epoch: lifetime.epoch)
        if !isRetired(lifetime), FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        guard let record = fenceLedger.migrations[lifetime.fenceKey] else { return nil }
        var nextVisited = visited
        nextVisited.insert(lifetime)
        return recoveryURLToLoad(
            for: RecoveryLifetime(
                documentID: record.destinationDocumentID,
                epoch: record.destinationEpoch
            ),
            visited: nextVisited
        )
    }

    func recoveryURL(for id: String, epoch: String?) -> URL {
        let suffix = epoch.map { ".\($0)" } ?? ""
        return recoveryDirectory.appendingPathComponent("\(documentDigest(id))\(suffix).recovery.md")
    }

    func legacyRecoveryURL(for id: String) -> URL {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let legacy = String(id.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" })
        return recoveryDirectory.appendingPathComponent("\(legacy).recovery.md")
    }

    func retiredURL(for lifetime: RecoveryLifetime) -> URL {
        recoveryDirectory.appendingPathComponent(
            "\(documentDigest(lifetime.documentID)).\(lifetime.epoch).retired"
        )
    }

    /// Records the migration before deleting its source. The ledger write is
    /// atomic, so a fresh process can recover the destination if it starts
    /// after source removal but before source retirement is fenced.
    func stageMigration(
        from source: RecoveryLifetime,
        to destination: RecoveryLifetime
    ) -> RecoveryCleanupResult {
        let record = RecoveryMigrationRecord(
            destinationDocumentID: destination.documentID,
            destinationEpoch: destination.epoch
        )
        if fenceLedger.migrations[source.fenceKey] == record {
            return .alreadyAbsent
        }
        do {
            var candidate = fenceLedger
            candidate.migrations[source.fenceKey] = record
            try publishFenceLedger(candidate)
            return .removed
        } catch {
            return .failed(.markerWriteFailed(recoveryFenceURL, errorCode(error)))
        }
    }

    func finishMigration(
        _ source: RecoveryLifetime,
        destination: RecoveryLifetime
    ) -> RecoveryCleanupResult {
        guard let record = fenceLedger.migrations[source.fenceKey] else { return .alreadyAbsent }
        guard record == RecoveryMigrationRecord(
            destinationDocumentID: destination.documentID,
            destinationEpoch: destination.epoch
        ) else {
            return .failed(.verificationFailed(recoveryFenceURL))
        }
        do {
            var candidate = fenceLedger
            candidate.migrations.removeValue(forKey: source.fenceKey)
            try publishFenceLedger(candidate)
            return .removed
        } catch {
            return .failed(.markerWriteFailed(recoveryFenceURL, errorCode(error)))
        }
    }

    var recoveryFenceURL: URL {
        recoveryDirectory.appendingPathComponent("recovery-fences.json")
    }

    func isRetired(_ lifetime: RecoveryLifetime) -> Bool {
        if let generation = RecoveryLifetimeEpoch.generation(for: lifetime.epoch) {
            let documentKey = documentDigest(lifetime.documentID)
            let current = fenceLedger.currentByDocument[documentKey]
            let highest = max(
                fenceLedger.highestGenerationByDocument[documentKey, default: 0],
                fenceLedger.globalHighestGeneration
            )
            return current != lifetime.epoch && generation <= highest
        }
        return fenceLedger.retired.contains(lifetime.fenceKey)
            || retiredLifetimes.contains(lifetime)
            || FileManager.default.fileExists(atPath: retiredURL(for: lifetime).path)
    }

    func isRetiredURL(_ url: URL, documentID: String) -> Bool {
        let name = url.deletingPathExtension().deletingPathExtension().lastPathComponent
        let components = name.split(separator: ".", maxSplits: 1)
        guard components.count == 2 else { return false }
        return isRetired(RecoveryLifetime(documentID: documentID, epoch: String(components[1])))
    }

    /// Physical marker files are diagnostics and remain globally bounded. The
    /// ledger is a single persistent file containing the authoritative fences.
    func compactMarkers() {
        while markerOrder.count > Self.markerLimit {
            let oldest = markerOrder.removeFirst()
            retiredLifetimes.remove(oldest)
            _ = removeDiagnosticMarker(at: retiredURL(for: oldest))
        }
        compactPhysicalMarkersGlobally()
    }

    /// Legacy UUIDs did not carry an exact generation. Preserve their exact
    /// retirement entries while migrating old records; all new FileDocument
    /// epochs use the bounded per-document generation protocol above.
    func retainLegacyRetirement(
        of epoch: String,
        documentID: String,
        in ledger: inout RecoveryFenceLedger
    ) {
        guard RecoveryLifetimeEpoch.generation(for: epoch) == nil else { return }
        ledger.retired.insert(RecoveryLifetime(documentID: documentID, epoch: epoch).fenceKey)
    }

    func removeRecoveryFile(at url: URL, sourceRemoval: Bool = false) -> RecoveryCleanupResult {
        do {
            try hooks?.beforeRecoveryRemoval?(url)
            if sourceRemoval {
                try hooks?.beforeSourceRemoval?(url)
            }
            try FileManager.default.removeItem(at: url)
            guard !FileManager.default.fileExists(atPath: url.path) else {
                return .failed(.removalFailed(url, Int(EIO)))
            }
            if sourceRemoval {
                try hooks?.afterSourceRemoval?(url)
            }
            return .removed
        } catch {
            let nsError = error as NSError
            if nsError.code == NSFileNoSuchFileError {
                return .alreadyAbsent
            }
            return .failed(.removalFailed(url, errorCode(error)))
        }
    }

    func removeDiagnosticMarker(at url: URL) -> RecoveryCleanupResult {
        do {
            try FileManager.default.removeItem(at: url)
            return .removed
        } catch {
            let nsError = error as NSError
            if nsError.code == NSFileNoSuchFileError {
                return .alreadyAbsent
            }
            return .failed(.removalFailed(url, errorCode(error)))
        }
    }

    func loadFenceLedgerIfNeeded() throws {
        guard !hasLoadedFenceLedger else { return }
        var candidate = RecoveryFenceLedger()
        let hasPersistedLedger = FileManager.default.fileExists(atPath: recoveryFenceURL.path)
        if hasPersistedLedger {
            candidate = try JSONDecoder().decode(RecoveryFenceLedger.self, from: Data(contentsOf: recoveryFenceURL))
            migrateLegacyFenceLedger(&candidate)
        }
        // Repair the global floor before either publishing it in memory or
        // writing it back. Publishing first made a failed repair look durable
        // to this actor while a fresh process still loaded the stale floor.
        let repairedHighWater = max(
            candidate.globalHighestGeneration,
            candidate.highestGenerationByDocument.values.max() ?? 0
        )
        candidate.globalHighestGeneration = repairedHighWater
        if hasPersistedLedger {
            try persistFenceLedger(candidate)
        }
        fenceLedger = candidate
        RecoveryLifetimeEpoch.observe(highWater: candidate.globalHighestGeneration)
        // Publish this flag last. A failed decode or atomic write leaves the
        // actor retryable rather than permanently operating on partial state.
        hasLoadedFenceLedger = true
        compactPhysicalMarkersGlobally()
    }

    func publishFenceLedger(_ candidate: RecoveryFenceLedger) throws {
        try persistFenceLedger(candidate)
        fenceLedger = candidate
    }

    func persistFenceLedger(_ ledger: RecoveryFenceLedger) throws {
        try FileManager.default.createDirectory(at: recoveryDirectory, withIntermediateDirectories: true)
        try hooks?.beforeMarkerWrite?(recoveryFenceURL)
        let data = try JSONEncoder().encode(ledger)
        try data.write(to: recoveryFenceURL, options: .atomic)
    }

    /// Current owners cannot be compacted, but inactive managed ownership is
    /// safely represented by the global floor. Keep only a bounded diagnostic
    /// sample of per-document high-water entries so sequential distinct files
    /// do not grow the ledger without limit.
    private func compactInactiveManagedOwnership(in ledger: inout RecoveryFenceLedger) {
        let inactive = ledger.highestGenerationByDocument.keys
            .filter { ledger.currentByDocument[$0] == nil }
            .sorted()
        let permittedInactive = max(0, Self.markerLimit - ledger.currentByDocument.count)
        guard inactive.count > permittedInactive else { return }
        for documentKey in inactive.prefix(inactive.count - permittedInactive) {
            ledger.highestGenerationByDocument.removeValue(forKey: documentKey)
        }
    }
}
