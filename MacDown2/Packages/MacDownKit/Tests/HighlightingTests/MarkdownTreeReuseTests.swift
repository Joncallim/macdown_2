import Foundation
@testable import Highlighting
import SwiftTreeSitter
import Testing

/// Root-cause evidence for #203 / closure-register H5: why a one-character
/// edit to a large Markdown document costs about as much as a full parse.
///
/// tree-sitter hands an unchanged subtree of the old tree to the new tree by
/// pointer, so a reused node keeps its `Node.id`. Counting the old top-level
/// children whose id survives a reparse therefore measures node reuse
/// directly, without timing noise.
///
/// The edit itself is not the problem: `changedRanges` reports at most one
/// changed range, so the edit offsets are understood and the old tree is a
/// valid reuse source (the JSON control reuses nearly every top-level node
/// with the identical edit arithmetic). The tree-sitter parse log for the
/// block grammar (`ts_parser_set_logger`, measured in a standalone C harness
/// against the vendored `v0.5.3` sources) shows why reuse still fails:
///
/// - `paragraph`, `_line`, `_block_not_section` and the `*_repeat` helper
///   nodes are refused as `cant_reuse_node_is_fragile`: they are built by
///   reductions the grammar's parse table marks as conflicting (GLR), and
///   tree-sitter never reuses a fragile node.
/// - Every `section` after the first is refused by the first-leaf check
///   (`cant_reuse_node symbol:section, first_leaf_symbol:atx_h1_marker`):
///   the external scanner's heading marker was lexed while the previous
///   section was still open, a lex mode the reparse never re-enters.
///
/// Only leaf tokens are reused, which saves lexing but not parsing: an edit
/// costs ~75% of a full parse at every size and every position. That is a
/// property of the upstream grammar, not of this app's wiring; the edit's
/// `Point` columns do not affect it (halving them leaves the parse log
/// byte-for-byte identical).
///
/// If an upstream grammar update ever starts reusing sections, the first test
/// below fails: re-measure `HighlightPerformanceTests` and revisit H5.
@MainActor
struct MarkdownTreeReuseTests {
    private static let markdownLine = "# Heading\n\nSome `code` and **bold** text.\n\n"
    private static let jsonLine = "{\"a\": [1, 2, 3], \"b\": \"text\"}\n"
    /// Large enough for hundreds of top-level nodes, small enough to parse
    /// quickly in a Debug build.
    private static let documentBytes = 64000

    @Test func markdownBlockGrammarReusesNoSectionEvenForAnEditAtTheEnd() throws {
        let text = Fixtures.markdownRepeating(line: Self.markdownLine, totalBytes: Self.documentBytes)
        let result = try reparse(languageID: "markdown", text: text, editNear: .end)

        #expect(result.topLevelCount > 1000, "the fixture parses into one section per heading")
        #expect(result.changedRangeCount <= 1, "the edit is located correctly, so the old tree is valid")
        // Measured: exactly one (the first section, which starts in the
        // initial parse state). Everything before the edit is rebuilt.
        #expect(result.reusedCount <= 2, "Markdown reused \(result.reusedCount) of \(result.topLevelCount)")
    }

    @Test func markdownBlockGrammarReusesNoSectionForAnEditAtTheStart() throws {
        let text = Fixtures.markdownRepeating(line: Self.markdownLine, totalBytes: Self.documentBytes)
        let result = try reparse(languageID: "markdown", text: text, editNear: .start)

        #expect(result.changedRangeCount <= 1)
        #expect(result.reusedCount <= 2, "Markdown reused \(result.reusedCount) of \(result.topLevelCount)")
    }

    /// Control: the same harness and edit arithmetic on a grammar without
    /// fragile reductions reuses almost every top-level node, so the Markdown
    /// result above is a grammar property rather than a harness artefact.
    @Test func jsonControlReusesNearlyEveryTopLevelNode() throws {
        let text = Fixtures.markdownRepeating(line: Self.jsonLine, totalBytes: Self.documentBytes)
        let result = try reparse(languageID: "json", text: text, editNear: .end)

        #expect(result.topLevelCount > 1000)
        #expect(result.changedRangeCount <= 1)
        #expect(
            Double(result.reusedCount) >= 0.9 * Double(result.topLevelCount),
            "JSON reused \(result.reusedCount) of \(result.topLevelCount)"
        )
    }

    // MARK: - Harness

    private enum EditPosition {
        case start
        case end
    }

    private struct ReparseResult {
        let topLevelCount: Int
        let reusedCount: Int
        let changedRangeCount: Int
    }

    /// Parses `text`, inserts one space just inside the first or last
    /// top-level node, reparses with the edited old tree, and counts how many
    /// old top-level nodes the new tree shares by identity.
    private func reparse(languageID: String, text: String, editNear position: EditPosition) throws -> ReparseResult {
        let config = try #require(GrammarRegistry().configuration(for: languageID))
        let parser = Parser()
        try parser.setLanguage(config.language)
        let tree = try #require(parser.parse(text))
        let oldIDs = try topLevelIDs(of: tree)

        let nsText = text as NSString
        let lastText = nsText.rangeOfCharacter(from: CharacterSet.newlines.inverted, options: .backwards).location
        let lastLineStart = nsText.lineRange(for: NSRange(location: lastText, length: 0)).location
        // Inside a line's text, never at a block boundary.
        let location = (position == .start ? 0 : lastLineStart) + 2
        let newText = nsText.replacingCharacters(in: NSRange(location: location, length: 0), with: " ")

        // SwiftTreeSitter parses UTF-16: byte offsets and point columns are
        // UTF-16 units * 2 (see HighlightPerformanceTests).
        let startPoint = point(for: location, in: nsText)
        tree.edit(InputEdit(
            startByte: location * 2,
            oldEndByte: location * 2,
            newEndByte: (location + 1) * 2,
            startPoint: startPoint,
            oldEndPoint: startPoint,
            newEndPoint: Point(row: startPoint.row, column: startPoint.column + 2)
        ))
        let reparsed = try #require(parser.parse(tree: tree, string: newText))
        let newIDs = try Set(topLevelIDs(of: reparsed))

        return ReparseResult(
            topLevelCount: oldIDs.count,
            reusedCount: oldIDs.count(where: newIDs.contains),
            changedRangeCount: tree.changedRanges(from: reparsed).count
        )
    }

    private func topLevelIDs(of tree: MutableTree) throws -> [UInt] {
        let root = try #require(tree.rootNode)
        return (0 ..< root.childCount).compactMap { root.child(at: $0)?.id }
    }

    private func point(for utf16Offset: Int, in text: NSString) -> Point {
        let lineStart = text.lineRange(for: NSRange(location: utf16Offset, length: 0)).location
        let row = text.substring(to: lineStart).count(where: { $0 == "\n" })
        return Point(row: row, column: (utf16Offset - lineStart) * 2)
    }
}
