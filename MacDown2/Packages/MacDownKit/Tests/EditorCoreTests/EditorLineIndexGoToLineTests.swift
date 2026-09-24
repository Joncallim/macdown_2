@testable import EditorCore
import Foundation
import Testing

/// EPIC-22 Slice 2b — `EditorLineIndex.utf16Offset(forLine:column:in:)`, the
/// inverse of `column(atUTF16Offset:onLine:in:)`, powering Go to Line/Column.
/// Split out of `EditorLineIndexTests.swift` to stay under SwiftLint's
/// `type_body_length` budget, matching this codebase's established pattern
/// for growing a heavily-tested type's test suite across multiple files.
@Suite("EditorLineIndex.utf16Offset(forLine:column:in:)")
struct EditorLineIndexGoToLineTests {
    @Test func roundTripsWithColumn() {
        let text = "aa\nbb\ncc" as NSString
        let index = EditorLineIndex(text: text)
        for offset in [0, 1, 3, 4, 6, 7] {
            let line = index.line(atUTF16Offset: offset)
            let column = index.column(atUTF16Offset: offset, onLine: line, in: text)
            #expect(
                index.utf16Offset(forLine: line, column: column, in: text) == offset,
                "line=\(line) column=\(column) expected offset=\(offset)"
            )
        }
    }

    @Test func countsCharactersNotUTF16Units() {
        let text = "😀ab" as NSString // 😀 is 2 UTF-16 units, 1 character
        let index = EditorLineIndex(text: text)
        #expect(index.utf16Offset(forLine: 1, column: 1, in: text) == 0)
        #expect(index.utf16Offset(forLine: 1, column: 2, in: text) == 2) // right after the emoji
        #expect(index.utf16Offset(forLine: 1, column: 3, in: text) == 3)
    }

    @Test func onSecondLine() {
        let text = "aa\nbbb\ncc" as NSString
        let index = EditorLineIndex(text: text)
        #expect(index.utf16Offset(forLine: 2, column: 1, in: text) == 3) // "bbb"'s own start
        #expect(index.utf16Offset(forLine: 2, column: 3, in: text) == 5)
    }

    @Test func clampsLineBelowRange() {
        let text = "aa\nbb\ncc" as NSString
        let index = EditorLineIndex(text: text)
        #expect(index.utf16Offset(forLine: 0, column: 1, in: text) == index.utf16Offset(
            forLine: 1,
            column: 1,
            in: text
        ))
        #expect(index.utf16Offset(forLine: -5, column: 1, in: text) == 0)
    }

    @Test func clampsLineBeyondRange() {
        let text = "aa\nbb\ncc" as NSString
        let index = EditorLineIndex(text: text)
        let lastLineStart = index.utf16Offset(forLine: 3, column: 1, in: text)
        #expect(index.utf16Offset(forLine: 100, column: 1, in: text) == lastLineStart)
    }

    @Test func clampsColumnBelowRangeToLineStart() {
        let text = "aa\nbb\ncc" as NSString
        let index = EditorLineIndex(text: text)
        #expect(index.utf16Offset(forLine: 2, column: 0, in: text) == 3)
        #expect(index.utf16Offset(forLine: 2, column: -5, in: text) == 3)
    }

    @Test func clampsColumnBeyondLineLengthToLineEndNeverIntoTerminator() {
        let text = "aa\r\nbb\ncc" as NSString
        let index = EditorLineIndex(text: text)
        // Line 1 is "aa" (2 characters); asking for column 50 must land at
        // its end (offset 2), never advance into the \r\n terminator or
        // beyond into line 2.
        #expect(index.utf16Offset(forLine: 1, column: 50, in: text) == 2)
    }

    @Test func handlesBareCRTerminatorWithoutConsumingIt() {
        let text = "aa\rbb" as NSString
        let index = EditorLineIndex(text: text)
        #expect(index.utf16Offset(forLine: 1, column: 50, in: text) == 2)
        #expect(index.utf16Offset(forLine: 2, column: 1, in: text) == 3)
    }
}
