import AppKit

/// Forwards current-document Find match ranges to the owned `EditorTextView`
/// for highlighting (EPIC-22 §6.14, Slice 5a). Extracted to its own file
/// matching the established per-feature-extension convention (e.g.
/// `EditorTextSystem+CommentToggle.swift`).
public extension EditorTextSystem {
    /// Sets the ranges the Find bar's match highlighting should draw, and
    /// which one (by index into `ranges`) is the current match — drawn
    /// visually distinct from the rest. Pass an empty array and `nil` to
    /// clear highlighting entirely (the Find bar closing, or the query
    /// becoming empty).
    ///
    /// A no-op (no redraw scheduled) when neither `ranges` nor
    /// `currentIndex` actually changed from what's already displayed, since
    /// this is called on every keystroke in the Find bar's query field via
    /// `EditorFindModel.updateMatches(in:)`.
    func setFindHighlights(ranges: [NSRange], currentIndex: Int?) {
        (textView as? EditorTextView)?.setFindHighlights(ranges: ranges, currentIndex: currentIndex)
    }
}
