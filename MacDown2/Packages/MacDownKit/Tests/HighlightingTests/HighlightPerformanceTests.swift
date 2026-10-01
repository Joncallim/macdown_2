import Foundation
@testable import Highlighting
import SwiftTreeSitter
import Testing

/// Debug builds (the CI `swift test` configuration) keep generous DOCUMENTATION
/// ceilings, recalibrated 2026-07-23 for the `macos-26` runner where E06's
/// parse-heavy tests contend for cores. Release builds
/// (`swift test -c release --filter HighlightPerformanceTests --no-parallel`)
/// enforce the ceilings below, which sit at ~2x the measured Release numbers
/// recorded in `planning/epic-22-implementation.md` (Slice 10s) — regression
/// guards, not the E05 product budgets. Two E05 budgets are *not* met by these
/// measurements and are reported rather than asserted away: see `ReleaseCeiling`.
@MainActor
struct HighlightPerformanceTests {
    /// Release ceilings. Measured on Apple silicon, 1 MB Markdown, serial run:
    /// full highlight 0.25 s (E05 budget 500 ms: met); full parse 0.20 s; an
    /// incremental reparse after a one-character edit 0.19 s — the same cost as
    /// a full parse (it scales linearly with document size and does not reuse
    /// the old tree), so E05's 50 ms keystroke budget is NOT met for 1 MB
    /// Markdown at the parser level (Neon runs it off the main actor). The 8 ms
    /// main-thread budget applies to viewport-slice work, covered by
    /// `EditorPerformanceTests`, not to a whole-document parse.
    private enum ReleaseCeiling {
        static let fullHighlight: Duration = .milliseconds(500)
        static let fullParse: Duration = .milliseconds(400)
        static let incrementalReparse: Duration = .milliseconds(400)
    }

    private static var isRelease: Bool {
        #if DEBUG
            false
        #else
            true
        #endif
    }

    @Test func fullHighlight1MB() throws {
        let text = Fixtures.markdownRepeating(
            line: "# Heading\n\nSome `code` and **bold** text.\n\n",
            totalBytes: 1_000_000
        )
        let registry = GrammarRegistry()
        let config = try #require(registry.configuration(for: "markdown"))

        let start = ContinuousClock().now
        let parser = Parser()
        try parser.setLanguage(config.language)
        guard let tree = parser.parse(text),
              let rootNode = tree.rootNode,
              let query = config.queries[.highlights]
        else {
            Issue.record("Failed to parse or load query")
            return
        }
        let cursor = query.execute(node: rootNode, in: tree)
        cursor.setRange(NSRange(location: 0, length: (text as NSString).length))
        _ = cursor.highlights()
        let duration = ContinuousClock().now - start

        #expect(
            duration < (Self.isRelease ? ReleaseCeiling.fullHighlight : .seconds(8)),
            "Full 1 MB highlight took \(duration)"
        )
    }

    @Test func incrementalKeystroke1MB() throws {
        let text = Fixtures.markdownRepeating(
            line: "# Heading\n\nSome `code` and **bold** text.\n\n",
            totalBytes: 1_000_000
        )
        let registry = GrammarRegistry()
        let config = try #require(registry.configuration(for: "markdown"))

        let parser = Parser()
        try parser.setLanguage(config.language)
        guard let editedTree = parser.parse(text) else {
            Issue.record("Initial parse failed")
            return
        }

        // Simulate inserting a character near the middle.
        let nsText = text as NSString
        let editLocation = nsText.length / 2
        let newText = nsText.replacingCharacters(in: NSRange(location: editLocation, length: 0), with: "x")

        // Tree-sitter edits operate on byte offsets and points. The fixture text
        // is ASCII, so UTF-16 offsets and byte offsets are equivalent.
        let startByte = editLocation
        let oldEndByte = editLocation
        let newEndByte = editLocation + 1

        let startPoint = point(for: editLocation, in: text)
        let oldEndPoint = startPoint
        let newEndPoint = point(for: editLocation + 1, in: newText)

        let inputEdit = InputEdit(
            startByte: startByte,
            oldEndByte: oldEndByte,
            newEndByte: newEndByte,
            startPoint: startPoint,
            oldEndPoint: oldEndPoint,
            newEndPoint: newEndPoint
        )
        editedTree.edit(inputEdit)

        let start = ContinuousClock().now
        _ = parser.parse(tree: editedTree, string: newText)
        let duration = ContinuousClock().now - start

        #expect(
            duration < (Self.isRelease ? ReleaseCeiling.incrementalReparse : .seconds(8)),
            "Incremental keystroke took \(duration)"
        )
    }

    @Test func mainThreadParseBudgetDocumented() throws {
        let text = Fixtures.markdownRepeating(
            line: "# Heading\n\nSome `code` and **bold** text.\n\n",
            totalBytes: 1_000_000
        )
        let registry = GrammarRegistry()
        let config = try #require(registry.configuration(for: "markdown"))

        let parser = Parser()
        try parser.setLanguage(config.language)

        let start = ContinuousClock().now
        _ = parser.parse(text)
        let duration = ContinuousClock().now - start

        #expect(
            duration < (Self.isRelease ? ReleaseCeiling.fullParse : .seconds(8)),
            "Full 1 MB parse took \(duration)"
        )
    }

    // MARK: - Helpers

    /// Returns the tree-sitter `Point` (row/column) for a UTF-16 offset.
    private func point(for utf16Offset: Int, in text: String) -> Point {
        let nsText = text as NSString
        var lineStart = 0
        var lineEnd = 0
        var contentsEnd = 0
        nsText.getLineStart(&lineStart,
                            end: &lineEnd,
                            contentsEnd: &contentsEnd,
                            for: NSRange(location: utf16Offset, length: 0))

        let preceding = nsText.substring(with: NSRange(location: 0, length: lineStart)) as NSString
        let row = preceding.components(separatedBy: "\n").count - 1
        let column = utf16Offset - lineStart

        return Point(row: row, column: column)
    }
}
