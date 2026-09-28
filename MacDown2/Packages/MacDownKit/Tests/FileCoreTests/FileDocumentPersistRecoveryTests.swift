@testable import FileCore
import Foundation
import Testing

/// `persistRecovery()` must report whether this exact snapshot is durably
/// recorded, not merely whether this call performed the write (issue #168).
@Suite("Document recovery persistence")
struct FileDocumentPersistRecoveryTests {
    @Test func aSnapshotAnotherWriterAlreadyRecordedCountsAsSecured() async throws {
        let fixture = try RecoveryFixture()
        defer { fixture.remove() }
        let document = FileDocument(text: "", recoveryBuffer: fixture.buffer).updatingText("draft")
        #expect(try await fixture.buffer.saveCurrentLifetime(
            content: document.text,
            for: document.id,
            version: document.mutationGeneration,
            epoch: document.recoveryEpoch
        ))

        #expect(await document.persistRecovery())
        #expect(try await fixture.buffer.load(for: document.id, epoch: document.recoveryEpoch) == "draft")
    }

    @Test func differentTextRecordedAtTheSameVersionStillFails() async throws {
        let fixture = try RecoveryFixture()
        defer { fixture.remove() }
        let document = FileDocument(text: "", recoveryBuffer: fixture.buffer).updatingText("draft")
        #expect(try await fixture.buffer.saveCurrentLifetime(
            content: "other",
            for: document.id,
            version: document.mutationGeneration,
            epoch: document.recoveryEpoch
        ))

        #expect(await !document.persistRecovery())
    }

    @Test func aNewerRecordedVersionStillFailsEvenWithTheSameText() async throws {
        let fixture = try RecoveryFixture()
        defer { fixture.remove() }
        let document = FileDocument(text: "", recoveryBuffer: fixture.buffer).updatingText("draft")
        #expect(try await fixture.buffer.saveCurrentLifetime(
            content: document.text,
            for: document.id,
            version: document.mutationGeneration + 1,
            epoch: document.recoveryEpoch
        ))

        #expect(await !document.persistRecovery())
    }

    @Test func aRetiredLifetimeStillFails() async throws {
        let fixture = try RecoveryFixture()
        defer { fixture.remove() }
        let document = FileDocument(text: "", recoveryBuffer: fixture.buffer).updatingText("draft")
        #expect(await document.persistRecovery())
        #expect(await fixture.buffer.retireWithOutcome(for: document.id, epoch: document.recoveryEpoch).isAbsent)

        #expect(await !document.persistRecovery())
    }
}

private struct RecoveryFixture {
    let directory: URL
    let buffer: RecoveryBuffer

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        buffer = RecoveryBuffer(recoveryDirectory: directory)
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}
