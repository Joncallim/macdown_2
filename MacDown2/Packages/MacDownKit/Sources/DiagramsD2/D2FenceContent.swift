import Foundation

/// Shared by `D2FenceScanner` (Export) and Preview's own block handling
/// (`TextualMarkdownPreview`'s `BlockView`), mirroring
/// `MermaidFenceContent`'s exact rationale: both need to recover a
/// fence's inner diagram source from its full, delimiter-included text.
public enum D2FenceContent {
    /// Strips exactly the first and last physical line — the opening
    /// ```d2 and closing ``` delimiters — from `fenceText`, which must be
    /// the block's full source including both delimiter lines.
    public static func stripDelimiters(from fenceText: String) -> String {
        var lines = fenceText.components(separatedBy: "\n")
        guard lines.count >= 2 else { return "" }
        lines.removeFirst()
        lines.removeLast()
        return lines.joined(separator: "\n")
    }
}
