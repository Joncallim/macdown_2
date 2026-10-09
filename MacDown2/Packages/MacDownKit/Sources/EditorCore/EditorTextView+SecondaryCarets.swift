import AppKit

/// Multi-caret rendering (§6.9's architecture-correction note, §6.10, Slice
/// 3b-i). Extracted from `EditorTextView.swift` to stay under its
/// file-length budget, matching `EditorTextView+FindHighlights.swift`'s own
/// extraction for the same reason.
extension EditorTextView {
    /// Every caret beyond the primary one lives only in
    /// `EditorTextSystem.selectionSet`, never in `textView.selectedRanges` —
    /// `NSTextView` cannot represent more than one simultaneous zero-length
    /// range there, confirmed empirically, so AppKit's own native
    /// insertion-point rendering only ever shows the primary caret. This
    /// pass draws a solid (deliberately non-blinking — see §6.10 on why
    /// synchronizing a second timer against AppKit's own private blink
    /// cadence is unnecessary complexity for a cosmetic property) vertical
    /// bar at every OTHER caret's position, in the same color AppKit uses
    /// for the real one.
    ///
    /// Uses `NSTextInputClient.firstRect(forCharacterRange:actualRange:)`
    /// (confirmed empirically, against this exact TextKit 2 stack, to
    /// return correct, already-coordinate-converted screen-space rects for
    /// an arbitrary zero-length range) rather than hand-deriving
    /// paragraph-relative line-fragment geometry the way `drawInvisibles`
    /// (`EditorTextView.swift`) must: that manual approach exists there
    /// because it draws MANY glyphs per visible line from one bounded
    /// fragment walk; here there are only ever a handful of explicit,
    /// already-known offsets to resolve, so the built-in, Apple-maintained
    /// API already designed for exactly this (IME candidate-window
    /// positioning) is the lower-risk choice — not re-deriving fragile
    /// geometry math this codebase has already been burned by once
    /// (§6.8/§6.9's own invisibles coordinate-space bug).
    ///
    /// Not viewport-pre-filtered before calling `firstRect` for each
    /// secondary caret, unlike `drawInvisibles`'s bounded fragment walk:
    /// `EditorTextViewSecondaryCaretTests`'s 100-caret stress test measures
    /// this directly against the §11 performance budget rather than
    /// pre-emptively adding an unverified viewport heuristic: this method
    /// is called once per real display pass (not once per keystroke on an
    /// otherwise-unrelated part of the document), and it costs one call to
    /// an already-fast, layout-caching API per caret. If a future, much
    /// larger cursor count is found to actually violate the budget, add
    /// the filter then, informed by a real measurement rather than a guess.
    func drawSecondaryCarets() {
        guard let owningSystem else { return }
        let selection = owningSystem.selectionSet
        guard selection.isMultiple else { return }
        let secondaryOffsets = selection.ranges.enumerated()
            .filter { index, range in index != selection.primaryIndex && range.length == 0 }
            .map(\.element.location)
        guard !secondaryOffsets.isEmpty, let window else { return }

        let color = insertionPointColor ?? .labelColor
        for offset in secondaryOffsets {
            var actualRange = NSRange(location: NSNotFound, length: 0)
            let screenRect = firstRect(
                forCharacterRange: NSRange(location: offset, length: 0),
                actualRange: &actualRange
            )
            guard actualRange.location != NSNotFound else { continue }
            var viewRect = convert(window.convertFromScreen(screenRect), from: nil)
            viewRect.size.width = max(viewRect.width, 1.5)
            color.setFill()
            NSBezierPath(rect: viewRect).fill()
        }
    }
}
