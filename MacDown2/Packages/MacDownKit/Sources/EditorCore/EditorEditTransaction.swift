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
    /// A transaction with overlapping replacements is a programmer error:
    /// `precondition` traps immediately, in both Debug and Release builds
    /// (Swift only compiles it out under `-Ounchecked`, which this codebase
    /// does not build with). The `guard ... else { break }` immediately
    /// below is defense-in-depth for that unchecked configuration only — it
    /// stops applying a subset of replacements that could otherwise corrupt
    /// text by operating on stale offsets, "failing closed" the same way
    /// this codebase already does for other malformed input (e.g.
    /// `FileStore`'s decode failures) — not a distinct Release-mode path.
    func apply(_ transaction: EditorEditTransaction) {
        guard !transaction.replacements.isEmpty else { return }
        let ordered = transaction.replacements.sorted { $0.range.location > $1.range.location }

        var applied: [TextReplacement] = []
        var previousStart = Int.max
        for replacement in ordered {
            let end = replacement.range.location + replacement.range.length
            precondition(end <= previousStart, "EditorEditTransaction replacements must be non-overlapping")
            guard end <= previousStart else { break }
            applied.append(replacement)
            previousStart = replacement.range.location
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
