@testable import ExportService
import Foundation
import MarkdownEngine
import Testing

@Suite("Spliced export body coordinates")
struct SplicedBodySourceMapTests {
    @Test func acceptedBlockAndInlineSplicesMapLaterHeadings() throws {
        let body = "# First\r\n\r\n```diagram\r\nnode\r\n```\r\n\r\n$𝛼$ tail\r\n# Last\r\n"
        let block = try #require(range(of: "```diagram\r\nnode\r\n```", in: body))
        let inline = try #require(range(of: "$𝛼$", in: body))
        let last = try #require(range(of: "# Last", in: body))
        let result = DerivedContentComposer.compose(
            bodyText: body,
            bodyStartOffset: 0,
            sourceUTF16Length: body.utf16.count,
            contributions: [
                ExportDerivedContribution(
                    sourceRange: block,
                    placement: .block,
                    html: "<svg>diagram</svg>",
                    sourceGeneration: 1
                ),
                ExportDerivedContribution(
                    sourceRange: inline,
                    placement: .inline,
                    html: "<span>alpha</span>",
                    sourceGeneration: 1
                ),
            ],
            sourceGeneration: 1,
            recordCoordinates: true
        )

        let coordinates = try #require(result.coordinates)
        let renderedLast = try #require(range(of: "# Last", in: result.splicedBody))
        #expect(result.customNodes.count == 2)
        #expect(SourceMap(text: body).line(atUTF16Offset: last.lowerBound)
            != SourceMap(text: result.splicedBody).line(atUTF16Offset: renderedLast.lowerBound))
        #expect(coordinates.renderedOffset(forOriginalOffset: 0) == 0)
        #expect(coordinates.renderedOffset(forOriginalOffset: last.lowerBound) == renderedLast.lowerBound)
        #expect(coordinates.renderedOffset(forOriginalOffset: block.lowerBound) == nil)
        #expect(coordinates.renderedOffset(forOriginalOffset: inline.lowerBound) == nil)
        #expect(coordinates.renderedOffset(forOriginalOffset: block.upperBound) != nil)
        #expect(coordinates.renderedOffset(forOriginalOffset: body.utf16.count)
            == result.splicedBody.utf16.count)
        #expect(coordinates.renderedOffset(forOriginalOffset: body.utf16.count + 1) == nil)
    }

    @Test func rejectedContributionDoesNotShiftCoordinates() throws {
        let body = "before $x$\n# Heading\n"
        let contributionRange = try #require(range(of: "$x$", in: body))
        let heading = try #require(range(of: "# Heading", in: body))
        let result = DerivedContentComposer.compose(
            bodyText: body,
            bodyStartOffset: 0,
            sourceUTF16Length: body.utf16.count,
            contributions: [
                ExportDerivedContribution(
                    sourceRange: contributionRange,
                    placement: .inline,
                    html: "<span>stale</span>",
                    sourceGeneration: 9
                ),
            ],
            sourceGeneration: 1,
            recordCoordinates: true
        )

        let coordinates = try #require(result.coordinates)
        #expect(result.splicedBody == body)
        #expect(coordinates.renderedOffset(forOriginalOffset: heading.lowerBound) == heading.lowerBound)
        #expect(coordinates.renderedOffset(forOriginalOffset: contributionRange.lowerBound)
            == contributionRange.lowerBound)

        let ordinary = DerivedContentComposer.compose(
            bodyText: body,
            bodyStartOffset: 0,
            sourceUTF16Length: body.utf16.count,
            contributions: [],
            sourceGeneration: 1
        )
        #expect(ordinary.coordinates?.sourceSHA256 == nil)
    }

    @Test func frontMatterOffsetIsRemovedBeforeMapping() throws {
        let prefix = "---\ntitle: Example\n---\n"
        let body = "before $x$\n# Heading\n"
        let localRange = try #require(range(of: "$x$", in: body))
        let heading = try #require(range(of: "# Heading", in: body))
        let result = DerivedContentComposer.compose(
            bodyText: body,
            bodyStartOffset: prefix.utf16.count,
            sourceUTF16Length: prefix.utf16.count + body.utf16.count,
            contributions: [
                ExportDerivedContribution(
                    sourceRange: (localRange.lowerBound + prefix.utf16.count)
                        ..< (localRange.upperBound + prefix.utf16.count),
                    placement: .inline,
                    html: "<span>x</span>",
                    sourceGeneration: 1
                ),
            ],
            sourceGeneration: 1,
            recordCoordinates: true
        )

        let coordinates = try #require(result.coordinates)
        let renderedHeading = try #require(range(of: "# Heading", in: result.splicedBody))
        #expect(coordinates.renderedOffset(forOriginalOffset: heading.lowerBound)
            == renderedHeading.lowerBound)
        #expect(coordinates.renderedOffset(forOriginalOffset: localRange.lowerBound) == nil)
    }

    @Test func matchesGeneratedCMarkHeadingsAfterSplicingWithoutTrustingRawTags() async throws {
        let fixture = try await headingFixture()
        let (source, document, index, derived, rendered, bodyStart) = (
            fixture.source, fixture.document, fixture.index, fixture.derived, fixture.rendered, fixture.bodyStart
        )

        let matches = try #require(EmittedHeadingMatcher.match(
            index: index, document: document, sourceText: source, derived: derived, rendered: rendered
        ))
        #expect(matches.count == 3)
        #expect(matches.map(\.indexed.fragment) == ["repeat", "nested", "repeat-1"])
        #expect(matches.map(\.emitted.level) == [1, 2, 1])
        #expect(rendered.html.contains("<h1 id=\"authored\">Raw heading</h1>"))

        let differentLevel = try CMarkGFM.render(
            derived.splicedBody.replacingOccurrences(of: "> ## Nested", with: "> ### Nested"),
            options: CMarkGFM.optUnsafe,
            collectHeadingLocations: true
        )
        #expect(EmittedHeadingMatcher.match(
            index: index, document: document, sourceText: source, derived: derived, rendered: differentLevel
        ) == nil)
        let differentText = try CMarkGFM.render(
            derived.splicedBody.replacingOccurrences(of: "# Repeat", with: "# Change"),
            options: CMarkGFM.optUnsafe,
            collectHeadingLocations: true
        )
        #expect(EmittedHeadingMatcher.match(
            index: index, document: document, sourceText: source, derived: derived, rendered: differentText
        ) == nil)
        #expect(EmittedHeadingMatcher.match(
            index: index, document: document, sourceText: source + " ", derived: derived, rendered: rendered
        ) == nil)
        let otherBody = document.body.replacingOccurrences(of: "Paragraph $x$.", with: "Paragraph $y$.")
        let otherDerived = DerivedContentComposer.compose(
            bodyText: otherBody,
            bodyStartOffset: bodyStart,
            sourceUTF16Length: source.utf16.count,
            contributions: [],
            sourceGeneration: 1,
            recordCoordinates: true
        )
        let otherRender = try CMarkGFM.render(
            otherDerived.splicedBody,
            options: CMarkGFM.optUnsafe,
            collectHeadingLocations: true
        )
        #expect(EmittedHeadingMatcher.match(
            index: index, document: document, sourceText: source, derived: otherDerived, rendered: otherRender
        ) == nil)
    }

    @Test func leakedSentinelFallbackRequiresItsOwnCoordinates() async throws {
        let fixture = try await headingFixture()
        let (source, document, index, bodyStart) = (
            fixture.source, fixture.document, fixture.index, fixture.bodyStart
        )
        // A leaked-sentinel fallback re-composes the body. It must use that
        // new body's map, rather than the first render's shifted positions.
        let fallback = DerivedContentComposer.compose(
            bodyText: document.body,
            bodyStartOffset: bodyStart,
            sourceUTF16Length: source.utf16.count,
            contributions: [],
            sourceGeneration: 1,
            recordCoordinates: true
        )
        let fallbackRender = try CMarkGFM.render(
            fallback.splicedBody,
            options: CMarkGFM.optUnsafe,
            collectHeadingLocations: true
        )
        #expect(EmittedHeadingMatcher.match(
            index: index, document: document, sourceText: source, derived: fallback, rendered: fallbackRender
        )?.count == 3)
    }
}

