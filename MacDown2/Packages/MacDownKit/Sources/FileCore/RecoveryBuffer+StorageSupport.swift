import CryptoKit
import Foundation

extension RecoveryBuffer {
    func compactPhysicalMarkersGlobally() {
        let markers = ((try? FileManager.default.contentsOfDirectory(
            at: recoveryDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? [])
            .filter { $0.pathExtension == "retired" }
            .sorted { modificationDate(of: $0) < modificationDate(of: $1) }
        guard markers.count > Self.markerLimit else { return }
        for marker in markers.prefix(markers.count - Self.markerLimit) {
            _ = removeDiagnosticMarker(at: marker)
        }
    }

    func diagnosticMarkerKey(for fenceKey: String) -> String? {
        guard let separator = fenceKey.lastIndex(of: "|") else { return nil }
        let lifetime = String(fenceKey[..<separator])
        guard let colon = lifetime.firstIndex(of: ":") else { return nil }
        let identifier = String(lifetime[lifetime.index(after: colon)...])
        let epoch = String(fenceKey[fenceKey.index(after: separator)...])
        return "\(documentDigest(identifier)).\(epoch)"
    }

    func lifetime(forFenceKey fenceKey: String) -> RecoveryLifetime? {
        guard let separator = fenceKey.lastIndex(of: "|"),
              let colon = fenceKey.firstIndex(of: ":"),
              let length = Int(fenceKey[..<colon])
        else { return nil }
        let identifier = String(fenceKey[fenceKey.index(after: colon) ..< separator])
        guard identifier.utf8.count == length else { return nil }
        let epoch = String(fenceKey[fenceKey.index(after: separator)...])
        guard !epoch.isEmpty else { return nil }
        return RecoveryLifetime(documentID: identifier, epoch: epoch)
    }

    func migrateLegacyFenceLedger(_ ledger: inout RecoveryFenceLedger) {
        for key in ledger.knownLifetimes {
            guard let lifetime = lifetime(forFenceKey: key),
                  RecoveryLifetimeEpoch.generation(for: lifetime.epoch) == nil
            else { continue }
            ledger.retired.insert(key)
        }
        ledger.knownLifetimes.removeAll()
    }

    func recordConsumedLegacyIfNeeded(documentID: String, url: URL, content: String) throws {
        guard url == legacyRecoveryURL(for: documentID) else { return }
        let record = ConsumedLegacyRecord(
            fileName: url.lastPathComponent,
            digest: digest(content),
            isUnambiguous: isUnambiguousLegacyIdentifier(documentID)
        )
        var candidate = fenceLedger
        candidate.consumedLegacy[documentID] = record
        try publishFenceLedger(candidate)
    }

    func promoteConsumedLegacyIfSafe(for documentID: String, epoch: String?) throws {
        guard epoch != nil, let consumed = fenceLedger.consumedLegacy[documentID] else { return }
        let legacy = recoveryDirectory.appendingPathComponent(consumed.fileName)
        guard consumed.isUnambiguous,
              let content = try? String(contentsOf: legacy, encoding: .utf8),
              digest(content) == consumed.digest
        else { return }
        let result = removeRecoveryFile(at: legacy, sourceRemoval: true)
        guard result.isAbsent else {
            if case let .failed(error) = result {
                throw error
            }
            return
        }
        var candidate = fenceLedger
        candidate.consumedLegacy.removeValue(forKey: documentID)
        try publishFenceLedger(candidate)
    }

    func isUnambiguousLegacyIdentifier(_ id: String) -> Bool {
        legacyRecoveryURL(for: id).deletingPathExtension().deletingPathExtension().lastPathComponent == id
    }

    func modificationDate(of url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }

    func documentDigest(_ id: String) -> String {
        SHA256.hash(data: Data(id.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    func digest(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    func errorCode(_ error: Error) -> Int {
        (error as NSError).code
    }

    func epochIdentifier(_ epoch: UUID?) -> String? {
        epoch?.uuidString.lowercased()
    }
}
