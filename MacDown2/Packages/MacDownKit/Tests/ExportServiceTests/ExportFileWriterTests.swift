@testable import ExportService
import Foundation
import Testing

/// Slice 2: companion-directory ownership and primary-last durability.
struct ExportFileWriterTests {
    private func makePrepared(bodyHTML: String, resources: [ExportResource] = []) -> PreparedExportDocument {
        PreparedExportDocument(
            title: "Title",
            bodyHTML: bodyHTML,
            stylesheet: "body { color: var(--md-foreground); }",
            manifest: ExportManifest(resources: resources, referenceMap: [:]),
            diagnostics: [],
            sourceGeneration: 1,
            preservesRawHTML: true
        )
    }

    private func pngResource() -> ExportResource {
        let bytes = Data([0x89, 0x50, 0x4E, 0x47])
        return ExportResource(identity: ExportResourceIdentity(bytes: bytes, mimeType: "image/png"), bytes: bytes)
    }

    @Test func selfContainedWritesASingleFile() throws {
        let directory = try ExportTestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let resource = pngResource()
        let prepared = makePrepared(
            bodyHTML: "<p><img src=\"\(ExportHTMLWriter.assetsDirectoryName)/\(resource.identity.fileName)\"></p>",
            resources: [resource]
        )
        let target = ExportTarget.html(
            url: directory.appendingPathComponent("doc.html"),
            mode: .selfContained
        )

        let result = try ExportFileWriter.writeHTML(prepared, to: target)

        #expect(result.companionFiles.isEmpty)
        #expect(FileManager.default.fileExists(atPath: result.primaryFile.path))
        let html = try String(contentsOf: result.primaryFile, encoding: .utf8)
        #expect(html.contains("data:image/png;base64,"))
        #expect(!FileManager.default
            .fileExists(atPath: directory.appendingPathComponent(ExportHTMLWriter.assetsDirectoryName).path))
    }

    @Test func standaloneWritesAssetsWithMarker() throws {
        let directory = try ExportTestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let resource = pngResource()
        let prepared = makePrepared(
            bodyHTML: "<p><img src=\"\(ExportHTMLWriter.assetsDirectoryName)/\(resource.identity.fileName)\"></p>",
            resources: [resource]
        )
        let target = ExportTarget.html(
            url: directory.appendingPathComponent("doc.html"),
            mode: .standalone(style: .embedded)
        )

        let result = try ExportFileWriter.writeHTML(prepared, to: target)

        #expect(FileManager.default.fileExists(atPath: result.primaryFile.path))
        let assetsDir = directory.appendingPathComponent(ExportHTMLWriter.assetsDirectoryName)
        #expect(FileManager.default.fileExists(atPath: assetsDir.path))
        #expect(FileManager.default
            .fileExists(atPath: assetsDir.appendingPathComponent(resource.identity.fileName).path))

        let marker = assetsDir.appendingPathComponent(ExportFileWriter.markerFileName)
        #expect(FileManager.default.fileExists(atPath: marker.path))
        #expect(try String(contentsOf: marker, encoding: .utf8) == ExportFileWriter.markerContent)
    }

    @Test func linkedStandaloneWritesStylesheetCompanion() throws {
        let directory = try ExportTestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let prepared = makePrepared(bodyHTML: "<p>hi</p>")
        let target = ExportTarget.html(
            url: directory.appendingPathComponent("doc.html"),
            mode: .standalone(style: .linked)
        )

        let result = try ExportFileWriter.writeHTML(prepared, to: target)

        let cssURL = directory.appendingPathComponent(ExportHTMLWriter.linkedStylesheetName)
        #expect(FileManager.default.fileExists(atPath: cssURL.path))
        #expect(result.companionFiles.contains(cssURL))
        let html = try String(contentsOf: result.primaryFile, encoding: .utf8)
        #expect(html.contains("<link rel=\"stylesheet\" href=\"report.css\">"))
    }

    @Test func neverDeletesNonReservedUserFiles() throws {
        let directory = try ExportTestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let assetsDir = directory.appendingPathComponent(ExportHTMLWriter.assetsDirectoryName)
        try FileManager.default.createDirectory(at: assetsDir, withIntermediateDirectories: true)
        let userFile = assetsDir.appendingPathComponent("user-notes.txt")
        try Data("keep me".utf8).write(to: userFile)

        let resource = pngResource()
        let prepared = makePrepared(
            bodyHTML: "<p><img src=\"\(ExportHTMLWriter.assetsDirectoryName)/\(resource.identity.fileName)\"></p>",
            resources: [resource]
        )
        let target = ExportTarget.html(
            url: directory.appendingPathComponent("doc.html"),
            mode: .standalone(style: .embedded)
        )

        _ = try ExportFileWriter.writeHTML(prepared, to: target)

        #expect(FileManager.default.fileExists(atPath: userFile.path))
        #expect(try String(contentsOf: userFile, encoding: .utf8) == "keep me")
    }

    @Test func writeHTMLRejectsPDFTarget() throws {
        let directory = try ExportTestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let prepared = makePrepared(bodyHTML: "<p>hi</p>")

        #expect(throws: ExportError.self) {
            try ExportFileWriter.writeHTML(prepared, to: .pdf(url: directory.appendingPathComponent("out.pdf")))
        }
    }
}
