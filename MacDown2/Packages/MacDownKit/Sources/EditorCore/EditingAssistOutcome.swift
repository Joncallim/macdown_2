import Foundation

/// One contiguous text mutation produced by an editing assist.
struct EditingAssistEdit: Equatable {
    /// UTF-16 range in the live text to replace.
    let replacementRange: NSRange
    /// The replacement text.
    let replacementString: String
    /// UTF-16 selection to apply after the replacement.
    let resultingSelection: NSRange
    /// Undo action name (shown in the Edit menu) when AppKit creates an undo
    /// item for the edit.
    let undoActionName: String
}

/// The pure engine's decision for one input action.
enum EditingAssistOutcome: Equatable {
    /// AppKit should perform the original operation unchanged.
    case passthrough
    /// A contiguous text replacement (one undoable edit).
    case edit(EditingAssistEdit)
    /// A selection-only change: no text mutation, no undo entry.
    case selection(NSRange)
    /// The operation was deliberately consumed without any change.
    /// This is not an unimplemented placeholder state.
    case handledNoChange
}
