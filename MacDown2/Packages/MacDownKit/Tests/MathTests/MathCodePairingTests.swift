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
