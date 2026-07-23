import Foundation
@testable import MarkdownEngine
import Testing

struct SourceMapTests {
    @Test func emptyTextIsOneLine() {
        let map = SourceMap(text: "")

        #expect(map.lineCount == 1)
        #expect(map.lineStartOffsets == [0])
        #expect(map.utf16Length == 0)
    }

    @Test func singleLineNoNewline() {
        let map = SourceMap(text: "abc")

        #expect(map.lineCount == 1)
        #expect(map.lineStartOffsets == [0])
        #expect(map.utf16Length == 3)
        #expect(map.utf16Range(ofLines: 1 ... 1) == NSRange(location: 0, length: 3))
    }

    @Test func trailingNewlineCreatesFinalEmptyLine() {
        let map = SourceMap(text: "abc\n")

        #expect(map.lineCount == 2)
        #expect(map.lineStartOffsets == [0, 4])
        #expect(map.utf16Length == 4)
        #expect(map.utf16Range(ofLines: 1 ... 1) == NSRange(location: 0, length: 3))
        #expect(map.utf16Range(ofLines: 2 ... 2) == NSRange(location: 4, length: 0))
    }

    @Test func multipleLines() {
        let map = SourceMap(text: "one\ntwo\nthree")

        #expect(map.lineCount == 3)
        #expect(map.lineStartOffsets == [0, 4, 8])
        #expect(map.utf16Range(ofLines: 1 ... 1) == NSRange(location: 0, length: 3))
        #expect(map.utf16Range(ofLines: 2 ... 2) == NSRange(location: 4, length: 3))
        #expect(map.utf16Range(ofLines: 3 ... 3) == NSRange(location: 8, length: 5))
    }

    @Test func crlfHandledByUTF16Counting() {
        let map = SourceMap(text: "line1\r\nline2")

        #expect(map.lineCount == 2)
        #expect(map.lineStartOffsets == [0, 7])
        #expect(map.utf16Range(ofLines: 1 ... 1) == NSRange(location: 0, length: 6))
        #expect(map.utf16Range(ofLines: 2 ... 2) == NSRange(location: 7, length: 5))
    }

    @Test func emojiSurrogatePairsCountedCorrectly() {
        let text = "😀\n🎉"
        let map = SourceMap(text: text)

        #expect(map.lineCount == 2)
        #expect(map.lineStartOffsets == [0, 3])
        #expect(map.utf16Length == 5)
        #expect(map.utf16Range(ofLines: 1 ... 1) == NSRange(location: 0, length: 2))
        #expect(map.utf16Range(ofLines: 2 ... 2) == NSRange(location: 3, length: 2))
    }

    @Test func lineAtOffsetRoundTrips() {
        let map = SourceMap(text: "one\ntwo\nthree")

        #expect(map.line(atUTF16Offset: 0) == 1)
        #expect(map.line(atUTF16Offset: 2) == 1)
        #expect(map.line(atUTF16Offset: 3) == 1)
        #expect(map.line(atUTF16Offset: 4) == 2)
        #expect(map.line(atUTF16Offset: 7) == 2)
        #expect(map.line(atUTF16Offset: 8) == 3)
    }

    @Test func offsetsAtBoundariesReturnClampedLine() {
        let map = SourceMap(text: "ab\ncd")

        #expect(map.line(atUTF16Offset: -1) == 1)
        #expect(map.line(atUTF16Offset: 100) == 2)
    }

    @Test func utf16RangeClampsOutOfBoundsLines() {
        let map = SourceMap(text: "ab\ncd")

        #expect(map.utf16Range(ofLines: 0 ... 0) == NSRange(location: 0, length: 0))
        #expect(map.utf16Range(ofLines: 5 ... 10) == NSRange(location: 5, length: 0))
    }
}
