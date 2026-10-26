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
        #expect(chunks.allSatisfy { !$0.hasSuffix("\n") && !$0.hasSuffix("\r") })
        #expect(OversizeTextChunker.displayChunks("\n") == ["\u{200B}"])
    }
}
