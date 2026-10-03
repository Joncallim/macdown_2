@testable import FileCore
import Foundation
import Testing

/// Review pass 1: long file names could never be saved (the staging name exceeded
/// NAME_MAX), and a read-only (0444) file was silently overwritten.
struct FileStoreSaveEdgeCasesTests {
    @Test func aFileWithAVeryLongNameCanBeSaved() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        // 243 bytes: legal on APFS, but the staging name used to add 42 more.
        let name = String(repeating: "a", count: 240) + ".md"
        let url = directory.appendingPathComponent(name)
        try "one".write(to: url, atomically: true, encoding: .utf8)

        let saved = try FileDocument(fileURL: url).load().edited(text: "two").save()

        #expect(saved.state == .clean)
        #expect(try String(contentsOf: url, encoding: .utf8) == "two")
    }

    @Test func companionNamesStayWithinTheComponentLimitEvenForMultibyteNames() {
        let url = URL(fileURLWithPath: "/tmp/" + String(repeating: "日本語", count: 40) + ".md")
        let name = FileStore.companionName(for: url, infix: "external-recovery")
        #expect(name.utf8.count <= 255)
        #expect(name.hasPrefix("."))
    }
}
