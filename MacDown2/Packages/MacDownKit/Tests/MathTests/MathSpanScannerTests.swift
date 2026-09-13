import Foundation
@testable import Math
import Testing

/// This scanner's contract is to match, character-for-character, what
/// `Textual`'s sealed `.math` `SyntaxExtension` would match — see
/// `MathSpanScanner.swift`'s own doc comment and
/// epic-19-implementation.md §2.1/§6.1. These fixtures are that contract:
/// they are derived by hand-tracing `PatternTokenizer`'s actual matching
/// algorithm (leftmost position, display pattern tried before inline,
/// prefix match only, one character advanced on no match), not merely by
/// guessing what "should" happen.
@Suite("MathSpanScanner")
struct MathSpanScannerTests {
    @Test func scanFindsASimpleInlineSpan() {
        let spans = MathSpanScanner.scan("$x=1$")
        #expect(spans.count == 1)
        #expect(spans.first?.style == .inline)
        #expect(spans.first?.latex == "x=1")
        #expect(spans.first?.range == 0 ..< 5)
    }

    @Test func scanFindsASimpleDisplaySpan() {
        let spans = MathSpanScanner.scan("$$x=1$$")
        #expect(spans.count == 1)
        #expect(spans.first?.style == .display)
        #expect(spans.first?.latex == "x=1")
        #expect(spans.first?.range == 0 ..< 7)
    }

    /// The display pattern is tried before the inline pattern at every
    /// position, so `$$...$$` is one display span, never two adjacent
    /// (and incorrect) inline spans each missing half their content.
    @Test func scanPrefersDisplayOverInlineForAdjacentDollarPairs() {
        let spans = MathSpanScanner.scan("$$E=mc^2$$")
        #expect(spans.count == 1)
        #expect(spans.first?.style == .display)
        #expect(spans.first?.latex == "E=mc^2")
    }

    @Test func scanFindsMultipleSpansInOrder() {
        let spans = MathSpanScanner.scan("$a$ and $b$")
        #expect(spans.count == 2)
        #expect(spans.map(\.latex) == ["a", "b"])
        #expect(spans.allSatisfy { $0.style == .inline })
    }

    @Test func scanFindsSpansInterleavedWithProse() throws {
        let text = "The energy is $E = mc^2$, a famous result."
        let spans = MathSpanScanner.scan(text)
        #expect(spans.count == 1)
        #expect(spans.first?.latex == "E = mc^2")
        let range = try #require(spans.first?.range)
        #expect((text as NSString)
            .substring(with: NSRange(location: range.lowerBound, length: range.count)) == "$E = mc^2$")
    }

    /// `\$` inside an inline span is consumed as one escaped unit by the
    /// alternation, not treated as the closing delimiter — mirrors
    /// Textual's own `mathInline` pattern exactly.
    @Test func scanTreatsAnEscapedDollarInsideInlineMathAsPartOfTheSpan() {
        let spans = MathSpanScanner.scan("$a\\$b$")
        #expect(spans.count == 1)
        #expect(spans.first?.latex == "a\\$b")
    }

    /// Inline math's character class excludes `\n`, so a span can never
    /// cross a line boundary — required so a `$` ending one paragraph and a
    /// `$` starting the next are never mistaken for one span
    /// (epic-19-implementation.md §15).
    @Test func scanNeverMatchesInlineMathAcrossANewline() {
        let spans = MathSpanScanner.scan("$a\nb$")
        #expect(spans.isEmpty)
    }

    /// Display math's `(?s)` flag DOES allow it to span multiple lines,
    /// matching a `$$\n...\n$$` block written across several lines.
    @Test func scanMatchesDisplayMathAcrossMultipleLines() {
        let text = "$$\n\\int_0^1 x^2\\,dx = \\frac{1}{3}\n$$"
        let spans = MathSpanScanner.scan(text)
        #expect(spans.count == 1)
        #expect(spans.first?.style == .display)
        #expect(spans.first?.latex == "\n\\int_0^1 x^2\\,dx = \\frac{1}{3}\n")
    }

    @Test func scanIgnoresALoneUnmatchedDollarSign() {
        #expect(MathSpanScanner.scan("Price: $5").isEmpty)
    }

    /// A known, documented false-positive: an even number of unescaped `$`
    /// in ordinary prose is indistinguishable from math to this scanner —
    /// this is inherited from Textual's own regex design, not something
    /// this scanner introduces or could safely special-case (residual risk
    /// 3, epic-19-implementation.md §18). This test exists to document the
    /// behavior precisely, not to endorse it.
    @Test func scanTreatsAnEvenCountOfDollarSignsInProseAsMath() {
        let spans = MathSpanScanner.scan("Price: $5, $10")
        #expect(spans.count == 1)
        #expect(spans.first?.latex == "5, ")
    }

    @Test func scanTreatsALoneDoubleDollarWithNoContentAsUnmatchedText() {
        #expect(MathSpanScanner.scan("$$").isEmpty)
    }

    @Test func scanTreatsFourConsecutiveDollarSignsAsUnmatchedText() {
        #expect(MathSpanScanner.scan("$$$$").isEmpty)
    }

    @Test func scanReturnsNothingForTextWithNoMathAtAll() {
        #expect(MathSpanScanner.scan("Just a paragraph, no equations here.").isEmpty)
    }

    @Test func scanReturnsNothingForEmptyText() {
        #expect(MathSpanScanner.scan("").isEmpty)
    }

    @Test func scanHandlesAMixOfInlineAndDisplaySpansInOneDocument() {
        let text = "Inline $a=1$ then display:\n\n$$\nb=2\n$$\n\nand another inline $c=3$."
        let spans = MathSpanScanner.scan(text)
        #expect(spans.map(\.style) == [.inline, .display, .inline])
        #expect(spans.map(\.latex) == ["a=1", "\nb=2\n", "c=3"])
    }
}
