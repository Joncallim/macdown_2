import ExportService
import Foundation
import Testing

/// A block-placed contribution used to be spliced out as a blank-line-delimited paragraph, which pulled it
/// out of its list item or block quote and split the list/quote around it.
struct DerivedContentContainerTests {
    private func prepare(
        _ markdown: String,
        replacing needle: String,
        with html: String
    ) async throws -> PreparedExportDocument {
        let found = (markdown as NSString).range(of: needle)
        precondition(found.location != NSNotFound)
        let contribution = ExportDerivedContribution(
            sourceRange: found.location ..< (found.location + found.length),
            placement: .block,
            html: html,
            sourceGeneration: 1
        )
        return try await ExportService.prepare(
            ExportRequest(
                text: markdown,
                sourceGeneration: 1,
                theme: ExportTestSupport.lightTheme(),
                contributions: [contribution]
            ),
            target: .html(url: URL(fileURLWithPath: "/tmp/containers.html"), mode: .standalone(style: .embedded))
        )
    }

    @Test func displayMathInAListItemStaysInItsItemAndTheListIsNotSplit() async throws {
        let prepared = try await prepare(
            "- energy $$E=mc^2$$ is famous\n- second\n",
            replacing: "$$E=mc^2$$",
            with: "<img alt=\"math\">"
        )

        #expect(prepared.bodyHTML.components(separatedBy: "<ul>").count == 2)
        #expect(prepared.bodyHTML.contains("<li>energy <img alt=\"math\"> is famous</li>"))
    }

    @Test func displayMathInABlockQuoteStaysInTheQuote() async throws {
        let prepared = try await prepare("> see $$E$$ here\n", replacing: "$$E$$", with: "<img alt=\"math\">")

        #expect(prepared.bodyHTML.contains("<blockquote>"))
        let quoteEnd = try #require(prepared.bodyHTML.range(of: "</blockquote>"))
        let image = try #require(prepared.bodyHTML.range(of: "<img alt=\"math\">"))
        #expect(image.upperBound <= quoteEnd.lowerBound)
    }

    @Test func aDiagramFenceInsideAQuoteStaysAsItsSourceWithAWarning() async throws {
        let markdown = "> ```mermaid\n> graph TD\n> A-->B\n> ```\n"
        let prepared = try await prepare(
            markdown,
            replacing: "> ```mermaid\n> graph TD\n> A-->B\n> ```",
            with: "<svg>diagram</svg>"
        )

        #expect(!prepared.bodyHTML.contains("<svg>diagram</svg>"))
        #expect(prepared.bodyHTML.contains("graph TD"))
        #expect(prepared.diagnostics.contains { $0.message.contains("list item or block quote") })
    }

    @Test func aTopLevelBlockContributionIsStillPlacedAsABlock() async throws {
        let prepared = try await prepare(
            "intro\n\n$$E$$\n\noutro\n",
            replacing: "$$E$$",
            with: "<img alt=\"math\">"
        )

        #expect(prepared.bodyHTML.contains("<img alt=\"math\">"))
        #expect(!prepared.bodyHTML.contains("math\"> </p>"))
        #expect(prepared.bodyHTML.contains("<p>intro</p>"))
        #expect(prepared.bodyHTML.contains("<p>outro</p>"))
    }
}
