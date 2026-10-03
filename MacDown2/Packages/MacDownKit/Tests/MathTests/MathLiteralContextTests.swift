import Contributions
import Foundation
import MarkdownEngine
@testable import Math
import Testing

/// `$…$` inside a URL, an HTML tag or front matter is literal text; typesetting it spliced
/// the math sentinel into `href`/`src`/`title` attributes of the exported HTML.
struct MathLiteralContextTests {
    private static let context = ExportMathRenderContext(
        foregroundRed: 0, foregroundGreen: 0, foregroundBlue: 0, pixelScale: 2
    )

    private func typesetLaTeX(in text: String) async throws -> [String] {
        let document = try await ParseEngine().parse(text, revision: 1)
        let contribution = MathContribution(context: Self.context) { _, _ in
            RenderedMathImage(pngData: Data(), logicalWidth: 1, logicalHeight: 1)
        }
        let results = try await contribution.run(document: document, sourceText: text, sourceGeneration: 1)
        return results.compactMap { result in
            guard case let .html(html) = result.content?.representation else { return nil }
            return html
        }
    }

    @Test(arguments: [
        "[price](https://example.com/?a=$x$)",
        "![x](https://e.com/a$b.png) and $c$ text",
        "[a]: https://example.com/?p=$5&q=$6\n\n[a]",
        "see www.example.com/$a$ now",
        "<https://example.com/$a$>",
        "<span title=\"$x$\">text</span>",
    ])
    func dollarsInUrlsAndTagsAreNotMath(_ text: String) async throws {
        let spans = try await typesetLaTeX(in: text)

        // Only the standalone "$c$" in the second input is real math.
        #expect(spans.count == (text.contains("$c$") ? 1 : 0))
    }

    @Test func realMathNextToALinkIsStillTypeset() async throws {
        let spans = try await typesetLaTeX(in: "[docs](https://example.com) show $E=mc^2$.")

        #expect(spans.count == 1)
    }

    @Test func mathAcrossAComparisonIsNotMistakenForATag() async throws {
        let spans = try await typesetLaTeX(in: "We have $a<b$ and $c>d$ here.")

        #expect(spans.count == 2)
    }

    @Test func mathInFrontMatterIsNotTypesetAndDoesNotPairWithBodyMath() async throws {
        let spans = try await typesetLaTeX(in: "---\nprice: $5 and $10\nnote: $$\n---\n\n$$E=mc^2$$\n")

        #expect(spans.count == 1)
    }
}
