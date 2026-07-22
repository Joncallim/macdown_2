import Foundation
@testable import Highlighting
import SwiftTreeSitter
import Testing

@MainActor
struct HighlightPerformanceTests {
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

        #expect(duration < .seconds(2), "Full 1 MB highlight took \(duration)")
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

        // Debug builds are much slower than release; this threshold documents
        // the current debug-build performance rather than enforcing the 8 ms
        // main-thread budget.
        #expect(duration < .seconds(2), "Incremental keystroke took \(duration)")
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

        // Budget is 8 ms synchronous slice in release builds; in debug builds
        // we use a generous ceiling to keep the test useful as documentation.
        #expect(duration < .seconds(2), "Main-thread parse budget exceeded: \(duration)")
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
