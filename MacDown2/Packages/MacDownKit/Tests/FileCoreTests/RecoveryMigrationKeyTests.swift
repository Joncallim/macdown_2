@testable import FileCore
import Foundation
import Testing

/// Review pass 8: `pendingMigrations` split its key at the FIRST `|`, but a document path may contain one (the epoch
/// never does), so the length check failed and the pending migration was silently dropped and never acknowledged.
struct RecoveryMigrationKeyTests {
    @Test func aSourcePathContainingAPipeIsStillReportedAsPending() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let buffer = RecoveryBuffer(recoveryDirectory: directory)
        let source = RecoveryLifetime(documentID: "/tmp/a|b.md", epoch: UUID().uuidString.lowercased())
        let destination = RecoveryLifetime(documentID: "/tmp/c.md", epoch: UUID().uuidString.lowercased())
        try await buffer.loadFenceLedgerIfNeeded()
        _ = await buffer.stageMigration(from: source, to: destination)

        let pending = try await buffer.pendingMigrations()

        #expect(pending.map(\.sourceDocumentID) == ["/tmp/a|b.md"])
        #expect(pending.map(\.destinationDocumentID) == ["/tmp/c.md"])
    }
}
