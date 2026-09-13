import Contributions
import Foundation
import MarkdownEngine

/// Renders one equation's LaTeX to a PNG plus its logical size. Implemented
/// in the app target via SwiftUI's `ImageRenderer`
/// (epic-19-implementation.md §6.2, §17 Slice 2); injected so
/// `MathContribution` and its tests never link SwiftUI/AppKit, mirroring
/// `TextFilterRunner`'s injected-`Limits` idiom and `ExportService`'s
/// injected parser/resource seams.
public typealias MathImageRendering = @Sendable (MathSpan, ExportMathRenderContext) async throws -> RenderedMathImage

/// E19's Export-side producer, matching `TOCContribution`'s exact shape
/// (epic-14-implementation.md §6.2) and registered alongside it for Export
/// only — never for Preview (epic-19-implementation.md §4 invariant 5, §6.3):
/// Preview's math rendering goes through `Textual`'s own `.math` syntax
/// extension directly on each block's literal source text, not through
/// `ContributionRegistry`.
public struct MathContribution: Contributing {
    public let id = "math"

    private let context: ExportMathRenderContext
    private let renderer: MathImageRendering

    public init(context: ExportMathRenderContext, renderer: @escaping MathImageRendering) {
        self.context = context
        self.renderer = renderer
    }

    /// For each `MathSpan` in `sourceText`, EXCLUDING any span inside a
    /// top-level code block or raw HTML block (`excludedRanges(in:)`
    /// below) or an inline code span anywhere (`InlineCodeSpanScanner`,
    /// `Math` target): render it and contribute a self-contained `<img>`
    /// HTML fragment via `.html` representation, or — on failure —
    /// contribute nothing for that span and report an `.error` diagnostic,
    /// isolated from every other span in the same document
    /// (epic-19-implementation.md §4 invariant 2, §9). A thrown
    /// `CancellationError` propagates immediately, abandoning remaining
    /// spans, matching `ContributionRegistry.run`'s own cancellation
    /// convention (epic-14-implementation.md §6.1).
    public func run(
        document: MarkdownDocument,
        sourceText: String,
        sourceGeneration: UInt
    ) async throws -> [ContributionResult] {
        let exclusions = Self.excludedRanges(in: document) + InlineCodeSpanScanner.ranges(in: sourceText)
        var results: [ContributionResult] = []
        for span in MathSpanScanner.scan(sourceText) where !exclusions.contains(where: { $0.overlaps(span.range) }) {
            try Task.checkCancellation()
            do {
                let image = try await renderer(span, context)
                results.append(ContributionResult(
                    contributionID: id,
                    content: ContributionContent(
                        sourceRange: span.range,
                        placement: span.style == .inline ? .inline : .block,
                        representation: .html(Self.imgTag(image: image, alt: span.latex))
                    ),
                    sourceGeneration: sourceGeneration
                ))
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                results.append(ContributionResult(
                    contributionID: id,
                    content: nil,
                    sourceGeneration: sourceGeneration,
                    diagnostics: [
                        ContributionDiagnostic(
                            severity: .error,
                            message: "equation could not be typeset: \(span.latex)"
                        ),
                    ]
                ))
            }
        }
        return results
    }

    /// UTF-16 ranges of every code block and raw HTML block in `document`,
    /// AT ANY NESTING DEPTH — a `$`-looking pattern inside one is never
    /// treated as math. Found during this epic's own adversarial review:
    /// `MathSpanScanner` operates on raw text with no block-structure
    /// awareness, unlike Textual's real `.math` extension
    /// (`PatternProcessor.expand` skips every `isPreformatted` run before
    /// trying its patterns, confirmed by reading its checked-out source) —
    /// without this check, a code sample containing coincidental
    /// `$...$`-shaped text (a shell variable, a literal LaTeX example,
    /// currency in a comment) could be silently spliced into the exported
    /// document as a rendered equation image, replacing the author's
    /// literal code text.
    ///
    /// Recurses into `block.children` rather than scanning only
    /// `document.blocks` (top-level siblings): a fenced code block nested
    /// inside a list item or block quote is a CHILD of that block in
    /// `MarkdownBlock`'s tree (`ParseEngine`'s `BlockConverter`), not a
    /// top-level sibling, so a shallow scan never sees it. This was
    /// originally scoped to top-level only, matching `TOCContribution`'s
    /// own precedent (epic-14-implementation.md §6.2) and documented as a
    /// residual risk (epic-19-implementation.md §18/§20). Reconciling that
    /// residual risk against the real `ParseEngine` pipeline (rather than
    /// leaving it as an unverified assertion) proved it is not a benign
    /// "fails closed" gap: a nested fenced code block containing an
    /// internal blank line defeats `InlineCodeSpanScanner`'s accidental,
    /// incidental protection (its own "does not cross a blank line" rule),
    /// which otherwise happened to catch the common single-paragraph case
    /// by coincidence — so math-like text after that blank line was
    /// spliced into the export exactly like the fixed inline-code and
    /// escaped-dollar defects. `TOCContribution` is a separate
    /// implementation with its own ownership boundary; this fix is scoped
    /// to `Math`, matching this epic's own module ownership (§5).
    static func excludedRanges(in document: MarkdownDocument) -> [Range<Int>] {
        document.blocks.flatMap { excludedRanges(in: $0, sourceMap: document.sourceMap) }
    }

    private static func excludedRanges(in block: MarkdownBlock, sourceMap: SourceMap) -> [Range<Int>] {
        switch block.kind {
        case .codeBlock, .htmlBlock:
            let nsRange = sourceMap.utf16Range(ofLines: block.lineRange)
            return [nsRange.location ..< (nsRange.location + nsRange.length)]
        default:
            return block.children.flatMap { excludedRanges(in: $0, sourceMap: sourceMap) }
        }
    }

    /// Builds a self-contained `<img>` tag embedding `image.pngData` as a
    /// `data:` URI, with `alt` set to the original LaTeX source
    /// (epic-19-implementation.md §12). `alt`'s only variable content is
    /// `span.latex`; the base64 payload is bytes MacDown 2 itself rendered —
    /// neither is ever concatenated unescaped into HTML structure
    /// (epic-19-implementation.md §10).
    ///
    /// Explicit `width`/`height` (rounded to the nearest whole CSS pixel,
    /// matching the HTML attribute's own integer expectation) come from
    /// `image`'s LOGICAL size, not its pixel dimensions — adversarial-review
    /// finding: without these, a browser/WKWebView has no DPI hint and
    /// renders the PNG at its native pixel size, `pixelScale`× too large
    /// (`RenderedMathImage`'s own doc comment).
    static func imgTag(image: RenderedMathImage, alt: String) -> String {
        let base64 = image.pngData.base64EncodedString()
        let width = Int(image.logicalWidth.rounded())
        let height = Int(image.logicalHeight.rounded())
        return "<img src=\"data:image/png;base64,\(base64)\" width=\"\(width)\" height=\"\(height)\" " +
            "alt=\"\(htmlAttributeEscaped(alt))\">"
    }

    private static func htmlAttributeEscaped(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count)
        for character in text {
            switch character {
            case "&": result += "&amp;"
            case "\"": result += "&quot;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            default: result.append(character)
            }
        }
        return result
    }
}
