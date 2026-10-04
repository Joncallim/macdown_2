@testable import EditorCore
import Foundation
import Testing

/// Review pass 1: Delete, Duplicate and Join Lines had the same CR-before-LF fusion defect
/// as the (fixed) Move Line — in a mixed-ending document the edit could leave a `\r` directly
/// before an unrelated `\n`, which reads back as ONE `\r\n`: a line vanishes or is invented.
/// Every applied edit must have exactly the line-structure effect it advertises.
@Suite("EditorLineTransforms — Delete/Duplicate/Join with mixed line endings")
struct EditorLineTransformsMixedEndingsTests {
    private typealias Units = EditorMoveLinesMixedEndingsTests

    private func contents(_ units: [String]) -> [String] {
        units.map { String($0.filter { !$0.isNewline }) }
    }

    private func forEachCaret(
        _ body: (String, Int, EditorSelectionSet, NSString, EditorLineIndex) -> String?
    ) -> [String] {
        var failures: [String] = []
        for document in Units.mixedEndingDocuments() {
            let text = document as NSString
            let lineIndex = EditorLineIndex(text: text)
            for line in 1 ... lineIndex.lineCount {
                let start = lineIndex.lineStartOffsets[line - 1]
                let selection = EditorSelectionSet(single: NSRange(location: start, length: 0))
                if let failure = body(document, line, selection, text, lineIndex) {
                    failures.append("\(document.debugDescription) line \(line): \(failure)")
                }
            }
        }
        return failures
    }

    @Test func deleteLineRemovesExactlyOneLineAndNothingElse() {
        let failures = forEachCaret { document, line, selection, text, lineIndex in
            let transaction = EditorLineTransforms.deleteLinesTransaction(
                text: text, lineIndex: lineIndex, selection: selection
            )
            guard let applied = LineTransformTestSupport.applied(transaction, to: document) else { return nil }
            let before = contents(Units.units(of: document))
            var expected = before
            expected.remove(at: line - 1)
            let after = contents(Units.units(of: applied.text))
            return after == expected || (line == before.count && after.count == expected.count) ? nil
                : "got \(applied.text.debugDescription)"
        }
        #expect(failures.isEmpty, "\(failures.prefix(3))")
    }

    @Test func duplicateLineAddsExactlyOneLine() {
        let failures = forEachCaret { document, _, selection, text, lineIndex in
            let transaction = EditorLineTransforms.duplicateLinesTransaction(
                text: text, lineIndex: lineIndex, selection: selection
            )
            guard let applied = LineTransformTestSupport.applied(transaction, to: document) else { return nil }
            let before = Units.units(of: document).count
            return Units.units(of: applied.text).count == before + 1 ? nil : "got \(applied.text.debugDescription)"
        }
        #expect(failures.isEmpty, "\(failures.prefix(3))")
    }

    @Test func joinLinesRemovesExactlyOneLine() {
        let failures = forEachCaret { document, _, selection, text, lineIndex in
            let transaction = EditorLineTransforms.joinLinesTransaction(
                text: text, lineIndex: lineIndex, selection: selection
            )
            guard let applied = LineTransformTestSupport.applied(transaction, to: document) else { return nil }
            let before = Units.units(of: document).count
            return Units.units(of: applied.text).count == before - 1 ? nil : "got \(applied.text.debugDescription)"
        }
        #expect(failures.isEmpty, "\(failures.prefix(3))")
    }

    @Test func theReportedCasesAreDeclinedNotFused() {
        // Delete line 2 of "a\ra\n\na" would give "a\r\na" (a blank line vanishes).
        let text = "a\ra\n\na" as NSString
        let lineIndex = EditorLineIndex(text: text)
        let selection = EditorSelectionSet(single: NSRange(location: lineIndex.lineStartOffsets[1], length: 0))
        #expect(EditorLineTransforms
            .deleteLinesTransaction(text: text, lineIndex: lineIndex, selection: selection) == nil)
    }

    @Test func joiningWithABlankLineAddsNoSeparator() throws {
        func join(_ document: String, caretAt location: Int, length: Int = 0) throws -> String {
            let text = document as NSString
            let lineIndex = EditorLineIndex(text: text)
            let selection = EditorSelectionSet(single: NSRange(location: location, length: length))
            let transaction = EditorLineTransforms.joinLinesTransaction(
                text: text, lineIndex: lineIndex, selection: selection
            )
            return try #require(LineTransformTestSupport.applied(transaction, to: document)).text
        }

        #expect(try join("a\n\nc", caretAt: 0) == "a\nc")
        #expect(try join("a\n\nc", caretAt: 0, length: 5) == "a c")
        #expect(try join("\nb", caretAt: 0) == "b")
    }

    /// Review pass 6: a caret on the last line (nothing to join) made `makeTransaction` miss its index and the whole
    /// multi-caret Join Lines silently did nothing.
    @Test func aCaretOnTheLastLineDoesNotCancelTheOtherCarets() throws {
        let document = "a\n  b\nc"
        let text = document as NSString
        let lineIndex = EditorLineIndex(text: text)
        let selection = EditorSelectionSet(ranges: [
            NSRange(location: 0, length: 0), // joins lines 1 and 2
            NSRange(location: 7, length: 0), // last line: nothing to join
        ], primaryIndex: 0)

        let transaction = EditorLineTransforms.joinLinesTransaction(
            text: text, lineIndex: lineIndex, selection: selection
        )

        let applied = try #require(LineTransformTestSupport.applied(transaction, to: document))
        #expect(applied.text == "a b\nc")
    }
}
