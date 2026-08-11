import Foundation

public enum RecoveryCleanupResult: Sendable, Equatable {
    case removed
    case alreadyAbsent
    case failed(RecoveryBufferError)

    public var isAbsent: Bool {
        switch self {
        case .removed, .alreadyAbsent: true
        case .failed: false
        }
    }
}

public enum RecoveryMigrationOutcome: Sendable, Equatable {
    case migrated
    case rejected
    case sourceRetained(RecoveryCleanupResult)
    case failed(RecoveryBufferError)

    public var isComplete: Bool {
        if case .migrated = self {
            return true
        }
        return false
    }
}

/// A durable source-to-destination redirect awaiting session acknowledgement.
/// The source lifetime remains recoverable until this exact record is cleared.
public struct RecoveryMigration: Sendable, Equatable {
    public let sourceDocumentID: String
    public let sourceEpoch: String
    public let destinationDocumentID: String
    public let destinationEpoch: String
}

public enum RecoveryBufferError: Error, Sendable, Equatable {
    case markerWriteFailed(URL, Int)
    case removalFailed(URL, Int)
    case writeFailed(URL, Int)
    case verificationFailed(URL)
}

struct RecoveryBufferHooks: Sendable {
    var beforeSourceRemoval: (@Sendable (URL) throws -> Void)?
    var beforeRecoveryRemoval: (@Sendable (URL) throws -> Void)?
    var beforeMarkerWrite: (@Sendable (URL) throws -> Void)?
    var afterSourceRemoval: (@Sendable (URL) throws -> Void)?

    init(
        beforeSourceRemoval: (@Sendable (URL) throws -> Void)? = nil,
        beforeRecoveryRemoval: (@Sendable (URL) throws -> Void)? = nil,
        beforeMarkerWrite: (@Sendable (URL) throws -> Void)? = nil
    ) {
        self.beforeSourceRemoval = beforeSourceRemoval
        self.beforeRecoveryRemoval = beforeRecoveryRemoval
        self.beforeMarkerWrite = beforeMarkerWrite
        afterSourceRemoval = nil
    }

    init(
        beforeSourceRemoval: (@Sendable (URL) throws -> Void)? = nil,
        beforeRecoveryRemoval: (@Sendable (URL) throws -> Void)? = nil,
        beforeMarkerWrite: (@Sendable (URL) throws -> Void)? = nil,
        afterSourceRemoval: @escaping @Sendable (URL) throws -> Void
    ) {
        self.beforeSourceRemoval = beforeSourceRemoval
        self.beforeRecoveryRemoval = beforeRecoveryRemoval
        self.beforeMarkerWrite = beforeMarkerWrite
        self.afterSourceRemoval = afterSourceRemoval
    }
}

struct RecoveryLifetime: Hashable {
    let documentID: String
    let epoch: String

    var fenceKey: String {
        "\(documentID.utf8.count):\(documentID)|\(epoch)"
    }
}

struct RecoveryMutation: Equatable {
    enum Kind: Equatable { case persist, remove }
    let version: UInt
    let kind: Kind
}

struct RecoveryFenceLedger: Codable {
    var retired: Set<String> = []
    var currentByDocument: [String: String] = [:]
    var highestGenerationByDocument: [String: UInt64] = [:]
    /// A global floor permits safe compaction of inactive per-document
    /// high-water entries: every managed epoch minted after reload is greater
    /// than this value, while a delayed old epoch is never admitted again.
    var globalHighestGeneration: UInt64 = 0
    var knownLifetimes: Set<String> = []
    var consumedLegacy: [String: ConsumedLegacyRecord] = [:]
    var migrations: [String: RecoveryMigrationRecord] = [:]

    private enum CodingKeys: String, CodingKey {
        case retired, currentByDocument, highestGenerationByDocument, globalHighestGeneration,
             knownLifetimes, consumedLegacy, migrations
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        retired = try container.decodeIfPresent(Set<String>.self, forKey: .retired) ?? []
        currentByDocument = try container.decodeIfPresent([String: String].self, forKey: .currentByDocument) ?? [:]
        highestGenerationByDocument = try container.decodeIfPresent(
            [String: UInt64].self, forKey: .highestGenerationByDocument
        ) ?? [:]
        globalHighestGeneration = try container.decodeIfPresent(UInt64.self, forKey: .globalHighestGeneration) ?? 0
        knownLifetimes = try container.decodeIfPresent(Set<String>.self, forKey: .knownLifetimes) ?? []
        consumedLegacy = try container
            .decodeIfPresent([String: ConsumedLegacyRecord].self, forKey: .consumedLegacy) ?? [:]
        migrations = try container.decodeIfPresent([String: RecoveryMigrationRecord].self, forKey: .migrations) ?? [:]
    }
}

struct RecoveryMigrationRecord: Codable, Equatable {
    let destinationDocumentID: String
    let destinationEpoch: String
}

/// UUIDv8-shaped recovery epochs whose leading 48 bits are a monotonic wall
/// generation. The low bytes remain random while recovery persists one exact
/// high-water mark per document.
enum RecoveryLifetimeEpoch {
    static let maximumGeneration: UInt64 = 0xFFFF_FFFF_FFFF

    private final class State: @unchecked Sendable {
        let lock = NSLock()
        var lastGeneration: UInt64 = 0
    }

    private static let state = State()

    static func observe(highWater: UInt64) {
        state.lock.lock()
        state.lastGeneration = max(state.lastGeneration, min(highWater, maximumGeneration - 1))
        state.lock.unlock()
    }

    static func make() -> UUID {
        state.lock.lock()
        defer { state.lock.unlock() }
        let wall = UInt64(max(0, Date().timeIntervalSince1970 * 1000))
        let generation = min(maximumGeneration, max(wall, state.lastGeneration &+ 1))
        state.lastGeneration = generation
        var bytes = Array(repeating: UInt8.zero, count: 16)
        for offset in 0 ..< 6 {
            bytes[offset] = UInt8((generation >> UInt64((5 - offset) * 8)) & 0xFF)
        }
        let random = UUID().uuid
        bytes[6...] = [
            random.0,
            random.1,
            random.2,
            random.3,
            random.4,
            random.5,
            random.6,
            random.7,
            random.8,
            random.9,
        ]
        bytes[6] = (bytes[6] & 0x0F) | 0x80
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    static func generation(for epoch: String) -> UInt64? {
        guard let uuid = UUID(uuidString: epoch) else { return nil }
        let bytes = withUnsafeBytes(of: uuid.uuid, Array.init)
        guard bytes[6] >> 4 == 8 else { return nil }
        return bytes[0 ..< 6].reduce(UInt64.zero) { ($0 << 8) | UInt64($1) }
    }
}

struct ConsumedLegacyRecord: Codable {
    let fileName: String
    let digest: String
    let isUnambiguous: Bool
}
