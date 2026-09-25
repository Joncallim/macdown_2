import AppKit

// MARK: - Synchronized plain-arrow-key caret movement (EPIC-22 §6.10, Slice 3b-iii)

public extension EditorTextSystem {
    /// Moves every active caret/selection left by one composed character
    /// sequence (never splitting a surrogate pair or combining sequence —
    /// the same `NSString.rangeOfComposedCharacterSequence(at:)` discipline
    /// `EditorTextSystem+MultiCursor.swift`'s delete logic already
    /// established), or collapses a real selection to its start, exactly
    /// like a native single-caret Left-arrow press. `false` (no-op, native
    /// single-caret handling proceeds unchanged) when fewer than two
    /// selections are active — this only ever intercepts the genuinely new
    /// multi-caret case.
    @discardableResult
    func moveAllCaretsLeft() -> Bool {
        moveAllCarets(.leftward)
    }

    /// The rightward counterpart of `moveAllCaretsLeft()`.
    @discardableResult
    func moveAllCaretsRight() -> Bool {
        moveAllCarets(.rightward)
    }

    /// Moves every active caret/selection up one line, at the same column
    /// (clamped to that line's actual length, via the same
    /// `EditorLineIndex`-based technique `addCursorAbove()`/`addCursorBelow()`
    /// use). A caret already on the first line collapses to its own anchor
    /// (matching native single-caret behavior: an arrow press always
    /// collapses an active selection even when it cannot move further).
    /// `false` when fewer than two selections are active.
    @discardableResult
    func moveAllCaretsUp() -> Bool {
        moveAllCarets(.upward)
    }

    /// The downward counterpart of `moveAllCaretsUp()`.
    @discardableResult
    func moveAllCaretsDown() -> Bool {
        moveAllCarets(.downward)
    }

    /// This is Slice 3b-iii's own, explicitly scoped first cut (§6.10):
    /// only the four plain, unmodified arrow keys are synchronized across
    /// every caret. Every other movement/selection-extension command
    /// (word/line/paragraph/document jumps, and any `AndModifySelection:`
    /// variant) is explicitly, disclosedly out of scope — an unhandled
    /// command does nothing to what this feature doesn't yet own, so it
    /// continues to move only the primary caret via AppKit's own native
    /// single-range handling, rather than collapsing or dropping the other
    /// carets. Broadening this list is a natural, separately-scoped
    /// follow-up once this pattern is proven for the smallest real case.
    private enum MovementDirection {
        case leftward, rightward, upward, downward
    }

    private func moveAllCarets(_ direction: MovementDirection) -> Bool {
        let selection = selectionSet
        guard selection.isMultiple else { return false }
        let text = textView.string as NSString
        let newRanges = selection.ranges.map { movedCaret(for: $0, direction: direction, in: text) }
        selectionSet = EditorSelectionSet(ranges: newRanges, primaryIndex: selection.primaryIndex)
        return true
    }

    /// Left/Up reference a range's START; Right/Down reference its END —
    /// both for the ordinary in-bounds movement case AND for the
    /// can't-move-further collapse case, so the two stay internally
    /// consistent. This is the SAME "collapse toward the edge closest to
    /// the direction of travel" choice native Left/Right make for a real
    /// selection, but the analogy is not exact for Up/Down: Left/Right
    /// collapse and stop there, while Up/Down collapse to that edge AND
    /// THEN also move one line further from it — e.g. pressing Up on a
    /// selection spanning several lines lands one line ABOVE the
    /// selection's own start, not merely at the start. This matches every
    /// real editor's conventional vertical-arrow-on-a-selection behavior,
    /// confirmed by an independent hostile review of this slice, but is a
    /// meaningfully different operation from the horizontal case, not a
    /// pure collapse.
    private func movedCaret(for range: NSRange, direction: MovementDirection, in text: NSString) -> NSRange {
        switch direction {
        case .leftward:
            movedLeft(range, in: text)
        case .rightward:
            movedRight(range, in: text)
        case .upward, .downward:
            movedVertically(range, upward: direction == .upward, in: text)
        }
    }

    private func movedLeft(_ range: NSRange, in text: NSString) -> NSRange {
        if range.length > 0 {
            return NSRange(location: range.location, length: 0)
        }
        guard range.location > 0 else { return NSRange(location: 0, length: 0) }
        let sequence = text.rangeOfComposedCharacterSequence(at: range.location - 1)
        return NSRange(location: sequence.location, length: 0)
    }

    private func movedRight(_ range: NSRange, in text: NSString) -> NSRange {
        let end = range.location + range.length
        if range.length > 0 {
            return NSRange(location: end, length: 0)
        }
        guard end < text.length else { return NSRange(location: text.length, length: 0) }
        let sequence = text.rangeOfComposedCharacterSequence(at: end)
        return NSRange(location: sequence.location + sequence.length, length: 0)
    }

    private func movedVertically(_ range: NSRange, upward: Bool, in text: NSString) -> NSRange {
        let anchor = upward ? range.location : range.location + range.length
        let referenceLine = lineIndex.line(atUTF16Offset: anchor)
        let referenceColumn = lineIndex.column(atUTF16Offset: anchor, onLine: referenceLine, in: text)
        let targetLine = upward ? referenceLine - 1 : referenceLine + 1
        guard targetLine >= 1, targetLine <= lineIndex.lineCount else {
            return NSRange(location: anchor, length: 0)
        }
        let targetOffset = lineIndex.utf16Offset(forLine: targetLine, column: referenceColumn, in: text)
        return NSRange(location: targetOffset, length: 0)
    }
}
