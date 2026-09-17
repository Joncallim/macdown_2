import Foundation

/// Shared by `MermaidFenceScanner` (Export) and Preview's own block handling
/// (`TextualMarkdownPreview`'s `BlockView`, epic-20-implementation.md §7.2) —
/// both need to recover a fence's inner diagram source from its full,
/// delimiter-included text, since `PreviewBlock.source` and a scanned
/// `MarkdownBlock`'s sliced text are both produced by the identical
/// `sourceMap.utf16Range(ofLines:)` slicing (confirmed against
/// `PreviewBlock.blocks(from:text:)`), fence delimiters included either way.
public enum MermaidFenceContent {
    /// Strips exactly the first and last physical line — the opening
    /// ```mermaid and closing ``` delimiters — from `fenceText`, which must
    /// be the block's full source including both delimiter lines.
    /// Positional, not syntax-aware: this works regardless of fence
    /// character (``` or ~~~), indentation, or language-tag spelling,
    /// because it never re-parses the delimiter text, only excludes it by
    /// line position.
    public static func stripDelimiters(from fenceText: String) -> String {
        var lines = fenceText.components(separatedBy: "\n")
        guard lines.count >= 2 else { return "" }
        lines.removeFirst()
        lines.removeLast()
        return lines.joined(separator: "\n")
    }
}
