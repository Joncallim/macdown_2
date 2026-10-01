import AppKit

extension EditorTextSystem {
    /// Menu/palette editing commands (line and text transforms, Toggle Comment)
    /// must not rewrite text while an IME composition is active — applying an
    /// edit would commit/cancel the marked text — nor re-enter an assist or a
    /// programmatic update. They fail open (return `false`), the same contract
    /// as snippet insertion.
    var canApplyCommandEdit: Bool {
        !textView.hasMarkedText() && !isPerformingEditingAssist && !isPerformingProgrammaticTextUpdate
    }
}
