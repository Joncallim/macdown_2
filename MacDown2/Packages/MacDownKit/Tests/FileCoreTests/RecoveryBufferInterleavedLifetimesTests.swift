@testable import FileCore
import Foundation
import Testing

/// Two live documents are minted lifetimes in one order but first persist in the
/// other: neither may be refused recovery because of the other's generation.
struct RecoveryBufferInterleavedLifetimesTests {
    private func makeBuffer() -> (RecoveryBuffer, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return (RecoveryBuffer(recoveryDirectory: directory), directory)
    }

    @Test func anOlderMintedLifetimeOfAnotherDocumentCanStillPersist() async throws {
        let (buffer, directory) = makeBuffer()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = try await buffer.mintRecoveryEpoch()
        let second = try await buffer.mintRecoveryEpoch()

        // The newer-minted document persists first...
        #expect(try await buffer.saveCurrentLifetime(content: "u", for: "untitled-2", version: 1, epoch: second))
        // ...the older-minted, different document must still be secured.
        #expect(try await buffer.saveCurrentLifetime(content: "f", for: "file:///f.md", version: 1, epoch: first))
        #expect(try await buffer.load(for: "file:///f.md", epoch: first) == "f")
        #expect(try await buffer.load(for: "untitled-2", epoch: second) == "u")
    }

    @Test func aRetiredOlderLifetimeIsStillRefused() async throws {
        let (buffer, directory) = makeBuffer()
        defer { try? FileManager.default.removeItem(at: directory) }
        let older = try await buffer.mintRecoveryEpoch()
        let newer = try await buffer.mintRecoveryEpoch()
        #expect(try await buffer.saveCurrentLifetime(content: "n", for: "doc-b", version: 1, epoch: newer))

        _ = await buffer.retireWithOutcome(for: "doc-a", epoch: older)

        #expect(try await !buffer.saveCurrentLifetime(content: "late", for: "doc-a", version: 1, epoch: older))
    }

    @Test func aRestoredLifetimeMustBeAdoptedToOutliveANewerDocumentsFirstPersist() async throws {
        let (buffer, directory) = makeBuffer()
        defer { try? FileManager.default.removeItem(at: directory) }
        // Epochs as read back from a saved session: not minted by this process.
        let restored = RecoveryLifetimeEpoch.make()
        let newer = try await buffer.mintRecoveryEpoch()
        #expect(try await buffer.saveCurrentLifetime(content: "n", for: "doc-b", version: 1, epoch: newer))

        await buffer.adoptRecoveryEpoch(restored)

        #expect(try await buffer.saveCurrentLifetime(content: "r", for: "doc-a", version: 1, epoch: restored))
    }
}
