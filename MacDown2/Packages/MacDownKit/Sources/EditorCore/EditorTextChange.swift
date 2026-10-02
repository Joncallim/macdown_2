import Foundation

/// A change to the editor's text, as reported to an observer (the Find model
/// keeps its "In Selection" domain in step with it — #183 F03 follow-up).
public enum EditorTextChange: Sendable, Equatable {
    /// One atomic edit: `range` is in pre-edit coordinates and is replaced by
    /// `replacementLength` UTF-16 units. A multi-range transaction reports one
    /// edit per range, highest location first, so each is valid in turn.
    case edit(range: NSRange, replacementLength: Int)
    /// The text changed in a way that carries no edit geometry (undo/redo,
    /// whole-document replacement); positions held by observers are no longer
    /// trustworthy.
    case untracked
}
