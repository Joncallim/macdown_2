import Contributions
import Foundation
import MarkdownEngine

/// Renders one equation's LaTeX to PNG bytes. Implemented in the app target
/// via SwiftUI's `ImageRenderer` (epic-19-implementation.md §6.2, §17 Slice
/// 2); injected so `MathContribution` and its tests never link SwiftUI/
/// AppKit, mirroring `TextFilterRunner`'s injected-`Limits` idiom and
/// `ExportService`'s injected parser/resource seams.
public typealias MathImageRendering = @Sendable (MathSpan, ExportMathRenderContext) async throws -> Data

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
    /// below): render it and contribute a self-contained `<img>` HTML
    /// fragment via `.html` representation, or — on failure — contribute
    /// nothing for that span and report an `.error` diagnostic, isolated
    /// from every other span in the same document
    /// (epic-19-implementation.md §4 invariant 2, §9). A thrown
    /// `CancellationError` propagates immediately, abandoning remaining
    /// spans, matching `ContributionRegistry.run`'s own cancellation
    /// convention (epic-14-implementation.md §6.1).
    public func run(
        document: MarkdownDocument,
        sourceText: String,
        sourceGeneration: UInt
    ) async throws -> [ContributionResult] {
        let exclusions = Self.excludedRanges(in: document)
        var results: [ContributionResult] = []
        for span in MathSpanScanner.scan(sourceText) where !exclusions.contains(where: { $0.overlaps(span.range) }) {
            try Task.checkCancellation()
            do {
                let pngData = try await renderer(span, context)
                results.append(ContributionResult(
                    contributionID: id,
                    content: ContributionContent(
                        sourceRange: span.range,
                        placement: span.style == .inline ? .inline : .block,
                        representation: .html(Self.imgTag(pngData: pngData, alt: span.latex))
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

    /// UTF-16 ranges of `document`'s top-level code blocks and raw HTML
    /// blocks — a `$`-looking pattern inside one is never treated as math.
    /// Found during this epic's own adversarial review: `MathSpanScanner`
    /// operates on raw text with no block-structure awareness, unlike
    /// Textual's real `.math` extension (`PatternProcessor.expand` skips
    /// every `isPreformatted` run before trying its patterns, confirmed by
    /// reading its checked-out source) — without this check, a code
    /// sample containing coincidental `$...$`-shaped text (a shell
    /// variable, a literal LaTeX example, currency in a comment) could be
    /// silently spliced into the exported document as a rendered equation
    /// image, replacing the author's literal code text. Top-level only,
    /// matching `TOCContribution`'s own precedent
    /// (epic-14-implementation.md §6.2) — a code fence nested inside a
    /// list item or block quote is a narrower, documented residual risk
    /// (epic-19-implementation.md §18), not covered here.
    static func excludedRanges(in document: MarkdownDocument) -> [Range<Int>] {
        document.blocks.compactMap { block in
            switch block.kind {
            case .codeBlock, .htmlBlock:
                let nsRange = document.sourceMap.utf16Range(ofLines: block.lineRange)
                return nsRange.location ..< (nsRange.location + nsRange.length)
            default:
                return nil
            }
        }
    }

    /// Builds a self-contained `<img>` tag embedding `pngData` as a `data:`
    /// URI, with `alt` set to the original LaTeX source
    /// (epic-19-implementation.md §12). `alt`'s only variable content is
    /// `span.latex`; the base64 payload is bytes MacDown 2 itself rendered —
    /// neither is ever concatenated unescaped into HTML structure
    /// (epic-19-implementation.md §10).
    static func imgTag(pngData: Data, alt: String) -> String {
        let base64 = pngData.base64EncodedString()
        return "<img src=\"data:image/png;base64,\(base64)\" alt=\"\(htmlAttributeEscaped(alt))\">"
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
