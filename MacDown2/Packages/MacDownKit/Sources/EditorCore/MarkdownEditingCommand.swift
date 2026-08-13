import Foundation

/// A Markdown formatting command available from the app menu (the
/// `.textFormatting` replacement) and from `EditorTextSystem`.
public enum MarkdownEditingCommand: Sendable, Equatable {
    /// `**selection**`
    case bold
    /// `*selection*`
    case italic
    /// `` `selection` ``
    case inlineCode
    /// ATX heading prefix `#…` (1...6); invalid levels are rejected at the
    /// `EditorTextSystem` entry boundary.
    case heading(level: Int)
    /// Removes the ATX heading prefix.
    case paragraph
}
