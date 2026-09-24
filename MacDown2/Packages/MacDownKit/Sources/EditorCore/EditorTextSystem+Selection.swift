import AppKit

// MARK: - Multi-range selection (EPIC-22 §6.9, §7.1, Slice 3a)

public extension EditorTextSystem {
    /// The current selection, as the plural sibling of `selectedRange`
    /// (`EditorTextSystem+Scroll.swift`), which remains unchanged and keeps
    /// returning `textView.selectedRange()` — confirmed empirically (against
    /// a real mounted text view, in `EditorMultiSelectionTests`) that
    /// AppKit's own single-range accessor always agrees with the first
    /// (topmost) entry of `selectedRanges`, the same range this type's own
    /// from-AppKit reconstruction below treats as primary by default.
    ///
    /// AppKit's `selectedRanges` has no concept of "primary" at all — it is
    /// always sorted ascending by location, with no notion of insertion
    /// order or a designated anchor — so `primaryIndex` cannot be recovered
    /// from `textView.selectedRanges` alone once it differs from `0` (e.g.
    /// after Option-clicking to add a caret BEFORE the primary one, once
    /// Slice 3b implements that). This getter therefore returns a cached
    /// `storedSelectionSet` whenever its `ranges` still exactly match
    /// AppKit's live `selectedRanges` (i.e. nothing has changed the
    /// selection through any path other than this type's own setter since
    /// it was last written) — preserving a genuinely non-zero
    /// `primaryIndex` across a read-after-write. Once AppKit's live ranges
    /// diverge from the cached copy (a native click, arrow-key navigation,
    /// or any direct `textView.selectedRanges`/`setSelectedRange` call this
    /// type didn't mediate), the cache is stale and this falls back to a
    /// fresh reconstruction from live AppKit state with `primaryIndex: 0` —
    /// a reasonable, documented default matching AppKit's own "first range"
    /// convention, not a crash or a silently wrong primary.
    var selectionSet: EditorSelectionSet {
        get {
            let liveRanges = textView.selectedRanges.map(\.rangeValue)
            if let cached = storedSelectionSet, cached.ranges == liveRanges {
                return cached
            }
            return EditorSelectionSet(selectedRanges: textView.selectedRanges) ??
                EditorSelectionSet(single: selectedRange)
        }
        set {
            storedSelectionSet = newValue
            textView.selectedRanges = newValue.asNSValueArray
        }
    }
}
