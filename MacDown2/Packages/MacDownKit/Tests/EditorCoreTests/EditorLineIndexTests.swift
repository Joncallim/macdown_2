@testable import EditorCore
import Foundation
import Testing

@Suite("EditorLineIndex")
struct EditorLineIndexTests {
    // MARK: - Full-document construction

    @Test func emptyDocumentIsOneLine() {
        let index = EditorLineIndex(text: "")
        #expect(index.lineCount == 1)
        #expect(index.lineStartOffsets == [0])
        #expect(index.utf16Length == 0)
    }

    @Test func singleLineNoTerminator() {
        let index = EditorLineIndex(text: "hello")
        #expect(index.lineCount == 1)
        #expect(index.lineStartOffsets == [0])
    }

    @Test func lfSeparatedLines() {
        let index = EditorLineIndex(text: "a\nb\nc")
        #expect(index.lineStartOffsets == [0, 2, 4])
        #expect(index.lineCount == 3)
    }

    @Test func crlfSeparatedLines() {
        let index = EditorLineIndex(text: "a\r\nb\r\nc")
        #expect(index.lineStartOffsets == [0, 3, 6])
    }

    @Test func bareCRSeparatedLines() {
        // Classic Mac OS 9 line endings: SourceMap does NOT handle this
        // (only `\n` starts a new line there); EditorLineIndex must.
        let index = EditorLineIndex(text: "a\rb\rc")
        #expect(index.lineStartOffsets == [0, 2, 4])
    }

    @Test func mixedLineEndings() {
        let index = EditorLineIndex(text: "a\nb\r\nc\rd")
        // "a" -> \n -> "b" -> \r\n -> "c" -> \r -> "d"
        #expect(index.lineStartOffsets == [0, 2, 5, 7])
    }

    @Test func trailingNewlineAddsEmptyFinalLine() {
        let index = EditorLineIndex(text: "a\nb\n")
        #expect(index.lineStartOffsets == [0, 2, 4])
        #expect(index.lineCount == 3)
    }

    @Test func consecutiveNewlinesProduceEmptyLine() {
        let index = EditorLineIndex(text: "a\n\nb")
        #expect(index.lineStartOffsets == [0, 2, 3])
    }

    // MARK: - line(atUTF16Offset:)

    @Test func lineAtOffsetBoundaries() {
        let index = EditorLineIndex(text: "aa\nbb\ncc")
        #expect(index.line(atUTF16Offset: 0) == 1)
        #expect(index.line(atUTF16Offset: 1) == 1)
        #expect(index.line(atUTF16Offset: 2) == 1) // the \n itself belongs to line 1
        #expect(index.line(atUTF16Offset: 3) == 2) // first char of line 2
        #expect(index.line(atUTF16Offset: 5) == 2)
        #expect(index.line(atUTF16Offset: 6) == 3)
        #expect(index.line(atUTF16Offset: 100) == 3) // past end clamps to last line
        #expect(index.line(atUTF16Offset: -5) == 1) // negative clamps to first line
    }

    // MARK: - utf16Range(ofLine:)

    @Test func utf16RangeExcludesTerminator() {
        let text = "aa\r\nbb\ncc" as NSString
        let index = EditorLineIndex(text: text)
        #expect(index.utf16Range(ofLine: 1, in: text) == NSRange(location: 0, length: 2))
        #expect(index.utf16Range(ofLine: 2, in: text) == NSRange(location: 4, length: 2))
        #expect(index.utf16Range(ofLine: 3, in: text) == NSRange(location: 7, length: 2))
        #expect(index.utf16Range(ofLine: 0, in: text) == NSRange(location: index.utf16Length, length: 0))
        #expect(index.utf16Range(ofLine: 4, in: text) == NSRange(location: index.utf16Length, length: 0))
    }

    @Test func utf16RangeExcludesBareCRTerminator() {
        let text = "aa\rbb" as NSString
        let index = EditorLineIndex(text: text)
        #expect(index.utf16Range(ofLine: 1, in: text) == NSRange(location: 0, length: 2))
    }

    // MARK: - column(atUTF16Offset:onLine:in:)

    @Test func columnCountsCharactersNotUTF16Units() {
        let text = "😀ab" as NSString // 😀 is 2 UTF-16 units, 1 character
        let index = EditorLineIndex(text: text)
        #expect(index.column(atUTF16Offset: 0, onLine: 1, in: text) == 1)
        #expect(index.column(atUTF16Offset: 2, onLine: 1, in: text) == 2) // right after the emoji
        #expect(index.column(atUTF16Offset: 3, onLine: 1, in: text) == 3)
    }

    // MARK: - Incremental `applying` vs. full rebuild equivalence (the load-bearing property)

