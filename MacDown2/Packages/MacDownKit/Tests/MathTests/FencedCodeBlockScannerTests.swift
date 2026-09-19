import Foundation
@testable import Math
import Testing

@Suite("FencedCodeBlockScanner")
struct FencedCodeBlockScannerTests {
    private func substrings(_ text: String, _ ranges: [Range<Int>]) -> [String] {
        let nsText = text as NSString
        return ranges
            .map { nsText.substring(with: NSRange(location: $0.lowerBound, length: $0.upperBound - $0.lowerBound)) }
    }

    @Test func findsATopLevelBacktickFence() {
        let text = "before\n```\ncode\n```\nafter"
        let ranges = FencedCodeBlockScanner.ranges(in: text)
        #expect(substrings(text, ranges) == ["```\ncode\n```\n"])
    }

    @Test func findsATildeFence() {
        let text = "before\n~~~\ncode\n~~~\nafter"
        let ranges = FencedCodeBlockScanner.ranges(in: text)
        #expect(substrings(text, ranges) == ["~~~\ncode\n~~~\n"])
    }

    @Test func findsAFenceIndentedInsideAListItem() {
        let text = "- item text\n\n  ```\n  literal code:\n\n  $bad$ end\n  ```"
        let ranges = FencedCodeBlockScanner.ranges(in: text)
        #expect(ranges.count == 1)
        let matched = substrings(text, ranges)[0]
        #expect(matched.contains("$bad$"))
        #expect(matched.hasPrefix("  ```"))
    }

    @Test func findsAFenceIndentedInsideABlockQuote() {
        let text = "> quoted\n>\n> ```\n> code\n> ```"
        let ranges = FencedCodeBlockScanner.ranges(in: text)
        #expect(ranges.count == 1)
    }

    @Test func toleratesABlankLineInsideTheFenceBody() {
        let text = "```\nfirst\n\nsecond\n```"
        let ranges = FencedCodeBlockScanner.ranges(in: text)
        #expect(ranges.count == 1)
        #expect(substrings(text, ranges)[0] == text)
    }

    @Test func unterminatedFenceExtendsToTheEndOfTheText() {
        let text = "```\nno closing fence here"
        let ranges = FencedCodeBlockScanner.ranges(in: text)
        #expect(ranges.count == 1)
        #expect(ranges[0].upperBound == (text as NSString).length)
    }

    @Test func aShorterClosingRunDoesNotClose() {
        // The closing run (2 backticks) is shorter than the opening run (4),
        // so per CommonMark it does not close the fence — the real closer
        // is the final, correctly-long run.
        let text = "````\ncode ``\nmore\n````"
        let ranges = FencedCodeBlockScanner.ranges(in: text)
        #expect(ranges.count == 1)
        #expect(substrings(text, ranges)[0] == text)
    }

    @Test func mismatchedFenceCharacterDoesNotClose() {
        let text = "```\ncode ~~~ still code\n```"
        let ranges = FencedCodeBlockScanner.ranges(in: text)
        #expect(ranges.count == 1)
        #expect(substrings(text, ranges)[0] == text)
    }

    @Test func aBacktickInTheInfoStringMeansItIsNotARealFenceOpen() {
        // CommonMark: a backtick fence's info string cannot itself contain a
        // backtick (it would be ambiguous with the fence delimiter itself).
        // The first line is correctly rejected as a fence-open; the bare
        // ``` on the last line is still a genuine (if unterminated) fence
        // in its own right, which the scanner correctly still finds.
        let text = "``` `oops`\nnot a real fence\n```"
        let ranges = FencedCodeBlockScanner.ranges(in: text)
        #expect(ranges.count == 1)
        #expect(!ranges.contains { $0.lowerBound == 0 })
    }

    @Test func findsMultipleFencesInOneText() {
        let text = "```\nfirst\n```\n\ntext between\n\n~~~\nsecond\n~~~\n"
        let ranges = FencedCodeBlockScanner.ranges(in: text)
        #expect(ranges.count == 2)
    }

    @Test func returnsNoRangesForPlainTextWithoutAnyFence() {
        #expect(FencedCodeBlockScanner.ranges(in: "just $math$ and text").isEmpty)
    }

    @Test func twoBackticksIsNotAFence() {
        // CommonMark requires at least 3; 2 backticks is an ordinary inline
        // code span, not this scanner's concern.
        #expect(FencedCodeBlockScanner.ranges(in: "``not a fence``").isEmpty)
    }
}
