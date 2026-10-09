import FileCore
import Foundation
@testable import MacDown2
import Testing

/// Tenth review (persistence cross-check #2): the watcher bind retry reinstalled the document captured when the first
/// watch failed, so a Save with Encoding that succeeded in the meantime was undone: the monitor probed the saved
/// Latin-1 file with the old automatic UTF-8 policy, reported it undecodable and the document turned dirty/unavailable.
@MainActor
struct BindRetryDocumentTests {
    @Test func theRetryUsesTheLiveDocumentsCurrentEncodingPolicy() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("doc.txt")
        try "caf\u{E9}".write(to: url, atomically: true, encoding: .utf8)
        let captured = try FileDocument(fileURL: url).load()
        let latin1 = FileEncodingMetadata(encoding: .isoLatin1, bom: .none)
        let live = try captured.saving(expectedRevision: captured.lastKnownRevision, encodingOverride: latin1)

        let chosen = ExternalFileController.bindRetryDocument(
            live: live,
            captured: captured,
            url: url.standardizedFileURL
        )

        #expect(chosen?.encoding == latin1)
        #expect(chosen?.lastKnownRevision == live.lastKnownRevision)
    }

    @Test func aDifferentFileOrNoDocumentCancelsTheRetry() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("a.txt")
        let other = directory.appendingPathComponent("b.txt")
        try "x".write(to: url, atomically: true, encoding: .utf8)
        try "y".write(to: other, atomically: true, encoding: .utf8)
        let captured = try FileDocument(fileURL: url).load()
        let different = try FileDocument(fileURL: other).load()

        #expect(ExternalFileController.bindRetryDocument(live: nil, captured: captured, url: url) == nil)
        #expect(ExternalFileController.bindRetryDocument(live: different, captured: captured, url: url) == nil)
    }
}
