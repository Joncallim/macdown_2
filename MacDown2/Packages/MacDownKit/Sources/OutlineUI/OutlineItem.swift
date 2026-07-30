import MarkdownEngine

/// One node in the outline tree (D3, D4).
///
/// `id` is the heading's ordinal in `MarkdownDocument.headings` — deterministic
/// and allocation-free, but only stable for the lifetime of a single parse.
/// See `OutlineIdentityMap` for carrying UI state across a re-parse.
public struct OutlineItem: Sendable, Equatable, Identifiable {
    public let id: Int
    public let level: Int
    public let title: String
    public let lineRange: ClosedRange<Int>
    public let children: [OutlineItem]

    public init(id: Int, level: Int, title: String, lineRange: ClosedRange<Int>, children: [OutlineItem]) {
        self.id = id
        self.level = level
        self.title = title
        self.lineRange = lineRange
        self.children = children
    }
}
