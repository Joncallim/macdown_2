@testable import FileCore
import Foundation
import Testing

/// Review pass 6: a zero-length or garbled `recovery-fences.json` (a crash or power loss while it was rewritten)
/// made `loadFenceLedgerIfNeeded` throw on every call, so every file open and every new document failed until the
/// user deleted the file by hand.
struct RecoveryBufferCorruptLedgerTests {
    private func directoryWithLedger(_ bytes: Data) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try bytes.write(to: directory.appendingPathComponent("recovery-fences.json"))
        return directory
    }

    @Test(arguments: [Data(), Data("not json".utf8), Data("{\"truncated\": ".utf8)])
    func aCorruptLedgerIsQuarantinedAndTheBufferKeepsWorking(_ bytes: Data) async throws {
        let directory = try directoryWithLedger(bytes)
        defer { try? FileManager.default.removeItem(at: directory) }
        let buffer = RecoveryBuffer(recoveryDirectory: directory)

        let epoch = try await buffer.mintRecoveryEpoch()
        let saved = try await buffer.saveCurrentLifetime(content: "draft", for: "doc", version: 1, epoch: epoch)

        #expect(saved)
        #expect(try await buffer.load(for: "doc", epoch: epoch) == "draft")
        let quarantined = directory.appendingPathComponent("recovery-fences.json.corrupt")
        #expect(try Data(contentsOf: quarantined) == bytes)
    }

    @Test func aValidLedgerIsLeftAlone() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = RecoveryBuffer(recoveryDirectory: directory)
        let epoch = try await first.mintRecoveryEpoch()
        _ = try await first.saveCurrentLifetime(content: "draft", for: "doc", version: 1, epoch: epoch)

        let second = RecoveryBuffer(recoveryDirectory: directory)
        _ = try await second.mintRecoveryEpoch()

        #expect(!FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("recovery-fences.json.corrupt").path
        ))
    }
}
