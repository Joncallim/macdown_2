import Contributions
@testable import MacDown2
import MarkdownEngine
import Preview
import Testing

/// Exhaustive admission/placement/budget coverage for
/// `PreviewContributionAdapter.compose(...)` (architecture takeover, passes
/// 5/10, 6/10, 7/10). Complements `PreviewContributionAdapterTests`, which
/// covers the happy-path paragraph-splice and pass-through behavior.
@Suite("PreviewContributionAdapter composition")
struct PreviewContributionComposerTests {
    // MARK: - Fixtures

    private static func document(text: String) -> MarkdownDocument {
        MarkdownDocument(
            body: text, bodyLineOffset: 0, blocks: [], headings: [], frontMatter: nil,
            sourceMap: SourceMap(text: text), revision: 0, options: .default
        )
    }

    private static func markdown(
        _ range: Range<Int>,
        placement: ContributionPlacement,
        _ text: String,
        generation: UInt = 1
    ) -> ContributionResult {
        let content = ContributionContent(sourceRange: range, placement: placement, representation: .markdown(text))
        return ContributionResult(contributionID: "t", content: content, sourceGeneration: generation)
    }

    private static func compose(
        text: String, base: [PreviewBlock], contributions: [ContributionResult], generation: UInt = 1
    ) -> PreviewContributionComposition {
        PreviewContributionAdapter.compose(
            base: base, document: document(text: text), sourceText: text,
            contributions: contributions, sourceGeneration: generation
        )
    }

    // MARK: - Inline placement (pass 5/10)

    @Test func inlinePlacementSplicesInPlacePreservingPrefixSuffixAndBlockKind() {
        let text = "one two three"
        let base = [PreviewBlock(kind: .heading(level: 2), source: text, lineRange: 1 ... 1)]
        let range = 4 ..< 7 // "two"
        let result = Self.markdown(range, placement: .inline, "TWO")

        let composition = Self.compose(text: text, base: base, contributions: [result])

        let blocks = composition.blocks ?? []
        #expect(blocks.count == 1)
        #expect(blocks.first?.source == "one TWO three")
        #expect(blocks.first?.kind == .heading(level: 2))
    }

    @Test func inlineSourceSpanningLinesIsRejected() {
        let text = "one\ntwo"
        let base = [PreviewBlock(kind: .paragraph, source: text, lineRange: 1 ... 2)]
        let range = 2 ..< 5 // crosses the "\n"
        let result = Self.markdown(range, placement: .inline, "X")

        let composition = Self.compose(text: text, base: base, contributions: [result])

        #expect(composition.blocks == base)
        #expect(composition.diagnostics.contains { $0.severity == .error })
    }

    @Test func inlineGeneratedMarkdownContainingALineBreakIsRejected() {
        let text = "one two"
        let base = [PreviewBlock(kind: .paragraph, source: text, lineRange: 1 ... 1)]
        let range = 4 ..< 7
        let result = Self.markdown(range, placement: .inline, "a\nb")

        let composition = Self.compose(text: text, base: base, contributions: [result])

        #expect(composition.blocks == base)
        #expect(composition.diagnostics.contains { $0.severity == .error })
    }

    // MARK: - Block placement (pass 5/10)

    @Test func wholeBlockReplacementWorksForANonParagraphBaseBlock() {
        let text = "```\ncode\n```"
        let base = [PreviewBlock(kind: .codeBlock(language: nil), source: text, lineRange: 1 ... 3)]
        let result = Self.markdown(0 ..< text.utf16.count, placement: .block, "- replaced")

        let composition = Self.compose(text: text, base: base, contributions: [result])

        let blocks = composition.blocks ?? []
        #expect(blocks.count == 1)
        #expect(blocks.first?.source == "- replaced")
        #expect(blocks.first?.kind == .custom("t"))
    }

    @Test func partialBlockReplacementInsideAParagraphOnCompletePhysicalLinesWorks() {
        let text = "one\ntwo\nthree"
        let base = [PreviewBlock(kind: .paragraph, source: text, lineRange: 1 ... 3)]
        let sourceMap = SourceMap(text: text)
        let lineTwo = sourceMap.utf16Range(ofLines: 2 ... 2)
        let range = lineTwo.location ..< (lineTwo.location + lineTwo.length)
        let result = Self.markdown(range, placement: .block, "TWO")

        let composition = Self.compose(text: text, base: base, contributions: [result])

        // The authored prefix is the exact captured slice, which includes
        // its own line's terminator — only a block placement's own trailing
        // LF is ever consumed, never an earlier authored one.
        let blocks = composition.blocks ?? []
        #expect(blocks.map(\.source) == ["one\n", "TWO", "three"])
    }

    @Test func partialBlockReplacementOutsideAParagraphIsRejected() {
        let text = "```\ntwo\n```"
        let base = [PreviewBlock(kind: .codeBlock(language: nil), source: text, lineRange: 1 ... 3)]
        let sourceMap = SourceMap(text: text)
        let lineTwo = sourceMap.utf16Range(ofLines: 2 ... 2)
        let range = lineTwo.location ..< (lineTwo.location + lineTwo.length)
        let result = Self.markdown(range, placement: .block, "TWO")

        let composition = Self.compose(text: text, base: base, contributions: [result])

        #expect(composition.blocks == base)
        #expect(composition.diagnostics.contains { $0.severity == .error })
    }

