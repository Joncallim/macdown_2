import Foundation
@testable import Math
import Testing

/// Review pass 1: math scanning only knew `\n`, so CRLF/CR documents got phantom
/// inline equations spanning line breaks and stray backticks that hid math.
struct MathLineEndingTests {
    @Test(arguments: ["\n", "\r\n", "\r"])
    func anInlineSpanNeverCrossesALineBreak(lineEnding: String) {
        let spans = MathSpanScanner.scan("Cost $5 and\(lineEnding)more $6 end")
        #expect(spans.isEmpty, "phantom span for \(lineEnding.debugDescription)")
    }

    @Test(arguments: ["\n", "\r\n", "\r"])
    func aStrayBacktickDoesNotPairAcrossParagraphs(lineEnding: String) {
        let text = "stray ` tick\(lineEnding)\(lineEnding)math $x$ here\(lineEnding)\(lineEnding)another ` tick"
        let codeRanges = InlineCodeSpanScanner.ranges(in: text)
        #expect(codeRanges.isEmpty, "backticks paired across a blank line for \(lineEnding.debugDescription)")
    }

    @Test func aBacktickPairWithinOneParagraphIsStillACodeSpan() {
        #expect(InlineCodeSpanScanner.ranges(in: "a `code` b").count == 1)
        #expect(InlineCodeSpanScanner.ranges(in: "a `co\r\nde` b").count == 1)
    }
}
