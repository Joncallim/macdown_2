import Foundation

/// Turns renderer-neutral derived-content contributions into the two things the
/// cmark bridge needs: a body text whose contributed ranges are replaced by
/// deterministic sentinels, and the custom-node specs that turn those sentinels
/// back into derived HTML.
///
/// Failure semantics (issue #49): a failed, stale, out-of-bounds, empty, or
/// overlapping contribution is *not* spliced — its authored Markdown remains in
/// the body and is parsed normally — and an error diagnostic records the reason.
/// Diagnostics a contribution carries are always forwarded, whether or not it is
/// placed, so nothing a renderer reported is silently dropped. There is exactly
/// one pass and no re-parse, so the fallback is bounded by construction.
enum DerivedContentComposer {
    struct Result {
        let splicedBody: String
        let customNodes: [CMarkGFM.CustomNodeSpec]
        let diagnostics: [ExportDiagnostic]
    }

    /// One accepted replacement: a body-relative UTF-16 range and the sentinel
    /// that stands in for it until the cmark tree walk substitutes it back.
    struct Splice {
        let range: Range<Int>
        let sentinel: String
        let isBlock: Bool
    }

    /// Immutable inputs shared by every contribution validation in one compose
    /// pass. Grouped so the per-contribution validator does not re-carry four
    /// fixed parameters, and so the O(n) UTF-16 length is measured once rather
    /// than once per contribution.
    struct ValidationContext {
        let bodyUTF16Length: Int
        let bodyStartOffset: Int
        let sourceUTF16Length: Int
        let sourceGeneration: UInt
        let sentinelSuffix: String
        let budget: ExportResourceBudget
    }

    static func compose(
        bodyText: String,
        bodyStartOffset: Int,
        sourceUTF16Length: Int,
        contributions: [ExportDerivedContribution],
        sourceGeneration: UInt,
        budget: ExportResourceBudget = .standard
    ) -> Result {
        guard !contributions.isEmpty else {
            return Result(splicedBody: bodyText, customNodes: [], diagnostics: [])
        }

        let context = ValidationContext(
            bodyUTF16Length: bodyText.utf16.count,
            bodyStartOffset: bodyStartOffset,
            sourceUTF16Length: sourceUTF16Length,
            sourceGeneration: sourceGeneration,
            // One scan of the body picks a sentinel family that cannot collide
            // with authored text, rather than re-scanning per contribution.
            sentinelSuffix: sentinelSuffix(notCollidingWith: bodyText),
            budget: budget
        )

        let sorted = contributions.sorted { $0.sourceRange.lowerBound < $1.sourceRange.lowerBound }
        var plan = DerivedContentPlan()
        for (index, contribution) in sorted.enumerated() {
            plan.consider(contribution, index: index, context: context)
        }

        return Result(
            splicedBody: splice(plan.splices, into: bodyText),
            customNodes: plan.customNodes,
            diagnostics: plan.diagnostics
        )
    }

    private static let blockSentinelBase = "E12BLOCK"
    private static let inlineSentinelBase = "E12INLINE"

    /// The shortest suffix that makes *both* sentinel families absent from the
    /// authored body. Because `E12BLOCK` is a prefix of every block sentinel,
    /// one containment check per family clears every sentinel that follows.
    private static func sentinelSuffix(notCollidingWith bodyText: String) -> String {
        var suffix = ""
        while bodyText.contains(blockSentinelBase + suffix) || bodyText.contains(inlineSentinelBase + suffix) {
            suffix += "_"
        }
        return suffix
    }

    /// `<family><suffix><index>Z`. The trailing `Z` terminates the digit run so
    /// no sentinel is ever a prefix — or a substring — of another (`…1Z` cannot
    /// be found inside `…10Z`).
    static func makeSentinel(isBlock: Bool, index: Int, suffix: String) -> String {
        let base = isBlock ? blockSentinelBase : inlineSentinelBase
        return "\(base)\(suffix)\(index)Z"
    }

