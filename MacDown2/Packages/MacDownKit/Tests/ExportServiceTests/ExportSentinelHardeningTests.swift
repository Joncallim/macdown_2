@testable import ExportService
import Foundation
import Testing

/// Review pass 9: (1) the deferred (table-cell) sentinel swap replaced EVERY match in the rendered HTML, including
/// inside attribute values, before the leak check ran; authored text written with an entity or backslash escape
/// decodes to the exact sentinel, so derived markup was pasted into a `title` attribute with no diagnostic. (2) The
/// sentinel-suffix search added one `_` per pass and rescanned the body: quadratic in a hostile `E12BLOCK____…` run.
struct ExportSentinelHardeningTests {
    private func prepare(_ markdown: String, replacing needle: String) async throws -> PreparedExportDocument {
        let found = (markdown as NSString).range(of: needle, options: .literal)
        precondition(found.location != NSNotFound)
        return try await ExportService.prepare(
            ExportRequest(
                text: markdown,
                sourceGeneration: 1,
                theme: ExportTestSupport.lightTheme(),
                contributions: [
                    ExportDerivedContribution(
                        sourceRange: found.location ..< found.location + found.length,
                        placement: .inline,
                        html: "<img alt=\"m\">",
                        sourceGeneration: 1
                    ),
                ]
            ),
            target: .html(url: URL(fileURLWithPath: "/tmp/sentinels.html"), mode: .standalone(style: .embedded))
        )
    }

    @Test(arguments: ["E12INLIN&#69;0Z", "E12INLINE\\_0Z"])
    func anAuthoredSentinelCopyInALinkTitleIsNotReplacedByDerivedMarkup(_ authored: String) async throws {
        let markdown = "| a |\n|---|\n| $x$ |\n\n[link](http://example.com \"\(authored)\")\n"

        let prepared = try await prepare(markdown, replacing: "$x$")

        #expect(!prepared.bodyHTML.contains("title=\"<img"))
        // The contribution is not placed (its sentinel could not be told from authored text): the cell keeps its
        // source and the user is told, instead of derived markup landing inside an attribute silently.
        #expect(prepared.bodyHTML.contains("<td>$x$</td>"))
        #expect(prepared.diagnostics.contains { $0.message.contains("exported as their source text") })
    }

    @Test func theTableCellContributionItselfIsStillPlaced() async throws {
        let prepared = try await prepare("| a |\n|---|\n| $x$ |\n", replacing: "$x$")

        #expect(prepared.bodyHTML.contains("<td><img alt=\"m\"></td>"))
    }

    @Test func aLongRunOfUnderscoresAfterASentinelBaseDoesNotMakeThePreparationQuadratic() async throws {
        let markdown = "E12BLOCK" + String(repeating: "_", count: 32000) + "\n\nhello $x$\n"
        let start = ContinuousClock.now

        let prepared = try await prepare(markdown, replacing: "$x$")

        #expect(ContinuousClock.now - start < .seconds(2))
        #expect(prepared.bodyHTML.contains("<img alt=\"m\">"))
        #expect(prepared.bodyHTML.contains("E12BLOCK"))
    }
}
