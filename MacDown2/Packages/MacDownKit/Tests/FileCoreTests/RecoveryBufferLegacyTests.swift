@testable import FileCore
import Foundation
import Testing

@Test func legacyDeletionLedgerSurvivesAFailedPromotionAndRetries() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let legacy = directory.appendingPathComponent("plain.recovery.md")
    try "legacy draft".write(to: legacy, atomically: true, encoding: .utf8)
    let failure = LegacyRemovalFailure()
    let recovery = RecoveryBuffer(
        recoveryDirectory: directory,
        beforeSourceRemoval: { _ in try failure.failOnce() }
    )
    let epoch = UUID()

    #expect(try await recovery.load(for: "plain") == "legacy draft")
    await #expect(throws: Error.self) {
        try await recovery.save(content: "new draft", for: "plain", version: 1, epoch: epoch)
    }
    #expect(FileManager.default.fileExists(atPath: legacy.path))

    try await recovery.save(content: "new draft", for: "plain", version: 2, epoch: epoch)
    #expect(!FileManager.default.fileExists(atPath: legacy.path))
    #expect(try await recovery.load(for: "plain", epoch: epoch) == "new draft")
}

@Test func durableFenceRejectsAnOldLifetimeAfterRestartAndMarkerCompaction() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let oldEpoch = UUID()
    let first = RecoveryBuffer(recoveryDirectory: directory)
    try await first.save(content: "old", for: "document", version: 1, epoch: oldEpoch)
    #expect(await (first.retireWithOutcome(for: "document", epoch: oldEpoch)).isAbsent)

    for index in 0 ..< 300 {
        let id = "document-\(index)"
        let epoch = UUID()
        try await first.save(content: id, for: id, version: 1, epoch: epoch)
        #expect(await (first.retireWithOutcome(for: id, epoch: epoch)).isAbsent)
    }

    let markerCount = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        .filter { $0.pathExtension == "retired" }
        .count
    #expect(markerCount <= 256)

    let restarted = RecoveryBuffer(recoveryDirectory: directory)
    #expect(try await !(restarted.saveCurrentLifetime(
        content: "late",
        for: "document",
        version: 2,
        epoch: oldEpoch
    )))
    #expect(try await restarted.load(for: "document", epoch: oldEpoch) == nil)
}

@Test func highBitManagedEpochRetiresWithoutSignedFenceArithmetic() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let highBitEpoch = UUID(uuid: (
        0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x80, 0x00,
        0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01
    ))
    #expect(RecoveryLifetimeEpoch.generation(for: highBitEpoch.uuidString.lowercased()) == 0xFFFF_FFFF_FFFF)

    let recovery = RecoveryBuffer(recoveryDirectory: directory)
    #expect(try await recovery.saveCurrentLifetime(
        content: "high-bit",
        for: "high-bit-document",
        version: 1,
        epoch: highBitEpoch
    ))
    #expect(await recovery.retireWithOutcome(for: "high-bit-document", epoch: highBitEpoch).isAbsent)
    #expect(try await !(recovery.saveCurrentLifetime(
        content: "stale",
        for: "high-bit-document",
        version: 2,
        epoch: highBitEpoch
    )))
}

@Test func managedGenerationLedgerRotatesExactlyWithoutFalseRejectingNewEpochs() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let documentID = "rotation-document"
    let recovery = RecoveryBuffer(recoveryDirectory: directory)
    let first = RecoveryLifetimeEpoch.make()
    var latest = first

    for index in 0 ..< 400 {
        let epoch = index == 0 ? first : RecoveryLifetimeEpoch.make()
        latest = epoch
        #expect(try await recovery.saveCurrentLifetime(
            content: "value-\(index)",
            for: documentID,
            version: UInt(index + 1),
            epoch: epoch
        ))
        #expect(await recovery.retireWithOutcome(for: documentID, epoch: epoch).isAbsent)
    }

    let freshEpoch = RecoveryLifetimeEpoch.make()
    #expect(try await recovery.saveCurrentLifetime(
        content: "fresh",
        for: documentID,
        version: 500,
        epoch: freshEpoch
    ))
    #expect(try await recovery.load(for: documentID, epoch: freshEpoch) == "fresh")
    #expect(try await !(recovery.saveCurrentLifetime(
        content: "late",
        for: documentID,
        version: 501,
        epoch: first
    )))
    #expect(await recovery.durableOwnershipCount == 1)

    let restarted = RecoveryBuffer(recoveryDirectory: directory)
    #expect(try await !(restarted.saveCurrentLifetime(
        content: "late-restarted",
        for: documentID,
        version: 502,
        epoch: latest
    )))
    let afterRestart = RecoveryLifetimeEpoch.make()
    #expect(try await restarted.saveCurrentLifetime(
        content: "new-after-restart",
        for: documentID,
        version: 503,
        epoch: afterRestart
    ))
}

