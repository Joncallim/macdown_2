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
            pngData: Data(repeating: 0, count: 20),
            naturalWidth: 10,
            naturalHeight: 10
        )
    }
}

private actor PNGCountingRenderer: MermaidDiagramRendering {
    private(set) var callCount = 0

    func render(_: MermaidFence, context _: MermaidRenderContext) -> RenderedMermaidDiagram {
        callCount += 1
        return RenderedMermaidDiagram(
            svg: "<svg/>", pngData: Data(repeating: 0, count: 80),
            naturalWidth: 10, naturalHeight: 10
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
        // One 60-byte SVG + 20-byte PNG fits; two counted copies would not.
        let cache = MermaidDiagramCache(
            budget: .init(maxEntries: 8, maxAggregateSVGBytes: 100),
            renderer: SlowRenderer()
        )

        async let first = cache.render(fence, context: context)
        async let second = cache.render(fence, context: context)
        _ = try await (first, second)

        #expect(await cache.count == 1)
    }

    @Test func retainedPNGBytesDriveEvictionEvenWhenSVGIsTiny() async throws {
        let context = MermaidRenderContext(
            foregroundRed: 0, foregroundGreen: 0, foregroundBlue: 0,
            backgroundRed: 1, backgroundGreen: 1, backgroundBlue: 1
        )
        let renderer = PNGCountingRenderer()
        let cache = MermaidDiagramCache(
            budget: .init(maxEntries: 8, maxAggregateSVGBytes: 100), renderer: renderer
        )
        let first = MermaidFence(source: "one", sourceRange: 0 ..< 3)
        let second = MermaidFence(source: "two", sourceRange: 0 ..< 3)
        _ = try await cache.render(first, context: context)
        _ = try await cache.render(second, context: context)
        #expect(await cache.count == 1)
        _ = try await cache.render(first, context: context)
        #expect(await renderer.callCount == 3)
    }
}
