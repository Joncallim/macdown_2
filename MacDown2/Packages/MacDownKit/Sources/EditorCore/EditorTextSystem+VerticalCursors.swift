import AppKit

// MARK: - Add Cursor Above/Below (EPIC-22 §6.10, Slice 3b-ii-b)

public extension EditorTextSystem {
    /// Adds a new caret one line above the current TOP-most caret, at the
    /// same column (clamped to that line's actual length — the standard
    /// "sticky column" vertical-caret-movement convention). `false` (no-op)
    /// if the top-most caret is already on the first line.
    ///
    /// Extends from the top-most existing caret, not necessarily the
    /// primary one: matches the "grow the column outward from its current
    /// edge" convention every real multi-cursor editor uses for repeated
    /// invocations, since the primary caret (§7.1's "first/topmost by
    /// AppKit convention") does not necessarily sit at either edge once
    /// other carets exist (e.g. after an Option-click, Slice 3b-ii, adds
    /// one above the original primary).
    ///
    /// The target column is recomputed fresh from the reference caret's own
    /// current column on every call — not carried as separate persistent
    /// "desired column" state across repeated invocations through an
    /// intermediate shorter line. This is a deliberate, disclosed scope
    /// decision (§6.10): genuine sticky-column tracking needs its own
    /// cache-invalidation discipline (mirroring Slice 3b-i's
    /// `storedSelectionSet` fix) that is a real, separable piece of
    /// complexity, not implied by "add a caret above/below" on its own.
    @discardableResult
    func addCursorAbove() -> Bool {
        addVerticalCursor(above: true)
    }

    /// The downward counterpart of `addCursorAbove()`: extends from the
    /// BOTTOM-most existing caret. `false` (no-op) if it is already on the
    /// last line.
    @discardableResult
    func addCursorBelow() -> Bool {
        addVerticalCursor(above: false)
    }

    private func addVerticalCursor(above: Bool) -> Bool {
        let text = textView.string as NSString
        let selection = selectionSet
        // `selection.ranges` is always sorted ascending and never empty
        // (`EditorSelectionSet`'s own invariant) — `.first`/`.last` are the
        // top-most/bottom-most existing carets respectively.
        guard let referenceRange = above ? selection.ranges.first : selection.ranges.last else { return false }

        let referenceLine = lineIndex.line(atUTF16Offset: referenceRange.location)
        let referenceColumn = lineIndex.column(atUTF16Offset: referenceRange.location, onLine: referenceLine, in: text)
        let targetLine = above ? referenceLine - 1 : referenceLine + 1
        guard targetLine >= 1, targetLine <= lineIndex.lineCount else { return false }

        let targetOffset = lineIndex.utf16Offset(forLine: targetLine, column: referenceColumn, in: text)
        var updated = selection
        updated.addRange(NSRange(location: targetOffset, length: 0), makePrimary: false)
        selectionSet = updated
        return true
    }
}
