import AppKit

public extension EditorTextSystem {
    /// Menu/palette editing commands (line and text transforms, Toggle Comment)
    /// must not rewrite text while an IME composition is active — applying an
    /// edit would commit/cancel the marked text — nor re-enter an assist or a
    /// programmatic update. They fail open (return `false`), the same contract
    /// as snippet insertion.
    var canApplyCommandEdit: Bool {
        !isDetachedFromEditorView && !textView.hasMarkedText() && !isPerformingEditingAssist
            && !isPerformingProgrammaticTextUpdate
    }

    /// Marks (or, for tests that drive a system without a view, unmarks) a system created ahead of its `EditorView`
    /// (the window's eager session set-up), so command edits are
    /// refused until the view mounts and clears this: a window opened or restored in Preview Only never mounts one.
    func setAwaitingEditorView(_ awaiting: Bool) {
        isDetachedFromEditorView = awaiting
    }
}
