@testable import ExportService
import Foundation
import Testing
import Themes

/// Review pass 1: a self-contained export silently lost every local image when
/// the output file name needed percent/entity escaping (a space, non-ASCII,
/// `&`, `'`) — the common default save name "My Notes.html".
struct ExportAssetNameEscapingTests {
    private let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3, 4])

    private func exportedHTML(outputName: String) async throws -> String {
        let dir = try ExportTestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try ExportTestSupport.writeFixture(named: "pic.png", in: dir, bytes: png)
        let out = dir.appendingPathComponent(outputName)
        let request = ExportRequest(
            text: "![a](pic.png)\n", sourceGeneration: 1, theme: BundledThemes.light,
            documentURL: dir.appendingPathComponent("doc.md")
        )
        _ = try await ExportService.exportHTML(request, to: .html(url: out, mode: .selfContained))
        return try String(contentsOf: out, encoding: .utf8)
    }

    @Test(arguments: ["plain.html", "My Notes.html", "café.html", "a&b.html", "it's.html", "100%.html"])
    func localImagesAreEmbeddedWhateverTheOutputNameNeedsEscaping(name: String) async throws {
        let html = try await exportedHTML(outputName: name)
        #expect(html.contains("data:image/png;base64,"), "image not embedded for \(name)")
        #expect(!html.contains(".assets/"), "a companion reference was left behind for \(name)")
    }

    @Test func escapedDestinationMatchesTheRenderersForm() {
        #expect(ExportHTMLWriter.cmarkEscapedDestination("My Notes.assets") == "My%20Notes.assets")
        #expect(ExportHTMLWriter.cmarkEscapedDestination("café.assets") == "caf%C3%A9.assets")
        #expect(ExportHTMLWriter.cmarkEscapedDestination("a&b.assets") == "a&amp;b.assets")
    }
}