    /// Applies an edit both incrementally and via full rebuild, and asserts
    /// the two agree — the property that actually matters, since a subtly
    /// wrong incremental update is far more dangerous than a slow one.
    private func assertIncrementalMatchesRebuild(
        original: String,
        editedRange: NSRange,
        replacement: String,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let oldText = original as NSString
        var incremental = EditorLineIndex(text: oldText)
        let newText = oldText.replacingCharacters(in: editedRange, with: replacement) as NSString
        incremental.applying(
            editedRange: editedRange,
            replacementUTF16Length: (replacement as NSString).length,
            newText: newText
        )
        let rebuilt = EditorLineIndex(text: newText)
        #expect(
            incremental == rebuilt,
            "original=\(original.debugDescription) edit=\(editedRange) replacement=\(replacement.debugDescription)",
            sourceLocation: sourceLocation
        )
    }

    @Test func incrementalAppendAtEnd() {
        assertIncrementalMatchesRebuild(
            original: "a\nb\nc",
            editedRange: NSRange(location: 5, length: 0),
            replacement: "\nd"
        )
    }

    @Test func incrementalInsertNewlineMidLine() {
        assertIncrementalMatchesRebuild(
            original: "abcdef",
            editedRange: NSRange(location: 3, length: 0),
            replacement: "\n"
        )
    }

    @Test func incrementalDeleteNewlineMergesLines() {
        assertIncrementalMatchesRebuild(
            original: "abc\ndef",
            editedRange: NSRange(location: 3, length: 1),
            replacement: ""
        )
    }

    @Test func incrementalReplaceSpanningMultipleLines() {
        assertIncrementalMatchesRebuild(
            original: "line1\nline2\nline3\nline4",
            editedRange: NSRange(location: 3, length: 10), // "e1\nline2\nl"
            replacement: "X"
        )
    }

    @Test func incrementalWholeDocumentReplace() {
        assertIncrementalMatchesRebuild(
            original: "a\nb\nc",
            editedRange: NSRange(location: 0, length: 5),
            replacement: "x\ny\nz\nw"
        )
    }

    @Test func incrementalInsertAtVeryStart() {
        assertIncrementalMatchesRebuild(
            original: "a\nb\nc",
            editedRange: NSRange(location: 0, length: 0),
            replacement: "z\n"
        )
    }

    @Test func incrementalCRLFStraddlingBoundary_insertedCRBeforeUntouchedLF() {
        // The adversarial case the "one extra margin line" design exists
        // for: the edit inserts a trailing \r immediately before untouched
        // content beginning with \n, forming a NEW CRLF pair that spans the
        // edit/tail boundary.
        assertIncrementalMatchesRebuild(
            original: "aaa\nbbb",
            editedRange: NSRange(location: 3, length: 0), // right before the existing \n
            replacement: "\r"
        )
    }

    @Test func incrementalCRLFStraddlingBoundaryWithUntouchedTailLines() {
        // Unlike `incrementalCRLFStraddlingBoundary_insertedCRBeforeUntouchedLF`
        // (only 2 lines, so the margin line IS the document's last line and
        // `hasOldTail` is false), this document has lines left over beyond
        // the margin line. That exercises the "rescanned.last == rescanEnd"
        // dedup branch, which only runs when `hasOldTail` is true.
        assertIncrementalMatchesRebuild(
            original: "aaa\nbbb\nccc\nddd",
            editedRange: NSRange(location: 3, length: 0), // right before the first \n
            replacement: "\r"
        )
    }

    @Test func incrementalNewlineAfterTrailingBareCRFormsCRLF() {
        // A document ending in a lone CR (its own complete terminator,
        // opening an empty final line) then gets a "\n" appended right
        // after it. The appended LF combines with the PRECEDING, already
        // fully-scanned CR into one CRLF pair — the mirror case of
        // `incrementalCRLFStraddlingBoundary_insertedCRBeforeUntouchedLF`,
        // caught only by the leading (not trailing) margin.
        assertIncrementalMatchesRebuild(
            original: "\r",
            editedRange: NSRange(location: 1, length: 0),
            replacement: "\n"
        )
    }

    @Test func incrementalCRLFStraddling_deletingLFLeavesLoneCR() {
        assertIncrementalMatchesRebuild(
            original: "aaa\r\nbbb\nccc",
            editedRange: NSRange(location: 4, length: 1), // delete the \n of \r\n, leaving a bare \r
            replacement: ""
        )
    }

    @Test func incrementalEditAtEmptyLineBoundary() {
        assertIncrementalMatchesRebuild(
            original: "a\n\nb",
            editedRange: NSRange(location: 2, length: 0),
            replacement: "x"
        )
    }

    @Test func incrementalDeleteEntireDocument() {
        assertIncrementalMatchesRebuild(
            original: "a\nb\nc",
            editedRange: NSRange(location: 0, length: 5),
            replacement: ""
        )
    }

    @Test func incrementalOnSingleLineDocument() {
        assertIncrementalMatchesRebuild(
            original: "hello",
            editedRange: NSRange(location: 2, length: 1),
            replacement: "XY"
        )
    }

    @Test func incrementalInsertLineAtVeryEndAfterTrailingNewline() {
        assertIncrementalMatchesRebuild(
            original: "a\nb\n",
            editedRange: NSRange(location: 4, length: 0),
            replacement: "c"
        )
    }

    @Test func incrementalCJKAndEmojiSurvivesLineSplit() {
        assertIncrementalMatchesRebuild(
            original: "日本語😀テスト",
            editedRange: NSRange(location: 4, length: 0),
            replacement: "\n"
        )
    }

    @Test func incrementalMultipleSequentialEdits() {
        var text = "one\ntwo\nthree" as NSString
        var index = EditorLineIndex(text: text)

        func edit(_ range: NSRange, _ replacement: String) {
            let newText = text.replacingCharacters(in: range, with: replacement) as NSString
            index.applying(
                editedRange: range,
                replacementUTF16Length: (replacement as NSString).length,
                newText: newText
            )
            text = newText
        }

        edit(NSRange(location: 3, length: 0), "\nnew")
        edit(NSRange(location: 0, length: 0), "start\n")
        edit(NSRange(location: index.utf16Length, length: 0), "\nend")

        #expect(index == EditorLineIndex(text: text))
    }

    // MARK: - Large-document incremental-vs-rebuild spot check

    @Test func incrementalOnLargeDocumentSingleKeystroke() {
        let lines = (0 ..< 5000).map { "line \($0) some representative text content" }
        let original = lines.joined(separator: "\n")
        // A single keystroke near the middle of a large document.
        let midpoint = (original as NSString).length / 2
        assertIncrementalMatchesRebuild(
            original: original,
            editedRange: NSRange(location: midpoint, length: 0),
            replacement: "X"
        )
    }
}
