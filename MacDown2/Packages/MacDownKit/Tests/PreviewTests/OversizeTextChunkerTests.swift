import Foundation
@testable import Preview
import Testing

@Suite("OversizeTextChunker")
struct OversizeTextChunkerTests {
    @Test func emptySourceHasNoPhantomText() {
        #expect(OversizeTextChunker.chunks("").isEmpty)
    }

    @Test func preservesNewlineBoundariesWhenTheyFit() {
        let source = String(repeating: "line\n", count: 200) + "tail"
        let chunks = OversizeTextChunker.chunks(source, maxUTF16Length: 32)

        #expect(chunks.joined() == source)
        #expect(chunks.dropLast().allSatisfy { $0.hasSuffix("\n") })
        #expect(chunks.allSatisfy { $0.utf16.count <= 32 })
    }

    @Test(arguments: ["\n", "\r\n", "\r"])
    func preservesAllLineEndingForms(_ lineEnding: String) {
        let source = String(repeating: "alpha\(lineEnding)", count: 80) + "omega"
        let chunks = OversizeTextChunker.chunks(source, maxUTF16Length: 24)

        #expect(chunks.joined() == source)
        #expect(chunks.allSatisfy { $0.utf16.count <= 24 })
        // A CRLF must remain one grapheme cluster and therefore cannot be
        // separated across two fallback Text views.
        if lineEnding == "\r\n" {
            #expect(chunks.dropLast().allSatisfy { !$0.hasSuffix("\r") })
        }
    }

    @Test func splitsAPathologicalLongLineOnlyAtGraphemeBoundaries() {
        let source = String(repeating: "🙂é界", count: 20000)
        let chunks = OversizeTextChunker.chunks(source, maxUTF16Length: 257)

        #expect(chunks.count > 1)
        #expect(chunks.joined() == source)
        #expect(chunks.allSatisfy { $0.utf16.count <= 257 })
        #expect(chunks.allSatisfy { !$0.hasSuffix("\u{301}") })
    }

    @Test(arguments: [64, 128, 256, 512])
    func boundsThe64Through512KiBLadder(_ kibibytes: Int) {
        let source = String(repeating: "0123456789abcdef\n", count: (kibibytes * 1024) / 17 + 1)
        let chunks = OversizeTextChunker.chunks(source, maxUTF16Length: 16 * 1024)

        #expect(source.utf8.count >= kibibytes * 1024)
        #expect(chunks.count > 1)
        #expect(chunks.joined() == source)
        #expect(chunks.allSatisfy { $0.utf16.count <= 16 * 1024 })
    }

    @Test func displayChunksDoNotAddBoundaryLineBreaks() {
        let source = String(repeating: "line\n", count: 80) + "tail"
        let chunks = OversizeTextChunker.displayChunks(source, maxUTF16Length: 24)

        #expect(chunks.count > 1)
        #expect(chunks.dropLast().allSatisfy { !$0.hasSuffix("\n") && !$0.hasSuffix("\r") })
    }

    @Test(arguments: ["\n", "\r\n", "\r"])
    func removesOnlyTheBoundaryLineEnding(_ ending: String) {
        let source = "ab\(ending)cd\(ending)"
        let limit = 2 + ending.utf16.count

        #expect(OversizeTextChunker.displayChunks(source, maxUTF16Length: limit) == ["ab", "cd\(ending)"])
        #expect(Array(OversizeTextChunker.chunks(source, maxUTF16Length: limit).joined().utf8) == Array(source.utf8))
    }

    @Test(arguments: ["\n", "\r\n", "\r"])
    func preservesUnicodeImmediatelyBeforeTheBoundary(_ ending: String) {
        let source = "e\u{301}\(ending)🙂\(ending)"
        let display = OversizeTextChunker.displayChunks(source, maxUTF16Length: 2 + ending.utf16.count)

        #expect(display == ["e\u{301}", "🙂\(ending)"])
        #expect(Array(display[0].utf8) == Array("e\u{301}".utf8))
    }

    @Test(arguments: ["\n", "\r\n", "\r"])
    func preservesBlankLinesAndTheFinalChunk(_ ending: String) {
        #expect(OversizeTextChunker.displayChunks("\(ending)\(ending)tail", maxUTF16Length: 4) == [ending, "tail"])
        #expect(OversizeTextChunker.displayChunks("\(ending)last", maxUTF16Length: 4) == ["\u{200B}", "last"])
        #expect(OversizeTextChunker.displayChunks("last\(ending)") == ["last\(ending)"])
        #expect(OversizeTextChunker.displayChunks(ending) == [ending])
        #expect(OversizeTextChunker.displayChunks("tail") == ["tail"])
        #expect(OversizeTextChunker.displayChunks("").isEmpty)
    }

    @Test func anIndivisibleOversizedGraphemeHasAnExplicitBoundedDisplayFallback() {
        let grapheme = "a" + String(repeating: "\u{301}", count: 40000)
        let source = "prefix\n" + grapheme + "\nsuffix"
        let display = OversizeTextChunker.displayChunks(source)

        #expect(grapheme.count == 1)
        #expect(display.allSatisfy { $0.utf16.count <= OversizeTextChunker.defaultMaxUTF16Length })
        #expect(display.contains("[Preview omitted one oversized grapheme]"))
        #expect(!display.contains { $0.contains("\u{301}") })
        #expect(Array(OversizeTextChunker.chunks(source).joined().utf8) == Array(source.utf8))
        let tinyDisplay = OversizeTextChunker.displayChunks(grapheme, maxUTF16Length: 7)
        #expect(tinyDisplay.allSatisfy { $0.utf16.count <= 7 })
        #expect(tinyDisplay.joined() == "[Preview omitted one oversized grapheme]")
    }
}
