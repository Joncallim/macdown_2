import ExportService
import Foundation
@testable import MacDown2
import Testing
import Themes

@Suite("Validated SVG PDF input")
struct ValidatedSVGHTMLPDFTests {
    @Test func pdfAdapterInputPreservesTheAcceptedHTMLBytes() async throws {
        let source = "```diagram\nnode\n```\n"
        let diagram = #"<svg id="root"><defs><linearGradient id="paint"/></defs>"#
            + #"<rect fill="url(#paint)" width="12" height="12"/></svg>"#
        let target = URL(fileURLWithPath: "/tmp/validated-svg-pdf-\(UUID().uuidString).pdf")
        let request = ExportRequest(
            text: source, sourceGeneration: 1, theme: BundledThemes.light,
            contributions: [
                ExportDerivedContribution(sourceRange: 0 ..< source.utf16.count,
                                          placement: .block, html: diagram, sourceGeneration: 1),
            ]
        )
        let result = try await ExportService.exportValidatedSVG(
            request, to: .pdf(url: target), lease: ExportLifetimeLease()
        ) { validated, url, _ in
            let html = try await PDFExportAdapter.validatedHTMLForWebKit(validated, to: url)
            #expect(Data(html.utf8) == validated.utf8)
            #expect(html.contains("script-src 'none'"))
            #expect(!html.contains("<!--MT117-SVG-"))
            do {
                _ = try await PDFExportAdapter.validatedHTMLForWebKit(
                    validated, to: url.deletingLastPathComponent().appendingPathComponent("other.pdf")
                )
                Issue.record("A PDF receipt was accepted for another destination")
            } catch is ExportError {
                // Correct: the receipt is bound to its original destination.
            }
        }
        #expect(result.primaryFile == target)
    }
}
