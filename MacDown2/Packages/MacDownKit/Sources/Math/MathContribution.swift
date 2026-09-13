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

    /// For each `MathSpan` in `sourceText`: render it and contribute a
    /// self-contained `<img>` HTML fragment via `.html` representation, or —
    /// on failure — contribute nothing for that span and report an
    /// `.error` diagnostic, isolated from every other span in the same
    /// document (epic-19-implementation.md §4 invariant 2, §9). A thrown
    /// `CancellationError` propagates immediately, abandoning remaining
    /// spans, matching `ContributionRegistry.run`'s own cancellation
    /// convention (epic-14-implementation.md §6.1).
    public func run(
        document _: MarkdownDocument,
        sourceText: String,
        sourceGeneration: UInt
    ) async throws -> [ContributionResult] {
        var results: [ContributionResult] = []
        for span in MathSpanScanner.scan(sourceText) {
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