private extension SplicedBodySourceMapTests {
    struct HeadingFixture {
        let source: String
        let document: MarkdownDocument
        let index: HeadingAnchorIndex
        let derived: DerivedContentComposer.Result
        let rendered: CMarkGFM.Rendered
        let bodyStart: Int
    }

    private func headingFixture() async throws -> HeadingFixture {
        let source = headingSource
        let document = try await ParseEngine().parse(source, revision: 1)
        #expect(source.hasSuffix(document.body))
        let bodyStart = source.utf16.count - document.body.utf16.count
        let contributions = try headingContributions(in: source)
        let index = try HeadingAnchorIndex(
            document: document,
            sourceText: source,
            documentID: "fixture",
            recoveryEpoch: UUID(),
            sourceGeneration: 1,
            reservedIDs: []
        )
        let derived = DerivedContentComposer.compose(
            bodyText: document.body,
            bodyStartOffset: bodyStart,
            sourceUTF16Length: source.utf16.count,
            contributions: contributions,
            sourceGeneration: 1,
            recordCoordinates: true
        )
        let rendered = try CMarkGFM.render(
            derived.splicedBody,
            options: CMarkGFM.optUnsafe,
            customNodes: derived.customNodes,
            collectHeadingLocations: true
        )
        return HeadingFixture(
            source: source, document: document, index: index, derived: derived,
            rendered: rendered, bodyStart: bodyStart
        )
    }

    private var headingSource: String {
        """
        ---
        title: Example
        ---

        # Repeat

        ```diagram
        node
        ```

        > ## Nested

        Paragraph $x$.

        # Repeat

        <h1 id="authored">Raw heading</h1>
        """
    }

    private func headingContributions(in source: String) throws -> [ExportDerivedContribution] {
        let block = try #require(range(of: "```diagram\nnode\n```", in: source))
        let inline = try #require(range(of: "$x$", in: source))
        return [
            ExportDerivedContribution(
                sourceRange: block,
                placement: .block,
                html: "<svg>diagram</svg>",
                sourceGeneration: 1
            ),
            ExportDerivedContribution(
                sourceRange: inline,
                placement: .inline,
                html: "<span>x</span>",
                sourceGeneration: 1
            ),
        ]
    }

    private func range(of needle: String, in text: String) -> Range<Int>? {
        let found = (text as NSString).range(of: needle)
        guard found.location != NSNotFound else { return nil }
        return found.location ..< (found.location + found.length)
    }
}
