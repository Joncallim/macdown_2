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
    /// click handling for it; `false` for a genuinely out-of-bounds offset,
    /// or when `offset` lands strictly inside an existing non-empty
    /// selection (see below) — both cases fail open to native click
    /// handling instead.
    ///
    /// An offset strictly inside an existing real (non-zero-length)
    /// selection is deliberately NOT handled: adding a zero-length point
    /// there would be silently merged away by `EditorSelectionSet.normalize`'s
    /// own overlap-merge rule (a genuine overlap, not a mere touch), which
    /// would consume the click while visibly doing nothing — no new caret,
    /// selection unchanged, and none of the ordinary click behavior
    /// (collapsing to a caret at the click point) the user would otherwise
    /// get. Found by an independent hostile review of this slice. Clicking
    /// exactly AT a selection's boundary (`location` or `location + length`)
    /// is unaffected by this guard and still adds a genuine, distinct
    /// touching caret, since `normalize` only merges genuine overlaps, not
    /// touching ranges.
    @discardableResult
    func toggleSecondaryCaret(at offset: Int) -> Bool {
        let documentLength = (textView.string as NSString).length
        guard offset >= 0, offset <= documentLength else { return false }

        var selection = selectionSet
        let landsInsideARealSelection = selection.ranges.contains { range in
            range.length > 0 && offset > range.location && offset < range.location + range.length
        }
        guard !landsInsideARealSelection else { return false }

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
