@testable import FileCore
import Foundation
import Testing
@testable import Workspace

/// EPIC-11 §3.2 — session restore persists encoding metadata needed to
/// interpret text (never raw bytes); legacy records use the documented
/// default.
@Suite("FileEncodingSessionRestore")
struct FileEncodingSessionRestoreTests {
    @Test func sessionRecordRoundTripPreservesEncoding() throws {
        let store = FileStore()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("doc.json")
        _ = try store.write("{\"a\":1}", to: url, bom: .utf8)

        let document = try FileDocument(fileURL: url, fileStore: store).load()
        let record = TabRecord(
            id: UUID(),
            fileURL: url,
            encoding: document.encoding
        )
        let data = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(TabRecord.self, from: data)

        #expect(decoded.encoding == document.encoding)
        #expect(decoded.encoding?.bom == .utf8)
    }

    @Test func legacySessionRecordWithoutEncodingDefaultsToUTF8() throws {
        let legacyJSON = """
        {"id":"\(UUID().uuidString)","fileURL":"/tmp/legacy.md","isPinned":false}
        """
        let record = try JSONDecoder().decode(
            TabRecord.self,
            from: Data(legacyJSON.utf8)
        )

        #expect(record.encoding == nil)
        #expect(record.encoding ?? .utf8Default == .utf8Default)
    }

    @Test func malformedEncodingRawValueDecodesToTheDefault() throws {
        // A corrupted/hand-edited session must not carry a garbage encoding
        // into restore (EPIC-11 §3.2: malformed metadata uses the documented
        // default).
        let corruptJSON = """
        {"id":"\(UUID().uuidString)","fileURL":"/tmp/doc.md","isPinned":false,
         "encoding":{"encodingRawValue":999999,"bom":"none"}}
        """
        let record = try JSONDecoder().decode(
            TabRecord.self,
            from: Data(corruptJSON.utf8)
        )

        #expect(record.encoding == .utf8Default)
    }

    @Test func inconsistentEncodingBOMPairDecodesToTheDefault() throws {
        // A mismatched pair (UTF-8 encoding with a UTF-16 BOM) would write
        // bytes under the wrong prefix; it must default instead.
        let mismatchedJSON = """
        {"id":"\(UUID().uuidString)","fileURL":"/tmp/doc.md","isPinned":false,
         "encoding":{"encodingRawValue":\(String.Encoding.utf8.rawValue),"bom":"utf16LittleEndian"}}
        """
        let record = try JSONDecoder().decode(
            TabRecord.self,
            from: Data(mismatchedJSON.utf8)
        )

        #expect(record.encoding == .utf8Default)
    }

    @Test func supportedEncodingsRoundTripThroughSessionJSON() throws {
        for metadata in [
            FileEncodingMetadata(encoding: .utf8, bom: .none),
            FileEncodingMetadata(encoding: .utf8, bom: .utf8),
            FileEncodingMetadata(encoding: .utf16LittleEndian, bom: .utf16LittleEndian),
            FileEncodingMetadata(encoding: .utf16BigEndian, bom: .utf16BigEndian),
        ] {
            let encoded = try JSONEncoder().encode(metadata)
            let decoded = try JSONDecoder().decode(FileEncodingMetadata.self, from: encoded)
            #expect(decoded == metadata)
        }
    }

    @MainActor
    @Test func restoreAppliesRecordEncodingToUntitledDocument() async throws {
        let recoveryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: recoveryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: recoveryDirectory) }
        let buffer = try RecoveryBuffer(recoveryDirectory: recoveryDirectory)

        let store = TabStore(recoveryBuffer: buffer)
        let documentID = UUID().uuidString
        let epoch = UUID()
        _ = try await buffer.saveCurrentLifetime(
            content: "{\"a\":1}",
            for: documentID,
            version: 1,
            epoch: epoch
        )

        let record = TabRecord(
            id: UUID(),
            untitledDocumentID: documentID,
            documentRecoveryEpoch: epoch,
            isPinned: false,
            encoding: FileEncodingMetadata(encoding: .utf16LittleEndian, bom: .utf16LittleEndian)
        )
        let tab = await store.restoreTab(from: record)

        #expect(tab != nil)
        #expect(tab?.document.encoding.bom == .utf16LittleEndian)
        #expect(tab?.document.text == "{\"a\":1}")
    }
}
