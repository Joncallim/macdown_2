import Foundation

/// One fenced ```mermaid``` block found in a document (epic-20-implementation.md
/// §6). Unlike `MathSpan`, Mermaid has no inline form — a fence is always a
/// complete block.
public struct MermaidFence: Sendable, Equatable {
    /// The fence's inner content: everything between the opening ```mermaid
    /// and closing ``` lines, with both delimiter lines themselves excluded.
    /// This is what gets handed to the renderer.
    public let source: String

    /// UTF-16 offsets into the ORIGINAL document text, spanning the ENTIRE
    /// fence — opening delimiter through closing delimiter inclusive. This
    /// is what a `ContributionContent`/export splice replaces, matching how
    /// `MathContribution`'s code-block exclusion covers a whole block, not
    /// just its inner text.
    public let sourceRange: Range<Int>

    public init(source: String, sourceRange: Range<Int>) {
        self.source = source
        self.sourceRange = sourceRange
    }
}
