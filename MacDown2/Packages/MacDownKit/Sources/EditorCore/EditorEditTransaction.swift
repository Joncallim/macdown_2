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
    /// `EditorSelectionSet`); `EditorTextSystem.apply(_:)` validates the
    /// whole set atomically via `EditorEditTransaction.validate(_:documentLength:)`
    /// before applying anything, and separately enforces the
    /// highest-to-lowest application order.
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

    /// Validates the ENTIRE set as one atomic unit: every replacement must
    /// have a non-negative location/length and fit within `documentLength`,
    /// and the set as a whole must be pairwise non-overlapping (touching is
    /// fine — two selections that merely share a boundary remain distinct,
    /// matching `EditorSelectionSet`'s own convention) with no two
    /// zero-length replacements at the exact same location (an
    /// unresolvable "duplicate simultaneous insert" ambiguity). Returns
    /// `true` only if every replacement is individually and jointly valid —
    /// there is no partial result, because a transaction represents one
    /// atomic user command: a malformed member invalidates the whole
    /// command, not just itself.
    ///
    /// Pure and build-configuration-independent: unlike
    /// `EditorTextSystem.apply(_:)`'s own `assertionFailure` diagnostic
    /// (Debug-fatal, a no-op in Release, and therefore untestable in a
    /// normal Debug test run without crashing the test process), this
    /// validation logic runs unconditionally in every configuration, so
    /// "malformed input mutates nothing" is directly unit-testable rather
    /// than merely asserted in a comment.
    static func validate(_ replacements: [TextReplacement], documentLength: Int) -> Bool {
        for replacement in replacements {
            guard isIndividuallyValid(replacement, documentLength: documentLength) else {
                return false
            }
        }
        // `zip(sorted, sorted.dropFirst())` naturally yields zero pairs for
        // an empty or single-element array — no index/range arithmetic, and
        // therefore no zero/one-element special case to get wrong (unlike
        // an earlier version of this function, which crashed on `1 ..< 0`
        // for an empty set).
        let sorted = replacements.sorted { $0.range.location < $1.range.location }
        for (previous, current) in zip(sorted, sorted.dropFirst()) {
            guard areDisjoint(previous, current) else {
                return false
            }
        }
        return true
    }

    /// Non-negative location/length, no `location + length` overflow, and
    /// the resulting end within `documentLength`.
    private static func isIndividuallyValid(_ replacement: TextReplacement, documentLength: Int) -> Bool {
        let location = replacement.range.location
        let length = replacement.range.length
        guard location >= 0, length >= 0 else { return false }
        let (end, overflowed) = location.addingReportingOverflow(length)
        guard !overflowed, end <= documentLength else { return false }
        return true
    }

    /// `previous`/`current` must already be sorted ascending by location.
    /// Touching (previous's end exactly equal to current's start) is
    /// allowed — two selections that merely share a boundary remain
    /// distinct, matching `EditorSelectionSet`'s own convention. Two
    /// zero-length replacements at the exact same location are rejected as
    /// an unresolvable "duplicate simultaneous insert" ambiguity, even
    /// though that case would otherwise read as "touching."
    private static func areDisjoint(_ previous: TextReplacement, _ current: TextReplacement) -> Bool {
        let previousEnd = previous.range.location + previous.range.length
        let isDuplicateZeroLength = current.range.length == 0
            && previous.range.length == 0
            && current.range.location == previous.range.location
        return current.range.location >= previousEnd && !isDuplicateZeroLength
    }

    /// For each replacement (ascending by pre-edit location), the
    /// zero-length caret range immediately after its own replacement text,
    /// adjusted for the cumulative length delta of every earlier
    /// (lower-offset) replacement — `apply(_:)` applies highest-offset-to-
    /// lowest, so a lower-offset replacement's own resulting position is
    /// never shifted by a higher one, but a HIGHER-offset caret's final
    /// position must account for every LOWER-offset replacement's own
    /// length change already having landed first. Two carets that converge
    /// on the same offset (e.g. two adjacent single-character deletes)
    /// collapse to one caret when passed through `EditorSelectionSet`'s own
    /// duplicate-caret merge rule — never a crash or a silently-dropped
    /// cursor. Used by any multi-range command (§7.2's multi-cursor typing
    /// and delete, Slice 3a) that wants "one caret per replacement,
    /// positioned where a human would expect after that edit" rather than
    /// hand-computing the offset arithmetic at each call site.
    static func resultingCaretRanges(for replacements: [TextReplacement]) -> [NSRange] {
        let sorted = replacements.sorted { $0.range.location < $1.range.location }
        var delta = 0
        return sorted.map { replacement in
            let shiftedLocation = replacement.range.location + delta
            let insertedLength = (replacement.replacementText as NSString).length
            delta += insertedLength - replacement.range.length
            return NSRange(location: shiftedLocation + insertedLength, length: 0)
        }
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
    /// A transaction is one atomic user command, so an invalid member
    /// (out-of-bounds, overlapping, or a duplicate zero-length edit at the
    /// same location) invalidates the WHOLE command, not just that one
    /// entry — this is a programmer error: `assertionFailure` traps
    /// immediately in Debug builds (loud, for development), but — unlike
    /// `precondition`, which traps in Release too — is a no-op in a
    /// standard optimized Release build, so execution falls through and
    /// returns having mutated nothing: no text change, no selection change,
    /// no undo entry, no publication. "Failing closed" this way, rather
    /// than terminating or partially applying, matches this codebase's
    /// established discipline for other malformed input (e.g.
    /// `FileStore`'s decode failures).
    func apply(_ transaction: EditorEditTransaction) {
        apply(transaction, reportsInvalidAsAssertionFailure: true)
    }

    /// The real implementation behind `apply(_:)`. `assertionFailure` traps
    /// as soon as it runs, so a Debug test that deliberately triggered it
    /// could never observe "and afterward nothing was mutated" in that same
    /// process — `swift test` builds Debug by default, where the trap fires
    /// immediately. `reportsInvalidAsAssertionFailure` exists
    /// solely as an `internal` (not `public`) testing seam so
    /// `EditorEditTransactionTests` can exercise the "reject the whole
    /// transaction, mutate nothing" contract against a REAL mounted
    /// `NSTextView` without that trap — every real call site, in every app
    /// build configuration, goes through `apply(_:)` above and always gets
    /// `true`; this parameter can never be set to `false` from outside this
    /// module, so the production Debug-fatal contract is not weakened.
    internal func apply(_ transaction: EditorEditTransaction, reportsInvalidAsAssertionFailure: Bool) {
        guard !transaction.replacements.isEmpty else { return }
        let documentLength = textView.textStorage?.length ?? 0
        guard EditorEditTransaction.validate(transaction.replacements, documentLength: documentLength) else {
            if reportsInvalidAsAssertionFailure {
                assertionFailure(
                    "EditorEditTransaction contains an out-of-bounds, overlapping, or duplicate-zero-length replacement"
                )
            }
            return
        }
        let ordered = transaction.replacements.sorted { $0.range.location > $1.range.location }

        textView.breakUndoCoalescing()
        isPerformingEditingAssist = true
        defer { isPerformingEditingAssist = false }

        // Each `insertText` call independently posts AppKit's text-change
        // notification; without suppression `textDidChange` would publish
        // the (still mid-transaction) binding value once per range instead
        // of once for the whole command. Suppress every call but the last.
        isApplyingMultiRangeTransaction = ordered.count > 1
        defer { isApplyingMultiRangeTransaction = false }
        for (index, replacement) in ordered.enumerated() {
            if index == ordered.count - 1 {
                isApplyingMultiRangeTransaction = false
            }
            textView.insertText(replacement.replacementText, replacementRange: replacement.range)
        }

        if let resultingSelection = transaction.resultingSelection {
            // Routed through `selectionSet`'s setter, not
            // `textView.selectedRanges` directly, so the cached
            // `storedSelectionSet` (§6.9's selection-source-of-truth
            // design) stays correct — including a non-zero `primaryIndex`
            // — for whatever reads `selectionSet` next, not just AppKit's
            // own range array.
            selectionSet = resultingSelection
        }
        if let undoActionName = transaction.undoActionName, undoManager.canUndo {
            undoManager.setActionName(undoActionName)
        }
        textView.breakUndoCoalescing()
    }
}
