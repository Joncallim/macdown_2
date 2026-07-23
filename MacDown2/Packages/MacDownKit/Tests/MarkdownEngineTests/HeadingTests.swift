import Foundation
@testable import MarkdownEngine
import Testing

struct HeadingTests {
    private let engine = ParseEngine()

    @Test func extractsAllHeadings() async throws {
        let document = try await engine.parse(Fixtures.headingCorpus, revision: 1)

        #expect(document.headings.count == 3)
        #expect(document.headings[0].level == 1)
        #expect(document.headings[1].level == 2)
        #expect(document.headings[2].level == 3)
    }

    @Test func headingTitlesArePlainText() async throws {
        let document = try await engine.parse("# Hello *world*\n", revision: 1)

        let heading = try #require(document.headings.first)
        #expect(heading.title == "Hello world")
    }

    @Test func headingsInsideBlockQuotesIncluded() async throws {
        let document = try await engine.parse(Fixtures.blockQuoteCorpus, revision: 1)

        #expect(document.headings.count == 1)
        #expect(document.headings[0].level == 2)
        #expect(document.headings[0].title == "Quote heading")
    }

    @Test func headingsInsideListsIncluded() async throws {
        let text = """
        - # List heading
        - Plain item
        """
        let document = try await engine.parse(text, revision: 1)

        #expect(document.headings.count == 1)
        #expect(document.headings[0].level == 1)
        #expect(document.headings[0].title == "List heading")
    }

    @Test func codeBlockDoesNotProduceHeadings() async throws {
        let text = """
        ```
        # Not a heading
        ```
        """
        let document = try await engine.parse(text, revision: 1)

        #expect(document.headings.isEmpty)
        #expect(document.blocks.contains(where: { $0.kind == .codeBlock(language: nil) }))
    }

    @Test func headingLineRangesUseOriginalSource() async throws {
        let document = try await engine.parse(Fixtures.validFrontMatter, revision: 1)

        let heading = try #require(document.headings.first)
        #expect(heading.lineRange == 9 ... 9)
    }
}
