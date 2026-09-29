@testable import FileCore
import Foundation
import Testing
@testable import Workspace

/// EPIC-22 §6.17 (Slice 8b): "Save with Encoding" changes the file's bytes
/// and the document's encoding metadata together, or neither.
@MainActor
@Suite("WorkspaceModel save with encoding")
struct WorkspaceModelSaveWithEncodingTests {
    private let latin1 = FileEncodingMetadata(encoding: .isoLatin1, bom: .none)

    private func model(url: URL, text: String, edited: String) -> WorkspaceModel {
        let tabStore = TabStore(sessionStore: FakeSessionStore())
        tabStore.newTab(document: FileDocument(fileURL: url, text: text).updatingText(edited))
        return WorkspaceModel(tabStore: tabStore, stateStore: FakeStateStore())
    }

    @Test func writesTheChosenEncodingAndAdoptsItAfterSuccess() async throws {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let url = directory.appendingPathComponent("note.txt")
        try "café".write(to: url, atomically: true, encoding: .utf8)
        let model = model(url: url, text: "café", edited: "café!")

        let result = await model.saveWithoutDestinationPrompt(encoding: latin1)

        #expect(result == .handled)
        #expect(try Data(contentsOf: url) == Data([0x63, 0x61, 0x66, 0xE9, 0x21]))
        #expect(model.activeDocument?.encoding == latin1)
        #expect(model.activeDocument?.state == .clean)
        #expect(model.lastError == nil)
    }

    @Test func aByteOrderMarkVariantIsWritten() async throws {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let url = directory.appendingPathComponent("bom.txt")
        try "hi".write(to: url, atomically: true, encoding: .utf8)
        let model = model(url: url, text: "hi", edited: "hi")
        let withBOM = FileEncodingMetadata(encoding: .utf8, bom: .utf8)

        _ = await model.saveWithoutDestinationPrompt(encoding: withBOM)

        #expect(try Data(contentsOf: url) == Data([0xEF, 0xBB, 0xBF, 0x68, 0x69]))
        #expect(model.activeDocument?.encoding == withBOM)
    }

    @Test func unrepresentableTextChangesNeitherTheFileNorTheDocument() async throws {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let url = directory.appendingPathComponent("emoji.txt")
        try "plain".write(to: url, atomically: true, encoding: .utf8)
        let model = model(url: url, text: "plain", edited: "plain 😀")

        _ = await model.saveWithoutDestinationPrompt(encoding: latin1)

        #expect(try String(contentsOf: url, encoding: .utf8) == "plain")
        #expect(model.activeDocument?.encoding == FileEncodingMetadata(encoding: .utf8, bom: .none))
        #expect(model.activeDocument?.state == .dirty)
        guard case let .textNotRepresentable(name) = model.lastError else {
            Issue.record("expected .textNotRepresentable, got \(String(describing: model.lastError))")
            return
        }
        #expect(name == latin1.displayName)
    }

    @Test func aDocumentWithoutABackingFileReportsARequiredDestination() async {
        let model = WorkspaceModel(stateStore: FakeStateStore())
        model.newDocument()
        model.tabStore.updateActiveDocument { $0.updatingText("hello") }

        let result = await model.saveWithoutDestinationPrompt(encoding: latin1)

        #expect(result == .requiresDestination)
        #expect(model.activeDocument?.encoding == FileEncodingMetadata(encoding: .utf8, bom: .none))
    }

    @Test func aCleanDocumentStillRewritesAfterAMetadataOnlyChange() async throws {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let url = directory.appendingPathComponent("touched.txt")
        try "café".write(to: url, atomically: true, encoding: .utf8)
        let loaded = try FileDocument(fileURL: url, text: "").load()
        let tabStore = TabStore(sessionStore: FakeSessionStore())
        tabStore.newTab(document: loaded)
        let model = WorkspaceModel(tabStore: tabStore, stateStore: FakeStateStore())
        // Same bytes, new file object: a backup/sync tool touching the file.
        try FileManager.default.removeItem(at: url)
        try "café".write(to: url, atomically: true, encoding: .utf8)

        _ = await model.saveWithoutDestinationPrompt(encoding: latin1)

        #expect(try Data(contentsOf: url) == Data([0x63, 0x61, 0x66, 0xE9]))
        #expect(model.activeDocument?.encoding == latin1)
        #expect(model.activeDocument?.state == .clean)
    }

    @Test func aLaterEditAdoptsTheSavedEncodingWithoutLosingTheEdit() {
        let url = URL(fileURLWithPath: "/tmp/epic22/adopt.txt")
        let base = FileDocument(fileURL: url, text: "a")
        let saved = FileDocument(fileURL: url, text: "a", encoding: latin1)
        let merged = base.updatingText("ab").adoptingSavedBaseline(from: saved)

        #expect(merged.encoding == latin1)
        #expect(merged.text == "ab")
        #expect(merged.state == .dirty)
    }

    @Test func documentSavingOverrideLeavesTheReceiverAndFileUntouchedOnFailure() throws {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let url = directory.appendingPathComponent("keep.txt")
        try "kept".write(to: url, atomically: true, encoding: .utf8)
        let document = FileDocument(fileURL: url, text: "kept").updatingText("kept 😀")

        #expect(throws: FileStoreError.self) {
            try document.saving(expectedRevision: nil, encodingOverride: latin1)
        }
        #expect(document.encoding == FileEncodingMetadata(encoding: .utf8, bom: .none))
        #expect(try String(contentsOf: url, encoding: .utf8) == "kept")
    }
}
