@testable import FileCore
import Foundation
import Testing

/// Review follow-ups for EPIC-22 §6.17 (Slice 8a): silent-normalisation and
/// policy-plumbing regressions found by the independent diff review.
@Suite("ExplicitEncodingFidelity")
struct ExplicitEncodingFidelityTests {
    private let store = FileStore()

    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    @Test func leadingByteOrderMarkScalarIsRefusedWithoutABOM() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("feff.txt")
        let text = "\u{FEFF}A"

        for encoding in [String.Encoding.utf8, .utf16LittleEndian, .utf16BigEndian] {
            #expect(!store.canRepresent(text, encoding: encoding, bom: .none))
            #expect(throws: FileStoreError.self) { try store.write(text, to: url, encoding: encoding, bom: .none) }
            #expect(!FileManager.default.fileExists(atPath: url.path))
        }
    }

    @Test func leadingByteOrderMarkScalarSurvivesWhenABOMIsWritten() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("feff-bom.txt")
        let text = "\u{FEFF}A"

        #expect(store.canRepresent(text, encoding: .utf8, bom: .utf8))
        try store.write(text, to: url, encoding: .utf8, bom: .utf8)
        let snapshot = try store.readSnapshot(from: url)
        #expect(snapshot.text == text)
        #expect(snapshot.encodingMetadata == FileEncodingMetadata(encoding: .utf8, bom: .utf8))
    }

    @Test func documentLoadReadsWithItsOwnEncodingPolicy() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("restored.txt")
        // Plain ASCII is valid UTF-8, so an automatic re-read would silently
        // replace the document's explicit Latin-1 choice with UTF-8.
        try Data("plain ascii".utf8).write(to: url)

        let document = FileDocument(
            fileURL: url,
            encoding: FileEncodingMetadata(encoding: .isoLatin1, bom: .none)
        )
        let loaded = try document.load()
        #expect(loaded.encoding == FileEncodingMetadata(encoding: .isoLatin1, bom: .none))

        try Data([0x63, 0x61, 0x66, 0xE9]).write(to: url)
        #expect(try document.load().text == "café")
    }

    @Test func monitorBaselineUpdateAppliesIDAndPolicyTogether() async throws {
        let url = URL(fileURLWithPath: "/tmp/epic22/baseline.txt")
        let prober = RecordingProber()
        let monitor = DocumentFileMonitor(
            debounce: .zero,
            watcher: MonitorWatcher(),
            prober: prober,
            sleeper: { _ in await Task.yield() }
        )
        try await monitor.bind(to: url, priorFileObjectID: nil) { _ in }

        await monitor.updateBaseline(priorFileObjectID: nil, decoding: .explicit(.shiftJIS), expectedURL: url)
        _ = await monitor.snapshotNow()
        #expect(await prober.lastRequest?.decoding == .explicit(.shiftJIS))

        await monitor.updateBaseline(
            priorFileObjectID: nil,
            decoding: .explicit(.isoLatin1),
            expectedURL: URL(fileURLWithPath: "/tmp/epic22/other.txt")
        )
        _ = await monitor.snapshotNow()
        #expect(await prober.lastRequest?.decoding == .explicit(.shiftJIS))
    }
}
