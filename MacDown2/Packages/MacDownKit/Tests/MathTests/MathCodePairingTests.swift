import Contributions
import Foundation
import MarkdownEngine
@testable import Math
import Testing

/// Review pass 5: `$` delimiters inside code were filtered out only AFTER pairing, so one in a code span flipped the
/// pairing of every later delimiter, and `$$` paired across blank lines, swallowing the paragraphs between.
struct MathCodePairingTests {
    private static let context = ExportMathRenderContext(
        foregroundRed: 0, foregroundGreen: 0, foregroundBlue: 0, pixelScale: 2
    )

    private func typeset(_ text: String) async throws -> [String] {
        let document = try await ParseEngine().parse(text, revision: 1)
        let recorder = Recorder()
        let contribution = MathContribution(context: Self.context) { span, _ in
            await recorder.record(span.latex)
            return RenderedMathImage(pngData: Data(), logicalWidth: 1, logicalHeight: 1)
        }
        _ = try await contribution.run(document: document, sourceText: text, sourceGeneration: 1)
        return await recorder.values
    }

    @Test(arguments: [
        ("Set `$PATH` then compute $x$ and $y$.", ["x", "y"]),
        ("Use `$$` for display math, like $$x$$ and $$y$$.", ["x", "y"]),
        ("```sh\necho $$\n```\n\nThen $$x$$ and $$y$$.", ["x", "y"]),
    ])
    func aDollarInCodeDoesNotFlipThePairingOfRealEquations(_ text: String, _ expected: [String]) async throws {
        #expect(try await typeset(text) == expected)
    }

    @Test func displayMathNeverPairsAcrossABlankLine() async throws {
        let text = "The hotel was $$ for sure.\n\nThe food was also $$ but fine.\n\nLast paragraph.\n"

        #expect(try await typeset(text).isEmpty)
    }

    @Test func displayMathStillSpansSingleNewlines() {
        let spans = MathSpanScanner.scan("$$\na\nb\n$$")

        #expect(spans.count == 1)
    }

    @Test func displayMathDoesNotCrossABlankLineWithCRLFOrSpaces() {
        #expect(MathSpanScanner.scan("$$a\r\n\r\nb$$").isEmpty)
        #expect(MathSpanScanner.scan("$$a\n  \nb$$").isEmpty)
    }
}

private actor Recorder {
    private(set) var values: [String] = []
    func record(_ latex: String) {
        values.append(latex)
    }
}

/// Review pass 6: continuation lines of display math inside a block quote carry the quote's `>` markers, which
/// reached the renderer as part of the equation.
struct MathQuoteMarkerTests {
    @Test func markersAreStrippedFromContinuationLinesOnly() {
        #expect(MathContainerPrefix.strippingQuoteMarkers(from: "\n> x^2\n> ") == "\nx^2\n")
        #expect(MathContainerPrefix.strippingQuoteMarkers(from: " a\n>> b\n > c") == " a\nb\nc")
        #expect(MathContainerPrefix.strippingQuoteMarkers(from: "a > b") == "a > b")
        #expect(MathContainerPrefix.strippingQuoteMarkers(from: "x\r\n> y") == "x\ny")
    }

    @Test func aSpanIsInAQuoteOnlyWhenItsOwnLineHasAMarker() {
        let text = "> $$\n> x\n> $$\n\nplain $$y$$"
        let units = Array(text.utf16)
        let first = (text as NSString).range(of: "$$").location
        let second = (text as NSString).range(of: "$$y$$").location

        #expect(MathContainerPrefix.isInsideQuote(spanStart: first, character: { units[$0] }))
        #expect(!MathContainerPrefix.isInsideQuote(spanStart: second, character: { units[$0] }))
    }

    @Test func exportRendersQuotedDisplayMathWithoutTheMarkers() async throws {
        let text = "> $$\n> x^2\n> $$\n"
        let document = try await ParseEngine().parse(text, revision: 1)
        let recorder = Recorder()
        let contribution = MathContribution(
            context: ExportMathRenderContext(foregroundRed: 0, foregroundGreen: 0, foregroundBlue: 0, pixelScale: 2)
        ) { span, _ in
            await recorder.record(span.latex)
            return RenderedMathImage(pngData: Data(), logicalWidth: 1, logicalHeight: 1)
        }

        _ = try await contribution.run(document: document, sourceText: text, sourceGeneration: 1)

        #expect(await recorder.values == ["\nx^2\n"])
    }
}

/// Review pass 7: LaTeX in the `alt` attribute was escaped per `Character`, so a `"` followed by a combining mark
/// or ZWNJ was not escaped and the author could add attributes (`style`, a remote `srcset`) to the exported `<img>`.
struct MathAltEscapingTests {
    @Test(arguments: ["\u{0301}", "\u{200C}", "\u{200D}", "\u{FE0F}"])
    func aQuoteFollowedByAnExtendingScalarCannotCloseTheAltAttribute(_ extender: String) {
        let image = RenderedMathImage(pngData: Data(), logicalWidth: 1, logicalHeight: 1)

        let html = MathContribution.imgTag(image: image, alt: "a\"\(extender) style=\"position:fixed\" q")

        #expect(html.contains("alt=\"a&quot;\(extender) style=&quot;position:fixed&quot; q\""))
    }
}
