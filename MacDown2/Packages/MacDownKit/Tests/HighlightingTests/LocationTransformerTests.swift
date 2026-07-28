import AppKit
@testable import Highlighting
import SwiftTreeSitter
import Testing

@MainActor
@Suite("NeonSyntaxHighlighter.locationTransformer")
struct LocationTransformerTests {
    private func transform(_ text: String, at offset: Int) -> SwiftTreeSitter.Point? {
        let textView = NSTextView()
        textView.string = text
        return NeonSyntaxHighlighter.locationTransformer(for: textView)(offset)
    }

    @Test func emptyDocumentReturnsRowZero() {
        #expect(transform("", at: 0) == SwiftTreeSitter.Point(row: 0, column: 0))
    }

    @Test func singleLineNoNewline() {
        #expect(transform("hello", at: 3) == SwiftTreeSitter.Point(row: 0, column: 3))
    }

    @Test func secondLineAfterOneNewline() {
        let text = "hello\nworld"
        // "world" starts at offset 6.
        #expect(transform(text, at: 6) == SwiftTreeSitter.Point(row: 1, column: 0))
        #expect(transform(text, at: 8) == SwiftTreeSitter.Point(row: 1, column: 2))
    }

    // Regression: the line-offset table build was swapped from a
    // `rangeOfCharacter(from:)` scan to a raw `unichar` buffer scan for
    // performance. A trailing newline is the edge case where a naive
    // rewrite is easy to get subtly wrong (whether it opens a new, empty
    // last line at `length`) — verified against the original implementation
    // before landing the change.
    @Test func trailingNewlineOpensEmptyLastLine() {
        let text = "line1\nline2\n"
        // Offset `text.utf16.count` is the very end, i.e. the start of the
        // empty line following the trailing newline.
        #expect(transform(text, at: text.utf16.count) == SwiftTreeSitter.Point(row: 2, column: 0))
    }

    @Test func multipleConsecutiveNewlines() {
        let text = "a\n\n\nb"
        // Row 0: "a", row 1: "", row 2: "", row 3: "b".
        #expect(transform(text, at: 0) == SwiftTreeSitter.Point(row: 0, column: 0))
        #expect(transform(text, at: 2) == SwiftTreeSitter.Point(row: 1, column: 0))
        #expect(transform(text, at: 3) == SwiftTreeSitter.Point(row: 2, column: 0))
        #expect(transform(text, at: 4) == SwiftTreeSitter.Point(row: 3, column: 0))
    }

    @Test func offsetPastEndClampsToLastLine() {
        let text = "hello\nworld"
        #expect(transform(text, at: text.utf16.count + 50) != nil)
    }

    @Test func rebuildsAfterDocumentLengthChanges() {
        let textView = NSTextView()
        textView.string = "line1\nline2"
        let transformer = NeonSyntaxHighlighter.locationTransformer(for: textView)

        #expect(transformer(6) == SwiftTreeSitter.Point(row: 1, column: 0))

        // Grow the document; the cached table must invalidate and rebuild
        // rather than reporting a stale row for the new content. Offset 18 is
        // the start of "line4" (three preceding newlines at 5, 11, 17).
        textView.string = "line1\nline2\nline3\nline4"
        #expect(transformer(18) == SwiftTreeSitter.Point(row: 3, column: 0))
    }
}
