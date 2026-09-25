import AppKit

// MARK: - Option-click add/remove caret (EPIC-22 §6.10, Slice 3b-ii)

public extension EditorTextSystem {
    /// Toggles a secondary (non-primary) caret at `offset`, called by
    /// `EditorTextView.mouseDown(with:)` on a plain Option-click. If a bare
    /// caret already sits exactly at `offset`, it is removed; otherwise one
    /// is added, alongside whatever selection is already active, without
    /// disturbing the existing primary.
    ///
    /// Returns `true` once handled — including the no-op case of toggling
    /// off the last remaining secondary caret — so the caller always treats
    /// a plain Option-click as consumed and never falls through to native
    /// click handling for it; `false` only for a genuinely out-of-bounds
    /// offset (defensive: real callers always resolve `offset` from a
    /// point actually inside this text view).
    @discardableResult
    func toggleSecondaryCaret(at offset: Int) -> Bool {
        let documentLength = (textView.string as NSString).length
        guard offset >= 0, offset <= documentLength else { return false }

        var selection = selectionSet
        if let existingIndex = selection.ranges.firstIndex(where: { $0.length == 0 && $0.location == offset }) {
            // `EditorSelectionSet.removeRange(at:)` is itself a no-op on the
            // last remaining range (a selection set is never empty) — no
            // separate guard needed here for "toggling off down to zero."
            selection.removeRange(at: existingIndex)
        } else {
            selection.addRange(NSRange(location: offset, length: 0), makePrimary: false)
        }
        selectionSet = selection
        return true
    }
}
