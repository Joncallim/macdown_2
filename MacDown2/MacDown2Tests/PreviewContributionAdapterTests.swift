import Contributions
@testable import MacDown2
import MarkdownEngine
import Preview
import Testing

@Suite("PreviewContributionAdapter")
struct PreviewContributionAdapterTests {
    // MARK: - results

    @Test func resultsIsEmptyWithoutADocumentOrText() async {
        let withoutDocument = await PreviewContributionAdapter.results(document: nil, text: "[TOC]", generation: 0)
        #expect(withoutDocument.isEmpty)

        let document = try? await ParseEngine().parse("[TOC]", revision: 0)
        let withoutText = await PreviewContributionAdapter.results(document: document, text: nil, generation: 0)
        #expect(withoutText.isEmpty)
    }

    @Test func resultsRunsTheStandardRegistryEndToEnd() async throws {
        let text = "# Title\n\n[TOC]\n\n## Section\n"
        let document = try await ParseEngine().parse(text, revision: 0)

        let results = await PreviewContributionAdapter.results(document: document, text: text, generation: 3)

        #expect(results.count == 1)
        #expect(results.first?.content != nil)
        #expect(results.first?.sourceGeneration == 3)
    }

    // MARK: - merged

    @Test func mergedReturnsBaseUnchangedWithNoContributions() {
        let base = [Self.block(lines: 1 ... 1, source: "Hello")]
        let merged = PreviewContributionAdapter.merged(
            base: base, contributions: [], sourceMap: SourceMap(text: "Hello"), currentGeneration: 0
        )
        #expect(merged == base)
    }

    @Test func mergedReturnsNilBaseUnchanged() {
        let merged = PreviewContributionAdapter.merged(
            base: nil, contributions: [], sourceMap: SourceMap(text: ""), currentGeneration: 0
        )
        #expect(merged == nil)
    }

    @Test func mergedSubstitutesTheBlockContainingAPlaceableContribution() throws {
        let text = "Intro\n\n[TOC]\n\nMore"
        let sourceMap = SourceMap(text: text)
        let base = [
            Self.block(lines: 1 ... 1, source: "Intro"),
            Self.block(lines: 3 ... 3, source: "[TOC]"),
            Self.block(lines: 5 ... 5, source: "More"),
        ]
        let markerOffset = sourceMap.utf16Range(ofLines: 3 ... 3).location
        let content = ContributionContent(
            sourceRange: markerOffset ..< (markerOffset + 5), placement: .block, representation: .markdown("- Heading")
        )
        let contribution = ContributionResult(contributionID: "toc", content: content, sourceGeneration: 1)

        let merged = try #require(PreviewContributionAdapter.merged(
            base: base, contributions: [contribution], sourceMap: sourceMap, currentGeneration: 1
        ))

        #expect(merged.count == 3)
        #expect(merged[0].source == "Intro")
        #expect(merged[1].source == "- Heading")
        #expect(merged[1].kind == .custom("toc"))
        #expect(merged[1].lineRange == 3 ... 3)
        #expect(merged[2].source == "More")
    }

    @Test func mergedRejectsAStaleGeneration() {
        let text = "[TOC]"
        let sourceMap = SourceMap(text: text)
        let base = [Self.block(lines: 1 ... 1, source: text)]
        let content = ContributionContent(sourceRange: 0 ..< 5, placement: .block, representation: .markdown("- x"))
        let contribution = ContributionResult(contributionID: "toc", content: content, sourceGeneration: 1)

        let merged = PreviewContributionAdapter.merged(
            base: base, contributions: [contribution], sourceMap: sourceMap, currentGeneration: 2
        )

        #expect(merged?.first?.source == text)
    }

    /// `.html` is a real, typed case that no adapter in this epic handles yet
    /// (epic-14-implementation.md §18) — a result carrying one must not be
    /// substituted.
    @Test func mergedIgnoresAnHTMLRepresentation() {
        let text = "[TOC]"
        let sourceMap = SourceMap(text: text)
        let base = [Self.block(lines: 1 ... 1, source: text)]
        let content = ContributionContent(sourceRange: 0 ..< 5, placement: .block, representation: .html("<p>x</p>"))
        let contribution = ContributionResult(contributionID: "toc", content: content, sourceGeneration: 1)

        let merged = PreviewContributionAdapter.merged(
            base: base, contributions: [contribution], sourceMap: sourceMap, currentGeneration: 1
        )

        #expect(merged?.first?.source == text)
    }

    private static func block(lines: ClosedRange<Int>, source: String) -> PreviewBlock {
        PreviewBlock(kind: .paragraph, source: source, lineRange: lines)
    }
}