    @Test func partialBlockReplacementNotAlignedToWholeLinesIsRejected() {
        let text = "one two\nthree"
        let base = [PreviewBlock(kind: .paragraph, source: text, lineRange: 1 ... 2)]
        let result = Self.markdown(4 ..< 7, placement: .block, "X") // mid-line "two"

        let composition = Self.compose(text: text, base: base, contributions: [result])

        #expect(composition.blocks == base)
        #expect(composition.diagnostics.contains { $0.severity == .error })
    }

    @Test func mixedNonOverlappingInlineAndBlockPlacementsPreserveSourceOrder() {
        let text = "one two\nthree"
        let base = [PreviewBlock(kind: .paragraph, source: text, lineRange: 1 ... 2)]
        let sourceMap = SourceMap(text: text)
        let lineTwo = sourceMap.utf16Range(ofLines: 2 ... 2)
        let inline = Self.markdown(4 ..< 7, placement: .inline, "TWO") // "two" inline
        let block = Self.markdown(
            lineTwo.location ..< (lineTwo.location + lineTwo.length), placement: .block, "- three"
        )

        let composition = Self.compose(text: text, base: base, contributions: [inline, block])

        let blocks = composition.blocks ?? []
        #expect(blocks.map(\.source) == ["one TWO\n", "- three"])
    }

    // MARK: - Malformed ranges (pass 6/10)

    @Test func negativeLowerBoundIsRejected() {
        let text = "hello"
        let base = [PreviewBlock(kind: .paragraph, source: text, lineRange: 1 ... 1)]
        let content = ContributionContent(sourceRange: -1 ..< 2, placement: .block, representation: .markdown("x"))
        let result = ContributionResult(contributionID: "t", content: content, sourceGeneration: 1)

        let composition = Self.compose(text: text, base: base, contributions: [result])
        #expect(composition.blocks == base)
    }

    @Test func upperBoundBeyondUTF16LengthIsRejected() {
        let text = "hi"
        let base = [PreviewBlock(kind: .paragraph, source: text, lineRange: 1 ... 1)]
        let result = Self.markdown(0 ..< 99, placement: .block, "x")

        let composition = Self.compose(text: text, base: base, contributions: [result])
        #expect(composition.blocks == base)
    }

    @Test func aRangeContainingOnlyANewlineGapBetweenBlocksIsRejected() {
        let text = "one\n\ntwo"
        let base = [
            PreviewBlock(kind: .paragraph, source: "one", lineRange: 1 ... 1),
            PreviewBlock(kind: .paragraph, source: "two", lineRange: 3 ... 3),
        ]
        // Offsets 3...4 are the blank line 2 — outside both block intervals.
        let result = Self.markdown(3 ..< 5, placement: .block, "x")

        let composition = Self.compose(text: text, base: base, contributions: [result])
        #expect(composition.blocks == base)
    }

    @Test func aRangeCrossingTwoBlocksIsRejected() {
        let text = "one\ntwo"
        let base = [
            PreviewBlock(kind: .paragraph, source: "one", lineRange: 1 ... 1),
            PreviewBlock(kind: .paragraph, source: "two", lineRange: 2 ... 2),
        ]
        let result = Self.markdown(1 ..< 6, placement: .block, "x")

        let composition = Self.compose(text: text, base: base, contributions: [result])
        #expect(composition.blocks == base)
    }

    @Test func aRangeValidForADifferentSourceIsRejected() {
        // `text` here is shorter than the document's own captured source, so
        // sourceMap.utf16Length != sourceUTF16Length — a document/source
        // mismatch must reject every candidate rather than mis-splice.
        let shortText = "hi"
        let longDocument = Self.document(text: "hi there, this is longer")
        let base = [PreviewBlock(kind: .paragraph, source: shortText, lineRange: 1 ... 1)]
        let result = Self.markdown(0 ..< 2, placement: .block, "x")

        let composition = PreviewContributionAdapter.compose(
            base: base, document: longDocument, sourceText: shortText, contributions: [result], sourceGeneration: 1
        )
        #expect(composition.blocks == base)
        #expect(composition.diagnostics.contains { $0.severity == .error })
    }

    @Test func nonBMPSourceProvesBoundsUseUTF16NotGraphemeCounts() {
        let text = "🎉x" // 🎉 is 2 UTF-16 code units; "x" starts at UTF-16 offset 2.
        let base = [PreviewBlock(kind: .paragraph, source: text, lineRange: 1 ... 1)]
        let result = Self.markdown(2 ..< 3, placement: .inline, "Y")

        let composition = Self.compose(text: text, base: base, contributions: [result])

        let blocks = composition.blocks ?? []
        #expect(blocks.first?.source == "🎉Y")
    }

