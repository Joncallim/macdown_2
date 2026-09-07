import AppKit
import Foundation

public extension EditorTextSystem {
    /// Applies text from an external source — e.g. a text-filter command's
    /// stdout — as exactly one native undoable edit, replacing `range` of
    /// the live text with `replacement`.
    ///
    /// This raises the same editing-assist reentrancy guard
    /// `applyAssistOutcome`'s `.edit` case does (`isPerformingEditingAssist`),
    /// **not** `isPerformingProgrammaticTextUpdate`: the replacement still
    /// flows through the normal `NSTextViewDelegate`/binding path and dirties
    /// the document like a user edit, but `EditorView.Coordinator
    /// .shouldChangeTextIn` is told not to reinterpret it as Markdown input.
    ///
    /// Without this guard, a filter whose legitimate output is a single
    /// Markdown-significant character (e.g. `*`) was silently rewritten by
    /// the Markdown editing-assist engine instead of inserted verbatim —
    /// post-review finding #3 on the E14B text-filters remediation.
    ///
    /// `range` is clamped to the live text as a last-resort safety net; the
    /// caller is expected to have already rejected a genuinely stale range
    /// (e.g. an edit happened elsewhere while an async command was
    /// running) rather than relying on this clamp to paper over it.
    @discardableResult
    func applyExternalReplacement(_ replacement: String, in range: NSRange, undoActionName: String) -> NSRange {
        let liveLength = (textView.string as NSString).length
        let location = min(max(0, range.location), liveLength)
        let length = min(max(0, range.length), liveLength - location)
        let clamped = NSRange(location: location, length: length)

        textView.breakUndoCoalescing()
        isPerformingEditingAssist = true
        textView.insertText(replacement, replacementRange: clamped)
        isPerformingEditingAssist = false
        let caret = NSRange(location: location + (replacement as NSString).length, length: 0)
        textView.setSelectedRange(caret)
        if undoManager.canUndo {
            undoManager.setActionName(undoActionName)
        }
        textView.breakUndoCoalescing()
        return caret
    }
}
