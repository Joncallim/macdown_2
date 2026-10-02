import FileCore
import Foundation
import Testing
@testable import Workspace

/// Non-UTF-8 files: deterministic detection opens BOM-less UTF-16; anything
/// ambiguous fails (never replacing bytes) and opens only on an explicit choice,
/// after which the chosen encoding survives saves.
@MainActor
struct OpenWithEncodingTests {
    private func makeStore() -> (TabStore, URL) {
        let directory = temporaryDirectory()
        let recovery = RecoveryBuffer(recoveryDirectory: directory.appendingPathComponent("Recovery"))
        return (TabStore(sessionStore: FakeSessionStore(), recoveryBuffer: recovery), directory)
    }

    @Test func aBomLessUTF16FileOpensAutomaticallyAndSavesInTheSameEncoding() async throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("wide.txt")
        try #require("Hello wide world\n".data(using: .utf16LittleEndian)).write(to: url)

        let tab = try #require(try? await store.openFileInTab(url).get())

        #expect(tab.document.text == "Hello wide world\n")
        #expect(tab.document.encoding == FileEncodingMetadata(encoding: .utf16LittleEndian, bom: .none))
        let saved = try tab.document.edited(text: "Hello wide world\nmore\n").save()
        #expect(try Data(contentsOf: url) == #require("Hello wide world\nmore\n".data(using: .utf16LittleEndian)))
        #expect(saved.encoding == tab.document.encoding)
    }

    @Test func aLatin1FileFailsToOpenAutomaticallyWithoutReplacingAnyByte() async throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("legacy.txt")
        let bytes = Data([0x63, 0x61, 0x66, 0xE9, 0x0A])
        try bytes.write(to: url)

        let result = await store.openFileInTab(url)

        guard case let .failure(error) = result else {
            Issue.record("expected the ambiguous file to fail to open")
            return
        }
        #expect(error.isUndecodableText)
        #expect(store.tabs.isEmpty)
        #expect(try Data(contentsOf: url) == bytes)
    }

    @Test func anExplicitEncodingOpensTheSameFileAndItSurvivesSaves() async throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("legacy.txt")
        try Data([0x63, 0x61, 0x66, 0xE9, 0x0A]).write(to: url)
        let latin1 = FileEncodingMetadata(encoding: .isoLatin1, bom: .none)

        let tab = try #require(try? await store.openFileInTab(url, encoding: latin1).get())

        #expect(tab.document.text == "café\n")
        #expect(tab.document.encoding == latin1)
        _ = try tab.document.edited(text: "café au lait\n").save()
        #expect(try Data(contentsOf: url) == #require("café au lait\n".data(using: .isoLatin1)))
    }

    @Test func aWrongExplicitEncodingFailsRatherThanMangling() async throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("japanese.txt")
        // Shift-JIS bytes with an odd length: not decodable as UTF-16.
        let bytes = Data([0x93, 0xFA, 0x96, 0x7B, 0x8C])
        try bytes.write(to: url)

        let result = await store.openFileInTab(
            url,
            encoding: FileEncodingMetadata(encoding: .utf16LittleEndian, bom: .none)
        )

        if case .success = result {
            Issue.record("expected the mismatched encoding to be refused")
        }
        #expect(try Data(contentsOf: url) == bytes)
    }
}
