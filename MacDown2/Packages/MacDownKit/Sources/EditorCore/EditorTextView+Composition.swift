import AppKit

/// IME / dead-key composition. AppKit reports none of the marked-text edits through `didChange`, so the editor's
/// derived state (line index, multi-cursor cache, the SwiftUI binding) has to be repaired when a composition ends,
/// and Undo/Redo must not run against text that holds a marked range its undo records know nothing about.
public extension EditorTextView {
    /// Setting empty marked text (backspacing a pinyin composition down to nothing) ends the composition without
    /// an `unmarkText` call.
    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        let wasComposing = hasMarkedText()
        super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
        if wasComposing, !hasMarkedText() {
            owningSystem?.compositionDidEnd()
        }
    }

    override func unmarkText() {
        let wasComposing = hasMarkedText()
        super.unmarkText()
        if wasComposing {
            owningSystem?.compositionDidEnd()
        }
    }

    /// Ends an active composition by removing its marked text.
    internal func cancelComposition() {
        guard hasMarkedText() else { return }
        setMarkedText(
            "",
            selectedRange: NSRange(location: 0, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        unmarkText()
    }
}