@Test func failedFencePersistenceLeavesTheSameActorRetryableAndRejectsStaleWritesAfterRestart() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let failure = LegacyRemovalFailure()
    let recovery = RecoveryBuffer(
        recoveryDirectory: directory,
        hooks: RecoveryBufferHooks(beforeMarkerWrite: { _ in try failure.failOnce() })
    )
    let epoch = UUID()

    await #expect(throws: Error.self) {
        try await recovery.saveCurrentLifetime(
            content: "first",
            for: "retryable-fence",
            version: 1,
            epoch: epoch
        )
    }
    #expect(try await recovery.saveCurrentLifetime(
        content: "retry",
        for: "retryable-fence",
        version: 1,
        epoch: epoch
    ))
    #expect(await recovery.retireWithOutcome(for: "retryable-fence", epoch: epoch).isAbsent)

    let restarted = RecoveryBuffer(recoveryDirectory: directory)
    #expect(try await !(restarted.saveCurrentLifetime(
        content: "late",
        for: "retryable-fence",
        version: 2,
        epoch: epoch
    )))
}

@Test func failedFenceLoadLeavesTheSameActorRetryable() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let fenceURL = directory.appendingPathComponent("recovery-fences.json")
    try Data("not json".utf8).write(to: fenceURL)
    let recovery = RecoveryBuffer(recoveryDirectory: directory)

    await #expect(throws: Error.self) {
        try await recovery.save(content: "first", for: "retryable-load", version: 1, epoch: UUID())
    }
    try FileManager.default.removeItem(at: fenceURL)
    try await recovery.save(content: "retry", for: "retryable-load", version: 1, epoch: UUID())
}

@Test func durableHighWaterMintsAForwardEpochWhenTheClockWouldRegress() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    // A persisted generation just ahead of the wall clock models a clock
    // regression without exhausting the 48-bit encoding for other tests that
    // correctly share the production minting state.
    let highWater = UInt64(Date().timeIntervalSince1970 * 1000) + 60000
    let durableEpoch = managedEpoch(generation: highWater)
    let first = RecoveryBuffer(recoveryDirectory: directory)
    #expect(try await first.saveCurrentLifetime(
        content: "durable",
        for: "clock-regression",
        version: 1,
        epoch: durableEpoch
    ))

    let restarted = RecoveryBuffer(recoveryDirectory: directory)
    // `FileDocument.create` must load the persisted high-water before it
    // mints. No prior `load` call is permitted to prime this fresh buffer.
    let document = try await FileDocument.create(
        text: "new",
        recoveryBuffer: restarted,
        documentID: "clock-regression"
    )
    let minted = document.recoveryEpoch
    let mintedGeneration = try #require(RecoveryLifetimeEpoch.generation(for: minted.uuidString.lowercased()))
    #expect(mintedGeneration > highWater)
    #expect(try await restarted.saveCurrentLifetime(
        content: "new",
        for: "clock-regression",
        version: 2,
        epoch: minted
    ))
}

@Test func legacyFenceRepairPersistsTheMaximumPerDocumentHighWater() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let documentKey = String(repeating: "a", count: 64)
    var ledger = RecoveryFenceLedger()
    ledger.highestGenerationByDocument[documentKey] = 0x1234
    let fenceURL = directory.appendingPathComponent("recovery-fences.json")
    try JSONEncoder().encode(ledger).write(to: fenceURL, options: .atomic)

    let recovery = RecoveryBuffer(recoveryDirectory: directory)
    _ = try await recovery.mintRecoveryEpoch()
    let repaired = try JSONDecoder().decode(RecoveryFenceLedger.self, from: Data(contentsOf: fenceURL))
    #expect(repaired.globalHighestGeneration == 0x1234)
}

private func managedEpoch(generation: UInt64) -> UUID {
    let bytes: [UInt8] = [
        UInt8((generation >> 40) & 0xFF), UInt8((generation >> 32) & 0xFF),
        UInt8((generation >> 24) & 0xFF), UInt8((generation >> 16) & 0xFF),
        UInt8((generation >> 8) & 0xFF), UInt8(generation & 0xFF),
        0x80, 0x00, 0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01,
    ]
    return UUID(uuid: (
        bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
        bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
    ))
}

private final class LegacyRemovalFailure: @unchecked Sendable {
    private let lock = NSLock()
    private var remaining = 1

    func failOnce() throws {
        lock.lock()
        defer { lock.unlock() }
        guard remaining > 0 else { return }
        remaining -= 1
        throw POSIXError(.EACCES)
    }
}