    @Test func aMalformedEarlierCandidateDoesNotPreventALaterValidCandidate() {
        let text = "one two"
        let base = [PreviewBlock(kind: .paragraph, source: text, lineRange: 1 ... 1)]
        let malformed = Self.markdown(-1 ..< 2, placement: .inline, "bad")
        let valid = Self.markdown(4 ..< 7, placement: .inline, "TWO")

        let composition = Self.compose(text: text, base: base, contributions: [malformed, valid])

        let blocks = composition.blocks ?? []
        #expect(blocks.first?.source == "one TWO")
        #expect(composition.diagnostics.contains { $0.severity == .error })
    }

    // MARK: - Overlap

    @Test func anOverlappingLaterResultLeavesItsSourceUntouchedWithADiagnostic() {
        let text = "one two three"
        let base = [PreviewBlock(kind: .paragraph, source: text, lineRange: 1 ... 1)]
        let first = Self.markdown(4 ..< 13, placement: .inline, "REST") // "two three"
        let overlapping = Self.markdown(8 ..< 13, placement: .inline, "THREE") // "three", overlaps first

        let composition = Self.compose(text: text, base: base, contributions: [first, overlapping])

        let blocks = composition.blocks ?? []
        #expect(blocks.first?.source == "one REST")
        #expect(composition.diagnostics.contains { $0.severity == .warning })
    }

    // MARK: - Budget (pass 7/10)

    @Test func exactlyTheBudgetCeilingComposesWithNoWarning() {
        let text = String(repeating: "x", count: 64)
        let base = [PreviewBlock(kind: .paragraph, source: text, lineRange: 1 ... 1)]
        let results = (0 ..< 64).map { Self.markdown($0 ..< ($0 + 1), placement: .inline, "Y") }

        let composition = Self.compose(text: text, base: base, contributions: results)

        #expect(!composition.diagnostics.contains { $0.contributionID == "preview-budget" })
    }

    @Test func the65thAcceptedPlacementRemainsAuthoredWithOneAggregateWarning() {
        let text = String(repeating: "x", count: 65)
        let base = [PreviewBlock(kind: .paragraph, source: text, lineRange: 1 ... 1)]
        let results = (0 ..< 65).map { Self.markdown($0 ..< ($0 + 1), placement: .inline, "Y") }

        let composition = Self.compose(text: text, base: base, contributions: results)

        let blocks = composition.blocks ?? []
        #expect(blocks.first?.source.filter { $0 == "x" }.count == 1)
        let budgetWarnings = composition.diagnostics.filter { $0.contributionID == "preview-budget" }
        #expect(budgetWarnings.count == 1)
        #expect(budgetWarnings.first?.message.contains("1") == true)
    }

    @Test func invalidStaleAndOverlappingCandidatesDoNotConsumeCountBudget() {
        let text = String(repeating: "x", count: 3)
        let base = [PreviewBlock(kind: .paragraph, source: text, lineRange: 1 ... 1)]
        let stale = Self.markdown(0 ..< 1, placement: .inline, "A", generation: 999)
        let overlapping1 = Self.markdown(1 ..< 2, placement: .inline, "B")
        let overlapping2 = Self.markdown(1 ..< 2, placement: .inline, "C")

        let composition = Self.compose(text: text, base: base, contributions: [stale, overlapping1, overlapping2])

        #expect(!composition.diagnostics.contains { $0.contributionID == "preview-budget" })
    }

    @Test func theGeneratedByteBudgetRejectsOnlyTheOverBudgetCandidate() {
        let text = "ab"
        let base = [PreviewBlock(kind: .paragraph, source: text, lineRange: 1 ... 1)]
        let within = String(repeating: "a", count: PreviewContributionBudget.standard.maximumGeneratedMarkdownUTF8Bytes)
        let atLimit = Self.markdown(0 ..< 1, placement: .inline, within)
        let overLimit = Self.markdown(1 ..< 2, placement: .inline, "one more byte")

        let composition = Self.compose(text: text, base: base, contributions: [atLimit, overLimit])

        let blocks = composition.blocks ?? []
        #expect(blocks.first?.source.hasSuffix("b") == true)
        #expect(composition.diagnostics.contains { $0.contributionID == "preview-budget" })
    }

    @Test func anOversizedCandidateFollowedByASmallValidCandidateStillFitsTheSmallOne() throws {
        let text = "abc"
        let base = [PreviewBlock(kind: .paragraph, source: text, lineRange: 1 ... 1)]
        let huge = String(
            repeating: "z",
            count: PreviewContributionBudget.standard.maximumGeneratedMarkdownUTF8Bytes + 1
        )
        let oversized = Self.markdown(0 ..< 1, placement: .inline, huge)
        let small = Self.markdown(1 ..< 2, placement: .inline, "Y")

        let composition = Self.compose(text: text, base: base, contributions: [oversized, small])

        let blocks = composition.blocks ?? []
        #expect(blocks.first?.source.contains("Y") == true)
        #expect(try !(#require(blocks.first?.source.contains("z"))))
    }
}
