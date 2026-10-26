@testable import MacDown2
import Preview
import Testing

@Suite("PreviewDisplayCache")
struct PreviewDisplayCacheTests {
    @Test func sameRevisionAndBlocksReuseTheCachedSnapshot() {
        let block = PreviewBlock(kind: .paragraph, source: "plain", lineRange: 1 ... 1)
        var cache = PreviewDisplayCache()

        cache.update(revision: 7, blocks: [block])
        let firstOutput = cache.output
        cache.update(revision: 7, blocks: [block])

        #expect(cache.output == firstOutput)
        #expect(cache.revision == 7)
    }

    @Test func revisionChangeInvalidatesPreprocessedOutput() {
        let first = PreviewBlock(kind: .paragraph, source: "before", lineRange: 1 ... 1)
        let second = PreviewBlock(kind: .paragraph, source: "$\\frac{1}{$", lineRange: 1 ... 1)
        var cache = PreviewDisplayCache()

        cache.update(revision: 1, blocks: [first])
        cache.update(revision: 2, blocks: [second])

        #expect(cache.revision == 2)
        #expect(cache.input == [second])
        #expect(cache.output?.first?.source == MathPreviewPreprocessor.invalidMathMarker)
    }

    @Test func aNewCompositionAtTheSameRevisionAlsoInvalidates() {
        let first = PreviewBlock(kind: .paragraph, source: "first", lineRange: 1 ... 1)
        let second = PreviewBlock(kind: .paragraph, source: "second", lineRange: 1 ... 1)
        var cache = PreviewDisplayCache()

        cache.update(revision: 3, blocks: [first])
        cache.update(revision: 3, blocks: [second])

        #expect(cache.input == [second])
        #expect(cache.output == [second])
    }

    @Test func nilDisplayInvalidatesTheCache() {
        let block = PreviewBlock(kind: .paragraph, source: "body", lineRange: 1 ... 1)
        var cache = PreviewDisplayCache()
        cache.update(revision: 4, blocks: [block])
        cache.update(revision: 5, blocks: nil)

        #expect(cache.revision == nil)
        #expect(cache.input == nil)
        #expect(cache.output == nil)
    }
}