    /// Builds the body with each valid range replaced by its sentinel. Block
    /// sentinels are surrounded by blank lines so they form a standalone
    /// paragraph; inline sentinels replace the range in place.
    ///
    /// The body is materialised as UTF-16 code units once. Converting each
    /// offset with `String.Index(utf16Offset:in:)` instead would walk the string
    /// from the start for every boundary, which is quadratic in the number of
    /// contributions.
    private static func splice(_ splices: [Splice], into bodyText: String) -> String {
        guard !splices.isEmpty else { return bodyText }

        let units = Array(bodyText.utf16)
        var result = ""
        result.reserveCapacity(bodyText.utf8.count + splices.count * 24)
        var cursor = 0

        func appendUnits(upTo end: Int) {
            let clampedEnd = min(max(end, cursor), units.count)
            guard cursor < clampedEnd else { return }
            result += String(decoding: units[cursor ..< clampedEnd], as: UTF16.self)
            cursor = clampedEnd
        }

        for entry in splices {
            appendUnits(upTo: entry.range.lowerBound)
            result += entry.isBlock ? "\n\n\(entry.sentinel)\n\n" : entry.sentinel
            // Jump past the replaced range; its characters are not emitted.
            cursor = min(max(entry.range.upperBound, cursor), units.count)
        }
        appendUnits(upTo: units.count)

        return result
    }
}

/// The running decision state of one compose pass: what has been accepted so
/// far, and what has been reported.
private struct DerivedContentPlan {
    var diagnostics: [ExportDiagnostic] = []
    var customNodes: [CMarkGFM.CustomNodeSpec] = []
    var splices: [DerivedContentComposer.Splice] = []

    private var previousBodyUpperBound = 0
    private var placedCount = 0
    private var aggregateDerivedBytes = 0

    mutating func consider(
        _ contribution: ExportDerivedContribution,
        index: Int,
        context: DerivedContentComposer.ValidationContext
    ) {
        // The renderer's own observations are forwarded either way; only an
        // error-level one blocks placement.
        diagnostics.append(contentsOf: contribution.diagnostics)

        let range = contribution.sourceRange
        let bodyRange = (range.lowerBound - context.bodyStartOffset) ..< (range.upperBound - context.bodyStartOffset)

        if let failure = rejection(for: contribution, bodyRange: bodyRange, context: context) {
            diagnostics.append(ExportDiagnostic(severity: .error, message: failure))
            return
        }

        let isBlock = contribution.placement == .block
        let sentinel = DerivedContentComposer.makeSentinel(
            isBlock: isBlock,
            index: index,
            suffix: context.sentinelSuffix
        )
        customNodes.append(CMarkGFM.CustomNodeSpec(sentinel: sentinel, isBlock: isBlock, html: contribution.html))
        splices.append(DerivedContentComposer.Splice(range: bodyRange, sentinel: sentinel, isBlock: isBlock))
        previousBodyUpperBound = bodyRange.upperBound
        placedCount += 1
        aggregateDerivedBytes += contribution.html.utf8.count
    }

    /// Why this contribution cannot be placed, or `nil` when it can be.
    private func rejection(
        for contribution: ExportDerivedContribution,
        bodyRange: Range<Int>,
        context: DerivedContentComposer.ValidationContext
    ) -> String? {
        if contribution.diagnostics.contains(where: { $0.severity == .error }) {
            return "derived contribution failed in its renderer; authored source preserved"
        }
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
        if bodyRange.upperBound > context.bodyUTF16Length {
            return "derived contribution range exceeds the body; authored source preserved"
        }
        if bodyRange.lowerBound < previousBodyUpperBound {
            return "derived contribution range overlaps another contribution; authored source preserved"
        }
        if contribution.html.isEmpty {
            return "derived contribution produced no HTML; authored source preserved"
        }
        return budgetRejection(for: contribution, budget: context.budget)
    }

    /// A budget violation rejects that one contribution and preserves its
    /// authored source; it never fails the export.
    private func budgetRejection(
        for contribution: ExportDerivedContribution,
        budget: ExportResourceBudget
    ) -> String? {
        guard placedCount < budget.maxDerivedFragmentCount else {
            return "derived contribution exceeds the \(budget.maxDerivedFragmentCount)-fragment "
                + "export limit; authored source preserved"
        }
        let (total, overflowed) = aggregateDerivedBytes.addingReportingOverflow(contribution.html.utf8.count)
        guard !overflowed, total <= budget.maxAggregateDerivedHTMLBytes else {
            let limit = ExportResourceBudget.describe(bytes: budget.maxAggregateDerivedHTMLBytes)
            return "derived contribution exceeds the \(limit) total derived HTML limit; authored source preserved"
        }
        return nil
    }
}
