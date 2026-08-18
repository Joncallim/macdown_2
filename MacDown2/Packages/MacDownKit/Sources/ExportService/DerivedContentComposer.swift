import Foundation

/// Turns renderer-neutral derived-content contributions into the two things the
/// cmark bridge needs: a body text whose contributed ranges are replaced by
/// deterministic sentinels, and the custom-node specs that turn those sentinels
/// back into derived HTML.
///
/// Failure semantics (issue #49): a stale, out-of-bounds, empty, or overlapping
/// contribution is *not* spliced — its authored Markdown remains in the body and
/// is parsed normally — and an error diagnostic records the reason. There is
/// exactly one pass and no re-parse, so the fallback is bounded by construction.
enum DerivedContentComposer {
    struct Result {
        let splicedBody: String
        let customNodes: [CMarkGFM.CustomNodeSpec]
        let diagnostics: [ExportDiagnostic]
    }

    /// Immutable inputs shared by every contribution validation in one compose
    /// pass. Grouped so the per-contribution validator does not re-carry four
    /// fixed parameters.
    private struct ValidationContext {
        let bodyText: String
        let bodyStartOffset: Int
        let sourceUTF16Length: Int
        let sourceGeneration: UInt
    }

    static func compose(
        bodyText: String,
        bodyStartOffset: Int,
        sourceUTF16Length: Int,
        contributions: [ExportDerivedContribution],
        sourceGeneration: UInt
    ) -> Result {
        let sorted = contributions.sorted { $0.sourceRange.lowerBound < $1.sourceRange.lowerBound }

        var diagnostics: [ExportDiagnostic] = []
        var customNodes: [CMarkGFM.CustomNodeSpec] = []
        var usedSentinels: Set<String> = []
        // Body-relative replacement ranges paired with their sentinel, in
        // source order. Sorted by construction.
        var splices: [(range: Range<Int>, sentinel: String)] = []

        var previousBodyUpperBound = 0
        let context = ValidationContext(
            bodyText: bodyText,
            bodyStartOffset: bodyStartOffset,
            sourceUTF16Length: sourceUTF16Length,
            sourceGeneration: sourceGeneration
        )
        for (index, contribution) in sorted.enumerated() {
            let range = contribution.sourceRange
            let bodyRange = (range.lowerBound - bodyStartOffset) ..< (range.upperBound - bodyStartOffset)

            if let failure = validationFailure(
                contribution: contribution,
                bodyRange: bodyRange,
                previousBodyUpperBound: previousBodyUpperBound,
                context: context
            ) {
                diagnostics.append(ExportDiagnostic(severity: .error, message: failure))
                continue
            }

            let sentinel = makeSentinel(
                isBlock: contribution.placement == .block,
                index: index,
                bodyText: bodyText,
                usedSentinels: &usedSentinels
            )
            customNodes.append(CMarkGFM.CustomNodeSpec(
                sentinel: sentinel,
                isBlock: contribution.placement == .block,
                html: contribution.html
            ))
            splices.append((bodyRange, sentinel))
            previousBodyUpperBound = bodyRange.upperBound
        }

        return Result(
            splicedBody: splice(sentinel: splices, into: bodyText),
            customNodes: customNodes,
            diagnostics: diagnostics
        )
    }

    /// Returns a failure message when the contribution must be rejected, or
    /// `nil` when it is accepted.
    private static func validationFailure(
        contribution: ExportDerivedContribution,
        bodyRange: Range<Int>,
        previousBodyUpperBound: Int,
        context: ValidationContext
    ) -> String? {
        if contribution.sourceGeneration != context.sourceGeneration {
            return "derived contribution is stale (source generation \(contribution.sourceGeneration) "
                + "!= \(context.sourceGeneration)); authored source preserved"
        }
        if contribution.sourceRange.lowerBound < context.bodyStartOffset
            || contribution.sourceRange.upperBound > context.sourceUTF16Length {
            return "derived contribution range \(contribution.sourceRange) is outside the document "
                + "body; authored source preserved"
        }
        if contribution.sourceRange.lowerBound >= contribution.sourceRange.upperBound {
            return "derived contribution range is empty; authored source preserved"
        }
        if bodyRange.upperBound > context.bodyText.utf16.count {
            return "derived contribution range exceeds the body; authored source preserved"
        }
        if bodyRange.lowerBound < previousBodyUpperBound {
            return "derived contribution range overlaps another contribution; authored source preserved"
        }
        return nil
    }

    private static func makeSentinel(
        isBlock: Bool,
        index: Int,
        bodyText: String,
        usedSentinels: inout Set<String>
    ) -> String {
        let base = isBlock ? "E12BLOCK" : "E12INLINE"
        var sentinel = "\(base)\(index)"
        while bodyText.contains(sentinel) || usedSentinels.contains(sentinel) {
            sentinel += "_"
        }
        usedSentinels.insert(sentinel)
        return sentinel
    }

    /// Builds the body with each valid range replaced by its sentinel. Block
    /// sentinels are surrounded by blank lines so they form a standalone
    /// paragraph; inline sentinels replace the range in place.
    private static func splice(sentinel splices: [(range: Range<Int>, sentinel: String)],
                               into bodyText: String) -> String {
        guard !splices.isEmpty else { return bodyText }

        var result = String.UnicodeScalarView()
        var cursor = 0

        func appendRange(_ range: Range<Int>) {
            guard range.lowerBound < range.upperBound else { return }
            let start = String.Index(utf16Offset: range.lowerBound, in: bodyText)
            let end = String.Index(utf16Offset: range.upperBound, in: bodyText)
            result.append(contentsOf: bodyText[start ..< end].unicodeScalars)
        }

        for (range, sentinel) in splices {
            appendRange(cursor ..< range.lowerBound)
            if sentinel.hasPrefix("E12BLOCK") {
                result.append(contentsOf: "\n\n\(sentinel)\n\n".unicodeScalars)
            } else {
                result.append(contentsOf: sentinel.unicodeScalars)
            }
            cursor = range.upperBound
        }
        appendRange(cursor ..< bodyText.utf16.count)

        return String(result)
    }
}
