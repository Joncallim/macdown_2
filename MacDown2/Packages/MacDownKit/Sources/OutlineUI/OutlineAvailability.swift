/// Every outline state has a name and a message (D7).
public enum OutlineAvailability: Sendable, Equatable {
    /// No document has been published yet. Sidebar renders nothing — no
    /// empty-state flash on open.
    case notParsed
    /// The active document is not Markdown. `items` is empty even if
    /// `headings` is populated (§2.4) — the gate protects the tree, not just
    /// the label.
    case unsupportedFormat(formatName: String)
    /// Markdown, zero headings.
    case noHeadings
    /// Markdown, at least one heading.
    case ready
}
