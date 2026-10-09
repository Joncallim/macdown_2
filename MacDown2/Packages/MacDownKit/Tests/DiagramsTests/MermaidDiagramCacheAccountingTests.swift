@testable import Diagrams
import Foundation
import Testing

/// Two concurrent renders of one diagram both miss, then both store the same key. The byte total counted
/// the second store on top of the first, and the phantom bytes were never subtracted, so every later
/// store evicted everything and the cache stopped working.
private actor SlowRenderer: MermaidDiagramRendering {
    func render(_: MermaidFence, context _: MermaidRenderContext) async throws -> RenderedMermaidDiagram {
        try await Task.sleep(for: .milliseconds(50))
        return RenderedMermaidDiagram(
            svg: String(repeating: "x", count: 60),
            pngData: nil,
            naturalWidth: 10,
            naturalHeight: 10
        )
    }
}

struct MermaidDiagramCacheAccountingTests {
    @Test func concurrentRendersOfOneDiagramDoNotDoubleCountItsBytes() async throws {
        let context = MermaidRenderContext(
            foregroundRed: 0, foregroundGreen: 0, foregroundBlue: 0,
            backgroundRed: 1, backgroundGreen: 1, backgroundBlue: 1
        )
        let fence = MermaidFence(source: "graph TD", sourceRange: 0 ..< 8)
        // One 60-byte entry fits the 100-byte budget; two counted copies would not.
        let cache = MermaidDiagramCache(
            budget: .init(maxEntries: 8, maxAggregateSVGBytes: 100),
            renderer: SlowRenderer()
        )

        async let first = cache.render(fence, context: context)
        async let second = cache.render(fence, context: context)
        _ = try await (first, second)

        #expect(await cache.count == 1)
    }
}
