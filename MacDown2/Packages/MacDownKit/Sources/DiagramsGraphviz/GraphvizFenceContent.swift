import Foundation
import MarkdownEngine

/// Shared by `GraphvizFenceScanner` (Export) and Preview's own block
/// handling (`TextualMarkdownPreview`'s `BlockView`), mirroring
/// `MermaidFenceContent`'s exact rationale.
public enum GraphvizFenceContent {
    /// Strips the opening delimiter line and, when present, the closing one — the opening
    /// ```dot/```graphviz and closing ``` delimiters — from `fenceText`,
    /// which must be the block's full source including both delimiter
    /// lines.
    public static func stripDelimiters(from fenceText: String) -> String {
        fenceText.fencedBlockInnerText()
    }
}
