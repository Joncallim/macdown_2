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

    @Test func displayMathInATableCellAHeadingAndEmphasisStaysInPlace() async throws {
        let table = try await prepare(
            "| a | b |\n|---|---|\n| $$x$$ | 2 |\n", replacing: "$$x$$", with: "<img alt=\"m\">"
        )
        #expect(table.bodyHTML.contains("<td><img alt=\"m\"></td>"))
        #expect(table.bodyHTML.contains("<td>2</td>"))

        let heading = try await prepare("# Title $$E$$ end\n", replacing: "$$E$$", with: "<img alt=\"m\">")
        #expect(heading.bodyHTML.contains("<h1>Title <img alt=\"m\"> end</h1>"))

        let emphasis = try await prepare("*see $$x$$ here*\n", replacing: "$$x$$", with: "<img alt=\"m\">")
        #expect(emphasis.bodyHTML.contains("<em>see <img alt=\"m\"> here</em>"))
    }

    @Test func aFenceOnTheListMarkerLineStaysInItsListAsSourceWithAWarning() async throws {
        for (markdown, fence) in [
            ("- ```mermaid\n  graph TD\n  ```\n- next\n", "- ```mermaid\n  graph TD\n  ```"),
            ("1. ```mermaid\n   graph TD\n   ```\n2. next\n", "1. ```mermaid\n   graph TD\n   ```"),
        ] {
            let prepared = try await prepare(markdown, replacing: fence, with: "<svg>diagram</svg>")

            #expect(!prepared.bodyHTML.contains("<svg>diagram</svg>"))
            #expect(prepared.bodyHTML.contains("next"))
            #expect(prepared.bodyHTML.components(separatedBy: "<li>").count == 3, "list was split: \(markdown)")
            #expect(prepared.diagnostics.contains { $0.message.contains("list item or block quote") })
        }
    }

    /// `cmark_node_replace` refuses a custom inline inside a GFM table cell; the old code then freed the node it
    /// had failed to unlink, so inline math in a table cell exported as an empty cell.
    @Test func inlineMathInATableCellIsNotLost() async throws {
        let markdown = "| a | b |\n|---|---|\n| $x$ and $y$ | 2 |\n"
        let contributions = ["$x$", "$y$"].enumerated().map { index, needle -> ExportDerivedContribution in
            let found = (markdown as NSString).range(of: needle)
            return ExportDerivedContribution(
                sourceRange: found.location ..< (found.location + found.length),
                placement: .inline,
                html: "<img alt=\"m\(index)\">",
                sourceGeneration: 1
            )
        }
        let prepared = try await ExportService.prepare(
            ExportRequest(
                text: markdown,
                sourceGeneration: 1,
                theme: ExportTestSupport.lightTheme(),
                contributions: contributions
            ),
            target: .html(url: URL(fileURLWithPath: "/tmp/cells.html"), mode: .standalone(style: .embedded))
        )

        #expect(prepared.bodyHTML.contains("<td><img alt=\"m0\"> and <img alt=\"m1\"></td>"))
        #expect(prepared.bodyHTML.contains("<td>2</td>"))
        #expect(!prepared.bodyHTML.contains("E12INLINE"))
    }

    /// Inline contributions the literal-context scanner cannot know about (a reference-definition title, a link
    /// destination with nested parentheses) used to reach the export as sentinel text such as `E12INLINE0Z`.
    @Test func aSentinelThatCannotBeSubstitutedIsNeverExportedAndTheSourceStaysInstead() async throws {
        let markdown = "[a]: /url \"Price $5 - $10\"\n\nsee [a] and [b](/u/(1)$x$ \"t\")\n"
        let contributions = ["$5 - $", "$x$"].enumerated().map { index, needle -> ExportDerivedContribution in
            let found = (markdown as NSString).range(of: needle)
            return ExportDerivedContribution(
                sourceRange: found.location ..< (found.location + found.length),
                placement: .inline,
                html: "<img alt=\"m\(index)\">",
                sourceGeneration: 1
            )
        }

        let prepared = try await ExportService.prepare(
            ExportRequest(
                text: markdown,
                sourceGeneration: 1,
                theme: ExportTestSupport.lightTheme(),
                contributions: contributions
            ),
            target: .html(url: URL(fileURLWithPath: "/tmp/leak.html"), mode: .standalone(style: .embedded))
        )

        #expect(!prepared.bodyHTML.contains("E12INLINE"))
        #expect(!prepared.bodyHTML.contains("E12BLOCK"))
        #expect(prepared.bodyHTML.contains("Price $5 - $10"))
        #expect(prepared.diagnostics.contains { $0.message.contains("exported as their source text") })
    }

    @Test func aFullyPlacedExportReportsNoLeakWarning() async throws {
        let prepared = try await prepare("see $$x$$ here\n", replacing: "$$x$$", with: "<img alt=\"m\">")

        #expect(!prepared.diagnostics.contains { $0.message.contains("exported as their source text") })
    }
}
