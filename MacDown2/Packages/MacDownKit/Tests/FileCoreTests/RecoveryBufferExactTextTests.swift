@testable import FileCore
import Foundation
import Testing

/// #183 F11 — a recovery round trip returns exactly the authored text, including
/// a leading U+FEFF that Foundation's UTF-8 read would otherwise treat as a BOM.
@Suite("RecoveryBuffer exact text (#183 F11)")
struct RecoveryBufferExactTextTests {
    private func roundTrip(_ text: String) async throws -> String? {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let buffer = RecoveryBuffer(recoveryDirectory: directory)
        let id = UUID().uuidString
        let epoch = UUID()
        try await buffer.save(content: text, for: id, version: 1, epoch: epoch)
        return try await buffer.load(for: id, epoch: epoch)
    }

    @Test(arguments: [
        "\u{FEFF}abc",
        "\u{FEFF}\u{FEFF}abc",
        "\u{FEFF}",
        "abc\u{FEFF}def",
        "plain text",
        "",
        "café \u{1F600}",
    ])
    func theRecoveredTextIsScalarForScalarTheAuthoredText(_ text: String) async throws {
        let recovered = try #require(try await roundTrip(text))
        #expect(Array(recovered.unicodeScalars) == Array(text.unicodeScalars))
    }

    @Test func aFileThatIsNotValidUTF8IsRejectedNotLossilyDecoded() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try Data([0x61, 0xFF, 0x62]).write(to: url)

        #expect(throws: (any Error).self) { _ = try RecoveryBuffer.readExactUTF8(at: url) }
    }

    @Test func aLeadingBOMInTheFileIsPreservedAsAScalarNotConsumed() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try Data([0xEF, 0xBB, 0xBF, 0x61]).write(to: url)

        let text = try RecoveryBuffer.readExactUTF8(at: url)

        #expect(try Array(text.unicodeScalars) == [#require(Unicode.Scalar(0xFEFF)), "a"])
    }
}
