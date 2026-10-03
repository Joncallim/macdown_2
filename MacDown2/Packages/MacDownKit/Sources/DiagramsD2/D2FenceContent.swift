import Foundation
import MarkdownEngine

/// Shared by `D2FenceScanner` (Export) and Preview's own block handling
/// (`TextualMarkdownPreview`'s `BlockView`), mirroring
/// `MermaidFenceContent`'s exact rationale: both need to recover a
/// fence's inner diagram source from its full, delimiter-included text.
public enum D2FenceContent {
    /// Strips the opening delimiter line and, when present, the closing one — the opening
    /// ```d2 and closing ``` delimiters — from `fenceText`, which must be
    /// the block's full source including both delimiter lines.
    public static func stripDelimiters(from fenceText: String) -> String {
        fenceText.fencedBlockInnerText()
    }
}
