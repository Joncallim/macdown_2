@testable import Contributions
import Foundation
import MarkdownEngine
import Testing

@Suite("TOCContribution")
struct TOCContributionTests {
    // MARK: - findMarkers

    @Test func findMarkersLocatesASingleMarkerLine() throws {
        let text = "# Title\n\n[TOC]\n\nBody."
        let sourceMap = SourceMap(text: text)

        let ranges = TOCContribution.findMarkers(in: text, sourceMap: sourceMap)

        #expect(ranges.count == 1)
        let range = try #require(ranges.first)
        let nsRange = NSRange(location: range.lowerBound, length: range.count)
        #expect((text as NSString).substring(with: nsRange) == "[TOC]")
    }

    @Test func findMarkersIgnoresATextWithNoMarker() {
        let text = "# Title\n\nJust a paragraph.\n"
        let sourceMap = SourceMap(text: text)

        #expect(TOCContribution.findMarkers(in: text, sourceMap: sourceMap).isEmpty)
    }

    @Test func findMarkersTrimsSurroundingWhitespace() {
        let text = "  [TOC]  \n"
        let sourceMap = SourceMap(text: text)

        #expect(TOCContribution.findMarkers(in: text, sourceMap: sourceMap).count == 1)
    }

    @Test func findMarkersHandlesACRLFTerminatedMarkerLine() {
        let text = "Intro\r\n[TOC]\r\nMore\r\n"
        let sourceMap = SourceMap(text: text)

        #expect(TOCContribution.findMarkers(in: text, sourceMap: sourceMap).count == 1)
    }

    @Test func findMarkersRequiresTheWholeLineNotAnEmbeddedOccurrence() {
        let text = "See [TOC] below for a table.\n"
        let sourceMap = SourceMap(text: text)

        #expect(TOCContribution.findMarkers(in: text, sourceMap: sourceMap).isEmpty)
    }

    @Test func findMarkersLocatesEveryOccurrence() {
        let text = "[TOC]\n\nSection\n\n[TOC]\n"
        let sourceMap = SourceMap(text: text)

        #expect(TOCContribution.findMarkers(in: text, sourceMap: sourceMap).count == 2)
    }

    // MARK: - markdownList

    @Test func markdownListWithNoHeadingsIsANonEmptyPlaceholder() {
        let list = TOCContribution.markdownList(for: [])
        #expect(!list.isEmpty)
    }

    @Test func markdownListIsFlatForHeadingsOfTheSameLevel() {
        let headings = [
            HeadingItem(level: 1, title: "One", lineRange: 1 ... 1),
            HeadingItem(level: 1, title: "Two", lineRange: 2 ... 2),
        ]

        #expect(TOCContribution.markdownList(for: headings) == "- One\n- Two")
    }

    @Test func markdownListNestsDeeperLevelsUnderTheirParent() {
        let headings = [
            HeadingItem(level: 1, title: "Intro", lineRange: 1 ... 1),
            HeadingItem(level: 2, title: "Background", lineRange: 2 ... 2),
            HeadingItem(level: 3, title: "Detail", lineRange: 3 ... 3),
            HeadingItem(level: 2, title: "Scope", lineRange: 4 ... 4),
            HeadingItem(level: 1, title: "Conclusion", lineRange: 5 ... 5),
        ]

        let expected = """
        - Intro
          - Background
            - Detail
          - Scope
        - Conclusion
        """
        #expect(TOCContribution.markdownList(for: headings) == expected)
    }

    /// A level that skips ahead of its predecessor (H1 -> H3, no H2) nests
    /// one level under the nearest shallower heading rather than leaving a
    /// phantom empty level (epic-14-implementation.md §6.2).
    @Test func markdownListCollapsesSkippedLevels() {
        let headings = [
            HeadingItem(level: 1, title: "A", lineRange: 1 ... 1),
            HeadingItem(level: 3, title: "B", lineRange: 2 ... 2),
        ]

        #expect(TOCContribution.markdownList(for: headings) == "- A\n  - B")
    }

    @Test func markdownListEscapesCommonMarkPunctuationInTitles() {
        let headings = [HeadingItem(level: 1, title: "Use [brackets] and *stars*", lineRange: 1 ... 1)]

        #expect(TOCContribution.markdownList(for: headings) == "- Use \\[brackets\\] and \\*stars\\*")
    }

    // MARK: - run (end-to-end, real parse)

    @Test func runProducesAPlacementForEachMarkerFromRealHeadings() async throws {
        let text = """
        # Title

        [TOC]

        ## Section One

        ## Section Two
        """
        let document = try await ParseEngine().parse(text, revision: 0)

        let results = try await TOCContribution().run(document: document, sourceText: text, sourceGeneration: 7)

        #expect(results.count == 1)
        let content = try #require(results.first?.content)
        #expect(content.placement == .block)
        guard case let .markdown(list) = content.representation else {
            Issue.record("expected a markdown representation")
            return
        }
        #expect(list.contains("Title"))
        #expect(list.contains("Section One"))
        #expect(list.contains("Section Two"))
        #expect(results.first?.sourceGeneration == 7)
    }

    @Test func runContributesNothingWhenThereIsNoMarker() async throws {
        let text = "# Title\n\nNo marker here.\n"
        let document = try await ParseEngine().parse(text, revision: 0)

        let results = try await TOCContribution().run(document: document, sourceText: text, sourceGeneration: 0)

        #expect(results.isEmpty)
    }
}
