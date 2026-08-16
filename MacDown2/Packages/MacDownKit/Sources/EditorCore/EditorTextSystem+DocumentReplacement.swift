import AppKit
import Foundation

public extension EditorTextSystem {
    /// Replaces the entire document with `replacement` as exactly one native
    /// edit (EPIC-11 §3.5): one undo group named `undoActionName`, one
    /// binding publication (the text-view delegate fires once), and the
    /// normal dirty/recovery transitions.
    ///
    /// This deliberately does NOT raise `isPerformingProgrammaticTextUpdate`:
    /// the document must observe the formatted text as a user edit so it
    /// becomes dirty and participates in save/recovery like any keystroke.
    ///
    /// The previous selection is preserved by clamping its location and
    /// length to the new text; a caret at the end of the source document
    /// stays at the end of the formatted document. When the replacement
    /// equals the current text, nothing happens: no undo entry and no
    /// publication, so formatting an already-formatted document never dirties
    /// it.
    func applyDocumentReplacement(_ replacement: String, undoActionName: String) {
        let oldLength = (textView.string as NSString).length
        guard replacement != textView.string else { return }
        let newLength = (replacement as NSString).length
        let selection = textView.selectedRange()

        textView.breakUndoCoalescing()
        textView.insertText(replacement, replacementRange: NSRange(location: 0, length: oldLength))
        let location: Int = if selection.location >= oldLength {
            // Caret (or selection start) at the end of the source stays at
            // the end of the formatted document.
            newLength
        } else {
            min(max(0, selection.location), newLength)
        }
        let length = min(max(0, selection.length), newLength - location)
        textView.setSelectedRange(NSRange(location: location, length: length))
        if undoManager.canUndo {
            undoManager.setActionName(undoActionName)
        }
        textView.breakUndoCoalescing()
    }
}
