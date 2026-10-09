import Foundation
@testable import Math
import Testing

// The previous Character-based (Swift `Regex`) scanner, kept as a reference: on text without grapheme-extending
// scalars the UTF-16 scanner must agree with it exactly (review pass 6 replaced it so a `$` glued to a ZWNJ is seen).

enum ReferenceMathScanner {
    static func scan(_ text: String) -> [MathSpan] {
        var spans: [MathSpan] = []
        var currentIndex = text.startIndex

        while currentIndex < text.endIndex {
            let remainder = text[currentIndex...]

            if let match = try? displayPattern.prefixMatch(in: remainder) {
                spans.append(span(for: match, style: .display, in: text))
                currentIndex = match.range.upperBound
                continue
            }
            if let match = try? inlinePattern.prefixMatch(in: remainder) {
                spans.append(span(for: match, style: .inline, in: text))
                currentIndex = match.range.upperBound
                continue
            }
            if isEscapedDollar(at: currentIndex, in: text) {
                currentIndex = text.index(currentIndex, offsetBy: 2)
                continue
            }
            currentIndex = text.index(after: currentIndex)
        }

        return spans
    }

    private static func isEscapedDollar(at index: String.Index, in text: String) -> Bool {
        guard text[index] == "\\" else { return false }
        let next = text.index(after: index)
        return next < text.endIndex && text[next] == "$"
    }

    private static func span(
        for match: Regex<(Substring, Substring)>.Match,
        style: MathSpan.Style,
        in text: String
    ) -> MathSpan {
        let lower = match.range.lowerBound.utf16Offset(in: text)
        let upper = match.range.upperBound.utf16Offset(in: text)
        return MathSpan(range: lower ..< upper, style: style, latex: String(match.output.1))
    }

    /// `Regex` is not `Sendable` (it is, in practice, an immutable compiled
    /// value safe to share for concurrent reads — there is no mutation after
    /// construction); `nonisolated(unsafe)` avoids recompiling either literal
    /// on every `scan(_:)` call, which the sub-millisecond-per-block budget
    /// in epic-19-implementation.md §11 assumes.
    /// Verbatim copy of Textual's `PatternTokenizer.Pattern.mathBlock`.
    /// A display span never crosses a blank line: Preview slices per block, so `$$ … <blank> … $$` can never pair
    /// there, and Export must agree instead of swallowing the paragraphs between two stray `$$`.
    private nonisolated(unsafe) static let displayPattern =
        /(?s)\$\$((?:(?!(?:\r\n|\n|\r)[ \t]*(?:\r\n|\n|\r)).)+?)\$\$/
    /// Textual's `PatternTokenizer.Pattern.mathInline`, plus `\r` in the excluded set so an
    /// inline span stops at a CRLF/CR line break exactly as it does at `\n`.
    private nonisolated(unsafe) static let inlinePattern = /\$(?!\$)((?:\\\$|[^$\n\r])+)\$/
}

struct MathSpanScannerEquivalenceTests {
    private struct Generator: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return state
        }
    }

    @Test func theUTF16ScannerAgreesWithTheCharacterScannerOnPlainText() {
        let alphabet = ["$", "$", "$", "\\", "a", "b", " ", "\t", "\n", "\r", "\r\n", "é", "x^2"]
        var random = Generator(state: 42)
        for _ in 0 ..< 30000 {
            let length = Int.random(in: 0 ... 14, using: &random)
            let text = (0 ..< length).map { _ in alphabet.randomElement(using: &random) ?? "" }.joined()
            #expect(
                MathSpanScanner.scan(text) == ReferenceMathScanner.scan(text),
                "diverged on \(text.debugDescription)"
            )
        }
    }

    /// Review pass 6: a closing `$` followed by a grapheme-extending scalar was invisible to the Character scanner,
    /// so the span swallowed the prose after it.
    @Test(arguments: ["\u{200C}", "\u{200D}", "\u{FE0F}", "\u{0301}", "\u{1F3FD}"])
    func aDelimiterGluedToAnExtendingScalarStillPairsCorrectly(_ extender: String) {
        let text = "a $x$\(extender) and $y$ c"

        let latex = MathSpanScanner.scan(text).map(\.latex)

        #expect(latex == ["x", "y"])
    }

    @Test func aSentinelGluedToAnExtendingScalarIsStillSubstituted() {
        let text = "$x$\u{200C}ها"

        #expect(MathSpanScanner.scan(text).map(\.range) == [0 ..< 3])
    }
}
