@testable import FileCore
import Foundation
import Testing

/// EPIC-22 §6.17 (Slice 8a): explicit-encoding decode, revision-only reads,
/// lossless write verification and the broadened metadata validation.
@Suite("ExplicitEncoding")
struct ExplicitEncodingTests {
    private func fixture(_ bytes: [UInt8]) throws -> (url: URL, cleanup: () -> Void) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("legacy.txt")
        try Data(bytes).write(to: url)
        return (url, { try? FileManager.default.removeItem(at: directory) })
    }

    private let store = FileStore()

    // MARK: - Decode

    @Test func latin1BytesFailAutomaticButDecodeExplicitly() throws {
        let (url, cleanup) = try fixture([0x63, 0x61, 0x66, 0xE9])
        defer { cleanup() }

        #expect(throws: FileStoreError.self) { try store.readSnapshot(from: url) }
        let snapshot = try store.readSnapshot(from: url, decoding: .explicit(.isoLatin1))
        #expect(snapshot.text == "café")
        #expect(snapshot.encodingMetadata == FileEncodingMetadata(encoding: .isoLatin1, bom: .none))
    }

    @Test func explicitDecodeIsLosslessOrFails() throws {
        // 0x81 is undefined in Windows-1252: decoding it would either drop or
        // invent a character, so saving the "same" text would change bytes.
        let (url, cleanup) = try fixture([0x61, 0x81, 0x62])
        defer { cleanup() }

        #expect {
            try store.readSnapshot(from: url, decoding: .explicit(.windowsCP1252))
        } throws: { error in
            guard case let FileStoreError.decodingFailed(diagnostics) = error else { return false }
            return diagnostics.count == 1
        }
    }

    @Test func shiftJISRoundTripsThroughExplicitDecode() throws {
        let text = "日本語のテキスト\n"
        let bytes = try #require(text.data(using: .shiftJIS))
        let (url, cleanup) = try fixture([UInt8](bytes))
        defer { cleanup() }

        let snapshot = try store.readSnapshot(from: url, decoding: .explicit(.shiftJIS))
        #expect(snapshot.text == text)
        #expect(snapshot.encoding == .shiftJIS)
    }

    @Test func explicitUTF8RejectsBytesThatAreNotUTF8() throws {
        let (url, cleanup) = try fixture([0x63, 0x61, 0x66, 0xE9])
        defer { cleanup() }
        #expect(throws: FileStoreError.self) { try store.readSnapshot(from: url, decoding: .explicit(.utf8)) }
    }

    @Test func explicitUTF16WithoutBOMDecodes() throws {
        let bytes = try [UInt8](#require("hi é".data(using: .utf16LittleEndian)))
        let (url, cleanup) = try fixture(bytes)
        defer { cleanup() }

        let snapshot = try store.readSnapshot(from: url, decoding: .explicit(.utf16LittleEndian))
        #expect(snapshot.text == "hi é")
        #expect(snapshot.bom == .none)
    }

    @Test func explicitUTF16WithMatchingBOMRecordsIt() throws {
        let bytes = try [0xFF, 0xFE] + [UInt8](#require("hi".data(using: .utf16LittleEndian)))
        let (url, cleanup) = try fixture(bytes)
        defer { cleanup() }

        let snapshot = try store.readSnapshot(from: url, decoding: .explicit(.utf16LittleEndian))
        #expect(snapshot.text == "hi")
        #expect(snapshot.bom == .utf16LittleEndian)
    }

    @Test func explicitUTF16RejectsTheOppositeEndiannessBOM() throws {
        let bytes = try [0xFF, 0xFE] + [UInt8](#require("hi".data(using: .utf16LittleEndian)))
        let (url, cleanup) = try fixture(bytes)
        defer { cleanup() }
        #expect(throws: FileStoreError.self) {
            try store.readSnapshot(from: url, decoding: .explicit(.utf16BigEndian))
        }
    }

    @Test func oddLengthUTF16IsRejectedNotTruncated() throws {
        let even = try [UInt8](#require("hi".data(using: .utf16LittleEndian)))
        let (url, cleanup) = try fixture([0xFF, 0xFE] + even + [0x41])
        defer { cleanup() }

        #expect(throws: FileStoreError.self) { try store.readSnapshot(from: url) }
        #expect(throws: FileStoreError.self) {
            try store.readSnapshot(from: url, decoding: .explicit(.utf16LittleEndian))
        }
    }

    // MARK: - Revision-only reads and legacy writes

    @Test func readRevisionWorksOnUndecodableFilesAndMatchesSnapshotRevision() throws {
        let (url, cleanup) = try fixture([0x63, 0xE9])
        defer { cleanup() }
        let revision = try store.readRevision(from: url)
        #expect(revision.fileSize == 2)
        let snapshot = try store.readSnapshot(from: url, decoding: .explicit(.isoLatin1))
        #expect(snapshot.revision == revision)
    }

    @Test func conditionalWriteOverALegacyEncodedFileSucceeds() throws {
        let (url, cleanup) = try fixture([0x63, 0x61, 0x66, 0xE9])
        defer { cleanup() }
        let baseline = try store.readRevision(from: url)

        let revision = try store.write("café!", to: url, encoding: .isoLatin1, expectedRevision: baseline)

        #expect(try Data(contentsOf: url) == Data([0x63, 0x61, 0x66, 0xE9, 0x21]))
        #expect(try revision == (store.readRevision(from: url)))
    }

    @Test func conditionalWriteStillRefusesAChangedLegacyFile() throws {
        let (url, cleanup) = try fixture([0x63, 0xE9])
        defer { cleanup() }
        let baseline = try store.readRevision(from: url)
        try Data([0x64, 0xE9]).write(to: url)

        #expect(throws: FileStoreError.self) {
            try store.write("ce", to: url, encoding: .isoLatin1, expectedRevision: baseline)
        }
        #expect(try Data(contentsOf: url) == Data([0x64, 0xE9]))
    }

    // MARK: - Representability

    @Test func unrepresentableTextFailsBeforeTouchingTheFile() throws {
        let (url, cleanup) = try fixture([0x63, 0xE9])
        defer { cleanup() }
        let baseline = try store.readRevision(from: url)

        #expect(!store.canRepresent("price €5", encoding: .isoLatin1))
        #expect(store.canRepresent("café", encoding: .isoLatin1))
        #expect(throws: FileStoreError.self) {
            try store.write("price €5", to: url, encoding: .isoLatin1, expectedRevision: baseline)
        }
        #expect(try Data(contentsOf: url) == Data([0x63, 0xE9]))
        #expect(try store.readRevision(from: url) == baseline)
    }

    @Test func aConverterThatSilentlyNormalisesIsRefused() throws {
        // Foundation composes a decomposed "é" (e + U+0301) into the single
        // Latin-1 byte, so the file would reopen as different scalars: the
        // user's text must never be rewritten behind their back (invariant #5).
        let (url, cleanup) = try fixture([0x63, 0xE9])
        defer { cleanup() }
        let baseline = try store.readRevision(from: url)
        let decomposed = "cafe\u{301}"

        #expect(!store.canRepresent(decomposed, encoding: .isoLatin1))
        #expect(store.canRepresent("caf\u{E9}", encoding: .isoLatin1))
        #expect(throws: FileStoreError.self) {
            try store.write(decomposed, to: url, encoding: .isoLatin1, expectedRevision: baseline)
        }
        #expect(try store.readRevision(from: url) == baseline)
    }

    // MARK: - Metadata validation

    @Test func legacyEncodingMetadataSurvivesSessionDecoding() throws {
        let original = FileEncodingMetadata(encoding: .windowsCP1252, bom: .none)
        let decoded = try JSONDecoder().decode(FileEncodingMetadata.self, from: JSONEncoder().encode(original))
        #expect(decoded == original)
    }

    @Test func inconsistentOrUnknownMetadataStillCollapsesToTheDefault() throws {
        let bomOnLegacy = FileEncodingMetadata(encoding: .isoLatin1, bom: .utf8)
        let unknown = FileEncodingMetadata(encodingRawValue: 987_654, bom: .none)
        for bad in [bomOnLegacy, unknown] {
            let decoded = try JSONDecoder().decode(FileEncodingMetadata.self, from: JSONEncoder().encode(bad))
            #expect(decoded == .utf8Default)
        }
    }

    @Test func decodingPolicyIsAutomaticOnlyWhenBytesAloneReproduceTheMetadata() {
        #expect(FileEncodingMetadata.utf8Default.decodingPolicy == .automatic)
        #expect(FileEncodingMetadata(encoding: .utf8, bom: .utf8).decodingPolicy == .automatic)
        #expect(FileEncodingMetadata(encoding: .utf16LittleEndian, bom: .utf16LittleEndian)
            .decodingPolicy == .automatic)
        #expect(FileEncodingMetadata(encoding: .utf16LittleEndian, bom: .none).decodingPolicy
            == .explicit(.utf16LittleEndian))
        #expect(FileEncodingMetadata(encoding: .isoLatin1, bom: .none).decodingPolicy == .explicit(.isoLatin1))
    }

    @Test func curatedEncodingsAreAllSupportedAndUnique() {
        let raw = FileEncodingCatalog.curated.map(\.rawValue)
        #expect(Set(raw).count == raw.count)
        #expect(raw.allSatisfy { FileEncodingCatalog.isSupported(rawValue: $0) })
        #expect(FileEncodingCatalog.all.count >= FileEncodingCatalog.curated.count)
    }

    // MARK: - Monitor

    @Test func explicitDecodingPolicyReachesEveryProbeAndIsBindingScoped() async throws {
        let firstURL = URL(fileURLWithPath: "/tmp/epic22/encoding-first.txt")
        let secondURL = URL(fileURLWithPath: "/tmp/epic22/encoding-second.txt")
        let prober = RecordingProber()
        let monitor = DocumentFileMonitor(
            debounce: .zero,
            watcher: MonitorWatcher(),
            prober: prober,
            sleeper: { _ in await Task.yield() }
        )

        try await monitor.bind(to: firstURL, priorFileObjectID: nil, decoding: .explicit(.isoLatin1)) { _ in }
        #expect(await prober.lastRequest?.decoding == .explicit(.isoLatin1))

        await monitor.updateBaseline(priorFileObjectID: nil, decoding: .explicit(.shiftJIS), expectedURL: firstURL)
        _ = await monitor.snapshotNow()
        #expect(await prober.lastRequest?.decoding == .explicit(.shiftJIS))

        try await monitor.bind(to: secondURL, priorFileObjectID: nil) { _ in }
        await monitor.updateBaseline(priorFileObjectID: nil, decoding: .explicit(.isoLatin1), expectedURL: firstURL)
        _ = await monitor.snapshotNow()
        #expect(await prober.lastRequest?.decoding == .automatic)
    }
}
