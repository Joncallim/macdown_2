@testable import FileCore
import Foundation
import Testing

/// The text round-trip fidelity corpus required by the E15 feature-complete
/// gate (`RELEASE_HARDENING.md`, issue #16): "Verify text fidelity:
/// encodings, relevant BOM cases, LF/CRLF, Unicode/emoji/CJK, final-newline
/// state, large files, no-op save, Save As and external atomic rewrites."
///
/// Encoding/BOM round trips and external-rewrite handling already have
/// thorough, dedicated coverage in `FileEncodingTests.swift` — this file
/// covers the remaining items that had no dedicated file-round-trip test:
/// line-ending preservation, final-newline state, Unicode/emoji/CJK content,
/// large files, and no-op re-save producing byte-identical output. All
/// exercise the real `FileStore.write`/`readSnapshot` pair against real
/// temporary files on disk — no in-memory string-transform stand-in.
@Suite("TextRoundTripFidelity")
struct TextRoundTripFidelityTests {
    private func temporaryFile(name: String = "fixture.md") throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(name)
    }

    // MARK: - Line endings

    @Test func crlfLineEndingsAreNeverSilentlyNormalizedToLF() throws {
        let store = FileStore()
        let url = try temporaryFile()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let original = "# Title\r\n\r\nA paragraph.\r\nSecond line.\r\n"
        try store.write(original, to: url)
        let snapshot = try store.readSnapshot(from: url)

        #expect(snapshot.text == original)
        #expect(snapshot.text.contains("\r\n"))
    }

    @Test func mixedLineEndingsAreNeverRewritten() throws {
        // A real-world file authored/edited across platforms can genuinely
        // mix \n and \r\n. The durable-text invariant (D10, MIGRATION_PLAN.md)
        // is that authored text is never gratuitously rewritten — this must
        // survive exactly as authored, mixture included, not be "cleaned up"
        // into one consistent style.
        let store = FileStore()
        let url = try temporaryFile()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let original = "line one\r\nline two\nline three\r\n"
        try store.write(original, to: url)
        let snapshot = try store.readSnapshot(from: url)

        #expect(snapshot.text == original)
    }

    @Test func bareCarriageReturnLineEndingsAreNeverSilentlyNormalized() throws {
        // Classic Mac OS (\r-only) line endings are rare today but a
        // pasted/legacy fragment could still contain one; it must round-trip
        // exactly like any other byte sequence, not be reinterpreted.
        let store = FileStore()
        let url = try temporaryFile()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let original = "line one\rline two\r"
        try store.write(original, to: url)
        let snapshot = try store.readSnapshot(from: url)

        #expect(snapshot.text == original)
    }

    // MARK: - Final-newline state

    @Test func aFileWithNoTrailingNewlineRoundTripsWithoutGainingOne() throws {
        let store = FileStore()
        let url = try temporaryFile()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let original = "# No trailing newline"
        try store.write(original, to: url)
        let snapshot = try store.readSnapshot(from: url)

        #expect(snapshot.text == original)
        #expect(!snapshot.text.hasSuffix("\n"))
    }

    @Test func aFileWithATrailingNewlineRoundTripsWithoutLosingIt() throws {
        let store = FileStore()
        let url = try temporaryFile()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let original = "# Has trailing newline\n"
        try store.write(original, to: url)
        let snapshot = try store.readSnapshot(from: url)

        #expect(snapshot.text == original)
        #expect(snapshot.text.hasSuffix("\n"))
    }

    @Test func aFileWithMultipleTrailingNewlinesRoundTripsWithoutCollapsingThem() throws {
        let store = FileStore()
        let url = try temporaryFile()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let original = "# Trailing blank lines\n\n\n"
        try store.write(original, to: url)
        let snapshot = try store.readSnapshot(from: url)

        #expect(snapshot.text == original)
    }

    // MARK: - Unicode / emoji / CJK

    @Test func emojiIncludingMultiScalarSequencesRoundTripExactly() throws {
        let store = FileStore()
        let url = try temporaryFile()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        // A simple emoji, a ZWJ family sequence, a skin-tone modifier, and a
        // flag (regional indicator pair) — each stresses UTF-8 multi-byte and
        // Unicode grapheme-cluster boundaries differently.
        let original = "Reactions: 👍 👨‍👩‍👧‍👦 👋🏽 🇯🇵\n"
        try store.write(original, to: url)
        let snapshot = try store.readSnapshot(from: url)

        #expect(snapshot.text == original)
        #expect(snapshot.text.unicodeScalars.count == original.unicodeScalars.count)
    }

    @Test func cjkTextRoundTripsExactly() throws {
        let store = FileStore()
        let url = try temporaryFile()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let original = "# 日本語のタイトル\n\n中文段落内容。\n\n한국어 문단입니다.\n"
        try store.write(original, to: url)
        let snapshot = try store.readSnapshot(from: url)

        #expect(snapshot.text == original)
    }

    @Test func combiningDiacriticsAndRightToLeftTextRoundTripExactly() throws {
        let store = FileStore()
        let url = try temporaryFile()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        // "é" as a combining sequence (e + U+0301), not the precomposed
        // form, plus real Arabic (right-to-left) text.
        let original = "Cafe\u{0301} \n\nمرحبا بالعالم\n"
        try store.write(original, to: url)
        let snapshot = try store.readSnapshot(from: url)

        #expect(snapshot.text == original)
    }

    // MARK: - Large files

    @Test func aLargeDocumentRoundTripsWithoutTruncationOrCorruption() throws {
        let store = FileStore()
        let url = try temporaryFile()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        var original = ""
        for index in 0 ..< 50000 {
            original += "Line \(index): representative body text for a large document.\n"
        }
        #expect(original.utf8.count > 2_500_000) // several MB, not a toy size

        try store.write(original, to: url)
        let snapshot = try store.readSnapshot(from: url)

        #expect(snapshot.text == original)
        #expect(snapshot.text.hasPrefix("Line 0:"))
        #expect(snapshot.text.contains("Line 49999:"))
    }

    // MARK: - No-op save

    @Test func reWritingUnchangedContentProducesByteIdenticalOutput() throws {
        let store = FileStore()
        let url = try temporaryFile()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let original = "# Stable\r\n\r\nSome CJK: 中文, some emoji: 🎉, no trailing newline"
        try store.write(original, to: url, bom: .utf8)
        let firstBytes = try Data(contentsOf: url)

        let snapshot = try store.readSnapshot(from: url)
        // A no-op save re-writes the exact same decoded text with the exact
        // same encoding/BOM metadata the file already carries.
        try store.write(snapshot.text, to: url, encoding: snapshot.encoding, bom: snapshot.bom)
        let secondBytes = try Data(contentsOf: url)

        #expect(firstBytes == secondBytes)
    }

    // MARK: - Save As

    @Test func saveAsToANewLocationPreservesContentByteForByte() throws {
        let store = FileStore()
        let originalURL = try temporaryFile(name: "original.md")
        let saveAsURL = originalURL.deletingLastPathComponent().appendingPathComponent("copy.md")
        defer { try? FileManager.default.removeItem(at: originalURL.deletingLastPathComponent()) }

        let original = "# Save As fidelity\r\n\r\n中文 emoji 🎉 CRLF\r\nno trailing newline"
        try store.write(original, to: originalURL, bom: .utf8)
        let snapshot = try store.readSnapshot(from: originalURL)

        try store.write(snapshot.text, to: saveAsURL, encoding: snapshot.encoding, bom: snapshot.bom)
        let saveAsSnapshot = try store.readSnapshot(from: saveAsURL)

        #expect(saveAsSnapshot.text == original)
        #expect(saveAsSnapshot.bom == snapshot.bom)
        #expect(saveAsSnapshot.encoding == snapshot.encoding)
    }
}
