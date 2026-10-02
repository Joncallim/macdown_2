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
        // A line's range stops before its WHOLE terminator (never between CR and LF).
        #expect(map.utf16Range(ofLines: 1 ... 1) == NSRange(location: 0, length: 5))
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

    // MARK: - #183 F07: CR / CRLF / mixed endings

    @Test func aLoneCarriageReturnEndsALine() {
        let map = SourceMap(text: "a\rbb\rccc")

        #expect(map.lineCount == 3)
        #expect(map.lineStartOffsets == [0, 2, 5])
        #expect(map.utf16Range(ofLines: 1 ... 1) == NSRange(location: 0, length: 1))
        #expect(map.utf16Range(ofLines: 2 ... 2) == NSRange(location: 2, length: 2))
        #expect(map.utf16Range(ofLines: 3 ... 3) == NSRange(location: 5, length: 3))
    }

    @Test func aCRLFPairIsOneTerminatorAndNeverSplit() {
        let text = "```d2\r\na -> b\r\n```\r\nafter"
        let map = SourceMap(text: text)

        #expect(map.lineCount == 4)
        let range = map.utf16Range(ofLines: 1 ... 3)
        #expect(Range(range, in: text) != nil, "the range must convert to a Swift Range")
        #expect((text as NSString).substring(with: range) == "```d2\r\na -> b\r\n```")
    }

    @Test func mixedEndingsAreEachOneTerminator() {
        let map = SourceMap(text: "a\nb\r\nc\rd")

        #expect(map.lineCount == 4)
        #expect(map.lineStartOffsets == [0, 2, 5, 7])
        #expect(map.utf16Range(ofLines: 2 ... 2) == NSRange(location: 2, length: 1))
    }

    @Test func aTrailingTerminatorLeavesAnEmptyLastLineAndNoTrailingTerminatorDoesNot() {
        #expect(SourceMap(text: "a\r\n").lineCount == 2)
        #expect(SourceMap(text: "a\r\n").utf16Range(ofLines: 2 ... 2) == NSRange(location: 3, length: 0))
        #expect(SourceMap(text: "a\rb").lineCount == 2)
        #expect(SourceMap(text: "a").lineCount == 1)
        #expect(SourceMap(text: "").lineCount == 1)
    }

    @Test func lineLookupFollowsCRAndCRLFStarts() {
        let map = SourceMap(text: "a\r\nb\rc")

        #expect(map.line(atUTF16Offset: 0) == 1)
        #expect(map.line(atUTF16Offset: 2) == 1) // the LF of a CRLF belongs to line 1
        #expect(map.line(atUTF16Offset: 3) == 2)
        #expect(map.line(atUTF16Offset: 5) == 3)
    }
}
