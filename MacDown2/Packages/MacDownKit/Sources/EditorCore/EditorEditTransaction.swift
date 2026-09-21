import AppKit
import Foundation

/// One disjoint text replacement, expressed in the *pre-edit* text's UTF-16
/// coordinates.
public struct TextReplacement: Sendable, Equatable {
    public let range: NSRange
    public let replacementText: String

    public init(range: NSRange, replacementText: String) {
        self.range = range
        self.replacementText = replacementText
    }
}

/// One disjoint multi-range text replacement applied as exactly one native
/// edit sequence, one undo group, one document-change publication —
/// generalizing the three existing hand-rolled one-edit patterns
/// (`applyDocumentReplacement`, `applyExternalReplacement`,
/// `applyAssistOutcome`) to N simultaneous, non-overlapping ranges. N == 1
/// is a valid, and encouraged, use of this type — it is the new general
/// case, not a multi-cursor-only special case.
public struct EditorEditTransaction: Sendable {
    /// Must be non-overlapping. Construction does not itself sort/validate
    /// (callers already produce these in a known order from an
    /// `EditorSelectionSet`); `EditorTextSystem.apply(_:)` is the one place
    /// that enforces the highest-to-lowest application order and the
    /// non-overlap invariant.
    public let replacements: [TextReplacement]
    public let undoActionName: String?

    /// The `EditorSelectionSet` to install after applying, expressed in
    /// *post-edit* offsets. The caller computes this; the transaction does
    /// not guess caret placement (mirroring `applyExternalReplacement`'s
    /// existing "caller passes explicit range" discipline).
    public let resultingSelection: EditorSelectionSet?

    public init(
        replacements: [TextReplacement],
        undoActionName: String? = nil,
        resultingSelection: EditorSelectionSet? = nil
    ) {
        self.replacements = replacements
        self.undoActionName = undoActionName
        self.resultingSelection = resultingSelection
    }

    /// Given `replacements` sorted highest-offset-to-lowest, returns the
    /// longest safe-to-apply prefix — dropping everything from the first
    /// out-of-bounds or overlapping entry onward — plus whether anything
    /// was dropped. Pure and build-configuration-independent: unlike
    /// `EditorTextSystem.apply(_:)`'s own `assertionFailure` diagnostic
    /// (Debug-fatal, a no-op in Release, and therefore untestable in a
    /// normal Debug test run without crashing the test process), this
    /// validation logic runs unconditionally in every configuration, so the
    /// "malformed input still yields a safe, non-corrupting result" claim
    /// is directly unit-testable rather than merely asserted in a comment.
    static func validating(
        orderedDescending replacements: [TextReplacement],
        documentLength: Int
    ) -> (applied: [TextReplacement], hadInvalidReplacement: Bool) {
        var applied: [TextReplacement] = []
        var previousStart = Int.max
        var hadInvalidReplacement = false
        for replacement in replacements {
            let location = replacement.range.location
            let end = location + replacement.range.length
            let isInBounds = location >= 0 && end <= documentLength
            let isNonOverlapping = end <= previousStart
            guard isInBounds, isNonOverlapping else {
                hadInvalidReplacement = true
                break
            }
            applied.append(replacement)
            previousStart = location
        }
        return (applied, hadInvalidReplacement)
    }
}

public extension EditorTextSystem {
    /// Applies every replacement highest-offset-to-lowest (so an earlier
    /// offset's meaning is never invalidated by a later replacement already
    /// having shifted the text), inside one `breakUndoCoalescing()`/
    /// `setActionName`/`breakUndoCoalescing()` bracket, with
    /// `isPerformingEditingAssist` raised for the whole transaction —
    /// exactly `applyExternalReplacement`'s existing shape, generalized to
    /// N ranges.
    ///
    /// A transaction with an out-of-bounds or overlapping replacement is a
    /// programmer error: `assertionFailure` traps immediately in Debug
    /// builds (loud, for development), but — unlike `precondition`, which
    /// traps in Release too — is a no-op in a standard optimized Release
    /// build, so execution falls through to applying only
    /// `EditorEditTransaction.validating(orderedDescending:documentLength:)`'s
    /// already-filtered safe prefix instead of crashing the shipped app.
    /// "Failing closed" this way, rather than terminating, matches this
    /// codebase's established discipline for other malformed input (e.g.
    /// `FileStore`'s decode failures).
    func apply(_ transaction: EditorEditTransaction) {
        guard !transaction.replacements.isEmpty else { return }
        let ordered = transaction.replacements.sorted { $0.range.location > $1.range.location }
        let documentLength = textView.textStorage?.length ?? 0
        let (applied, hadInvalidReplacement) = EditorEditTransaction.validating(
            orderedDescending: ordered,
            documentLength: documentLength
        )
        if hadInvalidReplacement {
            assertionFailure("EditorEditTransaction contains an out-of-bounds or overlapping replacement")
        }
        guard !applied.isEmpty else { return }

        textView.breakUndoCoalescing()
        isPerformingEditingAssist = true
        defer { isPerformingEditingAssist = false }

        // Each `insertText` call independently posts AppKit's text-change
        // notification; without suppression `textDidChange` would publish
        // the (still mid-transaction) binding value once per range instead
        // of once for the whole command. Suppress every call but the last.
        isApplyingMultiRangeTransaction = applied.count > 1
        defer { isApplyingMultiRangeTransaction = false }
        for (index, replacement) in applied.enumerated() {
            if index == applied.count - 1 {
                isApplyingMultiRangeTransaction = false
            }
            textView.insertText(replacement.replacementText, replacementRange: replacement.range)
        }

        if let resultingSelection = transaction.resultingSelection {
            textView.selectedRanges = resultingSelection.asNSValueArray
        }
        if let undoActionName = transaction.undoActionName, undoManager.canUndo {
            undoManager.setActionName(undoActionName)
        }
        textView.breakUndoCoalescing()
    }
}
