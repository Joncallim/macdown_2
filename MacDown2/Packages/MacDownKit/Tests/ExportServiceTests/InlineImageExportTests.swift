import ExportService
import Foundation
import Testing

/// A pasted inline image (`![x](data:image/png;base64,…)`) was blanked in every export format.
struct InlineImageExportTests {
    @Test func anInlineRasterImageSurvivesExportWithoutWarnings() async throws {
        let uri = "data:image/png;base64,iVBORw0KGgo="
        let prepared = try await ExportService.prepare(
            ExportRequest(text: "![pasted](\(uri))\n", sourceGeneration: 1, theme: ExportTestSupport.lightTheme()),
            target: .html(url: URL(fileURLWithPath: "/tmp/inline-image.html"), mode: .standalone(style: .embedded))
        )

        #expect(prepared.bodyHTML.contains("src=\"\(uri)\""))
        #expect(prepared.diagnostics.isEmpty)
    }
}
