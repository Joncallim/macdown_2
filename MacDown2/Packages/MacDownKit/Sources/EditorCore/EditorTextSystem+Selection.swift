import AppKit

// MARK: - Multi-range selection (EPIC-22 §6.9, §6.10, §7.1, Slices 3a/3b-i)

public extension EditorTextSystem {
    /// The current selection, as the plural sibling of `selectedRange`
    /// (`EditorTextSystem+Scroll.swift`), which remains unchanged and keeps
    /// returning `textView.selectedRange()` — confirmed empirically (against
    /// a real mounted text view, in `EditorMultiSelectionTests`) that
    /// AppKit's own single-range accessor always agrees with the first
    /// (topmost) entry of `selectedRanges`, the same range this type's own
    /// from-AppKit reconstruction below treats as primary by default.
    ///
    /// AppKit's `selectedRanges` has no concept of "primary" at all, and
    /// (§6.9's architecture-correction note) cannot even hold more than one
    /// simultaneous zero-length (bare-caret) range, or a mix of one with
    /// anything else, at any spacing — confirmed empirically with direct
    /// probes. So this property's `storedSelectionSet` cache is the actual
    /// source of truth for a caret set AppKit itself cannot fully
    /// corroborate; the getter below trusts it under either of two
    /// conditions, and falls back to a fresh from-AppKit reconstruction
    /// (`primaryIndex: 0`, a reasonable default, not a crash or a silently
    /// wrong primary) once neither holds — meaning some OTHER path (a
    /// native click, arrow-key navigation, or a direct
    /// `textView.selectedRanges`/`setSelectedRange` call this type didn't
    /// mediate) changed the selection since the cache was last written:
    /// 1. `cached.ranges == liveRanges` — the write fully survived AppKit's
    ///    own representation (a genuine, non-touching multi-*selection*,
    ///    e.g. what Select-All-Occurrence/Slice 3c produces), so the cache
    ///    is exactly what AppKit itself also reports, including a non-zero
    ///    `primaryIndex`.
    /// 2. `liveRanges == [cached.primaryRange]` — the setter's own write
    ///    could not fully survive (a bare caret beyond the first, or a
    ///    touching pair, silently collapsed/merged by AppKit) and
    ///    correctly reverted AppKit's visible state to just the primary
    ///    range (see the setter below); the cache is still the correct,
    ///    full-fidelity model, AppKit just cannot display all of it
    ///    natively — `EditorTextView`'s own secondary-caret drawing pass
    ///    (§6.10, Slice 3b-i) is what makes the rest visible.
    var selectionSet: EditorSelectionSet {
        get {
            let liveRanges = textView.selectedRanges.map(\.rangeValue)
            if let cached = storedSelectionSet, cached.ranges == liveRanges || liveRanges == [cached.primaryRange] {
                return cached
            }
            return EditorSelectionSet(selectedRanges: textView.selectedRanges) ??
                EditorSelectionSet(single: selectedRange)
        }
        set {
            storedSelectionSet = newValue
            textView.selectedRanges = newValue.asNSValueArray
            // Verify the write actually survived intact. If AppKit silently
            // collapsed/merged it (only possible when there is more than
            // one range: a single range always round-trips), fall back to
            // showing just the primary natively rather than leaving AppKit
            // in whatever partial/collapsed shape it produced on its own —
            // `storedSelectionSet` above already retains the correct full
            // model regardless, which the getter's second condition above
            // is what lets the rest of this type recover.
            if newValue.isMultiple, textView.selectedRanges.map(\.rangeValue) != newValue.ranges {
                textView.selectedRanges = [NSValue(range: newValue.primaryRange)]
            }
        }
    }
}
