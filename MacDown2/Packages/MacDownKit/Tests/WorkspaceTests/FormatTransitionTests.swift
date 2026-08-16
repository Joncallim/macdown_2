@testable import FileCore
import Foundation
import Testing
@testable import Workspace

/// EPIC-11 Gate 2 — format transitions: Save As re-derives the format from
/// the destination extension (never silently inheriting the source format),
/// preserves encoding/BOM metadata across the transition, and routes the
/// resulting format to its own preview capability.
@Suite("FormatTransition")
struct FormatTransitionTests {
    @Test func saveAsToJSONTransitionsFormatAndCapability() throws {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let source = directory.appendingPathComponent("note.md")
        let destination = directory.appendingPathComponent("data.json")
        _ = try FileStore().write(#"{"a":1}"#, to: source)
        let document = try FileDocument(fileURL: source).load()
        #expect(document.format.id == "markdown")

        let saved = try document.saveAs(destination)
        #expect(saved.fileURL == destination)
        #expect(saved.format.id == "json")
        #expect(saved.format.previewCapability == .jsonOutline)
        #expect(saved.format.defaultPreviewMode == .outline)
        #expect(saved.format.supportedPreviewModes == [.outline])
        #expect(saved.format.highlightLanguageID == "json")
        #expect(try FileStore().read(from: destination).content == #"{"a":1}"#)
    }

    @Test func saveAsFromJSONToMarkdownTransitionsFormat() throws {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let source = directory.appendingPathComponent("data.json")
        let destination = directory.appendingPathComponent("note.md")
        _ = try FileStore().write(#"{"a":1}"#, to: source)
        let document = try FileDocument(fileURL: source).load()
        #expect(document.format.id == "json")

        let saved = try document.saveAs(destination)
        #expect(saved.format.id == "markdown")
        #expect(saved.format.previewCapability == .markdown)
        #expect(saved.format.defaultPreviewMode == .rendered)
        #expect(try FileStore().read(from: destination).content == #"{"a":1}"#)
    }

    @Test func saveAsToHTMLTransitionsToSourceAndRendered() throws {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let source = directory.appendingPathComponent("data.json")
        let destination = directory.appendingPathComponent("page.html")
        _ = try FileStore().write(#"{"a":1}"#, to: source)
        let document = try FileDocument(fileURL: source).load()

        let saved = try document.saveAs(destination)
        #expect(saved.format.id == "html")
        #expect(saved.format.previewCapability == .htmlSourceAndRendered)
        #expect(saved.format.supportedPreviewModes == [.source, .rendered])
        #expect(saved.format.highlightLanguageID == "html")
    }

    @Test func saveAsToUnknownExtensionFallsBackToPlainText() throws {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let source = directory.appendingPathComponent("data.json")
        let destination = directory.appendingPathComponent("data.unknownext")
        _ = try FileStore().write(#"{"a":1}"#, to: source)
        let document = try FileDocument(fileURL: source).load()

        let saved = try document.saveAs(destination)
        #expect(saved.format.id == "plaintext")
        #expect(saved.format.previewCapability == .none)
        #expect(saved.format.defaultPreviewMode == nil)
    }

    @Test func encodingIsPreservedThroughFormatTransitions() throws {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let source = directory.appendingPathComponent("data.json")
        let destination = directory.appendingPathComponent("note.md")
        _ = try FileStore().write(
            #"{"a":1}"#,
            to: source,
            encoding: .utf16LittleEndian,
            bom: .utf16LittleEndian
        )
        let document = try FileDocument(fileURL: source).load()
        #expect(document.encoding.bom == .utf16LittleEndian)
        #expect(document.encoding.encoding == .utf16LittleEndian)

        let saved = try document.saveAs(destination)
        #expect(saved.format.id == "markdown")
        // Save As preserves source encoding metadata unless overridden.
        #expect(saved.encoding.bom == .utf16LittleEndian)
        #expect(saved.encoding.encoding == .utf16LittleEndian)
        // The written bytes round-trip with the same metadata.
        let snapshot = try FileStore().readSnapshot(from: destination)
        #expect(snapshot.text == #"{"a":1}"#)
        #expect(snapshot.bom == .utf16LittleEndian)
        #expect(snapshot.encoding == .utf16LittleEndian)
    }

    @Test func untitledDocumentSaveAsAdoptsDestinationFormat() throws {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let destination = directory.appendingPathComponent("fresh.json")
        let document = FileDocument(text: #"{"a":1}"#)
        #expect(document.format.id == "markdown")

        let saved = try document.saveAs(destination)
        #expect(saved.format.id == "json")
        #expect(saved.text == #"{"a":1}"#)
    }

    @Test func explicitEncodingOverrideBeatsSourceMetadataOnTransition() throws {
        let directory = temporaryDirectory()
        defer { cleanup(directory) }
        let source = directory.appendingPathComponent("data.json")
        let destination = directory.appendingPathComponent("note.md")
        _ = try FileStore().write(
            #"{"a":1}"#,
            to: source,
            encoding: .utf16LittleEndian,
            bom: .utf16LittleEndian
        )
        let document = try FileDocument(fileURL: source).load()

        let saved = try document.saveAs(destination, encodingOverride: .utf8Default)
        #expect(saved.format.id == "markdown")
        #expect(saved.encoding == .utf8Default)
        let snapshot = try FileStore().readSnapshot(from: destination)
        #expect(snapshot.bom == .none)
        #expect(snapshot.encoding == .utf8)
    }
}
